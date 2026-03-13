import std/[sets]
import seaqt/[qsyntaxhighlighter, qtextcharformat, qtextblock, qcolor, qbrush, qfont]
import bench/syntaxtheme

type NimHighlighter* = ref object of VirtualQSyntaxHighlighter

var
  fmtKeyword, fmtComment, fmtString, fmtNumber, fmtType: QTextCharFormat
  fmtBuiltinType, fmtCharLit, fmtDocComment, fmtBlockComment: QTextCharFormat
  fmtPragma, fmtOperator, fmtFuncName: QTextCharFormat
  fmtsReady = false

proc makeFormat(color: string, bold = false, italic = false): QTextCharFormat =
  result = QTextCharFormat.create()
  QTextFormat(h: result.h, owned: false).setForeground(
    QBrush.create(QColor.fromString(color)))
  if bold:
    QTextCharFormat(h: result.h, owned: false).setFontWeight(cint(QFontWeightEnum.Bold))
  if italic:
    QTextCharFormat(h: result.h, owned: false).setFontItalic(true)

proc ensureFormats() =
  if fmtsReady: return
  fmtsReady = true
  
  # Try to load from theme, fall back to hardcoded colors
  let t = currentTheme.syntax
  let kwColor = if t.keyword.len > 0: t.keyword else: "#569cd6"
  let typeColor = if t.`type`.len > 0: t.`type` else: "#4ec9b0"
  let builtinColor = if t.builtinType.len > 0: t.builtinType else: "#4ec9b0"
  let strColor = if t.string.len > 0: t.string else: "#ce9178"
  let numColor = if t.number.len > 0: t.number else: "#b5cea8"
  let commentColor = if t.comment.len > 0: t.comment else: "#6a9955"
  
  fmtKeyword = makeFormat(kwColor, true, false)
  fmtType = makeFormat(typeColor, false, false)
  fmtBuiltinType = makeFormat(builtinColor, false, false)
  fmtString = makeFormat(strColor)
  fmtCharLit = makeFormat(if t.charLit.len > 0: t.charLit else: "#ce9178")
  fmtNumber = makeFormat(numColor)
  fmtComment = makeFormat(commentColor, italic = true)
  fmtDocComment = makeFormat(if t.docComment.len > 0: t.docComment else: "#608b4e", italic = true)
  fmtBlockComment = makeFormat(commentColor, italic = true)
  fmtPragma = makeFormat(if t.pragma.len > 0: t.pragma else: "#9cdcfe")
  fmtOperator = makeFormat(if t.operator.len > 0: t.operator else: "#d4d4d4")
  fmtFuncName = makeFormat(if t.funcName.len > 0: t.funcName else: "#dcdcaa")

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
  ensureFormats()

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
          cint(start), cint(text.len - start), fmtBlockComment)
        return
      else:
        QSyntaxHighlighter(h: self[].h, owned: false).setFormat(
          cint(start), cint(i - start), fmtBlockComment)
      lastWasRoutineKw = false

    # Doc comments: ## until end of line
    elif c == '#' and i + 1 < text.len and text[i + 1] == '#':
      QSyntaxHighlighter(h: self[].h, owned: false).setFormat(
        cint(i), cint(text.len - i), fmtDocComment)
      break

    # Single-line comments: # until end of line
    elif c == '#':
      QSyntaxHighlighter(h: self[].h, owned: false).setFormat(
        cint(i), cint(text.len - i), fmtComment)
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
      QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmtString)
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
      QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmtString)
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
      QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmtString)
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
        QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmtCharLit)
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
      QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmtPragma)
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
      QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmtNumber)
      lastWasRoutineKw = false

    # Identifiers and keywords
    elif c in {'a'..'z', 'A'..'Z', '_'}:
      let start = i
      while i < text.len and text[i] in {'a'..'z', 'A'..'Z', '0'..'9', '_'}: inc i
      var word = newStringOfCap(i - start)
      for j in start..<i: word.add(text[j])

      if lastWasRoutineKw:
        QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmtFuncName)
        lastWasRoutineKw = false
      elif word in kwSet:
        QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmtKeyword)
        lastWasRoutineKw = word in routineKwSet
      elif word in builtinTypeSet:
        QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmtBuiltinType)
        lastWasRoutineKw = false
      elif word.len > 0 and word[0] in {'A'..'Z'}:
        QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmtType)
        lastWasRoutineKw = false
      else:
        lastWasRoutineKw = false

    # Operators
    elif c in operatorChars:
      let start = i
      while i < text.len and text[i] in operatorChars: inc i
      QSyntaxHighlighter(h: self[].h, owned: false).setFormat(cint(start), cint(i - start), fmtOperator)
      lastWasRoutineKw = false

    else:
      inc i
      lastWasRoutineKw = false

proc attach*(hl: NimHighlighter, doc: QTextDocument) =
  QSyntaxHighlighter.create(doc, hl)

proc rehighlight*(hl: NimHighlighter) =
  QSyntaxHighlighter(h: hl[].h, owned: false).rehighlight()
