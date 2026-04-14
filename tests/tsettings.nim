import std/[os, unittest]

import nide/settings/settingsstore
import nide/settings/settings
import nide/settings/keybindings

const TestHome = "/tmp/nide-settings-test-home"

proc settingsPath(): string =
  settingsFilePath()

suite "settings":
  let originalHome = getHomeDir()

  setup:
    putEnv("HOME", TestHome)
    createDir(TestHome)
    createDir(TestHome / ".config")
    createDir(getConfigDir() / "nide")
    if fileExists(settingsPath()):
      removeFile(settingsPath())

  teardown:
    if fileExists(settingsPath()):
      removeFile(settingsPath())
    putEnv("HOME", originalHome)

  test "missing restore flag defaults to false":
    let loaded = loadStoredSettings()
    check loaded.restoreLastSessionOnLaunch == false

  test "restore flag round trips through settings file":
    var original = StoredSettings()
    original.restoreLastSessionOnLaunch = true
    writeStoredSettings(original)

    let loaded = loadStoredSettings()
    check loaded.restoreLastSessionOnLaunch

  test "editor wheel scroll speed round trips through settings file":
    var original = StoredSettings()
    original.appearance.editorWheelScrollSpeed = 10
    writeStoredSettings(original)

    let loaded = loadStoredSettings()
    check loaded.appearance.editorWheelScrollSpeed == 10

  test "missing keybinding scheme defaults to emacs":
    let loaded = Settings.load()
    check loaded.keybindingScheme == Emacs

  test "keybinding scheme round trips through settings file":
    var original = Settings.load()
    original.keybindingScheme = VSCode
    original.write()

    let loaded = Settings.load()
    check loaded.keybindingScheme == VSCode
