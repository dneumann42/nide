import std/[tables, strutils]
import seaqt/[qtoolbar, qtoolbutton, qmenu, qwidget, qlayout, qaction, qapplication,
              qabstractbutton, qpixmap, qpaintdevice, qpainter, qcolor, qicon, qsize,
              qsvgrenderer, qlabel, qhboxlayout]

const RunSvg      = staticRead("icons/run.svg")
const BuildSvg    = staticRead("icons/build.svg")
const GearSvg     = staticRead("icons/gear.svg")
const FileTreeSvg = staticRead("icons/filetree.svg")
const GraphSvg    = staticRead("icons/graph.svg")
const LoadingSvg  = staticRead("icons/loading.svg")
const NimSvg      = staticRead("../../res/Nim_logo.svg")

proc svgIcon(svg: string, size: cint): QIcon =
  var pm = QPixmap.create(size, size)
  pm.fill(QColor.create("transparent"))
  var painter = QPainter.create(QPaintDevice(h: pm.h, owned: false))
  var renderer = QSvgRenderer.create(svg.toOpenArrayByte(0, svg.high))
  renderer.render(painter)
  discard painter.endX()
  QIcon.create(pm)

proc svgIcon(svg: string, size: cint, color: string): QIcon =
  var coloredSvg = svg.replace("fill=\"white\"", "fill=\"" & color & "\"")
  coloredSvg = coloredSvg.replace("stroke=\"white\"", "stroke=\"" & color & "\"")
  coloredSvg = coloredSvg.replace("currentColor", color)
  var pm = QPixmap.create(size, size)
  pm.fill(QColor.create("transparent"))
  var painter = QPainter.create(QPaintDevice(h: pm.h, owned: false))
  var renderer = QSvgRenderer.create(coloredSvg.toOpenArrayByte(0, coloredSvg.high))
  renderer.render(painter)
  discard painter.endX()
  QIcon.create(pm)

type
  ToolMenuId* = enum
    NewModule
    OpenModule
    OpenFile
    NewProject
    SaveProject
    OpenProject
    Quit
    SyntaxTheme
    RestartNimSuggest
    JumpBack
    JumpForward

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

proc buildFileMenu(self: Toolbar) =
  self.fileMenu = ToolMenu(label: "File")
  self.fileMenu.build()

  self.fileMenu.actions[NewModule] = self.fileMenu.menu.addAction("New Module")
  self.fileMenu.actions[OpenModule] = self.fileMenu.menu.addAction("Open Module")
  self.fileMenu.actions[OpenFile] = self.fileMenu.menu.addAction("Open File")

  self.fileMenu.actions[NewProject] = self.fileMenu.menu.addAction("New Project")
  self.fileMenu.actions[OpenProject] = self.fileMenu.menu.addAction("Open Project")

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

  discard self.toolbar.addWidget(self.nimMenu.button)

proc build*(self: Toolbar) =
  self.toolbar = QToolbar.create()
  self.toolbar.setMovable(false)
  self.toolbar.setIconSize(QSize.create(cint 12, cint 12))
  QWidget(h: self.toolbar.h, owned: false).setContentsMargins(cint 0, cint 0, cint 0, cint 0)
  QWidget(h: self.toolbar.h, owned: false).setFixedHeight(cint 28)
  let tbLayout = QWidget(h: self.toolbar.h, owned: false).layout()
  tbLayout.setContentsMargins(cint 0, cint 0, cint 0, cint 0)
  tbLayout.setSpacing(cint 2)

  var chipWidget = QWidget.create()
  chipWidget.owned = false
  chipWidget.setStyleSheet(
    "QWidget { background: #1e3a5c; color: #cce0ff; border-radius: 4px; padding: 2px 6px; }")

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
  self.loaderLabel.setPixmap(svgIcon(NimSvg, cint 12).pixmap(cint 12, cint 12))
  chipLayout.addWidget(QWidget(h: self.loaderLabel.h, owned: false))

  discard self.toolbar.addWidget(chipWidget)

  const IconSize = 12
  self.fileTreeBtn = QToolButton.create()
  self.fileTreeBtn.setAutoRaise(true)
  QWidget(h: self.fileTreeBtn.h, owned: false).setFixedSize(cint 18, cint 18)
  QAbstractButton(h: self.fileTreeBtn.h, owned: false).setIcon(svgIcon(FileTreeSvg, cint IconSize))
  QAbstractButton(h: self.fileTreeBtn.h, owned: false).setIconSize(QSize.create(cint IconSize, cint IconSize))
  QWidget(h: self.fileTreeBtn.h, owned: false).setEnabled(false)
  discard self.toolbar.addWidget(self.fileTreeBtn)

  self.graphBtn = QToolButton.create()
  self.graphBtn.setAutoRaise(true)
  QWidget(h: self.graphBtn.h, owned: false).setFixedSize(cint 18, cint 18)
  QAbstractButton(h: self.graphBtn.h, owned: false).setIcon(svgIcon(GraphSvg, cint IconSize))
  QAbstractButton(h: self.graphBtn.h, owned: false).setIconSize(QSize.create(cint IconSize, cint IconSize))
  discard self.toolbar.addWidget(self.graphBtn)

  self.buildFileMenu()
  self.buildViewMenu()
  self.buildNimMenu()

  block:
    var spacer = QWidget.create()
    spacer.owned = false
    spacer.setSizePolicy(cint(7), cint(5))  # Expanding x Preferred
    discard self.toolbar.addWidget(spacer)

  self.runBtn = QToolButton.create()
  self.runBtn.setAutoRaise(true)
  QWidget(h: self.runBtn.h, owned: false).setFixedSize(cint 18, cint 18)
  QAbstractButton(h: self.runBtn.h, owned: false).setIcon(svgIcon(RunSvg, cint IconSize))
  QAbstractButton(h: self.runBtn.h, owned: false).setIconSize(QSize.create(cint IconSize, cint IconSize))
  discard self.toolbar.addWidget(self.runBtn)

  self.buildBtn = QToolButton.create()
  self.buildBtn.setAutoRaise(true)
  QWidget(h: self.buildBtn.h, owned: false).setFixedSize(cint 18, cint 18)
  QAbstractButton(h: self.buildBtn.h, owned: false).setIcon(svgIcon(BuildSvg, cint IconSize))
  QAbstractButton(h: self.buildBtn.h, owned: false).setIconSize(QSize.create(cint IconSize, cint IconSize))
  discard self.toolbar.addWidget(self.buildBtn)

  self.settingsBtn = QToolButton.create()
  self.settingsBtn.setAutoRaise(true)
  QWidget(h: self.settingsBtn.h, owned: false).setFixedSize(cint 18, cint 18)
  QAbstractButton(h: self.settingsBtn.h, owned: false).setIcon(svgIcon(GearSvg, cint IconSize))
  QAbstractButton(h: self.settingsBtn.h, owned: false).setIconSize(QSize.create(cint IconSize, cint IconSize))
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
  const IconSize = 12
  QAbstractButton(h: self.fileTreeBtn.h, owned: false).setIcon(svgIcon(FileTreeSvg, cint IconSize, color))

proc onFileTreeToggle*(self: Toolbar, triggered: proc() {.raises: [].}) =
  self.fileTreeBtn.onClicked(triggered)

proc setLoading*(self: Toolbar, loading: bool) =
  if loading:
    self.loaderLabel.setPixmap(svgIcon(LoadingSvg, cint 12).pixmap(cint 12, cint 12))
  else:
    self.loaderLabel.setPixmap(svgIcon(NimSvg, cint 12).pixmap(cint 12, cint 12))
