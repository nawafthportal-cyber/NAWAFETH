from django.core.cache import cache


PUBLIC_CATEGORY_LIST_CACHE_KEY = "providers:public_category_list:v1"
PUBLIC_CATEGORY_LIST_CACHE_TTL = 60 * 60


def get_cached_public_category_list_payload(builder):
    payload = cache.get(PUBLIC_CATEGORY_LIST_CACHE_KEY)
    if payload is not None:
        return payload

    payload = builder()
    cache.set(PUBLIC_CATEGORY_LIST_CACHE_KEY, payload, PUBLIC_CATEGORY_LIST_CACHE_TTL)
    return payload


def invalidate_public_category_list_cache():
    cache.delete(PUBLIC_CATEGORY_LIST_CACHE_KEY)