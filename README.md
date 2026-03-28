# zmkmanual

LuaLaTeX-only package to generate a utilitarian keyboard manual from ZMK config files.

Current status: initial scaffold with working parser for this repo's keymap/layout/behaviors subset and TikZ layer rendering.

## Files

- `zmkmanual.sty`: package surface and TeX commands
- `zmkmanual.lua`: parser + resolver + TikZ emission
- `labels.lua`: key label tables + text/symbol normalization helpers
- `parser.lua`: ZMK/devicetree parsing + binding resolution
- `renderer.lua`: TikZ geometry + layer/overview rendering
- `annotations.lua`: complex-binding legend extraction + connector drawing
- `build-manual.py`: one-shot builder for local ZMK repos
- `cosmotyl-manual.tex`: example document for this repo

## Main commands

- `\zmkLoadConfig`
- `\zmkPrintLayerOverview`
- `\zmkPrintAllLayers`
- `\zmkPrintLegend`
- `\zmkPrintCombos`
- `\zmkPrintMacros`

## Compile example

Run from `zmkmanual/`:

```bash
lualatex cosmotyl-manual.tex
```

## Build from any local ZMK repo

Run from `zmkmanual/`:

```bash
./build-manual.py /path/to/local/zmk-config
```

Optional flags:

```bash
./build-manual.py /path/to/local/zmk-config --shield cosmotyl --output /tmp/manual.pdf
```

## Notes

- Engine requirement: LuaLaTeX (`lualatex`) only.
- Style is intentionally utilitarian.
- Combos/macros sections currently render explicit empty-state text when none are parsed.
- Optional package key `keycapscale` controls visual keycap scale (e.g. `keycapscale=0.94`).
- Optional package key `overviewscale` controls the all-layers overview size (e.g. `overviewscale=1.35`).
- Recommended for dense layouts: use larger page formats like `a3paper,landscape`.
