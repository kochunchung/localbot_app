/// Configuration for LocalBot App.
class AppConfig {
  /// Default Server URL (User specified)
  static const String defaultServerUrl = 'https://linebot.tasko.uk';

  /// Default HMAC Secret Key (Matching Server's CHANNEL_SECRET)
  static const String defaultChannelSecret = 'localbot-webhook-secret-key';

  /// Storage keys
  static const String keyServerUrl = 'localbot_server_url';
  static const String keyChannelSecret = 'localbot_channel_secret';
  static const String keyUserId = 'localbot_user_id';
  static const String keyDisplayName = 'localbot_display_name';
}
