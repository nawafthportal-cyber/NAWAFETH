/* ===================================================================
   promoPaymentPage.js — Dedicated promo checkout page
   =================================================================== */
'use strict';

const PromoPaymentPage = (() => {
  const REQUEST_TYPE_LABELS = {
    bundle: 'طلب ترويج متعدد الخدمات',
    banner_home: 'بنر الصفحة الرئيسية',
    featured_top5: 'شريط أبرز المختصين',
    featured_top10: 'شريط أبرز المختصين',
    boost_profile: 'شريط أبرز المختصين',
    push_notification: 'الرسائل الدعائية',
    banner_category: 'بنر صفحة القسم',
    banner_search: 'بنر صفحة البحث',
    popup_home: 'نافذة منبثقة رئيسية',
    popup_category: 'نافذة منبثقة داخل قسم',
    home_banner: 'بنر الصفحة الرئيسية',
    featured_specialists: 'شريط أبرز المختصين',
    portfolio_showcase: 'شريط البنرات والمشاريع',
    snapshots: 'شريط اللمحات',
    search_results: 'الظهور في قوائم البحث',
    promo_messages: 'الرسائل الدعائية',
    sponsorship: 'الرعاية',
  };

  const REQUEST_STATUS_LABELS = {
    new: 'جديد',
    in_review: 'قيد المراجعة',
    quoted: 'تم التسعير',
    pending_payment: 'بانتظار الدفع',
    awaiting_review: 'بانتظار المراجعة',
    in_progress: 'تحت المعالجة',
    active: 'مفعل',
    completed: 'مكتمل',
    rejected: 'مرفوض',
    expired: 'منتهي',
    cancelled: 'ملغي',
  };

  const INVOICE_STATUS_LABELS = {
    draft: 'مسودة',
    pending: 'بانتظار الدفع',
    paid: 'مدفوعة',
    failed: 'فشلت',
    cancelled: 'ملغاة',
    refunded: 'مسترجعة',
  };

  const state = {
    requestId: null,
    invoiceId: null,
    requestCode: '',
    invoiceCode: '',
    requestStatus: '',
    requestStatusLabel: '',
    invoiceStatus: '',
    requestType: '',
    requestTitle: '',
    amount: '0.00',
    method: 'mada',
    canPay: false,
  };

  function init() {
    if (!Auth.isLoggedIn()) {
      const gate = document.getElementById('verifyPayAuthGate');
      if (gate) gate.classList.remove('hidden');
      return;
    }

    const content = document.getElementById('verifyPayContent');
    if (content) content.classList.remove('hidden');

    bindStaticEvents();
    bindCardInputs();
    bindMethodInputs();
    loadRequestData();
  }

  function shell() {
    return document.getElementById('verifyPayContent');
  }

  function promotionUrl() {
    const node = shell();
    return (node && node.dataset && node.dataset.promotionUrl) || '/promotion/';
  }

  function detailUrlTemplate() {
    const node = shell();
    return (node && node.dataset && node.dataset.detailUrlTemplate) || '/api/promo/requests/__id__/';
  }

  function listUrl() {
    const node = shell();
    return (node && node.dataset && node.dataset.listUrl) || '/api/promo/requests/my/';
  }

  function initUrlTemplate() {
    const node = shell();
    return (node && node.dataset && node.dataset.initUrlTemplate) || '/api/billing/invoices/__id__/init-payment/';
  }

  function completeUrlTemplate() {
    const node = shell();
    return (node && node.dataset && node.dataset.completeUrlTemplate) || '/api/billing/invoices/__id__/complete-mock-payment/';
  }

  function detailUrl(requestId) {
    return detailUrlTemplate().replace('__id__', String(requestId || '0'));
  }

  function initUrl(invoiceId) {
    return initUrlTemplate().replace('__id__', String(invoiceId || '0'));
  }

  function completeUrl(invoiceId) {
    return completeUrlTemplate().replace('__id__', String(invoiceId || '0'));
  }

  function promotionUrlWithRequest(params) {
    const query = new URLSearchParams();
    if (state.requestId) query.set('request_id', String(state.requestId));
    if (params && params.payment) query.set('payment', String(params.payment));
    if (params && params.invoice && state.invoiceCode) query.set('invoice', String(state.invoiceCode));
    const queryString = query.toString();
    return promotionUrl() + (queryString ? ('?' + queryString) : '');
  }

  function bindStaticEvents() {
    const form = document.getElementById('verifyPayForm');
    const headerBack = document.getElementById('verifyPayHeaderBack');
    const backBtn = document.getElementById('verifyPayBackBtn');
    const submitBtn = document.getElementById('verifyPaySubmitBtn');

    [headerBack, backBtn].forEach((button) => {
      if (!button) return;
      button.addEventListener('click', () => {
        window.location.href = promotionUrlWithRequest();
      });
    });

    if (form) {
      form.addEventListener('submit', (event) => {
        event.preventDefault();
        submitPayment();
      });
    }

    if (submitBtn && !form) {
      submitBtn.addEventListener('click', submitPayment);
    }
  }

  function bindCardInputs() {
    const numberInput = document.getElementById('verifyPayCardNumber');
    const expiryInput = document.getElementById('verifyPayCardExpiry');
    const cvvInput = document.getElementById('verifyPayCardCvv');

    const normalizeNumber = () => {
      const digits = normalizeCardDigits(numberInput.value).slice(0, 19);
      numberInput.value = formatCardNumberDisplay(digits);
    };

    if (numberInput) {
      numberInput.addEventListener('input', normalizeNumber);
      numberInput.addEventListener('change', normalizeNumber);
    }

    const normalizeExpiry = () => {
      expiryInput.value = formatExpiryValue(expiryInput.value);
    };

    if (expiryInput) {
      expiryInput.addEventListener('input', normalizeExpiry);
      expiryInput.addEventListener('change', normalizeExpiry);
    }

    const normalizeCvv = () => {
      cvvInput.value = normalizeCardDigits(cvvInput.value).slice(0, 4);
    };

    if (cvvInput) {
      cvvInput.addEventListener('input', normalizeCvv);
      cvvInput.addEventListener('change', normalizeCvv);
    }
  }

  function bindMethodInputs() {
    const inputs = Array.from(document.querySelectorAll('input[name="verify-payment-method"]'));
    inputs.forEach((input) => {
      input.addEventListener('change', () => {
        if (!input.checked) return;
        state.method = String(input.value || 'mada').trim() || 'mada';
        syncMethodUi();
      });
    });
    syncMethodUi();
  }

  function syncMethodUi() {
    document.querySelectorAll('.verify-pay-method-option').forEach((label) => {
      const input = label.querySelector('input[name="verify-payment-method"]');
      label.classList.toggle('is-selected', !!(input && input.checked));
    });
  }

  function parseIntParam(name) {
    try {
      const params = new URLSearchParams(window.location.search || '');
      const raw = String(params.get(name) || '').trim();
      if (!raw) return 0;
      const parsed = parseInt(raw, 10);
      return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
    } catch (_) {
      return 0;
    }
  }

  function safeText(value) {
    if (value == null) return '';
    return String(value).trim();
  }

  function apiErrorMessage(response, fallback) {
    if (!response || !response.data) return fallback;
    const detail = response.data.detail;
    if (typeof detail === 'string' && detail.trim()) return detail.trim();
    if (typeof response.data === 'string') return response.data;
    return fallback;
  }

  function setLoading(loading) {
    const loadingNode = document.getElementById('verifyPayLoading');
    const body = document.getElementById('verifyPayForm') || document.getElementById('verifyPayBody');
    const error = document.getElementById('verifyPayError');
    if (loadingNode) loadingNode.classList.toggle('hidden', !loading);
    if (body) body.classList.toggle('hidden', !!loading);
    if (loading && error) error.classList.add('hidden');
  }

  function setError(message) {
    const error = document.getElementById('verifyPayError');
    const body = document.getElementById('verifyPayForm') || document.getElementById('verifyPayBody');
    const loadingNode = document.getElementById('verifyPayLoading');
    if (loadingNode) loadingNode.classList.add('hidden');
    if (body) body.classList.add('hidden');
    if (!error) return;
    error.textContent = message || 'تعذر تحميل بيانات الدفع.';
    error.classList.remove('hidden');
  }

  function setStatusBanner(message, tone) {
    const banner = document.getElementById('verifyPayStatusBanner');
    if (!banner) return;
    banner.classList.remove('hidden', 'is-success', 'is-error', 'is-warning');
    if (tone === 'success') banner.classList.add('is-success');
    if (tone === 'error') banner.classList.add('is-error');
    if (tone === 'warning') banner.classList.add('is-warning');
    banner.textContent = message || '';
    if (!message) banner.classList.add('hidden');
  }

  function money(value) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed.toFixed(2) : '0.00';
  }

  function invoiceStatusLabel(value) {
    const key = safeText(value).toLowerCase();
    return INVOICE_STATUS_LABELS[key] || (safeText(value) || '—');
  }

  function requestStatusLabel(value, fallbackLabel) {
    const key = safeText(value).toLowerCase();
    return safeText(fallbackLabel) || REQUEST_STATUS_LABELS[key] || (safeText(value) || '—');
  }

  function deriveRequestType(requestItem) {
    const items = Array.isArray(requestItem && requestItem.items) ? requestItem.items : [];
    if (items.length > 1) return REQUEST_TYPE_LABELS.bundle;
    const firstItem = items.length ? items[0] : null;
    const serviceType = safeText(firstItem && firstItem.service_type).toLowerCase();
    if (serviceType && REQUEST_TYPE_LABELS[serviceType]) return REQUEST_TYPE_LABELS[serviceType];
    const adType = safeText(requestItem && requestItem.ad_type).toLowerCase();
    return REQUEST_TYPE_LABELS[adType] || 'طلب ترويج';
  }

  function updatePayButtonState() {
    const submitBtn = document.getElementById('verifyPaySubmitBtn');
    if (!submitBtn) return;
    submitBtn.disabled = !state.canPay;
    submitBtn.textContent = state.canPay ? 'دفع الآن' : 'لا يوجد دفع مطلوب';
  }

  function renderState() {
    const requestCodeNode = document.getElementById('verifyPayRequestCode');
    const invoiceCodeNode = document.getElementById('verifyPayInvoiceCode');
    const requestTypeNode = document.getElementById('verifyPayRequestType');
    const requestTitleNode = document.getElementById('verifyPayRequestTitle');
    const requestStatusNode = document.getElementById('verifyPayRequestStatus');
    const invoiceStatusNode = document.getElementById('verifyPayInvoiceStatus');
    const amountNode = document.getElementById('verifyPayAmount');

    if (requestCodeNode) requestCodeNode.textContent = state.requestCode || '—';
    if (invoiceCodeNode) invoiceCodeNode.textContent = state.invoiceCode || '—';
    if (requestTypeNode) requestTypeNode.textContent = state.requestType || '—';
    if (requestTitleNode) requestTitleNode.textContent = state.requestTitle || '—';
    if (requestStatusNode) requestStatusNode.textContent = requestStatusLabel(state.requestStatus, state.requestStatusLabel);
    if (invoiceStatusNode) invoiceStatusNode.textContent = invoiceStatusLabel(state.invoiceStatus);
    if (amountNode) amountNode.textContent = money(state.amount) + ' ريال';

    updatePayButtonState();
  }

  function extractRows(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    if (payload && Array.isArray(payload.items)) return payload.items;
    return [];
  }

  async function fetchRequestById(requestId) {
    const response = await ApiClient.get(detailUrl(requestId));
    if (!response.ok || !response.data) {
      throw new Error(apiErrorMessage(response, 'تعذر تحميل تفاصيل طلب الترويج.'));
    }
    return response.data;
  }

  async function findRequestByInvoice(invoiceId) {
    const response = await ApiClient.get(listUrl());
    if (!response.ok || !response.data) {
      throw new Error(apiErrorMessage(response, 'تعذر تحميل طلبات الترويج.'));
    }
    const rows = extractRows(response.data);
    return rows.find((row) => {
      const invoiceValue = parseInt(String((row && row.invoice) || ''), 10);
      return Number.isFinite(invoiceValue) && invoiceValue === invoiceId;
    }) || null;
  }

  function hydrateFromRequest(requestItem) {
    if (!requestItem || typeof requestItem !== 'object') {
      throw new Error('تعذر تحديد الطلب المرتبط بعملية الدفع.');
    }

    const invoiceId = parseInt(String(requestItem.invoice || ''), 10);
    if (!Number.isFinite(invoiceId) || invoiceId <= 0) {
      throw new Error('هذا الطلب لا يحتوي على فاتورة جاهزة للدفع.');
    }

    state.requestId = parseInt(String(requestItem.id || ''), 10) || null;
    state.invoiceId = invoiceId;
    state.requestCode = safeText(requestItem.code) || (state.requestId ? ('PR' + String(state.requestId).padStart(6, '0')) : '—');
    state.invoiceCode = safeText(requestItem.invoice_code) || ('IV' + String(invoiceId).padStart(6, '0'));
    state.requestStatus = safeText(requestItem.provider_status_code || requestItem.status).toLowerCase();
    state.requestStatusLabel = safeText(requestItem.provider_status_label);
    state.invoiceStatus = safeText(requestItem.invoice_status).toLowerCase();
    state.requestType = deriveRequestType(requestItem);
    state.requestTitle = safeText(requestItem.title) || 'طلب ترويج';
    state.amount = safeText(requestItem.invoice_total) || '0.00';

    const paymentEffective = !!requestItem.payment_effective || state.invoiceStatus === 'paid';
    const paymentRequired = !!requestItem.payment_required || state.requestStatus === 'pending_payment';
    state.canPay = paymentRequired && !paymentEffective;

    if (paymentEffective) {
      setStatusBanner('تم سداد هذه الفاتورة مسبقًا. الطلب الآن بانتظار متابعة حالة التنفيذ من صفحة الترويج.', 'success');
    } else if (!paymentRequired) {
      setStatusBanner('هذا الطلب ليس في حالة انتظار الدفع حاليًا.', 'warning');
    } else {
      setStatusBanner('', '');
    }
  }

  async function loadRequestData() {
    setLoading(true);
    try {
      const requestId = parseIntParam('request_id');
      const invoiceId = parseIntParam('invoice_id');

      let requestItem = null;
      if (requestId > 0) {
        requestItem = await fetchRequestById(requestId);
      } else if (invoiceId > 0) {
        requestItem = await findRequestByInvoice(invoiceId);
        if (requestItem && requestItem.id) {
          requestItem = await fetchRequestById(requestItem.id);
        }
      } else {
        throw new Error('الرابط غير مكتمل. يجب أن يحتوي على request_id أو invoice_id.');
      }

      if (!requestItem) {
        throw new Error('تعذر العثور على طلب الترويج المرتبط بهذا الرابط.');
      }

      hydrateFromRequest(requestItem);
      renderState();
      setLoading(false);
    } catch (error) {
      setError((error && error.message) || 'تعذر تحميل صفحة الدفع.');
    }
  }

  function normalizeCardDigits(value) {
    return String(value || '').replace(/\D+/g, '');
  }

  function formatCardNumberDisplay(digits) {
    return String(digits || '').replace(/(.{4})/g, '$1 ').trim();
  }

  function formatExpiryValue(value) {
    const digits = normalizeCardDigits(value).slice(0, 4);
    if (digits.length <= 2) return digits;
    return digits.slice(0, 2) + '/' + digits.slice(2);
  }

  function luhnCheck(numberDigits) {
    let sum = 0;
    let alt = false;
    for (let i = numberDigits.length - 1; i >= 0; i -= 1) {
      let n = parseInt(numberDigits.charAt(i), 10);
      if (!Number.isFinite(n)) return false;
      if (alt) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alt = !alt;
    }
    return sum % 10 === 0;
  }

  function valueOf(id) {
    const node = document.getElementById(id);
    return node && node.value ? String(node.value).trim() : '';
  }

  function validatePaymentFields() {
    const methodInput = document.querySelector('input[name="verify-payment-method"]:checked');
    const method = methodInput ? String(methodInput.value || '').trim() : '';
    if (!method) {
      return { ok: false, message: 'اختر وسيلة الدفع أولًا.' };
    }

    const cardName = valueOf('verifyPayCardName');
    if (cardName.length < 3) {
      return { ok: false, message: 'أدخل اسم حامل البطاقة بشكل صحيح.' };
    }

    const cardNumber = normalizeCardDigits(valueOf('verifyPayCardNumber'));
    if (cardNumber.length < 12 || cardNumber.length > 19 || !luhnCheck(cardNumber)) {
      return { ok: false, message: 'رقم البطاقة غير صالح.' };
    }

    const expiryRaw = valueOf('verifyPayCardExpiry');
    const expiryMatch = /^(\d{2})\/(\d{2})$/.exec(expiryRaw);
    if (!expiryMatch) {
      return { ok: false, message: 'أدخل تاريخ الانتهاء بصيغة MM/YY.' };
    }

    const expMonth = parseInt(expiryMatch[1], 10);
    const expYear = 2000 + parseInt(expiryMatch[2], 10);
    if (!Number.isFinite(expMonth) || expMonth < 1 || expMonth > 12) {
      return { ok: false, message: 'شهر انتهاء البطاقة غير صحيح.' };
    }
    const expiryDate = new Date(expYear, expMonth, 0, 23, 59, 59, 999);
    if (expiryDate.getTime() < Date.now()) {
      return { ok: false, message: 'البطاقة منتهية الصلاحية.' };
    }

    const cvv = normalizeCardDigits(valueOf('verifyPayCardCvv'));
    if (cvv.length < 3 || cvv.length > 4) {
      return { ok: false, message: 'رمز CVV غير صحيح.' };
    }

    return { ok: true, method: method };
  }

  function setSubmitting(submitting) {
    const submitBtn = document.getElementById('verifyPaySubmitBtn');
    const backBtn = document.getElementById('verifyPayBackBtn');
    const headerBack = document.getElementById('verifyPayHeaderBack');
    if (submitBtn) {
      submitBtn.disabled = submitting || !state.canPay;
      submitBtn.textContent = submitting ? 'جاري تنفيذ الدفع...' : (state.canPay ? 'دفع الآن' : 'لا يوجد دفع مطلوب');
    }
    if (backBtn) backBtn.disabled = !!submitting;
    if (headerBack) headerBack.disabled = !!submitting;
  }

  async function submitPayment() {
    if (!state.canPay || !state.invoiceId) {
      setStatusBanner('لا يوجد دفع مطلوب لهذا الطلب حاليًا.', 'warning');
      return;
    }

    const validation = validatePaymentFields();
    if (!validation.ok) {
      setStatusBanner(validation.message || 'تحقق من بيانات البطاقة.', 'error');
      return;
    }

    state.method = validation.method || state.method || 'mada';
    const idempotencyKey = 'promo-checkout-' + String(state.requestId || '0') + '-' + String(state.invoiceId);

    setSubmitting(true);
    setStatusBanner('', '');
    try {
      const initRes = await ApiClient.request(initUrl(state.invoiceId), {
        method: 'POST',
        body: {
          provider: 'mock',
          idempotency_key: idempotencyKey,
          payment_method: state.method,
        },
      });
      if (!initRes.ok) {
        setStatusBanner(apiErrorMessage(initRes, 'تعذر بدء عملية الدفع.'), 'error');
        return;
      }

      const payRes = await ApiClient.request(completeUrl(state.invoiceId), {
        method: 'POST',
        body: {
          idempotency_key: idempotencyKey,
          payment_method: state.method,
        },
      });
      if (!payRes.ok) {
        setStatusBanner(apiErrorMessage(payRes, 'تعذر إتمام الدفع.'), 'error');
        return;
      }

      state.canPay = false;
      state.invoiceStatus = 'paid';
      state.requestStatus = 'awaiting_review';
      state.requestStatusLabel = 'بانتظار المراجعة';
      renderState();
      setStatusBanner('تم سداد الفاتورة بنجاح. الطلب الآن بانتظار مراجعة فريق الترويج، ولن يتم تفعيل الحملة إلا بعد اكتمال التنفيذ واعتماد الطلب.', 'success');

      window.setTimeout(() => {
        window.location.href = promotionUrlWithRequest({ payment: 'success', invoice: true });
      }, 1200);
    } catch (error) {
      setStatusBanner((error && error.message) || 'حدث خطأ غير متوقع أثناء الدفع.', 'error');
    } finally {
      setSubmitting(false);
    }
  }

  document.addEventListener('DOMContentLoaded', init);
  return { init };
})();