/// Web implementation of test environment detection.
/// Never accesses dart:io or Platform to prevent Web UnsupportedOperation crashes.
bool isFlutterTestEnvironment() => false;
