import 'dart:convert';

import 'package:PiliPalaX/common/widgets/pair.dart';
import 'package:PiliPalaX/http/init.dart';
import 'package:PiliPalaX/http/loading_state.dart';
import 'package:PiliPalaX/http/sponsor_block_api.dart';
import 'package:PiliPalaX/models/common/sponsor_block/post_segment_model.dart';
import 'package:PiliPalaX/models/common/sponsor_block/segment_type.dart';
import 'package:PiliPalaX/models_new/sponsor_block/segment_item.dart';
import 'package:PiliPalaX/models_new/sponsor_block/user_info.dart';
import 'package:PiliPalaX/utils/login.dart';
import 'package:PiliPalaX/utils/storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

/// https://github.com/hanydd/BilibiliSponsorBlock/wiki/API
abstract final class SponsorBlock {
  static String get blockServer =>
      GStorage.setting.get(SettingBoxKey.blockServer, defaultValue: 'https://api.sponsor.block') ??
      'https://api.sponsor.block';

  static final options = Options(
    followRedirects: true,
    headers: kDebugMode
        ? null
        : {
            'origin': 'PiliPalaX',
            'x-ext-version': '1.0.0',
          },
    validateStatus: (status) => true,
  );

  static Error getErrMsg(Response res) {
    String statusMessage;
    switch (res.statusCode) {
      case 200:
        statusMessage = '意料之外的响应';
        break;
      case 400:
        statusMessage = '参数错误';
        break;
      case 403:
        statusMessage = '被自动审核机制拒绝';
        break;
      case 404:
        statusMessage = '未找到数据';
        break;
      case 409:
        statusMessage = '重复提交';
        break;
      case 429:
        statusMessage = '提交太快（触发速率控制）';
        break;
      case 500:
        statusMessage = '服务器无法获取信息';
        break;
      case -1:
        statusMessage = res.data['message'].toString();
        break;
      default:
        statusMessage = res.statusMessage ?? res.statusCode.toString();
    }
    if (res.statusCode != null && res.statusCode != -1) {
      final data = res.data;
      if (res.statusCode == 200 ||
          (data is String && data.isNotEmpty && data.length < 200)) {
        statusMessage = '$statusMessage：$data';
      }
    }
    return Error(statusMessage, code: res.statusCode);
  }

  static String _api(String url) => '$blockServer/api/$url';

  static Future<LoadingState<List<SegmentItemModel>>> getSkipSegments({
    required String bvid,
    required int cid,
  }) async {
    final res = await Request().get(
      _api(SponsorBlockApi.skipSegments),
      data: {
        'videoID': bvid,
        'cid': cid,
      },
      options: options,
    );

    if (res.statusCode == 200) {
      final list = res.data as List;
      return Success(list.map((i) => SegmentItemModel.fromJson(i)).toList());
    }
    return getErrMsg(res);
  }

  static Future<LoadingState<void>> voteOnSponsorTime({
    required String uuid,
    int? type,
    SegmentType? category,
  }) async {
    final String? userId = GStorage.localCache.get(LocalCacheKey.blockUserID);
    final res = await Request().post(
      _api(SponsorBlockApi.voteOnSponsorTime),
      queryParameters: {
        'UUID': uuid,
        if (type != null) 'type': type,
        if (category != null) 'category': category.name,
        'userID': userId ?? '',
      },
      options: options,
    );
    return res.statusCode == 200 ? const Success(null) : getErrMsg(res);
  }

  static Future<LoadingState<void>> viewedVideoSponsorTime(String uuid) async {
    final res = await Request().post(
      _api(SponsorBlockApi.viewedVideoSponsorTime),
      data: {'UUID': uuid},
      options: options,
    );
    return res.statusCode == 200 ? const Success(null) : getErrMsg(res);
  }

  static Future<LoadingState<void>> uptimeStatus() async {
    final res = await Request().get(
      _api(SponsorBlockApi.uptimeStatus),
      options: options,
    );
    if (res.statusCode == 200 &&
        res.data is String &&
        _isStringNumeric(res.data)) {
      return const Success(null);
    }
    return getErrMsg(res);
  }

  static bool _isStringNumeric(String str) {
    return RegExp(r'^[\d\.]+$').hasMatch(str);
  }

  static Future<LoadingState<UserInfo>> userInfo(
    List<String> query, {
    String? userId,
  }) async {
    final String? actualUserId =
        userId ?? GStorage.localCache.get(LocalCacheKey.blockUserID);
    final res = await Request().get(
      _api(SponsorBlockApi.userInfo),
      queryParameters: {
        'userID': actualUserId ?? '',
        'values': jsonEncode(query),
      },
      options: options,
    );
    if (res.statusCode == 200) {
      return Success(UserInfo.fromJson(res.data));
    }
    return getErrMsg(res);
  }

  static Future<LoadingState<List<SegmentItemModel>>> postSkipSegments({
    required String bvid,
    required int cid,
    required double videoDuration,
    required List<PostSegmentModel> segments,
  }) async {
    final String? userId = GStorage.localCache.get(LocalCacheKey.blockUserID);
    final res = await Request().post(
      _api(SponsorBlockApi.skipSegments),
      data: {
        'videoID': bvid,
        'cid': cid.toString(),
        'userID': userId ?? '',
        'userAgent': kDebugMode
            ? 'Mozilla/5.0 (Linux; Android 10; SM-G975F)'
            : 'PiliPalaX/1.0.0',
        'videoDuration': videoDuration,
        'segments': segments
            .map(
              (item) => {
                'segment': [item.segment.first, item.segment.second],
                'category': item.category.name,
                'actionType': item.actionType.name,
              },
            )
            .toList(),
      },
      options: options,
    );

    if (res.statusCode == 200) {
      final list = res.data as List;
      return Success(list.map((i) => SegmentItemModel.fromJson(i)).toList());
    }
    return getErrMsg(res);
  }

  static Future<LoadingState<String>> getPortVideo({
    required String bvid,
    required int cid,
  }) async {
    final res = await Request().get(
      _api(SponsorBlockApi.portVideo),
      queryParameters: {
        'videoID': bvid,
        'cid': cid.toString(),
      },
      options: options,
    );

    if (res.statusCode == 200) {
      final data = res.data as Map<String, dynamic>;
      final ytbId = data['ytbID'] as String?;
      if (ytbId != null) {
        return Success(ytbId);
      }
    }
    return getErrMsg(res);
  }

  static Future<LoadingState<String>> postPortVideo({
    required String bvid,
    required int cid,
    required String ytbId,
    required int videoDuration,
  }) async {
    final String? userId = GStorage.localCache.get(LocalCacheKey.blockUserID);
    final res = await Request().post(
      _api(SponsorBlockApi.portVideo),
      data: {
        'bvID': bvid,
        'cid': cid.toString(),
        'ytbID': ytbId,
        'userID': userId ?? '',
        'biliDuration': videoDuration,
      },
      options: options,
    );

    if (res.statusCode == 200) {
      final data = res.data as Map<String, dynamic>;
      final uuid = data['UUID'] as String?;
      if (uuid != null) {
        return Success(uuid);
      }
    }
    return getErrMsg(res);
  }
}
