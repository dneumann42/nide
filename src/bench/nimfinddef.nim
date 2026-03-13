import std/[os, strutils]
import seaqt/[qprocess, qobject, qtcpsocket, qabstractsocket, qiodevice]

type
  Definition* = object
    file*: string
    line*: int
    col*: int
    qpath*: string
    symkind*: string

  ClientState = enum
    csIdle       # never started
    csStarting   # process launched, waiting for port + TCP connect
    csReady      # TCP connected, can send queries
    csDead       # process or socket died unexpectedly

  PendingQuery = object
    request:  string
    onResult: proc(def: Definition) {.raises: [].}
    onError:  proc(msg: string) {.raises: [].}

  NimSuggestClient* = ref object
    parentH:      pointer
    projectFile:  string
    port:         int
    processH:     pointer   # QProcess (owned: false)
    socketH:      pointer   # QTcpSocket (owned: false)
    state:        ClientState
    pending:      seq[PendingQuery]
    responseLines: seq[string]
    portBuf:      string
    responseBuf:  string

# ---------------------------------------------------------------------------
# Project file discovery
# ---------------------------------------------------------------------------

proc findNimbleEntry*(fromFile: string): string {.raises: [].} =
  ## Walk up from fromFile's directory looking for a .nimble file.
  ## If found and it declares a bin, return src/<binname>.nim relative to
  ## the nimble dir. Otherwise return fromFile unchanged.
  try:
    var dir = fromFile.parentDir()
    var prev = ""
    while dir != prev:
      for kind, path in walkDir(dir):
        if kind == pcFile and path.endsWith(".nimble"):
          # Found a nimble file — try to extract bin
          let content = readFile(path)
          for line in content.splitLines():
            let stripped = line.strip()
            # match: bin = @["foo"] or bin = @["foo", "bar"]
            if stripped.startsWith("bin"):
              let eq = stripped.find('=')
              if eq >= 0:
                let rhs = stripped[eq+1..^1].strip()
                # extract first quoted name
                let q1 = rhs.find('"')
                if q1 >= 0:
                  let q2 = rhs.find('"', q1+1)
                  if q2 > q1:
                    let binName = rhs[q1+1 ..< q2]
                    let candidate = dir / "src" / binName & ".nim"
                    if fileExists(candidate):
                      return candidate
          # Nimble found but no usable bin — use nimble dir as anchor
          # and fall through to return fromFile
          return fromFile
      prev = dir
      dir = dir.parentDir()
  except: discard
  return fromFile

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

proc parseResponse(lines: seq[string]): (bool, Definition) {.raises: [].} =
  for raw in lines:
    let ln = raw.strip()
    if ln.len == 0: continue
    let parts = ln.split('\t')
    if parts.len >= 7:
      try:
        if parts[0] == "def" or parts[0] == "sug":
          var d: Definition
          d.file    = parts[4]
          d.line    = parseInt(parts[5])
          d.col     = parseInt(parts[6])   # nimsuggest uses 0-based cols
          d.symkind = parts[1]
          d.qpath   = parts[2]
          return (true, d)
      except: discard
  return (false, Definition())

proc drainPending(client: NimSuggestClient, msg: string) {.raises: [].} =
  let q = client.pending
  client.pending = @[]
  for pq in q:
    try: pq.onError(msg) except: discard

proc sendFront(client: NimSuggestClient) {.raises: [].} =
  ## Send the first pending request over the socket.
  if client.pending.len == 0: return
  if client.socketH == nil: return
  try:
    let req = client.pending[0].request
    let io = QIODevice(h: client.socketH, owned: false)
    discard io.write(req.cstring)
  except: discard

proc handleResponse(client: NimSuggestClient) {.raises: [].} =
  ## Called when a complete nimsuggest response (terminated by empty line) arrives.
  if client.pending.len == 0:
    client.responseLines = @[]
    return
  let pq = client.pending[0]
  client.pending.delete(0)
  let (ok, def) = parseResponse(client.responseLines)
  client.responseLines = @[]
  if ok:
    try: pq.onResult(def) except: discard
  else:
    try: pq.onError("Definition not found") except: discard
  # Send next queued request if any
  if client.pending.len > 0:
    client.sendFront()

# ---------------------------------------------------------------------------
# Start / Kill / Restart
# ---------------------------------------------------------------------------

proc start*(client: NimSuggestClient) {.raises: [].}

proc onSocketConnected(client: NimSuggestClient) {.raises: [].} =
  client.state = csReady
  client.responseLines = @[]
  client.responseBuf = ""
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
    # Process complete lines
    while true:
      let nl = client.responseBuf.find('\n')
      if nl < 0: break
      let line = client.responseBuf[0 ..< nl].strip(chars={'\r', '\n', ' '})
      client.responseBuf = client.responseBuf[nl+1 .. ^1]
      if line.len == 0:
        # Empty line = end of response
        client.handleResponse()
      else:
        client.responseLines.add(line)
  except: discard

proc onSocketDead(client: NimSuggestClient, msg: string) {.raises: [].} =
  if client.state == csIdle: return   # deliberate kill, no restart
  client.state = csDead
  client.drainPending(msg)
  client.responseLines = @[]
  client.responseBuf = ""
  # Restart automatically
  client.start()

proc onProcessPortOutput(client: NimSuggestClient) {.raises: [].} =
  ## Called when nimsuggest writes to stdout — we expect a single port number line.
  if client.processH == nil: return
  if client.port > 0: return  # already have port
  try:
    let proc2 = QProcess(h: client.processH, owned: false)
    let bytes = proc2.readAllStandardOutput()
    if bytes.len > 0:
      var s = newString(bytes.len)
      for i in 0..<bytes.len: s[i] = char(bytes[i])
      client.portBuf &= s
    # Check if we have a complete line
    let nl = client.portBuf.find('\n')
    if nl < 0: return
    let portStr = client.portBuf[0 ..< nl].strip()
    let p = try: parseInt(portStr) except: 0
    if p <= 0 or p > 65535:
      client.onSocketDead("nimsuggest gave invalid port: " & portStr)
      return
    client.port = p
    # Now connect the TCP socket
    if client.socketH == nil: return
    let sock = QTcpSocket(h: client.socketH, owned: false)
    let sockH = client.socketH
    let clientRef = client
    sock.connectToHost("127.0.0.1", cushort(p), cint(3), cint(0))
    # onConnected
    QAbstractSocket(h: sockH, owned: false).onConnected do() {.raises: [].}:
      clientRef.onSocketConnected()
    # onReadyRead
    QIODevice(h: sockH, owned: false).onReadyRead do() {.raises: [].}:
      clientRef.onSocketReadyRead()
    # onDisconnected
    QAbstractSocket(h: sockH, owned: false).onDisconnected do() {.raises: [].}:
      if clientRef.state != csIdle:
        clientRef.socketH = nil
        clientRef.onSocketDead("nimsuggest socket disconnected")
    # onErrorOccurred
    QAbstractSocket(h: sockH, owned: false).onErrorOccurred do(err: cint) {.raises: [].}:
      if clientRef.state != csIdle:
        clientRef.socketH = nil
        clientRef.onSocketDead("nimsuggest socket error: " & $err)
  except: discard

proc kill*(client: NimSuggestClient) {.raises: [].} =
  ## Cleanly shut down nimsuggest. Does not restart.
  let prevState = client.state
  client.state = csIdle   # prevent onFinished/onDisconnected from restarting
  client.drainPending("nimsuggest killed")
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

proc start*(client: NimSuggestClient) {.raises: [].} =
  ## Start (or restart) nimsuggest. Kills any existing instance first.
  # Kill without the restart-prevention side-effect: set csIdle first so
  # any in-flight signals won't trigger another restart, then re-enter.
  let prevState = client.state
  client.state = csIdle
  # Clean up old socket
  if client.socketH != nil:
    try:
      QAbstractSocket(h: client.socketH, owned: false).disconnectFromHost()
      QAbstractSocket(h: client.socketH, owned: false).close()
    except: discard
    client.socketH = nil
  # Clean up old process
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

  try:
    let parent = QObject(h: client.parentH, owned: false)

    # Create socket first (we attach signals after we learn the port)
    var sock = QTcpSocket.create(parent)
    sock.owned = false
    client.socketH = sock.h

    # Create process
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
        clientRef.onSocketDead("nimsuggest process exited (code " & $exitCode & ")")

    let pid = try: $getCurrentProcessId() except: "0"
    process.start("nimsuggest",
      @["--autobind",
        "--clientProcessId:" & pid,
        client.projectFile])
  except:
    client.state = csDead
    client.drainPending("Failed to start nimsuggest: " & getCurrentExceptionMsg())

proc restart*(client: NimSuggestClient) {.raises: [].} =
  ## Manually restart nimsuggest (e.g. from toolbar).
  client.drainPending("nimsuggest restarting")
  client.start()

# ---------------------------------------------------------------------------
# Public query API
# ---------------------------------------------------------------------------

proc new*(T: typedesc[NimSuggestClient],
          parentH: pointer,
          projectFile: string): NimSuggestClient {.raises: [].} =
  T(parentH: parentH, projectFile: projectFile, state: csIdle)

proc queryDef*(client: NimSuggestClient,
               filePath: string,
               line: int,
               col: int,
               onResult: proc(def: Definition) {.raises: [].},
               onError:  proc(msg: string) {.raises: [].}) {.raises: [].} =
  let request = "def " & filePath & ":" & $line & ":" & $col & "\n"

  # Cancel any existing in-flight/pending query (user wants latest)
  if client.pending.len > 0:
    let old = client.pending[0]
    client.pending = @[]
    client.responseLines = @[]
    try: old.onError("cancelled") except: discard

  let pq = PendingQuery(request: request, onResult: onResult, onError: onError)

  case client.state
  of csReady:
    client.pending.add(pq)
    client.sendFront()
  of csStarting:
    client.pending.add(pq)   # will be sent on onConnected
  of csIdle:
    client.pending.add(pq)
    client.start()
  of csDead:
    client.pending.add(pq)
    client.start()           # restart will flush pending on connect
