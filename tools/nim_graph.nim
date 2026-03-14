import std/[os, strutils, sets, tables, parseopt]

type
  Module* = object
    name*: string
    path*: string
    imports*: seq[string]
    category*: string

  Config* = object
    srcDir*: string
    outputFile*: string
    depth*: int
    groupBy*: string
    includeStd*: bool
    skipPatterns*: seq[string]

const
  StdlibModules* = toHashSet([
    "strutils", "json", "os", "strformat", "algorithm", 
    "tables", "sets", "sequtils", "strtabs", "parseopt",
    "times", "hashes", "options", "parsejson", "streams",
    "regex", "pegs", "lexbase", "xmlparser", "xmltree",
    "htmlparser", "xmldom", "asyncdispatch", "asyncfile",
    "httpclient", "smtp", "ftpclient", "uri", "net",
    "db_sqlite", "db_mysql", "db_postgres", "random",
    "math", "stats", "critbits", "oids",
    "cookies", "md5", "sha1", "hmac", "md4", "crc",
    "unicode", "encodings", "utf8", "widecchars",
    "logging", "macros", "future",
    "typetraits", "typeinfo", "atomics", "locks",
    "channels", "threadpool", "system", "sugar", "dirs",
    "toml_serialization"
  ])

  QtModules* = toHashSet([
    "qapplication", "qwidget", "qdialog", "qmainwindow", "qtoolbar", "qsplitter",
    "qtoolbutton", "qmenu", "qaction", "qkeysequence", "qfiledialog",
    "qfont", "qfontmetrics", "qfontdatabase", "qpushbutton", "qlabel",
    "qplaintextedit", "qtextedit", "qtextdocument", "qtextcursor", "qtextformat",
    "qtextobject", "qlineedit", "qcheckbox", "qradiobutton", "qbuttongroup",
    "qlistwidget", "qlistwidgetitem", "qtreewidget", "qtreewidgetitem",
    "qtablewidget", "qtabwidget", "qstackedwidget",
    "qlayout", "qvboxlayout", "qhboxlayout", "qformlayout", "qboxlayout",
    "qgridlayout", "qspaceritem", "qsizePolicy",
    "qpainter", "qpaintevent", "qcolor", "qpalette", "qbrush", "qpen",
    "qpixmap", "qimage", "qicon", "qbitmap", "qsizef", "qpointf", "qrectf",
    "qsize", "qpoint", "qrect", "qmargins",
    "qprocess", "qtcpsocket", "qabstractsocket", "qiodevice", "qdatastream",
    "qfilesystemmodel", "qabstractitemmodel", "qabstractitemview", "qtreeview",
    "qheaderview", "qmodelindex", "qitemselectionmodel",
    "qscrollbar", "qscroller", "qscrollerproperties",
    "qevent", "qkeyevent", "qmouseevent", "qwheelevent", "qhelpevent",
    "qresizeevent", "qmoveevent", "qcloseevent", "qfocusevent",
    "qshortcut", "qtimer", "qobject", "qcoreapplication",
    "qgraphicsview", "qgraphicsscene", "qgraphicsitem", "qgraphicseffect",
    "qgraphicsopacityeffect", "qgraphicsblur", "qgraphicsdrop_shadoweffect",
    "qabstractbutton", "qtoolbutton", "qtabbar",
    "qstyle", "qstylefactory", "qstyleoption", "qcommonstyle",
    "qdialogbuttonbox", "qmessagebox", "qinputdialog", "qcolordialog",
    "qfontdialog", "qfiledialog", "qprogressdialog",
    "qcursor", "qclipboard", "qscreendescription", "qwindow",
    "qsynthesized", "qgesture", "qgesturerecognizer",
    "qabstractnativeeventfilter", "qnativeeventfilter",
    "qvariant", "qmetaobject", "qproperty", "qmetaenum",
    "qurl", "qfileinfo", "qdir", "qfile", "qtextstream",
    "qjsondocument", "qjsonobject", "qjsonarray", "qjsonvalue",
    "qxmlstreamreader", "qxmlstreamwriter", "dom",
    "qregularexpression",
    "qsvgwidget", "qsvgrenderer", "qpdfwriter", "qprinter", "qprintdialog",
    "qprintpreviewwidget", "qpagesize", "qpagelayout",
    "qtransform", "qmatrix", "qpolygon", "qpainterpath",
    "qvalidator", "qintvalidator", "qdoublevalidator", "qregexpvalidator",
    "qcompleter", "qhistory", "qundostack", "qundocommand",
    "qsystemtrayicon", "qnotification", "qnotificationsettings",
    "qdrag", "qmime_data",
    "qaxobject", "qaxwidget", "qaxbase",
    "qoffscreen", "qopengl", "qopenglwidget", "qopenglcontext",
    "qgl", "qglwidget", "qglcolormap",
    "qsql", "qsqlquery", "qsqlresult", "qsqlrecord", "qsqlfield",
    "qsqlerror", "qsqldatabase", "qsqlrelationaltablemodel",
    "qsqltabledelegate", "qsqlmimedata",
    "qnfc", "qnearfieldmanager", "qndefmessage", "qndefrecord",
    "qbluetooth", "qbluetoothdeviceinfo", "qbluetoothaddress",
    "qbluetoothlocaldevice", "qbluetoothserviceinfo", "qbluetoothsocket",
    "qbluetoothserver", "qbluetoothuuid",
    "qlocation", "qgeopositioninfo", "qgeocoordinate",
    "qmultimedia", "qmediaplayer", "qvideoframe", "qcamera",
    "qnetworkaccessmanager", "qnetworkrequest", "qnetworkreply",
    "qnetworkconfiguration", "qnetworkcookie", "qauthenticator",
    "qssl", "qsslsocket", "qsslerror", "qsslconfiguration",
    "qtest", "qsignalspy", "qabstractitemmodeltester",
    "gen_qlayout_types", "gen_qt_models", "qguiapplication", "osproc", "posix", "qtextcharformat"
  ])

  CategoryPatterns* = toTable({
    "io": @["file*", "stream*", "net*", "http*", "fetch*", "db*", "sock*", "finder", "log*"],
    "ui": @["*view*", "*dialog*", "*toolbar*", "*pane*", "*tree*", "*theme*", "*widget*", "*menu*", "*preview*"],
    "parsing": @["*parse*", "*lexer*", "*parser*", "*syntax*"],
    "types": @["*types*", "*model*", "*buffer*", "*project*", "*settings*", "*config*", "*prototype*"],
    "language": @["*suggest*", "*highlight*", "*check*", "*finddef*", "*complete*", "*index*", "*autocomplete*"],
    "logic": @["*runner*", "*build*", "*exec*", "*run*", "*task*", "*code*"],
    "core": @["application", "app", "main", "root"]
  })

  CategoryKeywords* = toTable({
    "io": @["streams", "httpclient", "asyncdispatch", "db_", "sockets", "net", "uri", "ftpclient", "smtp", "filelist"],
    "ui": @["qt", "seaqt", "qwidget", "qdialog", "qmainwindow", "qapplication", "qtoolbar", "qsplitter"],
    "parsing": @["json", "xml", "toml", "yaml", "pegs", "regex", "lexbase"],
    "language": @["compiler", "ast", "vm", "nimsuggest", "idents", "highlight"],
    "logic": @["process", "exec", "subprocess"]
  })

proc normalizeImport*(raw: string): string =
  ## Strip `as alias`, surrounding quotes, and take last path component.
  var s = raw.strip()
  # Remove " as <alias>" suffix (case-insensitive won't matter here)
  let asIdx = s.find(" as ")
  if asIdx >= 0:
    s = s[0..<asIdx].strip()
  # Strip surrounding quotes (e.g. import "../../tools/nim_graph")
  if s.len >= 2 and s[0] == '"' and s[^1] == '"':
    s = s[1..^2]
  # Take last path component
  if '/' in s:
    s = s.split('/')[^1]
  elif '\\' in s:
    s = s.split('\\')[^1]
  return s

proc matchPattern(name: string, patterns: seq[string]): bool =
  for p in patterns:
    if p.startswith("*") and p.endswith("*"):
      let middle = p[1..^2]
      if middle in name: return true
    elif p.startswith("*"):
      if name.endsWith(p[1..^1]): return true
    elif p.endswith("*"):
      if name.startsWith(p[0..^2]): return true
    elif name == p: return true
  return false

proc detectCategoryByName*(name: string): string =
  let nameLower = name.toLower()
  
  for cat, patterns in CategoryPatterns:
    if matchPattern(nameLower, patterns):
      return cat
  
  return ""

proc detectCategoryByImports(imports: seq[string]): string =
  for imp in imports:
    let impLower = imp.toLower()
    for cat, keywords in CategoryKeywords:
      for kw in keywords:
        if impLower == kw or impLower.contains(kw):
          return cat
  
  return ""

proc detectCategory*(m: Module): string =
  let byName = detectCategoryByName(m.name)
  if byName.len > 0:
    return byName
  
  let byImports = detectCategoryByImports(m.imports)
  if byImports.len > 0:
    return byImports
  
  return "types"

proc getProjectName*(srcDir: string): string =
  let parent = srcDir.parentDir()
  let name = srcDir.lastPathPart
  if name == "src":
    return parent.lastPathPart
  return name

proc isInStringOrComment(line: string, pos: int): bool =
  if pos < 0 or pos >= line.len: return true
  
  let prefix = line[0..<pos]
  
  if "#" in prefix:
    return true
  
  var inString = false
  var stringChar = ' '
  for c in prefix:
    if c == '"' or c == '\'':
      if not inString:
        inString = true
        stringChar = c
      elif c == stringChar:
        inString = false
    elif inString and c == '\\':
      continue
  
  return inString

proc scanModules*(srcDir: string, skipPatterns: seq[string]): seq[Module] =
  var modules: seq[Module]
  
  for path in walkDirRec(srcDir):
    if not path.endsWith(".nim"): continue
    if path.contains("/tests/") or path.contains("\\tests\\"): continue
    if path.contains("/test/"): continue
    
    let relative = path.relativePath(srcDir)
    for pattern in skipPatterns:
      if matchPattern(relative, @[pattern]):
        continue
    
    let name = path.lastPathPart.replace(".nim", "")
    var imports: seq[string]
    var pendingImport = ""
    var inBracket = false
    
    try:
      let content = readFile(path)
      var inMultilineString = false
      
      for lineRaw in content.splitLines:
        var line = lineRaw
        
        if "\"\"\"" in line or "'''" in line:
          inMultilineString = not inMultilineString
          continue
        
        if inMultilineString:
          continue
        
        let trimmed = line.strip()
        if trimmed.len == 0: 
          if inBracket and pendingImport.len > 0:
            pendingImport &= " " & line.strip()
          continue
        if trimmed.startswith("#"): continue
        
        if trimmed.startswith("import "):
          if pendingImport.len > 0:
            pendingImport = ""
            inBracket = false
          
          let startPos = trimmed.find("import") + 6
          if isInStringOrComment(trimmed, startPos):
            continue
          
          var rest = trimmed[7..^1].strip()
          
          if '[' in rest:
            let bracketStart = rest.find('[')
            if ']' in rest:
              let braceStart = rest.find('[')
              let braceEnd = rest.find(']')
              if braceEnd > braceStart:
                let inside = rest[braceStart+1..<braceEnd]
                for imp in inside.split(","):
                  let cleaned = normalizeImport(imp)
                  if cleaned.len > 0 and cleaned != "std" and cleaned != "pkg":
                    imports.add(cleaned)
              rest = rest[0..<bracketStart]
            else:
              inBracket = true
              pendingImport = rest
              continue
          
          if rest.len > 0:
            if rest.contains('[') and rest.contains(']'):
              let start = rest.find('[')
              let finish = rest.find(']')
              if finish > start:
                let inner = rest[start+1..<finish]
                for imp in inner.split(","):
                  let cleaned = normalizeImport(imp)
                  if cleaned.len > 0 and cleaned != "std" and cleaned != "pkg":
                    imports.add(cleaned)
                rest = rest[0..<start] & rest[finish+1..^1]
            
            for imp in rest.split(","):
              let cleaned = normalizeImport(imp)
              if cleaned.len > 0 and cleaned != "std" and cleaned != "pkg":
                imports.add(cleaned)
        elif inBracket and trimmed.len > 0:
          pendingImport &= " " & trimmed
          
          if ']' in trimmed:
            inBracket = false
            var rest = pendingImport
            if '[' in rest:
              let start = rest.find('[')
              let finish = rest.find(']')
              if finish > start:
                let inner = rest[start+1..<finish]
                for imp in inner.split(","):
                  let cleaned = normalizeImport(imp)
                  if cleaned.len > 0 and cleaned != "std" and cleaned != "pkg":
                    imports.add(cleaned)
            pendingImport = ""
            
        elif trimmed.startswith("include "):
          let rest = trimmed[8..^1].strip()
          for inc in rest.split(","):
            let cleaned = normalizeImport(inc)
            if cleaned.len > 0:
              imports.add(cleaned)
    except:
      discard
    
    let category = detectCategory(Module(name: name, imports: imports, category: ""))
    modules.add(Module(name: name, path: path, imports: imports, category: category))
  
  return modules

proc filterModulesByDepth*(modules: seq[Module], depth: int, includeStd: bool): Table[string, Module] =
  result = initTable[string, Module]()
  var moduleSet = initHashSet[string]()
  
  for m in modules:
    moduleSet.incl(m.name)
  
  proc shouldInclude(name: string): bool =
    if name.len == 0: return false
    if name in moduleSet: return false
    if not includeStd and name in StdlibModules: return false
    return true
  
  proc addWithDepth(name: string, d: int) =
    if d > depth: return
    if not shouldInclude(name): return
    
    moduleSet.incl(name)
    
    for m in modules:
      if m.name == name:
        for imp in m.imports:
          addWithDepth(imp, d + 1)
        break
  
  for m in modules:
    if m.category == "core" or m.name.toLower().contains("application"):
      for imp in m.imports:
        addWithDepth(imp, 1)
  
  for m in modules:
    if m.name in moduleSet:
      result[m.name] = m

proc generateDot*(modules: seq[Module], projectName: string, config: Config): string =
  var output = "digraph \"" & projectName & "\" {\n"
  output.add "    rankdir=TB;\n"
  output.add "    node [shape=box, style=rounded, fontname=\"Helvetica\"];\n"
  output.add "    edge [fontname=\"Helvetica\", color=\"#666666\"];\n\n"
  
  var categories = initOrderedTable[string, seq[string]]()
  var moduleCategories = initTable[string, string]()
  
  for m in modules:
    if config.groupBy == "category":
      let cat = m.category
      if cat notin categories:
        categories[cat] = @[]
      categories[cat].add(m.name)
      moduleCategories[m.name] = cat
    else:
      if "main" notin categories:
        categories["main"] = @[]
      categories["main"].add(m.name)
      moduleCategories[m.name] = "main"
  
  let colors = toTable({
    "core": "lightcoral",
    "io": "lightblue",
    "ui": "lightyellow", 
    "parsing": "lightcyan",
    "types": "lightgreen",
    "language": "lightpink",
    "logic": "lightgrey",
    "utils": "lightgoldenrodyellow",
    "main": "whitesmoke"
  })
  
  if config.groupBy == "category":
    for cat, mods in categories:
      let color = colors.getOrDefault(cat, "lightgrey")
      output.add "    subgraph cluster_" & cat & " {\n"
      output.add "        label=\"" & cat.toUpper() & "\";\n"
      output.add "        color=" & color & ";\n"
      output.add "        style=filled;\n"
      for m in mods:
        output.add "        " & m.replace("-", "_") & " [label=\"" & m & "\"];\n"
      output.add "    }\n\n"
  else:
    for cat, mods in categories:
      for m in mods:
        output.add "    " & m.replace("-", "_") & " [label=\"" & m & "\"];\n"
      output.add "\n"
  
  var edgesAdded = initHashSet[string]()
  
  for m in modules:
    let srcCat = moduleCategories.getOrDefault(m.name, "types")
    for imp in m.imports:
      if imp.len == 0: continue
      if imp in StdlibModules and not config.includeStd: continue
      
      let dstCat = moduleCategories.getOrDefault(imp, "external")
      
      if imp in StdlibModules and not config.includeStd: continue
      if imp in QtModules: continue
      
      let key = m.name & "->" & imp
      if key in edgesAdded: continue
      edgesAdded.incl(key)
      
      let srcNode = m.name.replace("-", "_")
      let dstNode = imp.replace("-", "_")
      
      if config.groupBy == "category" and srcCat != dstCat:
        output.add "    " & srcNode & " -> " & dstNode 
        output.add " [label=\"import\", color=\"gray\", style=\"dashed\"];\n"
      else:
        output.add "    " & srcNode & " -> " & dstNode & ";\n"
  
  output.add "}\n"
  return output

proc writeDotFile*(filename: string, content: string) =
  writeFile(filename, content)

proc parseArgs*: Config =
  result = Config(
    srcDir: "src",
    outputFile: "architecture.dot",
    depth: 1,
    groupBy: "category",
    includeStd: false,
    skipPatterns: @["tests/*", "test/*", ".git/*"]
  )
  
  for kind, key, val in getOpt():
    case kind
    of cmdArgument:
      if dirExists(key):
        result.srcDir = key
    of cmdLongOption, cmdShortOption:
      case key
      of "output", "o":
        result.outputFile = val
      of "depth", "d":
        result.depth = parseInt(val)
      of "group-by", "g":
        result.groupBy = val
      of "include-std":
        result.includeStd = true
      of "skip", "s":
        result.skipPatterns.add(val)
      of "help", "h":
        echo "nim_graph - Generate architecture DOT files from Nim source"
        echo ""
        echo "Usage: nim_graph [directory] [options]"
        echo ""
        echo "Options:"
        echo "  -o, --output=<file>   Output file (default: architecture.dot)"
        echo "  -d, --depth=<n>       Import depth 1-5 (default: 1)"
        echo "  -g, --group-by        none|package|category (default: category)"
        echo "  --include-std         Include stdlib imports"
        echo "  -s, --skip=<pattern>  Skip modules matching glob"
        echo "  -h, --help            Show this help"
        quit(0)
    of cmdEnd: discard

when isMainModule:
  let config = parseArgs()
  
  if not dirExists(config.srcDir):
    echo "Error: Source directory '", config.srcDir, "' does not exist"
    quit(1)
  
  echo "Scanning modules in: ", config.srcDir
  let modules = scanModules(config.srcDir, config.skipPatterns)
  echo "Found ", modules.len, " modules"
  
  let projectName = getProjectName(config.srcDir)
  echo "Project: ", projectName
  
  var categories = initCountTable[string]()
  for m in modules:
    categories.inc(m.category)
  
  echo "Categories: "
  for cat, count in categories.pairs:
    echo "  ", cat, ": ", count
  
  let dotContent = generateDot(modules, projectName, config)
  writeDotFile(config.outputFile, dotContent)
  
  echo "Wrote: ", config.outputFile
