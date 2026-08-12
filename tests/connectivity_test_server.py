#!/usr/bin/env python3

import argparse
import base64
import hashlib
import json
import os
import signal
import socket
import socketserver
import struct
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


WEBSOCKET_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


class HTTPHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_POST(self):
        if self.path != "/echo":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        self.send_response(201)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-GF-Test", "echo")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format, *_args):
        pass


class WebSocketHandler(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(10.0)
        headers = self._read_headers()
        key = headers.get("sec-websocket-key", "")
        if not key:
            return
        accept = base64.b64encode(
            hashlib.sha1((key + WEBSOCKET_GUID).encode("ascii")).digest()
        ).decode("ascii")
        response = [
            "HTTP/1.1 101 Switching Protocols",
            "Upgrade: websocket",
            "Connection: Upgrade",
            f"Sec-WebSocket-Accept: {accept}",
        ]
        protocols = [
            value.strip()
            for value in headers.get("sec-websocket-protocol", "").split(",")
            if value.strip()
        ]
        if "gf-test" in protocols:
            response.append("Sec-WebSocket-Protocol: gf-test")
        self.request.sendall(("\r\n".join(response) + "\r\n\r\n").encode("ascii"))

        while True:
            frame = self._read_frame()
            if frame is None:
                return
            opcode, payload = frame
            if opcode == 0x8:
                self._write_frame(0x8, payload)
                return
            if opcode == 0x9:
                self._write_frame(0xA, payload)
            elif opcode in (0x1, 0x2):
                self._write_frame(opcode, payload)

    def _read_headers(self):
        data = bytearray()
        while b"\r\n\r\n" not in data and len(data) < 65536:
            chunk = self.request.recv(4096)
            if not chunk:
                break
            data.extend(chunk)
        lines = bytes(data).decode("latin-1").split("\r\n")
        headers = {}
        for line in lines[1:]:
            if ":" in line:
                name, value = line.split(":", 1)
                headers[name.strip().lower()] = value.strip()
        return headers

    def _read_exact(self, size):
        data = bytearray()
        while len(data) < size:
            chunk = self.request.recv(size - len(data))
            if not chunk:
                return None
            data.extend(chunk)
        return bytes(data)

    def _read_frame(self):
        header = self._read_exact(2)
        if header is None:
            return None
        opcode = header[0] & 0x0F
        masked = bool(header[1] & 0x80)
        length = header[1] & 0x7F
        if length == 126:
            raw_length = self._read_exact(2)
            if raw_length is None:
                return None
            length = struct.unpack("!H", raw_length)[0]
        elif length == 127:
            raw_length = self._read_exact(8)
            if raw_length is None:
                return None
            length = struct.unpack("!Q", raw_length)[0]
        mask = self._read_exact(4) if masked else None
        payload = self._read_exact(length)
        if payload is None:
            return None
        if mask is not None:
            payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
        return opcode, payload

    def _write_frame(self, opcode, payload):
        header = bytearray([0x80 | opcode])
        length = len(payload)
        if length < 126:
            header.append(length)
        elif length <= 0xFFFF:
            header.append(126)
            header.extend(struct.pack("!H", length))
        else:
            header.append(127)
            header.extend(struct.pack("!Q", length))
        self.request.sendall(bytes(header) + payload)


class ThreadingTCPServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ready-file", required=True)
    args = parser.parse_args()

    http_server = ThreadingHTTPServer(("127.0.0.1", 0), HTTPHandler)
    websocket_server = ThreadingTCPServer(("127.0.0.1", 0), WebSocketHandler)
    stop_event = threading.Event()

    def stop(_signum, _frame):
        stop_event.set()

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    threads = [
        threading.Thread(target=http_server.serve_forever, daemon=True),
        threading.Thread(target=websocket_server.serve_forever, daemon=True),
    ]
    for thread in threads:
        thread.start()

    ready = {
        "http_url": f"http://127.0.0.1:{http_server.server_port}/echo",
        "websocket_url": f"ws://127.0.0.1:{websocket_server.server_address[1]}/echo",
    }
    temp_path = args.ready_file + ".tmp"
    with open(temp_path, "w", encoding="utf-8") as file:
        json.dump(ready, file)
        file.flush()
        os.fsync(file.fileno())
    os.replace(temp_path, args.ready_file)

    stop_event.wait()
    http_server.shutdown()
    websocket_server.shutdown()
    http_server.server_close()
    websocket_server.server_close()


if __name__ == "__main__":
    main()
