# Native-first iOS client

This directory contains the UIKit application and its native transport. The app entry point is in `MainViewController.swift`; `HarnessRuntime.swift` owns the URLSession JSON-RPC and Remote Mux state coordinator. `HarnessWire.swift` is the production Foundation-only wire layer shared by the app target and the Swift protocol tests.

The client does not embed a web renderer. Optional server-declared `dsh-native-ui/1` surfaces are accepted only as a constrained component tree; absence of that declaration is shown as an honest unavailable state.

See the repository [README](../README.md) and [completion report](../docs/native-completion-report.md) for supported boundaries and verification evidence.
