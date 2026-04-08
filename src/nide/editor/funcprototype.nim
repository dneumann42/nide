import seaqt/[qwidget, qvboxlayout, qlabel, qdialog, qpainter, qrect, qcursor]
import nide/nim/nimsuggest
import nide/helpers/qtconst
import nide/ui/widgets

const
  ProtoMinWidth = cint 450

type
  PrototypeWindow* = ref object
    dialogH*: pointer
    labelH*: pointer
    isVisible*: bool
    currentSymbol*: string
    currentModule*: string
    currentSignature*: string

proc closeWindow*(pw: PrototypeWindow) {.raises: [].} =
  if pw.dialogH == nil: return
  let d = QDialog(h: pw.dialogH, owned: false)
  d.hide()
  pw.dialogH = nil
  pw.labelH = nil
  pw.isVisible = false

proc showPrototype*(parent: QWidget,
                    symbol: string,
                    moduleName: string,
                    signature: string,
                    outWindow: ptr PrototypeWindow) {.raises: [].} =
  if signature.len == 0:
    if outWindow[] != nil:
      outWindow[].closeWindow()
    return

  try:
    if outWindow[] != nil and outWindow[].isVisible:
      if outWindow[].currentSymbol == symbol and outWindow[].currentModule == moduleName:
        return
      outWindow[].closeWindow()

    var w = PrototypeWindow(
      currentSymbol: symbol,
      currentModule: moduleName,
      currentSignature: signature,
      isVisible: true
    )
    outWindow[] = w

    var dialog = newWidget(QDialog.create(parent))
    let dialogH = dialog.h
    w.dialogH = dialogH

    dialog.setWindowTitle("Prototype - " & symbol)
    dialog.setWindowFlags(WF_Tool or WF_CustomizeWindowHint)
    dialog.setWindowFlags(cint(dialog.windowFlags()) and not WF_WindowTitleHint)

    var label = newWidget(QLabel.create())
    let labelH = label.h
    w.labelH = labelH

    let displayText = "<span style='color: #cdd6f4; font-weight: bold;'>" & symbol & 
                      "</span> <span style='color: #89b4fa;'>[" & moduleName & "]</span><br><br>" &
                      "<span style='color: #a6e3a1; font-family: monospace; font-size: 14px;'>" & signature & "</span>"
    label.setText(displayText)
    label.setStyleSheet("""
      background: #1e1e2e;
      border: 2px solid #89b4fa;
      border-radius: 8px;
      padding: 12px 16px;
      color: #cdd6f4;
      font-family: 'Fira Code', 'Consolas', monospace;
      font-size: 13px;
    """)

    label.setMinimumWidth(ProtoMinWidth)
    label.setTextFormat(TF_RichText)

    var layout = vbox()
    layout.addWidget(QWidget(h: labelH, owned: false))
    layout.applyTo(dialog.asWidget)

    dialog.setGeometry(150, 150, 550, 120)
    dialog.show()

  except:
    echo "[funcprototype] showPrototype error: " & getCurrentExceptionMsg()

proc isPrototypeVisible*(pw: PrototypeWindow): bool {.raises: [].} =
  return pw != nil and pw.isVisible

proc hidePrototype*(outWindow: ptr PrototypeWindow) {.raises: [].} =
  if outWindow[] != nil:
    outWindow[].closeWindow()
