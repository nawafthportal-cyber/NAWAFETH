import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat_message_model.dart';
import '../models/service_request_model.dart';
import '../services/messaging_service.dart';
import '../services/auth_service.dart';
import '../services/account_mode_service.dart';
import '../services/api_client.dart';
import '../services/app_logger.dart';
import '../services/marketplace_service.dart';
import '../services/providers_api_service.dart';
import '../constants/app_theme.dart';
import '../services/unread_badge_service.dart';
import '../widgets/platform_top_bar.dart';
import 'notifications_screen.dart';
import 'provider_dashboard/provider_order_details_screen.dart';
import 'service_request_form_screen.dart';

class ChatDetailScreen extends StatefulWidget {
  final int? threadId;
  final String peerName;
  final String? peerPhone;
  final String? peerCity;
  final int? peerId;
  final int? peerProviderId;

  const ChatDetailScreen({
    super.key,
    this.threadId,
    required this.peerName,
    this.peerPhone,
    this.peerCity,
    this.peerId,
    this.peerProviderId,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen>
  with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  late final AnimationController _entranceController;

  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _timer;
  Timer? _liveSyncTimer;
  bool _isRefreshingMessages = false;
  static const Duration _liveSyncBaseInterval = Duration(seconds: 6);
  static const Duration _liveSyncMaxInterval = Duration(seconds: 30);
  int _liveSyncFailures = 0;
  bool _isForeground = true;

  String? _pendingType;
  dynamic _pendingFile;
  int? _pendingDuration;

  // ✅ بيانات API
  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int? _myUserId;
  int? _resolvedThreadId;
  String? _errorMessage;
  bool _recorderInitialized = false;
  bool _playerInitialized = false;
  int? _playingMessageId;
  bool _isChatConnected = true;
  bool _isReconnecting = false;
  bool _isProviderAccount = false;
  int? _myProviderProfileId;
  bool _isFavorite = false;
  bool _isArchived = false;
  bool _isBlocked = false;
  bool _isBlockedByOther = false;
  String _favoriteLabel = '';
  bool _replyRestrictedToMe = false;
  bool _isSystemThread = false;
  String _replyRestrictionReason = '';
  String _systemSenderLabel = '';
  String _peerNameOverride = '';
  int _notificationUnread = 0;
  ValueListenable<UnreadBadges>? _badgeHandle;
  static final RegExp _serviceRequestUrlRegex = RegExp(
    r'(https?:\/\/[^\s]+|\/service-request\/?[^\s]*)',
    caseSensitive: false,
  );
  static final RegExp _paymentUrlRegex = RegExp(
    r'(https?:\/\/[^\s]*(?:promotion|promo-payment|subscription|verification)[^\s]*|\/(?:promotion|promo-payment|subscription|verification)(?:\/[^\s]*)?)',
    caseSensitive: false,
  );

  bool get _isChatWithClient => widget.peerProviderId == null;

  bool get _canShowProviderClientActions =>
      !_isAutomatedPlatformThread &&
      _isProviderAccount &&
      _isChatWithClient &&
      (widget.peerId ?? 0) > 0;

  bool get _isAutomatedPlatformThread => _isSystemThread;

  bool get _isReplyRestricted =>
      _replyRestrictedToMe || _isAutomatedPlatformThread;

    bool get _isComposerDisabled =>
      _isReplyRestricted || _isBlocked || _isBlockedByOther;

  String get _replyRestrictionMessage {
    final reason = _replyRestrictionReason.trim();
    if (reason.isNotEmpty) return reason;
    final label = _systemSenderLabel.trim();
    if (label.isNotEmpty) {
      return 'الردود مغلقة لهذه الرسائل من $label.';
    }
    return 'الردود مغلقة لهذه الرسائل الآلية.';
  }

  String get _systemThreadDisplayName {
    final label = _systemSenderLabel.trim();
    if (label.isNotEmpty) return label;
    final override = _peerNameOverride.trim();
    if (override.isNotEmpty) return override;
    final fallback = widget.peerName.trim();
    if (fallback.isNotEmpty) return fallback;
    return 'فريق المنصة';
  }

  String get _memberName {
    if (_isAutomatedPlatformThread) {
      return _systemThreadDisplayName;
    }
    final value = _peerNameOverride.trim().isNotEmpty
        ? _peerNameOverride.trim()
        : widget.peerName.trim();
    return value.isNotEmpty ? value : 'عضو';
  }

  String get _memberCity {
    final value = (widget.peerCity ?? '').trim();
    return value.isNotEmpty ? value : 'غير متوفر';
  }

  String get _peerSubtitle {
    if (_isAutomatedPlatformThread) {
      return 'رسائل آلية من $_systemThreadDisplayName';
    }
    if (_replyRestrictedToMe) {
      return 'الردود مقيدة لهذه المحادثة';
    }
    if (_canShowProviderClientActions) {
      return 'عميل يتابع معك مباشرة داخل المنصة';
    }
    if ((widget.peerProviderId ?? 0) > 0) {
      return _memberCity == 'غير متوفر'
          ? 'مقدم خدمة على المنصة'
          : 'مقدم خدمة في $_memberCity';
    }
    return 'رسائل مباشرة داخل نوافذ';
  }

  String get _composerSupportText {
    if (_isBlockedByOther) {
      return 'لا يمكنك إرسال رسائل لأن الطرف الآخر قام بحظرك.';
    }
    if (_isBlocked) {
      return 'قمت بحظر هذا العضو. أزل الحظر من خيارات الرسائل للمتابعة.';
    }
    if (_isReplyRestricted) return _replyRestrictionMessage;
    if (_isArchived) {
      return 'هذه الرسائل مؤرشفة وستعود تلقائياً عند إرسال رسالة جديدة.';
    }
    if (_isRecording) {
      return 'جارٍ تسجيل رسالة صوتية لمدة ${_formatDuration(_recordSeconds)}';
    }
    if (_hasPendingAttachment) {
      return 'المرفق جاهز. يمكنك إضافة وصف مختصر ثم الإرسال.';
    }
    if (_controller.text.trim().isNotEmpty) {
      return 'الرسالة جاهزة للإرسال.';
    }
    if (_canShowProviderClientActions) {
      return 'يمكنك إرسال نصوص أو مرفقات أو رابط طلب خدمة مباشر لهذا العميل.';
    }
    return 'يمكنك إرسال نصوص ومرفقات بشكل مباشر.';
  }

  String get _pendingAttachmentTitle {
    if (_pendingType == 'image') return 'صورة جاهزة للإرسال';
    if (_pendingType == 'audio') {
      final duration = _pendingDuration == null
          ? ''
          : ' (${_formatDuration(_pendingDuration!)})';
      return 'رسالة صوتية$duration';
    }
    if (_pendingType == 'video') return 'فيديو جاهز للإرسال';
    return 'ملف جاهز للإرسال';
  }

  bool get _hasPendingAttachment =>
      _pendingType != null && _pendingType != 'text' && _pendingFile is File;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scrollController.addListener(_onScroll);
    _badgeHandle = UnreadBadgeService.acquire();
    _badgeHandle?.addListener(_handleBadgeChange);
    _handleBadgeChange();
    _resolvedThreadId = widget.threadId;
    _initAccountContext();
    _initChat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceController.forward();
      }
    });
  }

  void _handleBadgeChange() {
    final badges = _badgeHandle?.value ?? UnreadBadges.empty;
    if (!mounted) return;
    setState(() {
      _notificationUnread = badges.notifications;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground =
        state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    _isForeground = isForeground;
    if (!isForeground) {
      _liveSyncTimer?.cancel();
      return;
    }
    if (_resolvedThreadId != null) {
      _startLiveSync(immediate: true);
    }
  }

  Future<void> _initAccountContext() async {
    final isProvider = await AccountModeService.isProviderMode();
    final providerId = isProvider
        ? await ProvidersApiService.fetchCurrentProviderProfileId()
        : null;
    if (!mounted) return;
    setState(() {
      _isProviderAccount = isProvider;
      _myProviderProfileId = providerId;
    });
  }

  Future<void> _initChat() async {
    _myUserId = await AuthService.getUserId();

    // إذا لم يكن لدينا threadId، نحاول إنشاء/جلب محادثة عبر peerProviderId
    if (_resolvedThreadId == null && widget.peerProviderId != null) {
      try {
        _resolvedThreadId = await MessagingService.getOrCreateDirectThread(
            widget.peerProviderId!);
      } catch (error, stackTrace) {
        AppLogger.warn(
          'ChatDetailScreen._initChat getOrCreateDirectThread failed',
          error: error,
          stackTrace: stackTrace,
        );
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'فشل فتح المحادثة';
        });
        return;
      }
    }

    if (_resolvedThreadId == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'لا يمكن فتح هذه المحادثة';
      });
      return;
    }

    await _loadThreadState();
    await _loadMessages();
    _startLiveSync();
  }

  Future<void> _loadThreadState() async {
    final threadId = _resolvedThreadId;
    if (threadId == null) return;

    try {
      final threadState = await MessagingService.fetchThreadState(threadId);
      if (!mounted || threadState == null) return;
      setState(() {
        _isFavorite = threadState.isFavorite;
        _favoriteLabel = threadState.favoriteLabel.trim();
        _isArchived = threadState.isArchived;
        _isBlocked = threadState.isBlocked;
        _isBlockedByOther = threadState.blockedByOther;
        _replyRestrictedToMe = threadState.replyRestrictedToMe;
        _replyRestrictionReason = threadState.replyRestrictionReason;
        _systemSenderLabel = threadState.systemSenderLabel;
        _isSystemThread = threadState.isSystemThread;
        if (_isComposerDisabled) {
          _pendingType = null;
          _pendingFile = null;
          _pendingDuration = null;
          _recordSeconds = 0;
        }
        if (_systemSenderLabel.trim().isNotEmpty) {
          _peerNameOverride = _systemSenderLabel.trim();
        }
      });
    } catch (error, stackTrace) {
      AppLogger.warn(
        'ChatDetailScreen._loadThreadState failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _syncPeerLabelFromMessages(List<ChatMessage> messages) {
    for (final message in messages.reversed) {
      if (message.senderId == _myUserId) continue;
      final teamName = message.senderTeamName.trim();
      final senderName = message.senderName.trim();
      final nextName = teamName.isNotEmpty ? teamName : senderName;
      if (nextName.isEmpty) continue;
      _peerNameOverride = nextName;
      return;
    }
    if (_systemSenderLabel.trim().isNotEmpty) {
      _peerNameOverride = _systemSenderLabel.trim();
    }
  }

  void _startLiveSync({bool immediate = false}) {
    _liveSyncTimer?.cancel();
    if (_resolvedThreadId == null || !_isForeground) return;
    if (immediate) {
      unawaited(_refreshMessages(liveSync: true));
    }
    _scheduleNextLiveSync();
  }

  void _scheduleNextLiveSync() {
    _liveSyncTimer?.cancel();
    if (_resolvedThreadId == null || !_isForeground) {
      return;
    }
    _liveSyncTimer = Timer(_currentLiveSyncInterval, () async {
      _liveSyncTimer = null;
      if (!mounted || _resolvedThreadId == null || !_isForeground) {
        return;
      }
      if (!_isLoading && !_isLoadingMore && !_isSending && !_isRefreshingMessages) {
        await _refreshMessages(liveSync: true);
      }
      if (mounted) {
        _scheduleNextLiveSync();
      }
    });
  }

  Duration get _currentLiveSyncInterval {
    final cappedFailures = _liveSyncFailures < 0
        ? 0
        : (_liveSyncFailures > 2 ? 2 : _liveSyncFailures);
    final factor = <int>[1, 2, 4][cappedFailures];
    final seconds = _liveSyncBaseInterval.inSeconds * factor;
    return Duration(
      seconds: seconds > _liveSyncMaxInterval.inSeconds
          ? _liveSyncMaxInterval.inSeconds
          : seconds,
    );
  }

  void _markLiveSyncSuccess() {
    _liveSyncFailures = 0;
  }

  void _markLiveSyncFailure() {
    if (_liveSyncFailures < 3) {
      _liveSyncFailures += 1;
    }
  }

  Future<void> _loadMessages() async {
    if (_resolvedThreadId == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      if (!_isChatConnected) {
        _isReconnecting = true;
      }
    });

    final result = await MessagingService.fetchMessagesResult(_resolvedThreadId!);
    if (!mounted) return;
    if (result.hasError) {
      _markLiveSyncFailure();
      setState(() {
        _isLoading = false;
        _errorMessage = result.errorMessage ?? 'فشل تحميل الرسائل';
        _isChatConnected = false;
        _isReconnecting = false;
      });
      return;
    }
    final page = result.page;
    final normalizedMessages = page.messages.reversed.toList();
    _syncPeerLabelFromMessages(normalizedMessages);
    _markLiveSyncSuccess();
    setState(() {
      _messages = normalizedMessages;
      _hasMore = page.hasMore;
      _isLoading = false;
      _isChatConnected = true;
      _isReconnecting = false;
    });

    unawaited(_markThreadReadAndRefresh());
    _scrollToBottom();
  }

  void _onScroll() {
    if (_scrollController.position.pixels <= 50 &&
        _hasMore &&
        !_isLoadingMore) {
      _loadOlderMessages();
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_resolvedThreadId == null) return;
    setState(() => _isLoadingMore = true);

    final result = await MessagingService.fetchMessagesResult(
      _resolvedThreadId!,
      offset: _messages.length,
    );

    if (!mounted) return;
    if (result.hasError) {
      setState(() => _isLoadingMore = false);
      _snack(result.errorMessage ?? 'تعذر تحميل الرسائل الأقدم');
      return;
    }
    final page = result.page;
    final olderMessages = page.messages.reversed.toList();
    setState(() {
      _messages.insertAll(0, olderMessages);
      _hasMore = page.hasMore;
      _isLoadingMore = false;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    if (_isSending) return;

    final text = _controller.text.trim();
    final hasPendingFile =
        _pendingType != null && _pendingType != 'text' && _pendingFile is File;

    if (text.isEmpty && !hasPendingFile) return;
    if (_resolvedThreadId == null) return;
    if (_isReplyRestricted) {
      _snack(_replyRestrictionMessage, backgroundColor: Colors.orange);
      return;
    }

    setState(() => _isSending = true);

    SendResult result;

    if (hasPendingFile && _pendingFile is File) {
      String attachmentType = 'file';
      if (_pendingType == 'image') attachmentType = 'image';
      if (_pendingType == 'audio') attachmentType = 'audio';

      result = await MessagingService.sendAttachment(
        _resolvedThreadId!,
        body: text.isNotEmpty ? text : null,
        file: _pendingFile as File,
        attachmentType: attachmentType,
      );
    } else {
      result = await MessagingService.sendTextMessage(_resolvedThreadId!, text);
    }

    if (!mounted) return;
    setState(() => _isSending = false);

    if (result.success) {
      _controller.clear();
      setState(() {
        _pendingType = null;
        _pendingFile = null;
        _pendingDuration = null;
        _recordSeconds = 0;
        _isChatConnected = true;
        _isReconnecting = false;
      });
      await _refreshMessages(forceScroll: true);
    } else {
      final errorText = result.error ?? 'فشل إرسال الرسالة';
      if (errorText.contains('الردود مغلقة')) {
        setState(() {
          _replyRestrictedToMe = true;
          _replyRestrictionReason = errorText;
        });
      }
      if (mounted) {
        setState(() {
          _isChatConnected = false;
          _isReconnecting = false;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorText,
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// تحديث الرسائل بدون إعادة التحميل الكامل
  Future<void> _refreshMessages({
    bool liveSync = false,
    bool forceScroll = false,
  }) async {
    if (_resolvedThreadId == null || _isRefreshingMessages) return;

    _isRefreshingMessages = true;
    final wasNearBottom = _isNearBottom();
    final previousCount = _messages.length;
    final previousLastId = _messages.isNotEmpty ? _messages.last.id : null;

    if (_isChatConnected == false && mounted) {
      setState(() {
        _isReconnecting = true;
      });
    }
    try {
      final result = await MessagingService.fetchMessagesResult(
        _resolvedThreadId!,
        limit: 30,
      );
      if (!mounted) return;
      if (result.hasError) {
        _markLiveSyncFailure();
        setState(() {
          _isChatConnected = false;
          _isReconnecting = false;
        });
        return;
      }

      final page = result.page;

      final updatedMessages = page.messages.reversed.toList();
      final updatedLastId =
          updatedMessages.isNotEmpty ? updatedMessages.last.id : null;
      final hasNewMessages = updatedMessages.length != previousCount ||
          updatedLastId != previousLastId;
      _syncPeerLabelFromMessages(updatedMessages);
      _markLiveSyncSuccess();

      setState(() {
        _messages = updatedMessages;
        _hasMore = page.hasMore;
        _isChatConnected = true;
        _isReconnecting = false;
      });

      if (hasNewMessages) {
        unawaited(_markThreadReadAndRefresh());
      }

      if (forceScroll || (hasNewMessages && (wasNearBottom || !liveSync))) {
        _scrollToBottom();
      }
    } finally {
      _isRefreshingMessages = false;
    }
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final remaining = _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    return remaining <= 140;
  }

  Future<void> _markThreadReadAndRefresh() async {
    final threadId = _resolvedThreadId;
    if (threadId == null) {
      return;
    }
    final marked = await MessagingService.markRead(threadId);
    if (marked) {
      await UnreadBadgeService.refresh(force: true);
    }
  }

  void _snack(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        backgroundColor: backgroundColor,
      ),
    );
  }

  Future<bool> _ensureRecorderReady() async {
    if (_recorderInitialized) return true;
    try {
      final permission = await Permission.microphone.request();
      if (permission != PermissionStatus.granted) {
        _snack('يجب السماح بالوصول إلى الميكروفون',
            backgroundColor: Colors.red);
        return false;
      }
      await _recorder.openRecorder();
      _recorderInitialized = true;
      return true;
    } catch (_) {
      _snack('تعذر تهيئة التسجيل الصوتي', backgroundColor: Colors.red);
      return false;
    }
  }

  Future<bool> _ensurePlayerReady() async {
    if (_playerInitialized) return true;
    try {
      await _player.openPlayer();
      _playerInitialized = true;
      return true;
    } catch (_) {
      _snack('تعذر تهيئة تشغيل الصوت', backgroundColor: Colors.red);
      return false;
    }
  }

  Future<void> _stopAudioPlayback({bool refreshUi = true}) async {
    try {
      if (_playerInitialized && _player.isPlaying) {
        await _player.stopPlayer();
      }
    } catch (error, stackTrace) {
      AppLogger.warn(
        'ChatDetailScreen._stopAudioPlayback failed',
        error: error,
        stackTrace: stackTrace,
      );
    }

    if (refreshUi && mounted) {
      setState(() => _playingMessageId = null);
    } else {
      _playingMessageId = null;
    }
  }

  // ✅ التسجيل الصوتي
  Future<void> _startRecording() async {
    if (_isRecording) return;
    if (_isReplyRestricted) {
      _snack(_replyRestrictionMessage, backgroundColor: Colors.orange);
      return;
    }
    final isRecorderReady = await _ensureRecorderReady();
    if (!isRecorderReady || !mounted) return;

    try {
      await _stopAudioPlayback(refreshUi: false);
      final path =
          '${Directory.systemTemp.path}${Platform.pathSeparator}chat_audio_${DateTime.now().millisecondsSinceEpoch}.aac';
      await _recorder.startRecorder(
        toFile: path,
        codec: Codec.aacADTS,
      );

      _timer?.cancel();
      setState(() {
        _isRecording = true;
        _pendingType = null;
        _pendingFile = null;
        _pendingDuration = null;
        _recordSeconds = 0;
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _recordSeconds++);
      });
    } catch (_) {
      _timer?.cancel();
      if (!mounted) return;
      setState(() => _isRecording = false);
      _snack('تعذر بدء التسجيل الصوتي', backgroundColor: Colors.red);
    }
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    try {
      final path = await _recorder.stopRecorder();
      if (!mounted) return;

      if (path == null || path.isEmpty) {
        setState(() {
          _isRecording = false;
          _pendingType = null;
          _pendingFile = null;
          _pendingDuration = null;
          _recordSeconds = 0;
        });
        _snack('لم يتم حفظ الرسالة الصوتية', backgroundColor: Colors.red);
        return;
      }

      setState(() {
        _isRecording = false;
        _pendingType = "audio";
        _pendingFile = File(path);
        _pendingDuration = _recordSeconds;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _pendingType = null;
        _pendingFile = null;
        _pendingDuration = null;
        _recordSeconds = 0;
      });
      _snack('تعذر إيقاف التسجيل الصوتي', backgroundColor: Colors.red);
    }
  }

  Future<void> _toggleAudioPlayback(ChatMessage msg) async {
    final fullUrl = ApiClient.buildMediaUrl(msg.attachmentUrl);
    if (fullUrl == null || fullUrl.isEmpty) {
      _snack('ملف الرسالة الصوتية غير متوفر', backgroundColor: Colors.red);
      return;
    }

    final isPlayerReady = await _ensurePlayerReady();
    if (!isPlayerReady) return;

    try {
      if (_playingMessageId == msg.id && _player.isPlaying) {
        await _stopAudioPlayback();
        return;
      }

      await _stopAudioPlayback(refreshUi: false);
      if (mounted) {
        setState(() => _playingMessageId = msg.id);
      } else {
        _playingMessageId = msg.id;
      }

      await _player.startPlayer(
        fromURI: fullUrl,
        whenFinished: () {
          if (!mounted) {
            _playingMessageId = null;
            return;
          }
          setState(() => _playingMessageId = null);
        },
      );
    } catch (_) {
      await _stopAudioPlayback();
      _snack('تعذر تشغيل الرسالة الصوتية', backgroundColor: Colors.red);
    }
  }

  // ✅ اختيار صورة من المعرض
  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _pendingType = "image";
        _pendingFile = File(picked.path);
      });
    }
  }

  // ✅ تصوير صورة من الكاميرا
  Future<void> _takePhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera);
    if (picked != null) {
      setState(() {
        _pendingType = "image";
        _pendingFile = File(picked.path);
      });
    }
  }

  // ✅ اختيار ملف
  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() {
        _pendingType = "file";
        _pendingFile = File(result.files.single.path!);
      });
    }
  }

  // ✅ تسجيل فيديو
  Future<void> _recordVideo() async {
    final picked = await ImagePicker().pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 3),
    );
    if (picked != null) {
      setState(() {
        _pendingType = "video";
        _pendingFile = File(picked.path);
      });
    }
  }

  // ✅ اختيار فيديو من المعرض
  Future<void> _pickVideoFromGallery() async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _pendingType = "video";
        _pendingFile = File(picked.path);
      });
    }
  }

  // ✅ خيارات المرفقات
  void _showAttachmentOptions() {
    if (_isReplyRestricted) {
      _snack(_replyRestrictionMessage, backgroundColor: Colors.orange);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          decoration: BoxDecoration(
            color: Theme.of(sheetContext).brightness == Brightness.dark
                ? AppColors.cardDark
                : AppColors.cardLight,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            boxShadow: AppShadows.elevated,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'إضافة مرفق',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: AppTextStyles.h2,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(sheetContext).brightness == Brightness.dark
                      ? AppTextStyles.textPrimaryDark
                      : AppTextStyles.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'اختر نوع المرفق الذي تريد إرساله ضمن نفس المحادثة.',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: AppTextStyles.caption,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(sheetContext).brightness == Brightness.dark
                      ? AppTextStyles.textSecondaryDark
                      : AppTextStyles.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              _buildSheetActionItem(
                icon: Icons.image_outlined,
                label: 'اختيار صورة من المعرض',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage();
                },
              ),
              _buildSheetActionItem(
                icon: Icons.camera_alt_outlined,
                label: 'تصوير صورة',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _takePhoto();
                },
              ),
              _buildSheetActionItem(
                icon: Icons.videocam_outlined,
                label: 'تسجيل فيديو',
                caption: 'الحد الأقصى 3 دقائق',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _recordVideo();
                },
              ),
              _buildSheetActionItem(
                icon: Icons.video_library_outlined,
                label: 'اختيار فيديو من المعرض',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickVideoFromGallery();
                },
              ),
              _buildSheetActionItem(
                icon: Icons.insert_drive_file_outlined,
                label: 'اختيار ملف',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ خيارات المحادثة من الشريط العلوي
  void _showChatOptions() {
    if (_isAutomatedPlatformThread) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          decoration: BoxDecoration(
            color: Theme.of(sheetContext).brightness == Brightness.dark
                ? AppColors.cardDark
                : AppColors.cardLight,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            boxShadow: AppShadows.elevated,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _memberName,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: AppTextStyles.h2,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(sheetContext).brightness == Brightness.dark
                      ? AppTextStyles.textPrimaryDark
                      : AppTextStyles.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _peerSubtitle,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: AppTextStyles.caption,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(sheetContext).brightness == Brightness.dark
                      ? AppTextStyles.textSecondaryDark
                      : AppTextStyles.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              _buildSheetActionItem(
                icon: Icons.mark_chat_read_rounded,
                label: 'اجعلها مقروءة',
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _markThreadReadAndRefresh();
                  _snack('تم تمييز المحادثة كمقروءة');
                },
              ),
              _buildSheetActionItem(
                icon: Icons.star_rounded,
                label: _isFavorite ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
                caption: _favoriteLabel.isNotEmpty
                    ? _favoriteLabel
                    : 'تحديث حالة المحادثة في المفضلة',
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await MessagingService.toggleFavorite(
                    _resolvedThreadId!,
                    remove: _isFavorite,
                  );
                  await _loadThreadState();
                  if (!mounted) return;
                  _snack('تم تحديث المفضلة');
                },
              ),
              _buildSheetActionItem(
                icon: Icons.block_rounded,
                label: _isBlocked ? 'إلغاء الحظر' : 'حظر العضو',
                danger: true,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showBlockConfirmation();
                },
              ),
              _buildSheetActionItem(
                icon: Icons.report_gmailerrorred_rounded,
                label: 'الإبلاغ عن عضو',
                danger: true,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showReportDialog();
                },
              ),
              _buildSheetActionItem(
                icon: Icons.archive_outlined,
                label: _isArchived ? 'إلغاء الأرشفة' : 'أرشفة المحادثة',
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final wasArchived = _isArchived;
                  await MessagingService.toggleArchive(
                    _resolvedThreadId!,
                    remove: wasArchived,
                  );
                  await _loadThreadState();
                  if (!mounted) return;
                  _snack(
                    wasArchived
                        ? 'تم إلغاء أرشفة المحادثة'
                        : 'تمت أرشفة المحادثة',
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ تأكيد الحظر — يستدعي API
  void _showBlockConfirmation() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _isBlocked ? "إلغاء الحظر" : "حظر العضو",
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        content: Text(
          _isBlocked
              ? "هل تريد إلغاء حظر ${widget.peerName}؟\n\nسيتمكن من مراسلتك مجددًا بعد ذلك."
              : "هل أنت متأكد من حظر ${widget.peerName}؟ \n\nلن يتمكن من مراسلتك بعد ذلك.",
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("إلغاء", style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final wasBlocked = _isBlocked;
              final success =
                  await MessagingService.toggleBlock(
                    _resolvedThreadId!,
                    remove: wasBlocked,
                  );
              if (!mounted) return;
              if (success) {
                await _loadThreadState();
              }
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? (wasBlocked
                            ? "تم إلغاء الحظر بنجاح"
                            : "تم حظر العضو بنجاح")
                        : (wasBlocked ? "فشل إلغاء الحظر" : "فشل الحظر"),
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                  backgroundColor: success ? Colors.red : Colors.grey,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(
              _isBlocked ? "إلغاء الحظر" : "حظر",
              style: const TextStyle(fontFamily: 'Cairo', color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ الإبلاغ — يرسل للباكند
  void _showReportDialog() {
    String? selectedReason;
    final TextEditingController detailsController = TextEditingController();
    bool isSending = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("إبلاغ عن المحادثة",
              style:
                  TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("المستخدم:",
                    style: TextStyle(
                        fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                Text(widget.peerName,
                    style: const TextStyle(fontFamily: 'Cairo')),
                const SizedBox(height: 16),
                const Text("سبب الإبلاغ:",
                    style: TextStyle(
                        fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedReason,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  hint: const Text("اختر السبب",
                      style: TextStyle(fontFamily: 'Cairo')),
                  items: [
                    "محتوى غير لائق",
                    "تحرش أو إزعاج",
                    "احتيال أو نصب",
                    "محتوى مسيء",
                    "انتهاك الخصوصية",
                    "أخرى",
                  ]
                      .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(r,
                                style: const TextStyle(fontFamily: 'Cairo')),
                          ))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedReason = v),
                ),
                const SizedBox(height: 16),
                const Text("تفاصيل إضافية (اختياري):",
                    style: TextStyle(
                        fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: detailsController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: "أضف تفاصيل إضافية...",
                    hintStyle: TextStyle(fontFamily: 'Cairo'),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("إلغاء",
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: isSending
                  ? null
                  : () async {
                      if (selectedReason == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("يرجى اختيار سبب الإبلاغ",
                                style: TextStyle(fontFamily: 'Cairo')),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }
                      setDialogState(() => isSending = true);
                      final result = await MessagingService.report(
                        _resolvedThreadId!,
                        reason: selectedReason!,
                        details: detailsController.text.trim().isNotEmpty
                            ? detailsController.text.trim()
                            : null,
                      );
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            result.success
                                ? "تم إرسال البلاغ بنجاح"
                                : result.error ?? "فشل الإرسال",
                            style: const TextStyle(fontFamily: 'Cairo'),
                          ),
                          backgroundColor:
                              result.success ? Colors.green : Colors.red,
                        ),
                      );
                    },
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: isSending
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text("إرسال",
                      style:
                          TextStyle(fontFamily: 'Cairo', color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ إرسال رابط طلب خدمة من المزوّد إلى العميل
  Future<void> _sendServiceRequestLink() async {
    if (_isSending) return;
    if (_isReplyRestricted) {
      _snack(_replyRestrictionMessage, backgroundColor: Colors.orange);
      return;
    }
    if (!_canShowProviderClientActions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'هذا الإجراء متاح فقط في محادثة المزوّد مع العميل',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
      return;
    }
    if (_resolvedThreadId == null) return;

    final providerId = _myProviderProfileId;
    if (providerId == null || providerId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر تحديد معرف المزوّد لإرسال الرابط',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final link =
        'https://www.nawafthportal.com/service-request/?provider_id=$providerId';
    final body = 'طلب خدمة مباشر:\n$link';

    setState(() => _isSending = true);
    final result =
        await MessagingService.sendTextMessage(_resolvedThreadId!, body);
    if (!mounted) return;
    setState(() => _isSending = false);

    if (result.success) {
      await _refreshMessages();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم إرسال رابط طلب الخدمة',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.error ?? 'فشل إرسال رابط الطلب',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  _ServiceRequestPayload? _extractServiceRequestPayload(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) return null;

    final match = _serviceRequestUrlRegex.firstMatch(text);
    if (match == null) return null;

    final rawUrl = match.group(0)?.trim() ?? '';
    if (rawUrl.isEmpty) return null;

    Uri? uri;
    try {
      uri = Uri.parse(rawUrl);
    } catch (_) {
      uri = null;
    }

    if (uri == null || !uri.hasScheme) {
      final normalized = rawUrl.startsWith('/') ? rawUrl : '/$rawUrl';
      uri = Uri.tryParse('https://www.nawafthportal.com$normalized');
    }
    if (uri == null) return null;

    final path = uri.path.toLowerCase();
    if (path != '/service-request' && path != '/service-request/') return null;

    final providerIdRaw = (uri.queryParameters['provider_id'] ?? '').trim();
    final providerId = int.tryParse(providerIdRaw);
    if (providerId == null || providerId <= 0) return null;

    final helperText =
        text.replaceFirst(rawUrl, '').replaceAll(RegExp(r'\s+'), ' ').trim();

    return _ServiceRequestPayload(
      providerId: providerId.toString(),
      helperText: helperText,
    );
  }

  Future<void> _openServiceRequestFromMessage(
      _ServiceRequestPayload payload) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceRequestFormScreen(
          providerId: payload.providerId,
        ),
      ),
    );
  }

  Widget _buildServiceRequestAction(
      _ServiceRequestPayload payload, bool isMe, Color textColor) {
    final bg = isMe
        ? Colors.white.withValues(alpha: 0.15)
        : AppColors.primary.withValues(alpha: 0.07);
    final border = isMe
        ? Colors.white.withValues(alpha: 0.25)
        : AppColors.primary.withValues(alpha: 0.22);
    final iconBg = isMe
        ? Colors.white.withValues(alpha: 0.2)
        : AppColors.primarySurface;
    final subTextColor = isMe ? Colors.white70 : Colors.black54;

    return InkWell(
      onTap: () => _openServiceRequestFromMessage(payload),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.assignment_turned_in_outlined,
                size: 18,
                color: textColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'طلب خدمة',
                    style: TextStyle(
                      color: textColor,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'اضغط هنا لإرسال طلبك لهذا المزوّد',
                    style: TextStyle(
                      color: subTextColor,
                      fontFamily: 'Cairo',
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_left, color: textColor, size: 18),
          ],
        ),
      ),
    );
  }

  bool _isPaymentUrl(String text) {
    return _paymentUrlRegex.hasMatch(text);
  }

  Widget _buildPaymentCTA(String body, bool isMe, Color textColor) {
    final match = _paymentUrlRegex.firstMatch(body);
    final url = match?.group(0)?.trim() ?? '';
    final helperText = body.replaceFirst(url, '').trim();

    final bg = isMe
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.green.withValues(alpha: 0.07);
    final border = isMe
        ? Colors.white.withValues(alpha: 0.25)
        : Colors.green.withValues(alpha: 0.22);
    final iconBg = isMe
        ? Colors.white.withValues(alpha: 0.2)
        : Colors.green.withValues(alpha: 0.12);
    final subColor = isMe ? Colors.white70 : Colors.black54;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (helperText.isNotEmpty) ...[
          Text(helperText,
              style: TextStyle(
                  color: textColor, fontFamily: 'Cairo', fontSize: 15)),
          const SizedBox(height: 8),
        ],
        InkWell(
          onTap: () {
            final uri = url.startsWith('http')
                ? Uri.tryParse(url)
                : Uri.tryParse('https://www.nawafthportal.com$url');
            if (uri != null) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text('💳', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'صفحة الدفع',
                        style: TextStyle(
                          color: textColor,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'اضغط هنا للانتقال إلى صفحة الدفع',
                        style: TextStyle(
                          color: subColor,
                          fontFamily: 'Cairo',
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left, color: textColor, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _requestStatusColor(String statusGroup) {
    switch (statusGroup) {
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'in_progress':
        return Colors.orange;
      case 'new':
        return Colors.amber.shade800;
      default:
        return Colors.grey;
    }
  }

  String _formatRequestDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString();
    return '$d/$m/$y';
  }

  bool _isAssignedToCurrentProvider(ServiceRequest request) {
    final myProviderId = _myProviderProfileId;
    if (myProviderId == null || myProviderId <= 0) return false;
    return request.provider == myProviderId;
  }

  Future<void> _openProviderRequestDetailsFromSheet(
    BuildContext sheetContext,
    ServiceRequest request,
  ) async {
    if (!_isAssignedToCurrentProvider(request)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'يمكن فتح تفاصيل الطلبات المسندة لك فقط',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    Navigator.pop(sheetContext);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderOrderDetailsScreen(requestId: request.id),
      ),
    );
  }

  void _showClientRequestsSheet() {
    final clientUserId = widget.peerId;
    if (clientUserId == null || clientUserId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر تحديد العميل لعرض طلباته',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.78,
              child: FutureBuilder<List<ServiceRequest>>(
                future: MarketplaceService.getProviderRequests(
                  clientUserId: clientUserId,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary),
                    );
                  }

                  if (snapshot.hasError) {
                    return const Center(
                      child: Text(
                        'تعذر تحميل طلبات العميل',
                        style:
                            TextStyle(fontFamily: 'Cairo', color: Colors.grey),
                      ),
                    );
                  }

                  final all = [...(snapshot.data ?? const <ServiceRequest>[])];
                  all.sort((a, b) => b.createdAt.compareTo(a.createdAt));

                  final current = all
                      .where((r) =>
                          r.statusGroup != 'completed' &&
                          r.statusGroup != 'cancelled')
                      .toList();
                  final previous = all
                      .where((r) =>
                          r.statusGroup == 'completed' ||
                          r.statusGroup == 'cancelled')
                      .toList();

                  if (all.isEmpty) {
                    return const Center(
                      child: Text(
                        'لا توجد طلبات لهذا العميل',
                        style:
                            TextStyle(fontFamily: 'Cairo', color: Colors.grey),
                      ),
                    );
                  }

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.assignment_outlined,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'طلبات العميل: ${widget.peerName}',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                          children: [
                            if (current.isNotEmpty) ...[
                              const Text(
                                'الطلبات الحالية',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...current.map(
                                (req) => Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    onTap: () =>
                                        _openProviderRequestDetailsFromSheet(
                                      sheetContext,
                                      req,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          _requestStatusColor(req.statusGroup)
                                              .withValues(alpha: 0.14),
                                      child: Icon(
                                        Icons.assignment,
                                        color: _requestStatusColor(
                                            req.statusGroup),
                                        size: 18,
                                      ),
                                    ),
                                    title: Text(
                                      '${req.displayId} • ${req.statusLabel}',
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${req.title}\n${_formatRequestDate(req.createdAt)}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontFamily: 'Cairo', fontSize: 11),
                                    ),
                                    trailing: const Icon(Icons.chevron_left),
                                    isThreeLine: true,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            if (previous.isNotEmpty) ...[
                              const Text(
                                'الطلبات السابقة',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...previous.map(
                                (req) => Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    onTap: () =>
                                        _openProviderRequestDetailsFromSheet(
                                      sheetContext,
                                      req,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          _requestStatusColor(req.statusGroup)
                                              .withValues(alpha: 0.14),
                                      child: Icon(
                                        req.statusGroup == 'completed'
                                            ? Icons.check_circle_outline
                                            : Icons.cancel_outlined,
                                        color: _requestStatusColor(
                                            req.statusGroup),
                                        size: 18,
                                      ),
                                    ),
                                    title: Text(
                                      '${req.displayId} • ${req.statusLabel}',
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${req.title}\n${_formatRequestDate(req.createdAt)}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontFamily: 'Cairo', fontSize: 11),
                                    ),
                                    trailing: const Icon(Icons.chevron_left),
                                    isThreeLine: true,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // ✅ خيارات الرسالة (حذف/نسخ)
  void _showMessageOptions(ChatMessage msg) {
    final isMe = msg.senderId == _myUserId;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          decoration: BoxDecoration(
            color: Theme.of(sheetContext).brightness == Brightness.dark
                ? AppColors.cardDark
                : AppColors.cardLight,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            boxShadow: AppShadows.elevated,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isMe ? 'خيارات رسالتك' : 'خيارات الرسالة',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: AppTextStyles.h2,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(sheetContext).brightness == Brightness.dark
                      ? AppTextStyles.textPrimaryDark
                      : AppTextStyles.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                msg.body.trim().isNotEmpty
                    ? msg.body.trim()
                    : (msg.attachmentName.isNotEmpty
                        ? msg.attachmentName
                        : 'رسالة بمرفق'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: AppTextStyles.caption,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(sheetContext).brightness == Brightness.dark
                      ? AppTextStyles.textSecondaryDark
                      : AppTextStyles.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              if (msg.body.isNotEmpty)
                _buildSheetActionItem(
                  icon: Icons.copy_rounded,
                  label: 'نسخ النص',
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: msg.body));
                    if (!sheetContext.mounted) return;
                    Navigator.pop(sheetContext);
                    _snack('تم نسخ النص');
                  },
                ),
              if (isMe)
                _buildSheetActionItem(
                  icon: Icons.delete_outline_rounded,
                  label: 'حذف الرسالة',
                  danger: true,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final success = await MessagingService.deleteMessage(
                      _resolvedThreadId!,
                      msg.id,
                    );
                    if (success) {
                      await _refreshMessages();
                    } else {
                      _snack('فشل حذف الرسالة', backgroundColor: Colors.red);
                    }
                  },
                ),
              if (!isMe)
                _buildSheetActionItem(
                  icon: Icons.report_gmailerrorred_rounded,
                  label: 'إبلاغ عن هذه الرسالة',
                  danger: true,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showReportDialog();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ فقاعة الرسائل
  Widget _buildMessageBubble(ChatMessage msg) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMe = msg.senderId == _myUserId;
    final systemLabel = msg.senderTeamName.trim().isNotEmpty
        ? msg.senderTeamName.trim()
        : msg.senderName.trim();

    final accent = isMe ? AppColors.primaryDark : AppColors.teal;
    final bubbleColor = isMe
        ? AppColors.primary
        : (msg.isSystemGenerated
            ? (isDark ? AppColors.cardDark : const Color(0xFFF6F1FF))
            : (isDark ? AppColors.cardDark : Colors.white));
    final textColor = isMe
        ? Colors.white
        : (isDark ? AppTextStyles.textPrimaryDark : AppTextStyles.textPrimary);
    final metaColor = isMe
        ? Colors.white.withValues(alpha: 0.76)
        : (isDark ? AppTextStyles.textSecondaryDark : AppTextStyles.textSecondary);

    Widget content;

    if (msg.hasAttachment) {
      final fullUrl = ApiClient.buildMediaUrl(msg.attachmentUrl);

      if (msg.attachmentType == 'image' && fullUrl != null) {
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: CachedNetworkImage(
                imageUrl: fullUrl,
                width: 220,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: 220,
                  height: 120,
                  alignment: Alignment.center,
                  color: Colors.black.withValues(alpha: 0.06),
                  child: const Icon(Icons.broken_image_outlined, size: 42),
                ),
              ),
            ),
            if (msg.body.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                msg.body,
                style: TextStyle(
                  color: textColor,
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  height: 1.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        );
      } else if (msg.attachmentType == 'audio') {
        final isPlayingThisMessage =
            _playingMessageId == msg.id && _player.isPlaying;
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: fullUrl == null ? null : () => _toggleAudioPlayback(msg),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: isMe
                      ? Colors.white.withValues(alpha: 0.14)
                      : (isDark ? AppColors.bgDark : const Color(0xFFF7FAFC)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPlayingThisMessage
                          ? Icons.stop_circle
                          : Icons.play_circle_fill,
                      color: isMe ? Colors.white : AppColors.primary,
                      size: 32,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        isPlayingThisMessage
                            ? "إيقاف الرسالة الصوتية"
                            : (msg.attachmentName.isNotEmpty
                                ? msg.attachmentName
                                : "تشغيل الرسالة الصوتية"),
                        style: TextStyle(
                          color: isMe ? Colors.white : Colors.black87,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (msg.body.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                msg.body,
                style: TextStyle(
                  color: textColor,
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  height: 1.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        );
      } else {
        content = InkWell(
          onTap: fullUrl == null
              ? null
              : () {
                  final uri = Uri.tryParse(fullUrl);
                  if (uri != null) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: isMe
                  ? Colors.white.withValues(alpha: 0.14)
                  : const Color(0xFFF7FAFC),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.insert_drive_file_outlined, color: textColor),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    msg.attachmentName.isNotEmpty ? msg.attachmentName : 'مرفق',
                    style: TextStyle(
                      color: textColor,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.open_in_new_rounded, color: textColor, size: 18),
              ],
            ),
          ),
        );
      }
    } else {
      if (_isPaymentUrl(msg.body)) {
        content = _buildPaymentCTA(msg.body, isMe, textColor);
      } else {
        final servicePayload = _extractServiceRequestPayload(msg.body);
        if (servicePayload != null) {
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (servicePayload.helperText.isNotEmpty) ...[
                Text(
                  servicePayload.helperText,
                  style: TextStyle(
                    color: textColor,
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    height: 1.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              _buildServiceRequestAction(servicePayload, isMe, textColor),
            ],
          );
        } else {
          content = Text(
            msg.body,
            style: TextStyle(
              color: textColor,
              fontFamily: 'Cairo',
              fontSize: 13,
              height: 1.8,
              fontWeight: FontWeight.w700,
            ),
          );
        }
      }
    }

    final hour24 = msg.createdAt.hour;
    final hour = hour24 > 12 ? hour24 - 12 : hour24;
    final amPm = hour24 >= 12 ? 'م' : 'ص';
    final minute = msg.createdAt.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minute $amPm';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageOptions(msg),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
          constraints: const BoxConstraints(maxWidth: 312),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(22),
                topRight: const Radius.circular(22),
                bottomLeft: isMe ? const Radius.circular(22) : const Radius.circular(8),
                bottomRight: isMe ? const Radius.circular(8) : const Radius.circular(22),
              ),
              border: isMe
                  ? null
                  : Border.all(
                      color: msg.isSystemGenerated
                          ? (isDark ? AppColors.borderDark : const Color(0xFFE4D7FF))
                          : (isDark ? AppColors.borderDark : AppColors.borderLight),
                    ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0C223D).withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 12, 13, 10),
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMe && msg.isSystemGenerated) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        systemLabel.isNotEmpty
                            ? '$systemLabel • رسالة آلية'
                            : 'رسالة آلية',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                  content,
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: metaColor,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          msg.readByIds.isNotEmpty ? Icons.done_all : Icons.done,
                          size: 15,
                          color: msg.readByIds.length > 1
                              ? const Color(0xFF93C5FD)
                              : Colors.white70,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(bool isDark) {
    if (_hasPendingAttachment) {
      final fileName = _pendingFile is File
          ? (_pendingFile as File).path.split('/').last
          : 'مرفق';
      final icon = _pendingType == 'image'
          ? Icons.image_outlined
          : _pendingType == 'audio'
              ? Icons.mic_none_rounded
              : _pendingType == 'video'
                  ? Icons.videocam_outlined
                  : Icons.insert_drive_file_outlined;

      return Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgDark : AppColors.grey50,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
              color: isDark ? AppColors.borderDark : AppColors.borderLight),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _pendingAttachmentTitle,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: AppTextStyles.bodySm,
                      fontWeight: FontWeight.w900,
                      color: isDark
                          ? AppTextStyles.textPrimaryDark
                          : AppTextStyles.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    fileName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: AppTextStyles.micro,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppTextStyles.textSecondaryDark
                          : AppTextStyles.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: AppColors.error),
              onPressed: () => setState(() {
                _pendingType = null;
                _pendingFile = null;
                _pendingDuration = null;
              }),
              iconSize: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
          ],
        ),
      );
    }

    return TextField(
      controller: _controller,
      enabled: !_isReplyRestricted,
      minLines: 1,
      maxLines: 5,
      maxLength: MessagingService.maxMessageLength,
      inputFormatters: [
        LengthLimitingTextInputFormatter(MessagingService.maxMessageLength),
      ],
      textCapitalization: TextCapitalization.sentences,
      style: TextStyle(
        fontFamily: 'Cairo',
        fontSize: AppTextStyles.bodyLg,
        fontWeight: FontWeight.w700,
        color: isDark ? AppTextStyles.textPrimaryDark : AppTextStyles.textPrimary,
      ),
      decoration: InputDecoration(
        hintText:
            _isReplyRestricted ? _replyRestrictionMessage : 'اكتب رسالة...',
        hintStyle: TextStyle(
          fontFamily: 'Cairo',
          fontSize: AppTextStyles.bodyMd,
          fontWeight: FontWeight.w700,
          color: isDark ? AppTextStyles.textTertiaryDark : AppTextStyles.textTertiary,
        ),
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
        counterText: '',
      ),
      onChanged: (_) => setState(() {
        _pendingType = _controller.text.trim().isEmpty ? null : 'text';
      }),
    );
  }

  String _formatDuration(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  bool _isSameMessageDay(DateTime left, DateTime right) {
    return left.year == right.year && left.month == right.month && left.day == right.day;
  }

  String _formatMessageDay(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'الأمس';
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildDayDivider(DateTime date) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
              child: Container(
                  height: 1,
                  color: isDark ? AppColors.borderDark : AppColors.grey200)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? AppColors.cardDark : AppColors.grey50,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                    color: isDark
                        ? AppColors.borderDark
                        : AppColors.borderLight),
              ),
              child: Text(
                _formatMessageDay(date),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: AppTextStyles.micro,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? AppTextStyles.textSecondaryDark
                      : AppTextStyles.textSecondary,
                ),
              ),
            ),
          ),
          Expanded(
              child: Container(
                  height: 1,
                  color: isDark ? AppColors.borderDark : AppColors.grey200)),
        ],
      ),
    );
  }

  Widget _buildSheetActionItem({
    required IconData icon,
    required String label,
    String? caption,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: danger ? AppColors.errorSurface : AppColors.primarySurface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(
          icon,
          color: danger ? AppColors.error : AppColors.primary,
          size: 19,
        ),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: AppTextStyles.bodyLg,
          fontWeight: FontWeight.w800,
          color: danger
              ? AppColors.error
              : (isDark
                  ? AppTextStyles.textPrimaryDark
                  : AppTextStyles.textPrimary),
        ),
      ),
      subtitle: caption == null
          ? null
          : Text(
              caption,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: AppTextStyles.micro,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppTextStyles.textSecondaryDark
                    : AppTextStyles.textSecondary,
              ),
            ),
      onTap: onTap,
    );
  }

  // ── Compact peer header (replaces old gradient hero card) ────────────────
  Widget _buildPeerHeader(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryDark, AppColors.primaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Center(
              child: Text(
                _memberName.isNotEmpty ? _memberName[0] : 'م',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Name + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        _memberName,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: AppTextStyles.h2,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? AppTextStyles.textPrimaryDark
                              : AppTextStyles.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_isFavorite && !_isAutomatedPlatformThread) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4CC),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _favoriteLabel.isNotEmpty ? _favoriteLabel : 'مفضلة',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF9A6700),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isChatConnected
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _peerSubtitle,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: AppTextStyles.caption,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppTextStyles.textSecondaryDark
                        : AppTextStyles.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Action buttons
          if (_canShowProviderClientActions) ...[
            const SizedBox(width: 6),
            _buildHeaderIconBtn(
                Icons.assignment_outlined, _showClientRequestsSheet, isDark),
            const SizedBox(width: 5),
            _buildHeaderIconBtn(
                Icons.send_outlined, _sendServiceRequestLink, isDark),
          ],
          if (!_isAutomatedPlatformThread) ...[
            const SizedBox(width: 5),
            _buildHeaderIconBtn(
                Icons.more_horiz_rounded, _showChatOptions, isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderIconBtn(
      IconData icon, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: isDark ? AppColors.borderDark : AppColors.primarySurface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(
          icon,
          size: 17,
          color: isDark ? AppColors.grey200 : AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildStatusBanner(bool isDark) {
    // Only show when there's something meaningful to communicate
    if (!_isBlockedByOther &&
        !_isBlocked &&
        !_isArchived &&
        !_isReplyRestricted &&
        _isChatConnected &&
        !_isRecording) {
      return const SizedBox.shrink();
    }

    Color background;
    Color borderColor;
    Color fg;
    IconData icon;
    String text;

    if (_isBlockedByOther) {
      background = AppColors.errorSurface;
      borderColor = AppColors.error;
      fg = AppColors.error;
      icon = Icons.block_rounded;
      text = 'لا يمكنك إرسال رسائل لأن الطرف الآخر قام بحظرك.';
    } else if (_isBlocked) {
      background = AppColors.errorSurface;
      borderColor = AppColors.error;
      fg = AppColors.error;
      icon = Icons.block_flipped;
      text = 'قمت بحظر هذا العضو. أزل الحظر من خيارات الرسائل للمتابعة.';
    } else if (_isReplyRestricted) {
      background = AppColors.warningSurface;
      borderColor = AppColors.warning;
      fg = AppColors.warning;
      icon = Icons.lock_outline_rounded;
      text = _replyRestrictionMessage;
    } else if (_isArchived) {
      background = AppColors.primarySurface;
      borderColor = AppColors.primary;
      fg = AppColors.primary;
      icon = Icons.archive_outlined;
      text = 'هذه الرسائل مؤرشفة وستعود تلقائياً عند إرسال رسالة جديدة.';
    } else if (_isRecording) {
      background = AppColors.errorSurface;
      borderColor = AppColors.error;
      fg = AppColors.error;
      icon = Icons.mic_rounded;
      text = 'جارٍ تسجيل رسالة صوتية لمدة ${_formatDuration(_recordSeconds)}';
    } else {
      background = AppColors.errorSurface;
      borderColor = AppColors.error;
      fg = AppColors.error;
      icon = Icons.cloud_off_rounded;
      text = _isReconnecting
          ? 'جارٍ إعادة الاتصال بالمحادثة...'
          : 'الاتصال بالمحادثة غير مستقر حالياً.';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
              color: borderColor.withValues(alpha: isDark ? 0.35 : 0.55)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: AppTextStyles.caption,
                  height: 1.5,
                  fontWeight: FontWeight.w800,
                  color: isDark ? fg.withValues(alpha: 0.9) : fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesSurface(bool isDark) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: AppTextStyles.bodyMd,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppTextStyles.textSecondaryDark
                      : AppTextStyles.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _loadMessages,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(
                  'إعادة المحاولة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline_rounded,
                  size: 58, color: isDark ? AppColors.borderDark : AppColors.grey300),
              const SizedBox(height: 14),
              Text(
                'لا توجد رسائل بعد',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: AppTextStyles.h2,
                  fontWeight: FontWeight.w900,
                  color: isDark
                      ? AppTextStyles.textPrimaryDark
                      : AppTextStyles.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'ابدأ المحادثة بإرسال رسالة أو مرفق بشكل مباشر.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: AppTextStyles.bodySm,
                  height: 1.8,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppTextStyles.textSecondaryDark
                      : AppTextStyles.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (_isLoadingMore)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF22577A),
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _refreshMessages(forceScroll: false),
            color: AppColors.primary,
            child: ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final showDivider = index == 0 ||
                    !_isSameMessageDay(
                      _messages[index - 1].createdAt,
                      message.createdAt,
                    );
                return Column(
                  children: [
                    if (showDivider) _buildDayDivider(message.createdAt),
                    _buildMessageBubble(message),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComposer(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _composerSupportText,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: AppTextStyles.micro,
              fontWeight: FontWeight.w800,
              color: _isComposerDisabled
                  ? AppColors.error
                  : (isDark
                      ? AppTextStyles.textSecondaryDark
                      : AppTextStyles.textSecondary),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildComposerRoundButton(
                icon: Icons.attach_file_rounded,
                background: AppColors.primarySurface,
                foreground: AppColors.primary,
                onPressed:
                  _isComposerDisabled ? null : _showAttachmentOptions,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.bgDark : AppColors.grey50,
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    border: Border.all(
                      color: isDark
                          ? AppColors.borderDark
                          : AppColors.borderLight,
                    ),
                  ),
                  child: _isRecording
                      ? Row(
                          children: [
                            const Icon(Icons.mic_rounded,
                                color: AppColors.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: LinearProgressIndicator(
                                value: (_recordSeconds % 10) / 10,
                                color: AppColors.error,
                                backgroundColor: AppColors.errorSurface,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _formatDuration(_recordSeconds),
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w800,
                                color: AppColors.error,
                              ),
                            ),
                          ],
                        )
                      : _buildPreview(isDark),
                ),
              ),
              const SizedBox(width: 8),
              _buildComposerRoundButton(
                icon: _isRecording
                    ? Icons.stop_rounded
                    : Icons.mic_none_rounded,
                background:
                    _isRecording ? AppColors.error : AppColors.primaryDark,
                foreground: Colors.white,
                onPressed: _isRecording
                    ? _stopRecording
                  : (_isComposerDisabled ? null : _startRecording),
              ),
              const SizedBox(width: 8),
              _buildComposerRoundButton(
                icon: Icons.send_rounded,
                background: AppColors.primary,
                foreground: Colors.white,
                isLoading: _isSending,
                onPressed: (_isComposerDisabled ||
                        _isSending ||
                        (_controller.text.trim().isEmpty && !_hasPendingAttachment))
                    ? null
                    : _sendMessage,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComposerRoundButton({
    required IconData icon,
    required Color background,
    required Color foreground,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: onPressed == null ? background.withValues(alpha: 0.45) : background,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: isLoading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            : Icon(icon, color: foreground),
      ),
    );
  }

  Widget _buildEntrance(int index, Widget child) {
    final begin = (0.08 * index).clamp(0.0, 0.8).toDouble();
    final end = (begin + 0.34).clamp(0.0, 1.0).toDouble();
    final animation = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _liveSyncTimer?.cancel();
    _entranceController.dispose();
    _badgeHandle?.removeListener(_handleBadgeChange);
    if (_badgeHandle != null) {
      UnreadBadgeService.release();
      _badgeHandle = null;
    }
    if (_playerInitialized) {
      _player.closePlayer();
    }
    if (_recorderInitialized) {
      _recorder.closeRecorder();
    }
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      appBar: PlatformTopBar(
        pageLabel: 'الرسائل',
        showBackButton: Navigator.of(context).canPop(),
        showChatAction: false,
        notificationCount: _notificationUnread,
        onNotificationsTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
          );
          await UnreadBadgeService.refresh(force: true);
        },
        trailingActions: const [],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: _buildEntrance(0, _buildPeerHeader(isDark)),
            ),
            _buildStatusBanner(isDark),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: _buildEntrance(
                  1,
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.cardDark : AppColors.cardLight,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: isDark ? AppColors.borderDark : AppColors.borderLight,
                      ),
                      boxShadow: AppShadows.card,
                    ),
                    child: _buildMessagesSurface(isDark),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: _buildEntrance(2, _buildComposer(isDark)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceRequestPayload {
  final String providerId;
  final String helperText;

  const _ServiceRequestPayload({
    required this.providerId,
    required this.helperText,
  });
}
