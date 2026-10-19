#!/bin/sh
# Linux/Ubuntu twin of build.bat: builds sample/dist/hello (ELF) with PyInstaller. Usage: build.sh [version]
# Build on the oldest Ubuntu you need to support: the binary needs glibc at least as new as the build host's.
set -eu
cd "$(dirname "$0")"
VERSION="${1:-local}"
python3 -m venv .venv
. .venv/bin/activate
pip install --quiet -r requirements.txt
sed "s/__VERSION__/$VERSION/" hello.py > build_hello.py
pyinstaller --noconfirm --onefile --name hello build_hello.py
rm -f build_hello.py
echo "built $(pwd)/dist/hello"
