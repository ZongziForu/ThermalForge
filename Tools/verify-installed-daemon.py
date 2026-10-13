#!/usr/bin/env python3
"""Read-only install check: query the version over the real daemon protocol."""
import json
import socket
import struct
import sys


def receive(connection, size):
    result = b""
    while len(result) < size:
        chunk = connection.recv(size - len(result))
        if not chunk:
            raise RuntimeError("Daemon closed the response early")
        result += chunk
    return result


def daemon_version():
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(3)
        connection.connect("/var/run/thermalforge.sock")
        body = json.dumps({"v": 1, "verb": "version", "oneshot": False}).encode()
        connection.sendall(struct.pack(">I", len(body)) + body)
        size = struct.unpack(">I", receive(connection, 4))[0]
        if size > 64 * 1024:
            raise RuntimeError("Daemon response exceeds protocol limit")
        response = json.loads(receive(connection, size))
        if response.get("ok") is not True or response.get("v") != 1:
            raise RuntimeError("Daemon returned an unsuccessful protocol response")
        return response.get("version")


if __name__ == "__main__":
    try:
        expected = sys.argv[1]
        actual = daemon_version()
        if actual != expected:
            raise RuntimeError(f"Expected daemon {expected}, got {actual}")
        print(f"Running daemon verified: {actual}")
    except (IndexError, OSError, ValueError, RuntimeError) as error:
        print(f"Install check failed: {error}", file=sys.stderr)
        sys.exit(1)
