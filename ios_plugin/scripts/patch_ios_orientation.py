#!/usr/bin/env python3
import argparse
import plistlib
import sys
from pathlib import Path

IPHONE_ORIENTATIONS = ["UIInterfaceOrientationPortrait"]
IPAD_ORIENTATIONS = [
    "UIInterfaceOrientationLandscapeLeft",
    "UIInterfaceOrientationLandscapeRight",
]


def _plist_paths(path: Path) -> list[Path]:
    if path.is_file():
        return [path]
    if path.is_dir():
        app_plists: list[Path] = []
        for plist_path in sorted(path.rglob("*.plist")):
            try:
                data = _load(plist_path)
            except Exception:
                continue
            if data.get("CFBundlePackageType") == "APPL":
                app_plists.append(plist_path)
        return app_plists
    raise SystemExit(f"path not found: {path}")


def _load(path: Path) -> dict:
    with path.open("rb") as f:
        return plistlib.load(f)


def _save(path: Path, data: dict) -> None:
    with path.open("wb") as f:
        plistlib.dump(data, f)


def _patch(path: Path) -> None:
    data = _load(path)
    data["UISupportedInterfaceOrientations"] = IPHONE_ORIENTATIONS
    data["UISupportedInterfaceOrientations~ipad"] = IPAD_ORIENTATIONS
    _save(path, data)
    print(f"patched iOS orientations in {path}")


def _validate(path: Path) -> list[str]:
    data = _load(path)
    errors: list[str] = []
    if data.get("UISupportedInterfaceOrientations") != IPHONE_ORIENTATIONS:
        errors.append(
            f"{path}: UISupportedInterfaceOrientations={data.get('UISupportedInterfaceOrientations')!r}"
        )
    if data.get("UISupportedInterfaceOrientations~ipad") != IPAD_ORIENTATIONS:
        errors.append(
            f"{path}: UISupportedInterfaceOrientations~ipad={data.get('UISupportedInterfaceOrientations~ipad')!r}"
        )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Patch Godot's exported iOS Info.plist orientation lists."
    )
    parser.add_argument("path", help="Info.plist file or directory containing exported plist files")
    parser.add_argument("--validate", action="store_true", help="validate only; do not modify files")
    args = parser.parse_args()

    paths = _plist_paths(Path(args.path))
    if not paths:
        print(f"no Info.plist found under {args.path}", file=sys.stderr)
        return 1

    if args.validate:
        errors: list[str] = []
        for path in paths:
            errors.extend(_validate(path))
        if errors:
            print("\n".join(errors), file=sys.stderr)
            return 1
        print(f"validated iOS orientations in {len(paths)} plist file(s)")
        return 0

    for path in paths:
        _patch(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
