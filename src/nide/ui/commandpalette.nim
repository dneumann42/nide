import std/[algorithm, strutils]
import seaqt/[qwidget, qlineedit, qlistwidget, qlistwidgetitem, qshortcut,
              qkeysequence, qobject]
import commands
import nide/helpers/qtconst
import nide/settings/theme
import nide/ui/widgets

type
  PaletteItem* = object
    desc*: CommandDescriptor
    bindingText*: string

  CommandPalette* = ref object
    container*: QWidget
    inputH*: pointer
    listH*: pointer
    dispatcher*: CommandDispatcher
    items*: seq[PaletteItem]
    filtered*: seq[PaletteItem]
    onSelected*: proc(id: CommandId) {.raises: [].}
    onClosed*: proc() {.raises: [].}

const
  PaletteMargin = cint 20
  PaletteBottomGap = cint 16
  PaletteWidth = cint 760
  PaletteMinRows = cint 4
  PaletteMaxRows = cint 10
  PaletteRowHeight = cint 26
  PaletteChromeHeight = cint 44

proc reposition*(palette: CommandPalette) {.raises: [].}
proc populate(palette: CommandPalette, query: string) {.raises: [].}

proc applyTheme*(palette: CommandPalette, theme: Theme) {.raises: [].} =
  if palette == nil or palette.container.h == nil:
    return

  let panelBg = windowColor(theme)
  let controlBg = surfaceColor(theme)
  let headerBg = headerColor(theme)
  let border = borderColor(theme)
  let text = textColor(theme)
  let muted = mutedTextColor(theme)
  let selected = highlightColor(theme)
  let selectedText = highlightedTextColor(theme)

  palette.container.setStyleSheet(
    "QWidget#commandPalette {" &
    "  background: " & panelBg & ";" &
    "  border: 1px solid " & border & ";" &
    "  border-radius: 6px;" &
    "}" &
    "QLineEdit {" &
    "  background: " & headerBg & ";" &
    "  color: " & text & ";" &
    "  border: none;" &
    "  border-bottom: 1px solid " & border & ";" &
    "  padding: 10px 12px;" &
    "  font-family: '" & clMonoFont & "', monospace;" &
    "  font-size: " & clMonoSize & ";" &
    "  selection-background-color: " & selected & ";" &
    "  selection-color: " & selectedText & ";" &
    "}" &
    "QLineEdit[placeholderText]:empty { color: " & muted & "; }" &
    "QListWidget {" &
    "  background: " & controlBg & ";" &
    "  color: " & text & ";" &
    "  border: none;" &
    "  outline: 0;" &
    "  font-family: '" & clMonoFont & "', monospace;" &
    "  font-size: " & clMonoSize & ";" &
    "}" &
    "QListWidget::item { padding: 4px 10px; }" &
    "QListWidget::item:selected {" &
    "  background: " & selected & ";" &
    "  color: " & selectedText & ";" &
    "}"
  )

proc rebuildItems(palette: CommandPalette) {.raises: [].} =
  if palette == nil or palette.dispatcher == nil:
    return
  palette.items.setLen(0)
  for desc in palette.dispatcher.listCommands():
    let bindingText = palette.dispatcher.bindingStrings(desc.id).join(", ")
    palette.items.add(PaletteItem(desc: desc, bindingText: bindingText))

proc toStr(oa: openArray[char]): string {.raises: [].} =
  result = newString(oa.len)
  if oa.len > 0:
    copyMem(addr result[0], unsafeAddr oa[0], oa.len)

proc closeWidget(palette: CommandPalette) {.raises: [].} =
  if palette == nil or palette.container.h == nil:
    return
  palette.container.hide()
  try: palette.onClosed() except CatchableError: discard

proc scoreMatch(query: string, item: PaletteItem): tuple[ok: bool, rank: int, text: string] {.raises: [].} =
  let q = query.strip().toLowerAscii()
  let label = item.desc.label.toLowerAscii()
  let id = item.desc.id.toLowerAscii()
  if q.len == 0:
    return (true, 0, item.desc.label)
  if label == q:
    return (true, 0, item.desc.label)
  if id == q:
    return (true, 1, item.desc.label)
  if label.startsWith(q):
    return (true, 2, item.desc.label)
  if id.startsWith(q):
    return (true, 3, item.desc.label)
  for alias in item.desc.aliases:
    let lowered = alias.toLowerAscii()
    if lowered == q:
      return (true, 4, item.desc.label)
    if lowered.startsWith(q):
      return (true, 5, item.desc.label)
  if q in label:
    return (true, 6, item.desc.label)
  if q in id:
    return (true, 7, item.desc.label)
  for alias in item.desc.aliases:
    if q in alias.toLowerAscii():
      return (true, 8, item.desc.label)

  var qi = 0
  for ch in label:
    if qi < q.len and ch == q[qi]:
      inc qi
  if qi == q.len:
    return (true, 9, item.desc.label)
  qi = 0
  for ch in id:
    if qi < q.len and ch == q[qi]:
      inc qi
  if qi == q.len:
    return (true, 10, item.desc.label)
  (false, 0, item.desc.label)

proc formatRow(item: PaletteItem): string =
  if item.bindingText.len > 0:
    item.desc.label & "    " & item.bindingText
  else:
    item.desc.label

proc populate(palette: CommandPalette, query: string) {.raises: [].} =
  if palette == nil or palette.listH == nil:
    return
  let list = QListWidget(h: palette.listH, owned: false)
  list.clear()
  var matches: seq[tuple[rank: int, label: string, item: PaletteItem]]
  for item in palette.items:
    let score = scoreMatch(query, item)
    if score.ok:
      matches.add((score.rank, score.text, item))
  matches.sort(proc(a, b: tuple[rank: int, label: string, item: PaletteItem]): int {.raises: [].} =
    let rankCmp = cmp(a.rank, b.rank)
    if rankCmp != 0: return rankCmp
    cmp(a.label.toLowerAscii(), b.label.toLowerAscii()))
  palette.filtered.setLen(0)
  for (_, _, item) in matches:
    palette.filtered.add(item)
    list.addItem(formatRow(item))
  if list.count() > 0:
    list.setCurrentRow(cint 0)
  palette.reposition()

proc selectNext(palette: CommandPalette) {.raises: [].} =
  if palette == nil or palette.listH == nil:
    return
  let lw = QListWidget(h: palette.listH, owned: false)
  if lw.count() == 0:
    return
  lw.setCurrentRow(min(lw.currentRow() + cint 1, lw.count() - cint 1))

proc selectPrev(palette: CommandPalette) {.raises: [].} =
  if palette == nil or palette.listH == nil:
    return
  let lw = QListWidget(h: palette.listH, owned: false)
  if lw.count() == 0:
    return
  lw.setCurrentRow(max(lw.currentRow() - cint 1, cint 0))

proc activateCurrent(palette: CommandPalette) {.raises: [].} =
  if palette == nil or palette.listH == nil:
    return
  let row = QListWidget(h: palette.listH, owned: false).currentRow()
  if row < 0 or row >= cint(palette.filtered.len):
    return
  let id = palette.filtered[row].desc.id
  palette.closeWidget()
  try: palette.onSelected(id) except CatchableError: discard

proc dismiss*(palette: CommandPalette) {.raises: [].} =
  palette.closeWidget()

proc isOpen*(palette: CommandPalette): bool {.raises: [].} =
  palette != nil and palette.container.h != nil and palette.container.isVisible()

proc reposition*(palette: CommandPalette) {.raises: [].} =
  if palette == nil or palette.container.h == nil:
    return
  let parent = palette.container.parentWidget()
  if parent.h == nil:
    return
  let itemCount = max(1, palette.filtered.len)
  let rows = max(PaletteMinRows, min(PaletteMaxRows, cint(itemCount)))
  let width = min(PaletteWidth, max(cint 420, parent.width() - PaletteMargin * 2))
  let height = PaletteChromeHeight + rows * PaletteRowHeight
  let x = max(PaletteMargin, (parent.width() - width) div 2)
  let y = max(PaletteMargin, parent.height() - height - PaletteBottomGap)
  palette.container.setGeometry(x, y, width, height)
  palette.container.raiseX()

proc open*(palette: CommandPalette) {.raises: [].} =
  if palette == nil:
    return
  palette.rebuildItems()
  palette.populate("")
  palette.reposition()
  palette.container.show()
  palette.container.raiseX()
  if palette.inputH != nil:
    let input = QLineEdit(h: palette.inputH, owned: false)
    input.clear()
    input.setFocus()

proc refreshItems*(palette: CommandPalette) {.raises: [].} =
  if palette == nil:
    return
  palette.rebuildItems()
  let query =
    if palette.inputH != nil: $QLineEdit(h: palette.inputH, owned: false).text()
    else: ""
  palette.populate(query)

proc newCommandPalette*(parent: QWidget,
                        dispatcher: CommandDispatcher,
                        onSelected: proc(id: CommandId) {.raises: [].},
                        onClosed: proc() {.raises: [].}): CommandPalette {.raises: [].} =
  result = CommandPalette(dispatcher: dispatcher, onSelected: onSelected, onClosed: onClosed)
  let palette = result

  palette.container = newWidget(QWidget.create(parent))
  palette.container.setObjectName("commandPalette")
  palette.applyTheme(Dark)

  var input = lineEdit("Execute command")
  palette.inputH = input.h
  var listWidget = newWidget(QListWidget.create())
  palette.listH = listWidget.h

  let layout = vbox()
  layout.add(input)
  layout.add(listWidget)
  layout.applyTo(palette.container)

  palette.rebuildItems()

  input.onTextChanged do(text: openArray[char]) {.raises: [].}:
    palette.populate(toStr(text))

  listWidget.onItemDoubleClicked do(item: QListWidgetItem) {.raises: [].}:
    discard item
    palette.activateCurrent()

  var nextSc = newWidget(QShortcut.create(QKeySequence.create("Ctrl+N"),
                                          QObject(h: palette.container.h, owned: false)))
  nextSc.setContext(SC_WidgetWithChildrenShortcut)
  nextSc.onActivated do() {.raises: [].}:
    palette.selectNext()

  var prevSc = newWidget(QShortcut.create(QKeySequence.create("Ctrl+P"),
                                          QObject(h: palette.container.h, owned: false)))
  prevSc.setContext(SC_WidgetWithChildrenShortcut)
  prevSc.onActivated do() {.raises: [].}:
    palette.selectPrev()

  var downSc = newWidget(QShortcut.create(QKeySequence.create("Down"),
                                          QObject(h: palette.container.h, owned: false)))
  downSc.setContext(SC_WidgetWithChildrenShortcut)
  downSc.onActivated do() {.raises: [].}:
    palette.selectNext()

  var upSc = newWidget(QShortcut.create(QKeySequence.create("Up"),
                                        QObject(h: palette.container.h, owned: false)))
  upSc.setContext(SC_WidgetWithChildrenShortcut)
  upSc.onActivated do() {.raises: [].}:
    palette.selectPrev()

  var enterSc = newWidget(QShortcut.create(QKeySequence.create("Return"),
                                           QObject(h: palette.container.h, owned: false)))
  enterSc.setContext(SC_WidgetWithChildrenShortcut)
  enterSc.onActivated do() {.raises: [].}:
    palette.activateCurrent()

  var escSc = newWidget(QShortcut.create(QKeySequence.create("Escape"),
                                         QObject(h: palette.container.h, owned: false)))
  escSc.setContext(SC_WidgetWithChildrenShortcut)
  escSc.onActivated do() {.raises: [].}:
    palette.dismiss()

  palette.container.hide()
