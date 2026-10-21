# Renders the JÜR mark (two horns curling into a heart) to PNG without SVG tools.
# usage: python3 render_mark.py out.png size hexcolor [stroke]
import sys
from PIL import Image, ImageDraw

HORNS = [
    [(50, 88), (30, 70), (14, 56), (14, 38), (14, 22), (28, 14), (40, 18), (50, 22), (50, 36), (40, 38), (34, 39), (30, 34), (33, 30)],
    [(50, 88), (70, 70), (86, 56), (86, 38), (86, 22), (72, 14), (60, 18), (50, 22), (50, 36), (60, 38), (66, 39), (70, 34), (67, 30)],
]

def cubic(p0, p1, p2, p3, n=60):
    for i in range(n + 1):
        t = i / n
        a = (1 - t) ** 3; b = 3 * (1 - t) ** 2 * t; c = 3 * (1 - t) * t * t; d = t ** 3
        yield (a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1])

def render(out, size, color, stroke=7.0):
    ss = 4
    S = size * ss
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    rgb = tuple(int(color.lstrip('#')[i:i + 2], 16) for i in (0, 2, 4)) + (255,)
    r = stroke / 2 * S / 100
    for pts in HORNS:
        for k in range(0, len(pts) - 1, 3):
            for (x, y) in cubic(*pts[k:k + 4]):
                X, Y = x * S / 100, y * S / 100
                dr.ellipse([X - r, Y - r, X + r, Y + r], fill=rgb)
    img.resize((size, size), Image.LANCZOS).save(out)

if __name__ == '__main__':
    render(sys.argv[1], int(sys.argv[2]), sys.argv[3], float(sys.argv[4]) if len(sys.argv) > 4 else 7.0)
