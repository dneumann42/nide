import std/algorithm

type
  SExprNodeId* = int

  SExprNodeKind* = enum
    senAtom
    senList

  SExprNode* = ref object
    id*: SExprNodeId
    kind*: SExprNodeKind
    text*: string
    parent*: SExprNode
    children*: seq[SExprNode]

  SExprDocument* = ref object
    root*: SExprNode
    selected*: SExprNodeId
    nextId*: SExprNodeId
    dirty*: bool

proc newSExprDocument*(): SExprDocument

proc newNode(doc: SExprDocument, kind: SExprNodeKind, text = ""): SExprNode =
  result = SExprNode(id: doc.nextId, kind: kind, text: text)
  inc doc.nextId

proc newSExprDocument*(): SExprDocument =
  result = SExprDocument(nextId: 1)
  result.root = result.newNode(senList)
  result.selected = result.root.id

proc markDirty(doc: SExprDocument) =
  if doc != nil:
    doc.dirty = true

proc addChild*(doc: SExprDocument, parent: SExprNode, child: SExprNode,
               index = -1, dirty = true) =
  if doc == nil or parent == nil or child == nil or parent.kind != senList:
    return
  child.parent = parent
  let idx = if index < 0 or index > parent.children.len: parent.children.len else: index
  parent.children.insert(child, idx)
  if dirty: doc.markDirty()

proc atom*(doc: SExprDocument, text: string): SExprNode =
  doc.newNode(senAtom, text)

proc list*(doc: SExprDocument): SExprNode =
  doc.newNode(senList)

proc cloneInto*(doc: SExprDocument, node: SExprNode): SExprNode =
  if doc == nil or node == nil:
    return nil
  result =
    case node.kind
    of senAtom: doc.atom(node.text)
    of senList: doc.list()
  for child in node.children:
    doc.addChild(result, doc.cloneInto(child), dirty = false)

proc findNode*(node: SExprNode, id: SExprNodeId): SExprNode =
  if node == nil:
    return nil
  if node.id == id:
    return node
  for child in node.children:
    let found = findNode(child, id)
    if found != nil:
      return found

proc selectedNode*(doc: SExprDocument): SExprNode =
  if doc == nil:
    return nil
  findNode(doc.root, doc.selected)

proc indexInParent*(node: SExprNode): int =
  if node == nil or node.parent == nil:
    return -1
  for i, child in node.parent.children:
    if child == node:
      return i
  -1

proc containsNode*(root, candidate: SExprNode): bool =
  if root == nil or candidate == nil:
    return false
  if root == candidate:
    return true
  for child in root.children:
    if containsNode(child, candidate):
      return true
  false

proc removeFromParent(node: SExprNode): int =
  result = node.indexInParent()
  if result >= 0:
    node.parent.children.delete(result)
    node.parent = nil

proc select*(doc: SExprDocument, node: SExprNode) =
  if doc != nil and node != nil:
    doc.selected = node.id

proc selectId*(doc: SExprDocument, id: SExprNodeId) =
  if doc != nil and findNode(doc.root, id) != nil:
    doc.selected = id

proc appendAtom*(doc: SExprDocument, parent: SExprNode, text = "atom"): SExprNode =
  result = doc.atom(text)
  doc.addChild(parent, result)
  doc.select(result)

proc appendList*(doc: SExprDocument, parent: SExprNode): SExprNode =
  result = doc.list()
  doc.addChild(parent, result)
  doc.select(result)

proc insertAfterSelected*(doc: SExprDocument, node: SExprNode) =
  let selected = doc.selectedNode()
  if selected == nil or selected.parent == nil:
    doc.addChild(doc.root, node)
  else:
    doc.addChild(selected.parent, node, selected.indexInParent() + 1)
  doc.select(node)

proc deleteSelected*(doc: SExprDocument): bool =
  let node = doc.selectedNode()
  if node == nil or node == doc.root:
    return false
  let parent = node.parent
  let idx = node.removeFromParent()
  if parent.children.len == 0:
    doc.select(parent)
  elif idx < parent.children.len:
    doc.select(parent.children[idx])
  else:
    doc.select(parent.children[^1])
  doc.markDirty()
  true

proc wrapSelected*(doc: SExprDocument): bool =
  let node = doc.selectedNode()
  if node == nil or node == doc.root or node.parent == nil:
    return false
  let parent = node.parent
  let idx = node.indexInParent()
  discard node.removeFromParent()
  let wrapper = doc.list()
  doc.addChild(parent, wrapper, idx, dirty = false)
  doc.addChild(wrapper, node, dirty = false)
  doc.select(wrapper)
  doc.markDirty()
  true

proc liftSelected*(doc: SExprDocument): bool =
  let node = doc.selectedNode()
  if node == nil or node == doc.root or node.parent == nil or node.parent.parent == nil:
    return false
  let oldParent = node.parent
  let grand = oldParent.parent
  let parentIdx = oldParent.indexInParent()
  discard node.removeFromParent()
  doc.addChild(grand, node, parentIdx + 1, dirty = false)
  doc.select(node)
  doc.markDirty()
  true

proc moveSelectedBy*(doc: SExprDocument, delta: int): bool =
  let node = doc.selectedNode()
  if node == nil or node.parent == nil:
    return false
  let idx = node.indexInParent()
  let target = idx + delta
  if idx < 0 or target < 0 or target >= node.parent.children.len:
    return false
  swap(node.parent.children[idx], node.parent.children[target])
  doc.markDirty()
  true

proc reparent*(doc: SExprDocument, node, newParent: SExprNode, index: int): bool =
  if doc == nil or node == nil or newParent == nil:
    return false
  if node == doc.root or newParent.kind != senList or containsNode(node, newParent):
    return false
  let oldParent = node.parent
  let oldIndex = node.indexInParent()
  var targetIndex = index
  discard node.removeFromParent()
  if oldParent == newParent and oldIndex >= 0 and oldIndex < targetIndex:
    dec targetIndex
  doc.addChild(newParent, node, targetIndex, dirty = false)
  doc.select(node)
  doc.markDirty()
  true

proc editAtom*(doc: SExprDocument, node: SExprNode, text: string): bool =
  if node == nil or node.kind != senAtom:
    return false
  node.text = text
  doc.select(node)
  doc.markDirty()
  true

proc parentOfSelected*(doc: SExprDocument): bool =
  let node = doc.selectedNode()
  if node != nil and node.parent != nil:
    doc.select(node.parent)
    return true

proc firstChildOfSelected*(doc: SExprDocument): bool =
  let node = doc.selectedNode()
  if node != nil and node.children.len > 0:
    doc.select(node.children[0])
    return true

proc siblingOfSelected*(doc: SExprDocument, delta: int): bool =
  let node = doc.selectedNode()
  if node == nil or node.parent == nil:
    return false
  let idx = node.indexInParent() + delta
  if idx < 0 or idx >= node.parent.children.len:
    return false
  doc.select(node.parent.children[idx])
  true

proc visibleNodes*(node: SExprNode): seq[SExprNode] =
  if node == nil:
    return @[]
  result.add(node)
  for child in node.children:
    result.add(child.visibleNodes())

proc nextVisible*(doc: SExprDocument, delta: int): bool =
  let nodes = doc.root.visibleNodes()
  let current = doc.selectedNode()
  if current == nil or nodes.len == 0:
    return false
  let idx = nodes.find(current)
  let target = idx + delta
  if target < 0 or target >= nodes.len:
    return false
  doc.select(nodes[target])
  true

proc selectedPath*(doc: SExprDocument): seq[int] =
  var node = doc.selectedNode()
  while node != nil and node.parent != nil:
    result.add(node.indexInParent())
    node = node.parent
  result.reverse()
