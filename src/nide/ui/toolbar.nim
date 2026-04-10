import std/[tables, strutils]
import seaqt/[qtoolbar, qtoolbutton, qmenu, qwidget, qlayout, qaction, qapplication,
              qabstractbutton, qsize, qicon, qlabel, qhboxlayout, qpushbutton, qpoint,
              qscrollarea, qvboxlayout, qscroller]
import nide/ui/widgets
import nide/helpers/logparser
import nide/helpers/qtconst, nide/helpers/uicolors

const RunSvg       = staticRead("icons/run.svg")
const BuildSvg     = staticRead("icons/build.svg")
const GearSvg      = staticRead("icons/gear.svg")
const FileTreeSvg  = staticRead("icons/filetree.svg")
const GraphSvg     = staticRead("icons/graph.svg")
const LoadingSvg   = staticRead("icons/loading.svg")
const NimSvg       = staticRead("../../res/Nim_logo.svg")

const
  ToolbarIconSize = cint 12
  ToolbarHeight = cint 28
  ToolbarSpacing = cint 2
  DiagBtnFontSize = "11px"
  PopupYOffset = cint 24
  MaxPopupHeight = cint 400


type
  ToolMenuId* = enum
    NewModule
    OpenModule
    OpenFile
    NewProject
    SaveProject
    OpenProject
    CloseProject
    Quit
    SyntaxTheme
    RestartNimSuggest
    JumpBack
    JumpForward
    CleanImports
    RefreshDiags

  ToolMenu* = ref object
    label: string
    button: QToolButton
    menu: QMenu
    actions: Table[ToolMenuId, QAction]

  Toolbar* = ref object
    toolbar: QToolbar
    fileMenu: ToolMenu
    viewMenu: ToolMenu
    nimMenu: ToolMenu
    projectLabel: QLabel
    newPaneBtn: QToolButton
    fileTreeBtn: QToolButton
    graphBtn: QToolButton
    runBtn: QToolButton
    buildBtn: QToolButton
    settingsBtn: QToolButton
    loaderLabel: QLabel
    diagWidget: QWidget
    diagAction: QAction
    diagHintBtn: QToolButton
    diagWarnBtn: QToolButton
    diagErrBtn: QToolButton
    diagNavigateCb: proc(path: string, line, col: int) {.raises: [].}

proc build(self: ToolMenu) =
  self.button = QToolButton.create()
  self.button.setText(self.label)

  self.menu = QMenu.create()

  self.button.setMenu(self.menu)
  self.button.setPopupMode(QToolButtonToolButtonPopupModeEnum.InstantPopup)

proc widget*(self: Toolbar): lent QWidget =
  result = self.toolbar

proc onTriggered*(
  self: Toolbar,
  event: ToolMenuId,
  triggered: proc(): void {.raises: [].}
) =
  if event in self.fileMenu.actions:
    self.fileMenu.actions[event].onTriggered(triggered)
  elif event in self.viewMenu.actions:
    self.viewMenu.actions[event].onTriggered(triggered)
  elif event in self.nimMenu.actions:
    self.nimMenu.actions[event].onTriggered(triggered)

proc setCloseProjectVisible*(self: Toolbar, visible: bool) {.raises: [].} =
  try:
    self.fileMenu.actions[CloseProject].setVisible(visible)
  except KeyError:
    discard

proc buildFileMenu(self: Toolbar) =
  self.fileMenu = ToolMenu(label: "File")
  self.fileMenu.build()

  self.fileMenu.actions[NewModule] = self.fileMenu.menu.addAction("New Module")
  self.fileMenu.actions[OpenModule] = self.fileMenu.menu.addAction("Open Module")
  self.fileMenu.actions[OpenFile] = self.fileMenu.menu.addAction("Open File")

  self.fileMenu.actions[NewProject] = self.fileMenu.menu.addAction("New Project")
  self.fileMenu.actions[OpenProject] = self.fileMenu.menu.addAction("Open Project")
  self.fileMenu.actions[CloseProject] = self.fileMenu.menu.addAction("Close Project")

  discard self.fileMenu.menu.addSeparator()
  self.fileMenu.actions[Quit] = self.fileMenu.menu.addAction("Quit")

  discard self.toolbar.addWidget(self.fileMenu.button)

proc buildViewMenu(self: Toolbar) =
  self.viewMenu = ToolMenu(label: "View")
  self.viewMenu.build()

  self.viewMenu.actions[SyntaxTheme] = self.viewMenu.menu.addAction("Syntax Theme...")

  discard self.toolbar.addWidget(self.viewMenu.button)

proc buildNimMenu(self: Toolbar) =
  self.nimMenu = ToolMenu(label: "Nim")
  self.nimMenu.build()

  self.nimMenu.actions[JumpBack] = self.nimMenu.menu.addAction("Jump Back")
  self.nimMenu.actions[JumpForward] = self.nimMenu.menu.addAction("Jump Forward")
  self.nimMenu.actions[RestartNimSuggest] = self.nimMenu.menu.addAction("Restart nimsuggest")
  discard self.nimMenu.menu.addSeparator()
  self.nimMenu.actions[CleanImports] = self.nimMenu.menu.addAction("Clean Imports")
  self.nimMenu.actions[RefreshDiags] = self.nimMenu.menu.addAction("Refresh Diagnostics")

  discard self.toolbar.addWidget(self.nimMenu.button)

proc build*(self: Toolbar) =
  self.toolbar = QToolbar.create()
  self.toolbar.setMovable(false)
  self.toolbar.setIconSize(QSize.create(ToolbarIconSize, ToolbarIconSize))
  QWidget(h: self.toolbar.h, owned: false).setContentsMargins(cint 0, cint 0, cint 0, cint 0)
  QWidget(h: self.toolbar.h, owned: false).setFixedHeight(ToolbarHeight)
  let tbLayout = QWidget(h: self.toolbar.h, owned: false).layout()
  tbLayout.setContentsMargins(cint 0, cint 0, cint 0, cint 0)
  tbLayout.setSpacing(ToolbarSpacing)

  var chipWidget = newWidget(QWidget.create())
  chipWidget.setStyleSheet(
    "QWidget { background: " & clChipBg & "; color: " & clChipText & "; border-radius: 4px; padding: 2px 6px; }")

  var chipLayout = hbox(margins = (cint 2, cint 0, cint 2, cint 0), spacing = cint 4)
  chipLayout.applyTo(chipWidget)

  self.projectLabel = label("—")
  chipLayout.add(self.projectLabel)

  self.loaderLabel = label()
  self.loaderLabel.setPixmap(svgIcon(NimSvg, ToolbarIconSize).pixmap(ToolbarIconSize, ToolbarIconSize))
  chipLayout.add(self.loaderLabel)

  discard self.toolbar.addWidget(chipWidget)

  self.fileTreeBtn = makeIconButton(FileTreeSvg, ToolbarIconSize)
  self.fileTreeBtn.asWidget.setEnabled(false)
  discard self.toolbar.addWidget(self.fileTreeBtn)

  self.graphBtn = makeIconButton(GraphSvg, ToolbarIconSize)
  discard self.toolbar.addWidget(self.graphBtn)

  self.buildFileMenu()
  self.buildViewMenu()
  self.buildNimMenu()

  block:
    var spacer = newWidget(QWidget.create())
    spacer.setSizePolicy(SP_Expanding, SP_Preferred)
    discard self.toolbar.addWidget(spacer)

  self.diagWidget = newWidget(QWidget.create())
  var diagLayout = hbox(spacing = ToolbarSpacing)
  diagLayout.applyTo(self.diagWidget)

  self.diagHintBtn = newWidget(QToolButton.create())
  diagLayout.add(self.diagHintBtn)

  self.diagWarnBtn = newWidget(QToolButton.create())
  diagLayout.add(self.diagWarnBtn)

  self.diagErrBtn = newWidget(QToolButton.create())
  diagLayout.add(self.diagErrBtn)

  self.diagAction = newWidget(self.toolbar.addWidget(self.diagWidget))
  self.diagAction.setVisible(false)

  self.runBtn = makeIconButton(RunSvg, ToolbarIconSize)
  discard self.toolbar.addWidget(self.runBtn)

  self.buildBtn = makeIconButton(BuildSvg, ToolbarIconSize)
  discard self.toolbar.addWidget(self.buildBtn)

  self.settingsBtn = makeIconButton(GearSvg, ToolbarIconSize)
  discard self.toolbar.addWidget(self.settingsBtn)

proc setProjectName*(self: Toolbar, name: string) =
  self.projectLabel.setText(name)

proc onRun*(self: Toolbar, triggered: proc() {.raises: [].}) =
  self.runBtn.onClicked(triggered)

proc onBuild*(self: Toolbar, triggered: proc() {.raises: [].}) =
  self.buildBtn.onClicked(triggered)

proc onGraph*(self: Toolbar, triggered: proc() {.raises: [].}) =
  self.graphBtn.onClicked(triggered)

proc onSettings*(self: Toolbar, triggered: proc() {.raises: [].}) =
  self.settingsBtn.onCLicked(triggered)

proc onNewPane*(self: Toolbar, triggered: proc() {.raises: [].}) =
  self.newPaneBtn.onClicked(triggered)

proc setFileTreeEnabled*(self: Toolbar, enabled: bool) =
  self.fileTreeBtn.asWidget.setEnabled(enabled)

proc setFileTreeIconColor*(self: Toolbar, color: string) =
  self.fileTreeBtn.asButton.setIcon(svgIcon(FileTreeSvg, ToolbarIconSize, color))

proc onFileTreeToggle*(self: Toolbar, triggered: proc() {.raises: [].}) =
  self.fileTreeBtn.onClicked(triggered)

proc setLoading*(self: Toolbar, loading: bool) =
  if loading:
    self.loaderLabel.setPixmap(svgIcon(LoadingSvg, ToolbarIconSize).pixmap(ToolbarIconSize, ToolbarIconSize))
  else:
    self.loaderLabel.setPixmap(svgIcon(NimSvg, ToolbarIconSize).pixmap(ToolbarIconSize, ToolbarIconSize))

proc updateDiagCounts*(self: Toolbar, lines: seq[LogLine]) {.raises: [].} =
  var hintCount = 0
  var warnCount = 0
  var errCount = 0
  for ll in lines:
    case ll.level
    of llHint: inc hintCount
    of llWarning: inc warnCount
    of llError: inc errCount
    else: discard

  var anyDiag = hintCount > 0 or warnCount > 0 or errCount > 0

  try:
    self.diagAction.setVisible(anyDiag)

    if hintCount > 0:
      self.diagHintBtn.setText("◆" & $hintCount)
      self.diagHintBtn.asWidget.setStyleSheet("QToolButton { color: #00cccc; background: transparent; border: none; font-size: " & DiagBtnFontSize & "; }")
      self.diagHintBtn.asWidget.show()
    else:
      self.diagHintBtn.asWidget.hide()
    if warnCount > 0:
      self.diagWarnBtn.setText("⚠" & $warnCount)
      self.diagWarnBtn.asWidget.setStyleSheet("QToolButton { color: " & clYellow & "; background: transparent; border: none; font-size: " & DiagBtnFontSize & "; }")
      self.diagWarnBtn.asWidget.show()
    else:
      self.diagWarnBtn.asWidget.hide()
    if errCount > 0:
      self.diagErrBtn.setText("✗" & $errCount)
      self.diagErrBtn.asWidget.setStyleSheet("QToolButton { color: " & clRed & "; background: transparent; border: none; font-size: " & DiagBtnFontSize & "; }")
      self.diagErrBtn.asWidget.show()
    else:
      self.diagErrBtn.asWidget.hide()
  except CatchableError: discard

proc showDiagPopover*(self: Toolbar, parentH: pointer, lines: seq[LogLine], filterLevel: LogLevel) {.raises: [].} =
  if lines.len == 0: return
  try:
    var popover = newWidget(QWidget.create())
    popover.setWindowFlags(WF_PopupFrameless)
    popover.setObjectName("diagPopover")
    popover.setStyleSheet(
      "QWidget#diagPopover { background: " & clBase & "; border: 1px solid " & clSurface2 & "; border-radius: 4px; } " &
      "QScrollArea { background: transparent; border: none; } " &
      "QScrollBar:vertical { background: " & clSurface0 & "; width: 8px; border-radius: 4px; } " &
      "QScrollBar::handle:vertical { background: " & clSurface2 & "; border-radius: 4px; min-height: 20px; } " &
      "QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0px; } " &
      "QLabel { color: " & clText & "; font-family: 'Fira Code', monospace; font-size: 12px; background: transparent; }"
    )

    var scroll = newWidget(QScrollArea.create(popover))
    scroll.setWidgetResizable(true)
    scroll.setHorizontalScrollBarPolicy(SBP_AlwaysOff)

    var listW = newWidget(QWidget.create(scroll))
    var listLayout = vbox(margins = (cint 4, cint 4, cint 4, cint 4), spacing = cint 2)
    listLayout.applyTo(listW)

    QScrollArea(h: scroll.h, owned: false).setWidget(listW)
    var popoverLayout = vbox()
    popoverLayout.add(scroll)
    popoverLayout.applyTo(popover)

    for ll in lines:
      if ll.level != filterLevel: continue
      let (label, color) = case ll.level
        of llError:   ("Error",   clRed)
        of llWarning: ("Warning", clYellow)
        of llHint:    ("Hint",    "#00cccc")
        else: continue
      let escaped = ll.raw.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
      let text = label & ": " & escaped & " (" & ll.file & " line " & $ll.line & ")"
      let filePath    = ll.file
      let lineNum     = ll.line
      let lineCol     = ll.col
      let navigateCb  = self.diagNavigateCb

      var itemBtn = button(text)
      itemBtn.setStyleSheet(
        "QPushButton { color: " & clText & "; background: transparent; border: none; text-align: left; padding: 6px 8px; font-family: 'Fira Code', monospace; font-size: 12px; }" &
        "QPushButton:hover { background: " & clSurface0 & "; }")
      itemBtn.onClicked do() {.raises: [].}:
        popover.hide()
        if navigateCb != nil:
          navigateCb(filePath, lineNum, lineCol)
      listLayout.add(itemBtn)

    if listLayout.count() == 0:
      return

    popover.adjustSize()
    let pw = popover.width()
    let ph = popover.height()

    var btnPos: QPoint
    case filterLevel
    of llHint: btnPos = self.diagHintBtn.mapToGlobal(QPoint.create(cint 0, cint 0))
    of llWarning: btnPos = self.diagWarnBtn.mapToGlobal(QPoint.create(cint 0, cint 0))
    of llError: btnPos = self.diagErrBtn.mapToGlobal(QPoint.create(cint 0, cint 0))
    else: btnPos = QPoint.create(cint 0, cint 0)

    var yPos = btnPos.y() + PopupYOffset
    popover.setGeometry(btnPos.x(), yPos, pw, min(ph, MaxPopupHeight))
    popover.raiseX()
    popover.show()
  except CatchableError: discard

proc onDiagHint*(self: Toolbar, triggered: proc() {.raises: [].}) =
  self.diagHintBtn.onClicked(triggered)

proc onDiagWarn*(self: Toolbar, triggered: proc() {.raises: [].}) =
  self.diagWarnBtn.onClicked(triggered)

proc onDiagErr*(self: Toolbar, triggered: proc() {.raises: [].}) =
  self.diagErrBtn.onClicked(triggered)

proc onDiagNavigate*(self: Toolbar, cb: proc(path: string, line, col: int) {.raises: [].}) =
  self.diagNavigateCb = cb
