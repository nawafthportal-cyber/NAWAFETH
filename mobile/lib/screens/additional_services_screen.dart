import 'package:flutter/material.dart';
import '../widgets/bottom_nav.dart';
import '../services/extras_service.dart';

class AdditionalServicesScreen extends StatefulWidget {
  const AdditionalServicesScreen({super.key});

  @override
  State<AdditionalServicesScreen> createState() =>
      _AdditionalServicesScreenState();
}

class _AdditionalServicesScreenState extends State<AdditionalServicesScreen> {
  String? selectedMain; // الخدمة الرئيسية
  String? selectedSub; // الفرعية
  bool inRequest = false; // شاشة الطلب
  bool inCheckout = false; // شاشة الدفع

  // بيانات الكتالوج من الـ API
  List<Map<String, dynamic>> _catalogItems = [];
  bool _isCatalogLoading = true;
  String? _selectedSku;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final result = await ExtrasService.fetchCatalog();
    if (!mounted) return;
    if (result.isSuccess && result.data is List) {
      setState(() {
        _catalogItems = (result.data as List).cast<Map<String, dynamic>>();
        _isCatalogLoading = false;
      });
    } else {
      setState(() => _isCatalogLoading = false);
    }
  }

  Future<void> _buyExtra(String sku) async {
    final result = await ExtrasService.buy(sku);
    if (!mounted) return;
    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم الطلب بنجاح')),
      );
      setState(() {
        inCheckout = false;
        inRequest = false;
        selectedSub = null;
        selectedMain = null;
        _selectedSku = null;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'فشل الطلب')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          inCheckout
              ? "الدفع"
              : inRequest
              ? "طلب الخدمة"
              : selectedMain != null
              ? selectedMain!
              : "الخدمات الإضافية",
          style: const TextStyle(
            fontFamily: "Cairo",
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: _buildBody(),
      ),
      bottomNavigationBar: const CustomBottomNav(currentIndex: 2), // ✅
    );
  }

  Widget _buildBody() {
    if (inCheckout) return _checkout();
    if (inRequest) return _requestForm();
    if (selectedSub != null) return _subServices(selectedSub!);
    if (selectedMain != null) return _mainServiceDetails(selectedMain!);
    return _mainServices();
  }

  // 🟣 المستوى الأول: الخدمات الرئيسية
  Widget _mainServices() {
    final services = [
      {"title": "إدارة العملاء", "icon": Icons.group, "color": Colors.teal},
      {
        "title": "الإدارة المالية",
        "icon": Icons.account_balance_wallet,
        "color": Colors.deepPurple,
      },
      {"title": "التقارير", "icon": Icons.bar_chart, "color": Colors.orange},
      {
        "title": "تطوير تصميم المنصات",
        "icon": Icons.design_services,
        "color": Colors.indigo,
      },
      {"title": "زيادة السعة", "icon": Icons.storage, "color": Colors.green},
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: services.length,
      itemBuilder: (context, index) {
        final item = services[index];
        return GestureDetector(
          onTap: () => setState(() => selectedMain = item["title"] as String),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: (item["color"] as Color).withOpacity(0.1),
                  child: Icon(
                    item["icon"] as IconData,
                    color: item["color"] as Color,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    item["title"] as String,
                    style: const TextStyle(
                      fontFamily: "Cairo",
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 18,
                  color: Colors.black45,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 🟣 المستوى الثاني: تفاصيل خدمة رئيسية
  Widget _mainServiceDetails(String service) {
    final subOptions = {
      "الإدارة المالية": [
        "تسجيل الحساب البنكي (QR)",
        "خدمات الدفع الإلكتروني",
        "الفواتير",
        "كشف حساب شامل",
        "الربط مع ضريبة القيمة المضافة",
        "تصدير PDF/Excel",
      ],
      "إدارة العملاء": ["إضافة عميل جديد", "إدارة العقود", "إرسال إشعارات"],
      "التقارير": ["تقرير شهري", "تقرير ربع سنوي", "تقرير سنوي"],
      "تطوير تصميم المنصات": ["تصميم واجهة جديدة", "تحسين تجربة المستخدم"],
      "زيادة السعة": ["رفع عدد الملفات", "زيادة مساحة التخزين"],
    };

    final items = subOptions[service] ?? [];

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final sub = items[index];
        return GestureDetector(
          onTap: () => setState(() => selectedSub = sub),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.white,
              border: Border.all(color: Colors.deepPurple.shade100),
            ),
            child: Row(
              children: [
                const Icon(Icons.arrow_right, color: Colors.deepPurple),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sub,
                    style: const TextStyle(fontFamily: "Cairo", fontSize: 15),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 18,
                  color: Colors.black38,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 🟣 المستوى الثالث: شاشة فرعية
  Widget _subServices(String service) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "تفاصيل الخدمة",
            style: TextStyle(
              fontFamily: "Cairo",
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple.shade700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            service,
            style: const TextStyle(fontFamily: "Cairo", fontSize: 15),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => setState(() => inRequest = true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                "طلب الخدمة",
                style: TextStyle(fontFamily: "Cairo", color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🟣 المستوى الرابع: نموذج طلب الخدمة
  Widget _requestForm() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "تفاصيل الطلب:",
            style: TextStyle(
              fontFamily: "Cairo",
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          const TextField(
            decoration: InputDecoration(
              labelText: "البيانات المطلوبة",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => setState(() => inCheckout = true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "متابعة للدفع",
                style: TextStyle(fontFamily: "Cairo", color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🟣 المستوى الخامس: الدفع
  Widget _checkout() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "مراجعة الطلب",
            style: TextStyle(
              fontFamily: "Cairo",
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.shopping_bag, color: Colors.deepPurple),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      selectedSub ?? "خدمة",
                      style: const TextStyle(fontFamily: "Cairo"),
                    ),
                  ),
                  const Text(
                    "100 ر.س",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFamily: "Cairo",
                      color: Colors.deepPurple,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    "تم الدفع بنجاح ✅",
                    textAlign: TextAlign.center,
                  ),
                ),
              );
              setState(() {
                selectedMain = null;
                selectedSub = null;
                inRequest = false;
                inCheckout = false;
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              "الدفع عبر Apple Pay",
              style: TextStyle(fontFamily: "Cairo", color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
