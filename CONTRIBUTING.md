# Contributing to Tabbed

## Prerequisites

- **macOS 13.0+**
- **Xcode** (includes `xcodebuild` and the Swift toolchain) — install from the Mac App Store
- **XcodeGen** — generates the Xcode project from `project.yml`
  ```sh
  brew install xcodegen
  ```

## Build and Run

```sh
./buildandrun.sh
```

Grant Accessibility permissions when prompted (System Settings > Privacy & Security > Accessibility). Note: you will need to re-grant permissions after each rebuild.

## Running Tests

```sh
./run.sh
```
