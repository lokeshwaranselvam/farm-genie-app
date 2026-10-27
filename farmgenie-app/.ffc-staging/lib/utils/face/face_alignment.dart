import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

/// Image-space coordinates, independent of ML Kit's person-left labels.
class FacePoint {
  final double x;
  final double y;

  const FacePoint(this.x, this.y);
}

/// A nonreflecting least-squares similarity transform from source to target.
class FaceSimilarityTransform {
  final double a;
  final double b;
  final double tx;
  final double ty;

  const FaceSimilarityTransform(this.a, this.b, this.tx, this.ty);

  factory FaceSimilarityTransform.fit(
    List<FacePoint> source,
    List<FacePoint> target,
  ) {
    if (source.length != target.length || source.length < 2) {
      throw ArgumentError('Matching source and target landmarks are required.');
    }
    for (final point in [...source, ...target]) {
      if (!point.x.isFinite || !point.y.isFinite) {
        throw ArgumentError('Face landmarks must contain finite coordinates.');
      }
    }
    final count = source.length;
    final sourceX =
        source.fold<double>(0, (sum, point) => sum + point.x) / count;
    final sourceY =
        source.fold<double>(0, (sum, point) => sum + point.y) / count;
    final targetX =
        target.fold<double>(0, (sum, point) => sum + point.x) / count;
    final targetY =
        target.fold<double>(0, (sum, point) => sum + point.y) / count;
    var denominator = 0.0;
    var aNumerator = 0.0;
    var bNumerator = 0.0;
    for (var index = 0; index < count; index++) {
      final sx = source[index].x - sourceX;
      final sy = source[index].y - sourceY;
      final dx = target[index].x - targetX;
      final dy = target[index].y - targetY;
      denominator += sx * sx + sy * sy;
      aNumerator += sx * dx + sy * dy;
      bNumerator += sx * dy - sy * dx;
    }
    if (denominator < 1e-8) {
      throw ArgumentError('Face landmarks must be separated.');
    }
    final a = aNumerator / denominator;
    final b = bNumerator / denominator;
    if (!a.isFinite || !b.isFinite || a * a + b * b < 1e-8) {
      throw ArgumentError('Face landmarks cannot form a valid alignment.');
    }
    return FaceSimilarityTransform(
      a,
      b,
      targetX - a * sourceX + b * sourceY,
      targetY - b * sourceX - a * sourceY,
    );
  }

  FacePoint apply(FacePoint source) => FacePoint(
    a * source.x - b * source.y + tx,
    b * source.x + a * source.y + ty,
  );

  FacePoint inverse(FacePoint target) {
    final determinant = a * a + b * b;
    if (!determinant.isFinite || determinant < 1e-8) {
      throw ArgumentError('The face alignment is not invertible.');
    }
    final dx = target.x - tx;
    final dy = target.y - ty;
    return FacePoint(
      (a * dx + b * dy) / determinant,
      (-b * dx + a * dy) / determinant,
    );
  }
}

class FaceAlignment {
  static const int side = 112;
  static const List<FacePoint> sfaceReferencePoints = [
    FacePoint(38.2946, 51.6963),
    FacePoint(73.5318, 51.5014),
    FacePoint(56.0252, 71.7366),
    FacePoint(41.5493, 92.3655),
    FacePoint(70.7299, 92.2041),
  ];

  /// Tightly packed 8-bit RGB bytes, row stride `width * 3`. A decoded JPEG
  /// is already in this layout, so the common path reads it without copying.
  static Uint8List rgbBytes(image.Image source) {
    final rgb = source.format == image.Format.uint8 && !source.hasPalette
        ? source
        : source.convert(format: image.Format.uint8, numChannels: 3);
    final bytes = rgb.getBytes(order: image.ChannelOrder.rgb);
    if (bytes.length < rgb.width * rgb.height * 3) {
      throw ArgumentError('The face image has an unsupported pixel layout.');
    }
    return bytes;
  }

  /// [landmarks] order: image-left eye, image-right eye, nose, image-left
  /// mouth corner, image-right mouth corner. Source must already be upright.
  static image.Image align(image.Image source, List<FacePoint> landmarks) =>
      alignRgb(
        rgbBytes(source),
        source.width,
        source.height,
        landmarks,
      );

  /// [align] over packed RGB bytes (see [rgbBytes]) of a [width] by [height]
  /// upright image. Reading bytes directly avoids per-tap pixel objects.
  static image.Image alignRgb(
    Uint8List rgb,
    int width,
    int height,
    List<FacePoint> landmarks,
  ) {
    if (landmarks.length != 5) {
      throw ArgumentError('Five face landmarks are required.');
    }
    if (width <= 0 || height <= 0 || rgb.length < width * height * 3) {
      throw ArgumentError('The face image pixels do not match its size.');
    }
    final transform = FaceSimilarityTransform.fit(
      landmarks,
      sfaceReferencePoints,
    );
    final aligned = image.Image(width: side, height: side);
    // Inverse warp avoids holes. Match OpenCV's bilinear/black-border behavior.
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final point = transform.inverse(FacePoint(x.toDouble(), y.toDouble()));
        final x0 = point.x.floor();
        final y0 = point.y.floor();
        final fx = point.x - x0;
        final fy = point.y - y0;
        var red = 0.0;
        var green = 0.0;
        var blue = 0.0;
        // Out-of-image taps contribute black, as before.
        void tap(int sx, int sy, double weight) {
          if (sx < 0 || sy < 0 || sx >= width || sy >= height) return;
          final offset = (sy * width + sx) * 3;
          red += rgb[offset] * weight;
          green += rgb[offset + 1] * weight;
          blue += rgb[offset + 2] * weight;
        }

        tap(x0, y0, (1 - fx) * (1 - fy));
        tap(x0 + 1, y0, fx * (1 - fy));
        tap(x0, y0 + 1, (1 - fx) * fy);
        tap(x0 + 1, y0 + 1, fx * fy);
        aligned.setPixelRgb(
          x,
          y,
          red.round().clamp(0, 255),
          green.round().clamp(0, 255),
          blue.round().clamp(0, 255),
        );
      }
    }
    return aligned;
  }

  /// SFace's ONNX graph performs its own normalization. Supply RGB 0..255,
  /// channel first, as float32; external division by 255 would be incorrect.
  static Float32List rgbNchw(image.Image aligned) {
    if (aligned.width != side || aligned.height != side) {
      throw ArgumentError('SFace requires an aligned 112 by 112 image.');
    }
    final rgb = rgbBytes(aligned);
    const planeSize = side * side;
    final result = Float32List(3 * planeSize);
    for (var index = 0; index < planeSize; index++) {
      result[index] = rgb[index * 3].toDouble();
      result[planeSize + index] = rgb[index * 3 + 1].toDouble();
      result[2 * planeSize + index] = rgb[index * 3 + 2].toDouble();
    }
    return result;
  }

  static List<double> normalizeEmbedding(List<double> values) {
    if (values.isEmpty || values.any((value) => !value.isFinite)) {
      throw ArgumentError('Face embeddings must contain finite values.');
    }
    final norm = math.sqrt(
      values.fold<double>(0, (sum, value) => sum + value * value),
    );
    if (!norm.isFinite || norm < 1e-12) {
      throw ArgumentError('Face embedding has no usable magnitude.');
    }
    return List<double>.unmodifiable(values.map((value) => value / norm));
  }

  static double cosineSimilarity(List<double> first, List<double> second) {
    if (first.length != second.length || first.isEmpty) {
      throw ArgumentError('Face embeddings must have matching dimensions.');
    }
    final a = normalizeEmbedding(first);
    final b = normalizeEmbedding(second);
    var score = 0.0;
    for (var index = 0; index < a.length; index++) {
      score += a[index] * b[index];
    }
    return score.clamp(-1.0, 1.0);
  }
}
