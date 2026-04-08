## uicolors.nim
## Color tokens for floating overlay widgets (popups, diagnostics, autocomplete).
## These are separate from the QPalette system in theme.nim — they apply to
## overlay widgets whose style is set via setStyleSheet, not palette inheritance.
## The palette is Catppuccin Mocha, which is the current de-facto overlay style.

const
  clBase*       = "#1e1e2e"   # popup/overlay background
  clSurface0*   = "#313244"   # selection / hover highlight
  clSurface2*   = "#585b70"   # border / separator
  clText*       = "#cdd6f4"   # primary text
  clSubtext0*   = "#a6adc8"   # secondary / dimmed text
  clBlue*       = "#89b4fa"   # accent / link
  clGreen*      = "#a6e3a1"   # success / type hint
  clRed*        = "#ff5555"   # error
  clYellow*     = "#ffaa00"   # warning
  clMonoFont*   = "Fira Code"
  clMonoSize*   = "13px"

  # Toolbar project chip
  clChipBg*     = "#1e3a5c"
  clChipText*   = "#cce0ff"

  # Gutter (editor line number sidebar)
  clGutterBg*   = "#000000"
  clGutterBdr*  = "#333333"

proc popupSheet*(bg = clBase, border = clSurface2, fg = clText,
                 font = clMonoFont, size = clMonoSize): string =
  ## Returns a base stylesheet string for floating overlay popup widgets.
  ## Callers may append additional widget-specific rules.
  "QWidget { background: " & bg & "; border: 1px solid " & border &
    "; border-radius: 3px; } " &
  "QLabel { color: " & fg & "; font-family: '" & font &
    "', monospace; font-size: " & size & "; padding: 6px 10px; background: transparent; }"
