# ClaudePill

macOS menu bar app: a pill showing the latest Claude Code session status, with a panel listing every session. Claude Code hooks (`hooks/log-event.sh`, registered in `~/.claude/settings.json` by `install-hooks.sh`) append events to `~/Library/Caches/ClaudePill/events.jsonl`; the app watches that file.

## Run and verify

- Install hooks, rebuild and relaunch: `./run.sh`
- Feed a fake event by piping hook JSON into the script: `echo '{"session_id":"test","cwd":"/path","hook_event_name":"Stop"}' | hooks/log-event.sh`
- Claude Code usually cannot see the screen here (no Screen Recording or Accessibility permission). Ask the user to check the UI. To inspect layout, write values to a file in `/tmp`: `NSLog` output does not show up in `log show`.

## Design

- Monochrome: the pill uses the primary color so it follows the menu bar appearance; statuses are SF Symbols, not colors.
- Sentence case for all copy.

## Gotchas

- The status item's click highlight is drawn by the system (`MenuBarAgent`), not the app, and cannot be removed or resized. It covers the whole status item window: the full menu bar height, and ~8pt of system padding each side of the button, like the highlight of the system's own menu bar icons.
- Round the item length up: the window snaps to whole points, and any shortfall truncates the pill text.
- Ghostty sessions are matched by tty (the `GHOSTTY_SURFACE_ID` env var does not match AppleScript terminal ids). `focus` alone does not switch tabs, so select the tab and activate the window first. Avoid running focus scripts against the user's Ghostty while they work in it.
- The installed hooks point at this repo's absolute path; moving the repo means running `uninstall-hooks.sh` before the move and `install-hooks.sh` after.
