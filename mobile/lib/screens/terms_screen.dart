import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_theme.dart';
import '../services/content_service.dart';
import '../services/api_client.dart';
import '../widgets/platform_top_bar.dart';

// ─── color tokens ────────────────────────────────────────────────────────────
const Color _teal    = Color(0xFF115E59);
const Color _tealMid = Color(0xFF0F766E);

// ─── helpers ─────────────────────────────────────────────────────────────────
String _toArabicDigits(String value) {
  const digits = '٠١٢٣٤٥٦٧٨٩';
  return value.replaceAllMapped(
    RegExp(r'[0-9]'),
    (m) => digits[int.parse(m.group(0)!)],
  );
}

List<_Clause> _parseClauses(String raw) {
  final lines = raw
      .replaceAll('\r', '')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return [];

  final clauses = <_Clause>[];
  _ClauseBuilder? current;
  final headingPattern = RegExp(r'^([0-9٠-٩]+)[.\-ـ:)]\s*(.+)$');

  for (final line in lines) {
    final match = headingPattern.firstMatch(line);
    if (match != null) {
      if (current != null) clauses.add(current.build());
      current = _ClauseBuilder(
        number: _toArabicDigits(match.group(1)!),
        title: match.group(2)!.trim(),
      );
    } else if (current == null) {
      current = _ClauseBuilder(
        number: _toArabicDigits('${clauses.length + 1}'),
        title: line,
      );
    } else {
      current.lines.add(line);
    }
  }
  if (current != null) clauses.add(current.build());
  return clauses;
}

class _Clause {
  const _Clause({required this.number, required this.title, required this.body});
  final String number;
  final String title;
  final String body;
}

class _ClauseBuilder {
  _ClauseBuilder({required this.number, required this.title});
  final String number;
  final String title;
  final List<String> lines = [];
  _Clause build() => _Clause(number: number, title: title, body: lines.join('\n'));
}

// ─── doc model ───────────────────────────────────────────────────────────────
class _TermsDoc {
  const _TermsDoc({
    required this.key,
    required this.title,
    required this.icon,
    required this.version,
    required this.published,
    required this.clauses,
    required this.fileUrl,
  });
  final String key;
  final String title;
  final IconData icon;
  final String version;
  final String published;
  final List<_Clause> clauses;
  final String fileUrl;
}

// ─── screen ──────────────────────────────────────────────────────────────────
class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  static const _docMeta = <String, Map<String, dynamic>>{
    'terms':              {'icon': Icons.article_outlined,    'title': 'اتفاقية الاستخدام'},
    'privacy':            {'icon': Icons.security_outlined,   'title': 'سياسة الخصوصية'},
    'regulations':        {'icon': Icons.balance_outlined,    'title': 'الأنظمة والتشريعات المتبعة'},
    'prohibited_services':{'icon': Icons.block_outlined,      'title': 'الخدمات الممنوعة'},
  };
  static const _docOrder = ['terms', 'privacy', 'regulations', 'prohibited_services'];

  bool _isLoading = true;
  bool _hasError  = false;
  String _pageTitle          = 'الشروط والأحكام';
  String _emptyLabel         = 'لا توجد مستندات متاحة حالياً';
  String _openDocumentLabel  = 'عرض المستند';
  String _fileOnlyHint       = 'اضغط على "عرض المستند" لفتح النسخة الرسمية.';
  String _missingHint        = 'لا توجد بيانات متاحة لهذا المستند حالياً.';

  List<_TermsDoc> _docs       = [];
  final _scrollController     = ScrollController();

  @override
  void initState() {
    super.initState();
    // الصفحة القانونية تحتاج بيانات حديثة دائماً → تجاوز الكاش
    _loadContent(forceRefresh: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadContent({bool forceRefresh = false}) async {
    final result = await ContentService.fetchPublicContent(forceRefresh: forceRefresh);
    if (!mounted) return;
    if (result.isSuccess && result.dataAsMap != null) {
      final data      = result.dataAsMap!;
      final blocks    = data['blocks']    as Map<String, dynamic>? ?? {};
      final documents = data['documents'] as Map<String, dynamic>?;

      final pageTitle   = (blocks['terms_page_title']?['title_ar']             ?? '').toString().trim();
      final emptyLabel  = (blocks['terms_empty_label']?['title_ar']            ?? '').toString().trim();
      final openLabel   = (blocks['terms_open_document_label']?['title_ar']    ?? '').toString().trim();
      final fileOnly    = (blocks['terms_file_only_hint']?['title_ar']         ?? '').toString().trim();
      final missingHint = (blocks['terms_missing_document_hint']?['title_ar']  ?? '').toString().trim();

      if (pageTitle.isNotEmpty)   _pageTitle         = pageTitle;
      if (emptyLabel.isNotEmpty)  _emptyLabel        = emptyLabel;
      if (openLabel.isNotEmpty)   _openDocumentLabel = openLabel;
      if (fileOnly.isNotEmpty)    _fileOnlyHint      = fileOnly;
      if (missingHint.isNotEmpty) _missingHint       = missingHint;

      if (documents != null && documents.isNotEmpty) {
        final orderedKeys = [
          ..._docOrder.where(documents.containsKey),
          ...documents.keys.where((k) => !_docOrder.contains(k)),
        ];
        final parsed = <_TermsDoc>[];
        for (final docType in orderedKeys) {
          final doc     = documents[docType] as Map<String, dynamic>? ?? {};
          final meta    = _docMeta[docType] ?? {'icon': Icons.description_outlined, 'title': docType};
          final fileUrl = ApiClient.buildMediaUrl(doc['file_url']?.toString()) ?? '';
          final body    = (doc['body_ar'] ?? '').toString().trim();
          final version = (doc['version'] ?? '').toString().trim();
          final content = body.isNotEmpty ? body : (fileUrl.isNotEmpty ? _fileOnlyHint : _missingHint);
          parsed.add(_TermsDoc(
            key:       docType,
            title:     (doc['label_ar'] ?? meta['title']).toString(),
            icon:      meta['icon'] as IconData,
            version:   version,
            published: _formatDate(doc['published_at']?.toString()),
            clauses:   _parseClauses(content),
            fileUrl:   fileUrl,
          ));
        }
        if (parsed.isNotEmpty) {
          setState(() => _docs = parsed);
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _hasError  = !result.isSuccess;
    });
  }

  String _formatDate(String? raw) {
    final trimmed = (raw ?? '').trim();
    if (trimmed.isEmpty) return '';
    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null) return trimmed;
    return DateFormat('dd/MM/yyyy', 'ar').format(parsed.toLocal());
  }

  Future<void> _openDocument(String fileUrl) async {
    final uri = Uri.tryParse(fileUrl.trim());
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

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: PlatformTopBar(
        pageLabel: _pageTitle,
        showBackButton: Navigator.of(context).canPop(),
        showNotificationAction: false,
        showChatAction: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () => _loadContent(forceRefresh: true),
              child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(child: const SizedBox(height: 8)),
                if (_hasError)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildErrorState(),
                  )
                else if (_docs.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    sliver: SliverList.separated(
                      itemCount: _docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, index) => _DocCard(
                        doc: _docs[index],
                        openDocumentLabel: _openDocumentLabel,
                        onOpenDocument: _openDocument,
                      ),
                    ),
                  ),
              ],
            ),
          ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.article_outlined, color: AppColors.primary, size: 32),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              _emptyLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: AppTextStyles.bodyMd,
                fontWeight: FontWeight.w800,
                color: Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.errorSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi_off_rounded, color: AppColors.error, size: 32),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text(
              'تعذّر تحميل المستندات',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: AppTextStyles.bodyLg,
                fontWeight: FontWeight.w900,
                color: AppColors.grey900,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'تحقق من الاتصال ثم اسحب للأسفل لإعادة المحاولة.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: AppTextStyles.bodyMd,
                fontWeight: FontWeight.w700,
                color: AppColors.grey500,
                height: 1.7,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            GestureDetector(
              onTap: () {
                setState(() {
                  _isLoading = true;
                  _hasError  = false;
                });
                _loadContent(forceRefresh: true);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Text(
                  'إعادة المحاولة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: AppTextStyles.bodyMd,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── _DocCard ────────────────────────────────────────────────────────────────
// لكل نوع مستند: لون مميز + أيقونة مختلفة
const _kDocAccents = <String, Color>{
  'terms':               Color(0xFF6027A2), // بنفسجي
  'privacy':             Color(0xFF0F766E), // أخضر
  'regulations':         Color(0xFF1D4ED8), // أزرق
  'prohibited_services': Color(0xFFC05621), // برتقالي
};

class _DocCard extends StatefulWidget {
  const _DocCard({
    super.key,
    required this.doc,
    required this.openDocumentLabel,
    required this.onOpenDocument,
  });
  final _TermsDoc doc;
  final String openDocumentLabel;
  final ValueChanged<String> onOpenDocument;

  @override
  State<_DocCard> createState() => _DocCardState();
}

class _DocCardState extends State<_DocCard> {
  bool _expanded = false;

  Color get _accent =>
      _kDocAccents[widget.doc.key] ?? AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final doc    = widget.doc;
    final accent = _accent;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: _expanded ? accent.withValues(alpha: 0.28) : AppColors.grey200,
        ),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          // ── header tap area ───────────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: _expanded ? accent.withValues(alpha: 0.04) : Colors.white,
              ),
              child: Row(
                children: [
                  // ── accent indicator bar ──────────────────────────
                  Container(
                    width: 3,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // ── icon ─────────────────────────────────────────
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(doc.icon, size: 16, color: accent),
                  ),
                  const SizedBox(width: 10),
                  // ── title + meta ─────────────────────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          doc.title,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: AppTextStyles.bodyLg,
                            fontWeight: FontWeight.w900,
                            color: _expanded ? accent : AppColors.grey900,
                            height: 1.3,
                          ),
                        ),
                        if (doc.version.isNotEmpty || doc.published.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (doc.version.isNotEmpty) 'إصدار ${doc.version}',
                              if (doc.published.isNotEmpty) doc.published,
                            ].join(' · '),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.grey400,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // ── expand arrow ─────────────────────────────────
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: AppDurations.normal,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: _expanded ? accent : AppColors.grey300,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── expandable body ───────────────────────────────────────────────
          AnimatedCrossFade(
            duration: AppDurations.slow,
            crossFadeState:
                _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // divider
                Container(height: 1, color: accent.withValues(alpha: 0.10)),

                // file button
                if (doc.fileUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                    child: GestureDetector(
                      onTap: () => widget.onOpenDocument(doc.fileUrl),
                      child: Container(
                        height: 38,
                        width: double.infinity,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: accent.withValues(alpha: 0.18)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.open_in_new_rounded, color: accent, size: 14),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              widget.openDocumentLabel,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: AppTextStyles.bodySm,
                                fontWeight: FontWeight.w900,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // clauses
                if (doc.clauses.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Column(
                      children: List.generate(doc.clauses.length, (i) {
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: i < doc.clauses.length - 1 ? AppSpacing.md : 0,
                          ),
                          child: _ClauseRow(
                            clause: doc.clauses[i],
                            accent: accent,
                          ),
                        );
                      }),
                    ),
                  ),

                if (doc.clauses.isEmpty && doc.fileUrl.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Text(
                      'لا توجد بنود متاحة لهذا المستند حالياً.',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: AppTextStyles.bodySm,
                        fontWeight: FontWeight.w700,
                        color: AppColors.grey400,
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

// ─── _ClauseRow ──────────────────────────────────────────────────────────────
class _ClauseRow extends StatelessWidget {
  const _ClauseRow({required this.clause, required this.accent});
  final _Clause clause;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // number badge
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            clause.number,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  clause.title,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: AppTextStyles.bodyMd,
                    fontWeight: FontWeight.w900,
                    color: AppColors.grey800,
                    height: 1.4,
                  ),
                ),
              ),
              if (clause.body.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  clause.body,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: AppTextStyles.bodySm,
                    fontWeight: FontWeight.w500,
                    color: AppColors.grey500,
                    height: 1.8,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
