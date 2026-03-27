import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

class _HomePageState extends State<HomePage> {
  final TextEditingController _line1Controller = TextEditingController();
  final TextEditingController _line2Controller = TextEditingController();
  final TextEditingController _line3Controller = TextEditingController();
  bool _isRunning = false;
  int _nextReminderMinutes = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    final FlutterLocalNotificationsPlugin notifications =
        FlutterLocalNotificationsPlugin();
    
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    
    await notifications.initialize(initSettings);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _line1Controller.text = prefs.getString('line1') ?? '记得喝水哦~';
    _line2Controller.text = prefs.getString('line2') ?? '休息一下眼睛';
    _line3Controller.text = prefs.getString('line3') ?? '站起来活动一下';
    setState(() {});
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('line1', _line1Controller.text);
    await prefs.setString('line2', _line2Controller.text);
    await prefs.setString('line3', _line3Controller.text);
  }

  void _startReminder() async {
    await _saveSettings();
    setState(() {
      _isRunning = true;
    });
    _scheduleNextReminder();
  }

  void _stopReminder() async {
    final FlutterLocalNotificationsPlugin notifications =
        FlutterLocalNotificationsPlugin();
    await notifications.cancelAll();
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

    final FlutterLocalNotificationsPlugin notifications =
        FlutterLocalNotificationsPlugin();

    const androidDetails = AndroidNotificationDetails(
      'reminder_channel',
      '随机提醒',
      channelDescription: '随机提醒通知',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(android: androidDetails);

    await notifications.show(
      0,
      '提醒',
      '${_line1Controller.text}\n${_line2Controller.text}\n${_line3Controller.text}',
      details,
    );

    setState(() {});

    Future.delayed(Duration(minutes: minutes), () {
      if (_isRunning) {
        _showFullScreenNotification();
        _scheduleNextReminder();
      }
    });
  }

  void _showFullScreenNotification() async {
    final FlutterLocalNotificationsPlugin notifications =
        FlutterLocalNotificationsPlugin();

    const androidDetails = AndroidNotificationDetails(
      'reminder_channel',
      '随机提醒',
      channelDescription: '随机提醒通知',
      importance: Importance.max,
      priority: Priority.max,
    );

    const details = NotificationDetails(android: androidDetails);

    await notifications.show(
      1,
      '提醒',
      '${_line1Controller.text}\n${_line2Controller.text}\n${_line3Controller.text}',
      details,
    );
  }

  @override
  void dispose() {
    _line1Controller.dispose();
    _line2Controller.dispose();
    _line3Controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('随机提醒小程序'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
              onChanged: (_) => _saveSettings(),
            ),
            const SizedBox(height: 30),
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
            const Text('• 点击"开始随机提醒"后，每隔1-4分钟随机弹出提醒'),
            const Text('• 锁屏状态下也会弹出通知'),
            const Text('• 可以随时修改提醒内容'),
          ],
        ),
      ),
    );
  }
}
