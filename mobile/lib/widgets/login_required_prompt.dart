import 'package:flutter/material.dart';

import '../constants/app_theme.dart';

class LoginRequiredPrompt extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onLoginTap;
  final String loginButtonLabel;

  const LoginRequiredPrompt({
    super.key,
    required this.title,
    required this.message,
    this.onLoginTap,
    this.loginButtonLabel = 'تسجيل الدخول',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_outline_rounded,
              color: AppColors.primary,
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isDark
                  ? AppTextStyles.textPrimaryDark
                  : AppTextStyles.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              height: 1.6,
              color: isDark
                  ? AppTextStyles.textSecondaryDark
                  : AppTextStyles.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onLoginTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(loginButtonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showLoginRequiredPromptDialog(
  BuildContext context, {
  required String title,
  required String message,
  String loginButtonLabel = 'تسجيل الدخول',
  String cancelButtonLabel = 'لاحقًا',
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            LoginRequiredPrompt(
              title: title,
              message: message,
              loginButtonLabel: loginButtonLabel,
              onLoginTap: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pushNamed('/login');
              },
            ),
            Positioned(
              top: 10,
              left: 10,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => Navigator.of(dialogContext).pop(),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.close_rounded, size: 18),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -18,
              left: 24,
              right: 24,
              child: TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(
                  cancelButtonLabel,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
