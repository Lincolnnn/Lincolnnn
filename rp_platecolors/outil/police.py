"""
RP PlateColors - génère les textures de assets/ (Python 3 + Pillow : pip install pillow)
    python outil/police.py [police.ttf]
Atlas : 8 colonnes x 5 lignes, cases de 64 x 96 px, ordre CHARS (doit rester identique à client/plates.lua).
Caractères blancs : la couleur est appliquée en jeu. Le contour est un 2e atlas aligné sur le 1er.
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-."
COLS, ROWS, CW, CH = 8, 5, 64, 96
PAD, STROKE = 9, 6
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
FONT = sys.argv[1] if len(sys.argv) > 1 else "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


WIDE = 160   # case de dessin, plus large que la case finale : compressée ensuite (style plaque condensé)


def glyph(ch, stroke):
    """Caractère centré dans une case large, même taille pour tous (hauteur des majuscules = case - marges)."""
    big = ImageFont.truetype(FONT, 200)
    x0, y0, x1, y1 = big.getbbox("H")
    scale = (CH - 2 * PAD) / (y1 - y0)
    font = ImageFont.truetype(FONT, max(8, round(200 * scale)))
    cell = Image.new("RGBA", (WIDE, CH), (255, 255, 255, 0))
    d = ImageDraw.Draw(cell)
    hx0, hy0, hx1, hy1 = font.getbbox("H")
    bx0, _, bx1, _ = font.getbbox(ch)
    x = (WIDE - (bx1 - bx0)) / 2 - bx0
    y = (CH - (hy1 - hy0)) / 2 - hy0
    d.text((x, y), ch, font=font, fill=(255, 255, 255, 255),
           stroke_width=stroke, stroke_fill=(255, 255, 255, 255))
    return cell


def squeeze():
    """Même facteur pour tous les caractères : le plus large (contour compris) tient dans la case finale."""
    widest = max(glyph(ch, STROKE).getbbox()[2] - glyph(ch, STROKE).getbbox()[0] for ch in CHARS)
    return min(1.0, (CW - 2) / widest)


def atlas(stroke, k):
    img = Image.new("RGBA", (COLS * CW, 512), (255, 255, 255, 0))
    w = round(WIDE * k)
    for i, ch in enumerate(CHARS):
        cell = glyph(ch, stroke).resize((w, CH), Image.LANCZOS).crop(((w - CW) // 2, 0, (w - CW) // 2 + CW, CH))
        img.paste(cell, ((i % COLS) * CW, (i // COLS) * CH))
    return img


os.makedirs(OUT, exist_ok=True)
K = squeeze()
atlas(0, K).save(os.path.join(OUT, "plate_font.png"))
atlas(STROKE, K).save(os.path.join(OUT, "plate_font_outline.png"))
# Police du jeu remplacée par du vide (masque le texte d'origine) ; normal map plate (pas de relief)
Image.new("RGBA", (64, 64), (0, 0, 0, 0)).save(os.path.join(OUT, "blank_font.png"))
Image.new("RGBA", (64, 64), (128, 128, 255, 255)).save(os.path.join(OUT, "flat_n.png"))
print("assets/ générés avec", FONT, "- compression horizontale", round(K, 3))
