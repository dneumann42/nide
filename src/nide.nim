import nide/application/[application, buildwiring]
import nide/helpers/debuglog
import seaqt/qapplication

proc start() =
  setupLogging()
  let _ = QApplication.create()
  var application = Application.new()
  QApplication.setApplicationName("Nide DEV 0.0.1")
  application.build()
  application.show()
  quit QApplication.exec().int

when isMainModule:
  start()
