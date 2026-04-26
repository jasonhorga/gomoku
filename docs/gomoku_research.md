# Gomoku/Renju AI 现状调研

调研时间：2026-04-26  
目的：找出我们 128f/6b CNN+MCTS 体系跟世界最强 AI 的差距，找改进路径。

---

## 1. 当前世界最强：Rapfi

### 概况
- **GitHub**: dhbloo/rapfi（开源，C++）
- **战绩**：GomoCup 2024-2025 冠军；Botzone 520 个 AI 排名 #1
- **作者**：dhbloo（疑似中国清华学生），是新一代 Yixin 接班人
- **网络权重**：CC0 license（公共领域，**任意使用**）

### 架构（关键创新）

**不是 CNN，是 Mixnet**：
- 把 15×15 棋盘分解成 11-cell 长的**方向线段**（横/竖/两个对角，共 4 方向 × N 段）
- 对每个线段查 **397K 大小的 pattern codebook**（预计算的查表）
- 输出 C-channel 特征
- 只在 **变化的 ~44 个 directional features 上 incremental update**（一手棋只动 ~44 个数）

**对比我们的 CNN**：
| 维度 | 我们 (CNN 128f/6b) | Rapfi Mixnet Medium |
|---|---|---|
| 参数量 | 2M | M=128, C=64（约 1M） |
| 推理 (CPU) | ~10ms / 次 forward | ~3-4μs / 次 update（incremental）|
| 推理 (CPU 满 forward) | n/a | 257K nodes/sec |
| 适合的搜索 | MCTS（每次走必须 forward）| Alpha-beta（每个节点一次 update）|

**关键差异**：incremental update。我们 CNN 每次 MCTS 节点都要重新跑全 forward，~10ms × 200 sims = 2s/move。Rapfi 一手棋只更新 44 个数，所以能在 alpha-beta 里跑深得多。

### 搜索算法
- **PVS (Principal Variation Search)** + Alpha-Beta，**不是 MCTS**
- VCF quiescence search
- 完整的现代 chess engine 工具箱：transposition table、killer moves、futility pruning、null move pruning、late move reduction
- 加 MCTS 变体（PUCT + dynamic factor + first-play urgency）作为可选

### 训练
- 30.8M positions 来自 **KataGomo**（AlphaZero-style 自我对弈数周）
- Teacher：ResNet-6b128f（**跟我们的 128f/6b 一模一样的架构！**）
- Distillation: 75% teacher labels + 25% ground truth
- 600k iterations × batch 128

**重要**：Rapfi 是 **distill 一个 ResNet teacher 到 Mixnet**。所以 ResNet 是中间步骤，最终引擎用 Mixnet 推理。

### 数字
- vs 各种 ResNet：+300-400 ELO（同等时间预算）
- vs Katagomo（前 SOTA）：+400 ELO（CPU 同等预算）
- 推理速度比 Katagomo 快 2.5x

---

## 2. 经典算法基础

### Threat-Space Search (TSS) — Allis 1993

不搜全部分支，**只搜攻击线**：
- 搜索时**只考虑威胁性的 move**（产生四/活三/双重威胁的步）
- 防御方多种应法时，**视作所有应法都被尝试过**（盲目假设防方走任意一种）
- 这是怎么搜深 20+ 步的关键
- 1993 年用 TSS + Proof-Number Search 正式证明 **15×15 自由 Gomoku 黑必胜**

### Lambda Search

TSS 的扩展：
- λ-1 = 单威胁搜索（VCF）
- λ-2 = 双威胁链
- λ-3 = 复合威胁
- 越高 lambda 越接近真实搜索深度

### Proof-Number Search (PNS)

替代 alpha-beta：
- 每个节点记 "证明数" 和 "反证数"
- 搜索时优先扩展最容易证明胜负的节点
- 在有强制胜路径时极快收敛
- 缺点：内存重，不适合 budget 紧的实时系统

### Renju 禁手

- 黑棋禁三三、四四、长连
- 唯一合法的强制胜模式：**四三** (one four + one three)
- 白棋利用禁手"逼黑入禁手"也是常见战术

---

## 3. 我们 vs SOTA 的差距分析

### 我们当前
- 网络：128f/6b ResNet (~2M 参数)
- 训练：50/50 hybrid（pattern+CNN priors）, MCTS @ 200 sims (production)
- 训练数据：自我对弈 + pattern-MCTS teacher（**没有 split detection**）
- 搜索：MCTS @ 200 sims + VCF/VCT depth 10/6
- 设备约束：iOS 推理 < 20ms

### 跟 Rapfi 的具体差距
| 项目 | 我们 | Rapfi | 差距 |
|---|---|---|---|
| 网络架构 | ResNet 128f/6b | Mixnet | Mixnet 推理快 1000x |
| 搜索算法 | MCTS | α-β + PVS | α-β 在窄分支更深 |
| Quiescence | VCF/VCT 单独跑 | 内嵌进 α-β | 整合度高 |
| 训练数据规模 | ~150 games × 6 iter ≈ 1k games | 30.8M positions ≈ 200k+ games | **200x 数据量** |
| 训练算力 | 1 晚 Mac M5 | 数周 KataGomo + ResNet teacher | 100x 算力 |
| Move ordering | 简单 prior 排序 | history heuristic + killer + LMR | 工程深度 |

**预估 ELO 差距**：我们 vs Rapfi 大概 **800-1000 ELO**（相当于业余 vs 职业）。

---

## 4. 改进路径（按性价比排）

### 路径 A：渐进改进（保持现有架构）

**A1. 用 split-aware teacher 重训** ★ 立刻可做
- 影响：CNN 能识别 split-3/4，预估 +50-100 ELO
- 工作量：一晚训练（用现有 pipeline，纯 self-play 1600 sims）
- 风险：低（按 ai_journey 验证过的配方）

**A2. 升级架构 192f/8b 或 256f/10b**
- 影响：突破 plateau，+100-200 ELO
- 工作量：1.5-2 晚（重新 bootstrap → iterate）
- 风险：中（更大模型需要更多数据）

**A3. 加 Lambda-2 threat search**
- 影响：复杂局面看得更深，+50-100 ELO
- 工作量：1-2 天编程
- 风险：低

**A4. 加禁手 (Renju) 模式**
- 影响：新功能；不直接增强自由对局
- 工作量：~1 周（参考 retrain_plan.md）
- 风险：中

### 路径 B：用 Rapfi 权重（最大跳跃）

**B1. 直接用 Rapfi 的预训权重做 inference**
- Rapfi-networks 是 CC0 公开权重
- 但需要把 Mixnet 推理 port 到 Swift（C++ → Swift）
- 优势：直接获得 SOTA 强度
- 工作量：2-3 周工程
- 风险：高（架构完全不同；工程量大）
- ELO 跳跃：**+800 ELO**（如果 port 成功）

**B2. 用 Rapfi 当我们的 teacher，distill 到我们的网络**
- 跑 Rapfi 自我对弈生成训练数据
- 用 Rapfi 的 policy/value 作为软标签训练我们的 CNN
- 优势：保持现有 inference 不变，但学到 SOTA 知识
- 工作量：1 周（数据生成 + 训练）
- 风险：中
- ELO 跳跃：可能 +200-400 ELO

### 路径 C：完全重写

**C1. 实现 Mixnet from scratch**
- 全套 Mixnet 引擎 + alpha-beta
- 优势：能跟上未来 Rapfi 升级
- 工作量：1-2 个月
- 不推荐：投入产出比不行

---

## 5. 我的建议

### 短期（本周）
**A1. 立即重训 + A3 Lambda-2 threat search**

具体：
1. 用现有 pipeline，从 `bootstrap_128f6b` 开始重新 iterate
   - 关键改动：直接用现有的 split-aware pattern_eval（teacher 自然带 split）
   - 配置严格按 ai_journey: 1600 sims, lr 3e-5, fresh_ratio 1.5, iterations 5
   - 预期：iter1 vs bootstrap ≥ 60%, iter2 vs iter1 plateau
2. 同时实现 Lambda-2 threat search 在 MCTS 之上
   - 当 MCTS 选定 move 后，跑 Lambda-2 验证不会被 fork
   - 如果对手有 fork 威胁，强制选 fork prevention

**预估**：能把 iOS L6 vs L4 从 65-90% 拉到 85-95%。

### 中期（下个月）
**B2. Rapfi 当 teacher distill 到我们的网络**

具体：
1. 在 Mac 上跑 Rapfi 自我对弈（C++ 编译运行）生成 50k-100k 对局
2. 提取 (position, policy, value) 三元组作为 SL 数据
3. 训练我们的 128f/6b 网络模仿 Rapfi 的输出
4. 输出强度大概率超越 A1+A3

**预估**：能让 L6 接近职业初段。

### 长期（如果项目持续）
**A2. 升级 192f/8b** 或者 **B1. Port Mixnet 到 Swift**

---

## 6. 立刻可以做的（不需大动作）

1. **重新 bootstrap 用现在的 pattern_eval**——这个最确定能 work，按 ai_journey 复现一次
2. **对照 Rapfi 的 NNUE trainer 看看他们怎么做 augmentation**——可能学到训练技巧
3. **下载 rapfi-networks 看模型结构** ——为将来 distill 准备

---

## 参考链接

- [Rapfi GitHub](https://github.com/dhbloo/rapfi)
- [Rapfi 论文 (arXiv 2025)](https://arxiv.org/abs/2503.13178)
- [Rapfi-networks 权重 CC0](https://github.com/dhbloo/rapfi-networks)
- [PyTorch NNUE Trainer](https://github.com/dhbloo/pytorch-nnue-trainer)
- [Allis 1993 Threat-Space Search 原论文](https://cdn.aaai.org/Symposia/Fall/1993/FS-93-02/FS93-02-001.pdf)
- [Baeldung TSS 教程](https://www.baeldung.com/cs/gomoku-threat-space-search)
- [GomoCup 历年战绩](https://gomocup.org/results/)
