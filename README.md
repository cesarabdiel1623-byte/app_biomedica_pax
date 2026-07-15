# Go Medical

## Configuracion de credenciales

Las credenciales del cliente ya no viven en `lib/` ni se empaquetan como asset.
La app lee valores inyectados en tiempo de compilacion con `dart-define`.

1. Crea un archivo local `dart_defines.json` en la raiz del proyecto.
2. Usa como base `dart_defines.example.json`.
3. Ejecuta la app inyectando ese archivo:

```bash
flutter run --dart-define-from-file=dart_defines.json
```

Si usas VS Code, la configuracion en `.vscode/launch.json` ya inyecta ese
archivo automaticamente.

Nota de seguridad:
`SUPABASE_ANON_KEY` es una clave publica de cliente, no una `service_role`.
Las operaciones sensibles deben protegerse con RLS en Supabase. Para builds de
release, usa `--dart-define-from-file` desde el sistema de build o CI/CD.

## Variables esperadas

```json
{
  "SUPABASE_URL": "https://TU-PROYECTO.supabase.co",
  "SUPABASE_ANON_KEY": "TU_SUPABASE_ANON_KEY",
  "GOOGLE_ANDROID_CLIENT_ID": "TU_ANDROID_CLIENT_ID.apps.googleusercontent.com",
  "GOOGLE_WEB_CLIENT_ID": "TU_WEB_CLIENT_ID.apps.googleusercontent.com"
}
```
