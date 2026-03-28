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

## GitHub Actions Integration

To extend the default upstream ZMK firmware workflow with manual generation, infer shields from `boards/shields`, build PDF-only output, and upload PDFs as workflow artifacts:

```yaml
name: Build ZMK firmware + manuals
on: [push, pull_request, workflow_dispatch]

jobs:
  build:
    uses: zmkfirmware/zmk/.github/workflows/build-user-config.yml@v0.3

  manual:
    runs-on: ubuntu-latest
    needs: build
    steps:
      - uses: actions/checkout@v4
        with:
          path: config

      - uses: actions/checkout@v4
        with:
          repository: your-org/zmk-manual-gen
          ref: main
          path: zmk-manual-gen

      - name: Install dependencies
        run: sudo apt-get update && sudo apt-get install -y texlive-luatex texlive-latex-extra texlive-pictures

      - name: Build manuals (auto-discover shields)
        run: |
          python - <<'PY'
          from pathlib import Path
          import subprocess
          import sys

          shields_root = Path("config/boards/shields")
          shields = []
          if shields_root.is_dir():
            for shield_dir in sorted(p for p in shields_root.iterdir() if p.is_dir()):
              name = shield_dir.name
              has_keymap = any(shield_dir.glob("*.keymap"))
              has_behaviors = (shield_dir / "behaviors.dtsi").is_file()
              has_layout = (shield_dir / f"{name}-layouts.dtsi").is_file() or any(shield_dir.glob("*layout*.dtsi"))
              if has_keymap and has_behaviors and has_layout:
                shields.append(name)

          if not shields:
            print("No usable shields found under config/boards/shields", file=sys.stderr)
            sys.exit(1)

          artifacts = Path("artifacts")
          artifacts.mkdir(parents=True, exist_ok=True)

          for shield in shields:
            out_dir = artifacts / shield
            out_dir.mkdir(parents=True, exist_ok=True)
            cmd = [
              "python",
              "zmk-manual-gen/build-manual.py",
              "config",
              "--shield",
              shield,
              "--keyboard",
              shield,
              "--output",
              str(out_dir / f"{shield}-manual.pdf"),
            ]
            print("Running:", " ".join(cmd))
            subprocess.run(cmd, check=True)
          PY

      - name: Upload PDFs artifact
        uses: actions/upload-artifact@v4
        with:
          name: zmk-manual-pdfs-${{ github.sha }}
          path: artifacts/**/*.pdf
```

Replace `repository:` with your values. Optionally pin `ref:` to a release tag or commit SHA.
No custom secret required for artifact uploads.

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
