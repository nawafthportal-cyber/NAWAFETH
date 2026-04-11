from __future__ import annotations


EXTRAS_REPORT_OPTIONS: tuple[tuple[str, str], ...] = (
    ("platform_metrics", "مؤشرات المنصة"),
    ("platform_visits", "عدد الزيارات لمنصتي"),
    ("platform_favorites", "عدد التفضيلات لمحتوى منصتي"),
    ("orders_breakdown", "عدد الطلبات (الجديدة - تحت التنفيذ - المكتملة - الملغية)"),
    ("platform_shares", "عدد مرات مشاركة منصتي"),
    ("service_requesters", "قائمة بمعرفات من طلب خدماتي"),
    ("potential_clients", "قائمة بمعرفات من تم تميزه كعميل محتمل"),
    ("content_favoriters", "قائمة بمعرفات من عمل تفضيل لمحتوى منصتي"),
    ("platform_followers", "قائمة بمعرفات من عمل متابعة لمنصتي"),
    ("content_sharers", "قائمة بمعرفات من عمل مشاركة لمنصتي"),
    ("positive_reviewers", "قائمة بمعرفات أصحاب التقييم الإيجابي لخدماتي"),
    ("content_commenters", "قائمة بمعرفات المعلقين على محتوى منصتي"),
)


EXTRAS_CLIENT_OPTIONS: tuple[tuple[str, str], ...] = (
    ("platform_clients_list", "قوائم عملاء منصتي"),
    ("historical_clients", "قائمة بجميع العملاء الذين سبق لهم تقديم طلب خدمة تشمل معرفاتهم ووسائل التواصل معهم"),
    ("all_followers", "قائمة بكل متابعي المختص"),
    ("potential_clients_contact", "قائمة بالعملاء المحتملين (المرشحين من قائمة التواصل)"),
    ("export_clients", "تصدير المعلومات إلى ملف PDF أو Excel"),
    ("list_services", "خدمات القوائم"),
    ("grouping", "التصنيف على شكل مجموعات (خدمة محددة - مهم - متكرر ...)"),
    ("bulk_messages", "إرسال الرسائل الجماعية لعملائي"),
    ("recurring_reminders", "خيار تذكير مرتبط بالعملاء وخدمتهم المتكررة (مثل الصيانة الدوري) يشمل مواعيد ورسائل تنبيه"),
    ("loyalty_program", "برنامج الولاء"),
    ("loyalty_points", "وضع نظام نقاط لعملائي مرتبط بعدد طلباتهم"),
)


EXTRAS_FINANCE_OPTIONS: tuple[tuple[str, str], ...] = (
    ("bank_qr_registration", "خدمة تسجيل الحساب البنكي للمختص (QR)"),
    ("electronic_payments", "خدمات الدفع الإلكتروني"),
    ("electronic_invoices", "الفواتير الإلكترونية لعمليات الدفع من خلال منصة مختص"),
    ("financial_statement", "كشف حساب شامل (اسم العميل - التاريخ - المبلغ المستلم - المبلغ الباقي - المبلغ النهائي)"),
    ("finance_export", "تصدير البيانات المالية للعمليات المنفذة من خلال منصة مختص إلى ملف PDF أو Excel"),
)


SECTION_TITLE_BY_KEY: dict[str, str] = {
    "reports": "التقارير",
    "clients": "إدارة العملاء",
    "finance": "الإدارة المالية",
}


OPTION_MAP_BY_SECTION_KEY: dict[str, dict[str, str]] = {
    "reports": dict(EXTRAS_REPORT_OPTIONS),
    "clients": dict(EXTRAS_CLIENT_OPTIONS),
    "finance": dict(EXTRAS_FINANCE_OPTIONS),
}


def option_items(options: tuple[tuple[str, str], ...]) -> list[dict[str, str]]:
    return [{"key": key, "label": label} for key, label in options]


def option_map(options: tuple[tuple[str, str], ...]) -> dict[str, str]:
    return {key: label for key, label in options}


def section_title_for(section_key: str) -> str:
    return SECTION_TITLE_BY_KEY.get(str(section_key or "").strip(), str(section_key or "").strip() or "-")


def option_label_for(section_key: str, option_key: str) -> str:
    section_map = OPTION_MAP_BY_SECTION_KEY.get(str(section_key or "").strip(), {})
    return section_map.get(str(option_key or "").strip(), str(option_key or "").strip() or "-")


def normalize_option_keys(raw_values: list[str], options: tuple[tuple[str, str], ...]) -> list[str]:
    allowed = set(option_map(options).keys())
    selected: list[str] = []
    for value in raw_values:
        normalized = str(value or "").strip()
        if not normalized or normalized not in allowed:
            continue
        if normalized in selected:
            continue
        selected.append(normalized)
    return selected


def selected_labels(selected_keys: list[str], options: tuple[tuple[str, str], ...]) -> list[str]:
    labels_by_key = option_map(options)
    return [labels_by_key[key] for key in selected_keys if key in labels_by_key]


def _safe_int(value, default: int, minimum: int | None = None) -> int:
    try:
        parsed = int(value)
    except Exception:
        parsed = default
    if minimum is not None and parsed < minimum:
        return minimum
    return parsed


def build_summary_sections(
    *,
    reports: dict,
    clients: dict,
    finance: dict,
) -> list[dict]:
    report_labels = selected_labels(list(reports.get("options", [])), EXTRAS_REPORT_OPTIONS)
    if reports.get("start_at"):
        report_labels.append(f"بداية التقرير: {reports['start_at']}")
    if reports.get("end_at"):
        report_labels.append(f"نهاية التقرير: {reports['end_at']}")

    client_labels = selected_labels(list(clients.get("options", [])), EXTRAS_CLIENT_OPTIONS)
    if client_labels:
        client_years = _safe_int(clients.get("subscription_years", 1), default=1, minimum=1)
        bulk_count = _safe_int(clients.get("bulk_message_count", 0), default=0, minimum=0)
        client_labels.append(f"مدة الاشتراك (بالسنوات): {client_years}")
        client_labels.append(f"عدد الرسائل الجماعية: {bulk_count}")

    finance_labels = selected_labels(list(finance.get("options", [])), EXTRAS_FINANCE_OPTIONS)
    if finance_labels:
        finance_years = _safe_int(finance.get("subscription_years", 1), default=1, minimum=1)
        finance_labels.append(f"مدة الاشتراك (بالسنوات): {finance_years}")
        qr_first_name = str(finance.get("qr_first_name", "") or "").strip()
        qr_last_name = str(finance.get("qr_last_name", "") or "").strip()
        iban = str(finance.get("iban", "") or "").strip()
        if qr_first_name:
            finance_labels.append(f"الاسم الأول: {qr_first_name}")
        if qr_last_name:
            finance_labels.append(f"الاسم الثاني: {qr_last_name}")
        if iban:
            finance_labels.append(f"IBAN: {iban}")

    return [
        {"key": "reports", "title": "التقارير", "items": report_labels},
        {"key": "clients", "title": "إدارة العملاء", "items": client_labels},
        {"key": "finance", "title": "الإدارة المالية", "items": finance_labels},
    ]
