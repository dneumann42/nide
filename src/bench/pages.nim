import seaqt/[
  qwidget, 
  qboxlayout, 
  qpushbutton, 
  qtoolbar, 
  qmenu, 
  qfontdatabase,
  qsplitter,
  qfont
]

type
  Page* = ref object of RootObj
    widget: QWidget 
    
  EditPage* = ref object of Page
    monoFont*: QFont
    toolbar*: QToolbar
  DashboardPage* = ref object of Page
    startButton: QPushButton

proc widget*(self: Page): lent QWidget =
  self.widget

method build*(self: Page) {.base.} =
  discard

method build*(self: EditPage) =
  discard

proc onStart*(self: DashboardPage, clicked: proc(): void {.raises: [].}) =
  discard 

method build*(self: DashboardPage) =
  self.widget = QWidget.create()
  let dashLayout = QVBoxLayout.create()
  self.startButton = QPushButton.create("Start")
  self.startButton.setFixedWidth(120)
  QLayout(h: dashLayout.h, owned: false).setContentsMargins(0, 0, 0, 0)
  dashLayout.addStretch()
  dashLayout.addWidget(QWidget(h: self.startButton.h, owned: false), 0, 132)
  dashLayout.addStretch()
  self.widget.setLayout(QLayout(h: dashLayout.h, owned: false))
