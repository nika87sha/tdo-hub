#!/usr/bin/env bash
# ==========================================================
# 📓 JOURNAL - Abre journal del día en tmux + nvim
# ==========================================================

HUB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$HUB_ROOT/core.sh"

JOURNAL_DIR="${JOURNAL_DIR:-$NOTES_DIR/journal}"
TEMPLATE="$TEMPLATES_DIR/entry.md"
TODAY=$(date +%Y-%m-%d)
YEAR=$(date +%Y)
MONTH=$(date +%m)
FILE="$JOURNAL_DIR/$YEAR/$MONTH/$TODAY.md"

mkdir -p "$(dirname "$FILE")"

if [[ ! -f "$FILE" ]]; then
    if [[ -f "$TEMPLATE" ]]; then
        apply_template "$TEMPLATE" "$FILE" "$TODAY"
    else
        echo "# 📓 $TODAY" > "$FILE"
    fi
fi

tmux has-session -t "$SESSION" 2>/dev/null || tmux new-session -d -s "$SESSION"
tmux has-session -t "$SESSION" 2>/dev/null || exit 1

EXISTING=$(tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -c "^journal$")
if [[ "$EXISTING" -gt 0 ]]; then
    PROC=$(tmux list-panes -t "$SESSION:journal" -F '#{pane_current_command}' 2>/dev/null | head -1)
    if [[ "$PROC" == "nvim" || "$PROC" == "vim" ]]; then
        tmux select-window -t "$SESSION:journal" 2>/dev/null
    else
        tmux send-keys -t "$SESSION:journal" "nvim '+normal Gko' \"$FILE\"" Enter
        tmux select-window -t "$SESSION:journal" 2>/dev/null
    fi
else
    tmux new-window -t "$SESSION" -n "journal"
    sleep 0.3
    tmux send-keys -t "$SESSION:journal" "nvim '+normal Gko' \"$FILE\"" Enter
    tmux select-window -t "$SESSION:journal" 2>/dev/null
fi

hyprctl dispatch 'hl.dsp.focus({ window = "class:Alacritty" })' 2>/dev/null
notify-send -u low "📓 Journal" "Abierto: $FILE" 2>/dev/null || true
