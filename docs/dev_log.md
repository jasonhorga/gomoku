## Project Overview

五子棋 (Gomoku) - Godot 4.2.2 在线双人对战游戏，经典木纹棋盘风格。

> **这份文档只覆盖到 2026-04-09（游戏 v1 发布）。后续的 AI 开发 / 模型训练 / 重命名 / iOS CI 都在 [`ai_journey.md`](./ai_journey.md)。**

## Planning Phase (2026-04-09)

用户最初被提供了 HTML/CSS/JS、React、Vue 三个选项，但选择了 **Godot 引擎**。
关键决策：
- 引擎：Godot 4.x + GDScript
- 对战模式：在线双人（ENet P2P，一人 Host 一人 Join）
- UI 风格：经典木纹棋盘
- 棋盘：标准 15x15

架构设计：
- 两个 Autoload 单例：`NetworkManager`（连接管理）和 `GameManager`（游戏逻辑桥接）
- 纯逻辑类 `GameLogic`（RefCounted，非 Node）
- 棋盘用单个 Node2D 的 `_draw()` 渲染，不用 225 个 Sprite 节点
- 木纹通过 gdshader 程序化生成，无需外部图片资源
- RPC 同步落子（回合制游戏不需要 MultiplayerSynchronizer）

## Implementation Phase

### 文件结构
```
project.godot
scripts/game_logic.gd          — 纯游戏逻辑
scripts/autoload/network_manager.gd — ENet 网络
scripts/autoload/game_manager.gd    — 游戏状态桥接
scenes/main_menu/               — 主菜单（Host/Join/Quit）
scenes/lobby/                   — 等待房间
scenes/game/board.gd + board.tscn — 棋盘渲染
scenes/game/game.gd + game.tscn   — 游戏主场景
scenes/game_over/               — 游戏结束
shaders/wood_texture.gdshader   — 木纹着色器
export_presets.cfg              — 导出配置
```

### 编译环境
- 服务器：Ubuntu 24.04 x86_64 (AWS)
- Godot：从 GitHub releases 下载 4.2.2-stable linux.x86_64
- 导出模板：Godot_v4.2.2-stable_export_templates.tpz (~854MB)
- 模板安装路径：`~/.local/share/godot/export_templates/4.2.2.stable/`

## Bugs & Fixes

### Bug 1: GameLogic class_name 未被识别
**现象：** `--import` 时报 `Identifier "GameLogic" not declared in the current scope`，导致 network_manager.gd 和 game_manager.gd 加载失败。
**原因：** `game_logic.gd` 中的 `class_name GameLogic` 在 headless 导入模式下没有被 autoload 脚本正确发现（加载顺序问题）。
**修复：** 所有引用 `GameLogic` 的脚本改为用 `const _GameLogic = preload("res://scripts/game_logic.gd")` 显式加载，避免依赖全局 class_name 解析。
**涉及文件：** network_manager.gd, game_manager.gd, board.gd, game.gd

### Bug 2: 棋盘线和棋子不可见
**现象：** 用户反馈"没有棋盘的线，下了子也看不到"，但联网功能正常。
**原因：** board.tscn 中 `WoodBackground`（ColorRect）是 Board（Node2D）的子节点。Godot 渲染顺序是先父节点 `_draw()` 再子节点，所以木纹背景把所有 `_draw()` 绘制的内容（网格线、棋子、标记）全部覆盖了。
**修复：** 在 board.tscn 的 WoodBackground 节点上添加 `show_behind_parent = true`，使其渲染在父节点 `_draw()` 内容之后。

### 非 Bug：macOS 导出失败
**现象：** `--export-release "macOS"` 报 "configuration errors" 但不显示具体错误。
**原因：** Godot 4.2 的 macOS 导出在非 macOS 平台上的 preset 配置要求不明确，错误信息被截断。
**绕过方案：** 手动组装 .app 包：
1. 用 Linux preset 导出 .pck 文件
2. 解压 macOS 导出模板 (macos.zip → macos_template.app)
3. 重命名可执行文件，替换 Info.plist，放入 .pck
4. 打包为 zip

## Deployment

### 文件托管尝试
| 平台 | 结果 |
|------|------|
| Python http.server + 公网 IP | 启动成功但端口可能被 AWS 安全组拦截 |
| file.io | 301 重定向，上传失败 |
| transfer.sh | 连接失败（服务不可用） |
| 0x0.st | 拒绝上传（称 AI 垃圾太多） |
| catbox.moe | 上传显示成功但实际文件 content-length=0 |
| **tmpfiles.org** | **成功**，约 1 小时有效期 |

### 构建产物
- `build/gomoku.x86_64` — Linux 可执行文件 (60MB, PCK 嵌入)
- `build/gomoku_macos.zip` — macOS Universal (arm64+x86_64) .app 包 (46MB)

## Current Status (2026-04-09)
- 联网功能：✅ 已验证可用
- 棋盘渲染：✅ 已修复（show_behind_parent）
- macOS M芯片版：✅ 已构建并上传
- 未签名，macOS 需要 `xattr -cr Gobang.app` 或右键打开

---

## Phase Recap 2026-04-10 → 2026-04-26

详细流水见 `ai_journey.md`，这里是简版。

### 网络训练
- 2026-04-10/11：v1 RL 失败（冷启动不可行），改 v2 SL bootstrap
- 2026-04-12：bootstrap 48f/3b，loss 5.3 → 1.5 通过
- 2026-04-13：iterate v4 48f/3b → `iter_3.pt`（48f/3b 天花板）
- 2026-04-14/15：升级 128f/6b，bootstrap loss → 1.05；iterate 一夜 → **`big_iter_1.pt` = 当前生产 best_model**（66.9% vs bootstrap）
- 2026-04-16：加分裂三/分裂四 pattern detection（**big_iter_1 训出来时还没这能力**）
- 2026-04-25：Path A 加 minimax adversarial 训练失败（recipe 错，30% vs baseline）

### iOS / macOS 部署
- 2026-04-15：macOS 签名 + 公证 OK
- 2026-04-17：iOS TestFlight 通过
- 2026-04-18：iPhone 真机验证
- 2026-04-21：**Swift 插件统一**——iOS + macOS 都跑 Swift + CoreML，删掉 Python TCP server 和 GDScript MCTS
- 2026-04-25：AI Lab 颜色轮换、iOS 看门狗崩溃修复 (P3s)
- 2026-04-25：中文 UI + 字体 (P3v/P3w/P3x)，bundled Noto Sans CJK SC subset 60KB

### 仓库
- 2026-04-26：废除"双目录" workaround——`/home/ubuntu/claude-web-data/hejia/gomoku/` 是单一 git checkout，Drive sync 处理 Mac 同步
- 2026-04-26：swift-ml-plugin → main 合并；51 commits ahead 归零

### 当前已知问题 / 改进路径

| 问题 | 严重度 | 路径 |
|---|---|---|
| best_model 不认分裂三/四 | 中 | 用现 pattern_eval 重新 bootstrap+iterate 一晚 |
| L4 minimax fork 攻势防不住（65-90% L6 vs L4）| 中 | 上面同条 + Lambda-2 threat search |
| 无禁手对战不平衡（黑必胜）| 低 | Path B：加禁手模式 (~3 天) |
| 网络架构 128f/6b 已 plateau | 低 | 升级 192f/8b 或 distill from Rapfi |

完整改进路径见 `docs/retrain_plan.md` + `docs/gomoku_research.md`。

### 下一阶段建议

短期（一晚）：用现在 pattern_eval（包含 split detection）从 `bootstrap_128f6b.pt` 重新 iterate，**纯 self-play 严格按 ai_journey 验证过的配方**。预期产出：识别分裂攻击的 best_model v2，~+50-100 ELO。

中期（一周）：实现 Lambda-2 threat search 在 MCTS 之上，或者 distill Rapfi 当 teacher。

长期：禁手模式 (Path B) 作为独立 feature；Mixnet 移植作为高投入实验。

