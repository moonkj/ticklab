#!/usr/bin/env python3
"""
TickLab App Store 광고 스크린샷 생성기.

준비:
1. iPhone 에서 받은 6장 스크린샷을 source/ 폴더에 1.png ~ 6.png 순으로 저장
   1.png = 컬렉션 (THE BENCH)
   2.png = 측정 진행 (박동 듣는 중)
   3.png = 워치 디테일 (IW371604 트렌드)
   4.png = 오늘 (Today)
   5.png = 브랜드 리그
   6.png = 업적 (Badges)

실행:
    cd ~/TickLab/marketing
    python3 generate_screenshots.py

결과:
    output/01_collection.png ... output/06_badges.png
    1320×2868 (App Store Connect "iPhone 6.9" Display" 슬롯에 그대로 업로드)
"""

import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

# ========== Canvas spec ==========
CANVAS_W = 1320
CANVAS_H = 2868
BG_COLOR = (250, 250, 247)  # #FAFAF7 warm linen

INK0 = (26, 27, 46)        # #1A1B2E primaryDeep
INK2 = (64, 64, 64)        # #404040
ACCENT_DARK = (160, 136, 66)  # #A08842

# ========== Fonts (macOS system) ==========
GOTHIC = "/System/Library/Fonts/AppleSDGothicNeo.ttc"  # Korean
SERIF = "/System/Library/Fonts/Supplemental/Times New Roman.ttf"
SF_BOLD = "/System/Library/Fonts/SFNS.ttf"  # SF

# ========== Layout ==========
SAFE_TOP = 130
EYEBROW_Y = 180
HEADLINE_Y = 280
SUB_Y = 540
SHOT_Y = 720          # screenshot top
SHOT_RADIUS = 60      # corner round
SHOT_SHADOW_BLUR = 40

# ========== Copy (slot, eyebrow, headline lines, sub) ==========
SLOTS = [
    ("01_collection",
     "TICKLAB",
     ["내 시계 컬렉션,", "한 권의 책처럼"],
     "11개 시계, 한눈에 펼쳐보기"),
    ("02_measure",
     "MEASURE",
     ["iPhone 으로", "일오차 측정"],
     "마이크 하나로 ±0.5 s/d 정밀도"),
    ("03_detail",
     "DETAIL",
     ["시계마다 자기만의", "기록과 트렌드"],
     "측정·서비스·일기를 한 곳에"),
    ("04_today",
     "TODAY",
     ["오늘 손목 위에", "무엇을 두를까"],
     "매일 다른 다이얼·운세·자기장 체크"),
    ("05_league",
     "LEAGUE",
     ["전 세계 컬렉터와", "같이 차고"],
     "주간·월간·연간 브랜드 랭킹"),
    ("06_badges",
     "JOURNEY",
     ["32가지 업적,", "컬렉터의 여정"],
     "COSC 달성 · 50회 돌파 · 야행성 컬렉터"),
]


def load_font(path: str, size: int) -> ImageFont.FreeTypeFont:
    """Pillow 가 .ttc 의 sub-font index 선택 가능. 굵기는 0-9 index."""
    try:
        return ImageFont.truetype(path, size, index=0)
    except Exception:
        return ImageFont.load_default()


def text_width(draw, text, font):
    bbox = draw.textbbox((0, 0), text, font=font)
    return bbox[2] - bbox[0]


def draw_rounded_image(canvas: Image.Image, shot: Image.Image, x: int, y: int, radius: int):
    """스크린샷에 round corner + drop shadow 적용 후 canvas 에 합성."""
    # Mask
    mask = Image.new("L", shot.size, 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([0, 0, shot.size[0], shot.size[1]],
                                radius=radius, fill=255)

    # Shadow layer
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        [x, y + 30, x + shot.size[0], y + 30 + shot.size[1]],
        radius=radius, fill=(0, 0, 0, 60))
    shadow = shadow.filter(ImageFilter.GaussianBlur(SHOT_SHADOW_BLUR))
    canvas.alpha_composite(shadow)

    # Screenshot rounded
    shot_rgba = shot.convert("RGBA")
    rounded = Image.new("RGBA", shot.size, (0, 0, 0, 0))
    rounded.paste(shot_rgba, (0, 0), mask=mask)
    canvas.alpha_composite(rounded, (x, y))


def render_slot(slot_id: str, eyebrow: str, headlines, sub: str,
                shot_path: Path, out_path: Path):
    canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), BG_COLOR + (255,))
    draw = ImageDraw.Draw(canvas)

    # Eyebrow (mono caps, gold)
    eyebrow_font = load_font(GOTHIC, 28)
    eyebrow_text = eyebrow + "  ·  EST. 2026"
    w = text_width(draw, eyebrow_text, eyebrow_font)
    # tracking 흉내내기: char 간 space 추가 안 해도 size 28 이면 OK
    draw.text(((CANVAS_W - w) / 2, EYEBROW_Y), eyebrow_text,
              fill=ACCENT_DARK, font=eyebrow_font)

    # Headline (serif bold, big)
    headline_font = load_font(GOTHIC, 92)
    y = HEADLINE_Y
    for line in headlines:
        w = text_width(draw, line, headline_font)
        draw.text(((CANVAS_W - w) / 2, y), line, fill=INK0, font=headline_font)
        y += 115

    # Sub
    sub_font = load_font(GOTHIC, 36)
    w = text_width(draw, sub, sub_font)
    draw.text(((CANVAS_W - w) / 2, SUB_Y), sub, fill=INK2, font=sub_font)

    # Screenshot
    if shot_path.exists():
        shot = Image.open(shot_path)
        # Resize to fit width ~1100 keeping ratio
        target_w = 1100
        ratio = target_w / shot.size[0]
        target_h = int(shot.size[1] * ratio)
        shot = shot.resize((target_w, target_h), Image.LANCZOS)
        x = (CANVAS_W - target_w) // 2
        draw_rounded_image(canvas, shot, x, SHOT_Y, SHOT_RADIUS)
    else:
        # Placeholder rectangle if screenshot missing
        ph_w, ph_h = 1100, 2000
        x = (CANVAS_W - ph_w) // 2
        draw.rounded_rectangle([x, SHOT_Y, x + ph_w, SHOT_Y + ph_h],
                               radius=SHOT_RADIUS,
                               outline=(200, 200, 200, 255), width=4)
        msg = f"{slot_id}.png 를\nsource/ 에 저장하세요"
        msg_font = load_font(GOTHIC, 48)
        bbox = draw.multiline_textbbox((0, 0), msg, font=msg_font)
        draw.multiline_text(
            ((CANVAS_W - (bbox[2] - bbox[0])) // 2,
             SHOT_Y + (ph_h - (bbox[3] - bbox[1])) // 2),
            msg, fill=(180, 180, 180, 255), font=msg_font, align="center")

    canvas.convert("RGB").save(out_path, "PNG", optimize=True)
    print(f"  ✓ {out_path.name}")


def main():
    base = Path(__file__).parent
    source = base / "screenshots" / "source"
    output = base / "screenshots" / "output"
    output.mkdir(parents=True, exist_ok=True)

    print(f"TickLab App Store 광고 스크린샷 생성")
    print(f"  source: {source}")
    print(f"  output: {output}")
    print()

    for idx, (slot_id, eyebrow, headlines, sub) in enumerate(SLOTS, start=1):
        shot = source / f"{idx}.png"
        out = output / f"{slot_id}.png"
        render_slot(slot_id, eyebrow, headlines, sub, shot, out)

    print()
    print("완료. App Store Connect → Screenshots → iPhone 6.9 Display 에 업로드.")


if __name__ == "__main__":
    main()
