#!/usr/bin/env bash
# ==========================================================
# 📅 RUTINA DIARIA
# ==========================================================

source "$(dirname "$0")/../core.sh"

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
    local AW_BASE="$(resolve_aw_api 2>/dev/null || true)"
    [ -z "$AW_BASE" ] && return
    local API="$AW_BASE/api/0"
    local TODAY=$(date +%Y-%m-%d)
    local DATA=$(curl -sL --connect-timeout 2 -m 10 "$API/buckets/${AW_BUCKET_WINDOW:-aw-watcher-window_$(hostname)}/events?limit=2000" 2>>"$HUB_ROOT/.tdo.log")
    [[ -z "$DATA" || "$DATA" == "[]" ]] && return
    local MSG=$(echo "$DATA" | python3 -c "
import sys, json
from collections import defaultdict
events = [e for e in json.load(sys.stdin) if e['timestamp'][:10] == '$TODAY']
totals = defaultdict(float)
for e in events: totals[e['data'].get('app','?')] += e['duration']
total = sum(totals.values())
switches = sum(1 for i in range(1,len(events)) if events[i]['data'].get('app')!=events[i-1]['data'].get('app'))
top = max(totals, key=totals.get) if totals else '?'
print(f'{total/60:.0f}m activo | {switches} switches | Top: {top}')
" 2>>"$HUB_ROOT/.tdo.log")
    [[ -n "$MSG" ]] && p "${BOLD}📊 ActivityWatch:${RST} $MSG"
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
