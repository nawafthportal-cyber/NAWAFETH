import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../models/chat_message_model.dart';
import '../services/messaging_service.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
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

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _timer;

  String? _pendingType;
  dynamic _pendingFile;
  int? _pendingDuration;

  // ✅ بيانات API
  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _totalCount = 0;
  int? _myUserId;
  int? _resolvedThreadId;
  String? _errorMessage;

  String get _memberName {
    final value = widget.peerName.trim();
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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _resolvedThreadId = widget.threadId;
    _initChat();
  }

  Future<void> _initChat() async {
    _myUserId = await AuthService.getUserId();

    // إذا لم يكن لدينا threadId، نحاول إنشاء/جلب محادثة عبر peerProviderId
    if (_resolvedThreadId == null && widget.peerProviderId != null) {
      try {
        _resolvedThreadId = await MessagingService.getOrCreateDirectThread(widget.peerProviderId!);
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

    await _loadMessages();
  }

  Future<void> _loadMessages() async {
    if (_resolvedThreadId == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final page = await MessagingService.fetchMessages(_resolvedThreadId!);
      if (!mounted) return;
      setState(() {
        // الرسائل تأتي مرتبة من الأحدث — نعكسها للعرض
        _messages = page.messages.reversed.toList();
        _hasMore = page.hasMore;
        _totalCount = page.totalCount;
        _isLoading = false;
      });

      // تمييز كمقروءة
      MessagingService.markRead(_resolvedThreadId!);

      // التمرير لأسفل
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'فشل تحميل الرسائل';
      });
    }
  }

  /// تحميل رسائل أقدم عند التمرير لأعلى
  void _onScroll() {
    if (_scrollController.position.pixels <= 50 && _hasMore && !_isLoadingMore) {
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
    setState(() {
      _messages.insertAll(0, page.messages.reversed.toList());
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

  // ✅ إرسال الرسالة
  Future<void> _sendMessage() async {
    if (_isSending) return;

    // التحقق من وجود محتوى
    final text = _controller.text.trim();
    final hasPendingFile = _pendingType != null && _pendingType != "text" && _pendingFile != null;
    final hasPendingAudio = _pendingType == "audio" && _pendingDuration != null;

    if (text.isEmpty && !hasPendingFile && !hasPendingAudio) return;
    if (_resolvedThreadId == null) return;

    setState(() => _isSending = true);

    SendResult result;

    if (hasPendingFile && _pendingFile is File) {
      // إرسال مرفق
      String attachmentType = 'file';
      if (_pendingType == 'image') attachmentType = 'image';
      if (_pendingType == 'audio') attachmentType = 'audio';
      // الفيديو يُعامل كملف في الباكند

      result = await MessagingService.sendAttachment(
        _resolvedThreadId!,
        body: text.isNotEmpty ? text : null,
        file: _pendingFile as File,
        attachmentType: attachmentType,
      );
    } else {
      // إرسال نص
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
      });
      // إعادة تحميل الرسائل لجلب الرسالة الجديدة من السيرفر
      await _refreshMessages();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.error ?? 'فشل إرسال الرسالة',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// تحديث الرسائل بدون إعادة التحميل الكامل
  Future<void> _refreshMessages() async {
    if (_resolvedThreadId == null) return;
    final page = await MessagingService.fetchMessages(_resolvedThreadId!, limit: 30);
    if (!mounted) return;
    setState(() {
      _messages = page.messages.reversed.toList();
      _hasMore = page.hasMore;
      _totalCount = page.totalCount;
    });
    _scrollToBottom();
  }

  // ✅ التسجيل الصوتي
  void _startRecording() {
    setState(() {
      _isRecording = true;
      _pendingType = null;
      _pendingFile = null;
      _recordSeconds = 0;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _recordSeconds++);
    });
  }

  void _stopRecording() {
    _timer?.cancel();
    setState(() {
      _isRecording = false;
      _pendingType = "audio";
      _pendingDuration = _recordSeconds;
    });
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
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.image, color: Colors.deepPurple),
            title: const Text("اختيار صورة من المعرض", style: TextStyle(fontFamily: "Cairo")),
            onTap: () { Navigator.pop(context); _pickImage(); },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: Colors.deepPurple),
            title: const Text("تصوير صورة", style: TextStyle(fontFamily: "Cairo")),
            onTap: () { Navigator.pop(context); _takePhoto(); },
          ),
          ListTile(
            leading: const Icon(Icons.videocam, color: Colors.deepPurple),
            title: const Text("تسجيل فيديو (حد أقصى 3 دقائق)", style: TextStyle(fontFamily: "Cairo")),
            onTap: () { Navigator.pop(context); _recordVideo(); },
          ),
          ListTile(
            leading: const Icon(Icons.video_library, color: Colors.deepPurple),
            title: const Text("اختيار فيديو من المعرض", style: TextStyle(fontFamily: "Cairo")),
            onTap: () { Navigator.pop(context); _pickVideoFromGallery(); },
          ),
          ListTile(
            leading: const Icon(Icons.insert_drive_file, color: Colors.deepPurple),
            title: const Text("اختيار ملف", style: TextStyle(fontFamily: "Cairo")),
            onTap: () { Navigator.pop(context); _pickFile(); },
          ),
        ],
      ),
    );
  }

  // ✅ خيارات المحادثة من الشريط العلوي
  void _showChatOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.mark_chat_read, color: Colors.blue),
            title: const Text("اجعلها مقروءة", style: TextStyle(fontFamily: "Cairo")),
            onTap: () async {
              Navigator.pop(context);
              await MessagingService.markRead(_resolvedThreadId!);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("تم تمييز المحادثة كمقروءة", style: TextStyle(fontFamily: 'Cairo')),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.star, color: Colors.amber),
            title: const Text("مفضلة", style: TextStyle(fontFamily: "Cairo")),
            onTap: () async {
              Navigator.pop(context);
              await MessagingService.toggleFavorite(_resolvedThreadId!);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("تم تحديث المفضلة", style: TextStyle(fontFamily: 'Cairo')),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.block, color: Colors.red),
            title: const Text("حظر العضو", style: TextStyle(fontFamily: "Cairo")),
            onTap: () {
              Navigator.pop(context);
              _showBlockConfirmation();
            },
          ),
          ListTile(
            leading: const Icon(Icons.report, color: Colors.orange),
            title: const Text("الإبلاغ عن عضو", style: TextStyle(fontFamily: "Cairo")),
            onTap: () {
              Navigator.pop(context);
              _showReportDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined, color: Colors.grey),
            title: const Text("أرشفة المحادثة", style: TextStyle(fontFamily: "Cairo")),
            onTap: () async {
              Navigator.pop(context);
              await MessagingService.toggleArchive(_resolvedThreadId!);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("تمت أرشفة المحادثة", style: TextStyle(fontFamily: 'Cairo')),
                ),
              );
              Navigator.pop(context); // العودة لقائمة المحادثات
            },
          ),
        ],
      ),
    );
  }

  // ✅ تأكيد الحظر — يستدعي API
  void _showBlockConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("حظر العضو", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: Text(
          "هل أنت متأكد من حظر ${widget.peerName}؟ \n\nلن يتمكن من مراسلتك بعد ذلك.",
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("إلغاء", style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await MessagingService.toggleBlock(_resolvedThreadId!);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success ? "تم حظر العضو بنجاح" : "فشل الحظر",
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                  backgroundColor: success ? Colors.red : Colors.grey,
                ),
              );
              if (success) Navigator.pop(context); // العودة لقائمة المحادثات
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("حظر", style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
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
          title: const Text("إبلاغ عن المحادثة", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("المستخدم:", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                Text(widget.peerName, style: const TextStyle(fontFamily: 'Cairo')),
                const SizedBox(height: 16),
                const Text("سبب الإبلاغ:", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedReason,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  hint: const Text("اختر السبب", style: TextStyle(fontFamily: 'Cairo')),
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
                            child: Text(r, style: const TextStyle(fontFamily: 'Cairo')),
                          ))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedReason = v),
                ),
                const SizedBox(height: 16),
                const Text("تفاصيل إضافية (اختياري):", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
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
              child: const Text("إلغاء", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: isSending
                  ? null
                  : () async {
                      if (selectedReason == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("يرجى اختيار سبب الإبلاغ", style: TextStyle(fontFamily: 'Cairo')),
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
                            result.success ? "تم إرسال البلاغ بنجاح" : result.error ?? "فشل الإرسال",
                            style: const TextStyle(fontFamily: 'Cairo'),
                          ),
                          backgroundColor: result.success ? Colors.green : Colors.red,
                        ),
                      );
                    },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
              child: isSending
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text("إرسال", style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ إرسال رابط طلب خدمة
  void _sendServiceRequestLink() {
    // إرسال رسالة نصية تحتوي على رابط طلب الخدمة
    _controller.text = "يمكنك طلب خدمة عبر الرابط التالي 🔗";
    _sendMessage();
  }

  // ✅ الانتقال إلى صفحة طلب الخدمة
  void _goToServiceRequest() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ServiceRequestFormScreen(
          providerName: widget.peerName,
          providerId: widget.peerProviderId?.toString(),
        ),
      ),
    );
  }

  // ✅ خيارات الرسالة (حذف/نسخ)
  void _showMessageOptions(ChatMessage msg) {
    final isMe = msg.senderId == _myUserId;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => Wrap(
        children: [
          if (msg.body.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.deepPurple),
              title: const Text("نسخ النص", style: TextStyle(fontFamily: "Cairo")),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("تم نسخ النص", style: TextStyle(fontFamily: 'Cairo'))),
                );
              },
            ),
          if (isMe)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text("حذف الرسالة", style: TextStyle(fontFamily: "Cairo")),
              onTap: () async {
                Navigator.pop(context);
                final success = await MessagingService.deleteMessage(_resolvedThreadId!, msg.id);
                if (success) {
                  _refreshMessages();
                } else {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("فشل حذف الرسالة", style: TextStyle(fontFamily: 'Cairo')),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
            ),
          if (!isMe)
            ListTile(
              leading: const Icon(Icons.report, color: Colors.orange),
              title: const Text("إبلاغ عن هذه الرسالة", style: TextStyle(fontFamily: "Cairo")),
              onTap: () {
                Navigator.pop(context);
                _showReportDialog();
              },
            ),
        ],
      ),
    );
  }

  // ✅ فقاعة الرسائل
  Widget _buildMessageBubble(ChatMessage msg) {
    final isMe = msg.senderId == _myUserId;

    Color bubbleColor = isMe ? Colors.deepPurple : Colors.grey.shade200;
    Color textColor = isMe ? Colors.white : Colors.black87;

    Widget content;

    if (msg.hasAttachment) {
      final fullUrl = ApiClient.buildMediaUrl(msg.attachmentUrl);

      if (msg.attachmentType == 'image' && fullUrl != null) {
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(fullUrl, width: 200, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48)),
            ),
            if (msg.body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(msg.body, style: TextStyle(color: textColor, fontFamily: "Cairo", fontSize: 15)),
            ],
          ],
        );
      } else if (msg.attachmentType == 'audio') {
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_fill, color: textColor, size: 32),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                msg.attachmentName.isNotEmpty ? msg.attachmentName : "رسالة صوتية",
                style: TextStyle(color: textColor, fontFamily: "Cairo"),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      } else {
        // ملف عادي
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file, color: textColor),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                msg.attachmentName.isNotEmpty ? msg.attachmentName : "مرفق",
                style: TextStyle(color: textColor, fontFamily: "Cairo"),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      }
    } else {
      // نص فقط
      content = Text(
        msg.body,
        style: TextStyle(color: textColor, fontFamily: "Cairo", fontSize: 15),
      );
    }

    // تنسيق الوقت
    final h = msg.createdAt.hour > 12 ? msg.createdAt.hour - 12 : msg.createdAt.hour;
    final amPm = msg.createdAt.hour >= 12 ? 'م' : 'ص';
    final m = msg.createdAt.minute.toString().padLeft(2, '0');
    final timeStr = '$h:$m $amPm';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageOptions(msg),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxWidth: 280),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
              bottomRight: isMe ? Radius.zero : const Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              content,
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 11,
                      color: isMe ? Colors.white70 : Colors.black54,
                      fontFamily: "Cairo",
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      msg.readByIds.isNotEmpty ? Icons.done_all : Icons.done,
                      size: 14,
                      color: msg.readByIds.length > 1 ? Colors.blue.shade200 : Colors.white60,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ معاينة قبل الإرسال
  Widget _buildPreview() {
    if (_pendingType == "image" && _pendingFile != null) {
      return Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(_pendingFile, width: 50, height: 50, fit: BoxFit.cover),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () => setState(() { _pendingType = null; _pendingFile = null; }),
          ),
        ],
      );
    } else if (_pendingType == "file" && _pendingFile != null) {
      return Row(
        children: [
          const Icon(Icons.insert_drive_file, color: Colors.deepPurple),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              (_pendingFile as File).path.split('/').last,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: "Cairo"),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () => setState(() { _pendingType = null; _pendingFile = null; }),
          ),
        ],
      );
    } else if (_pendingType == "audio" && _pendingDuration != null) {
      return Row(
        children: [
          const Icon(Icons.mic, color: Colors.red),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              "رسالة صوتية (${_formatDuration(_pendingDuration!)})",
              style: const TextStyle(fontFamily: "Cairo"),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () => setState(() { _pendingType = null; _pendingDuration = null; }),
          ),
        ],
      );
    } else if (_pendingType == "video" && _pendingFile != null) {
      return Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
              ),
              const Icon(Icons.play_circle_outline, color: Colors.white, size: 24),
            ],
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text("فيديو جاهز للإرسال", style: TextStyle(fontFamily: "Cairo"), overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () => setState(() { _pendingType = null; _pendingFile = null; }),
          ),
        ],
      );
    } else {
      return TextField(
        controller: _controller,
        style: const TextStyle(fontFamily: "Cairo"),
        decoration: const InputDecoration(hintText: "اكتب رسالة...", border: InputBorder.none),
        onChanged: (_) => setState(() => _pendingType = "text"),
      );
    }
  }

  String _formatDuration(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor ?? Colors.deepPurple,
        title: Text(
          _memberName,
          style: const TextStyle(fontFamily: "Cairo", fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (widget.peerProviderId != null)
            IconButton(
              icon: const Icon(Icons.send_outlined, color: Colors.white, size: 22),
              onPressed: () => _sendServiceRequestLink(),
              tooltip: "إرسال رابط طلب خدمة",
            ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showChatOptions(),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.15)),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 16, color: Colors.deepPurple),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _memberName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.phone_outlined, size: 15, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _memberPhone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_city_outlined, size: 15, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _memberCity,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ✅ الرسائل
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                            const SizedBox(height: 12),
                            Text(_errorMessage!, style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _loadMessages,
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                              child: const Text("إعادة المحاولة",
                                  style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
                            ),
                          ],
                        ),
                      )
                    : _messages.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade300),
                                const SizedBox(height: 16),
                                const Text("لا توجد رسائل بعد",
                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 16, color: Colors.grey)),
                                const SizedBox(height: 8),
                                const Text("ابدأ المحادثة بإرسال رسالة ✨",
                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.grey)),
                              ],
                            ),
                          )
                        : Column(
                            children: [
                              if (_isLoadingMore)
                                const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: SizedBox(
                                    height: 20, width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurple),
                                  ),
                                ),
                              Expanded(
                                child: ListView.builder(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  itemCount: _messages.length,
                                  itemBuilder: (context, index) => _buildMessageBubble(_messages[index]),
                                ),
                              ),
                            ],
                          ),
          ),

          // ✅ شريط الإدخال
          SafeArea(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file, color: Colors.deepPurple),
                    onPressed: _showAttachmentOptions,
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: _isRecording
                          ? Row(
                              children: [
                                const Icon(Icons.mic, color: Colors.red),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: LinearProgressIndicator(
                                    value: (_recordSeconds % 10) / 10,
                                    color: Colors.red,
                                    backgroundColor: Colors.red.shade100,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(_formatDuration(_recordSeconds), style: const TextStyle(color: Colors.red)),
                              ],
                            )
                          : _buildPreview(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_isRecording)
                    CircleAvatar(
                      backgroundColor: Colors.red,
                      child: IconButton(
                        icon: const Icon(Icons.stop, color: Colors.white),
                        onPressed: _stopRecording,
                      ),
                    )
                  else
                    CircleAvatar(
                      backgroundColor: Colors.deepPurple,
                      child: IconButton(
                        icon: const Icon(Icons.mic, color: Colors.white),
                        onPressed: _startRecording,
                      ),
                    ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Colors.deepPurple,
                    child: _isSending
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : IconButton(
                            icon: const Icon(Icons.send, color: Colors.white),
                            onPressed: _sendMessage,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}