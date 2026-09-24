#!/usr/bin/env bash
# ==========================================================
# 📋 WEEKLY REVIEW - Genera revisión semanal automática
# ==========================================================
#
# Crea nota en $WEEKLY_REVIEW_DIR/YYYY-WW.md con:
# - Stats ActivityWatch (apps, focus, switches)
# - Tareas completadas / pendientes / recurrencia
# - Journal highlights de la semana
# - Preguntas de reflexión
# - Métricas de productividad
#
# Config en .env:
#   WEEKLY_REVIEW_TEMPLATE, WEEKLY_REVIEW_DIR
# ==========================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
source "$SCRIPT_DIR/../core.sh"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/aw_client.sh"

ENV_FILE="$HUB_ROOT/.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

WEEKLY_TEMPLATE="${WEEKLY_REVIEW_TEMPLATE:-$TEMPLATES_DIR/weekly-review.md}"
WEEKLY_DIR="${WEEKLY_REVIEW_DIR:-$NOTES_DIR/02_areas/personal/reviews}"
mkdir -p "$WEEKLY_DIR"

# =========== CLI ARGS ===========
ACTION="${1:-generate}"
REF_DATE="${2:-$(date +%Y-%m-%d)}"

# =========== CALCULAR FECHAS (global, usado por todas las funciones) ===========
WEEK_START=$(date -d "$REF_DATE -$(date -d "$REF_DATE" +%u) days +1 day" +%Y-%m-%d 2>/dev/null || date -j -v+1d -v-monday -f "%Y-%m-%d" "$REF_DATE" +%Y-%m-%d 2>/dev/null)
WEEK_END=$(date -d "$WEEK_START +6 days" +%Y-%m-%d 2>/dev/null || date -j -v+6d -f "%Y-%m-%d" "$WEEK_START" +%Y-%m-%d 2>/dev/null)
WEEK_NUM=$(date -d "$WEEK_START" +%V 2>/dev/null || date -j -f "%Y-%m-%d" "$WEEK_START" +%V 2>/dev/null)
YEAR=$(date -d "$WEEK_START" +%Y 2>/dev/null || date -j -f "%Y-%m-%d" "$WEEK_START" +%Y)
OUTPUT_FILE="$WEEKLY_DIR/${YEAR}-W${WEEK_NUM}.md"

# Colores
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'
log() { echo -e "${B}[WEEKLY]${N} $*"; }
ok() { echo -e "${G}[WEEKLY]${N} $*"; }
warn() { echo -e "${Y}[WEEKLY]${N} $*"; }

# =========== RECOPILAR DATOS ===========

# --- 1. ActivityWatch Stats ---
get_aw_weekly() {
    aw_is_running || { echo "ActivityWatch no disponible"; return; }
    
    local start_iso=$(date -d "$WEEK_START 00:00:00" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -j -f "%Y-%m-%d" "$WEEK_START 00:00:00" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
    local end_iso=$(date -d "$WEEK_END 23:59:59" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -j -f "%Y-%m-%d" "$WEEK_END 23:59:59" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
    
    # Top apps
    local top_apps=$(aw_aggregate_by_app_simple "$start_iso" "$end_iso" 2>/dev/null | head -10)
    
    # Total time
    local total_sec=$(aw_total_time "$start_iso" "$end_iso" 2>/dev/null || echo 0)
    local total_h=$(awk "BEGIN {printf \"%.1f\", $total_sec/3600}")
    
    # Switches
    local switches=$(curl -sL --connect-timeout 2 -m 10 "$(_aw_resolve_api)/api/0/buckets/$AW_BUCKET_WINDOW/events?limit=5000" 2>/dev/null | python3 -c "
import sys, json, datetime
events = json.load(sys.stdin)
week_start = datetime.date.fromisoformat('$WEEK_START')
week_end = datetime.date.fromisoformat('$WEEK_END')
switches = 0
prev_app = None
for e in events:
    ts = e['timestamp'][:10]
    if week_start <= datetime.date.fromisoformat(ts) <= week_end:
        app = e['data'].get('app', 'unknown')
        if app != 'unknown' and app != prev_app:
            switches += 1
        prev_app = app
print(switches)
" 2>/dev/null || echo 0)
    
    # Focus sessions (duración > 25min en misma app)
    local focus_sessions=$(curl -sL --connect-timeout 2 -m 10 "$(_aw_resolve_api)/api/0/buckets/$AW_BUCKET_WINDOW/events?limit=5000" 2>/dev/null | python3 -c "
import sys, json, datetime
events = json.load(sys.stdin)
week_start = datetime.date.fromisoformat('$WEEK_START')
week_end = datetime.date.fromisoformat('$WEEK_END')
sessions = 0
current_app = None
current_start = None
current_dur = 0
for e in events:
    ts = e['timestamp'][:10]
    if not (week_start <= datetime.date.fromisoformat(ts) <= week_end):
        continue
    app = e['data'].get('app', 'unknown')
    dur = e.get('duration', 0)
    if app == 'unknown': continue
    if app == current_app:
        current_dur += dur
    else:
        if current_app and current_dur >= 1500:  # 25 min
            sessions += 1
        current_app = app
        current_dur = dur
if current_app and current_dur >= 1500:
    sessions += 1
print(sessions)
" 2>/dev/null || echo 0)
    
    cat <<EOF
## 📊 ActivityWatch (Semana $WEEK_NUM)

**Tiempo total:** ${total_h}h | **Focus sessions (>25min):** $focus_sessions | **Context switches:** $switches

### Top Apps
$top_apps
EOF
}

# --- 2. Tareas ---
get_tasks_weekly() {
    [[ ! -f "$TODO_ACTIVO" ]] && { echo "Sin archivo de tareas"; return; }
    
    local done_this_week=$(grep "\[x\] $WEEK_START" "$TODO_ACTIVO" 2>/dev/null || true)
    local done_this_week=$(grep "\[x\]" "$TODO_ACTIVO" 2>/dev/null | grep -E "($(date -d "$WEEK_START" +%Y-%m-%d)|$(date -d "$WEEK_START +1 day" +%Y-%m-%d)|$(date -d "$WEEK_START +2 day" +%Y-%m-%d)|$(date -d "$WEEK_START +3 day" +%Y-%m-%d)|$(date -d "$WEEK_START +4 day" +%Y-%m-%d)|$(date -d "$WEEK_START +5 day" +%Y-%m-%d)|$(date -d "$WEEK_END" +%Y-%m-%d))" 2>/dev/null || true)
    
    # Mejor: buscar líneas con fechas en la semana
    local done_count=0
    local done_list=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local task_date=$(echo "$line" | grep -oE '\[x\] [0-9]{4}-[0-9]{2}-[0-9]{2}' | cut -d' ' -f2)
        if [[ -n "$task_date" ]] && [[ "$task_date" > "$WEEK_START" ]] && [[ "$task_date" < "$(date -d "$WEEK_END +1 day" +%Y-%m-%d)" ]]; then
            done_count=$((done_count + 1))
            local desc=$(echo "$line" | sed 's/^- \[x\] [0-9-]* //')
            done_list+="  - $desc\n"
        fi
    done < <(grep "^\s*-\s*\[x\]" "$TODO_ACTIVO" 2>/dev/null)
    
    local pending=$(grep "^\s*-\s*\[ \]" "$TODO_ACTIVO" 2>/dev/null | wc -l)
    local high_prio=$(grep "^\s*-\s*\[ \]\s*!!" "$TODO_ACTIVO" 2>/dev/null | wc -l)
    local med_prio=$(grep "^\s*-\s*\[ \]\s*!" "$TODO_ACTIVO" 2>/dev/null | grep -v "!!" | wc -l)
    
    # Tareas recurrentes completadas
    local recur_done=$(grep "repeat:" "$TODO_TRASH" 2>/dev/null | grep -E "($(date -d "$WEEK_START" +%Y-%m-%d)|$(date -d "$WEEK_END" +%Y-%m-%d))" 2>/dev/null | wc -l)
    
    cat <<EOF
## ✅ Tareas

**Completadas esta semana:** $done_count | **Pendientes:** $pending (🔴 $high_prio | 🟡 $med_prio) | **Recurrentes:** $recur_done

### Completadas
$done_list
EOF
}

# --- 3. Journal Highlights ---
get_journal_weekly() {
    local highlights=""
    local count=0
    
    for i in {0..6}; do
        local day=$(date -d "$WEEK_START +$i days" +%Y-%m-%d 2>/dev/null || date -j -v+${i}d -f "%Y-%m-%d" "$WEEK_START" +%Y-%m-%d 2>/dev/null)
        local jfile="$JOURNAL_DIR/$(date -d "$day" +%Y 2>/dev/null)/$(date -d "$day" +%m 2>/dev/null)/$day.md"
        [[ ! -f "$jfile" ]] && continue
        
        # Extraer líneas con checkboxes marcados o secciones destacadas
        local day_highlights=$(grep -E "^\s*-\s*\[x\]|^##\s+" "$jfile" 2>/dev/null | head -3 | sed 's/^/    /')
        if [[ -n "$day_highlights" ]]; then
            highlights+="### $(date -d "$day" +%a\ %d 2>/dev/null)
$day_highlights

"
            count=$((count + 1))
        fi
    done
    
    [[ $count -eq 0 ]] && highlights="  *Sin entries de journal esta semana*"
    
    cat <<EOF
## 📓 Journal Highlights ($count días con contenido)
$highlights
EOF
}

# --- 4. Métricas derivadas (calculadas directamente) ---
get_metrics() {
    # Obtener datos AW directamente
    local start_iso=$(date -d "$WEEK_START 00:00:00" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -j -f "%Y-%m-%d" "$WEEK_START 00:00:00" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
    local end_iso=$(date -d "$WEEK_END 23:59:59" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -j -f "%Y-%m-%d" "$WEEK_END 23:59:59" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
    
    local aw_data=""
    aw_is_running && aw_data=$(aw_aggregate_by_app_simple "$start_iso" "$end_iso" 2>/dev/null)
    
    local total_sec=0
    local total_h=0
    local focus_sess=0
    local switches=0
    
    if [[ -n "$aw_data" ]]; then
        total_sec=$(echo "$aw_data" | awk -F'|' '{sum+=$1*3600} END {print int(sum)}')
        total_h=$(awk "BEGIN {printf \"%.1f\", $total_sec/3600}")
        
        # Focus sessions
        focus_sess=$(curl -sL --connect-timeout 2 -m 10 "$(_aw_resolve_api)/api/0/buckets/$AW_BUCKET_WINDOW/events?limit=5000" 2>/dev/null | python3 -c "
import sys, json, datetime
events = json.load(sys.stdin)
week_start = datetime.date.fromisoformat('$WEEK_START')
week_end = datetime.date.fromisoformat('$WEEK_END')
sessions = 0
current_app = None
current_dur = 0
for e in events:
    ts = e['timestamp'][:10]
    if not (week_start <= datetime.date.fromisoformat(ts) <= week_end):
        continue
    app = e['data'].get('app', 'unknown')
    dur = e.get('duration', 0)
    if app == 'unknown': continue
    if app == current_app:
        current_dur += dur
    else:
        if current_app and current_dur >= 1500:
            sessions += 1
        current_app = app
        current_dur = dur
if current_app and current_dur >= 1500:
    sessions += 1
print(sessions)
" 2>/dev/null || echo 0)
        
        # Switches
        switches=$(curl -sL --connect-timeout 2 -m 10 "$(_aw_resolve_api)/api/0/buckets/$AW_BUCKET_WINDOW/events?limit=5000" 2>/dev/null | python3 -c "
import sys, json, datetime
events = json.load(sys.stdin)
week_start = datetime.date.fromisoformat('$WEEK_START')
week_end = datetime.date.fromisoformat('$WEEK_END')
switches = 0
prev_app = None
for e in events:
    ts = e['timestamp'][:10]
    if week_start <= datetime.date.fromisoformat(ts) <= week_end:
        app = e['data'].get('app', 'unknown')
        if app != 'unknown' and app != prev_app:
            switches += 1
        prev_app = app
print(switches)
" 2>/dev/null || echo 0)
    fi
    
    # Tasks
    local done_count=0
    local done_list=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local task_date=$(echo "$line" | grep -oE '\[x\] [0-9]{4}-[0-9]{2}-[0-9]{2}' | cut -d' ' -f2)
        if [[ -n "$task_date" ]] && [[ "$task_date" > "$WEEK_START" ]] && [[ "$task_date" < "$(date -d "$WEEK_END +1 day" +%Y-%m-%d)" ]]; then
            done_count=$((done_count + 1))
        fi
    done < <(grep "^\s*-\s*\[x\]" "$TODO_ACTIVO" 2>/dev/null)
    
    local pending=$(grep "^\s*-\s*\[ \]" "$TODO_ACTIVO" 2>/dev/null | wc -l)
    local high_prio=$(grep "^\s*-\s*\[ \]\s*!!" "$TODO_ACTIVO" 2>/dev/null | wc -l)
    local med_prio=$(grep "^\s*-\s*\[ \]\s*!" "$TODO_ACTIVO" 2>/dev/null | grep -v "!!" | wc -l)
    
    # Focus score
    local focus_score=0
    if [[ $total_sec -gt 0 ]]; then
        local focus_ratio=$(awk "BEGIN {printf \"%.2f\", $focus_sess*25/($total_sec/60)}")
        local switch_penalty=$(awk "BEGIN {printf \"%.0f\", $switches/10}")
        focus_score=$(awk "BEGIN {printf \"%.0f\", $focus_ratio*100 - $switch_penalty}")
        [[ $focus_score -lt 0 ]] && focus_score=0
        [[ $focus_score -gt 100 ]] && focus_score=100
    fi
    
    local ratio="N/A"
    [[ $pending -gt 0 ]] && ratio=$(awk "BEGIN {printf \"%.1f\", $done_count/$pending}")
    
    cat <<EOF
## 📈 Métricas

| Métrica | Valor |
|---------|-------|
| **Focus Score** | $focus_score/100 |
| **Horas trackeadas** | ${total_h}h |
| **Focus sessions** | $focus_sess |
| **Context switches** | $switches |
| **Tasks done** | $done_count |
| **Tasks pending** | $pending |
| **Ratio done/pending** | $ratio |

**Interpretación Focus Score:**
- 80-100: 🟢 Deep work consistente
- 60-79: 🟡 Buen foco, algunos switches
- 40-59: 🟠 Fragmentado, revisar distracciones
- <40: 🔴 Muy reactivo, activar focus_mode
EOF
}

# --- 5. Preguntas de reflexión ---
get_reflection() {
    cat <<EOF
## 🤔 Reflexión Semanal

### Qué funcionó bien
- 

### Qué mejorar
- 

### Energía / Salud
- Sueño: 
- Ejercicio: 
- Estrés (1-10): 

### Próxima semana
- **Top 3 prioridades:**
  1. 
  2. 
  3. 
- **Habit tracker:**
  - [ ] 
  - [ ] 
  - [ ] 

### Notas / Ideas
- 
EOF
}

# =========== GENERAR ARCHIVO ===========

generate_review() {
    log "Generando weekly review: $WEEK_START a $WEEK_END (Semana $WEEK_NUM/$YEAR)"
    
    # Generar contenido directamente (evita problemas de sed con multilínea)
    {
        echo "# Weekly Review - ${YEAR}-W${WEEK_NUM}"
        echo ""
        echo "${WEEK_START} a ${WEEK_END}"
        echo ""
        get_aw_weekly
        echo ""
        get_tasks_weekly
        echo ""
        get_journal_weekly
        echo ""
        get_metrics
        echo ""
        get_reflection
    } > "$OUTPUT_FILE"
    
    ok "Weekly review creada: $OUTPUT_FILE"
}

# =========== CLI ===========

case "$ACTION" in
    generate) generate_review ;;
    open) generate_review && nvim "$OUTPUT_FILE" ;;
    --help|-h)
        cat <<EOF
Uso: weekly-review.sh [generate|open] [YYYY-MM-DD]

  generate [fecha]  - Genera review para semana de la fecha (default: hoy)
  open [fecha]      - Genera y abre en nvim
  --help            - Esta ayuda

La fecha determina la semana (lunes-domingo).
Archivo salida: $WEEKLY_DIR/YYYY-WWW.md

Template opcional: $WEEKLY_TEMPLATE
Variables: {{year}}, {{week}}, {{date_range}}, {{aw_stats}}, {{tasks}}, {{journal}}, {{metrics}}, {{reflection}}
EOF
        ;;
    *) err "Acción desconocida: $1"; exit 1 ;;
esac