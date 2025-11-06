#!/usr/bin/env bash
# ==========================================================
# 📊 ACTIVITYWATCH STATS - Estadísticas del día
# Consulta la AW API y muestra resumen de actividad
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
source "$SCRIPT_DIR/../core.sh"

# Si viene de un atajo (sin terminal), mostrarse en tmux
ensure_tmux_window "stats" "$0" "$@"

# Conexión vía resolve_aw_api (todo desde .env; sin IPs aquí)
AW_BASE="$(resolve_aw_api 2>/dev/null || true)"
if [ -n "$AW_BASE" ]; then
    API="$AW_BASE/api/0"
else
    API=""
fi

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

# Verificar conexión
if [ -z "$API" ]; then
    echo -e "${R}❌ No se pudo conectar a ActivityWatch${N}"
    echo -e "${D}   Intenta: aw-server o configura AW_SERVER_URL${N}"
    exit 1
fi

if ! curl -sL --connect-timeout 2 -m 10 "$API/buckets" >/dev/null 2>&1; then
    echo -e "${R}❌ No se puede conectar a ActivityWatch ($API)${N}"
    echo -e "${D}   Asegúrate de que aw-server está corriendo${N}"
    exit 1
fi

echo ""
echo -e "  ${W}╔═════════════════════════════════════════╗${N}"
echo -e "  ${W}║${N}  ${C}📊 ACTIVITYWATCH - Resumen del día${N}      ${W}║${N}"
echo -e "  ${W}╚═════════════════════════════════════════╝${N}"
echo ""

# --- Top apps ---
echo -e "  ${G}━━━ TOP APLICACIONES ━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""

curl -sL --connect-timeout 2 -m 10 "$API/buckets/${AW_BUCKET_WINDOW}/events?limit=2000" 2>/dev/null | python3 -c "
import sys, json
from collections import defaultdict
from datetime import datetime, timezone

def _local_day(ts):
    dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone().date().isoformat()

events = json.load(sys.stdin)
today = '$TODAY'
events = [e for e in events if _local_day(e['timestamp']) == today]

totals = defaultdict(float)
for e in events:
    app = e['data'].get('app', 'unknown')
    totals[app] += e['duration']

total = sum(totals.values())
if total == 0:
    print('  Sin datos para hoy.')
else:
    icons = {'firefox':'🦊','Alacritty':'💻','org.mozilla.Thunderbird':'📧','nvim':'📝'}
    pad = ''
    for app, dur in sorted(totals.items(), key=lambda x: -x[1])[:10]:
        mins = dur / 60
        pct = dur / total * 100
        bar_len = int(pct / 5)
        bar = '█' * bar_len + '░' * (20 - bar_len)
        icon = icons.get(app, '📱')
        print(f'  {icon} {app:<20} {bar} {mins:5.1f}m ({pct:.0f}%)')
    print(f'  {pad:<25}────────────────────')
    print(f'  {pad:<25}Total: {total/60:.1f} min')
" 2>>"$HUB_ROOT/.tdo.log"

echo ""

# --- Context switching ---
echo -e "  ${M}━━━ CONTEXTO (switching) ━━━━━━━━━━━━━━━━━${N}"
echo ""

curl -sL --connect-timeout 2 -m 10 "$API/buckets/${AW_BUCKET_WINDOW}/events?limit=2000" 2>/dev/null | python3 -c "
import sys, json
from collections import defaultdict
from datetime import datetime, timezone

def _local_day(ts):
    dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone().date().isoformat()

events = json.load(sys.stdin)
today = '$TODAY'
events = [e for e in events if _local_day(e['timestamp']) == today]

switches = 0
for i in range(1, len(events)):
    if events[i]['data'].get('app') != events[i-1]['data'].get('app'):
        switches += 1

if switches > 0:
    total_time = sum(e['duration'] for e in events)
    avg_between = total_time / switches
    print(f'  Cambios de app:    {switches}')
    print(f'  Promedio cada:     {avg_between:.0f} segundos')
    if switches > 30:
        print(f'  ⚠️  Muy alto - dificulta flow state')
    elif switches > 15:
        print(f'  ⚡ Moderado')
    else:
        print(f'  ✅ Normal - buen foco')
else:
    print('  Sin datos suficientes.')
" 2>>"$HUB_ROOT/.tdo.log"

echo ""

# --- Neovim ---
echo -e "  ${C}━━━ NEOVIM (qué editaste) ━━━━━━━━━━━━━━━━━${N}"
echo ""

curl -sL --connect-timeout 2 -m 10 "$API/buckets/${AW_BUCKET_VIM}/events?limit=2000" 2>/dev/null | python3 -c "
import sys, json
from collections import defaultdict
from datetime import datetime, timezone

def _local_day(ts):
    dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone().date().isoformat()

events = json.load(sys.stdin)
today = '$TODAY'
events = [e for e in events if _local_day(e['timestamp']) == today]

totals = defaultdict(float)
for e in events:
    lang = e['data'].get('language', '')
    if lang and lang != 'NvimTree':
        totals[lang] += e['duration']

total = sum(totals.values())
if total == 0:
    print('  Sin datos de editor.')
else:
    for lang, dur in sorted(totals.items(), key=lambda x: -x[1]):
        print(f'  📝 {lang:<15} {dur/60:5.1f}m')
" 2>>"$HUB_ROOT/.tdo.log"

echo ""

# --- Pomodoros ---
echo -e "  ${R}━━━ POMODOROS ━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""

LOG_FILE="${HOME}/.local/share/pomodoro-log.txt"
if [ -f "$LOG_FILE" ]; then
    COUNT=$(grep "$TODAY" "$LOG_FILE" 2>/dev/null | wc -l)
    if [ "$COUNT" -gt 0 ]; then
        echo "  🍅 $COUNT pomodoros completados hoy"
    else
        echo "  🍅 0 pomodoros hoy"
    fi
else
    echo "  🍅 Sin registros"
fi

echo ""
echo -e "  ${D}═══════════════════════════════════════════${N}"
echo ""