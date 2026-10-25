#!/usr/bin/env python3
"""Build and exercise preferences in a temporary app with isolated defaults."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--show", action="store_true", help="Leave the test preferences open for visual inspection")
parser.add_argument("--snapshots", action="store_true", help="Render light/dark preference snapshots into build/function-key-snapshots")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent

with tempfile.TemporaryDirectory(prefix="Fluor-preferences-ui-") as temporary:
    work = Path(temporary)
    shutil.copytree(root / "Fluor", work / "Fluor", symlinks=True, ignore=shutil.ignore_patterns(".DS_Store"))
    shutil.copytree(root / "Fluor.xcodeproj", work / "Fluor.xcodeproj", symlinks=True)
    shutil.copyfile(root / "README.md", work / "README.md")
    shutil.copyfile(root / "Tests/FunctionKeyPreferencesSmokeApp.swift", work / "Fluor/Misc/AppDelegate.swift")
    command = [
        "xcodebuild", "-project", str(work / "Fluor.xcodeproj"), "-scheme", "Fluor",
        "-configuration", "Debug", "-derivedDataPath", str(work / "DerivedData"),
        "-clonedSourcePackagesDirPath", str(root / "build/SourcePackages"),
        "PRODUCT_BUNDLE_IDENTIFIER=com.thinksoft.Fluor.function-key-ui-tests",
        "CODE_SIGNING_ALLOWED=NO", "build",
    ]
    log = root / "build/function-key-ui-build.log"
    log.parent.mkdir(exist_ok=True)
    with log.open("w") as output:
        result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        print(log.read_text()[-12000:], flush=True)
        raise SystemExit(result.returncode)
    app = work / "DerivedData/Build/Products/Debug/Fluor.app"
    print(f"UI test app: {app}", flush=True)
    command = [str(app / "Contents/MacOS/Fluor"), "-AppleLanguages", "(en)"]
    if args.show:
        command.append("--show")
    if args.snapshots:
        directory = root / "build/function-key-snapshots"
        directory.mkdir(exist_ok=True)
        command.extend(["--snapshot-directory", str(directory)])
    process = subprocess.Popen(command)
    try:
        result = process.wait(timeout=None if args.show else 30)
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        process.terminate()
        process.wait(timeout=10)
        raise
    raise SystemExit(result)
