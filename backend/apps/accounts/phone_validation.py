import re


LOCAL05_PHONE_PATTERN = re.compile(r"^05\d{8}$")
LOCAL05_PHONE_ERROR = "رقم الجوال يجب أن يكون 10 خانات ويبدأ بـ 05"


def keep_digits(value: str) -> str:
    return "".join(ch for ch in str(value or "") if ch.isdigit())


def normalize_phone_local05(phone: str) -> str:
    raw = str(phone or "").strip()
    digits = keep_digits(raw)

    if len(digits) == 10 and digits.startswith("05"):
        return digits
    if len(digits) == 9 and digits.startswith("5"):
        return f"0{digits}"
    if len(digits) == 12 and digits.startswith("9665"):
        return f"0{digits[3:]}"
    if len(digits) == 14 and digits.startswith("009665"):
        return f"0{digits[5:]}"

    return digits or raw


def is_valid_phone_local05(phone: str) -> bool:
    digits = keep_digits(phone)
    return bool(LOCAL05_PHONE_PATTERN.fullmatch(digits))


def require_phone_local05(
    value: str,
    *,
    allow_blank: bool = False,
    blank_error: str | None = None,
    invalid_error: str | None = None,
) -> str:
    raw = str(value or "").strip()
    if not raw:
        if allow_blank:
            return ""
        raise ValueError(blank_error or "رقم الجوال مطلوب")

    digits = keep_digits(raw)
    if not LOCAL05_PHONE_PATTERN.fullmatch(digits):
        raise ValueError(invalid_error or LOCAL05_PHONE_ERROR)
    return digits