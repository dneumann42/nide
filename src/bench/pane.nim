import std/[os, strutils]
import seaqt/[qwidget, qshortcut, qpushbutton, qvboxlayout, qhboxlayout, qlayout, qlabel, qpaintevent,
              qstackedwidget, qfiledialog, qplaintextedit, qfont, qfontmetrics,
              qpixmap, qpaintdevice, qpainter, qcolor, qicon, qsize,
              qsvgrenderer, qabstractbutton, qkeysequence,
              qpalette, qlineargradient,
              qlineedit, qcheckbox, qtextdocument, qtextcursor, qtextedit,
              qregularexpression, qbrush, qtextformat, qtextobject, qprocess,
              qevent, qhelpevent, qtooltip, qpoint, qrect, qscrollbar,
              qmouseevent, qkeyevent]
import bench/[buffers, logparser, nimcheck, widgetref, syntaxtheme, nimsuggest, nimfinddef, autocomplete]

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
    peNewModule, peOpenModule, peOpenProject,
    peGotoDefinition, peJumpBack, peJumpForward

  PaneEvent* = object
    pane*: Pane
    case kind*: PaneEventKind
    of peFileSelected:
      path*: string
    of peGotoDefinition:
      defFile*: string
      defLine*: int
      defCol*: int
    of peJumpBack:
      backFile*: string
      backLine*: int
      backCol*: int
    of peJumpForward:
      fwdFile*: string
      fwdLine*: int
      fwdCol*: int
    else: discard

  JumpLocation* = object
    file*: string
    line*: int
    col*: int

  Pane* = ref object
    container*: QWidget
    headerBar: QWidget
    label: QLabel
    statusLabel: QLabel
    stack: QStackedWidget
    openModuleWidget: QWidget
    editor*: QPlainTextEdit
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
    jumpHistory*:  seq[JumpLocation]
    jumpFuture*:   seq[JumpLocation]
    nimSuggest*:   NimSuggestClient
    matchIndex:     int
    checkProcessH:  ref pointer
    diagLines:      ref seq[LogLine]
    autocompleteMenu: AutocompleteMenu
    autocompleteJustOpened: bool  ## suppress the keyPressEvent that triggered open

  EditorWidget* = ref object of QPlainTextEdit

proc applyEditorTheme*(pane: Pane) {.raises: [].}
proc triggerJumpBack*(pane: Pane) {.raises: [].}
proc triggerJumpForward*(pane: Pane) {.raises: [].}
proc triggerGotoDefinition*(pane: Pane, client: NimSuggestClient) {.raises: [].}
proc triggerAutocomplete*(pane: Pane, client: NimSuggestClient) {.raises: [].}

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
  cint(fm.horizontalAdvance("0") * digits + 12)

proc updateLineNumberAreaWidth(editor: QPlainTextEdit) =
  editor.setViewportMargins(editor.lineNumberAreaWidth(), 0, 0, 0)

proc lineNumberAreaPaintEvent(editor: QPlainTextEdit, event: QPaintEvent, gutter: QWidget) {.raises: [].} =
  try:
    let editorFont = editor.document().defaultFont()
    var painter = QPainter.create(widgetToPaintDevice(gutter))
    painter.setFont(editorFont)
    painter.fillRect(event.rect(), QColor.create(gutterBackground()))
    # Draw right edge border
    let w = gutter.width()
    let h = gutter.height()
    painter.setPen(QColor.create("#333333"))
    painter.drawLine(cint(w - 1), 0, cint(w - 1), h)
    # Draw bottom edge border
    painter.drawLine(0, h - 1, w - 1, h - 1)
    var blk = editor.firstVisibleBlock()
    let offset = editor.contentOffset()
    while blk.isValid():
      let geo = editor.blockBoundingGeometry(blk)
      let top = cint(geo.top() + offset.y())
      let blockH = cint(geo.height())
      if top >= gutter.height(): break
      let numStr = $(blk.blockNumber() + 1)
      let lineH = cint(QFontMetrics.create(editorFont).height())
      painter.setPen(QColor.create(gutterForeground()))
      painter.drawText(0, top, w - 4, lineH, cint(0x0022), numStr)
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
    let evType = e.typeX()
    if evType == cint(QEventTypeEnum.ToolTip):
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
  editorVtbl.keyPressEvent = proc(self: QPlainTextEdit, e: QKeyEvent) {.raises: [], gcsafe.} =
    if pane.autocompleteMenu.isOpen():
      let key = e.key()
      let mods = e.modifiers()
      let ctrlMod = cint(0x04000000)  # Qt::ControlModifier
      if (mods and ctrlMod) != 0 and key == cint(0x4e):  # Ctrl+N
        {.cast(gcsafe).}: pane.autocompleteMenu.nextItem()
        return  # consume — do not pass to QPlainTextEdit
      elif (mods and ctrlMod) != 0 and key == cint(0x50):  # Ctrl+P
        {.cast(gcsafe).}: pane.autocompleteMenu.prevItem()
        return
      elif key == cint(0x01000004) or key == cint(0x01000005):  # Return / Enter
        {.cast(gcsafe).}: pane.autocompleteMenu.accept()
        return  # consume the Return so no newline is inserted
      elif key == cint(0x01000000):  # Escape
        {.cast(gcsafe).}: pane.autocompleteMenu.dismiss()
        return
      else:
        # Suppress the very first keyPressEvent after the menu opens — it's
        # the Ctrl+Space (or key repeat) that triggered the open.
        if pane.autocompleteJustOpened:
          {.cast(gcsafe).}: pane.autocompleteJustOpened = false
        else:
          echo "[pane] keyPress dismissing menu: key=0x", key.toHex(), " mods=0x", mods.toHex()
          {.cast(gcsafe).}: pane.autocompleteMenu.dismiss()
    QPlainTextEditkeyPressEvent(self, e)
  editorVtbl.mousePressEvent = proc(self: QPlainTextEdit, e: QMouseEvent) {.raises: [], gcsafe.} =
    # Any mouse click dismisses the autocomplete menu
    if pane.autocompleteMenu.isOpen():
      {.cast(gcsafe).}: pane.autocompleteMenu.dismiss()
    let btn = e.button()
    if btn == cint(8):   # Qt::BackButton / XButton1
      {.cast(gcsafe).}:
        if pane.jumpHistory.len > 0:
          let loc = pane.jumpHistory[^1]
          pane.jumpHistory.setLen(pane.jumpHistory.len - 1)
          pane.eventCb(PaneEvent(
            pane: pane,
            kind: peJumpBack,
            backFile: loc.file,
            backLine: loc.line,
            backCol:  loc.col
          ))
    elif btn == cint(16):  # Qt::ForwardButton / XButton2
      {.cast(gcsafe).}:
        if pane.jumpFuture.len > 0:
          let loc = pane.jumpFuture[^1]
          pane.jumpFuture.setLen(pane.jumpFuture.len - 1)
          pane.eventCb(PaneEvent(
            pane: pane,
            kind: peJumpForward,
            fwdFile: loc.file,
            fwdLine: loc.line,
            fwdCol:  loc.col
          ))
    elif btn == cint(1) and (e.modifiers() and cint(67108864)) != 0:  # LeftButton + Ctrl
      # Let Qt place the cursor at the click position first, then query
      QPlainTextEditmousePressEvent(self, e)
      {.cast(gcsafe).}:
        if pane.nimSuggest != nil:
          pane.triggerGotoDefinition(pane.nimSuggest)
    else:
      QPlainTextEditmousePressEvent(self, e)

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
  QWidget(h: gutter.h, owned: false).setStyleSheet("background: #000000; border-bottom: 1px solid #333333;")
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
  headerBar.setObjectName("headerBar")
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
    let (rightColor, _) = headerGradientColors(isDark)
    hbw.setStyleSheet("#headerBar { background: qlineargradient(x1:0, y1:0, x2:1, y2:0, stop:0 #000000, stop:0.95 " & rightColor & "); }")
  else:
    hbw.setStyleSheet("#headerBar { background: #000000; }")

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
  applyEditorTheme(pane)
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
  pane.eventCb(PaneEvent(pane: pane, kind: peOpenModule))

proc triggerOpenProject*(pane: Pane) {.raises: [].} =
  pane.eventCb(PaneEvent(pane: pane, kind: peOpenProject))

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

proc triggerGotoDefinition*(pane: Pane, client: NimSuggestClient) {.raises: [].} =
  if pane.buffer == nil or pane.buffer.path.len == 0:
    return
  let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
  let cur = ed.textCursor()
  let pos = cur.position()
  let doc = ed.document()
  let textBlock = doc.findBlock(pos)
  let lineNum = textBlock.blockNumber() + 1
  let colNum = cur.columnNumber()   # nimsuggest expects 0-based columns

  let filePath = pane.buffer.path
  if filePath.len == 0:
    return

  # Record current location before jumping so the back button can return here
  let fromLoc = JumpLocation(file: filePath, line: lineNum, col: colNum)

  client.queryDef(
    filePath,
    lineNum,
    colNum,
    proc(def: Definition) {.raises: [].} =
      pane.jumpHistory.add(fromLoc)
      pane.jumpFuture = @[]   # new branch clears forward history
      pane.eventCb(PaneEvent(
        pane: pane,
        kind: peGotoDefinition,
        defFile: def.file,
        defLine: def.line,
        defCol: def.col
      )),
    proc(msg: string) {.raises: [].} =
      echo "Goto definition error: " & msg
  )

proc triggerAutocomplete*(pane: Pane, client: NimSuggestClient) {.raises: [].} =
  if pane.buffer == nil or pane.buffer.path.len == 0:
    return
  let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
  let cur = ed.textCursor()
  let pos = cur.position()
  let doc = ed.document()
  let textBlock = doc.findBlock(pos)
  let lineNum = textBlock.blockNumber() + 1
  let colNum = cur.columnNumber()

  let filePath = pane.buffer.path
  if filePath.len == 0:
    return

  let paneRef = pane
  echo "[pane] triggerAutocomplete called at ", lineNum, ":", colNum
  if paneRef.autocompleteMenu.isOpen():
    echo "[pane] Autocomplete menu already showing, ignoring"
    return
  if client.pending.len > 0:
    echo "[pane] Query already in-flight, ignoring"
    return
  # Capture the trigger-time absolute character position so insertTextCb
  # can locate and replace the typed prefix precisely at accept time.
  let triggerPos = pos
  let edRef = ed
  client.querySug(
    filePath,
    lineNum,
    colNum,
    proc(completions: seq[Completion]) {.raises: [].} =
      if completions.len == 0:
        return

      proc insertTextCb(text: string) {.raises: [].} =
        let e = QPlainTextEdit(h: paneRef.editor.h, owned: false)
        let cur = e.textCursor()
        # Move to the trigger position, then extend selection back to the
        # start of the word — this selects only the typed prefix and replaces
        # it with the chosen completion. We do NOT use select(WordUnderCursor)
        # because that operates on the cursor's *current* position which may
        # differ from where the user was when they triggered autocomplete.
        let acceptPos = cur.position()
        # Select from start-of-word at trigger position to acceptPos
        cur.setPosition(triggerPos)
        discard cur.movePosition(cint(QTextCursorMoveOperationEnum.StartOfWord),
                                  cint(QTextCursorMoveModeEnum.MoveAnchor))
        let wordStart = cur.position()
        cur.setPosition(wordStart)
        cur.setPosition(acceptPos, cint(QTextCursorMoveModeEnum.KeepAnchor))
        cur.insertText(text)
        e.setTextCursor(cur)

      proc closeCb() {.raises: [].} =
        echo "[pane] autocomplete closeCb fired"
        paneRef.autocompleteMenu = nil

      paneRef.autocompleteJustOpened = true
      showCompletions(
        edRef,
        completions,
        insertTextCb,
        closeCb,
        addr(paneRef.autocompleteMenu)
      ),
    proc(msg: string) {.raises: [].} =
      echo "[autocomplete] Error callback: " & msg
  )

proc triggerJumpBack*(pane: Pane) {.raises: [].} =
  ## Pop the last jump location and navigate back to it.
  if pane.jumpHistory.len == 0: return
  let loc = pane.jumpHistory[^1]
  pane.jumpHistory.setLen(pane.jumpHistory.len - 1)
  pane.eventCb(PaneEvent(
    pane: pane,
    kind: peJumpBack,
    backFile: loc.file,
    backLine: loc.line,
    backCol:  loc.col
  ))

proc triggerJumpForward*(pane: Pane) {.raises: [].} =
  ## Pop the next jump location and navigate forward to it.
  if pane.jumpFuture.len == 0: return
  let loc = pane.jumpFuture[^1]
  pane.jumpFuture.setLen(pane.jumpFuture.len - 1)
  pane.eventCb(PaneEvent(
    pane: pane,
    kind: peJumpForward,
    fwdFile: loc.file,
    fwdLine: loc.line,
    fwdCol:  loc.col
  ))

proc closeSearch*(pane: Pane) {.raises: [].} =
  pane.searchBar.get().hide()
  pane.matchPositions = @[]
  applySelections(pane)
  QWidget(h: pane.editor.h, owned: false).setFocus()

proc zoomIn*(pane: Pane) {.raises: [].} =
  try:
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    var font = ed.document().defaultFont()
    font.setPointSize(font.pointSize() + cint 1)
    QWidget(h: ed.h, owned: false).setFont(font)
    ed.document().setDefaultFont(font)
    ed.updateLineNumberAreaWidth()
  except: discard

proc zoomOut*(pane: Pane) {.raises: [].} =
  try:
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    var font = ed.document().defaultFont()
    let newSize = max(font.pointSize() - cint 1, cint 6)
    font.setPointSize(newSize)
    QWidget(h: ed.h, owned: false).setFont(font)
    ed.document().setDefaultFont(font)
    ed.updateLineNumberAreaWidth()
  except: discard

proc setProjectOpen*(pane: Pane, open: bool) =
  pane.moduleBtnsRow.get().setVisible(open)
  pane.openProjectRow.get().setVisible(not open)

proc focus*(pane: Pane) {.raises: [].} =
  if pane.buffer != nil:
    QWidget(h: pane.editor.h, owned: false).setFocus()
  else:
    pane.container.setFocus()

proc applyEditorTheme*(pane: Pane) {.raises: [].} =
  ## Apply current syntax theme colors to the editor widget and gutter
  try:
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    let bg = editorBackground()
    let fg = editorForeground()
    # Set background via stylesheet for QPlainTextEdit and its viewport
    QWidget(h: pane.editor.h, owned: false).setStyleSheet(
      "QPlainTextEdit, QPlainTextEdit viewport { background: " & bg & "; color: " & fg & "; }")
    # Force gutter repaint
    ed.updateLineNumberAreaWidth()
    ed.viewport().update()
  except: discard

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

proc scrollToLine*(pane: Pane, line: int, col: int = 0) {.raises: [].} =
  if pane.buffer == nil: return
  let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
  let doc = ed.document()
  if line > 0 and line <= ed.blockCount():
    let targetBlock = doc.findBlockByNumber(cint(line - 1))
    var cur = ed.textCursor()
    cur.setPosition(targetBlock.position())
    if col > 0:
      discard cur.movePosition(cint 19, cint 0, cint(col - 1))  # Right, MoveAnchor
    ed.setTextCursor(cur)
    ed.centerCursor()
