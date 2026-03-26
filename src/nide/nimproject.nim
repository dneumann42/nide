import std/[os, strutils]

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
