#!/usr/bin/env bash
set -e
NOTES="$HOME/notes"
INBOX="$NOTES/00_inbox"
shopt -s nullglob
DESTINOS=(
  "01_projects"
  "01_projects/empresa"
  "01_projects/General"
  "01_projects/guapeton"
  "01_projects/home_lab"
  "01_projects/nebu-guard"
  "01_projects/parkings"
  "01_projects/piso"
  "02_areas"
  "02_areas/books"
  "02_areas/devops"
  "02_areas/devops/ansible"
  "02_areas/devops/docker"
  "02_areas/devops/jenkins"
  "02_areas/devops/kubernetes"
  "02_areas/Educacion"
  "02_areas/Educacion/asir"
  "02_areas/Educacion/python"
  "02_areas/Finanzas"
  "02_areas/personal"
  "02_areas/personal/finanzas"
  "02_areas/personal/varios"
  "02_areas/programacion"
  "02_areas/programacion/bash"
  "02_areas/programacion/python"
  "02_areas/salud"
  "03_recursos"
  "03_recursos/AI_Prompts"
  "03_recursos/estudios"
  "03_recursos/sistema"
  "03_recursos/varios"
  "04_archivo"
  "04_archivo/personal"
  "04_archivo/work_2024-2026_BBVA"
)
preview_nota() { grep -v "^---" "$1" | grep -v "^date:" | grep -v "^tags:" | grep -v "^$" | head -5; }
clasificar() {
  local buscar=$(echo "$1 $2" | tr '[:upper:]' '[:lower:]')
  case "$buscar" in
    *sai-lunes*|*idegpl*|*a3spje*|*eides*|*update-a3spje*|*migracion-eides*) echo "04_archivo/work_2024-2026_BBVA"; return ;;
    *permisos-sonar*) echo "02_areas/devops/ansible"; return ;;
    *django-setup*|*djnago-crear*) echo "02_areas/programacion"; return ;;
    *errores-vim*|*solventar-errores-nvim*|*recomendacion-plugins-nvim*) echo "02_areas/programacion"; return ;;
    *ruta-aprender-python*) echo "02_areas/Educacion/python"; return ;;
    *gentoo-install*|*plan-gentoo-delos*) echo "02_areas/devops"; return ;;
    *estrategia-cartera*|*trading-staking*|*trading*|*staking*|*airdrops*|*idea-radaracciones*) echo "02_areas/Finanzas"; return ;;
    *descargo-ansiedad*) echo "02_areas/salud"; return ;;
    *estructura-lab-rax*|*instruciones-esquema-bunker*|*dispositivos-iot*|*definicion_stack*|*segmentacion_datos*|*config-hermes*) echo "01_projects/home_lab"; return ;;
    *extracto-mentoria-linkedin*|*teclado-mecanico-actual*) echo "02_areas/personal"; return ;;
    *guia-bash-python*|*herramientas-cli*|*hash-grub-gmktec*|*limpieza-navegador*|*remapear-key-archlinux*) echo "03_recursos/varios"; return ;;
    *mensaje-*|*pruebas-rendimientos-modelos*|*jarvis-api-gemmini*|*idea-proyecto*|*learning*) echo "03_recursos/varios"; return ;;
    *nebu-guard*|*escalado-nebu*|*lanzamiento-saas*|*roadmap-mvp*) echo "01_projects/nebu-guard"; return ;;
    *pagar-menos-impuestos*) echo "02_areas/Finanzas"; return ;;
    *openshift-local*) echo "03_recursos/sistema"; return ;;
    *keybinds-cheatsheet*|*setup-nuevo-ordenador*) echo "03_recursos/sistema"; return ;;
    *conversa-ac*|*new-job-plexus*) echo "04_archivo/personal"; return ;;
    *python*|*bash*|*sysadmin*) echo "02_areas/programacion"; return ;;
    *django*|*vim*|*nvim*|*neovim*|*plugins*) echo "02_areas/programacion"; return ;;
    *gentoo*|*delos*) echo "02_areas/devops"; return ;;
    *lab*|*rax*|*esquema*|*bunker*) echo "01_projects/home_lab"; return ;;
    *mentoria*|*linkedin*|*carta*|*muerte*|*teclado*) echo "02_areas/personal"; return ;;
    *guia*|*cli*|*hash*|*grub*|*archlinux*) echo "03_recursos/varios"; return ;;
  esac
  echo "03_recursos/varios"
}
# --brain: solo brain_dump (para el atajo SUPER+Alt+T)
if [[ "${1:-}" == "--brain" ]]; then
  mapfile -t todas < <(ls "$INBOX"/brain_dump/*.md 2>/dev/null)
else
  mapfile -t todas < <(ls "$INBOX"/*.md "$INBOX"/brain_dump/*.md 2>/dev/null)
fi
notas=()
for n in "${todas[@]}"; do [[ "$(basename "$n")" != "README.md" ]] && notas+=("$n"); done
if [[ ${#notas[@]} -eq 0 ]]; then notify-send "📥 Inbox vacío" "No hay notas para clasificar"; exit 0; fi
# Paso 0: mostrar la lista y elegir (Shift+Enter = múltiple, Esc = todas)
menu_files=()
for nota in "${notas[@]}"; do
  menu_files+=("$(basename "$nota" .md | tr '-' ' ' | sed 's/\b./\u&/g')")
done
elegidos=$(printf "%s\n" "${menu_files[@]}" | rofi -dmenu -multi-select -p "📥 Inbox (${#notas[@]})" -mesg "Elige notas (Shift+Enter múltiple, Esc = todas)" -theme ~/.config/rofi/config.rasi 2>/dev/null)
if [[ -n "$elegidos" ]]; then
  filtradas=()
  while IFS= read -r lin; do
    for nota in "${notas[@]}"; do
      titulo_f=$(basename "$nota" .md | tr '-' ' ' | sed 's/\b./\u&/g')
      [[ "$titulo_f" == "$lin" ]] && filtradas+=("$nota")
    done
  done <<< "$elegidos"
  notas=("${filtradas[@]}")
fi
if [[ ${#notas[@]} -eq 0 ]]; then notify-send "📥 Inbox vacío" "No hay notas para clasificar"; exit 0; fi
movidas=0; saltadas=0
for nota in "${notas[@]}"; do
  [[ -d "$nota" ]] && continue
  preview=$(preview_nota "$nota")
  titulo=$(basename "$nota" .md | tr '-' ' ' | sed 's/\b./\u&/g')
  contenido=$(cat "$nota" 2>/dev/null)
  sugerencia=$(clasificar "$contenido" "$(basename "$nota")")
  [[ ! -d "$NOTES/$sugerencia" ]] && sugerencia="03_recursos/varios"
  destinos_validos=()
  for d in "${DESTINOS[@]}"; do [[ -d "$NOTES/$d" ]] && destinos_validos+=("$d"); done
  header="📄 $titulo"
  opciones=("$header" "" "✅ $sugerencia" "")
  for d in "${destinos_validos[@]}"; do [[ "$d" != "$sugerencia" ]] && opciones+=("📁 $d"); done
  opciones+=("" "⏭ Saltar" "🚪 Salir")
  sel=$(printf "%s\n" "${opciones[@]}" | rofi -dmenu -p "📥" -mesg "$preview" -theme ~/.config/rofi/config.rasi 2>/dev/null)
  [[ -z "$sel" || "$sel" == "🚪 Salir" || "$sel" == "$header" ]] && break
  if [[ "$sel" == "⏭ Saltar" || "$sel" == "" ]]; then saltadas=$((saltadas+1)); continue; fi
  dest=${sel#✅ }; dest=${dest#📁 }
  if [[ ! -d "$NOTES/$dest" ]]; then notify-send "❌ No existe" "$dest"; saltadas=$((saltadas+1)); continue; fi
  if mv "$nota" "$NOTES/$dest/$(basename "$nota")"; then movidas=$((movidas+1)); else saltadas=$((saltadas+1)); fi
  notify-send "📦 Clasificada" "$titulo → $dest"
done
resumen="✅ $movidas movidas"
[[ $saltadas -gt 0 ]] && resumen+=" | ⏭ $saltadas saltadas"
notify-send "📥 Inbox procesado" "$resumen"
