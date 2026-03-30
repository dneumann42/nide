import std/[strutils, options]
import db_connector/db_sqlite

type
  SymbolEntry* = object
    id*: int64
    name*: string
    module*: string
    signature*: string
  
  NimIndexDb* = ref object
    conn*: DbConn

proc openMemDb*(): NimIndexDb =
  let conn = open(":memory:", "", "", "")
  result = NimIndexDb(conn: conn)

proc createTables*(db: NimIndexDb) {.raises: [].} =
  try:
    db.conn.exec(sql"""
      CREATE TABLE IF NOT EXISTS symbols (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        module TEXT NOT NULL,
        signature TEXT NOT NULL
      )
    """)
    db.conn.exec(sql"CREATE INDEX IF NOT EXISTS idx_symbol_name ON symbols(name)")
    db.conn.exec(sql"CREATE INDEX IF NOT EXISTS idx_symbol_module ON symbols(module)")
  except:
    echo "[nimindexdb] createTables error: " & getCurrentExceptionMsg()

proc insertSymbol*(db: NimIndexDb, name, module, signature: string) {.raises: [].} =
  try:
    db.conn.exec(sql"INSERT INTO symbols (name, module, signature) VALUES (?, ?, ?)",
                name, module, signature)
  except:
    echo "[nimindexdb] insertSymbol error: " & getCurrentExceptionMsg()

proc getSymbol*(db: NimIndexDb, name, module: string): Option[SymbolEntry] {.raises: [].} =
  try:
    let rows = db.conn.getAllRows(sql"SELECT id, name, module, signature FROM symbols WHERE name = ? AND module = ?",
                                   name, module)
    if rows.len > 0:
      let row = rows[0]
      return some(SymbolEntry(
        id: parseInt(row[0]),
        name: row[1],
        module: row[2],
        signature: row[3]
      ))
  except:
    echo "[nimindexdb] getSymbol error: " & getCurrentExceptionMsg()
  return none(SymbolEntry)

proc searchSymbols*(db: NimIndexDb, prefix: string): seq[SymbolEntry] {.raises: [].} =
  try:
    let pattern = prefix & "%"
    echo "[nimindexdb] searchSymbols: pattern='", pattern, "'"
    for row in db.conn.fastRows(sql"SELECT id, name, module, signature FROM symbols WHERE name LIKE ? ORDER BY name LIMIT 20",
                                 pattern):
      result.add(SymbolEntry(
        id: parseInt(row[0]),
        name: row[1],
        module: row[2],
        signature: row[3]
      ))
    echo "[nimindexdb] searchSymbols: found ", result.len, " results"
  except:
    echo "[nimindexdb] searchSymbols error: " & getCurrentExceptionMsg()

proc getSymbolsByModule*(db: NimIndexDb, module: string): seq[SymbolEntry] {.raises: [].} =
  try:
    for row in db.conn.fastRows(sql"SELECT id, name, module, signature FROM symbols WHERE module = ? ORDER BY name",
                                 module):
      result.add(SymbolEntry(
        id: parseInt(row[0]),
        name: row[1],
        module: row[2],
        signature: row[3]
      ))
  except:
    echo "[nimindexdb] getSymbolsByModule error: " & getCurrentExceptionMsg()

proc getSymbolCount*(db: NimIndexDb): int {.raises: [].} =
  try:
    let row = db.conn.getRow(sql"SELECT COUNT(*) FROM symbols")
    result = parseInt(row[0])
  except:
    echo "[nimindexdb] getSymbolCount error: " & getCurrentExceptionMsg()
    result = 0

proc clearSymbols*(db: NimIndexDb) {.raises: [].} =
  try:
    db.conn.exec(sql"DELETE FROM symbols")
  except:
    echo "[nimindexdb] clearSymbols error: " & getCurrentExceptionMsg()

proc saveToFile*(db: NimIndexDb, path: string) {.raises: [].} =
  try:
    let backupConn = open(path, "", "", "")
    try:
      backupConn.exec(sql"""
        CREATE TABLE IF NOT EXISTS symbols (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          module TEXT NOT NULL,
          signature TEXT NOT NULL
        )
      """)
      backupConn.exec(sql"DELETE FROM symbols")
      for row in db.conn.fastRows(sql"SELECT name, module, signature FROM symbols"):
        backupConn.exec(sql"INSERT INTO symbols (name, module, signature) VALUES (?, ?, ?)",
                       row[0], row[1], row[2])
    finally:
      backupConn.close()
  except:
    echo "[nimindexdb] saveToFile error: " & getCurrentExceptionMsg()

proc loadFromFile*(db: NimIndexDb, path: string) {.raises: [].} =
  try:
    let sourceConn = open(path, "", "", "")
    try:
      for row in sourceConn.fastRows(sql"SELECT name, module, signature FROM symbols"):
        db.conn.exec(sql"INSERT INTO symbols (name, module, signature) VALUES (?, ?, ?)",
                    row[0], row[1], row[2])
    finally:
      sourceConn.close()
  except:
    echo "[nimindexdb] loadFromFile error: " & getCurrentExceptionMsg()

proc close*(db: NimIndexDb) {.raises: [].} =
  try:
    db.conn.close()
  except:
    echo "[nimindexdb] close error: " & getCurrentExceptionMsg()
