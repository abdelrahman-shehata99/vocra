<p align="center">
  <a href="https://www.vocra.cloud">
    <img src="https://raw.githubusercontent.com/abdelrahman-shehata99/vocra/main/assets/branding/vocra-logo.svg" height="40" alt="Vocra">
  </a>
</p>

# vocra_flutter example

A runnable demo of [`vocra_flutter`](../): a key-entry screen (enter your Groq
and Deepgram keys, with a "Test keys" check) and a conversation screen with a
mic toggle, live transcript, turn-state indicator, and latency readout.

## Run

This example is a workspace member, so run it from a clone of the repo:

```sh
cd packages/vocra_flutter/example
flutter run
```

You'll need a device or simulator and your own
[Groq](https://console.groq.com) + [Deepgram](https://console.deepgram.com) API
keys (entered on the first screen). Half-duplex is the default; full-duplex
requires native echo cancellation on a physical device.
