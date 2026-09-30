/// REST and WebSocket paths from docs/DEVICE_PROTOCOL.md. The client and
/// the mock device both read from here so they cannot drift apart.
abstract final class ApiPaths {
  static const info = '/api/info';
  static const state = '/api/state';
  static const config = '/api/config';
  static const talk = '/api/talk';
  static const talkSnapshot = '/api/talk/snapshot';
  static const say = '/api/say';
  static const stop = '/api/stop';
  static const history = '/api/history';
  static const restart = '/api/restart';
  static const provision = '/api/provision';
  static const pair = '/api/pair';
  static const capture = '/capture';
  static const stream = '/stream';
  static const ws = '/ws';

  static const tokenHeader = 'X-Orion-Token';
  static const mdnsService = '_orion._tcp.local';
  static const defaultPort = 80;
  static const mockPort = 8080;
  static const harnessPort = 7331;
}
