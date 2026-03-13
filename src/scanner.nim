## scanner.nim
## ファイルスキャンと行・列ルールへのマッチング

import std/[os, strutils, algorithm, sequtils, re]
import types

proc matchesPattern(filename, pattern: string): bool =
  ## 簡易glob: *.tif, *.png など拡張子パターンに対応
  if pattern.startsWith("*."):
    return filename.endsWith(pattern[1..^1])
  else:
    return filename == pattern

proc scanFiles*(cfg: Config): seq[string] =
  ## source.directory をスキャンし、pattern にマッチするファイル一覧を返す
  let dir = cfg.source.directory
  if not dirExists(dir):
    raise newException(IOError, "Source directory not found: " & dir)

  result = @[]
  for kind, path in walkDir(dir):
    if kind == pcFile:
      if matchesPattern(extractFilename(path), cfg.source.pattern):
        result.add(path)

  result.sort()
  echo "  Found ", result.len, " files matching '", cfg.source.pattern, "' in ", dir

# ---- 自動抽出: ファイル群から軸ラベルを収集 ----

proc extractLabels(files: seq[string], axExtract: AxisExtract): seq[string] =
  ## 全ファイルに正規表現を適用してキャプチャ値を収集し、ソートして返す
  let pattern = re(axExtract.extract)
  var seen: seq[string] = @[]

  for path in files:
    let filename = extractFilename(path)
    var m: array[20, string]
    if filename.match(pattern, m):
      # 最初のキャプチャグループ (m[0] はマッチ全体、m[1]以降がグループ)
      # std/re では find で captures を使う
      discard # handled below

  for path in files:
    let filename = extractFilename(path)
    var captures: array[20, string]
    let mstart = find(filename, pattern, captures)
    if mstart >= 0:
      # captures[0] = 1番目のキャプチャグループ
      # キャプチャグループがなければマッチ全体を使う
      var val = captures[0]
      if val == "":
        let mlen = matchLen(filename[mstart..^1], pattern)
        if mlen > 0:
          val = filename[mstart ..< mstart + mlen]
      if val != "" and val notin seen:
        seen.add(val)

  # ソート
  if axExtract.order.len > 0:
    # 明示的な順序指定: order に含まれるものを先頭に、残りを後ろに
    var ordered: seq[string] = @[]
    for o in axExtract.order:
      if o in seen:
        ordered.add(o)
    for s in seen:
      if s notin ordered:
        ordered.add(s)
    result = ordered
  else:
    result = seen
    case axExtract.sort
    of "desc":
      result.sort(SortOrder.Descending)
    of "natural":
      # 数字部分を考慮したソート: A1 < A2 < A10
      proc naturalCmp(a, b: string): int =
        var i, j = 0
        while i < a.len and j < b.len:
          if a[i].isDigit and b[j].isDigit:
            # 数字部分を数値として比較
            var na, nb = ""
            while i < a.len and a[i].isDigit: na.add(a[i]); inc i
            while j < b.len and b[j].isDigit: nb.add(b[j]); inc j
            let diff = na.parseInt - nb.parseInt
            if diff != 0: return diff
          else:
            let diff = ord(a[i]) - ord(b[j])
            if diff != 0: return diff
            inc i; inc j
        return a.len - b.len
      result.sort(naturalCmp)
    else: # "asc" or default
      result.sort(SortOrder.Ascending)

# ---- マッチング ----

proc findRowIndex(filename: string, rowAxis: AxisConfig): int =
  ## 行インデックスを返す (-1 = マッチなし)
  ## amExtract の場合は resolvedLabels を使う（buildGrid内で処理）
  case rowAxis.mode
  of amManual:
    for i, r in rowAxis.rules:
      if filename.contains(r.match): return i
    return -1
  of amExtract:
    return -1  # buildGrid 内で処理

proc findColIndex(filename: string, colAxis: AxisConfig): int =
  case colAxis.mode
  of amManual:
    for i, c in colAxis.rules:
      if filename.contains(c.match): return i
    return -1
  of amExtract:
    return -1  # buildGrid 内で処理

proc findExtractIndex(filename: string, axExtract: AxisExtract,
                      labels: seq[string]): int =
  ## 正規表現でキャプチャした値が labels の何番目かを返す
  let pattern = re(axExtract.extract)
  var captures: array[20, string]
  let start = find(filename, pattern, captures)
  if start < 0: return -1
  var val = captures[0]
  if val == "":
    let mlen = matchLen(filename[start..^1], pattern)
    if mlen > 0:
      val = filename[start ..< start + mlen]
  return labels.find(val)

proc buildGrid*(cfg: Config, files: seq[string]): seq[seq[GridCell]] =
  ## 行×列のグリッドを構築する

  # 軸ラベルを解決
  let rowLabels: seq[string] =
    case cfg.rowAxis.mode
    of amManual:  cfg.rowAxis.rules.mapIt(it.label)
    of amExtract: extractLabels(files, cfg.rowAxis.extractCfg)

  let colLabels: seq[string] =
    case cfg.colAxis.mode
    of amManual:  cfg.colAxis.rules.mapIt(it.label)
    of amExtract: extractLabels(files, cfg.colAxis.extractCfg)

  # 自動抽出の場合は何個見つかったか表示
  if cfg.rowAxis.mode == amExtract:
    echo "  Row labels extracted: ", rowLabels.len, " values"
  if cfg.colAxis.mode == amExtract:
    echo "  Col labels extracted: ", colLabels.len, " values"

  let nRows = rowLabels.len
  let nCols = colLabels.len

  # グリッドを空セルで初期化
  result = newSeqWith(nRows, newSeq[GridCell](nCols))
  for r in 0 ..< nRows:
    for c in 0 ..< nCols:
      result[r][c] = GridCell(
        row: r, col: c, filepath: "",
        rowLabel: rowLabels[r],
        colLabel: colLabels[c]
      )

  var matched, skipped, conflicts = 0

  for path in files:
    let filename = extractFilename(path)

    # 行インデックスを取得
    let ri =
      case cfg.rowAxis.mode
      of amManual:  findRowIndex(filename, cfg.rowAxis)
      of amExtract: findExtractIndex(filename, cfg.rowAxis.extractCfg, rowLabels)

    # 列インデックスを取得
    let ci =
      case cfg.colAxis.mode
      of amManual:  findColIndex(filename, cfg.colAxis)
      of amExtract: findExtractIndex(filename, cfg.colAxis.extractCfg, colLabels)

    if ri == -1 or ci == -1:
      skipped += 1
      echo "  [SKIP] ", filename,
           (if ri == -1: " (no row match)" else: ""),
           (if ci == -1: " (no col match)" else: "")
      continue

    if result[ri][ci].filepath != "":
      conflicts += 1
      echo "  [WARN] Conflict at [", rowLabels[ri], "][", colLabels[ci], "]"
      echo "         existing: ", extractFilename(result[ri][ci].filepath)
      echo "         ignored : ", filename
      continue

    result[ri][ci].filepath = path
    matched += 1

  echo ""
  echo "  Matched  : ", matched, " files"
  echo "  Skipped  : ", skipped, " files"
  if conflicts > 0:
    echo "  Conflicts: ", conflicts, " (first match wins)"

proc printGrid*(grid: seq[seq[GridCell]], cfg: Config) =
  ## グリッドの状態をターミナルに表示（max_cols でページ分割して表示）
  echo ""
  echo "=== Grid Layout ==="

  if grid.len == 0 or grid[0].len == 0:
    echo "  (empty grid - no files matched row/col rules)"
    echo ""
    return

  let labelWidth = 14
  let cellWidth  = 22
  let nCols = grid[0].len
  let pageCols = if cfg.output.max_cols > 0: cfg.output.max_cols else: nCols
  let nPages = (nCols + pageCols - 1) div pageCols

  for page in 0 ..< nPages:
    let colStart = page * pageCols
    let colEnd   = min(colStart + pageCols, nCols) - 1

    if nPages > 1:
      echo "  --- Page ", page + 1, "/", nPages,
           " (cols ", colStart + 1, "-", colEnd + 1, " of ", nCols, ") ---"

    # 列ラベルヘッダー
    stdout.write(" ".repeat(labelWidth) & " | ")
    for c in colStart .. colEnd:
      stdout.write(grid[0][c].colLabel.alignLeft(cellWidth) & " | ")
    echo ""
    echo "-".repeat(labelWidth + 3 + (cellWidth + 3) * (colEnd - colStart + 1))

    # 各行
    for r in 0 ..< grid.len:
      stdout.write(grid[r][0].rowLabel.alignLeft(labelWidth) & " | ")
      for c in colStart .. colEnd:
        let cell = grid[r][c]
        let fname = extractFilename(cell.filepath)
        let display =
          if cell.filepath == "": "[ EMPTY ]"
          else: "[ OK ] " & fname[0..min(13, fname.len-1)]
        stdout.write(display.alignLeft(cellWidth) & " | ")
      echo ""
    echo ""

# ---- グリッド分割 ----

proc splitGrid*(grid: seq[seq[GridCell]], cfg: Config): seq[GridPage] =
  ## max_rows / max_cols に基づいてグリッドをページに分割する
  ## max が 0 の場合はその軸は分割しない
  let nRows = grid.len
  let nCols = if nRows > 0: grid[0].len else: 0

  let pageRows = if cfg.output.max_rows > 0: cfg.output.max_rows else: nRows
  let pageCols = if cfg.output.max_cols > 0: cfg.output.max_cols else: nCols

  let nPageRows = (nRows + pageRows - 1) div pageRows  # 切り上げ
  let nPageCols = (nCols + pageCols - 1) div pageCols

  let totalPages = nPageRows * nPageCols
  result = @[]

  var pageIdx = 0
  for pr in 0 ..< nPageRows:
    for pc in 0 ..< nPageCols:
      let rowStart = pr * pageRows
      let rowEnd   = min(rowStart + pageRows, nRows)
      let colStart = pc * pageCols
      let colEnd   = min(colStart + pageCols, nCols)

      # このページのセルをスライス
      var cells: seq[seq[GridCell]] = @[]
      for r in rowStart ..< rowEnd:
        var row: seq[GridCell] = @[]
        for c in colStart ..< colEnd:
          row.add(grid[r][c])
        cells.add(row)

      result.add(GridPage(
        pageIndex: pageIdx,
        rowStart: rowStart, rowEnd: rowEnd,
        colStart: colStart, colEnd: colEnd,
        cells: cells
      ))
      pageIdx += 1

  if totalPages > 1:
    echo "  Split into ", totalPages, " pages",
         " (", nPageRows, " row-pages x ", nPageCols, " col-pages)"
    echo "  Page size: up to ", pageRows, " rows x ", pageCols, " cols"

proc pageFilename*(baseName: string, page: GridPage, totalPages: int): string =
  ## ページ番号付きのファイル名を生成
  ## 例: grid_output.png -> grid_output_001.png
  if totalPages == 1:
    return baseName  # 1ページなら連番なし

  let (dir, name, ext) = splitFile(baseName)
  let digits = if totalPages < 100: 2 elif totalPages < 1000: 3 else: 4
  let num = align($(page.pageIndex + 1), digits, '0')
  let newName = name & "_" & num & ext
  if dir == "": newName
  else: dir / newName
  