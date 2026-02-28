import 'package:flutter/material.dart';
import '../services/content_service.dart';

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  List<bool> _expanded = [false, false, false, false];
  bool _isLoading = true;

  List<Map<String, dynamic>> _terms = [
    {
      "title": "اتفاقية الاستخدام",
      "lastUpdate": "آخر تحديث: 10-08-2025",
      "content":
          "باستخدامك للمنصة، فإنك تقر وتوافق على الالتزام بجميع الشروط والأحكام. "
          "يجب استخدام المنصة بما يتوافق مع الأنظمة واللوائح المعمول بها في المملكة العربية السعودية.",
      "icon": Icons.article_outlined,
    },
    {
      "title": "سياسة الخصوصية",
      "lastUpdate": "آخر تحديث: 05-08-2025",
      "content":
          "تحرص المنصة على حماية بيانات مستخدميها. يتم جمع البيانات الأساسية فقط لأغراض تحسين الخدمات "
          "ولا تتم مشاركتها مع أي طرف ثالث دون إذن المستخدم إلا بموجب الأنظمة السعودية.",
      "icon": Icons.privacy_tip_outlined,
    },
    {
      "title": "الأنظمة والتشريعات المتبعة",
      "lastUpdate": "آخر تحديث: 01-08-2025",
      "content":
          "تخضع المنصة للأنظمة والتشريعات المعمول بها في المملكة العربية السعودية. "
          "يتعين على جميع المستخدمين الالتزام بجميع القوانين ذات العلاقة عند استخدام المنصة.",
      "icon": Icons.gavel_outlined,
    },
    {
      "title": "الخدمات الممنوعة",
      "lastUpdate": "آخر تحديث: 20-07-2025",
      "content":
          "يُمنع عرض أو طلب أي خدمات مخالفة للأنظمة أو الآداب العامة أو تتعارض مع التشريعات المعمول بها. "
          "وأي مخالفة قد تؤدي إلى إيقاف الحساب بشكل نهائي.",
      "icon": Icons.block_outlined,
    },
  ];

  // Map API doc_type → icon and fallback title
  static const Map<String, Map<String, dynamic>> _docMeta = {
    'terms': {'icon': Icons.article_outlined, 'title': 'اتفاقية الاستخدام'},
    'privacy': {'icon': Icons.privacy_tip_outlined, 'title': 'سياسة الخصوصية'},
    'regulations': {'icon': Icons.gavel_outlined, 'title': 'الأنظمة والتشريعات المتبعة'},
    'prohibited_services': {'icon': Icons.block_outlined, 'title': 'الخدمات الممنوعة'},
  };

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
      final documents = data['documents'] as Map<String, dynamic>?;
      if (documents != null && documents.isNotEmpty) {
        final List<Map<String, dynamic>> apiTerms = [];
        for (final entry in documents.entries) {
          final docType = entry.key;
          final doc = entry.value as Map<String, dynamic>? ?? {};
          final meta = _docMeta[docType] ?? {'icon': Icons.description_outlined, 'title': docType};
          apiTerms.add({
            'title': meta['title'],
            'lastUpdate': doc['published_at'] != null ? 'آخر تحديث: ${doc['published_at']}' : '',
            'content': doc['file_url']?.toString() ?? '',
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
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("الشروط والأحكام"),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _terms.length,
        itemBuilder: (context, index) {
          final item = _terms[index];
          final expanded = _expanded[index];

          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
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

                    // ✅ حالة الموافقة + آخر تحديث
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "✅ تمت الموافقة مسبقًا",
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          item["lastUpdate"],
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),

                    // ✅ النص التفصيلي عند التوسع
                    AnimatedCrossFade(
                      firstChild: const SizedBox.shrink(),
                      secondChild: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          item["content"],
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 14,
                            height: 1.5,
                            color: Colors.black87,
                          ),
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
