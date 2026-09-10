import AppKit
import Foundation
import DayLineCore

let arguments = CommandLine.arguments.dropFirst()
if arguments.contains("--help") || arguments.contains("-h") {
    print("用法：DayLine [--desktop | --quit]\n\n不带参数时打开日程；--desktop 只显示桌面卡片；--quit 退出正在运行的 DayLine。")
    exit(0)
}
if arguments.contains("--quit") {
    // Avoid launching AppKit, the database, or notification services merely to
    // ask an already-running instance to terminate.
    let lock = SingleInstance(dataDirectory: DataPaths.shared.directory)
    if !lock.isPrimary { lock.send("quit") }
    exit(0)
}

let application = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
