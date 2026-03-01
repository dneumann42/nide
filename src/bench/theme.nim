import seaqt/[qapplication, qpalette, qcolor, qstylefactory, qstyle]

type Theme* = enum Light, Dark

proc applyTheme*(theme: Theme) =
  # Fusion style makes QPalette work reliably cross-platform
  let style = QStyleFactory.createX("Fusion")
  QApplication.setStyle(style)

  let palette = QPalette.create()
  case theme
  of Dark:
    palette.setColor(cint QPaletteColorRoleEnum.Window,          QColor.fromString("#353535"))
    palette.setColor(cint QPaletteColorRoleEnum.WindowText,      QColor.fromString("#ffffff"))
    palette.setColor(cint QPaletteColorRoleEnum.Base,            QColor.fromString("#252525"))
    palette.setColor(cint QPaletteColorRoleEnum.AlternateBase,   QColor.fromString("#353535"))
    palette.setColor(cint QPaletteColorRoleEnum.ToolTipBase,     QColor.fromString("#1a1a1a"))
    palette.setColor(cint QPaletteColorRoleEnum.ToolTipText,     QColor.fromString("#ffffff"))
    palette.setColor(cint QPaletteColorRoleEnum.Text,            QColor.fromString("#ffffff"))
    palette.setColor(cint QPaletteColorRoleEnum.Button,          QColor.fromString("#353535"))
    palette.setColor(cint QPaletteColorRoleEnum.ButtonText,      QColor.fromString("#ffffff"))
    palette.setColor(cint QPaletteColorRoleEnum.BrightText,      QColor.fromString("#ff4444"))
    palette.setColor(cint QPaletteColorRoleEnum.Link,            QColor.fromString("#2a82da"))
    palette.setColor(cint QPaletteColorRoleEnum.Highlight,       QColor.fromString("#2a82da"))
    palette.setColor(cint QPaletteColorRoleEnum.HighlightedText, QColor.fromString("#000000"))
    palette.setColor(cint QPaletteColorRoleEnum.PlaceholderText, QColor.fromString("#888888"))
  of Light:
    discard  # leave palette as default (Fusion light)
  QApplication.setPalette(palette)
