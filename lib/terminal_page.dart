import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:xterm/xterm.dart';

import 'terminal_controller.dart';
import 'terminal_theme.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final HomeController controller = Get.put(HomeController());
  final ManjaroTerminalTheme terminalTheme = ManjaroTerminalTheme();

  bool visible = kDebugMode;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor:
          visible ? terminalTheme.background : colorScheme.surface,
      body: SafeArea(
        child: PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, result) {
            final pty = controller.pseudoTerminal;

            if (pty != null) {
              try {
                pty.writeString('\x03');
              } catch (_) {}
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              setState(() {
                visible = !visible;
              });
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Visibility(
                    visible: visible,
                    maintainState: true,
                    child: TerminalView(
                      controller.terminal,
                      readOnly: false,
                      backgroundOpacity: 1,
                      theme: terminalTheme,
                    ),
                  ),
                ),
                Center(
                  child: Material(
                    borderRadius: BorderRadius.circular(12.0),
                    color: colorScheme.surface,
                    elevation: 3,
                    child: SizedBox(
                      width: 300.0,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 28.0,
                              height: 28.0,
                              child: CircularProgressIndicator(
                                strokeWidth: 3.0,
                              ),
                            ),
                            const SizedBox(height: 12.0),
                            GetBuilder<HomeController>(
                              builder: (controller) {
                                final double progress =
                                    controller.progress.clamp(0.0, 1.0);

                                return Column(
                                  children: [
                                    ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(3.0),
                                      child: SizedBox(
                                        height: 5.0,
                                        child: LinearProgressIndicator(
                                          value: progress,
                                          backgroundColor:
                                              colorScheme.primary.withOpacity(
                                            0.2,
                                          ),
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8.0),
                                    Text(
                                      controller.currentProgress.trim(),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12.0,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
        
