import 'package:flutter/material.dart';

import '../../app/strings.dart';

class FirstStepField extends StatelessWidget {
  const FirstStepField({
    required this.controller,
    this.autofocus = false,
    this.trailing,
    super.key,
  });

  final TextEditingController controller;
  final bool autofocus;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    maxLength: 80,
    decoration: InputDecoration(
      labelText: S.fieldFirstStep,
      counterText: '',
      suffixIcon: trailing,
      border: const OutlineInputBorder(),
      isDense: true,
    ),
  );
}
