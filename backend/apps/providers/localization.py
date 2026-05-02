from __future__ import annotations

from .location_formatter import CITY_SCOPE_SEPARATOR, _clean_text, _lookup_region_for_city, _strip_region_prefix, split_city_scope


CATEGORY_NAME_EN = {
    "تصميم مواقع الويب": "Web Design",
    "صيانة": "Maintenance",
    "صيانة منزليه": "Home Maintenance",
    "صيانة منزلية": "Home Maintenance",
    "خدمات منزلية": "Home Services",
    "تنظيف": "Cleaning",
    "فعاليات وضيافة": "Events & Hospitality",
    "إبداع وتصميم": "Creativity & Design",
    "تقنية": "Technology",
    "استشارات": "Consulting",
    "الصحة والعافية": "Health & Wellness",
    "تعليم وتدريب": "Education & Training",
    "نقل وخدمات": "Moving & Services",
}

SUBCATEGORY_NAME_EN = {
    "تصميم صفحة هبوط": "Landing Page Design",
    "تصميم الواجهات": "UI Design",
    "سباكة": "Plumbing",
    "كهرباء": "Electrical",
    "تكييف وتبريد": "Air Conditioning & Refrigeration",
    "تنظيف منازل": "Home Cleaning",
    "تنظيم مناسبات": "Event Planning",
    "تصوير فوتوغرافي": "Photography",
    "تصميم داخلي": "Interior Design",
    "تطوير مواقع": "Website Development",
    "دعم تقني وشبكات": "Technical Support & Networks",
    "استشارات قانونية": "Legal Consultation",
    "علاج طبيعي": "Physical Therapy",
    "تدريب شخصي": "Personal Training",
    "دروس خصوصية": "Private Tutoring",
    "تدريب مهني": "Professional Training",
    "نقل أثاث": "Furniture Moving",
}

REGION_NAME_EN = {
    "الرياض": "Riyadh",
    "مكة المكرمة": "Makkah",
    "المدينة المنورة": "Madinah",
    "الشرقية": "Eastern Province",
    "القصيم": "Qassim",
    "عسير": "Asir",
    "تبوك": "Tabuk",
    "حائل": "Hail",
    "الجوف": "Al Jawf",
    "الحدود الشمالية": "Northern Borders",
    "نجران": "Najran",
    "جازان": "Jazan",
    "الباحة": "Al Bahah",
}

CITY_NAME_EN = {
    "الرياض": "Riyadh",
    "الخرج": "Al Kharj",
    "الدلم": "Ad Dilam",
    "الدرعية": "Diriyah",
    "الدوادمي": "Ad Dawadimi",
    "الزلفي": "Az Zulfi",
    "السليل": "As Sulayyil",
    "القويعية": "Al Quwayiyah",
    "المجمعة": "Al Majma'ah",
    "المزاحمية": "Al Muzahimiyah",
    "ثادق": "Thadiq",
    "حوطة بني تميم": "Hawtat Bani Tamim",
    "شقراء": "Shaqra",
    "ضرما": "Dharma",
    "عفيف": "Afif",
    "الأفلاج": "Al Aflaj",
    "مكة المكرمة": "Makkah",
    "جدة": "Jeddah",
    "الطائف": "Taif",
    "الجموم": "Al Jumum",
    "رابغ": "Rabigh",
    "القنفذة": "Al Qunfudhah",
    "الليث": "Al Lith",
    "تربة": "Turbah",
    "رنية": "Ranyah",
    "ظلم": "Dhalm",
    "المدينة المنورة": "Madinah",
    "ينبع": "Yanbu",
    "بدر": "Badr",
    "خيبر": "Khaybar",
    "العلا": "AlUla",
    "الدمام": "Dammam",
    "الخبر": "Khobar",
    "الظهران": "Dhahran",
    "الأحساء": "Al Ahsa",
    "الجبيل": "Jubail",
    "الخفجي": "Al Khafji",
    "القطيف": "Qatif",
    "حفر الباطن": "Hafar Al Batin",
    "بريدة": "Buraidah",
    "عنيزة": "Unaizah",
    "الرس": "Ar Rass",
    "البكيرية": "Al Bukayriyah",
    "البدائع": "Al Badayi",
    "المذنب": "Al Mithnab",
    "أبها": "Abha",
    "خميس مشيط": "Khamis Mushait",
    "بيشة": "Bisha",
    "محايل عسير": "Muhayil Asir",
    "النماص": "An Namas",
    "تنومة": "Tanomah",
    "سراة عبيدة": "Sarat Ubaydah",
    "تبوك": "Tabuk",
    "ضباء": "Duba",
    "الوجه": "Al Wajh",
    "حقل": "Haql",
    "أملج": "Umluj",
    "حائل": "Hail",
    "سكاكا": "Sakaka",
    "القريات": "Al Qurayyat",
    "طبرجل": "Tabarjal",
    "عرعر": "Arar",
    "رفحاء": "Rafha",
    "طريف": "Turaif",
    "نجران": "Najran",
    "شرورة": "Sharurah",
    "جازان": "Jazan",
    "صامطة": "Samtah",
    "صبيا": "Sabya",
    "الباحة": "Al Bahah",
    "بلجرشي": "Baljurashi",
    "العرضيات": "Al Ardiyat",
}


def translate_category_name(value: str | None) -> str:
    normalized = _clean_text(value)
    if not normalized:
        return ""
    return CATEGORY_NAME_EN.get(normalized, normalized)


def translate_subcategory_name(value: str | None) -> str:
    normalized = _clean_text(value)
    if not normalized:
        return ""
    return SUBCATEGORY_NAME_EN.get(normalized, normalized)


def translate_region_name(value: str | None) -> str:
    normalized = _strip_region_prefix(value or "")
    if not normalized:
        return ""
    return REGION_NAME_EN.get(normalized, normalized)


def translate_city_name(value: str | None) -> str:
    normalized = _clean_text(value)
    if not normalized:
        return ""
    return CITY_NAME_EN.get(normalized, normalized)


def format_city_display_en(city: str | None, *, region: str = "") -> str:
    normalized_city = _clean_text(city)
    normalized_region = _strip_region_prefix(region)

    if not normalized_city:
        return ""
    if CITY_SCOPE_SEPARATOR in normalized_city:
        scope_region, scope_city = split_city_scope(normalized_city)
        city_en = translate_city_name(scope_city)
        region_en = translate_region_name(scope_region)
        if not city_en:
            return ""
        if region_en:
            return f"{region_en}{CITY_SCOPE_SEPARATOR}{city_en}"
        return city_en

    city_en = translate_city_name(normalized_city)
    if normalized_region:
        region_en = translate_region_name(normalized_region)
        if region_en and region_en != city_en:
          return f"{region_en}{CITY_SCOPE_SEPARATOR}{city_en}"
        return city_en

    inferred_region = _lookup_region_for_city(normalized_city)
    inferred_region_en = translate_region_name(inferred_region)
    if inferred_region_en and inferred_region_en != city_en:
        return f"{inferred_region_en}{CITY_SCOPE_SEPARATOR}{city_en}"
    return city_en