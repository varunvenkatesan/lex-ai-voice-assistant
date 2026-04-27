from dotenv import load_dotenv
import json
import logging
import os
import asyncio
from typing import Any, Optional, Tuple

from livekit import agents
from livekit.agents import AgentSession, Agent, RoomInputOptions, ChatContext
from livekit.plugins import noise_cancellation, google, silero

from prompt import AGENT_INSTRUCTION, SESSION_INSTRUCTION
from tools import (
    get_current_india_datetime,
    get_weather,
    search_web,
    get_live_sports_scores,
    get_latest_news,
    send_email,
    add_task,
    get_tasks,
    complete_task,
    remember_preference,
    set_default_city,
    recall_memory,
    save_to_memory,
)
import mem0_shared

try:
    from mem0 import AsyncMemoryClient
except Exception:  # pragma: no cover - optional dependency runtime guard
    AsyncMemoryClient = None  # type: ignore[assignment]

try:
    from mcp_client import MCPServerSse
    from mcp_client.agent_tools import MCPToolsIntegration
except Exception:  # pragma: no cover - optional dependency runtime guard
    MCPServerSse = None  # type: ignore[assignment]
    MCPToolsIntegration = None  # type: ignore[assignment]

load_dotenv()
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")


def _env_float(name: str, default: float) -> float:
    raw = os.getenv(name, "").strip()
    if not raw:
        return default
    try:
        return float(raw)
    except ValueError:
        logging.warning("Invalid %s=%r, using default=%s", name, raw, default)
        return default


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name, "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        logging.warning("Invalid %s=%r, using default=%s", name, raw, default)
        return default


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name, "").strip().lower()
    if not raw:
        return default
    if raw in {"1", "true", "yes", "on"}:
        return True
    if raw in {"0", "false", "no", "off"}:
        return False
    logging.warning("Invalid %s=%r, using default=%s", name, raw, default)
    return default


def _truthy_env(name: str, default: str) -> bool:
    return os.getenv(name, default).strip().lower() in {"1", "true", "yes", "on"}


class Assistant(Agent):
    def __init__(self, chat_ctx: Optional[ChatContext] = None) -> None:
        # Use Gemini Realtime by default so only GOOGLE_API_KEY is required.
        # Legacy STT/TTS path remains available behind GOOGLE_USE_REALTIME=0.
        tools = [
            get_current_india_datetime,
            get_weather,
            search_web,
            get_live_sports_scores,
            get_latest_news,
            send_email,
            add_task,
            get_tasks,
            complete_task,
            remember_preference,
            set_default_city,
            recall_memory,
            save_to_memory,
        ]

        google_api_key = os.getenv("GOOGLE_API_KEY")
        if not google_api_key:
            raise RuntimeError("GOOGLE_API_KEY is required for the Lex agent")

        use_realtime = os.getenv("GOOGLE_USE_REALTIME", "1").strip() != "0"
        if use_realtime:
            realtime_model = os.getenv(
                "GOOGLE_REALTIME_MODEL",
                "gemini-2.5-flash-native-audio-preview-12-2025",
            ).strip()
            realtime_voice = os.getenv("GOOGLE_REALTIME_VOICE", "Kore").strip()
            realtime_language = (
                os.getenv("GOOGLE_REALTIME_LANGUAGE", "en-US").strip() or "en-US"
            )
            realtime_temperature = _env_float("GOOGLE_REALTIME_TEMPERATURE", 0.2)
            # Keep the default output ceiling reasonably low for voice latency,
            # while still leaving enough room for longer responses when needed.
            realtime_max_output_tokens = _env_int("GOOGLE_REALTIME_MAX_OUTPUT_TOKENS", 1024)
            if realtime_max_output_tokens <= 0:
                logging.warning(
                    "Invalid GOOGLE_REALTIME_MAX_OUTPUT_TOKENS=%s; using 2048",
                    realtime_max_output_tokens,
                )
                realtime_max_output_tokens = 2048
            elif realtime_max_output_tokens < 256:
                logging.warning(
                    "GOOGLE_REALTIME_MAX_OUTPUT_TOKENS=%s is very low for native audio; "
                    "using 256 to avoid clipped speech",
                    realtime_max_output_tokens,
                )
                realtime_max_output_tokens = 256
            logging.info(
                "Realtime config model=%s voice=%s language=%s temperature=%s "
                "max_output_tokens=%s",
                realtime_model,
                realtime_voice,
                realtime_language,
                realtime_temperature,
                realtime_max_output_tokens,
            )

            def _build_realtime_model(model_name: str) -> google.realtime.RealtimeModel:
                return google.realtime.RealtimeModel(
                    api_key=google_api_key,
                    model=model_name,
                    voice=realtime_voice,
                    language=realtime_language,
                    temperature=realtime_temperature,
                    max_output_tokens=realtime_max_output_tokens,
                )

            try:
                realtime_llm = _build_realtime_model(realtime_model)
            except ValueError as exc:
                # Common misconfig: Vertex-only model with Gemini API key mode.
                if "is a VertexAI model" in str(exc):
                    fallback_model = "gemini-2.5-flash-native-audio-preview-12-2025"
                    logging.warning(
                        "Realtime model %s is Vertex-only in current config; falling back to %s",
                        realtime_model,
                        fallback_model,
                    )
                    realtime_llm = _build_realtime_model(fallback_model)
                else:
                    raise

            super().__init__(
                instructions=AGENT_INSTRUCTION,
                llm=realtime_llm,
                tools=tools,
                chat_ctx=chat_ctx,
            )
            return

        credentials_file = os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
        if not credentials_file:
            raise RuntimeError(
                "GOOGLE_USE_REALTIME=0 requires GOOGLE_APPLICATION_CREDENTIALS "
                "for Google STT/TTS."
            )

        stt_languages = [
            language.strip()
            for language in os.getenv("GOOGLE_STT_LANGUAGES", "en-US").split(",")
            if language.strip()
        ] or ["en-US"]
        stt_detect_language = _env_bool("GOOGLE_STT_DETECT_LANGUAGE", False)
        tts_language = os.getenv("GOOGLE_TTS_LANGUAGE", "en-US").strip() or "en-US"

        super().__init__(
            instructions=AGENT_INSTRUCTION,
            stt=google.STT(
                credentials_file=credentials_file,
                languages=stt_languages,
                detect_language=stt_detect_language,
            ),
            vad=silero.VAD.load(),
            llm=google.LLM(
                api_key=google_api_key,
                temperature=0.8,
            ),
            tts=google.TTS(
                credentials_file=credentials_file,
                language=tts_language,
                voice_name="Aoede",
            ),
            tools=tools,
            chat_ctx=chat_ctx,
        )


async def _create_mem0_client() -> Optional[Any]:
    if AsyncMemoryClient is None:
        logging.warning("mem0 not available; continuing without long-term memory sync")
        return None

    try:
        return AsyncMemoryClient()
    except TypeError:
        # Some mem0 versions require explicit api_key argument.
        api_key = os.getenv("MEM0_API_KEY")
        if not api_key:
            logging.warning("MEM0_API_KEY missing; continuing without mem0 client")
            return None
        return AsyncMemoryClient(api_key=api_key)
    except Exception as exc:
        logging.warning("Could not initialize mem0 client: %s", exc)
        return None


async def _load_memory_context(mem0_client: Optional[Any], user_name: str) -> Tuple[ChatContext, str]:
    initial_ctx = ChatContext()
    if mem0_client is None:
        return initial_ctx, ""

    memory_bootstrap_limit = max(1, _env_int("LEX_MEMORY_BOOTSTRAP_LIMIT", 8))

    try:
        results = await mem0_client.get_all(user_id=user_name)
        if not results:
            return initial_ctx, ""

        memories = [
            {
                "memory": result.get("memory", ""),
                "updated_at": result.get("updated_at", ""),
            }
            for result in results
            if result.get("memory")
        ]
        memories.sort(key=lambda item: item.get("updated_at", ""), reverse=True)
        trimmed_memories = memories[:memory_bootstrap_limit]
        if not trimmed_memories:
            return initial_ctx, ""

        memory_lines = [f"- {item['memory']}" for item in trimmed_memories]
        memory_str = "\n".join(memory_lines)
        logging.info(
            "Loaded %s memories from mem0, bootstrapping %s",
            len(memories),
            len(trimmed_memories),
        )
        initial_ctx.add_message(
            role="assistant",
            content=(
                f"The user's name is {user_name}. Relevant memory context:\n"
                f"{memory_str}"
            ),
        )
        return initial_ctx, memory_str
    except Exception as exc:
        logging.warning("Failed to load mem0 memories: %s", exc)
        return initial_ctx, ""


async def _shutdown_hook(chat_ctx: ChatContext, mem0_client: Optional[Any], memory_str: str, user_name: str) -> None:
    if mem0_client is None:
        return

    logging.info("Shutting down: saving chat context to memory")
    messages_formatted = []

    for item in chat_ctx.items:
        # Skip non-message items (e.g. AgentConfigUpdate) that lack 'content'
        if not hasattr(item, "content"):
            continue
        content_str = "".join(item.content) if isinstance(item.content, list) else str(item.content)

        # Skip the synthetic memory bootstrap message to avoid duplicate storage.
        if memory_str and memory_str in content_str:
            continue

        role = str(item.role)
        if role in ("user", "assistant"):
            messages_formatted.append(
                {
                    "role": role,
                    "content": content_str.strip(),
                }
            )

    if not messages_formatted:
        return

    try:
        await mem0_client.add(messages_formatted, user_id=user_name)
        logging.info("Saved %s messages to mem0", len(messages_formatted))
    except Exception as exc:
        logging.warning("Failed to save chat context to mem0: %s", exc)


async def _generate_initial_greeting(session: AgentSession, user_name: str) -> None:
    try:
        # Wait for audio track and realtime session to be fully ready
        await asyncio.sleep(2.0)
        greeting_instruction = (
            f"Greet the user by name. The user's name is {user_name}. "
            f"Say something like: 'Hi {user_name}, I am LEX, your personal assistant. "
            f"How can I help you today?' Keep it warm, short, and natural."
        )
        await session.generate_reply(instructions=greeting_instruction)
        logging.info("Initial greeting generated for user=%s", user_name)
    except Exception as exc:
        logging.warning("Initial greeting failed: %s", exc)


async def entrypoint(ctx: agents.JobContext):
    logging.info("Entrypoint invoked for room=%s", ctx.room.name)

    user_name = os.getenv("MEMORY_USER_ID", "David")
    memory_client_timeout = max(0.5, _env_float("LEX_MEMORY_CLIENT_TIMEOUT_SECONDS", 1.0))
    memory_load_timeout = max(0.5, _env_float("LEX_MEMORY_LOAD_TIMEOUT_SECONDS", 1.5))
    mcp_attach_timeout = max(0.5, _env_float("LEX_MCP_ATTACH_TIMEOUT_SECONDS", 2.0))
    min_endpointing_delay = max(0.0, _env_float("LEX_MIN_ENDPOINTING_DELAY", 0.2))
    max_endpointing_delay = max(
        min_endpointing_delay,
        _env_float("LEX_MAX_ENDPOINTING_DELAY", 0.6),
    )

    mem0_client: Optional[Any] = None
    try:
        mem0_client = await asyncio.wait_for(
            _create_mem0_client(),
            timeout=memory_client_timeout,
        )
    except asyncio.TimeoutError:
        logging.warning(
            "Timed out initializing mem0 client after %.1fs; continuing without startup memory",
            memory_client_timeout,
        )

    # Expose client & user_id to function-tools via shared module
    mem0_shared.mem0_client = mem0_client
    mem0_shared.user_id = user_name

    initial_ctx = ChatContext()
    memory_str = ""
    if mem0_client is not None:
        try:
            initial_ctx, memory_str = await asyncio.wait_for(
                _load_memory_context(mem0_client, user_name),
                timeout=memory_load_timeout,
            )
        except asyncio.TimeoutError:
            logging.warning(
                "Timed out loading mem0 bootstrap context after %.1fs; continuing with empty context",
                memory_load_timeout,
            )

    agent: Agent = Assistant(chat_ctx=initial_ctx)

    n8n_url = os.getenv("N8N_MCP_SERVER_URL", "").strip()
    if n8n_url and MCPServerSse and MCPToolsIntegration:
        try:
            mcp_server = MCPServerSse(
                params={"url": n8n_url},
                cache_tools_list=True,
                name="SSE MCP Server",
            )
            agent = await asyncio.wait_for(
                MCPToolsIntegration.create_agent_with_tools(
                    agent_class=Assistant,
                    agent_kwargs={"chat_ctx": initial_ctx},
                    mcp_servers=[mcp_server],
                ),
                timeout=mcp_attach_timeout,
            )
            logging.info("MCP tools attached from %s", n8n_url)
        except asyncio.TimeoutError:
            logging.warning(
                "Timed out attaching MCP tools after %.1fs; continuing without MCP tools",
                mcp_attach_timeout,
            )
        except Exception as exc:
            logging.warning("MCP integration unavailable, continuing without MCP tools: %s", exc)
    elif n8n_url and (not MCPServerSse or not MCPToolsIntegration):
        logging.warning("N8N_MCP_SERVER_URL is set but MCP dependencies are missing")

    session = AgentSession(
        min_endpointing_delay=min_endpointing_delay,
        max_endpointing_delay=max_endpointing_delay,
        preemptive_generation=_env_bool("LEX_PREEMPTIVE_GENERATION", True),
        false_interruption_timeout=_env_float(
            "LEX_FALSE_INTERRUPTION_TIMEOUT",
            1.0,
        ),
    )

    try:
        await ctx.connect()
        logging.info("Connected to LiveKit room: %s", ctx.room.name)

        await session.start(
            room=ctx.room,
            agent=agent,
            room_input_options=RoomInputOptions(
                audio_enabled=True,
                video_enabled=False,
                noise_cancellation=noise_cancellation.BVC(),
            ),
        )
        logging.info("Agent session started and listening")

        if _truthy_env("LEX_ENABLE_INITIAL_GREETING", "0"):
            asyncio.create_task(_generate_initial_greeting(session, user_name))

        ctx.add_shutdown_callback(
            lambda: _shutdown_hook(
                getattr(session._agent, "chat_ctx", initial_ctx),  # pylint: disable=protected-access
                mem0_client,
                memory_str,
                user_name,
            )
        )
    except Exception:
        logging.exception("Agent entrypoint failed")
        raise


async def request_fnc(req: agents.JobRequest):
    room_name = getattr(req.room, "name", str(req.room))
    logging.info(
        "Job request received: id=%s room=%s agent_name=%s",
        req.id,
        room_name,
        req.agent_name,
    )
    await req.accept()


if __name__ == "__main__":
    agents.cli.run_app(
        agents.WorkerOptions(
            entrypoint_fnc=entrypoint,
            request_fnc=request_fnc,
            agent_name="lex",
        )
    )
