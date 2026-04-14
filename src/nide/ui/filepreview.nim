import std/[os, strutils]
import seaqt/[qabstractscrollarea, qcheckbox, qimage, qlabel, qpixmap, qplaintextedit,
              qresizeevent, qscrollarea, qstackedwidget, qsyntaxhighlighter,
              qtextdocument, qwidget]
import nide/editor/highlight
import nide/helpers/qtconst
import nide/ui/widgets

const
  BinaryPreviewPlaceholder* = "(binary file not previewed)"
  PreviewReadErrorPlaceholder* = "(could not read file)"
  BinaryDetectionSampleSize = 4096

const ImageExtensions = [
  ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp", ".svg", ".ico", ".tif", ".tiff"
]

type FilePreviewKind* = enum
  fpkText
  fpkImage
  fpkBinary
  fpkError

type FilePreviewWidget* = ref object
  container*: QWidget
  stack*: QStackedWidget
  textPreview*: QPlainTextEdit
  imageScroll*: QScrollArea
  imageLabel*: QLabel
  placeholder*: QLabel
  filterCheck*: QCheckBox
  highlighter*: EditorHighlighter
  imagePixmapH: pointer

proc isBinarySample*(sample: openArray[char]): bool {.raises: [].} =
  for ch in sample:
    if ch == '\0':
      return true
  false

proc basePixmap(preview: FilePreviewWidget): QPixmap =
  if preview == nil or preview.imagePixmapH == nil:
    return QPixmap()
  QPixmap(h: preview.imagePixmapH, owned: false)

proc setBasePixmap(preview: FilePreviewWidget, pixmap: QPixmap) =
  preview.imagePixmapH = pixmap.h

proc isImagePath*(path: string): bool {.raises: [].} =
  let ext = path.splitFile.ext.toLowerAscii()
  ext in ImageExtensions

proc loadImagePixmap*(path: string): tuple[ok: bool, pixmap: QPixmap] {.raises: [].} =
  try:
    var pixmap = QPixmap.create()
    pixmap.owned = false
    result.ok = pixmap.load(path)
    result.pixmap = pixmap
  except CatchableError:
    result = (false, QPixmap())

proc canLoadImage*(path: string): bool {.raises: [].} =
  try:
    var image = QImage.create()
    image.owned = false
    image.load(path)
  except CatchableError:
    false

proc detectBinaryFile*(path: string, readable: var bool): bool {.raises: [].} =
  try:
    var f: File
    if not open(f, path, fmRead):
      readable = false
      return false
    readable = true
    defer:
      close(f)

    var sample = newString(BinaryDetectionSampleSize)
    let bytesRead = readChars(f, sample.toOpenArray(0, sample.high))
    if bytesRead <= 0:
      return false
    sample.setLen(bytesRead)
    isBinarySample(sample)
  except CatchableError:
    readable = false
    false

proc loadFilePreview*(path: string): tuple[kind: FilePreviewKind, content: string] {.raises: [].} =
  try:
    if canLoadImage(path):
      return (fpkImage, "")

    var readable = false
    if detectBinaryFile(path, readable):
      return (fpkBinary, BinaryPreviewPlaceholder)
    if not readable:
      return (fpkError, PreviewReadErrorPlaceholder)
    (fpkText, readFile(path))
  except CatchableError:
    (fpkError, PreviewReadErrorPlaceholder)

proc updateImagePreview*(preview: FilePreviewWidget) {.raises: [].} =
  if preview == nil:
    return
  let pixmap = preview.basePixmap()
  if pixmap.h == nil or pixmap.isNull():
    preview.imageLabel.clear()
    return

  let viewport = QAbstractScrollArea(h: preview.imageScroll.h, owned: false).viewport()
  let availW = max(viewport.width(), cint 1)
  let availH = max(viewport.height(), cint 1)
  let mode =
    if preview.filterCheck.h != nil and preview.filterCheck.isChecked():
      SmoothTransformation
    else:
      FastTransformation

  let scaled =
    if pixmap.width() <= availW and pixmap.height() <= availH:
      pixmap
    else:
      pixmap.scaled(availW, availH, KeepAspectRatio, mode)
  preview.imageLabel.setPixmap(scaled)
  preview.imageLabel.asWidget.resize(scaled.size())

proc clearHighlighter(preview: FilePreviewWidget) {.raises: [].} =
  if preview == nil or preview.highlighter == nil:
    return
  QSyntaxHighlighter(h: preview.highlighter[].h, owned: false).setDocument(QTextDocument())
  preview.highlighter = nil

proc newFilePreviewWidget*(parent: QWidget, showFilter = true): FilePreviewWidget =
  result = FilePreviewWidget()

  var textPreview = newWidget(QPlainTextEdit.create())
  textPreview.setReadOnly(true)

  var imageLabel = newWidget(QLabel.create(""))
  imageLabel.setAlignment(AlignHCenterVCenter)
  imageLabel.asWidget.setMinimumSize(cint 1, cint 1)

  let previewRef = result
  var imageScrollVtbl = new QScrollAreaVTable
  imageScrollVtbl.resizeEvent = proc(self: QScrollArea, e: QResizeEvent) {.raises: [], gcsafe.} =
    QScrollArearesizeEvent(self, e)
    {.cast(gcsafe).}:
      previewRef.updateImagePreview()
  var imageScroll = newWidget(QScrollArea.create(vtbl = imageScrollVtbl))
  imageScroll.setWidget(imageLabel.asWidget)
  imageScroll.setWidgetResizable(false)
  imageScroll.asWidget.setStyleSheet("QScrollArea { border: none; }")

  var placeholder = newWidget(QLabel.create(""))
  placeholder.setAlignment(AlignHCenterVCenter)
  placeholder.asWidget.setStyleSheet("QLabel { color: #888888; }")

  var stack = newWidget(QStackedWidget.create())
  discard stack.addWidget(textPreview.asWidget)
  discard stack.addWidget(imageScroll.asWidget)
  discard stack.addWidget(placeholder.asWidget)

  var filterCheck: QCheckBox
  if showFilter:
    filterCheck = checkbox("Filtering")
    filterCheck.clickable do(checked: bool):
      discard checked
      previewRef.updateImagePreview()

  let layout = vbox()
  if showFilter:
    layout.add(filterCheck)
  layout.add(stack)

  var container = newWidget(QWidget.create(parent))
  layout.applyTo(container)

  result.container = container
  result.stack = stack
  result.textPreview = textPreview
  result.imageScroll = imageScroll
  result.imageLabel = imageLabel
  result.placeholder = placeholder
  result.filterCheck = filterCheck

proc setPreviewForFile*(preview: FilePreviewWidget, path: string): FilePreviewKind {.raises: [].} =
  if preview == nil:
    return fpkError

  let (kind, content) = loadFilePreview(path)
  case kind
  of fpkText:
    preview.clearHighlighter()
    preview.textPreview.setPlainText(content)
    let hl = createHighlighterForPath(path)
    if hl != nil:
      hl.attach(preview.textPreview.document())
    preview.highlighter = hl
    preview.stack.setCurrentWidget(preview.textPreview.asWidget)
  of fpkImage:
    preview.clearHighlighter()
    let (ok, pixmap) = loadImagePixmap(path)
    if not ok:
      preview.placeholder.setText(PreviewReadErrorPlaceholder)
      preview.stack.setCurrentWidget(preview.placeholder.asWidget)
      return fpkError
    preview.setBasePixmap(pixmap)
    preview.updateImagePreview()
    preview.stack.setCurrentWidget(preview.imageScroll.asWidget)
  of fpkBinary, fpkError:
    preview.clearHighlighter()
    preview.placeholder.setText(content)
    preview.stack.setCurrentWidget(preview.placeholder.asWidget)
  result = kind

proc showPreviewPlaceholder*(preview: FilePreviewWidget, text: string) {.raises: [].} =
  if preview == nil:
    return
  preview.placeholder.setText(text)
  preview.stack.setCurrentWidget(preview.placeholder.asWidget)

proc setPreviewForFile*(preview: QPlainTextEdit, path: string): FilePreviewKind {.raises: [].} =
  let (kind, content) = loadFilePreview(path)
  preview.setPlainText(
    case kind
    of fpkText: content
    of fpkImage: "(image preview available in rich preview widget)"
    of fpkBinary, fpkError: content
  )
  kind
