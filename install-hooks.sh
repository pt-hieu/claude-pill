#!/bin/sh
# Registers hooks/log-event.sh in ~/.claude/settings.json for the events ClaudePill tracks.
# Idempotent: an event that already runs the script is left alone.
set -eu
cd "$(dirname "$0")"

settings="$HOME/.claude/settings.json"
hook_command="$(pwd)/hooks/log-event.sh"
chmod +x "$hook_command"
[ -f "$settings" ] || echo '{}' > "$settings"
cp "$settings" "$settings.bak"

jq --arg command "$hook_command" '
  reduce ("UserPromptSubmit", "Stop", "Notification", "SessionEnd") as $event (.;
    if any(.hooks[$event][]?.hooks[]?; .command == $command) then .
    else .hooks[$event] += [{hooks: [{type: "command", command: $command}]}]
    end)
' "$settings.bak" > "$settings"

echo "Hooks installed in $settings (backup at $settings.bak)"
