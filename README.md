# YubiVault

**YubiKey-backed KeePass credential management for GitHub Copilot and PowerShell automation.**

YubiVault secures your API keys, passwords, and secrets in a KeePass database protected by your YubiKey. A 3-tier caching system minimizes YubiKey touches while keeping credentials hardware-protected. Built for GitHub Copilot and automation workflows where secrets should never exist in plaintext config files.

> **Free for personal use.** Commercial/professional use: [$5+ (pay what you think is fair)](https://buymeacoffee.com/ntsh/e/349997). One-time purchase, all v1.x updates included.
>
> [Buy a License](https://buymeacoffee.com/ntsh/e/349997) | [Report an Issue](https://github.com/D13tr1ch/YubiVault/issues)

---

## How It Works

```
Script calls Get-VaultEntry
        |
        v
  [Tier 1] In-memory cache -----> instant return
        |  (miss)
        v
  [Tier 2] DPAPI disk cache ----> instant return (survives restarts, 8h TTL)
        |  (miss)
        v
  [Tier 3] KeePassXC CLI -------> YubiKey popup appears
        |                          Touch key = authorize
        v                          Deny = cancel + reason
     Result cached to Tier 1 + 2
```

**Security layers:**
- **KeePass database** -- AES-256 encrypted `.kdbx` file
- **Master password** -- DPAPI-encrypted, tied to your Windows login (no typing)
- **YubiKey HMAC-SHA1** -- Physical touch required, hardware-bound challenge-response
- **DPAPI disk cache** -- Encrypted per-user, inaccessible to other accounts

---

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| Windows | 10+ | DPAPI + WinForms required |
| PowerShell | 5.1+ | Ships with Windows |
| [KeePassXC](https://keepassxc.org/download/) | 2.6+ | Provides `keepassxc-cli.exe` |
| [YubiKey](https://www.yubico.com/) | Any with HMAC-SHA1 | Most YubiKey models |
| [YubiKey Manager](https://www.yubico.com/support/download/yubikey-manager/) | Optional | For slot configuration |

---

## Installation

### Quick Setup

```powershell
# Clone or download YubiVault, then run the setup wizard:
.\Install-YubiVault.ps1
```

The wizard will:
1. Check/install KeePassXC
2. Detect your YubiKey and configure Slot 2
3. Locate or create a KeePass database
4. Save your master password (DPAPI-encrypted)
5. Install the module to your PowerShell module path
6. Verify everything works

### Manual Setup

```powershell
# 1. Copy module to your PowerShell modules directory
$dest = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\YubiVault\1.0.0"
New-Item -Path $dest -ItemType Directory -Force
Copy-Item YubiVault.psd1, YubiVault.psm1 $dest

# 2. Import and configure
Import-Module YubiVault
Set-VaultConfig -DatabasePath "C:\path\to\your\database.kdbx"
Save-VaultMasterPassword

# 3. Verify
Test-VaultPrerequisites
```

### YubiKey Slot Configuration

YubiVault uses **Slot 2** for HMAC-SHA1 challenge-response (Slot 1 is typically for static passwords).

```powershell
# Using YubiKey Manager CLI
ykman otp chalresp --touch --generate 2
```

Then in KeePassXC: **Database > Database Settings > Security > Add Additional Protection > Add Challenge-Response > YubiKey Slot 2**.

---

## Usage

### Basic Credential Retrieval

```powershell
Import-Module YubiVault

# Get all fields from a KeePass entry
$creds = Get-VaultEntry "My API Service"
$creds.UserName      # API key / client ID
$creds.Password      # API secret / password
$creds.URL           # Service endpoint
$creds.Notes         # Additional metadata

# Get a single field
$secret = Get-VaultSecret "My API Service" -Field Password
```

### Integration with Automation Scripts

```powershell
# Initialize-MyApp.ps1
Import-Module YubiVault

# Non-secret config (safe to commit)
$config = Get-Content '~\.myapp\config.json' -Raw | ConvertFrom-Json

# Secrets from KeePass (cached, YubiKey touch only on first call)
$creds = Get-VaultEntry "MyApp Credentials"

# Build config object
$appConfig = [PSCustomObject]@{
    baseUrl      = $config.baseUrl
    tenantId     = $config.tenantId
    clientId     = $creds.UserName
    clientSecret = $creds.Password
}
```

### Using with GitHub Copilot

When Copilot generates scripts that need credentials:

```powershell
# Instead of hardcoded secrets:
#   $apiKey = "sk-abc123..."        # NEVER DO THIS

# Use YubiVault:
Import-Module YubiVault
$apiKey = Get-VaultSecret "OpenAI API" -Field Password
```

Copilot will see `Get-VaultEntry` and `Get-VaultSecret` in your codebase and learn to use them automatically.

### Cache Management

```powershell
# Check current config and cache status
Test-VaultPrerequisites

# Force refresh a specific entry (requires YubiKey touch)
Update-VaultEntry "My API Service"

# Clear all caches (memory + disk)
Clear-VaultCache
```

### Scaffold a New App Integration

```powershell
Initialize-VaultApp -AppName "Terraform" -KeePassEntry "TF Cloud Token" `
    -Properties @{
        organization = "my-org"
        workspace    = "production"
    }
# Creates: ~\.terraform\config.json + Initialize-Terraform.ps1
```

---

## YubiKey Authorization Popup

When a YubiKey touch is needed, a topmost popup appears:

```
+--------------------------------------------+
|       Touch YubiKey to Authorize           |
+--------------------------------------------+
| Request Details                            |
| Entry:   Omada Client V2                   |
| Caller:  verify-final.ps1                  |
| Time:    2025-01-15 14:30:22               |
+--------------------------------------------+
|  Waiting for YubiKey touch...       [Deny] |
+--------------------------------------------+
```

- **Touch your YubiKey** = authorized (popup auto-closes)
- **Click Deny** = prompts for a reason, then cancels the operation

---

## Functions Reference

| Function | Description |
|----------|-------------|
| `Get-VaultEntry` | Retrieve all fields from a KeePass entry (3-tier cache) |
| `Get-VaultSecret` | Retrieve a single field (Password, UserName, URL, Notes) |
| `Save-VaultMasterPassword` | Store master password with DPAPI encryption (one-time) |
| `Get-VaultMasterPassword` | Retrieve the stored master password |
| `Set-VaultConfig` | Set database path, CLI path, or cache TTL |
| `Get-VaultConfig` | View current configuration |
| `Clear-VaultCache` | Clear in-memory and disk caches |
| `Update-VaultEntry` | Force-refresh an entry (bypasses cache) |
| `Initialize-VaultApp` | Scaffold config + initializer for a new app |
| `Format-Masked` | Mask a secret for safe display (`"abcd*** [32ch]"`) |
| `Test-VaultPrerequisites` | Check system readiness (CLI, database, YubiKey, cache) |

### Backward-Compatible Aliases

If you have existing scripts using the old function names, they still work:

| Old Name | New Name |
|----------|----------|
| `Get-KeePassEntry` | `Get-VaultEntry` |
| `Get-KeePassSecret` | `Get-VaultSecret` |
| `Clear-KeePassCache` | `Clear-VaultCache` |
| `Save-KeePassMasterPassword` | `Save-VaultMasterPassword` |
| `Refresh-KeePassEntry` | `Update-VaultEntry` |

---

## Architecture

```
YubiVault/
  YubiVault.psd1              Module manifest
  YubiVault.psm1              All functions (single file for simplicity)
  Install-YubiVault.ps1       Setup wizard
  README.md                   This file
  LICENSE                     Dual license (personal free / commercial $5+)
  .copilot-instructions.md    GitHub Copilot integration guide
  examples/
    Initialize-Omada.ps1      Example: TP-Link Omada integration
    Initialize-JumpCloud.ps1  Example: JumpCloud integration

User files (created by setup):
  ~/.keepass_cred              DPAPI-encrypted master password
  ~/.keepass_session/          DPAPI-encrypted credential cache
    *.dat                      One file per cached entry (8h TTL)
  ~/.keepass/Vault.kdbx        KeePass database (if created by wizard)
```

---

## Security Model

| Threat | Mitigation |
|--------|------------|
| Secrets in source control | Secrets only in KeePass DB; config files hold non-secret values |
| Stolen config files | No credentials in config files, only URLs and IDs |
| Stolen disk cache | DPAPI encryption -- only the Windows user who created it can decrypt |
| Stolen master password file | DPAPI encryption -- tied to Windows DPKG key, hardware-specific |
| Unauthorized CLI access | YubiKey physical touch required for every new cache-miss |
| Rogue script access | Popup shows entry name, calling script, and timestamp |
| Process hijacking | CLI runs in isolated runspace; master password piped via stdin |
| Cache persistence | 8-hour TTL with automatic expiration; `Clear-VaultCache` for immediate wipe |

---

## License

**YubiVault** uses a [dual license](LICENSE):

| Use Case | License | Cost |
|----------|---------|------|
| Personal, educational, non-commercial | Free License | $0 |
| Commercial, professional, freelance, business | [Commercial License](https://buymeacoffee.com/ntsh/e/349997) | $5+ per user (pay what you think is fair) |

Copyright (c) 2025-2026 TriHarmonic Solutions, a division of Beacon And Bridge LLC. All rights reserved.

One-time purchase. Covers all v1.x updates. No subscription.

**Dependency notice:** YubiVault calls [KeePassXC](https://keepassxc.org/) as an external CLI tool. KeePassXC is licensed under [GPL-2.0/GPL-3.0](https://github.com/keepassxreboot/keepassxc/blob/develop/LICENSE). YubiVault does not bundle, modify, or redistribute KeePassXC. Users must install KeePassXC independently.


---

## Contributing

Contributions welcome! By submitting a PR, you agree that your contribution is licensed under the same dual-license terms.

1. Fork & clone
2. Make changes to `YubiVault.psm1`
3. Test with `Test-VaultPrerequisites` and `Get-VaultEntry`
4. Submit a PR

---

## Troubleshooting

**"operation would block"** -- Close the KeePassXC GUI. It holds the YubiKey slot and blocks CLI access.

**"No saved master password"** -- Run `Save-VaultMasterPassword` to store your master password.

**YubiKey not detected** -- Ensure the key is plugged in and not in use by another application.

**Cache not working** -- Check `~\.keepass_session\` for `.dat` files. Run `Clear-VaultCache` and retry.

**Module not found after install** -- Verify the module path: `$env:PSModulePath -split ';'`
