# Gomoku 模型重训详细 Plan

## 现状回顾

**问题诊断**（来自 2026-04-25 的 Mac/Python 测试）：
- L6 (128f/6b CNN, 200 sims hybrid 0.5) vs L4 (minimax-d4 + TT + killer) = 65-90%
- 系统性弱点：L4 在中盘建立"双重威胁 fork"（如反对角 + row 10 + 列 6 同时威胁）时，L6 不能阻止
- 关键测试位置：move 22 之后 CNN value 从 -0.576 突降 -0.999，**8000 sims 仍救不了**
- 这不是 sims 不够，也不是 CNN 推理 bug，是**模型缺乏 anti-fork 训练数据**

**结论**：当前模型在自我对弈数据上学了"如何赢"，但很少见到"如何防御 minimax 风格的多重威胁"。

**禁手 (Renju) 角度**：
- 加禁手后黑方先手优势被削弱 → 双重威胁攻击难以同时构造（双三禁手）→ 局面更平衡 → L4 minimax 的 fork 战术可能失效
- 但也可能让 L6 在禁手模式下需要新的策略

**决定**：训练**两组**模型，独立做：

1. **强化版自由对局模型 (Free)** — 修复 L6 vs L4 的 fork 弱点
2. **禁手模型 (Renju)** — 支持禁手规则

它们要求不同的训练数据和验证标准。

---

## 训练目标对比

| 维度 | 当前 best_model | Free v2 (新) | Renju v1 (新) |
|---|---|---|---|
| 架构 | 128f / 6b (361k params) | 128f / 6b 或 192f / 8b | 128f / 6b |
| 训练数据 | 自我对弈 (CNN+MCTS) | 自我对弈 + L4 minimax 对抗数据 | 禁手自我对弈 |
| 输入特征 | 9 channel | 9 channel | 10 channel（+禁手 mask） |
| 棋力目标 | (基线) | vs L4 ≥ 90% (Mac), 双重威胁 fork 不再必输 | vs L4 (禁手版) ≥ 70% |
| 验证 | 现有 | benchmark fork 局型 | 禁手特殊局型 |

---

## 路径 A：强化 Free 模型（修 fork 弱点）

### A.1 数据策略

**问题**：当前自我对弈数据里，黑方都用相同策略下棋，white 看到的"对手风格"一致。L4 minimax 是不同的"对手风格"——更激进的局部威胁堆叠。

**解决**：在 self-play 数据集里**注入 L4 minimax 对手棋谱**。

具体做法：
- 30% 自我对弈（CNN+MCTS vs CNN+MCTS）
- 50% 异质对弈（CNN+MCTS vs Pattern-MCTS）
- **20% 对抗对弈（CNN+MCTS vs L4 minimax）** ← 新增

每局都从 CNN 视角生成训练数据（policy = MCTS visit distribution，value = game result）。

### A.2 Pipeline 改造

**文件**：`ai_server/nn/iterate.py`

加 `--adversarial-frac 0.2` 参数，在 self-play 阶段：

```python
# Pseudocode for iterate.py changes
def play_self_play_game(adapter_cnn, opponent_type):
    if opponent_type == 'self':
        b_engine, w_engine = mcts_cnn(adapter_cnn), mcts_cnn(adapter_cnn)
    elif opponent_type == 'pattern':
        b_engine, w_engine = mcts_cnn(adapter_cnn), mcts_pattern()
    elif opponent_type == 'minimax':
        b_engine, w_engine = mcts_cnn(adapter_cnn), MinimaxEngine(depth=4)
    # ... alternate B/W per game
    return play(b_engine, w_engine)

# In iterate loop:
n_self = int(games_per_iter * 0.3)
n_pattern = int(games_per_iter * 0.5)
n_advers = games_per_iter - n_self - n_pattern  # 20%
```

需要 port GDScript minimax 到 Python（已有部分，但需补全 TT + iterative deepening）。预计 4 小时。

### A.3 可选：扩大网络

如果 128f/6b 容量不够吸收新数据，考虑 192f/8b：
- Params: 361k → ~1.0M
- Inference latency: +50%（仍然秒级）
- 训练时间: +30%

**决策点**：先用 128f/6b 训一轮，看 fork 局型 benchmark 是否改善。如果改善 < 5%，升级架构。

### A.4 训练命令

**Bootstrap 不需要重做**——已有 `bootstrap_128f6b.pt` 仍是好起点。

**Iterate**（基于现有 `best_model.pt`）：

```bash
cd ai_server
python3 -m nn.iterate \
    --initial-model data/weights/best_model.pt \
    --iterations 6 \
    --games-per-iter 200 \
    --simulations 800 \
    --epochs 12 \
    --lr 5e-5 \
    --replay-size 80000 \
    --filters 128 --blocks 6 \
    --vcf-depth 10 \
    --adversarial-frac 0.2 \
    --benchmark-games 40 \
    --benchmark-sims 200 \
    --converge-threshold 0.50 \
    --cnn-prior-weight 0.5 \
    --checkpoint-prefix "free_v2_" \
    --log-file logs/free_v2_iterate.log
```

预计时间（Mac M5 32GB）：
- 200 games × 800 sims × 6 iter ≈ 12-15 小时
- 训练（每 iter 12 epochs × ~80k samples）≈ 30 分钟 × 6 = 3 小时
- **总：~15-18 小时一夜**

### A.5 Validation

**fork 局型 unit test**（核心验证）：

加 `ai_server/tests/test_fork_defense.py`：

```python
def test_critical_fork_defense():
    """The position where current best_model (Mac) fails 7/10 times."""
    moves = [(7,7),(8,7),(8,6),(6,8),(7,6),(6,6),(6,7),(7,8),
             (5,8),(4,9),(9,6),(8,5),(7,5),(7,4),(9,7),(6,4),
             (10,6),(11,6),(9,5),(9,4),(8,4)]
    g = GameLogic()
    for m in moves: g.place_stone(*m)
    # White move 22 — current model picks (7,3) → loses
    # New model should pick something that doesn't lose immediately
    # OR: new model's value head should warn (value < -0.4 acceptable, < -0.99 = bad)
    
    new_model = load('free_v2_iter_N.pt')
    policy, value = new_model.predict(g)
    
    # Loose criterion: top-3 priors should include something other than (7,3)
    # OR: if it picks (7,3), the immediate-next position value > -0.99
    assert value > -0.95, f"new model still thinks position lost: {value}"
```

**完整 benchmark**：

```bash
python3 bench_l4_vs_l6.py \
    --model-a data/weights/free_v2_iter_N.pt \
    --model-b minimax_d4 \
    --games 100 --alternate-colors \
    --output bench_results/free_v2_vs_l4.json
```

**判定标准**：
- ✅ 上线条件：vs L4 ≥ 85% (n=100) **且** fork 局型测试通过
- ❌ 不上线：< 80% 或 fork 测试不过

### A.6 Rollback

如果 `free_v2` 在 benchmark 里不如 `best_model`：
- 保留 `best_model.pt` 为生产
- 把 `free_v2_iter_N.pt` 移到 `archive/` + 写一份失败分析

---

## 路径 B：禁手模型（Renju v1）

### B.1 禁手检测算法

**核心函数**：`forbidden.py`

```python
def is_forbidden_for_black(board, row, col):
    """
    True iff placing BLACK at (row, col) would be forbidden.
    Order of checks (五连优先):
    1. 五连 → not forbidden (it's a win)
    2. 长连 (≥6) → forbidden
    3. 双四 (count fours ≥ 2 across 4 directions) → forbidden
    4. 双三 (count "live" open threes ≥ 2 across 4 directions) → forbidden
    """
    place black at (row, col)
    # Check 5-in-a-row first (overrides forbidden)
    if any direction has exactly 5 → return False (win)
    if any direction has ≥6 → return True (overline)
    # Count fours
    fours = count_fours(board, row, col, BLACK)
    if fours >= 2: return True
    # Count live threes
    threes = count_live_threes(board, row, col, BLACK)
    if threes >= 2: return True
    return False
```

**"live three" 定义**（Renju 严格规则）：
- 一条线上有 3 个连续黑子
- 且**两端都有空位能延伸成开四**
- 且延伸的下一步**不会触发禁手**（递归判定，深度通常 1-2）

**完整规则边界 case**：
- 三三禁手：必须是两条都是"真活三"
- 跳三 (X _ X X X) 在某些规则下算开三，某些不算
- 默认采用 **Renju 国际规则 (RIF)**

### B.2 训练数据特征

**输入扩展为 10 channel**（vs free 模型的 9 channel）：
- channels 0-8：同自由对局
- channel 9：**当前玩家是黑且开启禁手时**，禁手 mask（黑方禁手位置 = 1，否则 0）

如果 channel 9 全 0 → 模型推断为白方或自由模式
如果 channel 9 有 1 → 模型知道哪些位置不能下

这样**一个网络支持两种模式**——不需要双模型分发！

替代方案：完全不加 channel，纯靠训练让模型隐式学会禁手位置不好。
- 优势：更简洁，input 不变
- 劣势：模型必须从数据中学习"我是黑方所以这些位置危险"，训练效率低

**推荐：加 channel 9（明确告诉模型规则）**

### B.3 Bootstrap (禁手模式)

```bash
python3 -m nn.bootstrap \
    --games 300 \
    --simulations 600 \
    --epochs 60 \
    --filters 128 --blocks 6 \
    --input-channels 10 \
    --forbidden-mode \
    --save-name renju_bootstrap_128f6b.pt \
    --log-file logs/renju_bootstrap.log
```

为什么 600 sims 而不是 400：
- 禁手模式黑棋分支变窄，每个候选 sims 数应该多一点找好棋
- 总计算量类似

预计时间：~6 小时

### B.4 Iterate (禁手模式)

```bash
python3 -m nn.iterate \
    --initial-model data/weights/renju_bootstrap_128f6b.pt \
    --iterations 8 \
    --games-per-iter 150 \
    --simulations 800 \
    --epochs 10 \
    --lr 1e-4 \
    --replay-size 60000 \
    --filters 128 --blocks 6 \
    --input-channels 10 \
    --vcf-depth 10 \
    --forbidden-mode \
    --benchmark-games 40 \
    --benchmark-sims 200 \
    --converge-threshold 0.50 \
    --cnn-prior-weight 0.5 \
    --checkpoint-prefix "renju_v1_" \
    --log-file logs/renju_iterate.log
```

预计时间：~12 小时

### B.5 Validation

**禁手特殊局型测试**：
- 黑方面对开三时不能下双三禁手位 → 必须找其他防守
- 黑方建立四连威胁时考虑长连禁手
- 白方主动威胁黑方走入禁手（"逼禁手"战术）

```python
def test_renju_forced_forbidden():
    """White can force black into forbidden position."""
    # Setup specific position from Renju literature
    ...
```

**完整 benchmark**：
- Renju model vs L4 minimax (with forbidden mode) — 100 games
- Renju model vs Pattern-MCTS (with forbidden mode) — 50 games
- Cross-test: Renju model 跑 free play 模式 → 应该比 Free 模型差（off-distribution）

**判定标准**：
- ✅ vs L4 ≥ 70%
- ✅ vs Pattern-MCTS ≥ 80%
- ✅ 黑方禁手率 < 1%（自我对弈中黑方很少被强制禁手）

---

## 时间表

### 快路径（Path A 优先 + 推迟禁手）

| Day | Task | 时长 |
|---|---|---|
| Day 1 morning | Pipeline 改造（Path A） | 4h |
| Day 1 evening | 启动 free_v2 训练 | 启动 |
| Day 1 night | (训练运行) | 18h |
| Day 2 morning | Benchmark 验证 + 决策 | 2h |
| Day 2 afternoon | 上线 free_v2（如果通过） | 2h |
| **Day 2 end** | **新 Free 模型上线** | |
| Day 3-4 | 禁手算法 + 训练 pipeline 改造 | 12h |
| Day 4 evening | 启动 renju_v1 训练 | 启动 |
| Day 4-5 night | (训练运行) | 18h |
| Day 5-6 | Benchmark + 上线 | 4h |
| **Day 6 end** | **禁手模型上线 + UI 完成** | |

总计：**6 天**

### 平行路径（同时训）

如果用户的 Mac 能开两个 Python 进程并行训：
- Free v2 跑 GPU
- Renju v1 跑 CPU 慢一点
- Day 1-2：两个模型同时训练 + 验证
- Day 3-4：UI + 集成
- **Day 4 end：双模型上线**

但是注意 MPS 默认独占——平行需要小心。

### 推荐：先 Path A

理由：
1. Free 模型修 fork 弱点是当前用户体验最痛的问题
2. Path A 改动小（pipeline 加个 adversarial flag）
3. 禁手是新 feature，可以先验证基础流程稳定后再做
4. Path B 的禁手算法 bug 可能导致训练崩，先把 Path A 稳定再分散注意力

---

## 标准化重训流程（适用于未来所有重训）

### Step 1：基线锁定

跑当前生产模型 100 局 vs L4，记录：
- 总胜率
- 黑方胜率 / 白方胜率
- 平均步数
- fork 局型表现（如果有）

存档：`docs/training_runs/baseline_<date>.md`

### Step 2：Pipeline 改造

- 写明改了什么（数据/超参/架构/特征）
- 加单元测试（确保 game_logic / pattern_eval 没退化）
- 改完跑现有的 diff_test（Python ↔ Swift 一致性）

### Step 3：小规模验证

50 games × 100 sims，~30 分钟：
- Loss 曲线是否健康（policy CE 下降，value MSE 下降）
- 自我对弈是否有合理多样性（不全是 5 步速败）
- 没有 obvious bug

### Step 4：过夜训练

提前确认：
- 磁盘空间足够（每 iter 检查点 ~30MB × 8 iter = 240MB）
- log 重定向到文件
- 启动方式：`nohup python3 ... > logs/run.log 2>&1 &`
- 设置 wakelock（不让 Mac 睡）

### Step 5：训练监控

每 1-2 小时 check：
- log 最后 10 行
- iter benchmark 分数（每 iter 完了应有 vs prev 的对局结果）
- 如果连续 2 iter < 50%，杀进程重新分析

### Step 6：完整 Benchmark

最佳 checkpoint vs：
- 上一代生产模型（100 局，确认进步）
- L4 minimax（100 局，关键指标）
- Pattern-MCTS（50 局，sanity check）
- 自身（50 局，确认有合理胜负而不是全平局）

### Step 7：决策 + 文档

写 `docs/training_runs/<run_id>.md`：
- 改动摘要
- Loss 曲线 PNG
- Benchmark 结果表
- **决策**：上线 / 不上线 / 部分上线
- 如果不上线：原因 + 下次怎么改

### Step 8：上线流程

如果决定上线：
1. 旧模型 `best_model.pt` 移到 `archive/<date>_<old_run_id>.pt`
2. 新模型 copy 为 `best_model.pt`
3. 重新导出 onnx + mlpackage + mlmodelc
4. CI 重新打包 iOS + macOS
5. TestFlight 验证
6. 更新 `CLAUDE.md` + `MEMORY.md` 项目记录

---

## Checkpoint 命名规范

```
ai_server/data/weights/
├── best_model.pt              # 生产 - 自由对局
├── best_renju.pt              # 生产 - 禁手 (待训练)
├── archive/
│   ├── 2026-04-19_big_iter_1.pt    # 之前的最佳
│   ├── 2026-04-25_pre_v2.pt        # free_v2 替换前的备份
│   └── ...
└── runs/
    ├── free_v2/
    │   ├── iter_0.pt, iter_1.pt, ..., iter_6.pt
    │   ├── benchmark.json
    │   └── README.md
    └── renju_v1/
        ├── iter_0.pt, ..., iter_8.pt
        ├── benchmark.json
        └── README.md
```

---

## 风险评估

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| Path A 训出来不如基线 | 中 | 浪费一晚 | 早停（每 iter 跌破 50% 立即停） |
| 禁手算法 bug 导致训练数据污染 | 中 | 模型废 | 先写 100+ 单元测试 |
| Mac 训练时崩（OOM / MPS 错误） | 低 | 中断 | checkpoint 每 iter 保存，可续训 |
| 长连/三三检测 false positive | 中 | 黑方棋力下降 | RIF 标准 + 对照人工 |
| 双 channel input 改动让现有模型无法兼容 | 高 | 训练 from scratch | 设 channel 9 全零等价 9-channel，模型可初始化自现有权重 |

---

## 决策点（需 hejia 确认）

1. **优先 Path A 还是 Path B**？我推荐 **A（修 fork 弱点）**先，因为这是当前用户能感知到的问题。
2. **架构升级**？128f/6b → 192f/8b ?（参数 3x，推理慢 50%）
3. **input channel 加禁手 mask**？（推荐：是。让一个模型支持两种规则）
4. **平行训练 vs 串行**？（推荐串行，避免 Mac 资源竞争）
5. **训练 budget**？1 晚（保守）vs 2 晚（彻底）

---

## 下一步动作

如果路径选定（推荐 Path A 优先）：

1. **今天 / 明早**：
   - 我改 pipeline（加 minimax 对手 + adversarial-frac 参数）
   - 写 fork 局型 unit test
2. **晚上**：你启动训练
3. **隔天上午**：我帮你看 benchmark + 决定上不上
4. **隔天下午**：上线 + TestFlight 验证

禁手 (Path B) 完成 Path A 后再启动，避免同时改太多东西。

要我直接开工 Path A pipeline 改造么？
