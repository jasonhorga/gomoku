# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    ['onnx_server.py'],
    pathex=[],
    binaries=[],
    datas=[
        ('protocol.py', '.'),
        ('ai', 'ai'),
        # Note: model.onnx is NOT bundled here — it's copied into the
        # .app alongside the binary by build_app.sh, and the server's
        # find_model() looks next to the executable.
    ],
    hiddenimports=[
        'onnxruntime',
        'ai.game_logic',
        'ai.mcts_engine',
        'ai.pattern_eval',
        'ai.vcf_search',
        'ai.vct_search',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='gomoku_ai_server',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
