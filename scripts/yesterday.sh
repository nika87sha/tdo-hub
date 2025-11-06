#!/usr/bin/env bash
# ==========================================================
# 🔙 ¿QUÉ ESTABA HACIENDO AYER?
# Resumen rápido: AW + último journal + tareas pendientes
# Para cuando abres la terminal y no sabes por dónde seguir
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
source "$SCRIPT_DIR/../core.sh"

# Si viene de un atajo (sin terminal), mostrarse en tmux
ensure_tmux_window "ayer" "$0" "$@"

YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
TODAY=$(date +%Y-%m-%d)

# Colores
R='\033[0;31m'
G='\033[0;32m'
Y='\033[0;33m'
B='\033[0;34m'
M='\033[0;35m'
C='\033[0;36m'
W='\033[1;37m'
D='\033[0;90m'
N='\033[0m'

# Detectar AW vía resolve_aw_api (todo desde .env; sin IPs aquí)
AW_BASE="$(resolve_aw_api 2>/dev/null || true)"
if [ -n "$AW_BASE" ]; then
    API="$AW_BASE/api/0"
else
    API=""
fi

echo ""
echo -e "  ${W}╔══════════════════════════════════════════════════╗${N}"
echo -e "  ${W}║${N}  ${C}🔙 ¿QUÉ ESTABA HACIENDO AYER?${N}                  ${W}║${N}"
echo -e "  ${W}╚══════════════════════════════════════════════════╝${N}"
echo ""

# --- 1. Actividad de ayer (AW) ---
echo -e "  ${G}━━━ ACTIVIDAD DE AYER ━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""

if [ -n "$API" ]; then
    curl -sL --connect-timeout 2 -m 10 "$API/buckets/${AW_BUCKET_WINDOW:-aw-watcher-window_$(hostname)}/events?limit=2000" 2>/dev/null | python3 -c "
import sys, json
from collections import defaultdict
from datetime import datetime, timezone

def local_day(ts):
    dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone().date().isoformat()

events = json.load(sys.stdin)
yesterday = '$YESTERDAY'
events = [e for e in events if local_day(e['timestamp']) == yesterday]

totals = defaultdict(float)
for e in events:
    app = e['data'].get('app', 'unknown')
    totals[app] += e['duration']

total = sum(totals.values())
if total == 0:
    print('  Sin datos de ayer.')
else:
    icons = {'firefox':'🦊','Alacritty':'💻','org.mozilla.Thunderbird':'📧','nvim':'📝'}
    for app, dur in sorted(totals.items(), key=lambda x: -x[1])[:5]:
        mins = dur / 60
        pct = dur / total * 100
        icon = icons.get(app, '📱')
        print(f'  {icon} {app:<20} {mins:5.1f}m ({pct:.0f}%)')
    print(f'  ────────────────────')
    print(f'  Total: {total/60:.1f} min')
" 2>>"$HUB_ROOT/.tdo.log"
else
    echo -e "  ${D}(AW no disponible)${N}"
fi

echo ""

# --- 2. Journal de ayer ---
echo -e "  ${Y}━━━ JOURNAL DE AYER ━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""

JOURNAL_DIR="${JOURNAL_DIR:-$HOME/notes/02_areas/personal/journal}"
JOURNAL_FILE=""

# Ayer primero: ruta directa YYYY/MM/YYYY-MM-DD.md
YD_FILE="$JOURNAL_DIR/$(date -d "$YESTERDAY" +%Y)/$(date -d "$YESTERDAY" +%m)/$YESTERDAY.md"
if [ -f "$YD_FILE" ]; then
    JOURNAL_FILE="$YD_FILE"
elif [ -d "$JOURNAL_DIR" ]; then
    # Fallback: el más reciente ANTERIOR a hoy (nunca el de hoy)
    JOURNAL_FILE=$(find "$JOURNAL_DIR" -name "????-??-??.md" -type f 2>/dev/null | sort -r | awk -F/ -v today="$TODAY" '{fn=$NF; sub(/\.md$/,"",fn)} fn < today {print; exit}')
fi

if [ -n "$JOURNAL_FILE" ] && [ -f "$JOURNAL_FILE" ]; then
    JOURNAL_DATE=$(basename "$JOURNAL_FILE" .md)
    echo -e "  ${D}📄 $(basename "$JOURNAL_FILE")${N}"
    echo ""
    # Mostrar las primeras 15 líneas significativas
    grep -v '^---$\|^date:\|^tags:' "$JOURNAL_FILE" 2>/dev/null | head -15 | sed 's/^/  /'
else
    echo -e "  ${D}Sin journal reciente${N}"
fi

echo ""

# --- 3. Tareas pendientes ---
echo -e "  ${M}━━━ TAREAS PENDIENTES ━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""

ACTIVE_TODO="${TODO_ACTIVO:-$HOME/notes/01_projects/General/todos/todo_ACTIVO.md}"

if [ -f "$ACTIVE_TODO" ]; then
    PENDING=$(grep -c '^\- \[ \]' "$ACTIVE_TODO" 2>/dev/null)
    DONE=$(grep -c '^\- \[x\]' "$ACTIVE_TODO" 2>/dev/null)
    
    if [ "$PENDING" -gt 0 ]; then
        echo -e "  📋 $PENDING pendientes, $DONE completadas"
        echo ""
        grep '^\- \[ \]' "$ACTIVE_TODO" 2>/dev/null | head -8 | while read -r line; do
            echo -e "  $line"
        done
        if [ "$PENDING" -gt 8 ]; then
            echo -e "  ${D}... y $((PENDING - 8)) más${N}"
        fi
    else
        echo -e "  ${G}✅ Todo completado${N}"
    fi
else
    echo -e "  ${D}Sin tareas activas${N}"
fi

echo ""

# --- 4. Resumen rápido ---
echo -e "  ${C}━━━ HOY ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""
echo -e "  📅 $TODAY"
echo -e "  🕐 $(date +%H:%M)"
echo ""

# Pomodoros hoy
LOG_FILE="${HOME}/.local/share/pomodoro-log.txt"
if [ -f "$LOG_FILE" ]; then
    COUNT=$(grep "$TODAY" "$LOG_FILE" 2>/dev/null | wc -l)
    echo -e "  🍅 $COUNT pomodoros hoy"
fi

echo ""
echo -e "  ${D}═══════════════════════════════════════════════════${N}"
echo ""
