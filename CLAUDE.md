# bench — Claude instructions

## Style
- Prefer `do` syntax for seaqt callbacks over inline `proc() {.raises: [].} =`
  ```nim
  widget.onSomeSignal do() {.raises: [].}:
    doSomething()
  ```

## seaqt bindings
- When Qt classes aren't available in seaqt, check if you need to import the module (e.g., `import seaqt/qscrollbar`)
- seaqt uses code generation, so if a binding should exist, import the module first
