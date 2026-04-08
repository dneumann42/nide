import seaqt/[qwidget, qgraphicsopacityeffect, qgraphicseffect]
import nide/helpers/qtconst
import nide/ui/widgets

proc setupWindowOpacity*(topLevel: QWidget, target: QWidget,
                         enabled: bool, level: int): QGraphicsOpacityEffect =
  ## Attach a QGraphicsOpacityEffect to `target` and mark `topLevel` as
  ## translucent.  `target` should be a child widget that fills `topLevel`
  ## (e.g. the central splitter or a content container).
  topLevel.setAttribute(WA_TranslucentBackground)
  target.setAutoFillBackground(true)
  var eff = newWidget(QGraphicsOpacityEffect.create())
  eff.setOpacity(if enabled: float(level) / 100.0 else: 1.0)
  target.setGraphicsEffect(QGraphicsEffect(h: eff.h, owned: false))
  result = eff

proc applyOpacity*(eff: QGraphicsOpacityEffect, enabled: bool, level: int) =
  ## Update the effect level and force a repaint.
  eff.setOpacity(if enabled: float(level) / 100.0 else: 1.0)
  QGraphicsEffect(h: eff.h, owned: false).update()
