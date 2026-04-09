import std/os

const
  NideDataDirName* = ".local" / "nide"
  NideConfigDirName* = "nide"

proc nideDataDirPath*(): string =
  getHomeDir() / NideDataDirName

proc nideConfigDirPath*(): string =
  getConfigDir() / NideConfigDirName

proc ensureDirExists*(path: string): bool {.raises: [].} =
  try:
    if not dirExists(path):
      createDir(path)
    true
  except OSError, IOError:
    echo getCurrentExceptionMsg()
    false
