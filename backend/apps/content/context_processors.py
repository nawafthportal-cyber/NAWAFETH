from .services import template_site_payload


def site_public_content(request):
    return {
        "site_public_content": template_site_payload(),
    }
