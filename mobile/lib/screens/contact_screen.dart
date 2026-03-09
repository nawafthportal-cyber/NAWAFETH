// ignore_for_file: unused_field
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../models/ticket_model.dart';
import '../services/support_service.dart';

class ContactScreen extends StatefulWidget {
  final bool startNewTicketForm;
  final String? initialSupportTeam;
  final String? initialDescription;

  const ContactScreen({
    super.key,
    this.startNewTicketForm = false,
    this.initialSupportTeam,
    this.initialDescription,
  });

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  // البيانات من الـ API
  List<Ticket> tickets = [];
  bool _isLoadingTickets = true;
  String? _ticketsError;

  Ticket? selectedTicket;
  bool showNewTicketForm = false;
  bool isSupportTeamDropdownOpen = false;
  
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

  @override
  void initState() {
    super.initState();

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
        supportTeams = ['الدعم الفني', 'الاشتراكات', 'التوثيق', 'الاقتراحات', 'الإعلانات', 'الشكاوى والبلاغات'];
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
      setState(() {
        tickets = rawList
            .map((j) => Ticket.fromJson(j as Map<String, dynamic>))
            .toList();
        _isLoadingTickets = false;
      });
    } else {
      setState(() {
        _ticketsError = result.error ?? 'خطأ في جلب التذاكر';
        _isLoadingTickets = false;
      });
    }
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

  Future<void> _createNewTicket() async {
    if (selectedSupportTeam == null || _descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء اختيار فريق الدعم وكتابة التفاصيل')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final ticketType = _teamToTicketType[selectedSupportTeam] ?? 'tech';
    final result = await SupportService.createTicket(
      ticketType: ticketType,
      description: _descriptionController.text.trim(),
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
        showNewTicketForm = false;
        isSupportTeamDropdownOpen = false;
        _descriptionController.clear();
        selectedSupportTeam = null;
        attachments.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء البلاغ بنجاح')),
      );

      // إعادة تحميل التذاكر من الـ API
      _loadTickets();
    } else {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'فشل إنشاء البلاغ')),
      );
    }
  }

  Future<void> _sendReply() async {
    if (_replyController.text.trim().isEmpty || selectedTicket == null) return;
    if (selectedTicket!.serverId == null) return;

    final text = _replyController.text.trim();
    _replyController.clear();

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'فشل إرسال التعليق')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          "تواصل مع منصة نوافذ",
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // قائمة البلاغات
            _buildTicketsSection(theme, isDark),
            
            const SizedBox(height: 24),

            // نموذج بلاغ جديد أو تفاصيل البلاغ المحدد
            if (showNewTicketForm)
              _buildNewTicketForm(theme, isDark)
            else if (selectedTicket != null)
              _buildTicketDetails(theme, isDark)
            else
              Center(
                child: Text(
                  'اضغط على بلاغ لعرض التفاصيل',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketsSection(ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: isDark ? Colors.deepPurple.shade300 : Colors.deepPurple.shade200,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'قائمة البلاغات',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    showNewTicketForm = true;
                    selectedTicket = null;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark
                      ? Colors.pink.shade300
                      : const Color(0xFFE1BEE7),
                  foregroundColor: isDark ? Colors.black87 : Colors.deepPurple.shade700,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                ),
                child: const Text(
                  'بلاغ جديد',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // عرض البطاقات
          ...tickets.map((ticket) => _buildTicketCard(ticket, theme, isDark)),
        ],
      ),
    );
  }

  Widget _buildTicketCard(Ticket ticket, ThemeData theme, bool isDark) {
    final isSelected = selectedTicket?.id == ticket.id;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedTicket = ticket;
          showNewTicketForm = false;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.deepPurple.shade900.withValues(alpha: 0.3) : Colors.deepPurple.shade50)
              : (isDark ? Colors.grey.shade800 : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? (isDark ? Colors.deepPurple.shade300 : Colors.deepPurple)
                : (isDark ? Colors.grey.shade700 : Colors.grey.shade300),
            width: isSelected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getStatusColor(ticket.status, isDark),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          ticket.displayStatus,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _getStatusTextColor(ticket.status, isDark),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          ticket.title,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDateTime(ticket.createdAt),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? Colors.deepPurple.shade700 : Colors.deepPurple.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                ticket.id,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.deepPurple.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewTicketForm(ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: isDark ? Colors.deepPurple.shade300 : Colors.deepPurple.shade200,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // رسالة توجيهية
          Row(
            children: [
              Checkbox(
                value: selectedSupportTeam != null,
                onChanged: null,
                activeColor: Colors.deepPurple,
              ),
              Expanded(
                child: Text(
                  'لكي نخدمك بشكل أفضل حدد فريق الدعم المطلوب',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // قائمة فرق الدعم
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      isSupportTeamDropdownOpen = !isSupportTeamDropdownOpen;
                    });
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isSupportTeamDropdownOpen 
                              ? Icons.arrow_drop_up 
                              : Icons.arrow_drop_down,
                            color: Colors.deepPurple,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            selectedSupportTeam ?? 'فريق الدعم الفني',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      if (selectedSupportTeam != null)
                        Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 20,
                        ),
                    ],
                  ),
                ),
                if (isSupportTeamDropdownOpen) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'قائمة متسلسلة:',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...supportTeams.map((team) => CheckboxListTile(
                    title: Text(
                      team,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    value: selectedSupportTeam == team,
                    onChanged: (bool? value) {
                      setState(() {
                        selectedSupportTeam = value == true ? team : null;
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    activeColor: Colors.deepPurple,
                  )),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // حقل التفاصيل
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              controller: _descriptionController,
              maxLength: 300,
              maxLines: 4,
              style: TextStyle(
                fontFamily: 'Cairo',
                color: isDark ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: 'تفاصيل الطلب (300 حرف)',
                hintStyle: TextStyle(
                  fontFamily: 'Cairo',
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // قسم المرفقات
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                color: isDark ? Colors.deepPurple.shade300 : Colors.deepPurple.shade200,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.attach_file, color: Colors.deepPurple),
                    const SizedBox(width: 8),
                    Text(
                      'المرفقات',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildAttachmentButton(
                      icon: Icons.photo_library,
                      label: 'Photo Library',
                      onTap: _pickImage,
                      isDark: isDark,
                    ),
                    _buildAttachmentButton(
                      icon: Icons.camera_alt,
                      label: 'Take Photo',
                      onTap: _takePhoto,
                      isDark: isDark,
                    ),
                    _buildAttachmentButton(
                      icon: Icons.folder,
                      label: 'Choose File',
                      onTap: _pickFile,
                      isDark: isDark,
                    ),
                  ],
                ),
                if (attachments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'المرفقات المضافة: ${attachments.length}',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // أزرار الإجراءات
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    showNewTicketForm = false;
                    isSupportTeamDropdownOpen = false;
                    _descriptionController.clear();
                    selectedSupportTeam = null;
                    attachments.clear();
                  });
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Colors.pink.shade300 : Colors.deepPurple,
                  side: BorderSide(
                    color: isDark ? Colors.pink.shade300 : Colors.deepPurple,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                ),
                child: const Text(
                  'إلغاء',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _createNewTicket,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.pink.shade300 : const Color(0xFFE1BEE7),
                  foregroundColor: isDark ? Colors.black87 : Colors.deepPurple.shade700,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                ),
                child: const Text(
                  'إرسال',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade700 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? Colors.grey.shade600 : Colors.grey.shade300,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.deepPurple),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketDetails(ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: isDark ? Colors.deepPurple.shade300 : Colors.deepPurple.shade200,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // معلومات البلاغ
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDateTime(selectedTicket!.createdAt),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.deepPurple.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selectedTicket!.title,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? Colors.deepPurple.shade700 : Colors.deepPurple.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  selectedTicket!.id,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.deepPurple.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // الوصف
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade800.withValues(alpha: 0.5) : Colors.purple.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              selectedTicket!.description,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                height: 1.5,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // زر تعديل
          Center(
            child: OutlinedButton(
              onPressed: () {
                // يمكن إضافة وظيفة التعديل
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? Colors.deepPurple.shade300 : Colors.deepPurple,
                side: BorderSide(
                  color: isDark ? Colors.deepPurple.shade300 : Colors.deepPurple,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              ),
              child: const Text(
                'تعديل',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // المرفقات
          if (selectedTicket!.attachments.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDark ? Colors.deepPurple.shade300 : Colors.deepPurple.shade200,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.attach_file, color: Colors.deepPurple, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'المرفقات',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? Colors.pink.shade300 : const Color(0xFFE1BEE7),
                          foregroundColor: isDark ? Colors.black87 : Colors.deepPurple.shade700,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text(
                          'حفظ',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () {},
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? Colors.pink.shade300 : Colors.deepPurple,
                          side: BorderSide(
                            color: isDark ? Colors.pink.shade300 : Colors.deepPurple,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text(
                          'إلغاء',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // حالة البلاغ
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade800.withValues(alpha: 0.5) : Colors.purple.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'حالة الطلب',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(selectedTicket!.status, isDark),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        selectedTicket!.status,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _getStatusTextColor(selectedTicket!.status, isDark),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'آخر تحديث في',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                Text(
                  _formatDateTime(selectedTicket!.lastUpdate ?? selectedTicket!.createdAt),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.deepPurple.shade300 : Colors.deepPurple.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ردود المنصة
          if (selectedTicket!.replies.isNotEmpty) ...[
            ...selectedTicket!.replies.where((r) => r.from == 'platform').map((reply) =>
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade800.withValues(alpha: 0.5) : Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تعليق منصة نوافذ (300 حرف)',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      reply.message,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // حقل الرد
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              controller: _replyController,
              maxLength: 300,
              maxLines: 3,
              style: TextStyle(
                fontFamily: 'Cairo',
                color: isDark ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: 'رد على التعليق (300 حرف)',
                hintStyle: TextStyle(
                  fontFamily: 'Cairo',
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // زر إرسال الرد
          Center(
            child: ElevatedButton(
              onPressed: _sendReply,
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.pink.shade300 : const Color(0xFFE1BEE7),
                foregroundColor: isDark ? Colors.black87 : Colors.deepPurple.shade700,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
              ),
              child: const Text(
                'إرسال',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
