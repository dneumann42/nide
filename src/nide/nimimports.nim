import std/[strutils, sequtils, algorithm, tables, sets]
import compiler/[lexer, llstream, idents, options, pathutils]
import logparser

type
  ImportEntry = object
    modules:    seq[string]
    isFrom:     bool
    fromModule: string
    rawLines:   seq[string]
    startLine:  int
    endLine:    int

proc tokenizeSource(src: string): seq[Token] =
  let cache = newIdentCache()
  let config = newConfigRef()
  let stream = llStreamOpen(src)
  var lex: Lexer
  openLexer(lex, AbsoluteFile"<buffer>", stream, cache, config)
  while true:
    var tok: Token
    rawGetTok(lex, tok)
    result.add(tok)
    if tok.tokType == tkEof: break
  closeLexer(lex)

proc isIdentLike(t: Token): bool =
  ## True for tkSymbol and any keyword token used as a module name component.
  ## The Nim lexer gives keywords their own tokType (e.g. tkMod for 'mod'),
  ## but they still have a non-nil ident field when used in import paths.
  t.ident != nil and t.tokType notin {
    tkEof, tkOpr, tkBracketLe, tkBracketRi, tkComma, tkAs,
    tkImport, tkFrom, tkColon, tkSemiColon, tkDot, tkDotDot,
    tkParLe, tkParRi, tkCurlyLe, tkCurlyRi,
    tkStrLit, tkRStrLit, tkTripleStrLit,
    tkIntLit, tkInt8Lit, tkInt16Lit, tkInt32Lit, tkInt64Lit,
    tkUIntLit, tkUInt8Lit, tkUInt16Lit, tkUInt32Lit, tkUInt64Lit,
    tkFloatLit, tkFloat32Lit, tkFloat64Lit, tkFloat128Lit,
    tkCharLit
  }

proc parseImports(src: string): seq[ImportEntry] =
  let tokens = tokenizeSource(src)
  let srcLines = src.splitLines()
  var i = 0

  while i < tokens.len:
    if tokens[i].tokType == tkEof: break

    if tokens[i].tokType == tkImport:
      var entry: ImportEntry
      entry.startLine = tokens[i].line
      entry.endLine = tokens[i].line
      inc i

      var depth = 0
      var pathPrefix = ""

      while i < tokens.len:
        let t = tokens[i]
        if t.tokType == tkEof: break
        if depth == 0 and t.indent == 0: break

        if t.tokType == tkBracketLe:
          inc depth; inc i
        elif t.tokType == tkBracketRi:
          dec depth
          entry.endLine = max(entry.endLine, t.line)
          inc i
        elif t.tokType == tkComma:
          if depth == 0: pathPrefix = ""
          inc i
        elif t.tokType == tkAs:
          inc i
          if i < tokens.len and isIdentLike(tokens[i]):
            inc i  # skip alias name
        elif isIdentLike(t):
          let name = t.ident.s
          entry.endLine = max(entry.endLine, t.line)
          if i + 1 < tokens.len and tokens[i+1].tokType == tkOpr and
             tokens[i+1].ident != nil and tokens[i+1].ident.s == "/":
            pathPrefix = pathPrefix & name & "/"
            i += 2
          else:
            entry.modules.add(pathPrefix & name)
            if depth == 0: pathPrefix = ""
            inc i
        else: inc i

      if entry.modules.len > 0:
        let maxLine = min(entry.endLine, srcLines.len)
        if entry.startLine <= maxLine:
          entry.rawLines = srcLines[entry.startLine - 1 .. maxLine - 1]
        result.add(entry)

    elif tokens[i].tokType == tkFrom:
      var entry: ImportEntry
      entry.isFrom = true
      entry.startLine = tokens[i].line
      entry.endLine = tokens[i].line
      inc i

      # Collect module name (tokens between 'from' and 'import')
      var fromParts: seq[string]
      while i < tokens.len:
        let t = tokens[i]
        if t.tokType == tkEof or t.tokType == tkImport: break
        if isIdentLike(t):
          fromParts.add(t.ident.s)
        inc i
      entry.fromModule = fromParts.join("/")

      if i < tokens.len and tokens[i].tokType == tkImport: inc i

      # Consume rest until new top-level line
      while i < tokens.len:
        let t = tokens[i]
        if t.tokType == tkEof: break
        if t.indent == 0: break
        entry.endLine = max(entry.endLine, t.line)
        inc i

      let maxLine = min(entry.endLine, srcLines.len)
      if entry.startLine <= maxLine:
        entry.rawLines = srcLines[entry.startLine - 1 .. maxLine - 1]
      result.add(entry)

    else:
      inc i

proc collectUnusedModules*(diags: seq[LogLine], filePath: string): HashSet[string] =
  for ll in diags:
    if ll.file != filePath: continue
    if not ll.raw.endsWith("[UnusedImport]"): continue
    let tagPos = ll.raw.rfind("[UnusedImport]")
    if tagPos < 2: continue
    let closeQ = ll.raw.rfind('\'', 0, tagPos - 1)
    if closeQ < 1: continue
    let openQ = ll.raw.rfind('\'', 0, closeQ - 1)
    if openQ < 0: continue
    result.incl(ll.raw[openQ + 1 ..< closeQ])

proc reorganizeImports*(src: string, unused: HashSet[string]): string =
  let entries = parseImports(src)
  if entries.len == 0: return src

  var regularModules: seq[string]
  var fromEntryLines: seq[string]

  for entry in entries:
    if entry.isFrom:
      let slashPos = entry.fromModule.rfind('/')
      let leaf = if slashPos >= 0: entry.fromModule[slashPos + 1 .. ^1]
                 else: entry.fromModule
      if leaf notin unused:
        for l in entry.rawLines: fromEntryLines.add(l)
    else:
      for m in entry.modules:
        let slashPos = m.rfind('/')
        let leaf = if slashPos >= 0: m[slashPos + 1 .. ^1] else: m
        if leaf notin unused:
          regularModules.add(m)

  # Group by parent path
  var groups: Table[string, seq[string]]
  for m in regularModules:
    let slashPos = m.rfind('/')
    if slashPos >= 0:
      groups.mgetOrPut(m[0 ..< slashPos], @[]).add(m[slashPos + 1 .. ^1])
    else:
      groups.mgetOrPut("", @[]).add(m)

  # Build new import lines
  var newLines: seq[string]

  # No-parent imports first — all on one line, comma-separated
  if "" in groups:
    var members = groups[""]
    members.sort()
    if members.len == 1:
      newLines.add("import " & members[0])
    else:
      newLines.add("import " & members.join(", "))

  # Grouped imports sorted by parent
  var parents = toSeq(groups.keys).filterIt(it != "")
  parents.sort()
  for parent in parents:
    var members = groups[parent]
    members.sort()
    if members.len == 1:
      newLines.add("import " & parent & "/" & members[0])
    else:
      newLines.add("import " & parent & "/[" & members.join(", ") & "]")

  # From-imports last (verbatim)
  for l in fromEntryLines: newLines.add(l)

  # Splice: replace import lines in source, preserving everything else
  var skipLines: HashSet[int]
  for entry in entries:
    for ln in entry.startLine .. entry.endLine:
      skipLines.incl(ln)

  let srcLines = src.splitLines()
  var resultLines: seq[string]
  var inserted = false

  for idx in 0 ..< srcLines.len:
    let lineNum = idx + 1
    if lineNum in skipLines:
      if not inserted:
        for l in newLines: resultLines.add(l)
        inserted = true
    else:
      resultLines.add(srcLines[idx])

  result = resultLines.join("\n")
