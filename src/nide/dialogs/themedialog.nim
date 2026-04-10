import std/[strutils, tables]
import seaqt/[qwidget, qvboxlayout, qhboxlayout, qlayout, qdialog,
              qlistwidget, qlistwidgetitem, qplaintextedit, qfont,
              qsplitter, qdialogbuttonbox, qlabel, qpalette, qcolor, qbrush,
              qshortcut, qkeysequence, qobject, qcombobox]
import nide/settings/syntaxtheme, nide/editor/highlight
import nide/helpers/qtconst
import nide/ui/widgets

const
  PreviewFontSize = 11
  ThemeDialogWidth = cint 820
  ThemeDialogHeight = cint 520

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

    result.listWidget = newWidget(QListWidget.create())
    let listH = result.listWidget.h

    var selectedIdx = 0
    for idx, name in themes:
      result.listWidget.addItem(name)
      if name == currentName:
        selectedIdx = idx
    result.listWidget.setCurrentRow(cint selectedIdx)

    result.preview = newWidget(QPlainTextEdit.create())
    result.preview.setReadOnly(true)
    var previewFont = QFont.create("Fira Code")
    previewFont.setPointSize(PreviewFontSize)
    previewFont.setStyleHint(cint(QFontStyleHintEnum.TypeWriter))
    result.preview.asWidget.setFont(previewFont)
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
      except CatchableError: discard

    applyPreviewTheme(currentName)

    result.splitter = newWidget(QSplitter.create(Horizontal))   # horizontal
    result.splitter.addWidget(QWidget(h: listH, owned: false))
    result.splitter.addWidget(QWidget(h: previewH, owned: false))
    result.splitter.setStretchFactor(cint 0, cint 1)
    result.splitter.setStretchFactor(cint 1, cint 2)

    QListWidget(h: listH, owned: false).onCurrentRowChanged do(row: cint) {.raises: [].}:
      if row >= 0 and row < cint(themes.len):
        applyPreviewTheme(themes[row])
  except CatchableError: discard

proc currentThemeSelection*(picker: ThemePickerWidget): string {.raises: [].} =
  ## Return the name of the currently highlighted theme in the picker.
  try:
    let row = picker.listWidget.currentRow()
    if row >= 0 and row < cint(picker.themes.len):
      return picker.themes[row]
  except CatchableError: discard

# ── Standalone theme-picker dialog ─────────────────────────────────────────

proc showThemeDialog*(
  parent: QWidget,
  currentName: string,
  onSelected: proc(name: string) {.raises: [].}
) {.raises: [].} =
  try:
    var dialog = newWidget(QDialog.create(parent))
    let dialogH = dialog.h
    QWidget(h: dialogH, owned: false).setWindowTitle("Syntax Theme")
    QWidget(h: dialogH, owned: false).resize(ThemeDialogWidth, ThemeDialogHeight)

    var titleLabel = newWidget(QLabel.create("Select a syntax highlighting theme:"))

    let picker = buildThemePickerWidget(
      QWidget(h: dialogH, owned: false), currentName)

    var buttonBox = newWidget(QDialogButtonBox.create(Btn_OkCancel2))  # Ok | Cancel

    var outerLayout = vbox()
    outerLayout.addWidget(titleLabel.asWidget, cint 0)
    outerLayout.addWidget(picker.splitter.asWidget, cint 1)
    outerLayout.addWidget(buttonBox.asWidget, cint 0)
    outerLayout.applyTo(QWidget(h: dialogH, owned: false))

    buttonBox.onAccepted do() {.raises: [].}:
      let name = picker.currentThemeSelection()
      if name.len > 0:
        QDialog(h: dialogH, owned: false).accept()
        onSelected(name)

    buttonBox.onRejected do() {.raises: [].}:
      QDialog(h: dialogH, owned: false).reject()

    # Enter key to accept
    var enterSc = newWidget(QShortcut.create(QKeySequence.create("Return"),
                                             QObject(h: dialogH, owned: false)))
    enterSc.setContext(SC_WindowShortcut)  # WindowShortcut
    enterSc.onActivated do() {.raises: [].}:
      let name = picker.currentThemeSelection()
      if name.len > 0:
        QDialog(h: dialogH, owned: false).accept()
        onSelected(name)

    discard QDialog(h: dialogH, owned: false).exec()
  except CatchableError: discard
