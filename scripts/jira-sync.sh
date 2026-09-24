#!/usr/bin/env bash
# ==========================================================
# 🔄 JIRA SYNC - Sincronización bidireccional Jira ↔ tdo-hub
# ==========================================================
#
# Pull: Issues asignados → tareas locales con tag @jira KEY-123
# Push: Tareas locales done → transition issue + comentario
#
# Config en .env:
#   JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN, JIRA_PROJECT_KEYS
#   JIRA_JQL_ASSIGNED, JIRA_TRANSITION_DONE, JIRA_SYNC_TAG
# ==========================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
source "$SCRIPT_DIR/../core.sh"
source "$SCRIPT_DIR/../config.sh"

# Cargar .env si existe (override config.sh)
ENV_FILE="$HUB_ROOT/.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

# Validar config Jira
require_command "curl" "curl" || exit 1
require_command "jq" "jq" || exit 1

: "${JIRA_URL:?Falta JIRA_URL en .env}"
: "${JIRA_EMAIL:?Falta JIRA_EMAIL en .env}"
: "${JIRA_API_TOKEN:?Falta JIRA_API_TOKEN en .env}"
: "${JIRA_PROJECT_KEYS:?Falta JIRA_PROJECT_KEYS en .env}"

JIRA_AUTH="${JIRA_EMAIL}:${JIRA_API_TOKEN}"
JIRA_API="${JIRA_URL}/rest/api/3"
JIRA_TAG="${JIRA_SYNC_TAG:-@jira}"
JIRA_TRANSITION="${JIRA_TRANSITION_DONE:-Done}"
JQL="${JIRA_JQL_ASSIGNED:-assignee = currentUser() AND status NOT IN (Done, Closed) ORDER BY updated DESC}"

# Colores
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[0;34m'; N='\033[0m'

log() { echo -e "${B}[JIRA]${N} $*"; }
ok() { echo -e "${G}[JIRA]${N} $*"; }
warn() { echo -e "${Y}[JIRA]${N} $*"; }
err() { echo -e "${R}[JIRA]${N} $*" >&2; }

# =========== HELPERS ===========

jira_get() {
    curl -sS -u "$JIRA_AUTH" -H "Accept: application/json" "$JIRA_API$1"
}

jira_post() {
    curl -sS -u "$JIRA_AUTH" -H "Accept: application/json" -H "Content-Type: application/json" -X POST -d "$2" "$JIRA_API$1"
}

jira_put() {
    curl -sS -u "$JIRA_AUTH" -H "Accept: application/json" -H "Content-Type: application/json" -X PUT -d "$2" "$JIRA_API$1"
}

# Extraer issue key de una tarea local
extract_jira_key() {
    echo "$1" | grep -oE "$JIRA_TAG[[:space:]]*[A-Z]+-[0-9]+" | sed "s/$JIRA_TAG[[:space:]]*//"
}

# =========== PULL: Jira → Local ===========

jira_pull() {
    log "Obteniendo issues asignados desde Jira..."
    
    local encoded_jql=$(printf '%s' "$JQL" | jq -sRr @uri)
    local fields="key,summary,status,project,priority,assignee,updated,description"
    local response=$(jira_get "/search?jql=$encoded_jql&fields=$fields&maxResults=50")
    
    local total=$(echo "$response" | jq -r '.total // 0')
    [[ "$total" -eq 0 ]] && { warn "No hay issues asignados"; return 0; }
    
    log "Encontrados $total issues. Procesando..."
    
    local created=0 updated=0 skipped=0
    
    echo "$response" | jq -c '.issues[]' | while read -r issue; do
        local key=$(echo "$issue" | jq -r '.key')
        local summary=$(echo "$issue" | jq -r '.fields.summary')
        local status=$(echo "$issue" | jq -r '.fields.status.name')
        local project=$(echo "$issue" | jq -r '.fields.project.key')
        local priority=$(echo "$issue" | jq -r '.fields.priority.name // "Medium"')
        local updated_remote=$(echo "$issue" | jq -r '.fields.updated')
        
        # Buscar si ya existe tarea local con este key
        local existing_line=$(grep -F "$JIRA_TAG $key" "$TODO_ACTIVO" 2>/dev/null | head -1)
        
        # Mapear prioridad Jira → tdo-hub
        local prio_prefix=""
        case "$priority" in
            Highest|High) prio_prefix="!! " ;;
            Medium) prio_prefix="! " ;;
            Low|Lowest) prio_prefix="" ;;
        esac
        
        # Formato tarea: "!! Summary @jira KEY-123 due:YYYY-MM-DD"
        local due_date=$(date -d "+7 days" +%Y-%m-%d)  # Default 1 semana
        local task_text="${prio_prefix}${summary} ${JIRA_TAG} ${key} due:${due_date}"
        
        if [[ -n "$existing_line" ]]; then
            # Verificar si cambió (comparar updated)
            local existing_updated=$(grep -F "$JIRA_TAG $key" "$TODO_ACTIVO" | head -1 | grep -oE 'updated:[0-9-]+' | cut -d: -f2)
            if [[ "$existing_updated" != "$(echo "$updated_remote" | cut -dT -f1)" ]]; then
                # Actualizar tarea existente
                local escaped=$(sanitize_for_sed "$(get_task_base "$existing_line")")
                atomic_sed_replace "$TODO_ACTIVO" "s/^.*$escaped.*/- [ ] $task_text updated:$(echo "$updated_remote" | cut -dT -f1)/"
                ((updated++))
                ok "Actualizado: $key - $summary"
            else
                ((skipped++))
            fi
        else
            # Crear nueva tarea
            echo "- [ ] $task_text updated:$(echo "$updated_remote" | cut -dT -f1)" >> "$TODO_ACTIVO"
            ((created++))
            ok "Creado: $key - $summary"
        fi
    done
    
    log "Pull completado: $created nuevos, $updated actualizados, $skipped sin cambios"
}

# =========== PUSH: Local → Jira ===========

jira_push() {
    log "Buscando tareas locales completadas con tag $JIRA_TAG..."
    
    local done_tasks=$(grep -E "^\s*-\s*\[x\].*$JIRA_TAG" "$TODO_ACTIVO" 2>/dev/null || true)
    [[ -z "$done_tasks" ]] && { log "No hay tareas completadas con tag $JIRA_TAG"; return 0; }
    
    echo "$done_tasks" | while IFS= read -r line; do
        local key=$(extract_jira_key "$line")
        [[ -z "$key" ]] && continue
        
        # Verificar si ya se hizo push (marca pushed:)
        if echo "$line" | grep -q "pushed:"; then
            continue
        fi
        
        local task_base=$(get_task_base "$line")
        local comment="Completado desde tdo-hub: $task_base"
        
        log "Transicionando $key a '$JIRA_TRANSITION'..."
        
        # Obtener transiciones disponibles
        local transitions=$(jira_get "/issue/$key/transitions")
        local transition_id=$(echo "$transitions" | jq -r --arg name "$JIRA_TRANSITION" '.transitions[] | select(.name == $name) | .id' | head -1)
        
        if [[ -z "$transition_id" || "$transition_id" == "null" ]]; then
            warn "No existe transición '$JIRA_TRANSITION' para $key. Disponibles:"
            echo "$transitions" | jq -r '.transitions[] | "  - \(.name) (id: \(.id))"'
            continue
        fi
        
        # Ejecutar transición
        local payload=$(jq -n --arg id "$transition_id" --arg comment "$comment" '{transition: {id: $id}, update: {comment: [{add: {body: $comment}}]}}')
        local result=$(jira_post "/issue/$key/transitions" "$payload")
        
        if [[ -z "$result" || "$result" == "{}" ]]; then
            ok "Push OK: $key → $JIRA_TRANSITION"
            # Marcar como pushed en local
            local escaped=$(sanitize_for_sed "$task_base")
            atomic_sed_replace "$TODO_ACTIVO" "s/^.*$escaped.*/& pushed:$(date +%Y-%m-%d)/"
        else
            err "Push falló para $key: $result"
        fi
    done
}

# =========== SYNC: Pull + Push ===========

jira_sync() {
    log "=== Iniciando sync Jira ==="
    jira_pull
    jira_push
    log "=== Sync Jira completado ==="
}

# =========== CLI ===========

case "${1:-sync}" in
    pull) jira_pull ;;
    push) jira_push ;;
    sync) jira_sync ;;
    test)
        log "Probando conexión a Jira..."
        jira_get "/myself" | jq -r '"Usuario: \(.displayName) (\(.emailAddress))"'
        ;;
    --help|-h)
        cat <<EOF
Uso: jira-sync.sh [pull|push|sync|test]

  pull    - Traer issues asignados de Jira → tareas locales
  push    - Subir tareas locales completadas (@jira KEY) → Jira
  sync    - Pull + Push (default)
  test    - Verificar conexión y credenciales

Configuración en .env:
  JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN, JIRA_PROJECT_KEYS
  JIRA_JQL_ASSIGNED, JIRA_TRANSITION_DONE, JIRA_SYNC_TAG
EOF
        ;;
    *) err "Acción desconocida: $1. Usa --help"; exit 1 ;;
esac