import '../services/app_settings_service.dart';

String _insertThousandsSeparators(String integerPart) {
  if (integerPart.isEmpty) return integerPart;
  final isNegative = integerPart.startsWith('-');
  final digits = isNegative ? integerPart.substring(1) : integerPart;
  if (digits.isEmpty) return integerPart;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  final grouped = buffer.toString();
  return isNegative ? '-$grouped' : grouped;
}

String _withThousandsSeparators(String formatted) {
  final dotIndex = formatted.indexOf('.');
  if (dotIndex >= 0) {
    return '${_insertThousandsSeparators(formatted.substring(0, dotIndex))}'
        '${formatted.substring(dotIndex)}';
  }
  return _insertThousandsSeparators(formatted);
}

String formatDisplayNumber(
  num value, {
  int fractionDigits = 2,
  bool? fixedDecimals,
}) {
  final useFixed = fixedDecimals ?? AppSettingsService.instance.showFixedDecimals;
  var formatted = value.toStringAsFixed(fractionDigits);
  if (!useFixed) {
    formatted = formatted.replaceFirst(RegExp(r'\.?0+$'), '');
  }
  if (formatted == '-0') return '0';
  return _withThousandsSeparators(formatted);
}

String formatMoney(num value) {
  return formatDisplayNumber(value, fractionDigits: 0, fixedDecimals: true);
}

