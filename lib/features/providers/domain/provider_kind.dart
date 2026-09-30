import 'package:json_annotation/json_annotation.dart';

@JsonEnum(fieldRename: FieldRename.snake)
enum ProviderKind {
  openai,
  anthropic,
  deepinfra,
  groq,
  openrouter,
  ollama,
  custom,
}
