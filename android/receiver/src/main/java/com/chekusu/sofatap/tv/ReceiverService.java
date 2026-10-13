package com.chekusu.sofatap.tv;

import android.app.*;
import android.content.*;
import android.os.*;
import com.chekusu.sofatap.tv.input.InputBridge;
import org.json.JSONObject;
import java.util.concurrent.*;
import java.util.function.BooleanSupplier;

/** Started from native UI only. No boot receiver, wake lock or background auto-start. */
public final class ReceiverService extends Service {
    static volatile ReceiverService instance;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService setup = Executors.newSingleThreadExecutor();
    private volatile boolean stopped;
    volatile ReceiverServer server;
    volatile ReceiverIdentity identity;
    volatile PairingAuthority authority;
    volatile String error;
    private boolean starting;

    @Override public void onCreate() {
        super.onCreate(); instance = this;
        NotificationManager manager = getSystemService(NotificationManager.class);
        manager.createNotificationChannel(new NotificationChannel("receiver", getString(R.string.app_name), NotificationManager.IMPORTANCE_LOW));
        Intent open = new Intent(this, MainActivity.class);
        PendingIntent pending = PendingIntent.getActivity(this, 0, open, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Intent stop = new Intent(this, ReceiverService.class).setAction("stop");
        PendingIntent stopPending = PendingIntent.getService(this, 1, stop, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification note = new Notification.Builder(this, "receiver").setSmallIcon(R.drawable.notification_icon)
            .setContentTitle("Sofatap").setContentText(getString(R.string.notification_active)).setContentIntent(pending)
            .setOngoing(true).addAction(new Notification.Action.Builder(null, getString(R.string.stop), stopPending).build()).build();
        startForeground(41, note);
        InputBridge.setInterruptionListener(() -> { if (server != null) server.disconnectController(); });
    }
    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && "stop".equals(intent.getAction())) { stopSelf(); return START_NOT_STICKY; }
        if (starting || server != null) return START_NOT_STICKY;
        starting = true;
        setup.execute(() -> {
            ReceiverServer candidate = null;
            try {
                ReceiverIdentity credentials = new ReceiverIdentity(this);
                PairingAuthority auth = new PairingAuthority(credentials.pairedDigest(), SystemClock::elapsedRealtime, credentials::saveDigest);
                if (!auth.paired()) auth.newPairing();
                String name = PairingUri.deviceName(Build.MODEL);
                // Preserve the existing hello frame's 128-byte display-name contract.
                if (name.getBytes(java.nio.charset.StandardCharsets.UTF_8).length > 128) name = "Android TV";
                candidate = new ReceiverServer(credentials.tls(), null, 53319, auth, new ReceiverServer.Input() {
                    @Override public JSONObject snapshot() throws Exception {
                        return onMain(() -> InputBridge.snapshot(ReceiverService.this));
                    }
                    @Override public JSONObject apply(TVProtocol.Action action, BooleanSupplier current) throws Exception {
                        return onMain(() -> {
                            if (stopped || !current.getAsBoolean()) return new JSONObject().put("ok", false).put("code", "session_ended");
                            String kind = action.type();
                            if (kind.equals("key")) {
                                kind = action.key();
                                if (kind.equals("confirm")) kind = "focus_click";
                                else if (!kind.equals("back") && !kind.equals("home")) kind = "focus_" + kind;
                            }
                            return InputBridge.perform(ReceiverService.this, kind, action.dx(), action.dy());
                        });
                    }
                    @Override public void disconnected() {
                        main.post(() -> { if (server == null || !server.connected()) InputBridge.disconnect(); });
                    }
                }, name);
                synchronized (this) {
                    if (stopped) { candidate.close(); return; }
                    identity = credentials; authority = auth; server = candidate; candidate.start();
                }
            } catch (Exception failure) {
                if (candidate != null) candidate.close();
                error = "no_private_network".equals(failure.getMessage()) ? "no_private_network" : "start_failed";
            }
        });
        return START_NOT_STICKY;
    }
    private <T> T onMain(Callable<T> action) throws Exception {
        FutureTask<T> task = new FutureTask<>(action); main.post(task);
        try { return task.get(2, TimeUnit.SECONDS); }
        finally { task.cancel(false); main.removeCallbacks(task); }
    }
    void newPairing() {
        if (authority == null || stopped) return;
        // Called by the on-TV button: revoke the previous controller first.
        server.disconnectController(); InputBridge.disconnect();
        try { authority.newPairing(); error = null; }
        catch (Exception failure) { error = "storage_failed"; stopSelf(); }
    }
    String pairingUri(String address) {
        try {
            String token = authority == null ? null : authority.bootstrap();
            if (token == null || identity == null || !identity.addresses.contains(address)) return null;
            return PairingUri.create(address, 53319, token, identity.fingerprint(), Build.MODEL);
        } catch (Exception ignored) { return null; }
    }
    @Override public void onDestroy() {
        synchronized (this) { stopped = true; if (server != null) server.close(); }
        setup.shutdownNow(); InputBridge.setInterruptionListener(null); InputBridge.disconnect();
        if (instance == this) instance = null;
        stopForeground(STOP_FOREGROUND_REMOVE); super.onDestroy();
    }
    @Override public IBinder onBind(Intent intent) { return null; }
}
