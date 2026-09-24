#!/usr/bin/env bash
# 🛑 Botón de Pánico - Desactiva focus de forma forzada y sin toggle

source "$(dirname "$0")/../../core.sh"

# 1. Desactivar focus mode de forma explícita (NUNCA toggle)
bash "$FOCUS_SCRIPT" stop 2>/dev/null

# 2. Parar música y timers
stop_music 2>/dev/null
timew stop 2>/dev/null

# 3. Cerrar sesión tmux de foco o la sesión completa
tmux kill-session -t "$SESSION" 2>/dev/null

# 4. Notificar
notify-send "🛑 Botón de Pánico" "Descanso forzado. ¡Sin culpa!" -u critical
echo "[$(date +%Y-%m-%d_%H:%M)] Pánico activado" >> "$HOME/.config/tdo/notifications.log"

# 5. Limpiar notificaciones acumuladas
dunstctl close-all 2>/dev/null || true