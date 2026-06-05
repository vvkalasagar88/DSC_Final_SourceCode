import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:animated_snack_bar/animated_snack_bar.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'logger_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await LoggerService.requestPermission();
  await LoggerService.write('APP STARTED');

  FlutterError.onError = (FlutterErrorDetails details) async {
    FlutterError.dumpErrorToConsole(details);
    await LoggerService.write('FLUTTER ERROR: ${details.exception}');
    await LoggerService.write(details.stack.toString());
  };

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DSC Testing App',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const MethodChannel _channel = MethodChannel('dsc_token_channel');

  final StringBuffer logs = StringBuffer();
  bool tokenConnected = false;
  bool loading = false;
  bool _running = true;

  final ScrollController logScrollController = ScrollController();
  final TextEditingController textController = TextEditingController();

  // Key for capturing the document widget
  final GlobalKey repaintKey = GlobalKey();

  Uint8List? generatedImage;
  Uint8List? signedImageBytes;

  void scrollLogsToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (logScrollController.hasClients) {
        logScrollController.animateTo(
          logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void showFullScreenLogs() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: Scaffold(
            backgroundColor: const Color(0xFFF8F5FF),
            appBar: AppBar(
              elevation: 0,
              centerTitle: true,
              backgroundColor: const Color(0xFF7C3AED),
              title: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.article, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Logs Viewer',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ],
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.deepPurple.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.deepPurple.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade50,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.description_outlined,
                              color: Colors.deepPurple.shade700, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text('Log Details',
                                style: TextStyle(
                                    color: Colors.deepPurple.shade700,
                                    fontWeight: FontWeight.bold)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${logs.toString().isEmpty ? 0 : logs.toString().split('\n').length}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepPurple.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: logScrollController,
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          logs.toString().isEmpty ? 'No logs available' : logs.toString(),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade800,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> addLog(String text) async {
    debugPrint(text);
    await LoggerService.write(text);
    if (!mounted) return;

    final now = DateTime.now();
    final time =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
    final newLog = '[$time] $text\n';

    setState(() {
      logs.write(newLog);
    });
    scrollLogsToBottom();
  }

  // ================= Overlay signature fields on image =================
  Future<Uint8List?> overlaySignatureOnImage(
      Uint8List originalPng,
      String signerLabel,
      DateTime signTime,
      ) async {
    try {
      // Decode the original image
      final ui.Codec codec = await ui.instantiateImageCodec(originalPng);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ui.Image original = frame.image;

      // Create a canvas to draw on
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      final Paint paint = Paint();

      // Draw the original image
      canvas.drawImage(original, Offset.zero, paint);

      // Format the signer string
      final signer = signerLabel.isNotEmpty ? signerLabel : 'Undefined';
      final formattedTime = "${signTime.year}-${signTime.month}-${signTime.day} "
          "${signTime.hour}:${signTime.minute}:${signTime.second}";

      // Build the text paragraph (only three lines)
      final ui.ParagraphBuilder paragraphBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.right,
        ),
      )
        ..pushStyle(ui.TextStyle(color: const Color(0xFFCC0000)))
        ..addText('Digitally Signed\nSigner: $signer\nTime: $formattedTime');

      final ui.Paragraph paragraph = paragraphBuilder.build()
        ..layout(ui.ParagraphConstraints(width: original.width.toDouble()));

      // Position at bottom-right with 20px padding
      final double x = original.width - paragraph.width - 20;
      final double y = original.height - paragraph.height - 20;
      canvas.drawParagraph(paragraph, Offset(x, y));

      // Convert to PNG bytes
      final ui.Picture picture = recorder.endRecording();
      final ui.Image signedImage = await picture.toImage(original.width, original.height);
      final ByteData? byteData = await signedImage.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      await addLog('Overlay error: $e');
      return null;
    }
  }
  // ================================================================

  Future<String?> generateHashHex() async {
    try {
      await addLog('Generating Image...');

      final boundary = repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 3);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        await addLog('ByteData NULL');
        return null;
      }

      final pngBytes = byteData.buffer.asUint8List();
      generatedImage = pngBytes;
      signedImageBytes = pngBytes; // initial copy, will be overlaid later

      final digest = sha256.convert(pngBytes);
      final hashHex = digest.toString();

      await addLog('HashHex = $hashHex');
      return hashHex;
    } catch (e, stackTrace) {
      await addLog('Image Error: $e');
      await addLog(stackTrace.toString());
      return null;
    }
  }

  void showSignedImagePopup(String signature) {
    if (signedImageBytes == null) {
      addLog('No Signed Image Available');
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          child: Container(
            padding: const EdgeInsets.all(16),
            constraints: const BoxConstraints(maxHeight: 700),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Signed Image Preview',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(signedImageBytes!),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _running = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'nativeLog') {
        await addLog(call.arguments?.toString() ?? 'NULL LOG');
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      startUsbMonitoring();
    });

    addLog('[FLUTTER] App Started');
    LoggerService.getLogPath().then((path) {
      addLog('LOG FILE LOCATION = $path');
    });

    textController.text = '''
Digital Signature Test

This content is converted
into image and signed
using DSC Token.
''';
  }

  @override
  void dispose() {
    _running = false;
    textController.dispose();
    logScrollController.dispose();
    addLog('Widget Disposed');
    super.dispose();
  }

  void startUsbMonitoring() {
    addLog('USB Monitoring Started');
    Future.doWhile(() async {
      if (!mounted || !_running) {
        await addLog('Monitoring Stopped');
        return false;
      }
      await checkToken();
      if (tokenConnected) {
        await addLog('Token Connected - Monitoring Stopped');
        return false;
      }
      await Future.delayed(const Duration(seconds: 3));
      return true;
    });
  }

  Future<void> checkToken() async {
    await addLog('[FLUTTER] checkToken Calling...');
    try {
      final dynamic response = await _channel.invokeMethod('checkUsbToken');
      await addLog('Raw Result = $response');
      final bool result = response == true;
      await addLog('Parsed Result = $result');

      if (result != tokenConnected) {
        tokenConnected = result;
        if (result) {
          await addLog('USB Token Connected');
        } else {
          await addLog('USB Token Removed');
        }
        if (mounted) setState(() {});
      }
    } on PlatformException catch (e) {
      await addLog('PlatformException: ${e.code} ${e.message}');
    } catch (e, stackTrace) {
      await addLog('USB Check Error: $e');
      await addLog(stackTrace.toString());
    }
  }

  Future<void> runTest(String pin) async {
    await addLog('runTest Started');
    setState(() {
      loading = true;
    });

    String? selectedKeyLabel; // to store the label of the key used

    try {
      await addLog('--------------------------------');
      await addLog('Initializing PKCS11...');
      final initResult = await _channel.invokeMethod('initialize');
      await addLog('Initialize Result = $initResult');
      await Future.delayed(const Duration(seconds: 2));
      await addLog('PKCS11 Initialized');

      await addLog('Getting Slot Info...');
      final slotInfo = await _channel.invokeMethod('getSlotInfo');
      await addLog('Token Label: $slotInfo');

      await addLog('Opening Session...');
      final openResult = await _channel.invokeMethod('openSession');
      await addLog('Open Session Result = $openResult');

      await addLog('Logging Into Token...');
      final loginResult = await _channel.invokeMethod('loginUser', {'pin': pin});
      await addLog('Login Result = $loginResult');

      await addLog('Fetching Key Pairs...');
      final List<Map<String, dynamic>> keyList = await fetchKeyPairs();
      await addLog('Found ${keyList.length} key pair(s)');
      if (!mounted) return;

      final selection = await showKeySelectionDialog(keyList);
      if (selection == null) {
        await addLog('Key selection cancelled');
        try {
          await _channel.invokeMethod('logout');
          await _channel.invokeMethod('closeSession');
        } catch (_) {}
        if (mounted) setState(() => loading = false);
        return;
      }

      if (selection['action'] == 'new') {
        await addLog('Generating RSA Keypair...');
        final handles = await _channel.invokeMethod('generateKeypair');
        await addLog('Public Key Handle: ${handles['publicKey']}');
        await addLog('Private Key Handle: ${handles['privateKey']}');
        // For a newly generated key, we don't have a label. Use empty string (will show 'Undefined')
        selectedKeyLabel = '';
      } else {
        selectedKeyLabel = selection['label']?.toString() ?? '';
        await addLog('Using Existing Key: ${selection['label']} (handle ${selection['handle']})');
        await _channel.invokeMethod('selectKeyPair', {
          'handle': selection['handle'],
          'id': selection['id'],
        });
      }

      final hashHex = await generateHashHex();
      if (hashHex == null) {
        await addLog('Hash Generation Failed');
        return;
      }

      await addLog('Signing Data...');
      final signature = await _channel.invokeMethod('signData', {'hashHex': hashHex});
      final String signatureText = signature.toString();
      await addLog(signatureText);

      // ========== Overlay the three fields (no raw signature) ==========
      if (generatedImage != null) {
        final overlaid = await overlaySignatureOnImage(
          generatedImage!,
          selectedKeyLabel ?? '',
          DateTime.now(),
        );
        if (overlaid != null) {
          signedImageBytes = overlaid;
          await addLog('Signature fields overlaid onto image');
        } else {
          signedImageBytes = generatedImage;
          await addLog('Overlay failed, using original image');
        }
      }
      // =================================================================

      showSignedImagePopup(signatureText); // popup shows overlaid image

      await addLog('Verifying Signature...');
      final verify = await _channel.invokeMethod('verifySignature');
      await addLog('Verify Result = $verify');
      await addLog(verify == true ? 'Verification Success' : 'Verification Failed');

      await addLog('Logging Out...');
      final logoutResult = await _channel.invokeMethod('logout');
      await addLog('Logout Result = $logoutResult');

      await addLog('Closing Session...');
      final closeResult = await _channel.invokeMethod('closeSession');
      await addLog('Close Session Result = $closeResult');

      await addLog('TEST COMPLETED SUCCESSFULLY');
      final path = await LoggerService.getLogPath();
      await addLog('LOG FILE PATH = $path');

    } on PlatformException catch (e) {
      await addLog('PlatformException: ${e.code} ${e.message}');
    } catch (e, stackTrace) {
      await addLog('TEST ERROR: $e');
      await addLog(stackTrace.toString());
    }

    if (mounted) setState(() => loading = false);
  }

  Future<List<Map<String, dynamic>>> fetchKeyPairs() async {
    final dynamic rawKeys = await _channel.invokeMethod('listKeyPairs');
    return (rawKeys as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>?> showKeySelectionDialog(List<Map<String, dynamic>> keys) {
    final List<Map<String, dynamic>> localKeys = List<Map<String, dynamic>>.from(keys);

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            Future<void> handleDelete(Map<String, dynamic> key) async {
              final confirm = await showDialog<bool>(
                context: dialogContext,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete Key Pair'),
                  content: Text('Delete "${key['label']}"?\n'
                      'This permanently removes it from the token and cannot be undone.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirm != true) return;

              try {
                await _channel.invokeMethod('deleteKeyPair', {
                  'handle': key['handle'],
                  'id': key['id'],
                });
                await addLog('Deleted Key: ${key['label']}');
                final refreshed = await fetchKeyPairs();
                setLocalState(() {
                  localKeys..clear()..addAll(refreshed);
                });
              } catch (e) {
                await addLog('Delete Key Error: $e');
              }
            }

            return Dialog(
              child: Container(
                padding: const EdgeInsets.all(16),
                constraints: const BoxConstraints(maxHeight: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Select Key Pair',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    if (localKeys.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No key pairs found on token.\nCreate a new one to continue.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: localKeys.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final key = localKeys[index];
                            final id = (key['id'] ?? '').toString();
                            return ListTile(
                              leading: const Icon(Icons.vpn_key),
                              title: Text(key['label']?.toString() ?? 'Key'),
                              subtitle: Text(
                                'Handle: ${key['handle']}${id.isNotEmpty ? '   ID: $id' : ''}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                tooltip: 'Delete Key Pair',
                                onPressed: () => handleDelete(key),
                              ),
                              onTap: () {
                                Navigator.pop(dialogContext, {
                                  'action': 'existing',
                                  'handle': key['handle'],
                                  'id': key['id'],
                                  'label': key['label'],
                                });
                              },
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(dialogContext, {'action': 'new'}),
                        icon: const Icon(Icons.add),
                        label: const Text('Create New Key Pair'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(dialogContext, null),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void showPinDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Token Login'),
          content: TextField(
            controller: controller,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'Enter Token PIN'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final pin = controller.text.trim();
                Navigator.pop(context);
                if (pin.isNotEmpty) {
                  addLog('PIN Entered, Starting Test...');
                  runTest(pin);
                } else {
                  addLog('PIN Empty');
                }
              },
              child: const Text('Start Test'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        centerTitle: true,
        elevation: 15,
        shadowColor: Colors.black45,
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        flexibleSpace: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.purple, Color(0xFF7C3AED), Color(0xFF9333EA)],
            ),
            borderRadius: BorderRadius.circular(5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withOpacity(0.45),
                blurRadius: 8,
                spreadRadius: 1,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: -30,
                right: -30,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                bottom: -20,
                left: -20,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: []),
              ),
            ],
          ),
        ),
        title: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.30),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.usb_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 12),
                const Text(
                  'DSC Token Testing',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.0,
                    shadows: [Shadow(color: Colors.black38, offset: Offset(0, 5), blurRadius: 5)],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Digital Signature Test',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
                letterSpacing: 1.2,
                shadows: [Shadow(color: Colors.black38, offset: Offset(0, 5), blurRadius: 5)],
              ),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: tokenConnected
                      ? [const Color(0xFF11998E), const Color(0xFF38EF7D)]
                      : [const Color(0xFFFF512F), const Color(0xFFDD2476)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: (tokenConnected ? Colors.green : Colors.red).withOpacity(0.42),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      tokenConnected ? Icons.usb_rounded : Icons.usb_off_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tokenConnected ? 'USB Token Connected' : 'USB Token Not Connected',
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Icon(
                    tokenConnected ? Icons.check_circle : Icons.cancel,
                    color: Colors.white,
                    size: 20,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Document content with RepaintBoundary
            RepaintBoundary(
              key: repaintKey,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.deepPurple.withOpacity(0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.description, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          const Text(
                            'Document Content',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.all(1),
                      child: TextField(
                        controller: textController,
                        maxLines: 6,
                        decoration: InputDecoration(
                          hintText: 'Enter text to digitally sign...',
                          filled: true,
                          fillColor: const Color(0xFFF7F2FF),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(11),
                            borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
                          ),
                        ),
                        style: const TextStyle(fontSize: 15, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 6),
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: tokenConnected && !loading ? showPinDialog : null,
                      icon: loading
                          ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                          : const Icon(Icons.play_arrow_rounded),
                      label: Text(loading ? 'Running...' : 'Run Test', style: const TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(topLeft: Radius.circular(14), bottomLeft: Radius.circular(14)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        setState(() => logs.clear());
                        await LoggerService.clearLogs();
                        if (mounted) {
                          AnimatedSnackBar.material(
                            'Logs cleared successfully',
                            type: AnimatedSnackBarType.info,
                            duration: const Duration(seconds: 6),
                            mobilePositionSettings: const MobilePositionSettings(topOnAppearance: 100),
                            mobileSnackBarPosition: MobileSnackBarPosition.bottom,
                            desktopSnackBarPosition: DesktopSnackBarPosition.bottomLeft,
                          ).show(context);
                        }
                      },
                      icon: const Icon(Icons.delete),
                      label: const Text('Clear Logs', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(topRight: Radius.circular(14), bottomRight: Radius.circular(14)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.deepPurple.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.deepPurple.withOpacity(0.48),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: const BoxDecoration(
                        color: Color(0xFF7C3AED),
                        borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.article, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Logs',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                          Container(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${logs.toString().isEmpty ? 0 : logs.toString().split('\n').length - 1}',
                              textAlign: TextAlign.left,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: showFullScreenLogs,
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.fullscreen_rounded, color: Colors.deepPurple, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: SingleChildScrollView(
                          controller: logScrollController,
                          child: SizedBox(
                            width: double.infinity,
                            child: SelectableText(
                              logs.toString().isEmpty ? 'No logs available' : logs.toString(),
                              textAlign: TextAlign.left,
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade800, height: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}