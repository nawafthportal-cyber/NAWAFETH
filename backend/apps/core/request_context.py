from __future__ import annotations

from contextvars import ContextVar
from dataclasses import dataclass


_request_id_var: ContextVar[str] = ContextVar("request_id", default="-")
_request_path_var: ContextVar[str] = ContextVar("request_path", default="-")


@dataclass(frozen=True)
class RequestContextToken:
    request_id: object
    request_path: object


def bind_request_context(*, request_id: str, request_path: str) -> RequestContextToken:
    return RequestContextToken(
        request_id=_request_id_var.set(request_id or "-"),
        request_path=_request_path_var.set(request_path or "-"),
    )


def clear_request_context(token: RequestContextToken) -> None:
    _request_id_var.reset(token.request_id)
    _request_path_var.reset(token.request_path)


def get_request_id() -> str:
    return _request_id_var.get()


def get_request_path() -> str:
    return _request_path_var.get()
