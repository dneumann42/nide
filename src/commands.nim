import std/tables
import std/strutils
import std/algorithm
import nide/settings/keybindings

export KeybindingScheme, KeyCombo, combo, ctrlMod, altMod, shiftMod, noMod

type
  CommandId* = string
  Command*   = proc() {.raises: [].}

  CommandDescriptor* = object
    id*: CommandId
    label*: string
    aliases*: seq[string]
    visible*: bool

  BindingEntry* = tuple[id: CommandId, combo: KeyCombo, isChord: bool, chordPrefix: string]

  CommandDispatcher* = ref object
    commands: Table[CommandId, Command]
    metadata: Table[CommandId, CommandDescriptor]
    single:   Table[KeyCombo, CommandId]
    chordCx:  Table[KeyCombo, CommandId]
    inChord*: bool

proc removeBindingsForCommand(d: CommandDispatcher, id: CommandId) {.raises: [].} =
  var singleToRemove: seq[KeyCombo]
  for key, value in d.single:
    if value == id:
      singleToRemove.add(key)
  for key in singleToRemove:
    d.single.del(key)

  var chordToRemove: seq[KeyCombo]
  for key, value in d.chordCx:
    if value == id:
      chordToRemove.add(key)
  for key in chordToRemove:
    d.chordCx.del(key)

proc register*(d: CommandDispatcher, id: CommandId, cmd: Command) =
  d.commands[id] = cmd
  if not d.metadata.hasKey(id):
    d.metadata[id] = CommandDescriptor(id: id, label: id, visible: true)

proc register*(d: CommandDispatcher, desc: CommandDescriptor, cmd: Command) =
  d.commands[desc.id] = cmd
  d.metadata[desc.id] = desc

proc register*(d: CommandDispatcher, id: CommandId, label: string, cmd: Command,
               aliases: seq[string] = @[], visible = true) =
  d.register(CommandDescriptor(id: id, label: label, aliases: aliases, visible: visible), cmd)

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

proc execute*(d: CommandDispatcher, id: CommandId): bool =
  let cmd = d.commands.getOrDefault(id, nil)
  if cmd == nil:
    return false
  cmd()
  true

proc registerEmacsBindings(d: CommandDispatcher) {.raises: [].} =
  ## Bind the default Emacs-style key combos to command IDs.
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
  d.bindKey(combo(0x57, altMod),  "editor.copySelection")
  d.bindKey(combo(0x47, ctrlMod), "editor.closeSearch")    ## Ctrl+G
  d.bindKey(combo(0x59, ctrlMod), "editor.yank")
  d.bindKey(combo(0x58, ctrlMod), "editor.chordCx")
  d.bindKey(combo(0x4F, ctrlMod), "editor.openLine")
  d.bindKey(combo(0x4C, ctrlMod), "editor.recenter")
  d.bindKey(combo(0x4B, altMod),  "editor.scrollUp")    ## Alt+K — additional scroll binding
  d.bindKey(combo(0x4A, altMod),  "editor.scrollDown")  ## Alt+J — additional scroll binding
  d.bindKey(combo(0x53, ctrlMod),             "editor.findInBuffer")   ## Ctrl+S
  d.bindKey(combo(0x46, ctrlMod or shiftMod), "editor.ripgrepFind")    ## Ctrl+Shift+F
  d.bindKey(combo(0x5C, ctrlMod),             "editor.addColumn")      ## Ctrl+\
  d.bindKey(combo(0x30, altMod),             "editor.toggleFileTree") ## Alt+0
  d.bindKey(combo(0x45, ctrlMod or shiftMod), "editor.toggleFileTree") ## Ctrl+Shift+E
  d.bindKey(combo(0x5C, ctrlMod or shiftMod), "editor.splitRow")       ## Ctrl+Shift+\
  d.bindKey(combo(0x2E, ctrlMod),             "editor.gotoDefinition") ## Ctrl+.
  d.bindKey(combo(0x2C, ctrlMod),             "editor.jumpBack")       ## Ctrl+,
  d.bindKey(combo(0x50, ctrlMod or shiftMod), "editor.commandPalette") ## Ctrl+Shift+P
  d.bindKey(combo(0x01000032, noMod),         "editor.gotoDefinition") ## F3
  d.bindKey(combo(0x20, ctrlMod),             "editor.setMark")        ## Ctrl+Space
  d.bindKey(combo(0x3B, ctrlMod),             "editor.autocomplete")   ## Ctrl+;
  d.bindKey(combo(0x01000032, ctrlMod),       "editor.showPrototype")  ## Ctrl+F3
  d.bindKey(combo(0x3D, ctrlMod),             "editor.zoomIn")         ## Ctrl+=
  d.bindKey(combo(0x2D, ctrlMod),             "editor.zoomOut")        ## Ctrl+-
  d.bindKey(combo(0x01000000, noMod),         "editor.closeSearch")    ## Escape
  ## C-x chord bindings
  d.bindChordKey(combo(0x31, noMod),   "editor.deleteOtherWindows")
  d.bindChordKey(combo(0x30, noMod),   "editor.deleteWindow")
  d.bindChordKey(combo(0x32, noMod),   "editor.splitHorizontal")
  d.bindChordKey(combo(0x33, noMod),   "editor.splitVertical")
  d.bindChordKey(combo(0x4B, noMod),   "editor.killBuffer")
  d.bindChordKey(combo(0x42, noMod),   "editor.switchBuffer")
  d.bindChordKey(combo(0x4F, noMod),   "editor.otherWindow")
  d.bindChordKey(combo(0x20, noMod),   "editor.rectangleMark")
  d.bindChordKey(combo(0x53, ctrlMod), "editor.saveBuffer")
  d.bindChordKey(combo(0x43, ctrlMod), "editor.quitApplication")
  d.bindChordKey(combo(0x46, ctrlMod), "editor.findFile")

proc registerVSCodeBindings(d: CommandDispatcher) {.raises: [].} =
  registerEmacsBindings(d)

  d.removeBindingsForCommand("editor.commandPalette")
  d.bindKey(combo(0x50, ctrlMod or shiftMod), "editor.commandPalette") ## Ctrl+Shift+P

  d.removeBindingsForCommand("editor.findInBuffer")
  d.bindKey(combo(0x46, ctrlMod), "editor.findInBuffer") ## Ctrl+F

  d.removeBindingsForCommand("editor.ripgrepFind")
  d.bindKey(combo(0x46, ctrlMod or shiftMod), "editor.ripgrepFind") ## Ctrl+Shift+F

  d.removeBindingsForCommand("editor.saveBuffer")
  d.bindKey(combo(0x53, ctrlMod), "editor.saveBuffer") ## Ctrl+S

  d.removeBindingsForCommand("editor.findFile")
  d.bindKey(combo(0x50, ctrlMod), "editor.findFile") ## Ctrl+P

  d.removeBindingsForCommand("editor.switchBuffer")
  d.bindKey(combo(0x01000001, ctrlMod), "editor.switchBuffer") ## Ctrl+Tab

  d.removeBindingsForCommand("editor.toggleFileTree")
  d.bindKey(combo(0x45, ctrlMod or shiftMod), "editor.toggleFileTree") ## Ctrl+Shift+E

  d.removeBindingsForCommand("editor.gotoDefinition")
  d.bindKey(combo(0x0100003B, noMod), "editor.gotoDefinition") ## F12

  d.removeBindingsForCommand("editor.showPrototype")
  d.bindKey(combo(0x0100003B, ctrlMod), "editor.showPrototype") ## Ctrl+F12

  d.removeBindingsForCommand("editor.jumpBack")
  d.bindKey(combo(0x01000012, altMod), "editor.jumpBack") ## Alt+Left

proc registerBindings*(d: CommandDispatcher, scheme: KeybindingScheme) {.raises: [].} =
  case scheme
  of Emacs:
    registerEmacsBindings(d)
  of VSCode:
    registerVSCodeBindings(d)

proc registerDefaultBindings*(d: CommandDispatcher) {.raises: [].} =
  registerBindings(d, Emacs)

proc keyComboToString*(c: KeyCombo): string {.raises: [].} =
  ## Convert a KeyCombo to a portable string like "Ctrl+F".
  var parts: seq[string]
  if (c.mods and ctrlMod) != 0:  parts.add("Ctrl")
  if (c.mods and altMod) != 0:   parts.add("Alt")
  if (c.mods and shiftMod) != 0: parts.add("Shift")
  let keyName = case c.key
    of 0x01000000: "Escape"
    of 0x01000001: "Tab"
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

proc stringToKeyCombo*(s: string): KeyCombo {.raises: [].} =
  ## Parse a portable key string like "Ctrl+F" or "Ctrl+X 1" (chord) into a KeyCombo.
  if s.len == 0: return combo(0, noMod)
  
  let parts = s.split(' ')
  if parts.len == 2:
    let prefixCombo = stringToKeyCombo(parts[0])
    let keyCombo = stringToKeyCombo(parts[1])
    return keyCombo
  elif parts.len > 2:
    var prefixStr = ""
    var keyStr = ""
    for i, p in parts:
      if i < parts.len - 1:
        if prefixStr.len > 0: prefixStr &= "+"
        prefixStr &= p
      else:
        keyStr = p
    let prefixCombo = stringToKeyCombo(prefixStr)
    let keyCombo = stringToKeyCombo(keyStr)
    return keyCombo
  
  let plainParts = s.split('+')
  var mods: cint = noMod
  var key: cint = 0
  for part in plainParts:
    case part
    of "Ctrl":      mods = mods or ctrlMod
    of "Alt":       mods = mods or altMod
    of "Shift":     mods = mods or shiftMod
    of "Escape":    key = 0x01000000
    of "Tab":       key = 0x01000001
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

proc resetBindings*(d: CommandDispatcher) {.raises: [].} =
  ## Clear all key bindings so they can be re-registered from scratch.
  d.single.clear()
  d.chordCx.clear()

proc findChordPrefix*(d: CommandDispatcher, chordKey: KeyCombo): string {.raises: [].}

proc applyCustomBindings*(d: CommandDispatcher, custom: Table[string, string]) {.raises: [].} =
  ## Override default bindings with user-specified key strings.
  ## Removes existing bindings for each command before adding the new one.
  let chordPrefixBinding = custom.getOrDefault("editor.chordCx", "")
  if chordPrefixBinding.len > 0:
    let newCombo = stringToKeyCombo(chordPrefixBinding)
    if newCombo.key != 0:
      d.removeBindingsForCommand("editor.chordCx")
      d.single[newCombo] = "editor.chordCx"

  let chordPrefix = findChordPrefix(d, combo(0, noMod)).toLowerAscii()

  for cmdId, keyStr in custom:
    if cmdId == "editor.chordCx":
      continue

    let normalized = keyStr.replace(", ", " ").strip()
    let parts = normalized.splitWhitespace()
    if parts.len == 0:
      continue

    if parts.len == 2:
      if parts[0].toLowerAscii() != chordPrefix:
        continue
      let newCombo = stringToKeyCombo(parts[1])
      if newCombo.key == 0:
        continue
      d.removeBindingsForCommand(cmdId)
      d.chordCx[newCombo] = cmdId
      continue

    let newCombo = stringToKeyCombo(normalized)
    if newCombo.key == 0:
      continue
    d.removeBindingsForCommand(cmdId)
    d.single[newCombo] = cmdId

proc findChordPrefix*(d: CommandDispatcher, chordKey: KeyCombo): string {.raises: [].} =
  ## Find the prefix key that triggers this chord (e.g., "Ctrl+X" for C-x 1).
  for key, cmdId in d.single:
    if cmdId == "editor.chordCx":
      return keyComboToString(key)
  return "Ctrl+X"

proc bindingListForScheme(scheme: KeybindingScheme): seq[BindingEntry] {.raises: [].} =
  let d = CommandDispatcher()
  registerBindings(d, scheme)
  for k, v in d.single:
    result.add((id: v, combo: k, isChord: false, chordPrefix: ""))
  for k, v in d.chordCx:
    let prefix = findChordPrefix(d, k)
    result.add((id: v, combo: k, isChord: true, chordPrefix: prefix))

proc defaultBindingList*(scheme: KeybindingScheme = Emacs): seq[BindingEntry] {.raises: [].} =
  ## Returns the selected scheme's keybindings plus blank entries for commands
  ## that are only bound in the other scheme so they remain editable.
  result = bindingListForScheme(scheme)

  var seen: Table[CommandId, bool]
  for entry in result:
    seen[entry.id] = true

  for fallback in KeybindingScheme:
    if fallback == scheme:
      continue
    for entry in bindingListForScheme(fallback):
      if not seen.hasKey(entry.id):
        seen[entry.id] = true
        result.add((id: entry.id, combo: combo(0, noMod), isChord: false, chordPrefix: ""))

proc listCommands*(d: CommandDispatcher): seq[CommandDescriptor] {.raises: [].} =
  for _, desc in d.metadata:
    result.add(desc)
  result.sort(proc(a, b: CommandDescriptor): int {.raises: [].} =
    cmp(a.label.toLowerAscii(), b.label.toLowerAscii()))

proc bindingStrings*(d: CommandDispatcher, id: CommandId): seq[string] {.raises: [].} =
  for key, value in d.single:
    if value == id:
      let s = keyComboToString(key)
      if s.len > 0:
        result.add(s)
  let prefix = findChordPrefix(d, combo(0, noMod))
  for key, value in d.chordCx:
    if value == id:
      let suffix = keyComboToString(key)
      if suffix.len > 0:
        result.add(prefix & " " & suffix)
  result.sort(proc(a, b: string): int {.raises: [].} = cmp(a, b))
