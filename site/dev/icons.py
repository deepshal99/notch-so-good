# Composes the site's icons from a render of Peek in Gummy (dev/fav.html, via assets.mjs): his cherry head on a
# notch-black tile, the top of his head cropped by the tile's edge as if he's hanging into it.
# Writes favicon.ico (16/32/48), icon-192/512 and apple-touch-icon.
# usage: python3 site/dev/icons.py <gummy peek render.png>
import struct, sys, io
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

SITE = Path(__file__).resolve().parent.parent
src = Image.open(sys.argv[1]).convert('RGBA')
peek = src.crop(src.split()[-1].getbbox())
S, BLACK = 1024, (14, 14, 16, 255)

def tile(rounded=True):
    """The master: Peek at 92% of the tile's width, his top cut 12% past the tile's top edge."""
    im = Image.new('RGBA', (S, S), BLACK)
    w = int(S * 0.92); p = peek.resize((w, round(peek.height * w / peek.width)), Image.LANCZOS)
    im.alpha_composite(p, ((S - w) // 2, int(-S * 0.12)))
    if rounded:
        m = Image.new('L', (S, S), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, S - 1, S - 1), radius=int(S * 0.235), fill=255)
        im.putalpha(m)
    return im

MASTER, SQUARE = tile(), tile(rounded=False)

def size(im, px):
    out = im.resize((px, px), Image.LANCZOS)
    # tiny sizes: a light sharpen keeps the eyes crisp
    return out.filter(ImageFilter.UnsharpMask(radius=0.6, percent=70, threshold=0)) if px <= 48 else out

def ico(path, images):
    """An .ico of PNG entries (sharper than letting the encoder downsample one image)."""
    blobs = []
    for im in images:
        b = io.BytesIO(); im.save(b, 'PNG', optimize=True); blobs.append((im.size[0], b.getvalue()))
    head = struct.pack('<HHH', 0, 1, len(blobs)); off = 6 + 16 * len(blobs); dirs = b''
    for px, data in blobs:
        dirs += struct.pack('<BBBBHHII', px % 256, px % 256, 0, 0, 1, 32, len(data), off); off += len(data)
    Path(path).write_bytes(head + dirs + b''.join(d for _, d in blobs))

ico(SITE / 'favicon.ico', [size(MASTER, px) for px in (16, 32, 48)])
size(MASTER, 192).save(SITE / 'icon-192.png', optimize=True)
size(MASTER, 512).save(SITE / 'icon-512.png', optimize=True)
# iOS rounds the corners itself, so the home-screen icon is the full square
size(SQUARE, 180).convert('RGB').save(SITE / 'apple-touch-icon.png', optimize=True)
print('icons written')
