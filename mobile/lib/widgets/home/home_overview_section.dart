import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../constants/app_theme.dart';

class HomeOverviewSection extends StatelessWidget {
  final String accountName;
  final String accountSubtitle;
  final String? avatarUrl;
  final bool isLoading;
  final bool isLoggedIn;
  final int notificationCount;
  final List<HomeOverviewStat> stats;
  final List<String> latestItems;
  final VoidCallback onNotificationsTap;
  final VoidCallback onOrdersTap;
  final VoidCallback onSearchTap;
  final VoidCallback onProfileTap;

  const HomeOverviewSection({
    super.key,
    required this.accountName,
    required this.accountSubtitle,
    required this.avatarUrl,
    required this.isLoading,
    required this.isLoggedIn,
    required this.notificationCount,
    required this.stats,
    required this.latestItems,
    required this.onNotificationsTap,
    required this.onOrdersTap,
    required this.onSearchTap,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeroCard(context),
          const SizedBox(height: 12),
          _buildStats(context),
          const SizedBox(height: 12),
          _buildQuickActions(context),
          const SizedBox(height: 12),
          _buildLatestActivity(context),
        ],
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primaryLight,
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppShadows.elevated,
      ),
      child: Stack(
        children: [
          Positioned(
            top: -20,
            left: -16,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isLoggedIn ? 'أهلًا، $accountName' : 'أهلًا بك في نوافذ',
                            style: theme.textTheme.headlineLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            accountSubtitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Semantics(
                      button: true,
                      label: isLoggedIn ? 'فتح الحساب' : 'فتح تسجيل الدخول',
                      child: InkWell(
                        onTap: onProfileTap,
                        borderRadius: BorderRadius.circular(22),
                        child: _buildAvatar(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _HeroPill(
                      icon: Icons.notifications_active_outlined,
                      label: notificationCount > 0
                          ? '$notificationCount إشعار جديد'
                          : 'الإشعارات جاهزة للمتابعة',
                      onTap: onNotificationsTap,
                    ),
                    _HeroPill(
                      icon: Icons.manage_search_rounded,
                      label: 'ابحث عن الخدمة المناسبة بسرعة',
                      onTap: onSearchTap,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final imageUrl = (avatarUrl ?? '').trim();
    final provider = imageUrl.isNotEmpty
        ? CachedNetworkImageProvider(imageUrl)
        : null;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: isLoading
          ? const Padding(
              padding: EdgeInsets.all(18),
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Colors.white,
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: provider != null
                  ? Image(
                      image: provider,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildAvatarFallback(),
                    )
                  : _buildAvatarFallback(),
            ),
    );
  }

  Widget _buildAvatarFallback() {
    return Container(
      color: Colors.white.withValues(alpha: 0.12),
      child: const Icon(
        Icons.person_rounded,
        color: Colors.white,
        size: 28,
      ),
    );
  }

  Widget _buildStats(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ملخص سريع',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width >= 520 ? 4 : 2;
              final mainAxisExtent = width < 360
                  ? 146.0
                  : width < 520
                      ? 126.0
                      : 110.0;
              return GridView.builder(
                shrinkWrap: true,
                itemCount: stats.length,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: mainAxisExtent,
                ),
                itemBuilder: (context, index) {
                  final item = stats[index];
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.grey50,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: isLoading
                        ? const _SkeletonBox(height: 72)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(item.icon, color: item.color, size: 22),
                              const Spacer(),
                              Text(
                                item.value,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.label,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final accountLabel = isLoggedIn ? 'الحساب' : 'تسجيل الدخول';
    final actions = <_QuickActionData>[
      _QuickActionData(
        label: 'الطلبات',
        icon: Icons.receipt_long_rounded,
        onTap: onOrdersTap,
      ),
      _QuickActionData(
        label: 'الإشعارات',
        icon: Icons.notifications_outlined,
        onTap: onNotificationsTap,
      ),
      _QuickActionData(
        label: 'البحث',
        icon: Icons.search_rounded,
        onTap: onSearchTap,
      ),
      _QuickActionData(
        label: accountLabel,
        icon: Icons.person_outline_rounded,
        onTap: onProfileTap,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'اختصارات سريعة',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width >= 520 ? 4 : 2;
              return GridView.builder(
                itemCount: actions.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: width >= 520 ? 1.1 : 1.7,
                ),
                itemBuilder: (context, index) {
                  final item = actions[index];
                  return Semantics(
                    button: true,
                    label: item.label,
                    child: InkWell(
                      onTap: item.onTap,
                      borderRadius: BorderRadius.circular(20),
                      child: Ink(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.primarySurface.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(item.icon, color: AppColors.primary),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item.label,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLatestActivity(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'آخر النشاط',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (isLoading)
            const _SkeletonBox(height: 96)
          else if (latestItems.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.inbox_outlined,
                    size: 32,
                    color: AppColors.grey500,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'لا توجد تحديثات بعد',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'ابدأ بالبحث أو تصفح الخدمات وستظهر هنا آخر الأنشطة المهمة.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Column(
              children: latestItems.take(3).map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppTextStyles.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class HomeOverviewStat {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const HomeOverviewStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class _QuickActionData {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickActionData({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

class _HeroPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeroPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final maxTextWidth = MediaQuery.sizeOf(context).width * 0.58;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxTextWidth),
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double height;

  const _SkeletonBox({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFFF3F0F9), Color(0xFFECE7F7), Color(0xFFF3F0F9)],
        ),
      ),
    );
  }
}