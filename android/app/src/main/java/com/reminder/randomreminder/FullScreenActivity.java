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
 * 通过 notification 的 fullScreenIntent 或 AndroidIntent 启动
 * 锁屏和未锁屏时都能全屏弹出
 */
public class FullScreenActivity extends FlutterActivity {
    
    public static final String EXTRA_FULLSCREEN = "extra_fullscreen";
    public static boolean isFullScreenLaunch = false;
    private static final String CHANNEL = "com.reminder.randomreminder/launch";
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        // 检查是否是全屏启动
        if (getIntent() != null && getIntent().getBooleanExtra(EXTRA_FULLSCREEN, false)) {
            isFullScreenLaunch = true;
        }
        
        // 全屏配置 - 关键：允许在后台启动
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Window window = getWindow();
            window.setType(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY);
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED |
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON |
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON |
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN |
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            );
        } else {
            @SuppressWarnings("deprecation")
            Window window = getWindow();
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED |
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON |
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON |
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN |
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
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
