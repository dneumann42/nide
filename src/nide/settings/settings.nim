import seaqt/[qwidget, qdialog, qformlayout, qvboxlayout, qhboxlayout, qdialogbuttonbox,
              qlineedit, qcheckbox, qspinbox, qcombobox, qabstractbutton, qlabel,
              qabstractspinbox, qsplitter, qlayout, qslider, qabstractslider,
              qgraphicsopacityeffect, qgraphicseffect,
              qtabwidget, qtablewidget, qheaderview, qpushbutton, qkeysequenceedit,
              qkeysequence, qtableview, qabstractitemview, qradiobutton]
import std/[tables, algorithm, strutils, os, osproc]

import nide/settings/theme
import nide/dialogs/themedialog
import nide/ui/opacity
import nide/settings/settingsstore
import nide/dialogs/projectdialog
import commands
import nide/helpers/qtconst
import nide/ui/widgets

const
  MinFontSize = cint 6
  MaxFontSize = cint 72
  MinOpacity = cint 20
  MaxOpacity = cint 100
  OpacityStep = cint 5
  OpacityLabelMinWidth = cint 36
  KeybindSetColWidth = cint 60
  KeyCaptureWidth = cint 360
  KeyCaptureHeight = cint 130
  NimbleVersion* = "v0.22.3"
  FieldMinWidth = cint 280

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
  result.appearance.syntaxTheme = settings.appearance.syntaxTheme
  result.appearance.opacityEnabled = settings.appearance.opacityEnabled
  result.appearance.opacityLevel = settings.appearance.opacityLevel
  result.restoreLastSessionOnLaunch = settings.restoreLastSessionOnLaunch
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
  if stored.appearance.syntaxTheme.len > 0:
    result.appearance.syntaxTheme = stored.appearance.syntaxTheme
  result.appearance.opacityEnabled = stored.appearance.opacityEnabled
  if stored.appearance.opacityLevel > 0:
    result.appearance.opacityLevel = stored.appearance.opacityLevel
  result.restoreLastSessionOnLaunch = stored.restoreLastSessionOnLaunch
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
  of InstallWithNimble: settings.nim.nimbleInstallPath / "nim"
  of CustomPath: settings.nim.customNimPath

proc getNimblePath*(settings: Settings): string =
  case settings.nim.mode
  of InstallWithNimble: settings.nim.nimbleInstallPath / "nimble"
  of CustomPath: settings.nim.customNimblePath

proc findNimble*(): string {.raises: [].} =
  let nimbleBinDir = getHomeDir() / ".nimble" / "bin"
  for candidate in [nimbleBinDir / "nimble", "/usr/bin/nimble", "/usr/local/bin/nimble"]:
    if fileExists(candidate):
      return candidate
  try:
    let pathExe = findExe("nimble")
    if pathExe.len > 0:
      return pathExe
  except:
    discard
  return ""

proc write*(settings: Settings) {.raises: [].} =
  writeStoredSettings(settings.toStored())

proc showSettingsDialog*(
  parent:           QWidget,
  current:          Settings,
  onApply:          proc(s: Settings) {.raises: [].},
  onOpacityPreview: proc(enabled: bool, level: int) {.raises: [].} = nil
) {.raises: [].} =
  try:
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
    var opacityRowLayout = hbox()
    opacityRowLayout.addWidget(opacitySlider.asWidget, cint 1)
    opacityRowLayout.addWidget(opacityLabel.asWidget, cint 0)

    # Form layout
    var form = newWidget(QFormLayout.create())
    form.addRow("Theme mode",    themeModeCombo.asWidget)
    form.addRow("Font family",   fontEdit.asWidget)
    form.addRow("Font size",     fontSizeSpin.asWidget)
    form.addRow("",              lineNumbersCheck.asWidget)
    form.addRow("",              restoreSessionCheck.asWidget)
    form.addRow("",              opacityCheck.asWidget)
    form.addRow("Opacity level", opacityRowLayout.asLayout())

    # Syntax theme picker
    var syntaxLabel = newWidget(QLabel.create("Syntax theme"))

    let picker = buildThemePickerWidget(
      QWidget(h: appearTabH, owned: false),
      current.appearance.syntaxTheme)

    # Appearance tab layout
    var appearLayout = vbox()
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

    # Build sorted list of all default bindings
    var allBindings = defaultBindingList()
    allBindings.sort(proc(a, b: BindingEntry): int = cmp(a.id, b.id))

    var kbTable = newWidget(QTableWidget.create(cint allBindings.len, cint 3))
    let kbTableH = kbTable.h

    # Table configuration: no editing, select rows, no grid
    QAbstractItemView(h: kbTableH, owned: false).setEditTriggers(DD_NoEditTriggers)
    QAbstractItemView(h: kbTableH, owned: false).setSelectionBehavior(SB_SelectRows)
    QTableView(h: kbTableH, owned: false).setShowGrid(false)
    QTableWidget(h: kbTableH, owned: false).setHorizontalHeaderLabels(
      @["Command", "Binding", ""])
    let hdr = QTableView(h: kbTableH, owned: false).horizontalHeader()
    hdr.setStretchLastSection(false)
    hdr.setSectionResizeMode(cint 0, HR_ResizeToContents)
    hdr.setSectionResizeMode(cint 1, HR_ResizeToContents)
    hdr.setSectionResizeMode(cint 2, HR_Fixed)
    QHeaderView(h: hdr.h, owned: false).resizeSection(cint 2, KeybindSetColWidth)
    let vhdr = QTableView(h: kbTableH, owned: false).verticalHeader()
    vhdr.asWidget.setVisible(false)

    # Track user's custom binding changes (starts as a copy of saved customs)
    var customChanges = new(Table[string, string])
    customChanges[] = current.keybindings.toTable()

    for i, entry in allBindings:
      let row = cint i

      # Col 0: command id — read-only
      var idItem = newWidget(QTableWidgetItem.create(entry.id))
      idItem.setFlags(IF_SelectableEnabled)
      QTableWidget(h: kbTableH, owned: false).setItem(row, cint 0, idItem)

      # Col 1: current binding string — read-only
      var bindStr: string
      if customChanges[].hasKey(entry.id):
        bindStr = customChanges[][entry.id]
      elif entry.isChord and entry.chordPrefix.len > 0:
        bindStr = entry.chordPrefix & " " & keyComboToString(entry.combo)
      else:
        bindStr = keyComboToString(entry.combo)
      var bindItem = newWidget(QTableWidgetItem.create(bindStr))
      bindItem.setFlags(IF_SelectableEnabled)
      QTableWidget(h: kbTableH, owned: false).setItem(row, cint 1, bindItem)

      # Col 2: "Set" button (all bindings)
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

        var capLayout = vbox()
        capLayout.add(capLabel)
        capLayout.addWidget(QWidget(h: keyEditH, owned: false))
        capLayout.add(capBtns)
        capLayout.applyTo(QWidget(h: capDlgH, owned: false))

        if QDialog(h: capDlgH, owned: false).exec() == 1:
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
    var kbLayout = vbox()
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

    var installButton = newWidget(QPushButton.create("Install Nim"))

    var testResultLabel = newWidget(QLabel.create(""))
    testResultLabel.asWidget.setMinimumHeight(cint 60)

    let nimbleInstallPathEditH = nimbleInstallPathEdit.h
    let nimbleVersionComboH = nimbleVersionCombo.h
    let customNimPathEditH = customNimPathEdit.h
    let customNimblePathEditH = customNimblePathEdit.h
    let testButtonH = testButton.h
    let installButtonH = installButton.h
    let testResultLabelH = testResultLabel.h
    let installWithNimbleRadioH = installWithNimbleRadio.h
    let customPathRadioH = customPathRadio.h

    proc updateNimUIVisibility() {.raises: [].} =
      let isInstallMode = QAbstractButton(h: installWithNimbleRadioH, owned: false).isChecked()
      QWidget(h: nimbleInstallPathEditH, owned: false).setEnabled(isInstallMode)
      QWidget(h: nimbleVersionComboH, owned: false).setEnabled(isInstallMode)
      QWidget(h: installButtonH, owned: false).setEnabled(isInstallMode)
      QWidget(h: customNimPathEditH, owned: false).setEnabled(not isInstallMode)
      QWidget(h: customNimblePathEditH, owned: false).setEnabled(not isInstallMode)

    updateNimUIVisibility()

    installWithNimbleRadio.onToggled do(checked: bool) {.raises: [].}:
      if checked:
        updateNimUIVisibility()

    customPathRadio.onToggled do(checked: bool) {.raises: [].}:
      if checked:
        updateNimUIVisibility()

    testButton.onClicked do() {.raises: [].}:
      let isInstallMode = QAbstractButton(h: installWithNimbleRadioH, owned: false).isChecked()
      var configuredNimPath: string
      var configuredNimblePath: string

      if isInstallMode:
        let installPath = nimbleInstallPathEdit.text()
        if installPath.len > 0:
          configuredNimblePath = installPath / "nimble"
          configuredNimPath = installPath / "nim"
        else:
          configuredNimblePath = getHomeDir() / ".nimble" / "bin" / "nimble"
          configuredNimPath = getHomeDir() / ".nimble" / "bin" / "nim"
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
        except:
          discard

      if not (testNimblePath.len > 0 and fileExists(testNimblePath)):
        try:
          let foundNimble = findExe("nimble")
          if foundNimble.len > 0:
            testNimblePath = foundNimble
            nimbleFromPath = true
        except:
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
        except:
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
        except:
          results &= "nimble: FAILED\n"
          hasError = true
      else:
        results &= "nimble: NOT FOUND\n"
        hasError = true

      if hasError:
        QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #ff5555;'>" & results.replace("\n", "<br>") & "</span>")
      else:
        QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #50fa7b;'>" & results.replace("\n", "<br>") & "</span>")

    installButton.onClicked do() {.raises: [].}:
      let installPath = nimbleInstallPathEdit.text()
      let targetDir = if installPath.len > 0: installPath else: getHomeDir() / ".nimble" / "bin"
      let installNimblePath = targetDir / "nimble"

      if not dirExists(targetDir):
        try:
          createDir(targetDir)
        except:
          QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #ff5555;'>Failed to create directory</span>")
          return

      var nimbleExePath = findNimble()
      if nimbleExePath.len == 0:
        QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #ffaa00;'>Downloading nimble...</span>")

        let nimbleUrl = "https://github.com/nim-lang/nimble/releases/download/" & NimbleVersion & "/nimble-" & NimbleVersion & "-"
        var downloadUrl: string
        when defined(windows):
          downloadUrl = nimbleUrl & "x86_64-pc-windows.zip"
        elif defined(macosx):
          downloadUrl = nimbleUrl & "x86_64-unknown_darwin.tar.gz"
        else:
          downloadUrl = nimbleUrl & "x86_64-linux.tar.gz"

        try:
          let (output, code) = execCmdEx("curl -fsSL -o /tmp/nimble.tar.gz " & downloadUrl & " 2>&1")
          if code != 0:
            QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #ff5555;'>Failed to download nimble: " & output & "</span>")
            return
        except:
          QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #ff5555;'>Failed to download nimble</span>")
          return

        try:
          let (extractOutput, extractCode) = execCmdEx("tar -xzf /tmp/nimble.tar.gz -C " & targetDir & " --strip-components=1 2>&1")
          if extractCode != 0:
            QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #ff5555;'>Failed to extract nimble: " & extractOutput & "</span>")
            return
        except:
          QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #ff5555;'>Failed to extract nimble</span>")
          return

        nimbleExePath = installNimblePath
        QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #50fa7b;'>Nimble downloaded successfully</span><br>")

      let version = nimbleVersionCombo.currentText()
      QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #ffaa00;'>Installing Nim " & version & "...</span>")

      try:
        let (installOutput, installCode) = execCmdEx(nimbleExePath & " install -g nim@" & version & " 2>&1")
        if installCode == 0:
          QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #50fa7b;'>Nim " & version & " installed successfully!</span>")
        else:
          QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #ff5555;'>Failed to install Nim: " & installOutput & "</span>")
      except:
        QLabel(h: testResultLabelH, owned: false).setText("<span style='color: #ff5555;'>Failed to install Nim</span>")

    var nimForm = newWidget(QFormLayout.create())
    nimForm.addRow("", installWithNimbleRadio.asWidget)
    nimForm.addRow("Install path", nimbleInstallPathEdit.asWidget)
    nimForm.addRow("Nim version", nimbleVersionCombo.asWidget)
    nimForm.addRow("", customPathRadio.asWidget)
    nimForm.addRow("Nim path", customNimPathEdit.asWidget)
    nimForm.addRow("Nimble path", customNimblePathEdit.asWidget)

    var nimButtonLayout = hbox()
    nimButtonLayout.add(testButton)
    nimButtonLayout.add(installButton)
    nimButtonLayout.addStretch(cint 1)

    var nimLayout = vbox()
    nimLayout.addLayout(nimForm.asLayout())
    nimLayout.addLayout(nimButtonLayout.asLayout())
    nimLayout.addWidget(testResultLabel.asWidget, cint 1)
    nimLayout.applyTo(QWidget(h: nimTabH, owned: false))

    discard QTabWidget(h: tabsH, owned: false).addTab(
      QWidget(h: nimTabH, owned: false), "Nim Environment")

    # ── Buttons ─────────────────────────────────────────────────────────────
    var buttons = newWidget(QDialogButtonBox.create2(Btn_OkCancel))
    buttons.onAccepted do():
      QDialog(h: dialogH, owned: false).accept()
    buttons.onRejected do():
      QDialog(h: dialogH, owned: false).reject()

    # ── Content layout: tabs + buttons ──────────────────────────────────────
    var mainLayout = vbox()
    mainLayout.addWidget(QWidget(h: tabsH, owned: false), cint 1)
    mainLayout.add(buttons)
    mainLayout.applyTo(QWidget(h: contentH, owned: false))

    # Wrap contentWidget in a dialog-level VBox so it fills the dialog
    var dialogLayout = vbox()
    dialogLayout.addWidget(QWidget(h: contentH, owned: false))
    dialogLayout.applyTo(QWidget(h: dialogH, owned: false))

    if QDialog(h: dialogH, owned: false).exec() == 1:  # Accepted
      var updated = current
      updated.appearance.themeMode =
        if themeModeCombo.currentIndex() == 1: Dark else: Light
      updated.appearance.font       = fontEdit.text()
      updated.appearance.fontSize   = int fontSizeSpin.value()
      updated.appearance.lineNumbers = lineNumbersCheck.asButton.isChecked()
      updated.restoreLastSessionOnLaunch = restoreSessionCheck.asButton.isChecked()
      updated.appearance.opacityEnabled = opacityCheck.asButton.isChecked()
      updated.appearance.opacityLevel =
        int QAbstractSlider(h: opacitySlider.h, owned: false).value()
      let chosen = picker.currentThemeSelection()
      if chosen.len > 0:
        updated.appearance.syntaxTheme = chosen
      updated.keybindings = customChanges[].toOverrides()
      if installWithNimbleRadio.asButton.isChecked():
        updated.nim.mode = InstallWithNimble
      else:
        updated.nim.mode = CustomPath
      updated.nim.nimbleInstallPath = nimbleInstallPathEdit.text()
      updated.nim.nimbleVersion = nimbleVersionCombo.currentText()
      updated.nim.customNimPath = customNimPathEdit.text()
      updated.nim.customNimblePath = customNimblePathEdit.text()
      onApply(updated)
  except:
    discard
