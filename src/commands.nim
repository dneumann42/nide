import std/tables
import std/strutils
import nide/keybindings

export KeyCombo, combo, ctrlMod, altMod, shiftMod, noMod

type
  CommandId* = string
  Command*   = proc() {.raises: [].}

  BindingEntry* = tuple[id: CommandId, combo: KeyCombo, isChord: bool]

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

proc lookupCommand*(d: CommandDispatcher, c: KeyCombo): CommandId =
  d.single.getOrDefault(c, "")

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
  d.bindKey(combo(0x4F, ctrlMod), "editor.openLine")
  d.bindKey(combo(0x4C, ctrlMod), "editor.recenter")
  d.bindKey(combo(0x4B, altMod),  "editor.scrollUp")    ## Alt+K — additional scroll binding
  d.bindKey(combo(0x4A, altMod),  "editor.scrollDown")  ## Alt+J — additional scroll binding
  d.bindKey(combo(0x53, ctrlMod),             "editor.findInBuffer")   ## Ctrl+S
  d.bindKey(combo(0x46, ctrlMod or shiftMod), "editor.ripgrepFind")    ## Ctrl+Shift+F
  d.bindKey(combo(0x5C, ctrlMod),             "editor.addColumn")      ## Ctrl+\
  d.bindKey(combo(0x45, ctrlMod or shiftMod), "editor.toggleFileTree") ## Ctrl+Shift+E
  d.bindKey(combo(0x5C, ctrlMod or shiftMod), "editor.splitRow")       ## Ctrl+Shift+\
  d.bindKey(combo(0x01000032, noMod),         "editor.gotoDefinition") ## F3
  d.bindKey(combo(0x20, ctrlMod),             "editor.autocomplete")   ## Ctrl+Space
  d.bindKey(combo(0x01000032, ctrlMod),       "editor.showPrototype")  ## Ctrl+F3
  d.bindKey(combo(0x3D, ctrlMod),             "editor.zoomIn")         ## Ctrl+=
  d.bindKey(combo(0x2D, ctrlMod),             "editor.zoomOut")        ## Ctrl+-
  d.bindKey(combo(0x01000000, noMod),         "editor.closeSearch")    ## Escape
  ## C-x chord bindings
  d.bindChordKey(combo(0x31, noMod),   "editor.deleteOtherWindows")
  d.bindChordKey(combo(0x32, noMod),   "editor.splitHorizontal")
  d.bindChordKey(combo(0x33, noMod),   "editor.splitVertical")
  d.bindChordKey(combo(0x4B, noMod),   "editor.killBuffer")
  d.bindChordKey(combo(0x42, noMod),   "editor.switchBuffer")
  d.bindChordKey(combo(0x53, ctrlMod), "editor.saveBuffer")
  d.bindChordKey(combo(0x46, ctrlMod), "editor.findFile")

proc keyComboToString*(c: KeyCombo): string =
  ## Convert a KeyCombo to a portable string like "Ctrl+F".
  var parts: seq[string]
  if (c.mods and ctrlMod) != 0:  parts.add("Ctrl")
  if (c.mods and altMod) != 0:   parts.add("Alt")
  if (c.mods and shiftMod) != 0: parts.add("Shift")
  let keyName = case c.key
    of 0x01000000: "Escape"
    of 0x01000003: "Backspace"
    of 0x01000004: "Return"
    of 0x01000007: "Delete"
    of 0x01000012: "Left"
    of 0x01000013: "Up"
    of 0x01000014: "Right"
    of 0x01000015: "Down"
    of 0x01000030: "F1"
    of 0x01000031: "F2"
    of 0x01000032: "F3"
    of 0x01000033: "F4"
    of 0x01000034: "F5"
    of 0x01000035: "F6"
    of 0x01000036: "F7"
    of 0x01000037: "F8"
    of 0x01000038: "F9"
    of 0x01000039: "F10"
    of 0x0100003A: "F11"
    of 0x0100003B: "F12"
    else:
      if c.key >= 0x20 and c.key <= 0x7E: $char(c.key)
      else: ""
  if keyName.len > 0:
    parts.add(keyName)
    result = parts.join("+")

proc stringToKeyCombo*(s: string): KeyCombo =
  ## Parse a portable key string like "Ctrl+F" into a KeyCombo.
  if s.len == 0: return combo(0, noMod)
  let parts = s.split('+')
  var mods: cint = noMod
  var key: cint = 0
  for part in parts:
    case part
    of "Ctrl":      mods = mods or ctrlMod
    of "Alt":       mods = mods or altMod
    of "Shift":     mods = mods or shiftMod
    of "Escape":    key = 0x01000000
    of "Backspace": key = 0x01000003
    of "Return":    key = 0x01000004
    of "Delete":    key = 0x01000007
    of "Left":      key = 0x01000012
    of "Up":        key = 0x01000013
    of "Right":     key = 0x01000014
    of "Down":      key = 0x01000015
    of "F1":        key = 0x01000030
    of "F2":        key = 0x01000031
    of "F3":        key = 0x01000032
    of "F4":        key = 0x01000033
    of "F5":        key = 0x01000034
    of "F6":        key = 0x01000035
    of "F7":        key = 0x01000036
    of "F8":        key = 0x01000037
    of "F9":        key = 0x01000038
    of "F10":       key = 0x01000039
    of "F11":       key = 0x0100003A
    of "F12":       key = 0x0100003B
    else:
      if part.len == 1: key = cint(part[0].ord)
  result = combo(key, mods)

proc resetBindings*(d: CommandDispatcher) =
  ## Clear all key bindings so they can be re-registered from scratch.
  d.single.clear()
  d.chordCx.clear()

proc applyCustomBindings*(d: CommandDispatcher, custom: Table[string, string]) =
  ## Override default bindings with user-specified key strings.
  ## Removes any existing single binding for each command before adding the new one.
  for cmdId, keyStr in custom:
    let newCombo = stringToKeyCombo(keyStr)
    if newCombo.key == 0: continue
    var toRemove: seq[KeyCombo]
    for k, v in d.single:
      if v == cmdId: toRemove.add(k)
    for k in toRemove: d.single.del(k)
    d.single[newCombo] = cmdId

proc defaultBindingList*(): seq[BindingEntry] =
  ## Returns all default keybindings as a list for display/editing purposes.
  let d = CommandDispatcher()
  registerDefaultBindings(d)
  for k, v in d.single:
    result.add((id: v, combo: k, isChord: false))
  for k, v in d.chordCx:
    result.add((id: v, combo: k, isChord: true))
