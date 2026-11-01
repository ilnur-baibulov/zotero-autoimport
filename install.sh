#!/bin/sh
# Install (or reinstall) the launchd agent that watches the drop folder.
# Usage: ./install.sh [DROP_FOLDER]      default: ~/Downloads/to-zotero
set -e
cd "$(dirname "$0")"
LABEL=local.zotero-autoimport
INBOX="${1:-$HOME/Downloads/to-zotero}"
PYTHON="$(command -v python3)"
for t in pdftotext pdftoppm pdfinfo; do
  command -v "$t" >/dev/null || { echo "missing: $t (see README, brew install poppler)"; exit 1; }
done
# the agent gets the directories of the tools found now, plus the system ones
DIRS=""
for t in agy claude copilot ollama codex pdftotext ocrmypdf tesseract djvutxt; do
  p="$(command -v "$t" 2>/dev/null)" && DIRS="$DIRS:$(dirname "$p")" || true
done
AGENT_PATH="$(echo "${DIRS#:}:/usr/bin:/bin:/usr/sbin:/sbin" | tr ':' '\n' | awk '!s[$0]++' | paste -sd: -)"
mkdir -p "$INBOX" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
INBOX="$(cd "$INBOX" && pwd)"
P="$HOME/Library/LaunchAgents/$LABEL.plist"
sed -e "s|@LABEL@|$LABEL|" -e "s|@PYTHON@|$PYTHON|" -e "s|@SCRIPT@|$PWD/zotero_autoimport.py|" \
    -e "s|@INBOX@|$INBOX|g" -e "s|@PATH@|$AGENT_PATH|" -e "s|@HOME@|$HOME|g" \
    launchd.plist.in > "$P"
launchctl bootout "gui/$(id -u)" "$P" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$P"
echo "watching $INBOX; log: ~/Library/Logs/zotero-autoimport.log"
if [ ! -f config.env ] || ! grep -q "^ZAI_LLM_CMD=" config.env; then
  echo "note: set ZAI_LLM_CMD in config.env (see config.env.example)"
fi
