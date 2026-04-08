import std/[os, strutils]
import seaqt/[qtextdocument, qplaintextedit, qabstracttextdocumentlayout, qfont]
import nide/editor/highlight

type
  Buffer* = ref object
    name, path: string
    content: string
    documentH: pointer
    highlighter*: NimHighlighter
    externallyModified*: bool

  BufferManager* = object
    buffers: seq[Buffer]

const ScratchBufferName* = "scratch"
const DefaultBufferFontSize = 12

var scratchCount {.global.} = 0

proc init*(T: typedesc[BufferManager]): T =
  T(buffers: @[])

proc new*(T: typedesc[Buffer], path = ""): T =
  let n =
    if path.len > 0: path
    else:
      inc scratchCount
      "scratch-" & $scratchCount
  T(name: n, path: path)

proc name*(b: Buffer): string = b.name
proc `name=`*(b: Buffer, n: string) = b.name = n
proc path*(b: Buffer): string = b.path
proc `path=`*(b: Buffer, p: string) = b.path = p
proc content*(b: Buffer): string = b.content

proc document*(b: Buffer): QTextDocument =
  if b.documentH == nil:
    var doc = QTextDocument.create()
    doc.owned = false
    b.documentH = doc.h
    var layout = QPlainTextDocumentLayout.create(doc)
    layout.owned = false
    doc.setDocumentLayout(QAbstractTextDocumentLayout(h: layout.h, owned: false))
    var font = QFont.create("Fira Code")
    font.setPointSize(DefaultBufferFontSize)
    font.setStyleHint(cint(QFontStyleHintEnum.TypeWriter))
    doc.setDefaultFont(font)
    doc.setPlainText(b.content)
    doc.setModified(false)
    let hl = NimHighlighter()
    hl.attach(QTextDocument(h: b.documentH, owned: false))
    b.highlighter = hl
  result = QTextDocument(h: b.documentH, owned: false)

proc add*(bm: var BufferManager, buf: Buffer) =
  bm.buffers.add(buf)

iterator items*(bm: BufferManager): Buffer =
  for b in bm.buffers:
    yield b

proc len*(bm: BufferManager): int = bm.buffers.len

proc openFile*(bm: var BufferManager, path: string): Buffer =
  for buf in bm.buffers:
    if buf.path == path:
      when defined(debugFileWatcher):
        echo "[FileWatcher] BufferManager.openFile: found existing buffer for: ", path
      return buf
  result = Buffer.new(path)
  when defined(debugFileWatcher):
    echo "[FileWatcher] BufferManager.openFile: created new buffer for: ", path
  try:
    result.content = readFile(path)
    when defined(debugFileWatcher):
      echo "[FileWatcher] BufferManager.openFile: read content, len: ", result.content.len
  except:
    when defined(debugFileWatcher):
      echo "[FileWatcher] BufferManager.openFile: failed to read file: ", path
    discard
  discard result.document()
  bm.add(result)

proc close*(bm: var BufferManager, name: string) =
  for i in 0..<bm.buffers.len:
    if bm.buffers[i].name == name:
      bm.buffers.delete(i)
      return

proc closePath*(bm: var BufferManager, path: string) =
  for i in 0..<bm.buffers.len:
    if bm.buffers[i].path == path:
      bm.buffers.delete(i)
      return

proc closePathsUnder*(bm: var BufferManager, dir: string) =
  var i = bm.buffers.len - 1
  while i >= 0:
    let path = bm.buffers[i].path
    if path == dir or path.startsWith(dir / ""):
      bm.buffers.delete(i)
    dec i

proc rehighlightAll*(bm: BufferManager) =
  ## Re-highlight all open buffers (call after syntax theme change)
  for buf in bm.buffers:
    if buf.highlighter != nil:
      buf.highlighter.rehighlight()
