import nide/application/application
import nide/helpers/qtconst
import seaqt/qapplication

proc start() =
  let _ = QApplication.create()
  var application = Application.new()
  QApplication.setApplicationName("Nide DEV 0.0.1")
  application.build()
  application.show()
  quit QApplication.exec().int

when isMainModule:
  start()
