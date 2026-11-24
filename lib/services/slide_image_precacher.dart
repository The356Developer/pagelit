import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'presentation_parser.dart';

/// Pre-decodes slide background and picture textures into Flutter's GPU
/// [ImageCache] ahead of slide transitions so 1080p/4K projector transitions
/// never hitch on first frame.
class SlideImagePrecacher {
  const SlideImagePrecacher._();

  static void precacheAround(
    BuildContext context,
    PresentationDeck deck,
    int centerIndex, {
    int lookBehind = 1,
    int lookAhead = 2,
  }) {
    if (deck.slides.isEmpty) return;
    final start = (centerIndex - lookBehind).clamp(0, deck.slides.length - 1);
    final end = (centerIndex + lookAhead).clamp(0, deck.slides.length - 1);

    final seenBuffers = <Uint8List>{};
    for (int i = start; i <= end; i++) {
      final slide = deck.slides[i];
      final bg = slide.backgroundImage;
      if (bg != null && seenBuffers.add(bg)) {
        precacheImage(MemoryImage(bg), context).ignore();
      }
      for (final elem in slide.elements) {
        if (elem is SlidePictureElement && seenBuffers.add(elem.imageBytes)) {
          precacheImage(MemoryImage(elem.imageBytes), context).ignore();
        }
      }
    }
  }
}
