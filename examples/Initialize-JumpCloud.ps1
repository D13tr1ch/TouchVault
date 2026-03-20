# Initialize-JumpCloud.ps1 - Example: JumpCloud Admin API integration
# Usage: . "path\to\Initialize-JumpCloud.ps1"

Import-Module TouchVault -ErrorAction Stop

# Non-secret config (orgId, baseUrl - safe to commit)
$_jcNonSecret = Get-Content "$env:USERPROFILE\.jumpcloud\config.json" -Raw | ConvertFrom-Json

# Secrets from KeePass (YubiKey touch, cached per session)
$_jcCreds = Get-VaultEntry "JumpCloud Admin"

# Build config object
$jcConfig = [PSCustomObject]@{
    baseUrl      = $_jcNonSecret.baseUrl
    orgId        = $_jcNonSecret.orgId
    clientId     = $_jcCreds.UserName
    clientSecret = $_jcCreds.Password
}
