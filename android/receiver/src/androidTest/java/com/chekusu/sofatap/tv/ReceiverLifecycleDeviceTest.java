package com.chekusu.sofatap.tv;

import android.app.Instrumentation;
import android.os.Build;
import android.os.Looper;
import android.os.StrictMode;
import android.os.SystemClock;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import okhttp3.tls.HandshakeCertificates;
import okhttp3.tls.HeldCertificate;
import org.json.JSONObject;
import org.junit.Assume;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import javax.net.ssl.SSLException;
import javax.net.ssl.SSLParameters;
import javax.net.ssl.SSLSocket;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.EOFException;
import java.io.IOException;
import java.net.InetAddress;
import java.net.SocketException;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BooleanSupplier;
import static org.junit.Assert.*;

/** Real Android TLS teardown with an isolated listener and no service, saved identity or system input. */
@RunWith(AndroidJUnit4.class)
public final class ReceiverLifecycleDeviceTest {
    private Instrumentation instrumentation;

    @Before public void disposableEmulatorOnly() {
        instrumentation = InstrumentationRegistry.getInstrumentation();
        Assume.assumeTrue("Only the owned disposable emulator is allowed",
            "yes".equals(InstrumentationRegistry.getArguments().getString("disposableEmulator")) &&
            (Build.FINGERPRINT.contains("generic") || Build.MODEL.contains("sdk")));
        assertNotEquals("Fixture network work must stay off Android main", Looper.getMainLooper(), Looper.myLooper());
    }

    @Test public void mainThreadDisconnectInvalidatesImmediatelyAndAllowsAuthenticatedReconnect() throws Exception {
        try (Fixture fixture = new Fixture()) {
            Peer first = fixture.connect(fixture.bootstrap);
            String token = first.hello.getString("pairingToken");
            assertTrue(fixture.server.connected());
            strictMain(() -> {
                fixture.server.disconnectController();
                assertFalse("Disconnect must invalidate control before TLS cleanup", fixture.server.connected());
                fixture.server.disconnectController();
                assertEquals("Repeated disconnect must not duplicate notification", 1, fixture.disconnected.get());
            });
            first.assertClosed();
            assertEquals(1, fixture.disconnected.get());

            Peer resumed = fixture.connect(token);
            assertFalse("Reconnect must retain the existing in-memory credential", resumed.hello.has("pairingToken"));
            assertTrue(fixture.server.connected());
            assertEquals("Old worker teardown must not disconnect the resumed session", 1, fixture.disconnected.get());
            strictMain(() -> {
                fixture.server.disconnectController();
                assertFalse(fixture.server.connected());
            });
            resumed.assertClosed();
            assertEquals("Each authenticated session disconnects exactly once", 2, fixture.disconnected.get());
            assertEquals(0, fixture.applied.get());
        }
    }

    @Test public void mainThreadCloseWithLiveTlsIsImmediateAndIdempotent() throws Exception {
        try (Fixture fixture = new Fixture()) {
            Peer peer = fixture.connect(fixture.bootstrap);
            assertTrue(fixture.server.connected());
            strictMain(() -> {
                fixture.server.close();
                assertFalse("Server close must invalidate control before returning", fixture.server.connected());
                fixture.server.close();
                fixture.server.disconnectController();
                assertEquals(1, fixture.disconnected.get());
            });
            peer.assertClosed();
            assertEquals("Worker finally must not emit a second disconnect", 1, fixture.disconnected.get());
            assertEquals(0, fixture.applied.get());
        }
    }

    private void strictMain(Runnable action) throws Exception {
        AtomicReference<Throwable> failure = new AtomicReference<>();
        instrumentation.runOnMainSync(() -> {
            StrictMode.ThreadPolicy previous = StrictMode.getThreadPolicy();
            try {
                StrictMode.setThreadPolicy(new StrictMode.ThreadPolicy.Builder(previous)
                    .detectNetwork().penaltyDeathOnNetwork().build());
                action.run();
            } catch (Throwable problem) { failure.set(problem); }
            finally { StrictMode.setThreadPolicy(previous); }
        });
        Throwable problem = failure.get();
        if (problem instanceof Exception) throw (Exception) problem;
        if (problem instanceof Error) throw (Error) problem;
        if (problem != null) throw new AssertionError(problem);
    }

    private static final class Fixture implements AutoCloseable {
        final AtomicInteger applied = new AtomicInteger(), disconnected = new AtomicInteger();
        final PairingAuthority authority;
        final String bootstrap;
        final ReceiverServer server;
        final HandshakeCertificates clientCertificates;
        final List<SSLSocket> sockets = new ArrayList<>();

        Fixture() throws Exception {
            HeldCertificate leaf = ReceiverCertificate.generate(Collections.singletonList("127.0.0.1"));
            HandshakeCertificates serverCertificates = new HandshakeCertificates.Builder().heldCertificate(leaf).build();
            clientCertificates = new HandshakeCertificates.Builder().addTrustedCertificate(leaf.certificate()).build();
            authority = new PairingAuthority(null, SystemClock::elapsedRealtime, digest -> { });
            bootstrap = authority.newPairing();
            server = new ReceiverServer(serverCertificates.sslContext(), InetAddress.getByName("127.0.0.1"), 0,
                authority, new ReceiverServer.Input() {
                    @Override public JSONObject snapshot() throws Exception { return new JSONObject().put("ready", true); }
                    @Override public JSONObject apply(TVProtocol.Action action, BooleanSupplier current) throws Exception {
                        applied.incrementAndGet();
                        return new JSONObject().put("ok", false).put("code", "fixture_has_no_input");
                    }
                    @Override public void disconnected() { disconnected.incrementAndGet(); }
                }, "Lifecycle fixture");
            server.start();
        }

        Peer connect(String token) throws Exception {
            SSLSocket socket = (SSLSocket) clientCertificates.sslSocketFactory().createSocket("127.0.0.1", server.port());
            sockets.add(socket);
            socket.setSoTimeout(3000);
            SSLParameters parameters = socket.getSSLParameters();
            parameters.setEndpointIdentificationAlgorithm("HTTPS");
            socket.setSSLParameters(parameters);
            socket.startHandshake();
            socket.getOutputStream().write(("GET /control HTTP/1.1\r\nHost: 127.0.0.1:" + server.port() + "\r\n"
                + "Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\n"
                + "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nAuthorization: Bearer " + token + "\r\n\r\n")
                .getBytes(StandardCharsets.US_ASCII));
            socket.getOutputStream().flush();
            DataInputStream input = new DataInputStream(socket.getInputStream());
            ByteArrayOutputStream headers = new ByteArrayOutputStream();
            int suffix = 0;
            while (headers.size() < 8192 && suffix != 0x0d0a0d0a) {
                int next = input.read();
                if (next < 0) throw new EOFException("Missing fixture WebSocket upgrade");
                headers.write(next); suffix = (suffix << 8) | next;
            }
            assertEquals("Bounded complete upgrade response", 0x0d0a0d0a, suffix);
            assertTrue("Fixture authentication must succeed", headers.toString("US-ASCII").startsWith("HTTP/1.1 101 "));
            int opcode = input.readUnsignedByte(), length = input.readUnsignedByte();
            assertEquals("Expected one complete text hello", 0x81, opcode);
            assertEquals("Server frame must be unmasked", 0, length & 0x80);
            long size = length == 126 ? input.readUnsignedShort() : length == 127 ? input.readLong() : length;
            assertTrue("Bounded hello frame", size > 0 && size <= 65536);
            byte[] body = new byte[(int) size]; input.readFully(body);
            JSONObject hello = new JSONObject(new String(body, StandardCharsets.UTF_8));
            assertEquals("hello", hello.getString("type"));
            assertEquals("androidtv", hello.getString("platform"));
            return new Peer(socket, input, hello);
        }

        @Override public void close() {
            server.close();
            for (SSLSocket socket : sockets) {
                try { socket.close(); } catch (IOException ignored) { }
            }
        }
    }

    private static final class Peer {
        final SSLSocket socket;
        final DataInputStream input;
        final JSONObject hello;
        Peer(SSLSocket socket, DataInputStream input, JSONObject hello) {
            this.socket = socket; this.input = input; this.hello = hello;
        }
        void assertClosed() throws IOException {
            socket.setSoTimeout(3000);
            try { assertEquals("Teardown must close the TLS peer", -1, input.read()); }
            catch (SocketTimeoutException timeout) { throw new AssertionError("TLS teardown did not finish within 3 seconds", timeout); }
            catch (SocketException | SSLException closed) { /* TLS abort/reset is also a completed teardown. */ }
        }
    }
}
