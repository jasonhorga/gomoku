# 五子棋 Gomoku - 产品升级计划

## Context

当前项目是一个在线双人五子棋（ENet P2P），功能完整但模式单一。升级目标：

1. **单机双人对战** — 同一设备两人轮流下棋
2. **人机对战** — 多难度等级 AI，传统算法足以碾压大多数人
3. **AI vs AI** — 观战模式 + 棋局记录
4. **AI 自我进化** — 神经网络 + 自我对弈训练（AlphaZero 风格）

**技术路线：分两步走**
- Phase 1-4: 纯 GDScript，传统算法 AI (Minimax/MCTS)，权重自我调优，无需 Python，一个可执行文件可分享
- Phase 5: 加 Python AI 服务，神经网络自我进化 (AlphaZero)，开发者训练 → 玩家用预训练模型

## 架构总览

```
Phase 1-4 (纯 Godot):
┌──────────────────────────────────────┐
│            Godot 可执行文件            │
│  渲染 / UI / 联网 / 本地PvP          │
│  GDScript AI Level 1-5 (全内置)       │
│  棋局记录 / AI vs AI 观战             │
│  权重自我调优 (棋局分析→微调评分)       │
└──────────────────────────────────────┘

Phase 5 (加 Python):
┌──────────────────┐    TCP    ┌─────────────────────┐
│   Godot 游戏端    │ ◄──────► │   Python AI 服务端   │
│  + Level 1-5     │          │  PyTorch CNN + MCTS  │
│  + Level 6 入口   │          │  自我对弈 + 训练      │
└──────────────────┘          └─────────────────────┘
```

### Player 抽象层

```
PlayerController (base, RefCounted)
  ├── HumanPlayer      — 本地鼠标点击
  ├── NetworkPlayer    — 远程 RPC (ENet)
  ├── LocalAIPlayer    — GDScript AI, Thread (Level 1-5)
  └── RemoteAIPlayer   — TCP 调用 Python AI (Level 6, Phase 5)
```

### AI 难度层级

| Level | 名称 | 技术 | 预期水平 | 需要 Python |
|-------|------|------|---------|------------|
| 1 | 入门 | 随机 + 近邻优先 | 完全不会下 | 否 |
| 2 | 初级 | 棋型评分 (活四/活三等) | 入门玩家 | 否 |
| 3 | 中级 | Minimax Alpha-Beta 深度2 | 普通玩家 | 否 |
| 4 | 高级 | Minimax 深度4 + 迭代加深 + 置换表 | 业余高手 | 否 |
| 5 | 专家 | MCTS 5000次模拟 + 棋型启发 | 业余强手 | 否 |
| 6 | 大师 | MCTS + CNN (AlphaZero) | 持续进化 | 是 |

Level 1-5 全部纯 GDScript，分享给任何人都能直接玩。Level 6 需要 Python 服务。

## 升级后的文件结构

```
gobang/
  # ── Godot 端 ──
  project.godot
  scripts/
    game_logic.gd                     (不变)
    autoload/
      game_manager.gd                 (重构: GameMode + Player数组)
      network_manager.gd              (不变)
    player/                           (新)
      player_controller.gd
      human_player.gd
      network_player.gd
      local_ai_player.gd              — Thread 包装
      remote_ai_player.gd             — TCP 客户端 (Phase 5)
    ai/                               (新)
      ai_engine.gd                    — 基类
      ai_random.gd                    — Level 1
      ai_heuristic.gd                 — Level 2
      ai_minimax.gd                   — Level 3 & 4
      ai_mcts.gd                      — Level 5
      mcts_node.gd
      pattern_evaluator.gd            — 共享棋型评分
      zobrist.gd                      — 置换表哈希
    net/                              (新, Phase 5)
      ai_service_client.gd            — TCP 客户端
    data/                             (新)
      game_record.gd                  — 棋局序列化
      weight_tuner.gd                 — 棋型权重调优器
  scenes/
    main_menu/                        (修改: 模式菜单)
    lobby/                            (微调)
    game/
      board.gd                        (微调)
      game.gd                         (修改: 多模式UI)
    ai_setup/                         (新)
      ai_setup.gd + .tscn
    ai_lab/                           (新)
      ai_lab.gd + .tscn
  shaders/
    wood_texture.gdshader             (不变)

  # ── Python 端 (Phase 5) ──
  ai_server/
    server.py                         — TCP 服务
    protocol.py
    ai/
      mcts_engine.py                  — MCTS + CNN
      pattern_eval.py
    nn/
      model.py                        — CNN (PyTorch)
      trainer.py                      — 训练循环
      self_play.py                    — 自我对弈
    data/
      weights/                        — 模型权重
    requirements.txt                  — torch, numpy
```

## 实施阶段

### Phase 1: 架构重构 + 单机双人
**目标**: Player 抽象层，本地 PvP 可玩，在线模式不退步

新建:
- `scripts/player/player_controller.gd` — 基类，signal move_decided(row, col)，request_move(logic)，cancel()
- `scripts/player/human_player.gd` — submit_move(row, col) 触发信号
- `scripts/player/network_player.gd` — 监听 NetworkManager.move_received 触发信号

修改:
- `scripts/autoload/game_manager.gd`:
  - 新增 `enum GameMode { ONLINE, LOCAL_PVP, VS_AI, AI_VS_AI }`
  - 新增 `var players: Array = [null, null]` (黑/白 PlayerController)
  - 新增 `setup_online(color)`, `setup_local_pvp()`
  - 重写核心循环: `start_game()` → `_connect_current_player()` → `_on_move_decided()` → 循环
  - 新增 `submit_human_move(row, col)` 供 board.gd 调用
  - 保留所有原有 signal (stone_placed, turn_changed, game_ended, game_reset)
- `scenes/game/board.gd` — `_input()` 中 `try_place_stone()` → `submit_human_move()`
- `scenes/game/game.gd`:
  - 新增 `_configure_for_mode()` 按模式配置 UI
  - LOCAL_PVP: 显示"黑方回合"/"白方回合"而非"你的回合"
  - LOCAL_PVP: "再来一局"直接重置，不走网络握手
- `scenes/main_menu/main_menu.gd + .tscn`:
  - 重构为模式选择菜单: 单机对战 / 人机对战(暂disabled) / 在线对战 / AI实验室(暂disabled) / 退出
  - 在线对战点击后展开 Host/Join 子面板

验证:
- 在线 Host/Join 完整对局回归
- 本地 PvP 黑白交替下棋，胜负判定，再来一局

### Phase 2: GDScript AI (Level 1-3)
**目标**: 可以和 AI 下棋

新建:
- `scripts/ai/ai_engine.gd` — 基类，`choose_move(board: Array, current_player: int, move_history: Array) -> Vector2i`
- `scripts/ai/ai_random.gd` — 收集已有棋子2格内空位，随机选一个
- `scripts/ai/pattern_evaluator.gd`:
  - 棋型识别: 4方向扫描，分类为 five/open_four/half_four/open_three/half_three/open_two/half_two
  - 评分表: five=100000, open_four=10000, half_four=1000, open_three=1000, half_three=100, open_two=100, half_two=10
  - `score_cell(board, row, col, player) -> float` 单格攻防评分
  - `evaluate_board(board, player) -> float` 全局评分(Minimax用)
  - 防守权重 1.1x (优先堵对方)
- `scripts/ai/ai_heuristic.gd` — 遍历所有近邻空位，score_cell 取最高
- `scripts/ai/ai_minimax.gd`:
  - Alpha-Beta 搜索，可配置深度
  - 候选走法: 距已有棋子 Manhattan 距离 ≤ 2 的空位 (20-40个)
  - 走法排序: 先按 score_cell 降序 (剪枝效率)
  - 即时胜负检测: 有必胜走法直接返回
  - Level 3 = depth 2
- `scripts/player/local_ai_player.gd`:
  - 持有 AIEngine 实例
  - request_move() 启动 Thread
  - Thread 内调用 engine.choose_move()
  - 完成后 call_deferred 发射 move_decided
  - cancel() 设 _cancelled 标志 + wait_to_finish()
  - **关键**: 搜索用 board 深拷贝，不影响显示状态
- `scenes/ai_setup/ai_setup.gd + .tscn`:
  - 选颜色: 黑(先手) / 白(后手)
  - 选难度: Level 1-3 (后续 Phase 解锁更多)
  - 开始按钮

修改:
- `scripts/autoload/game_manager.gd` — 新增 `setup_vs_ai(human_color, level)`
- `scenes/main_menu/main_menu.gd` — 启用"人机对战"按钮，跳转 ai_setup 场景
- `scenes/game/game.gd` — VS_AI 模式: 对方回合显示"AI 思考中..."

验证:
- 人 vs Level 1: AI 随机但不放边角
- 人 vs Level 2: AI 能堵活三，能连子
- 人 vs Level 3: AI 有攻防策略，< 1秒响应
- 所有 level UI 不卡顿 (Thread)

### Phase 3: 高级 AI (Level 4-5)
**目标**: 有挑战性的 AI 对手

新建:
- `scripts/ai/zobrist.gd`:
  - 预生成 `table[15][15][3]` 随机数 (seed=42 确定性)
  - `update(row, col, piece)` XOR 更新
  - 用于 Minimax 置换表
- `scripts/ai/mcts_node.gd`:
  - parent, children, move, player, visits, wins, untried_moves
  - `ucb1(exploration) -> float` = wins/visits + C * sqrt(ln(parent.visits)/visits)
- `scripts/ai/ai_mcts.gd`:
  - 5000 次模拟 (Thread 中运行)
  - Selection: UCB1 选子节点
  - Expansion: 展开一个未尝试的走法
  - Simulation: 半随机 rollout (有活四必下，有活三必堵/下，否则近邻随机)
  - Backpropagation: 更新 visits/wins
  - 最终选 visits 最多的子节点

修改:
- `scripts/ai/ai_minimax.gd`:
  - Level 4 配置: depth=4, 启用迭代加深 + 置换表
  - 迭代加深: 先搜 depth 1→2→3→4，用前一层最佳走法做下一层第一候选
  - 置换表: Dictionary<int(zobrist_hash), {depth, score, flag, best_move}>
  - Aspiration window: 窄窗搜索，失败则全窗重搜
  - Killer move 启发: 每层记录2个最佳非捕获走法
- `scenes/ai_setup/ai_setup.gd` — 增加 Level 4-5 选项

验证:
- Level 4 (Minimax depth 4): < 3秒响应，能设陷阱(双活三/冲四活三)
- Level 5 (MCTS 5000次): 2-5秒响应，战略性强
- 对人类玩家有明显挑战性

### Phase 4: AI vs AI + 棋局记录 + 权重自我调优
**目标**: 观战模式 + 数据收集 + Level 2-5 通过棋局分析自动变强

新建:
- `scripts/data/game_record.gd`:
  - 属性: timestamp, mode, black_type, white_type, moves: Array[Vector2i], result, total_moves
  - `to_json() -> String` / `from_json(s) -> GameRecord`
  - 存储到 `user://game_records/YYYYMMDD_HHMMSS.json`
- `scripts/data/weight_tuner.gd`:
  - 分析棋局记录，统计每种棋型 (活四/活三/...) 在胜局 vs 败局中的出现频率
  - 胜局中高频出现的棋型 → 权重上调; 败局中高频 → 权重下调
  - 学习率 0.02，渐进式微调
  - `tune_from_records(records: Array[GameRecord]) -> Dictionary` 返回新权重
  - `run_tournament(weights_a, weights_b, games: int) -> Dictionary` 两套权重对弈验证
- `scenes/ai_lab/ai_lab.gd + .tscn`:
  - AI 对战观看:
    - 黑方 AI Level 选择 (1-5)
    - 白方 AI Level 选择 (1-5)
    - 速度控制: 慢(2s) / 正常(0.5s) / 快(0.1s) / 瞬间(0)
    - 开始/暂停/停止
  - 权重训练面板:
    - 批量对弈: 选择局数 (10-500) + AI Level → 运行
    - 进度条 + 实时胜率统计
    - "优化权重"按钮: 从棋局记录调优 → 显示前后权重对比
    - "重置为默认"按钮
  - 棋局统计: 总对局数、各 Level 胜率
  - 棋局回放: 选择历史棋局，逐步回放

修改:
- `scripts/autoload/game_manager.gd`:
  - 新增 `setup_ai_vs_ai(level_black, level_white)`
  - 新增 `var ai_move_delay: float = 0.5`
  - _on_move_decided() 中: AI_VS_AI 模式下 await 延迟后再请求下一步
  - 新增 `_save_game_record()` 游戏结束时自动保存
- `scripts/ai/pattern_evaluator.gd`:
  - 新增 `load_weights(path)` / `save_weights(path)` — 从 `user://ai_weights/pattern_weights.json` 加载/保存
  - _init() 时自动检查并加载已有权重文件，无则用默认值
- `scenes/game/game.gd`:
  - AI_VS_AI 模式: 显示"黑方(Level X) vs 白方(Level Y)"，无投降按钮
  - 速度控制 slider
  - 自动开始下一局选项
- `scenes/main_menu/main_menu.gd` — 启用"AI实验室"入口

权重调优流程 (纯 GDScript):
```
1. AI 实验室: 批量运行 100 局 Level 4 vs Level 4
2. 所有棋局自动保存为 JSON
3. 用户点击"优化权重":
   - WeightTuner 分析棋局，统计棋型-胜负相关性
   - 生成新权重 (活四可能从 10000 → 10200, 活三从 1000 → 1050...)
   - 新权重 vs 旧权重对弈 50 局验证
   - 新权重胜率 > 55% → 保存; 否则丢弃
4. 下次 AI 对局自动使用新权重 → Level 2-5 全部变强
```

验证:
- AI vs AI 观战完整对局，速度控制正常
- 棋局自动保存为 JSON，可读取回放
- 批量对弈 100 局 → 优化权重 → 验证新权重比默认权重胜率提升
- 至此游戏可作为完整产品分享 (一个可执行文件，Level 1-5 全内置，可自我优化)

### Phase 5: 神经网络自我进化 (Python)
**目标**: AlphaZero 风格 AI 训练 + 持续进化

新建 (Python):
- `ai_server/server.py` — asyncio TCP server (localhost:9877)，处理 move/train/status 指令
- `ai_server/protocol.py` — JSON 消息协议
- `ai_server/ai/mcts_engine.py` — MCTS + CNN 评估 (替代随机 rollout)
- `ai_server/ai/pattern_eval.py` — Python 版棋型评估 (NumPy)
- `ai_server/nn/model.py`:
  - PyTorch CNN: 输入 15×15×2 (黑子层+白子层)
  - → Conv2D(32, 3×3) + BN + ReLU × 3 层
  - → 策略头: Conv2D(1) → FC(225) → Softmax (落子概率)
  - → 价值头: Conv2D(1) → FC(64) → FC(1) → Tanh (局面评分 -1~+1)
- `ai_server/nn/self_play.py`:
  - 用当前模型 MCTS 自我对弈
  - 每步记录 (board_state, mcts_search_probabilities, eventual_winner)
  - 每局生成 ~100 个训练样本
- `ai_server/nn/trainer.py`:
  - 加载自我对弈数据
  - Loss = 策略交叉熵 + 价值 MSE + L2正则
  - Adam optimizer, lr=0.001
  - 训练若干 epoch → 保存新权重
- `ai_server/requirements.txt` — torch, numpy
- `ai_server/run.sh` — 启动脚本

新建 (Godot):
- `scripts/net/ai_service_client.gd` — StreamPeerTCP 连接 Python，JSON 收发，连接状态管理
- `scripts/player/remote_ai_player.gd` — 通过 TCP 请求 Python AI 落子

修改:
- `scenes/ai_setup/ai_setup.gd` — 增加 Level 6 选项，显示 Python 连接状态
- `scenes/ai_lab/ai_lab.gd` — 训练面板: 选择训练局数、查看训练进度、代数、模型对比胜率

自我进化流程:
```
初始化: 随机 CNN 权重 (第0代)
循环:
  1. 用当前模型 MCTS 自我对弈 200 局
  2. 收集训练数据 (~20000 个 state/policy/value 样本)
  3. 训练 CNN (10 epochs)
  4. 新模型 vs 旧模型对弈 50 局
     → 新模型胜率 > 55% → 保存为新一代
     → 否则 → 丢弃，继续用旧模型
  5. 回到步骤 1
```

验证:
- Python 服务启动，Godot 能连接
- Level 6 对局正常，CNN + MCTS 能返回合理落子
- 训练 3 代后，新模型 vs 第0代胜率明显提升
- 训练好的模型权重可导出，分享给其他玩家使用

## 开发环境与协作

### 双机协作 (Google Drive 共享目录)

项目目录通过 Google Drive 在两台机器间同步，无需 git/scp：

```
Google Drive: gobang/
  ├── Godot 代码 + 场景          ← Linux 上开发
  ├── ai_server/                 ← Linux 上写代码
  │   ├── train_pipeline.py      ← MacBook 上运行
  │   └── data/weights/          ← MacBook 训练输出，自动同步回 Linux
  └── build/                     ← Linux 上 Godot 编译
```

| 机器 | 配置 | 职责 |
|------|------|------|
| Linux (Claude Code) | 1核/4GB/无GPU | 写代码、Phase 1-4 测试、Godot 编译 |
| MacBook Air M5 (用户) | M5/32GB/MPS | Phase 5 CNN 训练 (PyTorch MPS 加速) |

### Phase 5 训练流程

```
Linux:                              MacBook:
  我写好 train_pipeline.py             你打开终端:
  (自动同步到 MacBook)                   cd gobang/ai_server
       │                               pip install -r requirements.txt
       │    Google Drive 自动同步        python train_pipeline.py --gen 10
       │                                     │ (跑一晚上)
       │                                     ↓
       │                               data/weights/gen_10.pt 生成
       │    Google Drive 自动同步             │
       │ ◄─────────────────────────────────┘
       ↓
  我看到 gen_10.pt，直接加载测试
  打包进 Godot 游戏发布
```

MacBook M5 训练估算:
- PyTorch MPS 后端加速，CNN 推理 ~0.5-1ms
- 一代训练 (200 局自我对弈 + CNN 训练): ~1-2 小时
- 10 代迭代: ~一晚上

### 不需要在 MacBook 上装 Claude Code
- train_pipeline.py 是全自动脚本，跑起来就不用管
- 日志输出到 `ai_server/logs/` (也会同步)
- 出问题了你贴日志给我看就行

## 部署策略

### Phase 1-4 完成后 (给朋友玩):
- 导出一个 Godot 可执行文件 (Linux/macOS)
- Level 1-5 全内置，无需安装任何东西
- 支持单机PvP、人机对战、在线对战、AI观战、AI权重自我调优

### Phase 5 完成后 (最强AI):
- 训练好的 CNN 权重打包进 Godot 游戏
- 玩家不需要 Python，Level 6 使用预训练模型做推理
- GDScript 实现轻量 CNN 前向传播 (小模型可接受)
- 或者: 玩家可选连接云端 AI 服务获取最新最强模型

## 关键设计决策

| 决策 | 理由 |
|------|------|
| Level 1-5 纯 GDScript | Phase 4 结束即可分享，无外部依赖 |
| Level 6 走 Python 训练 | 神经网络需要 PyTorch + MPS/GPU 加速 |
| Google Drive 共享 | 双机协作零配置，训练结果自动同步 |
| 分两步走 | 降低风险，Phase 4 已是完整产品 |
| TCP JSON 通信 | 简单、可调试、可扩展为远程服务 |
| GameLogic 不变 | 纯逻辑层干净不动 |
| NetworkManager 不变 | 最小化在线对战回归风险 |
| 训练/推理分离 | 开发者训练，玩家只用预训练模型 |

## 验证方式

Phase 1-2 (Linux, Godot headless):
1. 在线 Host/Join 回归测试
2. 本地 PvP 端到端
3. 人 vs GDScript AI (Level 1-3)

Phase 3-4 (Linux, Python):
1. Python AI vs AI 批量对弈 (无需 Godot)
2. 权重调优验证: 优化后胜率 > 默认权重
3. Godot 加载调优后的权重，Level 2-5 变强
4. AI 实验室 UI 完整流程

Phase 5 (MacBook 训练, Linux 集成):
1. MacBook: `python train_pipeline.py` 完整运行
2. Linux: 加载训练好的权重，Level 6 对局正常
3. 训练 3 代后，新模型 vs 第0代胜率明显提升
4. 预训练权重打包进 Godot 可执行文件
