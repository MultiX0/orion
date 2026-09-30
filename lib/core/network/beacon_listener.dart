import 'dart:async';
import 'dart:io';

import 'beacon.dart';

/// Listens for board beacons on UDP 7332. A port already taken or a firewall
/// that says no is silence, the same way mDNS is: the other three discovery
/// sources still run.
class BeaconListener {
  BeaconListener({this.port = BeaconPacket.udpPort});

  final int port;

  Stream<BeaconPacket> listen() {
    RawDatagramSocket? socket;
    late final StreamController<BeaconPacket> out;

    Future<void> close() async {
      socket?.close();
      socket = null;
      if (!out.isClosed) await out.close();
    }

    out = StreamController<BeaconPacket>(
      onListen: () async {
        final RawDatagramSocket bound;
        try {
          bound = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            port,
            reuseAddress: true,
          );
        } on SocketException {
          await close();
          return;
        }
        socket = bound;
        bound.broadcastEnabled = true;
        bound.listen(
          (event) {
            if (event != RawSocketEvent.read) return;
            final datagram = bound.receive();
            if (datagram == null) return;
            final packet = BeaconPacket.parse(datagram.data);
            if (packet != null && !out.isClosed) out.add(packet);
          },
          onError: (Object _) {},
          cancelOnError: false,
        );
      },
      onCancel: close,
    );
    return out.stream;
  }
}
