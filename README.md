# 🐸 FrogitudeCI Actions

Custom GitHub Actions for game engine CI/CD pipelines. Drop-in replacements for GameCI actions — same Docker images, full control.

## Actions

| Action | Purpose |
|--------|---------|
| [`unity-activate`](#unity-activate) | Activate Unity license (Personal .ulf or Pro serial) |
| [`unity-test`](#unity-test) | Run Edit-mode + Play-mode tests |
| [`unity-build`](#unity-build) | Build for any target platform |
| [`steam-deploy`](#steam-deploy) | Upload builds to Steamworks |

---

## unity-activate

Activates a Unity license inside Docker and stores it in a shared volume for subsequent steps.

```yaml
- uses: Frogitude/frogitude-ci-actions/unity-activate@v1
  with:
    unity-version: '2022.3.20f1'
    # Personal license (.ulf file content):
    license: ${{ secrets.UNITY_LICENSE }}
    # OR Pro license (serial):
    # serial: ${{ secrets.UNITY_SERIAL }}
    # email: ${{ secrets.UNITY_EMAIL }}
    # password: ${{ secrets.UNITY_PASSWORD }}
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `unity-version` | Yes | — | Unity Editor version |
| `license` | No | `''` | Personal .ulf file content |
| `serial` | No | `''` | Pro/Plus serial number |
| `email` | No | `''` | Unity account email (for serial) |
| `password` | No | `''` | Unity account password (for serial) |
| `docker-image` | No | auto | Override Docker image |

### Outputs

| Output | Description |
|--------|-------------|
| `volume-name` | Docker volume name with activated license |

---

## unity-test

Runs Unity Editor tests and outputs NUnit XML results with parsed summaries.

```yaml
- uses: Frogitude/frogitude-ci-actions/unity-test@v1
  id: tests
  with:
    unity-version: '2022.3.20f1'
    license: ${{ secrets.UNITY_LICENSE }}
    test-mode: all          # all, editmode, or playmode
    artifacts-path: test-results

- name: Check results
  run: echo "Passed ${{ steps.tests.outputs.passed }}/${{ steps.tests.outputs.total }}"
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `unity-version` | Yes | — | Unity Editor version |
| `test-mode` | No | `all` | `all`, `editmode`, or `playmode` |
| `project-path` | No | `.` | Path to Unity project |
| `artifacts-path` | No | `test-results` | Output directory for XML results |
| `coverage` | No | `false` | Enable code coverage |
| `license` | No | `''` | Personal .ulf content |
| `serial` | No | `''` | Pro serial number |
| `email` | No | `''` | Unity account email |
| `password` | No | `''` | Unity account password |

### Outputs

| Output | Description |
|--------|-------------|
| `results-path` | Path to test results directory |
| `total` | Total test count |
| `passed` | Passed test count |
| `failed` | Failed test count |
| `skipped` | Skipped test count |

---

## unity-build

Builds a Unity project for any target platform. Auto-selects the correct Docker image.

```yaml
- uses: Frogitude/frogitude-ci-actions/unity-build@v1
  with:
    unity-version: '2022.3.20f1'
    license: ${{ secrets.UNITY_LICENSE }}
    target-platform: StandaloneWindows64
    build-name: MyGame
```

### Platform → Docker Image

| Platform | Docker Tag |
|----------|-----------|
| `StandaloneWindows64` | `windows-mono-3` |
| `StandaloneOSX` | `mac-mono-3` |
| `StandaloneLinux64` | `linux-il2cpp-3` |
| `Android` | `android-3` |
| `iOS` | `ios-3` |
| `WebGL` | `webgl-3` |
| `LinuxHeadlessSimulation` | `linux-il2cpp-3` |

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `unity-version` | Yes | — | Unity Editor version |
| `target-platform` | Yes | — | Build target (see table above) |
| `project-path` | No | `.` | Path to Unity project |
| `build-name` | No | repo name | Output build name |
| `build-path` | No | `build` | Output directory |
| `build-method` | No | `''` | Custom C# build method |
| `il2cpp` | No | `false` | Force IL2CPP backend |
| `android-keystore-base64` | No | `''` | Base64 keystore for Android signing |
| `android-keystore-pass` | No | `''` | Keystore password |
| `android-keyalias-name` | No | `''` | Key alias name |
| `android-keyalias-pass` | No | `''` | Key alias password |
| `license` | No | `''` | Personal .ulf content |
| `serial` | No | `''` | Pro serial number |
| `email` | No | `''` | Unity account email |
| `password` | No | `''` | Unity account password |

### Outputs

| Output | Description |
|--------|-------------|
| `build-path` | Path to build output |
| `build-size` | Total artifact size |

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
