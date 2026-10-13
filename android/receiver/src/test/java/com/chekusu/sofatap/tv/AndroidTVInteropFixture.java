package com.chekusu.sofatap.tv;

import okhttp3.tls.HeldCertificate;
import org.json.JSONArray;
import org.json.JSONObject;
import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.nio.file.attribute.PosixFilePermissions;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.BooleanSupplier;

/** Short-lived interop fixture. Counts actions only; never accesses desktop/device input. */
public final class AndroidTVInteropFixture {
    public static void main(String[] args) throws Exception {
        if (args.length != 2) throw new IllegalArgumentException("Expected bind IPv4 and private temporary directory");
        InetAddress bind = InetAddress.getByName(args[0]);
        if (!(bind instanceof Inet4Address) || !bind.isSiteLocalAddress() || bind.isLoopbackAddress())
            throw new IllegalArgumentException("A private LAN IPv4 is required by the production pairing parser");
        Path directory = Path.of(args[1]).toAbsolutePath();
        if (!Files.isDirectory(directory)) throw new IllegalArgumentException("Caller must create private temporary directory");
        Files.setPosixFilePermissions(directory, PosixFilePermissions.fromString("rwx------"));
        HeldCertificate certificate = ReceiverCertificate.generate(Collections.singletonList(bind.getHostAddress()));
        KeyStore keys = KeyStore.getInstance(KeyStore.getDefaultType()); keys.load(null);
        keys.setKeyEntry("test", certificate.keyPair().getPrivate(), "test-only".toCharArray(),
            new java.security.cert.Certificate[]{certificate.certificate()});
        KeyManagerFactory manager = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        manager.init(keys, "test-only".toCharArray());
        SSLContext tls = SSLContext.getInstance("TLS"); tls.init(manager.getKeyManagers(), null, null);
        PairingAuthority authority = new PairingAuthority(null, System::currentTimeMillis, digest -> {});
        String bootstrap = authority.newPairing(); CountingInput input = new CountingInput(directory);
        ReceiverServer server = new ReceiverServer(tls, bind, 0, authority, input, "Sofatap test fixture");
        String pin = PairingAuthority.hex(MessageDigest.getInstance("SHA-256").digest(certificate.certificate().getEncoded()));
        String qr = "sofatap://tv?host=" + bind.getHostAddress() + "&port=" + server.port()
            + "&token=" + bootstrap + "&fingerprint=" + pin;
        Runtime.getRuntime().addShutdownHook(new Thread(server::close, "Sofatap-fixture-cleanup"));
        server.start();
        try {
            write(directory.resolve("stats.json"), input.stats(authority, server));
            write(directory.resolve("fixture.json"), new JSONObject().put("qr", qr)
                .put("host", bind.getHostAddress()).put("port", server.port()).put("pin", pin));
            long until = System.nanoTime() + TimeUnit.SECONDS.toNanos(60);
            while (!Files.exists(directory.resolve("stop")) && System.nanoTime() < until) {
                write(directory.resolve("stats.json"), input.stats(authority, server));
                Thread.sleep(100);
            }
        } finally {
            server.close();
            write(directory.resolve("stats.json"), input.stats(authority, server));
        }
    }

    private static final class CountingInput implements ReceiverServer.Input {
        private final Path directory;
        private final List<JSONObject> actions = new ArrayList<>();
        private final AtomicInteger snapshots = new AtomicInteger(), disconnects = new AtomicInteger();
        CountingInput(Path directory) { this.directory = directory; }
        @Override public JSONObject snapshot() throws Exception {
            snapshots.incrementAndGet(); boolean ready = !Files.exists(directory.resolve("block-input"));
            JSONObject capabilities = new JSONObject();
            for (String key : Arrays.asList("overlayCursor", "nodeClick", "scroll", "back", "home", "directionalFocus"))
                capabilities.put(key, ready);
            for (String key : Arrays.asList("text", "rawMouse", "rightClick", "drag")) capabilities.put(key, false);
            return new JSONObject().put("inputAvailable", ready)
                .put("inputStatus", ready ? "ready" : "accessibility_required").put("capabilities", capabilities);
        }
        @Override public synchronized JSONObject apply(TVProtocol.Action action, BooleanSupplier current) throws Exception {
            if (!current.getAsBoolean() || Files.exists(directory.resolve("block-input")))
                return new JSONObject().put("ok", false).put("code", "accessibility_required");
            JSONObject entry = new JSONObject().put("type", action.type()).put("dx", action.dx()).put("dy", action.dy());
            if (action.key() != null) entry.put("key", action.key());
            actions.add(entry); return new JSONObject().put("ok", true);
        }
        @Override public void disconnected() { disconnects.incrementAndGet(); }
        synchronized JSONObject stats(PairingAuthority authority, ReceiverServer server) throws Exception {
            return new JSONObject().put("paired", authority.paired()).put("actions", new JSONArray(actions))
                .put("snapshots", snapshots.get()).put("disconnects", disconnects.get()).put("connected", server.connected());
        }
    }

    private static void write(Path path, JSONObject value) throws Exception {
        Path temporary = Files.createTempFile(path.getParent(), ".sofatap-", ".json",
            PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------")));
        try {
            Files.write(temporary, value.toString().getBytes(StandardCharsets.UTF_8));
            Files.move(temporary, path, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
        } finally { Files.deleteIfExists(temporary); }
    }
}
