import std/[os, strutils]
import seaqt/[qtextdocument, qplaintextedit, qabstracttextdocumentlayout, qfont, qpixmap]
import nide/editor/highlight
import nide/ui/widgets
import nide/ui/filepreview

type
  BufferKind* = enum
    bkText
    bkImage

  Buffer* = ref object
    name, path: string
    kind*: BufferKind
    content: string
    documentH: pointer
    pixmapH: pointer
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
  T(name: n, path: path, kind: bkText)

proc name*(b: Buffer): string = b.name
proc `name=`*(b: Buffer, n: string) = b.name = n
proc path*(b: Buffer): string = b.path
proc `path=`*(b: Buffer, p: string) = b.path = p
proc content*(b: Buffer): string = b.content
proc kind*(b: Buffer): BufferKind = b.kind

proc pixmap*(b: Buffer): QPixmap =
  if b.pixmapH == nil:
    return QPixmap()
  QPixmap(h: b.pixmapH, owned: false)

proc setPixmap*(b: Buffer, pm: QPixmap) =
  b.pixmapH = pm.h

proc document*(b: Buffer): QTextDocument =
  if b.documentH == nil:
    var doc = newWidget(QTextDocument.create())
    b.documentH = doc.h
    var layout = newWidget(QPlainTextDocumentLayout.create(doc))
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
    var pixmap = QPixmap.create()
    pixmap.owned = false
    if pixmap.load(path):
      result.kind = bkImage
      result.pixmapH = pixmap.h
      when defined(debugFileWatcher):
        echo "[FileWatcher] BufferManager.openFile: loaded image buffer"
    else:
      let (previewKind, content) = loadFilePreview(path)
      result.kind =
        if previewKind == fpkImage: bkImage
        else: bkText
      if result.kind == bkImage:
        result.pixmapH = pixmap.h
      else:
        result.content = content
        when defined(debugFileWatcher):
          echo "[FileWatcher] BufferManager.openFile: read content, len: ", result.content.len
  except CatchableError:
    when defined(debugFileWatcher):
      echo "[FileWatcher] BufferManager.openFile: failed to read file: ", path
    discard
  if result.kind == bkText:
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
