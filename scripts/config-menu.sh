#!/usr/bin/env bash
# ==========================================================
# ⚙️ CONFIG - Editar config / ver rutas / limpiar caché
# Uso directo (atajo) o desde hub.sh
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
source "$SCRIPT_DIR/../core.sh"

SUB2=$(echo -e "📝 Editar\n🔗 Rutas\n🧹 Caché" | rofi -dmenu -p "Config:")
case "$SUB2" in
    *"Editar"*)  run_in_tmux "nvim '$HUB_ROOT/config.sh'" "config" ;;
    *"Rutas"*)   run_in_tmux "echo 'NOTES=$NOTES_DIR' && echo 'INBOX=$INBOX_DIR' && echo 'TODO=$TODO_ACTIVO' && read" "routes" ;;
    *"Caché"*)   rm -rf "$HOME/.config/tdo/cache" && notify "✓ Caché limpiado" ;;
esac
