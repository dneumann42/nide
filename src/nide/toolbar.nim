import std/[tables, strutils]
import seaqt/[qtoolbar, qtoolbutton, qmenu, qwidget, qlayout, qaction, qapplication,
              qabstractbutton, qsize, qicon, qlabel, qhboxlayout, qpushbutton, qpoint,
              qscrollarea, qvboxlayout, qscroller]
import widgets
import logparser
import qtconst, uicolors

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

  var chipWidget = QWidget.create()
  chipWidget.owned = false
  chipWidget.setStyleSheet(
    "QWidget { background: " & clChipBg & "; color: " & clChipText & "; border-radius: 4px; padding: 2px 6px; }")

  var chipLayout = QHBoxLayout.create()
  chipLayout.owned = false
  chipLayout.setContentsMargins(cint 2, cint 0, cint 2, cint 0)
  chipLayout.setSpacing(cint 4)
  QWidget(h: chipWidget.h, owned: false).setLayout(chipLayout)

  self.projectLabel = QLabel.create("—")
  self.projectLabel.owned = false
  chipLayout.addWidget(QWidget(h: self.projectLabel.h, owned: false))

  self.loaderLabel = QLabel.create("")
  self.loaderLabel.owned = false
  self.loaderLabel.setPixmap(svgIcon(NimSvg, ToolbarIconSize).pixmap(ToolbarIconSize, ToolbarIconSize))
  chipLayout.addWidget(QWidget(h: self.loaderLabel.h, owned: false))

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
    var spacer = QWidget.create()
    spacer.owned = false
    spacer.setSizePolicy(SP_Expanding, SP_Preferred)
    discard self.toolbar.addWidget(spacer)

  self.diagWidget = QWidget.create()
  self.diagWidget.owned = false
  var diagLayout = QHBoxLayout.create()
  diagLayout.owned = false
  diagLayout.setContentsMargins(cint 0, cint 0, cint 0, cint 0)
  diagLayout.setSpacing(ToolbarSpacing)
  QWidget(h: self.diagWidget.h, owned: false).setLayout(QLayout(h: diagLayout.h, owned: false))

  self.diagHintBtn = QToolButton.create()
  self.diagHintBtn.owned = false
  diagLayout.addWidget(QWidget(h: self.diagHintBtn.h, owned: false))

  self.diagWarnBtn = QToolButton.create()
  self.diagWarnBtn.owned = false
  diagLayout.addWidget(QWidget(h: self.diagWarnBtn.h, owned: false))

  self.diagErrBtn = QToolButton.create()
  self.diagErrBtn.owned = false
  diagLayout.addWidget(QWidget(h: self.diagErrBtn.h, owned: false))

  self.diagAction = self.toolbar.addWidget(self.diagWidget)
  self.diagAction.owned = false
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
  QWidget(h: self.fileTreeBtn.h, owned: false).setEnabled(enabled)

proc setFileTreeIconColor*(self: Toolbar, color: string) =
  QAbstractButton(h: self.fileTreeBtn.h, owned: false).setIcon(svgIcon(FileTreeSvg, ToolbarIconSize, color))

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
      QToolButton(h: self.diagHintBtn.h, owned: false).setText("◆" & $hintCount)
      QToolButton(h: self.diagHintBtn.h, owned: false).setStyleSheet("QToolButton { color: #00cccc; background: transparent; border: none; font-size: " & DiagBtnFontSize & "; }")
      QWidget(h: self.diagHintBtn.h, owned: false).show()
    else:
      QWidget(h: self.diagHintBtn.h, owned: false).hide()
    if warnCount > 0:
      QToolButton(h: self.diagWarnBtn.h, owned: false).setText("⚠" & $warnCount)
      QToolButton(h: self.diagWarnBtn.h, owned: false).setStyleSheet("QToolButton { color: " & clYellow & "; background: transparent; border: none; font-size: " & DiagBtnFontSize & "; }")
      QWidget(h: self.diagWarnBtn.h, owned: false).show()
    else:
      QWidget(h: self.diagWarnBtn.h, owned: false).hide()
    if errCount > 0:
      QToolButton(h: self.diagErrBtn.h, owned: false).setText("✗" & $errCount)
      QToolButton(h: self.diagErrBtn.h, owned: false).setStyleSheet("QToolButton { color: " & clRed & "; background: transparent; border: none; font-size: " & DiagBtnFontSize & "; }")
      QWidget(h: self.diagErrBtn.h, owned: false).show()
    else:
      QWidget(h: self.diagErrBtn.h, owned: false).hide()
  except: discard

proc showDiagPopover*(self: Toolbar, parentH: pointer, lines: seq[LogLine], filterLevel: LogLevel) {.raises: [].} =
  if lines.len == 0: return
  try:
    var popover = QWidget.create()
    popover.owned = false
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

    var scroll = QScrollArea.create(popover)
    scroll.owned = false
    scroll.setWidgetResizable(true)
    scroll.setHorizontalScrollBarPolicy(SBP_AlwaysOff)

    var listW = QWidget.create(scroll)
    listW.owned = false
    var listLayout = QVBoxLayout.create()
    listLayout.owned = false
    listLayout.setContentsMargins(cint 4, cint 4, cint 4, cint 4)
    listLayout.setSpacing(cint 2)
    listW.setLayout(QLayout(h: listLayout.h, owned: false))

    QScrollArea(h: scroll.h, owned: false).setWidget(QWidget(h: listW.h, owned: false))
    var popoverLayout = QVBoxLayout.create()
    popoverLayout.owned = false
    popoverLayout.setContentsMargins(cint 0, cint 0, cint 0, cint 0)
    popoverLayout.setSpacing(cint 0)
    popoverLayout.addWidget(QWidget(h: scroll.h, owned: false))
    popover.setLayout(QLayout(h: popoverLayout.h, owned: false))

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

      var itemBtn = QPushButton.create(text)
      itemBtn.owned = false
      itemBtn.setFlat(true)
      itemBtn.setStyleSheet(
        "QPushButton { color: " & clText & "; background: transparent; border: none; text-align: left; padding: 6px 8px; font-family: 'Fira Code', monospace; font-size: 12px; }" &
        "QPushButton:hover { background: " & clSurface0 & "; }")
      itemBtn.onClicked do() {.raises: [].}:
        QWidget(h: popover.h, owned: false).hide()
        if navigateCb != nil:
          navigateCb(filePath, lineNum, lineCol)
      listLayout.addWidget(QWidget(h: itemBtn.h, owned: false))

    if listLayout.count() == 0:
      return

    let popW = QWidget(h: popover.h, owned: false)
    popW.adjustSize()
    let pw = popW.width()
    let ph = popW.height()

    var btnPos: QPoint
    case filterLevel
    of llHint: btnPos = QToolButton(h: self.diagHintBtn.h, owned: false).mapToGlobal(QPoint.create(cint 0, cint 0))
    of llWarning: btnPos = QToolButton(h: self.diagWarnBtn.h, owned: false).mapToGlobal(QPoint.create(cint 0, cint 0))
    of llError: btnPos = QToolButton(h: self.diagErrBtn.h, owned: false).mapToGlobal(QPoint.create(cint 0, cint 0))
    else: btnPos = QPoint.create(cint 0, cint 0)


    var yPos = btnPos.y() + PopupYOffset
    popW.setGeometry(btnPos.x(), yPos, pw, min(ph, MaxPopupHeight))
    popW.raiseX()
    popW.show()
  except: discard

proc onDiagHint*(self: Toolbar, triggered: proc() {.raises: [].}) =
  self.diagHintBtn.onClicked(triggered)

proc onDiagWarn*(self: Toolbar, triggered: proc() {.raises: [].}) =
  self.diagWarnBtn.onClicked(triggered)

proc onDiagErr*(self: Toolbar, triggered: proc() {.raises: [].}) =
  self.diagErrBtn.onClicked(triggered)

proc onDiagNavigate*(self: Toolbar, cb: proc(path: string, line, col: int) {.raises: [].}) =
  self.diagNavigateCb = cb
