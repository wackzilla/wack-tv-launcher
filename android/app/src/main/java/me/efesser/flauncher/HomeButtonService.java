/*
 * Wack XP Launcher (FLauncher fork)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package me.efesser.flauncher;

import android.accessibilityservice.AccessibilityService;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;

/**
 * Makes the remote's Home button always open this launcher, even when the TV firmware
 * insists on its own home screen, and brings this launcher back if the stock home
 * screen shows up anyway. Both are toggled from the launcher settings, which are stored
 * by the Flutter side in its shared preferences file.
 *
 * Also gives the Start menu's "Turn Off Computer" dialog access to the system power
 * actions, which only an accessibility service can trigger.
 */
public class HomeButtonService extends AccessibilityService
{
    public static final String OVERRIDE_HOME_KEY = "flutter.override_home";
    public static final String GUARD_STOCK_KEY = "flutter.guard_stock_launcher";

    private static final String[] STOCK_HOMES = {
            "com.google.android.tvlauncher",
            "com.google.android.apps.tv.launcherx",
            "com.google.android.leanbacklauncher",
            "com.amazon.tv.launcher"
    };

    private static HomeButtonService instance;

    static HomeButtonService getInstance() {
        return instance;
    }

    static SharedPreferences flutterPreferences(Context context) {
        return context.getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE);
    }

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        instance = this;
    }

    @Override
    public boolean onUnbind(Intent intent) {
        instance = null;
        return super.onUnbind(intent);
    }

    @Override
    public void onDestroy() {
        instance = null;
        super.onDestroy();
    }

    @Override
    protected boolean onKeyEvent(KeyEvent event) {
        if (event.getKeyCode() == KeyEvent.KEYCODE_HOME
                && flutterPreferences(this).getBoolean(OVERRIDE_HOME_KEY, true)) {
            if (event.getAction() == KeyEvent.ACTION_UP) {
                goHome();
            }
            return true;
        }
        return false;
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event.getEventType() != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            return;
        }
        if (!flutterPreferences(this).getBoolean(GUARD_STOCK_KEY, true)) {
            return;
        }

        String packageName = String.valueOf(event.getPackageName());
        for (String stockHome : STOCK_HOMES) {
            if (stockHome.equals(packageName)) {
                goHome();
                return;
            }
        }
    }

    @Override
    public void onInterrupt() { }

    boolean standBy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            return performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN);
        }
        return false;
    }

    boolean showPowerDialog() {
        return performGlobalAction(GLOBAL_ACTION_POWER_DIALOG);
    }

    private void goHome() {
        Intent intent = new Intent(this, MainActivity.class)
                .setAction(MainActivity.ACTION_HOME_PRESSED)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        try {
            startActivity(intent);
        } catch (Exception ignored) { }
    }
}
