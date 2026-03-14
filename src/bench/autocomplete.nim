import std/[strutils, os]
import seaqt/[qwidget, qvboxlayout, qdialog, qlistwidget, qlistwidgetitem,
              qshortcut, qkeysequence, qobject, qpalette, qcolor]
import bench/nimsuggest

type
  AutocompleteData = object
    completions: seq[Completion]
    insertTextCb: proc(text: string) {.raises: [].}
    closeCb: proc() {.raises: [].}

proc showCompletions*(parent: QWidget,
                      completions: seq[Completion],
                      insertText: proc(text: string) {.raises: [].},
                      close: proc() {.raises: [].},
                      outDialogH: pointer = nil) {.raises: [].} =
  echo "[autocomplete] showCompletions called with ", completions.len, " items"
  if completions.len == 0:
    close()
    return

  try:
    var dialog = QDialog.create(parent)
    dialog.owned = false
    let dialogH = dialog.h
    if outDialogH != nil:
      cast[ptr pointer](outDialogH)[] = dialogH

    QWidget(h: dialogH, owned: false).setWindowFlags(cint(1))  # Qt::Dialog
    QWidget(h: dialogH, owned: false).setFocusPolicy(cint 0)

    var listWidget = QListWidget.create()
    listWidget.owned = false
    let listH = listWidget.h

    var layout = QVBoxLayout.create()
    layout.owned = false
    layout.setContentsMargins(cint 0, cint 0, cint 0, cint 0)
    layout.setSpacing(cint 0)
    layout.addWidget(QWidget(h: listWidget.h, owned: false))
    QWidget(h: dialogH, owned: false).setLayout(QLayout(h: layout.h, owned: false))

    var pal = QPalette.create()
    QPalette(h: pal.h, owned: false).setColor(cint 8, QColor.create("#2d2d2d"))
    QPalette(h: pal.h, owned: false).setColor(cint 0, QColor.create("#2d2d2d"))
    QWidget(h: dialogH, owned: false).setPalette(pal)
    QWidget(h: dialogH, owned: false).setStyleSheet("QListWidget { border: 1px solid #444; }")

    for c in completions:
      var item = QListWidgetItem.create(c.symkind & " " & c.name & " " & c.signature)
      item.owned = false
      QListWidget(h: listH, owned: false).addItem(item)

    QListWidget(h: listH, owned: false).setCurrentRow(cint 0)

    var data = AutocompleteData(completions: completions, insertTextCb: insertText, closeCb: close)

    listWidget.onItemDoubleClicked do(item: QListWidgetItem) {.raises: [].}:
      let row = QListWidget(h: listH, owned: false).currentRow()
      if row >= 0 and row < cint(completions.len):
        let c = completions[row]
        try: data.insertTextCb(c.name) except: discard
        QDialog(h: dialogH, owned: false).accept()

    var nextSc = QShortcut.create(QKeySequence.create("Ctrl+N"),
                                  QObject(h: dialogH, owned: false))
    nextSc.owned = false
    nextSc.setContext(cint 2)
    nextSc.onActivated do() {.raises: [].}:
      let lw = QListWidget(h: listH, owned: false)
      let next = min(lw.currentRow() + cint 1, lw.count() - cint 1)
      lw.setCurrentRow(next)

    var prevSc = QShortcut.create(QKeySequence.create("Ctrl+P"),
                                  QObject(h: dialogH, owned: false))
    prevSc.owned = false
    prevSc.setContext(cint 2)
    prevSc.onActivated do() {.raises: [].}:
      let lw = QListWidget(h: listH, owned: false)
      let prev = max(lw.currentRow() - cint 1, cint 0)
      lw.setCurrentRow(prev)

    var enterSc = QShortcut.create(QKeySequence.create("Return"),
                                   QObject(h: dialogH, owned: false))
    enterSc.owned = false
    enterSc.setContext(cint 2)
    enterSc.onActivated do() {.raises: [].}:
      let lw = QListWidget(h: listH, owned: false)
      let row = lw.currentRow()
      if row >= 0 and row < cint(completions.len):
        let c = completions[row]
        try: data.insertTextCb(c.name) except: discard
        QDialog(h: dialogH, owned: false).accept()

    var escapeSc = QShortcut.create(QKeySequence.create("Escape"),
                                    QObject(h: dialogH, owned: false))
    escapeSc.owned = false
    escapeSc.setContext(cint 2)
    escapeSc.onActivated do() {.raises: [].}:
      QDialog(h: dialogH, owned: false).reject()

    echo "[autocomplete] About to exec dialog"
    QWidget(h: dialogH, owned: false).show()
    echo "[autocomplete] Dialog should be visible now, pos"
    discard QDialog(h: dialogH, owned: false).exec()
    echo "[autocomplete] Dialog closed, result="
  except:
    echo "[autocomplete] Error: " & getCurrentExceptionMsg()
