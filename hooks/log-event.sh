#!/bin/sh
# Claude Code hook: appends the hook payload to the ClaudePill event log.
directory="$HOME/Library/Caches/ClaudePill"
mkdir -p "$directory"

# The terminal device of the Claude process lets ClaudePill focus the matching Ghostty terminal.
# Hooks run without a controlling terminal of their own, so walk up to the first ancestor that has one.
terminal_device=""
process_id=$$
while [ -n "$process_id" ] && [ "$process_id" -gt 1 ]; do
  candidate=$(ps -o tty= -p "$process_id" | tr -d ' ')
  if [ -n "$candidate" ] && [ "$candidate" != "??" ]; then
    terminal_device="/dev/$candidate"
    break
  fi
  process_id=$(ps -o ppid= -p "$process_id" | tr -d ' ')
done

jq -c --arg tty "$terminal_device" \
  '{session_id, cwd, hook_event_name, message, tty: (if $tty == "" then null else $tty end), ts: now}' \
  >> "$directory/events.jsonl"
