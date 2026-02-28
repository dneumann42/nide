import std/strformat, seaqt/[qapplication, qpushbutton]

let
  _ = QApplication.create() # Initialize the Qt library
  btn = QPushButton.create("Hello seaqt!")

QApplication.setApplicationName(" DEV ")

btn.setFixedWidth(320)

var counter = 0
btn.onPressed do():
  counter += 1
  btn.setText(&"You have clicked the button {counter} time(s)")

btn.show()

when isMainModule:
  quit QApplication.exec().int
