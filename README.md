# ClaudePill

A macOS menu bar pill showing the status of your Claude Code sessions, with a panel listing every session.

> [!NOTE]
> This app is vibecoded: it was written almost entirely by Claude Code, with no tests. It works on its author's machine; expect rough edges elsewhere.

The pill shows one icon summarizing all sessions:

| Icon | Meaning |
| --- | --- |
| Hand | A session is waiting for you (a permission prompt or question) |
| Clock | A session is working |
| Clock with check | A session is working and another finished since you last opened the panel |
| Circle check | The latest session is done |
| Sparkle | No sessions |

Click the pill to list sessions. Click a session to jump to its terminal in [Ghostty](https://ghostty.org); right-click it to reveal or copy its folder.

## Requirements

- macOS 14 or later
- Swift 6 toolchain (Xcode 16 or the Command Line Tools)
- [`jq`](https://jqlang.org): `brew install jq`
- [Claude Code](https://claude.com/claude-code)
- Optional: Ghostty, for jumping to a session's terminal. Without it, rows in the panel are not clickable.

## Install

```sh
git clone https://github.com/pt-hieu/claude-pill.git
cd claude-pill
./install-hooks.sh
./build.sh
open build/ClaudePill.app
```

`install-hooks.sh` adds ClaudePill's hook to `~/.claude/settings.json` for the `UserPromptSubmit`, `Stop`, `Notification` and `SessionEnd` events, after saving a backup to `~/.claude/settings.json.bak`. Running it again changes nothing. Sessions show up from their next event.

The hooks point at the clone's absolute path, so keep the clone where it is. To move it, run `./uninstall-hooks.sh` first, move it, then run `./install-hooks.sh` from the new place.

To start ClaudePill at login, copy `build/ClaudePill.app` to `/Applications` and add it in System Settings → General → Login Items.

The first time you jump to a session, macOS asks to let ClaudePill control Ghostty.

## How it works

Each hook event runs `hooks/log-event.sh`, which appends one line to `~/Library/Caches/ClaudePill/events.jsonl`. The app watches that file and keeps the latest event per session.

Each line holds the session id, working directory, event name, notification message, session title and terminal device. Nothing leaves your machine. The app keeps the log small: it drops events older than seven days and events of sessions that ended.

## Uninstall

```sh
./uninstall-hooks.sh
rm -rf ~/Library/Caches/ClaudePill
```

Then quit ClaudePill and delete the app.

## License

MIT. The status icons are from [Lucide](https://lucide.dev), under the ISC license in `Icons/LICENSE`.
