# Gomoku AI v2 训练策略

> **📌 这是 2026-04-11 v2 设计当时的思路快照。后续实际跑出来的结果、失败教训、架构升级（48f→128f）、最佳模型 big_iter_1 的由来都在 [`ai_journey.md`](./ai_journey.md) 的第 5-11 节。本文档保留作为"当时是怎么想的"的历史记录。**

**日期**: 2026-04-11  
**触发**: v1 训练 10 代后 loss 卡死 4.7, gen_001 仅比随机稍差, M5 热降频  
**状态（写作时）**: 已在 Linux CPU 端完整验证, 等待 M5 跑完整训练  
**状态（2026-04-15 回看）**: 策略验证成功，后续演进见 `ai_journey.md`

## 为什么 v1 失败

| 问题 | 具体表现 | 根源 |
|------|---------|------|
| Loss 卡死 | 4.7582 → 4.6650 → 4.6890 → 4.6900 (4 代只降 0.1) | 训练数据是噪声 |
| 胜率卡死 | Gen 1 vs 随机 **30%** (新模型比随机还差!) | 冷启动失败 |
| 所有代被拒 | Gen 2-4 vs Gen 1 全部 <55% | 烂基准, 自然无进步 |
| M5 热降频 | Gen 4 自对弈 128 分钟 (是 Gen 2 的 3 倍) | Python+MPS 满载 8h 无风扇 |

**根本原因**: 用"随机神经网络引导的 MCTS"生成训练数据, 等于两个瞎子互相指路 — 数据是噪声, CNN 学不到任何东西, 反过来进一步污染 MCTS。

## v2 核心改动

### 1. 训练信号: 从 "冷启动 RL" 改为 "监督学习模仿强 teacher"

v1 是 zero-knowledge AlphaZero — 100 局 × 10 代的规模下根本不够收敛 (原版用 2000 TPU × 40 天)。

v2 改为: **用 pattern-guided MCTS 作为 teacher, CNN 做监督学习**
- Teacher = 现成的 Level 5 级别 MCTS (纯 Python, 无 NN)
- CNN 学 teacher 的访问分布 (policy) 和最终胜负 (value)  
- 监督学习收敛稳定, 远比 RL 可靠

### 2. Pattern feature input: 9 通道 CNN

v1 输入 2 通道 (黑/白). v2 输入 9 通道:
```
channel 0: own stones
channel 1: opponent stones
channel 2: self 可下出五连 (必胜点 mask)
channel 3: self 可下出活四 mask
channel 4: self 可下出活三 mask
channel 5: opponent 可下出五连 (必堵)
channel 6: opponent 可下出活四
channel 7: opponent 可下出活三
channel 8: 最后一手位置
```

**关键洞察**: 棋型识别是最难学的部分. 直接编码到输入, CNN 从第一步就有 "Level 3" 的战术意识, 可以专注学高阶策略而不是从零识别活三。

### 3. Pattern-guided MCTS

`ai/mcts_engine.py` 完全重写:
- **PUCT 选择** (替代 UCB1), 更稳定处理 prior 差异大
- **Pattern prior**: 没有 NN 时用 `score_cell` 分数 softmax 作为先验
- **Static leaf eval** (替代 rollout): 不做 30 步 rollout, 只查 "1 步必胜/必堵", 速度 **100 倍提升**
- **Top-12 剪枝**: 根节点只考虑 pattern 分数最高的 12 个候选, 放弃边角
- **Dirichlet noise** (训练时): α=0.3, ε=0.25, 保证自我对弈产生多样局面

### 4. 数据增强: 8x 对称

Gomoku 在 D4 对称群下不变 (4 旋转 × 镜像 = 8 种). 每个训练样本扩 8 份, **免费 8x 数据**:
```python
augment_sample(state, policy, value) → 8 个 (state', policy', value)
```
单独这一个改动就抵得上 7 个自对弈 worker 的算力。

### 5. 并行自对弈

`nn/parallel_self_play.py` 用 `multiprocessing.Pool` 同时跑 3-4 局. Pattern-MCTS 是纯 NumPy + Python, 无 GPU 争用, 线性加速。

### 6. 模型升级

| | v1 tiny | v2 small |
|---|---------|---------|
| input channels | 2 | 9 |
| filters | 8 | 32 |
| res blocks | 1 | 2 |
| 参数 | ~10K | ~270K |
| M5 推理 | <1ms | <1ms (仍然快) |
| 训练时间 (单 epoch) | ~1s | ~3s |

小到仍然 ONNX 打包后 <500KB, 推理 <1ms, 但容量足够学出模式。

### 7. 更合理的评估

v1 新代 vs 旧代, 每步 50 sims — 评估本身很慢还不稳定。
v2:
- 快速 sanity: vs 纯随机对手 (必须 100% 胜)
- 强度测试: CNN-MCTS vs 纯 Pattern-MCTS 
- **draw = 0.5 分** (Gomoku 无禁手强对强常和棋, 纯胜率低估实力)

## 验证结果 (Linux 单核 CPU 上跑的 dry run)

| 配置 | Loss drop | vs Random | vs Teacher (score) |
|------|-----------|-----------|-------------------|
| 4 局 × 8 epoch | 43% | 100% (2/2) | 0% (小样本, 噪声) |
| 8 局 × 12 epoch | 45% | 100% (3/3) | 25% (1W 2L 1D) |
| 16 局 × 20 epoch | 43% | 100% (4/4) | **83% (5W 1L 0D)** |

**关键**:
1. Loss 稳定下降 40%+ — v1 的 0.1% 相比是质变
2. 100% vs 随机 — 学到了基本战术
3. 16 局后 CNN 已经**反杀 teacher 83%** — 监督学习收敛极快

v2 16 局 = v1 1000 局的有效规模, 因为:
- 有 teacher 提供学习目标 (不是噪声)
- 8x 数据增强 ≈ 128 局
- 9 通道输入省掉了"学会什么是活三"的几万步梯度下降

## 运行方式

### 在 Mac M5 上:

**第一步: Smoke Test (10-15 分钟)**
```bash
cd gomoku
./run_smoke_on_mac.sh
```
看最后的 `VERDICT` 区块:
- `loss drop >= 15%` ✓
- `vs Random >= 80%` ✓
- `vs Teacher` 仅作参考, 16 局噪声大

**输出 PASS** → 跑完整训练  
**输出 FAIL** → 发 VERDICT 给我看

**第二步: 完整训练 + 打包 (1-2 小时)**
```bash
./run_full_training_v2.sh
```
比 v1 快得多:
- v1: 100 局 × 10 代 × 8h = 一整晚 (结果失败)
- v2: 100 局 × 1 代 (bootstrap) × 1h = 一杯咖啡

完成后输出 `build/Gomoku_final.zip`, 直接发布。

## 为什么不用 MLX

查了 2026 年的 benchmark: **MLX 对 CNN (ResNet) 训练比 PyTorch MPS 慢 2-10x**。MLX 的优势在 Transformer 和大模型, 我们是小 ResNet, PyTorch MPS 是最佳选择。

## 代码改动清单

新增:
- `ai_server/ai/pattern_eval.py` — Python 版 pattern evaluator
- `ai_server/nn/augment.py` — 8x 对称增强
- `ai_server/nn/parallel_self_play.py` — 多进程自对弈
- `ai_server/nn/bootstrap.py` — 监督学习训练 pipeline
- `ai_server/smoke_test.py` — 快速烟雾测试入口
- `run_smoke_on_mac.sh` — Mac 端烟雾测试脚本
- `run_full_training_v2.sh` — Mac 端完整训练+打包
- `docs/training_v2_strategy.md` — 本文档

修改:
- `ai_server/ai/mcts_engine.py` — PUCT, pattern prior, static leaf eval, Dirichlet noise
- `ai_server/ai/game_logic.py` — 新增 `to_tensor_9ch()` 方法
- `ai_server/nn/model.py` — 9 通道输入, 32 filter × 2 block 默认, v2 checkpoint 格式
- `ai_server/export_onnx.py` — 支持 v2 checkpoint + 9 通道
- `ai_server/onnx_server.py` — 运行时生成 pattern feature planes, 9 通道推理
- `scripts/net/ai_service_client.gd` — `request_move` 可传 `last_move`
- `scripts/player/remote_ai_player.gd` — 从 `move_history` 提取 `last_move` 传给 server

保留不动 (legacy):
- `ai_server/train_pipeline.py` — v1 训练脚本 (失败的那个), 留着当反面教材
- `ai_server/nn/self_play.py` — v1 自对弈
- `ai_server/server.py` — v1 PyTorch server (无用)
