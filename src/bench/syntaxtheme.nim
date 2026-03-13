import std/[tables, strutils]
import seaqt/[qtextcharformat, qcolor, qbrush, qfont]
import toml_serialization

type
  SyntaxThemeMeta* = object
    name*: string
    variant*: string

  SyntaxThemeEditor* = object
    background*: string
    foreground*: string
    lineNumber*: string
    lineNumberBg*: string
    selection*: string
    currentLine*: string
    primary*: string

  SyntaxThemeSyntax* = object
    keyword*: string
    keywordBold* = true
    keywordItalic* = false
    `type`*: string
    typeBold* = false
    typeItalic* = false
    builtinType*: string
    string*: string
    charLit*: string
    number*: string
    comment*: string
    commentItalic* = true
    docComment*: string
    docCommentItalic* = true
    blockComment*: string
    pragma*: string
    operator*: string
    funcName*: string

  SyntaxTheme* = object
    meta*: SyntaxThemeMeta
    editor*: SyntaxThemeEditor
    syntax*: SyntaxThemeSyntax

  HighlightFormats* = object
    keyword*, `type`*, builtinType*, str*, charLit*, number*: QTextCharFormat
    comment*, docComment*, blockComment*: QTextCharFormat
    pragma*, operator*, funcName*: QTextCharFormat

# Embedded theme TOML sources
const ThemeSources* = [
  staticRead("themes/vscode_dark.toml"),
  staticRead("themes/monokai.toml"),
  staticRead("themes/dracula.toml"),
  staticRead("themes/solarized_dark.toml"),
  staticRead("themes/solarized_light.toml"),
  staticRead("themes/github_light.toml"),
  staticRead("themes/nord.toml"),
]

proc makeFormat(color: string, bold = false, italic = false): QTextCharFormat =
  result = QTextCharFormat.create()
  QTextFormat(h: result.h, owned: false).setForeground(
    QBrush.create(QColor.fromString(color)))
  if bold:
    QTextCharFormat(h: result.h, owned: false).setFontWeight(cint(QFontWeightEnum.Bold))
  if italic:
    QTextCharFormat(h: result.h, owned: false).setFontItalic(true)

proc buildFormats*(theme: SyntaxTheme): HighlightFormats =
  let s = theme.syntax
  result.keyword = makeFormat(s.keyword, s.keywordBold, s.keywordItalic)
  result.`type` = makeFormat(s.`type`, s.typeBold, s.typeItalic)
  result.builtinType = makeFormat(s.builtinType, s.typeBold, s.typeItalic)
  result.str = makeFormat(s.string)
  result.charLit = makeFormat(s.charLit)
  result.number = makeFormat(s.number)
  result.comment = makeFormat(s.comment, italic = s.commentItalic)
  result.docComment = makeFormat(s.docComment, italic = s.docCommentItalic)
  result.blockComment = makeFormat(s.blockComment, italic = s.commentItalic)
  result.pragma = makeFormat(s.pragma)
  result.operator = makeFormat(s.operator)
  result.funcName = makeFormat(s.funcName)

proc buildDefaultFormats*(): HighlightFormats =
  # Fallback hardcoded colors (VS Code Dark+ style)
  result.keyword = makeFormat("#569cd6", bold = true)
  result.`type` = makeFormat("#4ec9b0")
  result.builtinType = makeFormat("#4ec9b0")
  result.str = makeFormat("#ce9178")
  result.charLit = makeFormat("#ce9178")
  result.number = makeFormat("#b5cea8")
  result.comment = makeFormat("#6a9955", italic = true)
  result.docComment = makeFormat("#608b4e", italic = true)
  result.blockComment = makeFormat("#6a9955", italic = true)
  result.pragma = makeFormat("#9cdcfe")
  result.operator = makeFormat("#d4d4d4")
  result.funcName = makeFormat("#dcdcaa")

# Global theme state
var
  allThemes: OrderedTable[string, SyntaxTheme]
  currentThemeName*: string
  currentTheme*: SyntaxTheme
  currentFormats*: HighlightFormats
  themesLoaded = false

proc loadAllThemes*() =
  if themesLoaded and allThemes.len > 0: return
  themesLoaded = true
  for src in ThemeSources:
    try:
      let theme = Toml.decode(src, SyntaxTheme)
      allThemes[theme.meta.name] = theme
    except:
      discard

proc availableThemes*(): seq[string] =
  loadAllThemes()
  for name in allThemes.keys:
    result.add(name)

proc getTheme*(name: string): SyntaxTheme =
  loadAllThemes()
  if allThemes.hasKey(name):
    result = allThemes[name]
  else:
    # fallback to first theme
    for k, v in allThemes:
      return v

proc setCurrentTheme*(name: string) {.raises: [].} =
  try:
    loadAllThemes()
    currentThemeName = name
    currentTheme = getTheme(name)
    currentFormats = buildFormats(currentTheme)
  except:
    # Fallback to default formats if something goes wrong
    currentThemeName = "Fallback"
    currentFormats = buildDefaultFormats()

proc initDefaultTheme*() {.raises: [].} =
  try:
    if currentThemeName.len == 0:
      loadAllThemes()
      setCurrentTheme("VS Code Dark+")
    # Ensure formats are always set
    if currentThemeName.len == 0:
      currentFormats = buildDefaultFormats()
      currentThemeName = "Fallback"
  except:
    currentFormats = buildDefaultFormats()
    currentThemeName = "Fallback"

# Initialize at module load time
loadAllThemes()
if currentThemeName.len == 0:
  setCurrentTheme("VS Code Dark+")

proc editorBackground*(): string {.gcsafe.} = {.cast(gcsafe).}: 
  if currentTheme.editor.background.len > 0: currentTheme.editor.background
  else: "#000000"
proc editorForeground*(): string {.gcsafe.} = {.cast(gcsafe).}: currentTheme.editor.foreground
proc gutterBackground*(): string {.gcsafe.} = {.cast(gcsafe).}: currentTheme.editor.lineNumberBg
proc gutterForeground*(): string {.gcsafe.} = {.cast(gcsafe).}: currentTheme.editor.lineNumber
proc selectionColor*(): string {.gcsafe.} = {.cast(gcsafe).}: currentTheme.editor.selection
proc currentLineColor*(): string {.gcsafe.} = {.cast(gcsafe).}: currentTheme.editor.currentLine
proc primaryColor*(): string {.gcsafe.} = {.cast(gcsafe).}: currentTheme.editor.primary
proc isDarkTheme*(): bool {.gcsafe.} = {.cast(gcsafe).}: currentTheme.meta.variant == "dark"

proc headerGradientColors*(isDark: bool): (string, string) {.gcsafe.} =
  var primary = primaryColor()
  if primary.len == 0:
    primary = "#2a82da"  # fallback
  (primary, "#000000")
