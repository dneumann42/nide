import std/[os, strutils]

proc projectBackend*(nimblePath: string): string {.raises: [].} =
  ## Return the backend declared in the .nimble file, defaulting to "c".
  try:
    for line in nimblePath.readFile.splitLines:
      let stripped = line.strip()
      if stripped.startsWith("backend"):
        let eq = stripped.find('=')
        if eq < 0: continue
        let rhs = stripped[eq + 1 .. ^1].strip()
        let q1 = rhs.find('"')
        if q1 < 0: continue
        let q2 = rhs.find('"', q1 + 1)
        if q2 <= q1: continue
        let backend = rhs[q1 + 1 ..< q2].strip()
        if backend.len > 0:
          return backend
  except:
    discard
  "c"

proc findProjectMain*(nimblePath: string): string {.raises: [].} =
  ## Given a .nimble file path, return the main .nim entry point.
  ## Resolution order:
  ##   1. First `bin = ...` entry whose src/<name>.nim exists
  ##   2. src/<nimble-name>.nim
  ##   3. <nimble-name>.nim at project root
  ##   4. "" if nothing found
  try:
    let dir = nimblePath.parentDir()
    let defaultName = nimblePath.splitFile().name
    for line in nimblePath.readFile.splitLines:
      let stripped = line.strip()
      if stripped.startsWith("bin"):
        let eq = stripped.find('=')
        if eq < 0: continue
        let rhs = stripped[eq + 1 .. ^1].strip()
        let q1 = rhs.find('"')
        if q1 < 0: continue
        let q2 = rhs.find('"', q1 + 1)
        if q2 <= q1: continue
        let binName = rhs[q1 + 1 ..< q2]
        let candidate = dir / "src" / binName & ".nim"
        if candidate.fileExists: return candidate
    let srcMain = dir / "src" / defaultName & ".nim"
    if srcMain.fileExists: return srcMain
    let rootMain = dir / defaultName & ".nim"
    if rootMain.fileExists: return rootMain
  except: discard
  return ""

proc findProjectRoot*(path: string): string {.raises: [].} =
  ## Find the nearest ancestor directory that looks like a Nim project root.
  ## Prefer a directory containing a .nimble file, then fall back to config.nims.
  try:
    var dir =
      if path.dirExists: path
      elif path.fileExists: path.parentDir()
      else: path.parentDir()
    var prev = ""
    while dir.len > 0 and dir != prev:
      for entry in walkDir(dir):
        if entry.kind == pcFile and entry.path.endsWith(".nimble"):
          return dir
      if fileExists(dir / "config.nims"):
        return dir
      prev = dir
      dir = dir.parentDir()
  except:
    discard
  ""

proc projectDependencyPaths*(projectRoot: string): seq[string] {.raises: [].} =
  ## Read nimbledeps/nimble.paths.nims and expand the generated path entries to
  ## absolute package roots. This avoids relying on include-time thisDir()
  ## semantics, which are inconsistent in this environment.
  let pathsFile = projectRoot / "nimbledeps" / "nimble.paths.nims"
  if projectRoot.len == 0 or not fileExists(pathsFile):
    return

  let nimbleDepsDir = projectRoot / "nimbledeps"
  try:
    for rawLine in readFile(pathsFile).splitLines:
      let line = rawLine.strip()
      let amp = line.find('&')
      if amp < 0:
        continue
      let q1 = line.find('"', amp)
      let q2 = line.rfind('"')
      if q1 < 0 or q2 <= q1:
        continue
      var suffix = line[q1 + 1 ..< q2].strip()
      while suffix.len > 0 and (suffix[0] == '/' or suffix[0] == '\\'):
        suffix = suffix[1 .. ^1]
      if suffix.len == 0:
        continue
      result.add(nimbleDepsDir / suffix)
  except:
    discard

proc projectDependencyPathArgs*(projectRoot: string): seq[string] {.raises: [].} =
  for path in projectDependencyPaths(projectRoot):
    result.add("--path:" & path)
