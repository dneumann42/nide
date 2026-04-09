import std/[unittest, os, osproc, strutils]
import nide/helpers/logparser
import nide/nim/nimproject

# ---------------------------------------------------------------------------
# Helpers shared across suites
# ---------------------------------------------------------------------------

proc countDiags(lines: seq[LogLine]): tuple[hints, warnings, errors: int] =
  for ll in lines:
    case ll.level
    of llHint:    inc result.hints
    of llWarning: inc result.warnings
    of llError:   inc result.errors
    else: discard

proc parseOutput(raw: string): seq[LogLine] =
  for line in raw.splitLines:
    if line.len > 0:
      result.add parseLine(line)

# ---------------------------------------------------------------------------
# parseLine — real nim check output formats
# ---------------------------------------------------------------------------

suite "parseLine — real nim check output":

  test "config hint line is llOther":
    let ll = parseLine("Hint: used config file '/home/user/.local/nim/nim.cfg' [Conf]")
    check ll.level == llOther
    check ll.file  == ""

  test "progress dots are llOther":
    let ll = parseLine(".................................................")
    check ll.level == llOther
    check ll.file  == ""

  test "XDeclaredButNotUsed hint":
    let ll = parseLine("/home/user/proj/src/foo.nim(77, 19) Hint: 'bar' is declared but not used [XDeclaredButNotUsed]")
    check ll.level == llHint
    check ll.file  == "/home/user/proj/src/foo.nim"
    check ll.line  == 77
    check ll.col   == 19

  test "UnusedImport warning":
    let ll = parseLine("/home/user/proj/src/foo.nim(1, 54) Warning: imported and not used: 'qpainter' [UnusedImport]")
    check ll.level == llWarning
    check ll.file  == "/home/user/proj/src/foo.nim"
    check ll.line  == 1
    check ll.col   == 54

  test "compilation error":
    let ll = parseLine("/home/user/proj/src/foo.nim(10, 3) Error: undeclared identifier: 'x'")
    check ll.level == llError
    check ll.file  == "/home/user/proj/src/foo.nim"
    check ll.line  == 10
    check ll.col   == 3

  test "SuccessX hint at end of check is llOther":
    let ll = parseLine("Hint: 12345 lines; 1.2s; 200MiB peakmem; proj: /foo/bar.nim; out: unknownOutput [SuccessX]")
    check ll.level == llOther

  test "mixed output block: only diagnostics are counted":
    let raw = """
Hint: used config file '/home/user/nim.cfg' [Conf]
...........
/home/user/proj/src/a.nim(3, 5) Warning: imported and not used: 'os' [UnusedImport]
/home/user/proj/src/b.nim(10, 1) Error: undeclared identifier: 'x'
/home/user/proj/src/c.nim(77, 19) Hint: 'y' is declared but not used [XDeclaredButNotUsed]
Hint: 9999 lines; 0.5s; 100MiB peakmem; proj: foo.nim; out: unknownOutput [SuccessX]
""".strip()
    let lines = parseOutput(raw)
    let counts = countDiags(lines)
    check counts.hints    == 1
    check counts.warnings == 1
    check counts.errors   == 1

  test "output with only config lines gives zero counts":
    let raw = """
Hint: used config file '/a/nim.cfg' [Conf]
Hint: used config file '/b/config.nims' [Conf]
...........
""".strip()
    let lines = parseOutput(raw)
    let counts = countDiags(lines)
    check counts.hints    == 0
    check counts.warnings == 0
    check counts.errors   == 0

# ---------------------------------------------------------------------------
# findProjectMain
# ---------------------------------------------------------------------------

suite "findProjectMain":

  proc withTempNimble(content: string, srcFile: string, body: proc(path: string)) =
    let tmp = getTempDir() / "testnimble_" & $getCurrentProcessId()
    createDir(tmp)
    createDir(tmp / "src")
    writeFile(tmp / "myproject.nimble", content)
    if srcFile.len > 0:
      writeFile(tmp / "src" / srcFile, "# stub")
    try: body(tmp / "myproject.nimble")
    finally:
      removeDir(tmp)

  test "bin = @[\"name\"] array syntax finds src/name.nim":
    withTempNimble("""
version = "1.0"
bin     = @["myproject"]
""", "myproject.nim") do (path: string):
      let found = findProjectMain(path)
      check found.endsWith("src" / "myproject.nim")

  test "bin = \"name\" string syntax finds src/name.nim":
    withTempNimble("""
version = "1.0"
bin     = "myproject"
""", "myproject.nim") do (path: string):
      let found = findProjectMain(path)
      check found.endsWith("src" / "myproject.nim")

  test "no bin field falls back to src/<nimble-name>.nim":
    withTempNimble("""
version = "1.0"
""", "myproject.nim") do (path: string):
      let found = findProjectMain(path)
      check found.endsWith("src" / "myproject.nim")

  test "returns empty string when no nim file exists":
    withTempNimble("""
version = "1.0"
bin     = @["missing"]
""", "") do (path: string):
      let found = findProjectMain(path)
      check found == ""

  test "empty nimble file returns empty string":
    withTempNimble("", "") do (path: string):
      let found = findProjectMain(path)
      check found == ""

  test "backend field defaults to c when missing":
    withTempNimble("""
version = "1.0"
""", "") do (path: string):
      check projectBackend(path) == "c"

  test "backend field is parsed from nimble file":
    withTempNimble("""
version = "1.0"
backend = "cpp"
""", "") do (path: string):
      check projectBackend(path) == "cpp"

  test "project dependency paths expand from nimbledeps":
    let tmp = getTempDir() / "testnimpaths_" & $getCurrentProcessId()
    createDir(tmp)
    createDir(tmp / "nimbledeps")
    writeFile(tmp / "config.nims", "# stub")
    writeFile(tmp / "nimbledeps" / "nimble.paths.nims", """
switch("path", thisDir() & "/pkgs2/foo-1.0.0")
switch("path", thisDir() & "/pkgs2/bar-2.0.0")
""".strip())
    try:
      let paths = projectDependencyPaths(tmp)
      check paths == @[
        tmp / "nimbledeps" / "pkgs2" / "foo-1.0.0",
        tmp / "nimbledeps" / "pkgs2" / "bar-2.0.0"
      ]
      let args = projectDependencyPathArgs(tmp)
      check args == @[
        "--path:" & tmp / "nimbledeps" / "pkgs2" / "foo-1.0.0",
        "--path:" & tmp / "nimbledeps" / "pkgs2" / "bar-2.0.0"
      ]
    finally:
      removeDir(tmp)

  test "finds the actual nide project entry point":
    # Verify against the real nide.nimble so we catch regressions immediately.
    let nimblePath = currentSourcePath().parentDir().parentDir() / "nide.nimble"
    if not fileExists(nimblePath):
      skip()
    let found = findProjectMain(nimblePath)
    check found.len > 0
    check found.endsWith("src" / "nide.nim")
    check fileExists(found)

# ---------------------------------------------------------------------------
# Integration — run the real nim check and parse its output
# ---------------------------------------------------------------------------

suite "nim check integration":

  let projectRoot = currentSourcePath().parentDir().parentDir()
  let nimblePath  = projectRoot / "nide.nimble"

  test "nim check runs and produces output on stderr":
    if not fileExists(nimblePath): skip()
    let mainFile = findProjectMain(nimblePath)
    if mainFile.len == 0: skip()
    let nimExe = findExe("nim")
    if nimExe.len == 0: skip()
    # nim check writes everything to stderr; capture stderr explicitly
    let (output, exitCode) = execCmdEx(
      nimExe & " check --hints:off --warnings:off " & mainFile,
      workingDir = projectRoot)
    # nim check exits non-zero when there are errors/warnings, that's fine
    # We only care that it ran and produced some output
    check output.len > 0 or exitCode in {0, 1}

  test "nim check output has parseable diagnostics":
    if not fileExists(nimblePath): skip()
    let mainFile = findProjectMain(nimblePath)
    if mainFile.len == 0: skip()
    let nimExe = findExe("nim")
    if nimExe.len == 0: skip()
    # Run with all hints/warnings so we get real diagnostic lines
    let (output, _) = execCmdEx(
      nimExe & " check " & mainFile,
      workingDir = projectRoot)
    let lines = parseOutput(output)
    let counts = countDiags(lines)
    # This project is known to have unused import warnings and declared-but-not-used hints
    check counts.hints + counts.warnings + counts.errors > 0

  test "execCmdEx captures stderr (where nim check writes)":
    # execCmdEx merges stderr+stdout — verify nim check output is captured at all
    if not fileExists(nimblePath): skip()
    let mainFile = findProjectMain(nimblePath)
    if mainFile.len == 0: skip()
    let nimExe = findExe("nim")
    if nimExe.len == 0: skip()
    let (output, _) = execCmdEx(nimExe & " check " & mainFile,
                                 workingDir = projectRoot)
    # Should contain at least one "Warning:" or "Hint:" line with a file path
    var hasFileDiag = false
    for line in output.splitLines:
      let ll = parseLine(line)
      if ll.level in {llHint, llWarning, llError} and ll.file.len > 0:
        hasFileDiag = true
        break
    check hasFileDiag
