import seaqt/[qapplication, qvboxlayout, qboxlayout, qlayout, qwidget, qfiledialog]

import bench/[application, toolbar, buffers]

proc start() =
  let _ = QApplication.create()
  var application = Application.new()
  application.build()
  application.show()
  quit QApplication.exec().int

when isMainModule:
  start()
