import seaqt/[qwidget, qvboxlayout, qtreeview, qfilesystemmodel, qabstractitemview,
               qabstractitemmodel, qabstractscrollarea, qheaderview, qlabel,
               qabstractfileiconprovider, qmenu, qaction, qcontextmenuevent,
               qdragenterevent, qdragmoveevent, qdropevent, qmimedata, qurl,
               qshortcut, qkeysequence, qobject]
import std/[os, strutils]
import nide/helpers/devicons
import nide/helpers/fspaths
import nide/helpers/qtconst
import nide/settings/theme
import nide/ui/widgets

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
    let toolbarHeight = ToolbarHeight
    self.container.setGeometry(cint 0, toolbarHeight, cint TreeWidth, cint TreeHeight)
    self.container.raiseX()
  except CatchableError:
    discard

proc ensureCurrentIndex(self: FileTree): QModelIndex {.raises: [].} =
  let view = QAbstractItemView(h: self.treeView.h, owned: false)
  result = view.currentIndex()
  if result.isValid():
    return
  let rootIndex = view.rootIndex()
  if rootIndex.isValid():
    view.setCurrentIndex(rootIndex)
    result = rootIndex

proc focusCurrentIndex(self: FileTree, index: QModelIndex) {.raises: [].} =
  if not index.isValid():
    return
  let view = QAbstractItemView(h: self.treeView.h, owned: false)
  view.setCurrentIndex(index)
  self.treeView.scrollTo(index, cint(QAbstractItemViewScrollHintEnum.EnsureVisible))

proc moveSelection(self: FileTree, delta: int) {.raises: [].} =
  try:
    let current = self.ensureCurrentIndex()
    if not current.isValid():
      return
    let nextIndex =
      if delta > 0: self.treeView.indexBelow(current)
      else: self.treeView.indexAbove(current)
    if nextIndex.isValid():
      self.focusCurrentIndex(nextIndex)
  except CatchableError:
    discard

proc activateSelection(self: FileTree) {.raises: [].} =
  try:
    let index = self.ensureCurrentIndex()
    if not index.isValid():
      return
    let model = QFileSystemModel(h: self.model.h, owned: false)
    if model.isDir(index):
      self.treeView.setExpanded(index, not self.treeView.isExpanded(index))
      self.focusCurrentIndex(index)
      return
    let path = model.filePath(index)
    if self.onFileSelected != nil:
      self.onFileSelected(path)
  except CatchableError:
    discard

proc applyTheme*(self: FileTree, theme: Theme) {.raises: [].} =
  if self == nil or self.container.h == nil:
    return

  let panelBg = windowColor(theme)
  let controlBg = surfaceColor(theme)
  let headerBg = headerColor(theme)
  let border = borderColor(theme)
  let text = textColor(theme)
  let selected = highlightColor(theme)
  let selectedText = highlightedTextColor(theme)

  self.container.setStyleSheet(
    "QWidget#fileTreePanel {" &
    "  background: " & panelBg & ";" &
    "  border: 1px solid " & border & ";" &
    "  border-radius: 6px;" &
    "}" &
    "QLabel#fileTreeHeader {" &
    "  background: " & headerBg & ";" &
    "  color: " & text & ";" &
    "  padding: 4px 8px;" &
    "  font-weight: bold;" &
    "  border: none;" &
    "  border-bottom: 1px solid " & border & ";" &
    "}" &
    "QTreeView#fileTreeView {" &
    "  background: " & controlBg & ";" &
    "  color: " & text & ";" &
    "  border: none;" &
    "  outline: 0;" &
    "  show-decoration-selected: 1;" &
    "}" &
    "QTreeView#fileTreeView::item:selected {" &
    "  background: " & selected & ";" &
    "  color: " & selectedText & ";" &
    "}" &
    "QTreeView#fileTreeView::branch:selected {" &
    "  background: " & selected & ";" &
    "}"
  )

proc newFileTree*(mainWindow: QWidget): FileTree =
  result = FileTree()
  let self = result

  # Create as a top-level widget positioned manually over the content area.
  # Parent is mainWindow so it stays on top, but with Tool flag for floating behavior.
  self.container = newWidget(QWidget.create(mainWindow, WF_Tool))
  self.container.setObjectName("fileTreePanel")

  let layout = vbox()
  layout.applyTo(self.container)

  # Header label
  var header = label("Files", "QLabel { padding: 4px 8px; font-weight: bold; }")
  QWidget(h: header.h, owned: false).setObjectName("fileTreeHeader")
  QWidget(h: header.h, owned: false).setFixedHeight(HeaderHeight)
  layout.add(header)

  # File system model
  self.model = newWidget(QFileSystemModel.create())
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
    except CatchableError:
      try: event.ignore() except CatchableError: discard

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
    except CatchableError:
      try: event.ignore() except CatchableError: discard

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
    except CatchableError:
      try: event.ignore() except CatchableError: discard

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

      var menu = newWidget(QMenu.create(QWidget(h: tree.h, owned: false)))

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
    except CatchableError:
      discard

  self.treeView = newWidget(QTreeView.create(vtbl = treeVtbl))
  QWidget(h: self.treeView.h, owned: false).setObjectName("fileTreeView")
  QWidget(h: self.treeView.h, owned: false).setSizePolicy(SP_Expanding, SP_Expanding)
  QWidget(h: self.treeView.h, owned: false).setMinimumSize(cint TreeWidth, cint TreeHeight)
  QWidget(h: self.treeView.h, owned: false).setFocusPolicy(FP_StrongFocus)
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

  layout.add(self.treeView)

  # Wire single-click file activation
  QAbstractItemView(h: self.treeView.h, owned: false).onActivated do(
      index: QModelIndex) {.raises: [].}:
    try:
      let m = QFileSystemModel(h: modelH, owned: false)
      if not m.isDir(index):
        let path = m.filePath(index)
        if self.onFileSelected != nil:
          self.onFileSelected(path)
    except CatchableError:
      discard

  var nextSc = newWidget(QShortcut.create(QKeySequence.create("Ctrl+N"),
                                          QObject(h: self.treeView.h, owned: false)))
  nextSc.setContext(SC_WidgetShortcut)
  nextSc.onActivated do() {.raises: [].}:
    self.moveSelection(1)

  var prevSc = newWidget(QShortcut.create(QKeySequence.create("Ctrl+P"),
                                          QObject(h: self.treeView.h, owned: false)))
  prevSc.setContext(SC_WidgetShortcut)
  prevSc.onActivated do() {.raises: [].}:
    self.moveSelection(-1)

  var downSc = newWidget(QShortcut.create(QKeySequence.create("Down"),
                                          QObject(h: self.treeView.h, owned: false)))
  downSc.setContext(SC_WidgetShortcut)
  downSc.onActivated do() {.raises: [].}:
    self.moveSelection(1)

  var upSc = newWidget(QShortcut.create(QKeySequence.create("Up"),
                                        QObject(h: self.treeView.h, owned: false)))
  upSc.setContext(SC_WidgetShortcut)
  upSc.onActivated do() {.raises: [].}:
    self.moveSelection(-1)

  var enterSc = newWidget(QShortcut.create(QKeySequence.create("Return"),
                                           QObject(h: self.treeView.h, owned: false)))
  enterSc.setContext(SC_WidgetShortcut)
  enterSc.onActivated do() {.raises: [].}:
    self.activateSelection()

  var keypadEnterSc = newWidget(QShortcut.create(QKeySequence.create("Enter"),
                                                 QObject(h: self.treeView.h, owned: false)))
  keypadEnterSc.setContext(SC_WidgetShortcut)
  keypadEnterSc.onActivated do() {.raises: [].}:
    self.activateSelection()

  var escSc = newWidget(QShortcut.create(QKeySequence.create("Escape"),
                                         QObject(h: self.treeView.h, owned: false)))
  escSc.setContext(SC_WidgetShortcut)
  escSc.onActivated do() {.raises: [].}:
    self.container.hide()

  self.container.resize(cint TreeWidth, cint TreeHeight)
  self.applyTheme(Dark)

  # Start hidden
  self.container.hide()

proc setRoot*(self: FileTree, dir: string) {.raises: [].} =
  try:
    let rootIndex = self.model.setRootPath(dir)
    self.treeView.setRootIndex(rootIndex)
  except CatchableError:
    discard

proc showPanel*(self: FileTree) {.raises: [].}
proc showAndFocusPanel*(self: FileTree) {.raises: [].}
proc hidePanel*(self: FileTree) {.raises: [].}

proc toggle*(self: FileTree) {.raises: [].} =
  try:
    if self.container.isVisible():
      self.hidePanel()
    else:
      self.showAndFocusPanel()
  except CatchableError:
    discard

proc isVisible*(self: FileTree): bool {.raises: [].} =
  try: self.container.isVisible()
  except CatchableError: false

proc showPanel*(self: FileTree) {.raises: [].} =
  try:
    self.reposition()
    self.container.setFixedSize(cint TreeWidth, cint TreeHeight)
    self.container.show()
    self.reposition()
  except CatchableError:
    discard

proc showAndFocusPanel*(self: FileTree) {.raises: [].} =
  try:
    self.showPanel()
    discard self.ensureCurrentIndex()
    QWidget(h: self.treeView.h, owned: false).setFocus()
  except CatchableError:
    discard

proc hidePanel*(self: FileTree) {.raises: [].} =
  try:
    self.container.hide()
  except CatchableError:
    discard

proc hasFocus*(self: FileTree): bool {.raises: [].} =
  try:
    QWidget(h: self.treeView.h, owned: false).hasFocus()
  except CatchableError:
    false
