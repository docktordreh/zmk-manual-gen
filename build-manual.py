#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ShieldFiles:
    shield: str
    keymap: Path
    layout: Path
    behaviors: Path


def is_git_repo(path: Path) -> bool:
    git_path = path / ".git"
    return git_path.is_dir() or git_path.is_file()


def prefer_layout_file(shield_dir: Path, shield_name: str) -> Path | None:
    preferred = shield_dir / f"{shield_name}-layouts.dtsi"
    if preferred.is_file():
        return preferred

    layout_candidates = sorted(shield_dir.glob("*layout*.dtsi"))
    if layout_candidates:
        return layout_candidates[0]

    return None


def discover_shields(repo: Path) -> list[ShieldFiles]:
    shields_root = repo / "boards" / "shields"
    if not shields_root.is_dir():
        return []

    discovered: list[ShieldFiles] = []
    for shield_dir in sorted(shields_root.iterdir()):
        if not shield_dir.is_dir():
            continue

        shield_name = shield_dir.name
        preferred_keymap = shield_dir / f"{shield_name}.keymap"
        if preferred_keymap.is_file():
            keymap_file = preferred_keymap
        else:
            keymaps = sorted(shield_dir.glob("*.keymap"))
            if not keymaps:
                continue
            keymap_file = keymaps[0]

        behaviors_file = shield_dir / "behaviors.dtsi"
        if not behaviors_file.is_file():
            continue

        layout_file = prefer_layout_file(shield_dir, shield_name)
        if layout_file is None:
            continue

        discovered.append(
            ShieldFiles(
                shield=shield_name,
                keymap=keymap_file,
                layout=layout_file,
                behaviors=behaviors_file,
            )
        )

    return discovered


def choose_shield(shields: list[ShieldFiles], requested: str | None) -> ShieldFiles:
    if not shields:
        raise RuntimeError("no usable shield found under boards/shields")

    by_name = {entry.shield: entry for entry in shields}
    if requested is not None:
        selected = by_name.get(requested)
        if selected is None:
            available = ", ".join(sorted(by_name.keys()))
            raise RuntimeError(f"shield '{requested}' not found; available: {available}")
        return selected

    if len(shields) == 1:
        return shields[0]

    selected = shields[0]
    available = ", ".join(entry.shield for entry in shields)
    print(
        f"warning: multiple shields found ({available}); using '{selected.shield}'. "
        "pass --shield to pick another",
        file=sys.stderr,
    )
    return selected


def tex_escape_option(value: str) -> str:
    escaped = value.replace("\\", "/")
    escaped = escaped.replace("{", "\\{").replace("}", "\\}")
    return escaped


def render_tex(shield: ShieldFiles, keyboard_name: str, keycap_scale: float, overview_scale: float) -> str:
    keymap = tex_escape_option(str(shield.keymap.resolve()))
    layout = tex_escape_option(str(shield.layout.resolve()))
    behaviors = tex_escape_option(str(shield.behaviors.resolve()))

    return f"""\\documentclass[10pt]{{article}}

\\usepackage[a3paper,landscape,margin=10mm]{{geometry}}
\\usepackage[
  keyboard={keyboard_name},
  keymap={keymap},
  layout={layout},
  behaviors={behaviors},
  keycapscale={keycap_scale:.2f},
  overviewscale={overview_scale:.2f},
  strict=false
]{{zmkmanual}}

\\title{{{shield.shield} Keyboard Manual}}
\\author{{Generated from ZMK sources}}
\\date{{\\today}}

\\begin{{document}}
\\maketitle

\\zmkLoadConfig

\\section*{{Overview}}
\\zmkPrintLayerOverview

\\section*{{Layers}}
\\zmkPrintAllLayers

\\zmkPrintLegend
\\zmkPrintCombos
\\zmkPrintMacros

\\end{{document}}
"""


def compile_pdf(tex_source: str, package_dir: Path, output_pdf: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="zmkmanual-") as tmp_dir_raw:
        tmp_dir = Path(tmp_dir_raw)
        tex_path = tmp_dir / "manual.tex"
        tex_path.write_text(tex_source, encoding="utf-8")

        env = os.environ.copy()
        existing = env.get("TEXINPUTS", "")
        env["TEXINPUTS"] = f"{package_dir}{os.pathsep}{existing}"

        command = ["lualatex", "-interaction=nonstopmode", "-halt-on-error", tex_path.name]
        run = subprocess.run(
            command,
            cwd=tmp_dir,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )

        if run.returncode != 0:
            print(run.stdout, file=sys.stderr)
            raise RuntimeError("lualatex failed")

        built_pdf = tmp_dir / "manual.pdf"
        if not built_pdf.is_file():
            raise RuntimeError("lualatex succeeded but manual.pdf not found")

        output_pdf.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(built_pdf, output_pdf)


def export_images(pdf_path: Path, images_dir: Path, base_name: str, image_dpi: int) -> list[Path]:
    converter = shutil.which("pdftoppm")
    if converter is None:
        raise RuntimeError("pdftoppm not found; install poppler-utils or omit --images-dir")

    images_dir.mkdir(parents=True, exist_ok=True)
    for stale in images_dir.glob(f"{base_name}-page-*.png"):
        stale.unlink()

    prefix = images_dir / f"{base_name}-page"
    command = [
        converter,
        "-png",
        "-r",
        str(image_dpi),
        str(pdf_path),
        str(prefix),
    ]
    run = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    if run.returncode != 0:
        print(run.stdout, file=sys.stderr)
        raise RuntimeError("pdftoppm failed while exporting images")

    generated = sorted(images_dir.glob(f"{base_name}-page-*.png"))
    if not generated:
        raise RuntimeError("image export succeeded but no PNG files were produced")
    return generated


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a ZMK manual PDF from a local ZMK config repository",
    )
    parser.add_argument("repo", help="Path to local ZMK git repository")
    parser.add_argument("--shield", help="Shield name under boards/shields")
    parser.add_argument("--keyboard", help="Keyboard name for zmkmanual option and output filename")
    parser.add_argument("--output", help="Output PDF path")
    parser.add_argument("--images-dir", help="Optional output directory for per-page PNG exports")
    parser.add_argument("--image-dpi", type=int, default=180, help="PNG export DPI for --images-dir")
    parser.add_argument("--keycap-scale", type=float, default=0.90, help="Per-layer keycap visual scale")
    parser.add_argument("--overview-scale", type=float, default=1.35, help="Overview graphic scale")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    repo = Path(args.repo).expanduser().resolve()
    if not repo.is_dir():
        print(f"error: repo path is not a directory: {repo}", file=sys.stderr)
        return 2

    if not is_git_repo(repo):
        print(f"error: path is not a git repo: {repo}", file=sys.stderr)
        return 2

    if args.keycap_scale <= 0:
        print("error: --keycap-scale must be > 0", file=sys.stderr)
        return 2
    if args.overview_scale <= 0:
        print("error: --overview-scale must be > 0", file=sys.stderr)
        return 2
    if args.image_dpi <= 0:
        print("error: --image-dpi must be > 0", file=sys.stderr)
        return 2

    package_dir = Path(__file__).resolve().parent

    try:
        shield = choose_shield(discover_shields(repo), args.shield)
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    keyboard_name = args.keyboard if args.keyboard else shield.shield

    if args.output:
        output_pdf = Path(args.output).expanduser().resolve()
        if output_pdf.is_dir():
            output_pdf = output_pdf / f"{keyboard_name}-manual.pdf"
    else:
        output_pdf = Path.cwd() / f"{keyboard_name}-manual.pdf"

    tex_source = render_tex(shield, keyboard_name, args.keycap_scale, args.overview_scale)

    try:
        compile_pdf(tex_source, package_dir, output_pdf)
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    generated_images: list[Path] = []
    if args.images_dir:
        images_dir = Path(args.images_dir).expanduser().resolve()
        if images_dir.exists() and not images_dir.is_dir():
            print(f"error: --images-dir is not a directory: {images_dir}", file=sys.stderr)
            return 2
        try:
            generated_images = export_images(
                pdf_path=output_pdf,
                images_dir=images_dir,
                base_name=f"{keyboard_name}-manual",
                image_dpi=args.image_dpi,
            )
        except RuntimeError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1

    print(f"PDF written: {output_pdf}")
    print(f"Shield: {shield.shield}")
    print(f"Keyboard: {keyboard_name}")
    print(f"Keymap: {shield.keymap}")
    print(f"Layout: {shield.layout}")
    print(f"Behaviors: {shield.behaviors}")
    if generated_images:
        print(f"Images: {len(generated_images)} PNG pages")
        print(f"Images dir: {generated_images[0].parent}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
