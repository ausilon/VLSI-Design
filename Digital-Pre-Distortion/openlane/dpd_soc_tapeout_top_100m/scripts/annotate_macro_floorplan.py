from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path("/home/Ausilon/openlane_work/designs/dpd_soc_tapeout_top_100m")
DOCS = Path("/home/Ausilon/Desktop/dpd_v1/dpd_soc_min/docs")

BASE = ROOT / "dpd_soc_tapeout_top_full05_article_contrast.png"
OUT = ROOT / "dpd_soc_tapeout_top_full05_macro_labeled_v2.png"
OUT_DOCS = DOCS / OUT.name


def font(size):
    for path in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ):
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def centered_label(draw, xy, text, size):
    x0, y0, x1, y1 = xy
    fnt = font(size)
    lines = text.split("\n")
    bboxes = [draw.textbbox((0, 0), line, font=fnt) for line in lines]
    widths = [b[2] - b[0] for b in bboxes]
    heights = [b[3] - b[1] for b in bboxes]
    line_gap = max(5, size // 5)
    text_w = max(widths)
    text_h = sum(heights) + line_gap * (len(lines) - 1)
    cx = (x0 + x1) // 2
    cy = (y0 + y1) // 2
    pad_x = max(14, size // 2)
    pad_y = max(8, size // 3)
    box = (
        cx - text_w // 2 - pad_x,
        cy - text_h // 2 - pad_y,
        cx + text_w // 2 + pad_x,
        cy + text_h // 2 + pad_y,
    )
    draw.rounded_rectangle(box, radius=8, fill=(8, 10, 16, 225), outline=(255, 122, 232, 230), width=2)
    y = cy - text_h // 2
    for line, h in zip(lines, heights):
        tw = draw.textbbox((0, 0), line, font=fnt)[2]
        draw.text((cx - tw // 2, y), line, font=fnt, fill=(250, 250, 255, 255))
        y += h + line_gap


def macro(draw, xy, label, label_size):
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.rectangle(xy, fill=(185, 0, 132, 105), outline=(255, 0, 220, 255), width=5)
    img.alpha_composite(overlay)
    centered_label(draw, xy, label, label_size)


img = Image.open(BASE).convert("RGBA")
draw = ImageDraw.Draw(img)

title = "DPD SoC macro floorplan - SKY130/OpenLane"
draw.text((80, 30), title, font=font(36), fill=(235, 238, 245, 255))

macro(draw, (285, 290, 1055, 900), "Capture RAM", 50)
macro(draw, (315, 965, 790, 1206), "Coef Bank", 44)
macro(draw, (315, 1420, 590, 1685), "AXI-Lite", 42)
macro(draw, (700, 1510, 840, 1620), "Metrics", 28)
macro(draw, (300, 2142, 385, 2228), "Peripherals", 20)
macro(draw, (690, 2010, 900, 2199), "PicoRV32", 36)

macro(draw, (1306, 220, 1974, 900), "MACcore\ntraining", 44)
macro(draw, (1060, 1170, 2248, 2368), "GMPengine\ninference", 52)

img.save(OUT)
img.save(OUT_DOCS)
print(OUT)
print(OUT_DOCS)
