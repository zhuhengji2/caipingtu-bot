#!/usr/bin/env bash
set -euo pipefail

REPO="zhuhengji2/caipingtu-bot"
BRANCH="main"
TARGET="${CAIPINGTU_TARGET:-$HOME/.workbuddy/skills/caipingtu}"
SKIP_MODEL=0
SKIP_DEPS=0
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-model) SKIP_MODEL=1 ;;
    --skip-deps)  SKIP_DEPS=1 ;;
    --force)      FORCE=1 ;;
    --target)     TARGET="$2"; shift ;;
    -h|--help)    sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $1"; exit 1 ;;
  esac
  shift
done

echo ""
echo "  caipingtu-bot installer"
echo "  CAD floor plan -> colored interior plan"
echo ""

SRC=""
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$HERE/SKILL.md" ]; then
  SRC="$HERE"
  echo "[*] Using local files: $SRC"
else
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  ZIP="$TMP/src.zip"
  for URL in \
    "https://github.com/$REPO/archive/refs/heads/$BRANCH.zip" \
    "https://gh-proxy.com/https://github.com/$REPO/archive/refs/heads/$BRANCH.zip" \
    "https://ghfast.top/https://github.com/$REPO/archive/refs/heads/$BRANCH.zip"
  do
    echo "[*] Downloading from $URL"
    if curl -fsSL --max-time 120 -o "$ZIP" "$URL" && [ "$(wc -c < "$ZIP")" -gt 50000 ]; then
      break
    fi
    echo "[!] failed, trying next mirror"
  done
  [ -s "$ZIP" ] || { echo "[!] download failed"; exit 1; }
  echo "[*] Extracting"
  if command -v unzip >/dev/null 2>&1; then unzip -q -o "$ZIP" -d "$TMP"; else python3 -m zipfile -e "$ZIP" "$TMP"; fi
  SRC="$(find "$TMP" -maxdepth 2 -name SKILL.md -print | head -1 | xargs dirname)"
  [ -n "$SRC" ] || { echo "[!] SKILL.md not found in archive"; exit 1; }
fi

if [ -e "$TARGET" ]; then
  if [ "$FORCE" -ne 1 ]; then
    echo "[!] Target already exists: $TARGET"
    echo "[!] Re-run with --force to replace it (a .bak copy is kept)."
    exit 1
  fi
  rm -rf "$TARGET.bak"
  mv "$TARGET" "$TARGET.bak"
  echo "[!] Old version moved to $TARGET.bak"
fi

mkdir -p "$(dirname "$TARGET")"
echo "[*] Installing skill to $TARGET"
cp -R "$SRC" "$TARGET"
rm -rf "$TARGET/.git"
echo "[+] SKILL.md installed"

if [ "$SKIP_DEPS" -eq 0 ]; then
  if command -v python3 >/dev/null 2>&1; then
    echo "[*] Installing Python dependencies"
    python3 -m pip install -r "$TARGET/requirements.txt" --quiet && echo "[+] Dependencies ready" || echo "[!] pip failed"
  else
    echo "[!] python3 not found. Install Python 3.9+ then run: pip install -r $TARGET/requirements.txt"
  fi
fi

if [ "$SKIP_MODEL" -eq 0 ]; then
  if [ -f "$TARGET/scripts/models/lama_fp32.onnx" ]; then
    echo "[+] Model already present, skipped"
  else
    echo "[*] Downloading inpaint model (208 MB, resumable)"
    python3 "$TARGET/scripts/download_model.py" || echo "[!] model download failed, rerun: python3 $TARGET/scripts/download_model.py"
  fi
fi

echo ""
echo "  Done. Restart WorkBuddy, then send a floor plan and say:"
echo "    make a colored floor plan"
echo ""
echo "  Skill folder: $TARGET"
echo ""
