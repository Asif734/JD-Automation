import Foundation

let projectDir = "/Users/dnying/Documents/Codex/2026-05-15/https-rulechannel-tmall-com-spm-a2177"
let commandFile = "\(projectDir)/scripts/run_qianniu_rag_bot.command"
let launcherLog = "\(projectDir)/outputs/qianniu_bot/launcher.log"

try? FileManager.default.createDirectory(
    atPath: "\(projectDir)/outputs/qianniu_bot",
    withIntermediateDirectories: true
)
FileManager.default.createFile(atPath: launcherLog, contents: nil)
let logHandle = FileHandle(forWritingAtPath: launcherLog)
logHandle?.seekToEndOfFile()

let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/zsh")
process.arguments = [commandFile]
process.currentDirectoryURL = URL(fileURLWithPath: projectDir)
if let logHandle {
    process.standardOutput = logHandle
    process.standardError = logHandle
}

do {
    try process.run()
} catch {
    fputs("Failed to start QianNiu RAG bot: \(error)\n", stderr)
    exit(1)
}

process.waitUntilExit()
exit(process.terminationStatus)
