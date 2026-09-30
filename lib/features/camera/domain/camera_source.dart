import '../../../core/result.dart';
import 'camera_frame.dart';

/// Live frames and single captures from the board camera.
abstract class CameraSource {
  /// Opens the MJPEG stream on listen and closes it on cancel. The board
  /// allows one client, so only the visible camera view should listen.
  Stream<CameraFrame> frames();

  Future<Result<CameraFrame>> capture();

  /// Writes the frame as a JPEG and returns the path.
  Future<Result<String>> saveSnapshot(CameraFrame frame);
}
