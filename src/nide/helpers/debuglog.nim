import std/[logging, os]
export logging

import nide/helpers/appdirs

proc nideLogPath*(): string =
  nideDataDirPath() / "nide.log"

proc setupLogging*() =
  let dir = nideDataDirPath()
  if not dirExists(dir):
    createDir(dir)
  addHandler(newFileLogger(nideLogPath(),
    fmtStr="[$datetime] $levelname: "))

proc clearLog*() {.raises: [].} =
  try:
    let path = nideLogPath()
    if fileExists(path):
      removeFile(path)
  except CatchableError:
    discard

proc trimForLog*(text: string, maxLen = 4000): string =
  if text.len <= maxLen:
    return text
  text[0 ..< maxLen] & "\n...[truncated]"

# Safe wrappers for std/logging in {.raises: [].} procs.
# std/logging templates raise Exception, but these are safe in practice
# since the FileLogger internally handles I/O errors.

template logDebug*(args: varargs[string, `$`]) =
  {.cast(raises: []).}: debug(args)

template logInfo*(args: varargs[string, `$`]) =
  {.cast(raises: []).}: info(args)

template logWarn*(args: varargs[string, `$`]) =
  {.cast(raises: []).}: warn(args)

template logError*(args: varargs[string, `$`]) =
  {.cast(raises: []).}: error(args)
