import os
from datetime import timedelta
import logging
import json as _json
from typing import List, Optional

import requests

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from livekit import api
from pydantic import BaseModel, Field

try:
    from mem0 import MemoryClient
except Exception:  # pragma: no cover - optional runtime dependency
    MemoryClient = None  # type: ignore[assignment]

load_dotenv()
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

LIVEKIT_API_KEY = os.getenv("LIVEKIT_API_KEY")
LIVEKIT_API_SECRET = os.getenv("LIVEKIT_API_SECRET")
AGENT_NAME = os.getenv("LIVEKIT_AGENT_NAME", "lex")
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")
GOOGLE_CHAT_MODEL = os.getenv("GOOGLE_CHAT_MODEL", "gemini-2.5-flash").strip()
GOOGLE_CHAT_FALLBACK_MODELS = [
    model.strip()
    for model in os.getenv(
        "GOOGLE_CHAT_FALLBACK_MODELS",
        "gemini-2.5-flash-lite,gemini-2.0-flash,gemini-2.0-flash-lite",
    ).split(",")
    if model.strip()
]
GOOGLE_CHAT_DEFAULT_MAX_OUTPUT_TOKENS = int(
    os.getenv("GOOGLE_CHAT_DEFAULT_MAX_OUTPUT_TOKENS", "4096")
)
GOOGLE_CHAT_MAX_OUTPUT_TOKENS = int(
    os.getenv("GOOGLE_CHAT_MAX_OUTPUT_TOKENS", "8192")
)
GOOGLE_CHAT_MAX_HISTORY_MESSAGES = int(
    os.getenv("GOOGLE_CHAT_MAX_HISTORY_MESSAGES", "12")
)
GOOGLE_CHAT_MAX_HISTORY_CHARS = int(
    os.getenv("GOOGLE_CHAT_MAX_HISTORY_CHARS", "12000")
)
MEM0_API_KEY = os.getenv("MEM0_API_KEY", "").strip()

if not LIVEKIT_API_KEY or not LIVEKIT_API_SECRET:
    raise RuntimeError("LIVEKIT_API_KEY and LIVEKIT_API_SECRET must be set")


class TokenRequest(BaseModel):
    room: str = Field(..., min_length=1, max_length=64)
    identity: str = Field(..., min_length=1, max_length=64)
    name: str | None = Field(default=None, max_length=64)


class VisionAnalyzeRequest(BaseModel):
    image_base64: str = Field(..., min_length=64)
    prompt: str | None = Field(default=None, max_length=1200)


class ChatMessage(BaseModel):
    role: str = Field(..., pattern=r"^(user|assistant|model)$")
    content: str


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1)
    history: List[ChatMessage] = Field(default_factory=list)
    memory_user_id: Optional[str] = Field(default=None, max_length=128)
    memory_user_name: Optional[str] = Field(default=None, max_length=120)


app = FastAPI(title="Lex LiveKit Token Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


_SERVER_START_TIME: float = 0.0


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/network/info")
def network_info() -> dict[str, object]:
    """Diagnostic endpoint — useful for verifying connectivity from the app."""
    import time

    port = int(os.getenv("TOKEN_SERVER_PORT", "8080"))
    host = os.getenv("TOKEN_SERVER_HOST", "0.0.0.0")
    livekit_url = os.getenv("LIVEKIT_URL", "(not set)")
    uptime = round(time.time() - _SERVER_START_TIME, 1) if _SERVER_START_TIME else 0
    return {
        "status": "ok",
        "host": host,
        "port": port,
        "livekit_url": livekit_url,
        "agent_name": AGENT_NAME,
        "uptime_seconds": uptime,
        "standard_port": 8080,
        "protocol": "http",
    }


@app.get("/debug/room/{room_name}")
async def debug_room(room_name: str) -> dict[str, object]:
    lkapi = api.LiveKitAPI()
    try:
        rooms = await lkapi.room.list_rooms(api.ListRoomsRequest(names=[room_name]))
        dispatches = await lkapi.agent_dispatch.list_dispatch(room_name)
        return {
            "room_exists": len(rooms.rooms) > 0,
            "dispatches": [
                {"id": d.id, "agent_name": d.agent_name, "room": d.room}
                for d in dispatches
            ],
            "expected_agent": AGENT_NAME,
        }
    finally:
        await lkapi.aclose()


@app.post("/vision/analyze")
async def analyze_vision(payload: VisionAnalyzeRequest) -> dict[str, str]:
    if not GOOGLE_API_KEY:
        raise HTTPException(status_code=500, detail="GOOGLE_API_KEY not configured")

    instruction = payload.prompt or (
        "Identify the main object in this image. Respond briefly with:\n"
        "1) Object name\n"
        "2) Short description\n"
        "3) Common use\n"
        "4) Include Indian context if relevant\n"
        "If object looks like food, mention basic info.\n"
        "If electronic device, describe core function.\n"
        "If plant, mention likely species/use.\n"
        "If medicine/medical item, advise checking label and consulting a doctor.\n"
        "Do not provide dangerous or overconfident medical advice.\n"
        "If uncertain, clearly say you are not fully certain."
    )

    url = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        "gemini-2.0-flash:generateContent"
        f"?key={GOOGLE_API_KEY}"
    )
    body = {
        "contents": [
            {
                "parts": [
                    {"text": instruction},
                    {
                        "inline_data": {
                            "mime_type": "image/jpeg",
                            "data": payload.image_base64,
                        }
                    },
                ]
            }
        ],
        "generationConfig": {
            "temperature": 0.2,
            "maxOutputTokens": 260,
        },
    }

    try:
        resp = requests.post(url, json=body, timeout=35)
        if resp.status_code != 200:
            raise HTTPException(
                status_code=500,
                detail=f"vision_api_failed: {resp.status_code} {resp.text}",
            )

        data = resp.json()
        candidates = data.get("candidates", [])
        if not candidates:
            raise HTTPException(status_code=500, detail="vision_api_empty_candidates")

        parts = candidates[0].get("content", {}).get("parts", [])
        text = "\n".join(p.get("text", "").strip() for p in parts if p.get("text", "").strip())
        if not text:
            text = "I could not extract enough details from the image."

        return {"result": text}
    except HTTPException:
        raise
    except Exception as exc:
        logging.exception("Vision analyze failed")
        raise HTTPException(status_code=500, detail=f"vision_analyze_failed: {exc}")


@app.post("/token")
async def create_token(payload: TokenRequest) -> dict[str, str]:
    try:
        logging.info("Token requested: room=%s identity=%s", payload.room, payload.identity)
        # Ensure room exists before agent dispatch calls (LiveKit returns 404 otherwise).
        lkapi = api.LiveKitAPI()
        try:
            rooms = await lkapi.room.list_rooms(api.ListRoomsRequest(names=[payload.room]))
            if len(rooms.rooms) == 0:
                await lkapi.room.create_room(api.CreateRoomRequest(name=payload.room))
                logging.info("Created room=%s", payload.room)
            else:
                logging.info("Room already exists: %s", payload.room)

            # Explicitly dispatch agent to this room (required for worker -> room binding).
            existing = await lkapi.agent_dispatch.list_dispatch(payload.room)
            for dispatch in existing:
                try:
                    await lkapi.agent_dispatch.delete_dispatch(dispatch.id, payload.room)
                    logging.info(
                        "Removed previous dispatch id=%s room=%s agent_name=%s",
                        dispatch.id,
                        payload.room,
                        dispatch.agent_name,
                    )
                except Exception:
                    logging.exception(
                        "Failed removing dispatch id=%s room=%s",
                        dispatch.id,
                        payload.room,
                    )

            await lkapi.agent_dispatch.create_dispatch(
                api.CreateAgentDispatchRequest(
                    agent_name=AGENT_NAME,
                    room=payload.room,
                    metadata=payload.identity,
                )
            )
            logging.info("Created fresh dispatch for room=%s agent=%s", payload.room, AGENT_NAME)
        finally:
            await lkapi.aclose()

        token = (
            api.AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
            .with_identity(payload.identity)
            .with_name(payload.name or payload.identity)
            .with_grants(
                api.VideoGrants(
                    room_join=True,
                    room=payload.room,
                    can_publish=True,
                    can_subscribe=True,
                )
            )
            .with_ttl(timedelta(hours=6))
            .to_jwt()
        )
        logging.info("Token generated for identity=%s room=%s", payload.identity, payload.room)
        return {"token": token}
    except Exception as exc:
        logging.exception("Token generation failed")
        raise HTTPException(status_code=500, detail=f"token_generation_failed: {exc}")


# ─────────────────────────────────────────────────────────────────────────────
# Chat (text-to-text) — Gemini streaming endpoint
# ─────────────────────────────────────────────────────────────────────────────

_CHAT_SYSTEM_PROMPT = (
    "You are LEX, an intelligent AI personal assistant designed for Indian users. "
    "Be professional, friendly, and helpful. Use Indian context when relevant "
    "(IST, INR, Celsius, kilometers). Maintain conversation context and give "
    "clear, well-structured answers. "
    "If you greet the user, say 'Vanakkam' instead of 'Namaste'. "
    "Answer the user's request directly instead of asking unnecessary follow-up "
    "questions when a reasonable answer can already be given. "
    "If the user asks for code, provide complete runnable code with a short "
    "explanation and example output or usage when helpful. "
    "If the user asks for a story, essay, long explanation, tutorial, notes, or "
    "detailed answer, provide a full response with enough depth instead of a short summary. "
    "The Lex app can create reminders and alarms locally. If the user asks for a reminder, "
    "do not say you are unable to schedule notifications; acknowledge the reminder request naturally. "
    "When formatting improves readability, use clean markdown with short headings, "
    "bullet lists, bold or italic emphasis, blockquotes, and fenced code blocks. "
    "For simple questions, reply concisely. "
    "Never cut off mid-sentence. Always finish the complete response."
)

_CODE_REQUEST_HINTS = (
    "code",
    "program",
    "script",
    "function",
    "class",
    "algorithm",
    "python",
    "java",
    "javascript",
    "typescript",
    "dart",
    "flutter",
    "c++",
    "html",
    "css",
    "sql",
    "api",
)
_LONG_FORM_HINTS = (
    "long",
    "detailed",
    "detail",
    "explain",
    "story",
    "essay",
    "article",
    "tutorial",
    "notes",
    "step by step",
    "full",
    "complete",
    "write",
    "generate",
)
_CREATIVE_REQUEST_HINTS = (
    "story",
    "poem",
    "essay",
    "article",
    "speech",
    "letter",
    "creative",
)

_mem0_client: Optional["MemoryClient"] = None


def _get_mem0_client() -> Optional["MemoryClient"]:
    global _mem0_client

    if _mem0_client is not None:
        return _mem0_client
    if MemoryClient is None or not MEM0_API_KEY:
        return None

    try:
        _mem0_client = MemoryClient(api_key=MEM0_API_KEY)
    except TypeError:
        _mem0_client = MemoryClient()
    except Exception:
        logging.exception("Could not initialize Mem0 client for chat")
        return None

    return _mem0_client


def _normalize_memory_user_id(payload: ChatRequest) -> Optional[str]:
    candidate = (
        payload.memory_user_id
        or payload.memory_user_name
        or os.getenv("MEMORY_USER_ID", "")
    ).strip()
    if not candidate:
        return None
    return candidate[:128]


def _load_chat_memory_context(
    payload: ChatRequest,
    *,
    limit: int = 5,
) -> str:
    user_id = _normalize_memory_user_id(payload)
    if not user_id:
        return ""

    client = _get_mem0_client()
    if client is None:
        return ""

    try:
        results = client.search(payload.message, user_id=user_id, limit=limit)
    except Exception:
        logging.exception("Chat Mem0 search failed for user=%s", user_id)
        return ""

    if isinstance(results, dict):
        results = results.get("results", [])
    if not results:
        return ""

    memories: List[str] = []
    for result in results:
        memory = str(result.get("memory", "")).strip()
        if memory:
            memories.append(f"- {memory}")

    if not memories:
        return ""

    logging.info("Loaded %s Mem0 memories for chat user=%s", len(memories), user_id)
    return "\n".join(memories[:limit])


def _build_chat_system_prompt(payload: ChatRequest, memory_context: str) -> str:
    prompt = _CHAT_SYSTEM_PROMPT

    if payload.memory_user_name:
        prompt += f"\nThe user's display name is {payload.memory_user_name.strip()}."

    if memory_context:
        prompt += (
            "\nRelevant long-term memory for this user:\n"
            f"{memory_context}\n"
            "Use these memories only when relevant and do not mention memory storage unless asked."
        )

    return prompt


def _save_chat_exchange_to_mem0(
    payload: ChatRequest,
    assistant_reply: str,
) -> None:
    user_id = _normalize_memory_user_id(payload)
    reply = assistant_reply.strip()
    message = payload.message.strip()
    if not user_id or not message or not reply:
        return

    client = _get_mem0_client()
    if client is None:
        return

    messages = []
    if payload.memory_user_name:
        messages.append(
            {
                "role": "system",
                "content": f"User display name: {payload.memory_user_name.strip()}",
            }
        )
    messages.extend(
        [
            {"role": "user", "content": message},
            {"role": "assistant", "content": reply},
        ]
    )

    try:
        client.add(messages, user_id=user_id)
        logging.info("Saved chat exchange to Mem0 for user=%s", user_id)
    except Exception:
        logging.exception("Chat Mem0 save failed for user=%s", user_id)


def _build_gemini_contents(history: List[ChatMessage], new_message: str) -> list:
    """Convert chat history + new message into Gemini API contents format."""
    contents = []
    for msg in history:
        role = "model" if msg.role in ("assistant", "model") else "user"
        contents.append({"role": role, "parts": [{"text": msg.content}]})
    contents.append({"role": "user", "parts": [{"text": new_message}]})
    return contents


def _chat_model_candidates() -> List[str]:
    seen: set[str] = set()
    candidates: List[str] = []
    for model in [GOOGLE_CHAT_MODEL, *GOOGLE_CHAT_FALLBACK_MODELS]:
        if model and model not in seen:
            seen.add(model)
            candidates.append(model)
    return candidates


def _trim_chat_history(history: List[ChatMessage]) -> List[ChatMessage]:
    trimmed: List[ChatMessage] = []
    total_chars = 0

    for msg in reversed(history):
        content = msg.content.strip()
        if not content:
            continue
        if len(trimmed) >= GOOGLE_CHAT_MAX_HISTORY_MESSAGES:
            break
        if trimmed and total_chars + len(content) > GOOGLE_CHAT_MAX_HISTORY_CHARS:
            break
        trimmed.append(ChatMessage(role=msg.role, content=content))
        total_chars += len(content)

    trimmed.reverse()
    return trimmed


def _chat_generation_config(message: str) -> dict[str, float | int]:
    lower = message.lower()
    wants_code = any(hint in lower for hint in _CODE_REQUEST_HINTS)
    wants_long = (
        wants_code
        or len(message) >= 120
        or any(hint in lower for hint in _LONG_FORM_HINTS)
    )
    wants_creative = any(hint in lower for hint in _CREATIVE_REQUEST_HINTS)

    if wants_code:
        temperature = 0.35
    elif wants_creative:
        temperature = 0.85
    elif wants_long:
        temperature = 0.7
    else:
        temperature = 0.55

    max_output_tokens = (
        GOOGLE_CHAT_MAX_OUTPUT_TOKENS
        if wants_long
        else GOOGLE_CHAT_DEFAULT_MAX_OUTPUT_TOKENS
    )

    return {
        "temperature": temperature,
        "maxOutputTokens": max_output_tokens,
    }


def _extract_gemini_text(payload: dict) -> str:
    text_parts: List[str] = []
    for candidate in payload.get("candidates", []):
        for part in candidate.get("content", {}).get("parts", []):
            text = part.get("text")
            if text:
                text_parts.append(text)
    return "".join(text_parts).strip()


def _extract_gemini_error_text(raw_text: str) -> str:
    if not raw_text:
        return ""

    try:
        payload = _json.loads(raw_text)
    except _json.JSONDecodeError:
        return raw_text

    error = payload.get("error")
    if isinstance(error, dict):
        message = error.get("message")
        status = error.get("status")
        if message and status:
            return f"{status}: {message}"
        if message:
            return str(message)
    return raw_text


def _should_try_next_chat_model(status_code: Optional[int], error_text: str) -> bool:
    lower = error_text.lower()
    return bool(
        status_code == 404
        or status_code == 429
        or (status_code is not None and status_code >= 500)
        or "quota" in lower
        or "rate" in lower
        or "resource_exhausted" in lower
        or "deadline_exceeded" in lower
        or "unavailable" in lower
        or "not found" in lower
        or "unsupported" in lower
        or "not supported" in lower
    )


def _iter_sse_text_events(text: str, chunk_size: int = 320):
    for index in range(0, len(text), chunk_size):
        yield f"data: {_json.dumps({'text': text[index:index + chunk_size]})}\n\n"


def _friendly_chat_error(status_code: Optional[int], error_text: str) -> str:
    lower = error_text.lower()
    if status_code in (401, 403) or "authentication" in lower or "api key" in lower:
        return "Authentication error. Please check the Gemini API configuration."
    if (
        status_code == 429
        or "quota" in lower
        or "rate" in lower
        or "resource_exhausted" in lower
    ):
        return "Lex is currently busy. Please wait a moment and try again."
    if (
        (status_code and status_code >= 500)
        or "deadline_exceeded" in lower
        or "unavailable" in lower
    ):
        return "Server error. Please try again later."
    if "timeout" in lower or "timed out" in lower:
        return "Request timed out. Please try again."
    if "not found" in lower or "unsupported" in lower or "not supported" in lower:
        return "The configured Gemini chat model is unavailable. Please try again."
    return "Something went wrong. Please try again."


@app.post("/chat/stream")
async def chat_stream(payload: ChatRequest):
    """Stream a Gemini text response via SSE."""
    if not GOOGLE_API_KEY:
        raise HTTPException(status_code=500, detail="GOOGLE_API_KEY not configured")

    trimmed_history = _trim_chat_history(payload.history)
    memory_context = _load_chat_memory_context(payload)
    body = {
        "system_instruction": {
            "parts": [{"text": _build_chat_system_prompt(payload, memory_context)}]
        },
        "contents": _build_gemini_contents(trimmed_history, payload.message),
        "generationConfig": _chat_generation_config(payload.message),
    }

    def _event_generator():
        last_status_code: Optional[int] = None
        last_error_text = ""

        try:
            for model in _chat_model_candidates():
                url = (
                    "https://generativelanguage.googleapis.com/v1beta/models/"
                    f"{model}:streamGenerateContent"
                    f"?alt=sse&key={GOOGLE_API_KEY}"
                )

                try:
                    with requests.post(url, json=body, stream=True, timeout=60) as resp:
                        if resp.status_code != 200:
                            error_text = _extract_gemini_error_text(resp.text[:1000])
                            last_status_code = resp.status_code
                            last_error_text = error_text
                            logging.error(
                                "Gemini chat API error model=%s status=%s: %s",
                                model,
                                resp.status_code,
                                error_text,
                            )

                            if _should_try_next_chat_model(resp.status_code, error_text):
                                continue

                            friendly = _friendly_chat_error(resp.status_code, error_text)
                            yield f"data: {_json.dumps({'error': friendly})}\n\n"
                            return

                        streamed_any_text = False
                        collected_text_parts: List[str] = []
                        for line in resp.iter_lines(decode_unicode=True):
                            if not line or not line.startswith("data: "):
                                continue

                            raw = line[6:]
                            if raw == "[DONE]":
                                continue

                            try:
                                chunk = _json.loads(raw)
                            except _json.JSONDecodeError:
                                continue

                            candidates = chunk.get("candidates", [])
                            if not candidates:
                                continue

                            parts = candidates[0].get("content", {}).get("parts", [])
                            for part in parts:
                                text = part.get("text", "")
                                if text:
                                    streamed_any_text = True
                                    collected_text_parts.append(text)
                                    yield f"data: {_json.dumps({'text': text})}\n\n"

                    if streamed_any_text:
                        _save_chat_exchange_to_mem0(
                            payload,
                            "".join(collected_text_parts).strip(),
                        )
                        yield "data: [DONE]\n\n"
                        return

                    last_status_code = None
                    last_error_text = "empty response from Gemini stream"
                    logging.warning("Gemini chat stream returned no text for model=%s", model)
                except requests.Timeout as exc:
                    last_status_code = None
                    last_error_text = str(exc)
                    logging.warning("Gemini chat timeout for model=%s: %s", model, exc)
                    continue
                except requests.RequestException as exc:
                    last_status_code = None
                    last_error_text = str(exc)
                    logging.warning("Gemini chat request error for model=%s: %s", model, exc)
                    continue

            for model in _chat_model_candidates():
                url = (
                    "https://generativelanguage.googleapis.com/v1beta/models/"
                    f"{model}:generateContent"
                    f"?key={GOOGLE_API_KEY}"
                )

                try:
                    resp = requests.post(url, json=body, timeout=90)
                    if resp.status_code != 200:
                        error_text = _extract_gemini_error_text(resp.text[:1000])
                        last_status_code = resp.status_code
                        last_error_text = error_text
                        logging.error(
                            "Gemini fallback API error model=%s status=%s: %s",
                            model,
                            resp.status_code,
                            error_text,
                        )
                        if _should_try_next_chat_model(resp.status_code, error_text):
                            continue

                        friendly = _friendly_chat_error(resp.status_code, error_text)
                        yield f"data: {_json.dumps({'error': friendly})}\n\n"
                        return

                    payload_json = resp.json()
                    text = _extract_gemini_text(payload_json)
                    if not text:
                        last_status_code = None
                        last_error_text = "empty response from Gemini fallback"
                        logging.warning(
                            "Gemini fallback returned no text for model=%s", model
                        )
                        continue

                    _save_chat_exchange_to_mem0(payload, text)
                    yield from _iter_sse_text_events(text)
                    yield "data: [DONE]\n\n"
                    return
                except requests.Timeout as exc:
                    last_status_code = None
                    last_error_text = str(exc)
                    logging.warning("Gemini fallback timeout for model=%s: %s", model, exc)
                    continue
                except requests.RequestException as exc:
                    last_status_code = None
                    last_error_text = str(exc)
                    logging.warning(
                        "Gemini fallback request error for model=%s: %s", model, exc
                    )
                    continue

            friendly = _friendly_chat_error(last_status_code, last_error_text)
            yield f"data: {_json.dumps({'error': friendly})}\n\n"
        except Exception as exc:
            logging.exception("Chat stream failed")
            friendly = _friendly_chat_error(None, str(exc))
            yield f"data: {_json.dumps({'error': friendly})}\n\n"

    return StreamingResponse(
        _event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


# ─────────────────────────────────────────────────────────────────────────────
# Standardised server startup
# ─────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import time
    import uvicorn

    _SERVER_START_TIME = time.time()

    port = int(os.getenv("TOKEN_SERVER_PORT", "8080"))
    host = os.getenv("TOKEN_SERVER_HOST", "0.0.0.0")

    logging.info(
        "Starting Lex token server on %s:%s (standard port: 8080)", host, port
    )
    uvicorn.run(
        "token_server:app",
        host=host,
        port=port,
        reload=True,
    )

