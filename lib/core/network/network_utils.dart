import 'dart:io';

/// Returns the local IP that is on the same subnet as [targetIp].
/// Falls back to the first available non-loopback IP if no match found.
Future<String> getBestLocalIpFor(String targetIp) async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );

  // Extract target subnet prefix (first 3 octets)
  final targetParts = targetIp.split('.');
  if (targetParts.length != 4) return '0.0.0.0';
  final targetSubnet = '${targetParts[0]}.${targetParts[1]}.${targetParts[2]}';

  String? fallback;

  for (final interface in interfaces) {
    for (final addr in interface.addresses) {
      final ip = addr.address;
      if (ip.startsWith('127.') || ip.startsWith('169.254.')) continue;
      fallback ??= ip; // keep first valid IP as fallback

      final parts = ip.split('.');
      if (parts.length == 4) {
        final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
        if (subnet == targetSubnet) {
          return ip; // exact subnet match — use this one
        }
      }
    }
  }

  return fallback ?? '0.0.0.0';
}
