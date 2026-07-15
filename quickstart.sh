#!/usr/bin/env bash
# quickstart.sh — установка Kimi Approve Watch одной командой из bash-терминалов
# (Git Bash, MSYS2, WSL с доступом к powershell.exe).
#
#   curl -sL https://raw.githubusercontent.com/bimpiRU/kimi-approve-watch/main/quickstart.sh | bash
#
# Переопределения через переменные окружения:
#   KAW_DIR=/d/tools/kaw  KAW_MODE=startup  (gate|startup|none)
set -e

REPO="https://github.com/bimpiRU/kimi-approve-watch"
DIR="${KAW_DIR:-$USERPROFILE/kimi-approve-watch}"
[ -z "$DIR" ] && DIR="$HOME/kimi-approve-watch"
MODE="${KAW_MODE:-}"

echo
echo "  Kimi Approve Watch — quickstart (bash)"
echo "  Каталог: $DIR"
echo

if [ -d "$DIR/.git" ]; then
  echo "Уже установлено — обновляю (git pull)..."
  git -C "$DIR" pull --ff-only
elif command -v git >/dev/null 2>&1; then
  git clone "$REPO" "$DIR"
else
  echo "git не найден — скачиваю ZIP..."
  TMP="$(mktemp -d)"
  curl -sL "$REPO/archive/refs/heads/main.zip" -o "$TMP/kaw.zip"
  unzip -q "$TMP/kaw.zip" -d "$TMP"
  rm -rf "$DIR"
  mv "$TMP/kimi-approve-watch-main" "$DIR"
  rm -rf "$TMP"
fi

# путь вида C:\... для powershell.exe
if command -v cygpath >/dev/null 2>&1; then
  WINDIR="$(cygpath -w "$DIR")"
else
  WINDIR="$DIR"
fi

ARGS=(-NoProfile -ExecutionPolicy Bypass -File "$WINDIR\\install.ps1")
[ -n "$MODE" ] && ARGS+=(-Mode "$MODE")
ARGS+=(-WithStabilizer)

powershell.exe "${ARGS[@]}"
