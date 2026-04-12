import std/[options, os, unittest]

import nide/editor/syntaxdefs

suite "syntax definitions":
  test "bundled registry maps c-family headers to cpp":
    let registry = loadSyntaxRegistry()
    let syntax = registry.syntaxForPath("/tmp/demo.hpp")
    check syntax.isSome()
    check syntax.get().id == "cpp"
    check registry.syntaxForPath("/tmp/demo.HXX").get().id == "cpp"

  test "bundled registry maps nim family files to nim lexer":
    let registry = loadSyntaxRegistry()
    check registry.syntaxForPath("/tmp/demo.nim").get().engine == seNimLexer
    check registry.syntaxForPath("/tmp/demo.nimble").get().id == "nim"
    check registry.syntaxForPath("/tmp/demo.nimcfg").get().id == "nim"

  test "bundled registry maps sushi files to sushi syntax":
    let registry = loadSyntaxRegistry()
    let syntax = registry.syntaxForPath("/tmp/demo.sushi")
    check syntax.isSome()
    check syntax.get().id == "sushi"
    check syntax.get().engine == seRegex

  test "unknown extensions resolve to no syntax":
    let registry = loadSyntaxRegistry()
    check registry.syntaxForPath("/tmp/demo.unknown").isNone()

  test "user override replaces bundled definition by id":
    let tempRoot = getTempDir() / "nide-syntaxdefs-replace"
    let bundledDir = tempRoot / "bundled"
    let userDir = tempRoot / "user"
    createDir(tempRoot)
    createDir(bundledDir)
    createDir(userDir)
    writeFile(bundledDir / "cpp.toml", """
id = "cpp"
engine = "regex"
extensions = [".hpp", ".h"]

[[rules]]
pattern = "foo"
kind = "keyword"
""")
    writeFile(userDir / "cpp.toml", """
id = "cpp"
engine = "regex"
extensions = [".cxx"]

[[rules]]
pattern = "bar"
kind = "keyword"
""")

    let registry = loadSyntaxRegistry(@[bundledDir], userDir)
    check registry.syntaxForExtension(".hpp").isNone()
    check registry.syntaxForExtension(".cxx").get().id == "cpp"

    removeDir(tempRoot)

  test "resolved syntax exposes the configured engine":
    check loadSyntaxRegistry().syntaxForPath("/tmp/main.nim").get().engine == seNimLexer
    check loadSyntaxRegistry().syntaxForPath("/tmp/main.hpp").get().engine == seRegex
