import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:timezone/data/latest.dart' as tz_data;

// ─────────────────────────────────────────────
// 全局通知插件
// ─────────────────────────────────────────────
final fln.FlutterLocalNotificationsPlugin _notifications =
    fln.FlutterLocalNotificationsPlugin();

// ─────────────────────────────────────────────
// 前台任务回调（在独立 Isolate 运行，app 后台/锁屏时依然工作）
// ─────────────────────────────────────────────
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(ReminderTaskHandler());
}

class ReminderTaskHandler extends TaskHandler {
  int _waitSeconds = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    tz_data.initializeTimeZones();
    await _initNotificationsInTask();
    _scheduleNext();
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    if (_waitSeconds > 0) {
      _waitSeconds--;
      FlutterForegroundTask.updateService(
        notificationTitle: '随机提醒运行中',
        notificationText: '下次提醒：$_waitSeconds 秒后',
      );
    }
    if (_waitSeconds == 0) {
      _waitSeconds = -1; // 防止重复触发
      await _fireReminder();
      _scheduleNext();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await _notifications.cancelAll();
  }

  @override
  void onReceiveData(Object data) {}

  void _scheduleNext() {
    final rng = Random();
    _waitSeconds = rng.nextInt(31) + 10; // 10~40 秒
    FlutterForegroundTask.updateService(
      notificationTitle: '随机提醒运行中',
      notificationText: '下次提醒：$_waitSeconds 秒后',
    );
  }

  Future<void> _initNotificationsInTask() async {
    const androidSettings =
        fln.AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = fln.InitializationSettings(android: androidSettings);
    await _notifications.initialize(initSettings);

    const androidChannel = fln.AndroidNotificationChannel(
      'reminder_channel',
      '随机提醒',
      description: '随机提醒全屏通知',
      importance: fln.Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
            fln.AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  Future<void> _fireReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final line1 = prefs.getString('line1') ?? '记得喝水 💧';
    final line2 = prefs.getString('line2') ?? '站起来活动一下 🚶';

    // 使用高优先级 + fullScreenIntent 实现锁屏全屏弹出
    final androidDetails = fln.AndroidNotificationDetails(
      'reminder_channel',
      '随机提醒',
      channelDescription: '随机提醒全屏通知',
      importance: fln.Importance.max,
      priority: fln.Priority.max,      // 最高优先级
      fullScreenIntent: true,         // 全屏意图，锁屏时唤屏
      category: fln.AndroidNotificationCategory.alarm,
      visibility: fln.NotificationVisibility.public,
      timeoutAfter: 5000,
      autoCancel: true,
      playSound: true,
      enableVibration: true,
      styleInformation: fln.BigTextStyleInformation(
        '$line1\n$line2',
        contentTitle: '提醒',
      ),
    );

    await _notifications.show(
      1,
      '提醒',
      '$line1\n$line2',
      fln.NotificationDetails(android: androidDetails),
    );
  }
}

// ─────────────────────────────────────────────
// 初始化本地通知（主 Isolate 用）
// ─────────────────────────────────────────────
Future<void> _initNotifications() async {
  tz_data.initializeTimeZones();
  const androidSettings =
      fln.AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = fln.InitializationSettings(android: androidSettings);

  await _notifications.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (details) {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const ReminderOverlayPage()),
      );
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  const androidChannel = fln.AndroidNotificationChannel(
    'reminder_channel',
    '随机提醒',
    description: '随机提醒全屏通知',
    importance: fln.Importance.max,
    playSound: true,
    enableVibration: true,
    enableLights: true,
  );
  await _notifications
      .resolvePlatformSpecificImplementation<
          fln.AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(androidChannel);

  await _notifications
      .resolvePlatformSpecificImplementation<
          fln.AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

@pragma('vm:entry-point')
void notificationTapBackground(fln.NotificationResponse response) {}

// ─────────────────────────────────────────────
// 初始化前台任务配置
// ─────────────────────────────────────────────
void _initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'foreground_service_channel',
      channelName: '随机提醒服务',
      channelDescription: '随机提醒后台服务通知',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(1000), // 每秒回调
      autoRunOnBoot: false,
      allowWifiLock: true,
    ),
  );
}

// ─────────────────────────────────────────────
// 全局 Navigator key
// ─────────────────────────────────────────────
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initNotifications();
  _initForegroundTask();
  runApp(const RandomReminderApp());
}

class RandomReminderApp extends StatelessWidget {
  const RandomReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: '随机提醒',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
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

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final TextEditingController _line1 = TextEditingController();
  final TextEditingController _line2 = TextEditingController();

  bool _isRunning = false;
  int _countdownSeconds = 0;
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _checkIfRunning();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    _handleInitialNotification();
  }

  void _onTaskData(Object data) {}

  Future<void> _handleInitialNotification() async {
    final details = await _notifications.getNotificationAppLaunchDetails();
    if (details != null && details.didNotificationLaunchApp && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ReminderOverlayPage()),
        );
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _uiTimer?.cancel();
    _line1.dispose();
    _line2.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _line1.text = p.getString('line1') ?? '时时彻知无常！';
      _line2.text = p.getString('line2') ?? '刻刻精勤觉知！';
    });
  }

  Future<void> _saveSettings() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('line1', _line1.text);
    await p.setString('line2', _line2.text);
  }

  Future<void> _checkIfRunning() async {
    final running = await FlutterForegroundTask.isRunningService;
    if (mounted) setState(() => _isRunning = running);
  }

  void _toggleReminder() async {
    if (_isRunning) {
      await _stopReminder();
    } else {
      await _saveSettings();
      await _startReminder();
    }
  }

  Future<void> _startReminder() async {
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();

    final result = await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: '随机提醒运行中',
      notificationText: '准备开始...',
      callback: startCallback,
    );

    if (result is ServiceRequestSuccess ||
        await FlutterForegroundTask.isRunningService) {
      setState(() => _isRunning = true);
      _startUiCountdown();
    }
  }

  Future<void> _stopReminder() async {
    await FlutterForegroundTask.stopService();
    await _notifications.cancelAll();
    _uiTimer?.cancel();
    setState(() {
      _isRunning = false;
      _countdownSeconds = 0;
    });
  }

  void _startUiCountdown() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isRunning) return;
      setState(() {
        if (_countdownSeconds > 0) _countdownSeconds--;
      });
    });
    setState(() => _countdownSeconds = 25);
  }

  String _fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return m > 0 ? '$m 分 ${sec.toString().padLeft(2, '0')} 秒' : '$sec 秒';
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

            TextField(
              controller: _line1,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: _inputDecoration('提醒第 1 行'),
              onChanged: (_) => _saveSettings(),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _line2,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: _inputDecoration('提醒第 2 行'),
              onChanged: (_) => _saveSettings(),
            ),

            const SizedBox(height: 40),

            if (_isRunning) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 20, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F3460),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Colors.deepPurpleAccent, width: 1),
                ),
                child: Column(
                  children: [
                    const Text('下次提醒倒计时',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 14)),
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
                    const SizedBox(height: 6),
                    const Text('后台/锁屏下依然持续运行',
                        style: TextStyle(
                            color: Colors.white30, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _toggleReminder,
                icon: Icon(
                    _isRunning ? Icons.stop_circle : Icons.play_circle,
                    size: 28),
                label: Text(
                  _isRunning ? '停止提醒' : '保存并开始提醒',
                  style: const TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRunning
                      ? Colors.redAccent
                      : Colors.deepPurpleAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),

            const Spacer(),

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
                          color: Colors.white70,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text('• 编辑两行提醒文字后点击"保存并开始提醒"',
                      style: TextStyle(
                          color: Colors.white38, fontSize: 13)),
                  Text('• 每隔 10~40 秒随机弹出全屏提醒',
                      style: TextStyle(
                          color: Colors.white38, fontSize: 13)),
                  Text('• 后台和锁屏时也会亮屏全屏提醒',
                      style: TextStyle(
                          color: Colors.white38, fontSize: 13)),
                  Text('• 文字随机颜色、大小、位置',
                      style: TextStyle(
                          color: Colors.white38, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
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
      prefixIcon: const Icon(Icons.edit, color: Colors.white38),
    );
  }
}

// ─────────────────────────────────────────────
// 全屏提醒页
// ─────────────────────────────────────────────
class ReminderOverlayPage extends StatefulWidget {
  const ReminderOverlayPage({super.key});

  @override
  State<ReminderOverlayPage> createState() => _ReminderOverlayPageState();
}

class _ReminderOverlayPageState extends State<ReminderOverlayPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  Timer? _autoCloseTimer;

  final Random _rng = Random();

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
    _loadLines();

    _color1 = _palette[_rng.nextInt(_palette.length)];
    _color2 = _palette[_rng.nextInt(_palette.length)];
    _fontSize1 = 22 + _rng.nextDouble() * 20;
    _fontSize2 = 22 + _rng.nextDouble() * 20;
    _align1 = _randomAlignment();
    _align2 = _randomAlignment();

    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _fadeController.forward();

    _autoCloseTimer = Timer(const Duration(seconds: 5), _close);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _loadLines() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _line1 = p.getString('line1') ?? '记得喝水 💧';
        _line2 = p.getString('line2') ?? '站起来活动一下 🚶';
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
