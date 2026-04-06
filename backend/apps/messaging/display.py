import re


TEAM_NAME_RE = re.compile(r"رسالة(?:\s+آلية)?\s+من\s+(فريق\s+[^\n\r\.,،:؛]+)")


def extract_platform_team_name(message_body: str | None) -> str:
    text = str(message_body or "").strip()
    if not text:
        return ""
    match = TEAM_NAME_RE.search(text)
    if not match:
        return ""
    return (match.group(1) or "").strip()


def display_name_for_user(user, *, message_body: str | None = None, sender_team_name: str | None = None) -> str:
    if not user:
        return ""

    explicit_team_name = str(sender_team_name or "").strip()
    if explicit_team_name:
        return explicit_team_name

    if getattr(user, "is_staff", False):
        return extract_platform_team_name(message_body) or "فريق المنصة"

    first = (getattr(user, "first_name", "") or "").strip()
    last = (getattr(user, "last_name", "") or "").strip()
    full = ("%s %s" % (first, last)).strip()
    if full:
        return full

    username = (getattr(user, "username", "") or "").strip()
    if username:
        return username

    return getattr(user, "phone", "") or str(user)