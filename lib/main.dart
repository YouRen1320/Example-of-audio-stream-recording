// 导入Flutter基础包和录音库
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'websocket.dart';

void main() async {
  // 初始化环境变量
  await dotenv.load(fileName: ".env");
  // 应用入口，启动根组件
  runApp(const MyApp());
}

// 主应用组件
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const AudioRecorderPage(), // 设置主页为录音页面
      debugShowCheckedModeBanner: false, // 移除调试标志
    );
  }
}

// 录音功能页面组件
class AudioRecorderPage extends StatefulWidget {
  const AudioRecorderPage({super.key});

  @override
  State<AudioRecorderPage> createState() => _AudioRecorderPageState();
}

// 录音页面状态管理类
class _AudioRecorderPageState extends State<AudioRecorderPage> {
  late final AudioRecorder _audioRecorder; // 音频录制器实例
  bool isRecording = false; // 录音状态标志
  Stream<List<int>>? _audioStream; // 音频数据流（原始PCM数据）
  late final SpeechRecognizer _speechRecognizer; // 语音识别器实例
  String _recognizedText = ''; // 识别的文本

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder(); // 初始化录音器
    _speechRecognizer = SpeechRecognizer(sampleRate: 8000); // 初始化语音识别器
    _checkPermission(); // 启动时检查权限
  }

  // 检查录音权限
  Future<void> _checkPermission() async {
    if (await _audioRecorder.hasPermission()) {
      // 权限已授予
      print("已获得录音权限");
    } else {
      // 权限被拒绝时的处理
      print("录音权限未授予");
      // 实际项目中可在此添加跳转系统设置的逻辑
    }
  }

  @override
  void dispose() {
    _audioRecorder.dispose(); // 释放录音器资源
    _speechRecognizer.dispose(); // 释放语音识别器资源
    super.dispose();
  }

  // 开始录音（流模式）
  Future<void> startRecording() async {
    if (!isRecording) {
      try {
        // 启动语音识别
        await _speechRecognizer.startRecognition(
          onResult: (text) {
            setState(() {
              _recognizedText = text;
            });
          },
          onCompleted: () {
            print('语音识别完成');
          },
          onError: (error) {
            print('语音识别错误: $error');
          },
        );

        // 启动音频流录制
        _audioStream = await _audioRecorder.startStream(
          RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 8000),
        );

        // 监听音频数据流
        _audioStream?.listen(
          (data) {
            // 发送音频数据到语音识别器
            _speechRecognizer.sendAudioData(data);
          },
          onError: (error) {
            print('音频流异常: $error');
            stopRecording();
          },
          onDone: () {
            print('音频流结束');
            setState(() => isRecording = false);
          },
        );

        setState(() => isRecording = true);
      } catch (e) {
        print("启动录音失败: $e");
      }
    }
  }

  // 停止录音
  Future<void> stopRecording() async {
    if (isRecording) {
      try {
        await _audioRecorder.stop(); // 停止录音器
        _speechRecognizer.finishTask(); // 结束语音识别任务
        setState(() => isRecording = false);
        print("录音已停止");
      } catch (e) {
        print("停止录音失败: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("实时音频流录制"), centerTitle: true),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 动态切换按钮：开始/停止
            ElevatedButton(
              onPressed: isRecording ? stopRecording : startRecording,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 20,
                ),
              ),
              child: Text(
                isRecording ? "停止录制" : "开始录制",
                style: const TextStyle(fontSize: 20),
              ),
            ),
            const SizedBox(height: 20),
            // 状态提示
            Text(
              isRecording ? "录音进行中..." : "准备就绪",
              style: TextStyle(
                color: isRecording ? Colors.green : Colors.grey,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 20),
            // 显示识别的文本
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _recognizedText.isEmpty ? "等待识别..." : _recognizedText,
                style: const TextStyle(fontSize: 18),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
