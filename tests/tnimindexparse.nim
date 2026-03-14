import std/unittest
import bench/nimindexparse

suite "nimindexparse":
  test "parse simple symbol entry":
    let html = """
`echo`:
system: `echo(x: string)`
strutils: `echo(a: string)`
"""
    let entries = parseIndexHtml(html)
    check entries.len == 2
    
    check entries[0].name == "echo"
    check entries[0].module == "system"
    check entries[0].signature == "echo(x: string)"
    
    check entries[1].name == "echo"
    check entries[1].module == "strutils"
    check entries[1].signature == "echo(a: string)"
  
  test "parse multiple symbols":
    let html = """
`add`:
algorithm: `add[T](x: int; order: SortOrder): int`

`sub`:
system: `sub(x, y: int): int`

`$`:
system: `$`(x: int): string
strutils: `$`(x: string): string
"""
    let entries = parseIndexHtml(html)
    check entries.len == 4
    
    check entries[0].name == "add"
    check entries[0].module == "algorithm"
    
    check entries[1].name == "sub"
    check entries[1].module == "system"
    
    check entries[2].name == "$"
    check entries[2].module == "system"
    
    check entries[3].name == "$"
    check entries[3].module == "strutils"
  
  test "parse empty html returns empty":
    let entries = parseIndexHtml("")
    check entries.len == 0
  
  test "parse html without valid entries":
    let html = """
<div>Some random HTML content</div>
<p>Not a symbol entry</p>
"""
    let entries = parseIndexHtml(html)
    check entries.len == 0
  
  test "parse real index excerpt":
    let html = """
`abs`:
complex: `abs[T](z: Complex[T]): T`
jscore: `abs(m: MathLib; a: SomeNumber): SomeNumber`
rationals: `abs[T](x: Rational[T]): Rational[T]`
system: `abs(x: int): int`
times: `abs(a: Duration): Duration`
"""
    let entries = parseIndexHtml(html)
    check entries.len == 5
    check entries[0].name == "abs"
    check entries[0].module == "complex"
    check entries[4].name == "abs"
    check entries[4].module == "times"
