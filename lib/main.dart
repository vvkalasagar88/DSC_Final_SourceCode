import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:animated_snack_bar/animated_snack_bar.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
// import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
// import 'package:share_plus/share_plus.dart';

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
  bool _showLogs = false;

  final ScrollController logScrollController = ScrollController();
  final TextEditingController textController = TextEditingController();

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
                              '${logs.toString().isEmpty ? 0 : logs.toString().split('\n').length - 1}',
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

  // ================= PDF GENERATION WITH SIGNATURE BLOCK =================
  Future<Uint8List> generateSignedPdf(
      String documentText, String signerLabel, DateTime signTime) async {
    final pdf = pw.Document();

    // Decode Base64 image
    // const String base64GreenTick = "iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAApUlEQVRIS2NkoBAwUj8FmP5TQwNjJgAuxQYAv/0JmSGrLgAAAABJRU5ErkJggg==";
    // final Uint8List imageBytes = base64Decode(base64GreenTick);

    // Load the green tick image from assets
    final ByteData imageData = await rootBundle.load('assets/images/green_tick.png');
    final Uint8List imageBytes = imageData.buffer.asUint8List();

    // Split text into lines to preserve line breaks
    final lines = documentText.split('\n');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'Government of Andhra Pradesh',
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 20),
              // Document content
              ...lines.map((line) => pw.Text(line, style: pw.TextStyle(fontSize: 12))),
              pw.SizedBox(height: 50),
              // pw.Divider(),
              // pw.SizedBox(height: 20),
              // Signature block with green tick
              pw.Row(
                children: [
                  pw.Spacer(),
                  // pw.Image(pw.MemoryImage(imageBytes), width: 30, height: 30),
                  // pw.Image(pw.MemoryImage(imageBytes), width: 30, height: 30),
                  // pw.Text('✓ ',
                  //     style: pw.TextStyle(
                  //       fontSize: 30,
                  //       color: PdfColors.green,
                  //       fontWeight: pw.FontWeight.bold,
                  //     )),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('Digitally Signed By:',
                            style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic)),
                        // pw.Text(signerLabel.isNotEmpty ? signerLabel : 'Undefined',
                        //     style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                        pw.Stack(
                          alignment: pw.Alignment.center,
                          children: [
                            // pw.Image(pw.MemoryImage(imageBytes), width: 80, height: 30, fit: pw.BoxFit.fill),
                            pw.Opacity(
                              opacity: 0.8, // Adjust as needed (0.0 = fully transparent, 1.0 = fully opaque)
                              child: pw.Image(
                                pw.MemoryImage(imageBytes),
                                width: 80,
                                height: 50,
                                fit: pw.BoxFit.contain,
                              ),
                            ),
                            pw.Text(
                              '${signerLabel.isNotEmpty ? signerLabel : 'Undefined'}\nDate & Time: ${DateFormat('yyyy.MM.dd HH:mm:ss').format(signTime)} IST',
                              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                            ),
                            // pw.Text(signerLabel.isNotEmpty ? signerLabel : 'Undefined',
                            //     style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                          ],
                        ),
                        pw.SizedBox(height: 8),
                        // pw.Text('Date & Time:',
                        //     style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic)),
                        // pw.Text(DateFormat('yyyy.MM.dd HH:mm:ss').format(signTime) + ' IST',
                        //     style: pw.TextStyle(fontSize: 12)),
                        // pw.Text(
                        //   'Date & Time: ${DateFormat('yyyy.MM.dd HH:mm:ss').format(signTime)} IST',
                        //   style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic), // same style for entire text
                        // ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return await pdf.save();
  }

  Future<String?> generateHashFromText() async {
    try {
      final String documentText = textController.text;
      if (documentText.trim().isEmpty) {
        await addLog('Document text is empty');
        return null;
      }

      final bytes = utf8.encode(documentText);
      final digest = sha256.convert(bytes);
      final hashHex = digest.toString();

      await addLog('Document text hash (SHA256): $hashHex');
      return hashHex;
    } catch (e, stackTrace) {
      await addLog('Hash generation error: $e');
      await addLog(stackTrace.toString());
      return null;
    }
  }

  // ---------- USB monitoring and PKCS#11 methods ----------
  @override
  void initState() {
    super.initState();
    // getAppVersion();
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
    
      A Digital Signature Certificate (DSC) is an electronic form of identity used to securely sign digital documents. The certificate is stored within a secure cryptographic token, commonly known as a DSC Token, which protects the private key from unauthorized access.

      Digital signatures provide authentication, integrity, and non-repudiation. Authentication confirms the identity of the signer, integrity ensures that the document has not been modified after signing, and non-repudiation prevents the signer from denying their signature.

      The use of digital signatures enables secure electronic transactions, reduces paperwork, improves efficiency, and supports environmentally friendly digital governance. Government departments, businesses, and individuals widely use DSC-based signing for applications, approvals, contracts, and official records.

      This document has been prepared for testing and demonstration purposes to validate the digital signing process using a DSC Token. Any modification to the signed content after the signature is applied will invalidate the signature verification.
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

    String? selectedKeyLabel;

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
        selectedKeyLabel = '';
      } else {
        selectedKeyLabel = selection['label']?.toString() ?? '';
        await addLog('Using Existing Key: ${selection['label']} (handle ${selection['handle']})');
        await _channel.invokeMethod('selectKeyPair', {
          'handle': selection['handle'],
          'id': selection['id'],
        });
      }

      // 1. Generate hash from document text
      final hashHex = await generateHashFromText();
      if (hashHex == null) {
        await addLog('Hash Generation Failed');
        return;
      }

      // 2. Sign the hash
      await addLog('Signing Data...');
      final signature = await _channel.invokeMethod('signData', {'hashHex': hashHex});
      final String signatureText = signature.toString();
      await addLog('Signature: $signatureText');

      // 3. Generate PDF with signature block
      final pdfBytes = await generateSignedPdf(
        textController.text,
        selectedKeyLabel ?? '',
        DateTime.now(),
      );
      await addLog('PDF generated, size: ${pdfBytes.length} bytes');

      // 4. Save PDF directly to Downloads folder using path_provider
      try {
        final directory = await getDownloadsDirectory();
        if (directory == null) {
          await addLog('❌ Could not access Downloads folder');
          if (mounted) {
            AnimatedSnackBar.material(
              '❌ Could not access Downloads folder',
              type: AnimatedSnackBarType.error,
              duration: const Duration(seconds: 5),
            ).show(context);
          }
          return;
        }

        final fileName = 'signed_document_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(pdfBytes);
        await addLog('✅ Signed PDF saved to: ${file.path}');

        if (mounted) {
          AnimatedSnackBar.material(
            '✅ PDF digitally signed and saved to Downloads',
            type: AnimatedSnackBarType.success,
            duration: const Duration(seconds: 5),
            mobilePositionSettings: const MobilePositionSettings(topOnAppearance: 100),
          ).show(context);

          // NEW: Show dialog with Open and Share/Download buttons
          _showPdfSuccessDialog(file.path);
        }
      } catch (e) {
        await addLog('❌ Exception saving PDF: $e');
        if (mounted) {
          AnimatedSnackBar.material(
            '❌ Error saving PDF: $e',
            type: AnimatedSnackBarType.error,
            duration: const Duration(seconds: 5),
          ).show(context);
        }
      }

      // 5. Verify signature (optional)
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
                    const Text('Select Key',
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
                              // subtitle: Text(
                              //   'Handle: ${key['handle']}${id.isNotEmpty ? '   ID: $id' : ''}',
                              //   style: const TextStyle(fontSize: 12),
                              // ),
                              // trailing: IconButton(
                              //   icon: const Icon(Icons.delete, color: Colors.red),
                              //   tooltip: 'Delete Key Pair',
                              //   onPressed: () => handleDelete(key),
                              // ),
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

  // NEW: Dialog shown after PDF is saved
  void _showPdfSuccessDialog(String filePath) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.picture_as_pdf, color: Colors.deepPurple),
              SizedBox(width: 8),
              Text('PDF Generated Successfully'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your digitally signed document is ready.'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.save_alt, size: 16, color: Colors.deepPurple),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        filePath,
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                // Open the PDF with default viewer
                try {
                  final result = await OpenFile.open(filePath);
                  if (result.type != ResultType.done) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not open PDF file')),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error opening file: $e')),
                  );
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                try {
                  String? outputPath = await FilePicker.platform.saveFile(
                    dialogTitle: 'Save Signed PDF',
                    fileName: 'signed_document_${DateTime.now().millisecondsSinceEpoch}.pdf',
                    bytes: await File(filePath).readAsBytes(), // optional: pass bytes to write directly
                  );
                  if (outputPath != null) {
                    // File already saved? Actually saveFile writes the bytes if provided.
                    // Alternatively, we could just copy the existing file.
                    final sourceFile = File(filePath);
                    final destFile = File(outputPath);
                    await sourceFile.copy(destFile.path);

                    AnimatedSnackBar.material(
                      'PDF saved to: $outputPath',
                      type: AnimatedSnackBarType.info,
                      duration: const Duration(seconds: 6),
                      mobilePositionSettings: const MobilePositionSettings(topOnAppearance: 100),
                      mobileSnackBarPosition: MobileSnackBarPosition.top,
                      desktopSnackBarPosition: DesktopSnackBarPosition.topCenter,
                    ).show(context);


                    // ScaffoldMessenger.of(context).showSnackBar(
                    //   SnackBar(content: Text('PDF saved to: $outputPath')),
                    // );


                  }
                } catch (e) {

                  AnimatedSnackBar.material(
                    'Error saving: $e',
                    type: AnimatedSnackBarType.error,
                    duration: const Duration(seconds: 6),
                    mobilePositionSettings: const MobilePositionSettings(topOnAppearance: 100),
                    mobileSnackBarPosition: MobileSnackBarPosition.top,
                    desktopSnackBarPosition: DesktopSnackBarPosition.topCenter,
                  ).show(context);

                  // ScaffoldMessenger.of(context).showSnackBar(
                  //   SnackBar(content: Text('Error saving: $e')),
                  // );
                }
              },
              icon: const Icon(Icons.download),
              label: const Text('Download'),
            )
          ],
        );
      },
    );
  }

  void showPinDialog() {
    if (textController.text.trim().isEmpty) {
      addLog('Cannot proceed: Document content is empty');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter document content before signing'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

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
                  // runTest('9885632251');
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
    // Decode Base64 image
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
            // borderRadius: BorderRadius.circular(5),
            borderRadius:BorderRadius.only(
              // topLeft: Radius.circular(45),
              // topRight: Radius.circular(45),
              bottomLeft: Radius.circular(30),
              bottomRight: Radius.circular(30),
            ),
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
                  'DSC Token Utility',
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
            // VERSION CHIP
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: Text(
                "Version 1.0.0",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.purple,
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic, // ✅ added italic
                ),
              ),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(15),
        // padding: const EdgeInsets.only(top: 15, bottom: 15),
        child: Column(
          children: [
            // USB status (fixed)
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


            // Stack(
            //   alignment: Alignment.center,
            //   children: [
            //     Opacity(
            //       opacity: 0.8,
            //       child: Image.asset(
            //         'assets/images/green_tick1.png',
            //         width: 80,
            //         height: 50,
            //         fit: BoxFit.contain,
            //       ),
            //     ),
            //     Text(
            //       'Undefinedfdgdfgdfgdfgdfgdfgdfgfd\nUndefinedfdgdfgdfgdfgdfgdfgdfgfd'
            //           ,
            //       style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            //     ),
            //   ],
            // ),
            // Document header (fixed)
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withOpacity(0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: Row(
                  children: [
                    const Icon(Icons.description, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Document Content',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const Spacer(),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: TextButton(
                        onPressed: () {
                          textController.clear();
                          addLog('Document content cleared by user');
                          AnimatedSnackBar.material(
                            'Document content cleared',
                            type: AnimatedSnackBarType.info,
                            duration: const Duration(seconds: 6),
                            mobilePositionSettings: const MobilePositionSettings(topOnAppearance: 100),
                            mobileSnackBarPosition: MobileSnackBarPosition.top,
                            desktopSnackBarPosition: DesktopSnackBarPosition.topCenter,
                          ).show(context);
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.clear_all, size: 16),
                            SizedBox(width: 4),
                            Text('Clear', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Document content area - scrollable and takes remaining space
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.deepPurple.withOpacity(0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: textController,
                  maxLines: null,
                  expands: true,
                  decoration: InputDecoration(
                    hintText: 'Enter text to digitally sign...',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
              ),
            ),

            const SizedBox(height: 6),

            // Buttons row (fixed)
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  // Expanded(
                  //   child: ElevatedButton.icon(
                  //     onPressed: showDocumentPreview,
                  //     icon: const Icon(Icons.preview),
                  //     label: const Text(
                  //       'Preview',
                  //       style: TextStyle(fontWeight: FontWeight.bold),
                  //     ),
                  //     style: ElevatedButton.styleFrom(
                  //       backgroundColor: Colors.blue,
                  //       foregroundColor: Colors.white,
                  //       elevation: 4,
                  //       shape: const RoundedRectangleBorder(
                  //         borderRadius: BorderRadius.only(
                  //           topLeft: Radius.circular(14),
                  //           bottomLeft: Radius.circular(14),
                  //         ),
                  //       ),
                  //     ),
                  //   ),
                  // ),
                  // const SizedBox(width: 2),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: tokenConnected && !loading ? showPinDialog : null,
                      icon: loading
                          ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Icon(Icons.key_rounded),
                      label: loading
                          ? const SpinKitFadingCircle(
                        color: Colors.white,
                        size: 18,
                      )
                          : const Text(
                        'Digital Sign',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(14),
                            bottomRight: Radius.circular(14),
                            topLeft: Radius.circular(14),
                            bottomLeft: Radius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // Logs section (sticky bottom, height animates)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: _showLogs ? 250 : 45,
              width: double.infinity,
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
                          const Text(
                            'Logs',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '${logs.toString().isEmpty ? 0 : logs.toString().split('\n').length - 1}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: TextButton(
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
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.clear_all, size: 16),
                                  SizedBox(width: 4),
                                  Text('Clear', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: showFullScreenLogs,
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.fullscreen_rounded, color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () {
                                setState(() {
                                  _showLogs = !_showLogs;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  _showLogs ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_showLogs)
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
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade800,
                                  height: 1.5,
                                ),
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

  void showDocumentPreview() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(
              maxHeight: 600,
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.deepPurple,
                  child: const Row(
                    children: [
                      Icon(Icons.description, color: Colors.white),
                      SizedBox(width: 10),
                      Text(
                        'Document Preview',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        textController.text,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    label: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // String appVersion = "1.0.0";
  //
  // void getAppVersion() async {
  //   PackageInfo packageInfo = await PackageInfo.fromPlatform();
  //
  //   setState(() {
  //     appVersion = packageInfo.version;
  //   });
  // }
}