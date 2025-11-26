import 'dart:convert';
import 'dart:io';
import 'romanization_manager.dart';

class RomanizationService {
  final RomanizationManager _manager = RomanizationManager.instance;
  
  Future<String?> romanize(String text) async {
    try {
      final scriptPath = await _manager.getScriptPath();
      
      print('Using romanization script at: $scriptPath');
      
      final result = await Process.run('python3', [scriptPath, text]);
      
      if (result.exitCode != 0) {
        print('Romanization error: ${result.stderr}');
        return null;
      }
      
      final output = jsonDecode(result.stdout.toString());
      if (output['error'] != null) {
        print('Romanization script error: ${output['error']}');
        return null;
      }
      
      return output['result'];
    } catch (e) {
      print('Romanization exception: $e');
      return null;
    }
  }
}
