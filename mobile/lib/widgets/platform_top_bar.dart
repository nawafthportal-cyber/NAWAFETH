import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_theme.dart';
import '../screens/provider_profile_screen.dart';
import '../services/top_bar_branding_service.dart';

class PlatformTopBar extends StatefulWidget implements PreferredSizeWidget {
  final bool overlay;
  final bool showMenuButton;
  final bool showBackButton;
  final bool showNotificationAction;
  final bool showChatAction;
  final String? pageLabel;
  final VoidCallback? onMenuTap;
  final VoidCallback? onBackTap;
  final VoidCallback? onNotificationsTap;
  final VoidCallback? onChatsTap;
  final int notificationCount;
  final int chatCount;
  final double height;
  final List<Widget> trailingActions;

  const PlatformTopBar({
    super.key,
    this.overlay = false,
    this.showMenuButton = false,
    this.showBackButton = false,
    this.showNotificationAction = true,
    this.showChatAction = true,
    this.pageLabel,
    this.onMenuTap,
    this.onBackTap,
    this.onNotificationsTap,
    this.onChatsTap,
    this.notificationCount = 0,
    this.chatCount = 0,
    this.height = 68,
    this.trailingActions = const [],
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  State<PlatformTopBar> createState() => _PlatformTopBarState();
}

class _PlatformTopBarState extends State<PlatformTopBar> {
  TopBarSponsorData? _sponsor;
  String? _brandLogoUrl;
  Timer? _sponsorRotateTimer;
  bool _showSponsorFace = false;

  @override
  void initState() {
    super.initState();
    _loadBranding();
  }

  @override
  void dispose() {
    _sponsorRotateTimer?.cancel();
    super.dispose();
  }

  void _restartSponsorRotation() {
    _sponsorRotateTimer?.cancel();
    _sponsorRotateTimer = null;
    _showSponsorFace = false;
    final sponsor = _sponsor;
    if (sponsor == null) {
      return;
    }
    _sponsorRotateTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _sponsor == null) return;
      setState(() {
        _showSponsorFace = !_showSponsorFace;
      });
    });
  }

  Future<void> _loadBranding() async {
    final results = await Future.wait<Object?>([
      TopBarBrandingService.fetchActiveSponsor(),
      TopBarBrandingService.fetchBrandLogo(),
    ]);
    final sponsor = results[0] as TopBarSponsorData?;
    final brandLogoUrl = results[1] as String?;
    if (!mounted) return;
    setState(() {
      _sponsor = sponsor;
      _brandLogoUrl = brandLogoUrl;
      _showSponsorFace = false;
    });
    _restartSponsorRotation();
  }

  Future<void> _openSponsorDestination(TopBarSponsorData sponsor) async {
    final redirect = sponsor.redirectUrl?.trim();
    if (redirect != null && redirect.isNotEmpty) {
      final uri = Uri.tryParse(redirect);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    final providerId = sponsor.providerId?.trim();
    if (providerId == null || providerId.isEmpty || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderProfileScreen(providerId: providerId),
      ),
    );
  }

  Future<void> _handleSponsorTap() async {
    final sponsor = _sponsor;
    if (sponsor == null || !mounted) return;

    final message = sponsor.messageBody?.trim();
    final title =
        sponsor.name.trim().isNotEmpty ? sponsor.name.trim() : 'الراعي الرسمي';
    final canOpen = sponsor.hasLink;
    final dialogMessage = (message != null && message.isNotEmpty)
        ? message
        : 'لا توجد رسالة مضافة للرعاية حالياً.';
    final action = await showDialog<String>(
      context: context,
      barrierColor: const Color(0xFF0A1024).withValues(alpha: 0.62),
      builder: (context) {
        final screenSize = MediaQuery.sizeOf(context);
        final dialogWidth = math.min(screenSize.width - 26, 560.0);
        final maxDialogHeight = math.min(screenSize.height * 0.84, 760.0);
        final hasProviderFallback =
            sponsor.providerId?.trim().isNotEmpty == true && !canOpen;
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
          backgroundColor: Colors.transparent,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: SizedBox(
              width: dialogWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxDialogHeight),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(34),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFFEFF), Color(0xFFF7F2FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: const Color(0xFFE9DDFB)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF231942).withValues(alpha: 0.12),
                        blurRadius: 36,
                        offset: const Offset(0, 18),
                      ),
                      BoxShadow(
                        color: const Color(0xFFFACC15).withValues(alpha: 0.10),
                        blurRadius: 48,
                        offset: const Offset(0, 8),
                        spreadRadius: -18,
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: -80,
                        right: -40,
                        child: Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF8B5CF6)
                                    .withValues(alpha: 0.12),
                                const Color(0xFFE9D5FF)
                                    .withValues(alpha: 0.04),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: -36,
                        bottom: 108,
                        child: Container(
                          width: 132,
                          height: 132,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFD1FAE5)
                                .withValues(alpha: 0.34),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(26),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFFFEFF),
                                    Color(0xFFF7F3FF),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                border: Border.all(
                                  color: const Color(0xFFE8DEF8),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF2E1065)
                                        .withValues(alpha: 0.08),
                                    blurRadius: 24,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _buildSponsorDialogPill(
                                              icon:
                                                  Icons.workspace_premium_rounded,
                                              label: 'رعاية مميزة',
                                              background:
                                                  const Color(0xFFF3E8FF),
                                              foreground:
                                                  const Color(0xFF6D28D9),
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              'رسالة الراعي الرسمي',
                                              style: const TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF6B7280),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              title,
                                              style: const TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 25,
                                                fontWeight: FontWeight.w900,
                                                color: Color(0xFF2E236D),
                                                height: 1.15,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          color: Colors.white,
                                          border: Border.all(
                                            color: const Color(0xFFE5E7EB),
                                          ),
                                        ),
                                        child: IconButton(
                                          onPressed: () =>
                                              Navigator.of(context).pop('close'),
                                          splashRadius: 20,
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            color: Color(0xFF667085),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          height: 112,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(22),
                                            gradient: const LinearGradient(
                                              colors: [
                                                Color(0xFFF8FAFC),
                                                Color(0xFFF5F3FF),
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFE9DDFB),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 72,
                                                height: 72,
                                                padding:
                                                    const EdgeInsets.all(10),
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(22),
                                                  color: Colors.white,
                                                  border: Border.all(
                                                    color: const Color(0xFFE9DDFB),
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color:
                                                          const Color(0xFF2E1065)
                                                              .withValues(
                                                                  alpha: 0.05),
                                                      blurRadius: 18,
                                                      offset:
                                                          const Offset(0, 8),
                                                    ),
                                                  ],
                                                ),
                                                child: _SponsorBadge(
                                                  assetUrl: sponsor.assetUrl,
                                                  fallbackLabel: title,
                                                  overlay: false,
                                                ),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      title,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontFamily: 'Cairo',
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        color:
                                                            Color(0xFF2E236D),
                                                        height: 1.2,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      canOpen
                                                          ? 'يمكن الانتقال مباشرة إلى صفحة الراعي أو موقعه.'
                                                          : 'هذه الرسالة مخصصة للتعريف بالراعي داخل المنصة.',
                                                      style: const TextStyle(
                                                        fontFamily: 'Cairo',
                                                        fontSize: 12.5,
                                                        height: 1.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color:
                                                            Color(0xFF667085),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _buildSponsorDialogPill(
                                        icon: Icons.auto_awesome_rounded,
                                        label: 'رسالة تعريفية',
                                        background: const Color(0xFFEEF2FF),
                                        foreground: const Color(0xFF4338CA),
                                      ),
                                      _buildSponsorDialogPill(
                                        icon: canOpen
                                            ? Icons.link_rounded
                                            : Icons.visibility_outlined,
                                        label: canOpen
                                            ? 'يتضمن رابطًا مباشرًا'
                                            : hasProviderFallback
                                                ? 'يفتح ملف الراعي'
                                                : 'عرض فقط',
                                        background: canOpen
                                            ? const Color(0xFFDCFCE7)
                                            : const Color(0xFFF3F4F6),
                                        foreground: canOpen
                                            ? const Color(0xFF15803D)
                                            : const Color(0xFF4B5563),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                color: Colors.white.withValues(alpha: 0.84),
                                border: Border.all(
                                  color: const Color(0xFFE9DDFB),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF2E1065)
                                        .withValues(alpha: 0.05),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'رسالة الراعي',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF344054),
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          color: const Color(0xFFF5F3FF),
                                        ),
                                        alignment: Alignment.center,
                                        child: const Icon(
                                          Icons.format_quote_rounded,
                                          color: Color(0xFF7C3AED),
                                          size: 22,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    constraints: BoxConstraints(
                                      maxHeight: math.max(
                                        170,
                                        maxDialogHeight * 0.32,
                                      ),
                                    ),
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 14, 16, 14),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(22),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFFFFEFF),
                                          Color(0xFFF9FAFB),
                                        ],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                      border: Border.all(
                                        color: const Color(0xFFEDE9FE),
                                      ),
                                    ),
                                    child: Scrollbar(
                                      thumbVisibility: dialogMessage.length > 280,
                                      child: SingleChildScrollView(
                                        child: Text(
                                          dialogMessage,
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 15,
                                            height: 2,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF475467),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildSponsorDialogAction(
                                    label: 'إغلاق',
                                    icon: Icons.close_rounded,
                                    foreground: const Color(0xFF344054),
                                    background: Colors.white,
                                    borderColor: const Color(0xFFE4E7EC),
                                    onPressed: () =>
                                        Navigator.of(context).pop('close'),
                                  ),
                                ),
                                if (canOpen) ...[
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildSponsorDialogAction(
                                      label: 'زيارة الرابط',
                                      icon: Icons.open_in_new_rounded,
                                      foreground: Colors.white,
                                      background: const Color(0xFF16A34A),
                                      borderColor: const Color(0xFF86EFAC),
                                      onPressed: () =>
                                          Navigator.of(context).pop('open'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    if (action == 'open') {
      await _openSponsorDestination(sponsor);
    }
  }

  Widget _buildSponsorDialogPill({
    required IconData icon,
    required String label,
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSponsorDialogAction({
    required String label,
    required IconData icon,
    required Color foreground,
    required Color background,
    required Color borderColor,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: background == Colors.white
              ? null
              : LinearGradient(
                  colors: [
                    background,
                    Color.alphaBlend(
                      Colors.white.withValues(alpha: 0.16),
                      background,
                    ),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
          color: background == Colors.white ? background : null,
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: background == Colors.white
                  ? const Color(0xFF101828).withValues(alpha: 0.04)
                  : background.withValues(alpha: 0.22),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onPressed,
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final foreground = widget.overlay
        ? Colors.white
        : (isDark ? Colors.white : const Color(0xFF512DA8));
    final chromeBackground = widget.overlay
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: isDark ? 0.08 : 0.96);
    final chromeBorder = widget.overlay
        ? Colors.white.withValues(alpha: 0.18)
        : (isDark
            ? Colors.white.withValues(alpha: 0.1)
            : const Color(0xFFE8DEF8));
    final barDecoration = widget.overlay
        ? BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withValues(alpha: 0.16),
                Colors.black.withValues(alpha: 0.04),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          )
        : const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFAF8FF), Color(0xFFF8F4FD)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            border: Border(
              bottom: BorderSide(color: Color(0x12673AB7)),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x0D121224),
                blurRadius: 32,
                offset: Offset(0, 10),
              ),
            ],
          );

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: barDecoration,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: widget.height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 380;
                  final buttonSize = compact ? 40.0 : 44.0;
                  final faceHeight = compact ? 40.0 : 44.0;
                  final actions = <Widget>[
                    ...widget.trailingActions,
                    if (widget.trailingActions.isNotEmpty &&
                        (widget.showNotificationAction ||
                            widget.showChatAction))
                      const SizedBox(width: 4),
                    if (widget.showNotificationAction)
                      PlatformTopBarActionButton(
                        size: buttonSize,
                        icon: Icons.notifications_none_rounded,
                        foreground: foreground,
                        background: chromeBackground,
                        borderColor: chromeBorder,
                        count: widget.notificationCount,
                        onTap: widget.onNotificationsTap,
                      ),
                    if (widget.showNotificationAction && widget.showChatAction)
                      const SizedBox(width: 4),
                    if (widget.showChatAction)
                      PlatformTopBarActionButton(
                        size: buttonSize,
                        icon: Icons.chat_bubble_outline_rounded,
                        foreground: foreground,
                        background: chromeBackground,
                        borderColor: chromeBorder,
                        count: widget.chatCount,
                        onTap: widget.onChatsTap,
                      ),
                  ];
                  final actionButtonCount = widget.trailingActions.length +
                      (widget.showNotificationAction ? 1 : 0) +
                      (widget.showChatAction ? 1 : 0);
                  final actionGapCount =
                      actionButtonCount > 0 ? actionButtonCount - 1 : 0;
                  final leadingReserve = buttonSize + 8;
                  final trailingReserve = math.max(
                    compact ? 120.0 : 136.0,
                    (actionButtonCount * buttonSize) +
                        (actionGapCount * 4) +
                        12,
                  );
                  final brandMaxWidth = math.max(
                    80.0,
                    constraints.maxWidth - leadingReserve - trailingReserve,
                  );
                  final faceWidth = _resolveCenterFaceWidth(
                    availableWidth: brandMaxWidth,
                    faceHeight: faceHeight,
                  );

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: trailingReserve,
                              right: leadingReserve,
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    brandMaxWidth > 80 ? brandMaxWidth : 80,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.center,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 280),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: ScaleTransition(
                                        scale:
                                            Tween<double>(begin: 0.96, end: 1)
                                                .animate(animation),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: (_showSponsorFace && _sponsor != null)
                                      ? _buildSponsorFace(
                                          key: const ValueKey('sponsor-face'),
                                          shellWidth: faceWidth,
                                          shellHeight: faceHeight,
                                          chromeBackground: chromeBackground,
                                          chromeBorder: chromeBorder,
                                        )
                                      : _buildBrandFace(
                                          key: const ValueKey('brand-face'),
                                          shellWidth: faceWidth,
                                          shellHeight: faceHeight,
                                          chromeBackground: chromeBackground,
                                          chromeBorder: chromeBorder,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          width: leadingReserve,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _buildLeadingButton(
                              context: context,
                              foreground: foreground,
                              background: chromeBackground,
                              borderColor: chromeBorder,
                              buttonSize: buttonSize,
                              isDark: isDark,
                              overlay: widget.overlay,
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: trailingReserve,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: actions,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandFace({
    Key? key,
    required double shellWidth,
    required double shellHeight,
    required Color chromeBackground,
    required Color chromeBorder,
  }) {
    return _buildFaceShell(
      key: key,
      width: shellWidth,
      height: shellHeight,
      chromeBackground: chromeBackground,
      chromeBorder: chromeBorder,
      padding: const EdgeInsets.all(4),
      child: Center(
        child: _AppBadge(
          overlay: widget.overlay,
          logoUrl: _brandLogoUrl,
        ),
      ),
    );
  }

  Widget _buildSponsorFace({
    Key? key,
    required double shellWidth,
    required double shellHeight,
    required Color chromeBackground,
    required Color chromeBorder,
  }) {
    final sponsor = _sponsor;
    final sponsorName = sponsor?.name.trim().isNotEmpty == true
        ? sponsor!.name.trim()
        : 'مساحة الرعاية';
    return InkWell(
      key: key,
      onTap: sponsor == null ? null : _handleSponsorTap,
      borderRadius: BorderRadius.circular(14),
      child: _buildFaceShell(
        width: shellWidth,
        height: shellHeight,
        chromeBackground: chromeBackground,
        chromeBorder: chromeBorder,
        padding: const EdgeInsets.all(4),
        child: Center(
          child: _SponsorBadge(
            assetUrl: sponsor?.assetUrl,
            fallbackLabel: sponsorName,
            overlay: widget.overlay,
          ),
        ),
      ),
    );
  }

  Widget _buildFaceShell({
    Key? key,
    required double width,
    required double height,
    required Color chromeBackground,
    required Color chromeBorder,
    required EdgeInsetsGeometry padding,
    required Widget child,
  }) {
    return SizedBox(
      key: key,
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: chromeBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: chromeBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }

  double _resolveCenterFaceWidth({
    required double availableWidth,
    required double faceHeight,
  }) {
    // Web brand mark is square — match button dimensions
    return math.min(availableWidth, faceHeight);
  }

  Widget _buildLeadingButton({
    required BuildContext context,
    required Color foreground,
    required Color background,
    required Color borderColor,
    required double buttonSize,
    required bool isDark,
    required bool overlay,
  }) {
    if (widget.showBackButton) {
      return PlatformTopBarActionButton(
        size: buttonSize,
        icon: Icons.arrow_back_rounded,
        foreground: foreground,
        background: background,
        borderColor: borderColor,
        onTap: widget.onBackTap ?? () => Navigator.of(context).maybePop(),
      );
    }

    if (widget.showMenuButton) {
      // Hamburger uses purple-tinted background — matches web nav-menu-btn
      final menuBg = overlay
          ? Colors.white.withValues(alpha: 0.14)
          : (isDark
              ? const Color(0xFF673AB7).withValues(alpha: 0.14)
              : const Color(0x14673AB7));
      final menuBorder = overlay
          ? Colors.white.withValues(alpha: 0.18)
          : (isDark
              ? const Color(0xFF673AB7).withValues(alpha: 0.22)
              : const Color(0x1E673AB7));
      return PlatformTopBarActionButton(
        size: buttonSize,
        icon: Icons.menu_rounded,
        foreground: foreground,
        background: menuBg,
        borderColor: menuBorder,
        onTap: widget.onMenuTap,
      );
    }

    return SizedBox(width: buttonSize, height: buttonSize);
  }
}

class PlatformTopBarActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color foreground;
  final Color background;
  final Color borderColor;
  final int count;
  final double size;

  const PlatformTopBarActionButton({
    super.key,
    required this.icon,
    required this.foreground,
    required this.background,
    required this.borderColor,
    this.onTap,
    this.count = 0,
    this.size = 42,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: foreground, size: size <= 36 ? 18 : 19),
          ),
          if (count > 0)
            Positioned(
              top: -4,
              right: -5,
              child: Container(
                constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                padding: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                    fontSize: 7.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PlatformTopBarMenuButton<T> extends StatelessWidget {
  final IconData icon;
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final Color foreground;
  final Color background;
  final Color borderColor;

  const PlatformTopBarMenuButton({
    super.key,
    required this.icon,
    required this.itemBuilder,
    required this.foreground,
    required this.background,
    required this.borderColor,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: PopupMenuButton<T>(
        tooltip: '',
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: foreground, size: 21),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: onSelected,
        itemBuilder: itemBuilder,
      ),
    );
  }
}

class _AppBadge extends StatelessWidget {
  final bool overlay;
  final String? logoUrl;

  const _AppBadge({required this.overlay, this.logoUrl});

  @override
  Widget build(BuildContext context) {
    final resolvedLogoUrl = logoUrl?.trim();
    if (resolvedLogoUrl != null && resolvedLogoUrl.isNotEmpty) {
      return Container(
        width: 30,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: overlay ? 0.94 : 0.98),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: overlay
                ? Colors.white.withValues(alpha: 0.22)
                : const Color(0x1A8D5FD3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: overlay ? 0.10 : 0.08),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: CachedNetworkImage(
          imageUrl: resolvedLogoUrl,
          fit: BoxFit.contain,
          errorWidget: (_, __, ___) => Center(
            child: Text(
              'ن',
              style: TextStyle(
                color:
                    overlay ? const Color(0xFF8D5FD3) : const Color(0xFF5B2F88),
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
        ),
      );
    }
    return _buildDefaultBadge();
  }

  Widget _buildDefaultBadge() {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        gradient: LinearGradient(
          colors: overlay
              ? const [Color(0xFFF1A559), Color(0xFFB788F3)]
              : const [Color(0xFFFAF8FF), Color(0xFFF8F4FD)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: overlay
            ? [
                BoxShadow(
                  color: const Color(0xFFD8A877).withValues(alpha: 0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ]
            : null,
      ),
      child: Text(
        'ن',
        style: TextStyle(
          color: overlay ? Colors.white : const Color(0xFF512DA8),
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
      ),
    );
  }
}

class _SponsorBadge extends StatefulWidget {
  final String? assetUrl;
  final String fallbackLabel;
  final bool overlay;

  const _SponsorBadge({
    required this.assetUrl,
    required this.fallbackLabel,
    required this.overlay,
  });

  @override
  State<_SponsorBadge> createState() => _SponsorBadgeState();
}

class _SponsorBadgeState extends State<_SponsorBadge> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;
  _SponsorBadgeBox _logoBox = _SponsorBadgeBox.square;

  @override
  void initState() {
    super.initState();
    _resolveLogoBox();
  }

  @override
  void didUpdateWidget(covariant _SponsorBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.assetUrl ?? '').trim() != (widget.assetUrl ?? '').trim()) {
      _resolveLogoBox();
    }
  }

  @override
  void dispose() {
    _detachImageListener();
    super.dispose();
  }

  void _detachImageListener() {
    final stream = _imageStream;
    final listener = _imageStreamListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _imageStream = null;
    _imageStreamListener = null;
  }

  void _resolveLogoBox() {
    _detachImageListener();
    final resolvedUrl = widget.assetUrl?.trim();
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      if (mounted) {
        setState(() => _logoBox = _SponsorBadgeBox.square);
      }
      return;
    }

    final provider = CachedNetworkImageProvider(resolvedUrl);
    final stream = provider.resolve(const ImageConfiguration());
    final listener = ImageStreamListener(
      (imageInfo, _) {
        final width = imageInfo.image.width.toDouble();
        final height = imageInfo.image.height.toDouble();
        if (!mounted) return;
        setState(() {
          _logoBox = _SponsorBadgeBox.fromDimensions(width, height);
        });
        _detachImageListener();
      },
      onError: (_, __) {
        if (!mounted) return;
        setState(() => _logoBox = _SponsorBadgeBox.square);
        _detachImageListener();
      },
    );
    _imageStream = stream;
    _imageStreamListener = listener;
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = widget.assetUrl?.trim();
    return Container(
      width: 30,
      height: 30,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: widget.overlay
              ? const Color(0x14FFFFFF)
              : const Color(0x1A8D5FD3),
        ),
        gradient: widget.overlay
            ? const LinearGradient(
                colors: [Color(0x1AF1A559), Color(0x26FFFFFF)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              )
            : const LinearGradient(
                colors: [Color(0x1AF1A559), Color(0x1A8D5FD3)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: (resolvedUrl != null && resolvedUrl.isNotEmpty)
          ? SizedBox(
              width: _logoBox.width,
              height: _logoBox.height,
              child: CachedNetworkImage(
                imageUrl: resolvedUrl,
                fit: BoxFit.contain,
                alignment: Alignment.center,
                errorWidget: (_, __, ___) => _fallbackText(),
              ),
            )
          : _fallbackText(),
    );
  }

  Widget _fallbackText() {
    return Text(
      widget.fallbackLabel.trim().isEmpty
          ? 'ر'
          : widget.fallbackLabel.trim().characters.first,
      style: const TextStyle(
        color: AppColors.deepPurple,
        fontSize: 13,
        fontWeight: FontWeight.w900,
        fontFamily: 'Cairo',
      ),
    );
  }
}

class _SponsorBadgeBox {
  final double width;
  final double height;

  const _SponsorBadgeBox._(this.width, this.height);

  static const _SponsorBadgeBox square = _SponsorBadgeBox._(20, 20);
  static const _SponsorBadgeBox wide = _SponsorBadgeBox._(22, 14);
  static const _SponsorBadgeBox tall = _SponsorBadgeBox._(14, 22);

  static _SponsorBadgeBox fromDimensions(double width, double height) {
    if (width <= 0 || height <= 0) {
      return square;
    }
    final ratio = width / height;
    if (ratio >= 1.55) {
      return wide;
    }
    if (ratio <= 0.82) {
      return tall;
    }
    return square;
  }
}
