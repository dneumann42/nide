import std/[tables, unittest]
import commands

suite "default keybindings":
  test "ctrl shift p opens command palette":
    let d = CommandDispatcher()
    registerDefaultBindings(d)
    check d.lookupCommand(combo(0x50, ctrlMod or shiftMod)) == "editor.commandPalette"

  test "ctrl space sets mark":
    let d = CommandDispatcher()
    registerDefaultBindings(d)
    check d.lookupCommand(combo(0x20, ctrlMod)) == "editor.setMark"

  test "ctrl semicolon opens autocomplete":
    let d = CommandDispatcher()
    registerDefaultBindings(d)
    check d.lookupCommand(combo(0x3B, ctrlMod)) == "editor.autocomplete"

  test "ctrl g triggers cancel command":
    let d = CommandDispatcher()
    registerDefaultBindings(d)
    check d.lookupCommand(combo(0x47, ctrlMod)) == "editor.closeSearch"

  test "alt zero toggles file tree":
    let d = CommandDispatcher()
    registerDefaultBindings(d)
    check d.lookupCommand(combo(0x30, altMod)) == "editor.toggleFileTree"

  test "ctrl period triggers goto definition":
    let d = CommandDispatcher()
    registerDefaultBindings(d)
    check d.lookupCommand(combo(0x2E, ctrlMod)) == "editor.gotoDefinition"

  test "ctrl comma triggers jump back":
    let d = CommandDispatcher()
    registerDefaultBindings(d)
    check d.lookupCommand(combo(0x2C, ctrlMod)) == "editor.jumpBack"

  test "ctrl x space starts rectangle mark":
    let d = CommandDispatcher()
    var fired = false
    registerDefaultBindings(d)
    d.register("editor.rectangleMark", proc() {.raises: [].} = fired = true)
    d.inChord = true
    check d.dispatch(combo(0x20, noMod))
    check fired

  test "ctrl x zero triggers delete window":
    let d = CommandDispatcher()
    var fired = false
    registerDefaultBindings(d)
    d.register("editor.deleteWindow", proc() {.raises: [].} = fired = true)
    d.inChord = true
    check d.dispatch(combo(0x30, noMod))
    check fired

  test "ctrl x o triggers other window":
    let d = CommandDispatcher()
    var fired = false
    registerDefaultBindings(d)
    d.register("editor.otherWindow", proc() {.raises: [].} = fired = true)
    d.inChord = true
    check d.dispatch(combo(0x4F, noMod))
    check fired

  test "ctrl comma dispatches jump back command":
    let d = CommandDispatcher()
    var fired = false
    registerDefaultBindings(d)
    d.register("editor.jumpBack", proc() {.raises: [].} = fired = true)
    check d.dispatch(combo(0x2C, ctrlMod))
    check fired

suite "command metadata":
  test "registered commands expose metadata":
    let d = CommandDispatcher()
    d.register("editor.commandPalette", "Command Palette",
      proc() {.raises: [].} = discard,
      aliases = @["palette", "commands"])
    let commands = d.listCommands()
    check commands.len == 1
    check commands[0].id == "editor.commandPalette"
    check commands[0].label == "Command Palette"
    check commands[0].aliases == @["palette", "commands"]

  test "binding strings include single keys and chords":
    let d = CommandDispatcher()
    registerDefaultBindings(d)
    check "Ctrl+Shift+P" in d.bindingStrings("editor.commandPalette")
    check "Ctrl+X Ctrl+F" in d.bindingStrings("editor.findFile")
    check "Ctrl+X 0" in d.bindingStrings("editor.deleteWindow")
    check "Ctrl+X O" in d.bindingStrings("editor.otherWindow")

suite "keybinding schemes":
  test "vscode scheme remaps common editor commands":
    let d = CommandDispatcher()
    registerBindings(d, VSCode)
    check d.lookupCommand(combo(0x46, ctrlMod)) == "editor.findInBuffer"
    check d.lookupCommand(combo(0x53, ctrlMod)) == "editor.saveBuffer"
    check d.lookupCommand(combo(0x50, ctrlMod)) == "editor.findFile"
    check d.lookupCommand(combo(0x01000001, ctrlMod)) == "editor.switchBuffer"
    check d.lookupCommand(combo(0x0100003B, noMod)) == "editor.gotoDefinition"
    check d.lookupCommand(combo(0x01000012, altMod)) == "editor.jumpBack"

  test "custom overrides survive scheme changes":
    let d = CommandDispatcher()
    registerBindings(d, VSCode)
    d.applyCustomBindings({"editor.findFile": "Alt+P"}.toTable)
    check d.lookupCommand(combo(0x50, altMod)) == "editor.findFile"
    check d.lookupCommand(combo(0x50, ctrlMod)) == ""
