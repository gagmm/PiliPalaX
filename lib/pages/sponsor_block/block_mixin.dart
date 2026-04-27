import 'dart:async' show StreamSubscription, Timer;
import 'dart:math' as math;

import 'package:PiliPalaX/http/loading_state.dart';
import 'package:PiliPalaX/http/sponsor_block.dart';
import 'package:PiliPalaX/models/common/sponsor_block/segment_model.dart';
import 'package:PiliPalaX/models/common/sponsor_block/segment_type.dart';
import 'package:PiliPalaX/models/common/sponsor_block/skip_type.dart';
import 'package:PiliPalaX/models_new/sponsor_block/segment_item.dart';
import 'package:PiliPalaX/utils/storage.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:media_kit/media_kit.dart';

/// BlockConfigMixin - SponsorBlock配置
/// 从PiliPlus移植，兼容Dart 2.19
mixin BlockConfigMixin {
  // 获取SkipType设置（从Storage读取）
  SkipType getSkipType(int index) {
    final List<dynamic>? settings = GStorage.setting.get('blockSettings') as List<dynamic>?;
    if (settings == null || settings.length != SegmentType.values.length) {
      return SkipType.skipOnce;
    }
    final int? skipIndex = settings[index] as int?;
    if (skipIndex == null || skipIndex < 0 || skipIndex >= SkipType.values.length) {
      return SkipType.skipOnce;
    }
    return SkipType.values[skipIndex];
  }

  // 获取片段颜色
  Color getBlockColor(int index) {
    final SegmentType segmentType = SegmentType.values[index];
    final List<dynamic>? colors = GStorage.setting.get('blockColor') as List<dynamic>?;
    if (colors == null || colors.length != SegmentType.values.length) {
      return segmentType.color;
    }
    final String? colorStr = colors[index] as String?;
    if (colorStr == null || colorStr.isEmpty) {
      return segmentType.color;
    }
    final int? colorInt = int.tryParse('FF$colorStr', radix: 16);
    return colorInt != null ? Color(colorInt) : segmentType.color;
  }

  late final enableSponsorBlock = GStorage.setting.get(
    SettingBoxKey.enableSponsorBlock,
    defaultValue: false,
  ) as bool;

  // 启用SponsorBlock或PGC跳过
  bool get enableBlock => enableSponsorBlock;

  // 启用的片段类型列表
  Set<String> get enableList {
    final List<dynamic>? settings = GStorage.setting.get('blockSettings') as List<dynamic>?;
    if (settings == null || settings.length != SegmentType.values.length) {
      return SegmentType.values
          .where((t) => t != SegmentType.poi_highlight && t != SegmentType.poi_dynamic)
          .map((t) => t.name)
          .toSet();
    }
    final Set<String> result = {};
    for (int i = 0; i < SegmentType.values.length; i++) {
      final int? skipIndex = settings[i] as int?;
      if (skipIndex != null && skipIndex != SkipType.disable.index) {
        result.add(SegmentType.values[i].name);
      }
    }
    return result;
  }

  // 获取颜色
  List<Color> get blockColor {
    return List<Color>.generate(
      SegmentType.values.length,
      (index) => getBlockColor(index),
    );
  }

  // 获取跳过类型设置
  List<(SegmentType, SkipType)> get blockSettings {
    return List<(SegmentType, SkipType)>.generate(
      SegmentType.values.length,
      (index) => (SegmentType.values[index], getSkipType(index)),
    );
  }

  // 限制阈值
  double get blockLimit => GStorage.setting.get(
    'blockLimit',
    defaultValue: 0.0,
  ) as double;
}

/// BlockMixin - SponsorBlock核心逻辑
/// 需要被视频播放Controller混入
mixin BlockMixin on GetxController {
  int? _lastBlockPos;
  BlockConfigMixin get blockConfig;
  StreamSubscription<Duration>? _blockListener;
  StreamSubscription<Duration>? get blockListener => _blockListener;
  late final List<SegmentModel> _segmentList = <SegmentModel>[];

  Timer? _skipTimer;
  late final listKey = GlobalKey<AnimatedListState>();
  late final List<Object> listData = [];

  RxString? get videoLabel => null;
  Player? get player;
  bool get autoPlay;
  int? get timeLength;
  bool get preInitPlayer;
  int get currPosInMilliseconds;
  bool get isFullScreen => false;

  // 是否启用阻断（UGC视频或PGC跳过）
  bool get isBlock => blockConfig.enableBlock;

  /// 查询SponsorBlock片段
  Future<void> querySponsorBlock({
    required String bvid,
    required int cid,
  }) async {
    resetBlock();

    if (!blockConfig.enableBlock) return;

    final result = await SponsorBlock.getSkipSegments(bvid: bvid, cid: cid);
    if (result is Success<List<SegmentItemModel>>) {
      handleSBData(result.response);
    } else if (result is Error) {
      if (result.code != 404 && kDebugMode) {
        result.toast();
      }
    }
  }

  /// 初始化跳过监听
  void initSkip() {
    if (isClosed) return;
    if (_segmentList.isNotEmpty) {
      _blockListener?.cancel();
      _blockListener = player?.stream.position.listen((position) {
        int currentPos = position.inSeconds;
        if (currentPos != _lastBlockPos) {
          _lastBlockPos = currentPos;
          final msPos = currentPos * 1000;
          for (SegmentModel item in _segmentList) {
            // 检查当前时间是否在片段开始位置（误差1秒内）
            if (msPos <= item.start && item.start <= msPos + 1000) {
              switch (item.skipType) {
                case SkipType.alwaysSkip:
                  onSkip(item, isSeek: false);
                  break;
                case SkipType.skipOnce:
                  if (!item.hasSkipped) {
                    item.hasSkipped = true;
                    onSkip(item, isSeek: false);
                  }
                  break;
                case SkipType.skipManually:
                  onAddItem(item);
                  break;
                default:
                  break;
              }
              break;
            }
          }
        }
      });
    }
  }

  /// 处理SponsorBlock数据
  Future<void> handleSBData(List<SegmentItemModel> list) async {
    if (list.isNotEmpty) {
      try {
        Future<void>? future;
        final duration = list.first.videoDuration ?? timeLength!;

        // 处理片段列表
        _segmentList.addAll(
          list
              .where(
                (item) =>
                    blockConfig.enableList.contains(item.category) &&
                    item.segment[1] >= item.segment[0],
              )
              .map(
                (item) {
                  final segmentModel = SegmentModel.fromItemModel(
                    item,
                    isBlock ? blockConfig : null,
                  );
                  // 检查是否为整个视频（start=0, end=0）
                  if (segmentModel.start == 0 && segmentModel.end == 0) {
                    videoLabel?.value +=
                        '${videoLabel!.value.isNotEmpty ? '/' : ''}${segmentModel.segmentType.title}';
                  }

                  // 如果正在播放，检查当前位置是否需要跳过
                  if (_blockListener == null && autoPlay && player != null) {
                    final currPos = currPosInMilliseconds;
                    if (segmentModel.contains(currPos)) {
                      _lastBlockPos = currPos;

                      switch (segmentModel.skipType) {
                        case SkipType.alwaysSkip:
                        case SkipType.skipOnce:
                          segmentModel.hasSkipped = true;
                          if (player!.state.playing) {
                            future = onSkip(segmentModel);
                          } else {
                            player!.stream.playing.firstWhere((e) {
                              if (e) {
                                future = onSkip(segmentModel);
                                return true;
                              }
                              return false;
                            }, orElse: () => false);
                          }
                          break;
                        case SkipType.skipManually:
                          onAddItem(segmentModel);
                          break;
                        default:
                          break;
                      }
                    }
                  }

                  return segmentModel;
                },
              ),
        );

        // 初始化监听（如果还没初始化）
        if (_blockListener == null && (autoPlay || preInitPlayer)) {
          await future;
          initSkip();
        }
      } catch (e) {
        if (kDebugMode) debugPrint('failed to parse sponsorblock: $e');
      }
    }
  }

  /// 添加手动跳过提示项
  void onAddItem(Object item) {
    if (listData.contains(item)) return;
    listData.insert(0, item);
    listKey.currentState?.insertItem(0);
    _skipTimer ??= Timer.periodic(const Duration(seconds: 4), (_) {
      if (listData.isNotEmpty) {
        onRemoveItem(listData.length - 1, listData.last);
      }
    });
  }

  /// 移除提示项
  void onRemoveItem(int index, Object item) {
    EasyThrottle.throttle(
      'onRemoveItem',
      const Duration(milliseconds: 500),
      () {
        try {
          listData.removeAt(index);
          if (listData.isEmpty) {
            _stopSkipTimer();
          }
          listKey.currentState?.removeItem(
            index,
            (context, animation) => buildItem(item, animation),
          );
        } catch (_) {}
      },
    );
  }

  /// 构建提示项Widget（子类实现）
  Widget buildItem(Object item, Animation<double> animation) =>
      throw UnimplementedError();

  /// 停止跳过定时器
  void _stopSkipTimer() {
    if (_skipTimer != null) {
      _skipTimer!.cancel();
      _skipTimer = null;
    }
  }

  /// 跳转到指定位置（子类实现）
  Future<void>? seekTo(Duration duration, {required bool isSeek});

  /// 显示跳过提示
  void _skipToast(SegmentModel item) {
    final bool blockToast = GStorage.setting.get(
      'blockToast',
      defaultValue: true,
    ) as bool;
    if (autoPlay && blockToast) {
      _showBlockToast('已跳过${item.segmentType.shortTitle}片段');
    }
    // 上报已查看（匿名统计）
    final bool blockTrack = GStorage.setting.get(
      'blockTrack',
      defaultValue: true,
    ) as bool;
    if (isBlock && blockTrack) {
      SponsorBlock.viewedVideoSponsorTime(item.uuid);
    }
  }

  /// 执行跳过
  Future<void> onSkip(
    SegmentModel item, {
    bool isSkip = true,
    bool isSeek = true,
  }) async {
    try {
      await seekTo(
        Duration(milliseconds: item.end),
        isSeek: isSeek,
      );
      if (isSkip) {
        _skipToast(item);
      } else {
        _showBlockToast('已跳至${item.segmentType.shortTitle}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('failed to skip: $e');
      if (isSkip) {
        _showBlockToast('${item.segmentType.shortTitle}片段跳过失败');
      } else {
        _showBlockToast('跳转失败');
      }
    }
  }

  /// 显示提示
  void _showBlockToast(String msg) {
    SmartDialog.showToast(
      msg,
      alignment: isFullScreen ? const Alignment(0, 0.7) : null,
    );
  }

  /// 显示投票对话框
  void _showVoteDialog(SegmentModel segment) {
    showDialog(
      context: Get.context!,
      builder: (context) => AlertDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                dense: true,
                title: const Text('赞成票', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Get.back();
                  _doVote(segment.uuid, 1);
                },
              ),
              ListTile(
                dense: true,
                title: const Text('反对票', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Get.back();
                  _doVote(segment.uuid, 0);
                },
              ),
              ListTile(
                dense: true,
                title: const Text('更改类别', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Get.back();
                  _showCategoryDialog(segment);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 执行投票
  void _doVote(String uuid, int type) => SponsorBlock.voteOnSponsorTime(
    uuid: uuid,
    type: type,
  ).then((i) => SmartDialog.showToast(i.isSuccess ? '投票成功' : '投票失败: $i'));

  /// 显示更改类别对话框
  void _showCategoryDialog(SegmentModel segment) {
    showDialog(
      context: Get.context!,
      builder: (context) => AlertDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: SegmentType.values
                .map(
                  (item) => ListTile(
                    dense: true,
                    onTap: () {
                      Get.back();
                      SponsorBlock.voteOnSponsorTime(
                        uuid: segment.uuid,
                        category: item,
                      ).then((i) {
                        SmartDialog.showToast(
                          '类别更改${i.isSuccess ? '成功' : '失败: $i'}',
                        );
                      });
                    },
                    title: Text.rich(
                      TextSpan(
                        children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Container(
                              height: 10,
                              width: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: blockConfig.blockColor[item.index],
                              ),
                            ),
                            style: const TextStyle(fontSize: 14, height: 1),
                          ),
                          TextSpan(
                            text: ' ${item.title}',
                            style: const TextStyle(fontSize: 14, height: 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  /// 显示SponsorBlock详情对话框
  void showSBDetail() {
    showDialog(
      context: Get.context!,
      builder: (context) => AlertDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _segmentList
                .map(
                  (item) => ListTile(
                    onTap: () {
                      Get.back();
                      if (isBlock) {
                        _showVoteDialog(item);
                      }
                    },
                    dense: true,
                    title: Text.rich(
                      TextSpan(
                        children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Container(
                              height: 10,
                              width: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: blockConfig.blockColor[item.segmentType.index],
                              ),
                            ),
                            style: const TextStyle(fontSize: 14, height: 1),
                          ),
                          TextSpan(
                            text: ' ${item.segmentType.title}',
                            style: const TextStyle(fontSize: 14, height: 1),
                          ),
                        ],
                      ),
                    ),
                    contentPadding: const EdgeInsets.only(left: 16, right: 8),
                    subtitle: Text(
                      '${_formatDuration(item.start / 1000)} 至 ${_formatDuration(item.end / 1000)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.skipType.label,
                          style: const TextStyle(fontSize: 13),
                        ),
                        if (item.end != 0)
                          SizedBox(
                            width: 36,
                            height: 36,
                            child: IconButton(
                              tooltip: item.skipType == SkipType.showOnly
                                  ? '跳至此片段'
                                  : '跳过此片段',
                              onPressed: () {
                                Get.back();
                                onSkip(
                                  item,
                                  isSkip: item.skipType != SkipType.showOnly,
                                  isSeek: false,
                                );
                              },
                              style: IconButton.styleFrom(
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: Icon(
                                item.skipType == SkipType.showOnly
                                    ? Icons.my_location
                                    : MdiIcons.debugStepOver,
                                size: 18,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                          )
                        else
                          const SizedBox(width: 10),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  /// 格式化时长
  String _formatDuration(double seconds) {
    final int mins = (seconds / 60).floor();
    final int secs = (seconds % 60).floor();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  /// 取消监听器
  void cancelBlockListener() {
    if (_blockListener != null) {
      _blockListener!.cancel();
      _blockListener = null;
    }
  }

  /// 重置Block状态
  void resetBlock() {
    cancelBlockListener();
    _lastBlockPos = null;
    videoLabel?.value = '';
    _segmentList.clear();
  }

  /// 获取第一个片段位置（用于初始化定位）
  Duration? getFirstSegment([int pos = 0]) {
    final sortedList = List<SegmentModel>.from(_segmentList)..sort();
    for (var i in sortedList) {
      final start = i.start;
      final end = i.end;
      if (start == end) {
        continue;
      } else if (start - pos < 100) {
        if (i.skipType == SkipType.alwaysSkip ||
            (i.skipType == SkipType.skipOnce && !i.hasSkipped)) {
          _skipToast(i);
          pos = math.max(pos, end);
        }
      } else {
        break;
      }
    }
    if (pos != 0) {
      return Duration(milliseconds: pos);
    }
    return null;
  }

  @override
  void onClose() {
    _stopSkipTimer();
    if (blockConfig.enableBlock) {
      resetBlock();
    }
    super.onClose();
  }
}
