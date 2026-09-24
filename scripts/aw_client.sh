#!/usr/bin/env bash
# ==========================================================
# 📊 AW_CLIENT - Cliente unificado para ActivityWatch
# Elimina duplicación en yesterday.sh, aw-stats.sh, flow-detect.sh, daily-routine.sh
# ==========================================================

# BASH_SOURCE: funciona al sourcearse desde cualquier script ($0 sería el padre)
source "$(dirname "${BASH_SOURCE[0]}")/../core.sh"

# =========== CONFIGURACIÓN ===========
AW_API_BASE="${AW_API_BASE:-}"
AW_HOSTNAME="${AW_HOSTNAME:-$(hostname)}"
AW_BUCKET_WINDOW="${AW_BUCKET_WINDOW:-aw-watcher-window_${AW_HOSTNAME}}"
AW_BUCKET_VIM="${AW_BUCKET_VIM:-aw-watcher-vim_${AW_HOSTNAME}}"
AW_BUCKET_SHELL="${AW_BUCKET_SHELL:-aw-shell-zsh_${AW_HOSTNAME}}"

# =========== CONEXIÓN ===========
# Resuelve y cachea la URL base de AW
_aw_resolve_api() {
    [[ -n "$AW_API_BASE" ]] && echo "$AW_API_BASE" && return 0
    
    local candidates=(
        "${AW_SERVER_URL:-}"
        "${AW_DEFAULT_SERVER:-}"
        "${AW_FALLBACK_URL:-}"
        "${AW_FALLBACK_SERVER:-http://localhost:5600}"
        "http://localhost:5600"
    )
    
    for url in "${candidates[@]}"; do
        [[ -z "$url" ]] && continue
        if curl -sL --connect-timeout 2 -o /dev/null "$url/api/0/buckets" 2>/dev/null; then
            AW_API_BASE="$url"
            echo "$url"
            return 0
        fi
    done
    return 1
}

# Verificar disponibilidad de AW
aw_check() {
    _aw_resolve_api >/dev/null
}

# =========== CONSULTAS BASE ===========
# Obtener eventos de un bucket en rango de tiempo
# aw_get_events "bucket_name" "start_iso" "end_iso" [limit]
aw_get_events() {
    local bucket="$1"
    local start="$2"
    local end="$3"
    local limit="${4:-10000}"
    
    local api_base=$(_aw_resolve_api) || return 1
    curl -sL --connect-timeout 5 "${api_base}/api/0/buckets/${bucket}/events" \
        -G -d "start=$start" -d "end=$end" -d "limit=$limit" 2>/dev/null
}

# Obtener todos los buckets
aw_get_buckets() {
    local api_base=$(_aw_resolve_api) || return 1
    curl -sL --connect-timeout 2 "${api_base}/api/0/buckets" 2>/dev/null
}

# =========== AGREGACIONES COMUNES ===========
# Agregar eventos por aplicación (ventana activa)
# aw_aggregate_by_app "start_iso" "end_iso" [bucket]
aw_aggregate_by_app() {
    local start="$1"
    local end="$2"
    local bucket="${3:-$AW_BUCKET_WINDOW}"
    
    local events=$(aw_get_events "$bucket" "$start" "$end") || return 1
    
    # Procesar con awk: extraer app, sumar duración
    printf '%s\n' "$events" | python3 -c "
import sys, json
events = json.load(sys.stdin)
apps = {}
for e in events:
    data = e.get('data', {})
    app = data.get('app', 'unknown')
    title = data.get('title', '')
    dur = e.get('duration', 0)
    key = f'{app}|{title}'
    apps[key] = apps.get(key, 0) + dur

for key, total in sorted(apps.items(), key=lambda x: -x[1]):
    app, title = key.split('|', 1)
    hours = total / 3600
    if hours >= 0.01:
        print(f'{hours:.2f}|{app}|{title}')
"
}

# Agregar eventos por aplicación (solo nombre app, sin título)
aw_aggregate_by_app_simple() {
    local start="$1"
    local end="$2"
    local bucket="${3:-$AW_BUCKET_WINDOW}"
    
    local events=$(aw_get_events "$bucket" "$start" "$end") || return 1
    
    printf '%s\n' "$events" | python3 -c "
import sys, json
events = json.load(sys.stdin)
apps = {}
for e in events:
    data = e.get('data', {})
    app = data.get('app', 'unknown')
    dur = e.get('duration', 0)
    apps[app] = apps.get(app, 0) + dur

for app, total in sorted(apps.items(), key=lambda x: -x[1]):
    hours = total / 3600
    if hours >= 0.01:
        print(f'{hours:.2f}|{app}')
"
}

# Obtener tiempo total en rango (returns integer seconds)
aw_total_time() {
    local start="$1"
    local end="$2"
    local bucket="${3:-$AW_BUCKET_WINDOW}"
    
    local events=$(aw_get_events "$bucket" "$start" "$end") || return 1
    
    printf '%s\n' "$events" | python3 -c "
import sys, json
events = json.load(sys.stdin)
total = sum(e.get('duration', 0) for e in events)
print(int(total))
"
}

# =========== FORMATOS DE TIEMPO ===========
# Convertir segundos a formato legible
aw_format_duration() {
    local seconds="$1"
    local hours=$((seconds / 3600))
    local mins=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    
    if [[ $hours -gt 0 ]]; then
        printf '%dh %dm' "$hours" "$mins"
    elif [[ $mins -gt 0 ]]; then
        printf '%dm %ds' "$mins" "$secs"
    else
        printf '%ds' "$secs"
    fi
}

# ISO timestamp para hoy
aw_today_start() {
    date -d "$(date +%Y-%m-%d) 00:00:00" -u +%Y-%m-%dT%H:%M:%SZ
}

aw_today_end() {
    date -d "$(date +%Y-%m-%d) 23:59:59" -u +%Y-%m-%dT%H:%M:%SZ
}

# ISO timestamp para ayer
aw_yesterday_start() {
    date -d "yesterday 00:00:00" -u +%Y-%m-%dT%H:%M:%SZ
}

aw_yesterday_end() {
    date -d "yesterday 23:59:59" -u +%Y-%m-%dT%H:%M:%SZ
}

# ISO timestamp para hace N días
aw_days_ago_start() {
    local days="$1"
    date -d "$days days ago 00:00:00" -u +%Y-%m-%dT%H:%M:%SZ
}

aw_days_ago_end() {
    local days="$1"
    date -d "$days days ago 23:59:59" -u +%Y-%m-%dT%H:%M:%SZ
}

# =========== QUERYS DE ALTO NIVEL ===========
# Resumen de hoy
aw_summary_today() {
    aw_aggregate_by_app_simple "$(aw_today_start)" "$(aw_today_end)"
}

# Resumen de ayer
aw_summary_yesterday() {
    aw_aggregate_by_app_simple "$(aw_yesterday_start)" "$(aw_yesterday_end)"
}

# Resumen de últimos N días
aw_summary_last_days() {
    local days="$1"
    local start=$(aw_days_ago_start "$days")
    local end=$(aw_today_end)
    aw_aggregate_by_app_simple "$start" "$end"
}

# Detectar flow state (ventana única por mucho tiempo)
aw_detect_flow() {
    local min_minutes="${1:-15}"
    local min_seconds=$((min_minutes * 60))
    local start=$(aw_today_start)
    local end=$(aw_today_end)
    
    local events=$(aw_get_events "$AW_BUCKET_WINDOW" "$start" "$end") || return 1
    
    printf '%s\n' "$events" | python3 -c "
import sys, json
events = json.load(sys.stdin)
min_dur = $min_seconds

current_app = None
current_title = None
current_start = None
current_dur = 0

for e in events:
    data = e.get('data', {})
    app = data.get('app', 'unknown')
    title = data.get('title', '')
    dur = e.get('duration', 0)
    timestamp = e.get('timestamp', '')
    
    key = f'{app}|{title}'
    
    if key == current_app:
        current_dur += dur
    else:
        if current_app and current_dur >= min_dur:
            print(f'{current_dur}|{current_app}|{current_start}')
        current_app = key
        current_title = title
        current_start = timestamp
        current_dur = dur

if current_app and current_dur >= min_dur:
    print(f'{current_dur}|{current_app}|{current_start}')
"
}

# Obtener eventos de vim/nvim
aw_get_vim_events() {
    local start="$1"
    local end="$2"
    aw_get_events "$AW_BUCKET_VIM" "$start" "$end"
}

# Obtener eventos de shell (comandos ejecutados)
aw_get_shell_events() {
    local start="$1"
    local end="$2"
    aw_get_events "$AW_BUCKET_SHELL" "$start" "$end"
}

# Agregar eventos por lenguaje (vim/nvim) - usa heartbeats (duración 0 = 30s pulsetime)
aw_aggregate_by_language() {
    local start="$1"
    local end="$2"
    local bucket="${3:-$AW_BUCKET_VIM}"
    
    local events=$(aw_get_events "$bucket" "$start" "$end") || return 1
    
    printf '%s\n' "$events" | python3 -c "
import sys, json
events = json.load(sys.stdin)
langs = {}
for e in events:
    data = e.get('data', {})
    lang = data.get('language', '')
    if lang and lang != 'NvimTree':
        # Heartbeats have duration 0, each represents 30s (pulsetime)
        dur = e.get('duration', 0)
        if dur == 0:
            dur = 30  # pulsetime
        langs[lang] = langs.get(lang, 0) + dur

for lang, total in sorted(langs.items(), key=lambda x: -x[1]):
    hours = total / 3600
    if total >= 60:  # at least 1 minute
        print(f'{hours:.2f}|{lang}')
    elif total > 0:
        mins = total / 60
        print(f'{mins:.2f}|{lang}m')  # 'm' suffix for minutes
"
}

# Agregar comandos de shell
aw_aggregate_shell_commands() {
    local start="$1"
    local end="$2"
    local bucket="${3:-$AW_BUCKET_SHELL}"
    
    local events=$(aw_get_events "$bucket" "$start" "$end") || return 1
    
    printf '%s\n' "$events" | python3 -c "
import sys, json
events = json.load(sys.stdin)
cmds = {}
for e in events:
    data = e.get('data', {})
    cmd = data.get('command', '')
    if cmd and not data.get('heartbeat'):
        dur = e.get('duration', 0)
        cmds[cmd] = cmds.get(cmd, 0) + 1

for cmd, count in sorted(cmds.items(), key=lambda x: -x[1])[:15]:
    print(f'{count}|{cmd}')
"
}

# =========== UTILIDADES ===========
# Verificar si AW está corriendo
aw_is_running() {
    aw_check >/dev/null 2>&1
}

# Mostrar estado de conexión
aw_status() {
    if aw_check; then
        echo "✅ ActivityWatch: $(_aw_resolve_api)"
        aw_get_buckets | python3 -c "import sys,json; b=json.load(sys.stdin); print(f'   Buckets: {len(b)}')"
    else
        echo "❌ ActivityWatch: No disponible"
        return 1
    fi
}