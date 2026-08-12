# FileX

FileX is a Flutter Android app for:

1. Word -> PDF
2. PDF -> mobile-compatible DOCX
3. Camera scan -> PDF
4. Merge 2+ PDFs

## Build without Android Studio

This repository is designed for GitHub Actions.

1. Create a GitHub repository.
2. Upload this project.
3. Push to `main`.
4. Open **Actions**.
5. Open **Build FileX APK**.
6. Download the `FileX-release-apk` artifact.

## Important: document conversions

The mobile app intentionally sends Word/PDF conversion jobs to a configurable backend. This is required for reliable handling of Microsoft Office formats such as DOC/DOCX/DOCM/DOT/DOTX and for high-quality PDF -> DOCX conversion.

Build the APK with:

flutter build apk --release --dart-define=FILEX_SERVER=https://YOUR-CONVERSION-SERVER

GitHub Actions can be updated later with a repository secret or variable for the conversion server.

The scanner and PDF merger are local/on-device operations.

## Backend

The `backend/` directory contains a starter API contract. A production conversion backend should use a proper document conversion engine such as LibreOffice for Office -> PDF and a dedicated PDF -> DOCX conversion engine/service.

Do not put a private conversion API key directly into the APK.

## Current local file behavior

Generated files are written into the app's private documents directory. Android can open/share these files using the system file handlers. A future release can add an explicit "Save to Downloads" action using Android's Storage Access Framework.
