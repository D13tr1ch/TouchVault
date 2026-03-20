#Requires -Version 5.1

# ============================================================================
# YubiVault — YubiKey-backed KeePass credential management for automation
# ============================================================================
# 3-tier cache: in-memory → DPAPI disk cache → KeePassXC CLI + YubiKey
# ============================================================================

# ---------------------------------------------------------------------------
# Module-scoped state
# ---------------------------------------------------------------------------
$script:VaultCache       = @{}
$script:MasterPwFile     = "$env:USERPROFILE\.keepass_cred"
$script:DiskCacheDir     = "$env:USERPROFILE\.keepass_session"
$script:CacheTTLHours    = 8
$script:DefaultDatabase  = $null   # Set via Set-VaultConfig or auto-detected
$script:DefaultCli       = $null   # Set via Set-VaultConfig or auto-detected

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
function Set-VaultConfig {
    <#
    .SYNOPSIS
        Configures YubiVault defaults (database path, CLI path, cache TTL).
    .PARAMETER DatabasePath
        Path to the KeePass .kdbx file.
    .PARAMETER CliPath
        Path to keepassxc-cli.exe.
    .PARAMETER CacheTTLHours
        How many hours cached entries remain valid (default 8).
    .EXAMPLE
        Set-VaultConfig -DatabasePath "C:\Secrets\Vault.kdbx" -CacheTTLHours 4
    #>
    [CmdletBinding()]
    param(
        [string]$DatabasePath,
        [string]$CliPath,
        [int]$CacheTTLHours
    )
    if ($DatabasePath)  { $script:DefaultDatabase = $DatabasePath }
    if ($CliPath)       { $script:DefaultCli      = $CliPath }
    if ($CacheTTLHours) { $script:CacheTTLHours   = $CacheTTLHours }
}

function Get-VaultConfig {
    <#
    .SYNOPSIS
        Returns the current YubiVault configuration.
    #>
    [PSCustomObject]@{
        DatabasePath  = Resolve-DatabasePath
        CliPath       = Resolve-CliPath
        CacheTTLHours = $script:CacheTTLHours
        MasterPwFile  = $script:MasterPwFile
        DiskCacheDir  = $script:DiskCacheDir
    }
}

# ---------------------------------------------------------------------------
# Path resolution (auto-detect if not explicitly set)
# ---------------------------------------------------------------------------
function Resolve-DatabasePath {
    if ($script:DefaultDatabase) { return $script:DefaultDatabase }

    # Search common locations
    $candidates = @(
        "$env:USERPROFILE\.keepass\Vault.kdbx",
        "$env:USERPROFILE\Passwords.kdbx",
        "C:\NTSH\Passwords.kdbx"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { $script:DefaultDatabase = $p; return $p }
    }
    throw "No KeePass database found. Run Set-VaultConfig -DatabasePath 'path\to\file.kdbx'"
}

function Resolve-CliPath {
    if ($script:DefaultCli) { return $script:DefaultCli }

    $candidates = @(
        "C:\Program Files\KeePassXC\keepassxc-cli.exe",
        "${env:ProgramFiles}\KeePassXC\keepassxc-cli.exe",
        "${env:LOCALAPPDATA}\KeePassXC\keepassxc-cli.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { $script:DefaultCli = $p; return $p }
    }

    # Try PATH
    $cmd = Get-Command keepassxc-cli -ErrorAction SilentlyContinue
    if ($cmd) { $script:DefaultCli = $cmd.Source; return $cmd.Source }

    throw "KeePassXC CLI not found. Install KeePassXC or run Set-VaultConfig -CliPath 'path\to\keepassxc-cli.exe'"
}

# ---------------------------------------------------------------------------
# Master Password (DPAPI-encrypted)
# ---------------------------------------------------------------------------
function Save-VaultMasterPassword {
    <#
    .SYNOPSIS
        Saves the KeePass master password using Windows DPAPI encryption.
        Only the current Windows user can decrypt it. Run once per machine.
    .EXAMPLE
        Save-VaultMasterPassword
    #>
    [CmdletBinding()]
    param()
    $secure = Read-Host "Enter KeePass master password" -AsSecureString
    $secure | ConvertFrom-SecureString | Set-Content $script:MasterPwFile -Force
    Write-Host "Master password saved (DPAPI-encrypted). Only your Windows account can decrypt it." -ForegroundColor Green
}

function Get-VaultMasterPassword {
    <#
    .SYNOPSIS
        Retrieves the DPAPI-encrypted master password (internal use).
    #>
    [CmdletBinding()]
    param()
    if (-not (Test-Path $script:MasterPwFile)) {
        throw "No saved master password. Run Save-VaultMasterPassword first."
    }
    $secure = Get-Content $script:MasterPwFile | ConvertTo-SecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

# ---------------------------------------------------------------------------
# Disk Cache (DPAPI-encrypted, TTL-based)
# ---------------------------------------------------------------------------
function Get-DiskCachePath {
    param([string]$EntryName)
    if (-not (Test-Path $script:DiskCacheDir)) {
        New-Item -Path $script:DiskCacheDir -ItemType Directory -Force | Out-Null
    }
    $safeName = $EntryName -replace '[^\w\-]', '_'
    Join-Path $script:DiskCacheDir "$safeName.dat"
}

function Get-DiskCachedEntry {
    param([string]$EntryName)
    $path = Get-DiskCachePath $EntryName
    if (-not (Test-Path $path)) { return $null }

    $fileAge = (Get-Date) - (Get-Item $path).LastWriteTime
    if ($fileAge.TotalHours -gt $script:CacheTTLHours) {
        Remove-Item $path -Force
        return $null
    }

    try {
        $encrypted = Get-Content $path -Raw
        $secure = $encrypted | ConvertTo-SecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            $json = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
        $obj = $json | ConvertFrom-Json
        $entry = @{}
        $obj.PSObject.Properties | ForEach-Object { $entry[$_.Name] = $_.Value }
        return $entry
    } catch {
        Remove-Item $path -Force -ErrorAction SilentlyContinue
        return $null
    }
}

function Save-DiskCachedEntry {
    param([string]$EntryName, [hashtable]$Entry)
    $path = Get-DiskCachePath $EntryName
    $json = $Entry | ConvertTo-Json -Compress
    $secure = ConvertTo-SecureString $json -AsPlainText -Force
    $secure | ConvertFrom-SecureString | Set-Content $path -Force
}

# ---------------------------------------------------------------------------
# YubiKey Authorization Popup (WinForms)
# ---------------------------------------------------------------------------
function Show-YubiKeyPrompt {
    <#
    .SYNOPSIS
        Displays a topmost popup while waiting for YubiKey touch.
        Touch = authorize. Deny button = cancel + reason prompt.
        Returns CLI output or throws on denial.
    #>
    param(
        [string]$EntryName,
        [string]$CallerInfo,
        [string]$MasterPassword,
        [string]$CliPath,
        [string]$DatabasePath,
        [int]$YubiKeySlot = 2
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "YubiKey Authorization"
    $form.Size = New-Object System.Drawing.Size(440, 260)
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)

    $touchLabel = New-Object System.Windows.Forms.Label
    $touchLabel.Text = "Touch YubiKey to Authorize"
    $touchLabel.Font = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
    $touchLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 200, 0)
    $touchLabel.AutoSize = $false
    $touchLabel.Size = New-Object System.Drawing.Size(400, 35)
    $touchLabel.Location = New-Object System.Drawing.Point(15, 10)
    $touchLabel.TextAlign = "MiddleCenter"
    $form.Controls.Add($touchLabel)

    $detailBox = New-Object System.Windows.Forms.GroupBox
    $detailBox.Text = "Request Details"
    $detailBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $detailBox.ForeColor = [System.Drawing.Color]::LightGray
    $detailBox.Size = New-Object System.Drawing.Size(396, 110)
    $detailBox.Location = New-Object System.Drawing.Point(15, 50)
    $form.Controls.Add($detailBox)

    $entryLabel = New-Object System.Windows.Forms.Label
    $entryLabel.Text = "Entry:`t$EntryName"
    $entryLabel.Font = New-Object System.Drawing.Font("Consolas", 10)
    $entryLabel.ForeColor = [System.Drawing.Color]::White
    $entryLabel.AutoSize = $false
    $entryLabel.Size = New-Object System.Drawing.Size(370, 22)
    $entryLabel.Location = New-Object System.Drawing.Point(10, 25)
    $detailBox.Controls.Add($entryLabel)

    $callerLabel = New-Object System.Windows.Forms.Label
    $callerLabel.Text = "Caller:`t$CallerInfo"
    $callerLabel.Font = New-Object System.Drawing.Font("Consolas", 10)
    $callerLabel.ForeColor = [System.Drawing.Color]::White
    $callerLabel.AutoSize = $false
    $callerLabel.Size = New-Object System.Drawing.Size(370, 22)
    $callerLabel.Location = New-Object System.Drawing.Point(10, 50)
    $detailBox.Controls.Add($callerLabel)

    $timeLabel = New-Object System.Windows.Forms.Label
    $timeLabel.Text = "Time:`t$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $timeLabel.Font = New-Object System.Drawing.Font("Consolas", 10)
    $timeLabel.ForeColor = [System.Drawing.Color]::White
    $timeLabel.AutoSize = $false
    $timeLabel.Size = New-Object System.Drawing.Size(370, 22)
    $timeLabel.Location = New-Object System.Drawing.Point(10, 75)
    $detailBox.Controls.Add($timeLabel)

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = "Waiting for YubiKey touch..."
    $statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $statusLabel.ForeColor = [System.Drawing.Color]::Gray
    $statusLabel.AutoSize = $false
    $statusLabel.Size = New-Object System.Drawing.Size(290, 22)
    $statusLabel.Location = New-Object System.Drawing.Point(15, 170)
    $statusLabel.TextAlign = "MiddleLeft"
    $form.Controls.Add($statusLabel)

    $denyBtn = New-Object System.Windows.Forms.Button
    $denyBtn.Text = "Deny"
    $denyBtn.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $denyBtn.Size = New-Object System.Drawing.Size(80, 30)
    $denyBtn.Location = New-Object System.Drawing.Point(331, 168)
    $denyBtn.BackColor = [System.Drawing.Color]::FromArgb(140, 30, 30)
    $denyBtn.ForeColor = [System.Drawing.Color]::White
    $denyBtn.FlatStyle = "Flat"
    $form.Controls.Add($denyBtn)

    $script:_yukDenied = $false
    $denyBtn.Add_Click({ $script:_yukDenied = $true; $form.Close() })

    # Start KeePassXC CLI in background runspace
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript({
        param($pw, $cli, $db, $entry, $slot)
        $r = $pw | & $cli show $db "$entry" --all --show-protected --yubikey $slot 2>&1
        [PSCustomObject]@{ Output = $r; ExitCode = $LASTEXITCODE }
    }).AddArgument($MasterPassword).AddArgument($CliPath).AddArgument($DatabasePath).AddArgument($EntryName).AddArgument($YubiKeySlot)
    $asyncResult = $ps.BeginInvoke()

    # Poll timer: auto-close when CLI completes (touch detected)
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 250
    $timer.Add_Tick({
        if ($asyncResult.IsCompleted) { $timer.Stop(); $form.Close() }
    })
    $timer.Start()

    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()
    $timer.Dispose()

    # Handle denial
    if ($script:_yukDenied) {
        $ps.Stop(); $ps.Dispose(); $runspace.Close()

        $reasonForm = New-Object System.Windows.Forms.Form
        $reasonForm.Text = "Authorization Denied"
        $reasonForm.Size = New-Object System.Drawing.Size(400, 180)
        $reasonForm.StartPosition = "CenterScreen"
        $reasonForm.TopMost = $true
        $reasonForm.FormBorderStyle = "FixedDialog"
        $reasonForm.MaximizeBox = $false
        $reasonForm.MinimizeBox = $false
        $reasonForm.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)

        $rLabel = New-Object System.Windows.Forms.Label
        $rLabel.Text = "Why was this request denied?"
        $rLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $rLabel.ForeColor = [System.Drawing.Color]::LightGray
        $rLabel.AutoSize = $true
        $rLabel.Location = New-Object System.Drawing.Point(15, 15)
        $reasonForm.Controls.Add($rLabel)

        $rBox = New-Object System.Windows.Forms.TextBox
        $rBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $rBox.Size = New-Object System.Drawing.Size(355, 25)
        $rBox.Location = New-Object System.Drawing.Point(15, 45)
        $rBox.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
        $rBox.ForeColor = [System.Drawing.Color]::White
        $reasonForm.Controls.Add($rBox)

        $rEntryLabel = New-Object System.Windows.Forms.Label
        $rEntryLabel.Text = "Entry: $EntryName  |  Caller: $CallerInfo"
        $rEntryLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
        $rEntryLabel.ForeColor = [System.Drawing.Color]::Gray
        $rEntryLabel.AutoSize = $true
        $rEntryLabel.Location = New-Object System.Drawing.Point(15, 78)
        $reasonForm.Controls.Add($rEntryLabel)

        $submitBtn = New-Object System.Windows.Forms.Button
        $submitBtn.Text = "Submit"
        $submitBtn.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $submitBtn.Size = New-Object System.Drawing.Size(80, 30)
        $submitBtn.Location = New-Object System.Drawing.Point(290, 105)
        $submitBtn.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
        $submitBtn.ForeColor = [System.Drawing.Color]::White
        $submitBtn.FlatStyle = "Flat"
        $submitBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $reasonForm.Controls.Add($submitBtn)
        $reasonForm.AcceptButton = $submitBtn

        $reasonForm.Add_Shown({ $rBox.Focus() })
        [void]$reasonForm.ShowDialog()
        $denyReason = $rBox.Text
        $reasonForm.Dispose()

        $msg = "YubiKey authorization denied for '$EntryName' by $CallerInfo"
        if ($denyReason) { $msg += " - Reason: $denyReason" }
        Write-Warning $msg
        throw $msg
    }

    # Collect result (touch = authorized)
    $cliResult = $ps.EndInvoke($asyncResult)
    $ps.Dispose()
    $runspace.Close()

    return $cliResult
}

# ---------------------------------------------------------------------------
# Core Public Functions
# ---------------------------------------------------------------------------
function Get-VaultEntry {
    <#
    .SYNOPSIS
        Retrieves all fields from a KeePass entry with 3-tier caching.
        Tier 1: In-memory (instant, same session)
        Tier 2: DPAPI disk cache (survives restarts, 8-hour TTL)
        Tier 3: KeePassXC CLI + YubiKey (physical touch required)
    .PARAMETER EntryName
        The title of the KeePass entry to retrieve.
    .PARAMETER DatabasePath
        Path to the .kdbx file. Uses auto-detected default if omitted.
    .PARAMETER ForceRefresh
        Bypasses all caches and fetches fresh from KeePass (requires YubiKey touch).
    .PARAMETER YubiKeySlot
        YubiKey HMAC-SHA1 slot number (default: 2).
    .EXAMPLE
        $creds = Get-VaultEntry "Omada Client V2"
        $creds.UserName
        $creds.Password
    .EXAMPLE
        $creds = Get-VaultEntry "AWS Prod" -ForceRefresh
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$EntryName,

        [string]$DatabasePath,

        [switch]$ForceRefresh,

        [int]$YubiKeySlot = 2
    )

    if (-not $DatabasePath) { $DatabasePath = Resolve-DatabasePath }
    $cli = Resolve-CliPath

    # Tier 1: in-memory
    if (-not $ForceRefresh -and $script:VaultCache.ContainsKey($EntryName)) {
        return $script:VaultCache[$EntryName]
    }

    # Tier 2: DPAPI disk cache
    if (-not $ForceRefresh) {
        $diskEntry = Get-DiskCachedEntry $EntryName
        if ($diskEntry) {
            $script:VaultCache[$EntryName] = $diskEntry
            return $diskEntry
        }
    }

    # Tier 3: KeePassXC CLI + YubiKey
    if (-not (Test-Path $cli))          { throw "KeePassXC CLI not found at $cli" }
    if (-not (Test-Path $DatabasePath)) { throw "KeePass database not found at $DatabasePath" }

    $masterPw = Get-VaultMasterPassword

    # Detect calling script for popup context
    $callerInfo = "Unknown"
    $stack = Get-PSCallStack
    foreach ($frame in $stack) {
        if ($frame.ScriptName -and $frame.ScriptName -ne $MyInvocation.ScriptName) {
            $callerInfo = [System.IO.Path]::GetFileName($frame.ScriptName)
            break
        }
    }

    $cliResult = Show-YubiKeyPrompt `
        -EntryName $EntryName `
        -CallerInfo $callerInfo `
        -MasterPassword $masterPw `
        -CliPath $cli `
        -DatabasePath $DatabasePath `
        -YubiKeySlot $YubiKeySlot

    $result   = $cliResult.Output
    $exitCode = $cliResult.ExitCode

    if ($exitCode -ne 0) { throw "KeePassXC CLI error: $result" }

    $entry = @{}
    foreach ($line in $result) {
        if ($line -match "^(\w+):\s*(.*)$") {
            $entry[$Matches[1]] = $Matches[2].Trim()
        }
    }

    # Populate both caches
    $script:VaultCache[$EntryName] = $entry
    Save-DiskCachedEntry $EntryName $entry

    return $entry
}

function Get-VaultSecret {
    <#
    .SYNOPSIS
        Retrieves a single field from a KeePass entry. Convenience wrapper around Get-VaultEntry.
    .PARAMETER EntryName
        The title of the KeePass entry.
    .PARAMETER Field
        Which field to return (Password, UserName, URL, Notes). Default: Password.
    .EXAMPLE
        $apiKey = Get-VaultSecret "AWS Prod" -Field Password
        $user   = Get-VaultSecret "AWS Prod" -Field UserName
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$EntryName,

        [ValidateSet("Password", "UserName", "URL", "Notes")]
        [string]$Field = "Password",

        [string]$DatabasePath,

        [int]$YubiKeySlot = 2
    )

    $params = @{ EntryName = $EntryName; YubiKeySlot = $YubiKeySlot }
    if ($DatabasePath) { $params.DatabasePath = $DatabasePath }

    $entry = Get-VaultEntry @params
    return $entry[$Field]
}

function Clear-VaultCache {
    <#
    .SYNOPSIS
        Clears all cached credentials (in-memory and DPAPI disk cache).
        The next call to Get-VaultEntry will require a YubiKey touch.
    #>
    [CmdletBinding()]
    param()
    $script:VaultCache = @{}
    if (Test-Path $script:DiskCacheDir) {
        Remove-Item "$script:DiskCacheDir\*.dat" -Force -ErrorAction SilentlyContinue
    }
    Write-Host "YubiVault caches cleared (memory + disk)." -ForegroundColor Yellow
}

function Update-VaultEntry {
    <#
    .SYNOPSIS
        Forces a fresh fetch from KeePass, bypassing all caches (requires YubiKey touch).
    .EXAMPLE
        Update-VaultEntry "Omada Client V2"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$EntryName,
        [int]$YubiKeySlot = 2
    )
    Get-VaultEntry -EntryName $EntryName -ForceRefresh -YubiKeySlot $YubiKeySlot
}

function Initialize-VaultApp {
    <#
    .SYNOPSIS
        Creates a config + initializer scaffold for a new application.
        Generates a non-secret config JSON and an Initialize-*.ps1 script.
    .PARAMETER AppName
        Short name for the app (e.g., "Omada", "AWS").
    .PARAMETER KeePassEntry
        Title of the KeePass entry containing the credentials.
    .PARAMETER ConfigDir
        Directory for the non-secret config file. Default: ~\.<AppName>\
    .PARAMETER Properties
        Hashtable of non-secret config values (baseUrl, tenantId, etc.).
    .PARAMETER OutputDir
        Where to write the Initialize-*.ps1 script. Default: module directory.
    .EXAMPLE
        Initialize-VaultApp -AppName "Omada" -KeePassEntry "Omada Client V2" `
            -Properties @{ baseUrl = "https://api.example.com"; omadacId = "abc123" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [Parameter(Mandatory)]
        [string]$KeePassEntry,

        [string]$ConfigDir,

        [hashtable]$Properties = @{},

        [string]$OutputDir = $PSScriptRoot
    )

    if (-not $ConfigDir) { $ConfigDir = "$env:USERPROFILE\.$($AppName.ToLower())" }

    # Create config directory and JSON
    if (-not (Test-Path $ConfigDir)) {
        New-Item -Path $ConfigDir -ItemType Directory -Force | Out-Null
    }

    $configPath = Join-Path $ConfigDir "config.json"
    if ($Properties.Count -gt 0) {
        $Properties | ConvertTo-Json -Depth 3 | Set-Content $configPath -Force
        Write-Host "Config written: $configPath" -ForegroundColor Green
    }

    # Generate initializer script
    $varName = "`$${AppName}Config"
    $initContent = @"
# Initialize-$AppName.ps1 - Dot-source this to get $varName with secrets from KeePass
# Usage: . "$OutputDir\Initialize-$AppName.ps1"

Import-Module YubiVault -ErrorAction Stop

# Non-secret config
`$_nonSecret = Get-Content '$configPath' -Raw | ConvertFrom-Json

# Secrets from KeePass (YubiKey touch, cached per session)
`$_creds = Get-VaultEntry "$KeePassEntry"

# Build config object
$varName = [PSCustomObject]@{
"@

    foreach ($key in $Properties.Keys) {
        $initContent += "`n    $key = `$_nonSecret.$key"
    }
    $initContent += @"

    clientId     = `$_creds.UserName
    clientSecret = `$_creds.Password
}
"@

    $initPath = Join-Path $OutputDir "Initialize-$AppName.ps1"
    $initContent | Set-Content $initPath -Force
    Write-Host "Initializer written: $initPath" -ForegroundColor Green
    Write-Host "Usage: . '$initPath'" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------
function Format-Masked {
    <#
    .SYNOPSIS
        Masks a secret string, showing only a prefix and the character count.
    .EXAMPLE
        $secret | Format-Masked            # "abcd******* [32ch]"
        Format-Masked $secret -ShowChars 2  # "ab********* [32ch]"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$Value,
        [int]$ShowChars = 4
    )
    if ([string]::IsNullOrEmpty($Value)) { return '(empty)' }
    if ($Value.Length -le $ShowChars)     { return '*' * $Value.Length }
    $Value.Substring(0, $ShowChars) + ('*' * ($Value.Length - $ShowChars)) + " [$($Value.Length)ch]"
}

function Test-VaultPrerequisites {
    <#
    .SYNOPSIS
        Checks that all prerequisites are met (KeePassXC, YubiKey, master password).
    .EXAMPLE
        Test-VaultPrerequisites
    #>
    [CmdletBinding()]
    param()

    $results = @()

    # KeePassXC CLI
    try {
        $cli = Resolve-CliPath
        $ver = & $cli --version 2>&1
        $results += [PSCustomObject]@{ Check = "KeePassXC CLI"; Status = "OK"; Detail = "$cli (v$ver)" }
    } catch {
        $results += [PSCustomObject]@{ Check = "KeePassXC CLI"; Status = "FAIL"; Detail = $_.Exception.Message }
    }

    # Database
    try {
        $db = Resolve-DatabasePath
        $results += [PSCustomObject]@{ Check = "KeePass Database"; Status = "OK"; Detail = $db }
    } catch {
        $results += [PSCustomObject]@{ Check = "KeePass Database"; Status = "FAIL"; Detail = $_.Exception.Message }
    }

    # Master password
    if (Test-Path $script:MasterPwFile) {
        $results += [PSCustomObject]@{ Check = "Master Password"; Status = "OK"; Detail = "DPAPI-encrypted at $($script:MasterPwFile)" }
    } else {
        $results += [PSCustomObject]@{ Check = "Master Password"; Status = "FAIL"; Detail = "Not saved. Run Save-VaultMasterPassword" }
    }

    # YubiKey (ykman)
    $ykman = Get-Command ykman -ErrorAction SilentlyContinue
    if (-not $ykman) { $ykman = Get-Command "C:\Program Files\Yubico\YubiKey Manager\ykman.exe" -ErrorAction SilentlyContinue }
    if ($ykman) {
        try {
            $ykInfo = & $ykman.Source list 2>&1
            if ($ykInfo -match "YubiKey") {
                $results += [PSCustomObject]@{ Check = "YubiKey"; Status = "OK"; Detail = ($ykInfo | Select-Object -First 1) }
            } else {
                $results += [PSCustomObject]@{ Check = "YubiKey"; Status = "WARN"; Detail = "ykman found but no YubiKey detected (is it plugged in?)" }
            }
        } catch {
            $results += [PSCustomObject]@{ Check = "YubiKey"; Status = "WARN"; Detail = "ykman found but could not list devices" }
        }
    } else {
        $results += [PSCustomObject]@{ Check = "YubiKey"; Status = "WARN"; Detail = "ykman not found (optional: install YubiKey Manager)" }
    }

    # Disk cache status
    if (Test-Path $script:DiskCacheDir) {
        $cacheFiles = Get-ChildItem "$script:DiskCacheDir\*.dat" -ErrorAction SilentlyContinue
        $results += [PSCustomObject]@{ Check = "Disk Cache"; Status = "OK"; Detail = "$($cacheFiles.Count) cached entries in $($script:DiskCacheDir)" }
    } else {
        $results += [PSCustomObject]@{ Check = "Disk Cache"; Status = "OK"; Detail = "No cache directory yet (will be created on first use)" }
    }

    $results | Format-Table -AutoSize
}

# ---------------------------------------------------------------------------
# Backward-compatible aliases (for existing scripts using Get-KeePassEntry etc.)
# ---------------------------------------------------------------------------
New-Alias -Name Get-KeePassEntry           -Value Get-VaultEntry          -Force
New-Alias -Name Get-KeePassSecret          -Value Get-VaultSecret         -Force
New-Alias -Name Clear-KeePassCache         -Value Clear-VaultCache        -Force
New-Alias -Name Save-KeePassMasterPassword -Value Save-VaultMasterPassword -Force
New-Alias -Name Refresh-KeePassEntry       -Value Update-VaultEntry       -Force

# ---------------------------------------------------------------------------
# Module exports
# ---------------------------------------------------------------------------
Export-ModuleMember -Function @(
    'Set-VaultConfig'
    'Get-VaultConfig'
    'Save-VaultMasterPassword'
    'Get-VaultMasterPassword'
    'Get-VaultEntry'
    'Get-VaultSecret'
    'Clear-VaultCache'
    'Update-VaultEntry'
    'Initialize-VaultApp'
    'Format-Masked'
    'Test-VaultPrerequisites'
) -Alias @(
    'Get-KeePassEntry'
    'Get-KeePassSecret'
    'Clear-KeePassCache'
    'Save-KeePassMasterPassword'
    'Refresh-KeePassEntry'
)
