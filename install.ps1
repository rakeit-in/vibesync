# install.ps1
#
# Install the vibesync CLI on native Windows (PowerShell 5.1+ or PowerShell 7+).
# macOS / Linux / WSL / Git Bash users should use install.sh instead.
#
# Downloads a prebuilt vibesync binary from GitHub Releases
# and places it into a user-writable location. Does NOT build from source.
#
# Usage:
#   .\install.ps1 [-Prefix <dir>] [-Version <tag>] [-Force]
#
# Parameters:
#   -Prefix   Install directory.
#             Default: %LOCALAPPDATA%\Programs\vibesync
#             Env override: VIBESYNC_INSTALL_DIR
#   -Version  Release tag (e.g. v1.2.3). "latest" resolves automatically.
#             Default: latest
#             Env override: VIBESYNC_VERSION
#   -Force    Overwrite an existing vibesync.exe.
#             Env override: VIBESYNC_FORCE=1
#
# Additional environment variables:
#   VIBESYNC_INSTALL_BASE_URL   Override the base URL used to download releases.
#                               Default: https://github.com/rakeit-in/vibesync/releases/download
#
# Expected remote layout (GitHub Releases):
#   https://github.com/rakeit-in/vibesync/releases/download/<TAG>/
#     vibesync-windows-x86_64.exe
#     SHA256SUMS

[CmdletBinding()]
param(
    [string]$Prefix,
    [string]$Version,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$GitHubRepo = 'rakeit-in/vibesync'
$DefaultBaseUrl = "https://github.com/$GitHubRepo/releases/download"
$BaseUrl = if ($env:VIBESYNC_INSTALL_BASE_URL) { $env:VIBESYNC_INSTALL_BASE_URL } else { $DefaultBaseUrl }

if (-not $PSBoundParameters.ContainsKey('Prefix') -or [string]::IsNullOrWhiteSpace($Prefix)) {
    if ($env:VIBESYNC_INSTALL_DIR) {
        $Prefix = $env:VIBESYNC_INSTALL_DIR
    } else {
        $Prefix = Join-Path $env:LOCALAPPDATA 'Programs\vibesync'
    }
}

if (-not $PSBoundParameters.ContainsKey('Version') -or [string]::IsNullOrWhiteSpace($Version)) {
    if ($env:VIBESYNC_VERSION) {
        $Version = $env:VIBESYNC_VERSION
    } else {
        $Version = 'latest'
    }
}

if (-not $Force -and $env:VIBESYNC_FORCE -eq '1') {
    $Force = $true
}

function Write-Info($msg)  { Write-Host "[install] $msg" }
function Write-Warn2($msg) { Write-Warning "[install] $msg" }
function Fail($msg, [int]$code = 1) {
    Write-Host "[install][error] $msg" -ForegroundColor Red
    exit $code
}

# ---------- Resolve "latest" to an actual tag ----------

if ($Version -eq 'latest') {
    Write-Info "resolving latest version from GitHub releases..."
    try {
        # Use the HTML redirect at /releases/latest instead of the REST API,
        # because the API enforces a 60-req/hr limit on unauthenticated IPs,
        # which routinely breaks installs on shared networks.
        # /releases/latest responds with 302 -> /releases/tag/<TAG>.
        $req = [System.Net.HttpWebRequest]::Create("https://github.com/$GitHubRepo/releases/latest")
        $req.AllowAutoRedirect = $false
        $req.Method = 'HEAD'
        $req.UserAgent = 'vibesync-install'
        $resp = $req.GetResponse()
        $location = $resp.Headers['Location']
        $resp.Close()
        if (-not $location -or $location -notmatch '/tag/([^/]+)$') {
            Fail "failed to resolve latest version (no release published yet?)" 3
        }
        $Version = $Matches[1]
        Write-Info "latest version: $Version"
    } catch {
        Fail "failed to resolve latest version from GitHub: $($_.Exception.Message)" 3
    }
}

# ---------- Detect arch ----------

switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { $arch = 'x86_64' }
    'ARM64' { $arch = 'arm64'  }
    default { Fail "Unsupported CPU arch: $env:PROCESSOR_ARCHITECTURE" 2 }
}

# Current Windows release matrix only promises x86_64.
if ($arch -ne 'x86_64') {
    Fail "This installer currently only supports Windows x86_64. Detected: $arch" 2
}

$asset    = "vibesync-windows-$arch.exe"
$AssetUrl = "$BaseUrl/$Version/$asset"
$SumsUrl  = "$BaseUrl/$Version/SHA256SUMS"

Write-Info "target : $asset"
Write-Info "version: $Version"
Write-Info "prefix : $Prefix"
Write-Info "asset  : $AssetUrl"

# ---------- Download ----------

$tmpDir    = Join-Path ([System.IO.Path]::GetTempPath()) ("vibesync-install-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpDir | Out-Null
$assetPath = Join-Path $tmpDir $asset
$sumsPath  = Join-Path $tmpDir 'SHA256SUMS'

try {
    Write-Info "downloading asset..."
    Invoke-WebRequest -Uri $AssetUrl -OutFile $assetPath -UseBasicParsing
} catch {
    Fail "failed to download $AssetUrl : $($_.Exception.Message)" 3
}

$sumsAvailable = $true
try {
    Write-Info "downloading SHA256SUMS..."
    Invoke-WebRequest -Uri $SumsUrl -OutFile $sumsPath -UseBasicParsing
} catch {
    $sumsAvailable = $false
    Write-Warn2 "SHA256SUMS not available at $SumsUrl; skipping checksum verification."
}

if ($sumsAvailable) {
    Write-Info "verifying checksum..."
    $escaped = [regex]::Escape($asset)
    $line = (Get-Content $sumsPath) | Where-Object { $_ -match "\s\*?$escaped\s*$" } | Select-Object -First 1
    if (-not $line) {
        Fail "checksum entry for $asset not found in SHA256SUMS" 3
    }
    $expected = ($line -split '\s+')[0].ToLowerInvariant()
    $actual   = (Get-FileHash -Algorithm SHA256 -Path $assetPath).Hash.ToLowerInvariant()
    if ($expected -ne $actual) {
        Fail "checksum mismatch for $asset : expected $expected, got $actual" 3
    }
    Write-Info "checksum ok"
}

# ---------- Install ----------

if (-not (Test-Path $Prefix)) {
    New-Item -ItemType Directory -Path $Prefix | Out-Null
}

$destExe = Join-Path $Prefix 'vibesync.exe'

if ((Test-Path $destExe) -and (-not $Force)) {
    Fail "$destExe already exists. Re-run with -Force or set VIBESYNC_FORCE=1 to overwrite."
}

Copy-Item -Path $assetPath -Destination $destExe -Force
Write-Info "installed: $destExe"

# ---------- PATH hint ----------

$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if ($null -eq $userPath) { $userPath = '' }
$pathItems = $userPath -split ';' | Where-Object { $_ -ne '' }
if ($pathItems -notcontains $Prefix) {
    Write-Warn2 "$Prefix is not in your user PATH. Add it with:"
    Write-Host "    setx PATH `"$Prefix;%PATH%`""
}

# ---------- Self check ----------

try {
    & $destExe --version
} catch {
    Write-Warn2 "installed binary did not respond to --version; please verify manually."
}

Write-Info "done"

# cleanup
Remove-Item -Recurse -Force $tmpDir
