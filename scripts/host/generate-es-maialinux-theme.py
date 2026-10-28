#!/usr/bin/env python3
"""
generate-es-maialinux-theme.py
Generates EmulationStation theme assets for MaiaLinux system:
- system.png (500x130) for the carousel
- background_icon.png (960x540) for the system background silhouette
- theme.xml
"""

import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUTPUT_DIR = "/home/roberto/projects/maialinux/config/emulationstation/maialinux"
os.makedirs(OUTPUT_DIR, exist_ok=True)

# 1. Generate system.png (500 x 130)
# Carousel banner with MaiaLinux logo and clean, bold typography
width, height = 500, 130
banner = Image.new("RGBA", (width, height), (0, 0, 0, 0))
draw = ImageDraw.Draw(banner)

# Try loading an icon from existing images
logo_path = "/home/roberto/projects/maialinux/images/logo-kernel-rg353-640x480.png"
icon = None
if os.path.exists(logo_path):
    src = Image.open(logo_path).convert("RGBA")
    # In logo-kernel-rg353-640x480.png, center area has the star/logo
    # Let's crop central area or resize appropriately
    w_src, h_src = src.size
    # Center crop square
    crop_size = min(w_src, h_src)
    left = (w_src - crop_size) // 2
    top = (h_src - crop_size) // 2
    center_sq = src.crop((left + 50, top + 50, w_src - left - 50, h_src - top - 50))
    icon = center_sq.resize((100, 100), Image.Resampling.LANCZOS)

# Fonts
font_title = None
font_sub = None
for f_path in [
    "/usr/share/fonts/truetype/ubuntu/Ubuntu-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
]:
    if os.path.exists(f_path):
        font_title = ImageFont.truetype(f_path, 42)
        font_sub = ImageFont.truetype(f_path, 16)
        break

if not font_title:
    font_title = ImageFont.load_default()
    font_sub = font_title

# Draw icon on left
icon_x = 25
icon_y = (height - 100) // 2
if icon:
    # Give icon a subtle circular mask
    mask = Image.new("L", (100, 100), 0)
    draw_mask = ImageDraw.Draw(mask)
    draw_mask.rounded_rectangle((0, 0, 99, 99), radius=18, fill=255)
    banner.paste(icon, (icon_x, icon_y), mask)

# Draw text
text_x = 140
text_y = 30

# Shadow
draw.text((text_x + 2, text_y + 2), "MaiaLinux", font=font_title, fill=(15, 23, 42, 220))
# Text fill (clean gradient-like or light cyan / white)
draw.text((text_x, text_y), "MaiaLinux", font=font_title, fill=(255, 255, 255, 255))

# Subtitle badge / text
sub_x = text_x + 2
sub_y = text_y + 48
draw.text((sub_x + 1, sub_y + 1), "LXQt Desktop & Dev", font=font_sub, fill=(15, 23, 42, 180))
draw.text((sub_x, sub_y), "LXQt Desktop & Dev", font=font_sub, fill=(167, 139, 250, 255))

banner_path = os.path.join(OUTPUT_DIR, "system.png")
banner.save(banner_path, "PNG")
print(f"Generated {banner_path}")

# 2. Generate background_icon.png (960 x 540)
bg_w, bg_h = 960, 540
bg_icon = Image.new("RGBA", (bg_w, bg_h), (0, 0, 0, 0))
if os.path.exists(logo_path):
    src = Image.open(logo_path).convert("RGBA")
    # Resize to fit elegantly on the right side
    icon_big = src.resize((480, 360), Image.Resampling.LANCZOS)
    # Apply alpha transparency
    alpha = icon_big.split()[3] if len(icon_big.split()) > 3 else Image.new("L", icon_big.size, 180)
    icon_big.putalpha(140)
    bg_icon.paste(icon_big, (bg_w - 500, (bg_h - 360) // 2), icon_big)

bg_icon_path = os.path.join(OUTPUT_DIR, "background_icon.png")
bg_icon.save(bg_icon_path, "PNG")
print(f"Generated {bg_icon_path}")

# 3. Generate theme.xml
theme_xml_content = """<theme>
	<formatVersion>7</formatVersion>
	<include>./../theme.xml</include>

	<view name="system">
		<image name="logo">
			<path>./system.png</path>
		</image>
		<image name="background_icon" extra="true">
			<zIndex>3</zIndex>
			<path>./background_icon.png</path>
		</image>
	</view>

	<view name="detailed, video">
		<image name="system" extra="true">
			<origin>0.5 0.5</origin>
			<pos>0.75 0.138</pos>
			<maxSize>0.4 0.14</maxSize>
			<path>./system.png</path>
			<zIndex>3</zIndex>
		</image>
	</view>

	<view name="basic">
		<image name="system" extra="true">
			<origin>0.5 0</origin>
			<pos>0.5 0.02</pos>
			<maxSize>1 .12</maxSize>
			<path>./system.png</path>
			<zIndex>3</zIndex>
		</image>
	</view>
</theme>
"""

theme_xml_path = os.path.join(OUTPUT_DIR, "theme.xml")
with open(theme_xml_path, "w", encoding="utf-8") as f:
    f.write(theme_xml_content)
print(f"Generated {theme_xml_path}")

