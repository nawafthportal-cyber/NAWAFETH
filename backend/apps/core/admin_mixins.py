class HiddenFromAdminIndexMixin:
    """
    Keep model admin registered and fully functional, but hide it from
    the main admin index and app model list to reduce visual noise.
    """

    def get_model_perms(self, request):
        return {}
