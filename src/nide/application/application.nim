import commands, toml_serialization
import nide/application/application_types
export application_types
import nide/panemanager
import nide/application/sessionops
import nide/editor/buffers
import nide/helpers/[debuglog, fspaths, logparser, qtconst, runner, widgetref]
import nide/navigation/[rgfinder, sessionstate]
import nide/nim/[nimcheck, nimproject, nimsuggest]
import nide/pane/pane
import nide/project/[filefinder, projects]
import nide/settings/[projectconfig, settings, syntaxtheme, theme, toolchain]
import nide/ui/[commandpalette, filetree, opacity, toolbar, widgets]
import seaqt/[qabstractbutton, qapplication, qclipboard, qcoreapplication, qfiledialog, qfilesystemwatcher, qgraphicsopacityeffect, qguiapplication, qinputdialog, qkeysequence, qmainwindow, qmessagebox, qobject, qplaintextedit, qprocess, qresizeevent, qshortcut, qsplitter, qtextcursor, qtextdocument, qtextedit, qtimer, qtoolbar, qtoolbutton, qwidget]
import std/[options, os, strutils]

proc getTargetPane*(self: Application): Pane {.raises: [].} =
  result = self.paneManager.lastFocusedPane
  if result == nil and self.paneManager.panels.len > 0:
    result = self.paneManager.panels[0]

proc getOrCreateTargetPane*(self: Application): Pane {.raises: [].} =
  self.getTargetPane()

proc openFile*(self: Application, path: string): Buffer {.raises: [].} =
  result = self.bufferManager.openFile(path)
  when defined(debugFileWatcher):
    echo "[FileWatcher] openFile: ", path
  if result.path.len > 0:
    let added = self.fileWatcher.addPath(result.path)
    when defined(debugFileWatcher):
      echo "[FileWatcher] addPath result: ", added, ", files: ", self.fileWatcher.files()
    if self.currentProject.len > 0:
      self.projectManager.recordOpenedFile(self.currentProject, result.path)

proc updateRestoreSessionAvailability*(self: Application) {.raises: [].} =
  let available = hasLastSession()
  if self.paneManager == nil:
    return
  for panel in self.paneManager.panels:
    panel.setRestoreLastSessionAvailable(available)

proc saveLastSessionNow*(self: Application) {.raises: [].} =
  if self.restoringSession or not self.sessionPersistenceReady or self.paneManager == nil:
    return
  saveLastSession(buildLastSession(self.paneManager, self.projectNimbleFile))
  self.updateRestoreSessionAvailability()

proc requestSessionSave*(self: Application) {.raises: [].} =
  if self.restoringSession or not self.sessionPersistenceReady:
    return
  if self.sessionSaveTimer.h == nil:
    self.saveLastSessionNow()
  else:
    self.sessionSaveTimer.start()

proc pushJumpLocation*(pane: Pane, target: var seq[JumpLocation]) {.raises: [].} =
  if pane.buffer != nil and pane.buffer.path.len > 0:
    try:
      let ed = QPlainTextEdit(h: pane.editor.h, owned: false)
      let cur = ed.textCursor()
      target.add(JumpLocation(
        file: pane.buffer.path,
        line: cur.blockNumber() + 1,
        col:  cur.columnNumber()))
    except CatchableError: discard

proc openInPane*(self: Application, pane: Pane, path: string) {.raises: [].} =
  try:
    let buf = self.openFile(path)
    pane.setBuffer(buf)
    if path.len > 0 and self.projectDiagLines != nil:
      var prefill: seq[LogLine]
      for ll in self.projectDiagLines[]:
        if ll.file == path: prefill.add(ll)
      if prefill.len > 0:
        pane.prefillDiags(prefill)
    self.requestSessionSave()
  except CatchableError: discard

proc navigateToLocation*(self: Application, pane: Pane, path: string, line, col: int) {.raises: [].} =
  if path.len > 0:
    self.openInPane(pane, path)
  pane.scrollToLine(line, col)

proc registerPaneShortcut*(self: Application, sequence: string, callback: proc(target: Pane): void {.raises: [].}) {.raises: [].} =
  var sc = newWidget(QShortcut.create(QKeySequence.create(sequence),
                                      QObject(h: self.root.h, owned: false)))
  sc.setContext(SC_WindowShortcut)
  sc.onActivated do() {.raises: [].}:
    let target = self.getTargetPane()
    if target != nil and not (target.dispatcher != nil and target.dispatcher.inChord):
      callback(target)

proc registerGlobalShortcut*(self: Application, sequence: string, callback: proc(): void {.raises: [].}) {.raises: [].} =
  var sc = newWidget(QShortcut.create(QKeySequence.create(sequence),
                                      QObject(h: self.root.h, owned: false)))
  sc.setContext(SC_WindowShortcut)
  sc.onActivated do() {.raises: [].}:
    let target = self.getTargetPane()
    if target != nil and target.dispatcher != nil and target.dispatcher.inChord: return
    callback()

proc buffers*(app: Application): lent BufferManager {.raises: [].} =
  result = app.bufferManager

proc new*(T: typedesc[Application]): T =
  result = T(
    bufferManager: BufferManager.init(),
    toolbar: Toolbar(),
    projectManager: ProjectManager.init()
  )
  result.projectManager.load()
  result.fileWatcher = QFileSystemWatcher.create()
  new(result.projectDiagLines)
  result.projectDiagLines[] = @[]
  new(result.projectCheckProcessH)
  result.projectCheckProcessH[] = nil

proc updateRecentProjects*(self: Application) {.raises: [].} =
  for panel in self.paneManager.panels:
    panel.setRecentProjects(self.projectManager.recentProjects)

proc resolvedProjectToolchain*(self: Application): ResolvedToolchain {.raises: [].} =
  resolveProjectToolchain(
    getNimPath(self.settings),
    getNimblePath(self.settings),
    self.currentProject,
    self.projectConfig
  )

proc restartProjectNimIntegration*(self: Application) {.raises: [].} =
  if self.projectNimbleFile.len == 0:
    return

  if self.nimSuggest != nil:
    self.nimSuggest.kill()

  var entryFile = findProjectMain(self.projectNimbleFile)
  if entryFile.len == 0:
    entryFile = findNimbleEntry(self.projectNimbleFile)

  let toolchain = self.resolvedProjectToolchain()
  logDebug("application: restartProjectNimIntegration backend=", self.currentProjectBackend,
    " nim=", toolchain.nimCommand,
    " nimble=", toolchain.nimbleCommand,
    " nimsuggest=", toolchain.nimsuggestCommand,
    " source=", toolchain.source)
  self.nimSuggest = NimSuggestClient.new(
    self.root.h,
    entryFile,
    toolchain.nimsuggestCommand,
    self.currentProjectBackend,
    debug = false)
  startNimSuggest(self.nimSuggest)
  self.paneManager.nimSuggest = self.nimSuggest
  for panel in self.paneManager.panels:
    panel.nimSuggest = self.nimSuggest

proc runProjectCheck*(self: Application) {.raises: [].} =
  if self.projectNimbleFile.len == 0: return
  let mainFile = findProjectMain(self.projectNimbleFile)
  if mainFile.len == 0: return
  if self.projectCheckProcessH[] != nil:
    try: QProcess(h: self.projectCheckProcessH[], owned: false).kill()
    except CatchableError: discard
    self.projectCheckProcessH[] = nil
  let toolchain = self.resolvedProjectToolchain()
  runNimCheck(self.root.h, mainFile, toolchain.nimCommand, self.currentProjectBackend, self.projectCheckProcessH,
    proc(lines: seq[LogLine]) {.raises: [].} =
      self.projectDiagLines[] = lines
      self.toolbar.updateDiagCounts(lines))

proc openProject*(self: Application, path: string, restoreMode = false) {.raises: [].} =
  let dir = path.parentDir()
  self.currentProject = dir
  self.projectNimbleFile = path
  self.currentProjectBackend = projectBackend(path)
  self.projectConfig = loadProjectConfig(dir)
  logDebug("application: openProject nimble=", path,
    " backend=", self.currentProjectBackend,
    " useSystemNim=", self.projectConfig.useSystemNim,
    " projectNimPath=", self.projectConfig.nimPath,
    " projectNimblePath=", self.projectConfig.nimblePath)
  for panel in self.paneManager.panels:
    panel.clearBuffer()
  self.paneManager.setProjectOpen(true)
  self.bufferManager = BufferManager.init()
  try: setCurrentDir(dir) except OSError: discard
  self.toolbar.setProjectName(dir.lastPathPart)
  self.projectManager.recordOpenedProject(path)
  self.fileTree.setRoot(dir)
  self.toolbar.setFileTreeEnabled(true)
  self.toolbar.applyTheme(self.theme)
  self.restartProjectNimIntegration()
  if not restoreMode:
    self.paneManager.panels[0].triggerOpenModule()
  self.toolbar.setCloseProjectVisible(true)
  self.runProjectCheck()
  self.requestSessionSave()

proc openProject*(self: Application) {.raises: [].} =
  let file = QFileDialog.getOpenFileName(
    self.appWidget(), "", "", "Nimble files (*.nimble)")
  if file.len == 0: return
  self.openProject(file)

proc closeProject*(self: Application) {.raises: [].} =
  self.currentProject = ""
  self.projectNimbleFile = ""
  self.currentProjectBackend = ""
  self.projectConfig = ProjectConfig()
  for panel in self.paneManager.panels:
    panel.clearBuffer()
  self.paneManager.setProjectOpen(false)
  self.bufferManager = BufferManager.init()
  self.toolbar.setProjectName("—")
  self.fileTree.setRoot("")
  self.toolbar.setFileTreeEnabled(false)
  self.toolbar.applyTheme(self.theme)
  if self.nimSuggest != nil:
    self.nimSuggest.kill()
    self.nimSuggest = nil
  self.paneManager.nimSuggest = nil
  for panel in self.paneManager.panels:
    panel.nimSuggest = nil
  self.toolbar.setCloseProjectVisible(false)
  self.projectDiagLines[] = @[]
  self.toolbar.updateDiagCounts(@[])
  self.requestSessionSave()

proc prepareForSessionRestore*(self: Application): Pane =
  if self.currentProject.len > 0:
    self.closeProject()
  if self.paneManager.panels.len == 0:
    result = self.paneManager.addColumn()
  else:
    result = self.paneManager.panels[0]
  self.paneManager.closeOtherPanes(result)
  result.clearBuffer()

proc restoreLastSession*(self: Application) {.raises: [].} =
  let loaded = loadLastSession()
  if loaded.isNone():
    self.updateRestoreSessionAvailability()
    return

  let session = loaded.get()
  self.restoringSession = true
  try:
    var layout = session.columns
    if layout.len == 0:
      layout = @[SavedColumnSession(panes: @[SavedPaneSession()])]
    elif layout[0].panes.len == 0:
      layout[0].panes = @[SavedPaneSession()]

    var firstPane = self.prepareForSessionRestore()
    if session.projectNimbleFile.len > 0 and fileExists(session.projectNimbleFile):
      self.openProject(session.projectNimbleFile, restoreMode = true)
      if self.paneManager.panels.len > 0:
        firstPane = self.paneManager.panels[0]

    let paneGrid = restoreSessionLayout(self.paneManager, layout, firstPane)

    for colIdx, savedColumn in layout:
      if colIdx >= paneGrid.len:
        break
      for rowIdx, savedPane in savedColumn.panes:
        if rowIdx >= paneGrid[colIdx].len:
          break
        let pane = paneGrid[colIdx][rowIdx]
        if savedPane.filePath.len > 0 and fileExists(savedPane.filePath):
          self.openInPane(pane, savedPane.filePath)
          pane.restoreViewState(savedPane.cursorLine, savedPane.cursorColumn,
                                savedPane.verticalScroll, savedPane.horizontalScroll)
        else:
          pane.clearBuffer()

    let focusPane = resolveFocusPane(
      paneGrid,
      session.activeColumnIndex,
      session.activePaneIndex)
    if focusPane.isSome():
      focusPane.get().focus()
  finally:
    self.restoringSession = false

  self.saveLastSessionNow()

proc closeBuffer*(self: Application, name: string) {.raises: [].} =
  for panel in self.paneManager.panels:
    if panel.buffer != nil and panel.buffer.name == name:
      panel.clearBuffer()
  self.bufferManager.close(name)
  self.requestSessionSave()

import nide/application/filetreeops

proc show*(self: Application) =
  self.root.show()
