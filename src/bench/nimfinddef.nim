import std/[os, strutils]
import seaqt/[qprocess, qobject]

type
  Definition* = object
    file*: string
    line*: int
    col*: int
    qpath*: string
    symkind*: string

proc runNimFindDef*(
    parentH:  pointer,
    filePath: string,
    line: int,
    col: int,
    onResult: proc(def: Definition) {.raises: [].},
    onError: proc(msg: string) {.raises: [].}
) {.raises: [].} =
  var serverProcess: pointer = nil
  
  try:
    let absPath = filePath
    echo "DEBUG: filePath=", filePath, " line=", line, " col=", col
    let cmd = "printf 'def %s:%s:%s\\n' '" & absPath & "' " & $line & " " & $col & " | nimsuggest --stdin --refresh '" & absPath & "'"
    echo "DEBUG: cmd=", cmd
    let shellCmd = "/bin/bash -c " & quoteShell(cmd)
    
    var process = QProcess.create(QObject(h: parentH, owned: false))
    process.owned = false
    let processH = process.h
    serverProcess = processH

    process.setProcessChannelMode(cint 1)
    process.setWorkingDirectory(filePath.parentDir())
    
    process.start("bash", @["-c", cmd])

    var output = ""

    process.onReadyReadStandardOutput do() {.raises: [].}:
      try:
        let bytes = QProcess(h: processH, owned: false).readAllStandardOutput()
        if bytes.len > 0:
          var s = newString(bytes.len)
          for i in 0..<bytes.len: s[i] = char(bytes[i])
          output &= s
      except: discard

    process.onReadyReadStandardError do() {.raises: [].}:
      try:
        let bytes = QProcess(h: processH, owned: false).readAllStandardError()
        if bytes.len > 0:
          var s = newString(bytes.len)
          for i in 0..<bytes.len: s[i] = char(bytes[i])
          output &= s
      except: discard

    discard process.waitForFinished(15000)
    
    if output.len == 0:
      onError("No output from nimsuggest")
      return
    
    var found = false
    var def: Definition
    
    for rawLine in output.splitLines():
      let line = rawLine.strip()
      if line.len == 0: continue
      if line.contains("usage"): continue
      if line.contains("type '"): continue
      if line.contains("quit"): continue
      if line.startsWith("debug"): continue
      if line.startsWith("terse"): continue
      
      let parts = line.split('\t')
      if parts.len >= 7:
        try:
          if parts[0] == "def" or parts[0] == "sug":
            def.file = parts[4]
            def.line = parseInt(parts[5])
            def.col = parseInt(parts[6]) + 1
            def.symkind = parts[1]
            def.qpath = parts[2]
            found = true
            break
        except:
          continue
    
    if found:
      onResult(def)
    else:
      onError("Definition not found")
    
    if serverProcess != nil:
      try:
        QProcess(h: serverProcess, owned: false).kill()
      except:
        discard

  except:
    onError("Failed to start nimsuggest: " & getCurrentExceptionMsg())
    if serverProcess != nil:
      try:
        QProcess(h: serverProcess, owned: false).kill()
      except:
        discard
