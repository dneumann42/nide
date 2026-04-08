import std/[osproc, streams, os]
import seaqt/[qwidget, qdialog, qvboxlayout, qhboxlayout, qlayout,
              qpushbutton, qlabel, qscrollarea, qsvgwidget,
              qabstractscrollarea, qabstractslider, qscrollbar,
              qmouseevent, qwheelevent, qcursor, qpoint,
              qsize]
# Cursor shape constants (Qt::CursorShape)
const
  OpenHandCursor   = cint(17)
  ClosedHandCursor = cint(18)

# Mouse button constants (Qt::MouseButton)
const
  LeftButton = cint(1)

# Keyboard modifier constants (Qt::KeyboardModifier)
const
  CtrlModifier = cint(0x04000000)

const
  GraphWidth = cint 900
  GraphHeight = cint 700
  ZoomSensitivity = 0.005
  MinZoom = 0.1
  MaxZoom = 10.0
  FallbackSvgWidth = cint 800
  FallbackSvgHeight = cint 600
  WheelAngleDivisor = 120.0
  WheelPixelStep = 20.0

proc findDot(): string =
  for dir in ["/usr/sbin", "/usr/bin", "/usr/local/bin", "/opt/homebrew/bin"]:
    let p = dir / "dot"
    if fileExists(p): return p
  return ""

proc showError(dialogH: pointer, msg: string) {.raises: [].} =
  try:
    var errLabel = QLabel.create(msg)
    errLabel.owned = false
    var closeBtn = QPushButton.create("Close")
    closeBtn.owned = false
    closeBtn.onClicked do() {.raises: [].}:
      QWidget(h: dialogH, owned: false).hide()
    var layout = QVBoxLayout.create()
    layout.owned = false
    layout.addWidget(QWidget(h: errLabel.h, owned: false))
    layout.addStretch()
    layout.addWidget(QWidget(h: closeBtn.h, owned: false))
    QWidget(h: dialogH, owned: false).setLayout(QLayout(h: layout.h, owned: false))
    discard QDialog(h: dialogH, owned: false).exec()
  except: discard

proc showGraphDialog*(parent: QWidget, dotSource: string) {.raises: [].} =
  var dialog = QDialog.create(parent)
  dialog.owned = false
  let dialogH = dialog.h
  QWidget(h: dialogH, owned: false).setWindowTitle("Module Graph")
  QWidget(h: dialogH, owned: false).resize(GraphWidth, GraphHeight)

  let dotBin = findDot()
  if dotBin.len == 0:
    showError(dialogH, "graphviz not found.\nExpected dot at /usr/sbin/dot, /usr/bin/dot, or /usr/local/bin/dot.")
    return

  echo "=== dot input ==="
  echo dotSource
  echo "=== end dot input ==="

  var svgResult = ""
  try:
    var p = startProcess(dotBin, args = ["-Tsvg"], options = {poUsePath})
    p.inputStream.write(dotSource)
    p.inputStream.close()
    svgResult = p.outputStream.readAll()
    p.close()
  except:
    echo "=== dot exception: ", getCurrentExceptionMsg()
    showError(dialogH, "dot failed: " & getCurrentExceptionMsg())
    return

  echo "=== dot output (first 500) ==="
  echo svgResult[0..min(499, svgResult.high)]
  echo "=== end dot output ==="

  if svgResult.len == 0 or svgResult[0..4] != "<?xml":
    let preview = if svgResult.len > 0: svgResult[0..min(300, svgResult.high)] else: "(empty)"
    showError(dialogH, "dot produced no SVG.\nstdout: " & preview)
    return

  try:
    # State for drag-to-pan
    var dragging = false
    var dragStartX = cint(0)
    var dragStartY = cint(0)
    var scrollStartH = cint(0)
    var scrollStartV = cint(0)

    # Current zoom scale (1.0 = 100%)
    var scale = 1.0

    # We need the natural (unscaled) SVG size from sizeHint
    # Create the widget first, then read its sizeHint after load
    var svgNatW = cint(0)
    var svgNatH = cint(0)

    # We hold pointers to both the svgWidget and scrollArea so vtable
    # handlers can reach scrollbars. We use ref cells to share state.
    var svgWidgetH: pointer = nil
    var scrollAreaH: pointer = nil

    # vtable for QSvgWidget
    var vtbl = new QSvgWidgetVTable

    vtbl[].mousePressEvent = proc(self: QSvgWidget, e: QMouseEvent) {.raises: [], gcsafe.} =
      try:
        if e.button() == LeftButton:
          dragging = true
          dragStartX = e.globalX()
          dragStartY = e.globalY()
          let sa = QAbstractScrollArea(h: scrollAreaH, owned: false)
          scrollStartH = sa.horizontalScrollBar().value()
          scrollStartV = sa.verticalScrollBar().value()
          let cur = QCursor.create(ClosedHandCursor)
          QWidget(h: self.h, owned: false).setCursor(cur)
      except: discard
      QSvgWidgetmousePressEvent(self, e)

    vtbl[].mouseReleaseEvent = proc(self: QSvgWidget, e: QMouseEvent) {.raises: [], gcsafe.} =
      try:
        dragging = false
        let cur = QCursor.create(OpenHandCursor)
        QWidget(h: self.h, owned: false).setCursor(cur)
      except: discard
      QSvgWidgetmouseReleaseEvent(self, e)

    vtbl[].mouseMoveEvent = proc(self: QSvgWidget, e: QMouseEvent) {.raises: [], gcsafe.} =
      try:
        if dragging:
          let dx = dragStartX - e.globalX()
          let dy = dragStartY - e.globalY()
          let sa = QAbstractScrollArea(h: scrollAreaH, owned: false)
          let hbar = sa.horizontalScrollBar()
          let vbar = sa.verticalScrollBar()
          hbar.setValue(scrollStartH + dx)
          vbar.setValue(scrollStartV + dy)
      except: discard

    vtbl[].wheelEvent = proc(self: QSvgWidget, e: QWheelEvent) {.raises: [], gcsafe.} =
      try:
        let mods = e.modifiers()
        if (mods and CtrlModifier) != 0:
          # Zoom: Ctrl+wheel scales the SVG widget
          var delta: float64
          if e.hasPixelDelta():
            delta = float64(e.pixelDelta().y())
          else:
            delta = float64(e.angleDelta().y()) / WheelAngleDivisor * WheelPixelStep

          let oldScale = scale
          scale = scale * (1.0 + delta * ZoomSensitivity)
          if scale < MinZoom: scale = MinZoom
          if scale > MaxZoom: scale = MaxZoom

          let newW = cint(float64(svgNatW) * scale)
          let newH = cint(float64(svgNatH) * scale)
          let w = QWidget(h: self.h, owned: false)
          w.resize(newW, newH)
          w.setMinimumSize(newW, newH)

          # Adjust scroll so we zoom toward the mouse position
          let sa = QAbstractScrollArea(h: scrollAreaH, owned: false)
          let hbar = sa.horizontalScrollBar()
          let vbar = sa.verticalScrollBar()
          let ratio = scale / oldScale
          hbar.setValue(cint(float64(hbar.value()) * ratio))
          vbar.setValue(cint(float64(vbar.value()) * ratio))
        else:
          # Plain scroll: pass to base
          QSvgWidgetwheelEvent(self, e)
      except: discard

    var svgWidget = QSvgWidget.create(vtbl = vtbl)
    svgWidget.owned = false
    svgWidgetH = svgWidget.h

    let svgBytes = cast[seq[byte]](svgResult)
    svgWidget.load(toOpenArray(svgBytes, 0, svgBytes.high))

    # Read natural size after load
    let hint = svgWidget.sizeHint()
    svgNatW = hint.width()
    svgNatH = hint.height()
    if svgNatW <= 0: svgNatW = FallbackSvgWidth
    if svgNatH <= 0: svgNatH = FallbackSvgHeight

    # Set initial size and tracking
    let w = QWidget(h: svgWidgetH, owned: false)
    w.resize(svgNatW, svgNatH)
    w.setMinimumSize(svgNatW, svgNatH)
    w.setMouseTracking(true)
    let openCur = QCursor.create(OpenHandCursor)
    w.setCursor(openCur)

    var scrollArea = QScrollArea.create()
    scrollArea.owned = false
    scrollAreaH = scrollArea.h
    scrollArea.setWidget(QWidget(h: svgWidgetH, owned: false))
    scrollArea.setWidgetResizable(false)

    var closeBtn = QPushButton.create("Close")
    closeBtn.owned = false
    closeBtn.onClicked do() {.raises: [].}:
      QWidget(h: dialogH, owned: false).hide()

    var btnRow = QHBoxLayout.create()
    btnRow.owned = false
    btnRow.addStretch()
    btnRow.addWidget(QWidget(h: closeBtn.h, owned: false))

    var mainLayout = QVBoxLayout.create()
    mainLayout.owned = false
    mainLayout.addWidget(QWidget(h: scrollArea.h, owned: false))
    mainLayout.addLayout(QLayout(h: btnRow.h, owned: false))
    QWidget(h: dialogH, owned: false).setLayout(QLayout(h: mainLayout.h, owned: false))

    discard QDialog(h: dialogH, owned: false).exec()
  except: discard
