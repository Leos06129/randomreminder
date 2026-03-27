import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

void main() {
  runApp(const RandomReminderApp());
}

class RandomReminderApp extends StatelessWidget {
  const RandomReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '随机提醒',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final TextEditingController _line1Controller = TextEditingController();
  final TextEditingController _line2Controller = TextEditingController();
  final TextEditingController _line3Controller = TextEditingController();
  
  bool _isRunning = false;
  int _nextReminderMinutes = 0;
  
  // 字体设置
  String _fontFamily = 'Default';
  double _fontSize = 24.0;
  Color _textColor = Colors.black;
  
  static const _notificationChannelId = 'reminder_channel';
  static const _notificationChannelName = '随机提醒';
  static const _notificationChannelDesc = '随机提醒通知';
  
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  
  Timer? _fullScreenTimer;

  final List<String> _fontFamilies = [
    'Default', 'serif', 'monospace', 'cursive', 'fantasy'
  ];
  
  final List<double> _fontSizes = [18.0, 20.0, 22.0, 24.0, 28.0, 32.0, 36.0, 40.0];
  
  final List<Color> _colors = [
    Colors.black, Colors.white, Colors.red, Colors.blue, 
    Colors.green, Colors.orange, Colors.purple, Colors.pink
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _initNotifications();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _line1Controller.dispose();
    _line2Controller.dispose();
    _line3Controller.dispose();
    _fullScreenTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App 在后台时也要保持提醒
  }

  Future<void> _initNotifications() async {
    // 初始化时区
    tz_data.initializeTimeZones();
    
    // Android 设置
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    
    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
    
    // 创建通知渠道（重要：锁屏通知需要高优先级渠道）
    const androidChannel = AndroidNotificationChannel(
      _notificationChannelId,
      _notificationChannelName,
      description: _notificationChannelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
    );
    
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
    
    // 请求通知权限（Android 13+）
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  void _onNotificationTap(NotificationResponse response) {
    // 点击通知时打开应用
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _line1Controller.text = prefs.getString('line1') ?? '记得喝水哦~';
    _line2Controller.text = prefs.getString('line2') ?? '休息一下眼睛';
    _line3Controller.text = prefs.getString('line3') ?? '站起来活动一下';
    
    _fontFamily = prefs.getString('fontFamily') ?? 'Default';
    _fontSize = prefs.getDouble('fontSize') ?? 24.0;
    _textColor = Color(prefs.getInt('textColor') ?? 0xFF000000);
    
    setState(() {});
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('line1', _line1Controller.text);
    await prefs.setString('line2', _line2Controller.text);
    await prefs.setString('line3', _line3Controller.text);
    await prefs.setString('fontFamily', _fontFamily);
    await prefs.setDouble('fontSize', _fontSize);
    await prefs.setInt('textColor', _textColor.toARGB32());
  }

  void _startReminder() async {
    await _saveSettings();
    setState(() {
      _isRunning = true;
    });
    _scheduleNextReminder();
  }

  void _stopReminder() async {
    await _notifications.cancelAll();
    _fullScreenTimer?.cancel();
    setState(() {
      _isRunning = false;
      _nextReminderMinutes = 0;
    });
  }

  void _scheduleNextReminder() async {
    if (!_isRunning) return;

    final random = Random();
    final minutes = random.nextInt(4) + 1;
    _nextReminderMinutes = minutes;

    setState(() {});

    // 计算提醒时间
    final scheduledTime = DateTime.now().add(Duration(minutes: minutes));
    
    // 创建全屏通知设置（锁屏唤醒屏幕）
    final androidDetails = AndroidNotificationDetails(
      _notificationChannelId,
      _notificationChannelName,
      channelDescription: _notificationChannelDesc,
      importance: Importance.max,
      fullScreenIntent: true,  // 关键：全屏意图，锁屏时唤醒屏幕
      category: AndroidNotificationCategory.alarm,
      timeoutAfter: 5000,       // 5秒后自动消失
      autoCancel: true,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(
        '${_line1Controller.text}\n${_line2Controller.text}\n${_line3Controller.text}',
        contentTitle: '提醒',
        summaryText: '点击查看详情',
      ),
    );

    final details = NotificationDetails(android: androidDetails);

    // 使用 zonedSchedule 来定时提醒
    try {
      await _notifications.zonedSchedule(
        0,
        '提醒',
        '${_line1Controller.text}\n${_line2Controller.text}\n${_line3Controller.text}',
        _convertToTZDateTime(scheduledTime),
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      // 如果 zonedSchedule 失败，使用延时显示通知
      Timer(Duration(minutes: minutes), () {
        if (_isRunning) {
          _showFullScreenNotification();
        }
      });
    }
  }

  // 转换 DateTime 到 TZDateTime
  tz.TZDateTime _convertToTZDateTime(DateTime dateTime) {
    final location = tz.local;
    return tz.TZDateTime.from(dateTime, location);
  }

  void _showFullScreenNotification() async {
    if (!_isRunning) return;

    // 全屏通知设置
    final androidDetails = AndroidNotificationDetails(
      _notificationChannelId,
      _notificationChannelName,
      channelDescription: _notificationChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,  // 锁屏时唤醒屏幕
      category: AndroidNotificationCategory.alarm,
      timeoutAfter: 5000,
      autoCancel: true,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(
        '${_line1Controller.text}\n${_line2Controller.text}\n${_line3Controller.text}',
        contentTitle: '提醒',
        summaryText: '点击查看详情',
      ),
    );

    final details = NotificationDetails(android: androidDetails);

    // 显示通知（这会唤醒锁屏屏幕）
    await _notifications.show(
      0,
      '提醒',
      '${_line1Controller.text}\n${_line2Controller.text}\n${_line3Controller.text}',
      details,
    );

    // 5秒后自动进入下一次提醒
    _fullScreenTimer = Timer(const Duration(seconds: 5), () {
      if (_isRunning) {
        _scheduleNextReminder();
      }
    });
  }

  void _showFontSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('字体设置', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            
            // 字体选择
            const Text('字体'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: _fontFamilies.map((font) {
                return ChoiceChip(
                  label: Text(font, style: TextStyle(fontFamily: font)),
                  selected: _fontFamily == font,
                  onSelected: (selected) {
                    setState(() => _fontFamily = font);
                    _saveSettings();
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
            
            const SizedBox(height: 20),
            
            // 字体大小
            const Text('字体大小'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: _fontSizes.map((size) {
                return ChoiceChip(
                  label: Text('${size.toInt()}'),
                  selected: _fontSize == size,
                  onSelected: (selected) {
                    setState(() => _fontSize = size);
                    _saveSettings();
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
            
            const SizedBox(height: 20),
            
            // 字体颜色
            const Text('字体颜色'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: _colors.map((color) {
                return GestureDetector(
                  onTap: () {
                    setState(() => _textColor = color);
                    _saveSettings();
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _textColor == color ? Colors.blue : Colors.grey,
                        width: _textColor == color ? 3 : 1,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('随机提醒小程序'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.font_download),
            onPressed: _showFontSettings,
            tooltip: '字体设置',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '设置提醒内容（3行文字）',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _line1Controller,
              decoration: const InputDecoration(
                labelText: '第1行',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.text_fields),
              ),
              style: TextStyle(fontFamily: _fontFamily == 'Default' ? null : _fontFamily, fontSize: _fontSize * 0.7),
              onChanged: (_) => _saveSettings(),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _line2Controller,
              decoration: const InputDecoration(
                labelText: '第2行',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.text_fields),
              ),
              style: TextStyle(fontFamily: _fontFamily == 'Default' ? null : _fontFamily, fontSize: _fontSize * 0.7),
              onChanged: (_) => _saveSettings(),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _line3Controller,
              decoration: const InputDecoration(
                labelText: '第3行',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.text_fields),
              ),
              style: TextStyle(fontFamily: _fontFamily == 'Default' ? null : _fontFamily, fontSize: _fontSize * 0.7),
              onChanged: (_) => _saveSettings(),
            ),
            const SizedBox(height: 30),
            
            // 预览效果
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  const Text('预览效果', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(
                    _line1Controller.text,
                    style: TextStyle(
                      fontFamily: _fontFamily == 'Default' ? null : _fontFamily,
                      fontSize: _fontSize * 0.6,
                      color: _textColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    _line2Controller.text,
                    style: TextStyle(
                      fontFamily: _fontFamily == 'Default' ? null : _fontFamily,
                      fontSize: _fontSize * 0.6,
                      color: _textColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    _line3Controller.text,
                    style: TextStyle(
                      fontFamily: _fontFamily == 'Default' ? null : _fontFamily,
                      fontSize: _fontSize * 0.6,
                      color: _textColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            if (_isRunning) ...[
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.timer, color: Colors.green, size: 40),
                    const SizedBox(height: 10),
                    Text(
                      '正在运行中...',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '下次提醒: $_nextReminderMinutes 分钟后',
                      style: TextStyle(color: Colors.green.shade600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _stopReminder,
                icon: const Icon(Icons.stop),
                label: const Text('停止提醒'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: _startReminder,
                icon: const Icon(Icons.play_arrow),
                label: const Text('开始随机提醒'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 10),
            const Text(
              '💡 使用说明',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            const Text('• 首次使用需允许通知权限'),
            const Text('• 点击"开始随机提醒"后，每隔1-4分钟随机弹出提醒'),
            const Text('• 锁屏状态下会亮屏显示提醒'),
            const Text('• 点击右上角图标可设置字体、大小、颜色'),
            const Text('• 请确保手机没有限制应用后台运行'),
          ],
        ),
      ),
    );
  }
}
