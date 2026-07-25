from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

BASE = Path("/home/Ausilon/openlane_work/designs")
TOP = BASE / "dpd_soc_macro_top_100m"
RUN = TOP / "runs/macro_view_final_01"
OUT = TOP / "dpd_soc_macro_top_floorplan_view.png"

die_w, die_h = 6800.0, 7500.0

placements = {
    "u_metrics": ("Metric engine", "dpd_metrics_100m/runs/signoff_100m_01/results/signoff/metric_engine.lef"),
    "u_pico": ("PicoRV32", "dpd_pico_100m/runs/signoff_100m_01/results/signoff/picorv32_ol_wrapper.lef"),
    "u_axi": ("AXI-Lite", "dpd_axi_100m/runs/signoff_100m_01/results/signoff/axi_ctrl_wrapper.lef"),
    "u_peripherals": ("Peripherals", "dpd_peripherals_100m/runs/signoff_100m_01/results/signoff/peripherals_wrapper.lef"),
    "u_gmp": ("GMP core", "dpd_gmp_engine_100m/runs/signoff_100m_01/results/signoff/gmp_engine_ol_wrapper.lef"),
    "u_capture_ram": ("Capture RAM", "dpd_capture_ram_macro_100m/runs/macro_route_100m_01/results/signoff/capture_ram_macro.lef"),
    "u_coef_bank": ("Coef bank", "dpd_coef_bank_macro_100m/runs/macro_route_100m_01/results/signoff/coef_bank_macro.lef"),
    "u_mac": ("MAC engine", "dpd_mac_engine_100m/runs/signoff_100m_no_prefill_01/results/signoff/mac_engine.lef"),
}

def lef_size(path):
    for line in path.read_text(errors="ignore").splitlines():
        line = line.strip()
        if line.startswith("SIZE "):
            parts = line.replace(";", "").split()
            return float(parts[1]), float(parts[3])
    raise RuntimeError(f"SIZE not found in {path}")

def load_placements(path):
    out = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name, x, y, orient = line.split()
        out[name] = (float(x), float(y), orient)
    return out

pos = load_placements(TOP / "macro_placement.cfg")

scale = 0.33
margin = 120
img_w = int(die_w * scale) + 2 * margin
img_h = int(die_h * scale) + 2 * margin
img = Image.new("RGB", (img_w, img_h), "#f7f8fb")
draw = ImageDraw.Draw(img)

try:
    font_big = ImageFont.truetype("DejaVuSans-Bold.ttf", 34)
    font = ImageFont.truetype("DejaVuSans.ttf", 24)
    font_small = ImageFont.truetype("DejaVuSans.ttf", 18)
except Exception:
    font_big = font = font_small = None

def xy(x, y):
    return margin + x * scale, margin + (die_h - y) * scale

# Die and core outlines.
x0, y0 = xy(0, die_h)
x1, y1 = xy(die_w, 0)
draw.rectangle([x0, y0, x1, y1], outline="#1f2937", width=5, fill="#ffffff")
cx0, cy0 = xy(200, 8600)
cx1, cy1 = xy(7000, 200)
draw.rectangle([cx0, cy0, cx1, cy1], outline="#9ca3af", width=2)

palette = {
    "u_gmp": "#8ecae6",
    "u_mac": "#b7e4c7",
    "u_capture_ram": "#ffd166",
    "u_coef_bank": "#f4a261",
    "u_axi": "#cdb4db",
    "u_pico": "#ffafcc",
    "u_metrics": "#a8dadc",
    "u_peripherals": "#d9ed92",
}

for inst, (label, rel_lef) in placements.items():
    x, y, orient = pos[inst]
    w, h = lef_size(BASE / rel_lef)
    if orient in ("E", "W", "FE", "FW"):
        w, h = h, w
    rx0, ry0 = xy(x, y + h)
    rx1, ry1 = xy(x + w, y)
    draw.rectangle([rx0, ry0, rx1, ry1], fill=palette.get(inst, "#dddddd"), outline="#111827", width=3)
    tw = draw.textlength(label, font=font)
    draw.text(((rx0 + rx1 - tw) / 2, (ry0 + ry1) / 2 - 18), label, fill="#111827", font=font)
    size_txt = f"{w/1000:.2f} x {h/1000:.2f} mm"
    sw = draw.textlength(size_txt, font=font_small)
    draw.text(((rx0 + rx1 - sw) / 2, (ry0 + ry1) / 2 + 14), size_txt, fill="#374151", font=font_small)

title = "DPD SoC Macro Assembly - SKY130 Preliminary Floorplan"
draw.text((margin, 28), title, fill="#111827", font=font_big)
subtitle = f"Die: {die_w/1000:.2f} x {die_h/1000:.2f} mm = {(die_w*die_h)/1e6:.2f} mm2"
draw.text((margin, 72), subtitle, fill="#374151", font=font)
draw.text((margin, img_h - 58), "View generated from OpenLane macro placement and final hard-macro LEF sizes.", fill="#4b5563", font=font_small)

OUT.parent.mkdir(parents=True, exist_ok=True)
img.save(OUT)
print(OUT)
