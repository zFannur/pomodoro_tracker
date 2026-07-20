"""Генерация иконок приложения из assets/icon/logo.png.

Windows: многоразмерный app_icon.ico (16..256). Многоразмерный ICO нужен,
чтобы Windows брал готовый 24px для панели задач, а не грубо ужимал 256px
(иначе иконка выглядит мыльной и «ужатой»).

Android: ic_launcher.png по плотностям экрана в mipmap-*.

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

# Android: свой PNG на каждую плотность — система сама выберет нужный.
android_res = root / "android/app/src/main/res"
for density, px in [
    ("mdpi", 48),
    ("hdpi", 72),
    ("xhdpi", 96),
    ("xxhdpi", 144),
    ("xxxhdpi", 192),
]:
    target = android_res / f"mipmap-{density}" / "ic_launcher.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    src.resize((px, px), Image.LANCZOS).save(target, format="PNG")
    print(f"OK: {target} ({px}px)")
