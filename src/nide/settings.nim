import seaqt/[qwidget, qdialog, qformlayout, qvboxlayout, qhboxlayout, qdialogbuttonbox,
              qlineedit, qcheckbox, qspinbox, qcombobox, qabstractbutton, qlabel,
              qabstractspinbox, qsplitter, qlayout, qslider, qabstractslider,
              qgraphicsopacityeffect, qgraphicseffect,
              qtabwidget, qtablewidget, qheaderview, qpushbutton, qkeysequenceedit,
              qkeysequence, qtableview, qabstractitemview]
import std/[tables, algorithm, strutils]

import theme
import themedialog
import opacity
import settingsstore
import ../commands

type
  AppearanceSettings* = object
    themeMode*: Theme
    transparent*: bool
    lineNumbers*: bool
    font* = "Fira Code"
    fontSize* = 14
    syntaxTheme* = "Monokai"
    opacityEnabled*: bool
    opacityLevel*:   int = 85

  KeybindingOverride* = object
    command*: string
    key*:     string

  Settings* = object
    appearance*:  AppearanceSettings
    restoreLastSessionOnLaunch*: bool
    keybindings*: seq[KeybindingOverride]  ## user-defined overrides, e.g. {command: "editor.forwardChar", key: "Ctrl+T"}

proc syntaxTheme*(s: Settings): string = s.appearance.syntaxTheme
proc `syntaxTheme=`*(s: var Settings, v: string) = s.appearance.syntaxTheme = v

proc toStored(overrides: seq[KeybindingOverride]): seq[StoredKeybindingOverride] =
  for o in overrides:
    result.add(StoredKeybindingOverride(command: o.command, key: o.key))

proc toRuntime(overrides: seq[StoredKeybindingOverride]): seq[KeybindingOverride] =
  for o in overrides:
    result.add(KeybindingOverride(command: o.command, key: o.key))

proc toStoredTheme(theme: Theme): string =
  case theme
  of Dark: "Dark"
  of Light: "Light"

proc parseStoredTheme(value: string): Theme =
  if value.toLowerAscii() == "dark": Dark else: Light

proc toStored(settings: Settings): StoredSettings =
  result.appearance.themeMode = toStoredTheme(settings.appearance.themeMode)
  result.appearance.transparent = settings.appearance.transparent
  result.appearance.lineNumbers = settings.appearance.lineNumbers
  result.appearance.font = settings.appearance.font
  result.appearance.fontSize = settings.appearance.fontSize
  result.appearance.syntaxTheme = settings.appearance.syntaxTheme
  result.appearance.opacityEnabled = settings.appearance.opacityEnabled
  result.appearance.opacityLevel = settings.appearance.opacityLevel
  result.restoreLastSessionOnLaunch = settings.restoreLastSessionOnLaunch
  result.keybindings = settings.keybindings.toStored()

proc toRuntime(stored: StoredSettings): Settings =
  result = Settings()
  result.appearance.themeMode = parseStoredTheme(stored.appearance.themeMode)
  result.appearance.transparent = stored.appearance.transparent
  result.appearance.lineNumbers = stored.appearance.lineNumbers
  if stored.appearance.font.len > 0:
    result.appearance.font = stored.appearance.font
  if stored.appearance.fontSize > 0:
    result.appearance.fontSize = stored.appearance.fontSize
  if stored.appearance.syntaxTheme.len > 0:
    result.appearance.syntaxTheme = stored.appearance.syntaxTheme
  result.appearance.opacityEnabled = stored.appearance.opacityEnabled
  if stored.appearance.opacityLevel > 0:
    result.appearance.opacityLevel = stored.appearance.opacityLevel
  result.restoreLastSessionOnLaunch = stored.restoreLastSessionOnLaunch
  result.keybindings = stored.keybindings.toRuntime()

proc toTable*(overrides: seq[KeybindingOverride]): Table[string, string] =
  for o in overrides: result[o.command] = o.key

proc toOverrides*(t: Table[string, string]): seq[KeybindingOverride] =
  for cmd, key in t: result.add(KeybindingOverride(command: cmd, key: key))

proc load*(_: typedesc[Settings]): Settings {.raises: [].} =
  loadStoredSettings().toRuntime()

proc write*(settings: Settings) {.raises: [].} =
  writeStoredSettings(settings.toStored())

proc showSettingsDialog*(
  parent:           QWidget,
  current:          Settings,
  onApply:          proc(s: Settings) {.raises: [].},
  onOpacityPreview: proc(enabled: bool, level: int) {.raises: [].} = nil
) {.raises: [].} =
  try:
    var dialog = QDialog.create(parent)
    dialog.owned = false
    let dialogH = dialog.h

    QWidget(h: dialogH, owned: false).setWindowTitle("Settings")
    QWidget(h: dialogH, owned: false).resize(cint 900, cint 600)
    # Content container — opacity effect goes on this child, not the dialog itself
    var contentWidget = QWidget.create(QWidget(h: dialogH, owned: false))
    contentWidget.owned = false
    let contentH = contentWidget.h
    let contentEff = setupWindowOpacity(
      QWidget(h: dialogH, owned: false),
      QWidget(h: contentH, owned: false),
      current.appearance.opacityEnabled,
      current.appearance.opacityLevel)
    let contentEffectH = contentEff.h

    # ── Tab widget ───────────────────────────────────────────────────────────
    var tabs = QTabWidget.create(QWidget(h: contentH, owned: false))
    tabs.owned = false
    let tabsH = tabs.h

    # ════════════════════════════════════════════════════════════════════════
    # Tab 1 — Appearance
    # ════════════════════════════════════════════════════════════════════════
    var appearTab = QWidget.create(QWidget(h: tabsH, owned: false))
    appearTab.owned = false
    let appearTabH = appearTab.h

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

    # Opacity checkbox
    var opacityCheck = QCheckBox.create("Enable opacity")
    opacityCheck.owned = false
    QAbstractButton(h: opacityCheck.h, owned: false).setChecked(
      current.appearance.opacityEnabled)

    var restoreSessionCheck = QCheckBox.create("Automatically restore last session on launch")
    restoreSessionCheck.owned = false
    QAbstractButton(h: restoreSessionCheck.h, owned: false).setChecked(
      current.restoreLastSessionOnLaunch)

    # Opacity slider — Qt::Horizontal = 1
    var opacitySlider = QSlider.create(cint 1)
    opacitySlider.owned = false
    QWidget(h: opacitySlider.h, owned: false).setMinimumHeight(cint 24)
    QAbstractSlider(h: opacitySlider.h, owned: false).setMinimum(cint 20)
    QAbstractSlider(h: opacitySlider.h, owned: false).setMaximum(cint 100)
    QAbstractSlider(h: opacitySlider.h, owned: false).setSingleStep(cint 5)
    QAbstractSlider(h: opacitySlider.h, owned: false).setValue(
      cint current.appearance.opacityLevel)
    QWidget(h: opacitySlider.h, owned: false).setEnabled(
      current.appearance.opacityEnabled)

    # Percentage label
    var opacityLabel = QLabel.create($current.appearance.opacityLevel & "%")
    opacityLabel.owned = false
    QWidget(h: opacityLabel.h, owned: false).setMinimumWidth(cint 36)

    # Wire checkbox → enable/disable slider + live preview
    let sliderH   = opacitySlider.h
    let labelH    = opacityLabel.h
    let checkH    = opacityCheck.h
    let previewCb = onOpacityPreview
    opacityCheck.onStateChanged do(state: cint) {.raises: [].}:
      let enabled = state != 0
      QWidget(h: sliderH, owned: false).setEnabled(enabled)
      let lvl = int QAbstractSlider(h: sliderH, owned: false).value()
      QGraphicsOpacityEffect(h: contentEffectH, owned: false).applyOpacity(enabled, lvl)
      if previewCb != nil:
        previewCb(enabled, lvl)

    # Wire slider → update label + live preview
    QAbstractSlider(h: opacitySlider.h, owned: false).onValueChanged do(v: cint) {.raises: [].}:
      QLabel(h: labelH, owned: false).setText($v & "%")
      let enabled = QAbstractButton(h: checkH, owned: false).isChecked()
      QGraphicsOpacityEffect(h: contentEffectH, owned: false).applyOpacity(enabled, int v)
      if previewCb != nil:
        previewCb(enabled, int v)

    # Slider row
    var opacityRowLayout = QHBoxLayout.create()
    opacityRowLayout.owned = false
    opacityRowLayout.setContentsMargins(cint 0, cint 0, cint 0, cint 0)
    opacityRowLayout.addWidget(QWidget(h: opacitySlider.h, owned: false), cint 1)
    opacityRowLayout.addWidget(QWidget(h: opacityLabel.h,  owned: false), cint 0)

    # Form layout
    var form = QFormLayout.create()
    form.owned = false
    form.addRow("Theme mode",    QWidget(h: themeModeCombo.h,   owned: false))
    form.addRow("Font family",   QWidget(h: fontEdit.h,         owned: false))
    form.addRow("Font size",     QWidget(h: fontSizeSpin.h,     owned: false))
    form.addRow("",              QWidget(h: lineNumbersCheck.h, owned: false))
    form.addRow("",              QWidget(h: restoreSessionCheck.h, owned: false))
    form.addRow("",              QWidget(h: opacityCheck.h,     owned: false))
    form.addRow("Opacity level", QLayout(h: opacityRowLayout.h, owned: false))

    # Syntax theme picker
    var syntaxLabel = QLabel.create("Syntax theme")
    syntaxLabel.owned = false

    let picker = buildThemePickerWidget(
      QWidget(h: appearTabH, owned: false),
      current.appearance.syntaxTheme)

    # Appearance tab layout
    var appearLayout = QVBoxLayout.create()
    appearLayout.owned = false
    appearLayout.addLayout(QLayout(h: form.h, owned: false))
    appearLayout.addWidget(QWidget(h: syntaxLabel.h,     owned: false), cint 0)
    appearLayout.addWidget(QWidget(h: picker.splitter.h, owned: false), cint 1)
    QWidget(h: appearTabH, owned: false).setLayout(
      QLayout(h: appearLayout.h, owned: false))

    discard QTabWidget(h: tabsH, owned: false).addTab(
      QWidget(h: appearTabH, owned: false), "Appearance")

    # ════════════════════════════════════════════════════════════════════════
    # Tab 2 — Keybindings
    # ════════════════════════════════════════════════════════════════════════
    var kbTab = QWidget.create(QWidget(h: tabsH, owned: false))
    kbTab.owned = false
    let kbTabH = kbTab.h

    # Build sorted list of all default bindings
    var allBindings = defaultBindingList()
    allBindings.sort(proc(a, b: BindingEntry): int = cmp(a.id, b.id))

    var kbTable = QTableWidget.create(cint allBindings.len, cint 3)
    kbTable.owned = false
    let kbTableH = kbTable.h

    # Table configuration: no editing, select rows, no grid
    QAbstractItemView(h: kbTableH, owned: false).setEditTriggers(cint 0)
    QAbstractItemView(h: kbTableH, owned: false).setSelectionBehavior(cint 1)
    QTableView(h: kbTableH, owned: false).setShowGrid(false)
    QTableWidget(h: kbTableH, owned: false).setHorizontalHeaderLabels(
      @["Command", "Binding", ""])
    let hdr = QTableView(h: kbTableH, owned: false).horizontalHeader()
    hdr.setStretchLastSection(false)
    hdr.setSectionResizeMode(cint 0, cint 1)  # ResizeToContents
    hdr.setSectionResizeMode(cint 1, cint 1)
    hdr.setSectionResizeMode(cint 2, cint 2)  # Fixed
    QHeaderView(h: hdr.h, owned: false).resizeSection(cint 2, cint 60)
    let vhdr = QTableView(h: kbTableH, owned: false).verticalHeader()
    QWidget(h: vhdr.h, owned: false).setVisible(false)

    # Track user's custom binding changes (starts as a copy of saved customs)
    var customChanges = new(Table[string, string])
    customChanges[] = current.keybindings.toTable()

    for i, entry in allBindings:
      let row = cint i

      # Col 0: command id — read-only
      var idItem = QTableWidgetItem.create(entry.id)
      idItem.owned = false
      idItem.setFlags(cint 0x21)  # ItemIsSelectable | ItemIsEnabled
      QTableWidget(h: kbTableH, owned: false).setItem(row, cint 0, idItem)

      # Col 1: current binding string — read-only
      let bindStr =
        if customChanges[].hasKey(entry.id): customChanges[][entry.id]
        else: keyComboToString(entry.combo)
      var bindItem = QTableWidgetItem.create(bindStr)
      bindItem.owned = false
      bindItem.setFlags(cint 0x21)
      QTableWidget(h: kbTableH, owned: false).setItem(row, cint 1, bindItem)

      # Col 2: "Set" button (single bindings only; chord bindings are fixed)
      if not entry.isChord:
        var setBtn = QPushButton.create("Set")
        setBtn.owned = false
        let setBtnH = setBtn.h
        let cmdId   = entry.id
        let changesRef = customChanges
        QAbstractButton(h: setBtnH, owned: false).onClicked do() {.raises: [].}:
          # Open a small key-capture dialog
          var capDlg = QDialog.create(QWidget(h: dialogH, owned: false))
          capDlg.owned = false
          let capDlgH = capDlg.h
          QWidget(h: capDlgH, owned: false).setWindowTitle("Set Keybinding")
          QWidget(h: capDlgH, owned: false).resize(cint 360, cint 130)

          var capLabel = QLabel.create("Command:  " & cmdId & "\n\nPress a key combination:")
          capLabel.owned = false

          var keyEdit = QKeySequenceEdit.create()
          keyEdit.owned = false
          let keyEditH = keyEdit.h

          var capBtns = QDialogButtonBox.create2(cint(1024 or 4194304))
          capBtns.owned = false
          capBtns.onAccepted do():
            QDialog(h: capDlgH, owned: false).accept()
          capBtns.onRejected do():
            QDialog(h: capDlgH, owned: false).reject()

          var capLayout = QVBoxLayout.create()
          capLayout.owned = false
          capLayout.addWidget(QWidget(h: capLabel.h,  owned: false))
          capLayout.addWidget(QWidget(h: keyEditH,    owned: false))
          capLayout.addWidget(QWidget(h: capBtns.h,   owned: false))
          QWidget(h: capDlgH, owned: false).setLayout(
            QLayout(h: capLayout.h, owned: false))

          if QDialog(h: capDlgH, owned: false).exec() == 1:
            # Take only the first key combo in case user entered multiple
            let rawStr = QKeySequenceEdit(h: keyEditH, owned: false).keySequence().toString()
            let newStr = rawStr.split(", ")[0]
            if newStr.len > 0:
              changesRef[][cmdId] = newStr
              let bi = QTableWidget(h: kbTableH, owned: false).item(row, cint 1)
              if bi.h != nil:
                bi.setText(newStr)

        QTableWidget(h: kbTableH, owned: false).setCellWidget(
          row, cint 2, QWidget(h: setBtnH, owned: false))

    # Keybindings tab layout
    var kbLayout = QVBoxLayout.create()
    kbLayout.owned = false
    kbLayout.addWidget(QWidget(h: kbTableH, owned: false), cint 1)
    QWidget(h: kbTabH, owned: false).setLayout(
      QLayout(h: kbLayout.h, owned: false))

    discard QTabWidget(h: tabsH, owned: false).addTab(
      QWidget(h: kbTabH, owned: false), "Keybindings")

    # ── Buttons ─────────────────────────────────────────────────────────────
    var buttons = QDialogButtonBox.create2(cint(1024 or 4194304))  # Ok | Cancel
    buttons.owned = false
    buttons.onAccepted do():
      QDialog(h: dialogH, owned: false).accept()
    buttons.onRejected do():
      QDialog(h: dialogH, owned: false).reject()

    # ── Content layout: tabs + buttons ──────────────────────────────────────
    var mainLayout = QVBoxLayout.create()
    mainLayout.owned = false
    mainLayout.addWidget(QWidget(h: tabsH,    owned: false), cint 1)
    mainLayout.addWidget(QWidget(h: buttons.h, owned: false), cint 0)

    QWidget(h: contentH, owned: false).setLayout(
      QLayout(h: mainLayout.h, owned: false))

    # Wrap contentWidget in a dialog-level VBox so it fills the dialog
    var dialogLayout = QVBoxLayout.create()
    dialogLayout.owned = false
    dialogLayout.setContentsMargins(cint 0, cint 0, cint 0, cint 0)
    dialogLayout.addWidget(QWidget(h: contentH, owned: false))
    QWidget(h: dialogH, owned: false).setLayout(
      QLayout(h: dialogLayout.h, owned: false))

    if QDialog(h: dialogH, owned: false).exec() == 1:  # Accepted
      var updated = current
      updated.appearance.themeMode =
        if themeModeCombo.currentIndex() == 1: Dark else: Light
      updated.appearance.font       = fontEdit.text()
      updated.appearance.fontSize   = int fontSizeSpin.value()
      updated.appearance.lineNumbers =
        QAbstractButton(h: lineNumbersCheck.h, owned: false).isChecked()
      updated.restoreLastSessionOnLaunch =
        QAbstractButton(h: restoreSessionCheck.h, owned: false).isChecked()
      updated.appearance.opacityEnabled =
        QAbstractButton(h: opacityCheck.h, owned: false).isChecked()
      updated.appearance.opacityLevel =
        int QAbstractSlider(h: opacitySlider.h, owned: false).value()
      let chosen = picker.currentThemeSelection()
      if chosen.len > 0:
        updated.appearance.syntaxTheme = chosen
      updated.keybindings = customChanges[].toOverrides()
      onApply(updated)
  except:
    discard
