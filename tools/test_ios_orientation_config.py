#!/usr/bin/env python3
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]


def test_ios_export_runtime_orientation_uses_sensor() -> None:
    project = (REPO_ROOT / "project.godot").read_text(encoding="utf-8")
    assert "window/handheld/orientation=6" in project


def test_ios_workflow_patches_and_validates_exported_plist() -> None:
    workflow = (REPO_ROOT / ".github" / "workflows" / "ios.yml").read_text(encoding="utf-8")
    export_line = 'godot --headless --export-release "iOS" build/ios/gomoku.ipa'
    patch_line = "python3 ios_plugin/scripts/patch_ios_orientation.py build/ios"
    validate_line = "python3 ios_plugin/scripts/patch_ios_orientation.py --validate build/ios"

    assert export_line in workflow
    assert patch_line in workflow
    assert validate_line in workflow
    assert workflow.index(export_line) < workflow.index(patch_line) < workflow.index(validate_line)


def test_ios_export_preset_does_not_use_ignored_orientation_keys() -> None:
    presets = (REPO_ROOT / "export_presets.cfg").read_text(encoding="utf-8")
    assert "orientation/portrait" not in presets
    assert "orientation/landscape_left" not in presets
    assert "orientation/landscape_right" not in presets
    assert "orientation/portrait_upside_down" not in presets


def test_ios_workflow_validates_final_ipa_orientation_after_fastlane() -> None:
    workflow = (REPO_ROOT / ".github" / "workflows" / "ios.yml").read_text(encoding="utf-8")
    fastlane_line = "run: bundle exec fastlane beta"
    unzip_line = "unzip -q build/ios/gomoku.ipa -d /tmp/gomoku_ipa_check"
    final_validate_line = (
        "python3 ios_plugin/scripts/patch_ios_orientation.py --validate "
        '"$app_plist"'
    )

    assert fastlane_line in workflow
    assert unzip_line in workflow
    assert final_validate_line in workflow
    assert workflow.index(fastlane_line) < workflow.index(unzip_line) < workflow.index(final_validate_line)
