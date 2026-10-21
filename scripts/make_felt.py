"""Seamless felt texture tile (assets/felt.png): warm wool ground with short,
randomly oriented fibres and soft mottling. Run: python3 scripts/make_felt.py"""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 256
rng = np.random.default_rng(7)
base = np.array([239, 230, 214], dtype=float)  # felt.ground #EFE6D6

# soft mottling: blurred noise, tiled seamlessly by wrapping
noise = rng.normal(0, 1, (S, S))
img = Image.fromarray(((noise - noise.min()) / (noise.max() - noise.min()) * 255).astype('uint8'))
big = Image.new('L', (S * 3, S * 3))
for x in range(3):
    for y in range(3):
        big.paste(img, (x * S, y * S))
mottle = np.array(big.filter(ImageFilter.GaussianBlur(14)).crop((S, S, 2 * S, 2 * S)), dtype=float) / 255 - 0.5

rgb = np.clip(base[None, None, :] + mottle[..., None] * 18, 0, 255)
tile = Image.fromarray(rgb.astype('uint8'), 'RGB')

# fibres, drawn on a 3x3 canvas so they wrap
fib = Image.new('RGBA', (S * 3, S * 3), (0, 0, 0, 0))
d = ImageDraw.Draw(fib)
for _ in range(2600):
    x, y = rng.uniform(S, 2 * S, 2)
    a = rng.uniform(0, np.pi)
    l = rng.uniform(3, 11)
    dx, dy = np.cos(a) * l, np.sin(a) * l
    light = rng.random() < 0.5
    col = (255, 252, 244, int(rng.uniform(40, 90))) if light else (170, 150, 120, int(rng.uniform(25, 60)))
    for ox in (-S, 0, S):
        for oy in (-S, 0, S):
            d.line([(x + ox, y + oy), (x + ox + dx, y + oy + dy)], fill=col, width=1)
fib = fib.filter(ImageFilter.GaussianBlur(0.4)).crop((S, S, 2 * S, 2 * S))
tile = Image.alpha_composite(tile.convert('RGBA'), fib).convert('RGB')
tile.save('assets/felt.png', optimize=True)
print('assets/felt.png', tile.size)
