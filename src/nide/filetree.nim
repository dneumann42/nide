import seaqt/[qwidget, qvboxlayout, qtreeview, qfilesystemmodel, qabstractitemview,
               qabstractitemmodel, qheaderview, qlabel, qabstractfileiconprovider,
               qmenu, qaction, qcontextmenuevent]
import ./devicons

const TreeWidth = 320
const TreeHeight = 420

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

proc reposition*(self: FileTree) {.raises: [].} =
  ## Repositions the floating panel to the top-left of the main window content area.
  if self.splitterH == nil: return
  try:
    let mainWin = QWidget(h: self.splitterH, owned: false)
    let toolbarHeight = cint 28
    self.container.setGeometry(cint 0, toolbarHeight, cint TreeWidth, cint TreeHeight)
    self.container.raiseX()
  except:
    discard

proc newFileTree*(mainWindow: QWidget): FileTree =
  result = FileTree()
  let self = result

  # Create as a top-level widget positioned manually over the content area.
  # Parent is mainWindow so it stays on top, but with Tool flag for floating behavior.
  self.container = QWidget.create(mainWindow, cint 0x00000008)  # Qt.Tool
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
  QWidget(h: header.h, owned: false).setFixedHeight(cint 28)
  layout.addWidget(QWidget(h: header.h, owned: false))

  # File system model
  self.model = QFileSystemModel.create()
  self.model.owned = false
  self.model.setReadOnly(true)

  # Custom devicon provider
  self.iconProvider = newDevIconProvider()
  self.model.setIconProvider(
    QAbstractFileIconProvider(h: self.iconProvider.h, owned: false))

  # Tree view
  let modelH = self.model.h
  var treeVtbl = new QTreeViewVTable
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
  QWidget(h: self.treeView.h, owned: false).setSizePolicy(cint 7, cint 7)  # Expanding
  QWidget(h: self.treeView.h, owned: false).setMinimumSize(cint TreeWidth, cint TreeHeight)
  self.treeView.setModel(QAbstractItemModel(h: self.model.h, owned: false))
  self.treeView.setHeaderHidden(true)
  self.treeView.setAnimated(true)
  self.treeView.setIndentation(cint 16)
  self.treeView.setUniformRowHeights(true)

  # Hide size, type, date-modified columns (1, 2, 3)
  let hdr = self.treeView.header()
  hdr.hideSection(cint 1)
  hdr.hideSection(cint 2)
  hdr.hideSection(cint 3)
  hdr.setSectionResizeMode(cint 0, cint 1)  # Stretch
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
