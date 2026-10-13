package com.chekusu.sofatap.tv;

import android.app.*;
import android.content.*;
import android.graphics.Rect;
import android.os.*;
import android.view.WindowManager;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import com.chekusu.sofatap.tv.input.InputBridge;
import org.json.JSONObject;
import org.junit.*;
import org.junit.runner.RunWith;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.concurrent.atomic.AtomicReference;
import static org.junit.Assert.*;

/** Runs only on an explicitly opted-in disposable emulator, never on a household TV. */
@RunWith(AndroidJUnit4.class)
public final class ReceiverDeviceTest {
    private Instrumentation instrumentation;
    private UiAutomation automation;
    private Context context;
    interface Checked<T> { T call() throws Exception; }
    @Before public void emulatorOnly() {
        instrumentation = InstrumentationRegistry.getInstrumentation(); context = instrumentation.getTargetContext();
        Assume.assumeTrue("Only the owned headless emulator is allowed",
            "yes".equals(InstrumentationRegistry.getArguments().getString("disposableEmulator")) &&
            (Build.FINGERPRINT.contains("generic") || Build.MODEL.contains("sdk")));
        automation = instrumentation.getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES);
    }
    private <T> T main(Checked<T> operation) throws Exception {
        AtomicReference<T> value = new AtomicReference<>(); AtomicReference<Exception> error = new AtomicReference<>();
        instrumentation.runOnMainSync(() -> { try { value.set(operation.call()); } catch (Exception e) { error.set(e); } });
        if (error.get() != null) throw error.get(); return value.get();
    }
    private String shell(String command) throws IOException {
        try (ParcelFileDescriptor fd = automation.executeShellCommand(command);
             FileInputStream input = new FileInputStream(fd.getFileDescriptor()); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[2048]; int count; while ((count = input.read(buffer)) >= 0) output.write(buffer, 0, count);
            return output.toString("UTF-8").trim();
        }
    }
    private void until(Checked<Boolean> condition) throws Exception {
        long deadline = SystemClock.elapsedRealtime() + 8000;
        while (!condition.call() && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(80);
        assertTrue("Timed out waiting for an observable Android state", condition.call());
    }
    private JSONObject snapshot() throws Exception { return main(() -> InputBridge.snapshot(context)); }
    private JSONObject input(String action, double x, double y) throws Exception { return main(() -> InputBridge.perform(context, action, x, y)); }
    private void moveTo(int x, int y) throws Exception {
        JSONObject position = input("move", 0, 0); assertTrue(position.toString(), position.getBoolean("ok"));
        double dx = x - position.getDouble("x"), dy = y - position.getDouble("y");
        while (Math.abs(dx) > 0.1 || Math.abs(dy) > 0.1) {
            double stepX = Math.max(-400, Math.min(400, dx)), stepY = Math.max(-400, Math.min(400, dy));
            JSONObject moved = input("move", stepX, stepY); assertTrue(moved.toString(), moved.getBoolean("ok")); dx -= stepX; dy -= stepY;
        }
    }
    @Test public void strictProtocolUsesAndroidJsonProvider() throws Exception {
        String base = "{\"id\":\"11111111-1111-4111-8111-111111111111\",\"type\":\"click\"}";
        assertEquals("click", TVProtocol.parse(base).type());
        for (String invalid : new String[]{"\uFEFF" + base, base.replace("{", "{/*comment*/"), base.replace("click", "cl\\ick"), base.replace("\"type\"", "'type'"), base.replace("}", ",\"type\":\"ping\"}"), base + "#comment"}) {
            try { TVProtocol.parse(invalid); fail("Lenient JSON accepted"); } catch (IllegalArgumentException expected) { }
        }
    }
    @Test public void identityIsEncryptedAndSurvivesRestart() throws Exception {
        ReceiverIdentity first = new ReceiverIdentity(context); String fingerprint = first.fingerprint();
        String marker = PairingAuthority.hash(PairingAuthority.randomToken());
        try {
            first.saveDigest(marker); ReceiverIdentity second = new ReceiverIdentity(context);
            assertEquals(fingerprint, second.fingerprint()); assertEquals(marker, second.pairedDigest());
            byte[] bytes = Files.readAllBytes(new File(context.getNoBackupFilesDir(), "receiver-identity.enc").toPath());
            String raw = new String(bytes, StandardCharsets.ISO_8859_1);
            assertFalse(raw.contains(marker)); assertFalse(raw.contains("PRIVATE KEY"));
            assertTrue(first.certificate.certificate().getExtendedKeyUsage().contains("1.3.6.1.5.5.7.3.1"));
        } finally { first.saveDigest(null); }
    }
    @Test public void nativePairingProtectsOnlyVisibleCredentials() throws Exception {
        MainActivity activity = (MainActivity) instrumentation.startActivitySync(new Intent(context, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        try {
            until(() -> main(() -> activity.getWindow().getDecorView().getWidth() > 0));
            assertFalse(main(() -> (activity.getWindow().getAttributes().flags & WindowManager.LayoutParams.FLAG_SECURE) != 0));
            main(() -> { context.startForegroundService(new Intent(context, ReceiverService.class)); return null; });
            until(() -> ReceiverService.instance != null && ReceiverService.instance.server != null);
            until(() -> main(() -> (activity.getWindow().getAttributes().flags & WindowManager.LayoutParams.FLAG_SECURE) != 0));
            assertTrue(main(() -> ReceiverService.instance.pairingUri(ReceiverService.instance.identity.addresses.get(0)).startsWith("sofatap://tv?")));
        } finally { main(() -> { context.stopService(new Intent(context, ReceiverService.class)); activity.finish(); return null; }); }
    }
    @Test public void realAccessibilityClickScrollAndDisconnectOnTvEmulator() throws Exception {
        String previous = shell("settings get secure enabled_accessibility_services");
        String enabled = shell("settings get secure accessibility_enabled");
        InputFixtureActivity fixture = null;
        try {
            shell("settings put secure enabled_accessibility_services com.chekusu.sofatap.tv/.input.SofatapAccessibilityService");
            shell("settings put secure accessibility_enabled 1");
            until(() -> snapshot().optBoolean("inputAvailable"));
            assertTrue("Fixture must be the TV system image", context.getPackageManager().hasSystemFeature("android.hardware.type.television"));
            fixture = (InputFixtureActivity) instrumentation.startActivitySync(new Intent(context, InputFixtureActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            final InputFixtureActivity target = fixture;
            until(() -> main(() -> target.click.getWidth() > 0) && snapshot().optBoolean("activeWindowReadable"));
            SystemClock.sleep(300);
            Rect button = main(() -> { Rect r = new Rect(); target.click.getGlobalVisibleRect(r); return r; });
            moveTo(button.centerX(), button.centerY());
            JSONObject click = input("click", 0, 0); assertTrue(click.toString(), click.getBoolean("ok"));
            until(() -> main(() -> target.clicks == 1));
            Rect area = main(() -> { Rect r = new Rect(); target.scroll.getGlobalVisibleRect(r); return r; });
            moveTo(area.centerX(), area.centerY());
            JSONObject scroll = input("scroll", 0, 80); assertTrue(scroll.toString(), scroll.getBoolean("ok"));
            until(() -> main(() -> target.scroll.getScrollY() > 0));
            assertTrue(snapshot().getBoolean("cursorVisible"));
            main(() -> { InputBridge.disconnect(); return null; });
            assertFalse(snapshot().getBoolean("cursorVisible"));
            shell("settings put secure enabled_accessibility_services null");
            until(() -> !snapshot().optBoolean("inputAvailable"));
            assertFalse(input("click", 0, 0).getBoolean("ok"));
            assertEquals(1, (int) main(() -> target.clicks));
        } finally {
            if (fixture != null) { final Activity a = fixture; main(() -> { a.finish(); return null; }); }
            if ("null".equals(previous)) shell("settings delete secure enabled_accessibility_services");
            else shell("settings put secure enabled_accessibility_services '" + previous.replace("'", "'\\''") + "'");
            if ("null".equals(enabled)) shell("settings delete secure accessibility_enabled");
            else shell("settings put secure accessibility_enabled " + ("1".equals(enabled) ? "1" : "0"));
        }
    }
}
