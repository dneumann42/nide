import std/[os, strutils]
import seaqt/[qwidget, qshortcut, qpushbutton, qvboxlayout, qhboxlayout, qlayout, qlabel, qpaintevent,
              qstackedwidget, qfiledialog, qplaintextedit, qfont, qfontmetrics,
              qpixmap, qpaintdevice, qpainter, qcolor, qicon, qsize,
              qsvgrenderer, qabstractbutton, qkeysequence,
              qpalette, qlineargradient,
              qlineedit, qcheckbox, qtextdocument, qtextcursor, qtextedit,
              qregularexpression, qbrush, qtextformat, qtextobject, qprocess,
              qevent, qhelpevent, qtooltip, qpoint, qrect]
import bench/[buffers, logparser, nimcheck, widgetref]

{.compile("search_extra.cpp", gorge("pkg-config --cflags Qt6Widgets")).}
proc createDefaultExtraSelection(): pointer {.importc: "QTextEditExtraSelection_createDefault".}
proc QWidget_virtbase(src: pointer, outQObject: ptr pointer, outPaintDevice: ptr pointer) {.importc: "QWidget_virtbase".}

proc widgetToPaintDevice(w: QWidget): QPaintDevice =
  var outQObject: pointer
  var outPaintDevice: pointer
  QWidget_virtbase(w.h, addr outQObject, addr outPaintDevice)
  QPaintDevice(h: outPaintDevice, owned: false)

type
  PaneEventKind* = enum
    peFileSelected, peClose, peVSplit, peHSplit,
    peNewModule, peOpenModule, peOpenProject

  PaneEvent* = object
    pane*: Pane
    case kind*: PaneEventKind
    of peFileSelected:
      path*: string
    else: discard

  Pane* = ref object
    container: QWidget
    headerBar: QWidget
    label: QLabel
    statusLabel: QLabel
    stack: QStackedWidget
    openModuleWidget: QWidget
    editor: QPlainTextEdit
    emptyDoc: WidgetRef[QTextDocument]
    changed*: bool
    buffer*: Buffer
    eventCb: proc(ev: PaneEvent) {.raises: [].}
    moduleBtnsRow: WidgetRef[QWidget]
    openProjectRow: WidgetRef[QWidget]
    searchBar:     WidgetRef[QWidget]
    searchInput:   WidgetRef[QLineEdit]
    caseCheck:     WidgetRef[QCheckBox]
    regexCheck:    WidgetRef[QCheckBox]
    matchPositions: seq[(cint, cint)]
    matchIndex:     int
    checkProcessH:  ref pointer
    diagLines:      ref seq[LogLine]

  EditorWidget* = ref object of QPlainTextEdit

const StatusDark = ""
const StatusLight = "★"

const VsplitSvg = staticRead("icons/vsplit.svg")
const HsplitSvg = staticRead("icons/hsplit.svg")
const SaveSvg = staticRead("icons/save.svg")

proc svgIcon(svg: string, size: cint): QIcon =
  var pm = QPixmap.create(size, size)
  pm.fill(QColor.create("transparent"))
  var painter = QPainter.create(QPaintDevice(h: pm.h, owned: false))
  var renderer = QSvgRenderer.create(svg.toOpenArrayByte(0, svg.high))
  renderer.render(painter)
  discard painter.endX()
  QIcon.create(pm)

proc widget*(pane: Pane): QWidget =
  QWidget(h: pane.container.h, owned: false)

proc formatDiagTooltip(diags: seq[LogLine]): string {.raises: [].} =
  for d in diags:
    let prefix = case d.level
      of llError: "Error"
      of llWarning: "Warning"
      of llHint: "Hint"
      else: "Note"
    if result.len > 0: result.add "\n"
    result.add prefix & ": " & d.raw

proc diagAtPos(pane: Pane, pos: cint): seq[LogLine] {.raises: [].} =
  if pane.diagLines == nil or pane.buffer == nil: return
  try:
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    let doc = ed.document()
    for ll in pane.diagLines[]:
      if ll.level == llOther or ll.line < 1: continue
      if ll.file != pane.buffer.path: continue
      if doc.blockCount() < ll.line: continue
      let blk = doc.findBlockByNumber(cint(ll.line - 1))
      let start = blk.position() + cint(max(0, ll.col - 1))
      var cur = ed.textCursor()
      cur.setPosition(start)
      discard cur.movePosition(cint 14, cint 1)  # EndOfWord, KeepAnchor
      let endPos = cur.position()
      if pos >= start and pos < endPos:
        result.add(ll)
  except: discard

proc applySelections*(pane: Pane) {.raises: [].} =
  try:
    let ed  = QPlainTextEdit(h: pane.editor.h, owned: false)
    let doc = ed.document()
    var sels: seq[QTextEditExtraSelection]

    # Search matches
    if pane.matchPositions.len > 0:
      var fmt = QTextCharFormat.create()
      QTextFormat(h: fmt.h, owned: false).setBackground(
        QBrush.create(QColor.create("#4a4a00")))
      for (s, e) in pane.matchPositions:
        var cur = ed.textCursor()
        cur.setPosition(s)
        cur.setPosition(e, cint(QTextCursorMoveModeEnum.KeepAnchor))
        var sel = QTextEditExtraSelection(h: createDefaultExtraSelection(), owned: true)
        sel.setCursor(cur)
        sel.setFormat(fmt)
        sels.add(sel)

    # Diagnostics
    if pane.diagLines != nil and pane.buffer != nil:
      for ll in pane.diagLines[]:
        if ll.level == llOther or ll.line < 1: continue
        if ll.file != pane.buffer.path: continue
        let colorStr = case ll.level
          of llError:   "#ff5555"
          of llWarning: "#ffaa00"
          of llHint:    "#00cccc"
          else:         continue
        if doc.blockCount() < ll.line: continue
        let blk = doc.findBlockByNumber(cint(ll.line - 1))
        var cur = ed.textCursor()
        cur.setPosition(blk.position() + cint(max(0, ll.col - 1)))
        discard cur.movePosition(cint 14, cint 1)  # EndOfWord, KeepAnchor
        var fmt = QTextCharFormat.create()
        fmt.setUnderlineStyle(cint 7)  # SpellCheckUnderline
        fmt.setUnderlineColor(QColor.create(colorStr))
        var sel = QTextEditExtraSelection(h: createDefaultExtraSelection(), owned: true)
        sel.setCursor(cur)
        sel.setFormat(fmt)
        sels.add(sel)

    ed.setExtraSelections(sels)
  except: discard

proc runCheck*(pane: Pane) {.raises: [].} =
  if pane.checkProcessH[] != nil:
    try: QProcess(h: pane.checkProcessH[], owned: false).kill()
    except: discard
    pane.checkProcessH[] = nil
  if pane.buffer == nil or pane.buffer.path.len == 0: return
  if not pane.buffer.path.endsWith(".nim"): return
  let filePath = pane.buffer.path
  runNimCheck(pane.container.h, filePath, pane.checkProcessH,
    proc(lines: seq[LogLine]) {.raises: [].} =
      pane.diagLines[] = lines
      applySelections(pane))

proc save*(pane: Pane) {.raises: [].} =
  if pane.buffer != nil and pane.buffer.path.len > 0:
    try:
      writeFile(pane.buffer.path, QPlainTextEdit(h: pane.editor.h, owned: false).toPlainText())
      runCheck(pane)
      QPlainTextEdit(h: pane.editor.h, owned: false).document().setModified(false)
    except:
      discard

proc lineNumberAreaWidth*(editor: QPlainTextEdit): cint =
  let digits = max(1, ($editor.blockCount()).len)
  let fm = QFontMetrics.create(editor.document().defaultFont())
  cint(fm.horizontalAdvance("0") * digits + 8)

proc updateLineNumberAreaWidth(editor: QPlainTextEdit) =
  editor.setViewportMargins(editor.lineNumberAreaWidth(), 0, 0, 0)

proc lineNumberAreaPaintEvent(editor: QPlainTextEdit, event: QPaintEvent, gutter: QWidget) {.raises: [].} =
  try:
    let editorFont = editor.document().defaultFont()
    var painter = QPainter.create(widgetToPaintDevice(gutter))
    painter.setFont(editorFont)
    painter.fillRect(event.rect(), QColor.create("#1a1a1a"))
    var blk = editor.firstVisibleBlock()
    let offset = editor.contentOffset()
    let w = gutter.width()
    while blk.isValid():
      let geo = editor.blockBoundingGeometry(blk)
      let top = cint(geo.top() + offset.y())
      let blockH = cint(geo.height())
      if top >= gutter.height(): break
      let numStr = $(blk.blockNumber() + 1)
      painter.setPen(QColor.create("#606060"))
      painter.drawText(0, top, w - 4, blockH, cint(0x0082), numStr)
      blk = blk.next()
    discard painter.endX()
  except: discard

proc newPane*(
  onEvent: proc(ev: PaneEvent) {.raises: [].}
): Pane =
  result = Pane()
  new(result.checkProcessH); result.checkProcessH[] = nil
  new(result.diagLines);     result.diagLines[]     = @[]
  let pane = result

  # --- Open Project row (shown when no project is open) ---
  var openProjectBtn = QPushButton.create("Open Project")
  openProjectBtn.owned = false

  var openProjectLayout = QHBoxLayout.create(); openProjectLayout.owned = false
  openProjectLayout.addStretch()
  openProjectLayout.addWidget(QWidget(h: openProjectBtn.h, owned: false))
  openProjectLayout.addStretch()

  var openProjectRow = QWidget.create()
  openProjectRow.owned = false
  openProjectRow.setLayout(QLayout(h: openProjectLayout.h, owned: false))

  # --- Module buttons row (shown when project is open) ---
  var newModuleBtn = QPushButton.create("New Module")
  newModuleBtn.owned = false
  var openModuleBtn = QPushButton.create("Open Module")
  openModuleBtn.owned = false

  var moduleBtnsLayout = QHBoxLayout.create(); moduleBtnsLayout.owned = false
  moduleBtnsLayout.addStretch()
  moduleBtnsLayout.addWidget(QWidget(h: newModuleBtn.h, owned: false))
  moduleBtnsLayout.addWidget(QWidget(h: openModuleBtn.h, owned: false))
  moduleBtnsLayout.addStretch()

  var moduleBtnsRow = QWidget.create()
  moduleBtnsRow.owned = false
  moduleBtnsRow.setLayout(QLayout(h: moduleBtnsLayout.h, owned: false))
  QWidget(h: moduleBtnsRow.h, owned: false).hide()  # hidden until project opened

  # --- Outer layout for page 0 ---
  var layout = QVBoxLayout.create(); layout.owned = false
  layout.addStretch()
  layout.addWidget(QWidget(h: openProjectRow.h, owned: false))
  layout.addWidget(QWidget(h: moduleBtnsRow.h, owned: false))
  layout.addStretch()

  var openModuleWidget = QWidget.create()
  openModuleWidget.owned = false
  openModuleWidget.setLayout(QLayout(h: layout.h, owned: false))
  openModuleWidget.setFocusPolicy(cint 2)  # Qt::ClickFocus

  var gutterH: pointer = nil
  var editorVtbl = new QPlainTextEditVTable
  editorVtbl.resizeEvent = proc(self: QPlainTextEdit, e: QResizeEvent) {.raises: [], gcsafe.} =
    QPlainTextEditresizeEvent(self, e)
    if gutterH == nil: return
    let cr = QWidget(h: self.h, owned: false).contentsRect()
    QWidget(h: gutterH, owned: false).setGeometry(
      cr.left(), cr.top(), self.lineNumberAreaWidth(), cr.height())
  editorVtbl.event = proc(self: QPlainTextEdit, e: QEvent): bool {.raises: [], gcsafe.} =
    if e.typeX() == cint(QEventTypeEnum.ToolTip):
      let he = QHelpEvent(h: e.h, owned: false)
      let cur = self.cursorForPosition(he.pos())
      let diags = diagAtPos(pane, cur.position())
      if diags.len > 0:
        QToolTip.showText(he.globalPos(), formatDiagTooltip(diags),
          QWidget(h: self.h, owned: false))
      else:
        QToolTip.hideText()
      return true
    QPlainTextEditevent(self, e)
  
  var editor = QPlainTextEdit.create(vtbl = editorVtbl)
  editor.owned = false
  editor.setFrameStyle(0)

  var editorFont = QFont.create("Fira Code")
  editorFont.setPointSize(14)
  editorFont.setStyleHint(cint(QFontStyleHintEnum.TypeWriter))

  QWidget(h: editor.h, owned: false).setFont(editorFont)

  let editorH = editor.h
  var gutterVtbl = new QWidgetVTable
  gutterVtbl.paintEvent = proc(self: QWidget, event: QPaintEvent) {.raises: [], gcsafe.} =
    lineNumberAreaPaintEvent(QPlainTextEdit(h: editorH, owned: false), event, self)
  var gutter = QWidget.create(QWidget(h: editor.h, owned: false), cint(0), vtbl = gutterVtbl)
  gutter.owned = false
  gutterH = gutter.h

  editor.updateLineNumberAreaWidth()

  editor.onBlockCountChanged do(count: cint) {.raises: [].}:
    QPlainTextEdit(h: editorH, owned: false).updateLineNumberAreaWidth()

  editor.onUpdateRequest do(rect: QRect, dy: cint) {.raises: [].}:
    let g = QWidget(h: gutterH, owned: false)
    if dy != 0:
      g.scroll(cint 0, dy)
    else:
      g.update(0, rect.y(), g.width(), rect.height())
    let ed = QPlainTextEdit(h: editorH, owned: false)
    if rect.contains(ed.viewport().rect()):
      ed.updateLineNumberAreaWidth()

  var stack = QStackedWidget.create()
  stack.owned = false
  discard stack.addWidget(QWidget(h: openModuleWidget.h, owned: false))
  discard stack.addWidget(QWidget(h: editor.h, owned: false))

  var label = QLabel.create("")
  label.owned = false

  var statusLabel = QLabel.create(StatusDark)
  statusLabel.owned = false

  const IconSize = 10

  var vSplitBtn = QPushButton.create("")
  vSplitBtn.owned = false
  vSplitBtn.setFlat(true)
  QWidget(h: vSplitBtn.h, owned: false).setFixedSize(cint 18, cint 18)
  QAbstractButton(h: vSplitBtn.h, owned: false).setIcon(svgIcon(VsplitSvg, cint IconSize))
  QAbstractButton(h: vSplitBtn.h, owned: false).setIconSize(QSize.create(cint IconSize, cint IconSize))

  var hSplitBtn = QPushButton.create("")
  hSplitBtn.owned = false
  hSplitBtn.setFlat(true)
  QWidget(h: hSplitBtn.h, owned: false).setFixedSize(cint 18, cint 18)
  QAbstractButton(h: hSplitBtn.h, owned: false).setIcon(svgIcon(HsplitSvg, cint IconSize))
  QAbstractButton(h: hSplitBtn.h, owned: false).setIconSize(QSize.create(cint IconSize, cint IconSize))

  var closeBtn = QPushButton.create("×")
  closeBtn.owned = false
  closeBtn.setFlat(true)
  QWidget(h: closeBtn.h, owned: false).setFixedSize(cint 18, cint 18)

  var saveBtn = QPushButton.create("")
  saveBtn.owned = false
  saveBtn.setFlat(true)
  QWidget(h: saveBtn.h, owned: false).setFixedSize(cint 18, cint 18)
  QAbstractButton(h: saveBtn.h, owned: false).setIcon(svgIcon(SaveSvg, cint IconSize))
  QAbstractButton(h: saveBtn.h, owned: false).setIconSize(QSize.create(cint IconSize, cint IconSize))

  var headerLayout = QHBoxLayout.create()
  headerLayout.owned = false
  QLayout(h: headerLayout.h, owned: false).setContentsMargins(cint 4, cint 2, cint 4, cint 2)
  headerLayout.addWidget(QWidget(h: label.h, owned: false), cint(0), cint(0))
  headerLayout.addWidget(QWidget(h: statusLabel.h, owned: false), cint(0), cint(0))
  headerLayout.addStretch()
  headerLayout.addWidget(QWidget(h: saveBtn.h, owned: false), cint(0), cint(0))
  headerLayout.addWidget(QWidget(h: vSplitBtn.h, owned: false), cint(0), cint(0))
  headerLayout.addWidget(QWidget(h: hSplitBtn.h, owned: false), cint(0), cint(0))
  headerLayout.addWidget(QWidget(h: closeBtn.h, owned: false), cint(0), cint(0))

  var headerBar = QWidget.create()
  headerBar.owned = false
  headerBar.setLayout(QLayout(h: headerLayout.h, owned: false))

  # --- Search bar ---
  var searchInput = QLineEdit.create()
  searchInput.owned = false
  searchInput.setPlaceholderText("Search…")

  var caseCheck = QCheckBox.create("Aa")
  caseCheck.owned = false

  var regexCheck = QCheckBox.create(".*")
  regexCheck.owned = false

  var prevBtn = QPushButton.create("▲")
  prevBtn.owned = false
  prevBtn.setFlat(true)
  QWidget(h: prevBtn.h, owned: false).setFixedSize(cint 22, cint 22)

  var nextBtn = QPushButton.create("▼")
  nextBtn.owned = false
  nextBtn.setFlat(true)
  QWidget(h: nextBtn.h, owned: false).setFixedSize(cint 22, cint 22)

  var searchCloseBtn = QPushButton.create("×")
  searchCloseBtn.owned = false
  searchCloseBtn.setFlat(true)
  QWidget(h: searchCloseBtn.h, owned: false).setFixedSize(cint 22, cint 22)

  var searchLayout = QHBoxLayout.create()
  searchLayout.owned = false
  QLayout(h: searchLayout.h, owned: false).setContentsMargins(cint 4, cint 2, cint 4, cint 2)
  searchLayout.addWidget(QWidget(h: searchInput.h, owned: false), cint 1, cint 0)
  searchLayout.addWidget(QWidget(h: caseCheck.h, owned: false), cint 0, cint 0)
  searchLayout.addWidget(QWidget(h: regexCheck.h, owned: false), cint 0, cint 0)
  searchLayout.addWidget(QWidget(h: prevBtn.h, owned: false), cint 0, cint 0)
  searchLayout.addWidget(QWidget(h: nextBtn.h, owned: false), cint 0, cint 0)
  searchLayout.addWidget(QWidget(h: searchCloseBtn.h, owned: false), cint 0, cint 0)

  var searchBar = QWidget.create()
  searchBar.owned = false
  searchBar.setLayout(QLayout(h: searchLayout.h, owned: false))
  QWidget(h: searchBar.h, owned: false).hide()

  # Outer container: header bar + search bar + stack
  var outerLayout = QVBoxLayout.create()
  outerLayout.owned = false
  QLayout(h: outerLayout.h, owned: false).setContentsMargins(cint 0, cint 0, cint 0, cint 0)
  QLayout(h: outerLayout.h, owned: false).setSpacing(cint 0)
  outerLayout.addWidget(QWidget(h: headerBar.h, owned: false), cint(0), cint(0))
  outerLayout.addWidget(QWidget(h: searchBar.h, owned: false), cint(0), cint(0))
  outerLayout.addWidget(QWidget(h: stack.h, owned: false), cint(0), cint(0))
  var container = QWidget.create()
  container.owned = false
  container.setAutoFillBackground(true)
  container.setLayout(QLayout(h: outerLayout.h, owned: false))

  result.container = container
  result.headerBar = headerBar
  result.label = label
  result.statusLabel = statusLabel
  result.stack = stack
  result.openModuleWidget = openModuleWidget
  result.editor = editor
  var emptyDoc = QTextDocument.create()
  emptyDoc.owned = false
  emptyDoc.setDefaultFont(editorFont)
  result.emptyDoc        = capture(emptyDoc)
  result.eventCb         = onEvent
  result.moduleBtnsRow   = capture(moduleBtnsRow)
  result.openProjectRow  = capture(openProjectRow)
  result.searchBar       = capture(searchBar)
  result.searchInput     = capture(searchInput)
  result.caseCheck       = capture(caseCheck)
  result.regexCheck      = capture(regexCheck)

  openProjectBtn.onClicked do() {.raises: [].}:
    onEvent(PaneEvent(pane: pane, kind: peOpenProject))
  newModuleBtn.onClicked do() {.raises: [].}:
    onEvent(PaneEvent(pane: pane, kind: peNewModule))
  openModuleBtn.onClicked do() {.raises: [].}:
    onEvent(PaneEvent(pane: pane, kind: peOpenModule))

  vSplitBtn.onClicked do() {.raises: [].}:
    onEvent(PaneEvent(pane: pane, kind: peVSplit))
  hSplitBtn.onClicked do() {.raises: [].}:
    onEvent(PaneEvent(pane: pane, kind: peHSplit))
  closeBtn.onClicked do() {.raises: [].}:
    onEvent(PaneEvent(pane: pane, kind: peClose))

  # --- Search helpers ---
  proc moveToCurrent(pane: Pane) {.raises: [].} =
    if pane.matchPositions.len == 0: return
    let (s, e) = pane.matchPositions[pane.matchIndex]
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    var cur = ed.textCursor()
    cur.setPosition(s)
    cur.setPosition(e, cint(QTextCursorMoveModeEnum.KeepAnchor))
    ed.setTextCursor(cur)
    ed.ensureCursorVisible()

  proc doSearchImpl(pane: Pane) {.raises: [].} =
    let ed    = QPlainTextEdit(h: pane.editor.h, owned: false)
    let inp   = pane.searchInput.get()
    let query = inp.text()
    if query.len == 0:
      pane.matchPositions = @[]
      applySelections(pane)
      return
    let caseSens = QAbstractButton(h: pane.caseCheck.h, owned: false).isChecked()
    let useRx    = QAbstractButton(h: pane.regexCheck.h, owned: false).isChecked()
    let flags    = if caseSens: cint(QTextDocumentFindFlagEnum.FindCaseSensitively)
                   else: cint(0)

    var rx = QRegularExpression.create(query)
    if not caseSens:
      rx.setPatternOptions(
        cint(QRegularExpressionPatternOptionEnum.CaseInsensitiveOption))

    let doc = ed.document()
    var pos     = cint(0)
    var matches: seq[(cint, cint)]

    while true:
      var cur = if useRx: doc.find(rx, pos)
                else:     doc.find(query, pos, flags)
      if cur.isNull(): break
      let s = cur.selectionStart()
      let e = cur.selectionEnd()
      if e <= pos: break  # zero-length match guard
      matches.add((s, e))
      pos = e

    pane.matchPositions = matches
    pane.matchIndex     = 0
    applySelections(pane)
    moveToCurrent(pane)

  proc closeSearch(pane: Pane) {.raises: [].} =
    pane.searchBar.get().hide()
    pane.matchPositions = @[]
    applySelections(pane)
    QWidget(h: pane.editor.h, owned: false).setFocus()

  saveBtn.onClicked do() {.raises: [].}: save(pane)

  # --- Search signal connections ---
  searchInput.onTextChanged do(text: openArray[char]) {.raises: [].}:
    doSearchImpl(pane)

  caseCheck.onStateChanged do(state: cint) {.raises: [].}:
    doSearchImpl(pane)

  regexCheck.onStateChanged do(state: cint) {.raises: [].}:
    doSearchImpl(pane)

  searchInput.onReturnPressed do() {.raises: [].}:
    if pane.matchPositions.len > 0:
      pane.matchIndex = (pane.matchIndex + 1) mod pane.matchPositions.len
      moveToCurrent(pane)

  nextBtn.onClicked do() {.raises: [].}:
    if pane.matchPositions.len > 0:
      pane.matchIndex = (pane.matchIndex + 1) mod pane.matchPositions.len
      moveToCurrent(pane)

  prevBtn.onClicked do() {.raises: [].}:
    if pane.matchPositions.len > 0:
      pane.matchIndex =
        (pane.matchPositions.len + pane.matchIndex - 1) mod pane.matchPositions.len
      moveToCurrent(pane)

  searchCloseBtn.onClicked do() {.raises: [].}:
    closeSearch(pane)

  # --- Ctrl+D shortcut: show diagnostics at cursor ---
  var diagSc = QShortcut.create(QKeySequence.create("Ctrl+D"),
                                QObject(h: pane.container.h, owned: false))
  diagSc.owned = false
  diagSc.setContext(cint 1)  # WidgetWithChildrenShortcut
  diagSc.onActivated do() {.raises: [].}:
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    let cur = ed.textCursor()
    let diags = diagAtPos(pane, cur.position())
    if diags.len > 0:
      let rect = ed.cursorRect()
      let globalPos = QWidget(h: ed.h, owned: false).mapToGlobal(
        QPoint.create(rect.left(), rect.top() + rect.height()))
      QToolTip.showText(globalPos, formatDiagTooltip(diags),
        QWidget(h: ed.h, owned: false))

proc setHeaderFocus*(pane: Pane, focused: bool, isDark: bool) =
  let hbw = QWidget(h: pane.headerBar.h, owned: false)
  if focused:
    var grad = QLinearGradient.create(0.0, 0.0, 0.0, 1.0)
    QGradient(h: grad.h, owned: false).setCoordinateMode(cint QGradientCoordinateModeEnum.ObjectMode)
    if isDark:
      QGradient(h: grad.h, owned: false).setColorAt(0.0, QColor.create("#1e3a5c"))
      QGradient(h: grad.h, owned: false).setColorAt(1.0, QColor.create("#000000"))
    else:
      QGradient(h: grad.h, owned: false).setColorAt(0.0, QColor.create("#b8d4f0"))
      QGradient(h: grad.h, owned: false).setColorAt(1.0, QColor.create("#e8e8e8"))
    var brush = QBrush.create(QGradient(h: grad.h, owned: false))
    var pal = QPalette.create()
    pal.setBrush(cint QPaletteColorRoleEnum.Window, brush)
    hbw.setPalette(pal)
    hbw.setAutoFillBackground(true)
  else:
    var grad = QLinearGradient.create(0.0, 0.0, 0.0, 1.0)
    QGradient(h: grad.h, owned: false).setCoordinateMode(cint QGradientCoordinateModeEnum.ObjectMode)
    if isDark:
      QGradient(h: grad.h, owned: false).setColorAt(0.0, QColor.create("#0b1623"))
      QGradient(h: grad.h, owned: false).setColorAt(1.0, QColor.create("#000000"))
    else:
      QGradient(h: grad.h, owned: false).setColorAt(0.0, QColor.create("#596b7c"))
      QGradient(h: grad.h, owned: false).setColorAt(1.0, QColor.create("#e8e8e8"))
    var brush = QBrush.create(QGradient(h: grad.h, owned: false))
    var pal = QPalette.create()
    pal.setBrush(cint QPaletteColorRoleEnum.Window, brush)
    hbw.setPalette(pal)
    hbw.setAutoFillBackground(true)

proc setBuffer*(pane: Pane, buf: Buffer) =
  var displayName = buf.name
  try: displayName = relativePath(buf.name, getCurrentDir())
  except: discard
  pane.label.setText(displayName)
  let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
  ed.setDocument(buf.document())
  pane.buffer = buf
  buf.document().onModificationChanged do(modified: bool) {.raises: [].}:
    if pane.buffer != buf: return
    pane.changed = modified
    pane.statusLabel.setText(if modified: StatusLight else: StatusDark)
  pane.stack.setCurrentIndex(cint(1))
  pane.searchBar.get().hide()
  pane.matchPositions = @[]
  pane.diagLines[] = @[]
  applySelections(pane)
  runCheck(pane)

proc clearBuffer*(pane: Pane) =
  pane.label.setText("")
  let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
  ed.setDocument(pane.emptyDoc.get())
  pane.changed = false
  pane.statusLabel.setText(StatusDark)
  pane.stack.setCurrentIndex(cint(0))
  pane.buffer = nil
  pane.searchBar.get().hide()
  pane.matchPositions = @[]
  pane.diagLines[] = @[]

proc openModuleDialog*(pane: Pane) {.raises: [].} =
  let fn = QFileDialog.getOpenFileName(QWidget(h: pane.container.h, owned: false))
  if fn.len > 0:
    pane.eventCb(PaneEvent(pane: pane, kind: peFileSelected, path: fn))

proc triggerNewModule*(pane: Pane) {.raises: [].} =
  pane.eventCb(PaneEvent(pane: pane, kind: peNewModule))

proc triggerOpenModule*(pane: Pane) {.raises: [].} =
  discard

proc triggerFind*(pane: Pane) {.raises: [].} =
  pane.searchBar.get().show()
  QWidget(h: pane.searchInput.h, owned: false).setFocus()
  let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
  let inp = pane.searchInput.get()
  let query = inp.text()
  if query.len == 0:
    pane.matchPositions = @[]
    applySelections(pane)
    return
  let caseSens = QAbstractButton(h: pane.caseCheck.h, owned: false).isChecked()
  let useRx = QAbstractButton(h: pane.regexCheck.h, owned: false).isChecked()
  let flags = if caseSens: cint(QTextDocumentFindFlagEnum.FindCaseSensitively) else: cint(0)
  var rx = QRegularExpression.create(query)
  if not caseSens:
    rx.setPatternOptions(cint(QRegularExpressionPatternOptionEnum.CaseInsensitiveOption))
  let doc = ed.document()
  var pos = cint(0)
  var matches: seq[(cint, cint)]
  while true:
    var cur = if useRx: doc.find(rx, pos) else: doc.find(query, pos, flags)
    if cur.isNull(): break
    let s = cur.selectionStart()
    let e = cur.selectionEnd()
    if e <= pos: break
    matches.add((s, e))
    pos = e
  pane.matchPositions = matches
  pane.matchIndex = 0
  applySelections(pane)
  if pane.matchPositions.len > 0:
    let s = pane.matchPositions[0][0]
    let e = pane.matchPositions[0][1]
    var cur = ed.textCursor()
    cur.setPosition(s)
    cur.setPosition(e, cint(QTextCursorMoveModeEnum.KeepAnchor))
    ed.setTextCursor(cur)
    ed.ensureCursorVisible()

proc closeSearch*(pane: Pane) {.raises: [].} =
  pane.searchBar.get().hide()
  pane.matchPositions = @[]
  applySelections(pane)
  QWidget(h: pane.editor.h, owned: false).setFocus()

proc setProjectOpen*(pane: Pane, open: bool) =
  pane.moduleBtnsRow.get().setVisible(open)
  pane.openProjectRow.get().setVisible(not open)

proc focus*(pane: Pane) {.raises: [].} =
  if pane.buffer != nil:
    QWidget(h: pane.editor.h, owned: false).setFocus()
  else:
    pane.container.setFocus()

proc jumpToLine*(pane: Pane, lineNum: int, col: int = 0) {.raises: [].} =
  if pane.buffer == nil: return
  let ed  = QPlainTextEdit(h: pane.editor.h, owned: false)
  let doc = ed.document()
  let blk = doc.findBlockByNumber(cint(lineNum - 1))
  var cur = ed.textCursor()
  cur.setPosition(blk.position())
  if col > 0:
    discard cur.movePosition(cint 19, cint 0, cint(col - 1))  # Right, MoveAnchor, col-1 times
  ed.setTextCursor(cur)
  ed.ensureCursorVisible()
