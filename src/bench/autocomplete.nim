## Autocomplete popup implemented as a child widget of the editor viewport.
##
## Parenting the list to the editor's viewport keeps everything inside the
## Qt widget tree — no top-level window, no compositor involvement, works
## correctly on Wayland.  Positioning uses viewport-local cursorRect() coords.

import seaqt/[qwidget, qvboxlayout, qlistwidget, qlistwidgetitem,
              qrect, qplaintextedit, qobject]
import nimsuggest

type
  AutocompleteMenu* = ref object
    widgetH*:  pointer    ## QWidget popup handle (nil when closed/not yet open)
    listH*:    pointer    ## QListWidget handle
    completions*: seq[Completion]
    insertTextCb*: proc(text: string) {.raises: [].}
    closeCb*:      proc() {.raises: [].}

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

proc prevItem*(menu: AutocompleteMenu) {.raises: [].} =
  if menu == nil or menu.listH == nil: return
  let lw = QListWidget(h: menu.listH, owned: false)
  let prev = max(lw.currentRow() - cint 1, cint 0)
  lw.setCurrentRow(prev)

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
    try: menu.insertTextCb(selectedName) except: discard
  try: menu.closeCb() except: discard

proc dismiss*(menu: AutocompleteMenu) {.raises: [].} =
  ## Close without inserting.
  if menu == nil or menu.widgetH == nil: return
  menu.closeWidget()
  try: menu.closeCb() except: discard

proc isOpen*(menu: AutocompleteMenu): bool {.raises: [].} =
  menu != nil and menu.widgetH != nil

proc showCompletions*(editor: QPlainTextEdit,
                      completions: seq[Completion],
                      insertText: proc(text: string) {.raises: [].},
                      close: proc() {.raises: [].},
                      outMenu: ptr AutocompleteMenu) {.raises: [].} =
  echo "[autocomplete] showCompletions called with ", completions.len, " items"
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
    var popup = QWidget.create(viewport)
    popup.owned = false
    let popupH = popup.h
    menu.widgetH = popupH

    let pw = QWidget(h: popupH, owned: false)
    pw.setObjectName("acPopup")
    pw.setStyleSheet("""
      QWidget#acPopup {
        background: #1e1e2e;
        border: 1px solid #585b70;
      }
      QListWidget {
        background: #1e1e2e;
        color: #cdd6f4;
        border: none;
        font-family: 'Fira Code', monospace;
        font-size: 13px;
        outline: 0;
      }
      QListWidget::item { padding: 2px 8px; }
      QListWidget::item:selected {
        background: #313244;
        color: #cdd6f4;
      }
    """)

    # List widget (parented to popup via layout — it owns it)
    var listWidget = QListWidget.create()
    listWidget.owned = false
    let listH = listWidget.h
    menu.listH = listH

    listWidget.onItemDoubleClicked do(item: QListWidgetItem) {.raises: [].}:
      menu.accept()

    for c in completions:
      let label = c.symkind & "  " & c.name &
                  (if c.signature.len > 0: "  " & c.signature else: "")
      var item = QListWidgetItem.create(label)
      item.owned = false
      QListWidget(h: listH, owned: false).addItem(item)

    QListWidget(h: listH, owned: false).setCurrentRow(cint 0)

    var layout = QVBoxLayout.create()
    layout.owned = false
    layout.setContentsMargins(cint 1, cint 1, cint 1, cint 1)
    layout.setSpacing(cint 0)
    layout.addWidget(QWidget(h: listH, owned: false))
    pw.setLayout(QLayout(h: layout.h, owned: false))

    # Size: cap height to show at most ~10 items, max 280px
    let itemH = cint 22
    let visItems = min(cint(completions.len), cint 10)
    let popupW = cint 560
    let popupH2 = visItems * itemH + cint 4  # +4 for border

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

    echo "[autocomplete] Popup shown at viewport-local ", px, ",", py,
         " size ", popupW, "x", popupH2
  except:
    echo "[autocomplete] Error: " & getCurrentExceptionMsg()
