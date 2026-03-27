import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/content_service.dart';
import '../services/api_client.dart';
import '../widgets/platform_top_bar.dart';

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  List<bool> _expanded = [false, false, false, false];
  bool _isLoading = true;
  String _pageTitle = 'الشروط والأحكام';
  String _emptyLabel = 'لا توجد مستندات متاحة حالياً';
  String _openDocumentLabel = 'عرض المستند';
  String _fileOnlyHint = 'اضغط على "عرض المستند" لفتح النسخة الرسمية.';
  String _missingDocumentHint = 'لا توجد بيانات متاحة لهذا المستند حالياً.';

  List<Map<String, dynamic>> _terms = [];

  // Map API doc_type → icon and fallback title
  static const Map<String, Map<String, dynamic>> _docMeta = {
    'terms': {'icon': Icons.article_outlined, 'title': 'اتفاقية الاستخدام'},
    'privacy': {'icon': Icons.privacy_tip_outlined, 'title': 'سياسة الخصوصية'},
    'regulations': {'icon': Icons.gavel_outlined, 'title': 'الأنظمة والتشريعات المتبعة'},
    'prohibited_services': {'icon': Icons.block_outlined, 'title': 'الخدمات الممنوعة'},
  };
  static const List<String> _docOrder = [
    'terms',
    'privacy',
    'regulations',
    'prohibited_services',
  ];

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    final result = await ContentService.fetchPublicContent();
    if (!mounted) return;
    if (result.isSuccess && result.dataAsMap != null) {
      final data = result.dataAsMap!;
      final blocks = data['blocks'] as Map<String, dynamic>? ?? {};
      final documents = data['documents'] as Map<String, dynamic>?;
      final pageTitle = (blocks['terms_page_title']?['title_ar'] ?? '').toString().trim();
      final emptyLabel = (blocks['terms_empty_label']?['title_ar'] ?? '').toString().trim();
      final openLabel = (blocks['terms_open_document_label']?['title_ar'] ?? '').toString().trim();
      final fileOnlyHint = (blocks['terms_file_only_hint']?['title_ar'] ?? '').toString().trim();
      final missingHint = (blocks['terms_missing_document_hint']?['title_ar'] ?? '').toString().trim();
      if (pageTitle.isNotEmpty) _pageTitle = pageTitle;
      if (emptyLabel.isNotEmpty) _emptyLabel = emptyLabel;
      if (openLabel.isNotEmpty) _openDocumentLabel = openLabel;
      if (fileOnlyHint.isNotEmpty) _fileOnlyHint = fileOnlyHint;
      if (missingHint.isNotEmpty) _missingDocumentHint = missingHint;
      if (documents != null && documents.isNotEmpty) {
        final List<Map<String, dynamic>> apiTerms = [];
        final orderedKeys = [
          ..._docOrder.where(documents.containsKey),
          ...documents.keys.where((key) => !_docOrder.contains(key)),
        ];
        for (final docType in orderedKeys) {
          final doc = documents[docType] as Map<String, dynamic>? ?? {};
          final meta = _docMeta[docType] ?? {'icon': Icons.description_outlined, 'title': docType};
          final fileUrl = ApiClient.buildMediaUrl(doc['file_url']?.toString());
          final body = (doc['body_ar'] ?? '').toString().trim();
          final version = (doc['version'] ?? '').toString().trim();
          apiTerms.add({
            'title': (doc['label_ar'] ?? meta['title']).toString(),
            'lastUpdate': _buildMetaLine(
              publishedAt: doc['published_at']?.toString(),
              version: version,
            ),
            'content':
                body.isNotEmpty
                    ? body
                    : ((fileUrl ?? '').isNotEmpty
                        ? _fileOnlyHint
                        : _missingDocumentHint),
            'fileUrl': fileUrl,
            'icon': meta['icon'],
          });
        }
        if (apiTerms.isNotEmpty) {
          setState(() {
            _terms = apiTerms;
            _expanded = List.filled(apiTerms.length, false);
          });
        }
      }
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  String _buildMetaLine({String? publishedAt, String? version}) {
    final parts = <String>[];
    final normalizedVersion = (version ?? '').trim();
    if (normalizedVersion.isNotEmpty) {
      parts.add('الإصدار $normalizedVersion');
    }

    final formattedDate = _formatPublishedAt(publishedAt);
    if (formattedDate.isNotEmpty) {
      parts.add('آخر تحديث: $formattedDate');
    }
    return parts.join(' • ');
  }

  String _formatPublishedAt(String? rawValue) {
    final raw = (rawValue ?? '').trim();
    if (raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('dd/MM/yyyy', 'ar').format(parsed.toLocal());
  }

  Future<void> _openDocument(String? fileUrl) async {
    final url = (fileUrl ?? '').trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح المستند')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PlatformTopBar(
        pageLabel: _pageTitle,
        showBackButton: Navigator.of(context).canPop(),
        showNotificationAction: false,
        showChatAction: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
          : _terms.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _emptyLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _terms.length,
              itemBuilder: (context, index) {
                final item = _terms[index];
                final expanded = _expanded[index];
                final fileUrl = (item["fileUrl"] as String?)?.trim() ?? '';
                final metaLine = (item["lastUpdate"] as String?)?.trim() ?? '';

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {
                      setState(() {
                        _expanded[index] = !_expanded[index];
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ✅ العنوان + الأيقونة + السهم
                          Row(
                            children: [
                              Icon(item["icon"], color: Colors.deepPurple),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item["title"],
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Icon(
                                expanded ? Icons.expand_less : Icons.expand_more,
                                color: Colors.deepPurple,
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          if (metaLine.isNotEmpty)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    metaLine,
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (metaLine.isNotEmpty)
                            const SizedBox(height: 4),
                          AnimatedCrossFade(
                            firstChild: const SizedBox.shrink(),
                            secondChild: Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item["content"],
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 14,
                                      height: 1.5,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  if (fileUrl.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: () => _openDocument(fileUrl),
                                        icon: const Icon(Icons.open_in_new_rounded),
                                        label: Text(_openDocumentLabel),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            crossFadeState:
                                expanded
                                    ? CrossFadeState.showSecond
                                    : CrossFadeState.showFirst,
                            duration: const Duration(milliseconds: 300),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
