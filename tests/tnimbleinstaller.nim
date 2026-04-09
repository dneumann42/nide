import std/unittest

import nide/settings/nimbleinstaller

suite "nimbleinstaller":
  test "empty configured path falls back to default nimble bin":
    check resolveNimbleInstallDir("") == defaultNimbleInstallDir()

  test "configured path is preserved":
    check resolveNimbleInstallDir("/tmp/custom-nimble-bin") == "/tmp/custom-nimble-bin"

  test "latest release parser selects current platform asset":
    let suffix = currentNimbleAssetSuffix()
    let release = parseLatestNimbleRelease(
      """{
        "tag_name": "v9.9.9",
        "assets": [
          {
            "name": "nimble-v9.9.9-other-platform.tar.gz",
            "browser_download_url": "https://example.invalid/other"
          },
          {
            "name": "nimble-v9.9.9-""" & suffix & """",
            "browser_download_url": "https://example.invalid/current"
          }
        ]
      }"""
    )
    check release.tag == "v9.9.9"
    check release.downloadUrl == "https://example.invalid/current"

  test "latest release parser leaves url empty when asset is missing":
    let release = parseLatestNimbleRelease(
      """{
        "tag_name": "v9.9.9",
        "assets": [
          {
            "name": "nimble-v9.9.9-no-match.tar.gz",
            "browser_download_url": "https://example.invalid/other"
          }
        ]
      }"""
    )
    check release.tag == "v9.9.9"
    check release.downloadUrl.len == 0
