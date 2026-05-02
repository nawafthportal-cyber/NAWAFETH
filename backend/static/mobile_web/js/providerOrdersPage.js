/* ===================================================================
   providerOrdersPage.js — Provider Orders Management
   - Assigned requests
   - Available competitive requests
   - Available urgent requests
   =================================================================== */
'use strict';

const ProviderOrdersPage = (() => {
  const COPY = {
    ar: {
      pageTitle: 'نوافــذ — إدارة الطلبات',
      authGateTitle: 'تسجيل الدخول مطلوب',
      authGateDescription: 'يجب تسجيل الدخول أولًا للوصول إلى لوحة إدارة الطلبات ومتابعة الطلبات المسندة والعروض التنافسية والطلبات العاجلة من مكان واحد.',
      authGateButton: 'تسجيل الدخول',
      heroAria: 'واجهة إدارة الطلبات',
      resultsAria: 'نتائج الطلبات',
      backAria: 'العودة للوحة المزود',
      heroPanelKicker: 'مركز التشغيل',
      heroPanelTitle: 'لوحة أكثر هدوءًا ووضوحًا',
      heroPanelBody: 'نظرة مركزة تساعدك على التقاط الطلبات المهمة سريعًا بدون تشتيت أو ازدحام بصري.',
      heroPanelItem1: 'انتقال سريع بين الطلبات المسندة والتنافسية والعاجلة.',
      heroPanelItem2: 'ملخص واضح للحالة والمدينة والقيمة وموعد التسليم.',
      heroPanelItem3: 'واجهة أكثر اتزانًا على الجوال والديسكتوب.',
      heroKicker: 'مركز تشغيل طلباتك',
      heroTitle: 'إدارة الطلبات',
      heroSubtitle: 'واجهة واحدة لمتابعة الطلبات المسندة لك، واغتنام الفرص التنافسية، والتعامل السريع مع الطلبات العاجلة بتوزيع أكثر هدوءًا ووضوحًا على الجوال والديسكتوب.',
      heroPill1: 'متابعة لحظية',
      heroPill2: 'بحث وفرز سريع',
      heroPill3: 'عرض احترافي متعدد الحالات',
      kpiAssignedLabel: 'المسندة',
      kpiAssignedNote: 'طلبات نشطة داخل سير العمل',
      kpiCompetitiveLabel: 'التنافسية',
      kpiCompetitiveNote: 'فرص متاحة للتسعير',
      kpiUrgentLabel: 'العاجلة',
      kpiUrgentNote: 'تحتاج استجابة أسرع',
      tabAssignedLabel: 'المسندة لي',
      tabAssignedNote: 'تشغيل وتنفيذ',
      tabCompetitiveLabel: 'عروض الأسعار',
      tabCompetitiveNote: 'فرص تنافسية',
      tabUrgentLabel: 'الطلبات العاجلة',
      tabUrgentNote: 'استجابة فورية',
      sortLabel: 'الترتيب',
      sortNewest: 'الأحدث',
      sortOldest: 'الأقدم',
      sortStatus: 'حسب الحالة',
      sortCity: 'حسب المدينة',
      sortAmount: 'الأعلى قيمة',
      sortDeadline: 'الأقرب موعدًا',
      refresh: 'تحديث البيانات',
      refreshing: 'جاري التحديث...',
      clearSearch: 'مسح البحث',
      controlsKicker: 'لوحة التحكم',
      controlsTitle: 'تصفية ومتابعة',
      searchLabel: 'البحث الذكي',
      assignedSearchPlaceholder: 'بحث برقم الطلب أو العنوان أو العميل أو المدينة',
      competitiveSearchPlaceholder: 'بحث في عروض الأسعار المتاحة برقم الطلب أو العنوان أو المدينة',
      urgentSearchPlaceholder: 'بحث في الطلبات العاجلة برقم الطلب أو العنوان أو المدينة',
      statusFilterLabel: 'فلتر الحالة',
      statusAll: 'الكل',
      statusGroupNew: 'جديد',
      statusGroupInProgress: 'تحت التنفيذ',
      statusGroupCompleted: 'مكتمل',
      statusGroupCancelled: 'ملغي',
      legend1: 'طلب جديد يحتاج مراجعة أو قبول',
      legend2: 'طلب قيد التنفيذ أو المتابعة',
      legend3: 'طلب مكتمل وتم إغلاقه',
      legend4: 'طلب ملغي أو منتهي',
      sideNoteTitle: 'إيقاع تشغيل أنظف',
      sideNoteBody: 'استخدم التبويبات العلوية للتبديل بين نوع الطلبات، ثم ضيّق النتائج بالحالة والبحث من هنا بسرعة.',
      loading: 'جاري تحميل الطلبات...',
      resultsChipAssigned: 'عرض تشغيلي للطلبات المسندة',
      resultsChipCompetitive: 'فرص جاهزة للتسعير والمراجعة',
      resultsChipUrgent: 'طلبات عاجلة تستحق الأولوية',
      activeAssignedLabel: 'الطلبات المسندة لي',
      activeCompetitiveLabel: 'عروض الأسعار المتاحة',
      activeUrgentLabel: 'الطلبات العاجلة المتاحة',
      groupAllLabel: 'كل الحالات',
      groupNewLabel: 'جديد',
      groupInProgressLabel: 'تحت التنفيذ',
      groupCompletedLabel: 'مكتمل',
      groupCancelledLabel: 'ملغي',
      searchCountLabel: '{count} نتيجة بعد البحث',
      visibleCountLabel: '{count} طلب ظاهر',
      sortHintLabel: 'الترتيب: {label}',
      workflowAssignedSummary: 'بانتظار القبول: {acceptance} • بانتظار اعتماد العميل: {client}',
      workflowCompetitiveSummary: 'طلبات متاحة للتسعير المباشر',
      workflowUrgentSummary: 'طلبات عاجلة تحتاج استجابة سريعة',
      activeBadgeAssigned: 'مباشر',
      activeBadgeCompetitive: 'تنافسي',
      activeBadgeUrgent: 'عاجل',
      loadUnavailable: 'تعذّر تحميل الطلبات بسبب عدم جاهزية الاتصال.',
      loadFailed: 'تعذّر تحميل الطلبات. حاول مرة أخرى.',
      unexpectedLoad: 'حدث خطأ غير متوقع أثناء تحميل الطلبات.',
      emptySearch: 'لا توجد نتائج مطابقة',
      emptyCompetitive: 'لا توجد طلبات عروض أسعار متاحة',
      emptyUrgent: 'لا توجد طلبات عاجلة متاحة',
      emptyDefault: 'لا توجد طلبات',
      emptySearchHint: 'جرّب كلمات بحث مختلفة أو امسح البحث لعرض كل الطلبات.',
      emptyAssignedHint: 'غيّر تبويب الحالة أو راجع الطلبات الأخرى في التبويبات العلوية.',
      emptyOtherHint: 'يمكنك الضغط على زر تحديث البيانات لعرض أحدث الطلبات.',
      cardAvailable: 'متاح',
      cardUntitled: 'طلب بدون عنوان',
      cardOpen: 'عرض التفاصيل',
      cardClientLabel: 'العميل',
      cardCityLabel: 'المدينة',
      cardValueLabel: 'القيمة',
      cardClientPrefix: 'العميل ',
      cardQuoteDeadlineLabel: 'آخر موعد',
      cardDeliveryLabel: 'التسليم',
      metaUrgent: 'أولوية عالية',
      metaCompetitive: 'متاح للتسعير',
      statusPending: 'قيد المراجعة',
      statusNew: 'جديد',
      statusSubmitted: 'جديد',
      statusAccepted: 'تم قبول الطلب',
      statusAwaitingClient: 'بانتظار اعتماد العميل',
      statusInProgress: 'تحت التنفيذ',
      statusAcceptedShort: 'مقبول',
      statusCompleted: 'مكتمل',
      statusCancelled: 'ملغي',
      statusRejected: 'مرفوض',
      statusExpired: 'منتهي',
      typeNormal: 'عادي',
      typeCompetitive: 'تنافسي',
      typeUrgent: 'عاجل',
      currency: 'ر.س',
    },
    en: {
      pageTitle: 'Nawafeth — Orders Management',
      authGateTitle: 'Sign in required',
      authGateDescription: 'Sign in first to access the orders management board and track assigned orders, competitive opportunities, and urgent requests from one place.',
      authGateButton: 'Sign in',
      heroAria: 'Orders management interface',
      resultsAria: 'Orders results',
      backAria: 'Back to provider dashboard',
      heroPanelKicker: 'Operations center',
      heroPanelTitle: 'A calmer, clearer board',
      heroPanelBody: 'A focused view that helps you spot important orders quickly without clutter or visual noise.',
      heroPanelItem1: 'Quick movement between assigned, competitive, and urgent requests.',
      heroPanelItem2: 'A clear summary of status, city, value, and delivery timing.',
      heroPanelItem3: 'A more balanced interface on mobile and desktop.',
      heroKicker: 'Your orders operations hub',
      heroTitle: 'Orders management',
      heroSubtitle: 'One interface to follow your assigned requests, capture competitive opportunities, and respond quickly to urgent orders with a cleaner layout across mobile and desktop.',
      heroPill1: 'Live follow-up',
      heroPill2: 'Fast search and sort',
      heroPill3: 'Professional multi-state view',
      kpiAssignedLabel: 'Assigned',
      kpiAssignedNote: 'Active requests in the workflow',
      kpiCompetitiveLabel: 'Competitive',
      kpiCompetitiveNote: 'Pricing opportunities available',
      kpiUrgentLabel: 'Urgent',
      kpiUrgentNote: 'Needs a faster response',
      tabAssignedLabel: 'Assigned to me',
      tabAssignedNote: 'Execution and follow-up',
      tabCompetitiveLabel: 'Price offers',
      tabCompetitiveNote: 'Competitive opportunities',
      tabUrgentLabel: 'Urgent requests',
      tabUrgentNote: 'Immediate response',
      sortLabel: 'Sort',
      sortNewest: 'Newest',
      sortOldest: 'Oldest',
      sortStatus: 'By status',
      sortCity: 'By city',
      sortAmount: 'Highest value',
      sortDeadline: 'Nearest deadline',
      refresh: 'Refresh data',
      refreshing: 'Refreshing...',
      clearSearch: 'Clear search',
      controlsKicker: 'Control panel',
      controlsTitle: 'Filter and follow-up',
      searchLabel: 'Smart search',
      assignedSearchPlaceholder: 'Search by order number, title, client, or city',
      competitiveSearchPlaceholder: 'Search available price offers by order number, title, or city',
      urgentSearchPlaceholder: 'Search urgent orders by order number, title, or city',
      statusFilterLabel: 'Status filter',
      statusAll: 'All',
      statusGroupNew: 'New',
      statusGroupInProgress: 'In progress',
      statusGroupCompleted: 'Completed',
      statusGroupCancelled: 'Cancelled',
      legend1: 'A new request waiting for review or acceptance',
      legend2: 'A request in execution or follow-up',
      legend3: 'A request completed and closed',
      legend4: 'A cancelled or ended request',
      sideNoteTitle: 'A cleaner operating rhythm',
      sideNoteBody: 'Use the top tabs to switch request types, then narrow results by status and search from here quickly.',
      loading: 'Loading orders...',
      resultsChipAssigned: 'Operational view for assigned requests',
      resultsChipCompetitive: 'Ready-to-price opportunities for review',
      resultsChipUrgent: 'Urgent requests worth prioritizing',
      activeAssignedLabel: 'Assigned requests',
      activeCompetitiveLabel: 'Available price offers',
      activeUrgentLabel: 'Available urgent requests',
      groupAllLabel: 'All statuses',
      groupNewLabel: 'New',
      groupInProgressLabel: 'In progress',
      groupCompletedLabel: 'Completed',
      groupCancelledLabel: 'Cancelled',
      searchCountLabel: '{count} search results',
      visibleCountLabel: '{count} visible requests',
      sortHintLabel: 'Sort: {label}',
      workflowAssignedSummary: 'Awaiting acceptance: {acceptance} • Awaiting client approval: {client}',
      workflowCompetitiveSummary: 'Requests available for direct pricing',
      workflowUrgentSummary: 'Urgent requests need a faster response',
      activeBadgeAssigned: 'Direct',
      activeBadgeCompetitive: 'Competitive',
      activeBadgeUrgent: 'Urgent',
      loadUnavailable: 'Unable to load orders because the connection layer is not ready.',
      loadFailed: 'Unable to load orders. Please try again.',
      unexpectedLoad: 'An unexpected error occurred while loading orders.',
      emptySearch: 'No matching results',
      emptyCompetitive: 'No available price-offer requests',
      emptyUrgent: 'No available urgent requests',
      emptyDefault: 'No orders found',
      emptySearchHint: 'Try different keywords or clear the search to show all requests.',
      emptyAssignedHint: 'Change the status tab or review the other request tabs above.',
      emptyOtherHint: 'You can press refresh data to load the latest requests.',
      cardAvailable: 'Available',
      cardUntitled: 'Untitled request',
      cardOpen: 'Open details',
      cardClientLabel: 'Client',
      cardCityLabel: 'City',
      cardValueLabel: 'Value',
      cardClientPrefix: 'Client ',
      cardQuoteDeadlineLabel: 'Deadline',
      cardDeliveryLabel: 'Delivery',
      metaUrgent: 'High priority',
      metaCompetitive: 'Available for pricing',
      statusPending: 'Under review',
      statusNew: 'New',
      statusSubmitted: 'New',
      statusAccepted: 'Accepted',
      statusAwaitingClient: 'Awaiting client approval',
      statusInProgress: 'In progress',
      statusAcceptedShort: 'Accepted',
      statusCompleted: 'Completed',
      statusCancelled: 'Cancelled',
      statusRejected: 'Rejected',
      statusExpired: 'Expired',
      typeNormal: 'Standard',
      typeCompetitive: 'Competitive',
      typeUrgent: 'Urgent',
      currency: 'SAR',
    },
  };
  const SORT_COPY_KEYS = {
    newest: 'sortNewest',
    oldest: 'sortOldest',
    status: 'sortStatus',
    city: 'sortCity',
    amount_desc: 'sortAmount',
    deadline: 'sortDeadline',
  };
  const SORT_OPTIONS = Object.keys(SORT_COPY_KEYS);
  const STORAGE_KEY = 'nawafeth.providerOrders.ui.v2';

  const state = {
    assignedOrders: [],
    competitiveOrders: [],
    urgentOrders: [],
    activeTab: 'assigned',
    selectedStatusGroup: '',
    searchText: '',
    sortBy: 'newest',
    isFetching: false,
    initialized: false,
  };

  function init() {
    if (state.initialized) return;
    state.initialized = true;

    _applyStaticCopy();
    document.addEventListener('nawafeth:languagechange', _handleLanguageChange);

    const authGate = byId('auth-gate');
    const content = byId('porders-content');

    if (!authGate || !content) {
      console.error('[ProviderOrdersPage] Missing required page elements');
      return;
    }

    const pageAuthenticated = content.dataset.authenticated === '1';
    const jsAuthenticated =
      window.Auth &&
      typeof Auth.isLoggedIn === 'function' &&
      Auth.isLoggedIn();

    if (!pageAuthenticated && !jsAuthenticated) {
      authGate.style.display = 'grid';
      content.style.display = 'none';
      return;
    }

    _loadPersistedState();

    authGate.style.display = 'none';
    content.style.display = 'flex';

    _applyInitialTabFromUrl();
    _bindMainTabs();
    _bindStatusTabs();
    _bindSearch();
    _bindSortControl();
    _bindUtilityButtons();
    _applyStateToControls();
    _syncTabUI();
    _fetchOrders();
  }

  function _loadPersistedState() {
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY);
      if (!raw) return;

      const saved = JSON.parse(raw);
      if (!saved || typeof saved !== 'object') return;

      const tab = String(saved.activeTab || '').trim().toLowerCase();
      if (['assigned', 'competitive', 'urgent'].includes(tab)) {
        state.activeTab = tab;
      }

      const group = String(saved.selectedStatusGroup || '').trim();
      if (['', 'new', 'in_progress', 'completed', 'cancelled'].includes(group)) {
        state.selectedStatusGroup = group;
      }

      state.searchText = String(saved.searchText || '').trim().toLowerCase();

      const sortBy = String(saved.sortBy || '').trim();
      if (SORT_OPTIONS.includes(sortBy)) {
        state.sortBy = sortBy;
      }
    } catch (_) {
      // تجاهل أخطاء التخزين المحلي
    }
  }

  function _persistState() {
    try {
      window.localStorage.setItem(
        STORAGE_KEY,
        JSON.stringify({
          activeTab: state.activeTab,
          selectedStatusGroup: state.selectedStatusGroup,
          searchText: state.searchText,
          sortBy: state.sortBy,
        }),
      );
    } catch (_) {
      // تجاهل أخطاء الكتابة في التخزين المحلي
    }
  }

  function _applyInitialTabFromUrl() {
    try {
      const tab = String(new URLSearchParams(window.location.search).get('tab') || '')
        .trim()
        .toLowerCase();

      if (['assigned', 'competitive', 'urgent'].includes(tab)) {
        state.activeTab = tab;
      }
    } catch (_) {
      // تجاهل أخطاء الرابط
    }
  }

  function _bindMainTabs() {
    const tabs = byId('po-request-tabs');
    if (!tabs) return;

    tabs.addEventListener('click', (event) => {
      const btn = event.target.closest('.status-tab');
      if (!btn) return;

      const tab = String(btn.dataset.tab || '').trim();

      if (!['assigned', 'competitive', 'urgent'].includes(tab)) return;
      if (state.activeTab === tab) return;

      state.activeTab = tab;

      if (state.activeTab !== 'assigned') {
        state.selectedStatusGroup = '';
        _markStatusFilter('');
      }

      _persistState();
      _syncTabUI();
      _render();
    });
  }

  function _bindStatusTabs() {
    const tabs = byId('po-status-tabs');
    if (!tabs) return;

    tabs.addEventListener('click', (event) => {
      const btn = event.target.closest('.status-tab');
      if (!btn || state.activeTab !== 'assigned') return;

      const group = String(btn.dataset.group || '').trim();

      if (!['', 'new', 'in_progress', 'completed', 'cancelled'].includes(group)) return;
      if (state.selectedStatusGroup === group) return;

      state.selectedStatusGroup = group;

      _persistState();
      _markStatusFilter(group);
      _render();
    });
  }

  function _bindSearch() {
    const input = byId('po-search');
    if (!input) return;

    let timer = null;

    input.addEventListener('input', (event) => {
      clearTimeout(timer);

      timer = setTimeout(() => {
        state.searchText = String(event.target.value || '').trim().toLowerCase();
        _updateClearSearchState();
        _persistState();
        _render();
      }, 220);
    });
  }

  function _bindSortControl() {
    const select = byId('po-sort-select');
    if (!select) return;

    select.addEventListener('change', (event) => {
      const next = String(event.target.value || '').trim();
      if (!SORT_OPTIONS.includes(next)) return;

      state.sortBy = next;

      _persistState();
      _render();
    });
  }

  function _bindUtilityButtons() {
    const refreshBtn = byId('po-refresh-btn');
    if (refreshBtn) {
      refreshBtn.addEventListener('click', () => {
        if (state.isFetching) return;
        _fetchOrders();
      });
    }

    const clearBtn = byId('po-clear-search-btn');
    if (clearBtn) {
      clearBtn.addEventListener('click', () => {
        const input = byId('po-search');

        if (input) input.value = '';

        state.searchText = '';

        _persistState();
        _updateClearSearchState();
        _render();
      });
    }

    _updateClearSearchState();
  }

  function _syncTabUI() {
    const content = byId('porders-content');
    if (content) {
      content.dataset.view = state.activeTab;
    }

    qsa('#po-request-tabs .status-tab').forEach((btn) => {
      btn.classList.toggle('active', btn.dataset.tab === state.activeTab);
    });

    const statusTabs = byId('po-status-tabs');
    if (statusTabs) {
      statusTabs.style.display = state.activeTab === 'assigned' ? '' : 'none';
    }

    const legend = byId('po-status-legend');
    if (legend) {
      legend.style.display = state.activeTab === 'assigned' ? '' : 'none';
    }

    _updateSearchPlaceholder();
    _markStatusFilter(state.selectedStatusGroup);
    _updateContextSummary();
    _updateSmartBar(_filteredOrders().length);
  }

  function _applyStateToControls() {
    const searchInput = byId('po-search');
    if (searchInput) {
      searchInput.value = state.searchText;
    }

    const sortSelect = byId('po-sort-select');
    if (sortSelect && Object.prototype.hasOwnProperty.call(SORT_LABELS, state.sortBy)) {
      sortSelect.value = state.sortBy;
    }

    _updateClearSearchState();
  }

  function _markStatusFilter(group) {
    qsa('#po-status-tabs .status-tab').forEach((btn) => {
      btn.classList.toggle('active', String(btn.dataset.group || '') === group);
    });
  }

  async function _fetchOrders() {
    if (!window.ApiClient || typeof ApiClient.get !== 'function') {
      _setLoading(false);
      _setError(_copy('loadUnavailable'));
      return;
    }

    state.isFetching = true;
    _syncRefreshButtonState();
    _setLoading(true);
    _setError('');

    try {
      const [assignedRes, competitiveRes, urgentRes] = await Promise.allSettled([
        ApiClient.get('/api/marketplace/provider/requests/'),
        ApiClient.get('/api/marketplace/provider/competitive/available/'),
        ApiClient.get('/api/marketplace/provider/urgent/available/'),
      ]);

      const assignedOk =
        assignedRes.status === 'fulfilled' &&
        assignedRes.value &&
        assignedRes.value.ok;

      const competitiveOk =
        competitiveRes.status === 'fulfilled' &&
        competitiveRes.value &&
        competitiveRes.value.ok;

      const urgentOk =
        urgentRes.status === 'fulfilled' &&
        urgentRes.value &&
        urgentRes.value.ok;

      if (assignedOk) {
        state.assignedOrders = _extractList(assignedRes.value.data);
      }

      if (competitiveOk) {
        state.competitiveOrders = _extractList(competitiveRes.value.data);
      }

      if (urgentOk) {
        state.urgentOrders = _extractList(urgentRes.value.data);
      }

      if (!assignedOk && !competitiveOk && !urgentOk) {
        _setError(_copy('loadFailed'));
      }

      _updateCounts();
      _render();
    } catch (error) {
      console.error('[ProviderOrdersPage] Fetch failed:', error);
      _setError(_copy('unexpectedLoad'));
      _render();
    } finally {
      state.isFetching = false;
      _syncRefreshButtonState();
      _setLoading(false);
    }
  }

  function _updateCounts() {
    const assigned = String(state.assignedOrders.length);
    const competitive = String(state.competitiveOrders.length);
    const urgent = String(state.urgentOrders.length);

    setText('po-count-assigned', assigned);
    setText('po-count-competitive', competitive);
    setText('po-count-urgent', urgent);

    setText('po-kpi-assigned', assigned);
    setText('po-kpi-competitive', competitive);
    setText('po-kpi-urgent', urgent);

    _updateContextSummary();
  }

  function _assignedWorkflowCounts() {
    const counts = {
      awaiting_acceptance: 0,
      awaiting_client: 0,
    };

    state.assignedOrders.forEach((order) => {
      const stage = String((order && order.status) || '').toLowerCase();
      const type = String((order && order.request_type) || '').toLowerCase();

      if (type === 'normal' && stage === 'new') {
        counts.awaiting_acceptance += 1;
      }

      if (stage === 'awaiting_client') {
        counts.awaiting_client += 1;
      }
    });

    return counts;
  }

  function _extractList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    if (payload && Array.isArray(payload.data)) return payload.data;
    return [];
  }

  function _currentOrders() {
    if (state.activeTab === 'competitive') return state.competitiveOrders;
    if (state.activeTab === 'urgent') return state.urgentOrders;

    if (!state.selectedStatusGroup) return state.assignedOrders;

    return state.assignedOrders.filter((order) => {
      return _statusGroup(order) === state.selectedStatusGroup;
    });
  }

  function _orderCityText(order) {
    if (window.UI && typeof UI.formatCityDisplay === 'function') {
      return UI.formatCityDisplay(
        order && (order.city_display || order.city),
        order && (order.region || order.region_name),
      );
    }

    const city = String((order && (order.city_display || order.city)) || '').trim();
    const region = String((order && (order.region || order.region_name)) || '').trim();

    if (city && region) return city + ' - ' + region;
    return city || region || '';
  }

  function _filteredOrders() {
    const list = _currentOrders();

    const filtered = !state.searchText
      ? list.slice()
      : list.filter((order) => {
          const id = String(order.display_id || order.id || '').toLowerCase();
          const title = String(order.title || '').toLowerCase();
          const client = String(order.client_name || '').toLowerCase();
          const city = (_orderCityText(order) + ' ' + String(order.city || '')).toLowerCase();

          return (
            id.includes(state.searchText) ||
            title.includes(state.searchText) ||
            client.includes(state.searchText) ||
            city.includes(state.searchText)
          );
        });

    return _sortOrders(filtered);
  }

  function _sortOrders(list) {
    const rows = Array.isArray(list) ? list.slice() : [];

    const rankByStatus = {
      new: 0,
      in_progress: 1,
      completed: 2,
      cancelled: 3,
    };

    rows.sort((a, b) => {
      const ta = _timestamp(a && a.created_at);
      const tb = _timestamp(b && b.created_at);

      if (state.sortBy === 'oldest') return ta - tb;

      if (state.sortBy === 'status') {
        const ra = rankByStatus[_statusGroup(a)] ?? 99;
        const rb = rankByStatus[_statusGroup(b)] ?? 99;

        if (ra !== rb) return ra - rb;
        return tb - ta;
      }

      if (state.sortBy === 'city') {
        const ca = _orderCityText(a);
        const cb = _orderCityText(b);
        const cityResult = ca.localeCompare(cb, 'ar');

        if (cityResult !== 0) return cityResult;
        return tb - ta;
      }

      if (state.sortBy === 'amount_desc') {
        const aa = _amountValue(a);
        const ab = _amountValue(b);

        if (ab !== aa) return ab - aa;
        return tb - ta;
      }

      if (state.sortBy === 'deadline') {
        const da = _deadlineValue(a);
        const db = _deadlineValue(b);

        if (da !== db) return da - db;
        return tb - ta;
      }

      return tb - ta;
    });

    return rows;
  }

  function _render() {
    const list = _filteredOrders();
    const container = byId('po-list');
    const empty = byId('po-empty');

    if (!container || !empty) return;

    container.innerHTML = '';
    container.classList.toggle('is-single', list.length === 1);

    _syncTabUI();
    _updateSmartBar(list.length);

    if (!list.length) {
      empty.style.display = '';

      const text = empty.querySelector('p');
      const hint = empty.querySelector('small');

      if (text) {
        if (state.searchText) {
          text.textContent = _copy('emptySearch');
        } else if (state.activeTab === 'competitive') {
          text.textContent = _copy('emptyCompetitive');
        } else if (state.activeTab === 'urgent') {
          text.textContent = _copy('emptyUrgent');
        } else {
          text.textContent = _copy('emptyDefault');
        }
      }

      if (hint) {
        if (state.searchText) {
          hint.textContent = _copy('emptySearchHint');
        } else if (state.activeTab === 'assigned') {
          hint.textContent = _copy('emptyAssignedHint');
        } else {
          hint.textContent = _copy('emptyOtherHint');
        }
      }

      return;
    }

    empty.style.display = 'none';

    const frag = document.createDocumentFragment();

    list.forEach((order, index) => {
      frag.appendChild(_buildCard(order, index));
    });

    container.appendChild(frag);
  }

  function _buildCard(order, index) {
    const safeOrder = order || {};
    const statusGroup = _statusGroup(safeOrder);
    const type = String(safeOrder.request_type || '').toLowerCase();
    const safeId = String(safeOrder.id || '').trim();

    const card = _el('a', {
      className: 'order-card po-card po-card-' + statusGroup,
      href: safeId ? '/provider-orders/' + encodeURIComponent(safeId) + '/' : '#',
    });

    card.style.setProperty('--po-card-delay', String(Math.min(index || 0, 10) * 28) + 'ms');

    const top = _el('div', { className: 'order-card-top po-card-top' });
    const start = _el('div', { className: 'po-card-head' });

    start.appendChild(
      _el('span', {
        className: 'order-id',
        textContent: String(safeOrder.display_id || safeOrder.id || '-'),
      }),
    );

    if (type && type !== 'normal') {
      start.appendChild(
        _el('span', {
          className: 'order-type-badge order-type-badge-' + type,
          textContent: _typeLabel(type),
        }),
      );
    }

    if (state.activeTab !== 'assigned' && !safeOrder.provider) {
      start.appendChild(
        _el('span', {
          className: 'po-available-badge',
          textContent: _copy('cardAvailable'),
        }),
      );
    }

    const status = _el('span', {
      className: 'order-status',
      textContent: _statusLabel(safeOrder),
    });

    status.style.color = _statusColor(safeOrder);
    status.style.borderColor = _statusColor(safeOrder);
    status.style.backgroundColor = _statusBg(safeOrder);

    top.appendChild(start);
    top.appendChild(status);

    const body = _el('div', { className: 'order-card-body' });

    body.appendChild(
      _el('h4', {
        textContent: String(safeOrder.title || _copy('cardUntitled')),
      }),
    );

    const meta = _metaLine(safeOrder);
    if (meta) {
      body.appendChild(
        _el('p', {
          className: 'order-meta',
          textContent: meta,
        }),
      );
    }

    const cityText = _orderCityText(safeOrder);
    if (cityText) {
      body.appendChild(
        _el('p', {
          className: 'order-date',
          textContent: cityText,
        }),
      );
    }

    const pills = _el('div', { className: 'po-card-pills' });

    if (safeOrder.category_name) {
      pills.appendChild(
        _el('span', {
          className: 'po-card-pill',
          textContent: String(safeOrder.category_name),
        }),
      );
    }

    if (safeOrder.subcategory_name) {
      pills.appendChild(
        _el('span', {
          className: 'po-card-pill po-card-pill-soft',
          textContent: String(safeOrder.subcategory_name),
        }),
      );
    }

    if (pills.childElementCount) {
      body.appendChild(pills);
    }

    const infoGrid = _el('div', { className: 'po-card-grid' });

    _appendInfoCell(infoGrid, _copy('cardClientLabel'), _cardClient(safeOrder));
    _appendInfoCell(infoGrid, _copy('cardCityLabel'), cityText);
    _appendInfoCell(infoGrid, _cardDateLabel(safeOrder), _cardDateValue(safeOrder));
    _appendInfoCell(infoGrid, _copy('cardValueLabel'), _cardAmount(safeOrder));

    if (infoGrid.childElementCount) {
      body.appendChild(infoGrid);
    }

    const footer = _el('div', { className: 'po-card-footer' });

    footer.appendChild(
      _el('span', {
        className: 'po-card-date',
        textContent: _formatDate(safeOrder.created_at),
      }),
    );

    footer.appendChild(
      _el('span', {
        className: 'po-card-link',
        textContent: _copy('cardOpen'),
      }),
    );

    body.appendChild(footer);

    card.appendChild(top);
    card.appendChild(body);

    return card;
  }

  function _metaLine(order) {
    const parts = [];

    if (order.category_name && !order.subcategory_name) {
      parts.push(String(order.category_name));
    }

    if (state.activeTab === 'urgent') {
      parts.push(_copy('metaUrgent'));
    } else if (state.activeTab === 'competitive') {
      parts.push(_copy('metaCompetitive'));
    }

    return parts.join(' • ');
  }

  function _activeTabLabel() {
    if (state.activeTab === 'competitive') return _copy('activeCompetitiveLabel');
    if (state.activeTab === 'urgent') return _copy('activeUrgentLabel');
    return _copy('activeAssignedLabel');
  }

  function _statusGroupLabel() {
    const map = {
      '': _copy('groupAllLabel'),
      new: _copy('groupNewLabel'),
      in_progress: _copy('groupInProgressLabel'),
      completed: _copy('groupCompletedLabel'),
      cancelled: _copy('groupCancelledLabel'),
    };

    return map[String(state.selectedStatusGroup || '')] || 'كل الحالات';
  }

  function _updateSearchPlaceholder() {
    const input = byId('po-search');
    if (!input) return;

    if (state.activeTab === 'competitive') {
      input.placeholder = _copy('competitiveSearchPlaceholder');
      return;
    }

    if (state.activeTab === 'urgent') {
      input.placeholder = _copy('urgentSearchPlaceholder');
      return;
    }

    input.placeholder = _copy('assignedSearchPlaceholder');
  }

  function _updateSmartBar(visibleCount) {
    const title = byId('po-active-view-label');
    const count = byId('po-visible-count-label');
    const sortHint = byId('po-sort-hint-label');
    const chip = byId('po-results-chip');

    if (title) {
      title.textContent =
        state.activeTab === 'assigned'
          ? _activeTabLabel() + ' • ' + _statusGroupLabel()
          : _activeTabLabel();
    }

    if (count) {
      const totalLabel = Number(visibleCount || 0).toLocaleString(_numberLocale());
      count.textContent = state.searchText
        ? _copy('searchCountLabel', { count: totalLabel })
        : _copy('visibleCountLabel', { count: totalLabel });
    }

    if (sortHint) {
      sortHint.textContent = _copy('sortHintLabel', { label: _sortLabel(state.sortBy) });
    }

    if (chip) {
      chip.textContent =
        state.activeTab === 'assigned'
          ? _copy('resultsChipAssigned')
          : state.activeTab === 'competitive'
            ? _copy('resultsChipCompetitive')
            : _copy('resultsChipUrgent');
    }
  }

  function _updateContextSummary() {
    const workflow = _assignedWorkflowCounts();
    const summary = byId('po-workflow-count-label');
    const badge = byId('po-active-tab-badge');

    if (summary) {
      if (state.activeTab === 'competitive') {
        summary.textContent = _copy('workflowCompetitiveSummary');
      } else if (state.activeTab === 'urgent') {
        summary.textContent = _copy('workflowUrgentSummary');
      } else {
        summary.textContent = _copy('workflowAssignedSummary', {
          acceptance: String(workflow.awaiting_acceptance),
          client: String(workflow.awaiting_client),
        });
      }
    }

    if (badge) {
      badge.textContent =
        {
          assigned: _copy('activeBadgeAssigned'),
          competitive: _copy('activeBadgeCompetitive'),
          urgent: _copy('activeBadgeUrgent'),
        }[state.activeTab] || _copy('activeBadgeAssigned');
    }
  }

  function _updateClearSearchState() {
    const btn = byId('po-clear-search-btn');
    if (!btn) return;

    const hasSearch = Boolean(state.searchText);

    btn.disabled = !hasSearch;
    btn.classList.toggle('is-disabled', !hasSearch);
    btn.setAttribute('aria-disabled', hasSearch ? 'false' : 'true');
  }

  function _syncRefreshButtonState() {
    const btn = byId('po-refresh-btn');
    if (!btn) return;

    btn.disabled = state.isFetching;
    btn.textContent = state.isFetching ? _copy('refreshing') : _copy('refresh');
    btn.setAttribute('aria-busy', state.isFetching ? 'true' : 'false');
  }

  function _statusGroup(order) {
    const explicit = String((order && order.status_group) || '').toLowerCase();

    if (['new', 'in_progress', 'completed', 'cancelled'].includes(explicit)) {
      return explicit;
    }

    const status = String((order && order.status) || '').toLowerCase();

    if (['pending', 'new', 'submitted', 'provider_accepted', 'awaiting_client'].includes(status)) {
      return 'new';
    }

    if (['in_progress', 'accepted', 'started'].includes(status)) {
      return 'in_progress';
    }

    if (['completed', 'done', 'finished'].includes(status)) {
      return 'completed';
    }

    if (['cancelled', 'rejected', 'expired', 'canceled'].includes(status)) {
      return 'cancelled';
    }

    return 'new';
  }

  function _statusLabel(order) {
    const label = String((order && order.status_label) || '').trim();
    if (label && _currentLang() !== 'en') return label;

    const status = String((order && order.status) || '').toLowerCase();

    const statusMap = {
      pending: _copy('statusPending'),
      new: _copy('statusNew'),
      submitted: _copy('statusSubmitted'),
      provider_accepted: _copy('statusAccepted'),
      awaiting_client: _copy('statusAwaitingClient'),
      in_progress: _copy('statusInProgress'),
      accepted: _copy('statusAcceptedShort'),
      started: _copy('statusInProgress'),
      completed: _copy('statusCompleted'),
      done: _copy('statusCompleted'),
      finished: _copy('statusCompleted'),
      cancelled: _copy('statusCancelled'),
      canceled: _copy('statusCancelled'),
      rejected: _copy('statusRejected'),
      expired: _copy('statusExpired'),
    };

    return statusMap[status] || statusMap[_statusGroup(order)] || _copy('statusNew');
  }

  function _statusColor(order) {
    const group = _statusGroup(order);

    if (group === 'completed') return '#2E7D32';
    if (group === 'cancelled') return '#C62828';
    if (group === 'in_progress') return '#E67E22';

    return '#A56800';
  }

  function _statusBg(order) {
    const group = _statusGroup(order);

    if (group === 'completed') return 'rgba(46, 125, 50, 0.11)';
    if (group === 'cancelled') return 'rgba(198, 40, 40, 0.11)';
    if (group === 'in_progress') return 'rgba(230, 126, 34, 0.11)';

    return 'rgba(165, 104, 0, 0.11)';
  }

  function _typeLabel(type) {
    return {
      normal: _copy('typeNormal'),
      competitive: _copy('typeCompetitive'),
      urgent: _copy('typeUrgent'),
    }[type] || type || '';
  }

  function _cardClient(order) {
    const client = String((order && order.client_name) || '').trim();

    if (!client) return '';
    if (state.activeTab === 'assigned') return client;

    return _copy('cardClientPrefix') + client;
  }

  function _cardDateLabel(order) {
    return order && order.quote_deadline ? _copy('cardQuoteDeadlineLabel') : _copy('cardDeliveryLabel');
  }

  function _cardDateValue(order) {
    if (order && order.quote_deadline) return _formatDateOnly(order.quote_deadline);
    if (order && order.expected_delivery_at) return _formatDateOnly(order.expected_delivery_at);

    return '';
  }

  function _cardAmount(order) {
    const amount = _amountValue(order);

    if (!Number.isFinite(amount) || amount < 0) return '';

    return _formatMoney(amount);
  }

  function _appendInfoCell(container, label, value) {
    const text = String(value || '').trim();
    if (!container || !text) return;

    const cell = _el('div', { className: 'po-card-meta' });

    cell.appendChild(
      _el('span', {
        className: 'po-card-meta-label',
        textContent: label,
      }),
    );

    cell.appendChild(
      _el('strong', {
        className: 'po-card-meta-value',
        textContent: text,
      }),
    );

    container.appendChild(cell);
  }

  function _formatDate(value) {
    const dt = value ? new Date(value) : null;

    if (!dt || Number.isNaN(dt.getTime())) return '';

    return dt.toLocaleString(_dateLocale(), {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
    });
  }

  function _formatDateOnly(value) {
    const dt = value ? new Date(value) : null;

    if (!dt || Number.isNaN(dt.getTime())) return '';

    return dt.toLocaleDateString(_dateLocale(), {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });
  }

  function _formatMoney(value) {
    const num = Number(value);

    if (!Number.isFinite(num)) return String(value || '-');

    return num.toLocaleString(_numberLocale()) + ' ' + _copy('currency');
  }

  function _amountValue(order) {
    const candidates = [
      order && order.estimated_service_amount,
      order && order.actual_service_amount,
      order && order.received_amount,
      order && order.remaining_amount,
      order && order.amount,
      order && order.total_amount,
    ];

    for (let i = 0; i < candidates.length; i += 1) {
      const val = Number(candidates[i]);

      if (Number.isFinite(val)) return val;
    }

    return -1;
  }

  function _deadlineValue(order) {
    const candidates = [
      order && order.expected_delivery_at,
      order && order.quote_deadline,
      order && order.delivered_at,
    ];

    for (let i = 0; i < candidates.length; i += 1) {
      const ts = _timestamp(candidates[i]);

      if (Number.isFinite(ts) && ts > 0) return ts;
    }

    return Number.POSITIVE_INFINITY;
  }

  function _timestamp(value) {
    const dt = value ? new Date(value) : null;

    if (!dt || Number.isNaN(dt.getTime())) return 0;

    return dt.getTime();
  }

  function _setLoading(loading) {
    const el = byId('po-loading');
    if (el) el.style.display = loading ? '' : 'none';

    const list = byId('po-list');
    if (list) list.classList.toggle('is-loading', Boolean(loading));
  }

  function _setError(message) {
    const el = byId('po-error');
    if (!el) return;

    if (!message) {
      el.textContent = '';
      el.classList.add('hidden');
      return;
    }

    el.textContent = message;
    el.classList.remove('hidden');
  }

  function _el(tag, options) {
    if (window.UI && typeof UI.el === 'function') {
      return UI.el(tag, options || {});
    }

    const node = document.createElement(tag);
    const opts = options || {};

    if (opts.className) node.className = opts.className;
    if (opts.textContent !== undefined) node.textContent = opts.textContent;
    if (opts.href) node.setAttribute('href', opts.href);

    return node;
  }

  function byId(id) {
    return document.getElementById(id);
  }

  function qsa(selector) {
    return Array.from(document.querySelectorAll(selector));
  }

  function setText(id, value) {
    const el = byId(id);

    if (el) el.textContent = value;
  }

  function _currentLang() {
    if (window.NawafethI18n && typeof window.NawafethI18n.getLanguage === 'function') {
      return window.NawafethI18n.getLanguage() === 'en' ? 'en' : 'ar';
    }

    return document.documentElement.lang === 'en' ? 'en' : 'ar';
  }

  function _copy(key, replacements) {
    const lang = _currentLang();
    let text = (COPY[lang] && COPY[lang][key]) || COPY.ar[key] || '';

    if (!replacements || typeof replacements !== 'object') return text;

    return text.replace(/\{(\w+)\}/g, (_, token) => {
      return Object.prototype.hasOwnProperty.call(replacements, token)
        ? String(replacements[token])
        : '';
    });
  }

  function _sortLabel(sortKey) {
    return _copy(SORT_COPY_KEYS[sortKey] || SORT_COPY_KEYS.newest);
  }

  function _dateLocale() {
    return _currentLang() === 'en' ? 'en-GB' : 'ar-SA';
  }

  function _numberLocale() {
    return _currentLang() === 'en' ? 'en-US' : 'ar-SA';
  }

  function _applyStaticCopy() {
    document.title = _copy('pageTitle');

    const authGate = byId('auth-gate');
    const hero = byId('po-hero');
    const resultsBoard = byId('po-results-board');
    const backBtn = byId('po-back-btn');
    const searchInput = byId('po-search');
    const clearBtn = byId('po-clear-search-btn');

    if (authGate) authGate.setAttribute('aria-label', _copy('authGateTitle'));
    if (hero) hero.setAttribute('aria-label', _copy('heroAria'));
    if (resultsBoard) resultsBoard.setAttribute('aria-label', _copy('resultsAria'));
    if (backBtn) backBtn.setAttribute('aria-label', _copy('backAria'));
    if (clearBtn) clearBtn.setAttribute('aria-label', _copy('clearSearch'));

    setText('po-hero-panel-kicker', _copy('heroPanelKicker'));
    setText('po-hero-panel-title', _copy('heroPanelTitle'));
    setText('po-hero-panel-body', _copy('heroPanelBody'));
    setText('po-hero-panel-item-1', _copy('heroPanelItem1'));
    setText('po-hero-panel-item-2', _copy('heroPanelItem2'));
    setText('po-hero-panel-item-3', _copy('heroPanelItem3'));
    setText('po-hero-kicker', _copy('heroKicker'));
    setText('po-hero-title', _copy('heroTitle'));
    setText('po-hero-subtitle', _copy('heroSubtitle'));
    setText('po-hero-pill-1', _copy('heroPill1'));
    setText('po-hero-pill-2', _copy('heroPill2'));
    setText('po-hero-pill-3', _copy('heroPill3'));
    setText('po-kpi-label-assigned', _copy('kpiAssignedLabel'));
    setText('po-kpi-note-assigned', _copy('kpiAssignedNote'));
    setText('po-kpi-label-competitive', _copy('kpiCompetitiveLabel'));
    setText('po-kpi-note-competitive', _copy('kpiCompetitiveNote'));
    setText('po-kpi-label-urgent', _copy('kpiUrgentLabel'));
    setText('po-kpi-note-urgent', _copy('kpiUrgentNote'));
    setText('po-tab-assigned-label', _copy('tabAssignedLabel'));
    setText('po-tab-assigned-note', _copy('tabAssignedNote'));
    setText('po-tab-competitive-label', _copy('tabCompetitiveLabel'));
    setText('po-tab-competitive-note', _copy('tabCompetitiveNote'));
    setText('po-tab-urgent-label', _copy('tabUrgentLabel'));
    setText('po-tab-urgent-note', _copy('tabUrgentNote'));
    setText('po-sort-label', _copy('sortLabel'));
    setText('po-sort-option-newest', _copy('sortNewest'));
    setText('po-sort-option-oldest', _copy('sortOldest'));
    setText('po-sort-option-status', _copy('sortStatus'));
    setText('po-sort-option-city', _copy('sortCity'));
    setText('po-sort-option-amount', _copy('sortAmount'));
    setText('po-sort-option-deadline', _copy('sortDeadline'));
    setText('po-refresh-btn', state.isFetching ? _copy('refreshing') : _copy('refresh'));
    setText('po-clear-search-btn', _copy('clearSearch'));
    setText('po-controls-kicker', _copy('controlsKicker'));
    setText('po-controls-title', _copy('controlsTitle'));
    setText('po-search-label', _copy('searchLabel'));
    setText('po-status-filter-label', _copy('statusFilterLabel'));
    setText('po-status-all', _copy('statusAll'));
    setText('po-status-new', _copy('statusGroupNew'));
    setText('po-status-in-progress', _copy('statusGroupInProgress'));
    setText('po-status-completed', _copy('statusGroupCompleted'));
    setText('po-status-cancelled', _copy('statusGroupCancelled'));
    setText('po-legend-1', _copy('legend1'));
    setText('po-legend-2', _copy('legend2'));
    setText('po-legend-3', _copy('legend3'));
    setText('po-legend-4', _copy('legend4'));
    setText('po-side-note-title', _copy('sideNoteTitle'));
    setText('po-side-note-body', _copy('sideNoteBody'));
    setText('po-empty-text', _copy('emptyDefault'));
    setText('po-empty-hint', _copy('emptyAssignedHint'));
    setText('po-loading-text', _copy('loading'));
    setText('po-active-view-label', _activeTabLabel());
    setText('po-results-chip', state.activeTab === 'assigned' ? _copy('resultsChipAssigned') : state.activeTab === 'competitive' ? _copy('resultsChipCompetitive') : _copy('resultsChipUrgent'));

    if (searchInput) {
      _updateSearchPlaceholder();
    }

    const authTitle = authGate && authGate.querySelector('.auth-gate-unified-title');
    const authDesc = authGate && authGate.querySelector('.auth-gate-unified-desc');
    const authButton = authGate && authGate.querySelector('.auth-gate-unified-btn');

    if (authTitle) authTitle.textContent = _copy('authGateTitle');
    if (authDesc) authDesc.textContent = _copy('authGateDescription');
    if (authButton) authButton.textContent = _copy('authGateButton');
  }

  function _handleLanguageChange() {
    _applyStaticCopy();
    _updateCounts();
    _render();
  }

  document.addEventListener('DOMContentLoaded', init);

  return {
    init,
    refresh: _fetchOrders,
  };
})();
