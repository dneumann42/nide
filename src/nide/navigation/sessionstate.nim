import nide/project/projects
import std/[options, os]

import toml_serialization

import nide/helpers/tomlstore

type
  SavedPaneSession* = object
    filePath*: string
    cursorLine*: int
    cursorColumn*: int
    verticalScroll*: int
    horizontalScroll*: int

  SavedColumnSession* = object
    panes*: seq[SavedPaneSession]

  LastSession* = object
    projectNimbleFile*: string
    activeColumnIndex*: int
    activePaneIndex*: int
    columns*: seq[SavedColumnSession]

proc lastSessionFilePath*(): string =
  nideDirPath() / "last_session.toml"

proc legacyLastSessionFilePath(): string =
  nideDirPath() / "last_session"

proc hasLastSession*(): bool =
  fileExists(lastSessionFilePath()) or fileExists(legacyLastSessionFilePath())

proc isMeaningful*(session: LastSession): bool =
  if session.projectNimbleFile.len > 0:
    return true
  for col in session.columns:
    for pane in col.panes:
      if pane.filePath.len > 0:
        return true
  false

proc loadLastSession*(): Option[LastSession] =
  var path = lastSessionFilePath()
  if not fileExists(path):
    let legacyPath = legacyLastSessionFilePath()
    if not fileExists(legacyPath):
      return none(LastSession)
    path = legacyPath
  let session = loadTomlFile(path, LastSession, "last session")
  if session.isMeaningful():
    some(session)
  else:
    none(LastSession)

proc saveLastSession*(session: LastSession) =
  if not session.isMeaningful():
    return
  discard saveTomlFile(lastSessionFilePath(), session, "last session")
