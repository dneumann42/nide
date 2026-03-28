import logic
export logic
import autocomplete, buffers, commands, funcprototype, logparser, nimcheck, nimfinddef, nimimports, nimindex, nimsuggest, syntaxtheme, widgetref, widgets
import seaqt/[qabstractbutton, qabstractitemview, qbrush, qcheckbox, qcolor, qcursor, qevent, qfiledialog, qfont, qfontmetrics, qhboxlayout, qheaderview, qicon, qkeyevent, qkeysequence, qlabel, qlayout, qlineargradient, qlineedit, qlistwidget, qlistwidgetitem, qmessagebox, qmouseevent, qpaintdevice, qpainter, qpaintevent, qpalette, qpixmap, qplaintextdocumentlayout, qplaintextedit, qpoint, qprocess, qpushbutton, qrect, qregularexpression, qscrollarea, qscrollbar, qscroller, qscrollerproperties, qshortcut, qsize, qstackedwidget, qsvgrenderer, qtableview, qtablewidget, qtablewidgetitem, qtextcursor, qtextdocument, qtextedit, qtextformat, qtextobject, qtimer, qvariant, qvboxlayout, qwheelevent, qwidget]
import std/[options, os, strutils]

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
    peNewModule, peOpenModule, peOpenProject, peNewProject, peOpenRecentProject,
    peGotoDefinition, peJumpBack, peJumpForward,
    peSave, peFindFile, peSwitchBuffer, peDeleteOtherWindows

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
    emptyDoc: WidgetRef[QTextDocument]
    changed*: bool
    buffer*: Buffer
    eventCb: proc(ev: PaneEvent) {.raises: [].}
    moduleBtnsRow: WidgetRef[QWidget]
    openProjectRow: WidgetRef[QWidget]
    recentProjectsList: WidgetRef[QTableWidget]
    recentProjectsLabel: WidgetRef[QLabel]
    recentProjectPaths: seq[string]
    searchBar:     WidgetRef[QWidget]
    searchInput:   WidgetRef[QLineEdit]
    caseCheck:     WidgetRef[QCheckBox]
    regexCheck:    WidgetRef[QCheckBox]
    matchPositions: seq[(cint, cint)]
    bracketMatchPositions: seq[(cint, cint)]
    jumpHistory*:  seq[JumpLocation]
    jumpFuture*:   seq[JumpLocation]
    nimSuggest*:   NimSuggestClient
    matchIndex:     int
    checkProcessH:  ref pointer
    diagLines:      ref seq[LogLine]
    diagPopupH:     pointer  # viewport-child QWidget popup, nil until first hover
    diagLabelH:     pointer  # QLabel inside diagPopup
    diagShownLine:  int      # line of the diagnostic currently in the popup
    diagShownCol:   int      # col of the diagnostic currently in the popup
    diagReady:      bool     # true once nim check has returned at least once for this buffer
    diagHideTimerH: pointer  # single-shot QTimer that hides the popup after a delay
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

proc scrollUp*(pane: Pane) {.raises: [].}
proc scrollDown*(pane: Pane) {.raises: [].}
proc applyEditorTheme*(pane: Pane) {.raises: [].}
proc closeSearch*(pane: Pane) {.raises: [].}
proc triggerJumpBack*(pane: Pane) {.raises: [].}
proc triggerJumpForward*(pane: Pane) {.raises: [].}
proc triggerGotoDefinition*(pane: Pane, client: NimSuggestClient) {.raises: [].}
proc triggerAutocomplete*(pane: Pane, client: NimSuggestClient) {.raises: [].}
proc triggerPrototype*(pane: Pane) {.raises: [].}
proc triggerCleanImports*(pane: Pane) {.raises: [].}
proc showPrototypeAtCursor*(pane: Pane) {.raises: [].}
proc updatePrototypeAtCursor*(pane: Pane) {.raises: [].}

const StatusDark = ""
const StatusLight = "★"

const VsplitSvg = staticRead("icons/vsplit.svg")
const HsplitSvg = staticRead("icons/hsplit.svg")
const SaveSvg = staticRead("icons/save.svg")


proc widget*(pane: Pane): QWidget =
  QWidget(h: pane.container.h, owned: false)

proc hideDiagPopup(pane: Pane) {.raises: [].} =
  if pane.diagHideTimerH != nil:
    try: QTimer(h: pane.diagHideTimerH, owned: false).stop()
    except: discard
  if pane.diagPopupH != nil:
    try: QWidget(h: pane.diagPopupH, owned: false).hide()
    except: discard
  pane.diagShownLine = 0
  pane.diagShownCol  = 0

proc scheduleDiagHide(pane: Pane) {.raises: [].} =
  if pane.diagHideTimerH == nil: return
  try:
    let t = QTimer(h: pane.diagHideTimerH, owned: false)
    t.stop()
    t.start()
  except: discard

proc updateDiagIcons*(pane: Pane) {.raises: [].} =
  if pane.diagLines == nil or pane.buffer == nil: return
  let currentFile = pane.buffer.path
  let (hintCount, warnCount, errCount) = countDiags(pane.diagLines[], currentFile)
  try:
    let hintW = QWidget(h: pane.hintBtn.h, owned: false)
    let warnW = QWidget(h: pane.warnBtn.h, owned: false)
    let errW = QWidget(h: pane.errBtn.h, owned: false)
    if hintCount > 0:
      QPushButton(h: pane.hintBtn.h, owned: false).setText("◆" & $hintCount)
      QPushButton(h: pane.hintBtn.h, owned: false).setStyleSheet("QPushButton { color: #00cccc; background: transparent; border: none; font-size: 11px; } QPushButton:hover { color: #00eeee; }")
      hintW.show()
    else:
      hintW.hide()
    if warnCount > 0:
      QPushButton(h: pane.warnBtn.h, owned: false).setText("⚠" & $warnCount)
      QPushButton(h: pane.warnBtn.h, owned: false).setStyleSheet("QPushButton { color: #ffaa00; background: transparent; border: none; font-size: 11px; } QPushButton:hover { color: #ffcc00; }")
      warnW.show()
    else:
      warnW.hide()
    if errCount > 0:
      QPushButton(h: pane.errBtn.h, owned: false).setText("✗" & $errCount)
      QPushButton(h: pane.errBtn.h, owned: false).setStyleSheet("QPushButton { color: #ff5555; background: transparent; border: none; font-size: 11px; } QPushButton:hover { color: #ff7777; }")
      errW.show()
    else:
      errW.hide()
  except: discard

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
      var popup = QWidget.create(viewport)
      popup.owned = false
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

      var label = QLabel.create()
      label.owned = false
      QLabel(h: label.h, owned: false).setWordWrap(true)
      QLabel(h: label.h, owned: false).setTextFormat(cint 1)  # Qt::RichText
      QLabel(h: label.h, owned: false).setTextInteractionFlags(cint 3)  # TextSelectableByMouse | TextSelectableByKeyboard
      pane.diagLabelH = label.h

      var layout = QVBoxLayout.create()
      layout.owned = false
      layout.setContentsMargins(cint 0, cint 0, cint 0, cint 0)
      layout.setSpacing(cint 0)
      layout.addWidget(QWidget(h: pane.diagLabelH, owned: false))
      QWidget(h: pane.diagPopupH, owned: false).setLayout(
        QLayout(h: layout.h, owned: false))

    QLabel(h: pane.diagLabelH, owned: false).setText(html)

    let pw = QWidget(h: pane.diagPopupH, owned: false)
    pw.adjustSize()
    let popupW = pw.width()
    let popupH = pw.height()

    let vpW = viewport.width()
    let vpH = viewport.height()
    var px = mousePos.x()
    var py = mousePos.y() + cint 18
    if px + popupW > vpW: px = max(cint 0, vpW - popupW)
    if py + popupH > vpH: py = max(cint 0, mousePos.y() - popupH)

    pw.setGeometry(px, py, popupW, popupH)
    pw.raiseX()
    pw.show()
    pane.diagShownLine = diags[0].line
    pane.diagShownCol  = diags[0].col
  except: discard


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
    ed.setTextCursor(savedCursor)
    ed.verticalScrollBar().setValue(savedScroll)
  except: discard

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
    if pane.buffer.externallyModified:
      let parent = QWidget(h: pane.container.h, owned: false)
      # StandardButton values: Save=2048, Discard=8388608
      let clicked = QMessageBox.warning(
        parent,
        "File Modified Externally",
        "This file was changed outside the editor. Overwrite it with your changes, or discard them and reload from disk?",
        cint(2048 or 8388608),
        cint(2048))
      if clicked == cint(8388608):
        try:
          let content = readFile(pane.buffer.path)
          pane.buffer.document().setPlainText(content)
          pane.buffer.document().setModified(false)
          pane.buffer.externallyModified = false
        except:
          discard
        return
      pane.buffer.externallyModified = false
    try:
      let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
      let savedScroll = ed.verticalScrollBar().value()
      writeFile(pane.buffer.path, ed.toPlainText())
      runCheck(pane)
      ed.document().setModified(false)
      ed.verticalScrollBar().setValue(savedScroll)
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

proc hideDiagPopover(pane: Pane) {.raises: [].} =
  if pane.diagPopoverH != nil:
    try: QWidget(h: pane.diagPopoverH, owned: false).hide()
    except: discard

proc showDiagPopover(pane: Pane, filterLevel: LogLevel) {.raises: [].} =
  if pane.diagLines == nil or pane.diagLines[].len == 0: return
  try:
    if pane.diagPopoverH != nil:
      try:
        QWidget(h: pane.diagPopoverH, owned: false).delete()
      except: discard
      pane.diagPopoverH = nil
      pane.diagPopoverListH = nil
      pane.diagPopoverLayoutH = nil

    var popover = QWidget.create()
    popover.owned = false
    popover.setWindowFlags(cint(0x00000008 or 0x00000001))  # Qt::Popup | Qt::FramelessWindowHint
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

    var scroll = QScrollArea.create(popover)
    scroll.owned = false
    scroll.setWidgetResizable(true)
    scroll.setHorizontalScrollBarPolicy(cint(0))  # Qt::ScrollBarAlwaysOff

    var listW = QWidget.create(scroll)
    listW.owned = false
    var listLayout = QVBoxLayout.create()
    listLayout.owned = false
    listLayout.setContentsMargins(cint 4, cint 4, cint 4, cint 4)
    listLayout.setSpacing(cint 2)
    listW.setLayout(QLayout(h: listLayout.h, owned: false))
    pane.diagPopoverListH = listW.h
    pane.diagPopoverLayoutH = listLayout.h

    QScrollArea(h: scroll.h, owned: false).setWidget(QWidget(h: listW.h, owned: false))
    var popoverLayout = QVBoxLayout.create()
    popoverLayout.owned = false
    popoverLayout.setContentsMargins(cint 0, cint 0, cint 0, cint 0)
    popoverLayout.setSpacing(cint 0)
    popoverLayout.addWidget(QWidget(h: scroll.h, owned: false))
    popover.setLayout(QLayout(h: popoverLayout.h, owned: false))

    for ll in pane.diagLines[]:
      if ll.file != pane.buffer.path: continue
      if ll.level != filterLevel: continue
      let (label, color) = case ll.level
        of llError:   ("Error",   "#ff5555")
        of llWarning: ("Warning", "#ffaa00")
        of llHint:    ("Hint",    "#00cccc")
        else: continue
      let escaped = ll.raw.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
      let text = label & ": " & escaped & " (line " & $ll.line & ")"
      let lineNum = ll.line

      var itemBtn = QPushButton.create(text)
      itemBtn.owned = false
      itemBtn.setFlat(true)
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

      listLayout.addWidget(QWidget(h: itemBtn.h, owned: false))

    if listLayout.count() == 0:
      return

    let popW = QWidget(h: pane.diagPopoverH, owned: false)
    popW.adjustSize()
    let pw = popW.width()
    let ph = popW.height()

    var btnPos: QPoint
    case filterLevel
    of llHint: btnPos = QPushButton(h: pane.hintBtn.h, owned: false).mapToGlobal(QPoint.create(cint 0, cint 0))
    of llWarning: btnPos = QPushButton(h: pane.warnBtn.h, owned: false).mapToGlobal(QPoint.create(cint 0, cint 0))
    of llError: btnPos = QPushButton(h: pane.errBtn.h, owned: false).mapToGlobal(QPoint.create(cint 0, cint 0))
    else: btnPos = QPoint.create(cint 0, cint 0)

    var yPos = btnPos.y() + 24

    popW.setGeometry(btnPos.x(), yPos, pw, min(ph, cint 400))
    popW.raiseX()
    popW.show()
  except: discard

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

proc newPane*(
  onEvent: proc(ev: PaneEvent) {.raises: [].}
): Pane =
  result = Pane()
  new(result.checkProcessH); result.checkProcessH[] = nil
  new(result.diagLines);     result.diagLines[]     = @[]
  let pane = result

  # --- Open Project row (shown when no project is open) ---
  var newProjectBtn = QPushButton.create("New Project")
  newProjectBtn.owned = false
  var openProjectBtn = QPushButton.create("Open Project")
  openProjectBtn.owned = false

  var recentLabel = QLabel.create("Recent Projects")
  recentLabel.owned = false
  QWidget(h: recentLabel.h, owned: false).hide()

  var recentTable = QTableWidget.create(cint 0, cint 2)
  recentTable.owned = false
  let recentTableH = recentTable.h
  QWidget(h: recentTableH, owned: false).hide()
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
    except: discard

  # Card: outline border only, palette-inherited background
  var cardWidget = QWidget.create()
  cardWidget.owned = false
  cardWidget.setObjectName("welcomeCard")
  cardWidget.setStyleSheet(
    "QWidget#welcomeCard { border: 1px solid #333333; border-radius: 4px; }")
  QWidget(h: cardWidget.h, owned: false).setMinimumWidth(cint 480)

  var cardLayout = QVBoxLayout.create(); cardLayout.owned = false
  QLayout(h: cardLayout.h, owned: false).setContentsMargins(cint 20, cint 20, cint 20, cint 20)
  QLayout(h: cardLayout.h, owned: false).setSpacing(cint 10)

  var btnRow = QHBoxLayout.create(); btnRow.owned = false
  btnRow.addWidget(QWidget(h: newProjectBtn.h, owned: false))
  btnRow.addWidget(QWidget(h: openProjectBtn.h, owned: false))
  btnRow.addStretch()

  cardLayout.addLayout(QLayout(h: btnRow.h, owned: false))
  cardLayout.addWidget(QWidget(h: recentLabel.h, owned: false))
  cardLayout.addWidget(QWidget(h: recentTableH, owned: false))
  cardWidget.setLayout(QLayout(h: cardLayout.h, owned: false))

  # Outer centering layout
  var openProjectLayout = QVBoxLayout.create(); openProjectLayout.owned = false
  QLayout(h: openProjectLayout.h, owned: false).setContentsMargins(cint 40, cint 40, cint 40, cint 40)
  openProjectLayout.addStretch()
  openProjectLayout.addWidget(QWidget(h: cardWidget.h, owned: false))
  openProjectLayout.addStretch()

  var openProjectRow = QWidget.create()
  openProjectRow.owned = false
  openProjectRow.setLayout(QLayout(h: openProjectLayout.h, owned: false))

  pane.recentProjectsList = capture(recentTable)
  pane.recentProjectsLabel = capture(recentLabel)

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
    QPlainTextEditevent(self, e)
  editorVtbl.mouseMoveEvent = proc(self: QPlainTextEdit, e: QMouseEvent) {.raises: [], gcsafe.} =
    let cur = self.cursorForPosition(e.pos())
    let diags = diagAtPos(pane, cur.position())
    if diags.len > 0:
      # Cancel any pending hide and show/keep the popup.
      if pane.diagHideTimerH != nil:
        try: QTimer(h: pane.diagHideTimerH, owned: false).stop()
        except: discard
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

    if pane.prototypeWindow.isPrototypeVisible():
      if key == cint(0x01000000):  # Escape
        {.cast(gcsafe).}: hidePrototype(addr pane.prototypeWindow)
        QPlainTextEditkeyPressEvent(self, e)
        return
      elif key == cint(0x01000004) or key == cint(0x01000005):  # Return
        {.cast(gcsafe).}: hidePrototype(addr pane.prototypeWindow)
        QPlainTextEditkeyPressEvent(self, e)
        return
      elif key == cint(0x01000021):  # Ctrl (shouldn't happen but just in case)
        QPlainTextEditkeyPressEvent(self, e)
        return
      else:
        QPlainTextEditkeyPressEvent(self, e)
        {.cast(gcsafe).}:
          pane.updatePrototypeAtCursor()
        return
    
    if pane.autocompleteMenu.isOpen():
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
          {.cast(gcsafe).}: pane.autocompleteMenu.dismiss()
    elif key == cint(0x01000001):  # Qt::Key_Tab → insert 2 spaces
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

    # Command dispatcher — ignore modifier-only keypresses
    let isModifierOnly = key >= cint(0x01000020) and key <= cint(0x01000023)
    if not isModifierOnly:
      let relevantMods = mods and (ctrlMod or altMod or shiftMod)
      let c: KeyCombo = (key, relevantMods)
      {.cast(gcsafe).}:
        if pane.dispatcher != nil and pane.dispatcher.dispatch(c):
          return

    QPlainTextEditkeyPressEvent(self, e)
  editorVtbl.mousePressEvent = proc(self: QPlainTextEdit, e: QMouseEvent) {.raises: [], gcsafe.} =
    # Any mouse click dismisses the autocomplete menu
    if pane.autocompleteMenu.isOpen():
      {.cast(gcsafe).}: pane.autocompleteMenu.dismiss()
    let btn = e.button()
    if btn == cint(8):   # Qt::BackButton / XButton1
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
    elif btn == cint(16):  # Qt::ForwardButton / XButton2
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
    elif btn == cint(1) and (e.modifiers() and cint(67108864)) != 0:  # LeftButton + Ctrl
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
        dy = float64(-e.angleDelta().y) / 120.0 * 20.0
      let newY = min(max(curY + dy, 0.0), maxY)
      scroller.scrollTo(QPointF.create(0.0, newY), cint(80))
    except: discard

  var editor = QPlainTextEdit.create(vtbl = editorVtbl)
  editor.owned = false
  editor.setFrameStyle(0)
  editor.viewport().setMouseTracking(true)

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

  editor.onCursorPositionChanged do() {.raises: [].}:
    updateBracketMatch(pane)

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

  var hintBtn = QPushButton.create("")
  hintBtn.owned = false
  hintBtn.setFlat(true)
  QWidget(h: hintBtn.h, owned: false).setSizePolicy(cint 0, cint 0)
  QWidget(h: hintBtn.h, owned: false).setMinimumWidth(cint 24)
  QWidget(h: hintBtn.h, owned: false).setFixedHeight(cint 18)

  var warnBtn = QPushButton.create("")
  warnBtn.owned = false
  warnBtn.setFlat(true)
  QWidget(h: warnBtn.h, owned: false).setSizePolicy(cint 0, cint 0)
  QWidget(h: warnBtn.h, owned: false).setMinimumWidth(cint 24)
  QWidget(h: warnBtn.h, owned: false).setFixedHeight(cint 18)

  var errBtn = QPushButton.create("")
  errBtn.owned = false
  errBtn.setFlat(true)
  QWidget(h: errBtn.h, owned: false).setSizePolicy(cint 0, cint 0)
  QWidget(h: errBtn.h, owned: false).setMinimumWidth(cint 24)
  QWidget(h: errBtn.h, owned: false).setFixedHeight(cint 18)

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
  headerLayout.addWidget(QWidget(h: hintBtn.h, owned: false), cint(0), cint(0))
  headerLayout.addWidget(QWidget(h: warnBtn.h, owned: false), cint(0), cint(0))
  headerLayout.addWidget(QWidget(h: errBtn.h, owned: false), cint(0), cint(0))
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
  var inputVtbl = new QLineEditVTable
  inputVtbl.keyPressEvent = proc(self: QLineEdit, e: QKeyEvent) {.raises: [], gcsafe.} =
    let key  = e.key()
    let mods = e.modifiers()
    if key == cint(0x01000000):  # Escape → close search
      {.cast(gcsafe).}:
        pane.searchBar.get().hide()
        pane.matchPositions = @[]
        applySelections(pane)
        QWidget(h: pane.editor.h, owned: false).setFocus()
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
  var searchInput = QLineEdit.create(vtbl = inputVtbl)
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
  # Timer that hides the diagnostic popup after a short delay, giving the user
  # time to move the mouse into the popup. Restarted if underMouse() is true.
  var diagHideTimer = QTimer.create(QObject(h: result.container.h, owned: false))
  diagHideTimer.owned = false
  QTimer(h: diagHideTimer.h, owned: false).setSingleShot(true)
  QTimer(h: diagHideTimer.h, owned: false).setInterval(cint 500)
  result.diagHideTimerH = diagHideTimer.h
  QTimer(h: diagHideTimer.h, owned: false).onTimeout do() {.raises: [].}:
    if pane.diagPopupH != nil and
       QWidget(h: pane.diagPopupH, owned: false).isVisible() and
       QWidget(h: pane.diagPopupH, owned: false).underMouse():
      QTimer(h: pane.diagHideTimerH, owned: false).start()
    else:
      hideDiagPopup(pane)
  result.label = label
  result.statusLabel = statusLabel
  result.stack = stack
  result.openModuleWidget = openModuleWidget
  result.editor = editor
  var emptyDoc = QTextDocument.create()
  emptyDoc.owned = false
  var emptyLayout = QPlainTextDocumentLayout.create(emptyDoc)
  emptyLayout.owned = false
  emptyDoc.setDocumentLayout(QAbstractTextDocumentLayout(h: emptyLayout.h, owned: false))
  emptyDoc.setDefaultFont(editorFont)
  result.emptyDoc        = capture(emptyDoc)
  result.eventCb         = onEvent
  result.moduleBtnsRow   = capture(moduleBtnsRow)
  result.openProjectRow  = capture(openProjectRow)
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
  var diagSc = QShortcut.create(QKeySequence.create("Ctrl+Shift+D"),
                                QObject(h: pane.container.h, owned: false))
  diagSc.owned = false
  diagSc.setContext(cint 1)  # WidgetWithChildrenShortcut
  diagSc.onActivated do() {.raises: [].}:
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    let cur = ed.textCursor()
    let diags = diagAtPos(pane, cur.position())
    if diags.len > 0:
      let rect = ed.cursorRect()
      showDiagPopup(pane, ed, diags,
        QPoint.create(rect.left(), rect.top() + rect.height()))

proc setHeaderFocus*(pane: Pane, focused: bool, isDark: bool) =
  let hbw = QWidget(h: pane.headerBar.h, owned: false)
  let iconColor = if focused: "#000000" else: "#ffffff"
  const headerIconSize = 10
  if focused:
    let (rightColor, _) = headerGradientColors(isDark)
    hbw.setStyleSheet("#headerBar { background: qlineargradient(x1:0, y1:0, x2:1, y2:0, stop:0 #000000, stop:0.95 " & rightColor & "); }")
  else:
    hbw.setStyleSheet("#headerBar { background: #000000; }")
  QAbstractButton(h: pane.saveBtn.get().h, owned: false).setIcon(svgIcon(SaveSvg, cint headerIconSize, iconColor))
  QAbstractButton(h: pane.vSplitBtn.get().h, owned: false).setIcon(svgIcon(VsplitSvg, cint headerIconSize, iconColor))
  QAbstractButton(h: pane.hSplitBtn.get().h, owned: false).setIcon(svgIcon(HsplitSvg, cint headerIconSize, iconColor))
  QWidget(h: pane.closeBtn.get().h, owned: false).setStyleSheet("QPushButton { color: " & iconColor & "; }")

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
  pane.diagReady = false
  applySelections(pane)
  updateDiagIcons(pane)
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
  pane.diagReady = false
  updateDiagIcons(pane)

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
  let query = pane.searchInput.get().text()
  if query.len == 0:
    pane.matchPositions = @[]
    applySelections(pane)
    return

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
      recordJump(pane.jumpHistory, pane.jumpFuture, fromLoc)
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
  if paneRef.autocompleteMenu.isOpen():
    return
  if client.pending.len > 0:
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

proc scrollUp*(pane: Pane) {.raises: [].} =
  try:
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    let vp = ed.viewport()
    let scroller = QScroller.scroller(QObject(h: vp.h, owned: false))
    let curY = scroller.finalPosition().y
    let newY = max(curY - 10.0, 0.0)
    scroller.scrollTo(QPointF.create(0.0, newY), cint(80))
  except: discard

proc scrollDown*(pane: Pane) {.raises: [].} =
  try:
    let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
    let vp = ed.viewport()
    let scroller = QScroller.scroller(QObject(h: vp.h, owned: false))
    let curY = scroller.finalPosition().y
    let maxY = float(ed.verticalScrollBar().maximum())
    let newY = min(curY + 10.0, maxY)
    scroller.scrollTo(QPointF.create(0.0, newY), cint(80))
  except: discard

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
  except: discard

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
      var nameItem = QTableWidgetItem.create(p.lastPathPart)
      nameItem.owned = false
      nameItem.setFlags(cint 0x21)  # ItemIsSelectable | ItemIsEnabled
      var pathItem = QTableWidgetItem.create(p)
      pathItem.owned = false
      pathItem.setFlags(cint 0x21)
      tw.setItem(row, cint 0, nameItem)
      tw.setItem(row, cint 1, pathItem)
    let hasItems = projects.len > 0
    QWidget(h: tw.h, owned: false).setVisible(hasItems)
    QWidget(h: pane.recentProjectsLabel.get().h, owned: false).setVisible(hasItems)
  except: discard

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

proc triggerPrototype*(pane: Pane) {.raises: [].} =
  if pane.prototypeWindow.isPrototypeVisible():
    hidePrototype(addr pane.prototypeWindow)
    return
  
  pane.showPrototypeAtCursor()

proc showPrototypeAtCursor*(pane: Pane) {.raises: [].} =
  if pane.buffer == nil:
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
  except: discard

proc triggerCleanImports*(pane: Pane) {.raises: [].} =
  if pane.buffer == nil or pane.buffer.path.len == 0: return
  if not pane.buffer.path.endsWith(".nim"): return
  if pane.diagReady:
    doCleanImports(pane)
  else:
    if pane.checkProcessH[] != nil:
      try: QProcess(h: pane.checkProcessH[], owned: false).kill()
      except: discard
      pane.checkProcessH[] = nil
    let filePath = pane.buffer.path
    runNimCheck(pane.container.h, filePath, pane.checkProcessH,
      proc(lines: seq[LogLine]) {.raises: [].} =
        pane.diagLines[] = lines
        pane.diagReady = true
        applySelections(pane)
        doCleanImports(pane))

