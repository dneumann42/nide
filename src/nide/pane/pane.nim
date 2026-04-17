import nide/pane/logic
export logic
import nide/editor/autocomplete, nide/editor/buffers, nide/editor/sexpr_parse, commands, nide/editor/funcprototype, nide/helpers/logparser, nide/nim/nimcheck, nide/nim/nimfinddef, nide/nim/nimimports, nide/nim/nimindex, nide/nim/nimsuggest, nide/settings/[syntaxtheme, theme], nide/helpers/widgetref, nide/ui/[sexprview, widgets]
import nide/helpers/[debuglog, qtconst]
import seaqt/[qabstractbutton, qabstractitemview, qabstractscrollarea, qabstractslider, qbrush, qcheckbox, qclipboard, qcolor, qcursor, qevent, qfiledialog, qfont, qfontmetrics, qguiapplication, qhboxlayout, qheaderview, qicon, qkeyevent, qkeysequence, qlabel, qlayout, qlineargradient, qlineedit, qlistwidget, qlistwidgetitem, qmessagebox, qmouseevent, qpaintdevice, qpainter, qpaintevent, qpalette, qpixmap, qplaintextdocumentlayout, qplaintextedit, qpoint, qprocess, qpushbutton, qrect, qregularexpression, qresizeevent, qscrollarea, qscrollbar, qscroller, qscrollerproperties, qshortcut, qsize, qstackedwidget, qsvgrenderer, qtableview, qtablewidget, qtablewidgetitem, qtextcursor, qtextdocument, qtextedit, qtextformat, qtextobject, qtimer, qvariant, qvboxlayout, qwheelevent, qwidget]
import std/[math, options, os, strutils]

{.compile("../search_extra.cpp", gorge("pkg-config --cflags Qt6Widgets")).}
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
    peNewModule, peOpenModule, peOpenProject, peNewProject, peOpenRecentProject,
    peGotoDefinition, peJumpBack, peJumpForward,
    peSave, peFindFile, peSwitchBuffer, peDeleteOtherWindows,
    peRestoreLastSession, peStateChanged

  PaneEvent* = object
    pane*: Pane
    case kind*: PaneEventKind
    of peFileSelected:
      path*: string
    of peOpenRecentProject:
      projectPath*: string
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

  Pane* = ref object
    container*: QWidget
    headerBar: QWidget
    label: QLabel
    statusLabel: QLabel
    stack: QStackedWidget
    openModuleWidget: QWidget
    editor*: QPlainTextEdit
    sexprView*: SExprView
    sexprPage: QScrollArea
    imagePage: QWidget
    imageScroll: QScrollArea
    imageLabel: QLabel
    imageFilterCheck: WidgetRef[QCheckBox]
    imageZoomLabel: QLabel
    imageScale: float64
    imageUserZoomed: bool
    emptyDoc: WidgetRef[QTextDocument]
    changed*: bool
    buffer*: Buffer
    editorWheelScrollSpeed*: float64
    showLineNumbers*: bool
    eventCb: proc(ev: PaneEvent) {.raises: [].}
    moduleBtnsRow: WidgetRef[QWidget]
    openProjectRow: WidgetRef[QWidget]
    recentProjectsList: WidgetRef[QTableWidget]
    recentProjectsLabel: WidgetRef[QLabel]
    restoreSessionBtn: WidgetRef[QPushButton]
    recentProjectPaths: seq[string]
    searchBar:     WidgetRef[QWidget]
    searchInput:   WidgetRef[QLineEdit]
    caseCheck:     WidgetRef[QCheckBox]
    regexCheck:    WidgetRef[QCheckBox]
    matchPositions: seq[(cint, cint)]
    bracketMatchPositions: seq[(cint, cint)]
    markActive: bool
    rectangleMarkActive: bool
    markPos: cint
    jumpHistory*:  seq[JumpLocation]
    jumpFuture*:   seq[JumpLocation]
    nimSuggest*:   NimSuggestClient
    nimCommandProvider*: proc(): string {.raises: [].}
    nimBackendProvider*: proc(): string {.raises: [].}
    matchIndex:     int
    checkProcessH:  ref pointer
    diagLines:      ref seq[LogLine]
    diagPopupH:     pointer  # viewport-child QWidget popup, nil until first hover
    diagLabelH:     pointer  # QLabel inside diagPopup
    diagShownLine:  int      # line of the diagnostic currently in the popup
    diagShownCol:   int      # col of the diagnostic currently in the popup
    diagReady:      bool     # true once nim check has returned at least once for this buffer
    diagHideTimerH: pointer  # single-shot QTimer that hides the popup after a delay
    autocompleteRefreshTimerH: pointer
    autocompleteMenu: AutocompleteMenu
    prototypeWindow: PrototypeWindow
    autocompleteJustOpened: bool  ## suppress the keyPressEvent that triggered open
    dispatcher*: CommandDispatcher
    saveBtn:        WidgetRef[QPushButton]
    vSplitBtn:      WidgetRef[QPushButton]
    hSplitBtn:      WidgetRef[QPushButton]
    closeBtn:       WidgetRef[QPushButton]
    hintBtn:        WidgetRef[QPushButton]
    warnBtn:        WidgetRef[QPushButton]
    errBtn:         WidgetRef[QPushButton]
    diagPopoverH:   pointer
    diagPopoverListH: pointer
    diagPopoverLayoutH: pointer

  EditorWidget* = ref object of QPlainTextEdit

  AutocompleteTrigger* = enum
    atCommand
    atRefresh

proc scrollUp*(pane: Pane) {.raises: [].}
proc scrollDown*(pane: Pane) {.raises: [].}
proc setEditorWheelScrollSpeed*(pane: Pane, speed: int) {.raises: [].}
proc setEditorFont*(pane: Pane, family: string, size: int) {.raises: [].}
proc setLineNumbersVisible*(pane: Pane, visible: bool) {.raises: [].}
proc applySelections*(pane: Pane) {.raises: [].}
proc applyEditorTheme*(pane: Pane) {.raises: [].}
proc closeSearch*(pane: Pane) {.raises: [].}
proc triggerJumpBack*(pane: Pane) {.raises: [].}
proc triggerJumpForward*(pane: Pane) {.raises: [].}
proc triggerGotoDefinition*(pane: Pane, client: NimSuggestClient) {.raises: [].}
proc triggerAutocomplete*(pane: Pane, client: NimSuggestClient,
                          trigger: AutocompleteTrigger = atCommand) {.raises: [].}
proc triggerPrototype*(pane: Pane) {.raises: [].}
proc triggerCleanImports*(pane: Pane) {.raises: [].}
proc showPrototypeAtCursor*(pane: Pane) {.raises: [].}
proc updatePrototypeAtCursor*(pane: Pane) {.raises: [].}
proc clearMarkState*(pane: Pane, clearNativeSelection = true) {.raises: [].}
proc activateMark*(pane: Pane) {.raises: [].}
proc activateRectangleMark*(pane: Pane) {.raises: [].}
proc moveCursor*(pane: Pane, op: cint, count: cint = 1): bool {.raises: [].}
proc copyRegion*(pane: Pane) {.raises: [].}
proc killRegion*(pane: Pane) {.raises: [].}
proc refreshImageView(pane: Pane) {.raises: [].}
proc fitImageToPane(pane: Pane) {.raises: [].}

const StatusDark = ""
const StatusLight = "★"

const VsplitSvg = staticRead("icons/vsplit.svg")
const HsplitSvg = staticRead("icons/hsplit.svg")
const SaveSvg = staticRead("icons/save.svg")
const AutocompleteRefreshMs = cint 120

const
  DiagBtnFontSize = "11px"
  # DiagPopupFontSize = "13px"
  DiagPopupYOffset = cint 18
  LineNumberPadding = 12
  WelcomeCardMinWidth = cint 480
  CardMargin = cint 20
  CardSpacing = cint 10
  OuterMargin = cint 40
  HeaderButtonSize = cint 18
  HeaderButtonMinWidth = cint 24
  SearchButtonSize = cint 22
  DiagHideMs = cint 500
  MinFontSize = cint 6
  ScrollStepPx = 10.0
  ScrollAnimMs = cint 80
  WheelAngleDivisor = 120.0
  DefaultWheelPixelStep = 10.0
  PopoverYOffset = cint 24
  MaxPopoverHeight = cint 400
  ImageZoomStep = 1.25
  MinImageZoom = 0.1
  MaxImageZoom = 16.0

proc widget*(pane: Pane): QWidget =
  QWidget(h: pane.container.h, owned: false)

proc isImageBuffer(pane: Pane): bool =
  pane.buffer != nil and pane.buffer.kind == bkImage

proc updateImageZoomLabel(pane: Pane) {.raises: [].} =
  if pane.imageZoomLabel.h == nil:
    return
  let pct = max(int(round(pane.imageScale * 100.0)), 1)
  pane.imageZoomLabel.setText($pct & "%")

proc refreshImageView(pane: Pane) {.raises: [].} =
  if pane.buffer == nil or pane.buffer.kind != bkImage or pane.imageScroll.h == nil:
    return
  let pixmap = pane.buffer.pixmap()
  if pixmap.h == nil or pixmap.isNull():
    pane.imageLabel.setText("Could not render image")
    pane.imageZoomLabel.setText("0%")
    return

  let viewport = QAbstractScrollArea(h: pane.imageScroll.h, owned: false).viewport()
  let targetW = max(cint(round(float64(pixmap.width()) * pane.imageScale)), cint 1)
  let targetH = max(cint(round(float64(pixmap.height()) * pane.imageScale)), cint 1)
  let mode =
    if pane.imageFilterCheck.get().isChecked():
      SmoothTransformation
    else:
      FastTransformation
  let scaled = pixmap.scaled(targetW, targetH, KeepAspectRatio, mode)
  pane.imageLabel.setPixmap(scaled)
  pane.imageLabel.asWidget.resize(scaled.size())
  if scaled.width() < viewport.width() or scaled.height() < viewport.height():
    QScrollArea(h: pane.imageScroll.h, owned: false).ensureVisible(
      max(scaled.width() div 2, cint 0),
      max(scaled.height() div 2, cint 0))
  pane.updateImageZoomLabel()

proc fitImageToPane(pane: Pane) {.raises: [].} =
  if pane.buffer == nil or pane.buffer.kind != bkImage or pane.imageScroll.h == nil:
    return
  let pixmap = pane.buffer.pixmap()
  if pixmap.h == nil or pixmap.isNull():
    pane.imageScale = 1.0
    pane.updateImageZoomLabel()
    return
  let viewport = QAbstractScrollArea(h: pane.imageScroll.h, owned: false).viewport()
  if viewport.width() <= 0 or viewport.height() <= 0:
    pane.imageScale = 1.0
  else:
    let scaleX = float64(viewport.width()) / float64(max(pixmap.width(), cint 1))
    let scaleY = float64(viewport.height()) / float64(max(pixmap.height(), cint 1))
    pane.imageScale = max(min(scaleX, scaleY), MinImageZoom)
  pane.imageUserZoomed = false
  pane.refreshImageView()

proc currentPointPos(pane: Pane): cint =
  let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
  ed.textCursor().position()

proc stopAutocompleteRefresh(pane: Pane) {.raises: [].} =
  if pane.autocompleteRefreshTimerH != nil:
    try: QTimer(h: pane.autocompleteRefreshTimerH, owned: false).stop()
    except CatchableError: discard

proc scheduleAutocompleteRefresh(pane: Pane) {.raises: [].} =
  if pane.autocompleteRefreshTimerH == nil:
    return
  try: QTimer(h: pane.autocompleteRefreshTimerH, owned: false).start()
  except CatchableError: discard

proc dirtyNimSuggestPath(filePath: string): string =
  let tempDir = getTempDir() / "nide-nimsuggest"
  try:
    createDir(tempDir)
  except OSError:
    discard
  filePath.replace('\\', '_').replace('/', '_').replace(':', '_') & ".dirty.nim"

proc writeDirtyNimSuggestFile(pane: Pane): string {.raises: [].} =
  if pane.buffer == nil or pane.buffer.path.len == 0:
    return ""
  let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
  let doc = ed.document()
  if not doc.isModified():
    return ""
  let tempDir = getTempDir() / "nide-nimsuggest"
  try:
    createDir(tempDir)
    let dirtyPath = tempDir / dirtyNimSuggestPath(pane.buffer.path)
    writeFile(dirtyPath, ed.toPlainText())
    return dirtyPath
  except CatchableError:
    return ""

proc syncTransientSelection(pane: Pane) {.raises: [].} =
  let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
  let pointPos = currentPointPos(pane)
  if pane.rectangleMarkActive:
    let cur = ed.textCursor()
    cur.setPosition(pointPos, cint(QTextCursorMoveModeEnum.MoveAnchor))
    ed.setTextCursor(cur)
  elif pane.markActive:
    let cur = ed.textCursor()
    cur.setPosition(pane.markPos, cint(QTextCursorMoveModeEnum.MoveAnchor))
    cur.setPosition(pointPos, cint(QTextCursorMoveModeEnum.KeepAnchor))
    ed.setTextCursor(cur)
  applySelections(pane)

proc clearMarkState*(pane: Pane, clearNativeSelection = true) {.raises: [].} =
  let wasRectangle = pane.rectangleMarkActive
  pane.markActive = false
  pane.rectangleMarkActive = false
  pane.markPos = 0
  if clearNativeSelection:
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    let cur = ed.textCursor()
    let pos = cur.position()
    cur.setPosition(pos, cint(QTextCursorMoveModeEnum.MoveAnchor))
    ed.setTextCursor(cur)
  if wasRectangle:
    applySelections(pane)

proc activateMark*(pane: Pane) {.raises: [].} =
  if pane.isImageBuffer():
    return
  pane.markPos = currentPointPos(pane)
  pane.markActive = true
  pane.rectangleMarkActive = false
  syncTransientSelection(pane)

proc activateRectangleMark*(pane: Pane) {.raises: [].} =
  if pane.isImageBuffer():
    return
  pane.markPos = currentPointPos(pane)
  pane.markActive = false
  pane.rectangleMarkActive = true
  syncTransientSelection(pane)

proc moveCursor*(pane: Pane, op: cint, count: cint = 1): bool {.raises: [].} =
  if pane.isImageBuffer():
    return false
  let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
  let cur = ed.textCursor()
  let mode =
    if pane.rectangleMarkActive: cint(QTextCursorMoveModeEnum.MoveAnchor)
    elif pane.markActive: cint(QTextCursorMoveModeEnum.KeepAnchor)
    else: cint(QTextCursorMoveModeEnum.MoveAnchor)
  result = cur.movePosition(op, mode, count)
  ed.setTextCursor(cur)
  if pane.rectangleMarkActive:
    applySelections(pane)

proc copyRegion*(pane: Pane) {.raises: [].} =
  if pane.isImageBuffer():
    return
  let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
  if pane.rectangleMarkActive:
    let text = ed.document().toPlainText()
    QGuiApplication.clipboard().setText(
      copyRectangleText(text, pane.markPos.int, currentPointPos(pane).int))
    return
  let cur = ed.textCursor()
  if cur.hasSelection():
    QGuiApplication.clipboard().setText($cur.selectedText())

proc killRegion*(pane: Pane) {.raises: [].} =
  if pane.isImageBuffer():
    return
  let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
  if pane.rectangleMarkActive:
    let oldText = ed.document().toPlainText()
    let anchor = offsetToLineCol(oldText, pane.markPos.int)
    let point = offsetToLineCol(oldText, currentPointPos(pane).int)
    let newText = removeRectangleText(oldText, pane.markPos.int, currentPointPos(pane).int)
    QGuiApplication.clipboard().setText(
      copyRectangleText(oldText, pane.markPos.int, currentPointPos(pane).int))
    let cur = ed.textCursor()
    cur.beginEditBlock()
    discard cur.movePosition(cint(QTextCursorMoveOperationEnum.Start),
                             cint(QTextCursorMoveModeEnum.MoveAnchor))
    discard cur.movePosition(cint(QTextCursorMoveOperationEnum.End),
                             cint(QTextCursorMoveModeEnum.KeepAnchor))
    cur.insertText(newText)
    let targetPos = lineColToOffset(newText, min(anchor.line, point.line),
                                    min(anchor.col, point.col))
    cur.setPosition(cint(targetPos), cint(QTextCursorMoveModeEnum.MoveAnchor))
    cur.endEditBlock()
    ed.setTextCursor(cur)
    pane.clearMarkState(clearNativeSelection = false)
    return
  pane.clearMarkState(clearNativeSelection = false)
  ed.cut()

proc hideDiagPopup(pane: Pane) {.raises: [].} =
  if pane.diagHideTimerH != nil:
    try: QTimer(h: pane.diagHideTimerH, owned: false).stop()
    except CatchableError: discard
  if pane.diagPopupH != nil:
    try: QWidget(h: pane.diagPopupH, owned: false).hide()
    except CatchableError: discard
  pane.diagShownLine = 0
  pane.diagShownCol  = 0

proc scheduleDiagHide(pane: Pane) {.raises: [].} =
  if pane.diagHideTimerH == nil: return
  try:
    let t = QTimer(h: pane.diagHideTimerH, owned: false)
    t.stop()
    t.start()
  except CatchableError: discard

proc updateDiagIcons*(pane: Pane) {.raises: [].} =
  if pane.diagLines == nil or pane.buffer == nil: return
  let currentFile = pane.buffer.path
  let (hintCount, warnCount, errCount) = countDiags(pane.diagLines[], currentFile)
  try:
    let hintB = pane.hintBtn.get()
    let warnB = pane.warnBtn.get()
    let errB  = pane.errBtn.get()
    if hintCount > 0:
      hintB.setText("◆" & $hintCount)
      hintB.asWidget.setStyleSheet("QPushButton { color: #00cccc; background: transparent; border: none; font-size: " & DiagBtnFontSize & "; } QPushButton:hover { color: #00eeee; }")
      hintB.asWidget.show()
    else:
      hintB.asWidget.hide()
    if warnCount > 0:
      warnB.setText("⚠" & $warnCount)
      warnB.asWidget.setStyleSheet("QPushButton { color: #ffaa00; background: transparent; border: none; font-size: " & DiagBtnFontSize & "; } QPushButton:hover { color: #ffcc00; }")
      warnB.asWidget.show()
    else:
      warnB.asWidget.hide()
    if errCount > 0:
      errB.setText("✗" & $errCount)
      errB.asWidget.setStyleSheet("QPushButton { color: #ff5555; background: transparent; border: none; font-size: " & DiagBtnFontSize & "; } QPushButton:hover { color: #ff7777; }")
      errB.asWidget.show()
    else:
      errB.asWidget.hide()
  except CatchableError: discard

proc showDiagPopup(pane: Pane, ed: QPlainTextEdit, diags: seq[LogLine],
                   mousePos: QPoint) {.raises: [].} =
  try:
    # If the same diagnostic is already visible, leave it in place so the user
    # can hover over the popup and select / copy text.
    if pane.diagShownLine == diags[0].line and pane.diagShownCol == diags[0].col and
       pane.diagPopupH != nil and
       QWidget(h: pane.diagPopupH, owned: false).isVisible():
      return

    var html = ""
    for d in diags:
      let (label, color) = case d.level
        of llError:   ("Error",   "#ff5555")
        of llWarning: ("Warning", "#ffaa00")
        of llHint:    ("Hint",    "#00cccc")
        else: continue
      if html.len > 0: html.add "<br>"
      let escaped = d.raw.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
      html.add "<span style='color:" & color & ";'>&#9679; <b>" & label & ":</b></span> " & escaped
    if html.len == 0: return

    let viewport = ed.viewport()

    # Create the popup widget lazily (parented to viewport — no mapToGlobal needed)
    if pane.diagPopupH == nil:
      var popup = newWidget(QWidget.create(viewport))
      pane.diagPopupH = popup.h

      QWidget(h: pane.diagPopupH, owned: false).setObjectName("diagPopup")
      QWidget(h: pane.diagPopupH, owned: false).setStyleSheet("""
        QWidget#diagPopup {
          background: #1e1e2e;
          border: 1px solid #585b70;
          border-radius: 3px;
        }
        QLabel {
          color: #cdd6f4;
          font-family: 'Fira Code', monospace;
          font-size: 13px;
          padding: 6px 10px;
          background: transparent;
        }
      """)

      var diagLabel = newWidget(QLabel.create())
      diagLabel.setWordWrap(true)
      diagLabel.setTextFormat(TF_RichText)
      diagLabel.setTextInteractionFlags(TIF_TextSelectableAll)
      pane.diagLabelH = diagLabel.h

      var diagLayout = vbox()
      diagLayout.addWidget(QWidget(h: pane.diagLabelH, owned: false))
      QWidget(h: pane.diagPopupH, owned: false).setLayout(diagLayout.asLayout())

    QLabel(h: pane.diagLabelH, owned: false).setText(html)

    let pw = QWidget(h: pane.diagPopupH, owned: false)
    pw.adjustSize()
    let popupW = pw.width()
    let popupH = pw.height()

    let vpW = viewport.width()
    let vpH = viewport.height()
    var px = mousePos.x()
    var py = mousePos.y() + DiagPopupYOffset
    if px + popupW > vpW: px = max(cint 0, vpW - popupW)
    if py + popupH > vpH: py = max(cint 0, mousePos.y() - popupH)

    pw.setGeometry(px, py, popupW, popupH)
    pw.raiseX()
    pw.show()
    pane.diagShownLine = diags[0].line
    pane.diagShownCol  = diags[0].col
  except CatchableError: discard


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
      discard cur.movePosition(TC_EndOfWord, TM_KeepAnchor)
      let endPos = cur.position()
      if pos >= start and pos < endPos:
        result.add(ll)
  except CatchableError: discard

proc applySelections*(pane: Pane) {.raises: [].} =
  try:
    let ed  = QPlainTextEdit(h: pane.editor.h, owned: false)
    let savedCursor = ed.textCursor()
    let savedScroll = ed.verticalScrollBar().value()
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

    # Bracket matching
    if pane.bracketMatchPositions.len == 2:
      var fmt = QTextCharFormat.create()
      QTextFormat(h: fmt.h, owned: false).setBackground(
        QBrush.create(QColor.create("#264f78")))
      for (s, e) in pane.bracketMatchPositions:
        var cur = ed.textCursor()
        cur.setPosition(s)
        cur.setPosition(e, cint(QTextCursorMoveModeEnum.KeepAnchor))
        var sel = QTextEditExtraSelection(h: createDefaultExtraSelection(), owned: true)
        sel.setCursor(cur)
        sel.setFormat(fmt)
        sels.add(sel)

    # Rectangle mark overlay
    if pane.rectangleMarkActive:
      let text = doc.toPlainText()
      let pointPos = currentPointPos(pane).int
      var fmt = QTextCharFormat.create()
      QTextFormat(h: fmt.h, owned: false).setBackground(
        QBrush.create(QColor.create(selectionColor())))
      for span in rectangleSpans(text, pane.markPos.int, pointPos):
        if span.startCol >= span.endCol or doc.blockCount() <= cint(span.line):
          continue
        let blk = doc.findBlockByNumber(cint(span.line))
        var cur = ed.textCursor()
        cur.setPosition(blk.position() + cint(span.startCol))
        cur.setPosition(blk.position() + cint(span.endCol),
                        cint(QTextCursorMoveModeEnum.KeepAnchor))
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
        discard cur.movePosition(TC_EndOfWord, TM_KeepAnchor)
        var fmt = QTextCharFormat.create()
        fmt.setUnderlineStyle(UL_SpellCheckUnderline)
        fmt.setUnderlineColor(QColor.create(colorStr))
        var sel = QTextEditExtraSelection(h: createDefaultExtraSelection(), owned: true)
        sel.setCursor(cur)
        sel.setFormat(fmt)
        sels.add(sel)

    ed.setExtraSelections(sels)
    ed.setTextCursor(savedCursor)
    ed.verticalScrollBar().setValue(savedScroll)
  except CatchableError:
    logError("pane: applySelections error: ", getCurrentExceptionMsg())

proc updateBracketMatch(pane: Pane) {.raises: [].} =
  try:
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    let cur = ed.textCursor()
    let pos = int(cur.position())
    let text = ed.document().toPlainText()
    pane.bracketMatchPositions = @[]
    const brackets = {'(', ')', '[', ']', '{', '}'}
    var p1 = -1
    if pos < text.len and text[pos] in brackets:
      p1 = pos
    elif pos > 0 and text[pos - 1] in brackets:
      p1 = pos - 1
    if p1 >= 0:
      let p2 = findMatchingBracket(text, p1)
      if p2 >= 0:
        pane.bracketMatchPositions = @[(cint(p1), cint(p1 + 1)),
                                        (cint(p2), cint(p2 + 1))]
    applySelections(pane)
  except CatchableError: discard

proc runCheck*(pane: Pane) {.raises: [].} =
  if pane.checkProcessH[] != nil:
    try: QProcess(h: pane.checkProcessH[], owned: false).kill()
    except CatchableError: discard
    pane.checkProcessH[] = nil
  if pane.buffer == nil or pane.buffer.path.len == 0: return
  if pane.buffer.kind != bkText: return
  if not pane.buffer.path.endsWith(".nim"): return
  let filePath = pane.buffer.path
  let nimCommand =
    if pane.nimCommandProvider != nil: pane.nimCommandProvider()
    else: "nim"
  let nimBackend =
    if pane.nimBackendProvider != nil: pane.nimBackendProvider()
    else: "c"
  runNimCheck(pane.container.h, filePath, nimCommand, nimBackend, pane.checkProcessH,
    proc(lines: seq[LogLine]) {.raises: [].} =
      pane.diagLines[] = lines
      pane.diagReady = true
      applySelections(pane)
      updateDiagIcons(pane))

proc prefillDiags*(pane: Pane, lines: seq[LogLine]) {.raises: [].} =
  ## Pre-populate diagnostics from an already-completed check (e.g. the
  ## project-wide check). The per-pane async check will overwrite these when
  ## it finishes; this just avoids a blank state while waiting.
  pane.diagLines[] = lines
  pane.diagReady = true
  applySelections(pane)
  updateDiagIcons(pane)

proc save*(pane: Pane) {.raises: [].} =
  if pane.buffer != nil and pane.buffer.path.len > 0:
    if pane.buffer.kind notin {bkText, bkSExpr}:
      return
    if pane.buffer.externallyModified:
      let parent = QWidget(h: pane.container.h, owned: false)
      # StandardButton values: Save=2048, Discard=8388608
      let clicked = QMessageBox.warning(
        parent,
        "File Modified Externally",
        "This file was changed outside the editor. Overwrite it with your changes, or discard them and reload from disk?",
        (MsgBox_Save or MsgBox_Discard),
        MsgBox_Save)
      if clicked == MsgBox_Discard:
        try:
          let content = readFile(pane.buffer.path)
          if pane.buffer.kind == bkSExpr:
            pane.buffer.sexpr = parseSExpr(content)
            pane.sexprView.setDocument(pane.buffer.sexpr)
          else:
            pane.buffer.document().setPlainText(content)
            pane.buffer.document().setModified(false)
          pane.buffer.externallyModified = false
        except CatchableError:
          logError("pane: reload file error: ", getCurrentExceptionMsg())
        return
      pane.buffer.externallyModified = false
    try:
      if pane.buffer.kind == bkSExpr:
        writeFile(pane.buffer.path, serializeSExpr(pane.buffer.sexprDocument()))
        pane.buffer.sexpr.dirty = false
        pane.changed = false
        pane.statusLabel.setText(StatusDark)
      else:
        let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
        let savedScroll = ed.verticalScrollBar().value()
        writeFile(pane.buffer.path, ed.toPlainText())
        runCheck(pane)
        ed.document().setModified(false)
        ed.verticalScrollBar().setValue(savedScroll)
    except CatchableError:
      logError("pane: save error: ", getCurrentExceptionMsg())

proc lineNumberAreaWidth*(editor: QPlainTextEdit): cint =
  if not QObject(h: editor.h, owned: false).property("nide.showLineNumbers").toBool():
    return 0
  let digits = max(1, ($editor.blockCount()).len)
  let fm = QFontMetrics.create(editor.document().defaultFont())
  cint(fm.horizontalAdvance("0") * digits + LineNumberPadding)

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
      # let blockH = cint(geo.height())
      if top >= gutter.height(): break
      let numStr = $(blk.blockNumber() + 1)
      let lineH = cint(QFontMetrics.create(editorFont).height())
      painter.setPen(QColor.create(gutterForeground()))
      painter.drawText(0, top, w - 4, lineH, AlignRightVCenter, numStr)
      blk = blk.next()
    discard painter.endX()
  except CatchableError: discard

proc hideDiagPopover(pane: Pane) {.raises: [].} =
  if pane.diagPopoverH != nil:
    try: QWidget(h: pane.diagPopoverH, owned: false).hide()
    except CatchableError: discard

proc showDiagPopover(pane: Pane, filterLevel: LogLevel) {.raises: [].} =
  if pane.diagLines == nil or pane.diagLines[].len == 0: return
  try:
    if pane.diagPopoverH != nil:
      try:
        QWidget(h: pane.diagPopoverH, owned: false).delete()
      except CatchableError: discard
      pane.diagPopoverH = nil
      pane.diagPopoverListH = nil
      pane.diagPopoverLayoutH = nil

    var popover = newWidget(QWidget.create())
    popover.setWindowFlags(WF_PopupFrameless)
    popover.setObjectName("diagPopover")
    popover.setStyleSheet("""
      QWidget#diagPopover {
        background: #1e1e2e;
        border: 1px solid #585b70;
        border-radius: 4px;
      }
      QScrollArea {
        background: transparent;
        border: none;
      }
      QScrollBar:vertical {
        background: #313244;
        width: 8px;
        border-radius: 4px;
      }
      QScrollBar::handle:vertical {
        background: #585b70;
        border-radius: 4px;
        min-height: 20px;
      }
      QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
        height: 0px;
      }
      QLabel {
        color: #cdd6f4;
        font-family: 'Fira Code', monospace;
        font-size: 12px;
        background: transparent;
      }
    """)
    pane.diagPopoverH = popover.h

    var scroll = newWidget(QScrollArea.create(popover))
    scroll.setWidgetResizable(true)
    scroll.setHorizontalScrollBarPolicy(SBP_AlwaysOff)

    var listW = newWidget(QWidget.create(scroll))
    var listLayout = vbox(margins = (cint 4, cint 4, cint 4, cint 4), spacing = cint 2)
    listLayout.applyTo(listW)
    pane.diagPopoverListH = listW.h
    pane.diagPopoverLayoutH = listLayout.h

    scroll.setWidget(listW)
    var popoverLayout = vbox()
    popoverLayout.add(scroll)
    popoverLayout.applyTo(popover)

    for ll in pane.diagLines[]:
      if ll.file != pane.buffer.path: continue
      if ll.level != filterLevel: continue
      let (label, _) = case ll.level
        of llError:   ("Error",   "#ff5555")
        of llWarning: ("Warning", "#ffaa00")
        of llHint:    ("Hint",    "#00cccc")
        else: continue
      let escaped = ll.raw.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
      let text = label & ": " & escaped & " (line " & $ll.line & ")"
      let lineNum = ll.line

      var itemBtn = button(text)
      itemBtn.setStyleSheet(
        "QPushButton { color: #cdd6f4; background: transparent; border: none; text-align: left; padding: 6px 8px; font-family: 'Fira Code', monospace; font-size: 12px; }" &
        "QPushButton:hover { background: #313244; }")
      itemBtn.onClicked do() {.raises: [].}:
        hideDiagPopover(pane)
        if pane.buffer != nil:
          let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
          let doc = ed.document()
          let blk = doc.findBlockByNumber(cint(lineNum - 1))
          var cur = ed.textCursor()
          cur.setPosition(blk.position())
          ed.setTextCursor(cur)
          ed.ensureCursorVisible()

      listLayout.add(itemBtn)

    if listLayout.count() == 0:
      return

    let popW = QWidget(h: pane.diagPopoverH, owned: false)
    popW.adjustSize()
    let pw = popW.width()
    let ph = popW.height()

    var btnPos: QPoint
    case filterLevel
    of llHint: btnPos = pane.hintBtn.get().mapToGlobal(QPoint.create(cint 0, cint 0))
    of llWarning: btnPos = pane.warnBtn.get().mapToGlobal(QPoint.create(cint 0, cint 0))
    of llError: btnPos = pane.errBtn.get().mapToGlobal(QPoint.create(cint 0, cint 0))
    else: btnPos = QPoint.create(cint 0, cint 0)

    var yPos = btnPos.y() + PopoverYOffset

    popW.setGeometry(btnPos.x(), yPos, pw, min(ph, MaxPopoverHeight))
    popW.raiseX()
    popW.show()
  except CatchableError: discard

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
  let caseSens = pane.caseCheck.get().asButton.isChecked()
  let useRx    = pane.regexCheck.get().asButton.isChecked()
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

proc dispatchPaneCommandKey(pane: Pane, key, mods: cint): bool {.raises: [].} =
  if pane.dispatcher == nil:
    return false
  let maybeCombo = commandKeyComboForDispatch(key, mods)
  if maybeCombo.isNone():
    return false
  pane.dispatcher.dispatch(maybeCombo.get())

proc newPane*(
  onEvent: proc(ev: PaneEvent) {.raises: [].}
): Pane =
  result = Pane()
  result.editorWheelScrollSpeed = DefaultWheelPixelStep
  new(result.checkProcessH); result.checkProcessH[] = nil
  new(result.diagLines);     result.diagLines[]     = @[]
  let pane = result

  # --- Open Project row (shown when no project is open) ---
  var newProjectBtn = newWidget(QPushButton.create("New Project"))
  var openProjectBtn = newWidget(QPushButton.create("Open Project"))
  var restoreSessionBtn = newWidget(QPushButton.create("Restore Last Session"))
  restoreSessionBtn.asWidget.setEnabled(false)

  var recentLabel = newWidget(QLabel.create("Recent Projects"))
  recentLabel.asWidget.hide()

  var recentTable = newWidget(QTableWidget.create(cint 0, cint 2))
  let recentTableH = recentTable.h
  recentTable.asWidget.hide()
  QAbstractItemView(h: recentTableH, owned: false).setEditTriggers(cint 0)
  QAbstractItemView(h: recentTableH, owned: false).setSelectionBehavior(cint 1)
  QTableView(h: recentTableH, owned: false).setShowGrid(false)
  QTableWidget(h: recentTableH, owned: false).setHorizontalHeaderLabels(@["Project", "Path"])
  let thdr = QTableView(h: recentTableH, owned: false).horizontalHeader()
  thdr.setSectionResizeMode(cint 0, cint 1)  # ResizeToContents
  thdr.setStretchLastSection(true)
  let vhdr = QTableView(h: recentTableH, owned: false).verticalHeader()
  QWidget(h: vhdr.h, owned: false).setVisible(false)

  recentTable.onCellDoubleClicked do(row: cint, column: cint) {.raises: [].}:
    try:
      if row >= 0 and row < cint(pane.recentProjectPaths.len):
        pane.eventCb(PaneEvent(pane: pane, kind: peOpenRecentProject,
                               projectPath: pane.recentProjectPaths[row]))
    except CatchableError: discard

  # Card: outline border only, palette-inherited background
  var cardWidget = newWidget(QWidget.create())
  cardWidget.setObjectName("welcomeCard")
  cardWidget.setStyleSheet(
    "QWidget#welcomeCard { border: 1px solid #333333; border-radius: 4px; }")
  cardWidget.setMinimumWidth(WelcomeCardMinWidth)

  var cardLayout = vbox(margins = (CardMargin, CardMargin, CardMargin, CardMargin), spacing = CardSpacing)

  var btnRow = hbox()
  btnRow.add(newProjectBtn)
  btnRow.add(openProjectBtn)
  btnRow.add(restoreSessionBtn)
  btnRow.addStretch()

  cardLayout.addSub(btnRow)
  cardLayout.add(recentLabel)
  cardLayout.addWidget(QWidget(h: recentTableH, owned: false))
  cardLayout.applyTo(cardWidget)

  # Outer centering layout
  var openProjectLayout = vbox(margins = (OuterMargin, OuterMargin, OuterMargin, OuterMargin))
  openProjectLayout.addStretch()
  openProjectLayout.add(cardWidget)
  openProjectLayout.addStretch()

  var openProjectRow = newWidget(QWidget.create())
  openProjectLayout.applyTo(openProjectRow)

  pane.recentProjectsList = capture(recentTable)
  pane.recentProjectsLabel = capture(recentLabel)

  # --- Module buttons row (shown when project is open) ---
  var newModuleBtn = newWidget(QPushButton.create("New Module"))
  var openModuleBtn = newWidget(QPushButton.create("Open Module"))

  var moduleBtnsLayout = hbox()
  moduleBtnsLayout.addStretch()
  moduleBtnsLayout.add(newModuleBtn)
  moduleBtnsLayout.add(openModuleBtn)
  moduleBtnsLayout.addStretch()

  var moduleBtnsRow = newWidget(QWidget.create())
  moduleBtnsLayout.applyTo(moduleBtnsRow)
  moduleBtnsRow.hide()  # hidden until project opened

  # --- Outer layout for page 0 ---
  var pageLayout = vbox()
  pageLayout.addStretch()
  pageLayout.add(openProjectRow)
  pageLayout.add(moduleBtnsRow)
  pageLayout.addStretch()

  var openModuleWidget = newWidget(QWidget.create())
  pageLayout.applyTo(openModuleWidget)
  openModuleWidget.setFocusPolicy(FP_ClickFocus)

  var gutterH: pointer = nil
  var editorVtbl = new QPlainTextEditVTable
  editorVtbl.resizeEvent = proc(self: QPlainTextEdit, e: QResizeEvent) {.raises: [], gcsafe.} =
    QPlainTextEditresizeEvent(self, e)
    if gutterH == nil: return
    let cr = QWidget(h: self.h, owned: false).contentsRect()
    QWidget(h: gutterH, owned: false).setGeometry(
      cr.left(), cr.top(), self.lineNumberAreaWidth(), cr.height())
  editorVtbl.event = proc(self: QPlainTextEdit, e: QEvent): bool {.raises: [], gcsafe.} =
    QPlainTextEditevent(self, e)
  editorVtbl.mouseMoveEvent = proc(self: QPlainTextEdit, e: QMouseEvent) {.raises: [], gcsafe.} =
    let cur = self.cursorForPosition(e.pos())
    let diags = diagAtPos(pane, cur.position())
    if diags.len > 0:
      # Cancel any pending hide and show/keep the popup.
      if pane.diagHideTimerH != nil:
        try: QTimer(h: pane.diagHideTimerH, owned: false).stop()
        except CatchableError: discard
      {.cast(gcsafe).}: showDiagPopup(pane, self, diags, e.pos())
    else:
      # Schedule a delayed hide so the user has time to move the mouse into
      # the popup. The timer callback will check underMouse() and restart
      # itself if needed.
      {.cast(gcsafe).}: scheduleDiagHide(pane)
    QPlainTextEditmouseMoveEvent(self, e)
  editorVtbl.leaveEvent = proc(self: QPlainTextEdit, e: QEvent) {.raises: [], gcsafe.} =
    {.cast(gcsafe).}: scheduleDiagHide(pane)
    QPlainTextEditleaveEvent(self, e)
  editorVtbl.keyPressEvent = proc(self: QPlainTextEdit, e: QKeyEvent) {.raises: [], gcsafe.} =
    {.cast(gcsafe).}: hideDiagPopup(pane)
    let key = e.key()
    let mods = e.modifiers()
    let typedText = $e.text()

    if pane.prototypeWindow.isPrototypeVisible():
      if key == Key_Escape:
        {.cast(gcsafe).}: hidePrototype(addr pane.prototypeWindow)
        QPlainTextEditkeyPressEvent(self, e)
        return
      elif key == Key_Return or key == Key_Enter:
        {.cast(gcsafe).}: hidePrototype(addr pane.prototypeWindow)
        QPlainTextEditkeyPressEvent(self, e)
        return
      elif key == Key_Control:
        QPlainTextEditkeyPressEvent(self, e)
        return
      else:
        QPlainTextEditkeyPressEvent(self, e)
        {.cast(gcsafe).}:
          pane.updatePrototypeAtCursor()
        return
    
    if pane.autocompleteMenu.isOpen():
      if (mods and ctrlMod) != 0 and key == Key_N:
        {.cast(gcsafe).}: pane.autocompleteMenu.nextItem()
        return  # consume — do not pass to QPlainTextEdit
      elif (mods and ctrlMod) != 0 and key == Key_P:
        {.cast(gcsafe).}: pane.autocompleteMenu.prevItem()
        return
      elif key == Key_Return or key == Key_Enter:
        if pane.autocompleteMenu.hasExplicitSelection():
          {.cast(gcsafe).}: pane.stopAutocompleteRefresh()
          {.cast(gcsafe).}: pane.autocompleteMenu.accept()
          return  # consume the Return only when accepting a visible choice
        {.cast(gcsafe).}: pane.autocompleteMenu.dismiss()
      elif key == Key_Escape:
        {.cast(gcsafe).}: pane.stopAutocompleteRefresh()
        {.cast(gcsafe).}: pane.autocompleteMenu.dismiss()
        return
      elif shouldRefreshAutocompleteOnKeyPress(key.int, mods.int, typedText):
        {.cast(gcsafe).}: pane.autocompleteJustOpened = false
        {.cast(gcsafe).}:
          if (pane.markActive or pane.rectangleMarkActive) and
             shouldClearMarkOnKeyPress(key.int, mods.int, typedText):
            pane.clearMarkState(clearNativeSelection = pane.rectangleMarkActive)
        QPlainTextEditkeyPressEvent(self, e)
        {.cast(gcsafe).}: pane.scheduleAutocompleteRefresh()
        return
      else:
        # Suppress the very first keyPressEvent after the menu opens — it's
        # the Ctrl+Space (or key repeat) that triggered the open.
        if pane.autocompleteJustOpened:
          {.cast(gcsafe).}: pane.autocompleteJustOpened = false
        elif (mods and (ctrlMod or altMod)) == 0:
          {.cast(gcsafe).}: pane.stopAutocompleteRefresh()
          {.cast(gcsafe).}: pane.autocompleteMenu.dismiss()
    elif key == Key_Tab:  # insert 2 spaces
      {.cast(gcsafe).}:
        if pane.markActive or pane.rectangleMarkActive:
          pane.clearMarkState(clearNativeSelection = pane.rectangleMarkActive)
      let cur = self.textCursor()
      if cur.hasSelection():
        # Indent every selected line by 2 spaces
        let startPos = cur.selectionStart()
        let endPos   = cur.selectionEnd()
        let c = self.textCursor()
        c.beginEditBlock()
        c.setPosition(endPos)
        let endBlock = c.blockNumber()
        c.setPosition(startPos)
        while true:
          discard c.movePosition(cint(QTextCursorMoveOperationEnum.StartOfBlock),
                                  cint(QTextCursorMoveModeEnum.MoveAnchor))
          c.insertText("  ")
          if c.blockNumber() >= endBlock: break
          discard c.movePosition(cint(QTextCursorMoveOperationEnum.NextBlock),
                                  cint(QTextCursorMoveModeEnum.MoveAnchor))
        c.endEditBlock()
        self.setTextCursor(c)
      else:
        cur.insertText("  ")
        self.setTextCursor(cur)
      return

    if (mods and (ctrlMod or altMod)) == 0:
      if typedText.len == 1:
        let ch = typedText[0]
        let maybeClose = autoClosePairFor(ch)
        if maybeClose.isSome():
          {.cast(gcsafe).}:
            if pane.markActive or pane.rectangleMarkActive:
              pane.clearMarkState(clearNativeSelection = pane.rectangleMarkActive)
          let closeCh = maybeClose.get()
          let cur = self.textCursor()
          if cur.hasSelection():
            let selected = $cur.selectedText()
            cur.beginEditBlock()
            cur.insertText($ch & selected & $closeCh)
            discard cur.movePosition(cint(QTextCursorMoveOperationEnum.Left),
                                     cint(QTextCursorMoveModeEnum.MoveAnchor),
                                     cint(1 + selected.len))
            discard cur.movePosition(cint(QTextCursorMoveOperationEnum.Right),
                                     cint(QTextCursorMoveModeEnum.KeepAnchor),
                                     cint(selected.len))
            cur.endEditBlock()
            self.setTextCursor(cur)
          else:
            cur.beginEditBlock()
            cur.insertText($ch & $closeCh)
            discard cur.movePosition(cint(QTextCursorMoveOperationEnum.Left),
                                     cint(QTextCursorMoveModeEnum.MoveAnchor))
            cur.endEditBlock()
            self.setTextCursor(cur)
          return
        elif ch.isAutoCloseCloser():
          let cur = self.textCursor()
          if not cur.hasSelection():
            let pos = cur.position().int
            let text = self.document().toPlainText()
            if shouldSkipAutoCloseCloser(text, pos, ch):
              {.cast(gcsafe).}:
                if pane.markActive or pane.rectangleMarkActive:
                  pane.clearMarkState(clearNativeSelection = false)
              discard cur.movePosition(cint(QTextCursorMoveOperationEnum.Right),
                                       cint(QTextCursorMoveModeEnum.MoveAnchor))
              self.setTextCursor(cur)
              return

    {.cast(gcsafe).}:
      if (pane.markActive or pane.rectangleMarkActive) and
         shouldClearMarkOnKeyPress(key.int, mods.int, typedText):
        pane.clearMarkState(clearNativeSelection = pane.rectangleMarkActive)

    {.cast(gcsafe).}:
      if dispatchPaneCommandKey(pane, key, mods):
        return

    QPlainTextEditkeyPressEvent(self, e)
  editorVtbl.mousePressEvent = proc(self: QPlainTextEdit, e: QMouseEvent) {.raises: [], gcsafe.} =
    # Any mouse click dismisses the autocomplete menu
    if pane.autocompleteMenu.isOpen():
      {.cast(gcsafe).}: pane.stopAutocompleteRefresh()
      {.cast(gcsafe).}: pane.autocompleteMenu.dismiss()
    {.cast(gcsafe).}:
      if pane.markActive or pane.rectangleMarkActive:
        pane.clearMarkState()
    let btn = e.button()
    if btn == MB_BackButton:
      {.cast(gcsafe).}:
        let loc = popJumpBack(pane.jumpHistory)
        if loc.isSome():
          pane.eventCb(PaneEvent(
            pane: pane,
            kind: peJumpBack,
            backFile: loc.get().file,
            backLine: loc.get().line,
            backCol:  loc.get().col
          ))
    elif btn == MB_ForwardButton:
      {.cast(gcsafe).}:
        let loc = popJumpForward(pane.jumpFuture)
        if loc.isSome():
          pane.eventCb(PaneEvent(
            pane: pane,
            kind: peJumpForward,
            fwdFile: loc.get().file,
            fwdLine: loc.get().line,
            fwdCol:  loc.get().col
          ))
    elif btn == MB_LeftButton and (e.modifiers() and ControlModifier) != 0:
      # Let Qt place the cursor at the click position first, then query
      QPlainTextEditmousePressEvent(self, e)
      {.cast(gcsafe).}:
        if pane.nimSuggest != nil:
          pane.triggerGotoDefinition(pane.nimSuggest)
    else:
      QPlainTextEditmousePressEvent(self, e)

  editorVtbl.wheelEvent = proc(self: QPlainTextEdit, e: QWheelEvent) {.raises: [], gcsafe.} =
    try:
      let vp = self.viewport()
      let scroller = QScroller.scroller(QObject(h: vp.h, owned: false))
      let curY = scroller.finalPosition().y
      let maxY = float64(self.verticalScrollBar().maximum())
      var dy: float64
      if e.hasPixelDelta():
        dy = float64(-e.pixelDelta().y)
      else:
        # angleDelta: 120 units per notch on a standard mouse wheel
        dy = float64(-e.angleDelta().y) / WheelAngleDivisor * pane.editorWheelScrollSpeed
      let newY = min(max(curY + dy, 0.0), maxY)
      scroller.scrollTo(QPointF.create(0.0, newY), ScrollAnimMs)
    except CatchableError: discard

  var editor = newWidget(QPlainTextEdit.create(vtbl = editorVtbl))
  editor.setFrameStyle(NoFrame)
  editor.setCenterOnScroll(true)
  editor.viewport().setMouseTracking(true)

  var editorFont = QFont.create("Fira Code")
  editorFont.setPointSize(14)
  editorFont.setStyleHint(cint(QFontStyleHintEnum.TypeWriter))

  editor.asWidget.setFont(editorFont)
  discard QObject(h: editor.h, owned: false).setProperty("nide.showLineNumbers", QVariant.create(true))

  let editorH = editor.h
  var gutterVtbl = new QWidgetVTable
  gutterVtbl.paintEvent = proc(self: QWidget, event: QPaintEvent) {.raises: [], gcsafe.} =
    lineNumberAreaPaintEvent(QPlainTextEdit(h: editorH, owned: false), event, self)
  var gutter = newWidget(QWidget.create(editor.asWidget, cint(0), vtbl = gutterVtbl))
  gutter.setStyleSheet("background: #000000; border-bottom: 1px solid #333333;")
  gutterH = gutter.h

  editor.updateLineNumberAreaWidth()

  editor.onBlockCountChanged do(count: cint) {.raises: [].}:
    QPlainTextEdit(h: editorH, owned: false).updateLineNumberAreaWidth()

  editor.onCursorPositionChanged do() {.raises: [].}:
    updateBracketMatch(pane)
    onEvent(PaneEvent(pane: pane, kind: peStateChanged))

  QAbstractSlider(h: editor.verticalScrollBar().h, owned: false).onValueChanged do(value: cint) {.raises: [].}:
    discard value
    onEvent(PaneEvent(pane: pane, kind: peStateChanged))

  QAbstractSlider(h: editor.horizontalScrollBar().h, owned: false).onValueChanged do(value: cint) {.raises: [].}:
    discard value
    onEvent(PaneEvent(pane: pane, kind: peStateChanged))

  editor.onUpdateRequest do(rect: QRect, dy: cint) {.raises: [].}:
    let g = QWidget(h: gutterH, owned: false)
    if dy != 0:
      g.scroll(cint 0, dy)
    else:
      g.update(0, rect.y(), g.width(), rect.height())
    let ed = QPlainTextEdit(h: editorH, owned: false)
    if rect.contains(ed.viewport().rect()):
      ed.updateLineNumberAreaWidth()

  var imageLabel = newWidget(QLabel.create(""))
  imageLabel.setAlignment(AlignHCenterVCenter)
  imageLabel.asWidget.setMinimumSize(cint 1, cint 1)
  imageLabel.asWidget.setStyleSheet("QLabel { background: transparent; }")

  let paneRef = pane
  var imageScrollVtbl = new QScrollAreaVTable
  imageScrollVtbl.resizeEvent = proc(self: QScrollArea, e: QResizeEvent) {.raises: [], gcsafe.} =
    QScrollArearesizeEvent(self, e)
    {.cast(gcsafe).}:
      if paneRef.imageUserZoomed:
        paneRef.refreshImageView()
      else:
        paneRef.fitImageToPane()
  var imageScroll = newWidget(QScrollArea.create(vtbl = imageScrollVtbl))
  imageScroll.setWidget(imageLabel.asWidget)
  imageScroll.setWidgetResizable(false)
  imageScroll.setAlignment(AlignHCenterVCenter)
  imageScroll.asWidget.setStyleSheet("QScrollArea { border: none; background: " & editorBackground() & "; }")

  var imageFilterCheck = checkbox("Filtering", checked = true)
  imageFilterCheck.clickable do(checked: bool):
    discard checked
    pane.refreshImageView()

  var imageZoomOutBtn = button("-")
  imageZoomOutBtn.asWidget.setFixedHeight(cint 24)
  var imageZoomLabel = newWidget(QLabel.create("100%"))
  imageZoomLabel.setAlignment(AlignHCenterVCenter)
  imageZoomLabel.asWidget.setMinimumWidth(cint 48)
  var imageZoomResetBtn = button("Fit")
  imageZoomResetBtn.asWidget.setFixedHeight(cint 24)
  var imageZoomInBtn = button("+")
  imageZoomInBtn.asWidget.setFixedHeight(cint 24)

  var imageToolbar = hbox(margins = (cint 8, cint 6, cint 8, cint 6), spacing = cint 8)
  imageToolbar.addWidget(imageFilterCheck.asWidget, cint 0, cint 0)
  imageToolbar.addStretch()
  imageToolbar.addWidget(imageZoomOutBtn.asWidget, cint 0, cint 0)
  imageToolbar.addWidget(imageZoomLabel.asWidget, cint 0, cint 0)
  imageToolbar.addWidget(imageZoomResetBtn.asWidget, cint 0, cint 0)
  imageToolbar.addWidget(imageZoomInBtn.asWidget, cint 0, cint 0)

  var imageLayout = vbox()
  imageLayout.addLayout(QLayout(h: imageToolbar.h, owned: false))
  imageLayout.addWidget(imageScroll.asWidget, cint 1, cint 0)
  var imagePage = newWidget(QWidget.create())
  imageLayout.applyTo(imagePage)

  var sexpr = newSExprView(proc() {.raises: [].} =
    pane.changed = true
    pane.statusLabel.setText(StatusLight)
    onEvent(PaneEvent(pane: pane, kind: peStateChanged)))
  var sexprScroll = newWidget(QScrollArea.create())
  sexprScroll.setWidget(sexpr.widget)
  sexprScroll.setWidgetResizable(true)
  sexprScroll.setAlignment(0)
  sexprScroll.asWidget.setStyleSheet("QScrollArea { border: none; background: " & editorBackground() & "; }")

  var stack = newWidget(QStackedWidget.create())
  discard stack.addWidget(openModuleWidget)
  discard stack.addWidget(editor.asWidget)
  discard stack.addWidget(imagePage)
  discard stack.addWidget(sexprScroll.asWidget)

  var label = newWidget(QLabel.create(""))
  var statusLabel = newWidget(QLabel.create(StatusDark))

  var hintBtn = button("")
  hintBtn.asWidget.setSizePolicy(cint 0, cint 0)
  hintBtn.asWidget.setMinimumWidth(HeaderButtonMinWidth)
  hintBtn.asWidget.setFixedHeight(HeaderButtonSize)

  var warnBtn = button("")
  warnBtn.asWidget.setSizePolicy(cint 0, cint 0)
  warnBtn.asWidget.setMinimumWidth(HeaderButtonMinWidth)
  warnBtn.asWidget.setFixedHeight(HeaderButtonSize)

  var errBtn = button("")
  errBtn.asWidget.setSizePolicy(cint 0, cint 0)
  errBtn.asWidget.setMinimumWidth(HeaderButtonMinWidth)
  errBtn.asWidget.setFixedHeight(HeaderButtonSize)

  const IconSize = 10

  var vSplitBtn = button("")
  vSplitBtn.asWidget.setFixedSize(HeaderButtonSize, HeaderButtonSize)
  vSplitBtn.asButton.setIcon(svgIcon(VsplitSvg, cint IconSize))
  vSplitBtn.asButton.setIconSize(QSize.create(cint IconSize, cint IconSize))

  var hSplitBtn = button("")
  hSplitBtn.asWidget.setFixedSize(HeaderButtonSize, HeaderButtonSize)
  hSplitBtn.asButton.setIcon(svgIcon(HsplitSvg, cint IconSize))
  hSplitBtn.asButton.setIconSize(QSize.create(cint IconSize, cint IconSize))

  var closeBtn = button("×")
  closeBtn.asWidget.setFixedSize(HeaderButtonSize, HeaderButtonSize)

  var saveBtn = button("")
  saveBtn.asWidget.setFixedSize(HeaderButtonSize, HeaderButtonSize)
  saveBtn.asButton.setIcon(svgIcon(SaveSvg, cint IconSize))
  saveBtn.asButton.setIconSize(QSize.create(cint IconSize, cint IconSize))

  var headerLayout = hbox(margins = (cint 4, cint 2, cint 4, cint 2))
  headerLayout.addWidget(label.asWidget, cint(0), cint(0))
  headerLayout.addWidget(statusLabel.asWidget, cint(0), cint(0))
  headerLayout.addWidget(hintBtn.asWidget, cint(0), cint(0))
  headerLayout.addWidget(warnBtn.asWidget, cint(0), cint(0))
  headerLayout.addWidget(errBtn.asWidget, cint(0), cint(0))
  headerLayout.addStretch()
  headerLayout.addWidget(saveBtn.asWidget, cint(0), cint(0))
  headerLayout.addWidget(vSplitBtn.asWidget, cint(0), cint(0))
  headerLayout.addWidget(hSplitBtn.asWidget, cint(0), cint(0))
  headerLayout.addWidget(closeBtn.asWidget, cint(0), cint(0))

  var headerBar = newWidget(QWidget.create())
  headerBar.setObjectName("headerBar")
  headerLayout.applyTo(headerBar)

  # --- Search bar ---
  var inputVtbl = new QLineEditVTable
  inputVtbl.keyPressEvent = proc(self: QLineEdit, e: QKeyEvent) {.raises: [], gcsafe.} =
    let key  = e.key()
    let mods = e.modifiers()
    if key == Key_Escape:  # close search
      {.cast(gcsafe).}:
        pane.searchBar.get().hide()
        pane.matchPositions = @[]
        applySelections(pane)
        pane.editor.asWidget.setFocus()
      return
    let relevantMods = mods and (ctrlMod or altMod or shiftMod)
    let kc: KeyCombo = (key, relevantMods)
    {.cast(gcsafe).}:
      if pane.dispatcher != nil and
         pane.dispatcher.lookupCommand(kc) == "editor.findInBuffer":
        if pane.matchPositions.len > 0:
          pane.matchIndex = (pane.matchIndex + 1) mod pane.matchPositions.len
          let (s, ef) = pane.matchPositions[pane.matchIndex]
          let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
          var cur = ed.textCursor()
          cur.setPosition(s)
          cur.setPosition(ef, cint(QTextCursorMoveModeEnum.KeepAnchor))
          ed.setTextCursor(cur)
          ed.ensureCursorVisible()
        return
    QLineEditkeyPressEvent(self, e)
  var searchInput = newWidget(QLineEdit.create(vtbl = inputVtbl))
  searchInput.setPlaceholderText("Search…")

  var caseCheck = checkbox("Aa")
  var regexCheck = checkbox(".*")

  var prevBtn = button("▲")
  prevBtn.asWidget.setFixedSize(SearchButtonSize, SearchButtonSize)

  var nextBtn = button("▼")
  nextBtn.asWidget.setFixedSize(SearchButtonSize, SearchButtonSize)

  var searchCloseBtn = button("×")
  searchCloseBtn.asWidget.setFixedSize(SearchButtonSize, SearchButtonSize)

  var searchLayout = hbox(margins = (cint 4, cint 2, cint 4, cint 2))
  searchLayout.addWidget(searchInput.asWidget, cint 1, cint 0)
  searchLayout.addWidget(caseCheck.asWidget, cint 0, cint 0)
  searchLayout.addWidget(regexCheck.asWidget, cint 0, cint 0)
  searchLayout.addWidget(prevBtn.asWidget, cint 0, cint 0)
  searchLayout.addWidget(nextBtn.asWidget, cint 0, cint 0)
  searchLayout.addWidget(searchCloseBtn.asWidget, cint 0, cint 0)

  var searchBar = newWidget(QWidget.create())
  searchLayout.applyTo(searchBar)
  searchBar.hide()

  # Outer container: header bar + search bar + stack
  var outerLayout = vbox()
  outerLayout.addWidget(headerBar, cint(0), cint(0))
  outerLayout.addWidget(searchBar, cint(0), cint(0))
  outerLayout.addWidget(stack.asWidget, cint(0), cint(0))
  var containerVtbl = new QWidgetVTable
  containerVtbl.keyPressEvent = proc(self: QWidget, e: QKeyEvent) {.raises: [], gcsafe.} =
    {.cast(gcsafe).}:
      if dispatchPaneCommandKey(pane, e.key(), e.modifiers()):
        return
    QWidgetkeyPressEvent(self, e)
  var container = newWidget(QWidget.create(vtbl = containerVtbl))
  container.setAutoFillBackground(true)
  container.setFocusPolicy(FP_ClickFocus)
  outerLayout.applyTo(container)

  result.container = container
  result.headerBar = headerBar
  # Timer that hides the diagnostic popup after a short delay, giving the user
  # time to move the mouse into the popup. Restarted if underMouse() is true.
  var diagHideTimer = newWidget(QTimer.create(QObject(h: result.container.h, owned: false)))
  diagHideTimer.setSingleShot(true)
  diagHideTimer.setInterval(DiagHideMs)
  result.diagHideTimerH = diagHideTimer.h
  diagHideTimer.onTimeout do() {.raises: [].}:
    if pane.diagPopupH != nil and
       QWidget(h: pane.diagPopupH, owned: false).isVisible() and
       QWidget(h: pane.diagPopupH, owned: false).underMouse():
      QTimer(h: pane.diagHideTimerH, owned: false).start()
    else:
      hideDiagPopup(pane)
  var autocompleteRefreshTimer = newWidget(QTimer.create(QObject(h: result.container.h, owned: false)))
  autocompleteRefreshTimer.setSingleShot(true)
  autocompleteRefreshTimer.setInterval(AutocompleteRefreshMs)
  result.autocompleteRefreshTimerH = autocompleteRefreshTimer.h
  autocompleteRefreshTimer.onTimeout do() {.raises: [].}:
    if pane.autocompleteMenu.isOpen() and pane.nimSuggest != nil:
      pane.triggerAutocomplete(pane.nimSuggest, atRefresh)
  result.label = label
  result.statusLabel = statusLabel
  result.stack = stack
  result.openModuleWidget = openModuleWidget
  result.editor = editor
  result.sexprView = sexpr
  result.sexprPage = sexprScroll
  result.imagePage = imagePage
  result.imageScroll = imageScroll
  result.imageLabel = imageLabel
  result.imageFilterCheck = capture(imageFilterCheck)
  result.imageZoomLabel = imageZoomLabel
  result.imageScale = 1.0
  result.imageUserZoomed = false
  result.showLineNumbers = true
  var emptyDoc = newWidget(QTextDocument.create())
  var emptyLayout = newWidget(QPlainTextDocumentLayout.create(emptyDoc))
  emptyDoc.setDocumentLayout(QAbstractTextDocumentLayout(h: emptyLayout.h, owned: false))
  emptyDoc.setDefaultFont(editorFont)
  result.emptyDoc        = capture(emptyDoc)
  result.eventCb         = onEvent
  result.moduleBtnsRow   = capture(moduleBtnsRow)
  result.openProjectRow  = capture(openProjectRow)
  result.recentProjectsList = capture(recentTable)
  result.recentProjectsLabel = capture(recentLabel)
  result.restoreSessionBtn = capture(restoreSessionBtn)
  result.searchBar       = capture(searchBar)
  result.searchInput     = capture(searchInput)
  result.caseCheck       = capture(caseCheck)
  result.regexCheck      = capture(regexCheck)
  result.saveBtn         = capture(saveBtn)
  result.vSplitBtn       = capture(vSplitBtn)
  result.hSplitBtn       = capture(hSplitBtn)
  result.closeBtn        = capture(closeBtn)
  result.hintBtn         = capture(hintBtn)
  result.warnBtn         = capture(warnBtn)
  result.errBtn          = capture(errBtn)

  newProjectBtn.onClicked do() {.raises: [].}:
    onEvent(PaneEvent(pane: pane, kind: peNewProject))
  openProjectBtn.onClicked do() {.raises: [].}:
    onEvent(PaneEvent(pane: pane, kind: peOpenProject))
  restoreSessionBtn.onClicked do() {.raises: [].}:
    onEvent(PaneEvent(pane: pane, kind: peRestoreLastSession))
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

  hintBtn.onClicked do() {.raises: [].}:
    showDiagPopover(pane, llHint)
  warnBtn.onClicked do() {.raises: [].}:
    showDiagPopover(pane, llWarning)
  errBtn.onClicked do() {.raises: [].}:
    showDiagPopover(pane, llError)

  saveBtn.onClicked do() {.raises: [].}: save(pane)

  imageZoomInBtn.onClicked do() {.raises: [].}:
    pane.imageUserZoomed = true
    pane.imageScale = min(pane.imageScale * ImageZoomStep, MaxImageZoom)
    pane.refreshImageView()

  imageZoomOutBtn.onClicked do() {.raises: [].}:
    pane.imageUserZoomed = true
    pane.imageScale = max(pane.imageScale / ImageZoomStep, MinImageZoom)
    pane.refreshImageView()

  imageZoomResetBtn.onClicked do() {.raises: [].}:
    pane.fitImageToPane()

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
  var diagSc = newWidget(QShortcut.create(QKeySequence.create("Ctrl+Shift+D"),
                                          QObject(h: pane.container.h, owned: false)))
  diagSc.setContext(SC_WidgetWithChildrenShortcut)
  diagSc.onActivated do() {.raises: [].}:
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    let cur = ed.textCursor()
    let diags = diagAtPos(pane, cur.position())
    if diags.len > 0:
      let rect = ed.cursorRect()
      showDiagPopup(pane, ed, diags,
        QPoint.create(rect.left(), rect.top() + rect.height()))

proc setHeaderFocus*(pane: Pane, focused: bool, theme: Theme) =
  let iconColor = paneHeaderIconColor(theme, focused)
  const headerIconSize = 10
  if focused:
    let baseColor = paneHeaderBaseColor(theme)
    let accentColor = paneHeaderAccentColor(theme)
    pane.headerBar.setStyleSheet(
      "#headerBar { background: qlineargradient(x1:0, y1:0, x2:1, y2:0, stop:0.7 " &
      baseColor & ", stop:0.99 " & accentColor & "); }")
  else:
    pane.headerBar.setStyleSheet("#headerBar { background: " & paneHeaderBaseColor(theme) & "; }")
  pane.saveBtn.get().asButton.setIcon(svgIcon(SaveSvg, cint headerIconSize, iconColor))
  pane.vSplitBtn.get().asButton.setIcon(svgIcon(VsplitSvg, cint headerIconSize, iconColor))
  pane.hSplitBtn.get().asButton.setIcon(svgIcon(HsplitSvg, cint headerIconSize, iconColor))
  pane.closeBtn.get().asWidget.setStyleSheet("QPushButton { color: " & iconColor & "; }")

proc setBuffer*(pane: Pane, buf: Buffer) =
  pane.stopAutocompleteRefresh()
  var displayName = buf.name
  try: displayName = relativePath(buf.name, getCurrentDir())
  except CatchableError: discard
  pane.label.setText(displayName)
  pane.buffer = buf
  if buf.kind == bkText:
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    ed.setDocument(buf.document())
    buf.document().onModificationChanged do(modified: bool) {.raises: [].}:
      if pane.buffer != buf: return
      pane.changed = modified
      pane.statusLabel.setText(if modified: StatusLight else: StatusDark)
    pane.stack.setCurrentIndex(cint(1))
    pane.searchBar.get().hide()
    pane.saveBtn.get().asWidget.setEnabled(true)
  elif buf.kind == bkSExpr:
    pane.changed = buf.sexprDocument().dirty
    pane.statusLabel.setText(if pane.changed: StatusLight else: StatusDark)
    pane.sexprView.setDocument(buf.sexprDocument())
    pane.stack.setCurrentWidget(pane.sexprPage.asWidget)
    pane.searchBar.get().hide()
    pane.saveBtn.get().asWidget.setEnabled(true)
  else:
    pane.changed = false
    pane.statusLabel.setText(StatusDark)
    pane.stack.setCurrentWidget(pane.imagePage)
    pane.searchBar.get().hide()
    pane.saveBtn.get().asWidget.setEnabled(false)
    pane.imageScale = 1.0
    pane.imageUserZoomed = false
    pane.fitImageToPane()
  pane.searchBar.get().hide()
  pane.markActive = false
  pane.rectangleMarkActive = false
  pane.markPos = 0
  pane.matchPositions = @[]
  pane.diagLines[] = @[]
  pane.diagReady = false
  applySelections(pane)
  updateDiagIcons(pane)
  applyEditorTheme(pane)
  runCheck(pane)

proc clearBuffer*(pane: Pane) =
  pane.stopAutocompleteRefresh()
  pane.label.setText("")
  let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
  ed.setDocument(pane.emptyDoc.get())
  pane.sexprView.setDocument(nil)
  pane.imageLabel.clear()
  pane.imageScale = 1.0
  pane.imageUserZoomed = false
  pane.changed = false
  pane.statusLabel.setText(StatusDark)
  pane.stack.setCurrentIndex(cint(0))
  pane.buffer = nil
  pane.saveBtn.get().asWidget.setEnabled(true)
  pane.markActive = false
  pane.rectangleMarkActive = false
  pane.searchBar.get().hide()
  pane.matchPositions = @[]
  pane.diagLines[] = @[]
  pane.diagReady = false
  updateDiagIcons(pane)

proc openModuleDialog*(pane: Pane) {.raises: [].} =
  let fn = QFileDialog.getOpenFileName(pane.container)
  if fn.len > 0:
    pane.eventCb(PaneEvent(pane: pane, kind: peFileSelected, path: fn))

proc triggerNewModule*(pane: Pane) {.raises: [].} =
  pane.eventCb(PaneEvent(pane: pane, kind: peNewModule))

proc triggerOpenModule*(pane: Pane) {.raises: [].} =
  pane.eventCb(PaneEvent(pane: pane, kind: peOpenModule))

proc triggerOpenProject*(pane: Pane) {.raises: [].} =
  pane.eventCb(PaneEvent(pane: pane, kind: peOpenProject))

proc triggerFind*(pane: Pane) {.raises: [].} =
  if pane.buffer == nil or pane.buffer.kind != bkText:
    return
  pane.searchBar.get().show()
  pane.searchInput.get().asWidget.setFocus()
  let query = pane.searchInput.get().text()
  if query.len == 0:
    pane.matchPositions = @[]
    applySelections(pane)
    return

proc triggerGotoDefinition*(pane: Pane, client: NimSuggestClient) {.raises: [].} =
  if pane.buffer == nil or pane.buffer.kind != bkText or pane.buffer.path.len == 0:
    return
  let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
  let cur = ed.textCursor()
  let pos = cur.position()
  let doc = ed.document()
  let textBlock = doc.findBlock(pos)
  let lineNum = textBlock.blockNumber() + 1
  let colNum = cur.columnNumber()   # nimsuggest expects 0-based columns

  let filePath = pane.buffer.path
  let dirtyFilePath = pane.writeDirtyNimSuggestFile()
  if filePath.len == 0:
    return

  # Record current location before jumping so the back button can return here
  let fromLoc = JumpLocation(file: filePath, line: lineNum, col: colNum)

  client.queryDef(
    filePath,
    dirtyFilePath,
    lineNum,
    colNum,
    proc(def: Definition) {.raises: [].} =
      recordJump(pane.jumpHistory, pane.jumpFuture, fromLoc)
      pane.eventCb(PaneEvent(
        pane: pane,
        kind: peGotoDefinition,
        defFile: def.file,
        defLine: def.line,
        defCol: def.col
      )),
    proc(msg: string) {.raises: [].} =
      logError("pane: goto definition error: ", msg)
  )

proc triggerAutocomplete*(pane: Pane, client: NimSuggestClient,
                          trigger: AutocompleteTrigger = atCommand) {.raises: [].} =
  if pane.buffer == nil or pane.buffer.kind != bkText or pane.buffer.path.len == 0:
    return
  if trigger == atCommand and pane.autocompleteMenu.isOpen():
    pane.stopAutocompleteRefresh()
    pane.autocompleteMenu.accept()
    return
  let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
  let cur = ed.textCursor()
  let pos = cur.position()
  let doc = ed.document()
  let textBlock = doc.findBlock(pos)
  let lineNum = textBlock.blockNumber() + 1
  let colNum = cur.columnNumber()
  let prefix = identifierPrefixAt(doc.toPlainText(), pos.int)

  let filePath = pane.buffer.path
  let dirtyFilePath = pane.writeDirtyNimSuggestFile()
  if filePath.len == 0:
    return

  let paneRef = pane
  # Capture the trigger-time absolute character position so insertTextCb
  # can locate and replace the typed prefix precisely at accept time.
  let triggerPos = pos
  let edRef = ed
  client.querySug(
    filePath,
    dirtyFilePath,
    lineNum,
    colNum,
    proc(completions: seq[Completion]) {.raises: [].} =
      var items: seq[tuple[name, symkind, file: string]]
      items.setLen(completions.len)
      for i, completion in completions:
        items[i] = (completion.name, completion.symkind, completion.file)
      let rankedIdx = sortAutocompleteMatches(items, prefix, filePath)
      var rankedCompletions: seq[Completion]
      rankedCompletions.setLen(rankedIdx.len)
      for i, idx in rankedIdx:
        rankedCompletions[i] = completions[idx]
      if rankedCompletions.len == 0:
        if paneRef.autocompleteMenu.isOpen():
          paneRef.stopAutocompleteRefresh()
          paneRef.autocompleteMenu.dismiss()
        return

      proc insertTextCb(text: string) {.raises: [].} =
        let e = QPlainTextEdit(h: paneRef.editor.h, owned: false)
        let cur = e.textCursor()
        paneRef.clearMarkState()
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
        paneRef.stopAutocompleteRefresh()
        paneRef.autocompleteMenu = nil

      paneRef.autocompleteJustOpened = trigger == atCommand
      showCompletions(
        edRef,
        rankedCompletions,
        insertTextCb,
        closeCb,
        addr(paneRef.autocompleteMenu)
      ),
    proc(msg: string) {.raises: [].} =
      logError("pane: autocomplete error: ", msg)
  )

proc triggerJumpBack*(pane: Pane) {.raises: [].} =
  ## Pop the last jump location and navigate back to it.
  let loc = popJumpBack(pane.jumpHistory)
  if loc.isNone(): return
  pane.eventCb(PaneEvent(
    pane: pane,
    kind: peJumpBack,
    backFile: loc.get().file,
    backLine: loc.get().line,
    backCol:  loc.get().col
  ))

proc triggerJumpForward*(pane: Pane) {.raises: [].} =
  ## Pop the next jump location and navigate forward to it.
  let loc = popJumpForward(pane.jumpFuture)
  if loc.isNone(): return
  pane.eventCb(PaneEvent(
    pane: pane,
    kind: peJumpForward,
    fwdFile: loc.get().file,
    fwdLine: loc.get().line,
    fwdCol:  loc.get().col
  ))

proc closeSearch*(pane: Pane) {.raises: [].} =
  pane.searchBar.get().hide()
  pane.matchPositions = @[]
  applySelections(pane)
  if pane.isImageBuffer():
    pane.imageScroll.asWidget.setFocus()
  else:
    pane.editor.asWidget.setFocus()

proc zoomIn*(pane: Pane) {.raises: [].} =
  try:
    if pane.isImageBuffer():
      pane.imageUserZoomed = true
      pane.imageScale = min(pane.imageScale * ImageZoomStep, MaxImageZoom)
      pane.refreshImageView()
      return
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    var font = ed.document().defaultFont()
    font.setPointSize(font.pointSize() + cint 1)
    ed.asWidget.setFont(font)
    ed.document().setDefaultFont(font)
    ed.updateLineNumberAreaWidth()
  except CatchableError: discard

proc zoomOut*(pane: Pane) {.raises: [].} =
  try:
    if pane.isImageBuffer():
      pane.imageUserZoomed = true
      pane.imageScale = max(pane.imageScale / ImageZoomStep, MinImageZoom)
      pane.refreshImageView()
      return
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    var font = ed.document().defaultFont()
    let newSize = max(font.pointSize() - cint 1, MinFontSize)
    font.setPointSize(newSize)
    ed.asWidget.setFont(font)
    ed.document().setDefaultFont(font)
    ed.updateLineNumberAreaWidth()
  except CatchableError: discard

proc scrollUp*(pane: Pane) {.raises: [].} =
  try:
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    let vp = ed.viewport()
    let scroller = QScroller.scroller(QObject(h: vp.h, owned: false))
    let curY = scroller.finalPosition().y
    let newY = max(curY - ScrollStepPx, 0.0)
    scroller.scrollTo(QPointF.create(0.0, newY), ScrollAnimMs)
  except CatchableError: discard

proc setEditorWheelScrollSpeed*(pane: Pane, speed: int) {.raises: [].} =
  pane.editorWheelScrollSpeed = max(float64(speed), 1.0)

proc setEditorFont*(pane: Pane, family: string, size: int) {.raises: [].} =
  try:
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    var font = ed.document().defaultFont()
    if family.len > 0:
      font.setFamily(family)
    if size > 0:
      font.setPointSize(cint size)
    ed.asWidget.setFont(font)
    ed.document().setDefaultFont(font)
    if pane.emptyDoc.h != nil:
      QTextDocument(h: pane.emptyDoc.h, owned: false).setDefaultFont(font)
    if pane.sexprView != nil:
      pane.sexprView.setEditorFont(family, size)
    ed.updateLineNumberAreaWidth()
    ed.viewport().update()
  except CatchableError: discard

proc setLineNumbersVisible*(pane: Pane, visible: bool) {.raises: [].} =
  pane.showLineNumbers = visible
  try:
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    discard QObject(h: ed.h, owned: false).setProperty("nide.showLineNumbers", QVariant.create(visible))
    ed.updateLineNumberAreaWidth()
    ed.viewport().update()
  except CatchableError: discard

proc scrollDown*(pane: Pane) {.raises: [].} =
  try:
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    let vp = ed.viewport()
    let scroller = QScroller.scroller(QObject(h: vp.h, owned: false))
    let curY = scroller.finalPosition().y
    let maxY = float(ed.verticalScrollBar().maximum())
    let newY = min(curY + ScrollStepPx, maxY)
    scroller.scrollTo(QPointF.create(0.0, newY), ScrollAnimMs)
  except CatchableError: discard

proc setupSmoothScrolling*(pane: Pane) {.raises: [].} =
  try:
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    let vp = ed.viewport()
    let vpObj = QObject(h: vp.h, owned: false)
    let scroller = QScroller.scroller(vpObj)
    var props = scroller.scrollerProperties()
    # Disable overshoot bounce — unwanted in an editor
    props.setScrollMetric(
      cint(QScrollerPropertiesScrollMetricEnum.VerticalOvershootPolicy),
      QVariant.create(cint(QScrollerPropertiesOvershootPolicyEnum.OvershootAlwaysOff)))
    props.setScrollMetric(
      cint(QScrollerPropertiesScrollMetricEnum.HorizontalOvershootPolicy),
      QVariant.create(cint(QScrollerPropertiesOvershootPolicyEnum.OvershootAlwaysOff)))
    scroller.setScrollerProperties(props)
  except CatchableError: discard

proc setProjectOpen*(pane: Pane, open: bool) =
  pane.moduleBtnsRow.get().setVisible(open)
  pane.openProjectRow.get().setVisible(not open)

proc setRecentProjects*(pane: Pane, projects: seq[string]) {.raises: [].} =
  try:
    pane.recentProjectPaths = projects
    let tw = pane.recentProjectsList.get()
    tw.setRowCount(cint 0)
    for p in projects:
      let row = tw.rowCount()
      tw.insertRow(row)
      var nameItem = newWidget(QTableWidgetItem.create(p.lastPathPart))
      nameItem.setFlags(IF_SelectableEnabled)
      var pathItem = newWidget(QTableWidgetItem.create(p))
      pathItem.setFlags(IF_SelectableEnabled)
      tw.setItem(row, cint 0, nameItem)
      tw.setItem(row, cint 1, pathItem)
    let hasItems = projects.len > 0
    tw.asWidget.setVisible(hasItems)
    pane.recentProjectsLabel.get().asWidget.setVisible(hasItems)
  except CatchableError: discard

proc setRestoreLastSessionAvailable*(pane: Pane, available: bool) {.raises: [].} =
  try:
    let btn = pane.restoreSessionBtn.get()
    btn.asWidget.setVisible(true)
    btn.asWidget.setEnabled(available)
  except CatchableError: discard

proc currentCursorPosition*(pane: Pane): tuple[line, col: int] {.raises: [].} =
  if pane.buffer == nil or pane.buffer.kind != bkText:
    return (1, 0)
  try:
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    let cur = ed.textCursor()
    (cur.blockNumber() + 1, cur.columnNumber())
  except CatchableError:
    (1, 0)

proc currentScrollPosition*(pane: Pane): tuple[vertical, horizontal: int] {.raises: [].} =
  try:
    if pane.isImageBuffer():
      let area = QAbstractScrollArea(h: pane.imageScroll.h, owned: false)
      (area.verticalScrollBar().value().int, area.horizontalScrollBar().value().int)
    elif pane.buffer != nil and pane.buffer.kind == bkSExpr:
      let area = QAbstractScrollArea(h: pane.sexprPage.h, owned: false)
      (area.verticalScrollBar().value().int, area.horizontalScrollBar().value().int)
    else:
      let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
      (ed.verticalScrollBar().value().int, ed.horizontalScrollBar().value().int)
  except CatchableError:
    (0, 0)

proc restoreViewState*(pane: Pane, line, col, vertical, horizontal: int) {.raises: [].} =
  if pane.buffer == nil:
    return
  if pane.buffer.kind == bkSExpr:
    let area = QAbstractScrollArea(h: pane.sexprPage.h, owned: false)
    area.verticalScrollBar().setValue(cint min(max(vertical, 0), area.verticalScrollBar().maximum().int))
    area.horizontalScrollBar().setValue(cint min(max(horizontal, 0), area.horizontalScrollBar().maximum().int))
    pane.sexprView.focus()
    return
  if pane.buffer.kind != bkText:
    pane.fitImageToPane()
    return
  try:
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    let maxBlock = max(ed.blockCount().int, 1)
    let targetLine = min(max(line, 1), maxBlock)
    let doc = ed.document()
    let blk = doc.findBlockByNumber(cint(targetLine - 1))
    var cur = ed.textCursor()
    cur.setPosition(blk.position())
    let blockLen = max(blk.length().int - 1, 0)
    let targetCol = min(max(col, 0), blockLen)
    if targetCol > 0:
      discard cur.movePosition(cint(QTextCursorMoveOperationEnum.Right),
                               cint(QTextCursorMoveModeEnum.MoveAnchor),
                               cint(targetCol))
    ed.setTextCursor(cur)
    ed.verticalScrollBar().setValue(cint min(max(vertical, 0), ed.verticalScrollBar().maximum().int))
    ed.horizontalScrollBar().setValue(cint min(max(horizontal, 0), ed.horizontalScrollBar().maximum().int))
  except CatchableError:
    discard

proc focus*(pane: Pane) {.raises: [].} =
  if pane.isImageBuffer():
    QWidget(h: pane.imageScroll.h, owned: false).setFocus()
  elif pane.buffer != nil and pane.buffer.kind == bkSExpr:
    pane.sexprView.focus()
  elif pane.buffer != nil:
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
    QWidget(h: pane.imageScroll.h, owned: false).setStyleSheet(
      "QScrollArea { background: " & bg & "; border: none; }")
    QWidget(h: pane.imagePage.h, owned: false).setStyleSheet(
      "QWidget { background: " & bg & "; color: " & fg & "; }")
    if pane.sexprView != nil and pane.sexprView.widget.h != nil:
      QWidget(h: pane.sexprView.widget.h, owned: false).setStyleSheet(
        "QWidget { background: " & bg & "; color: " & fg & "; }")
      QWidget(h: pane.sexprPage.h, owned: false).setStyleSheet(
        "QScrollArea { background: " & bg & "; border: none; }")
    # Force gutter repaint
    ed.updateLineNumberAreaWidth()
    ed.viewport().update()
  except CatchableError: discard

proc jumpToLine*(pane: Pane, lineNum: int, col: int = 0) {.raises: [].} =
  if pane.buffer == nil or pane.buffer.kind != bkText: return
  let ed  = QPlainTextEdit(h: pane.editor.h, owned: false)
  let doc = ed.document()
  let blk = doc.findBlockByNumber(cint(lineNum - 1))
  var cur = ed.textCursor()
  cur.setPosition(blk.position())
  if col > 0:
    discard cur.movePosition(TC_Right, TM_MoveAnchor, cint(col - 1))
  ed.setTextCursor(cur)
  ed.ensureCursorVisible()

proc scrollToLine*(pane: Pane, line: int, col: int = 0) {.raises: [].} =
  if pane.buffer == nil or pane.buffer.kind != bkText: return
  let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
  let doc = ed.document()
  if line > 0 and line <= ed.blockCount():
    let targetBlock = doc.findBlockByNumber(cint(line - 1))
    var cur = ed.textCursor()
    cur.setPosition(targetBlock.position())
    if col > 0:
      discard cur.movePosition(TC_Right, TM_MoveAnchor, cint(col - 1))
    ed.setTextCursor(cur)
    ed.centerCursor()

proc triggerPrototype*(pane: Pane) {.raises: [].} =
  if pane.prototypeWindow.isPrototypeVisible():
    hidePrototype(addr pane.prototypeWindow)
    return
  
  pane.showPrototypeAtCursor()

proc showPrototypeAtCursor*(pane: Pane) {.raises: [].} =
  if pane.buffer == nil or pane.buffer.kind != bkText:
    return
  
  let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
  let cur = ed.textCursor()
  let pos = cur.position()
  let doc = ed.document()
  let text = doc.toPlainText()
  
  let word = getWordAtCursor(text, pos)
  if word.len == 0:
    QLabel(h: pane.statusLabel.h, owned: false).setText("Prototype: no word at cursor")
    return
  
  let result = querySymbol(word)
  if result.isSome():
    let entry = result.get()
    QLabel(h: pane.statusLabel.h, owned: false).setText("Prototype: " & entry.name & " [" & entry.module & "]")
    showPrototype(QWidget(h: pane.editor.h, owned: false),
                  entry.name, entry.module, entry.signature,
                  addr pane.prototypeWindow)
  else:
    QLabel(h: pane.statusLabel.h, owned: false).setText("Prototype: not found - " & word)

proc updatePrototypeAtCursor*(pane: Pane) {.raises: [].} =
  if not pane.prototypeWindow.isPrototypeVisible():
    return
  pane.showPrototypeAtCursor()

proc doCleanImports(pane: Pane) {.raises: [].} =
  try:
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    let source = ed.toPlainText()
    let unused = collectUnusedModules(pane.diagLines[], pane.buffer.path)
    let newSource = reorganizeImports(source, unused)
    if newSource == source: return
    let savedPos = ed.textCursor().position()
    let savedScroll = ed.verticalScrollBar().value()
    let cur = ed.textCursor()
    discard cur.movePosition(cint(QTextCursorMoveOperationEnum.Start),
                             cint(QTextCursorMoveModeEnum.MoveAnchor))
    discard cur.movePosition(cint(QTextCursorMoveOperationEnum.End),
                             cint(QTextCursorMoveModeEnum.KeepAnchor))
    cur.insertText(newSource)
    cur.setPosition(min(savedPos, cint(newSource.len)))
    ed.setTextCursor(cur)
    ed.verticalScrollBar().setValue(savedScroll)
  except:  # reorganizeImports uses Nim compiler lexer which raises Exception
    logError("pane: doCleanImports error: ", getCurrentExceptionMsg())

proc triggerCleanImports*(pane: Pane) {.raises: [].} =
  if pane.buffer == nil or pane.buffer.kind != bkText or pane.buffer.path.len == 0: return
  if not pane.buffer.path.endsWith(".nim"): return
  if pane.diagReady:
    doCleanImports(pane)
  else:
    if pane.checkProcessH[] != nil:
      try: QProcess(h: pane.checkProcessH[], owned: false).kill()
      except CatchableError: discard
      pane.checkProcessH[] = nil
    let filePath = pane.buffer.path
    let nimCommand =
      if pane.nimCommandProvider != nil: pane.nimCommandProvider()
      else: "nim"
    let nimBackend =
      if pane.nimBackendProvider != nil: pane.nimBackendProvider()
      else: "c"
    runNimCheck(pane.container.h, filePath, nimCommand, nimBackend, pane.checkProcessH,
      proc(lines: seq[LogLine]) {.raises: [].} =
        pane.diagLines[] = lines
        pane.diagReady = true
        applySelections(pane)
        doCleanImports(pane))
