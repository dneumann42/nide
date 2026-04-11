import std/[os, algorithm, strutils]
import seaqt/[qwidget, qdialog, qlineedit, qlistwidget,
              qlistwidgetitem, qshortcut, qkeysequence, qobject,
              qabstractbutton,
              qsplitter, qlabel]
import nide/ui/[filepreview, widgets]
import nide/helpers/qtconst

var gitignorePatterns*: seq[string] = @[]
var gitignoreRoot*: string = ""

proc loadGitignoreDir(dir: string) {.raises: [].}

proc loadGitignore*(root: string) {.raises: [].} =
  gitignoreRoot = root
  gitignorePatterns.setLen(0)
  for sd in [".git", "node_modules", "__pycache__", ".nimble", "bin", "build", "dist", "nimbledeps"]:
    gitignorePatterns.add(sd & "/*")
  try:
    loadGitignoreDir(root)
    for kind, dirPath in walkDir(root):
      if kind == pcDir and not dirPath.contains("/.") and not dirPath.contains("\\."):
        loadGitignoreDir(dirPath)
    for dirPath in walkDirRec(root):
      if dirPath.contains("/.") or dirPath.contains("\\."): continue
      let parent = dirPath.parentDir
      loadGitignoreDir(parent)
  except CatchableError: discard

proc loadGitignoreDir(dir: string) {.raises: [].} =
  let gitignorePath = dir / ".gitignore"
  if not fileExists(gitignorePath): return
  try:
    let content = readFile(gitignorePath)
    var basePrefix = dir.relativePath(gitignoreRoot)
    if basePrefix == ".": basePrefix = ""
    for line in content.splitLines:
      var pattern = line.strip
      if pattern.len == 0 or pattern.startswith("#"): continue
      if pattern.startswith("!"):
        continue
      if pattern.endswith("/"):
        pattern = pattern[0..^2] & "/*"
      if basePrefix.len > 0:
        pattern = basePrefix / pattern
      gitignorePatterns.add(pattern)
  except CatchableError: discard

proc matchesGitignore*(path: string): bool {.raises: [].} =
  if gitignorePatterns.len == 0: return false
  if gitignoreRoot.len == 0: return false
  let relative = path.replace(gitignoreRoot & DirSep, "")
  if relative.len == 0: return false
  for pattern in gitignorePatterns:
    if pattern.len == 0: continue
    if pattern.startswith("*") and pattern.endswith("*"):
      if pattern.len < 3: continue
      let middle = pattern[1..^2]
      if middle in relative: return true
    elif pattern.startswith("*"):
      if pattern.len < 2: continue
      if relative.endsWith(pattern[1..^1]): return true
    elif pattern.endswith("*"):
      if pattern.len < 2: continue
      let prefix = pattern[0..^2]
      if relative.startsWith(prefix): return true
    elif relative.startsWith(pattern & DirSep): return true
    elif pattern == relative: return true
    if '/' in pattern:
      let parts = relative.split(DirSep)
      var partial = ""
      for i, pt in parts:
        if partial.len > 0: partial &= DirSep
        partial &= pt
        if partial == pattern or partial == pattern[0..^2]:
          return true
  return false

const
  FinderWidth = cint 1100
  FinderHeight = cint 550
  BufferFinderWidth = cint 480
  BufferFinderHeight = cint 320

proc toStr*(oa: openArray[char]): string {.raises: [].} =
  result = newString(oa.len)
  if oa.len > 0:
    copyMem(addr result[0], unsafeAddr oa[0], oa.len)

proc fuzzyScore(query, target: string): int {.raises: [].} =
  ## Returns -1 if query is not a subsequence of target, else match count (higher = better).
  if query.len == 0: return 0
  var qi = 0
  for ch in target:
    if qi < query.len and ch == query[qi]: 
      inc qi
  if qi == query.len: qi else: -1

proc findProjectFiles(root: string): seq[(string, bool)] {.raises: [].} =
  loadGitignore(root)
  try:
    for path in walkDirRec(root):
      result.add((path.relativePath(root), matchesGitignore(path)))
  except CatchableError:
    discard

proc showFileFinder*(parent: QWidget,
                     recentFiles: seq[string],
                     onFileSelected: proc(path: string) {.raises: [].}) {.raises: [].} =
  try:
    var dialog = newWidget(QDialog.create(parent))
    let dialogH = dialog.h
    QWidget(h: dialogH, owned: false).setWindowTitle("Open File")
    QWidget(h: dialogH, owned: false).resize(FinderWidth, FinderHeight)

    var searchBox = newWidget(QLineEdit.create())
    searchBox.setPlaceholderText("Search project files...")
    var showIgnoredCheck = checkbox("Show ignored files")

    var listWidget = newWidget(QListWidget.create())
    let listH = listWidget.h

    let leftLayout = vbox()
    leftLayout.add(searchBox)
    leftLayout.add(showIgnoredCheck)
    leftLayout.add(listWidget)

    # Recent files section below the file list
    var recentListH: pointer = nil
    if recentFiles.len > 0:
      var recentLabel = newWidget(QLabel.create("Recent"))
      var recentList = newWidget(QListWidget.create())
      recentListH = recentList.h
      let root = try: getCurrentDir() except OSError: "."
      for f in recentFiles:
        recentList.addItem(f.relativePath(root))
      leftLayout.add(recentLabel)
      leftLayout.add(recentList)

      recentList.onItemDoubleClicked do(item: QListWidgetItem) {.raises: [].}:
        try:
          let lw = QListWidget(h: recentListH, owned: false)
          let row = lw.row(item)
          if row >= 0 and row < cint(recentFiles.len):
            let path = recentFiles[row]
            QDialog(h: dialogH, owned: false).accept()
            onFileSelected(path)
        except CatchableError: discard

    var leftPanel = newWidget(QWidget.create())
    leftLayout.applyTo(leftPanel)

    let preview = newFilePreviewWidget(leftPanel, showFilter = true)

    var splitter = newWidget(QSplitter.create(Horizontal))
    splitter.addWidget(leftPanel)
    splitter.addWidget(preview.container)
    splitter.setStretchFactor(cint 0, cint 1)
    splitter.setStretchFactor(cint 1, cint 2)

    let outerLayout = vbox()
    outerLayout.add(splitter)
    outerLayout.applyTo(QWidget(h: dialogH, owned: false))

    let root = try: getCurrentDir() except OSError: "."
    let allFiles = findProjectFiles(root)

    proc populate(query: string) {.raises: [].} =
      try:
        let lw = QListWidget(h: listH, owned: false)
        lw.clear()
        let showIgnored = showIgnoredCheck.asButton.isChecked()
        var matches: seq[(int, string)]
        for (f, ignored) in allFiles:
          if ignored and not showIgnored: continue
          let score = fuzzyScore(query, f)
          if score >= 0:
            matches.add((score, f))
        matches.sort(proc(a, b: (int, string)): int {.raises: [].} = cmp(b[0], a[0]))
        for (_, path) in matches:
          lw.addItem(path)
        if lw.count() > 0:
          lw.setCurrentRow(cint 0)
      except CatchableError: discard

    populate("")

    listWidget.onCurrentRowChanged do(row: cint) {.raises: [].}:
      if row >= 0:
        try:
          let path = root / QListWidget(h: listH, owned: false).item(row).text()
          discard setPreviewForFile(preview, path)
        except CatchableError:
          showPreviewPlaceholder(preview, PreviewReadErrorPlaceholder)

    searchBox.onTextChanged do(text: openArray[char]) {.raises: [].}:
      populate(toStr(text))

    showIgnoredCheck.clickable do(checked: bool):
      discard checked
      populate(searchBox.text())

    # Ctrl+N = next item
    var nextSc = newWidget(QShortcut.create(QKeySequence.create("Ctrl+N"),
                                            QObject(h: dialogH, owned: false)))
    nextSc.setContext(SC_WindowShortcut)   # WindowShortcut
    nextSc.onActivated do() {.raises: [].}:
      let lw = QListWidget(h: listH, owned: false)
      let next = min(lw.currentRow() + cint 1, lw.count() - cint 1)
      lw.setCurrentRow(next)

    # Ctrl+P = previous item
    var prevSc = newWidget(QShortcut.create(QKeySequence.create("Ctrl+P"),
                                            QObject(h: dialogH, owned: false)))
    prevSc.setContext(SC_WindowShortcut)   # WindowShortcut
    prevSc.onActivated do() {.raises: [].}:
      let lw = QListWidget(h: listH, owned: false)
      let prev = max(lw.currentRow() - cint 1, cint 0)
      lw.setCurrentRow(prev)

    # Enter = open current selection
    var enterSc = newWidget(QShortcut.create(QKeySequence.create("Return"),
                                             QObject(h: dialogH, owned: false)))
    enterSc.setContext(SC_WindowShortcut)
    enterSc.onActivated do() {.raises: [].}:
      let lw = QListWidget(h: listH, owned: false)
      let row = lw.currentRow()
      if row >= 0:
        let path = root / lw.item(row).text()
        QDialog(h: dialogH, owned: false).accept()
        onFileSelected(path)

    # Double-click = open
    listWidget.onItemDoubleClicked do(item: QListWidgetItem) {.raises: [].}:
      let path = root / item.text()
      QDialog(h: dialogH, owned: false).accept()
      onFileSelected(path)

    discard QDialog(h: dialogH, owned: false).exec()
  except CatchableError: discard

proc showBufferFinder*(parent: QWidget,
                       entries: seq[(string, string)],
                       onSelected: proc(key: string) {.raises: [].}) {.raises: [].} =
  try:
    var dialog = newWidget(QDialog.create(parent))
    let dialogH = dialog.h
    QWidget(h: dialogH, owned: false).setWindowTitle("Switch Buffer")
    QWidget(h: dialogH, owned: false).resize(BufferFinderWidth, BufferFinderHeight)

    var searchBox = newWidget(QLineEdit.create())
    searchBox.setPlaceholderText("Search open buffers...")

    var listWidget = newWidget(QListWidget.create())
    let listH = listWidget.h

    let layout = vbox()
    layout.add(searchBox)
    layout.add(listWidget)
    layout.applyTo(QWidget(h: dialogH, owned: false))

    var filteredKeys: seq[string]

    proc populate(query: string) {.raises: [].} =
      try:
        let lw = QListWidget(h: listH, owned: false)
        lw.clear()
        var matches: seq[(int, string, string)]
        for (display, key) in entries:
          let score = fuzzyScore(query, display)
          if score >= 0:
            matches.add((score, display, key))
        matches.sort(proc(a, b: (int, string, string)): int {.raises: [].} = cmp(b[0], a[0]))
        filteredKeys.setLen(0)
        for (_, display, key) in matches:
          lw.addItem(display)
          filteredKeys.add(key)
        if lw.count() > 0:
          lw.setCurrentRow(cint 0)
      except CatchableError: discard

    populate("")

    searchBox.onTextChanged do(text: openArray[char]) {.raises: [].}:
      populate(toStr(text))

    # Ctrl+N = next item
    var nextSc = newWidget(QShortcut.create(QKeySequence.create("Ctrl+N"),
                                            QObject(h: dialogH, owned: false)))
    nextSc.setContext(SC_WindowShortcut)
    nextSc.onActivated do() {.raises: [].}:
      let lw = QListWidget(h: listH, owned: false)
      let next = min(lw.currentRow() + cint 1, lw.count() - cint 1)
      lw.setCurrentRow(next)

    # Ctrl+B = previous item
    var prevSc = newWidget(QShortcut.create(QKeySequence.create("Ctrl+B"),
                                            QObject(h: dialogH, owned: false)))
    prevSc.setContext(SC_WindowShortcut)
    prevSc.onActivated do() {.raises: [].}:
      let lw = QListWidget(h: listH, owned: false)
      let prev = max(lw.currentRow() - cint 1, cint 0)
      lw.setCurrentRow(prev)

    # Enter = open current selection
    var enterSc = newWidget(QShortcut.create(QKeySequence.create("Return"),
                                             QObject(h: dialogH, owned: false)))
    enterSc.setContext(SC_WindowShortcut)
    enterSc.onActivated do() {.raises: [].}:
      let lw = QListWidget(h: listH, owned: false)
      let row = lw.currentRow()
      if row >= 0 and row < cint(filteredKeys.len):
        let key = filteredKeys[row]
        QDialog(h: dialogH, owned: false).accept()
        onSelected(key)

    # Double-click = open
    listWidget.onItemDoubleClicked do(item: QListWidgetItem) {.raises: [].}:
      try:
        let lw = QListWidget(h: listH, owned: false)
        let row = lw.row(item)
        if row >= 0 and row < cint(filteredKeys.len):
          let key = filteredKeys[row]
          QDialog(h: dialogH, owned: false).accept()
          onSelected(key)
      except CatchableError: discard

    discard QDialog(h: dialogH, owned: false).exec()
  except CatchableError: discard
