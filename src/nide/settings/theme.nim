import seaqt/[qapplication, qpalette, qcolor, qstylefactory, qstyle]

type Theme* = enum Light, Dark

proc windowColor*(theme: Theme): string =
  case theme
  of Dark: "#000000"
  of Light: "#f0f0f0"

proc surfaceColor*(theme: Theme): string =
  case theme
  of Dark: "#0d0d0d"
  of Light: "#ffffff"

proc headerColor*(theme: Theme): string =
  case theme
  of Dark: "#1a1a1a"
  of Light: "#e6e6e6"

proc textColor*(theme: Theme): string =
  case theme
  of Dark: "#ffffff"
  of Light: "#000000"

proc mutedTextColor*(theme: Theme): string =
  case theme
  of Dark: "#888888"
  of Light: "#6b6b6b"

proc borderColor*(theme: Theme): string =
  case theme
  of Dark: "#333333"
  of Light: "#c7c7c7"

proc highlightColor*(theme: Theme): string =
  "#2a82da"

proc highlightedTextColor*(theme: Theme): string =
  case theme
  of Dark, Light: "#000000"

proc chromeIconColor*(theme: Theme, enabled = true): string =
  if not enabled:
    mutedTextColor(theme)
  else:
    textColor(theme)

proc paneHeaderBaseColor*(theme: Theme): string =
  case theme
  of Dark: windowColor(theme)
  of Light: headerColor(theme)

proc paneHeaderAccentColor*(theme: Theme): string =
  highlightColor(theme)

proc paneHeaderIconColor*(theme: Theme, focused: bool): string =
  if focused:
    "#000000"
  else:
    chromeIconColor(theme)

proc applyTheme*(theme: Theme) =
  # Fusion style makes QPalette work reliably cross-platform
  let style = QStyleFactory.createX("Fusion")
  QApplication.setStyle(style)

  let palette = QPalette.create()
  case theme
  of Dark:
    palette.setColor(cint QPaletteColorRoleEnum.Window,          QColor.fromString(windowColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.WindowText,      QColor.fromString(textColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.Base,            QColor.fromString(surfaceColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.AlternateBase,   QColor.fromString("#111111"))
    palette.setColor(cint QPaletteColorRoleEnum.ToolTipBase,     QColor.fromString(headerColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.ToolTipText,     QColor.fromString(textColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.Text,            QColor.fromString(textColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.Button,          QColor.fromString(headerColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.ButtonText,      QColor.fromString(textColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.BrightText,      QColor.fromString("#ff4444"))
    palette.setColor(cint QPaletteColorRoleEnum.Link,            QColor.fromString(highlightColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.Highlight,       QColor.fromString(highlightColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.HighlightedText, QColor.fromString(highlightedTextColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.PlaceholderText, QColor.fromString(mutedTextColor(theme)))
    # Explicit border/frame roles so Fusion draws visible edges on black
    palette.setColor(cint QPaletteColorRoleEnum.Light,           QColor.fromString("#606060"))
    palette.setColor(cint QPaletteColorRoleEnum.Midlight,        QColor.fromString(borderColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.Mid,             QColor.fromString("#4a4a4a"))
    palette.setColor(cint QPaletteColorRoleEnum.Dark,            QColor.fromString("#222222"))
    palette.setColor(cint QPaletteColorRoleEnum.Shadow,          QColor.fromString(windowColor(theme)))
  of Light:
    palette.setColor(cint QPaletteColorRoleEnum.Window,          QColor.fromString(windowColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.WindowText,      QColor.fromString(textColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.Base,            QColor.fromString(surfaceColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.AlternateBase,   QColor.fromString("#f7f7f7"))
    palette.setColor(cint QPaletteColorRoleEnum.ToolTipBase,     QColor.fromString(surfaceColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.ToolTipText,     QColor.fromString(textColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.Text,            QColor.fromString(textColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.Button,          QColor.fromString(headerColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.ButtonText,      QColor.fromString(textColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.BrightText,      QColor.fromString("#ff4444"))
    palette.setColor(cint QPaletteColorRoleEnum.Link,            QColor.fromString(highlightColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.Highlight,       QColor.fromString(highlightColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.HighlightedText, QColor.fromString(highlightedTextColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.PlaceholderText, QColor.fromString(mutedTextColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.Light,           QColor.fromString("#ffffff"))
    palette.setColor(cint QPaletteColorRoleEnum.Midlight,        QColor.fromString("#d9d9d9"))
    palette.setColor(cint QPaletteColorRoleEnum.Mid,             QColor.fromString(borderColor(theme)))
    palette.setColor(cint QPaletteColorRoleEnum.Dark,            QColor.fromString("#a0a0a0"))
    palette.setColor(cint QPaletteColorRoleEnum.Shadow,          QColor.fromString("#7f7f7f"))
  QApplication.setPalette(palette)
