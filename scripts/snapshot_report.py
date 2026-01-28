#!/usr/bin/env python3
import argparse
import html
import json
import os
import re
import subprocess
import time
from pathlib import Path

BASE_CSS = (
    "html,body{margin:0;padding:0;font-family:-apple-system,Helvetica,Arial,sans-serif;"
    "font-size:16px;line-height:1.4;background:#fff;color:#111;}"
    ".snapshot-root{padding:12px;}"
)


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


def run_vision_ocr(image_path):
    script = Path(__file__).parent / "vision_ocr.swift"
    if not script.exists():
        return None
    tool = ensure_swift_tool(script, "vision_ocr", ["Vision", "AppKit"])
    if not tool:
        return None
    try:
        result = subprocess.run(
            [str(tool), str(image_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        return None
    output = result.stdout.strip()
    if not output and result.stderr.strip():
        output = f"error: {result.stderr.strip()}"
    if not output:
        return None
    return output


def parse_trim_geometry(value):
    if not value:
        return None
    # format: WxH+X+Y
    if "+" not in value or "x" not in value:
        return None
    try:
        size, x, y = value.split("+")
        w, h = size.split("x")
        return {
            "trim_width": int(w),
            "trim_height": int(h),
            "trim_x": int(x),
            "trim_y": int(y),
        }
    except ValueError:
        return None


def parse_test_log(path_value):
    if not path_value:
        return {}
    path = Path(path_value)
    if not path.exists():
        return {}
    try:
        text = path.read_text()
    except OSError:
        return {}
    statuses = {}
    matcher = re.compile(r"Test case '([^']+)' (passed|failed)")
    for match in matcher.finditer(text):
        raw_test = match.group(1)
        status_raw = match.group(2)
        simple = raw_test.replace("/", ".")
        if "." in simple:
            simple = simple.split(".")[-1]
        simple = simple.split("(", 1)[0]
        statuses[simple] = status_raw
    case_matcher = re.compile(r"Test Case '-\[[^ ]+ ([^]]+)\]' (passed|failed)")
    for match in case_matcher.finditer(text):
        method_name = match.group(1)
        status_raw = match.group(2)
        statuses[method_name] = status_raw
        if method_name.startswith("test") and len(method_name) > 4:
            trimmed = method_name[4:]
            if trimmed:
                trimmed = trimmed[0].lower() + trimmed[1:]
                statuses[trimmed] = status_raw
                base_name = trimmed
            else:
                base_name = method_name
        else:
            base_name = method_name
        base_key = base_name.split("_", 1)[0]
        statuses[base_key] = status_raw
    return statuses


def load_ocr_metrics(ocr_dir, base_name, label):
    if not ocr_dir:
        return None
    path = ocr_dir / f"{base_name}.{label}.lines.json"
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    lines = data.get("lines") or []
    heights = []
    char_widths = []
    for line in lines:
        rect = line.get("rect") or {}
        text = line.get("text") or ""
        h = rect.get("h")
        w = rect.get("w")
        if isinstance(h, (int, float)):
            heights.append(float(h))
        if isinstance(w, (int, float)) and text:
            char_widths.append(float(w) / max(1, len(text)))
    def median(values):
        if not values:
            return None
        values = sorted(values)
        mid = len(values) // 2
        if len(values) % 2:
            return values[mid]
        return (values[mid - 1] + values[mid]) / 2
    return {
        "ocr_top": data.get("topPadding"),
        "ocr_bottom": data.get("bottomPadding"),
        "ocr_left": data.get("leftPadding"),
        "ocr_right": data.get("rightPadding"),
        "ocr_lines": len(lines),
        "ocr_line_height_median": median(heights),
        "ocr_char_width_median": median(char_widths),
    }


def render_html_preview(html_payload, out_path, width=600, height=220):
    script = Path(__file__).parent / "render_html.swift"
    if not script.exists():
        return False
    tool = ensure_swift_tool(script, "render_html", ["WebKit", "AppKit"])
    if not tool:
        return False
    out_path.parent.mkdir(parents=True, exist_ok=True)
    html_path = out_path.with_suffix(".html")
    payload = (
        "<!doctype html><html><head><meta charset='utf-8'>"
        f"<style>{BASE_CSS}</style></head><body>"
        f"<div class='snapshot-root'>{html_payload}</div></body></html>"
    )
    html_path.write_text(payload, encoding="utf-8")
    try:
        result = subprocess.run(
            [str(tool), str(html_path), str(out_path), str(width), str(height)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        return False
    return result.returncode == 0 and out_path.exists()


def ensure_swift_tool(script_path, name, frameworks):
    tools_dir = Path("/tmp/swiftuihtml-report-tools")
    tools_dir.mkdir(parents=True, exist_ok=True)
    binary = tools_dir / name
    script_mtime = script_path.stat().st_mtime
    if binary.exists() and binary.stat().st_mtime >= script_mtime:
        return binary
    cmd = ["swiftc", str(script_path), "-o", str(binary)]
    for framework in frameworks:
        cmd += ["-framework", framework]
    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        return None
    if result.returncode != 0:
        return None
    return binary


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
    nonwhite_out = run_magick([
        str(path),
        "-colorspace",
        "Gray",
        "-threshold",
        "99%",
        "-format",
        "%[fx:mean]",
        "info:",
    ])
    nonwhite_ratio = None
    if nonwhite_out:
        try:
            nonwhite_ratio = 1.0 - float(nonwhite_out.split()[0])
        except ValueError:
            nonwhite_ratio = None
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
    trim_out = run_magick([str(path), "-trim", "-format", "%@", "info:"])
    trim = parse_trim_geometry(trim_out)
    metrics = {
        "width": width,
        "height": height,
        "unique": unique,
        "saturation": saturation,
        "luminance": luminance,
        "dark_ratio": dark_ratio,
        "nonwhite_ratio": nonwhite_ratio,
        "edge_mean": edge_mean,
    }
    if trim:
        metrics.update(trim)
        metrics["trim_left"] = trim["trim_x"]
        metrics["trim_top"] = trim["trim_y"]
        metrics["trim_right"] = max(0, width - (trim["trim_x"] + trim["trim_width"]))
        metrics["trim_bottom"] = max(0, height - (trim["trim_y"] + trim["trim_height"]))
    return metrics


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
    base_nonwhite = base.get("nonwhite_ratio")
    new_nonwhite = new.get("nonwhite_ratio")
    if base_unique and new_unique and base_unique > 2000 and new_unique < base_unique * 0.5:
        flags.append("low color variety vs baseline")
    if base_sat is not None and new_sat is not None and base_sat > 0.02 and new_sat < base_sat * 0.6:
        flags.append("low saturation vs baseline")
    if base_lum is not None and new_lum is not None and base_lum < 0.98 and new_lum > base_lum + 0.02:
        flags.append("brighter vs baseline")
    if base_nonwhite is not None and new_nonwhite is not None and base_nonwhite > 0.02 and new_nonwhite < base_nonwhite * 0.6:
        flags.append("low nonwhite coverage vs baseline")
    if base_dark is not None and new_dark is not None and base_dark > 0.02 and new_dark < base_dark * 0.6:
        flags.append("low ink coverage vs baseline")
    if base_edge is not None and new_edge is not None and base_edge > 0.01 and new_edge < base_edge * 0.6:
        flags.append("low edge detail vs baseline")
    if (
        base_nonwhite is not None and new_nonwhite is not None
        and base_edge is not None and new_edge is not None
        and base_nonwhite > 0.05
        and new_nonwhite < base_nonwhite * 0.5
        and new_edge < base_edge * 0.5
    ):
        flags.append("possible missing images (low nonwhite + low edge)")
    if (
        base_sat is not None and new_sat is not None
        and base_edge is not None and new_edge is not None
        and base_sat > 0.03
        and new_sat < base_sat * 0.5
        and new_edge < base_edge * 0.7
    ):
        flags.append("possible missing images (low saturation + low edge)")
    if (
        base_unique is not None and new_unique is not None
        and base_edge is not None and new_edge is not None
        and base_unique > 1500
        and new_unique < base_unique * 0.5
        and new_edge < base_edge * 0.6
    ):
        flags.append("possible missing images (low color variety + low edge)")
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
    nonwhite = metrics.get("nonwhite_ratio")
    edge = metrics.get("edge_mean")
    sat_str = "n/a" if sat is None else f"{sat:.4f}"
    lum_str = "n/a" if lum is None else f"{lum:.4f}"
    dark_str = "n/a" if dark is None else f"{dark:.4f}"
    nonwhite_str = "n/a" if nonwhite is None else f"{nonwhite:.4f}"
    edge_str = "n/a" if edge is None else f"{edge:.4f}"
    trim_left = metrics.get("trim_left")
    trim_top = metrics.get("trim_top")
    trim_right = metrics.get("trim_right")
    trim_bottom = metrics.get("trim_bottom")
    trim_str = ""
    if None not in (trim_left, trim_top, trim_right, trim_bottom):
        trim_str = f", trim(T/L/B/R)={trim_top}/{trim_left}/{trim_bottom}/{trim_right}"
    ocr_top = metrics.get("ocr_top")
    ocr_bottom = metrics.get("ocr_bottom")
    ocr_left = metrics.get("ocr_left")
    ocr_right = metrics.get("ocr_right")
    ocr_lines = metrics.get("ocr_lines")
    ocr_line_h = metrics.get("ocr_line_height_median")
    ocr_char_w = metrics.get("ocr_char_width_median")
    ocr_str = ""
    if None not in (ocr_top, ocr_bottom, ocr_left, ocr_right, ocr_lines):
        ocr_str = (
            f", ocr(T/L/B/R)={ocr_top:.1f}/{ocr_left:.1f}/{ocr_bottom:.1f}/{ocr_right:.1f}"
            f", lines={ocr_lines}"
        )
        if ocr_line_h is not None:
            ocr_str += f", lineH~{ocr_line_h:.1f}"
        if ocr_char_w is not None:
            ocr_str += f", charW~{ocr_char_w:.2f}"
    return (
        f"{width}x{height} px, unique={unique}, sat={sat_str}, lum={lum_str}, "
        f"dark={dark_str}, nonwhite={nonwhite_str}, edge={edge_str}"
        f"{trim_str}{ocr_str}"
    )


def is_snapshot_image(name: str) -> bool:
    lower = name.lower()
    if lower.startswith(("reference_", "failure_", "difference_", "diff-")):
        return False
    if lower.startswith("_probe_"):
        return False
    if ".baseline." in lower or ".ocr." in lower:
        return False
    if lower.endswith(".render.png"):
        return False
    return True


def build_report(artifacts_dir, baseline_dir, title, out_prefix, test_log=None):
    if not artifacts_dir.exists():
        raise SystemExit("No artifacts found at " + str(artifacts_dir))
    stamp = time.strftime("%Y%m%d-%H%M%S")
    report_dir = Path(f"{out_prefix}-{stamp}")
    report_dir.mkdir(parents=True, exist_ok=True)
    ocr_dir = artifacts_dir.parent / "ocr"
    test_statuses = parse_test_log(test_log)
    test_log_path = Path(test_log) if test_log else None
    test_log_available = bool(test_log_path and test_log_path.exists())

    rows = []
    artifacts = list(artifacts_dir.rglob("*.png"))
    artifacts.sort(key=lambda path: path.stat().st_mtime, reverse=True)
    for artifact in artifacts:
        name = artifact.name
        group = artifact.parent.relative_to(artifacts_dir).as_posix() or "."
        if not is_snapshot_image(name):
            continue
        baseline = baseline_dir / group
        baseline = baseline / name
        rows.append((group, name, baseline, artifact))

    css = """
body { font-family: -apple-system, Helvetica, Arial, sans-serif; margin: 24px; background: #f7f7f7; }
.header { margin-bottom: 16px; }
.group { margin-top: 28px; }
.card { background: #fff; border-radius: 12px; padding: 16px; margin: 16px 0; box-shadow: 0 3px 18px rgba(0,0,0,0.08); }
.title { font-weight: 600; margin-bottom: 12px; }
.grid { display: grid; grid-template-columns: repeat(3, minmax(220px, 1fr)); gap: 12px; width: 100%; }
.details { margin-top: 12px; }
.details-toggle-row { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; justify-content: space-between; }
.details-content { display: none; margin-top: 12px; }
.details-columns { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; }
.details-column { background: #fafafa; border: 1px solid #eee; border-radius: 10px; padding: 12px; display: flex; flex-direction: column; gap: 8px; }
.label { font-size: 12px; color: #666; margin-bottom: 6px; }
.toggle { margin-top: 8px; font-size: 12px; padding: 6px 10px; border-radius: 8px; border: 1px solid #ddd; background: #f5f5f5; cursor: pointer; }
.html-block { margin: 0; background: #fff; color: #111; padding: 10px; border-radius: 8px; border: 1px solid #e5e5e5; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; white-space: pre-wrap; }
.html-preview { border-radius: 8px; overflow: hidden; border: 1px solid #e5e5e5; }
.html-preview iframe { width: 100%; height: 220px; border: 0; }
.html-render img { width: 100%; height: auto; border-radius: 8px; border: 1px solid #e5e5e5; }
.ocr-block { margin: 8px 0 0; background: #111; color: #eaeaea; padding: 10px; border-radius: 8px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; white-space: pre-wrap; }
img { width: 100%; height: auto; border: 1px solid #eee; background: #fff; border-radius: 6px; }
.path { font-size: 11px; color: #999; word-break: break-all; }
.missing { color: #b00020; font-size: 12px; }
.metrics { font-size: 11px; color: #666; margin-top: 6px; }
.flag { color: #b00020; font-size: 12px; font-weight: 600; margin-top: 6px; }
.test-result { font-size: 12px; font-weight: 600; margin-top: 6px; }
.test-result.passed { color: #2e7d32; }
.test-result.failed { color: #d32f2f; }
.test-result.unknown { color: #6c6c6c; }
"""

    script = """
<script>
function toggleHtml(id) {
  var detail = document.getElementById(id + "-details");
  if (!detail) return;
  var show = (detail.style.display !== "block");
  detail.style.display = show ? "block" : "none";
}
</script>
"""

    parts = ["<!doctype html>", "<html><head><meta charset='utf-8'>", f"<style>{css}</style>", script, "</head><body>"]
    parts.append(
        f"<div class='header'><h2>{html.escape(title)}</h2><div>Artifacts: {html.escape(str(artifacts_dir))}</div></div>"
    )

    current_group = None
    for group, name, baseline, artifact in rows:
        if group != current_group:
            current_group = group
            parts.append(f"<div class='group'><h3>{html.escape(group)}</h3></div>")
        snapshot_id = artifact.stem.split(".", 1)[0]
        lookup_key = snapshot_id.split("-", 1)[0]
        test_status = test_statuses.get(lookup_key)
        parts.append("<div class='card'>")
        parts.append(f"<div class='title'>{html.escape(name)}</div>")
        parts.append("<div class='grid'>")

        base_metrics = image_metrics(baseline) if baseline.exists() else {}
        new_metrics = image_metrics(artifact) if artifact.exists() else {}
        base_name = artifact.stem
        base_ocr = load_ocr_metrics(ocr_dir, base_name, "baseline") if ocr_dir.exists() else None
        new_ocr = load_ocr_metrics(ocr_dir, base_name, "new") if ocr_dir.exists() else None
        if base_ocr:
            base_metrics.update(base_ocr)
        if new_ocr:
            new_metrics.update(new_ocr)
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
        if test_status:
            status_label = test_status.capitalize()
            status_class = "failed" if test_status == "failed" else "passed"
            parts.append(f"<div class='test-result {status_class}'>Test result ({html.escape(snapshot_id)}): {html.escape(status_label)}</div>")
        elif test_log_available:
            parts.append(f"<div class='test-result unknown'>Test result ({html.escape(snapshot_id)}): log recorded but test missing</div>")
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

        parts.append("</div>")  # grid

        html_path = artifact.with_suffix(".html")
        if not html_path.exists():
            html_path = baseline.with_suffix(".html")
        html_id = f"html-{group.replace('/', '_')}-{name}"
        try:
            html_payload = html_path.read_text(encoding="utf-8") if html_path.exists() else ""
        except OSError:
            html_payload = ""
        if not html_payload:
            html_payload = "No HTML input captured for this snapshot."
        iframe_doc = (
            "<!doctype html><html><head><meta charset='utf-8'>"
            f"<style>{BASE_CSS}</style></head><body>"
            f"<div class='snapshot-root'>{html_payload}</div></body></html>"
        )
        parts.append("<div class='details'>")
        parts.append("<div class='details-toggle-row'>")
        parts.append(f"<button class='toggle' onclick=\"toggleHtml('{html_id}')\">Toggle HTML input / preview</button>")
        parts.append("<div class='label'>HTML input + iframe + snapshot</div>")
        parts.append("</div>")
        parts.append(f"<div class='details-content' id='{html_id}-details'>")
        parts.append("<div class='details-columns'>")
        parts.append("<div class='details-column'>")
        parts.append("<div class='label'>HTML Input</div>")
        parts.append(f"<pre id='{html_id}' class='html-block'>{html.escape(html_payload)}</pre>")
        parts.append("</div>")
        parts.append("<div class='details-column'>")
        parts.append("<div class='label'>HTML iframe</div>")
        parts.append(f"<div id='{html_id}-preview' class='html-preview'><iframe srcdoc=\"{html.escape(iframe_doc)}\"></iframe></div>")
        parts.append("</div>")

        ocr_payloads = []
        if baseline.exists():
            ocr_payloads.append(("baseline", run_vision_ocr(baseline)))
        if artifact.exists():
            ocr_payloads.append(("new", run_vision_ocr(artifact)))
        render_path = report_dir / f"render-{group.replace('/', '_')}-{name}"
        if render_html_preview(html_payload, render_path):
            parts.append("<div class='details-column html-render'>")
            parts.append("<div class='label'>Rendered Snapshot</div>")
            parts.append(f"<img src='file://{render_path}' />")
            parts.append("</div>")
            ocr_payloads.append(("html", run_vision_ocr(render_path)))

        parts.append("</div>")  # details-columns

        ocr_lines = []
        for label, payload in ocr_payloads:
            if not payload:
                ocr_lines.append(f"{label}: (ocr unavailable)")
            else:
                ocr_lines.append(f"{label}:\n{payload}")
        if ocr_lines:
            parts.append(f"<pre id='{html_id}-ocr' class='ocr-block'>{html.escape('\\n\\n'.join(ocr_lines))}</pre>")

        parts.append("</div>")  # details-content
        parts.append("</div>")  # details
        parts.append("</div>")  # card

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
    parser.add_argument("--test-log", default="", help="Optional xcodebuild log used to summarize test results")
    args = parser.parse_args()

    artifacts_dir = Path(args.artifacts).resolve()
    baseline_dir = Path(args.baseline).resolve()
    build_report(artifacts_dir, baseline_dir, args.title, args.out_prefix, args.test_log)


if __name__ == "__main__":
    main()
