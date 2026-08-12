# 上游巡检 2026-08-12（upstream/main @ 2efac7d）

只读巡检，没有 cherry-pick、没有合并、没有动产品代码。工作区里 Bundle ID / Sparkle 那三处未提交改动原样保留。

判据来源：`scripts/upstream-sync.sh`（`git cherry` 判等价补丁）+ 每一条自己看 diff。
本轮内容上真缺 **77 条**，脚本的【该拿】桶 **0 条**（因为它只认 `[fix]`/`[perf]` 前缀，本轮的修复挂在 `[ui/fix]` 和 `[agent]` 下面）。
下面 7 条是我建议动的，其余 70 条给了归类。

---

## 先说三件会改变你怎么读这份清单的事

### 一、`upstream-sync.sh` 的【落点不存在】桶有假阴性，本轮埋掉了一条真 bug 修复

脚本第 91-100 行只判断「这个 `Sources/*` 文件在不在我们树上」，**没区分补丁是修改它还是新增它**。
一个新增文件在我们树上当然不存在 —— 于是任何"带一个新文件"的提交都被判成"打不上去"。

本轮被这条误判扔掉的：`c017a17`（#495，Agent 流式 UI 卡死，**真修复**）、`03f4bba`、`2c5a5c8`、`750bed7`、`89c8731`、`36b47c5`、`a5c7d4f`。
其中 `c017a17` 是这一轮我最建议拿的一条。

正确的判据是看 `git show --name-status`：`M` 的文件缺 = 真落点不存在；`A` 的文件缺 = 正常。
真正落点不存在的只有：`8bb5de4` `5846d8a` `44971d2` `e0df4c3` `e014d62`（改 `Agent/Clients/PalmierClient.swift`、`OpenAIProvider.swift`、`Agent/Chat/AgentService.swift`、上游多语 `.lproj`——这些模块我们换掉了），以及 `f551e80` `05880e8` `2c5a5c8` 的**一部分**依赖（下面单列）。

**没改脚本**（本次边界是只读）。要修的话就是把 `git show --format="" --name-only` 换成 `--name-status`，只对 `M`/`R` 的缺失判定为落点不存在。

### 二、mac 端的 agent 系统提示词在**客户端**，不在网关

`AgentService.swift:375` 把 `AgentInstructions.serverInstructions` 和 `ToolDefinitions.inAppAgent` 的完整 schema 随每次请求发出去。
所以**工具契约和提示词的改动是自洽的，不需要先改网关**。
这一条推翻了之前记在脚本 `DECIDED` 里的 "模型提示词在网关侧"（那句对 9d06340 成立的部分是三栈布局需要模型侧配合，但对 `2efac7d`/`0fa1295`/`277ad3b` 这类不成立）。
证据：`Sources/PalmierPro/Agent/AgentService.swift:362-376`。

### 三、Bundle ID / Sparkle 的冲突风险：**本轮为零**

上游碰 `Info.plist` / `scripts/bundle.sh` / `entitlements` / `appcast.xml` 的提交只有两类：

- 版本号 bump 和 appcast（`8c98589` `69a77e9` `f4a776b` `c3a1257` `a6db84f` 和对应的 5 条 appcast）—— 我们走自己的版本线，本来就不拿；
- `452b2fe`（#431 本地化基座，改 `Package.swift` + `Info.plist` + `bundle.sh`）和 `8d5648d`（#440，改 `bundle.sh`）—— 两条都已经拒过。

下面 7 条建议拿的补丁，**没有一条碰这三个文件**。今天的 `ai.metag` → `ai.metag.mac` 改动可以放心提交。

### 附带结论：无障碍这一轮没有东西可拿

全量扫了 77 条里 `Sources/*` 的 `+` 行，命中 `accessibility|VoiceOver|reduceMotion|differentiateWithoutColor|contrastLevel` 的全部是**顺带加的 `accessibilityLabel`**，且集中在我们已拒的本地化栈（`98de811`，67 处）和外观系统（`c1061bd`）里。**上游本轮没有独立的无障碍修复。**

### 附带结论：`expr-allowlist.ts` 不在这个仓

它在 `studio/packages/core/src/expr-allowlist.ts`。mac 端没有表达式引擎，"动效"是 `TextAnimator` 的固定预设枚举，和白名单没有交集。
唯一沾边的是 `a373cc3`（#524）会删掉预设名 —— 见下，判为不拿。

---

## 我建议拿的（7 条，按优先级）

### 1. `c017a17` #495 — Agent 流式回复把主线程压死，且切会话会丢内容

**它做了什么（看 diff）**：把逐 token 直接改 `@MainActor @Observable` 的 `messages[i].blocks` 换成"离主 actor 合并快照、再整块 apply"（新增 `AgentStreamPresentationBuffer.swift`，212 行）；同时给 `applyStreamSnapshot` / `dropEmptyAssistantTurn` 加了 `conversationID`，让流式中途切会话时晚到的快照回到它原本那个会话。提交里还夹了一次目录搬迁（`Agent/*.swift` → `Agent/Chat/`）。

**结论：改造后拿（手抄，不 cherry-pick）**。置信度 **高**。

**理由**：我们树上就是修复前那一版，逐字同形 —— `AgentService.swift:382-398` 的 `for try await event in stream` 里每个 `.textDelta` 都调 `appendTextDelta`（465 行）直接改 `messages[index].blocks`。两个 bug 都在：
1. 长回复 = 每 token 一次 SwiftUI 全面板失效；
2. 我们的 `dropEmptyAssistantTurn(id:)` 和 `runPendingToolUses(assistantID:)` **完全没有 conversationID 参数**，`currentSessionId` 在 233/251/268 行会被切会话改掉 —— 流式过程中切会话，回复写进错的地方。

**为什么不 cherry-pick**：我们的 `AgentService.swift` 相对上游同一基线是 **113+/241-**；上游那版有 `openAIReasoning` / `reasoningSummaryDelta`（OpenAI provider，我们没有），补丁里有一半 hunk 是处理它们的。加上目录搬迁，三方合并只会制造噪音。**抄合并思路和 conversationID 参数，不抄文件。**

**冲突面**：`Sources/PalmierPro/Agent/AgentService.swift`（我们已重度分叉），新增一个 buffer 文件。不碰 UI、不碰打包。

**验证它真的生效的行为判据**（不是"编译过了"）：
- 让 agent 产出一段 8000+ token 的长回复，**在流式过程中**拖时间线播放头 + 滚动聊天列表 —— 必须不掉帧、不转菊花。
- 流式进行到一半切到另一个会话，等它结束再切回来 —— 回复必须**完整**落在原会话里，且没有半截的 tool_use 块。
- **变异验证**：把合并窗口调成 0（退化成每 delta apply 一次），上面第一条必须当场复现卡顿。做不到就说明测的不是这件事。

---

### 2. `b052c83` #506 的 `maxCharacters` 那一小块 — 中文字幕的行长上限

**它做了什么**：`CaptionBuilder.phrases` 的断句判据从 "视觉宽度 + maxWords" 变成 "视觉宽度 + maxWords + **maxCharacters**"，同时删掉了 `enforceMinDuration`，并把 `closingShortGaps` 整个重写成 `adjustedCaptionTiming`（先消重叠再补间隙）。

**结论：改造后拿 —— 只取 `maxCharacters` 那条判据**。置信度 **高**（对"该拿哪一小块"高；对"上游那台字幕机器"是明确不拿）。

**理由**：中文没有词边界，`maxWords` 对我们的用户等于不存在；**每行字符上限才是他们真正要的旋钮**。而同一提交里的 `adjustedCaptionTiming`/`resolveOverlap` 正是我们已经按自己形状重写过的那台机器 —— `CaptionSpecBuilder.swift` 相对上游基线已 **83+/80-**（`55929f3b` 那次），93 行还带着我们自己写的 wordCycle 延长注释。这就是脚本头部警告的 `5ddc2fa` 剧本，别再演一次。

要移植的具体范围：`CaptionBuilder.split` 的 `fits` 闭包加一条 `text.count <= cap`、`CaptionSpecBuilder.Input` 加 `maxCharacters`、`CaptionTab` 加一个输入框。**其余一律不动。**

**冲突面**：`CaptionBuilder.swift`（好消息：这个文件我们和上游基线**逐字节相同**）、`CaptionSpecBuilder.swift`（重度分叉，手改）、`CaptionTab.swift`（141+/209- 分叉，手改）。不碰打包。

**行为判据**：一段 60 秒中文口播，设 `maxCharacters=12` 生成字幕 → 每一条 clip 的文本长度都 ≤12、**一个字都没丢**（把所有 clip 文本拼起来必须等于转写全文）、相邻两条时间不重叠。**变异验证**：把上限改成 1000，必须立刻出现超长条。

---

### 3. `d3abe80` #512 — 轨道头右键"选中本轨全部片段"

**它做了什么**：`TimelineHeaderView` 加 `menu(for:)` + `hitTestTrack`，`EditorViewModel+Tracks` 加 9 行 `selectAllClips(onTrack:)`。共 47 行，3 个文件。

**结论：拿**。置信度 **高**。

**理由**：时间线交互，我们的用户天天在用；批量选中整轨是剪辑里的高频动作，现在只能框选。落地条件全部满足：我们有 `L10n`（`Utilities/Localization.swift`，65 处在用）、有 `TimelineGeometry.trackY/trackHeight`、有 `editor.selectedGap`（`TimelineInputController.swift:151`），而我们的 `TimelineHeaderView` **没有** `menu(for:)`（唯一的在 `TimelineView.swift:1001`，不同的 view），不会撞。

**冲突面**：`TimelineHeaderView.swift`（我们相对基线只差 8+/21-）、`EditorViewModel+Tracks.swift`（差 1+/1-）、`en.lproj/Localizable.strings` 一行 —— 需要顺手补中文串。不碰打包。

**行为判据**：在一条有 5 个 clip 的轨道头上右键 → 菜单出现 → 点击后那 5 个全部高亮 → 按 Delete，删掉的正好是这 5 个、别的轨道一个都没动。**空轨道上右键，该菜单项必须是灰的。**

---

### 4. `2efac7d` #533 里的四段行为约束 — agent 的提示词

**它做了什么**：重写系统提示词 93 行。里面混着两类东西：描述新工具的（`copy_clip_settings`、`rotationX/rotationY`、`style.blur`、`fillMode 'inverted'`）和纯行为约束的。

**结论：改造后拿（手抄四段，其余丢掉）**。置信度 **中高**。

**该抄的四段**：
1. **"不要空转轮询长任务"** —— 视频/图像/放大 fire and move on；音频快，查一两次就行。
2. **"永远不要承诺生成完了我再告诉你 —— 这一轮不会自己重启"**。这条价值最高：agent 现在真的在对用户撒这个谎，用户就干等着。
3. **trim/tighten 的做法** —— 先问一两个聚焦问题，然后剪彻底（不只是"嗯啊"，还有假开头、重复段、句间死空），**剪完回读转写确认还读得通**。
4. **"改画幅是 `set_project_settings`，不是 `apply_layout`"**，以及要保原比例就先 `create_timeline(from=)` 复制一份。

这四条我们全都有对应工具（`set_project_settings`、`create_timeline` 都在我们的 `ToolDefinitions` 里）。

**不该抄的**：任何提到 `copy_clip_settings` / `rotationX,rotationY` / `style.blur` / `fillMode 'inverted'` 的句子 —— 这四样能力我们没有（见下面 #515/#519/#529/#525 都判为缓）。**在系统提示词里描述一个不存在的工具，等于给模型装一个幻觉源。**

**冲突面**：只有 `AgentInstructions.swift` 一个文件，我们相对基线只差 5+/19-（差的正好就是上面那几样我们没有的能力）。零打包风险。

**行为判据**：
- 让 agent 发起一次视频生成 —— 它的回复里**不能**出现"生成好我通知你 / 我等着"这类承诺，必须给出 placeholder id 并说"好了叫我"。
- 说"把这条竖过来" —— 它必须调 `set_project_settings`，不能调 `apply_layout`。
- 说"帮我把这段口播剪紧" —— 它必须先读一次 `get_transcript`，剪完再读一次。

---

### 5. `0fa1295` #507 — 文本框永远按内容自适应

**它做了什么**：从 `add_texts` / `update_text` 的 `transform` schema 里删掉 `width` / `height`，只留 `centerX/centerY/rotation`；执行侧把 `shouldFitToContent` 从"没给 width/height 才 fit"改成"内容或影响排版的样式变了就 fit"，并把 fit 移到 transform 应用之前。

**结论：拿**。置信度 **中**。

**理由**：模型自己编 width/height 是"字被切掉 / 字被拉扁"的主要来源，删掉这个自由度就删掉了这一整类 bug。落地条件很好：**我们的 `ToolExecutor+Texts.swift` 与上游基线逐字节相同**；`ToolDefinitions.swift` 分叉 28+/52-，但差异都在我们删掉的那些工具处，这几个 hunk 大概率干净。

**注意配对**：`277ad3b` #509 是它的直接后续（`centerX/centerY` → 按对齐方式锚定的 `x/y`）。**我把 #509 判为缓**：它同时改了 `get_timeline` 的输出形状（transform 里 `centerX/width` 换成 `x/y`），我们只要有任何 skill 或用户提示词记着 `centerX`，就会**静默**错位 —— 静默错位比报错难查。只拿 #507 会停在一个自洽的中间态（center-only + auto-fit），可用。

**冲突面**：`ToolDefinitions.swift`、`ToolExecutor+Texts.swift`。不碰打包。

**行为判据**：让 agent 加一句 20 字中文标题，再让它把文案改成 40 字 —— 框必须跟着变长，**一个字都不能被截**，且中心位置不变。再让它明确要求 `width: 0.2` —— 必须被 schema 拒掉并报错，而不是默默接受。

---

### 6. `9a378df` #500 — 给 agent 一个"换素材"工具

**它做了什么**：新增 `swap_clip_media` 工具，并把原本散在 `EditorViewModel+ClipMutations` 里的换素材逻辑收敛进 `EditorViewModel+MediaSwap`（同一个域操作同时服务 UI 和 agent）。

**结论：拿**。置信度 **中**。

**理由**：落地条件几乎完美 —— `EditorViewModel+ClipMutations.swift` 与上游基线**无差异**，`EditorViewModel+MediaSwap.swift` 只差 1 行。而"这个镜头换成另一段"是我们用户会说的话，现在只能删了重加（会丢掉所有调过的参数）。

**冲突面**：`ToolDefinitions.swift`、`ToolExecutor+Clips.swift`、`EditorViewModel+MediaSwap.swift`、`TimelineView.swift`（3 行）。附带 119 行测试。不碰打包。

**行为判据**：一条调过变换 + 色彩 + 关键帧的 10 秒 clip，换成另一段素材 → 时长、入出点、变换、色彩、关键帧**全部保留**，只有画面换了；`Cmd-Z` 一次完整回到原素材（不是分成三步 undo）。

---

### 7. `2cccc6b` #521 — 失败的生成显示"这次没有扣费"

**它做了什么**：`BackendGenerationJob` 加一个 `refundedCredits: Int?`，透到 `MediaAsset.wasGenerationRefunded`，失败卡片上多一行绿字。共 14 行、4 个文件。

**结论：改造后拿 —— 但先去网关确认字段存在**。置信度 **中**（对代码本身高；对"我们的网关会不会返回这个字段"未知）。

**理由**：它**不是**绑 KieAI/Convex 那类死按钮 —— `refundedCredits` 是我们自己网关就能加的一个字段。而"生成失败还扣我钱"是最伤信任的一类投诉，这一行字就是答案。但如果网关不返回，它就是一段永远不显示的死代码 —— 这正是这个仓库修过八次的"建好了但走不到"。**先确认网关，再动客户端。**

**冲突面**：`GenerationBackend.swift`、`GenerationService.swift`、`MediaAsset.swift`、`PreviewContainerView.swift`，都是纯新增行，冲突面几乎为零。不碰打包。

**行为判据**：造一个必然失败的生成（比如给一个非法参数）→ 失败卡片上出现那句话；成功的卡片上**不能**出现。**变异验证**：把网关返回的 `refundedCredits` 改成 0，那句话必须消失。

---

## 明确不拿 / 缓的（本轮新判断）

| 补丁 | 结论 | 归类与理由 |
|---|---|---|
| `a373cc3` #524 删冗余动效预设 | **不拿** | 与我们的改动冲突 + 静默降级。它从 `Codable` 枚举里删 `fadeIn`/`wordPop`/`wordCycle`。我们的 `TextAnimation.init(from:)`（第 85 行）对未知值回落到 `.none` —— 老项目不会崩，会**静默变成没有动效**，比崩更难发现。而 wordCycle 的延长逻辑我们已在 `CaptionSpecBuilder.swift:93` 按自己形状写过。上游删的是他们自己的债。 |
| `277ad3b` #509 文本按对齐锚定 | **缓** | 改了 `get_timeline` 输出形状（`centerX/width` → `x/y`）。任何记着 `centerX` 的 skill 或用户提示词都会**静默**错位。真要拿就和 #507 一起、并同步检一遍 skill 库。 |
| `6a02f03` #526 面板/检查器装修 | **不拿** | 价值不足。纯外观，改 `AppTheme`/`Constants`，和 #523 抢同一批常量。 |
| `09351ee` #525 反色填充 | **缓** | 价值不足（非缺陷）。改 `FrameRenderer` + `TextFillMode`(Codable) + 工具 schema，是 #530 的地基。 |
| `8597ea7` #529 文字高斯模糊 | **缓** | 同上。新增 `TextStyle.blur`（Codable 新字段，向前不兼容旧版读新项目）。我们的 `FrameRenderer` 已落后 64 行。 |
| `d327c64` #530 文字颜色做蒙版 | **缓** | 同上，且**建在 #525 之上**。这三条要拿就一起拿，且要在 #519 之后。 |
| `36b47c5` #519 文字透视倾斜 | **缓** | 价值不足 vs 风险。566 行，改 `PreviewHitTester` / `TransformOverlayView` —— 那是我们预览区的交互热区，动了就要重测全部拖拽手势。 |
| `38a0851` #523 轨道头可拖宽 | **缓** | 价值不足 vs 风险。147 行改 `TimelineContainerView`，顺带改了 fit-all 缩放算式（`EditorViewModel+PreviewTabs`）和 hover 归属（删掉 `mouseExited` 里的 `NSCursor.arrow.set()`）。在没拿 #520 可编辑轨道名的前提下，加宽轨道头没有内容可放。 |
| `05880e8` #520 可编辑轨道名 | **缓（有依赖）** | 它 `M` 了 `ToolExecutor+AgentActivity.swift` —— 那是 #517 新增的文件，我们没有。**真·落点不存在**，要拿得先吞 #517 的 828 行。 |
| `89c8731` #517 时间线上显示 agent 活动 | **不拿** | 价值不足。828 行新界面层，方向与"产品太复杂"的用户反馈相反。 |
| `750bed7` #515 `copy_clip_settings` | **缓** | 507 行**纯新增、零冲突**（全是新文件），技术上最好拿。但它是给 agent 加第 48 个工具。先回答"我们的操作集需不需要"，别因为好拿就拿。 |
| `f551e80` #518 导入 SRT/WebVTT | **改造后拿的候选，本轮先别动** | 848 行 / 36 文件，其中三个我们没有（`ExportTimelineAnalyticsSnapshot` 是遥测、`UILocalization` 是上游 L10n、`EditorViewModel+ClipSettings` 来自 #515）。**真正值钱的只有 `SubtitleFileParser.swift`（143 行，纯解析、零依赖）**。哪天要做"用户拿自己的字幕稿"，抄那一个文件 + 一条导入路径，别碰其余 35 个。 |
| `03f4bba` #511 字幕预览叠在画面上 | **缓** | 447 行、重写 `CaptionTab`，而我们的 `CaptionTab` 已分叉 141+/209-。冲突面大。 |
| `2c5a5c8` #514 可编辑裁切画幅 | **缓** | 改 `Models/Timeline.swift` 且 `M` 了我们没有的 `UILocalization.swift`。和之前对 `432e60e` 的判断一致：我们已有 9:16 等预设，缺的只是自定义画幅，锦上添花。 |
| `a5c7d4f` #528 画布参考线 | **缓** | 411 行纯新增、零冲突。但给一个被评"太复杂"的产品再加一层叠加层，先不加。 |
| `af80556` #505 | **不拿** | 上游的 `AGENTS.md`，我们有自己的。 |
| `be32c99` #531 上手流程遥测 | **不拿** | 遥测。与 prompt 24 小时抹除的承诺冲突（立场问题）。 |
| `e014d62` #497 社区技能自动同步 | **不拿** | 落点不存在（`Agent/Chat/AgentService.swift`）+ 拉的是上游的社区技能仓库。 |

其余 40+ 条（版本 bump / appcast / changelog / 本地化栈 / 外观系统 / 上游 README 与贡献指南 / KieAI 模型目录相关 / 遥测）维持 `upstream-sync.sh` 里 `DECIDED` 的既有判断，本轮无新证据推翻。

---

## 总表（建议拿的排在最前）

| # | 补丁 | 做了什么 | 结论 | 理由 | 冲突面 | 置信度 |
|---|---|---|---|---|---|---|
| 1 | `c017a17` #495 | 流式回复离主 actor 合并快照；晚到快照按 conversationID 回原会话 | **改造后拿（手抄）** | 我们树上就是修复前那一版；长回复卡死 + 切会话丢内容两个真 bug | `AgentService.swift`（已重度分叉 113+/241-）+ 1 新文件。**不碰打包** | 高 |
| 2 | `b052c83` #506 的 `maxCharacters` | 断句加"每行字符上限"判据 | **改造后拿（只取这一小块）** | 中文没有词边界，`maxWords` 等于没有；同提交的字幕计时机器我们已重写过，别再合 | `CaptionBuilder`(与基线同)、`CaptionSpecBuilder`(83+/80-)、`CaptionTab`(141+/209-) | 高 |
| 3 | `d3abe80` #512 | 轨道头右键"选中本轨全部片段"，47 行 | **拿** | 时间线高频交互；落地条件全满足，我们的 header 没有 `menu(for:)` 不会撞 | `TimelineHeaderView`(8+/21-)、`+Tracks`(1+/1-)、一条 L10n 串（要补中文） | 高 |
| 4 | `2efac7d` #533 的四段 | 不空转轮询 / 不承诺"生成完通知你" / trim 要彻底并回读 / 改画幅用 `set_project_settings` | **改造后拿（手抄四段）** | 提示词在客户端，自洽可落；#2 那条是 agent 现在真在撒的谎 | 只有 `AgentInstructions.swift`(5+/19-)。**丢掉提到 `copy_clip_settings`/`rotationX,Y`/`style.blur`/`inverted` 的句子** | 中高 |
| 5 | `0fa1295` #507 | 文本框 schema 删掉 width/height，永远按内容自适应 | **拿** | 模型编 width/height 是"字被切/被拉扁"的主要来源；`ToolExecutor+Texts` 与基线逐字节相同 | `ToolDefinitions`(28+/52-)、`ToolExecutor+Texts`(无差异) | 中 |
| 6 | `9a378df` #500 | `swap_clip_media` 工具 + 换素材逻辑收敛到一个域操作 | **拿** | `+ClipMutations` 与基线无差异、`+MediaSwap` 只差 1 行；用户会说"这镜头换一段" | `ToolDefinitions`、`+Clips`、`+MediaSwap`、`TimelineView`(3 行) | 中 |
| 7 | `2cccc6b` #521 | 失败生成显示"这次没有扣费"，14 行 | **改造后拿（先确认网关字段）** | 不是死按钮类 —— `refundedCredits` 是我们自家网关能加的字段；不加就是永远不显示的死代码 | 4 个文件、全是新增行，冲突≈0 | 中（代码高，网关未知） |
| 8 | `a373cc3` #524 | 删 `fadeIn`/`wordPop`/`wordCycle` 三个动效预设 | **不拿** | 与我们的改动冲突 + 老项目**静默**变成无动效（decoder 回落 `.none`） | — | 高 |
| 9 | `277ad3b` #509 | transform `centerX/width` → 按对齐锚定的 `x/y` | **缓** | 改了 `get_timeline` 输出形状，记着 `centerX` 的地方会静默错位 | — | 中 |
| 10 | `6a02f03` #526 | 面板/检查器外观 | **不拿** | 价值不足；和 #523 抢同一批 `AppTheme` 常量 | — | 高 |
| 11 | `09351ee`/`8597ea7`/`d327c64` #525/#529/#530 | 反色填充 / 文字高斯模糊 / 文字色蒙版 | **缓（要拿就三条一起）** | 价值不足（非缺陷）；链式依赖；`FrameRenderer` 已落后 64 行 | — | 中 |
| 12 | `36b47c5` #519 | 文字透视倾斜，566 行 | **缓** | 动预览区交互热区（`PreviewHitTester`/`TransformOverlayView`），风险高收益低 | — | 中 |
| 13 | `38a0851` #523 | 轨道头可拖宽，147 行 | **缓** | 顺带改 fit-all 缩放算式和 hover 归属；没拿 #520 的话加宽也没内容可放 | — | 中 |
| 14 | `05880e8` #520 | 可编辑轨道名 | **缓（依赖 #517）** | 真·落点不存在：`M` 了 #517 新增的 `ToolExecutor+AgentActivity.swift` | — | 高 |
| 15 | `89c8731` #517 | 时间线上显示 agent 活动，828 行 | **不拿** | 价值不足；与"产品太复杂"的反馈反向 | — | 中 |
| 16 | `750bed7` #515 | `copy_clip_settings`，507 行纯新增 | **缓** | 技术上零冲突最好拿，但是第 48 个 agent 工具 —— 先回答需不需要 | — | 中 |
| 17 | `f551e80` #518 | 导入 SRT/WebVTT，848 行 36 文件 | **缓（只值 `SubtitleFileParser.swift` 那 143 行）** | 三个依赖文件我们没有（遥测/上游 L10n/#515）；真要做就抄那一个纯解析文件 | — | 中 |
| 18 | `03f4bba` #511 | 字幕预览叠在画面上，447 行 | **缓** | 重写 `CaptionTab`，而我们已分叉 141+/209- | — | 中 |
| 19 | `2c5a5c8` #514 | 可编辑裁切画幅 | **缓** | `M` 了我们没有的 `UILocalization.swift`；我们已有预设，缺的只是自定义 | — | 中 |
| 20 | `a5c7d4f` #528 | 画布参考线，411 行纯新增 | **缓** | 零冲突，但给"太复杂"的产品再加一层叠加层 | — | 中 |
| 21 | `af80556` #505 | 上游 AGENTS.md | **不拿** | 与我们的仓库无关 | — | 高 |
| 22 | `be32c99` #531 | 上手流程遥测 | **不拿** | 遥测（立场） | — | 高 |
| 23 | `e014d62` #497 | 社区技能自动同步 | **不拿** | 落点不存在 + 拉上游社区仓库 | — | 高 |

---

## 拿不准的，明说

- **#521 的网关字段**：我没有查网关代码（本次边界只在 `mac`）。它值不值得动，取决于我们的生成 job 返回里有没有退款信息。这是动手前的唯一一个前置问题。
- **#507 单独拿会不会留坑**：我判断中间态自洽（center-only + auto-fit），但没编译验证。`ToolExecutor+Texts.swift` 与基线逐字节相同这一点让我倾向于它会干净落地，**但 cherry-pick 之后必须 `swift build` + 跑 `ToolExecutorTests`/`MCPStaticRotationTests` 才算数**（脚本头部第 106-110 行那条教训）。
- **#500 的 UI 侧**：我只确认了域操作层与基线一致，没有追 UI 里换素材的入口在我们这边是不是也分叉过。
