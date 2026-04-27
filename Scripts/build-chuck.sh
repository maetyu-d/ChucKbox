#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor"
CHUCK_DIR="$VENDOR_DIR/chuck"

mkdir -p "$VENDOR_DIR"

if [ ! -d "$CHUCK_DIR/.git" ]; then
  git clone https://github.com/ccrma/chuck.git "$CHUCK_DIR"
else
  git -C "$CHUCK_DIR" pull --ff-only
fi

cd "$CHUCK_DIR/src"
make mac

echo
echo "Built ChucK at:"
echo "  $CHUCK_DIR/src/chuck"
