import std/[os]
import seaqt/[
  qwidget, qtabwidget, qtabbar, qsplitter, qrubberband,
  qpoint, qdrag, qmimedata, qfont]
import seaqt/QtGui/gen_qevent
import seaqt/QtCore/gen_qobject_types

import bench/buffers

const DragMime* = "application/x-bench-tabdrag"

type
  DropZone* = enum dzNone, dzLeft, dzRight, dzBottom

  Pane* = ref object
    tabWidget*: QTabWidget
    tabBar*: CustomTabBar   ## keeps GC ref alive
    buffers*: seq[Buffer]   ## in tab-index order
    parentH*: pointer       ## raw h of the QSplitter that owns this pane

  CustomTabBar* = ref object of VirtualQTabBar
    dragTabIdx*: cint
    dragStartX*, dragStartY*: cint
    pane*: Pane
    overlay*: DropOverlay

  DropOverlay* = ref object of VirtualQWidget
    rubberBand*: QRubberBand
    srcPaneIdx*: int
    srcTabIdx*: cint
    activeZone*: DropZone
    onDrop*: proc(srcIdx: int, tabIdx: cint, dst: Pane,
                  zone: DropZone) {.closure, raises: [].}

## Module-global panes list; bench.nim drives it via gPanes.
var gPanes*: seq[Pane]

## Forward declaration (body is at bottom of file)
proc newPane*(monoFont: QFont,
              onTabClose: proc(pane: Pane,
                               idx: cint) {.closure, raises: [].}): Pane {.raises: [].}

# ─── helpers ─────────────────────────────────────────────────────────────────

proc tabTitle*(buf: Buffer): string =
  if buf.path.len == 0: ScratchBufferName
  else: splitFile(buf.path).name & splitFile(buf.path).ext

proc paneIndexOf*(pane: Pane): int =
  for i, p in gPanes:
    if p == pane: return i
  -1

proc addTabToPane*(pane: Pane, buf: Buffer) =
  discard pane.tabWidget.addTab(QWidget(h: buf.editor.h, owned: false),
                                tabTitle(buf))
  pane.tabWidget.setCurrentIndex(pane.tabWidget.count() - 1)

# ─── DropOverlay ─────────────────────────────────────────────────────────────

proc hitTest(panes: seq[Pane], overlayH: pointer,
             pos: QPoint): (Pane, DropZone) {.raises: [].} =
  let overlayW = QWidget(h: overlayH, owned: false)
  for p in panes:
    let tw = QWidget(h: p.tabWidget.h, owned: false)
    let tl = tw.mapTo(overlayW, QPoint.create(0, 0))
    let tlx = tl.x()
    let tly = tl.y()
    let pw = tw.width()
    let ph = tw.height()
    let x = pos.x() - tlx
    let y = pos.y() - tly
    if x < 0 or y < 0 or x >= pw or y >= ph: continue
    let zone =
      if   x < pw * 25 div 100: dzLeft
      elif x > pw * 75 div 100: dzRight
      elif y > ph * 70 div 100: dzBottom
      else: dzNone
    return (p, zone)
  (nil, dzNone)

proc updateRubberBand(overlay: DropOverlay, pane: Pane,
                      zone: DropZone) {.raises: [].} =
  let tw = QWidget(h: pane.tabWidget.h, owned: false)
  let ow = QWidget(h: overlay[].h, owned: false)
  let tl = tw.mapTo(ow, QPoint.create(0, 0))
  let x = tl.x()
  let y = tl.y()
  let w = tw.width()
  let h = tw.height()
  let (rx, ry, rw, rh) =
    case zone
    of dzLeft:   (x, y, w div 2, h)
    of dzRight:  (x + w div 2, y, w - w div 2, h)
    of dzBottom: (x, y + h * 70 div 100, w, h - h * 70 div 100)
    of dzNone:   (x, y, w, h)
  overlay.rubberBand.setGeometry(cint rx, cint ry, cint rw, cint rh)
  QWidget(h: overlay.rubberBand.h, owned: false).show()

method dragEnterEvent*(self: DropOverlay, ev: QDragEnterEvent) =
  let dropEv = QDropEvent(h: ev.h, owned: false)
  if dropEv.mimeData().hasFormat(DragMime):
    dropEv.acceptProposedAction()

method dragMoveEvent*(self: DropOverlay, ev: QDragMoveEvent) =
  let dropEv = QDropEvent(h: ev.h, owned: false)
  let pos = dropEv.pos()
  let (pane, zone) = hitTest(gPanes, self[].h, pos)
  self.activeZone = zone
  if pane == nil or zone == dzNone:
    ev.ignore()
    QWidget(h: self.rubberBand.h, owned: false).hide()
    return
  dropEv.acceptProposedAction()
  updateRubberBand(self, pane, zone)

method dropEvent*(self: DropOverlay, ev: QDropEvent) =
  let pos = ev.pos()
  let (pane, zone) = hitTest(gPanes, self[].h, pos)
  ev.acceptProposedAction()
  QWidget(h: self.rubberBand.h, owned: false).hide()
  if pane != nil and zone != dzNone and self.onDrop != nil:
    self.onDrop(self.srcPaneIdx, self.srcTabIdx, pane, zone)

# ─── CustomTabBar ─────────────────────────────────────────────────────────────

method mousePressEvent*(self: CustomTabBar, ev: QMouseEvent) =
  QTabBarmousePressEvent(QTabBar(h: self[].h, owned: false), ev)
  let p = ev.pos()
  self.dragStartX = p.x()
  self.dragStartY = p.y()
  self.dragTabIdx = QTabBar(h: self[].h, owned: false).tabAt(p)

method mouseMoveEvent*(self: CustomTabBar, ev: QMouseEvent) =
  QTabBarmouseMoveEvent(QTabBar(h: self[].h, owned: false), ev)
  if self.dragTabIdx < 0: return
  let p = ev.pos()
  let dx = p.x() - self.dragStartX
  let dy = p.y() - self.dragStartY
  if abs(dx) + abs(dy) < 10: return

  let tabIdx = self.dragTabIdx
  self.dragTabIdx = -1

  if self.overlay == nil or self.overlay[].h == nil: return
  let pIdx = paneIndexOf(self.pane)
  if pIdx < 0: return

  self.overlay.srcPaneIdx = pIdx
  self.overlay.srcTabIdx = tabIdx

  let ow = QWidget(h: self.overlay[].h, owned: false)
  let parent = ow.parentWidget()
  ow.setGeometry(0, 0, parent.width(), parent.height())
  ow.show()
  ow.raiseX()

  let drag = QDrag.create(QObject(h: self[].h, owned: false))
  let mime = QMimeData.create()
  mime.setText(DragMime)
  drag.setMimeData(mime)
  discard drag.exec(cint 2)  # MoveAction

  ow.hide()
  QWidget(h: self.overlay.rubberBand.h, owned: false).hide()

method mouseReleaseEvent*(self: CustomTabBar, ev: QMouseEvent) =
  QTabBarmouseReleaseEvent(QTabBar(h: self[].h, owned: false), ev)
  self.dragTabIdx = -1

# ─── Split/remove logic ───────────────────────────────────────────────────────

proc removePaneFromSplitter*(pane: Pane) {.raises: [].} =
  let pIdx = gPanes.find(pane)
  if pIdx >= 0: gPanes.delete(pIdx)

  let tw = QWidget(h: pane.tabWidget.h, owned: false)
  let parentSplitter = QSplitter(h: pane.parentH, owned: false)
  if pane.parentH == nil: return
  let twIdx = parentSplitter.indexOf(tw)
  if twIdx < 0: return

  let count = parentSplitter.count()
  if count == 2:
    let otherIdx: cint = if twIdx == 0: 1 else: 0
    let otherWidget = parentSplitter.widget(otherIdx)
    let grandParentW = QWidget(h: pane.parentH, owned: false).parentWidget()
    if grandParentW.h != nil:
      let grandSplitter = QSplitter(h: grandParentW.h, owned: false)
      let splitterIdx = grandSplitter.indexOf(
        QWidget(h: pane.parentH, owned: false))
      if splitterIdx >= 0:
        discard grandSplitter.replaceWidget(splitterIdx, otherWidget)
        let oldParentH = pane.parentH
        for p in gPanes:
          if p.parentH == oldParentH:
            p.parentH = grandParentW.h
        return
    tw.hide()
  else:
    tw.hide()

proc doSplit*(srcPaneIdx: int, srcTabIdx: cint, dst: Pane,
              zone: DropZone, monoFont: QFont,
              onTabClose: proc(pane: Pane,
                               idx: cint) {.closure, raises: [].}) {.raises: [].} =
  if srcPaneIdx < 0 or srcPaneIdx >= gPanes.len: return
  let src = gPanes[srcPaneIdx]
  if srcTabIdx < 0 or srcTabIdx >= src.buffers.len: return
  if src == dst and src.buffers.len == 1: return

  # 1. Remove buffer from source pane
  let buf = src.buffers[srcTabIdx]
  src.buffers.delete(srcTabIdx)
  src.tabWidget.removeTab(srcTabIdx)

  # 2. Build new pane
  let np = newPane(monoFont, onTabClose)
  np.buffers.add(buf)
  gPanes.add(np)
  addTabToPane(np, buf)

  # 3. Replace dst's widget in its parent with a sub-splitter
  let orientation: cint = if zone in {dzLeft, dzRight}: cint 1 else: cint 2
  let dstWidget = QWidget(h: dst.tabWidget.h, owned: false)
  let parentSplitter = QSplitter(h: dst.parentH, owned: false)
  let dstIdx = parentSplitter.indexOf(dstWidget)

  let sub = QSplitter.create(orientation)
  discard parentSplitter.replaceWidget(dstIdx, QWidget(h: sub.h, owned: false))

  # 4. Populate sub-splitter (ordering depends on zone)
  if zone in {dzRight, dzBottom}:
    sub.addWidget(dstWidget)
    sub.addWidget(QWidget(h: np.tabWidget.h, owned: false))
  else:
    sub.addWidget(QWidget(h: np.tabWidget.h, owned: false))
    sub.addWidget(dstWidget)

  # 5. Update parentH for affected panes
  dst.parentH = sub.h
  np.parentH = sub.h

  # 6. Remove empty source pane if all tabs were moved
  if src.buffers.len == 0:
    removePaneFromSplitter(src)

# ─── Pane factory ─────────────────────────────────────────────────────────────

proc newPane*(monoFont: QFont,
              onTabClose: proc(pane: Pane,
                               idx: cint) {.closure, raises: [].}): Pane {.raises: [].} =
  let tw = QTabWidget.create()
  tw.setTabsClosable(true)
  tw.setMovable(true)
  tw.setAcceptDrops(false)

  result = Pane(tabWidget: tw)
  let paneRef = result  # stable ref captured by close handler

  let tb = CustomTabBar()
  QTabBar.create(tb)
  tb.dragTabIdx = -1
  tb.pane = result
  result.tabBar = tb

  result.tabWidget.setTabBar(QTabBar(h: tb[].h, owned: false))

  result.tabWidget.onTabCloseRequested do(index: cint):
    onTabClose(paneRef, index)
