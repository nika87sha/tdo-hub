#!/usr/bin/env bash
# ==========================================================
# 📅 OUTLOOK FOCUS BLOCKS - Sincroniza calendario Outlook → focus_mode
# ==========================================================
#
# Lee eventos de calendarios Outlook (vía Microsoft Graph) y:
# - Bloquea distractores durante eventos categorizados como "Focus/Deep Work"
# - Crea tareas locales para reuniones importantes
# - Notifica 5 min antes de eventos de focus
#
# Config en .env:
#   MSGRAPH_CLIENT_ID, MSGRAPH_CLIENT_SECRET, MSGRAPH_TENANT_ID
#   MSGRAPH_USER_EMAIL, OUTLOOK_CALENDAR_NAME
#   OUTLOOK_FOCUS_CATEGORIES, OUTLOOK_SYNC_LOOKAHEAD_DAYS
# ==========================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
source "$SCRIPT_DIR/../core.sh"
source "$SCRIPT_DIR/../config.sh"

ENV_FILE="$HUB_ROOT/.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

require_command "curl" "curl" || exit 1
require_command "jq" "jq" || exit 1

: "${MSGRAPH_CLIENT_ID:?Falta MSGRAPH_CLIENT_ID en .env}"
: "${MSGRAPH_CLIENT_SECRET:?Falta MSGRAPH_CLIENT_SECRET en .env}"
: "${MSGRAPH_TENANT_ID:?Falta MSGRAPH_TENANT_ID en .env}"
: "${MSGRAPH_USER_EMAIL:?Falta MSGRAPH_USER_EMAIL en .env}"

MSGRAPH_TOKEN_FILE="$HOME/.cache/tdo-hub/msgraph-token.json"
mkdir -p "$(dirname "$MSGRAPH_TOKEN_FILE")"

FOCUS_CATEGORIES="${OUTLOOK_FOCUS_CATEGORIES:-Focus,Deep Work,No Meetings}"
LOOKAHEAD_DAYS="${OUTLOOK_SYNC_LOOKAHEAD_DAYS:-7}"
CALENDAR_NAME="${OUTLOOK_CALENDAR_NAME:-Calendar}"

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[0;34m'; N='\033[0m'
log() { echo -e "${B}[OUTLOOK]${N} $*"; }
ok() { echo -e "${G}[OUTLOOK]${N} $*"; }
warn() { echo -e "${Y}[OUTLOOK]${N} $*"; }
err() { echo -e "${R}[OUTLOOK]${N} $*" >&2; }

# =========== MICROSOFT GRAPH AUTH ===========

msgraph_get_token() {
    local now=$(date +%s)
    local cached_token=""
    local expires_at=0
    
    if [[ -f "$MSGRAPH_TOKEN_FILE" ]]; then
        cached_token=$(jq -r '.access_token // ""' "$MSGRAPH_TOKEN_FILE" 2>/dev/null)
        expires_at=$(jq -r '.expires_at // 0' "$MSGRAPH_TOKEN_FILE" 2>/dev/null)
    fi
    
    # Token válido por al menos 60s más
    if [[ -n "$cached_token" && "$cached_token" != "null" && $((expires_at - now)) -gt 60 ]]; then
        echo "$cached_token"
        return 0
    fi
    
    log "Obteniendo nuevo token Microsoft Graph..."
    
    local response=$(curl -sS -X POST "https://login.microsoftonline.com/$MSGRAPH_TENANT_ID/oauth2/v2.0/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=$MSGRAPH_CLIENT_ID" \
        -d "client_secret=$MSGRAPH_CLIENT_SECRET" \
        -d "scope=https://graph.microsoft.com/.default" \
        -d "grant_type=client_credentials")
    
    local token=$(echo "$response" | jq -r '.access_token // ""')
    local expires_in=$(echo "$response" | jq -r '.expires_in // 3600')
    
    if [[ -z "$token" || "$token" == "null" ]]; then
        err "No se pudo obtener token: $response"
        return 1
    fi
    
    local expires_at=$((now + expires_in))
    jq -n --arg token "$token" --argjson exp "$expires_at" '{access_token: $token, expires_at: $exp}' > "$MSGRAPH_TOKEN_FILE"
    echo "$token"
}

msgraph_get() {
    local token=$(msgraph_get_token) || return 1
    curl -sS -H "Authorization: Bearer $token" -H "Accept: application/json" "https://graph.microsoft.com/v1.0$1"
}

# =========== CALENDAR LOGIC ===========

# Convertir categorías string a array para matching
IFS=',' read -ra FOCUS_CATS <<< "$FOCUS_CATEGORIES"
focus_categories=("${FOCUS_CATS[@]}")

is_focus_event() {
    local categories_json="$1"
    # categories es array de strings en Graph API
    local cats=$(echo "$categories_json" | jq -r '.[]?' 2>/dev/null || echo "")
    while IFS= read -r cat; do
        [[ -z "$cat" ]] && continue
        for fc in "${focus_categories[@]}"; do
            fc=$(echo "$fc" | xargs)  # trim
            [[ "$cat" == "$fc" ]] && return 0
        done
    done <<< "$cats"
    return 1
}

# Obtener eventos de los próximos N días
outlook_get_events() {
    local start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local end=$(date -u -d "+$LOOKAHEAD_DAYS days" +%Y-%m-%dT%H:%M:%SZ)
    
    # URL encode
    local start_enc=$(printf '%s' "$start" | jq -sRr @uri)
    local end_enc=$(printf '%s' "$end" | jq -sRr @uri)
    
    local filter="start/dateTime ge '$start' and end/dateTime le '$end'"
    local select="subject,start,end,categories,location,isOnlineMeeting,onlineMeetingUrl,importance"
    local orderby="start/dateTime"
    
    msgraph_get "/users/$MSGRAPH_USER_EMAIL/calendar/events?\$filter=$filter&\$select=$select&\$orderby=$orderby&\$top=50"
}

# Crear bloqueo de foco para un evento
create_focus_block() {
    local event_id="$1"
    local subject="$2"
    local start_dt="$3"
    local end_dt="$4"
    local is_focus="$5"
    
    local start_local=$(date -d "$start_dt" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${start_dt%.*}" +%s 2>/dev/null)
    local end_local=$(date -d "$end_dt" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${end_dt%.*}" +%s 2>/dev/null)
    local now=$(date +%s)
    
    # Si ya pasó, ignorar
    [[ $end_local -lt $now ]] && return 0
    
    # Si es evento de focus y no ha empezado, programar focus_mode
    if [[ "$is_focus" == "true" && $start_local -gt $now ]]; then
        local mins_until=$(( (start_local - now) / 60 ))
        local duration=$(( (end_local - start_local) / 60 ))
        
        log "Evento focus detectado: '$subject' en $mins_until min (duración: ${duration}min)"
        
        # Crear at job para activar focus_mode al inicio del evento
        local at_time=$(date -d "@$start_local" +"%H:%M %Y-%m-%d" 2>/dev/null || date -j -f "%s" "$start_local" +"%H:%M %Y-%m-%d" 2>/dev/null)
        echo "bash $FOCUS_SCRIPT &>/dev/null" | at "$at_time" 2>/dev/null && \
            log "Programado focus_mode para '$subject' a las $(date -d "@$start_local" +"%H:%M" 2>/dev/null)"
        
        # Programar fin de focus
        local at_time_end=$(date -d "@$end_local" +"%H:%M %Y-%m-%d" 2>/dev/null || date -j -f "%s" "$end_local" +"%H:%M %Y-%m-%d" 2>/dev/null)
        echo "bash $FOCUS_SCRIPT stop &>/dev/null" | at "$at_time_end" 2>/dev/null && \
            log "Programado fin focus_mode para '$subject' a las $(date -d "@$end_local" +"%H:%M" 2>/dev/null)"
    fi
    
    # Crear tarea local para reunión importante (opcional)
    if [[ "$is_focus" != "true" ]]; then
        local task_key="OUTLOOK-$(echo "$event_id" | md5sum | cut -c1-8)"
        local due_date=$(date -d "$start_dt" +%Y-%m-%d 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${start_dt%.*}" +%Y-%m-%d 2>/dev/null)
        local task_text="📅 $subject @outlook $task_key due:$due_date"
        
        # Solo si no existe ya
        if ! grep -Fq "@outlook $task_key" "$TODO_ACTIVO" 2>/dev/null; then
            echo "- [ ] $task_text" >> "$TODO_ACTIVO"
            ok "Tarea creada: $subject ($due_date)"
        fi
    fi
}

# =========== MAIN SYNC ===========

outlook_sync() {
    log "Sincronizando calendario Outlook (próximos $LOOKAHEAD_DAYS días)..."
    
    local events_json=$(outlook_get_events) || { err "Error obteniendo eventos"; return 1; }
    
    local count=$(echo "$events_json" | jq '.value | length')
    [[ "$count" -eq 0 ]] && { log "Sin eventos en el rango"; return 0; }
    
    log "Procesando $count eventos..."
    
    echo "$events_json" | jq -c '.value[]' | while read -r event; do
        local id=$(echo "$event" | jq -r '.id')
        local subject=$(echo "$event" | jq -r '.subject // "Sin asunto"')
        local start=$(echo "$event" | jq -r '.start.dateTime')
        local end=$(echo "$event" | jq -r '.end.dateTime')
        local categories=$(echo "$event" | jq -c '.categories // []')
        local importance=$(echo "$event" | jq -r '.importance // "normal"')
        
        local is_focus="false"
        is_focus_event "$categories" && is_focus="true"
        
        create_focus_block "$id" "$subject" "$start" "$end" "$is_focus"
    done
    
    ok "Sync Outlook completado"
}

# =========== DAEMON MODE ===========

outlook_daemon() {
    log "Iniciando daemon Outlook sync (cada 15 min)..."
    while true; do
        outlook_sync
        sleep 900  # 15 min
    done
}

# =========== CLI ===========

case "${1:-sync}" in
    sync) outlook_sync ;;
    daemon) outlook_daemon ;;
    events) 
        log "Próximos eventos:"
        outlook_get_events | jq -r '.value[] | "\(.start.dateTime) - \(.subject) [\(.categories | join(","))]"'
        ;;
    test)
        log "Probando conexión Microsoft Graph..."
        msgraph_get "/users/$MSGRAPH_USER_EMAIL" | jq -r '"Usuario: \(.displayName) (\(.userPrincipalName))"'
        ;;
    --help|-h)
        cat <<EOF
Uso: outlook-focus.sh [sync|daemon|events|test]

  sync      - Sincronizar eventos → focus blocks + tareas (default)
  daemon    - Ejecutar como daemon (sync cada 15 min)
  events    - Listar próximos eventos
  test      - Verificar conexión Graph API

Configuración en .env:
  MSGRAPH_CLIENT_ID, MSGRAPH_CLIENT_SECRET, MSGRAPH_TENANT_ID
  MSGRAPH_USER_EMAIL, OUTLOOK_CALENDAR_NAME
  OUTLOOK_FOCUS_CATEGORIES, OUTLOOK_SYNC_LOOKAHEAD_DAYS

Categorías focus (ej): "Focus,Deep Work,No Meetings"
EOF
        ;;
    *) err "Acción desconocida: $1"; exit 1 ;;
esac