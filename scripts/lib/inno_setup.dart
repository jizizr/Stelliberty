import 'dart:io';
import 'package:path/path.dart' as p;
import 'common.dart';

// 生成 Inno Setup 配置（内嵌模板，移除简体中文支持）
String _generateInnoSetupConfig({
  required String appName,
  required String version,
  required String appExeName,
  required String outputDir,
  required String outputFileName,
  required String sourceDir,
  required String archMode,
}) {
  // 生成标准 GUID 格式（使用固定的应用专属 GUID）
  // 注意：每个应用应该有唯一的 GUID，这里使用应用名生成
  final appNameHash = appName.hashCode
      .abs()
      .toRadixString(16)
      .padLeft(8, '0')
      .toUpperCase();
  final guid = 'A1B2C3D4-E5F6-7890-$appNameHash-123456789ABC';

  // Publisher 名称使用应用名称（首字母大写）
  final publisher = appName;

  return '''
; Inno Setup 配置文件 - 由 build.dart 自动生成

#define MyAppName "$appName"
#define MyAppVersion "$version"
#define MyAppPublisher "$publisher"
#define MyAppExeName "$appExeName"
#define MyAppPackageName "${appName.toLowerCase()}"

[Setup]
; 应用程序基本信息
AppId={{$guid}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppCopyright=Copyright (C) 2025 {#MyAppPublisher}

; 安装目录
; 默认使用用户本地目录（推荐，避免写入权限问题）
; Inno Setup 安装包统一要求管理员权限（用于杀死进程和服务管理）
; 便携式部署请使用 ZIP 打包方式
DefaultDirName={localappdata}\\Programs\\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
DisableProgramGroupPage=yes

; 输出配置
OutputDir=$outputDir
OutputBaseFilename=$outputFileName

; 压缩配置
Compression=lzma2/max
SolidCompression=yes

; 安装界面配置
WizardStyle=modern

; 架构配置
$archMode

; 权限配置
; admin: 强制要求管理员权限（用于 taskkill 杀死进程和 sc 管理服务）
; 注意：不添加 PrivilegesRequiredOverridesAllowed，始终强制管理员权限
PrivilegesRequired=admin

; 卸载配置
UninstallDisplayIcon={app}\\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
UninstallFilesDir={app}\\uninstall

; 其他配置
DisableWelcomePage=no
DisableDirPage=no
DisableReadyPage=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "$sourceDir\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"
Name: "{group}\\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; 卸载时删除运行时生成的数据文件夹
Type: filesandordirs; Name: "{app}\\data"

[Code]
var
  ResetDirButton: TButton;
  ClearAppDataCheckbox: Boolean;
  UninstallDataForm: TSetupForm;

// 获取 Windows 系统盘符（如 C:）
function GetSystemDrive(): String;
var
  WinDir: String;
begin
  WinDir := ExpandConstant('{sys}');  // 例如 C:\Windows\System32
  Result := Copy(WinDir, 1, 2);       // 提取 C:
end;

// 检查是否为系统盘路径
function IsSystemDrivePath(Path: String): Boolean;
var
  SystemDrive: String;
  PathDrive: String;
begin
  SystemDrive := Uppercase(GetSystemDrive());  // C:
  PathDrive := Uppercase(Copy(Path, 1, 2));    // 提取路径的盘符
  Result := (PathDrive = SystemDrive);
end;

// 检查安装路径是否为受保护的系统目录
function IsRestrictedPath(Path: String): Boolean;
var
  UpperPath: String;
  WinDir: String;
  LocalAppData: String;
  AllowedPath: String;
begin
  Result := False;
  UpperPath := Uppercase(Path);
  
  // 策略：系统盘严格限制，其他盘完全自由
  
  // 如果不在系统盘，允许任意路径（包括 D:\, E:\ 根目录）
  if not IsSystemDrivePath(Path) then
  begin
    Result := False;  // 其他盘不做任何限制
    Exit;
  end;
  
  // 以下规则仅适用于系统盘（通常是 C:）
  
  // 1. 禁止安装到系统盘根目录 (C:\\)
  if (Length(UpperPath) = 3) and (UpperPath[2] = ':') and (UpperPath[3] = '\\') then
  begin
    Result := True;
    Exit;
  end;
  
  // 2. 获取允许的安装目录
  LocalAppData := Uppercase(ExpandConstant('{localappdata}'));  // C:\Users\{用户}\AppData\Local
  
  // 3. 检查是否在 %LOCALAPPDATA%\\Programs 下
  AllowedPath := LocalAppData + '\\PROGRAMS';
  if (Pos(AllowedPath, UpperPath) = 1) then
  begin
    Result := False;  // 允许安装到 %LOCALAPPDATA%\Programs\*
    Exit;
  end;
  
  // 4. 系统盘的其他所有路径都禁止
  Result := True;
end;

// 重置为默认目录按钮点击事件
procedure ResetDirButtonClick(Sender: TObject);
begin
  WizardForm.DirEdit.Text := ExpandConstant('{localappdata}\\Programs\\{#MyAppName}');
end;

// 初始化目录选择页面，添加重置图标按钮
procedure InitializeWizard();
begin
  // 创建重置按钮（图标风格，放在浏览按钮左边）
  ResetDirButton := TButton.Create(WizardForm);
  ResetDirButton.Parent := WizardForm.DirBrowseButton.Parent;
  
  // 位置：浏览按钮左侧
  ResetDirButton.Left := WizardForm.DirBrowseButton.Left - ScaleX(28);
  ResetDirButton.Top := WizardForm.DirBrowseButton.Top;
  
  // 尺寸：小巧的方形图标按钮
  ResetDirButton.Width := ScaleX(23);
  ResetDirButton.Height := WizardForm.DirBrowseButton.Height;
  
  // 样式：重置图标 ↻ (Unicode U+21BB)
  ResetDirButton.Caption := '↻';
  ResetDirButton.OnClick := @ResetDirButtonClick;
  
  // 提示文本
  ResetDirButton.Hint := 'Reset to default installation directory';
  ResetDirButton.ShowHint := True;
end;


// 目录选择验证
function NextButtonClick(CurPageID: Integer): Boolean;
var
  DirPath: String;
begin
  Result := True;
  
  // 在选择目录页面时验证
  if CurPageID = wpSelectDir then
  begin
    DirPath := WizardDirValue;
    
    // 检查是否为受保护路径
    if IsRestrictedPath(DirPath) then
    begin
      MsgBox('Cannot install to this location:' #13#10#13#10 +
             DirPath + #13#10#13#10 +
             'Installation Policy:' #13#10 +
             '• Windows system drive: Only allowed in' #13#10 +
             '  ' + ExpandConstant('{localappdata}') + '\\Programs' #13#10 +
             '• Other drives: No restrictions',
             mbError, MB_OK);
      Result := False;
      Exit;
    end;
  end;
end;

function IsProcessRunning(ProcessName: String): Boolean;
var
  ResultCode: Integer;
  Output: AnsiString;
begin
  Result := False;
  if Exec('cmd.exe', '/c tasklist /FI "IMAGENAME eq ' + ProcessName + '" | findstr /i "' + ProcessName + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    // 如果 findstr 返回 0，说明找到了进程
    if ResultCode = 0 then
      Result := True;
  end;
end;

procedure KillProcess(ProcessName: String);
var
  ResultCode: Integer;
  Retries: Integer;
begin
  // taskkill /F /IM 会终止所有匹配的进程实例
  Exec('cmd.exe', '/c taskkill /F /IM ' + ProcessName, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

  // 等待进程完全停止
  Sleep(500);

  // 重试最多 3 次，确保所有实例都被终止
  Retries := 0;
  while IsProcessRunning(ProcessName) and (Retries < 3) do
  begin
    Sleep(500);
    Exec('cmd.exe', '/c taskkill /F /IM ' + ProcessName, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Retries := Retries + 1;
  end;
end;

function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
  MsgText: String;
  AppRunning: Boolean;
  ClashRunning: Boolean;
begin
  // 检查主程序是否在运行
  AppRunning := CheckForMutexes('Global\\StelliibertyMutex') or IsProcessRunning('{#MyAppExeName}');

  // 检查 clash-core.exe 是否在运行
  ClashRunning := IsProcessRunning('clash-core.exe');

  // 只有在应用或 Clash 运行时才提示
  if AppRunning or ClashRunning then
  begin
    MsgText := '{#MyAppName} or Clash process is currently running.' + #13#10#13#10 +
               'The installer will automatically:' + #13#10 +
               '  • Stop the main application' + #13#10 +
               '  • Stop Clash process' + #13#10#13#10 +
               'Continue with installation?';

    if MsgBox(MsgText, mbConfirmation, MB_YESNO) = IDYES then
    begin
      // 1. 强制停止主程序
      if AppRunning then
      begin
        KillProcess('{#MyAppExeName}');

        // 验证是否成功停止
        if IsProcessRunning('{#MyAppExeName}') then
        begin
          MsgBox('Failed to stop {#MyAppName}.' + #13#10#13#10 + 'Please close it manually and try again.', mbError, MB_OK);
          Result := False;
          Exit;
        end;
      end;

      // 2. 强制停止 Clash 进程
      if ClashRunning then
      begin
        KillProcess('clash-core.exe');

        // 验证是否成功停止
        if IsProcessRunning('clash-core.exe') then
        begin
          MsgBox('Failed to stop Clash process.' + #13#10#13#10 + 'Please stop it manually and try again.', mbError, MB_OK);
          Result := False;
          Exit;
        end;
      end;

      Result := True;
    end
    else
    begin
      Result := False;
    end;
  end
  else
  begin
    // 没有进程在运行，直接继续安装
    Result := True;
  end;
end;

function GetServicePath(): String;
var
  ResultCode: Integer;
  TempFile: String;
  Lines: TArrayOfString;
  I: Integer;
  Line: String;
  Pos1: Integer;
begin
  Result := '';
  
  // 使用临时文件捕获 sc qc 输出
  // 注意：Inno Setup 的 Exec 不支持直接捕获输出到变量，必须使用文件
  TempFile := ExpandConstant('{tmp}') + '\sc_query_stelliberty.txt';
  
  // 查询服务配置
  if Exec('cmd.exe', '/c sc qc StellibertyService > "' + TempFile + '" 2>&1', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    // 读取输出
    if LoadStringsFromFile(TempFile, Lines) then
    begin
      for I := 0 to GetArrayLength(Lines) - 1 do
      begin
        Line := Trim(Lines[I]);
        // 查找 BINARY_PATH_NAME 行
        if Pos('BINARY_PATH_NAME', Line) > 0 then
        begin
          // 提取路径
          Pos1 := Pos(':', Line);
          if Pos1 > 0 then
          begin
            Result := Trim(Copy(Line, Pos1 + 1, Length(Line)));
            // 移除可能的引号
            StringChangeEx(Result, '"', '', True);
            Break;
          end;
        end;
      end;
    end;
  end;
  
  // 清理临时文件
  if FileExists(TempFile) then
    DeleteFile(TempFile);
end;

// 询问用户卸载方式
function AskClearAppData(): Boolean;
var
  MsgText: String;
  ButtonResult: Integer;
begin
  MsgText := 'Please choose uninstall option:' + #13#10#13#10 +
             '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' + #13#10#13#10 +
             '【Clean Uninstall】' + #13#10 +
             'Remove the program AND all user data:' + #13#10 +
             '  • Scheduled tasks' + #13#10 +
             '  • Settings and preferences' + #13#10 +
             '  • Data in: ' + ExpandConstant('{userappdata}\\{#MyAppPackageName}') + #13#10#13#10 +
             '【Standard Uninstall】' + #13#10 +
             'Only remove the program, keep your settings' + #13#10#13#10 +
             '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' + #13#10#13#10 +
             'Click YES for Clean Uninstall' + #13#10 +
             'Click NO for Standard Uninstall' + #13#10 +
             'Click CANCEL to abort uninstallation';
  
  ButtonResult := MsgBox(MsgText, mbConfirmation, MB_YESNOCANCEL or MB_DEFBUTTON2);
  
  if ButtonResult = IDYES then
  begin
    // 干净卸载
    Result := True;
  end
  else if ButtonResult = IDNO then
  begin
    // 直接卸载（标准卸载）
    Result := False;
  end
  else
  begin
    // 取消卸载
    Result := False;
    // 注意：这里不能直接退出，需要在调用处处理
  end;
end;

function InitializeUninstall(): Boolean;
var
  ResultCode: Integer;
  ServicePath: String;
  MsgText: String;
  AppRunning: Boolean;
  ClashRunning: Boolean;
  ButtonResult: Integer;
begin
  // 初始化
  ClearAppDataCheckbox := False;
  
  // 检查主程序和相关进程是否在运行
  AppRunning := CheckForMutexes('Global\\StelliibertyMutex') or IsProcessRunning('{#MyAppExeName}');
  ClashRunning := IsProcessRunning('clash-core.exe');
  
  // 动态查询 Windows 服务路径
  ServicePath := GetServicePath();
  
  // 构建提示信息，直接合并到卸载选项对话框
  MsgText := 'Uninstall {#MyAppName}?' + #13#10#13#10;
  
  if ServicePath <> '' then
  begin
    MsgText := MsgText + 'Windows Service detected at:' + #13#10 + ServicePath + #13#10#13#10;
  end;
  
  MsgText := MsgText + 'The uninstaller will automatically:' + #13#10;
  
  if ServicePath <> '' then
  begin
    MsgText := MsgText +
               '  • Stop and close application' + #13#10 +
               '  • Stop and remove Windows Service' + #13#10 +
               '  • Stop Clash process' + #13#10 +
               '  • Delete service files' + #13#10#13#10;
  end
  else
  begin
    MsgText := MsgText +
               '  • Stop and close application' + #13#10 +
               '  • Stop Clash process' + #13#10#13#10;
  end;
  
  if AppRunning or ClashRunning then
    MsgText := MsgText + 'Note: Active processes will be forcefully terminated.' + #13#10#13#10;
  
  MsgText := MsgText + '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' + #13#10#13#10 +
             '【Clean Uninstall】' + #13#10 +
             'Remove program AND all user data:' + #13#10 +
             '  • Scheduled tasks' + #13#10 +
             '  • Settings and preferences' + #13#10 +
             '  • Data in: ' + ExpandConstant('{userappdata}') + '\\stelliberty' + #13#10#13#10 +
             '【Standard Uninstall】' + #13#10 +
             'Remove program only, keep settings' + #13#10#13#10 +
             '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' + #13#10#13#10 +
             'YES = Clean Uninstall' + #13#10 +
             'NO = Standard Uninstall' + #13#10 +
             'CANCEL = Abort';
  
  // 直接显示三按钮选择对话框
  ButtonResult := MsgBox(MsgText, mbConfirmation, MB_YESNOCANCEL or MB_DEFBUTTON2);
  
  if ButtonResult = IDCANCEL then
  begin
    Result := False;
    Exit;
  end;
  
  // YES = 干净卸载，NO = 标准卸载
  ClearAppDataCheckbox := (ButtonResult = IDYES);
  
  // 强制终止主程序
  if AppRunning then
  begin
    KillProcess('{#MyAppExeName}');
  end;
  
  // 处理 Windows 服务
  if ServicePath <> '' then
  begin
    // 停止服务
    Exec('sc.exe', 'stop StellibertyService', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(1500);
    
    // 删除服务
    Exec('sc.exe', 'delete StellibertyService', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
  
  // 强制停止所有 clash-core.exe 进程
  if ClashRunning then
  begin
    KillProcess('clash-core.exe');
  end;
  
  // 最终验证：确保所有关键进程都已停止
  if IsProcessRunning('{#MyAppExeName}') or IsProcessRunning('clash-core.exe') then
  begin
    MsgBox('Failed to stop all processes.' #13#10#13#10 +
           'Some processes are still running. The uninstaller will continue,' #13#10 +
           'but some files may not be removed.', mbError, MB_OK);
  end;
  
  Result := True;
end;

// 删除计划任务
procedure RemoveScheduledTask();
var
  ResultCode: Integer;
  TaskName: String;
begin
  TaskName := '{#MyAppName}';
  
  // 先检查任务是否存在
  if Exec('cmd.exe', '/c schtasks /query /tn ' + TaskName, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    if ResultCode = 0 then
    begin
      // 任务存在，删除它
      Exec('cmd.exe', '/c schtasks /delete /tn ' + TaskName + ' /f', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;
  end;
end;

// 删除 AppData 文件夹
procedure RemoveAppDataFolder();
var
  AppDataPath: String;
  ResultCode: Integer;
begin
  // 获取 %APPDATA%\{#MyAppPackageName} 路径（Roaming 目录，使用小写包名）
  AppDataPath := ExpandConstant('{userappdata}\\{#MyAppPackageName}');
  
  if DirExists(AppDataPath) then
  begin
    // 使用 cmd 的 rmdir 命令递归删除整个文件夹
    Exec('cmd.exe', '/c rmdir /s /q "' + AppDataPath + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  AppDir: String;
  ServicePath: String;
  ServiceDir: String;
  ShouldClearAppData: Boolean;
begin
  // 卸载完成后，清理服务文件和残留目录
  if CurUninstallStep = usPostUninstall then
  begin
    AppDir := ExpandConstant('{app}');
    
    // 动态获取服务路径
    ServicePath := GetServicePath();
    
    if ServicePath <> '' then
    begin
      // 提取服务目录
      ServiceDir := ExtractFileDir(ServicePath);
      
      // 强制删除服务文件（如果存在）
      if FileExists(ServicePath) then
      begin
        DeleteFile(ServicePath);
      end;
      
      // 尝试删除服务目录
      if DirExists(ServiceDir) then
      begin
        RemoveDir(ServiceDir);
      end;
    end;
    
    // 检查用户是否选择清除应用数据
    if ClearAppDataCheckbox then
    begin
      // 删除计划任务
      RemoveScheduledTask();
      
      // 删除 AppData 文件夹
      RemoveAppDataFolder();
    end;
    
    // 尝试删除安装目录（如果为空）
    RemoveDir(AppDir);
  end;
end;
''';
}

// 使用 Inno Setup 打包为安装程序
Future<void> packInnoSetup({
  required String projectRoot,
  required String sourceDir,
  required String outputPath,
  required String appName,
  required String version,
  required String arch,
}) async {
  if (!Platform.isWindows) {
    throw Exception('Inno Setup 打包仅支持 Windows 平台');
  }

  log('▶️  正在使用 Inno Setup 打包为安装程序...');

  // 检查 Inno Setup 6 是否安装
  final innoSetupPaths = [
    r'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    r'C:\Program Files\Inno Setup 6\ISCC.exe',
  ];

  String? isccPath;
  for (final path in innoSetupPaths) {
    if (await File(path).exists()) {
      isccPath = path;
      break;
    }
  }

  if (isccPath == null) {
    throw Exception(
      '未找到 Inno Setup 编译器 (ISCC.exe)。\n'
      '请运行以下命令安装: dart run scripts/prebuild.dart --installer',
    );
  }

  log('✅ 找到 Inno Setup: $isccPath');

  // 生成 ISS 配置文件
  final appNameCapitalized =
      '${appName.substring(0, 1).toUpperCase()}${appName.substring(1)}';
  // 支持 x64 和 arm64 架构的 Inno Setup 配置
  final archMode = (arch == 'x64' || arch == 'arm64')
      ? 'ArchitecturesInstallIn64BitMode=$arch'
      : '';
  final outputDir = p.dirname(outputPath);
  final outputFileName = p.basenameWithoutExtension(outputPath);

  final issContent = _generateInnoSetupConfig(
    appName: appNameCapitalized,
    version: version,
    appExeName: '$appName.exe',
    outputDir: outputDir,
    outputFileName: outputFileName,
    sourceDir: sourceDir,
    archMode: archMode,
  );

  // 写入临时 ISS 文件
  final issFile = File(p.join(projectRoot, 'build', 'setup.iss'));
  await issFile.parent.create(recursive: true);
  await issFile.writeAsString(issContent);

  log('📝 生成配置文件: ${issFile.path}');

  // 运行 Inno Setup 编译器
  log('🔨 正在编译安装程序...');
  final result = await Process.run(isccPath, [
    issFile.path,
  ], workingDirectory: projectRoot);

  if (result.exitCode != 0) {
    log('❌ Inno Setup 编译失败');
    log(result.stdout);
    log(result.stderr);
    throw Exception('Inno Setup 编译失败');
  }

  // 显示文件大小
  final fileSize = await File(outputPath).length();
  final sizeInMB = (fileSize / (1024 * 1024)).toStringAsFixed(2);
  log('✅ 打包完成: ${p.basename(outputPath)} ($sizeInMB MB)');
}
