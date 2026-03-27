import pytest
from django.test import Client


@pytest.mark.django_db
@pytest.mark.parametrize("path", ["/", "/search/"])
def test_shared_topbar_renders_across_pages(path):
    client = Client()
    res = client.get(path)

    assert res.status_code == 200
    html = res.content.decode("utf-8", errors="ignore")

    assert 'id="top-navbar"' in html
    assert 'id="btn-menu"' in html
    assert 'id="btn-notifications"' in html
    assert 'id="btn-chat"' in html
    assert 'id="topbar-sponsor"' in html


@pytest.mark.django_db
def test_home_page_no_longer_renders_duplicate_top_headers():
    client = Client()
    res = client.get("/")

    assert res.status_code == 200
    html = res.content.decode("utf-8", errors="ignore")

    assert 'id="hero-menu-btn"' not in html
    assert 'class="home-desktop-header"' not in html