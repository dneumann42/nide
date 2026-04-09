import std/unittest
import nide/nim/nimindexparse

suite "nimindexparse":
  test "parse simple symbol entry":
    let html = """
<dt><a name="echo" href="#echo"><span>echo:</span></a></dt><dd><ul class="simple">
<li><a class="reference external"
      data-doc-search-tag="system: proc echo(x: string)" href="system.html#echo">system: proc echo(x: string)</a></li>
</ul></dd>
"""
    let entries = parseIndexHtml(html)
    check entries.len >= 1
    
  test "parse real index HTML with link tags":
    let html = """
<link rel="stylesheet" type="text/css" href="nimdoc.out.css?v=2.2.8">
<dt><a name="echo" href="#echo"><span>echo:</span></a></dt><dd><ul class="simple">
<li><a class="reference external"
      data-doc-search-tag="system: proc echo(x: string)" href="system.html#echo">system: proc echo(x: string)</a></li>
</ul></dd>
"""
    let entries = parseIndexHtml(html)
    check entries.len >= 1

  test "parse HTML with br tags":
    let html = """
<br>
<dt><a name="echo" href="#echo"><span>echo:</span></a></dt><dd><ul class="simple">
<li><a class="reference external"
      data-doc-search-tag="system: proc echo(x: string)" href="system.html#echo">system: proc echo(x: string)</a></li>
</ul></dd>
"""
    let entries = parseIndexHtml(html)
    check entries.len >= 1

  test "parse HTML with various self-closing tags":
    let html = """
<link rel="stylesheet">
<br>
<hr>
<input type="text">
<img src="test.png">
<meta charset="utf-8">
<dt><a name="echo" href="#echo"><span>echo:</span></a></dt><dd><ul class="simple">
<li><a class="reference external"
      data-doc-search-tag="system: proc echo(x: string)" href="system.html#echo">system: proc echo(x: string)</a></li>
</ul></dd>
"""
    let entries = parseIndexHtml(html)
    check entries.len >= 1

  test "parse HTML with script tags":
    let html = """
<script>var x = 1;</script>
<dt><a name="echo" href="#echo"><span>echo:</span></a></dt><dd><ul class="simple">
<li><a class="reference external"
      data-doc-search-tag="system: proc echo(x: string)" href="system.html#echo">system: proc echo(x: string)</a></li>
</ul></dd>
"""
    let entries = parseIndexHtml(html)
    check entries.len >= 1
  
  test "parse empty html returns empty":
    let entries = parseIndexHtml("")
    check entries.len == 0
