import nide/helpers/logparser, nide/ui/widgets
import seaqt/[qboxlayout, qbrush, qclipboard, qcolor, qdialog, qfont, qguiapplication, qlabel, qlineedit, qlistwidget, qlistwidgetitem, qobject, qprocess, qpushbutton, qwidget]
import std/[os, posix]
import nide/helpers/qtconst

const
  RunnerWidth = cint 640
  RunnerHeight = cint 400
  FontHint_TypeWriter = cint 2

proc runCommand*(parent: QWidget, title, command: string,
                 onBackground: proc(reopen: proc() {.raises: [].}) {.raises: [].} = nil,
                 onGotoLocation: proc(file: string, line, col: int) {.raises: [].} = nil,
                 workingDirectory = "",
                 allowInput = false) {.raises: [].} =
  try:
    var dialog = newWidget(QDialog.create(parent))
    let dialogH = dialog.h
    QWidget(h: dialogH, owned: false).setWindowTitle(title)
    QWidget(h: dialogH, owned: false).resize(RunnerWidth, RunnerHeight)

    var listWidget = newWidget(QListWidget.create())
    var font = QFont.create("Monospace")
    font.setStyleHint(FontHint_TypeWriter)  # TypeWriter
    listWidget.asWidget.setFont(font)

    var killBtn    = newWidget(QPushButton.create("Kill"))
    var copyBtn    = newWidget(QPushButton.create("Copy Log"))
    var copyErrBtn = newWidget(QPushButton.create("Copy Error"))
    var closeBtn   = newWidget(QPushButton.create("Close"))
    var inputEdit  = newWidget(QLineEdit.create())
    var sendBtn    = newWidget(QPushButton.create("Send"))
    var statusLabel = newWidget(QLabel.create("Running..."))
    inputEdit.setPlaceholderText("Send input line...")
    sendBtn.asWidget.setEnabled(allowInput)

    let btnRow = hbox()
    btnRow.add(statusLabel)
    btnRow.addStretch()
    btnRow.add(killBtn)
    btnRow.add(copyBtn)
    btnRow.add(copyErrBtn)
    btnRow.add(closeBtn)

    let mainLayout = vbox()
    mainLayout.add(listWidget)
    if allowInput:
      let inputRow = hbox()
      inputRow.add(inputEdit)
      inputRow.add(sendBtn)
      mainLayout.addSub(inputRow)
    mainLayout.addSub(btnRow)
    mainLayout.applyTo(QWidget(h: dialogH, owned: false))

    # Process parented to dialog — Qt auto-cleans on dialog destroy
    var process = newWidget(QProcess.create(QObject(h: dialogH, owned: false)))
    let processH    = process.h
    let listH       = listWidget.h
    let statusH     = statusLabel.h
    let killBtnH    = killBtn.h
    let copyErrBtnH = copyErrBtn.h
    let inputEditH  = inputEdit.h
    let sendBtnH    = sendBtn.h

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
        var item = newWidget(QListWidgetItem.create(s))
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

    proc focusInput() {.raises: [].} =
      try:
        if allowInput:
          QWidget(h: inputEditH, owned: false).setFocus()
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
    if workingDirectory.len > 0:
      process.setWorkingDirectory(workingDirectory)
    else:
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
        if allowInput:
          QWidget(h: inputEditH, owned: false).setEnabled(false)
          QWidget(h: sendBtnH, owned: false).setEnabled(false)
      except: discard

    proc submitInput() {.raises: [].} =
      try:
        if not allowInput or not running[]:
          return
        let line = QLineEdit(h: inputEditH, owned: false).text()
        let payload = line & "\n"
        discard QProcess(h: processH, owned: false).write(payload.cstring, clonglong(payload.len))
        addLogLine("> " & line)
        QLineEdit(h: inputEditH, owned: false).clear()
        focusInput()
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
          focusInput()
        onBackground(reopenProc)

    dialog.onRejected do() {.raises: [].}:
      if running[] and onBackground != nil:
        let reopenProc = proc() {.raises: [].} =
          QWidget(h: dialogH, owned: false).show()
          focusInput()
        onBackground(reopenProc)

    if allowInput:
      inputEdit.onReturnPressed do() {.raises: [].}:
        submitInput()

      sendBtn.onClicked do() {.raises: [].}:
        submitInput()

    process.start("bash", @["-c", command])
    QWidget(h: dialogH, owned: false).show()
    focusInput()
  except: discard
