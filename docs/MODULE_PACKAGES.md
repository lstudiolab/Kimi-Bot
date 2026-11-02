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

Kimi enforces compressed and extracted size limits, file-count limits, regular-file-only archives, safe relative paths, manifest schema and command-count rules, SHA-256 integrity, JavaScript syntax, an import allowlist, and static checks for risky APIs and embedded credentials. Packages with high-severity findings are rejected. Extraction is staged; a failed scan does not replace an existing installation.

The scanner is a static risk filter, not a proof that code is harmless. It can miss obfuscated or novel attacks. For that reason, this implementation does **not execute downloaded package code**. Passing checks means the package is structurally valid and passed the current static checks; it does not mean the package is activated or trusted. Runtime activation requires a separately reviewed, permission-limited adapter.
