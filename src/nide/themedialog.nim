import std/[strutils, tables]
import seaqt/[qwidget, qvboxlayout, qhboxlayout, qlayout, qdialog,
              qlistwidget, qlistwidgetitem, qplaintextedit, qfont,
              qsplitter, qdialogbuttonbox, qlabel, qpalette, qcolor, qbrush,
              qshortcut, qkeysequence, qobject, qcombobox]
import syntaxtheme, highlight

const SampleCode* = """# Nim syntax highlighting preview
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

type
  ThemePickerWidget* = object
    ## Owns a QSplitter containing a theme list and a live syntax preview.
    ## Call `currentName()` to read the selection at any time.
    splitter*:    QSplitter
    listWidget*:  QListWidget
    preview*:     QPlainTextEdit
    themes*:      seq[string]   # ordered list matching list-widget rows

proc buildThemePickerWidget*(
  parent:      QWidget,
  currentName: string,
): ThemePickerWidget {.raises: [].} =
  ## Build a reusable list + preview widget for picking a syntax theme.
  ## The caller is responsible for parenting / laying out `result.splitter`.
  try:
    let themes = availableThemes()
    result.themes = themes

    result.listWidget = QListWidget.create()
    result.listWidget.owned = false
    let listH = result.listWidget.h

    var selectedIdx = 0
    for idx, name in themes:
      QListWidget(h: listH, owned: false).addItem(name)
      if name == currentName:
        selectedIdx = idx
    QListWidget(h: listH, owned: false).setCurrentRow(cint selectedIdx)

    result.preview = QPlainTextEdit.create()
    result.preview.owned = false
    result.preview.setReadOnly(true)
    var previewFont = QFont.create("Fira Code")
    previewFont.setPointSize(11)
    previewFont.setStyleHint(cint(QFontStyleHintEnum.TypeWriter))
    QWidget(h: result.preview.h, owned: false).setFont(previewFont)
    let previewH = result.preview.h

    let previewHl = NimHighlighter()
    previewHl.attach(result.preview.document())

    result.preview.setPlainText(SampleCode)

    proc applyPreviewTheme(name: string) {.raises: [].} =
      try:
        let theme = getTheme(name)
        let pw = QWidget(h: previewH, owned: false)
        var pal = pw.palette()
        pal.setColor(cint QPaletteColorRoleEnum.Base,
          QColor.fromString(theme.editor.background))
        pal.setColor(cint QPaletteColorRoleEnum.Text,
          QColor.fromString(theme.editor.foreground))
        pw.setPalette(pal)
        let savedName = currentThemeName
        setCurrentTheme(name)
        previewHl.rehighlight()
        setCurrentTheme(savedName)
      except: discard

    applyPreviewTheme(currentName)

    result.splitter = QSplitter.create(cint 1)   # horizontal
    result.splitter.owned = false
    result.splitter.addWidget(QWidget(h: listH,              owned: false))
    result.splitter.addWidget(QWidget(h: previewH,           owned: false))
    result.splitter.setStretchFactor(cint 0, cint 1)
    result.splitter.setStretchFactor(cint 1, cint 2)

    QListWidget(h: listH, owned: false).onCurrentRowChanged do(row: cint) {.raises: [].}:
      if row >= 0 and row < cint(themes.len):
        applyPreviewTheme(themes[row])
  except: discard

proc currentThemeSelection*(picker: ThemePickerWidget): string {.raises: [].} =
  ## Return the name of the currently highlighted theme in the picker.
  try:
    let row = QListWidget(h: picker.listWidget.h, owned: false).currentRow()
    if row >= 0 and row < cint(picker.themes.len):
      return picker.themes[row]
  except: discard

# ── Standalone theme-picker dialog ─────────────────────────────────────────

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

    let picker = buildThemePickerWidget(
      QWidget(h: dialogH, owned: false), currentName)

    var buttonBox = QDialogButtonBox.create(
      cint(0x00000400 or 0x00400000))  # Ok | Cancel
    buttonBox.owned = false

    var outerLayout = QVBoxLayout.create()
    outerLayout.owned = false
    outerLayout.addWidget(QWidget(h: titleLabel.h,         owned: false), cint 0)
    outerLayout.addWidget(QWidget(h: picker.splitter.h,    owned: false), cint 1)
    outerLayout.addWidget(QWidget(h: buttonBox.h,          owned: false), cint 0)
    QWidget(h: dialogH, owned: false).setLayout(
      QLayout(h: outerLayout.h, owned: false))

    buttonBox.onAccepted do() {.raises: [].}:
      let name = picker.currentThemeSelection()
      if name.len > 0:
        QDialog(h: dialogH, owned: false).accept()
        onSelected(name)

    buttonBox.onRejected do() {.raises: [].}:
      QDialog(h: dialogH, owned: false).reject()

    # Enter key to accept
    var enterSc = QShortcut.create(QKeySequence.create("Return"),
                                   QObject(h: dialogH, owned: false))
    enterSc.owned = false
    enterSc.setContext(cint 2)  # WindowShortcut
    enterSc.onActivated do() {.raises: [].}:
      let name = picker.currentThemeSelection()
      if name.len > 0:
        QDialog(h: dialogH, owned: false).accept()
        onSelected(name)

    discard QDialog(h: dialogH, owned: false).exec()
  except: discard
