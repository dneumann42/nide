import seaqt/[qwidget, qsplitter]
import bench/[pane, widgetref]

type
  PaneCallbacks* = object
    onFileSelected*: proc(pane: Pane, path: string) {.raises: [].}
    onNewModule*: proc(pane: Pane) {.raises: [].}
    onOpenModule*: proc(pane: Pane) {.raises: [].}
    onOpenProject*: proc(pane: Pane) {.raises: [].}

  PaneManager* = ref object
    panels*: seq[Pane]
    splitter: WidgetRef[QSplitter]
    lastFocusedPane*: Pane
    callbacks: PaneCallbacks
    hasProject: bool

proc closePane*(self: PaneManager, pane: Pane) {.raises: [].}
proc insertCol*(self: PaneManager, afterPane: Pane, col: WidgetRef[QSplitter])
proc insertRow*(self: PaneManager, afterPane: Pane, col: WidgetRef[QSplitter])

proc makePane(self: PaneManager, col: WidgetRef[QSplitter]): Pane =
  result = newPane(proc(ev: PaneEvent) {.raises: [].} =
    case ev.kind
    of peFileSelected: self.callbacks.onFileSelected(ev.pane, ev.path)
    of peClose:        self.closePane(ev.pane)
    of peVSplit:
      try: self.insertCol(ev.pane, col)
      except: discard
    of peHSplit:
      try: self.insertRow(ev.pane, col)
      except: discard
    of peNewModule:    self.callbacks.onNewModule(ev.pane)
    of peOpenModule:   self.callbacks.onOpenModule(ev.pane)
    of peOpenProject:  self.callbacks.onOpenProject(ev.pane))
  if self.hasProject:
    result.setProjectOpen(true)

proc init*(T: typedesc[PaneManager], splitter: QSplitter, cbs: PaneCallbacks): T =
  T(splitter: capture(splitter), callbacks: cbs)

proc addColumn*(self: PaneManager) =
  var col = QSplitter.create(cint 2)    # vertical
  col.setHandleWidth(cint 4)
  QWidget(h: col.h, owned: false).setAutoFillBackground(true)
  QWidget(h: col.h, owned: false).setStyleSheet("QSplitter::handle { background: #333333; }")
  col.owned = false
  let colRef = capture(col)
  let p = self.makePane(colRef)
  col.addWidget(p.widget())
  self.splitter.get().addWidget(QWidget(h: col.h, owned: false))
  self.panels.add(p)
  p.focus()

proc insertCol*(self: PaneManager, afterPane: Pane, col: WidgetRef[QSplitter]) =
  let colW = QWidget(h: col.h, owned: false)
  let idx = self.splitter.get().indexOf(colW)
  if idx < 0: return
  let oldSizes = self.splitter.get().sizes()
  let srcW = oldSizes[idx]
  var newCol = QSplitter.create(cint 2)   # vertical
  newCol.setHandleWidth(cint 4)
  QWidget(h: newCol.h, owned: false).setAutoFillBackground(true)
  QWidget(h: newCol.h, owned: false).setStyleSheet("QSplitter::handle { background: #333333; }")
  newCol.owned = false
  let newColRef = capture(newCol)
  let p = self.makePane(newColRef)
  newCol.addWidget(p.widget())
  self.splitter.get().insertWidget(cint(idx + 1), QWidget(h: newCol.h, owned: false))
  var newSizes = newSeq[cint](oldSizes.len + 1)
  for i in 0..<idx:               newSizes[i]     = oldSizes[i]
  newSizes[idx]                   = cint(srcW div 2)
  newSizes[idx + 1]               = cint(srcW - srcW div 2)
  for i in idx+1..<oldSizes.len:  newSizes[i + 1] = oldSizes[i]
  self.splitter.get().setSizes(newSizes)
  self.panels.add(p)
  p.focus()

proc insertRow*(self: PaneManager, afterPane: Pane, col: WidgetRef[QSplitter]) =
  let colSplitter = col.get()
  let idx = colSplitter.indexOf(afterPane.widget())
  if idx < 0: return
  let oldSizes = colSplitter.sizes()
  let srcH = oldSizes[idx]
  let p = self.makePane(col)
  colSplitter.insertWidget(cint(idx + 1), p.widget())
  var newSizes = newSeq[cint](oldSizes.len + 1)
  for i in 0..<idx:               newSizes[i]     = oldSizes[i]
  newSizes[idx]                   = cint(srcH div 2)
  newSizes[idx + 1]               = cint(srcH - srcH div 2)
  for i in idx+1..<oldSizes.len:  newSizes[i + 1] = oldSizes[i]
  colSplitter.setSizes(newSizes)
  self.panels.add(p)
  p.focus()

proc equalizeSplits*(self: PaneManager) =
  let n = self.splitter.get().count().int
  var sizes = newSeq[cint](n)
  for i in 0..<n:
    sizes[i] = cint(1)
  self.splitter.get().setSizes(sizes)

proc closePane*(self: PaneManager, pane: Pane) {.raises: [].} =
  if self.panels.len <= 1:
    pane.clearBuffer()
  else:
    pane.widget().hide()
    try:
      for i in countdown(self.panels.high, 0):
        if self.panels[i] == pane:
          self.panels.delete(i)
          break
    except: discard

proc splitRow*(self: PaneManager, pane: Pane) =
  let parent = pane.widget().parentWidget()
  if parent.h == nil: return
  let col = capture(QSplitter(h: parent.h, owned: false))
  self.insertRow(pane, col)

proc setProjectOpen*(self: PaneManager, open: bool) =
  self.hasProject = open
  for panel in self.panels:
    panel.setProjectOpen(open)

proc updateFocus*(self: PaneManager, focusedWidget: QWidget, isDark: bool) =
  for p in self.panels:
    let focused = focusedWidget.h != nil and p.widget().isAncestorOf(focusedWidget)
    p.setHeaderFocus(focused, isDark)
    if focused:
      self.lastFocusedPane = p
