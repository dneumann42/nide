import std/[sets]
import seaqt/[qsyntaxhighlighter, qtextcharformat, qtextblock]
import bench/syntaxtheme

type NimHighlighter* = ref object of VirtualQSyntaxHighlighter

# Multi-line block state encoding:
#   0  = normal (no multi-line state)
#   1+ = inside block comment with nesting depth
#  -1  = inside triple-quoted string
const
  StateNormal* = 0
  StateTripleString* = -1

const nimKeywords = [
  "addr", "and", "as", "asm",
  "bind", "block", "break",
  "case", "cast", "concept", "const", "continue", "converter",
  "defer", "discard", "distinct", "div", "do",
  "elif", "else", "end", "enum", "except", "export",
  "finally", "for", "from", "func",
  "if", "import", "in", "include", "interface", "is", "isnot", "iterator",
  "let",
  "macro", "method", "mixin", "mod",
  "nil", "not", "notin",
  "object", "of", "or", "out",
  "proc", "ptr",
  "raise", "ref", "return",
  "shl", "shr", "static",
  "template", "try", "tuple", "type",
  "using",
  "var",
  "when", "while",
  "xor",
  "yield",
  "true", "false",
]

# Keywords that are followed by a function/routine name
const routineKeywords = ["proc", "func", "method", "macro", "template", "iterator", "converter"]

const nimBuiltinTypes = [
  "int", "int8", "int16", "int32", "int64",
  "uint", "uint8", "uint16", "uint32", "uint64",
  "float", "float32", "float64",
  "bool", "char", "string", "cstring",
  "byte", "Natural", "Positive",
  "Ordinal", "SomeInteger", "SomeFloat", "SomeNumber", "SomeSignedInt", "SomeUnsignedInt",
  "seq", "array", "openArray", "varargs", "set", "HashSet",
  "Table", "OrderedTable", "CountTable",
  "Option", "Result",
  "pointer", "auto", "any", "untyped", "typed", "void",
  "typedesc", "range",
  "Slice", "HSlice",
  "Exception", "CatchableError", "Defect", "IOError", "OSError", "ValueError",
  "IndexDefect", "FieldDefect", "RangeDefect", "ref", "ptr",
]

var
  kwSet: HashSet[string]
  routineKwSet: HashSet[string]
  builtinTypeSet: HashSet[string]
  setsReady = false

proc ensureSets() =
  if setsReady: return
  setsReady = true
  for kw in nimKeywords: kwSet.incl(kw)
  for kw in routineKeywords: routineKwSet.incl(kw)
  for t in nimBuiltinTypes: builtinTypeSet.incl(t)

const operatorChars = {'+', '-', '*', '/', '\\', '<', '>', '!', '?', '^', '.',
                       '|', '%', '&', '$', '@', '~', '='}

method highlightBlock*(self: NimHighlighter, text: openArray[char]) =
  ensureSets()

  template fmts(): untyped = currentFormats

  template applyFmt(start, count: int, fmtVar: QTextCharFormat) =
    QSyntaxHighlighter(h: self[].h, owned: false).setFormat(
      cint(start), cint(count), QTextCharFormat(h: fmtVar.h, owned: false))

  template setState(s: int) =
    QSyntaxHighlighter(h: self[].h, owned: false).setCurrentBlockState(cint(s))

  template prevState(): int =
    int(QSyntaxHighlighter(h: self[].h, owned: false).previousBlockState())

  let prev = prevState()
  setState(StateNormal)

  var i = 0

  # Continue multi-line block comment from previous block
  if prev > 0:
    var depth = prev
    let start = 0
    while i < text.len:
      if i + 1 < text.len and text[i] == '#' and text[i + 1] == '[':
        inc depth
        i += 2
      elif i + 1 < text.len and text[i] == ']' and text[i + 1] == '#':
        dec depth
        i += 2
        if depth == 0:
          applyFmt(start, i - start, fmts.blockComment)
          break
      else:
        inc i
    if depth > 0:
      applyFmt(start, text.len - start, fmts.blockComment)
      setState(depth)
      return

  # Continue multi-line triple-quoted string from previous block
  if prev == StateTripleString:
    let start = 0
    while i < text.len:
      if i + 2 < text.len and text[i] == '"' and text[i + 1] == '"' and text[i + 2] == '"':
        i += 3
        applyFmt(start, i - start, fmts.str)
        break
      else:
        inc i
    if i >= text.len:
      applyFmt(start, text.len - start, fmts.str)
      setState(StateTripleString)
      return

  # Track whether previous token was a routine keyword (for funcName highlighting)
  var lastWasRoutineKw = false

  while i < text.len:
    let c = text[i]

    # Block comments: #[ ... ]# with nesting
    if c == '#' and i + 1 < text.len and text[i + 1] == '[':
      let start = i
      var depth = 1
      i += 2
      while i < text.len and depth > 0:
        if i + 1 < text.len and text[i] == '#' and text[i + 1] == '[':
          inc depth
          i += 2
        elif i + 1 < text.len and text[i] == ']' and text[i + 1] == '#':
          dec depth
          i += 2
        else:
          inc i
      if depth > 0:
        applyFmt(start, text.len - start, fmts.blockComment)
        setState(depth)
        return
      else:
        applyFmt(start, i - start, fmts.blockComment)
      lastWasRoutineKw = false

    # Doc comments: ## until end of line
    elif c == '#' and i + 1 < text.len and text[i + 1] == '#':
      applyFmt(i, text.len - i, fmts.docComment)
      break

    # Single-line comments: # until end of line
    elif c == '#':
      applyFmt(i, text.len - i, fmts.comment)
      break

    # Triple-quoted strings: """..."""
    elif c == '"' and i + 2 < text.len and text[i + 1] == '"' and text[i + 2] == '"':
      let start = i
      i += 3
      var closed = false
      while i < text.len:
        if i + 2 < text.len and text[i] == '"' and text[i + 1] == '"' and text[i + 2] == '"':
          i += 3
          closed = true
          break
        else:
          inc i
      if not closed:
        applyFmt(start, text.len - start, fmts.str)
        setState(StateTripleString)
        return
      else:
        applyFmt(start, i - start, fmts.str)
      lastWasRoutineKw = false

    # Raw strings: r"..."
    elif c == 'r' and i + 1 < text.len and text[i + 1] == '"':
      let start = i
      i += 2  # skip r"
      while i < text.len:
        if text[i] == '"':
          # In raw strings, "" is an escaped quote
          if i + 1 < text.len and text[i + 1] == '"':
            i += 2
          else:
            inc i
            break
        else:
          inc i
      applyFmt(start, i - start, fmts.str)
      lastWasRoutineKw = false

    # Regular strings: "..."
    elif c == '"':
      let start = i
      inc i
      while i < text.len:
        if text[i] == '\\':
          inc i
          if i < text.len: inc i
        elif text[i] == '"':
          inc i
          break
        else:
          inc i
      applyFmt(start, i - start, fmts.str)
      lastWasRoutineKw = false

    # Character literals: 'x', '\n', etc.
    elif c == '\'':
      let start = i
      inc i
      if i < text.len:
        if text[i] == '\\':
          inc i
          if i < text.len: inc i  # skip escaped char
        else:
          inc i  # skip single char
      if i < text.len and text[i] == '\'':
        inc i
        applyFmt(start, i - start, fmts.charLit)
      # else: not a valid char literal, don't highlight (could be apostrophe in suffix)
      lastWasRoutineKw = false

    # Pragmas: {. ... .}
    elif c == '{' and i + 1 < text.len and text[i + 1] == '.':
      let start = i
      i += 2
      while i < text.len:
        if text[i] == '.' and i + 1 < text.len and text[i + 1] == '}':
          i += 2
          break
        else:
          inc i
      applyFmt(start, i - start, fmts.pragma)
      lastWasRoutineKw = false

    # Numbers: integer, float, hex, octal, binary with optional type suffixes
    elif c in {'0'..'9'}:
      let start = i
      if c == '0' and i + 1 < text.len and text[i + 1] in {'x', 'X'}:
        # Hex
        i += 2
        while i < text.len and text[i] in {'0'..'9', 'a'..'f', 'A'..'F', '_'}:
          inc i
      elif c == '0' and i + 1 < text.len and text[i + 1] in {'o', 'O'}:
        # Octal
        i += 2
        while i < text.len and text[i] in {'0'..'7', '_'}:
          inc i
      elif c == '0' and i + 1 < text.len and text[i + 1] in {'b', 'B'}:
        # Binary
        i += 2
        while i < text.len and text[i] in {'0', '1', '_'}:
          inc i
      else:
        # Decimal integer or float
        while i < text.len and text[i] in {'0'..'9', '_'}:
          inc i
        if i < text.len and text[i] == '.' and i + 1 < text.len and text[i + 1] in {'0'..'9'}:
          inc i  # skip the dot
          while i < text.len and text[i] in {'0'..'9', '_'}:
            inc i
        # Exponent
        if i < text.len and text[i] in {'e', 'E'}:
          inc i
          if i < text.len and text[i] in {'+', '-'}: inc i
          while i < text.len and text[i] in {'0'..'9', '_'}:
            inc i
      # Type suffix: 'i8, 'i16, 'u32, 'f64, etc.
      if i < text.len and text[i] == '\'':
        inc i
        while i < text.len and text[i] in {'a'..'z', 'A'..'Z', '0'..'9'}:
          inc i
      applyFmt(start, i - start, fmts.number)
      lastWasRoutineKw = false

    # Identifiers and keywords
    elif c in {'a'..'z', 'A'..'Z', '_'}:
      let start = i
      while i < text.len and text[i] in {'a'..'z', 'A'..'Z', '0'..'9', '_'}:
        inc i
      var word = newStringOfCap(i - start)
      for j in start..<i:
        word.add(text[j])

      if lastWasRoutineKw:
        # This identifier follows proc/func/method/etc.
        applyFmt(start, i - start, fmts.funcName)
        lastWasRoutineKw = false
      elif word in kwSet:
        applyFmt(start, i - start, fmts.keyword)
        lastWasRoutineKw = word in routineKwSet
      elif word in builtinTypeSet:
        applyFmt(start, i - start, fmts.builtinType)
        lastWasRoutineKw = false
      elif word.len > 0 and word[0] in {'A'..'Z'}:
        applyFmt(start, i - start, fmts.`type`)
        lastWasRoutineKw = false
      else:
        lastWasRoutineKw = false

    # Backtick-quoted identifiers: `someIdent`
    elif c == '`':
      let start = i
      inc i
      while i < text.len and text[i] != '`':
        inc i
      if i < text.len:
        inc i  # skip closing backtick
      if lastWasRoutineKw:
        applyFmt(start, i - start, fmts.funcName)
      lastWasRoutineKw = false

    # Operators
    elif c in operatorChars:
      let start = i
      while i < text.len and text[i] in operatorChars:
        inc i
      applyFmt(start, i - start, fmts.operator)
      lastWasRoutineKw = false

    # Skip whitespace but preserve routineKw state
    elif c in {' ', '\t', '\r', '\n'}:
      inc i
      # Don't reset lastWasRoutineKw — allow whitespace between `proc` and name

    # Other characters (braces, parens, brackets, semicolons, etc.)
    else:
      inc i
      lastWasRoutineKw = false

proc attach*(hl: NimHighlighter, doc: QTextDocument) =
  QSyntaxHighlighter.create(doc, hl)

proc rehighlight*(hl: NimHighlighter) =
  QSyntaxHighlighter(h: hl[].h, owned: false).rehighlight()
