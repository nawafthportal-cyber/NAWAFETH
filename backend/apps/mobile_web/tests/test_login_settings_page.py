import pytest
from django.test import Client


@pytest.mark.django_db
def test_login_settings_page_renders_action_buttons_and_modal():
    client = Client()
    res = client.get("/login-settings/")

    assert res.status_code == 200
    html = res.content.decode("utf-8", errors="ignore")

    assert 'id="ls-action-username"' in html
    assert 'id="ls-action-password"' in html
    assert 'id="ls-action-email"' in html
    assert 'id="ls-action-phone"' in html
    assert 'id="ls-action-pin"' in html
    assert 'id="ls-action-faceid"' in html

    assert 'id="ls-action-modal"' in html
    assert 'id="ls-modal-fields"' in html
    assert "mobile_web/js/loginSettingsPage.js" in html
