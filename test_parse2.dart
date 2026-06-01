int _chineseNumToInt(String s) {
  const map = {'零':0,'一':1,'二':2,'两':2,'三':3,'四':4,'五':5,'六':6,'七':7,'八':8,'九':9,'十':10};
  s = s.trim();
  if (s.isEmpty) return -1;
  final n = int.tryParse(s);
  if (n != null) return n;
  if (map.containsKey(s)) return map[s]!;
  if (s.startsWith('十') && s.length > 1) return 10 + (map[s[1]] ?? 0);
  if (s.endsWith('十') && s.length > 1) return (map[s[0]] ?? 0) * 10;
  if (s.contains('十')) {
    final parts = s.split('十');
    final tens = parts[0].isEmpty ? 1 : (map[parts[0]] ?? 0);
    final ones = parts.length > 1 && parts[1].isNotEmpty ? (map[parts[1]] ?? 0) : 0;
    return tens * 10 + ones;
  }
  return -1;
}

void main() {
  final tests = ["晚上十点吃药", "九点半吃药", "十三点去吃饭", "下午三点半吃药"];
  
  for (final text in tests) {
    String normalized = text;
    
    normalized = normalized.replaceAllMapped(
      RegExp(r'([零一二两三四五六七八九十百]+)\s*点'),
      (m) {
        final num = _chineseNumToInt(m.group(1)!);
        print('  中文点: matched="${m.group(1)}", num=$num');
        return num >= 0 ? '$num点' : m.group(0)!;
      },
    );
    normalized = normalized.replaceAllMapped(
      RegExp(r'([零一二两三四五六七八九十百]+)\s*点半'),
      (m) {
        final num = _chineseNumToInt(m.group(1)!);
        print('  中文点半: matched="${m.group(1)}", num=$num');
        return num >= 0 ? '$num点半' : m.group(0)!;
      },
    );
    
    print('Input: "$text" → normalized: "$normalized"');
    print('');
  }
}
