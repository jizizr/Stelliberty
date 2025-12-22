import 'dart:io';
import 'dart:convert';

// 运行一个进程并等待其完成
Future<void> runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  bool allowNonZeroExit = false,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
  );

  final exitCode = await process.exitCode;
  if (exitCode != 0 && !allowNonZeroExit) {
    throw Exception(
      '命令 "$executable ${arguments.join(' ')}" 执行失败，退出码: $exitCode',
    );
  }
}

// 运行命令并捕获输出
Future<ProcessResult> runProcessWithOutput(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  String? stdinData,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );

  // 如果需要输入数据（如 sudo 密码）
  if (stdinData != null) {
    process.stdin.writeln(stdinData);
    await process.stdin.close();
  }

  final stdout = await process.stdout.transform(utf8.decoder).join();
  final stderr = await process.stderr.transform(utf8.decoder).join();
  final exitCode = await process.exitCode;

  return ProcessResult(process.pid, exitCode, stdout, stderr);
}
