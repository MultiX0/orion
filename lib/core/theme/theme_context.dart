import 'package:flutter/material.dart';

import 'orion_text.dart';

extension OrionThemeContext on BuildContext {
  OrionText get text =>
      Theme.of(this).extension<OrionText>() ?? OrionText.standard;
}
