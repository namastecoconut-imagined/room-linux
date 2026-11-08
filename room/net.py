"""Tiny async HTTP on Qt's own network stack — everything runs on the UI thread's event loop, no threads to juggle."""
import json
from urllib.parse import urlencode

from PySide6.QtCore import QByteArray, QUrl
from PySide6.QtNetwork import QNetworkAccessManager, QNetworkReply, QNetworkRequest

_nam: QNetworkAccessManager | None = None


def nam() -> QNetworkAccessManager:
    global _nam
    if _nam is None:
        _nam = QNetworkAccessManager()
    return _nam


def request(method: str, url: str, done=None, headers: dict | None = None, body: bytes | None = None, timeout_ms: int = 12000):
    """done(status:int, data:bytes) — status 0 means it never got an answer."""
    req = QNetworkRequest(QUrl(url))
    req.setTransferTimeout(timeout_ms)
    req.setAttribute(QNetworkRequest.Attribute.RedirectPolicyAttribute,
                     QNetworkRequest.RedirectPolicy.NoLessSafeRedirectPolicy)
    for k, v in (headers or {}).items():
        req.setRawHeader(k.encode(), v.encode())
    payload = QByteArray(body or b"")
    m = method.upper()
    if m == "GET":
        reply = nam().get(req)
    elif m == "POST":
        reply = nam().post(req, payload)
    elif m == "PUT":
        reply = nam().put(req, payload)
    else:
        reply = nam().sendCustomRequest(req, m.encode(), payload)

    def finished():
        status = reply.attribute(QNetworkRequest.Attribute.HttpStatusCodeAttribute) or 0
        data = bytes(reply.readAll().data())
        if reply.error() != QNetworkReply.NetworkError.NoError and not status:
            status = 0
        reply.deleteLater()
        if done:
            try:
                done(int(status), data)
            except Exception as e:
                print(f"[room] error handling {url[:60]}: {e}")

    reply.finished.connect(finished)
    return reply


def get_json(url: str, done, headers: dict | None = None):
    def cb(status, data):
        obj = None
        if status == 200:
            try:
                obj = json.loads(data)
            except Exception:
                obj = None
        done(obj)
    return request("GET", url, cb, headers)


def form(d: dict) -> bytes:
    return urlencode(d).encode()
