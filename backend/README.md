# FileX conversion backend

Expected endpoints:

POST /convert/word-to-pdf
- Request body: raw document bytes
- Header: X-File-Name
- Response: application/pdf bytes

POST /convert/pdf-to-word
- Request body: raw PDF bytes
- Header: X-File-Name
- Response: application/vnd.openxmlformats-officedocument.wordprocessingml.document bytes

Recommended implementation:
- LibreOffice headless for Office -> PDF
- A production PDF -> DOCX engine/service for PDF -> editable DOCX
- Temporary files with automatic deletion
- File size and timeout limits
- HTTPS
- No permanent document retention

The Flutter app does not embed a secret API key.
