## widgets.nim
## UI helpers that reduce boilerplate across the nide codebase.
##
## Provides:
##   - svgIcon: canonical SVG-to-QIcon renderer (consolidates pane.nim + toolbar.nim copies)
##   - makeIconButton / makeIconPushButton: icon button factory
##   - asWidget / asButton / asLayout: inline cast helpers that eliminate QWidget(h:,owned:false) noise
##   - vbox / hbox: layout builder procs
##   - add / applyTo: layout population helpers
##   - newWidget: template for owned=false auto-set on widget creation

import std/strutils
import seaqt/[qpixmap, qpaintdevice, qpainter, qcolor, qicon, qsvgrenderer,
              qwidget, qabstractbutton, qlayout, qboxlayout,
              qvboxlayout, qhboxlayout, qsize, qtoolbutton, qpushbutton,
              qlabel, qlineedit, qcheckbox]
import nide/helpers/uicolors
import nide/helpers/qtconst

export uicolors

# ---------------------------------------------------------------------------
# Widget creation with auto-owned=false
# ---------------------------------------------------------------------------

template newWidget*(createProc: untyped): untyped =
  ## Creates a widget and automatically sets owned=false.
  ## Usage: let btn = newWidget(QPushButton.create("text"))
  let result = createProc
  result.owned = false
  result

# ---------------------------------------------------------------------------
# SVG icon rendering
# ---------------------------------------------------------------------------

proc svgIcon*(svg: string, size: cint): QIcon =
  ## Render an SVG string to a QIcon at the given pixel size.
  var pm = QPixmap.create(size, size)
  pm.fill(QColor.create("transparent"))
  var painter = QPainter.create(QPaintDevice(h: pm.h, owned: false))
  var renderer = QSvgRenderer.create(svg.toOpenArrayByte(0, svg.high))
  renderer.render(painter)
  discard painter.endX()
  QIcon.create(pm)

proc svgIcon*(svg: string, size: cint, color: string): QIcon =
  ## Render an SVG with fill/stroke/currentColor replaced by `color`.
  var s = svg.replace("fill=\"white\"", "fill=\"" & color & "\"")
  s = s.replace("stroke=\"white\"", "stroke=\"" & color & "\"")
  s = s.replace("currentColor", color)
  var pm = QPixmap.create(size, size)
  pm.fill(QColor.create("transparent"))
  var painter = QPainter.create(QPaintDevice(h: pm.h, owned: false))
  var renderer = QSvgRenderer.create(s.toOpenArrayByte(0, s.high))
  renderer.render(painter)
  discard painter.endX()
  QIcon.create(pm)

# ---------------------------------------------------------------------------
# Cast helpers — eliminate QWidget(h: x.h, owned: false) noise
# ---------------------------------------------------------------------------

func asWidget*(w: QToolButton): QWidget {.inline.} =
  QWidget(h: w.h, owned: false)

func asWidget*(w: QPushButton): QWidget {.inline.} =
  QWidget(h: w.h, owned: false)

func asWidget*(w: QWidget): QWidget {.inline.} =
  QWidget(h: w.h, owned: false)

func asButton*(w: QToolButton): QAbstractButton {.inline.} =
  QAbstractButton(h: w.h, owned: false)

func asButton*(w: QPushButton): QAbstractButton {.inline.} =
  QAbstractButton(h: w.h, owned: false)

func asLayout*(w: QVBoxLayout): QLayout {.inline.} =
  QLayout(h: w.h, owned: false)

func asLayout*(w: QHBoxLayout): QLayout {.inline.} =
  QLayout(h: w.h, owned: false)

# ---------------------------------------------------------------------------
# Icon button factory
# ---------------------------------------------------------------------------

proc makeIconButton*(svg: string, iconSize: cint, widgetSize: cint = 18): QToolButton =
  ## Create a flat autoraise QToolButton with a fixed square size and SVG icon.
  result = QToolButton.create()
  result.owned = false
  result.setAutoRaise(true)
  result.asWidget.setFixedSize(widgetSize, widgetSize)
  result.asButton.setIcon(svgIcon(svg, iconSize))
  result.asButton.setIconSize(QSize.create(iconSize, iconSize))

proc makeIconButton*(svg: string, iconSize: cint, color: string,
                     widgetSize: cint = 18): QToolButton =
  ## Overload that applies a fill color to the SVG.
  result = QToolButton.create()
  result.owned = false
  result.setAutoRaise(true)
  result.asWidget.setFixedSize(widgetSize, widgetSize)
  result.asButton.setIcon(svgIcon(svg, iconSize, color))
  result.asButton.setIconSize(QSize.create(iconSize, iconSize))

proc makeIconPushButton*(svg: string, iconSize: cint, widgetSize: cint = 18): QPushButton =
  ## Create a flat QPushButton with a fixed square size and SVG icon.
  result = QPushButton.create("")
  result.owned = false
  result.setFlat(true)
  result.asWidget.setFixedSize(widgetSize, widgetSize)
  result.asButton.setIcon(svgIcon(svg, iconSize))
  result.asButton.setIconSize(QSize.create(iconSize, iconSize))

# ---------------------------------------------------------------------------
# Layout builders
# ---------------------------------------------------------------------------

proc vbox*(margins: tuple[l, t, r, b: cint] = (cint 0, cint 0, cint 0, cint 0),
           spacing: cint = cint 0): QVBoxLayout =
  ## Create a QVBoxLayout with owned=false, margins, and spacing pre-set.
  result = QVBoxLayout.create()
  result.owned = false
  result.setContentsMargins(margins.l, margins.t, margins.r, margins.b)
  result.setSpacing(spacing)

proc hbox*(margins: tuple[l, t, r, b: cint] = (cint 0, cint 0, cint 0, cint 0),
           spacing: cint = cint 0): QHBoxLayout =
  ## Create a QHBoxLayout with owned=false, margins, and spacing pre-set.
  result = QHBoxLayout.create()
  result.owned = false
  result.setContentsMargins(margins.l, margins.t, margins.r, margins.b)
  result.setSpacing(spacing)

template add*(layout: QVBoxLayout | QHBoxLayout, widget: typed) =
  ## Add any widget (any type with a .h field) to a layout.
  layout.addWidget(QWidget(h: widget.h, owned: false))

template addSub*(layout: QVBoxLayout | QHBoxLayout, sublayout: typed) =
  ## Add a nested layout to a layout.
  layout.addLayout(QLayout(h: sublayout.h, owned: false))

template applyTo*(layout: typed, widget: QWidget) =
  ## Set this layout on a container widget.
  widget.setLayout(QLayout(h: layout.h, owned: false))

# ---------------------------------------------------------------------------
# Simple widget builders
# ---------------------------------------------------------------------------

proc label*(text: string = "", style: string = ""): QLabel =
  ## Create a QLabel with owned=false.
  result = QLabel.create(text)
  result.owned = false
  if style.len > 0:
    QWidget(h: result.h, owned: false).setStyleSheet(style)

proc button*(text: string, flat: bool = true): QPushButton =
  ## Create a QPushButton with owned=false, optionally flat.
  result = QPushButton.create(text)
  result.owned = false
  result.setFlat(flat)

proc checkbox*(text: string, checked: bool = false): QCheckBox =
  result = QCheckBox.create(text)
  result.owned = false
  result.setChecked(checked)

proc lineEdit*(placeholder: string = "", minWidth: cint = 0): QLineEdit =
  result = QLineEdit.create()
  result.owned = false
  if placeholder.len > 0:
    result.setPlaceholderText(placeholder)
  if minWidth > 0:
    result.setMinimumWidth(minWidth)

# ---------------------------------------------------------------------------
# Spacers and stretch
# ---------------------------------------------------------------------------

proc stretch*(): QWidget =
  ## Create a stretch widget (invisible spacer).
  result = QWidget.create()
  result.owned = false
  result.setSizePolicy(SP_Preferred, SP_Preferred)

proc hstretch*(): QWidget =
  result = QWidget.create()
  result.owned = false
  result.setSizePolicy(SP_Expanding, SP_Minimum)

proc vstretch*(): QWidget =
  result = QWidget.create()
  result.owned = false
  result.setSizePolicy(SP_Minimum, SP_Expanding)

# ---------------------------------------------------------------------------
# Common widget configurations
# ---------------------------------------------------------------------------

template clickable*(btn: QPushButton, body: untyped) =
  ## Attach a clicked handler to a button.
  btn.onClicked do() {.raises: [].}: body

template clickable*(btn: QCheckBox, body: untyped) =
  btn.onToggled do(checked: bool) {.raises: [].}:
    body(checked)
