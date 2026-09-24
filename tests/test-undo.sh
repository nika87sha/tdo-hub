#!/usr/bin/env bash
# Undo vía undo.sh con rofi falso. Fixture en copia aislada.

H="$TDO_HUB"
V="$TDO_TMP/vault"
fail=0

mkdir -p "$V/01_projects/General/todos"
printf -- '- [ ] Tarea A\n' > "$V/01_projects/General/todos/todo_ACTIVO.md"

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
EOF
sed -i "s|__H__|$H|; s|__V__|$V|" "$H/.env"
printf -- '- [x] 2026-09-20 Tarea RESTORE-ME-333\n' > "$H/trash.md"

mkdir -p "$TDO_TMP/fakebin2"
cat > "$TDO_TMP/fakebin2/rofi" <<'EOF2'
#!/usr/bin/env bash
cat >/dev/null
echo "- [x] 2026-09-20 Tarea RESTORE-ME-333"
EOF2
chmod +x "$TDO_TMP/fakebin2/rofi"

PATH="$TDO_TMP/fakebin2:$PATH" bash "$H/scripts/notes/undo.sh" >/dev/null 2>&1

if grep -q "RESTORE-ME-333" "$V/01_projects/General/todos/todo_ACTIVO.md"; then
    echo "  ✓ undo restaura"
else
    echo "  ✗ undo restaura"; fail=$((fail + 1))
fi

echo "RESULT fail=$fail"
exit $((fail > 0))
