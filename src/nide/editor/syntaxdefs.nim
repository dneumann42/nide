import std/[algorithm, options, os, strutils, tables]

import toml_serialization

import nide/helpers/[appdirs, debuglog, tomlstore]

type
  SyntaxEngine* = enum
    seNimLexer
    seRegex

  FormatKind* = enum
    fkKeyword, fkControlFlow, fkType, fkBuiltinType, fkString, fkCharLit,
    fkNumber, fkComment, fkDocComment, fkBlockComment, fkPragma,
    fkOperator, fkFuncName, fkSpecialVar

  RegexRule* = object
    pattern*: string
    kind*: FormatKind

  SyntaxDefinition* = object
    id*: string
    engine*: SyntaxEngine
    extensions*: seq[string]
    rules*: seq[RegexRule]

  SyntaxRegistry* = object
    definitions*: OrderedTable[string, SyntaxDefinition]
    extensionToSyntax*: Table[string, string]

  StoredRegexRule = object
    pattern*: string
    kind*: string

  StoredSyntaxDefinition = object
    id*: string
    engine*: string
    extensions*: seq[string]
    rules*: seq[StoredRegexRule]

const
  SyntaxesDirName* = "syntaxes"

proc syntaxOverridesDirPath*(): string {.raises: [].} =
  nideConfigDirPath() / SyntaxesDirName

proc bundledSyntaxDirs*(): seq[string] {.raises: [].} =
  result.add(getAppFilename().parentDir() / SyntaxesDirName)
  result.add(currentSourcePath().parentDir().parentDir() / SyntaxesDirName)

proc normalizeExtension(ext: string): string {.raises: [].} =
  result = ext.strip().toLowerAscii()
  if result.len == 0:
    return ""
  if not result.startsWith("."):
    result = "." & result

proc parseEngine(value: string): Option[SyntaxEngine] {.raises: [].} =
  case value.strip().toLowerAscii()
  of "nimlexer":
    some(seNimLexer)
  of "regex":
    some(seRegex)
  else:
    none(SyntaxEngine)

proc parseFormatKind(value: string): Option[FormatKind] {.raises: [].} =
  case value.strip()
  of "keyword":
    some(fkKeyword)
  of "controlFlow":
    some(fkControlFlow)
  of "type":
    some(fkType)
  of "builtinType":
    some(fkBuiltinType)
  of "string":
    some(fkString)
  of "charLit":
    some(fkCharLit)
  of "number":
    some(fkNumber)
  of "comment":
    some(fkComment)
  of "docComment":
    some(fkDocComment)
  of "blockComment":
    some(fkBlockComment)
  of "pragma":
    some(fkPragma)
  of "operator":
    some(fkOperator)
  of "funcName":
    some(fkFuncName)
  of "specialVar":
    some(fkSpecialVar)
  else:
    none(FormatKind)

proc loadSyntaxDefinition(path: string): Option[SyntaxDefinition] {.raises: [].} =
  let stored = loadTomlFile(path, StoredSyntaxDefinition, "syntax definition")
  if stored.id.len == 0:
    logWarn("syntaxdefs: skipping syntax file with missing id: ", path)
    return none(SyntaxDefinition)

  let engine = parseEngine(stored.engine)
  if engine.isNone():
    logWarn("syntaxdefs: skipping syntax file with invalid engine: ", path,
      " engine=", stored.engine)
    return none(SyntaxDefinition)

  var syntax = SyntaxDefinition(
    id: stored.id.strip(),
    engine: engine.get(),
  )

  for ext in stored.extensions:
    let normalized = normalizeExtension(ext)
    if normalized.len > 0:
      syntax.extensions.add(normalized)

  for rule in stored.rules:
    let kind = parseFormatKind(rule.kind)
    if rule.pattern.len == 0 or kind.isNone():
      logWarn("syntaxdefs: skipping invalid regex rule in ", path,
        " kind=", rule.kind)
      continue
    syntax.rules.add(RegexRule(pattern: rule.pattern, kind: kind.get()))

  result = some(syntax)

proc syntaxFilePaths(dir: string): seq[string] {.raises: [].} =
  if not dirExists(dir):
    return
  try:
    for kind, path in walkDir(dir):
      if kind == pcFile and path.toLowerAscii().endsWith(".toml"):
        result.add(path)
  except OSError:
    return
  result.sort(system.cmp[string])

proc registerDefinition(registry: var SyntaxRegistry, syntax: SyntaxDefinition) {.raises: [].} =
  let previous = registry.definitions.getOrDefault(syntax.id)
  if previous.id.len > 0:
    for ext in previous.extensions:
      if registry.extensionToSyntax.getOrDefault(ext) == syntax.id:
        registry.extensionToSyntax.del(ext)
  registry.definitions[syntax.id] = syntax
  for ext in syntax.extensions:
    registry.extensionToSyntax[ext] = syntax.id

proc loadSyntaxRegistry*(bundledDirs: seq[string], userDir = ""): SyntaxRegistry {.raises: [].} =
  for dir in bundledDirs:
    for path in syntaxFilePaths(dir):
      let syntax = loadSyntaxDefinition(path)
      if syntax.isSome():
        result.registerDefinition(syntax.get())

  if userDir.len > 0:
    for path in syntaxFilePaths(userDir):
      let syntax = loadSyntaxDefinition(path)
      if syntax.isSome():
        result.registerDefinition(syntax.get())

proc loadSyntaxRegistry*(): SyntaxRegistry {.raises: [].} =
  loadSyntaxRegistry(bundledSyntaxDirs(), syntaxOverridesDirPath())

proc len*(registry: SyntaxRegistry): int {.raises: [].} =
  registry.definitions.len

proc syntaxForExtension*(registry: SyntaxRegistry, ext: string): Option[SyntaxDefinition] {.raises: [].} =
  let normalized = normalizeExtension(ext)
  if normalized.len == 0:
    return none(SyntaxDefinition)
  let id = registry.extensionToSyntax.getOrDefault(normalized)
  if id.len == 0:
    return none(SyntaxDefinition)
  let syntax = registry.definitions.getOrDefault(id)
  if syntax.id.len == 0:
    return none(SyntaxDefinition)
  some(syntax)

proc syntaxForPath*(registry: SyntaxRegistry, path: string): Option[SyntaxDefinition] {.raises: [].} =
  registry.syntaxForExtension(path.splitFile.ext)

var currentSyntaxRegistry* = loadSyntaxRegistry()

proc reloadSyntaxRegistry*() {.raises: [].} =
  currentSyntaxRegistry = loadSyntaxRegistry()

proc syntaxForPath*(path: string): Option[SyntaxDefinition] {.raises: [].} =
  currentSyntaxRegistry.syntaxForPath(path)
