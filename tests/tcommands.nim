import std/unittest
import commands

suite "default keybindings":
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

  test "ctrl x space starts rectangle mark":
    let d = CommandDispatcher()
    var fired = false
    registerDefaultBindings(d)
    d.register("editor.rectangleMark", proc() {.raises: [].} = fired = true)
    d.inChord = true
    check d.dispatch(combo(0x20, noMod))
    check fired
