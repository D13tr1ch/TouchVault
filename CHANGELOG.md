# Changelog

All notable changes to YubiVault will be documented in this file.

## [1.0.0] - 2026-03-20

### Added
- 3-tier credential cache: in-memory, DPAPI disk (8h TTL), KeePassXC CLI + YubiKey
- Topmost WinForms popup with touch-to-authorize UX
- Deny button with reason prompt for audit trail
- DPAPI-encrypted master password storage (tied to Windows login)
- Auto-detection of KeePassXC CLI and database paths
- Backward-compatible aliases (`Get-KeePassEntry`, `Get-KeePassSecret`, etc.)
- `Test-VaultPrerequisites` system readiness check
- `Initialize-VaultApp` scaffold generator for new integrations
- `Format-Masked` utility for safe secret display
- Setup wizard (`Install-YubiVault.ps1`) with 6-step guided configuration
- GitHub Copilot integration guide (`.copilot-instructions.md`)
- Example integrations for TP-Link Omada and JumpCloud
