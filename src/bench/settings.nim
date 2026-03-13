import seaqt/[qwidget, qdialog, qformlayout]
import toml_serialization, os

import theme

type
  AppearanceSettings* = object
    themeMode: Theme
    transparent: bool
    lineNumbers: bool
    font = "Monospace"
    fontSize = 12
    syntaxTheme = "VS Code Dark+"

  Settings* = object
    appearance: AppearanceSettings

proc syntaxTheme*(s: Settings): string = s.appearance.syntaxTheme
proc `syntaxTheme=`*(s: var Settings, v: string) = s.appearance.syntaxTheme = v

proc load*(T: typedesc[Settings]): T {.raises: [].} =
  result = T()
  try:
    if not dirExists(getConfigDir() / "bench"):
      createDir(getConfigDir() / "bench")
    let path = getConfigDir() / "bench" / "settings.toml"
    if fileExists(path):
      result = Toml.decode(readFile(path), typeof result)
  except:
    echo getCurrentExceptionMsg()

proc write*(settings: Settings) {.raises: [].} =
  try:
    if not dirExists(getConfigDir() / "bench"):
      createDir(getConfigDir() / "bench")

    let path = getConfigDir() / "bench" / "settings.toml"
    writeFile(path, Toml.encode(settings))
  except:
    echo getCurrentExceptionMsg()

proc showSettingsDialog*(
  parent: QWidget
) {.raises: [].} =
  try:
    var dialog = QDialog.create(parent)
    dialog.owned = false
    let dialogH = dialog.h
    
    QWidget(h: dialogH, owned: false).setWindowTitle("Settings")
    QWidget(h: dialogH, owned: false).resize(cint 640, cint 480)

    var form = QFormLayout.create()
    form.owned = false

    discard QDialog(h: dialogH, owned: false).exec()
  except:
    discard
