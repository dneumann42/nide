import seaqt/[qwidget, qvboxlayout, qhboxlayout, qlayout, qdialog,
              qlistwidget, qlistwidgetitem, qplaintextedit, qfont,
              qsplitter, qdialogbuttonbox, qlabel, qpalette, qcolor, qbrush]
import bench/[syntaxtheme, highlight]

const SampleCode = """# Nim syntax highlighting preview
import std/[strutils, tables]

type
  Animal* = ref object of RootObj
    name: string
    age: int

  Dog = object
    breed: string
    weight: float

proc greet(animal: Animal): string =
  ## Returns a greeting for the animal
  result = "Hello, " & animal.name & "!"

func factorial(n: Natural): int =
  if n <= 1: return 1
  result = n * factorial(n - 1)

let message = "The answer is: " & $42
var count = 0xFF_FF'u16
const Pi = 3.14159

#[
  This is a block comment
  that spans multiple lines
]#

iterator items*[T](arr: openArray[T]): T {.inline.} =
  for i in 0..<arr.len:
    yield arr[i]

when isMainModule:
  var table = initTable[string, int]()
  table["one"] = 1
  echo greet(Animal(name: "Rex", age: 5))
  discard factorial(10)
"""

proc showThemeDialog*(
  parent: QWidget,
  currentName: string,
  onSelected: proc(name: string) {.raises: [].}
) {.raises: [].} =
  try:
    var dialog = QDialog.create(parent)
    dialog.owned = false
    let dialogH = dialog.h
    QWidget(h: dialogH, owned: false).setWindowTitle("Syntax Theme")
    QWidget(h: dialogH, owned: false).resize(cint 820, cint 520)

    var titleLabel = QLabel.create("Select a syntax highlighting theme:")
    titleLabel.owned = false

    var listWidget = QListWidget.create()
    listWidget.owned = false
    let listH = listWidget.h

    let themes = availableThemes()
    var selectedIdx = 0
    for idx, name in themes:
      QListWidget(h: listH, owned: false).addItem(name)
      if name == currentName:
        selectedIdx = idx
    QListWidget(h: listH, owned: false).setCurrentRow(cint selectedIdx)

    var preview = QPlainTextEdit.create()
    preview.owned = false
    preview.setReadOnly(true)
    var previewFont = QFont.create("Fira Code")
    previewFont.setPointSize(11)
    previewFont.setStyleHint(cint(QFontStyleHintEnum.TypeWriter))
    QWidget(h: preview.h, owned: false).setFont(previewFont)
    let previewH = preview.h

    # Attach highlighter to preview
    let previewHl = NimHighlighter()
    previewHl.attach(preview.document())

    preview.setPlainText(SampleCode)

    proc applyPreviewTheme(name: string) {.raises: [].} =
      try:
        let theme = getTheme(name)
        # Update preview editor colors
        let pw = QWidget(h: previewH, owned: false)
        var pal = pw.palette()
        pal.setColor(cint QPaletteColorRoleEnum.Base,
          QColor.fromString(theme.editor.background))
        pal.setColor(cint QPaletteColorRoleEnum.Text,
          QColor.fromString(theme.editor.foreground))
        pw.setPalette(pal)

        # Save and restore global theme, apply preview theme temporarily
        let savedName = currentThemeName
        setCurrentTheme(name)
        previewHl.rehighlight()
        # Restore previous theme (don't apply to main editor yet)
        setCurrentTheme(savedName)
      except:
        discard

    # Apply initial preview
    applyPreviewTheme(currentName)

    var splitter = QSplitter.create(cint 1)  # horizontal
    splitter.owned = false
    splitter.addWidget(QWidget(h: listWidget.h, owned: false))
    splitter.addWidget(QWidget(h: preview.h, owned: false))
    splitter.setStretchFactor(cint 0, cint 1)
    splitter.setStretchFactor(cint 1, cint 2)

    var buttonBox = QDialogButtonBox.create(
      cint(0x00000400 or 0x00400000))  # Ok | Cancel
    buttonBox.owned = false
    let buttonBoxH = buttonBox.h

    var outerLayout = QVBoxLayout.create()
    outerLayout.owned = false
    outerLayout.addWidget(QWidget(h: titleLabel.h, owned: false))
    outerLayout.addWidget(QWidget(h: splitter.h, owned: false))
    outerLayout.addWidget(QWidget(h: buttonBox.h, owned: false))
    QWidget(h: dialogH, owned: false).setLayout(
      QLayout(h: outerLayout.h, owned: false))

    listWidget.onCurrentRowChanged do(row: cint) {.raises: [].}:
      if row >= 0 and row < cint(themes.len):
        applyPreviewTheme(themes[row])

    buttonBox.onAccepted do() {.raises: [].}:
      let lw = QListWidget(h: listH, owned: false)
      let row = lw.currentRow()
      if row >= 0 and row < cint(themes.len):
        QDialog(h: dialogH, owned: false).accept()
        onSelected(themes[row])

    buttonBox.onRejected do() {.raises: [].}:
      QDialog(h: dialogH, owned: false).reject()

    discard QDialog(h: dialogH, owned: false).exec()
  except: discard
