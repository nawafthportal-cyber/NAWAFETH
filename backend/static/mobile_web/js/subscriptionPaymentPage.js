'use strict';

const SubscriptionPaymentPage = (() => {
  const state = {
    subscriptionId: null,
    invoiceId: null,
    planId: null,
    requestCode: '',
    invoiceCode: '',
    requestStatus: '',
    invoiceStatus: '',
    amount: '0.00',
    currency: 'SAR',
    planName: '',
    durationLabel: '',
    method: 'mada',
    canPay: false,
  };
  let toastTimer = null;

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
    loadSubscriptionData();
  }

  function shell() {
    return document.getElementById('verifyPayContent');
  }

  function plansUrl() {
    const node = shell();
    return (node && node.dataset && node.dataset.plansUrl) || '/plans/';
  }

  function summaryUrlBase() {
    const node = shell();
    return (node && node.dataset && node.dataset.summaryUrl) || '/plans/summary/';
  }

  function cancelUrlTemplate() {
    const node = shell();
    return (node && node.dataset && node.dataset.cancelUrlTemplate) || '/api/subscriptions/cancel/__id__/';
  }

  function cancelUrl(subscriptionId) {
    return cancelUrlTemplate().replace('__id__', String(subscriptionId || '0'));
  }

  function summaryUrl(planId) {
    if (!planId) return plansUrl();
    return `${summaryUrlBase()}?plan_id=${encodeURIComponent(String(planId))}`;
  }

  function listUrl() {
    const node = shell();
    return (node && node.dataset && node.dataset.listUrl) || '/api/subscriptions/my/';
  }

  function initUrlTemplate() {
    const node = shell();
    return (node && node.dataset && node.dataset.initUrlTemplate) || '/api/billing/invoices/__id__/init-payment/';
  }

  function completeUrlTemplate() {
    const node = shell();
    return (node && node.dataset && node.dataset.completeUrlTemplate) || '/api/billing/invoices/__id__/complete-mock-payment/';
  }

  function initUrl(invoiceId) {
    return initUrlTemplate().replace('__id__', String(invoiceId || '0'));
  }

  function completeUrl(invoiceId) {
    return completeUrlTemplate().replace('__id__', String(invoiceId || '0'));
  }

  function bindStaticEvents() {
    const form = document.getElementById('verifyPayForm');
    const headerBack = document.getElementById('verifyPayHeaderBack');
    const backBtn = document.getElementById('verifyPayBackBtn');
    const submitBtn = document.getElementById('verifyPaySubmitBtn');

    [headerBack, backBtn].forEach((button) => {
      if (!button) return;
      button.addEventListener('click', async () => {
        await cancelAndReturn();
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
    const cardNameInput = document.getElementById('verifyPayCardName');
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

    [cardNameInput, numberInput, expiryInput, cvvInput].forEach((input) => {
      if (!input) return;
      input.addEventListener('input', () => clearFieldError(input.id));
      input.addEventListener('change', () => clearFieldError(input.id));
    });
  }

  function bindMethodInputs() {
    const inputs = Array.from(document.querySelectorAll('input[name="verify-payment-method"]'));
    inputs.forEach((input) => {
      input.addEventListener('change', () => {
        if (!input.checked) return;
        state.method = String(input.value || 'mada').trim() || 'mada';
        clearMethodError();
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

  function asList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    if (payload && Array.isArray(payload.items)) return payload.items;
    return [];
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
    const body = document.getElementById('verifyPayForm');
    const error = document.getElementById('verifyPayError');
    if (loadingNode) loadingNode.classList.toggle('hidden', !loading);
    if (body) body.classList.toggle('hidden', !!loading);
    if (loading && error) error.classList.add('hidden');
  }

  function setError(message) {
    const error = document.getElementById('verifyPayError');
    const body = document.getElementById('verifyPayForm');
    const loadingNode = document.getElementById('verifyPayLoading');
    if (loadingNode) loadingNode.classList.add('hidden');
    if (body) body.classList.add('hidden');
    if (!error) return;
    error.textContent = message || 'تعذر تحميل بيانات الدفع.';
    error.classList.remove('hidden');
    showToast(error.textContent, 'error');
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

  function showToast(message, tone) {
    const toast = document.getElementById('verifyPayToast');
    if (!toast || !message) return;
    toast.textContent = String(message || '').trim();
    toast.classList.remove('show', 'success', 'error', 'warning');
    if (tone === 'success') toast.classList.add('success');
    else if (tone === 'warning') toast.classList.add('warning');
    else toast.classList.add('error');
    requestAnimationFrame(() => toast.classList.add('show'));
    if (toastTimer) window.clearTimeout(toastTimer);
    toastTimer = window.setTimeout(() => {
      toast.classList.remove('show');
    }, 3600);
  }

  function methodGroup() {
    return document.querySelector('.verify-pay-methods');
  }

  function setMethodError(message) {
    const methods = methodGroup();
    const node = document.getElementById('verifyPayMethodError');
    if (methods) methods.classList.add('is-invalid');
    if (!node) return;
    node.textContent = message || '';
    node.classList.toggle('hidden', !message);
  }

  function clearMethodError() {
    const methods = methodGroup();
    const node = document.getElementById('verifyPayMethodError');
    if (methods) methods.classList.remove('is-invalid');
    if (node) {
      node.textContent = '';
      node.classList.add('hidden');
    }
  }

  function setFieldError(fieldId, message) {
    const input = document.getElementById(fieldId);
    const err = document.getElementById(fieldId + 'Error');
    if (input) {
      input.classList.add('is-invalid');
      input.setAttribute('aria-invalid', 'true');
    }
    if (err) {
      err.textContent = message || '';
      err.classList.toggle('hidden', !message);
    }
  }

  function clearFieldError(fieldId) {
    const input = document.getElementById(fieldId);
    const err = document.getElementById(fieldId + 'Error');
    if (input) {
      input.classList.remove('is-invalid');
      input.removeAttribute('aria-invalid');
    }
    if (err) {
      err.textContent = '';
      err.classList.add('hidden');
    }
  }

  function clearAllFieldErrors() {
    clearMethodError();
    ['verifyPayCardName', 'verifyPayCardNumber', 'verifyPayCardExpiry', 'verifyPayCardCvv'].forEach(clearFieldError);
  }

  function focusField(fieldId) {
    const node = document.getElementById(fieldId);
    if (!node || typeof node.focus !== 'function') return;
    try {
      node.focus({ preventScroll: false });
    } catch (_) {
      node.focus();
    }
  }

  function applyServerFieldError(message) {
    const text = String(message || '').trim();
    if (!text) return '';
    const lower = text.toLowerCase();
    if (lower.includes('mm/yy') || text.includes('تاريخ الانتهاء') || lower.includes('expiry')) {
      setFieldError('verifyPayCardExpiry', text);
      return 'verifyPayCardExpiry';
    }
    if (lower.includes('cvv') || lower.includes('cvc') || lower.includes('security code') || text.includes('رمز')) {
      setFieldError('verifyPayCardCvv', text);
      return 'verifyPayCardCvv';
    }
    if (text.includes('رقم البطاقة') || lower.includes('card number')) {
      setFieldError('verifyPayCardNumber', text);
      return 'verifyPayCardNumber';
    }
    if (text.includes('حامل البطاقة') || lower.includes('cardholder') || lower.includes('card holder')) {
      setFieldError('verifyPayCardName', text);
      return 'verifyPayCardName';
    }
    return '';
  }

  function money(value) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed.toFixed(2) : '0.00';
  }

  function invoiceStatusLabel(value) {
    const key = safeText(value).toLowerCase();
    const map = {
      draft: 'مسودة',
      pending: 'بانتظار الدفع',
      paid: 'مدفوعة',
      failed: 'فشلت',
      cancelled: 'ملغاة',
      refunded: 'مسترجعة',
    };
    return map[key] || (safeText(value) || '—');
  }

  function requestStatusLabel(value) {
    const key = safeText(value).toLowerCase();
    const map = {
      pending_payment: 'بانتظار الدفع',
      awaiting_review: 'بانتظار المراجعة',
      active: 'نشط',
      grace: 'فترة سماح',
      expired: 'منتهي',
      cancelled: 'ملغي',
    };
    return map[key] || (safeText(value) || '—');
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
    const requestStatusNode = document.getElementById('verifyPayRequestStatus');
    const invoiceStatusNode = document.getElementById('verifyPayInvoiceStatus');
    const amountNode = document.getElementById('verifyPayAmount');
    const planNameNode = document.getElementById('verifyPayPlanName');
    const durationNode = document.getElementById('verifyPayDuration');

    if (requestCodeNode) requestCodeNode.textContent = state.requestCode || '—';
    if (invoiceCodeNode) invoiceCodeNode.textContent = state.invoiceCode || '—';
    if (requestStatusNode) requestStatusNode.textContent = requestStatusLabel(state.requestStatus);
    if (invoiceStatusNode) invoiceStatusNode.textContent = invoiceStatusLabel(state.invoiceStatus);
    if (amountNode) amountNode.textContent = money(state.amount) + ' ريال';
    if (planNameNode) planNameNode.textContent = state.planName || '—';
    if (durationNode) durationNode.textContent = state.durationLabel || '—';

    updatePayButtonState();
  }

  async function fetchSubscriptions() {
    const response = await ApiClient.get(listUrl());
    if (!response.ok || !response.data) {
      throw new Error(apiErrorMessage(response, 'تعذر تحميل طلبات الاشتراك.'));
    }
    return asList(response.data);
  }

  function hydrateFromSubscription(item) {
    if (!item || typeof item !== 'object') {
      throw new Error('تعذر تحديد طلب الاشتراك المرتبط بعملية الدفع.');
    }

    const invoiceSummary = item.invoice_summary || {};
    const invoiceId = parseInt(String(item.invoice || invoiceSummary.id || ''), 10);
    if (!Number.isFinite(invoiceId) || invoiceId <= 0) {
      throw new Error('هذا الطلب لا يحتوي على فاتورة جاهزة للدفع.');
    }

    state.subscriptionId = parseInt(String(item.id || ''), 10) || null;
    state.invoiceId = invoiceId;
    state.planId = parseInt(String((item.plan && item.plan.id) || ''), 10) || null;
    state.requestCode = safeText(item.request_code) || (state.subscriptionId ? ('SD' + String(state.subscriptionId).padStart(6, '0')) : '—');
    state.invoiceCode = safeText(invoiceSummary.code) || ('IV' + String(invoiceId).padStart(6, '0'));
    state.requestStatus = safeText(item.provider_status_code || item.status).toLowerCase();
    state.invoiceStatus = safeText(invoiceSummary.status).toLowerCase();
    state.amount = safeText(invoiceSummary.total) || '0.00';
    state.currency = safeText(invoiceSummary.currency || 'SAR') || 'SAR';
    state.planName = safeText(item.plan && (item.plan.title || item.plan.name)) || 'الباقة';
    state.durationLabel = safeText(item.duration_label) || `${safeText(item.duration_count || '1')} مدة`;

    const invoicePaid = state.invoiceStatus === 'paid' || invoiceSummary.payment_effective === true;
    const requestNeedsPayment = state.requestStatus === 'pending_payment';
    state.canPay = requestNeedsPayment && !invoicePaid;

    if (invoicePaid || state.requestStatus === 'awaiting_review') {
      setStatusBanner('تم سداد هذا الطلب بالفعل. الباقة لا تتفعل مباشرة بعد الدفع، والطلب الآن بانتظار مراجعة واعتماد فريق الاشتراكات.', 'success');
    } else if (!requestNeedsPayment) {
      setStatusBanner('هذا الطلب ليس في حالة انتظار الدفع حالياً.', 'warning');
    } else {
      setStatusBanner('', '');
    }
  }

  async function loadSubscriptionData() {
    setLoading(true);
    try {
      const subscriptionId = parseIntParam('subscription_id');
      const invoiceId = parseIntParam('invoice_id');
      if (!subscriptionId && !invoiceId) {
        throw new Error('الرابط غير مكتمل. يجب أن يحتوي على subscription_id أو invoice_id.');
      }

      const subscriptions = await fetchSubscriptions();
      const selected = subscriptions.find((row) => {
        const rowId = parseInt(String((row && row.id) || ''), 10);
        const rowInvoiceId = parseInt(String((row && ((row.invoice_summary && row.invoice_summary.id) || row.invoice)) || ''), 10);
        if (subscriptionId > 0 && Number.isFinite(rowId) && rowId === subscriptionId) return true;
        return invoiceId > 0 && Number.isFinite(rowInvoiceId) && rowInvoiceId === invoiceId;
      });

      if (!selected) {
        throw new Error('تعذر العثور على طلب الاشتراك المرتبط بهذا الرابط.');
      }

      hydrateFromSubscription(selected);
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
    clearAllFieldErrors();
    const methodInput = document.querySelector('input[name="verify-payment-method"]:checked');
    const method = methodInput ? String(methodInput.value || '').trim() : '';
    if (!method) {
      const message = 'اختر وسيلة الدفع أولاً.';
      setMethodError(message);
      return { ok: false, message, focusFieldId: '' };
    }

    const cardName = valueOf('verifyPayCardName');
    if (cardName.length < 3) {
      const message = 'أدخل اسم حامل البطاقة بشكل صحيح.';
      setFieldError('verifyPayCardName', message);
      return { ok: false, message, focusFieldId: 'verifyPayCardName' };
    }

    const cardNumber = normalizeCardDigits(valueOf('verifyPayCardNumber'));
    if (cardNumber.length < 12 || cardNumber.length > 19 || !luhnCheck(cardNumber)) {
      const message = 'رقم البطاقة غير صالح.';
      setFieldError('verifyPayCardNumber', message);
      return { ok: false, message, focusFieldId: 'verifyPayCardNumber' };
    }

    const expiryRaw = valueOf('verifyPayCardExpiry');
    const expiryMatch = /^(\d{2})\/(\d{2})$/.exec(expiryRaw);
    if (!expiryMatch) {
      const message = 'أدخل تاريخ الانتهاء بصيغة MM/YY.';
      setFieldError('verifyPayCardExpiry', message);
      return { ok: false, message, focusFieldId: 'verifyPayCardExpiry' };
    }

    const expMonth = parseInt(expiryMatch[1], 10);
    const expYear = 2000 + parseInt(expiryMatch[2], 10);
    if (!Number.isFinite(expMonth) || expMonth < 1 || expMonth > 12) {
      const message = 'شهر انتهاء البطاقة غير صحيح.';
      setFieldError('verifyPayCardExpiry', message);
      return { ok: false, message, focusFieldId: 'verifyPayCardExpiry' };
    }
    const expiryDate = new Date(expYear, expMonth, 0, 23, 59, 59, 999);
    if (expiryDate.getTime() < Date.now()) {
      const message = 'البطاقة منتهية الصلاحية.';
      setFieldError('verifyPayCardExpiry', message);
      return { ok: false, message, focusFieldId: 'verifyPayCardExpiry' };
    }

    const cvv = normalizeCardDigits(valueOf('verifyPayCardCvv'));
    if (cvv.length < 3 || cvv.length > 4) {
      const message = 'رمز CVV غير صحيح.';
      setFieldError('verifyPayCardCvv', message);
      return { ok: false, message, focusFieldId: 'verifyPayCardCvv' };
    }

    return { ok: true, method };
  }

  function setSubmitting(submitting) {
    const submitBtn = document.getElementById('verifyPaySubmitBtn');
    const backBtn = document.getElementById('verifyPayBackBtn');
    if (submitBtn) {
      submitBtn.disabled = submitting || !state.canPay;
      submitBtn.textContent = submitting ? 'جاري تنفيذ الدفع...' : (state.canPay ? 'دفع الآن' : 'لا يوجد دفع مطلوب');
    }
    if (backBtn) backBtn.disabled = !!submitting;
  }

  async function cancelAndReturn() {
    const redirectTarget = summaryUrl(state.planId);
    if (!state.subscriptionId || state.requestStatus !== 'pending_payment' || state.invoiceStatus === 'paid') {
      window.location.href = redirectTarget;
      return;
    }

    setSubmitting(true);
    clearAllFieldErrors();
    setStatusBanner('', '');
    try {
      const response = await ApiClient.request(cancelUrl(state.subscriptionId), {
        method: 'POST',
        body: {},
      });
      if (!response.ok) {
        const message = apiErrorMessage(response, 'تعذر إلغاء طلب الاشتراك الحالي.');
        setStatusBanner(message, 'error');
        showToast(message, 'error');
        return;
      }

      const nextUrl = response.data && response.data.redirect_url ? String(response.data.redirect_url) : redirectTarget;
      window.location.href = nextUrl || redirectTarget;
    } catch (error) {
      const message = (error && error.message) || 'تعذر إلغاء الطلب الحالي.';
      setStatusBanner(message, 'error');
      showToast(message, 'error');
    } finally {
      setSubmitting(false);
    }
  }

  function showSuccessDialog() {
    const existing = document.getElementById('subpay-result-backdrop');
    if (existing) existing.remove();

    const backdrop = document.createElement('div');
    backdrop.id = 'subpay-result-backdrop';
    backdrop.className = 'subpay-result-backdrop';
    backdrop.innerHTML = `
      <div class="subpay-result-dialog" role="dialog" aria-modal="true" aria-label="تم الدفع بنجاح">
        <div class="subpay-result-code">رقم الطلب: ${safeText(state.requestCode || '—')}</div>
        <div class="subpay-result-body">
          <p>تمت عملية الدفع بنجاح</p>
          <p>تم السداد وتحويل الطلب إلى قائمة طلبات الاشتراكات بانتظار مراجعة واعتماد الفريق.</p>
          <p>لا يتم تفعيل الباقة مباشرة بعد الدفع، وسيتم إشعارك عند اعتماد الترقية.</p>
        </div>
        <button type="button" class="subpay-result-close">إغلاق</button>
      </div>
    `;
    document.body.appendChild(backdrop);

    return new Promise((resolve) => {
      const closeButton = backdrop.querySelector('.subpay-result-close');
      const close = () => {
        backdrop.remove();
        resolve();
      };
      if (closeButton) closeButton.addEventListener('click', close);
      backdrop.addEventListener('click', (event) => {
        if (event.target === backdrop) close();
      });
    });
  }

  async function submitPayment() {
    if (!state.canPay || !state.invoiceId) {
      const message = 'لا يوجد دفع مطلوب لهذا الطلب حالياً.';
      setStatusBanner(message, 'warning');
      showToast(message, 'warning');
      return;
    }

    const validation = validatePaymentFields();
    if (!validation.ok) {
      const message = validation.message || 'تحقق من بيانات البطاقة.';
      setStatusBanner(message, 'error');
      showToast(message, 'error');
      if (validation.focusFieldId) focusField(validation.focusFieldId);
      return;
    }

    state.method = validation.method || state.method || 'mada';
    const idempotencyKey = 'subscription-checkout-' + String(state.subscriptionId || '0') + '-' + String(state.invoiceId);

    setSubmitting(true);
    clearAllFieldErrors();
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
        const message = apiErrorMessage(initRes, 'تعذر بدء عملية الدفع.');
        const fieldId = applyServerFieldError(message);
        setStatusBanner(message, 'error');
        showToast(message, 'error');
        if (fieldId) focusField(fieldId);
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
        const message = apiErrorMessage(payRes, 'تعذر إتمام الدفع.');
        const fieldId = applyServerFieldError(message);
        setStatusBanner(message, 'error');
        showToast(message, 'error');
        if (fieldId) focusField(fieldId);
        return;
      }

      state.canPay = false;
      state.invoiceStatus = 'paid';
      state.requestStatus = 'awaiting_review';
      renderState();
      setStatusBanner('تم سداد الفاتورة بنجاح. لا يتم تفعيل الباقة مباشرة بعد الدفع، وقد انتقل الطلب الآن إلى قائمة طلبات الاشتراكات بانتظار مراجعة واعتماد الفريق.', 'success');
      showToast('تم سداد الفاتورة بنجاح.', 'success');
      await showSuccessDialog();
      window.location.href = plansUrl();
    } catch (error) {
      const message = (error && error.message) || 'حدث خطأ غير متوقع أثناء الدفع.';
      const fieldId = applyServerFieldError(message);
      setStatusBanner(message, 'error');
      showToast(message, 'error');
      if (fieldId) focusField(fieldId);
    } finally {
      setSubmitting(false);
    }
  }

  document.addEventListener('DOMContentLoaded', init);
  return { init };
})();
