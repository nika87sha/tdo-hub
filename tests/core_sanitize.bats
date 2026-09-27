#!/usr/bin/env bats
# Tests for sanitize functions in core.sh (via sanitize.sh)

setup() {
    export HUB_ROOT="/tmp/tdo-test-$$"
    mkdir -p "$HUB_ROOT"
    source "$BATS_TEST_DIRNAME/../core.sh" 2>/dev/null
}

teardown() {
    rm -rf "$HUB_ROOT"
}

# sanitize_for_sed tests
@test "sanitize_for_sed escapes forward slash" {
    run sanitize_for_sed "path/to/file"
    [ "$output" = "path\/to\/file" ]
}

@test "sanitize_for_sed escapes backslash" {
    run sanitize_for_sed "path\\to\\file"
    [ "$output" = "path\\\\to\\\\file" ]
}

@test "sanitize_for_sed escapes ampersand" {
    run sanitize_for_sed "foo&bar"
    [ "$output" = "foo\&bar" ]
}

@test "sanitize_for_sed escapes regex metacharacters" {
    run sanitize_for_sed "foo.bar*baz+qux?foo"
    [ "$output" = "foo\.bar\*baz\+qux\?foo" ]
}

@test "sanitize_for_sed escapes brackets and parentheses" {
    run sanitize_for_sed "foo[bar]baz(qux)"
    [ "$output" = "foo\[bar\]baz\(qux\)" ]
}

@test "sanitize_for_sed handles empty string" {
    run sanitize_for_sed ""
    [ "$output" = "" ]
}

# sanitize_for_regex tests
@test "sanitize_for_regex escapes regex metacharacters" {
    run sanitize_for_regex "foo.bar*baz+qux?"
    [ "$output" = "foo\.bar\*baz\+qux\?" ]
}

@test "sanitize_for_regex handles anchors" {
    run sanitize_for_regex "^foo$"
    [ "$output" = "\^foo\$" ]
}

# sanitize_for_shell tests
@test "sanitize_for_shell escapes special chars" {
    run sanitize_for_shell 'foo$bar`baz'
    [[ "$output" =~ \\$ ]]
    [[ "$output" =~ \` ]]
}

# sanitize_filename tests
@test "sanitize_filename removes dangerous chars" {
    run sanitize_filename 'foo/bar:baz*qux?foo'
    [ "$output" = "foobarbazquxfoo" ]
}

@test "sanitize_filename preserves safe chars" {
    run sanitize_filename "foo-bar_baz.qux foo"
    [ "$output" = "foo-bar_baz.qux foo" ]
}

@test "sanitize_filename trims whitespace" {
    run sanitize_filename "  foo  bar  "
    [ "$output" = "foo  bar" ]
}

# validate_safe_input tests
@test "validate_safe_input rejects path traversal" {
    run validate_safe_input "../etc/passwd" "path"
    [ "$status" -eq 1 ]
}

@test "validate_safe_input rejects absolute paths" {
    run validate_safe_input "/etc/passwd" "path"
    [ "$status" -eq 1 ]
}

@test "validate_safe_input accepts safe filename" {
    run validate_safe_input "foo-bar_baz.txt" "filename"
    [ "$status" -eq 0 ]
}

@test "validate_safe_input rejects shell metacharacters" {
    run validate_safe_input 'foo$bar' "general"
    [ "$status" -eq 1 ]
}

# sanitize_and_validate tests
@test "sanitize_and_validate sed context" {
    run sanitize_and_validate "foo/bar" "sed"
    [ "$status" -eq 0 ]
    [ "$output" = "foo\/bar" ]
}

@test "sanitize_and_validate rejects dangerous in path context" {
    run sanitize_and_validate "../etc/passwd" "path"
    [ "$status" -eq 1 ]
}

# sanitize_for_json tests
@test "sanitize_for_json escapes quotes and backslashes" {
    run sanitize_for_json 'foo"bar\baz'
    [ "$output" = "foo\"bar\\baz" ]
}

@test "sanitize_for_json escapes newlines and tabs" {
    run sanitize_for_json $'foo\nbar\tbaz'
    [[ "$output" =~ \\n ]]
    [[ "$output" =~ \\t ]]
}

# sanitize_for_url tests
@test "sanitize_for_url encodes spaces" {
    run sanitize_for_url "foo bar"
    [ "$output" = "foo%20bar" ]
}

@test "sanitize_for_url encodes special chars" {
    run sanitize_for_url 'foo&bar=baz'
    [ "$output" = "foo%26bar%3Dbaz" ]
}