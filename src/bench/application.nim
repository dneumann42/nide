import std/[os, json]
import toml_serialization
import seaqt/[qapplication, qwidget, qfiledialog, qmainwindow, qtoolbar, qsplitter,
              qcoreapplication, qtoolbutton, qabstractbutton,
              qshortcut, qkeysequence, qobject, qgraphicsopacityeffect,
              qplaintextedit, qtextdocument, qtextcursor, qtextedit,
              qresizeevent]

import toolbar, buffers, projects, projectdialog, moduledialog, theme, pane, runner,
              filefinder, rgfinder, settings, widgetref, panemanager, syntaxtheme, themedialog,
              nimsuggest, filetree, graphdialog, opacity
import commands
import "../../tools/nim_graph" as nim_graph

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
    fileTree: FileTree
    theme: Theme
    currentProject: string
    runStatusBtn:  WidgetRef[QToolButton]
    buildStatusBtn: WidgetRef[QToolButton]
    runReopen:  proc() {.raises: [].}
    buildReopen: proc() {.raises: [].}
    opacityEffect: QGraphicsOpacityEffect
    nimSuggest: NimSuggestClient
    settings: Settings

proc getTargetPane*(self: Application): Pane =
  result = self.paneManager.lastFocusedPane
  if result == nil and self.paneManager.panels.len > 0:
    result = self.paneManager.panels[0]

proc getOrCreateTargetPane*(self: Application): Pane =
  self.getTargetPane()

proc pushJumpLocation(pane: Pane, target: var seq[JumpLocation]) {.raises: [].} =
  if pane.buffer != nil and pane.buffer.path.len > 0:
    try:
      let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
      let cur = ed.textCursor()
      target.add(JumpLocation(
        file: pane.buffer.path,
        line: cur.blockNumber() + 1,
        col:  cur.columnNumber()))
    except: discard

proc navigateToLocation*(self: Application, pane: Pane, path: string, line, col: int) {.raises: [].} =
  if path.len > 0:
    let buf = self.bufferManager.openFile(path)
    pane.setBuffer(buf)
  pane.scrollToLine(line, col)

proc createStatusButton*(self: Application, text: string, parentH: pointer): WidgetRef[QToolButton] =
  var btn = QToolButton.create()
  btn.owned = false
  QAbstractButton(h: btn.h, owned: false).setText(text)
  QWidget(h: btn.h, owned: false).setParent(QWidget(h: parentH, owned: false))
  QWidget(h: btn.h, owned: false).hide()
  capture(btn)

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
  self.fileTree.setRoot(dir)
  self.toolbar.setFileTreeEnabled(true)
  self.toolbar.setFileTreeIconColor("#ffffff")
  # Start nimsuggest for this project
  if self.nimSuggest != nil:
    self.nimSuggest.kill()
  let entryFile = findNimbleEntry(path)
  self.nimSuggest = NimSuggestClient.new(self.root.h, entryFile, debug = true)
  startNimSuggest(self.nimSuggest)
  self.paneManager.nimSuggest = self.nimSuggest
  for panel in self.paneManager.panels:
    panel.nimSuggest = self.nimSuggest
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
  # WA_TranslucentBackground is set by setupWindowOpacity below
  QWidget(h: self.root.h, owned: false).setMinimumSize(cint(800), cint(480))
  self.toolbar.build()

  self.root.addToolBar(QToolBar(h: self.toolbar.widget().h, owned: false))

  # Pane columns splitter — override resizeEvent to reposition the floating file tree.
  # The vtable proc captures fileTreeRef via a ref-cell so it can be assigned after create.
  var splitterVtbl = new QSplitterVTable
  var fileTreeCell: ref FileTree
  new(fileTreeCell)
  splitterVtbl.resizeEvent = proc(self: QSplitter, e: QResizeEvent) {.raises: [], gcsafe.} =
    QSplitterresizeEvent(self, e)
    if fileTreeCell[] != nil and fileTreeCell[].isVisible():
      {.cast(gcsafe).}: fileTreeCell[].reposition()

  var splitter = QSplitter.create(cint(1), vtbl = splitterVtbl)
  splitter.setHandleWidth(cint 4)
  QWidget(h: splitter.h, owned: false).setAutoFillBackground(true)
  QWidget(h: splitter.h, owned: false).setStyleSheet("QSplitter::handle { background: #333333; }")
  self.root.setCentralWidget(QWidget(h: splitter.h, owned: false))
  splitter.owned = false

  # File tree panel — child of main window, positioned manually over content
  self.fileTree = newFileTree(self.root)
  self.fileTree.splitterH = self.root.h  # store main window for repositioning
  fileTreeCell[] = self.fileTree

  self.theme = Dark
  applyTheme(Dark)

  # Load the settings
  echo "Loading settings..."
  self.settings = Settings.load()

  self.opacityEffect = setupWindowOpacity(
    QWidget(h: self.root.h, owned: false),
    QWidget(h: splitter.h, owned: false),
    self.settings.appearance.opacityEnabled,
    self.settings.appearance.opacityLevel)

  initDefaultTheme()
  setCurrentTheme(self.settings.appearance.syntaxTheme)

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
      pane.pushJumpLocation(pane.jumpFuture)
      self.navigateToLocation(pane, path, line, col),
    onJumpForward: proc(pane: Pane, path: string, line: int, col: int) {.raises: [].} =
      pane.pushJumpLocation(pane.jumpHistory)
      self.navigateToLocation(pane, path, line, col),
    onFindFile: proc(pane: Pane) {.raises: [].} =
      showFileFinder(QWidget(h: self.root.h, owned: false)) do(path: string) {.raises: [].}:
        let buf = self.bufferManager.openFile(path)
        pane.setBuffer(buf),
    onSwitchBuffer: proc(pane: Pane) {.raises: [].} =
      var entries: seq[(string, string)]
      let cwd = try: getCurrentDir() except OSError: ""
      for buf in self.bufferManager:
        var display = buf.name
        if cwd.len > 0:
          try: display = relativePath(buf.name, cwd)
          except: discard
        entries.add((display, buf.name))
      if entries.len == 0: return
      showBufferFinder(QWidget(h: self.root.h, owned: false), entries) do(key: string) {.raises: [].}:
        for buf in self.bufferManager:
          if buf.name == key:
            pane.setBuffer(buf)
            break
    ))

  # Command dispatcher — register all editor commands and bind default keys
  block:
    let disp = CommandDispatcher()
    registerDefaultBindings(disp)
    self.paneManager.dispatcher = disp

    disp.register("editor.chordCx", proc() {.raises: [].} =
      disp.inChord = true)

    # Cursor movement
    disp.register("editor.forwardChar", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p == nil: return
      let ed = QPlainTextEdit(h: p.editor.h, owned: false)
      let c = ed.textCursor()
      discard c.movePosition(cint(QTextCursorMoveOperationEnum.Right), cint(QTextCursorMoveModeEnum.MoveAnchor))
      ed.setTextCursor(c))
    disp.register("editor.backwardChar", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p == nil: return
      let ed = QPlainTextEdit(h: p.editor.h, owned: false)
      let c = ed.textCursor()
      discard c.movePosition(cint(QTextCursorMoveOperationEnum.Left), cint(QTextCursorMoveModeEnum.MoveAnchor))
      ed.setTextCursor(c))
    disp.register("editor.nextLine", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p == nil: return
      let ed = QPlainTextEdit(h: p.editor.h, owned: false)
      let c = ed.textCursor()
      discard c.movePosition(cint(QTextCursorMoveOperationEnum.Down), cint(QTextCursorMoveModeEnum.MoveAnchor))
      ed.setTextCursor(c))
    disp.register("editor.prevLine", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p == nil: return
      let ed = QPlainTextEdit(h: p.editor.h, owned: false)
      let c = ed.textCursor()
      discard c.movePosition(cint(QTextCursorMoveOperationEnum.Up), cint(QTextCursorMoveModeEnum.MoveAnchor))
      ed.setTextCursor(c))
    disp.register("editor.beginningOfLine", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p == nil: return
      let ed = QPlainTextEdit(h: p.editor.h, owned: false)
      let c = ed.textCursor()
      discard c.movePosition(cint(QTextCursorMoveOperationEnum.StartOfLine), cint(QTextCursorMoveModeEnum.MoveAnchor))
      ed.setTextCursor(c))
    disp.register("editor.endOfLine", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p == nil: return
      let ed = QPlainTextEdit(h: p.editor.h, owned: false)
      let c = ed.textCursor()
      discard c.movePosition(cint(QTextCursorMoveOperationEnum.EndOfLine), cint(QTextCursorMoveModeEnum.MoveAnchor))
      ed.setTextCursor(c))
    disp.register("editor.forwardWord", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p == nil: return
      let ed = QPlainTextEdit(h: p.editor.h, owned: false)
      let c = ed.textCursor()
      discard c.movePosition(cint(QTextCursorMoveOperationEnum.NextWord), cint(QTextCursorMoveModeEnum.MoveAnchor))
      ed.setTextCursor(c))
    disp.register("editor.backwardWord", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p == nil: return
      let ed = QPlainTextEdit(h: p.editor.h, owned: false)
      let c = ed.textCursor()
      discard c.movePosition(cint(QTextCursorMoveOperationEnum.PreviousWord), cint(QTextCursorMoveModeEnum.MoveAnchor))
      ed.setTextCursor(c))
    disp.register("editor.beginningOfBuffer", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p == nil: return
      let ed = QPlainTextEdit(h: p.editor.h, owned: false)
      let c = ed.textCursor()
      discard c.movePosition(cint(QTextCursorMoveOperationEnum.Start), cint(QTextCursorMoveModeEnum.MoveAnchor))
      ed.setTextCursor(c))
    disp.register("editor.endOfBuffer", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p == nil: return
      let ed = QPlainTextEdit(h: p.editor.h, owned: false)
      let c = ed.textCursor()
      discard c.movePosition(cint(QTextCursorMoveOperationEnum.End), cint(QTextCursorMoveModeEnum.MoveAnchor))
      ed.setTextCursor(c))

    # Scroll
    disp.register("editor.scrollDown", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p != nil: p.scrollDown())
    disp.register("editor.scrollUp", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p != nil: p.scrollUp())

    # Edit
    disp.register("editor.deleteForwardChar", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p == nil: return
      let ed = QPlainTextEdit(h: p.editor.h, owned: false)
      let c = ed.textCursor()
      c.deleteChar()
      ed.setTextCursor(c))

    disp.register("editor.killLine", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p == nil: return
      let ed = QPlainTextEdit(h: p.editor.h, owned: false)
      let c = ed.textCursor()
      discard c.movePosition(cint(QTextCursorMoveOperationEnum.EndOfLine),
                             cint(QTextCursorMoveModeEnum.KeepAnchor))
      if c.hasSelection():
        c.removeSelectedText()
      else:
        c.deleteChar()
      ed.setTextCursor(c))

    disp.register("editor.killWordForward", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p == nil: return
      let ed = QPlainTextEdit(h: p.editor.h, owned: false)
      let c = ed.textCursor()
      discard c.movePosition(cint(QTextCursorMoveOperationEnum.NextWord),
                             cint(QTextCursorMoveModeEnum.KeepAnchor))
      c.removeSelectedText()
      ed.setTextCursor(c))

    disp.register("editor.killWordBackward", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p == nil: return
      let ed = QPlainTextEdit(h: p.editor.h, owned: false)
      let c = ed.textCursor()
      discard c.movePosition(cint(QTextCursorMoveOperationEnum.PreviousWord),
                             cint(QTextCursorMoveModeEnum.KeepAnchor))
      c.removeSelectedText()
      ed.setTextCursor(c))

    disp.register("editor.killRegion", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p != nil: QPlainTextEdit(h: p.editor.h, owned: false).cut())

    disp.register("editor.yank", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p != nil: QPlainTextEdit(h: p.editor.h, owned: false).paste())

    # Buffer / window management
    disp.register("editor.saveBuffer", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p != nil: p.save())

    disp.register("editor.killBuffer", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p != nil: self.paneManager.closePane(p))

    disp.register("editor.deleteOtherWindows", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p != nil: self.paneManager.closeOtherPanes(p))

    disp.register("editor.splitHorizontal", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p != nil: self.paneManager.splitRow(p))

    disp.register("editor.splitVertical", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p != nil: self.paneManager.splitCol(p))

    disp.register("editor.findFile", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p == nil: return
      showFileFinder(QWidget(h: self.root.h, owned: false)) do(path: string) {.raises: [].}:
        let buf = self.bufferManager.openFile(path)
        p.setBuffer(buf))

    disp.register("editor.switchBuffer", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p == nil: return
      var entries: seq[(string, string)]
      let cwd = try: getCurrentDir() except OSError: ""
      for buf in self.bufferManager:
        var display = buf.name
        if cwd.len > 0:
          try: display = relativePath(buf.name, cwd)
          except: discard
        entries.add((display, buf.name))
      if entries.len == 0: return
      showBufferFinder(QWidget(h: self.root.h, owned: false), entries) do(key: string) {.raises: [].}:
        for buf in self.bufferManager:
          if buf.name == key:
            p.setBuffer(buf)
            break)

  # Wire file tree: clicking a file opens it in the active pane
  self.fileTree.onFileSelected = proc(path: string) {.raises: [].} =
    let target = self.getTargetPane()
    if target == nil: return
    let buf = self.bufferManager.openFile(path)
    target.setBuffer(buf)

  self.runStatusBtn = self.createStatusButton("nimble run", self.root.h)
  self.buildStatusBtn = self.createStatusButton("nimble build", self.root.h)

  let runStatusBtn = QToolButton(h: self.runStatusBtn.h, owned: false)
  runStatusBtn.onClicked do() {.raises: [].}:
    QWidget(h: self.runStatusBtn.h, owned: false).hide()
    if self.runReopen != nil:
      self.runReopen()
      self.runReopen = nil

  let buildStatusBtn = QToolButton(h: self.buildStatusBtn.h, owned: false)
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
        let target = self.getTargetPane()
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
        let target = self.getTargetPane()
        if target == nil: return
        let buf = self.bufferManager.openFile(file)
        target.setBuffer(buf)
        target.jumpToLine(line, col)
      except: discard
    runCommand(QWidget(h: self.root.h, owned: false), "nimble build", "n=$(ls *.nimble | head -1); b=${n%.nimble}; nim cpp --out:./$b src/$b.nim", onBg, gotoBuild)

  self.toolbar.onGraph do():
    try:
      let srcDir = if self.currentProject.len > 0: self.currentProject / "src"
                   else: getCurrentDir() / "src"
      echo "=== graph srcDir: ", srcDir, " exists: ", dirExists(srcDir)
      let config = nim_graph.Config(
        srcDir: srcDir,
        outputFile: "",
        depth: 1,
        groupBy: "category",
        includeStd: false,
        skipPatterns: @["tests/*", "test/*", ".git/*"]
      )
      let modules = nim_graph.scanModules(config.srcDir, config.skipPatterns)
      let projectName = nim_graph.getProjectName(config.srcDir)
      let dot = nim_graph.generateDot(modules, projectName, config)
      showGraphDialog(QWidget(h: self.root.h, owned: false), dot)
    except:
      echo "=== graph error: ", getCurrentExceptionMsg()

  self.toolbar.onFileTreeToggle do():
    if self.currentProject.len > 0:
      self.fileTree.toggle()

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
    let target = self.getTargetPane()
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
    showSettingsDialog(
      QWidget(h: self.root.h, owned: false),
      self.settings,
      proc(updated: Settings) {.raises: [].} =
        self.settings = updated
        self.settings.write()
        applyTheme(updated.appearance.themeMode)
        setCurrentTheme(updated.appearance.syntaxTheme)
        self.bufferManager.rehighlightAll()
        for pane in self.paneManager.panels:
          pane.applyEditorTheme()
        self.opacityEffect.applyOpacity(
          updated.appearance.opacityEnabled,
          updated.appearance.opacityLevel),
      proc(enabled: bool, level: int) {.raises: [].} =
        self.opacityEffect.applyOpacity(enabled, level)
    )

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

  self.registerPaneShortcut("Ctrl+S") do(target: Pane) {.raises: [].}:
    target.triggerFind()

  self.registerPaneShortcut("Escape") do(target: Pane) {.raises: [].}:
    target.closeSearch()

  self.registerPaneShortcut("Ctrl+O") do(target: Pane) {.raises: [].}:
    if target.buffer == nil:
      target.triggerOpenProject()

  self.registerPaneShortcut("Ctrl+Shift+F") do(target: Pane) {.raises: [].}:
    showRipgrepFinder(QWidget(h: self.root.h, owned: false)) do(file: string, lineNum: int) {.raises: [].}:
      let buf = self.bufferManager.openFile(file)
      target.setBuffer(buf)
      target.scrollToLine(lineNum)

  self.registerGlobalShortcut("Ctrl+\\") do() {.raises: [].}:
    self.paneManager.addColumn()
    self.paneManager.equalizeSplits()

  self.registerGlobalShortcut("Ctrl+Shift+E") do() {.raises: [].}:
    if self.currentProject.len > 0:
      self.fileTree.toggle()

  self.registerGlobalShortcut("Alt+K") do() {.raises: [].}:
    let target = self.getTargetPane()
    if target != nil:
      target.scrollUp()

  self.registerGlobalShortcut("Alt+J") do() {.raises: [].}:
    let target = self.getTargetPane()
    if target != nil:
      target.scrollDown()

  self.registerPaneShortcut("Ctrl+Shift+\\") do(target: Pane) {.raises: [].}:
    try: self.paneManager.splitRow(target)
    except: discard

  self.registerPaneShortcut("F3") do(target: Pane) {.raises: [].}:
    if self.nimSuggest == nil: return
    try: target.triggerGotoDefinition(self.nimSuggest)
    except: discard

  self.registerPaneShortcut("Ctrl+Space") do(target: Pane) {.raises: [].}:
    if self.nimSuggest == nil: return
    try: target.triggerAutocomplete(self.nimSuggest)
    except: discard

  self.registerPaneShortcut("Ctrl+F3") do(target: Pane) {.raises: [].}:
    try: target.triggerPrototype()
    except: discard

  self.registerPaneShortcut("Ctrl+=") do(target: Pane) {.raises: [].}:
    target.zoomIn()

  self.registerPaneShortcut("Ctrl+-") do(target: Pane) {.raises: [].}:
    target.zoomOut()

  self.paneManager.addColumn()  # initialize at least one
  self.paneManager.equalizeSplits()

  let appInstance = QApplication(h: QCoreApplication.instance().h, owned: false)
  appInstance.onFocusChanged do(old, now: QWidget):
    try:
      self.paneManager.updateFocus(now, self.theme == Dark)
    except: 
      discard

proc show*(self: Application) =
  self.root.show()
