import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import 'package:settings/settings.dart';
import 'package:xterm/xterm.dart';

import 'config.dart';
import 'generated/l10n.dart';
import 'script.dart';
import 'utils.dart';

class HomeController extends GetxController {
  bool vsCodeStaring = false;

  SettingNode privacySetting = 'privacy'.setting;

  Pty? pseudoTerminal;

  late Terminal terminal = Terminal(
    maxLines: 10000,
    onResize: (width, height, pixelWidth, pixelHeight) {
      pseudoTerminal?.resize(height, width);
    },
    onOutput: (data) {
      pseudoTerminal?.writeString(data);
    },
  );

  bool webviewHasOpen = false;

  File progressFile = File('${RuntimeEnvir.tmpPath}/progress');

  File progressDesFile = File(
    '${RuntimeEnvir.tmpPath}/progress_des',
  );

  double progress = 0.0;

  double step = 17;

  String currentProgress = '';

  // 进度 +1
  // Progress +1
  void bumpProgress() {
    try {
      int current = 0;

      if (progressFile.existsSync()) {
        final content = progressFile.readAsStringSync().trim();

        if (content.isNotEmpty) {
          current = int.tryParse(content) ?? 0;
        }
      } else {
        progressFile.createSync(recursive: true);
      }

      progressFile.writeAsStringSync('${current + 1}');

      // 不再只依赖文件监听器刷新 UI。
      progress = ((current + 1) / step).clamp(0.0, 1.0);
    } catch (e) {
      try {
        progressFile.writeAsStringSync('1');
      } catch (_) {}

      progress = 1 / step;
    }

    update();
  }

  // 监听输出，当输出中包含启动成功的标志时，启动 Code Server
  // Listen for output and start the Code Server when the success flag is detected
  Future<void> vsCodeStartWhenSuccessBind() async {
    terminal.writeProgress(
      '${S.current.listen_vscode_start}...',
    );

    final Completer completer = Completer();

    Utf8Decoder decoder = const Utf8Decoder(
      allowMalformed: true,
    );

    pseudoTerminal!
        .output
        .cast<List<int>>()
        .transform(decoder)
        .listen((event) async {
      if (event.contains(
        'http://0.0.0.0:${Config.port}',
      )) {
        Log.e(event);

        if (!completer.isCompleted) {
          completer.complete();
        }
      }

      if (event.contains('already')) {
        Log.e(event);

        if (!completer.isCompleted) {
          completer.complete();
        }
      }

      terminal.write(event);
    });

    await completer.future;

    bumpProgress();

    await Future.delayed(
      const Duration(milliseconds: 100),
    );

    webviewHasOpen = true;

    openWebView();

    Future.delayed(
      const Duration(milliseconds: 2000),
      () {
        vsCodeStaring = false;
        update();
      },
    );
  }

  // 初始化环境，将动态库中的文件链接到数据目录
  // Init environment and link files from the dynamic library to the data directory
  Future<void> initEnvir() async {
    List<String> androidFiles = [
      'libbash.so',
      'libbusybox.so',
      'liblibtalloc.so.2.so',
      'libloader.so',
      'libproot.so',
      'libsudo.so',
    ];

    String libPath = await getLibPath();

    Log.i('libPath -> $libPath');

    for (int i = 0; i < androidFiles.length; i++) {
      // when android target sdk > 28
      // cannot execute file in /data/data/com.xxx/files/usr/bin
      // so we need create a link to /data/data/com.xxx/files/usr/bin

      final sourcePath = '$libPath/${androidFiles[i]}';

      String fileName = androidFiles[i].replaceAll(
        RegExp('^lib|\\.so\$'),
        '',
      );

      String filePath =
          '${RuntimeEnvir.binPath}/$fileName';

      // custom path, termux-api will invoke
      File file = File(filePath);

      FileSystemEntityType type =
          await FileSystemEntity.type(filePath);

      Log.i('$fileName type -> $type');

      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.link) {
        // old version adb is plain file
        Log.i(
          'find plain file -> $fileName, delete it',
        );

        await file.delete();
      }

      Link link = Link(filePath);

      if (link.existsSync()) {
        link.deleteSync();
      }

      try {
        Log.i(
          'create link -> $fileName ${link.path}',
        );

        link.createSync(sourcePath);
      } catch (e) {
        Log.e(
          'installAdbToEnvir error -> $e',
        );
      }
    }
  }

  // 同步当前进度
  // Sync the current progress
  void syncProgress() {
    progressFile.createSync(recursive: true);

    progressFile.writeAsStringSync('0');

    progressFile
        .watch(events: FileSystemEvent.all)
        .listen((event) async {
      if (event.type == FileSystemEvent.modify) {
        String content =
            await progressFile.readAsString();

        Log.e('content -> $content');

        if (content.isEmpty) {
          return;
        }

        progress = int.parse(content) / step;

        Log.e('progress -> $progress');

        update();
      }
    });

    progressDesFile.createSync(recursive: true);

    progressDesFile.writeAsStringSync('');

    progressDesFile
        .watch(events: FileSystemEvent.all)
        .listen((event) async {
      if (event.type == FileSystemEvent.modify) {
        String content =
            await progressDesFile.readAsString();

        currentProgress = content;

        update();
      }
    });
  }

  // 创建 busybox 的软连接，来确保 proot-distro 会用到的命令正常运行
  // create busybox symlinks, to ensure proot-distro can use the commands normally
  void createBusyboxLink() {
    try {
      List<String> links = [
        ...[
          'awk',
          'ash',
          'basename',
          'bzip2',
          'curl',
          'cp',
          'chmod',
          'cut',
          'cat',
          'du',
          'dd',
          'find',
          'grep',
          'gzip',
        ],
        ...[
          'hexdump',
          'head',
          'id',
          'lscpu',
          'mkdir',
          'realpath',
          'rm',
          'sed',
          'stat',
          'sh',
          'tr',
          'tar',
          'uname',
          'xargs',
          'xz',
          'xxd',
        ],
      ];

      for (String linkName in links) {
        Link link = Link(
          '${RuntimeEnvir.binPath}/$linkName',
        );

        if (!link.existsSync()) {
          link.createSync(
            '${RuntimeEnvir.binPath}/busybox',
          );
        }
      }

      Link link = Link(
        '${RuntimeEnvir.binPath}/file',
      );

      if (link.existsSync()) {
        link.deleteSync();
      }

      link.createSync('/system/bin/file');
    } catch (e) {
      Log.e(
        'Create link failed -> $e',
      );
    }
  }

  Future<void> loadCodeVersion() async {
    if (GetPlatform.isAndroid) {
      PermissionStatus status =
          await Permission.manageExternalStorage.request();

      Log.i('status -> $status');

      if (!status.isGranted) {
        return;
      }
    }

    File file = File('/sdcard/code_version');

    try {
      if (!file.existsSync()) {
        file.createSync();

        file.writeAsStringSync(
          Config.defaultCodeServerVersion,
        );
      }
    } catch (e) {
      Log.e(
        'Create code_version file failed -> $e',
      );
    }

    if (file.existsSync()) {
      Config.codeServerVersion =
          file.readAsStringSync();
    }

    if (Config.codeServerVersion.isEmpty) {
      Config.codeServerVersion =
          Config.defaultCodeServerVersion;
    }
  }

  bool get useCustomCodeServer =>
      Config.codeServerVersion !=
      Config.defaultCodeServerVersion;

  void setProgress(String description) {
    currentProgress = description;

    terminal.writeProgress(
      currentProgress,
    );

    // 关键修复：立即刷新 GetX 页面。
    update();
  }

  Future<void> loadCodeServer() async {
    setProgress(
      '[1] Checking storage permission...',
    );

    await loadCodeVersion();

    // loadCodeVersion() 原来在拒绝权限后只是 return，
    // 但 loadCodeServer() 仍会继续运行。
    // 这里必须真正停止整个初始化过程。
    if (GetPlatform.isAndroid) {
      final status =
          await Permission.manageExternalStorage.status;

      if (!status.isGranted) {
        setProgress(
          'Please enable "All files access" permission, then reopen Code FA.',
        );

        return;
      }
    }

    bumpProgress();

    // 创建相关文件夹
    // Create related folders
    setProgress(
      '[2] Creating runtime directories...',
    );

    Directory(
      RuntimeEnvir.tmpPath,
    ).createSync(recursive: true);

    Directory(
      RuntimeEnvir.homePath,
    ).createSync(recursive: true);

    Directory(
      RuntimeEnvir.binPath,
    ).createSync(recursive: true);

    bumpProgress();

    setProgress(
      '[3] Initializing native environment...',
    );

    await initEnvir();

    bumpProgress();

    // -
    setProgress(
      '${S.current.create_terminal_obj}...',
    );

    pseudoTerminal = createPTY(
      rows: terminal.viewHeight,
      columns: terminal.viewWidth,
    );

    bumpProgress();

    // -
    terminal.writeProgress(
      '${S.current.current_code_version}:'
      '${Config.codeServerVersion} '
      '[${useCustomCodeServer ? 'custom' : ''}]',
    );

    setProgress(
      '${S.current.copy_proot_distro}...',
    );

    await AssetsUtils.copyAssetToPath(
      'assets/proot-distro.zip',
      '${RuntimeEnvir.homePath}/proot-distro.zip',
    );

    bumpProgress();

    // -
    setProgress(
      '${S.current.copy_ubuntu}...',
    );

    await AssetsUtils.copyAssetToPath(
      'assets/${Config.ubuntuFileName}',
      '${RuntimeEnvir.homePath}/${Config.ubuntuFileName}',
    );

    bumpProgress();

    // -
    setProgress(
      '${S.current.create_busybox_symlink}...',
    );

    createBusyboxLink();

    bumpProgress();

    // -
    String codeServerName =
        'code-server-${Config.codeServerVersion}-linux-arm64.tar.gz';

    String sourcePath = useCustomCodeServer
        ? '/sdcard/$codeServerName'
        : 'assets/$codeServerName';

    setProgress(
      '${S.current.copy_code_server('[$sourcePath]')} '
      '${RuntimeEnvir.tmpPath}...',
    );

    try {
      if (useCustomCodeServer) {
        File codeServerOnSdcard =
            File(sourcePath);

        File targetFile = File(
          '${RuntimeEnvir.tmpPath}/$codeServerName',
        );

        if (targetFile.existsSync() &&
            targetFile.lengthSync() ==
                codeServerOnSdcard.lengthSync()) {
          Log.i(
            'code server already copied to tmp, skip',
          );
        } else {
          if (targetFile.existsSync()) {
            targetFile.deleteSync();
          }

          await codeServerOnSdcard.copy(
            targetFile.path,
          );
        }
      } else {
        await AssetsUtils.copyAssetToPath(
          sourcePath,
          '${RuntimeEnvir.tmpPath}/$codeServerName',
        );
      }
    } catch (e) {
      Log.e(
        'Copy code server failed -> $e',
      );

      terminal.write(
        'Copy code server failed -> $e',
      );

      setProgress(
        'STARTUP ERROR: Copy code server failed -> $e',
      );

      return;
    }

    // -
    final codeServerPath =
        '${RuntimeEnvir.tmpPath}/$codeServerName';

    setProgress(
      '${S.current.gen_script}...',
    );

    String fixHardLinkShell = '';

    try {
      Map<String, String> hardLinks =
          await getHardLinkMap(
        codeServerPath,
      );

      fixHardLinkShell =
          genFixCodeServerHardLinkShell(
        hardLinks,
      );

      Log.i(
        'fixHardLinkShell -> $fixHardLinkShell',
      );
    } catch (e) {
      terminal.write(
        'Get hard link failed, '
        'will cause code-server start failed -> '
        '$e\r\n',
      );

      setProgress(
        'STARTUP ERROR: Get hard link failed -> $e',
      );

      return;
    }

    bumpProgress();

    bumpProgress();

    // -
    vsCodeStartWhenSuccessBind();

    bumpProgress();

    File(
      '${RuntimeEnvir.homePath}/common.sh',
    ).writeAsStringSync(
      '$commonScript\n$fixHardLinkShell',
    );

    bumpProgress();

    if (pseudoTerminal == null) {
      throw Exception(
        'PTY is null before starting code-server',
      );
    }

    setProgress(
      '[4] Starting code-server...',
    );

    startVsCode(
      pseudoTerminal!,
    );
  }

  Future<void> startVsCode(
    Pty pseudoTerminal,
  ) async {
    vsCodeStaring = true;

    update();

    pseudoTerminal.writeString(
      'source ${RuntimeEnvir.homePath}/common.sh\n'
      'start_vs_code\n',
    );

    // pseudoTerminal.writeString('bash\n');
  }

  @override
  void onInit() {
    super.onInit();

    // 为 Google Play 上架做准备
    // For Google Play
    Future.delayed(
      Duration.zero,
      () async {
        try {
          if (privacySetting.get() == null) {
            await Get.to(
              PrivacyAgreePage(
                onAgreeTap: () {
                  privacySetting.set(true);
                  Get.back();
                },
              ),
            );
          }

          syncProgress();

          await loadCodeServer();
        } catch (e, st) {
          currentProgress =
              'STARTUP ERROR: $e';

          Log.e(currentProgress);

          Log.e(
            st.toString(),
          );

          update();

          try {
            terminal.write(
              '\r\n$currentProgress\r\n'
              '$st\r\n',
            );
          } catch (_) {}
        }
      },
    );
  }
}
