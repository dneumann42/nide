import std/os
import seaqt/[qwidget, qdialog, qlineedit, qformlayout, qvboxlayout, qhboxlayout,
              qdialogbuttonbox, qpushbutton, qfiledialog]
import nide/helpers/qtconst
import nide/ui/widgets

const
  PathEditMinWidth = 150

proc showNewModuleDialog*(parent: QWidget): string =
  var dialog = QDialog.create(parent)

  var nameEdit = newWidget(QLineEdit.create())
  nameEdit.setPlaceholderText("module_name")

  var pathEditRow = newWidget(QWidget.create())
  var pathEditRowLayout = hbox()
  pathEditRowLayout.applyTo(pathEditRow)

  var pathEdit = newWidget(QLineEdit.create())
  pathEdit.setMinimumWidth(PathEditMinWidth)
  let defaultPath = try: getCurrentDir() / "src" except OSError: "src"
  pathEdit.setText(defaultPath)
  pathEditRowLayout.add(pathEdit)

  var browseBtn = newWidget(QPushButton.create("Browse"))
  pathEditRowLayout.add(browseBtn)
  let dialogRef = dialog.asWidget
  browseBtn.onClicked do():
    let dir = QFileDialog.getExistingDirectory(dialogRef)
    if dir.len > 0:
      pathEdit.setText(dir)

  var form = newWidget(QFormLayout.create())
  form.addRow("Name", nameEdit.asWidget)
  form.addRow("Path", pathEditRow.asWidget)

  # Ok=1024, Cancel=4194304 (QDialogButtonBox::StandardButton)
  var buttons = newWidget(QDialogButtonBox.create2(Btn_OkCancel))
  buttons.onAccepted do(): dialog.accept()
  buttons.onRejected do(): dialog.reject()

  var mainLayout = vbox()
  mainLayout.addLayout(form.asLayout())
  mainLayout.add(buttons)

  dialog.asWidget.setWindowTitle("New Module")
  mainLayout.applyTo(dialog.asWidget)

  if dialog.exec() == 1:
    let name = nameEdit.text()
    let dir  = pathEdit.text()
    if name.len > 0 and dir.len > 0:
      let path = dir / name & ".nim"
      try:
        createDir(dir)
        writeFile(path, "when isMainModule:\n  discard\n")
        return path
      except: discard
