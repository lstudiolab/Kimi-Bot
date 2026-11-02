# Kimi Update Log

This file records notable changes to Kimi. Newest updates appear first.

## Latest — November 2, 2026

### Fixed
- Fixed the settings module export mismatch. `src/settings.js` now exports `KimiSettings`, matching the import in `src/index.js`.
- This resolves the startup error stating that `./settings.js` does not provide an export named `KimiSettings`.

## November 1, 2026

### Module installation
- Added a staged installation progress display for library installs.
- The display reports preparation, module loading, manifest and structure checks, decompression, slash-command checks, registration, activation, and completion.
- The progress display is visual; actual library installation and Discord command synchronization are handled by the bot's installation flow.

### Module packages
- Added the `.kmod` compressed module package format using gzip-compressed TAR archives.
- Added package creation, download, extraction, and validation commands for maintainers.
- Downloads are automatically decompressed and validated before installation.
- Added manifest validation, module and bundle command-count limits, SHA-256 integrity indexes, archive size and file-count limits, and unsafe-path / symlink rejection.
- Added JavaScript syntax checks for packaged files.
- Added package documentation and automated tests.

### Security-check disclosure
- The package vulnerability status is currently a **simulated demonstration check**. It does not perform real vulnerability analysis.
- Archive validation, integrity verification, and JavaScript syntax checks are actual checks.

## Updating Kimi

On the Termux host, run:

```bash
git pull
npm start
```

For a clean update, stop the currently running Kimi process before pulling the latest changes.
