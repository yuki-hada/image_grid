## config.nim
## 自前の最小TOMLパーサーで設定ファイルを読み込む
## toml_serialization を使わないので依存なし

import std/[os, strutils, sequtils]
import types

# ---- 最小TOMLパーサー ----

type
  TomlSection = object
    name: string
    isArray: bool
    keys: seq[tuple[k, v: string]]

proc stripComment(line: string): string =
  var inStr = false
  for i, c in line:
    if c == '"': inStr = not inStr
    if c == '#' and not inStr: return line[0..<i].strip()
  return line.strip()

proc parseTomlFile(path: string): seq[TomlSection] =
  var sections: seq[TomlSection]
  var current = TomlSection(name: "__root__")
  for rawLine in lines(path):
    let line = stripComment(rawLine)
    if line.len == 0: continue
    if line.startsWith("[[") and line.endsWith("]]"):
      sections.add(current)
      current = TomlSection(name: line[2..^3].strip(), isArray: true)
    elif line.startsWith("[") and line.endsWith("]"):
      sections.add(current)
      current = TomlSection(name: line[1..^2].strip(), isArray: false)
    elif "=" in line:
      let idx = line.find('=')
      let k = line[0..<idx].strip()
      let v = line[idx+1..^1].strip()
      current.keys.add((k, v))
  sections.add(current)
  return sections

proc getStr(keys: seq[tuple[k, v: string]], key: string, default = ""): string =
  for pair in keys:
    if pair.k == key:
      let v = pair.v
      if v.startsWith('"') and v.endsWith('"'): return v[1..^2]
      return v
  return default

proc getInt(keys: seq[tuple[k, v: string]], key: string, default = 0): int =
  for pair in keys:
    if pair.k == key:
      try: return pair.v.parseInt
      except: return default
  return default

proc getSeqStr(keys: seq[tuple[k, v: string]], key: string): seq[string] =
  for pair in keys:
    if pair.k == key:
      let v = pair.v.strip()
      if v.startsWith("[") and v.endsWith("]"):
        let inner = v[1..^2]
        return inner.split(',').mapIt(it.strip().strip(chars = {'"'})).filterIt(it.len > 0)
  return @[]

# ---- Config 構築 ----

proc resolveAxis(rules: seq[AxisRule], extractCfg: AxisExtract): AxisConfig =
  if rules.len > 0:
    AxisConfig(mode: amManual, rules: rules)
  elif extractCfg.extract != "":
    AxisConfig(mode: amExtract, extractCfg: extractCfg)
  else:
    AxisConfig(mode: amManual, rules: @[])

proc loadConfig*(path: string): Config =
  if not fileExists(path):
    raise newException(IOError, "Config file not found: " & path)

  let sections = parseTomlFile(path)

  var output   = OutputConfig()
  var source   = SourceConfig()
  var rows: seq[AxisRule]
  var cols: seq[AxisRule]
  var rowsExtract = AxisExtract()
  var colsExtract = AxisExtract()

  for sec in sections:
    case sec.name
    of "output":
      output.filename        = sec.keys.getStr("filename", "grid_output.png")
      output.cell_width      = sec.keys.getInt("cell_width",  512)
      output.cell_height     = sec.keys.getInt("cell_height", 512)
      output.gap             = sec.keys.getInt("gap", 8)
      output.label_font_size = sec.keys.getInt("label_font_size", 12)
      output.max_rows        = sec.keys.getInt("max_rows", 0)
      output.max_cols        = sec.keys.getInt("max_cols", 0)
    of "source":
      source.directory = sec.keys.getStr("directory", ".")
      source.pattern   = sec.keys.getStr("pattern", "*.tif")
    of "rows":
      if sec.isArray:
        rows.add(AxisRule(
          label: sec.keys.getStr("label"),
          match: sec.keys.getStr("match")
        ))
    of "cols":
      if sec.isArray:
        cols.add(AxisRule(
          label: sec.keys.getStr("label"),
          match: sec.keys.getStr("match")
        ))
    of "rows_extract":
      rowsExtract.extract = sec.keys.getStr("extract")
      rowsExtract.sort    = sec.keys.getStr("sort", "asc")
      rowsExtract.order   = sec.keys.getSeqStr("order")
    of "cols_extract":
      colsExtract.extract = sec.keys.getStr("extract")
      colsExtract.sort    = sec.keys.getStr("sort", "asc")
      colsExtract.order   = sec.keys.getSeqStr("order")
    else:
      discard

  if output.filename == "":   output.filename   = "grid_output.png"
  if output.cell_width == 0:  output.cell_width  = 512
  if output.cell_height == 0: output.cell_height = 512
  if source.directory == "":  source.directory   = "."
  if source.pattern == "":    source.pattern     = "*.tif"

  result.output  = output
  result.source  = source
  result.rowAxis = resolveAxis(rows, rowsExtract)
  result.colAxis = resolveAxis(cols, colsExtract)

proc validateConfig*(cfg: Config) =
  case cfg.rowAxis.mode
  of amManual:
    if cfg.rowAxis.rules.len == 0:
      raise newException(ValueError,
        "No row rules defined. Add [[rows]] or [rows_extract] to config.")
  of amExtract:
    if cfg.rowAxis.extractCfg.extract == "":
      raise newException(ValueError, "[rows_extract] extract is empty")
  case cfg.colAxis.mode
  of amManual:
    if cfg.colAxis.rules.len == 0:
      raise newException(ValueError,
        "No col rules defined. Add [[cols]] or [cols_extract] to config.")
  of amExtract:
    if cfg.colAxis.extractCfg.extract == "":
      raise newException(ValueError, "[cols_extract] extract is empty")

proc echoConfig*(cfg: Config) =
  echo "=== Config ==="
  echo "  Source dir : ", cfg.source.directory
  echo "  Pattern    : ", cfg.source.pattern
  echo "  Output     : ", cfg.output.filename
  echo "  Cell size  : ", cfg.output.cell_width, " x ", cfg.output.cell_height
  echo "  Gap        : ", cfg.output.gap, " px"
  if cfg.output.max_rows > 0: echo "  Max rows   : ", cfg.output.max_rows
  if cfg.output.max_cols > 0: echo "  Max cols   : ", cfg.output.max_cols
  case cfg.rowAxis.mode
  of amManual:
    echo "  Rows [manual] : ", cfg.rowAxis.rules.len
    for r in cfg.rowAxis.rules: echo "    [", r.label, "] match=", r.match
  of amExtract:
    echo "  Rows [auto]   : extract=", cfg.rowAxis.extractCfg.extract,
         "  sort=", cfg.rowAxis.extractCfg.sort
  case cfg.colAxis.mode
  of amManual:
    echo "  Cols [manual] : ", cfg.colAxis.rules.len
    for c in cfg.colAxis.rules: echo "    [", c.label, "] match=", c.match
  of amExtract:
    echo "  Cols [auto]   : extract=", cfg.colAxis.extractCfg.extract,
         "  sort=", cfg.colAxis.extractCfg.sort
         