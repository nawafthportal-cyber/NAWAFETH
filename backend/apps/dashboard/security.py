from __future__ import annotations

from django.http.request import split_domain_port
from django.utils.http import url_has_allowed_host_and_scheme


def is_safe_redirect_url(url: str | None, *, allowed_hosts: set[str] | None = None) -> bool:
    value = (url or "").strip()
    if not value:
        return False
    if value.startswith("//"):
        return False
    if value.startswith("/") and not value.startswith("//"):
        return True
    if allowed_hosts is None:
        allowed_hosts = set()
    host = split_domain_port(value)[0]
    if host:
        allowed_hosts = set(allowed_hosts)
        allowed_hosts.add(host)
    return url_has_allowed_host_and_scheme(value, allowed_hosts=allowed_hosts, require_https=False)

