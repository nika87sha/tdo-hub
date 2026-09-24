#!/usr/bin/env bash
# ==========================================================
# 🎁 REWARD SYSTEM
# Después de N pomodoros, sugiere una recompensa
# Dopamina programada para cerebros TDAH
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
source "$SCRIPT_DIR/../../core.sh"

POMODOROS_NEEDED="${1:-3}"
TODAY=$(date +%Y-%m-%d)
LOG_FILE="${HOME}/.local/share/pomodoro-log.txt"

# Contar pomodoros de hoy
if [ ! -f "$LOG_FILE" ]; then
    exit 0
fi

COUNT=$(grep -c "$TODAY" "$LOG_FILE" 2>/dev/null)
[ "$COUNT" -eq 0 ] && exit 0

# Verificar si ya se dio reward hoy
REWARD_FILE="${HOME}/.local/share/tdo-reward-$(date +%Y-%m-%d)"
if [ -f "$REWARD_FILE" ]; then
    LAST_REWARD=$(cat "$REWARD_FILE" 2>/dev/null)
    # Si ya tuvo reward con menos pomodoros, no repetir hasta alcanzar siguiente umbral
    if [ "$COUNT" -le "$LAST_REWARD" ]; then
        exit 0
    fi
fi

# Verificar si alcanzó el umbral
REWARD_LEVEL=$(( COUNT / POMODOROS_NEEDED ))
[ "$REWARD_LEVEL" -eq 0 ] && exit 0

# Recompensas por nivel
get_reward() {
    local level=$1
    case $level in
        1)
            echo "🍵 Primer bloque: toma un café o té"
            echo "   Llevas $COUNT pomodoros — buen inicio"
            ;;
        2)
            echo "🏃 Segundo bloque: mueve el cuerpo"
            echo "   5 min de estiramiento o caminar"
            ;;
        3)
            echo "🎵 Tercer bloque: tu música favorita"
            echo "   5 min de algo que te guste"
            ;;
        4)
            echo "📱 Cuarto bloque: revisa tu phone (limitado)"
            echo "   5 min max — pon alarma"
            ;;
        5)
            echo "🏆 ¡Cinco bloques! Eres máquina"
            echo "   Tómate 15 min para lo que quieras"
            ;;
        *)
            echo "⭐ Bloque $level completado"
            echo "   $COUNT pomodoros totales — sigue así"
            ;;
    esac
}

REWARD=$(get_reward "$REWARD_LEVEL")

# Mostrar notificación
notify "🎁 ¡Recompensa!" "$REWARD"

# Guardar estado
echo "$COUNT" > "$REWARD_FILE"

# Log
echo "[$(date +%H:%M:%S)] Reward level $REWARD_LEVEL after $COUNT pomodoros" >> "$HOME/.local/share/tdo-rewards.log"
