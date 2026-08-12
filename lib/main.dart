import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf_combiner/pdf_combiner.dart';

void main() {
  runApp(const FileXApp());
}

class FileXApp extends StatelessWidget {
  const FileXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FileX',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3157D5),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F7FC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF4F7FC),
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool busy = false;

  // Set this to your deployed FileX conversion backend.
  // Example: https://your-server.example.com
  static const String conversionServer = String.fromEnvironment(
    'FILEX_SERVER',
    defaultValue: '',
  );

  Future<void> _run(Future<String?> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final path = await action();
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved: ${File(path).uri.pathSegments.last}'),
          action: SnackBarAction(
            label: 'OPEN',
            onPressed: () => OpenFilex.open(path),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Operation failed: $e')),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> _wordToPdf() async {
    if (conversionServer.isEmpty) {
      throw Exception(
        'Word conversion server is not configured. Build with '
        '--dart-define=FILEX_SERVER=https://your-server.example.com',
      );
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'doc', 'docx', 'docm', 'dot', 'dotx', 'dotm', 'odt', 'rtf',
      ],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return null;

    final f = result.files.single;
    final response = await http.post(
      Uri.parse('$conversionServer/convert/word-to-pdf'),
      headers: {'Content-Type': 'application/octet-stream',
                'X-File-Name': Uri.encodeComponent(f.name)},
      body: f.bytes,
    );
    if (response.statusCode != 200) {
      throw Exception('Server returned ${response.statusCode}');
    }
    return _saveBytes(response.bodyBytes, _baseName(f.name) + '.pdf');
  }

  Future<String?> _pdfToWord() async {
    if (conversionServer.isEmpty) {
      throw Exception(
        'PDF conversion server is not configured. Build with '
        '--dart-define=FILEX_SERVER=https://your-server.example.com',
      );
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return null;

    final f = result.files.single;
    final response = await http.post(
      Uri.parse('$conversionServer/convert/pdf-to-word'),
      headers: {'Content-Type': 'application/octet-stream',
                'X-File-Name': Uri.encodeComponent(f.name)},
      body: f.bytes,
    );
    if (response.statusCode != 200) {
      throw Exception('Server returned ${response.statusCode}');
    }
    return _saveBytes(response.bodyBytes, _baseName(f.name) + '.docx');
  }

  Future<String?> _scanToPdf() async {
    final picker = ImagePicker();
    final images = <XFile>[];

    while (true) {
      final image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (image == null) break;
      images.add(image);

      if (!mounted) break;
      final more = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Page captured'),
          content: Text('${images.length} page(s) captured. Scan another page?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('FINISH'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('SCAN NEXT'),
            ),
          ],
        ),
      );
      if (more != true) break;
    }

    if (images.isEmpty) return null;

    final dir = await getApplicationDocumentsDirectory();
    final out = File(
      '${dir.path}/FileX_Scan_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );

    final inputs = <MergeInput>[
      for (final image in images) MergeInput.path(image.path),
    ];

    await PdfCombiner.createPDFFromMultipleImages(
      inputs: inputs,
      outputPath: out.path,
      config: const PdfFromMultipleImageConfig(
        rescale: ImageScale(width: 1240, height: 1754),
        keepAspectRatio: true,
      ),
    );
    return out.path;
  }

  Future<String?> _mergePdfs() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
    );
    if (result == null || result.files.length < 2) {
      throw Exception('Please select at least 2 PDF files.');
    }

    final dir = await getApplicationDocumentsDirectory();
    final out = File(
      '${dir.path}/FileX_Merged_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );

    final inputs = <MergeInput>[];
    for (final f in result.files) {
      if (f.path != null) {
        inputs.add(MergeInput.path(f.path!));
      } else if (f.bytes != null) {
        inputs.add(MergeInput.bytes(f.bytes!));
      }
    }

    await PdfCombiner.mergeMultiplePDFs(
      inputs: inputs,
      outputPath: out.path,
    );
    return out.path;
  }

  Future<String> _saveBytes(Uint8List bytes, String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  String _baseName(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, size: 25),
            SizedBox(width: 10),
            Text(
              'FileX',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 25),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your files, simplified.',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'Convert, scan and combine documents in seconds.',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.blueGrey.shade700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: .93,
                    children: [
                      _Tile(
                        icon: Icons.description_outlined,
                        title: 'Word to PDF',
                        subtitle: 'DOC, DOCX & more',
                        onTap: () => _run(_wordToPdf),
                      ),
                      _Tile(
                        icon: Icons.picture_as_pdf_outlined,
                        title: 'PDF to Word',
                        subtitle: 'Create mobile DOCX',
                        onTap: () => _run(_pdfToWord),
                      ),
                      _Tile(
                        icon: Icons.document_scanner_outlined,
                        title: 'Scan to PDF',
                        subtitle: 'Use your camera',
                        onTap: () => _run(_scanToPdf),
                      ),
                      _Tile(
                        icon: Icons.merge_type_outlined,
                        title: 'Merge PDFs',
                        subtitle: 'Combine 2 or more',
                        onTap: () => _run(_mergePdfs),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lock_outline, size: 22),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Files created by FileX are saved locally on your device.',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (busy)
            Positioned.fill(
              child: Container(
                color: Colors.black38,
                child: Center(
                  child: Card(
                    elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 24,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          SizedBox(
                            height: 42,
                            width: 42,
                            child: CircularProgressIndicator(strokeWidth: 4),
                          ),
                          SizedBox(height: 18),
                          Text(
                            'Processing file…',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text('Please wait'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.black12),
            boxShadow: const [
              BoxShadow(
                blurRadius: 12,
                offset: Offset(0, 5),
                color: Color(0x12000000),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF0FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 29, color: const Color(0xFF3157D5)),
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.blueGrey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
