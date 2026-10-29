import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'fingerprint.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'api.dart';
import 'location_card.dart';

void main() => runApp(const MamanApp());
final api = Api();
const ink = Color(0xFF241B36), green = Color(0xFFE86B4A);
const canvas = Color(0xFFF7F4FA), lavender = Color(0xFFECE5F5);

class MamanApp extends StatelessWidget {
  const MamanApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mầm An',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: green),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        iconColor: green,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: lavender,
      ),
      scaffoldBackgroundColor: canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 7),
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
    ),
    home: const Login(),
  );
}

void notify(BuildContext context, Object text) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text.toString().replaceFirst('Exception: ', ''))),
    );
Widget field(
  TextEditingController controller,
  String label, {
  bool secret = false,
  TextInputType? keyboard,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 14),
  child: TextField(
    controller: controller,
    obscureText: secret,
    keyboardType: keyboard,
    decoration: InputDecoration(labelText: label),
  ),
);

class Login extends StatefulWidget {
  const Login({super.key});
  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final username = TextEditingController(),
      password = TextEditingController(),
      email = TextEditingController(),
      name = TextEditingController(),
      code = TextEditingController();
  bool register = false, busy = false;
  String? challenge;
  @override
  void dispose() {
    for (final c in [username, password, email, name, code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> work(Future<void> Function() fn) async {
    setState(() => busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) notify(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> enter(Map<String, dynamic> result) async {
    api.token = result['token'];
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => Home(user: Map<String, dynamic>.from(result['user'])),
      ),
    );
  }

  Future<void> submit() => work(() async {
    if (challenge != null) {
      await enter(
        Map<String, dynamic>.from(
          await api.call('POST', '/auth/otp', {
            'challengeId': challenge,
            'code': code.text.trim(),
          }),
        ),
      );
      return;
    }
    final r = await api
        .call('POST', register ? '/auth/register' : '/auth/login', {
          'username': username.text.trim(),
          'password': password.text,
          if (register) 'email': email.text.trim(),
          if (register) 'name': name.text.trim(),
        });
    setState(() => challenge = r['challengeId']);
    if (mounted) notify(context, r['message']);
  });
  Future<void> biometric() => work(() async {
    final auth = FingerprintAuth();
    if (!await auth.available()) {
      throw Exception(
        'Thiết bị cần sinh trắc học đã đăng ký và được Android hỗ trợ.',
      );
    }
    if (!mounted) return;
    if (!await auth.authenticate(context)) return;
    final token = await Api.storage.read(key: 'biometric_token');
    if (token == null) {
      throw Exception(
        'Hãy đăng nhập bằng OTP và bật sinh trắc học trong tài khoản trước.',
      );
    }
    api.token = token;
    try {
      final u = await api.call('GET', '/me');
      await enter({'token': token, 'user': u});
    } catch (e) {
      await api.logout();
      rethrow;
    }
  });
  Future<void> google() => work(() async {
    if (!api.configured) throw Exception('Cần cấu hình địa chỉ backend trước.');
    final verifier = base64UrlEncode(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    final digest = sha256.convert(utf8.encode(verifier)).toString();
    final result = await FlutterWebAuth2.authenticate(
      url: '${Api.base}/auth/google/start?verifierHash=$digest',
      callbackUrlScheme: 'childguard',
    );
    final c = Uri.parse(result).queryParameters['code'];
    if (c == null) throw Exception('Google chưa trả mã xác thực');
    final response = Map<String, dynamic>.from(
      await api.call('POST', '/auth/google/exchange', {
        'code': c,
        'verifier': verifier,
      }),
    );
    if (response['requiresOtp'] == true) {
      if (!mounted) return;
      setState(() {
        challenge = response['challengeId'];
        code.clear();
      });
      notify(context, response['message']);
      return;
    }
    await enter(response);
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF4ECFA), Color(0xFFFFF3EA), canvas],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(26, 28, 26, 40),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF49375F), ink],
                      ),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(42),
                        bottomRight: Radius.circular(42),
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -14,
                          bottom: -34,
                          child: Icon(
                            Icons.spa_rounded,
                            size: 150,
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.eco_rounded,
                                  color: Color(0xFFFFB38F),
                                  size: 28,
                                ),
                                const SizedBox(width: 9),
                                const Text(
                                  'MẦM AN',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'AN TOÀN SỐ',
                                    style: TextStyle(
                                      color: Color(0xFFFFD1BD),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 42),
                            Text(
                              challenge != null
                                  ? 'Một bước nữa\nlà bạn vào nhà.'
                                  : register
                                  ? 'Bắt đầu hành trình\ncùng Mầm An.'
                                  : 'Nuôi dưỡng\nthói quen tốt.',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                height: 1.12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Không gian để gia đình đồng hành an toàn trong thế giới số.',
                              style: TextStyle(
                                color: Color(0xFFD8D1E0),
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -22),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 18),
                      padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x18241B36),
                            blurRadius: 28,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: lavender,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  challenge != null
                                      ? Icons.mark_email_read_outlined
                                      : register
                                      ? Icons.person_add_alt_1_rounded
                                      : Icons.lock_open_rounded,
                                  color: ink,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      challenge != null
                                          ? 'Xác thực email'
                                          : register
                                          ? 'Tạo tài khoản'
                                          : 'Đăng nhập',
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: ink,
                                      ),
                                    ),
                                    Text(
                                      challenge != null
                                          ? 'Nhập mã để tiếp tục'
                                          : 'Chào mừng bạn trở lại',
                                      style: const TextStyle(
                                        color: Color(0xFF71697C),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          if (!api.configured)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 16),
                              child: Text(
                                'Chưa cấu hình máy chủ. Xem hướng dẫn chạy backend để kết nối.',
                                style: TextStyle(color: Colors.deepOrange),
                              ),
                            ),
                          if (challenge != null) ...[
                            const Text(
                              'Mã có hiệu lực 5 phút, tối đa 5 lần thử.',
                            ),
                            const SizedBox(height: 12),
                            field(
                              code,
                              'Mã OTP',
                              keyboard: TextInputType.number,
                            ),
                          ] else ...[
                            if (register) ...[
                              field(name, 'Họ tên'),
                              field(
                                email,
                                'Email',
                                keyboard: TextInputType.emailAddress,
                              ),
                            ],
                            field(
                              username,
                              register
                                  ? 'Tên đăng nhập (3–32 ký tự)'
                                  : 'Tên đăng nhập hoặc email',
                            ),
                            field(
                              password,
                              'Mật khẩu (ít nhất 10 ký tự)',
                              secret: true,
                            ),
                          ],
                          FilledButton(
                            onPressed: busy ? null : submit,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Text(
                                busy
                                    ? 'Đang xử lý…'
                                    : challenge != null
                                    ? 'Xác thực & tiếp tục'
                                    : register
                                    ? 'Đăng ký'
                                    : 'Đăng nhập với OTP',
                              ),
                            ),
                          ),
                          if (challenge == null) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Row(
                                children: [
                                  Expanded(child: Divider()),
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Text(
                                      'HOẶC',
                                      style: TextStyle(
                                        color: Color(0xFF8A8294),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Expanded(child: Divider()),
                                ],
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: busy ? null : google,
                              icon: const Icon(Icons.account_circle_outlined),
                              label: const Text('Tiếp tục với Google'),
                            ),
                            TextButton.icon(
                              onPressed: busy ? null : biometric,
                              icon: const Icon(Icons.fingerprint),
                              label: const Text('Mở bằng vân tay'),
                            ),
                          ],
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                    challenge = null;
                                    register = !register;
                                    code.clear();
                                  }),
                            child: Text(
                              challenge != null
                                  ? 'Quay lại / gửi mã mới'
                                  : register
                                  ? 'Đã có tài khoản? Đăng nhập'
                                  : 'Chưa có tài khoản? Đăng ký',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 0, 24, 22),
                    child: Text(
                      'Một không gian số tích cực bắt đầu từ sự đồng hành.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF71697C), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class Home extends StatefulWidget {
  final Map<String, dynamic> user;
  const Home({super.key, required this.user});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  List<dynamic> children = [], users = [];
  Map<String, dynamic> stats = {};
  bool loading = true;
  String? error;
  int page = 0;
  String get role => widget.user['role'];
  bool get isParent => role == 'parent';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (role == 'admin') {
        users = await api.call('GET', '/admin/users');
        stats = Map<String, dynamic>.from(
          await api.call('GET', '/staff/dashboard'),
        );
      } else if (role == 'staff') {
        stats = Map<String, dynamic>.from(
          await api.call('GET', '/staff/dashboard'),
        );
      } else {
        children = await api.call('GET', '/children');
      }
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> manageUser(Map<String, dynamic> user) async {
    const labels = {
      'parent': 'Phụ huynh',
      'child': 'Trẻ em',
      'staff': 'Nhân viên',
      'admin': 'Quản trị viên',
    };
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(user['name']),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user['email']),
            Text('Vai trò: ${labels[user['role']] ?? user['role']}'),
            Text(
              user['verified'] == true
                  ? 'Email đã xác minh'
                  : 'Email chưa xác minh',
            ),
            const SizedBox(height: 16),
            if (user['role'] == 'admin')
              const Text(
                'Tài khoản quản trị được bảo vệ, không thể đổi quyền tại đây.',
              )
            else
              ...['parent', 'child', 'staff'].map(
                (role) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(labels[role]!),
                  trailing: user['role'] == role
                      ? const Icon(Icons.check)
                      : const Icon(Icons.chevron_right),
                  onTap: user['role'] == role
                      ? null
                      : () => Navigator.pop(ctx, role),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận đổi quyền'),
        content: Text('Đổi ${user['name']} thành ${labels[selected]}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await execute(() async {
      await api.call('PATCH', '/admin/users/${user['id']}/role', {
        'role': selected,
      });
      if (mounted) {
        notify(context, 'Đã cập nhật quyền thành ${labels[selected]}');
      }
    });
  }

  Future<void> execute(Future<void> Function() fn) async {
    try {
      await fn();
      await load();
    } catch (e) {
      if (mounted) notify(context, e);
    }
  }

  Future<void> editChild([Map<String, dynamic>? c]) async {
    final result = await editDialog(
      context,
      c == null ? 'Thêm hồ sơ trẻ' : 'Sửa hồ sơ trẻ',
      {
        'name': ('Tên trẻ', c?['name'] ?? ''),
        'age': ('Tuổi', '${c?['age'] ?? 8}'),
        'daily_limit': ('Giới hạn phút/ngày', '${c?['daily_limit'] ?? 120}'),
      },
    );
    if (result == null) return;
    await execute(() async {
      await api.call(
        c == null ? 'POST' : 'PUT',
        c == null ? '/children' : '/children/${c['id']}',
        {
          'name': result['name'],
          'age': int.tryParse(result['age'] ?? '') ?? 0,
          'daily_limit': int.tryParse(result['daily_limit'] ?? '') ?? 0,
        },
      );
    });
  }

  Future<void> logout() async {
    await api.logout();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const Login()));
  }

  Future<void> enableFinger() async {
    try {
      final auth = FingerprintAuth();
      if (!await auth.available()) {
        throw Exception('Hãy đăng ký vân tay trong cài đặt Android.');
      }
      if (!mounted) return;
      if (await auth.authenticate(context)) {
        await Api.storage.write(key: 'biometric_token', value: api.token);
        if (mounted) {
          notify(
            context,
            'Đã bật vân tay. Phiên hết hạn sau 12 giờ; sau đó cần OTP.',
          );
        }
      }
    } catch (e) {
      if (mounted) notify(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: Colors.white,
      title: const Row(
        children: [
          Icon(Icons.eco_rounded, color: green),
          SizedBox(width: 8),
          Text('Mầm An', style: TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Làm mới',
          onPressed: load,
          icon: const Icon(Icons.refresh),
        ),
        const SizedBox(width: 8),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: page,
      onDestinationSelected: (i) => setState(() => page = i),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.space_dashboard_outlined),
          label: 'Tổng quan',
        ),
        NavigationDestination(
          icon: Icon(Icons.manage_accounts_outlined),
          label: 'Tài khoản',
        ),
      ],
    ),
    floatingActionButton: page == 0 && isParent
        ? FloatingActionButton.extended(
            onPressed: () => editChild(),
            icon: const Icon(Icons.add),
            label: const Text('Thêm trẻ'),
          )
        : null,
    body: page == 1
        ? ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE7DC),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: Text(
                          widget.user['name'].toString().isEmpty
                              ? '?'
                              : widget.user['name']
                                    .toString()
                                    .substring(0, 1)
                                    .toUpperCase(),
                          style: const TextStyle(
                            color: ink,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.user['name'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ink,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.user['email'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF71697C),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'TÀI KHOẢN',
                style: TextStyle(
                  color: Color(0xFF71697C),
                  fontSize: 11,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ListTile(
                  leading: const Icon(Icons.badge_outlined, color: green),
                  title: const Text('Vai trò'),
                  subtitle: Text(
                    {
                          'parent': 'Phụ huynh',
                          'child': 'Trẻ em',
                          'staff': 'Nhân viên',
                          'admin': 'Quản trị viên',
                        }[role] ??
                        role,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'BẢO MẬT',
                style: TextStyle(
                  color: Color(0xFF71697C),
                  fontSize: 11,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.fingerprint, color: green),
                      title: const Text('Bật vân tay'),
                      subtitle: const Text(
                        'Dữ liệu sinh trắc học chỉ được xử lý trên thiết bị.',
                      ),
                      onTap: enableFinger,
                    ),
                    const Divider(height: 1, indent: 56, endIndent: 18),
                    ListTile(
                      leading: const Icon(Icons.lock_reset, color: ink),
                      title: const Text('Tắt vân tay'),
                      onTap: () async {
                        await Api.storage.delete(key: 'biometric_token');
                        if (context.mounted) {
                          notify(context, 'Đã tắt vân tay');
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: logout,
                icon: const Icon(Icons.logout),
                label: const Text('Đăng xuất & xóa phiên đã lưu'),
              ),
            ],
          )
        : loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error!),
                  FilledButton(onPressed: load, child: const Text('Thử lại')),
                ],
              ),
            ),
          )
        : RefreshIndicator(
            onRefresh: load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 100),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'KHÔNG GIAN GIA ĐÌNH',
                            style: TextStyle(
                              color: green,
                              fontSize: 11,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Xin chào, ${widget.user['name']}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ink,
                              fontSize: 25,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            role == 'admin'
                                ? 'Trang quản trị'
                                : role == 'staff'
                                ? 'Dashboard nhân viên'
                                : role == 'child'
                                ? 'Không gian của con'
                                : 'Cùng con xây dựng thói quen số tốt',
                            style: const TextStyle(
                              color: Color(0xFF71697C),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE7DC),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Center(
                        child: Text(
                          widget.user['name'].toString().isEmpty
                              ? '?'
                              : widget.user['name']
                                    .toString()
                                    .substring(0, 1)
                                    .toUpperCase(),
                          style: const TextStyle(
                            color: ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                if (role == 'parent' || role == 'child') ...[
                  Row(
                    children: [
                      Expanded(
                        child: _OverviewMetric(
                          icon: Icons.people_alt_outlined,
                          label: role == 'child'
                              ? 'Hồ sơ của con'
                              : 'Hồ sơ trẻ',
                          value: '${children.length}',
                          color: lavender,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _OverviewMetric(
                          icon: Icons.schedule_rounded,
                          label: 'Kế hoạch mỗi ngày',
                          value:
                              '${children.fold<int>(0, (sum, child) => sum + (int.tryParse('${child['daily_limit']}') ?? 0))} phút',
                          color: const Color(0xFFFFE7DC),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                ],
                if (role == 'admin' || role == 'staff') ...[
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: stats.entries
                        .map(
                          (e) => Chip(
                            backgroundColor: Colors.white,
                            side: BorderSide.none,
                            avatar: const Icon(
                              Icons.insights_outlined,
                              size: 18,
                              color: green,
                            ),
                            label: Text('${e.key}: ${e.value}'),
                          ),
                        )
                        .toList(),
                  ),
                  if (role == 'staff')
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Nhân viên xem số liệu tổng hợp để hỗ trợ vận hành. Không truy cập hồ sơ riêng tư của gia đình.',
                        ),
                      ),
                    ),
                  ...users.map(
                    (u) => Card(
                      child: ListTile(
                        title: Text(u['name']),
                        subtitle: Text('${u['email']} • ${u['role']}'),
                        onTap: () => manageUser(Map<String, dynamic>.from(u)),
                        trailing: IconButton(
                          tooltip: 'Quản lý tài khoản',
                          onPressed: () =>
                              manageUser(Map<String, dynamic>.from(u)),
                          icon: const Icon(Icons.manage_accounts_outlined),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          role == 'child'
                              ? 'Hồ sơ được liên kết'
                              : 'Gia đình của bạn',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (children.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          isParent
                              ? 'Thêm hồ sơ đầu tiên để bắt đầu đồng hành cùng con.'
                              : 'Nhờ phụ huynh liên kết email tài khoản con trong hồ sơ trẻ.',
                        ),
                      ),
                    ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 520 ? 3 : 2;
                      final itemWidth =
                          (constraints.maxWidth - (columns - 1) * 12) / columns;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: children.indexed.map((entry) {
                          final index = entry.$1;
                          final child = Map<String, dynamic>.from(entry.$2);
                          final palette = [
                            const Color(0xFFECE5F5),
                            const Color(0xFFFFE7DC),
                            const Color(0xFFE0F0EA),
                            const Color(0xFFFFF0C9),
                          ];
                          final accent = [
                            ink,
                            green,
                            const Color(0xFF31735D),
                            const Color(0xFF916A21),
                          ];
                          final name = child['name'].toString();
                          return SizedBox(
                            width: itemWidth,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(22),
                                onTap: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ChildPage(
                                        child: child,
                                        isParent: isParent,
                                      ),
                                    ),
                                  );
                                  await load();
                                },
                                onLongPress: isParent
                                    ? () => editChild(child)
                                    : null,
                                child: Ink(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: palette[index % palette.length],
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.child_care_rounded,
                                            color:
                                                accent[index % accent.length],
                                            size: 23,
                                          ),
                                          const Spacer(),
                                          Icon(
                                            Icons.arrow_outward_rounded,
                                            color:
                                                accent[index % accent.length],
                                            size: 18,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 20),
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: ink,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        '${child['age']} tuổi',
                                        style: const TextStyle(
                                          color: Color(0xFF71697C),
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.75,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.schedule_rounded,
                                              size: 14,
                                              color:
                                                  accent[index % accent.length],
                                            ),
                                            const SizedBox(width: 5),
                                            Flexible(
                                              child: Text(
                                                '${child['daily_limit']} phút/ngày',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: ink,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
  );
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 112),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Icon(icon, color: ink, size: 20),
        const SizedBox(height: 8),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: ink,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF71697C), fontSize: 11),
        ),
      ],
    ),
  );
}

Future<Map<String, String>?> editDialog(
  BuildContext context,
  String title,
  Map<String, (String, String)> fields,
) async {
  final controllers = fields.map(
    (key, value) => MapEntry(key, TextEditingController(text: value.$2)),
  );
  final result = await showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: fields.entries
              .map(
                (e) => field(
                  controllers[e.key]!,
                  e.value.$1,
                  keyboard: ['age', 'daily_limit', 'reward'].contains(e.key)
                      ? TextInputType.number
                      : null,
                ),
              )
              .toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            ctx,
            controllers.map((k, v) => MapEntry(k, v.text.trim())),
          ),
          child: const Text('Lưu'),
        ),
      ],
    ),
  );
  // Controllers stay alive until the dialog route has completed its exit animation.
  Future.delayed(const Duration(seconds: 1), () {
    for (final c in controllers.values) {
      c.dispose();
    }
  });
  return result;
}

class ChildPage extends StatefulWidget {
  final Map<String, dynamic> child;
  final bool isParent;
  const ChildPage({super.key, required this.child, required this.isParent});
  @override
  State<ChildPage> createState() => _ChildPageState();
}

class _ChildPageState extends State<ChildPage> {
  List<dynamic> devices = [], agreements = [], checkins = [];
  bool busy = true;
  String? error;
  String get id => widget.child['id'];
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    NfcManager.instance.stopSession();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await Future.wait([
        api.call('GET', '/children/$id/devices'),
        api.call('GET', '/children/$id/agreements'),
        api.call('GET', '/children/$id/checkins'),
      ]);
      devices = r[0];
      agreements = r[1];
      checkins = r[2];
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> act(Future<void> Function() f) async {
    try {
      await f();
      await load();
    } catch (e) {
      if (mounted) notify(context, e);
    }
  }

  Future<void> device([Map<String, dynamic>? d]) async {
    final b = await editDialog(
      context,
      d == null ? 'Thêm thiết bị' : 'Đổi tên thiết bị',
      {'name': ('Tên điện thoại', d?['name'] ?? '')},
    );
    if (b == null) return;
    await act(() async {
      await api.call(
        d == null ? 'POST' : 'PUT',
        d == null ? '/children/$id/devices' : '/devices/${d['id']}',
        b,
      );
    });
  }

  Future<void> agreement() async {
    final b = await editDialog(context, 'Thỏa thuận thời gian số', {
      'title': ('Mục tiêu (ví dụ đọc sách 30 phút)', ''),
      'reward': ('Phút thưởng', '15'),
    });
    if (b == null) return;
    await act(() async {
      await api.call('POST', '/children/$id/agreements', {
        'title': b['title'],
        'reward': int.tryParse(b['reward'] ?? '') ?? 0,
      });
    });
  }

  Future<void> nfc(bool enroll) async {
    try {
      if (!await NfcManager.instance.isAvailable()) {
        throw Exception('Thiết bị không hỗ trợ NFC hoặc NFC chưa bật.');
      }
      if (!mounted) return;
      bool scanned = false;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(enroll ? 'Gắn thẻ NFC' : 'Check-in NFC'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.nfc, size: 64, color: green),
              SizedBox(height: 16),
              Text('Đưa thẻ đến mặt sau điện thoại.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await NfcManager.instance.stopSession();
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Hủy'),
            ),
          ],
        ),
      );
      await NfcManager.instance.startSession(
        onDiscovered: (tag) async {
          if (scanned) return;
          scanned = true;
          try {
            List<int>? uid;
            for (final key in [
              'nfca',
              'nfcb',
              'nfcf',
              'nfcv',
              'mifareclassic',
              'mifareultralight',
              'isodep',
            ]) {
              final d = tag.data[key];
              if (d is Map && d['identifier'] is List) {
                uid = List<int>.from(d['identifier']);
                break;
              }
            }
            if (uid == null || uid.isEmpty) {
              throw Exception('Thẻ không có UID được hỗ trợ');
            }
            final tagHash = sha256.convert(uid).toString();
            await api.call(
              enroll ? 'PUT' : 'POST',
              '/children/$id/${enroll ? 'nfc' : 'checkins'}',
              {'tagHash': tagHash},
            );
            await NfcManager.instance.stopSession();
            if (mounted) {
              Navigator.pop(context);
              notify(context, enroll ? 'Đã gắn thẻ' : 'Check-in thành công');
              await load();
            }
          } catch (e) {
            await NfcManager.instance.stopSession();
            if (mounted) {
              Navigator.pop(context);
              notify(context, e);
            }
          }
        },
      );
    } on PlatformException catch (e) {
      if (mounted) notify(context, e.message ?? 'Lỗi NFC');
    } catch (e) {
      if (mounted) notify(context, e);
    }
  }

  Future<bool> confirm(String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Xác nhận xóa'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Xóa'),
            ),
          ],
        ),
      ) ??
      false;
  @override
  Widget build(BuildContext context) {
    final bonus = agreements
        .where((a) => a['status'] == 'approved')
        .fold<int>(0, (sum, a) => sum + (a['reward'] as int));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hồ sơ trẻ'),
        actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
      ),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: TextButton(
                onPressed: load,
                child: Text('$error\nThử lại'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECE5F5),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(19),
                        ),
                        child: const Icon(
                          Icons.child_care_rounded,
                          color: ink,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.child['name'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.child['age']} tuổi  ·  Hồ sơ gia đình',
                              style: const TextStyle(
                                color: Color(0xFF71697C),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'KẾ HOẠCH THỜI GIAN SỐ',
                              style: TextStyle(
                                color: Color(0xFF71697C),
                                letterSpacing: 1,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Icon(Icons.schedule_rounded, color: green, size: 20),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${widget.child['daily_limit']}',
                            style: const TextStyle(
                              color: ink,
                              fontSize: 42,
                              height: 1,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(left: 8, bottom: 5),
                            child: Text(
                              'phút mỗi ngày',
                              style: TextStyle(
                                color: Color(0xFF71697C),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE7DC),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$bonus phút thưởng đã duyệt',
                          style: const TextStyle(
                            color: ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Đây là kế hoạch đã lưu; ứng dụng chưa chặn thời gian dùng thiết bị.',
                        style: TextStyle(
                          color: Color(0xFF71697C),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.isParent) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final b = await editDialog(context, 'Sửa hồ sơ', {
                            'name': ('Tên', widget.child['name']),
                            'age': ('Tuổi', '${widget.child['age']}'),
                            'daily_limit': (
                              'Phút/ngày',
                              '${widget.child['daily_limit']}',
                            ),
                          });
                          if (b == null) return;
                          await act(() async {
                            final r = await api.call('PUT', '/children/$id', {
                              'name': b['name'],
                              'age': int.tryParse(b['age'] ?? '') ?? 0,
                              'daily_limit':
                                  int.tryParse(b['daily_limit'] ?? '') ?? 0,
                            });
                            widget.child.addAll(Map<String, dynamic>.from(r));
                          });
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Sửa hồ sơ'),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          final b = await editDialog(
                            context,
                            'Liên kết tài khoản trẻ',
                            {
                              'email': (
                                'Email tài khoản trẻ đã được admin cấp quyền',
                                '',
                              ),
                            },
                          );
                          if (b != null) {
                            await act(() async {
                              await api.call('POST', '/children/$id/link', b);
                              if (context.mounted) {
                                notify(context, 'Đã liên kết');
                              }
                            });
                          }
                        },
                        child: const Text('Liên kết trẻ'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Thiết bị của con',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (widget.isParent)
                      IconButton(
                        onPressed: () => device(),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                  ],
                ),
                if (devices.isEmpty)
                  const Text(
                    'Chưa có thiết bị. Thêm tên điện thoại để quản lý hồ sơ.',
                  ),
                ...devices.map(
                  (d) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.phone_android, color: green),
                      title: Text(d['name']),
                      subtitle: const Text('Android • hồ sơ thiết bị'),
                      onTap: widget.isParent
                          ? () => device(Map<String, dynamic>.from(d))
                          : null,
                      trailing: widget.isParent
                          ? IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                if (await confirm('Xóa thiết bị này?')) {
                                  await act(() async {
                                    await api.call(
                                      'DELETE',
                                      '/devices/${d['id']}',
                                    );
                                  });
                                }
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Thỏa thuận tích cực',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: agreement,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                const Text(
                  'Con đề xuất mục tiêu; phụ huynh quyết định phần thưởng.',
                ),
                ...agreements.map(
                  (a) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a['title'],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '+${a['reward']} phút • ${{'pending': 'Chờ duyệt', 'approved': 'Đã duyệt', 'rejected': 'Từ chối'}[a['status']]}',
                          ),
                          if (widget.isParent)
                            Wrap(
                              spacing: 8,
                              children: [
                                if (a['status'] == 'pending')
                                  ...['approved', 'rejected'].map(
                                    (s) => TextButton(
                                      onPressed: () => act(() async {
                                        await api.call(
                                          'PATCH',
                                          '/agreements/${a['id']}',
                                          {'status': s},
                                        );
                                      }),
                                      child: Text(
                                        s == 'approved' ? 'Duyệt' : 'Từ chối',
                                      ),
                                    ),
                                  ),
                                TextButton(
                                  onPressed: () async {
                                    if (await confirm('Xóa thỏa thuận này?')) {
                                      await act(() async {
                                        await api.call(
                                          'DELETE',
                                          '/agreements/${a['id']}',
                                        );
                                      });
                                    }
                                  },
                                  child: const Text('Xóa'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                LocationCard(api: api, childId: id, canShare: !widget.isParent),
                const SizedBox(height: 24),
                const Text(
                  'Điểm chạm an tâm',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Chạm thẻ NFC để ghi nhận check-in. UID thẻ không phải bằng chứng danh tính hay vị trí.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => nfc(false),
                      icon: const Icon(Icons.nfc),
                      label: const Text('Check-in NFC'),
                    ),
                    if (widget.isParent)
                      OutlinedButton(
                        onPressed: () => nfc(true),
                        child: const Text('Gắn thẻ'),
                      ),
                  ],
                ),
                ...checkins.map(
                  (c) => ListTile(
                    leading: const Icon(
                      Icons.check_circle_outline,
                      color: green,
                    ),
                    title: const Text('Check-in thành công'),
                    subtitle: Text(
                      DateTime.parse(
                        c['created_at'],
                      ).toLocal().toString().split('.').first,
                    ),
                  ),
                ),
                if (widget.isParent) ...[
                  const SizedBox(height: 32),
                  TextButton.icon(
                    onPressed: () async {
                      if (!await confirm(
                        'Xóa hồ sơ cùng thiết bị, thỏa thuận và lịch sử check-in?',
                      )) {
                        return;
                      }
                      try {
                        await api.call('DELETE', '/children/$id');
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) notify(context, e);
                      }
                    },
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    label: const Text(
                      'Xóa hồ sơ trẻ',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
                const SizedBox(height: 30),
              ],
            ),
    );
  }
}
