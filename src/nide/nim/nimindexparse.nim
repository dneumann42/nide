import std/[xmlparser, xmltree, strutils, re]
import nide/helpers/debuglog

type
  ParsedSymbol* = object
    name*: string
    module*: string
    signature*: string

proc fixBrokenHtml(html: string): string =
  result = html
  
  result = result.replace(re"<script[^>]*>.*?</script>", "")
  
  let selfClosing = ["link", "meta", "br", "hr", "input", "img", "area", "base", "col", "embed", "source", "track", "wbr", "param"]
  for tag in selfClosing:
    result = result.replace("<" & tag & " ", "<" & tag & " /> ")
    result = result.replace("<" & tag & ">", "<" & tag & " />")

proc parseIndexHtml*(html: string): seq[ParsedSymbol] {.raises: [].} =
  result = @[]
  try:
    let fixedHtml = fixBrokenHtml(html)
    let wrapped = "<root>" & fixedHtml & "</root>"
    let xml = parseXml(wrapped)
    var currentName = ""
    var nodesToProcess: seq[XmlNode] = @[]
    
    for i in 0..<xml.len:
      nodesToProcess.add(xml[i])
    
    while nodesToProcess.len > 0:
      let node = nodesToProcess[0]
      nodesToProcess.delete(0)
      if node.kind == xnElement:
        if node.tag == "dt":
          proc findSpan(n: XmlNode): string =
            for i in 0..<n.len:
              let child = n[i]
              if child.kind == xnElement:
                if child.tag == "span":
                  return child.innerText()
                let nested = findSpan(child)
                if nested.len > 0:
                  return nested
            return ""
          let spanText = findSpan(node)
          if spanText.len > 0 and spanText[^1] == ':':
            currentName = spanText[0..^2]
        elif currentName.len > 0 and node.tag == "dd":
          for i in 0..<node.len:
            let child = node[i]
            if child.kind == xnElement and child.tag == "ul":
              for j in 0..<child.len:
                let li = child[j]
                if li.kind == xnElement and li.tag == "li":
                  for k in 0..<li.len:
                    let a = li[k]
                    if a.kind == xnElement and a.tag == "a":
                      let tagAttr = a.attr("data-doc-search-tag")
                      let tagStr = $tagAttr
                      let colonPos = strutils.find(tagStr, ":")
                      if colonPos >= 0:
                        let moduleName = tagStr[0..<colonPos].strip()
                        let signature = tagStr[colonPos+1..^1].strip()
                        if moduleName.len > 0 and signature.len > 0:
                          result.add(ParsedSymbol(
                            name: currentName,
                            module: moduleName,
                            signature: signature
                          ))
        for i in 0..<node.len:
          nodesToProcess.add(node[i])
  except:  # parseXml raises Exception
    logError("nimindexparse: Parse error: ", getCurrentExceptionMsg())
