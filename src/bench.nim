import bench/application
import seaqt/qapplication

proc start() =
  let _ = QApplication.create()
  var application = Application.new()
  QApplication.setApplicationName("Bench DEV 0.0.1")
  application.build()
  application.show()
  quit QApplication.exec().int

when isMainModule:
  start()
