import std/[math, options]
import nide/editor/[sexpr_model, sexpr_parse]
import nide/helpers/qtconst
import nide/settings/syntaxtheme
import nide/ui/widgets
import seaqt/[qbrush, qclipboard, qcolor, qfont, qfontmetrics, qguiapplication,
              qinputdialog, qkeyevent, qmouseevent, qpainter, qpaintevent, qpaintdevice,
              qpen, qpoint, qrect, qwidget]

proc QWidget_virtbase(src: pointer, outQObject: ptr pointer, outPaintDevice: ptr pointer) {.importc: "QWidget_virtbase".}

proc widgetToPaintDevice(w: QWidget): QPaintDevice =
  var outQObject: pointer
  var outPaintDevice: pointer
  QWidget_virtbase(w.h, addr outQObject, addr outPaintDevice)
  QPaintDevice(h: outPaintDevice, owned: false)

type
  NodeRect = object
    id: SExprNodeId
    node: SExprNode
    x, y, w, h: cint

  InsertionSlot = object
    parent: SExprNodeId
    index: int
    x, y, w, h: cint

  SExprView* = ref object
    widget*: QWidget
    doc*: SExprDocument
    rects: seq[NodeRect]
    slots: seq[InsertionSlot]
    hoverId: SExprNodeId
    dragId: SExprNodeId
    dropSlot: Option[InsertionSlot]
    mouseDown: bool
    font: QFont
    layoutDirty: bool
    layoutWidth: cint
    contentWidth: cint
    contentHeight: cint
    onChanged*: proc() {.raises: [].}

const
  Margin = cint 8
  Gap = cint 4
  PadX = cint 6
  PadY = cint 3
  ListPadX = cint 12
  ListPadY = cint 6
  Indent = cint 14
  MinListWidth = cint 34
  SlotSize = cint 4
  Antialiasing = cint 1
  Key_W = cint 0x57
  Key_L = cint 0x4C
  Key_C = cint 0x43
  Key_V = cint 0x56
  Key_Y = cint 0x59

const palette = [
  "#385c78", "#5b4d7d", "#6b4f58", "#51735b", "#826536", "#3f6f70",
  "#6f5d86", "#765b49", "#506b91", "#746b43", "#806070", "#4d756b"
]

proc contains(r: NodeRect, p: QPoint): bool =
  p.x() >= r.x and p.x() <= r.x + r.w and p.y() >= r.y and p.y() <= r.y + r.h

proc contains(s: InsertionSlot, p: QPoint): bool =
  p.x() >= s.x and p.x() <= s.x + s.w and p.y() >= s.y and p.y() <= s.y + s.h

proc intersects(r: NodeRect, clip: QRect): bool =
  r.x <= clip.x() + clip.width() and r.x + r.w >= clip.x() and
    r.y <= clip.y() + clip.height() and r.y + r.h >= clip.y()

proc invalidateLayout(view: SExprView) =
  view.layoutDirty = true

proc notifyChanged(view: SExprView) =
  view.invalidateLayout()
  if view.onChanged != nil:
    view.onChanged()
  if view.widget.h != nil:
    view.widget.update()

proc colorFor(node: SExprNode): string =
  palette[node.id mod palette.len]

proc selected(view: SExprView): SExprNode =
  if view.doc == nil: nil else: view.doc.selectedNode()

proc textWidth(fm: QFontMetrics, text: string): cint =
  cint(max(fm.horizontalAdvance(if text.len == 0: "\"\"" else: text), 12))

proc layoutNode(view: SExprView, node: SExprNode, fm: QFontMetrics,
                x, y: cint): tuple[w, h: cint] =
  if node.kind == senAtom:
    result.w = textWidth(fm, node.text) + PadX * 2
    result.h = cint(fm.height() + PadY * 2)
    view.rects.add(NodeRect(id: node.id, node: node, x: x, y: y, w: result.w, h: result.h))
    return

  let rectIndex = view.rects.len
  view.rects.add(NodeRect(id: node.id, node: node, x: x, y: y, w: MinListWidth,
                          h: cint(fm.height() + PadY * 2)))
  var childY = y + ListPadY
  var maxChildW = cint 0
  var childRects: seq[NodeRect] = @[]
  for child in node.children:
    let childX = x + ListPadX + Indent
    let childRectIndex = view.rects.len
    let childSize = view.layoutNode(child, fm, childX, childY)
    let childRect = view.rects[childRectIndex]
    childRects.add(childRect)
    childY += childSize.h + Gap
    maxChildW = max(maxChildW, childSize.w)

  if node.children.len == 0:
    result.w = MinListWidth
    result.h = cint(fm.height() + PadY * 2)
  else:
    result.w = max(MinListWidth, ListPadX * 2 + Indent + maxChildW)
    result.h = max(cint(fm.height() + PadY * 2),
                   ListPadY * 2 + (childY - (y + ListPadY) - Gap))

  view.rects[rectIndex].w = result.w
  view.rects[rectIndex].h = result.h
  let slotX = x + ListPadX
  let slotW = max(cint 20, result.w - ListPadX * 2)
  if node.children.len == 0:
    view.slots.add(InsertionSlot(parent: node.id, index: 0,
      x: slotX, y: y + result.h div 2 - SlotSize div 2, w: slotW, h: SlotSize))
  else:
    for i, r in childRects:
      let slotY =
        if i == 0: r.y - Gap div 2 - SlotSize div 2
        else: r.y - Gap div 2 - SlotSize div 2
      view.slots.add(InsertionSlot(parent: node.id, index: i,
        x: slotX, y: max(y + SlotSize, slotY), w: slotW, h: SlotSize))
      if i == childRects.high:
        view.slots.add(InsertionSlot(parent: node.id, index: i + 1,
          x: slotX, y: r.y + r.h + Gap div 2, w: slotW, h: SlotSize))

proc layoutDocument(view: SExprView, fm: QFontMetrics) =
  if view.doc == nil or view.doc.root == nil:
    return
  var y = Margin
  var maxChildW = cint 96
  var childRects: seq[NodeRect] = @[]
  for child in view.doc.root.children:
    let childRectIndex = view.rects.len
    let childSize = view.layoutNode(child, fm, Margin, y)
    let childRect = view.rects[childRectIndex]
    childRects.add(childRect)
    y += childSize.h + Gap
    maxChildW = max(maxChildW, childSize.w)

  let slotW = max(cint 96, maxChildW)
  if childRects.len == 0:
    view.slots.add(InsertionSlot(parent: view.doc.root.id, index: 0,
      x: Margin, y: Margin, w: slotW, h: SlotSize))
  else:
    for i, r in childRects:
      view.slots.add(InsertionSlot(parent: view.doc.root.id, index: i,
        x: Margin, y: max(cint 0, r.y - Gap div 2 - SlotSize div 2), w: slotW, h: SlotSize))
      if i == childRects.high:
        view.slots.add(InsertionSlot(parent: view.doc.root.id, index: i + 1,
          x: Margin, y: r.y + r.h + Gap div 2, w: slotW, h: SlotSize))

proc rebuildLayout(view: SExprView, width: cint) =
  view.rects = @[]
  view.slots = @[]
  view.layoutWidth = width
  view.contentWidth = cint 240
  view.contentHeight = cint 160
  if view.doc == nil:
    view.layoutDirty = false
    return
  let fm = QFontMetrics.create(view.font)
  view.layoutDocument(fm)
  var maxX = cint 240
  var maxY = cint 160
  for r in view.rects:
    maxX = max(maxX, r.x + r.w + Margin)
    maxY = max(maxY, r.y + r.h + Margin)
  view.contentWidth = max(maxX, width)
  view.contentHeight = maxY
  if view.widget.h != nil:
    view.widget.setMinimumSize(view.contentWidth, view.contentHeight)
  view.layoutDirty = false

proc ensureLayout(view: SExprView, width: cint) =
  if view.layoutDirty or view.layoutWidth != width:
    view.rebuildLayout(width)

proc hitNode(view: SExprView, p: QPoint): SExprNode =
  for i in countdown(view.rects.high, 0):
    if view.rects[i].contains(p):
      return view.rects[i].node
  nil

proc hitSlot(view: SExprView, p: QPoint): Option[InsertionSlot] =
  for s in view.slots:
    if s.contains(p):
      return some(s)
  none(InsertionSlot)

proc editAtomDialog(view: SExprView, node: SExprNode) =
  if view.doc == nil:
    return
  let target =
    if node != nil and node.kind == senAtom: node
    else: view.doc.atom("atom")
  var ok = false
  let parent = QWidget(h: view.widget.h, owned: false)
  let text = QInputDialog.getText(parent, "Edit Atom", "Atom", cint 0, target.text, addr ok)
  if ok:
    if node == nil or node.kind != senAtom:
      view.doc.insertAfterSelected(target)
    discard view.doc.editAtom(target, text)
    view.notifyChanged()

proc pasteInto(view: SExprView, parent: SExprNode = nil, index = -1) =
  if view.doc == nil:
    return
  let text = QGuiApplication.clipboard().text()
  if text.len == 0:
    return
  let parsed = parseSExpr(text)
  var targetParent = parent
  if targetParent == nil:
    let selected = view.selected()
    targetParent = if selected != nil and selected.kind == senList: selected else: view.doc.root
  var insertAt = index
  for child in parsed.root.children:
    let clone = view.doc.cloneInto(child)
    if insertAt < 0:
      view.doc.addChild(targetParent, clone, dirty = false)
    else:
      view.doc.addChild(targetParent, clone, insertAt, dirty = false)
      inc insertAt
    view.doc.select(clone)
  view.doc.dirty = true
  view.notifyChanged()

proc copySelected(view: SExprView) =
  let node = view.selected()
  if node != nil:
    QGuiApplication.clipboard().setText(serializeNode(node))

proc keyEdit(view: SExprView, key, mods: cint, text: string): bool =
  if view.doc == nil:
    return false
  let selected = view.selected()
  let ctrl = (mods and ControlModifier) != 0
  let alt = (mods and cint 0x08000000) != 0
  let shift = (mods and cint 0x02000000) != 0

  if ctrl and key == Key_C:
    view.copySelected(); return true
  if (ctrl and key == Key_V) or (ctrl and key == Key_Y):
    view.pasteInto(); return true
  if ctrl and key == Key_W:
    if view.doc.wrapSelected(): view.notifyChanged()
    return true
  if ctrl and key == Key_L:
    if view.doc.liftSelected(): view.notifyChanged()
    return true
  if ctrl and key == Key_F:
    discard view.doc.siblingOfSelected(1)
    view.widget.update()
    return true
  if ctrl and key == cint 0x42:
    discard view.doc.siblingOfSelected(-1)
    view.widget.update()
    return true
  if ctrl and key == Key_N:
    discard view.doc.nextVisible(1)
    view.widget.update()
    return true
  if ctrl and key == Key_P:
    discard view.doc.nextVisible(-1)
    view.widget.update()
    return true
  if ctrl and key == cint 0x4B:
    if view.doc.liftSelected(): view.notifyChanged()
    return true
  if ctrl and (key == Key_Return or key == Key_Enter):
    if view.doc.wrapSelected(): view.notifyChanged()
    return true
  if alt and key == Key_F:
    discard view.doc.nextVisible(1)
    view.widget.update()
    return true
  if alt and key == cint 0x42:
    discard view.doc.nextVisible(-1)
    view.widget.update()
    return true

  case key
  of Key_Left:
    result = view.doc.siblingOfSelected(-1)
  of Key_Right:
    result = view.doc.siblingOfSelected(1)
  of Key_Up:
    if alt:
      if view.doc.moveSelectedBy(-1): view.notifyChanged()
      return true
    result = view.doc.parentOfSelected()
  of Key_Down:
    if alt:
      if view.doc.moveSelectedBy(1): view.notifyChanged()
      return true
    result = view.doc.firstChildOfSelected()
  of Key_Tab:
    result = if shift: view.doc.parentOfSelected() else: view.doc.firstChildOfSelected()
  of Key_Backspace, Key_Delete:
    if view.doc.deleteSelected(): view.notifyChanged()
    return true
  of Key_Return, Key_Enter:
    let atom = view.doc.atom("atom")
    view.doc.insertAfterSelected(atom)
    view.notifyChanged()
    view.editAtomDialog(atom)
    return true
  else:
    if text.len == 1 and not ctrl and not alt and selected != nil and selected.kind == senAtom:
      view.editAtomDialog(selected)
      return true
  if result:
    view.widget.update()

proc drawCachedNode(view: SExprView, painter: QPainter, r: NodeRect, clip: QRect) =
  if not r.intersects(clip):
    return
  let node = r.node
  let isSel = view.doc.selected == r.id
  let isHover = view.hoverId == r.id
  var pen = QPen.create(QColor.create(if isSel: "#f5d76e" elif isHover: "#b7c7d9" else: "#00000000"))
  pen.setWidth(if isSel: cint 3 else: cint 1)
  painter.setPen(pen)
  let fill =
    if node.kind == senList: colorFor(node)
    else: "#2f3440"
  painter.setBrush(QBrush.create(QColor.create(fill)))
  let radius = float64(max(cint 7, min(r.h div 2, cint 14)))
  painter.drawRoundedRect(r.x, r.y, r.w, r.h, radius, radius)
  if node.kind == senAtom:
    painter.setPen(QColor.create(editorForeground()))
    painter.drawText(r.x + PadX, r.y, r.w - PadX * 2, r.h,
                     AlignHCenterVCenter, if node.text.len == 0: "\"\"" else: node.text)

proc paint(view: SExprView, self: QWidget, event: QPaintEvent) =
  view.ensureLayout(self.width())
  var painter = QPainter.create(widgetToPaintDevice(self))
  painter.setRenderHint(Antialiasing, true)
  painter.setFont(view.font)
  painter.fillRect(event.rect(), QColor.create(editorBackground()))
  if view.doc != nil:
    let clip = event.rect()
    let clipBottom = clip.y() + clip.height()
    for r in view.rects:
      if r.y > clipBottom:
        break
      view.drawCachedNode(painter, r, clip)
  if view.dropSlot.isSome():
    let s = view.dropSlot.get()
    painter.setPen(QColor.create("#f5d76e"))
    painter.setBrush(QBrush.create(QColor.create("#f5d76e")))
    painter.drawRoundedRect(s.x, s.y, max(s.w, cint 20), max(s.h, SlotSize), 2.0, 2.0)
  discard painter.endX()

proc newSExprView*(onChanged: proc() {.raises: [].} = nil): SExprView =
  result = SExprView(onChanged: onChanged)
  result.doc = newSExprDocument()
  result.font = QFont.create("Fira Code")
  result.font.setPointSize(cint 14)
  result.font.setStyleHint(cint(QFontStyleHintEnum.TypeWriter))
  let view = result
  var vtbl = new QWidgetVTable
  vtbl.paintEvent = proc(self: QWidget, event: QPaintEvent) {.raises: [], gcsafe.} =
    {.cast(gcsafe).}:
      try: view.paint(self, event)
      except Exception: discard
  vtbl.keyPressEvent = proc(self: QWidget, e: QKeyEvent) {.raises: [], gcsafe.} =
    {.cast(gcsafe).}:
      try:
        if view.keyEdit(e.key(), e.modifiers(), $e.text()):
          return
      except Exception: discard
    QWidgetkeyPressEvent(self, e)
  vtbl.mousePressEvent = proc(self: QWidget, e: QMouseEvent) {.raises: [], gcsafe.} =
    {.cast(gcsafe).}:
      try:
        self.setFocus()
        view.ensureLayout(self.width())
        if e.button() == MB_RightButton:
          let parent = view.hitNode(e.pos())
          if parent != nil:
            view.doc.select(parent)
          let target = if parent != nil and parent.kind == senList: parent else: view.doc.root
          discard view.doc.appendAtom(target, "atom")
          view.notifyChanged()
          return
        let hit = view.hitNode(e.pos())
        if hit != nil:
          view.doc.select(hit)
          view.dragId = hit.id
          view.mouseDown = true
        else:
          let slot = view.hitSlot(e.pos())
          if slot.isSome():
            let parent = findNode(view.doc.root, slot.get().parent)
            if parent != nil:
              discard view.doc.appendAtom(parent, "atom")
              view.notifyChanged()
        self.update()
      except Exception: discard
  vtbl.mouseMoveEvent = proc(self: QWidget, e: QMouseEvent) {.raises: [], gcsafe.} =
    {.cast(gcsafe).}:
      try:
        view.ensureLayout(self.width())
        let hit = view.hitNode(e.pos())
        view.hoverId = if hit == nil: 0 else: hit.id
        if view.mouseDown and view.dragId != 0:
          view.dropSlot = view.hitSlot(e.pos())
        self.update()
      except Exception: discard
  vtbl.mouseReleaseEvent = proc(self: QWidget, e: QMouseEvent) {.raises: [], gcsafe.} =
    {.cast(gcsafe).}:
      try:
        if view.mouseDown and view.dragId != 0 and view.dropSlot.isSome():
          let dragged = findNode(view.doc.root, view.dragId)
          let slot = view.dropSlot.get()
          let parent = findNode(view.doc.root, slot.parent)
          if dragged != nil and parent != nil:
            discard view.doc.reparent(dragged, parent, slot.index)
            view.notifyChanged()
        view.mouseDown = false
        view.dragId = 0
        view.dropSlot = none(InsertionSlot)
        self.update()
      except Exception: discard
  vtbl.mouseDoubleClickEvent = proc(self: QWidget, e: QMouseEvent) {.raises: [], gcsafe.} =
    {.cast(gcsafe).}:
      try:
        view.ensureLayout(self.width())
        let hit = view.hitNode(e.pos())
        if hit != nil:
          view.doc.select(hit)
          if hit.kind == senAtom:
            view.editAtomDialog(hit)
          else:
            discard view.doc.appendAtom(hit, "atom")
            view.notifyChanged()
      except Exception: discard
  result.widget = newWidget(QWidget.create(vtbl = vtbl))
  result.widget.setFocusPolicy(FP_StrongFocus)
  result.widget.setMouseTracking(true)
  result.widget.setMinimumSize(cint 240, cint 160)
  result.widget.setStyleSheet("QWidget { background: " & editorBackground() & "; }")
  result.invalidateLayout()

proc setDocument*(view: SExprView, doc: SExprDocument) =
  view.doc = if doc == nil: newSExprDocument() else: doc
  view.invalidateLayout()
  if view.widget.h != nil:
    view.widget.update()

proc setEditorFont*(view: SExprView, family: string, size: int) =
  view.font = QFont.create(family)
  view.font.setPointSize(cint size)
  view.font.setStyleHint(cint(QFontStyleHintEnum.TypeWriter))
  if view.widget.h != nil:
    view.widget.setFont(view.font)
    view.invalidateLayout()
    view.widget.update()

proc focus*(view: SExprView) =
  if view != nil and view.widget.h != nil:
    view.widget.setFocus()

when defined(test):
  proc debugLayoutRects*(view: SExprView, width: cint): seq[tuple[id: SExprNodeId, x, y, w, h: int]] =
    view.ensureLayout(width)
    for r in view.rects:
      result.add((r.id, r.x.int, r.y.int, r.w.int, r.h.int))

  proc debugLayoutDirty*(view: SExprView): bool =
    view.layoutDirty
