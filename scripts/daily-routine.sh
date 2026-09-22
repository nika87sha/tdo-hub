#!/usr/bin/env bash
# ==========================================================
# 📅 RUTINA DIARIA
# ==========================================================

source "$(dirname "$0")/../core.sh"
source "$(dirname "$0")/aw_client.sh"

BOLD='\033[1m'
DIM='\033[2m'
RST='\033[0m'

p() { echo -e "$@"; }

create_daily_entry() {
    local ARCHIVO="$JOURNAL_DIR/$(date +%Y)/$(date +%m)/$(date +%Y-%m-%d).md"
    [[ ! -f "$ARCHIVO" ]] && {
        mkdir -p "$(dirname "$ARCHIVO")"
        apply_template "$TEMPLATES_DIR/entry.md" "$ARCHIVO" "Diario $(date +%F)"
    }
}

get_priority_tasks() {
    [[ ! -f "$TODO_ACTIVO" ]] && return
    p "${BOLD}📌 Tareas Pendientes:${RST}"
    grep -E "^\s*-\s*\[" "$TODO_ACTIVO" | head -8 | while IFS= read -r line; do
        local desc=$(echo "$line" | sed 's/^[[:space:]]*- \[.\] //')
        local icon="⭕"
        echo "$line" | grep -qE '^\s*-\s*\[.\]\s*!!' && icon="🔴"
        echo "$line" | grep -qE '^\s*-\s*\[.\]\s*!' && icon="🟡"
        echo "$line" | grep -q "\[x\]" && icon="✅"
        p "  $icon $desc"
    done
}

get_yesterday_stats() {
    local YESTERDAY=$(date -d "1 day ago" +%Y-%m-%d)
    local JOUR="$JOURNAL_DIR/$(date -d "$YESTERDAY" +%Y)/$(date -d "$YESTERDAY" +%m)/$YESTERDAY.md"
    if [[ -f "$JOUR" ]]; then
        local HABITS=$(grep -c "\[x\]" "$JOUR" 2>/dev/null | tr -d '[:space:]')
        [[ "$HABITS" =~ ^[0-9]+$ && "$HABITS" -gt 0 ]] && p "${BOLD}📊 Ayer:${RST} $HABITS hábitos completados"
    fi
}

show_aw_summary() {
    aw_is_running || return
    local TOTAL_SECONDS=$(aw_total_time "$(aw_today_start)" "$(aw_today_end)" 2>/dev/null || echo 0)
    [[ "$TOTAL_SECONDS" -eq 0 ]] && return
    
    local TOP_APP=$(aw_summary_today | head -1 | cut -d'|' -f2)
    local TOTAL_HOURS=$(echo "$TOTAL_SECONDS / 3600" | bc -l)
    local MINS=$(echo "$TOTAL_HOURS * 60" | bc -l | cut -d. -f1)
    
    # Count switches - simplified
    local EVENTS=$(aw_get_events "$AW_BUCKET_WINDOW" "$(aw_today_start)" "$(aw_today_end)" 2>/dev/null)
    local SWITCHES=0
    if [[ -n "$EVENTS" && "$EVENTS" != "[]" ]]; then
        SWITCHES=$(echo "$EVENTS" | python3 -c "
import sys, json
events = json.load(sys.stdin)
switches = sum(1 for i in range(1,len(events)) if events[i]['data'].get('app')!=events[i-1]['data'].get('app'))
print(switches)
" 2>/dev/null || echo 0)
    fi
    
    p "${BOLD}📊 ActivityWatch:${RST} ${MINS}m activo | ${SWITCHES} switches | Top: ${TOP_APP}"
}

show_brain() {
    local P=$(grep -h "^- " "$NOTES_DIR/00_inbox/brain_dump/dump_"*.md 2>/dev/null | grep -v "✅" | wc -l)
    [[ "$P" -gt 0 ]] && p "${BOLD}🧠 Brain:${RST} $P ideas sin triar — Hub (SUPER+N) → 📥 Organizar"
    [[ "$P" -eq 0 ]] && p "${BOLD}🧠 Brain:${RST} limpio ✅"
}
show_unsync() {
    command -v git &>/dev/null && [[ -d "$NOTES_DIR/.git" ]] || return
    local N=$(cd "$NOTES_DIR" && git status --porcelain 2>/dev/null | wc -l)
    [[ "$N" -gt 0 ]] && p "${BOLD}⚠️  Sync:${RST} $N archivos pendientes"
}

main() {
    create_daily_entry
    [[ "$1" == "--sync" ]] && cd "$NOTES_DIR" && git add -A && git commit -m "🔄 Auto-sync $(date +%F)" --quiet 2>/dev/null

    clear
    p "${BOLD}═══════════════════════════════════════${RST}"
    p "${BOLD}🌅 $(date +%A,\ %d\ de\ %B)${RST}"
    p "${BOLD}═══════════════════════════════════════${RST}"
    echo ""
    get_priority_tasks
    echo ""
    get_yesterday_stats
    show_aw_summary
    show_brain
    show_unsync
    echo ""
    p "${BOLD}═══════════════════════════════════════${RST}"
    p "💡 ${DIM}tdo → menú | Ctrl+A → m → captura${RST}"
    p "${BOLD}═══════════════════════════════════════${RST}"
}

main "$@"
