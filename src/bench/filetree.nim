import seaqt/[qwidget, qvboxlayout, qtreeview, qfilesystemmodel, qabstractitemview,
               qabstractitemmodel, qheaderview, qlabel]

const TreeWidth = 320
const TreeHeight = 420

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

  # Tree view
  self.treeView = QTreeView.create()
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
