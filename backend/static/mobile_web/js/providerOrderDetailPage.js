/* Provider order detail page - Flutter parity */
'use strict';

const ProviderOrderDetailPage = (() => {
  const state = {
    id: null,
    order: null,
    actionLoading: false,
    completionFiles: [],
    toastTimer: null,
    offerAlreadySent: false,
  };
  const TYPE_LABEL = { normal: 'عادي', competitive: 'تنافسي', urgent: 'عاجل' };
  const STATUS_COLOR = { new: '#A56800', in_progress: '#E67E22', completed: '#2E7D32', cancelled: '#C62828' };

  function init() {
    if (!Auth.isLoggedIn()) return showGate();
    byId('pod-content').style.display = '';
    const m = location.pathname.match(/\/provider-orders\/(\d+)\/?$/);
    if (!m) return showError('رابط غير صحيح');
    state.id = Number(m[1]);
    const chat = byId('pod-chat-btn');
    if (chat) chat.addEventListener('click', () => toast('سيتم فتح الرسائل مع العميل قريباً'));
    loadDetail();
  }

  function showGate() {
    byId('auth-gate').style.display = '';
    const link = byId('pod-login-link');
    if (link) link.href = '/login/?next=' + encodeURIComponent(location.pathname);
  }

  async function loadDetail() {
    setLoading(true);
    hideError();
    const res = await ApiClient.get('/api/marketplace/provider/requests/' + state.id + '/detail/');
    setLoading(false);
    if (!res.ok || !res.data || typeof res.data !== 'object') return showError(extractError(res, 'تعذّر تحميل تفاصيل الطلب'));
    state.order = res.data;
    state.completionFiles = [];
    state.offerAlreadySent = false;
    render();
  }

  function render() {
    const o = state.order;
    if (!o) return;
    hideError();
    byId('pod-detail').style.display = '';

    setText('pod-client-name', val(o.client_name, 'غير متوفر'));
    setText('pod-client-phone', val(o.client_phone, 'غير متوفر'));
    setText('pod-client-city', val(o.city, 'غير متوفر'));

    const displayId = Number.isFinite(Number(o.id)) ? ('R' + String(o.id).padStart(6, '0')) : val(o.display_id, '-');
    setText('pod-display-id', displayId);

    const t = str(o.request_type).toLowerCase();
    const typeBadge = byId('pod-type-badge');
    if (t && t !== 'normal') {
      typeBadge.style.display = 'inline-flex';
      typeBadge.textContent = TYPE_LABEL[t] || t;
      const urgent = t === 'urgent';
      typeBadge.style.color = urgent ? '#C62828' : '#1565C0';
      typeBadge.style.backgroundColor = urgent ? 'rgba(198,40,40,.12)' : 'rgba(21,101,192,.12)';
    } else {
      typeBadge.style.display = 'none';
      typeBadge.textContent = '';
    }

    const c = str(o.category_name);
    const s = str(o.subcategory_name);
    const catEl = byId('pod-category');
    if (c) {
      catEl.style.display = '';
      catEl.textContent = s ? (c + ' / ' + s) : c;
    } else {
      catEl.style.display = 'none';
      catEl.textContent = '';
    }
    setText('pod-date', fmtDateTime(o.created_at));

    const group = statusGroup(o);
    const color = STATUS_COLOR[group] || '#9E9E9E';
    const status = byId('pod-status-pill');
    status.textContent = val(o.status_label, statusLabel(group));
    status.style.color = color;
    status.style.backgroundColor = color + '1A';
    status.style.borderColor = color + '66';

    setText('pod-title', val(o.title, '-'));
    setText('pod-description', val(o.description, '-'));

    renderAttachments(o);
    renderLogs(o);
    renderActions(o, group);
  }

  function renderAttachments(o) {
    const list = Array.isArray(o.attachments) ? o.attachments : [];
    const empty = byId('pod-attachments-empty');
    const fw = byId('pod-final-attachments-wrap');
    const rw = byId('pod-regular-attachments-wrap');
    const fh = byId('pod-final-attachments');
    const rh = byId('pod-regular-attachments');
    const rhTitle = byId('pod-regular-heading');
    fh.innerHTML = '';
    rh.innerHTML = '';
    if (!list.length) {
      empty.style.display = '';
      fw.style.display = 'none';
      rw.style.display = 'none';
      return;
    }
    empty.style.display = 'none';
    const deliveredAt = asDate(o.delivered_at);
    const finals = [];
    const regular = [];
    list.forEach((a) => {
      const created = asDate(a.created_at);
      if (deliveredAt && created && created.getTime() >= deliveredAt.getTime()) finals.push(a);
      else regular.push(a);
    });
    if (finals.length) {
      fw.style.display = '';
      finals.forEach((a) => fh.appendChild(attachmentRow(a)));
    } else fw.style.display = 'none';
    if (regular.length) {
      rw.style.display = '';
      rhTitle.style.display = finals.length ? '' : 'none';
      regular.forEach((a) => rh.appendChild(attachmentRow(a)));
    } else rw.style.display = 'none';
  }

  function attachmentRow(a) {
    const path = str(a.file_url) || str(a.file) || str(a.url);
    const href = path ? ApiClient.mediaUrl(path) : '';
    const type = (str(a.file_type) || 'document').toLowerCase();
    const name = path ? path.split('/').pop() : val(a.original_name, 'ملف');
    const el = document.createElement(href ? 'a' : 'div');
    el.className = 'pod-attachment-row';
    if (href) {
      el.href = href;
      el.target = '_blank';
      el.rel = 'noopener';
    }
    const code = document.createElement('span');
    code.className = 'pod-attachment-icon';
    code.textContent = type === 'image' ? 'IMG' : type === 'video' ? 'VID' : type === 'audio' ? 'AUD' : 'DOC';
    const title = document.createElement('span');
    title.className = 'pod-attachment-name';
    title.textContent = name || 'ملف';
    const badge = document.createElement('span');
    badge.className = 'pod-attachment-type';
    badge.textContent = type.toUpperCase();
    el.appendChild(code);
    el.appendChild(title);
    el.appendChild(badge);
    return el;
  }

  function renderLogs(o) {
    const section = byId('pod-logs-section');
    const root = byId('pod-logs');
    const logs = Array.isArray(o.status_logs) ? o.status_logs : [];
    root.innerHTML = '';
    if (!logs.length) {
      section.style.display = 'none';
      return;
    }
    section.style.display = '';
    logs.forEach((log) => {
      const row = document.createElement('div');
      row.className = 'pod-log-item';
      const dot = document.createElement('span');
      dot.className = 'pod-log-dot';
      const body = document.createElement('div');
      body.className = 'pod-log-body';
      const title = document.createElement('p');
      title.className = 'pod-log-title';
      title.textContent = val(log.from_status, '—') + ' → ' + val(log.to_status, '—');
      body.appendChild(title);
      const note = str(log.note);
      if (note) {
        const p = document.createElement('p');
        p.className = 'pod-log-note';
        p.textContent = note;
        body.appendChild(p);
      }
      if (asDate(log.created_at)) {
        const p = document.createElement('p');
        p.className = 'pod-log-date';
        p.textContent = fmtDateTime(log.created_at);
        body.appendChild(p);
      }
      row.appendChild(dot);
      row.appendChild(body);
      root.appendChild(row);
    });
  }

  function renderActions(o, group) {
    const root = byId('pod-actions');
    root.innerHTML = '';
    if (group === 'new') {
      if (isCompetitiveAvailable(o)) return renderCompetitiveOfferActions(root);
      if (isUrgentAvailable(o)) return renderUrgentAvailableActions(root);
      if (isCompetitiveAssigned(o)) return renderCompetitiveAssignedNewActions(root, o);
      return renderAssignedNewActions(root, o);
    }
    if (group === 'in_progress') return renderProgressActions(root, o);
    if (group === 'completed') return renderCompleted(root, o);
    if (group === 'cancelled') return renderCancelled(root, o);
  }

  function renderAssignedNewActions(root, o) {
    root.innerHTML = `
      <button type="button" class="pod-btn pod-btn-success pod-btn-block" id="pod-accept-btn" data-pod-action>قبول الطلب</button>
      <div class="pod-readonly-box" id="pod-client-rejection-box" style="display:none"><label>سبب رفض العميل للتفاصيل السابقة</label><p id="pod-client-rejection-note">-</p></div>
      <p class="pod-action-title" id="pod-progress-title"></p>
      <label class="pod-input-label" for="pod-expected-delivery">موعد التسليم المتوقع</label>
      <input type="datetime-local" class="pod-input" id="pod-expected-delivery">
      <div class="pod-grid-2">
        <div><label class="pod-input-label" for="pod-estimated-amount">قيمة الخدمة المقدرة (SR)</label><input type="number" class="pod-input" id="pod-estimated-amount" step="0.01" min="0" placeholder="0"></div>
        <div><label class="pod-input-label" for="pod-received-amount">المبلغ المستلم (SR)</label><input type="number" class="pod-input" id="pod-received-amount" step="0.01" min="0" placeholder="0"></div>
      </div>
      <label class="pod-input-label" for="pod-note">ملاحظة (اختياري)</label>
      <textarea class="pod-textarea" id="pod-note" rows="2" placeholder="ملاحظة (اختياري)"></textarea>
      <button type="button" class="pod-btn pod-btn-primary pod-btn-block" id="pod-progress-btn" data-pod-action></button>
      <div class="pod-divider"></div>
      <p class="pod-action-title">رفض الطلب</p>
      <label class="pod-input-label" for="pod-cancel-reason">سبب الإلغاء</label>
      <textarea class="pod-textarea" id="pod-cancel-reason" rows="2" placeholder="سبب الإلغاء..."></textarea>
      <button type="button" class="pod-btn pod-btn-outline-danger pod-btn-block" id="pod-reject-btn" data-pod-action>رفض الطلب</button>`;
    byId('pod-expected-delivery').value = toDateTimeInput(o.expected_delivery_at);
    byId('pod-estimated-amount').value = str(o.estimated_service_amount);
    byId('pod-received-amount').value = str(o.received_amount);
    byId('pod-cancel-reason').value = str(o.cancel_reason);
    const rejected = o.provider_inputs_approved === false;
    byId('pod-progress-title').textContent = rejected ? 'إعادة إرسال تفاصيل التنفيذ' : 'إرسال تفاصيل التنفيذ';
    byId('pod-progress-btn').textContent = rejected ? 'إعادة إرسال التفاصيل' : 'إرسال التفاصيل للعميل';
    const rbox = byId('pod-client-rejection-box');
    if (rejected) {
      rbox.style.display = '';
      setText('pod-client-rejection-note', val(o.provider_inputs_decision_note, '-'));
    } else rbox.style.display = 'none';
    byId('pod-accept-btn').addEventListener('click', acceptOrder);
    byId('pod-progress-btn').addEventListener('click', () => submitProgress(true));
    byId('pod-reject-btn').addEventListener('click', rejectOrder);
    setActionLoading(false);
  }

  function renderUrgentAvailableActions(root) {
    root.innerHTML = `
      <div class="pod-readonly-box">
        <label>طلب عاجل متاح</label>
        <p>هذا الطلب العاجل متاح الآن لك. عند القبول سيتم إسناده لك مباشرة.</p>
      </div>
      <button type="button" class="pod-btn pod-btn-danger pod-btn-block" id="pod-urgent-accept-btn" data-pod-action>قبول الطلب العاجل</button>`;
    byId('pod-urgent-accept-btn').addEventListener('click', acceptOrder);
    setActionLoading(false);
  }

  function renderCompetitiveOfferActions(root) {
    if (state.offerAlreadySent) {
      root.appendChild(readonly('عرض السعر', 'تم إرسال عرضك على هذا الطلب. بانتظار قرار العميل.'));
      setActionLoading(false);
      return;
    }

    root.innerHTML = `
      <div class="pod-readonly-box">
        <label>طلب عروض أسعار متاح</label>
        <p>أدخل السعر ومدة التنفيذ لإرسال عرضك للعميل. يمكنك إرسال عرض واحد لكل طلب.</p>
      </div>
      <div class="pod-grid-2">
        <div><label class="pod-input-label" for="pod-offer-price">سعر العرض (SR)</label><input type="number" class="pod-input" id="pod-offer-price" step="0.01" min="0" placeholder="0"></div>
        <div><label class="pod-input-label" for="pod-offer-duration">مدة التنفيذ (يوم)</label><input type="number" class="pod-input" id="pod-offer-duration" step="1" min="1" placeholder="5"></div>
      </div>
      <label class="pod-input-label" for="pod-offer-note">ملاحظة للعميل (اختياري)</label>
      <textarea class="pod-textarea" id="pod-offer-note" rows="3" placeholder="ملاحظة (اختياري)"></textarea>
      <button type="button" class="pod-btn pod-btn-primary pod-btn-block" id="pod-send-offer-btn" data-pod-action>إرسال عرض السعر</button>`;

    byId('pod-send-offer-btn').addEventListener('click', sendCompetitiveOffer);
    setActionLoading(false);
  }

  function renderCompetitiveAssignedNewActions(root, o) {
    root.innerHTML = `
      <div class="pod-readonly-box" id="pod-client-rejection-box" style="display:none"><label>سبب رفض العميل للتفاصيل السابقة</label><p id="pod-client-rejection-note">-</p></div>
      <p class="pod-action-title" id="pod-progress-title"></p>
      <label class="pod-input-label" for="pod-expected-delivery">موعد التسليم المتوقع</label>
      <input type="datetime-local" class="pod-input" id="pod-expected-delivery">
      <div class="pod-grid-2">
        <div><label class="pod-input-label" for="pod-estimated-amount">قيمة الخدمة المقدرة (SR)</label><input type="number" class="pod-input" id="pod-estimated-amount" step="0.01" min="0" placeholder="0"></div>
        <div><label class="pod-input-label" for="pod-received-amount">المبلغ المستلم (SR)</label><input type="number" class="pod-input" id="pod-received-amount" step="0.01" min="0" placeholder="0"></div>
      </div>
      <label class="pod-input-label" for="pod-note">ملاحظة (اختياري)</label>
      <textarea class="pod-textarea" id="pod-note" rows="2" placeholder="ملاحظة (اختياري)"></textarea>
      <button type="button" class="pod-btn pod-btn-primary pod-btn-block" id="pod-progress-btn" data-pod-action></button>`;
    byId('pod-expected-delivery').value = toDateTimeInput(o.expected_delivery_at);
    byId('pod-estimated-amount').value = str(o.estimated_service_amount);
    byId('pod-received-amount').value = str(o.received_amount);

    const rejected = o.provider_inputs_approved === false;
    byId('pod-progress-title').textContent = rejected ? 'إعادة إرسال تفاصيل التنفيذ' : 'إرسال تفاصيل التنفيذ';
    byId('pod-progress-btn').textContent = rejected ? 'إعادة إرسال التفاصيل' : 'إرسال التفاصيل للعميل';
    const rbox = byId('pod-client-rejection-box');
    if (rejected) {
      rbox.style.display = '';
      setText('pod-client-rejection-note', val(o.provider_inputs_decision_note, '-'));
    } else rbox.style.display = 'none';

    byId('pod-progress-btn').addEventListener('click', () => submitProgress(true));
    setActionLoading(false);
  }

  function renderProgressActions(root, o) {
    root.innerHTML = `
      <p class="pod-action-title">تحديث التقدم</p>
      <label class="pod-input-label" for="pod-expected-delivery">موعد التسليم المتوقع</label>
      <input type="datetime-local" class="pod-input" id="pod-expected-delivery">
      <div class="pod-grid-2">
        <div><label class="pod-input-label" for="pod-estimated-amount">قيمة الخدمة المقدرة (SR)</label><input type="number" class="pod-input" id="pod-estimated-amount" step="0.01" min="0" placeholder="0"></div>
        <div><label class="pod-input-label" for="pod-received-amount">المبلغ المستلم (SR)</label><input type="number" class="pod-input" id="pod-received-amount" step="0.01" min="0" placeholder="0"></div>
      </div>
      <label class="pod-input-label" for="pod-note">ملاحظة (اختياري)</label>
      <textarea class="pod-textarea" id="pod-note" rows="2" placeholder="ملاحظة (اختياري)"></textarea>
      <button type="button" class="pod-btn pod-btn-warning pod-btn-block" id="pod-progress-btn" data-pod-action>تحديث التقدم</button>
      <div class="pod-divider"></div>
      <p class="pod-action-title">إكمال الطلب</p>
      <label class="pod-input-label" for="pod-delivered-at">موعد التسليم الفعلي</label>
      <input type="datetime-local" class="pod-input" id="pod-delivered-at">
      <label class="pod-input-label" for="pod-actual-amount">قيمة الخدمة الفعلية (SR)</label>
      <input type="number" class="pod-input" id="pod-actual-amount" step="0.01" min="0" placeholder="0">
      <p class="pod-input-label">مرفقات الإكمال (فواتير/صور/ملفات)</p>
      <label class="pod-file-picker"><input type="file" id="pod-completion-files" multiple><span class="pod-btn pod-btn-outline pod-btn-block">إضافة مرفقات</span></label>
      <div id="pod-completion-files-list" class="pod-file-list"></div>
      <button type="button" class="pod-btn pod-btn-success pod-btn-block" id="pod-complete-btn" data-pod-action>إكمال الطلب</button>
      <div class="pod-divider"></div>
      <p class="pod-action-title">رفض / إلغاء الطلب</p>
      <label class="pod-input-label" for="pod-cancel-reason">سبب الإلغاء</label>
      <textarea class="pod-textarea" id="pod-cancel-reason" rows="2" placeholder="سبب الإلغاء..."></textarea>
      <button type="button" class="pod-btn pod-btn-outline-danger pod-btn-block" id="pod-reject-btn" data-pod-action>إلغاء الطلب</button>`;
    byId('pod-expected-delivery').value = toDateTimeInput(o.expected_delivery_at);
    byId('pod-estimated-amount').value = str(o.estimated_service_amount);
    byId('pod-received-amount').value = str(o.received_amount);
    byId('pod-delivered-at').value = toDateTimeInput(o.delivered_at);
    byId('pod-actual-amount').value = str(o.actual_service_amount);
    byId('pod-cancel-reason').value = str(o.cancel_reason);
    byId('pod-completion-files').addEventListener('change', onFilesPick);
    byId('pod-progress-btn').addEventListener('click', () => submitProgress(false));
    byId('pod-complete-btn').addEventListener('click', completeOrder);
    byId('pod-reject-btn').addEventListener('click', rejectOrder);
    renderPickedFiles();
    setActionLoading(false);
  }

  function renderCompleted(root, o) {
    root.appendChild(readonly('موعد التسليم الفعلي', o.delivered_at ? fmtDateOnly(o.delivered_at) : '-'));
    root.appendChild(readonly('قيمة الخدمة الفعلية (SR)', val(o.actual_service_amount, '-')));
    if (o.review_rating !== null && o.review_rating !== undefined) {
      root.appendChild(readonly('تقييم العميل', String(o.review_rating) + '/5 — ' + str(o.review_comment)));
    }
  }

  function renderCancelled(root, o) {
    root.appendChild(readonly('تاريخ الإلغاء', o.canceled_at ? fmtDateOnly(o.canceled_at) : '-'));
    root.appendChild(readonly('سبب الإلغاء', val(o.cancel_reason, '-')));
  }

  function readonly(label, value) {
    const box = document.createElement('div');
    box.className = 'pod-readonly-box';
    const l = document.createElement('label');
    l.textContent = label;
    const p = document.createElement('p');
    p.textContent = val(value, '-');
    box.appendChild(l);
    box.appendChild(p);
    return box;
  }

  function onFilesPick(e) {
    const files = Array.from(e.target.files || []);
    files.forEach((f) => {
      if (!state.completionFiles.some((x) => x.name === f.name && x.size === f.size && x.lastModified === f.lastModified)) {
        state.completionFiles.push(f);
      }
    });
    e.target.value = '';
    renderPickedFiles();
  }

  function renderPickedFiles() {
    const root = byId('pod-completion-files-list');
    if (!root) return;
    root.innerHTML = '';
    state.completionFiles.forEach((f, i) => {
      const row = document.createElement('div');
      row.className = 'pod-file-row';
      const name = document.createElement('span');
      name.className = 'pod-file-name';
      name.textContent = f.name;
      const del = document.createElement('button');
      del.type = 'button';
      del.className = 'pod-file-remove';
      del.textContent = 'إزالة';
      del.setAttribute('data-pod-action', '1');
      del.disabled = state.actionLoading;
      del.addEventListener('click', () => {
        if (state.actionLoading) return;
        state.completionFiles.splice(i, 1);
        renderPickedFiles();
      });
      row.appendChild(name);
      row.appendChild(del);
      root.appendChild(row);
    });
  }

  async function acceptOrder() {
    if (state.actionLoading) return;
    const order = state.order;
    if (!order) return;
    setActionLoading(true);
    const res = isUrgentAvailable(order)
      ? await ApiClient.request('/api/marketplace/requests/urgent/accept/', {
        method: 'POST',
        body: { request_id: state.id },
      })
      : await ApiClient.request('/api/marketplace/provider/requests/' + state.id + '/accept/', { method: 'POST' });
    setActionLoading(false);
    if (!res.ok) return toast(extractError(res, 'فشلت العملية'));
    toast(isUrgentAvailable(order)
      ? 'تم قبول الطلب العاجل بنجاح'
      : 'تم قبول الطلب. أرسل تفاصيل التنفيذ للعميل');
    loadDetail();
  }

  async function sendCompetitiveOffer() {
    if (state.actionLoading) return;
    const priceRaw = str(byId('pod-offer-price').value);
    const durationRaw = str(byId('pod-offer-duration').value);
    const noteRaw = str(byId('pod-offer-note').value);

    const price = Number(priceRaw);
    if (!priceRaw || !Number.isFinite(price) || price <= 0) return toast('أدخل سعر عرض صالح');

    const duration = Number(durationRaw);
    if (!durationRaw || !Number.isInteger(duration) || duration <= 0) {
      return toast('أدخل مدة تنفيذ بالأيام بشكل صحيح');
    }

    const body = {
      price: priceRaw,
      duration_days: duration,
    };
    if (noteRaw) body.note = noteRaw;

    setActionLoading(true);
    const res = await ApiClient.request('/api/marketplace/requests/' + state.id + '/offers/create/', {
      method: 'POST',
      body,
    });
    setActionLoading(false);

    if (res.ok) {
      state.offerAlreadySent = true;
      toast('تم إرسال عرض السعر بنجاح');
      renderActions(state.order, statusGroup(state.order));
      return;
    }

    if (res.status === 409) {
      state.offerAlreadySent = true;
      toast('تم إرسال عرض مسبقًا على هذا الطلب');
      renderActions(state.order, statusGroup(state.order));
      return;
    }

    toast(extractError(res, 'تعذّر إرسال العرض'));
  }

  async function submitProgress(isNew) {
    if (state.actionLoading) return;
    const expected = dateToIso(byId('pod-expected-delivery').value);
    const est = str(byId('pod-estimated-amount').value);
    const rec = str(byId('pod-received-amount').value);
    const note = str(byId('pod-note').value);
    if (isNew && !expected) return toast('حدد موعد التسليم المتوقع');
    if (isNew && (!est || !rec)) return toast('أدخل القيمة المقدرة والمبلغ المستلم');
    if ((est && !rec) || (!est && rec)) return toast('أدخل القيمة المقدرة والمبلغ المستلم معًا');
    const body = {};
    if (expected) body.expected_delivery_at = expected;
    if (est) body.estimated_service_amount = est;
    if (rec) body.received_amount = rec;
    if (note) body.note = note;
    if (!Object.keys(body).length) return toast('أدخل ملاحظة أو حدّث بيانات التنفيذ');
    setActionLoading(true);
    const res = await ApiClient.request('/api/marketplace/provider/requests/' + state.id + '/progress-update/', { method: 'POST', body });
    setActionLoading(false);
    if (!res.ok) return toast(extractError(res, 'فشلت العملية'));
    toast(isNew ? 'تم إرسال تحديثك للعميل بانتظار القرار' : 'تم تحديث التقدم');
    loadDetail();
  }

  async function completeOrder() {
    if (state.actionLoading) return;
    const delivered = dateToIso(byId('pod-delivered-at').value);
    const actual = str(byId('pod-actual-amount').value);
    const noteEl = byId('pod-note');
    const note = noteEl ? str(noteEl.value) : '';
    if (!delivered) return toast('حدد موعد التسليم الفعلي');
    if (!actual) return toast('أدخل قيمة الخدمة الفعلية');
    setActionLoading(true);
    let res;
    if (state.completionFiles.length) {
      const fd = new FormData();
      fd.append('delivered_at', delivered);
      fd.append('actual_service_amount', actual);
      if (note) fd.append('note', note);
      state.completionFiles.forEach((f) => fd.append('attachments', f, f.name));
      res = await ApiClient.request('/api/marketplace/requests/' + state.id + '/complete/', { method: 'POST', body: fd, formData: true });
    } else {
      const body = { delivered_at: delivered, actual_service_amount: actual };
      if (note) body.note = note;
      res = await ApiClient.request('/api/marketplace/requests/' + state.id + '/complete/', { method: 'POST', body });
    }
    setActionLoading(false);
    if (!res.ok) return toast(extractError(res, 'فشلت العملية'));
    toast('تم إكمال الطلب');
    state.completionFiles = [];
    loadDetail();
  }

  async function rejectOrder() {
    if (state.actionLoading) return;
    const reason = str(byId('pod-cancel-reason').value);
    if (!reason) return toast('الرجاء كتابة سبب الإلغاء');
    setActionLoading(true);
    const res = await ApiClient.request('/api/marketplace/provider/requests/' + state.id + '/reject/', {
      method: 'POST',
      body: { canceled_at: new Date().toISOString(), cancel_reason: reason },
    });
    setActionLoading(false);
    if (!res.ok) return toast(extractError(res, 'فشلت العملية'));
    toast('تم إلغاء الطلب');
    loadDetail();
  }

  function setActionLoading(v) {
    state.actionLoading = v;
    document.querySelectorAll('#pod-actions [data-pod-action]').forEach((el) => { el.disabled = v; });
    const input = byId('pod-completion-files');
    if (input) input.disabled = v;
  }

  function setLoading(v) {
    byId('pod-loading').style.display = v ? '' : 'none';
    if (v) byId('pod-detail').style.display = 'none';
  }

  function showError(msg) {
    const box = byId('pod-error');
    box.innerHTML = '';
    const text = document.createElement('span');
    text.textContent = msg;
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'pod-error-retry';
    btn.textContent = 'إعادة المحاولة';
    btn.addEventListener('click', loadDetail);
    box.appendChild(text);
    box.appendChild(btn);
    box.style.display = '';
    byId('pod-detail').style.display = 'none';
  }

  function hideError() {
    byId('pod-error').style.display = 'none';
    byId('pod-error').innerHTML = '';
  }

  function toast(msg) {
    const el = byId('pod-toast');
    if (!el) return alert(msg);
    el.textContent = msg;
    el.classList.add('show');
    if (state.toastTimer) clearTimeout(state.toastTimer);
    state.toastTimer = setTimeout(() => el.classList.remove('show'), 2600);
  }

  function extractError(res, fallback) {
    if (!res || !res.data) return fallback;
    const d = res.data;
    if (typeof d === 'string' && d.trim()) return d.trim();
    if (typeof d.detail === 'string' && d.detail.trim()) return d.detail.trim();
    if (typeof d === 'object') {
      for (const k of Object.keys(d)) {
        const v = d[k];
        if (typeof v === 'string' && v.trim()) return v.trim();
        if (Array.isArray(v) && v.length && typeof v[0] === 'string') return v[0];
      }
    }
    return fallback;
  }

  function statusGroup(o) {
    const g = str(o.status_group).toLowerCase();
    if (['new', 'in_progress', 'completed', 'cancelled'].includes(g)) return g;
    const s = str(o.status).toLowerCase();
    if (s === 'in_progress') return 'in_progress';
    if (s === 'completed') return 'completed';
    if (s === 'cancelled' || s === 'canceled') return 'cancelled';
    return 'new';
  }

  function statusLabel(group) {
    if (group === 'in_progress') return 'تحت التنفيذ';
    if (group === 'completed') return 'مكتمل';
    if (group === 'cancelled') return 'ملغي';
    return 'جديد';
  }

  function requestType(o) {
    return str(o && o.request_type).toLowerCase();
  }

  function hasAssignedProvider(o) {
    const provider = o && o.provider;
    if (provider === null || provider === undefined || provider === '') return false;
    if (typeof provider === 'object') return provider.id !== null && provider.id !== undefined;
    return true;
  }

  function isCompetitiveAvailable(o) {
    return requestType(o) === 'competitive' && !hasAssignedProvider(o);
  }

  function isUrgentAvailable(o) {
    return requestType(o) === 'urgent' && !hasAssignedProvider(o);
  }

  function isCompetitiveAssigned(o) {
    return requestType(o) === 'competitive' && hasAssignedProvider(o);
  }

  function fmtDateTime(v) {
    const d = asDate(v);
    if (!d) return '-';
    return arDigits(pad(d.getHours()) + ':' + pad(d.getMinutes()) + '  ' + pad(d.getDate()) + '/' + pad(d.getMonth() + 1) + '/' + d.getFullYear());
  }

  function fmtDateOnly(v) {
    const d = asDate(v);
    if (!d) return '-';
    return arDigits(pad(d.getDate()) + '/' + pad(d.getMonth() + 1) + '/' + d.getFullYear());
  }

  function toDateTimeInput(v) {
    const d = asDate(v);
    if (!d) return '';
    return (
      d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate())
      + 'T' + pad(d.getHours()) + ':' + pad(d.getMinutes())
    );
  }

  function dateToIso(v) {
    const c = str(v);
    if (!c) return null;
    if (/^\d{4}-\d{2}-\d{2}$/.test(c)) return c + 'T00:00:00';
    if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(c)) return c + ':00';
    if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/.test(c)) return c;
    return null;
  }

  function asDate(v) {
    if (!v) return null;
    const d = v instanceof Date ? v : new Date(v);
    return Number.isNaN(d.getTime()) ? null : d;
  }

  function arDigits(v) { return String(v).replace(/\d/g, (d) => '٠١٢٣٤٥٦٧٨٩'[Number(d)]); }
  function pad(n) { return String(n).padStart(2, '0'); }
  function str(v) { return v === null || v === undefined ? '' : String(v).trim(); }
  function val(v, f) { const s = str(v); return s || f; }
  function setText(id, value) { const el = byId(id); if (el) el.textContent = value; }
  function byId(id) { return document.getElementById(id); }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
  return { init };
})();
