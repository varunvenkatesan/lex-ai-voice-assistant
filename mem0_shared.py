"""
Shared mem0 state — set by agent.py at startup, consumed by tools.py.

This module avoids circular imports between agent.py and tools.py while
letting function-tools access the mem0 AsyncMemoryClient and user_id
that are initialised during the LiveKit entrypoint.
"""

from typing import Any, Optional

# Populated by agent.py after creating the AsyncMemoryClient.
mem0_client: Optional[Any] = None

# Current user id for mem0 operations.  Defaults to env-var value set in agent.py.
user_id: str = "David"
