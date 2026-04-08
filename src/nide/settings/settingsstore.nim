import std/os

import toml_serialization

type
  StoredAppearanceSettings* = object
    themeMode*: string
    transparent*: bool
    lineNumbers*: bool
    font*: string
    fontSize*: int
    syntaxTheme*: string
    opacityEnabled*: bool
    opacityLevel*: int

  StoredKeybindingOverride* = object
    command*: string
    key*: string

  StoredNimSettings* = object
    mode*: string
    nimbleInstallPath*: string
    nimbleVersion*: string
    customNimPath*: string
    customNimblePath*: string

  StoredSettings* = object
    appearance*: StoredAppearanceSettings
    restoreLastSessionOnLaunch*: bool
    keybindings*: seq[StoredKeybindingOverride]
    nim*: StoredNimSettings

const SettingsFile* = "settings.toml"

proc settingsFilePath*(): string =
  getConfigDir() / "nide" / SettingsFile

proc loadStoredSettings*(): StoredSettings {.raises: [].} =
  try:
    if not dirExists(getConfigDir() / "nide"):
      createDir(getConfigDir() / "nide")
    let path = settingsFilePath()
    if fileExists(path):
      result = Toml.loadFile(path, StoredSettings)
  except:
    echo getCurrentExceptionMsg()

proc writeStoredSettings*(settings: StoredSettings) {.raises: [].} =
  try:
    if not dirExists(getConfigDir() / "nide"):
      createDir(getConfigDir() / "nide")
    Toml.saveFile(settingsFilePath(), settings)
  except:
    echo getCurrentExceptionMsg()
