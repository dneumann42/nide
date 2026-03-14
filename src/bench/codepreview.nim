import seaqt/[qwidget, qplaintextedit, qfont, qfontmetrics,
              qpaintdevice, qpainter, qcolor, qpaintevent, qrect, qtextobject,
              qresizeevent, qtextdocument, qpoint]
import syntaxtheme

proc QWidget_virtbase(src: pointer, outQObject: ptr pointer, outPaintDevice: ptr pointer) {.importc: "QWidget_virtbase".}

proc widgetToPaintDevice(w: QWidget): QPaintDevice =
  var outQObject: pointer
  var outPaintDevice: pointer
  QWidget_virtbase(w.h, addr outQObject, addr outPaintDevice)
  QPaintDevice(h: outPaintDevice, owned: false)

proc lineNumberAreaWidth*(editor: QPlainTextEdit): cint =
  let digits = max(1, ($editor.blockCount()).len)
  let fm = QFontMetrics.create(editor.document().defaultFont())
  cint(fm.horizontalAdvance("0") * digits + 12)

proc lineNumberAreaPaintEvent*(editor: QPlainTextEdit, event: QPaintEvent, gutter: QWidget) {.raises: [].} =
  try:
    let editorFont = editor.document().defaultFont()
    var painter = QPainter.create(widgetToPaintDevice(gutter))
    painter.setFont(editorFont)
    painter.fillRect(event.rect(), QColor.create(gutterBackground()))
    let w = gutter.width()
    let h = gutter.height()
    painter.setPen(QColor.create("#333333"))
    painter.drawLine(cint(w - 1), 0, cint(w - 1), h)
    painter.drawLine(0, h - 1, w - 1, h - 1)
    var blk = editor.firstVisibleBlock()
    let offset = editor.contentOffset()
    while blk.isValid():
      let geo = editor.blockBoundingGeometry(blk)
      let top = cint(geo.top() + offset.y())
      if top >= gutter.height(): break
      let numStr = $(blk.blockNumber() + 1)
      let lineH = cint(QFontMetrics.create(editorFont).height())
      painter.setPen(QColor.create(gutterForeground()))
      painter.drawText(0, top, w - 4, lineH, cint(0x0022), numStr)
      blk = blk.next()
    discard painter.endX()
  except: discard

proc setupCodePreview*(parent: QWidget): tuple[preview: QPlainTextEdit, gutterH: pointer] =
  var gutterH: pointer = nil

  var previewVtbl = new QPlainTextEditVTable
  previewVtbl.resizeEvent = proc(self: QPlainTextEdit, e: QResizeEvent) {.raises: [], gcsafe.} =
    QPlainTextEditresizeEvent(self, e)
    if gutterH == nil: return
    let cr = QWidget(h: self.h, owned: false).contentsRect()
    QWidget(h: gutterH, owned: false).setGeometry(
      cr.left(), cr.top(), self.lineNumberAreaWidth(), cr.height())

  var preview = QPlainTextEdit.create(vtbl = previewVtbl)
  preview.owned = false
  preview.setReadOnly(true)
  var previewFont = QFont.create("Monospace")
  previewFont.setStyleHint(cint(QFontStyleHintEnum.TypeWriter))
  QWidget(h: preview.h, owned: false).setFont(previewFont)
  let previewH = preview.h

  var previewGutterVtbl = new QWidgetVTable
  previewGutterVtbl.paintEvent = proc(self: QWidget, event: QPaintEvent) {.raises: [], gcsafe.} =
    lineNumberAreaPaintEvent(QPlainTextEdit(h: previewH, owned: false), event, self)
  var previewGutter = QWidget.create(QWidget(h: previewH, owned: false), cint(0), vtbl = previewGutterVtbl)
  previewGutter.owned = false
  gutterH = previewGutter.h

  QPlainTextEdit(h: previewH, owned: false).setViewportMargins(
    QPlainTextEdit(h: previewH, owned: false).lineNumberAreaWidth(), 0, 0, 0)

  preview.onBlockCountChanged do(count: cint) {.raises: [].}:
    QPlainTextEdit(h: previewH, owned: false).setViewportMargins(
      QPlainTextEdit(h: previewH, owned: false).lineNumberAreaWidth(), 0, 0, 0)

  preview.onUpdateRequest do(rect: QRect, dy: cint) {.raises: [].}:
    let g = QWidget(h: gutterH, owned: false)
    if dy != 0:
      g.scroll(cint 0, dy)
    else:
      g.update(0, rect.y(), g.width(), rect.height())
    let ed = QPlainTextEdit(h: previewH, owned: false)
    if rect.contains(ed.viewport().rect()):
      ed.setViewportMargins(ed.lineNumberAreaWidth(), 0, 0, 0)

  result = (preview, gutterH)
