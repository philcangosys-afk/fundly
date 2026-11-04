import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Text, Align;
// نص فلاتر الأصلي: «source» في سطر حقوق الخريطة لا يقبل غيره.
import 'package:flutter/widgets.dart' as fw show Text;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/app_language.dart';
import '../../l10n/tr_widgets.dart';
import 'app_design.dart';

/// الموقع المختار من الخريطة داخل التطبيق: الإحداثيات والعنوان والمدينة
/// والمنطقة، ورابط خرائط جوجل للمكان نفسه (يُفتح بالدبوس ذاته).
class PickedLocation {
  const PickedLocation({
    required this.lat,
    required this.lng,
    this.address = '',
    this.city = '',
    this.area = '',
  });

  final double lat;
  final double lng;
  final String address;
  final String city;
  final String area;

  String get link =>
      'https://www.google.com/maps/search/?api=1&query='
      '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
}

/// يفتح الخريطة: اكتب منطقة وابحث عنها، اضغط على المكان لتثبيت الدبوس،
/// ثم «اختيار هذا الموقع». [query] يُبحث عنه فور الفتح، و[lat]/[lng]
/// موقع سابق يُعرض مثبّتًا.
Future<PickedLocation?> showLocationPicker(
  BuildContext context, {
  String query = '',
  double? lat,
  double? lng,
}) {
  return Navigator.of(context).push<PickedLocation>(
    MaterialPageRoute(
      builder: (_) => LocationPickerScreen(
        initialQuery: query,
        initialLat: lat,
        initialLng: lng,
      ),
    ),
  );
}

class _Place {
  const _Place({
    required this.point,
    required this.title,
    required this.subtitle,
    required this.city,
    required this.area,
  });

  final LatLng point;
  final String title;
  final String subtitle;
  final String city;
  final String area;
}

/// البحث والعنوان من OpenStreetMap (Nominatim) — بلا مفتاح، ويعمل على
/// أندرويد والآيفون بالطريقة نفسها.
class _PlaceService {
  static const _host = 'nominatim.openstreetmap.org';

  static Future<dynamic> _get(String path, Map<String, String> params) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(Uri.https(_host, path, params));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'FundlyApp/1.0 (com.fundlyapp.app)',
      );
      request.headers.set(
        HttpHeaders.acceptLanguageHeader,
        '${AppTr.code},ar,en',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        throw HttpException('status ${response.statusCode}');
      }
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }

  static String _first(Map address, List<String> keys) {
    for (final key in keys) {
      final value = '${address[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static _Place? _parse(dynamic row) {
    if (row is! Map) return null;
    final lat = double.tryParse('${row['lat'] ?? ''}');
    final lng = double.tryParse('${row['lon'] ?? ''}');
    if (lat == null || lng == null) return null;
    final address = row['address'] is Map ? row['address'] as Map : const {};
    final city = _first(address, const [
      'city',
      'town',
      'village',
      'municipality',
      'county',
      'state',
    ]);
    final area = _first(address, const [
      'suburb',
      'neighbourhood',
      'quarter',
      'city_district',
      'district',
      'hamlet',
    ]);
    final road = _first(address, const ['road', 'pedestrian', 'street']);
    final name = '${row['name'] ?? ''}'.trim();
    final country = _first(address, const ['country']);
    final parts = <String>[];
    for (final part in [name, road, area, city, country]) {
      if (part.isNotEmpty && !parts.contains(part)) parts.add(part);
    }
    final display = '${row['display_name'] ?? ''}'.trim();
    return _Place(
      point: LatLng(lat, lng),
      title: parts.isNotEmpty ? parts.first : display,
      subtitle: parts.length > 1 ? parts.skip(1).join(' - ') : display,
      city: city,
      area: area,
    );
  }

  static Future<List<_Place>> search(String query) async {
    final data = await _get('/search', {
      'q': query,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '8',
    });
    if (data is! List) return const [];
    return [for (final row in data) ?_parse(row)];
  }

  static Future<_Place?> reverse(LatLng point) async {
    final data = await _get('/reverse', {
      'lat': point.latitude.toStringAsFixed(6),
      'lon': point.longitude.toStringAsFixed(6),
      'format': 'jsonv2',
      'addressdetails': '1',
      'zoom': '18',
    });
    return _parse(data);
  }
}

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    this.initialQuery = '',
    this.initialLat,
    this.initialLng,
  });

  final String initialQuery;
  final double? initialLat;
  final double? initialLng;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  // بلا موقع سابق: عرض عام للعالم دون دولة بعينها، ويُقرَّب إلى موقع
  // الجهاز إن كان الإذن ممنوحًا مسبقًا.
  static const _fallback = LatLng(20, 20);

  final _map = MapController();
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  bool _mapReady = false;

  LatLng? _pin;
  _Place? _pinPlace;
  bool _resolving = false;
  int _resolveToken = 0;

  List<_Place> _results = const [];
  bool _searching = false;
  String _searchError = '';
  bool _locating = false;

  LatLng get _start {
    final lat = widget.initialLat;
    final lng = widget.initialLng;
    return lat != null && lng != null ? LatLng(lat, lng) : _fallback;
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = widget.initialQuery.trim();
    if (widget.initialLat != null && widget.initialLng != null) {
      // موقع سابق: مثبّت من البداية، وعنوانه يُجلب بعد أول رسم.
      _pin = _start;
      _resolving = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _setPin(_start, move: false),
      );
    } else if (_searchCtrl.text.isNotEmpty) {
      // المكتوب في الحقل يُبحث عنه فور فتح الخريطة.
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _map.dispose();
    super.dispose();
  }

  void _moveTo(LatLng point, double zoom) {
    if (!_mapReady) return;
    _map.move(point, zoom);
  }

  /// يثبّت الدبوس ويجلب عنوان المكان.
  Future<void> _setPin(LatLng point, {bool move = true, _Place? place}) async {
    final token = ++_resolveToken;
    setState(() {
      _pin = point;
      _pinPlace = place;
      _resolving = place == null;
      _results = const [];
    });
    if (move) _moveTo(point, 16);
    if (place != null) return;
    _Place? found;
    try {
      found = await _PlaceService.reverse(point);
    } catch (_) {
      found = null;
    }
    if (!mounted || token != _resolveToken) return;
    setState(() {
      _pinPlace = found;
      _resolving = false;
    });
  }

  Future<void> _search() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;
    _searchFocus.unfocus();
    setState(() {
      _searching = true;
      _searchError = '';
    });
    try {
      final results = await _PlaceService.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searchError = results.isEmpty ? 'لا توجد نتائج — جرّب اسمًا آخر' : '';
      });
      // أول نتيجة تظهر على الخريطة، ويختار المستخدم من القائمة أو يضغط على
      // المكان بالضبط.
      if (results.isNotEmpty) _moveTo(results.first.point, 14);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _searchError = 'تعذّر البحث — تأكد من الاتصال بالإنترنت',
      );
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// بلا موقع سابق ولا بحث: يُقرَّب إلى آخر موقع معروف للجهاز دون طلب إذن
  /// ودون تثبيت دبوس. إن لم يكن الإذن ممنوحًا تبقى الخريطة على العرض العام.
  Future<void> _centerOnDeviceQuietly() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return;
      }
      final position = await Geolocator.getLastKnownPosition();
      if (position == null || !mounted || !_mapReady || _pin != null) return;
      _map.move(LatLng(position.latitude, position.longitude), 12);
    } catch (_) {
      // يبقى العرض العام.
    }
  }

  Future<void> _myLocation() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('فعّل خدمة الموقع في الجوال أولًا');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _toast('لم يُسمح للتطبيق بمعرفة الموقع');
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      await _setPin(LatLng(position.latitude, position.longitude));
    } catch (_) {
      _toast('تعذّر تحديد موقعك الحالي');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _choose() {
    final pin = _pin;
    if (pin == null) return;
    final place = _pinPlace;
    final address = place == null
        ? ''
        : [place.title, place.subtitle]
              .where((part) => part.trim().isNotEmpty)
              .join(' - ');
    Navigator.of(context).pop(
      PickedLocation(
        lat: pin.latitude,
        lng: pin.longitude,
        address: address,
        city: place?.city ?? '',
        area: place?.area ?? '',
      ),
    );
  }

  Widget _searchBox() {
    return Material(
      color: AppTheme.page,
      elevation: 3,
      borderRadius: BorderRadius.circular(AppTheme.rField),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        textAlign: AppTr.alignEnd,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        decoration: InputDecoration(
          hintText: AppTr.tr('اكتب اسم المنطقة أو المكان'),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          suffixIcon: _searching
              ? const Padding(
                  padding: EdgeInsets.all(13),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  tooltip: AppTr.tr('بحث'),
                  onPressed: _search,
                  icon: const Icon(
                    Icons.search_rounded,
                    color: AppTheme.brand,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _resultsList() {
    if (_results.isEmpty && _searchError.isEmpty) {
      return const SizedBox.shrink();
    }
    return Material(
      color: AppTheme.page,
      elevation: 3,
      borderRadius: BorderRadius.circular(AppTheme.rInner),
      clipBehavior: Clip.antiAlias,
      child: _searchError.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                _searchError,
                textAlign: AppTr.alignEnd,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.danger,
                ),
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final place = _results[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.place_outlined,
                      color: AppTheme.brand,
                    ),
                    title: Text(
                      place.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: place.subtitle.isEmpty
                        ? null
                        : Text(
                            place.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                    onTap: () => _setPin(place.point, place: place),
                  );
                },
              ),
            ),
    );
  }

  Widget _bottomPanel() {
    final pin = _pin;
    final place = _pinPlace;
    return Material(
      color: AppTheme.page,
      elevation: 8,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppTheme.rCard),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pin == null)
                const Text(
                  'ابحث عن المنطقة، ثم اضغط على المكان في الخريطة لتثبيت الدبوس.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.muted,
                  ),
                )
              else ...[
                Row(
                  textDirection: AppTr.uiDir,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      color: AppTheme.danger,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _resolving
                                ? 'جارٍ جلب بيانات المكان...'
                                : (place?.title.isNotEmpty ?? false)
                                ? place!.title
                                : 'موقع محدد على الخريطة',
                            textAlign: AppTr.alignEnd,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.title,
                            ),
                          ),
                          if (!_resolving &&
                              (place?.subtitle.isNotEmpty ?? false)) ...[
                            const SizedBox(height: 3),
                            Text(
                              place!.subtitle,
                              maxLines: 3,
                              textAlign: AppTr.alignEnd,
                              style: const TextStyle(
                                fontSize: 11.5,
                                height: 1.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF46534F),
                              ),
                            ),
                          ],
                          const SizedBox(height: 3),
                          Text(
                            '${pin.latitude.toStringAsFixed(6)}, '
                            '${pin.longitude.toStringAsFixed(6)}',
                            textAlign: AppTr.alignEnd,
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brand,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _resolving ? null : _choose,
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: const Text(
                    'اختيار هذا الموقع',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pin = _pin;
    return Directionality(
      textDirection: AppTr.uiDir,
      child: Scaffold(
        backgroundColor: AppTheme.page,
        appBar: AppBar(
          title: const Text('تحديد الموقع على الخريطة'),
          backgroundColor: AppTheme.page,
          surfaceTintColor: Colors.transparent,
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: _start,
                      initialZoom: widget.initialLat != null ? 16 : 2,
                      onMapReady: () {
                        _mapReady = true;
                        if (widget.initialLat == null &&
                            _searchCtrl.text.trim().isEmpty) {
                          _centerOnDeviceQuietly();
                        }
                      },
                      onTap: (_, point) {
                        _searchFocus.unfocus();
                        _setPin(point, move: false);
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.fundlyapp.app',
                      ),
                      if (pin != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: pin,
                              width: 46,
                              height: 46,
                              alignment: Alignment.topCenter,
                              child: const Icon(
                                Icons.location_on_rounded,
                                size: 46,
                                color: AppTheme.danger,
                              ),
                            ),
                          ],
                        ),
                      const SimpleAttributionWidget(
                        source: fw.Text('OpenStreetMap'),
                      ),
                    ],
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _searchBox(),
                        const SizedBox(height: 8),
                        _resultsList(),
                      ],
                    ),
                  ),
                  PositionedDirectional(
                    bottom: 16,
                    start: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'location-picker-me',
                      backgroundColor: AppTheme.page,
                      foregroundColor: AppTheme.brand,
                      tooltip: AppTr.tr('موقعي الحالي'),
                      onPressed: _locating ? null : _myLocation,
                      child: _locating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location_rounded),
                    ),
                  ),
                ],
              ),
            ),
            _bottomPanel(),
          ],
        ),
      ),
    );
  }
}
