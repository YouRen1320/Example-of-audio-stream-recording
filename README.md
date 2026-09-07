# Flutter 实时音频流录制示例

这是一个把麦克风 PCM 音频流通过 WebSocket 发送到阿里云百炼实时语音识别接口的 Flutter 示例。应用不会主动把录音写入本地文件，但音频会发送给第三方云服务处理。

## 当前状态

- 已实际验证：Windows。
- 尚未实际验证：macOS、Android、iOS、Linux、Web。
- macOS 工程已声明麦克风权限；其他平台仍需按 `record` 插件和平台要求逐项配置、构建与真机验收。
- 当前仅适合作为本地学习示例，不是生产级语音识别客户端。

## 本地运行

```bash
flutter doctor
flutter pub get
cp .env.example .env
flutter run -d windows
```

然后在本地 `.env` 中填写你自己的 `DASHSCOPE_API_KEY`。`.env` 已被 Git 忽略；不要把真实 Key 放进提交、Issue、日志或截图。

## 数据与安全边界

- `flutter_dotenv` 会把 `.env` 作为客户端资源打包，客户端中的 Key 可以被提取。生产环境应由受控后端代持云服务凭据，并为用户签发短期、最小权限令牌。
- 录音虽然不保存为本地文件，但会离开设备并发送到阿里云百炼；使用前需向录音参与者明确告知并取得必要同意。
- 当前实现没有离线缓存、断点续传、流量限制、内容脱敏或数据删除流程。
- 调试日志只保留连接状态和数据块大小，不输出完整服务端消息或识别文本。

## 主要依赖

- Flutter / Dart
- `record` 6.x：采集 PCM 音频流
- `web_socket_channel`：连接实时识别 WebSocket
- `flutter_dotenv`：仅用于本地示例配置

## 许可证

当前仓库未声明开源许可证。在补充许可证前，默认不授予复制、修改或再发布权限。
