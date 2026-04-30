<div align="center">

# VibeSync

[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey.svg)](https://github.com/rakeit-in/vibesync/releases)
[![Built with Rust](https://img.shields.io/badge/built%20with-Rust-orange.svg)](https://www.rust-lang.org/)

**统一管理 8 款 AI 编程工具的配置**

Claude Code · Codex · Gemini · OpenCode · Cursor · Antigravity · Codebuddy · Claude Internal

</div>

---

## 功能简介

VibeSync 在一个界面中统一管理 **MCP 服务器、Skills、Slash Commands 和 Prompts**，支持以下 8 款 AI 编程工具：

- **GUI 桌面应用** — 基于 Tauri + React 构建
- **`vibesync` 命令行工具** — 与 GUI 共享同一套 Rust 库，功能完全对等

两种界面的改动实时互通。

---

## 安装

### CLI（`vibesync`）

一键安装：

```bash
# macOS / Linux / WSL / Git Bash
curl -fsSL https://raw.githubusercontent.com/rakeit-in/vibesync/main/install.sh | bash
```

或手动下载安装：

```bash
# 下载安装脚本
curl -fsSL -o install.sh https://raw.githubusercontent.com/rakeit-in/vibesync/main/install.sh
chmod +x install.sh

# 安装（默认安装到 ~/.local/bin）
./install.sh

# 自定义安装目录
./install.sh --prefix /usr/local/bin

# 安装指定版本
./install.sh --version v1.0.0
```

Windows（PowerShell）：

```powershell
irm https://raw.githubusercontent.com/rakeit-in/vibesync/main/install.ps1 | iex
```

### GUI 应用

从 [Releases](https://github.com/rakeit-in/vibesync/releases) 下载对应平台的安装包：

| 平台 | 文件 |
|------|------|
| macOS Apple Silicon | `VibeContextSync_*_arm64.dmg` |
| macOS Intel | `VibeContextSync_*_x86_64.dmg` |
| Linux | `VibeContextSync_*_x86_64.AppImage` / `.deb` |
| Windows | `VibeContextSync_*_x86_64-setup.exe` / `.msi` |

---

## 快速开始

```bash
vibesync                    # 启动交互式 TUI
vibesync --help             # 查看所有命令
```

---

## 常用命令

### MCP 服务器

```bash
vibesync mcp list                        # 列出所有 MCP 服务器
vibesync mcp add                         # 添加服务器（交互式）
vibesync mcp sync                        # 同步到所有工具的配置文件
vibesync mcp import                      # 从所有工具当前配置导入
```

### Skills

```bash
vibesync skills list                     # 列出已安装的 Skills
vibesync skills install <name>           # 安装 Skill
vibesync skills sync                     # 同步到所有工具目录
vibesync skills scan-unmanaged           # 扫描工具目录中未纳管的 Skill
```

### Slash Commands

```bash
vibesync slash list                      # 列出所有 Slash Commands
vibesync slash add <name>                # 添加新命令
vibesync slash sync                      # 同步到工具目录
```

### Prompts

```bash
vibesync prompts list                    # 列出所有 Prompt 预设
vibesync prompts activate <id>           # 激活预设
vibesync prompts deactivate              # 取消当前激活的 Prompt
```

### 全局参数

```bash
vibesync --app <工具> <命令>             # 指定目标工具
vibesync --verbose <命令>                # 开启详细输出
```

**支持的工具：** `claude`（默认）、`codex`、`gemini`、`opencode`、`cursor`、`antigravity`、`codebuddy`、`claude-internal`

---

## License

MIT
