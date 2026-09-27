#!/usr/bin/env bats
# Tests for task helpers in core.sh

setup() {
    export HUB_ROOT="/tmp/tdo-test-$$"
    export TODO_ACTIVO="$HUB_ROOT/todo.md"
    export TODO_TRASH="$HUB_ROOT/trash.md"
    export SESSION_LOG="$HUB_ROOT/session.log"
    export BLOCK_FILE="$HUB_ROOT/bloqueo.txt"
    export PHRASES_FILE="$HUB_ROOT/phrases.txt"
    export NOTES_DIR="$HUB_ROOT/notes"
    export INBOX_DIR="$HUB_ROOT/inbox"
    export TEMPLATES_DIR="$HUB_ROOT/templates"
    export JOURNAL_DIR="$HUB_ROOT/journal"
    export TODOS_DIR="$HUB_ROOT/todos"
    export TODO_ACTIVO="$TODOS_DIR/todo.md"
    mkdir -p "$HUB_ROOT" "$NOTES_DIR" "$INBOX_DIR" "$TEMPLATES_DIR" "$JOURNAL_DIR" "$TODOS_DIR"
    echo "# Test phrases" > "$PHRASES_FILE"
    echo "Dale." >> "$PHRASES_FILE"
    source "$BATS_TEST_DIRNAME/../core.sh" 2>/dev/null
}

teardown() {
    rm -rf "$HUB_ROOT"
}

# parse_task_date tests
@test "parse_task_date extracts due date" {
    run parse_task_date "task due:2024-01-15"
    [ "$output" = "2024-01-15" ]
}

@test "parse_task_date returns empty for no date" {
    run parse_task_date "task without date"
    [ "$output" = "" ]
}

@test "parse_task_date handles multiple dates (first match)" {
    run parse_task_date "task due:2024-01-15 due:2024-01-20"
    [ "$output" = "2024-01-15" ]
}

# is_task_overdue tests
@test "is_task_overdue returns 0 for past date" {
    run is_task_overdue "task due:2020-01-01"
    [ "$status" -eq 0 ]
}

@test "is_task_overdue returns 1 for future date" {
    run is_task_overdue "task due:2099-01-01"
    [ "$status" -eq 1 ]
}

@test "is_task_overdue returns 2 for no date" {
    run is_task_overdue "task without date"
    [ "$status" -eq 2 ]
}

# get_task_priority tests
@test "get_task_priority returns high for !!" {
    run get_task_priority "!! urgent task"
    [ "$output" = "high" ]
}

@test "get_task_priority returns medium for !" {
    run get_task_priority "! normal task"
    [ "$output" = "medium" ]
}

@test "get_task_priority returns normal for no prefix" {
    run get_task_priority "normal task"
    [ "$output" = "normal" ]
}

@test "get_task_priority prioritizes !! over !" {
    run get_task_priority "!! task with !"
    [ "$output" = "high" ]
}

# get_task_categories tests
@test "get_task_categories extracts @tags" {
    run get_task_categories "task @work @personal @urgent"
    [ "$output" = "personal
urgent
work" ]
}

@test "get_task_categories returns empty for no tags" {
    run get_task_categories "task without tags"
    [ "$output" = "" ]
}

@test "get_task_categories deduplicates tags" {
    run get_task_categories "task @work @work @personal"
    [ "$output" = "personal
work" ]
}

# get_task_base tests
@test "get_task_base strips due date" {
    run get_task_base "task due:2024-01-15"
    [ "$output" = "task" ]
}

@test "get_task_base strips repeat" {
    run get_task_base "task repeat:daily"
    [ "$output" = "task" ]
}

@test "get_task_base strips @tags" {
    run get_task_base "task @work @personal"
    [ "$output" = "task" ]
}

@test "get_task_base strips 🎯 marker" {
    run get_task_base "🎯 task with marker"
    [ "$output" = "task with marker" ]
}

@test "get_task_base strips all metadata" {
    run get_task_base "!! 🎯 task due:2024-01-15 @work repeat:daily"
    [ "$output" = "task" ]
}

# sort_by_priority tests
@test "sort_by_priority sorts by due date bucket then priority" {
    cat > "$TODO_ACTIVO" <<'EOF'
- [ ] !! overdue task due:2020-01-01
- [ ] normal task due:2020-01-01
- [ ] ! today task due:2024-01-15
- [ ] normal today task due:2024-01-15
- [ ] future task due:2099-01-01
- [ ] no date task
EOF
    run sort_by_priority "$(get_all_tasks)"
    # Should be: overdue (!! first), today (! first), future, no-date
    lines=($output)
    [[ "${lines[0]}" =~ "overdue task" ]]
    [[ "${lines[1]}" =~ "normal task" ]]
    [[ "${lines[2]}" =~ "today task" ]]
    [[ "${lines[3]}" =~ "normal today task" ]]
    [[ "${lines[4]}" =~ "future task" ]]
    [[ "${lines[5]}" =~ "no date task" ]]
}

# filter_tasks_by_date tests
@test "filter_tasks_by_date overdue returns only overdue" {
    local tasks="task1 due:2020-01-01
task2 due:2099-01-01"
    run filter_tasks_by_date "overdue" "$tasks"
    [ "$output" = "task1 due:2020-01-01" ]
}

@test "filter_tasks_by_date today returns only today" {
    local today=$(date +%Y-%m-%d)
    local tasks="task1 due:$today
task2 due:2099-01-01"
    run filter_tasks_by_date "today" "$tasks"
    [ "$output" = "task1 due:$today" ]
}

@test "filter_tasks_by_date no-date returns tasks without due" {
    local tasks="task1 due:2024-01-15
task2 no date
task3"
    run filter_tasks_by_date "no-date" "$tasks"
    [[ "$output" =~ "task2" ]]
    [[ "$output" =~ "task3" ]]
    [[ ! "$output" =~ "task1" ]]
}

# parse_recurrence tests
@test "parse_recurrence extracts daily" {
    run parse_recurrence "task repeat:daily"
    [ "$output" = "daily" ]
}

@test "parse_recurrence extracts weekly" {
    run parse_recurrence "task repeat:weekly"
    [ "$output" = "weekly" ]
}

@test "parse_recurrence extracts monthly" {
    run parse_recurrence "task repeat:monthly"
    [ "$output" = "monthly" ]
}

@test "parse_recurrence returns empty for no repeat" {
    run parse_recurrence "task due:2024-01-15"
    [ "$output" = "" ]
}

# expand_recurring_task tests
@test "expand_recurring_task updates due date for daily" {
    run expand_recurring_task "task due:2024-01-15 repeat:daily"
    [[ "$output" =~ "due:2024-01-16" ]]
}

@test "expand_recurring_task updates due date for weekly" {
    run expand_recurring_task "task due:2024-01-15 repeat:weekly"
    [[ "$output" =~ "due:2024-01-22" ]]
}

@test "expand_recurring_task updates due date for monthly" {
    run expand_recurring_task "task due:2024-01-15 repeat:monthly"
    [[ "$output" =~ "due:2024-02-15" ]]
}

@test "expand_recurring_task returns 1 for no repeat" {
    run expand_recurring_task "task due:2024-01-15"
    [ "$status" -eq 1 ]
}

# get_all_tasks tests
@test "get_all_tasks returns only pending tasks" {
    cat > "$TODO_ACTIVO" <<'EOF'
- [ ] pending task 1
- [x] done task 1
- [ ] pending task 2
- [ ] pending task 3
EOF
    run get_all_tasks
    lines=($output)
    [ "${#lines[@]}" -eq 3 ]
    [[ ! "$output" =~ "done task" ]]
}

@test "get_all_tasks handles multiline tasks" {
    cat > "$TODO_ACTIVO" <<'EOF'
- [ ] multiline task
  due:2024-01-15
  @work
- [ ] simple task
EOF
    run get_all_tasks
    lines=($output)
    [ "${#lines[@]}" -eq 2 ]
    [[ "$output" =~ "multiline task" ]]
    [[ "$output" =~ "due:2024-01-15" ]]
    [[ "$output" =~ "@work" ]]
}