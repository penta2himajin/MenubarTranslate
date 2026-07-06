import Foundation
import MenubarTranslateCore

#if canImport(Darwin)
import Darwin
#endif

// Thin forwarder: read any piped stdin, then hand everything to the (testable) driver.
let args = Array(CommandLine.arguments.dropFirst())

var stdinText: String?
if isatty(FileHandle.standardInput.fileDescriptor) == 0 {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    stdinText = String(data: data, encoding: .utf8)
}

let out = FileHandleSink(FileHandle.standardOutput)
let err = FileHandleSink(FileHandle.standardError)

let code = await CommandLineDriver().run(args, stdin: stdinText, out: out, err: err)
exit(code)
