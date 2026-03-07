import std/[os]
import seaqt/[qtextdocument, qplaintextedit, qabstracttextdocumentlayout]
import bench/highlight

type
  Buffer* = ref object
    name, path: string
    content: string
    documentH: pointer
    highlighter: NimHighlighter

  BufferManager* = object
    buffers: seq[Buffer]

const ScratchBufferName* = "scratch"

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
      return buf
  result = Buffer.new(path)
  try:
    result.content = readFile(path)
  except:
    discard
  discard result.document()
  bm.add(result)

proc close*(bm: var BufferManager, name: string) =
  for i in 0..<bm.buffers.len:
    if bm.buffers[i].name == name:
      bm.buffers.delete(i)
      return
