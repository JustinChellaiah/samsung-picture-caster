import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_cast_dlna/media_cast_dlna.dart';

// This is the IP address of the computer running the Python server.
// Make sure your Android device is on the same Wi-Fi network.
const String serverUrl = 'http://192.168.86.32:5000';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Picture Caster',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
      ),
      home: const PictureGrid(),
    );
  }
}

class PictureGrid extends StatefulWidget {
  const PictureGrid({super.key});

  @override
  State<PictureGrid> createState() => _PictureGridState();
}

class _PictureGridState extends State<PictureGrid> {
  late Future<List<String>> _picturesFuture;
  final MediaCastDlnaApi _mediaCastDlna = MediaCastDlnaApi();
  final ValueNotifier<List<DlnaDevice>> _devicesNotifier = ValueNotifier([]);
  final ValueNotifier<DlnaDevice?> _connectedDevice = ValueNotifier(null);
  Timer? _discoveryTimer;

  @override
  void initState() {
    super.initState();
    _picturesFuture = fetchPictures();
  }

  @override
  void dispose() {
    _discoveryTimer?.cancel();
    _mediaCastDlna.stopDiscovery();
    _devicesNotifier.dispose();
    _connectedDevice.dispose();
    super.dispose();
  }

  Future<List<String>> fetchPictures() async {
    try {
      final response = await http.get(Uri.parse('$serverUrl/pictures'));

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        return data.map((item) => item.toString()).toList();
      } else {
        throw Exception('Failed to load pictures (Status code: ${response.statusCode})');
      }
    } catch (e) {
      throw Exception('Failed to connect to the server: $e');
    }
  }

  Future<void> _startDeviceDiscovery() async {
    print('Initializing UPnP service...');
    await _mediaCastDlna.initializeUpnpService();

    print('Starting new device discovery...');
    final discoveryOptions = DiscoveryOptions(
      timeout: DiscoveryTimeout(seconds: 10),
      searchTarget: SearchTarget(target: 'urn:schemas-upnp-org:device:MediaRenderer:1'),
    );
    await _mediaCastDlna.startDiscovery(discoveryOptions);
    print('Discovery started. Setting up periodic check...');

    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      print('Device discovery timer fired...');
      try {
        final devices = await _mediaCastDlna.getDiscoveredDevices();
        print('Raw discovered devices list: $devices');
        print('Friendly names: ${devices.map((d) => d.friendlyName).toList()}');
        _devicesNotifier.value = devices;
      } catch (e) {
        print('Error during device discovery: $e');
      }
    });
  }

  void _disconnectFromDevice() {
    print('Disconnecting from device...');
    _mediaCastDlna.stop(_connectedDevice.value!.udn);
    _connectedDevice.value = null;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Disconnected from device')),
    );
  }

  Future<void> _showCastDevicesDialog() async {
    print('Opening cast devices dialog...');
    await _startDeviceDiscovery();

    showDialog(
      context: context,
      builder: (context) {
        return _DeviceListDialog(
          devicesNotifier: _devicesNotifier,
          connectedDeviceNotifier: _connectedDevice,
          onDeviceSelected: (device) {
            _connectedDevice.value = device;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Connected to ${device.friendlyName}')),
            );
          },
        );
      },
    );
  }

  void _castPicture(String pictureFileName) async {
    if (_connectedDevice.value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a device first.')),
      );
      return;
    }

    final imageUrl = '$serverUrl/pictures/$pictureFileName';
    final metadata = ImageMetadata(
        title: pictureFileName, upnpClass: 'object.item.imageItem');

    try {
      await Future.delayed(const Duration(seconds: 1));
      try {
        await _mediaCastDlna.setMediaUri(_connectedDevice.value!.udn, Url(value: imageUrl), metadata);
        await _mediaCastDlna.play(_connectedDevice.value!.udn);
      } on PlatformException catch (e) {
        debugPrint('Error casting picture: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error casting: ${e.message}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Casting $pictureFileName...'))
      );
    } catch (e) {
      print('Error casting picture: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error casting $pictureFileName: $e'))
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select a Picture to Cast'),
        actions: [
          ValueListenableBuilder<DlnaDevice?>(
            valueListenable: _connectedDevice,
            builder: (context, device, child) {
              return IconButton(
                icon: Icon(
                  device != null ? Icons.cast_connected : Icons.cast,
                  color: device != null ? Colors.blueAccent : Colors.white,
                ),
                tooltip: device != null ? 'Disconnect' : 'Cast to device',
                onPressed: () {
                  if (device != null) {
                    _disconnectFromDevice();
                  } else {
                    _showCastDevicesDialog();
                  }
                },
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          ValueListenableBuilder<List<DlnaDevice>>(
            valueListenable: _devicesNotifier,
            builder: (context, devices, child) {
              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text('Discovered Devices: ${devices.length}', style: const TextStyle(fontSize: 16)),
              );
            },
          ),
          Expanded(
            child: FutureBuilder<List<String>>(
              future: _picturesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'Error: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red, fontSize: 16),
                      ),
                    ),
                  );
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No pictures found on the server.'));
                } else {
                  final pictures = snapshot.data!;
                  return GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 4.0,
                      mainAxisSpacing: 4.0,
                    ),
                    itemCount: pictures.length,
                    itemBuilder: (context, index) {
                      final imageUrl = '$serverUrl/pictures/${pictures[index]}';
                      print('Attempting to load image from URL: $imageUrl');
                      return GestureDetector(
                        onTap: () => _castPicture(pictures[index]),
                        child: GridTile(
                          child: Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(child: CircularProgressIndicator());
                            },
                            errorBuilder: (context, error, stackTrace) {
                              print('Error loading image: $error');
                              print(stackTrace);
                              return const Icon(Icons.broken_image, size: 50, color: Colors.redAccent);
                            },
                          ),
                        ),
                      );
                    },
                  );
                }
              },
            ),
          ), // End Expanded
        ],
      ), // End Column
    );
  }
}

class _DeviceListDialog extends StatelessWidget {
  final ValueNotifier<List<DlnaDevice>> devicesNotifier;
  final ValueNotifier<DlnaDevice?> connectedDeviceNotifier;
  final Function(DlnaDevice) onDeviceSelected;

  const _DeviceListDialog({
    required this.devicesNotifier,
    required this.connectedDeviceNotifier,
    required this.onDeviceSelected,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select a Device'),
      content: SizedBox(
        width: double.maxFinite,
        child: ValueListenableBuilder<List<DlnaDevice>>(
          valueListenable: devicesNotifier,
          builder: (context, devices, child) {
            if (devices.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Searching for devices...'),
                  ],
                ),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];
                return ListTile(
                  title: Text(device.friendlyName ?? 'Unknown Device'),
                  subtitle: Text(device.udn.value),
                  onTap: () {
                    onDeviceSelected(device);
                    Navigator.of(context).pop();
                  },
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
