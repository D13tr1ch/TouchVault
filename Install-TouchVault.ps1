#Requires -Version 5.1
<#
.SYNOPSIS
    TouchVault Setup Wizard - Configures KeePass + YubiKey credential management.

.DESCRIPTION
    Interactive setup that:
    1. Checks prerequisites (KeePassXC, YubiKey Manager)
    2. Optionally installs KeePassXC via winget
    3. Creates or locates the KeePass database
    4. Configures YubiKey HMAC-SHA1 challenge-response on Slot 2
    5. Saves the master password with DPAPI encryption
    6. Installs the TouchVault module to the user's PowerShell module path
    7. Verifies everything works

.EXAMPLE
    .\Install-TouchVault.ps1
#>

[CmdletBinding()]
param(
    [switch]$SkipModuleInstall,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Step {
    param([string]$Number, [string]$Text)
    Write-Host ""
    Write-Host "  [$Number] $Text" -ForegroundColor Cyan
    Write-Host "  $('=' * ($Text.Length + 4))" -ForegroundColor DarkCyan
}

function Write-OK  { param([string]$Text) Write-Host "     OK  $Text" -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host "   WARN  $Text" -ForegroundColor Yellow }
function Write-Fail { param([string]$Text) Write-Host "   FAIL  $Text" -ForegroundColor Red }

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  TouchVault Setup Wizard" -ForegroundColor Yellow
Write-Host "  ======================" -ForegroundColor DarkYellow
Write-Host "  YubiKey-backed KeePass credential management" -ForegroundColor Gray
Write-Host "  for GitHub Copilot and PowerShell automation" -ForegroundColor Gray
Write-Host ""

# ---------------------------------------------------------------------------
# Step 1: Check KeePassXC
# ---------------------------------------------------------------------------
Write-Step "1/6" "Checking KeePassXC"

$cliPaths = @(
    "C:\Program Files\KeePassXC\keepassxc-cli.exe",
    "${env:ProgramFiles}\KeePassXC\keepassxc-cli.exe",
    "${env:LOCALAPPDATA}\KeePassXC\keepassxc-cli.exe"
)
$cli = $null
foreach ($p in $cliPaths) {
    if (Test-Path $p) { $cli = $p; break }
}
if (-not $cli) {
    $cmd = Get-Command keepassxc-cli -ErrorAction SilentlyContinue
    if ($cmd) { $cli = $cmd.Source }
}

if ($cli) {
    $ver = & $cli --version 2>&1
    Write-OK "KeePassXC CLI found: $cli (v$ver)"
} else {
    Write-Warn "KeePassXC CLI not found."
    $install = Read-Host "     Install KeePassXC via winget? (Y/n)"
    if ($install -ne 'n') {
        Write-Host "     Installing KeePassXC..." -ForegroundColor Gray
        winget install KeePassXCTeam.KeePassXC --accept-package-agreements --accept-source-agreements
        $cli = "C:\Program Files\KeePassXC\keepassxc-cli.exe"
        if (-not (Test-Path $cli)) {
            Write-Fail "Installation may require a restart. Re-run this script after restart."
            exit 1
        }
        $ver = & $cli --version 2>&1
        Write-OK "KeePassXC installed: v$ver"
    } else {
        Write-Fail "KeePassXC is required. Install from https://keepassxc.org/download/ and re-run."
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Step 2: Check YubiKey
# ---------------------------------------------------------------------------
Write-Step "2/6" "Checking YubiKey"

$ykman = $null
$ykmanPaths = @(
    "C:\Program Files\Yubico\YubiKey Manager\ykman.exe",
    "${env:ProgramFiles}\Yubico\YubiKey Manager\ykman.exe"
)
foreach ($p in $ykmanPaths) {
    if (Test-Path $p) { $ykman = $p; break }
}
if (-not $ykman) {
    $cmd = Get-Command ykman -ErrorAction SilentlyContinue
    if ($cmd) { $ykman = $cmd.Source }
}

if ($ykman) {
    $devices = & $ykman list 2>&1
    if ($devices -match "YubiKey") {
        Write-OK "YubiKey detected: $($devices | Select-Object -First 1)"

        # Check Slot 2 for HMAC-SHA1
        $slots = & $ykman otp info 2>&1
        if ($slots -match "Slot 2.*challenge-response") {
            Write-OK "Slot 2 already configured for HMAC-SHA1 challenge-response"
        } else {
            Write-Warn "Slot 2 is not configured for HMAC-SHA1."
            $configSlot = Read-Host "     Configure Slot 2 now? This is required for TouchVault. (Y/n)"
            if ($configSlot -ne 'n') {
                Write-Host "     Touch your YubiKey when it blinks..." -ForegroundColor Yellow
                & $ykman otp chalresp --touch --generate 2 --force 2>&1
                Write-OK "Slot 2 configured for HMAC-SHA1 challenge-response"
                Write-Warn "IMPORTANT: Open KeePassXC > Database Settings > Security > Add YubiKey Slot 2."
            } else {
                Write-Warn "YubiKey Slot 2 must be configured manually. See README.md"
            }
        }
    } else {
        Write-Warn "No YubiKey detected. Plug in your YubiKey and re-run."
    }
} else {
    Write-Warn "YubiKey Manager (ykman) not found."
    Write-Host "     Install from https://www.yubico.com/support/download/yubikey-manager/" -ForegroundColor Gray
    Write-Host "     YubiKey Manager is optional for setup but recommended." -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# Step 3: Locate or create KeePass database
# ---------------------------------------------------------------------------
Write-Step "3/6" "KeePass Database"

$dbCandidates = @(
    "$env:USERPROFILE\.keepass\Vault.kdbx",
    "$env:USERPROFILE\Passwords.kdbx",
    "C:\NTSH\Passwords.kdbx"
)
$db = $null
foreach ($p in $dbCandidates) {
    if (Test-Path $p) { $db = $p; break }
}

if ($db) {
    Write-OK "Database found: $db"
} else {
    Write-Host "     No database found at default locations." -ForegroundColor Gray
    $dbPath = Read-Host "     Enter path to your .kdbx file (or press Enter to create one)"
    if ($dbPath -and (Test-Path $dbPath)) {
        $db = $dbPath
        Write-OK "Database: $db"
    } else {
        $newDir = "$env:USERPROFILE\.keepass"
        if (-not (Test-Path $newDir)) { New-Item -Path $newDir -ItemType Directory -Force | Out-Null }
        $db = "$newDir\Vault.kdbx"
        Write-Host "     Creating new database at $db" -ForegroundColor Gray
        Write-Host "     You will be prompted to enter a master password." -ForegroundColor Gray
        $secure = Read-Host "     Enter master password for new database" -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $rawPw = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
        finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        $rawPw | & $cli db-create $db --set-password 2>&1
        if (Test-Path $db) {
            Write-OK "Database created: $db"
        } else {
            Write-Fail "Failed to create database. Create manually in KeePassXC and re-run."
            exit 1
        }
    }
}

# ---------------------------------------------------------------------------
# Step 4: Save master password (DPAPI)
# ---------------------------------------------------------------------------
Write-Step "4/6" "Master Password (DPAPI Encryption)"

$credFile = "$env:USERPROFILE\.keepass_cred"
if ((Test-Path $credFile) -and -not $Force) {
    Write-OK "DPAPI-encrypted master password already saved."
    $overwrite = Read-Host "     Overwrite? (y/N)"
    if ($overwrite -eq 'y') {
        $secure = Read-Host "     Enter KeePass master password" -AsSecureString
        $secure | ConvertFrom-SecureString | Set-Content $credFile -Force
        Write-OK "Master password updated."
    }
} else {
    $secure = Read-Host "     Enter KeePass master password" -AsSecureString
    $secure | ConvertFrom-SecureString | Set-Content $credFile -Force
    Write-OK "Master password saved (DPAPI-encrypted, tied to your Windows account)."
}

# ---------------------------------------------------------------------------
# Step 5: Install module
# ---------------------------------------------------------------------------
Write-Step "5/6" "Installing TouchVault Module"

if ($SkipModuleInstall) {
    Write-Warn "Skipped (use -SkipModuleInstall to skip)"
} else {
    $moduleSrc  = $PSScriptRoot
    $moduleBase = "$env:USERPROFILE\Documents\PowerShell\Modules\TouchVault"
    $moduleLegacy = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\TouchVault"

    # Install to both PS 7 and PS 5.1 module paths
    foreach ($target in @($moduleBase, $moduleLegacy)) {
        $verDir = Join-Path $target "1.0.0"
        if (-not (Test-Path $verDir)) { New-Item -Path $verDir -ItemType Directory -Force | Out-Null }

        Copy-Item "$moduleSrc\TouchVault.psd1" "$verDir\" -Force
        Copy-Item "$moduleSrc\TouchVault.psm1" "$verDir\" -Force

        # Copy LICENSE and README if present
        if (Test-Path "$moduleSrc\LICENSE")   { Copy-Item "$moduleSrc\LICENSE"   "$verDir\" -Force }
        if (Test-Path "$moduleSrc\README.md") { Copy-Item "$moduleSrc\README.md" "$verDir\" -Force }

        Write-OK "Installed to $verDir"
    }

    # Also update the profile hint
    $profilePath = $PROFILE.CurrentUserAllHosts
    if ($profilePath -and (Test-Path $profilePath)) {
        $profileContent = Get-Content $profilePath -Raw
        if ($profileContent -notmatch "TouchVault") {
            Write-Host "     TIP: Add 'Import-Module TouchVault' to your PowerShell profile:" -ForegroundColor Gray
            Write-Host "          $profilePath" -ForegroundColor Gray
        }
    } else {
        Write-Host "     TIP: Add 'Import-Module TouchVault' to your PowerShell profile for auto-loading." -ForegroundColor Gray
    }
}

# ---------------------------------------------------------------------------
# Step 6: Verify
# ---------------------------------------------------------------------------
Write-Step "6/6" "Verification"

try {
    Import-Module "$PSScriptRoot\TouchVault.psd1" -Force -ErrorAction Stop
    Write-OK "Module imported successfully"

    $config = Get-VaultConfig
    Write-OK "Database: $($config.DatabasePath)"
    Write-OK "CLI:      $($config.CliPath)"
    Write-OK "Cache:    $($config.CacheTTLHours)h TTL"

    Write-Host ""
    Write-Host "  Setup Complete!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Quick Start:" -ForegroundColor White
    Write-Host "    Import-Module TouchVault" -ForegroundColor Gray
    Write-Host '    $creds = Get-VaultEntry "MyApp"' -ForegroundColor Gray
    Write-Host '    $creds.UserName' -ForegroundColor Gray
    Write-Host '    $creds.Password' -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Run 'Test-VaultPrerequisites' to check system status." -ForegroundColor Gray
    Write-Host ""
} catch {
    Write-Fail "Module import failed: $_"
    Write-Host "     Check errors above and re-run." -ForegroundColor Gray
    exit 1
}
