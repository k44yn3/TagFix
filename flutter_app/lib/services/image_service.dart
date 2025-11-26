import 'dart:typed_data';
import 'package:image/image.dart' as img;

class ImageService {
  Future<List<int>?> resizeImage(List<int> imageBytes, {int width = 500, int height = 500}) async {
    try {
      final image = img.decodeImage(Uint8List.fromList(imageBytes));
      if (image == null) return null;

      final size = image.width < image.height ? image.width : image.height;
      final x = (image.width - size) ~/ 2;
      final y = (image.height - size) ~/ 2;
      
      final cropped = img.copyCrop(image, 
        x: x,
        y: y,
        width: size,
        height: size,
      );

      final resized = img.copyResize(cropped, width: width, height: height);

      return img.encodeJpg(resized);
    } catch (e) {
      print('Error resizing image: $e');
      return null;
    }
  }
}
