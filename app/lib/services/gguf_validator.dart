import 'dart:io';

class GgufValidator {
  static const List<int> _ggufMagic = [0x47, 0x47, 0x55, 0x46]; // "GGUF"

  static Future<GgufValidationResult> validateFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return GgufValidationResult(
          isValid: false,
          error: 'File does not exist',
        );
      }

      final fileBytes = await file.openRead(0, 4).first;
      if (fileBytes.length < 4) {
        return GgufValidationResult(
          isValid: false,
          error: 'File is too small to be a valid GGUF',
        );
      }

      final matchesMagic = _ggufMagic.asMap().entries.every(
            (entry) => entry.value == fileBytes[entry.key],
          );

      if (!matchesMagic) {
        return GgufValidationResult(
          isValid: false,
          error: 'File is not a valid GGUF (wrong magic number)',
        );
      }

      return GgufValidationResult(isValid: true);
    } catch (e) {
      return GgufValidationResult(
        isValid: false,
        error: 'Error validating file: $e',
      );
    }
  }
}

class GgufValidationResult {
  final bool isValid;
  final String? error;

  const GgufValidationResult({
    required this.isValid,
    this.error,
  });
}
