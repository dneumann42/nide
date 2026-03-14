import std/unittest
import std/tempfiles
import std/os
import std/options
import bench/nimindexdb

suite "nimindexdb":
  let testDb = openMemDb()
  
  test "create tables":
    testDb.createTables()
    let count = testDb.getSymbolCount()
    check count == 0
  
  test "insert and retrieve symbol":
    testDb.insertSymbol("echo", "system", "echo(x: varargs[string, `$`])")
    let result = testDb.getSymbol("echo", "system")
    check result.isSome()
    if result.isSome():
      check result.get().name == "echo"
      check result.get().module == "system"
      check result.get().signature == "echo(x: varargs[string, `$`])"
  
  test "insert multiple symbols":
    testDb.insertSymbol("add", "system", "add[T](x: var T, y: T)")
    testDb.insertSymbol("sub", "system", "sub[T](x: var T, y: T)")
    testDb.insertSymbol("echo", "strutils", "echo(a: varargs[string])")
    
    let count = testDb.getSymbolCount()
    check count == 4
  
  test "search symbols by name prefix":
    testDb.insertSymbol("echo", "system", "echo(x: string)")
    let results = testDb.searchSymbols("ech")
    check results.len >= 1
    check results[0].name == "echo"
  
  test "get symbols by module":
    testDb.insertSymbol("func1", "mymod", "func1(): int")
    testDb.insertSymbol("func2", "mymod", "func2(): string")
    let results = testDb.getSymbolsByModule("mymod")
    check results.len == 2
  
  test "clear all symbols":
    testDb.clearSymbols()
    let count = testDb.getSymbolCount()
    check count == 0

suite "file cache":
  test "save and load from file":
    let tmpDir = createTempDir("nimindex_test_", "")
    defer: removeDir(tmpDir)
    let cacheFile = tmpDir / "test_cache.db"
    
    let db1 = openMemDb()
    db1.createTables()
    db1.insertSymbol("test", "mymod", "test(): void")
    db1.saveToFile(cacheFile)
    check fileExists(cacheFile)
    
    let db2 = openMemDb()
    db2.createTables()
    db2.loadFromFile(cacheFile)
    
    let result = db2.getSymbol("test", "mymod")
    check result.isSome()
    if result.isSome():
      check result.get().signature == "test(): void"
  
  test "empty database saves empty file":
    let tmpDir = createTempDir("nimindex_test_", "")
    defer: removeDir(tmpDir)
    let cacheFile = tmpDir / "empty_cache.db"
    
    let db = openMemDb()
    db.createTables()
    db.saveToFile(cacheFile)
    check fileExists(cacheFile)
