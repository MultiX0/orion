import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

/// The bundled JPEGs the fake camera loops through.
class FrameStore {
  FrameStore(this.frames);

  /// Reads every .jpg in a folder, sorted by name so the loop is stable.
  factory FrameStore.fromDirectory(Directory dir) {
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.jpg'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    return FrameStore([for (final f in files) f.readAsBytesSync()]);
  }

  final List<Uint8List> frames;

  bool get isEmpty => frames.isEmpty;
  Uint8List at(int index) => frames[index % frames.length];
}

/// GET /stream and GET /capture. The board allows one stream client, so a
/// second connection gets 409 like the real one.
class MockCamera {
  MockCamera(this.store, {this.fps = 10});

  final FrameStore store;
  final int fps;
  var _streaming = false;
  var _sequence = 0;

  static const boundary = 'frame';

  Response capture() {
    if (store.isEmpty) return _noFrames();
    final bytes = store.at(_sequence++);
    return Response.ok(
      bytes,
      headers: <String, String>{
        'content-type': 'image/jpeg',
        'cache-control': 'no-store',
      },
    );
  }

  Response stream() {
    if (store.isEmpty) return _noFrames();
    if (_streaming) {
      return Response(
        409,
        body: '{"error":"busy","message":"The camera already has a viewer"}',
        headers: const <String, String>{'content-type': 'application/json'},
      );
    }
    _streaming = true;
    final controller = StreamController<List<int>>();
    final gap = Duration(milliseconds: (1000 / fps).round());
    var index = 0;
    final timer = Timer.periodic(gap, (_) {
      if (controller.isClosed) return;
      controller.add(_part(store.at(index++)));
    });
    controller.onCancel = () {
      timer.cancel();
      _streaming = false;
    };
    return Response.ok(
      controller.stream,
      headers: <String, String>{
        'content-type': 'multipart/x-mixed-replace; boundary=$boundary',
        'cache-control': 'no-store',
      },
      context: const <String, Object>{'shelf.io.buffer_output': false},
    );
  }

  List<int> _part(Uint8List jpeg) => <int>[
    ...'--$boundary\r\n'.codeUnits,
    ...'content-type: image/jpeg\r\n'.codeUnits,
    ...'content-length: ${jpeg.length}\r\n\r\n'.codeUnits,
    ...jpeg,
    ...'\r\n'.codeUnits,
  ];

  Response _noFrames() => Response.internalServerError(
    body: '{"error":"no_frames","message":"No JPEGs in the frames folder"}',
    headers: const <String, String>{'content-type': 'application/json'},
  );
}
