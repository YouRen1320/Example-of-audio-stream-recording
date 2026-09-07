import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recorded/websocket.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'DASHSCOPE_API_KEY=test-only-key');
  });

  test('接受当前接口支持的 8000Hz 采样率', () {
    expect(() => SpeechRecognizer(sampleRate: 8000), returnsNormally);
  });

  test('拒绝当前接口不支持的采样率', () {
    expect(
      () => SpeechRecognizer(sampleRate: 16000),
      throwsA(isA<ArgumentError>()),
    );
  });
}
