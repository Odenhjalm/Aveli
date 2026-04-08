# Flutter integration test investigation

Command
- RUN_FLUTTER_INTEGRATION=1 ./ops/verify_all.sh

Observed
- Backend tests complete (~10 minutes), then Flutter unit tests run, followed by integration tests on the `linux` device.
- `frontend/integration_test/host_participant_flow_test.dart` builds the Linux bundle and passes.
- `frontend/integration_test/livekit_participant_flow_test.dart` stays in the "loading/Building Linux application..." phase for over a minute and did not complete before the 20-minute overall timeout; no explicit test failure surfaced.
- `flutter_linux.log` contains "No pubspec.yaml file found", implying a prior run executed Flutter from the wrong working directory.

Likely causes
- Integration tests are executed per file (see `ops/verify_all.sh`), which triggers a Linux build for each test file; total runtime is long and can exceed CI timeouts.
- Mis-invocation from the repo root (instead of `frontend/`) can cause immediate Linux-runner failures.

Recommendations (no fixes yet)
1. Run the LiveKit integration test in isolation from `frontend/` to confirm whether it hangs or simply needs more build time:
   `flutter test integration_test/livekit_participant_flow_test.dart -d linux`
2. Evaluate consolidating integration tests into a single invocation or shared build to avoid repeated Linux builds.
3. Ensure CI runs Flutter commands with `cwd=frontend` to avoid the "No pubspec.yaml" failure.
4. If `livekit_participant_flow_test.dart` still hangs, add targeted diagnostics around the specific pump/await points to identify the wait (avoid blind delays).
