# install-kicad-mcp.ps1
# One-shot installer for kicad-mcp (https://github.com/blwfish/kicad-mcp) on Windows.
# Run in an ADMINISTRATOR PowerShell:
#   Set-ExecutionPolicy -Scope Process Bypass -Force; .\install-kicad-mcp.ps1
# Safe to re-run: every step skips work that is already done.

# "Continue" so native tools writing to stderr (git, java, pip) do not abort under
# Windows PowerShell 5.1; failures are checked explicitly via $LASTEXITCODE / throw.
$ErrorActionPreference = "Continue"
$InstallDir = Join-Path $HOME "kicad-mcp"
$JarPath    = Join-Path $HOME "freerouting.jar"
$JarUrl     = "https://github.com/freerouting/freerouting/releases/download/v2.2.4/freerouting-2.2.4.jar"

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    WARN: $msg" -ForegroundColor Yellow }

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")
}

function Winget-Install($id, $name) {
    Write-Host "    Installing $name ($id) via winget..."
    winget install --id $id -e --accept-source-agreements --accept-package-agreements --silent
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {  # -1978335189 = already installed
        throw "winget failed to install $name (exit $LASTEXITCODE)"
    }
    Refresh-Path
}

# --- 0. Pre-flight -----------------------------------------------------------
Step "Checking environment"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw "Please run this script from an Administrator PowerShell." }
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget not found. Install 'App Installer' from the Microsoft Store, then re-run."
}
Ok "Administrator + winget available"

# --- 1. Git ------------------------------------------------------------------
Step "Git"
if (Get-Command git -ErrorAction SilentlyContinue) { Ok (git --version) }
else { Winget-Install "Git.Git" "Git"; Ok (git --version) }

# --- 2. Python 3.10+ ---------------------------------------------------------
Step "Python 3.10+"
$py = $null
foreach ($cand in @("py -3.12", "py -3.11", "py -3.10", "python")) {
    try {
        $parts = $cand.Split(" ")
        $v = & $parts[0] $parts[1..9] -c "import sys;print('%d.%d'%sys.version_info[:2])" 2>$null
        if ($v -and [version]$v -ge [version]"3.10") { $py = $parts; break }
    } catch {}
}
if (-not $py) {
    Winget-Install "Python.Python.3.12" "Python 3.12"
    $py = @("py", "-3.12")
}
Ok ("Using: " + ($py -join " ") + " -> " + (& $py[0] $py[1..9] --version))

# --- 3. Java 17+ -------------------------------------------------------------
Step "Java 17+ (needed for autorouting)"
$javaOk = $false
if (Get-Command java -ErrorAction SilentlyContinue) {
    $jv = (& java -version 2>&1 | Select-Object -First 1) -as [string]
    if ($jv -match '"(\d+)') { $javaOk = [int]$Matches[1] -ge 17 }
}
if (-not $javaOk) { Winget-Install "EclipseAdoptium.Temurin.21.JRE" "Java 21 (Temurin JRE)" }
Ok ((& java -version 2>&1 | Select-Object -First 1) -as [string])

# --- 4. KiCad 9 --------------------------------------------------------------
Step "KiCad 8+"
function Find-KiCadRoot {
    # A "root" is the folder that contains bin\kicad-cli.exe.
    $cands = New-Object System.Collections.Generic.List[string]
    # 1. Install locations recorded by the KiCad installer (machine + per-user).
    $regKeys = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                 "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
                 "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*")
    Get-ItemProperty $regKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "KiCad*" } | ForEach-Object {
            if ($_.InstallLocation) { $cands.Add($_.InstallLocation.Trim('"')) }
            # UninstallString may carry quotes and args, e.g. "C:\...\uninstall.exe" /S
            if ($_.UninstallString -match '^\s*"?([^"]+?\.exe)') { $cands.Add((Split-Path $Matches[1] -Parent)) }
        }
    # 2. Usual parent folders, plus their versioned subfolders (8.0, 9.0, 10.0, ...).
    foreach ($p in @("$env:ProgramFiles\KiCad", "${env:ProgramFiles(x86)}\KiCad",
                     "$env:LOCALAPPDATA\Programs\KiCad", "C:\KiCad")) {
        $cands.Add($p)
        Get-ChildItem $p -Directory -ErrorAction SilentlyContinue | ForEach-Object { $cands.Add($_.FullName) }
    }
    # 3. kicad-cli already on PATH.
    $onPath = Get-Command kicad-cli.exe -ErrorAction SilentlyContinue
    if ($onPath) { $cands.Add((Split-Path (Split-Path $onPath.Source -Parent) -Parent)) }

    $found = $cands | Where-Object {
            try { $_ -and (Test-Path -LiteralPath (Join-Path $_ "bin\kicad-cli.exe") -ErrorAction Stop) } catch { $false }
        } |
        ForEach-Object { (Resolve-Path $_).Path } | Select-Object -Unique
    if (-not $found) { return $null }
    # Prefer the highest version (via kicad-cli.exe file version), real folders over our junctions.
    return ($found | Sort-Object @{ Expression = {
        try { [version](Get-Item (Join-Path $_ "bin\kicad-cli.exe")).VersionInfo.ProductVersion.Split(" ")[0] }
        catch { [version]"0.0" } }; Descending = $true },
        @{ Expression = { $_ -eq "C:\Program Files\KiCad" } } | Select-Object -First 1)
}
$KiCadRoot = Find-KiCadRoot
if (-not $KiCadRoot) {
    Winget-Install "KiCad.KiCad" "KiCad"
    $KiCadRoot = Find-KiCadRoot
    if (-not $KiCadRoot) {
        Warn "Could not locate kicad-cli.exe. Searching C:\ (this can take a minute)..."
        $hit = Get-ChildItem C:\ -Recurse -Filter kicad-cli.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { $KiCadRoot = Split-Path (Split-Path $hit.FullName -Parent) -Parent }
    }
    if (-not $KiCadRoot) {
        throw "KiCad is installed but kicad-cli.exe was not found anywhere on C:. Open KiCad once, then re-run; or reinstall KiCad from https://www.kicad.org/download/windows/"
    }
}
$KiCadCli = Join-Path $KiCadRoot "bin\kicad-cli.exe"
Ok ("KiCad at $KiCadRoot, version " + (& $KiCadCli --version))

# kicad-mcp hard-codes C:\Program Files\KiCad\bin\python.exe for its pcbnew bridge
# and C:\Program Files\KiCad\share\kicad for libraries (no env override for the
# Python path). KiCad 8/9 install into a versioned subfolder, so add junctions.
$Base = "C:\Program Files\KiCad"
if ($KiCadRoot -ne $Base) {
    if (-not (Test-Path $Base)) { New-Item -ItemType Directory -Path $Base | Out-Null }
    foreach ($sub in @("bin", "share")) {
        $link = Join-Path $Base $sub
        $target = Join-Path $KiCadRoot $sub
        if (-not (Test-Path $link)) {
            New-Item -ItemType Junction -Path $link -Target $target | Out-Null
            Ok "Junction $link -> $target"
        } else { Ok "$link already exists" }
    }
}

# --- 5. FreeRouter -----------------------------------------------------------
Step "FreeRouter v2.2.4"
if ((Test-Path $JarPath) -and ((Get-Item $JarPath).Length -gt 10MB)) { Ok "$JarPath already present" }
else {
    Invoke-WebRequest -Uri $JarUrl -OutFile $JarPath -UseBasicParsing
    Ok "Downloaded to $JarPath"
}

# --- 6. kicad-mcp ------------------------------------------------------------
Step "kicad-mcp (main branch)"
if (Test-Path (Join-Path $InstallDir ".git")) {
    git -C $InstallDir checkout main; git -C $InstallDir pull --ff-only
} else {
    git clone -b main https://github.com/blwfish/kicad-mcp.git $InstallDir
}
$VenvPy = Join-Path $InstallDir ".venv\Scripts\python.exe"
if (-not (Test-Path $VenvPy)) { & $py[0] $py[1..9] -m venv (Join-Path $InstallDir ".venv") }
# files.pythonhosted.org is slow/unreliable from some networks (e.g. mainland China),
# so fall back to domestic PyPI mirrors. Longer timeout + more retries for big wheels.
$pipOpts = @("--timeout", "120", "--retries", "10", "--no-cache-dir")
$indexes = @("", "https://pypi.tuna.tsinghua.edu.cn/simple", "https://mirrors.aliyun.com/pypi/simple/")
# kicad-mcp pins mcp-agent-notes as a git+https://github.com dependency (not on PyPI).
# If github.com is unreachable, put mcp_agent_notes-*.whl next to this script:
# once it is installed, pip treats the requirement as satisfied and skips the clone.
$localWheel = Get-ChildItem -Path $PSScriptRoot -Filter "mcp_agent_notes-*.whl" -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($localWheel) {
    & $VenvPy -m pip install $localWheel.FullName --no-deps -q
    if ($LASTEXITCODE -ne 0) { throw "Failed to install $($localWheel.Name)" }
    Ok "Installed $($localWheel.Name) from local file (no GitHub needed)"
}
$pipOk = $false
foreach ($idx in $indexes) {
    $extra = @()
    if ($idx) { Warn "Retrying pip with mirror $idx"; $extra = @("-i", $idx) }
    & $VenvPy -m pip install --upgrade pip -q @pipOpts @extra
    # Plain editable install: the 'dev' extra is only test tooling and no longer exists.
    & $VenvPy -m pip install -e "$InstallDir" @pipOpts @extra
    if ($LASTEXITCODE -eq 0) { $pipOk = $true; break }
    Start-Sleep -Seconds 3   # let AV/indexer release temp files (WinError 32)
}
if (-not $pipOk) { throw "pip install failed on all indexes - check your network/proxy" }
$ServerExe = Join-Path $InstallDir ".venv\Scripts\kicad-mcp.exe"
if (-not (Test-Path $ServerExe)) { throw "kicad-mcp.exe not found at $ServerExe" }
Ok "Installed: $ServerExe"

# --- 7. Claude Code + registration -------------------------------------------
Step "Registering with Claude Code"
$env:Path += ";" + (Join-Path $HOME ".local\bin")
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Warn "Claude Code CLI not found - installing"
    # Run the official installer in its own process: piping it into
    # Invoke-Expression inside this script fails ("Cannot overwrite variable Target").
    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://claude.ai/install.ps1 | iex"
    Refresh-Path
    $env:Path += ";" + (Join-Path $HOME ".local\bin")
}
if (Get-Command claude -ErrorAction SilentlyContinue) {
    claude mcp remove kicad -s user 2>$null | Out-Null
    claude mcp add kicad -s user `
        -e "KICAD_CLI_PATH=$KiCadCli" `
        -e "FREEROUTER_JAR=$JarPath" `
        -- $ServerExe
    if ($LASTEXITCODE -eq 0) { Ok "Registered 'kicad' in Claude Code (user scope - every project)" }
    else { Warn "claude mcp add failed (exit $LASTEXITCODE)" }
} else {
    Warn "Claude Code CLI still not available - skipped Claude Code registration"
}

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

# --- 8. Verify ---------------------------------------------------------------
Step "Verifying (same checks as AGENT-INSTALL.md)"
$env:KICAD_CLI_PATH = $KiCadCli
$env:FREEROUTER_JAR = $JarPath
$verify = @'
import asyncio, sys
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
async def main():
    params = StdioServerParameters(command=sys.argv[1])
    async with stdio_client(params) as (r, w):
        async with ClientSession(r, w) as s:
            await s.initialize()
            tools = await s.list_tools()
            print("tools:", len(tools.tools))
            for name, args in [("project", {"operation": "list"}),
                               ("library", {"operation": "search", "query": "0603 resistor", "type": "footprint"})]:
                res = await s.call_tool(name, args)
                print(name, "->", res.content[0].text[:400])
asyncio.run(main())
'@
$verifyFile = Join-Path $env:TEMP "kicad_mcp_verify.py"
Set-Content -Path $verifyFile -Value $verify -Encoding ASCII
& $VenvPy $verifyFile $ServerExe 2>$null
& (Join-Path $KiCadRoot "bin\python.exe") -c "import pcbnew; print('pcbnew', pcbnew.Version())"

Step "Done"
if (Get-Command claude -ErrorAction SilentlyContinue) { claude mcp list }
Write-Host "`nRestart Claude Code, then ask it: search the library for a 0603 resistor footprint." -ForegroundColor Green
