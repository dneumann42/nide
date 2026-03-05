import std/[os, strutils]
import seaqt/[qprocess, qobject]
import bench/logparser

proc runNimCheck*(
    parentH:  pointer,
    filePath: string,
    cancelH:  ref pointer,
    onDone:   proc(lines: seq[LogLine]) {.raises: [].}
) {.raises: [].} =
  try:
    var process = QProcess.create(QObject(h: parentH, owned: false))
    process.owned = false
    let processH = process.h
    cancelH[] = processH

    var allOutput: ref string
    new(allOutput); allOutput[] = ""

    process.setProcessChannelMode(cint 1)  # MergedChannels
    process.setWorkingDirectory(getCurrentDir())

    process.onReadyReadStandardOutput do() {.raises: [].}:
      try:
        let bytes = QProcess(h: processH, owned: false).readAllStandardOutput()
        if bytes.len > 0:
          var s = newString(bytes.len)
          for i in 0..<bytes.len: s[i] = char(bytes[i])
          allOutput[] &= s
      except: discard

    process.onFinished do(exitCode: cint) {.raises: [].}:
      try:
        let bytes = QProcess(h: processH, owned: false).readAllStandardOutput()
        if bytes.len > 0:
          var s = newString(bytes.len)
          for i in 0..<bytes.len: s[i] = char(bytes[i])
          allOutput[] &= s
        cancelH[] = nil
        var lines: seq[LogLine]
        for rawLine in allOutput[].splitLines():
          if rawLine.len > 0:
            lines.add(parseLine(rawLine))
        onDone(lines)
      except: discard

    process.start("nim", @["check", filePath])
  except: discard
