import 'tool_safety.dart';
import 'tool_spec.dart';

/// The tools from docs/HARNESS.md. `GET /tools` serves this list, minus the
/// ones this machine cannot do, so the LLM never sees a tool that would fail.
abstract final class ToolCatalog {
  static const openApp = ToolSpec(
    name: 'open_app',
    description: 'Open an installed application by name',
    safety: ToolSafety.safe,
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'name': <String, dynamic>{
          'type': 'string',
          'description': 'Application name, for example spotify',
        },
      },
      'required': <String>['name'],
    },
  );

  static const lockPc = ToolSpec(
    name: 'lock_pc',
    description: 'Lock the workstation',
    safety: ToolSafety.confirm,
  );

  static const systemStats = ToolSpec(
    name: 'system_stats',
    description: 'CPU, RAM, GPU usage and temperatures',
    safety: ToolSafety.safe,
  );

  static const screenshot = ToolSpec(
    name: 'screenshot',
    description: 'Take a screenshot and describe it',
    safety: ToolSafety.confirm,
  );

  static const searchFiles = ToolSpec(
    name: 'search_files',
    description: 'Find files by name in Documents, Downloads and Desktop',
    safety: ToolSafety.confirm,
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'query': <String, dynamic>{
          'type': 'string',
          'description': 'Part of the file name to look for',
        },
      },
      'required': <String>['query'],
    },
  );

  static const media = ToolSpec(
    name: 'media',
    description:
        'Control what is playing in any app, through Windows: play, pause, '
        'next, previous, or status to hear what is playing and whether it is '
        'paused; also volume up, volume down, mute',
    safety: ToolSafety.safe,
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'action': <String, dynamic>{
          'type': 'string',
          'enum': <String>[
            'play',
            'pause',
            'play_pause',
            'status',
            'next',
            'previous',
            'volume_up',
            'volume_down',
            'mute',
          ],
        },
      },
      'required': <String>['action'],
    },
  );

  static const agentTask = ToolSpec(
    name: 'agent_task',
    description:
        'Hand a multi-step task to the PC agent. Use for anything not '
        'covered by the other tools.',
    safety: ToolSafety.always,
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'task': <String, dynamic>{
          'type': 'string',
          'description': 'The task in plain language',
        },
      },
      'required': <String>['task'],
    },
  );

  static const openLink = ToolSpec(
    name: 'open_link',
    description:
        'Open a web address, a file, or an app link. App links act inside '
        'the app: spotify:track:<id> plays that song in Spotify, '
        'spotify:search:<words> searches Spotify, ms-settings:bluetooth opens '
        'a Settings page, mailto: starts an email.',
    safety: ToolSafety.safe,
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'target': <String, dynamic>{
          'type': 'string',
          'description': 'The address, path or app link',
        },
      },
      'required': <String>['target'],
    },
  );

  static const closeApp = ToolSpec(
    name: 'close_app',
    description:
        'Close an app by name, the way its own close button does, so an app '
        'with unsaved work still asks. Use this to close anything; never '
        'press keys to close an app.',
    safety: ToolSafety.safe,
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'name': <String, dynamic>{
          'type': 'string',
          'description': 'The app, like Spotify or Chrome',
        },
      },
      'required': <String>['name'],
    },
  );

  static const focusApp = ToolSpec(
    name: 'focus_app',
    description: 'Bring an open app to the front, before pressing keys in it',
    safety: ToolSafety.safe,
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'name': <String, dynamic>{
          'type': 'string',
          'description': 'App name or part of its window title',
        },
      },
      'required': <String>['name'],
    },
  );

  static const uiLook = ToolSpec(
    name: 'ui_look',
    description:
        'See what an open app offers: its buttons, text fields, list items, '
        'links, tabs and menu items by name, through Windows UI Automation. '
        'Use it before ui_act for any app you have no shortcut for, and again '
        'after acting to see what changed. Controls are listed in the '
        'window\'s order. A "Row:" line gives the text of a list row, such '
        'as a song with its artist and length, before the buttons in it; a '
        'name that repeats is numbered, "Play Blinding Lights #2".',
    safety: ToolSafety.safe,
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'app': <String, dynamic>{
          'type': 'string',
          'description': 'The app, like Spotify, Chrome or Settings',
        },
      },
      'required': <String>['app'],
    },
  );

  static const uiAct = ToolSpec(
    name: 'ui_act',
    description:
        'Work any control ui_look showed: "click" a button, list item, link '
        'or tab, "type" text into a field, or "focus" it. Name the control as '
        'ui_look wrote it.',
    safety: ToolSafety.confirm,
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'app': <String, dynamic>{'type': 'string'},
        'control': <String, dynamic>{
          'type': 'string',
          'description':
              'The control name as ui_look showed it, with its #number when '
              'it has one',
        },
        'action': <String, dynamic>{
          'type': 'string',
          'enum': <String>['click', 'type', 'focus'],
        },
        'text': <String, dynamic>{
          'type': 'string',
          'description': 'For type: what to type',
        },
      },
      'required': <String>['app', 'control', 'action'],
    },
  );

  static const runPowerShell = ToolSpec(
    name: 'run_powershell',
    description:
        'Run a PowerShell command on this PC, for anything no other tool '
        'does: system settings, files, processes, volume, network, installed '
        'apps. Returns what it printed. Keep commands short and safe; never '
        'delete or format anything the user did not ask for.',
    safety: ToolSafety.confirm,
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'command': <String, dynamic>{'type': 'string'},
      },
      'required': <String>['command'],
    },
  );

  static const pressKeys = ToolSpec(
    name: 'press_keys',
    description:
        'Press keys in the app in front, for example "space" to play or '
        'pause, "ctrl+l", "enter", "ctrl+shift+t"; several separated by commas',
    safety: ToolSafety.confirm,
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'keys': <String, dynamic>{'type': 'string'},
      },
      'required': <String>['keys'],
    },
  );

  static const typeText = ToolSpec(
    name: 'type_text',
    description:
        'Type text, in any language, into an app: brought to the front '
        'first when named, otherwise the app in front',
    safety: ToolSafety.confirm,
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'text': <String, dynamic>{'type': 'string'},
        'app': <String, dynamic>{
          'type': 'string',
          'description': 'The app to type into, like Notepad',
        },
      },
      'required': <String>['text'],
    },
  );

  static const openWindows = ToolSpec(
    name: 'open_windows',
    description: 'List the apps that have a window open and what each shows',
    safety: ToolSafety.safe,
  );

  static const native = <ToolSpec>[
    openApp,
    lockPc,
    systemStats,
    screenshot,
    searchFiles,
    media,
  ];

  /// Real control of any app, where the OS allows it (DesktopControl).
  static const control = <ToolSpec>[
    openLink,
    closeApp,
    focusApp,
    uiLook,
    uiAct,
    runPowerShell,
    pressKeys,
    typeText,
    openWindows,
  ];

  static const all = <ToolSpec>[...native, ...control, agentTask];

  static ToolSpec? byName(String name) =>
      all.where((t) => t.name == name).firstOrNull;

  /// What this machine can offer right now.
  static List<ToolSpec> available({
    required bool hasNativeTools,
    required bool hasAgent,
    bool hasControl = false,
  }) => <ToolSpec>[
    if (hasNativeTools) ...native,
    if (hasControl) ...control,
    if (hasAgent) agentTask,
  ];
}
