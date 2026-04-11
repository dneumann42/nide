import std/[os, unittest]

import nide/project/filefinder
import nide/ui/filepreview

const TestRoot = "/tmp/nide-test-gitignore"
const PreviewTestRoot = "/tmp/nide-test-filepreview"
const RepoRoot = currentSourcePath.parentDir.parentDir

suite "gitignore loading":
  setup:
    createDir(TestRoot)
    setCurrentDir(TestRoot)

  teardown:
    setCurrentDir("/tmp")
    removeDir(TestRoot)

  test "empty .gitignore produces no patterns":
    gitignorePatterns.setLen(0)
    gitignoreRoot = ""
    check matchesGitignore("some/path") == false

  test "simple filename pattern *.log matches .log files":
    gitignorePatterns = @["*.log"]
    gitignoreRoot = TestRoot
    check matchesGitignore(TestRoot / "error.log") == true
    check matchesGitignore(TestRoot / "foo.txt") == false

  test "directory pattern matches files inside":
    gitignorePatterns = @["nimbledeps"]
    gitignoreRoot = TestRoot
    check matchesGitignore(TestRoot / "nimbledeps" / "pkgs" / "foo.nim") == true
    check matchesGitignore(TestRoot / "src" / "main.nim") == false

  test "wildcard prefix *.log matches .log files":
    gitignorePatterns = @["*.log"]
    gitignoreRoot = TestRoot
    check matchesGitignore(TestRoot / "error.log") == true

  test "wildcard suffix foo* matches foobar":
    gitignorePatterns = @["foo*"]
    gitignoreRoot = TestRoot
    check matchesGitignore(TestRoot / "foobar") == true
    check matchesGitignore(TestRoot / "barfoo") == false

  test "wildcard both *test* matches anywhere":
    gitignorePatterns = @["*test*"]
    gitignoreRoot = TestRoot
    check matchesGitignore(TestRoot / "mytest.nim") == true
    check matchesGitignore(TestRoot / "test" / "file.nim") == true
    check matchesGitignore(TestRoot / "main.nim") == false

  test "exact match":
    gitignorePatterns = @["exact.nim"]
    gitignoreRoot = TestRoot
    check matchesGitignore(TestRoot / "exact.nim") == true
    check matchesGitignore(TestRoot / "other.nim") == false

suite "loadGitignore":
  setup:
    createDir(TestRoot)
    setCurrentDir(TestRoot)
    gitignorePatterns.setLen(0)
    gitignoreRoot = ""

  teardown:
    setCurrentDir("/tmp")
    removeDir(TestRoot)

  test "loads root .gitignore":
    writeFile(TestRoot / ".gitignore", "*.log\nbuild/\n")
    loadGitignore(TestRoot)
    check "*.log" in gitignorePatterns
    check "build/*" in gitignorePatterns

  test "ignores comments and empty lines":
    writeFile(TestRoot / ".gitignore", "# comment\n\n*.log\n")
    loadGitignore(TestRoot)
    check "*.log" in gitignorePatterns
    check "# comment" notin gitignorePatterns

  test "ignores negation patterns":
    writeFile(TestRoot / ".gitignore", "*.log\n!important.nim\n")
    loadGitignore(TestRoot)
    check "*.log" in gitignorePatterns
    check "!important.nim" notin gitignorePatterns

  test "adds built-in ignored directories":
    writeFile(TestRoot / ".gitignore", "")
    loadGitignore(TestRoot)
    check gitignorePatterns.len > 0
  
  test "loads subdirectory .gitignore":
    createDir(TestRoot / "subdir")
    writeFile(TestRoot / ".gitignore", "")
    writeFile(TestRoot / "subdir" / ".gitignore", "secret.nim\n")
    loadGitignore(TestRoot)
    check "subdir/secret.nim" in gitignorePatterns or "subdir\\secret.nim" in gitignorePatterns

suite "file preview loading":
  setup:
    createDir(PreviewTestRoot)

  teardown:
    removeDir(PreviewTestRoot)

  test "text sample without NUL is not binary":
    check isBinarySample("let answer = 42\n") == false

  test "sample containing NUL is binary":
    check isBinarySample("abc" & '\0' & "def") == true

  test "empty file is previewed as text":
    let path = PreviewTestRoot / "empty.txt"
    writeFile(path, "")
    let (kind, content) = loadFilePreview(path)
    check kind == fpkText
    check content == ""

  test "binary file returns placeholder":
    let path = PreviewTestRoot / "image.bin"
    writeFile(path, "abc" & '\0' & "def")
    let (kind, content) = loadFilePreview(path)
    check kind == fpkBinary
    check content == BinaryPreviewPlaceholder

  test "known image file is previewed as image":
    let (kind, content) = loadFilePreview(RepoRoot / "screenshot.png")
    check kind == fpkImage
    check content == ""

  test "missing file returns read error placeholder":
    let (kind, content) = loadFilePreview(PreviewTestRoot / "missing.txt")
    check kind == fpkError
    check content == PreviewReadErrorPlaceholder
