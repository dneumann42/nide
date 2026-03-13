import std/[os, json]
import seaqt/[qapplication, qwidget, qfiledialog, qmainwindow, qtoolbar, qsplitter,
              qcoreapplication, qtoolbutton, qabstractbutton,
              qshortcut, qkeysequence, qobject, qgraphicsopacityeffect,
              qgraphicseffect, qplaintextedit, qtextdocument, qtextcursor, qtextedit]
import bench/[toolbar, buffers, projects, projectdialog, moduledialog, theme, pane, runner,
              filefinder, rgfinder, settings, widgetref, panemanager, syntaxtheme, themedialog,
              nimfinddef]

type
  ApplicationState = object
    lastOpenedProjectPath: string

  PaneKeyBinding* = object
    sequence: string
    callback*: proc(target: Pane) {.raises: [].}

  GlobalKeyBinding* = object
    sequence: string
    callback*: proc() {.raises: [].}

  Application* = ref object
    bufferManager: BufferManager
    toolbar: Toolbar
    projectManager: ProjectManager
    root: QMainWindow
    paneManager: PaneManager
    theme: Theme
    currentProject: string
    runStatusBtn:  WidgetRef[QToolButton]
    buildStatusBtn: WidgetRef[QToolButton]
    runReopen:  proc() {.raises: [].}
    buildReopen: proc() {.raises: [].}
    opacityActive: bool
    opacityEffect: QGraphicsOpacityEffect
    nimSuggest: NimSuggestClient

proc getTargetPane*(self: Application): Pane =
  result = self.paneManager.lastFocusedPane
  if result == nil and self.paneManager.panels.len > 0:
    result = self.paneManager.panels[0]

proc registerPaneShortcut*(self: Application, sequence: string, callback: proc(target: Pane): void {.raises: [].}) =
  var sc = QShortcut.create(QKeySequence.create(sequence),
                            QObject(h: self.root.h, owned: false))
  sc.owned = false
  sc.setContext(cint 2)
  sc.onActivated do() {.raises: [].}:
    let target = self.getTargetPane()
    if target != nil:
      callback(target)

proc registerGlobalShortcut*(self: Application, sequence: string, callback: proc(): void {.raises: [].}) =
  var sc = QShortcut.create(QKeySequence.create(sequence),
                            QObject(h: self.root.h, owned: false))
  sc.owned = false
  sc.setContext(cint 2)
  sc.onActivated callback

proc buffers*(app: Application): lent BufferManager =
  result = app.bufferManager

proc new*(T: typedesc[Application]): T =
  result = T(
    bufferManager: BufferManager.init(),
    toolbar: Toolbar(),
    projectManager: ProjectManager.init()
  )
  result.projectManager.load()

proc writeLastOpenedProject(path: string) {.raises: [].} =
  try:
    let contents = 
      if fileExists(path):
        readFile(path)
      else:
        "{}"
    var cfg = parseJson(contents).to(ApplicationState)
    cfg.lastOpenedProjectPath = path
    writeFile(path, (%* cfg).pretty)
  except:
    echo getCurrentExceptionMsg()

proc openProject(self: Application, path: string) {.raises: [].} =
  let dir = path.parentDir()
  self.currentProject = dir
  for panel in self.paneManager.panels:
    panel.clearBuffer()
  self.paneManager.setProjectOpen(true)
  self.bufferManager = BufferManager.init()
  try: setCurrentDir(dir) except OSError: discard
  self.toolbar.setProjectName(dir.lastPathPart)
  writeLastOpenedProject(path)
  # Start nimsuggest for this project
  if self.nimSuggest != nil:
    self.nimSuggest.kill()
  let entryFile = findNimbleEntry(path)
  self.nimSuggest = NimSuggestClient.new(self.root.h, entryFile)
  self.nimSuggest.start()
  self.paneManager.panels[0].triggerOpenModule()

proc openProject(self: Application) {.raises: [].} =
  let file = QFileDialog.getOpenFileName(
    QWidget(h: self.root.h, owned: false), "", "", "Nimble files (*.nimble)")
  if file.len == 0: return
  self.openProject(file)

proc closeBuffer*(self: Application, name: string) =
  for panel in self.paneManager.panels:
    if panel.buffer != nil and panel.buffer.name == name:
      panel.clearBuffer()
  self.bufferManager.close(name)

proc build*(self: Application) =
  self.root = QMainWindow.create()
  QWidget(h: self.root.h, owned: false).setAttribute(cint(120))  # WA_TranslucentBackground
  QWidget(h: self.root.h, owned: false).setMinimumSize(cint(800), cint(480))
  self.toolbar.build()

  self.root.addToolBar(QToolBar(h: self.toolbar.widget().h, owned: false))

  var splitter = QSplitter.create(cint(1))
  splitter.setHandleWidth(cint 4)
  QWidget(h: splitter.h, owned: false).setAutoFillBackground(true)
  QWidget(h: splitter.h, owned: false).setStyleSheet("QSplitter::handle { background: #333333; }")
  self.root.setCentralWidget(QWidget(h: splitter.h, owned: false))
  splitter.owned = false

  var opEff = QGraphicsOpacityEffect.create()
  opEff.setOpacity(1.0)
  QWidget(h: splitter.h, owned: false).setGraphicsEffect(
    QGraphicsEffect(h: opEff.h, owned: false))
  opEff.owned = false
  self.opacityEffect = opEff

  self.theme = Dark
  applyTheme(Dark)

  # Initialize syntax theme (load from settings if available, otherwise default)
  initDefaultTheme()
  setCurrentTheme("VS Code Dark+")

  self.paneManager = PaneManager.init(splitter, PaneCallbacks(
    onFileSelected: proc(pane: Pane, path: string) {.raises: [].} =
      let buf = self.bufferManager.openFile(path)
      pane.setBuffer(buf),
    onNewModule: proc(pane: Pane) {.raises: [].} =
      let path = showNewModuleDialog(QWidget(h: self.root.h, owned: false))
      if path.len > 0:
        let buf = self.bufferManager.openFile(path)
        pane.setBuffer(buf),
    onOpenModule: proc(pane: Pane) {.raises: [].} =
      showFileFinder(QWidget(h: self.root.h, owned: false),
        proc(path: string) {.raises: [].} =
          let buf = self.bufferManager.openFile(path)
          pane.setBuffer(buf)),
    onOpenProject: proc(pane: Pane) {.raises: [].} =
      self.openProject(),
    onGotoDefinition: proc(pane: Pane, path: string, line: int, col: int) {.raises: [].} =
      let buf = self.bufferManager.openFile(path)
      pane.setBuffer(buf)
      pane.scrollToLine(line, col),
    onJumpBack: proc(pane: Pane, path: string, line: int, col: int) {.raises: [].} =
      # Push current position onto the forward stack before navigating back
      if pane.buffer != nil and pane.buffer.path.len > 0:
        try:
          let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
          let cur = ed.textCursor()
          pane.jumpFuture.add(JumpLocation(
            file: pane.buffer.path,
            line: cur.blockNumber() + 1,
            col:  cur.columnNumber()))
        except: discard
      if path.len > 0:
        let buf = self.bufferManager.openFile(path)
        pane.setBuffer(buf)
      pane.scrollToLine(line, col),
    onJumpForward: proc(pane: Pane, path: string, line: int, col: int) {.raises: [].} =
      # Push current position onto the back stack before navigating forward
      if pane.buffer != nil and pane.buffer.path.len > 0:
        try:
          let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
          let cur = ed.textCursor()
          pane.jumpHistory.add(JumpLocation(
            file: pane.buffer.path,
            line: cur.blockNumber() + 1,
            col:  cur.columnNumber()))
        except: discard
      if path.len > 0:
        let buf = self.bufferManager.openFile(path)
        pane.setBuffer(buf)
      pane.scrollToLine(line, col)
    ))

  # Floating background-process indicator buttons (initially hidden, child of root)
  var runStatusBtn = QToolButton.create()
  runStatusBtn.owned = false
  QAbstractButton(h: runStatusBtn.h, owned: false).setText("nimble run")
  QWidget(h: runStatusBtn.h, owned: false).setParent(QWidget(h: self.root.h, owned: false))
  QWidget(h: runStatusBtn.h, owned: false).hide()
  self.runStatusBtn = capture(runStatusBtn)

  var buildStatusBtn = QToolButton.create()
  buildStatusBtn.owned = false
  QAbstractButton(h: buildStatusBtn.h, owned: false).setText("nimble build")
  QWidget(h: buildStatusBtn.h, owned: false).setParent(QWidget(h: self.root.h, owned: false))
  QWidget(h: buildStatusBtn.h, owned: false).hide()
  self.buildStatusBtn = capture(buildStatusBtn)

  runStatusBtn.onClicked do() {.raises: [].}:
    QWidget(h: self.runStatusBtn.h, owned: false).hide()
    if self.runReopen != nil:
      self.runReopen()
      self.runReopen = nil

  buildStatusBtn.onClicked do() {.raises: [].}:
    QWidget(h: self.buildStatusBtn.h, owned: false).hide()
    if self.buildReopen != nil:
      self.buildReopen()
      self.buildReopen = nil

  self.toolbar.onRun do():
    let onBg = proc(reopen: proc() {.raises: [].}) {.raises: [].} =
      self.runReopen = reopen
      let rw = QWidget(h: self.root.h, owned: false)
      let btn = QWidget(h: self.runStatusBtn.h, owned: false)
      btn.move(rw.width() - cint(110), rw.height() - cint(40))
      btn.show()
      btn.raiseX()
    let gotoRun = proc(file: string, line, col: int) {.raises: [].} =
      try:
        var target = self.paneManager.lastFocusedPane
        if target == nil and self.paneManager.panels.len > 0:
          target = self.paneManager.panels[0]
        if target == nil: return
        let buf = self.bufferManager.openFile(file)
        target.setBuffer(buf)
        target.jumpToLine(line, col)
      except: discard
    runCommand(QWidget(h: self.root.h, owned: false), "nimble run", "n=$(ls *.nimble | head -1); b=${n%.nimble}; nim cpp --out:./$b src/$b.nim && ./$b", onBg, gotoRun)

  self.toolbar.onBuild do():
    let onBg = proc(reopen: proc() {.raises: [].}) {.raises: [].} =
      self.buildReopen = reopen
      let rw = QWidget(h: self.root.h, owned: false)
      let btn = QWidget(h: self.buildStatusBtn.h, owned: false)
      btn.move(rw.width() - cint(110), rw.height() - cint(80))
      btn.show()
      btn.raiseX()
    let gotoBuild = proc(file: string, line, col: int) {.raises: [].} =
      try:
        var target = self.paneManager.lastFocusedPane
        if target == nil and self.paneManager.panels.len > 0:
          target = self.paneManager.panels[0]
        if target == nil: return
        let buf = self.bufferManager.openFile(file)
        target.setBuffer(buf)
        target.jumpToLine(line, col)
      except: discard
    runCommand(QWidget(h: self.root.h, owned: false), "nimble build", "n=$(ls *.nimble | head -1); b=${n%.nimble}; nim cpp --out:./$b src/$b.nim", onBg, gotoBuild)

  self.toolbar.onThemeToggle do():
    self.theme = if self.theme == Dark: Light else: Dark
    applyTheme(self.theme)
    self.toolbar.setThemeIcon(self.theme == Dark)
    self.paneManager.updateFocus(QApplication.focusWidget(), self.theme == Dark)

  self.toolbar.onOpacityToggle do():
    self.opacityActive = not self.opacityActive
    let level = if self.opacityActive: 0.95 else: 1.0
    self.opacityEffect.setOpacity(level)

  self.toolbar.onTriggered(NewProject) do():
    showNewProjectDialog(QWidget(h: self.root.h, owned: false), self.projectManager)

  self.toolbar.onTriggered(NewModule) do():
    if self.paneManager.panels.len > 0:
      self.paneManager.panels[0].triggerNewModule()

  self.toolbar.onTriggered(OpenModule) do():
    if self.paneManager.panels.len > 0:
      self.paneManager.panels[0].triggerOpenModule()
  
  self.toolbar.onTriggered(OpenFile) do():
    let file = QFileDialog.getOpenFileName(
        QWidget(h: self.root.h, owned: false), "", "", "All files (*.*)")
    if file.len == 0: return
    let buf = self.bufferManager.openFile(file)
    
    var target = self.paneManager.lastFocusedPane
    if target == nil and self.paneManager.panels.len > 0:
      target = self.paneManager.panels[0]
    if target == nil: return
    target.setBuffer(buf)

  self.toolbar.onTriggered(OpenProject) do():
    self.openProject()

  self.toolbar.onTriggered(Quit) do():
    QApplication.quit()

  self.toolbar.onTriggered(SyntaxTheme) do():
    showThemeDialog(
      QWidget(h: self.root.h, owned: false),
      currentThemeName,
      proc(name: string) {.raises: [].} =
        try:
          setCurrentTheme(name)
          self.bufferManager.rehighlightAll()
          for panel in self.paneManager.panels:
            panel.applyEditorTheme()
        except:
          discard
    )

  self.toolbar.onNewPane do():
    self.paneManager.addColumn()
    self.paneManager.equalizeSplits()

  self.toolbar.onSettings do():
    showSettingsDialog(QWidget(h: self.root.h, owned: false))

  self.toolbar.onTriggered(JumpBack) do():
    let target = self.getTargetPane()
    if target != nil:
      target.triggerJumpBack()

  self.toolbar.onTriggered(JumpForward) do():
    let target = self.getTargetPane()
    if target != nil:
      target.triggerJumpForward()

  self.toolbar.onTriggered(RestartNimSuggest) do():
    if self.nimSuggest != nil:
      self.nimSuggest.restart()

  let cbFindFile = proc(target: Pane): void {.raises: [].} =
    showFileFinder(
      QWidget(h: self.root.h, owned: false),
      proc(path: string) {.raises: [].} =
        let buf = self.bufferManager.openFile(path)
        target.setBuffer(buf))
  self.registerPaneShortcut("Ctrl+P", cbFindFile)

  let cbFind = proc(target: Pane): void {.raises: [].} =
    target.triggerFind()
  self.registerPaneShortcut("Ctrl+F", cbFind)

  let cbEscape = proc(target: Pane): void {.raises: [].} =
    target.closeSearch()
  self.registerPaneShortcut("Escape", cbEscape)

  let cbOpenProject = proc(target: Pane): void {.raises: [].} =
    if target.buffer == nil:
      target.triggerOpenProject()
  self.registerPaneShortcut("Ctrl+O", cbOpenProject)

  let cbBuffer = proc(target: Pane): void {.raises: [].} =
    var entries: seq[(string, string)]
    let cwd = try: getCurrentDir() except OSError: ""
    for buf in self.bufferManager:
      var display = buf.name
      if cwd.len > 0:
        try: display = relativePath(buf.name, cwd)
        except: discard
      entries.add((display, buf.name))
    if entries.len == 0: return
    showBufferFinder(
      QWidget(h: self.root.h, owned: false),
      entries,
      proc(key: string) {.raises: [].} =
        for buf in self.bufferManager:
          if buf.name == key:
            target.setBuffer(buf)
            break)
  self.registerPaneShortcut("Ctrl+B", cbBuffer)

  let cbRg = proc(target: Pane): void {.raises: [].} =
    showRipgrepFinder(
      QWidget(h: self.root.h, owned: false),
      proc(file: string, lineNum: int) {.raises: [].} =
        let buf = self.bufferManager.openFile(file)
        target.setBuffer(buf)
        target.scrollToLine(lineNum))
  self.registerPaneShortcut("Ctrl+Shift+F", cbRg)

  let cbSave = proc(target: Pane): void {.raises: [].} =
    target.save()
  self.registerPaneShortcut("Ctrl+S", cbSave)

  let cbClosePane = proc(target: Pane): void {.raises: [].} =
    self.paneManager.closePane(target)
  self.registerPaneShortcut("Ctrl+W", cbClosePane)

  let cbNewPane = proc(): void {.raises: [].} =
    self.paneManager.addColumn()
    self.paneManager.equalizeSplits()
  self.registerGlobalShortcut("Ctrl+\\", cbNewPane)

  let cbHSplit = proc(target: Pane): void {.raises: [].} =
    try: self.paneManager.splitRow(target)
    except: discard
  self.registerPaneShortcut("Ctrl+Shift+\\", cbHSplit)

  let cbGotoDef = proc(target: Pane): void {.raises: [].} =
    if self.nimSuggest == nil: return
    try: target.triggerGotoDefinition(self.nimSuggest)
    except: discard
  self.registerPaneShortcut("F3", cbGotoDef)

  let cbZoomIn = proc(target: Pane): void {.raises: [].} =
    target.zoomIn()
  self.registerPaneShortcut("Ctrl+=", cbZoomIn)

  let cbZoomOut = proc(target: Pane): void {.raises: [].} =
    target.zoomOut()
  self.registerPaneShortcut("Ctrl+-", cbZoomOut)

  self.paneManager.addColumn()  # initialize at least one
  self.paneManager.equalizeSplits()

  let appInstance = QApplication(h: QCoreApplication.instance().h, owned: false)
  appInstance.onFocusChanged do(old, now: QWidget):
    try:
      self.paneManager.updateFocus(now, self.theme == Dark)
    except: discard

proc show*(self: Application) =
  self.root.show()
