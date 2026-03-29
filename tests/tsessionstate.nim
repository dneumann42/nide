import std/[options, os, unittest]

import nide/[projects, sessionstate]
import toml_serialization

const TestHome = "/tmp/nide-test-home"

proc sessionPaths(): tuple[sessionPath, backupPath, legacyPath, legacyBackupPath: string] =
  let sessionPath = lastSessionFilePath()
  let legacyPath = nideDirPath() / "last_session"
  (sessionPath, sessionPath & ".bak-test", legacyPath, legacyPath & ".bak-test")

suite "sessionstate":
  let originalHome = getHomeDir()

  setup:
    putEnv("HOME", TestHome)
    createDir(TestHome)
    createDir(TestHome / ".local")
    createDir(nideDirPath())
    let (sessionPath, backupPath, legacyPath, legacyBackupPath) = sessionPaths()
    if fileExists(backupPath):
      removeFile(backupPath)
    if fileExists(legacyBackupPath):
      removeFile(legacyBackupPath)
    if fileExists(sessionPath):
      moveFile(sessionPath, backupPath)
    if fileExists(legacyPath):
      moveFile(legacyPath, legacyBackupPath)

  teardown:
    let (sessionPath, backupPath, legacyPath, legacyBackupPath) = sessionPaths()
    if fileExists(sessionPath):
      removeFile(sessionPath)
    if fileExists(legacyPath):
      removeFile(legacyPath)
    if fileExists(backupPath):
      moveFile(backupPath, sessionPath)
    if fileExists(legacyBackupPath):
      moveFile(legacyBackupPath, legacyPath)
    putEnv("HOME", originalHome)

  test "save and load round-trip session state":
    let original = LastSession(
      projectNimbleFile: "/tmp/demo/demo.nimble",
      activeColumnIndex: 1,
      activePaneIndex: 0,
      columns: @[
        SavedColumnSession(panes: @[
          SavedPaneSession(
            filePath: "/tmp/demo/src/a.nim",
            cursorLine: 10,
            cursorColumn: 4,
            verticalScroll: 120,
            horizontalScroll: 8)
        ]),
        SavedColumnSession(panes: @[
          SavedPaneSession(
            filePath: "/tmp/demo/src/b.nim",
            cursorLine: 3,
            cursorColumn: 2,
            verticalScroll: 40,
            horizontalScroll: 0)
        ])
      ])
    saveLastSession(original)

    let loaded = loadLastSession()
    check loaded.isSome()
    if loaded.isSome():
      check loaded.get().projectNimbleFile == original.projectNimbleFile
      check loaded.get().activeColumnIndex == 1
      check loaded.get().activePaneIndex == 0
      check loaded.get().columns.len == 2
      check loaded.get().columns[0].panes[0].cursorLine == 10
      check loaded.get().columns[0].panes[0].verticalScroll == 120
      check loaded.get().columns[1].panes[0].filePath == "/tmp/demo/src/b.nim"

  test "empty session is not considered restorable":
    saveLastSession(LastSession())
    check loadLastSession().isNone()

  test "empty session does not overwrite previous meaningful session":
    let original = LastSession(
      projectNimbleFile: "/tmp/demo/demo.nimble",
      columns: @[
        SavedColumnSession(panes: @[
          SavedPaneSession(filePath: "/tmp/demo/src/main.nim")
        ])
      ])
    saveLastSession(original)
    saveLastSession(LastSession())

    let loaded = loadLastSession()
    check loaded.isSome()
    if loaded.isSome():
      check loaded.get().projectNimbleFile == original.projectNimbleFile

  test "load supports legacy last_session filename":
    let legacySessionPath = nideDirPath() / "last_session"
    Toml.saveFile(legacySessionPath, LastSession(
      projectNimbleFile: "/tmp/demo/demo.nimble",
      columns: @[
        SavedColumnSession(panes: @[
          SavedPaneSession(filePath: "/tmp/demo/src/main.nim")
        ])
      ]
    ))

    let loaded = loadLastSession()
    check loaded.isSome()
    if loaded.isSome():
      check loaded.get().projectNimbleFile == "/tmp/demo/demo.nimble"
