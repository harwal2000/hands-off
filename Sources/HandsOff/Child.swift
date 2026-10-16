import Foundation
import HandsOffCore

/// The wrapped command. If handsoff is interrupted, the command is stopped too and the keyboard let go, so an
/// agent's timeout never leaves "Hands off" showing.
enum Child {
    nonisolated(unsafe) private static var current: Process?

    static func run(_ command: [String], holder: Int32) -> Int32 {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/env")
        p.arguments = command
        var env = ProcessInfo.processInfo.environment
        env["HANDSOFF_HOLDER"] = String(holder)
        p.environment = env
        do { try p.run() } catch {
            FileHandle.standardError.write(Data("handsoff: couldn't run \(command[0]): \(error.localizedDescription)\n".utf8))
            return 127
        }
        current = p
        p.waitUntilExit()
        current = nil
        return p.terminationReason == .uncaughtSignal ? 128 + p.terminationStatus : p.terminationStatus
    }

    static func stop() { current?.terminate() }
}

enum Cleanup {
    nonisolated(unsafe) private static var sources: [DispatchSourceSignal] = []

    static func install(store: StateStore, pid: Int32) {
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            source.setEventHandler {
                Child.stop()
                store.release(pid: pid)
                store.removeWaiter(pid: pid)
                exit(128 + sig)
            }
            source.resume()
            sources.append(source)
        }
    }
}
