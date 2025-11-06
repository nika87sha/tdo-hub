#!/usr/bin/env bash
# ==========================================================
# 🧠 FLOW STATE DETECTOR
# Detecta si llevas mucho tiempo en la misma app
# y te avisa para mantener o romper el foco
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
source "$SCRIPT_DIR/../core.sh"

THRESHOLD="${1:-25}"  # minutos mínimo para notificar

# Detectar AW vía resolve_aw_api (todo desde .env; sin IPs aquí)
AW_BASE="$(resolve_aw_api 2>/dev/null || true)"
[ -z "$AW_BASE" ] && exit 1
API="$AW_BASE/api/0"

# Obtener eventos de las últimas 2 horas
END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
START=$(date -u -d "2 hours ago" +%Y-%m-%dT%H:%M:%SZ)

RESULT=$(curl -sL --connect-timeout 2 -m 10 "$API/buckets/${AW_BUCKET_WINDOW:-aw-watcher-window_$(hostname)}/events?limit=500&start=$START&end=$END" 2>/dev/null | python3 -c "
import sys, json
from collections import defaultdict
from datetime import datetime, timezone

events = json.load(sys.stdin)
if not events:
    sys.exit(0)

# Calcular tiempo por app en los últimos 30 min (todo tz-aware UTC)
now = datetime.now(timezone.utc)
recent = []
for e in events:
    ts = e['timestamp'].replace('Z', '+00:00')
    try:
        event_time = datetime.fromisoformat(ts)
        if event_time.tzinfo is None:
            event_time = event_time.replace(tzinfo=timezone.utc)
        if (now - event_time).total_seconds() < 1800:  # 30 min
            recent.append(e)
    except Exception:
        pass

if not recent:
    sys.exit(0)

totals = defaultdict(float)
for e in recent:
    app = e['data'].get('app', 'unknown')
    totals[app] += e['duration']

if not totals:
    sys.exit(0)

top_app = max(totals, key=totals.get)
top_dur = totals[top_app]
total = sum(totals.values())
pct = top_dur / total * 100 if total > 0 else 0
mins = top_dur / 60

# Solo sugerir si es >60% del tiempo y >15 min
if pct > 60 and mins > 15:
    print(f'{top_app}|{mins:.0f}|{pct:.0f}')
" 2>>"$HUB_ROOT/.tdo.log")

if [ -n "$RESULT" ]; then
    APP=$(echo "$RESULT" | cut -d'|' -f1)
    MINS=$(echo "$RESULT" | cut -d'|' -f2)
    PCT=$(echo "$RESULT" | cut -d'|' -f3)
    
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
