import std/[strutils, options]
import bench/nimindexdb
import bench/nimindexfetch
import bench/nimindexparse

var gIndexDb*: NimIndexDb
var gIndexLoaded*: bool = false

proc ensureIndexLoaded*() {.raises: [].} =
  if gIndexLoaded:
    return
  
  echo "[nimindex] Loading index..."
  try:
    gIndexDb = openMemDb()
    gIndexDb.createTables()
  except:
    echo "[nimindex] Failed to open database"
    return
  
  let html = getIndexContent()
  if html.len > 0:
    let entries = parseIndexHtml(html)
    echo "[nimindex] Parsed ", entries.len, " entries"
    try:
      for entry in entries:
        gIndexDb.insertSymbol(entry.name, entry.module, entry.signature)
      echo "[nimindex] Inserted symbols into database"
      gIndexLoaded = true
    except:
      echo "[nimindex] Failed to insert symbols"
  else:
    echo "[nimindex] Failed to load index"

proc getWordAtCursor*(text: string; cursorPos: int): string {.raises: [].} =
  if cursorPos <= 0 or cursorPos > text.len:
    return ""
  
  var startPos = cursorPos - 1
  var endPos = cursorPos - 1
  
  while startPos >= 0:
    let c = text[startPos]
    if c.isAlphaNumeric() or c == '_' or c == '[' or c == ']':
      dec startPos
    else:
      break
  
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
  if gIndexDb == nil or word.len == 0:
    return none(SymbolEntry)
  
  let results = gIndexDb.searchSymbols(word)
  if results.len > 0:
    return some(results[0])
  return none(SymbolEntry)

proc togglePrototypeWindow*(): bool {.raises: [].} =
  ensureIndexLoaded()
  return gIndexLoaded
