# Timi image tools (no AI API)

Timi can run lightweight image checks when a member uploads an image and either mentions Timi or replies to one of Timi's messages. The bot does not send images to an external AI service and deletes its temporary working files after analysis.

## Included checks

- PNG/JPEG/GIF/WEBP/BMP signature validation, dimensions and file size.
- SHA-256 exact duplicate detection, retained in memory for up to seven days (maximum 500 records per server).
- Optional perceptual duplicate detection with ImageMagick.
- OCR with Tesseract (English language data).
- QR decoding with ZBar.
- URL extraction from OCR and QR data, with basic phishing indicators (shorteners, HTTP links, punycode, raw IP hosts and common Discord impersonation patterns).
- Heuristic scam-text checks against OCR output.

These are not AI image understanding and do not reliably classify nudity, violence, gore, or other visual content. A clean result is not proof that an image or link is safe. Timi does not automatically delete, punish, or block a member based on these heuristic flags.

## Optional Termux tools

Install what is available in your Termux repository:

```bash
pkg update
pkg install tesseract zbar imagemagick
```

If a package is unavailable in the configured Termux repository, the corresponding feature stays disabled; metadata and exact duplicate checks still work.

## Usage

Install the Security library. Upload an image and mention Timi, or reply to a Timi message with an image. Timi analyzes at most three images per request, each up to 8 MB. Per-user requests are rate-limited to one every 10 seconds. Temporary files are removed after processing.
