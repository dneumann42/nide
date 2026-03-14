import std/[strutils]
import seaqt/[qprocess, qobject, qtcpsocket, qabstractsocket, qiodevice]
import bench/nimsuggest

type
  Definition* = object
    file*: string
    line*: int
    col*: int
    qpath*: string
    symkind*: string

proc parseDefResponse*(lines: seq[string]): (bool, Definition) {.raises: [].} =
  for raw in lines:
    let ln = raw.strip()
    if ln.len == 0: continue
    let parts = ln.split('\t')
    if parts.len >= 7 and (parts[0] == "def" or parts[0] == "sug"):
      try:
        var d: Definition
        d.file    = parts[4]
        d.line    = parseInt(parts[5])
        d.col     = parseInt(parts[6])
        d.symkind = parts[1]
        d.qpath   = parts[2]
        return (true, d)
      except: discard
  return (false, Definition())

proc queryDef*(client: NimSuggestClient,
               filePath: string,
               line: int,
               col: int,
               onResult: proc(def: Definition) {.raises: [].},
               onError: proc(msg: string) {.raises: [].}) {.raises: [].} =
  let request = "def " & filePath & ":" & $line & ":" & $col & "\n"

  let onSug = proc(completions: seq[Completion]) {.raises: [].} =
    let (ok, def) = parseDefResponse(client.responseLines)
    if ok:
      try: onResult(def) except: discard
    else:
      try: onError("Definition not found") except: discard

  let pq = PendingQuery(request: request, isSug: false, onResultSug: onSug, onError: onError)

  case client.state
  of csReady:
    client.pending.add(pq)
    client.sendFront()
  of csStarting:
    client.pending.add(pq)
  of csIdle:
    client.pending.add(pq)
    startNimSuggest(client)
  of csDead:
    client.pending.add(pq)
    startNimSuggest(client)
