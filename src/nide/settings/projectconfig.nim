import std/[json, os]

type
  ProjectConfig* = object
    useSystemNim*: bool
    nimPath*: string
    nimblePath*: string

proc projectConfigFilePath*(projectRoot: string): string =
  if projectRoot.len == 0: "" else: projectRoot / ".nide.json"

proc parseProjectConfig*(content: string): ProjectConfig =
  let node = parseJson(content)
  if node.kind != JObject:
    return

  if node.hasKey("useSystemNim") and node["useSystemNim"].kind == JBool:
    result.useSystemNim = node["useSystemNim"].getBool()
  if node.hasKey("nimPath") and node["nimPath"].kind == JString:
    result.nimPath = node["nimPath"].getStr()
  if node.hasKey("nimblePath") and node["nimblePath"].kind == JString:
    result.nimblePath = node["nimblePath"].getStr()

proc loadProjectConfig*(projectRoot: string): ProjectConfig {.raises: [].} =
  let path = projectConfigFilePath(projectRoot)
  if path.len == 0 or not fileExists(path):
    return

  try:
    result = parseProjectConfig(readFile(path))
  except CatchableError:
    discard

proc saveProjectConfig*(projectRoot: string, config: ProjectConfig) {.raises: [].} =
  let path = projectConfigFilePath(projectRoot)
  if path.len == 0:
    return

  try:
    let node = %*{
      "useSystemNim": config.useSystemNim,
      "nimPath": config.nimPath,
      "nimblePath": config.nimblePath
    }
    writeFile(path, pretty(node, indent = 2) & "\n")
  except CatchableError:
    discard
