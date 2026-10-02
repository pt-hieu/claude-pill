#!/bin/sh
# Removes the hooks/log-event.sh entries that install-hooks.sh added to ~/.claude/settings.json.
# Only entries pointing at this clone are removed: run it from the clone that installed them.
set -eu
cd "$(dirname "$0")"

if ! command -v jq >/dev/null; then
  echo "ClaudePill needs jq: install it with 'brew install jq', then run this again." >&2
  exit 1
fi

settings="$HOME/.claude/settings.json"
hook_command="$(pwd)/hooks/log-event.sh"
[ -f "$settings" ] || { echo "No $settings: nothing to remove"; exit 0; }
cp "$settings" "$settings.bak"

# Drops the matching hooks, then any group or event left empty, then the hooks key if nothing remains.
jq --arg command "$hook_command" '
  if .hooks then
    .hooks |= with_entries(
      .value |= map(.hooks |= map(select(.command != $command)) | select(.hooks | length > 0))
      | select(.value | length > 0))
    | if .hooks == {} then del(.hooks) else . end
  else . end
' "$settings.bak" > "$settings"

echo "Hooks removed from $settings (backup at $settings.bak)"
