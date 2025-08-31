import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// API Anahtarınızı buraya girin
const String GOOGLE_MAPS_API_KEY = "YOUR_GOOGLE_MAPS_API_KEY";

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'EDS ve Rota Uygulaması',
      home: SpeedTrackerPage(),
    );
  }
}

class SpeedTrackerPage extends StatefulWidget {
  const SpeedTrackerPage({super.key});

  @override
  State<SpeedTrackerPage> createState() => _SpeedTrackerPageState();
}

class _SpeedTrackerPageState extends State<SpeedTrackerPage> with WidgetsBindingObserver {
  // MethodChannel
  static const platform = MethodChannel('com.example.eds_app/pip');
  
  // Harita ve konum değişkenleri
  GoogleMapController? _mapController;
  final LatLng _center = const LatLng(41.0082, 28.9784); // İstanbul merkez
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  // Hesaplama değişkenleri
  bool _isTracking = false;
  double _totalDistance = 0.0;
  double _currentSpeed = 0.0;
  double _averageSpeed = 0.0;
  Position? _lastPosition;
  DateTime? _startTime;
  StreamSubscription<Position>? _positionStreamSubscription;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _speedWarningActive = false;
  double _speedLimit = 50.0; // Varsayılan hız sınırı

  // Arama ve rota değişkenleri
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  String _routeDuration = '';
  String _routeDistance = '';
  List<dynamic> _alternativeRoutes = [];
  int _selectedRouteIndex = 0;
  LatLng? _destinationLocation;
  bool _isInPipMode = false;

  // Radar noktaları ve ikon
  List<LatLng> _radarLocations = [
    const LatLng(41.015137, 28.979530), // Örnek radar noktası 1 (Sultanahmet)
    const LatLng(41.0428, 29.0068), // Örnek radar noktası 2 (Beşiktaş)
  ];
  BitmapDescriptor? _radarIcon;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLocationPermission();
    _loadRadarPointsAndIcons();

    platform.setMethodCallHandler((call) async {
      if (call.method == "onPiPModeChanged") {
        setState(() {
          _isInPipMode = call.arguments as bool;
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _enterPiPMode();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStreamSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // Özel ikonları ve kayıtlı radar noktalarını yükleme
  Future<void> _loadRadarPointsAndIcons() async {
    final Uint8List radarData = await _getBytesFromAsset('assets/radar_icon.png', 100);
    _radarIcon = BitmapDescriptor.fromBytes(radarData);

    // Kayıtlı radar noktalarını yükle
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedRadars = prefs.getString('radar_points');
    if (savedRadars != null) {
      final List<dynamic> radarList = json.decode(savedRadars);
      _radarLocations = radarList.map((item) => LatLng(item[0], item[1])).toList();
    }

    // Haritaya radar noktalarını ekle
    _addRadarMarkers();
  }

  void _addRadarMarkers() {
    _markers.removeWhere((m) => m.markerId.value.startsWith('radar'));
    for (var location in _radarLocations) {
      _markers.add(
        Marker(
          markerId: MarkerId('radar_${location.latitude}_${location.longitude}'),
          position: location,
          icon: _radarIcon!,
          infoWindow: const InfoWindow(title: 'EDS/Radar Noktası'),
        ),
      );
    }
  }

  Future<Uint8List> _getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  }

  // Konum izni kontrolü
  Future<void> _checkLocationPermission() async {
    var status = await Permission.location.status;
    if (status.isDenied) {
      await Permission.location.request();
    }
  }

  // Hız sınırı uyarısı kontrolü
  void _checkSpeedLimit(double speed) {
    if (speed > _speedLimit && !_speedWarningActive) {
      setState(() {
        _speedWarningActive = true;
      });
      _playWarningSound();
    } else if (speed <= _speedLimit && _speedWarningActive) {
      setState(() {
        _speedWarningActive = false;
      });
      _stopWarningSound();
    }
  }

  // Uyarı sesi çal
  void _playWarningSound() async {
    await _audioPlayer.play(AssetSource('speed_warning.mp3'));
    _audioPlayer.setReleaseMode(ReleaseMode.loop);
  }

  // Uyarı sesini durdur
  void _stopWarningSound() {
    _audioPlayer.stop();
  }

  // Takip başlatma
  void _startTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konum servisi kapalı. Lütfen açın.')),
      );
      return;
    }

    setState(() {
      _isTracking = true;
      _totalDistance = 0.0;
      _currentSpeed = 0.0;
      _averageSpeed = 0.0;
      _startTime = DateTime.now();
      _lastPosition = null;
    });

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1,
      ),
    ).listen((Position position) {
      if (_lastPosition != null) {
        double distance = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        _totalDistance += distance;
        final elapsedTime = DateTime.now().difference(_startTime!).inSeconds;
        if (elapsedTime > 0) {
          _averageSpeed = (_totalDistance / elapsedTime) * 3.6;
        }
      }

      setState(() {
        _currentSpeed = position.speed * 3.6;
        _markers.removeWhere((m) => m.markerId.value == 'current_location');
        _markers.add(
          Marker(
            markerId: const MarkerId("current_location"),
            position: LatLng(position.latitude, position.longitude),
            infoWindow: const InfoWindow(title: 'Şu anki konumunuz'),
          ),
        );
      });

      _checkSpeedLimit(_currentSpeed);

      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: 17.0,
          ),
        ),
      );
      _lastPosition = position;
    });
  }

  // Takibi durdurma
  void _stopTracking() {
    _positionStreamSubscription?.cancel();
    _stopWarningSound();
    setState(() {
      _isTracking = false;
      _speedWarningActive = false;
    });
  }

  // Yer arama
  Future<void> _searchPlaces(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    final String url =
        'https://maps.googleapis.com/maps/api/place/textsearch/json?query=$query&key=$GOOGLE_MAPS_API_KEY';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['results'] != null) {
        setState(() {
          _searchResults = data['results'];
        });
      }
    }
  }

  // Rota oluşturma
  Future<void> _createRoute(LatLng destination) async {
    _polylines.clear();
    _markers.removeWhere((m) => m.markerId.value != 'current_location' && !m.markerId.value.startsWith('radar'));
    setState(() {
      _routeDuration = '';
      _routeDistance = '';
      _alternativeRoutes = [];
      _destinationLocation = destination;
    });

    Position currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);

    final String origin = '${currentPosition.latitude},${currentPosition.longitude}';
    final String destinationStr = '${destination.latitude},${destination.longitude}';

    final String url =
        'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destinationStr&alternatives=true&key=$GOOGLE_MAPS_API_KEY';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['routes'] != null && data['routes'].isNotEmpty) {
        setState(() {
          _alternativeRoutes = data['routes'];
          _selectedRouteIndex = 0; // Varsayılan olarak ilk rotayı seç
        });
        _drawAlternativeRoutes();
      }
    }
  }

  // Alternatif rotaları çizme
  void _drawAlternativeRoutes() {
    _polylines.clear();
    for (int i = 0; i < _alternativeRoutes.length; i++) {
      final route = _alternativeRoutes[i];
      final points = route['overview_polyline']['points'];
      final List<LatLng> polylinePoints = _decodePoly(points);
      final isSelected = i == _selectedRouteIndex;

      _polylines.add(
        Polyline(
          polylineId: PolylineId('route_$i'),
          points: polylinePoints,
          color: isSelected ? Colors.blue : Colors.grey,
          width: isSelected ? 5 : 3,
          onTap: () => _selectRoute(i),
        ),
      );
    }
  }

  // Seçilen rotayı haritada gösterme
  void _selectRoute(int routeIndex) {
    if (routeIndex >= 0 && routeIndex < _alternativeRoutes.length) {
      setState(() {
        _selectedRouteIndex = routeIndex;
        _drawAlternativeRoutes();
        final route = _alternativeRoutes[routeIndex];
        _routeDuration = route['legs'][0]['duration']['text'];
        _routeDistance = route['legs'][0]['distance']['text'];
        
        _markers.removeWhere((m) => m.markerId.value == 'destination_marker');
        _markers.add(
          Marker(
            markerId: const MarkerId('destination_marker'),
            position: _destinationLocation!,
            infoWindow: InfoWindow(title: _searchController.text),
          ),
        );
      });
      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(
          _boundsFromPolyline(_decodePoly(_alternativeRoutes[routeIndex]['overview_polyline']['points'])),
          100.0,
        ),
      );
    }
  }

  // Kullanıcının bulunduğu konuma radar ekleme
  Future<void> _addRadarPoint() async {
    try {
      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final newRadar = LatLng(position.latitude, position.longitude);

      setState(() {
        _radarLocations.add(newRadar);
        _addRadarMarkers(); // Yeni radarı haritaya ekle
      });
      _saveRadarPoints();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konum alınamadı: $e')),
      );
    }
  }

  // Radar noktalarını yerel depolamaya kaydetme
  Future<void> _saveRadarPoints() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<List<double>> radarList = _radarLocations.map((loc) => [loc.latitude, loc.longitude]).toList();
    await prefs.setString('radar_points', json.encode(radarList));
  }

  // Resim içinde resim (mini ekran) moduna geçme
  Future<void> _enterPiPMode() async {
    try {
      if (Theme.of(context).platform == TargetPlatform.android) {
        await platform.invokeMethod('enterPiP');
      }
    } on PlatformException catch (e) {
      print("Failed to enter Picture-in-Picture mode: '${e.message}'.");
    }
  }

  // Poligonal çizgi kodlamasını çözme
  List<LatLng> _decodePoly(String poly) {
    var list = poly.codeUnits;
    var lList = <int>[];
    int index = 0;
    int len = poly.length;
    int c = 0;

    while (index < len) {
      var b = 0;
      var shift = 0;
      int result = 0;
      do {
        b = list[index++] - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      c = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lList.add(c);
    }

    var lat = 0.0;
    var lng = 0.0;
    var result = <LatLng>[];

    for (int i = 0; i < lList.length; i += 2) {
      lat += lList[i] * 1e-5;
      lng += lList[i + 1] * 1e-5;
      result.add(LatLng(lat, lng));
    }
    return result;
  }

  // Rota için harita sınırlarını hesaplama
  LatLngBounds _boundsFromPolyline(List<LatLng> polylinePoints) {
    double minLat = polylinePoints[0].latitude;
    double minLng = polylinePoints[0].longitude;
    double maxLat = polylinePoints[0].latitude;
    double maxLng = polylinePoints[0].longitude;

    for (var point in polylinePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  // Şu anki konuma dönme
  Future<void> _goToCurrentLocation() async {
    final Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(position.latitude, position.longitude),
          zoom: 17.0,
        ),
      ),
    );
  }

  // Hız sınırı ayar penceresi
  void _showSpeedLimitDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hız Sınırı Ayarla (km/s)'),
          content: TextField(
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final newLimit = double.tryParse(value);
              if (newLimit != null) {
                setState(() {
                  _speedLimit = newLimit;
                });
              }
            },
            controller: TextEditingController(text: _speedLimit.toStringAsFixed(0)),
            decoration: const InputDecoration(
              hintText: 'Yeni hız sınırı',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tamam'),
            ),
          ],
        );
      },
    );
  }

  // UI Oluşturma
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EDS ve Rota Uygulaması'),
        backgroundColor: Colors.blueGrey,
        actions: [
          IconButton(
            icon: const Icon(Icons.speed),
            onPressed: _showSpeedLimitDialog,
            tooltip: 'Hız Sınırını Ayarla',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Google Haritası
          if (!_isInPipMode)
            GoogleMap(
              initialCameraPosition: CameraPosition(target: _center, zoom: 12.0),
              onMapCreated: (controller) {
                _mapController = controller;
              },
              markers: _markers,
              polylines: _polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              mapType: MapType.normal,
              zoomControlsEnabled: false,
              trafficEnabled: true,
            )
          else
            // Mini ekran görünümü
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Hız: ${_currentSpeed.toStringAsFixed(0)} km/s',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: _speedWarningActive ? Colors.red : Colors.green,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sınır: ${_speedLimit.toStringAsFixed(0)} km/s',
                    style: const TextStyle(fontSize: 24, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ortalama: ${_averageSpeed.toStringAsFixed(0)} km/s',
                    style: const TextStyle(fontSize: 20, color: Colors.grey),
                  ),
                ],
              ),
            ),

          // Arama Çubuğu
          if (!_isInPipMode)
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => _searchPlaces(value),
                    decoration: InputDecoration(
                      hintText: 'Hedef ara...',
                      filled: true,
                      fillColor: Colors.white,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchResults = []);
                        },
                      ),
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  // Arama Sonuçları Listesi
                  if (_searchResults.isNotEmpty)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 5,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final place = _searchResults[index];
                          return ListTile(
                            title: Text(place['name']),
                            subtitle: Text(place['formatted_address'] ?? ''),
                            onTap: () {
                              _createRoute(LatLng(
                                place['geometry']['location']['lat'],
                                place['geometry']['location']['lng'],
                              ));
                              setState(() {
                                _searchResults = [];
                                _searchController.text = place['name'];
                              });
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          
          // Rota Bilgileri
          if (!_isInPipMode && _routeDuration.isNotEmpty)
            Positioned(
              top: 80,
              right: 10,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Süre: $_routeDuration',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Mesafe: $_routeDistance',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Hız Paneli ve Durum Bilgileri
          if (!_isInPipMode)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hız: ${_currentSpeed.toStringAsFixed(0)} km/s',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: _speedWarningActive ? Colors.red : Colors.green,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Ortalama: ${_averageSpeed.toStringAsFixed(0)} km/s',
                            style: const TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                          Text(
                            'Sınır: ${_speedLimit.toStringAsFixed(0)} km/s',
                            style: const TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ],
                      ),
                      if (_isTracking)
                        IconButton(
                          onPressed: _stopTracking,
                          icon: const Icon(Icons.stop_circle, size: 48, color: Colors.red),
                        )
                      else
                        IconButton(
                          onPressed: _startTracking,
                          icon: const Icon(Icons.play_circle_fill, size: 48, color: Colors.green),
                        ),
                    ],
                  ),
                ),
              ),
            ),

          // Şu anki konuma dönme butonu
          if (!_isInPipMode)
            Positioned(
              bottom: 110, // Hız panelinin üstünde
              right: 20,
              child: FloatingActionButton(
                onPressed: _goToCurrentLocation,
                mini: true,
                backgroundColor: Colors.white,
                child: const Icon(Icons.my_location, color: Colors.blueGrey),
              ),
            ),
          
          // Radar ekleme butonu
          if (!_isInPipMode)
            Positioned(
              bottom: 110,
              left: 20,
              child: FloatingActionButton(
                onPressed: _addRadarPoint,
                mini: true,
                backgroundColor: Colors.redAccent,
                child: const Icon(Icons.camera, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}