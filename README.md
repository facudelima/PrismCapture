# PrismCapture

App nativa de capturas para macOS, inspirada en Lightshot / CleanShot X.

**Sin IA** — captura, anotación, OCR, portapapeles, historial y compartir.

## Descargar la app

1. Andá a [**Releases**](https://github.com/facudelima/PrismCapture/releases)
2. Bajá `PrismCapture-*-macos.zip`
3. Descomprimí y mové `PrismCapture.app` a **Aplicaciones**
4. Primera vez: clic derecho → **Abrir** (Gatekeeper)

Requiere **macOS 14+** y permiso de **Grabación de pantalla**.

### Actualizaciones

La app muestra la versión en el menú bar y en **Ajustes → Actualizaciones**. Puede buscar la última release en GitHub e instalarla. Como el repo es privado, usa el token de Keychain (`github.com`) o un PAT en Ajustes.

## Requisitos (desarrollo)

- macOS 14+
- Xcode 16+
- Permiso de **Grabación de pantalla**

## Abrir y compilar

```bash
open PrismCapture.xcodeproj
```

En Xcode: target **PrismCapture** → Run (⌘R).

Por terminal:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project PrismCapture.xcodeproj -scheme PrismCapture -configuration Debug build
```

Generar zip de Release (para instalar como app):

```bash
./scripts/build-release.sh 1.0.0
# → dist/PrismCapture-1.0.0-macos.zip
```

## Uso

La app vive en la barra de menú (`LSUIElement`).

| Atajo | Acción |
|-------|--------|
| ⌘⇧2 | Capturar área |
| ⌘⇧3 | Pantalla completa |
| ⌘⇧4 | Ventana |
| Space | Alternar modo ventana en el overlay |
| ⌘C | Copiar |
| ⌘S | Guardar |
| Esc | Cancelar / cerrar |

Tras capturar aparece un editor flotante con herramientas de anotación (rectángulo, círculo, flecha, lápiz, resaltador, blur, pixelate, texto, marcadores, emoji, crop), undo/redo, OCR y subida. La herramienta **Mover** re-captura la zona (estilo Lightshot).

## Arquitectura

SwiftUI + MVVM:

- `App/` — Menu bar, estado global
- `Services/` — captura (ScreenCaptureKit), clipboard, archivos, OCR (Vision), upload, hotkeys
- `ViewModels/` — captura, anotación, historial, ajustes
- `Views/` — overlay de selección, editor, settings, historial

## Notas

- Imgur requiere reemplazar `YOUR_IMGUR_CLIENT_ID` en `UploadService.swift`.
- El color de acento hereda el de macOS.
- Tema: Claro / Oscuro / Auto en Ajustes.
