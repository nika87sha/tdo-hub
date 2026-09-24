#!/usr/bin/env bash
# ==========================================================
# ↩️ UNDO - Deshacer última acción de tareas
# Uso directo (atajo) o desde hub.sh
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
source "$SCRIPT_DIR/../../core.sh"

[[ ! -f "$TODO_TRASH" ]] && notify "Undo" "No hay acciones" && exit 0
SEL=$(tail -10 "$TODO_TRASH" 2>/dev/null | rofi_menu "↩️" "Últimas acciones")
[[ -z "$SEL" ]] && exit 0
echo "- [ ] $(echo "$SEL" | sed 's/^[^:]*: //; s/^.*\[x\] //')" >> "$TODO_ACTIVO" && notify "Restaurado"
