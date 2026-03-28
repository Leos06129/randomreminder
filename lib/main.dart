import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  await _initNotifications();
  runApp(const RandomReminderApp());
}

Future<void> _initNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);
  await _notifications.initialize(initSettings);

  const androidChannel = AndroidNotificationChannel(
    'reminder_channel',
    '随机提醒',
    description: '随机提醒通知',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    enableLights: true,
  );
  await _notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(androidChannel);

  await _notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

class RandomReminderApp extends StatelessWidget {
  const RandomReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '随机提醒',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
      routes: {
        '/reminder': (context) => const ReminderOverlayPage(),
      },
    );
  }
}

// ─────────────────────────────────────────────
// 主页面
// ─────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _line1 = TextEditingController();
  final TextEditingController _line2 = TextEditingController();

  bool _isRunning = false;
  int _countdownSeconds = 0;
  Timer? _countdownTimer;
  Timer? _reminderTimer;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _line1.dispose();
    _line2.dispose();
    _countdownTimer?.cancel();
    _reminderTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _line1.text = p.getString('line1') ?? '记得喝水 💧';
      _line2.text = p.getString('line2') ?? '站起来活动一下 🚶';
    });
  }

  Future<void> _saveSettings() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('line1', _line1.text);
    await p.setString('line2', _line2.text);
  }

  // 启动或停止
  void _toggleReminder() async {
    if (_isRunning) {
      _stopReminder();
    } else {
      await _saveSettings();
      _startReminder();
    }
  }

  void _startReminder() {
    setState(() => _isRunning = true);
    _scheduleNext();
  }

  void _stopReminder() {
    _countdownTimer?.cancel();
    _reminderTimer?.cancel();
    _notifications.cancelAll();
    setState(() {
      _isRunning = false;
      _countdownSeconds = 0;
    });
  }

  void _scheduleNext() {
    if (!_isRunning) return;
    final rng = Random();
    // 20 ~ 60 秒随机
    final waitSeconds = rng.nextInt(41) + 20;
    setState(() => _countdownSeconds = waitSeconds);

    // 倒计时
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_isRunning) {
        t.cancel();
        return;
      }
      setState(() => _countdownSeconds--);
      if (_countdownSeconds <= 0) {
        t.cancel();
      }
    });

    // 到时触发全屏提醒
    _reminderTimer?.cancel();
    _reminderTimer = Timer(Duration(seconds: waitSeconds), () {
      if (_isRunning) {
        _showReminder();
      }
    });
  }

  Future<void> _showReminder() async {
    // 发送通知（锁屏唤醒）
    final androidDetails = AndroidNotificationDetails(
      'reminder_channel',
      '随机提醒',
      channelDescription: '随机提醒通知',
      importance: Importance.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      timeoutAfter: 5000,
      autoCancel: true,
      playSound: true,
      enableVibration: true,
    );
    await _notifications.show(
      0,
      '提醒',
      '${_line1.text}  ${_line2.text}',
      NotificationDetails(android: androidDetails),
    );

    // 前台：跳转到全屏提醒页，传入提醒文字
    if (mounted) {
      await Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          pageBuilder: (_, __, ___) => ReminderOverlayPage(
            line1: _line1.text,
            line2: _line2.text,
          ),
        ),
      );
    }

    // 关闭后进入下一轮
    if (_isRunning) _scheduleNext();
  }

  String _fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return m > 0
        ? '$m 分 ${sec.toString().padLeft(2, '0')} 秒'
        : '$sec 秒';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('随机提醒', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),

            // 第1行
            TextField(
              controller: _line1,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                labelText: '提醒第 1 行',
                labelStyle: const TextStyle(color: Colors.white54),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.deepPurpleAccent),
                ),
                prefixIcon:
                    const Icon(Icons.edit, color: Colors.white38),
              ),
              onChanged: (_) => _saveSettings(),
            ),

            const SizedBox(height: 16),

            // 第2行
            TextField(
              controller: _line2,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                labelText: '提醒第 2 行',
                labelStyle: const TextStyle(color: Colors.white54),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.deepPurpleAccent),
                ),
                prefixIcon:
                    const Icon(Icons.edit, color: Colors.white38),
              ),
              onChanged: (_) => _saveSettings(),
            ),

            const SizedBox(height: 40),

            // 倒计时卡片
            if (_isRunning) ...[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F3460),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.deepPurpleAccent, width: 1),
                ),
                child: Column(
                  children: [
                    const Text('下次提醒倒计时',
                        style: TextStyle(color: Colors.white54, fontSize: 14)),
                    const SizedBox(height: 10),
                    Text(
                      _fmt(_countdownSeconds),
                      style: const TextStyle(
                        color: Colors.deepPurpleAccent,
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // 开始/停止 按钮（同时保存）
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _toggleReminder,
                icon: Icon(_isRunning ? Icons.stop_circle : Icons.play_circle,
                    size: 28),
                label: Text(
                  _isRunning ? '停止提醒' : '保存并开始提醒',
                  style: const TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isRunning ? Colors.redAccent : Colors.deepPurpleAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),

            const Spacer(),

            // 说明
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('💡 使用说明',
                      style: TextStyle(
                          color: Colors.white70, fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text('• 编辑两行提醒文字后点击"保存并开始提醒"',
                      style: TextStyle(color: Colors.white38, fontSize: 13)),
                  Text('• 每隔 20~60 秒随机弹出全屏提醒',
                      style: TextStyle(color: Colors.white38, fontSize: 13)),
                  Text('• 锁屏状态下会亮屏全屏显示',
                      style: TextStyle(color: Colors.white38, fontSize: 13)),
                  Text('• 文字随机颜色、大小、位置',
                      style: TextStyle(color: Colors.white38, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 全屏提醒覆盖页
// ─────────────────────────────────────────────
class ReminderOverlayPage extends StatefulWidget {
  final String line1;
  final String line2;

  const ReminderOverlayPage({
    super.key,
    this.line1 = '',
    this.line2 = '',
  });

  @override
  State<ReminderOverlayPage> createState() => _ReminderOverlayPageState();
}

class _ReminderOverlayPageState extends State<ReminderOverlayPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  Timer? _autoCloseTimer;

  final Random _rng = Random();

  // 随机样式
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

    // 随机样式初始化
    _color1 = _palette[_rng.nextInt(_palette.length)];
    _color2 = _palette[_rng.nextInt(_palette.length)];
    _fontSize1 = 22 + _rng.nextDouble() * 20; // 22~42
    _fontSize2 = 22 + _rng.nextDouble() * 20;
    _align1 = _randomAlignment();
    _align2 = _randomAlignment();

    // 淡入动画
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _fadeController.forward();

    // 5 秒后自动关闭
    _autoCloseTimer = Timer(const Duration(seconds: 5), _close);

    // 全屏 + 亮屏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Alignment _randomAlignment() {
    // x: -0.8 ~ 0.8  y: -0.8 ~ 0.8
    final x = (_rng.nextDouble() * 1.6) - 0.8;
    final y = (_rng.nextDouble() * 1.6) - 0.8;
    return Alignment(x, y);
  }

  void _close() {
    _autoCloseTimer?.cancel();
    if (mounted) {
      _fadeController.reverse().then((_) {
        if (mounted) Navigator.of(context).pop();
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _close,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
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

              // 第1行文字（随机位置）
              Align(
                alignment: _align1,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    widget.line1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _color1,
                      fontSize: _fontSize1,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          blurRadius: 12,
                          color: _color1.withOpacity(0.7),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 第2行文字（随机位置）
              Align(
                alignment: _align2,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    widget.line2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _color2,
                      fontSize: _fontSize2,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          blurRadius: 12,
                          color: _color2.withOpacity(0.7),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 提示（右上角）
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
      ),
    );
  }
}
