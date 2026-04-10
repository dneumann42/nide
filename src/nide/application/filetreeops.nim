import std/[os, strutils]
import seaqt/[qfilesystemwatcher, qinputdialog, qmessagebox, qwidget]
import nide/application/application_types
import nide/editor/buffers
import nide/helpers/[fspaths, qtconst]
import nide/pane/pane
import nide/panemanager
import nide/ui/[filetree, widgets]

proc showFileTreeError(self: Application, title, message: string) {.raises: [].} =
  discard QMessageBox.critical(self.appWidget(), title, message)

proc showFileTreeInfo(self: Application, title, message: string) {.raises: [].} =
  discard QMessageBox.information(self.appWidget(), title, message)

proc promptFileTreeText(
    self: Application,
    title, labelText: string,
    defaultValue = "",
    okText = "OK"): string {.raises: [].} =
  var dialog = newWidget(QInputDialog.create(self.appWidget()))
  dialog.setWindowTitle(title)
  dialog.setInputMode(ID_TextInput)
  dialog.setLabelText(labelText)
  dialog.setTextValue(defaultValue)
  dialog.setOkButtonText(okText)
  dialog.setCancelButtonText("Cancel")
  if dialog.exec() == 1:
    result = dialog.textValue()

proc validateFileTreeName(name: string): string =
  if name.strip().len == 0:
    return "Name cannot be empty."
  if name == "." or name == "..":
    return "Name must not be '.' or '..'."
  if '/' in name or '\\' in name:
    return "Name must not contain path separators."

proc clearFileTreeClipboard*(self: Application) =
  self.fileTreeClipboardPath = ""
  self.fileTreeClipboardMode = ftcNone

proc canPasteInFileTree*(self: Application): bool =
  self.fileTreeClipboardMode != ftcNone and self.fileTreeClipboardPath.len > 0

proc refreshFileTree*(self: Application) {.raises: [].} =
  if self.currentProject.len > 0:
    self.fileTree.setRoot(self.currentProject)

proc syncClipboardAfterRename(self: Application, oldPath, newPath: string, isDir: bool) =
  if self.fileTreeClipboardPath.len == 0:
    return
  if isDir:
    if isSameOrChildPath(self.fileTreeClipboardPath, oldPath):
      self.fileTreeClipboardPath = remapPath(self.fileTreeClipboardPath, oldPath, newPath)
  elif normalizedFsPath(self.fileTreeClipboardPath) == normalizedFsPath(oldPath):
    self.fileTreeClipboardPath = newPath

proc clearClipboardIfDeleted(self: Application, deletedPath: string, isDir: bool) =
  if self.fileTreeClipboardPath.len == 0:
    return
  if isDir:
    if isSameOrChildPath(self.fileTreeClipboardPath, deletedPath):
      self.clearFileTreeClipboard()
  elif normalizedFsPath(self.fileTreeClipboardPath) == normalizedFsPath(deletedPath):
    self.clearFileTreeClipboard()

proc syncOpenBuffersAfterRename*(self: Application, oldPath, newPath: string, isDir: bool) {.raises: [].} =
  var changedBuffers: seq[Buffer]
  for buf in self.bufferManager.items:
    let shouldUpdate =
      if isDir: isSameOrChildPath(buf.path, oldPath)
      else: normalizedFsPath(buf.path) == normalizedFsPath(oldPath)
    if not shouldUpdate:
      continue

    let previousPath = buf.path
    let updatedPath = if isDir: remapPath(previousPath, oldPath, newPath) else: newPath
    discard self.fileWatcher.removePath(previousPath)
    buf.name = updatedPath
    buf.path = updatedPath
    if fileExists(updatedPath):
      discard self.fileWatcher.addPath(updatedPath)
    changedBuffers.add(buf)

  for panel in self.paneManager.panels:
    if panel.buffer == nil:
      continue
    for buf in changedBuffers:
      if panel.buffer == buf:
        panel.setBuffer(buf)
        break

proc syncOpenBuffersAfterDelete*(self: Application, deletedPath: string, isDir: bool) {.raises: [].} =
  var deletedBuffers: seq[Buffer]
  for buf in self.bufferManager.items:
    let shouldDelete =
      if isDir: isSameOrChildPath(buf.path, deletedPath)
      else: normalizedFsPath(buf.path) == normalizedFsPath(deletedPath)
    if shouldDelete:
      deletedBuffers.add(buf)
      discard self.fileWatcher.removePath(buf.path)

  for panel in self.paneManager.panels:
    if panel.buffer == nil:
      continue
    for buf in deletedBuffers:
      if panel.buffer == buf:
        panel.clearBuffer()
        break

  if isDir:
    self.bufferManager.closePathsUnder(deletedPath)
  else:
    self.bufferManager.closePath(deletedPath)

proc copyFileTreeItem*(self: Application, path: string) =
  self.fileTreeClipboardPath = path
  self.fileTreeClipboardMode = ftcCopy

proc cutFileTreeItem*(self: Application, path: string) =
  self.fileTreeClipboardPath = path
  self.fileTreeClipboardMode = ftcCut

proc moveFileTreeItem*(self: Application, sourcePath, destinationDir: string): bool {.raises: [].} =
  if not pathExistsAny(sourcePath):
    self.showFileTreeError("Move Failed", "The source item no longer exists.")
    return
  if not dirExists(destinationDir):
    return

  let destinationPath = destinationDir / sourcePath.lastPathPart()
  let sourceIsDir = dirExists(sourcePath)

  if normalizedFsPath(sourcePath) == normalizedFsPath(destinationPath):
    return
  if normalizedFsPath(sourcePath.parentDir()) == normalizedFsPath(destinationDir):
    return
  if pathExistsAny(destinationPath):
    self.showFileTreeError("Move Failed", "An item with that name already exists in the destination.")
    return
  if sourceIsDir and isSameOrChildPath(destinationDir, sourcePath):
    self.showFileTreeError("Move Failed", "Cannot move a folder into itself or one of its children.")
    return

  try:
    if sourceIsDir:
      moveDir(sourcePath, destinationPath)
    else:
      moveFile(sourcePath, destinationPath)
    self.syncOpenBuffersAfterRename(sourcePath, destinationPath, sourceIsDir)
    self.syncClipboardAfterRename(sourcePath, destinationPath, sourceIsDir)
    self.refreshFileTree()
    result = true
  except Exception as exc:
    self.showFileTreeError("Move Failed", exc.msg)

proc pasteFileTreeItem*(self: Application, path: string, isDir: bool) {.raises: [].} =
  if not self.canPasteInFileTree():
    self.showFileTreeInfo("Paste", "Nothing to paste.")
    return

  let sourcePath = self.fileTreeClipboardPath
  if not pathExistsAny(sourcePath):
    self.clearFileTreeClipboard()
    self.showFileTreeError("Paste Failed", "The source item no longer exists.")
    return

  let destinationDir = if isDir: path else: path.parentDir()
  let destinationPath = destinationDir / sourcePath.lastPathPart()
  let sourceIsDir = dirExists(sourcePath)

  if normalizedFsPath(sourcePath) == normalizedFsPath(destinationPath):
    self.showFileTreeError("Paste Failed", "The destination is the same as the source.")
    return
  if pathExistsAny(destinationPath):
    self.showFileTreeError("Paste Failed", "An item with that name already exists in the destination.")
    return
  if sourceIsDir and isSameOrChildPath(destinationDir, sourcePath):
    self.showFileTreeError("Paste Failed", "Cannot paste a folder into itself or one of its children.")
    return

  try:
    case self.fileTreeClipboardMode
    of ftcCopy:
      if sourceIsDir:
        copyDir(sourcePath, destinationPath)
      else:
        copyFile(sourcePath, destinationPath)
      self.refreshFileTree()
    of ftcCut:
      if self.moveFileTreeItem(sourcePath, destinationDir):
        self.clearFileTreeClipboard()
    of ftcNone:
      discard
  except Exception as exc:
    self.showFileTreeError("Paste Failed", exc.msg)

proc renameFileTreeItem*(self: Application, path: string, isDir: bool) {.raises: [].} =
  let currentName = path.lastPathPart()
  let newName = self.promptFileTreeText("Rename", "New name", currentName, "Rename")
  if newName.len == 0:
    return

  let validationError = validateFileTreeName(newName)
  if validationError.len > 0:
    self.showFileTreeError("Rename Failed", validationError)
    return
  if newName == currentName:
    return

  let destinationPath = path.parentDir() / newName
  if pathExistsAny(destinationPath):
    self.showFileTreeError("Rename Failed", "An item with that name already exists.")
    return

  try:
    if isDir:
      moveDir(path, destinationPath)
    else:
      moveFile(path, destinationPath)
    self.syncOpenBuffersAfterRename(path, destinationPath, isDir)
    self.syncClipboardAfterRename(path, destinationPath, isDir)
    self.refreshFileTree()
  except Exception as exc:
    self.showFileTreeError("Rename Failed", exc.msg)

proc deleteFileTreeItem*(self: Application, path: string, isDir: bool) {.raises: [].} =
  let parent = self.appWidget()
  let itemType = if isDir: "folder" else: "file"
  let clicked = QMessageBox.warning(
    parent,
    "Delete",
    "Delete this " & itemType & "?\n" & path,
    (MsgBox_Yes or MsgBox_Cancel),
    MsgBox_Cancel)
  if clicked != MsgBox_Yes:
    return

  try:
    if isDir:
      removeDir(path)
    else:
      removeFile(path)
    self.syncOpenBuffersAfterDelete(path, isDir)
    self.clearClipboardIfDeleted(path, isDir)
    self.refreshFileTree()
  except Exception as exc:
    self.showFileTreeError("Delete Failed", exc.msg)

proc createFileTreeFile*(self: Application, dir: string) {.raises: [].} =
  let name = self.promptFileTreeText("New File", "File name", "", "Create")
  if name.len == 0:
    return

  let validationError = validateFileTreeName(name)
  if validationError.len > 0:
    self.showFileTreeError("Create File Failed", validationError)
    return

  let path = dir / name
  if pathExistsAny(path):
    self.showFileTreeError("Create File Failed", "A file or folder with that name already exists.")
    return

  try:
    writeFile(path, "")
    self.refreshFileTree()
  except Exception as exc:
    self.showFileTreeError("Create File Failed", exc.msg)

proc createFileTreeFolder*(self: Application, dir: string) {.raises: [].} =
  let name = self.promptFileTreeText("New Folder", "Folder name", "", "Create")
  if name.len == 0:
    return

  let validationError = validateFileTreeName(name)
  if validationError.len > 0:
    self.showFileTreeError("Create Folder Failed", validationError)
    return

  let path = dir / name
  if pathExistsAny(path):
    self.showFileTreeError("Create Folder Failed", "A file or folder with that name already exists.")
    return

  try:
    createDir(path)
    self.refreshFileTree()
  except Exception as exc:
    self.showFileTreeError("Create Folder Failed", exc.msg)
