import seaqt/[qapplication]
import bench/application

proc start() =
  let _ = QApplication.create()
  var application = Application.new()
  QApplication.setApplicationName("Bench DEV 0.0.1")
  application.build()
  application.show()
  quit QApplication.exec().int
 
when isMainModule:
  start()
