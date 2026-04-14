import std/strutils

## Key modifier constants, KeyCombo type, and combo helper.
## Command-to-key bindings live in src/commands.nim.
const
  ctrlMod*  = cint(0x04000000)  # Qt::ControlModifier
  altMod*   = cint(0x08000000)  # Qt::AltModifier
  shiftMod* = cint(0x02000000)  # Qt::ShiftModifier
  noMod*    = cint(0)

type
  KeybindingScheme* = enum
    Emacs
    VSCode

  KeyCombo* = tuple[key: cint, mods: cint]

proc combo*(key: cint, mods: cint): KeyCombo = (key, mods)

proc keybindingSchemeLabel*(scheme: KeybindingScheme): string =
  case scheme
  of Emacs: "Emacs"
  of VSCode: "VS Code"

proc toStored*(scheme: KeybindingScheme): string =
  case scheme
  of Emacs: "emacs"
  of VSCode: "vscode"

proc parseKeybindingScheme*(value: string): KeybindingScheme =
  case value.strip().toLowerAscii()
  of "vscode", "vs code": VSCode
  else: Emacs
