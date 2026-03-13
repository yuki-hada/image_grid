# image_grid

[日本語](https://yuki-8.gitbook.io/image-grid)

A CLI tool for arranging microscope images (JPEG/PNG/TIFF) into a grid and exporting as a single PNG.

Rows and columns of the grid are defined independently:
- **Rows** — typically channels (e.g. DAPI, GFP, RFP), defined manually in the config
- **Columns** — typically well positions, either defined manually or extracted automatically from filenames via regex

---

## Installation

### Download binary (recommended)

Download the latest binary for your platform from the [releases page](https://github.com/yuki-hada/image_grid/releases/latest) and add it to your PATH.

### Build from source

```bash
nimble build
```

Requires Nim >= 1.6.0. Dependencies: `stb_image`.

---

## Usage

```
image_grid [options]

Options:
  -c, --config <path>   Config file path (default: config.toml)
  -o, --output <path>   Output filename (overrides config)
  -d, --dir <path>      Source directory (overrides config)
  --dry-run             Show grid layout only, skip image compositing
  --list                List matched files and exit
  -v, --verbose         Verbose output
  -h, --help            Show this help
```

### Quick start

```bash
# Preview grid layout without compositing
image_grid --dry-run

# Run with a specific config and directory
image_grid -c my_config.toml -d /path/to/images

# Override output filename
image_grid -o result.png
```

---

## config.toml

All fields have defaults — no field is strictly required. At minimum, you need at least one row definition (`[[rows]]` or `[rows_extract]`) and one column definition (`[[cols]]` or `[cols_extract]`).

### [output]

| Key | Default | Description |
|-----|---------|-------------|
| `filename` | `"grid_output.png"` | Output PNG filename |
| `cell_width` | `512` | Width of each cell in pixels |
| `cell_height` | `512` | Height of each cell in pixels |
| `gap` | `8` | Gap between cells in pixels |
| `label_font_size` | `12` | Label font size |
| `max_cols` | `0` | Split output into multiple files every N columns (0 = no split) |
| `max_rows` | `0` | Split output into multiple files every N rows (0 = no split) |

### [source]

| Key | Default | Description |
|-----|---------|-------------|
| `directory` | `"."` | Directory to scan for images (overridable with `-d`) |
| `pattern` | `"*.tif"` | Glob pattern for image files |

### Rows — manual (`[[rows]]`)

Define rows explicitly in order. Each entry requires:

| Key | Description |
|-----|-------------|
| `label` | Label shown in the grid header |
| `match` | Substring that must appear in the filename |

```toml
[[rows]]
label = "PC"
match = "C1"

[[rows]]
label = "GFP"
match = "C2"

[[rows]]
label = "RFP"
match = "C3"
```

### Columns — manual (`[[cols]]`)

Same structure as `[[rows]]`. Use when you want explicit control over column order.

```toml
[[cols]]
label = "Well A1"
match = "W0001"

[[cols]]
label = "Well A2"
match = "W0002"
```

### Columns — auto-extract (`[cols_extract]`)

Extract column labels from filenames using a regex. Use this instead of `[[cols]]` when the number of wells is large or varies between experiments.

| Key | Default | Description |
|-----|---------|-------------|
| `extract` | — | Regex applied to each filename. The first capture group (or full match if no groups) becomes the column label |
| `sort` | `"asc"` | Sort order: `"asc"`, `"desc"`, or `"natural"` (numeric-aware, e.g. W2 < W10) |
| `order` | `[]` | Optional explicit ordering. Listed values appear first; remaining values follow in `sort` order |

```toml
[cols_extract]
extract = "W\d{4}F0001"
sort    = "natural"
```

Capture group example — label will be just the `W\d{4}` part:
```toml
[cols_extract]
extract = "(W\d{4})F0001"
sort    = "natural"
```

> **Note:** `[rows_extract]` follows the same structure as `[cols_extract]` and can be used instead of `[[rows]]`.

---

## Page splitting

When `max_cols` or `max_rows` is set, the output is split into multiple numbered files automatically:

```
grid_output.png  →  grid_output_01.png, grid_output_02.png, ...
```

The `--dry-run` preview also paginates to match, making it easy to verify the layout before compositing.

---

## Minimal config example

```toml
[source]
directory = "/path/to/images"

[[rows]]
label = "DAPI"
match = "C1"

[[rows]]
label = "GFP"
match = "C2"

[cols_extract]
extract = "W\d{4}F0001"
sort    = "natural"
```

## Full config example

```toml
[output]
filename    = "grid_output.png"
cell_width  = 512
cell_height = 512
gap         = 10
max_cols    = 12
max_rows    = 0

[source]
directory = "/path/to/images"
pattern   = "*.jpg"

[[rows]]
label = "PC"
match = "C1"

[[rows]]
label = "GFP"
match = "C2"

[[rows]]
label = "RFP"
match = "C3"

[cols_extract]
extract = "W\d{4}F0001"
sort    = "natural"
```
