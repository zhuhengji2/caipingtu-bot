#Requires -Version 5.1
<#
  caipingtu-bot one-click installer (Windows)
  Usage:
    irm https://raw.githubusercontent.com/zhuhengji2/caipingtu-bot/main/install.ps1 | iex
  Options:
    .\install.ps1 -SkipModel        skip the 208MB inpaint model
    .\install.ps1 -SkipDeps         skip pip install
    .\install.ps1 -Force            overwrite an existing install
#>
param(
    [string]$Target = (Join-Path $env:USERPROFILE ".workbuddy\skills\caipingtu"),
    [switch]$SkipDeps,
    [switch]$SkipModel,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$Repo = "zhuhengji2/caipingtu-bot"
$Branch = "main"
$Sources = @(
    "https://github.com/$Repo/archive/refs/heads/$Branch.zip",
    "https://gh-proxy.com/https://github.com/$Repo/archive/refs/heads/$Branch.zip",
    "https://ghfast.top/https://github.com/$Repo/archive/refs/heads/$Branch.zip"
)

function Write-Step($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  caipingtu-bot installer" -ForegroundColor White
Write-Host "  CAD floor plan -> colored interior plan" -ForegroundColor DarkGray
Write-Host ""

if ($PSVersionTable.PSVersion.Major -lt 5) {
    throw "PowerShell 5.1 or newer is required."
}

$tmp = Join-Path $env:TEMP ("caipingtu-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

# Local checkout? use it directly. Otherwise download the archive.
$localSkill = $null
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "SKILL.md"))) {
    $localSkill = $PSScriptRoot
    Write-Step "Using local files: $localSkill"
}

if (-not $localSkill) {
    $zip = Join-Path $tmp "src.zip"
    $got = $false
    foreach ($url in $Sources) {
        try {
            Write-Step "Downloading from $url"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 120
            if ((Get-Item $zip).Length -gt 50000) { $got = $true; break }
        } catch {
            Write-Warn "failed, trying next mirror"
        }
    }
    if (-not $got) {
        Write-Warn "All download sources failed."
        Write-Warn "Fallback: download the ZIP manually from https://github.com/$Repo"
        throw "Download failed."
    }
    Write-Step "Extracting"
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $localSkill = (Get-ChildItem -Path $tmp -Directory | Where-Object { Test-Path (Join-Path $_.FullName "SKILL.md") } | Select-Object -First 1).FullName
    if (-not $localSkill) { throw "Archive does not contain SKILL.md" }
}

# Install into the skills folder
if (Test-Path $Target) {
    if (-not $Force) {
        Write-Warn "Target already exists: $Target"
        Write-Warn "Re-run with -Force to replace it (a .bak copy is kept)."
        throw "Aborted."
    }
    $bak = "$Target.bak"
    if (Test-Path $bak) { Remove-Item $bak -Recurse -Force }
    Move-Item $Target $bak
    Write-Warn "Old version moved to $bak"
}

$parent = Split-Path $Target -Parent
if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

Write-Step "Installing skill to $Target"
Copy-Item $localSkill $Target -Recurse -Force
Remove-Item (Join-Path $Target ".git") -Recurse -Force -ErrorAction SilentlyContinue
Write-Ok "SKILL.md installed"

# Python deps
if (-not $SkipDeps) {
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) {
        Write-Warn "Python not found in PATH. Install Python 3.9+ first: https://www.python.org/downloads/"
        Write-Warn "Then run: pip install -r `"$Target\requirements.txt`""
    } else {
        Write-Step "Installing Python dependencies (opencv / numpy / onnxruntime)"
        & python -m pip install -r (Join-Path $Target "requirements.txt") --quiet
        if ($LASTEXITCODE -ne 0) { Write-Warn "pip install returned $LASTEXITCODE" } else { Write-Ok "Dependencies ready" }
    }
} else {
    Write-Warn "Skipped dependencies"
}

# Inpaint model
$model = Join-Path $Target "scripts\models\lama_fp32.onnx"
if (-not $SkipModel) {
    if (Test-Path $model) {
        Write-Ok "Model already present, skipped"
    } else {
        Write-Step "Downloading inpaint model (208 MB, resumable)"
        & python (Join-Path $Target "scripts\download_model.py")
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Model download failed. Run it again later:"
            Write-Warn "  python `"$Target\scripts\download_model.py`""
        } else {
            Write-Ok "Model ready"
        }
    }
} else {
    Write-Warn "Skipped model download. Fetch it later with:"
    Write-Warn "  python `"$Target\scripts\download_model.py`""
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "  Done. Restart WorkBuddy, then send a floor plan and say:" -ForegroundColor White
Write-Host "    make a colored floor plan / zuo cai ping tu" -ForegroundColor Gray
Write-Host ""
Write-Host "  Skill folder: $Target" -ForegroundColor DarkGray
Write-Host ""
