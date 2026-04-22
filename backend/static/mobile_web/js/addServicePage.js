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
  function init() {
    if (_guardProviderMode()) return;
    _bindAuthRequiredLinks();
  }

  function _guardProviderMode() {
    if (!window.Auth || typeof Auth.ensureServiceRequestAccess !== 'function') return;
    if (!Auth.ensureServiceRequestAccess({
      gateId: 'add-service-provider-block',
      contentId: 'add-service-client-content',
      target: '/add-service/',
      title: 'إنشاء الطلبات متاح في وضع العميل',
      description: 'أنت تستخدم المنصة الآن بوضع مقدم الخدمة، لذلك تم إيقاف مسارات طلب الخدمات الجديدة حتى لا تختلط أدوات المزود بمسارات العميل.',
      note: 'بدّل نوع الحساب إلى عميل الآن، ثم ستظهر لك جميع مسارات الطلب مباشرة في نفس الصفحة.',
      switchLabel: 'التبديل إلى عميل',
      profileLabel: 'فتح نافذتي',
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
            title: 'مسارات الطلب غير متاحة في وضع مقدم الخدمة',
            description: 'لإنشاء طلب عاجل أو طلب عروض أسعار أو أي طلب خدمة جديد، بدّل نوع الحساب إلى عميل أولًا.',
            note: 'بعد التبديل ستتمكن من متابعة نفس المسار بدون تسجيل خروج.',
            switchLabel: 'التبديل إلى عميل',
            profileLabel: 'الذهاب إلى نافذتي',
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

  // Boot
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
  return {};
})();
