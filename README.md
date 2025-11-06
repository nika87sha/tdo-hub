# TDO Hub

Un menú de productividad con atajos de teclado para capturar tareas, llevar journal, enfocar y ver estadísticas. Hyprland + rofi + tmux.

---

## Índice

- [Funciones principales](#funciones-principales)
- [Estructura](#estructura)
- [Configuración](#configuración)
- [Uso](#uso)
  - [Atajos de teclado (esenciales 8)](#atajos-de-teclado-esenciales-8)
  - [Menú Hub (SUPER+N) — Menú en una sola pantalla](#menú-hub-supern---menú-en-una-sola-pantalla)
  - [Focus Mode](#focus-mode)
  - [Música](#música)
  - ["¿Qué estaba haciendo ayer?"](#-qué-estaba-haciendo-ayer-superalt-y-)
  - [Brain dump y notas de voz](#brain-dump-y-notas-de-voz-superaltt-b-superaltt-t-superalt-m-)
  - [Flow State Detector](#flow-state-detector-superaltd-)
  - [Sistema de Recompensas](#sistema-de-recompensas)
  - [Integración Waybar (Pomodoro)](#integración-waybar-pomodoro)
- [Tests](#tests)
- [Aliases útiles](#aliases-útiles)
- [Cron jobs](#cron-jobs)
- [Licencia](#licencia)

---

## Funciones principales

| Icono | Función | Descripción |
|-------|---------|-------------|
| 📝 | Capturar | Nueva nota o tarea rápida |
| 🔍 | Buscar | Buscar en notas con fzf en tmux |
| 📋 | Tareas | Lista de tareas con prioridades |
| 📓 | Journal | Diario del día |
| 🔯 | Ayer | Resumen de actividad + journal + tareas |
| 🍅 | Enfocar | Activar Focus Mode con bloqueo |
| ⏱️ | Time | Resumen timewarrior |
| 🧠 | Flow | Detectar flow state actual |
| 🎁 | Reward | Ver recompensas disponibles |
| 📊 | Stats | Estadísticas ActivityWatch |
| 🎵 | Música | Menú de música (shuffle, folders, playlists) |
| 🎲 | Redescubrir | Nota aleatoria del día |
| 📥 | Organizar | Clasificar inbox automáticamente |
| 🔄 | Sync | Sync notas con git |
| ↩️ | Undo | Deshacer última acción |
| ⚙️ | Config | Editar configuración / ver rutas / limpiar caché |
| 🛑 | Pánico | Modo emergencia para parar todo |

| ⚙️ | Config | Editar configuración / ver rutas / limpiar caché |
| 🛑 | Pánico | Modo emergencia para parar todo |

---

## Estructura

```
tdo-hub/
├── hub.sh                  # Menú principal (rofi)
├── core.sh                 # Funciones compartidas
├── config.sh               # Configuración central (carga .env)
├── .env.example            # Ejemplo de configuración
├── .env                    # Tu configuración personal (no se sube)
├── scripts/
│   ├── focus_mode.sh       # Bloqueo de red + focus
│   ├── focus_music.sh      # Música para focus mode
│   ├── journal.sh          # Diario personal
│   ├── quick-capture-rofi.sh  # Captura interactiva
│   ├── buscar.sh           # Buscar en notas (tmux + fzf)
│   ├── tareas.sh           # Lista de tareas con prioridades
│   ├── undo.sh             # Deshacer última acción
│   ├── config-menu.sh      # Editar config / rutas / caché
│   ├── time.sh             # Resumen timewarrior en tmux
│   ├── brain-dump.sh       # Idea rápida al brain dump del día
│   ├── voice-note.sh       # Graba 5s y transcribe a brain dump
│   ├── aw-stats.sh         # Estadísticas ActivityWatch
│   ├── daily-routine.sh    # Resumen diario
│   ├── streak-tracker.sh   # Tracker de rachas
│   ├── triage-local.sh      # Clasificador de inbox
│   ├── panic_button.sh     # Botón de pánico
│   ├── note-of-the-day.py  # Nota aleatoria del día
│   ├── yesterday.sh        # ¿Qué estaba haciendo ayer?
│   ├── flow-detect.sh      # Flow state detector
│   ├── reward.sh           # Sistema de recompensas
│   ├── pomodoro-daemon.sh  # Daemon pomodoro + estado para waybar
│   ├── pomodoro-waybar.sh  # Módulo custom/pomodoro de waybar
│   ├── mpd_auto_update.sh  # Auto-update de base MPD
│   └── regenerate_playlists.sh  # Regenera playlists de MPD
├── templates/              # Templates por defecto (entry.md, note.md)
├── phrases.txt             # Frases motivacionales
├── bloqueo_distraccion.txt # Dominios bloqueados en focus
└── trash.md                # Papelera de tareas
```

---

## Configuración

### 1. Archivo `.env` (obligatorio)

El proyecto usa un archivo `.env` como **única fuente de rutas y ajustes**. `.env` define todo explícitamente, `config.sh` solo aporta defaults genéricos (sin tu layout ni tus IPs) si algo falta. Cópialo y ajusta lo que necesites:

```bash
cp .env.example .env
```

**Ejemplo de `.env` personalizado:**

```bash
# Tus rutas
NOTES_DIR="$HOME/notes"
PROJECTS_DIR="$NOTES_DIR/01_projects"
TODOS_DIR="$PROJECTS_DIR/todos"
TODO_ACTIVO="$TODOS_DIR/todo_ACTIVO.md"
JOURNAL_DIR="$NOTES_DIR/journal"
TEMPLATES_DIR="$NOTES_DIR/templates"
INBOX_DIR="$NOTES_DIR/00_inbox"

# Tmux
SESSION="work"

# ActivityWatch (opcional)
# Orden de conexión: AW_SERVER_URL → AW_FALLBACK_URL → http://localhost:5600
AW_FALLBACK_URL="http://192.168.1.XXX:5600"  # IP del servidor AW de tu red
# Si el servidor AW genera datos en otra máquina, fijá los buckets a ese host:
# AW_WINDOW_BUCKET="aw-watcher-window_tu_host"
# AW_VIM_BUCKET="aw-watcher-vim_tu_host"
```

> `.env` NO se sube a Git (es personal). `.env.example` sí se sube como referencia.

### 2. Hyprland keybindings (esenciales 8)

Añadir a `~/.config/hypr/UserConfigs/UserKeybinds.conf`:

```conf
# TDO Hub (8 atajos esenciales)
bind = $mainMod, N, exec, $HOME/.local/bin/tdo-hub/hub.sh
bind = $mainMod, J, exec, $HOME/.local/bin/tdo-hub/scripts/journal.sh

# Acciones directas esenciales (cada una a su script, sin pasar por el menú)
bind = $mainMod ALT, Y, exec, $HOME/.local/bin/tdo-hub/scripts/yesterday.sh
bind = $mainMod ALT, D, exec, $HOME/.local/bin/tdo-hub/scripts/flow-detect.sh 25
bind = $mainMod ALT, C, exec, $HOME/.local/bin/tdo-hub/scripts/quick-capture-rofi.sh
bind = $mainMod ALT, U, exec, $HOME/.local/bin/tdo-hub/scripts/buscar.sh
bind = $mainMod ALT, Z, exec, $HOME/.local/bin/tdo-hub/scripts/undo.sh
bind = $mainMod ALT, F, exec, $HOME/.local/bin/tdo-hub/scripts/focus_mode.sh
bind = $mainMod ALT, A, exec, $HOME/.local/bin/tdo-hub/scripts/aw-stats.sh
bind = $mainMod ALT, M, exec, python3 $HOME/.local/bin/tdo-hub/scripts/voice-note.sh
```

### 3. MPD (música)

Crear `~/.config/mpd/mpd.conf`:

```bash
mkdir -p ~/.config/mpd
cat > ~/.config/mpd/mpd.conf << 'EOF'
music_directory "$HOME/Musica"
playlist_directory "$HOME/Musica/playlists"
db_file "$HOME/.mpd/mpd.db"
log_file "$HOME/.mpd/mpd.log"
pid_file "$HOME/.mpd/mpd.pid"
state_file "$HOME/.mpd/mpdstate"
audio_output {
    type "pulse"
    name "pulse audio"
}
bind_to_address "127.0.0.1"
port "6601"
EOF

systemctl --user enable --now mpd
```

> **Nota:** TDO usa puerto `6601` (no el default 6600).

---

## Uso

### Atajos de teclado (esenciales 8)

| Atajo | Acción |
|-------|--------|
| `SUPER+N` | Abrir Hub (menú principal) |
| `SUPER+J` | Journal del día |
| `SUPER+Alt+C` | Capturar (nota o tarea) |
| `SUPER+Alt+U` | Buscar en notas (fzf en tmux) |
| `SUPER+Alt+Z` | Deshacer última acción |
| `SUPER+Alt+Y` | ¿Qué estaba haciendo ayer? |
| `SUPER+Alt+F` | Toggle Focus Mode |
| `SUPER+Alt+D` | Flow state detector |

> Todas las acciones aceptan llamada directa: `hub.sh <accion>`
> (ej: `hub.sh tareas`). Ver `hub.sh help`.
> Cada atajo apunta a su script en `scripts/` sin pasar por el menú:
> capturar→`quick-capture-rofi.sh`, buscar→`buscar.sh`, tareas→`tareas.sh`,
> stats→`aw-stats.sh`, focus→`focus_mode.sh`, deshacer→`undo.sh`,
> ayer→`yesterday.sh`, flow→`flow-detect.sh`.

### Menú Hub (SUPER+N) — Menú en una sola pantalla

El menú Hub (activado con `SUPER+N`) muestra un conjunto de opciones esenciales dispuestas en una sola columna que caben en una sola pantalla sin necesidad de desplazamiento. Usa el tema `themes/hub.rasi`. Cada opción lanza su script asociado directamente:

- **Capturar** → `quick-capture-rofi.sh` (nueva nota o tarea)
- **Buscar** → `buscar.sh` (búsqueda en notas con fzf en tmux)
- **Tareas** → `tareas.sh` (lista de tareas con prioridades)
- **Journal** → `journal.sh` (diario del día)
- **Ayer** → `yesterday.sh` (resumen de actividad del día anterior)
- **Enfocar** → `focus_mode.sh` (bloqueo de distracciones y pomodoro)
- **Deshacer** → `undo.sh` (deshacer última acción)
- **Flow detector** → `flow-detect.sh` (detecta estado de flow)

### Focus Mode

1. Marca una tarea con 🎯 en tu archivo de tareas activas
2. Activa focus: `SUPER+Alt+F` o desde Hub → 🍅 Enfocar
3. Selecciona música (shuffle, directorio específico, o sin música)
4. Se bloquean distracciones y arranca pomodoro
5. Al terminar: desactiva con Hub → 🛑 Parar Focus (stop explícito: si no hay focus activo, no hace nada) o `SUPER+Alt+F` (toggle)

### Música

- **Desde Hub**: 🍅 Enfocar / 🎵 Música (menú único)
- **En Focus**: se activa automáticamente al entrar
- **ncmpcpp**: para control manual mientras trabajas
- **Playlists**: guardadas en `~/Musica/playlists/`

### "¿Qué estaba haciendo ayer?" (`SUPER+Alt+Y`)

Muestra un resumen rápido para retomar el hilo:
- **Actividad de ayer**: apps más usadas (via ActivityWatch, día local)
- **Journal de ayer**: tu journal de ayer (si no existe, el más reciente anterior a hoy — nunca el de hoy)
- **Tareas pendientes**: las de `TODO_ACTIVO` (qué queda por hacer)
- **Hoy**: fecha, hora y pomodoros completados

> Si un día no usaste el PC (finde, etc.), verás "Sin datos de ayer": es correcto, no un error.

### Brain dump y notas de voz (`SUPER+Alt+B` / `SUPER+Alt+T` / `SUPER+Alt+M`)

- **B**: rofi de una línea → se añade `- HH:MM idea` al `brain_dump/dump_HOY.md`.
  `daily-routine` las cuenta como "ideas sin triar" y `triage-local` las clasifica.
- **T**: `triage-local.sh --brain` — clasifica solo el brain_dump.
- **M**: graba 5s con `pw-record` (16kHz mono) y transcribe con `whisper --model tiny`;
  si no hay STT, guarda el wav en `00_inbox/voice/` y deja la nota con su ruta.

> `ALT+B` estaba ocupado por el WaybarLayout del sistema: `UserKeybinds.conf`
> lo libera con `unbind` antes de asignarlo al brain dump.

### Flow State Detector (`SUPER+Alt+D`)

Analiza tu actividad reciente y te notifica si:
- Llevas **25+ min** en la misma app
- Estás en **Firefox** → "¿Esto es productivo?"
- Estás en **terminal/editor** → "Mantén el ritmo 🍅"
- Estás en **comunicación** → "¿Puedes responder después?"

### Sistema de Recompensas

Automático después de cada pomodoro:
- **3 pomodoros** → ☕ Tómate un café
- **6 pomodoros** → 🏃 Mueve el cuerpo 5 min
- **9 pomodoros** → 🎵 Tu música favorita 5 min
- **12 pomodoros** → 📱 Revisa tu phone (5 min max)
- **15 pomodoros** → 🏆 ¡15 min libres!

### 4. Integración Waybar (Pomodoro)

Para añadir el icono de Pomodoro en tu barra de Waybar, edita tu archivo de configuración de Waybar (normalmente `~/.config/waybar/config` o `~/.config/waybar/config.jsonc`) y añade un módulo `custom/pomodoro`.

Asegúrate de que `pomodoro-daemon.sh` esté corriendo en segundo plano (puedes añadirlo a tu `autostart` de Hyprland).

```jsonc
"custom/pomodoro": {
    "format": "{}",
    "return-type": "json",
    "exec": "~/.local/bin/tdo-hub/scripts/pomodoro-waybar.sh",
    "interval": 1
},
```

---

## Tests

```bash
bash tests/run_tests.sh
```

Suite headless en sandbox `/tmp`: copia el repo, usa `.env`/vault/sesiones tmux de mentira y rofi falso. Cubre config (precedencia `.env`), yesterday (journal de ayer, nunca hoy), tareas Done, undo, journal y AW-resolve.

Con tripwire: si un test toca el repo real o `~/notes`, la suite falla.

---

## Aliases útiles

Añade estas líneas a tu `~/.zshrc` (o `~/.bashrc`) para atajos rápidos:

```bash
# TDO Hub aliases
alias tdo-hub="cd ~/.local/bin/tdo-hub"
alias tdo-reload="source ~/.zshrc"
alias tdo-journal="bash ~/.local/bin/tdo-hub/scripts/journal.sh"
alias tdo-capture="bash ~/.local/bin/tdo-hub/scripts/quick-capture-rofi.sh"
alias tdo-focus="bash ~/.local/bin/tdo-hub/scripts/focus_mode.sh"
alias tdo-undone="bash ~/.local/bin/tdo-hub/scripts/undo.sh"
alias tdo-aw="bash ~/.local/bin/tdo-hub/scripts/aw-stats.sh"
alias tdo-yesterday="bash ~/.local/bin/tdo-hub/scripts/yesterday.sh"
alias tdo-flow="bash ~/.local/bin/tdo-hub/scripts/flow-detect.sh"
```

Con estos aliases puedes ejecutar acciones principales sin escribir la ruta completa, ej: `tdo-focus` en lugar de `bash ~/.local/bin/tdo-hub/scripts/focus_mode.sh`.

---

## Cron jobs

Para programar tareas periódicas, añade las siguientes líneas a tu `crontab` (`crontab -e`):

| Horario | Script | Descripción |
|---------|--------|-------------|
| `0 9 * * *` | `daily-routine.sh` | Resumen del día a las 9:00 |
| `21 * * * *` | `notify-send "Journal reminder"` | Recordatorio de journal a las 21:00 |
| `0 * * * *` | `time.sh` | Resumen de timewarrior cada hora |
| `0 6 * * 1` | `weekly-review.sh` | Revisión semanal los lunes a las 6:00 |

Los scripts `daily-routine.sh`, `time.sh` y otros están en `~/scripts/` y deben ser ejecutables. Asegúrate de que la variable `SESSION` en tu `.env` coincida con el nombre de sesión tmux que usarán los scripts.

---

## Licencia

MIT