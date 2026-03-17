import seaqt/[qwidget, qdialog, qformlayout, qvboxlayout, qhboxlayout, qdialogbuttonbox,
              qlineedit, qcheckbox, qspinbox, qcombobox, qabstractbutton, qlabel,
              qabstractspinbox, qsplitter, qlayout]
import toml_serialization, os

import theme
import themedialog

type
  AppearanceSettings* = object
    themeMode*: Theme
    transparent*: bool
    lineNumbers*: bool
    font* = "Fira Code"
    fontSize* = 14
    syntaxTheme* = "Monokai"

  Settings* = object
    appearance*: AppearanceSettings

const 
  SettingsFile = "settings.toml"

proc syntaxTheme*(s: Settings): string = s.appearance.syntaxTheme
proc `syntaxTheme=`*(s: var Settings, v: string) = s.appearance.syntaxTheme = v

proc load*(T: typedesc[Settings]): T {.raises: [].} =
  result = T()
  try:
    if not dirExists(getConfigDir() / "bench"):
      createDir(getConfigDir() / "bench")
    let path = getConfigDir() / "bench" / SettingsFile
    if fileExists(path):
      result = Toml.decode(readFile(path), T)
  except:
    echo getCurrentExceptionMsg()

proc write*(settings: Settings) {.raises: [].} =
  try:
    if not dirExists(getConfigDir() / "bench"):
      createDir(getConfigDir() / "bench")
    let path = getConfigDir() / "bench" / SettingsFile
    writeFile(path, Toml.encode(settings))
  except:
    echo getCurrentExceptionMsg()

proc showSettingsDialog*(
  parent:  QWidget,
  current: Settings,
  onApply: proc(s: Settings) {.raises: [].}
) {.raises: [].} =
  try:
    var dialog = QDialog.create(parent)
    dialog.owned = false
    let dialogH = dialog.h

    QWidget(h: dialogH, owned: false).setWindowTitle("Settings")
    QWidget(h: dialogH, owned: false).resize(cint 900, cint 560)

    # ── Appearance controls ─────────────────────────────────────────────────

    # Theme mode (Light / Dark)
    var themeModeCombo = QComboBox.create()
    themeModeCombo.owned = false
    themeModeCombo.addItem("Light")
    themeModeCombo.addItem("Dark")
    themeModeCombo.setCurrentIndex(
      if current.appearance.themeMode == Dark: cint 1 else: cint 0)

    # Font family
    var fontEdit = QLineEdit.create()
    fontEdit.owned = false
    fontEdit.setText(current.appearance.font)
    fontEdit.setPlaceholderText("e.g. Fira Code, Monospace")

    # Font size
    var fontSizeSpin = QSpinBox.create()
    fontSizeSpin.owned = false
    fontSizeSpin.setMinimum(cint 6)
    fontSizeSpin.setMaximum(cint 72)
    fontSizeSpin.setValue(cint current.appearance.fontSize)

    # Line numbers toggle
    var lineNumbersCheck = QCheckBox.create("Show line numbers")
    lineNumbersCheck.owned = false
    QAbstractButton(h: lineNumbersCheck.h, owned: false).setChecked(
      current.appearance.lineNumbers)

    # ── Form (top section) ──────────────────────────────────────────────────
    var form = QFormLayout.create()
    form.owned = false
    form.addRow("Theme mode",  QWidget(h: themeModeCombo.h,   owned: false))
    form.addRow("Font family", QWidget(h: fontEdit.h,         owned: false))
    form.addRow("Font size",   QWidget(h: fontSizeSpin.h,     owned: false))
    form.addRow("",            QWidget(h: lineNumbersCheck.h, owned: false))

    # ── Syntax theme picker (list + live preview) ───────────────────────────
    var syntaxLabel = QLabel.create("Syntax theme")
    syntaxLabel.owned = false

    let picker = buildThemePickerWidget(
      QWidget(h: dialogH, owned: false),
      current.appearance.syntaxTheme)

    # ── Buttons ─────────────────────────────────────────────────────────────
    var buttons = QDialogButtonBox.create2(cint(1024 or 4194304))  # Ok | Cancel
    buttons.owned = false
    buttons.onAccepted do():
      QDialog(h: dialogH, owned: false).accept()
    buttons.onRejected do():
      QDialog(h: dialogH, owned: false).reject()

    # ── Layout ──────────────────────────────────────────────────────────────
    var mainLayout = QVBoxLayout.create()
    mainLayout.owned = false
    mainLayout.addLayout(QLayout(h: form.h, owned: false))
    mainLayout.addWidget(QWidget(h: syntaxLabel.h,        owned: false), cint 0)
    mainLayout.addWidget(QWidget(h: picker.splitter.h,    owned: false), cint 1)
    mainLayout.addWidget(QWidget(h: buttons.h,            owned: false), cint 0)

    QWidget(h: dialogH, owned: false).setLayout(
      QLayout(h: mainLayout.h, owned: false))

    if QDialog(h: dialogH, owned: false).exec() == 1:  # Accepted
      var updated = current
      updated.appearance.themeMode =
        if themeModeCombo.currentIndex() == 1: Dark else: Light
      updated.appearance.font       = fontEdit.text()
      updated.appearance.fontSize   = int fontSizeSpin.value()
      updated.appearance.lineNumbers =
        QAbstractButton(h: lineNumbersCheck.h, owned: false).isChecked()
      let chosen = picker.currentThemeSelection()
      if chosen.len > 0:
        updated.appearance.syntaxTheme = chosen
      onApply(updated)
  except:
    discard
