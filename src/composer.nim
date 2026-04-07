## 画像を読み込んでグリッドに並べて出力
import std/[os, strutils, math]
import stb_image/read as stbi
import stb_image/write as stbiw
import types

# ---- ピクセルバッファ操作 ----

type
  RGBImage = object
    width, height: int
    pixels: seq[uint8]  ## RGB packed, len = width * height * 3

proc newRGBImage(w, h: int, fillR, fillG, fillB: uint8): RGBImage =
  result.width = w
  result.height = h
  result.pixels = newSeq[uint8](w * h * 3)
  for i in 0 ..< w * h:
    result.pixels[i * 3 + 0] = fillR
    result.pixels[i * 3 + 1] = fillG
    result.pixels[i * 3 + 2] = fillB

proc setPixel(img: var RGBImage, x, y: int, r, g, b: uint8) =
  if x < 0 or x >= img.width or y < 0 or y >= img.height: return
  let idx = (y * img.width + x) * 3
  img.pixels[idx + 0] = r
  img.pixels[idx + 1] = g
  img.pixels[idx + 2] = b

proc copyRegion(dst: var RGBImage, src: RGBImage,
                dstX, dstY, srcX, srcY, w, h: int) =
  ## src の (srcX, srcY) から w×h を dst の (dstX, dstY) にコピー
  for dy in 0 ..< h:
    for dx in 0 ..< w:
      let sx = srcX + dx
      let sy = srcY + dy
      let ddx = dstX + dx
      let ddy = dstY + dy
      if sx < src.width and sy < src.height and
         ddx < dst.width and ddy < dst.height:
        let si = (sy * src.width + sx) * 3
        let di = (ddy * dst.width + ddx) * 3
        dst.pixels[di + 0] = src.pixels[si + 0]
        dst.pixels[di + 1] = src.pixels[si + 1]
        dst.pixels[di + 2] = src.pixels[si + 2]

# ---- 画像ロード ----

proc loadImageAsRGB(path: string, targetW, targetH: int): RGBImage =
  ## ファイルを読み込んで targetW x targetH にリサイズして返す
  var w, h, channels: int
  let data = stbi.load(path, w, h, channels, 3)  # 強制RGB

  if data.len == 0:
    raise newException(IOError, "Failed to load image: " & path)

  # 簡易ニアレストネイバーリサイズ
  result = newRGBImage(targetW, targetH, 0, 0, 0)
  for dy in 0 ..< targetH:
    for dx in 0 ..< targetW:
      let sx = dx * w div targetW
      let sy = dy * h div targetH
      let si = (sy * w + sx) * 3
      let di = (dy * targetW + dx) * 3
      result.pixels[di + 0] = data[si + 0]
      result.pixels[di + 1] = data[si + 1]
      result.pixels[di + 2] = data[si + 2]

# ---- ラベル描画（シンプルな1px文字） ----

# 5x7 ビットマップフォント（数字・アルファベット大文字・記号・スペース）
# 各文字は5列×7行のビット列
const FONT_W = 5
const FONT_H = 7
const FONT: array[43, array[FONT_H, uint8]] = [
  # 0-9
  [0b01110u8, 0b10001u8, 0b10011u8, 0b10101u8, 0b11001u8, 0b10001u8, 0b01110u8],
  [0b00100u8, 0b01100u8, 0b00100u8, 0b00100u8, 0b00100u8, 0b00100u8, 0b01110u8],
  [0b01110u8, 0b10001u8, 0b00001u8, 0b00010u8, 0b00100u8, 0b01000u8, 0b11111u8],
  [0b01110u8, 0b10001u8, 0b00001u8, 0b00110u8, 0b00001u8, 0b10001u8, 0b01110u8],
  [0b00010u8, 0b00110u8, 0b01010u8, 0b10010u8, 0b11111u8, 0b00010u8, 0b00010u8],
  [0b11111u8, 0b10000u8, 0b11110u8, 0b00001u8, 0b00001u8, 0b10001u8, 0b01110u8],
  [0b00110u8, 0b01000u8, 0b10000u8, 0b11110u8, 0b10001u8, 0b10001u8, 0b01110u8],
  [0b11111u8, 0b00001u8, 0b00010u8, 0b00100u8, 0b01000u8, 0b01000u8, 0b01000u8],
  [0b01110u8, 0b10001u8, 0b10001u8, 0b01110u8, 0b10001u8, 0b10001u8, 0b01110u8],
  [0b01110u8, 0b10001u8, 0b10001u8, 0b01111u8, 0b00001u8, 0b00010u8, 0b01100u8],
  # A-Z (index 10-35)
  [0b01110u8, 0b10001u8, 0b10001u8, 0b11111u8, 0b10001u8, 0b10001u8, 0b10001u8], # A
  [0b11110u8, 0b10001u8, 0b10001u8, 0b11110u8, 0b10001u8, 0b10001u8, 0b11110u8], # B
  [0b01110u8, 0b10001u8, 0b10000u8, 0b10000u8, 0b10000u8, 0b10001u8, 0b01110u8], # C
  [0b11100u8, 0b10010u8, 0b10001u8, 0b10001u8, 0b10001u8, 0b10010u8, 0b11100u8], # D
  [0b11111u8, 0b10000u8, 0b10000u8, 0b11110u8, 0b10000u8, 0b10000u8, 0b11111u8], # E
  [0b11111u8, 0b10000u8, 0b10000u8, 0b11110u8, 0b10000u8, 0b10000u8, 0b10000u8], # F
  [0b01110u8, 0b10001u8, 0b10000u8, 0b10111u8, 0b10001u8, 0b10001u8, 0b01111u8], # G
  [0b10001u8, 0b10001u8, 0b10001u8, 0b11111u8, 0b10001u8, 0b10001u8, 0b10001u8], # H
  [0b01110u8, 0b00100u8, 0b00100u8, 0b00100u8, 0b00100u8, 0b00100u8, 0b01110u8], # I
  [0b00111u8, 0b00010u8, 0b00010u8, 0b00010u8, 0b10010u8, 0b10010u8, 0b01100u8], # J
  [0b10001u8, 0b10010u8, 0b10100u8, 0b11000u8, 0b10100u8, 0b10010u8, 0b10001u8], # K
  [0b10000u8, 0b10000u8, 0b10000u8, 0b10000u8, 0b10000u8, 0b10000u8, 0b11111u8], # L
  [0b10001u8, 0b11011u8, 0b10101u8, 0b10001u8, 0b10001u8, 0b10001u8, 0b10001u8], # M
  [0b10001u8, 0b11001u8, 0b10101u8, 0b10011u8, 0b10001u8, 0b10001u8, 0b10001u8], # N
  [0b01110u8, 0b10001u8, 0b10001u8, 0b10001u8, 0b10001u8, 0b10001u8, 0b01110u8], # O
  [0b11110u8, 0b10001u8, 0b10001u8, 0b11110u8, 0b10000u8, 0b10000u8, 0b10000u8], # P
  [0b01110u8, 0b10001u8, 0b10001u8, 0b10001u8, 0b10101u8, 0b10010u8, 0b01101u8], # Q
  [0b11110u8, 0b10001u8, 0b10001u8, 0b11110u8, 0b10100u8, 0b10010u8, 0b10001u8], # R
  [0b01110u8, 0b10001u8, 0b10000u8, 0b01110u8, 0b00001u8, 0b10001u8, 0b01110u8], # S
  [0b11111u8, 0b00100u8, 0b00100u8, 0b00100u8, 0b00100u8, 0b00100u8, 0b00100u8], # T
  [0b10001u8, 0b10001u8, 0b10001u8, 0b10001u8, 0b10001u8, 0b10001u8, 0b01110u8], # U
  [0b10001u8, 0b10001u8, 0b10001u8, 0b10001u8, 0b10001u8, 0b01010u8, 0b00100u8], # V
  [0b10001u8, 0b10001u8, 0b10001u8, 0b10101u8, 0b10101u8, 0b11011u8, 0b10001u8], # W
  [0b10001u8, 0b10001u8, 0b01010u8, 0b00100u8, 0b01010u8, 0b10001u8, 0b10001u8], # X
  [0b10001u8, 0b10001u8, 0b01010u8, 0b00100u8, 0b00100u8, 0b00100u8, 0b00100u8], # Y
  [0b11111u8, 0b00001u8, 0b00010u8, 0b00100u8, 0b01000u8, 0b10000u8, 0b11111u8], # Z
  # space (index 36), underscore (index 37)
  [0b00000u8, 0b00000u8, 0b00000u8, 0b00000u8, 0b00000u8, 0b00000u8, 0b00000u8], # ' '
  [0b00000u8, 0b00000u8, 0b00000u8, 0b00000u8, 0b00000u8, 0b00000u8, 0b11111u8], # '_'
  # 記号 (index 38-42)
  [0b00000u8, 0b00000u8, 0b00000u8, 0b11111u8, 0b00000u8, 0b00000u8, 0b00000u8], # '-'
  [0b00000u8, 0b00000u8, 0b00000u8, 0b00000u8, 0b00000u8, 0b00110u8, 0b00110u8], # '.'
  [0b00010u8, 0b00100u8, 0b01000u8, 0b01000u8, 0b01000u8, 0b00100u8, 0b00010u8], # '('
  [0b01000u8, 0b00100u8, 0b00010u8, 0b00010u8, 0b00010u8, 0b00100u8, 0b01000u8], # ')'
  [0b00001u8, 0b00010u8, 0b00100u8, 0b00100u8, 0b01000u8, 0b10000u8, 0b10000u8], # '/'
]

proc charToFontIndex(c: char): int =
  case c
  of '0'..'9': return ord(c) - ord('0')
  of 'A'..'Z': return ord(c) - ord('A') + 10
  of 'a'..'z': return ord(c) - ord('a') + 10  # 小文字→大文字扱い
  of ' ': return 36
  of '_': return 37
  of '-': return 38
  of '.': return 39
  of '(': return 40
  of ')': return 41
  of '/': return 42
  else: return 36  # 未知文字はスペース

proc drawText(img: var RGBImage, text: string, x, y: int,
              r, g, b: uint8, scale: int = 2) =
  ## (x, y) に text を描画（左上起点）
  let spacing = (FONT_W + 1) * scale
  for ci, ch in text:
    let fi = charToFontIndex(ch)
    let ox = x + ci * spacing
    for row in 0 ..< FONT_H:
      let bits = FONT[fi][row]
      for col in 0 ..< FONT_W:
        if ((bits shr (FONT_W - 1 - col)) and 1u8) == 1u8:
          for sy in 0 ..< scale:
            for sx in 0 ..< scale:
              img.setPixel(ox + col * scale + sx, y + row * scale + sy, r, g, b)

# ---- グリッド合成 ----

proc composePage*(cfg: Config, page: GridPage, outPath: string) =
  ## 1ページ分のグリッドを合成して PNG として出力する

  let cells = page.cells
  let nRows = cells.len
  let nCols = if nRows > 0: cells[0].len else: 0

  let gap = cfg.output.gap
  let cw = cfg.output.cell_width
  let ch = cfg.output.cell_height

  let scale = max(1, cfg.output.label_scale)
  let charH = FONT_H * scale
  let charW = (FONT_W + 1) * scale
  let maxRowLabelLen = block:
    var m = 0
    for row in cells:
      if row.len > 0: m = max(m, row[0].rowLabel.len)
    m
  let labelAreaH = charH + 16
  let labelAreaW = max(40, charW * maxRowLabelLen + 8)

  let totalW = labelAreaW + nCols * cw + (nCols + 1) * gap
  let totalH = labelAreaH + nRows * ch + (nRows + 1) * gap

  echo "  Canvas size: ", totalW, " x ", totalH, " px"

  # 背景: 濃いグレー
  var canvas = newRGBImage(totalW, totalH, 40, 40, 45)

  # ---- 列ラベルを描画 ----
  for ci in 0 ..< nCols:
    let cx = labelAreaW + ci * (cw + gap) + gap
    let label = cells[0][ci].colLabel
    drawText(canvas, label, cx + 4, (labelAreaH - charH) div 2, 220, 220, 255, scale)

  # ---- 行ラベルを描画 ----
  for ri in 0 ..< nRows:
    let cy = labelAreaH + ri * (ch + gap) + gap
    let label = cells[ri][0].rowLabel
    drawText(canvas, label, 4, cy + ch div 2 - charH div 2, 255, 220, 180, scale)

  # ---- 各セルを描画 ----
  var loaded = 0
  var empty = 0

  for ri in 0 ..< nRows:
    for ci in 0 ..< nCols:
      let cell = cells[ri][ci]
      let dx = labelAreaW + ci * (cw + gap) + gap
      let dy = labelAreaH + ri * (ch + gap) + gap

      if cell.filepath == "":
        empty += 1
        let emptyImg = newRGBImage(cw, ch, 60, 60, 65)
        canvas.copyRegion(emptyImg, dx, dy, 0, 0, cw, ch)
        drawText(canvas, "NO IMAGE", dx + 10, dy + ch div 2 - charH div 2, 120, 120, 120, scale)
      else:
        echo "  Loading: ", extractFilename(cell.filepath)
        try:
          let img = loadImageAsRGB(cell.filepath, cw, ch)
          canvas.copyRegion(img, dx, dy, 0, 0, cw, ch)
          loaded += 1
        except CatchableError:
          echo "  [ERROR] Failed to load: ", cell.filepath
          let errImg = newRGBImage(cw, ch, 80, 40, 40)
          canvas.copyRegion(errImg, dx, dy, 0, 0, cw, ch)
          drawText(canvas, "ERROR", dx + 10, dy + ch div 2 - charH div 2, 255, 80, 80, scale)

  echo "  Loaded: ", loaded, "  Empty: ", empty

  # ---- 出力 ----
  echo "  Writing: ", outPath
  let ok = stbiw.writePNG(outPath, canvas.width, canvas.height, 3, canvas.pixels)
  if not ok:
    raise newException(IOError, "Failed to write output: " & outPath)
  echo "  Done! -> ", outPath
