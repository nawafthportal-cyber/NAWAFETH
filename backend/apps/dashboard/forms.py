from __future__ import annotations

from django import forms

from apps.backoffice.models import AccessLevel, AccessPermission, Dashboard
from apps.content.models import (
    LegalDocumentType,
    validate_content_block_media,
    validate_legal_document_file,
)
from apps.promo.models import (
    PromoFrequency,
    PromoOpsStatus,
    PromoPosition,
    PromoSearchScope,
    PromoServiceType,
)
from apps.promo.services import promo_min_campaign_hours, promo_min_campaign_message
from apps.support.models import SupportTeam, SupportTicketStatus


class DashboardLoginForm(forms.Form):
    username = forms.CharField(
        label="اسم المستخدم",
        max_length=64,
        widget=forms.TextInput(
            attrs={
                "class": "input-control",
                "placeholder": "اسم المستخدم أو رقم الجوال",
                "autocomplete": "username",
                "autofocus": "autofocus",
            }
        ),
    )
    password = forms.CharField(
        label="كلمة المرور",
        widget=forms.PasswordInput(
            attrs={
                "class": "input-control",
                "placeholder": "••••••••",
                "autocomplete": "current-password",
            }
        ),
    )


class DashboardOTPForm(forms.Form):
    code = forms.CharField(
        label="رمز التحقق",
        min_length=4,
        max_length=6,
        widget=forms.TextInput(
            attrs={
                "class": "input-control",
                "inputmode": "numeric",
                "autocomplete": "one-time-code",
            }
        ),
    )

    def clean_code(self):
        value = (self.cleaned_data.get("code") or "").strip()
        if not value.isdigit():
            raise forms.ValidationError("رمز التحقق يجب أن يكون أرقامًا فقط.")
        return value


class AccessProfileForm(forms.Form):
    profile_id = forms.IntegerField(required=False, widget=forms.HiddenInput())
    username = forms.CharField(
        label="اسم المستخدم",
        max_length=50,
        widget=forms.TextInput(
            attrs={
                "class": "input-control",
                "placeholder": "ثمانية حروف وارقام",
                "autocomplete": "username",
            }
        ),
    )
    mobile_number = forms.CharField(
        label="رقم الجوال",
        max_length=20,
        widget=forms.TextInput(
            attrs={
                "class": "input-control",
                "placeholder": "9665xxxxxxxx",
                "inputmode": "tel",
                "autocomplete": "tel",
            }
        ),
    )
    level = forms.ChoiceField(label="مستوى الصلاحية", choices=AccessLevel.choices)
    dashboards = forms.MultipleChoiceField(
        label="لوحات التحكم",
        required=False,
        widget=forms.CheckboxSelectMultiple,
    )
    permissions = forms.MultipleChoiceField(
        label="الصلاحيات الدقيقة",
        required=False,
        widget=forms.CheckboxSelectMultiple,
    )
    password = forms.CharField(
        label="كلمة المرور",
        required=False,
        widget=forms.PasswordInput(
            render_value=False,
            attrs={
                "class": "input-control",
                "placeholder": "كلمة مرور قوية",
                "autocomplete": "new-password",
            },
        ),
    )
    password_expiration_date = forms.DateField(
        label="تاريخ انتهاء كلمة المرور",
        required=False,
        widget=forms.DateInput(attrs={"type": "date", "class": "input-control"}),
    )
    account_revoke_date = forms.DateField(
        label="تاريخ إلغاء/سحب الحساب",
        required=False,
        widget=forms.DateInput(attrs={"type": "date", "class": "input-control"}),
    )

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["level"].widget.attrs.update({"class": "input-control"})
        dashboards = Dashboard.objects.filter(is_active=True).order_by("sort_order", "id")
        self.fields["dashboards"].choices = [(dash.code, f"{dash.code} - {dash.name_ar}") for dash in dashboards]
        permissions = AccessPermission.objects.filter(is_active=True).order_by("sort_order", "id")
        self.fields["permissions"].choices = [
            (perm.code, f"{perm.code} - {perm.name_ar}") for perm in permissions
        ]

    def clean_mobile_number(self):
        value = (self.cleaned_data.get("mobile_number") or "").strip()
        normalized = value.replace(" ", "").replace("-", "")
        if not normalized or len(normalized) < 9:
            raise forms.ValidationError("رقم الجوال غير صالح.")
        return normalized

    def clean_username(self):
        value = (self.cleaned_data.get("username") or "").strip()
        normalized = value.replace("_", "")
        if len(normalized) < 8 or not normalized.isalnum():
            raise forms.ValidationError("اسم المستخدم يجب أن يكون 8 أحرف/أرقام على الأقل وبدون رموز.")
        return value

    def clean_password(self):
        value = (self.cleaned_data.get("password") or "").strip()
        if not value:
            return value
        has_letter = any(ch.isalpha() for ch in value)
        has_digit = any(ch.isdigit() for ch in value)
        if len(value) < 8 or not (has_letter and has_digit):
            raise forms.ValidationError("كلمة المرور يجب أن تكون 8 أحرف على الأقل وتحتوي حروفًا وأرقامًا.")
        return value

    def clean(self):
        cleaned_data = super().clean()
        profile_id = cleaned_data.get("profile_id")
        password = (cleaned_data.get("password") or "").strip()
        level = cleaned_data.get("level")
        dashboards = cleaned_data.get("dashboards") or []

        if level == AccessLevel.POWER and len(dashboards) < 1:
            self.add_error("dashboards", "مستوى Power User يتطلب اختيار لوحة واحدة على الأقل.")
        if level == AccessLevel.USER and len(dashboards) != 1:
            self.add_error("dashboards", "مستوى User يتطلب اختيار لوحة تحكم واحدة فقط.")

        if not profile_id and not password:
            self.add_error("password", "كلمة المرور مطلوبة عند إنشاء حساب جديد.")
        return cleaned_data


class SupportDashboardActionForm(forms.Form):
    status = forms.ChoiceField(
        label="حالة الطلب",
        choices=SupportTicketStatus.choices,
        widget=forms.Select(attrs={"class": "input-control"}),
    )
    assigned_team = forms.ChoiceField(
        label="فريق الدعم",
        required=False,
        widget=forms.Select(attrs={"class": "input-control"}),
    )
    assigned_to = forms.ChoiceField(
        label="المكلف بالطلب",
        required=False,
        widget=forms.Select(attrs={"class": "input-control"}),
    )
    description = forms.CharField(
        label="تفاصيل الطلب",
        max_length=300,
        required=False,
        widget=forms.Textarea(
            attrs={
                "class": "input-control",
                "rows": 4,
                "maxlength": 300,
                "placeholder": "تفاصيل الطلب (300 حرف كحد أقصى)",
            }
        ),
    )
    assignee_comment = forms.CharField(
        label="تعليق المكلف بالطلب",
        max_length=300,
        required=False,
        widget=forms.Textarea(
            attrs={
                "class": "input-control",
                "rows": 4,
                "maxlength": 300,
                "placeholder": "تعليق داخلي (300 حرف كحد أقصى)",
            }
        ),
    )
    attachment = forms.FileField(
        label="المرفقات",
        required=False,
        widget=forms.ClearableFileInput(attrs={"class": "input-control"}),
    )

    def __init__(self, *args, **kwargs):
        assignee_choices = kwargs.pop("assignee_choices", None)
        team_choices = kwargs.pop("team_choices", None)
        super().__init__(*args, **kwargs)

        if team_choices is None:
            team_qs = SupportTeam.objects.filter(is_active=True).order_by("sort_order", "id")
            team_choices = [(str(team.id), team.name_ar) for team in team_qs]
        if assignee_choices is None:
            assignee_choices = []

        self.fields["assigned_team"].choices = [("", "غير محدد")] + list(team_choices)
        self.fields["assigned_to"].choices = [("", "غير محدد")] + list(assignee_choices)

    def clean_description(self):
        value = (self.cleaned_data.get("description") or "").strip()
        return value[:300]

    def clean_assignee_comment(self):
        value = (self.cleaned_data.get("assignee_comment") or "").strip()
        return value[:300]


class ContentFirstTimeForm(forms.Form):
    intro_title = forms.CharField(
        label="العنوان الرئيسي",
        max_length=120,
        widget=forms.TextInput(
            attrs={
                "class": "input-control",
                "placeholder": "منصة مختص المنصة الأشمل...",
                "maxlength": 120,
            }
        ),
    )
    intro_body = forms.CharField(
        label="النص التعريفي العام",
        max_length=300,
        required=False,
        widget=forms.Textarea(
            attrs={
                "class": "input-control",
                "rows": 4,
                "maxlength": 300,
                "placeholder": "وصف موجز يظهر أعلى الصفحة (300 حرف).",
            }
        ),
    )
    client_title = forms.CharField(
        label="عنوان قسم العميل",
        max_length=80,
        widget=forms.TextInput(
            attrs={
                "class": "input-control",
                "placeholder": "كعميل",
                "maxlength": 80,
            }
        ),
    )
    client_body = forms.CharField(
        label="وصف العميل",
        max_length=300,
        widget=forms.Textarea(
            attrs={
                "class": "input-control",
                "rows": 4,
                "maxlength": 300,
                "placeholder": "وصف مخصص للعملاء (300 حرف).",
            }
        ),
    )
    provider_title = forms.CharField(
        label="عنوان قسم مقدم الخدمة",
        max_length=80,
        widget=forms.TextInput(
            attrs={
                "class": "input-control",
                "placeholder": "كمقدم خدمة",
                "maxlength": 80,
            }
        ),
    )
    provider_body = forms.CharField(
        label="وصف مقدم الخدمة",
        max_length=300,
        widget=forms.Textarea(
            attrs={
                "class": "input-control",
                "rows": 4,
                "maxlength": 300,
                "placeholder": "وصف مخصص لمقدمي الخدمات (300 حرف).",
            }
        ),
    )

    def clean_intro_body(self):
        return (self.cleaned_data.get("intro_body") or "").strip()[:300]

    def clean_client_body(self):
        return (self.cleaned_data.get("client_body") or "").strip()[:300]

    def clean_provider_body(self):
        return (self.cleaned_data.get("provider_body") or "").strip()[:300]


class ContentDesignUploadForm(forms.Form):
    design_file = forms.FileField(
        label="رفع التصميم",
        required=False,
        widget=forms.ClearableFileInput(attrs={"class": "input-control"}),
    )
    file_specs = forms.CharField(
        label="مواصفات الملف المرفوع",
        max_length=180,
        required=False,
        widget=forms.TextInput(
            attrs={
                "class": "input-control",
                "placeholder": "يتم تعبئته تلقائيًا بعد اختيار الملف",
                "maxlength": 180,
                "readonly": "readonly",
                "tabindex": "-1",
            }
        ),
    )

    def clean_design_file(self):
        uploaded = self.cleaned_data.get("design_file")
        if uploaded is None:
            return uploaded
        validate_content_block_media(uploaded)
        return uploaded

    def clean_file_specs(self):
        return (self.cleaned_data.get("file_specs") or "").strip()[:180]


class ContentSettingsLegalForm(forms.Form):
    doc_type = forms.ChoiceField(
        label="نوع المستند",
        choices=LegalDocumentType.choices,
        widget=forms.Select(attrs={"class": "input-control"}),
    )
    body_ar = forms.CharField(
        label="النص القانوني",
        required=False,
        widget=forms.Textarea(
            attrs={
                "class": "input-control",
                "rows": 6,
                "maxlength": 5000,
                "placeholder": "يمكن إدخال نص المستند أو رفع ملف.",
            }
        ),
    )
    file = forms.FileField(
        label="رفع الملف",
        required=False,
        widget=forms.ClearableFileInput(attrs={"class": "input-control"}),
    )
    version = forms.CharField(
        label="الإصدار",
        max_length=40,
        required=False,
        widget=forms.TextInput(attrs={"class": "input-control", "placeholder": "1.0"}),
    )
    published_at = forms.DateTimeField(
        label="تاريخ النشر",
        required=False,
        input_formats=["%Y-%m-%dT%H:%M", "%Y-%m-%d %H:%M", "%Y-%m-%d"],
        widget=forms.DateTimeInput(attrs={"type": "datetime-local", "class": "input-control"}),
    )

    def clean_file(self):
        uploaded = self.cleaned_data.get("file")
        if uploaded is None:
            return uploaded
        validate_legal_document_file(uploaded)
        return uploaded

    def clean_body_ar(self):
        return (self.cleaned_data.get("body_ar") or "").strip()[:5000]

    def clean_version(self):
        version = (self.cleaned_data.get("version") or "").strip()
        return version[:40] if version else "1.0"

    def clean(self):
        cleaned = super().clean()
        body = (cleaned.get("body_ar") or "").strip()
        file_obj = cleaned.get("file")
        if not body and not file_obj:
            self.add_error("body_ar", "أدخل نصًا أو أرفق ملفًا واحدًا على الأقل.")
        return cleaned


class ContentSettingsLinksForm(forms.Form):
    about_text = forms.CharField(
        label="نص تعريف المنصة",
        max_length=1000,
        required=False,
        widget=forms.Textarea(
            attrs={
                "class": "input-control",
                "rows": 5,
                "maxlength": 1000,
                "placeholder": "نص تعريف منصة مختص.",
            }
        ),
    )
    website_url = forms.URLField(
        label="رابط الموقع على الويب",
        required=False,
        widget=forms.URLInput(attrs={"class": "input-control", "placeholder": "https://example.com"}),
    )
    ios_store = forms.URLField(
        label="رابط التحميل في آبل ستور",
        required=False,
        widget=forms.URLInput(attrs={"class": "input-control", "placeholder": "https://apps.apple.com/..."}),
    )
    android_store = forms.URLField(
        label="رابط التحميل في الأندرويد",
        required=False,
        widget=forms.URLInput(attrs={"class": "input-control", "placeholder": "https://play.google.com/..."}),
    )
    x_url = forms.URLField(
        label="رابط منصة إكس",
        required=False,
        widget=forms.URLInput(attrs={"class": "input-control", "placeholder": "https://x.com/..."}),
    )
    whatsapp_url = forms.URLField(
        label="رابط الواتساب",
        required=False,
        widget=forms.URLInput(attrs={"class": "input-control", "placeholder": "https://wa.me/..."}),
    )
    email = forms.EmailField(
        label="إيميل المنصة",
        required=False,
        widget=forms.EmailInput(attrs={"class": "input-control", "placeholder": "ops@example.com"}),
    )

    def clean_about_text(self):
        return (self.cleaned_data.get("about_text") or "").strip()[:1000]


class ContentReviewActionForm(forms.Form):
    MODERATION_ACTION_NONE = "none"
    MODERATION_ACTION_APPROVE_REVIEW = "approve_review"
    MODERATION_ACTION_HIDE_REVIEW = "hide_review"
    MODERATION_ACTION_REJECT_REVIEW = "reject_review"
    MODERATION_ACTION_DELETE_TARGET = "delete_target"

    MODERATION_ACTION_CHOICES = (
        (MODERATION_ACTION_NONE, "بدون إجراء إشرافي"),
        (MODERATION_ACTION_APPROVE_REVIEW, "اعتماد التقييم"),
        (MODERATION_ACTION_HIDE_REVIEW, "إخفاء التقييم"),
        (MODERATION_ACTION_REJECT_REVIEW, "رفض التقييم"),
        (MODERATION_ACTION_DELETE_TARGET, "حذف المحتوى محل الشكوى"),
    )

    status = forms.ChoiceField(
        label="حالة الطلب",
        choices=SupportTicketStatus.choices,
        widget=forms.Select(attrs={"class": "input-control"}),
    )
    assigned_team = forms.ChoiceField(
        label="فريق الدعم",
        required=False,
        widget=forms.Select(attrs={"class": "input-control"}),
    )
    assigned_to = forms.ChoiceField(
        label="المكلف بالطلب",
        required=False,
        widget=forms.Select(attrs={"class": "input-control"}),
    )
    description = forms.CharField(
        label="تفاصيل الطلب",
        max_length=300,
        required=False,
        widget=forms.Textarea(
            attrs={
                "class": "input-control",
                "rows": 4,
                "maxlength": 300,
                "placeholder": "تفاصيل الطلب (300 حرف).",
            }
        ),
    )
    assignee_comment = forms.CharField(
        label="تعليق المكلف بالطلب",
        max_length=300,
        required=False,
        widget=forms.Textarea(
            attrs={
                "class": "input-control",
                "rows": 4,
                "maxlength": 300,
                "placeholder": "تعليق داخلي (300 حرف).",
            }
        ),
    )
    management_reply = forms.CharField(
        label="رد الإدارة على التقييم",
        max_length=500,
        required=False,
        widget=forms.Textarea(
            attrs={
                "class": "input-control",
                "rows": 3,
                "maxlength": 500,
                "placeholder": "رد رسمي يظهر في صفحة المراجعة (اختياري).",
            }
        ),
    )
    moderation_action = forms.ChoiceField(
        label="إجراء إشرافي",
        required=False,
        choices=MODERATION_ACTION_CHOICES,
        widget=forms.Select(attrs={"class": "input-control"}),
    )
    attachment = forms.FileField(
        label="المرفقات",
        required=False,
        widget=forms.ClearableFileInput(attrs={"class": "input-control"}),
    )

    def __init__(self, *args, **kwargs):
        assignee_choices = kwargs.pop("assignee_choices", None)
        team_choices = kwargs.pop("team_choices", None)
        super().__init__(*args, **kwargs)

        if team_choices is None:
            team_qs = SupportTeam.objects.filter(is_active=True).order_by("sort_order", "id")
            team_choices = [(str(team.id), team.name_ar) for team in team_qs]
        if assignee_choices is None:
            assignee_choices = []

        self.fields["assigned_team"].choices = [("", "غير محدد")] + list(team_choices)
        self.fields["assigned_to"].choices = [("", "غير محدد")] + list(assignee_choices)

    def clean_description(self):
        return (self.cleaned_data.get("description") or "").strip()[:300]

    def clean_assignee_comment(self):
        return (self.cleaned_data.get("assignee_comment") or "").strip()[:300]

    def clean_management_reply(self):
        return (self.cleaned_data.get("management_reply") or "").strip()[:500]


class PromoInquiryActionForm(forms.Form):
    status = forms.ChoiceField(
        label="حالة الطلب",
        choices=SupportTicketStatus.choices,
        widget=forms.Select(attrs={"class": "input-control"}),
    )
    assigned_team = forms.ChoiceField(
        label="فريق الدعم",
        required=False,
        widget=forms.Select(attrs={"class": "input-control"}),
    )
    assigned_to = forms.ChoiceField(
        label="المكلف بالطلب",
        required=False,
        widget=forms.Select(attrs={"class": "input-control"}),
    )
    description = forms.CharField(
        label="تفاصيل الاستفسار",
        max_length=300,
        required=False,
        widget=forms.Textarea(
            attrs={
                "class": "input-control",
                "rows": 4,
                "maxlength": 300,
                "placeholder": "تفاصيل الاستفسار (300 حرف).",
            }
        ),
    )
    operator_comment = forms.CharField(
        label="تعليق المكلف بالطلب",
        max_length=300,
        required=False,
        widget=forms.Textarea(
            attrs={
                "class": "input-control",
                "rows": 3,
                "maxlength": 300,
                "placeholder": "تعليق داخلي (300 حرف).",
            }
        ),
    )
    detailed_request_url = forms.URLField(
        label="رابط صفحة طلب الترويج التفصيلي",
        required=False,
        widget=forms.URLInput(
            attrs={
                "class": "input-control",
                "placeholder": "https://...",
            }
        ),
    )
    linked_request_id = forms.ChoiceField(
        label="ربط الاستفسار بطلب ترويج",
        required=False,
        widget=forms.Select(attrs={"class": "input-control"}),
    )
    attachment = forms.FileField(
        label="المرفقات",
        required=False,
        widget=forms.ClearableFileInput(attrs={"class": "input-control"}),
    )

    def __init__(self, *args, **kwargs):
        assignee_choices = kwargs.pop("assignee_choices", None)
        team_choices = kwargs.pop("team_choices", None)
        linked_request_choices = kwargs.pop("linked_request_choices", None)
        super().__init__(*args, **kwargs)

        if team_choices is None:
            team_qs = SupportTeam.objects.filter(is_active=True).order_by("sort_order", "id")
            team_choices = [(str(team.id), team.name_ar) for team in team_qs]
        if assignee_choices is None:
            assignee_choices = []
        if linked_request_choices is None:
            linked_request_choices = []

        self.fields["assigned_team"].choices = [("", "غير محدد")] + list(team_choices)
        self.fields["assigned_to"].choices = [("", "غير محدد")] + list(assignee_choices)
        self.fields["linked_request_id"].choices = [("", "بدون ربط")] + list(linked_request_choices)

    def clean_description(self):
        return (self.cleaned_data.get("description") or "").strip()[:300]

    def clean_operator_comment(self):
        return (self.cleaned_data.get("operator_comment") or "").strip()[:300]


class PromoRequestActionForm(forms.Form):
    assigned_to = forms.ChoiceField(
        label="المكلف بالطلب",
        required=False,
        widget=forms.Select(attrs={"class": "input-control"}),
    )
    ops_status = forms.ChoiceField(
        label="حالة التنفيذ",
        choices=PromoOpsStatus.choices,
        widget=forms.Select(attrs={"class": "input-control"}),
    )
    ops_note = forms.CharField(
        label="ملاحظة تنفيذ",
        max_length=300,
        required=False,
        widget=forms.Textarea(
            attrs={
                "class": "input-control",
                "rows": 3,
                "maxlength": 300,
                "placeholder": "ملاحظة تنفيذية داخلية.",
            }
        ),
    )
    quote_note = forms.CharField(
        label="ملاحظة التسعير",
        max_length=300,
        required=False,
        widget=forms.Textarea(
            attrs={
                "class": "input-control",
                "rows": 3,
                "maxlength": 300,
                "placeholder": "ملاحظة للعميل عند اعتماد التسعير.",
            }
        ),
    )

    def __init__(self, *args, **kwargs):
        assignee_choices = kwargs.pop("assignee_choices", None)
        super().__init__(*args, **kwargs)
        if assignee_choices is None:
            assignee_choices = []
        self.fields["assigned_to"].choices = [("", "غير محدد")] + list(assignee_choices)

    def clean_ops_note(self):
        return (self.cleaned_data.get("ops_note") or "").strip()[:300]

    def clean_quote_note(self):
        return (self.cleaned_data.get("quote_note") or "").strip()[:300]


class PromoModuleItemForm(forms.Form):
    request_id = forms.IntegerField(
        label="رقم طلب الترويج",
        required=True,
        min_value=1,
        widget=forms.NumberInput(
            attrs={
                "class": "input-control",
                "placeholder": "ID",
                "inputmode": "numeric",
            }
        ),
    )
    requester_identifier = forms.CharField(
        label="اسم المستخدم/الجوال للعميل",
        required=False,
        max_length=64,
        widget=forms.TextInput(
            attrs={
                "class": "input-control",
                "placeholder": "@username أو 9665xxxxxxx",
            }
        ),
    )
    title = forms.CharField(
        label="عنوان الحملة",
        required=False,
        max_length=160,
        widget=forms.TextInput(
            attrs={
                "class": "input-control",
                "placeholder": "عنوان الحملة الترويجية",
            }
        ),
    )
    start_at = forms.DateTimeField(
        label="بداية الحملة",
        required=False,
        input_formats=["%Y-%m-%dT%H:%M", "%Y-%m-%d %H:%M", "%Y-%m-%d"],
        widget=forms.DateTimeInput(attrs={"type": "datetime-local", "class": "input-control"}),
    )
    end_at = forms.DateTimeField(
        label="نهاية الحملة",
        required=False,
        input_formats=["%Y-%m-%dT%H:%M", "%Y-%m-%d %H:%M", "%Y-%m-%d"],
        widget=forms.DateTimeInput(attrs={"type": "datetime-local", "class": "input-control"}),
    )
    send_at = forms.DateTimeField(
        label="وقت الإرسال",
        required=False,
        input_formats=["%Y-%m-%dT%H:%M", "%Y-%m-%d %H:%M", "%Y-%m-%d"],
        widget=forms.DateTimeInput(attrs={"type": "datetime-local", "class": "input-control"}),
    )
    frequency = forms.ChoiceField(
        label="معدل الظهور",
        required=False,
        choices=[("", "غير محدد")] + list(PromoFrequency.choices),
        widget=forms.Select(attrs={"class": "input-control"}),
    )
    search_scope = forms.ChoiceField(
        label="قائمة الظهور في البحث",
        required=False,
        choices=[("", "غير محدد")] + list(PromoSearchScope.choices),
        widget=forms.Select(attrs={"class": "input-control"}),
    )
    search_scopes = forms.MultipleChoiceField(
        label="قوائم الظهور في البحث",
        required=False,
        choices=list(PromoSearchScope.choices),
        widget=forms.CheckboxSelectMultiple,
    )
    search_position = forms.ChoiceField(
        label="ترتيب الظهور في البحث",
        required=False,
        choices=[("", "غير محدد")] + [
            (PromoPosition.FIRST, "الأول في القائمة"),
            (PromoPosition.SECOND, "الثاني في القائمة"),
            (PromoPosition.TOP5, "من أول خمسة أسماء"),
            (PromoPosition.TOP10, "من أول عشرة أسماء"),
        ],
        widget=forms.Select(attrs={"class": "input-control"}),
    )
    target_provider_id = forms.IntegerField(
        label="معرف المختص المستهدف (اختياري)",
        required=False,
        min_value=1,
        widget=forms.NumberInput(
            attrs={
                "class": "input-control",
                "placeholder": "Provider ID",
                "inputmode": "numeric",
            }
        ),
    )
    target_category = forms.CharField(
        label="التصنيف المستهدف",
        required=False,
        max_length=80,
        widget=forms.TextInput(attrs={"class": "input-control", "placeholder": "مثال: التصميم وصناعة المحتوى"}),
    )
    target_city = forms.CharField(
        label="المدينة المستهدفة",
        required=False,
        max_length=80,
        widget=forms.TextInput(attrs={"class": "input-control", "placeholder": "مثال: الرياض"}),
    )
    redirect_url = forms.URLField(
        label="رابط التوجيه",
        required=False,
        widget=forms.URLInput(attrs={"class": "input-control", "placeholder": "https://..."}),
    )
    message_title = forms.CharField(
        label="عنوان الرسالة الدعائية",
        required=False,
        max_length=160,
        widget=forms.TextInput(attrs={"class": "input-control", "placeholder": "عنوان مختصر"}),
    )
    message_body = forms.CharField(
        label="نص الرسالة الدعائية",
        required=False,
        max_length=500,
        widget=forms.Textarea(
            attrs={
                "class": "input-control",
                "rows": 3,
                "maxlength": 500,
                "placeholder": "نص الرسالة الدعائية",
            }
        ),
    )
    use_notification_channel = forms.BooleanField(
        label="رسائل التنبيه الدعائية",
        required=False,
    )
    use_chat_channel = forms.BooleanField(
        label="رسائل المحادثات الدعائية",
        required=False,
    )
    sponsor_name = forms.CharField(
        label="اسم الراعي",
        required=False,
        max_length=160,
        widget=forms.TextInput(attrs={"class": "input-control", "placeholder": "اسم الجهة الراعية"}),
    )
    sponsor_url = forms.URLField(
        label="رابط الراعي",
        required=False,
        widget=forms.URLInput(attrs={"class": "input-control", "placeholder": "https://..."}),
    )
    sponsorship_months = forms.IntegerField(
        label="مدة الرعاية (بالأشهر)",
        required=False,
        min_value=0,
        widget=forms.NumberInput(attrs={"class": "input-control", "placeholder": "0"}),
    )
    attachment_specs = forms.CharField(
        label="مواصفات الملف المرفوع",
        required=False,
        max_length=300,
        widget=forms.TextInput(attrs={"class": "input-control", "placeholder": "مثال: PNG/MP4 - 1920x840 (نسبة 16:7)"}),
    )
    operator_note = forms.CharField(
        label="ملاحظة تشغيلية",
        required=False,
        max_length=300,
        widget=forms.Textarea(
            attrs={
                "class": "input-control",
                "rows": 2,
                "maxlength": 300,
                "placeholder": "ملاحظة داخلية لفريق الترويج",
            }
        ),
    )
    media_file = forms.FileField(
        label="رفع التصميم/الملف",
        required=False,
        widget=forms.ClearableFileInput(attrs={"class": "input-control"}),
    )
    mobile_scale = forms.IntegerField(
        label="حجم الجوال (%)",
        required=False,
        min_value=40,
        max_value=140,
        widget=forms.NumberInput(attrs={"class": "input-control", "placeholder": "100"}),
    )
    tablet_scale = forms.IntegerField(
        label="حجم الأجهزة المتوسطة (%)",
        required=False,
        min_value=40,
        max_value=150,
        widget=forms.NumberInput(attrs={"class": "input-control", "placeholder": "100"}),
    )
    desktop_scale = forms.IntegerField(
        label="حجم الديسكتوب (%)",
        required=False,
        min_value=40,
        max_value=160,
        widget=forms.NumberInput(attrs={"class": "input-control", "placeholder": "100"}),
    )

    def __init__(self, *args, **kwargs):
        self.service_type = kwargs.pop("service_type", "")
        super().__init__(*args, **kwargs)
        if not self.is_bound:
            initial_scope = str(self.initial.get("search_scope") or "").strip()
            initial_scopes = self.initial.get("search_scopes") or []
            if initial_scope and not initial_scopes:
                self.initial["search_scopes"] = [initial_scope]

    def clean(self):
        cleaned = super().clean()
        service_type = str(self.service_type or "").strip()
        request_id = cleaned.get("request_id")
        if not request_id:
            self.add_error("request_id", "اختر رقم طلب ترويج قائم أولاً.")

        start_at = cleaned.get("start_at")
        end_at = cleaned.get("end_at")
        send_at = cleaned.get("send_at")

        if service_type in {
            PromoServiceType.HOME_BANNER,
            PromoServiceType.FEATURED_SPECIALISTS,
            PromoServiceType.PORTFOLIO_SHOWCASE,
            PromoServiceType.SNAPSHOTS,
            PromoServiceType.SEARCH_RESULTS,
            PromoServiceType.SPONSORSHIP,
        }:
            if not start_at or not end_at:
                self.add_error("start_at", "بداية ونهاية الحملة مطلوبتان.")
            elif end_at <= start_at:
                self.add_error("end_at", "تاريخ النهاية يجب أن يكون بعد البداية.")
            elif (end_at - start_at).total_seconds() < promo_min_campaign_hours() * 60 * 60:
                self.add_error("end_at", promo_min_campaign_message())

        if service_type in {
            PromoServiceType.FEATURED_SPECIALISTS,
            PromoServiceType.PORTFOLIO_SHOWCASE,
            PromoServiceType.SNAPSHOTS,
        } and not (cleaned.get("frequency") or "").strip():
            self.add_error("frequency", "معدل الظهور مطلوب لهذا النوع.")

        if service_type == PromoServiceType.SEARCH_RESULTS:
            selected_scopes = [str(scope).strip() for scope in (cleaned.get("search_scopes") or []) if str(scope).strip()]
            legacy_scope = (cleaned.get("search_scope") or "").strip()
            if not selected_scopes and legacy_scope:
                selected_scopes = [legacy_scope]
            selected_scopes = list(dict.fromkeys(selected_scopes))
            if not selected_scopes:
                self.add_error("search_scopes", "اختر قائمة ظهور واحدة على الأقل.")
            cleaned["resolved_search_scopes"] = selected_scopes
            if not (cleaned.get("search_position") or "").strip():
                self.add_error("search_position", "ترتيب الظهور مطلوب.")

        if service_type == PromoServiceType.PROMO_MESSAGES:
            if not send_at:
                self.add_error("send_at", "وقت الإرسال مطلوب.")
            if not cleaned.get("use_notification_channel") and not cleaned.get("use_chat_channel"):
                self.add_error("use_notification_channel", "اختر قناة إرسال واحدة على الأقل.")
            if not (cleaned.get("message_body") or "").strip() and cleaned.get("media_file") is None:
                self.add_error("message_body", "أدخل نص الرسالة أو أرفق ملفًا.")

        if service_type == PromoServiceType.SPONSORSHIP:
            months = int(cleaned.get("sponsorship_months") or 0)
            if months <= 0:
                self.add_error("sponsorship_months", "مدة الرعاية بالأشهر مطلوبة.")

        return cleaned

    def clean_title(self):
        return (self.cleaned_data.get("title") or "").strip()[:160]

    def clean_requester_identifier(self):
        return (self.cleaned_data.get("requester_identifier") or "").strip()[:64]

    def clean_target_category(self):
        return (self.cleaned_data.get("target_category") or "").strip()[:80]

    def clean_target_city(self):
        return (self.cleaned_data.get("target_city") or "").strip()[:80]

    def clean_message_title(self):
        return (self.cleaned_data.get("message_title") or "").strip()[:160]

    def clean_message_body(self):
        return (self.cleaned_data.get("message_body") or "").strip()[:500]

    def clean_attachment_specs(self):
        return (self.cleaned_data.get("attachment_specs") or "").strip()[:300]

    def clean_operator_note(self):
        return (self.cleaned_data.get("operator_note") or "").strip()[:300]
