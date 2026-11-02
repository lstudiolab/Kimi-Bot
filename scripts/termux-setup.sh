#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
pkg update -y
pkg upgrade -y
pkg install -y swift git
printf 'Swift installed. Clone Kimi, configure .env, then run swift build -c release.\n'
