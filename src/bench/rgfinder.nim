import std/[strutils, os, osproc]
import seaqt/[qwidget, qvboxlayout, qlayout, qdialog, qlineedit, qlistwidget,
              qlistwidgetitem, qshortcut, qkeysequence, qobject, qtimer,
              qsplitter, qplaintextedit, qfont, qtextdocument, qtextcursor, qtextobject,
              qfontmetrics, qpaintdevice, qpainter, qcolor, qpaintevent, qrect,
              qresizeevent, qpoint]
import bench/[highlight, syntaxtheme]

proc QWidget_virtbase(src: pointer, outQObject: ptr pointer, outPaintDevice: ptr pointer) {.importc: "QWidget_virtbase".}

proc widgetToPaintDevice(w: QWidget): QPaintDevice =
  var outQObject: pointer
  var outPaintDevice: pointer
  QWidget_virtbase(w.h, addr outQObject, addr outPaintDevice)
  QPaintDevice(h: outPaintDevice, owned: false)

proc lineNumberAreaWidth(editor: QPlainTextEdit): cint =
  let digits = max(1, ($editor.blockCount()).len)
  let fm = QFontMetrics.create(editor.document().defaultFont())
  cint(fm.horizontalAdvance("0") * digits + 12)

proc lineNumberAreaPaintEvent(editor: QPlainTextEdit, event: QPaintEvent, gutter: QWidget) {.raises: [].} =
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

proc dbg(msg: string) {.raises: [].} =
  try: stderr.write(msg & "\n") except: discard

proc toStr(oa: openArray[char]): string {.raises: [].} =
  result = newString(oa.len)
  if oa.len > 0:
    copyMem(addr result[0], unsafeAddr oa[0], oa.len)

type RgMatch = object
  file: string
  lineNum: int
  match: string

proc showRipgrepFinder*(parent: QWidget,
    onSelected: proc(file: string, lineNum: int) {.raises: [].}) {.raises: [].} =
  try:
    let cwd = try: getCurrentDir() except OSError: "."

    var dialog = QDialog.create(parent)
    dialog.owned = false
    let dialogH = dialog.h
    QWidget(h: dialogH, owned: false).setWindowTitle("Find in Files")
    QWidget(h: dialogH, owned: false).resize(cint 900, cint 500)

    var searchBox = QLineEdit.create()
    searchBox.owned = false

    var listWidget = QListWidget.create()
    listWidget.owned = false
    let listH = listWidget.h

    var leftLayout = QVBoxLayout.create()
    leftLayout.owned = false
    leftLayout.addWidget(QWidget(h: searchBox.h, owned: false))
    leftLayout.addWidget(QWidget(h: listWidget.h, owned: false))

    var leftPanel = QWidget.create()
    leftPanel.owned = false
    leftPanel.setLayout(QLayout(h: leftLayout.h, owned: false))

    var previewGutterH: pointer = nil
    var previewVtbl = new QPlainTextEditVTable
    previewVtbl.resizeEvent = proc(self: QPlainTextEdit, e: QResizeEvent) {.raises: [], gcsafe.} =
      QPlainTextEditresizeEvent(self, e)
      if previewGutterH == nil: return
      let cr = QWidget(h: self.h, owned: false).contentsRect()
      QWidget(h: previewGutterH, owned: false).setGeometry(
        cr.left(), cr.top(), self.lineNumberAreaWidth(), cr.height())

    var preview = QPlainTextEdit.create(vtbl = previewVtbl)
    preview.owned = false
    preview.setReadOnly(true)
    var previewFont = QFont.create("Monospace")
    previewFont.setStyleHint(cint(QFontStyleHintEnum.TypeWriter))
    QWidget(h: preview.h, owned: false).setFont(previewFont)
    let previewHl = NimHighlighter()
    previewHl.attach(preview.document())
    let previewH = preview.h

    var previewGutterVtbl = new QWidgetVTable
    previewGutterVtbl.paintEvent = proc(self: QWidget, event: QPaintEvent) {.raises: [], gcsafe.} =
      lineNumberAreaPaintEvent(QPlainTextEdit(h: previewH, owned: false), event, self)
    var previewGutter = QWidget.create(QWidget(h: previewH, owned: false), cint(0), vtbl = previewGutterVtbl)
    previewGutter.owned = false
    previewGutterH = previewGutter.h

    QPlainTextEdit(h: previewH, owned: false).setViewportMargins(
      QPlainTextEdit(h: previewH, owned: false).lineNumberAreaWidth(), 0, 0, 0)

    preview.onBlockCountChanged do(count: cint) {.raises: [].}:
      QPlainTextEdit(h: previewH, owned: false).setViewportMargins(
        QPlainTextEdit(h: previewH, owned: false).lineNumberAreaWidth(), 0, 0, 0)

    preview.onUpdateRequest do(rect: QRect, dy: cint) {.raises: [].}:
      let g = QWidget(h: previewGutterH, owned: false)
      if dy != 0:
        g.scroll(cint 0, dy)
      else:
        g.update(0, rect.y(), g.width(), rect.height())
      let ed = QPlainTextEdit(h: previewH, owned: false)
      if rect.contains(ed.viewport().rect()):
        ed.setViewportMargins(ed.lineNumberAreaWidth(), 0, 0, 0)

    var splitter = QSplitter.create(cint 1)
    splitter.owned = false
    splitter.addWidget(QWidget(h: leftPanel.h, owned: false))
    splitter.addWidget(QWidget(h: preview.h, owned: false))
    splitter.setStretchFactor(cint 0, cint 1)
    splitter.setStretchFactor(cint 1, cint 2)

    var outerLayout = QVBoxLayout.create()
    outerLayout.owned = false
    outerLayout.addWidget(QWidget(h: splitter.h, owned: false))
    QWidget(h: dialogH, owned: false).setLayout(QLayout(h: outerLayout.h, owned: false))

    var currentMatches: seq[RgMatch]
    var pendingQuery = ""

    var timer = QTimer.create(QObject(h: dialogH, owned: false))
    timer.owned = false
    let timerH = timer.h
    QTimer(h: timerH, owned: false).setSingleShot(true)
    QTimer(h: timerH, owned: false).setInterval(cint 300)

    proc populate(query: string) {.raises: [].} =
      let lw = QListWidget(h: listH, owned: false)
      lw.clear()
      currentMatches = @[]
      if query.strip().len == 0: return
      try:
        # Find real ripgrep: try common locations before relying on PATH
        # (/usr/sbin/rg may be a non-ripgrep system utility)
        var rgExe = ""
        for candidate in ["/usr/bin/rg",
                          getEnv("HOME") & "/.cargo/bin/rg",
                          getEnv("HOME") & "/.local/bin/rg",
                          "/usr/local/bin/rg"]:
          if fileExists(candidate):
            let (ver, code) = execCmdEx(candidate & " --version 2>&1")
            if code == 0 and "ripgrep" in ver:
              rgExe = candidate
              break
        if rgExe.len == 0:
          rgExe = findExe("rg")
        dbg("rgfinder: rg=" & (if rgExe.len == 0: "NOT FOUND" else: rgExe))
        if rgExe.len == 0: return
        let (shellPwd, _) = execCmdEx("pwd 2>&1")
        dbg("rgfinder: shellpwd=" & shellPwd.strip())
        let cmd = rgExe & " -n --no-heading --color never --no-ignore -- " &
                  quoteShell(query) & " " & quoteShell(cwd) & " 2>/dev/null | head -n 200"
        dbg("rgfinder: cmd=" & cmd)
        let (output, exitCode) = execCmdEx(cmd)
        dbg("rgfinder: exit=" & $exitCode & " outlen=" & $output.len)
        if output.len > 0:
          dbg("rgfinder: first120: " & output[0 .. min(119, output.len-1)])
        for lineStr in output.splitLines():
          if lineStr.len == 0: continue
          if currentMatches.len >= 200: break
          try:
            let parts = lineStr.split(':', 2)
            if parts.len == 3:
              currentMatches.add(RgMatch(
                file:    (try: relativePath(parts[0], cwd) except: parts[0]),
                lineNum: parseInt(parts[1]),
                match:   parts[2]
              ))
          except: discard
        dbg("rgfinder: matches=" & $currentMatches.len)
        for m in currentMatches:
          lw.addItem(m.file & ":" & $m.lineNum & "  " & m.match.strip())
        if lw.count() > 0:
          lw.setCurrentRow(cint 0)
      except: discard

    QTimer(h: timerH, owned: false).onTimeout do() {.raises: [].}:
      dbg("rgfinder: timer fired, query=" & pendingQuery)
      populate(pendingQuery)

    listWidget.onCurrentRowChanged do(row: cint) {.raises: [].}:
      if row >= 0 and row < cint(currentMatches.len):
        let m = currentMatches[row]
        let absPath = if isAbsolute(m.file): m.file else: cwd / m.file
        try:
          let content = readFile(absPath)
          let pv = QPlainTextEdit(h: previewH, owned: false)
          pv.setPlainText(content)
          let blk = pv.document().findBlockByNumber(cint(m.lineNum - 1))
          var cur = pv.textCursor()
          cur.setPosition(blk.position())
          pv.setTextCursor(cur)
          pv.ensureCursorVisible()
        except:
          QPlainTextEdit(h: previewH, owned: false).setPlainText("(could not read file)")

    searchBox.onTextChanged do(text: openArray[char]) {.raises: [].}:
      pendingQuery = toStr(text)
      dbg("rgfinder: text changed: " & pendingQuery)
      QTimer(h: timerH, owned: false).start()

    # Ctrl+N — next result
    var nextSc = QShortcut.create(QKeySequence.create("Ctrl+N"),
                                  QObject(h: dialogH, owned: false))
    nextSc.owned = false
    nextSc.setContext(cint 2)
    nextSc.onActivated do() {.raises: [].}:
      let lw = QListWidget(h: listH, owned: false)
      lw.setCurrentRow(min(lw.currentRow() + cint 1, lw.count() - cint 1))

    # Ctrl+P — previous result
    var prevSc = QShortcut.create(QKeySequence.create("Ctrl+P"),
                                  QObject(h: dialogH, owned: false))
    prevSc.owned = false
    prevSc.setContext(cint 2)
    prevSc.onActivated do() {.raises: [].}:
      let lw = QListWidget(h: listH, owned: false)
      lw.setCurrentRow(max(lw.currentRow() - cint 1, cint 0))

    proc doSelect(row: cint) {.raises: [].} =
      if row >= 0 and row < cint(currentMatches.len):
        let m = currentMatches[row]
        let absPath = if isAbsolute(m.file): m.file else: cwd / m.file
        QDialog(h: dialogH, owned: false).accept()
        onSelected(absPath, m.lineNum)

    # Enter — activate selection
    var enterSc = QShortcut.create(QKeySequence.create("Return"),
                                   QObject(h: dialogH, owned: false))
    enterSc.owned = false
    enterSc.setContext(cint 2)
    enterSc.onActivated do() {.raises: [].}:
      doSelect(QListWidget(h: listH, owned: false).currentRow())

    # Double-click — activate selection
    listWidget.onItemDoubleClicked do(item: QListWidgetItem) {.raises: [].}:
      doSelect(QListWidget(h: listH, owned: false).row(item))

    discard QDialog(h: dialogH, owned: false).exec()
  except: discard
