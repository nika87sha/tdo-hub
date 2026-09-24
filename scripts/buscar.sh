#!/usr/bin/env bash
# ==========================================================
# 🔍 BUSCAR EN NOTAS - tmux + fzf (ventana 🔍 dedicada)
# Uso directo (atajo) o desde hub.sh
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
source "$SCRIPT_DIR/../core.sh"

WIN="🔍"
tmux has-session -t "$SESSION" 2>/dev/null || tmux new-session -d -s "$SESSION"

if tmux list-windows -t "$SESSION" -F "#{window_name}" 2>/dev/null | grep -q "^$WIN$"; then
    PROC=$(tmux list-panes -t "$SESSION:$WIN" -F '#{pane_current_command}' 2>/dev/null | head -1)
    if [[ "$PROC" == "nvim" || "$PROC" == "vim" ]]; then
        tmux select-window -t "$SESSION:$WIN" 2>/dev/null
        hyprctl dispatch 'hl.dsp.focus({ window = "class:Alacritty" })' 2>/dev/null
        notify "🔍" "Cierra el archivo (:q) para buscar de nuevo"
        exit 0
    fi
else
    tmux new-window -t "$SESSION" -n "$WIN"
    sleep 0.5
fi

# El \$(...) escapado evita que se expanda aquí: se ejecuta DENTRO de tmux.
# Si cancelas fzf, nvim no se abre ([ -n ... ]).
tmux send-keys -t "$SESSION:$WIN" C-u "clear && cd '$NOTES_DIR' && f=\$(rg --files | fzf) && [ -n \"\$f\" ] && nvim \"\$f\"" C-m
tmux select-window -t "$SESSION:$WIN" 2>/dev/null
hyprctl dispatch 'hl.dsp.focus({ window = "class:Alacritty" })' 2>/dev/null
