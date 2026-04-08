import std/[tables, strutils]
import seaqt/[qabstractfileiconprovider, qfileinfo, qicon, qpixmap,
              qpainter, qcolor, qfont, qfontdatabase, qpaintdevice, qrect]
import nide/helpers/qtconst

const IconSize = 16

type IconDef = tuple[glyph: string, color: string]

const extIcons: Table[string, IconDef] = {
  "nim":              ("\ue26e", "#FFE953"),
  "nims":             ("\ue26e", "#FFE953"),
  "nimble":           ("\ue26e", "#FFE953"),
  "nimcfg":           ("\ue26e", "#FFE953"),
  "py":               ("\ue73c", "#3776AB"),
  "pyi":              ("\ue73c", "#3776AB"),
  "pyw":              ("\ue73c", "#3776AB"),
  "js":               ("\ue74e", "#F7DF1E"),
  "mjs":              ("\ue74e", "#F7DF1E"),
  "cjs":              ("\ue74e", "#F7DF1E"),
  "jsx":              ("\ue74e", "#F7DF1E"),
  "ts":               ("\ue628", "#3178C6"),
  "tsx":              ("\ue628", "#3178C6"),
  "mts":              ("\ue628", "#3178C6"),
  "html":             ("\ue736", "#E34F26"),
  "htm":              ("\ue736", "#E34F26"),
  "css":              ("\ue749", "#1572B6"),
  "scss":             ("\ue749", "#CC6699"),
  "sass":             ("\ue749", "#CC6699"),
  "json":             ("\ue60b", "#CBCB41"),
  "jsonc":            ("\ue60b", "#CBCB41"),
  "yaml":             ("\ue6d8", "#CB171E"),
  "yml":              ("\ue6d8", "#CB171E"),
  "toml":             ("\ue6b2", "#9C4121"),
  "xml":              ("\ue796", "#E37933"),
  "svg":              ("\ue796", "#FFB13B"),
  "rs":               ("\ue7a8", "#CE422B"),
  "go":               ("\ue724", "#00ADD8"),
  "c":                ("\ue61e", "#A8B9CC"),
  "h":                ("\ue61e", "#A8B9CC"),
  "cpp":              ("\ue61d", "#00599C"),
  "cc":               ("\ue61d", "#00599C"),
  "cxx":              ("\ue61d", "#00599C"),
  "hpp":              ("\ue61d", "#00599C"),
  "hxx":              ("\ue61d", "#00599C"),
  "zig":              ("\ue6a9", "#F7A41D"),
  "java":             ("\ue738", "#E76F00"),
  "kt":               ("\ue70e", "#A97BFF"),
  "kts":              ("\ue70e", "#A97BFF"),
  "scala":            ("\ue7b4", "#DC322F"),
  "clj":              ("\ue76a", "#63B132"),
  "cljs":             ("\ue76a", "#63B132"),
  "edn":              ("\ue76a", "#63B132"),
  "rb":               ("\ue62b", "#CC342D"),
  "php":              ("\ue73d", "#777BB4"),
  "lua":              ("\ue620", "#000080"),
  "sh":               ("\uf489", "#89E051"),
  "bash":             ("\uf489", "#89E051"),
  "zsh":              ("\uf489", "#89E051"),
  "fish":             ("\uf489", "#89E051"),
  "hs":               ("\ue777", "#5D4F85"),
  "lhs":              ("\ue777", "#5D4F85"),
  "ex":               ("\ue62d", "#A074C4"),
  "exs":              ("\ue62d", "#A074C4"),
  "ml":               ("\ue67a", "#E98228"),
  "mli":              ("\ue67a", "#E98228"),
  "swift":            ("\ue755", "#FA7343"),
  "r":                ("\ue68a", "#276DC2"),
  "rmd":              ("\ue68a", "#276DC2"),
  "vim":              ("\ue7c5", "#019733"),
  "vimrc":            ("\ue7c5", "#019733"),
  "dockerfile":       ("\uf308", "#2496ED"),
  "cmake":            ("\ue794", "#064F8C"),
  "sql":              ("\ue706", "#DAA520"),
  "sqlite":           ("\ue706", "#DAA520"),
  "db":               ("\ue706", "#DAA520"),
  "md":               ("\ue73e", "#519ABA"),
  "markdown":         ("\ue73e", "#519ABA"),
  "gitignore":        ("\ue702", "#F54D27"),
  "gitattributes":    ("\ue702", "#F54D27"),
}.toTable

var nerdFontFamily = ""
var fontSearchDone = false

proc findNerdFont() {.raises: [].} =
  if fontSearchDone: return
  fontSearchDone = true
  try:
    let all = QFontDatabase.families()
    # Prefer the dedicated symbols-only mono font
    for fam in all:
      if fam == "Symbols Nerd Font Mono":
        nerdFontFamily = fam
        return
    # Fall back to any installed Nerd Font (patched fonts carry the same glyphs)
    for fam in all:
      if "Nerd Font" in fam:
        nerdFontFamily = fam
        return
  except:
    discard

proc glyphToIcon(glyph: string, color: string): QIcon {.raises: [].} =
  var pm = QPixmap.create(cint IconSize, cint IconSize)
  pm.fill(QColor.create("transparent"))
  var painter = QPainter.create(QPaintDevice(h: pm.h, owned: false))
  var font = QFont.create(nerdFontFamily)
  font.setPixelSize(cint IconSize)
  painter.setFont(font)
  painter.setPen(QColor.create(color))
  painter.drawText(QRect.create(cint 0, cint 0, cint IconSize, cint IconSize),
                   AlignHCenterVCenter, glyph.toOpenArray(0, glyph.high))
  discard painter.endX()
  QIcon.create(pm)

type DevIconProvider* = ref object of VirtualQAbstractFileIconProvider

method icon*(self: DevIconProvider, info: QFileInfo): QIcon =
  try:
    findNerdFont()
    if nerdFontFamily.len > 0:
      let ext = info.suffix().toLowerAscii()
      if ext in extIcons:
        let (glyph, color) = extIcons[ext]
        return glyphToIcon(glyph, color)
      let fname = info.fileName().toLowerAscii()
      if fname in extIcons:
        let (glyph, color) = extIcons[fname]
        return glyphToIcon(glyph, color)
  except:
    discard
  QAbstractFileIconProvidericon(self[], info)

proc newDevIconProvider*(): DevIconProvider =
  result = DevIconProvider()
  QAbstractFileIconProvider.create(result)
