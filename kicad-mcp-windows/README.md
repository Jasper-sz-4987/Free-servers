# kicad-mcp Windows 一键安装

在 Windows 上安装 [blwfish/kicad-mcp](https://github.com/blwfish/kicad-mcp)，并注册到 Claude Desktop 和 Claude Code。

## 用法

1. 把本目录下的两个文件放在同一个文件夹里（比如"下载"）：
   - `install-kicad-mcp.ps1`
   - `mcp_agent_notes-0.2.0-py3-none-any.whl`
2. 以**管理员身份**打开 PowerShell，执行：
   ```powershell
   cd $HOME\Downloads
   Set-ExecutionPolicy -Scope Process Bypass -Force; .\install-kicad-mcp.ps1
   ```
3. 看到 `OK: Registered 'kicad' in Claude Desktop` 后，从托盘图标完全退出 Claude Desktop，再重新打开。

脚本可以重复运行，已经完成的步骤会自动跳过。

## 脚本做了什么

- 用 winget 安装 Git、Python 3.12、Java 21（Temurin）和 KiCad（当前为 10.x）。
- 自动查找 KiCad 的实际安装位置，包括按用户安装到 `%LOCALAPPDATA%\Programs\KiCad\<版本>` 的情况。然后建立 `C:\Program Files\KiCad\bin` 和 `share` 两个 junction 指向它，因为 kicad-mcp 在 Windows 上只认这两个路径。
- 下载 FreeRouter v2.2.4，放到 `%USERPROFILE%\freerouting.jar`。
- 从 `main` 分支克隆 kicad-mcp，并在 venv 中安装。官方 PyPI 连不上时，会自动改用清华、阿里云镜像。
- `mcp-agent-notes` 这个依赖只放在 GitHub 上。如果脚本旁边有它的 `.whl` 文件，就先装本地文件，这样 GitHub 不通也能完成安装。
- 注册到 Claude Code（`claude mcp add -s user`），以及 Claude Desktop（`%APPDATA%\Claude\claude_desktop_config.json`，原配置会备份为 `.bak`）。
- 验证项：工具数为 18、项目列表、元件库搜索（0603 电阻）、KiCad 自带的 Python 能 `import pcbnew`。

## 关于 `mcp_agent_notes-0.2.0-py3-none-any.whl`

这个文件由 https://github.com/blwfish/mcp-agent-notes 构建，使用 kicad-mcp 0.18.0 固定的提交
`dd83adf8bb97755f91dbfcf857dbaeb987883f8f`。纯 Python，没有其他依赖。

SHA-256：`12b3fdbf508f34fdc3110eb75b437be07b7b7c726fce66c652c7250cc4758101`

kicad-mcp 以后如果更换了固定的提交，需要重新构建这个文件：
```bash
git clone https://github.com/blwfish/mcp-agent-notes && cd mcp-agent-notes
git checkout <pyproject.toml 中的新 commit>
pip wheel --no-deps . -w dist
```

## 已知情况

- Claude Desktop 如果是从微软商店安装的，配置文件在别的位置。可以在 Claude Desktop 的"设置 → Developer → Edit Config"里手动加入 `kicad` 这一项。
- `downloads.claude.ai` 连不上时，Claude Code 命令行会装不上。这不影响 Claude Desktop 的使用。
- kicad-mcp 官方只测试过 KiCad 8/9。KiCad 10.0.6 已经通过上面列出的验证项。
