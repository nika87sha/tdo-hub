#!/usr/bin/env bash
# Streak tracker - counts consecutive days with completed tasks
NOTES_DIR="${NOTES_DIR:-$HOME/notes}"
HUB_ROOT="${HUB_ROOT:-$HOME/.local/bin/tdo-hub}"
TODO_ACTIVO="${TODO_ACTIVO:-$NOTES_DIR/01_projects/General/todos/todo_ACTIVO.md}"
TODO_TRASH="${TODO_TRASH:-$HUB_ROOT/trash.md}"

if [[ ! -f "$TODO_TRASH" ]]; then
    echo "0"
    exit 0
fi

streak=0
day_offset=0

while true; do
    check_date=$(date -d "-${day_offset} days" +%Y-%m-%d 2>/dev/null)
    [[ -z "$check_date" ]] && break
    
    if grep -q "\[x\] $check_date" "$TODO_TRASH" 2>/dev/null; then
        streak=$((streak + 1))
        day_offset=$((day_offset + 1))
    else
        break
    fi
done

echo "$streak"
