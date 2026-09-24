#!/usr/bin/env bash
# Determinar la ubicación real del script, resolviendo symlinks
SCRIPT_PATH="${BASH_SOURCE[0]}"
if [[ -L "$SCRIPT_PATH" ]]; then
    SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH")"
fi
DIR_ACTUAL="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

# Exportar HUB_ROOT ANTES de cargar config
export HUB_ROOT="$DIR_ACTUAL"

# Detectar SO y cargar config apropiada
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DISTRO_ID="$ID"
else
    DISTRO_ID=$(uname -s)
fi

# Cargar config específica de SO si existe
if [[ -f "$DIR_ACTUAL/config-${DISTRO_ID}.sh" ]]; then
    source "$DIR_ACTUAL/config-${DISTRO_ID}.sh"
fi

source "$DIR_ACTUAL/core.sh"
# aw_client define aw_is_running/_aw_resolve_api (doctor y stats)
source "$DIR_ACTUAL/scripts/lib/aw_client.sh"

# --- DETECCIÓN DE SESIÓN TMUX ---
# Si ya estamos dentro de tmux, usar la sesión actual (vía display-message,
# que devuelve el nombre real de sesión; parsear $TMUX da el socket, no sirve).
# Si no, crear/adjuntar la sesión configurada en $SESSION (default: work)
if [[ -n "$TMUX" ]]; then
    SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "$SESSION")
else
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        tmux new-session -d -s "$SESSION"
    fi
fi

# --- ABRIR NOTES EN TMUX (reusa ventana 📝, no acumula) ---
open_note() {
    local file="$1" win="📝"
    tmux has-session -t "$SESSION" 2>/dev/null || tmux new-session -d -s "$SESSION"
    if tmux list-windows -t "$SESSION" -F "#{window_name}" 2>/dev/null | grep -q "^$win$"; then
        local dead=$(tmux list-panes -t "$SESSION:$win" -F "#{pane_dead}" 2>/dev/null)
        local proc=$(tmux list-panes -t "$SESSION:$win" -F '#{pane_current_command}' 2>/dev/null | head -1)
        if [[ "$dead" == "1" ]]; then
            tmux respawn-pane -k -t "$SESSION:$win"
            sleep 0.3
            tmux send-keys -t "$SESSION:$win" "nvim '$file'" Enter
        elif [[ "$proc" == "nvim" || "$proc" == "vim" ]]; then
            tmux select-window -t "$SESSION:$win" 2>/dev/null
            hyprctl dispatch 'hl.dsp.focus({ window = "class:Alacritty" })' 2>/dev/null
            return
        else
            tmux send-keys -t "$SESSION:$win" "nvim '$file'" Enter
        fi
    else
        tmux new-window -t "$SESSION" -n "$win"
        sleep 0.3
        tmux send-keys -t "$SESSION:$win" "nvim '$file'" Enter
    fi
    tmux select-window -t "$SESSION:$win" 2>/dev/null
    hyprctl dispatch 'hl.dsp.focus({ window = "class:Alacritty" })' 2>/dev/null
}

# --- NOTA ALEATORIA AL INICIAR (solo accesible desde ⚙️ Más → Redescubrir) ---

# --- RUTINA DIARIA ---
run_daily_routine_once() {
    local LAST_RUN_FILE="$HOME/.config/tdo/last-daily-run"
    mkdir -p "$(dirname "$LAST_RUN_FILE")"
    local TODAY=$(date +%Y-%m-%d)
    local LAST_RUN=$(cat "$LAST_RUN_FILE" 2>/dev/null)
    if [[ "$LAST_RUN" != "$TODAY" ]]; then
        bash "$SCRIPTS_DIR/notes/daily-routine.sh"
        echo "$TODAY" > "$LAST_RUN_FILE"
    fi
}

# --- CAPTURA RÁPIDA ---
quick_capture() {
    local accion=$(echo -e "📝 Nueva nota\n✅ Nueva tarea" | rofi -dmenu -p "Capturar:")
    [[ -z "$accion" ]] && return

    if [[ "$accion" == *"tarea"* ]]; then
        # Script dedicado con prioridad y fecha visual
        bash "$SCRIPTS_DIR/capture/quick-capture-rofi.sh"
        return
    fi

    local title=$(rofi -dmenu -p "📝 Título:")
    [[ -z "$title" ]] && return
    local tags=$(rofi -dmenu -p "🏷️ Tags:" -mesg "Separados por espacio")
    local fname=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g; s/[^a-z0-9-]//g')
    [[ -z "$fname" ]] && fname="nota-$(date +%s)"
    local f="$INBOX_DIR/$fname.md"
    local template="$TEMPLATES_DIR/note.md"
    if [[ -f "$template" ]]; then
        sed "s/{{date}}/$(date +%Y-%m-%d)/g; s/{{title}}/$title/g" "$template" > "$f"
        [[ -n "$tags" ]] && sed -i "s/tags: \[.*\]/tags: [$tags]/" "$f"
    else
        echo -e "# $title\n\n" > "$f"
    fi
    open_note "$f"
}


# --- REGISTRO DE SESIÓN ---
log_focus_start() {
    local task="${1:-Focus session}"
    echo "$(date +%s)|$task" > "$SESSION_LOG"
}

# --- RESUMEN DE CONTEXTO PARA EL MENÚ ---
build_context_msg() {
    local msg=""
    local overdue=$(get_all_tasks | while IFS= read -r t; do is_task_overdue "$t" 2>/dev/null && echo "$t"; done)
    local n_overdue=$(echo "$overdue" | grep -c .)
    [[ "$n_overdue" -gt 0 ]] && msg+="🔴 $n_overdue vencidas  "
    if [[ -f "$SESSION_LOG" ]]; then
        local saved=$(cat "$SESSION_LOG")
        local ts=$(echo "$saved" | cut -d'|' -f1)
        local task=$(echo "$saved" | cut -d'|' -f2-)
        local elapsed=$(( ($(date +%s) - ${ts:-0}) / 60 ))
        if [[ $elapsed -lt 300 ]]; then
            msg+="↩️ Hace ${elapsed}m: ${task:0:40}"
        fi
    fi
    echo "${msg:-Selecciona una opción}"
}

# --- FEEDBACK AL SALIR ---
session_feedback() {
    local done_today=$(grep -c "\[x\] $(date +%Y-%m-%d)" "$TODO_ACTIVO" 2>/dev/null)
    [[ -z "$done_today" ]] && done_today=0
    local streak=$(bash "$SCRIPTS_DIR/focus/streak-tracker.sh" 2>/dev/null)
    [[ -z "$streak" ]] && streak=0
    notify "TDO" "✅ $done_today hoy · 🔥 $streak días"
}

# --- DOCTOR ---
_doctor() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║${RESET}  🏥 TDO-HUB DOCTOR                            ${BLUE}║${RESET}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${RESET}\n"
    
    local issues=0
    local warnings=0
    
    # 1. Dependencias críticas
    echo -e "${BLUE}📦 Dependencias Críticas:${RESET}"
    for cmd in bash tmux nvim; do
        if command -v "$cmd" &>/dev/null; then
            echo -e "  ${GREEN}✓${RESET} $cmd"
        else
            echo -e "  ${RED}✗${RESET} $cmd (CRÍTICO)"
            ((issues++))
        fi
    done
    
    # 2. Dependencias recomendadas
    echo -e "\n${BLUE}🎁 Dependencias Recomendadas:${RESET}"
    for cmd in rofi fzf rg notify-send mpc timew; do
        if command -v "$cmd" &>/dev/null; then
            echo -e "  ${GREEN}✓${RESET} $cmd"
        else
            echo -e "  ${YELLOW}⚠${RESET} $cmd (recomendado)"
            ((warnings++))
        fi
    done
    
    # 3. Configuración
    echo -e "\n${BLUE}⚙️ Configuración:${RESET}"
    [[ -f "$HUB_ROOT/.env" ]] && echo -e "  ${GREEN}✓${RESET} .env existe" || echo -e "  ${YELLOW}⚠${RESET} .env no encontrado (usa .env.example)"
    [[ -f "$HUB_ROOT/config.sh" ]] && echo -e "  ${GREEN}✓${RESET} config.sh" || echo -e "  ${RED}✗${RESET} config.sh faltante"
    
    # 4. Directorios
    echo -e "\n${BLUE}📁 Directorios:${RESET}"
    for var in NOTES_DIR INBOX_DIR TEMPLATES_DIR JOURNAL_DIR TODOS_DIR; do
        local dir="${!var}"
        if [[ -d "$dir" ]]; then
            echo -e "  ${GREEN}✓${RESET} $var: $dir"
        else
            echo -e "  ${YELLOW}⚠${RESET} $var no existe: $dir (se creará)"
            ((warnings++))
        fi
    done
    
    # 5. Archivos
    echo -e "\n${BLUE}📄 Archivos:${RESET}"
    [[ -f "$TODO_ACTIVO" ]] && echo -e "  ${GREEN}✓${RESET} TODO_ACTIVO" || echo -e "  ${YELLOW}⚠${RESET} TODO_ACTIVO no existe"
    [[ -f "$BLOCK_FILE" ]] && echo -e "  ${GREEN}✓${RESET} bloqueo_distraccion.txt" || echo -e "  ${RED}✗${RESET} bloqueo_distraccion.txt faltante"
    [[ -f "$PHRASES_FILE" ]] && echo -e "  ${GREEN}✓${RESET} phrases.txt" || echo -e "  ${YELLOW}⚠${RESET} phrases.txt no existe"
    
    # 6. Focus mode (sudoers)
    echo -e "\n${BLUE}🛡️ Focus Mode:${RESET}"
    if [[ -w "/etc/hosts" ]]; then
        echo -e "  ${GREEN}✓${RESET} /etc/hosts escribible"
    elif check_sudoers_setup &>/dev/null; then
        echo -e "  ${GREEN}✓${RESET} sudoers configurado"
    else
        echo -e "  ${RED}✗${RESET} sudoers NO configurado"
        echo -e "    ${YELLOW}Fix:${RESET} sudo visudo -f /etc/sudoers.d/tdo-hub < $HUB_ROOT/scripts/system/sudoers-tdo"
        ((issues++))
    fi
    
    # 7. ActivityWatch
    echo -e "\n${BLUE}📊 ActivityWatch:${RESET}"
    if aw_is_running 2>/dev/null; then
        local api=$(_aw_resolve_api 2>/dev/null)
        echo -e "  ${GREEN}✓${RESET} Conectado: $api"
    else
        echo -e "  ${YELLOW}⚠${RESET} No detectado (stats no funcionarán)"
        ((warnings++))
    fi
    
    # 8. Tmux
    echo -e "\n${BLUE}🖥️ Tmux:${RESET}"
    if tmux list-sessions 2>/dev/null | head -1 | grep -q .; then
        local sessions=$(tmux list-sessions 2>/dev/null | wc -l)
        echo -e "  ${GREEN}✓${RESET} $sessions sesión(es) activa(s)"
    else
        echo -e "  ${YELLOW}⚠${RESET} Sin sesiones (se crearán al usar hub)"
        ((warnings++))
    fi
    
    # 9. Scripts ejecutables
    echo -e "\n${BLUE}🔧 Scripts:${RESET}"
    local script_count=0
    local exec_count=0
    for s in "$SCRIPTS_DIR"/*.sh; do
        [[ -f "$s" ]] || continue
        ((script_count++))
        [[ -x "$s" ]] && ((exec_count++))
    done
    echo -e "  ${GREEN}✓${RESET} $exec_count/$script_count scripts ejecutables"
    
    # Resumen
    echo -e "\n${BLUE}═══════════════════════════════════════════════════${RESET}"
    if [[ $issues -eq 0 && $warnings -eq 0 ]]; then
        echo -e "${GREEN}✅ Sistema sano - listo para usar${RESET}"
    elif [[ $issues -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  $warnings advertencia(s) - funcional pero revisar${RESET}"
    else
        echo -e "${RED}❌ $issues error(es) crítico(s) - necesita atención${RESET}"
    fi
    echo -e "${BLUE}═══════════════════════════════════════════════════${RESET}\n"
}

# --- ENFOCAR ---
start_focus() {
    notify "🎯" "Enfocando..."
    timew start "Focus session" 2>/dev/null
    log_focus_start "Focus session"
    bash "$FOCUS_SCRIPT" &>/dev/null &
}

# Ejecutar rutina diaria
run_daily_routine_once

# Helper: crear ventana tmux y enfocar
_open_win() {
    local name="$1" cmd="$2"
    tmux has-session -t "$SESSION" 2>/dev/null || return 1
    local exists=$(tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -c "^${name}$")
    if [[ "$exists" -gt 0 ]]; then
        local proc=$(tmux list-panes -t "$SESSION:$name" -F '#{pane_current_command}' 2>/dev/null | head -1)
        if [[ "$proc" == "nvim" || "$proc" == "vim" ]]; then
            tmux select-window -t "$SESSION:$name" 2>/dev/null
        else
            tmux send-keys -t "$SESSION:$name" "$cmd" Enter
            tmux select-window -t "$SESSION:$name" 2>/dev/null
        fi
    else
        tmux new-window -t "$SESSION" -n "$name"
        sleep 0.3
        tmux send-keys -t "$SESSION:$name" "$cmd" Enter
        tmux select-window -t "$SESSION:$name" 2>/dev/null
    fi
    hyprctl dispatch 'hl.dsp.focus({ window = "class:Alacritty" })' 2>/dev/null
}


# --- MENÚ PRINCIPAL (pantalla única, 2 columnas vía themes/hub.rasi) ---
# Solo se arma si NO hay args: con `hub.sh <accion>` no hay que abrir rofi.
ACTION=""
if [[ $# -eq 0 ]]; then
    ctx=$(build_context_msg)
    ACTION=$(echo -e "📝 Capturar\n🔍 Buscar\n📋 Tareas\n📓 Journal\n🔙 Ayer\n🎲 Redescubrir\n🍅 Enfocar\n🛑 Parar Focus\n⏱️ Time\n🧠 Flow\n🎁 Reward\n📊 Stats\n🎵 Música\n📥 Organizar\n🔄 Sync\n📋 Weekly Review\n↩️ Undo\n🛑 Pánico\n⚙️ Config" | rofi_menu "Hub" "$ctx")
fi

# --- DISPATCH DE ACCIONES (menú rofi o directo: hub.sh <accion>) ---
run_action() {
    local a="$1"
    case "$a" in
        capturar) a="📝 Capturar" ;;
        buscar) a="🔍 Buscar" ;;
        tareas) a="📋 Tareas" ;;
        journal) a="📓 Journal" ;;
        ayer) a="🔙 Ayer" ;;
        enfocar) a="🍅 Enfocar" ;;
        parar) a="🛑 Parar Focus" ;;
        time) a="⏱️ Time" ;;
        flow) a="🧠 Flow" ;;
        reward) a="🎁 Reward" ;;
        stats) a="📊 Stats" ;;
        musica) a="🎵 Música" ;;
        redescubrir) a="🎲 Redescubrir" ;;
        organizar) a="📥 Organizar" ;;
        sync) a="🔄 Sync" ;;
        weekly) a="📋 Weekly Review" ;;
        undo) a="↩️ Undo" ;;
        panico) a="🛑 Pánico" ;;
        config) a="⚙️ Config" ;;
        doctor) a="🏥 Doctor" ;;
        help|--help|-h)
            echo "Uso: hub.sh [accion]"
            echo "Acciones: capturar buscar tareas journal ayer enfocar parar time flow reward stats musica redescubrir organizar sync weekly undo panico config doctor"
            echo "Sin args: menú rofi completo."
            return 0
            ;;
    esac
    case "$a" in
    "📝 Capturar") quick_capture ;;
    "🔍 Buscar") bash "$SCRIPTS_DIR/capture/buscar.sh" ;;
    "📋 Tareas") bash "$SCRIPTS_DIR/notes/tareas.sh" ;;
    *"Journal"*)
        FILE_JOURNAL="$JOURNAL_DIR/$(date +%Y)/$(date +%m)/$(date +%Y-%m-%d).md"
        if [[ ! -f "$FILE_JOURNAL" ]]; then
            apply_template "$TEMPLATES_DIR/entry.md" "$FILE_JOURNAL" "$(date +%F)"
        fi
        _open_win "journal" "nvim '+normal Gko' '$FILE_JOURNAL'"
        ;;
    *"Ayer"*)
        _open_win "ayer" "bash '$SCRIPTS_DIR/notes/yesterday.sh'"
        ;;
    *"Enfocar"*)
        start_focus
        ;;
    *"Parar Focus"*)
        timew stop 2>/dev/null
        bash "$FOCUS_SCRIPT" stop 2>&1 | head -5
        notify "🛑 Focus parado"
        ;;
    *"Time"*)
        bash "$SCRIPTS_DIR/notes/time.sh"
        ;;
    *"Flow"*)
        bash "$SCRIPTS_DIR/focus/flow-detect.sh" 15
        ;;
    *"Reward"*)
        bash "$SCRIPTS_DIR/focus/reward.sh" 3
        ;;
    *"Stats"*)
        _open_win "stats" "bash '$SCRIPTS_DIR/stats/aw-stats.sh'"
        ;;
    *"Música"*)
        bash "$SCRIPTS_DIR/focus/focus_music.sh"
        ;;
    *"Redescubrir"*)
        nota=$(python3 "$SCRIPTS_DIR/system/note-of-the-day.py" 2>/dev/null)
        [[ -n "$nota" && -f "$nota" ]] && _open_win "note" "nvim '$nota'"
        ;;
    *"Organizar"*)
        if [[ -f "$SCRIPTS_DIR/triage-local.sh" ]]; then
            _open_win "triage" "bash '$SCRIPTS_DIR/triage-local.sh' && echo '✅ Inbox clasificado' || echo '❌ Error'"
        else
            notify-send "📥 Organizar" "triage-local.sh no está instalado (script local opcional)"
        fi
        ;;
    *"Sync"*)
        _open_win "sync" "bash '$SCRIPTS_DIR/system/sync.sh'"
        ;;
    *"Weekly Review"*)
        _open_win "weekly" "bash '$SCRIPTS_DIR/notes/weekly-review.sh open'"
        ;;
    *"Undo"*)
        bash "$SCRIPTS_DIR/notes/undo.sh"
        ;;
    *"Pánico"*)
        _open_win "panic" "bash '$PANIC_SCRIPT'"
        ;;
    *"Config"*)
        bash "$SCRIPTS_DIR/system/config-menu.sh"
        ;;
    *"Doctor"*)
        _doctor
        ;;
        *) echo "Acción desconocida: $a — usa: hub.sh help" >&2; return 1 ;;
    esac
}

# --- ENTRADA: hub.sh [accion] abre directo; sin args muestra el menú ---
if [[ $# -gt 0 ]]; then
    run_action "$1"
else
    run_action "$ACTION"
fi

# Feedback al salir (solo si se hizo algo útil hoy)
session_feedback
