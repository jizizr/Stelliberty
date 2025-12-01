import 'package:flutter/material.dart';
import 'package:stelliberty/clash/data/subscription_model.dart';
import 'package:stelliberty/ui/common/modern_dialog_subs/option_selector.dart';
import 'package:stelliberty/i18n/i18n.dart';

// 代理模式选择器
// 用于订阅对话框和覆写对话框的代理模式选择
class ProxyModeSelector extends StatelessWidget {
  final SubscriptionProxyMode selectedValue;
  final ValueChanged<SubscriptionProxyMode> onChanged;

  const ProxyModeSelector({
    super.key,
    required this.selectedValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final trans = context.translate;

    return OptionSelectorWidget<SubscriptionProxyMode>(
      title: trans.subscriptionDialog.proxyModeTitle,
      titleIcon: Icons.public,
      isHorizontal: true,
      options: [
        OptionItem(
          value: SubscriptionProxyMode.direct,
          title: SubscriptionProxyMode.direct.displayName,
          subtitle: trans.subscriptionDialog.proxyModeDirect,
        ),
        OptionItem(
          value: SubscriptionProxyMode.system,
          title: SubscriptionProxyMode.system.displayName,
          subtitle: trans.subscriptionDialog.proxyModeSystem,
        ),
        OptionItem(
          value: SubscriptionProxyMode.core,
          title: SubscriptionProxyMode.core.displayName,
          subtitle: trans.subscriptionDialog.proxyModeCore,
        ),
      ],
      selectedValue: selectedValue,
      onChanged: onChanged,
    );
  }
}
