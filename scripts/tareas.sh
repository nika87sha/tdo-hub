#!/usr/bin/env bash
# ==========================================================
# 📋 TAREAS - Lista con prioridades, Done/Edit/Focus
# Uso directo (atajo) o desde hub.sh
# Rofi: Enter=menú | Alt+c=Done | Alt+e=Edit | Alt+d=Focus
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
source "$SCRIPT_DIR/../core.sh"

start_focus_here() {
    local task="${1:-Focus session}"
    notify "🎯" "Enfocando..."
    timew start "$task" 2>/dev/null
    echo "$(date +%s)|$task" > "$SESSION_LOG"
    bash "$FOCUS_SCRIPT" &>/dev/null &
}

edit_task() {
    local task="$1"
    local escaped=$(printf '%s\n' "$task" | sed 's/[.[\*^$()\/]/\\&/g')
    local line=$(grep -n "$escaped" "$TODO_ACTIVO" | head -1 | cut -d: -f1)
    [[ -z "$line" ]] && notify "Error" "Tarea no encontrada" && return 1
    local new_text=$(echo "$task" | rofi -dmenu -p "✏️" 2>/dev/null)
    [[ -z "$new_text" ]] && return 1
    echo "# EDIT $(date +%Y-%m-%d_%H:%M): $task → $new_text" >> "$TODO_TRASH"
    sed -i "${line}s/^.*/- [ ] $new_text/" "$TODO_ACTIVO"
    notify "✏️ Editado" "$new_text"
}

while true; do
    ALL_TASKS=$(get_all_tasks)
    [[ -z "$ALL_TASKS" ]] && notify "Tareas" "No hay tareas pendientes" && break

    SORTED_TASKS=$(sort_by_priority "$ALL_TASKS")

    SEL_RAW=$(echo "$SORTED_TASKS" | sed 's/^!!/🔥 /; s/^!/⚡ /' | rofi -dmenu -p "✅ Tareas" -mesg "Escribe para filtrar | Alt+c: Done | Alt+e: Edit | Alt+d: Focus" -kb-custom-1 "Alt+c" -kb-custom-2 "Alt+e" -kb-custom-3 "Alt+d")
    CODE=$?
    [[ $CODE -eq 1 || -z "$SEL_RAW" ]] && break

    # Preservar el prefijo original (! / !!) para matchear exactamente la línea en TODO_ACTIVO
    PRIO_PREFIX=""
    case "$SEL_RAW" in
        "🔥 "*) PRIO_PREFIX="!! " ;;
        "⚡ "*)  PRIO_PREFIX="! "  ;;
    esac
    SEL=$(echo "$SEL_RAW" | sed 's/^[🔥⚡] //; s/^ *//')
    FULL_TASK="${PRIO_PREFIX}${SEL}"
    TASK_BASE=$(get_task_base "$FULL_TASK")
    ESC=$(printf '%s\n' "$TASK_BASE" | sed 's/[.[\*^$()\/]/\\&/g')

    case $CODE in
        # Rofi dmenu: 0=Enter, 1=cancel, 10+N para kb-custom-N (Alt+c=10 Done, Alt+e=11 Edit, Alt+d=12 Focus)
        10)
            timew stop 2>/dev/null
            echo "- [x] $(date +%Y-%m-%d) $FULL_TASK" >> "$TODO_TRASH"
            if echo "$FULL_TASK" | grep -q "repeat:"; then
                complete_task_with_recurrence "$FULL_TASK"
            else
                sed -i "s/- \[ \] $ESC/- [x] $ESC/" "$TODO_ACTIVO"
            fi
            notify "¡Hecho!" "$FULL_TASK" ;;
        11) edit_task "$FULL_TASK" ;;
        12)
            sed -i "s/🎯 //g" "$TODO_ACTIVO"
            sed -i "s/- \[ \] $ESC/- [ ] 🎯 $ESC/" "$TODO_ACTIVO"
            timew start "$SEL" 2>/dev/null
            echo "$(date +%s)|$SEL" > "$SESSION_LOG"
            bash "$FOCUS_SCRIPT" &>/dev/null &
            break ;;
        0)
            ACCION=$(echo -e "✏️ Editar\n🎯 Focus\n✅ Done\n🔄 Recurrente\n❌ Borrar" | rofi -dmenu -p "$SEL")
            [[ "$ACCION" == *"Editar"* ]] && edit_task "$FULL_TASK"
            [[ "$ACCION" == *"Focus"* ]] && sed -i "s/🎯 //g" "$TODO_ACTIVO" && sed -i "s/- \[ \] $ESC/- [ ] 🎯 $ESC/" "$TODO_ACTIVO" && start_focus_here "$SEL" && break
            [[ "$ACCION" == *"Done"* ]] && { timew stop 2>/dev/null; echo "- [x] $(date +%Y-%m-%d) $FULL_TASK" >> "$TODO_TRASH"; sed -i "s/- \[ \] $ESC/- [x] $ESC/" "$TODO_ACTIVO"; notify "¡Hecho!" "$FULL_TASK"; }
            [[ "$ACCION" == *"Recurrente"* ]] && complete_task_with_recurrence "$FULL_TASK"
            [[ "$ACCION" == *"Borrar"* ]] && echo "# BORRADO $(date +%Y-%m-%d_%H:%M): $FULL_TASK" >> "$TODO_TRASH" && sed -i "/$ESC/d" "$TODO_ACTIVO"
            ;;
    esac
done
