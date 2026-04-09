import nide/project/projects
import std/[options, os]

import toml_serialization

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
  try:
    let session = Toml.loadFile(path, LastSession)
    if session.isMeaningful():
      some(session)
    else:
      none(LastSession)
  except CatchableError as e:
    echo "Failed to load last session: ", e.msg
    none(LastSession)

proc saveLastSession*(session: LastSession) =
  if not session.isMeaningful():
    return
  try:
    if not dirExists(nideDirPath()):
      createDir(nideDirPath())
    Toml.saveFile(lastSessionFilePath(), session)
  except CatchableError as e:
    echo "Failed to save last session: ", e.msg
