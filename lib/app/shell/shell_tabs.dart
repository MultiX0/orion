import 'package:flutter/material.dart';

/// One nav destination. Both the bottom bar and the rail read this list.
class ShellTab {
  const ShellTab(this.label, this.path, this.icon, this.activeIcon);

  final String label;
  final String path;
  final IconData icon;
  final IconData activeIcon;

  bool matches(String location) =>
      path == '/' ? location == '/' : location.startsWith(path);
}

abstract final class ShellTabs {
  static const home = ShellTab('Home', '/', Icons.blur_on, Icons.blur_on);
  static const talk = ShellTab('Talk', '/talk', Icons.mic_none, Icons.mic);
  static const camera = ShellTab(
    'Camera',
    '/camera',
    Icons.camera_alt_outlined,
    Icons.camera_alt,
  );
  static const conversation = ShellTab(
    'Conversation',
    '/conversation',
    Icons.forum_outlined,
    Icons.forum,
  );
  static const providers = ShellTab(
    'Providers',
    '/providers',
    Icons.hub_outlined,
    Icons.hub,
  );
  static const settings = ShellTab(
    'Settings',
    '/settings',
    Icons.tune,
    Icons.tune,
  );
  static const harness = ShellTab(
    'Harness',
    '/harness',
    Icons.terminal,
    Icons.terminal,
  );

  static const mobile = [home, talk, camera, conversation];
  static const more = [providers, settings];
  static const desktop = [
    home,
    talk,
    camera,
    conversation,
    providers,
    settings,
  ];

  static int indexFor(List<ShellTab> tabs, String location) {
    final i = tabs.indexWhere((t) => t.matches(location));
    return i < 0 ? -1 : i;
  }
}
