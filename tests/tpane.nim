import std/[unittest, options]
import nide/pane/logic
import nide/helpers/logparser

# Helpers to build LogLine fixtures (same pattern as tnimimports.nim)
proc errLine(file: string, line = 1): LogLine =
  parseLine(file & "(" & $line & ", 1) Error: undeclared identifier: 'x'")

proc warnLine(file: string, line = 1): LogLine =
  parseLine(file & "(" & $line & ", 1) Warning: deprecated")

proc hintLine(file: string, line = 1): LogLine =
  parseLine(file & "(" & $line & ", 1) Hint: processing [Processing]")

# ── findMatchingBracket ────────────────────────────────────────────────────────

suite "findMatchingBracket":
  test "finds matching close paren (forward)":
    check findMatchingBracket("(foo)", 0) == 4

  test "finds matching open paren (backward)":
    check findMatchingBracket("(foo)", 4) == 0

  test "nested parens - outer match":
    check findMatchingBracket("(a(b)c)", 0) == 6

  test "nested parens - inner match from open":
    check findMatchingBracket("(a(b)c)", 2) == 4

  test "nested parens - inner match from close":
    check findMatchingBracket("(a(b)c)", 4) == 2

  test "square brackets":
    check findMatchingBracket("[x]", 0) == 2
    check findMatchingBracket("[x]", 2) == 0

  test "curly brackets":
    check findMatchingBracket("{}", 0) == 1
    check findMatchingBracket("{}", 1) == 0

  test "unmatched open paren returns -1":
    check findMatchingBracket("(abc", 0) == -1

  test "unmatched close paren returns -1":
    check findMatchingBracket("abc)", 3) == -1

  test "non-bracket char returns -1":
    check findMatchingBracket("hello", 1) == -1

  test "out of range pos < 0 returns -1":
    check findMatchingBracket("(foo)", -1) == -1

  test "out of range pos >= len returns -1":
    check findMatchingBracket("(foo)", 5) == -1

  test "empty string returns -1":
    check findMatchingBracket("", 0) == -1

# ── auto-close pairs ──────────────────────────────────────────────────────────

suite "autoClosePairs":
  test "maps supported openers to closers":
    check autoClosePairFor('(').get() == ')'
    check autoClosePairFor('[').get() == ']'
    check autoClosePairFor('{').get() == '}'

  test "does not support angle bracket":
    check autoClosePairFor('<').isNone()

  test "recognizes supported closers":
    check isAutoCloseCloser(')')
    check isAutoCloseCloser(']')
    check isAutoCloseCloser('}')
    check not isAutoCloseCloser('>')

  test "skip-over only when next char matches closer":
    check shouldSkipAutoCloseCloser("()", 1, ')')
    check shouldSkipAutoCloseCloser("[]", 1, ']')
    check not shouldSkipAutoCloseCloser("(]", 1, ')')
    check not shouldSkipAutoCloseCloser("()", 0, ')')
    check not shouldSkipAutoCloseCloser("", 0, ')')
    check not shouldSkipAutoCloseCloser("<>", 1, '>')

# ── countDiags ────────────────────────────────────────────────────────────────

suite "countDiags":
  test "counts errors warnings hints for matching file":
    let lines = @[
      errLine("/f.nim"),
      warnLine("/f.nim"),
      hintLine("/f.nim"),
      errLine("/f.nim"),
    ]
    let c = countDiags(lines, "/f.nim")
    check c.errors   == 2
    check c.warnings == 1
    check c.hints    == 1

  test "ignores lines from other files":
    let lines = @[errLine("/other.nim"), warnLine("/f.nim")]
    let c = countDiags(lines, "/f.nim")
    check c.errors   == 0
    check c.warnings == 1

  test "ignores llOther level":
    let lines = @[parseLine("some plain output")]
    let c = countDiags(lines, "")
    check c.errors == 0 and c.warnings == 0 and c.hints == 0

  test "empty input returns all zeros":
    let c = countDiags(@[], "/f.nim")
    check c.errors == 0 and c.warnings == 0 and c.hints == 0

# ── jump history ──────────────────────────────────────────────────────────────

suite "jump history":
  test "recordJump appends location to history":
    var hist: seq[JumpLocation]
    var fut:  seq[JumpLocation]
    recordJump(hist, fut, JumpLocation(file: "a.nim", line: 1, col: 0))
    check hist.len == 1
    check hist[0].file == "a.nim"

  test "recordJump clears future":
    var hist: seq[JumpLocation]
    var fut = @[JumpLocation(file: "b.nim", line: 5, col: 0)]
    recordJump(hist, fut, JumpLocation(file: "a.nim", line: 1, col: 0))
    check fut.len == 0

  test "popJumpBack from empty history returns none":
    var hist: seq[JumpLocation]
    check popJumpBack(hist).isNone()

  test "popJumpBack pops most recent location":
    var hist = @[
      JumpLocation(file: "a.nim", line: 1, col: 0),
      JumpLocation(file: "b.nim", line: 2, col: 0),
    ]
    let loc = popJumpBack(hist)
    check loc.isSome()
    check loc.get().file == "b.nim"
    check hist.len == 1

  test "popJumpForward from empty future returns none":
    var fut: seq[JumpLocation]
    check popJumpForward(fut).isNone()

  test "popJumpForward pops most recent future location":
    var fut = @[
      JumpLocation(file: "a.nim", line: 1, col: 0),
      JumpLocation(file: "b.nim", line: 3, col: 0),
    ]
    let loc = popJumpForward(fut)
    check loc.isSome()
    check loc.get().file == "b.nim"
    check fut.len == 1

  test "record then pop returns original location":
    var hist: seq[JumpLocation]
    var fut:  seq[JumpLocation]
    let orig = JumpLocation(file: "x.nim", line: 42, col: 7)
    recordJump(hist, fut, orig)
    let back = popJumpBack(hist)
    check back.isSome()
    check back.get().file == orig.file
    check back.get().line == orig.line
    check back.get().col  == orig.col

# ── rectangle selection ───────────────────────────────────────────────────────

suite "rectangle selection":
  test "offset and line column round trip":
    let text = "alpha\nbeta\ngamma"
    let pos = lineColToOffset(text, 1, 2)
    check pos == 8
    check offsetToLineCol(text, pos) == (1, 2)

  test "rectangle spans clamp to short lines":
    let text = "abcd\nxy\nmnop"
    let spans = rectangleSpans(text, 1, text.len)
    check spans.len == 3
    check spans[0] == RectangleSpan(line: 0, startCol: 1, endCol: 4)
    check spans[1] == RectangleSpan(line: 1, startCol: 1, endCol: 2)
    check spans[2] == RectangleSpan(line: 2, startCol: 1, endCol: 4)

  test "copy rectangle preserves covered rows":
    let text = "abcd\nxy\nmnop"
    check copyRectangleText(text, 1, text.len) == "bcd\ny\nnop"

  test "remove rectangle deletes selected columns line by line":
    let text = "abcd\nxy\nmnop"
    check removeRectangleText(text, 1, text.len) == "a\nx\nm"

# ── mark clearing ─────────────────────────────────────────────────────────────

suite "mark clearing":
  test "plain typing clears mark":
    check shouldClearMarkOnKeyPress(0x41, 0, "a")

  test "backspace and tab clear mark":
    check shouldClearMarkOnKeyPress(0x01000003, 0, "")
    check shouldClearMarkOnKeyPress(0x01000001, 0, "")

  test "control chords do not clear mark":
    check not shouldClearMarkOnKeyPress(0x20, 0x04000000, " ")
    check not shouldClearMarkOnKeyPress(0x3B, 0x04000000, ";")

suite "autocomplete refresh":
  test "plain typing refreshes autocomplete":
    check shouldRefreshAutocompleteOnKeyPress(0x41, 0, "a")
    check shouldRefreshAutocompleteOnKeyPress(0x20, 0, " ")

  test "backspace and delete refresh autocomplete":
    check shouldRefreshAutocompleteOnKeyPress(0x01000003, 0, "")
    check shouldRefreshAutocompleteOnKeyPress(0x01000007, 0, "")

  test "modifier chords do not refresh autocomplete":
    check not shouldRefreshAutocompleteOnKeyPress(0x3B, 0x04000000, ";")
    check not shouldRefreshAutocompleteOnKeyPress(0x4E, 0x04000000, "")

# ── autocomplete ranking ──────────────────────────────────────────────────────

suite "autocomplete ranking":
  test "extracts identifier prefix at cursor":
    check identifierPrefixAt("echo fo", 7) == "fo"
    check identifierPrefixAt("foo_bar", 7) == "foo_bar"
    check identifierPrefixAt("foo.bar", 7) == "bar"
    check identifierPrefixAt("foo(", 4) == ""

  test "prefix matches outrank unrelated completions":
    let items = @[
      ("baz", "skProc", "/tmp/other.nim"),
      ("foobar", "skProc", "/tmp/main.nim"),
      ("fooBar", "skVar", "/tmp/main.nim"),
    ]
    let ranked = sortAutocompleteMatches(items, "fo", "/tmp/main.nim")
    check ranked.len == 2
    check ranked[0] == 1
    check ranked[1] == 2

  test "returns original completions when no names match prefix":
    let items = @[
      ("alpha", "skProc", "/tmp/a.nim"),
      ("beta", "skProc", "/tmp/b.nim"),
    ]
    let ranked = sortAutocompleteMatches(items, "zz", "/tmp/a.nim")
    check ranked.len == 2
    check ranked[0] == 0
    check ranked[1] == 1
