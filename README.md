# 管理通知 Action

这个 GitHub Action 用于管理和限制通知的发送。它可以跟踪通知频率，防止过度通知，并维护一个包含通知历史的 GitHub Issue。

## 输入参数

| 参数                        | 描述                                 | 是否必需 | 默认值              |
| --------------------------- | ------------------------------------ | -------- | ------------------- |
| `github_token`              | GitHub token                         | 是       | -                   |
| `operation_result`          | 操作结果 (true 为成功, false 为失败) | 是       | -                   |
| `notification_interval`     | 两次通知之间的最小间隔时间（秒）     | 否       | 3600（1小时）       |
| `max_notifications_per_day` | 24 小时内最大通知次数                | 否       | 3                   |
| `issue_title`               | Issue 标题                           | 否       | `${{ github.job }}` |
| `issue_label`               | Issue 标签                           | 否       | ''                  |
| `keep_latest_only_message`  | 是否只保留最新的记录 (true/false)    | 否       | 'true'              |
| `debug_mode`                | 是否启用调试模式 (true/false)        | 否       | 'false'             |

## 输出

| 输出                     | 描述                             |
| ------------------------ | -------------------------------- |
| `should_notify`          | 是否应该发送通知                 |
| `error_message`          | 如果发生错误，这里会包含错误信息 |
| `notification_count`     | 24 小时内的通知数                |
| `last_notification_time` | 最后一次通知的时间               |

## 使用示例

```yaml
name: 管理通知示例

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  manage-notifications:
    runs-on: ubuntu-latest
    steps:
    - name: 管理通知
      id: manage_notifications
      uses: candies404/manage-notifications@latest
      with:
        github_token: ${{ secrets.GITHUB_TOKEN }}
        operation_result: 'true'
        notification_interval: '3600'
        max_notifications_per_day: '3'
        issue_title: '通知管理'
        issue_label: '通知'
        debug_mode: 'false'

    - name: 检查通知结果
      run: |
        if [[ "${{ steps.manage_notifications.outputs.should_notify }}" == "true" ]]; then
          echo "应该发送通知"
          # 在这里添加发送通知的逻辑
        else
          echo "不应该发送通知"
        fi
        echo "通知计数: ${{ steps.manage_notifications.outputs.notification_count }}"
        echo "上次通知时间: ${{ steps.manage_notifications.outputs.last_notification_time }}"
```

## 为什么需要 GitHub Token

这个 Action 需要 GitHub Token 的原因如下：

1. **创建和编辑 Issues**: Action 需要权限来创建新的 Issue（如果不存在）和编辑现有的 Issue 来记录通知历史。

2. **读取仓库信息**: 为了检查现有的 Issues 和标签，Action 需要读取仓库的权限。

3. **创建标签**: 如果指定的标签不存在，Action 需要权限来创建新的标签。

4. **API 访问**: GitHub CLI (`gh`) 命令需要 token 来进行身份验证，以执行各种 GitHub API 操作。

5. **安全性**: 使用 token 可以确保 Action 只有必要的权限来执行其任务，而不是完全访问仓库的所有内容。

通过要求提供 `github_token`，这个 Action 可以安全地执行其功能，同时遵守 GitHub 的最佳实践和权限模型。在大多数情况下，可以使用 `${{ secrets.GITHUB_TOKEN }}`，它是 GitHub Actions 自动提供的有限权限 token。

## 注意事项

- 确保您的仓库设置允许 GitHub Actions 创建和编辑 Issues。
- 如果您需要更高的权限（例如，在私有仓库中操作），可能需要提供具有更多权限的自定义 GitHub token。
- 调试模式会输出更多的日志信息，可以帮助排查问题。
- 请注意 `notification_interval` 和 `max_notifications_per_day` 的设置，以避免过度通知。
- 定期检查通知 Issue 的内容，确保它符合您的期望。
- 

## 贡献

我们欢迎并感谢任何形式的贡献！如果您想为这个项目做出贡献，请遵循以下步骤：

1. Fork 这个仓库
2. 创建您的特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交您的更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启一个 Pull Request

同时，如果您发现任何 bug 或有任何改进建议，请不要犹豫，立即开一个 issue。

## 许可证

该项目采用 MIT 许可证。查看 [LICENSE](./LICENSE) 文件以获得更多详细信息。
