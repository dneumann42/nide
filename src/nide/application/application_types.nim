import nide/editor/buffers
import nide/helpers/[logparser, widgetref]
import nide/nim/nimsuggest
import nide/pane/pane
import nide/panemanager
import nide/project/projects
import nide/settings/[projectconfig, settings, theme]
import nide/ui/[commandpalette, filetree, toolbar, widgets]
import seaqt/[qfilesystemwatcher, qgraphicsopacityeffect, qmainwindow, qtimer, qtoolbutton, qwidget]

type
  FileTreeClipboardMode* = enum
    ftcNone, ftcCopy, ftcCut

  PaneKeyBinding* = object
    sequence*: string
    callback*: proc(target: Pane) {.raises: [].}

  GlobalKeyBinding* = object
    sequence*: string
    callback*: proc() {.raises: [].}

  Application* = ref object
    bufferManager*: BufferManager
    toolbar*: Toolbar
    projectManager*: ProjectManager
    root*: QMainWindow
    paneManager*: PaneManager
    fileTree*: FileTree
    commandPalette*: CommandPalette
    theme*: Theme
    currentProject*: string
    projectNimbleFile*: string
    runStatusBtn*:  WidgetRef[QToolButton]
    buildStatusBtn*: WidgetRef[QToolButton]
    runReopen*:  proc() {.raises: [].}
    buildReopen*: proc() {.raises: [].}
    opacityEffect*: QGraphicsOpacityEffect
    nimSuggest*: NimSuggestClient
    settings*: Settings
    projectConfig*: ProjectConfig
    currentProjectBackend*: string
    fileWatcher*: QFileSystemWatcher
    loaderTimer*: QTimer
    projectDiagLines*: ref seq[LogLine]
    projectCheckProcessH*: ref pointer
    fileTreeClipboardPath*: string
    fileTreeClipboardMode*: FileTreeClipboardMode
    sessionSaveTimer*: QTimer
    sessionPersistenceReady*: bool
    restoringSession*: bool

const
  MinWindowWidth* = cint 800
  MinWindowHeight* = cint 480
  LoaderIntervalMs* = cint 200
  SessionSaveDebounceMs* = cint 200
  SplitterHandleWidth* = cint 4
  RunStatusOffsetX* = cint 110
  RunStatusOffsetY* = cint 40
  BuildStatusOffsetY* = cint 80
  FileWatcherRetryMs* = 50
  FileReadRetries* = 3

proc appWidget*(self: Application): QWidget {.raises: [].} =
  self.root.asWidget
