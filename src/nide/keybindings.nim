## Key modifier constants, KeyCombo type, and combo helper.
## Command-to-key bindings live in src/commands.nim (registerDefaultBindings).
const
  ctrlMod*  = cint(0x04000000)  # Qt::ControlModifier
  altMod*   = cint(0x08000000)  # Qt::AltModifier
  shiftMod* = cint(0x02000000)  # Qt::ShiftModifier
  noMod*    = cint(0)

type
  KeyCombo* = tuple[key: cint, mods: cint]

proc combo*(key: cint, mods: cint): KeyCombo = (key, mods)
