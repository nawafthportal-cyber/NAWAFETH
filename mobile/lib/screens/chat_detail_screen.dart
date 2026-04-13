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
import '../services/marketplace_service.dart';
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
    with SingleTickerProviderStateMixin {
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
  static const Duration _liveSyncInterval = Duration(seconds: 2);

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

  String get _connectionStatusText {
    if (_isChatConnected) return 'متصل';
    if (_isReconnecting) return 'جارٍ إعادة الاتصال...';
    return 'غير متصل';
  }

  bool get _isChatWithClient => widget.peerProviderId == null;

  bool get _canShowProviderClientActions =>
      !_isAutomatedPlatformThread &&
      _isProviderAccount &&
      _isChatWithClient &&
      (widget.peerId ?? 0) > 0;

  bool get _isAutomatedPlatformThread => _isSystemThread;

  bool get _isReplyRestricted =>
      _replyRestrictedToMe || _isAutomatedPlatformThread;

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

  String get _memberPhone {
    final value = (widget.peerPhone ?? '').trim();
    return value.isNotEmpty ? value : 'غير متوفر';
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
    if (_isReplyRestricted) return _replyRestrictionMessage;
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

  int? _toIntOrNull(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  Future<void> _initAccountContext() async {
    final isProvider = await AccountModeService.isProviderMode();
    int? providerId;
    if (isProvider) {
      final meRes = await ApiClient.get('/api/accounts/me/?mode=provider');
      if (meRes.isSuccess && meRes.dataAsMap != null) {
        providerId = _toIntOrNull(meRes.dataAsMap!['provider_profile_id']);
      }
    }
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
      } catch (_) {
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
        _replyRestrictedToMe = threadState.replyRestrictedToMe;
        _replyRestrictionReason = threadState.replyRestrictionReason;
        _systemSenderLabel = threadState.systemSenderLabel;
        _isSystemThread = threadState.isSystemThread;
        if (_isReplyRestricted) {
          _pendingType = null;
          _pendingFile = null;
          _pendingDuration = null;
          _recordSeconds = 0;
        }
        if (_systemSenderLabel.trim().isNotEmpty) {
          _peerNameOverride = _systemSenderLabel.trim();
        }
      });
    } catch (_) {}
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

  void _startLiveSync() {
    _liveSyncTimer?.cancel();
    if (_resolvedThreadId == null) return;

    _liveSyncTimer = Timer.periodic(_liveSyncInterval, (_) {
      if (!mounted || _resolvedThreadId == null) return;
      if (_isLoading || _isLoadingMore || _isSending || _isRefreshingMessages) {
        return;
      }
      _refreshMessages(liveSync: true);
    });
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

    try {
      final page = await MessagingService.fetchMessages(_resolvedThreadId!);
      if (!mounted) return;
      final normalizedMessages = page.messages.reversed.toList();
      _syncPeerLabelFromMessages(normalizedMessages);
      setState(() {
        _messages = normalizedMessages;
        _hasMore = page.hasMore;
        _isLoading = false;
        _isChatConnected = true;
        _isReconnecting = false;
      });

      unawaited(_markThreadReadAndRefresh());
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'فشل تحميل الرسائل';
        _isChatConnected = false;
        _isReconnecting = false;
      });
    }
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

    final page = await MessagingService.fetchMessages(
      _resolvedThreadId!,
      offset: _messages.length,
    );

    if (!mounted) return;
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
      final page =
          await MessagingService.fetchMessages(_resolvedThreadId!, limit: 30);
      if (!mounted) return;

      final updatedMessages = page.messages.reversed.toList();
      final updatedLastId =
          updatedMessages.isNotEmpty ? updatedMessages.last.id : null;
      final hasNewMessages = updatedMessages.length != previousCount ||
          updatedLastId != previousLastId;
        _syncPeerLabelFromMessages(updatedMessages);

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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isChatConnected = false;
        _isReconnecting = false;
      });
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
    } catch (_) {}

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
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F0F172A),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'إضافة مرفق',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'اختر نوع المرفق الذي تريد إرساله ضمن نفس المحادثة.',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF667085),
                ),
              ),
              const SizedBox(height: 12),
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F0F172A),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _memberName,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _peerSubtitle,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF667085),
                ),
              ),
              const SizedBox(height: 12),
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
                label: 'تحديث المفضلة',
                caption: 'إضافة أو إزالة المحادثة من المفضلة',
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await MessagingService.toggleFavorite(_resolvedThreadId!);
                  if (!mounted) return;
                  _snack('تم تحديث المفضلة');
                },
              ),
              _buildSheetActionItem(
                icon: Icons.block_rounded,
                label: 'حظر العضو',
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
                label: 'أرشفة المحادثة',
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await MessagingService.toggleArchive(_resolvedThreadId!);
                  if (!mounted) return;
                  _snack('تمت أرشفة المحادثة');
                  Navigator.pop(context);
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
    final rootContext = context;
    showDialog(
      context: rootContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text("حظر العضو",
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: Text(
          "هل أنت متأكد من حظر ${widget.peerName}؟ \n\nلن يتمكن من مراسلتك بعد ذلك.",
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
              final success =
                  await MessagingService.toggleBlock(_resolvedThreadId!);
              if (!rootContext.mounted) return;
              ScaffoldMessenger.of(rootContext).showSnackBar(
                SnackBar(
                  content: Text(
                    success ? "تم حظر العضو بنجاح" : "فشل الحظر",
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                  backgroundColor: success ? Colors.red : Colors.grey,
                ),
              );
              if (success && rootContext.mounted) {
                Navigator.pop(rootContext); // العودة لقائمة المحادثات
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("حظر",
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
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
                  ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
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
        : Colors.deepPurple.withValues(alpha: 0.07);
    final border = isMe
        ? Colors.white.withValues(alpha: 0.25)
        : Colors.deepPurple.withValues(alpha: 0.22);
    final iconBg = isMe
        ? Colors.white.withValues(alpha: 0.2)
        : Colors.deepPurple.withValues(alpha: 0.12);
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
                          CircularProgressIndicator(color: Colors.deepPurple),
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
                              color: Colors.deepPurple,
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F0F172A),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isMe ? 'خيارات رسالتك' : 'خيارات الرسالة',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
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
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF667085),
                ),
              ),
              const SizedBox(height: 12),
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
    final isMe = msg.senderId == _myUserId;
    final systemLabel = msg.senderTeamName.trim().isNotEmpty
        ? msg.senderTeamName.trim()
        : msg.senderName.trim();

    final accent = isMe ? const Color(0xFF5B3FD0) : const Color(0xFF22577A);
    final bubbleColor = isMe
        ? const Color(0xFF5B3FD0)
        : (msg.isSystemGenerated
            ? const Color(0xFFF6F1FF)
            : const Color(0xFFFFFFFF));
    final textColor = isMe ? Colors.white : const Color(0xFF0F172A);
    final metaColor = isMe
        ? Colors.white.withValues(alpha: 0.76)
        : const Color(0xFF667085);

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
                      : const Color(0xFFF7FAFC),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPlayingThisMessage
                          ? Icons.stop_circle
                          : Icons.play_circle_fill,
                      color: isMe ? Colors.white : Colors.deepPurple,
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
                          ? const Color(0xFFE4D7FF)
                          : const Color(0xFFE4EBF1),
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

  // ✅ معاينة قبل الإرسال
  Widget _buildPreview() {
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFDCE6ED)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFE9F2F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF22577A), size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _pendingAttachmentTitle,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    fileName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10.8,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF667085),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Color(0xFFB42318)),
              onPressed: () => setState(() {
                _pendingType = null;
                _pendingFile = null;
                _pendingDuration = null;
              }),
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
      style: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        hintText: _isReplyRestricted ? _replyRestrictionMessage : 'اكتب رسالة...',
        hintStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF98A2B3),
        ),
        border: InputBorder.none,
      ),
      onChanged: (_) => setState(() => _pendingType = 'text'),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: const Color(0xFFE5E7EB))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFE4EBF1)),
              ),
              child: Text(
                _formatMessageDay(date),
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF667085),
                ),
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: const Color(0xFFE5E7EB))),
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: danger ? const Color(0xFFFFF1F1) : const Color(0xFFF4F8FB),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: danger ? const Color(0xFFB42318) : const Color(0xFF22577A),
          size: 20,
        ),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: danger ? const Color(0xFFB42318) : const Color(0xFF0F172A),
        ),
      ),
      subtitle: caption == null
          ? null
          : Text(
              caption,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10.8,
                fontWeight: FontWeight.w700,
                color: Color(0xFF667085),
              ),
            ),
      onTap: onTap,
    );
  }

  Widget _buildHeroCard(bool isDark) {
    final headerActions = <Widget>[
      if (_canShowProviderClientActions)
        _buildHeroActionButton(
          icon: Icons.assignment_outlined,
          label: 'طلبات العميل',
          onTap: _showClientRequestsSheet,
        ),
      if (_canShowProviderClientActions)
        _buildHeroActionButton(
          icon: Icons.send_outlined,
          label: 'رابط الطلب',
          onTap: _sendServiceRequestLink,
        ),
      if (!_isAutomatedPlatformThread)
        _buildHeroActionButton(
          icon: Icons.more_horiz_rounded,
          label: 'خيارات',
          onTap: _showChatOptions,
        ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF183B64), Color(0xFF22577A), Color(0xFF0F766E)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C223D).withValues(alpha: 0.16),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -42,
            left: -18,
            child: Container(
              width: 136,
              height: 136,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            bottom: -54,
            right: -22,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 54,
                    width: 54,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Center(
                      child: Text(
                        _memberName.isNotEmpty ? _memberName[0] : 'م',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _memberName,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _peerSubtitle,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            height: 1.8,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.84),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildHeroChip(
                    icon: Icons.wifi_tethering_rounded,
                    label: _connectionStatusText,
                  ),
                  if (!_isAutomatedPlatformThread)
                    _buildHeroChip(
                      icon: Icons.phone_outlined,
                      label: _memberPhone,
                    ),
                  if (!_isAutomatedPlatformThread)
                    _buildHeroChip(
                      icon: Icons.location_on_outlined,
                      label: _memberCity,
                    ),
                  if (_isAutomatedPlatformThread)
                    _buildHeroChip(
                      icon: Icons.shield_outlined,
                      label: 'رسائل آلية',
                    ),
                ],
              ),
              if (headerActions.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: headerActions,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.8,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    Color background = const Color(0xFFEAF7F9);
    Color border = const Color(0xFFCCE0F8);
    Color foreground = const Color(0xFF22577A);
    IconData icon = Icons.info_outline_rounded;
    String text = _composerSupportText;

    if (_isReplyRestricted) {
      background = const Color(0xFFFFF4E5);
      border = const Color(0xFFF4C27A);
      foreground = const Color(0xFF9A5A00);
      icon = Icons.lock_outline_rounded;
      text = _replyRestrictionMessage;
    } else if (!_isChatConnected) {
      background = const Color(0xFFFFF1F1);
      border = const Color(0xFFF3C0C4);
      foreground = const Color(0xFFB42318);
      icon = Icons.cloud_off_rounded;
      text = _isReconnecting
          ? 'جاري إعادة الاتصال بالمحادثة...'
          : 'الاتصال بالمحادثة غير مستقر حالياً.';
    } else if (_isRecording) {
      background = const Color(0xFFFFF1F1);
      border = const Color(0xFFF3C0C4);
      foreground = const Color(0xFFB42318);
      icon = Icons.mic_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11.5,
                height: 1.7,
                fontWeight: FontWeight.w800,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesSurface(bool isDark) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF22577A)),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade400),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF667085),
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _loadMessages,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22577A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
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
                  size: 62, color: Colors.grey.shade400),
              const SizedBox(height: 14),
              Text(
                'لا توجد رسائل بعد',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'ابدأ المحادثة بإرسال رسالة أو مرفق بشكل مباشر.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  height: 1.8,
                  fontWeight: FontWeight.w700,
                  color: isDark ? const Color(0xFF92A6BA) : const Color(0xFF52637A),
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
          child: ListView.builder(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              final showDivider =
                  index == 0 || !_isSameMessageDay(_messages[index - 1].createdAt, message.createdAt);
              return Column(
                children: [
                  if (showDivider) _buildDayDivider(message.createdAt),
                  _buildMessageBubble(message),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildComposer(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132637) : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0x220E5E85),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C223D).withValues(alpha: isDark ? 0.10 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _composerSupportText,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.8,
              fontWeight: FontWeight.w800,
              color: _isReplyRestricted
                  ? const Color(0xFFB42318)
                  : (isDark ? const Color(0xFFB8C7D9) : const Color(0xFF52637A)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildComposerRoundButton(
                icon: Icons.attach_file_rounded,
                background: const Color(0xFFEAF7F9),
                foreground: const Color(0xFF22577A),
                onPressed: _isReplyRestricted ? null : _showAttachmentOptions,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF102231) : const Color(0xFFF7FAFC),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFDCE6ED)),
                  ),
                  child: _isRecording
                      ? Row(
                          children: [
                            const Icon(Icons.mic_rounded, color: Color(0xFFB42318)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: LinearProgressIndicator(
                                value: (_recordSeconds % 10) / 10,
                                color: const Color(0xFFB42318),
                                backgroundColor: const Color(0xFFFEE4E2),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _formatDuration(_recordSeconds),
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFB42318),
                              ),
                            ),
                          ],
                        )
                      : _buildPreview(),
                ),
              ),
              const SizedBox(width: 8),
              _buildComposerRoundButton(
                icon: _isRecording ? Icons.stop_rounded : Icons.mic_none_rounded,
                background: _isRecording ? const Color(0xFFB42318) : const Color(0xFF5B3FD0),
                foreground: Colors.white,
                onPressed: _isRecording ? _stopRecording : (_isReplyRestricted ? null : _startRecording),
              ),
              const SizedBox(width: 8),
              _buildComposerRoundButton(
                icon: Icons.send_rounded,
                background: const Color(0xFF22577A),
                foreground: Colors.white,
                isLoading: _isSending,
                onPressed: (_isReplyRestricted || _isSending) ? null : _sendMessage,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0E1726) : const Color(0xFFF2F7FB),
      appBar: PlatformTopBar(
        pageLabel: 'الرسائل',
        showBackButton: Navigator.of(context).canPop(),
        showChatAction: false,
        notificationCount: _notificationUnread,
        onNotificationsTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const NotificationsScreen(),
            ),
          );
          await UnreadBadgeService.refresh(force: true);
        },
        trailingActions: const [],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? const LinearGradient(
                  colors: [Color(0xFF0E1726), Color(0xFF122235), Color(0xFF17293D)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
              : const LinearGradient(
                  colors: [Color(0xFFEEF5FB), Color(0xFFF4F7FB), Color(0xFFF7F8FC)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: _buildEntrance(0, _buildHeroCard(isDark)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: _buildEntrance(1, _buildStatusBanner()),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: _buildEntrance(
                    2,
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF132637)
                            : Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : const Color(0x220E5E85),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0C223D)
                                .withValues(alpha: isDark ? 0.10 : 0.06),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: _buildMessagesSurface(isDark),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: _buildEntrance(3, _buildComposer(isDark)),
              ),
            ],
          ),
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
