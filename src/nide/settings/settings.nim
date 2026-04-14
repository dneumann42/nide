import commands
import nide/dialogs/[projectdialog, themedialog]
import nide/helpers/qtconst
import nide/settings/[keybindings, nimbleinstaller, projectconfig, settingsstore, theme, toolchain]
import nide/ui/[opacity, widgets]
import seaqt/[qabstractbutton, qabstractitemview, qabstractslider, qabstractspinbox, qcheckbox, qcombobox, qdialog, qdialogbuttonbox, qformlayout, qgraphicseffect, qgraphicsopacityeffect, qhboxlayout, qheaderview, qkeysequence, qkeysequenceedit, qlabel, qlayout, qlineedit, qlistwidget, qpushbutton, qradiobutton, qslider, qspinbox, qsplitter, qtableview, qtablewidget, qtabwidget, qvboxlayout, qwidget]
import std/[algorithm, os, osproc, strutils, tables]


const
  MinFontSize = cint 6
  MaxFontSize = cint 72
  MinEditorWheelScrollSpeed = cint 4
  MaxEditorWheelScrollSpeed = cint 40
  MinOpacity = cint 20
  MaxOpacity = cint 100
  OpacityStep = cint 5
  OpacityLabelMinWidth = cint 36
  KeybindDefaultColWidth = cint 150
  KeybindSourceColWidth = cint 80
  KeybindSetColWidth = cint 60
  KeyCaptureWidth = cint 360
  KeyCaptureHeight = cint 130
  FieldMinWidth = cint 280
  FormSpacing = cint 12
  TabMargin = cint 12

type
  AppearanceSettings* = object
    themeMode*: Theme
    transparent*: bool
    lineNumbers*: bool
    font* = "Fira Code"
    fontSize* = 14
    editorWheelScrollSpeed* = 10
    syntaxTheme* = "Monokai"
    opacityEnabled*: bool
    opacityLevel*:   int = 85

  KeybindingOverride* = object
    command*: string
    key*:     string

  NimEnvironmentMode* = enum
    InstallWithNimble
    CustomPath

  NimEnvironmentSettings* = object
    mode*: NimEnvironmentMode
    nimbleInstallPath*: string
    nimbleVersion*: string
    customNimPath*: string
    customNimblePath*: string

  Settings* = object
    appearance*:  AppearanceSettings
    restoreLastSessionOnLaunch*: bool
    keybindingScheme*: KeybindingScheme = VSCode
    keybindings*: seq[KeybindingOverride]
    nim*: NimEnvironmentSettings  ## user-defined overrides, e.g. {command: "editor.forwardChar", key: "Ctrl+T"}

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
  result.appearance.editorWheelScrollSpeed = settings.appearance.editorWheelScrollSpeed
  result.appearance.syntaxTheme = settings.appearance.syntaxTheme
  result.appearance.opacityEnabled = settings.appearance.opacityEnabled
  result.appearance.opacityLevel = settings.appearance.opacityLevel
  result.restoreLastSessionOnLaunch = settings.restoreLastSessionOnLaunch
  result.keybindingScheme = settings.keybindingScheme.toStored()
  result.keybindings = settings.keybindings.toStored()
  case settings.nim.mode
  of InstallWithNimble: result.nim.mode = "installWithNimble"
  of CustomPath: result.nim.mode = "customPath"
  result.nim.nimbleInstallPath = settings.nim.nimbleInstallPath
  result.nim.nimbleVersion = settings.nim.nimbleVersion
  result.nim.customNimPath = settings.nim.customNimPath
  result.nim.customNimblePath = settings.nim.customNimblePath

proc toRuntime(stored: StoredSettings): Settings =
  result = Settings()
  result.appearance.themeMode = parseStoredTheme(stored.appearance.themeMode)
  result.appearance.transparent = stored.appearance.transparent
  result.appearance.lineNumbers = stored.appearance.lineNumbers
  if stored.appearance.font.len > 0:
    result.appearance.font = stored.appearance.font
  if stored.appearance.fontSize > 0:
    result.appearance.fontSize = stored.appearance.fontSize
  if stored.appearance.editorWheelScrollSpeed > 0:
    result.appearance.editorWheelScrollSpeed = stored.appearance.editorWheelScrollSpeed
  if stored.appearance.syntaxTheme.len > 0:
    result.appearance.syntaxTheme = stored.appearance.syntaxTheme
  result.appearance.opacityEnabled = stored.appearance.opacityEnabled
  if stored.appearance.opacityLevel > 0:
    result.appearance.opacityLevel = stored.appearance.opacityLevel
  result.restoreLastSessionOnLaunch = stored.restoreLastSessionOnLaunch
  if stored.keybindingScheme.len > 0:
    result.keybindingScheme = parseKeybindingScheme(stored.keybindingScheme)
  result.keybindings = stored.keybindings.toRuntime()
  case stored.nim.mode
  of "installWithNimble": result.nim.mode = InstallWithNimble
  of "customPath": result.nim.mode = CustomPath
  else: result.nim.mode = InstallWithNimble
  if stored.nim.nimbleInstallPath.len > 0:
    result.nim.nimbleInstallPath = stored.nim.nimbleInstallPath
  else:
    result.nim.nimbleInstallPath = getHomeDir() / ".nimble" / "bin"
  if stored.nim.nimbleVersion.len > 0:
    result.nim.nimbleVersion = stored.nim.nimbleVersion
  else:
    result.nim.nimbleVersion = "2.2.6"
  result.nim.customNimPath = stored.nim.customNimPath
  result.nim.customNimblePath = stored.nim.customNimblePath

proc toTable*(overrides: seq[KeybindingOverride]): Table[string, string] =
  for o in overrides: result[o.command] = o.key

proc toOverrides*(t: Table[string, string]): seq[KeybindingOverride] =
  for cmd, key in t: result.add(KeybindingOverride(command: cmd, key: key))

proc load*(_: typedesc[Settings]): Settings {.raises: [].} =
  loadStoredSettings().toRuntime()

proc getNimPath*(settings: Settings): string =
  case settings.nim.mode
  of InstallWithNimble: settings.nim.nimbleInstallPath / nimExecutableName("nim")
  of CustomPath: settings.nim.customNimPath

proc getNimblePath*(settings: Settings): string =
  case settings.nim.mode
  of InstallWithNimble: settings.nim.nimbleInstallPath / nimExecutableName("nimble")
  of CustomPath: settings.nim.customNimblePath

proc findNimble*(): string {.raises: [].} =
  let nimbleBinDir = getHomeDir() / ".nimble" / "bin"
  for candidate in [
    nimbleBinDir / nimExecutableName("nimble"),
    "/usr/bin" / nimExecutableName("nimble"),
    "/usr/local/bin" / nimExecutableName("nimble")
  ]:
    if fileExists(candidate):
      return candidate
  try:
    let pathExe = findExe("nimble")
    if pathExe.len > 0:
      return pathExe
  except CatchableError:
    discard
  return ""

proc write*(settings: Settings) {.raises: [].} =
  writeStoredSettings(settings.toStored())

proc showSettingsDialog*(
  parent:           QWidget,
  current:          Settings,
  currentProjectRoot: string,
  currentProjectConfig: ProjectConfig,
  onApply:          proc(s: Settings, projectConfig: ProjectConfig) {.raises: [].}
) {.raises: [].} =
  try:
    var updated = current
    var updatedProjectConfig = currentProjectConfig
    var refreshResolvedToolchainLabels:
      proc() {.raises: [].} = nil

    proc applyChanges() {.raises: [].} =
      if refreshResolvedToolchainLabels != nil:
        refreshResolvedToolchainLabels()
      onApply(updated, updatedProjectConfig)

    var dialog = newWidget(QDialog.create(parent))
    let dialogH = dialog.h

    QWidget(h: dialogH, owned: false).setWindowTitle("Settings")
    QWidget(h: dialogH, owned: false).resize(cint 900, cint 600)
    # Content container — opacity effect goes on this child, not the dialog itself
    var contentWidget = newWidget(QWidget.create(QWidget(h: dialogH, owned: false)))
    let contentH = contentWidget.h
    let contentEff = setupWindowOpacity(
      QWidget(h: dialogH, owned: false),
      QWidget(h: contentH, owned: false),
      current.appearance.opacityEnabled,
      current.appearance.opacityLevel)
    let contentEffectH = contentEff.h

    # ── Tab widget ───────────────────────────────────────────────────────────
    var tabs = newWidget(QTabWidget.create(QWidget(h: contentH, owned: false)))
    let tabsH = tabs.h

    # ════════════════════════════════════════════════════════════════════════
    # Tab 1 — Appearance
    # ════════════════════════════════════════════════════════════════════════
    var appearTab = newWidget(QWidget.create(QWidget(h: tabsH, owned: false)))
    let appearTabH = appearTab.h

    # Theme mode (Light / Dark)
    var themeModeCombo = newWidget(QComboBox.create())
    themeModeCombo.addItem("Light")
    themeModeCombo.addItem("Dark")
    themeModeCombo.setCurrentIndex(
      if current.appearance.themeMode == Dark: cint 1 else: cint 0)

    # Font family
    var fontEdit = newWidget(QLineEdit.create())
    fontEdit.setText(current.appearance.font)
    fontEdit.setPlaceholderText("e.g. Fira Code, Monospace")

    # Font size
    var fontSizeSpin = newWidget(QSpinBox.create())
    fontSizeSpin.setMinimum(MinFontSize)
    fontSizeSpin.setMaximum(MaxFontSize)
    fontSizeSpin.setValue(cint current.appearance.fontSize)

    # Editor wheel scroll speed
    var editorWheelScrollSpeedSpin = newWidget(QSpinBox.create())
    editorWheelScrollSpeedSpin.setMinimum(MinEditorWheelScrollSpeed)
    editorWheelScrollSpeedSpin.setMaximum(MaxEditorWheelScrollSpeed)
    editorWheelScrollSpeedSpin.setValue(cint current.appearance.editorWheelScrollSpeed)

    # Line numbers toggle
    var lineNumbersCheck = checkbox("Show line numbers", current.appearance.lineNumbers)

    # Opacity checkbox
    var opacityCheck = checkbox("Enable opacity", current.appearance.opacityEnabled)

    var restoreSessionCheck = checkbox("Automatically restore last session on launch",
                                       current.restoreLastSessionOnLaunch)

    # Opacity slider — Qt::Horizontal = 1
    var opacitySlider = newWidget(QSlider.create(cint 1))
    opacitySlider.asWidget.setMinimumHeight(cint 24)
    QAbstractSlider(h: opacitySlider.h, owned: false).setMinimum(MinOpacity)
    QAbstractSlider(h: opacitySlider.h, owned: false).setMaximum(MaxOpacity)
    QAbstractSlider(h: opacitySlider.h, owned: false).setSingleStep(OpacityStep)
    QAbstractSlider(h: opacitySlider.h, owned: false).setValue(
      cint current.appearance.opacityLevel)
    QWidget(h: opacitySlider.h, owned: false).setEnabled(
      current.appearance.opacityEnabled)

    # Percentage label
    var opacityLabel = newWidget(QLabel.create($current.appearance.opacityLevel & "%"))
    opacityLabel.asWidget.setMinimumWidth(OpacityLabelMinWidth)

    # Wire checkbox → enable/disable slider + live preview
    let sliderH   = opacitySlider.h
    let labelH    = opacityLabel.h
    let checkH    = opacityCheck.h
    opacityCheck.onStateChanged do(state: cint) {.raises: [].}:
      let enabled = state != 0
      QWidget(h: sliderH, owned: false).setEnabled(enabled)
      let lvl = int QAbstractSlider(h: sliderH, owned: false).value()
      QGraphicsOpacityEffect(h: contentEffectH, owned: false).applyOpacity(enabled, lvl)
      updated.appearance.opacityEnabled = enabled
      applyChanges()

    # Wire slider → update label + live preview
    QAbstractSlider(h: opacitySlider.h, owned: false).onValueChanged do(v: cint) {.raises: [].}:
      QLabel(h: labelH, owned: false).setText($v & "%")
      let enabled = QAbstractButton(h: checkH, owned: false).isChecked()
      QGraphicsOpacityEffect(h: contentEffectH, owned: false).applyOpacity(enabled, int v)
      updated.appearance.opacityLevel = int v
      applyChanges()

    # Slider row
    var opacityRowLayout = hbox()
    opacityRowLayout.addWidget(opacitySlider.asWidget, cint 1)
    opacityRowLayout.addWidget(opacityLabel.asWidget, cint 0)

    # Form layout
    var form = newWidget(QFormLayout.create())
    form.setSpacing(FormSpacing)
    form.addRow("Theme mode",    themeModeCombo.asWidget)
    form.addRow("Font family",   fontEdit.asWidget)
    form.addRow("Font size",     fontSizeSpin.asWidget)
    form.addRow("Wheel scroll speed", editorWheelScrollSpeedSpin.asWidget)
    form.addRow("",              lineNumbersCheck.asWidget)
    form.addRow("",              restoreSessionCheck.asWidget)
    form.addRow("",              opacityCheck.asWidget)
    form.addRow("Opacity level", opacityRowLayout.asLayout())

    # Syntax theme picker
    var syntaxLabel = newWidget(QLabel.create("Syntax theme"))

    let picker = buildThemePickerWidget(
      QWidget(h: appearTabH, owned: false),
      current.appearance.syntaxTheme)

    QComboBox(h: themeModeCombo.h, owned: false).onCurrentIndexChanged do(
      idx: cint) {.raises: [].}:
      updated.appearance.themeMode = if idx == 1: Dark else: Light
      applyChanges()

    QLineEdit(h: fontEdit.h, owned: false).onEditingFinished do() {.raises: [].}:
      updated.appearance.font = fontEdit.text()
      applyChanges()

    fontSizeSpin.onValueChanged do(v: cint) {.raises: [].}:
      updated.appearance.fontSize = int v
      applyChanges()

    editorWheelScrollSpeedSpin.onValueChanged do(v: cint) {.raises: [].}:
      updated.appearance.editorWheelScrollSpeed = int v
      applyChanges()

    lineNumbersCheck.onStateChanged do(state: cint) {.raises: [].}:
      updated.appearance.lineNumbers = state != 0
      applyChanges()

    restoreSessionCheck.onStateChanged do(state: cint) {.raises: [].}:
      updated.restoreLastSessionOnLaunch = state != 0
      applyChanges()

    QListWidget(h: picker.listWidget.h, owned: false).onCurrentRowChanged do(
      row: cint) {.raises: [].}:
      if row >= 0 and row < cint(picker.themes.len):
        updated.appearance.syntaxTheme = picker.themes[row]
        applyChanges()

    # Appearance tab layout
    var appearLayout = vbox((TabMargin, TabMargin, TabMargin, TabMargin))
    appearLayout.addLayout(form.asLayout())
    appearLayout.addWidget(syntaxLabel.asWidget, cint 0)
    appearLayout.addWidget(picker.splitter.asWidget, cint 1)
    appearLayout.applyTo(QWidget(h: appearTabH, owned: false))

    discard QTabWidget(h: tabsH, owned: false).addTab(
      QWidget(h: appearTabH, owned: false), "Appearance")

    # ════════════════════════════════════════════════════════════════════════
    # Tab 2 — Keybindings
    # ════════════════════════════════════════════════════════════════════════
    var kbTab = newWidget(QWidget.create(QWidget(h: tabsH, owned: false)))
    let kbTabH = kbTab.h

    var keybindingSchemeCombo = newWidget(QComboBox.create())
    for scheme in KeybindingScheme:
      keybindingSchemeCombo.addItem(keybindingSchemeLabel(scheme))
    keybindingSchemeCombo.setCurrentIndex(
      if current.keybindingScheme == VSCode: cint 1 else: cint 0)

    var kbTable = newWidget(QTableWidget.create(cint 0, cint 5))
    let kbTableH = kbTable.h

    # Table configuration: no editing, select rows, no grid
    QAbstractItemView(h: kbTableH, owned: false).setEditTriggers(DD_NoEditTriggers)
    QAbstractItemView(h: kbTableH, owned: false).setSelectionBehavior(SB_SelectRows)
    QTableView(h: kbTableH, owned: false).setShowGrid(false)
    QTableWidget(h: kbTableH, owned: false).setHorizontalHeaderLabels(
      @["Command", "Binding", "Default", "Source", ""])
    let hdr = QTableView(h: kbTableH, owned: false).horizontalHeader()
    hdr.setStretchLastSection(false)
    hdr.setSectionResizeMode(cint 0, HR_ResizeToContents)
    hdr.setSectionResizeMode(cint 1, HR_ResizeToContents)
    hdr.setSectionResizeMode(cint 2, HR_Fixed)
    hdr.setSectionResizeMode(cint 3, HR_Fixed)
    hdr.setSectionResizeMode(cint 4, HR_Fixed)
    QHeaderView(h: hdr.h, owned: false).resizeSection(cint 2, KeybindDefaultColWidth)
    QHeaderView(h: hdr.h, owned: false).resizeSection(cint 3, KeybindSourceColWidth)
    QHeaderView(h: hdr.h, owned: false).resizeSection(cint 4, KeybindSetColWidth)
    let vhdr = QTableView(h: kbTableH, owned: false).verticalHeader()
    vhdr.asWidget.setVisible(false)

    # Track user's custom binding changes (starts as a copy of saved customs)
    var customChanges = new(Table[string, string])
    customChanges[] = current.keybindings.toTable()

    proc selectedKeybindingScheme(): KeybindingScheme {.raises: [].} =
      if keybindingSchemeCombo.currentIndex() == 1: VSCode else: Emacs

    proc refreshKeybindingsTable() {.raises: [].}

    proc applyKeybindingSchemeSelection() {.raises: [].} =
      updated.keybindingScheme = selectedKeybindingScheme()
      refreshKeybindingsTable()
      applyChanges()

    proc refreshKeybindingsTable() {.raises: [].} =
      var allBindings = defaultBindingList(selectedKeybindingScheme())
      allBindings.sort(proc(a, b: BindingEntry): int = cmp(a.id, b.id))

      let table = QTableWidget(h: kbTableH, owned: false)
      table.setRowCount(cint 0)
      table.clearContents()
      table.setRowCount(cint allBindings.len)

      for i, entry in allBindings:
        let row = cint i

        var idItem = newWidget(QTableWidgetItem.create(entry.id))
        idItem.setFlags(IF_SelectableEnabled)
        table.setItem(row, cint 0, idItem)

        var bindStr: string
        var defaultBindStr: string
        let customBinding = customChanges[].getOrDefault(entry.id, "")
        let isCustom = customBinding.len > 0
        if entry.combo.key == 0:
          defaultBindStr = ""
        elif entry.isChord and entry.chordPrefix.len > 0:
          defaultBindStr = entry.chordPrefix & " " & keyComboToString(entry.combo)
        else:
          defaultBindStr = keyComboToString(entry.combo)
        if customBinding.len > 0:
          bindStr = customBinding
        else:
          bindStr = defaultBindStr

        var bindItem = newWidget(QTableWidgetItem.create(bindStr))
        bindItem.setFlags(IF_SelectableEnabled)
        table.setItem(row, cint 1, bindItem)

        var defaultItem = newWidget(QTableWidgetItem.create(defaultBindStr))
        defaultItem.setFlags(IF_SelectableEnabled)
        table.setItem(row, cint 2, defaultItem)

        let sourceLabel =
          if isCustom: "User"
          else: "Default"
        var sourceItem = newWidget(QTableWidgetItem.create(sourceLabel))
        sourceItem.setFlags(IF_SelectableEnabled)
        table.setItem(row, cint 3, sourceItem)

        var setBtn = newWidget(QPushButton.create("Set"))
        let setBtnH = setBtn.h
        let cmdId = entry.id
        let changesRef = customChanges
        QAbstractButton(h: setBtnH, owned: false).onClicked do() {.raises: [].}:
          var capDlg = newWidget(QDialog.create(QWidget(h: dialogH, owned: false)))
          let capDlgH = capDlg.h
          QWidget(h: capDlgH, owned: false).setWindowTitle("Set Keybinding")
          QWidget(h: capDlgH, owned: false).resize(KeyCaptureWidth, KeyCaptureHeight)

          var capLabel = newWidget(QLabel.create("Command:  " & cmdId & "\n\nPress a key combination:"))

          var keyEdit = newWidget(QKeySequenceEdit.create())
          let keyEditH = keyEdit.h

          var capBtns = newWidget(QDialogButtonBox.create2(Btn_OkCancel))
          capBtns.onAccepted do():
            QDialog(h: capDlgH, owned: false).accept()
          capBtns.onRejected do():
            QDialog(h: capDlgH, owned: false).reject()

          var capLayout = vbox((cint 8, cint 8, cint 8, cint 8))
          capLayout.add(capLabel)
          capLayout.addWidget(QWidget(h: keyEditH, owned: false))
          capLayout.add(capBtns)
          capLayout.applyTo(QWidget(h: capDlgH, owned: false))

          if QDialog(h: capDlgH, owned: false).exec() == 1:
            let rawStr = QKeySequenceEdit(h: keyEditH, owned: false).keySequence().toString()
            let newStr = rawStr.split(", ")[0]
            if newStr.len > 0:
              changesRef[][cmdId] = newStr
              updated.keybindings = changesRef[].toOverrides()
              refreshKeybindingsTable()
              applyChanges()

        table.setCellWidget(row, cint 4, QWidget(h: setBtnH, owned: false))

    QComboBox(h: keybindingSchemeCombo.h, owned: false).onCurrentIndexChanged do(
      idx: cint) {.raises: [].}:
      discard idx
      applyKeybindingSchemeSelection()

    QComboBox(h: keybindingSchemeCombo.h, owned: false).onActivated do(
      idx: cint) {.raises: [].}:
      discard idx
      applyKeybindingSchemeSelection()

    refreshKeybindingsTable()

    # Keybindings tab layout
    var kbLayout = vbox((TabMargin, TabMargin, TabMargin, TabMargin))
    var kbForm = newWidget(QFormLayout.create())
    kbForm.setSpacing(FormSpacing)
    kbForm.addRow("Default keybindings", keybindingSchemeCombo.asWidget)
    kbLayout.addLayout(kbForm.asLayout())
    kbLayout.addWidget(QWidget(h: kbTableH, owned: false), cint 1)
    kbLayout.applyTo(QWidget(h: kbTabH, owned: false))

    discard QTabWidget(h: tabsH, owned: false).addTab(
      QWidget(h: kbTabH, owned: false), "Keybindings")

    # ════════════════════════════════════════════════════════════════════════
    # Tab 3 — Nim Environment
    # ════════════════════════════════════════════════════════════════════════
    var nimTab = newWidget(QWidget.create(QWidget(h: tabsH, owned: false)))
    let nimTabH = nimTab.h

    var installWithNimbleRadio = newWidget(QRadioButton.create("Install with Nimble"))
    var customPathRadio = newWidget(QRadioButton.create("Custom Path"))

    if current.nim.mode == InstallWithNimble:
      installWithNimbleRadio.asButton.setChecked(true)
    else:
      customPathRadio.asButton.setChecked(true)

    var nimbleInstallPathEdit = newWidget(QLineEdit.create())
    nimbleInstallPathEdit.setText(current.nim.nimbleInstallPath)
    nimbleInstallPathEdit.setPlaceholderText(getHomeDir() / ".nimble" / "bin")

    var nimbleVersionCombo = newWidget(QComboBox.create())
    nimbleVersionCombo.setMinimumWidth(FieldMinWidth)
    var availableVersions = getNimVersions()
    for ver in availableVersions:
      nimbleVersionCombo.addItem(ver)
    var defaultVersionIdx = 0
    for i, ver in availableVersions:
      if ver == current.nim.nimbleVersion:
        defaultVersionIdx = i
        break
    nimbleVersionCombo.setCurrentIndex(cint defaultVersionIdx)

    var customNimPathEdit = newWidget(QLineEdit.create())
    customNimPathEdit.setText(current.nim.customNimPath)
    customNimPathEdit.setPlaceholderText("e.g. /usr/bin/nim")

    var customNimblePathEdit = newWidget(QLineEdit.create())
    customNimblePathEdit.setText(current.nim.customNimblePath)
    customNimblePathEdit.setPlaceholderText("e.g. /usr/bin/nimble")

    var testButton = newWidget(QPushButton.create("Test"))

    var installNimbleButton = newWidget(QPushButton.create("Install Nimble"))
    var installButton = newWidget(QPushButton.create("Install Nim"))

    var testResultLabel = newWidget(QLabel.create(""))
    testResultLabel.asWidget.setMinimumHeight(cint 60)

    let nimbleInstallPathEditH = nimbleInstallPathEdit.h
    let nimbleVersionComboH = nimbleVersionCombo.h
    let customNimPathEditH = customNimPathEdit.h
    let customNimblePathEditH = customNimblePathEdit.h
    let installNimbleButtonH = installNimbleButton.h
    let installButtonH = installButton.h
    let testResultLabelH = testResultLabel.h
    let installWithNimbleRadioH = installWithNimbleRadio.h

    proc updateNimUIVisibility() {.raises: [].} =
      let isInstallMode = QAbstractButton(h: installWithNimbleRadioH, owned: false).isChecked()
      QWidget(h: nimbleInstallPathEditH, owned: false).setEnabled(isInstallMode)
      QWidget(h: nimbleVersionComboH, owned: false).setEnabled(isInstallMode)
      QWidget(h: installNimbleButtonH, owned: false).setEnabled(isInstallMode)
      QWidget(h: installButtonH, owned: false).setEnabled(isInstallMode)
      QWidget(h: customNimPathEditH, owned: false).setEnabled(not isInstallMode)
      QWidget(h: customNimblePathEditH, owned: false).setEnabled(not isInstallMode)

    updateNimUIVisibility()

    installWithNimbleRadio.onToggled do(checked: bool) {.raises: [].}:
      if checked:
        updateNimUIVisibility()
        updated.nim.mode = InstallWithNimble
        applyChanges()

    customPathRadio.onToggled do(checked: bool) {.raises: [].}:
      if checked:
        updateNimUIVisibility()
        updated.nim.mode = CustomPath
        applyChanges()

    QLineEdit(h: nimbleInstallPathEdit.h, owned: false).onEditingFinished do() {.raises: [].}:
      updated.nim.nimbleInstallPath = nimbleInstallPathEdit.text()
      applyChanges()

    QComboBox(h: nimbleVersionCombo.h, owned: false).onCurrentIndexChanged do(
      idx: cint) {.raises: [].}:
      discard idx
      updated.nim.nimbleVersion = nimbleVersionCombo.currentText()
      applyChanges()

    QLineEdit(h: customNimPathEdit.h, owned: false).onEditingFinished do() {.raises: [].}:
      updated.nim.customNimPath = customNimPathEdit.text()
      applyChanges()

    QLineEdit(h: customNimblePathEdit.h, owned: false).onEditingFinished do() {.raises: [].}:
      updated.nim.customNimblePath = customNimblePathEdit.text()
      applyChanges()

    testButton.onClicked do() {.raises: [].}:
      let isInstallMode = QAbstractButton(h: installWithNimbleRadioH, owned: false).isChecked()
      var configuredNimPath: string
      var configuredNimblePath: string

      if isInstallMode:
        let installPath = nimbleInstallPathEdit.text()
        if installPath.len > 0:
          configuredNimblePath = installPath / nimExecutableName("nimble")
          configuredNimPath = installPath / nimExecutableName("nim")
        else:
          configuredNimblePath = defaultNimbleInstallDir() / nimExecutableName("nimble")
          configuredNimPath = defaultNimbleInstallDir() / nimExecutableName("nim")
      else:
        configuredNimblePath = customNimblePathEdit.text()
        configuredNimPath = customNimPathEdit.text()

      var testNimPath = configuredNimPath
      var testNimblePath = configuredNimblePath
      var nimFromPath = false
      var nimbleFromPath = false

      if not (testNimPath.len > 0 and fileExists(testNimPath)):
        try:
          let foundNim = findExe("nim")
          if foundNim.len > 0:
            testNimPath = foundNim
            nimFromPath = true
        except CatchableError:
          discard

      if not (testNimblePath.len > 0 and fileExists(testNimblePath)):
        try:
          let foundNimble = findExe("nimble")
          if foundNimble.len > 0:
            testNimblePath = foundNimble
            nimbleFromPath = true
        except CatchableError:
          discard

      var results: string
      var hasError = false

      if testNimPath.len > 0 and fileExists(testNimPath):
        try:
          let (nimOut, nimCode) = execCmdEx(testNimPath & " --version 2>&1")
          if nimCode == 0:
            let source = if nimFromPath: " (from PATH)" else: ""
            results &= "nim: OK" & source & "\n" & nimOut.strip()
          else:
            results &= "nim: FAILED\n" & nimOut.strip()
            hasError = true
        except CatchableError:
          results &= "nim: FAILED\n"
          hasError = true
      else:
        results &= "nim: NOT FOUND\n"
        hasError = true

      if testNimblePath.len > 0 and fileExists(testNimblePath):
        try:
          let (nimbOut, nimbCode) = execCmdEx(testNimblePath & " --version 2>&1")
          if nimbCode == 0:
            let source = if nimbleFromPath: " (from PATH)" else: ""
            results &= "nimble: OK" & source & "\n" & nimbOut.strip()
          else:
            results &= "nimble: FAILED\n" & nimbOut.strip()
            hasError = true
        except CatchableError:
          results &= "nimble: FAILED\n"
          hasError = true
      else:
        results &= "nimble: NOT FOUND\n"
        hasError = true

      if hasError:
        QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #ff5555;'>" & results.replace("\n", "<br>") & "</span>")
      else:
        QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #50fa7b;'>" & results.replace("\n", "<br>") & "</span>")

    installNimbleButton.onClicked do() {.raises: [].}:
      QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #ffaa00;'>Installing latest Nimble...</span>")
      let installResult = installLatestNimble(nimbleInstallPathEdit.text())
      if installResult.ok:
        QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #50fa7b;'>" & installResult.message & "</span>")
      else:
        QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #ff5555;'>" & installResult.message & "</span>")

    installButton.onClicked do() {.raises: [].}:
      var nimbleExePath = findNimble()
      if nimbleExePath.len == 0:
        QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #ffaa00;'>Installing latest Nimble...</span>")
        let installResult = installLatestNimble(nimbleInstallPathEdit.text())
        if not installResult.ok:
          QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #ff5555;'>" & installResult.message & "</span>")
          return
        nimbleExePath = installResult.nimblePath

      let version = nimbleVersionCombo.currentText()
      QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #ffaa00;'>Installing Nim " & version & "...</span>")

      try:
        let (installOutput, installCode) = execCmdEx(nimbleExePath & " install -g nim@" & version & " 2>&1")
        if installCode == 0:
          QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #50fa7b;'>Nim " & version & " installed successfully!</span>")
        else:
          QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #ff5555;'>Failed to install Nim: " & installOutput & "</span>")
      except CatchableError:
        QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #ff5555;'>Failed to install Nim</span>")

    var nimForm = newWidget(QFormLayout.create())
    nimForm.setSpacing(FormSpacing)
    nimForm.addRow("", installWithNimbleRadio.asWidget)
    nimForm.addRow("Install path", nimbleInstallPathEdit.asWidget)
    nimForm.addRow("Nim version", nimbleVersionCombo.asWidget)
    nimForm.addRow("", customPathRadio.asWidget)
    nimForm.addRow("Nim path", customNimPathEdit.asWidget)
    nimForm.addRow("Nimble path", customNimblePathEdit.asWidget)

    var nimButtonLayout = hbox()
    nimButtonLayout.add(testButton)
    nimButtonLayout.add(installNimbleButton)
    nimButtonLayout.add(installButton)
    nimButtonLayout.addStretch(cint 1)

    var nimLayout = vbox((TabMargin, TabMargin, TabMargin, TabMargin))
    nimLayout.addLayout(nimForm.asLayout())
    nimLayout.addLayout(nimButtonLayout.asLayout())
    nimLayout.addWidget(testResultLabel.asWidget, cint 1)
    nimLayout.applyTo(QWidget(h: nimTabH, owned: false))

    discard QTabWidget(h: tabsH, owned: false).addTab(
      QWidget(h: nimTabH, owned: false), "Nim Environment")

    # ════════════════════════════════════════════════════════════════════════
    # Tab 4 — Project
    # ════════════════════════════════════════════════════════════════════════
    var projectTab = newWidget(QWidget.create(QWidget(h: tabsH, owned: false)))
    let projectTabH = projectTab.h

    let hasOpenProject = currentProjectRoot.len > 0
    let configPath =
      if hasOpenProject: projectConfigFilePath(currentProjectRoot)
      else: ".nide.json"

    var projectRootLabel = newWidget(QLabel.create(
      if hasOpenProject: currentProjectRoot else: "No project open"))
    projectRootLabel.setWordWrap(true)

    var projectConfigPathLabel = newWidget(QLabel.create(configPath))
    projectConfigPathLabel.setWordWrap(true)

    var useSystemNimCheck = checkbox(
      "Use system Nim for this project",
      currentProjectConfig.useSystemNim)

    let resolvedProjectToolchain = resolveProjectToolchain(
      getNimPath(current),
      getNimblePath(current),
      currentProjectRoot,
      currentProjectConfig
    )

    var resolvedSourceLabel = newWidget(QLabel.create(
      if hasOpenProject and currentProjectConfig.useSystemNim:
        "Using " & resolvedProjectToolchain.source
      elif hasOpenProject:
        "Using global settings"
      else:
        "No project open"
    ))
    resolvedSourceLabel.setWordWrap(true)

    var resolvedNimLabel = newWidget(QLabel.create(
      if resolvedProjectToolchain.nimCommand.len > 0:
        resolvedProjectToolchain.nimCommand
      else:
        "Not resolved"
    ))
    resolvedNimLabel.setWordWrap(true)

    var resolvedNimbleLabel = newWidget(QLabel.create(
      if resolvedProjectToolchain.nimbleCommand.len > 0:
        resolvedProjectToolchain.nimbleCommand
      else:
        "Not resolved"
    ))
    resolvedNimbleLabel.setWordWrap(true)

    var resolvedNimSuggestLabel = newWidget(QLabel.create(
      if resolvedProjectToolchain.nimsuggestCommand.len > 0:
        resolvedProjectToolchain.nimsuggestCommand
      else:
        "Not resolved"
    ))
    resolvedNimSuggestLabel.setWordWrap(true)

    refreshResolvedToolchainLabels = proc() {.raises: [].} =
      let resolved = resolveProjectToolchain(
        getNimPath(updated),
        getNimblePath(updated),
        currentProjectRoot,
        updatedProjectConfig
      )
      resolvedSourceLabel.setText(
        if hasOpenProject and updatedProjectConfig.useSystemNim:
          "Using " & resolved.source
        elif hasOpenProject:
          "Using global settings"
        else:
          "No project open"
      )
      resolvedNimLabel.setText(
        if resolved.nimCommand.len > 0:
          resolved.nimCommand
        else:
          "Not resolved"
      )
      resolvedNimbleLabel.setText(
        if resolved.nimbleCommand.len > 0:
          resolved.nimbleCommand
        else:
          "Not resolved"
      )
      resolvedNimSuggestLabel.setText(
        if resolved.nimsuggestCommand.len > 0:
          resolved.nimsuggestCommand
        else:
          "Not resolved"
      )

    var projectNimPathEdit = newWidget(QLineEdit.create())
    projectNimPathEdit.setText(currentProjectConfig.nimPath)
    projectNimPathEdit.setPlaceholderText("e.g. /nix/store/.../bin/nim")

    var projectNimblePathEdit = newWidget(QLineEdit.create())
    projectNimblePathEdit.setText(currentProjectConfig.nimblePath)
    projectNimblePathEdit.setPlaceholderText("e.g. /nix/store/.../bin/nimble")

    let useSystemNimCheckH = useSystemNimCheck.h
    let projectNimPathEditH = projectNimPathEdit.h
    let projectNimblePathEditH = projectNimblePathEdit.h

    proc updateProjectUIVisibility() {.raises: [].} =
      QWidget(h: useSystemNimCheckH, owned: false).setEnabled(hasOpenProject)
      let enableOverrides =
        hasOpenProject and QAbstractButton(h: useSystemNimCheckH, owned: false).isChecked()
      QWidget(h: projectNimPathEditH, owned: false).setEnabled(enableOverrides)
      QWidget(h: projectNimblePathEditH, owned: false).setEnabled(enableOverrides)

    updateProjectUIVisibility()

    useSystemNimCheck.onStateChanged do(state: cint) {.raises: [].}:
      discard state
      updateProjectUIVisibility()
      updatedProjectConfig.useSystemNim = useSystemNimCheck.asButton.isChecked()
      applyChanges()

    QLineEdit(h: projectNimPathEdit.h, owned: false).onEditingFinished do() {.raises: [].}:
      updatedProjectConfig.nimPath = projectNimPathEdit.text()
      applyChanges()

    QLineEdit(h: projectNimblePathEdit.h, owned: false).onEditingFinished do() {.raises: [].}:
      updatedProjectConfig.nimblePath = projectNimblePathEdit.text()
      applyChanges()

    var projectForm = newWidget(QFormLayout.create())
    projectForm.setSpacing(FormSpacing)
    projectForm.addRow("Project root", projectRootLabel.asWidget)
    projectForm.addRow("Config file", projectConfigPathLabel.asWidget)
    projectForm.addRow("", useSystemNimCheck.asWidget)
    projectForm.addRow("Nim path", projectNimPathEdit.asWidget)
    projectForm.addRow("Nimble path", projectNimblePathEdit.asWidget)
    projectForm.addRow("Resolved from", resolvedSourceLabel.asWidget)
    projectForm.addRow("Effective nim", resolvedNimLabel.asWidget)
    projectForm.addRow("Effective nimble", resolvedNimbleLabel.asWidget)
    projectForm.addRow("Effective nimsuggest", resolvedNimSuggestLabel.asWidget)

    var projectLayout = vbox((TabMargin, TabMargin, TabMargin, TabMargin))
    projectLayout.addLayout(projectForm.asLayout())
    projectLayout.addStretch(cint 1)
    projectLayout.applyTo(QWidget(h: projectTabH, owned: false))

    discard QTabWidget(h: tabsH, owned: false).addTab(
      QWidget(h: projectTabH, owned: false), "Project")

    # ── Buttons ─────────────────────────────────────────────────────────────
    var buttons = newWidget(QDialogButtonBox.create2(Btn_OkCancel))
    buttons.onAccepted do():
      QDialog(h: dialogH, owned: false).accept()
    buttons.onRejected do():
      QDialog(h: dialogH, owned: false).reject()

    # ── Content layout: tabs + buttons ──────────────────────────────────────
    var mainLayout = vbox((TabMargin, TabMargin, TabMargin, TabMargin))
    mainLayout.addWidget(QWidget(h: tabsH, owned: false), cint 1)
    mainLayout.add(buttons)
    mainLayout.applyTo(QWidget(h: contentH, owned: false))

    # Wrap contentWidget in a dialog-level VBox so it fills the dialog
    var dialogLayout = vbox((TabMargin, TabMargin, TabMargin, TabMargin))
    dialogLayout.addWidget(QWidget(h: contentH, owned: false))
    dialogLayout.applyTo(QWidget(h: dialogH, owned: false))

    discard QDialog(h: dialogH, owned: false).exec()
  except CatchableError:
    discard
