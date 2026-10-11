export 'test_env_detector_io.dart'
    if (dart.library.js_interop) 'test_env_detector_web.dart'
    if (dart.library.html) 'test_env_detector_web.dart';
