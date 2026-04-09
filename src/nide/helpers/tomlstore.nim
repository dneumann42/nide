import std/os

import toml_serialization

import nide/helpers/appdirs

proc loadTomlFile*[T](path: string, _: typedesc[T], label: string): T {.raises: [].} =
  try:
    if fileExists(path):
      result = Toml.loadFile(path, T)
  except CatchableError as e:
    echo "Failed to load ", label, ": ", e.msg

proc saveTomlFile*[T](path: string, value: T, label: string): bool {.raises: [].} =
  let dirPath = path.parentDir()
  if dirPath.len > 0 and not ensureDirExists(dirPath):
    return false
  try:
    Toml.saveFile(path, value)
    true
  except CatchableError as e:
    echo "Failed to save ", label, ": ", e.msg
    false
