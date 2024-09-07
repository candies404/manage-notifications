#!/bin/bash

# 调试信息和错误处理函数
debug_and_error_handling() {
    set -ex
    echo "开始执行脚本..."
    echo "Bash 版本: $BASH_VERSION"
    echo "操作系统信息:"
    uname -a
    echo "当前工作目录:"
    pwd
    echo "环境变量:"
    env | grep '^INPUT_' | sort
}
# 格式化时间
format_time() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(( (seconds % 3600) / 60 ))
    local remaining_seconds=$((seconds % 60))
    
    if [ $hours -gt 0 ]; then
        echo "${hours}小时${minutes}分${remaining_seconds}秒"
    elif [ $minutes -gt 0 ]; then
        echo "${minutes}分${remaining_seconds}秒"
    else
        echo "${remaining_seconds}秒"
    fi
}

# 错误报告函数
report_error() {
    echo "错误: $1" >&2
    echo "error_message=$1" >> $GITHUB_OUTPUT
    exit 1
}

# 检查 DEBUG_MODE 环境变量
if [ "${INPUT_DEBUG_MODE:-false}" = "true" ]; then
    debug_and_error_handling
fi

# 输入验证
[ -z "$INPUT_GITHUB_TOKEN" ] && report_error "GitHub token 未提供"
[ -z "$INPUT_OPERATION_RESULT" ] && report_error "操作结果未提供"

# 1. 变量定义和环境设置
REPO_OWNER=$(echo "$GITHUB_REPOSITORY" | cut -d '/' -f 1)
REPO_NAME=$(echo "$GITHUB_REPOSITORY" | cut -d '/' -f 2)
ISSUE_TITLE="${INPUT_ISSUE_TITLE:-${GITHUB_JOB}}"
MAX_NOTIFICATIONS="${INPUT_MAX_NOTIFICATIONS_PER_DAY:-3}"
NOTIFICATION_INTERVAL="${INPUT_NOTIFICATION_INTERVAL:-3600}"
ISSUE_LABEL="${INPUT_ISSUE_LABEL}"
KEEP_LATEST_ONLY_MESSAGE="${INPUT_KEEP_LATEST_ONLY_MESSAGE:-true}"
current_time=$(date +%s)
formatted_current_time=$(date "+%Y-%m-%d %H:%M:%S")

echo "环境变量设置完成:"
echo "REPO_OWNER: $REPO_OWNER"
echo "REPO_NAME: $REPO_NAME"
echo "ISSUE_TITLE: $ISSUE_TITLE"
echo "MAX_NOTIFICATIONS: $MAX_NOTIFICATIONS"
echo "NOTIFICATION_INTERVAL: $NOTIFICATION_INTERVAL"
echo "ISSUE_LABEL: $ISSUE_LABEL"
echo "KEEP_LATEST_ONLY_MESSAGE: $KEEP_LATEST_ONLY_MESSAGE"
echo "当前时间: $formatted_current_time"

# 2. 获取并验证基本设置
command -v gh &> /dev/null || report_error "GitHub CLI (gh) 未安装或不在 PATH 中"
echo "GitHub CLI 检查通过"

# 使用 GitHub Token
echo "$INPUT_GITHUB_TOKEN" | gh auth login --with-token

# 3. 检查并创建 Issue 标签
if [ ! -z "$INPUT_ISSUE_LABEL" ]; then
  if ! gh label list --repo "$REPO_OWNER/$REPO_NAME" | grep -q "$INPUT_ISSUE_LABEL"; then
    echo "创建标签: $INPUT_ISSUE_LABEL"
    if ! gh label create "$INPUT_ISSUE_LABEL" -R "$REPO_OWNER/$REPO_NAME" -c "#0366d6" -d "Used for tracking notifications"; then
      report_error "标签创建失败"
    fi
  fi
  echo "标签检查/创建完成"
fi

# 4. 查找或创建 Issue
echo "查找 Issue..."
ISSUE_QUERY="repo:$REPO_OWNER/$REPO_NAME is:issue is:open \"$ISSUE_TITLE\""
[ ! -z "$INPUT_ISSUE_LABEL" ] && ISSUE_QUERY+=" label:\"$INPUT_ISSUE_LABEL\""
issue_number=$(gh issue list --search "$ISSUE_QUERY" --limit 1 --json number --jq '.[0].number')

if [ -z "$issue_number" ]; then
  echo "未找到匹配的 Issue，创建新 Issue..."
  create_command="gh issue create --repo $REPO_OWNER/$REPO_NAME --title \"$ISSUE_TITLE\" --body \"${GITHUB_JOB}\""
  [ ! -z "$INPUT_ISSUE_LABEL" ] && create_command+=" --label \"$INPUT_ISSUE_LABEL\""
  if ! issue_number=$(eval "$create_command" | awk '{print $NF}'); then
    report_error "Issue 创建失败"
  fi
  echo "新 Issue 创建成功，编号: $issue_number"
  content=""
else
  echo "找到现有 Issue，编号: $issue_number"
  # 5. 解析 Issue 内容
  echo "获取 Issue 内容..."
  if ! content=$(gh issue view "$issue_number" --repo "$REPO_OWNER/$REPO_NAME" --json body --jq '.body'); then
    if ! content=$(gh api "repos/$REPO_OWNER/$REPO_NAME/issues/$issue_number" --jq '.body'); then
      report_error "获取 issue 内容失败"
    fi
  fi
  echo "Issue 内容获取成功"
fi

# 6. 处理通知时间记录
echo "处理通知时间记录..."
IFS=$'\n' read -d '' -r -a notifications <<< "$content"

count=0
last_notification_time=0
for notification in "${notifications[@]}"; do
  echo "处理通知: $notification"
  if [[ $notification =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
    timestamp=$(date -d "${BASH_REMATCH[1]}" +%s)
    if (( current_time - timestamp < 86400 )); then
      count=$((count + 1))
      (( timestamp > last_notification_time )) && last_notification_time=$timestamp
    fi
  fi
done
echo "24小时内的通知数: $count"
if [ $last_notification_time -ne 0 ]; then
  echo "最后通知时间: $(date -d @$last_notification_time "+%Y-%m-%d %H:%M:%S")"
else
  echo "没有找到有效的通知记录"
fi

# 7. 决定是否发送新通知
echo "决定是否发送新通知..."
should_notify=false
reasons=()

if [ $count -ge $MAX_NOTIFICATIONS ]; then
    reasons+=("24小时内的通知数($count)已达到 ($MAX_NOTIFICATIONS) 条")
fi

time_since_last=$((current_time - last_notification_time))
if [ $time_since_last -lt $NOTIFICATION_INTERVAL ]; then
    formatted_time_since_last=$(format_time $time_since_last)
    formatted_interval=$(format_time $NOTIFICATION_INTERVAL)
    reasons+=("距离上次通知的时间(${formatted_time_since_last})小于设定的通知间隔(${formatted_interval})")
fi

if [ ${#reasons[@]} -eq 0 ]; then
    should_notify=true
    echo "允许发送新通知"
else
    echo "不满足发送新通知的条件:"
    for reason in "${reasons[@]}"; do
        echo "- $reason"
    done
fi

# 8. 更新 Issue 记录
echo "更新 Issue 记录..."
status=$([ "$INPUT_OPERATION_RESULT" = "true" ] && echo "允许发送通知" || echo "禁止发送通知")

new_entry="${formatted_current_time} - $status"
temp_notifications=("${notifications[@]}" "$new_entry")
IFS=$'\n' sorted_notifications=($(sort <<< "${temp_notifications[*]}"))
[ "${#sorted_notifications[@]}" -gt "$MAX_NOTIFICATIONS" ] && sorted_notifications=("${sorted_notifications[@]:$((${#sorted_notifications[@]} - MAX_NOTIFICATIONS))}")
new_content=$(printf "%s\n" "${sorted_notifications[@]}" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')

echo "更新 Issue 内容..."
if ! echo "$new_content" | gh issue edit "$issue_number" --repo "$REPO_OWNER/$REPO_NAME" --body-file -; then
  report_error "更新 issue 内容失败"
fi
echo "Issue 更新成功"

# 9. 设置输出变量
echo "should_notify=$should_notify" >> $GITHUB_OUTPUT
echo "notification_count=$count" >> $GITHUB_OUTPUT
echo "last_notification_time=$(date -d @$last_notification_time '+%Y-%m-%d %H:%M:%S')" >> $GITHUB_OUTPUT
echo "脚本执行完成"
