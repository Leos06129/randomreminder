package com.reminder.randomreminder;

import android.app.Activity;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.view.Window;
import android.view.WindowManager;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/**
 * 全屏提醒 Activity
 * 通过 notification 的 fullScreenIntent 启动，实现锁屏时全屏弹出
 */
public class FullScreenActivity extends FlutterActivity {
    
    public static final String EXTRA_FULLSCREEN = "extra_fullscreen";
    public static boolean isFullScreenLaunch = false;
    private static final String CHANNEL = "com.example.randomreminder/launch";
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        // 检查是否是全屏启动
        if (getIntent() != null && getIntent().getBooleanExtra(EXTRA_FULLSCREEN, false)) {
            isFullScreenLaunch = true;
        }
        
        // 全屏配置
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Window window = getWindow();
            window.setType(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY);
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED |
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON |
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            );
        } else {
            @SuppressWarnings("deprecation")
            Window window = getWindow();
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED |
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON |
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            );
        }
    }
    
    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        
        // 注册方法通道
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("isFullScreen")) {
                    result.success(isFullScreenLaunch);
                    // 重置标志
                    isFullScreenLaunch = false;
                } else {
                    result.notImplemented();
                }
            });
    }
}
