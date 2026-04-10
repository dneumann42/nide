import std/[json, os, osproc, strutils]

type
  NimbleRelease* = object
    tag*: string
    downloadUrl*: string

  NimbleInstallResult* = object
    ok*: bool
    message*: string
    nimblePath*: string
    releaseTag*: string

proc defaultNimbleInstallDir*(): string =
  getHomeDir() / ".nimble" / "bin"

proc resolveNimbleInstallDir*(configuredPath: string): string =
  if configuredPath.len > 0: configuredPath else: defaultNimbleInstallDir()

proc nimExecutableName*(base: string): string =
  base & ExeExt

proc currentNimbleAssetSuffix*(): string =
  when defined(windows):
    "x86_64-pc-windows.zip"
  elif defined(macosx):
    "x86_64-unknown_darwin.tar.gz"
  else:
    "x86_64-linux.tar.gz"

proc runCommand(args: openArray[string]): tuple[output: string, code: int] =
  let commandResult = execCmdEx(quoteShellCommand(@args) & " 2>&1")
  (commandResult.output, commandResult.exitCode)

proc copyTreeContents(sourceDir, targetDir: string) =
  for kind, path in walkDir(sourceDir):
    let destination = targetDir / path.extractFilename()
    case kind
    of pcFile, pcLinkToFile:
      copyFile(path, destination)
    of pcDir:
      if not dirExists(destination):
        createDir(destination)
      copyTreeContents(path, destination)
    of pcLinkToDir:
      discard

proc parseLatestNimbleRelease*(jsonContent: string): NimbleRelease =
  let data = parseJson(jsonContent)
  if data.kind != JObject or not data.hasKey("tag_name"):
    return

  result.tag = data["tag_name"].getStr()
  if not data.hasKey("assets") or data["assets"].kind != JArray:
    return

  let expectedSuffix = currentNimbleAssetSuffix()
  for asset in data["assets"]:
    if asset.kind != JObject:
      continue
    if not asset.hasKey("name") or not asset.hasKey("browser_download_url"):
      continue
    let assetName = asset["name"].getStr()
    if assetName.endsWith(expectedSuffix):
      result.downloadUrl = asset["browser_download_url"].getStr()
      return

proc ensureInstallDir(targetDir: string) =
  let parentDir = targetDir.parentDir()
  if parentDir.len > 0 and not dirExists(parentDir):
    createDir(parentDir)
  if not dirExists(targetDir):
    createDir(targetDir)

proc fetchLatestNimbleRelease*(): tuple[release: NimbleRelease, error: string] {.raises: [].} =
  try:
    let (output, code) = runCommand([
      "curl",
      "-fsSL",
      "https://api.github.com/repos/nim-lang/nimble/releases/latest"
    ])
    if code != 0:
      result.error = "Failed to resolve the latest Nimble release: " & output.strip()
      return

    let release = parseLatestNimbleRelease(output)
    if release.tag.len == 0:
      result.error = "Failed to parse the latest Nimble release metadata"
      return
    if release.downloadUrl.len == 0:
      result.error = "No Nimble asset found for this platform"
      return

    result.release = release
  except CatchableError:
    result.error = "Failed to resolve the latest Nimble release"

proc installLatestNimble*(configuredPath: string): NimbleInstallResult {.raises: [].} =
  let targetDir = resolveNimbleInstallDir(configuredPath)
  let releaseInfo = fetchLatestNimbleRelease()
  if releaseInfo.error.len > 0:
    result.message = releaseInfo.error
    return

  try:
    ensureInstallDir(targetDir)
  except CatchableError:
    result.message = "Failed to create install directory"
    return

  let release = releaseInfo.release
  let archiveExt =
    if release.downloadUrl.endsWith(".zip"): ".zip"
    elif release.downloadUrl.endsWith(".tar.gz"): ".tar.gz"
    else: ".archive"
  let tempBase = "nide-nimble-" & $getCurrentProcessId()
  let archivePath = getTempDir() / (tempBase & archiveExt)

  try:
    let (downloadOutput, downloadCode) = runCommand([
      "curl",
      "-fsSL",
      "-o",
      archivePath,
      release.downloadUrl
    ])
    if downloadCode != 0:
      result.message = "Failed to download Nimble: " & downloadOutput.strip()
      return
  except CatchableError:
    result.message = "Failed to download Nimble"
    return

  try:
    if release.downloadUrl.endsWith(".zip"):
      when defined(windows):
        let extractDir = getTempDir() / (tempBase & "-extract")
        if dirExists(extractDir):
          removeDir(extractDir)
        createDir(extractDir)
        let psCommand =
          "Expand-Archive -LiteralPath '" & archivePath.replace("'", "''") &
          "' -DestinationPath '" & extractDir.replace("'", "''") & "' -Force"
        let (extractOutput, extractCode) = runCommand([
          "powershell",
          "-NoProfile",
          "-Command",
          psCommand
        ])
        if extractCode != 0:
          result.message = "Failed to extract Nimble: " & extractOutput.strip()
          return

        var extractedRoot = extractDir
        let nimbleExe = nimExecutableName("nimble")
        if not fileExists(extractDir / nimbleExe):
          for kind, path in walkDir(extractDir):
            if kind == pcDir and fileExists(path / nimbleExe):
              extractedRoot = path
              break

        if not fileExists(extractedRoot / nimbleExe):
          result.message = "Failed to extract Nimble: missing executable"
          return

        copyTreeContents(extractedRoot, targetDir)
      else:
        let (extractOutput, extractCode) = runCommand([
          "unzip",
          "-oq",
          archivePath,
          "-d",
          targetDir
        ])
        if extractCode != 0:
          result.message = "Failed to extract Nimble: " & extractOutput.strip()
          return
    else:
      let (extractOutput, extractCode) = runCommand([
        "tar",
        "-xzf",
        archivePath,
        "-C",
        targetDir,
        "--strip-components=1"
      ])
      if extractCode != 0:
        result.message = "Failed to extract Nimble: " & extractOutput.strip()
        return
  except CatchableError:
    result.message = "Failed to extract Nimble"
    return
  finally:
    try:
      if fileExists(archivePath):
        removeFile(archivePath)
    except CatchableError:
      discard

  result.ok = true
  result.releaseTag = release.tag
  result.nimblePath = targetDir / nimExecutableName("nimble")
  result.message = "Nimble " & release.tag & " installed successfully!"
