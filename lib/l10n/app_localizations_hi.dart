// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'मेडिकल ट्रांजैक्शन ऐप';

  @override
  String get startRecording => 'रिकॉर्डिंग शुरू करें';

  @override
  String get stopRecording => 'रिकॉर्डिंग रोकें';

  @override
  String get pause => 'रोकें';

  @override
  String get resume => 'जारी रखें';

  @override
  String get recording => 'रिकॉर्डिंग';

  @override
  String get paused => 'रोका गया';

  @override
  String get patients => 'मरीज़';

  @override
  String get addPatient => 'मरीज़ जोड़ें';

  @override
  String get settings => 'सेटिंग्स';

  @override
  String get theme => 'थीम';

  @override
  String get language => 'भाषा';

  @override
  String get darkMode => 'डार्क मोड';

  @override
  String get lightMode => 'लाइट मोड';

  @override
  String get systemMode => 'सिस्टम डिफॉल्ट';

  @override
  String get english => 'अंग्रेजी';

  @override
  String get hindi => 'हिंदी';

  @override
  String get patientName => 'मरीज़ का नाम';

  @override
  String get phoneNumber => 'फोन नंबर';

  @override
  String get email => 'ईमेल';

  @override
  String get save => 'सहेजें';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get selectPatient => 'मरीज़ चुनें';

  @override
  String get noPatientSelected => 'कोई मरीज़ नहीं चुना गया';

  @override
  String get duration => 'अवधि';

  @override
  String get audioLevel => 'ऑडियो स्तर';

  @override
  String get uploading => 'अपलोड हो रहा है';

  @override
  String get uploaded => 'अपलोड हो गया';

  @override
  String get failed => 'असफल';

  @override
  String get recordings => 'रिकॉर्डिंग्स';

  @override
  String get sessionDetails => 'सत्र विवरण';

  @override
  String get recordingStarted => 'रिकॉर्डिंग शुरू हो गई';

  @override
  String get recordingStoppedSaved => 'रिकॉर्डिंग रोक दी गई और सहेजी गई';

  @override
  String get startingRecording => 'रिकॉर्डिंग शुरू हो रही है...';

  @override
  String get stoppingRecording => 'रिकॉर्डिंग रोकी जा रही है...';

  @override
  String get errorStartingRecording => 'रिकॉर्डिंग शुरू करने में त्रुटि';

  @override
  String get errorStoppingRecording => 'रिकॉर्डिंग रोकने में त्रुटि';

  @override
  String get retry => 'पुनः प्रयास करें';

  @override
  String get goAheadListening => 'आगे बढ़ें। मैं सुन रहा हूं।';

  @override
  String get listening => 'सुन रहे हैं...';

  @override
  String get medicalTranscription => 'चिकित्सा प्रतिलेखन';

  @override
  String get tapToBeginSession =>
      'एक नया चिकित्सा प्रतिलेखन सत्र शुरू करने के लिए टैप करें';

  @override
  String get quickActions => 'त्वरित कार्य';

  @override
  String get sessionInformation => 'सत्र जानकारी';

  @override
  String get transcript => 'प्रतिलेख';

  @override
  String get sessionId => 'सत्र आईडी';

  @override
  String get date => 'तारीख';

  @override
  String get startTime => 'शुरुआती समय';

  @override
  String get endTime => 'समाप्ति समय';

  @override
  String get noPatient => 'कोई मरीज़ नहीं';

  @override
  String get recordingSession => 'रिकॉर्डिंग सत्र';

  @override
  String get headsetConnected => 'हेडसेट जुड़ा हुआ';

  @override
  String get deviceMic => 'डिवाइस माइक';

  @override
  String get gainControl => 'गेन नियंत्रण';

  @override
  String get liveTranscription => 'लाइव प्रतिलेखन';

  @override
  String get listeningForSpeech => 'भाषण सुन रहे हैं';

  @override
  String get tapToStartInstructions =>
      'रिकॉर्डिंग शुरू करने के लिए नीचे दिए गए बटन पर टैप करें';

  @override
  String get listeningToYou => 'आपको सुन रहे हैं..';

  @override
  String get tapToPauseLongPressStop =>
      'रोकने के लिए टैप करें • रोकने के लिए लंबे समय तक दबाएं';

  @override
  String get transcriptReady => 'प्रतिलेख: तैयार';

  @override
  String get unknown => 'अज्ञात';

  @override
  String get errorLoadingSessions => 'सत्र लोड करने में त्रुटि';

  @override
  String patientCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count मरीज़',
      one: '1 मरीज़',
      zero: 'कोई मरीज़ नहीं',
    );
    return '$_temp0';
  }

  @override
  String recordingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count रिकॉर्डिंग्स',
      one: '1 रिकॉर्डिंग',
      zero: 'कोई रिकॉर्डिंग नहीं',
    );
    return '$_temp0';
  }
}
