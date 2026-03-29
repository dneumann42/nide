import buffers, commands, filefinder, filetree, graphdialog, logparser, moduledialog, nimcheck, nimproject, nimsuggest, opacity, pane/pane, panemanager, projectdialog, projects, rgfinder, runner, sessionstate, settings, syntaxtheme, theme, themedialog, toml_serialization, toolbar, widgetref
import seaqt/[qabstractbutton, qapplication, qcoreapplication, qfiledialog, qfilesystemwatcher, qgraphicsopacityeffect, qinputdialog, qkeysequence, qmainwindow, qmessagebox, qobject, qplaintextedit, qprocess, qresizeevent, qshortcut, qsplitter, qtextcursor, qtextdocument, qtextedit, qtimer, qtoolbar, qtoolbutton, qwidget]
import std/[options, os, strutils]

import "../../tools/nim_graph" as nim_graph

type
  FileTreeClipboardMode = enum
    ftcNone, ftcCopy, ftcCut

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
    projectNimbleFile: string
    runStatusBtn:  WidgetRef[QToolButton]
    buildStatusBtn: WidgetRef[QToolButton]
    runReopen:  proc() {.raises: [].}
    buildReopen: proc() {.raises: [].}
    opacityEffect: QGraphicsOpacityEffect
    nimSuggest: NimSuggestClient
    settings: Settings
    fileWatcher: QFileSystemWatcher
    loaderTimer: QTimer
    projectDiagLines: ref seq[LogLine]
    projectCheckProcessH: ref pointer
    fileTreeClipboardPath: string
    fileTreeClipboardMode: FileTreeClipboardMode
    sessionSaveTimer: QTimer
    sessionPersistenceReady: bool
    restoringSession: bool

proc appWidget(self: Application): QWidget =
  QWidget(h: self.root.h, owned: false)

proc pathExistsAny(path: string): bool =
  fileExists(path) or dirExists(path)

proc normalizedFsPath(path: string): string =
  try:
    result = normalizePathEnd(normalizedPath(absolutePath(path)), false)
  except CatchableError:
    result = normalizePathEnd(normalizedPath(path), false)
  when defined(windows):
    result = result.toLowerAscii()

proc isSameOrChildPath(path, root: string): bool =
  let normalizedPath = normalizedFsPath(path)
  let normalizedRoot = normalizedFsPath(root)
  var prefix = normalizedRoot
  prefix.add(DirSep)
  normalizedPath == normalizedRoot or normalizedPath.startsWith(prefix)

proc remapPath(oldPath, oldRoot, newRoot: string): string {.raises: [].} =
  let normalizedOldPath = normalizedFsPath(oldPath)
  let normalizedOldRoot = normalizedFsPath(oldRoot)
  let normalizedNewRoot = normalizedFsPath(newRoot)
  if normalizedOldPath == normalizedOldRoot:
    normalizedNewRoot
  else:
    try:
      normalizedNewRoot / relativePath(normalizedOldPath, normalizedOldRoot)
    except Exception:
      normalizedNewRoot / oldPath.lastPathPart()

proc showFileTreeError(self: Application, title, message: string) {.raises: [].} =
  discard QMessageBox.critical(self.appWidget(), title, message)

proc showFileTreeInfo(self: Application, title, message: string) {.raises: [].} =
  discard QMessageBox.information(self.appWidget(), title, message)

proc promptFileTreeText(
    self: Application,
    title, labelText: string,
    defaultValue = "",
    okText = "OK"): string {.raises: [].} =
  var dialog = QInputDialog.create(self.appWidget())
  dialog.owned = false
  dialog.setWindowTitle(title)
  dialog.setInputMode(cint 0)  # TextInput
  dialog.setLabelText(labelText)
  dialog.setTextValue(defaultValue)
  dialog.setOkButtonText(okText)
  dialog.setCancelButtonText("Cancel")
  if dialog.exec() == 1:
    result = dialog.textValue()

proc validateFileTreeName(name: string): string =
  if name.strip().len == 0:
    return "Name cannot be empty."
  if name == "." or name == "..":
    return "Name must not be '.' or '..'."
  if '/' in name or '\\' in name:
    return "Name must not contain path separators."

proc clearFileTreeClipboard(self: Application) =
  self.fileTreeClipboardPath = ""
  self.fileTreeClipboardMode = ftcNone

proc canPasteInFileTree(self: Application): bool =
  self.fileTreeClipboardMode != ftcNone and self.fileTreeClipboardPath.len > 0

proc refreshFileTree(self: Application) {.raises: [].} =
  if self.currentProject.len > 0:
    self.fileTree.setRoot(self.currentProject)

proc syncClipboardAfterRename(self: Application, oldPath, newPath: string, isDir: bool) =
  if self.fileTreeClipboardPath.len == 0:
    return
  if isDir:
    if isSameOrChildPath(self.fileTreeClipboardPath, oldPath):
      self.fileTreeClipboardPath = remapPath(self.fileTreeClipboardPath, oldPath, newPath)
  elif normalizedFsPath(self.fileTreeClipboardPath) == normalizedFsPath(oldPath):
    self.fileTreeClipboardPath = newPath

proc clearClipboardIfDeleted(self: Application, deletedPath: string, isDir: bool) =
  if self.fileTreeClipboardPath.len == 0:
    return
  if isDir:
    if isSameOrChildPath(self.fileTreeClipboardPath, deletedPath):
      self.clearFileTreeClipboard()
  elif normalizedFsPath(self.fileTreeClipboardPath) == normalizedFsPath(deletedPath):
    self.clearFileTreeClipboard()

proc syncOpenBuffersAfterRename(self: Application, oldPath, newPath: string, isDir: bool) {.raises: [].} =
  var changedBuffers: seq[Buffer]
  for buf in self.bufferManager.items:
    let shouldUpdate =
      if isDir: isSameOrChildPath(buf.path, oldPath)
      else: normalizedFsPath(buf.path) == normalizedFsPath(oldPath)
    if not shouldUpdate:
      continue

    let previousPath = buf.path
    let updatedPath = if isDir: remapPath(previousPath, oldPath, newPath) else: newPath
    discard self.fileWatcher.removePath(previousPath)
    buf.name = updatedPath
    buf.path = updatedPath
    if fileExists(updatedPath):
      discard self.fileWatcher.addPath(updatedPath)
    changedBuffers.add(buf)

  for panel in self.paneManager.panels:
    if panel.buffer == nil:
      continue
    for buf in changedBuffers:
      if panel.buffer == buf:
        panel.setBuffer(buf)
        break

proc syncOpenBuffersAfterDelete(self: Application, deletedPath: string, isDir: bool) {.raises: [].} =
  var deletedBuffers: seq[Buffer]
  for buf in self.bufferManager.items:
    let shouldDelete =
      if isDir: isSameOrChildPath(buf.path, deletedPath)
      else: normalizedFsPath(buf.path) == normalizedFsPath(deletedPath)
    if shouldDelete:
      deletedBuffers.add(buf)
      discard self.fileWatcher.removePath(buf.path)

  for panel in self.paneManager.panels:
    if panel.buffer == nil:
      continue
    for buf in deletedBuffers:
      if panel.buffer == buf:
        panel.clearBuffer()
        break

  if isDir:
    self.bufferManager.closePathsUnder(deletedPath)
  else:
    self.bufferManager.closePath(deletedPath)

proc copyFileTreeItem(self: Application, path: string) =
  self.fileTreeClipboardPath = path
  self.fileTreeClipboardMode = ftcCopy

proc cutFileTreeItem(self: Application, path: string) =
  self.fileTreeClipboardPath = path
  self.fileTreeClipboardMode = ftcCut

proc moveFileTreeItem(self: Application, sourcePath, destinationDir: string): bool {.raises: [].} =
  if not pathExistsAny(sourcePath):
    self.showFileTreeError("Move Failed", "The source item no longer exists.")
    return
  if not dirExists(destinationDir):
    return

  let destinationPath = destinationDir / sourcePath.lastPathPart()
  let sourceIsDir = dirExists(sourcePath)

  if normalizedFsPath(sourcePath) == normalizedFsPath(destinationPath):
    return
  if normalizedFsPath(sourcePath.parentDir()) == normalizedFsPath(destinationDir):
    return
  if pathExistsAny(destinationPath):
    self.showFileTreeError("Move Failed", "An item with that name already exists in the destination.")
    return
  if sourceIsDir and isSameOrChildPath(destinationDir, sourcePath):
    self.showFileTreeError("Move Failed", "Cannot move a folder into itself or one of its children.")
    return

  try:
    if sourceIsDir:
      moveDir(sourcePath, destinationPath)
    else:
      moveFile(sourcePath, destinationPath)
    self.syncOpenBuffersAfterRename(sourcePath, destinationPath, sourceIsDir)
    self.syncClipboardAfterRename(sourcePath, destinationPath, sourceIsDir)
    self.refreshFileTree()
    result = true
  except Exception as exc:
    self.showFileTreeError("Move Failed", exc.msg)

proc pasteFileTreeItem(self: Application, path: string, isDir: bool) {.raises: [].} =
  if not self.canPasteInFileTree():
    self.showFileTreeInfo("Paste", "Nothing to paste.")
    return

  let sourcePath = self.fileTreeClipboardPath
  if not pathExistsAny(sourcePath):
    self.clearFileTreeClipboard()
    self.showFileTreeError("Paste Failed", "The source item no longer exists.")
    return

  let destinationDir = if isDir: path else: path.parentDir()
  let destinationPath = destinationDir / sourcePath.lastPathPart()
  let sourceIsDir = dirExists(sourcePath)

  if normalizedFsPath(sourcePath) == normalizedFsPath(destinationPath):
    self.showFileTreeError("Paste Failed", "The destination is the same as the source.")
    return
  if pathExistsAny(destinationPath):
    self.showFileTreeError("Paste Failed", "An item with that name already exists in the destination.")
    return
  if sourceIsDir and isSameOrChildPath(destinationDir, sourcePath):
    self.showFileTreeError("Paste Failed", "Cannot paste a folder into itself or one of its children.")
    return

  try:
    case self.fileTreeClipboardMode
    of ftcCopy:
      if sourceIsDir:
        copyDir(sourcePath, destinationPath)
      else:
        copyFile(sourcePath, destinationPath)
      self.refreshFileTree()
    of ftcCut:
      if self.moveFileTreeItem(sourcePath, destinationDir):
        self.clearFileTreeClipboard()
    of ftcNone:
      discard
  except Exception as exc:
    self.showFileTreeError("Paste Failed", exc.msg)

proc renameFileTreeItem(self: Application, path: string, isDir: bool) {.raises: [].} =
  let currentName = path.lastPathPart()
  let newName = self.promptFileTreeText("Rename", "New name", currentName, "Rename")
  if newName.len == 0:
    return

  let validationError = validateFileTreeName(newName)
  if validationError.len > 0:
    self.showFileTreeError("Rename Failed", validationError)
    return
  if newName == currentName:
    return

  let destinationPath = path.parentDir() / newName
  if pathExistsAny(destinationPath):
    self.showFileTreeError("Rename Failed", "An item with that name already exists.")
    return

  try:
    if isDir:
      moveDir(path, destinationPath)
    else:
      moveFile(path, destinationPath)
    self.syncOpenBuffersAfterRename(path, destinationPath, isDir)
    self.syncClipboardAfterRename(path, destinationPath, isDir)
    self.refreshFileTree()
  except Exception as exc:
    self.showFileTreeError("Rename Failed", exc.msg)

proc deleteFileTreeItem(self: Application, path: string, isDir: bool) {.raises: [].} =
  let parent = self.appWidget()
  let itemType = if isDir: "folder" else: "file"
  let clicked = QMessageBox.warning(
    parent,
    "Delete",
    "Delete this " & itemType & "?\n" & path,
    cint(16384 or 4194304),  # Yes | Cancel
    cint 4194304)
  if clicked != cint 16384:
    return

  try:
    if isDir:
      removeDir(path)
    else:
      removeFile(path)
    self.syncOpenBuffersAfterDelete(path, isDir)
    self.clearClipboardIfDeleted(path, isDir)
    self.refreshFileTree()
  except Exception as exc:
    self.showFileTreeError("Delete Failed", exc.msg)

proc createFileTreeFile(self: Application, dir: string) {.raises: [].} =
  let name = self.promptFileTreeText("New File", "File name", "", "Create")
  if name.len == 0:
    return

  let validationError = validateFileTreeName(name)
  if validationError.len > 0:
    self.showFileTreeError("Create File Failed", validationError)
    return

  let path = dir / name
  if pathExistsAny(path):
    self.showFileTreeError("Create File Failed", "A file or folder with that name already exists.")
    return

  try:
    writeFile(path, "")
    self.refreshFileTree()
  except Exception as exc:
    self.showFileTreeError("Create File Failed", exc.msg)

proc createFileTreeFolder(self: Application, dir: string) {.raises: [].} =
  let name = self.promptFileTreeText("New Folder", "Folder name", "", "Create")
  if name.len == 0:
    return

  let validationError = validateFileTreeName(name)
  if validationError.len > 0:
    self.showFileTreeError("Create Folder Failed", validationError)
    return

  let path = dir / name
  if pathExistsAny(path):
    self.showFileTreeError("Create Folder Failed", "A file or folder with that name already exists.")
    return

  try:
    createDir(path)
    self.refreshFileTree()
  except Exception as exc:
    self.showFileTreeError("Create Folder Failed", exc.msg)

proc getTargetPane*(self: Application): Pane =
  result = self.paneManager.lastFocusedPane
  if result == nil and self.paneManager.panels.len > 0:
    result = self.paneManager.panels[0]

proc getOrCreateTargetPane*(self: Application): Pane =
  self.getTargetPane()

proc openFile(self: Application, path: string): Buffer =
  result = self.bufferManager.openFile(path)
  when defined(debugFileWatcher):
    echo "[FileWatcher] openFile: ", path
  if result.path.len > 0:
    let added = self.fileWatcher.addPath(result.path)
    when defined(debugFileWatcher):
      echo "[FileWatcher] addPath result: ", added, ", files: ", self.fileWatcher.files()
    if self.currentProject.len > 0:
      self.projectManager.recordOpenedFile(self.currentProject, result.path)

proc updateRestoreSessionAvailability(self: Application) {.raises: [].} =
  let available = loadLastSession().isSome()
  if self.paneManager == nil:
    return
  for panel in self.paneManager.panels:
    panel.setRestoreLastSessionAvailable(available)

proc buildLastSession(self: Application): LastSession =
  let columns = self.paneManager.visibleColumns()
  result.projectNimbleFile = self.projectNimbleFile
  for colIdx, panes in columns:
    var savedColumn = SavedColumnSession()
    for rowIdx, pane in panes:
      let cursor = pane.currentCursorPosition()
      let scroll = pane.currentScrollPosition()
      savedColumn.panes.add(SavedPaneSession(
        filePath: if pane.buffer != nil: pane.buffer.path else: "",
        cursorLine: cursor.line,
        cursorColumn: cursor.col,
        verticalScroll: scroll.vertical,
        horizontalScroll: scroll.horizontal
      ))
      if pane == self.paneManager.lastFocusedPane:
        result.activeColumnIndex = colIdx
        result.activePaneIndex = rowIdx
    result.columns.add(savedColumn)
  if self.paneManager.lastFocusedPane == nil and result.columns.len > 0 and result.columns[0].panes.len > 0:
    result.activeColumnIndex = 0
    result.activePaneIndex = 0

proc saveLastSessionNow(self: Application) {.raises: [].} =
  if self.restoringSession or not self.sessionPersistenceReady or self.paneManager == nil:
    return
  saveLastSession(self.buildLastSession())
  self.updateRestoreSessionAvailability()

proc requestSessionSave(self: Application) {.raises: [].} =
  if self.restoringSession or not self.sessionPersistenceReady:
    return
  if self.sessionSaveTimer.h == nil:
    self.saveLastSessionNow()
  else:
    self.sessionSaveTimer.start()

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

proc openInPane(self: Application, pane: Pane, path: string) {.raises: [].} =
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
  except: discard

proc navigateToLocation*(self: Application, pane: Pane, path: string, line, col: int) {.raises: [].} =
  if path.len > 0:
    self.openInPane(pane, path)
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
    if target != nil and not (target.dispatcher != nil and target.dispatcher.inChord):
      callback(target)

proc registerGlobalShortcut*(self: Application, sequence: string, callback: proc(): void {.raises: [].}) =
  var sc = QShortcut.create(QKeySequence.create(sequence),
                            QObject(h: self.root.h, owned: false))
  sc.owned = false
  sc.setContext(cint 2)
  sc.onActivated do() {.raises: [].}:
    let target = self.getTargetPane()
    if target != nil and target.dispatcher != nil and target.dispatcher.inChord: return
    callback()

proc buffers*(app: Application): lent BufferManager =
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

proc updateRecentProjects(self: Application) {.raises: [].} =
  for panel in self.paneManager.panels:
    panel.setRecentProjects(self.projectManager.recentProjects)

proc runProjectCheck*(self: Application) {.raises: [].} =
  if self.projectNimbleFile.len == 0: return
  let mainFile = findProjectMain(self.projectNimbleFile)
  if mainFile.len == 0: return
  if self.projectCheckProcessH[] != nil:
    try: QProcess(h: self.projectCheckProcessH[], owned: false).kill()
    except: discard
    self.projectCheckProcessH[] = nil
  runNimCheck(self.root.h, mainFile, self.projectCheckProcessH,
    proc(lines: seq[LogLine]) {.raises: [].} =
      self.projectDiagLines[] = lines
      self.toolbar.updateDiagCounts(lines))

proc openProject(self: Application, path: string, restoreMode = false) {.raises: [].} =
  let dir = path.parentDir()
  self.currentProject = dir
  self.projectNimbleFile = path
  for panel in self.paneManager.panels:
    panel.clearBuffer()
  self.paneManager.setProjectOpen(true)
  self.bufferManager = BufferManager.init()
  try: setCurrentDir(dir) except OSError: discard
  self.toolbar.setProjectName(dir.lastPathPart)
  self.projectManager.recordOpenedProject(path)
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
  if not restoreMode:
    self.paneManager.panels[0].triggerOpenModule()
  self.toolbar.setCloseProjectVisible(true)
  self.runProjectCheck()
  self.requestSessionSave()

proc openProject(self: Application) {.raises: [].} =
  let file = QFileDialog.getOpenFileName(
    QWidget(h: self.root.h, owned: false), "", "", "Nimble files (*.nimble)")
  if file.len == 0: return
  self.openProject(file)

proc closeProject*(self: Application) {.raises: [].} =
  self.currentProject = ""
  self.projectNimbleFile = ""
  for panel in self.paneManager.panels:
    panel.clearBuffer()
  self.paneManager.setProjectOpen(false)
  self.bufferManager = BufferManager.init()
  self.toolbar.setProjectName("—")
  self.fileTree.setRoot("")
  self.toolbar.setFileTreeEnabled(false)
  self.toolbar.setFileTreeIconColor("#888888")
  if self.nimSuggest != nil:
    self.nimSuggest.kill()
    self.nimSuggest = nil
  self.toolbar.setCloseProjectVisible(false)
  self.projectDiagLines[] = @[]
  self.toolbar.updateDiagCounts(@[])
  self.requestSessionSave()

proc prepareForSessionRestore(self: Application): Pane =
  if self.currentProject.len > 0:
    self.closeProject()
  if self.paneManager.panels.len == 0:
    result = self.paneManager.addColumn()
  else:
    result = self.paneManager.panels[0]
  self.paneManager.closeOtherPanes(result)
  result.clearBuffer()

proc restoreLastSession(self: Application) {.raises: [].} =
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

    var paneGrid: seq[seq[Pane]] = @[@[firstPane]]
    while paneGrid[0].len < layout[0].panes.len:
      let newPane = self.paneManager.splitRow(paneGrid[0][^1])
      if newPane == nil:
        break
      paneGrid[0].add(newPane)

    for colIdx in 1..<layout.len:
      let newColPane = self.paneManager.addColumn()
      paneGrid.add(@[newColPane])
      while paneGrid[colIdx].len < layout[colIdx].panes.len:
        let newPane = self.paneManager.splitRow(paneGrid[colIdx][^1])
        if newPane == nil:
          break
        paneGrid[colIdx].add(newPane)

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

    var focusPane: Pane
    if session.activeColumnIndex >= 0 and session.activeColumnIndex < paneGrid.len:
      let col = paneGrid[session.activeColumnIndex]
      if session.activePaneIndex >= 0 and session.activePaneIndex < col.len:
        focusPane = col[session.activePaneIndex]
    if focusPane == nil and paneGrid.len > 0 and paneGrid[0].len > 0:
      focusPane = paneGrid[0][0]
    if focusPane != nil:
      focusPane.focus()
  finally:
    self.restoringSession = false

  self.saveLastSessionNow()

proc closeBuffer*(self: Application, name: string) =
  for panel in self.paneManager.panels:
    if panel.buffer != nil and panel.buffer.name == name:
      panel.clearBuffer()
  self.bufferManager.close(name)
  self.requestSessionSave()

proc build*(self: Application) =
  self.root = QMainWindow.create()
  # WA_TranslucentBackground is set by setupWindowOpacity below
  QWidget(h: self.root.h, owned: false).setMinimumSize(cint(800), cint(480))
  self.toolbar.build()
  self.toolbar.setCloseProjectVisible(false)

  self.root.addToolBar(QToolBar(h: self.toolbar.widget().h, owned: false))

  # Loader timer to update spinner based on nimsuggest state
  self.loaderTimer = QTimer.create()
  self.loaderTimer.owned = false
  self.loaderTimer.setInterval(cint 200)
  let appRef = self
  self.loaderTimer.onTimeout do() {.raises: [].}:
    var isLoading = appRef.projectCheckProcessH[] != nil
    if not isLoading and appRef.nimSuggest != nil:
      let ns = appRef.nimSuggest
      isLoading = ns.state == csStarting or ns.pending.len > 0
    appRef.toolbar.setLoading(isLoading)
  self.loaderTimer.start()

  self.sessionSaveTimer = QTimer.create()
  self.sessionSaveTimer.owned = false
  self.sessionSaveTimer.setInterval(cint 200)
  self.sessionSaveTimer.setSingleShot(true)
  self.sessionSaveTimer.onTimeout do() {.raises: [].}:
    self.saveLastSessionNow()

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
      self.openInPane(pane, path),
    onNewModule: proc(pane: Pane) {.raises: [].} =
      let path = showNewModuleDialog(QWidget(h: self.root.h, owned: false))
      if path.len > 0:
        self.openInPane(pane, path),
    onOpenModule: proc(pane: Pane) {.raises: [].} =
      showFileFinder(QWidget(h: self.root.h, owned: false),
        self.projectManager.recentFilesFor(self.currentProject),
        proc(path: string) {.raises: [].} =
          self.openInPane(pane, path)),
    onNewProject: proc(pane: Pane) {.raises: [].} =
      showNewProjectDialog(QWidget(h: self.root.h, owned: false), self.projectManager),
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
      showFileFinder(QWidget(h: self.root.h, owned: false),
        self.projectManager.recentFilesFor(self.currentProject)) do(path: string) {.raises: [].}:
        self.openInPane(pane, path),
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
            self.requestSessionSave()
            break
    ,
    onRestoreLastSession: proc(pane: Pane) {.raises: [].} =
      discard pane
      self.restoreLastSession(),
    onPaneStateChanged: proc(pane: Pane) {.raises: [].} =
      discard pane
      self.requestSessionSave(),
    onLayoutChanged: proc() {.raises: [].} =
      self.requestSessionSave()
    ))

  # Command dispatcher — register all editor commands and bind default keys
  block:
    let disp = CommandDispatcher()
    registerDefaultBindings(disp)
    disp.applyCustomBindings(self.settings.keybindings.toTable())
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

    disp.register("editor.openLine", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p == nil: return
      if p.buffer == nil:
        p.triggerOpenProject()
        return
      let ed = QPlainTextEdit(h: p.editor.h, owned: false)
      let c = ed.textCursor()
      c.insertText("\n")
      discard c.movePosition(cint(QTextCursorMoveOperationEnum.Left),
                             cint(QTextCursorMoveModeEnum.MoveAnchor))
      ed.setTextCursor(c))

    disp.register("editor.recenter", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p != nil: QPlainTextEdit(h: p.editor.h, owned: false).centerCursor())

    disp.register("editor.killRegion", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p != nil: QPlainTextEdit(h: p.editor.h, owned: false).cut())

    disp.register("editor.yank", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p != nil: QPlainTextEdit(h: p.editor.h, owned: false).paste())

    # Buffer / window management
    disp.register("editor.saveBuffer", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p != nil: p.save())

    disp.register("editor.quitApplication", proc() {.raises: [].} =
      QApplication.quit())

    disp.register("editor.killBuffer", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p != nil: self.paneManager.closePane(p))

    disp.register("editor.deleteOtherWindows", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p != nil: self.paneManager.closeOtherPanes(p))

    disp.register("editor.splitHorizontal", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p != nil: discard self.paneManager.splitRow(p))

    disp.register("editor.splitVertical", proc() {.raises: [].} =
      let p = self.getTargetPane(); if p != nil: discard self.paneManager.splitCol(p))

    disp.register("editor.findFile", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p == nil: return
      showFileFinder(QWidget(h: self.root.h, owned: false),
        self.projectManager.recentFilesFor(self.currentProject)) do(path: string) {.raises: [].}:
        self.openInPane(p, path))

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
            self.requestSessionSave()
            break)

    # Search / navigation
    disp.register("editor.findInBuffer", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p != nil: p.triggerFind())

    disp.register("editor.closeSearch", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p != nil: p.closeSearch())

    disp.register("editor.ripgrepFind", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p == nil: return
      showRipgrepFinder(QWidget(h: self.root.h, owned: false)) do(file: string, lineNum: int) {.raises: [].}:
        self.openInPane(p, file)
        p.scrollToLine(lineNum))

    disp.register("editor.gotoDefinition", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p == nil or self.nimSuggest == nil: return
      try: p.triggerGotoDefinition(self.nimSuggest)
      except: discard)

    disp.register("editor.autocomplete", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p == nil or self.nimSuggest == nil: return
      try: p.triggerAutocomplete(self.nimSuggest)
      except: discard)

    disp.register("editor.showPrototype", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p == nil: return
      try: p.triggerPrototype()
      except: discard)

    # Layout / view
    disp.register("editor.addColumn", proc() {.raises: [].} =
      discard self.paneManager.addColumn()
      self.paneManager.equalizeSplits())

    disp.register("editor.toggleFileTree", proc() {.raises: [].} =
      if self.currentProject.len > 0: self.fileTree.toggle())

    disp.register("editor.splitRow", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p == nil: return
      try: discard self.paneManager.splitRow(p)
      except: discard)

    disp.register("editor.zoomIn", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p != nil: p.zoomIn())

    disp.register("editor.zoomOut", proc() {.raises: [].} =
      let p = self.getTargetPane()
      if p != nil: p.zoomOut())

  # Wire file tree: clicking a file opens it in the active pane
  self.fileTree.onFileSelected = proc(path: string) {.raises: [].} =
    let target = self.getTargetPane()
    if target == nil: return
    self.openInPane(target, path)
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
        self.openInPane(target, file)
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
        self.openInPane(target, file)
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
    let target = self.getTargetPane()
    if target == nil: return
    self.openInPane(target, file)

  self.toolbar.onTriggered(OpenProject) do():
    self.openProject()

  self.toolbar.onTriggered(CloseProject) do():
    self.closeProject()

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
    discard self.paneManager.addColumn()
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
          updated.appearance.opacityLevel)
        let disp = self.paneManager.dispatcher
        if disp != nil:
          disp.resetBindings()
          registerDefaultBindings(disp)
          disp.applyCustomBindings(updated.keybindings.toTable()),
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
    if pane == nil: return
    self.navigateToLocation(pane, path, line, col)

  discard self.paneManager.addColumn()  # initialize at least one
  self.paneManager.equalizeSplits()
  self.updateRecentProjects()
  self.updateRestoreSessionAvailability()
  self.sessionPersistenceReady = true

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
      sleep(50)
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
        if QPlainTextEdit(h: panel.editor.h, owned: false).document().isModified():
          dirty = true
          break
    if dirty:
      buf.externallyModified = true
      when defined(debugFileWatcher):
        echo "[FileWatcher] buffer dirty, marking externallyModified"
    else:
      var content = ""
      var readOk = false
      for i in 0..<3:
        try:
          content = readFile(p)
          readOk = true
          break
        except:
          when defined(debugFileWatcher):
            echo "[FileWatcher] retry readFile attempt ", i + 1, ": ", getCurrentExceptionMsg()
          sleep(50)
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

  let appInstance = QApplication(h: QCoreApplication.instance().h, owned: false)
  appInstance.onFocusChanged do(old, now: QWidget):
    try:
      self.paneManager.updateFocus(now, self.theme == Dark)
      discard old
      self.requestSessionSave()
    except: 
      discard

proc show*(self: Application) =
  self.root.show()
