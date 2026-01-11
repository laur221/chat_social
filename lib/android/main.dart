import 'package:flutter/material.dart';

class MobileHome extends StatelessWidget {
  const MobileHome({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Aceasta este versiunea pentru Telefon',
        style: TextStyle(fontSize: 18),
      ),
    );
  }
}