import seaqt/[qwidget, qvboxlayout, qtreeview, qfilesystemmodel, qabstractitemview,
               qabstractitemmodel, qabstractscrollarea, qheaderview, qlabel,
               qabstractfileiconprovider, qmenu, qaction, qcontextmenuevent,
               qdragenterevent, qdragmoveevent, qdropevent, qmimedata, qurl]
import std/[os, strutils]
import ./devicons
import ./qtconst

const TreeWidth = 320
const TreeHeight = 420

const
  ToolbarHeight = cint 28
  HeaderHeight = cint 28
  TreeIndent = cint 16
  AutoExpandDelayMs = cint 600

type
  FileTreeMenuAction* = enum
    ftCopy, ftPaste, ftRename, ftDelete, ftCut, ftNewFile, ftNewFolder

  FileTree* = ref object
    container*:       QWidget
    treeView:         QTreeView
    model:            QFileSystemModel
    iconProvider:     DevIconProvider  # keep alive to prevent GC collection
    splitterH*:       pointer   # raw handle of the parent splitter for positioning
    onFileSelected*:  proc(path: string) {.raises: [].}
    canPaste*:        proc(): bool {.raises: [].}
    onMenuAction*:    proc(action: FileTreeMenuAction, path: string, isDir: bool) {.raises: [].}
    onMoveRequested*: proc(sourcePath: string, targetDir: string): bool {.raises: [].}

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

proc draggedLocalPaths(event: QDropEvent, rootPath: string): seq[string] {.raises: [].} =
  if rootPath.len == 0:
    return
  let mime = event.mimeData()
  if not mime.hasUrls():
    return
  for url in mime.urls():
    if not url.isLocalFile():
      continue
    let localPath = url.toLocalFile()
    if localPath.len == 0:
      continue
    if isSameOrChildPath(localPath, rootPath):
      result.add(localPath)

proc dropTargetDir(tree: QTreeView, model: QFileSystemModel, pos: QPoint): string {.raises: [].} =
  let index = tree.indexAt(pos)
  if not index.isValid() or not model.isDir(index):
    return ""
  model.filePath(index)

proc canDropPaths(sourcePaths: seq[string], targetDir: string): bool =
  if sourcePaths.len != 1 or targetDir.len == 0:
    return false
  let sourcePath = sourcePaths[0]
  let destinationPath = targetDir / sourcePath.lastPathPart()
  if normalizedFsPath(sourcePath) == normalizedFsPath(destinationPath):
    return false
  if normalizedFsPath(sourcePath.parentDir()) == normalizedFsPath(targetDir):
    return false
  if dirExists(sourcePath) and isSameOrChildPath(targetDir, sourcePath):
    return false
  if pathExistsAny(destinationPath):
    return false
  true

proc reposition*(self: FileTree) {.raises: [].} =
  ## Repositions the floating panel to the top-left of the main window content area.
  if self.splitterH == nil: return
  try:
    let mainWin = QWidget(h: self.splitterH, owned: false)
    let toolbarHeight = ToolbarHeight
    self.container.setGeometry(cint 0, toolbarHeight, cint TreeWidth, cint TreeHeight)
    self.container.raiseX()
  except:
    discard

proc newFileTree*(mainWindow: QWidget): FileTree =
  result = FileTree()
  let self = result

  # Create as a top-level widget positioned manually over the content area.
  # Parent is mainWindow so it stays on top, but with Tool flag for floating behavior.
  self.container = QWidget.create(mainWindow, WF_Tool)
  self.container.owned = false

  let layout = QVBoxLayout.create()
  layout.setContentsMargins(cint 0, cint 0, cint 0, cint 0)
  layout.setSpacing(cint 0)
  self.container.setLayout(layout)

  # Header label
  var header = QLabel.create("Files")
  header.owned = false
  QWidget(h: header.h, owned: false).setStyleSheet(
    "QLabel { padding: 4px 8px; font-weight: bold; }")
  QWidget(h: header.h, owned: false).setFixedHeight(HeaderHeight)
  layout.addWidget(QWidget(h: header.h, owned: false))

  # File system model
  self.model = QFileSystemModel.create()
  self.model.owned = false
  self.model.setReadOnly(false)

  # Custom devicon provider
  self.iconProvider = newDevIconProvider()
  self.model.setIconProvider(
    QAbstractFileIconProvider(h: self.iconProvider.h, owned: false))

  # Tree view
  let modelH = self.model.h
  var treeVtbl = new QTreeViewVTable
  treeVtbl.dragEnterEvent = proc(tree: QTreeView, event: QDragEnterEvent) {.raises: [], gcsafe.} =
    try:
      let model = QFileSystemModel(h: modelH, owned: false)
      let dropEvent = QDropEvent(h: event.h, owned: false)
      let sourcePaths = draggedLocalPaths(dropEvent, model.rootPath())
      if self.onMoveRequested != nil and sourcePaths.len == 1:
        event.accept()
      else:
        event.ignore()
    except:
      try: event.ignore() except: discard

  treeVtbl.dragMoveEvent = proc(tree: QTreeView, event: QDragMoveEvent) {.raises: [], gcsafe.} =
    try:
      let model = QFileSystemModel(h: modelH, owned: false)
      let dropEvent = QDropEvent(h: event.h, owned: false)
      let sourcePaths = draggedLocalPaths(dropEvent, model.rootPath())
      let targetDir = dropTargetDir(tree, model, dropEvent.pos())
      if self.onMoveRequested != nil and canDropPaths(sourcePaths, targetDir):
        dropEvent.setDropAction(DD_MoveAction)
        event.accept()
      else:
        event.ignore()
    except:
      try: event.ignore() except: discard

  treeVtbl.dropEvent = proc(tree: QTreeView, event: QDropEvent) {.raises: [], gcsafe.} =
    try:
      let model = QFileSystemModel(h: modelH, owned: false)
      let sourcePaths = draggedLocalPaths(event, model.rootPath())
      let targetDir = dropTargetDir(tree, model, event.pos())
      if self.onMoveRequested == nil or not canDropPaths(sourcePaths, targetDir):
        event.ignore()
        return

      let targetIndex = tree.indexAt(event.pos())
      if targetIndex.isValid():
        QAbstractItemView(h: tree.h, owned: false).setCurrentIndex(targetIndex)

      var accepted = false
      {.cast(gcsafe).}:
        accepted = self.onMoveRequested(sourcePaths[0], targetDir)

      if accepted:
        event.setDropAction(DD_MoveAction)
        event.acceptProposedAction()
      else:
        event.ignore()
    except:
      try: event.ignore() except: discard

  treeVtbl.contextMenuEvent = proc(tree: QTreeView, event: QContextMenuEvent) {.raises: [], gcsafe.} =
    try:
      let index = tree.indexAt(event.pos())
      if not index.isValid():
        return

      let view = QAbstractItemView(h: tree.h, owned: false)
      view.setCurrentIndex(index)

      let model = QFileSystemModel(h: modelH, owned: false)
      let path = model.filePath(index)
      let isDir = model.isDir(index)

      var menu = QMenu.create(QWidget(h: tree.h, owned: false))
      menu.owned = false

      let copyAction = menu.addAction("Copy")
      let cutAction = menu.addAction("Cut")
      let pasteAction = menu.addAction("Paste")
      if self.canPaste != nil:
        {.cast(gcsafe).}:
          pasteAction.setEnabled(self.canPaste())
      else:
        pasteAction.setEnabled(false)
      let renameAction = menu.addAction("Rename")
      let deleteAction = menu.addAction("Delete")
      var newFileAction: QAction
      var newFolderAction: QAction

      if isDir:
        discard menu.addSeparator()
        newFileAction = menu.addAction("New File")
        newFolderAction = menu.addAction("New Folder")

      let chosen = menu.exec(event.globalPos())
      if chosen.h == nil or self.onMenuAction == nil:
        return

      {.cast(gcsafe).}:
        if chosen.h == copyAction.h:
          self.onMenuAction(ftCopy, path, isDir)
        elif chosen.h == cutAction.h:
          self.onMenuAction(ftCut, path, isDir)
        elif chosen.h == pasteAction.h:
          self.onMenuAction(ftPaste, path, isDir)
        elif chosen.h == renameAction.h:
          self.onMenuAction(ftRename, path, isDir)
        elif chosen.h == deleteAction.h:
          self.onMenuAction(ftDelete, path, isDir)
        elif isDir and chosen.h == newFileAction.h:
          self.onMenuAction(ftNewFile, path, isDir)
        elif isDir and chosen.h == newFolderAction.h:
          self.onMenuAction(ftNewFolder, path, isDir)
    except:
      discard

  self.treeView = QTreeView.create(vtbl = treeVtbl)
  self.treeView.owned = false
  QWidget(h: self.treeView.h, owned: false).setSizePolicy(SP_Expanding, SP_Expanding)
  QWidget(h: self.treeView.h, owned: false).setMinimumSize(cint TreeWidth, cint TreeHeight)
  self.treeView.setModel(QAbstractItemModel(h: self.model.h, owned: false))
  self.treeView.setHeaderHidden(true)
  self.treeView.setAnimated(true)
  self.treeView.setAutoExpandDelay(AutoExpandDelayMs)
  self.treeView.setIndentation(TreeIndent)
  self.treeView.setUniformRowHeights(true)
  let treeView = QAbstractItemView(h: self.treeView.h, owned: false)
  treeView.setEditTriggers(DD_NoEditTriggers)
  treeView.setDragEnabled(true)
  treeView.setDropIndicatorShown(true)
  treeView.setDragDropMode(DD_InternalMove)
  treeView.setDefaultDropAction(DD_MoveAction)
  QWidget(h: self.treeView.h, owned: false).setAcceptDrops(true)
  QAbstractScrollArea(h: self.treeView.h, owned: false).viewport().setAcceptDrops(true)

  # Hide size, type, date-modified columns (1, 2, 3)
  let hdr = self.treeView.header()
  hdr.hideSection(cint 1)
  hdr.hideSection(cint 2)
  hdr.hideSection(cint 3)
  hdr.setSectionResizeMode(cint 0, HR_Stretch)
  hdr.setStretchLastSection(false)

  layout.addWidget(QWidget(h: self.treeView.h, owned: false))

  # Wire single-click file activation
  QAbstractItemView(h: self.treeView.h, owned: false).onActivated do(
      index: QModelIndex) {.raises: [].}:
    try:
      let m = QFileSystemModel(h: modelH, owned: false)
      if not m.isDir(index):
        let path = m.filePath(index)
        if self.onFileSelected != nil:
          self.onFileSelected(path)
    except:
      discard

  self.container.resize(cint TreeWidth, cint TreeHeight)

  # Start hidden
  self.container.hide()

proc setRoot*(self: FileTree, dir: string) {.raises: [].} =
  try:
    let rootIndex = self.model.setRootPath(dir)
    self.treeView.setRootIndex(rootIndex)
  except:
    discard

proc toggle*(self: FileTree) {.raises: [].} =
  try:
    if self.container.isVisible():
      self.container.hide()
    else:
      self.reposition()
      QWidget(h: self.container.h, owned: false).setFixedSize(cint TreeWidth, cint TreeHeight)
      self.container.show()
      self.reposition()
  except:
    discard

proc isVisible*(self: FileTree): bool {.raises: [].} =
  try: self.container.isVisible()
  except: false
