# mock-sequencer

A standalone mock sequencer WebSocket server for local development and testing.

## Features

- **WebSocket Proxy:** Forwards messages from a remote sequencer or test node to local clients.
- **Message Manipulation:** Supports skipping, reordering, and oversizing messages to simulate malicious or faulty sequencer behavior.
- **HTTP Control API:** Dynamically control sequencer behavior via simple REST endpoints.

## Usage

Check the `regression/test_with_malicious_sequencer.bash` for usage.
