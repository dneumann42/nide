import seaqt/[qapplication, qvboxlayout, qboxlayout, qlayout, qwidget, qfiledialog]
import bench/[toolbar, buffers]

type
  Application* = ref object
    bufferManager: BufferManager
    toolbar: Toolbar
    root: QWidget

proc buffers*(app: Application): lent BufferManager =
  result = app.bufferManager

proc new*(T: typedesc[Application]): T =
  result = T(
    bufferManager: BufferManager.init(),
    toolbar: Toolbar()
  )

proc build*(self: Application) =
  let rootLayout = QVBoxLayout.create()

  self.root = QWidget.create()
  self.toolbar.build()

  QLayout(h: rootLayout.h, owned: false).setContentsMargins(0, 0, 0, 0)
  rootLayout.addWidget(self.toolbar.widget())
  QBoxLayout(h: rootLayout.h, owned: false).addStretch()

  self.toolbar.onTriggered(OpenFile) do():
    let fn = QFileDialog.getOpenFileName(self.root)
    echo fn

  self.toolbar.onTriggered(Quit) do():
    QApplication.quit()
  
  self.root.setLayout(rootLayout)

proc show*(self: Application) =
  self.root.show()
