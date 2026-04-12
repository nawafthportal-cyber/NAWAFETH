from __future__ import annotations

from django.db.models.signals import post_delete, post_save
from django.dispatch import receiver

from .models import SiteContentBlock, SiteLegalDocument, SiteLinks
from .services import invalidate_public_content_cache


@receiver(post_save, sender=SiteContentBlock)
@receiver(post_delete, sender=SiteContentBlock)
@receiver(post_save, sender=SiteLegalDocument)
@receiver(post_delete, sender=SiteLegalDocument)
@receiver(post_save, sender=SiteLinks)
@receiver(post_delete, sender=SiteLinks)
def _invalidate_content_payload_cache(**_kwargs):
    invalidate_public_content_cache()
