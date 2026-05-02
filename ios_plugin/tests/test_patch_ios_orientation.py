#!/usr/bin/env python3
import plistlib
import subprocess
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "ios_plugin" / "scripts" / "patch_ios_orientation.py"


def test_patch_sets_iphone_portrait_and_ipad_landscape() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        plist_path = Path(tmp) / "Info.plist"
        with plist_path.open("wb") as f:
            plistlib.dump(
                {
                    "UISupportedInterfaceOrientations": ["UIInterfaceOrientationLandscapeLeft"],
                    "UISupportedInterfaceOrientations~ipad": ["UIInterfaceOrientationLandscapeRight"],
                    "UIDeviceFamily": [1, 2],
                },
                f,
            )

        subprocess.run(["python3", str(SCRIPT), str(plist_path)], check=True)

        with plist_path.open("rb") as f:
            patched = plistlib.load(f)

    assert patched["UISupportedInterfaceOrientations"] == ["UIInterfaceOrientationPortrait"]
    assert patched["UISupportedInterfaceOrientations~ipad"] == [
        "UIInterfaceOrientationLandscapeLeft",
        "UIInterfaceOrientationLandscapeRight",
    ]
    assert patched["UIDeviceFamily"] == [1, 2]


def test_validate_detects_wrong_iphone_orientation() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        plist_path = Path(tmp) / "Info.plist"
        with plist_path.open("wb") as f:
            plistlib.dump(
                {
                    "CFBundlePackageType": "APPL",
                    "UISupportedInterfaceOrientations": ["UIInterfaceOrientationLandscapeLeft"],
                    "UISupportedInterfaceOrientations~ipad": [
                        "UIInterfaceOrientationLandscapeLeft",
                        "UIInterfaceOrientationLandscapeRight",
                    ],
                    "UIDeviceFamily": [1, 2],
                },
                f,
            )

        result = subprocess.run(
            ["python3", str(SCRIPT), "--validate", str(plist_path)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    assert result.returncode != 0
    assert "UISupportedInterfaceOrientations" in result.stderr


def test_directory_mode_ignores_framework_plists() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        build_dir = Path(tmp) / "build" / "ios"
        app_plist = build_dir / "gomoku-Info.plist"
        framework_plist = build_dir / "Frameworks" / "GomokuNeural.framework" / "Info.plist"
        app_plist.parent.mkdir(parents=True)
        framework_plist.parent.mkdir(parents=True)

        with app_plist.open("wb") as f:
            plistlib.dump(
                {
                    "CFBundlePackageType": "APPL",
                    "UISupportedInterfaceOrientations": ["UIInterfaceOrientationLandscapeLeft"],
                    "UISupportedInterfaceOrientations~ipad": ["UIInterfaceOrientationLandscapeRight"],
                    "UIDeviceFamily": [1, 2],
                },
                f,
            )
        with framework_plist.open("wb") as f:
            plistlib.dump({"CFBundlePackageType": "FMWK", "CFBundleName": "GomokuNeural"}, f)

        subprocess.run(["python3", str(SCRIPT), str(build_dir)], check=True)

        with app_plist.open("rb") as f:
            app_data = plistlib.load(f)
        with framework_plist.open("rb") as f:
            framework_data = plistlib.load(f)

    assert app_data["UISupportedInterfaceOrientations"] == ["UIInterfaceOrientationPortrait"]
    assert "UISupportedInterfaceOrientations" not in framework_data
