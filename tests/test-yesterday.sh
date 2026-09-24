#!/usr/bin/env bash
# Ayer: journal de AYER (nunca el de hoy) + tareas de TODO_ACTIVO.
# Fixture vault en la copia aislada $TDO_HUB.

H="$TDO_HUB"
V="$TDO_TMP/vault"
fail=0
check() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then echo "  ✓ $desc";
    else echo "  ✗ $desc"; fail=$((fail + 1)); fi
}
check_out() { # check_out <desc> <hay> <texto>
    local desc="$1" want="$2" text="$3"
    if echo "$text" | grep -qF "$want"; then echo "  ✓ $desc";
    else echo "  ✗ $desc (falta: $want)"; fail=$((fail + 1)); fi
}
check_absent() {
    local desc="$1" want="$2" text="$3"
    if echo "$text" | grep -qF "$want"; then echo "  ✗ $desc (aparece: $want)"; fail=$((fail + 1));
    else echo "  ✓ $desc"; fi
}

YD=$(date -d "yesterday" +%Y-%m-%d)
TD=$(date +%Y-%m-%d)
YY=$(date -d "$YD" +%Y); YM=$(date -d "$YD" +%m)
TY=$(date +%Y); TM=$(date +%m)

mkdir -p "$V/02_areas/personal/journal/$YY/$YM" "$V/02_areas/personal/journal/$TY/$TM" "$V/01_projects/General/todos" "$V/templates"
echo "# Journal AYER-MARKER-123" > "$V/02_areas/personal/journal/$YY/$YM/$YD.md"
echo "# Journal HOY-MARKER-456" > "$V/02_areas/personal/journal/$TY/$TM/$TD.md"
printf -- '- [ ] !! Tarea pendiente FIXTURE-789\n- [x] Hecha vieja\n' > "$V/01_projects/General/todos/todo_ACTIVO.md"
echo "# entry" > "$V/templates/entry.md"

cat > "$H/.env" <<'EOF'
HUB_ROOT="__H__"
NOTES_DIR="__V__"
PROJECTS_DIR="$NOTES_DIR/01_projects"
TODOS_DIR="$PROJECTS_DIR/General/todos"
TODO_ACTIVO="$TODOS_DIR/todo_ACTIVO.md"
JOURNAL_DIR="$NOTES_DIR/02_areas/personal/journal"
TEMPLATES_DIR="$NOTES_DIR/templates"
INBOX_DIR="$NOTES_DIR/00_inbox"
SESSION="tdo-test-session"
AW_SERVER_URL="http://127.0.0.1:9"
AW_DEFAULT_SERVER="http://127.0.0.1:9"
AW_FALLBACK_URL="http://127.0.0.1:9"
AW_FALLBACK_SERVER="http://127.0.0.1:9"
EOF
sed -i "s|__H__|$H|; s|__V__|$V|" "$H/.env"

out=$(bash "$H/scripts/notes/yesterday.sh" 2>/dev/null)
code=$?
check "exit 0" test "$code" -eq 0
check_out "muestra journal de ayer" "AYER-MARKER-123" "$out"
check_absent "no muestra journal de hoy" "HOY-MARKER-456" "$out"
check_out "muestra tareas pendientes" "FIXTURE-789" "$out"

echo "RESULT fail=$fail"
exit $((fail > 0))
