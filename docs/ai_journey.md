# 五子棋 AI 开发历程：原理讲解与实战复盘

> 写给未来的自己回顾：我们是怎么一步步做出这个 AI 的，每个决策背后的思考，以及失败中学到的东西。
>
> 面向 ML 初学者：不假设你懂神经网络或强化学习。需要用到的概念会从头解释。
>
> 时间跨度：2026-03-30 ~ 2026-04-15（约两周）
> 最后更新：2026-04-15（新增 Section 13 部署成熟化：AI 性能修复 + macOS 签名 CI）
> 当前状态：`best_model.pt = big_iter_1` (128f/6b)，对 bootstrap 版本胜率 66.9%；已签名+公证的 `Gomoku_signed.zip` 可分发

---

## 目录

1. [起点：为什么做这个项目](#1-起点)
2. [传统 AI 的天花板：Level 1-5](#2-传统-ai-的天花板)
3. [神经网络 AI 基础知识](#3-神经网络-ai-基础知识)
4. [第一次尝试 v1 失败](#4-第一次尝试-v1-失败)
5. [策略大调整 v2](#5-策略大调整-v2)
6. [v2 Bootstrap 训练成功](#6-v2-bootstrap-训练成功)
7. [迭代自我提升（Phase 2）](#7-迭代自我提升)
8. [架构升级 128f/6b：big_iter_1 的胜利](#8-架构升级-128f6b)
9. [失败的尝试与诊断](#9-失败的尝试与诊断)
10. [经验教训 TL;DR](#10-经验教训-tldr)
11. [当前模型与部署现状](#11-当前模型与部署现状)
12. [未来方向](#12-未来方向)
13. [Part 2: 部署成熟化 (2026-04-15)](#13-part-2-部署成熟化2026-04-15-下午)
14. [Part 3: AI 缺陷修补 (2026-04-16/17)](#14-part-3-ai-缺陷修补2026-04-1617)

---

## 1. 起点

### 1.1 选 Godot 的判断（2026-03-30）

最初选型时有三个方向：HTML/CSS/JS、React、Vue。**选了 Godot 引擎**，原因：

- **打包成独立可执行文件** — 给朋友玩不用教他们装 node_modules
- **游戏原生能力** — 渲染/输入/联网都内置，不需要组合一堆 npm 包
- **跨平台** — 同一套代码打 Linux/macOS/iOS
- **GDScript 写起来像 Python** — 学习曲线低

代价：团队里 ML 生态在 Python 里，所以最终架构是 **Godot（游戏）+ Python（AI 服务）** 的双语混合。

### 1.2 核心架构：Player 抽象（关键设计）

整个项目最重要的一个决策 —— `PlayerController` 抽象基类：

```
PlayerController (抽象基类)
├── HumanPlayer      ← 本地鼠标点击
├── NetworkPlayer    ← 远程 RPC（ENet）
├── LocalAIPlayer    ← GDScript AI（Thread）Level 1-5
└── RemoteAIPlayer   ← TCP 调 Python AI，Level 6
```

**为什么重要**：GameManager 只认 `PlayerController`，不管对面是人还是 AI 还是网络玩家。结果：

- 加新 AI 难度 = 写一个新的 AI engine 类，插进 LocalAIPlayer
- 在线双人 = 两端各塞一个 NetworkPlayer
- 人机对战、AI vs AI 观战 = 几乎 0 代码改动，只是 Player 组合不同

如果一开始就把联网逻辑和游戏状态混在一起写，后面的所有扩展都会是痛苦的重构。

### 1.3 第一个可玩版本（2026-04-09）

两天搞出联网 PvP，踩了两个典型 Godot 坑：

- **Bug 1**：`class_name GameLogic` 在 `--import` headless 导入时没被识别 → 改用 `const _GameLogic = preload(...)` 显式加载
- **Bug 2**：棋盘线和棋子不可见 → 原因是 `WoodBackground` 是 Board 的子节点，子节点默认渲染在父节点 `_draw()` 之后，把所有东西盖住了。修复：`show_behind_parent = true`

到这里项目已经是可用游戏，接下来才开始真正的"AI 之旅"。

---

## 2. 传统 AI 的天花板

先解释一下五子棋为什么不是"写几条 if-else 就能下"的游戏。

### 2.1 搜索空间

15×15 棋盘 = 225 个格子。假设平均每步 10 个合理落点：

- 看 1 步：10 个选择
- 看 2 步：100 个
- 看 4 步：10,000 个
- 看 8 步：100,000,000 个（1 亿）

**深度 8 已经超出普通电脑 1 秒能算完的范围**。而高手下五子棋要看 20+ 步才能避开对方的陷阱。

所以 AI 设计的核心问题是：**怎么在不遍历所有走法的前提下，找到几乎最优的那一步？**

### 2.2 Level 1-2：随机 + 贪心

| Level | 策略 | 强度 |
|---|---|---|
| 1 | 在已有棋子周围 2 格内随机落 | 完全不会下 |
| 2 | 对每个空位算一个"棋型分数"，选最高的 | 入门玩家水平 |

Level 2 的关键是 **棋型评分表**：

```
five (五连)    = 100000  (必胜)
open_four      = 10000   (活四：两头都能连成五)
half_four      = 1000    (冲四：只有一头能连)
open_three     = 1000    (活三：能变活四)
half_three     = 100
open_two       = 100
half_two       = 10
```

评分时考虑四个方向（横、竖、两对角），把自己的攻击分数和堵对方的防守分数加起来，选综合分最高的点。

**防守权重加 1.1x** — 这是人类下棋的常识："宁可错杀一千也不放过一个对方的活四"。

### 2.3 Level 3-4：Minimax + Alpha-Beta

**Minimax**：假设对手是完美的（总是下对自己最差、对他最好的那一步），递归往下搜。

```
我方 max 选最大分  ─┐
  对方 min 选最小分 ─┤
    我方 max ──────┤
      对方 min ────┘
        ...
```

**Alpha-Beta 剪枝**：搜到一半发现这个分支已经明显比之前找到的最优差，就直接剪掉不搜了。实测剪枝后效率提升 10-100 倍。

**Level 4 的额外优化**：

- **迭代加深**：先搜 depth 1 → 2 → 3 → 4，前一层的最优走法当下一层的第一候选（让剪枝更早触发）
- **置换表**：Zobrist hash 标识盘面，搜过的局面缓存结果，避免重复搜索
- **Killer move 启发**：每层记住两个"经常导致剪枝"的走法，优先试它们

Level 4 在 15×15 上能搜到深度 4，响应时间 < 3 秒，能主动下双活三陷阱，业余高手水平。

### 2.4 Level 5：MCTS（重点！）

**MCTS = Monte Carlo Tree Search，蒙特卡洛树搜索**。这是后面所有神经网络 AI 的基础，必须搞懂。

**核心思想**：不做完整的 Minimax 搜索（太慢），而是用**随机模拟**估计每个走法的胜率。

四步循环（每次迭代都走一遍这四步）：

```
1. Selection（选择）
   从根节点往下，每层选"最值得探索"的子节点
   公式：UCB1 = 平均胜率 + C × √(ln(总访问次数) / 自己的访问次数)
   含义：前项是"已知的好"，后项是"探索不足的"，两者平衡

2. Expansion（扩展）
   选到一个没完全展开的节点，添加一个新子节点

3. Simulation（模拟 / rollout）
   从新子节点开始，双方都随机下棋直到终局
   记录：是黑赢还是白赢

4. Backpropagation（回传）
   沿着走过的路径，把胜负更新到每个节点的"胜率"统计
```

做 5000 次这样的循环后，**访问次数最多的子节点 = 最优走法**。

**为什么这样就对了？**
- 好的走法会被反复选中（步骤 1），因为它胜率高
- 被选中越多，路径上所有节点的统计越准
- 最终访问次数本身就反映了"MCTS 认为有多好"

Level 5 做 5000 次模拟，响应 2-5 秒，业余强手水平。

### 2.5 传统算法的天花板

Level 5 已经能赢绝大多数业余玩家。但有两个本质限制：

1. **Simulation 用随机 rollout**：双方随机下，模拟出来的胜负噪声很大，尤其开局阶段（离终局远）
2. **没有"感觉"**：看不出"这个局面黑棋明显占优"，除非是教科书级别的棋型

这就是**神经网络能帮上忙的地方**：让 NN 替代 rollout，直接"看一眼"就给出胜率估计。

---

## 3. 神经网络 AI 基础知识

### 3.1 AlphaGo/AlphaZero 做了什么

简化版本：

- **AlphaGo（2016）**：MCTS + 两个神经网络（一个选候选走法，一个估胜率），训练数据来自人类棋谱 + 自我对弈
- **AlphaZero（2017）**：**完全不用人类棋谱**，从随机权重开始，靠自我对弈训练。在围棋、国际象棋、将棋上超过人类

核心公式：**MCTS + 神经网络 = 比单独用任何一个都强得多**

- 神经网络负责"第一感"：给每个走法打个先验分数（prior），给局面估个胜率（value）
- MCTS 负责"深入思考"：用神经网络的第一感引导搜索方向，搜深了之后修正神经网络的判断

### 3.2 CNN：适合处理棋盘的"视觉"结构

**CNN = Convolutional Neural Network，卷积神经网络**。

想象你在看棋盘："左上角有个活三"这个判断，不管活三在棋盘的哪个位置，识别方法都一样 —— 看一个局部 5×5 的区域里的棋子排列。

CNN 的 convolution 层就是在做这个：**用一个小的滤波器（比如 3×3）扫过整个输入，提取局部特征**。多层 conv 堆叠，第一层识别"两个相邻的棋子"，中间层识别"活三"，高层识别"双活三的陷阱"。

我们用的是 **ResNet 风格**（残差网络）：每一层的输出会和输入相加再传下去，这样避免深层网络的"梯度消失"问题。

### 3.3 双头网络：Policy + Value

一个网络同时输出两个东西：

```
输入（9 通道 × 15 × 15 棋盘）
  ↓
[ResNet body：几个 residual block]
  ↓
  ├── Policy 头 → 225 个数（每个格子的落子概率）
  └── Value 头 → 1 个数（-1 到 +1，当前局面黑赢的概率 × 2 - 1）
```

**Policy 头**：教网络"一般这种局面应该下哪里"（离散分布，softmax 归一化）
**Value 头**：教网络"这种局面谁占优"（连续值，tanh 归一化到 [-1, 1]）

### 3.4 CNN 如何指导 MCTS（三种混合模式）

这是我们项目里最关键的概念。MCTS 的 Selection 步骤原来用 UCB1，换成神经网络的 prior 之后叫 **PUCT**：

```
PUCT = Q(节点) + C × P(节点) × √(父节点访问次数) / (1 + 自己访问次数)
```

其中 `P(节点)` 就是神经网络的 Policy 输出 —— "这个走法看起来有多靠谱"。

神经网络介入 MCTS 有三种模式（我们代码里都支持）：

1. **Pattern-only**：不用 NN，prior 来自人工棋型评分（`pattern_eval.py`），叶子节点评估也用棋型分数
2. **Pure CNN**：prior 用 CNN 的 policy，叶子节点评估用 CNN 的 value head
3. **Hybrid（我们最终用的）**：prior 是 CNN × 权重 + 棋型 × (1-权重) 的混合，叶子节点评估用棋型 score 的 tanh

**为什么选 Hybrid？** 后面的教训章节会讲到，这是踩了坑才得出的。Pure CNN 理论上最强但实际上小网络噪声太大，纯 CNN prior 会让 MCTS 走偏。

---

## 4. 第一次尝试 v1 失败

### 4.1 设计思路（2026-04-10 ~ 04-11）

照搬 AlphaZero 原版：

- **纯 2 通道输入**：黑子 + 白子，不加任何人工特征
- **随机初始化的 CNN**：让它从零学
- **自我对弈**：当前最新 CNN 跑 MCTS，两边都用同一个 CNN，打 100 局收集数据
- **训练**：用自对弈数据训练 CNN（policy 学 MCTS 的访问分布，value 学最终胜负）
- **迭代**：新模型 vs 旧模型，赢了留下，继续下一代

跑了 10 代，MacBook M5 上大概一天。

### 4.2 失败的具体数字

| 指标 | v1 实际表现 | 应该是什么样 |
|---|---|---|
| Loss | 4.7582 → 4.6650 → 4.6890 → 4.6900（4 代只降 0.1） | 应该稳定下降 |
| Gen 1 vs 随机 | **30%**（比随机还差！） | 应该 > 80% |
| Gen 2-4 vs Gen 1 | 全部 < 55% | 应该有一代胜率 > 60% |
| 自对弈时间 | Gen 4 花了 128 分钟（是 Gen 2 的 3 倍） | 应该稳定 |

最后一条的 128 分钟是因为 M5 满载 8 小时后热降频，说明这条路连物理上都跑不下去。

### 4.3 根本原因：冷启动 RL 不可行

**为什么失败？**

- 初始 CNN 权重是随机的，所以第一代 MCTS 的 prior 完全是噪声
- Noise-guided MCTS 产生的"自对弈数据"也是噪声
- 用噪声数据训 CNN → CNN 学不到东西 → 下一代 MCTS 还是噪声

就是**两个瞎子互相指路**。

**AlphaZero 原版为什么行得通？** 
- 他们用 2000 块 TPU 跑 40 天，生成了 4000 万局自对弈
- 即便是噪声数据，样本量大到一定程度后，"好的走法被选中稍微多一点点"的统计优势会累积出来
- 我们 100 局 × 10 代 = 1000 局，差 4 个数量级，根本不够

### 4.4 教训：规模定律 + 没有捷径

- **别重复 AlphaZero 原版的思路** —— 我们没有 2000 TPU
- **需要某种先验知识注入** —— 不能真的从 0 开始

这个洞察直接推动了 v2 的重设计。

---

## 5. 策略大调整 v2

2026-04-11 扔掉 v1，重做。核心理念转变：**从强化学习（RL）改为监督学习（SL）**。

### 5.1 RL vs SL：根本区别

- **RL（v1）**：模型自己和自己打，从胜负里学。没有"正确答案"，只有"哪一局赢了"
- **SL（v2）**：找一个**已经会下棋的老师**，让 CNN 学它的走法。有明确的"正确答案"（老师选了哪个走法）

SL 的好处：**收敛快、稳定**。代价：强度上限被老师限制，但我们的老师是 Level 5 MCTS，已经挺强了，足够当起点。

### 5.2 Pattern-MCTS 作为 Teacher

用 Python 重写了一个 MCTS：

```
ai_server/ai/mcts_engine.py
ai_server/ai/pattern_eval.py
```

- 不用神经网络，prior 用 **pattern_eval 的棋型分数 softmax**
- Leaf 评估用棋型分数（后面还会改进）
- 做 400 次模拟 ≈ Level 5 水平

这个 teacher 是"完全确定性的，知识来源于人工写的棋型评分表"。它不会再变，作为参考点很稳。

**训练数据生成**：
1. Teacher 两边自我对弈 N 局
2. 每一步记下 (盘面状态, MCTS 访问分布, 最终胜负)
3. CNN 学 (盘面 → 访问分布) 和 (盘面 → 胜负)

### 5.3 九通道输入（关键突破）

v1 用 2 通道（黑/白）。v2 扩展到 **9 通道**：

```
channel 0: 己方棋子  (1 表示有，0 表示无)
channel 1: 对方棋子
channel 2: 己方能一步成五的点（mask）
channel 3: 己方能下活四的点
channel 4: 己方能下活三的点
channel 5: 对方能一步成五的点（必须堵！）
channel 6: 对方能下活四的点
channel 7: 对方能下活三的点
channel 8: 最后一手位置（告诉 CNN 上一步下在哪）
```

**关键洞察**：channel 2-7 是**人工预处理出来的棋型信息**。CNN 不用从原始棋子学"什么叫活三"，这 **几万步梯度下降的工作量被免掉了**。

类比：教小孩算术，如果先教他"1+1=2、2+2=4"的表，再让他做微积分，远比让他从数手指开始学微积分快。

这一个改动是 v2 快速收敛的最大功臣。

### 5.4 数据增强 8x

五子棋在 **D4 对称群**下不变（4 个旋转 × 2 个镜像 = 8 种）。一个局面和它的 8 个对称版本是"一样的"。

`nn/augment.py` 做了这件事：**每个训练样本自动生成 8 个对称版本**。

```
原始 1 条数据 → augment → 8 条数据（每条都是合理的训练样本）
```

等效于"免费 8 倍训练数据"。v2 用 16 局自对弈的效果就抵得上 v1 用 128 局。

### 5.5 PUCT 替代 UCB1

UCB1 的 exploration 项是 `C × √(ln(N)/n)`，所有走法的 exploration bonus 一样。
PUCT 是 `C × P × √(N)/(1+n)`，**exploration bonus 乘以 prior 分数**。

好处：prior 高的走法被多探索，prior 低的少探索。在 prior 分化大的情况下（神经网络输出就是这样），PUCT 比 UCB1 稳定得多。

### 5.6 Static Leaf Eval（后来改成了 Continuous）

**原来 MCTS 的 Simulation 步骤**：从叶子节点随机下 30 步到终局，看谁赢。速度慢、噪声大。

**v2 初版用 static leaf eval**：不做 rollout，直接判断叶子局面有没有"一步必胜"（五连 / 活四 / 冲四双威胁）。
- 有 → 返回 +1 或 -1
- 没有 → 返回 0（平）

速度提升 100 倍。**但有一个致命问题**：绝大多数中间局面没有"一步必胜"，所以绝大多数叶子评估返回 0。MCTS 收到的信号是一片"平"，区分不出哪个走法更好。

**后来改成 continuous leaf eval**（在 iterate 阶段发现的，见第 8 节）：
```python
score_diff = 己方棋型总分 - 对方棋型总分
leaf_value = tanh(score_diff / 1000)  # 映射到 [-1, +1]
```

这样即使没有"一步必胜"，也能用 tanh(分差) 给 MCTS 一个渐变的信号。这个改动后面救了命。

---

## 6. v2 Bootstrap 训练成功

### 6.1 Smoke Test（2026-04-11 Linux 上）

先在 Linux 小规模跑一遍验证：

| 配置 | Loss drop | vs Random | vs Teacher (score) |
|---|---|---|---|
| 4 局 × 8 epoch | 43% | 100% (2/2) | 0% |
| 8 局 × 12 epoch | 45% | 100% (3/3) | 25% |
| **16 局 × 20 epoch** | **43%** | **100% (4/4)** | **83% (5W 1L 0D)** |

16 局 × 20 epoch 已经能反杀 teacher 83%，v1 1000 局都做不到。

**Loss drop 43-45% 意味着什么？** Loss 是 CNN 预测和 MCTS 访问分布的差距。drop 43% 说明 CNN 学得不错了。v1 是 2% drop —— 基本没学到任何东西。

### 6.2 Bootstrap 48f/3b（2026-04-12）

在 M5 上跑完整 bootstrap：

```bash
python3 -m nn.bootstrap --games 200 --simulations 400 --epochs 50 \
    --filters 48 --blocks 3 --save-name gen_final.pt
```

配置：
- 200 局自对弈（teacher vs teacher）
- 每局每步 MCTS 做 400 simulations
- 48 filters × 3 blocks ≈ 361k 参数（小模型）
- 50 epoch 训练

产出：`gen_final.pt`（第一个像样的神经网络 AI）。

### 6.3 Bootstrap 128f/6b（2026-04-14）

后来升级到更大网络：

```bash
python3 -m nn.bootstrap --games 200 --simulations 400 --epochs 50 \
    --filters 128 --blocks 6 --save-name bootstrap_128f6b.pt
```

训练日志：
- 开始 loss = 2.9729
- 结束 loss = 1.0499（drop 64.7%）
- vs Random: 100%（6/6）
- vs Teacher: 40% score（4W 6L 0D）

**注意 vs Teacher 只有 40%！** 这是 bootstrap 的**天花板**：CNN 在模仿 teacher，它永远不可能比 teacher 强。40% 已经很接近了（teacher 的上限是 50% 对自己打平）。

要突破 teacher，必须进入 **Phase 2：迭代自我提升**。

---

## 7. 迭代自我提升

### 7.1 原理（Phase 2）

```
循环：
1. 当前 CNN + MCTS 自我对弈 N 局 → 生成训练数据
2. 用这些数据训练 CNN → 新版本
3. 新版本 vs 旧版本打 40 局 benchmark
   - 新版本胜率 > 52% → 保留，继续下一轮
   - 胜率 < 52% → 停止（converge）
4. 回到 1
```

**为什么要 benchmark？** 防止"训练越训越差"。每一轮新模型必须证明自己比上一轮强。

**为什么胜率阈值是 52% 不是 50%？**
- 40 局的标准差约 8%，50% 很可能是噪声
- 52% 给一点 margin，稍微更可靠一点

### 7.2 iterate_v4 实验（2026-04-13）

从 `gen_final.pt`（48f/3b）开始迭代：

```
配置: iterations=5, games_per_iter=80, simulations=400, 
      cnn_prior_weight=0.5, replay_size=40000
```

结果：

| 轮次 | vs 上一轮 | 备注 |
|---|---|---|
| iter1 vs gen_final | **68%** | 明显提升 |
| iter2 vs iter1 | 52% | 还在进步 |
| iter3 vs iter2 | 51% | 接近阈值 |
| iter4 | 停止 | score < 52% |

**产出 `iter_3.pt`** —— 当时最好的 48f/3b 模型。

### 7.3 phA 继续迭代（2026-04-14）

想看看 iter_3 能不能再往上走，从它继续迭代：

```
配置: iterations=8, games_per_iter=150, simulations=800, 
      cnn_prior_weight=0.5
```

| 轮次 | vs 上一轮 |
|---|---|
| iter1 vs iter_3 | 75% |
| iter2 vs iter1 | 59% |
| iter3 vs iter2 | 52% |
| iter4 vs iter3 | **44% ❌** |

**Plateau signal**：第四轮第一次低于 50%，说明 48f/3b 这个架构**到头了**。硬训下去开始倒退。

产出 `phA_iter_3.pt`，但**和 iter_3 的差距在 benchmark 误差范围内**。相当于没改进。

这就是**小网络的天花板**：参数量不足以支撑更强的策略。要突破只能换更大的网络。

---

## 8. 架构升级 128f/6b

### 8.1 为什么加大网络

48f/3b ≈ 361k 参数
128f/6b ≈ 数百万参数（约 10 倍）

更多参数 = 更多"记忆空间" = 能学到更复杂的模式。

代价：
- 训练更慢（每次 forward/backward 更重）
- 推理更慢（打包进 iOS 时不能太大）
- 需要更多数据才能发挥（小数据 + 大模型 = 过拟合）

**经验判断**：300k 参数在五子棋上太少；128f/6b 还在 iOS 能接受的推理时间内（<20ms）；值得一试。

### 8.2 Bootstrap 128f/6b

跑了一个通宵的大 bootstrap：
- loss: 2.9729 → **1.0499**（drop 64.7%，比 48f/3b 还低）
- 50 epoch 才收敛（小模型 30 epoch 就平了，说明大模型容量真的更多）

产出 `bootstrap_128f6b.pt`。

### 8.3 Overnight Iterate（2026-04-14 → 04-15）

**关键的一晚**，配置用了最激进的 MCTS：

```
iterations=20, games_per_iter=150, simulations=1600, 
epochs=5, lr=3e-5, cnn_prior_weight=0.5, fresh_ratio=1.5
```

`simulations=1600` 是之前的 2 倍 —— MCTS 看得更深，训练数据更高质量。

结果：

| 轮次 | vs 上一轮 | score | 时间 |
|---|---|---|---|
| iter1 vs bootstrap | **66%** | 23W 10L 7D | 156s |
| iter2 vs iter1 | 50% | 18W 18L 4D | 124s |
| iter3 vs iter2 | 55% | 19W 15L 6D | 132s |

**iter1 拿到 66%** —— 相比 bootstrap 这是巨大进步。

iter2、iter3 基本平盘，说明又到 plateau。

**最关键的 benchmark**：`big_iter_1 vs bootstrap_128f6b` 打 80 局、每步 200 sims：

```
big_iter_1 胜率：66.9%
```

这就是现在 `best_model.pt` 的由来。

### 8.4 后续 iter2/iter3 为什么没提升

Bootstrap loss 已经降到 1.05，意味着 CNN 几乎完美模仿了 teacher。从"完美模仿 Level 5 teacher"再往上走，需要更高质量的 MCTS 数据（更深的搜索、更多的 simulations）才能给 CNN 新信号。

**1600 sims 已经是 M5 上能承受的上限**。再往上 2-3 天打不完一个 iteration。

结论：**这个架构 + 这个 teacher + 这个算力预算下，big_iter_1 就是尽头**。

---

## 9. 失败的尝试与诊断

### 9.1 CNN prior weight 扫描

Hybrid 模式下，CNN prior 和 pattern prior 按权重混合：

```python
prior = cnn_prior_weight × CNN + (1 - cnn_prior_weight) × pattern
```

直觉：CNN 学了那么多，权重调高点让它主导不是更好？

实验：

| cnn_prior_weight | 结果 | 说明 |
|---|---|---|
| 0.3 | **iter1 32% ❌** | 过度依赖 pattern，CNN 学的东西用不上 |
| 0.5 | iter1 66% ✓ | **最优** |
| 0.75 | iter1 12% ❌❌ | 小 CNN prior 噪声太大 |
| 0.90 | iter1 <20% ❌❌ | 完全 CNN 主导，崩 |

**教训**：50/50 是小网络的安全区。往任何一侧偏都坏。
- 偏 pattern 太多 → CNN 变装饰品
- 偏 CNN 太多 → 小网络 prior 的噪声主导搜索，MCTS 走偏

如果换成 256f/10b 或更大的网络，CNN prior 可能可靠到能 0.7+，但我们这个规模不行。

### 9.2 Replay Buffer 架构演进

训练数据池（replay buffer）的设计踩了两轮坑：

**v1：单 FIFO buffer**
- 所有历史数据一个队列，满了就扔最老的
- 一次 iteration 的新数据一下子把 bootstrap 的老数据全挤出去
- 结果：新训出来的模型 **"忘了"** teacher 教的基础，崩盘 40%

**v2：两池（bootstrap anchor + fresh FIFO）**
- bootstrap pool 不淘汰（保持老师的"锚"）
- fresh pool 每轮更新
- 训练时从两池各抽一半

这个改动解决了 forgetting 问题。

**v3（当前）**：发现从 iter_3+ 继续迭代时，**bootstrap pool 其实不需要**。因为 CNN 已经远超老师了，老师的数据反而是低质量的。删掉 bootstrap pool 也没事。

**但**：如果 `{model_path}_samples.pkl` 不存在时，代码有个小 bug：
```python
bootstrap_pool = []  # 空
fresh_cap = int(0 * args.fresh_ratio)  # = 0
fresh_pool[-0:]  # Python quirk! 这返回整个 list
```

**Python 的 `list[-0:]` 返回完整列表**，不是期望的空列表。所以 fresh pool 无限增长（Phase A 第 4 轮已经 174k+ 样本）。没有爆掉但是 bug。

修复：
```python
if len(bootstrap_pool) == 0:
    fresh_cap = args.replay_size  # 用配置的上限
```

### 9.3 Static vs Continuous Leaf Eval

这是另一个关键诊断。

**症状**：用 bootstrap 模型做 self-play，**90% 游戏都是 225 步平局**（走完整个棋盘）。训练数据全是平局，CNN 学不到胜负信号，loss 不降，迭代不前进。

**诊断过程**：
- 打印每局最后一步，发现两方一直在"占地"，互相不进攻
- 读 MCTS 代码：叶子节点评估用 `_static_leaf_value()` 
- 这个函数只判断"一步必胜"，中间局面返回 EMPTY（映射成 0.5 平）
- **MCTS 收到的所有叶子信号都是 0.5**，完全区分不出哪一步更好，退化成"在走法分布上做均匀采样"

**修复**：改成 continuous leaf eval
```python
def _continuous_leaf_value(board, player):
    my_score = pattern_eval.score_for(board, player)
    op_score = pattern_eval.score_for(board, opponent)
    diff = my_score - op_score
    return np.tanh(diff / 1000.0)  # [-1, +1] 连续信号
```

修复后 self-play 游戏长度从"225 步平局"变成"30-80 步决胜"。训练数据质量大幅提升。

**教训**：MCTS 的叶子信号一定要**连续、有区分度**。离散的二值信号在大多数情况下等于没信号。

### 9.4 Bootstrap 数据"反噬"问题

iterate.py 默认会加载 `{model_path}_samples.pkl`（bootstrap 时保存的训练数据）作为 anchor pool。

对 `gen_final.pt` → iter_3，这是对的：bootstrap 数据是 teacher 的黄金标准。

**但**从 `iter_3.pt` 继续迭代时，bootstrap 数据**比 iter_3 的 self-play 数据质量低**。这些低质量数据反而拖后腿。

日志里会出现 warning "will overfit on fresh games only" —— 其实不是问题，反而是好事。

**教训**：model progression 到一定程度后，**老数据是负资产，不是遗产**。

---

## 10. 经验教训 TL;DR

浓缩版 —— 遇到新的 AI 训练问题时快速翻这几条：

1. **冷启动 RL 在小算力下不可行**。需要先 supervised bootstrap 一个基础模型，再用 RL 迭代提升。

2. **特征工程比想象中重要**。9 通道输入（含 pattern masks）让 CNN 快 1-2 个数量级收敛。不要迷信"让网络从像素学所有东西"。

3. **小网络必须配 pattern prior**。纯 CNN prior 在小模型上噪声太大。50/50 Hybrid 是安全区。

4. **MCTS 叶子信号必须连续**。离散二值（必胜/非必胜）在绝大多数局面等于没信号。用 `tanh(score_diff)` 给渐变值。

5. **Replay buffer 要分两池**（bootstrap anchor + fresh FIFO）防止 forgetting。但从 strong checkpoint 继续时可以只用 fresh。

6. **迭代的收益递减很快**。小模型 3 代到头，大模型也就 1-3 代明显进步。更长的迭代不会再赚。

7. **Benchmark 至少 40 局**。40 局标准差 ~8%，少于这个数得到的"胜率"不可靠。

8. **Loss 趋势比绝对值重要**。loss drop % 能直接反映学习质量。loss 几乎不动 = 数据是噪声。

9. **训练数据的游戏长度要正常**。如果 self-play 大量出现 225 步平局，说明 leaf eval 有问题，不是模型不会下。

10. **能用监督学习就别用强化学习**。SL 稳定可控，RL 难调参且收敛慢。只在突破 teacher 上限时才切到 RL。

---

## 11. 当前模型与部署现状

### 11.1 模型谱系

```
gen_final.pt (48f/3b, bootstrap from pattern teacher)
    ↓ iterate (v4)
iter_3.pt (48f/3b, 3 轮迭代)
    ↓ iterate (phA) — marginal, plateau
phA_iter_3.pt (48f/3b, 近似 iter_3 强度)

bootstrap_128f6b.pt (128f/6b, bigger bootstrap)
    ↓ iterate (overnight_128f6b)
big_iter_1.pt (128f/6b, 66% vs bootstrap) ★ 当前最佳
big_iter_2.pt (128f/6b, plateau)
big_iter_3.pt (128f/6b, plateau)
```

### 11.2 线上使用

- **`best_model.pt`** = `big_iter_1.pt` 的副本，提交到 git（8.1 MB）
- **`best_model.onnx`** = 导出给 Godot/iOS 推理用（8.0 MB 单文件，内嵌 `.data` 权重）
- **`export_onnx.py`**：导出脚本，新 PyTorch 上要 `dynamo=False` + `save_as_external_data=False`
- **`build/Gomoku_signed.zip`** (2026-04-15 起) = macos-cd workflow 产物，已签名 + 公证 + stapled，双击即开

### 11.3 Godot 集成

- Level 6 = CNN + MCTS，走 Python AI Server（TCP :9877）
  - **重要**：onnx_server.py 现在包含 MCTSEngine（2026-04-15 前是纯 CNN no MCTS，强度被砍一半 —— 见 Section 13.1-C）
  - 默认 80 sims，可通过 `--sims N` 或 `GOMOKU_SIMS` 环境变量覆盖
- AI server launcher：15 秒 poll 循环（2026-04-15 前是 1.5s 固定超时，经常错误 fallback —— 见 Section 13.1-B）
- macOS：AI Server 嵌入 .app bundle，游戏启动时自动 launch；`model.onnx` 放在 `Contents/Resources/`（不是 `MacOS/`，Apple codesign 要求）
- Linux：AI Server 在可执行文件同目录
- iOS：**Level 6 被禁用**（`scenes/ai_setup/ai_setup.gd` 里硬编码 hide on mobile），因为 iOS 沙箱不能 subprocess。iOS 上只有 Level 1-5（纯 GDScript）

### 11.4 训练成本参考

MacBook Air M5 + MPS：
- Bootstrap 128f/6b 50 epoch：~3 小时
- 一轮 iterate 150 局 × 1600 sims：~5 小时
- Benchmark 40 局 × 200 sims：~2 分钟

---

## 12. 未来方向

### 12.1 已经走不通的方向（别再试）

- ❌ **纯 CNN prior（weight > 0.5）** —— 小网络不够稳
- ❌ **继续迭代 48f/3b** —— 架构上限到了
- ❌ **简单重跑 iterate 更多轮** —— 同一配置不会更好
- ❌ **加长 CNN value head 当 leaf eval** —— 小网络的 value 噪声太大
- ❌ **冷启动 AlphaZero** —— 除非有 2000 TPU

### 12.2 可能有收益的方向

- ✅ **更大网络 256f/10b** —— 参数 4 倍，可能支撑更高 cnn_prior_weight
- ✅ **Teacher 升级** —— 用 big_iter_1 自己当 teacher 重 bootstrap（self-distillation）
- ✅ **更长 MCTS（3200+ sims）** —— 需要服务器或耐心，能给 CNN 更高质量信号
- ~~**引入 VCF search**~~ —— **2026-04-16 已做**，加上了 VCT（见 §14.3）
- ✅ **对抗式数据生成** —— 找 big_iter_1 的弱点（比如开局某些 pattern）针对性补样本

### 12.3 最现实的下一步

如果想再做一轮训练，我会：

1. 换 256f/8b 网络（参数约 2-3 倍）
2. Teacher 改成 big_iter_1（self-distill bootstrap）
3. Simulations 用 3200（M5 晚上跑一轮需约 10h，可接受）
4. 只跑 3 个 iteration，别贪多

预期：或许能拿到 55-60% vs big_iter_1。如果跑出来不到 52%，说明这条路也到头了，该换思路（更大网络、或不同 teacher 范式）。

---

## 13. Part 2: 部署成熟化（2026-04-15 下午）

开发主体完成后，花了半天把"能跑"变成"能交付"。两大块：**AI 性能问题诊断 + 修复**、**macOS 签名公证 CI 流水线**。

### 13.1 AI 性能 4 个 Fix

用户反馈 Mac 上 Level 5（MCTS）和 Level 6（CNN AI）都很慢。诊断后发现是 4 个不同问题：

**A. Level 5 GDScript MCTS 默认 5000 sims 太多**
- 实测 Ubuntu VM: **246 秒/步**（M5 上约 60-90 秒，不能忍）
- GDScript 每 sim 做 15×15 棋盘深拷贝 + 每 rollout 步重扫 225 格，本质上算法可接受、实现在解释器里跑不动
- 降到 1500 sims + rollout 步长 100→40 后约 10 秒/步

**B. Level 6 启动器 timeout bug**（实战里的"伪 Level 6"）
- `ai_server_launcher.gd:30` 写死 `await 1.5 秒` 然后检查 TCP 端口
- 但 pyinstaller + onnxruntime 冷启动需要 4-5 秒
- 超时后 `_use_server = false` → Level 6 静默 fallback 到 GDScript MCTS(3000)
- **用户以为自己在玩神经网络 AI，实际用的 MCTS（还慢还弱）**
- 修复：15 秒 poll 循环（500ms 间隔），首次冷启动给足时间；warm 启动 <2 秒即 ready

**C. 部署版 Level 6 没用 MCTS**（架构层面的"伪 Level 6"）
- 这个坑最大。训练时用 `mcts_engine.py` 做 800-1600 sims 的 MCTS + CNN 混合搜索
- 但**部署用的 `onnx_server.py` 只跑一次 CNN forward pass，直接取 argmax**
- 等于把训练出来的 AI 拆了一半能力 —— 相当于训了 Alpha-MCTS，部署成 Alpha-Direct
- 为什么这样？早期开发期图简单，忘了 MCTS
- 修复：给 `onnx_server.py` 加 `OnnxModelAdapter` 类，把现成的 `MCTSEngine` 插进去，80 sims 默认
- 性能惊喜：hybrid 模式下 **CNN 只在 root 调用一次算 priors**，leaf eval 用 pattern-based tanh（纯 numpy）
- 实测 1 核 Ubuntu VM：普通局面 700ms，强制堵 14ms
- M5 上预估 150-200ms/步 —— 比重写前的"每 leaf 跑 CNN"快一个量级

**D. `model.onnx` 命名问题**
- weights 目录只有 `best_model.onnx`，但 server 默认找 `model.onnx`
- 双保险：`find_model()` 加回退路径、`build_server.sh` 自动 cp

### 13.2 关键教训 Part 2（补充到 TL;DR）

11. **部署和训练必须用同一套推理逻辑**。Section 13.1-C 的坑特别隐蔽 —— 训练指标完美，线上却弱。任何时候部署侧简化了推理管道，都要用基准测试对比原版确认强度没掉。

12. **"Level 6 慢"的 bug 常常不是 CNN 慢，而是 fallback 被触发了**。用户看到的"慢 AI"可能根本不是你想的那个 AI。加 UI 显示当前 AI 类型（"Neural (server)" vs "Neural (MCTS fallback)"）很重要。

13. **timeout 要配 poll，不要固定 sleep**。单点等待假设每个环境启动时间相同 —— 永远错。poll 间隔要考虑单次探测的开销（我们的 `_check_port_open` 自带 1s TCP timeout，poll 间隔 500ms 就够）。

### 13.3 macOS 签名 + 公证流水线

第二大块工作：把 Mac 分发从"未签名 + 用户 `xattr -cr`"变成"双击就开、不被 Gatekeeper 拦"。成果：`.github/workflows/macos-cd.yml`，推 `macos-v*` tag 或手动触发，产物是 `Gomoku_signed.zip`（~94MB，已签名 + 公证 + stapled）。

踩了 14 个坑才打通。**这些坑每一个都可能在未来重现**，记下来省未来大量时间：

| # | 问题 | 根因 | 修复 |
|---|---|---|---|
| 1 | `com.gomoku.game` 不存在 Apple Developer portal | 早期乱起的占位名 | 改用 `com.jasonhorga.gomoku`（iOS/macOS 共用一个 App ID） |
| 2 | ASC API 创建 Developer ID 证书报 generic error | **Apple ASC API 对 Developer ID 支持时好时坏**，Admin 权限也不保证能成 | 放弃 API 路线，**Mac 上手动生成 CSR → 下载证书 → 导出 .p12 → `fastlane match import`** |
| 3 | Godot 4.2.2 macOS export 报 "configuration errors" 无具体原因 | Godot 4.2 的 macOS 导出在非 macOS 平台（甚至 macos-15 runner）都挂，错误信息被截断 | CI 升级 Godot 到 4.5.1（4.5 打印具体错误） |
| 4 | Godot 4.5 要求 ETC2 ASTC 纹理 | arm64/universal export 在 4.5 里强制 | `project.godot` 加 `rendering/textures/vram_compression/import_etc2_astc=true` |
| 5 | Export 模板找不到 `godot_macos_release.arm64` | Godot 4.5 模板里只有 universal 二进制 | preset 里 `binary_format/architecture` 从 `arm64` 改成 `universal` |
| 6 | `build_app.sh: Permission denied` | `actions/checkout@v4` 在 macOS runner 上不保留 exec bit | 改用 `bash build_app.sh` 调用 |
| 7 | `Gomoku.app/Contents/MacOS: No such file or directory` | Godot 把 .app 命名成 "五子棋 Gomoku.app"（取自 `config/name`，含中文+空格） | `build_app.sh` 动态查找 `*.app`，重命名成 `Gomoku.app`，并 normalize 内部 binary/pck 名称 |
| 8 | `security import: MAC verification failed during PKCS12 import (wrong password?)` | **macOS 15 / Xcode 26 的 `security import` 拒绝空密码 .p12**（不管算法多现代/多 legacy） | 给 .p12 设置非空密码（用 MATCH_KEYCHAIN_PASSWORD） |
| 9 | `fastlane match` 的 cert installer 默认用空密码 | match 内部假定 .p12 无密码 | **绕过 match 的 cert install**，Fastfile 里手动 `git clone` + `Match::Encryption.decrypt` + `security import -P <known>` |
| 10 | 手动 `security find-identity` 返回空 | 引用方式错（`gomoku-macos-signing.keychain` 而不是完整路径） | 用 `$HOME/Library/Keychains/<name>-db` 完整路径 |
| 11 | `codesign ... Gomoku.app` 报 "In subcomponent: MacOS/model.onnx" + "code object is not signed at all" | **Apple 不允许 `.app/Contents/MacOS/` 下放非 Mach-O 数据文件**。model.onnx 必须在 Resources/ | `build_app.sh` 把 model.onnx 放 `Contents/Resources/`，`onnx_server.py` 的 `find_model()` 加 `base/../Resources/` 到搜索路径 |
| 12 | fastlane `sh` 和 workflow step 的 cwd 不一致 | fastlane 的 runner 会 `chdir` 到 fastlane/ 目录 | 所有路径改绝对路径（`GOMOKU_APP_PATH: ${{ github.workspace }}/build/Gomoku.app`） |
| 13 | match 对 Developer ID 强制要 provisioning profile | Developer ID 分发（非 App Store）其实不需要 profile，但 match 不支持跳过 | 跳过 match 本身的 install 流程（见 #9） |
| 14 | 最终 zip 路径相对 | 和 #12 同源 | `File.join(File.dirname(app_path), "Gomoku_signed.zip")` |

**这 14 个坑里 #8 和 #11 是最"隐蔽"的**：openssl 能正常读我们的 .p12 + Apple security 不能读；Godot 能跑 + Apple codesign 拒绝。**macOS 的 `security` 和 `codesign` 比任何 OpenSSL 标准都严**。

### 13.4 一次性 bootstrap 的 Developer ID 证书

因为 ASC API 拒绝自动创建 Developer ID 证书（坑 #2），未来换 Apple Developer 账号、或证书过期（5 年一次）时，需要重复这个一次性流程：

1. **Mac 上**（Keychain Access）:
   - Certificate Assistant → Request a Certificate From a Certificate Authority → Saved to disk → 得到 `CertificateSigningRequest.certSigningRequest`
2. **Apple Developer portal**（https://developer.apple.com/account/resources/certificates/add）:
   - 选 **Developer ID Application** → **G2 Sub-CA** → 上传 CSR → 下载 `.cer`
   - 双击 .cer 安装到 login keychain
3. **Mac Keychain Access 导出 .p12**:
   - login → My Certificates → 右键 "Developer ID Application: ..." → Export → 选 .p12 → 设密码
4. **Linux dev 机**:
   - `openssl pkcs12` 换成 legacy 格式 + empty → non-empty password → 用 fastlane Match::Encryption 加密 → commit 到 gomoku-signing repo master 分支

具体命令在 git history `7a58d37`、`9162022`、`5aad6fc` 的 commit 里。

### 13.5 当前部署状态（2026-04-15 收尾）

- **`Gomoku_signed.zip`** (94MB) 在 `build/` 目录，签名 + 公证 + stapled
- **Developer ID cert** 存在 `jasonhorga/gomoku-signing` master 分支，加密格式是 fastlane match v2（AES-GCM + PBKDF2-HMAC-SHA256）
- **macos-cd workflow** 每次手动触发（或推 `macos-v*` tag 自动），~3-5 分钟跑完（含 notary 等待）
- **iOS pipeline** 尚未测试（iOS CI 的 signing bootstrap 也没跑过，下一次真要发 iOS 时再测）

---

## 14. Part 3: AI 缺陷修补（2026-04-16/17）

交付之后又挖出三类问题，每一类都暴露"最初设计时把五子棋当过于简单了"：
L5 MCTS 架构不对、L6 看不到多步杀棋、整个棋型评估器从没识别过分裂棋型。

### 14.1 L5 MCTS 比 L4 Minimax 还弱

用户在 AI Lab 里用 L4 vs L5 跑 20 局 batch，**L4 全胜 20:0**。
这显然和直觉不符——MCTS 3000 次模拟应该碾压固定深度 4 的 Minimax。

诊断：原版 L5 是"UCB1 + 半随机 rollout"——
- UCB1 没有先验，15×15 的 100+ 候选走法都要靠访问次数试探
- 半随机 rollout（有活四必下、有活三必堵）对一盘还有 20 步的局面信号基本是噪声
- 两个弱环节叠加，3000 sims 的"见得多"根本没变成"选得准"

**修复（2026-04-16）：把 L5 改成 AlphaZero 风格但不要神经网络**
- UCB1 → **PUCT**（引入先验项）
- 先验来源：**棋型评估器**（pattern_evaluator.score_cell 归一化）
- 随机 rollout → **棋型叶值**（`tanh(board_eval_diff / 1000)`）
- Expansion：根节点一次性展开所有候选并附上先验
- 即时胜/堵做成短路：在 root 之前扫一遍，命中直接返回

重写后用户测：L5 稳定赢 L4。架构是对的，问题在于最初"把 MCTS 当独立搜索"时没有配棋型先验。

用户直接问了："MCTS 最开始设计就有这个问题？那你之前的设计文档瞎写的？"
——这是公平的质问。以后 MCTS 类算法在小棋盘上不加先验属于基本错误。

### 14.2 L6 被用户老婆打败 → MCTS 模拟数太少

2026-04-16 晚上用户老婆作为黑棋赢了 L6。复盘棋谱看到的是一串**双威胁**组合：
白棋每一步都在被迫堵某个威胁，但每堵一个新的威胁出现，走到第 48 手必输。

诊断：
- L6 部署时 sims=80，这在棋型已经明显的中局不够
- 更重要的：L6 **只看当前棋型分数**，看不到"2 步后会形成双威胁"这种深度战术

用户反馈："感觉可以再慢点"——可以接受 L6 单步多思考几秒。

**修复：**
1. `onnx_server.py` 默认 simulations 80 → **200**
2. 加 **VCT (Victory by Continuous Threats)** 战术搜索（下面 §14.3）

### 14.3 VCF 不够用，需要 VCT

原来的 `vcf_search.py` 只找"连续冲四必杀"。但用户老婆那盘棋的杀棋组合
含有**活三 + 冲四**交替——VCF 找不到，因为它只看冲四分支。

用户问："VCT 是通常做法么？设计的时候怎么没有？能不能系统性讲讲各种方法？"
——又是一次公平质问。系统回答：

```
战术搜索方法全景（Allis 1994 et al.）:

┌──────┬────────────────────────────┬──────┬──────────┐
│ 名称  │ 定义                        │ 分支  │ 能捕捉的  │
├──────┼────────────────────────────┼──────┼──────────┤
│ VCF   │ 连续冲四必杀                 │ ~1   │ 单线杀棋  │
│ VCT   │ 连续威胁（冲四 + 活三）必杀    │ 2-6  │ 双威胁    │
│ TSS   │ Threat Space Search         │ 更宽 │ 任意威胁  │
│       │ (含活二双三等更广威胁)        │      │ 组合     │
└──────┴────────────────────────────┴──────┴──────────┘
```

实现 VCT（`ai_server/ai/vct_search.py`，~170 行）：
1. 先调用 VCF，有解直接返回
2. 没有 VCF 解时，枚举"造活三的走法" + "冲四走法"作为分支
3. 对每个分支递归到对手必防步，然后继续找下一个威胁
4. 深度超过 `max_depth=6` 或分支超 `max_branch=6` 即回退

`mcts_engine.py` 在 `search()` 开头跑两遍（己方必杀 + 对方必杀），命中直接返回。

VCT 对用户那盘棋的实测：如果 L6 在关键局面能早几步看到"对方 3 步内必杀"，
就会避开触发点而不是被动堵。

### 14.4 棋型评估器从来没识别过分裂棋型

部署 VCT 后我再跑用户那盘棋，VCT 还是没找到对方的必杀。重新复盘发现：
**用户老婆的杀棋组合用的是 `XX_X`、`XXX_X` 这种分裂棋型**，
而整套棋型评估器只看连续棋型。

用户直接说："分裂三 分裂四本来就是标准应该防范的啊，是不是 planning 又错了？"

这是**第二次**暴露"最开始把五子棋当简单的填格子游戏"。
Allis 的 Gomoku 论文（1994）里分裂棋型是基本棋型。
把它漏掉意味着：
- 棋型评估器的打分偏低（很多威胁看不见）
- VCF/VCT 枚举威胁走法时漏掉"填缺口成活四/五"的组合
- CNN 训练时的 teacher 也看不见 → 学到的 policy 也不会针对分裂棋型

**修复：双侧都补上**

Python 侧 (`ai_server/ai/pattern_eval.py`):
- 新增 `_scan_line()` 代替 `_count_consecutive()`，除了连续段数，还向缺口另一侧扫描
- 新增 `_gapped_score()`: N+1 gap 棋子 → 填缺口成五连 → half_four；N=3 → half_three
- `evaluate_position()` 每方向取 `max(连续分, 分裂分)`

GDScript 侧 (`scripts/ai/pattern_evaluator.gd`)—**2026-04-17 补**：
- 同样加 `_scan_line()` 返回 `Vector3i(cons, gap_stones, end_open)`
- `_evaluate_position()` / `_evaluate_existing_stone()` 都走新逻辑
- `_evaluate_existing_stone()` 多一个"起点检测"：跳过"有同色子跨缺口在我之前"的位置，避免同一分裂线被计两次
- 回归测试：`tests/test_gapped_patterns.gd`（5 个 case 全过）

`vcf_search.py` 也在 `_four_info()` 里增加了分裂四检测，把填缺口走法加入威胁枚举。

### 14.5 关键教训 Part 3

14. **不要从"现有代码能做什么"反推"需求是什么"**。两次翻车都是这个模式：
    最初写 MCTS 时没想到要加棋型先验，因为"原版 UCB1 算法不需要"；
    最初写棋型评估时只看连续棋型，因为"代码扫描连续段更自然"。
    正确路径是先梳理"Gomoku AI 需要识别的完整棋型集合 + 搜索策略集合"，
    再看代码覆盖到哪里。文献（Allis 1994 的 Gomoku 论文）就是答案。

15. **用户的领域直觉是最锋利的 review 工具**。两次都是用户（业余玩家）
    直接说"标准应该防范的"，我才意识到缺了什么。遇到用户说"这个很基本吧"时，
    立刻停下来对照文献检查，不要急着解释现状。

16. **改 Python 不能忘同步 GDScript，反之亦然**。棋型评估器双实现必须一致，
    不然 L2/L4/L5（GDScript）看得见某个威胁、L6（Python）看不见，或反过来，
    会产生诡异的"档位互克"。

### 14.6 当前 AI 栈状态（2026-04-17）

```
┌──────────┬────────────────────────────────────────┐
│ Level    │ 实现                                    │
├──────────┼────────────────────────────────────────┤
│ L1 Random│ 随机落子                                 │
│ L2 Heur  │ 棋型评分（连续 + 分裂） + 贪心取 max       │
│ L3 MiniM │ Minimax d2，棋型评估                     │
│ L4 MiniM │ Iter-deepening d4 + 置换表 + killer move │
│ L5 MCTS  │ PUCT + 棋型先验 + 棋型叶值，1500 sims     │
│ L6 NN    │ PUCT + (0.5 CNN + 0.5 棋型) 先验 + 棋型叶  │
│          │ 值 + VCF + VCT，200 sims                 │
└──────────┴────────────────────────────────────────┘

棋型识别（双侧同步，2026-04-17）:
  连续: five, open_four, half_four, open_three, half_three, open_two, half_two
  分裂: split-four (XXX_X) → half_four
        split-three (XX_X) → half_three

战术搜索（L6 专用）:
  VCF (深度 10) — 连续冲四必杀
  VCT (深度 6, 分支 6) — 冲四 + 活三混合必杀

权重调优功能已删除 (2026-04-16)：
  原设计"AI vs AI 批量 → 统计胜方棋型 → 调权重"，
  实测 99% 时候会回归到初始权重，没有实际改进效果。
```

---

## 附录：关键文件索引

```
ai_server/
  ai/
    game_logic.py       — 15×15 棋盘、胜负判定、to_tensor_9ch
    pattern_eval.py     — 棋型分数（连续 + 分裂，2026-04-17 补）
    mcts_engine.py      — Hybrid MCTS（前置 VCF/VCT 战术短路）
    vcf_search.py       — VCF 战术搜索（连续冲四必杀）
    vct_search.py       — VCT 战术搜索（冲四 + 活三必杀，2026-04-16 新增）
  nn/
    model.py            — GomokuNet (ResNet + 双头)
    bootstrap.py        — Phase 1: 监督学习 bootstrap
    iterate.py          — Phase 2: 迭代自我提升
    parallel_self_play.py — 多进程 self-play
    trainer.py          — Adam + policy CE + value MSE
    augment.py          — 8x 对称增强
  data/weights/         — 所有 .pt/.pkl/.onnx 模型文件
  logs/                 — 所有训练 log（粒度到每局）
  
docs/
  ai_journey.md         ← 本文档（总览 + 原理 + 部署）
  technical_guide.md    ← 技术细节参考（代码级）
  training_v2_strategy.md ← 2026-04-11 v2 设计当时的想法（历史）
  upgrade_plan.md       ← 2026-04-09 Phase 1-5 总体规划（已完成）
  dev_log.md            ← 2026-04-09 早期开发日志（游戏部分）

.github/workflows/
  ios.yml                    ← iOS TestFlight CD (未实测)
  signing-bootstrap.yml      ← iOS match bootstrap (未实测)
  macos-cd.yml               ← macOS 签名+公证 pipeline (2026-04-15 打通)
  macos-signing-bootstrap.yml ← macOS Developer ID bootstrap (已失败，用手动 path B 代替)

fastlane/
  Fastfile              ← iOS + macOS lanes (macOS 用手动 security import 绕过 match)
  Appfile               ← iOS app identifier
  entitlements-macos.plist ← codesign hardened runtime entitlements

run_overnight_128f6b.sh ← 生成 big_iter_1 的训练脚本（参考配置）
```
