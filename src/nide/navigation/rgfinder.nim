import std/[strutils, os, osproc]
import seaqt/[qwidget, qdialog, qlineedit, qlistwidget,
              qlistwidgetitem, qshortcut, qkeysequence, qobject, qtimer,
              qsplitter, qplaintextedit, qtextdocument, qtextcursor, qtextobject]
import nide/editor/highlight, nide/ui/codepreview, nide/ui/widgets
import nide/helpers/qtconst

const
  RgFinderWidth = cint 900
  RgFinderHeight = cint 500
  SearchDebounceMs = cint 300
  MaxRgResults = 200

proc dbg(msg: string) {.raises: [].} =
  try: stderr.write(msg & "\n") except: discard

proc toStr*(oa: openArray[char]): string {.raises: [].} =
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

    var dialog = newWidget(QDialog.create(parent))
    let dialogH = dialog.h
    QWidget(h: dialogH, owned: false).setWindowTitle("Find in Files")
    QWidget(h: dialogH, owned: false).resize(RgFinderWidth, RgFinderHeight)

    var searchBox = newWidget(QLineEdit.create())

    var listWidget = newWidget(QListWidget.create())
    let listH = listWidget.h

    let leftLayout = vbox()
    leftLayout.add(searchBox)
    leftLayout.add(listWidget)

    var leftPanel = newWidget(QWidget.create())
    leftLayout.applyTo(leftPanel)

    let (preview, previewGutterH) = setupCodePreview(leftPanel)
    let previewHl = NimHighlighter()
    previewHl.attach(preview.document())
    let previewH = preview.h

    var splitter = newWidget(QSplitter.create(Horizontal))
    splitter.addWidget(leftPanel)
    splitter.addWidget(preview.asWidget)
    splitter.setStretchFactor(cint 0, cint 1)
    splitter.setStretchFactor(cint 1, cint 2)

    let outerLayout = vbox()
    outerLayout.add(splitter)
    outerLayout.applyTo(QWidget(h: dialogH, owned: false))

    var currentMatches: seq[RgMatch]
    var pendingQuery = ""

    var timer = newWidget(QTimer.create(QObject(h: dialogH, owned: false)))
    let timerH = timer.h
    QTimer(h: timerH, owned: false).setSingleShot(true)
    QTimer(h: timerH, owned: false).setInterval(SearchDebounceMs)

    proc populate(query: string) {.raises: [].} =
      let lw = QListWidget(h: listH, owned: false)
      lw.clear()
      currentMatches = @[]
      if query.strip().len == 0: return
      try:
        # Find real ripgrep: try common locations before relying on PATH
        # (/usr/sbin/rg may be a non-ripgrep system utility)
        var rgExe = ""
        for candidate in [getAppDir() / "rg",
                          "/usr/bin/rg",
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
          if currentMatches.len >= MaxRgResults: break
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
    var nextSc = newWidget(QShortcut.create(QKeySequence.create("Ctrl+N"),
                                            QObject(h: dialogH, owned: false)))
    nextSc.setContext(SC_WindowShortcut)
    nextSc.onActivated do() {.raises: [].}:
      let lw = QListWidget(h: listH, owned: false)
      lw.setCurrentRow(min(lw.currentRow() + cint 1, lw.count() - cint 1))

    # Ctrl+P — previous result
    var prevSc = newWidget(QShortcut.create(QKeySequence.create("Ctrl+P"),
                                            QObject(h: dialogH, owned: false)))
    prevSc.setContext(SC_WindowShortcut)
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
    var enterSc = newWidget(QShortcut.create(QKeySequence.create("Return"),
                                             QObject(h: dialogH, owned: false)))
    enterSc.setContext(SC_WindowShortcut)
    enterSc.onActivated do() {.raises: [].}:
      doSelect(QListWidget(h: listH, owned: false).currentRow())

    # Double-click — activate selection
    listWidget.onItemDoubleClicked do(item: QListWidgetItem) {.raises: [].}:
      doSelect(QListWidget(h: listH, owned: false).row(item))

    discard QDialog(h: dialogH, owned: false).exec()
  except: discard
