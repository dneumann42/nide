import std/[sets]
import seaqt/[qsyntaxhighlighter, qtextblock]
import syntaxtheme

type NimHighlighter* = ref object of VirtualQSyntaxHighlighter

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

  template fmt(): untyped = currentFormats
  var i = 0
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
        QSyntaxHighlighter(h: self[].h, owned: false).setFormat(
          cint(start), cint(text.len - start), fmt().blockComment)
        return
      else:
        QSyntaxHighlighter(h: self[].h, owned: false).setFormat(
          cint(start), cint(i - start), fmt().blockComment)
      lastWasRoutineKw = false

    # Doc comments: ## until end of line
    elif c == '#' and i + 1 < text.len and text[i + 1] == '#':
      QSyntaxHighlighter(h: self[].h, owned: false).setFormat(
        cint(i), cint(text.len - i), fmt().docComment)
      break

    # Single-line comments: # until end of line
    elif c == '#':
      QSyntaxHighlighter(h: self[].h, owned: false).setFormat(
        cint(i), cint(text.len - i), fmt().comment)
      break

    # Triple-quoted strings: """..."""
    elif c == '"' and i + 2 < text.len and text[i + 1] == '"' and text[i + 2] == '"':
      let start = i
      i += 3
      while i < text.len:
        if i + 2 < text.len and text[i] == '"' and text[i + 1] == '"' and text[i + 2] == '"':
          i += 3
          break
        else:
          inc i
      QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmt().str)
      lastWasRoutineKw = false

    # Raw strings: r"..."
    elif c == 'r' and i + 1 < text.len and text[i + 1] == '"':
      let start = i
      i += 2
      while i < text.len:
        if text[i] == '"':
          if i + 1 < text.len and text[i + 1] == '"':
            i += 2
          else:
            inc i
            break
        else:
          inc i
      QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmt().str)
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
      QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmt().str)
      lastWasRoutineKw = false

    # Character literals: 'x'
    elif c == '\'':
      let start = i
      inc i
      if i < text.len:
        if text[i] == '\\':
          inc i
          if i < text.len: inc i
        else:
          inc i
      if i < text.len and text[i] == '\'':
        inc i
        QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmt().charLit)
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
      QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmt().pragma)
      lastWasRoutineKw = false

    # Numbers
    elif c in {'0'..'9'}:
      let start = i
      if c == '0' and i + 1 < text.len and text[i + 1] in {'x', 'X'}:
        i += 2
        while i < text.len and text[i] in {'0'..'9', 'a'..'f', 'A'..'F', '_'}: inc i
      elif c == '0' and i + 1 < text.len and text[i + 1] in {'o', 'O'}:
        i += 2
        while i < text.len and text[i] in {'0'..'7', '_'}: inc i
      elif c == '0' and i + 1 < text.len and text[i + 1] in {'b', 'B'}:
        i += 2
        while i < text.len and text[i] in {'0', '1', '_'}: inc i
      else:
        while i < text.len and text[i] in {'0'..'9', '_'}: inc i
        if i < text.len and text[i] == '.' and i + 1 < text.len and text[i + 1] in {'0'..'9'}:
          inc i
          while i < text.len and text[i] in {'0'..'9', '_'}: inc i
      if i < text.len and text[i] == '\'':
        inc i
        while i < text.len and text[i] in {'a'..'z', 'A'..'Z', '0'..'9'}: inc i
      QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmt().number)
      lastWasRoutineKw = false

    # Identifiers and keywords
    elif c in {'a'..'z', 'A'..'Z', '_'}:
      let start = i
      while i < text.len and text[i] in {'a'..'z', 'A'..'Z', '0'..'9', '_'}: inc i
      var word = newStringOfCap(i - start)
      for j in start..<i: word.add(text[j])

      if lastWasRoutineKw:
        QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmt().funcName)
        lastWasRoutineKw = false
      elif word in kwSet:
        QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmt().keyword)
        lastWasRoutineKw = word in routineKwSet
      elif word in builtinTypeSet:
        QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmt().builtinType)
        lastWasRoutineKw = false
      elif word.len > 0 and word[0] in {'A'..'Z'}:
        QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmt().type)
        lastWasRoutineKw = false
      else:
        lastWasRoutineKw = false

    # Operators
    elif c in operatorChars:
      let start = i
      while i < text.len and text[i] in operatorChars: inc i
      QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmt().operator)
      lastWasRoutineKw = false

    else:
      inc i
      lastWasRoutineKw = false

proc attach*(hl: NimHighlighter, doc: QTextDocument) =
  QSyntaxHighlighter.create(doc, hl)

proc rehighlight*(hl: NimHighlighter) =
  QSyntaxHighlighter(h: hl[].h, owned: false).rehighlight()
