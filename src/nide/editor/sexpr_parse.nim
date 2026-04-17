import std/[sequtils, strutils]
import nide/editor/sexpr_model

type
  Parser = object
    src: string
    pos: int
    doc: SExprDocument

proc atEnd(p: Parser): bool {.raises: [].} = p.pos >= p.src.len
proc peek(p: Parser): char {.raises: [].} = (if p.atEnd(): '\0' else: p.src[p.pos])
proc advance(p: var Parser): char {.raises: [].} =
  result = p.peek()
  if not p.atEnd():
    inc p.pos

proc skipTrivia(p: var Parser) {.raises: [].} =
  while not p.atEnd():
    if p.peek() in {' ', '\t', '\r', '\n'}:
      discard p.advance()
    elif p.peek() == ';':
      while not p.atEnd() and p.peek() != '\n':
        discard p.advance()
    else:
      break

proc parseStringAtom(p: var Parser): SExprNode {.raises: [].} =
  var text = ""
  text.add p.advance()
  var escaped = false
  while not p.atEnd():
    let ch = p.advance()
    text.add ch
    if escaped:
      escaped = false
    elif ch == '\\':
      escaped = true
    elif ch == '"':
      break
  p.doc.atom(text)

proc parseAtom(p: var Parser): SExprNode {.raises: [].} =
  var text = ""
  while not p.atEnd():
    let ch = p.peek()
    if ch in {' ', '\t', '\r', '\n', '(', ')', ';'}:
      break
    text.add p.advance()
  if text.len == 0:
    text.add p.advance()
  p.doc.atom(text)

proc parseNode(p: var Parser): SExprNode {.raises: [].}

proc parseList(p: var Parser): SExprNode {.raises: [].} =
  result = p.doc.list()
  discard p.advance()
  while not p.atEnd():
    p.skipTrivia()
    if p.atEnd():
      break
    if p.peek() == ')':
      discard p.advance()
      break
    let child = p.parseNode()
    p.doc.addChild(result, child, dirty = false)

proc parseNode(p: var Parser): SExprNode {.raises: [].} =
  p.skipTrivia()
  if p.atEnd():
    return p.doc.atom("")
  case p.peek()
  of '(':
    p.parseList()
  of ')':
    discard p.advance()
    p.doc.atom(")")
  of '"':
    p.parseStringAtom()
  else:
    p.parseAtom()

proc parseSExpr*(source: string): SExprDocument {.raises: [].} =
  result = newSExprDocument()
  var parser = Parser(src: source, doc: result)
  while not parser.atEnd():
    parser.skipTrivia()
    if parser.atEnd():
      break
    let node = parser.parseNode()
    result.addChild(result.root, node, dirty = false)
  if result.root.children.len > 0:
    result.selected = result.root.children[0].id
  result.dirty = false

proc quoteAtom(text: string): string {.raises: [].} =
  if text.len == 0:
    return "\"\""
  if text.len >= 2 and text[0] == '"' and text[^1] == '"':
    return text
  for ch in text:
    if ch in {' ', '\t', '\r', '\n', '(', ')', ';'}:
      var escaped = "\""
      for c in text:
        case c
        of '\\': escaped.add "\\\\"
        of '"': escaped.add "\\\""
        of '\n': escaped.add "\\n"
        of '\r': escaped.add "\\r"
        of '\t': escaped.add "\\t"
        else: escaped.add c
      escaped.add "\""
      return escaped
  text

proc serializeNode*(node: SExprNode): string {.raises: [].} =
  if node == nil:
    return ""
  case node.kind
  of senAtom:
    quoteAtom(node.text)
  of senList:
    if node.children.len == 0:
      "()"
    else:
      "(" & node.children.mapIt(serializeNode(it)).join(" ") & ")"

proc serializeSExpr*(doc: SExprDocument): string {.raises: [].} =
  if doc == nil or doc.root == nil:
    return ""
  if doc.root.children.len == 0:
    return "()\n"
  doc.root.children.mapIt(serializeNode(it)).join("\n") & "\n"
