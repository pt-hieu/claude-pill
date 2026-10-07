#!/bin/sh
# Registers hooks/log-event.sh in ~/.claude/settings.json for the events ClaudePill tracks.
# Idempotent: an event that already runs the script is left alone, and settings already holding every hook are not rewritten.
set -eu
cd "$(dirname "$0")"

if ! command -v jq >/dev/null; then
  echo "ClaudePill needs jq: install it with 'brew install jq', then run this again." >&2
  exit 1
fi

settings="$HOME/.claude/settings.json"
hook_command="$(pwd)/hooks/log-event.sh"
chmod +x "$hook_command"
[ -f "$settings" ] || echo '{}' > "$settings"

updated="$(jq --arg command "$hook_command" '
  reduce ("UserPromptSubmit", "Stop", "Notification", "SessionEnd") as $event (.;
    if any(.hooks[$event][]?.hooks[]?; .command == $command) then .
    else .hooks[$event] += [{hooks: [{type: "command", command: $command}]}]
    end)
' "$settings")"

if [ "$updated" = "$(jq . "$settings")" ]; then
  echo "Hooks already installed in $settings"
  exit 0
fi

cp "$settings" "$settings.bak"
printf '%s\n' "$updated" > "$settings"
echo "Hooks installed in $settings (backup at $settings.bak)"
