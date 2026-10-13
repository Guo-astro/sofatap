package com.chekusu.sofatap.tv;

import org.json.JSONObject;
import javax.net.ssl.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BooleanSupplier;

/** Small, bounded local TLS/WebSocket endpoint for authenticated manual input only. */
public final class ReceiverServer implements AutoCloseable {
    public interface Input {
        JSONObject snapshot() throws Exception;
        JSONObject apply(TVProtocol.Action action, BooleanSupplier stillCurrent) throws Exception;
        void disconnected();
    }
    private final SSLServerSocket listener;
    private final PairingAuthority authority;
    private final Input input;
    private final String name;
    private final boolean allowLoopbackPeers;
    private final ExecutorService workers = new ThreadPoolExecutor(0, 4, 30, TimeUnit.SECONDS,
        new SynchronousQueue<>());
    private final ScheduledExecutorService deadlines = Executors.newSingleThreadScheduledExecutor();
    private final Set<Socket> sockets = ConcurrentHashMap.newKeySet();
    private final AtomicReference<Socket> controller = new AtomicReference<>();
    private volatile boolean closed;

    public ReceiverServer(SSLContext tls, InetAddress bind, int port, PairingAuthority authority,
                          Input input, String name) throws IOException {
        this.listener = (SSLServerSocket)tls.getServerSocketFactory().createServerSocket(port, 4, bind);
        this.allowLoopbackPeers = bind != null && bind.isLoopbackAddress();
        List<String> protocols = new ArrayList<>();
        for (String p : listener.getSupportedProtocols()) if (p.equals("TLSv1.2") || p.equals("TLSv1.3")) protocols.add(p);
        listener.setEnabledProtocols(protocols.toArray(new String[0]));
        this.authority = authority; this.input = input; this.name = name;
    }
    public int port() { return listener.getLocalPort(); }
    public boolean connected() { return controller.get() != null; }
    public void start() { new Thread(this::accept, "Sofatap-TV-listener").start(); }
    private void accept() {
        while (!closed) {
            try {
                SSLSocket socket = (SSLSocket)listener.accept();
                if (!allowsPeer(socket.getInetAddress(), allowLoopbackPeers)) { close(socket); continue; }
                sockets.add(socket);
                try { workers.execute(() -> handle(socket)); }
                catch (RejectedExecutionException busy) { sockets.remove(socket); close(socket); }
            } catch (IOException error) { if (!closed) close(); }
        }
    }
    public void disconnectController() { Socket socket = controller.get(); if (socket != null) close(socket); }
    static boolean allowsPeer(InetAddress address, boolean allowLoopback) {
        // Production QR endpoints are RFC1918 IPv4. Wildcard binding must not also
        // expose an authenticated control service to public IPv6 or other interfaces.
        if (allowLoopback && address.isLoopbackAddress()) return true;
        return address instanceof Inet4Address && address.isSiteLocalAddress();
    }
    private void handle(SSLSocket socket) {
        ScheduledFuture<?> expiry = null;
        try {
            // A wall-clock deadline bounds slow TLS/header senders, including dribbled bytes.
            expiry = deadlines.schedule(() -> close(socket), 5, TimeUnit.SECONDS);
            socket.setSoTimeout(5000); socket.setTcpNoDelay(true); socket.startHandshake();
            InputStream in = socket.getInputStream(); OutputStream out = socket.getOutputStream();
            Map<String, String> h = WebSocketCodec.request(in);
            if (!controller.compareAndSet(null, socket)) { reject(out, "409 Conflict"); return; }
            String auth = h.getOrDefault("authorization", "");
            long generation = authority.generation();
            PairingAuthority.Grant grant = authority.authorize(auth.startsWith("Bearer ") ? auth.substring(7) : null);
            if (!grant.allowed()) { reject(out, "401 Unauthorized"); return; }
            BooleanSupplier current = () -> !closed && !socket.isClosed() && controller.get() == socket && authority.generation() == generation;
            if (!current.getAsBoolean()) return;
            WebSocketCodec.upgrade(out, h.get("sec-websocket-key"));
            JSONObject hello = input.snapshot();
            hello.put("type", "hello").put("version", 1).put("platform", "androidtv").put("name", name);
            if (grant.replacementToken() != null) hello.put("pairingToken", grant.replacementToken());
            send(out, hello);
            expiry.cancel(false); expiry = null;
            socket.setSoTimeout(20_000);
            Map<String, Cached> seen = new HashMap<>();
            long rateStart = System.nanoTime(); int actions = 0;
            while (current.getAsBoolean()) {
                expiry = deadlines.schedule(() -> close(socket), 20, TimeUnit.SECONDS);
                String message = readMessage(in, out);
                if (message == null) return;
                expiry.cancel(false);
                // Also bound a stalled reader while writing acknowledgments.
                expiry = deadlines.schedule(() -> close(socket), 5, TimeUnit.SECONDS);
                if (System.nanoTime() - rateStart >= 1_000_000_000L) { rateStart = System.nanoTime(); actions = 0; }
                if (++actions > 240 || seen.size() >= 32_768) return;
                TVProtocol.Action action;
                try { action = TVProtocol.parse(message); }
                catch (Exception invalid) { send(out, TVProtocol.ack("", false, "invalid_action")); return; }
                String id = action.id().toLowerCase(Locale.ROOT);
                String digest = PairingAuthority.hash(message);
                Cached previous = seen.get(id);
                if (previous != null) {
                    if (!previous.digest.equals(digest)) { send(out, TVProtocol.ack(action.id(), false, "id_reused")); return; }
                    send(out, previous.ack); // Never repeat input on a duplicate.
                } else {
                    JSONObject ack;
                    if (action.type().equals("ping")) {
                        ack = input.snapshot().put("type", "ack").put("id", action.id()).put("ok", true);
                    } else {
                        if (!current.getAsBoolean()) return;
                        JSONObject result = input.apply(action, current);
                        ack = TVProtocol.ack(action.id(), result.optBoolean("ok", false),
                            result.optBoolean("ok", false) ? null : result.optString("code", "input_unavailable"));
                    }
                    if (!current.getAsBoolean()) return;
                    seen.put(id, new Cached(digest, ack)); send(out, ack);
                }
                expiry.cancel(false); expiry = null;
            }
        } catch (Exception ignored) {
            // Neither credentials nor input payloads are logged, even on malformed traffic.
        } finally {
            if (expiry != null) expiry.cancel(false);
            if (controller.compareAndSet(socket, null)) input.disconnected();
            close(socket); sockets.remove(socket);
        }
    }
    private record Cached(String digest, JSONObject ack) { }
    private static String readMessage(InputStream in, OutputStream out) throws IOException {
        ByteArrayOutputStream parts = new ByteArrayOutputStream(); boolean started = false; int frames = 0;
        while (++frames <= 256) {
            WebSocketCodec.Frame f = WebSocketCodec.read(in);
            if (f.opcode() == 8) { WebSocketCodec.write(out, 8, new byte[]{3, (byte)232}); return null; }
            if (f.opcode() == 9) { WebSocketCodec.write(out, 10, f.payload()); continue; }
            if (f.opcode() == 10) continue;
            if ((!started && f.opcode() != 1) || (started && f.opcode() != 0)) throw new IOException("invalid_fragment");
            started = true;
            if (parts.size() + f.payload().length > WebSocketCodec.MAX_MESSAGE) throw new IOException("message_too_large");
            parts.write(f.payload());
            if (f.fin()) return WebSocketCodec.text(parts.toByteArray());
        }
        throw new IOException("too_many_frames");
    }
    private static void send(OutputStream out, JSONObject message) throws IOException {
        WebSocketCodec.write(out, 1, message.toString().getBytes(StandardCharsets.UTF_8));
    }
    private static void reject(OutputStream out, String code) throws IOException {
        out.write(("HTTP/1.1 " + code + "\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.US_ASCII)); out.flush();
    }
    private static void close(Socket socket) {
        // A peer need not cooperate with TLS close_notify. Never spend the 20s
        // message timeout draining attacker data while holding the controller slot.
        try { socket.setSoTimeout(1); socket.setSoLinger(true, 0); } catch (IOException ignored) { }
        try { socket.shutdownInput(); } catch (IOException ignored) { }
        try { socket.close(); } catch (IOException ignored) { }
    }
    @Override public void close() {
        closed = true;
        try { listener.close(); } catch (IOException ignored) { }
        for (Socket socket : sockets) close(socket);
        workers.shutdownNow(); deadlines.shutdownNow();
    }
}
