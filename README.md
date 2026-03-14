# Bench

A productive, keyboard-driven development environment for Nim, built with Qt.

## Features

- **Project management** — Open and manage Nim projects with a built-in file tree
- **Nim integration** — Run and build projects directly from the toolbar using nimble
- **Code intelligence** — Goto definition, find symbol references, and autocomplete via nimsuggest
- **Syntax highlighting** — Nim syntax highlighting with multiple themes (Nord, Solarized Dark/Light, GitHub Light)
- **Workbench** — A notebook-style workspace for planning and drafting commits
- **Keyboard shortcuts** — Quick pane switching, file opening, and more

## Requirements

- [Nim](https://nim-lang.org/) >= 2.2.6
- [Nimble](https://github.com/nim-lang/nimble) >= 0.22.2
- Qt 6.4+ (via [seaqt](https://github.com/seaqt/nim-seaqt))

## Installation

### Flatpak

```bash
flatpak install io.github.dneumann42.Bench
```

### From source

```bash
nimble build
```

Run with:
```bash
./bench
```

## Screenshots

TODO: Add screenshots

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+P` | Quick open file |
| `Ctrl+Shift+P` | Command palette |
| `Ctrl+B` | Build project |
| `Ctrl+Shift+B` | Run project |
| `Ctrl+1-9` | Switch to pane 1-9 |

## License

MIT
