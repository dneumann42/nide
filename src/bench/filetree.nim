import seaqt/[qwidget, qvboxlayout, qtreeview, qfilesystemmodel, qabstractitemview,
               qabstractitemmodel, qheaderview, qlabel]

const TreeWidth = 320*4
const TreeHeight = 420*4

type
  FileTree* = ref object
    container*:       QWidget
    treeView:         QTreeView
    model:            QFileSystemModel
    splitterH*:       pointer   # raw handle of the parent splitter for positioning
    onFileSelected*:  proc(path: string) {.raises: [].}

proc reposition*(self: FileTree) {.raises: [].} =
  ## Repositions the floating panel to the top-left of the main window content area.
  if self.splitterH == nil: return
  try:
    # self.splitterH is actually the mainWindow handle for positioning
    let mainWin = QWidget(h: self.splitterH, owned: false)
    let toolbarHeight = cint 28  # fixed toolbar height
    let winH = mainWin.height()
    # Position below toolbar, fixed height (or full if window is smaller)
    let h = if winH - toolbarHeight > cint(TreeHeight): cint(TreeHeight) else: winH - toolbarHeight
    self.container.setGeometry(cint 0, toolbarHeight, cint TreeWidth, h)
    self.container.raiseX()
  except:
    discard

proc newFileTree*(mainWindow: QWidget): FileTree =
  result = FileTree()
  let self = result

  # Create as a child of the main window (plain widget, not a window)
  # We'll position it manually over the content area.
  self.container = QWidget.create(mainWindow, cint 0)
  self.container.owned = false
  self.container.setWindowFlags(cint 0)  # ensure it's a plain widget, not a window

  let layout = QVBoxLayout.create()
  layout.setContentsMargins(cint 0, cint 0, cint 0, cint 0)
  layout.setSpacing(cint 0)
  self.container.setLayout(layout)

  # Header label
  var header = QLabel.create("Files")
  header.owned = false
  QWidget(h: header.h, owned: false).setStyleSheet(
    "QLabel { padding: 4px 8px; font-weight: bold; }")
  layout.addWidget(QWidget(h: header.h, owned: false))

  # File system model
  self.model = QFileSystemModel.create()
  self.model.owned = false
  self.model.setReadOnly(true)

  # Tree view
  self.treeView = QTreeView.create()
  self.treeView.owned = false
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

  layout.addWidget(QWidget(h: self.treeView.h, owned: false))

  # Wire single-click file activation
  let modelH = self.model.h
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
      self.container.show()
      self.container.raiseX()
  except:
    discard

proc isVisible*(self: FileTree): bool {.raises: [].} =
  try: self.container.isVisible()
  except: false
