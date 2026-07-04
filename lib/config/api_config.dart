/// TLS/SNI uses [nginxHost]; TCP can still target [serverIp] via DNS or direct IP apps.
class ApiConfig {
  static const serverIp = '187.77.125.241';
  /// Nginx `server_name` + TLS cert CN — update if Hostinger hostname changes.
  static const nginxHost = 'srv1804550.hstgr.cloud';
  /// Hostname URL so Android/iOS TLS handshake matches the VPS certificate.
  static const defaultBaseUrl = 'https://$nginxHost/api/v1';
}
