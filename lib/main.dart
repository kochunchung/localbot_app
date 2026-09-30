import 'package:flutter/material.dart';
import 'screens/chat_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LocalBotApp());
}

class LocalBotApp extends StatelessWidget {
  const LocalBotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LocalBot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00B900), // LINE official green
          primary: const Color(0xFF00B900),
        ),
        useMaterial3: true,
        fontFamily: 'sans-serif',
      ),
      home: const ChatScreen(),
    );
  }
}
