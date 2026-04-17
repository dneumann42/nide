import commands
import nide/panemanager
import nide/application/[application, application_types, filetreeops]
import nide/dialogs/[graphdialog, moduledialog, projectdialog, themedialog]
import nide/editor/[buffers, sexpr_parse]
import nide/helpers/[debuglog, logparser, qtconst, runner, widgetref]
import nide/navigation/rgfinder
import nide/nim/nimsuggest
import nide/pane/pane
import nide/project/[filefinder, projects]
import nide/settings/[projectconfig, settings, syntaxtheme, theme, toolchain]
import nide/ui/[commandpalette, filepreview, filetree, opacity, toolbar, widgets]
import seaqt/[qabstractbutton, qapplication, qcoreapplication, qfiledialog, qfilesystemwatcher, qguiapplication, qmainwindow, qmessagebox, qplaintextedit, qresizeevent, qsplitter, qtextcursor, qtextdocument, qtextedit, qtimer, qtoolbar, qtoolbutton, qwidget]
import std/[os, strutils]
import tools/nim_graph

proc createStatusButton(self: Application, text: string, parentH: pointer): WidgetRef[QToolButton] =
  var btn = newWidget(QToolButton.create())
  btn.asButton.setText(text)
  btn.asWidget.setParent(QWidget(h: parentH, owned: false))
  btn.asWidget.hide()
  capture(btn)

proc setupLoaderTimer(self: Application) =
  self.loaderTimer = newWidget(QTimer.create())
  self.loaderTimer.setInterval(LoaderIntervalMs)
  let appRef = self
  self.loaderTimer.onTimeout do() {.raises: [].}:
    var isLoading = appRef.projectCheckProcessH[] != nil
    if not isLoading and appRef.nimSuggest != nil:
      let ns = appRef.nimSuggest
      isLoading = ns.state == csStarting or ns.pending.len > 0
    appRef.toolbar.setLoading(isLoading)
  self.loaderTimer.start()

proc setupSessionSaveTimer(self: Application) =
  self.sessionSaveTimer = newWidget(QTimer.create())
  self.sessionSaveTimer.setInterval(SessionSaveDebounceMs)
  self.sessionSaveTimer.setSingleShot(true)
  self.sessionSaveTimer.onTimeout do() {.raises: [].}:
    self.saveLastSessionNow()

proc createCentralSplitter(
    self: Application,
    fileTreeCell: ref FileTree,
    commandPaletteCell: ref CommandPalette): QSplitter =
  var splitterVtbl = new QSplitterVTable
  splitterVtbl.resizeEvent = proc(self: QSplitter, e: QResizeEvent) {.raises: [], gcsafe.} =
    QSplitterresizeEvent(self, e)
    if fileTreeCell[] != nil and fileTreeCell[].isVisible():
      {.cast(gcsafe).}: fileTreeCell[].reposition()
    if commandPaletteCell[] != nil and commandPaletteCell[].isOpen():
      {.cast(gcsafe).}: commandPaletteCell[].reposition()

  result = newWidget(QSplitter.create(Horizontal, vtbl = splitterVtbl))
  result.setHandleWidth(SplitterHandleWidth)
  result.asWidget.setAutoFillBackground(true)
  result.asWidget.setStyleSheet("QSplitter::handle { background: #333333; }")
  self.root.setCentralWidget(result.asWidget)

proc setupPaneManager(self: Application, splitter: QSplitter) =
  self.paneManager = PaneManager.init(splitter, PaneCallbacks(
    onFileSelected: proc(pane: Pane, path: string) {.raises: [].} =
      self.openInPane(pane, path),
    onNewModule: proc(pane: Pane) {.raises: [].} =
      let path = showNewModuleDialog(self.appWidget())
      if path.len > 0:
        self.openInPane(pane, path),
    onOpenModule: proc(pane: Pane) {.raises: [].} =
      showFileFinder(self.appWidget(),
        self.projectManager.recentFilesFor(self.currentProject),
        proc(path: string) {.raises: [].} =
          self.openInPane(pane, path)),
    onNewProject: proc(pane: Pane) {.raises: [].} =
      showNewProjectDialog(self.appWidget(), self.projectManager),
    onOpenProject: proc(pane: Pane) {.raises: [].} =
      self.openProject(),
    onOpenRecentProject: proc(pane: Pane, path: string) {.raises: [].} =
      self.openProject(path),
    onGotoDefinition: proc(pane: Pane, path: string, line: int, col: int) {.raises: [].} =
      self.navigateToLocation(pane, path, line, col),
    onJumpBack: proc(pane: Pane, path: string, line: int, col: int) {.raises: [].} =
      pane.pushJumpLocation(pane.jumpFuture)
      self.navigateToLocation(pane, path, line, col),
    onJumpForward: proc(pane: Pane, path: string, line: int, col: int) {.raises: [].} =
      pane.pushJumpLocation(pane.jumpHistory)
      self.navigateToLocation(pane, path, line, col),
    onFindFile: proc(pane: Pane) {.raises: [].} =
      showFileFinder(self.appWidget(),
        self.projectManager.recentFilesFor(self.currentProject)) do(path: string) {.raises: [].}:
        self.openInPane(pane, path),
    onSwitchBuffer: proc(pane: Pane) {.raises: [].} =
      var entries: seq[(string, string)]
      let cwd = try: getCurrentDir() except OSError: ""
      for buf in self.bufferManager:
        var display = buf.name
        if cwd.len > 0:
          try: display = relativePath(buf.name, cwd)
          except CatchableError: discard
        entries.add((display, buf.name))
      if entries.len == 0:
        return
      showBufferFinder(self.appWidget(), entries) do(key: string) {.raises: [].}:
        for buf in self.bufferManager:
          if buf.name == key:
            pane.setBuffer(buf)
            self.requestSessionSave()
            break,
    onRestoreLastSession: proc(pane: Pane) {.raises: [].} =
      discard pane
      self.restoreLastSession(),
    onPaneStateChanged: proc(pane: Pane) {.raises: [].} =
      discard pane
      self.requestSessionSave(),
    onLayoutChanged: proc() {.raises: [].} =
      self.requestSessionSave(),
    resolveNimCommand: proc(): string {.raises: [].} =
      self.resolvedProjectToolchain().nimCommand,
    resolveNimBackend: proc(): string {.raises: [].} =
      if self.currentProjectBackend.len > 0: self.currentProjectBackend else: "c"
  ))
  self.paneManager.setEditorFont(
    self.settings.appearance.font,
    self.settings.appearance.fontSize)
  self.paneManager.setLineNumbersVisible(
    self.settings.appearance.lineNumbers)
  self.paneManager.setEditorWheelScrollSpeed(
    self.settings.appearance.editorWheelScrollSpeed)

proc setupCommandDispatcher(self: Application) =
  let disp = CommandDispatcher()
  registerBindings(disp, self.settings.keybindingScheme)
  disp.applyCustomBindings(self.settings.keybindings.toTable())
  self.paneManager.dispatcher = disp

  proc moveTarget(op: cint) {.raises: [].} =
    let p = self.getTargetPane()
    if p == nil:
      return
    discard p.moveCursor(cint(op))

  # proc moveTarget(op: QTextCursorMoveOperationEnum) {.raises: [].} =
  #   moveTarget(cint(op))

  disp.register("editor.chordCx", "Prefix: C-x") do() {.raises: [].}:
    disp.inChord = true

  disp.register("editor.commandPalette", "Command Palette") do() {.raises: [].}:
    if self.commandPalette != nil:
      self.commandPalette.open()

  disp.register("editor.setMark", "Set Mark") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p != nil:
      p.activateMark()

  disp.register("editor.rectangleMark", "Rectangle Mark") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p != nil:
      p.activateRectangleMark()

  disp.register("editor.forwardChar", "Move Forward Char") do() {.raises: [].}:
    moveTarget(QTextCursorMoveOperationEnum.Right)
  disp.register("editor.backwardChar", "Move Backward Char") do() {.raises: [].}:
    moveTarget(QTextCursorMoveOperationEnum.Left)
  disp.register("editor.nextLine", "Move Next Line") do() {.raises: [].}:
    moveTarget(QTextCursorMoveOperationEnum.Down)
  disp.register("editor.prevLine", "Move Previous Line") do() {.raises: [].}:
    moveTarget(QTextCursorMoveOperationEnum.Up)
  disp.register("editor.beginningOfLine", "Move to Beginning of Line") do() {.raises: [].}:
    moveTarget(QTextCursorMoveOperationEnum.StartOfLine)
  disp.register("editor.endOfLine", "Move to End of Line") do() {.raises: [].}:
    moveTarget(QTextCursorMoveOperationEnum.EndOfLine)
  disp.register("editor.forwardWord", "Move Forward Word") do() {.raises: [].}:
    moveTarget(QTextCursorMoveOperationEnum.NextWord)
  disp.register("editor.backwardWord", "Move Backward Word") do() {.raises: [].}:
    moveTarget(QTextCursorMoveOperationEnum.PreviousWord)
  disp.register("editor.beginningOfBuffer", "Move to Beginning of Buffer") do() {.raises: [].}:
    moveTarget(QTextCursorMoveOperationEnum.Start)
  disp.register("editor.endOfBuffer", "Move to End of Buffer") do() {.raises: [].}:
    moveTarget(QTextCursorMoveOperationEnum.End)

  disp.register("editor.scrollDown", "Scroll Down") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p != nil:
      p.scrollDown()
  disp.register("editor.scrollUp", "Scroll Up") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p != nil:
      p.scrollUp()

  disp.register("editor.deleteForwardChar", "Delete Forward Char") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p == nil:
      return
    p.clearMarkState(clearNativeSelection = false)
    let ed = QPlainTextEdit(h: p.editor.h, owned: false)
    let c = ed.textCursor()
    c.deleteChar()
    ed.setTextCursor(c)

  disp.register("editor.killLine", "Kill Line") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p == nil:
      return
    p.clearMarkState()
    let ed = QPlainTextEdit(h: p.editor.h, owned: false)
    let c = ed.textCursor()
    discard c.movePosition(cint(QTextCursorMoveOperationEnum.EndOfLine),
                           cint(QTextCursorMoveModeEnum.KeepAnchor))
    if c.hasSelection():
      c.removeSelectedText()
    else:
      c.deleteChar()
    ed.setTextCursor(c)

  disp.register("editor.copySelection", "Copy Selection") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p == nil:
      return
    p.copyRegion()
    p.clearMarkState()

  disp.register("editor.killWordForward", "Kill Word Forward") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p == nil:
      return
    p.clearMarkState()
    let ed = QPlainTextEdit(h: p.editor.h, owned: false)
    let c = ed.textCursor()
    discard c.movePosition(cint(QTextCursorMoveOperationEnum.NextWord),
                           cint(QTextCursorMoveModeEnum.KeepAnchor))
    c.removeSelectedText()
    ed.setTextCursor(c)

  disp.register("editor.killWordBackward", "Kill Word Backward") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p == nil:
      return
    p.clearMarkState()
    let ed = QPlainTextEdit(h: p.editor.h, owned: false)
    let c = ed.textCursor()
    discard c.movePosition(cint(QTextCursorMoveOperationEnum.PreviousWord),
                           cint(QTextCursorMoveModeEnum.KeepAnchor))
    c.removeSelectedText()
    ed.setTextCursor(c)

  disp.register("editor.openLine", "Open Line") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p == nil:
      return
    if p.buffer == nil:
      p.triggerOpenProject()
      return
    p.clearMarkState()
    let ed = QPlainTextEdit(h: p.editor.h, owned: false)
    let c = ed.textCursor()
    c.insertText("\n")
    discard c.movePosition(cint(QTextCursorMoveOperationEnum.Left),
                           cint(QTextCursorMoveModeEnum.MoveAnchor))
    ed.setTextCursor(c)

  disp.register("editor.recenter", "Recenter Cursor") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p != nil:
      QPlainTextEdit(h: p.editor.h, owned: false).centerCursor()

  disp.register("editor.killRegion", "Kill Region") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p != nil:
      p.killRegion()

  disp.register("editor.yank", "Yank") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p != nil:
      p.clearMarkState(clearNativeSelection = false)
      QPlainTextEdit(h: p.editor.h, owned: false).paste()

  disp.register("editor.saveBuffer", "Save Buffer") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p != nil:
      p.save()

  disp.register("editor.quitApplication", "Quit Application") do() {.raises: [].}:
    QApplication.quit()

  disp.register("editor.killBuffer", "Kill Buffer") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p != nil:
      self.paneManager.closePane(p)

  disp.register("editor.deleteOtherWindows", "Delete Other Windows") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p != nil:
      self.paneManager.closeOtherPanes(p)

  disp.register("editor.deleteWindow", "Delete Window") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p != nil:
      discard self.paneManager.deleteWindow(p)

  disp.register("editor.splitHorizontal", "Split Window Horizontally") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p != nil:
      discard self.paneManager.splitRow(p)

  disp.register("editor.splitVertical", "Split Window Vertically") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p != nil:
      discard self.paneManager.splitCol(p)

  disp.register("editor.findFile", "Find File") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p == nil:
      return
    showFileFinder(self.appWidget(),
      self.projectManager.recentFilesFor(self.currentProject)) do(path: string) {.raises: [].}:
      self.openInPane(p, path)

  disp.register("editor.switchBuffer", "Switch Buffer") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p == nil:
      return
    var entries: seq[(string, string)]
    let cwd = try: getCurrentDir() except OSError: ""
    for buf in self.bufferManager:
      var display = buf.name
      if cwd.len > 0:
        try: display = relativePath(buf.name, cwd)
        except CatchableError: discard
      entries.add((display, buf.name))
    if entries.len == 0:
      return
    showBufferFinder(self.appWidget(), entries) do(key: string) {.raises: [].}:
      for buf in self.bufferManager:
        if buf.name == key:
          p.setBuffer(buf)
          self.requestSessionSave()
          break

  disp.register("editor.otherWindow", "Other Window") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p != nil:
      discard self.paneManager.focusNextPane(p)

  disp.register("editor.findInBuffer", "Find in Buffer") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p != nil:
      p.triggerFind()

  disp.register("editor.closeSearch", "Close Search") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p != nil:
      p.clearMarkState()
      p.closeSearch()

  disp.register("editor.ripgrepFind", "Find in Files") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p == nil:
      return
    showRipgrepFinder(self.appWidget()) do(file: string, lineNum: int) {.raises: [].}:
      self.openInPane(p, file)
      p.scrollToLine(lineNum)

  disp.register("editor.gotoDefinition", "Go to Definition") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p == nil or self.nimSuggest == nil:
      return
    try:
      p.triggerGotoDefinition(self.nimSuggest)
    except CatchableError:
      discard

  disp.register("editor.jumpBack", "Jump Back") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p == nil:
      return
    try:
      p.triggerJumpBack()
    except CatchableError:
      discard

  disp.register("editor.autocomplete", "Autocomplete") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p == nil or self.nimSuggest == nil:
      return
    try:
      p.triggerAutocomplete(self.nimSuggest)
    except CatchableError:
      discard

  disp.register("editor.showPrototype", "Show Prototype") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p == nil:
      return
    try:
      p.triggerPrototype()
    except CatchableError:
      discard

  disp.register("editor.addColumn", "Add Column") do() {.raises: [].}:
    discard self.paneManager.addColumn()
    self.paneManager.equalizeSplits()

  disp.register("editor.toggleFileTree", "Toggle File Tree") do() {.raises: [].}:
    if self.currentProject.len > 0:
      if self.fileTree.isVisible():
        self.fileTree.hidePanel()
      else:
        self.fileTree.showAndFocusPanel()

  disp.register("editor.splitRow", "Split Row") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p == nil:
      return
    try:
      discard self.paneManager.splitRow(p)
    except CatchableError:
      discard

  disp.register("editor.zoomIn", "Zoom In") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p != nil:
      p.zoomIn()

  disp.register("editor.zoomOut", "Zoom Out") do() {.raises: [].}:
    let p = self.getTargetPane()
    if p != nil:
      p.zoomOut()

  self.commandPalette = newCommandPalette(self.appWidget(), disp) do(id: CommandId) {.raises: [].}:
    discard disp.execute(id)
  do() {.raises: [].}:
    let target = self.getTargetPane()
    if target != nil:
      target.focus()
  self.commandPalette.applyTheme(self.theme)

proc wireFileTree(self: Application) =
  self.fileTree.onFileSelected = proc(path: string) {.raises: [].} =
    let target = self.getTargetPane()
    if target == nil:
      return
    self.openInPane(target, path)
    target.focus()
  self.fileTree.canPaste = proc(): bool {.raises: [].} =
    self.canPasteInFileTree()
  self.fileTree.onMoveRequested = proc(sourcePath: string, targetDir: string): bool {.raises: [].} =
    self.moveFileTreeItem(sourcePath, targetDir)
  self.fileTree.onMenuAction = proc(action: FileTreeMenuAction, path: string, isDir: bool) {.raises: [].} =
    case action
    of ftCopy:
      self.copyFileTreeItem(path)
    of ftCut:
      self.cutFileTreeItem(path)
    of ftPaste:
      self.pasteFileTreeItem(path, isDir)
    of ftRename:
      self.renameFileTreeItem(path, isDir)
    of ftDelete:
      self.deleteFileTreeItem(path, isDir)
    of ftNewFile:
      if isDir:
        self.createFileTreeFile(path)
    of ftNewFolder:
      if isDir:
        self.createFileTreeFolder(path)

proc wireStatusButtons(self: Application) =
  self.runStatusBtn = self.createStatusButton("nimble run", self.root.h)
  self.buildStatusBtn = self.createStatusButton("nimble build", self.root.h)

  let runStatusBtn = self.runStatusBtn.get()
  runStatusBtn.onClicked do() {.raises: [].}:
    self.runStatusBtn.get().asWidget.hide()
    if self.runReopen != nil:
      self.runReopen()
      self.runReopen = nil

  let buildStatusBtn = self.buildStatusBtn.get()
  buildStatusBtn.onClicked do() {.raises: [].}:
    self.buildStatusBtn.get().asWidget.hide()
    if self.buildReopen != nil:
      self.buildReopen()
      self.buildReopen = nil

proc wireToolbar(self: Application) =
  proc ensureRunnableProject(action: string): bool {.raises: [].} =
    if self.currentProject.len == 0 or self.projectNimbleFile.len == 0:
      discard QMessageBox.information(
        self.appWidget(),
        action,
        "Open a Nimble project before using toolbar " & action.toLowerAscii() & ".")
      return false
    true

  self.toolbar.onRun do():
    if not ensureRunnableProject("Run"):
      return
    let onBg = proc(reopen: proc() {.raises: [].}) {.raises: [].} =
      self.runReopen = reopen
      let rw = self.appWidget()
      let btn = self.runStatusBtn.get().asWidget
      btn.move(rw.width() - RunStatusOffsetX, rw.height() - RunStatusOffsetY)
      btn.show()
      btn.raiseX()
    let gotoRun = proc(file: string, line, col: int) {.raises: [].} =
      try:
        let target = self.getTargetPane()
        if target == nil:
          return
        self.openInPane(target, file)
        target.jumpToLine(line, col)
      except CatchableError:
        discard
    let toolchain = self.resolvedProjectToolchain()
    let cmd = quoteShell(toolchain.nimbleCommand) & " run"
    runCommand(self.appWidget(), "nimble run", cmd, onBg, gotoRun,
      self.currentProject, allowInput = true)

  self.toolbar.onBuild do():
    if not ensureRunnableProject("Build"):
      return
    let onBg = proc(reopen: proc() {.raises: [].}) {.raises: [].} =
      self.buildReopen = reopen
      let rw = self.appWidget()
      let btn = self.buildStatusBtn.get().asWidget
      btn.move(rw.width() - RunStatusOffsetX, rw.height() - BuildStatusOffsetY)
      btn.show()
      btn.raiseX()
    let gotoBuild = proc(file: string, line, col: int) {.raises: [].} =
      try:
        let target = self.getTargetPane()
        if target == nil:
          return
        self.openInPane(target, file)
        target.jumpToLine(line, col)
      except CatchableError:
        discard
    let toolchain = self.resolvedProjectToolchain()
    let cmd = quoteShell(toolchain.nimbleCommand) & " build"
    runCommand(self.appWidget(), "nimble build", cmd, onBg, gotoBuild, self.currentProject)

  self.toolbar.onGraph do():
    try:
      let srcDir = if self.currentProject.len > 0: self.currentProject / "src"
                   else: getCurrentDir() / "src"
      logDebug("application: graph srcDir: ", srcDir, " exists: ", dirExists(srcDir))
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
      showGraphDialog(self.appWidget(), dot)
    except CatchableError:
      logError("application: graph error: ", getCurrentExceptionMsg())

  self.toolbar.onFileTreeToggle do():
    if self.currentProject.len > 0:
      if self.fileTree.isVisible():
        self.fileTree.hidePanel()
      else:
        self.fileTree.showAndFocusPanel()

  self.toolbar.onTriggered(NewProject) do():
    showNewProjectDialog(self.appWidget(), self.projectManager)

  self.toolbar.onTriggered(NewModule) do():
    if self.paneManager.panels.len > 0:
      self.paneManager.panels[0].triggerNewModule()

  self.toolbar.onTriggered(OpenModule) do():
    if self.paneManager.panels.len > 0:
      self.paneManager.panels[0].triggerOpenModule()

  self.toolbar.onTriggered(OpenFile) do():
    let file = QFileDialog.getOpenFileName(
      self.appWidget(), "", "", "All files (*.*)")
    if file.len == 0:
      return
    let target = self.getTargetPane()
    if target == nil:
      return
    self.openInPane(target, file)

  self.toolbar.onTriggered(OpenProject) do():
    self.openProject()

  self.toolbar.onTriggered(CloseProject) do():
    self.closeProject()

  self.toolbar.onTriggered(Quit) do():
    QApplication.quit()

  self.toolbar.onTriggered(SyntaxTheme) do():
    showThemeDialog(
      self.appWidget(),
      currentThemeName,
      proc(name: string) {.raises: [].} =
        try:
          setCurrentTheme(name)
          self.bufferManager.rehighlightAll()
          for panel in self.paneManager.panels:
            panel.applyEditorTheme()
        except CatchableError:
          discard
    )

  self.toolbar.onNewPane do():
    discard self.paneManager.addColumn()
    self.paneManager.equalizeSplits()

  self.toolbar.onSettings do():
    showSettingsDialog(
      self.appWidget(),
      self.settings,
      self.currentProject,
      self.projectConfig,
      proc(updated: Settings, projectConfig: ProjectConfig) {.raises: [].} =
        let previousSettings = self.settings
        let previousProjectConfig = self.projectConfig
        let themeModeChanged =
          previousSettings.appearance.themeMode != updated.appearance.themeMode
        let syntaxThemeChanged =
          previousSettings.appearance.syntaxTheme != updated.appearance.syntaxTheme
        let editorFontChanged =
          previousSettings.appearance.font != updated.appearance.font or
          previousSettings.appearance.fontSize != updated.appearance.fontSize
        let lineNumbersChanged =
          previousSettings.appearance.lineNumbers != updated.appearance.lineNumbers
        let wheelSpeedChanged =
          previousSettings.appearance.editorWheelScrollSpeed != updated.appearance.editorWheelScrollSpeed
        let opacityChanged =
          previousSettings.appearance.opacityEnabled != updated.appearance.opacityEnabled or
          previousSettings.appearance.opacityLevel != updated.appearance.opacityLevel
        let keybindingsChanged =
          previousSettings.keybindingScheme != updated.keybindingScheme or
          previousSettings.keybindings != updated.keybindings
        let nimSettingsChanged =
          previousSettings.nim != updated.nim
        let projectConfigChanged =
          previousProjectConfig != projectConfig

        self.settings = updated
        self.theme = updated.appearance.themeMode
        self.settings.write()
        if self.currentProject.len > 0 and projectConfigChanged:
          self.projectConfig = projectConfig
          saveProjectConfig(self.currentProject, self.projectConfig)
        elif self.currentProject.len > 0:
          self.projectConfig = projectConfig

        if themeModeChanged:
          applyTheme(self.theme)
          self.toolbar.applyTheme(self.theme)
          if self.fileTree != nil:
            self.fileTree.applyTheme(self.theme)
          if self.commandPalette != nil:
            self.commandPalette.applyTheme(self.theme)
          self.paneManager.updateFocus(QApplication.focusWidget(), self.theme)

        if syntaxThemeChanged:
          setCurrentTheme(updated.appearance.syntaxTheme)
          self.bufferManager.rehighlightAll()
          for pane in self.paneManager.panels:
            pane.applyEditorTheme()

        if editorFontChanged:
          self.paneManager.setEditorFont(
            updated.appearance.font,
            updated.appearance.fontSize)

        if lineNumbersChanged:
          self.paneManager.setLineNumbersVisible(
            updated.appearance.lineNumbers)

        if wheelSpeedChanged:
          self.paneManager.setEditorWheelScrollSpeed(
            updated.appearance.editorWheelScrollSpeed)

        if opacityChanged:
          self.opacityEffect.applyOpacity(
            updated.appearance.opacityEnabled,
            updated.appearance.opacityLevel)

        let disp = self.paneManager.dispatcher
        if disp != nil and keybindingsChanged:
          disp.resetBindings()
          registerBindings(disp, updated.keybindingScheme)
          disp.applyCustomBindings(updated.keybindings.toTable())
          if self.commandPalette != nil:
            self.commandPalette.refreshItems()

        if self.currentProject.len > 0 and (nimSettingsChanged or projectConfigChanged):
          self.restartProjectNimIntegration()
          self.runProjectCheck()
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

  self.toolbar.onTriggered(CleanImports) do():
    let target = self.getTargetPane()
    if target != nil:
      target.triggerCleanImports()

  self.toolbar.onTriggered(RefreshDiags) do():
    self.runProjectCheck()

  self.toolbar.onDiagHint do():
    self.toolbar.showDiagPopover(self.toolbar.widget().h, self.projectDiagLines[], llHint)

  self.toolbar.onDiagWarn do():
    self.toolbar.showDiagPopover(self.toolbar.widget().h, self.projectDiagLines[], llWarning)

  self.toolbar.onDiagErr do():
    self.toolbar.showDiagPopover(self.toolbar.widget().h, self.projectDiagLines[], llError)

  self.toolbar.onDiagNavigate do(path: string, line, col: int) {.raises: [].}:
    let pane = self.getTargetPane()
    if pane == nil:
      return
    self.navigateToLocation(pane, path, line, col)

proc wireInitialState(self: Application) =
  discard self.paneManager.addColumn()
  self.paneManager.equalizeSplits()
  self.updateRecentProjects()
  self.updateRestoreSessionAvailability()
  self.sessionPersistenceReady = true
  if self.settings.restoreLastSessionOnLaunch:
    self.restoreLastSession()

proc wireFileWatcher(self: Application) =
  self.fileWatcher.onFileChanged do(path: openArray[char]):
    when defined(debugFileWatcher):
      echo "[FileWatcher] fileChanged signal received!"
    let p = filefinder.toStr(path)
    when defined(debugFileWatcher):
      echo "[FileWatcher] path: ", p
    var added = self.fileWatcher.addPath(p)
    when defined(debugFileWatcher):
      echo "[FileWatcher] re-add result: ", added, ", files: ", self.fileWatcher.files()
    if not added:
      when defined(debugFileWatcher):
        echo "[FileWatcher] re-add failed, retrying..."
      sleep(FileWatcherRetryMs)
      added = self.fileWatcher.addPath(p)
      when defined(debugFileWatcher):
        echo "[FileWatcher] re-add retry result: ", added, ", files: ", self.fileWatcher.files()
    var buf: Buffer
    for b in self.bufferManager:
      if b.path == p:
        buf = b
        break
    if buf == nil:
      when defined(debugFileWatcher):
        echo "[FileWatcher] buffer not found for path: ", p
      return
    when defined(debugFileWatcher):
      echo "[FileWatcher] buffer found: ", buf.name
    var dirty = false
    for panel in self.paneManager.panels:
      if panel.buffer == buf:
        if buf.kind == bkText and QPlainTextEdit(h: panel.editor.h, owned: false).document().isModified():
          dirty = true
          break
        if buf.kind == bkSExpr and buf.sexprDocument().dirty:
          dirty = true
          break
    if dirty:
      buf.externallyModified = true
      when defined(debugFileWatcher):
        echo "[FileWatcher] buffer dirty, marking externallyModified"
    else:
      if buf.kind == bkImage:
        var readOk = false
        for i in 0..<FileReadRetries:
          try:
            let (ok, pixmap) = loadImagePixmap(p)
            if ok:
              buf.setPixmap(pixmap)
              readOk = true
              break
          except CatchableError:
            when defined(debugFileWatcher):
              echo "[FileWatcher] retry image reload attempt ", i + 1, ": ", getCurrentExceptionMsg()
          sleep(FileWatcherRetryMs)
        if readOk:
          buf.externallyModified = false
          for panel in self.paneManager.panels:
            if panel.buffer == buf:
              panel.setBuffer(buf)
          when defined(debugFileWatcher):
            echo "[FileWatcher] reloaded image from: ", p
        else:
          buf.externallyModified = true
          when defined(debugFileWatcher):
            echo "[FileWatcher] failed to reload image after retries"
      elif buf.kind == bkSExpr:
        var content = ""
        var readOk = false
        for i in 0..<FileReadRetries:
          try:
            content = readFile(p)
            readOk = true
            break
          except CatchableError:
            when defined(debugFileWatcher):
              echo "[FileWatcher] retry sexpr readFile attempt ", i + 1, ": ", getCurrentExceptionMsg()
            sleep(FileWatcherRetryMs)
        if readOk:
          buf.sexpr = parseSExpr(content)
          buf.externallyModified = false
          for panel in self.paneManager.panels:
            if panel.buffer == buf:
              panel.setBuffer(buf)
        else:
          buf.externallyModified = true
      else:
        var content = ""
        var readOk = false
        for i in 0..<FileReadRetries:
          try:
            content = readFile(p)
            readOk = true
            break
          except CatchableError:
            when defined(debugFileWatcher):
              echo "[FileWatcher] retry readFile attempt ", i + 1, ": ", getCurrentExceptionMsg()
            sleep(FileWatcherRetryMs)
        if readOk:
          if content != buf.document().toPlainText():
            buf.document().setPlainText(content)
          buf.document().setModified(false)
          buf.externallyModified = false
          when defined(debugFileWatcher):
            echo "[FileWatcher] reloaded content from: ", p
        else:
          buf.externallyModified = true
          when defined(debugFileWatcher):
            echo "[FileWatcher] failed to read after retries, marking externallyModified"

proc wireFocusTracking(self: Application) =
  let appInstance = QApplication(h: QCoreApplication.instance().h, owned: false)
  appInstance.onFocusChanged do(old, now: QWidget):
    try:
      self.paneManager.updateFocus(now, self.theme)
      discard old
      self.requestSessionSave()
    except CatchableError:
      discard

proc build*(self: Application) =
  self.root = QMainWindow.create()
  self.root.asWidget.setMinimumSize(MinWindowWidth, MinWindowHeight)
  self.toolbar.build()
  self.toolbar.setCloseProjectVisible(false)
  self.root.addToolBar(QToolBar(h: self.toolbar.widget().h, owned: false))

  self.setupLoaderTimer()
  self.setupSessionSaveTimer()

  var fileTreeCell: ref FileTree
  new(fileTreeCell)
  var commandPaletteCell: ref CommandPalette
  new(commandPaletteCell)

  let splitter = self.createCentralSplitter(fileTreeCell, commandPaletteCell)

  self.fileTree = newFileTree(self.root)
  self.fileTree.splitterH = self.root.h
  fileTreeCell[] = self.fileTree

  self.theme = Dark
  applyTheme(self.theme)
  self.toolbar.applyTheme(self.theme)

  logInfo("application: Loading settings...")
  self.settings = Settings.load()
  self.theme = self.settings.appearance.themeMode
  applyTheme(self.theme)
  self.toolbar.applyTheme(self.theme)
  self.fileTree.applyTheme(self.theme)

  self.opacityEffect = setupWindowOpacity(
    self.appWidget(),
    splitter.asWidget,
    self.settings.appearance.opacityEnabled,
    self.settings.appearance.opacityLevel)

  initDefaultTheme()
  setCurrentTheme(self.settings.appearance.syntaxTheme)

  self.setupPaneManager(splitter)
  self.paneManager.updateFocus(QApplication.focusWidget(), self.theme)
  self.setupCommandDispatcher()
  commandPaletteCell[] = self.commandPalette
  self.wireFileTree()
  self.wireStatusButtons()
  self.wireToolbar()
  self.wireInitialState()
  self.wireFileWatcher()
  self.wireFocusTracking()
