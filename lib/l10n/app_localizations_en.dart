// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Medical Transaction App';

  @override
  String get startRecording => 'Start Recording';

  @override
  String get stopRecording => 'Stop Recording';

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Resume';

  @override
  String get recording => 'Recording';

  @override
  String get paused => 'Paused';

  @override
  String get patients => 'Patients';

  @override
  String get addPatient => 'Add Patient';

  @override
  String get settings => 'Settings';

  @override
  String get theme => 'Theme';

  @override
  String get language => 'Language';

  @override
  String get darkMode => 'Dark Mode';

  @override
  String get lightMode => 'Light Mode';

  @override
  String get systemMode => 'System Default';

  @override
  String get english => 'English';

  @override
  String get hindi => 'Hindi';

  @override
  String get patientName => 'Patient Name';

  @override
  String get phoneNumber => 'Phone Number';

  @override
  String get email => 'Email';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get selectPatient => 'Select Patient';

  @override
  String get noPatientSelected => 'No Patient Selected';

  @override
  String get duration => 'Duration';

  @override
  String get audioLevel => 'Audio Level';

  @override
  String get uploading => 'Uploading';

  @override
  String get uploaded => 'Uploaded';

  @override
  String get failed => 'Failed';

  @override
  String get recordings => 'Recordings';

  @override
  String get sessionDetails => 'Session Details';

  @override
  String get recordingStarted => 'Recording started';

  @override
  String get recordingStoppedSaved => 'Recording stopped and saved';

  @override
  String get startingRecording => 'Starting recording...';

  @override
  String get stoppingRecording => 'Stopping recording...';

  @override
  String get errorStartingRecording => 'Error starting recording';

  @override
  String get errorStoppingRecording => 'Error stopping recording';

  @override
  String get retry => 'Retry';

  @override
  String get goAheadListening => 'Go ahead. I\'m listening.';

  @override
  String get listening => 'Listening...';

  @override
  String get medicalTranscription => 'Medical Transcription';

  @override
  String get tapToBeginSession =>
      'Tap to begin a new medical transcription session';

  @override
  String get quickActions => 'Quick Actions';

  @override
  String get sessionInformation => 'Session Information';

  @override
  String get transcript => 'Transcript';

  @override
  String get sessionId => 'Session ID';

  @override
  String get date => 'Date';

  @override
  String get startTime => 'Start Time';

  @override
  String get endTime => 'End Time';

  @override
  String get noPatient => 'No Patient';

  @override
  String get recordingSession => 'Recording Session';

  @override
  String get headsetConnected => 'Headset Connected';

  @override
  String get deviceMic => 'Device Mic';

  @override
  String get gainControl => 'Gain Control';

  @override
  String get liveTranscription => 'Live transcription';

  @override
  String get listeningForSpeech => 'Listening for speech';

  @override
  String get tapToStartInstructions =>
      'Tap the button below to start recording';

  @override
  String get listeningToYou => 'Listening to You..';

  @override
  String get tapToPauseLongPressStop => 'Tap to pause • Long press to stop';

  @override
  String get transcriptReady => 'TRANSCRIPT: READY';

  @override
  String get unknown => 'Unknown';

  @override
  String get errorLoadingSessions => 'Error loading sessions';

  @override
  String patientCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count patients',
      one: '1 patient',
      zero: 'No patients',
    );
    return '$_temp0';
  }

  @override
  String recordingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recordings',
      one: '1 recording',
      zero: 'No recordings',
    );
    return '$_temp0';
  }
}
