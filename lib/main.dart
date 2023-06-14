import 'package:flutter/material.dart';
import 'dart:async';
import 'package:beacons_plugin/beacons_plugin.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'dart:typed_data';
import 'package:permission_handler/permission_handler.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:convert/convert.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluetooth Lock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<List<String?>> data = [];
  List<List<String?>> filterData = [];
  double showFilter = -100;
  double adFilter = -60;
  late String beaconResult;
  final StreamController<String> beaconEventsController =
      StreamController<String>.broadcast();

  final FlutterBlePeripheral blePeripheral = FlutterBlePeripheral();
  AdvertiseData advertiseData = AdvertiseData(
    serviceUuid: '012345678-9abc-def0-1234-56789abcdef',
    // manufacturerId: 1234,
    // manufacturerData: Uint8List.fromList([1, 2, 3, 4, 5, 6]),
    // includeDeviceName: true
  );
  final AdvertiseSettings advertiseSettings = AdvertiseSettings(
      advertiseMode: AdvertiseMode.advertiseModeLowLatency,
      txPowerLevel: AdvertiseTxPower.advertiseTxPowerMedium,
      timeout: 10000);
  // final AdvertiseSetParameters advertiseSetParameters =
  //     AdvertiseSetParameters(txPowerLevel: txPowerMedium, interval: 1000);
  bool isAdvertise = false;
  bool canAdvertise = false;
  bool isScanning = false;
  LogFile logFile = LogFile('log.txt');

  void createEncryptedUUID() async {
    // sync();
    final logFileText = await logFile.read();
    // print(logFileText);
    String prevUUID = logFileText.split('/n')[0];
    String stringKey = logFileText.split('/n')[1];
    final ciphertextHex = generateUUID(prevUUID, stringKey);
    logFile.write('$ciphertextHex/n$stringKey');
    final servivceUUID = convertStringtoUUID(ciphertextHex);
    advertiseData = AdvertiseData(serviceUuid: servivceUUID);
  }

  void sync() {
    logFile.write(
        '0123456789abcdef0123456789abcdef/n00112233445566778899aabbccddeeff');
    advertiseData =
        AdvertiseData(serviceUuid: '012345678-9abc-def0-1234-56789abcdef');
    updateView();
  }

//Initate Beacon Function
  initiatebeacon() async {
    BeaconsPlugin.addRegion("myBeacon", "01022022-f88f-0000-00ae-9605fd9bb620")
        .then((result) {
      // print(result);
    });

    //Send 'true' to run in background [OPTIONAL]
    await BeaconsPlugin.runInBackground(true);
  }

  startBeacon() async {
    //IMPORTANT: Start monitoring once scanner is setup & ready (only for Android)
    if (Platform.isAndroid) {
      //Prominent disclosure
      await BeaconsPlugin.clearDisclosureDialogShowFlag(true);
      await BeaconsPlugin.setDisclosureDialogMessage(
          title: "Need Location Permission",
          message: "This app collects location data to work with beacons.");

      //Only in case, you want the dialog to be shown again. By Default, dialog will never be shown if permissions are granted.
      await BeaconsPlugin.clearDisclosureDialogShowFlag(true);

      await Permission.location.request();
      if (await Permission.location.isGranted) {
        //print("Permission Granted");
      }
      BeaconsPlugin.channel.setMethodCallHandler((call) async {
        //print(call.method);

        if (call.method == 'isPermissionDialogShown') {
          await BeaconsPlugin.startMonitoring();
        } else if (call.method == 'scannerReady') {
          await BeaconsPlugin.startMonitoring();
        } else {
          //print("not ready");
        }
      });
    } else if (Platform.isIOS) {
      await BeaconsPlugin.startMonitoring();
      isScanning = true;
    }
  }

  @override
  void initState() {
    super.initState();
    initiatebeacon();
    startBeacon();
  }

  ble() {
    BeaconsPlugin.listenToBeacons(beaconEventsController);
    beaconEventsController.stream.listen(
        (data) {
          isScanning = true;
          if (data.isNotEmpty) {
            beaconResult = data;
          }
          //print("Beacons DataReceived: " + data);
          updateData(data);
        },
        onDone: () {},
        onError: (error) {
          //print("Error: $error");
        });
  }

  void stopScan() {
    BeaconsPlugin.stopMonitoring();
    isScanning = false;
  }

  void updateData(String str) {
    var temp = str.split(",");
    var dev = [
      temp[0].split(": ")[1].substring(1, temp[0].split(": ")[1].length - 1),
      temp[1].split(": ")[1].substring(1, temp[1].split(": ")[1].length - 1),
      temp[2].split(": ")[1].substring(1, temp[2].split(": ")[1].length - 1),
      temp[7].split(": ")[1].substring(1, temp[7].split(": ")[1].length - 1),
      temp[5].split(": ")[1].substring(1, temp[5].split(": ")[1].length - 1),
      temp[8].split(": ")[1].substring(1, temp[8].split(": ")[1].length - 1)
    ];
    var flag = true;
    for (int i = 0; i < data.length; i++) {
      if (data[i][2] == dev[2]) {
        flag = false;
        data[i][3] = dev[3];
        data[i][4] = dev[4];
        data[i][5] = dev[5];
      }
    }
    if (flag) {
      dev[0] = "Beacon #${data.length}";
      data.add(dev);
    }
    if (dev[2].contains("AC:23:3F:F6:70:00") && int.parse(dev[5]) > adFilter) {
      canAdvertise = true;
    } else {
      canAdvertise = false;
    }
    updateView();
  }

  void updateView() {
    filterData = [];
    for (int i = 0; i < data.length; i++) {
      if (!(data[i][2]!.contains("AC:23:3F"))) continue;
      if (int.parse(data[i][5]!) > showFilter) filterData.add(data[i]);
    }
    setState(() {});
  }

  void advertise() async {
    if (canAdvertise) {
      // final isSupported = await blePeripheral.isSupported;
      stopScan();
      if (await blePeripheral.isAdvertising) {
        await blePeripheral.stop();
        createEncryptedUUID();
        startBeacon();
        ble();
      } else {
        await blePeripheral.start(
          advertiseData: advertiseData,
          advertiseSettings: advertiseSettings,
          // advertiseSetParameters: advertiseSetParameters,
        );
      }
      // print(isSupported);
      // print("here: ${await blePeripheral.isAdvertising}");
      isAdvertise = await blePeripheral.isAdvertising;
      updateView();
    }
  }

  @override
  void dispose() {
    beaconEventsController.close();
    BeaconsPlugin.stopMonitoring();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('iBeacon Scanner'),
        ),
        body: Column(
          children: [
            const SizedBox(height: 16.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 200.0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('RSSI Filter:',
                          style: TextStyle(fontSize: 16)),
                      Text((showFilter).toInt().toStringAsFixed(1),
                          style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10.0),
            Slider(
              value: -showFilter,
              min: 0,
              max: 100,
              onChanged: (newValue) {
                setState(() {
                  showFilter = -newValue;
                });
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 200.0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('AD Filter:', style: TextStyle(fontSize: 16)),
                      Text((adFilter).toInt().toStringAsFixed(1),
                          style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10.0),
            Slider(
              value: -adFilter,
              min: 0,
              max: 100,
              onChanged: (newValue) {
                setState(() {
                  adFilter = -newValue;
                });
              },
            ),
            const SizedBox(height: 10.0),
            Text(canAdvertise ? "CAN ADVERTISE" : "CANNOT ADVERTISE",
                style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 10.0),
            Text(isAdvertise ? "ADVERTISING" : "NOT ADVERTISING",
                style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 10.0),
            Text(advertiseData.serviceUuid!,
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10.0),
            Expanded(
              child: ListView.builder(
                itemCount: filterData.length,
                itemBuilder: (context, index) {
                  return DeviceWidget(
                    deviceName: filterData[index][0]!,
                    uuid: filterData[index][1]!,
                    macAddress: filterData[index][2]!,
                    scanTime: filterData[index][3]!,
                    distance: filterData[index][4]!,
                    rssi: filterData[index][5]!,
                  );
                },
              ),
            ),
          ],
        ),
        floatingActionButton:
            Column(mainAxisAlignment: MainAxisAlignment.end, children: [
          FloatingActionButton(
            onPressed: ble,
            backgroundColor: isScanning ? Colors.grey : Colors.blue,
            child: const Icon(Icons.add),
          ),
          const SizedBox(
            height: 10,
          ),
          FloatingActionButton(
            onPressed: advertise,
            backgroundColor: canAdvertise
                ? (isAdvertise ? Colors.red : Colors.blue)
                : Colors.grey,
            child: const Icon(Icons.send),
          ),
          const SizedBox(
            height: 10,
          ),
          FloatingActionButton(
            onPressed: sync,
            child: const Icon(Icons.sync),
          ),
        ]));
  }
}

class DeviceWidget extends StatelessWidget {
  final String deviceName;
  final String uuid;
  final String macAddress;
  final String scanTime;
  final String distance;
  final String rssi;

  const DeviceWidget(
      {required this.deviceName,
      required this.uuid,
      required this.macAddress,
      required this.scanTime,
      required this.distance,
      required this.rssi,
      super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8.0),
          Container(
            height: 3.0,
            color: Colors.black,
          ),
          const SizedBox(height: 8.0),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                deviceName,
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Text(
                'RSSI: $rssi',
                style: const TextStyle(fontSize: 20),
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          Container(
            height: 1.0,
            color: Colors.black,
          ),
          const SizedBox(height: 8.0),
          Text(
            'UUID: $uuid',
            style: const TextStyle(fontSize: 16),
          ),
          Text(
            'MAC Address: $macAddress',
            style: const TextStyle(fontSize: 16),
          ),
          Text(
            'Scan Time: $scanTime',
            style: const TextStyle(fontSize: 16),
          ),
          Text(
            'Distance: $distance',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8.0),
          Container(
            height: 3.0,
            color: Colors.black,
          ),
          const SizedBox(height: 15.0),
        ],
      ),
    );
  }
}

String convertStringtoUUID(String str) {
  return '${str.substring(0, 8)}-${str.substring(8, 12)}-${str.substring(12, 16)}-${str.substring(16, 20)}-${str.substring(20, 32)}';
}

String generateUUID(String prevUUID, String stringKey) {
  final initialUserData = Uint8List.fromList(hex.decode(prevUUID));
  final key = encrypt.Key(Uint8List.fromList(hex.decode(stringKey)));
  final encrypter =
      encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.ecb));
  final encrypted = encrypter.encryptBytes(initialUserData,
      iv: encrypt.IV(Uint8List.fromList([])));
  return hex.encode(encrypted.bytes).substring(0, 32);
}

class LogFile {
  late File _logFile;

  LogFile(String fileName) {
    _initLogFile(fileName);
  }

  void _initLogFile(String fileName) async {
    Directory appDocumentsDirectory = await getApplicationDocumentsDirectory();
    String logFilePath = '${appDocumentsDirectory.path}/$fileName';
    // print("file:/${logFilePath}");
    _logFile = File(logFilePath);
    if (!_logFile.existsSync()) {
      await _logFile.create();
    }
  }

  Future<void> append(String logEntry) async {
    await _logFile.writeAsString('$logEntry\n', mode: FileMode.append);
  }

  Future<void> write(String logEntry) async {
    await _logFile.writeAsString(logEntry);
  }

  Future<String> read() async {
    if (!_logFile.existsSync()) {
      return '';
    }
    return await _logFile.readAsString();
  }
}
