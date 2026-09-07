import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // 新增导入
import 'package:web_socket_channel/io.dart'; // 增加 IOWebSocketChannel 的导入

/// 语音识别器类，提供基于WebSocket的实时语音识别功能
/// 使用阿里云达摩院语音识别API（paraformer-realtime-v2模型）
class SpeechRecognizer {
  /// WebSocket服务端地址
  static const String _url =
      'wss://dashscope.aliyuncs.com/api-ws/v1/inference'; // 移除末尾的斜杠

  /// API鉴权密钥
  final String apiKey = dotenv.get('DASHSCOPE_API_KEY');

  /// 音频采样率（默认8000Hz）
  final int sampleRate;

  /// WebSocket通信通道
  WebSocketChannel? _channel;

  /// 语音识别任务唯一ID
  String _taskId = '';

  /// 任务启动状态标记
  bool _taskStarted = false;

  /// 任务结束指令已发送标记
  bool _taskFinishSent = false;

  /// 构造函数
  /// [sampleRate] - 音频采样率（默认8000）
  SpeechRecognizer({this.sampleRate = 8000})
    : assert(dotenv.isInitialized, '环境变量未初始化') {
    // 安全验证
    if (sampleRate != 8000) {
      throw ArgumentError('阿里云API仅支持8000Hz采样率');
    }
    if (apiKey.isEmpty) {
      throw ArgumentError('DASHSCOPE_API_KEY 未配置');
    }
    _taskStarted = false;
    _taskFinishSent = false;
  }

  /// 启动语音识别流程
  /// [onResult] - 实时识别结果回调
  /// [onCompleted] - 识别完成回调
  /// [onError] - 错误处理回调
  Future<void> startRecognition({
    required Function(String) onResult,
    required Function() onCompleted,
    required Function(String) onError,
  }) async {
    // 生成32位任务ID
    _taskId = const Uuid().v4().replaceAll('-', '').substring(0, 32);

    // 重置状态标志
    _taskStarted = false;
    _taskFinishSent = false;

    try {
      // 建立WebSocket连接
      final channel = await _connectWebSocket();
      _channel = channel;

      // 发送任务启动指令
      _sendRunTask(channel);

      // 监听WebSocket响应
      channel.stream.listen(
        (data) => _handleMessage(data, onResult, onCompleted, onError),
        onError: (error) => onError('WebSocket 错误: $error'),
        onDone: () {
          if (!_taskStarted) {
            onError('连接意外中断，任务未启动');
          }
          onCompleted();
        },
      );
    } catch (e) {
      onError('连接失败: $e');
    }
  }

  /// 建立WebSocket连接
  /// 返回配置了认证头的WebSocket通道
  Future<IOWebSocketChannel> _connectWebSocket() async {
    try {
      print('正在连接WebSocket...');
      final uri = Uri.parse(_url);

      final channel = IOWebSocketChannel.connect(
        uri,
        headers: {
          'Authorization': 'bearer $apiKey', // 修正Authorization header格式
          'X-DashScope-DataInspection': 'enable',
          'Content-Type': 'application/json',
        },
      );

      print('WebSocket连接已建立');
      return channel;
    } catch (e) {
      print('WebSocket连接失败: $e'); // 添加错误日志
      throw Exception('WebSocket连接失败: $e');
    }
  }

  /// 发送任务启动指令
  /// [channel] - 已建立的WebSocket通道
  void _sendRunTask(WebSocketChannel channel) {
    final message = jsonEncode({
      'header': {
        'action': 'run-task',
        'task_id': _taskId,
        'streaming': 'duplex',
      },
      'payload': {
        'task_group': 'audio',
        'task': 'asr',
        'function': 'recognition',
        'model': 'paraformer-realtime-8k-v2',
        'parameters': {
          'sample_rate': sampleRate,
          'format': 'pcm', // 改回pcm格式
          'language_hints': ['zh'], // 添加此行，指定中文识别
        },
        'input': {},
      },
    });

    print('发送任务启动指令');
    channel.sink.add(message);
  }

  /// 处理服务端消息
  /// [data] - 原始消息数据
  /// [onResult] - 结果回调
  /// [onCompleted] - 完成回调
  /// [onError] - 错误回调
  void _handleMessage(
    dynamic data,
    Function(String) onResult,
    Function() onCompleted,
    Function(String) onError,
  ) {
    try {
      final message = jsonDecode(data);
      final header = message['header'];

      print('消息类型: ${header['event']}');

      switch (header['event']) {
        case 'task-started':
          _taskStarted = true;
          print('语音识别任务已启动 - TaskID: $_taskId');
          break;
        case 'result-generated':
          final text = message['payload']['output']['sentence']['text'] ?? '';
          // 识别文本可能包含个人信息，只通过回调交给界面，不写入调试日志。
          onResult(text);
          break;
        case 'task-finished':
          print('语音识别任务完成');
          _taskFinishSent = true; // 标记任务已经结束
          _channel?.sink.close();
          onCompleted();
          break;
        case 'task-failed':
          final errorMsg = '识别失败: ${header['error_message']}';
          print(errorMsg);
          onError(errorMsg);
          _channel?.sink.close();
          break;
        default:
          print('未知事件: ${header['event']}');
      }
    } catch (e) {
      print('消息处理错误: $e');
      onError('消息解析失败: $e');
    }
  }

  /// 添加重连机制
  Future<void> _reconnect() async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        _channel = await _connectWebSocket();
        _sendRunTask(_channel!);
        return;
      } catch (e) {
        retryCount++;
        await Future.delayed(Duration(seconds: retryCount));
      }
    }
    throw Exception('重连失败');
  }

  /// 发送任务结束指令
  void _sendFinishTask() {
    if (_channel != null && _taskStarted && !_taskFinishSent) {
      final message = jsonEncode({
        'header': {
          'action': 'finish-task',
          'task_id': _taskId,
          'streaming': 'duplex',
        },
        'payload': {'input': {}},
      });

      print('发送任务结束指令');
      _channel!.sink.add(message);
      _taskFinishSent = true;
    }
  }

  /// 发送音频数据块
  /// [audioData] - 音频数据块
  void sendAudioData(List<int> audioData) {
    if (_taskStarted && _channel != null) {
      try {
        // 根据阿里云文档，直接发送二进制音频数据
        print('发送PCM数据: ${audioData.length} bytes');
        _channel!.sink.add(Uint8List.fromList(audioData));
      } catch (e) {
        print('音频发送失败: $e');
      }
    }
  }

  /// 结束当前识别任务
  void finishTask() {
    if (_taskStarted && !_taskFinishSent) {
      _sendFinishTask();
    }
  }

  /// 释放资源
  /// 必须在使用完毕后调用以防止内存泄漏
  void dispose() {
    _channel?.sink.close();
  }
}

// 示例用法
void main() async {
  // 加载环境变量
  await dotenv.load(fileName: ".env");

  // 初始化识别器
  final recognizer = SpeechRecognizer(sampleRate: 8000);

  // 启动识别流程
  recognizer.startRecognition(
    onResult: (text) => print('识别结果: $text'), // 实时结果回调
    onCompleted: () => print('识别完成'), // 完成通知
    onError: (error) => print('发生错误: $error'), // 错误处理
  );
}
