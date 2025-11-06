#!/usr/bin/env bash
# Determinar la ubicación real del script, resolviendo symlinks
SCRIPT_PATH="${BASH_SOURCE[0]}"
if [[ -L "$SCRIPT_PATH" ]]; then
    SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH")"
fi
DIR_ACTUAL="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

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
            hyprctl dispatch focuswindow "class:Alacritty" 2>/dev/null
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
    hyprctl dispatch focuswindow "class:Alacritty" 2>/dev/null
}

# --- NOTA ALEATORIA AL INICIAR (solo accesible desde ⚙️ Más → Redescubrir) ---

# --- RUTINA DIARIA ---
run_daily_routine_once() {
    local LAST_RUN_FILE="$HOME/.config/tdo/last-daily-run"
    mkdir -p "$(dirname "$LAST_RUN_FILE")"
    local TODAY=$(date +%Y-%m-%d)
    local LAST_RUN=$(cat "$LAST_RUN_FILE" 2>/dev/null)
    if [[ "$LAST_RUN" != "$TODAY" ]]; then
        bash "$SCRIPTS_DIR/daily-routine.sh"
        echo "$TODAY" > "$LAST_RUN_FILE"
    fi
}

# --- CAPTURA RÁPIDA ---
quick_capture() {
    local accion=$(echo -e "📝 Nueva nota\n✅ Nueva tarea" | rofi -dmenu -p "Capturar:")
    [[ -z "$accion" ]] && return

    if [[ "$accion" == *"tarea"* ]]; then
        # Script dedicado con prioridad y fecha visual
        bash "$SCRIPTS_DIR/quick-capture-rofi.sh"
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
    local done_today=$(grep -c "\[x\] $(date +%Y-%m-%d)" "$TODO_ACTIVO" 2>/dev/null || echo 0)
    local streak=$(bash "$SCRIPTS_DIR/streak-tracker.sh" 2>/dev/null || echo 0)
    notify "TDO" "✅ $done_today hoy · 🔥 $streak días"
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
    hyprctl dispatch focuswindow "class:Alacritty" 2>/dev/null
}


# --- MENÚ PRINCIPAL (pantalla única, 2 columnas vía themes/hub.rasi) ---
ctx=$(build_context_msg)
ACTION=$(echo -e "📝 Capturar\n🔍 Buscar\n📋 Tareas\n📓 Journal\n🔙 Ayer\n🎲 Redescubrir\n🍅 Enfocar\n🛑 Parar Focus\n⏱️ Time\n🧠 Flow\n🎁 Reward\n📊 Stats\n🎵 Música\n📥 Organizar\n🔄 Sync\n↩️ Undo\n🛑 Pánico\n⚙️ Config" | rofi -dmenu -p "Hub" -mesg "$ctx" -config "$DIR_ACTUAL/themes/hub.rasi")

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
        undo) a="↩️ Undo" ;;
        panico) a="🛑 Pánico" ;;
        config) a="⚙️ Config" ;;
        help|--help|-h)
            echo "Uso: hub.sh [accion]"
            echo "Acciones: capturar buscar tareas journal ayer enfocar parar time flow reward stats musica redescubrir organizar sync undo panico config"
            echo "Sin args: menú rofi completo."
            return 0
            ;;
    esac
    case "$a" in
    "📝 Capturar") quick_capture ;;
    "🔍 Buscar") bash "$SCRIPTS_DIR/buscar.sh" ;;
    "📋 Tareas") bash "$SCRIPTS_DIR/tareas.sh" ;;
    *"Journal"*)
        FILE_JOURNAL="$JOURNAL_DIR/$(date +%Y)/$(date +%m)/$(date +%Y-%m-%d).md"
        if [[ ! -f "$FILE_JOURNAL" ]]; then
            apply_template "$TEMPLATES_DIR/entry.md" "$FILE_JOURNAL" "$(date +%F)"
        fi
        _open_win "journal" "nvim '+normal Gko' '$FILE_JOURNAL'"
        ;;
    *"Ayer"*)
        _open_win "ayer" "bash '$SCRIPTS_DIR/yesterday.sh'"
        ;;
    *"Enfocar"*)
        start_focus
        ;;
    *"Parar Focus"*)
        timew stop 2>/dev/null
        zsh "$FOCUS_SCRIPT" stop 2>&1 | head -5
        notify "🛑 Focus parado"
        ;;
    *"Time"*)
        bash "$SCRIPTS_DIR/time.sh"
        ;;
    *"Flow"*)
        bash "$SCRIPTS_DIR/flow-detect.sh" 15
        ;;
    *"Reward"*)
        bash "$SCRIPTS_DIR/reward.sh" 3
        ;;
    *"Stats"*)
        _open_win "stats" "bash '$SCRIPTS_DIR/aw-stats.sh'"
        ;;
    *"Música"*)
        bash "$SCRIPTS_DIR/focus_music.sh"
        ;;
    *"Redescubrir"*)
        nota=$(python3 "$SCRIPTS_DIR/note-of-the-day.py" 2>/dev/null)
        [[ -n "$nota" && -f "$nota" ]] && _open_win "note" "nvim '$nota'"
        ;;
    *"Organizar"*)
        _open_win "triage" "bash '$SCRIPTS_DIR/triage-local.sh' && echo '✅ Inbox clasificado' || echo '❌ Error'"
        ;;
    *"Sync"*)
        _open_win "sync" "bash '$SCRIPTS_DIR/sync.sh'"
        ;;
    *"Undo"*)
        bash "$SCRIPTS_DIR/undo.sh"
        ;;
    *"Pánico"*)
        _open_win "panic" "bash '$PANIC_SCRIPT'"
        ;;
    *"Config"*)
        bash "$SCRIPTS_DIR/config-menu.sh"
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
