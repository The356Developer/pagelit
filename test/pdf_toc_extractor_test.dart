import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagelit/services/pdf_toc_extractor.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Future<Uint8List> _saveAndDispose(PdfDocument doc) async {
  try {
    final bytes = await doc.save();
    return Uint8List.fromList(bytes);
  } finally {
    doc.dispose();
  }
}

void main() {
  group('PdfTocExtractor', () {
    test('Tier 1: extracts hierarchical embedded bookmarks with parent destination fallback', () async {
      final doc = PdfDocument();
      final p1 = doc.pages.add();
      final p2 = doc.pages.add();
      final p3 = doc.pages.add();
      final p4 = doc.pages.add();

      p1.graphics.drawString(
        'Cover Page',
        PdfStandardFont(PdfFontFamily.helvetica, 20),
        bounds: const Rect.fromLTWH(40, 40, 400, 40),
      );

      // Parent chapter without a direct destination; child points to page 3
      final ch1 = doc.bookmarks.add('Chapter 1: Foundations');
      ch1.add('1.1 Background').destination =
          PdfDestination(p3, const Offset(0, 0));
      ch1.add('1.2 Core Model').destination =
          PdfDestination(p4, const Offset(0, 0));

      doc.bookmarks.add('Chapter 2: Conclusion').destination =
          PdfDestination(p2, const Offset(0, 0));

      final bytes = await _saveAndDispose(doc);
      final loaded = PdfDocument(inputBytes: bytes);
      addTearDown(loaded.dispose);

      final result = PdfTocExtractor.extractFromBookmarks(loaded);
      expect(result.isNotEmpty, isTrue);
      expect(result.source, PdfTocSource.embeddedBookmarks);
      expect(result.entries.length, 2);

      // Top chapter falls back to first child's page (3) when direct dest is absent
      expect(result.entries[0].title, 'Chapter 1: Foundations');
      expect(result.entries[0].pageNumber, 3);
      expect(result.entries[0].bookmark, isNotNull);
      expect(result.entries[0].children.length, 2);
      expect(result.entries[0].children[0].pageNumber, 3);
      expect(result.entries[0].children[1].pageNumber, 4);

      expect(result.entries[1].title, 'Chapter 2: Conclusion');
      expect(result.entries[1].pageNumber, 2);

      expect(result.topLevelPages, [2, 3]);
      expect(result.chapterTitleForPage(3), '1.1 Background');
      expect(result.chapterTitleForPage(4), '1.2 Core Model');
    });

    test('Tier 2: detects printed TOC page with dot leaders, split columns, and front-matter offset calibration', () async {
      final doc = PdfDocument();
      final fontTitle = PdfStandardFont(PdfFontFamily.helvetica, 18, style: PdfFontStyle.bold);
      final fontBody = PdfStandardFont(PdfFontFamily.helvetica, 11);

      // PDF Page 1: Cover
      doc.pages.add().graphics.drawString(
        'Annual Engineering Report',
        fontTitle,
        bounds: const Rect.fromLTWH(60, 120, 400, 40),
      );

      // PDF Page 2: Printed Table of Contents (numbered in book pages starting after front-matter -> offset +2)
      final tocPage = doc.pages.add();
      tocPage.graphics.drawString(
        'Table of Contents',
        fontTitle,
        bounds: const Rect.fromLTWH(40, 40, 300, 30),
      );
      // Dot leader format
      tocPage.graphics.drawString(
        'Chapter 1: Getting Started ...................... 1',
        fontBody,
        bounds: const Rect.fromLTWH(40, 90, 450, 20),
      );
      // Separate column segments on the same visual row (title on left, page on right)
      tocPage.graphics.drawString(
        '1.1 Environment Setup',
        fontBody,
        bounds: const Rect.fromLTWH(60, 115, 250, 20),
      );
      tocPage.graphics.drawString(
        '2',
        fontBody,
        bounds: const Rect.fromLTWH(470, 115, 30, 20),
      );
      tocPage.graphics.drawString(
        'Chapter 2: System Architecture .................. 3',
        fontBody,
        bounds: const Rect.fromLTWH(40, 140, 450, 20),
      );

      // PDF Page 3 (Printed page 1): Chapter 1
      doc.pages.add().graphics.drawString(
        'Chapter 1: Getting Started',
        fontTitle,
        bounds: const Rect.fromLTWH(40, 50, 420, 30),
      );

      // PDF Page 4 (Printed page 2): 1.1 Environment Setup
      doc.pages.add().graphics.drawString(
        '1.1 Environment Setup',
        fontTitle,
        bounds: const Rect.fromLTWH(40, 50, 420, 30),
      );

      // PDF Page 5 (Printed page 3): Chapter 2
      doc.pages.add().graphics.drawString(
        'Chapter 2: System Architecture',
        fontTitle,
        bounds: const Rect.fromLTWH(40, 50, 420, 30),
      );

      final bytes = await _saveAndDispose(doc);
      final result = PdfTocExtractor.extractFromBytesSync(bytes);

      expect(result.isNotEmpty, isTrue);
      expect(result.source, PdfTocSource.detectedTocPage);
      expect(result.tocPageNumber, 2);

      // Hierarchy: 2 top chapters; 1.1 nested under Chapter 1
      expect(result.entries.length, 2);
      expect(result.entries[0].title, 'Chapter 1: Getting Started');
      expect(result.entries[0].pageNumber, 3); // 1 + 2 offset
      expect(result.entries[0].children.length, 1);
      expect(result.entries[0].children[0].title, '1.1 Environment Setup');
      expect(result.entries[0].children[0].pageNumber, 4); // 2 + 2 offset

      expect(result.entries[1].title, 'Chapter 2: System Architecture');
      expect(result.entries[1].pageNumber, 5); // 3 + 2 offset
    });

    test('Tier 2: detects French Sommaire TOC page', () async {
      final doc = PdfDocument();
      final fontTitle = PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold);
      final fontBody = PdfStandardFont(PdfFontFamily.helvetica, 11);

      final tocPage = doc.pages.add();
      tocPage.graphics.drawString(
        'Sommaire',
        fontTitle,
        bounds: const Rect.fromLTWH(40, 40, 300, 30),
      );
      tocPage.graphics.drawString(
        'Chapitre 1 : Introduction .... 2',
        fontBody,
        bounds: const Rect.fromLTWH(40, 90, 400, 20),
      );
      tocPage.graphics.drawString(
        'Chapitre 2 : Resultats .... 3',
        fontBody,
        bounds: const Rect.fromLTWH(40, 115, 400, 20),
      );

      doc.pages.add().graphics.drawString(
        'Chapitre 1 : Introduction',
        fontTitle,
        bounds: const Rect.fromLTWH(40, 50, 400, 30),
      );
      doc.pages.add().graphics.drawString(
        'Chapitre 2 : Resultats',
        fontTitle,
        bounds: const Rect.fromLTWH(40, 50, 400, 30),
      );

      final bytes = await _saveAndDispose(doc);
      final result = PdfTocExtractor.extractFromBytesSync(bytes);

      expect(result.source, PdfTocSource.detectedTocPage);
      expect(result.entries.length, 2);
      expect(result.entries[0].title, 'Chapitre 1 : Introduction');
      expect(result.entries[0].pageNumber, 2);
      expect(result.entries[1].title, 'Chapitre 2 : Resultats');
      expect(result.entries[1].pageNumber, 3);
    });

    test('Tier 3: detects visual & structural headings while ignoring repeating running headers', () async {
      final doc = PdfDocument();
      final runningHeaderFont = PdfStandardFont(PdfFontFamily.helvetica, 9);
      final chapterFont = PdfStandardFont(PdfFontFamily.helvetica, 20, style: PdfFontStyle.bold);
      final sectionFont = PdfStandardFont(PdfFontFamily.helvetica, 15, style: PdfFontStyle.bold);
      final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 11);

      for (int p = 1; p <= 4; p++) {
        final page = doc.pages.add();
        // Repeating running header & footer on all 4 pages
        page.graphics.drawString(
          'Pagelit Technical Manual',
          runningHeaderFont,
          bounds: const Rect.fromLTWH(40, 16, 300, 16),
        );
        page.graphics.drawString(
          'Page $p',
          runningHeaderFont,
          bounds: const Rect.fromLTWH(260, 800, 80, 16),
        );

        if (p == 1) {
          page.graphics.drawString(
            'Chapter 1: Core Architecture',
            chapterFont,
            bounds: const Rect.fromLTWH(40, 100, 450, 30),
          );
          page.graphics.drawString(
            'This introductory paragraph explains how the rendering pipeline operates across mobile screens.',
            bodyFont,
            bounds: const Rect.fromLTWH(40, 150, 480, 60),
          );
        } else if (p == 2) {
          page.graphics.drawString(
            '1.1 Memory Caching',
            sectionFont,
            bounds: const Rect.fromLTWH(40, 100, 400, 26),
          );
          page.graphics.drawString(
            'Images are decoded at bounded resolution so scrolling remains smooth even on older phones.',
            bodyFont,
            bounds: const Rect.fromLTWH(40, 145, 480, 60),
          );
        } else if (p == 3) {
          page.graphics.drawString(
            'Chapitre 2 : Performance',
            chapterFont,
            bounds: const Rect.fromLTWH(40, 100, 450, 30),
          );
          page.graphics.drawString(
            'Les calculs lourds sont executes en arriere-plan pour eviter les blocages de l interface.',
            bodyFont,
            bounds: const Rect.fromLTWH(40, 150, 480, 60),
          );
        } else {
          page.graphics.drawString(
            'Normal prose continuation that must not appear as a separate chapter heading in the outline.',
            bodyFont,
            bounds: const Rect.fromLTWH(40, 100, 480, 60),
          );
        }
      }

      final bytes = await _saveAndDispose(doc);
      final result = PdfTocExtractor.extractFromBytesSync(bytes);

      expect(result.isNotEmpty, isTrue);
      expect(result.source, PdfTocSource.detectedHeadings);

      final flatTitles = result.flattened.map((e) => e.title).toList();
      expect(flatTitles, isNot(contains('Pagelit Technical Manual')));
      expect(flatTitles, contains('Chapter 1: Core Architecture'));
      expect(flatTitles, contains('1.1 Memory Caching'));
      expect(flatTitles, contains('Chapitre 2 : Performance'));

      expect(result.entries.length, 2);
      expect(result.entries[0].title, 'Chapter 1: Core Architecture');
      expect(result.entries[0].pageNumber, 1);
      expect(result.entries[0].children.first.title, '1.1 Memory Caching');
      expect(result.entries[0].children.first.pageNumber, 2);
      expect(result.entries[1].title, 'Chapitre 2 : Performance');
      expect(result.entries[1].pageNumber, 3);
    });

    test('Tier 3: detects slide titles in landscape presentation PDFs', () async {
      final doc = PdfDocument();
      doc.pageSettings.orientation = PdfPageOrientation.landscape;
      doc.pageSettings.size = const Size(842, 595);

      final titleFont = PdfStandardFont(PdfFontFamily.helvetica, 26, style: PdfFontStyle.bold);
      final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 14);

      final titles = ['Quarterly Roadmap', 'Performance Gains', 'Next Milestones'];
      for (final title in titles) {
        final page = doc.pages.add();
        page.graphics.drawString(
          title,
          titleFont,
          bounds: const Rect.fromLTWH(50, 45, 700, 45),
        );
        page.graphics.drawString(
          'Supporting bullet details for $title presented during the team sync.',
          bodyFont,
          bounds: const Rect.fromLTWH(50, 220, 700, 80),
        );
      }

      final bytes = await _saveAndDispose(doc);
      final result = PdfTocExtractor.extractFromBytesSync(bytes);

      expect(result.isNotEmpty, isTrue);
      expect(result.source, PdfTocSource.slideTitles);
      expect(result.entries.length, 3);
      expect(result.entries[0].title, 'Quarterly Roadmap');
      expect(result.entries[0].pageNumber, 1);
      expect(result.entries[1].title, 'Performance Gains');
      expect(result.entries[1].pageNumber, 2);
      expect(result.entries[2].title, 'Next Milestones');
      expect(result.entries[2].pageNumber, 3);
    });
  });
}
