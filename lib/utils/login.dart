
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/http/user.dart';
import 'package:pilipala/pages/dynamics/index.dart';
import 'package:pilipala/pages/home/index.dart';
import 'package:pilipala/pages/media/index.dart';
import 'package:pilipala/pages/mine/index.dart';
import 'package:pilipala/utils/cookie.dart';
import 'package:pilipala/utils/storage.dart';

class LoginUtils {
  static Future refreshLoginStatus(bool status) async {
    try {
      // 底栏页面可自定义，未启用的页面不会注册 controller
      if (Get.isRegistered<MineController>()) {
        // 更改我的页面登录状态
        MineController mineCtr = Get.find<MineController>();
        await mineCtr.resetUserInfo();
        mineCtr.userLogin.value = status;
      }

      // 更改主页登录状态
      if (Get.isRegistered<HomeController>()) {
        Get.find<HomeController>().updateLoginStatus(status);
      }

      if (Get.isRegistered<DynamicsController>()) {
        Get.find<DynamicsController>().userLogin.value = status;
      }

      if (Get.isRegistered<MediaController>()) {
        Get.find<MediaController>().userLogin.value = status;
      }
    } catch (err) {
      SmartDialog.showToast('refreshLoginStatus error: ${err.toString()}');
    }
  }

  static confirmLogin(url, controller) async {
    var content = '';
    if (url != null) {
      content = '${content + url}; \n';
    }
    try {
      await SetCookie.onSet();
      final result = await UserHttp.userInfo();
      if (result['status'] && result['data'].isLogin) {
        SmartDialog.showToast('登录成功');
        try {
          Box userInfoCache = GStrorage.userInfo;
          if (!userInfoCache.isOpen) {
            userInfoCache = await Hive.openBox('userInfo');
          }
          await userInfoCache.put('userInfoCache', result['data']);

          final HomeController homeCtr = Get.find<HomeController>();
          homeCtr.updateLoginStatus(true);
          homeCtr.userFace.value = result['data'].face;
          if (Get.isRegistered<MediaController>()) {
            Get.find<MediaController>().mid = result['data'].mid;
          }
          await LoginUtils.refreshLoginStatus(true);
        } catch (err) {
          SmartDialog.show(builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('登录遇到问题'),
              content: Text(err.toString()),
              actions: [
                TextButton(
                  onPressed: controller != null
                      ? () => controller.reload()
                      : SmartDialog.dismiss,
                  child: const Text('确认'),
                )
              ],
            );
          });
        }
        Get.back();
      } else {
        // 获取用户信息失败
        SmartDialog.showToast(result['msg']);
        Clipboard.setData(ClipboardData(text: result['msg']));
      }
    } catch (e) {
      SmartDialog.showNotify(msg: e.toString(), notifyType: NotifyType.warning);
      content = content + e.toString();
      Clipboard.setData(ClipboardData(text: content));
    }
  }
}
