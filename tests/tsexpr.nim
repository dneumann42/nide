import std/[strutils, unittest]
import nide/editor/[buffers, sexpr_model, sexpr_parse]

suite "sexpr parser":
  test "round trips nested lists":
    let doc = parseSExpr("(define (square x) (* x x))")
    check serializeSExpr(doc).strip() == "(define (square x) (* x x))"

  test "recovers missing close paren":
    let doc = parseSExpr("(a (b c)")
    check serializeSExpr(doc).strip() == "(a (b c))"

  test "recovers stray close paren as atom":
    let doc = parseSExpr("a ) b")
    check serializeSExpr(doc).strip() == "a\n\")\"\nb"

  test "keeps quoted string atoms":
    let doc = parseSExpr("""(say "hello world")""")
    check serializeSExpr(doc).strip() == """(say "hello world")"""

suite "sexpr model":
  test "delete selected subtree preserves root":
    let doc = parseSExpr("(a b c)")
    let listNode = doc.root.children[0]
    doc.select(listNode.children[1])
    check doc.deleteSelected()
    check serializeSExpr(doc).strip() == "(a c)"

  test "wrap selected node":
    let doc = parseSExpr("(a b)")
    let listNode = doc.root.children[0]
    doc.select(listNode.children[0])
    check doc.wrapSelected()
    check serializeSExpr(doc).strip() == "((a) b)"

  test "prevents moving node into descendant":
    let doc = parseSExpr("(a (b c))")
    let outer = doc.root.children[0]
    let inner = outer.children[1]
    check not doc.reparent(outer, inner, 0)

suite "sexpr file routing":
  test "lisp extensions are structural":
    check isSExprPath("/tmp/demo.lisp")
    check isSExprPath("/tmp/demo.scm")
    check isSExprPath("/tmp/demo.sxp")
    check not isSExprPath("/tmp/demo.nim")
