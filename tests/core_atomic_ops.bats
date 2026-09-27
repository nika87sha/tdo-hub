#!/usr/bin/env bats
# Tests for atomic file operations in core.sh

setup() {
    export HUB_ROOT="/tmp/tdo-test-$$"
    export TODO_ACTIVO="$HUB_ROOT/todo.md"
    export TODO_TRASH="$HUB_ROOT/trash.md"
    export SESSION_LOG="$HUB_ROOT/session.log"
    mkdir -p "$HUB_ROOT"
    source "$BATS_TEST_DIRNAME/../core.sh" 2>/dev/null
}

teardown() {
    rm -rf "$HUB_ROOT"
}

@test "atomic_sed_replace creates file if not exists" {
    atomic_sed_replace "$TODO_ACTIVO" "s/foo/bar/"
    [ -f "$TODO_ACTIVO" ]
}

@test "atomic_sed_replace replaces pattern correctly" {
    echo "foo bar baz" > "$TODO_ACTIVO"
    atomic_sed_replace "$TODO_ACTIVO" "s/foo/FOO/"
    run cat "$TODO_ACTIVO"
    [ "$output" = "FOO bar baz" ]
}

@test "atomic_sed_replace preserves file on error" {
    echo "original content" > "$TODO_ACTIVO"
    # Invalid sed expression should not corrupt file
    atomic_sed_replace "$TODO_ACTIVO" "s/[invalid/" 2>/dev/null || true
    run cat "$TODO_ACTIVO"
    [ "$output" = "original content" ]
}

@test "atomic_write_tasks writes content atomically" {
    atomic_write_tasks "$TODO_ACTIVO" "line1\nline2\nline3"
    run cat "$TODO_ACTIVO"
    [ "$output" = "line1
line2
line3" ]
}

@test "atomic_read_tasks reads file with lock" {
    echo -e "task1\ntask2" > "$TODO_ACTIVO"
    run atomic_read_tasks "$TODO_ACTIVO"
    [ "$output" = "task1
task2" ]
}

@test "concurrent atomic writes don't corrupt" {
    # Simulate concurrent writes
    for i in {1..10}; do
        atomic_write_tasks "$TODO_ACTIVO" "write $i" &
    done
    wait
    [ -f "$TODO_ACTIVO" ]
    run cat "$TODO_ACTIVO"
    [[ "$output" =~ "write" ]]
}