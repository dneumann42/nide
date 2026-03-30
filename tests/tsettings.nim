import std/[os, unittest]

import nide/settingsstore

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
