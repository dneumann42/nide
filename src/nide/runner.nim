import logparser, widgets
import seaqt/[qboxlayout, qbrush, qclipboard, qcolor, qdialog, qfont, qguiapplication, qlabel, qlistwidget, qlistwidgetitem, qobject, qprocess, qpushbutton, qwidget]
import std/[os, posix]
import qtconst

const
  RunnerWidth = cint 640
  RunnerHeight = cint 400
  FontHint_TypeWriter = cint 2

proc runCommand*(parent: QWidget, title, command: string,
                 onBackground: proc(reopen: proc() {.raises: [].}) {.raises: [].} = nil,
                 onGotoLocation: proc(file: string, line, col: int) {.raises: [].} = nil) {.raises: [].} =
  try:
    var dialog = QDialog.create(parent)
    dialog.owned = false
    let dialogH = dialog.h
    QWidget(h: dialogH, owned: false).setWindowTitle(title)
    QWidget(h: dialogH, owned: false).resize(RunnerWidth, RunnerHeight)

    var listWidget = QListWidget.create()
    listWidget.owned = false
    var font = QFont.create("Monospace")
    font.setStyleHint(FontHint_TypeWriter)  # TypeWriter
    QWidget(h: listWidget.h, owned: false).setFont(font)

    var killBtn = QPushButton.create("Kill")
    killBtn.owned = false

    var copyBtn = QPushButton.create("Copy Log")
    copyBtn.owned = false

    var copyErrBtn = QPushButton.create("Copy Error")
    copyErrBtn.owned = false

    var closeBtn = QPushButton.create("Close")
    closeBtn.owned = false

    var statusLabel = QLabel.create("Running...")
    statusLabel.owned = false

    let btnRow = hbox()
    btnRow.add(statusLabel)
    btnRow.addStretch()
    btnRow.add(killBtn)
    btnRow.add(copyBtn)
    btnRow.add(copyErrBtn)
    btnRow.add(closeBtn)

    let mainLayout = vbox()
    mainLayout.add(listWidget)
    mainLayout.addSub(btnRow)
    mainLayout.applyTo(QWidget(h: dialogH, owned: false))

    # Process parented to dialog — Qt auto-cleans on dialog destroy
    var process = QProcess.create(QObject(h: dialogH, owned: false))
    process.owned = false
    let processH    = process.h
    let listH       = listWidget.h
    let statusH     = statusLabel.h
    let killBtnH    = killBtn.h
    let copyErrBtnH = copyErrBtn.h

    # "Copy Errors" hidden until at least one error/warning appears
    QWidget(h: copyErrBtnH, owned: false).hide()

    var running: ref bool
    new(running)
    running[] = true

    # Parsed log lines (parallel to list rows)
    var lines: ref seq[LogLine]
    new(lines)
    lines[] = @[]

    # Buffer for incomplete lines across readAllStandardOutput calls
    var pending: ref string
    new(pending)
    pending[] = ""

    proc addLogLine(s: string) {.raises: [].} =
      try:
        let ll = parseLine(s)
        lines[].add(ll)
        var item = QListWidgetItem.create(s)
        item.owned = false
        case ll.level
        of llError:
          item.setForeground(QBrush.create(QColor.create("#ff5555")))
          QWidget(h: copyErrBtnH, owned: false).show()
        of llWarning:
          item.setForeground(QBrush.create(QColor.create("#ffaa00")))
          QWidget(h: copyErrBtnH, owned: false).show()
        of llHint:
          item.setForeground(QBrush.create(QColor.create("#888888")))
        of llOther:
          discard
        QListWidget(h: listH, owned: false).addItem(item)
        QListWidget(h: listH, owned: false).scrollToBottom()
      except: discard

    proc processBytes(data: openArray[char]) {.raises: [].} =
      try:
        var s = newString(data.len)
        for i in 0..<data.len: s[i] = data[i]
        var buf = pending[] & s
        var start = 0
        for i in 0..<buf.len:
          if buf[i] == '\n':
            addLogLine(buf[start ..< i])
            start = i + 1
        pending[] = buf[start .. ^1]
      except: discard

    process.setProcessChannelMode(PC_MergedChannels)   # MergedChannels
    process.setWorkingDirectory(getCurrentDir())

    process.onReadyReadStandardOutput do() {.raises: [].}:
      try:
        let bytes = QProcess(h: processH, owned: false).readAllStandardOutput()
        if bytes.len > 0:
          processBytes(toOpenArray(
            cast[ptr UncheckedArray[char]](unsafeAddr bytes[0]), 0, bytes.high))
      except: discard

    process.onFinished do(exitCode: cint) {.raises: [].}:
      try:
        running[] = false
        let bytes = QProcess(h: processH, owned: false).readAllStandardOutput()
        if bytes.len > 0:
          processBytes(toOpenArray(
            cast[ptr UncheckedArray[char]](unsafeAddr bytes[0]), 0, bytes.high))
        # Flush any remaining partial line
        if pending[].len > 0:
          addLogLine(pending[])
          pending[] = ""
        QLabel(h: statusH, owned: false).setText(
          "Finished (exit code: " & $exitCode & ")")
        QWidget(h: killBtnH, owned: false).setEnabled(false)
      except: discard

    listWidget.onItemClicked do(item: QListWidgetItem) {.raises: [].}:
      try:
        let row = QListWidget(h: listH, owned: false).row(item)
        if row >= 0 and row < lines[].len:
          let ll = lines[][row]
          if ll.level != llOther and onGotoLocation != nil:
            onGotoLocation(ll.file, ll.line, ll.col)
            QWidget(h: dialogH, owned: false).hide()
      except: discard

    copyBtn.onClicked do() {.raises: [].}:
      try:
        var text = ""
        for ll in lines[]:
          text.add(ll.raw & "\n")
        QGuiApplication.clipboard().setText(text)
      except: discard

    copyErrBtn.onClicked do() {.raises: [].}:
      try:
        var text = ""
        for ll in lines[]:
          if ll.level in {llError, llWarning}:
            text.add(ll.raw & "\n")
        QGuiApplication.clipboard().setText(text)
      except: discard

    killBtn.onClicked do() {.raises: [].}:
      let pid = QProcess(h: processH, owned: false).processId()
      if pid > 0:
        discard posix.kill(Pid(-pid), SIGKILL)  # kill entire process group
      QProcess(h: processH, owned: false).kill()

    closeBtn.onClicked do() {.raises: [].}:
      QWidget(h: dialogH, owned: false).hide()
      if running[] and onBackground != nil:
        let reopenProc = proc() {.raises: [].} =
          QWidget(h: dialogH, owned: false).show()
        onBackground(reopenProc)

    dialog.onRejected do() {.raises: [].}:
      if running[] and onBackground != nil:
        let reopenProc = proc() {.raises: [].} =
          QWidget(h: dialogH, owned: false).show()
        onBackground(reopenProc)

    process.start("bash", @["-c", command])
    QWidget(h: dialogH, owned: false).show()
  except: discard
