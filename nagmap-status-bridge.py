#!/usr/bin/env python3
# Bridges Naemon's Livestatus to the classic Nagios status.dat format that
# nagmapReborn's status parser expects (src/NagmapReborn/functions.php:ngrebornStatus()).
# Naemon Core no longer writes status.dat itself (status_file is a no-op),
# so this script polls Livestatus and regenerates the file periodically.

import os
import socket
import tempfile

LIVESTATUS_SOCKET = "/omd/sites/default/tmp/run/live"
STATUS_FILE = "/omd/sites/default/var/naemon/status.dat"


def query(request):
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(LIVESTATUS_SOCKET)
    sock.sendall(request.encode())
    sock.shutdown(socket.SHUT_WR)
    chunks = []
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            break
        chunks.append(chunk)
    sock.close()
    return b"".join(chunks).decode(errors="replace")


def main():
    lines = []

    for row in query("GET hosts\nColumns: name state\n\n").splitlines():
        if not row:
            continue
        name, state = row.split(";")
        lines += ["hoststatus {", f"host_name={name}", f"current_state={state}", "}"]

    for row in query("GET services\nColumns: host_name description state\n\n").splitlines():
        if not row:
            continue
        host, description, state = row.split(";", 2)
        lines += [
            "servicestatus {",
            f"host_name={host}",
            f"service_description={description}",
            f"current_state={state}",
            "}",
        ]

    fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(STATUS_FILE))
    try:
        with os.fdopen(fd, "w") as f:
            f.write("\n".join(lines) + "\n")
        os.chmod(tmp_path, 0o644)
        os.replace(tmp_path, STATUS_FILE)
    except BaseException:
        os.unlink(tmp_path)
        raise


if __name__ == "__main__":
    main()
