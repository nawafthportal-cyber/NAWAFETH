import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/colors.dart';
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
    this.height = 62,
    this.trailingActions = const [],
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  State<PlatformTopBar> createState() => _PlatformTopBarState();
}

class _PlatformTopBarState extends State<PlatformTopBar> {
  TopBarSponsorData? _sponsor;
  Timer? _sponsorRotateTimer;
  bool _showSponsorFace = false;

  @override
  void initState() {
    super.initState();
    _loadSponsor();
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

  Future<void> _loadSponsor() async {
    final sponsor = await TopBarBrandingService.fetchActiveSponsor();
    if (!mounted) return;
    setState(() {
      _sponsor = sponsor;
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
    final title = sponsor.name.trim().isNotEmpty ? sponsor.name.trim() : 'الراعي الرسمي';
    final canOpen = sponsor.hasLink;
    final action = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            (message != null && message.isNotEmpty)
                ? message
                : 'لا توجد رسالة مضافة للرعاية حالياً.',
            style: const TextStyle(
              fontFamily: 'Cairo',
              height: 1.7,
            ),
          ),
          actions: [
            if (canOpen)
              FilledButton(
                onPressed: () => Navigator.of(context).pop('open'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.deepPurple,
                  foregroundColor: Colors.white,
                ),
                child: const Text(
                  'فتح الرابط',
                  style: TextStyle(fontFamily: 'Cairo'),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('close'),
              child: const Text(
                'إغلاق',
                style: TextStyle(fontFamily: 'Cairo'),
              ),
            ),
          ],
        );
      },
    );
    if (action == 'open') {
      await _openSponsorDestination(sponsor);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final foreground = widget.overlay
        ? Colors.white
        : (isDark ? Colors.white : const Color(0xFF56316D));
    final secondary = widget.overlay
        ? Colors.white.withValues(alpha: 0.84)
        : (isDark ? Colors.white70 : const Color(0xFF7B6A90));
    final chromeBackground = widget.overlay
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: isDark ? 0.08 : 0.82);
    final chromeBorder = widget.overlay
        ? Colors.white.withValues(alpha: 0.18)
        : const Color(0xFFDACDED);
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
        : BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFFFFF), Color(0xFFF8F4FD)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            border: Border(
              bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 8),
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
                  final buttonSize = compact ? 36.0 : 38.0;
                  final sideReserve = compact ? 104.0 : 120.0;
                  final brandMaxWidth = constraints.maxWidth - (sideReserve * 2);
                  final actions = <Widget>[
                    ...widget.trailingActions,
                    if (widget.trailingActions.isNotEmpty &&
                        (widget.showNotificationAction || widget.showChatAction))
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

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: sideReserve),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.pageLabel != null && widget.pageLabel!.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 1),
                                    child: Text(
                                      widget.pageLabel!.trim(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 8.8,
                                        fontWeight: FontWeight.w800,
                                        fontFamily: 'Cairo',
                                        color: secondary,
                                      ),
                                    ),
                                  ),
                                ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: brandMaxWidth > 80 ? brandMaxWidth : 80),
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
                                            scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
                                            child: child,
                                          ),
                                        );
                                      },
                                      child: (_showSponsorFace && _sponsor != null)
                                          ? _buildSponsorFace(
                                              key: const ValueKey('sponsor-face'),
                                              foreground: foreground,
                                              secondary: secondary,
                                              chromeBackground: chromeBackground,
                                              chromeBorder: chromeBorder,
                                            )
                                          : _buildBrandFace(
                                              key: const ValueKey('brand-face'),
                                              foreground: foreground,
                                              chromeBackground: chromeBackground,
                                              chromeBorder: chromeBorder,
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          width: sideReserve,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _buildLeadingButton(
                              context: context,
                              foreground: foreground,
                              background: chromeBackground,
                              borderColor: chromeBorder,
                              buttonSize: buttonSize,
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: sideReserve,
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
    required Color foreground,
    required Color chromeBackground,
    required Color chromeBorder,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: chromeBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: chromeBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(
                colors: widget.overlay
                    ? const [Color(0xFFF1A559), Color(0xFFB788F3)]
                    : const [Color(0xFF5B2F88), Color(0xFF8D5FD3)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
            child: const Text(
              'ن',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'نوافــذ',
            style: TextStyle(
              color: foreground,
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              fontFamily: 'Cairo',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSponsorFace({
    Key? key,
    required Color foreground,
    required Color secondary,
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
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: chromeBackground,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: chromeBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'برعاية',
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                fontFamily: 'Cairo',
                color: secondary,
              ),
            ),
            const SizedBox(width: 5),
            _SponsorBadge(
              assetUrl: sponsor?.assetUrl,
              fallbackLabel: sponsorName,
              overlay: widget.overlay,
            ),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 112),
              child: Text(
                sponsorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Cairo',
                  color: foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeadingButton({
    required BuildContext context,
    required Color foreground,
    required Color background,
    required Color borderColor,
    required double buttonSize,
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
      return PlatformTopBarActionButton(
        size: buttonSize,
        icon: Icons.menu_rounded,
        foreground: foreground,
        background: background,
        borderColor: borderColor,
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

class _SponsorBadge extends StatelessWidget {
  final String? assetUrl;
  final String fallbackLabel;
  final bool overlay;

  const _SponsorBadge({
    required this.assetUrl,
    required this.fallbackLabel,
    required this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = assetUrl?.trim();
    final badge = Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: overlay
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
          ? Image.network(
              resolvedUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallbackText(),
            )
          : _fallbackText(),
    );
    return badge;
  }

  Widget _fallbackText() {
    return Text(
      fallbackLabel.trim().isEmpty ? 'ر' : fallbackLabel.trim().characters.first,
      style: const TextStyle(
        color: AppColors.deepPurple,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        fontFamily: 'Cairo',
      ),
    );
  }
}
