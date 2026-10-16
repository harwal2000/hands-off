import AppKit

// One executable: launched with no arguments (Finder, `open`, login) it is the menu bar app; with a subcommand
// (`handsoff …`, a symlink to this file) it is the command-line tool.
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.isEmpty {
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    app.setActivationPolicy(.accessory)
    app.run()
} else {
    exit(CLI.run(arguments))
}
