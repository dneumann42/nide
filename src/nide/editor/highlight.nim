import std/[sets, strutils]
import compiler/[lexer, llstream, idents, options, pathutils]
import seaqt/[qsyntaxhighlighter, qtextblock, qtextdocument]
import nide/settings/syntaxtheme

type
  FormatKind = enum
    fkKeyword, fkControlFlow, fkType, fkBuiltinType, fkString, fkCharLit,
    fkNumber, fkComment, fkDocComment, fkBlockComment, fkPragma,
    fkOperator, fkFuncName, fkSpecialVar

  LineFormat = object
    col, len: int
    kind: FormatKind

  NimHighlighter* = ref object of VirtualQSyntaxHighlighter
    lineFormats: seq[seq[LineFormat]]
    cachedCharCount: int

# --- Sets ---

var
  builtinTypeSet: HashSet[string]
  specialVarSet: HashSet[string]
  setsReady = false

proc ensureSets() =
  if setsReady: return
  setsReady = true
  for t in [
    "int", "int8", "int16", "int32", "int64",
    "uint", "uint8", "uint16", "uint32", "uint64",
    "float", "float32", "float64",
    "bool", "char", "string", "cstring",
    "byte", "natural", "positive",
    "ordinal", "someinteger", "somefloat", "somenumber", "somesignedint", "someunsignedint",
    "seq", "array", "openarray", "varargs", "set", "hashset",
    "table", "orderedtable", "counttable",
    "option",
    "pointer", "auto", "any", "untyped", "typed", "void",
    "typedesc", "range",
    "slice", "hslice",
    "exception", "catchableerror", "defect", "ioerror", "oserror", "valueerror",
    "indexdefect", "fielddefect", "rangedefect",
    "true", "false",
  ]: builtinTypeSet.incl(t)
  for v in ["result", "self", "it"]: specialVarSet.incl(v)

# --- Tokenizer ---

proc tokenizeSource(src: string): seq[Token] =
  let cache = newIdentCache()
  let config = newConfigRef()
  config.errorMax = high(int)  # prevent quit() on any lexer error
  config.writelnHook = proc(s: string) {.closure, gcsafe.} = discard  # suppress stderr output
  let stream = llStreamOpen(src)
  var lex: Lexer
  openLexer(lex, AbsoluteFile"<buffer>", stream, cache, config)
  while true:
    var tok: Token
    rawGetTok(lex, tok)
    result.add(tok)
    if tok.tokType == tkEof: break
  closeLexer(lex)

# --- Cache builder ---

proc addFmt(lfs: var seq[seq[LineFormat]], line0, col, len: int, kind: FormatKind) =
  if len <= 0: return
  while lfs.len <= line0: lfs.add(@[])
  lfs[line0].add(LineFormat(col: col, len: len, kind: kind))

proc emitFmt(lfs: var seq[seq[LineFormat]], srcLines: openArray[string],
             line0, col, nextLine0, nextCol: int, fk: FormatKind) =
  if nextLine0 > line0:
    # Multi-line token: color across all spanned lines
    if line0 < srcLines.len:
      addFmt(lfs, line0, col, srcLines[line0].len - col, fk)
    for L in line0 + 1 ..< nextLine0:
      if L < srcLines.len:
        addFmt(lfs, L, 0, srcLines[L].len, fk)
    if nextLine0 < srcLines.len:
      addFmt(lfs, nextLine0, 0, nextCol, fk)
  else:
    addFmt(lfs, line0, col, max(0, nextCol - col), fk)

proc rebuildCache(hl: NimHighlighter, src: string) =
  ensureSets()
  hl.lineFormats = @[]

  let srcLines = src.splitLines()

  var tokens: seq[Token]
  try:
    tokens = tokenizeSource(src)
  except:  # Nim compiler lexer can raise Exception, not just CatchableError
    return

  const routineKws = {tkProc, tkFunc, tkMethod, tkMacro, tkTemplate, tkIterator, tkConverter}

  var pragmaDepth = 0
  var nextIsRoutineName = false

  for i in 0 ..< tokens.len:
    let tok = tokens[i]
    if tok.tokType == tkEof: break

    let line0 = tok.line - 1
    let col = tok.col
    if line0 < 0 or line0 >= srcLines.len: continue

    let nextLine0 = if i + 1 < tokens.len: tokens[i+1].line - 1 else: srcLines.len
    let nextCol   = if i + 1 < tokens.len: tokens[i+1].col   else: 0

    template emit(fk: FormatKind) =
      emitFmt(hl.lineFormats, srcLines, line0, col, nextLine0, nextCol, fk)

    # Pragma boundary tokens: color as pragma and update depth
    if tok.tokType == tkCurlyDotLe:
      inc pragmaDepth
      emit(fkPragma)
      nextIsRoutineName = false
      continue
    elif tok.tokType == tkCurlyDotRi:
      if pragmaDepth > 0: dec pragmaDepth
      emit(fkPragma)
      nextIsRoutineName = false
      continue

    # Inside a pragma: color non-structural tokens
    if pragmaDepth > 0:
      case tok.tokType
      of tkSpaces, tkComma, tkSemiColon, tkParLe, tkParRi,
         tkBracketLe, tkBracketRi, tkCurlyLe, tkCurlyRi:
        discard
      else:
        emit(fkPragma)
      continue

    # Normal token classification
    case tok.tokType

    # Declaration keywords
    of tkLet, tkVar, tkConst, tkType, tkProc, tkFunc, tkMethod, tkMacro,
       tkTemplate, tkIterator, tkConverter, tkImport, tkFrom, tkInclude,
       tkExport, tkUsing, tkBind, tkMixin, tkConcept, tkStatic, tkAs,
       tkDiscard, tkAddr, tkCast, tkDo, tkEnd, tkInterface, tkOut:
      emit(fkKeyword)
      nextIsRoutineName = tok.tokType in routineKws

    # Control flow keywords
    of tkIf, tkElif, tkElse, tkCase, tkOf, tkFor, tkWhile, tkWhen,
       tkBreak, tkContinue, tkReturn, tkRaise, tkYield,
       tkTry, tkExcept, tkFinally, tkDefer, tkBlock:
      emit(fkControlFlow)
      nextIsRoutineName = false

    # Type-like keywords → builtin type color, not keyword
    of tkRef, tkPtr, tkTuple, tkObject, tkEnum, tkDistinct, tkNil:
      emit(fkBuiltinType)
      nextIsRoutineName = false

    # Operator keywords
    of tkAnd, tkOr, tkNot, tkXor, tkIn, tkNotin, tkIs, tkIsnot,
       tkDiv, tkMod, tkShl, tkShr:
      emit(fkOperator)
      nextIsRoutineName = false

    # Operator tokens
    of tkOpr, tkInfixOpr, tkPrefixOpr, tkPostfixOpr, tkEquals:
      emit(fkOperator)
      nextIsRoutineName = false

    # Identifiers
    of tkSymbol:
      let normName = if tok.ident != nil: tok.ident.s else: ""
      if nextIsRoutineName:
        emit(fkFuncName)
        nextIsRoutineName = false
      elif normName in specialVarSet:
        emit(fkSpecialVar)
        nextIsRoutineName = false
      elif normName in builtinTypeSet:
        emit(fkBuiltinType)
        nextIsRoutineName = false
      elif col < srcLines[line0].len and srcLines[line0][col] in {'A'..'Z'}:
        emit(fkType)
        nextIsRoutineName = false
      else:
        nextIsRoutineName = false

    of tkAccent:
      # Backtick-quoted identifier — check source char after the backtick
      if col + 1 < srcLines[line0].len and srcLines[line0][col + 1] in {'A'..'Z'}:
        emit(fkType)
      nextIsRoutineName = false

    # String literals (single-line and multi-line)
    of tkStrLit, tkRStrLit, tkGStrLit, tkCustomLit,
       tkTripleStrLit, tkGTripleStrLit:
      emit(fkString)
      nextIsRoutineName = false

    # Character literals
    of tkCharLit:
      emit(fkCharLit)
      nextIsRoutineName = false

    # Numeric literals
    of tkIntLit, tkInt8Lit, tkInt16Lit, tkInt32Lit, tkInt64Lit,
       tkUIntLit, tkUInt8Lit, tkUInt16Lit, tkUInt32Lit, tkUInt64Lit,
       tkFloatLit, tkFloat32Lit, tkFloat64Lit, tkFloat128Lit:
      emit(fkNumber)
      nextIsRoutineName = false

    # Comments (single-line, doc, and block)
    of tkComment:
      if tok.literal.startsWith("##"):
        emit(fkDocComment)
      elif tok.literal.startsWith("#["):
        emit(fkBlockComment)
      else:
        emit(fkComment)
      nextIsRoutineName = false

    of tkSpaces:
      discard  # preserve nextIsRoutineName across whitespace

    else:
      nextIsRoutineName = false

# --- Qt highlighter interface ---

method highlightBlock*(self: NimHighlighter, text: openArray[char]) =
  let qsh = QSyntaxHighlighter(h: self[].h, owned: false)
  let doc = qsh.document()
  let charCount = int(doc.characterCount())

  if charCount != self.cachedCharCount:
    self.rebuildCache(doc.toPlainText())
    self.cachedCharCount = charCount

  let blockNum = int(qsh.currentBlock().blockNumber())
  if blockNum < self.lineFormats.len:
    for lf in self.lineFormats[blockNum]:
      let c = cint(lf.col)
      let n = cint(lf.len)
      case lf.kind
      of fkKeyword:      qsh.setFormat(c, n, currentFormats.keyword)
      of fkControlFlow:  qsh.setFormat(c, n, currentFormats.controlFlow)
      of fkType:         qsh.setFormat(c, n, currentFormats.`type`)
      of fkBuiltinType:  qsh.setFormat(c, n, currentFormats.builtinType)
      of fkString:       qsh.setFormat(c, n, currentFormats.str)
      of fkCharLit:      qsh.setFormat(c, n, currentFormats.charLit)
      of fkNumber:       qsh.setFormat(c, n, currentFormats.number)
      of fkComment:      qsh.setFormat(c, n, currentFormats.comment)
      of fkDocComment:   qsh.setFormat(c, n, currentFormats.docComment)
      of fkBlockComment: qsh.setFormat(c, n, currentFormats.blockComment)
      of fkPragma:       qsh.setFormat(c, n, currentFormats.pragma)
      of fkOperator:     qsh.setFormat(c, n, currentFormats.operator)
      of fkFuncName:     qsh.setFormat(c, n, currentFormats.funcName)
      of fkSpecialVar:   qsh.setFormat(c, n, currentFormats.specialVar)

proc attach*(hl: NimHighlighter, doc: QTextDocument) =
  QSyntaxHighlighter.create(doc, hl)

proc rehighlight*(hl: NimHighlighter) =
  QSyntaxHighlighter(h: hl[].h, owned: false).rehighlight()
