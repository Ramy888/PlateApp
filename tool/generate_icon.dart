// Generates the PlatePatch app icon set. Run with:
//   dart run tool/generate_icon.dart
//
// The mark is a plate with one thing being added to it — the whole product in
// a single shape. Drawn in code so it can be regenerated at any size without
// a design tool in the loop.
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const _green = 0xFF4F6B2E; // ABGR for package:image (0xAABBGGRR)
const _cream = 0xFFF0F7FB;
const _amber = 0xFF3DA3E8;
const _ink = 0xFF20241F;

void main() {
  Directory('assets/icon').createSync(recursive: true);

  _write('assets/icon/icon.png', _draw(size: 1024, background: _green));
  // Adaptive icons crop to a circle, so the foreground is drawn small enough
  // to survive the mask and the background layer is a flat colour.
  _write('assets/icon/icon_foreground.png',
      _draw(size: 1024, background: null, scale: 0.62));
  _write('assets/icon/icon_monochrome.png',
      _draw(size: 1024, background: null, scale: 0.62, monochrome: true));

  stdout.writeln('Wrote assets/icon/*.png');
}

void _write(String path, img.Image image) =>
    File(path).writeAsBytesSync(img.encodePng(image));

img.Image _draw({
  required int size,
  int? background,
  double scale = 1.0,
  bool monochrome = false,
}) {
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  if (background != null) {
    img.fill(canvas, color: _color(canvas, background));
  }

  final plateFill = monochrome ? _ink : _cream;
  final rimColor = monochrome ? _cream : (background == null ? _ink : _green);
  final patchFill = monochrome ? _ink : _amber;

  // The mark is wider up-and-right than down-and-left, so the drawing origin
  // is nudged to put the *composition* in the centre, not the plate.
  final unit = size * scale;
  final c = size / 2 - unit * 0.044;

  // The plate, sitting slightly low so the added item has room above it.
  final plateR = unit * 0.30;
  final plateY = size / 2 + unit * 0.026;
  img.fillCircle(canvas,
      x: c.round(), y: plateY.round(), radius: plateR.round(),
      color: _color(canvas, plateFill), antialias: true);

  // The rim, cut as a ring by redrawing the inner disc in the plate colour.
  final rimR = plateR * 0.70;
  img.fillCircle(canvas,
      x: c.round(), y: plateY.round(), radius: (rimR + unit * 0.012).round(),
      color: _color(canvas, rimColor), antialias: true);
  img.fillCircle(canvas,
      x: c.round(), y: plateY.round(), radius: rimR.round(),
      color: _color(canvas, plateFill), antialias: true);

  // The addition: one item arriving at the edge of the plate.
  final patchR = unit * 0.155;
  final patchX = c + unit * 0.215;
  final patchY = plateY - unit * 0.245;
  if (background != null) {
    // A halo in the background colour keeps the two shapes readable when they
    // overlap, without needing a stroke.
    img.fillCircle(canvas,
        x: patchX.round(), y: patchY.round(),
        radius: (patchR + unit * 0.028).round(),
        color: _color(canvas, background), antialias: true);
  }
  img.fillCircle(canvas,
      x: patchX.round(), y: patchY.round(), radius: patchR.round(),
      color: _color(canvas, patchFill), antialias: true);

  // The plus inside it.
  final arm = patchR * 0.52;
  final thick = patchR * 0.20;
  final plusColor = _color(canvas, monochrome ? _cream : _cream);
  _bar(canvas, patchX, patchY, arm, thick, plusColor, horizontal: true);
  _bar(canvas, patchX, patchY, arm, thick, plusColor, horizontal: false);

  return canvas;
}

void _bar(
  img.Image canvas,
  double cx,
  double cy,
  double arm,
  double thick,
  img.Color color, {
  required bool horizontal,
}) {
  final halfLong = arm;
  final halfShort = thick;
  final x1 = cx - (horizontal ? halfLong : halfShort);
  final x2 = cx + (horizontal ? halfLong : halfShort);
  final y1 = cy - (horizontal ? halfShort : halfLong);
  final y2 = cy + (horizontal ? halfShort : halfLong);
  img.fillRect(canvas,
      x1: x1.round(), y1: y1.round(), x2: x2.round(), y2: y2.round(),
      radius: math.min(halfShort, halfLong) * 0.8,
      color: color);
}

img.Color _color(img.Image image, int abgr) => img.ColorRgba8(
      abgr & 0xFF,
      (abgr >> 8) & 0xFF,
      (abgr >> 16) & 0xFF,
      (abgr >> 24) & 0xFF,
    );
