#!/usr/bin/env bash
# ==========================================================
# 📊 ACTIVITYWATCH STATS - Estadísticas del día
# Consulta la AW API y muestra resumen de actividad
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
source "$SCRIPT_DIR/../../core.sh"
source "$SCRIPT_DIR/../lib/aw_client.sh"

# Si viene de un atajo (sin terminal), mostrarse en tmux
tmux_run_script "stats" "$0" "$@"

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
if ! aw_is_running; then
    echo -e "${R}❌ No se pudo conectar a ActivityWatch${N}"
    echo -e "${D}   Intenta: aw-server o configura AW_SERVER_URL${N}"
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

aw_summary_today | while IFS='|' read -r hours app; do
    [[ -z "$hours" ]] && continue
    # Filter out unknown apps that might still appear
    [[ "$app" == "unknown" ]] && continue
    icon="📱"
    case "$app" in
        firefox|chrome|brave|Firefox|Chrome|Brave) icon="🦊" ;;
        Alacritty|kitty|gnome-terminal|Alacritty) icon="💻" ;;
        Thunderbird|evolution) icon="📧" ;;
        nvim|vim|code|nvim|vim|Code) icon="📝" ;;
    esac
    # Use awk for float formatting (bash printf doesn't handle floats well)
    printf '  %s %-20s ' "$icon" "$app"
    echo "$hours" | awk '{printf "%.1fh\n", $1}'
done

# Add shell/terminal time (from shell bucket heartbeats)
SHELL_SECONDS=$(cd /home/verodg/.local/bin/tdo-hub/scripts && bash -c "source ./aw_client.sh && aw_get_shell_events \"\$(date -d 'today 00:00:00' -u +%Y-%m-%dT%H:%M:%SZ)\" \"\$(date -d 'today 23:59:59' -u +%Y-%m-%dT%H:%M:%SZ)\"" | python3 -c "
import sys, json
events = json.load(sys.stdin)
total = 0
for e in events:
    data = e.get('data', {})
    if data.get('heartbeat'):
        dur = e.get('duration', 0)
        if dur == 0:
            dur = 30  # pulsetime
        total += dur
print(total)
" 2>/dev/null || echo 0)

# Use awk for float comparison
if awk -v t="$SHELL_SECONDS" 'BEGIN {exit !(t > 0)}'; then
    SHELL_HOURS=$(echo "$SHELL_SECONDS" | awk '{printf "%.2f", $1/3600}')
    printf '  💻 %-20s ' "Terminal (shell)"
    echo "$SHELL_HOURS" | awk '{printf "%.1fh\n", $1}'
fi

TOTAL_SECONDS=$(aw_total_time "$(aw_today_start)" "$(aw_today_end)" 2>/dev/null || echo 0)
# Use awk for float comparison
if awk -v t="$TOTAL_SECONDS" 'BEGIN {exit !(t > 0)}'; then
    printf '  ────────────────────\n'
    aw_format_duration "$TOTAL_SECONDS" | xargs -I{} printf '  Total: %s\n' "{}"
else
    echo -e "  ${D}(Sin datos para hoy)${N}"
fi

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

# Filter out unknown apps
events = [e for e in events if e['data'].get('app') != 'unknown']

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

aw_aggregate_by_language "$(aw_today_start)" "$(aw_today_end)" | while IFS='|' read -r val lang; do
    [[ -z "$val" ]] && continue
    if [[ "$lang" == *m ]]; then
        lang="${lang%m}"
        printf '  📝 %-15s ' "$lang"
        echo "$val" | awk '{printf "%.1fm\n", $1}'
    else
        printf '  📝 %-15s ' "$lang"
        echo "$val" | awk '{printf "%.1fh\n", $1}'
    fi
done

# If no vim data, check if bucket exists
if ! aw_aggregate_by_language "$(aw_today_start)" "$(aw_today_end)" | grep -q '|'; then
    echo -e "  ${D}Sin datos de editor${N}"
fi

echo ""

# --- Dentro de la Terminal (desglose) ---
echo -e "  ${B}━━━ DENTRO DE LA TERMINAL ━━━━━━━━━━━━━━━━━${N}"
echo ""

# Get shell events with command breakdown and estimate time per command
cd /home/verodg/.local/bin/tdo-hub/scripts && bash -c "source ./aw_client.sh && aw_get_shell_events \"\$(date -d 'today 00:00:00' -u +%Y-%m-%dT%H:%M:%SZ)\" \"\$(date -d 'today 23:59:59' -u +%Y-%m-%dT%H:%M:%SZ)\"" | python3 -c "
import sys, json
from collections import defaultdict

events = json.load(sys.stdin)
cmd_counts = defaultdict(int)
heartbeats = 0

for e in events:
    data = e.get('data', {})
    if data.get('heartbeat'):
        heartbeats += 1
    else:
        cmd = data.get('command', '')
        if cmd:
            cmd_counts[cmd] += 1

# Each heartbeat = 30s. Distribute proportionally by command frequency.
total_cmds = sum(cmd_counts.values())
if total_cmds > 0 and heartbeats > 0:
    secs_per_heartbeat = 30
    total_secs = heartbeats * secs_per_heartbeat
    for cmd, count in sorted(cmd_counts.items(), key=lambda x: -x[1])[:10]:
        pct = count / total_cmds
        cmd_secs = total_secs * pct
        if cmd_secs >= 60:
            print(f'{cmd_secs/60:.1f}|{cmd}m')
        else:
            print(f'{cmd_secs:.0f}|{cmd}s')
elif heartbeats > 0:
    print(f'{heartbeats * 30}|terminal-only')
" 2>/dev/null | while IFS='|' read -r val cmd; do
    [[ -z "$val" ]] && continue
    if [[ "$cmd" == *m ]]; then
        cmd="${cmd%m}"
        printf '  💻 %-15s ' "$cmd"
        echo "$val" | awk '{printf "%.1fm\n", $1}'
    elif [[ "$cmd" == *s ]]; then
        cmd="${cmd%s}"
        printf '  💻 %-15s ' "$cmd"
        echo "$val" | awk '{printf "%ds\n", $1}'
    else
        printf '  💻 %-15s ' "$cmd"
        echo "$val" | awk '{printf "%.1fm\n", $1}'
    fi
done

# If no breakdown available
if ! cd /home/verodg/.local/bin/tdo-hub/scripts && bash -c "source ./aw_client.sh && aw_get_shell_events \"\$(date -d 'today 00:00:00' -u +%Y-%m-%dT%H:%M:%SZ)\" \"\$(date -d 'today 23:59:59' -u +%Y-%m-%dT%H:%M:%SZ)\"" | python3 -c "
import sys, json
events = json.load(sys.stdin)
has_data = any(not e.get('data', {}).get('heartbeat') and e.get('data', {}).get('command') for e in events)
print('HAS_DATA' if has_data else 'NO_DATA')
" 2>/dev/null | grep -q 'HAS_DATA'; then
    echo -e "  ${D}(Ejecutá comandos para ver desglose)${N}"
fi

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