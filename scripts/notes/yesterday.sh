#!/usr/bin/env bash
# ==========================================================
# 🔙 ¿QUÉ ESTABA HACIENDO AYER?
# Resumen rápido: AW + último journal + tareas pendientes
# Para cuando abres la terminal y no sabes por dónde seguir
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
source "$SCRIPT_DIR/../../core.sh"
source "$SCRIPT_DIR/../lib/aw_client.sh"

# Si viene de un atajo (sin terminal), mostrarse en tmux
tmux_run_script "ayer" "$0" "$@"

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

echo ""
echo -e "  ${W}╔══════════════════════════════════════════════════╗${N}"
echo -e "  ${W}║${N}  ${C}🔙 ¿QUÉ ESTABA HACIENDO AYER?${N}                  ${W}║${N}"
echo -e "  ${W}╚══════════════════════════════════════════════════╝${N}"
echo ""

# --- 1. Actividad de ayer (AW) ---
echo -e "  ${G}━━━ ACTIVIDAD DE AYER ━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""

aw_summary_yesterday | while IFS='|' read -r hours app; do
    [[ -z "$hours" ]] && continue
    icon="📱"
    case "$app" in
        firefox|chrome|brave) icon="🦊" ;;
        Alacritty|kitty|gnome-terminal) icon="💻" ;;
        Thunderbird|evolution) icon="📧" ;;
        nvim|vim|code) icon="📝" ;;
    esac
    printf '  %s %-20s %5.1fh\n' "$icon" "$app" "$hours"
done

TOTAL_HOURS=$(aw_total_time "$(aw_yesterday_start)" "$(aw_yesterday_end)" 2>/dev/null || echo 0)
if [[ "$TOTAL_HOURS" -gt 0 ]]; then
    printf '  ────────────────────\n'
    aw_format_duration "$TOTAL_HOURS" | xargs -I{} printf '  Total: %s\n' "{}"
else
    echo -e "  ${D}(AW no disponible o sin datos)${N}"
fi

echo ""

# --- 2. Journal de ayer ---
echo -e "  ${Y}━━━ JOURNAL DE AYER ━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""

# JOURNAL_DIR ya viene de config.sh
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

ACTIVE_TODO="${TODO_ACTIVO}"

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
