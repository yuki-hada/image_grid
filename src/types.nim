## 共通型定義
type
  ## 軸（行・列）の定義モード
  AxisMode* = enum
    amManual,   ## [[rows]] / [[cols]] で手動列挙
    amExtract   ## [rows_extract] / [cols_extract] で正規表現自動抽出

  ## 手動ルール（Phase 1 互換）
  AxisRule* = object
    label*: string       ## グリッドに表示するラベル
    match*: string       ## ファイル名に含まれるべき文字列

  ## 自動抽出ルール（Phase 2）
  ## toml_serialization で安全に扱えるようフラットな型のみ使用
  AxisExtract* = object
    extract*: string     ## 正規表現 例: "(?P<well>Well_[A-Z]\d+)"
    sort*: string        ## "asc" / "desc" / "natural"
    order*: seq[string]  ## 明示的な並び順（空なら sort で自動）

  ## 行または列の設定（手動 or 自動のどちらか）
  ## ※ toml_serialization では case object を直接使わない
  AxisConfig* = object
    case mode*: AxisMode
    of amManual:
      rules*: seq[AxisRule]
    of amExtract:
      extractCfg*: AxisExtract

  OutputConfig* = object
    filename*: string
    cell_width*: int
    cell_height*: int
    gap*: int
    label_scale*: int
    max_rows*: int
    max_cols*: int

  SourceConfig* = object
    directory*: string
    pattern*: string

  ## TOMLから読み込む生の設定
  ## Option[T] を使わず、extract == "" で未設定を判定する
  RawConfig* = object
    output*: OutputConfig
    source*: SourceConfig
    rows*: seq[AxisRule]         ## [[rows]] 手動列挙
    cols*: seq[AxisRule]         ## [[cols]] 手動列挙
    rows_extract*: AxisExtract   ## [rows_extract] 自動抽出（extract==""なら未設定）
    cols_extract*: AxisExtract   ## [cols_extract] 自動抽出（extract==""なら未設定）

  ## 処理に使う解決済み設定
  Config* = object
    output*: OutputConfig
    source*: SourceConfig
    rowAxis*: AxisConfig
    colAxis*: AxisConfig

  ## グリッドの1セル
  GridCell* = object
    row*: int
    col*: int
    filepath*: string
    rowLabel*: string
    colLabel*: string

  ## 分割後の1ページ分
  GridPage* = object
    pageIndex*: int
    rowStart*, rowEnd*: int
    colStart*, colEnd*: int
    cells*: seq[seq[GridCell]]
