class UserInfo {
  final int viewCount;
  final double minutesSaved;
  final int segmentCount;

  const UserInfo({
    required this.viewCount,
    required this.minutesSaved,
    required this.segmentCount,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) => UserInfo(
    viewCount: json['viewCount'],
    minutesSaved: (json['minutesSaved'] as num).toDouble(),
    segmentCount: json['segmentCount'],
  );

  @override
  String toString() {
    final int totalMinutes = minutesSaved.round();
    final int hours = totalMinutes ~/ 60;
    final int minutes = totalMinutes % 60;
    String timeStr;
    if (hours > 0) {
      timeStr = '${hours}小时${minutes}分钟';
    } else {
      timeStr = '${minutes}分钟';
    }
    return ('您提交了 ${segmentCount} 片段\n'
        '您为大家节省了 ${viewCount} 片段\n'
        '($timeStr 的生命)');
  }
}
