#!/usr/bin/env bash
# Config: .env manda, defaults genéricos sin .env completo.
# Usa la copia aislada $TDO_HUB.

H="$TDO_HUB"
fail=0
check() { # check <desc> <condición-comando...>
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then echo "  ✓ $desc";
    else echo "  ✗ $desc"; fail=$((fail + 1)); fi
}

# 1. .env completo manda (incluidas derivadas personalizadas)
cat > "$H/.env" <<'EOF2'
HUB_ROOT="__H__"
NOTES_DIR="__T__/vault"
PROJECTS_DIR="$NOTES_DIR/01_projects"
TODOS_DIR="$PROJECTS_DIR/General/todos"
TODO_ACTIVO="$TODOS_DIR/todo_ACTIVO.md"
JOURNAL_DIR="$NOTES_DIR/02_areas/personal/journal"
TEMPLATES_DIR="$NOTES_DIR/templates"
INBOX_DIR="$NOTES_DIR/00_inbox"
SESSION="tdo-test-session"
AW_DEFAULT_SERVER="http://127.0.0.1:9"
AW_FALLBACK_SERVER="http://127.0.0.1:9"
EOF2
sed -i "s|__H__|$H|; s|__T__|$TDO_TMP|" "$H/.env"

vals=$(env -i HOME=/root PATH=/usr/bin:/bin HUB_ROOT="$H" bash -c 'source "$HUB_ROOT/config.sh" >/dev/null 2>&1; echo "$TODO_ACTIVO|$JOURNAL_DIR|$SESSION|$AW_DEFAULT_SERVER"')
check ".env manda en derivadas" test "$vals" = "$TDO_TMP/vault/01_projects/General/todos/todo_ACTIVO.md|$TDO_TMP/vault/02_areas/personal/journal|tdo-test-session|http://127.0.0.1:9"

# 2. Sin .env personalizado: defaults genéricos (sin rutas P.A.R.A. de nadie)
rm "$H/.env"
vals2=$(env -i HOME=/root PATH=/usr/bin:/bin HUB_ROOT="$H" bash -c 'source "$HUB_ROOT/config.sh" >/dev/null 2>&1; echo "$PROJECTS_DIR|$JOURNAL_DIR|$AW_DEFAULT_SERVER"')
check "defaults genéricos sin P.A.R.A." test "$vals2" = "/root/notes/projects|/root/notes/journal|"
check "sin rastro de layout personal" bash -c "! grep -q '01_projects\|02_areas' \"$H/config.sh\""

echo "RESULT fail=$fail"
exit $((fail > 0))
