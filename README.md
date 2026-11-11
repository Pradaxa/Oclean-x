# Oclean X (app nativa iOS)

Envoltura nativa de la web app mi-cepillo (https://mi-cepillo.pages.dev) con
Bluetooth real vía Capacitor + @capacitor-community/bluetooth-le.

- `www/`: la web app completa (misma que se despliega en Cloudflare Pages).
  `www/assets/native-ble-shim.js` solo actúa dentro de la app nativa.
- `ios/`: proyecto Xcode generado por Capacitor (SPM).
- Build: GitHub Actions macOS → IPA sin firmar → release → `altstore/source.json`
  (instalación con AltStore Classic, firma gratuita de 7 días).

Publicar: Actions → build-ios → Run workflow → publish=true (solo con OK del usuario).
