import os
import subprocess
import zipfile

CHROME_PATH = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
OUT_DIR = os.path.abspath(r"tool\sample_docs")
os.makedirs(OUT_DIR, exist_ok=True)


def build_pdf():
    html = """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  @page {
    size: letter;
    margin: 0.7in 0.75in;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif;
    color: #17161C;
    line-height: 1.65;
    font-size: 13.5px;
  }
  .page {
    page-break-after: always;
    padding-top: 8px;
  }
  .page:last-child { page-break-after: auto; }
  .eyebrow {
    font-size: 10.5px;
    font-weight: 800;
    letter-spacing: 1.5px;
    text-transform: uppercase;
    color: #E5453B;
    margin-bottom: 6px;
  }
  h1 {
    font-size: 28px;
    font-weight: 800;
    line-height: 1.2;
    color: #17161C;
    margin-bottom: 12px;
  }
  h2 {
    font-size: 20px;
    font-weight: 700;
    color: #0C3866;
    margin: 18px 0 10px 0;
  }
  p {
    margin-bottom: 12px;
    color: #2B2A32;
  }
  .callout {
    background: #FFF9DB;
    border-left: 4px solid #FAB005;
    padding: 12px 16px;
    border-radius: 6px;
    margin: 16px 0;
    font-size: 13px;
  }
  .callout-blue {
    background: #E7F5FF;
    border-left: 4px solid #1971C2;
    padding: 12px 16px;
    border-radius: 6px;
    margin: 16px 0;
    font-size: 13px;
  }
  .kpi-row {
    display: flex;
    gap: 12px;
    margin: 18px 0;
  }
  .kpi {
    flex: 1;
    background: #F8F6F2;
    border: 1px solid #E5DFD5;
    border-radius: 10px;
    padding: 14px 16px;
  }
  .kpi-label {
    font-size: 10.5px;
    font-weight: 700;
    color: #6E6A77;
    text-transform: uppercase;
    letter-spacing: 0.8px;
  }
  .kpi-val {
    font-size: 24px;
    font-weight: 800;
    color: #E5453B;
    margin-top: 2px;
  }
  .chart-box {
    background: #FAFAFC;
    border: 1px solid #E6E6EC;
    border-radius: 10px;
    padding: 16px 18px;
    margin: 18px 0;
  }
  .chart-title {
    font-size: 12.5px;
    font-weight: 700;
    color: #444;
    margin-bottom: 14px;
  }
  .bars {
    display: flex;
    align-items: flex-end;
    gap: 18px;
    height: 130px;
    padding-top: 10px;
    border-bottom: 1.5px solid #D0D0D8;
  }
  .bar-col {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    height: 100%;
    justify-content: flex-end;
  }
  .bar {
    width: 60%;
    border-radius: 6px 6px 0 0;
    background: #E5453B;
  }
  .bar-lbls {
    display: flex;
    gap: 18px;
    margin-top: 6px;
    font-size: 11px;
    color: #555;
    text-align: center;
  }
  .bar-lbls div { flex: 1; font-weight: 600; }
  table {
    width: 100%;
    border-collapse: collapse;
    margin: 16px 0;
    font-size: 12.5px;
  }
  th {
    background: #17161C;
    color: #FFFFFF;
    text-align: left;
    padding: 10px 12px;
    font-weight: 700;
  }
  td {
    padding: 9px 12px;
    border-bottom: 1px solid #E5DFD5;
  }
  tr:nth-child(even) td { background: #FAF8F4; }
  ul { margin: 10px 0 14px 20px; }
  li { margin-bottom: 6px; }
</style>
</head>
<body>
  <div class="page">
    <div class="eyebrow">Annual Briefing • 2026 Edition</div>
    <h1>Global Market &amp; Digital Document Report</h1>
    <p>
      Organizations worldwide accelerated the shift toward local-first document workflows in 2026. Rather than uploading confidential PDFs, contracts, and spreadsheets to remote servers, teams increasingly rely on private on-device readers capable of fast rendering and offline markup.
    </p>
    <div class="kpi-row">
      <div class="kpi">
        <div class="kpi-label">YoY Adoption</div>
        <div class="kpi-val">+38.4%</div>
      </div>
      <div class="kpi">
        <div class="kpi-label">Avg Render Time</div>
        <div class="kpi-val" style="color:#1971C2;">18 ms</div>
      </div>
      <div class="kpi">
        <div class="kpi-label">Offline Privacy</div>
        <div class="kpi-val" style="color:#2B8A3E;">100%</div>
      </div>
    </div>
    <div class="callout">
      <b>Key Finding:</b> Mobile professionals review 4.3x more PDFs and OOXML Office files offline during transit than at connected workstations, making zero-lag zoom and tactile chapter navigation critical for daily productivity.
    </div>
    <div class="chart-box">
      <div class="chart-title">Figure 1.1 — Enterprise Mobile Document Growth Index (2023–2026)</div>
      <div class="bars">
        <div class="bar-col"><div class="bar" style="height:38%; background:#F7B4AF;"></div></div>
        <div class="bar-col"><div class="bar" style="height:56%; background:#F18A83;"></div></div>
        <div class="bar-col"><div class="bar" style="height:78%; background:#EB645B;"></div></div>
        <div class="bar-col"><div class="bar" style="height:98%; background:#E5453B;"></div></div>
      </div>
      <div class="bar-lbls">
        <div>2023 (42)</div>
        <div>2024 (64)</div>
        <div>2025 (89)</div>
        <div>2026 (118)</div>
      </div>
    </div>
    <p>
      Security audits across regulated legal, healthcare, and engineering departments emphasize minimizing network permissions. Applications operating without external telemetry eliminate inadvertent leakage of proprietary blueprints and financial models.
    </p>
  </div>

  <div class="page">
    <div class="eyebrow">Chapter 2 • Performance Benchmarks</div>
    <h2>On-Device Rendering Architecture</h2>
    <p>
      Hardware-accelerated canvas rasterization eliminates jitter when pinching deep into complex schematic drawings, dense academic journals, and multi-column annual filings.
    </p>
    <table>
      <tr>
        <th>Document Class</th>
        <th>Typical Pages</th>
        <th>Cold Open</th>
        <th>Memory Budget</th>
      </tr>
      <tr>
        <td><b>Technical Whitepaper (PDF)</b></td>
        <td>48 pages</td>
        <td>95 ms</td>
        <td>34 MB</td>
      </tr>
      <tr>
        <td><b>Service Agreement (DOCX)</b></td>
        <td>12 pages</td>
        <td>110 ms</td>
        <td>28 MB</td>
      </tr>
      <tr>
        <td><b>Quarterly Model (XLSX)</b></td>
        <td>4 sheets</td>
        <td>85 ms</td>
        <td>24 MB</td>
      </tr>
      <tr>
        <td><b>Executive Deck (PPTX)</b></td>
        <td>24 slides</td>
        <td>130 ms</td>
        <td>41 MB</td>
      </tr>
    </table>
    <div class="callout-blue">
      <b>Engineering Note:</b> Keeping working memory compact avoids garbage collection pauses while dragging zoomed pages across high-refresh-rate displays.
    </div>
    <ul>
      <li><b>Vector Fidelity:</b> Sharp text contours at up to 3x magnification without pixelation.</li>
      <li><b>Persistent Progress:</b> Exact page numbers and scroll positions restore automatically.</li>
      <li><b>Eye Comfort Tints:</b> Warm Sepia, Dim, and True Night modes lower luminance glare.</li>
    </ul>
  </div>

  <div class="page">
    <div class="eyebrow">Chapter 3 • Security &amp; Compliance</div>
    <h2>Zero-Permission Data Governance</h2>
    <p>
      Modern privacy regulations require strict provenance over document handling. By stripping network access entirely at the manifest level, mobile readers provide verifiable assurance that user files remain solely on local storage.
    </p>
    <p>
      When optional analysis is desired by the user, explicit page snapshots keep context scoped strictly to the single active page rather than exposing entire document libraries to background indexing.
    </p>
  </div>

  <div class="page">
    <div class="eyebrow">Chapter 4 • Regional Outlook</div>
    <h2>Global Multi-Script Adoption</h2>
    <p>
      Cross-border teams frequently collaborate across English, French, and Arabic technical manuals. Proper bidirectional layout mirroring ensures right-to-left scripts remain aligned alongside bilingual appendices and numerical tables.
    </p>
    <p>
      Educational institutions and consulting groups report measurable time savings when field engineers can jump smoothly between document sections without subscription locks or account sign-in prompts.
    </p>
  </div>

  <div class="page">
    <div class="eyebrow">Chapter 5 • 2026 Takeaways</div>
    <h2>Summary &amp; Strategic Priorities</h2>
    <ul>
      <li>Consolidate PDF, Word, Excel, and PowerPoint review into one lightweight workspace.</li>
      <li>Guarantee full annotation capability without recurring monthly paywalls.</li>
      <li>Protect battery longevity and eyesight with paper-warm sepia and deep night palettes.</li>
    </ul>
  </div>
</body>
</html>
"""
    temp_html = os.path.join(OUT_DIR, "_temp_report.html")
    pdf_path = os.path.join(OUT_DIR, "Global_Market_Report_2026.pdf")
    with open(temp_html, "w", encoding="utf-8") as f:
        f.write(html)
    cmd = [
        CHROME_PATH,
        "--headless=new",
        f"--print-to-pdf={pdf_path}",
        "--no-pdf-header-footer",
        f"file:///{temp_html.replace(os.sep, '/')}",
    ]
    subprocess.run(cmd, check=True)
    if os.path.exists(temp_html):
        os.remove(temp_html)
    print(f"Created {pdf_path} ({os.path.getsize(pdf_path):,} bytes)")


def build_docx():
    docx_path = os.path.join(OUT_DIR, "Product_Launch_Strategy.docx")
    content_types = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>"""
    rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>"""
    doc_rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>"""
    styles_xml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/><w:color w:val="222222"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:spacing w:before="240" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="36"/><w:color w:val="0C3866"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="heading 2"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:spacing w:before="220" w:after="100"/><w:outlineLvl w:val="1"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="E5453B"/></w:rPr>
  </w:style>
</w:styles>"""

    def tbl_cell(text, bg=None, bold=False, color="222222", align="left"):
        shd = f'<w:shd w:val="clear" w:color="auto" w:fill="{bg}"/>' if bg else ""
        b_tag = "<w:b/>" if bold else ""
        return f"""<w:tc>
          <w:tcPr>{shd}<w:tcMar><w:top w:w="90" w:type="dxa"/><w:bottom w:w="90" w:type="dxa"/><w:left w:w="100" w:type="dxa"/><w:right w:w="100" w:type="dxa"/></w:tcMar></w:tcPr>
          <w:p><w:pPr><w:spacing w:after="0"/><w:jc w:val="{align}"/></w:pPr><w:r><w:rPr>{b_tag}<w:color w:val="{color}"/><w:sz w:val="18"/></w:rPr><w:t>{text}</w:t></w:r></w:p>
        </w:tc>"""

    document_xml = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
      <w:r><w:rPr><w:b/><w:sz w:val="38"/><w:color w:val="0C3866"/></w:rPr><w:t>2026 Product Launch Strategy</w:t></w:r>
    </w:p>
    <w:p>
      <w:pPr><w:spacing w:after="180"/><w:pBdr><w:bottom w:val="single" w:sz="12" w:space="6" w:color="E5453B"/></w:pBdr></w:pPr>
      <w:r><w:rPr><w:b/><w:sz w:val="18"/><w:color w:val="6E6A77"/></w:rPr><w:t>COMMERCIAL OPERATIONS BRIEFING  •  Q4 RELEASE PLAN</w:t></w:r>
    </w:p>

    <w:p>
      <w:pPr><w:pStyle w:val="Heading2"/></w:pPr>
      <w:r><w:rPr><w:b/><w:sz w:val="26"/><w:color w:val="0C3866"/></w:rPr><w:t>1. Executive Summary</w:t></w:r>
    </w:p>
    <w:p>
      <w:r><w:t>This document outlines core operational milestones, engineering deliverables, and cross-functional review dates for the 2026 product launch across North America and EMEA markets.</w:t></w:r>
    </w:p>

    <w:p>
      <w:pPr>
        <w:shd w:val="clear" w:color="auto" w:fill="FBE6E3"/>
        <w:pBdr><w:left w:val="single" w:sz="24" w:space="8" w:color="E5453B"/></w:pBdr>
        <w:ind w:left="180" w:right="120"/>
        <w:spacing w:before="100" w:after="200"/>
      </w:pPr>
      <w:r><w:rPr><w:b/><w:color w:val="C33A31"/></w:rPr><w:t>Key Target: </w:t></w:r>
      <w:r><w:t>Achieve 99.9% offline reliability across customer documentation portals prior to general availability in Quarter 4.</w:t></w:r>
    </w:p>

    <w:p>
      <w:pPr><w:pStyle w:val="Heading2"/></w:pPr>
      <w:r><w:rPr><w:b/><w:sz w:val="26"/><w:color w:val="0C3866"/></w:rPr><w:t>2. Milestone Schedule &amp; Valuation</w:t></w:r>
    </w:p>

    <w:tbl>
      <w:tblPr>
        <w:tblW w:w="5000" w:type="pct"/>
        <w:tblBorders>
          <w:top w:val="single" w:sz="6" w:color="CBD5E1"/>
          <w:left w:val="single" w:sz="6" w:color="CBD5E1"/>
          <w:bottom w:val="single" w:sz="6" w:color="CBD5E1"/>
          <w:right w:val="single" w:sz="6" w:color="CBD5E1"/>
          <w:insideH w:val="single" w:sz="4" w:color="E2E8F0"/>
          <w:insideV w:val="single" w:sz="4" w:color="E2E8F0"/>
        </w:tblBorders>
      </w:tblPr>
      <w:tblGrid>
        <w:gridCol w:w="3000"/>
        <w:gridCol w:w="2100"/>
        <w:gridCol w:w="2300"/>
        <w:gridCol w:w="2200"/>
      </w:tblGrid>
      <w:tr>
        <w:trPr><w:tblHeader/></w:trPr>
        {tbl_cell("Phase", bg="0C3866", bold=True, color="FFFFFF")}
        {tbl_cell("Timeline", bg="0C3866", bold=True, color="FFFFFF")}
        {tbl_cell("Owner", bg="0C3866", bold=True, color="FFFFFF")}
        {tbl_cell("Budget", bg="0C3866", bold=True, color="FFFFFF", align="right")}
      </w:tr>
      <w:tr>
        {tbl_cell("Architecture", bold=True)}
        {tbl_cell("Mo 1–2")}
        {tbl_cell("Platform")}
        {tbl_cell("$45,000", bold=True, align="right")}
      </w:tr>
      <w:tr>
        {tbl_cell("Localization", bg="F8F9FA", bold=True)}
        {tbl_cell("Mo 3–4", bg="F8F9FA")}
        {tbl_cell("Product", bg="F8F9FA")}
        {tbl_cell("$28,500", bg="F8F9FA", bold=True, align="right")}
      </w:tr>
      <w:tr>
        {tbl_cell("QA &amp; Audit", bold=True)}
        {tbl_cell("Month 5")}
        {tbl_cell("Security")}
        {tbl_cell("$32,000", bold=True, align="right")}
      </w:tr>
      <w:tr>
        {tbl_cell("Global Launch", bg="F8F9FA", bold=True)}
        {tbl_cell("Month 6", bg="F8F9FA")}
        {tbl_cell("Growth", bg="F8F9FA")}
        {tbl_cell("$54,000", bg="F8F9FA", bold=True, align="right")}
      </w:tr>
    </w:tbl>

    <w:p>
      <w:pPr><w:pStyle w:val="Heading2"/></w:pPr>
      <w:r><w:rPr><w:b/><w:sz w:val="26"/><w:color w:val="0C3866"/></w:rPr><w:t>3. Launch Readiness Checklist</w:t></w:r>
    </w:p>
    <w:p><w:r><w:t>•  Finalize English, French, and Arabic RTL interface verification.</w:t></w:r></w:p>
    <w:p><w:r><w:t>•  Confirm zero-network offline compliance across every platform build.</w:t></w:r></w:p>
    <w:p><w:r><w:t>•  Publish technical customer onboarding guides and press kit assets.</w:t></w:r></w:p>

    <w:sectPr>
      <w:pgSz w:w="12240" w:h="15840"/>
      <w:pgMar w:top="1080" w:right="1080" w:bottom="1080" w:left="1080"/>
    </w:sectPr>
  </w:body>
</w:document>"""

    with zipfile.ZipFile(docx_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("[Content_Types].xml", content_types)
        zf.writestr("_rels/.rels", rels)
        zf.writestr("word/_rels/document.xml.rels", doc_rels)
        zf.writestr("word/styles.xml", styles_xml)
        zf.writestr("word/document.xml", document_xml)
    print(f"Created {docx_path} ({os.path.getsize(docx_path):,} bytes)")


def build_xlsx():
    xlsx_path = os.path.join(OUT_DIR, "Q4_Financial_Model.xlsx")

    content_types = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet3.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>"""
    rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>"""
    wb_xml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Summary" sheetId="1" r:id="rId1"/>
    <sheet name="Revenue" sheetId="2" r:id="rId2"/>
    <sheet name="Expenses" sheetId="3" r:id="rId3"/>
  </sheets>
</workbook>"""
    wb_rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/>
</Relationships>"""

    def make_sheet(rows_data):
        row_xml = []
        for r_idx, row in enumerate(rows_data, start=1):
            cells = []
            for c_idx, cell in enumerate(row):
                col_letter = chr(65 + c_idx)
                coord = f"{col_letter}{r_idx}"
                if isinstance(cell, tuple):
                    formula, val = cell
                    cells.append(f'<c r="{coord}"><f>{formula}</f><v>{val}</v></c>')
                elif isinstance(cell, (int, float)):
                    cells.append(f'<c r="{coord}"><v>{cell}</v></c>')
                else:
                    escaped = (
                        str(cell)
                        .replace("&", "&amp;")
                        .replace("<", "&lt;")
                        .replace(">", "&gt;")
                    )
                    cells.append(
                        f'<c r="{coord}" t="inlineStr"><is><t>{escaped}</t></is></c>'
                    )
            row_xml.append(f'<row r="{r_idx}">{"".join(cells)}</row>')
        return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>{"".join(row_xml)}</sheetData>
</worksheet>"""

    sheet1 = make_sheet([
        ["Department", "Q3 Actual", "Q4 Budget", "Q4 Actual", "Variance"],
        ["Cloud Infrastructure", 41200, 45000, 42800, ("D2-C2", -2200)],
        ["Engineering R&D", 112000, 120000, 118500, ("D3-C3", -1500)],
        ["Growth Marketing", 79500, 85000, 84200, ("D4-C4", -800)],
        ["Legal & Security", 16400, 18000, 16900, ("D5-C5", -1100)],
        ["Product Support", 29800, 32000, 31400, ("D6-C6", -600)],
        ["Design & QA", 21500, 24000, 23100, ("D7-C7", -900)],
        ["Total Expenditure", ("SUM(B2:B7)", 300400), ("SUM(C2:C7)", 324000), ("SUM(D2:D7)", 316900), ("SUM(E2:E7)", -7100)],
    ])

    sheet2 = make_sheet([
        ["Region", "Q1 ($)", "Q2 ($)", "Q3 ($)", "Q4 ($)", "Full Year"],
        ["North America", 142000, 158000, 174000, 196000, ("SUM(B2:E2)", 670000)],
        ["Europe (EMEA)", 98000, 112000, 128000, 145000, ("SUM(B3:E3)", 483000)],
        ["Asia-Pacific", 64000, 79000, 91000, 114000, ("SUM(B4:E4)", 348000)],
        ["Latin America", 28000, 34000, 41000, 52000, ("SUM(B5:E5)", 155000)],
        ["Total Revenue", ("SUM(B2:B5)", 332000), ("SUM(C2:C5)", 383000), ("SUM(D2:D5)", 434000), ("SUM(E2:E5)", 507000), ("SUM(F2:F5)", 1656000)],
    ])

    sheet3 = make_sheet([
        ["Expense Item", "Category", "Monthly Avg", "Annual Total"],
        ["Compute Nodes", "Hosting", 8500, ("C2*12", 102000)],
        ["SDK Licenses", "Tooling", 2200, ("C3*12", 26400)],
        ["Security Audits", "Compliance", 3100, ("C4*12", 37200)],
        ["Team Operations", "General", 6400, ("C5*12", 76800)],
        ["Total OpEx", "", ("SUM(C2:C5)", 20200), ("SUM(D2:D5)", 242400)],
    ])

    with zipfile.ZipFile(xlsx_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("[Content_Types].xml", content_types)
        zf.writestr("_rels/.rels", rels)
        zf.writestr("xl/workbook.xml", wb_xml)
        zf.writestr("xl/_rels/workbook.xml.rels", wb_rels)
        zf.writestr("xl/worksheets/sheet1.xml", sheet1)
        zf.writestr("xl/worksheets/sheet2.xml", sheet2)
        zf.writestr("xl/worksheets/sheet3.xml", sheet3)
    print(f"Created {xlsx_path} ({os.path.getsize(xlsx_path):,} bytes)")


def build_pptx():
    pptx_path = os.path.join(OUT_DIR, "Keynote_Pitch_Deck.pptx")
    W = 12192000  # 13.33 in (16:9)
    H = 6858000   # 7.5 in

    def shape(sp_id, name, x_pct, y_pct, w_pct, h_pct, fill=None, border=None, border_pt=1.5, geom="roundRect", paragraphs=None, ph_type=None, valign="ctr"):
        x = int(W * x_pct)
        y = int(H * y_pct)
        cx = int(W * w_pct)
        cy = int(H * h_pct)
        ph_xml = f'<p:nvPr><p:ph type="{ph_type}"/></p:nvPr>' if ph_type else "<p:nvPr/>"
        fill_xml = f'<a:solidFill><a:srgbClr val="{fill}"/></a:solidFill>' if fill else "<a:noFill/>"
        if border:
            ln_w = int(border_pt * 12700)
            ln_xml = f'<a:ln w="{ln_w}"><a:solidFill><a:srgbClr val="{border}"/></a:solidFill></a:ln>'
        else:
            ln_xml = '<a:ln><a:noFill/></a:ln>'
        p_xml = ""
        for p in (paragraphs or []):
            align = p.get("align", "l")
            bullet_xml = '<a:buChar char="•"/>' if p.get("bullet") else "<a:buNone/>"
            runs = ""
            for r in p.get("runs", []):
                sz = int(r.get("sz", 18) * 100)
                b = ' b="1"' if r.get("bold") else ' b="0"'
                col = r.get("color", "17161C")
                txt = str(r.get("text", "")).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                runs += f'<a:r><a:rPr lang="en-US" sz="{sz}"{b}><a:solidFill><a:srgbClr val="{col}"/></a:solidFill></a:rPr><a:t>{txt}</a:t></a:r>'
            p_xml += f'<a:p><a:pPr algn="{align}">{bullet_xml}</a:pPr>{runs}</a:p>'
        return f"""<p:sp>
          <p:nvSpPr><p:cNvPr id="{sp_id}" name="{name}"/><p:cNvSpPr/>{ph_xml}</p:nvSpPr>
          <p:spPr>
            <a:xfrm><a:off x="{x}" y="{y}"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm>
            <a:prstGeom prst="{geom}"><a:avLst/></a:prstGeom>
            {fill_xml}
            {ln_xml}
          </p:spPr>
          <p:txBody><a:bodyPr anchor="{valign}" lIns="140000" rIns="140000" tIns="100000" bIns="100000"/><a:lstStyle/>{p_xml}</p:txBody>
        </p:sp>"""

    def wrap_slide(bg_hex, shapes_xml):
        return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:bg><p:bgPr><a:solidFill><a:srgbClr val="{bg_hex}"/></a:solidFill></p:bgPr></p:bg>
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr/>
      {"".join(shapes_xml)}
    </p:spTree>
  </p:cSld>
</p:sld>"""

    # Slide 1: Cover
    s1 = wrap_slide("17161C", [
        shape(2, "Tag", 0.08, 0.22, 0.28, 0.08, fill="E5453B", paragraphs=[
            {"align": "ctr", "runs": [{"text": "2026 KEYNOTE BRIEFING", "sz": 14, "bold": True, "color": "FFFFFF"}]}
        ]),
        shape(3, "Title", 0.08, 0.34, 0.84, 0.25, ph_type="ctrTitle", geom="rect", paragraphs=[
            {"runs": [{"text": "Offline-First Document Workflows", "sz": 40, "bold": True, "color": "FFFFFF"}]}
        ]),
        shape(4, "Subtitle", 0.08, 0.60, 0.78, 0.14, geom="rect", paragraphs=[
            {"runs": [{"text": "Fast PDF annotation, Office fidelity & private mobile reading across your entire organization.", "sz": 20, "color": "C8C4D4"}]}
        ]),
        shape(5, "FooterBadge", 0.08, 0.82, 0.84, 0.08, fill="232229", border="383642", border_pt=1, paragraphs=[
            {"runs": [{"text": "   PDF  •  Word (DOCX)  •  Excel (XLSX)  •  PowerPoint (PPTX)      |      100% Private & Ad-Free", "sz": 14, "bold": True, "color": "EDEAF2"}]}
        ]),
    ])

    # Slide 2: Market Growth & KPIs
    s2 = wrap_slide("FBF8F4", [
        shape(2, "Eyebrow", 0.06, 0.07, 0.30, 0.05, geom="rect", valign="t", paragraphs=[
            {"runs": [{"text": "KEY METRICS • Q4 2026", "sz": 12, "bold": True, "color": "E5453B"}]}
        ]),
        shape(3, "Title", 0.06, 0.12, 0.88, 0.11, ph_type="title", geom="rect", valign="t", paragraphs=[
            {"runs": [{"text": "Market Opportunity & Mobile Velocity", "sz": 30, "bold": True, "color": "17161C"}]}
        ]),
        shape(4, "KPI1", 0.06, 0.28, 0.27, 0.28, fill="FFFFFF", border="E5453B", border_pt=2, paragraphs=[
            {"align": "ctr", "runs": [{"text": "+38%", "sz": 38, "bold": True, "color": "E5453B"}]},
            {"align": "ctr", "runs": [{"text": "Annual Offline Document Growth", "sz": 14, "color": "555259"}]}
        ]),
        shape(5, "KPI2", 0.365, 0.28, 0.27, 0.28, fill="FFFFFF", border="1971C2", border_pt=2, paragraphs=[
            {"align": "ctr", "runs": [{"text": "18 ms", "sz": 38, "bold": True, "color": "1971C2"}]},
            {"align": "ctr", "runs": [{"text": "Median On-Device Page Render", "sz": 14, "color": "555259"}]}
        ]),
        shape(6, "KPI3", 0.67, 0.28, 0.27, 0.28, fill="FFFFFF", border="2B8A3E", border_pt=2, paragraphs=[
            {"align": "ctr", "runs": [{"text": "0 Bytes", "sz": 38, "bold": True, "color": "2B8A3E"}]},
            {"align": "ctr", "runs": [{"text": "External Cloud Telemetry Sent", "sz": 14, "color": "555259"}]}
        ]),
        shape(7, "Takeaways", 0.06, 0.62, 0.88, 0.28, fill="F4F0E8", border="E9E2D8", border_pt=1, paragraphs=[
            {"bullet": True, "runs": [{"text": "Unified support for PDFs, DOCX documents, multi-sheet XLSX models & PPTX slides.", "sz": 16, "color": "17161C"}]},
            {"bullet": True, "runs": [{"text": "No forced sign-in walls, no cloud upload limits, and zero advertising trackers.", "sz": 16, "color": "17161C"}]}
        ]),
    ])

    # Slide 3: Product Pillars
    s3 = wrap_slide("FFFFFF", [
        shape(2, "Title", 0.06, 0.09, 0.88, 0.11, ph_type="title", geom="rect", valign="t", paragraphs=[
            {"runs": [{"text": "Two Pillars Built for Focused Reading", "sz": 30, "bold": True, "color": "0C3866"}]}
        ]),
        shape(3, "LeftCard", 0.06, 0.25, 0.42, 0.62, fill="FBF8F4", border="E5453B", border_pt=2, valign="t", paragraphs=[
            {"runs": [{"text": "Precision PDF Annotation", "sz": 22, "bold": True, "color": "E5453B"}]},
            {"bullet": True, "runs": [{"text": "Highlight, underline, strike & squiggle in 7 colors", "sz": 15, "color": "222222"}]},
            {"bullet": True, "runs": [{"text": "Sticky comments & annotated copy export", "sz": 15, "color": "222222"}]},
            {"bullet": True, "runs": [{"text": "Tactile chapter scrubber with bookmark preview", "sz": 15, "color": "222222"}]}
        ]),
        shape(4, "RightCard", 0.52, 0.25, 0.42, 0.62, fill="F4F7FB", border="1971C2", border_pt=2, valign="t", paragraphs=[
            {"runs": [{"text": "Native Office Fidelity", "sz": 22, "bold": True, "color": "1971C2"}]},
            {"bullet": True, "runs": [{"text": "True Word layout, tables, callouts & outline", "sz": 15, "color": "222222"}]},
            {"bullet": True, "runs": [{"text": "Excel formula inspector & multi-sheet switching", "sz": 15, "color": "222222"}]},
            {"bullet": True, "runs": [{"text": "PowerPoint slide grid & fullscreen mode", "sz": 15, "color": "222222"}]}
        ]),
    ])

    # Slide 4: Roadmap
    s4 = wrap_slide("17161C", [
        shape(2, "Title", 0.06, 0.10, 0.88, 0.12, ph_type="title", geom="rect", valign="t", paragraphs=[
            {"runs": [{"text": "2026 Strategic Execution Roadmap", "sz": 30, "bold": True, "color": "FFFFFF"}]}
        ]),
        shape(3, "Q1", 0.06, 0.30, 0.20, 0.48, fill="232229", border="E5453B", border_pt=2, valign="t", paragraphs=[
            {"runs": [{"text": "Q1 • Foundation", "sz": 17, "bold": True, "color": "E5453B"}]},
            {"runs": [{"text": "Hardware PDF canvas & chapter TOC detection", "sz": 14, "color": "DDD9E6"}]}
        ]),
        shape(4, "Q2", 0.29, 0.30, 0.20, 0.48, fill="232229", border="4DABF7", border_pt=2, valign="t", paragraphs=[
            {"runs": [{"text": "Q2 • Office Suite", "sz": 17, "bold": True, "color": "4DABF7"}]},
            {"runs": [{"text": "OOXML Word, Excel & Slide render engines", "sz": 14, "color": "DDD9E6"}]}
        ]),
        shape(5, "Q3", 0.52, 0.30, 0.20, 0.48, fill="232229", border="51CF66", border_pt=2, valign="t", paragraphs=[
            {"runs": [{"text": "Q3 • Eye Comfort", "sz": 17, "bold": True, "color": "51CF66"}]},
            {"runs": [{"text": "Sepia, Dim & Night modes + EN / FR / AR", "sz": 14, "color": "DDD9E6"}]}
        ]),
        shape(6, "Q4", 0.75, 0.30, 0.20, 0.48, fill="E5453B", border="FF8787", border_pt=2, valign="t", paragraphs=[
            {"runs": [{"text": "Q4 • Gemini AI", "sz": 17, "bold": True, "color": "FFFFFF"}]},
            {"runs": [{"text": "One-tap page summaries sent directly to Gemini", "sz": 14, "color": "FFFFFF"}]}
        ]),
    ])

    slides = [s1, s2, s3, s4]
    ct_overrides = "\n".join(
        f'  <Override PartName="/ppt/slides/slide{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'
        for i in range(1, len(slides) + 1)
    )
    content_types = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
  <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
{ct_overrides}
</Types>"""
    rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
</Relationships>"""
    pres_rels_items = "\n".join(
        f'  <Relationship Id="rId{i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide{i}.xml"/>'
        for i in range(1, len(slides) + 1)
    )
    pres_rels = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
{pres_rels_items}
  <Relationship Id="rId99" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>
</Relationships>"""
    sld_ids = "\n".join(
        f'    <p:sldId id="{255 + i}" r:id="rId{i}"/>' for i in range(1, len(slides) + 1)
    )
    pres_xml = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:sldIdLst>
{sld_ids}
  </p:sldIdLst>
  <p:sldSz cx="{W}" cy="{H}" type="screen16x9"/>
  <p:notesSz cx="6858000" cy="9144000"/>
</p:presentation>"""
    theme_xml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="PagelitTheme">
  <a:themeElements>
    <a:clrScheme name="Pagelit">
      <a:dk1><a:srgbClr val="17161C"/></a:dk1>
      <a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>
      <a:dk2><a:srgbClr val="0C3866"/></a:dk2>
      <a:lt2><a:srgbClr val="FBF8F4"/></a:lt2>
      <a:accent1><a:srgbClr val="E5453B"/></a:accent1>
      <a:accent2><a:srgbClr val="1971C2"/></a:accent2>
      <a:accent3><a:srgbClr val="2B8A3E"/></a:accent3>
      <a:accent4><a:srgbClr val="FAB005"/></a:accent4>
      <a:accent5><a:srgbClr val="4DABF7"/></a:accent5>
      <a:accent6><a:srgbClr val="51CF66"/></a:accent6>
      <a:hlink><a:srgbClr val="1971C2"/></a:hlink>
      <a:folHlink><a:srgbClr val="7950F2"/></a:folHlink>
    </a:clrScheme>
    <a:fontScheme name="Pagelit"><a:majorFont><a:latin typeface="Calibri"/></a:majorFont><a:minorFont><a:latin typeface="Calibri"/></a:minorFont></a:fontScheme>
    <a:fmtScheme name="Pagelit"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme>
  </a:themeElements>
</a:theme>"""

    with zipfile.ZipFile(pptx_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("[Content_Types].xml", content_types)
        zf.writestr("_rels/.rels", rels)
        zf.writestr("ppt/presentation.xml", pres_xml)
        zf.writestr("ppt/_rels/presentation.xml.rels", pres_rels)
        zf.writestr("ppt/theme/theme1.xml", theme_xml)
        for i, s_xml in enumerate(slides, start=1):
            zf.writestr(f"ppt/slides/slide{i}.xml", s_xml)
    print(f"Created {pptx_path} ({os.path.getsize(pptx_path):,} bytes)")


def main():
    build_pdf()
    build_docx()
    build_xlsx()
    build_pptx()


if __name__ == "__main__":
    main()
