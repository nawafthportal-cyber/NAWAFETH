# Sprint 2 Parity Smoke Checklist

نفذ هذه القائمة عند أي PR مؤثر على API أو على الشاشات الحرجة.

## Auth

- إرسال OTP ينجح
- التحقق من OTP يعيد access/refresh
- `me` يعرض الهاتف و`role_state`

## Profile

- فتح ملف مزود خدمة ينجح في Flutter
- فتح الملف نفسه ينجح في `mobile_web`
- الصورة/الاسم/التوثيق تظهر في القناتين

## Orders

- إنشاء طلب خدمة عادي
- ظهور الطلب في قائمة طلباتي

## Chat

- فتح direct thread
- إرسال رسالة نصية

## Plans / verification / promo / support

- فتح صفحة الباقات
- فتح بيانات التوثيق
- ظهور banner/promo placement
- إنشاء تذكرة دعم

## Baseline parity note

- لا يشترط تطابق pixel-perfect
- المطلوب في Sprint 2: تطابق contract + بقاء الـ flow صالحًا في القناتين
