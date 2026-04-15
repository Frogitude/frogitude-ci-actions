# 🐸 FrogitudeCI Actions

Custom GitHub Actions for game engine CI/CD pipelines. Drop-in replacements for GameCI actions — same Docker images (`unityci/editor`), full control over the build process.

## Versioning

All actions use **semantic version tags**. Pin to a major version for stability:

```yaml
- uses: Frogitude/frogitude-ci-actions/unity-build@v1      # recommended
- uses: Frogitude/frogitude-ci-actions/unity-build@v1.2.0   # exact pin
- uses: Frogitude/frogitude-ci-actions/unity-build@main      # bleeding edge
```

| Tag | Meaning |
|-----|---------|
| `@v1` | Latest v1.x.x (stable, recommended) |
| `@v1.2.0` | Exact release — fully reproducible |
| `@main` | Tip of main branch — may break |

## Quick Start (Secrets Wizard Website)

```bash
npm install
npm run secrets-wizard    # opens http://localhost:3001
```

The **GitHub panel** provides one-click setup: validate → sync secrets → push workflow.

## Actions

| Action | Purpose |
|--------|---------|
| [`unity-activate`](#unity-activate) | Activate Unity license (Personal, Pro serial, or License Server) |
| [`unity-test`](#unity-test) | Run Edit-mode, Play-mode, or Standalone tests |
| [`unity-build`](#unity-build) | Build for any target platform |
| [`unity-return-license`](#unity-return-license) | Return Pro/Plus serial license seat |
| [`steam-deploy`](#steam-deploy) | Upload builds to Steamworks |

---

## unity-activate

Activates a Unity license inside Docker and stores it in a shared volume for subsequent steps.
Supports **Personal (.ulf)**, **Pro/Plus (serial)**, and **License Server (floating)** activation.

```yaml
- uses: Frogitude/frogitude-ci-actions/unity-activate@v1
  with:
    unity-version: '6000.0.23f1'
    # Personal license:
    license: ${{ secrets.UNITY_LICENSE }}
    # OR Pro serial:
    # serial: ${{ secrets.UNITY_SERIAL }}
    # email: ${{ secrets.UNITY_EMAIL }}
    # password: ${{ secrets.UNITY_PASSWORD }}
    # OR License Server:
    # licensing-server: ${{ secrets.UNITY_LICENSING_SERVER }}
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `unity-version` | Yes | — | Unity Editor version (e.g. `2022.3.20f1`, `6000.0.23f1`) |
| `license` | No | `''` | Personal .ulf file content |
| `serial` | No | `''` | Pro/Plus serial number |
| `email` | No | `''` | Unity account email (for serial) |
| `password` | No | `''` | Unity account password (for serial) |
| `licensing-server` | No | `''` | Unity License Server URL (floating license) |
| `docker-image` | No | auto | Override Docker image |
| `container-registry` | No | `unityci/editor` | Docker image registry |
| `container-registry-version` | No | `3` | Docker image tag version |

### Outputs

| Output | Description |
|--------|-------------|
| `volume-name` | Docker volume name with activated license |

---

## unity-test

Runs Unity tests and outputs NUnit XML results with parsed summaries.
Supports **EditMode**, **PlayMode**, **Standalone**, and **all** modes.

```yaml
- uses: Frogitude/frogitude-ci-actions/unity-test@v1
  id: tests
  with:
    unity-version: '6000.0.23f1'
    license: ${{ secrets.UNITY_LICENSE }}
    test-mode: all
    coverage: true
    coverage-options: 'generateAdditionalMetrics;generateHtmlReport;generateBadgeReport'

- name: Check results
  run: echo "Passed ${{ steps.tests.outputs.passed }}/${{ steps.tests.outputs.total }}"
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `unity-version` | Yes | — | Unity Editor version |
| `test-mode` | No | `all` | `all`, `editmode`, `playmode`, or `standalone` |
| `project-path` | No | `.` | Path to Unity project |
| `artifacts-path` | No | `test-results` | Output directory for XML results |
| `coverage` | No | `false` | Enable code coverage |
| `coverage-options` | No | see below | Coverage options string |
| `custom-parameters` | No | `''` | Extra Unity CLI arguments |
| `package-mode` | No | `false` | Test a Unity package instead of project |
| `use-host-network` | No | `false` | Use host network (private registries) |
| `check-name` | No | `''` | Custom name for GitHub check annotation |
| `license` | No | `''` | Personal .ulf content |
| `serial` | No | `''` | Pro serial number |
| `email` | No | `''` | Unity account email |
| `password` | No | `''` | Unity account password |
| `licensing-server` | No | `''` | Unity License Server URL |
| `docker-image` | No | auto | Override Docker image |
| `container-registry` | No | `unityci/editor` | Docker image registry |
| `container-registry-version` | No | `3` | Docker image tag version |
| `docker-cpu-limit` | No | `''` | Docker CPU limit |
| `docker-memory-limit` | No | `''` | Docker memory limit |
| `ssh-agent` | No | `''` | SSH agent socket path |
| `git-private-token` | No | `''` | Token for private Git dependencies |
| `run-as-host-user` | No | `false` | Run Docker as host UID (self-hosted) |

> Default `coverage-options`: `generateAdditionalMetrics;generateHtmlReport;generateBadgeReport`

### Outputs

| Output | Description |
|--------|-------------|
| `results-path` | Path to test results directory |
| `total` | Total test count |
| `passed` | Passed test count |
| `failed` | Failed test count |
| `skipped` | Skipped test count |
| `coverage-path` | Path to coverage results (when enabled) |

---

## unity-build

Builds a Unity project for any target platform. Auto-selects the correct Docker image.
Supports **Build Profiles** (Unity 6+), **versioning**, **Android signing/export**, and **GPU rendering**.

```yaml
- uses: Frogitude/frogitude-ci-actions/unity-build@v1
  with:
    unity-version: '6000.0.23f1'
    license: ${{ secrets.UNITY_LICENSE }}
    target-platform: StandaloneWindows64
    build-name: MyGame
    versioning: Semantic
    version: '1.2.0'
```

### Platform → Docker Image

| Platform | Docker Tag |
|----------|-----------|
| `StandaloneWindows64` | `windows-mono` |
| `StandaloneWindows` | `windows-mono` |
| `StandaloneOSX` | `mac-mono` |
| `StandaloneLinux64` | `linux-il2cpp` |
| `Android` | `android` |
| `iOS` | `ios` |
| `WebGL` | `webgl` |
| `tvOS` | `appletv` |
| `WSAPlayer` | `universal-windows-platform` |
| `LinuxHeadlessSimulation` | `linux-il2cpp` |

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `unity-version` | Yes | — | Unity Editor version |
| `target-platform` | Yes | — | Build target (see table above) |
| `project-path` | No | `.` | Path to Unity project |
| `build-name` | No | repo name | Output build name |
| `build-path` | No | `build` | Output directory |
| `build-method` | No | `''` | Custom C# build method |
| `build-profile` | No | `''` | Unity Build Profile path (Unity 6+) |
| `custom-parameters` | No | `''` | Extra Unity CLI arguments |
| `versioning` | No | `''` | `Semantic`, `Tag`, `Custom`, or `None` |
| `version` | No | `''` | Version string (for Custom versioning) |
| `il2cpp` | No | `false` | Force IL2CPP backend |
| `enable-gpu` | No | `false` | Enable GPU rendering in build |
| `allow-dirty-build` | No | `false` | Allow builds with uncommitted changes |
| `android-keystore-base64` | No | `''` | Base64 keystore for Android signing |
| `android-keystore-pass` | No | `''` | Keystore password |
| `android-keyalias-name` | No | `''` | Key alias name |
| `android-keyalias-pass` | No | `''` | Key alias password |
| `android-export-type` | No | `androidPackage` | `androidPackage` (APK), `androidAppBundle` (AAB), or `androidStudioProject` |
| `android-target-sdk-version` | No | `''` | Android target SDK version |
| `android-symbol-type` | No | `''` | `public`, `debugging`, or `none` |
| `license` | No | `''` | Personal .ulf content |
| `serial` | No | `''` | Pro serial number |
| `email` | No | `''` | Unity account email |
| `password` | No | `''` | Unity account password |
| `licensing-server` | No | `''` | Unity License Server URL |
| `docker-image` | No | auto | Override Docker image |
| `container-registry` | No | `unityci/editor` | Docker image registry |
| `container-registry-version` | No | `3` | Docker image tag version |
| `docker-cpu-limit` | No | `''` | Docker CPU limit |
| `docker-memory-limit` | No | `''` | Docker memory limit |
| `ssh-agent` | No | `''` | SSH agent socket path |
| `git-private-token` | No | `''` | Token for private Git dependencies |
| `run-as-host-user` | No | `false` | Run Docker as host UID (self-hosted) |

### Outputs

| Output | Description |
|--------|-------------|
| `build-path` | Path to build output |
| `build-size` | Total artifact size |
| `build-version` | Resolved version string |
| `engine-exit-code` | Unity Editor exit code |

---

## unity-return-license

Returns a Unity Pro/Plus serial license to free the seat allocation.
Run this as a **post-step** or in an `if: always()` job after build/test.

> Personal (.ulf) and License Server licenses do **not** need returning.

```yaml
- uses: Frogitude/frogitude-ci-actions/unity-return-license@v1
  if: always()
  with:
    unity-version: '6000.0.23f1'
    license-volume: ${{ steps.activate.outputs.volume-name }}
    serial: ${{ secrets.UNITY_SERIAL }}
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `unity-version` | Yes | — | Unity Editor version |
| `license-volume` | Yes | — | Docker volume with activated license |
| `serial` | Yes | — | Pro/Plus serial key |
| `container-registry` | No | `unityci/editor` | Docker image registry |
| `container-registry-version` | No | `3` | Docker image tag version |

---

## steam-deploy

Uploads build artifacts to Steamworks via `steamcmd`. Uses `config.vdf` for authentication (no interactive MFA).

```yaml
- uses: Frogitude/frogitude-ci-actions/steam-deploy@v1
  with:
    username: ${{ secrets.STEAM_USERNAME }}
    config-vdf: ${{ secrets.STEAM_CONFIG_VDF }}
    app-id: '480'
    release-branch: prerelease
    root-path: build
    depot-1-path: windows
    depot-2-path: macos
    depot-3-path: linux
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `username` | Yes | — | Steam username |
| `config-vdf` | Yes | — | Base64-encoded config.vdf |
| `app-id` | Yes | — | Steam Application ID |
| `build-description` | No | auto | Build description in Steamworks |
| `release-branch` | No | `prerelease` | Target branch |
| `root-path` | No | `build` | Root content path |
| `depot-1-path` | No | `''` | Depot 1 content path |
| `depot-2-path` | No | `''` | Depot 2 content path |
| `depot-3-path` | No | `''` | Depot 3 content path |
| `depot-4-path` | No | `''` | Depot 4 content path |
| `depot-5-path` | No | `''` | Depot 5 content path |

---

## Generate config.vdf

To generate `STEAM_CONFIG_VDF`:

```bash
# On a machine where you can complete MFA:
steamcmd +login YOUR_USERNAME +quit

# Encode the resulting config:
base64 -w 0 ~/.steam/config/config.vdf
# Store the output as a GitHub Secret: STEAM_CONFIG_VDF
```

---

## License

MIT — [Frogitude](https://github.com/Frogitude)
