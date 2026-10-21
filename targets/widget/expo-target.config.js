/** Home Screen widget (iOS): new likes, unread messages and your next event.
 *  Built by @bacons/apple-targets during `expo prebuild`. */
/** @type {import('@bacons/apple-targets/app.plugin').Config} */
module.exports = {
  type: 'widget',
  name: 'QadamWidget',
  icon: '../../assets/icon.png',
  colors: {
    $widgetBackground: '#1F5FA0',
    $accent: '#E2A63B',
  },
  deploymentTarget: '16.0',
  entitlements: {
    'com.apple.security.application-groups': ['group.kz.qadam.app'],
  },
};
