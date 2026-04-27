// Wbi签名 用于生成 REST API 请求中的 w_rid 和 wts 字段
// https://github.com/SocialSisterYi/bilibili-API-collect/blob/master/docs/misc/sign/wbi.md
// 移植自PiliPlus，兼容Dart 2.19
import 'dart:async';
import 'dart:convert';

import 'package:PiliPalaX/http/api.dart';
import 'package:PiliPalaX/http/init.dart';
import 'package:PiliPalaX/utils/storage.dart';
import 'package:PiliPalaX/utils/utils.dart';
import 'package:crypto/crypto.dart';

/// WBI签名工具类
/// 用于B站Web API请求的签名生成
class WbiSign {
  static Box get _localCache => GStorage.localCache;
  static final RegExp _chrFilter = RegExp(r"[!\'\(\)\*]");

  /// mixin_key混淆表
  static const List<int> _mixinKeyEncTab = <int>[
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
    27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
  ];

  static Future<String>? _future;

  /// 对 imgKey 和 subKey 进行字符顺序打乱编码
  static String getMixinKey(String orig) {
    final codeUnits = orig.codeUnits;
    // 从映射表中取出对应位置的字符拼接成mixin_key
    return String.fromCharCodes(_mixinKeyEncTab.map((i) => codeUnits[i]));
  }

  /// 为请求参数进行 wbi 签名
  /// [params] 请求参数
  /// [mixinKey] mixin_key
  static void encWbi(Map<String, dynamic> params, String mixinKey) {
    params['wts'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // 按照 key 重排参数
    final List<String> keys = params.keys.toList()..sort();
    // URL编码 + 过滤特殊字符 + 拼接
    final queryStr = keys
        .map(
          (i) =>
              '${Uri.encodeComponent(i)}=${Uri.encodeComponent(params[i].toString().replaceAll(_chrFilter, ''))}',
        )
        .join('&');
    // 计算 w_rid (md5)
    params['w_rid'] = md5.convert(utf8.encode(queryStr + mixinKey)).toString();
  }

  /// 从API获取WBI密钥
  static Future<String> _getWbiKeys() async {
    try {
      final resp = await Request().get(Api.userInfo);
      final wbiUrls = resp.data['data']['wbi_img'];

      final imgKey = Utils.getFileName(wbiUrls['img_url'].toString(), fileExt: false);
      final subKey = Utils.getFileName(wbiUrls['sub_url'].toString(), fileExt: false);
      final mixinKey = getMixinKey(imgKey + subKey);

      _localCache.put(LocalCacheKey.wbiMixinKey, mixinKey);

      return mixinKey;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to get WBI keys: $e');
      }
      return '';
    }
  }

  /// 获取mixin_key（带缓存）
  static FutureOr<String> getWbiKeys() {
    final nowDate = DateTime.now();
    // 检查缓存是否有效（同一天）
    final int cachedTime = _localCache.get(
      LocalCacheKey.wbiTimeStamp,
      defaultValue: 0,
    ) as int;
    if (DateTime.fromMillisecondsSinceEpoch(cachedTime).day == nowDate.day) {
      final String? mixinKey = _localCache.get(LocalCacheKey.wbiMixinKey) as String?;
      if (mixinKey != null && mixinKey.isNotEmpty) {
        return mixinKey;
      }
      return _future ??= _getWbiKeys();
    } else {
      // 缓存过期，重新获取
      return _future = _localCache
          .put(LocalCacheKey.wbiTimeStamp, nowDate.millisecondsSinceEpoch)
          .then((_) => _getWbiKeys());
    }
  }

  /// 为参数添加WBI签名
  /// [params] 原始请求参数
  /// 返回带wts和w_rid的完整参数
  static Future<Map<String, dynamic>> makeSign(
    Map<String, dynamic> params,
  ) async {
    final String mixinKey = await getWbiKeys();
    if (mixinKey.isNotEmpty) {
      encWbi(params, mixinKey);
    }
    return params;
  }

  /// 清除WBI缓存（用于签名失效时）
  static void clearCache() {
    _localCache.delete(LocalCacheKey.wbiMixinKey);
    _localCache.delete(LocalCacheKey.wbiTimeStamp);
    _future = null;
  }
}
