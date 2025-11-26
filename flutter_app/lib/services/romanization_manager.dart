import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class RomanizationManager {
  static RomanizationManager? _instance;
  String? _scriptPath;
  
  RomanizationManager._();
  
  static RomanizationManager get instance {
    _instance ??= RomanizationManager._();
    return _instance!;
  }
  
  Future<String> getScriptPath() async {
    if (_scriptPath != null) {
      return _scriptPath!;
    }
    
    const assetPath = 'scripts/romanize.py';
    
    final appDir = await getApplicationSupportDirectory();
    final scriptsDir = Directory(path.join(appDir.path, 'scripts'));
    
    if (!await scriptsDir.exists()) {
      await scriptsDir.create(recursive: true);
    }
    
    final scriptFile = File(path.join(scriptsDir.path, 'romanize.py'));
    
    if (!await scriptFile.exists()) {
      print('Extracting romanization script to ${scriptFile.path}');
      final scriptContent = await rootBundle.loadString(assetPath);
      await scriptFile.writeAsString(scriptContent);
      
      if (Platform.isLinux || Platform.isMacOS) {
        await Process.run('chmod', ['+x', scriptFile.path]);
      }
    }
    
    _scriptPath = scriptFile.path;
    return _scriptPath!;
  }
  
  Future<bool> isAvailable() async {
    try {
      final scriptPath = await getScriptPath();
      final result = await Process.run('python3', [scriptPath, 'test']);
      return result.exitCode == 0 || result.stdout.toString().contains('"result"');
    } catch (e) {
      print('Romanization not available: $e');
      return false;
    }
  }
}
