#!/bin/bash
# 上游同步体检。**判断为什么该拿或不该拿，而不是只列出差了几个提交。**
#
# 为什么要脚本而不是每次肉眼看：
#   一、`git rev-list --count` 按 SHA 算，而我们是 cherry-pick 进来的（内容同、SHA 不同）。
#       用它算过一次"落后 20 个提交"，差点白做一场 74 个冲突的合并 ——
#       实际六条修复早就在树里。必须用 `git cherry` 判等价补丁。
#   二、上游的 AI 能力绑在**上游后端**上（KieAI 模型目录、Convex 订阅），
#       而我们换掉了后端。硬 cherry-pick 会得到一个找不到模型的死按钮 ——
#       正是这个仓库里修过八次的"建好了但走不到"。
#   三、遥测类与我们对外的隐私承诺（prompt 24 小时抹除）冲突，是立场问题不是技术问题。
#   四、【该拿】只是**按前缀猜的**：`[fix]` / `[perf]` 就进那一栏，没人验证过它能落地。
#       5ddc2fa 号称改 7 个文件 73 行，实际因为坐在我们没拿的 #506 之上，
#       三方合并拖出两百行无关代码 —— 它当时就在【该拿】里。
#       **这一栏是候选，不是结论**：每一条 cherry-pick 之后必须看冲突规模、
#       必须 swift build、必须跑相关单测，再决定是拿补丁还是按我们的形状重写。
set -euo pipefail
cd "$(dirname "$0")/.."
git fetch --quiet upstream

echo "=== 内容上真缺的（git cherry 判等价补丁，不看 SHA）==="
missing=$(git cherry -v master upstream/main | grep '^+' || true)
[ -z "$missing" ] && { echo "  没有。已同步。"; exit 0; }

# 已经做过的判断记在这里，避免每次重新纠结同一件事。
# 格式：<7 位 sha>|<归类>|<理由>
DECIDED="
0eac952|blocked|靠 allModels.first{id contains \"lipsync\"} 找模型，我们的目录来自自家网关，没有这一档
eac669e|blocked|同上，靠 id contains \"reframe\"；拿过来是个找不到模型的死按钮
624ffee|blocked|走 Convex 订阅 generations:projectActivity，我们换掉了后端
452b2fe|refused|本地化重构，我们有自己的 L10n；合它会带来 74 个冲突且收益为零
98de811|refused|同上，是本地化那一摞的落地提交，不是普通修复
432e60e|review|我们已有 9:16 等预设，缺的只是自定义画幅 —— 锦上添花
8d5648d|refused|已按我们的需要拿过（941bfe4c），删掉了上游的 --telemetry 开关，所以补丁内容不同
c1061bd|refused|外观设置动 69 个文件 1421 行，是主题系统；冲突大、对我们收益小
bee6314|refused|供应商 logo 是给上游 KieAI 那批供应商的，我们的模型菜单显示自家档位
674b5e8|refused|上游的贡献指南，与我们的仓库无关
94394bb|taken|已拿（53559d3c）并按我们的产品改过；squash 后 git cherry 认不出
a2cf030|blocked|只有一行，但它依赖 TrackSize.defaultHeight —— 那个符号来自我们没拿的提交，编译不过；而"高一点"的分数常量在我们树上没有消费方
287ce76|blocked|依赖 themeForegroundColor，来自我们拒过的外观系统 c1061bd；且工具描述里写着"额度够就用云端转写"，与我们一律端侧免费的立场冲突
896d0b6|taken|已拿（a4b9b33e）：媒体搜索显示匹配的时间线；冲突只来自上游 L10n，按我们的写法解掉了
1d76782|review|字幕间隙合并是真瑕疵，但 8 处冲突且捎带改 ToolDefinitions；两位用户说产品太复杂，字幕微调排在接住首页那句话之后
c2b52be|refused|Agent 侧边栏周边装修，而我们的 agent 面板已分叉（砍掉 Convex/Clerk）
6aafb86|refused|重设计选中素材检查器，9 文件 430 行；方向是往检查器继续加界面，与"太复杂"的反馈相反
b36e5ab|blocked|Edit→Reframe 改用 MiniMax H3，绑上游模型目录；我们换了后端，拿来是死按钮（同 eac669e）
9d06340|review|三栈布局是 agent 工具契约，模型提示词在网关侧；不同步更新就是模型永远不会调用的死工具
ed60fe0|review|MetagAgentClient 已经收 SSE，但网关不发思考增量；先做网关，UI 才有意义
8c0ae39|refused|上游 README 星标图，与我们的仓库无关
ef6b51d|refused|已按我们的需要拿过（cd38b500），去掉了同一 hunk 里属于 #457 遥测的那一半
94394bb|review|引导式上手流程，产品取舍；注意它常与 analytics 打包
ed60fe0|review|流式思考过程，需要我们的网关支持流式返回才有意义
255dfc5|refused|试过：8 处冲突。工具描述里写着"额度够就用云端转写"，而我们是一律端侧且免费——那是立场差异，合进去等于在 LLM 读的描述里写一个我们没有的行为。有价值的只有 trackIndex 一小块，按我们的方式重写比拆冲突便宜
5ba45f4|review|clip link 管理工具，先看我们的 agent 操作集需不需要
8ba926a|taken|已拿（bc1ddb87）：scrub 音频解码移出协作线程池
ffc3e2d|taken|已拿（bc1ddb87）：时间线访问冲突，先改本地副本再提交
521106e|taken|已拿（bc1ddb87）：scrub reader 取消竞态
168b1e6|taken|已拿（bc1ddb87）：时间线符号快照崩溃
123d3aa|taken|已拿（15244fc2）：删掉音频表盘的无障碍轮询；冲突只来自上游 L10n
c88aae3|taken|已拿（04259df3）：转写取消不再被吞成失败，干净落地
426fbce|taken|已拿（31686f2b）：静音音轨不再插进合成。我们这边原本靠混音把音量设成 0 —— 声音是对的，但素材照样解码，导出白烧时间。变异验证：撤掉那一行，mutedAudioTrackIsExcludedFromComposition 当场红
0e6aca4|taken|已拿（b8880152）：合成时复用源素材。上游测试用了 FixtureVideo.write(fileType:)，我们的 fixture 没这个参数（写的是 mp4，与本测无关），去掉即可。变异验证：拿掉 sourceAssetsByURL 复用那一行，transientTrackFailureDoesNotPoisonURLAliases 从 1 次创建变成 2 次，红
5ba37cb|taken|已拿（6a505acb）：切项目窗口卡死。冲突只在 VideoProject 那一处 —— 上游删掉 showEditor，我们同一位置还有 generation log 的初始化，只删上游删的那行。**上游自带的 keyProjectWindowHidesHome 是空转的**：它直接调 projectWindowDidBecomeKey，把 VideoProject 里的接线改回 activateProject 它照样绿。补了 windowBecomingKeyThroughItsOwnDelegateHidesHome 从 makeWindowControllers 装出的 controller 触发真的 windowDidBecomeKey，变异验证过
4f7ecfa|taken|已拿（1f7bcb8b）：关掉 What's New 之后首页点不动 —— 不可见的 GeometryReader 把点击全吃了。我们树上是一模一样的形状。冲突只是底色（我们用 Color.black，上游换了主题色），保留我们的。**没有自动化判据，按仓库规矩交给人验**。试过两条路都不通：一，ChangelogStore.pending 是 private(set)，只在 checkForWhatsNew() 里从 bundle 读出来赋值，而测试进程的 Bundle.main 是测试运行器，取不到 CFBundleShortVersionString，那条路走不进去；二，改从引导层驱动（它和更新说明共用同一个 ZStack 和同一个 allowsHitTesting），把 HomeView 宿主进 NSHostingView 做 AppKit 命中测试 —— 进程当场 EXC_BREAKPOINT。AGENTS.md 本来就写着 UI 行为由人工验证、未经用户确认不许说通过。手工步骤：defaults write <bundleid> lastSeenVersion 0.1.7 → 启动当前版本 → 关掉 What'"'"'s New → 点首页任意一张工程卡片，必须有反应
b0be0a9|refused|只是把 clerk-ios 从 1.2.1 提到 1.3.9。我们砍掉了 Clerk，走自家网关的登录
258f633|review|mutation receipt 编码，动的是 agent 工具契约（ToolExecutor+Timeline / MutationDelta），我们那部分已分叉；等 agent 工具集稳定再看
5ddc2fa|taken|已按我们的形状重写（55929f3b）：最后一条字幕按住不闪。别再 cherry-pick 它 —— 它坐在 #506（逐条字符上限）和一次重叠消解重写之上，三方合并会把两百行无关的字幕机器连同上游 L10n 一起拖进四个文件；只取时间计算那一小块
"

take=(); blocked=(); refused=(); review=(); gone=(); taken_already=()
while read -r _ sha msg; do
  short="${sha:0:7}"
  # 先看有没有做过判断
  decided=$(echo "$DECIDED" | grep "^$short|" || true)
  if [ -n "$decided" ]; then
    kind=$(echo "$decided" | cut -d'|' -f2)
    why=$(echo "$decided" | cut -d'|' -f3)
    case "$kind" in
      blocked) blocked+=("$short  $msg  —— $why") ;;
      taken)   taken_already+=("$short  $msg  —— $why") ;;
      refused) refused+=("$short  $msg  —— $why") ;;
      *)       review+=("$short  $msg  —— $why") ;;
    esac
    continue
  fi
  files=$(git show --format="" --name-only "$sha" | tr '\n' ' ')

  # **落点还在不在。** 一个补丁不依赖上游后端，不等于它能落到我们树上 ——
  # 我们替换掉的模块（agent 客户端、本地化、模型目录）里的文件根本不存在，
  # 补丁打不上去。原来只判断"依不依赖后端"，于是 e0df4c3（改 OpenAIProvider.swift）
  # 被归进【该拿】，而我们压根没有那个文件。
  #
  # 只看**源码**文件：测试文件是新增的，本来就不存在，不能作为判据。
  # **变量名不要和外层的 $missing 撞。** 第一版就叫 missing，
  # 把外层那份（git cherry 的全部结果）覆盖成了单个文件名，
  # 于是"合计缺 37 条"静默变成"合计缺 1 条"，而列表照常打印 37 行 ——
  # 报告自相矛盾却不报错，是最难发现的那种坏。
  absent=""
  for f in $files; do
    case "$f" in
      Sources/*) [ -e "$f" ] || absent="$absent $f" ;;
    esac
  done
  if [ -n "$absent" ]; then
    gone+=("$short  $msg  —— 落点不存在：$(echo $absent | cut -c1-70)")
    continue
  fi

  # **文件在，不等于补丁能落地。** a2cf030 只改一个我们有的文件，却依赖
  # TrackSize.defaultHeight —— 那个符号来自我们没拿的提交，拿了编译不过。
  # 符号级检查做起来不便宜（要解析 Swift），所以这里只记教训：
  # 【该拿】里的每一条，cherry-pick 之后必须 swift build 才算数。
  case "$msg" in
    *"[fix]"*|*"[perf]"*|*"[fix/"*)   take+=("$short  $msg") ;;
    *telemetry*|*analytics*|*Telemetry*)
        refused+=("$short  $msg  —— 与 prompt 24 小时抹除的承诺冲突") ;;
    *changelog*|*"Bump to"*|*appcast*)
        refused+=("$short  $msg  —— 上游的发版元数据，我们走自己的版本线") ;;
    *)
      # 依赖上游后端的，拿过来就是死按钮
      if echo "$files" | grep -qE "GenerationBackend|Submission/|ModelCatalog" \
         && git show "$sha" | grep -qE '^\+.*(convex|allModels\.first|caps\.)' ; then
        blocked+=("$short  $msg  —— 绑在上游后端/模型目录上，我们换过后端")
      else
        review+=("$short  $msg")
      fi ;;
  esac
done <<< "$missing"

show() { [ ${#2} -eq 0 ] && return 0; echo; echo "$1"; printf '  %s\n' "${@:2}"; }
show "【该拿】修复与性能，与后端无关：" "${take[@]:-}"
printf '\n【落点不存在】我们替换掉了那部分，补丁打不上去：\n'
printf '  %s\n' "${gone[@]:-（无）}"
show "【拿不了】依赖上游后端，硬拿会得到死按钮：" "${blocked[@]:-}"
show "【不拿】立场或版本线问题：" "${refused[@]:-}"
show "【要人判断】产品取舍：" "${review[@]:-}"
# 已拿过的：squash 提交后 patch-id 对不上，不记录就会每次重复建议
show "【已拿】内容已在树上（提交被合并过，git cherry 认不出）：" "${taken_already[@]:-}"
echo
echo "  合计缺 $(echo "$missing" | wc -l | tr -d ' ') 条；【该拿】$( [ -n "${take[*]:-}" ] && echo ${#take[@]} || echo 0 ) 条需要处理。"
