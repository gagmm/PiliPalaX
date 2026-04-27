import 'package:PiliPalaX/models/common/sponsor_block/segment_type.dart';
import 'package:PiliPalaX/models/common/sponsor_block/skip_type.dart';
import 'package:PiliPalaX/models_new/sponsor_block/segment_item.dart';
import 'package:PiliPalaX/pages/sponsor_block/block_mixin.dart';

class SegmentModel implements Comparable<SegmentModel> {
  SegmentModel({
    required this.uuid,
    required this.segmentType,
    required this.start,
    required this.end,
    required this.skipType,
  });

  factory SegmentModel.fromItemModel(
    SegmentItemModel item,
    BlockConfigMixin? config,
  ) {
    final segmentType = SegmentType.fromName(item.category);
    // 兼容Dart 2.19: 使用单独字段而不是Record类型
    final skipType = config != null
        ? config.blockSettings[segmentType.index].second
        : SkipType.disable;
    return SegmentModel(
      uuid: item.uuid,
      segmentType: segmentType,
      start: item.segment[0],
      end: item.segment[1],
      skipType: skipType,
    );
  }

  final String uuid;
  final SegmentType segmentType;
  final int start;  // 代替 segment.$1
  final int end;    // 代替 segment.$2
  final SkipType skipType;
  bool hasSkipped = false;

  @override
  int compareTo(SegmentModel other) {
    if (start != other.start) {
      return start.compareTo(other.start);
    }
    return end.compareTo(other.end);
  }

  bool contains(int ms) => start <= ms && ms <= end;
}
