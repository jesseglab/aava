"""Export native macOS icon sizes from the generated Aava source artwork."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
brand = root / 'Apps/macOS/Resources/Brand'
iconset = root / 'build/branding/AppIcon.iconset'
iconset.mkdir(parents=True, exist_ok=True)
for size in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        name = f'icon_{size}x{size}' + ('@2x' if scale == 2 else '') + '.png'
        pixels = str(size * scale)
        subprocess.run(['sips', '-z', pixels, pixels, str(brand / 'AppIcon.png'), '--out', str(iconset / name)], check=True, stdout=subprocess.DEVNULL)
subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(brand / 'AppIcon.icns')], check=True)
print(brand / 'AppIcon.icns')
