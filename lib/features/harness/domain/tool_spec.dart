import 'tool_safety.dart';

/// One tool the board may call. `parameters` is a JSON Schema object, exactly
/// as the OpenAI function-calling format wants it.
class ToolSpec {
  const ToolSpec({
    required this.name,
    required this.description,
    required this.safety,
    this.parameters = const <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{},
    },
  });

  final String name;
  final String description;
  final ToolSafety safety;
  final Map<String, dynamic> parameters;

  Map<String, dynamic> toFunctionJson() => <String, dynamic>{
    'type': 'function',
    'function': <String, dynamic>{
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };
}
