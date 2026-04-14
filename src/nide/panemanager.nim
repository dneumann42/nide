import seaqt/[qwidget, qsplitter, qobject]
import nide/pane/pane, nide/helpers/widgetref, nide/nim/nimsuggest
import commands
import std/algorithm
import nide/helpers/qtconst
import nide/settings/theme
import nide/ui/widgets

const SplitterHandleWidth = cint 4

type
  PaneCallbacks* = object
    onFileSelected*: proc(pane: Pane, path: string) {.raises: [].}
    onNewModule*: proc(pane: Pane) {.raises: [].}
    onOpenModule*: proc(pane: Pane) {.raises: [].}
    onNewProject*: proc(pane: Pane) {.raises: [].}
    onOpenProject*: proc(pane: Pane) {.raises: [].}
    onOpenRecentProject*: proc(pane: Pane, path: string) {.raises: [].}
    onGotoDefinition*: proc(pane: Pane, path: string, line: int, col: int) {.raises: [].}
    onJumpBack*: proc(pane: Pane, path: string, line: int, col: int) {.raises: [].}
    onJumpForward*: proc(pane: Pane, path: string, line: int, col: int) {.raises: [].}
    onFindFile*: proc(pane: Pane) {.raises: [].}
    onSwitchBuffer*: proc(pane: Pane) {.raises: [].}
    onRestoreLastSession*: proc(pane: Pane) {.raises: [].}
    onPaneStateChanged*: proc(pane: Pane) {.raises: [].}
    onLayoutChanged*: proc() {.raises: [].}
    resolveNimCommand*: proc(): string {.raises: [].}
    resolveNimBackend*: proc(): string {.raises: [].}

  PaneManager* = ref object
    panels*: seq[Pane]
    splitter: WidgetRef[QSplitter]
    lastFocusedPane*: Pane
    callbacks: PaneCallbacks
    hasProject: bool
    nimSuggest*: NimSuggestClient
    dispatcher*: CommandDispatcher
    editorWheelScrollSpeed*: int

proc closePane*(self: PaneManager, pane: Pane, notify = true) {.raises: [].}
proc closeOtherPanes*(self: PaneManager, keepPane: Pane) {.raises: [].}
proc insertCol*(self: PaneManager, afterPane: Pane, col: WidgetRef[QSplitter]): Pane
proc insertRow*(self: PaneManager, afterPane: Pane, col: WidgetRef[QSplitter]): Pane
proc deleteWindow*(self: PaneManager, pane: Pane): bool {.raises: [].}
proc focusNextPane*(self: PaneManager, pane: Pane): bool {.raises: [].}

proc notifyLayoutChanged(self: PaneManager) =
  if self.callbacks.onLayoutChanged != nil:
    self.callbacks.onLayoutChanged()

proc setEditorWheelScrollSpeed*(self: PaneManager, speed: int) {.raises: [].} =
  self.editorWheelScrollSpeed = speed
  for pane in self.panels:
    pane.setEditorWheelScrollSpeed(speed)

proc makePane(self: PaneManager, col: WidgetRef[QSplitter]): Pane =
  result = newPane(proc(ev: PaneEvent) {.raises: [].} =
    case ev.kind
    of peFileSelected: self.callbacks.onFileSelected(ev.pane, ev.path)
    of peClose:        self.closePane(ev.pane)
    of peVSplit:
      try: discard self.insertCol(ev.pane, col)
      except: discard  # Qt widget creation can raise Exception
    of peHSplit:
      try: discard self.insertRow(ev.pane, col)
      except: discard  # Qt widget creation can raise Exception
    of peNewModule:    self.callbacks.onNewModule(ev.pane)
    of peOpenModule:   self.callbacks.onOpenModule(ev.pane)
    of peNewProject:
      if self.callbacks.onNewProject != nil: self.callbacks.onNewProject(ev.pane)
    of peOpenProject:  self.callbacks.onOpenProject(ev.pane)
    of peOpenRecentProject:
      if self.callbacks.onOpenRecentProject != nil:
        self.callbacks.onOpenRecentProject(ev.pane, ev.projectPath)
    of peGotoDefinition: self.callbacks.onGotoDefinition(ev.pane, ev.defFile, ev.defLine, ev.defCol)
    of peJumpBack: self.callbacks.onJumpBack(ev.pane, ev.backFile, ev.backLine, ev.backCol)
    of peJumpForward: self.callbacks.onJumpForward(ev.pane, ev.fwdFile, ev.fwdLine, ev.fwdCol)
    of peSave: ev.pane.save()
    of peFindFile:
      if self.callbacks.onFindFile != nil: self.callbacks.onFindFile(ev.pane)
    of peSwitchBuffer:
      if self.callbacks.onSwitchBuffer != nil: self.callbacks.onSwitchBuffer(ev.pane)
    of peDeleteOtherWindows: self.closeOtherPanes(ev.pane)
    of peRestoreLastSession:
      if self.callbacks.onRestoreLastSession != nil:
        self.callbacks.onRestoreLastSession(ev.pane)
    of peStateChanged:
      if self.callbacks.onPaneStateChanged != nil:
        self.callbacks.onPaneStateChanged(ev.pane))
  if self.hasProject:
    result.setProjectOpen(true)
  result.nimSuggest = self.nimSuggest
  result.nimCommandProvider = self.callbacks.resolveNimCommand
  result.nimBackendProvider = self.callbacks.resolveNimBackend
  result.dispatcher = self.dispatcher
  result.setEditorWheelScrollSpeed(self.editorWheelScrollSpeed)
  result.setupSmoothScrolling()

proc init*(T: typedesc[PaneManager], splitter: QSplitter, cbs: PaneCallbacks): T =
  T(splitter: capture(splitter), callbacks: cbs, editorWheelScrollSpeed: 10)

proc addColumn*(self: PaneManager): Pane =
  var col = newWidget(QSplitter.create(Vertical))    # vertical
  col.setHandleWidth(SplitterHandleWidth)
  col.asWidget.setAutoFillBackground(true)
  col.asWidget.setStyleSheet("QSplitter::handle { background: #333333; }")
  let colRef = capture(col)
  result = self.makePane(colRef)
  col.addWidget(result.widget())
  self.splitter.get().addWidget(col.asWidget)
  self.panels.add(result)
  result.focus()
  self.notifyLayoutChanged()

proc insertCol*(self: PaneManager, afterPane: Pane, col: WidgetRef[QSplitter]): Pane =
  let colW = col.get().asWidget
  let idx = self.splitter.get().indexOf(colW)
  if idx < 0: return
  let oldSizes = self.splitter.get().sizes()
  let srcW = oldSizes[idx]
  var newCol = newWidget(QSplitter.create(Vertical))   # vertical
  newCol.setHandleWidth(SplitterHandleWidth)
  newCol.asWidget.setAutoFillBackground(true)
  newCol.asWidget.setStyleSheet("QSplitter::handle { background: #333333; }")
  let newColRef = capture(newCol)
  result = self.makePane(newColRef)
  newCol.addWidget(result.widget())
  self.splitter.get().insertWidget(cint(idx + 1), newCol.asWidget)
  var newSizes = newSeq[cint](oldSizes.len + 1)
  for i in 0..<idx:               newSizes[i]     = oldSizes[i]
  newSizes[idx]                   = cint(srcW div 2)
  newSizes[idx + 1]               = cint(srcW - srcW div 2)
  for i in idx+1..<oldSizes.len:  newSizes[i + 1] = oldSizes[i]
  self.splitter.get().setSizes(newSizes)
  self.panels.add(result)
  result.focus()
  self.notifyLayoutChanged()

proc insertRow*(self: PaneManager, afterPane: Pane, col: WidgetRef[QSplitter]): Pane =
  let colSplitter = col.get()
  let idx = colSplitter.indexOf(afterPane.widget())
  if idx < 0: return
  let oldSizes = colSplitter.sizes()
  let srcH = oldSizes[idx]
  result = self.makePane(col)
  colSplitter.insertWidget(cint(idx + 1), result.widget())
  var newSizes = newSeq[cint](oldSizes.len + 1)
  for i in 0..<idx:               newSizes[i]     = oldSizes[i]
  newSizes[idx]                   = cint(srcH div 2)
  newSizes[idx + 1]               = cint(srcH - srcH div 2)
  for i in idx+1..<oldSizes.len:  newSizes[i + 1] = oldSizes[i]
  colSplitter.setSizes(newSizes)
  self.panels.add(result)
  result.focus()
  self.notifyLayoutChanged()

proc equalizeSplits*(self: PaneManager) =
  let n = self.splitter.get().count().int
  var sizes = newSeq[cint](n)
  for i in 0..<n:
    sizes[i] = cint(1)
  self.splitter.get().setSizes(sizes)

proc closePane*(self: PaneManager, pane: Pane, notify = true) {.raises: [].} =
  if self.panels.len <= 1:
    pane.clearBuffer()
  else:
    pane.widget().hide()
    try:
      for i in countdown(self.panels.high, 0):
        if self.panels[i] == pane:
          self.panels.delete(i)
          break
    except CatchableError: discard
  if notify:
    self.notifyLayoutChanged()

proc closeOtherPanes*(self: PaneManager, keepPane: Pane) {.raises: [].} =
  try:
    var toClose: seq[Pane]
    for p in self.panels:
      if p != keepPane: toClose.add(p)
    for p in toClose:
      self.closePane(p, notify = false)
    self.notifyLayoutChanged()
  except CatchableError: discard

proc splitRow*(self: PaneManager, pane: Pane): Pane =
  let parent = pane.widget().parentWidget()
  if parent.h == nil: return
  let col = capture(QSplitter(h: parent.h, owned: false))
  self.insertRow(pane, col)

proc splitCol*(self: PaneManager, pane: Pane): Pane =
  let parent = pane.widget().parentWidget()
  if parent.h == nil: return
  let col = capture(QSplitter(h: parent.h, owned: false))
  self.insertCol(pane, col)

proc visibleColumns*(self: PaneManager): seq[seq[Pane]] =
  var positions: seq[tuple[colIdx, rowIdx: int, pane: Pane]]
  for pane in self.panels:
    let parent = pane.widget().parentWidget()
    if parent.h == nil:
      continue
    let col = QSplitter(h: parent.h, owned: false)
    let colIdx = self.splitter.get().indexOf(col.asWidget).int
    let rowIdx = col.indexOf(pane.widget()).int
    if colIdx >= 0 and rowIdx >= 0:
      positions.add((colIdx, rowIdx, pane))

  positions.sort(proc(a, b: tuple[colIdx, rowIdx: int, pane: Pane]): int =
    if a.colIdx != b.colIdx:
      cmp(a.colIdx, b.colIdx)
    else:
      cmp(a.rowIdx, b.rowIdx))

  for pos in positions:
    while result.len <= pos.colIdx:
      result.add(@[])
    result[pos.colIdx].add(pos.pane)

proc visiblePanes(self: PaneManager): seq[Pane] =
  for col in self.visibleColumns():
    for pane in col:
      result.add(pane)

proc detachWidget(w: QWidget) =
  try:
    w.hide()
    w.setParent(QWidget())
    QObject(h: w.h, owned: false).deleteLater()
  except CatchableError:
    discard

proc deleteWindow*(self: PaneManager, pane: Pane): bool {.raises: [].} =
  let ordered = self.visiblePanes()
  if ordered.len <= 1:
    return false

  var paneIndex = -1
  for i, candidate in ordered:
    if candidate == pane:
      paneIndex = i
      break
  if paneIndex < 0:
    return false

  let focusIndex = focusIndexAfterRemoval(paneIndex, ordered.len)
  let focusTarget =
    if focusIndex >= 0 and focusIndex < ordered.len:
      if ordered[focusIndex] == pane:
        if focusIndex + 1 < ordered.len: ordered[focusIndex + 1] else: nil
      else:
        ordered[focusIndex]
    else:
      nil

  let paneWidget = pane.widget()
  let parent = paneWidget.parentWidget()
  if parent.h == nil:
    return false
  let col = QSplitter(h: parent.h, owned: false)
  let colWidget = col.asWidget
  let root = self.splitter.get()
  let columnWasSinglePane = col.count().int <= 1

  for i in countdown(self.panels.high, 0):
    if self.panels[i] == pane:
      self.panels.delete(i)
      break

  if self.lastFocusedPane == pane:
    self.lastFocusedPane = nil

  detachWidget(paneWidget)
  if columnWasSinglePane:
    detachWidget(colWidget)

  if focusTarget != nil:
    self.lastFocusedPane = focusTarget
    focusTarget.focus()
  elif self.panels.len > 0:
    self.lastFocusedPane = self.panels[0]
    self.panels[0].focus()

  let rootCount = root.count().int
  if rootCount > 0:
    var sizes = newSeq[cint](rootCount)
    for i in 0..<rootCount:
      sizes[i] = cint 1
    root.setSizes(sizes)

  self.notifyLayoutChanged()
  true

proc focusNextPane*(self: PaneManager, pane: Pane): bool {.raises: [].} =
  let ordered = self.visiblePanes()
  if ordered.len <= 1:
    return false

  var paneIndex = -1
  for i, candidate in ordered:
    if candidate == pane:
      paneIndex = i
      break
  let nextIndex = nextWrappedIndex(paneIndex, ordered.len)
  if nextIndex < 0:
    return false

  let target = ordered[nextIndex]
  self.lastFocusedPane = target
  target.focus()
  true

proc setProjectOpen*(self: PaneManager, open: bool) =
  self.hasProject = open
  for panel in self.panels:
    panel.setProjectOpen(open)

proc updateFocus*(self: PaneManager, focusedWidget: QWidget, theme: Theme) =
  for p in self.panels:
    let focused = focusedWidget.h != nil and p.widget().isAncestorOf(focusedWidget)
    p.setHeaderFocus(focused, theme)
    if focused:
      self.lastFocusedPane = p
