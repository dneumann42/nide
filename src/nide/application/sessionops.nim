import std/options

import nide/navigation/sessionstate
import nide/editor/buffers
import nide/panemanager
import nide/pane/pane

proc buildLastSession*(paneManager: PaneManager, projectNimbleFile: string): LastSession =
  let columns = paneManager.visibleColumns()
  result.projectNimbleFile = projectNimbleFile
  for colIdx, panes in columns:
    var savedColumn = SavedColumnSession()
    for rowIdx, pane in panes:
      let cursor = pane.currentCursorPosition()
      let scroll = pane.currentScrollPosition()
      savedColumn.panes.add(SavedPaneSession(
        filePath: if pane.buffer != nil: pane.buffer.path() else: "",
        cursorLine: cursor.line,
        cursorColumn: cursor.col,
        verticalScroll: scroll.vertical,
        horizontalScroll: scroll.horizontal
      ))
      if pane == paneManager.lastFocusedPane:
        result.activeColumnIndex = colIdx
        result.activePaneIndex = rowIdx
    result.columns.add(savedColumn)
  if paneManager.lastFocusedPane == nil and
     result.columns.len > 0 and
     result.columns[0].panes.len > 0:
    result.activeColumnIndex = 0
    result.activePaneIndex = 0

proc restoreSessionLayout*(
    paneManager: PaneManager,
    layout: seq[SavedColumnSession],
    firstPane: Pane): seq[seq[Pane]] =
  result = @[@[firstPane]]
  while result[0].len < layout[0].panes.len:
    let newPane = paneManager.splitRow(result[0][^1])
    if newPane == nil:
      break
    result[0].add(newPane)

  for colIdx in 1..<layout.len:
    let newColPane = paneManager.addColumn()
    result.add(@[newColPane])
    while result[colIdx].len < layout[colIdx].panes.len:
      let newPane = paneManager.splitRow(result[colIdx][^1])
      if newPane == nil:
        break
      result[colIdx].add(newPane)

proc resolveFocusPane*(
    paneGrid: seq[seq[Pane]],
    activeColumnIndex, activePaneIndex: int): Option[Pane] =
  if activeColumnIndex >= 0 and activeColumnIndex < paneGrid.len:
    let col = paneGrid[activeColumnIndex]
    if activePaneIndex >= 0 and activePaneIndex < col.len:
      return some(col[activePaneIndex])
  if paneGrid.len > 0 and paneGrid[0].len > 0:
    return some(paneGrid[0][0])
  none(Pane)
