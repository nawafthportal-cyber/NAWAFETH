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
                  backgroundColor: AppColors.primary,
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
                  final sideReserve = compact ? 120.0 : 136.0;
                  final brandMaxWidth =
                      constraints.maxWidth - (sideReserve * 2);
                  final faceHeight = compact ? 40.0 : 44.0;
                  final faceWidth = _resolveCenterFaceWidth(
                    availableWidth: brandMaxWidth,
                    faceHeight: faceHeight,
                  );
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

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: Center(
                          child: Padding(
                            padding:
                                EdgeInsets.symmetric(horizontal: sideReserve),
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
                          width: sideReserve,
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
                color: overlay
                    ? const Color(0xFF8D5FD3)
                    : const Color(0xFF5B2F88),
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
              : const [Color(0xFF5B2F88), Color(0xFF8D5FD3)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: (overlay ? const Color(0xFFD8A877) : const Color(0xFF6E42A0))
                .withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: const Text(
        'ن',
        style: TextStyle(
          color: Colors.white,
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
