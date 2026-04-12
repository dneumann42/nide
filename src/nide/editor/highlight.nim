import std/[options, sets, strutils]
import compiler/[lexer, llstream, idents, pathutils]
from compiler/options import newConfigRef
import seaqt/[qregularexpression, qsyntaxhighlighter, qtextblock, qtextdocument]

import nide/editor/syntaxdefs
import nide/settings/syntaxtheme

type
  LineFormat = object
    col, len: int
    kind: FormatKind

  EditorHighlighter* = ref object of VirtualQSyntaxHighlighter

  NimHighlighter* = ref object of EditorHighlighter
    lineFormats: seq[seq[LineFormat]]
    cachedCharCount: int

  CompiledRegexRule = object
    regex: QRegularExpression
    kind: FormatKind

  RegexHighlighter* = ref object of EditorHighlighter
    syntaxId: string
    lineFormats: seq[seq[LineFormat]]
    cachedCharCount: int
    rules: seq[CompiledRegexRule]

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

proc applyFormat(qsh: QSyntaxHighlighter, col, len: int, kind: FormatKind) =
  let c = cint(col)
  let n = cint(len)
  case kind
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

proc addFmt(lfs: var seq[seq[LineFormat]], line0, col, len: int, kind: FormatKind) =
  if len <= 0: return
  while lfs.len <= line0:
    lfs.add(@[])
  lfs[line0].add(LineFormat(col: col, len: len, kind: kind))

proc emitFmt(lfs: var seq[seq[LineFormat]], srcLines: openArray[string],
             line0, col, nextLine0, nextCol: int, fk: FormatKind) =
  if nextLine0 > line0:
    if line0 < srcLines.len:
      addFmt(lfs, line0, col, srcLines[line0].len - col, fk)
    for lineIdx in line0 + 1 ..< nextLine0:
      if lineIdx < srcLines.len:
        addFmt(lfs, lineIdx, 0, srcLines[lineIdx].len, fk)
    if nextLine0 < srcLines.len:
      addFmt(lfs, nextLine0, 0, nextCol, fk)
  else:
    addFmt(lfs, line0, col, max(0, nextCol - col), fk)

proc tokenizeSource(src: string): seq[Token] =
  let cache = newIdentCache()
  let config = newConfigRef()
  config.errorMax = high(int)
  config.writelnHook = proc(s: string) {.closure, gcsafe.} = discard
  let stream = llStreamOpen(src)
  var lex: Lexer
  openLexer(lex, AbsoluteFile"<buffer>", stream, cache, config)
  while true:
    var tok: Token
    rawGetTok(lex, tok)
    result.add(tok)
    if tok.tokType == tkEof:
      break
  closeLexer(lex)

proc rebuildNimCache(hl: NimHighlighter, src: string) =
  ensureSets()
  hl.lineFormats = @[]

  let srcLines = src.splitLines()

  var tokens: seq[Token]
  try:
    tokens = tokenizeSource(src)
  except:
    return

  const routineKws = {tkProc, tkFunc, tkMethod, tkMacro, tkTemplate, tkIterator, tkConverter}

  var pragmaDepth = 0
  var nextIsRoutineName = false

  for i in 0 ..< tokens.len:
    let tok = tokens[i]
    if tok.tokType == tkEof:
      break

    let line0 = tok.line - 1
    let col = tok.col
    if line0 < 0 or line0 >= srcLines.len:
      continue

    let nextLine0 = if i + 1 < tokens.len: tokens[i + 1].line - 1 else: srcLines.len
    let nextCol = if i + 1 < tokens.len: tokens[i + 1].col else: 0

    template emit(fk: FormatKind) =
      emitFmt(hl.lineFormats, srcLines, line0, col, nextLine0, nextCol, fk)

    if tok.tokType == tkCurlyDotLe:
      inc pragmaDepth
      emit(fkPragma)
      nextIsRoutineName = false
      continue
    elif tok.tokType == tkCurlyDotRi:
      if pragmaDepth > 0:
        dec pragmaDepth
      emit(fkPragma)
      nextIsRoutineName = false
      continue

    if pragmaDepth > 0:
      case tok.tokType
      of tkSpaces, tkComma, tkSemiColon, tkParLe, tkParRi,
         tkBracketLe, tkBracketRi, tkCurlyLe, tkCurlyRi:
        discard
      else:
        emit(fkPragma)
      continue

    case tok.tokType
    of tkLet, tkVar, tkConst, tkType, tkProc, tkFunc, tkMethod, tkMacro,
       tkTemplate, tkIterator, tkConverter, tkImport, tkFrom, tkInclude,
       tkExport, tkUsing, tkBind, tkMixin, tkConcept, tkStatic, tkAs,
       tkDiscard, tkAddr, tkCast, tkDo, tkEnd, tkInterface, tkOut:
      emit(fkKeyword)
      nextIsRoutineName = tok.tokType in routineKws
    of tkIf, tkElif, tkElse, tkCase, tkOf, tkFor, tkWhile, tkWhen,
       tkBreak, tkContinue, tkReturn, tkRaise, tkYield,
       tkTry, tkExcept, tkFinally, tkDefer, tkBlock:
      emit(fkControlFlow)
      nextIsRoutineName = false
    of tkRef, tkPtr, tkTuple, tkObject, tkEnum, tkDistinct, tkNil:
      emit(fkBuiltinType)
      nextIsRoutineName = false
    of tkAnd, tkOr, tkNot, tkXor, tkIn, tkNotin, tkIs, tkIsnot,
       tkDiv, tkMod, tkShl, tkShr:
      emit(fkOperator)
      nextIsRoutineName = false
    of tkOpr, tkInfixOpr, tkPrefixOpr, tkPostfixOpr, tkEquals:
      emit(fkOperator)
      nextIsRoutineName = false
    of tkSymbol:
      let normName = if tok.ident != nil: tok.ident.s else: ""
      if nextIsRoutineName:
        emit(fkFuncName)
      elif normName in specialVarSet:
        emit(fkSpecialVar)
      elif normName in builtinTypeSet:
        emit(fkBuiltinType)
      elif col < srcLines[line0].len and srcLines[line0][col] in {'A'..'Z'}:
        emit(fkType)
      nextIsRoutineName = false
    of tkAccent:
      if col + 1 < srcLines[line0].len and srcLines[line0][col + 1] in {'A'..'Z'}:
        emit(fkType)
      nextIsRoutineName = false
    of tkStrLit, tkRStrLit, tkGStrLit, tkCustomLit,
       tkTripleStrLit, tkGTripleStrLit:
      emit(fkString)
      nextIsRoutineName = false
    of tkCharLit:
      emit(fkCharLit)
      nextIsRoutineName = false
    of tkIntLit, tkInt8Lit, tkInt16Lit, tkInt32Lit, tkInt64Lit,
       tkUIntLit, tkUInt8Lit, tkUInt16Lit, tkUInt32Lit, tkUInt64Lit,
       tkFloatLit, tkFloat32Lit, tkFloat64Lit, tkFloat128Lit:
      emit(fkNumber)
      nextIsRoutineName = false
    of tkComment:
      if tok.literal.startsWith("##"):
        emit(fkDocComment)
      elif tok.literal.startsWith("#["):
        emit(fkBlockComment)
      else:
        emit(fkComment)
      nextIsRoutineName = false
    of tkSpaces:
      discard
    else:
      nextIsRoutineName = false

proc buildLineStarts(src: string): seq[int] =
  result = @[0]
  for idx, ch in src:
    if ch == '\n':
      result.add(idx + 1)

proc offsetToLineCol(lineStarts: openArray[int], offset: int): tuple[line0, col: int] =
  var low = 0
  var high = lineStarts.len - 1
  while low <= high:
    let mid = (low + high) div 2
    if lineStarts[mid] <= offset:
      result.line0 = mid
      low = mid + 1
    else:
      high = mid - 1
  result.col = offset - lineStarts[result.line0]

proc addSpanFormats(lfs: var seq[seq[LineFormat]], srcLines: openArray[string],
                    lineStarts: openArray[int], startPos, endPos: int, kind: FormatKind) =
  if endPos <= startPos or srcLines.len == 0:
    return
  let startLoc = offsetToLineCol(lineStarts, startPos)
  let endLoc =
    if endPos == startPos:
      startLoc
    else:
      offsetToLineCol(lineStarts, endPos)
  emitFmt(lfs, srcLines, startLoc.line0, startLoc.col, endLoc.line0, endLoc.col, kind)

proc compileRules(syntax: SyntaxDefinition): seq[CompiledRegexRule] =
  for rule in syntax.rules:
    let regex = QRegularExpression.create(rule.pattern)
    if not regex.isValid():
      continue
    regex.optimize()
    result.add(CompiledRegexRule(regex: regex, kind: rule.kind))

proc rebuildRegexCache(hl: RegexHighlighter, src: string) =
  hl.lineFormats = @[]
  let srcLines = src.splitLines()
  if srcLines.len == 0:
    return

  let lineStarts = buildLineStarts(src)
  for rule in hl.rules:
    var matches = rule.regex.globalMatch(src)
    while matches.hasNext():
      let m = matches.next()
      if not m.hasMatch():
        continue
      let startPos = m.capturedStart().int
      let endPos = m.capturedEnd().int
      addSpanFormats(hl.lineFormats, srcLines, lineStarts, startPos, endPos, rule.kind)

method highlightBlock*(self: NimHighlighter, text: openArray[char]) =
  let qsh = QSyntaxHighlighter(h: self[].h, owned: false)
  let doc = qsh.document()
  let charCount = int(doc.characterCount())

  if charCount != self.cachedCharCount:
    self.rebuildNimCache(doc.toPlainText())
    self.cachedCharCount = charCount

  let blockNum = int(qsh.currentBlock().blockNumber())
  if blockNum < self.lineFormats.len:
    for lf in self.lineFormats[blockNum]:
      qsh.applyFormat(lf.col, lf.len, lf.kind)

method highlightBlock*(self: RegexHighlighter, text: openArray[char]) =
  let qsh = QSyntaxHighlighter(h: self[].h, owned: false)
  let doc = qsh.document()
  let charCount = int(doc.characterCount())

  if charCount != self.cachedCharCount:
    self.rebuildRegexCache(doc.toPlainText())
    self.cachedCharCount = charCount

  let blockNum = int(qsh.currentBlock().blockNumber())
  if blockNum < self.lineFormats.len:
    for lf in self.lineFormats[blockNum]:
      qsh.applyFormat(lf.col, lf.len, lf.kind)

proc newNimHighlighter*(): NimHighlighter =
  NimHighlighter()

proc newRegexHighlighter*(syntax: SyntaxDefinition): RegexHighlighter =
  RegexHighlighter(syntaxId: syntax.id, rules: compileRules(syntax))

proc createHighlighterForPath*(path: string): EditorHighlighter {.raises: [].} =
  let syntax = syntaxForPath(path)
  if syntax.isNone():
    return nil
  case syntax.get().engine
  of seNimLexer:
    newNimHighlighter()
  of seRegex:
    newRegexHighlighter(syntax.get())

proc attach*(hl: EditorHighlighter, doc: QTextDocument) =
  QSyntaxHighlighter.create(doc, hl)

proc rehighlight*(hl: EditorHighlighter) =
  if hl == nil:
    return
  QSyntaxHighlighter(h: hl[].h, owned: false).rehighlight()
