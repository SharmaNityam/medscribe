import 'package:get_it/get_it.dart';
import '../repositories/api_repository.dart';
import '../repositories/local_storage_repository.dart';
import '../services/audio_recorder_service.dart';
import '../services/session_service.dart';
import '../services/upload_service.dart';
import '../services/interruption_handler.dart';
import '../services/transcription_service.dart';

final GetIt getIt = GetIt.instance;

void setupServiceLocator() {
  if (getIt.isRegistered<ApiRepository>()) return;

  getIt
    ..registerLazySingleton<ApiRepository>(() => ApiRepository())
    ..registerLazySingleton<LocalStorageRepository>(() => LocalStorageRepository())
    ..registerLazySingleton<AudioRecorderService>(
      () => AudioRecorderService(),
      dispose: (service) => service.dispose(),
    )
    ..registerLazySingleton<SessionService>(() => SessionService(
          apiRepository: getIt<ApiRepository>(),
          localStorage: getIt<LocalStorageRepository>(),
        ))
    ..registerLazySingleton<UploadService>(
      () => UploadService(
        apiRepository: getIt<ApiRepository>(),
        localStorage: getIt<LocalStorageRepository>(),
        sessionService: getIt<SessionService>(),
      ),
      dispose: (service) => service.dispose(),
    )
    ..registerLazySingleton<TranscriptionService>(
      () => TranscriptionService(),
      dispose: (service) => service.dispose(),
    )
    ..registerLazySingleton<InterruptionHandler>(
      () => InterruptionHandler(
        audioRecorder: getIt<AudioRecorderService>(),
        sessionService: getIt<SessionService>(),
        uploadService: getIt<UploadService>(),
        transcriptionService: getIt<TranscriptionService>(),
      ),
      dispose: (handler) => handler.dispose(),
    );
}
