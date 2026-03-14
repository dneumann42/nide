import std/[strutils, options]
import bench/nimindexdb
import bench/nimindexfetch
import bench/nimindexparse

var gIndexDb*: NimIndexDb
var gIndexLoaded*: bool = false

proc ensureIndexLoaded*() {.raises: [].} =
  if gIndexLoaded:
    return
  
  echo "[nimindex] Loading Nim stdlib index..."
  try:
    gIndexDb = openMemDb()
    gIndexDb.createTables()
  except:
    echo "[nimindex] Failed to open database: ", getCurrentExceptionMsg()
    return
  
  let html = getIndexContent()
  if html.len > 0:
    echo "[nimindex] Parsing index (", html.len, " bytes)..."
    let entries = parseIndexHtml(html)
    echo "[nimindex] Found ", entries.len, " symbols"
    if entries.len > 0:
      echo "[nimindex] First 3 entries: ", entries[0].name, " / ", entries[0].module, " / ", entries[0].signature
      if entries.len > 1:
        echo "[nimindex] Second: ", entries[1].name, " / ", entries[1].module
      if entries.len > 2:
        echo "[nimindex] Third: ", entries[2].name, " / ", entries[2].module
    try:
      for entry in entries:
        gIndexDb.insertSymbol(entry.name, entry.module, entry.signature)
      echo "[nimindex] Index ready!"
      gIndexLoaded = true
    except:
      echo "[nimindex] Failed to insert symbols: ", getCurrentExceptionMsg()
  else:
    echo "[nimindex] Failed to download index"

proc getWordAtCursor*(text: string; cursorPos: int): string {.raises: [].} =
  if cursorPos <= 0 or cursorPos > text.len:
    return ""
  
  var startPos = cursorPos - 1
  var endPos = cursorPos - 1
  
  # Skip backward over non-word chars to find word start
  while startPos >= 0:
    let c = text[startPos]
    if c.isAlphaNumeric() or c == '_' or c == '[' or c == ']':
      dec startPos
    else:
      break
  
  # If we're at an opening paren, skip it and continue backward
  while startPos >= 0 and text[startPos] == '(':
    dec startPos
  
  # Continue finding word start
  while startPos >= 0:
    let c = text[startPos]
    if c.isAlphaNumeric() or c == '_':
      dec startPos
    else:
      break
  
  # Find word end
  while endPos < text.len:
    let c = text[endPos]
    if c.isAlphaNumeric() or c == '_' or c == '[' or c == ']':
      inc endPos
    else:
      break
  
  if startPos < endPos:
    return text[(startPos + 1)..<endPos]
  return ""

proc querySymbol*(word: string): Option[SymbolEntry] {.raises: [].} =
  ensureIndexLoaded()
  if gIndexDb == nil:
    return none(SymbolEntry)
  if word.len == 0:
    return none(SymbolEntry)
  
  let results = gIndexDb.searchSymbols(word)
  if results.len > 0:
    return some(results[0])
  return none(SymbolEntry)

proc togglePrototypeWindow*(): bool {.raises: [].} =
  ensureIndexLoaded()
  return gIndexLoaded
