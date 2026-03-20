# Initialize-Omada.ps1 - Example: TP-Link Omada Cloud API integration
# Usage: . "path\to\Initialize-Omada.ps1"

Import-Module TouchVault -ErrorAction Stop

# Non-secret config (baseUrl, omadacId - safe to commit)
$_omadaNonSecret = Get-Content "$env:USERPROFILE\.omada\omada-config.json" -Raw | ConvertFrom-Json

# Secrets from KeePass (YubiKey touch, cached per session)
$_omadaCreds = Get-VaultEntry "Omada Client V2"

# Build config objects - backward-compatible with existing scripts
$cfg = [PSCustomObject]@{
    baseUrl      = $_omadaNonSecret.baseUrl
    omadacId     = $_omadaNonSecret.omadacId
    clientId     = $_omadaCreds.UserName
    clientSecret = $_omadaCreds.Password
}
$config = $cfg
