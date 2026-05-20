import 'package:flutter/material.dart';

void main() {
  runApp(const MoproApp());
}

class MoproApp extends StatelessWidget {
  const MoproApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Center(child: Text('Mopro'))),
    );
  }
}
