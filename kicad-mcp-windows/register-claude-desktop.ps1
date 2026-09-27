# register-claude-desktop.ps1
# Adds the kicad MCP server to Claude Desktop's config (both the Microsoft Store
# build and the regular installer build), keeping all existing settings.
# Assumes install-kicad-mcp.ps1 has already installed everything. No admin needed:
#   Set-ExecutionPolicy -Scope Process Bypass -Force; .\register-claude-desktop.ps1

$ErrorActionPreference = "Continue"
function Ok($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    WARN: $msg" -ForegroundColor Yellow }

$InstallDir = Join-Path $HOME "kicad-mcp"
$VenvPy    = Join-Path $InstallDir ".venv\Scripts\python.exe"
$ServerExe = Join-Path $InstallDir ".venv\Scripts\kicad-mcp.exe"
$JarPath   = Join-Path $HOME "freerouting.jar"
$KiCadCli  = "C:\Program Files\KiCad\bin\kicad-cli.exe"   # junction made by the installer
if (-not (Test-Path $ServerExe)) { throw "kicad-mcp not found at $ServerExe - run install-kicad-mcp.ps1 first" }
if (-not (Test-Path $KiCadCli)) { Warn "$KiCadCli not found - run install-kicad-mcp.ps1 first" }

# Also register with the Claude Desktop app. The Microsoft Store (MSIX) build
# reads its config from a virtualized folder under %LOCALAPPDATA%\Packages, not
# %APPDATA%\Claude - write to every location that exists so either build works.
$DesktopCfgDirs = @(Get-ChildItem "$env:LOCALAPPDATA\Packages\Claude_*\LocalCache\Roaming\Claude" -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { $_.FullName })
$DesktopCfgDirs += (Join-Path $env:APPDATA "Claude")
# Merge with Python's json module: keeps every existing key (preferences, other
# MCP servers) intact and writes UTF-8 without BOM, which Claude Desktop requires.
$merge = @'
import json, os, shutil, sys
path, exe, cli, jar = sys.argv[1:5]
cfg = {}
if os.path.exists(path):
    shutil.copyfile(path, path + ".bak")
    with open(path, encoding="utf-8-sig") as f:
        text = f.read().strip()
    if text:
        cfg = json.loads(text)
cfg.setdefault("mcpServers", {})["kicad"] = {
    "command": exe,
    "env": {"KICAD_CLI_PATH": cli, "FREEROUTER_JAR": jar},
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
print("ok")
'@
$mergeFile = Join-Path $env:TEMP "kicad_mcp_merge_cfg.py"
Set-Content -Path $mergeFile -Value $merge -Encoding ASCII
foreach ($dir in $DesktopCfgDirs) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $cfgPath = Join-Path $dir "claude_desktop_config.json"
    $out = & $VenvPy $mergeFile $cfgPath $ServerExe $KiCadCli $JarPath 2>&1
    if ($LASTEXITCODE -eq 0) { Ok "Registered 'kicad' in Claude Desktop config: $cfgPath" }
    else { Warn "Could not update $cfgPath : $out" }
}
Write-Host "    -> Fully quit Claude Desktop (tray icon > Quit) and reopen it." -ForegroundColor Green

