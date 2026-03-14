import std/[strutils]

type
  ParsedSymbol* = object
    name*: string
    module*: string
    signature*: string

proc findMatchingBacktick(s: string; start: int): int =
  var depth = 0
  var i = start
  while i < s.len:
    if s[i] == '`':
      if i + 1 < s.len:
        if s[i + 1] == '$':
          inc i
        elif s[i + 1] == '`':
          inc i
      if i < s.len:
        inc depth
        if depth == 1:
          return i
    inc i
  return -1

proc parseIndexHtml*(html: string): seq[ParsedSymbol] {.raises: [].} =
  result = @[]
  try:
    let lines = html.splitLines
    var currentName = ""
    
    for i, line in lines:
      let stripped = line.strip()
      if stripped.len == 0:
        continue
      
      if stripped.startsWith("`") and stripped.endsWith("`:"):
        let endQuote = stripped.find("`", 1)
        if endQuote > 1:
          currentName = stripped[1 ..< endQuote]
          continue
      
      if currentName.len > 0 and stripped.contains(": "):
        let colonPos = stripped.find(": ")
        if colonPos > 0:
          let moduleName = stripped[0 ..< colonPos]
          let sigStart = colonPos + 2
          if sigStart < stripped.len and stripped[sigStart] == '`':
            let sigEnd = findMatchingBacktick(stripped, sigStart + 1)
            if sigEnd > sigStart:
              var signature = stripped[(sigStart + 1) ..< sigEnd]
              signature = signature.replace("`$`", "$").replace("``", "`")
              result.add(ParsedSymbol(
                name: currentName,
                module: moduleName,
                signature: signature
              ))
  except:
    echo "[nimindexparse] Parse error: " & getCurrentExceptionMsg()
