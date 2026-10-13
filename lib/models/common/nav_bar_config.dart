import 'package:flutter/material.dart';

import '../../pages/dynamics/index.dart';
import '../../pages/home/index.dart';
import '../../pages/media/index.dart';
import '../../pages/tavern/index.dart';

List defaultNavigationBars = [
  {
    'id': 0,
    'icon': const Icon(
      Icons.home_outlined,
      size: 21,
    ),
    'selectIcon': const Icon(
      Icons.home,
      size: 21,
    ),
    'label': "首页",
    'count': 0,
    'page': const HomePage(),
  },
  {
    'id': 2,
    'icon': const Icon(
      Icons.motion_photos_on_outlined,
      size: 21,
    ),
    'selectIcon': const Icon(
      Icons.motion_photos_on,
      size: 21,
    ),
    'label': "动态",
    'count': 0,
    'page': const DynamicsPage(),
  },
  {
    'id': 3,
    'icon': const Icon(
      Icons.video_collection_outlined,
      size: 20,
    ),
    'selectIcon': const Icon(
      Icons.video_collection,
      size: 21,
    ),
    'label': "媒体库",
    'count': 0,
    'page': const MediaPage(),
  },
  {
    'id': 4,
    'icon': const Icon(
      Icons.local_bar_outlined,
      size: 21,
    ),
    'selectIcon': const Icon(
      Icons.local_bar,
      size: 21,
    ),
    'label': "酒馆",
    'count': 0,
    'page': const TavernPage(),
  }
];
