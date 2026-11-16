import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../color/sampling.dart';

class LoadedPhoto {
  final RgbRaster raster;

  /// The same pixels re-encoded as JPEG, upright. We display (and archive)
  /// this version so screen taps map 1:1 to [raster] pixel coordinates.
  final Uint8List jpeg;
  LoadedPhoto(this.raster, this.jpeg);
}

/// Longest side after downscaling. A 2000 px image still has thousands of
/// pixels on the pad, which is plenty for averaging, and is far quicker to
/// process than a full 12 MP frame.
const int maxPhotoDimension = 2000;

/// Decodes, rotates upright (EXIF orientation), downsizes and converts the
/// photo. Runs in a background isolate so the UI stays responsive.
Future<LoadedPhoto> loadPhoto(String path) => Isolate.run(() {
      final bytes = File(path).readAsBytesSync();
      var image = img.decodeImage(bytes);
      if (image == null) throw const FormatException('Unsupported image');
      image = img.bakeOrientation(image);
      final longest = image.width > image.height ? image.width : image.height;
      if (longest > maxPhotoDimension) {
        // Averaging interpolation in linear light: each output pixel is the
        // physically correct mix of the input pixels it covers.
        image = img.copyResize(image,
            width: image.width >= image.height ? maxPhotoDimension : null,
            height: image.height > image.width ? maxPhotoDimension : null,
            interpolation: img.Interpolation.average,
            linearBlend: true);
      }
      final rgb = image.convert(format: img.Format.uint8, numChannels: 3);
      final data = Uint8List.fromList(rgb.getBytes(order: img.ChannelOrder.rgb));
      final jpeg = img.encodeJpg(rgb, quality: 95);
      return LoadedPhoto(RgbRaster(rgb.width, rgb.height, data), jpeg);
    });
