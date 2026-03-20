@{
    # Module identity
    RootModule        = 'TouchVault.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a3f7c2e1-9b84-4d6f-b5e3-1c8a2f0d7e9b'
    Author            = 'TriHarmonic Solutions'
    CompanyName       = 'Beacon And Bridge Solutions LLC'
    Copyright         = '(c) 2025-2026 TriHarmonic Solutions, a division of Beacon And Bridge Solutions LLC. Dual License: Free personal / Commercial $5+.'
    Description       = 'YubiKey-backed KeePass credential management for GitHub Copilot and PowerShell automation. Provides 3-tier caching (in-memory, DPAPI disk, CLI+YubiKey) with a topmost authorization popup.'

    # Requirements
    PowerShellVersion = '5.1'
    # CLRVersion      = '4.0'

    # Exports
    FunctionsToExport = @(
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
    )
    AliasesToExport   = @(
        'Get-KeePassEntry'
        'Get-KeePassSecret'
        'Clear-KeePassCache'
        'Save-KeePassMasterPassword'
        'Refresh-KeePassEntry'
    )
    CmdletsToExport   = @()
    VariablesToExport  = @()

    # Metadata for gallery / discovery
    PrivateData = @{
        PSData = @{
            Tags         = @('KeePass', 'YubiKey', 'Secrets', 'DPAPI', 'Credentials', 'Security', 'Copilot', 'Automation')
            LicenseUri   = 'https://github.com/D13tr1ch/TouchVault/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/D13tr1ch/TouchVault'
            # IconUri    = ''
            ReleaseNotes = @'
v1.0.0 - Initial release
- 3-tier credential cache (in-memory, DPAPI disk, KeePassXC CLI + YubiKey)
- Topmost WinForms popup with touch-to-authorize UX
- Deny button with reason prompt and audit trail
- DPAPI-encrypted master password storage
- Backward-compatible aliases for existing scripts
- Setup wizard (Install-TouchVault.ps1)
- GitHub Copilot integration guide
'@
        }
    }
}
