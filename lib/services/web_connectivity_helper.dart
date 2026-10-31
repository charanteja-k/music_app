import 'web_connectivity_helper_stub.dart'
    if (dart.library.js_interop) 'web_connectivity_helper_web.dart'
    as helper;

/// Returns the browser's native online status (Web only, returns true on Native).
bool isWebOnline() => helper.isWebOnline();

/// Hooks into browser online/offline events (Web only, no-op on Native).
void setupWebConnectivityListeners(void Function(bool isOnline) onChange) =>
    helper.setupWebConnectivityListeners(onChange);
