import 'dart:math';
import 'dart:async';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

// ─────────────────────────────────────────────
// 全局通知插件
// ─────────────────────────────────────────────
final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();

// ─────────────────────────────────────────────
// 前台任务回调（在独立 Isolate 运行，app 后台/锁屏时依然工作）
// ─────────────────────────────────────────────
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(ReminderTaskHandler());
}

class ReminderTaskHandler extends TaskHandler {
  int _waitSeconds = 0;
  Timer? _timer;

  // 每秒被 FlutterForegroundTask 回调一次
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
      // 更新通知栏倒计时文字
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
    _timer?.cancel();
    await _notifications.cancelAll();
  }

  // 收到 main isolate 发来的消息（如更新提醒文字）
  @override
  void onReceiveData(Object data) {}

  void _scheduleNext() {
    final rng = Random();
    _waitSeconds = rng.nextInt(41) + 20; // 20~60 秒
    FlutterForegroundTask.updateService(
      notificationTitle: '随机提醒运行中',
      notificationText: '下次提醒：$_waitSeconds 秒后',
    );
  }

  Future<void> _initNotificationsInTask() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(initSettings);

    const androidChannel = AndroidNotificationChannel(
      'reminder_channel',
      '随机提醒',
      description: '随机提醒全屏通知',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  Future<void> _fireReminder() async {
    // 读取保存的提醒内容
    final prefs = await SharedPreferences.getInstance();
    final line1 = prefs.getString('line1') ?? '记得喝水 💧';
    final line2 = prefs.getString('line2') ?? '站起来活动一下 🚶';

    // 全屏通知：锁屏唤屏 + 前台 Activity 覆盖
    final androidDetails = AndroidNotificationDetails(
      'reminder_channel',
      '随机提醒',
      channelDescription: '随机提醒全屏通知',
      importance: Importance.max,
      fullScreenIntent: true,        // 关键：全屏意图唤屏
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      timeoutAfter: 5000,            // 5 秒后通知自动消失
      autoCancel: true,
      playSound: true,
      enableVibration: true,
      // 把提醒文字放在通知体里，供全屏 Activity 读取
      styleInformation: BigTextStyleInformation(
        '$line1\n$line2',
        contentTitle: '提醒',
      ),
    );

    await _notifications.show(
      1,
      '提醒',
      '$line1\n$line2',
      NotificationDetails(android: androidDetails),
    );
  }
}

// ─────────────────────────────────────────────
// 初始化本地通知（主 Isolate 用）
// ─────────────────────────────────────────────
Future<void> _initNotifications() async {
  tz_data.initializeTimeZones();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);

  await _notifications.initialize(
    initSettings,
    // 点击通知时打开全屏提醒页
    onDidReceiveNotificationResponse: (details) {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const ReminderOverlayPage()),
      );
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  const androidChannel = AndroidNotificationChannel(
    'reminder_channel',
    '随机提醒',
    description: '随机提醒全屏通知',
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

// 后台通知点击回调（顶层函数）
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {}

// ─────────────────────────────────────────────
// 初始化前台任务
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
// 全局 Navigator key（供通知回调跳转用）
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

  // 前台时用来显示倒计时（从服务轮询）
  int _countdownSeconds = 0;
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _checkIfRunning();

    // 监听前台任务数据（倒计时更新）
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);

    // 当 app 从通知点击唤起时，直接显示全屏提醒
    _handleInitialNotification();
  }

  void _onTaskData(Object data) {
    // TaskHandler.sendData() 可以传倒计时，这里暂用轮询
  }

  Future<void> _handleInitialNotification() async {
    final details =
        await _notifications.getNotificationAppLaunchDetails();
    if (details != null &&
        details.didNotificationLaunchApp &&
        mounted) {
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
      _line1.text = p.getString('line1') ?? '记得喝水 💧';
      _line2.text = p.getString('line2') ?? '站起来活动一下 🚶';
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

  // 启动或停止
  void _toggleReminder() async {
    if (_isRunning) {
      await _stopReminder();
    } else {
      await _saveSettings();
      await _startReminder();
    }
  }

  Future<void> _startReminder() async {
    // 请求必要权限
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();

    final result = await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: '随机提醒运行中',
      notificationText: '准备开始...',
      callback: startCallback,
    );

    if (result == ServiceRequestResult.success ||
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

  // UI 倒计时（仅前台显示，不影响后台逻辑）
  void _startUiCountdown() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!_isRunning) return;
      // 读取服务通知文字里的秒数（简单方案）
      setState(() {
        if (_countdownSeconds > 0) _countdownSeconds--;
      });
    });
    // 初始值设一个随机区间中值（服务会自行管理真实倒计时）
    setState(() => _countdownSeconds = 40);
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
              decoration: _inputDecoration('提醒第 1 行'),
              onChanged: (_) => _saveSettings(),
            ),

            const SizedBox(height: 16),

            // 第2行
            TextField(
              controller: _line2,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: _inputDecoration('提醒第 2 行'),
              onChanged: (_) => _saveSettings(),
            ),

            const SizedBox(height: 40),

            // 倒计时卡片
            if (_isRunning) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F3460),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.deepPurpleAccent, width: 1),
                ),
                child: Column(
                  children: [
                    const Text('下次提醒倒计时',
                        style:
                            TextStyle(color: Colors.white54, fontSize: 14)),
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
                        style:
                            TextStyle(color: Colors.white30, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // 开始/停止 按钮
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
                          color: Colors.white70,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text('• 编辑两行提醒文字后点击"保存并开始提醒"',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 13)),
                  Text('• 每隔 20~60 秒随机弹出全屏提醒',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 13)),
                  Text('• 后台和锁屏时也会亮屏全屏提醒',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 13)),
                  Text('• 文字随机颜色、大小、位置',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 13)),
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
        borderSide:
            const BorderSide(color: Colors.deepPurpleAccent),
      ),
      prefixIcon: const Icon(Icons.edit, color: Colors.white38),
    );
  }
}

// ─────────────────────────────────────────────
// 全屏提醒覆盖页（前台/从通知点击唤起都会显示）
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

    // 读取保存的提醒内容
    _loadLines();

    _color1 = _palette[_rng.nextInt(_palette.length)];
    _color2 = _palette[_rng.nextInt(_palette.length)];
    _fontSize1 = 22 + _rng.nextDouble() * 20;
    _fontSize2 = 22 + _rng.nextDouble() * 20;
    _align1 = _randomAlignment();
    _align2 = _randomAlignment();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
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
                          blurRadius: 12,
                          color: _color1.withOpacity(0.7),
                        ),
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
                          blurRadius: 12,
                          color: _color2.withOpacity(0.7),
                        ),
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
