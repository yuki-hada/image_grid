## CLIエントリポイント
import std/[os, parseopt, strutils]
import config, scanner, composer, types

const VERSION = static:
  var v = "unknown"
  for line in staticRead("../image_grid.nimble").splitLines():
    if line.startsWith("version"):
      let parts = line.split('=')
      if parts.len == 2:
        v = parts[1].strip().strip(chars = {'"'})
      break
  v

const HELP = """
image_grid v""" & VERSION & """

Usage:
  image_grid [options]

Options:
  -c, --config <path>   Config file path (default: config.toml)
  -o, --output <path>   Output filename (overrides config)
  -d, --dir <path>      Source directory (overrides config)
  --dry-run             Show grid layout only, skip image compositing
  --list                List matched files and exit
  --verbose             Verbose output
  -v, --version         Show version and exit
  -h, --help            Show this help

Example config.toml:
  [output]
  filename = "grid_output.png"
  cell_width = 512
  cell_height = 512
  gap = 8

  [source]
  directory = "./images"
  pattern = "*.tif"

  [[rows]]
  label = "DAPI"
  match = "DAPI"

  [[rows]]
  label = "GFP"
  match = "GFP"

  [[cols]]
  label = "Well_A01"
  match = "Well_A01"

  [[cols]]
  label = "Well_B02"
  match = "Well_B02"
"""

type
  CliOptions = object
    configPath: string
    outputOverride: string
    dirOverride: string
    dryRun: bool
    listOnly: bool
    verbose: bool

proc parseArgs(): CliOptions =
  result.configPath = "config.toml"
  result.dryRun = false
  result.listOnly = false
  result.verbose = false

  var p = initOptParser(commandLineParams())
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      case p.key
      of "h", "help":
        echo HELP
        quit(0)
      of "v", "version":
        echo "image_grid version ", VERSION
        quit(0)
      of "c", "config":
        result.configPath = p.val
      of "o", "output":
        result.outputOverride = p.val
      of "d", "dir":
        result.dirOverride = p.val
      of "dry-run":
        result.dryRun = true
      of "list":
        result.listOnly = true
      of "verbose":
        result.verbose = true
      else:
        echo "Unknown option: --", p.key
        quit(1)
    of cmdArgument:
      # 位置引数はconfig pathとして扱う
      result.configPath = p.key

proc run() =
  let opts = parseArgs()

  echo "image_grid v", VERSION
  echo ""

  # ---- 設定読み込み ----
  echo "[1/4] Loading config: ", opts.configPath
  var cfg: Config
  try:
    cfg = loadConfig(opts.configPath)
  except IOError as e:
    echo "ERROR: ", e.msg
    echo ""
    echo "Run with --help to see usage and example config."
    quit(1)
  except CatchableError as e:
    echo "ERROR: Failed to parse config"
    echo "  Exception: ", $e.name
    echo "  Message  : ", e.msg
    quit(1)
  except:
    echo "ERROR: Failed to parse config (unknown exception)"
    echo "  ", getCurrentExceptionMsg()
    quit(1)

  # CLIオプションで上書き
  if opts.outputOverride != "":
    cfg.output.filename = opts.outputOverride
  if opts.dirOverride != "":
    cfg.source.directory = opts.dirOverride

  # 設定の検証
  try:
    validateConfig(cfg)
  except ValueError as e:
    echo "ERROR: Invalid config: ", e.msg
    quit(1)

  if opts.verbose:
    echoConfig(cfg)
  echo ""

  # ---- ファイルスキャン ----
  echo "[2/4] Scanning files..."
  var files: seq[string]
  try:
    files = scanFiles(cfg)
  except IOError as e:
    echo "ERROR: ", e.msg
    quit(1)

  if opts.listOnly:
    echo ""
    echo "=== Matched Files ==="
    for f in files:
      echo "  ", f
    quit(0)
  echo ""

  # ---- グリッド構築 ----
  echo "[3/4] Building grid..."
  let grid = buildGrid(cfg, files)
  printGrid(grid, cfg)

  if opts.dryRun:
    echo "Dry-run mode: skipping image compositing."
    quit(0)

  # ---- グリッド分割 ----
  let pages = splitGrid(grid, cfg)
  let totalPages = pages.len

  # ---- 画像合成 ----
  echo "[4/4] Compositing images..."
  if totalPages > 1:
    echo "  Output: ", totalPages, " files"
  try:
    for page in pages:
      let outPath = pageFilename(cfg.output.filename, page, totalPages)
      if totalPages > 1:
        echo ""
        echo "  --- Page ", page.pageIndex + 1, "/", totalPages,
             " (rows ", page.rowStart + 1, "-", page.rowEnd,
             ", cols ", page.colStart + 1, "-", page.colEnd, ") ---"
      composePage(cfg, page, outPath)
  except IOError as e:
    echo "ERROR: ", e.msg
    quit(1)
  except:
    echo "ERROR: ", getCurrentExceptionMsg()
    quit(1)

  echo ""
  echo "All done!"

when isMainModule:
  run()
