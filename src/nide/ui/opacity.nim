import seaqt/[qwidget, qgraphicsopacityeffect, qgraphicseffect]
import nide/helpers/qtconst

proc setupWindowOpacity*(topLevel: QWidget, target: QWidget,
                         enabled: bool, level: int): QGraphicsOpacityEffect =
  ## Attach a QGraphicsOpacityEffect to `target` and mark `topLevel` as
  ## translucent.  `target` should be a child widget that fills `topLevel`
  ## (e.g. the central splitter or a content container).
  QWidget(h: topLevel.h, owned: false).setAttribute(WA_TranslucentBackground)
  QWidget(h: target.h,   owned: false).setAutoFillBackground(true)
  var eff = QGraphicsOpacityEffect.create()
  eff.owned = false
  eff.setOpacity(if enabled: float(level) / 100.0 else: 1.0)
  QWidget(h: target.h, owned: false).setGraphicsEffect(
    QGraphicsEffect(h: eff.h, owned: false))
  result = eff

proc applyOpacity*(eff: QGraphicsOpacityEffect, enabled: bool, level: int) =
  ## Update the effect level and force a repaint.
  eff.setOpacity(if enabled: float(level) / 100.0 else: 1.0)
  QGraphicsEffect(h: eff.h, owned: false).update()
