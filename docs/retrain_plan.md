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

**核心改动**：用现有的 split-aware `pattern_eval`（含 split-three / split-four 检测，commit fe32925, 2026-04-16）从 `bootstrap_128f6b.pt` 重新 iterate。Teacher 现在能识别分裂棋型，CNN 跟着学就有这能力。

**纯 self-play，不混 adversarial**（修正 04-25 P4a 失败教训）：

| 选择 | 依据 |
|---|---|
| 不混 minimax 对手 | Python `minimax_engine.py` 比 iOS GDScript L4 弱（Python 100% vs random，但对 L6 弱）。CNN 对着弱 minimax 学等于练稻草人。**04-25 实测 30% vs baseline**——已证伪 |
| 不混 pattern-only MCTS | self-play 时 value target = 终局结果，policy target = MCTS visit dist。混 heterogenous opponent 让"对方棋路不是 CNN+MCTS"这件事变成额外噪声源（§9 教训反复证明） |
| 用 §8.3 验证过的纯 self-play | big_iter_1 (66.9% vs bootstrap) 就是这套跑出来的。**没有证据偏离会更好** |

**理论根据**：AlphaZero / KataGo / Leela 都纯 self-play。"opponent diversity"在 multi-agent RL（poker、StarCraft）有用，但 zero-sum 完美信息单 agent 不需要——agent 收敛到 minimax 解时，外部 weak opponent 数据反而会拉低均衡点。

### A.2 Pipeline 改造

**基本不需要改。** 现有 `nn/iterate.py` 已支持本计划全部参数。**不新增引擎、不加 `--adversarial-frac`**。

前置确认（5 分钟）：
1. `ai/pattern_eval.py` 含 `_scan_line()` / `_gapped_score()`（split detection）—— grep 一下
2. `data/weights/bootstrap_128f6b.pt` 和对应的 `bootstrap_128f6b_samples.pkl` 在位
3. （可选）`tests/test_fork_defense.py` 作为新模型 sanity check

### A.3 架构升级：本轮保持 128f/6b

**严格不动架构。** 理由：
- `ai_journey.md` §8 在 128f/6b 上验证过完整 §8.3 配方
- 本轮主要变量是 **split-aware teacher**，不该和"换架构"耦合（耦合后无法归因）
- 192f/8b → 1M+ params，bootstrap 要重做，训练时间近翻倍。先把当前架构 split-aware 后的上限摸清

如果本轮 retrain 完仍 vs L4 ≤ 80%，按性价比考虑：
- (a) Lambda-2 threat search（不动模型，~1-2 天编程）
- (b) 192f/8b 重 bootstrap + iterate（~2 晚）
- (c) Path B2 Rapfi 蒸馏（见 `gomoku_research.md` §4，~1 周）

### A.4 训练命令（§8.3 配方）

**Mac 上一键启动**：`bash ai_server/run_retrain.sh`（会做前置检查、用 caffeinate 防睡眠、nohup 后台启动、写 PID 文件）。下面是脚本里同样的命令，附带每个参数的依据。

**起点是 `bootstrap_128f6b.pt`，不是 `best_model.pt`。** 理由：iterate 启动时读 `{model_path}_samples.pkl` 作为 bootstrap anchor pool（§9.2 v2 双池设计）。`best_model.pt` 没对应 .pkl 会触发 §9.2 末尾的 "fresh pool 无 cap" bug，pool 无限增长到 174k+。`bootstrap_128f6b.pt` 有 .pkl，走标准路径。

```bash
cd ai_server
python3 -m nn.iterate \
    --initial-model data/weights/bootstrap_128f6b.pt \
    --iterations 5 \
    --games-per-iter 150 \
    --simulations 1600 \
    --epochs 5 \
    --lr 3e-5 \
    --replay-size 60000 \
    --fresh-ratio 1.5 \
    --filters 128 --blocks 6 \
    --vcf-depth 10 \
    --benchmark-games 40 \
    --benchmark-sims 200 \
    --converge-threshold 0.50 \
    --cnn-prior-weight 0.5 \
    --checkpoint-prefix "free_v2_" \
    --log-file logs/free_v2_iterate.log
```

**预计时间**（Mac M5 32GB）：
- 150 games × 1600 sims × 5 iter ≈ 12-14 小时 self-play
- 5 epochs × ~30-60k samples × 5 iter ≈ 1-2 小时训练
- **总：~14-16 小时一夜**

#### 每个参数的依据（明确标注理论强度）

| 参数 | 值 | 依据 | 依据强度 |
|---|---|---|---|
| `--initial-model bootstrap_128f6b.pt` | | 必须有对应 `_samples.pkl` 才不触发 §9.2 fresh pool bug | **强**（bug 实证） |
| `--iterations` | 5 | §10 教训 #6：1-3 代到头。5 给 1 代 margin。理论：MCTS 分布随 CNN 收敛趋稳，marginal info → 0 | **强**（实测+信息论） |
| `--simulations` | 1600 | §8.3 验证；MCTS 理论：每候选走法 ≥10 visits 才有可信 visit 分布。15×15 ~80 候选 × 16 ≈ 1280 是下界。AlphaZero Chess 用 800（19×19 太大补偿不到），KataGo 用 1000-1600 | 中（理论+对标） |
| `--lr` | 3e-5 | Fine-tuning 标准做法：bootstrap 已 pretrained，新一轮应降 1-2 数量级避免 catastrophic forgetting。Adam from-scratch 1e-3 → fine-tune 1e-5 ~ 1e-4，3e-5 在 AZ late-stage schedule 范围内 | 中（理论+经验） |
| `--epochs` | 5 | 每 iter ~30-60k × 8 augment ≈ 240k-480k 等效样本。5 epochs ≈ 2-3k batch updates。SGD 收敛理论：fine-tune 应少 epoch 多 batch，5 在合理区间 | 中 |
| `--cnn-prior-weight` | 0.5 | **唯一无强理论依据**。§9.1 仅 4 点粗扫显示 0.5 最优。勉强援引"无信息先验下等权重"的 minimax bound。建议训完跑 A.7 sweep 验证 | **弱**（强经验，无理论） |
| `--fresh-ratio` | 1.5 | §9.2 v2 buffer 实证：fresh pool ≤ 1.5 × bootstrap pool 时 forgetting 控制良好 | 中（实证） |
| `--replay-size` | 60000 | 经验 cap 防 OOM。每 iter 加 ~30-50k，60k 覆盖最近 1-2 iter | 弱（实操） |
| `--benchmark-games` | 40 | §10 教训 #7：40 局 binomial std ~8%，detect 5% 改进的最低 sample size | **强**（统计） |
| `--converge-threshold` | 0.50 | "输 = 没改进"硬下界（§7.1 用 0.52 给 margin，但 5 iter 硬上限本身就是 fallback） | 中 |

**总评**：10 个参数中 4 个**强**依据（initial-model、iterations、benchmark-games、converge-threshold），4 个中等，2 个弱（prior-weight、replay-size）。最弱的是 `cnn_prior_weight=0.5`——A.7 sweep 就是来补这一条的。下次再 retrain 想做实验，**prior-weight 是性价比最高的扫点维度**，其他参数动了大概率退化。

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

### A.7 Optional：训练后 prior weight fine sweep

**前提**：A.4 训完得到一个比 `best_model` 更好的 `free_v2_iter_N.pt`。

**动机**：当前生产用的 `cnn_prior_weight=0.5` 来自 `ai_journey.md` §9.1 在 big_iter_1 上的 **4 点粗扫**（0.3 / 0.5 / 0.75 / 0.9），0.4-0.6 之间从未细调过。新模型用 split-aware teacher 训出来后，CNN 的 policy 分布会变，最优 weight 可能微移。这是低成本验证。

**实验**（只动 inference，不重训）：

```bash
# Lock new model, vary cnn_prior_weight at inference time
for W in 0.4 0.5 0.6; do
    python3 bench_l4_vs_l6.py \
        --model-a data/weights/free_v2_iter_N.pt \
        --model-b minimax_d4 \
        --cnn-prior-weight $W \
        --games 100 --alternate-colors \
        --benchmark-sims 200 \
        --output bench_results/free_v2_w${W}_vs_l4.json
done
```

**成本**：~4-6 小时 Mac M5（远低于一晚训练）。

**判定**：
- 0.5 仍最高 → 保持现状，"50/50 假设" 在新模型上 confirm
- 邻近值显著高（差距 > 5%）→ 更新 production inference 的 default weight
- 差距 2-5% → 噪声范围（n=100 标准差 ~5%），保持 0.5

**长远视角（不在本计划内）**：如果将来走 Path B2 Rapfi 蒸馏（见 `gomoku_research.md` §4），蒸馏后 CNN 等价学过 30.8M positions，训练规模跳 200x。届时应重新扫 [0.5, 0.6, 0.7, 0.8] —— Rapfi 自己的 teacher 用纯 NN prior（≈1.0），那个 regime 我们的小 sweep 可能完全不适用。

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
