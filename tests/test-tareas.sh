#!/usr/bin/env bash
# Tareas Done vía tareas.sh con rofi falso (respuestas en secuencia).
# Fixture todo en la copia aislada $TDO_HUB.

H="$TDO_HUB"
V="$TDO_TMP/vault"
fail=0
ok() { echo "  ✓ $1"; }
bad() { echo "  ✗ $1"; fail=$((fail + 1)); }

mkdir -p "$V/01_projects/General/todos"
printf -- '- [ ] !! Tarea DONE-ME-111\n- [ ] Tarea intacta 222\n' > "$V/01_projects/General/todos/todo_ACTIVO.md"
: > "$H/trash.md"

cat > "$H/.env" <<'EOF'
HUB_ROOT="__H__"
NOTES_DIR="__V__"
PROJECTS_DIR="$NOTES_DIR/01_projects"
TODOS_DIR="$PROJECTS_DIR/General/todos"
TODO_ACTIVO="$TODOS_DIR/todo_ACTIVO.md"
TODO_TRASH="$HUB_ROOT/trash.md"
JOURNAL_DIR="$NOTES_DIR/journal"
TEMPLATES_DIR="$NOTES_DIR/templates"
INBOX_DIR="$NOTES_DIR/inbox"
SESSION="tdo-test-session"
AW_DEFAULT_SERVER="http://127.0.0.1:9"
AW_FALLBACK_SERVER="http://127.0.0.1:9"
EOF
sed -i "s|__H__|$H|; s|__V__|$V|" "$H/.env"

# Rofi falso con estado: 1ª llamada → elige tarea (código 10 = Alt+c Done),
# resto → vacío (código 1 = cancelar).
mkdir -p "$TDO_TMP/fakebin"
cat > "$TDO_TMP/fakebin/rofi" <<'EOF2'
#!/usr/bin/env bash
n=$(cat "$TDO_TMP/rofistate" 2>/dev/null || echo 0)
n=$((n + 1)); echo "$n" > "$TDO_TMP/rofistate"
input=$(cat)
if [[ "$n" == "1" ]]; then
    echo "$input" | head -1
    exit 10
fi
exit 1
EOF2
chmod +x "$TDO_TMP/fakebin/rofi"
echo 0 > "$TDO_TMP/rofistate"

PATH="$TDO_TMP/fakebin:$PATH" bash "$H/scripts/tareas.sh" >/dev/null 2>&1

grep -q "DONE-ME-111" "$H/trash.md" && ok "Done va a trash" || bad "Done va a trash"
grep -q "^- \[x\] !! Tarea DONE-ME-111" "$V/01_projects/General/todos/todo_ACTIVO.md" && ok "todo marcado [x]" || bad "todo marcado [x]"
grep -q "^- \[ \] Tarea intacta 222" "$V/01_projects/General/todos/todo_ACTIVO.md" && ok "el resto intacto" || bad "el resto intacto"

echo "RESULT fail=$fail"
exit $((fail > 0))
