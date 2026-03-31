import logparser
import std/algorithm
import std/options
import std/strutils
import ../keybindings
import ../qtconst

type
  JumpLocation* = object
    file*: string
    line*: int
    col*: int

  RectangleSpan* = object
    line*: int
    startCol*: int
    endCol*: int

const identifierChars = {'a'..'z', 'A'..'Z', '0'..'9', '_'}

const
  ScoreExactMatch = 400
  ScorePrefixMatch = 250
  ScoreSubstringMatch = 50
  MaxNameLenPenalty = 80
  ScoreNoPrefix = 25
  ScoreSameFile = 40
  ScoreProcSymbol = 15
  ScoreVarSymbol = 10
  ScoreTypeSymbol = 5

proc autoClosePairFor*(ch: char): Option[char] =
  case ch
  of '(': some(')')
  of '[': some(']')
  of '{': some('}')
  else: none(char)

proc isAutoCloseCloser*(ch: char): bool =
  ch in {')', ']', '}'}

proc shouldSkipAutoCloseCloser*(text: string, pos: int, typed: char): bool =
  if not typed.isAutoCloseCloser():
    return false
  pos >= 0 and pos < text.len and text[pos] == typed

proc findMatchingBracket*(text: string, pos: int): int =
  if pos < 0 or pos >= text.len: return -1
  let ch = text[pos]
  let forward = ch in {'(', '[', '{'}
  let openBr = case ch
    of '(', ')': '('
    of '[', ']': '['
    else:        '{'
  let closeBr = case ch
    of '(', ')': ')'
    of '[', ']': ']'
    else:        '}'
  if ch notin {'(', ')', '[', ']', '{', '}'}: return -1
  var depth = 0
  if forward:
    for i in pos ..< text.len:
      if text[i] == openBr: inc depth
      elif text[i] == closeBr:
        dec depth
        if depth == 0: return i
  else:
    for i in countdown(pos, 0):
      if text[i] == closeBr: inc depth
      elif text[i] == openBr:
        dec depth
        if depth == 0: return i
  return -1

proc countDiags*(lines: seq[LogLine], file: string): tuple[hints, warnings, errors: int] =
  for ll in lines:
    if ll.file != file: continue
    case ll.level
    of llHint:    inc result.hints
    of llWarning: inc result.warnings
    of llError:   inc result.errors
    else: discard

proc recordJump*(history: var seq[JumpLocation], future: var seq[JumpLocation],
                 loc: JumpLocation) =
  history.add(loc)
  future = @[]

proc popJumpBack*(history: var seq[JumpLocation]): Option[JumpLocation] =
  if history.len == 0: return none(JumpLocation)
  let loc = history[^1]
  history.setLen(history.len - 1)
  some(loc)

proc popJumpForward*(future: var seq[JumpLocation]): Option[JumpLocation] =
  if future.len == 0: return none(JumpLocation)
  let loc = future[^1]
  future.setLen(future.len - 1)
  some(loc)

proc offsetToLineCol*(text: string, pos: int): tuple[line, col: int] =
  let clamped = min(max(pos, 0), text.len)
  var line = 0
  var col = 0
  var i = 0
  while i < clamped:
    if text[i] == '\n':
      inc line
      col = 0
    else:
      inc col
    inc i
  (line, col)

proc lineColToOffset*(text: string, line, col: int): int =
  let lines = text.split('\n')
  var pos = 0
  for i in 0 ..< min(line, lines.len):
    pos += lines[i].len
    if i < lines.len - 1:
      inc pos
  let targetLine = min(max(line, 0), max(lines.len - 1, 0))
  let targetLen = if lines.len == 0: 0 else: lines[targetLine].len
  pos + min(max(col, 0), targetLen)

proc rectangleSpans*(text: string, anchorPos, pointPos: int): seq[RectangleSpan] =
  let lines = text.split('\n')
  let anchor = offsetToLineCol(text, anchorPos)
  let point = offsetToLineCol(text, pointPos)
  let startLine = min(anchor.line, point.line)
  let endLine = max(anchor.line, point.line)
  let startCol = min(anchor.col, point.col)
  let endCol = max(anchor.col, point.col)
  for lineIdx in startLine .. endLine:
    let lineLen = if lineIdx < lines.len: lines[lineIdx].len else: 0
    let actualStart = min(startCol, lineLen)
    let actualEnd = min(endCol, lineLen)
    result.add(RectangleSpan(line: lineIdx, startCol: actualStart, endCol: actualEnd))

proc copyRectangleText*(text: string, anchorPos, pointPos: int): string =
  let lines = text.split('\n')
  let spans = rectangleSpans(text, anchorPos, pointPos)
  var parts: seq[string]
  for span in spans:
    if span.line < lines.len and span.startCol < span.endCol:
      parts.add(lines[span.line][span.startCol ..< span.endCol])
    else:
      parts.add("")
  result = parts.join("\n")

proc removeRectangleText*(text: string, anchorPos, pointPos: int): string =
  var lines = text.split('\n')
  let spans = rectangleSpans(text, anchorPos, pointPos)
  for span in spans:
    if span.line >= lines.len or span.startCol >= span.endCol:
      continue
    lines[span.line] = lines[span.line][0 ..< span.startCol] &
      lines[span.line][span.endCol .. ^1]
  result = lines.join("\n")

proc shouldClearMarkOnKeyPress*(key, mods: int, text: string): bool =
  if (mods and (ctrlMod or altMod)) != 0:
    return false
  if key == Key_Backspace or key == Key_Return or key == Key_Enter or
     key == Key_Delete or key == Key_Tab:
    return true
  text.len > 0

proc shouldRefreshAutocompleteOnKeyPress*(key, mods: int, text: string): bool =
  if (mods and (ctrlMod or altMod)) != 0:
    return false
  if key == Key_Backspace or key == Key_Delete:
    return true
  text.len > 0

proc normalizeIdentifier(text: string): string =
  result = newStringOfCap(text.len)
  for ch in text:
    if ch != '_':
      result.add(ch.toLowerAscii())

proc identifierPrefixAt*(text: string, pos: int): string =
  let clamped = min(max(pos, 0), text.len)
  var start = clamped
  while start > 0 and text[start - 1] in identifierChars:
    dec start
  result = text[start ..< clamped]

proc sortAutocompleteMatches*(items: openArray[tuple[name, symkind, file: string]],
                              prefix: string,
                              currentFile: string): seq[int] =
  type RankedCompletion = tuple[score: int, idx: int]

  let normalizedPrefix = normalizeIdentifier(prefix)
  var ranked: seq[RankedCompletion]

  for idx, item in items:
    let normalizedName = normalizeIdentifier(item.name)
    var score = 0

    if normalizedPrefix.len > 0:
      if normalizedName == normalizedPrefix:
        score += ScoreExactMatch
      if normalizedName.startsWith(normalizedPrefix):
        score += ScorePrefixMatch
      elif normalizedName.contains(normalizedPrefix):
        score += ScoreSubstringMatch
      else:
        continue

      score -= min(item.name.len, MaxNameLenPenalty)
    else:
      score += ScoreNoPrefix

    if currentFile.len > 0 and item.file == currentFile:
      score += ScoreSameFile

    case item.symkind
    of "skProc", "skFunc", "skMethod", "skTemplate", "skMacro":
      score += ScoreProcSymbol
    of "skVar", "skLet", "skConst", "skParam", "skResult":
      score += ScoreVarSymbol
    of "skType", "skEnumField":
      score += ScoreTypeSymbol
    else:
      discard

    ranked.add((score, idx))

  if ranked.len == 0:
    result = newSeq[int](items.len)
    for idx in 0 ..< items.len:
      result[idx] = idx
    return

  ranked.sort(proc(a, b: RankedCompletion): int =
    result = cmp(b.score, a.score)
    if result == 0:
      result = cmp(a.idx, b.idx)
  )

  result = newSeq[int](ranked.len)
  for i, entry in ranked:
    result[i] = entry.idx
