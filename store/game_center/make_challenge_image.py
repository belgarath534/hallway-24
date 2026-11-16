"""Draws the 3840x2160 Game Center challenge picture: the menu's hallway, darkened, with the challenge's name."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFont

HERE = Path(__file__).parent
ROOT = HERE.parent.parent
W, H = 3840, 2160
hall = Image.open(ROOT / "App/Assets.xcassets/MenuHallway.imageset/menu_hallway.jpg").convert("RGB")
hall = hall.resize((W, W))
img = hall.crop((0, (W - H) // 2, W, (W - H) // 2 + H))
img = ImageEnhance.Brightness(img).enhance(0.55)
d = ImageDraw.Draw(img)
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf", 260)
small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf", 130)
for text, f, y in (("Hallway 24", font, 1500), ("How far can you get?", small, 1830)):
    w = d.textlength(text, font=f)
    d.text(((W - w) / 2 + 8, y + 8), text, font=f, fill=(0, 0, 0))
    d.text(((W - w) / 2, y), text, font=f, fill=(245, 215, 160))
img.save(HERE / "challenge_furthest_hour.png")
print("Drew the challenge picture")
