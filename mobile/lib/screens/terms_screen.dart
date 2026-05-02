import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_theme.dart';
import '../services/content_service.dart';
import '../services/api_client.dart';
import '../widgets/platform_top_bar.dart';

// ─── color tokens ────────────────────────────────────────────────────────────
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
    required this.publishedMillis,
    required this.clauses,
    required this.fileUrl,
  });
  final String key;
  final String title;
  final IconData icon;
  final String version;
  final String published;
  final int publishedMillis;
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
  String _heroKicker         = 'المركز القانوني';
  String _pageSummary        = 'اطلع على سياسات نوافذ الرسمية بطريقة واضحة ومنظمة قبل استخدام خدمات المنصة.';
  String _emptyLabel         = 'لا توجد مستندات متاحة حالياً';
  String _documentsLabel     = 'المستندات';
  String _latestUpdateLabel  = 'آخر تحديث';
  String _fileCountLabel     = 'مرفقات رسمية';
  String _railTitle          = 'المستندات';
  String _openDocumentLabel  = 'عرض المستند';
  String _fileOnlyHint       = 'اضغط على "عرض المستند" لفتح النسخة الرسمية.';
  String _missingHint        = 'لا توجد بيانات متاحة لهذا المستند حالياً.';

  List<_TermsDoc> _docs       = [];
  final _scrollController     = ScrollController();
  final Map<String, GlobalKey> _docKeys = <String, GlobalKey>{};
  String? _activeDocKey;

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
      final heroKicker  = (blocks['terms_kicker']?['title_ar']                  ?? '').toString().trim();
      final pageSummary = (blocks['terms_page_summary']?['title_ar']            ?? '').toString().trim();
      final emptyLabel  = (blocks['terms_empty_label']?['title_ar']            ?? '').toString().trim();
      final documentsLabel = (blocks['terms_documents_label']?['title_ar']     ?? '').toString().trim();
      final latestUpdateLabel = (blocks['terms_latest_update_label']?['title_ar'] ?? '').toString().trim();
      final fileCountLabel = (blocks['terms_file_count_label']?['title_ar']    ?? '').toString().trim();
      final railTitle   = (blocks['terms_rail_title']?['title_ar']             ?? '').toString().trim();
      final openLabel   = (blocks['terms_open_document_label']?['title_ar']    ?? '').toString().trim();
      final fileOnly    = (blocks['terms_file_only_hint']?['title_ar']         ?? '').toString().trim();
      final missingHint = (blocks['terms_missing_document_hint']?['title_ar']  ?? '').toString().trim();

      if (pageTitle.isNotEmpty)   _pageTitle         = pageTitle;
      if (heroKicker.isNotEmpty)  _heroKicker        = heroKicker;
      if (pageSummary.isNotEmpty) _pageSummary       = pageSummary;
      if (emptyLabel.isNotEmpty)  _emptyLabel        = emptyLabel;
      if (documentsLabel.isNotEmpty) _documentsLabel = documentsLabel;
      if (latestUpdateLabel.isNotEmpty) _latestUpdateLabel = latestUpdateLabel;
      if (fileCountLabel.isNotEmpty) _fileCountLabel = fileCountLabel;
      if (railTitle.isNotEmpty)   _railTitle         = railTitle;
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
          final publishedAt = DateTime.tryParse((doc['published_at'] ?? '').toString().trim())?.toLocal();
          final content = body.isNotEmpty ? body : (fileUrl.isNotEmpty ? _fileOnlyHint : _missingHint);
          parsed.add(_TermsDoc(
            key:       docType,
            title:     (doc['label_ar'] ?? meta['title']).toString(),
            icon:      meta['icon'] as IconData,
            version:   version,
            published: _formatDate(doc['published_at']?.toString()),
            publishedMillis: publishedAt?.millisecondsSinceEpoch ?? 0,
            clauses:   _parseClauses(content),
            fileUrl:   fileUrl,
          ));
        }
        if (parsed.isNotEmpty) {
          setState(() {
            _docs = parsed;
            if (_activeDocKey == null || !parsed.any((doc) => doc.key == _activeDocKey)) {
              _activeDocKey = parsed.first.key;
            }
          });
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

  String get _latestPublishedLabel {
    if (_docs.isEmpty) return '-';
    final candidates = _docs.where((doc) => doc.published.isNotEmpty).toList();
    if (candidates.isEmpty) return '-';
    candidates.sort((left, right) => right.publishedMillis.compareTo(left.publishedMillis));
    return candidates.first.published;
  }

  int get _officialFileCount => _docs.where((doc) => doc.fileUrl.isNotEmpty).length;

  GlobalKey _keyForDoc(String docKey) {
    return _docKeys.putIfAbsent(docKey, GlobalKey.new);
  }

  Future<void> _jumpToDoc(String docKey) async {
    final key = _keyForDoc(docKey);
    setState(() {
      _activeDocKey = docKey;
    });
    final targetContext = key.currentContext;
    if (targetContext == null) return;
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.06,
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
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _buildHeroSection(),
                  ),
                ),
                if (_docs.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: _buildNavRail(),
                    ),
                  ),
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
                      itemBuilder: (context, index) {
                        final doc = _docs[index];
                        return Container(
                          key: _keyForDoc(doc.key),
                          child: _DocCard(
                            doc: doc,
                            openDocumentLabel: _openDocumentLabel,
                            onOpenDocument: _openDocument,
                          ),
                        );
                      },
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

  Widget _buildHeroSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF24135F), Color(0xFF5132A7), Color(0xFF0F766E)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E211956),
            blurRadius: 34,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: -40,
            bottom: -70,
            child: Container(
              width: 180,
              height: 180,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x1FFFFFFF),
              ),
            ),
          ),
          Positioned(
            right: -24,
            top: -32,
            child: Container(
              width: 140,
              height: 140,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x162DD4BF),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _heroKicker,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Color(0xC2FFFFFF),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _pageTitle,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _pageSummary,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xD1FFFFFF),
                  height: 1.85,
                ),
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 420;
                  final stats = [
                    _buildHeroStat(_documentsLabel, _toArabicDigits('${_docs.length}')),
                    _buildHeroStat(_latestUpdateLabel, _latestPublishedLabel),
                    _buildHeroStat(_fileCountLabel, _toArabicDigits('$_officialFileCount')),
                  ];
                  if (narrow) {
                    return Column(
                      children: [
                        for (var i = 0; i < stats.length; i++) ...[
                          stats[i],
                          if (i < stats.length - 1) const SizedBox(height: 10),
                        ],
                      ],
                    );
                  }
                  return Row(
                    children: [
                      for (var i = 0; i < stats.length; i++) ...[
                        Expanded(child: stats[i]),
                        if (i < stats.length - 1) const SizedBox(width: 10),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroStat(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x2EFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Color(0xB8FFFFFF),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavRail() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x140F172A)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _railTitle,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final doc in _docs) ...[
                  _buildNavChip(doc),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavChip(_TermsDoc doc) {
    final selected = _activeDocKey == doc.key;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _jumpToDoc(doc.key),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0x140F766E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0x3D0F766E) : const Color(0x120F172A),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                gradient: const LinearGradient(
                  colors: [Color(0x1F0F766E), Color(0x197C3AED)],
                ),
              ),
              child: Icon(doc.icon, size: 18, color: const Color(0xFF115E59)),
            ),
            const SizedBox(width: 9),
            Text(
              doc.title,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: selected ? const Color(0xFF115E59) : const Color(0xFF243042),
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
  bool _expanded = true;

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
