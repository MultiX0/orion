/// Whether a tool runs on arrival or waits for the user.
enum ToolSafety {
  /// Runs immediately. Nothing here can lose data or leak the screen.
  safe,

  /// Needs an approval the first time this session.
  confirm,

  /// Needs an approval every single time. Only agent_task.
  always,
}
