from django.db import models
from django.db.models import Q
from django.conf import settings
from django.utils import timezone
from apps.marketplace.models import ServiceRequest


_DIRECT_CONTEXT_MODES = {"client", "provider", "shared"}


def normalize_thread_mode(mode: str | None, *, fallback: str = "") -> str:
    normalized = str(mode or "").strip().lower()
    return normalized if normalized in _DIRECT_CONTEXT_MODES else fallback


def direct_thread_mode_q(*, user, mode: str | None) -> Q:
    normalized_mode = normalize_thread_mode(mode)
    if not getattr(user, "pk", None):
        return Q(pk__in=[])
    if not normalized_mode:
        return Q(participant_1=user) | Q(participant_2=user)

    accepted_modes = [normalized_mode, Thread.ContextMode.SHARED]


    return (
        (
            Q(participant_1=user)
            & (
                Q(participant_1_mode__in=accepted_modes)
                | (Q(participant_1_mode="") & Q(context_mode__in=accepted_modes))
            )
        )
        |
        (
            Q(participant_2=user)
            & (
                Q(participant_2_mode__in=accepted_modes)
                | (Q(participant_2_mode="") & Q(context_mode__in=accepted_modes))
            )
        )
    )

class Thread(models.Model):
    class ContextMode(models.TextChoices):
        CLIENT = "client", "عميل"
        PROVIDER = "provider", "مزود"
        SHARED = "shared", "مشترك"

    request = models.OneToOneField(
        ServiceRequest, on_delete=models.CASCADE, related_name="thread",
        null=True, blank=True,
    )
    # Direct messaging (no request required)
    participant_1 = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name="direct_threads_as_p1", null=True, blank=True,
    )
    participant_2 = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name="direct_threads_as_p2", null=True, blank=True,
    )
    is_direct = models.BooleanField(default=False)
    is_system_thread = models.BooleanField(default=False, db_index=True)
    system_thread_key = models.CharField(max_length=64, blank=True, default="", db_index=True)
    context_mode = models.CharField(
        max_length=20,
        choices=ContextMode.choices,
        default=ContextMode.SHARED,
        db_index=True,
    )
    participant_1_mode = models.CharField(
        max_length=20,
        choices=ContextMode.choices,
        blank=True,
        default="",
        db_index=True,
    )
    participant_2_mode = models.CharField(
        max_length=20,
        choices=ContextMode.choices,
        blank=True,
        default="",
        db_index=True,
    )
    reply_restricted_to = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        related_name="reply_restricted_threads",
        null=True,
        blank=True,
    )
    reply_restriction_reason = models.CharField(max_length=255, blank=True, default="")
    system_sender_label = models.CharField(max_length=120, blank=True, default="")
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        indexes = [
            models.Index(fields=["participant_1", "participant_2"]),
        ]

    def __str__(self):
        if self.is_direct:
            return f"DirectThread #{self.id} ({self.participant_1_id} ↔ {self.participant_2_id})"
        return f"Thread for request #{self.request_id}"

    def direct_participant_mode(self, user) -> str:
        user_id = getattr(user, "id", user)
        if not self.is_direct or not user_id:
            return self.ContextMode.SHARED
        if user_id == self.participant_1_id:
            return normalize_thread_mode(self.participant_1_mode, fallback=normalize_thread_mode(self.context_mode, fallback=self.ContextMode.SHARED))
        if user_id == self.participant_2_id:
            return normalize_thread_mode(self.participant_2_mode, fallback=normalize_thread_mode(self.context_mode, fallback=self.ContextMode.SHARED))
        return self.ContextMode.SHARED

    def participant_mode_for_user(self, user) -> str:
        user_id = getattr(user, "id", user)
        if not user_id:
            return self.ContextMode.SHARED
        if self.is_direct:
            return self.direct_participant_mode(user_id)
        if self.request_id:
            sr = self.request
            if sr and sr.client_id == user_id:
                return self.ContextMode.CLIENT
            if sr and sr.provider_id and sr.provider.user_id == user_id:
                return self.ContextMode.PROVIDER
        return self.ContextMode.SHARED

    def mode_matches_user(self, user, mode: str | None) -> bool:
        normalized_mode = normalize_thread_mode(mode)
        if not normalized_mode:
            return self.is_participant(user)
        participant_mode = self.participant_mode_for_user(user)
        return participant_mode in {normalized_mode, self.ContextMode.SHARED}

    def other_participant(self, user):
        user_id = getattr(user, "id", user)
        if not user_id:
            return None
        if self.is_direct:
            if user_id == self.participant_1_id:
                return self.participant_2
            if user_id == self.participant_2_id:
                return self.participant_1
            return None
        if self.request_id and self.request:
            if self.request.client_id == user_id:
                return getattr(self.request.provider, "user", None)
            if getattr(self.request, "provider_id", None) and self.request.provider.user_id == user_id:
                return self.request.client
        return None

    def set_participant_modes(self, *, participant_1_mode: str | None = None, participant_2_mode: str | None = None, save: bool = False):
        update_fields: list[str] = []

        if participant_1_mode is not None:
            normalized = normalize_thread_mode(participant_1_mode)
            if self.participant_1_mode != normalized:
                self.participant_1_mode = normalized
                update_fields.append("participant_1_mode")

        if participant_2_mode is not None:
            normalized = normalize_thread_mode(participant_2_mode)
            if self.participant_2_mode != normalized:
                self.participant_2_mode = normalized
                update_fields.append("participant_2_mode")

        if save and update_fields:
            self.save(update_fields=update_fields)
        return update_fields

    def can_user_send(self, user) -> bool:
        user_id = getattr(user, "id", user)
        if not user_id:
            return False
        return not (self.reply_restricted_to_id and self.reply_restricted_to_id == user_id)

    def configure_system_thread(
        self,
        *,
        system_thread_key: str | None = None,
        system_sender_label: str | None = None,
        reply_restricted_to=None,
        reply_restriction_reason: str | None = None,
        save: bool = False,
    ):
        update_fields: list[str] = []

        if not self.is_system_thread:
            self.is_system_thread = True
            update_fields.append("is_system_thread")

        normalized_key = str(system_thread_key or "").strip().lower()
        if self.system_thread_key != normalized_key:
            self.system_thread_key = normalized_key
            update_fields.append("system_thread_key")

        normalized_label = str(system_sender_label or "").strip()
        if self.system_sender_label != normalized_label:
            self.system_sender_label = normalized_label
            update_fields.append("system_sender_label")

        restricted_user_id = getattr(reply_restricted_to, "id", reply_restricted_to)
        if self.reply_restricted_to_id != restricted_user_id:
            self.reply_restricted_to_id = restricted_user_id
            update_fields.append("reply_restricted_to")

        normalized_reason = str(reply_restriction_reason or "").strip()
        if self.reply_restriction_reason != normalized_reason:
            self.reply_restriction_reason = normalized_reason
            update_fields.append("reply_restriction_reason")

        if save and update_fields:
            self.save(update_fields=update_fields)
        return update_fields

    def is_participant(self, user) -> bool:
        """Check if user is a participant in this thread (direct or request-based)."""
        if self.is_direct:
            return user.id in (self.participant_1_id, self.participant_2_id)
        if self.request_id:
            sr = self.request
            if sr.client_id == user.id:
                return True
            if sr.provider_id and sr.provider.user_id == user.id:
                return True
        return False


class Message(models.Model):
    thread = models.ForeignKey(Thread, on_delete=models.CASCADE, related_name="messages")
    sender = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="sent_messages")
    body = models.TextField(max_length=2000)
    is_system_generated = models.BooleanField(default=False, db_index=True)
    sender_team_name = models.CharField(max_length=120, blank=True, default="")
    attachment = models.FileField(upload_to="messaging/attachments/%Y/%m/%d/", null=True, blank=True)
    attachment_type = models.CharField(max_length=20, blank=True, default="")  # audio, image, file
    attachment_name = models.CharField(max_length=255, blank=True, default="")
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ("id",)

    def __str__(self):
        return f"Msg #{self.id} by {self.sender_id}"


def create_system_message(
    *,
    thread: Thread,
    sender,
    body: str,
    sender_team_name: str = "",
    system_thread_key: str = "",
    reply_restricted_to=None,
    reply_restriction_reason: str = "",
    attachment=None,
    attachment_type: str = "",
    attachment_name: str = "",
    created_at=None,
):
    restricted_user = reply_restricted_to if reply_restricted_to is not None else thread.other_participant(sender)
    thread.configure_system_thread(
        system_thread_key=system_thread_key,
        system_sender_label=sender_team_name,
        reply_restricted_to=restricted_user,
        reply_restriction_reason=reply_restriction_reason,
        save=True,
    )
    return Message.objects.create(
        thread=thread,
        sender=sender,
        body=(body or "")[:2000],
        is_system_generated=True,
        sender_team_name=str(sender_team_name or "").strip(),
        attachment=attachment,
        attachment_type=(attachment_type or "").strip(),
        attachment_name=(attachment_name or "").strip(),
        created_at=created_at or timezone.now(),
    )


class MessageRead(models.Model):
    message = models.ForeignKey(Message, on_delete=models.CASCADE, related_name="reads")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="message_reads")
    read_at = models.DateTimeField(default=timezone.now)

    class Meta:
        unique_together = ("message", "user")
        indexes = [
            models.Index(fields=["user", "read_at"]),
        ]


class ThreadUserState(models.Model):
    # Choices for favorite_label
    FAVORITE_LABEL_POTENTIAL = "potential_client"
    FAVORITE_LABEL_IMPORTANT = "important_conversation"
    FAVORITE_LABEL_INCOMPLETE = "incomplete_contact"
    FAVORITE_LABEL_CHOICES = [
        (FAVORITE_LABEL_POTENTIAL, "عميل محتمل"),
        (FAVORITE_LABEL_IMPORTANT, "محادثة مهمة"),
        (FAVORITE_LABEL_INCOMPLETE, "تواصل غير مكتمل"),
    ]

    # Choices for client_label
    CLIENT_LABEL_POTENTIAL = "potential"
    CLIENT_LABEL_CURRENT = "current"
    CLIENT_LABEL_PAST = "past"
    CLIENT_LABEL_CHOICES = [
        (CLIENT_LABEL_POTENTIAL, "عميل محتمل"),
        (CLIENT_LABEL_CURRENT, "عميل حالي"),
        (CLIENT_LABEL_PAST, "عميل سابق"),
    ]

    thread = models.ForeignKey(Thread, on_delete=models.CASCADE, related_name="user_states")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="thread_states")

    is_favorite = models.BooleanField(default=False)
    favorite_label = models.CharField(
        max_length=30, blank=True, default="",
        choices=FAVORITE_LABEL_CHOICES,
        help_text="تصنيف المفضلة: عميل محتمل / محادثة مهمة / تواصل غير مكتمل",
    )
    client_label = models.CharField(
        max_length=20, blank=True, default="",
        choices=CLIENT_LABEL_CHOICES,
        help_text="تمييز العميل: محتمل / حالي / سابق",
    )
    is_archived = models.BooleanField(default=False)
    is_blocked = models.BooleanField(default=False)
    is_deleted = models.BooleanField(default=False)

    blocked_at = models.DateTimeField(null=True, blank=True)
    archived_at = models.DateTimeField(null=True, blank=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(default=timezone.now)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ("thread", "user")
        indexes = [
            models.Index(fields=["user", "is_favorite"], name="messaging_t_user_id_439020_idx"),
            models.Index(fields=["user", "is_archived"], name="messaging_t_user_id_a56866_idx"),
            models.Index(fields=["user", "is_blocked"], name="messaging_t_user_id_b28302_idx"),
            models.Index(fields=["user", "is_deleted"], name="messaging_t_user_id_deleted_idx"),
        ]

    def __str__(self) -> str:
        return f"ThreadUserState thread={self.thread_id} user={self.user_id}"
