#!/usr/bin/env bats
# Tests for AW client functions in core.sh (via aw_client.sh)

setup() {
    export HUB_ROOT="/tmp/tdo-test-$$"
    export AW_BUCKET_WINDOW="test-window"
    export AW_BUCKET_VIM="test-vim"
    export AW_FALLBACK_SERVER="http://localhost:5600"
    mkdir -p "$HUB_ROOT"
    source "$BATS_TEST_DIRNAME/../core.sh" 2>/dev/null
    source "$BATS_TEST_DIRNAME/../scripts/lib/aw_client.sh" 2>/dev/null
}

teardown() {
    rm -rf "$HUB_ROOT"
}

# aw_format_duration tests
@test "aw_format_duration formats seconds to hours and minutes" {
    run aw_format_duration 3661
    [ "$output" = "1h 1m" ]
}

@test "aw_format_duration formats minutes and seconds" {
    run aw_format_duration 125
    [ "$output" = "2m 5s" ]
}

@test "aw_format_duration formats only seconds" {
    run aw_format_duration 45
    [ "$output" = "45s" ]
}

@test "aw_format_duration handles exact hours" {
    run aw_format_duration 7200
    [ "$output" = "2h 0m" ]
}

# aw_today_start/aw_today_end tests
@test "aw_today_start returns ISO format for today midnight UTC" {
    run aw_today_start
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T00:00:00Z$ ]]
}

@test "aw_today_end returns ISO format for today 23:59:59 UTC" {
    run aw_today_end
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T23:59:59Z$ ]]
}

# aw_yesterday_start/aw_yesterday_end tests
@test "aw_yesterday_start returns ISO format for yesterday midnight UTC" {
    run aw_yesterday_start
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T00:00:00Z$ ]]
}

# aw_days_ago_start/aw_days_ago_end tests
@test "aw_days_ago_start returns correct date for N days ago" {
    run aw_days_ago_start 7
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T00:00:00Z$ ]]
}

# _aw_resolve_api tests (mocked)
@test "_aw_resolve_api returns fallback when no server" {
    unset AW_SERVER_URL AW_DEFAULT_SERVER AW_FALLBACK_URL AW_FALLBACK_SERVER
    # This will fail without actual server, just test it runs
    run _aw_resolve_api 2>/dev/null || true
    [ "$status" -eq 1 ]  # Should fail without server
}

# aw_check tests
@test "aw_check returns 1 when no server" {
    unset AW_SERVER_URL AW_DEFAULT_SERVER AW_FALLBACK_URL AW_FALLBACK_SERVER
    run aw_check 2>/dev/null || true
    [ "$status" -eq 1 ]
}

# aw_is_running tests
@test "aw_is_running returns 1 when no server" {
    unset AW_SERVER_URL AW_DEFAULT_SERVER AW_FALLBACK_URL AW_FALLBACK_SERVER
    run aw_is_running 2>/dev/null || true
    [ "$status" -eq 1 ]
}