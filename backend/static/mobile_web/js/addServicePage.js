/* ===================================================================
   addServicePage.js — Add Service hub page controller
   The page now hosts 3 request-path cards only (no categories grid).
   Responsibilities:
     1. Provider-mode guard (block creation in provider mode).
     2. Auth-required link interception for /urgent-request/ and
        /request-quote/ (redirects to /login/ when not signed in).
   =================================================================== */
'use strict';

const AddServicePage = (() => {
  const COPY = {
    ar: {
      pageTitle: 'نوافــذ — طلب خدمة',
      providerGateKicker: 'وضع الحساب الحالي',
      providerGateTitle: 'إنشاء الطلبات متاح في وضع العميل',
      providerGateDescription: 'أنت تستخدم المنصة الآن بوضع مقدم الخدمة، لذلك تم إيقاف مسارات طلب الخدمات الجديدة حتى لا تختلط أدوات المزود بمسارات العميل.',
      providerGateNote: 'بدّل نوع الحساب إلى عميل الآن، ثم ستظهر لك جميع مسارات الطلب مباشرة في نفس الصفحة.',
      providerGateSwitch: 'التبديل إلى عميل',
      providerGateProfile: 'فتح نافذتي',
      blockedTitle: 'مسارات الطلب غير متاحة في وضع مقدم الخدمة',
      blockedDescription: 'لإنشاء طلب عاجل أو طلب عروض أسعار أو أي طلب خدمة جديد، بدّل نوع الحساب إلى عميل أولًا.',
      blockedNote: 'بعد التبديل ستتمكن من متابعة نفس المسار بدون تسجيل خروج.',
      blockedSwitch: 'التبديل إلى عميل',
      blockedProfile: 'الذهاب إلى نافذتي',
      heroKicker: 'جاهز لاستقبال طلبك',
      ordersLink: 'طلباتي',
      heroTitle: 'كيف تحب أن نُنجز خدمتك؟',
      heroSubtitle: 'اختر المسار الأنسب لك، وكل مسار يفتح نموذج طلب مخصص بأقل خطوات ممكنة.',
      statPaths: 'مسارات للطلب',
      statTime: 'متوسط وقت الإرسال',
      statAvailability: 'استقبال الطلبات',
      sectionTitle: 'اختر نوع الطلب',
      sectionTag: '3 مسارات',
      searchTitle: 'البحث عن مزود خدمة',
      searchBadge: 'طلب مباشر',
      searchSubtitle: 'تصفح المزودين، قارن التقييمات، وابدأ المحادثة بنفسك مباشرة.',
      searchChipLocation: 'فلترة جغرافية',
      searchChipRatings: 'تقييمات حقيقية',
      searchChipChat: 'محادثة فورية',
      urgentTitle: 'طلب عاجل',
      urgentBadge: 'الأكثر طلبًا',
      urgentSubtitle: 'إشعار فوري لأقرب المزودين المؤهلين مع استجابة سريعة خلال دقائق.',
      urgentChipResponse: 'استجابة فورية',
      urgentChipCall: 'اتصال مباشر',
      urgentChipNearest: 'أقرب مزود',
      quoteTitle: 'طلب عروض أسعار',
      quoteBadge: 'قارن العروض',
      quoteSubtitle: 'استقبل عدة عروض من مزودين موثوقين، قارنها واختر الأنسب لك.',
      quoteChipPricing: 'أسعار تنافسية',
      quoteChipCompare: 'مقارنة مرنة',
      quoteChipTrusted: 'مزودون موثوقون',
      helpTitle: 'غير متأكد من المسار المناسب؟',
      helpSubtitle: 'تواصل مع فريق الدعم وسنساعدك في اختيار الطريقة الأنسب لاحتياجك.',
      helpLink: 'المساعدة',
    },
    en: {
      pageTitle: 'Nawafeth — Request a Service',
      providerGateKicker: 'Current account mode',
      providerGateTitle: 'Request creation is available in client mode',
      providerGateDescription: 'You are using the platform in provider mode right now, so new service-request paths are paused to keep provider tools separate from client flows.',
      providerGateNote: 'Switch to client mode now and all request paths will appear on the same page immediately.',
      providerGateSwitch: 'Switch to client',
      providerGateProfile: 'Open My Profile',
      blockedTitle: 'Request paths are unavailable in provider mode',
      blockedDescription: 'To create an urgent request, a quote request, or any new service request, switch the account mode to client first.',
      blockedNote: 'After switching, you can continue the same flow without signing out.',
      blockedSwitch: 'Switch to client',
      blockedProfile: 'Go to My Profile',
      heroKicker: 'Ready to receive your request',
      ordersLink: 'My Orders',
      heroTitle: 'How would you like us to handle your service?',
      heroSubtitle: 'Choose the path that fits you best, and each path opens a tailored request form in the fewest possible steps.',
      statPaths: 'Request paths',
      statTime: 'Average submit time',
      statAvailability: 'Request intake',
      sectionTitle: 'Choose the request type',
      sectionTag: '3 paths',
      searchTitle: 'Find a service provider',
      searchBadge: 'Direct request',
      searchSubtitle: 'Browse providers, compare ratings, and start the conversation yourself right away.',
      searchChipLocation: 'Geographic filtering',
      searchChipRatings: 'Real ratings',
      searchChipChat: 'Instant chat',
      urgentTitle: 'Urgent request',
      urgentBadge: 'Most requested',
      urgentSubtitle: 'Instant alerts for the nearest qualified providers with fast responses within minutes.',
      urgentChipResponse: 'Immediate response',
      urgentChipCall: 'Direct call',
      urgentChipNearest: 'Nearest provider',
      quoteTitle: 'Request quotes',
      quoteBadge: 'Compare offers',
      quoteSubtitle: 'Receive multiple offers from trusted providers, compare them, and choose what fits you best.',
      quoteChipPricing: 'Competitive pricing',
      quoteChipCompare: 'Flexible comparison',
      quoteChipTrusted: 'Trusted providers',
      helpTitle: 'Not sure which path fits best?',
      helpSubtitle: 'Contact the support team and we will help you choose the right flow for your need.',
      helpLink: 'Help',
    },
  };

  function init() {
    document.addEventListener('nawafeth:languagechange', _handleLanguageChange);
    _applyStaticCopy();
    if (_guardProviderMode()) return;
    _bindAuthRequiredLinks();
  }

  function _handleLanguageChange() {
    _applyStaticCopy();
    _guardProviderMode();
  }

  function _guardProviderMode() {
    if (!window.Auth || typeof Auth.ensureServiceRequestAccess !== 'function') return;
    if (!Auth.ensureServiceRequestAccess({
      gateId: 'add-service-provider-block',
      contentId: 'add-service-client-content',
      target: '/add-service/',
      kicker: _copy('providerGateKicker'),
      title: _copy('providerGateTitle'),
      description: _copy('providerGateDescription'),
      note: _copy('providerGateNote'),
      switchLabel: _copy('providerGateSwitch'),
      profileLabel: _copy('providerGateProfile'),
    })) return true;
    return false;
  }

  function _bindAuthRequiredLinks() {
    document.querySelectorAll('a[data-auth-required="true"]').forEach((link) => {
      link.addEventListener('click', (event) => {
        if (window.Auth && typeof Auth.isServiceRequestBlockedForCurrentMode === 'function' && Auth.isServiceRequestBlockedForCurrentMode()) {
          event.preventDefault();
          Auth.renderProviderRequestBlock({
            gateId: 'add-service-provider-block',
            contentId: 'add-service-client-content',
            target: '/add-service/',
            kicker: _copy('providerGateKicker'),
            title: _copy('blockedTitle'),
            description: _copy('blockedDescription'),
            note: _copy('blockedNote'),
            switchLabel: _copy('blockedSwitch'),
            profileLabel: _copy('blockedProfile'),
          });
          return;
        }
        const serverAuth = window.NAWAFETH_SERVER_AUTH || null;
        const isLoggedIn = !!(
          (window.Auth && typeof Auth.isLoggedIn === 'function' && Auth.isLoggedIn())
          || (serverAuth && serverAuth.isAuthenticated)
        );
        if (isLoggedIn) return;
        event.preventDefault();
        const next = link.getAttribute('href') || '/';
        window.location.href = '/login/?next=' + encodeURIComponent(next);
      });
    });
  }

  function _applyStaticCopy() {
    document.title = _copy('pageTitle');
    _setText('add-service-provider-kicker', _copy('providerGateKicker'));
    _setText('add-service-provider-title', _copy('providerGateTitle'));
    _setText('add-service-provider-description', _copy('providerGateDescription'));
    _setText('add-service-provider-switch', _copy('providerGateSwitch'));
    _setText('add-service-provider-profile', _copy('providerGateProfile'));
    _setText('add-service-provider-note', _copy('providerGateNote'));
    _setText('add-service-hero-kicker', _copy('heroKicker'));
    _setText('add-service-orders-link', _copy('ordersLink'));
    _setText('add-service-hero-title', _copy('heroTitle'));
    _setText('add-service-hero-subtitle', _copy('heroSubtitle'));
    _setText('add-service-stat-paths', _copy('statPaths'));
    _setText('add-service-stat-time', _copy('statTime'));
    _setText('add-service-stat-availability', _copy('statAvailability'));
    _setText('add-service-section-title', _copy('sectionTitle'));
    _setText('add-service-section-tag', _copy('sectionTag'));
    _setText('add-service-search-title', _copy('searchTitle'));
    _setText('add-service-search-badge', _copy('searchBadge'));
    _setText('add-service-search-subtitle', _copy('searchSubtitle'));
    _setText('add-service-search-chip-location', _copy('searchChipLocation'));
    _setText('add-service-search-chip-ratings', _copy('searchChipRatings'));
    _setText('add-service-search-chip-chat', _copy('searchChipChat'));
    _setText('add-service-urgent-title', _copy('urgentTitle'));
    _setText('add-service-urgent-badge', _copy('urgentBadge'));
    _setText('add-service-urgent-subtitle', _copy('urgentSubtitle'));
    _setText('add-service-urgent-chip-response', _copy('urgentChipResponse'));
    _setText('add-service-urgent-chip-call', _copy('urgentChipCall'));
    _setText('add-service-urgent-chip-nearest', _copy('urgentChipNearest'));
    _setText('add-service-quote-title', _copy('quoteTitle'));
    _setText('add-service-quote-badge', _copy('quoteBadge'));
    _setText('add-service-quote-subtitle', _copy('quoteSubtitle'));
    _setText('add-service-quote-chip-pricing', _copy('quoteChipPricing'));
    _setText('add-service-quote-chip-compare', _copy('quoteChipCompare'));
    _setText('add-service-quote-chip-trusted', _copy('quoteChipTrusted'));
    _setText('add-service-help-title', _copy('helpTitle'));
    _setText('add-service-help-subtitle', _copy('helpSubtitle'));
    _setText('add-service-help-link', _copy('helpLink'));
  }

  function _setText(id, value) {
    const node = document.getElementById(id);
    if (node) node.textContent = value;
  }

  function _currentLang() {
    try {
      if (window.NawafethI18n && typeof window.NawafethI18n.getLanguage === 'function') {
        return window.NawafethI18n.getLanguage() === 'en' ? 'en' : 'ar';
      }
    } catch (_) {}
    try {
      return (localStorage.getItem('nw_lang') || 'ar').toLowerCase() === 'en' ? 'en' : 'ar';
    } catch (_) {
      return 'ar';
    }
  }

  function _copy(key) {
    const bundle = COPY[_currentLang()] || COPY.ar;
    return Object.prototype.hasOwnProperty.call(bundle, key) ? bundle[key] : COPY.ar[key] || '';
  }

  // Boot
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
  return {};
})();
