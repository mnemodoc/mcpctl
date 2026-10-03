#!/usr/bin/env python3
"""Update version and SHA256 checksums in a Homebrew formula.

Usage:
    python3 scripts/update_formula.py \\
        --formula Formula/mcpctl.rb \\
        --version 0.2.0 \\
        --darwin-arm64   <sha256> \\
        --darwin-amd64   <sha256> \\
        --linux-arm64    <sha256> \\
        --linux-amd64    <sha256>
"""
import argparse
import re
import sys
from pathlib import Path


# The formula declares no `version`: Homebrew scans it from the release tag in
# the download URLs. Declaring it as well makes `brew audit --strict` fail with
# "version is redundant with version scanned from URL", so the version lives in
# the URLs only and is rewritten there.
def replace_version(content: str, version: str) -> str:
    pattern = re.compile(r'(/releases/download/v)[^/"]+(/)')
    result, n = pattern.subn(rf"\g<1>{version}\g<2>", content)
    if n == 0:
        print("ERROR: no release download URL found to bump", file=sys.stderr)
        sys.exit(1)
    return result


def replace_sha(content: str, platform: str, sha: str) -> str:
    """Replace the sha256 following the URL that contains `platform`."""
    pattern = re.compile(
        r'(url\s+"[^"]*' + re.escape(platform) + r'[^"]*"\s+sha256\s+)"[a-f0-9]{64}"',
        re.DOTALL,
    )
    result, n = pattern.subn(rf'\g<1>"{sha}"', content)
    if n == 0:
        print(f"ERROR: no sha256 found for platform {platform!r}", file=sys.stderr)
        sys.exit(1)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--formula", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--darwin-arm64", required=True, dest="darwin_arm64")
    parser.add_argument("--darwin-amd64", required=True, dest="darwin_amd64")
    parser.add_argument("--linux-arm64", required=True, dest="linux_arm64")
    parser.add_argument("--linux-amd64", required=True, dest="linux_amd64")
    args = parser.parse_args()

    path = Path(args.formula)
    content = path.read_text()

    content = replace_version(content, args.version)
    content = replace_sha(content, "darwin-arm64", args.darwin_arm64)
    content = replace_sha(content, "darwin-amd64", args.darwin_amd64)
    content = replace_sha(content, "linux-arm64",  args.linux_arm64)
    content = replace_sha(content, "linux-amd64",  args.linux_amd64)

    path.write_text(content)
    print(f"Updated {path} to v{args.version}")


if __name__ == "__main__":
    main()
