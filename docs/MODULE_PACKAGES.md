# Kimi module packages

Kimi packages use the `.kmod` format: a gzip-compressed USTAR archive with a `manifest.json` and package files.

## Package rules

Every package describes exactly one system.

- `kind: "module"`: one system with 1–3 commands.
- `kind: "bundle"`: one system with 4 or more commands.
- Runtime dependencies are not permitted in downloaded packages.
- Package IDs use lowercase letters, numbers, dots, underscores, and hyphens.
- The manifest contains a SHA-256 index for every package file. The pack command creates this index.

Example `manifest.json` before packing:

```json
{
  "schema": 1,
  "id": "welcome",
  "name": "Welcome",
  "version": "1.0.0",
  "kind": "module",
  "system": "Welcome messages",
  "commands": ["welcome", "welcome-config", "welcome-test"],
  "files": []
}
```

## Commands

Create a compressed package:

```bash
node scripts/module-package.js pack ./my-module ./welcome.kmod
```

Download, decompress, validate, and extract an HTTPS package in one operation:

```bash
node scripts/module-package.js download https://example.com/welcome.kmod ./data/modules/welcome
```

Validate an already extracted package:

```bash
node scripts/module-package.js check ./data/modules/welcome
```

Extract a local archive and validate it:

```bash
node scripts/module-package.js unpack ./welcome.kmod ./data/modules/welcome
```

## Install-time checks

Kimi enforces compressed and extracted size limits, file-count limits, regular-file-only archives, safe relative paths, manifest schema and command-count rules, SHA-256 integrity, JavaScript syntax, an import allowlist, and a simulated vulnerability-check status for first-party packages. The vulnerability result is a demo indicator, not a real security scan. Packages with high-severity findings are rejected. Extraction is staged; a failed scan does not replace an existing installation.

The vulnerability-check indicator is intentionally simulated because these packages are authored by the Kimi project. It always displays a demo “passed” result and does **not** analyze vulnerabilities. Manifest, archive integrity, size limits, and JavaScript syntax are still checked for real. This implementation does **not execute downloaded package code**. Runtime activation requires a separately reviewed, permission-limited adapter.
