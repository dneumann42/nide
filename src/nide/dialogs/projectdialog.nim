import std/[json, os, osproc, algorithm]
import seaqt/[qwidget, qdialog, qlineedit, qformlayout, qvboxlayout, qhboxlayout, qdialogbuttonbox, qpushbutton, qfiledialog, qcombobox, qlabel, qframe]
import nide/project/projects
import nide/helpers/qtconst
import nide/ui/widgets

const
  DialogMinWidth = cint 520
  DialogMinHeight = cint 420
  FieldMinWidth = cint 280
  PathMinWidth = cint 220
  FormSpacing = cint 12

proc getNimVersions*(): seq[string] =
  try:
    discard execProcess("nimble", args = ["refresh"], options = {poStdErrToStdOut, poUsePath})
  except:
    discard
  let releasesFile = getHomeDir() / ".nimble" / "official-nim-releases.json"
  if not fileExists(releasesFile):
    return @["2.2.6", "devel"]
  try:
    let jsonContent = readFile(releasesFile)
    let jsonData = parseJson(jsonContent)
    for item in jsonData:
      if item.hasKey("version"):
        result.add(item["version"].getStr())
    result.sort(Descending)
    result.add("devel")
  except:
    return @["2.2.6", "devel"]

proc showNewProjectDialog*(parent: QWidget, pm: var ProjectManager) =
  var dialog = QDialog.create(parent)
  let dialogH = dialog.h
  QWidget(h: dialogH, owned: false).setWindowTitle("New Project")
  QWidget(h: dialogH, owned: false).setMinimumWidth(DialogMinWidth)
  QWidget(h: dialogH, owned: false).setMinimumHeight(DialogMinHeight)

  var nameEdit    = newWidget(QLineEdit.create())
  var versionEdit = newWidget(QLineEdit.create())
  var authorEdit  = newWidget(QLineEdit.create())
  var descEdit    = newWidget(QLineEdit.create())

  nameEdit.setMinimumWidth(FieldMinWidth)
  versionEdit.setMinimumWidth(FieldMinWidth)
  authorEdit.setMinimumWidth(FieldMinWidth)
  descEdit.setMinimumWidth(FieldMinWidth)

  nameEdit.setPlaceholderText("myproject")
  versionEdit.setText("0.1.0")
  authorEdit.setPlaceholderText("Your Name")
  descEdit.setPlaceholderText("A short description of your project")

  var licenseCombo = newWidget(QComboBox.create())
  licenseCombo.setMinimumWidth(FieldMinWidth)
  licenseCombo.addItem("MIT")
  licenseCombo.addItem("Apache-2.0")
  licenseCombo.addItem("GPL-2.0")
  licenseCombo.addItem("GPL-3.0")
  licenseCombo.addItem("BSD")
  licenseCombo.addItem("MPL-2.0")
  licenseCombo.addItem("Unlicense")
  licenseCombo.setCurrentIndex(cint 0)

  var nimVersions = getNimVersions()
  var nimVersionCombo = newWidget(QComboBox.create())
  nimVersionCombo.setMinimumWidth(FieldMinWidth)
  for ver in nimVersions:
    nimVersionCombo.addItem(ver)
  nimVersionCombo.setCurrentIndex(cint 0)

  var pathEditRow = newWidget(QWidget.create())
  var pathEditRowLayout = hbox()
  pathEditRowLayout.applyTo(pathEditRow)

  var pathEdit = newWidget(QLineEdit.create())
  pathEdit.setMinimumWidth(PathMinWidth)
  pathEditRowLayout.add(pathEdit)

  var pathEditButton = newWidget(QPushButton.create("Browse"))
  pathEditRowLayout.add(pathEditButton)
  let dialogRef = dialog.asWidget
  pathEditButton.onClicked do():
    let dir = QFileDialog.getExistingDirectory(dialogRef)
    if dir.len > 0:
      pathEdit.setText(dir)

  pathEdit.setPlaceholderText("/path/to/projects")

  var separator = newWidget(QFrame.create())
  separator.setFrameShape(QF_Box)
  separator.setFrameShadow(QF_Plain)
  separator.setStyleSheet("QFrame { background: #e0e0e0; min-height: 2px; max-height: 2px; }")

  var form = newWidget(QFormLayout.create())
  form.setSpacing(FormSpacing)
  form.addRow("Name",        nameEdit.asWidget)
  form.addRow("Version",     versionEdit.asWidget)
  form.addRow("Author",      authorEdit.asWidget)
  form.addRow("Description", descEdit.asWidget)
  form.addRow("Nim Version", nimVersionCombo.asWidget)
  form.addRow("License",     licenseCombo.asWidget)
  form.addRow("Location",    pathEditRow.asWidget)

  var label = newWidget(QLabel.create("Create a new Nim project"))
  label.asWidget.setStyleSheet("QLabel { font-weight: bold; font-size: 14px; padding-bottom: 8px; }")

  var buttons = newWidget(QDialogButtonBox.create2(Btn_OkCancel))
  buttons.onAccepted do(): dialog.accept()
  buttons.onRejected do(): dialog.reject()

  var mainLayout = vbox(spacing = cint 8)
  mainLayout.add(label)
  mainLayout.add(separator)
  mainLayout.addLayout(form.asLayout())
  mainLayout.addStretch(1)
  mainLayout.add(buttons)
  mainLayout.applyTo(QWidget(h: dialogH, owned: false))

  if dialog.exec() == 1:
    pm.createProject(Project(
      name:        nameEdit.text(),
      version:     versionEdit.text(),
      author:      authorEdit.text(),
      description: descEdit.text(),
      license:     licenseCombo.currentText(),
      nimVersion:  nimVersionCombo.currentText(),
      path:        pathEdit.text(),
    ))