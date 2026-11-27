# BoringSSL Builds

Automated, reproducible-per-commit builds of BoringSSL shared libraries for selected desktop platforms.

The workflow checks the upstream `google/boringssl` HEAD, builds that exact commit on native GitHub-hosted runners, packages the public headers and native libraries, and publishes one GitHub Release containing all platform archives.

## Supported targets

| RID | Runner | Output |
|---|---|---|
| `win-x64` | Windows x64 | `crypto.dll`, `ssl.dll`, import `.lib` files |
| `win-arm64` | Windows ARM64 | `crypto.dll`, `ssl.dll`, import `.lib` files |
| `linux-x64` | Linux x64 | `libcrypto.so`, `libssl.so` |
| `linux-arm64` | Linux ARM64 | `libcrypto.so`, `libssl.so` |
| `osx-x64` | macOS Intel | `libcrypto.dylib`, `libssl.dylib` |
| `osx-arm64` | macOS Apple Silicon | `libcrypto.dylib`, `libssl.dylib` |

Runner availability can vary by GitHub plan and repository. If a runner label is unavailable to your repository, change the corresponding `os` value in `.github/workflows/build.yml`.

## Release naming

Releases are named after the upstream commit:

```text
boringssl-<first-12-characters-of-upstream-commit>
```

Each release contains six ZIP archives and `SHA256SUMS.txt`.

Each ZIP contains:

```text
include/openssl/   Public BoringSSL headers
lib/               Shared libraries and Windows import libraries
bin/               Windows DLL files
LICENSE            Upstream license, when present
build-info.json    Upstream commit, RID and checksums
```

## Run locally

Install Git, CMake, Ninja, Python 3, Go, and the platform's native compiler/toolchain.

### Linux

```bash
sudo apt-get install cmake ninja-build python3 git golang nasm perl
bash scripts/build.sh linux-x64 <upstream-commit>
```

### macOS

```bash
brew install cmake ninja python git go nasm
bash scripts/build.sh osx-arm64 <upstream-commit>
```

### Windows

Run from a Visual Studio Developer PowerShell with the matching architecture tools enabled:

```powershell
.\scripts\build.ps1 -Rid win-x64 -UpstreamSha <upstream-commit>
```

The scripts create `boringssl/`, `build/`, and `dist/` in the repository root.

## GitHub Actions

The workflow runs when:

- A commit is pushed to `main`.
- It is started manually using **Actions → Build BoringSSL → Run workflow**.
- The daily schedule fires.

The workflow only publishes a release if that upstream commit has not already been released.

The repository's Actions setting must allow `GITHUB_TOKEN` to create releases. The workflow declares `contents: write`.

## Important compatibility notes

BoringSSL is not a drop-in, ABI-stable replacement for OpenSSL. It does not promise API or ABI stability. Always consume headers and native binaries from the same release, and pin the upstream commit in downstream projects.

The `BORINGSSL_SHARED_LIBRARY` preprocessor definition may be required when compiling code that includes BoringSSL headers against shared builds. Check the upstream headers and build configuration for the exact revision you consume.

These packages are intended for development and application integration. They are not a promise of FIPS validation or a substitute for reviewing BoringSSL's security and platform requirements.

## License

BoringSSL is maintained by Google. Review the upstream license and notices before redistributing or embedding the binaries.
