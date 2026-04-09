import std/[os, unittest]

import nide/settings/projectconfig
import nide/settings/toolchain

const TestRoot = "/tmp/nide-projectconfig-test"

suite "projectconfig":
  let originalPath = getEnv("PATH")

  setup:
    if dirExists(TestRoot):
      removeDir(TestRoot)
    createDir(TestRoot)

  teardown:
    if dirExists(TestRoot):
      removeDir(TestRoot)
    putEnv("PATH", originalPath)

  test "missing config falls back to defaults":
    let loaded = loadProjectConfig(TestRoot)
    check loaded.useSystemNim == false
    check loaded.nimPath.len == 0
    check loaded.nimblePath.len == 0

  test "config round trips through .nide.json":
    let original = ProjectConfig(
      useSystemNim: true,
      nimPath: "/nix/store/demo/bin/nim",
      nimblePath: "/nix/store/demo/bin/nimble"
    )
    saveProjectConfig(TestRoot, original)

    let loaded = loadProjectConfig(TestRoot)
    check loaded.useSystemNim
    check loaded.nimPath == original.nimPath
    check loaded.nimblePath == original.nimblePath

  test "malformed json falls back safely":
    writeFile(projectConfigFilePath(TestRoot), "{ not valid json")
    let loaded = loadProjectConfig(TestRoot)
    check loaded.useSystemNim == false
    check loaded.nimPath.len == 0
    check loaded.nimblePath.len == 0

  test "resolver uses project explicit paths when system nim is enabled":
    let projectBinDir = TestRoot / "project-bin"
    createDir(projectBinDir)
    let projectNimPath = projectBinDir / "nim"
    let projectNimblePath = projectBinDir / "nimble"
    let projectNimSuggestPath = projectBinDir / "nimsuggest"
    writeFile(projectNimPath, "")
    writeFile(projectNimblePath, "")
    writeFile(projectNimSuggestPath, "")

    let resolved = resolveProjectToolchain(
      "/global/bin/nim",
      "/global/bin/nimble",
      TestRoot,
      ProjectConfig(
        useSystemNim: true,
        nimPath: projectNimPath,
        nimblePath: projectNimblePath
      )
    )
    check resolved.usesProjectConfig
    check resolved.nimCommand == projectNimPath
    check resolved.nimbleCommand == projectNimblePath
    check resolved.nimsuggestCommand == projectNimSuggestPath
    check resolved.source == "project config"

  test "resolver falls back to PATH executables for system nim without explicit paths":
    let binDir = TestRoot / "bin"
    createDir(binDir)
    let nimPath = binDir / "nim"
    let nimblePath = binDir / "nimble"
    let nimsuggestPath = binDir / "nimsuggest"
    writeFile(nimPath, "")
    writeFile(nimblePath, "")
    writeFile(nimsuggestPath, "")
    setFilePermissions(nimPath, {fpUserExec, fpUserRead, fpUserWrite})
    setFilePermissions(nimblePath, {fpUserExec, fpUserRead, fpUserWrite})
    setFilePermissions(nimsuggestPath, {fpUserExec, fpUserRead, fpUserWrite})
    putEnv("PATH", binDir)

    let resolved = resolveProjectToolchain(
      "/global/bin/nim",
      "/global/bin/nimble",
      TestRoot,
      ProjectConfig(useSystemNim: true)
    )
    check resolved.usesProjectConfig
    check resolved.nimCommand == nimPath
    check resolved.nimbleCommand == nimblePath
    check resolved.nimsuggestCommand == nimsuggestPath
    check resolved.source == "system PATH"

  test "resolver falls back to global toolchain when project override is disabled":
    let nimDir = TestRoot / "global-bin"
    createDir(nimDir)
    let nimsuggestPath = nimDir / "nimsuggest"
    writeFile(nimsuggestPath, "")

    let resolved = resolveProjectToolchain(
      nimDir / "nim",
      nimDir / "nimble",
      TestRoot,
      ProjectConfig(useSystemNim: false)
    )
    check resolved.usesProjectConfig == false
    check resolved.nimCommand == nimDir / "nim"
    check resolved.nimbleCommand == nimDir / "nimble"
    check resolved.nimsuggestCommand == nimsuggestPath
    check resolved.source == "global settings"
