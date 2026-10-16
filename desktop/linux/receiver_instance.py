"""One receiver per logged-in account; a second launch restores its window."""

import fcntl
import os
from pathlib import Path
import socket
import stat


class ReceiverInstance:
    def __init__(self, root=None):
        runtime = os.environ.get("XDG_RUNTIME_DIR", "")
        default = (Path(runtime) / "sofatap-receiver" if runtime and Path(runtime).is_absolute()
                   else Path(f"/tmp/sofatap-receiver-{os.getuid()}"))
        self.root = Path(root) if root is not None else default
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        metadata = self.root.lstat()
        if (not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.getuid()
                or stat.S_IMODE(metadata.st_mode) & 0o077):
            raise PermissionError("Receiver runtime directory must be private")
        self.lock = None
        self.server = None
        self.path = self.root / "control.sock"

    def acquire(self, startup=False):
        descriptor = os.open(self.root / "receiver.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        self.lock = os.fdopen(descriptor, "w")
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.lock.close()
            self.lock = None
            if not startup:
                # The primary may still be starting. A failed activation never
                # starts a competing backend or removes the primary's socket.
                with socket.socket(socket.AF_UNIX) as client:
                    client.settimeout(1)
                    try:
                        client.connect(str(self.path))
                        client.sendall(b"show")
                    except OSError:
                        pass
            return False
        try:
            self.path.unlink(missing_ok=True)
            self.server = socket.socket(socket.AF_UNIX)
            self.server.bind(str(self.path))
            self.server.listen(4)
            self.server.setblocking(False)
        except Exception:
            self.close()
            raise
        return True

    def show_requested(self):
        if self.server is None:
            return False
        try:
            client, _ = self.server.accept()
        except BlockingIOError:
            return False
        with client:
            client.settimeout(0.05)
            try:
                return client.recv(8) == b"show"
            except OSError:
                return False

    def close(self):
        if self.server is not None:
            self.server.close()
            self.server = None
            self.path.unlink(missing_ok=True)
        if self.lock is not None:
            self.lock.close()
            self.lock = None
