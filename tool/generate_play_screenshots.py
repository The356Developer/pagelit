import os
import subprocess
from PIL import Image

CHROME_PATH = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
ROOT_DIR = os.path.abspath(r".")
RAW_DIR = os.path.abspath(r"Marketing\PlayConsole\raw")
CROPS_DIR = os.path.join(RAW_DIR, "crops")
OUTPUT_DIR = os.path.abspath(r"Marketing\PlayConsole")
FONTS_DIR = os.path.abspath(r"assets\fonts")

os.makedirs(CROPS_DIR, exist_ok=True)
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Clean old obsolete Play Store mockups that do not reflect the real app
OBSOLETE_FILES = [
    "01_all_in_one_suite.png",
    "02_mobile_and_pc.png",
    "03_pdf_markup_scrubber.png",
    "04_word_excel_slides.png",
    "05_comfort_and_languages.png",
    "06_ai_gemini_insights.png",
]


def prepare_crops():
    """Creates clean, status-bar-free real app captures and tight feature crops."""
    full_crop_box = (0, 96, 1080, 2345)  # Removes Android status bar + nav gesture bar

    clean_map = {
        "raw_pdf_normal.png": "clean_pdf_normal.png",
        "raw_pdf_markup.png": "clean_pdf_markup.png",
        "raw_pdf_quickbar.png": "clean_pdf_quickbar.png",
        "raw_pdf_sepia.png": "clean_pdf_sepia.png",
        "raw_pdf_night.png": "clean_pdf_night.png",
        "raw_word.png": "clean_word.png",
        "raw_excel.png": "clean_excel.png",
        "raw_pptx_slide.png": "clean_pptx_slide.png",
        "raw_pptx_slide1.png": "clean_pptx_slide1.png",
    }
    for src_name, dst_name in clean_map.items():
        src_path = os.path.join(RAW_DIR, src_name)
        dst_path = os.path.join(CROPS_DIR, dst_name)
        im = Image.open(src_path)
        im.crop(full_crop_box).save(dst_path)

    # Tight feature crops from real captures
    # 1. Annotation & PageScrubber dock (exact card bounds, zero text above)
    im_qb = Image.open(os.path.join(RAW_DIR, "raw_pdf_quickbar.png"))
    im_qb.crop((46, 1885, 1034, 2328)).save(
        os.path.join(CROPS_DIR, "crop_toolbar_scrubber.png")
    )

    # 2. Word document top card + table crop (for collage)
    im_word = Image.open(os.path.join(RAW_DIR, "raw_word.png"))
    im_word.crop((0, 96, 1080, 1750)).save(
        os.path.join(CROPS_DIR, "crop_word_card.png")
    )

    # 3. Excel AppBar + formula bar + grid top (for collage)
    im_excel = Image.open(os.path.join(RAW_DIR, "raw_excel.png"))
    im_excel.crop((0, 96, 1080, 1340)).save(
        os.path.join(CROPS_DIR, "crop_excel_top.png")
    )

    # 4. PPTX Slide 1 clean slide canvas crop (for collage)
    im_ppt1 = Image.open(os.path.join(RAW_DIR, "raw_pptx_slide1.png"))
    im_ppt1.crop((24, 920, 1056, 1525)).save(
        os.path.join(CROPS_DIR, "crop_pptx_slide1_card.png")
    )

    # 5. PPTX 2x2 Slide Overview Grid bottom sheet
    im_grid = Image.open(os.path.join(RAW_DIR, "raw_pptx_grid.png"))
    im_grid.crop((0, 775, 1080, 2240)).save(
        os.path.join(CROPS_DIR, "crop_pptx_grid.png")
    )

    # 6. Real More Menu popup from ReaderScreen
    im_menu = Image.open(os.path.join(RAW_DIR, "raw_pdf_menu.png"))
    im_menu.crop((292, 118, 1048, 2048)).save(
        os.path.join(CROPS_DIR, "crop_more_menu.png")
    )

    # 7. Real Gemini Sparkle spotlight crop (AppBar right side)
    im_norm = Image.open(os.path.join(RAW_DIR, "raw_pdf_normal.png"))
    im_norm.crop((500, 102, 1080, 226)).save(
        os.path.join(CROPS_DIR, "crop_pdf_appbar_actions.png")
    )


def file_uri(path):
    return "file:///" + path.replace("\\", "/")


def font_css():
    return f"""
    @font-face {{
      font-family: 'Poppins';
      src: url('{file_uri(os.path.join(FONTS_DIR, "Poppins-Regular.ttf"))}') format('truetype');
      font-weight: 400;
    }}
    @font-face {{
      font-family: 'Poppins';
      src: url('{file_uri(os.path.join(FONTS_DIR, "Poppins-Medium.ttf"))}') format('truetype');
      font-weight: 500;
    }}
    @font-face {{
      font-family: 'Poppins';
      src: url('{file_uri(os.path.join(FONTS_DIR, "Poppins-SemiBold.ttf"))}') format('truetype');
      font-weight: 600;
    }}
    @font-face {{
      font-family: 'Poppins';
      src: url('{file_uri(os.path.join(FONTS_DIR, "Poppins-Bold.ttf"))}') format('truetype');
      font-weight: 700;
    }}
    """


def clean_status_bar(dark=False):
    fg = "#EDEAF2" if dark else "#17161C"
    bg = "#121117" if dark else "#FBF8F4"
    return f"""
    <div class="clean-status" style="background: {bg}; color: {fg};">
      <span>9:41</span>
      <div style="display: flex; align-items: center; gap: 10px;">
        <svg width="18" height="14" viewBox="0 0 18 14" fill="none">
          <rect x="0" y="9" width="3" height="5" rx="1" fill="{fg}"/>
          <rect x="5" y="6" width="3" height="8" rx="1" fill="{fg}"/>
          <rect x="10" y="3" width="3" height="11" rx="1" fill="{fg}"/>
          <rect x="15" y="0" width="3" height="14" rx="1" fill="{fg}"/>
        </svg>
        <svg width="26" height="13" viewBox="0 0 26 13" fill="none">
          <rect x="1" y="1" width="21" height="11" rx="3" stroke="{fg}" stroke-width="1.6"/>
          <rect x="3" y="3" width="17" height="7" rx="1.5" fill="{fg}"/>
          <rect x="23" y="4" width="2.5" height="5" rx="1" fill="{fg}"/>
        </svg>
      </div>
    </div>
    """


COMMON_CSS = """
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    width: 1080px;
    height: 2400px;
    overflow: hidden;
    font-family: 'Poppins', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background: linear-gradient(172deg, #FBF8F4 0%, #F4ECE3 46%, #EADFD3 100%);
    position: relative;
    color: #17161C;
    -webkit-font-smoothing: antialiased;
  }
  .grid-pattern {
    position: absolute;
    inset: 0;
    background-image: radial-gradient(rgba(23, 22, 28, 0.045) 1.5px, transparent 1.5px);
    background-size: 36px 36px;
    pointer-events: none;
    z-index: 0;
  }
  .glow-red {
    position: absolute;
    width: 920px;
    height: 920px;
    border-radius: 50%;
    background: radial-gradient(circle, rgba(229, 69, 59, 0.16) 0%, rgba(229, 69, 59, 0) 70%);
    top: 480px;
    left: 80px;
    pointer-events: none;
    z-index: 1;
  }
  .glow-warm {
    position: absolute;
    width: 820px;
    height: 820px;
    border-radius: 50%;
    background: radial-gradient(circle, rgba(217, 119, 6, 0.11) 0%, rgba(217, 119, 6, 0) 70%);
    top: 1420px;
    right: -120px;
    pointer-events: none;
    z-index: 1;
  }

  /* Header */
  .header-container {
    position: relative;
    z-index: 10;
    padding: 86px 56px 0 56px;
    text-align: center;
  }
  .eyebrow-pill {
    display: inline-flex;
    align-items: center;
    gap: 10px;
    padding: 10px 24px;
    border-radius: 999px;
    background: rgba(229, 69, 59, 0.10);
    border: 1.5px solid rgba(229, 69, 59, 0.25);
    color: #C33A31;
    font-size: 19px;
    font-weight: 700;
    letter-spacing: 1.6px;
    text-transform: uppercase;
    margin-bottom: 22px;
  }
  .eyebrow-pill .dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: #E5453B;
  }
  h1.main-title {
    font-size: 66px;
    font-weight: 700;
    line-height: 1.14;
    letter-spacing: -1.2px;
    color: #17161C;
    margin-bottom: 18px;
  }
  p.subtitle {
    font-size: 28px;
    font-weight: 400;
    line-height: 1.45;
    color: #55515E;
    max-width: 940px;
    margin: 0 auto;
  }

  /* Phone Hardware Mockup matching 1080x2249 crop ratio (1:2.08) */
  .phone-frame {
    position: absolute;
    background: #141318;
    border-radius: 58px;
    padding: 14px;
    box-shadow:
      0 42px 95px -12px rgba(23, 22, 28, 0.36),
      0 18px 42px -10px rgba(229, 69, 59, 0.18),
      inset 0 0 0 2.5px rgba(255, 255, 255, 0.16);
    z-index: 5;
  }
  .phone-screen {
    width: 100%;
    height: 100%;
    border-radius: 44px;
    overflow: hidden;
    background: #FBF8F4;
    display: flex;
    flex-direction: column;
    position: relative;
  }
  .phone-camera {
    position: absolute;
    top: 12px;
    left: 50%;
    transform: translateX(-50%);
    width: 22px;
    height: 22px;
    border-radius: 50%;
    background: #0A0A0C;
    z-index: 30;
    box-shadow: inset 0 0 0 2px #26252E;
  }
  .clean-status {
    height: 44px;
    padding: 10px 28px 0 28px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-size: 15px;
    font-weight: 600;
    flex-shrink: 0;
    z-index: 20;
  }
  .screen-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    object-position: top center;
    display: block;
    flex: 1;
  }

  /* Floating Callout Cards & Badges */
  .float-card {
    position: absolute;
    background: #FFFFFF;
    border-radius: 24px;
    border: 2px solid #E9E2D8;
    box-shadow: 0 28px 65px rgba(23, 22, 28, 0.24), 0 8px 20px rgba(229, 69, 59, 0.10);
    overflow: hidden;
    z-index: 15;
  }
  .float-pill {
    position: absolute;
    background: rgba(255, 255, 255, 0.96);
    border: 2px solid #E9E2D8;
    border-radius: 999px;
    padding: 15px 28px;
    box-shadow: 0 20px 48px rgba(23, 22, 28, 0.16);
    display: flex;
    align-items: center;
    gap: 12px;
    font-size: 21px;
    font-weight: 600;
    color: #17161C;
    z-index: 20;
    white-space: nowrap;
  }
  .bottom-hook {
    position: absolute;
    bottom: 44px;
    left: 50%;
    transform: translateX(-50%);
    background: #17161C;
    color: #FFFFFF;
    border-radius: 999px;
    padding: 17px 34px;
    font-size: 21px;
    font-weight: 600;
    display: flex;
    align-items: center;
    gap: 12px;
    box-shadow: 0 20px 50px rgba(23, 22, 28, 0.28);
    z-index: 25;
    white-space: nowrap;
  }
  .badge-tag {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 5px 12px;
    border-radius: 8px;
    font-size: 13px;
    font-weight: 700;
    color: #FFFFFF;
    letter-spacing: 0.4px;
  }
"""


def base_page(title_html, body_html, dark_bg=False):
    bg_override = ""
    if dark_bg:
        bg_override = """
        body {
          background: linear-gradient(172deg, #17161C 0%, #121117 55%, #0D0C12 100%);
          color: #EDEAF2;
        }
        h1.main-title { color: #FFFFFF; }
        p.subtitle { color: #A6A2B1; }
        .eyebrow-pill {
          background: rgba(229, 69, 59, 0.20);
          border-color: rgba(229, 69, 59, 0.45);
          color: #FF8780;
        }
        .grid-pattern {
          background-image: radial-gradient(rgba(255, 255, 255, 0.05) 1.5px, transparent 1.5px);
        }
        .bottom-hook {
          background: #E5453B;
          color: #FFFFFF;
        }
        """
    return f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    {font_css()}
    {COMMON_CSS}
    {bg_override}
  </style>
</head>
<body>
  <div class="grid-pattern"></div>
  <div class="glow-red"></div>
  <div class="glow-warm"></div>
  {title_html}
  {body_html}
</body>
</html>"""


def generate_01_all_in_one():
    pdf_img = file_uri(os.path.join(CROPS_DIR, "clean_pdf_normal.png"))
    word_crop = file_uri(os.path.join(CROPS_DIR, "crop_word_card.png"))
    excel_crop = file_uri(os.path.join(CROPS_DIR, "crop_excel_top.png"))
    pptx_crop = file_uri(os.path.join(CROPS_DIR, "crop_pptx_slide1_card.png"))

    header = """
    <div class="header-container">
      <div class="eyebrow-pill"><span class="dot"></span> All-in-One • Zero Internet Permission</div>
      <h1 class="main-title">PDF, Word, Excel &amp; Slides<br>100% Offline &amp; Private.</h1>
      <p class="subtitle">No cloud uploads, no ads, no accounts. Every file stays strictly on your phone.</p>
    </div>
    """
    body = f"""
    <!-- Main Real PDF Phone Frame (slightly left for collage balance) -->
    <div class="phone-frame" style="top: 525px; left: 72px; width: 735px; height: 1580px;">
      <div class="phone-camera"></div>
      <div class="phone-screen">
        {clean_status_bar()}
        <img class="screen-img" src="{pdf_img}" alt="Pagelit PDF Reader"/>
      </div>
    </div>

    <!-- Floating Real Word Card (Top Right) -->
    <div class="float-card" style="top: 595px; right: 34px; width: 430px; height: 615px; border-color: #1971C2; transform: rotate(2.2deg);">
      <div style="background: #1971C2; color: white; padding: 9px 16px; display: flex; justify-content: space-between; align-items: center;">
        <span style="font-size: 14px; font-weight: 700;">DOCX • Native Layout</span>
        <span style="font-size: 12px; opacity: 0.9;">Tables &amp; Outline</span>
      </div>
      <img src="{word_crop}" style="width: 100%; display: block;"/>
    </div>

    <!-- Floating Real PowerPoint Card (Mid Right) -->
    <div class="float-card" style="top: 1245px; right: 30px; width: 420px; border-color: #E8590C; transform: rotate(-1.8deg); background: #17161C;">
      <div style="background: #E8590C; color: white; padding: 8px 16px; display: flex; justify-content: space-between; align-items: center;">
        <span style="font-size: 14px; font-weight: 700;">PPTX • Presentation</span>
        <span style="font-size: 12px;">16:9 &amp; Fullscreen</span>
      </div>
      <img src="{pptx_crop}" style="width: 100%; display: block;"/>
    </div>

    <!-- Floating Real Excel Card (Bottom Right) -->
    <div class="float-card" style="top: 1585px; right: 42px; width: 465px; height: 525px; border-color: #2B8A3E; transform: rotate(1.4deg);">
      <div style="background: #2B8A3E; color: white; padding: 8px 16px; display: flex; justify-content: space-between; align-items: center;">
        <span style="font-size: 14px; font-weight: 700;">XLSX • Formula Inspector</span>
        <span style="font-size: 12px;">Multi-Sheet</span>
      </div>
      <img src="{excel_crop}" style="width: 100%; display: block;"/>
    </div>

    <div class="bottom-hook">
      <span style="font-size: 24px;">🔒</span>
      <span>Zero INTERNET Permission • 100% Ad-Free Forever</span>
    </div>
    """
    return base_page(header, body)


def generate_02_markup_scrubber():
    qb_img = file_uri(os.path.join(CROPS_DIR, "clean_pdf_quickbar.png"))
    dock_crop = file_uri(os.path.join(CROPS_DIR, "crop_toolbar_scrubber.png"))

    header = """
    <div class="header-container">
      <div class="eyebrow-pill"><span class="dot"></span> Unlocked For Everyone • No Paywall</div>
      <h1 class="main-title">Annotate Free.<br>Scrub Pages Fast.</h1>
      <p class="subtitle">Highlight, underline, strike, squiggle &amp; add sticky notes in 7 colors with tactile chapter scrubbing.</p>
    </div>
    """
    body = f"""
    <!-- Main Real PDF Quick-Selection + Annotation Bar Phone -->
    <div class="phone-frame" style="top: 520px; left: 50%; transform: translateX(-50%); width: 760px; height: 1625px;">
      <div class="phone-camera"></div>
      <div class="phone-screen">
        {clean_status_bar()}
        <img class="screen-img" src="{qb_img}" alt="Pagelit PDF Annotations"/>
      </div>
    </div>

    <!-- Floating Label pointing to real Quick Action Bar -->
    <div class="float-pill" style="top: 765px; right: 34px; border-color: #E5453B;">
      <span style="font-size: 22px;">✨</span>
      <span>Instant Selection &amp; Gemini Bar</span>
    </div>

    <!-- Zoomed-In Magnification Callout of Real 7-Color Toolbar & Scrubber -->
    <div class="float-card" style="bottom: 142px; left: 50%; transform: translateX(-50%); width: 960px; border: 3px solid #E5453B; border-radius: 32px; background: #FBF8F4; padding: 14px 16px 10px 16px;">
      <div style="display: flex; justify-content: space-between; align-items: center; padding: 0 12px 10px 12px;">
        <span style="font-size: 16px; font-weight: 700; color: #C33A31; text-transform: uppercase; letter-spacing: 0.8px;">🔍 Precision Dock: Scrubber + 6 Tools + 7 Colors + Undo</span>
        <span class="badge-tag" style="background: #2B8A3E;">100% FREE</span>
      </div>
      <img src="{dock_crop}" style="width: 100%; border-radius: 22px; display: block; border: 1px solid #E9E2D8;"/>
    </div>

    <div class="bottom-hook">
      <span style="font-size: 24px;">🖍️</span>
      <span>Save Annotated PDF Copy Offline — No Subscription Needed</span>
    </div>
    """
    return base_page(header, body)


def generate_03_word_and_excel():
    word_img = file_uri(os.path.join(CROPS_DIR, "clean_word.png"))
    excel_img = file_uri(os.path.join(CROPS_DIR, "clean_excel.png"))

    header = """
    <div class="header-container">
      <div class="eyebrow-pill"><span class="dot"></span> True OOXML Office Engine</div>
      <h1 class="main-title">Crisp Word Docs.<br>Formula-Ready Excel.</h1>
      <p class="subtitle">Native tables, styled callouts &amp; outline headings in Word — multi-sheet tabs &amp; live =SUM() inspection in Excel.</p>
    </div>
    """
    body = f"""
    <!-- Left / Back Phone: Real Word Viewer -->
    <div class="phone-frame" style="top: 540px; left: 42px; width: 615px; height: 1320px; z-index: 4;">
      <div class="phone-camera"></div>
      <div class="phone-screen">
        {clean_status_bar()}
        <img class="screen-img" src="{word_img}" alt="Pagelit Word Viewer"/>
      </div>
    </div>

    <!-- Floating Badge Top Left -->
    <div class="float-pill" style="top: 492px; left: 48px; border-color: #1971C2; font-size: 18px; padding: 11px 22px;">
      <span class="badge-tag" style="background: #1971C2;">DOCX</span>
      <span>Outline TOC + Native Tables</span>
    </div>

    <!-- Right / Front Phone: Real Excel Viewer -->
    <div class="phone-frame" style="top: 880px; right: 42px; width: 615px; height: 1320px; z-index: 12;">
      <div class="phone-camera"></div>
      <div class="phone-screen">
        {clean_status_bar()}
        <img class="screen-img" src="{excel_img}" alt="Pagelit Excel Viewer"/>
      </div>
    </div>

    <!-- Floating Badge Right above Excel -->
    <div class="float-pill" style="top: 830px; right: 48px; border-color: #2B8A3E; font-size: 18px; padding: 11px 22px;">
      <span class="badge-tag" style="background: #2B8A3E;">XLSX</span>
      <span>Live Formula Bar (=SUM) &amp; Sheet Tabs</span>
    </div>

    <div class="bottom-hook">
      <span style="font-size: 24px;">⚡</span>
      <span>Save Any Word Page or Sheet Straight to Gallery</span>
    </div>
    """
    return base_page(header, body)


def generate_04_powerpoint():
    slide_img = file_uri(os.path.join(CROPS_DIR, "clean_pptx_slide.png"))
    grid_crop = file_uri(os.path.join(CROPS_DIR, "crop_pptx_grid.png"))
    slide1_crop = file_uri(os.path.join(CROPS_DIR, "crop_pptx_slide1_card.png"))

    header = """
    <div class="header-container">
      <div class="eyebrow-pill"><span class="dot"></span> Presentations On The Go</div>
      <h1 class="main-title">PowerPoint Decks<br>Built for Clarity.</h1>
      <p class="subtitle">Swipe 16:9 slides, jump via the 2×2 thumbnail overview, read outline notes, or play fullscreen slideshow.</p>
    </div>
    """
    body = f"""
    <!-- Main Real PPTX Slide Viewer Phone -->
    <div class="phone-frame" style="top: 525px; left: 68px; width: 730px; height: 1565px; z-index: 5;">
      <div class="phone-camera"></div>
      <div class="phone-screen">
        {clean_status_bar()}
        <img class="screen-img" src="{slide_img}" alt="Pagelit PowerPoint Slide"/>
      </div>
    </div>

    <!-- Mini Cover Slide Card (Top Right) -->
    <div class="float-card" style="top: 580px; right: 34px; width: 410px; border-color: #E8590C; background: #17161C; transform: rotate(2deg);">
      <div style="background: #E8590C; color: white; padding: 7px 14px; font-size: 13px; font-weight: 700; display: flex; justify-content: space-between;">
        <span>▶ Slideshow Ready</span>
        <span>Slide 1 / 4</span>
      </div>
      <img src="{slide1_crop}" style="width: 100%; display: block;"/>
    </div>

    <!-- Floating Real Slide Overview Grid Sheet (Bottom Right) -->
    <div class="float-card" style="bottom: 135px; right: 36px; width: 575px; border: 2.5px solid #E5453B; border-radius: 30px; z-index: 16;">
      <div style="background: #E5453B; color: white; padding: 10px 20px; display: flex; justify-content: space-between; align-items: center;">
        <span style="font-size: 16px; font-weight: 700;">⊞ Instant Slide Overview Grid</span>
        <span style="font-size: 13px; font-weight: 600;">16:9 Deck</span>
      </div>
      <img src="{grid_crop}" style="width: 100%; display: block;"/>
    </div>

    <div class="bottom-hook">
      <span style="font-size: 24px;">📽️</span>
      <span>Slides + Outline Mode + Fullscreen Player</span>
    </div>
    """
    return base_page(header, body)


def generate_05_comfort_and_languages():
    sepia_img = file_uri(os.path.join(CROPS_DIR, "clean_pdf_sepia.png"))
    night_img = file_uri(os.path.join(CROPS_DIR, "clean_pdf_night.png"))

    header = """
    <div class="header-container">
      <div class="eyebrow-pill"><span class="dot"></span> Zero Eye Strain • Multilingual</div>
      <h1 class="main-title">Sepia &amp; True Night.<br>English, FR &amp; العربية</h1>
      <p class="subtitle">Four comfort modes (Normal, Sepia, Dim, Night), system Dark Theme &amp; automatic Arabic RTL direction.</p>
    </div>
    """
    body = f"""
    <!-- Floating Pills Flanking Phone -->
    <div class="float-pill" style="top: 515px; left: 36px; border-color: #D97706; font-size: 18px; padding: 12px 22px;">
      <span>📜 Normal · Sepia · Dim · Night</span>
    </div>

    <div class="float-pill" style="top: 515px; right: 36px; border-color: #E5453B; font-size: 18px; padding: 12px 22px; background: #1C1B23; color: #EDEAF2;">
      <span>🌐 English · Français · العربية (RTL)</span>
    </div>

    <!-- Center Wide Phone with Real 50/50 Split Merge: Sepia (Left) vs Night (Right) -->
    <div class="phone-frame" style="top: 615px; left: 50%; transform: translateX(-50%); width: 775px; height: 1595px;">
      <div class="phone-camera"></div>
      <div class="phone-screen" style="background: #FBF8F4;">
        {clean_status_bar()}
        <div style="flex: 1; position: relative; overflow: hidden;">
          <!-- Left Half: Real Sepia Capture -->
          <div style="position: absolute; inset: 0; clip-path: inset(0 50% 0 0);">
            <img src="{sepia_img}" style="width: 100%; height: 100%; object-fit: cover; object-position: top center; display: block;"/>
          </div>
          <!-- Right Half: Real Night Capture -->
          <div style="position: absolute; inset: 0; clip-path: inset(0 0 0 50%);">
            <img src="{night_img}" style="width: 100%; height: 100%; object-fit: cover; object-position: top center; display: block;"/>
          </div>
          <!-- Crisp Center Split Divider + Pill -->
          <div style="position: absolute; top: 0; bottom: 0; left: 50%; width: 4px; transform: translateX(-50%); background: #E5453B; box-shadow: 0 0 18px rgba(229, 69, 59, 0.7);"></div>
          <div style="position: absolute; top: 47%; left: 50%; transform: translate(-50%, -50%); background: #E5453B; color: #FFFFFF; padding: 10px 22px; border-radius: 999px; font-size: 18px; font-weight: 700; box-shadow: 0 10px 28px rgba(0, 0, 0, 0.35); white-space: nowrap;">
            ◀ Warm Sepia &nbsp;|&nbsp; True Night ▶
          </div>
        </div>
      </div>
    </div>

    <div class="bottom-hook">
      <span style="font-size: 24px;">🌙</span>
      <span>Keep Screen On Option • Smooth Fade Transitions</span>
    </div>
    """
    return base_page(header, body, dark_bg=True)


def generate_06_gemini_and_tools():
    norm_img = file_uri(os.path.join(CROPS_DIR, "clean_pdf_normal.png"))
    menu_crop = file_uri(os.path.join(CROPS_DIR, "crop_more_menu.png"))

    header = """
    <div class="header-container">
      <div class="eyebrow-pill"><span class="dot"></span> One-Tap AI + Built-In Utilities</div>
      <h1 class="main-title">Ask Gemini in 1 Tap.<br>Print, Rotate &amp; Export.</h1>
      <p class="subtitle">Send any page, slide, or spreadsheet straight to Google Gemini — plus Print, Rotate 90° &amp; Save to Gallery.</p>
    </div>
    """
    body = f"""
    <!-- Left Phone: Real PDF Reader + Spotlight Ring on Real Sparkle Icon -->
    <div class="phone-frame" style="top: 530px; left: 48px; width: 700px; height: 1500px; z-index: 4;">
      <div class="phone-camera"></div>
      <div class="phone-screen">
        {clean_status_bar()}
        <div style="position: relative; flex: 1; overflow: hidden;">
          <img class="screen-img" src="{norm_img}" alt="Pagelit One-Tap Ask Gemini"/>
          <!-- Spotlight Ring directly around Pagelit's real red Ask Gemini sparkle button (~83% X, ~3.4% Y inside body) -->
          <div style="position: absolute; top: 14px; left: 548px; width: 64px; height: 64px; border-radius: 50%; border: 4.5px solid #E5453B; background: rgba(229, 69, 59, 0.14); box-shadow: 0 0 0 8px rgba(229, 69, 59, 0.16); pointer-events: none;"></div>
        </div>
      </div>
    </div>

    <!-- Callout Pill Pointing to the Red Gemini Button -->
    <div class="float-pill" style="top: 480px; right: 44px; border-color: #E5453B; font-size: 19px; padding: 13px 24px;">
      <span style="font-size: 22px;">✨</span>
      <span>1-Tap Ask Gemini (PDF · DOCX · XLSX · PPTX)</span>
    </div>

    <!-- Right Floating Real Menu Popup Crop -->
    <div class="float-card" style="top: 735px; right: 36px; width: 470px; border: 2.5px solid #17161C; border-radius: 30px; z-index: 16;">
      <div style="background: #17161C; color: white; padding: 10px 20px; display: flex; justify-content: space-between; align-items: center;">
        <span style="font-size: 16px; font-weight: 700;">Pro Reader Actions Menu</span>
        <span class="badge-tag" style="background: #E5453B;">OFFLINE TOOLS</span>
      </div>
      <img src="{menu_crop}" style="width: 100%; display: block;"/>
    </div>

    <div class="bottom-hook">
      <span style="font-size: 24px;">🖨️</span>
      <span>Print · Rotate 90° · Comments · Save View to Gallery</span>
    </div>
    """
    return base_page(header, body)


def render_screenshot(html_content, output_png_path):
    temp_html = output_png_path.replace(".png", "_temp.html")
    with open(temp_html, "w", encoding="utf-8") as f:
        f.write(html_content)

    print(f"Rendering: {os.path.basename(output_png_path)}...")
    cmd = [
        CHROME_PATH,
        "--headless=new",
        f"--screenshot={output_png_path}",
        "--window-size=1080,2400",
        "--force-device-scale-factor=1",
        "--disable-gpu",
        "--hide-scrollbars",
        f"file:///{temp_html.replace(os.sep, '/')}",
    ]
    subprocess.run(cmd, check=True)

    if os.path.exists(temp_html):
        os.remove(temp_html)

    w, h = Image.open(output_png_path).size
    print(f"  -> {os.path.basename(output_png_path)} ({w}x{h}, {os.path.getsize(output_png_path):,} bytes)")


def main():
    for old_name in OBSOLETE_FILES:
        old_path = os.path.join(OUTPUT_DIR, old_name)
        if os.path.exists(old_path):
            os.remove(old_path)
            print(f"Removed obsolete file: {old_name}")

    print("Preparing status-bar-free crops from real device captures...")
    prepare_crops()

    screens = [
        ("01_all_in_one_offline.png", generate_01_all_in_one()),
        ("02_pdf_markup_scrubber.png", generate_02_markup_scrubber()),
        ("03_word_and_excel.png", generate_03_word_and_excel()),
        ("04_powerpoint_slides.png", generate_04_powerpoint()),
        ("05_eye_comfort_and_languages.png", generate_05_comfort_and_languages()),
        ("06_gemini_and_pro_tools.png", generate_06_gemini_and_tools()),
    ]

    for fname, html in screens:
        out_path = os.path.join(OUTPUT_DIR, fname)
        render_screenshot(html, out_path)

    print("\nAll 6 Play Console screenshots generated in:")
    print(OUTPUT_DIR)


if __name__ == "__main__":
    main()
