from django import template

from apps.providers.location_formatter import format_city_display

register = template.Library()


@register.filter(name="city_display")
def city_display(value):
    return format_city_display(value)