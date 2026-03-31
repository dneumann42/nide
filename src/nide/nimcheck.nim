import std/[os, strutils]
import seaqt/[qprocess, qobject]
import logparser
import qtconst

proc runNimCheck*(
    parentH:  pointer,
    filePath: string,
    cancelH:  ref pointer,
    onDone:   proc(lines: seq[LogLine]) {.raises: [].}
) {.raises: [].} =
  try:
    let nimExe = findExe("nim")
    if nimExe.len == 0: return

    var process = QProcess.create(QObject(h: parentH, owned: false))
    process.owned = false
    let processH = process.h
    cancelH[] = processH

    # nim check writes everything to stderr; MergedChannels routes it through
    # readAllStandardOutput / readyReadStandardOutput.
    process.setProcessChannelMode(PC_MergedChannels)  # MergedChannels
    process.setWorkingDirectory(getCurrentDir())

    # Accumulate output incrementally so Qt's pipe buffer never fills up.
    var allOutput: ref string
    new(allOutput); allOutput[] = ""

    process.onReadyReadStandardOutput do() {.raises: [].}:
      try:
        let bytes = QProcess(h: processH, owned: false).readAllStandardOutput()
        if bytes.len > 0:
          var s = newString(bytes.len)
          for i in 0..<bytes.len: s[i] = char(bytes[i])
          allOutput[] &= s
      except: discard

    process.onErrorOccurred do(err: cint) {.raises: [].}:
      # Only clear cancelH if we're still the current process. When kill() is
      # called on us to make room for a new check, cancelH[] will already point
      # to the new process — don't clobber it.
      if cancelH[] == processH:
        cancelH[] = nil

    process.onFinished do(exitCode: cint) {.raises: [].}:
      try:
        # If we were killed to make room for a newer check, skip delivering
        # stale results so the new check's onDone fires unobstructed.
        if cancelH[] != processH: return
        # Drain any output not yet picked up by onReadyReadStandardOutput.
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

    process.start(nimExe, @["check", filePath])
  except: discard
