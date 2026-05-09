/* ===================================================================
   providerDetailPage.js — Provider public profile detail (redesigned)
   Mirrors the Flutter ProviderProfileScreen layout.
   =================================================================== */
'use strict';

const ProviderDetailPage = (() => {
  const COPY = {
    ar: {
      providerNotFound: 'مقدم الخدمة غير موجود',
      tabMetaProfile: 'أساسي',
      back: 'رجوع',
      save: 'حفظ',
      share: 'مشاركة',
      blueVerification: 'توثيق أزرق',
      greenVerification: 'توثيق أخضر',
      excellenceBadgesTitle: 'شارات التميز',
      excellenceBadgesHint: 'شارات توضح إنجازات وتقدير مقدم الخدمة داخل المنصة.',
      return: 'العودة',
      returnToMap: 'العودة إلى الخريطة',
      requestService: 'طلب الخدمة',
      follow: 'متابعة',
      unfollow: 'إلغاء المتابعة',
      message: 'مراسلة',
      call: 'اتصال',
      whatsapp: 'واتساب',
      providerFallback: 'مقدم خدمة',
      unavailable: 'غير متوفر',
      noDescription: 'لا يوجد وصف',
      bioTitle: 'نبذة عن مقدم الخدمة',
      additionalInfoTitle: 'معلومات إضافية',
      additionalDetailsLabel: 'شرح تفصيلي',
      qualificationsLabel: 'المؤهلات',
      experiencesLabel: 'الخبرات العملية',
      overview: 'ملخص مقدم الخدمة',
      city: 'المدينة',
      experience: 'الخبرة',
      serviceRange: 'نطاق الخدمة',
      completedRequests: 'الطلبات المكتملة',
      followers: 'متابعون',
      likes: 'إعجاب',
      rating: 'التقييم',
      followLinks: 'روابط المتابعة',
      showFollowers: 'عرض من يتابعون مقدم الخدمة',
      showFollowing: 'عرض من يتابعهم مقدم الخدمة',
      followersLabel: 'المتابعون',
      followingLabel: 'المتابعين',
      viewList: 'عرض القائمة',
      highlightsTitle: 'لمحات مقدم الخدمة',
      swipeHint: 'اسحب يمين/يسار',
      tabsAria: 'تبويبات ملف مقدم الخدمة',
      profileTab: 'الملف الشخصي',
      servicesTab: 'خدماتي',
      portfolioTab: 'معرض خدماتي',
      reviewsTab: 'المراجعات',
      accountType: 'صفة الحساب',
      mainServiceCategory: 'التصنيف الرئيسي للخدمات المقدمة',
      specialization: 'التخـصص',
      yearsExperience: 'سنوات الخبرة',
      whatsappNumber: 'رقم الواتساب',
      website: 'الموقع الالكتروني',
      openWebsite: 'فتح الموقع الإلكتروني',
      mapTitle: 'نطاق الخدمة على الخريطة',
      mapPending: 'سيظهر نطاق الخدمة بعد تحميل بيانات مقدم الخدمة.',
      mapAria: 'خريطة نطاق خدمة مقدم الخدمة',
      mapNoExactLocation: 'لم يحدد مقدم الخدمة موقعًا دقيقًا على الخريطة بعد.',
      socialAccounts: 'حسابات التواصل الاجتماعي',
      linkedinAccount: 'حساب لينكدإن',
      facebookAccount: 'حساب فيس بوك',
      youtubeAccount: 'قناة يوتيوب',
      instagramAccount: 'حساب انستقرام',
      xAccount: 'حساب X',
      snapchatAccount: 'حساب سناب شات',
      pinterestAccount: 'حساب بنترست',
      tiktokAccount: 'حساب تيك توك',
      behanceAccount: 'حساب بيهانس',
      emailContact: 'البريد الإلكتروني',
      openLink: 'فتح الرابط',
      sendEmail: 'إرسال بريد إلكتروني',
      openInstagram: 'فتح حساب انستقرام',
      openX: 'فتح حساب X',
      openSnapchat: 'فتح حساب سناب شات',
      servicesBadge: 'خدمات المزود',
      servicesHeroTitle: 'خدمات مرتبة وواضحة قبل بدء التواصل',
      servicesHeroSubtitle: 'راجع ما يقدمه المزوّد، نطاق التسعير، ووصف كل خدمة قبل الانتقال إلى الرسائل أو طلب التنفيذ.',
      servicesEmptyTitle: 'لا توجد خدمات متاحة حالياً',
      servicesEmptySubtitle: 'لم يضف مقدم الخدمة خدمات في هذا القسم بعد.',
      portfolioBadge: 'معرض خدماتي',
      portfolioHeroTitle: 'استعراض عمودي سريع بنفس روح المشاهد القصيرة',
      portfolioHeroSubtitle: 'افتح أي بطاقة لمشاهدة الصور والفيديوهات بواجهة كاملة، مع بقاء الإعجاب والحفظ ظاهرين مباشرة على كل عنصر.',
      portfolioEmptyTitle: 'لا توجد عناصر في معرض الأعمال',
      portfolioEmptySubtitle: 'المعرض فارغ حالياً. عند إضافة محتوى من حساب مقدم الخدمة سيظهر هنا.',
      portfolioItemsCount: '{count} عنصر',
      portfolioSectionsCount: '{count} قسم',
      reviewsEmpty: 'لا توجد تقييمات بعد',
      ratingCriteriaTitle: 'بنود التقييم',
      ratingDistributionTitle: 'توزيع التقييمات',
      ratingStarsLabel: '{count} نجوم',
      ratingBarMeta: '{count} تقييم • {percent}%',
      reviewResponseSpeed: 'سرعة الاستجابة',
      reviewResponseSpeedHint: 'سرعة الرد على استفسارات العميل',
      reviewCostValue: 'القيمة مقابل السعر',
      reviewCostValueHint: 'مدى مناسبة السعر مقابل الخدمة',
      reviewQuality: 'جودة العمل',
      reviewQualityHint: 'جودة التنفيذ أو النتيجة النهائية',
      reviewCredibility: 'المصداقية',
      reviewCredibilityHint: 'الوضوح والموثوقية في التعامل',
      reviewOnTime: 'الالتزام بالمواعيد',
      reviewOnTimeHint: 'الالتزام بالوقت المتفق عليه',
      reviewerContactHint: 'انقر لمراسلة صاحب هذا التقييم',
      reviewerChatOwnerOnly: 'سجّل الدخول لمراسلة صاحب هذا التقييم',
      reviewerConversationAria: 'مراسلة {name}',
      criterionExcellent: 'ممتاز جدًا',
      criterionStrong: 'قوي',
      criterionGood: 'جيد',
      criterionNeedsSupport: 'يحتاج دعم',
      criterionNoData: 'بدون بيانات',
      close: 'إغلاق',
      copyLink: 'نسخ الرابط',
      linkCopied: 'تم نسخ الرابط',
      linkCopyFailed: 'تعذر نسخ الرابط',
      linkShared: 'تمت مشاركة الرابط',
      shareLinkFailed: 'تعذر مشاركة الرابط',
      shareProviderWindow: 'مشاركة نافذة مقدم الخدمة',
      reportProvider: 'الإبلاغ عن مقدم الخدمة',
      reportProviderDialog: 'إبلاغ عن مزود خدمة',
      reportInfo: 'بيانات المبلغ عنه:',
      reportTypeProvider: 'نوع البلاغ: مزود خدمة',
      reportReason: 'سبب الإبلاغ:',
      reportDetails: 'تفاصيل إضافية (اختياري):',
      reportDetailsPlaceholder: 'اكتب التفاصيل هنا...',
      cancel: 'إلغاء',
      submitReport: 'إرسال البلاغ',
      submitReportPending: 'جارٍ إرسال البلاغ...',
      reportSent: 'تم إرسال البلاغ للإدارة. شكراً لك',
      reportSendFailed: 'تعذر إرسال البلاغ حالياً',
      reportReasonInappropriate: 'محتوى غير لائق',
      reportReasonHarassment: 'تحرش أو إزعاج',
      reportReasonFraud: 'احتيال أو نصب',
      reportReasonAbusive: 'محتوى مسيء',
      reportReasonPrivacy: 'انتهاك الخصوصية',
      reportReasonOther: 'أخرى',
      qrAlt: 'رمز QR',
      whatsappIntro: 'السلام عليكم\nأتواصل معك بخصوص خدماتك في منصة نوافذ @{name}',
      cannotChatYourself: 'لا يمكنك محادثة نفسك',
      invalidProviderId: 'تعذر فتح الرسائل: معرف المزود غير صالح',
      openMessagesFailed: 'تعذر فتح الرسائل حالياً',
      mapLoadFailedSummary: 'تعذر عرض نطاق الخدمة على الخريطة حالياً.',
      mapLoadFailed: 'تعذر عرض الخريطة حالياً.',
      loadListFailed: 'تعذر تحميل القائمة',
      noFollowersYet: 'لا يوجد متابعون بعد',
      noFollowingYet: 'لا يوجد متابَعون بعد',
      searchByName: 'ابحث بالاسم أو المعرّف…',
      searchList: 'ابحث في القائمة',
      user: 'مستخدم',
      openProfile: 'فتح ملف {name}',
      notProviderShort: '{name} — ليس مزود خدمة',
      blueBadgeVerified: 'موثق بالشارة الزرقاء',
      greenBadgeVerified: 'موثق بالشارة الخضراء',
      provider: 'مزود خدمة',
      client: 'عميل',
      noMatchingResults: 'لا توجد نتائج مطابقة',
      notProviderTitle: 'هذا الحساب ليس مزود خدمة',
      notProviderMessage: 'هذا الحساب مسجّل كعميل في منصة نوافذ ولا يملك ملفًا عامًا لمقدم خدمة، لذلك لا يمكن فتح صفحته.',
      understood: 'حسناً، فهمت',
      cover: 'غلاف',
      experienceYearsValue: '{count} سنوات',
      serviceRangeKm: '{count} كم',
      followersSheetTitle: 'المتابعون',
      followingSheetTitle: 'المتابعين',
      followersSheetSubtitle: 'الذين يتابعون مقدم الخدمة',
      followingSheetSubtitle: 'الذين يتابعهم مقدم الخدمة',
      highlightSection: 'لمحات',
      highlightFallback: 'لمحة',
      reelFallback: 'ريل',
      serviceWithoutName: 'خدمة بدون اسم',
      publishedService: 'خدمة منشورة',
      selectedService: 'خدمة يقدّمها المزود',
      pricing: 'التسعير',
      requestServiceCard: 'طلب الخدمة',
      serviceMainCategoryLabel: 'التصنيف الرئيسي',
      serviceScopeLabel: 'نطاق التنفيذ',
      serviceCommunicationHint: 'للتفاهم حول هذه الخدمة استخدم أزرار المتابعة والتواصل أعلى الصفحة.',
      serviceConfiguredHint: 'هذه الخدمة ظاهرة من إعدادات ملف المزود حتى لو لم يضف بطاقة خدمة مفصلة بعد.',
      servicePriceNegotiable: 'السعر: حسب الاتفاق',
      servicePriceSingle: 'السعر: {value}{suffix}',
      servicePriceRange: 'السعر: {from} - {to}{suffix}',
      serviceUnitFixed: 'سعر ثابت',
      serviceUnitStarting: 'يبدأ من',
      serviceUnitHour: 'بالساعة',
      serviceUnitDay: 'باليوم',
      serviceUnitNegotiable: 'قابل للتفاوض',
      serviceUrgentEnabled: 'تدعم الطلبات العاجلة',
      serviceGeoScoped: 'ضمن النطاق المكاني',
      serviceRemoteAvailable: 'عن بعد',
      serviceRequestHint: 'الانتقال مباشرة إلى نموذج طلب الخدمة',
      servicesCountZero: '0 خدمة',
      servicesCountOne: 'خدمة واحدة',
      servicesCountTwo: 'خدمتان',
      servicesCountFew: '{count} خدمات',
      servicesCountMany: '{count} خدمة',
      worksSection: 'أعمالي',
      noDescriptionGeneric: 'بدون وصف',
      portfolioItemFallback: 'عنصر من المعرض',
      videoShort: 'فيديو قصير',
      image: 'صورة',
      watchVertical: 'شاهد العرض العمودي',
      browseWork: 'استعرض العمل',
      openFullscreen: 'فتح بملء الشاشة',
      like: 'إعجاب',
      saveToFavorites: 'حفظ في المفضلة',
      scrollHorizontally: 'مرر أفقياً وافتح أي بطاقة',
      noItemsInSection: 'لا توجد عناصر في هذا القسم حالياً',
      noItemsInSectionSubtitle: 'سيظهر المحتوى هنا عند إضافته من ملف مقدم الخدمة.',
      videoFromGallery: 'فيديو من المعرض',
      likeSavedAs: 'تم تسجيل الإعجاب بصفتك {mode}',
      unlikeSavedAs: 'تم إلغاء الإعجاب بصفتك {mode}',
      savedAsFavorite: 'تم الحفظ في المفضلة بصفتك {mode}',
      removedFromFavorites: 'تمت إزالة العنصر من المفضلة بصفتك {mode}',
      likeUpdateFailed: 'تعذر تحديث الإعجاب',
      saveUpdateFailed: 'تعذر تحديث الحفظ',
      profileSavedAria: 'فتح مفضلتي',
      profileUnsavedAria: 'الانتقال إلى المعرض للحفظ',
      profileSavedTitle: 'فتح مفضلتي',
      profileUnsavedTitle: 'احفظ من المعرض أو اللمحات',
      saveFromGalleryHint: 'اضغط حفظ على أي صورة أو فيديو لإضافته إلى مفضلتك',
      anonymousReviewer: 'مستخدم',
      providerReply: 'رد مقدم الخدمة',
      ratingsCount: '{count} تقييم',
      providerMode: 'مزود',
      clientMode: 'عميل',
      serviceCoverageAroundCity: 'تغطية تصل إلى {range} كم حول {city}.',
      serviceCoverageAroundProvider: 'تغطية تصل إلى {range} كم حول موقع مقدم الخدمة.',
      serviceCoverageInCity: 'النطاق المحدد {range} كم داخل مدينة {city} دون نقطة خريطة دقيقة.',
      noGeoPointAvailable: 'لا تتوفر إحداثيات دقيقة لعرض نطاق الخدمة على الخريطة حالياً.',
      mapFailedNow: 'تعذر تحميل الخريطة حالياً.',
      seoProviderDescription: 'تعرف على خدمات {name} عبر منصة نوافــذ.',
      seoPlatformDescription: 'منصة نوافــذ للخدمات الرقمية والمهنية.',
    },
    en: {
      providerNotFound: 'Provider not found',
      tabMetaProfile: 'Basic',
      back: 'Back',
      save: 'Save',
      share: 'Share',
      blueVerification: 'Blue verification',
      greenVerification: 'Green verification',
      excellenceBadgesTitle: 'Excellence badges',
      excellenceBadgesHint: 'Badges that highlight the provider\'s achievements and recognition on the platform.',
      return: 'Return',
      returnToMap: 'Back to map',
      requestService: 'Request service',
      follow: 'Follow',
      unfollow: 'Unfollow',
      message: 'Message',
      call: 'Call',
      whatsapp: 'WhatsApp',
      providerFallback: 'Provider',
      unavailable: 'Unavailable',
      noDescription: 'No description available',
      bioTitle: 'About the provider',
      additionalInfoTitle: 'Additional information',
      additionalDetailsLabel: 'Detailed description',
      qualificationsLabel: 'Qualifications',
      experiencesLabel: 'Work experience',
      overview: 'Provider overview',
      city: 'City',
      experience: 'Experience',
      serviceRange: 'Service range',
      completedRequests: 'Completed requests',
      followers: 'Followers',
      likes: 'Likes',
      rating: 'Rating',
      followLinks: 'Follow links',
      showFollowers: 'Show who follows this provider',
      showFollowing: 'Show who this provider follows',
      followersLabel: 'Followers',
      followingLabel: 'Following',
      viewList: 'View list',
      highlightsTitle: 'Provider highlights',
      swipeHint: 'Swipe left or right',
      tabsAria: 'Provider profile tabs',
      profileTab: 'Profile',
      servicesTab: 'Services',
      portfolioTab: 'Portfolio',
      reviewsTab: 'Reviews',
      accountType: 'Account type',
      mainServiceCategory: 'Main service category',
      specialization: 'Specialization',
      yearsExperience: 'Years of experience',
      whatsappNumber: 'WhatsApp number',
      website: 'Website',
      openWebsite: 'Open website',
      mapTitle: 'Service range on the map',
      mapPending: 'The service range will appear after the provider data loads.',
      mapAria: 'Provider service range map',
      mapNoExactLocation: 'The provider has not set an exact location on the map yet.',
      socialAccounts: 'Social accounts',
      linkedinAccount: 'LinkedIn account',
      facebookAccount: 'Facebook account',
      youtubeAccount: 'YouTube channel',
      instagramAccount: 'Instagram account',
      xAccount: 'X account',
      snapchatAccount: 'Snapchat account',
      pinterestAccount: 'Pinterest account',
      tiktokAccount: 'TikTok account',
      behanceAccount: 'Behance account',
      emailContact: 'Email address',
      openLink: 'Open link',
      sendEmail: 'Send email',
      openInstagram: 'Open Instagram account',
      openX: 'Open X account',
      openSnapchat: 'Open Snapchat account',
      servicesBadge: 'Provider services',
      servicesHeroTitle: 'Clear, organized services before you start the conversation',
      servicesHeroSubtitle: 'Review what the provider offers, the pricing range, and each service description before moving to messages or placing a request.',
      servicesEmptyTitle: 'No services are available right now',
      servicesEmptySubtitle: 'The provider has not added services in this section yet.',
      portfolioBadge: 'Portfolio',
      portfolioHeroTitle: 'A fast vertical showcase with the feel of short-form viewing',
      portfolioHeroSubtitle: 'Open any card to view photos and videos in a full-screen experience while likes and saves remain visible on every item.',
      portfolioEmptyTitle: 'There are no portfolio items',
      portfolioEmptySubtitle: 'The portfolio is empty right now. Content added from the provider account will appear here.',
      portfolioItemsCount: '{count} items',
      portfolioSectionsCount: '{count} sections',
      reviewsEmpty: 'There are no reviews yet',
      ratingCriteriaTitle: 'Rating items',
      ratingDistributionTitle: 'Rating distribution',
      ratingStarsLabel: '{count} stars',
      ratingBarMeta: '{count} reviews • {percent}%',
      reviewResponseSpeed: 'Response speed',
      reviewResponseSpeedHint: 'How quickly the provider responded to the client',
      reviewCostValue: 'Value for money',
      reviewCostValueHint: 'How fair the price felt for the service delivered',
      reviewQuality: 'Work quality',
      reviewQualityHint: 'Quality of execution or final outcome',
      reviewCredibility: 'Credibility',
      reviewCredibilityHint: 'Clarity and trustworthiness during the service',
      reviewOnTime: 'On-time delivery',
      reviewOnTimeHint: 'Commitment to the agreed timeline',
      reviewerContactHint: 'Tap to message this reviewer',
      reviewerChatOwnerOnly: 'Sign in to message this reviewer',
      reviewerConversationAria: 'Message {name}',
      criterionExcellent: 'Excellent',
      criterionStrong: 'Strong',
      criterionGood: 'Good',
      criterionNeedsSupport: 'Needs support',
      criterionNoData: 'No data',
      close: 'Close',
      copyLink: 'Copy link',
      linkCopied: 'Link copied',
      linkCopyFailed: 'Unable to copy the link',
      linkShared: 'The link was shared',
      shareLinkFailed: 'Unable to share the link',
      shareProviderWindow: 'Share the provider page',
      reportProvider: 'Report the provider',
      reportProviderDialog: 'Report a provider',
      reportInfo: 'Reported account details:',
      reportTypeProvider: 'Report type: provider',
      reportReason: 'Reason for the report:',
      reportDetails: 'Additional details (optional):',
      reportDetailsPlaceholder: 'Write the details here...',
      cancel: 'Cancel',
      submitReport: 'Send report',
      submitReportPending: 'Sending...',
      reportSent: 'The report was sent to the team. Thank you.',
      reportSendFailed: 'Unable to send the report right now',
      reportReasonInappropriate: 'Inappropriate content',
      reportReasonHarassment: 'Harassment or nuisance',
      reportReasonFraud: 'Fraud or scam',
      reportReasonAbusive: 'Abusive content',
      reportReasonPrivacy: 'Privacy violation',
      reportReasonOther: 'Other',
      qrAlt: 'QR code',
      whatsappIntro: 'Hello, I am contacting you about your services on Nawafeth @{name}',
      cannotChatYourself: 'You cannot chat with yourself',
      invalidProviderId: 'Unable to open messages: invalid provider ID',
      openMessagesFailed: 'Unable to open messages right now',
      mapLoadFailedSummary: 'Unable to show the service range on the map right now.',
      mapLoadFailed: 'Unable to show the map right now.',
      loadListFailed: 'Unable to load the list',
      noFollowersYet: 'There are no followers yet',
      noFollowingYet: 'There is no following list yet',
      searchByName: 'Search by name or handle…',
      searchList: 'Search the list',
      user: 'User',
      openProfile: 'Open profile {name}',
      notProviderShort: '{name} — not a provider',
      blueBadgeVerified: 'Verified with the blue badge',
      greenBadgeVerified: 'Verified with the green badge',
      provider: 'Provider',
      client: 'Client',
      noMatchingResults: 'No matching results',
      notProviderTitle: 'This account is not a provider',
      notProviderMessage: 'This account is registered as a client on Nawafeth and does not have a public provider profile, so its page cannot be opened.',
      understood: 'OK, understood',
      cover: 'Cover',
      experienceYearsValue: '{count} years',
      serviceRangeKm: '{count} km',
      followersSheetTitle: 'Followers',
      followingSheetTitle: 'Following',
      followersSheetSubtitle: 'People following this provider',
      followingSheetSubtitle: 'People this provider follows',
      highlightSection: 'Highlights',
      highlightFallback: 'Highlight',
      reelFallback: 'Reel',
      serviceWithoutName: 'Untitled service',
      publishedService: 'Published service',
      selectedService: 'Configured service',
      pricing: 'Pricing',
      requestServiceCard: 'Request service',
      serviceMainCategoryLabel: 'Main category',
      serviceScopeLabel: 'Delivery scope',
      serviceCommunicationHint: 'To discuss this service, use the follow and contact actions at the top of the page.',
      serviceConfiguredHint: 'This service is shown from the provider profile settings even if no detailed service card has been added yet.',
      servicePriceNegotiable: 'Price: by agreement',
      servicePriceSingle: 'Price: {value}{suffix}',
      servicePriceRange: 'Price: {from} - {to}{suffix}',
      serviceUnitFixed: 'Fixed price',
      serviceUnitStarting: 'Starting from',
      serviceUnitHour: 'Per hour',
      serviceUnitDay: 'Per day',
      serviceUnitNegotiable: 'Negotiable',
      serviceUrgentEnabled: 'Urgent requests enabled',
      serviceGeoScoped: 'Within service area',
      serviceRemoteAvailable: 'Remote service',
      serviceRequestHint: 'Open the service request form directly',
      servicesCountZero: '0 services',
      servicesCountOne: '1 service',
      servicesCountTwo: '2 services',
      servicesCountFew: '{count} services',
      servicesCountMany: '{count} services',
      worksSection: 'My work',
      noDescriptionGeneric: 'No description',
      portfolioItemFallback: 'Portfolio item',
      videoShort: 'Short video',
      image: 'Image',
      watchVertical: 'Watch vertically',
      browseWork: 'Browse the work',
      openFullscreen: 'Open full screen',
      like: 'Like',
      saveToFavorites: 'Save to favorites',
      scrollHorizontally: 'Scroll horizontally and open any card',
      noItemsInSection: 'There are no items in this section right now',
      noItemsInSectionSubtitle: 'Content will appear here when it is added from the provider profile.',
      videoFromGallery: 'Gallery video',
      likeSavedAs: 'Like recorded as {mode}',
      unlikeSavedAs: 'Like removed as {mode}',
      savedAsFavorite: 'Saved to favorites as {mode}',
      removedFromFavorites: 'Removed from favorites as {mode}',
      likeUpdateFailed: 'Unable to update the like',
      saveUpdateFailed: 'Unable to update the save',
      profileSavedAria: 'Open my favorites',
      profileUnsavedAria: 'Go to the gallery to save',
      profileSavedTitle: 'Open my favorites',
      profileUnsavedTitle: 'Save something from the gallery or highlights',
      saveFromGalleryHint: 'Tap save on any image or video to add it to your favorites',
      anonymousReviewer: 'User',
      providerReply: 'Provider reply',
      ratingsCount: '{count} ratings',
      providerMode: 'provider',
      clientMode: 'client',
      serviceCoverageAroundCity: 'Coverage reaches up to {range} km around {city}.',
      serviceCoverageAroundProvider: 'Coverage reaches up to {range} km around the provider location.',
      serviceCoverageInCity: 'The configured range is {range} km inside {city} without an exact map point.',
      noGeoPointAvailable: 'Exact coordinates are not available to show the service range on the map right now.',
      mapFailedNow: 'Unable to load the map right now.',
      seoProviderDescription: 'Discover the services of {name} on Nawafeth.',
      seoPlatformDescription: 'Nawafeth platform for digital and professional services.',
    },
  };

  let _providerId = null;
  let _mode = 'client';
  let _isFollowing = false;
  let _isBookmarked = false;
  let _activeTab = 'profile';
  let _providerData = null;
  let _providerPhone = '';
  let _providerWhatsappUrl = '';
  let _spotlights = [];
  let _portfolioItems = [];
  let _profileLikesBase = 0;
  let _portfolioLikes = 0;
  let _spotlightLikes = 0;
  let _portfolioSaves = 0;
  let _spotlightSaves = 0;
  let _portfolioSavedByMe = false;
  let _spotlightSavedByMe = false;
  let _mediaLikesTotal = null;
  let _spotlightSyncBound = false;
  let _portfolioSyncBound = false;
  let _portfolioPreviewObserver = null;
  let _derivedMainCategory = '';
  let _derivedSubCategory = '';
  let _returnNav = null;
  let _socialUrls = {
    instagram: '',
    x: '',
    snapchat: '',
  };
  let _currentProfile = null;
  let _isOwnProviderProfile = false;
  let _serviceRangeMap = null;
  let _serviceRangeLayer = null;
  let _coverGalleryIndex = 0;
  let _coverGalleryTimer = 0;

  function _activeMode() {
    if (typeof Auth !== 'undefined' && Auth && typeof Auth.getActiveAccountMode === 'function') {
      const mode = _trimText(Auth.getActiveAccountMode()).toLowerCase();
      if (mode === 'provider' || mode === 'client') return mode;
    }
    return _resolveMode();
  }

  function _syncMode(modeOverride) {
    const nextMode = (modeOverride === 'provider' || modeOverride === 'client') ? modeOverride : _activeMode();
    _mode = nextMode === 'provider' ? 'provider' : 'client';
    return _mode;
  }

  function init() {
    document.addEventListener('nawafeth:languagechange', _handleLanguageChange);
    window.addEventListener('nw:account-mode-changed', _handleAccountModeChange);
    window.addEventListener('pageshow', _handlePageShow);
    const match = window.location.pathname.match(/\/provider\/(\d+)(?:\/[^/?#]+)?\/?/);
    if (!match) {
      document.querySelector('.pd-page').textContent = '';
      const msg = UI.el('div', { className: 'pd-empty', style: { padding: '80px 20px' } });
      msg.appendChild(UI.el('div', { className: 'pd-empty-icon', textContent: '🔍' }));
      msg.appendChild(UI.el('p', { textContent: _copy('providerNotFound') }));
      document.querySelector('.pd-page').appendChild(msg);
      return;
    }
    _providerId = match[1];
    _syncMode();
    _returnNav = _resolveReturnNavigation();

    _bindTabs();
    _bindActions();
    _bindSpotlightSync();
    _bindPortfolioSync();
    _renderModeBadge();
    _syncDirectChatAvailability();
    _applyStaticCopy();
    _loadAll();
  }

  function _handleAccountModeChange(event) {
    const nextMode = event && event.detail && event.detail.mode;
    _syncMode(nextMode);
  }

  function _handlePageShow() {
    _syncMode();
  }

  async function _trackProviderShare(channel) {
    if (!_providerId || !window.ApiClient || typeof ApiClient.request !== 'function') return;
    try {
      await ApiClient.request('/api/providers/' + encodeURIComponent(String(_providerId)) + '/share/', {
        method: 'POST',
        body: {
          content_type: 'profile',
          channel: channel || 'other',
        },
      });
    } catch (_) {}
  }

  /* ── Tabs ── */
  function _bindTabs() {
    const tabsRoot = document.getElementById('pd-tabs');
    if (!tabsRoot) return;

    tabsRoot.addEventListener('click', e => {
      const btn = e.target.closest('.pd-tab');
      if (!btn || !tabsRoot.contains(btn)) return;
      const tabName = String(btn.dataset.tab || '').trim();
      if (!tabName) return;
      _setActiveTab(tabName, { scrollIntoView: true });
    });

    tabsRoot.addEventListener('keydown', e => {
      const currentBtn = e.target.closest('.pd-tab');
      if (!currentBtn || !tabsRoot.contains(currentBtn)) return;

      const tabs = _tabButtons();
      if (!tabs.length) return;
      const currentIndex = tabs.indexOf(currentBtn);
      if (currentIndex < 0) return;

      const dir = String(document.documentElement.getAttribute('dir') || 'ltr').toLowerCase();
      const forwardKey = dir === 'rtl' ? 'ArrowLeft' : 'ArrowRight';
      const backwardKey = dir === 'rtl' ? 'ArrowRight' : 'ArrowLeft';

      let targetIndex = -1;
      if (e.key === forwardKey) {
        targetIndex = (currentIndex + 1) % tabs.length;
      } else if (e.key === backwardKey) {
        targetIndex = (currentIndex - 1 + tabs.length) % tabs.length;
      } else if (e.key === 'Home') {
        targetIndex = 0;
      } else if (e.key === 'End') {
        targetIndex = tabs.length - 1;
      } else if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        _setActiveTab(String(currentBtn.dataset.tab || '').trim(), { focusTab: true, scrollIntoView: true });
        return;
      } else {
        return;
      }

      e.preventDefault();
      const targetBtn = tabs[targetIndex];
      if (!targetBtn) return;
      _setActiveTab(String(targetBtn.dataset.tab || '').trim(), { focusTab: true, scrollIntoView: true });
    });

    _setActiveTab(_activeTab || 'profile');
    _setTabMeta('profile', _copy('tabMetaProfile'));
    _setTabMeta('services', '...');
    _setTabMeta('portfolio', '...');
    _setTabMeta('reviews', '...');
  }

  function _tabButtons() {
    return Array.from(document.querySelectorAll('#pd-tabs .pd-tab'));
  }

  function _setActiveTab(nextTab, opts = {}) {
    const tabName = String(nextTab || '').trim();
    if (!tabName) return;

    const buttons = _tabButtons();
    const activeButton = buttons.find((btn) => String(btn.dataset.tab || '').trim() === tabName);
    if (!activeButton) return;

    _activeTab = tabName;
    buttons.forEach((btn) => {
      const isActive = btn === activeButton;
      btn.classList.toggle('active', isActive);
      btn.setAttribute('aria-selected', isActive ? 'true' : 'false');
      btn.setAttribute('tabindex', isActive ? '0' : '-1');
    });

    document.querySelectorAll('.pd-panel').forEach((panel) => {
      const isActive = panel.id === ('tab-' + tabName);
      panel.classList.toggle('active', isActive);
      if (isActive) {
        panel.removeAttribute('hidden');
      } else {
        panel.setAttribute('hidden', 'hidden');
      }
    });

    _syncPortfolioPreviewPlayback();
    if (_activeTab === 'profile') {
      _syncServiceRangeMapSize();
    }

    if (opts.scrollIntoView) {
      _ensureActiveTabVisible();
    }

    if (opts.focusTab && typeof activeButton.focus === 'function') {
      try {
        activeButton.focus({ preventScroll: true });
      } catch (_) {
        activeButton.focus();
      }
    }
  }

  function _ensureActiveTabVisible() {
    const tabsRoot = document.getElementById('pd-tabs');
    const active = document.querySelector('#pd-tabs .pd-tab.active');
    if (!tabsRoot || !active || !tabsRoot.contains(active)) return;

    const rootRect = tabsRoot.getBoundingClientRect();
    const activeRect = active.getBoundingClientRect();
    const activeCenter = activeRect.left + (activeRect.width / 2);
    const rootCenter = rootRect.left + (rootRect.width / 2);
    const delta = activeCenter - rootCenter;

    try {
      tabsRoot.scrollTo({
        left: tabsRoot.scrollLeft + delta,
        behavior: 'smooth',
      });
    } catch (_) {
      tabsRoot.scrollLeft += delta;
    }

    _resetPageHorizontalScroll();
  }

  function _resetPageHorizontalScroll() {
    if (window.scrollX === 0 && document.documentElement.scrollLeft === 0 && document.body.scrollLeft === 0) return;
    try {
      window.scrollTo({ left: 0, top: window.scrollY, behavior: 'auto' });
    } catch (_) {
      window.scrollTo(0, window.scrollY || document.documentElement.scrollTop || document.body.scrollTop || 0);
    }
    document.documentElement.scrollLeft = 0;
    document.body.scrollLeft = 0;
  }

  function _setTabMeta(tabName, value) {
    const el = document.getElementById('pd-tab-meta-' + tabName);
    if (!el) return;
    const text = String(value === null || value === undefined ? '' : value).trim();
    if (!text) {
      el.textContent = '';
      el.classList.add('hidden');
      return;
    }
    el.textContent = text;
    el.classList.remove('hidden');
  }

  function _formatTabCount(count) {
    return _safeInt(count).toLocaleString(_locale());
  }

  function _setInitialShellLoading(loading) {
    const loadingShell = document.getElementById('pd-loading-shell');
    const contentShell = document.getElementById('pd-content-shell');
    if (loadingShell) loadingShell.classList.toggle('hidden', !loading);
    if (contentShell) {
      contentShell.classList.toggle('hidden', !!loading);
      contentShell.setAttribute('aria-busy', loading ? 'true' : 'false');
    }
  }

  function _setTabLoadingState(sectionName, loading) {
    const loadingEl = document.getElementById('pd-' + sectionName + '-loading');
    if (loadingEl) loadingEl.classList.toggle('hidden', !loading);
  }

  /* ── Action buttons ── */
  function _bindActions() {
    const followBtn = document.getElementById('btn-follow');
    if (followBtn) {
      followBtn.addEventListener('click', _toggleFollow);
    }

    const requestBtn = document.getElementById('btn-request-service');
    if (requestBtn) {
      requestBtn.addEventListener('click', (event) => {
        if (_isOwnProviderProfile) {
          event.preventDefault();
          return;
        }
        requestBtn.href = _buildServiceRequestUrl();
      });
    }

    const followersBtn = document.getElementById('btn-show-followers');
    if (followersBtn) {
      followersBtn.addEventListener('click', () => _openConnectionsSheet('followers'));
    }

    const followingBtn = document.getElementById('btn-show-following');
    if (followingBtn) {
      followingBtn.addEventListener('click', () => _openConnectionsSheet('following'));
    }

    const backBtn = document.getElementById('btn-back');
    if (backBtn) {
      backBtn.addEventListener('click', () => {
        if (_returnNav && _returnNav.href) {
          window.location.href = _returnNav.href;
          return;
        }
        if (window.history.length > 1) {
          window.history.back();
          return;
        }
        const fallback = document.referrer && document.referrer.startsWith(window.location.origin)
          ? document.referrer
          : '/search/';
        window.location.href = fallback;
      });
    }

    const returnToMapBtn = document.getElementById('btn-back-to-map');
    if (returnToMapBtn) {
      if (_returnNav && _returnNav.href) {
        returnToMapBtn.href = _returnNav.href;
        returnToMapBtn.textContent = _returnNav.label || _copy('return');
        returnToMapBtn.setAttribute('aria-label', _returnNav.label || _copy('return'));
        returnToMapBtn.classList.remove('hidden');
      } else {
        returnToMapBtn.classList.add('hidden');
      }
    }

    // Message
    const msgBtn = document.getElementById('btn-message');
    if (msgBtn) msgBtn.addEventListener('click', _openDirectChat);

    // Call
    const callBtn = document.getElementById('btn-call');
    if (callBtn) callBtn.addEventListener('click', () => {
      if (_providerPhone) window.open('tel:' + _formatPhoneE164(_providerPhone));
    });

    // WhatsApp (header + profile tab)
    ['btn-whatsapp', 'pd-btn-whatsapp'].forEach(id => {
      const el = document.getElementById(id);
      if (el) el.addEventListener('click', e => {
        e.preventDefault();
        const name = _pickFirstText(_providerData?.display_name, _providerData?.displayName);
        const waUrl = _buildWhatsappChatUrl(
          _providerWhatsappUrl,
          _providerPhone,
          _copy('whatsappIntro', { name }),
        );
        if (!waUrl) return;
        window.open(waUrl, '_blank');
      });
    });

    // Profile tab quick actions
    const qCall = document.getElementById('pd-btn-call');
    if (qCall) qCall.addEventListener('click', e => {
      e.preventDefault();
      if (_providerPhone) window.open('tel:' + _formatPhoneE164(_providerPhone));
    });
    const qChat = document.getElementById('pd-btn-chat');
    if (qChat) qChat.addEventListener('click', e => {
      e.preventDefault();
      _openDirectChat();
    });

    // Bookmark
    const bookmarkBtn = document.getElementById('btn-bookmark');
    if (bookmarkBtn) {
      bookmarkBtn.addEventListener('click', _handleBookmarkAction);
    }

    // Share
    const shareBtn = document.getElementById('btn-share');
    if (shareBtn) shareBtn.addEventListener('click', _openShareAndReportSheet);
  }

  async function _openDirectChat() {
    if (!Auth.isLoggedIn()) {
      window.location.href = '/login/?next=' + encodeURIComponent(window.location.pathname);
      return;
    }

    await _syncDirectChatAvailability();
    if (_isOwnProviderProfile) {
      _showToast(_copy('cannotChatYourself'));
      return;
    }

    const providerId = _safeInt(_providerId);
    if (!providerId) {
      _showToast(_copy('invalidProviderId'));
      return;
    }

    const res = await ApiClient.request(_withMode('/api/messaging/direct/thread/'), {
      method: 'POST',
      body: { provider_id: providerId },
    });

    if (res.ok && res.data && res.data.id) {
      window.location.href = '/chat/' + res.data.id + '/';
      return;
    }

    _showToast((res.data && (res.data.detail || res.data.error)) || _copy('openMessagesFailed'));
  }

  async function _syncDirectChatAvailability() {
    _isOwnProviderProfile = false;
    if (!Auth.isLoggedIn()) {
      _applyDirectChatAvailability();
      return;
    }

    try {
      _currentProfile = await Auth.getProfile(false, 'provider');
    } catch (_) {
      _currentProfile = null;
    }

    const currentProviderId = _safeInt(
      _currentProfile && (_currentProfile.provider_profile_id || _currentProfile.provider_id)
    );
    _isOwnProviderProfile = !!currentProviderId && String(currentProviderId) === String(_providerId);
    _applyDirectChatAvailability();
  }

  function _applyDirectChatAvailability() {
    ['btn-message', 'pd-btn-chat'].forEach((id) => {
      const button = document.getElementById(id);
      if (!button) return;
      button.disabled = _isOwnProviderProfile;
      button.setAttribute('aria-disabled', _isOwnProviderProfile ? 'true' : 'false');
      button.classList.toggle('hidden', _isOwnProviderProfile);
    });

    const requestBtn = document.getElementById('btn-request-service');
    if (requestBtn) {
      requestBtn.classList.toggle('hidden', _isOwnProviderProfile);
      requestBtn.setAttribute('aria-disabled', _isOwnProviderProfile ? 'true' : 'false');
      requestBtn.href = _buildServiceRequestUrl();
    }

    const followBtn = document.getElementById('btn-follow');
    if (followBtn) {
      followBtn.classList.toggle('hidden', _isOwnProviderProfile);
      followBtn.setAttribute('aria-disabled', _isOwnProviderProfile ? 'true' : 'false');
    }
  }

  function _buildServiceRequestUrl() {
    const params = new URLSearchParams();
    params.set('provider_id', String(_providerId || ''));
    params.set('return_to', window.location.pathname + window.location.search);
    return '/service-request/?' + params.toString();
  }

  function _bindSpotlightSync() {
    if (_spotlightSyncBound) return;
    _spotlightSyncBound = true;
    window.addEventListener('nw:spotlight-engagement-update', (event) => {
      const detail = event?.detail || {};
      const providerId = _safeInt(detail.provider_id);
      if (!providerId || String(providerId) !== String(_providerId)) return;
      const itemId = _safeInt(detail.id);
      if (!itemId) return;

      const target = _spotlights.find((item) => _safeInt(item.id) === itemId);
      if (!target) return;

      const previousLikes = _safeInt(target.likes_count);
      const previousSaves = _safeInt(target.saves_count);

      target.likes_count = _safeInt(detail.likes_count);
      target.saves_count = _safeInt(detail.saves_count);
      target.comments_count = _safeInt(detail.comments_count);
      target.is_liked = _asBool(detail.is_liked);
      target.is_saved = _asBool(detail.is_saved);

      if (_mediaLikesTotal !== null) {
        _mediaLikesTotal = Math.max(0, _safeInt(_mediaLikesTotal) + (target.likes_count - previousLikes));
      }

      _syncSpotlightEngagementTotals();
      _updateSpotlightBadge(target);
      _recomputeEngagementView();
    });
  }

  function _bindPortfolioSync() {
    if (_portfolioSyncBound) return;
    _portfolioSyncBound = true;
    window.addEventListener('nw:portfolio-engagement-update', (event) => {
      const detail = event?.detail || {};
      const providerId = _safeInt(detail.provider_id);
      if (!providerId || String(providerId) !== String(_providerId)) return;
      const itemId = _safeInt(detail.id);
      if (!itemId) return;

      const target = _portfolioItems.find((item) => _safeInt(item.id) === itemId);
      if (!target) return;

      target.likes_count = _safeInt(detail.likes_count);
      target.saves_count = _safeInt(detail.saves_count);
      target.comments_count = _safeInt(detail.comments_count);
      target.is_liked = _asBool(detail.is_liked);
      target.is_saved = _asBool(detail.is_saved);

      _syncPortfolioEngagementTotals();
      _updatePortfolioBadge(target);
      _recomputeEngagementView();
    });
  }

  function _resolveReturnNavigation() {
    try {
      const params = new URLSearchParams(window.location.search || '');
      const fromMap = params.get('from_map') === '1';
      const returnTo = String(params.get('return_to') || '').trim();
      const returnLabel = String(params.get('return_label') || '').trim();

      if (!fromMap && !returnTo) return null;

      const fallbackMapPath = '/search/?open_map=1';
      const rawTarget = returnTo || fallbackMapPath;
      let href = _sanitizeInternalReturnPath(rawTarget);
      if (!href) return null;

      if (fromMap && href.startsWith('/search')) {
        const normalized = new URL(href, window.location.origin);
        if (normalized.searchParams.get('open_map') !== '1') {
          normalized.searchParams.set('open_map', '1');
        }
        href = normalized.pathname + normalized.search + normalized.hash;
      }

      return {
        href,
        label: returnLabel || (fromMap ? _copy('returnToMap') : _copy('return')),
      };
    } catch (_) {
      return {
        href: '/search/?open_map=1',
        label: _copy('returnToMap'),
      };
    }
  }

  function _sanitizeInternalReturnPath(rawPath) {
    const candidate = String(rawPath || '').trim();
    if (!candidate || candidate.startsWith('//')) return '';
    try {
      const parsed = new URL(candidate, window.location.origin);
      if (parsed.origin !== window.location.origin) return '';
      if (!parsed.pathname.startsWith('/')) return '';
      return parsed.pathname + parsed.search + parsed.hash;
    } catch (_) {
      return '';
    }
  }

  /* ── Load all data ── */
  async function _loadAll() {
    _setInitialShellLoading(true);
    const providerPath = _withMode('/api/providers/' + _providerId + '/');
    const statsPath = _withMode('/api/providers/' + _providerId + '/stats/');
    const [provRes, statsRes] = await Promise.all([
      ApiClient.get(providerPath),
      ApiClient.get(statsPath)
    ]);

    if (provRes.ok && provRes.data) {
      _providerData = provRes.data;
      // Reveal the content shell BEFORE rendering so any embedded
      // sub-widgets (e.g. Leaflet map) can size themselves correctly.
      _setInitialShellLoading(false);
      _renderProvider(provRes.data, statsRes.ok ? statsRes.data : null);
      if (typeof NwAnalytics !== 'undefined') {
        NwAnalytics.trackOnce(
          'provider.profile_view',
          {
            surface: 'mobile_web.provider_detail',
            source_app: 'providers',
            object_type: 'ProviderProfile',
            object_id: String(_providerId || ''),
            payload: {
              mode: _mode || 'client',
              has_stats: !!(statsRes.ok && statsRes.data),
            },
          },
          'provider.profile_view:mobile_web:' + String(_providerId || '')
        );
      }
    }
    _setInitialShellLoading(false);
    _syncFollowState();

    // Parallel: services, portfolio, reviews, spotlights
    _loadServices();
    _loadPortfolio();
    _loadReviews();
    _loadSpotlights();
  }

  /* ═══════════════════════════════════════════════
     RENDER PROVIDER PROFILE
     ═══════════════════════════════════════════════ */
  function _stopProviderCoverGalleryRotation() {
    if (_coverGalleryTimer) {
      window.clearInterval(_coverGalleryTimer);
      _coverGalleryTimer = 0;
    }
  }

  function _normalizedProviderCoverGallery(provider) {
    const profile = provider || {};
    const gallery = Array.isArray(profile.cover_gallery)
      ? profile.cover_gallery
      : (Array.isArray(profile.coverGallery) ? profile.coverGallery : []);
    const normalizedGallery = gallery
      .map((item, index) => {
        const rawUrl = item && (item.image_url || item.imageUrl || item.url || item.image);
        return {
          imageUrl: rawUrl ? ApiClient.mediaUrl(rawUrl) : '',
          sortOrder: Number(item && item.sort_order != null ? item.sort_order : index),
        };
      })
      .filter((item) => item.imageUrl);
    if (normalizedGallery.length) return normalizedGallery;

    const coverImages = Array.isArray(profile.cover_images)
      ? profile.cover_images
      : (Array.isArray(profile.coverImages) ? profile.coverImages : []);
    const normalizedList = coverImages
      .map((rawUrl, index) => ({
        imageUrl: rawUrl ? ApiClient.mediaUrl(rawUrl) : '',
        sortOrder: index,
      }))
      .filter((item) => item.imageUrl);
    if (normalizedList.length) return normalizedList;

    const coverImage = _pickFirstText(profile.cover_image, profile.coverImage);
    if (!coverImage) return [];
    return [{ imageUrl: ApiClient.mediaUrl(coverImage), sortOrder: 0 }];
  }

  function _renderProviderCoverGallery(provider) {
    const coverEl = document.getElementById('pd-cover');
    const dots = document.getElementById('pd-cover-gallery-dots');
    if (!coverEl) return;

    const gallery = _normalizedProviderCoverGallery(provider);
    _stopProviderCoverGalleryRotation();
    let mediaImg = coverEl.querySelector('img.pd-cover-media');
    let backgroundImg = coverEl.querySelector('img.pd-cover-bg');

    if (!backgroundImg) {
      backgroundImg = document.createElement('img');
      backgroundImg.className = 'pd-cover-bg';
      backgroundImg.alt = '';
      backgroundImg.setAttribute('aria-hidden', 'true');
      backgroundImg.decoding = 'async';
      coverEl.insertBefore(backgroundImg, coverEl.firstChild);
    }

    if (!mediaImg) {
      mediaImg = document.createElement('img');
      mediaImg.className = 'pd-cover-media';
      mediaImg.decoding = 'async';
      mediaImg.loading = 'eager';
      mediaImg.fetchPriority = 'high';
      const gradientEl = coverEl.querySelector('.pd-cover-gradient');
      coverEl.insertBefore(mediaImg, gradientEl || dots || null);
    }

    if (!gallery.length) {
      coverEl.style.backgroundImage = '';
      coverEl.classList.remove('has-media', 'has-gallery');
      if (mediaImg) {
        mediaImg.removeAttribute('src');
        mediaImg.alt = '';
      }
      if (backgroundImg) {
        backgroundImg.removeAttribute('src');
      }
      if (dots) {
        dots.innerHTML = '';
        dots.classList.add('hidden');
      }
      return;
    }

    _coverGalleryIndex = Math.max(0, Math.min(_coverGalleryIndex, gallery.length - 1));

    const applySlide = (index) => {
      _coverGalleryIndex = index;
      const imageUrl = gallery[index].imageUrl;
      const displayName = _pickFirstText(provider && (provider.display_name || provider.displayName));
      coverEl.style.backgroundImage = '';
      backgroundImg.src = imageUrl;
      mediaImg.src = imageUrl;
      mediaImg.alt = displayName || _copy('cover');
      coverEl.classList.add('has-media');
      coverEl.classList.toggle('has-gallery', gallery.length > 1);
      if (!dots) return;
      dots.innerHTML = '';
      dots.classList.toggle('hidden', gallery.length <= 1);
      gallery.forEach((_, dotIndex) => {
        const dot = document.createElement('button');
        dot.type = 'button';
        dot.className = 'pd-cover-gallery-dot' + (dotIndex === _coverGalleryIndex ? ' is-active' : '');
        dot.setAttribute('aria-label', `${_copy('cover')} ${dotIndex + 1}`);
        dot.addEventListener('click', () => {
          applySlide(dotIndex);
          if (gallery.length > 1) {
            _stopProviderCoverGalleryRotation();
            _coverGalleryTimer = window.setInterval(() => {
              applySlide((_coverGalleryIndex + 1) % gallery.length);
            }, 4800);
          }
        });
        dots.appendChild(dot);
      });
    };

    applySlide(_coverGalleryIndex);
    if (gallery.length > 1) {
      _coverGalleryTimer = window.setInterval(() => {
        applySlide((_coverGalleryIndex + 1) % gallery.length);
      }, 4800);
    }
  }

  function _renderProvider(p, stats) {
    _providerWhatsappUrl = _pickFirstText(p.whatsapp_url, p.whatsappUrl);
    _providerPhone = _pickFirstText(
      p.phone,
      p.whatsapp,
      p.phone_number,
      p.phoneNumber
    );

    // ── Cover ──
    _renderProviderCoverGallery(p);

    // ── Avatar ──
    const avatarEl = document.getElementById('pd-avatar');
    const profileImage = _pickFirstText(p.profile_image, p.profileImage);
    const displayName = _pickFirstText(p.display_name, p.displayName);
    if (profileImage) {
      avatarEl.textContent = '';
      avatarEl.appendChild(UI.lazyImg(ApiClient.mediaUrl(profileImage), displayName || ''));
    } else {
      avatarEl.textContent = displayName.charAt(0) || '؟';
    }
    const avatarWrapEl = avatarEl ? avatarEl.closest('.pd-avatar-wrap') : null;
    if (avatarWrapEl && typeof UI.presenceDot === 'function') {
      avatarWrapEl.querySelectorAll('.nw-presence-dot').forEach((dot) => dot.remove());
      avatarWrapEl.appendChild(UI.presenceDot(_asBool(p.is_online), { size: 'lg' }));
    }

    // ── Verification badges (blue/green unified style) ──
    const blueBadge = document.getElementById('pd-verified-badge-blue');
    const greenBadge = document.getElementById('pd-verified-badge-green');
    if (blueBadge) {
      blueBadge.classList.toggle('hidden', !_asBool(p.is_verified_blue));
    }
    if (greenBadge) {
      greenBadge.classList.toggle('hidden', !_asBool(p.is_verified_green));
    }

    _renderAvatarExcellenceBadges(p.excellence_badges);
    _renderExcellenceBadgeShowcase(p.excellence_badges);

    // ── Name & handle ──
    const username = _pickFirstText(p.username, p.user_name);
    _setText('pd-name', displayName);
    _setText('pd-handle', username ? ('@' + username) : '');
    _syncCategoryViews();

    // ── Stats ──
    const completed = stats?.completed_requests ?? p.completed_requests ?? p.completed_orders_count ?? 0;
    const followers = stats?.followers_count ?? p.followers_count ?? 0;
    const following = stats?.following_count ?? p.following_count ?? 0;
    const profileLikes = stats?.profile_likes_count ?? stats?.likes_count ?? p.likes_count ?? 0;
    _mediaLikesTotal = _safeNullableInt(stats?.media_likes_count);
    const rating = p.rating_avg ? parseFloat(p.rating_avg).toFixed(1) : '-';

    _setText('stat-completed', completed);
    _setText('stat-followers', followers);
    _profileLikesBase = _safeInt(profileLikes);
    _setText('stat-likes', _mediaLikesTotal !== null ? _mediaLikesTotal : _profileLikesBase);
    _setText('stat-rating', rating);

    _recomputeEngagementView();

    const followingBtn = document.getElementById('btn-show-following');
    if (followingBtn) {
      followingBtn.dataset.count = String(following || 0);
    }

    // ── Follow state ──
    _isFollowing = _asBool(p.is_following);
    _updateFollowBtn();

    // ── Profile tab content ──
    _renderProfileTab(p);

    // ── Page meta ──
    _applySeoMeta(p, displayName);
  }

  /* ── Render profile tab details ── */
  function _renderProfileTab(p) {
    const unavailable = _copy('unavailable');
    const bioText = _pickFirstText(p.bio, p.description);
    const providerTypeLabel = _pickFirstText(p.provider_type_label, p.providerTypeLabel);
    const whatsappRaw = _pickFirstText(p.whatsapp, p.phone, p.phone_number, p.phoneNumber);
    const websiteRaw = String(p.website || '').trim();
    const cityText = _displayOrUnavailable(_resolveProviderCityDisplay(p), unavailable);
    const experienceText = p.years_experience ? _copy('experienceYearsValue', { count: p.years_experience }) : unavailable;
    const serviceRangeText = _copy('serviceRangeKm', { count: _resolveServiceRangeKm(p) });
      const socialCard = document.getElementById('pd-social-card');

    // Bio
    _setText('pd-bio', bioText || _copy('noDescription'));
    _setAutoDirection('pd-bio', bioText);
    _renderAdditionalInfoCard(p);

    // Registration data
    const mainCategory = _resolveMainCategory(p);
    const subCategory = _resolveSubCategory(p);
    _setText('pd-provider-type', _displayOrUnavailable(providerTypeLabel, unavailable));
    _setText('pd-main-category', _displayOrUnavailable(mainCategory, unavailable));
    _setText('pd-sub-category', _displayOrUnavailable(subCategory, unavailable));

    // Experience
    _setText('pd-experience', experienceText);
    _setText('pd-whatsapp', _displayOrUnavailable(whatsappRaw, unavailable));
    _setText('pd-website', websiteRaw || unavailable);
    _setText('pd-city-name', cityText);
    _setText('pd-overview-city', cityText);
    _setText('pd-overview-experience', experienceText);
    _setText('pd-overview-range', serviceRangeText);

    // ── Website ──
    const websiteBtn = document.getElementById('pd-website-open');
    if (websiteBtn) {
      websiteBtn.disabled = !websiteRaw;
      websiteBtn.classList.toggle('disabled', !websiteRaw);
      websiteBtn.onclick = () => {
        if (!websiteRaw) return;
        const url = websiteRaw.startsWith('http') ? websiteRaw : ('https://' + websiteRaw);
        window.open(url, '_blank', 'noopener');
      };
    }

    _renderSocialLinks(p, socialCard);

    try {
      _renderServiceRangeMap(p);
    } catch (_) {
      _setText('pd-service-range-summary', _copy('mapLoadFailedSummary'));
      const mapEl = document.getElementById('pd-service-range-map');
      const emptyEl = document.getElementById('pd-service-range-map-empty');
      if (mapEl) mapEl.classList.add('hidden');
      if (emptyEl) {
        emptyEl.textContent = _copy('mapLoadFailed');
        emptyEl.classList.remove('hidden');
      }
    }
  }

  function _normalizeProfileInfoEntries(items) {
    if (!Array.isArray(items)) return [];
    const values = [];
    items.forEach((item) => {
      const text = typeof item === 'string'
        ? _trimText(item)
        : _pickFirstText(item && item.title, item && item.name, item && item.label, item && item.value);
      if (text && values.indexOf(text) === -1) values.push(text);
    });
    return values;
  }

  function _appendAdditionalInfoSection(card, label, options) {
    if (!card) return;
    const valueHtml = _trimText(options && options.html);
    const valueText = _trimText(options && options.text);
    if (!valueHtml && !valueText) return;

    if (card.children.length > 1) {
      card.appendChild(UI.el('div', { className: 'pd-field-divider' }));
    }

    const row = UI.el('div', { className: 'pd-field-row' });
    const field = UI.el('div', { className: 'pd-field' });
    field.appendChild(UI.el('span', { className: 'pd-field-label', textContent: label }));

    const valueNode = UI.el('div', { className: 'pd-field-value' });
    if (valueHtml) {
      valueNode.innerHTML = valueHtml;
    } else {
      valueNode.textContent = valueText;
      _setAutoDirection(valueNode, valueText);
    }

    field.appendChild(valueNode);
    row.appendChild(field);
    card.appendChild(row);
  }

  function _renderAdditionalInfoCard(provider) {
    const panel = document.getElementById('tab-profile');
    if (!panel) return;

    const detailsText = _trimText(provider && provider.about_details);
    const qualifications = _normalizeProfileInfoEntries(provider && provider.qualifications);
    const experiences = _normalizeProfileInfoEntries(provider && provider.experiences);
    const hasContent = !!(detailsText || qualifications.length || experiences.length);

    const existing = document.getElementById('pd-additional-info-card');
    if (!hasContent) {
      if (existing) existing.remove();
      return;
    }

    const card = existing || UI.el('div', { className: 'pd-card', id: 'pd-additional-info-card' });
    card.textContent = '';

    const title = UI.el('h4', { className: 'pd-card-title' });
    title.innerHTML = [
      '<svg width="18" height="18" viewBox="0 0 24 24" fill="var(--color-primary)"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path><path d="M14 2v6h6"></path><path d="M8 13h8"></path><path d="M8 17h5"></path></svg>',
      '<span>' + _escapeHtml(_copy('additionalInfoTitle')) + '</span>',
    ].join('');
    card.appendChild(title);

    if (detailsText) {
      _appendAdditionalInfoSection(card, _copy('additionalDetailsLabel'), {
        html: _escapeHtml(detailsText).replace(/\n/g, '<br>'),
      });
    }

    if (qualifications.length) {
      _appendAdditionalInfoSection(card, _copy('qualificationsLabel'), {
        html: qualifications.map((item) => '<span class="pd-service-chip">' + _escapeHtml(item) + '</span>').join(' '),
      });
    }

    if (experiences.length) {
      _appendAdditionalInfoSection(card, _copy('experiencesLabel'), {
        html: experiences.map((item) => '<div>' + _escapeHtml(item) + '</div>').join(''),
      });
    }

    const anchor = document.getElementById('pd-categories-card') || document.getElementById('pd-contact-card') || document.getElementById('pd-social-card');
    if (!existing) {
      if (anchor && anchor.parentNode === panel) panel.insertBefore(card, anchor);
      else panel.appendChild(card);
    }
  }

  function _resolveProviderCityDisplay(provider) {
    return UI.formatCityDisplay(
      _pickFirstText(provider && provider.city_display, provider && provider.city),
      _pickFirstText(provider && (provider.region || provider.region_name))
    );
  }

  async function _openConnectionsSheet(kind) {
    const isFollowers = kind === 'followers';
    const endpoint = _withMode(isFollowers
      ? '/api/providers/' + _providerId + '/followers/?scope=all'
      : '/api/providers/' + _providerId + '/following/?scope=all');
    const title = isFollowers ? _copy('followersSheetTitle') : _copy('followingSheetTitle');
    const subtitle = isFollowers ? _copy('followersSheetSubtitle') : _copy('followingSheetSubtitle');
    const countEl = isFollowers ? document.getElementById('stat-followers') : document.getElementById('btn-show-following');
    const fallbackCount = countEl ? (parseInt(isFollowers ? countEl.textContent : countEl.dataset.count, 10) || 0) : 0;

    const res = await ApiClient.get(endpoint);
    const items = res.ok
      ? (Array.isArray(res.data) ? res.data : (res.data?.results || []))
      : [];
    const actualCount = Array.isArray(items) ? items.length : 0;
    const count = actualCount || fallbackCount;

    if (countEl && actualCount !== fallbackCount) {
      if (isFollowers) countEl.textContent = String(actualCount);
      else countEl.dataset.count = String(actualCount);
    }

    const backdrop = UI.el('div', { className: 'pd-sheet-backdrop pd-connections-sheet-backdrop' });
    const sheet = UI.el('div', { className: 'pd-sheet pd-connections-sheet' });
    const handle = UI.el('div', { className: 'pd-sheet-handle' });
    const header = UI.el('div', { className: 'pd-sheet-header pd-connections-sheet-header' });
    const headingWrap = UI.el('div', { className: 'pd-connections-heading' });
    const headingIcon = UI.el('span', { className: 'pd-connections-heading-icon' });
    headingIcon.innerHTML = isFollowers
      ? '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>'
      : '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><line x1="19" y1="8" x2="19" y2="14"/><line x1="22" y1="11" x2="16" y2="11"/></svg>';
    const headingMeta = UI.el('div', { className: 'pd-connections-heading-meta' });
    headingMeta.appendChild(UI.el('div', {
      className: 'pd-sheet-title',
      textContent: title + ' (' + count + ')',
    }));
    headingMeta.appendChild(UI.el('div', {
      className: 'pd-connections-subtitle',
      textContent: subtitle,
    }));
    headingWrap.appendChild(headingIcon);
    headingWrap.appendChild(headingMeta);
    const closeBtn = UI.el('button', {
      className: 'pd-sheet-close',
      type: 'button',
      textContent: '×',
    });
    closeBtn.setAttribute('aria-label', _copy('close'));
    closeBtn.addEventListener('click', closeSheet);

    header.appendChild(headingWrap);
    header.appendChild(closeBtn);
    sheet.appendChild(handle);
    sheet.appendChild(header);

    const body = UI.el('div', { className: 'pd-sheet-body' });
    let noticeTimer = null;

    if (!res.ok && !items.length) {
      body.appendChild(UI.el('div', {
        className: 'pd-sheet-empty',
        textContent: res.error || _copy('loadListFailed'),
      }));
    } else if (!items.length) {
      body.appendChild(UI.el('div', {
        className: 'pd-sheet-empty',
        textContent: isFollowers ? _copy('noFollowersYet') : _copy('noFollowingYet'),
      }));
    } else {
      // Search input (premium UX) — filter rows by name/username
      const searchWrap = UI.el('div', { className: 'pd-connections-search' });
      const searchIcon = UI.el('span', { className: 'pd-connections-search-icon' });
      searchIcon.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>';
      const searchInput = UI.el('input', {
        type: 'search',
        className: 'pd-connections-search-input',
        placeholder: _copy('searchByName'),
      });
      searchInput.setAttribute('autocomplete', 'off');
      searchInput.setAttribute('aria-label', _copy('searchList'));
      searchWrap.appendChild(searchIcon);
      searchWrap.appendChild(searchInput);
      body.appendChild(searchWrap);

      const list = UI.el('div', { className: 'pd-sheet-list pd-connections-list' });
      const rowRecords = [];

      items.forEach(item => {
        const name = String(item.display_name || item.name || item.username || _copy('user')).trim() || _copy('user');
        const username = String(item.username || item.username_display || '').trim();
        const avatarUrl = ApiClient.mediaUrl(item.profile_image || item.provider_profile_image || item.avatar || '');

        // Determine provider status.
        // Followers endpoint: item.provider_id is set only for providers.
        // Following endpoint: every item is a provider (item.id IS the provider id).
        const followerProviderId = _safeInt(item.provider_id);
        const isProvider = isFollowers ? followerProviderId > 0 : true;
        const linkProviderId = isFollowers ? followerProviderId : _safeInt(item.id);
        const isVerifiedBlue = !!item.is_verified_blue;
        const isVerifiedGreen = !!item.is_verified_green;

        const row = UI.el('button', {
          type: 'button',
          className: 'pd-sheet-item pd-connections-item' + (isProvider ? ' is-provider' : ' is-client'),
        });
        row.setAttribute('aria-label', isProvider
          ? _copy('openProfile', { name })
          : _copy('notProviderShort', { name }));

        const avatar = UI.el('div', { className: 'pd-sheet-avatar' });
        if (avatarUrl) avatar.appendChild(UI.lazyImg(avatarUrl, name));
        else avatar.appendChild(UI.el('span', { textContent: name.charAt(0) }));
        row.appendChild(avatar);

        const meta = UI.el('div', { className: 'pd-sheet-meta' });
        const nameRow = UI.el('div', { className: 'pd-connections-name-row' });
        const nameEl = UI.el('span', { className: 'pd-sheet-name', textContent: name });
        _setAutoDirection(nameEl, name);
        nameRow.appendChild(nameEl);
        if (isProvider) {
          const verifiedBadges = UI.buildVerificationBadges({
            isVerifiedBlue: isVerifiedBlue,
            isVerifiedGreen: isVerifiedGreen,
            iconSize: 13,
            gap: '3px',
            blueLabel: _copy('blueBadgeVerified'),
            greenLabel: _copy('greenBadgeVerified'),
          });
          if (verifiedBadges) nameRow.appendChild(verifiedBadges);
        }
        meta.appendChild(nameRow);
        if (username) {
          meta.appendChild(UI.el('span', {
            className: 'pd-sheet-handle-text pd-connections-handle-text',
            textContent: '@' + username,
          }));
        }
        row.appendChild(meta);

        const badge = UI.el('span', {
          className: 'pd-connections-badge ' + (isProvider ? 'is-provider' : 'is-client'),
          textContent: isProvider ? _copy('provider') : _copy('client'),
        });
        row.appendChild(badge);

        const chevron = UI.el('span', { className: 'pd-connections-chevron' });
        chevron.setAttribute('aria-hidden', 'true');
        chevron.innerHTML = isProvider
          ? '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 6-6 6 6 6"/></svg>'
          : '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 8v4"/><path d="M12 16h.01"/></svg>';
        row.appendChild(chevron);

        row.addEventListener('click', (event) => {
          event.preventDefault();
          if (isProvider && linkProviderId > 0) {
            closeSheet();
            window.location.href = '/provider/' + encodeURIComponent(String(linkProviderId)) + '/';
            return;
          }
          showNotProviderModal(name, avatarUrl, username);
        });

        list.appendChild(row);
        rowRecords.push({ row, haystack: (name + ' ' + username).toLowerCase() });
      });
      body.appendChild(list);

      const emptySearch = UI.el('div', {
        className: 'pd-sheet-empty pd-connections-empty-search hidden',
        textContent: _copy('noMatchingResults'),
      });
      body.appendChild(emptySearch);

      searchInput.addEventListener('input', () => {
        const q = searchInput.value.trim().toLowerCase();
        let visible = 0;
        rowRecords.forEach(rec => {
          const match = !q || rec.haystack.indexOf(q) !== -1;
          rec.row.classList.toggle('hidden', !match);
          if (match) visible += 1;
        });
        emptySearch.classList.toggle('hidden', visible !== 0);
      });
    }

    sheet.appendChild(body);
    backdrop.appendChild(sheet);
    document.body.appendChild(backdrop);
    requestAnimationFrame(() => backdrop.classList.add('open'));

    backdrop.addEventListener('click', e => {
      if (e.target === backdrop) closeSheet();
    });

    function closeSheet() {
      backdrop.classList.remove('open');
      if (noticeTimer) {
        window.clearTimeout(noticeTimer);
        noticeTimer = null;
      }
      setTimeout(() => backdrop.remove(), 180);
    }

    function showNotProviderModal(name, avatarUrl, username) {
      const existing = document.querySelector('.pd-not-provider-modal');
      if (existing) existing.remove();

      const modalBackdrop = UI.el('div', { className: 'pd-not-provider-modal' });
      const card = UI.el('div', { className: 'pd-not-provider-card' });

      const avatarBubble = UI.el('div', { className: 'pd-not-provider-avatar' });
      if (avatarUrl) avatarBubble.appendChild(UI.lazyImg(avatarUrl, name));
      else avatarBubble.appendChild(UI.el('span', { textContent: (name || _copy('providerFallback')).charAt(0) }));

      const lockBadge = UI.el('span', { className: 'pd-not-provider-lock' });
      lockBadge.setAttribute('aria-hidden', 'true');
      lockBadge.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 1 1 8 0v4"/></svg>';
      avatarBubble.appendChild(lockBadge);
      card.appendChild(avatarBubble);

      card.appendChild(UI.el('div', {
        className: 'pd-not-provider-title',
        textContent: _copy('notProviderTitle'),
      }));
      card.appendChild(UI.el('div', {
        className: 'pd-not-provider-name',
        textContent: name + (username ? ' (@' + username + ')' : ''),
      }));
      card.appendChild(UI.el('p', {
        className: 'pd-not-provider-message',
        textContent: _copy('notProviderMessage'),
      }));

      const okBtn = UI.el('button', {
        type: 'button',
        className: 'pd-not-provider-ok',
        textContent: _copy('understood'),
      });
      const closeIcon = UI.el('button', {
        type: 'button',
        className: 'pd-not-provider-close',
        textContent: '×',
      });
      closeIcon.setAttribute('aria-label', _copy('close'));

      card.appendChild(okBtn);
      card.appendChild(closeIcon);
      modalBackdrop.appendChild(card);
      document.body.appendChild(modalBackdrop);
      requestAnimationFrame(() => modalBackdrop.classList.add('open'));

      function dismiss() {
        modalBackdrop.classList.remove('open');
        window.setTimeout(() => modalBackdrop.remove(), 200);
        document.removeEventListener('keydown', onKey);
      }
      function onKey(e) {
        if (e.key === 'Escape') dismiss();
      }
      okBtn.addEventListener('click', dismiss);
      closeIcon.addEventListener('click', dismiss);
      modalBackdrop.addEventListener('click', (e) => {
        if (e.target === modalBackdrop) dismiss();
      });
      document.addEventListener('keydown', onKey);
      try { okBtn.focus({ preventScroll: true }); } catch (_) { okBtn.focus(); }
    }
  }

  function _buildProviderLink() {
    const resolvedId = _safeInt(_providerData && (_providerData.id || _providerData.provider_id))
      || _safeInt(_providerId)
      || _providerId
      || 'provider';
    const base = String(ApiClient.baseUrl || window.location.origin || '').replace(/\/+$/, '');
    return base + '/provider/' + encodeURIComponent(String(resolvedId)) + '/';
  }

  function _buildQrImageUrl(targetUrl) {
    return 'https://api.qrserver.com/v1/create-qr-code/?size=420x420&data=' + encodeURIComponent(String(targetUrl || ''));
  }

  async function _openShareAndReportSheet() {
    const providerLink = _buildProviderLink();
    const qrImageUrl = _buildQrImageUrl(providerLink);
    const providerName = _trimText(document.getElementById('pd-name')?.textContent) || _copy('providerFallback');

    const existing = document.querySelector('.pd-share-sheet-backdrop');
    if (existing) existing.remove();

    const backdrop = UI.el('div', { className: 'pd-sheet-backdrop pd-share-sheet-backdrop' });
    const sheet = UI.el('div', { className: 'pd-sheet pd-share-sheet' });
    const handle = UI.el('div', { className: 'pd-sheet-handle' });
    const header = UI.el('div', { className: 'pd-sheet-header' });
    const heading = UI.el('div', {
      className: 'pd-sheet-title',
      textContent: _copy('shareProviderWindow'),
    });
    const closeBtn = UI.el('button', {
      className: 'pd-sheet-close',
      type: 'button',
      textContent: '×',
    });
    closeBtn.setAttribute('aria-label', _copy('close'));
    closeBtn.addEventListener('click', closeSheet);

    header.appendChild(heading);
    header.appendChild(closeBtn);
    sheet.appendChild(handle);
    sheet.appendChild(header);

    const body = UI.el('div', { className: 'pd-sheet-body pd-share-sheet-body' });
    const card = UI.el('div', { className: 'pd-share-card' });
    const qrWrap = UI.el('div', { className: 'pd-share-qr-wrap' });
    const qrImg = UI.el('img', {
      className: 'pd-share-qr',
      src: qrImageUrl,
      alt: _copy('qrAlt'),
    });
    qrImg.addEventListener('error', () => {
      qrWrap.innerHTML = '';
      qrWrap.appendChild(UI.el('div', { className: 'pd-share-qr-fallback', textContent: 'QR' }));
    });
    qrWrap.appendChild(qrImg);
    card.appendChild(qrWrap);

    card.appendChild(UI.el('p', {
      className: 'pd-share-link',
      textContent: providerLink,
    }));

    const actions = UI.el('div', { className: 'pd-share-actions' });
    const copyBtn = UI.el('button', {
      type: 'button',
      className: 'pd-share-btn',
      textContent: _copy('copyLink'),
    });
    copyBtn.addEventListener('click', async () => {
      const copied = await _copyToClipboard(providerLink);
      if (copied) await _trackProviderShare('copy_link');
      closeSheet();
      _showToast(copied ? _copy('linkCopied') : _copy('linkCopyFailed'));
    });

    const shareBtn = UI.el('button', {
      type: 'button',
      className: 'pd-share-btn',
      textContent: _copy('share'),
    });
    shareBtn.addEventListener('click', async () => {
      if (navigator.share) {
        try {
          await navigator.share({
            title: _copy('shareProviderWindow'),
            text: providerName,
            url: providerLink,
          });
          await _trackProviderShare('other');
          closeSheet();
          _showToast(_copy('linkShared'));
          return;
        } catch (err) {
          if (err && err.name === 'AbortError') return;
        }
      }
      const copied = await _copyToClipboard(providerLink);
      if (copied) await _trackProviderShare('copy_link');
      closeSheet();
      _showToast(copied ? _copy('linkCopied') : _copy('shareLinkFailed'));
    });

    actions.appendChild(copyBtn);
    actions.appendChild(shareBtn);
    card.appendChild(actions);
    body.appendChild(card);

    const reportBtn = UI.el('button', {
      type: 'button',
      className: 'pd-share-report-btn',
    });
    reportBtn.innerHTML = [
      '<span class="pd-share-report-icon" aria-hidden="true">',
      '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">',
      '<path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"></path>',
      '<line x1="4" y1="22" x2="4" y2="15"></line>',
      '</svg>',
      '</span>',
      '<span>' + _escapeHtml(_copy('reportProvider')) + '</span>',
    ].join('');
    reportBtn.addEventListener('click', () => {
      closeSheet();
      _openProviderReportDialog();
    });
    body.appendChild(reportBtn);

    sheet.appendChild(body);
    backdrop.appendChild(sheet);
    document.body.appendChild(backdrop);
    requestAnimationFrame(() => backdrop.classList.add('open'));

    backdrop.addEventListener('click', (e) => {
      if (e.target === backdrop) closeSheet();
    });

    function closeSheet() {
      backdrop.classList.remove('open');
      setTimeout(() => backdrop.remove(), 180);
    }
  }

  async function _copyToClipboard(text) {
    const value = String(text || '');
    if (!value) return false;

    if (navigator.clipboard && window.isSecureContext) {
      try {
        await navigator.clipboard.writeText(value);
        return true;
      } catch (_) {}
    }

    try {
      const input = document.createElement('textarea');
      input.value = value;
      input.setAttribute('readonly', '');
      input.style.position = 'fixed';
      input.style.top = '-9999px';
      input.style.left = '-9999px';
      document.body.appendChild(input);
      input.focus();
      input.select();
      const ok = document.execCommand('copy');
      input.remove();
      return !!ok;
    } catch (_) {
      return false;
    }
  }

  function _openProviderReportDialog() {
    const reasons = [
      _copy('reportReasonInappropriate'),
      _copy('reportReasonHarassment'),
      _copy('reportReasonFraud'),
      _copy('reportReasonAbusive'),
      _copy('reportReasonPrivacy'),
      _copy('reportReasonOther'),
    ];

    const providerName = _trimText(document.getElementById('pd-name')?.textContent) || _copy('providerFallback');
    const providerHandle = _trimText(document.getElementById('pd-handle')?.textContent);
    const entityText = providerHandle ? (providerName + ' (' + providerHandle + ')') : providerName;

    const oldDialog = document.querySelector('.pd-report-backdrop');
    if (oldDialog) oldDialog.remove();

    const backdrop = UI.el('div', { className: 'pd-report-backdrop' });
    const dialog = UI.el('div', { className: 'pd-report-dialog' });

    const titleRow = UI.el('div', { className: 'pd-report-title-row' });
    const titleIcon = UI.el('span', { className: 'pd-report-title-icon' });
    titleIcon.innerHTML = [
      '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">',
      '<path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"></path>',
      '<line x1="4" y1="22" x2="4" y2="15"></line>',
      '</svg>',
    ].join('');
    titleRow.appendChild(titleIcon);
    titleRow.appendChild(UI.el('h3', {
      className: 'pd-report-title',
      textContent: _copy('reportProviderDialog'),
    }));
    dialog.appendChild(titleRow);

    const infoBox = UI.el('div', { className: 'pd-report-info' });
    infoBox.appendChild(UI.el('p', {
      className: 'pd-report-info-label',
      textContent: _copy('reportInfo'),
    }));
    infoBox.appendChild(UI.el('p', {
      className: 'pd-report-info-value',
      textContent: entityText,
    }));
    infoBox.appendChild(UI.el('p', {
      className: 'pd-report-context',
      textContent: _copy('reportTypeProvider'),
    }));
    dialog.appendChild(infoBox);

    const reasonLabel = UI.el('label', {
      className: 'pd-report-label',
      textContent: _copy('reportReason'),
    });
    reasonLabel.setAttribute('for', 'pd-report-reason');
    dialog.appendChild(reasonLabel);

    const reasonSelect = UI.el('select', {
      className: 'pd-report-select',
      id: 'pd-report-reason',
    });
    reasons.forEach((reason) => {
      reasonSelect.appendChild(UI.el('option', { value: reason, textContent: reason }));
    });
    dialog.appendChild(reasonSelect);

    const detailsLabel = UI.el('label', {
      className: 'pd-report-label',
      textContent: _copy('reportDetails'),
    });
    detailsLabel.setAttribute('for', 'pd-report-details');
    dialog.appendChild(detailsLabel);

    const detailsInput = UI.el('textarea', {
      className: 'pd-report-textarea',
      id: 'pd-report-details',
      rows: 4,
      placeholder: _copy('reportDetailsPlaceholder'),
    });
    detailsInput.maxLength = 500;
    dialog.appendChild(detailsInput);

    const actions = UI.el('div', { className: 'pd-report-actions' });
    const cancelBtn = UI.el('button', {
      type: 'button',
      className: 'pd-report-btn pd-report-btn-cancel',
      textContent: _copy('cancel'),
    });
    cancelBtn.addEventListener('click', closeDialog);

    const submitBtn = UI.el('button', {
      type: 'button',
      className: 'pd-report-btn pd-report-btn-submit',
      textContent: _copy('submitReport'),
    });
    submitBtn.addEventListener('click', async () => {
      if (!Auth.isLoggedIn()) {
        window.location.href = '/login/?next=' + encodeURIComponent(window.location.pathname);
        return;
      }
      submitBtn.disabled = true;
      submitBtn.textContent = _copy('submitReportPending');
      try {
        const res = await ApiClient.request(_withMode('/api/providers/' + _providerId + '/report/'), {
          method: 'POST',
          body: {
            reason: String(reasonSelect.value || '').trim(),
            details: String(detailsInput.value || '').trim(),
          },
        });
        if (!res || !res.ok) {
          throw new Error((res && res.data && (res.data.detail || res.data.error)) || _copy('reportSendFailed'));
        }
        closeDialog();
        _showToast(_copy('reportSent'));
      } catch (err) {
        submitBtn.disabled = false;
        submitBtn.textContent = _copy('submitReport');
        _showToast((err && err.message) ? err.message : _copy('reportSendFailed'));
      }
    });

    actions.appendChild(cancelBtn);
    actions.appendChild(submitBtn);
    dialog.appendChild(actions);
    backdrop.appendChild(dialog);
    document.body.appendChild(backdrop);

    requestAnimationFrame(() => backdrop.classList.add('open'));
    backdrop.addEventListener('click', (e) => {
      if (e.target === backdrop) closeDialog();
    });

    function closeDialog() {
      backdrop.classList.remove('open');
      setTimeout(() => backdrop.remove(), 180);
    }
  }

  /* ═══ Follow / Unfollow ═══ */
  async function _toggleFollow() {
    if (!Auth.isLoggedIn()) { window.location.href = '/login/?next=' + encodeURIComponent(window.location.pathname); return; }
    const url = _withMode(_isFollowing
      ? '/api/providers/' + _providerId + '/unfollow/'
      : '/api/providers/' + _providerId + '/follow/');
    const btn = document.getElementById('btn-follow');
    btn.disabled = true;
    const res = await ApiClient.request(url, { method: 'POST' });
    btn.disabled = false;
    if (res.ok) {
      _isFollowing = !_isFollowing;
      _updateFollowBtn();
      const el = document.getElementById('stat-followers');
      if (el) {
        let c = parseInt(el.textContent) || 0;
        c += _isFollowing ? 1 : -1;
        el.textContent = Math.max(0, c);
      }
    }
  }

  async function _syncFollowState() {
    if (!Auth.isLoggedIn()) return;
    const res = await ApiClient.get(_withMode('/api/providers/me/following/'));
    if (!res.ok) return;
    const list = Array.isArray(res.data) ? res.data : (res.data?.results || []);
    const targetId = _safeInt(_providerId);
    const isFollowing = list.some(entry => {
      const provider = entry && (entry.provider || entry);
      return _safeInt(provider && provider.id) === targetId;
    });
    _isFollowing = isFollowing;
    _updateFollowBtn();
  }

  function _updateFollowBtn() {
    const btn = document.getElementById('btn-follow');
    if (!btn) return;
    btn.setAttribute('aria-label', _isFollowing ? _copy('unfollow') : _copy('follow'));
    btn.title = _isFollowing ? _copy('unfollow') : _copy('follow');
    if (_isFollowing) {
      btn.classList.add('following');
      btn.querySelector('span') ? null : null;
      // Replace inner content
      btn.textContent = '';
      const svg = _createSVG('<path d="M16 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="8.5" cy="7" r="4"/><line x1="23" y1="11" x2="17" y2="11"/>', 16);
      btn.appendChild(svg);
      btn.appendChild(document.createTextNode(' ' + _copy('unfollow')));
    } else {
      btn.classList.remove('following');
      btn.textContent = '';
      const svg = _createSVG('<path d="M16 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="8.5" cy="7" r="4"/><line x1="20" y1="8" x2="20" y2="14"/><line x1="23" y1="11" x2="17" y2="11"/>', 16);
      btn.appendChild(svg);
      btn.appendChild(document.createTextNode(' ' + _copy('follow')));
    }
  }

  /* ═══ Spotlights / Highlights ═══ */
  async function _loadSpotlights() {
    try {
      const res = await ApiClient.get(_withMode('/api/providers/' + _providerId + '/spotlights/'));
      if (!res.ok) {
        console.warn('[NW] spotlights API failed', res.status);
      } else {
        const raw = Array.isArray(res.data) ? res.data : (res.data?.results || []);
        console.log('[NW] spotlights raw count:', raw.length);

        _spotlights = raw.map(item => {
          const rawCaption = String(item.caption || item.title || '').trim();
          return {
            id: item.id,
            source: 'spotlight',
            provider_id: item.provider_id || _safeInt(_providerId),
            provider_display_name: _pickFirstText(
              item.provider_display_name,
              item.providerDisplayName,
              _providerData?.display_name,
              _providerData?.displayName
            ),
            provider_profile_image: _pickFirstText(
              item.provider_profile_image,
              item.providerProfileImage,
              _providerData?.profile_image,
              _providerData?.profileImage
            ),
            file_type: item.file_type || 'image',
            file_url: item.file_url || item.media_url || '',
            thumbnail_url: item.thumbnail_url || item.file_url || item.media_url || '',
            mode_context: _mode || 'client',
            section_title: _copy('highlightSection'),
            media_label: _deriveSpotlightMediaLabel(item, rawCaption),
            caption: rawCaption,
            likes_count: _safeInt(item.likes_count),
            saves_count: _safeInt(item.saves_count),
            is_liked: _asBool(item.is_liked),
            is_saved: _asBool(item.is_saved),
          };
        }).filter(item => (item.file_url || item.thumbnail_url));

        console.log('[NW] spotlights after filter:', _spotlights.length);
        try { _syncSpotlightEngagementTotals(); } catch (_) {}
        try { _recomputeEngagementView(); } catch (_) {}
      }
    } catch (err) {
      console.error('[NW] _loadSpotlights error:', err);
    } finally {
      _renderSpotlightsRow();
    }
  }

  function _renderSpotlightsRow() {
    const section = document.getElementById('pd-highlights-section');
    const row = document.getElementById('pd-highlights');
    if (!section || !row) return;

    const emptyEl = document.getElementById('pd-highlights-empty');
    const hintEl = document.getElementById('pd-highlights-hint');

    if (!_spotlights.length) {
      // Keep section visible, show empty state
      if (emptyEl) emptyEl.style.display = '';
      if (hintEl) hintEl.style.display = 'none';
      return;
    }

    // Has spotlights — clear row (removes empty state), render items, show hint
    if (hintEl) hintEl.style.display = '';
    row.textContent = '';
    _spotlights.forEach((item, idx) => {
      const el = UI.el('div', { className: 'pd-highlight-item' });
      el.dataset.itemId = String(_safeInt(item.id));
      const thumb = UI.el('div', { className: 'pd-highlight-thumb' });
      thumb.appendChild(_buildSpotlightPreviewMedia(item));

      const stats = UI.el('div', { className: 'pd-highlight-stats' });
      const likes = UI.el('span', {
        className: 'pd-highlight-stat' + (item.is_liked ? ' active' : ''),
        textContent: '❤ ' + String(_safeInt(item.likes_count)),
      });
      likes.dataset.stat = 'likes';
      const saves = UI.el('span', {
        className: 'pd-highlight-stat' + (item.is_saved ? ' active' : ''),
        textContent: '🔖 ' + String(_safeInt(item.saves_count)),
      });
      saves.dataset.stat = 'saves';
      stats.appendChild(likes);
      stats.appendChild(saves);
      thumb.appendChild(stats);

      el.appendChild(thumb);

      const caption = (item.caption || '').toString().trim();
      const labelEl = UI.el('div', { className: 'pd-highlight-label', textContent: caption || _copy('highlightFallback') });
      _setAutoDirection(labelEl, caption);
      el.appendChild(labelEl);

      el.addEventListener('click', () => {
        if (typeof SpotlightViewer !== 'undefined') {
          SpotlightViewer.open(_spotlights, idx, {
            source: 'spotlight',
            label: _copy('highlightFallback'),
            eventName: 'nw:spotlight-engagement-update',
            immersive: true,
            tiktokMode: true,
            modeContext: _mode || 'client',
          });
        }
      });

      row.appendChild(el);
    });
  }

  function _buildSpotlightPreviewMedia(item) {
    const fileType = String(item?.file_type || '').trim().toLowerCase();
    const thumbUrl = String(item?.thumbnail_url || '').trim();
    const fileUrl = String(item?.file_url || '').trim();
    const isVideo = fileType.indexOf('video') === 0 || /\.(mp4|mov|webm|m4v)(\?|$)/i.test(fileUrl);

    if (thumbUrl && !/\.(mp4|mov|webm|m4v)(\?|$)/i.test(thumbUrl)) {
      return UI.lazyImg(ApiClient.mediaUrl(thumbUrl), item.media_label || _copy('highlightFallback'));
    }

    if (isVideo && fileUrl) {
      const video = document.createElement('video');
      video.className = 'pd-highlight-preview-video';
      video.muted = true;
      video.defaultMuted = true;
      video.playsInline = true;
      video.preload = 'metadata';
      video.setAttribute('muted', 'muted');
      video.setAttribute('playsinline', 'playsinline');
      video.setAttribute('webkit-playsinline', 'webkit-playsinline');
      video.setAttribute('aria-hidden', 'true');
      video.src = ApiClient.mediaUrl(fileUrl);
      video.addEventListener('loadeddata', () => {
        try { video.currentTime = 0.1; } catch (_) {}
      }, { once: true });
      return video;
    }

    if (fileUrl) {
      return UI.lazyImg(ApiClient.mediaUrl(fileUrl), item.media_label || _copy('highlightFallback'));
    }

    return UI.el('div', { className: 'pd-highlight-fallback', textContent: _copy('reelFallback') });
  }

  function _syncSpotlightEngagementTotals() {
    _spotlightLikes = _spotlights.reduce((sum, item) => sum + _safeInt(item.likes_count), 0);
    _spotlightSaves = _spotlights.reduce((sum, item) => sum + _safeInt(item.saves_count), 0);
    _spotlightSavedByMe = _spotlights.some(item => !!item.is_saved);
  }

  function _updateSpotlightBadge(item) {
    const key = String(_safeInt(item?.id));
    if (!key) return;
    const root = document.querySelector('.pd-highlight-item[data-item-id="' + key + '"]');
    if (!root) return;
    const likesEl = root.querySelector('.pd-highlight-stat[data-stat="likes"]');
    const savesEl = root.querySelector('.pd-highlight-stat[data-stat="saves"]');
    if (likesEl) {
      likesEl.textContent = '❤ ' + String(_safeInt(item.likes_count));
      likesEl.classList.toggle('active', _asBool(item.is_liked));
    }
    if (savesEl) {
      savesEl.textContent = '🔖 ' + String(_safeInt(item.saves_count));
      savesEl.classList.toggle('active', _asBool(item.is_saved));
    }
  }

  /* ═══ Services ═══ */
  function _providerSelectedServiceRows(provider) {
    const rows = provider && Array.isArray(provider.selected_subcategories)
      ? provider.selected_subcategories
      : (provider && Array.isArray(provider.selectedSubcategories) ? provider.selectedSubcategories : []);

    return rows.map((item, idx) => {
      const categoryName = _pickFirstText(
        item && item.category_name,
        item && item.categoryName,
        provider ? provider.primary_category_name : '',
        provider ? provider.primaryCategoryName : ''
      );
      const name = _pickFirstText(
        item && item.name,
        item && item.subcategory_name,
        item && item.subCategoryName
      );
      return {
        id: _safeInt(item && item.id) || ('selected-service-' + String(idx + 1)),
        service_id: null,
        title: name,
        subcategory_name: name,
        category_name: categoryName,
        category_id: _safeInt(item && item.category_id) || null,
        price_unit: 'negotiable',
        is_selected_service_fallback: true,
        accepts_urgent: !!(item && item.accepts_urgent),
        requires_geo_scope: !(item && item.requires_geo_scope === false),
        subcategory: {
          id: _safeInt(item && item.id) || null,
          name: name,
          category_id: _safeInt(item && item.category_id) || null,
          category_name: categoryName,
        },
      };
    }).filter((item) => _trimText(item.title) || _trimText(item.category_name));
  }

  function _serviceFootnote(service) {
    return service && service.is_selected_service_fallback
      ? _copy('serviceConfiguredHint')
      : _copy('serviceCommunicationHint');
  }

  function _serviceScopeLabel(service) {
    return service && service.requires_geo_scope === false
      ? _copy('serviceRemoteAvailable')
      : _copy('serviceGeoScoped');
  }

  function _buildServiceRequestUrl(service) {
    const params = new URLSearchParams();
    params.set('provider_id', String(_providerId || ''));
    const serviceId = _safeInt(service && (service.service_id || service.id));
    const subcategory = service && typeof service.subcategory === 'object' ? service.subcategory : null;
    const categoryId = _safeInt(
      (subcategory && (subcategory.category_id || (subcategory.category && subcategory.category.id))) ||
      (service && service.category_id)
    );
    const subcategoryId = _safeInt(
      (subcategory && subcategory.id) ||
      (service && service.subcategory_id)
    );
    if (serviceId && !service.is_selected_service_fallback) params.set('service_id', String(serviceId));
    if (categoryId) params.set('category_id', String(categoryId));
    if (subcategoryId) params.set('subcategory_id', String(subcategoryId));
    params.set('service_name', String(service && (service.title || service.name) || '').trim());
    params.set('return_to', window.location.pathname + window.location.search);
    return '/service-request/?' + params.toString();
  }

  async function _loadServices() {
    const container = document.getElementById('pd-services-list');
    const emptyEl = document.getElementById('pd-services-empty');
    _setTabLoadingState('services', true);
    const res = await ApiClient.get('/api/providers/' + _providerId + '/services/');
    if (!res.ok) {
      _setTabMeta('services', '0');
      _setTabLoadingState('services', false);
      return;
    }
    const list = Array.isArray(res.data) ? res.data : (res.data?.results || []);
    const displayList = list.length ? list : _providerSelectedServiceRows(_providerData);
    _refreshDerivedCategories(displayList);
    _syncCategoryViews();
    container.textContent = '';
    if (emptyEl) emptyEl.classList.add('hidden');
    _setTabLoadingState('services', false);
    _setTabMeta('services', _formatTabCount(displayList.length));

    if (!displayList.length) {
      if (emptyEl) emptyEl.classList.remove('hidden');
      return;
    }

    displayList.forEach((svc, idx) => {
      const title = String(svc.title || svc.name || '').trim() || _copy('serviceWithoutName');
      const description = String(svc.description || '').trim();
      const subcategory = (svc.subcategory && typeof svc.subcategory === 'object') ? svc.subcategory : null;
      const categoryLabel = String(
        (subcategory && subcategory.category_name) ||
        svc.category_name ||
        svc.main_category ||
        ''
      ).trim();
      const subCategoryLabel = String(
        (subcategory && subcategory.name) ||
        svc.subcategory_name ||
        svc.sub_category ||
        ''
      ).trim();
      const requestUrl = _buildServiceRequestUrl(svc);
      const scopeLabel = _serviceScopeLabel(svc);

      const card = UI.el('div', { className: 'pd-service-list-card' });
      card.appendChild(UI.el('div', { className: 'pd-service-list-glow' }));

      const head = UI.el('div', { className: 'pd-service-list-head' });
      const headMain = UI.el('div', { className: 'pd-service-list-head-main' });
      headMain.appendChild(UI.el('span', { className: 'pd-service-index', textContent: String(idx + 1) }));

      const titleWrap = UI.el('div', { className: 'pd-service-list-title-wrap' });
  titleWrap.appendChild(UI.el('span', { className: 'pd-service-list-kicker', textContent: svc.is_selected_service_fallback ? _copy('selectedService') : _copy('publishedService') }));
      const serviceTitle = UI.el('h4', { className: 'pd-service-list-title', textContent: title });
      _setAutoDirection(serviceTitle, title);
      titleWrap.appendChild(serviceTitle);
      headMain.appendChild(titleWrap);
      head.appendChild(headMain);

      const requestButton = document.createElement('a');
      requestButton.className = 'pd-service-request-btn';
      requestButton.href = requestUrl;
      requestButton.setAttribute('aria-label', _copy('requestServiceCard'));
      requestButton.setAttribute('title', _copy('serviceRequestHint'));
      requestButton.innerHTML = '<span class="pd-service-request-btn-icon" aria-hidden="true"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.15" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3H8a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V7z"></path><path d="M14 3v4h4"></path><path d="M12 11v6"></path><path d="M9 14h6"></path></svg></span>';
      head.appendChild(requestButton);
      card.appendChild(head);

      const meta = UI.el('div', { className: 'pd-service-meta-stack' });
      const categoryMeta = UI.el('div', { className: 'pd-service-meta-item' });
      categoryMeta.appendChild(UI.el('span', { className: 'pd-service-meta-label', textContent: _copy('serviceMainCategoryLabel') }));
      const categoryValue = UI.el('strong', { className: 'pd-service-meta-value', textContent: categoryLabel || _copy('unavailable') });
      _setAutoDirection(categoryValue, categoryLabel);
      categoryMeta.appendChild(categoryValue);
      meta.appendChild(categoryMeta);

      const scopeMeta = UI.el('div', { className: 'pd-service-meta-item' });
      scopeMeta.appendChild(UI.el('span', { className: 'pd-service-meta-label', textContent: _copy('serviceScopeLabel') }));
      scopeMeta.appendChild(UI.el('strong', { className: 'pd-service-scope-pill', textContent: scopeLabel }));
      meta.appendChild(scopeMeta);
      card.appendChild(meta);

      const chips = UI.el('div', { className: 'pd-service-list-chips' });
      if (subCategoryLabel) {
        chips.appendChild(UI.el('span', { className: 'pd-service-chip', textContent: subCategoryLabel }));
      }
      if (svc.accepts_urgent) {
        chips.appendChild(UI.el('span', { className: 'pd-service-chip primary', textContent: _copy('serviceUrgentEnabled') }));
      }
      card.appendChild(chips);

      if (description) {
        const descEl = UI.el('p', { className: 'pd-service-list-desc', textContent: description });
        _setAutoDirection(descEl, description);
        card.appendChild(descEl);
      }

      const footer = UI.el('div', { className: 'pd-service-list-footer' });
      footer.appendChild(UI.el('span', {
        className: 'pd-service-footnote',
        textContent: _serviceFootnote(svc),
      }));
      card.appendChild(footer);

      container.appendChild(card);
    });
  }

  function _servicePriceLabel(service) {
    const from = _asNumber(service.price_from);
    const to = _asNumber(service.price_to);
    const unit = _serviceUnitLabel(service);
    const suffix = unit ? (' / ' + unit) : '';

    if (!Number.isFinite(from) && !Number.isFinite(to)) return _copy('servicePriceNegotiable');
    if (Number.isFinite(from) && Number.isFinite(to)) {
      if (Math.abs(from - to) < 0.0001) {
        return _copy('servicePriceSingle', { value: _formatCompactNumber(from), suffix });
      }
      return _copy('servicePriceRange', { from: _formatCompactNumber(from), to: _formatCompactNumber(to), suffix });
    }
    const value = Number.isFinite(from) ? from : to;
    if (Number.isFinite(value)) return _copy('servicePriceSingle', { value: _formatCompactNumber(value), suffix });
    return _copy('servicePriceNegotiable');
  }

  function _serviceUnitLabel(service) {
    const explicitLabel = String(service.price_unit_label || service.priceUnitLabel || '').trim();
    if (explicitLabel) return explicitLabel;

    const raw = String(service.price_unit || service.priceUnit || '').trim();
    const mapping = {
      fixed: _copy('serviceUnitFixed'),
      starting_from: _copy('serviceUnitStarting'),
      hour: _copy('serviceUnitHour'),
      day: _copy('serviceUnitDay'),
      negotiable: _copy('serviceUnitNegotiable'),
    };
    return mapping[raw] || raw;
  }

  function _serviceCountLabel(count) {
    if (count === 0) return _copy('servicesCountZero');
    if (count === 1) return _copy('servicesCountOne');
    if (count === 2) return _copy('servicesCountTwo');
    if (count >= 3 && count <= 10) return _copy('servicesCountFew', { count });
    return _copy('servicesCountMany', { count });
  }

  function _asNumber(value) {
    if (value === null || value === undefined || value === '') return NaN;
    const n = Number(value);
    return Number.isFinite(n) ? n : NaN;
  }

  /* ═══ Portfolio ═══ */
  async function _loadPortfolio() {
    const container = document.getElementById('pd-portfolio-sections');
    const emptyEl = document.getElementById('pd-portfolio-empty');
    if (!container) return;
    _setTabLoadingState('portfolio', true);
    const res = await ApiClient.get(_withMode('/api/providers/' + _providerId + '/portfolio/'));
    if (!res.ok) {
      _setTabMeta('portfolio', '0');
      _setTabLoadingState('portfolio', false);
      return;
    }
    const list = Array.isArray(res.data) ? res.data : (res.data?.results || []);

    container.textContent = '';
    _updatePortfolioHeroMetrics(0, 0);
    _resetPortfolioPreviewObserver();

    if (!list.length) {
      if (emptyEl) emptyEl.classList.remove('hidden');
      _setTabLoadingState('portfolio', false);
      _syncPortfolioPreviewPlayback();
      return;
    }
    if (emptyEl) emptyEl.classList.add('hidden');

    const grouped = new Map();
    _portfolioItems = [];
    list.forEach(item => {
      const fileType = String(item.file_type || 'image').toLowerCase();
      const fileUrl = String(item.file_url || item.image || item.media_url || item.file || '').trim();
      const thumbUrl = String(item.thumbnail_url || '').trim();
      const media = fileUrl || thumbUrl;
      if (!media) return;

      const rawCaption = String(item.caption || item.title || '').trim();
      const categoryName = String(item.category_name || '').trim();
      const sectionTitle = categoryName || _extractPortfolioSectionTitle(rawCaption);
      const description = _extractPortfolioItemDescription(rawCaption, sectionTitle);

      if (!grouped.has(sectionTitle)) grouped.set(sectionTitle, []);
      const normalizedItem = {
        id: _safeInt(item.id),
        source: 'portfolio',
        provider_id: _safeInt(item.provider_id) || _safeInt(_providerId),
        provider_display_name: _pickFirstText(
          item.provider_display_name,
          item.providerDisplayName,
          _providerData?.display_name,
          _providerData?.displayName
        ),
        provider_profile_image: _pickFirstText(
          item.provider_profile_image,
          item.providerProfileImage,
          _providerData?.profile_image,
          _providerData?.profileImage
        ),
        category_id: _safeInt(item.category_id),
        category_name: categoryName,
        type: fileType.startsWith('video') ? 'video' : 'image',
        media: media,
        file_type: fileType.startsWith('video') ? 'video' : 'image',
        file_url: fileUrl || media,
        thumbnail: thumbUrl,
        thumbnail_url: thumbUrl || fileUrl || media,
        mode_context: _mode || 'client',
        section_title: sectionTitle,
        media_label: _derivePortfolioMediaLabel(item, description, fileUrl),
        caption: rawCaption,
        desc: description,
        likes_count: _safeInt(item.likes_count),
        saves_count: _safeInt(item.saves_count),
        comments_count: _safeInt(item.comments_count),
        is_liked: _asBool(item.is_liked),
        is_saved: _asBool(item.is_saved),
      };
      grouped.get(sectionTitle).push(normalizedItem);
      _portfolioItems.push(normalizedItem);
    });

    _syncPortfolioEngagementTotals();
    _recomputeEngagementView();

    const sections = _resolvePortfolioSections(grouped);
    _updatePortfolioHeroMetrics(_portfolioItems.length, sections.length);
    sections.forEach(({ sectionTitle, sectionDesc, items }) => {
      const section = UI.el('section', { className: 'pd-portfolio-section' });
      const header = UI.el('div', { className: 'pd-portfolio-section-head' });
      header.appendChild(UI.el('h4', { className: 'pd-portfolio-section-title', textContent: sectionTitle }));
      const meta = UI.el('div', { className: 'pd-portfolio-section-meta' });
      meta.appendChild(UI.el('span', { className: 'pd-portfolio-section-count', textContent: String(items.length) }));
      meta.appendChild(UI.el('span', { className: 'pd-portfolio-section-hint', textContent: _copy('scrollHorizontally') }));
      header.appendChild(meta);
      section.appendChild(header);

      if (sectionDesc) {
        section.appendChild(UI.el('p', { className: 'pd-portfolio-section-desc', textContent: sectionDesc }));
      }

      if (!items.length) {
        const emptyCard = UI.el('div', { className: 'pd-empty-section-card' });
        emptyCard.appendChild(UI.el('p', { className: 'pd-empty-title', textContent: _copy('noItemsInSection') }));
        emptyCard.appendChild(UI.el('p', { className: 'pd-empty-subtitle', textContent: _copy('noItemsInSectionSubtitle') }));
        section.appendChild(emptyCard);
        container.appendChild(section);
        return;
      }

      const grid = UI.el('div', { className: 'pd-portfolio-grid pd-portfolio-reel-rail' });
      items.forEach((item, index) => {
        const el = UI.el('article', { className: 'pd-portfolio-item pd-portfolio-reel-card' });
        el.dataset.itemId = String(_safeInt(item.id));
        el.setAttribute('role', 'button');
        el.setAttribute('tabindex', '0');
        const displayUrl = (item.type === 'video' && item.thumbnail) ? item.thumbnail : item.media;
        const frame = UI.el('div', { className: 'pd-portfolio-frame' });
        if (item.type === 'video') {
          frame.appendChild(_buildPortfolioPreviewVideo(item, displayUrl, item.desc || sectionTitle));
        } else {
          frame.appendChild(UI.lazyImg(ApiClient.mediaUrl(displayUrl), item.desc || sectionTitle));
        }

        el.appendChild(frame);
        el.addEventListener('click', () => {
          if (typeof SpotlightViewer !== 'undefined') {
            const viewerItems = _portfolioItems.length ? _portfolioItems : items;
            const viewerIndex = Math.max(
              0,
              viewerItems.findIndex((entry) => _safeInt(entry && entry.id) === _safeInt(item.id))
            );
            SpotlightViewer.open(viewerItems, viewerIndex, {
              source: 'portfolio',
              label: _copy('portfolioTab'),
              eventName: 'nw:portfolio-engagement-update',
              immersive: true,
              tiktokMode: true,
              modeContext: _mode || 'client',
            });
          }
        });
        el.addEventListener('keydown', (event) => {
          if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            el.click();
          }
        });
        grid.appendChild(el);
      });

      section.appendChild(grid);
      container.appendChild(section);
    });

    if (!container.children.length && emptyEl) {
      emptyEl.classList.remove('hidden');
    }
    _setTabLoadingState('portfolio', false);
    _setupPortfolioPreviewObserver();
    _syncPortfolioPreviewPlayback();
  }

  function _buildPortfolioPreviewVideo(item, fallbackUrl, label) {
    const video = document.createElement('video');
    video.className = 'pd-portfolio-preview-video';
    video.muted = true;
    video.defaultMuted = true;
    video.loop = true;
    video.playsInline = true;
    video.preload = 'metadata';
    video.setAttribute('muted', 'muted');
    video.setAttribute('playsinline', 'playsinline');
    video.setAttribute('webkit-playsinline', 'webkit-playsinline');
    video.setAttribute('aria-label', label || item.media_label || _copy('videoFromGallery'));
    video.dataset.previewVideo = 'true';
    video.dataset.inview = '0';

    const sourceUrl = ApiClient.mediaUrl(item.file_url || item.media || fallbackUrl);
    if (sourceUrl) video.src = sourceUrl;
    const posterUrl = ApiClient.mediaUrl(item.thumbnail || item.thumbnail_url || fallbackUrl || item.media);
    if (posterUrl) video.poster = posterUrl;

    video.addEventListener('error', () => {
      const replacement = UI.lazyImg(posterUrl || fallbackUrl || item.media, label || item.media_label || '');
      replacement.className = 'pd-portfolio-preview-fallback';
      if (video.parentNode) video.parentNode.replaceChild(replacement, video);
    }, { once: true });

    return video;
  }

  function _resetPortfolioPreviewObserver() {
    if (_portfolioPreviewObserver) {
      _portfolioPreviewObserver.disconnect();
      _portfolioPreviewObserver = null;
    }
  }

  function _setupPortfolioPreviewObserver() {
    _resetPortfolioPreviewObserver();
    if (typeof window === 'undefined' || typeof document === 'undefined') return;
    const videos = Array.from(document.querySelectorAll('.pd-portfolio-preview-video'));
    if (!videos.length) return;

    if (typeof window.IntersectionObserver !== 'function') {
      videos.forEach((video, index) => {
        video.dataset.inview = index === 0 ? '1' : '0';
      });
      return;
    }

    _portfolioPreviewObserver = new window.IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        const video = entry.target;
        video.dataset.inview = entry.isIntersecting && entry.intersectionRatio >= 0.65 ? '1' : '0';
      });
      _syncPortfolioPreviewPlayback();
    }, {
      threshold: [0.35, 0.65, 0.85],
    });

    videos.forEach((video) => _portfolioPreviewObserver.observe(video));
  }

  function _syncPortfolioPreviewPlayback() {
    if (typeof document === 'undefined') return;
    const shouldPlay = _activeTab === 'portfolio';
    document.querySelectorAll('.pd-portfolio-preview-video').forEach((video) => {
      const isVisible = video.dataset.inview === '1';
      if (shouldPlay && isVisible) {
        const playAttempt = video.play();
        if (playAttempt && typeof playAttempt.catch === 'function') {
          playAttempt.catch(() => {});
        }
        return;
      }
      try {
        video.pause();
      } catch (_) {
        // no-op
      }
    });
  }

  function _updatePortfolioHeroMetrics(totalItems, totalSections) {
    const totalEl = document.getElementById('pd-portfolio-total');
    const sectionsEl = document.getElementById('pd-portfolio-sections-total');
    if (totalEl) totalEl.textContent = _copy('portfolioItemsCount', { count: _safeInt(totalItems) });
    if (sectionsEl) sectionsEl.textContent = _copy('portfolioSectionsCount', { count: _safeInt(totalSections) });
    _setTabMeta('portfolio', _formatTabCount(totalItems));
  }

  function _syncPortfolioEngagementTotals() {
    _portfolioLikes = _portfolioItems.reduce((sum, item) => sum + _safeInt(item.likes_count), 0);
    _portfolioSaves = _portfolioItems.reduce((sum, item) => sum + _safeInt(item.saves_count), 0);
    _portfolioSavedByMe = _portfolioItems.some((item) => !!item.is_saved);
  }

  function _updatePortfolioBadge(item) {
    const key = String(_safeInt(item?.id));
    if (!key) return;
    const root = document.querySelector('.pd-portfolio-item[data-item-id="' + key + '"]');
    if (!root) return;
    const likesEl = root.querySelector('.pd-portfolio-item-stat[data-stat="likes"]');
    const savesEl = root.querySelector('.pd-portfolio-item-stat[data-stat="saves"]');
    if (likesEl) {
      const likesCount = likesEl.querySelector('span');
      if (likesCount) likesCount.textContent = String(_safeInt(item.likes_count));
      likesEl.classList.toggle('active', _asBool(item.is_liked));
    }
    if (savesEl) {
      const savesCount = savesEl.querySelector('span');
      if (savesCount) savesCount.textContent = String(_safeInt(item.saves_count));
      savesEl.classList.toggle('active', _asBool(item.is_saved));
    }
  }

  async function _togglePortfolioLike(item, triggerBtn) {
    const outcome = await _togglePortfolioReaction(item, 'like', triggerBtn);
    if (outcome) _showToast(outcome);
  }

  async function _togglePortfolioSave(item, triggerBtn) {
    const outcome = await _togglePortfolioReaction(item, 'save', triggerBtn);
    if (outcome) _showToast(outcome);
  }

  async function _togglePortfolioReaction(item, action, triggerBtn) {
    if (!Auth.isLoggedIn()) {
      window.location.href = '/login/?next=' + encodeURIComponent(window.location.pathname + window.location.search);
      return '';
    }

    const isLike = action === 'like';
    const previousFlag = isLike ? !!item.is_liked : !!item.is_saved;
    const previousCount = _safeInt(isLike ? item.likes_count : item.saves_count);
    const nextFlag = !previousFlag;
    const nextCount = Math.max(0, previousCount + (nextFlag ? 1 : -1));

    if (isLike) {
      item.is_liked = nextFlag;
      item.likes_count = nextCount;
    } else {
      item.is_saved = nextFlag;
      item.saves_count = nextCount;
    }

    _syncPortfolioEngagementTotals();
    _updatePortfolioBadge(item);
    _recomputeEngagementView();
    _emitPortfolioEngagementUpdate(item);

    if (triggerBtn) triggerBtn.disabled = true;
    const endpoint = '/api/providers/portfolio/' + item.id + '/' + (nextFlag ? action : 'un' + action) + '/';
    const res = await ApiClient.request(_withMode(endpoint), { method: 'POST' });
    if (triggerBtn) triggerBtn.disabled = false;

    if (res.ok) {
      return isLike
        ? (nextFlag ? _copy('likeSavedAs', { mode: _getModeLabel() }) : _copy('unlikeSavedAs', { mode: _getModeLabel() }))
        : (nextFlag ? _copy('savedAsFavorite', { mode: _getModeLabel() }) : _copy('removedFromFavorites', { mode: _getModeLabel() }));
    }

    if (isLike) {
      item.is_liked = previousFlag;
      item.likes_count = previousCount;
    } else {
      item.is_saved = previousFlag;
      item.saves_count = previousCount;
    }
    _syncPortfolioEngagementTotals();
    _updatePortfolioBadge(item);
    _recomputeEngagementView();
    _emitPortfolioEngagementUpdate(item);

    if (res.status === 401) {
      window.location.href = '/login/?next=' + encodeURIComponent(window.location.pathname + window.location.search);
      return '';
    }
    return isLike ? _copy('likeUpdateFailed') : _copy('saveUpdateFailed');
  }

  function _emitPortfolioEngagementUpdate(item) {
    if (!item || typeof window === 'undefined') return;
    window.dispatchEvent(new CustomEvent('nw:portfolio-engagement-update', {
      detail: {
        id: item.id,
        provider_id: item.provider_id,
        likes_count: Number(item.likes_count) || 0,
        saves_count: Number(item.saves_count) || 0,
        comments_count: Number(item.comments_count) || 0,
        is_liked: !!item.is_liked,
        is_saved: !!item.is_saved,
      },
    }));
  }

  function _recomputeEngagementView() {
    const totalLikes = _mediaLikesTotal !== null
      ? _safeInt(_mediaLikesTotal)
      : (_safeInt(_profileLikesBase) + _safeInt(_portfolioLikes) + _safeInt(_spotlightLikes));
    _setText('stat-likes', totalLikes);

    _isBookmarked = !!(_portfolioSavedByMe || _spotlightSavedByMe);
    const bookmarkBtn = document.getElementById('btn-bookmark');
    if (!bookmarkBtn) return;
    bookmarkBtn.classList.toggle('bookmarked', _isBookmarked);
    bookmarkBtn.setAttribute('aria-label', _isBookmarked ? _copy('profileSavedAria') : _copy('profileUnsavedAria'));
    bookmarkBtn.title = _isBookmarked ? _copy('profileSavedTitle') : _copy('profileUnsavedTitle');
    const svg = bookmarkBtn.querySelector('svg');
    if (svg) svg.setAttribute('fill', _isBookmarked ? '#fff' : 'none');
  }

  function _handleBookmarkAction() {
    if (!Auth.isLoggedIn()) {
      window.location.href = '/login/?next=' + encodeURIComponent(window.location.pathname + window.location.search);
      return;
    }

    if (_isBookmarked) {
      window.location.href = '/interactive/?tab=favorites';
      return;
    }

    _switchToTab('portfolio');
    const portfolioPanel = document.getElementById('tab-portfolio');
    if (portfolioPanel && typeof portfolioPanel.scrollIntoView === 'function') {
      portfolioPanel.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
    _showToast(_copy('saveFromGalleryHint'));
  }

  function _switchToTab(nextTab) {
    _setActiveTab(nextTab, { scrollIntoView: true });
  }

  /* ═══ Reviews ═══ */
  function _extractProviderReply(review) {
    return _pickFirstText(
      review && review.provider_reply,
      review && review.providerReply,
      review && review.provider_response,
      review && review.providerResponse,
      review && review.reply
    );
  }

  function _getReviewAuthorName(review) {
    return review && (review.reviewer_name || review.client_name || review.user_name) || _copy('anonymousReviewer');
  }

  async function _openReviewerChat(review, triggerEl) {
    if (!Auth.isLoggedIn()) {
      window.location.href = '/login/?next=' + encodeURIComponent(window.location.pathname + window.location.search);
      return;
    }

    const reviewId = _safeInt(review && review.id);
    if (!reviewId) {
      _showToast(_copy('openMessagesFailed'));
      return;
    }

    if (triggerEl) triggerEl.disabled = true;
    const res = await ApiClient.request(_withMode('/api/reviews/reviews/' + reviewId + '/provider-chat-thread/'), {
      method: 'POST',
    });
    if (triggerEl) triggerEl.disabled = false;

    if (res.ok && res.data && res.data.thread_id) {
      window.location.href = '/chat/' + res.data.thread_id + '/';
      return;
    }

    _showToast((res.data && (res.data.detail || res.data.error)) || _copy('openMessagesFailed'));
  }

  function _buildReviewCard(review) {
    const card = UI.el('article', { className: 'pd-review-card' });

    const header = UI.el('div', { className: 'pd-review-header' });
    const reviewerName = _getReviewAuthorName(review);
    const authorWrap = UI.el('div', { className: 'pd-review-author-wrap' });
    const authorBtn = UI.el('button', {
      className: 'pd-review-author pd-review-author-action',
      textContent: reviewerName,
    });
    authorBtn.type = 'button';
    authorBtn.title = _copy('reviewerContactHint');
    authorBtn.setAttribute('aria-label', _copy('reviewerConversationAria', { name: reviewerName }));
    authorBtn.addEventListener('click', () => {
      _openReviewerChat(review, authorBtn);
    });
    authorWrap.appendChild(authorBtn);
    const reviewDateRaw = review.created_at || review.created;
    if (reviewDateRaw) {
      const reviewDate = new Date(reviewDateRaw);
      authorWrap.appendChild(UI.el('span', {
        className: 'pd-review-date',
        textContent: reviewDate.toLocaleDateString(_locale(), { year: 'numeric', month: 'short', day: 'numeric' }),
      }));
    }
    header.appendChild(authorWrap);
    const ratingWrap = UI.el('div', { className: 'pd-review-rating' });
    const stars = UI.el('span', { className: 'pd-review-stars' });
    const rating = Math.round(review.rating || 0);
    for (let i = 0; i < 5; i++) {
      stars.appendChild(UI.icon('star', 14, i < rating ? '#FFC107' : '#E0E0E0'));
    }
    ratingWrap.appendChild(stars);
    ratingWrap.appendChild(UI.el('span', {
      className: 'pd-review-score',
      textContent: Number.parseFloat(review.rating || 0).toFixed(1),
    }));
    header.appendChild(ratingWrap);
    card.appendChild(header);

    const reviewText = _pickFirstText(review.comment, review.text, review.review_text);
    if (reviewText) {
      const reviewEl = UI.el('div', { className: 'pd-review-text', textContent: reviewText });
      _setAutoDirection(reviewEl, reviewText);
      card.appendChild(reviewEl);
    }

    const providerReply = _extractProviderReply(review);
    if (providerReply) {
      const replyBox = UI.el('div', { className: 'pd-review-reply' });
      replyBox.appendChild(UI.el('div', {
        className: 'pd-review-reply-label',
        textContent: _copy('providerReply'),
      }));
      const replyEl = UI.el('div', {
        className: 'pd-review-reply-text',
        textContent: providerReply,
      });
      _setAutoDirection(replyEl, providerReply);
      replyBox.appendChild(replyEl);
      card.appendChild(replyBox);
    }

    return card;
  }

  function _reviewCriterionConfigs() {
    return [
      { key: 'response_speed', avgKey: 'response_speed_avg', label: _copy('reviewResponseSpeed'), shortLabel: _copy('reviewResponseSpeed'), hint: _copy('reviewResponseSpeedHint') },
      { key: 'quality', avgKey: 'quality_avg', label: _copy('reviewQuality'), shortLabel: _copy('reviewQuality'), hint: _copy('reviewQualityHint') },
      { key: 'cost_value', avgKey: 'cost_value_avg', label: _copy('reviewCostValue'), shortLabel: _copy('reviewCostValue'), hint: _copy('reviewCostValueHint') },
      { key: 'credibility', avgKey: 'credibility_avg', label: _copy('reviewCredibility'), shortLabel: _copy('reviewCredibility'), hint: _copy('reviewCredibilityHint') },
      { key: 'on_time', avgKey: 'on_time_avg', label: _copy('reviewOnTime'), shortLabel: _copy('reviewOnTime'), hint: _copy('reviewOnTimeHint') },
    ];
  }

  function _criterionToneLabel(value) {
    if (value >= 4.7) return _copy('criterionExcellent');
    if (value >= 4.2) return _copy('criterionStrong');
    if (value >= 3.5) return _copy('criterionGood');
    if (value > 0) return _copy('criterionNeedsSupport');
    return _copy('criterionNoData');
  }

  function _buildRatingCriteriaSummary(summary) {
    const items = _reviewCriterionConfigs().map((criterion) => {
      const value = Number.parseFloat(summary && summary[criterion.avgKey]);
      return {
        label: criterion.label,
        hint: criterion.hint,
        value,
      };
    }).filter((item) => Number.isFinite(item.value) && item.value > 0);

    if (!items.length) return null;

    const wrap = UI.el('div', { className: 'pd-rating-criteria-summary' });
    wrap.appendChild(UI.el('div', {
      className: 'pd-rating-criteria-title',
      textContent: _copy('ratingCriteriaTitle'),
    }));

    items.forEach((item) => {
      const row = UI.el('div', { className: 'pd-rating-criterion-row' });
      const copy = UI.el('div', { className: 'pd-rating-criterion-copy' });
      copy.appendChild(UI.el('strong', { textContent: item.label }));
      copy.appendChild(UI.el('span', { textContent: item.hint }));
      row.appendChild(copy);

      const track = UI.el('div', { className: 'pd-rating-criterion-track' });
      const bar = UI.el('div', { className: 'pd-rating-bar' });
      const fill = UI.el('div', { className: 'pd-rating-bar-fill' });
      fill.style.width = Math.max(0, Math.min(100, (item.value / 5) * 100)) + '%';
      bar.appendChild(fill);
      track.appendChild(bar);
      row.appendChild(track);

      row.appendChild(UI.el('span', {
        className: 'pd-rating-criterion-value',
        textContent: item.value.toFixed(1),
      }));

      wrap.appendChild(row);
    });

    return wrap;
  }

  async function _loadReviews() {
    const summaryEl = document.getElementById('pd-rating-summary');
    const listEl = document.getElementById('pd-reviews-list');
    const emptyEl = document.getElementById('pd-reviews-empty');
    _setTabLoadingState('reviews', true);
    let ratingCountForMeta = 0;

    const [ratingRes, reviewsRes] = await Promise.all([
      ApiClient.get('/api/reviews/providers/' + _providerId + '/rating/'),
      ApiClient.get('/api/reviews/providers/' + _providerId + '/reviews/')
    ]);

    // Rating summary
    if (ratingRes.ok && ratingRes.data && summaryEl) {
      const r = ratingRes.data;
      const ratingCount = _safeInt(r.rating_count || r.count || 0);
      ratingCountForMeta = ratingCount;
      const ratingAvgRaw = r.rating_avg !== undefined && r.rating_avg !== null ? r.rating_avg : r.average;
      const ratingAvg = Number.parseFloat(ratingAvgRaw);
      const distribution = r.distribution || {};
      summaryEl.textContent = '';
      const bigDiv = UI.el('div', { className: 'pd-rating-big' });
      bigDiv.appendChild(UI.text(ratingCount > 0 && Number.isFinite(ratingAvg) ? ratingAvg.toFixed(1) : '-'));
      bigDiv.appendChild(UI.icon('star', 24, '#FFC107'));
      summaryEl.appendChild(bigDiv);
      summaryEl.appendChild(UI.el('div', { className: 'pd-rating-count', textContent: _copy('ratingsCount', { count: ratingCount }) }));

      const criteriaSummary = _buildRatingCriteriaSummary(r);
      if (criteriaSummary) summaryEl.appendChild(criteriaSummary);
    }

    // Reviews list
    let reviews = [];
    if (reviewsRes.ok && reviewsRes.data) {
      reviews = Array.isArray(reviewsRes.data) ? reviewsRes.data : (reviewsRes.data.results || []);
    }

    if (!ratingCountForMeta) {
      ratingCountForMeta = reviews.length;
    }
    _setTabMeta('reviews', _formatTabCount(ratingCountForMeta));

    if (listEl) listEl.textContent = '';

    if (!reviews.length) {
      _setTabLoadingState('reviews', false);
      if (emptyEl) emptyEl.classList.remove('hidden');
      return;
    }

    if (emptyEl) emptyEl.classList.add('hidden');
    if (!listEl) return;

    const isCompactReviews = window.matchMedia && window.matchMedia('(max-width: 640px)').matches;
    const marqueeReviews = reviews.slice();
    const shouldUseStaticLayout = isCompactReviews || marqueeReviews.length <= 3;
    if (shouldUseStaticLayout) {
      const staticList = UI.el('div', { className: 'pd-reviews-static' });
      if (!isCompactReviews && marqueeReviews.length <= 3) {
        staticList.classList.add('pd-reviews-static-featured');
      }
      marqueeReviews.forEach((review) => {
        staticList.appendChild(_buildReviewCard(review));
      });
      listEl.appendChild(staticList);
      _setTabLoadingState('reviews', false);
      return;
    }

    const marquee = UI.el('div', { className: 'pd-reviews-marquee' });
    const track = UI.el('div', { className: 'pd-reviews-track' });
    const groupA = UI.el('div', { className: 'pd-reviews-track-group' });

    marqueeReviews.forEach((review) => {
      groupA.appendChild(_buildReviewCard(review));
    });
    const groupB = groupA.cloneNode(true);

    const totalCardsPerGroup = marqueeReviews.length;
    track.style.setProperty(
      '--pd-reviews-duration',
      Math.max(24, totalCardsPerGroup * 5) + 's'
    );
    track.appendChild(groupA);
    track.appendChild(groupB);
    marquee.appendChild(track);
    listEl.appendChild(marquee);
    _setTabLoadingState('reviews', false);
  }

  /* ═══ Helpers ═══ */

  function _safeInt(value) {
    const n = parseInt(value, 10);
    return Number.isFinite(n) ? n : 0;
  }

  function _safeNullableInt(value) {
    if (value === null || value === undefined || value === '') return null;
    const n = parseInt(value, 10);
    return Number.isFinite(n) ? n : null;
  }

  function _asBool(value) {
    if (typeof value === 'boolean') return value;
    if (typeof value === 'number') return value !== 0;
    const text = String(value || '').trim().toLowerCase();
    if (!text) return false;
    if (text === 'true' || text === '1' || text === 'yes' || text === 'y' || text === 'on') return true;
    if (text === 'false' || text === '0' || text === 'no' || text === 'n' || text === 'off') return false;
    return false;
  }

  function _trimText(value) {
    return String(value || '').trim();
  }

  function _normalizeSeoSlug(value) {
    return _trimText(value)
      .toLowerCase()
      .replace(/[^\u0600-\u06ff0-9a-z]+/gi, '-')
      .replace(/^-+|-+$/g, '');
  }

  function _providerCanonicalPath(provider) {
    const providerId = _safeInt(provider && provider.id ? provider.id : _providerId);
    if (!providerId) return '';
    const seoSlug = _normalizeSeoSlug(provider && provider.seo_slug);
    return seoSlug ? ('/provider/' + providerId + '/' + seoSlug + '/') : ('/provider/' + providerId + '/');
  }

  function _setMetaContent(id, value) {
    const node = document.getElementById(id);
    if (!node) return;
    node.setAttribute('content', _trimText(value));
  }

  function _setCanonicalUrl(url) {
    if (!url) return;
    const node = document.getElementById('page-canonical');
    if (node) node.setAttribute('href', url);
  }

  function _applySeoMeta(provider, displayName) {
    const seoTitle = _pickFirstText(provider && provider.seo_title, displayName, _copy('providerFallback'));
    const siteTitle = _siteTitle();
    const pageTitle = seoTitle ? (seoTitle + ' | ' + siteTitle) : (siteTitle + ' | ' + _copy('providerFallback'));
    const description = _pickFirstText(
      provider && provider.seo_meta_description,
      provider && provider.bio,
      provider && provider.about_details,
      displayName ? _copy('seoProviderDescription', { name: displayName }) : _copy('seoPlatformDescription')
    );
    const canonicalPath = _providerCanonicalPath(provider);
    const canonicalUrl = canonicalPath ? (window.location.origin + canonicalPath) : window.location.href;
    const imageUrl = _pickFirstText(provider && provider.cover_image, provider && provider.profile_image);
    const absoluteImageUrl = imageUrl
      ? (/^https?:\/\//i.test(imageUrl) ? imageUrl : (window.location.origin + (imageUrl.startsWith('/') ? '' : '/') + imageUrl))
      : '';

    document.title = pageTitle;
    _setMetaContent('meta-description', description);
    _setMetaContent('meta-keywords', provider && provider.seo_keywords);
    _setMetaContent('meta-og-title', pageTitle);
    _setMetaContent('meta-og-description', description);
    _setMetaContent('meta-og-url', canonicalUrl);
    _setMetaContent('meta-og-image', absoluteImageUrl);
    _setMetaContent('meta-twitter-title', pageTitle);
    _setMetaContent('meta-twitter-description', description);
    _setMetaContent('meta-twitter-image', absoluteImageUrl);
    _setCanonicalUrl(canonicalUrl);

    if (canonicalPath) {
      const currentPath = window.location.pathname.endsWith('/') ? window.location.pathname : (window.location.pathname + '/');
      if (currentPath !== canonicalPath && window.history && typeof window.history.replaceState === 'function') {
        window.history.replaceState({}, '', canonicalPath + window.location.search + window.location.hash);
      }
    }
  }

  function _pickFirstText() {
    for (let i = 0; i < arguments.length; i += 1) {
      const text = _trimText(arguments[i]);
      if (text) return text;
    }
    return '';
  }

  function _resolveMode() {
    let accountModeRaw = '';
    try {
      accountModeRaw = sessionStorage.getItem('nw_account_mode') || '';
    } catch {}
    const byAccountMode = _trimText(accountModeRaw).toLowerCase();
    if (byAccountMode === 'provider') return 'provider';
    if (byAccountMode === 'client') return 'client';
    const roleState = (typeof Auth !== 'undefined' && Auth.getRoleState)
      ? _trimText(Auth.getRoleState()).toLowerCase()
      : '';
    return roleState.includes('provider') ? 'provider' : 'client';
  }

  function _withMode(path) {
    _syncMode();
    const sep = path.includes('?') ? '&' : '?';
    return path + sep + 'mode=' + encodeURIComponent(_mode || 'client');
  }

  function _formatCompactNumber(value) {
    if (!Number.isFinite(value)) return '';
    if (Math.abs(value - Math.round(value)) < 0.0001) {
      return String(Math.round(value));
    }
    return Number(value)
      .toFixed(2)
      .replace(/0+$/, '')
      .replace(/\.$/, '');
  }

  function _uniqueNonEmpty(values) {
    const seen = new Set();
    const result = [];
    values.forEach((value) => {
      const clean = _trimText(value);
      if (!clean || seen.has(clean)) return;
      seen.add(clean);
      result.push(clean);
    });
    return result;
  }

  function _joinForDisplay(values, maxItems) {
    const list = _uniqueNonEmpty(values || []);
    const limit = Number.isFinite(maxItems) && maxItems > 0 ? maxItems : 3;
    if (!list.length) return '';
    if (list.length <= limit) return list.join('، ');
    return list.slice(0, limit).join('، ') + ' (+' + String(list.length - limit) + ')';
  }

  function _joinAllForDisplay(values) {
    const list = _uniqueNonEmpty(values || []);
    return list.length ? list.join('، ') : '';
  }

  function _normalizeComparableText(value) {
    return _trimText(String(value || '').replace(/\s+/g, ' ')).toLowerCase();
  }

  function _serviceCategoryFromService(service) {
    const subcategory = service && typeof service.subcategory === 'object' ? service.subcategory : null;
    return _pickFirstText(
      subcategory ? subcategory.category_name : '',
      subcategory ? subcategory.categoryName : '',
      service ? service.category_name : '',
      service ? service.main_category : '',
      service ? service.categoryName : '',
      service ? service.mainCategory : ''
    );
  }

  function _serviceSubCategoryFromService(service) {
    const subcategory = service && typeof service.subcategory === 'object' ? service.subcategory : null;
    return _pickFirstText(
      subcategory ? subcategory.name : '',
      subcategory ? subcategory.subcategory_name : '',
      subcategory ? subcategory.subCategoryName : '',
      service ? service.subcategory_name : '',
      service ? service.sub_category : '',
      service ? service.subCategoryName : '',
      service ? service.subCategory : ''
    );
  }

  function _providerMainCategory(provider) {
    const selectedSubcategories = provider && Array.isArray(provider.selected_subcategories)
      ? provider.selected_subcategories
      : (provider && Array.isArray(provider.selectedSubcategories) ? provider.selectedSubcategories : []);
    const selectedCategoryNames = selectedSubcategories.map((item) => _pickFirstText(
      item && item.category_name,
      item && item.categoryName
    ));
    return _joinAllForDisplay([
      provider ? provider.primary_category_name : '',
      provider ? provider.primaryCategoryName : '',
    ].concat(
      provider && Array.isArray(provider.main_categories) ? provider.main_categories : [],
      provider && Array.isArray(provider.mainCategories) ? provider.mainCategories : [],
      selectedCategoryNames,
      [
        provider ? provider.category_name : '',
        provider ? provider.main_category : '',
        provider ? provider.categoryName : '',
        provider ? provider.mainCategory : ''
      ]
    ));
  }

  function _providerSubCategory(provider) {
    const selectedSubcategories = provider && Array.isArray(provider.selected_subcategories)
      ? provider.selected_subcategories
      : (provider && Array.isArray(provider.selectedSubcategories) ? provider.selectedSubcategories : []);
    const selectedNames = selectedSubcategories.map((item) => _pickFirstText(
      item && item.name,
      item && item.subcategory_name,
      item && item.subCategoryName
    ));
    return _joinAllForDisplay([
      provider ? provider.primary_subcategory_name : '',
      provider ? provider.primarySubcategoryName : '',
    ].concat(selectedNames, [
      provider ? provider.subcategory_name : '',
      provider ? provider.sub_category : '',
      provider ? provider.subcategoryName : '',
      provider ? provider.subCategoryName : '',
      provider ? provider.subCategory : ''
    ]));
  }

  function _resolveMainCategory(provider) {
    return _providerMainCategory(provider) || _derivedMainCategory;
  }

  function _resolveSubCategory(provider) {
    return _providerSubCategory(provider) || _derivedSubCategory;
  }

  function _updateIdentityCategoryLine(mainCategory, subCategory) {
    const lineEl = document.getElementById('pd-category-line');
    if (!lineEl) return;
    lineEl.textContent = '';
    lineEl.classList.add('hidden');
  }

  function _syncCategoryViews() {
    if (!_providerData) return;
    const mainCategory = _resolveMainCategory(_providerData);
    const subCategory = _resolveSubCategory(_providerData);
    _updateIdentityCategoryLine(mainCategory, subCategory);
    _setText('pd-main-category', _displayOrUnavailable(mainCategory, _copy('unavailable')));
    _setText('pd-sub-category', _displayOrUnavailable(subCategory, _copy('unavailable')));
  }

  function _refreshDerivedCategories(services) {
    const list = Array.isArray(services) ? services : [];
    const categories = list.map((service) => _serviceCategoryFromService(service));
    const subcategories = list.map((service) => _serviceSubCategoryFromService(service));
    _derivedMainCategory = _joinAllForDisplay(categories);
    _derivedSubCategory = _joinAllForDisplay(subcategories);
  }

  function _setText(id, val) {
    const el = document.getElementById(id);
    if (el) el.textContent = val;
  }

  function _setAttr(id, name, value) {
    const el = document.getElementById(id);
    if (el) el.setAttribute(name, value);
  }

  function _setAutoDirection(target, value) {
    const el = typeof target === 'string' ? document.getElementById(target) : target;
    if (!el) return;
    if (_trimText(value)) el.setAttribute('dir', 'auto');
    else el.removeAttribute('dir');
  }

  function _addContactRow(container, iconHtml, text, href) {
    const row = UI.el(href ? 'a' : 'div', { className: 'pd-contact-row' });
    if (href) { row.href = href.startsWith('http') ? href : ('https://' + href); row.target = '_blank'; row.rel = 'noopener'; }
    const iconWrap = UI.el('span', {});
    iconWrap.innerHTML = iconHtml; // safe: from our own _svgIcon
    row.appendChild(iconWrap);
    row.appendChild(UI.el('span', { textContent: text }));
    container.appendChild(row);
  }

  function _addSocialRow(container, iconHtml, label, value, href, actionLabel) {
    const row = UI.el('div', { className: 'pd-social-row' });
    const iconWrap = UI.el('div', { className: 'pd-social-icon' });
    iconWrap.innerHTML = iconHtml;
    row.appendChild(iconWrap);

    const info = UI.el('div', { className: 'pd-social-info' });
    info.appendChild(UI.el('div', { className: 'pd-social-label', textContent: label }));
    const valueNode = UI.el('div', { className: 'pd-social-value', textContent: value });
    _setAutoDirection(valueNode, value);
    info.appendChild(valueNode);
    row.appendChild(info);

    const linkAttrs = { className: 'pd-social-link', href };
    if (!String(href || '').startsWith('mailto:')) {
      linkAttrs.target = '_blank';
      linkAttrs.rel = 'noopener';
    }
    if (actionLabel) {
      linkAttrs['aria-label'] = actionLabel;
      linkAttrs.title = actionLabel;
    }
    const link = UI.el('a', linkAttrs);
    link.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 13v6a2 2 0 01-2 2H5a2 2 0 01-2-2V8a2 2 0 012-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/></svg>';
    row.appendChild(link);
    container.appendChild(row);
  }

  function _normalizeSocialPlatform(value) {
    const text = String(value || '').trim().toLowerCase();
    if (!text) return '';
    if (text === 'twitter' || text === 'twitter_url' || text === 'x_url') return 'x';
    if (text === 'fb' || text === 'fb_url') return 'facebook';
    if (text === 'mail' || text === 'mail_to' || text === 'e-mail') return 'email';
    if (text === 'linkedin_url' || text === 'linked_in') return 'linkedin';
    if (text === 'youtube_url' || text === 'yt') return 'youtube';
    if (text === 'pinterest_url' || text === 'pin') return 'pinterest';
    if (text === 'behance_url') return 'behance';
    return text;
  }

  function _normalizeSocialLinkObject(item) {
    if (typeof item === 'string') {
      const url = item.trim();
      return url ? { url, label: '', platform: '' } : null;
    }
    if (!item || typeof item !== 'object') return null;
    const url = String(item.url || item.href || item.link || item.value || '').trim();
    if (!url) return null;
    return {
      url,
      label: String(item.label || '').trim(),
      platform: _normalizeSocialPlatform(item.platform || item.key || item.type || item.name),
    };
  }

  function _resolveSocialPlatformFromUrl(url) {
    const lower = String(url || '').trim().toLowerCase();
    if (!lower) return '';
    if (lower.indexOf('mailto:') === 0) return 'email';
    if (lower.includes('linkedin.com')) return 'linkedin';
    if (lower.includes('facebook.com') || lower.includes('fb.com')) return 'facebook';
    if (lower.includes('youtube.com') || lower.includes('youtu.be')) return 'youtube';
    if (lower.includes('instagram.com')) return 'instagram';
    if (lower.includes('x.com') || lower.includes('twitter.com')) return 'x';
    if (lower.includes('snapchat.com')) return 'snapchat';
    if (lower.includes('pinterest.com')) return 'pinterest';
    if (lower.includes('tiktok.com')) return 'tiktok';
    if (lower.includes('behance.net')) return 'behance';
    return '';
  }

  function _resolveSocialHref(url, platform) {
    const text = String(url || '').trim();
    if (!text) return '';
    if (_normalizeSocialPlatform(platform) === 'email') {
      return /^mailto:/i.test(text) ? text : ('mailto:' + text.replace(/^mailto:/i, '').trim());
    }
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(text)) return text;
    return 'https://' + text.replace(/^\/+/, '');
  }

  function _socialLabelForPlatform(platform, fallbackLabel) {
    switch (_normalizeSocialPlatform(platform)) {
      case 'linkedin': return _copy('linkedinAccount');
      case 'facebook': return _copy('facebookAccount');
      case 'youtube': return _copy('youtubeAccount');
      case 'instagram': return _copy('instagramAccount');
      case 'x': return _copy('xAccount');
      case 'snapchat': return _copy('snapchatAccount');
      case 'pinterest': return _copy('pinterestAccount');
      case 'tiktok': return _copy('tiktokAccount');
      case 'behance': return _copy('behanceAccount');
      case 'email': return _copy('emailContact');
      default: return String(fallbackLabel || '').trim() || _copy('website');
    }
  }

  function _socialActionLabel(platform) {
    return _normalizeSocialPlatform(platform) === 'email' ? _copy('sendEmail') : _copy('openLink');
  }

  function _socialIconForPlatform(platform) {
    switch (_normalizeSocialPlatform(platform)) {
      case 'linkedin': return _svgIcon('linkedin');
      case 'facebook': return _svgIcon('facebook');
      case 'youtube': return _svgIcon('youtube');
      case 'instagram': return _svgIcon('instagram');
      case 'x': return _svgIcon('x');
      case 'snapchat': return _svgIcon('snapchat');
      case 'pinterest': return _svgIcon('pinterest');
      case 'tiktok': return _svgIcon('tiktok');
      case 'behance': return _svgIcon('behance');
      case 'email': return _svgIcon('email');
      default: return _svgIcon('web');
    }
  }

  function _socialValueForDisplay(url, platform) {
    const normalizedPlatform = _normalizeSocialPlatform(platform);
    if (normalizedPlatform === 'email') {
      return String(url || '').replace(/^mailto:/i, '').trim();
    }
    const handle = _extractHandle(url);
    if (handle) return handle;
    try {
      const parsed = new URL(_resolveSocialHref(url, normalizedPlatform));
      return (parsed.hostname + parsed.pathname).replace(/^www\./i, '').replace(/\/$/, '');
    } catch (_err) {
      return String(url || '').trim();
    }
  }

  function _resolveSocialDescriptor(item) {
    const normalized = _normalizeSocialLinkObject(item);
    if (!normalized) return null;
    const platform = normalized.platform || _resolveSocialPlatformFromUrl(normalized.url);
    const href = _resolveSocialHref(normalized.url, platform);
    if (!href) return null;
    return {
      label: _socialLabelForPlatform(platform, normalized.label),
      value: _socialValueForDisplay(normalized.url, platform),
      href,
      actionLabel: _socialActionLabel(platform),
      icon: _socialIconForPlatform(platform),
    };
  }

  function _renderSocialLinks(provider, socialCard) {
    const socialList = document.getElementById('pd-social-list');
    if (!socialList) return;

    const rows = (Array.isArray(provider && provider.social_links) ? provider.social_links : [])
      .map(_resolveSocialDescriptor)
      .filter(Boolean);

    socialList.innerHTML = '';
    if (!rows.length) {
      if (socialCard) socialCard.classList.add('hidden');
      return;
    }

    if (socialCard) socialCard.classList.remove('hidden');
    rows.forEach((item) => {
      _addSocialRow(socialList, item.icon, item.label, item.value, item.href, item.actionLabel);
    });
  }

  function _extractHandle(url) {
    try {
      const uri = new URL(url.startsWith('http') ? url : ('https://' + url));
      const parts = uri.pathname.split('/').filter(Boolean);
      return parts.length ? '@' + parts[parts.length - 1] : '';
    } catch { return ''; }
  }

  function _displayOrUnavailable(value, unavailableText) {
    const text = String(value || '').trim();
    return text || unavailableText;
  }

  function _setSocialRow(kind, valueId, buttonId, unavailableText) {
    const url = String(_socialUrls[kind] || '').trim();
    const valueEl = document.getElementById(valueId);
    if (valueEl) {
      valueEl.textContent = url ? (_extractHandle(url) || url) : unavailableText;
      _setAutoDirection(valueEl, url ? (_extractHandle(url) || url) : '');
    }
    const button = document.getElementById(buttonId);
    if (!button) return;
    button.disabled = !url;
    button.classList.toggle('disabled', !url);
    button.onclick = () => {
      if (!url) return;
      const href = url.startsWith('http') ? url : ('https://' + url);
      window.open(href, '_blank', 'noopener');
    };
  }

  function _findSocialUrl(provider, keyword) {
    const socialLinks = Array.isArray(provider.social_links) ? provider.social_links : [];
    const needle = String(keyword || '').trim().toLowerCase();
    if (!needle) return '';

    for (const item of socialLinks) {
      const url = (typeof item === 'string' ? item : (item?.url || '')).toString().trim();
      if (!url) continue;
      if (url.toLowerCase().includes(needle)) return url;
    }
    return '';
  }

  function _extractPortfolioSectionTitle(caption) {
    const text = String(caption || '').trim();
    if (!text) return _copy('worksSection');
    const separators = [' - ', ' — ', ' – ', ' | ', '|'];
    for (const separator of separators) {
      const idx = text.indexOf(separator);
      if (idx > 0) return text.slice(0, idx).trim() || _copy('worksSection');
    }
    return _copy('worksSection');
  }

  function _extractPortfolioItemDescription(caption, sectionTitle) {
    const text = String(caption || '').trim();
    if (!text) return _copy('noDescriptionGeneric');
    const section = String(sectionTitle || '').trim();
    if (!section || section === _copy('worksSection')) return text;

    const separators = [' - ', ' — ', ' – ', ' | ', '|'];
    for (const separator of separators) {
      const prefix = section + separator;
      if (text.startsWith(prefix)) {
        const rest = text.slice(prefix.length).trim();
        if (rest) return rest;
      }
    }
    return text;
  }

  function _derivePortfolioMediaLabel(item, description, fileUrl) {
    const explicit = String(item?.title || item?.name || '').trim();
    if (explicit) return explicit;
    const desc = String(description || '').trim();
    if (desc && desc !== _copy('noDescriptionGeneric')) return desc;
    const rawCaption = String(item?.caption || '').trim();
    if (rawCaption) return rawCaption;
    const fromPath = String(fileUrl || '').split('?')[0].split('/').pop() || '';
    if (fromPath) return decodeURIComponent(fromPath);
    return _copy('portfolioItemFallback');
  }

  function _deriveSpotlightMediaLabel(item, rawCaption) {
    const explicit = String(item?.title || item?.name || '').trim();
    if (explicit) return explicit;
    const caption = String(rawCaption || '').trim();
    if (caption) return caption;
    const fromPath = String(item?.file_url || item?.media_url || '').split('?')[0].split('/').pop() || '';
    if (fromPath) return decodeURIComponent(fromPath);
    return _copy('highlightFallback');
  }

  function _renderModeBadge() {
    const identity = document.querySelector('.pd-identity');
    if (!identity) return;

    let badge = document.getElementById('pd-mode-badge');
    if (badge) {
      badge.remove();
    }
  }

  function _getModeLabel() {
    return _syncMode() === 'provider' ? _copy('providerMode') : _copy('clientMode');
  }

  function _resolveServiceRangeKm(provider) {
    const radiusRaw = Number(provider.coverage_radius_km);
    if (Number.isFinite(radiusRaw) && radiusRaw > 0) {
      return Math.round(radiusRaw);
    }
    return 5;
  }

  function _parseCoordinate(value) {
    if (value === null || value === undefined || value === '') return null;
    if (typeof value === 'number') return Number.isFinite(value) ? value : null;
    const normalized = String(value).trim().replace(',', '.');
    if (!normalized) return null;
    const parsed = Number.parseFloat(normalized);
    return Number.isFinite(parsed) ? parsed : null;
  }

  function _resolveServiceRangeCenter(provider) {
    const lat = _parseCoordinate(
      provider && (provider.lat ?? provider.latitude ?? provider.location_lat ?? provider.locationLat)
    );
    const lng = _parseCoordinate(
      provider && (provider.lng ?? provider.longitude ?? provider.location_lng ?? provider.locationLng)
    );
    return { lat, lng };
  }

  function _hasValidGeoPoint(lat, lng) {
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return false;
    if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return false;
    return Math.abs(lat) > 0.000001 || Math.abs(lng) > 0.000001;
  }

  function _serviceRangeSummaryText(city, rangeKm, hasMapPoint) {
    const cityText = _trimText(city);
    if (hasMapPoint) {
      if (cityText) return _copy('serviceCoverageAroundCity', { range: rangeKm, city: cityText });
      return _copy('serviceCoverageAroundProvider', { range: rangeKm });
    }
    if (cityText) {
      return _copy('serviceCoverageInCity', { range: rangeKm, city: cityText });
    }
    return _copy('noGeoPointAvailable');
  }

  function _syncServiceRangeMapSize() {
    if (!_serviceRangeMap) return;
    // Retry across animation frames so the map invalidates once the
    // surrounding shell has been laid out (mobile widths often have a
    // race between unhiding the shell and Leaflet measuring its size).
    [60, 200, 500].forEach((delay) => {
      setTimeout(() => {
        try {
          if (_serviceRangeMap) _serviceRangeMap.invalidateSize();
        } catch (_) {}
      }, delay);
    });
  }

  function _renderServiceRangeMap(provider) {
    const mapEl = document.getElementById('pd-service-range-map');
    const emptyEl = document.getElementById('pd-service-range-map-empty');
    const summaryEl = document.getElementById('pd-service-range-summary');
    if (!mapEl) return;

    const rangeKm = _resolveServiceRangeKm(provider);
    const city = UI.formatCityDisplay(
      _pickFirstText(provider && (provider.city_display || provider.city)),
      _pickFirstText(provider && (provider.region || provider.region_name))
    );
    const center = _resolveServiceRangeCenter(provider);
    const hasPoint = _hasValidGeoPoint(center.lat, center.lng);

    if (summaryEl) {
      summaryEl.textContent = _serviceRangeSummaryText(city, rangeKm, hasPoint);
    }

    if (typeof L === 'undefined') {
      mapEl.classList.add('hidden');
      if (emptyEl) {
        emptyEl.textContent = _copy('mapFailedNow');
        emptyEl.classList.remove('hidden');
      }
      return;
    }

    if (!hasPoint) {
      mapEl.classList.add('hidden');
      if (emptyEl) {
        emptyEl.textContent = _copy('mapNoExactLocation');
        emptyEl.classList.remove('hidden');
      }
      if (_serviceRangeLayer) _serviceRangeLayer.clearLayers();
      return;
    }

    mapEl.classList.remove('hidden');
    if (emptyEl) emptyEl.classList.add('hidden');

    if (!_serviceRangeMap) {
      _serviceRangeMap = L.map(mapEl, {
        scrollWheelZoom: false,
      });
      L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
        subdomains: 'abcd',
        maxZoom: 20,
        attribution: '&copy; OpenStreetMap &copy; CARTO',
      }).addTo(_serviceRangeMap);
    }

    if (!_serviceRangeMap._loaded) {
      _serviceRangeMap.setView([center.lat, center.lng], 12);
    }

    if (_serviceRangeLayer) {
      _serviceRangeLayer.clearLayers();
    } else {
      _serviceRangeLayer = L.layerGroup().addTo(_serviceRangeMap);
    }

    const radiusMeters = Math.max(1000, rangeKm * 1000);
    const circle = L.circle([center.lat, center.lng], {
      radius: radiusMeters,
      color: '#7C3AED',
      weight: 2,
      fillColor: '#8B5CF6',
      fillOpacity: 0.18,
    });
    const marker = L.circleMarker([center.lat, center.lng], {
      radius: 7,
      color: '#FFFFFF',
      weight: 2,
      fillColor: '#7C3AED',
      fillOpacity: 1,
    });

    _serviceRangeLayer.addLayer(circle);
    _serviceRangeLayer.addLayer(marker);

    const targetBounds = L.latLng(center.lat, center.lng).toBounds(radiusMeters * 2);
    if (targetBounds && targetBounds.isValid()) {
      _serviceRangeMap.fitBounds(targetBounds, { padding: [20, 20], maxZoom: 14 });
    } else {
      _serviceRangeMap.setView([center.lat, center.lng], 12);
    }

    _syncServiceRangeMapSize();
  }

  function _resolvePortfolioSections(grouped) {
    const selectedSubcategories = (_providerData && Array.isArray(_providerData.selected_subcategories))
      ? _providerData.selected_subcategories
      : [];
    const mainCategories = (_providerData && Array.isArray(_providerData.main_categories))
      ? _providerData.main_categories
      : [];
    const categoryTitles = [];
    selectedSubcategories.forEach(row => {
      const title = String(row && row.category_name || '').trim();
      if (title && !categoryTitles.includes(title)) categoryTitles.push(title);
    });
    mainCategories.forEach(title => {
      const clean = String(title || '').trim();
      if (clean && !categoryTitles.includes(clean)) categoryTitles.push(clean);
    });

    if (categoryTitles.length) {
      const categorySections = categoryTitles.map(title => ({
        sectionTitle: title,
        sectionDesc: '',
        items: grouped.get(title) || [],
      }));
      grouped.forEach((items, title) => {
        if (!categoryTitles.includes(title)) {
          categorySections.push({ sectionTitle: title, sectionDesc: '', items });
        }
      });
      return categorySections;
    }

    const rawSections = (_providerData && (_providerData.content_sections || _providerData.contentSections)) || [];
    const definedSections = Array.isArray(rawSections)
      ? rawSections.filter(section => section && typeof section === 'object')
      : [];

    if (definedSections.length) {
      const merged = new Map();
      return definedSections.map(section => {
        const title = String(section.section_title || section.title || section.name || 'أعمالي').trim() || 'أعمالي';
        const desc = String(section.section_desc || section.description || '').trim();
        if (merged.has(title)) {
          const current = merged.get(title);
          if (!current.sectionDesc && desc) current.sectionDesc = desc;
          return null;
        }
        const items = grouped.get(title) || [];
        const entry = { sectionTitle: title, sectionDesc: desc, items };
        merged.set(title, entry);
        return entry;
      }).filter(Boolean);
    }

    const results = [];
    grouped.forEach((items, title) => {
      results.push({
        sectionTitle: title,
        sectionDesc: '',
        items,
      });
    });
    return results;
  }

  function _detectPlatform(url) {
    const u = url.toLowerCase();
    if (u.includes('instagram')) return { label: _copy('instagramAccount'), icon: _svgIcon('instagram') };
    if (u.includes('x.com') || u.includes('twitter')) return { label: _copy('xAccount'), icon: _svgIcon('x') };
    if (u.includes('snapchat')) return { label: _copy('snapchatAccount'), icon: _svgIcon('snapchat') };
    if (u.includes('tiktok')) return { label: 'TikTok', icon: _svgIcon('web') };
    if (u.includes('facebook')) return { label: 'Facebook', icon: _svgIcon('web') };
    if (u.includes('youtube')) return { label: 'YouTube', icon: _svgIcon('web') };
    if (u.includes('linkedin')) return { label: 'LinkedIn', icon: _svgIcon('web') };
    return { label: _copy('website'), icon: _svgIcon('web') };
  }

  function _svgIcon(name) {
    const icons = {
      location: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#673AB7"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>',
      phone: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#673AB7"><path d="M6.62 10.79c1.44 2.83 3.76 5.14 6.59 6.59l2.2-2.2c.27-.27.67-.36 1.02-.24 1.12.37 2.32.57 3.57.57.55 0 1 .45 1 1V20c0 .55-.45 1-1 1-9.39 0-17-7.61-17-17 0-.55.45-1 1-1h3.5c.55 0 1 .45 1 1 0 1.25.2 2.45.57 3.57.11.35.03.74-.25 1.02l-2.2 2.2z"/></svg>',
      whatsapp: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#25D366"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347z"/></svg>',
      email: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#2563EB" stroke-width="2"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="M4 7l8 6 8-6"/></svg>',
      web: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#673AB7"><path d="M11.99 2C6.47 2 2 6.48 2 12s4.47 10 9.99 10C17.52 22 22 17.52 22 12S17.52 2 11.99 2zm6.93 6h-2.95a15.65 15.65 0 00-1.38-3.56A8.03 8.03 0 0118.92 8zM12 4.04c.83 1.2 1.48 2.53 1.91 3.96h-3.82c.43-1.43 1.08-2.76 1.91-3.96zM4.26 14C4.1 13.36 4 12.69 4 12s.1-1.36.26-2h3.38c-.08.66-.14 1.32-.14 2 0 .68.06 1.34.14 2H4.26zm.82 2h2.95c.32 1.25.78 2.45 1.38 3.56A7.987 7.987 0 015.08 16zm2.95-8H5.08a7.987 7.987 0 014.33-3.56A15.65 15.65 0 008.03 8zM12 19.96c-.83-1.2-1.48-2.53-1.91-3.96h3.82c-.43 1.43-1.08 2.76-1.91 3.96zM14.34 14H9.66c-.09-.66-.16-1.32-.16-2 0-.68.07-1.35.16-2h4.68c.09.65.16 1.32.16 2 0 .68-.07 1.34-.16 2zm.25 5.56c.6-1.11 1.06-2.31 1.38-3.56h2.95a8.03 8.03 0 01-4.33 3.56zM16.36 14c.08-.66.14-1.32.14-2 0-.68-.06-1.34-.14-2h3.38c.16.64.26 1.31.26 2s-.1 1.36-.26 2h-3.38z"/></svg>',
      linkedin: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none"><rect x="3" y="3" width="18" height="18" rx="4" fill="#0A66C2"/><path d="M8.1 10.2h2.3V18H8.1zm1.16-1.23a1.33 1.33 0 1 1 0-2.66 1.33 1.33 0 0 1 0 2.66zM12 10.2h2.2v1.07h.03c.31-.58 1.06-1.2 2.18-1.2 2.33 0 2.76 1.53 2.76 3.53V18h-2.3v-3.91c0-.93-.02-2.13-1.3-2.13-1.3 0-1.5 1.01-1.5 2.06V18H12z" fill="#fff"/></svg>',
      facebook: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none"><path d="M13.5 21v-7h2.4l.36-2.8H13.5V9.42c0-.81.23-1.36 1.39-1.36H16.4V5.56c-.26-.03-1.14-.11-2.18-.11-2.16 0-3.64 1.32-3.64 3.74v2.01H8.2V14h2.38v7h2.92z" fill="#1877F2"/></svg>',
      youtube: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none"><rect x="3" y="6" width="18" height="12" rx="4" fill="#FF0000"/><path d="M10 9.5l5 2.5-5 2.5z" fill="#fff"/></svg>',
      instagram: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#E1306C"><rect x="2" y="2" width="20" height="20" rx="5" fill="none" stroke="#E1306C" stroke-width="2"/><circle cx="12" cy="12" r="5" fill="none" stroke="#E1306C" stroke-width="2"/><circle cx="17.5" cy="6.5" r="1.5" fill="#E1306C"/></svg>',
      x: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#000"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/></svg>',
      snapchat: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#FFFC00"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z"/></svg>',
      pinterest: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" fill="#E60023"/><path d="M12.34 17.78c-.9 0-1.75-.48-2.04-1.03l-.58 2.24-.04.13c-.1.36-.42.61-.8.61H8l1.12-4.41c-.2-.52-.32-1.18-.32-1.82 0-2.35 1.73-4.11 4.09-4.11 2.05 0 3.39 1.46 3.39 3.3 0 2.26-1 4.09-2.55 4.09-.8 0-1.4-.67-1.22-1.48.24-.97.7-2.01.7-2.71 0-.62-.33-1.14-1.01-1.14-.8 0-1.44.83-1.44 1.94 0 .71.24 1.19.24 1.19l-.98 4.15c.72.22 1.5.34 2.31.34" fill="#fff"/></svg>',
      tiktok: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none"><path d="M14.5 3c.4 1.77 1.45 3.14 3.19 3.73v2.58a6.55 6.55 0 0 1-3.11-1v5.64a5.45 5.45 0 1 1-5.45-5.45c.3 0 .6.03.88.08v2.71a2.74 2.74 0 1 0 1.86 2.59V3h2.63z" fill="#111"/><path d="M14.5 3c.4 1.77 1.45 3.14 3.19 3.73" stroke="#25F4EE" stroke-width="1.2"/><path d="M12.64 13.88a2.74 2.74 0 1 1-2.63-3.45" stroke="#FE2C55" stroke-width="1.2"/></svg>',
      behance: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none"><rect x="3" y="5" width="18" height="14" rx="4" fill="#1769FF"/><path d="M8.2 10.1h2.42c.98 0 1.68.55 1.68 1.44 0 .75-.42 1.18-.94 1.32v.03c.74.11 1.21.7 1.21 1.56 0 1.05-.78 1.84-2.09 1.84H8.2zm1.41 2.48h.85c.46 0 .74-.23.74-.63 0-.39-.28-.62-.74-.62h-.85zm0 2.72h1.01c.54 0 .87-.27.87-.74s-.33-.73-.87-.73H9.61zM15.18 10.37h2.84v.68h-2.84zm3.23 4.18c-.08 1.29-1.1 2.11-2.56 2.11-1.68 0-2.72-1.1-2.72-2.88 0-1.77 1.05-2.91 2.68-2.91 1.6 0 2.59 1.08 2.59 2.82v.42h-3.87c.02.86.52 1.38 1.3 1.38.56 0 .96-.24 1.08-.94zm-3.79-1.29h2.47c-.03-.77-.47-1.22-1.18-1.22-.7 0-1.18.47-1.29 1.22z" fill="#fff"/></svg>',
    };
    return icons[name] || icons.web;
  }

  function _createSVG(paths, size) {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('width', size || 16);
    svg.setAttribute('height', size || 16);
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('fill', 'none');
    svg.setAttribute('stroke', 'currentColor');
    svg.setAttribute('stroke-width', '2');
    svg.innerHTML = paths;
    return svg;
  }

  function _formatPhoneE164(phone) {
    const raw = String(phone || '').trim();
    if (!raw) return '';
    const cleaned = raw.replace(/\s+/g, '');
    if (cleaned.startsWith('+')) {
      const plusDigits = cleaned.slice(1).replace(/\D+/g, '');
      return plusDigits ? ('+' + plusDigits) : '';
    }

    const digits = cleaned.replace(/\D+/g, '');
    if (!digits) return '';
    if (digits.startsWith('05') && digits.length === 10) return '+966' + digits.substring(1);
    if (digits.startsWith('5') && digits.length === 9) return '+966' + digits;
    if (digits.startsWith('9665') && digits.length === 12) return '+' + digits;
    if (digits.startsWith('009665') && digits.length === 14) return '+' + digits.substring(2);
    return cleaned;
  }

  function _normalizeWhatsappBaseUrl(raw) {
    const text = String(raw || '').trim();
    if (!text) return '';
    if (/^[\d+\s()-]+$/.test(text)) {
      const phone = _formatPhoneE164(text).replace('+', '');
      return phone ? ('https://wa.me/' + phone) : '';
    }
    let candidate = text;
    if (candidate.startsWith('wa.me/')) candidate = 'https://' + candidate;
    if (!/^https?:\/\//i.test(candidate)) candidate = 'https://' + candidate;
    try {
      const parsed = new URL(candidate);
      const host = parsed.hostname.toLowerCase();
      if (host === 'wa.me' || host.endsWith('.wa.me')) {
        const pathDigits = parsed.pathname.replace(/\D+/g, '');
        const phone = _formatPhoneE164(pathDigits).replace('+', '');
        return phone ? ('https://wa.me/' + phone) : '';
      }
      const phoneQuery = parsed.searchParams.get('phone');
      const phone = _formatPhoneE164(phoneQuery).replace('+', '');
      return phone ? ('https://wa.me/' + phone) : '';
    } catch (_) {
      const phone = _formatPhoneE164(text).replace('+', '');
      return phone ? ('https://wa.me/' + phone) : '';
    }
  }

  function _buildWhatsappChatUrl(rawUrl, fallbackPhone, message) {
    const base = _normalizeWhatsappBaseUrl(rawUrl) || _normalizeWhatsappBaseUrl(fallbackPhone);
    if (!base) return '';
    try {
      const url = new URL(base);
      url.searchParams.set('text', String(message || '').trim());
      return url.toString();
    } catch (_) {
      return base;
    }
  }

  function _ensureExcellenceMount() {
    let mount = document.getElementById('pd-excellence-badges');
    if (mount) return mount;

    const handle = document.getElementById('pd-handle');
    const categoryLine = document.getElementById('pd-category-line');
    if (!handle || !handle.parentNode) return null;

    mount = document.createElement('div');
    mount.id = 'pd-excellence-badges';
    mount.className = 'pd-excellence-badges hidden';
    if (categoryLine && categoryLine.parentNode === handle.parentNode) {
      handle.parentNode.insertBefore(mount, categoryLine);
    } else {
      handle.insertAdjacentElement('afterend', mount);
    }
    return mount;
  }

  function _normalizeExcellenceBadgeItems(value) {
    if (window.UI && typeof UI.normalizeExcellenceBadges === 'function') {
      return UI.normalizeExcellenceBadges(value);
    }
    return [];
  }

  function _getAvatarExcellenceArcLayout(count) {
    if (count <= 1) {
      return [{ left: '50%', bottom: '1px' }];
    }
    if (count === 2) {
      return [
        { left: '32%', bottom: '9px' },
        { left: '68%', bottom: '9px' },
      ];
    }
    if (count === 3) {
      return [
        { left: '18%', bottom: '15px' },
        { left: '50%', bottom: '1px' },
        { left: '82%', bottom: '15px' },
      ];
    }
    return [
      { left: '10%', bottom: '18px' },
      { left: '37%', bottom: '6px' },
      { left: '63%', bottom: '6px' },
      { left: '90%', bottom: '18px' },
    ];
  }

  function _renderAvatarExcellenceBadges(value) {
    const wrap = document.getElementById('pd-avatar-excellence-badges');
    if (!wrap) return;

    wrap.textContent = '';
    const allBadges = _normalizeExcellenceBadgeItems(value);
    const badges = allBadges.slice(0, 3);
    if (!badges.length) {
      wrap.classList.add('hidden');
      return;
    }

    const badgeNodes = [];

    badges.forEach((badge) => {
      const badgeEl = document.createElement('span');
      const badgeName = String(badge.name || badge.name_ar || badge.name_en || badge.code || '').trim();
      const badgeColor = String(badge.color || '').trim() || '#C0841A';
      const iconName = String(badge.icon || '').trim() || 'sparkles';

      badgeEl.className = 'pd-avatar-excellence-badge';
      badgeEl.setAttribute('title', badgeName || 'شارة تميز');
      badgeEl.setAttribute('aria-label', badgeName || 'شارة تميز');
      badgeEl.style.setProperty('--pd-excellence-color', badgeColor);
      badgeEl.appendChild(UI.icon(iconName, 12, '#fff'));
      wrap.appendChild(badgeEl);
      badgeNodes.push(badgeEl);
    });

    const hiddenCount = Math.max(0, allBadges.length - badges.length);
    if (hiddenCount > 0) {
      const moreEl = document.createElement('span');
      moreEl.className = 'pd-avatar-excellence-badge is-more';
      moreEl.textContent = '+' + String(hiddenCount);
      moreEl.setAttribute('title', '+' + String(hiddenCount));
      moreEl.setAttribute('aria-label', '+' + String(hiddenCount));
      wrap.appendChild(moreEl);
      badgeNodes.push(moreEl);
    }

    const layout = _getAvatarExcellenceArcLayout(badgeNodes.length);
    badgeNodes.forEach((node, index) => {
      const slot = layout[index] || layout[layout.length - 1];
      node.style.setProperty('--badge-left', slot.left);
      node.style.setProperty('--badge-bottom', slot.bottom);
    });

    wrap.classList.remove('hidden');
  }

  function _renderExcellenceBadgeShowcase(value) {
    const mount = _ensureExcellenceMount();
    if (!mount) return;

    mount.textContent = '';
    const badges = _normalizeExcellenceBadgeItems(value);
    if (!badges.length) {
      mount.classList.add('hidden');
      mount.style.display = 'none';
      return;
    }

    const badgeRow = UI.buildExcellenceBadges(badges, {
      className: 'excellence-badges pd-excellence-chip-row',
      iconSize: 12,
    });
    if (!badgeRow) {
      mount.classList.add('hidden');
      mount.style.display = 'none';
      return;
    }

    const intro = document.createElement('div');
    intro.className = 'pd-excellence-intro';

    const title = document.createElement('strong');
    title.className = 'pd-excellence-title';
    title.textContent = _copy('excellenceBadgesTitle');

    const hint = document.createElement('p');
    hint.className = 'pd-excellence-hint';
    hint.textContent = _copy('excellenceBadgesHint');

    intro.appendChild(title);
    intro.appendChild(hint);

    mount.classList.remove('hidden');
    mount.style.display = 'grid';
    mount.appendChild(intro);
    mount.appendChild(badgeRow);
  }

  function _showToast(msg) {
    const toast = UI.el('div', {
      textContent: msg,
      style: {
        position: 'fixed', bottom: '24px', left: '50%', transform: 'translateX(-50%)',
        background: '#333', color: '#fff', padding: '10px 24px',
        borderRadius: '12px', fontSize: '13px', fontWeight: '600',
        zIndex: '9999', fontFamily: 'Cairo, sans-serif',
        boxShadow: '0 4px 20px rgba(0,0,0,0.2)'
      }
    });
    document.body.appendChild(toast);
    setTimeout(() => toast.remove(), 2500);
  }

  function _handleLanguageChange() {
    _applyStaticCopy();
    _updateFollowBtn();
    _recomputeEngagementView();
    if (_providerId) _loadAll();
  }

  function _applyStaticCopy() {
    _setAttr('btn-back', 'aria-label', _copy('back'));
    _setAttr('btn-bookmark', 'aria-label', _copy('save'));
    _setAttr('btn-share', 'aria-label', _copy('share'));
    _setAttr('pd-verified-badge-blue', 'aria-label', _copy('blueVerification'));
    _setAttr('pd-verified-badge-green', 'aria-label', _copy('greenVerification'));
    _setText('btn-back-to-map', _returnNav?.label || _copy('return'));
    _setAttr('btn-back-to-map', 'aria-label', _returnNav?.label || _copy('return'));
    _setAttr('pd-overview-strip', 'aria-label', _copy('overview'));
    _setText('pd-overview-city-label', _copy('city'));
    _setText('pd-overview-experience-label', _copy('experience'));
    _setText('pd-overview-range-label', _copy('serviceRange'));
    _setText('stat-completed-label', _copy('completedRequests'));
    _setText('stat-followers-label', _copy('followers'));
    _setText('stat-likes-label', _copy('likes'));
    _setText('stat-rating-label', _copy('rating'));
    _setAttr('pd-connections-row', 'aria-label', _copy('followLinks'));
    _setAttr('btn-show-followers', 'aria-label', _copy('showFollowers'));
    _setAttr('btn-show-following', 'aria-label', _copy('showFollowing'));
    _setText('pd-followers-label', _copy('followersLabel'));
    _setText('pd-followers-hint', _copy('viewList'));
    _setText('pd-following-label', _copy('followingLabel'));
    _setText('pd-following-hint', _copy('viewList'));
    _setText('pd-highlights-title', _copy('highlightsTitle'));
    _setText('pd-highlights-hint', _copy('swipeHint'));
    _setText('pd-request-service-text', _copy('requestService'));
    _setAttr('btn-request-service', 'aria-label', _copy('requestService'));
    _setAttr('btn-request-service', 'title', _copy('requestService'));
    _setAttr('btn-message', 'aria-label', _copy('message'));
    _setAttr('btn-message', 'title', _copy('message'));
    _setAttr('btn-call', 'aria-label', _copy('call'));
    _setAttr('btn-call', 'title', _copy('call'));
    _setAttr('btn-whatsapp', 'aria-label', _copy('whatsapp'));
    _setAttr('btn-whatsapp', 'title', _copy('whatsapp'));
    _setAttr('pd-tabs', 'aria-label', _copy('tabsAria'));
    _setText('pd-tab-text-profile', _copy('profileTab'));
    _setText('pd-tab-text-services', _copy('servicesTab'));
    _setText('pd-tab-text-portfolio', _copy('portfolioTab'));
    _setText('pd-tab-text-reviews', _copy('reviewsTab'));
    _setText('pd-bio-title', _copy('bioTitle'));
    _setText('pd-provider-type-label', _copy('accountType'));
    _setText('pd-main-category-label', _copy('mainServiceCategory'));
    _setText('pd-sub-category-label', _copy('specialization'));
    _setText('pd-experience-label', _copy('yearsExperience'));
    _setText('pd-whatsapp-label', _copy('whatsappNumber'));
    _setText('pd-website-label', _copy('website'));
    _setAttr('pd-website-open', 'aria-label', _copy('openWebsite'));
    _setText('pd-city-label', _copy('city'));
    _setText('pd-service-range-title', _copy('mapTitle'));
    _setAttr('pd-service-range-map', 'aria-label', _copy('mapAria'));
    _setText('pd-social-title', _copy('socialAccounts'));
    _setText('pd-social-instagram-label', _copy('instagramAccount'));
    _setText('pd-social-x-label', _copy('xAccount'));
    _setText('pd-social-snapchat-label', _copy('snapchatAccount'));
    _setAttr('pd-social-open-instagram', 'aria-label', _copy('openInstagram'));
    _setAttr('pd-social-open-x', 'aria-label', _copy('openX'));
    _setAttr('pd-social-open-snapchat', 'aria-label', _copy('openSnapchat'));
    _setText('pd-services-empty-title', _copy('servicesEmptyTitle'));
    _setText('pd-services-empty-subtitle', _copy('servicesEmptySubtitle'));
    _setText('pd-portfolio-empty-title', _copy('portfolioEmptyTitle'));
    _setText('pd-portfolio-empty-subtitle', _copy('portfolioEmptySubtitle'));
    _setText('pd-reviews-empty-text', _copy('reviewsEmpty'));
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

  function _locale() {
    return _currentLang() === 'en' ? 'en-US' : 'ar-SA';
  }

  function _siteTitle() {
    try {
      if (window.NawafethI18n && typeof window.NawafethI18n.t === 'function') {
        return window.NawafethI18n.t('siteTitle');
      }
    } catch (_) {}
    return _currentLang() === 'en' ? 'Nawafeth' : 'نوافــذ';
  }

  function _copy(key, replacements) {
    const bundle = COPY[_currentLang()] || COPY.ar;
    const template = Object.prototype.hasOwnProperty.call(bundle, key) ? bundle[key] : COPY.ar[key];
    return _replaceTokens(template, replacements);
  }

  function _replaceTokens(text, replacements) {
    if (typeof text !== 'string' || !replacements) return text;
    return text.replace(/\{(\w+)\}/g, (_, token) => (
      Object.prototype.hasOwnProperty.call(replacements, token) ? String(replacements[token]) : ''
    ));
  }

  function _escapeHtml(value) {
    return String(value || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  // Boot
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else { init(); }

  return {};
})();
