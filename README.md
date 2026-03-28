# zmk-manual-gen

LuaLaTeX toolkit for generating physical-layout ZMK manuals from source-of-truth keymaps.

## Repository Layout

- `zmkmanual.sty`: package surface and TeX commands
- `zmkmanual.lua`: loader + orchestration + TeX-facing render commands
- `parser.lua`: ZMK/devicetree parsing + semantic resolution
- `renderer.lua`: TikZ geometry + key rendering
- `labels.lua`: key labels, aliases, symbol normalization
- `annotations.lua`: complex-binding callouts and legend connectors
- `build-manual.py`: one-shot PDF (and optional image) build helper

## LaTeX Commands

- `\zmkLoadConfig`
- `\zmkPrintLayerOverview`
- `\zmkPrintAllLayers`
- `\zmkPrintLegend`
- `\zmkPrintCombos`
- `\zmkPrintMacros`

## Quick Start

Requirements:

- `lualatex` (TeX Live with LuaHBTeX)
- optional for docs images: `pdftoppm` (Poppler)

Build from any local ZMK repo:

```bash
./build-manual.py /path/to/local/zmk-config
```

Default output:

- `./<keyboard>-manual.pdf` (current working directory)

Useful flags:

```bash
./build-manual.py /path/to/local/zmk-config \
  --shield cosmotyl \
  --keyboard cosmotyl \
  --output ./artifacts/
```

- `--keyboard <name>` sets package `keyboard=` and output basename.
- `--output <path>` supports file path or directory path.

## Image Export for Documentation

The script can export per-page PNGs from the generated PDF.

```bash
./build-manual.py /path/to/local/zmk-config \
  --keyboard cosmotyl \
  --images-dir ./docs/images/cosmotyl \
  --image-dpi 180
```

Output naming pattern:

- `docs/images/cosmotyl/cosmotyl-manual-page-01.png`
- `docs/images/cosmotyl/cosmotyl-manual-page-02.png`
- ...

## PDF Walkthrough

### All-Layers Overview

![Cosmotyl manual page 1](docs/images/cosmotyl/cosmotyl-manual-page-01.png)

This first page is an overlay view across all layers. Every physical key position appears once, and each colored line inside a key is that key's behavior on a different layer. The "Layer colors" legend maps each color to its layer.

### Per-Layer Detail Page

![Cosmotyl manual page 2](docs/images/cosmotyl/cosmotyl-manual-page-02.png)

After the overview, the PDF switches to individual layer pages. Each key is rendered in exact physical position, and complex behaviors are called out with connector lines to the legend so keycaps stay readable while still documenting hold-tap/tap-dance/layer actions.

### Reference Sections

![Cosmotyl manual page 10](docs/images/cosmotyl/cosmotyl-manual-page-10.png)

The final section is reference-oriented: behavior index (ref/count/meaning), then combos and macros. Combos/macros are always shown, including explicit "none defined" output when the source has none.