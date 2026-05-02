/* ===================================================================
   languagePage.js — Language selection page (mobile parity)
   Keeps user choice locally and syncs against active account session.
   =================================================================== */
'use strict';

const LanguagePage = (() => {
  const KEY = 'nw_lang';
  const COPY = {
    ar: {
      title: 'نوافــذ — اللغة',
      heroBadge: 'هوية المنصة',
      pageTitle: 'اختيار اللغة',
      heroSubtitle: 'اختر اللغة التي تناسبك لتجربة أوضح وأكثر انسجامًا مع واجهة نوافذ.',
      heroCardTitle: 'واجهة ثنائية اللغة',
      heroCardBody: 'العربية والإنجليزية بحالة اختيار واضحة',
      authKicker: 'مزامنة الحساب',
      authTitle: 'سجّل دخولك أولًا',
      authBody: 'تسجيل الدخول يضمن حفظ اللغة المختارة وربطها بتجربتك داخل المنصة.',
      loginCta: 'تسجيل الدخول',
      currentSettingKicker: 'الإعداد الحالي',
      currentLanguageTitle: 'اللغة الحالية',
      optionsGroupLabel: 'خيارات اللغة',
      arabicLabel: 'العربية',
      arabicCaption: 'الواجهة الافتراضية للمنصة',
      englishLabel: 'English',
      englishCaption: 'واجهة مناسبة للتصفح الدولي',
      currentLanguageValue: 'العربية',
      success: 'تم اختيار العربية',
      saveError: 'تعذر حفظ اللغة على هذا المتصفح',
    },
    en: {
      title: 'Nawafeth — Language',
      heroBadge: 'Platform Identity',
      pageTitle: 'Language Selection',
      heroSubtitle: 'Choose the language that gives you a clearer and more consistent Nawafeth experience.',
      heroCardTitle: 'Bilingual Interface',
      heroCardBody: 'Arabic and English with a clear active state.',
      authKicker: 'Account Sync',
      authTitle: 'Sign In First',
      authBody: 'Signing in helps keep your selected language synced with your experience across the platform.',
      loginCta: 'Sign In',
      currentSettingKicker: 'Current Setting',
      currentLanguageTitle: 'Current Language',
      optionsGroupLabel: 'Language options',
      arabicLabel: 'Arabic',
      arabicCaption: 'The platform default interface',
      englishLabel: 'English',
      englishCaption: 'A better fit for international browsing',
      currentLanguageValue: 'English',
      success: 'English selected',
      saveError: 'Unable to save the language on this browser',
    },
  };

  function init() {
    const authGate = document.getElementById('language-auth-gate');
    const content = document.getElementById('language-content');
    const lang = _getLanguage();

    _applyPageLanguage(lang);

    if (!Auth.isLoggedIn()) {
      if (authGate) authGate.classList.remove('hidden');
      if (content) content.classList.add('hidden');
      return;
    }

    if (authGate) authGate.classList.add('hidden');
    if (content) content.classList.remove('hidden');

    _renderCurrent();
    _loadProfileForSync();

    const arBtn = document.getElementById('lang-ar');
    const enBtn = document.getElementById('lang-en');
    if (arBtn) arBtn.addEventListener('click', () => _setLanguage('ar'));
    if (enBtn) enBtn.addEventListener('click', () => _setLanguage('en'));
  }

  async function _loadProfileForSync() {
    try {
      await Auth.getProfile(true);
    } catch (_) {
      // Keep page functional even if profile fetch fails.
    }
  }

  function _setLanguage(lang) {
    try {
      localStorage.setItem(KEY, lang);
    } catch (_) {
      _showError(_copy(_getLanguage()).saveError);
      return;
    }

    if (window.NawafethI18n && typeof window.NawafethI18n.applyLanguage === 'function') {
      window.NawafethI18n.applyLanguage(lang);
    }

    _applyPageLanguage(lang);
    _renderCurrent();
    _showSuccess(_copy(lang).success);
  }

  function _getLanguage() {
    try {
      return localStorage.getItem(KEY) || 'ar';
    } catch (_) {
      return 'ar';
    }
  }

  function _renderCurrent() {
    const lang = _getLanguage();
    const label = document.getElementById('language-current-label');
    if (label) {
      label.textContent = _copy(lang).currentLanguageValue;
    }

    _renderSelectionState(lang);
  }

  function _applyPageLanguage(lang) {
    const dict = _copy(lang);
    document.documentElement.lang = lang;
    document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
    document.title = dict.title;

    document.querySelectorAll('[data-i18n]').forEach((node) => {
      const key = node.getAttribute('data-i18n');
      if (!key || !(key in dict)) return;
      node.textContent = dict[key];
    });

    document.querySelectorAll('[data-i18n-aria-label]').forEach((node) => {
      const key = node.getAttribute('data-i18n-aria-label');
      if (!key || !(key in dict)) return;
      node.setAttribute('aria-label', dict[key]);
    });
  }

  function _copy(lang) {
    return COPY[lang] || COPY.ar;
  }

  function _renderSelectionState(lang) {
    const options = document.querySelectorAll('.language-option');
    options.forEach((option) => {
      const isActive = option.dataset.lang === lang;
      option.classList.toggle('is-active', isActive);
      option.setAttribute('aria-pressed', isActive ? 'true' : 'false');
    });
  }

  function _showSuccess(msg) {
    const success = document.getElementById('language-success');
    const error = document.getElementById('language-error');
    if (error) error.classList.add('hidden');
    if (!success) return;
    success.textContent = msg;
    success.classList.remove('hidden');
  }

  function _showError(msg) {
    const success = document.getElementById('language-success');
    const error = document.getElementById('language-error');
    if (success) success.classList.add('hidden');
    if (!error) return;
    error.textContent = msg;
    error.classList.remove('hidden');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return { init };
})();
