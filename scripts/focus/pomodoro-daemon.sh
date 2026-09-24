#!/bin/bash
# Pomodoro daemon: independiente de tmux, visible en waybar
# Estado en /tmp/pomodoro-state

STATE_FILE="/tmp/pomodoro-state"
FOCUS_MIN=25
BREAK_MIN=5
LOG_FILE="${HOME}/.local/share/pomodoro-log.txt"

update_status() {
    local status="$1"
    local remaining="$2"
    local mins="${remaining%m}"
    local icon="🍅"
    [ "$status" = "active" ] && icon="🍅"
    [ "$status" = "break" ] && icon="☕"
    if [ "$mins" -gt 0 ] 2>/dev/null; then
        echo "{\"text\":\"$icon $remaining\",\"class\":\"pomodoro-$status\"}" > "$STATE_FILE"
    fi
}

idle_status() {
    echo "{\"text\":\"🍅\",\"class\":\"pomodoro-idle\"}" > "$STATE_FILE"
}

notify() {
    local msg="$1"
    local urgency="$2"
    notify-send -u "$urgency" -t 10000 "Pomodoro" "$msg"
    paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null || true
}

case "${1:-toggle}" in
    toggle)
        if [ -f /tmp/pomodoro-pid ]; then
            kill "$(cat /tmp/pomodoro-pid)" 2>/dev/null
            rm -f /tmp/pomodoro-pid
            idle_status
            notify-send -u low "Pomodoro" "Detenido"
        else
            nohup "$0" run >/dev/null 2>&1 &
            disown
            echo $! > /tmp/pomodoro-pid
            notify-send -u normal "Pomodoro" "25 min de foco. ¡A darle!"
        fi
        ;;
    run)
        # Focus phase
        for ((m = FOCUS_MIN; m > 0; m--)); do
            update_status "active" "${m}m"
            sleep 60
        done
        notify "¡Foco terminado! Tómate $BREAK_MIN min de descanso" "critical"
        # Log de pomodoro completado
        mkdir -p "$(dirname "$LOG_FILE")"
        echo "$(date '+%Y-%m-%d %H:%M') - Pomodoro $((FOCUS_MIN))m completado en $(basename "$(pwd)") ( $(pwd) )" >> "$LOG_FILE"
        # Resumen rápido de actividad del día
        TODAY_COUNT=$(grep "$(date '+%Y-%m-%d')" "$LOG_FILE" 2>/dev/null | wc -l)
        notify-send -u low -t 5000 "🍅 Resumen del día" "Pomodoros completados hoy: $TODAY_COUNT"
        # Break phase
        for ((m = BREAK_MIN; m > 0; m--)); do
            update_status "break" "${m}m"
            sleep 60
        done
        notify "¡Descanso terminado! Listo para otro foco" "critical"
        idle_status
        rm -f /tmp/pomodoro-pid
        ;;
    status)
        cat "$STATE_FILE" 2>/dev/null || echo "{\"text\":\"\",\"class\":\"pomodoro-idle\"}"
        ;;
    log)
        if [ -f "$LOG_FILE" ]; then
            echo "=== Pomodoros completados ==="
            tail -"${1:-10}" "$LOG_FILE"
            echo "=== Total hoy: $(grep "$(date '+%Y-%m-%d')" "$LOG_FILE" 2>/dev/null | wc -l) pomodoros ==="
        else
            echo "Sin registros aún."
        fi
        ;;
    today)
        if [ -f "$LOG_FILE" ]; then
            grep "$(date '+%Y-%m-%d')" "$LOG_FILE" 2>/dev/null | wc -l
        else
            echo "0"
        fi
        ;;
esac
