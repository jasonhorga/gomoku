#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "assets" / "fonts" / "cjk_subset.otf"
SCAN_ROOTS = ("scenes", "scripts")
SCAN_SUFFIXES = {".gd", ".tscn"}
SCAN_FILES = ("project.godot",)
PRUNE_DIRS = {".git", ".godot", "build", "__pycache__"}
PRINTABLE_ASCII = "".join(chr(codepoint) for codepoint in range(0x20, 0x7F))
BASE_CHARS = PRINTABLE_ASCII + "五子棋黑白方玩家对手回合步数平局胜负赢输禁手规则自由开始返回主菜单新对局悔棋复盘上一下一步从头自动播放暂停继续速度即时快普通慢批量进度完成记录就绪不能落子确认取消认输停止等待连接失败服务器创建端口可能被占用检查重试神经网络蒙特卡洛启发搜索随机实验室本地双人电脑人机观看战斗最后一局，。！？：；（）·●○▶"
CJK_RE = re.compile(r"[　-〿㐀-䶿一-鿿＀-￯]")


def iter_text_files(root: Path):
    for root_name in SCAN_ROOTS:
        scan_root = root / root_name
        if not scan_root.exists():
            continue
        for dirpath, dirnames, filenames in os.walk(scan_root):
            dirnames[:] = sorted(name for name in dirnames if name not in PRUNE_DIRS)
            for filename in sorted(filenames):
                path = Path(dirpath) / filename
                if path.suffix in SCAN_SUFFIXES:
                    yield path

    for filename in SCAN_FILES:
        path = root / filename
        if path.is_file():
            yield path


def collect_chars(root: Path) -> str:
    chars = set(BASE_CHARS)
    for path in iter_text_files(root):
        text = path.read_text(encoding="utf-8", errors="ignore")
        chars.update(CJK_RE.findall(text))
    return "".join(sorted(chars))


def write_chars_file(chars: str, path: Path) -> None:
    path.write_text(chars, encoding="utf-8")


def run_pyftsubset(source_font: Path, output_font: Path, chars_file: Path) -> None:
    cmd = [
        "pyftsubset",
        str(source_font),
        f"--output-file={output_font}",
        f"--text-file={chars_file}",
        "--layout-features=*",
        "--glyph-names",
        "--symbol-cmap",
        "--legacy-cmap",
        "--notdef-glyph",
        "--notdef-outline",
        "--recommended-glyphs",
        "--name-IDs=*",
        "--name-legacy",
        "--name-languages=*",
    ]
    try:
        subprocess.run(cmd, check=True)
    except FileNotFoundError:
        raise SystemExit("pyftsubset not found. Install fonttools on the Mac with: python3 -m pip install fonttools")


def font_supports_all(font_path: Path, chars: str) -> list[str]:
    try:
        from fontTools.ttLib import TTFont
    except ModuleNotFoundError:
        raise SystemExit("fontTools not found. Install with: python3 -m pip install fonttools")
    font = TTFont(font_path)
    cmap = set()
    for table in font["cmap"].tables:
        cmap.update(table.cmap.keys())
    return [ch for ch in chars if ord(ch) not in cmap]


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate/check the bundled CJK UI font subset.")
    parser.add_argument("--source-font", type=Path, help="Full CJK source font used to build the subset.")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true", help="Only verify the current output covers scanned UI chars.")
    args = parser.parse_args()

    chars = collect_chars(ROOT)
    chars_file = ROOT / "assets" / "fonts" / "cjk_subset_chars.txt"
    write_chars_file(chars, chars_file)

    if args.check:
        missing = font_supports_all(args.output, chars)
        if missing:
            print("Missing glyphs: " + "".join(missing), file=sys.stderr)
            return 1
        print(f"OK: {args.output} covers {len(chars)} UI glyphs")
        return 0

    if args.source_font is None:
        raise SystemExit("--source-font is required unless --check is used")
    if not args.source_font.exists():
        raise SystemExit(f"source font not found: {args.source_font}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    run_pyftsubset(args.source_font, args.output, chars_file)
    missing = font_supports_all(args.output, chars)
    if missing:
        print("Missing glyphs after subset: " + "".join(missing), file=sys.stderr)
        return 1
    print(f"Generated {args.output} with {len(chars)} UI glyphs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
