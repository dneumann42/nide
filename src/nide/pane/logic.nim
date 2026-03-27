import logparser
import std/options

type
  JumpLocation* = object
    file*: string
    line*: int
    col*: int

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
