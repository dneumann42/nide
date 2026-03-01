import seaqt/[qwidget, qpushbutton, qvboxlayout, qlayout,
              qstackedwidget, qfiledialog, qplaintextedit]
import bench/[buffers, highlight]

type
  Pane* = ref object
    stack: QStackedWidget
    openModuleWidget: QWidget
    editor: QPlainTextEdit
    highlighter: NimHighlighter
    bufferName*: string

proc widget*(pane: Pane): QWidget =
  QWidget(h: pane.stack.h, owned: false)

proc newPane*(onFileSelected: proc(pane: Pane, path: string) {.raises: [].}): Pane =
  result = Pane()

  var btn = QPushButton.create("Open Module")
  btn.owned = false
  var layout = QVBoxLayout.create()
  layout.owned = false
  layout.addStretch()
  layout.addWidget(QWidget(h: btn.h, owned: false), cint(0), cint(4))  # AlignHCenter = 4
  layout.addStretch()
  var openModuleWidget = QWidget.create()
  openModuleWidget.owned = false
  openModuleWidget.setLayout(QLayout(h: layout.h, owned: false))

  var editor = QPlainTextEdit.create()
  editor.owned = false
  let hl = NimHighlighter()
  hl.attach(editor.document())

  var stack = QStackedWidget.create()
  stack.owned = false
  discard stack.addWidget(QWidget(h: openModuleWidget.h, owned: false))
  discard stack.addWidget(QWidget(h: editor.h, owned: false))

  result.stack = stack
  result.openModuleWidget = openModuleWidget
  result.editor = editor
  result.highlighter = hl

  let pane = result
  btn.onClicked(proc() {.raises: [].} =
    let fn = QFileDialog.getOpenFileName(QWidget(h: pane.stack.h, owned: false))
    if fn.len > 0:
      onFileSelected(pane, fn))

proc setBuffer*(pane: Pane, buf: Buffer) =
  pane.editor.setPlainText(buf.content)
  pane.stack.setCurrentIndex(cint(1))
  pane.bufferName = buf.name

proc clearBuffer*(pane: Pane) =
  pane.editor.setPlainText("")
  pane.stack.setCurrentIndex(cint(0))
  pane.bufferName = ""
