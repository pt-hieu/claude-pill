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

payload=$(cat)

# The session title lives only in the transcript: a title set with /rename wins over the generated one.
# The generated title is written after the first prompt, so the first event of a session has none.
transcript_path=$(printf '%s' "$payload" | jq -r '.transcript_path // empty')
title=""
if [ -f "$transcript_path" ]; then
  title=$(grep -F '"type":"custom-title"' "$transcript_path" | tail -n 1 | jq -r '.customTitle // empty')
  if [ -z "$title" ]; then
    title=$(grep -F '"type":"ai-title"' "$transcript_path" | tail -n 1 | jq -r '.aiTitle // empty')
  fi
fi

printf '%s' "$payload" | jq -c --arg tty "$terminal_device" --arg title "$title" \
  '{session_id, cwd, hook_event_name, message, title: (if $title == "" then null else $title end), tty: (if $tty == "" then null else $tty end), ts: now}' \
  >> "$directory/events.jsonl"
