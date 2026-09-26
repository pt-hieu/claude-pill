#!/bin/sh
# Claude Code hook: appends the hook payload to the ClaudePill event log.
directory="$HOME/Library/Caches/ClaudePill"
mkdir -p "$directory"
jq -c '{session_id, cwd, hook_event_name, message, ts: now}' >> "$directory/events.jsonl"
