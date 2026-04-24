import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../models/ticket_model.dart';
import '../services/support_service.dart';
import '../widgets/platform_top_bar.dart';

class ContactScreen extends StatefulWidget {
  final bool startNewTicketForm;
  final String? initialSupportTeam;
  final String? initialDescription;
  final int? initialTicketId;

  const ContactScreen({
    super.key,
    this.startNewTicketForm = false,
    this.initialSupportTeam,
    this.initialDescription,
    this.initialTicketId,
  });

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  // البيانات من الـ API
  List<Ticket> tickets = [];
  bool _isLoadingTickets = true;
  bool _isLoadingDetail = false;
  String? _ticketsError;
  String? _detailError;

  Ticket? selectedTicket;
  bool showNewTicketForm = false;
  int? _preferredTicketId;
  
  // متحكمات النموذج
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _replyController = TextEditingController();
  String? selectedSupportTeam;
  List<String> attachments = [];

  // قائمة فرق الدعم (تُحمّل من الـ API)
  List<Map<String, dynamic>> _apiTeams = [];
  List<String> supportTeams = [];

  // تحويل اسم الفريق العربي إلى ticket_type
  static const Map<String, String> _teamToTicketType = {
    'فريق الدعم والمساعدة': 'tech',
    'فريق إدارة المحتوى': 'suggest',
    'فريق إدارة الإعلانات والترويج': 'ads',
    'فريق التوثيق': 'verify',
    'فريق إدارة الترقية والاشتراكات': 'subs',
    'فريق إدارة الخدمات الإضافية': 'extras',
    'الدعم': 'tech',
    'الترويج': 'ads',
    'الدعم الفني': 'tech',
    'المالية': 'subs',
    'الاشتراكات': 'subs',
    'التوثيق': 'verify',
    'المحتوى': 'suggest',
    'الاقتراحات': 'suggest',
    'الإعلانات': 'ads',
    'الشكاوى والبلاغات': 'complaint',
    'الخدمات الإضافية': 'extras',
  };

  static const Map<String, String> _teamToAssignedCode = {
    'فريق الدعم والمساعدة': 'support',
    'فريق إدارة المحتوى': 'content',
    'فريق إدارة الإعلانات والترويج': 'promo',
    'فريق التوثيق': 'verification',
    'فريق إدارة الترقية والاشتراكات': 'finance',
    'فريق إدارة الخدمات الإضافية': 'extras',
    'الدعم': 'support',
    'الدعم الفني': 'support',
    'الترويج': 'promo',
    'المالية': 'finance',
    'الاشتراكات': 'finance',
    'التوثيق': 'verification',
    'المحتوى': 'content',
    'الاقتراحات': 'content',
    'الإعلانات': 'promo',
    'الشكاوى والبلاغات': 'content',
    'الخدمات الإضافية': 'extras',
  };

  static const Map<String, String> _ticketTypeLabels = {
    'tech': 'الدعم الفني',
    'support': 'الدعم والمساعدة',
    'suggest': 'اقتراح',
    'ads': 'إعلانات وترويج',
    'verify': 'التوثيق',
    'subs': 'الاشتراكات والترقيات',
    'extras': 'الخدمات الإضافية',
    'complaint': 'شكوى وبلاغ',
  };

  static const Color _brandPrimary = Color(0xFF4D3EC8);
  static const Color _brandAccent = Color(0xFFF3B35C);
  static const Color _brandSurface = Color(0xFFF8F5FF);
  static const Color _brandText = Color(0xFF17132A);

  @override
  void initState() {
    super.initState();
    _preferredTicketId = widget.initialTicketId;

    if (widget.startNewTicketForm) {
      showNewTicketForm = true;
      selectedTicket = null;
    }

    _loadTeams();
    _loadTickets();

    final desc = widget.initialDescription;
    if (desc != null && desc.trim().isNotEmpty) {
      _descriptionController.text = desc;
    }
  }

  /// تحميل فرق الدعم من الـ API
  Future<void> _loadTeams() async {
    final result = await SupportService.fetchTeams();
    if (!mounted) return;
    if (result.isSuccess && result.data is List) {
      final teamsList = (result.data as List).cast<Map<String, dynamic>>();
      setState(() {
        _apiTeams = teamsList;
        supportTeams = teamsList
            .map((t) => t['name_ar'] as String? ?? '')
            .where((n) => n.isNotEmpty)
            .toList();
      });
      // Apply initial support team after teams are loaded
      final team = widget.initialSupportTeam;
      if (team != null && supportTeams.contains(team)) {
        setState(() => selectedSupportTeam = team);
      }
    } else {
      // fallback to static list
      setState(() {
        supportTeams = [
          'فريق الدعم والمساعدة',
          'فريق إدارة المحتوى',
          'فريق إدارة الإعلانات والترويج',
          'فريق التوثيق',
          'فريق إدارة الترقية والاشتراكات',
          'فريق إدارة الخدمات الإضافية',
        ];
      });
      final team = widget.initialSupportTeam;
      if (team != null && supportTeams.contains(team)) {
        setState(() => selectedSupportTeam = team);
      }
    }
  }

  /// تحميل التذاكر من الـ API
  Future<void> _loadTickets() async {
    setState(() {
      _isLoadingTickets = true;
      _ticketsError = null;
    });

    final result = await SupportService.fetchMyTickets();
    if (!mounted) return;

    if (result.isSuccess && result.data != null) {
      final List rawList;
      if (result.data is List) {
        rawList = result.data as List;
      } else if (result.data is Map && result.data['results'] is List) {
        rawList = result.data['results'] as List;
      } else {
        rawList = [];
      }
      final loadedTickets = rawList
          .map((j) => Ticket.fromJson(j as Map<String, dynamic>))
          .toList();
      final preferredTicket = _resolvePreferredTicket(loadedTickets);

      setState(() {
        tickets = loadedTickets;
        _isLoadingTickets = false;
        if (showNewTicketForm) {
          selectedTicket = null;
          _detailError = null;
        } else {
          selectedTicket = preferredTicket;
        }
      });

      final targetDetailId =
          !showNewTicketForm ? (_preferredTicketId ?? preferredTicket?.serverId) : null;
      if (targetDetailId != null) {
        await _fetchTicketDetail(targetDetailId, silent: true);
      }
    } else {
      setState(() {
        _ticketsError = result.error ?? 'خطأ في جلب التذاكر';
        _isLoadingTickets = false;
      });
    }
  }

  Ticket? _resolvePreferredTicket(List<Ticket> loadedTickets) {
    if (loadedTickets.isEmpty) {
      return null;
    }

    final requestedTicketId = _preferredTicketId;
    if (requestedTicketId != null) {
      for (final ticket in loadedTickets) {
        if (ticket.serverId == requestedTicketId) {
          return ticket;
        }
      }
    }

    final currentTicket = selectedTicket;
    if (currentTicket == null) {
      return loadedTickets.first;
    }

    for (final ticket in loadedTickets) {
      if (currentTicket.serverId != null &&
          ticket.serverId == currentTicket.serverId) {
        return ticket;
      }
      if (ticket.id == currentTicket.id) {
        return ticket;
      }
    }

    return loadedTickets.first;
  }

  Future<void> _fetchTicketDetail(int ticketId, {bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoadingDetail = true;
        _detailError = null;
      });
    } else {
      _detailError = null;
    }

    final result = await SupportService.fetchTicketDetail(ticketId);
    if (!mounted) return;

    if (result.isSuccess && result.data is Map<String, dynamic>) {
      final detailedTicket = Ticket.fromJson(result.data as Map<String, dynamic>);
      setState(() {
        _isLoadingDetail = false;
        _detailError = null;
        _preferredTicketId = detailedTicket.serverId;
        selectedTicket = detailedTicket;
        tickets = tickets.map((ticket) {
          if (ticket.serverId == detailedTicket.serverId ||
              ticket.id == detailedTicket.id) {
            return detailedTicket;
          }
          return ticket;
        }).toList();
      });
    } else {
      setState(() {
        _isLoadingDetail = false;
        _detailError = result.error ?? 'تعذر تحميل تفاصيل البلاغ';
      });
    }
  }

  Future<void> _selectTicket(Ticket ticket) async {
    setState(() {
      showNewTicketForm = false;
      _preferredTicketId = ticket.serverId;
      selectedTicket = ticket;
      _detailError = null;
      _replyController.clear();
    });

    if (ticket.serverId != null) {
      await _fetchTicketDetail(ticket.serverId!);
    }
  }

  String _resolveAssignedTeamCode() {
    final selected = (selectedSupportTeam ?? '').trim();
    if (selected.isEmpty) return '';

    for (final team in _apiTeams) {
      final name = (team['name_ar'] as String? ?? '').trim();
      final code = (team['code'] as String? ?? '').trim();
      if (name == selected && code.isNotEmpty) {
        return code;
      }
    }

    return _teamToAssignedCode[selected] ?? '';
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  String _formatDateTime(DateTime dt) {
    return DateFormat('dd/MM/yyyy - HH:mm').format(dt);
  }

  String _ticketTypeLabel(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return 'بلاغ دعم';
    }
    return _ticketTypeLabels[normalized] ?? normalized;
  }

  String _ticketTeamLabel(Ticket ticket) {
    final supportTeam = ticket.supportTeam.trim();
    if (supportTeam.isNotEmpty) {
      return supportTeam;
    }
    return _ticketTypeLabel(ticket.ticketType);
  }

  String _replyAuthorLabel(TicketReply reply) {
    final author = reply.from.trim();
    if (author.isEmpty || author.toLowerCase() == 'platform') {
      return 'منصة نوافذ';
    }
    if (author.toLowerCase() == 'user') {
      return 'أنت';
    }
    return author;
  }

  bool _replyFromCurrentUser(TicketReply reply) {
    return reply.from.trim().toLowerCase() == 'user';
  }

  String _fileNameFromPath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'مرفق';
    }
    final normalized = trimmed.replaceAll('\\', '/');
    final segments = normalized.split('/');
    return segments.isNotEmpty ? segments.last : normalized;
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(fontFamily: 'Cairo'),
            textAlign: TextAlign.right,
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? const Color(0xFFB3261E)
              : const Color(0xFF2F6D4F),
        ),
      );
  }

  void _openNewTicketForm() {
    setState(() {
      showNewTicketForm = true;
      selectedTicket = null;
      _detailError = null;
      _replyController.clear();
    });
  }

  void _resetNewTicketForm() {
    setState(() {
      showNewTicketForm = false;
      _descriptionController.clear();
      selectedSupportTeam = widget.initialSupportTeam;
      attachments.clear();
      _detailError = null;
      selectedTicket = _resolvePreferredTicket(tickets);
    });
  }

  Color _getStatusColor(String status, bool isDark) {
    switch (status) {
      case 'جديد':
      case 'new':
        return isDark ? Colors.blue.shade300 : Colors.blue.shade100;
      case 'تحت المعالجة':
      case 'in_progress':
        return isDark ? Colors.deepPurple.shade300 : Colors.deepPurple.shade100;
      case 'مُعاد':
      case 'returned':
        return isDark ? Colors.orange.shade300 : Colors.orange.shade100;
      case 'مغلق':
      case 'closed':
        return isDark ? Colors.grey.shade400 : Colors.grey.shade300;
      default:
        return isDark ? Colors.grey.shade400 : Colors.grey.shade200;
    }
  }

  Color _getStatusTextColor(String status, bool isDark) {
    switch (status) {
      case 'جديد':
      case 'new':
        return isDark ? Colors.blue.shade900 : Colors.blue.shade700;
      case 'تحت المعالجة':
      case 'in_progress':
        return isDark ? Colors.deepPurple.shade900 : Colors.deepPurple.shade700;
      case 'مُعاد':
      case 'returned':
        return isDark ? Colors.orange.shade900 : Colors.orange.shade700;
      case 'مغلق':
      case 'closed':
        return isDark ? Colors.grey.shade900 : Colors.grey.shade700;
      default:
        return isDark ? Colors.grey.shade900 : Colors.grey.shade600;
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        attachments.add(image.path);
      });
    }
  }

  Future<void> _takePhoto() async {
    final ImagePicker picker = ImagePicker();
    final XFile? photo = await picker.pickImage(source: ImageSource.camera);
    if (photo != null) {
      setState(() {
        attachments.add(photo.path);
      });
    }
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() {
        attachments.add(result.files.single.path!);
      });
    }
  }

  bool _isSubmitting = false;
  bool _isSendingReply = false;

  Future<void> _createNewTicket() async {
    if (selectedSupportTeam == null || _descriptionController.text.trim().isEmpty) {
      _showSnack('الرجاء اختيار فريق الدعم وكتابة التفاصيل', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    final ticketType = _teamToTicketType[selectedSupportTeam] ?? 'tech';
    final assignedTeamCode = _resolveAssignedTeamCode();
    final result = await SupportService.createTicket(
      ticketType: ticketType,
      description: _descriptionController.text.trim(),
      assignedTeam: assignedTeamCode.isNotEmpty ? assignedTeamCode : null,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      // رفع المرفقات بعد إنشاء التذكرة بنجاح
      final ticketId = result.dataAsMap?['id'] as int?;
      if (ticketId != null && attachments.isNotEmpty) {
        for (final path in attachments) {
          await SupportService.uploadAttachment(
            ticketId: ticketId,
            file: File(path),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _preferredTicketId = ticketId;
        showNewTicketForm = false;
        _descriptionController.clear();
        selectedSupportTeam = null;
        attachments.clear();
      });

      _showSnack('تم إنشاء البلاغ بنجاح');

      // إعادة تحميل التذاكر من الـ API
      await _loadTickets();
      if (ticketId != null) {
        await _fetchTicketDetail(ticketId, silent: true);
      }
    } else {
      setState(() => _isSubmitting = false);
      _showSnack(result.error ?? 'فشل إنشاء البلاغ', isError: true);
    }
  }

  Future<void> _sendReply() async {
    if (_replyController.text.trim().isEmpty || selectedTicket == null) return;
    if (selectedTicket!.serverId == null) return;
    if (_isSendingReply) return;

    final text = _replyController.text.trim();
    _replyController.clear();
    setState(() => _isSendingReply = true);

    // Optimistic: add locally first
    final reply = TicketReply(
      from: 'user',
      message: text,
      timestamp: DateTime.now(),
    );
    setState(() {
      final index = tickets.indexWhere((t) => t.id == selectedTicket!.id);
      if (index != -1) {
        tickets[index] = tickets[index].copyWith(
          replies: [...tickets[index].replies, reply],
          lastUpdate: DateTime.now(),
        );
        selectedTicket = tickets[index];
      }
    });

    // Call API
    final result = await SupportService.addComment(
      ticketId: selectedTicket!.serverId!,
      text: text,
    );

    if (!result.isSuccess && mounted) {
      _showSnack(result.error ?? 'فشل إرسال التعليق', isError: true);
      await _fetchTicketDetail(selectedTicket!.serverId!, silent: true);
    } else if (selectedTicket?.serverId != null) {
      await _fetchTicketDetail(selectedTicket!.serverId!, silent: true);
    }

    if (mounted) {
      setState(() => _isSendingReply = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = isDark
        ? const Color(0xFF0F1220)
        : const Color(0xFFF5F3FB);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: PlatformTopBar(
        pageLabel: 'تواصل مع منصة نوافذ',
        showBackButton: Navigator.of(context).canPop(),
        showNotificationAction: false,
        showChatAction: false,
      ),
      body: RefreshIndicator.adaptive(
        color: _brandPrimary,
        onRefresh: _loadTickets,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHero(theme, isDark),
              const SizedBox(height: 16),
              _buildStatsRow(theme, isDark),
              const SizedBox(height: 16),
              _buildTicketsSection(theme, isDark),
              const SizedBox(height: 16),
              if (showNewTicketForm)
                _buildNewTicketForm(theme, isDark)
              else if (_isLoadingDetail || selectedTicket != null || _detailError != null)
                _buildTicketDetails(theme, isDark)
              else
                _buildDetailPlaceholder(theme, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero(ThemeData theme, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF4331B8),
            Color(0xFF6C54E5),
            Color(0xFF9E82FF),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: _brandPrimary.withValues(alpha: 0.28),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: const Icon(
                  Icons.support_agent_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'تواصل معنا',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'تابع البلاغات، أرسل استفسارك، وراجع الردود من نفس المكان.',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        height: 1.6,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _openNewTicketForm,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _brandPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: const Text(
                  'بلاغ جديد',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _isLoadingTickets ? null : () => _loadTickets(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.42),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text(
                  'تحديث البلاغات',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(ThemeData theme, bool isDark) {
    final openCount = tickets
        .where((ticket) => ticket.status != 'closed' && ticket.status != 'مغلق')
        .length;
    final closedCount = tickets.length - openCount;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildStatCard(
          title: 'إجمالي البلاغات',
          value: '${tickets.length}',
          icon: Icons.sticky_note_2_outlined,
          accent: _brandPrimary,
          isDark: isDark,
        ),
        _buildStatCard(
          title: 'البلاغات المفتوحة',
          value: '$openCount',
          icon: Icons.timelapse_rounded,
          accent: const Color(0xFF2A8B6E),
          isDark: isDark,
        ),
        _buildStatCard(
          title: 'المغلقة',
          value: '$closedCount',
          icon: Icons.verified_rounded,
          accent: _brandAccent,
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
    required bool isDark,
  }) {
    return Container(
      width: 112,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF191D2D) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE9E3FB),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.14 : 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : _brandText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              height: 1.5,
              color: isDark ? Colors.white70 : const Color(0xFF6A6480),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketsSection(ThemeData theme, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171B2A) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE9E3FB),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.06),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'قائمة البلاغات',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : _brandText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'اختر البلاغ لعرض التفاصيل الكاملة والردود المرتبطة به.',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: isDark ? Colors.white60 : const Color(0xFF6A6480),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : _brandSurface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${tickets.length} بلاغ',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : _brandPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingTickets)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_ticketsError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4F2),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFF4C9C4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'تعذر تحميل البلاغات',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF8D2A20),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _ticketsError!,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      color: Color(0xFF8D2A20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _loadTickets,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFB3261E),
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text(
                      'إعادة المحاولة',
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                  ),
                ],
              ),
            )
          else if (tickets.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : _brandSurface,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: _brandPrimary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.inbox_outlined,
                      color: _brandPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'لا توجد بلاغات حتى الآن',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: isDark ? Colors.white : _brandText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'ابدأ بإنشاء بلاغ جديد وسنرتب توجيهه إلى الفريق المناسب.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      height: 1.7,
                      color: isDark ? Colors.white70 : const Color(0xFF6A6480),
                    ),
                  ),
                ],
              ),
            )
          else
            ...tickets.map((ticket) => _buildTicketCard(ticket, theme, isDark)),
        ],
      ),
    );
  }

  Widget _buildTicketCard(Ticket ticket, ThemeData theme, bool isDark) {
    final isSelected = selectedTicket?.id == ticket.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _selectTicket(ticket),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark ? _brandPrimary.withValues(alpha: 0.18) : _brandSurface)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.03)
                      : const Color(0xFFFDFCFF)),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isSelected
                    ? _brandPrimary
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFE7E0F7)),
                width: isSelected ? 1.6 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _getStatusColor(ticket.status, isDark),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              ticket.displayStatus,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _getStatusTextColor(ticket.status, isDark),
                              ),
                            ),
                          ),
                          Text(
                            _ticketTeamLabel(ticket),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: isDark ? Colors.white70 : const Color(0xFF6A6480),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isLoadingDetail && isSelected)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    else
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: isDark ? Colors.white54 : const Color(0xFF8A84A1),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ticket.id,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : _brandText,
                        ),
                      ),
                    ),
                    Text(
                      _ticketTypeLabel(ticket.ticketType),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: isDark ? Colors.white60 : const Color(0xFF7A748D),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  ticket.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    height: 1.7,
                    color: isDark ? Colors.white70 : const Color(0xFF58516B),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: isDark ? Colors.white54 : const Color(0xFF8B86A3),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _formatDateTime(ticket.createdAt),
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: isDark ? Colors.white54 : const Color(0xFF8B86A3),
                        ),
                      ),
                    ),
                    if (ticket.attachments.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _brandAccent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${ticket.attachments.length} مرفق',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF9A6718),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNewTicketForm(ThemeData theme, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171B2A) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE9E3FB),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.06),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _brandPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  color: _brandPrimary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'بلاغ جديد',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : _brandText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'اختر الفريق المناسب واكتب وصفًا واضحًا حتى يصل البلاغ بسرعة للجهة الصحيحة.',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        height: 1.6,
                        color: isDark ? Colors.white70 : const Color(0xFF6A6480),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : _brandSurface,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: supportTeams.contains(selectedSupportTeam)
                      ? selectedSupportTeam
                      : null,
                  items: supportTeams
                      .map(
                        (team) => DropdownMenuItem<String>(
                          value: team,
                          child: Text(
                            team,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              color: isDark ? Colors.white : _brandText,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _isSubmitting
                      ? null
                      : (value) => setState(() => selectedSupportTeam = value),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  decoration: _fieldDecoration(
                    isDark: isDark,
                    labelText: 'الفريق المختص',
                    hintText: 'اختر فريق الدعم',
                    prefixIcon: Icons.groups_rounded,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _descriptionController,
                  maxLength: 300,
                  maxLines: 5,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: isDark ? Colors.white : _brandText,
                  ),
                  decoration: _fieldDecoration(
                    isDark: isDark,
                    labelText: 'تفاصيل البلاغ',
                    hintText:
                        'اشرح المشكلة أو الطلب بشكل مختصر وواضح، مع أي تفاصيل تساعد فريق الدعم.',
                    prefixIcon: Icons.subject_rounded,
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFFFFCF6),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFFF3E7C6),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _brandAccent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.attach_file_rounded,
                        color: Color(0xFF9A6718),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'المرفقات',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : _brandText,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'يمكنك إضافة صور أو ملفات توضح البلاغ قبل إرساله.',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color:
                                  isDark ? Colors.white70 : const Color(0xFF7B745A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text(
                        'المعرض',
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _takePhoto,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text(
                        'الكاميرا',
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: const Text(
                        'ملف',
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                  ],
                ),
                if (attachments.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final attachment in attachments)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : const Color(0xFFE7E0F7),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.insert_drive_file_outlined,
                                size: 16,
                                color: _brandPrimary,
                              ),
                              const SizedBox(width: 6),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 160),
                                child: Text(
                                  _fileNameFromPath(attachment),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    color: isDark ? Colors.white : _brandText,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: () => setState(() {
                                  attachments.remove(attachment);
                                }),
                                child: const Padding(
                                  padding: EdgeInsets.all(2),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                    color: Color(0xFF8D2A20),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSubmitting ? null : _resetNewTicketForm,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : _brandPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.16)
                          : const Color(0xFFDCCFFF),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'إلغاء',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isSubmitting ? null : _createNewTicket,
                  style: FilledButton.styleFrom(
                    backgroundColor: _brandPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(
                    _isSubmitting ? 'جارٍ الإرسال...' : 'إرسال البلاغ',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required String label,
    required String value,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      width: 154,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE7E0F7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _brandPrimary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _brandPrimary, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              color: isDark ? Colors.white60 : const Color(0xFF7B7690),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : _brandText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyCard({
    required TicketReply reply,
    required bool isDark,
  }) {
    final fromCurrentUser = _replyFromCurrentUser(reply);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fromCurrentUser
            ? _brandPrimary.withValues(alpha: isDark ? 0.16 : 0.08)
            : (isDark
                ? Colors.white.withValues(alpha: 0.04)
                : const Color(0xFFFFFCF6)),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: fromCurrentUser
              ? _brandPrimary.withValues(alpha: 0.22)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFF1E7C7)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _replyAuthorLabel(reply),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : _brandText,
                  ),
                ),
              ),
              Text(
                _formatDateTime(reply.timestamp),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: isDark ? Colors.white60 : const Color(0xFF8B86A3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            reply.message,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              height: 1.7,
              color: isDark ? Colors.white70 : const Color(0xFF58516B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailPlaceholder(ThemeData theme, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171B2A) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE9E3FB),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: _brandPrimary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.forum_outlined,
              color: _brandPrimary,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'اختر بلاغًا لعرض التفاصيل',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : _brandText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'ستظهر هنا حالة البلاغ، المرفقات، والتعليقات بينك وبين فريق الدعم.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              height: 1.7,
              color: isDark ? Colors.white70 : const Color(0xFF6A6480),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required bool isDark,
    required String hintText,
    String? labelText,
    IconData? prefixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      alignLabelWithHint: true,
      prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
      filled: true,
      fillColor: isDark
          ? Colors.white.withValues(alpha: 0.04)
          : const Color(0xFFFDFCFF),
      hintStyle: TextStyle(
        fontFamily: 'Cairo',
        color: isDark ? Colors.white54 : const Color(0xFF8B86A3),
      ),
      labelStyle: TextStyle(
        fontFamily: 'Cairo',
        color: isDark ? Colors.white70 : const Color(0xFF6A6480),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE7E0F7),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE7E0F7),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _brandPrimary, width: 1.3),
      ),
    );
  }

  Widget _buildTicketDetails(ThemeData theme, bool isDark) {
    if (_isLoadingDetail && selectedTicket == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF171B2A) : Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_detailError != null && selectedTicket == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4F2),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFF4C9C4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'تعذر تحميل تفاصيل البلاغ',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w800,
                color: Color(0xFF8D2A20),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _detailError!,
              style: const TextStyle(
                fontFamily: 'Cairo',
                color: Color(0xFF8D2A20),
              ),
            ),
          ],
        ),
      );
    }

    final ticket = selectedTicket;
    if (ticket == null) {
      return _buildDetailPlaceholder(theme, isDark);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171B2A) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE9E3FB),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.06),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  isDark ? const Color(0xFF22195C) : _brandSurface,
                  isDark ? const Color(0xFF171B2A) : const Color(0xFFFDFBFF),
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFFE4DDF8),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ticket.id,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : _brandText,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _ticketTypeLabel(ticket.ticketType),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              color: isDark ? Colors.white70 : const Color(0xFF6A6480),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(ticket.status, isDark),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        ticket.displayStatus,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w800,
                          color: _getStatusTextColor(ticket.status, isDark),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_detailError != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4F2),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFF4C9C4)),
                    ),
                    child: Text(
                      _detailError!,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: Color(0xFF8D2A20),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildInfoCard(
                      label: 'الفريق',
                      value: _ticketTeamLabel(ticket),
                      icon: Icons.groups_rounded,
                      isDark: isDark,
                    ),
                    _buildInfoCard(
                      label: 'تاريخ الإنشاء',
                      value: _formatDateTime(ticket.createdAt),
                      icon: Icons.event_rounded,
                      isDark: isDark,
                    ),
                    _buildInfoCard(
                      label: 'آخر تحديث',
                      value: _formatDateTime(ticket.lastUpdate ?? ticket.createdAt),
                      icon: Icons.update_rounded,
                      isDark: isDark,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'وصف البلاغ',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : _brandText,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : _brandSurface,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(
              ticket.description,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                height: 1.8,
                color: isDark ? Colors.white70 : const Color(0xFF58516B),
              ),
            ),
          ),
          if (ticket.attachments.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'المرفقات',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : _brandText,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: ticket.attachments.map((attachment) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFFFFFCF6),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFF3E7C6),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.attach_file_rounded,
                        size: 18,
                        color: Color(0xFF9A6718),
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 190),
                        child: Text(
                          _fileNameFromPath(attachment),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: isDark ? Colors.white : _brandText,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'سجل التعليقات',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : _brandText,
                  ),
                ),
              ),
              if (_isLoadingDetail)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (ticket.replies.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : _brandSurface,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(
                'لا توجد تعليقات حتى الآن على هذا البلاغ.',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  color: isDark ? Colors.white70 : const Color(0xFF6A6480),
                ),
              ),
            )
          else
            ...ticket.replies.map(
              (reply) => _buildReplyCard(reply: reply, isDark: isDark),
            ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : _brandSurface,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'أضف ردًا',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : _brandText,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _replyController,
                  maxLength: 300,
                  maxLines: 4,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: isDark ? Colors.white : _brandText,
                  ),
                  decoration: _fieldDecoration(
                    isDark: isDark,
                    hintText: 'اكتب ردك أو استفسارك الإضافي هنا.',
                    prefixIcon: Icons.mode_comment_outlined,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _isSendingReply ? null : _sendReply,
                    style: FilledButton.styleFrom(
                      backgroundColor: _brandPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: _isSendingReply
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      _isSendingReply ? 'جارٍ الإرسال...' : 'إرسال الرد',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
