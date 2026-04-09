import std/os

import nide/settings/nimbleinstaller
import nide/settings/projectconfig

type
  ResolvedToolchain* = object
    nimCommand*: string
    nimbleCommand*: string
    nimsuggestCommand*: string
    usesProjectConfig*: bool
    source*: string

proc siblingExecutable(toolPath, baseName: string): string =
  if toolPath.len == 0:
    return ""
  let candidate = toolPath.parentDir() / nimExecutableName(baseName)
  if fileExists(candidate): candidate else: ""

proc resolveExecutableFromPath(baseName: string): string =
  try:
    let resolved = findExe(baseName)
    if resolved.len > 0:
      return resolved
  except:
    discard
  ""

proc resolveExecutable(preferredPath, baseName: string): string =
  if preferredPath.len > 0:
    return preferredPath
  resolveExecutableFromPath(baseName)

proc resolveProjectToolchain*(
    globalNimPath: string,
    globalNimblePath: string,
    projectRoot: string,
    projectConfig: ProjectConfig
): ResolvedToolchain =
  if projectRoot.len > 0 and projectConfig.useSystemNim:
    result.usesProjectConfig = true
    result.nimCommand = resolveExecutable(projectConfig.nimPath, "nim")
    result.nimbleCommand = resolveExecutable(projectConfig.nimblePath, "nimble")
    let projectNimSuggest = siblingExecutable(result.nimCommand, "nimsuggest")
    result.nimsuggestCommand =
      if projectNimSuggest.len > 0:
        projectNimSuggest
      else:
        resolveExecutableFromPath("nimsuggest")
    result.source =
      if projectConfig.nimPath.len > 0 or projectConfig.nimblePath.len > 0:
        "project config"
      else:
        "system PATH"
    return

  result.nimCommand = globalNimPath
  result.nimbleCommand = globalNimblePath
  let globalNimSuggest = siblingExecutable(globalNimPath, "nimsuggest")
  result.nimsuggestCommand =
    if globalNimSuggest.len > 0:
      globalNimSuggest
    else:
      resolveExecutableFromPath("nimsuggest")
  result.source = "global settings"
