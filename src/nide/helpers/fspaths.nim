import std/[os, strutils]

proc pathExistsAny*(path: string): bool =
  fileExists(path) or dirExists(path)

proc normalizedFsPath*(path: string): string =
  try:
    result = normalizePathEnd(normalizedPath(absolutePath(path)), false)
  except CatchableError:
    result = normalizePathEnd(normalizedPath(path), false)
  when defined(windows):
    result = result.toLowerAscii()

proc isSameOrChildPath*(path, root: string): bool =
  let normalizedPath = normalizedFsPath(path)
  let normalizedRoot = normalizedFsPath(root)
  var prefix = normalizedRoot
  prefix.add(DirSep)
  normalizedPath == normalizedRoot or normalizedPath.startsWith(prefix)

proc remapPath*(oldPath, oldRoot, newRoot: string): string {.raises: [].} =
  let normalizedOldPath = normalizedFsPath(oldPath)
  let normalizedOldRoot = normalizedFsPath(oldRoot)
  let normalizedNewRoot = normalizedFsPath(newRoot)
  if normalizedOldPath == normalizedOldRoot:
    normalizedNewRoot
  else:
    try:
      normalizedNewRoot / relativePath(normalizedOldPath, normalizedOldRoot)
    except Exception:
      normalizedNewRoot / oldPath.lastPathPart()
