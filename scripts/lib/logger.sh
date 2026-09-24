#!/usr/bin/env bash
# ==========================================================
# 📝 LOGGER - Sistema de logging unificado y estructurado
# Reemplaza: .tdo.log, $LOG_FILE, pomodoro-log.txt, etc.
# ==========================================================

# HUB_ROOT ya está disponible desde core.sh que nos carga
[[ -z "$HUB_ROOT" ]] && HUB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# =========== CONFIGURACIÓN ===========
_LOG_FILE="${TD_LOG_FILE:-$HUB_ROOT/.tdo.log}"
_LOG_LEVEL="${TD_LOG_LEVEL:-INFO}"
_LOG_JSON="${TD_LOG_JSON:-false}"
_LOG_MAX_SIZE="${TD_LOG_MAX_SIZE:-10485760}"  # 10MB
_LOG_MAX_FILES="${TD_LOG_MAX_FILES:-5}"

# Niveles: DEBUG=0, INFO=1, WARN=2, ERROR=3
declare -A _LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)
_CURRENT_LEVEL=${_LOG_LEVELS[$_LOG_LEVEL]:-1}

# =========== ROTACIÓN ===========
_log_rotate() {
    [[ -f "$_LOG_FILE" ]] || return 0
    local size=$(stat -c%s "$_LOG_FILE" 2>/dev/null || echo 0)
    [[ $size -lt $_LOG_MAX_SIZE ]] && return 0
    
    for i in $(seq $((_LOG_MAX_FILES - 1)) -1 1); do
        [[ -f "${_LOG_FILE}.$i" ]] && mv "${_LOG_FILE}.$i" "${_LOG_FILE}.$((i + 1))"
    done
    mv "$_LOG_FILE" "${_LOG_FILE}.1"
}

# =========== CORE LOGGING ===========
_log_write() {
    local level="$1"
    local label="$2"
    local message="$3"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local caller="${BASH_SOURCE[2]##*/}:${BASH_LINENO[1]}"
    
    _log_rotate
    
    if [[ "$_LOG_JSON" == "true" ]]; then
        # JSON estructurado para parsing
        local json_msg=$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g')
        printf '{"timestamp":"%s","level":"%s","label":"%s","message":"%s","caller":"%s"}\n' \
            "$timestamp" "$level" "$label" "$json_msg" "$caller" >> "$_LOG_FILE"
    else
        # Formato legible
        printf '[%s] [%s] [%s] %s\n' "$timestamp" "$level" "$label" "$message" >> "$_LOG_FILE"
    fi
}

# =========== PÚBLICO ===========
log_debug() {
    [[ ${_LOG_LEVELS[DEBUG]:-0} -ge $_CURRENT_LEVEL ]] && _log_write "DEBUG" "$1" "$2"
}

log_info() {
    [[ ${_LOG_LEVELS[INFO]:-1} -ge $_CURRENT_LEVEL ]] && _log_write "INFO" "$1" "$2"
}

log_warn() {
    [[ ${_LOG_LEVELS[WARN]:-2} -ge $_CURRENT_LEVEL ]] && _log_write "WARN" "$1" "$2"
}

log_error() {
    [[ ${_LOG_LEVELS[ERROR]:-3} -ge $_CURRENT_LEVEL ]] && _log_write "ERROR" "$1" "$2"
}

log_fatal() {
    _log_write "FATAL" "$1" "$2"
    exit 1
}

# =========== HELPERS COMUNES ===========
log_ok() {
    log_info "$1" "✓ $2"
}

log_fail() {
    log_error "$1" "✗ $2"
}

log_action() {
    log_info "$1" "ACTION: $2"
}

log_duration() {
    local label="$1"
    local start_time="$2"
    local end_time="${3:-$(date +%s)}"
    local duration=$((end_time - start_time))
    log_info "$label" "Duration: ${duration}s"
}

# =========== CONSULTA ===========
# log_tail [lines] - ver últimas líneas
log_tail() {
    local lines="${1:-50}"
    tail -n "$lines" "$_LOG_FILE" 2>/dev/null || echo "No log file"
}

# log_grep "pattern" - buscar en logs
log_grep() {
    grep -i "$1" "$_LOG_FILE" 2>/dev/null | tail -20
}

# log_clear - limpiar logs
log_clear() {
    > "$_LOG_FILE"
    log_info "SYSTEM" "Log cleared"
}

# =========== COMPATIBILIDAD ===========
# Mantener notify() funcional (usa logger interno)
# notify "Title" "Message" -> log_info + notify-send
notify() {
    local title="${1:-TDO}"
    local message="${2:-$1}"
    log_info "NOTIFY" "$title: $message"
    command -v notify-send &>/dev/null && notify-send "$title" "$message" --icon=task-accepted 2>/dev/null
}

# Alias legacy
log_msg() { log_info "$1" "$2"; }
log_err() { log_error "ERROR" "$1"; }