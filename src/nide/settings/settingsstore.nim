import std/os

import toml_serialization

import nide/helpers/appdirs
import nide/helpers/tomlstore

type
  StoredAppearanceSettings* = object
    themeMode*: string
    transparent*: bool
    lineNumbers*: bool
    font*: string
    fontSize*: int
    editorWheelScrollSpeed*: int
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
  nideConfigDirPath() / SettingsFile

proc loadStoredSettings*(): StoredSettings {.raises: [].} =
  discard ensureDirExists(nideConfigDirPath())
  result = loadTomlFile(settingsFilePath(), StoredSettings, "settings")

proc writeStoredSettings*(settings: StoredSettings) {.raises: [].} =
  discard saveTomlFile(settingsFilePath(), settings, "settings")
