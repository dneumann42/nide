import std/[tables]
import seaqt/[qtoolbar, qtoolbutton, qmenu, qwidget, qlayout, qaction, qapplication,
              qabstractbutton, qpixmap, qpaintdevice, qpainter, qcolor, qicon, qsize,
              qsvgrenderer]

const SunSvg   = staticRead("icons/sun.svg")
const MoonSvg  = staticRead("icons/moon.svg")
const RunSvg   = staticRead("icons/run.svg")
const BuildSvg = staticRead("icons/build.svg")

proc svgIcon(svg: string, size: cint): QIcon =
  var pm = QPixmap.create(size, size)
  pm.fill(QColor.create("transparent"))
  var painter = QPainter.create(QPaintDevice(h: pm.h, owned: false))
  var renderer = QSvgRenderer.create(svg.toOpenArrayByte(0, svg.high))
  renderer.render(painter)
  discard painter.endX()
  QIcon.create(pm)

type
  ToolMenuId* = enum
    NewFile
    SaveFile
    OpenFile
    NewProject
    SaveProject
    OpenProject
    Quit

  ToolMenu* = ref object
    label: string
    button: QToolButton
    menu: QMenu
    actions: Table[ToolMenuId, QAction]

  Toolbar* = ref object
    toolbar: QToolbar
    fileMenu: ToolMenu
    newPaneBtn: QToolButton
    themeBtn: QToolButton
    runBtn: QToolButton
    buildBtn: QToolButton

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
  self.fileMenu.actions[event].onTriggered(triggered)

proc buildFileMenu(self: Toolbar) =
  self.fileMenu = ToolMenu(label: "File")
  self.fileMenu.build()

  self.fileMenu.actions[NewFile] = self.fileMenu.menu.addAction("New Module")
  self.fileMenu.actions[OpenFile] = self.fileMenu.menu.addAction("Open Module")

  self.fileMenu.actions[NewProject] = self.fileMenu.menu.addAction("New Project")
  self.fileMenu.actions[OpenProject] = self.fileMenu.menu.addAction("Open Project")

  discard self.fileMenu.menu.addSeparator()
  self.fileMenu.actions[Quit] = self.fileMenu.menu.addAction("Quit")

  discard self.toolbar.addWidget(self.fileMenu.button)

proc build*(self: Toolbar) =
  self.toolbar = QToolbar.create()
  self.toolbar.setMovable(false)
  self.toolbar.setIconSize(QSize.create(cint 12, cint 12))
  QWidget(h: self.toolbar.h, owned: false).setContentsMargins(cint 0, cint 0, cint 0, cint 0)
  QWidget(h: self.toolbar.h, owned: false).setFixedHeight(cint 28)
  let tbLayout = QWidget(h: self.toolbar.h, owned: false).layout()
  tbLayout.setContentsMargins(cint 0, cint 0, cint 0, cint 0)
  tbLayout.setSpacing(cint 2)
  self.buildFileMenu()

  const IconSize = 12
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

  var spacer = QWidget.create()
  spacer.owned = false
  spacer.setSizePolicy(cint(7), cint(5))  # Expanding x Preferred
  discard self.toolbar.addWidget(spacer)

  self.themeBtn = QToolButton.create()
  self.themeBtn.setAutoRaise(true)
  QWidget(h: self.themeBtn.h, owned: false).setFixedSize(cint 18, cint 18)
  QAbstractButton(h: self.themeBtn.h, owned: false).setIcon(svgIcon(SunSvg, cint IconSize))
  QAbstractButton(h: self.themeBtn.h, owned: false).setIconSize(QSize.create(cint IconSize, cint IconSize))
  discard self.toolbar.addWidget(self.themeBtn)

proc onRun*(self: Toolbar, triggered: proc() {.raises: [].}) =
  self.runBtn.onClicked(triggered)

proc onBuild*(self: Toolbar, triggered: proc() {.raises: [].}) =
  self.buildBtn.onClicked(triggered)

proc onNewPane*(self: Toolbar, triggered: proc() {.raises: [].}) =
  self.newPaneBtn.onClicked(triggered)

proc onThemeToggle*(self: Toolbar, triggered: proc() {.raises: [].}) =
  self.themeBtn.onClicked(triggered)

proc setThemeIcon*(self: Toolbar, isDark: bool) =
  const IconSize = 12
  let svg = if isDark: SunSvg else: MoonSvg
  QAbstractButton(h: self.themeBtn.h, owned: false).setIcon(svgIcon(svg, cint IconSize))
