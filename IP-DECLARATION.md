# Intellectual Property Declaration

## Owner

**TriHarmonic Solutions**
A division of **Beacon And Bridge LLC**

## Declaration

All intellectual property contained in this repository, including but not limited
to source code, documentation, designs, trade secrets, algorithms, architectures,
and associated materials, is the sole and exclusive property of TriHarmonic
Solutions, a division of Beacon And Bridge LLC.

## Covered Works

This declaration covers the following intellectual property:

### YubiVault PowerShell Module (v1.0.0+)

| Asset | Description |
|-------|-------------|
| **YubiVault.psm1** | Core module: 3-tier credential caching engine, DPAPI encryption layer, YubiKey HMAC-SHA1 integration, WinForms authorization popup, disk cache management |
| **YubiVault.psd1** | Module manifest and metadata |
| **Install-YubiVault.ps1** | 6-step setup wizard with auto-detection logic |
| **.copilot-instructions.md** | GitHub Copilot integration rules and patterns |
| **Documentation** | README.md, CHANGELOG.md, and all associated guides |
| **Examples** | Initialize-Omada.ps1, Initialize-JumpCloud.ps1, and any future example integrations |

### Proprietary Algorithms and Designs

- **3-Tier Credential Cache Architecture**: In-memory (session scope) -> DPAPI disk cache (8-hour TTL, survives restarts) -> KeePassXC CLI + YubiKey hardware authentication
- **Touch-to-Authorize Popup System**: Background runspace WinForms topmost window with caller identification, deny-with-reason audit trail, and auto-close on YubiKey touch detection
- **DPAPI Key Wrapping for Portable Backups**: AES-256-CBC encryption with DPAPI-wrapped key material and custom binary format (YVBK01)
- **Auto-Detection Routines**: Database path resolution, CLI path resolution, and YubiKey slot detection logic

## Date of Creation

Initial development commenced: **March 2026**
First public release (v1.0.0): **March 20, 2026**

## Repository

- GitHub: https://github.com/D13tr1ch/YubiVault
- Initial commit: v1.0.0, March 20, 2026

## Copyright Notice

Copyright (c) 2025-2026 TriHarmonic Solutions, a division of Beacon And Bridge LLC.
All rights reserved.

## Licensing

The software is distributed under a dual-license model (see [LICENSE](LICENSE)):
- Free for personal, educational, and non-commercial use
- Commercial use requires a paid license ($5+ per user)

Distribution under these license terms does not constitute a transfer or waiver of
intellectual property rights. All IP rights remain exclusively with TriHarmonic
Solutions / Beacon And Bridge LLC.

## Third-Party Dependencies

YubiVault invokes KeePassXC as an external CLI process. KeePassXC is a separate
open-source project licensed under GPL-2.0/GPL-3.0. YubiVault does not incorporate,
bundle, modify, or create derivative works of KeePassXC. No third-party IP is
claimed.

## Confidentiality

Portions of the implementation that are not publicly distributed (including internal
tooling, deployment scripts, and infrastructure configurations) remain trade secrets
of TriHarmonic Solutions / Beacon And Bridge LLC.
