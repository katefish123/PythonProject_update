# Git 提交身份与协作规范

本规范适用于 `PythonProject_update` 仓库及本项目所有分支（main、main-A、main-B、main-C、c-pipeline-next）。

## 1. 提交身份

- 所有提交的 **author 与 committer 统一为项目负责人个人账号**：

  ```text
  slowshine <3297694176@qq.com>
  ```

- 禁止使用工具或代理账号作为提交身份，包括但不限于 `Codex <codex@openai.com>`、`Copilot`、`cursor`、`noreply@anthropic.com` 等。
- 禁止在提交信息中添加指向 AI 工具或机器人账号的 `Co-authored-by:` 尾注。
- 使用辅助工具生成或修改代码时，提交前必须由提交人核对身份，工具不得自行 `git commit`。

## 2. 本机配置

每台参与本项目的机器执行一次：

```bash
git config --global user.name  "slowshine"
git config --global user.email "3297694176@qq.com"
```

并在仓库内确认没有覆盖项：

```bash
git config --local --list | grep -E '^user\.'
```

`git push` 的认证走系统凭据管理器；不要把密码、访问令牌写进仓库、文档、提交信息或任何 `git config`。

## 3. 提交前检查

```bash
git status
git log -1 --format='author=%an <%ae>%ncommitter=%cn <%ce>'
```

- author 或 committer 出现工具账号时，不得推送，先修正再提交。
- 只暂存本次改动的文件，不整目录 `git add -A`。
- 构建产物、码流、仿真库按 `.gitattributes` 与既有约定处理，不随意入库。

## 4. 分支与合并

- `main` 为集成分支；`main-A`、`main-B`、`main-C` 为各成员开发主线，`c-pipeline-next` 为 C 的实验分支。
- 合并通过 Pull Request 完成，合并提交信息保留来源分支。
- 需要改写历史（rebase 已推送的提交、filter-branch、修改作者）时，必须提前通知全体成员。改写会更换该提交之后所有 SHA，其他人需要 `git fetch` 后 `git reset --hard origin/<分支>` 或重新 clone；不得在旧历史上直接 merge。

## 5. 历史清理记录

| 日期 | 操作 | 范围 |
| --- | --- | --- |
| 2026-10-31 | 将 `256b5ea`、`5c1fd3e` 的 author/committer 由 `Codex <codex@openai.com>` 改写为 `slowshine <3297694176@qq.com>`，并强推 `main`、`main-A` | 提交树内容、提交说明、提交时间均未变；`main-B`、`main-C`、`c-pipeline-next` 未受影响 |

补充说明：

- 2026-09-26 至 2026-10-01 的 9 个提交使用占位身份 `userName <userEmail>`（`v1/v2/v3/rotate_image.py` 等算法文件），该身份不关联任何 GitHub 账号，按原样保留，不归属到负责人名下。
- GitHub 已合并的 Pull Request 页面不会因历史改写而更新其提交列表；Contributors 统计会在默认分支改写后重新计算，可能存在缓存延迟。
