# bench — Claude instructions

## Style
- Prefer `do` syntax for seaqt callbacks over inline `proc() {.raises: [].} =`
  ```nim
  widget.onSomeSignal do() {.raises: [].}:
    doSomething()
  ```
