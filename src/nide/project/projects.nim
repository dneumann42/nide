import std/[options, os, dirs, strformat, sequtils]

import toml_serialization

 # derive vcs from directory
type
  Project* = object
    path*: string
    name*, version*, author*: string
    description*, license*, nimVersion*: string

  ProjectRecentFiles* = object
    project*: string
    files*: seq[string]

  ProjectManager* = object
    openProject: Option[string]
    projects: seq[string]
    recentProjects*: seq[string]
    projectFiles*: seq[ProjectRecentFiles]

proc nideDirPath*(): string =
  getHomeDir() / ".local" / "nide"

proc hasNoProjects*(pm: ProjectManager): bool =
  pm.projects.len() == 0

iterator projects*(pm: ProjectManager): string =
  for p in pm.projects: yield p

proc addProject*(self: var ProjectManager, path: string) =
  self.projects.add(path)

proc projectsFileExists(): bool =
  result = fileExists(nideDirPath() / "projects.toml")

proc write*(self: ProjectManager)

proc load*(self: var ProjectManager) =
  if not projectsFileExists():
    let pm = ProjectManager()
    pm.write()
  try:
    self = Toml.loadFile(nideDirPath() / "projects.toml", ProjectManager)
  except CatchableError as e:
    echo "Failed to load projects: ", e.msg

proc write*(self: ProjectManager) =
  try:
    Toml.saveFile(nideDirPath() / "projects.toml", self)
  except CatchableError as e:
    echo "Failed to save projects: ", e.msg

proc createProject*(self: var ProjectManager, project: Project, noWrite = false) =
  let projectDir = project.path / project.name
  self.projects.add(projectDir)

  try:
    createDir(projectDir / "src")

    let nimbleContents = fmt"""
# Package
version     = "{project.version}"
author      = "{project.author}"
description = "{project.description}"
license     = "{project.license}"
srcDir      = "src"

# Dependencies
requires "nim >= {project.nimVersion}"
"""

    writeFile(projectDir / project.name & ".nimble", nimbleContents)
    writeFile(projectDir / "src" / project.name & ".nim", "")
  except OSError as e:
    echo "Failed to create project files: ", e.msg
  except IOError as e:
    echo "Failed to create project files: ", e.msg

  if not noWrite:
    self.write()

const MaxRecentProjects = 10
const MaxRecentFiles = 20

proc recordOpenedProject*(self: var ProjectManager, path: string) =
  self.recentProjects = self.recentProjects.filterIt(it != path)
  self.recentProjects.insert(path, 0)
  if self.recentProjects.len > MaxRecentProjects:
    self.recentProjects.setLen(MaxRecentProjects)
  self.write()

proc recordOpenedFile*(self: var ProjectManager, projectPath, filePath: string) =
  var found = false
  for prf in self.projectFiles.mitems:
    if prf.project == projectPath:
      prf.files = prf.files.filterIt(it != filePath)
      prf.files.insert(filePath, 0)
      if prf.files.len > MaxRecentFiles:
        prf.files.setLen(MaxRecentFiles)
      found = true
      break
  if not found:
    self.projectFiles.add(ProjectRecentFiles(project: projectPath, files: @[filePath]))
  self.write()

proc recentFilesFor*(self: ProjectManager, projectPath: string): seq[string] =
  for prf in self.projectFiles:
    if prf.project == projectPath:
      return prf.files

proc init*(T: typedesc[ProjectManager]): T {.raises: [].} =
  let nidePath = nideDirPath()
  try:
    if not dirExists(nidePath):
      createDir(nidePath)
  except OSError, IOError:
    echo getCurrentExceptionMsg() 
  result = T()
