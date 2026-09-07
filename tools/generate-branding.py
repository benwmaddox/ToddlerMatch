"""Build platform sizes from the committed, opaque icon master. Requires Pillow."""
from pathlib import Path
from PIL import Image


def generate(branding):
    branding = Path(branding)
    source = Image.open(branding / 'source.png').convert('RGBA')
    if source.width != source.height or source.getchannel('A').getextrema() != (255, 255):
        raise ValueError('Icon source must be square and fully opaque')
    master = source.convert('RGB').resize((1024, 1024), Image.Resampling.LANCZOS)
    master.save(branding / 'app-icon.png', optimize=True)
    res = branding / 'android/res'
    for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        folder = res / f'mipmap-{density}'
        folder.mkdir(parents=True, exist_ok=True)
        master.resize((size, size), Image.Resampling.LANCZOS).save(folder / 'ic_launcher.png', optimize=True)
    # Adaptive layers are 108dp; the normal mask covers the middle 72dp.
    # Edge-extend into the motion overscan to preserve the legacy composition.
    art = master.resize((288, 288), Image.Resampling.LANCZOS)
    adaptive = Image.new('RGB', (432, 432))
    adaptive.paste(art, (72, 72))
    for box, size, dest in [((0, 0, 288, 1), (288, 72), (72, 0)), ((0, 287, 288, 288), (288, 72), (72, 360)), ((0, 0, 1, 288), (72, 288), (0, 72)), ((287, 0, 288, 288), (72, 288), (360, 72))]:
        adaptive.paste(art.crop(box).resize(size), dest)
    for sx, sy, dx, dy in [(0, 0, 0, 0), (287, 0, 360, 0), (0, 287, 0, 360), (287, 287, 360, 360)]:
        adaptive.paste(art.getpixel((sx, sy)), (dx, dy, dx + 72, dy + 72))
    drawable = res / 'drawable-xxxhdpi'
    drawable.mkdir(parents=True, exist_ok=True)
    adaptive.save(drawable / 'stasis_icon_foreground.png', optimize=True)
    folder = res / 'mipmap-anydpi-v26'
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'ic_launcher.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@android:color/black" />
    <foreground android:drawable="@drawable/stasis_icon_foreground" />
</adaptive-icon>
''', encoding='utf-8')
    web = branding / 'web'
    web.mkdir(parents=True, exist_ok=True)
    for name, size in [('icon-192.png', 192), ('icon-512.png', 512), ('apple-touch-icon.png', 180)]:
        master.resize((size, size), Image.Resampling.LANCZOS).save(web / name, optimize=True)
    master.save(web / 'favicon.ico', sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])


if __name__ == '__main__':
    generate(Path(__file__).resolve().parents[1] / 'branding')
