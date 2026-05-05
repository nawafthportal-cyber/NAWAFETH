/* Provider order detail page - Flutter parity */
'use strict';

const ProviderOrderDetailPage = (() => {
  const state = {
    initialized: false,
    id: null,
    order: null,
    actionLoading: false,
    chatOpening: false,
    completionFiles: [],
    progressFiles: [],
    toastTimer: null,
    offerAlreadySent: false,
  };
  const COPY = {
    ar: {
      pageTitle: 'تفاصيل الطلب — نوافــذ',
      gateTitle: 'تسجيل الدخول مطلوب',
      gateDescription: 'يرجى تسجيل الدخول للوصول إلى تفاصيل الطلب.',
      login: 'تسجيل الدخول',
      back: 'رجوع',
      detailTitle: 'تفاصيل الطلب',
      detailSubtitle: 'تفاصيل تشغيل الطلب',
      openMessages: 'فتح الرسائل',
      startChat: 'بدء المحادثة مع العميل',
      openingChat: 'جاري فتح المحادثة...',
      requestChip: 'طلب',
      attachmentsLabel: 'المرفقات',
      executionAttachmentsLabel: 'مرفقات التنفيذ',
      statusLabel: 'الحالة',
      descriptionHeading: 'وصف الطلب',
      textLabel: 'النص',
      actionsHeading: 'الإجراءات',
      logsHeading: 'السجل',
      backToOrders: 'العودة للطلبات',
      clientHeading: 'العميل',
      phoneLabel: 'الجوال',
      cityLabel: 'المدينة',
      unavailable: 'غير متوفر',
      invalidUrl: 'رابط غير صحيح',
      loadFailed: 'تعذّر تحميل تفاصيل الطلب',
      requestTypeDefault: 'طلب خدمة',
      typeNormal: 'عادي',
      typeCompetitive: 'تنافسي',
      typeUrgent: 'عاجل',
      statusNew: 'جديد',
      statusAccepted: 'تم قبول الطلب',
      statusAwaitingClient: 'بانتظار اعتماد العميل للتفاصيل',
      statusInProgress: 'تحت التنفيذ',
      statusCompleted: 'مكتمل',
      statusCancelled: 'ملغي',
      fileImage: 'صورة',
      fileVideo: 'فيديو',
      fileAudio: 'صوت',
      fileDocument: 'مستند',
      file: 'ملف',
      attachmentAlt: 'مرفق',
      openFile: 'فتح الملف',
      fileUnavailable: 'غير متاح',
      fromProvider: 'من مزود الخدمة',
      fromClient: 'من العميل',
      noAttachments: 'لا توجد مرفقات.',
      clientAttachments: 'مرفقات العميل',
      providerAttachments: 'مرفقات مزود الخدمة',
      logStatusUpdate: 'تحديث على الحالة: {status}',
      logStatusTransition: 'من {from} إلى {to}',
      byActor: 'بواسطة: {actor}',
      logNoteProviderAcceptedAwaitingDetails: 'قبول من المزود بانتظار إرسال تفاصيل التنفيذ',
      logNoteProviderSentExecutionInputs: 'إرسال/تحديث مدخلات التنفيذ من مزود الخدمة',
      logNoteProviderSentProgressUpdate: 'إرسال تحديث تقدم من مزود الخدمة بانتظار اعتماد العميل',
      logNoteClientApprovedInputs: 'العميل وافق على مدخلات المزود وبدأ التنفيذ',
      logNoteClientApprovedProgress: 'العميل وافق على تحديث التقدم ويمكن متابعة التنفيذ',
      logNoteClientApprovedInputsWithNote: 'العميل وافق على مدخلات المزود: {note}',
      logNoteClientApprovedProgressWithNote: 'العميل وافق على تحديث التقدم: {note}',
      logNoteClientRejectedInputs: 'العميل رفض مدخلات المزود',
      logNoteClientRejectedProgress: 'العميل رفض تحديث التقدم',
      logNoteClientRejectedInputsWithNote: 'العميل رفض مدخلات المزود: {note}',
      logNoteClientRejectedProgressWithNote: 'العميل رفض تحديث التقدم: {note}',
      logNoteStartExecution: 'بدء التنفيذ',
      logNoteStartExecutionAwaitingApproval: 'إرسال مدخلات التنفيذ بانتظار اعتماد العميل',
      logNoteCompleted: 'تم الإكمال. يرجى مراجعة الطلب وتقييم الخدمة.',
      logNoteCompletedReview: 'تم إكمال الطلب. يرجى مراجعة الطلب وتقييم الخدمة.',
      logNoteOfferSelected: 'اختيار عرض وإسناد الطلب لمزود الخدمة',
      logNoteRequestAssignedToProvider: 'قبول الطلب وإسناده لمزود الخدمة',
      logNoteProviderAcceptedRequest: 'قبول الطلب من مزود الخدمة',
      logNoteReopened: 'إعادة فتح الطلب',
      logNoteClientCancelledUrgentAfterAccept: 'إلغاء الطلب العاجل من العميل بعد قبول مزود الخدمة',
      logNoteClientCancelled: 'إلغاء الطلب من العميل',
      logNoteAdminCancelled: 'إلغاء الطلب من فريق الإدارة',
      logNoteProviderCancelled: 'إلغاء الطلب من مزود الخدمة',
      logNoteProviderUrgentDeclinedPrefix: 'اعتذار مزود الخدمة عن الطلب العاجل: {reason}',
      logNoteProviderCancelledPrefix: 'إلغاء من المزود: {reason}',
      logNoteProviderCancelledDuringExecutionPrefix: 'إلغاء من مزود الخدمة أثناء التنفيذ: {reason}',
      awaitingResponseLabel: 'بانتظار ردك على الطلب',
      awaitingResponseDesc: 'بعد قبول الطلب ستتمكن من إدخال السعر وموعد التسليم وإرسالها للعميل لاعتمادها.',
      acceptRequest: 'قبول الطلب',
      rejectRequest: 'رفض الطلب',
      rejectReasonLabel: 'سبب الرفض',
      rejectReasonPlaceholder: 'سبب الرفض...',
      cancelReasonPlaceholder: 'سبب الإلغاء...',
      urgentAvailableLabel: 'طلب عاجل متاح',
      urgentAvailableDesc: 'هذا الطلب العاجل متاح الآن لك. عند القبول سيتم إسناده لك مباشرة.',
      acceptUrgent: 'قبول الطلب العاجل',
      competitiveAvailableLabel: 'طلب عروض أسعار متاح',
      competitiveAvailableDesc: 'أدخل السعر ومدة التنفيذ لإرسال عرضك للعميل. يمكنك إرسال عرض واحد لكل طلب.',
      offerPriceLabel: 'سعر العرض (SR)',
      offerDurationLabel: 'مدة التنفيذ (يوم)',
      clientNoteLabel: 'ملاحظة للعميل (اختياري)',
      noteLabel: 'ملاحظة (اختياري)',
      notePlaceholder: 'ملاحظة (اختياري)',
      sendOffer: 'إرسال عرض السعر',
      offerSentLabel: 'عرض السعر',
      offerSentDesc: 'تم إرسال عرضك على هذا الطلب. بانتظار قرار العميل.',
      previousClientRejectionLabel: 'سبب رفض العميل للتفاصيل السابقة',
      sentProgressTitle: 'تحديث التقدم المرسل',
      expectedDeliveryLabel: 'موعد التسليم المتوقع',
      estimatedAmountLabel: 'قيمة الخدمة المقدرة (SR)',
      receivedAmountLabel: 'المبلغ المستلم (SR)',
      resendUpdateToClient: 'إعادة إرسال التحديث للعميل',
      resendExecutionDetails: 'إعادة إرسال تفاصيل التنفيذ',
      sendExecutionDetails: 'إرسال تفاصيل التنفيذ',
      updateExecutionDetails: 'تحديث تفاصيل التنفيذ المرسلة',
      sendDetailsToClient: 'إرسال التفاصيل للعميل',
      resendDetailsToClient: 'إعادة إرسال التفاصيل',
      progressUpdateTitle: 'تحديث التقدم',
      progressUpdateButton: 'تحديث التقدم',
      completeOrderTitle: 'إكمال الطلب',
      deliveredAtLabel: 'موعد التسليم الفعلي',
      actualAmountLabel: 'قيمة الخدمة الفعلية (SR)',
      completionAttachmentsLabel: 'مرفقات الإكمال (فواتير/صور/ملفات)',
      progressAttachmentsLabel: 'مرفقات تتبع التنفيذ',
      progressAttachmentsHint: 'أرفق صور أو فيديو أو ملفات توضح سير العمل ليطلع عليها العميل',
      addAttachments: 'إضافة مرفقات',
      cancelDuringExecutionTitle: 'إلغاء الطلب أثناء التنفيذ',
      cancelOrder: 'إلغاء الطلب',
      completionDateLabel: 'موعد التسليم الفعلي',
      actualServiceAmountLabel: 'قيمة الخدمة الفعلية (SR)',
      clientReviewLabel: 'تقييم العميل',
      cancellationDateLabel: 'تاريخ الإلغاء',
      cancellationReasonLabel: 'سبب الإلغاء',
      remove: 'إزالة',
      acceptSuccess: 'تم قبول الطلب. أرسل تفاصيل التنفيذ للعميل',
      urgentAcceptSuccess: 'تم قبول الطلب العاجل بنجاح',
      operationFailed: 'فشلت العملية',
      invalidOfferPrice: 'أدخل سعر عرض صالح',
      invalidDuration: 'أدخل مدة تنفيذ بالأيام بشكل صحيح',
      offerSentSuccess: 'تم إرسال عرض السعر بنجاح',
      offerAlreadyExists: 'تم إرسال عرض مسبقًا على هذا الطلب',
      offerSendFailed: 'تعذّر إرسال العرض',
      chooseExpectedDelivery: 'حدد موعد التسليم المتوقع',
      enterEstimatedAndReceived: 'أدخل القيمة المقدرة والمبلغ المستلم',
      enterAmountsTogether: 'أدخل القيمة المقدرة والمبلغ المستلم معًا',
      enterNoteOrUpdate: 'أدخل ملاحظة أو حدّث بيانات التنفيذ',
      progressSentAwaitingClient: 'تم إرسال تحديثك للعميل بانتظار القرار',
      progressUpdated: 'تم تحديث التقدم',
      chooseActualDelivery: 'حدد موعد التسليم الفعلي',
      enterActualAmount: 'أدخل قيمة الخدمة الفعلية',
      orderCompleted: 'تم إكمال الطلب',
      writeCancelReason: 'الرجاء كتابة سبب الإلغاء',
      orderCancelled: 'تم إلغاء الطلب',
      orderRejected: 'تم رفض الطلب',
      cannotDetermineClient: 'تعذّر تحديد العميل لفتح المحادثة',
      openChatFailed: 'تعذّر فتح المحادثة',
      retry: 'إعادة المحاولة',
      originalLanguageNotice: 'بعض التفاصيل والأسماء والملاحظات تُعرض بلغتها الأصلية.',
      summaryStatus: '{type} بحالة {status}',
      summaryWithin: 'ضمن {category}',
      summaryIn: 'في {city}'
    },
    en: {
      pageTitle: 'Order Details — Nawafeth',
      gateTitle: 'Sign in required',
      gateDescription: 'Please sign in to access the order details.',
      login: 'Sign in',
      back: 'Back',
      detailTitle: 'Order details',
      detailSubtitle: 'Order operations details',
      openMessages: 'Open messages',
      startChat: 'Start chat with client',
      openingChat: 'Opening chat...',
      requestChip: 'Request',
      attachmentsLabel: 'Attachments',
      executionAttachmentsLabel: 'Execution attachments',
      statusLabel: 'Status',
      descriptionHeading: 'Request description',
      textLabel: 'Text',
      actionsHeading: 'Actions',
      logsHeading: 'Timeline',
      backToOrders: 'Back to orders',
      clientHeading: 'Client',
      phoneLabel: 'Phone',
      cityLabel: 'City',
      unavailable: 'Not available',
      invalidUrl: 'Invalid link',
      loadFailed: 'Unable to load the order details',
      requestTypeDefault: 'Service request',
      typeNormal: 'Standard',
      typeCompetitive: 'Competitive',
      typeUrgent: 'Urgent',
      statusNew: 'New',
      statusAccepted: 'Accepted',
      statusAwaitingClient: 'Awaiting client approval for the details',
      statusInProgress: 'In progress',
      statusCompleted: 'Completed',
      statusCancelled: 'Cancelled',
      fileImage: 'Image',
      fileVideo: 'Video',
      fileAudio: 'Audio',
      fileDocument: 'Document',
      file: 'File',
      attachmentAlt: 'Attachment',
      openFile: 'Open file',
      fileUnavailable: 'Unavailable',
      fromProvider: 'From provider',
      fromClient: 'From client',
      noAttachments: 'No attachments available.',
      clientAttachments: 'Client attachments',
      providerAttachments: 'Provider attachments',
      logStatusUpdate: 'Status update: {status}',
      logStatusTransition: 'From {from} to {to}',
      byActor: 'By: {actor}',
      logNoteProviderAcceptedAwaitingDetails: 'Provider accepted the request and is expected to send execution details',
      logNoteProviderSentExecutionInputs: 'Provider sent or updated the execution inputs',
      logNoteProviderSentProgressUpdate: 'Provider sent a progress update pending client approval',
      logNoteClientApprovedInputs: 'The client approved the provider inputs and execution started',
      logNoteClientApprovedProgress: 'The client approved the progress update and execution can continue',
      logNoteClientApprovedInputsWithNote: 'The client approved the provider inputs: {note}',
      logNoteClientApprovedProgressWithNote: 'The client approved the progress update: {note}',
      logNoteClientRejectedInputs: 'The client rejected the provider inputs',
      logNoteClientRejectedProgress: 'The client rejected the progress update',
      logNoteClientRejectedInputsWithNote: 'The client rejected the provider inputs: {note}',
      logNoteClientRejectedProgressWithNote: 'The client rejected the progress update: {note}',
      logNoteStartExecution: 'Execution started',
      logNoteStartExecutionAwaitingApproval: 'Execution inputs were sent and are waiting for client approval',
      logNoteCompleted: 'Completed. Please review the request and rate the service.',
      logNoteCompletedReview: 'The order was completed. Please review the request and rate the service.',
      logNoteOfferSelected: 'An offer was selected and the request was assigned to the provider',
      logNoteRequestAssignedToProvider: 'The request was accepted and assigned to the provider',
      logNoteProviderAcceptedRequest: 'The provider accepted the request',
      logNoteReopened: 'The request was reopened',
      logNoteClientCancelledUrgentAfterAccept: 'The client cancelled the urgent request after provider acceptance',
      logNoteClientCancelled: 'The client cancelled the request',
      logNoteAdminCancelled: 'The admin team cancelled the request',
      logNoteProviderCancelled: 'The provider cancelled the request',
      logNoteProviderUrgentDeclinedPrefix: 'The provider declined the urgent request: {reason}',
      logNoteProviderCancelledPrefix: 'Cancelled by provider: {reason}',
      logNoteProviderCancelledDuringExecutionPrefix: 'Cancelled by provider during execution: {reason}',
      awaitingResponseLabel: 'Waiting for your response',
      awaitingResponseDesc: 'After accepting the request, you will be able to enter the price and delivery date, then send them to the client for approval.',
      acceptRequest: 'Accept request',
      rejectRequest: 'Reject request',
      rejectReasonLabel: 'Rejection reason',
      rejectReasonPlaceholder: 'Rejection reason...',
      cancelReasonPlaceholder: 'Cancellation reason...',
      urgentAvailableLabel: 'Urgent request available',
      urgentAvailableDesc: 'This urgent request is available to you now. Once accepted, it will be assigned to you directly.',
      acceptUrgent: 'Accept urgent request',
      competitiveAvailableLabel: 'Competitive quote request available',
      competitiveAvailableDesc: 'Enter the price and execution duration to send your offer to the client. You can send one offer per request.',
      offerPriceLabel: 'Offer price (SAR)',
      offerDurationLabel: 'Execution duration (days)',
      clientNoteLabel: 'Note to client (optional)',
      noteLabel: 'Note (optional)',
      notePlaceholder: 'Note (optional)',
      sendOffer: 'Send quote offer',
      offerSentLabel: 'Quote offer',
      offerSentDesc: 'Your offer has already been sent for this request. Waiting for the client decision.',
      previousClientRejectionLabel: 'Reason the client rejected the previous details',
      sentProgressTitle: 'Last progress update sent',
      expectedDeliveryLabel: 'Expected delivery time',
      estimatedAmountLabel: 'Estimated service amount (SAR)',
      receivedAmountLabel: 'Received amount (SAR)',
      resendUpdateToClient: 'Resend update to client',
      resendExecutionDetails: 'Resend execution details',
      sendExecutionDetails: 'Send execution details',
      updateExecutionDetails: 'Update the execution details already sent',
      sendDetailsToClient: 'Send details to client',
      resendDetailsToClient: 'Resend details',
      progressUpdateTitle: 'Progress update',
      progressUpdateButton: 'Update progress',
      completeOrderTitle: 'Complete order',
      deliveredAtLabel: 'Actual delivery time',
      actualAmountLabel: 'Actual service amount (SAR)',
      completionAttachmentsLabel: 'Completion attachments (invoices/images/files)',
      progressAttachmentsLabel: 'Workflow attachments',
      progressAttachmentsHint: 'Attach photos, video or files showing work progress so the client can follow along',
      addAttachments: 'Add attachments',
      cancelDuringExecutionTitle: 'Cancel order during execution',
      cancelOrder: 'Cancel order',
      completionDateLabel: 'Actual delivery time',
      actualServiceAmountLabel: 'Actual service amount (SAR)',
      clientReviewLabel: 'Client review',
      cancellationDateLabel: 'Cancellation date',
      cancellationReasonLabel: 'Cancellation reason',
      remove: 'Remove',
      acceptSuccess: 'The request was accepted. Send the execution details to the client.',
      urgentAcceptSuccess: 'The urgent request was accepted successfully',
      operationFailed: 'The operation failed',
      invalidOfferPrice: 'Enter a valid offer price',
      invalidDuration: 'Enter a valid execution duration in days',
      offerSentSuccess: 'The quote offer was sent successfully',
      offerAlreadyExists: 'An offer has already been sent for this request',
      offerSendFailed: 'Unable to send the offer',
      chooseExpectedDelivery: 'Select the expected delivery time',
      enterEstimatedAndReceived: 'Enter the estimated amount and received amount',
      enterAmountsTogether: 'Enter the estimated amount and the received amount together',
      enterNoteOrUpdate: 'Enter a note or update the execution details',
      progressSentAwaitingClient: 'Your update was sent to the client and is waiting for a decision',
      progressUpdated: 'Progress updated',
      chooseActualDelivery: 'Select the actual delivery time',
      enterActualAmount: 'Enter the actual service amount',
      orderCompleted: 'The order was completed',
      writeCancelReason: 'Please provide a cancellation reason',
      orderCancelled: 'The order was cancelled',
      orderRejected: 'The request was rejected',
      cannotDetermineClient: 'Unable to determine the client to open the chat',
      openChatFailed: 'Unable to open the chat',
      retry: 'Retry',
      originalLanguageNotice: 'Some request details, names, and notes are shown in their original language.',
      summaryStatus: '{type} with status {status}',
      summaryWithin: 'under {category}',
      summaryIn: 'in {city}'
    }
  };
  const TYPE_COPY_KEYS = { normal: 'typeNormal', competitive: 'typeCompetitive', urgent: 'typeUrgent' };
  const STATUS_COLOR = { new: '#A56800', in_progress: '#E67E22', completed: '#2E7D32', cancelled: '#C62828' };
  const STATUS_PILL_TEXT_COLOR = '#F8FAFC';
  const STATUS_COPY_KEYS = {
    new: 'statusNew',
    provider_accepted: 'statusAccepted',
    awaiting_client: 'statusAwaitingClient',
    in_progress: 'statusInProgress',
    completed: 'statusCompleted',
    cancelled: 'statusCancelled',
    canceled: 'statusCancelled'
  };
  const FILE_TYPE_COPY_KEYS = { image: 'fileImage', video: 'fileVideo', audio: 'fileAudio', document: 'fileDocument' };
  const SYSTEM_LOG_NOTE_COPY_KEYS = {
    'قبول من المزود بانتظار إرسال تفاصيل التنفيذ': 'logNoteProviderAcceptedAwaitingDetails',
    'إرسال/تحديث مدخلات التنفيذ من مزود الخدمة': 'logNoteProviderSentExecutionInputs',
    'إرسال تحديث تقدم من مزود الخدمة بانتظار اعتماد العميل': 'logNoteProviderSentProgressUpdate',
    'العميل وافق على مدخلات المزود وبدأ التنفيذ': 'logNoteClientApprovedInputs',
    'العميل وافق على تحديث التقدم ويمكن متابعة التنفيذ': 'logNoteClientApprovedProgress',
    'العميل رفض مدخلات المزود': 'logNoteClientRejectedInputs',
    'العميل رفض تحديث التقدم': 'logNoteClientRejectedProgress',
    'بدء التنفيذ': 'logNoteStartExecution',
    'إرسال مدخلات التنفيذ بانتظار اعتماد العميل': 'logNoteStartExecutionAwaitingApproval',
    'تم الإكمال. يرجى مراجعة الطلب وتقييم الخدمة.': 'logNoteCompleted',
    'تم إكمال الطلب. يرجى مراجعة الطلب وتقييم الخدمة.': 'logNoteCompletedReview',
    'اختيار عرض وإسناد الطلب لمزود الخدمة': 'logNoteOfferSelected',
    'قبول الطلب وإسناده لمزود الخدمة': 'logNoteRequestAssignedToProvider',
    'قبول الطلب من مزود الخدمة': 'logNoteProviderAcceptedRequest',
    'إعادة فتح الطلب': 'logNoteReopened',
    'إلغاء الطلب العاجل من العميل بعد قبول مزود الخدمة': 'logNoteClientCancelledUrgentAfterAccept',
    'إلغاء الطلب من العميل': 'logNoteClientCancelled',
    'إلغاء الطلب من فريق الإدارة': 'logNoteAdminCancelled',
    'إلغاء الطلب من مزود الخدمة': 'logNoteProviderCancelled'
  };

  function init() {
    if (state.initialized) return;
    state.initialized = true;

    applyStaticCopy();
    document.addEventListener('nawafeth:languagechange', handleLanguageChange);

    if (!Auth.isLoggedIn()) return showGate();
    byId('pod-content').style.display = '';
    const m = location.pathname.match(/\/provider-orders\/(\d+)\/?$/);
    if (!m) return showError(_copy('invalidUrl'));
    state.id = Number(m[1]);
    bindChatButtons();
    loadDetail();
  }

  function applyStaticCopy() {
    document.title = _copy('pageTitle');

    const backLink = byId('pod-back-link');
    const topChatButton = byId('pod-chat-btn');
    const launchChatButton = byId('pod-chat-launch-btn');

    setText('pod-auth-title', _copy('gateTitle'));
    setText('pod-auth-desc', _copy('gateDescription'));
    setText('pod-login-link', _copy('login'));
    setText('pod-page-title', _copy('detailTitle'));
    setText('pod-page-subtitle', _copy('detailSubtitle'));
    setText('pod-request-chip', _copy('requestChip'));
    setText('pod-chat-launch-label', _copy('startChat'));
    setText('pod-overview-attachments-label', _copy('attachmentsLabel'));
    setText('pod-overview-final-label', _copy('executionAttachmentsLabel'));
    setText('pod-overview-status-label', _copy('statusLabel'));
    setText('pod-description-heading', _copy('descriptionHeading'));
    setText('pod-description-label', _copy('textLabel'));
    setText('pod-attachments-heading', _copy('attachmentsLabel'));
    setText('pod-attachments-empty', _copy('noAttachments'));
    setText('pod-actions-heading', _copy('actionsHeading'));
    setText('pod-logs-heading', _copy('logsHeading'));
    setText('pod-back-orders-link', _copy('backToOrders'));
    setText('pod-client-heading', _copy('clientHeading'));
    setText('pod-phone-label', _copy('phoneLabel'));
    setText('pod-city-label', _copy('cityLabel'));

    if (backLink) backLink.setAttribute('aria-label', _copy('back'));
    if (topChatButton) topChatButton.setAttribute('aria-label', _copy('openMessages'));
    if (launchChatButton) launchChatButton.setAttribute('aria-label', _copy('startChat'));
  }

  function handleLanguageChange() {
    applyStaticCopy();
    if (state.order) {
      render();
      return;
    }
    renderPickedFiles();
    updateChatButtons();
  }

  function bindChatButtons() {
    [byId('pod-chat-btn'), byId('pod-chat-launch-btn')].forEach((button) => {
      if (!button || button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', openChat);
    });
    updateChatButtons();
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
    if (!res.ok || !res.data || typeof res.data !== 'object') return showError(extractError(res, _copy('loadFailed')));
    state.order = res.data;
    state.completionFiles = [];
    state.progressFiles = [];
    state.offerAlreadySent = false;
    render();
  }

  function render() {
    const o = state.order;
    if (!o) return;
    hideError();
    byId('pod-detail').style.display = '';

    const clientName = val(o.client_name, _copy('unavailable'));
    const clientPhone = val(o.client_phone, _copy('unavailable'));
    const requestCity = localizedRequestCity(o);
    const clientCity = val(
      localizedClientCity(o, requestCity),
      _copy('unavailable')
    );
    setText('pod-client-name', clientName);
    setText('pod-client-phone', clientPhone);
    setText('pod-client-city', clientCity);
    setText('pod-client-summary', [clientPhone, clientCity].filter((item) => item && item !== _copy('unavailable')).join(' • ') || '-');
    setText('pod-client-initials', clientInitials(clientName));

    const displayId = Number.isFinite(Number(o.id)) ? ('R' + String(o.id).padStart(6, '0')) : val(o.display_id, '-');
    setText('pod-display-id', displayId);

    const t = str(o.request_type).toLowerCase();
    const typeBadge = byId('pod-type-badge');
    if (t && t !== 'normal') {
      typeBadge.style.display = 'inline-flex';
      typeBadge.textContent = typeLabel(t);
      const urgent = t === 'urgent';
      typeBadge.style.color = urgent ? '#C62828' : '#1565C0';
      typeBadge.style.backgroundColor = urgent ? 'rgba(198,40,40,.12)' : 'rgba(21,101,192,.12)';
    } else {
      typeBadge.style.display = 'none';
      typeBadge.textContent = '';
    }

    const c = localizedCategoryName(o);
    const s = localizedSubcategoryName(o);
    const catEl = byId('pod-category');
    if (c) {
      catEl.style.display = '';
      catEl.textContent = s ? (c + ' / ' + s) : c;
    } else {
      catEl.style.display = 'none';
      catEl.textContent = '';
    }
    setText('pod-date', fmtDateTime(o.created_at));
    setText('pod-hero-summary', buildHeroSummary(o, requestCity || clientCity));

    const group = statusGroup(o);
    const color = STATUS_COLOR[group] || '#9E9E9E';
    const status = byId('pod-status-pill');
    status.textContent = statusLabelFromRaw(o.status);
    status.style.color = STATUS_PILL_TEXT_COLOR;
    status.style.backgroundColor = color + '33';
    status.style.borderColor = color + 'A6';
    status.style.boxShadow = '0 10px 22px rgba(15, 23, 42, 0.18), inset 0 1px 0 rgba(255, 255, 255, 0.12)';
    setText('pod-status-inline', status.textContent || '-');

    setTextAutoDirection('pod-title', val(o.title, '-'));
    setTextAutoDirection('pod-description', val(o.description, '-'));
    updateOriginalLanguageNotice(o);

    renderAttachments(o);
    renderLogs(o);
    renderActions(o, group);
    updateChatButtons();
  }

  function renderAttachments(o) {
    const list = Array.isArray(o.attachments) ? o.attachments : [];
    const empty = byId('pod-attachments-empty');
    const fw = byId('pod-final-attachments-wrap');
    const rw = byId('pod-regular-attachments-wrap');
    const fh = byId('pod-final-attachments');
    const rh = byId('pod-regular-attachments');
    const rhTitle = byId('pod-regular-heading');
    const fhTitle = byId('pod-final-heading');
    const fCount = byId('pod-final-count');
    const rCount = byId('pod-regular-count');
    fh.innerHTML = '';
    rh.innerHTML = '';
    if (fhTitle) fhTitle.textContent = _copy('providerAttachments');
    if (rhTitle) rhTitle.textContent = _copy('clientAttachments');
    if (!list.length) {
      empty.style.display = '';
      empty.textContent = _copy('noAttachments');
      fw.style.display = 'none';
      rw.style.display = 'none';
      if (fCount) fCount.textContent = localizeDigits('0');
      if (rCount) rCount.textContent = localizeDigits('0');
      setText('pod-final-count-summary', localizeDigits('0'));
      setText('pod-regular-count-summary', localizeDigits('0'));
      return;
    }
    empty.style.display = 'none';
    const completionMoment = resolveCompletionMoment(o);
    const finals = [];
    const regular = [];
    list.forEach((a) => {
      if (isProviderAttachment(a, completionMoment, o)) finals.push(a);
      else regular.push(a);
    });
    finals.sort((a, b) => toMs(b && b.created_at) - toMs(a && a.created_at));
    regular.sort((a, b) => toMs(b && b.created_at) - toMs(a && a.created_at));
    if (fCount) fCount.textContent = localizeDigits(finals.length);
    if (rCount) rCount.textContent = localizeDigits(regular.length);
    setText('pod-final-count-summary', localizeDigits(finals.length));
    setText('pod-regular-count-summary', localizeDigits(regular.length));
    fw.classList.add('is-provider');
    rw.classList.add('is-client');
    if (finals.length) {
      fw.style.display = '';
      finals.forEach((a) => fh.appendChild(attachmentRow(a, true)));
    } else fw.style.display = 'none';
    if (regular.length) {
      rw.style.display = '';
      regular.forEach((a) => rh.appendChild(attachmentRow(a, false)));
    } else rw.style.display = 'none';
  }

  function attachmentRow(a, isProviderFile) {
    const path = str(a.file_url) || str(a.file) || str(a.url);
    const href = path ? ApiClient.mediaUrl(path) : '';
    const type = (str(a.file_type) || 'document').toLowerCase();
    const name = attachmentName(path, a);
    const el = document.createElement(href ? 'a' : 'div');
    el.className = 'pod-attachment-row' + (isProviderFile ? ' is-final' : '');
    if (href) {
      el.href = href;
      el.target = '_blank';
      el.rel = 'noopener';
    }

    const preview = document.createElement('div');
    preview.className = 'pod-attachment-preview';
    preview.appendChild(buildAttachmentPreview(type, href, name));

    const body = document.createElement('span');
    body.className = 'pod-attachment-body';

    const head = document.createElement('span');
    head.className = 'pod-attachment-head';

    const title = document.createElement('span');
    title.className = 'pod-attachment-name';
    title.textContent = name || _copy('file');

    const open = document.createElement('span');
    open.className = 'pod-attachment-open';
    open.textContent = href ? _copy('openFile') : _copy('fileUnavailable');

    head.appendChild(title);
    head.appendChild(open);
    body.appendChild(head);

    const meta = document.createElement('span');
    meta.className = 'pod-attachment-meta';
    const badge = document.createElement('span');
    badge.className = 'pod-attachment-type';
    badge.textContent = fileTypeLabel(type);
    meta.appendChild(badge);

    const owner = document.createElement('span');
    owner.className = 'pod-attachment-owner';
    owner.textContent = isProviderFile ? _copy('fromProvider') : _copy('fromClient');
    meta.appendChild(owner);

    const createdAt = asDate(a && a.created_at);
    if (createdAt) {
      const date = document.createElement('span');
      date.className = 'pod-attachment-date';
      date.textContent = fmtDateTime(createdAt);
      meta.appendChild(date);
    }
    body.appendChild(meta);

    el.appendChild(preview);
    el.appendChild(body);
    return el;
  }

  function buildAttachmentPreview(type, href, name) {
    if (type === 'image' && href) {
      const img = document.createElement('img');
      img.src = href;
      img.alt = name || _copy('attachmentAlt');
      img.loading = 'lazy';
      return img;
    }
    if (type === 'video' && href) {
      const video = document.createElement('video');
      video.src = href;
      video.muted = true;
      video.playsInline = true;
      video.preload = 'metadata';
      return video;
    }

    const box = document.createElement('div');
    box.className = 'pod-attachment-placeholder';
    const strong = document.createElement('strong');
    strong.textContent = fileTypeCode(type);
    const label = document.createElement('span');
    label.textContent = fileTypeLabel(type);
    box.appendChild(strong);
    box.appendChild(label);
    return box;
  }

  function renderLogs(o) {
    const section = byId('pod-logs-section');
    const root = byId('pod-logs');
    const logs = Array.isArray(o.status_logs) ? o.status_logs.slice() : [];
    logs.sort((a, b) => toMs(b && b.created_at) - toMs(a && a.created_at));
    root.innerHTML = '';
    if (!logs.length) {
      section.style.display = 'none';
      return;
    }
    section.style.display = '';
    logs.forEach((log, idx) => {
      const row = document.createElement('div');
      row.className = 'pod-log-item';
      if (idx === logs.length - 1) row.classList.add('is-last');
      const dot = document.createElement('span');
      dot.className = 'pod-log-dot';
      const targetGroup = statusGroupFromRaw(log.to_status);
      const dotColor = STATUS_COLOR[targetGroup] || '#673AB7';
      dot.style.backgroundColor = dotColor;
      dot.style.boxShadow = '0 0 0 4px ' + dotColor + '29';
      const body = document.createElement('div');
      body.className = 'pod-log-body';
      const title = document.createElement('p');
      title.className = 'pod-log-title';
      const fromLabel = statusLabelFromRaw(log.from_status);
      const toLabel = statusLabelFromRaw(log.to_status);
      title.textContent = fromLabel === toLabel
        ? _copy('logStatusUpdate', { status: toLabel })
        : _copy('logStatusTransition', { from: fromLabel, to: toLabel });
      body.appendChild(title);
      const actor = str(log.actor_name);
      if (actor && actor !== '-') {
        const p = document.createElement('p');
        p.className = 'pod-log-actor';
        p.textContent = _copy('byActor', { actor });
        body.appendChild(p);
      }
      const note = localizeSystemLogNote(log.note);
      if (note) {
        const p = document.createElement('p');
        p.className = 'pod-log-note';
        p.textContent = note;
        setAutoDirection(p, note);
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
    if (workflowStage(o) === 'awaiting_client' && providerInputsStage(o) === 'progress_update') {
      return renderAwaitingClientProgressActions(root, o);
    }
    if (group === 'new') {
      if (isCompetitiveAvailable(o)) return renderCompetitiveOfferActions(root);
      if (isUrgentAvailable(o)) return renderUrgentAvailableActions(root);
      if (isAwaitingProviderAcceptance(o)) return renderAwaitingAcceptanceActions(root, o);
      if (isCompetitiveAssigned(o) && canSendExecutionDetails(o)) return renderCompetitiveAssignedNewActions(root, o);
      if (canSendExecutionDetails(o)) return renderAssignedNewActions(root, o);
      return renderAssignedNewActions(root, o);
    }
    if (group === 'in_progress') return renderProgressActions(root, o);
    if (group === 'completed') return renderCompleted(root, o);
    if (group === 'cancelled') return renderCancelled(root, o);
  }

  function renderAwaitingClientProgressActions(root, o) {
    root.innerHTML = `
      <div class="pod-readonly-box">
        <label>${_copy('sentProgressTitle')}</label>
        <p>${_copy('progressSentAwaitingClient')}</p>
      </div>
      <p class="pod-action-title">${_copy('sentProgressTitle')}</p>
      <label class="pod-input-label" for="pod-expected-delivery">${_copy('expectedDeliveryLabel')}</label>
      <input type="datetime-local" class="pod-input" id="pod-expected-delivery">
      <div class="pod-grid-2">
        <div><label class="pod-input-label" for="pod-estimated-amount">${_copy('estimatedAmountLabel')}</label><input type="number" class="pod-input" id="pod-estimated-amount" step="0.01" min="0" placeholder="0"></div>
        <div><label class="pod-input-label" for="pod-received-amount">${_copy('receivedAmountLabel')}</label><input type="number" class="pod-input" id="pod-received-amount" step="0.01" min="0" placeholder="0"></div>
      </div>
      <label class="pod-input-label" for="pod-note">${_copy('noteLabel')}</label>
      <textarea class="pod-textarea" id="pod-note" rows="2" placeholder="${_copy('notePlaceholder')}"></textarea>
      ${progressFilesPickerHtml()}
      <button type="button" class="pod-btn pod-btn-warning pod-btn-block" id="pod-progress-btn" data-pod-action>${_copy('resendUpdateToClient')}</button>`;
    byId('pod-expected-delivery').value = toDateTimeInput(o.expected_delivery_at);
    byId('pod-estimated-amount').value = str(o.estimated_service_amount);
    byId('pod-received-amount').value = str(o.received_amount);
    byId('pod-progress-btn').addEventListener('click', () => submitProgress(false));
    bindProgressFilesPicker();
    setActionLoading(false);
  }

  function renderAssignedNewActions(root, o) {
    root.innerHTML = `
      <div class="pod-readonly-box" id="pod-client-rejection-box" style="display:none"><label>${_copy('previousClientRejectionLabel')}</label><p id="pod-client-rejection-note">-</p></div>
      <p class="pod-action-title" id="pod-progress-title"></p>
      <label class="pod-input-label" for="pod-expected-delivery">${_copy('expectedDeliveryLabel')}</label>
      <input type="datetime-local" class="pod-input" id="pod-expected-delivery">
      <div class="pod-grid-2">
        <div><label class="pod-input-label" for="pod-estimated-amount">${_copy('estimatedAmountLabel')}</label><input type="number" class="pod-input" id="pod-estimated-amount" step="0.01" min="0" placeholder="0"></div>
        <div><label class="pod-input-label" for="pod-received-amount">${_copy('receivedAmountLabel')}</label><input type="number" class="pod-input" id="pod-received-amount" step="0.01" min="0" placeholder="0"></div>
      </div>
      <label class="pod-input-label" for="pod-note">${_copy('noteLabel')}</label>
      <textarea class="pod-textarea" id="pod-note" rows="2" placeholder="${_copy('notePlaceholder')}"></textarea>
      ${progressFilesPickerHtml()}
      <button type="button" class="pod-btn pod-btn-primary pod-btn-block" id="pod-progress-btn" data-pod-action></button>
      <div class="pod-divider"></div>
      <p class="pod-action-title">${_copy('rejectRequest')}</p>
      <label class="pod-input-label" for="pod-cancel-reason">${_copy('cancellationReasonLabel')}</label>
      <textarea class="pod-textarea" id="pod-cancel-reason" rows="2" placeholder="${_copy('cancelReasonPlaceholder')}"></textarea>
      <button type="button" class="pod-btn pod-btn-outline-danger pod-btn-block" id="pod-reject-btn" data-pod-action>${_copy('rejectRequest')}</button>`;
    byId('pod-expected-delivery').value = toDateTimeInput(o.expected_delivery_at);
    byId('pod-estimated-amount').value = str(o.estimated_service_amount);
    byId('pod-received-amount').value = str(o.received_amount);
    byId('pod-cancel-reason').value = str(o.cancel_reason);
    const rejected = o.provider_inputs_approved === false;
    const waitingClient = workflowStage(o) === 'awaiting_client' && !rejected;
    byId('pod-progress-title').textContent = rejected
      ? _copy('resendExecutionDetails')
      : (waitingClient ? _copy('updateExecutionDetails') : _copy('sendExecutionDetails'));
    byId('pod-progress-btn').textContent = rejected
      ? _copy('resendDetailsToClient')
      : (waitingClient ? _copy('updateExecutionDetails') : _copy('sendDetailsToClient'));
    const rbox = byId('pod-client-rejection-box');
    if (rejected) {
      rbox.style.display = '';
      setTextAutoDirection('pod-client-rejection-note', val(o.provider_inputs_decision_note, '-'));
    } else rbox.style.display = 'none';
    byId('pod-progress-btn').addEventListener('click', () => submitProgress(true));
    byId('pod-reject-btn').addEventListener('click', rejectOrder);
    bindProgressFilesPicker();
    setActionLoading(false);
  }

  function renderAwaitingAcceptanceActions(root) {
    root.innerHTML = `
      <div class="pod-readonly-box">
        <label>${_copy('awaitingResponseLabel')}</label>
        <p>${_copy('awaitingResponseDesc')}</p>
      </div>
      <button type="button" class="pod-btn pod-btn-success pod-btn-block" id="pod-accept-btn" data-pod-action>${_copy('acceptRequest')}</button>
      <div class="pod-divider"></div>
      <p class="pod-action-title">${_copy('rejectRequest')}</p>
      <label class="pod-input-label" for="pod-cancel-reason">${_copy('rejectReasonLabel')}</label>
      <textarea class="pod-textarea" id="pod-cancel-reason" rows="2" placeholder="${_copy('cancelReasonPlaceholder')}"></textarea>
      <button type="button" class="pod-btn pod-btn-outline-danger pod-btn-block" id="pod-reject-btn" data-pod-action>${_copy('rejectRequest')}</button>`;
    byId('pod-accept-btn').addEventListener('click', acceptOrder);
    byId('pod-reject-btn').addEventListener('click', rejectOrder);
    setActionLoading(false);
  }

  function renderUrgentAvailableActions(root) {
    root.innerHTML = `
      <div class="pod-readonly-box">
        <label>${_copy('urgentAvailableLabel')}</label>
        <p>${_copy('urgentAvailableDesc')}</p>
      </div>
      <button type="button" class="pod-btn pod-btn-danger pod-btn-block" id="pod-urgent-accept-btn" data-pod-action>${_copy('acceptUrgent')}</button>`;
    byId('pod-urgent-accept-btn').addEventListener('click', acceptOrder);
    setActionLoading(false);
  }

  function renderCompetitiveOfferActions(root) {
    if (state.offerAlreadySent) {
      root.appendChild(readonly(_copy('offerSentLabel'), _copy('offerSentDesc')));
      setActionLoading(false);
      return;
    }

    root.innerHTML = `
      <div class="pod-readonly-box">
        <label>${_copy('competitiveAvailableLabel')}</label>
        <p>${_copy('competitiveAvailableDesc')}</p>
      </div>
      <div class="pod-grid-2">
        <div><label class="pod-input-label" for="pod-offer-price">${_copy('offerPriceLabel')}</label><input type="number" class="pod-input" id="pod-offer-price" step="0.01" min="0" placeholder="0"></div>
        <div><label class="pod-input-label" for="pod-offer-duration">${_copy('offerDurationLabel')}</label><input type="number" class="pod-input" id="pod-offer-duration" step="1" min="1" placeholder="5"></div>
      </div>
      <label class="pod-input-label" for="pod-offer-note">${_copy('clientNoteLabel')}</label>
      <textarea class="pod-textarea" id="pod-offer-note" rows="3" placeholder="${_copy('notePlaceholder')}"></textarea>
      <button type="button" class="pod-btn pod-btn-primary pod-btn-block" id="pod-send-offer-btn" data-pod-action>${_copy('sendOffer')}</button>`;

    byId('pod-send-offer-btn').addEventListener('click', sendCompetitiveOffer);
    setActionLoading(false);
  }

  function renderCompetitiveAssignedNewActions(root, o) {
    root.innerHTML = `
      <div class="pod-readonly-box" id="pod-client-rejection-box" style="display:none"><label>${_copy('previousClientRejectionLabel')}</label><p id="pod-client-rejection-note">-</p></div>
      <p class="pod-action-title" id="pod-progress-title"></p>
      <label class="pod-input-label" for="pod-expected-delivery">${_copy('expectedDeliveryLabel')}</label>
      <input type="datetime-local" class="pod-input" id="pod-expected-delivery">
      <div class="pod-grid-2">
        <div><label class="pod-input-label" for="pod-estimated-amount">${_copy('estimatedAmountLabel')}</label><input type="number" class="pod-input" id="pod-estimated-amount" step="0.01" min="0" placeholder="0"></div>
        <div><label class="pod-input-label" for="pod-received-amount">${_copy('receivedAmountLabel')}</label><input type="number" class="pod-input" id="pod-received-amount" step="0.01" min="0" placeholder="0"></div>
      </div>
      <label class="pod-input-label" for="pod-note">${_copy('noteLabel')}</label>
      <textarea class="pod-textarea" id="pod-note" rows="2" placeholder="${_copy('notePlaceholder')}"></textarea>
      ${progressFilesPickerHtml()}
      <button type="button" class="pod-btn pod-btn-primary pod-btn-block" id="pod-progress-btn" data-pod-action></button>`;
    byId('pod-expected-delivery').value = toDateTimeInput(o.expected_delivery_at);
    byId('pod-estimated-amount').value = str(o.estimated_service_amount);
    byId('pod-received-amount').value = str(o.received_amount);

    const rejected = o.provider_inputs_approved === false;
    byId('pod-progress-title').textContent = rejected ? _copy('resendExecutionDetails') : _copy('sendExecutionDetails');
    byId('pod-progress-btn').textContent = rejected ? _copy('resendDetailsToClient') : _copy('sendDetailsToClient');
    const rbox = byId('pod-client-rejection-box');
    if (rejected) {
      rbox.style.display = '';
      setTextAutoDirection('pod-client-rejection-note', val(o.provider_inputs_decision_note, '-'));
    } else rbox.style.display = 'none';

    byId('pod-progress-btn').addEventListener('click', () => submitProgress(true));
    bindProgressFilesPicker();
    setActionLoading(false);
  }

  function renderProgressActions(root, o) {
    root.innerHTML = `
      <p class="pod-action-title">${_copy('progressUpdateTitle')}</p>
      <label class="pod-input-label" for="pod-expected-delivery">${_copy('expectedDeliveryLabel')}</label>
      <input type="datetime-local" class="pod-input" id="pod-expected-delivery">
      <div class="pod-grid-2">
        <div><label class="pod-input-label" for="pod-estimated-amount">${_copy('estimatedAmountLabel')}</label><input type="number" class="pod-input" id="pod-estimated-amount" step="0.01" min="0" placeholder="0"></div>
        <div><label class="pod-input-label" for="pod-received-amount">${_copy('receivedAmountLabel')}</label><input type="number" class="pod-input" id="pod-received-amount" step="0.01" min="0" placeholder="0"></div>
      </div>
      <label class="pod-input-label" for="pod-note">${_copy('noteLabel')}</label>
      <textarea class="pod-textarea" id="pod-note" rows="2" placeholder="${_copy('notePlaceholder')}"></textarea>
      ${progressFilesPickerHtml()}
      <button type="button" class="pod-btn pod-btn-warning pod-btn-block" id="pod-progress-btn" data-pod-action>${_copy('progressUpdateButton')}</button>
      <div class="pod-divider"></div>
      <p class="pod-action-title">${_copy('completeOrderTitle')}</p>
      <label class="pod-input-label" for="pod-delivered-at">${_copy('deliveredAtLabel')}</label>
      <input type="datetime-local" class="pod-input" id="pod-delivered-at">
      <label class="pod-input-label" for="pod-actual-amount">${_copy('actualAmountLabel')}</label>
      <input type="number" class="pod-input" id="pod-actual-amount" step="0.01" min="0" placeholder="0">
      <p class="pod-input-label">${_copy('completionAttachmentsLabel')}</p>
      <label class="pod-file-picker"><input type="file" id="pod-completion-files" multiple><span class="pod-btn pod-btn-outline pod-btn-block">${_copy('addAttachments')}</span></label>
      <div id="pod-completion-files-list" class="pod-file-list"></div>
      <button type="button" class="pod-btn pod-btn-success pod-btn-block" id="pod-complete-btn" data-pod-action>${_copy('completeOrderTitle')}</button>
      <div class="pod-divider"></div>
      <p class="pod-action-title">${_copy('cancelDuringExecutionTitle')}</p>
      <label class="pod-input-label" for="pod-cancel-reason">${_copy('cancellationReasonLabel')}</label>
      <textarea class="pod-textarea" id="pod-cancel-reason" rows="2" placeholder="${_copy('cancelReasonPlaceholder')}"></textarea>
      <button type="button" class="pod-btn pod-btn-outline-danger pod-btn-block" id="pod-reject-btn" data-pod-action>${_copy('cancelOrder')}</button>`;
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
    bindProgressFilesPicker();
    setActionLoading(false);
  }

  function renderCompleted(root, o) {
    root.appendChild(readonly(_copy('completionDateLabel'), o.delivered_at ? fmtDateOnly(o.delivered_at) : '-'));
    root.appendChild(readonly(_copy('actualServiceAmountLabel'), val(o.actual_service_amount, '-')));
    if (o.review_rating !== null && o.review_rating !== undefined) {
      root.appendChild(readonly(_copy('clientReviewLabel'), String(o.review_rating) + '/5 — ' + str(o.review_comment), { autoDirection: true }));
    }
  }

  function renderCancelled(root, o) {
    root.appendChild(readonly(_copy('cancellationDateLabel'), o.canceled_at ? fmtDateOnly(o.canceled_at) : '-'));
    root.appendChild(readonly(_copy('cancellationReasonLabel'), val(o.cancel_reason, '-'), { autoDirection: true }));
  }

  function readonly(label, value, options) {
    const box = document.createElement('div');
    box.className = 'pod-readonly-box';
    const l = document.createElement('label');
    l.textContent = label;
    const p = document.createElement('p');
    const text = val(value, '-');
    p.textContent = text;
    if (options && options.autoDirection) setAutoDirection(p, text);
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
      del.textContent = _copy('remove');
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

  function progressFilesPickerHtml() {
    return `
      <div class="pod-progress-files-block">
        <p class="pod-input-label">${_copy('progressAttachmentsLabel')}</p>
        <p class="pod-input-hint">${_copy('progressAttachmentsHint')}</p>
        <label class="pod-file-picker"><input type="file" id="pod-progress-files" multiple><span class="pod-btn pod-btn-outline pod-btn-block">${_copy('addAttachments')}</span></label>
        <div id="pod-progress-files-list" class="pod-file-list"></div>
      </div>`;
  }

  function bindProgressFilesPicker() {
    const input = byId('pod-progress-files');
    if (input) input.addEventListener('change', onProgressFilesPick);
    renderPickedProgressFiles();
  }

  function onProgressFilesPick(e) {
    const files = Array.from(e.target.files || []);
    files.forEach((f) => {
      if (!state.progressFiles.some((x) => x.name === f.name && x.size === f.size && x.lastModified === f.lastModified)) {
        state.progressFiles.push(f);
      }
    });
    e.target.value = '';
    renderPickedProgressFiles();
  }

  function renderPickedProgressFiles() {
    const root = byId('pod-progress-files-list');
    if (!root) return;
    root.innerHTML = '';
    state.progressFiles.forEach((f, i) => {
      const row = document.createElement('div');
      row.className = 'pod-file-row';
      const name = document.createElement('span');
      name.className = 'pod-file-name';
      name.textContent = f.name;
      const del = document.createElement('button');
      del.type = 'button';
      del.className = 'pod-file-remove';
      del.textContent = _copy('remove');
      del.setAttribute('data-pod-action', '1');
      del.disabled = state.actionLoading;
      del.addEventListener('click', () => {
        if (state.actionLoading) return;
        state.progressFiles.splice(i, 1);
        renderPickedProgressFiles();
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
    if (!res.ok) return toast(extractError(res, _copy('operationFailed')));
    toast(isUrgentAvailable(order)
      ? _copy('urgentAcceptSuccess')
      : _copy('acceptSuccess'));
    loadDetail();
  }

  async function sendCompetitiveOffer() {
    if (state.actionLoading) return;
    const priceRaw = str(byId('pod-offer-price').value);
    const durationRaw = str(byId('pod-offer-duration').value);
    const noteRaw = str(byId('pod-offer-note').value);

    const price = Number(priceRaw);
    if (!priceRaw || !Number.isFinite(price) || price <= 0) return toast(_copy('invalidOfferPrice'));

    const duration = Number(durationRaw);
    if (!durationRaw || !Number.isInteger(duration) || duration <= 0) {
      return toast(_copy('invalidDuration'));
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
      toast(_copy('offerSentSuccess'));
      renderActions(state.order, statusGroup(state.order));
      return;
    }

    if (res.status === 409) {
      state.offerAlreadySent = true;
      toast(_copy('offerAlreadyExists'));
      renderActions(state.order, statusGroup(state.order));
      return;
    }

    toast(extractError(res, _copy('offerSendFailed')));
  }

  async function submitProgress(isNew) {
    if (state.actionLoading) return;
    const expected = dateToIso(byId('pod-expected-delivery').value);
    const est = str(byId('pod-estimated-amount').value);
    const rec = str(byId('pod-received-amount').value);
    const note = str(byId('pod-note').value);
    if (isNew && !expected) return toast(_copy('chooseExpectedDelivery'));
    if (isNew && (!est || !rec)) return toast(_copy('enterEstimatedAndReceived'));
    if ((est && !rec) || (!est && rec)) return toast(_copy('enterAmountsTogether'));
    const hasFiles = state.progressFiles && state.progressFiles.length > 0;
    const fields = {};
    if (expected) fields.expected_delivery_at = expected;
    if (est) fields.estimated_service_amount = est;
    if (rec) fields.received_amount = rec;
    if (note) fields.note = note;
    if (!Object.keys(fields).length && !hasFiles) return toast(_copy('enterNoteOrUpdate'));
    setActionLoading(true);
    let res;
    if (hasFiles) {
      const fd = new FormData();
      Object.keys(fields).forEach((k) => fd.append(k, fields[k]));
      state.progressFiles.forEach((f) => fd.append('attachments', f, f.name));
      res = await ApiClient.request('/api/marketplace/provider/requests/' + state.id + '/progress-update/', { method: 'POST', body: fd });
    } else {
      res = await ApiClient.request('/api/marketplace/provider/requests/' + state.id + '/progress-update/', { method: 'POST', body: fields });
    }
    setActionLoading(false);
    if (!res.ok) return toast(extractError(res, _copy('operationFailed')));
    state.progressFiles = [];
    toast(isNew ? _copy('progressSentAwaitingClient') : _copy('progressUpdated'));
    loadDetail();
  }

  async function completeOrder() {
    if (state.actionLoading) return;
    const delivered = dateToIso(byId('pod-delivered-at').value);
    const actual = str(byId('pod-actual-amount').value);
    const noteEl = byId('pod-note');
    const note = noteEl ? str(noteEl.value) : '';
    if (!delivered) return toast(_copy('chooseActualDelivery'));
    if (!actual) return toast(_copy('enterActualAmount'));
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
    if (!res.ok) return toast(extractError(res, _copy('operationFailed')));
    toast(_copy('orderCompleted'));
    state.completionFiles = [];
    loadDetail();
  }

  async function rejectOrder() {
    if (state.actionLoading) return;
    const order = state.order;
    if (!order) return;
    const reason = str(byId('pod-cancel-reason').value);
    if (!reason) return toast(_copy('writeCancelReason'));
    setActionLoading(true);
    const endpoint = statusGroup(order) === 'in_progress'
      ? '/api/marketplace/provider/requests/' + state.id + '/cancel/'
      : '/api/marketplace/provider/requests/' + state.id + '/reject/';
    const res = await ApiClient.request(endpoint, {
      method: 'POST',
      body: { canceled_at: new Date().toISOString(), cancel_reason: reason },
    });
    setActionLoading(false);
    if (!res.ok) return toast(extractError(res, _copy('operationFailed')));
    toast(statusGroup(order) === 'in_progress' ? _copy('orderCancelled') : _copy('orderRejected'));
    loadDetail();
  }

  async function openChat(event) {
    if (event) event.preventDefault();
    if (state.chatOpening) return;
    if (!state.order || !state.id) {
      toast(_copy('cannotDetermineClient'));
      return;
    }

    state.chatOpening = true;
    updateChatButtons();
    const res = await ApiClient.request(withMode('/api/messaging/direct/thread/'), {
      method: 'POST',
      body: { request_id: state.id },
    });
    state.chatOpening = false;
    updateChatButtons();

    if (!res.ok || !res.data || !res.data.id) {
      toast(extractError(res, _copy('openChatFailed')));
      return;
    }

    window.location.href = withMode('/chat/' + res.data.id + '/');
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
    btn.textContent = _copy('retry');
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

  function updateChatButtons() {
    const canChat = !!(state.order && state.id);
    [byId('pod-chat-btn'), byId('pod-chat-launch-btn')].forEach((button) => {
      if (!button) return;
      button.disabled = !canChat || state.chatOpening;
      button.setAttribute('aria-disabled', (!canChat || state.chatOpening) ? 'true' : 'false');
    });
    const launchLabel = byId('pod-chat-launch-btn');
    if (launchLabel) {
      const label = launchLabel.querySelector('.pod-chat-btn-text span:last-child');
      if (label) {
        label.textContent = state.chatOpening
          ? _copy('openingChat')
          : _copy('startChat');
      }
    }
  }

  function buildHeroSummary(order, cityLabel) {
    const parts = [];
    const type = typeLabel(str(order && order.request_type).toLowerCase()) || _copy('requestTypeDefault');
    const status = statusLabelFromRaw(order && order.status);
    const category = [localizedCategoryName(order), localizedSubcategoryName(order)].filter(Boolean).join(' / ');
    parts.push(_copy('summaryStatus', { type, status }));
    if (category) parts.push(_copy('summaryWithin', { category }));
    if (cityLabel && cityLabel !== _copy('unavailable')) parts.push(_copy('summaryIn', { city: cityLabel }));
    return parts.join(' • ');
  }

  function clientInitials(name) {
    const parts = str(name).split(/\s+/).filter(Boolean);
    if (!parts.length) return '--';
    return parts.slice(0, 2).map((part) => part.charAt(0)).join('').toUpperCase();
  }

  function activeMode() {
    try {
      const raw = window.localStorage.getItem('activeMode') || window.localStorage.getItem('account_mode') || '';
      const mode = String(raw || '').trim().toLowerCase();
      if (mode === 'provider' || mode === 'client') return mode;
    } catch (_) {}

    try {
      const parsed = new URL(window.location.href);
      const mode = String(parsed.searchParams.get('mode') || '').trim().toLowerCase();
      if (mode === 'provider' || mode === 'client') return mode;
    } catch (_) {}

    const role = (Auth.getRoleState() || '').trim().toLowerCase();
    return role === 'provider' ? 'provider' : 'client';
  }

  function withMode(path) {
    const mode = activeMode();
    const sep = path.includes('?') ? '&' : '?';
    return path + sep + 'mode=' + encodeURIComponent(mode);
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
    if (group === 'in_progress') return _copy('statusInProgress');
    if (group === 'completed') return _copy('statusCompleted');
    if (group === 'cancelled') return _copy('statusCancelled');
    return _copy('statusNew');
  }

  function statusLabelFromRaw(raw) {
    const key = str(raw).toLowerCase();
    return STATUS_COPY_KEYS[key] ? _copy(STATUS_COPY_KEYS[key]) : val(raw, '—');
  }

  function statusGroupFromRaw(raw) {
    const key = str(raw).toLowerCase();
    if (key === 'in_progress') return 'in_progress';
    if (key === 'completed') return 'completed';
    if (key === 'cancelled' || key === 'canceled') return 'cancelled';
    return 'new';
  }

  function resolveCompletionMoment(order) {
    const logs = Array.isArray(order && order.status_logs) ? order.status_logs : [];
    let marker = null;
    logs.forEach((log) => {
      if (str(log && log.to_status).toLowerCase() !== 'completed') return;
      const created = asDate(log && log.created_at);
      if (!created) return;
      if (!marker || created.getTime() > marker.getTime()) marker = created;
    });
    if (marker) return marker;
    return asDate(order && order.delivered_at);
  }

  function isProviderAttachment(attachment, completionMoment, order) {
    const created = asDate(attachment && attachment.created_at);
    if (!created) return false;
    if (completionMoment) {
      return created.getTime() >= (completionMoment.getTime() - 120000);
    }
    const deliveredAt = asDate(order && order.delivered_at);
    if (!deliveredAt) return false;
    return created.getTime() >= deliveredAt.getTime();
  }

  function fileTypeCode(type) {
    if (type === 'image') return 'IMG';
    if (type === 'video') return 'VID';
    if (type === 'audio') return 'AUD';
    return 'DOC';
  }

  function fileTypeLabel(type) {
    return FILE_TYPE_COPY_KEYS[type] ? _copy(FILE_TYPE_COPY_KEYS[type]) : _copy('file');
  }

  function attachmentName(path, attachment) {
    if (!path) return val(attachment && attachment.original_name, _copy('file'));
    const cleanPath = String(path).split('?')[0].split('#')[0];
    const name = cleanPath.split('/').pop() || '';
    try {
      return decodeURIComponent(name) || _copy('file');
    } catch (_) {
      return name || _copy('file');
    }
  }

  function toMs(v) {
    const d = asDate(v);
    return d ? d.getTime() : 0;
  }

  function requestType(o) {
    return str(o && o.request_type).toLowerCase();
  }

  function workflowStage(o) {
    return str(o && o.status).toLowerCase();
  }

  function providerInputsStage(o) {
    const stage = str(o && o.provider_inputs_stage).toLowerCase();
    if (stage === 'progress_update') return 'progress_update';
    if (stage === 'pre_execution') return 'pre_execution';
    return '';
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

  function isAwaitingProviderAcceptance(o) {
    return requestType(o) === 'normal' && hasAssignedProvider(o) && workflowStage(o) === 'new';
  }

  function canSendExecutionDetails(o) {
    const stage = workflowStage(o);
    if (stage === 'provider_accepted' || stage === 'awaiting_client') return true;
    return isCompetitiveAssigned(o) && stage === 'new';
  }

  function fmtDateTime(v) {
    const d = asDate(v);
    if (!d) return '-';
    return localizeDigits(pad(d.getHours()) + ':' + pad(d.getMinutes()) + '  ' + pad(d.getDate()) + '/' + pad(d.getMonth() + 1) + '/' + d.getFullYear());
  }

  function fmtDateOnly(v) {
    const d = asDate(v);
    if (!d) return '-';
    return localizeDigits(pad(d.getDate()) + '/' + pad(d.getMonth() + 1) + '/' + d.getFullYear());
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

  function currentLang() {
    if (window.NawafethI18n && typeof window.NawafethI18n.getLanguage === 'function') {
      return window.NawafethI18n.getLanguage() === 'en' ? 'en' : 'ar';
    }

    return document.documentElement.lang === 'en' ? 'en' : 'ar';
  }

  function _copy(key, replacements) {
    const lang = currentLang();
    let text = (COPY[lang] && COPY[lang][key]) || COPY.ar[key] || '';

    if (!replacements || typeof replacements !== 'object') return text;

    return text.replace(/\{(\w+)\}/g, (_, token) => {
      return Object.prototype.hasOwnProperty.call(replacements, token)
        ? String(replacements[token])
        : '';
    });
  }

  function typeLabel(type) {
    const key = TYPE_COPY_KEYS[type] || 'requestTypeDefault';
    return _copy(key);
  }

  function localizeSystemLogNote(note) {
    const raw = str(note);
    if (!raw) return '';

    if (SYSTEM_LOG_NOTE_COPY_KEYS[raw]) {
      return _copy(SYSTEM_LOG_NOTE_COPY_KEYS[raw]);
    }

    const matchedClientApproval = raw.match(/^العميل وافق على (مدخلات المزود|تحديث التقدم):\s*(.+)$/);
    if (matchedClientApproval) {
      return _copy(
        matchedClientApproval[1] === 'تحديث التقدم'
          ? 'logNoteClientApprovedProgressWithNote'
          : 'logNoteClientApprovedInputsWithNote',
        { note: matchedClientApproval[2] }
      );
    }

    const matchedClientReject = raw.match(/^العميل رفض (مدخلات المزود|تحديث التقدم):\s*(.+)$/);
    if (matchedClientReject) {
      return _copy(
        matchedClientReject[1] === 'تحديث التقدم'
          ? 'logNoteClientRejectedProgressWithNote'
          : 'logNoteClientRejectedInputsWithNote',
        { note: matchedClientReject[2] }
      );
    }

    const matchedUrgentDecline = raw.match(/^اعتذار مزود الخدمة عن الطلب العاجل:\s*(.+)$/);
    if (matchedUrgentDecline) {
      return _copy('logNoteProviderUrgentDeclinedPrefix', { reason: matchedUrgentDecline[1] });
    }

    const matchedProviderCancel = raw.match(/^إلغاء من المزود:\s*(.+)$/);
    if (matchedProviderCancel) {
      return _copy('logNoteProviderCancelledPrefix', { reason: matchedProviderCancel[1] });
    }

    const matchedProviderCancelInProgress = raw.match(/^إلغاء من مزود الخدمة أثناء التنفيذ:\s*(.+)$/);
    if (matchedProviderCancelInProgress) {
      return _copy('logNoteProviderCancelledDuringExecutionPrefix', { reason: matchedProviderCancelInProgress[1] });
    }

    return raw;
  }

  function localizedCategoryName(order) {
    if (currentLang() === 'en') return val(order && order.category_name_en, str(order && order.category_name));
    return str(order && order.category_name);
  }

  function localizedSubcategoryName(order) {
    if (currentLang() === 'en') return val(order && order.subcategory_name_en, str(order && order.subcategory_name));
    return str(order && order.subcategory_name);
  }

  function localizedRequestCity(order) {
    if (currentLang() === 'en') {
      return val(str(order && order.city_display_en), str(order && order.city_display) || str(order && order.city));
    }
    return val(UI.formatCityDisplay(order && (order.city_display || order.city), order && (order.region || order.region_name)), '');
  }

  function localizedClientCity(order, fallbackCity) {
    if (currentLang() === 'en') {
      return val(str(order && order.client_city_display_en), str(order && order.client_city_display) || str(order && order.client_city) || fallbackCity);
    }
    return UI.formatCityDisplay(order && (order.client_city_display || order.client_city || fallbackCity));
  }

  function localizeDigits(v) {
    const raw = String(v);
    if (currentLang() === 'en') return raw;
    return raw.replace(/\d/g, (d) => '٠١٢٣٤٥٦٧٨٩'[Number(d)]);
  }

  function containsArabicScript(value) {
    return /[\u0600-\u06FF]/.test(str(value));
  }

  function hasOriginalLanguageContent(order) {
    if (!order || currentLang() !== 'en') return false;
    const directFields = [
      order.title,
      order.description,
      order.client_name,
      order.provider_inputs_decision_note,
      order.review_comment,
      order.cancel_reason,
    ];
    if (directFields.some(containsArabicScript)) return true;
    return (order.status_logs || []).some((log) => {
      if (containsArabicScript(log && log.actor_name)) return true;
      const rawNote = str(log && log.note);
      if (!rawNote || localizeSystemLogNote(rawNote) !== rawNote) return false;
      return containsArabicScript(rawNote);
    });
  }

  function updateOriginalLanguageNotice(order) {
    const el = byId('pod-original-language-note');
    if (!el) return;
    el.textContent = _copy('originalLanguageNotice');
    el.style.display = hasOriginalLanguageContent(order) ? '' : 'none';
  }

  function pad(n) { return String(n).padStart(2, '0'); }
  function str(v) { return v === null || v === undefined ? '' : String(v).trim(); }
  function val(v, f) { const s = str(v); return s || f; }
  function setText(id, value) { const el = byId(id); if (el) el.textContent = value; }
  function setAutoDirection(el, value) {
    if (!el) return;
    if (str(value)) el.setAttribute('dir', 'auto');
    else el.removeAttribute('dir');
  }
  function setTextAutoDirection(id, value) {
    const el = byId(id);
    if (!el) return;
    el.textContent = value;
    setAutoDirection(el, value);
  }
  function byId(id) { return document.getElementById(id); }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
  return { init };
})();
