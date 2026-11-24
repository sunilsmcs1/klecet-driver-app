#!/bin/sh
# Build on a laptop with Flutter installed:  sh build.sh
set -e
flutter create --org in.klecet --platforms=android --project-name klecet_driver .
cp android_overrides/AndroidManifest.xml android/app/src/main/AndroidManifest.xml
flutter pub get
flutter build apk --release
echo "APK: build/app/outputs/flutter-apk/app-release.apk"
