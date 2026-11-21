import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pagelit/l10n/app_localizations.dart';
import 'package:pagelit/screens/word_viewer_screen.dart';
import 'package:pagelit/services/reading_prefs.dart';
import 'package:pagelit/services/word_parser.dart';

Uint8List _encodeArchive(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final data = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, data.length, data));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List createSampleDocx() {
  const relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rIdLink1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://pagelit.app" TargetMode="External"/>
</Relationships>''';

  const docXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:body>
    <!-- Centered heading with background shading -->
    <w:p>
      <w:pPr>
        <w:pStyle w:val="Heading1"/>
        <w:jc w:val="center"/>
        <w:shd w:fill="EBF3FB"/>
      </w:pPr>
      <w:r>
        <w:rPr>
          <w:sz w:val="48"/>
          <w:color w:val="0055AA"/>
        </w:rPr>
        <w:t>Project Specification</w:t>
      </w:r>
    </w:p>

    <!-- Paragraph with strikethrough, highlight, and line break -->
    <w:p>
      <w:pPr>
        <w:jc w:val="both"/>
      </w:pPr>
      <w:r>
        <w:rPr>
          <w:strike/>
        </w:rPr>
        <w:t>Old requirement.</w:t>
      </w:r>
      <w:r>
        <w:br/>
      </w:r>
      <w:r>
        <w:rPr>
          <w:highlight w:val="yellow"/>
          <w:b/>
        </w:rPr>
        <w:t>New requirement: High performance.</w:t>
      </w:r>
    </w:p>

    <!-- Paragraph with nested hyperlink -->
    <w:p>
      <w:r>
        <w:t>Visit our website: </w:t>
      </w:r>
      <w:hyperlink r:id="rIdLink1">
        <w:r>
          <w:rPr>
            <w:color w:val="0000FF"/>
            <w:u w:val="single"/>
          </w:rPr>
          <w:t>Pagelit Official Site</w:t>
        </w:r>
      </w:hyperlink>
    </w:p>
  </w:body>
</w:document>''';

  return _encodeArchive({
    'word/_rels/document.xml.rels': relsXml,
    'word/document.xml': docXml,
  });
}

Uint8List createRichWordDocx() {
  const themeXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office Theme">
  <a:themeElements>
    <a:clrScheme name="Office">
      <a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>
      <a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>
      <a:dk2><a:srgbClr val="44546A"/></a:dk2>
      <a:lt2><a:srgbClr val="E7E6E6"/></a:lt2>
      <a:accent1><a:srgbClr val="4472C4"/></a:accent1>
      <a:accent2><a:srgbClr val="ED7D31"/></a:accent2>
    </a:clrScheme>
    <a:fontScheme name="Office">
      <a:majorFont><a:latin typeface="Calibri Light"/></a:majorFont>
      <a:minorFont><a:latin typeface="Calibri"/></a:minorFont>
    </a:fontScheme>
  </a:themeElements>
</a:theme>''';

  const stylesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:asciiTheme="minorHAnsi"/>
        <w:sz w:val="22"/>
      </w:rPr>
    </w:rPrDefault>
    <w:pPrDefault>
      <w:pPr>
        <w:spacing w:after="160" w:line="259" w:lineRule="auto"/>
      </w:pPr>
    </w:pPrDefault>
  </w:docDefaults>
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:rPr>
      <w:color w:val="222222"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Titre1">
    <w:name w:val="heading 1"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:spacing w:before="240" w:after="80"/>
      <w:outlineLvl w:val="0"/>
      <w:pBdr>
        <w:bottom w:val="single" w:sz="12" w:color="auto" w:themeColor="accent1"/>
      </w:pBdr>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:asciiTheme="majorHAnsi"/>
      <w:b/>
      <w:sz w:val="32"/>
      <w:color w:themeColor="accent1" w:themeShade="BF"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="StrongQuote">
    <w:name w:val="Strong Quote"/>
    <w:basedOn w:val="Normal"/>
    <w:rPr>
      <w:b/>
      <w:i/>
    </w:rPr>
  </w:style>
  <w:style w:type="character" w:styleId="BadgeChar">
    <w:name w:val="BadgeChar"/>
    <w:rPr>
      <w:b/>
      <w:color w:themeColor="accent2"/>
      <w:shd w:val="clear" w:fill="FFF3E0"/>
    </w:rPr>
  </w:style>
  <w:style w:type="table" w:styleId="AccentTable">
    <w:name w:val="AccentTable"/>
    <w:tblPr>
      <w:tblBorders>
        <w:top w:val="single" w:sz="4" w:color="CCCCCC"/>
        <w:bottom w:val="single" w:sz="4" w:color="CCCCCC"/>
        <w:left w:val="none"/>
        <w:right w:val="none"/>
        <w:insideH w:val="single" w:sz="4" w:color="EEEEEE"/>
        <w:insideV w:val="none"/>
      </w:tblBorders>
    </w:tblPr>
    <w:tblStylePr w:type="firstRow">
      <w:rPr>
        <w:b/>
        <w:color w:val="FFFFFF"/>
      </w:rPr>
      <w:tcPr>
        <w:shd w:val="clear" w:fill="4472C4"/>
      </w:tcPr>
    </w:tblStylePr>
  </w:style>
</w:styles>''';

  const numberingXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:abstractNum w:abstractNumId="10">
    <w:lvl w:ilvl="0">
      <w:start w:val="1"/>
      <w:numFmt w:val="decimal"/>
      <w:lvlText w:val="%1."/>
      <w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr>
    </w:lvl>
    <w:lvl w:ilvl="1">
      <w:start w:val="1"/>
      <w:numFmt w:val="lowerLetter"/>
      <w:lvlText w:val="%2)"/>
      <w:pPr><w:ind w:left="1440" w:hanging="360"/></w:pPr>
    </w:lvl>
  </w:abstractNum>
  <w:abstractNum w:abstractNumId="11">
    <w:lvl w:ilvl="0">
      <w:numFmt w:val="bullet"/>
      <w:lvlText w:val="\uF0FC"/>
      <w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr>
    </w:lvl>
  </w:abstractNum>
  <w:num w:numId="1"><w:abstractNumId w:val="10"/></w:num>
  <w:num w:numId="2"><w:abstractNumId w:val="11"/></w:num>
</w:numbering>''';

  const docXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">
  <w:background w:color="FAFBFD"/>
  <w:body>
    <w:sdt>
      <w:sdtContent>
        <w:p>
          <w:pPr><w:pStyle w:val="Titre1"/></w:pPr>
          <w:r><w:t>Annual Report</w:t></w:r>
        </w:p>
      </w:sdtContent>
    </w:sdt>

    <w:p>
      <w:pPr><w:pStyle w:val="StrongQuote"/></w:pPr>
      <w:r>
        <w:rPr><w:b w:val="0"/></w:rPr>
        <w:t>Unbolded quote </w:t>
      </w:r>
      <w:r>
        <w:rPr><w:rStyle w:val="BadgeChar"/></w:rPr>
        <w:t>TAG</w:t>
      </w:r>
      <w:del><w:r><w:delText>SHOULD BE SKIPPED</w:delText></w:r></w:del>
    </w:p>

    <w:p>
      <w:r><w:t>H</w:t></w:r>
      <w:r><w:rPr><w:vertAlign w:val="subscript"/></w:rPr><w:t>2</w:t></w:r>
      <w:r><w:t>O and E=mc</w:t></w:r>
      <w:r><w:rPr><w:vertAlign w:val="superscript"/></w:rPr><w:t>2</w:t></w:r>
      <w:r><w:rPr><w:caps/></w:rPr><w:t> caps</w:t></w:r>
      <w:r><w:rPr><w:color w:themeColor="accent1" w:themeTint="33"/></w:rPr><w:t> tinted</w:t></w:r>
    </w:p>

    <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>First item</w:t></w:r></w:p>
    <w:p><w:pPr><w:numPr><w:ilvl w:val="1"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>Sub A</w:t></w:r></w:p>
    <w:p><w:pPr><w:numPr><w:ilvl w:val="1"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>Sub B</w:t></w:r></w:p>
    <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>Second item</w:t></w:r></w:p>
    <w:p><w:pPr><w:numPr><w:ilvl w:val="1"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>Sub Reset</w:t></w:r></w:p>
    <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="2"/></w:numPr></w:pPr><w:r><w:t>Check item</w:t></w:r></w:p>

    <w:p>
      <w:r><w:t>Before break</w:t></w:r>
      <w:r><w:br w:type="page"/></w:r>
      <w:r><w:t>After break</w:t></w:r>
    </w:p>

    <w:tbl>
      <w:tblPr>
        <w:tblStyle w:val="AccentTable"/>
        <w:tblW w:w="9000" w:type="dxa"/>
      </w:tblPr>
      <w:tblGrid>
        <w:gridCol w:w="4500"/>
        <w:gridCol w:w="4500"/>
      </w:tblGrid>
      <w:tr>
        <w:trPr><w:tblHeader/></w:trPr>
        <w:tc><w:p><w:r><w:t>Metric</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>Value</w:t></w:r></w:p></w:tc>
      </w:tr>
      <w:tr>
        <w:tc>
          <w:tcPr><w:vMerge w:val="restart"/><w:vAlign w:val="center"/></w:tcPr>
          <w:p><w:r><w:t>Hel</w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>lo</w:t></w:r></w:p>
          <w:p><w:r><w:t>Second line</w:t></w:r></w:p>
        </w:tc>
        <w:tc><w:p><w:r><w:t>100</w:t></w:r></w:p></w:tc>
      </w:tr>
      <w:tr>
        <w:tc><w:tcPr><w:vMerge/></w:tcPr><w:p/></w:tc>
        <w:tc><w:p><w:r><w:t>200</w:t></w:r></w:p></w:tc>
      </w:tr>
      <w:tr>
        <w:tc>
          <w:tcPr><w:gridSpan w:val="2"/></w:tcPr>
          <w:p><w:r><w:t>Merged footer</w:t></w:r></w:p>
        </w:tc>
      </w:tr>
    </w:tbl>

    <w:tbl>
      <w:tblPr>
        <w:tblBorders>
          <w:top w:val="none"/><w:bottom w:val="none"/>
          <w:left w:val="none"/><w:right w:val="none"/>
          <w:insideH w:val="none"/><w:insideV w:val="none"/>
        </w:tblBorders>
      </w:tblPr>
      <w:tr>
        <w:tc><w:p><w:r><w:t>Left</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>Right</w:t></w:r></w:p></w:tc>
      </w:tr>
    </w:tbl>

    <w:sectPr>
      <w:pgSz w:w="11906" w:h="16838"/>
      <w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/>
    </w:sectPr>
  </w:body>
</w:document>''';

  return _encodeArchive({
    'word/theme/theme1.xml': themeXml,
    'word/styles.xml': stylesXml,
    'word/numbering.xml': numberingXml,
    'word/document.xml': docXml,
  });
}

Uint8List _encodeArchiveRaw(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List createCoverPageDocx() {
  final cornerPng = img.encodePng(img.Image(width: 4, height: 4));

  const docRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rIdHdr1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>
</Relationships>''';

  const headerRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rIdCorner" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/corner.png"/>
</Relationships>''';

  const headerXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
       xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
       xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
       xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"
       xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:p>
    <w:r>
      <w:drawing>
        <wp:anchor behindDoc="1" relativeHeight="1">
          <wp:positionH relativeFrom="page"><wp:posOffset>254000</wp:posOffset></wp:positionH>
          <wp:positionV relativeFrom="page"><wp:posOffset>254000</wp:posOffset></wp:positionV>
          <wp:extent cx="635000" cy="635000"/>
          <a:graphic>
            <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
              <pic:pic>
                <pic:blipFill><a:blip r:embed="rIdCorner"/></pic:blipFill>
                <pic:spPr><a:xfrm rot="5400000" flipH="1"/></pic:spPr>
              </pic:pic>
            </a:graphicData>
          </a:graphic>
        </wp:anchor>
      </w:drawing>
    </w:r>
  </w:p>
</w:hdr>''';

  const docXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
            xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
            xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"
            xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:body>
    <w:p>
      <w:r>
        <w:drawing>
          <wp:anchor behindDoc="0" relativeHeight="20">
            <wp:positionH relativeFrom="page"><wp:posOffset>914400</wp:posOffset></wp:positionH>
            <wp:positionV relativeFrom="page"><wp:posOffset>914400</wp:posOffset></wp:positionV>
            <wp:extent cx="5486400" cy="2743200"/>
            <a:graphic>
              <a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">
                <wps:wsp>
                  <wps:spPr>
                    <a:prstGeom prst="snip2SameRect"/>
                    <a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill>
                    <a:ln w="19050"><a:solidFill><a:srgbClr val="1F4E79"/></a:solidFill></a:ln>
                  </wps:spPr>
                  <wps:txbx>
                    <w:txbxContent>
                      <w:p>
                        <w:pPr><w:jc w:val="center"/></w:pPr>
                        <w:r>
                          <w:rPr><w:b/><w:sz w:val="36"/><w:color w:val="1F4E79"/></w:rPr>
                          <w:t>CERTIFICATE OF EXCELLENCE</w:t>
                        </w:r>
                      </w:p>
                    </w:txbxContent>
                  </wps:txbx>
                </wps:wsp>
              </a:graphicData>
            </a:graphic>
          </wp:anchor>
        </w:drawing>
      </w:r>
      <w:r>
        <w:drawing>
          <wp:anchor behindDoc="0" relativeHeight="30">
            <wp:positionH relativeFrom="page"><wp:posOffset>1270000</wp:posOffset></wp:positionH>
            <wp:positionV relativeFrom="page"><wp:posOffset>4572000</wp:posOffset></wp:positionV>
            <wp:extent cx="2540000" cy="1270000"/>
            <a:graphic>
              <a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup">
                <wpg:wgp>
                  <wpg:grpSpPr>
                    <a:xfrm>
                      <a:chOff x="0" y="0"/>
                      <a:chExt cx="2540000" cy="1270000"/>
                    </a:xfrm>
                  </wpg:grpSpPr>
                  <wps:wsp>
                    <wps:spPr>
                      <a:xfrm>
                        <a:off x="0" y="0"/>
                        <a:ext cx="1270000" cy="635000"/>
                      </a:xfrm>
                      <a:prstGeom prst="roundRect"/>
                      <a:solidFill><a:srgbClr val="E8EEF5"/></a:solidFill>
                    </wps:spPr>
                    <wps:txbx>
                      <w:txbxContent>
                        <w:p><w:r><w:t>Group Box Label</w:t></w:r></w:p>
                      </w:txbxContent>
                    </wps:txbx>
                  </wps:wsp>
                </wpg:wgp>
              </a:graphicData>
            </a:graphic>
          </wp:anchor>
        </w:drawing>
      </w:r>
    </w:p>
    <w:sectPr>
      <w:headerReference w:type="default" r:id="rIdHdr1"/>
      <w:pgSz w:w="12240" w:h="15840"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
    </w:sectPr>
  </w:body>
</w:document>''';

  return _encodeArchiveRaw({
    'word/_rels/document.xml.rels': utf8.encode(docRelsXml),
    'word/_rels/header1.xml.rels': utf8.encode(headerRelsXml),
    'word/header1.xml': utf8.encode(headerXml),
    'word/media/corner.png': cornerPng,
    'word/document.xml': utf8.encode(docXml),
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File tempDocxFile;
  late File tempRichDocxFile;
  late File tempCoverDocxFile;

  setUp(() async {
    ReadingPrefs.comfortMode.value = ComfortMode.normal;
    tempDocxFile = File('${Directory.systemTemp.path}/test_styling.docx');
    await tempDocxFile.writeAsBytes(createSampleDocx());
    tempRichDocxFile = File('${Directory.systemTemp.path}/test_rich_word.docx');
    await tempRichDocxFile.writeAsBytes(createRichWordDocx());
    tempCoverDocxFile = File('${Directory.systemTemp.path}/test_cover_word.docx');
    await tempCoverDocxFile.writeAsBytes(createCoverPageDocx());
  });

  tearDown(() async {
    ReadingPrefs.comfortMode.value = ComfortMode.normal;
    for (final f in [tempDocxFile, tempRichDocxFile, tempCoverDocxFile]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  });

  test('WordParser parses alignments, hyperlinks, font sizes, strikethrough, highlights, and line breaks', () async {
    final zipBytes = createSampleDocx();
    final doc = await WordParser.parse(zipBytes);

    expect(doc.blocks.length, 3);

    // Block 0: Heading 1, centered, font size 24pt (48 / 2), background shading EBF3FB
    final h1 = doc.blocks[0] as WordParagraph;
    expect(h1.headingLevel, 1);
    expect(h1.alignment, TextAlign.center);
    expect(h1.backgroundColorHex, 'EBF3FB');
    expect(h1.spans.first.fontSize, 24.0);
    expect(h1.spans.first.colorHex, '0055AA');

    // Block 1: Justified paragraph, strikethrough, line break, yellow highlight
    final p2 = doc.blocks[1] as WordParagraph;
    expect(p2.alignment, TextAlign.justify);
    expect(p2.spans[0].text, 'Old requirement.');
    expect(p2.spans[0].strikethrough, true);
    expect(p2.spans[1].text, '\n');
    expect(p2.spans[2].text, 'New requirement: High performance.');
    expect(p2.spans[2].bold, true);
    expect(p2.spans[2].highlightHex, 'yellow');

    // Block 2: Hyperlink extracted with URL target
    final p3 = doc.blocks[2] as WordParagraph;
    expect(p3.fullText, contains('Visit our website: Pagelit Official Site'));
    final linkSpan = p3.spans.firstWhere((s) => s.text == 'Pagelit Official Site');
    expect(linkSpan.linkUrl, 'https://pagelit.app');
    expect(linkSpan.underline, true);
    expect(linkSpan.colorHex, '0000FF');
  });

  test('WordParser resolves styles, themes, numbering, SDT, deletions, page breaks, and rich tables', () async {
    final doc = await WordParser.parse(createRichWordDocx());

    // Document defaults & page settings
    expect(doc.defaultFontSizePt, 11.0);
    expect(doc.defaultFontFamily, 'Calibri');
    expect(doc.pageSettings.backgroundColorHex, 'FAFBFD');
    expect(doc.pageSettings.widthPt, closeTo(595.3, 0.2));
    expect(doc.pageSettings.marginLeftPt, closeTo(56.7, 0.2));

    // SDT heading with localized style name + theme font + theme shade + bottom border
    final heading = doc.blocks[0] as WordParagraph;
    expect(heading.fullText, 'Annual Report');
    expect(heading.headingLevel, 1);
    expect(heading.spaceBeforePt, 12.0);
    expect(heading.spaceAfterPt, 4.0);
    expect(heading.borders?.bottom?.isVisible, true);
    expect(heading.borders?.bottom?.widthPt, 1.5);
    expect(heading.borders?.bottom?.colorHex, '4472C4');
    expect(heading.spans.first.fontFamily, 'Calibri Light');
    expect(heading.spans.first.fontSize, 16.0);
    expect(heading.spans.first.bold, true);
    // accent1 (4472C4 = 68, 114, 196) * shade BF (191/255) = 335593
    expect(heading.spans.first.colorHex, '335593');

    // Inherited bold overridden by w:b w:val="0", character style rStyle, and skipped w:del
    final quote = doc.blocks[1] as WordParagraph;
    expect(quote.fullText, 'Unbolded quote TAG');
    expect(quote.spans[0].bold, false);
    expect(quote.spans[0].italic, true);
    expect(quote.spans[1].bold, true);
    expect(quote.spans[1].colorHex, 'ED7D31');
    expect(quote.spans[1].shadingColorHex, 'FFF3E0');

    // Subscript, superscript, caps, and themeTint
    final scripts = doc.blocks[2] as WordParagraph;
    expect(scripts.spans[1].isSubscript, true);
    expect(scripts.spans[3].isSuperscript, true);
    expect(scripts.spans[4].allCaps, true);
    // accent1 (4472C4) with tint 33 (20% color + 80% white = 218, 227, 243 = DAE3F3)
    expect(scripts.spans[5].colorHex, 'DAE3F3');

    // Numbered lists with multi-level counter resets and bullet PUA glyph mapping
    final list1 = doc.blocks[3] as WordParagraph;
    final list1a = doc.blocks[4] as WordParagraph;
    final list1b = doc.blocks[5] as WordParagraph;
    final list2 = doc.blocks[6] as WordParagraph;
    final list2a = doc.blocks[7] as WordParagraph;
    final check = doc.blocks[8] as WordParagraph;
    expect(list1.listMarker, '1.');
    expect(list1.indent, 36.0);
    expect(list1.firstLineIndent, -18.0);
    expect(list1a.listMarker, 'a)');
    expect(list1a.listLevel, 1);
    expect(list1a.indent, 72.0);
    expect(list1b.listMarker, 'b)');
    expect(list2.listMarker, '2.');
    expect(list2a.listMarker, 'a)');
    expect(check.listMarker, '✓');

    // Page break splits paragraph cleanly
    final beforeBreak = doc.blocks[9] as WordParagraph;
    final pageBreak = doc.blocks[10];
    final afterBreak = doc.blocks[11] as WordParagraph;
    expect(beforeBreak.fullText, 'Before break');
    expect(pageBreak, isA<WordPageBreakBlock>());
    expect(afterBreak.fullText, 'After break');

    // Styled table with firstRow, rich cells, vMerge, gridSpan
    final styledTbl = doc.blocks[12] as WordTableBlock;
    expect(styledTbl.hasExplicitHeaderRow, true);
    expect(styledTbl.columnWidthsPt, [225.0, 225.0]);
    expect(styledTbl.borders?.hasAny, true);
    expect(styledTbl.borders?.left?.isVisible, false);

    final hCell = styledTbl.richCells![0][0];
    expect(hCell.backgroundColorHex, '4472C4');
    final hPara = hCell.blocks.first as WordParagraph;
    expect(hPara.spans.first.bold, true);
    expect(hPara.spans.first.colorHex, 'FFFFFF');

    final mergedVertCell = styledTbl.richCells![1][0];
    expect(mergedVertCell.text, 'Hello\nSecond line');
    expect(mergedVertCell.rowSpan, 2);
    expect(mergedVertCell.verticalAlignment, 'center');
    expect((mergedVertCell.blocks[0] as WordParagraph).spans[1].bold, true);

    expect(styledTbl.richCells![2][0].isVerticalMergeContinue, true);
    expect(styledTbl.richCells![3][0].colSpan, 2);

    // Borderless table
    final borderlessTbl = doc.blocks[13] as WordTableBlock;
    expect(borderlessTbl.borders, isNotNull);
    expect(borderlessTbl.borders!.hasAny, false);
  });

  testWidgets('WordViewerScreen renders styled headings, highlights, and hyperlinks', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: WordViewerScreen(
            filePath: tempDocxFile.path,
            title: 'test_styling.docx',
          ),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 300));
    });

    await tester.pump();

    expect(find.text('Project Specification'), findsOneWidget);
    expect(find.byType(SelectableText), findsWidgets);
  });

  testWidgets('WordViewerScreen renders rich Word formatting, lists, page breaks, and merged tables cleanly', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: WordViewerScreen(
            filePath: tempRichDocxFile.path,
            title: 'test_rich_word.docx',
          ),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 300));
    });

    await tester.pump();

    expect(find.text('Annual Report'), findsOneWidget);
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.text('✓'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Metric'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Metric'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Merged footer'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Merged footer'), findsOneWidget);

    // Verify dim comfort mode renders without errors as well.
    ReadingPrefs.comfortMode.value = ComfortMode.dim;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('WordParser parses anchored drawings, text boxes, grouped shapes, and header images', () async {
    final doc = await WordParser.parse(createCoverPageDocx());

    expect(doc.blocks, isEmpty);
    expect(doc.floatingElements.length, 3);

    // 1. Snip2SameRect text box
    final box = doc.floatingElements[0];
    expect(box.xPt, closeTo(72.0, 0.1));
    expect(box.yPt, closeTo(72.0, 0.1));
    expect(box.widthPt, closeTo(432.0, 0.1));
    expect(box.heightPt, closeTo(216.0, 0.1));
    expect(box.shapeType, 'snip2SameRect');
    expect(box.fillColorHex, 'FFFFFF');
    expect(box.strokeColorHex, '1F4E79');
    expect(box.strokeWidthPt, closeTo(1.5, 0.1));
    expect(box.textBlocks.length, 1);
    expect((box.textBlocks.first as WordParagraph).fullText, 'CERTIFICATE OF EXCELLENCE');

    // 2. Unpacked grouped shape
    final grpShape = doc.floatingElements[1];
    expect(grpShape.xPt, closeTo(100.0, 0.1));
    expect(grpShape.yPt, closeTo(360.0, 0.1));
    expect(grpShape.widthPt, closeTo(100.0, 0.1));
    expect(grpShape.heightPt, closeTo(50.0, 0.1));
    expect(grpShape.shapeType, 'roundRect');
    expect(grpShape.fillColorHex, 'E8EEF5');
    expect((grpShape.textBlocks.first as WordParagraph).fullText, 'Group Box Label');

    // 3. Repeating header anchored image with rotation and horizontal flip
    final hdrCorner = doc.floatingElements[2];
    expect(hdrCorner.pageIndex, -1);
    expect(hdrCorner.behindDoc, true);
    expect(hdrCorner.xPt, closeTo(20.0, 0.1));
    expect(hdrCorner.yPt, closeTo(20.0, 0.1));
    expect(hdrCorner.rotationDeg, closeTo(90.0, 0.1));
    expect(hdrCorner.flipH, true);
    expect(hdrCorner.imageBytes, isNotNull);
  });

  testWidgets('WordViewerScreen renders cover page floating shapes/headers and handles narrow AppBar without overflow', (tester) async {
    tester.view.physicalSize = const Size(220, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: WordViewerScreen(
            filePath: tempCoverDocxFile.path,
            title: 'Very Long Cover Document Filename (4).docx',
          ),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 300));
    });

    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('CERTIFICATE OF EXCELLENCE'), findsOneWidget);
    expect(find.text('Group Box Label'), findsOneWidget);

    // Exercise animated double-tap zoom in and back out cleanly.
    final viewerFinder = find.byType(InteractiveViewer);
    expect(viewerFinder, findsOneWidget);
    final center = tester.getCenter(viewerFinder);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
