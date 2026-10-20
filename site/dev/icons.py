# Composes the site's icons from a render of Peek (dev/fav.html, via assets.mjs):
# favicon.ico (16/32/48), icon-192/512 and apple-touch-icon.
# usage: python3 site/dev/icons.py <peek render.png>
import struct, sys, io
from pathlib import Path
from PIL import Image, ImageFilter

SITE = Path(__file__).resolve().parent.parent
src = Image.open(sys.argv[1]).convert('RGBA')
peek = src.crop(src.split()[-1].getbbox())

def square(size, fill=0.96, bg=None):
    """Peek centred in a square, `fill` of its width; on transparent unless bg is given."""
    S = 1024
    im = Image.new('RGBA', (S, S), bg or (0, 0, 0, 0))
    w = int(S * fill); p = peek.resize((w, round(peek.height * w / peek.width)), Image.LANCZOS)
    im.alpha_composite(p, ((S - p.width) // 2, (S - p.height) // 2))
    out = im.resize((size, size), Image.LANCZOS)
    # tiny sizes: a light sharpen keeps the eyes crisp
    return out.filter(ImageFilter.UnsharpMask(radius=0.6, percent=70, threshold=0)) if size <= 48 else out

def ico(path, images):
    """An .ico of PNG entries (sharper than letting the encoder downsample one image)."""
    blobs = []
    for im in images:
        b = io.BytesIO(); im.save(b, 'PNG', optimize=True); blobs.append((im.size[0], b.getvalue()))
    head = struct.pack('<HHH', 0, 1, len(blobs)); off = 6 + 16 * len(blobs); dirs = b''
    for size, data in blobs:
        dirs += struct.pack('<BBBBHHII', size % 256, size % 256, 0, 0, 1, 32, len(data), off); off += len(data)
    Path(path).write_bytes(head + dirs + b''.join(d for _, d in blobs))

ico(SITE / 'favicon.ico', [square(s) for s in (16, 32, 48)])
square(192).save(SITE / 'icon-192.png', optimize=True)
square(512).save(SITE / 'icon-512.png', optimize=True)
# iOS fills transparency with black, so the home-screen icon gets a white tile with room around Peek
square(180, fill=0.78, bg=(255, 255, 255, 255)).convert('RGB').save(SITE / 'apple-touch-icon.png', optimize=True)
print('icons written')
