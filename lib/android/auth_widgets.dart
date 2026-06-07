import 'package:flutter/material.dart';

InputDecoration authInputDecoration({
  required String label,
  required IconData icon,
}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFE4E8F2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFFF6B5F), width: 1.5),
    ),
  );
}

class ErrorPanel extends StatelessWidget {
  final String message;

  const ErrorPanel({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE9E9),
        border: Border.all(color: const Color(0xFFFFC4C4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        message,
        style: const TextStyle(fontSize: 12, color: Color(0xFF8A1F1F)),
      ),
    );
  }
}
