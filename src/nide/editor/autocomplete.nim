## Autocomplete popup implemented as a child widget of the editor viewport.
##
## Parenting the list to the editor's viewport keeps everything inside the
## Qt widget tree — no top-level window, no compositor involvement, works
## correctly on Wayland.  Positioning uses viewport-local cursorRect() coords.

import seaqt/[qwidget, qlistwidget, qlistwidgetitem,
              qrect, qplaintextedit, qobject]
import nide/nim/nimsuggest, nide/ui/widgets, nide/helpers/uicolors
import nide/helpers/debuglog
import std/os

type
  AutocompleteMenu* = ref object
    widgetH*:  pointer    ## QWidget popup handle (nil when closed/not yet open)
    listH*:    pointer    ## QListWidget handle
    completions*: seq[Completion]
    explicitSelection*: bool
    insertTextCb*: proc(text: string) {.raises: [].}
    closeCb*:      proc() {.raises: [].}

const
  AcItemHeight = cint 22
  AcMaxVisibleItems = cint 10
  AcPopupWidth = cint 720
  AcMinVisibleRows = cint 2
  AcBorderPadding = cint 4

proc closeWidget(menu: AutocompleteMenu) {.raises: [].} =
  if menu.widgetH == nil: return
  let w = QWidget(h: menu.widgetH, owned: false)
  menu.widgetH = nil
  menu.listH = nil
  w.hide()
  # Schedule Qt-side deletion so the C++ object is freed on the next event loop
  QObject(h: w.h, owned: false).deleteLater()

proc nextItem*(menu: AutocompleteMenu) {.raises: [].} =
  if menu == nil or menu.listH == nil: return
  let lw = QListWidget(h: menu.listH, owned: false)
  let next = min(lw.currentRow() + cint 1, lw.count() - cint 1)
  lw.setCurrentRow(next)
  menu.explicitSelection = next >= 0

proc prevItem*(menu: AutocompleteMenu) {.raises: [].} =
  if menu == nil or menu.listH == nil: return
  let lw = QListWidget(h: menu.listH, owned: false)
  let prev = max(lw.currentRow() - cint 1, cint 0)
  lw.setCurrentRow(prev)
  menu.explicitSelection = prev >= 0

proc hasExplicitSelection*(menu: AutocompleteMenu): bool {.raises: [].} =
  menu != nil and menu.explicitSelection and menu.listH != nil and
    QListWidget(h: menu.listH, owned: false).currentRow() >= 0

proc accept*(menu: AutocompleteMenu) {.raises: [].} =
  ## Insert selected completion then close.
  if menu == nil or menu.widgetH == nil: return
  # Read selection before closing widget (sets listH to nil)
  var selectedName = ""
  if menu.listH != nil:
    let lw = QListWidget(h: menu.listH, owned: false)
    let row = lw.currentRow()
    if row >= 0 and row < cint(menu.completions.len):
      selectedName = menu.completions[row].name
  menu.closeWidget()
  if selectedName.len > 0:
    try: menu.insertTextCb(selectedName) except CatchableError: discard
  try: menu.closeCb() except CatchableError: discard

proc dismiss*(menu: AutocompleteMenu) {.raises: [].} =
  ## Close without inserting.
  if menu == nil or menu.widgetH == nil: return
  menu.closeWidget()
  try: menu.closeCb() except CatchableError: discard

proc isOpen*(menu: AutocompleteMenu): bool {.raises: [].} =
  menu != nil and menu.widgetH != nil

proc showCompletions*(editor: QPlainTextEdit,
                      completions: seq[Completion],
                      insertText: proc(text: string) {.raises: [].},
                      close: proc() {.raises: [].},
                      outMenu: ptr AutocompleteMenu) {.raises: [].} =
  logDebug("autocomplete: showCompletions called with ", completions.len, " items")
  if completions.len == 0:
    close()
    return

  try:
    # Dismiss any previously open menu
    if outMenu[] != nil and outMenu[].isOpen():
      outMenu[].dismiss()

    var menu = AutocompleteMenu(
      completions: completions,
      insertTextCb: insertText,
      closeCb: close
    )
    outMenu[] = menu

    # Cursor rect in viewport-local coordinates — no mapToGlobal needed.
    let curRect = editor.cursorRect()
    let localX = curRect.left()
    let localY = curRect.top() + curRect.height()

    # Parent the popup to the viewport so it renders as an in-window overlay.
    let viewport = editor.viewport()
    var popup = newWidget(QWidget.create(viewport))
    let popupH = popup.h
    menu.widgetH = popupH

    let pw = popup
    pw.setObjectName("acPopup")
    pw.setStyleSheet(
      "QWidget#acPopup {" &
      "  background: " & clBase & ";" &
      "  border: 1px solid " & clSurface2 & ";" &
      "}" &
      "QListWidget {" &
      "  background: " & clBase & ";" &
      "  color: " & clText & ";" &
      "  border: none;" &
      "  font-family: '" & clMonoFont & "', monospace;" &
      "  font-size: " & clMonoSize & ";" &
      "  outline: 0;" &
      "}" &
      "QListWidget::item { padding: 2px 8px; }" &
      "QListWidget::item:selected {" &
      "  background: " & clSurface0 & ";" &
      "  color: " & clText & ";" &
      "}"
    )

    # List widget (parented to popup via layout — it owns it)
    var listWidget = newWidget(QListWidget.create())
    let listH = listWidget.h
    menu.listH = listH

    listWidget.onItemDoubleClicked do(item: QListWidgetItem) {.raises: [].}:
      menu.accept()

    for c in completions:
      let location =
        if c.file.len > 0:
          "  " & c.file.lastPathPart & ":" & $c.line & ":" & $c.col
        else:
          ""
      let label = c.symkind & "  " & c.name &
                  (if c.signature.len > 0: "  " & c.signature else: "") &
                  location
      var item = newWidget(QListWidgetItem.create(label))
      listWidget.addItem(item)

    QListWidget(h: listH, owned: false).setCurrentRow(cint 0)
    menu.explicitSelection = true

    let layout = vbox(margins = (cint 1, cint 1, cint 1, cint 1))
    layout.add(listWidget)
    layout.applyTo(pw)

    # Size: cap height to show at most ~10 items. Keep a safer minimum size so
    # short result sets don't end up with scrollbars obscuring the row text.
    let itemH = AcItemHeight
    let visItems = min(cint(completions.len), AcMaxVisibleItems)
    let popupW = AcPopupWidth
    let popupH2 = max(visItems, AcMinVisibleRows) * itemH + AcBorderPadding  # +border

    let vpW = viewport.width()
    let vpH = viewport.height()

    var px = localX
    var py = localY
    # Clamp horizontally
    if px + popupW > vpW: px = max(cint 0, vpW - popupW)
    # Flip above cursor if not enough room below
    if py + popupH2 > vpH:
      py = max(cint 0, curRect.top() - popupH2)

    pw.setGeometry(px, py, popupW, popupH2)
    pw.raiseX()
    pw.show()

    logDebug("autocomplete: Popup shown at viewport-local ", px, ",", py,
         " size ", popupW, "x", popupH2)
  except CatchableError:
    logError("autocomplete: Error: ", getCurrentExceptionMsg())
