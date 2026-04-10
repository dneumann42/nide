import std/[httpclient, os, times]
import nide/helpers/debuglog

const
  IndexUrl* = "https://nim-lang.org/docs/theindex.html"
  CacheDir* = ".config/nide"
  CacheFileName* = "nimindex.html"
  CacheMaxAge* = 7 * 24 * 60 * 60  # 7 days in seconds

proc getCachePath*(): string =
  let home = getHomeDir()
  let configDir = home / CacheDir
  result = configDir / CacheFileName

proc cacheNeedsRefresh*(path: string): bool =
  if not fileExists(path):
    return true
  let fileInfo = getFileInfo(path)
  let fileTime = fileInfo.lastWriteTime
  let now = getTime()
  let age = now - fileTime
  return age.inSeconds > CacheMaxAge

proc downloadIndex*(): string {.raises: [].} =
  try:
    logInfo("nimindexfetch: Downloading index from: ", IndexUrl)
    let client = newHttpClient()
    defer: client.close()
    let content = client.getContent(IndexUrl)
    logInfo("nimindexfetch: Downloaded ", content.len, " bytes")
    return content
  except:  # newHttpClient raises Exception via SSL init
    logError("nimindexfetch: Download error: ", getCurrentExceptionMsg())
    return ""

proc saveIndexToCache*(content: string): bool {.raises: [].} =
  try:
    let cachePath = getCachePath()
    let cacheDir = cachePath.parentDir()
    if not dirExists(cacheDir):
      createDir(cacheDir)
    writeFile(cachePath, content)
    logInfo("nimindexfetch: Saved index to: ", cachePath)
    return true
  except CatchableError:
    logError("nimindexfetch: Save error: ", getCurrentExceptionMsg())
    return false

proc loadIndexFromCache*(): string {.raises: [].} =
  try:
    let cachePath = getCachePath()
    if fileExists(cachePath):
      logInfo("nimindexfetch: Loading index from cache: ", cachePath)
      return readFile(cachePath)
  except CatchableError:
    logError("nimindexfetch: Load error: ", getCurrentExceptionMsg())
  return ""

proc getIndexContent*(): string {.raises: [].} =
  let cachePath = getCachePath()
  var needsRefresh = true
  try:
    needsRefresh = cacheNeedsRefresh(cachePath)
  except CatchableError:
    needsRefresh = true

  if needsRefresh:
    logInfo("nimindexfetch: Cache stale or missing, downloading fresh index")
    let content = downloadIndex()
    if content.len > 0:
      discard saveIndexToCache(content)
      return content
    else:
      logWarn("nimindexfetch: Download failed, trying cache")
      return loadIndexFromCache()
  else:
    return loadIndexFromCache()

proc forceRefreshCache*(): string {.raises: [].} =
  let content = downloadIndex()
  if content.len > 0:
    discard saveIndexToCache(content)
  return content
