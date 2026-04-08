import std/[unittest, sets, strutils]
import nide/nim/nimimports

import nide/helpers/logparser

proc unusedHint(file, module: string, line = 1): LogLine =
  let raw = file & "(" & $line & ", 1) Hint: imported and not used: '" & module & "' [UnusedImport]"
  parseLine(raw)

suite "collectUnusedModules":
  test "extracts bare module name from UnusedImport hint":
    let diags = @[unusedHint("/a/b.nim", "strutils")]
    let unused = collectUnusedModules(diags, "/a/b.nim")
    check "strutils" in unused

  test "filters by file path":
    let diags = @[unusedHint("/other.nim", "os"), unusedHint("/mine.nim", "strutils")]
    let unused = collectUnusedModules(diags, "/mine.nim")
    check "strutils" in unused
    check "os" notin unused

  test "ignores non-UnusedImport hints":
    let diags = @[parseLine("/a.nim(1, 1) Error: undeclared identifier: 'foo'")]
    let unused = collectUnusedModules(diags, "/a.nim")
    check unused.len == 0

  test "collects multiple unused modules":
    let diags = @[unusedHint("/f.nim", "os"), unusedHint("/f.nim", "strutils")]
    let unused = collectUnusedModules(diags, "/f.nim")
    check "os" in unused
    check "strutils" in unused

suite "reorganizeImports - basic":
  test "no-op when no unused":
    let src = "import os\n\necho 1\n"
    check reorganizeImports(src, initHashSet[string]()) == src

  test "removes a single unused import":
    let src = "import os\nimport strutils\n\necho 1\n"
    let r = reorganizeImports(src, toHashSet(["os"]))
    check "os" notin r
    check "strutils" in r
    check "echo 1" in r

  test "removes all modules from a line":
    let src = "import os\n\necho 1\n"
    let r = reorganizeImports(src, toHashSet(["os"]))
    check "import" notin r
    check "echo 1" in r

  test "preserves non-import lines":
    let src = "import os\n\nproc foo() = discard\n"
    let r = reorganizeImports(src, initHashSet[string]())
    check "proc foo() = discard" in r

suite "reorganizeImports - grouping":
  test "groups two modules from same parent":
    let src = "import std/strutils\nimport std/sequtils\n"
    let r = reorganizeImports(src, initHashSet[string]())
    check "import std/[sequtils, strutils]" in r

  test "single module from parent stays ungrouped":
    let src = "import std/strutils\n"
    let r = reorganizeImports(src, initHashSet[string]())
    check "import std/strutils" in r
    check "[" notin r

  test "no-parent imports are combined into one line":
    let src = "import os\nimport strutils\n"
    let r = reorganizeImports(src, initHashSet[string]())
    check "import os, strutils" in r

  test "groups three modules alphabetically":
    let src = "import std/strutils\nimport std/os\nimport std/sequtils\n"
    let r = reorganizeImports(src, initHashSet[string]())
    check "import std/[os, sequtils, strutils]" in r

  test "bracket-form import is expanded then regrouped":
    let src = "import std/[strutils, sequtils]\n"
    let r = reorganizeImports(src, initHashSet[string]())
    check "import std/[sequtils, strutils]" in r

  test "removes one module from bracket group":
    let src = "import std/[strutils, sequtils, os]\n\necho 1\n"
    let r = reorganizeImports(src, toHashSet(["os"]))
    check "os" notin r
    check "import std/[sequtils, strutils]" in r

suite "reorganizeImports - application.nim case":
  # Reproduces the imports that were mangled when the tool ran on itself.
  # Validates correct handling of multi-line bracket imports.
  const appImports = """import std/[os, strutils]
import toml_serialization
import seaqt/[qapplication, qwidget, qfiledialog, qmainwindow, qtoolbar, qsplitter,
              qcoreapplication, qtoolbutton, qabstractbutton,
              qshortcut, qkeysequence, qobject, qgraphicsopacityeffect,
              qplaintextedit, qtextdocument, qtextcursor, qtextedit,
              qresizeevent, qfilesystemwatcher, qtimer]

import toolbar, buffers, projects, projectdialog, moduledialog, theme, pane, runner,
              filefinder, rgfinder, settings, widgetref, panemanager, syntaxtheme, themedialog,
              nimsuggest, filetree, graphdialog, opacity
import commands
import "../../tools/nim_graph" as nim_graph

type
  App = ref object
    x: int
"""

  test "no-op with no unused modules preserves all content":
    let r = reorganizeImports(appImports, initHashSet[string]())
    check "toml_serialization" in r
    check "qapplication" in r
    check "qtimer" in r
    check "toolbar" in r
    check "commands" in r
    check "type" in r
    check "App = ref object" in r

  test "preserves modules from continuation lines":
    let r = reorganizeImports(appImports, initHashSet[string]())
    check "filefinder" in r
    check "rgfinder" in r
    check "panemanager" in r
    check "nimsuggest" in r
    check "              filefinder" notin r

  test "removes one seaqt module, keeps rest":
    let r = reorganizeImports(appImports, toHashSet(["qtimer"]))
    check "qtimer" notin r
    check "qapplication" in r
    check "qwidget" in r

  test "removes one std module, keeps other":
    let r = reorganizeImports(appImports, toHashSet(["os"]))
    check "os" notin r
    check "strutils" in r

  test "removes both std modules, drops std import entirely":
    let r = reorganizeImports(appImports, toHashSet(["os", "strutils"]))
    check "std/" notin r
    check "toml_serialization" in r

suite "reorganizeImports - from imports":
  test "from import is kept verbatim":
    let src = "from std/strutils import split\n\necho \"x\".split(\",\")\n"
    let r = reorganizeImports(src, initHashSet[string]())
    check "from std/strutils import split" in r

  test "unused from module is dropped":
    let src = "from std/strutils import split\n\necho 1\n"
    let r = reorganizeImports(src, toHashSet(["strutils"]))
    check "from std/strutils" notin r

  test "from imports appear after regular imports":
    let src = "from std/os import getEnv\nimport strutils\n"
    let r = reorganizeImports(src, initHashSet[string]())
    let importPos = r.find("import strutils")
    let fromPos   = r.find("from std/os import getEnv")
    check importPos >= 0
    check fromPos > importPos

suite "reorganizeImports - sorting":
  test "no-parent imports are sorted alphabetically":
    let src = "import strutils\nimport os\nimport sequtils\n"
    let r = reorganizeImports(src, initHashSet[string]())
    check "import os, sequtils, strutils" in r

  test "parent groups are sorted alphabetically":
    let src = "import zzz/mod\nimport aaa/mod\n"
    let r = reorganizeImports(src, initHashSet[string]())
    let aaaPos = r.find("aaa/")
    let zzzPos = r.find("zzz/")
    check aaaPos < zzzPos

suite "reorganizeImports - multi-line imports":
  test "parses all modules in comma-separated multi-line import":
    let src = "import toolbar, buffers,\n              filefinder, rgfinder\n\necho 1\n"
    let r = reorganizeImports(src, initHashSet[string]())
    check "toolbar" in r
    check "buffers" in r
    check "filefinder" in r
    check "rgfinder" in r
    check "              filefinder" notin r

  test "removes unused module from multi-line comma import":
    let src = "import toolbar, buffers,\n              filefinder\n"
    let r = reorganizeImports(src, toHashSet(["buffers"]))
    check "buffers" notin r
    check "toolbar" in r
    check "filefinder" in r
    check "              filefinder" notin r
