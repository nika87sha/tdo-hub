#!/usr/bin/env bash
# ==========================================================
# 🧠 FLOW STATE DETECTOR
# Detecta si llevas mucho tiempo en la misma app
# y te avisa para mantener o romper el foco
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
source "$SCRIPT_DIR/../../core.sh"
source "$SCRIPT_DIR/../lib/aw_client.sh"

THRESHOLD="${1:-25}"  # minutos mínimo para notificar

# Verificar AW
aw_is_running || exit 1

# Obtener eventos de las últimas 2 horas
END=$(aw_today_end)
START=$(date -u -d "2 hours ago" +%Y-%m-%dT%H:%M:%SZ)

RESULT=$(aw_detect_flow 30 | head -1)

if [ -n "$RESULT" ]; then
    APP=$(echo "$RESULT" | cut -d'|' -f2)
    MINS=$(echo "$RESULT" | cut -d'|' -f1)
    PCT=$(echo "$RESULT" | cut -d'|' -f3)
    MINS=${MINS%.*}  # truncar decimales
    
    if [ "$MINS" -ge "$THRESHOLD" ]; then
        # Decidir qué sugerir según la app
        case "$APP" in
            firefox|chromium|google-chrome)
                notify "🌐 Llevas ${MINS}min en $APP (${PCT}%)" "¿Esto es productivo? Ctrl+A → m para capturar idea"
                ;;
            Alacritty|nvim|neovim|code|vscode)
                notify "💻 Flow state: ${MINS}min en $APP" "Mantén el ritmo 🍅 o toma una pausa"
                ;;
            org.mozilla.Thunderbird|discord|org.telegram.desktop)
                notify "📧 ${MINS}min en comunicación" "¿Puedes responder después? Enfócate"
                ;;
            *)
                notify "⏰ ${MINS}min en $APP (${PCT}%)" "¿Es lo que querías hacer?"
                ;;
        esac
    fi
fi
