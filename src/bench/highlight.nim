import seaqt/[qsyntaxhighlighter, qtextcharformat, qcolor, qbrush, qfont]

type NimHighlighter* = ref object of VirtualQSyntaxHighlighter

var
  fmtsReady = false
  fmtKeyword, fmtComment, fmtString, fmtNumber, fmtType: QTextCharFormat

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
  fmtKeyword = makeFormat("#569cd6", bold = true)
  fmtComment = makeFormat("#6a9955", italic = true)
  fmtString  = makeFormat("#ce9178")
  fmtNumber  = makeFormat("#b5cea8")
  fmtType    = makeFormat("#4ec9b0")

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

method highlightBlock*(self: NimHighlighter, text: openArray[char]) =
  ensureFormats()
  template applyFmt(start, count: int, fmtVar: QTextCharFormat) =
    QSyntaxHighlighter(h: self[].h, owned: false).setFormat(
      cint(start), cint(count), QTextCharFormat(h: fmtVar.h, owned: false))
  var i = 0
  while i < text.len:
    let c = text[i]
    if c == '#':
      applyFmt(i, text.len - i, fmtComment)
      break
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
      applyFmt(start, i - start, fmtString)
    elif c in {'0'..'9'}:
      let start = i
      while i < text.len and
            text[i] in {'0'..'9', '_', 'x', 'X', 'o', 'O', 'b', 'B', '.'}:
        inc i
      applyFmt(start, i - start, fmtNumber)
    elif c in {'a'..'z', 'A'..'Z', '_'}:
      let start = i
      while i < text.len and
            text[i] in {'a'..'z', 'A'..'Z', '0'..'9', '_'}:
        inc i
      var word = newStringOfCap(i - start)
      for j in start..<i:
        word.add(text[j])
      var isKw = false
      for kw in nimKeywords:
        if word == kw:
          isKw = true
          break
      if isKw:
        applyFmt(start, i - start, fmtKeyword)
      elif word.len > 0 and word[0] in {'A'..'Z'}:
        applyFmt(start, i - start, fmtType)
    else:
      inc i

proc attach*(hl: NimHighlighter, doc: QTextDocument) =
  QSyntaxHighlighter.create(doc, hl)
