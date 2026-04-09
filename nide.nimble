# Package

version       = "0.0.0"
author        = "dneumann42"
description   = "A new awesome nimble package"
license       = "MIT"
srcDir        = "src"
bin           = @["nide"]
backend       = "cpp"

# Dependencies

requires "nim >= 2.2.8"
requires "seaqt == 0.6.4.0"

requires "db_connector >= 0.1.0"
requires "toml_serialization >= 0.2.18"

# Download the correct ripgrep binary for this platform and place it next to
# the built nide binary (project root). Run once after cloning or when updating.
#   nimble fetchrg
task fetchrg, "Download ripgrep binary for bundling":
  const rgVersion = "14.1.1"
  when defined(windows):
    const rgUrl = "https://github.com/BurntSushi/ripgrep/releases/download/" &
                  rgVersion & "/ripgrep-" & rgVersion & "-x86_64-pc-windows-msvc.zip"
    exec "curl -fsSL -o rg-dl.zip " & rgUrl
    exec "powershell -NoProfile -Command " &
         "\"Expand-Archive -Force rg-dl.zip rg-dl; " &
         "Copy-Item (Get-ChildItem -Recurse rg-dl -Filter rg.exe | " &
         "Select-Object -First 1).FullName rg.exe; " &
         "Remove-Item -Recurse -Force rg-dl, rg-dl.zip\""
  else:
    const rgUrl = "https://github.com/BurntSushi/ripgrep/releases/download/" &
                  rgVersion & "/ripgrep-" & rgVersion & "-x86_64-unknown-linux-musl.tar.gz"
    exec "curl -fsSL -o /tmp/rg.tgz " & rgUrl
    exec "tar -xzf /tmp/rg.tgz --strip-components=1 " &
         "ripgrep-" & rgVersion & "-x86_64-unknown-linux-musl/rg"
    exec "chmod +x rg"
