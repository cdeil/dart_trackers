# ------------------------------------------------------------------------
# Trackers
# Copyright (c) 2026 Roboflow. All Rights Reserved.
# Licensed under the Apache License, Version 2.0 [see LICENSE for details]
# ------------------------------------------------------------------------

import argparse
import ast
import json
import tokenize
from collections.abc import Callable
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DART_ROOT = REPO_ROOT / "dart_trackers"


@dataclass(frozen=True)
class Category:
    label: str
    files: tuple[Path, ...]
    note: str = ""


PYTHON_CATEGORIES = {
    "numpy_linalg_replacement": Category(
        "NumPy / linalg replacement",
        (),
        "Provided by NumPy in Python; implemented in Dart as matrix.dart.",
    ),
    "scipy_assignment_replacement": Category(
        "SciPy assignment replacement",
        (),
        "Provided by scipy.optimize.linear_sum_assignment in Python; implemented in Dart.",
    ),
    "support": Category(
        "Detection / IoU / state support",
        (
            REPO_ROOT / "src/trackers/utils/converters.py",
            REPO_ROOT / "src/trackers/utils/iou.py",
            REPO_ROOT / "src/trackers/utils/state_representations.py",
            REPO_ROOT / "src/trackers/utils/base_tracklet.py",
        ),
    ),
    "kalman": Category(
        "Kalman filter",
        (REPO_ROOT / "src/trackers/utils/kalman_filter.py",),
    ),
    "sort": Category(
        "SORT tracker",
        tuple(sorted((REPO_ROOT / "src/trackers/core/sort").glob("*.py"))),
    ),
    "bytetrack": Category(
        "ByteTrack tracker",
        tuple(sorted((REPO_ROOT / "src/trackers/core/bytetrack").glob("*.py"))),
    ),
    "ocsort": Category(
        "OC-SORT tracker",
        tuple(sorted((REPO_ROOT / "src/trackers/core/ocsort").glob("*.py"))),
    ),
    "botsort": Category(
        "BoT-SORT tracker",
        tuple(
            path
            for path in sorted((REPO_ROOT / "src/trackers/core/botsort").glob("*.py"))
            if path.name not in {"cmc.py", "_cmc_xyxy.py"}
        ),
        "CMC implementation excluded because the Dart package intentionally omits runtime CMC.",
    ),
    "tests": Category(
        "Relevant Python tests",
        (
            REPO_ROOT / "tests/core/test_associated_indices.py",
            REPO_ROOT / "tests/core/test_trackers.py",
            REPO_ROOT / "tests/core/test_tracklets.py",
        ),
        "Representative upstream tests for tracker behavior; dataset/eval tests excluded.",
    ),
    "cli": Category(
        "Dart JSONL demo CLI",
        (),
        "No Python equivalent; Python owns video rendering in the demo workflow.",
    ),
}


DART_CATEGORIES = {
    "numpy_linalg_replacement": Category(
        "NumPy / linalg replacement",
        (DART_ROOT / "lib/src/matrix.dart",),
    ),
    "scipy_assignment_replacement": Category(
        "SciPy assignment replacement",
        (DART_ROOT / "lib/src/assignment.dart",),
    ),
    "support": Category(
        "Detection / IoU / state support",
        (
            DART_ROOT / "lib/src/detections.dart",
            DART_ROOT / "lib/src/iou.dart",
            DART_ROOT / "lib/src/cmc.dart",
            DART_ROOT / "lib/src/tracker.dart",
        ),
    ),
    "kalman": Category(
        "Kalman filter",
        (DART_ROOT / "lib/src/kalman_filter.dart",),
    ),
    "sort": Category(
        "SORT tracker",
        (DART_ROOT / "lib/src/sort_tracker.dart",),
    ),
    "bytetrack": Category(
        "ByteTrack tracker",
        (DART_ROOT / "lib/src/bytetrack_tracker.dart",),
    ),
    "ocsort": Category(
        "OC-SORT tracker",
        (DART_ROOT / "lib/src/ocsort_tracker.dart",),
    ),
    "botsort": Category(
        "BoT-SORT tracker",
        (DART_ROOT / "lib/src/botsort_tracker.dart",),
        "Pure Dart no-CMC tracker slice.",
    ),
    "tests": Category(
        "Dart tests and conformance",
        tuple(path for path in sorted((DART_ROOT / "test").glob("*.dart")) if not path.name.endswith(".g.dart"))
        + tuple(sorted((DART_ROOT / "conformance/python").glob("*.py"))),
        "Generated fixture Dart source is excluded.",
    ),
    "cli": Category(
        "Dart JSONL demo CLI",
        (DART_ROOT / "bin/track_json.dart",),
    ),
}


def python_sloc(path: Path) -> int:
    source = path.read_text()
    docstring_lines = _python_docstring_lines(source)
    counted: set[int] = set()
    tokens = tokenize.tokenize(BytesIO(source.encode()).readline)
    for token in tokens:
        if token.type in {
            tokenize.ENCODING,
            tokenize.ENDMARKER,
            tokenize.NL,
            tokenize.NEWLINE,
            tokenize.INDENT,
            tokenize.DEDENT,
            tokenize.COMMENT,
        }:
            continue
        start, end = token.start[0], token.end[0]
        for line in range(start, end + 1):
            if line not in docstring_lines:
                counted.add(line)
    return len(counted)


def _python_docstring_lines(source: str) -> set[int]:
    lines: set[int] = set()
    tree = ast.parse(source)
    for node in ast.walk(tree):
        body = getattr(node, "body", None)
        if not isinstance(body, list) or not body:
            continue
        first = body[0]
        if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) and isinstance(first.value.value, str):
            end = getattr(first, "end_lineno", first.lineno)
            lines.update(range(first.lineno, end + 1))
    return lines


def dart_sloc(path: Path) -> int:
    in_block_comment = False
    count = 0
    for raw_line in path.read_text().splitlines():
        line = raw_line
        output = []
        i = 0
        in_string: str | None = None
        while i < len(line):
            ch = line[i]
            nxt = line[i + 1] if i + 1 < len(line) else ""
            if in_block_comment:
                if ch == "*" and nxt == "/":
                    in_block_comment = False
                    i += 2
                else:
                    i += 1
                continue
            if in_string is not None:
                output.append(ch)
                if ch == "\\":
                    if i + 1 < len(line):
                        output.append(line[i + 1])
                        i += 2
                        continue
                elif ch == in_string:
                    in_string = None
                i += 1
                continue
            if ch in {"'", '"'}:
                in_string = ch
                output.append(ch)
                i += 1
                continue
            if ch == "/" and nxt == "/":
                break
            if ch == "/" and nxt == "*":
                in_block_comment = True
                i += 2
                continue
            output.append(ch)
            i += 1
        if "".join(output).strip():
            count += 1
    return count


def category_report(categories: dict[str, Category], counter: Callable[[Path], int]) -> dict[str, dict[str, object]]:
    report: dict[str, dict[str, object]] = {}
    for key, category in categories.items():
        files = [path for path in category.files if path.exists()]
        file_counts = {str(path.relative_to(REPO_ROOT)): counter(path) for path in files}
        report[key] = {
            "label": category.label,
            "sloc": sum(file_counts.values()),
            "files": file_counts,
            "note": category.note,
        }
    return report


def render_markdown(report: dict[str, object]) -> str:
    py = report["python"]  # type: ignore[index]
    dart = report["dart"]  # type: ignore[index]
    lines = [
        "# Source line count report",
        "",
        "Generated by `python tool/sloc_report.py --format markdown`.",
        "",
        "| Category | Python SLOC | Dart SLOC | Dart / Python | Notes |",
        "|---|---:|---:|---:|---|",
    ]
    for key in DART_CATEGORIES:
        py_item = py[key]  # type: ignore[index]
        dart_item = dart[key]  # type: ignore[index]
        py_sloc = py_item["sloc"]
        dart_sloc = dart_item["sloc"]
        ratio = "n/a" if py_sloc == 0 else f"{dart_sloc / py_sloc:.2f}x"
        note = dart_item.get("note") or py_item.get("note") or ""
        lines.append(f"| {dart_item['label']} | {py_sloc} | {dart_sloc} | {ratio} | {note} |")
    lines.extend(
        [
            "",
            "## Included files",
            "",
            "### Python",
            "",
        ]
    )
    lines.extend(_render_files(py))
    lines.extend(["", "### Dart", ""])
    lines.extend(_render_files(dart))
    return "\n".join(lines) + "\n"


def _render_files(section: dict[str, dict[str, object]]) -> list[str]:
    lines: list[str] = []
    for item in section.values():
        lines.append(f"#### {item['label']}")
        files = item["files"]
        if not files:
            lines.append("- none; external dependency or not implemented")
        else:
            for file_path, count in files.items():
                lines.append(f"- `{file_path}`: {count}")
        if item.get("note"):
            lines.append(f"- Note: {item['note']}")
        lines.append("")
    return lines


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--format", choices=["json", "markdown"], default="json")
    args = parser.parse_args()

    report = {
        "python": category_report(PYTHON_CATEGORIES, python_sloc),
        "dart": category_report(DART_CATEGORIES, dart_sloc),
    }
    if args.format == "json":
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(render_markdown(report), end="")


if __name__ == "__main__":
    main()
