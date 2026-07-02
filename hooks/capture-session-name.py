#!/usr/bin/env python3
"""
SessionStart hook: capture the current session's statusline session_name
to a per-session file so downstream readers (e.g. pair-chrome status page)
can show the literal user-set title.

Contract (PRD Module 6, slice 0005):
  - stdin: JSON with at least {session_id, session_name}
  - file:  ~/.claude/session-name-<session_id>.txt, mode 0600
  - body:  literal session_name string, no trailing newline
  - on missing/empty session_name: write an empty file (0 bytes)
  - idempotent (overwrites in place) and non-blocking (< 1s)
"""
import json
import os
import sys


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        # Malformed stdin -> nothing to do, never block the session.
        return 0

    session_id = data.get("session_id") or "default"
    session_name = data.get("session_name") or ""

    target_dir = os.path.expanduser("~/.claude")
    os.makedirs(target_dir, exist_ok=True)
    target_path = os.path.join(target_dir, f"session-name-{session_id}.txt")

    # No trailing newline: the reader does `cat | head -1 | tr -d '\n'`.
    fd = os.open(target_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.write(fd, session_name.encode("utf-8"))
    finally:
        os.close(fd)
    return 0


if __name__ == "__main__":
    sys.exit(main())
