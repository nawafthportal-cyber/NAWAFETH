class RequestStatusFilters {
  static const String allLabel = 'الكل';
  static const String newLabel = 'جديد';
  static const String inProgressLabel = 'تحت التنفيذ';
  static const String completedLabel = 'مكتمل';
  static const String cancelledLabel = 'ملغي';

  static const String newStatus = 'new';
  static const String providerAcceptedStatus = 'provider_accepted';
  static const String awaitingClientStatus = 'awaiting_client';
  static const String inProgressStatus = 'in_progress';
  static const String completedStatus = 'completed';
  static const String cancelledStatus = 'cancelled';

  static const List<String> orderedLabels = [
    allLabel,
    newLabel,
    inProgressLabel,
    completedLabel,
    cancelledLabel,
  ];

  static String? apiValueForLabel(String? label) {
    switch (label) {
      case newLabel:
        return newStatus;
      case inProgressLabel:
        return inProgressStatus;
      case completedLabel:
        return completedStatus;
      case cancelledLabel:
        return cancelledStatus;
      default:
        return null;
    }
  }

  static String statusGroupForRawStatus(String? rawStatus) {
    switch ((rawStatus ?? '').trim().toLowerCase()) {
      case newStatus:
      case providerAcceptedStatus:
      case awaitingClientStatus:
        return newStatus;
      case inProgressStatus:
        return inProgressStatus;
      case completedStatus:
        return completedStatus;
      case 'canceled':
      case cancelledStatus:
        return cancelledStatus;
      default:
        return newStatus;
    }
  }

  static String labelForRawStatus(String? rawStatus) {
    switch ((rawStatus ?? '').trim().toLowerCase()) {
      case newStatus:
        return newLabel;
      case providerAcceptedStatus:
        return 'تم قبول الطلب';
      case awaitingClientStatus:
        return 'بانتظار اعتماد العميل للتفاصيل';
      case inProgressStatus:
        return inProgressLabel;
      case completedStatus:
        return completedLabel;
      case 'canceled':
      case cancelledStatus:
        return cancelledLabel;
      default:
        return (rawStatus ?? '').trim().isEmpty ? '—' : rawStatus!.trim();
    }
  }
}