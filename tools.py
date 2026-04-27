import logging
from livekit.agents import function_tool, RunContext
import requests
from langchain_community.tools import DuckDuckGoSearchRun
import os
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
import smtplib
from email.mime.multipart import MIMEMultipart  
from email.mime.text import MIMEText
from typing import Optional

@function_tool()
async def get_weather(
    context: RunContext,  # type: ignore
    city: str = "") -> str:
    """
    Get the current weather for a given city in Celsius.
    If city is omitted, uses saved default city from memory, then Chennai fallback.
    """
    resolved_city = city.strip()
    if not resolved_city:
        user_city = memory_manager.get_preferences().get("default_city", "")
        resolved_city = user_city if user_city else "Chennai"

    try:
        response = requests.get(
            f"https://wttr.in/{resolved_city}?format=3")
        if response.status_code == 200:
            logging.info(f"Weather for {resolved_city}: {response.text.strip()}")
            return response.text.strip()   
        else:
            logging.error(f"Failed to get weather for {resolved_city}: {response.status_code}")
            return f"Could not retrieve weather for {resolved_city}."
    except Exception as e:
        logging.error(f"Error retrieving weather for {resolved_city}: {e}")
        return f"An error occurred while retrieving weather for {resolved_city}." 

@function_tool()
async def search_web(
    context: RunContext,  # type: ignore
    query: str) -> str:
    """
    Search the web using DuckDuckGo for real-time information.
    Returns concise, voice-friendly results.
    Use this for general knowledge, current events, and any query
    that needs up-to-date internet data.
    """
    try:
        results = DuckDuckGoSearchRun().run(tool_input=query)
        logging.info(f"Search results for '{query}': {results}")
        # Truncate for voice-friendly output (keep under 500 chars)
        if results and len(results) > 500:
            # Try to cut at a sentence boundary
            truncated = results[:500]
            last_period = truncated.rfind('.')
            if last_period > 200:
                truncated = truncated[:last_period + 1]
            results = truncated
        return results if results else "I couldn't find any results for that query."
    except Exception as e:
        logging.error(f"Error searching the web for '{query}': {e}")
        return f"I couldn't find the latest information right now."


@function_tool()
async def get_live_sports_scores(
    context: RunContext,  # type: ignore
    sport: str = "cricket",
    query: str = "",
) -> str:
    """
    Get live or latest sports scores and match updates.
    Supports cricket (IPL, international), football, and other major sports.

    Args:
        sport: The sport to check - "cricket", "football", "tennis", etc.
        query: Optional specific query like team name or tournament (e.g. "IPL", "CSK", "India vs Australia")
    """
    try:
        # Build a targeted search query for sports scores
        sport_lower = sport.strip().lower()
        user_query = query.strip()

        if sport_lower == "cricket":
            if user_query:
                search_query = f"{user_query} cricket live score today 2026"
            else:
                search_query = "IPL cricket live score today 2026"
        elif sport_lower == "football":
            if user_query:
                search_query = f"{user_query} football live score today"
            else:
                search_query = "football live scores today Premier League"
        else:
            search_query = f"{sport} {user_query} live score today" if user_query else f"{sport} live scores today"

        results = DuckDuckGoSearchRun().run(tool_input=search_query)
        logging.info(f"Sports search for '{search_query}': {results}")

        if not results or len(results.strip()) < 10:
            return f"I couldn't find live {sport} scores right now. Try asking again in a moment."

        # Truncate for voice — keep concise
        if len(results) > 400:
            truncated = results[:400]
            last_period = truncated.rfind('.')
            if last_period > 150:
                truncated = truncated[:last_period + 1]
            results = truncated

        return results
    except Exception as e:
        logging.error(f"Error fetching {sport} scores: {e}")
        return f"I couldn't find live {sport} scores right now."


# ── RSS Feed URLs for news (no API keys required) ──
_NEWS_FEEDS = {
    "india": [
        "https://feeds.feedburner.com/ndtvnews-top-stories",
        "https://timesofindia.indiatimes.com/rssfeedstopstories.cms",
    ],
    "world": [
        "http://feeds.bbci.co.uk/news/world/rss.xml",
        "https://feeds.feedburner.com/ndtvnews-world-news",
    ],
    "technology": [
        "http://feeds.bbci.co.uk/news/technology/rss.xml",
        "https://timesofindia.indiatimes.com/rssfeeds/66949542.cms",
    ],
    "business": [
        "https://economictimes.indiatimes.com/rssfeedstopstories.cms",
        "http://feeds.bbci.co.uk/news/business/rss.xml",
    ],
    "sports": [
        "https://timesofindia.indiatimes.com/rssfeeds/4719148.cms",
        "http://feeds.bbci.co.uk/sport/rss.xml",
    ],
}


@function_tool()
async def get_latest_news(
    context: RunContext,  # type: ignore
    category: str = "india",
    count: int = 5,
) -> str:
    """
    Get latest news headlines from trusted sources.
    Returns concise, voice-friendly headlines.

    Args:
        category: News category - "india", "world", "technology", "business", "sports"
        count: Number of headlines to return (1 to 5, default 5)
    """
    import feedparser

    category_lower = category.strip().lower()
    count = max(1, min(count, 5))

    feeds = _NEWS_FEEDS.get(category_lower, _NEWS_FEEDS["india"])
    headlines = []

    for feed_url in feeds:
        if len(headlines) >= count:
            break
        try:
            feed = feedparser.parse(feed_url)
            for entry in feed.entries:
                if len(headlines) >= count:
                    break
                title = entry.get("title", "").strip()
                if title and title not in headlines:
                    headlines.append(title)
        except Exception as e:
            logging.warning(f"Failed to parse RSS feed {feed_url}: {e}")
            continue

    if not headlines:
        # Fallback to DuckDuckGo news search
        try:
            fallback_query = f"latest {category_lower} news today headlines"
            results = DuckDuckGoSearchRun().run(tool_input=fallback_query)
            if results:
                if len(results) > 400:
                    results = results[:400]
                    last_period = results.rfind('.')
                    if last_period > 150:
                        results = results[:last_period + 1]
                return f"Here are the latest {category_lower} updates: {results}"
        except Exception:
            pass
        return f"I couldn't fetch {category_lower} news right now. Please try again."

    # Format for voice output
    news_text = f"Here are today's top {category_lower} headlines: "
    for i, headline in enumerate(headlines, 1):
        news_text += f"{i}. {headline}. "

    logging.info(f"News ({category_lower}): {len(headlines)} headlines returned")
    return news_text.strip()


@function_tool()    
async def send_email(
    context: RunContext,  # type: ignore
    to_email: str,
    subject: str,
    message: str,
    cc_email: Optional[str] = None
) -> str:
    """
    Send an email through Gmail.
    
    Args:
        to_email: Recipient email address
        subject: Email subject line
        message: Email body content
        cc_email: Optional CC email address
    """
    try:
        # Gmail SMTP configuration
        smtp_server = "smtp.gmail.com"
        smtp_port = 587
        
        # Get credentials from environment variables
        gmail_user = os.getenv("GMAIL_USER")
        gmail_password = os.getenv("GMAIL_APP_PASSWORD")  # Use App Password, not regular password
        
        if not gmail_user or not gmail_password:
            logging.error("Gmail credentials not found in environment variables")
            return "Email sending failed: Gmail credentials not configured."
        
        # Create message
        msg = MIMEMultipart()
        msg['From'] = gmail_user
        msg['To'] = to_email
        msg['Subject'] = subject
        
        # Add CC if provided
        recipients = [to_email]
        if cc_email:
            msg['Cc'] = cc_email
            recipients.append(cc_email)
        
        # Attach message body
        msg.attach(MIMEText(message, 'plain'))
        
        # Connect to Gmail SMTP server
        server = smtplib.SMTP(smtp_server, smtp_port)
        server.starttls()  # Enable TLS encryption
        server.login(gmail_user, gmail_password)
        
        # Send email
        text = msg.as_string()
        server.sendmail(gmail_user, recipients, text)
        server.quit()
        
        logging.info(f"Email sent successfully to {to_email}")
        return f"Email sent successfully to {to_email}"
        
    except smtplib.SMTPAuthenticationError:
        logging.error("Gmail authentication failed")
        return "Email sending failed: Authentication error. Please check your Gmail credentials."
    except smtplib.SMTPException as e:
        logging.error(f"SMTP error occurred: {e}")
        return f"Email sending failed: SMTP error - {str(e)}"
    except Exception as e:
        logging.error(f"Error sending email: {e}")
        return f"An error occurred while sending email: {str(e)}"

# Initialize Managers
from memory import MemoryManager
from task_manager import TaskManager

memory_manager = MemoryManager()
task_manager = TaskManager()

def _get_india_now() -> datetime:
    """
    Return current datetime in IST.
    Falls back to fixed UTC+05:30 when ZoneInfo data is unavailable.
    """
    try:
        return datetime.now(ZoneInfo("Asia/Kolkata"))
    except ZoneInfoNotFoundError:
        ist = timezone(timedelta(hours=5, minutes=30), name="IST")
        return datetime.now(ist)


@function_tool()
async def get_current_india_datetime(context: RunContext) -> str:
    """
    Get the current date and time in India (IST).
    """
    try:
        now_ist = _get_india_now()
        date_str = now_ist.strftime("%d/%m/%Y")
        time_str = now_ist.strftime("%I:%M %p")
        return f"The current time in India is {time_str} IST on {date_str}."
    except Exception as e:
        logging.error(f"Error retrieving current India datetime: {e}")
        return "I am unable to retrieve the current India time right now."

@function_tool()
async def add_task(
    context: RunContext,
    description: str,
    due_date: str = "") -> str:
    """
    Add a new task to the user's todo list.
    Args:
        description: The task description.
        due_date: Optional due date/time (string format).
    """
    task = task_manager.add_task(description, due_date)
    return f"Task added: {task['description']} (ID: {task['id']})"

@function_tool()
async def get_tasks(context: RunContext) -> str:
    """
    Get the list of pending tasks.
    """
    tasks = task_manager.get_pending_tasks()
    if not tasks:
        return "You have no pending tasks."
    
    result = "Pending Tasks:\n"
    for t in tasks:
        due = f" (Due: {t['due_date']})" if t['due_date'] else ""
        result += f"- [ID: {t['id']}] {t['description']}{due}\n"
    return result

@function_tool()
async def complete_task(
    context: RunContext,
    task_identifier: str) -> str:
    """
    Mark a task as completed.
    Args:
        task_identifier: The ID or description of the task to complete.
    """
    return task_manager.complete_task(task_identifier)

@function_tool()
async def remember_preference(
    context: RunContext,
    key: str,
    value: str) -> str:
    """
    Remember a user preference or fact.
    Args:
        key: The category or key for the preference (e.g., "favorite_color", "birthday").
        value: The value to remember.
    """
    memory_manager.set_preference(key, value)
    return f"I have remembered that your {key} is {value}."


@function_tool()
async def set_default_city(
    context: RunContext,
    city: str,
) -> str:
    """
    Save the user's default city (India context) for weather and location fallback.
    """
    resolved = city.strip()
    if not resolved:
        return "Please provide a valid city name."
    memory_manager.set_preference("default_city", resolved)
    return f"Default city saved as {resolved}."


# ---------------------------------------------------------------------------
# Mem0 cloud memory tools
# ---------------------------------------------------------------------------
import mem0_shared


@function_tool()
async def recall_memory(
    context: RunContext,  # type: ignore
    query: str,
) -> str:
    """
    Search the user's long-term cloud memory for relevant information.
    Use this when the user asks what you remember about them, or asks
    about something discussed in a previous conversation.

    Args:
        query: A natural-language description of what to look up,
               e.g. "favorite music" or "what we discussed yesterday".
    """
    if mem0_shared.mem0_client is None:
        return "Long-term memory is not available right now."

    try:
        results = await mem0_shared.mem0_client.search(
            query, user_id=mem0_shared.user_id
        )
        if not results:
            return "I don't have any memories matching that query."

        memories = [
            {
                "memory": r.get("memory", ""),
                "updated_at": r.get("updated_at", ""),
            }
            for r in results
        ]
        import json as _json

        memories_str = _json.dumps(memories, ensure_ascii=False)
        logging.info("recall_memory found %s results for '%s'", len(memories), query)
        return f"Here is what I remember: {memories_str}"
    except Exception as exc:
        logging.warning("recall_memory failed: %s", exc)
        return "I was unable to search my memory right now."


@function_tool()
async def save_to_memory(
    context: RunContext,  # type: ignore
    content: str,
) -> str:
    """
    Explicitly save a piece of information to long-term cloud memory.
    Use this when the user says 'remember this', 'save this',
    'from now on', or similar phrases indicating they want you to
    remember something permanently.

    Args:
        content: The information to remember, written as a clear statement.
    """
    if mem0_shared.mem0_client is None:
        return "Long-term memory is not available right now."

    try:
        messages = [{"role": "user", "content": content}]
        await mem0_shared.mem0_client.add(messages, user_id=mem0_shared.user_id)
        logging.info("save_to_memory saved: %s", content[:80])
        return f"Got it, I will remember that."
    except Exception as exc:
        logging.warning("save_to_memory failed: %s", exc)
        return "I was unable to save that to memory right now."
