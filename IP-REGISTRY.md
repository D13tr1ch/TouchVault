# Intellectual Property Registry

## Entity Information

| Field | Value |
|-------|-------|
| **IP Owner** | TriHarmonic Solutions |
| **Parent Entity** | Beacon And Bridge LLC |
| **Relationship** | TriHarmonic Solutions is a division of Beacon And Bridge LLC |
| **Registry Date** | March 20, 2026 |
| **Registry Version** | 1.0 |

---

## IP Asset Inventory

### Asset #001: YubiVault

| Field | Detail |
|-------|--------|
| **Asset Name** | YubiVault |
| **Asset Type** | Software (PowerShell Module) |
| **Classification** | Proprietary with dual-license distribution |
| **Status** | Active, v1.0.0 released |
| **Date Created** | March 2026 |
| **Date First Published** | March 20, 2026 |
| **Repository** | https://github.com/D13tr1ch/YubiVault |
| **Language/Platform** | PowerShell 5.1+, Windows 10+ |
| **License Model** | Dual: Free personal / Commercial $5+ per user |
| **Purchase URL** | https://buymeacoffee.com/ntsh/e/349997 |
| **GUID** | a3f7c2e1-9b84-4d6f-b5e3-1c8a2f0d7e9b |

**Description**: YubiKey-backed KeePass credential management module for GitHub
Copilot and PowerShell automation. Features 3-tier caching (in-memory, DPAPI disk,
CLI+YubiKey), a topmost WinForms authorization popup, and DPAPI-encrypted master
password storage.

**Key Innovations**:
1. 3-tier credential caching architecture with automatic TTL expiration
2. Touch-to-authorize popup with caller identification and deny-with-reason audit
3. DPAPI disk cache enabling credential persistence across PowerShell sessions
4. Seamless GitHub Copilot integration via .copilot-instructions.md convention
5. DPAPI key wrapping for portable encrypted backups (YVBK01 format)

**Components**:

| File | Lines | Purpose |
|------|-------|---------|
| YubiVault.psm1 | ~700 | Core module: 11 public functions, 6 internal functions, 5 aliases |
| YubiVault.psd1 | ~60 | Module manifest |
| Install-YubiVault.ps1 | ~300 | 6-step setup wizard |
| .copilot-instructions.md | ~70 | AI assistant integration rules |
| README.md | ~310 | Technical documentation |
| LICENSE | ~70 | Dual license terms |
| CHANGELOG.md | ~20 | Release history |
| examples/Initialize-Omada.ps1 | ~20 | TP-Link Omada integration example |
| examples/Initialize-JumpCloud.ps1 | ~20 | JumpCloud integration example |

---

### Asset #002: YVBK01 Encrypted Backup Format

| Field | Detail |
|-------|--------|
| **Asset Name** | YVBK01 Encrypted Backup Format |
| **Asset Type** | Specification (Binary File Format) |
| **Classification** | Trade Secret |
| **Status** | Active, in use |
| **Date Created** | March 2026 |
| **Associated Product** | YubiVault |

**Description**: Custom binary format for portable encrypted backups using AES-256-CBC
with DPAPI-wrapped key material.

**Format Specification**:
```
[6 bytes]  Magic header: "YVBK01" (ASCII)
[4 bytes]  Int32: DPAPI-protected AES key length
[N bytes]  DPAPI-protected AES-256 key
[4 bytes]  Int32: DPAPI-protected IV length
[M bytes]  DPAPI-protected AES-CBC IV
[R bytes]  AES-256-CBC encrypted payload (PKCS7 padding)
```

---

### Asset #003: 3-Tier Credential Cache Architecture

| Field | Detail |
|-------|--------|
| **Asset Name** | 3-Tier Credential Cache Architecture |
| **Asset Type** | Software Architecture / Design |
| **Classification** | Proprietary (published in documentation) |
| **Status** | Active |
| **Date Created** | March 2026 |
| **Associated Product** | YubiVault |

**Description**: A layered caching strategy for hardware-backed credential retrieval:
- **Tier 1**: In-memory hashtable (session scope, instant)
- **Tier 2**: DPAPI-encrypted disk files (per-user, 8-hour TTL, survives restarts)
- **Tier 3**: KeePassXC CLI with YubiKey HMAC-SHA1 challenge-response (requires physical touch)

---

## Trademarks

| Mark | Status | Scope |
|------|--------|-------|
| YubiVault | Common law (unregistered) | Software product name |

Note: "YubiKey" is a registered trademark of Yubico, Inc. "KeePassXC" is a trademark
of the KeePassXC Team. These marks are used solely for descriptive compatibility purposes.

---

## Record Keeping

This registry shall be updated when new IP assets are created, modified, or retired.
Each update should include the date, description of change, and updated version number.

| Date | Change | Registry Version |
|------|--------|-----------------|
| March 20, 2026 | Initial registry created with Assets #001-#003 | 1.0 |
