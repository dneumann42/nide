import std/[os]
import seaqt/[
  qapplication, qmainwindow, qstackedwidget,
  qwidget, qpushbutton,
  qplaintextedit, qtoolbar, qboxlayout,
  qmenu, qtoolbutton, qaction, qfiledialog,
  qfont, qfontdatabase, qtabwidget, qsizepolicy,
  qsplitter, qrubberband]
import seaqt/QtWidgets/gen_qlayout_types

import bench/[buffers, ui, theme, split]

proc buildApplication() =
  let _ = QApplication.create()

  var bufferManager = BufferManager.init()

  let dashboard = QWidget.create()
  let dashLayout = QVBoxLayout.create()
  let startBtn = QPushButton.create("Start")
  startBtn.setFixedWidth(120)
  QLayout(h: dashLayout.h, owned: false).setContentsMargins(0, 0, 0, 0)
  dashLayout.addStretch()
  dashLayout.addWidget(QWidget(h: startBtn.h, owned: false), 0, 132)
  dashLayout.addStretch()
  dashboard.setLayout(QLayout(h: dashLayout.h, owned: false))

  let editPage = QWidget.create()
  let editLayout = QVBoxLayout.create()
  let toolbar = QToolBar.create()
  toolbar.setMovable(true)
  toolbar.setFloatable(false)

  let buffersMenu = QMenu.create()
  let monoFont = QFontDatabase.systemFont(cint QFontDatabaseSystemFontEnum.FixedFont)
  var handleTabClose: proc(pane: Pane, idx: cint) {.closure, raises: [].}

  proc makePane(): Pane =
    newPane(monoFont) do(pane: Pane, idx: cint) {.closure, raises: [].}:
      handleTabClose(pane, idx)

  let rootSplitter = QSplitter.create(cint 1)
  let firstPane = makePane()
  firstPane.parentH = rootSplitter.h
  gPanes.add(firstPane)
  rootSplitter.addWidget(QWidget(h: firstPane.tabWidget.h, owned: false))

  editLayout.setSpacing(0)
  QLayout(h: editLayout.h, owned: false).setContentsMargins(0, 0, 0, 0)
  editLayout.addWidget(QWidget(h: toolbar.h, owned: false))
  editLayout.addWidget(QWidget(h: rootSplitter.h, owned: false), 1)
  editPage.setLayout(QLayout(h: editLayout.h, owned: false))

  firstPane.tabBar.overlay = block:
    let overlay = DropOverlay()

    # QWidget.create(editPage, overlay)
    # overlay.rubberBand = QRubberBand.create(
    #   cint QRubberBandShapeEnum.Rectangle,
    #   QWidget(h: overlay[].h, owned: false))
    # QWidget(h: overlay[].h, owned: false).setAcceptDrops(true)
    # QWidget(h: overlay[].h, owned: false).hide()
    #
    # overlay.onDrop = proc(srcIdx: int, tabIdx: cint, dst: Pane,
    #                       zone: DropZone) {.closure, raises: [].} =
    #   doSplit(srcIdx, tabIdx, dst, zone, monoFont,
    #     proc(pane: Pane, idx: cint) {.closure, raises: [].} =
    #       handleTabClose(pane, idx))
    #   # Wire overlay into any newly-created pane
    #   for p in gPanes:
    #     if p.tabBar.overlay == nil or p.tabBar.overlay[].h == nil:
    #       p.tabBar.overlay = overlay

    overlay

  proc activePaneIdx(): int =
    for i, p in gPanes:
      if QWidget(h: p.tabWidget.h, owned: false).hasFocus():
        return i
    gPanes.len - 1

  proc activePane(): Pane =
    if gPanes.len == 0: return nil
    gPanes[activePaneIdx()]

  proc tabTitle(buf: Buffer): string =
    if buf.path.len == 0: ScratchBufferName
    else: splitFile(buf.path).name & splitFile(buf.path).ext

  proc openBuffer(path = "", content = "") =
    let buf = Buffer.new(path)
    QWidget(h: buf.editor.h, owned: false).setFont(monoFont)
    if content.len > 0:
      buf.editor.setPlainText(content)
    bufferManager.add(buf)
    let pane = activePane()
    if pane == nil: return
    pane.buffers.add(buf)
    addTabToPane(pane, buf)

  proc findBufPane(buf: Buffer): (Pane, cint) =
    for p in gPanes:
      for i, b in p.buffers:
        if b == buf:
          return (p, cint i)
    (nil, -1)

  handleTabClose = proc(pane: Pane, idx: cint) {.closure, raises: [].} =
    if idx < 0 or idx >= pane.buffers.len: return
    pane.buffers.delete(idx)
    pane.tabWidget.removeTab(idx)
    if pane.buffers.len == 0:
      removePaneFromSplitter(pane)

  let win = QMainWindow.create()
  win.setWindowTitle("Bench DEV 0.0.0")
  win.resize(800, 600)

  let stack = QStackedWidget.create()
  win.setCentralWidget(QWidget(h: stack.h, owned: false))

  let idxDash = stack.addWidget(dashboard)
  let idxEdit = stack.addWidget(editPage)

  openBuffer()

  proc showBuffer(buf: Buffer) =
    let (pane, tabIdx) = findBufPane(buf)
    if pane != nil:
      pane.tabWidget.setCurrentIndex(tabIdx)
    else:
      let p = activePane()
      if p == nil: return
      p.buffers.add(buf)
      addTabToPane(p, buf)
    stack.setCurrentIndex(idxEdit)

  proc addBufMenuItem(buf: Buffer) =
    let (pane, _) = findBufPane(buf)
    let label = tabTitle(buf) & (if pane != nil: "" else: " (closed)")
    let act = QWidget(h: buffersMenu.h, owned: false).addAction(label)
    act.onTriggered do():
      showBuffer(buf)

  buffersMenu.onAboutToShow do():
    buffersMenu.clear()
    for buf in bufferManager:
      addBufMenuItem(buf)

  startBtn.onPressed do():
    stack.setCurrentIndex(idxEdit)

  let
    openFileAction = menuAction(OpenFile) do():
      let path = QFileDialog.getOpenFileName(
        QWidget(h: win.h, owned: false),
        "Open File", "", "Nim files (*.nim *.nimble *.nims);;All files (*)"
      )
      if path.len > 0:
        for buf in bufferManager:
          if buf.path == path:
            showBuffer(buf)
            return
        try:
          openBuffer(path, readFile(path))
          stack.setCurrentIndex(idxEdit)
        except IOError:
          discard

    saveFileAsAction = menuAction(SaveFileAs) do():
      let p = activePane()
      if p == nil: return
      let idx = p.tabWidget.currentIndex()
      if idx < 0 or idx >= p.buffers.len: return
      let buf = p.buffers[idx]
      let path = QFileDialog.getSaveFileName(
        QWidget(h: win.h, owned: false),
        "Save File", buf.path, "Nim files (*.nim *.nimble *.nims);;All files (*)")
      if path.len > 0:
        try:
          writeFile(path, buf.editor.toPlainText())
          buf.path = path
          p.tabWidget.setTabText(idx, tabTitle(buf))
        except IOError:
          discard

    saveFileAction = menuAction(SaveFile) do():
      let p = activePane()
      if p == nil: return
      let idx = p.tabWidget.currentIndex()
      if idx < 0 or idx >= p.buffers.len: return
      let buf = p.buffers[idx]
      if buf.path.len > 0:
        try:
          writeFile(buf.path, buf.editor.toPlainText())
        except IOError:
          discard

    quitAction = menuAction(Quit) do():
      QApplication.quit()

  let fileMenu = buildFileMenu(
    openFileAction,
    saveFileAction,
    saveFileAsAction,
    quitAction
  )
  discard toolbar.addWidget(QWidget(h: fileMenu.h, owned: false))

  let
    projectNewAction = menuAction(NewProject) do():
      discard
    projectOpenAction = menuAction(OpenProject) do():
      discard

  let projectMenu = buildProjectMenu(
    projectNewAction,
    projectOpenAction
  )
  discard toolbar.addWidget(QWidget(h: projectMenu.h, owned: false))

  let buffersBtn = QToolButton.create()
  buffersBtn.setText("Buffers")
  buffersBtn.setMenu(buffersMenu)
  buffersBtn.setPopupMode(cint QToolButtonToolButtonPopupModeEnum.InstantPopup)
  discard toolbar.addWidget(QWidget(h: buffersBtn.h, owned: false))

  let spacer = QWidget.create()
  spacer.setSizePolicy(
    cint QSizePolicyPolicyEnum.Expanding,
    cint QSizePolicyPolicyEnum.Preferred
  )
  discard toolbar.addWidget(QWidget(h: spacer.h, owned: false))

  var currentTheme = Theme.Light
  let themeBtn = QPushButton.create("Dark")
  themeBtn.setFixedWidth(60)
  discard toolbar.addWidget(QWidget(h: themeBtn.h, owned: false))

  themeBtn.onPressed do():
    currentTheme = if currentTheme == Theme.Light: Theme.Dark else: Theme.Light
    applyTheme(currentTheme)
    themeBtn.setText(if currentTheme == Theme.Dark: "Light" else: "Dark")

  stack.setCurrentIndex(idxEdit)

  win.show()
  quit QApplication.exec().int

when isMainModule:
  buildApplication()
