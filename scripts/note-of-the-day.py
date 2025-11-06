#!/usr/bin/env python3
"""Muestra notas al azar para redescubrir lo que escribiste"""

import os
import random
import subprocess
import sys
from datetime import datetime
from pathlib import Path

NOTES = os.environ.get("NOTES_DIR", os.path.expanduser("~/notes"))


def obtener_notas():
    notas = []
    for ruta in Path(NOTES).rglob("*.md"):
        if ".git" in ruta.parts:
            continue
        rel = str(ruta.relative_to(NOTES))
        nombre = ruta.stem
        if any(
            p in rel
            for p in ["journal/", "entries/", "todos/", "templates/", "General/todos"]
        ):
            continue
        if nombre.startswith("202") and len(nombre) >= 10:
            continue
        texto = ruta.read_text(errors="ignore")
        notas.append((rel, nombre, texto, ruta))
    return notas


def nota_al_azar(notas):
    if not notas:
        return None
    pesos = [1.0 / (i + 1) for i in range(len(notas))]
    return random.choices(notas, weights=pesos, k=1)[0]


def preview(texto, max_lineas=15):
    lineas = []
    for l in texto.splitlines():
        l = l.strip()
        if (
            l
            and not l.startswith("---")
            and not l.startswith("date:")
            and not l.startswith("tags:")
        ):
            lineas.append(l)
    return "\n".join(lineas[:max_lineas])


def main():
    notas = obtener_notas()
    if not notas:
        subprocess.run(["notify-send", "📝 No hay notas"])
        return

    while True:
        if len(sys.argv) > 1 and sys.argv[1] == "--today":
            hoy = datetime.now()
            dia_mes = f"-{hoy.month:02d}-{hoy.day:02d}"
            del_ano_pasado = [n for n in notas if dia_mes in n[0]]
            nota = (
                random.choice(del_ano_pasado) if del_ano_pasado else nota_al_azar(notas)
            )
            titulo = "📅 Tal día como hoy"
        else:
            nota = nota_al_azar(notas)
            titulo = "🎲 Nota aleatoria"

        rel, nombre, texto, ruta = nota
        preview_texto = preview(texto)
        titulo_nota = nombre.replace("-", " ").title()
        opciones = f"📖 Abrir\n🎲 Otra\n🚪 Salir"
        rofi_cmd = ["rofi", "-dmenu", "-p", "🎲", "-mesg", preview_texto]
        # Usar tema rofi si existe
        rofi_theme = os.path.expanduser("~/.config/rofi/config.rasi")
        if os.path.exists(rofi_theme):
            rofi_cmd.extend(["-theme", rofi_theme])
        try:
            sel = subprocess.run(
                rofi_cmd,
                input=opciones,
                capture_output=True,
                text=True,
                timeout=30,
            ).stdout.strip()
        except:
            break

        if not sel or sel == "🚪 Salir":
            break
        if sel == "🎲 Otra":
            continue
        if sel == "📖 Abrir":
            print(str(ruta))
            break


if __name__ == "__main__":
    main()
