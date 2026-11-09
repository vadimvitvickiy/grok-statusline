#!/bin/bash
# Grok status line, laid out like the Claude Code one.
# Line 1: model, effort, context window, branch, worktree.
# Line 2: folder, session age, the turn in flight, prompt-cache hit rate.
# Line 3: session cost, once a price is known.
# Grok sends no plan limits, editor mode, fast-mode flag, or counts of lines the agent changed.
# The palette follows the macOS appearance. GROK_STATUSLINE_THEME=light or dark overrides it.

readonly RESET=$'\033[0m' BOLD=$'\033[1m'
theme=${GROK_STATUSLINE_THEME:-}
if [[ -z $theme ]]; then
  if [[ $(defaults read -g AppleInterfaceStyle 2>/dev/null) == Dark ]]; then
    theme=dark
  else
    theme=light
  fi
fi
if [[ $theme == dark ]]; then
  readonly BLUE="147;197;253" VIOLET="196;181;253" GREEN="74;222;128" ORANGE="253;186;116" RED="248;113;113"
  readonly CYAN="103;232;249" AMBER="252;211;77" FUCHSIA="240;171;252" TEAL="94;234;212"
else
  readonly BLUE="30;64;175" VIOLET="91;33;182" GREEN="22;101;52" ORANGE="154;52;18" RED="153;27;27"
  readonly CYAN="21;94;117" AMBER="146;64;14" FUCHSIA="134;25;143" TEAL="17;94;89"
fi
# Usage turns orange at 50% and red at 80%, the same cutoffs as the Claude status line.
readonly WARNING_PERCENT=50
readonly ALERT_PERCENT=80
readonly SEPARATOR="  ·  "

# Unreadable input renders no status line rather than a broken one.
fields=$(jq -r 2>/dev/null '
  def whole: if . == null then "" else round end;
  # cache_read over every input token billed this session. Absent until the first call.
  def cache_hit:
    .context_window.session_usage as $u
    | if $u == null then ""
      else
        (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0)) as $total
        | if $total == 0 then ""
          else (($u.cache_read_input_tokens // 0) * 100 / $total | round)
          end
      end;
  def turn_seconds:
    if .turn.started_at_ms == null then ""
    else [((now * 1000 | floor) - .turn.started_at_ms) / 1000 | floor, 0] | max
    end;
  @sh "model=\(.model.display_name // .model.id // "")
    effort=\(.effort.level // "")
    current_dir=\(.workspace.current_dir // .cwd // "")
    repo_root=\(.workspace.repo_root // "")
    branch_name=\(.workspace.branch // "")
    worktree=\(.worktree.name // .workspace.git_worktree // "")
    duration_ms=\(.cost.total_duration_ms | whole)
    turn_seconds=\(turn_seconds)
    context_used=\(.context_window.used_percentage | whole)
    context_tokens=\(.context_window.context_tokens | whole)
    context_size=\(.context_window.context_window_size // 0)
    cache_hit=\(cache_hit)
    cost_usd=\(if .cost.total_cost_usd == null then "" else .cost.total_cost_usd end)"
') || exit 0
eval "$fields"

title() {
  printf %s "${BOLD}$1${RESET}"
}

paint() {
  printf %s $'\033[1;38;2;'"$1m$2${RESET}"
}

usage_color() {
  local percent=$1
  if ((percent >= ALERT_PERCENT)); then
    printf %s "$RED"
  elif ((percent >= WARNING_PERCENT)); then
    printf %s "$ORANGE"
  else
    printf %s "$GREEN"
  fi
}

# 1d 18h, 4h 8m, 55m, or 12s below a minute.
format_duration() {
  local seconds=$1
  if ((seconds >= 86400)); then
    printf '%dd %dh' $((seconds / 86400)) $((seconds % 86400 / 3600))
  elif ((seconds >= 3600)); then
    printf '%dh %dm' $((seconds / 3600)) $((seconds % 3600 / 60))
  elif ((seconds >= 60)); then
    printf '%dm' $((seconds / 60))
  else
    printf '%ds' "$seconds"
  fi
}

format_tokens() {
  local tokens=$1
  if ((tokens >= 1000000)); then
    local tenths=$((tokens % 1000000 / 100000))
    if ((tenths == 0)); then
      printf '%dM' $((tokens / 1000000))
    else
      printf '%d.%dM' $((tokens / 1000000)) "$tenths"
    fi
  elif ((tokens >= 1000)); then
    printf '%dk' $((tokens / 1000))
  else
    printf '%d' "$tokens"
  fi
}

join_segments() {
  local line="" segment
  for segment in "$@"; do
    [[ -z $segment ]] && continue
    line+="${line:+$SEPARATOR}${segment}"
  done
  if [[ -n $line ]]; then
    printf '%s\n' "$line"
  fi
}

usage_segment() {
  local label=$1 used=$2
  local left=$((used >= 100 ? 0 : 100 - used))
  printf %s "$(title "$label") $(paint "$(usage_color "$used")" "${used}% used / ${left}% left")"
}

model_segment() {
  [[ -z $model ]] && return
  local name=${model/ (1M context)/}
  if ((context_size >= 1000000)) && [[ $name != *1M* ]]; then
    name+=" 1M"
  fi
  printf %s "$(title MODEL) $(paint "$BLUE" "$name")"
}

effort_segment() {
  [[ -n $effort ]] && printf %s "$(title EFFORT) $(paint "$VIOLET" "$effort")"
}

context_segment() {
  if [[ -z $context_used ]]; then
    printf %s "$(title CONTEXT) waiting for first response"
    return
  fi
  local text
  text=$(usage_segment CONTEXT "$context_used")
  # An omitted count is unknown. 0 is an empty window, and the session_* totals are not a share of it.
  if [[ -n $context_tokens ]] && ((context_size > 0)); then
    text+=" ($(format_tokens "$context_tokens") of $(format_tokens "$context_size"))"
  fi
  printf %s "$text"
}

folder_segment() {
  [[ -z $current_dir ]] && return
  printf %s "$(title FOLDER) $(paint "$AMBER" "${current_dir##*/}")"
}

# workspace.branch is omitted on a detached HEAD, so the short hash comes from git.
branch_segment() {
  local name=$branch_name
  if [[ -z $name && -n $repo_root ]]; then
    name=$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null) || name=
  fi
  [[ -n $name ]] && printf %s "$(title BRANCH) $(paint "$FUCHSIA" "$name")"
}

session_segment() {
  [[ -z $duration_ms ]] && return
  printf %s "$(title SESSION) $(paint "$CYAN" "$(format_duration $((duration_ms / 1000)))")"
}

turn_segment() {
  [[ -z $turn_seconds ]] && return
  printf %s "$(title TURN) $(paint "$CYAN" "$(format_duration "$turn_seconds")")"
}

cache_segment() {
  [[ -z $cache_hit ]] && return
  printf %s "$(title CACHE) $(paint "$TEAL" "${cache_hit}% hit")"
}

# A cost under half a cent rounds to $0.00, which the built-in row also hides.
cost_segment() {
  [[ -z $cost_usd ]] && return
  local text
  text=$(LC_ALL=C awk -v n="$cost_usd" 'BEGIN {
    cents = int(n * 100 + 0.5)
    if (cents < 1) exit 1
    printf "$%d.%02d", int(cents / 100), cents % 100
  }') || return
  printf %s "$(title COST) $(paint "$AMBER" "$text")"
}

join_segments \
  "$(model_segment)" \
  "$(effort_segment)" \
  "$(context_segment)" \
  "$(branch_segment)" \
  "${worktree:+$(title WORKTREE) $(paint "$FUCHSIA" "$worktree")}"

join_segments \
  "$(folder_segment)" \
  "$(session_segment)" \
  "$(turn_segment)" \
  "$(cache_segment)"

join_segments \
  "$(cost_segment)"
