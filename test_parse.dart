// 测试正则是否工作
void main() {
  final tests = [
    "13点去吃饭",
    "晚上12点吃药",
    "晚上十点吃药",
    "11.30吃药",
    "九点半吃药",
  ];
  
  for (final text in tests) {
    String normalized = text;
    // Step 1: 11.30 → 11点30分
    normalized = normalized.replaceAllMapped(
      RegExp(r'(\d{1,2})[.:：](\d{2})'),
      (m) => '${m.group(1)}点${m.group(2)}分',
    );
    print('Input: "$text" → normalized: "$normalized"');
    
    // Test "X点XX分"
    final hourMinMatch = RegExp(r'(\d+)\s*点\s*(\d+)\s*分?').firstMatch(normalized);
    if (hourMinMatch != null) {
      print('  → hourMinMatch: h=${hourMinMatch.group(1)}, m=${hourMinMatch.group(2)}');
    }
    
    // Test "X点"
    final simpleHourMatch = RegExp(r'(?<!\d)(\d{1,2})\s*点(?!\s*[半分\d])').firstMatch(normalized);
    if (simpleHourMatch != null) {
      print('  → simpleHourMatch: h=${simpleHourMatch.group(1)}');
    } else {
      print('  → simpleHourMatch: null');
    }
    
    // Try without lookbehind
    final simpleNoLookbehind = RegExp(r'(^|\D)(\d{1,2})\s*点(?!\s*[半分\d])').firstMatch(normalized);
    if (simpleNoLookbehind != null) {
      print('  → noLookbehind: h=${simpleNoLookbehind.group(2)}');
    } else {
      print('  → noLookbehind: null');
    }
    
    print('');
  }
}
