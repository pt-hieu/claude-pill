import Foundation

/// Brings a session's terminal to the front in Ghostty through its AppleScript dictionary.
enum Ghostty {
    /// Focuses the terminal on the session's device, selecting its tab and window first because
    /// `focus` alone does not switch tabs. Opens a new tab in the session's folder when that
    /// terminal is gone.
    private static let script = """
        on run argv
            set terminalDevice to item 1 of argv
            set workingDirectory to item 2 of argv
            tell application "Ghostty"
                activate
                if terminalDevice is not "" then
                    repeat with candidateWindow in windows
                        repeat with candidateTab in tabs of candidateWindow
                            repeat with candidateTerminal in terminals of candidateTab
                                if tty of candidateTerminal is terminalDevice then
                                    select tab candidateTab
                                    activate window candidateWindow
                                    focus candidateTerminal
                                    return
                                end if
                            end repeat
                        end repeat
                    end repeat
                end if
                set configuration to new surface configuration
                set initial working directory of configuration to workingDirectory
                if (count of windows) is 0 then
                    new window with configuration configuration
                else
                    new tab in front window with configuration configuration
                end if
            end tell
        end run
        """

    static func open(_ session: Session) {
        // osascript rather than NSAppleScript keeps the lookup off the main thread; the values travel
        // as arguments so a path can never be interpreted as script.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, session.terminalDevice ?? "", session.projectPath]
        try? process.run()
    }
}
