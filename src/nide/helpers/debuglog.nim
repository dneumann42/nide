import std/[os, strutils, times]

proc debugLogPath*(baseDir = ""): string =
  let dir =
    if baseDir.len > 0:
      baseDir
    else:
      try:
        getCurrentDir()
      except CatchableError:
        getTempDir()
  dir / ".nide-debug.log"

proc trimForLog*(text: string, maxLen = 4000): string =
  if text.len <= maxLen:
    return text
  text[0 ..< maxLen] & "\n...[truncated]"

proc appendDebugLog*(component, message: string, baseDir = "") {.raises: [].} =
  try:
    let stamp = now().format("yyyy-MM-dd HH:mm:ss")
    let line = "[" & stamp & "] [" & component & "] " & message.strip() & "\n"
    let path = debugLogPath(baseDir)
    let dir = path.parentDir()
    if dir.len > 0 and not dirExists(dir):
      createDir(dir)
    var f = open(path, fmAppend)
    try:
      f.write(line)
    finally:
      f.close()
  except CatchableError:
    discard

proc clearDebugLog*(baseDir = "") {.raises: [].} =
  try:
    let path = debugLogPath(baseDir)
    if fileExists(path):
      removeFile(path)
  except CatchableError:
    discard
