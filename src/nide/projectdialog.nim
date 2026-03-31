import std/[json, os, osproc, algorithm]
import seaqt/[qwidget, qdialog, qlineedit, qformlayout, qvboxlayout, qhboxlayout, qdialogbuttonbox, qpushbutton, qfiledialog, qcombobox, qlabel, qframe]
import projects
import qtconst

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

  var nameEdit    = QLineEdit.create(); nameEdit.owned    = false
  var versionEdit = QLineEdit.create(); versionEdit.owned = false
  var authorEdit  = QLineEdit.create(); authorEdit.owned  = false
  var descEdit    = QLineEdit.create(); descEdit.owned    = false

  nameEdit.setMinimumWidth(FieldMinWidth)
  versionEdit.setMinimumWidth(FieldMinWidth)
  authorEdit.setMinimumWidth(FieldMinWidth)
  descEdit.setMinimumWidth(FieldMinWidth)

  nameEdit.setPlaceholderText("myproject")
  versionEdit.setText("0.1.0")
  authorEdit.setPlaceholderText("Your Name")
  descEdit.setPlaceholderText("A short description of your project")

  var licenseCombo = QComboBox.create(); licenseCombo.owned = false
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
  var nimVersionCombo = QComboBox.create(); nimVersionCombo.owned = false
  nimVersionCombo.setMinimumWidth(FieldMinWidth)
  for ver in nimVersions:
    nimVersionCombo.addItem(ver)
  nimVersionCombo.setCurrentIndex(cint 0)

  var
    pathEditRow = QWidget.create()
    pathEditRowLayout = QHBoxLayout.create()

  pathEditRow.setLayout(QLayout(h: pathEditRowLayout.h, owned: false))
  pathEditRowLayout.owned = false
  pathEditRow.owned = false

  var pathEdit = QLineEdit.create(); pathEdit.owned = false
  pathEdit.setMinimumWidth(PathMinWidth)
  pathEditRowLayout.addWidget(QWidget(h: pathEdit.h, owned: false))
  QLayout(h: pathEditRowLayout.h, owned: false).setContentsMargins(0, 0, 0, 0)

  var pathEditButton = QPushButton.create("Browse"); pathEditButton.owned = false
  pathEditRowLayout.addWidget(QWidget(h: pathEditButton.h, owned: false))
  let dialogRef = QWidget(h: dialog.h, owned: false)
  pathEditButton.onClicked do():
    let dir = QFileDialog.getExistingDirectory(dialogRef)
    if dir.len > 0:
      pathEdit.setText(dir)

  pathEdit.setPlaceholderText("/path/to/projects")

  var separator = QFrame.create()
  separator.owned = false
  separator.setFrameShape(QF_Box)
  separator.setFrameShadow(QF_Plain)
  separator.setStyleSheet("QFrame { background: #e0e0e0; min-height: 2px; max-height: 2px; }")

  var form = QFormLayout.create(); form.owned = false
  form.setSpacing(FormSpacing)
  form.addRow("Name",        QWidget(h: nameEdit.h,    owned: false))
  form.addRow("Version",     QWidget(h: versionEdit.h, owned: false))
  form.addRow("Author",      QWidget(h: authorEdit.h,  owned: false))
  form.addRow("Description", QWidget(h: descEdit.h,    owned: false))
  form.addRow("Nim Version", QWidget(h: nimVersionCombo.h, owned: false))
  form.addRow("License",     QWidget(h: licenseCombo.h, owned: false))
  form.addRow("Location",    QWidget(h: pathEditRow.h,    owned: false))

  var label = QLabel.create("Create a new Nim project")
  label.owned = false
  QWidget(h: label.h, owned: false).setStyleSheet("QLabel { font-weight: bold; font-size: 14px; padding-bottom: 8px; }")

  var buttons = QDialogButtonBox.create2(Btn_OkCancel)
  buttons.owned = false
  buttons.onAccepted do(): dialog.accept()
  buttons.onRejected do(): dialog.reject()

  var mainLayout = QVBoxLayout.create(); mainLayout.owned = false
  mainLayout.setSpacing(cint 8)
  mainLayout.addWidget(QWidget(h: label.h, owned: false))
  mainLayout.addWidget(QWidget(h: separator.h, owned: false))
  mainLayout.addLayout(QLayout(h: form.h, owned: false))
  mainLayout.addStretch(1)
  mainLayout.addWidget(QWidget(h: buttons.h, owned: false))

  QWidget(h: dialogH, owned: false).setLayout(QLayout(h: mainLayout.h, owned: false))

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