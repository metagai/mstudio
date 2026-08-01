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
"

take=(); blocked=(); refused=(); review=()
while read -r _ sha msg; do
  short="${sha:0:7}"
  # 先看有没有做过判断
  decided=$(echo "$DECIDED" | grep "^$short|" || true)
  if [ -n "$decided" ]; then
    kind=$(echo "$decided" | cut -d'|' -f2)
    why=$(echo "$decided" | cut -d'|' -f3)
    case "$kind" in
      blocked) blocked+=("$short  $msg  —— $why") ;;
      refused) refused+=("$short  $msg  —— $why") ;;
      *)       review+=("$short  $msg  —— $why") ;;
    esac
    continue
  fi
  files=$(git show --format="" --name-only "$sha" | tr '\n' ' ')
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
show "【拿不了】依赖上游后端，硬拿会得到死按钮：" "${blocked[@]:-}"
show "【不拿】立场或版本线问题：" "${refused[@]:-}"
show "【要人判断】产品取舍：" "${review[@]:-}"
echo
echo "  合计缺 $(echo "$missing" | wc -l | tr -d ' ') 条；【该拿】$( [ -n "${take[*]:-}" ] && echo ${#take[@]} || echo 0 ) 条需要处理。"
