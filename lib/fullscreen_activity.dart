import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 全屏提醒 Activity（独立页面，锁屏/后台时由原生启动）
class FullScreenReminderActivity extends StatefulWidget {
  const FullScreenReminderActivity({super.key});

  @override
  State<FullScreenReminderActivity> createState() =>
      _FullScreenReminderActivityState();
}

class _FullScreenReminderActivityState
    extends State<FullScreenReminderActivity> {
  final Random _rng = Random();
  Timer? _autoCloseTimer;

  String _line1 = '';
  String _line2 = '';

  late Color _color1;
  late Color _color2;
  late double _fontSize1;
  late double _fontSize2;
  late Alignment _align1;
  late Alignment _align2;

  final List<Color> _palette = [
    Colors.white,
    Colors.yellowAccent,
    Colors.cyanAccent,
    Colors.pinkAccent,
    Colors.lightGreenAccent,
    Colors.orangeAccent,
    Colors.tealAccent,
    Colors.purpleAccent,
  ];

  @override
  void initState() {
    super.initState();
    _loadLinesAndShow();

    // 5秒后自动关闭
    _autoCloseTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemNavigator.pop();
      }
    });
  }

  Future<void> _loadLinesAndShow() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _line1 = p.getString('line1') ?? '记得喝水 💧';
        _line2 = p.getString('line2') ?? '站起来活动一下 🚶';
        
        _color1 = _palette[_rng.nextInt(_palette.length)];
        _color2 = _palette[_rng.nextInt(_palette.length)];
        _fontSize1 = 22 + _rng.nextDouble() * 20;
        _fontSize2 = 22 + _rng.nextDouble() * 20;
        _align1 = _randomAlignment();
        _align2 = _randomAlignment();
      });
    }
  }

  Alignment _randomAlignment() {
    final x = (_rng.nextDouble() * 1.6) - 0.8;
    final y = (_rng.nextDouble() * 1.6) - 0.8;
    return Alignment(x, y);
  }

  void _close() {
    _autoCloseTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemNavigator.pop();
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 全屏黑底
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _close,
        child: Stack(
          children: [
            // 背景渐变
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [
                    Colors.deepPurple.withOpacity(0.3),
                    Colors.black,
                  ],
                ),
              ),
            ),
            // 第1行文字
            Align(
              alignment: _align1,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _line1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _color1,
                    fontSize: _fontSize1,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                          blurRadius: 12, color: _color1.withOpacity(0.7))
                    ],
                  ),
                ),
              ),
            ),
            // 第2行文字
            Align(
              alignment: _align2,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _line2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _color2,
                    fontSize: _fontSize2,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                          blurRadius: 12, color: _color2.withOpacity(0.7))
                    ],
                  ),
                ),
              ),
            ),
            // 提示
            const Positioned(
              top: 40,
              right: 20,
              child: Text(
                '点击任意处关闭',
                style: TextStyle(color: Colors.white24, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
