import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_transaction_app/core/models/session.dart';
import 'package:medical_transaction_app/features/recording/recording_controller.dart';
import 'package:medical_transaction_app/features/recording/recording_screen.dart';
import 'package:medical_transaction_app/features/settings/theme_language_provider.dart';
import 'package:medical_transaction_app/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeRecordingController extends ChangeNotifier implements RecordingController {
  bool _recording = false;
  bool _paused = false;
  Completer<void>? startGate;
  final List<String> calls = [];

  @override
  bool get isRecording => _recording;

  @override
  bool get isPaused => _paused;

  @override
  double get amplitude => -30;

  @override
  double get gain => 1.0;

  @override
  Duration get duration => const Duration(seconds: 7);

  @override
  String get transcriptionText => '';

  @override
  RecordingSession? get currentSession => null;

  @override
  void setGain(double gain) {}

  @override
  Future<void> startRecording({
    required String userId,
    String? patientId,
    String? patientName,
    String? templateId,
  }) async {
    calls.add('start');
    if (startGate != null) await startGate!.future;
    _recording = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _paused = true;
    notifyListeners();
  }

  @override
  Future<void> resume() async {
    calls.add('resume');
    _paused = false;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    _recording = false;
    _paused = false;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget buildApp(FakeRecordingController controller) {
  return ChangeNotifierProvider(
    create: (_) => ThemeLanguageProvider(),
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChangeNotifierProvider<RecordingController>.value(
                    value: controller,
                    child: const RecordingScreen(userId: 'user_123'),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> openRecordingScreen(WidgetTester tester, FakeRecordingController controller) async {
  await tester.binding.setSurfaceSize(const Size(430, 932));
  await tester.pumpWidget(buildApp(controller));
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Finder get micButton => find.byIcon(Icons.mic);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('idle shows the mic button labelled "Start recording"', (tester) async {
    final controller = FakeRecordingController();
    await openRecordingScreen(tester, controller);

    expect(micButton, findsOneWidget);
    expect(find.bySemanticsLabel('Start recording'), findsOneWidget);
    expect(find.text('Listening to You..'), findsNothing);
  });

  testWidgets('shows a spinner while starting, then the listening state', (tester) async {
    final controller = FakeRecordingController()..startGate = Completer<void>();
    await openRecordingScreen(tester, controller);

    await tester.tap(micButton);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(micButton, findsNothing);

    controller.startGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.calls, ['start']);
    expect(find.text('Listening to You..'), findsOneWidget);
    expect(find.text('00:07'), findsOneWidget);
    expect(find.text('Tap to pause • Long press to stop'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Pause recording')), findsOneWidget);
  });

  testWidgets('tap pauses, tap again resumes', (tester) async {
    final controller = FakeRecordingController();
    await openRecordingScreen(tester, controller);
    await tester.tap(micButton);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Listening to You..'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.isPaused, isTrue);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('00:07'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('^Resume recording')), findsOneWidget);

    await tester.tap(find.text('Paused'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.isPaused, isFalse);
    expect(find.text('Listening to You..'), findsOneWidget);
    expect(controller.calls, ['start', 'pause', 'resume']);
  });

  testWidgets('long press stops the recording and closes the screen', (tester) async {
    final controller = FakeRecordingController();
    await openRecordingScreen(tester, controller);
    await tester.tap(micButton);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.longPress(find.text('Listening to You..'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(controller.calls, ['start', 'stop']);
    expect(controller.isRecording, isFalse);
    expect(find.byType(RecordingScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
