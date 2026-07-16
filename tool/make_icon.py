"""Генерация Windows-иконки приложения.

Делает многоразмерный app_icon.ico (16..256) из assets/icon/logo.png.
Многоразмерный ICO нужен, чтобы Windows брал готовый 24px для панели задач,
а не грубо ужимал 256px (иначе иконка выглядит мыльной и «ужатой»).

logo.png должен быть квадратным PNG с прозрачным фоном и полями по краям.
Запуск:  python tool/make_icon.py
"""

from pathlib import Path

from PIL import Image

root = Path(__file__).resolve().parent.parent
src = Image.open(root / "assets/icon/logo.png").convert("RGBA")
sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
out = root / "windows/runner/resources/app_icon.ico"
src.save(out, format="ICO", sizes=sizes)
print(f"OK: {out} ({len(sizes)} размеров)")
