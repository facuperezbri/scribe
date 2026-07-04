# LocalDictate

Aplicación de escritorio para macOS que graba voz en español y la transcribe
completamente en el dispositivo, usando [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift)
(Whisper en Core ML) de Argmax. No hay backend, no hay analítica ni telemetría,
no hay login ni pagos.

## Privacidad

> El audio y el texto se procesan localmente en esta Mac. No se envían a
> servidores. Solo se usa internet para descargar el modelo si todavía no
> está instalado.

Esta es la única operación de red de toda la app: la descarga inicial del
modelo de Whisper, disparada exclusivamente por el usuario desde el botón
"Descargar modelo". `ModelManager` nunca descarga nada por sí solo; solo lee
el disco para saber si el modelo ya está instalado.

## Requisitos

- macOS 13 o superior
- Xcode 15 o superior
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- ~1 GB de espacio libre en disco para el modelo (`large-v3-v20240930_626MB`)

## Compilar y ejecutar

```bash
xcodegen generate
open LocalDictate.xcodeproj
```

Y correr el esquema `LocalDictate` desde Xcode (⌘R).

También se puede compilar desde la terminal:

```bash
xcodegen generate
xcodebuild -project LocalDictate.xcodeproj -scheme LocalDictate \
  -configuration Debug -destination 'platform=macOS' build
```

## Uso

1. Pulsar "Grabar" y hablar en español. Mientras se grava se muestra el
   tiempo transcurrido, un medidor del nivel de entrada del micrófono (para
   confirmar que se está captando audio) y, pasados los 2 y 5 minutos, un
   aviso de que la grabación es larga. Pulsar "Detener" para terminar.
2. Si es la primera vez, hace falta descargar el modelo (~626 MB) con el
   botón "Descargar modelo". La transcripción de la grabación pendiente
   arranca automáticamente en cuanto termina la descarga.
3. Mientras se transcribe se muestra un indicador de progreso indeterminado
   (WhisperKit no expone progreso incremental para este paso) con un botón
   "Cancelar". Cancelar es "soft": la app descarta el resultado en cuanto
   llega, pero no puede garantizar que WhisperKit aborte la inferencia a
   mitad de camino.
4. El texto transcripto aparece en el área editable, con un contador de
   palabras y caracteres debajo. Se puede corregir a mano, copiar con
   "Copiar" o borrar con "Limpiar". Grabar de nuevo o limpiar con una
   transcripción existente pide confirmación antes de reemplazarla o
   borrarla.
5. Con el modelo ya instalado, "Ver en Finder" abre la carpeta donde vive
   en disco.

## Arquitectura

| Archivo | Responsabilidad |
|---|---|
| `LocalDictateApp.swift` | Punto de entrada de la app (`WindowGroup`). |
| `ContentView.swift` | Layout principal en SwiftUI y diálogos de confirmación. |
| `DictationViewModel.swift` | Estado de la app y orquestación entre servicios. |
| `RecordingButton.swift` | Botón principal de Grabar/Detener. |
| `RecordingFeedbackView.swift` | Tiempo transcurrido, medidor de nivel y avisos por duración mientras se grava. |
| `TranscribingFeedbackView.swift` | Indicador de progreso y botón de cancelar mientras se transcribe. |
| `TranscriptEditorView.swift` | Área editable de la transcripción, con placeholder y contador de palabras/caracteres. |
| `StatusBadgeView.swift` | Indicador compacto del estado actual de la app. |
| `ModelStatusView.swift` | Estado del modelo (instalado / descargando / no instalado). |
| `PrivacyNoteView.swift` | Nota de privacidad fija al pie de la ventana. |
| `AudioRecorderService.swift` | Grabación de audio a WAV local (16 kHz, mono, 16-bit). |
| `MicrophonePermissionManager.swift` | Permiso de micrófono del sistema. |
| `ModelManager.swift` | Presencia y descarga explícita del modelo de WhisperKit. |
| `TranscriptionService.swift` | Envuelve WhisperKit para transcribir localmente. |
| `ClipboardService.swift` | Copiar texto al portapapeles. |

El uso directo de WhisperKit queda confinado a `ModelManager` y
`TranscriptionService`; el resto de la app no conoce esa dependencia.

## Modelo

- Variante: `large-v3-v20240930_626MB` (repo `argmaxinc/whisperkit-coreml`).
- Se guarda en `~/Library/Application Support/LocalDictate/Models`.
- El idioma de transcripción está fijo en español (`TranscriptionService`).

## Solución de problemas

### macOS pide permiso de micrófono repetidamente, en cada reinstalación

Causa raíz: sin un Team ID de firma estable, cada build recompilado tiene una
identidad de firma distinta y TCC (el sistema de permisos de macOS) no puede
asociar el permiso otorgado con la siguiente versión de la app. Se soluciona
firmando con un Team ID fijo:

1. En Xcode, seleccioná el proyecto `LocalDictate` (no el target) en el
   Project Navigator, luego la pestaña **Signing & Capabilities** del target
   `LocalDictate`.
2. Activá "Automatically manage signing" y elegí tu Apple ID / Team.
3. Confirmá que `project.yml` tiene `DEVELOPMENT_TEAM` con ese Team ID (podés
   verlo también con `security find-identity -v -p codesigning`, o inspeccionando
   un build ya firmado con `codesign -dvvv LocalDictate.app` — el campo
   `TeamIdentifier` no debe decir `not set`).

Lo que sí mantiene estable la identidad de la app frente a TCC (y por lo tanto
evita el re-prompt) son tres cosas, todas ya fijas en este repo:

- **Bundle Identifier**: `com.localdictate.app`, fijo en `project.yml`
  (`PRODUCT_BUNDLE_IDENTIFIER`), no se recalcula por build.
- **Team ID / certificado de firma**: mientras exista un solo certificado
  "Apple Development" válido en el keychain para ese Team (`security
  find-identity -v -p codesigning` debería listar exactamente uno), Xcode
  firma siempre igual. Si en algún momento aparece más de un certificado
  válido, Xcode puede firmar con uno distinto entre builds y eso sí reinicia
  el permiso.
- **Ruta de build (DerivedData)**: no importa. TCC identifica a la app por su
  firma de código (Team ID + Bundle ID), no por la ruta del binario, así que
  builds sucesivos en `DerivedData` con hashes distintos no disparan un
  nuevo prompt mientras la firma no cambie.

Lo único que sí fuerza un re-prompt aun con esto resuelto es un
`tccutil reset Microphone` explícito, o revocar el certificado de desarrollo
(por ejemplo, al reinstalar Xcode desde cero o cambiar de Apple ID).

### No aparece el diálogo de permiso de micrófono, ni una entrada en Ajustes

Causa raíz: con `ENABLE_HARDENED_RUNTIME: YES`, macOS exige un entitlement
explícito para acceder a recursos protegidos como el micrófono
(`com.apple.security.device.audio-input`), además del texto en
`NSMicrophoneUsageDescription`. Sin ese entitlement, el diálogo de TCC nunca
se llega a mostrar — ni se registra ningún intento en Ajustes — y en la
consola puede verse algo como `NSViewBridgeErrorCanceled`. Se soluciona
agregando el entitlement en `LocalDictate/LocalDictate.entitlements` (ya
incluido en este repo) y apuntándolo desde `CODE_SIGN_ENTITLEMENTS` en
`project.yml`.

Si necesitás reintentar el flujo de permiso desde cero durante desarrollo:

```bash
tccutil reset Microphone com.localdictate.app
```

### Mensajes en consola como `ViewBridge ... NSViewBridgeErrorCanceled` o `Unable to obtain a task name port right`

Son ruido benigno de macOS (el subsistema `RemoteViewService`/`ViewBridge`
usado por paneles de sistema fuera de proceso, y el intento del debugger de
adjuntarse a un proceso auxiliar efímero). El propio mensaje de Apple lo
aclara: `benign unless unexpected`. Si la app funciona bien (grabación,
permiso, transcripción), no indican un problema real.

## Limitaciones conocidas

- Solo español; no hay selector de idioma ni autodetección.
- Sin ícono de app personalizado.
- El manejo de errores es básico: los mensajes se muestran en texto, sin
  reintentos automáticos más allá de dejar los botones disponibles para
  volver a intentar.
- Cada transcripción reemplaza a la anterior; no hay modo de agregar
  (append) ni historial de transcripciones pasadas.
- Cancelar una transcripción en curso es "soft": WhisperKit no expone una
  forma de abortar la inferencia a mitad de camino, así que la app solo
  garantiza descartar el resultado cuando llega, no detener el cálculo antes.
- No hay selector de modelo: se usa siempre el mismo modelo de WhisperKit
  fijado en `ModelManager`.
- Sin atajo de teclado global, ícono en la barra de menú ni transcripción
  en vivo mientras se grava (todo esto es a propósito: queda fuera de esta
  versión y reservado para una futura).

## Próximos pasos (fuera de esta versión)

Roadmap tentativo para después de MVP2, en orden de prioridad:

- **MVP3** — Atajo de teclado global para grabar/detener sin enfocar la
  ventana, y pegado automático del resultado en la app que estaba activa.
- **MVP4** — Ícono en la barra de menú (menu bar extra) como forma
  alternativa de uso, sin depender de la ventana principal.
- **MVP5** — Transcripción en vivo mientras se graba, en lugar de esperar
  a "Detener".
- **MVP6** — Historial de transcripciones anteriores (hoy solo se persiste
  la última).
- **MVP7** — Selector de modelo (elegir entre variantes de Whisper según el
  trade-off velocidad/precisión que prefiera cada usuario) y limpieza de
  cara a una eventual distribución (ícono de app propio, etc.).
