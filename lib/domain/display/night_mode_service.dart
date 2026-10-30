class NightModeService {
  const NightModeService();

  static bool isActive({
    required int startMinutes,
    required int endMinutes,
    required DateTime now,
    bool enabled = true,
  }) {
    if (!enabled) {
      return false;
    }
    final start = _normalize(startMinutes);
    final end = _normalize(endMinutes);
    if (start == end) {
      return false;
    }
    final local = now.toLocal();
    final current = local.hour * 60 + local.minute;
    if (start < end) {
      return current >= start && current < end;
    }
    return current >= start || current < end;
  }

  static int _normalize(int minutes) {
    final value = minutes % 1440;
    return value < 0 ? value + 1440 : value;
  }
}
