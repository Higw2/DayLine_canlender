import Darwin
import Foundation

enum InstallerError: LocalizedError {
    case invalidArguments
    case parentNotWritable
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments: return "更新辅助程序参数无效"
        case .parentNotWritable: return "应用所在目录不可写"
        case .copyFailed(let message): return message
        }
    }
}

func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw InstallerError.copyFailed("\(executable) 执行失败（\(process.terminationStatus)）")
    }
}

func install() throws {
    guard CommandLine.arguments.count == 4,
          let pid = Int32(CommandLine.arguments[3]) else { throw InstallerError.invalidArguments }

    let fileManager = FileManager.default
    let target = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    let staged = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
    let parent = target.deletingLastPathComponent()
    guard fileManager.isWritableFile(atPath: parent.path) else { throw InstallerError.parentNotWritable }

    while kill(pid, 0) == 0 { Thread.sleep(forTimeInterval: 0.2) }

    let suffix = UUID().uuidString
    let incoming = parent.appendingPathComponent(".DayLine-update-\(suffix).app")
    let backup = parent.appendingPathComponent(".DayLine-previous-\(suffix).app")
    defer {
        try? fileManager.removeItem(at: incoming)
        try? fileManager.removeItem(at: backup)
    }

    try run("/usr/bin/ditto", [staged.path, incoming.path])
    do {
        try fileManager.moveItem(at: target, to: backup)
        try fileManager.moveItem(at: incoming, to: target)
    } catch {
        if !fileManager.fileExists(atPath: target.path), fileManager.fileExists(atPath: backup.path) {
            try? fileManager.moveItem(at: backup, to: target)
        }
        throw error
    }

    try run("/usr/bin/open", [target.path])
}

do {
    try install()
} catch {
    if CommandLine.arguments.count > 1 {
        try? run("/usr/bin/open", [CommandLine.arguments[1]])
    }
    let message = "DayLine 更新失败：\(error.localizedDescription)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
