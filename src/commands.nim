import std/tables
import bench/keybindings

export KeyCombo, combo, ctrlMod, altMod, shiftMod, noMod

type
  CommandId* = string
  Command*   = proc() {.raises: [].}

  CommandDispatcher* = ref object
    commands: Table[CommandId, Command]
    single:   Table[KeyCombo, CommandId]
    chordCx:  Table[KeyCombo, CommandId]
    inChord*: bool

proc register*(d: CommandDispatcher, id: CommandId, cmd: Command) =
  d.commands[id] = cmd

proc bindKey*(d: CommandDispatcher, c: KeyCombo, id: CommandId) =
  d.single[c] = id

proc bindChordKey*(d: CommandDispatcher, c: KeyCombo, id: CommandId) =
  d.chordCx[c] = id

proc dispatch*(d: CommandDispatcher, c: KeyCombo): bool =
  if d.inChord:
    d.inChord = false
    let id = d.chordCx.getOrDefault(c, "")
    if id.len == 0: return false
    let cmd = d.commands.getOrDefault(id, nil)
    if cmd != nil: cmd()
    return true
  let id = d.single.getOrDefault(c, "")
  if id.len == 0: return false
  let cmd = d.commands.getOrDefault(id, nil)
  if cmd != nil: cmd()
  return true

proc registerDefaultBindings*(d: CommandDispatcher) =
  ## Bind the default Emacs-style key combos to command IDs.
  ## Single-key bindings
  d.bindKey(combo(0x46, ctrlMod), "editor.forwardChar")
  d.bindKey(combo(0x42, ctrlMod), "editor.backwardChar")
  d.bindKey(combo(0x4E, ctrlMod), "editor.nextLine")
  d.bindKey(combo(0x50, ctrlMod), "editor.prevLine")
  d.bindKey(combo(0x41, ctrlMod), "editor.beginningOfLine")
  d.bindKey(combo(0x45, ctrlMod), "editor.endOfLine")
  d.bindKey(combo(0x46, altMod),  "editor.forwardWord")
  d.bindKey(combo(0x42, altMod),  "editor.backwardWord")
  d.bindKey(combo(0x3C, altMod or shiftMod), "editor.beginningOfBuffer")
  d.bindKey(combo(0x3E, altMod or shiftMod), "editor.endOfBuffer")
  d.bindKey(combo(0x56, ctrlMod), "editor.scrollDown")
  d.bindKey(combo(0x56, altMod),  "editor.scrollUp")
  d.bindKey(combo(0x44, ctrlMod), "editor.deleteForwardChar")
  d.bindKey(combo(0x4B, ctrlMod), "editor.killLine")
  d.bindKey(combo(0x44, altMod),  "editor.killWordForward")
  d.bindKey(combo(0x01000003, altMod), "editor.killWordBackward")
  d.bindKey(combo(0x57, ctrlMod), "editor.killRegion")
  d.bindKey(combo(0x59, ctrlMod), "editor.yank")
  d.bindKey(combo(0x58, ctrlMod), "editor.chordCx")
  ## C-x chord bindings
  d.bindChordKey(combo(0x31, noMod),   "editor.deleteOtherWindows")
  d.bindChordKey(combo(0x32, noMod),   "editor.splitHorizontal")
  d.bindChordKey(combo(0x33, noMod),   "editor.splitVertical")
  d.bindChordKey(combo(0x4B, noMod),   "editor.killBuffer")
  d.bindChordKey(combo(0x42, noMod),   "editor.switchBuffer")
  d.bindChordKey(combo(0x53, ctrlMod), "editor.saveBuffer")
  d.bindChordKey(combo(0x46, ctrlMod), "editor.findFile")
