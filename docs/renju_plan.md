# 禁手规则 + 模型重训 Plan

## 背景

无禁手 15×15 Gomoku 数学上**黑必胜**（Allis 1993）。当前 L4 minimax+TT 能利用这点用双重威胁强制胜，L6 (CNN+MCTS 200 sims) 在 65-90% 范围。要让 L6 真正稳定碾压 L4，**单纯调参/加 sims 不够**——需要要么换游戏规则（禁手），要么重训更强的模型。

禁手规则（Renju 标准）：
- **黑棋限制**：不能下 **三三**（双开三）、**四四**（双四）、**长连**（6 连及以上）
- **白棋无限制**
- 黑必须以恰好 **5 连** 取胜
- 这个规则平衡了黑方先手优势

---

## 目标

1. App 增加 **禁手规则开关**（玩家可选启用 / 关闭）
2. 启用禁手时，AI 各等级都遵守规则
3. **重训一个禁手专用 CNN 模型**（与现有自由对局模型并存）
4. 制定**未来模型重训流程**，让后续训练标准化

---

## 整体架构

```
游戏开始
  ├── 玩家选择规则：[ ] 禁手  [ ] 自由对局
  ├── 选择 AI 等级 L1-L6
  └── 启动游戏
       ├── L1-L4 (GDScript): 加禁手过滤候选
       ├── L5 (Swift pattern-MCTS): 加禁手过滤
       └── L6 (Swift CNN+MCTS): 
             - 自由对局 → 当前模型 model.onnx
             - 禁手对局 → 新模型 model_renju.onnx
```

---

## 阶段 1：禁手检测算法 (P4.1)

**核心函数**：`is_forbidden_black(board, row, col) -> bool`

**算法**（在空 cell (r,c) 假设黑下棋后判定）：

1. **检查长连**：4 方向扫描，任一方向 ≥6 连续黑子 → 禁手
2. **检查四四**：统计本步形成的"四"数量
   - "四" = 此处放黑后能在下一步形成 5 连的 pattern
   - 包括开四 (open_four)、半开四 (half_four)、跳四 (gap_four)
   - ≥2 个不同方向上的四 → 四四禁手
3. **检查三三**：统计本步形成的"开三"数量
   - "开三" = 此处放黑后能在下一步形成开四的 pattern（必须是真活三）
   - ≥2 个不同方向上的开三 → 三三禁手
4. **五连优先**：如果本步形成恰好 5 连 → 胜利（不视为禁手）
5. **递归判定**：判断三三时，若一个三延伸成四后会触发禁手，则不算真活三（高级规则，可选）

**测试用例**（必须覆盖）：
- 双开三：B(7,7),W(*),B(7,8),W(*),B(8,8) — 黑下 (8,7) 触发双开三禁手
- 双开四：黑同时形成两条 4 连
- 长连：黑形成 6 连
- 四三组合（合法，不禁手）

**实现位置**：
- `ai_server/ai/forbidden.py`（Python，用于训练 + 参考实现）
- `ios_plugin/Sources/Forbidden.swift`（Swift，用于 L5/L6 推理）
- `scripts/ai/forbidden.gd`（GDScript，用于 L1-L4 + UI）

**预计工作量**：~6 小时（3 个语言 × 2 小时）+ 测试

---

## 阶段 2：UI 和游戏规则 (P4.2)

**改动点**：

1. **Local PvP 设置**（local_pvp_setup.tscn — 如果存在）和 **AI Setup**（ai_setup.tscn）
   - 加 CheckBox "禁手规则" （默认关闭，符合大众习惯）
2. **Game Manager** 跟踪 forbidden_enabled 状态
3. **Game Logic** (`scripts/game_logic.gd`)
   - `place_stone()`：黑方下棋时调用 forbidden 检测
   - 黑下禁手 → 立即判白胜（显示 "黑棋禁手负"）
4. **棋盘视觉**：黑方回合时，禁手位置可以画"×"提示（可选）
5. **结束面板**：
   - "胜方：白方（黑禁手）"

**预计工作量**：~3 小时

---

## 阶段 3：AI 不重训情况下兼容禁手 (P4.3)

**目标**：不重训也能跑禁手对局，但 AI 强度会有损失（CNN 训练时不知道禁手）。

**改动**：

1. **Pattern Evaluator**（3 语言）
   - `score_cell(board, r, c, player, forbidden_enabled)`：
     - 如果 player==BLACK 且 forbidden_enabled 且 is_forbidden_black(board, r, c) → 返回 -∞
2. **MCTS Engine**（Python + Swift）
   - 候选生成时过滤掉黑方禁手位置
3. **VCF/VCT 搜索**（Python + Swift）
   - attacker==BLACK 且 forbidden_enabled 时，过滤候选
4. **Move Validation**（GDScript）
   - L1-L4 选 move 后再检查一次禁手（防止 random 选到禁手）

**预期效果**：L6 在禁手模式下能下棋但棋力弱化 ~5-10%（CNN priors 偶尔指向禁手位置，需要被过滤）

**预计工作量**：~4 小时

---

## 阶段 4：禁手 CNN 重训 (P4.4) ★关键阶段

### 4a. Training Pipeline 改造

文件改动：
1. `ai_server/ai/game_logic.py`：加 `forbidden_enabled` 参数
2. `ai_server/ai/pattern_eval.py`：黑方 score_cell 检查禁手
3. `ai_server/ai/mcts_engine.py`：候选过滤
4. `ai_server/nn/bootstrap.py`：传 `forbidden_enabled=True`
5. `ai_server/nn/iterate.py`：传 `forbidden_enabled=True`

### 4b. Bootstrap 训练（pattern-MCTS teacher）

```bash
cd ai_server
python3 -m nn.bootstrap \
    --games 200 --simulations 400 --epochs 50 \
    --filters 128 --blocks 6 \
    --forbidden \
    --save-name renju_bootstrap_128f6b.pt \
    --log-file renju_bootstrap.log
```

预计 4-6 小时（pattern-MCTS 在禁手模式下分支更窄，可能快一点）

### 4c. Iterate 自我对弈精炼

```bash
python3 -m nn.iterate \
    --initial-model data/weights/renju_bootstrap_128f6b.pt \
    --iterations 8 --games-per-iter 150 --simulations 800 \
    --epochs 10 --lr 1e-4 \
    --filters 128 --blocks 6 --vcf-depth 10 \
    --forbidden \
    --benchmark-games 40 --benchmark-sims 200 \
    --converge-threshold 0.50 \
    --cnn-prior-weight 0.5 \
    --checkpoint-prefix "renju_" \
    --log-file renju_iterate.log
```

预计 8-12 小时（自我对弈 8 轮，每轮 ~1 小时）

**总训练时间：约一晚（12-18 小时）**

### 4d. 模型导出

训练完最佳 checkpoint → ONNX → mlpackage → mlmodelc：

```bash
python3 export_coreml.py data/weights/renju_iter_N.pt \
    --filters 128 --blocks 6 \
    -o /tmp/GomokuRenjuNet.mlpackage
xcrun coremlc compile /tmp/GomokuRenjuNet.mlpackage /tmp/
```

最终产物：`GomokuRenjuNet.mlmodelc`（与现有 `GomokuNet.mlmodelc` 并存）

**预计工作量**：~2 小时改 pipeline + 一晚训练 + 1 小时导出和 bench

---

## 阶段 5：模型分发和分发 (P4.5)

### 5a. App Bundle 改造

iOS xcframework + macOS .app 都需要打包**两个 mlmodelc**：
- `GomokuNet.mlmodelc`（自由对局）
- `GomokuRenjuNet.mlmodelc`（禁手）

CI 改动：
- `ios.yml` 和 `macos-cd.yml`：编译两个 .pt → 两个 .mlmodelc → 都注入 .app
- `build_app.sh`：copy 两个 .mlmodelc 到 Resources/

App 大小预估：每个模型 8MB → 总增加 ~8MB，可接受

### 5b. Code Dispatch（Swift）

`GomokuMLCore.swift`：

```swift
private var coreMLAdapterFree: CoreMLAdapter?
private var coreMLAdapterRenju: CoreMLAdapter?

@objc public func chooseMove(level: Int, board: [[NSNumber]], 
                             player: Int, forbiddenEnabled: Bool) -> CGPoint {
    let modelName = forbiddenEnabled ? "GomokuRenjuNet" : "GomokuNet"
    let adapter = ensureCoreMLLoaded(modelName: modelName)
    // ... rest of logic
}
```

GDScript wrapper：传入 forbidden_enabled 参数

**预计工作量**：~3 小时

---

## 阶段 6：测试 + Polish (P4.6)

1. **单元测试**：禁手检测的所有边缘 case
2. **集成测试**：跑禁手 batch L1 vs L1, L4 vs L6, L6 vs L6
3. **回归测试**：自由对局 batch 仍然 90% L6 vs L4
4. **iOS 设备验证**：实机跑禁手模式
5. **UI polish**：禁手提示动画、错误提示

**预计工作量**：~4 小时

---

## 总工作量估计

| 阶段 | 工时 | 备注 |
|---|---|---|
| P4.1 检测算法 | 6h | 3 语言实现 + 测试 |
| P4.2 UI/规则 | 3h | toggle + 游戏结束 |
| P4.3 AI 兼容（不重训） | 4h | pattern eval + MCTS 过滤 |
| P4.4 重训 CNN | 2h + 一晚 + 1h | pipeline + train + export |
| P4.5 双模型分发 | 3h | CI + Swift dispatch |
| P4.6 测试 | 4h | 单元/集成/UI |
| **总计** | **22h + 一晚训练** | 约 3 工作日 |

---

## 未来模型重训标准流程（独立于禁手）

不论是禁手还是其他改动，重训流程应该标准化：

### 触发场景
- 发现 L6 系统性弱点（如本次的双重威胁 fork）
- 网络架构升级（128f/6b → 256f/8b）
- 改变输入特征（如增加 pattern channels）
- 增加新的训练数据

### 标准流程

1. **Baseline benchmark**：当前最佳模型 vs L4 minimax，记录基准胜率
2. **改 pipeline**：修改 bootstrap.py / iterate.py / 数据增强 / 网络架构
3. **本地小规模验证**：50 games × 100 sims，~30 分钟，看 loss 下降是否健康
4. **过夜大规模训练**：bootstrap → iterate ≥ 5 轮，每轮 benchmark
5. **新模型 vs baseline**：100 games L4-vs-L6 + L6-vs-L6 互测
6. **决策**：
   - 新模型 ≥ baseline + 5%：上线
   - 新模型 < baseline：分析原因（数据 / 超参 / pipeline bug）
7. **导出 + 分发**：onnx → mlpackage → mlmodelc → 打包到 app
8. **iOS/Mac TestFlight 验证**：实机跑 batch
9. **更新 CLAUDE.md 和 memory**：记录新 baseline + 决策依据

### Checkpoint 命名规范

```
data/weights/
├── best_model.pt              # 当前最强（自由对局）
├── best_renju.pt              # 当前最强（禁手）
├── archive/
│   ├── 2026-04-25_big_iter_1.pt
│   ├── 2026-04-25_big_iter_3.pt
│   └── ...
```

每次新模型成为 `best_*.pt` 时，把旧 baseline 移到 archive。

### 文档要求

每次训练 run 完成后写一篇 `docs/training_runs/YYYY-MM-DD_description.md`：
- 改动了什么
- 训练超参
- Loss 曲线
- Benchmark 结果（vs baseline + vs L4 minimax）
- 上线/不上线决定

---

## 优先级建议

**强烈推荐**：先做 P4.1-P4.3（禁手算法 + UI + 不重训兼容）。这能让用户立刻玩禁手模式，棋力虽然损失 5-10% 但仍然强。

**之后再做**：P4.4 重训。一晚的训练投入换来真正强的禁手 L6。

**长期**：标准化重训流程，让以后改进 model 不依赖临时操作。

---

## 风险与备选

1. **禁手算法 bug**：边缘 case（递归判活三）可能漏判 → 加强测试
2. **重训失败**：可能新模型不如 baseline → fallback 到不重训方案
3. **App 大小**：双模型 +8MB → 仍在合理范围
4. **iOS 编译时间**：双模型 mlmodelc 编译 +1-2 分钟 CI 时间，可接受

---

## 决策点（需要 hejia 决定）

1. **默认是否启用禁手**？
   - 方案 A：默认关闭（自由对局，易上手）
   - 方案 B：默认开启（专业五子棋玩家习惯）
   - 推荐：A
2. **L1-L4 是否实现禁手过滤**？
   - 是：游戏体验一致
   - 否：仅 L5/L6 知道禁手 → 不一致
   - 推荐：是
3. **训练优先级**：本周做 P4.1-P4.3，下周训模型？还是一次性做完？
4. **是否要做 swap2/swap5 开局**？（专业禁手对战的标准开局协议）
   - 推荐：先不做，单独项目
