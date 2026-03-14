import std/[os, strutils]
import seaqt/[qprocess, qobject, qtcpsocket, qabstractsocket, qiodevice]

type
  Completion* = object
    name*: string
    symkind*: string
    signature*: string
    file*: string
    line*: int
    col*: int

  ClientState* = enum
    csIdle
    csStarting
    csReady
    csDead

  PendingQuery* = object
    request*: string
    isSug*: bool
    onResultSug*: proc(completions: seq[Completion]) {.raises: [].}
    onError*: proc(msg: string) {.raises: [].}

  NimSuggestClient* = ref object
    parentH*:      pointer
    projectFile*:  string
    port*:         int
    processH*:     pointer
    socketH*:      pointer
    state*:        ClientState
    pending*:      seq[PendingQuery]
    responseLines*: seq[string]
    portBuf*:      string
    responseBuf*:   string
    debug*:        bool

proc findNimbleEntry*(fromFile: string): string {.raises: [].} =
  try:
    var dir = fromFile.parentDir()
    var prev = ""
    while dir != prev:
      for kind, path in walkDir(dir):
        if kind == pcFile and path.endsWith(".nimble"):
          let content = readFile(path)
          for line in content.splitLines():
            let stripped = line.strip()
            if stripped.startsWith("bin"):
              let eq = stripped.find('=')
              if eq >= 0:
                let rhs = stripped[eq+1..^1].strip()
                let q1 = rhs.find('"')
                if q1 >= 0:
                  let q2 = rhs.find('"', q1+1)
                  if q2 > q1:
                    let binName = rhs[q1+1 ..< q2]
                    let candidate = dir / "src" / binName & ".nim"
                    if fileExists(candidate):
                      return candidate
          return fromFile
      prev = dir
      dir = dir.parentDir()
  except: discard
  return fromFile

proc parseSugResponse*(lines: seq[string]): seq[Completion] {.raises: [].} =
  for raw in lines:
    let ln = raw.strip()
    if ln.len == 0: continue
    let parts = ln.split('\t')
    if parts.len >= 7 and parts[0] == "sug":
      try:
        var c: Completion
        c.symkind = parts[1]
        c.name = parts[2]
        c.signature = parts[3]
        c.file = parts[4]
        c.line = parseInt(parts[5])
        c.col = parseInt(parts[6])
        result.add(c)
      except: discard

proc drainPending(client: NimSuggestClient, msg: string) {.raises: [].} =
  let q = client.pending
  client.pending = @[]
  for pq in q:
    try: pq.onError(msg) except: discard

proc log(client: NimSuggestClient, msg: string) {.raises: [].} =
  if client.debug:
    echo "[nimsuggest] " & msg

proc startNimSuggest*(client: NimSuggestClient) {.raises: [].}

proc onSocketConnected(client: NimSuggestClient) {.raises: [].}
proc onSocketReadyRead(client: NimSuggestClient) {.raises: [].}
proc onSocketDead(client: NimSuggestClient, msg: string) {.raises: [].}
proc sendFront*(client: NimSuggestClient) {.raises: [].}
proc handleResponse(client: NimSuggestClient) {.raises: [].}

template doStart(client: NimSuggestClient) =
  startNimSuggest(client)

proc onSocketConnected(client: NimSuggestClient) {.raises: [].} =
  client.state = csReady
  client.responseLines = @[]
  client.responseBuf = ""
  client.log("Socket connected, state=Ready")
  if client.pending.len > 0:
    client.sendFront()

proc onSocketReadyRead(client: NimSuggestClient) {.raises: [].} =
  if client.socketH == nil: return
  try:
    let io = QIODevice(h: client.socketH, owned: false)
    let bytes = io.readAll()
    if bytes.len > 0:
      var s = newString(bytes.len)
      for i in 0..<bytes.len: s[i] = char(bytes[i])
      client.responseBuf &= s
    while true:
      let nl = client.responseBuf.find('\n')
      if nl < 0: break
      let line = client.responseBuf[0 ..< nl].strip(chars={'\r', '\n', ' '})
      client.responseBuf = client.responseBuf[nl+1 .. ^1]
      if line.len == 0:
        client.handleResponse()
      else:
        client.responseLines.add(line)
  except: discard

proc onSocketDead(client: NimSuggestClient, msg: string) {.raises: [].} =
  client.log("Socket dead: " & msg & ", pending: " & $client.pending.len)
  if client.state == csIdle: return
  let hadPending = client.pending.len > 0
  client.state = csDead
  if hadPending:
    client.drainPending(msg)
  client.responseLines = @[]
  client.responseBuf = ""
  if hadPending:
    doStart(client)

proc sendFront*(client: NimSuggestClient) {.raises: [].} =
  if client.pending.len == 0: return
  if client.socketH == nil or client.state != csReady:
    client.log("Socket not ready, restarting")
    doStart(client)
    return
  try:
    let req = client.pending[0].request
    client.log("Sending: " & req.strip())
    let io = QIODevice(h: client.socketH, owned: false)
    discard io.write(req.cstring)
  except: discard

proc handleResponse(client: NimSuggestClient) {.raises: [].} =
  if client.pending.len == 0:
    client.responseLines = @[]
    return
  let pq = client.pending[0]
  client.pending.delete(0)
  client.log("Got " & $client.responseLines.len & " response lines")
  for i, line in client.responseLines:
    if i < 5:
      client.log("  Response line: " & line)
  if pq.isSug:
    let completions = parseSugResponse(client.responseLines)
    client.responseLines = @[]
    client.log("Parsed " & $completions.len & " completions")
    try: pq.onResultSug(completions) except: discard
  else:
    client.log("Calling def callback")
    try: pq.onResultSug(@[]) except: discard
    client.responseLines = @[]
  # Check if socket is still connected - nimsuggest closes after each request
  if client.socketH != nil:
    let sock = QAbstractSocket(h: client.socketH, owned: false)
    if sock.state() != cint(3):  # ConnectedState
      client.log("Socket closed by server after response")
      client.socketH = nil
      client.state = csIdle

proc onProcessPortOutput(client: NimSuggestClient) {.raises: [].} =
  if client.processH == nil: return
  if client.port > 0: return
  try:
    let proc2 = QProcess(h: client.processH, owned: false)
    let bytes = proc2.readAllStandardOutput()
    if bytes.len > 0:
      var s = newString(bytes.len)
      for i in 0..<bytes.len: s[i] = char(bytes[i])
      client.portBuf &= s
    let nl = client.portBuf.find('\n')
    if nl < 0: return
    let portStr = client.portBuf[0 ..< nl].strip()
    let p = try: parseInt(portStr) except: 0
    if p <= 0 or p > 65535:
      client.onSocketDead("invalid port: " & portStr)
      return
    client.port = p
    client.log("Got port: " & $p)
    if client.socketH == nil: return
    let sock = QTcpSocket(h: client.socketH, owned: false)
    let sockH = client.socketH
    let clientRef = client
    sock.connectToHost("127.0.0.1", cushort(p), cint(3), cint(0))
    QAbstractSocket(h: sockH, owned: false).onConnected do() {.raises: [].}:
      clientRef.onSocketConnected()
    QIODevice(h: sockH, owned: false).onReadyRead do() {.raises: [].}:
      clientRef.onSocketReadyRead()
    QAbstractSocket(h: sockH, owned: false).onDisconnected do() {.raises: [].}:
      if clientRef.state != csIdle and clientRef.pending.len > 0:
        clientRef.socketH = nil
        clientRef.onSocketDead("socket disconnected")
    QAbstractSocket(h: sockH, owned: false).onErrorOccurred do(err: cint) {.raises: [].}:
      if clientRef.state != csIdle and clientRef.pending.len > 0:
        clientRef.socketH = nil
        clientRef.onSocketDead("socket error: " & $err)
  except: discard

proc kill*(client: NimSuggestClient) {.raises: [].} =
  let prevState = client.state
  client.state = csIdle
  client.drainPending("killed")
  client.responseLines = @[]
  client.responseBuf = ""
  client.portBuf = ""
  client.port = 0
  if client.socketH != nil:
    try:
      QAbstractSocket(h: client.socketH, owned: false).disconnectFromHost()
      QAbstractSocket(h: client.socketH, owned: false).close()
    except: discard
    client.socketH = nil
  if client.processH != nil:
    try:
      QProcess(h: client.processH, owned: false).kill()
      discard QProcess(h: client.processH, owned: false).waitForFinished(cint 2000)
    except: discard
    client.processH = nil
  discard prevState

proc startNimSuggest*(client: NimSuggestClient) {.raises: [].} =
  let prevState = client.state
  client.state = csIdle
  if client.socketH != nil:
    try:
      QAbstractSocket(h: client.socketH, owned: false).disconnectFromHost()
      QAbstractSocket(h: client.socketH, owned: false).close()
    except: discard
    client.socketH = nil
  if client.processH != nil:
    try:
      QProcess(h: client.processH, owned: false).kill()
      discard QProcess(h: client.processH, owned: false).waitForFinished(cint 2000)
    except: discard
    client.processH = nil
  client.port = 0
  client.portBuf = ""
  client.responseLines = @[]
  client.responseBuf = ""
  discard prevState

  client.state = csStarting
  client.log("Starting nimsuggest for: " & client.projectFile)

  try:
    let parent = QObject(h: client.parentH, owned: false)
    var sock = QTcpSocket.create(parent)
    sock.owned = false
    client.socketH = sock.h

    var process = QProcess.create(parent)
    process.owned = false
    let processH = process.h
    client.processH = processH
    let clientRef = client

    process.onReadyReadStandardOutput do() {.raises: [].}:
      clientRef.onProcessPortOutput()

    process.onFinished do(exitCode: cint) {.raises: [].}:
      if clientRef.state != csIdle:
        clientRef.processH = nil
        clientRef.onSocketDead("process exited (code " & $exitCode & ")")

    let pid = try: $getCurrentProcessId() except: "0"
    process.start("nimsuggest",
      @["--autobind",
        "--clientProcessId:" & pid,
        client.projectFile])
  except:
    client.state = csDead
    let errMsg = "Failed to start: " & getCurrentExceptionMsg()
    client.log(errMsg)
    client.drainPending(errMsg)

proc restart*(client: NimSuggestClient) {.raises: [].} =
  client.drainPending("restarting")
  doStart(client)

proc new*(T: typedesc[NimSuggestClient],
          parentH: pointer,
          projectFile: string,
          debug: bool = false): NimSuggestClient {.raises: [].} =
  T(parentH: parentH, projectFile: projectFile, state: csIdle, debug: debug)

proc querySug*(client: NimSuggestClient,
               filePath: string,
               line: int,
               col: int,
               onResult: proc(completions: seq[Completion]) {.raises: [].},
               onError: proc(msg: string) {.raises: [].}) {.raises: [].} =
  let request = "sug " & filePath & ":" & $line & ":" & $col & "\n"
  client.log("querySug: " & request.strip())

  if client.pending.len > 0:
    let old = client.pending[0]
    client.pending = @[]
    client.responseLines = @[]
    try: old.onError("cancelled") except: discard

  let pq = PendingQuery(request: request, isSug: true, onResultSug: onResult, onError: onError)

  case client.state
  of csReady:
    client.pending.add(pq)
    client.sendFront()
  of csStarting:
    client.pending.add(pq)
  of csIdle:
    client.pending.add(pq)
    doStart(client)
  of csDead:
    client.pending.add(pq)
    doStart(client)

proc restartClient*(client: NimSuggestClient) {.raises: [].} =
  startNimSuggest(client)
