#!/usr/bin/env python3
import argparse
import html
import os
import subprocess
import time
from pathlib import Path


def run_magick(args):
    candidates = [
        ("/opt/homebrew/bin/magick", True),
        ("/opt/homebrew/bin/convert", False),
        ("magick", True),
        ("convert", False),
    ]
    for tool, uses_magick in candidates:
        cmd = [tool] + (["convert"] if uses_magick else []) + args
        try:
            output = subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True).strip()
            if output:
                return output
        except FileNotFoundError:
            continue
        except subprocess.CalledProcessError:
            continue
    return None


def run_compare(base_path, new_path, output_path):
    candidates = [
        ("/opt/homebrew/bin/magick", True),
        ("/opt/homebrew/bin/compare", False),
        ("magick", True),
        ("compare", False),
    ]
    for tool, uses_magick in candidates:
        cmd = [tool]
        if uses_magick:
            cmd.append("compare")
        cmd += ["-metric", "AE", str(base_path), str(new_path), str(output_path)]
        try:
            result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            metric = (result.stderr or result.stdout).strip()
            return metric
        except FileNotFoundError:
            continue
    return None


def image_metrics(path):
    if not path.exists():
        return {}
    out = run_magick([str(path), "-format", "%w %h %k", "info:"])
    if not out:
        return {}
    parts = out.split()
    if len(parts) < 3:
        return {}
    try:
        width = int(parts[0])
        height = int(parts[1])
        unique = int(float(parts[2]))
    except ValueError:
        return {}
    sat_out = run_magick([
        str(path),
        "-colorspace",
        "HSL",
        "-channel",
        "G",
        "-separate",
        "-format",
        "%[fx:mean]",
        "info:",
    ])
    saturation = None
    if sat_out:
        try:
            saturation = float(sat_out.split()[0])
        except ValueError:
            saturation = None
    lum_out = run_magick([
        str(path),
        "-colorspace",
        "Gray",
        "-format",
        "%[fx:mean]",
        "info:",
    ])
    luminance = None
    if lum_out:
        try:
            luminance = float(lum_out.split()[0])
        except ValueError:
            luminance = None
    dark_out = run_magick([
        str(path),
        "-colorspace",
        "Gray",
        "-threshold",
        "95%",
        "-format",
        "%[fx:mean]",
        "info:",
    ])
    dark_ratio = None
    if dark_out:
        try:
            dark_ratio = 1.0 - float(dark_out.split()[0])
        except ValueError:
            dark_ratio = None
    edge_out = run_magick([
        str(path),
        "-colorspace",
        "Gray",
        "-edge",
        "1",
        "-format",
        "%[fx:mean]",
        "info:",
    ])
    edge_mean = None
    if edge_out:
        try:
            edge_mean = float(edge_out.split()[0])
        except ValueError:
            edge_mean = None
    return {
        "width": width,
        "height": height,
        "unique": unique,
        "saturation": saturation,
        "luminance": luminance,
        "dark_ratio": dark_ratio,
        "edge_mean": edge_mean,
    }


def heuristic_flags(base, new):
    flags = []
    if not base or not new:
        return flags
    base_unique = base.get("unique")
    new_unique = new.get("unique")
    base_sat = base.get("saturation")
    new_sat = new.get("saturation")
    base_lum = base.get("luminance")
    new_lum = new.get("luminance")
    base_dark = base.get("dark_ratio")
    new_dark = new.get("dark_ratio")
    base_edge = base.get("edge_mean")
    new_edge = new.get("edge_mean")
    if base_unique and new_unique and base_unique > 2000 and new_unique < base_unique * 0.5:
        flags.append("low color variety vs baseline")
    if base_sat is not None and new_sat is not None and base_sat > 0.02 and new_sat < base_sat * 0.6:
        flags.append("low saturation vs baseline")
    if base_lum is not None and new_lum is not None and base_lum < 0.98 and new_lum > base_lum + 0.02:
        flags.append("brighter vs baseline")
    if base_dark is not None and new_dark is not None and base_dark > 0.02 and new_dark < base_dark * 0.6:
        flags.append("low ink coverage vs baseline")
    if base_edge is not None and new_edge is not None and base_edge > 0.01 and new_edge < base_edge * 0.6:
        flags.append("low edge detail vs baseline")
    return flags


def format_metrics(metrics):
    if not metrics:
        return "metrics unavailable"
    width = metrics.get("width")
    height = metrics.get("height")
    unique = metrics.get("unique")
    sat = metrics.get("saturation")
    lum = metrics.get("luminance")
    dark = metrics.get("dark_ratio")
    edge = metrics.get("edge_mean")
    sat_str = "n/a" if sat is None else f"{sat:.4f}"
    lum_str = "n/a" if lum is None else f"{lum:.4f}"
    dark_str = "n/a" if dark is None else f"{dark:.4f}"
    edge_str = "n/a" if edge is None else f"{edge:.4f}"
    return (
        f"{width}x{height} px, unique={unique}, sat={sat_str}, lum={lum_str}, "
        f"dark={dark_str}, edge={edge_str}"
    )


def build_report(artifacts_dir, baseline_dir, title, out_prefix):
    if not artifacts_dir.exists():
        raise SystemExit("No artifacts found at " + str(artifacts_dir))
    stamp = time.strftime("%Y%m%d-%H%M%S")
    report_dir = Path(f"{out_prefix}-{stamp}")
    report_dir.mkdir(parents=True, exist_ok=True)

    rows = []
    for artifact in sorted(artifacts_dir.rglob("*.png")):
        group = artifact.parent.relative_to(artifacts_dir).as_posix() or "."
        baseline = baseline_dir / artifact.name
        rows.append((group, artifact.name, baseline, artifact))

    css = """
body { font-family: -apple-system, Helvetica, Arial, sans-serif; margin: 24px; background: #f7f7f7; }
.header { margin-bottom: 16px; }
.group { margin-top: 28px; }
.card { background: #fff; border-radius: 12px; padding: 16px; margin: 16px 0; box-shadow: 0 2px 10px rgba(0,0,0,0.06); }
.title { font-weight: 600; margin-bottom: 12px; }
.grid { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 12px; }
.label { font-size: 12px; color: #666; margin-bottom: 6px; }
img { width: 100%; height: auto; border: 1px solid #eee; background: #fff; }
.path { font-size: 11px; color: #999; word-break: break-all; }
.missing { color: #b00020; font-size: 12px; }
.metrics { font-size: 11px; color: #666; margin-top: 6px; }
.flag { color: #b00020; font-size: 12px; font-weight: 600; margin-top: 6px; }
"""

    parts = ["<!doctype html>", "<html><head><meta charset='utf-8'>", f"<style>{css}</style>", "</head><body>"]
    parts.append(
        f"<div class='header'><h2>{html.escape(title)}</h2><div>Artifacts: {html.escape(str(artifacts_dir))}</div></div>"
    )

    current_group = None
    for group, name, baseline, artifact in rows:
        if group != current_group:
            current_group = group
            parts.append(f"<div class='group'><h3>{html.escape(group)}</h3></div>")
        parts.append("<div class='card'>")
        parts.append(f"<div class='title'>{html.escape(name)}</div>")
        parts.append("<div class='grid'>")

        base_metrics = image_metrics(baseline) if baseline.exists() else {}
        new_metrics = image_metrics(artifact) if artifact.exists() else {}
        flags = heuristic_flags(base_metrics, new_metrics)

        parts.append("<div>")
        parts.append("<div class='label'>Baseline</div>")
        if baseline.exists():
            parts.append(f"<img src='file://{baseline}' />")
            parts.append(f"<div class='path'>{html.escape(str(baseline))}</div>")
            parts.append(f"<div class='metrics'>{html.escape(format_metrics(base_metrics))}</div>")
        else:
            parts.append("<div class='missing'>Missing baseline</div>")
            parts.append(f"<div class='path'>{html.escape(str(baseline))}</div>")
        parts.append("</div>")

        parts.append("<div>")
        parts.append("<div class='label'>New</div>")
        parts.append(f"<img src='file://{artifact}' />")
        parts.append(f"<div class='path'>{html.escape(str(artifact))}</div>")
        parts.append(f"<div class='metrics'>{html.escape(format_metrics(new_metrics))}</div>")
        if flags:
            parts.append(f"<div class='flag'>Possible missing images: {html.escape(', '.join(flags))}</div>")
        parts.append("</div>")

        parts.append("<div>")
        parts.append("<div class='label'>Diff</div>")
        diff_name = f"diff-{group.replace('/', '_')}-{name}"
        diff_path = report_dir / diff_name
        diff_metric = None
        if baseline.exists():
            diff_metric = run_compare(baseline, artifact, diff_path)
        if diff_path.exists():
            parts.append(f"<img src='file://{diff_path}' />")
            if diff_metric:
                parts.append(f"<div class='metrics'>diff AE={html.escape(diff_metric)}</div>")
        else:
            parts.append("<div class='missing'>Diff unavailable</div>")
        parts.append("</div>")

        parts.append("</div>")

    parts.append("</body></html>")

    report_path = report_dir / "index.html"
    report_path.write_text("\n".join(parts), encoding="utf-8")
    print(report_path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifacts", required=True)
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--out-prefix", required=True)
    args = parser.parse_args()

    artifacts_dir = Path(args.artifacts).resolve()
    baseline_dir = Path(args.baseline).resolve()
    build_report(artifacts_dir, baseline_dir, args.title, args.out_prefix)


if __name__ == "__main__":
    main()
