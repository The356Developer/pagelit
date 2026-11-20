import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagelit/services/presentation_parser.dart';

void main() {
  test('Visual PresentationParser parses slide dimensions, theme colors, and visual elements', () async {
    final archive = Archive();

    // 1. presentation.xml with 16:9 widescreen dimensions
    const presXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:sldSz cx="12192000" cy="6858000"/>
  <p:sldIdLst>
    <p:sldId id="256" r:id="rId1"/>
  </p:sldIdLst>
</p:presentation>''';

    // 2. presentation.xml.rels
    const presRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>
</Relationships>''';

    // 3. theme1.xml with custom accent colors
    const themeXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office Theme">
  <a:themeElements>
    <a:clrScheme name="Office">
      <a:dk1><a:sysClr val="windowText" lastClr="112233"/></a:dk1>
      <a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>
      <a:dk2><a:srgbClr val="223344"/></a:dk2>
      <a:lt2><a:srgbClr val="EFEFEF"/></a:lt2>
      <a:accent1><a:srgbClr val="FF5500"/></a:accent1>
      <a:accent2><a:srgbClr val="00AAFF"/></a:accent2>
    </a:clrScheme>
  </a:themeElements>
</a:theme>''';

    // 4. slide1.xml.rels with image
    const slide1RelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rIdImg1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.png"/>
</Relationships>''';

    // 5. slide1.xml with title shape, styled body shape, and picture
    const slide1Xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:bg>
      <p:bgPr>
        <a:solidFill><a:srgbClr val="FAFAFA"/></a:solidFill>
      </p:bgPr>
    </p:bg>
    <p:spTree>
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="2" name="Title 1"/>
          <p:nvPr><p:ph type="title"/></p:nvPr>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm>
            <a:off x="1219200" y="685800"/>
            <a:ext cx="9753600" cy="1371600"/>
          </a:xfrm>
        </p:spPr>
        <p:txBody>
          <a:p>
            <a:pPr algn="ctr"/>
            <a:r>
              <a:rPr sz="3200" b="1">
                <a:solidFill><a:schemeClr val="accent1"/></a:solidFill>
              </a:rPr>
              <a:t>MX-LAB ASSISTANT IA</a:t>
            </a:r>
          </a:p>
        </p:txBody>
      </p:sp>
      <p:pic>
        <p:nvPicPr>
          <p:cNvPr id="3" name="Picture 1"/>
        </p:nvPicPr>
        <p:blipFill>
          <a:blip r:embed="rIdImg1"/>
        </p:blipFill>
        <p:spPr>
          <a:xfrm>
            <a:off x="1219200" y="2743200"/>
            <a:ext cx="4876800" cy="3429000"/>
          </a:xfrm>
        </p:spPr>
      </p:pic>
    </p:spTree>
  </p:cSld>
</p:sld>''';

    final dummyPngBytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);

    archive.addFile(ArchiveFile('ppt/presentation.xml', presXml.length, utf8.encode(presXml)));
    archive.addFile(ArchiveFile('ppt/_rels/presentation.xml.rels', presRelsXml.length, utf8.encode(presRelsXml)));
    archive.addFile(ArchiveFile('ppt/theme/theme1.xml', themeXml.length, utf8.encode(themeXml)));
    archive.addFile(ArchiveFile('ppt/slides/slide1.xml', slide1Xml.length, utf8.encode(slide1Xml)));
    archive.addFile(ArchiveFile('ppt/slides/_rels/slide1.xml.rels', slide1RelsXml.length, utf8.encode(slide1RelsXml)));
    archive.addFile(ArchiveFile('ppt/media/image1.png', dummyPngBytes.length, dummyPngBytes));

    final zipBytes = ZipEncoder().encode(archive);
    final deck = await PresentationParser.parse(Uint8List.fromList(zipBytes));

    expect(deck.slides.length, 1);
    expect(deck.aspectRatio, closeTo(16 / 9, 0.01));
    expect(deck.slideWidthEmu, 12192000);
    expect(deck.slideHeightEmu, 6858000);

    final slide = deck.slides.first;
    expect(slide.title, 'MX-LAB ASSISTANT IA');
    expect(slide.backgroundColor, const Color(0xFFFAFAFA));

    // Check elements
    expect(slide.elements.length, 2);
    final titleElem = slide.elements.first as SlideShapeElement;
    expect(titleElem.x, closeTo(0.1, 0.01));
    expect(titleElem.y, closeTo(0.1, 0.01));
    expect(titleElem.width, closeTo(0.8, 0.01));
    expect(titleElem.height, closeTo(0.2, 0.01));

    expect(titleElem.paragraphs.first.alignment, TextAlign.center);
    final span = titleElem.paragraphs.first.spans.first;
    expect(span.text, 'MX-LAB ASSISTANT IA');
    expect(span.bold, true);
    expect(span.fontSize, 32.0);
    expect(span.fontColor, const Color(0xFFFF5500)); // Resolved from accent1

    final picElem = slide.elements[1] as SlidePictureElement;
    expect(picElem.x, closeTo(0.1, 0.01));
    expect(picElem.y, closeTo(0.4, 0.01));
    expect(picElem.width, closeTo(0.4, 0.01));
    expect(picElem.height, closeTo(0.5, 0.01));
    expect(picElem.imageBytes, dummyPngBytes);
  });

  test('Visual PresentationParser parses tables and group shapes with coordinate offsets', () async {
    final archive = Archive();

    const presXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:sldSz cx="10000000" cy="5000000"/>
  <p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst>
</p:presentation>''';

    const presRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>
</Relationships>''';

    const slide1Xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:graphicFrame>
        <a:xfrm>
          <a:off x="1000000" y="1000000"/>
          <a:ext cx="8000000" cy="2000000"/>
        </a:xfrm>
        <a:graphic>
          <a:graphicData>
            <a:tbl>
              <a:tblGrid>
                <a:gridCol w="4000000"/>
                <a:gridCol w="4000000"/>
              </a:tblGrid>
              <a:tr h="1000000">
                <a:tc><a:txBody><a:p><a:r><a:t>Cell 1A</a:t></a:r></a:p></a:txBody></a:tc>
                <a:tc><a:txBody><a:p><a:r><a:t>Cell 1B</a:t></a:r></a:p></a:txBody></a:tc>
              </a:tr>
            </a:tbl>
          </a:graphicData>
        </a:graphic>
      </p:graphicFrame>

      <p:grpSp>
        <p:grpSpPr>
          <a:xfrm>
            <a:off x="2000000" y="3000000"/>
            <a:ext cx="4000000" cy="1500000"/>
            <a:chOff x="0" y="0"/>
            <a:chExt cx="200" cy="100"/>
          </a:xfrm>
        </p:grpSpPr>
        <p:sp>
          <p:spPr>
            <a:xfrm>
              <a:off x="50" y="25"/>
              <a:ext cx="100" cy="50"/>
            </a:xfrm>
          </p:spPr>
          <p:txBody><a:p><a:r><a:t>Grouped Text</a:t></a:r></a:p></p:txBody>
        </p:sp>
      </p:grpSp>
    </p:spTree>
  </p:cSld>
</p:sld>''';

    archive.addFile(ArchiveFile('ppt/presentation.xml', presXml.length, utf8.encode(presXml)));
    archive.addFile(ArchiveFile('ppt/_rels/presentation.xml.rels', presRelsXml.length, utf8.encode(presRelsXml)));
    archive.addFile(ArchiveFile('ppt/slides/slide1.xml', slide1Xml.length, utf8.encode(slide1Xml)));

    final deck = await PresentationParser.parse(Uint8List.fromList(ZipEncoder().encode(archive)));
    expect(deck.slides.length, 1);
    final elements = deck.slides.first.elements;
    expect(elements.length, 2);

    final table = elements[0] as SlideTableElement;
    expect(table.x, closeTo(0.1, 0.01));
    expect(table.y, closeTo(0.2, 0.01));
    expect(table.rows.length, 1);
    expect(table.rows.first[0].plainText, 'Cell 1A');
    expect(table.rows.first[1].plainText, 'Cell 1B');

    // Group shape mapping:
    // child x=50 in (0..200) -> 0.25 offset in group extW (4000000) = 1000000 + offX(2000000) = 3000000
    // 3000000 / 10000000 = 0.3
    final groupedShape = elements[1] as SlideShapeElement;
    expect(groupedShape.x, closeTo(0.3, 0.01));
    expect(groupedShape.plainText, 'Grouped Text');
  });

  test('PresentationParser extracts <p:timing> animations, layout placeholder inheritance, and expanded transitions', () async {
    final archive = Archive();

    const presXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:sldSz cx="10000000" cy="5000000"/>
  <p:sldIdLst>
    <p:sldId id="256" r:id="rId1"/>
    <p:sldId id="257" r:id="rId2"/>
    <p:sldId id="258" r:id="rId3"/>
  </p:sldIdLst>
</p:presentation>''';

    const presRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide2.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide3.xml"/>
</Relationships>''';

    const slide1RelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rIdL1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
</Relationships>''';

    const layout1Xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:bg><p:bgPr><a:solidFill><a:srgbClr val="112233"/></a:solidFill></p:bgPr></p:bg>
    <p:spTree>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="1" name="Title Placeholder"/><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="500000" y="250000"/><a:ext cx="9000000" cy="1000000"/></a:xfrm>
        </p:spPr>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:sldLayout>''';

    const slide1Xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="10" name="Title 1"/><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>
        <p:txBody><a:p><a:r><a:t>Inherited Position Title</a:t></a:r></a:p></p:txBody>
      </p:sp>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="11" name="Box A"/><p:nvPr/></p:nvSpPr>
        <p:spPr><a:xfrm><a:off x="1000000" y="2000000"/><a:ext cx="3000000" cy="1000000"/></a:xfrm></p:spPr>
        <p:txBody><a:p><a:r><a:t>Fly In Point</a:t></a:r></a:p></p:txBody>
      </p:sp>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="12" name="Box B"/><p:nvPr/></p:nvSpPr>
        <p:spPr><a:xfrm><a:off x="5000000" y="2000000"/><a:ext cx="3000000" cy="1000000"/></a:xfrm></p:spPr>
        <p:txBody><a:p><a:r><a:t>Zoom Point</a:t></a:r></a:p></p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
  <p:transition spd="fast"><p:cover dir="l"/></p:transition>
  <p:timing>
    <p:tnLst>
      <p:par>
        <p:cTn id="1" nodeType="tmRoot">
          <p:childTnLst>
            <p:seq>
              <p:cTn id="2" nodeType="mainSeq">
                <p:childTnLst>
                  <p:par>
                    <p:cTn id="3" presetID="10" presetClass="entr" presetSubtype="0" nodeType="withEffect">
                      <p:stCondLst><p:cond delay="0"/></p:stCondLst>
                      <p:childTnLst>
                        <p:animEffect><p:cBhvr><p:cTn id="4" dur="350"/><p:tgtEl><p:spTgt spid="10"/></p:tgtEl></p:cBhvr></p:animEffect>
                      </p:childTnLst>
                    </p:cTn>
                  </p:par>
                  <p:par>
                    <p:cTn id="5" presetID="2" presetClass="entr" presetSubtype="8" nodeType="clickEffect">
                      <p:stCondLst><p:cond delay="50"/></p:stCondLst>
                      <p:childTnLst>
                        <p:anim><p:cBhvr><p:cTn id="6" dur="500"/><p:tgtEl><p:spTgt spid="11"/></p:tgtEl></p:cBhvr></p:anim>
                      </p:childTnLst>
                    </p:cTn>
                  </p:par>
                  <p:par>
                    <p:cTn id="7" presetID="23" presetClass="entr" presetSubtype="0" nodeType="clickEffect">
                      <p:childTnLst>
                        <p:anim><p:cBhvr><p:cTn id="8" dur="400"/><p:tgtEl><p:spTgt spid="12"/></p:tgtEl></p:cBhvr></p:anim>
                      </p:childTnLst>
                    </p:cTn>
                  </p:par>
                </p:childTnLst>
              </p:cTn>
            </p:seq>
          </p:childTnLst>
        </p:cTn>
      </p:par>
    </p:tnLst>
  </p:timing>
</p:sld>''';

    const slide2Xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld><p:spTree/></p:cSld>
  <p:transition><p:split/></p:transition>
</p:sld>''';

    const slide3Xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld><p:spTree/></p:cSld>
  <p:transition><p:cut/></p:transition>
</p:sld>''';

    archive.addFile(ArchiveFile('ppt/presentation.xml', presXml.length, utf8.encode(presXml)));
    archive.addFile(ArchiveFile('ppt/_rels/presentation.xml.rels', presRelsXml.length, utf8.encode(presRelsXml)));
    archive.addFile(ArchiveFile('ppt/slides/_rels/slide1.xml.rels', slide1RelsXml.length, utf8.encode(slide1RelsXml)));
    archive.addFile(ArchiveFile('ppt/slideLayouts/slideLayout1.xml', layout1Xml.length, utf8.encode(layout1Xml)));
    archive.addFile(ArchiveFile('ppt/slides/slide1.xml', slide1Xml.length, utf8.encode(slide1Xml)));
    archive.addFile(ArchiveFile('ppt/slides/slide2.xml', slide2Xml.length, utf8.encode(slide2Xml)));
    archive.addFile(ArchiveFile('ppt/slides/slide3.xml', slide3Xml.length, utf8.encode(slide3Xml)));

    final deck = await PresentationParser.parse(Uint8List.fromList(ZipEncoder().encode(archive)));
    expect(deck.slides.length, 3);

    final s1 = deck.slides[0];
    // Background inherited from slideLayout1
    expect(s1.backgroundColor, const Color(0xFF112233));
    expect(s1.transitionType, SlideTransitionType.cover);
    expect(s1.transitionDurationMs, 250);

    // Title shape inherited <a:xfrm> from slideLayout1 placeholder
    final inheritedTitle = s1.elements[0] as SlideShapeElement;
    expect(inheritedTitle.shapeId, '10');
    expect(inheritedTitle.x, closeTo(0.05, 0.005));
    expect(inheritedTitle.y, closeTo(0.05, 0.005));
    expect(inheritedTitle.width, closeTo(0.90, 0.005));
    expect(inheritedTitle.height, closeTo(0.20, 0.005));

    // Timing steps parsed cleanly
    expect(s1.animations.length, 3);
    expect(s1.animationClickStepCount, 2);

    expect(s1.animations[0].shapeId, '10');
    expect(s1.animations[0].effect, SlideAnimationEffect.fade);
    expect(s1.animations[0].trigger, SlideAnimationTrigger.withPrevious);
    expect(s1.animations[0].clickGroup, 0);
    expect(s1.animations[0].durationMs, 350);

    expect(s1.animations[1].shapeId, '11');
    expect(s1.animations[1].effect, SlideAnimationEffect.flyIn);
    expect(s1.animations[1].direction, SlideAnimationDirection.fromLeft);
    expect(s1.animations[1].trigger, SlideAnimationTrigger.onClick);
    expect(s1.animations[1].clickGroup, 1);
    expect(s1.animations[1].delayMs, 50);

    expect(s1.animations[2].shapeId, '12');
    expect(s1.animations[2].effect, SlideAnimationEffect.zoom);
    expect(s1.animations[2].clickGroup, 2);

    // Expanded transitions on slide 2 & 3
    expect(deck.slides[1].transitionType, SlideTransitionType.split);
    expect(deck.slides[2].transitionType, SlideTransitionType.cut);
  });
}
