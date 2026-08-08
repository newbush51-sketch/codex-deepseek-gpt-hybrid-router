# Codex DeepSeek + GPT Hybrid Router

在 Windows 上把 DeepSeek 与 GPT/Codex 接入同一个 Codex 入口，并提供开机自启、健康检查、失败重启、60 秒看门狗和离线手动恢复。

![Architecture](docs/architecture.png)

## 它解决什么

Codex 统一连接本地 `127.0.0.1:4140`：

- `deepseek-*` 模型转发到 LiteLLM `4141`，再访问 DeepSeek API。
- 其他模型转发到 OpenAI Codex 后端，并通过 Clash/Mihomo `7897` 出网。
- DeepSeek 分支会移除 OpenAI Authorization、Cookie 和账号 ID，避免凭据串线。
- Windows 登录后四个计划任务按 5/10/20/35 秒错峰启动。
- 看门狗每 60 秒检查并按依赖顺序修复异常组件。

> 这是“模型路由”，不是把两个模型的答案合并为一个答案。

## 架构

```text
Codex -> Hybrid Router :4140
           |-- deepseek-* -> LiteLLM :4141 -> DeepSeek API
           `-- other models -> Clash :7897 -> OpenAI Codex backend

Windows logon -> delayed tasks -> 60s watchdog -> automatic recovery
```

## 要求

- Windows 10/11
- Codex Desktop 或 Codex CLI（至少启动过一次，以生成 `~/.codex/models_cache.json`）
- Python 3.10+
- Clash Verge Rev / Mihomo，混合端口为 `7897`
- DeepSeek API Key 与可用余额

## 快速安装

1. 克隆仓库并进入目录。

```powershell
git clone https://github.com/newbush51-sketch/codex-deepseek-gpt-hybrid-router.git
cd codex-deepseek-gpt-hybrid-router
```

2. 把 DeepSeek Key 写入 Windows 用户级环境变量，然后重新打开 PowerShell。

```powershell
setx DEEPSEEK_API_KEY "在本机填写你的Key"
```

3. 安装。若 Clash 不在默认目录，请传入实际目录。

```powershell
.\Install.ps1 -ClashVergeDir "D:\path\to\Clash Verge"
```

4. 把 [`config/config.toml.snippet`](config/config.toml.snippet) 合并到 `%USERPROFILE%\.codex\config.toml`，并把 `YOUR_NAME` 换成 Windows 用户名。修改前请备份原配置。

5. 完整验收。

```powershell
.\Test-Stack.ps1
```

健康结果应包含：

```text
Clash7897      : True
Hybrid4140     : True
DeepSeek4141   : True
OpenAIUpstream : True
Healthy        : True
```

## 稳定性设计

| 层级 | 机制 |
|---|---|
| 启动脚本 | 启动前探活，健康时直接退出，避免重复实例 |
| 计划任务 | 登录后错峰启动，失败后每分钟重试 |
| 看门狗 | 每 60 秒检查 `7897`、`4141`、`4140` |
| 上游探测 | 使用无效令牌确认请求能到达 OpenAI，不暴露真实令牌 |
| 手动恢复 | 双击 `Recover-Codex-Proxy.cmd`，不依赖 Codex 在线 |
| 日志 | 5–10 MB 轮转，保留最近一份旧日志 |

## 常用命令

```powershell
# 查看心跳
Get-Content "$HOME\.codex\deepseek-proxy\stack-guard-heartbeat.txt"

# 完整检查并自动修复
powershell -File "$HOME\.codex\deepseek-proxy\Ensure-CodexProxyStack.ps1" -FullCheck

# 查看任务状态
Get-ScheduledTask -TaskName "Codex*" | Select-Object TaskName, State
```

## 测试

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m pytest -q
```

## 安全说明

- 所有服务只监听 `127.0.0.1`。
- API Key 只从用户环境变量读取，不进入仓库、任务参数或日志。
- `hybrid-models.json` 在安装时由本机 Codex 模型缓存生成，并被 `.gitignore` 排除。
- 不要公开 `~/.codex/auth.json`、`.credentials.json`、Cookie、完整日志或真实 Key。

## 卸载

只删除计划任务，保留部署文件：

```powershell
.\Uninstall.ps1
```

同时删除 `%USERPROFILE%\.codex\deepseek-proxy`：

```powershell
.\Uninstall.ps1 -RemoveDeployedFiles
```

## 许可证

[MIT](LICENSE)

