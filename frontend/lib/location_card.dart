import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';

class LocationCard extends StatefulWidget {
  const LocationCard({
    super.key,
    required this.api,
    required this.childId,
    required this.canShare,
  });
  final Api api;
  final String childId;
  final bool canShare;
  @override
  State<LocationCard> createState() => _LocationCardState();
}

class _LocationCardState extends State<LocationCard> {
  Map<String, dynamic>? location;
  bool busy = false;
  String? error;
  String get path => '/children/${widget.childId}/location';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() => run(() async {
    final result = await widget.api.call('GET', path);
    location = result == null ? null : Map<String, dynamic>.from(result);
  });
  Future<void> share() async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chia sẻ với phụ huynh?'),
        content: const Text(
          'Gửi vị trí hiện tại của điện thoại này và độ chính xác lên máy chủ. Chỉ phụ huynh liên kết xem được. Không theo dõi nền. Bạn có thể ngừng và xóa vị trí bất cứ lúc nào.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đồng ý chia sẻ'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;
    await run(() async {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Hãy bật dịch vụ vị trí trên điện thoại.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Quyền vị trí bị khóa. Hãy mở Cài đặt ứng dụng để cấp quyền.',
        );
      }
      if (permission == LocationPermission.denied) {
        throw Exception('Bạn chưa cho phép truy cập vị trí.');
      }
      final point = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );
      location = Map<String, dynamic>.from(
        await widget.api.call('PUT', path, {
          'latitude': point.latitude,
          'longitude': point.longitude,
          'accuracy': point.accuracy,
        }),
      );
    });
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFFFEEE7),
                child: Icon(
                  Icons.location_on_outlined,
                  color: Color(0xFFE86B4A),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Vị trí an tâm',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            location == null
                ? 'Chưa chia sẻ vị trí.'
                : 'Lần chia sẻ gần nhất: ${DateTime.parse(location!['updated_at']).toLocal().toString().split('.').first}',
          ),
          if (location != null) ...[
            Text('Độ chính xác khoảng ${location!['accuracy']} m'),
            const Text(
              'Đây là vị trí tại thời điểm gửi, không phải theo dõi trực tiếp.',
            ),
            TextButton.icon(
              onPressed: () async {
                final l = location!;
                final uri = Uri.https('www.google.com', '/maps/search/', {
                  'api': '1',
                  'query': '${l['latitude']},${l['longitude']}',
                });
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.map_outlined),
              label: const Text('Xem trên bản đồ'),
            ),
          ],
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.deepOrange)),
          if (busy)
            const LinearProgressIndicator()
          else
            Wrap(
              spacing: 8,
              children: [
                if (widget.canShare)
                  FilledButton.icon(
                    onPressed: share,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Chia sẻ vị trí hiện tại'),
                  ),
                OutlinedButton(onPressed: load, child: const Text('Làm mới')),
                if (widget.canShare && location != null)
                  TextButton(
                    onPressed: () => run(() async {
                      await widget.api.call('DELETE', path);
                      location = null;
                    }),
                    child: const Text('Ngừng & xóa vị trí'),
                  ),
              ],
            ),
        ],
      ),
    ),
  );
}
