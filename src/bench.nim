import std/[os]
import seaqt/[
  qapplication, qmainwindow, qstackedwidget,
  qwidget, qpushbutton,
  qplaintextedit, qtoolbar, qboxlayout,
  qmenu, qtoolbutton, qaction, qkeysequence, qfiledialog]
import seaqt/QtWidgets/gen_qlayout_types

let _ = QApplication.create()

let dashboard = QWidget.create()
let dashLayout = QVBoxLayout.create()
let startBtn = QPushButton.create("Start")
startBtn.setFixedWidth(120)
dashLayout.addStretch()
dashLayout.addWidget(QWidget(h: startBtn.h, owned: false), 0, 132) # AlignCenter
dashLayout.addStretch()
dashboard.setLayout(QLayout(h: dashLayout.h, owned: false))

let editPage = QWidget.create()
let editLayout = QVBoxLayout.create()
let toolbar = QToolBar.create()
toolbar.setMovable(false)
toolbar.setFloatable(false)

let backBtn = QPushButton.create("← Back")
discard toolbar.addWidget(QWidget(h: backBtn.h, owned: false))

let fileMenu = QMenu.create()
let menuWidget = QWidget(h: fileMenu.h, owned: false)
let actOpen   = menuWidget.addAction("&Open",    QKeySequence.create("Ctrl+O"))
let actSave   = menuWidget.addAction("&Save",    QKeySequence.create("Ctrl+S"))
let actSaveAs = menuWidget.addAction("Save &As", QKeySequence.create("Ctrl+Shift+S"))
discard fileMenu.addSeparator()
let actQuit   = menuWidget.addAction("&Quit",    QKeySequence.create("Ctrl+Q"))

let fileBtn = QToolButton.create()
fileBtn.setText("File")
fileBtn.setMenu(fileMenu)
fileBtn.setPopupMode(cint QToolButtonToolButtonPopupModeEnum.InstantPopup)
discard toolbar.addWidget(QWidget(h: fileBtn.h, owned: false))

let editor = QPlainTextEdit.create()
editLayout.setSpacing(0)
editLayout.addWidget(QWidget(h: toolbar.h, owned: false))
editLayout.addWidget(QWidget(h: editor.h, owned: false), 1)
editPage.setLayout(QLayout(h: editLayout.h, owned: false))

let win = QMainWindow.create()
win.setWindowTitle("bench DEV 0.0.0")
win.resize(800, 600)

let stack = QStackedWidget.create()
win.setCentralWidget(QWidget(h: stack.h, owned: false))

let idxDash = stack.addWidget(dashboard)
let idxEdit = stack.addWidget(editPage)

startBtn.onPressed do():
  stack.setCurrentIndex(idxEdit)

backBtn.onPressed do():
  stack.setCurrentIndex(idxDash)

actOpen.onTriggered do():
  let path = QFileDialog.getOpenFileName(
    QWidget(h: win.h, owned: false),
    "Open File", "", "Nim files (*.nim *.nimble *.nims);;All files (*)")
  if path.len > 0:
    try:
      editor.setPlainText(readFile(path))
      stack.setCurrentIndex(idxEdit)
    except IOError:
      discard
actSave.onTriggered do(): discard
actSaveAs.onTriggered do(): discard
actQuit.onTriggered do(): QApplication.quit()

win.show()

when isMainModule:
  quit QApplication.exec().int
