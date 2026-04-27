// ignore_for_file: constant_identifier_names

import 'dart:ui';

import 'package:PiliPalaX/models/common/sponsor_block/action_type.dart';

enum SegmentType {
  sponsor(
    '赞助/恰饭',
    '赞助',
    '付费推广、推荐和直接广告。不是自我推广或免费提及他们喜欢的商品/创作者/网站/产品。',
    Color(0xFF00d400),
    [
      ActionType.skip,
      ActionType.mute,
      ActionType.full,
    ],
  ),
  selfpromo(
    '无偿/自我推广',
    '推广',
    '类似于 "赞助广告" ，但无报酬或是自我推广。包括有关商品、捐赠的部分或合作者的信息。',
    Color(0xFFffff00),
    [
      ActionType.skip,
      ActionType.mute,
      ActionType.full,
    ],
  ),
  exclusive_access(
    '独家访问/抢先体验',
    '品牌合作',
    '创作者被品牌支付佣金或免费提供商品/服务，对商品/服务进行评价。视频不一定专门介绍该商品，但会积极提及。',
    Color(0xFF008a47),
    [
      ActionType.skip,
      ActionType.mute,
      ActionType.full,
    ],
  ),
  interaction(
    '关注/订阅提醒',
    '互动',
    '视频中间或结尾简短提醒点赞、订阅或关注创作者，或在评论/社交媒体互动。不包含新内容或背景信息。',
    Color(0xFFcc00ff),
    [
      ActionType.skip,
      ActionType.mute,
    ],
  ),
  intro(
    '片头/开头问候',
    '片头',
    '视频开始的动画/片段，内容结束后不重复。片头没有新内容，不应在片尾后重复。',
    Color(0xFF00ffff),
    [
      ActionType.skip,
      ActionType.mute,
    ],
  ),
  outro(
    '片尾/结束语',
    '片尾',
    '视频结束后的致谢、结尾片段，内容介绍后重复。不包含新内容，不解释背景。',
    Color(0xFF0202ed),
    [
      ActionType.skip,
      ActionType.mute,
    ],
  ),
  preview(
    '精彩片段',
    '预览',
    '展示同频道即将或之前视频的精彩片段，宣传频道/系列特色，或出现在回顾前/后的旧视频摘要。',
    Color(0xFF008fdf),
    [
      ActionType.skip,
      ActionType.mute,
    ],
  ),
  poi_highlight(
    '精彩时刻/重点内容',
    '重点',
    '主要与视频主题相关的重点部分。适合非连续观看，标记视频最精彩部分，方便跳转。',
    Color(0xFFff1684),
    [
      ActionType.poi,
    ],
  ),
  filler(
    '离题/废话',
    '离题',
    "适合想看视频重点的观众。包括：离题内容、重复内容、无信息的幽默、静音片段等。不是主观评价，而是视频创作者明确离题或重复自己时标记。",
    Color(0xFF7300ff),
    [
      ActionType.skip,
      ActionType.mute,
    ],
  ),
  music_offtopic(
    '音乐:非音乐部分',
    '非音乐',
    '仅用于音乐视频。音乐视频应只包含音乐，此分类标记非音乐内容。',
    Color(0xFFff9900),
    [
      ActionType.skip,
      ActionType.mute,
    ],
  ),
  padding(
    '暂停/无声片段',
    '暂停',
    '仅包含空白或背景音乐的音频，有助于过渡到新片段。',
    Color(0xFFFFFFFF),
    [
      ActionType.skip,
      ActionType.mute,
    ],
  ),
  preview_dynamic(
    '动态预览',
    '动态',
    '跳转到动态预览内容',
    Color(0xFF00ffff),
    [
      ActionType.poi,
    ],
  ),
  poi_dynamic(
    '动态重点',
    '重点',
    '跳转到动态重点内容',
    Color(0xFFff1684),
    [
      ActionType.poi,
    ],
  ),
  ;

  final String title;
  final String shortTitle;
  final String desc;
  final Color color;
  final List<ActionType> actionTypes;

  const SegmentType(
    this.title,
    this.shortTitle,
    this.desc,
    this.color,
    this.actionTypes,
  );

  factory SegmentType.fromName(String name) {
    return SegmentType.values.firstWhere(
      (e) => e.name == name,
      orElse: () => SegmentType.sponsor,
    );
  }
}
