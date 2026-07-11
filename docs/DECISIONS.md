# Decisiones de diseño

Registro de decisiones de diseño no obvias tomadas durante el desarrollo de Scribe, con su motivación. El código ya no referencia números de fase/MVP en los comentarios (ver `git log` para esa historia); este documento reúne el *por qué* de las decisiones que vale la pena no perder.

## Estado del dictado como máquina de estados explícita

`DictationSessionState` (`.idle`, `.requestingPermission`, `.startingRecording`, `.recording`, `.stoppingRecording`, `.transcribing`) reemplaza flags booleanos ad hoc (`isStartingRecording`, `isTranscriptionCancelled`) que representaban estas transiciones de forma implícita. Cada paso del flujo grabar → transcribir es un caso explícito, y `handlePrimaryDictationAction` decide qué hacer mirando solo el caso actual, sin estado oculto adicional. `AppState` separa permiso/modelo/sesión/error como dimensiones independientes en vez de un único enum plano que mezclara las cuatro cosas en un solo caso por vez.

## Reemplazar una transcripción ya no bloquea con una confirmación

Grabar de nuevo sobre una transcripción existente no pide confirmación: `DictationViewModel` guarda esa transcripción en `previousTranscript` (un único búfer en memoria, no un historial) y arranca a grabar directo. `restorePreviousTranscript()` permite recuperarla como red de seguridad de un solo uso. Limpiar (`clearTranscript()`) sigue pidiendo confirmación explícita porque es una acción destructiva iniciada por el usuario, distinta de un reemplazo esperable del flujo normal.

## Escala compartida de espaciado (`Metrics`)

Antes cada vista definía sus propios números sueltos (14, 10, 8, 6, 4...) sin relación entre sí. `Metrics` centraliza padding/radios/espaciado para que no vuelvan a divergir entre vistas.

## `AppDelegate` posee `DictationViewModel`, no `ContentView`

Si `ContentView` posee el view model como `@StateObject`, cerrar la ventana principal destruye la instancia y con ella el view model — y el monitor global del atajo (que vive dentro de `GlobalHotkeyServicing` y captura `self` como `weak`) deja de andar en cuanto se cierra la ventana. Con el view model viviendo en `AppDelegate`, sigue existiendo mientras la app esté corriendo, sin importar si la ventana está abierta, minimizada o cerrada.

## El atajo global no activa la ventana principal (background-first)

Presionar el atajo global (o los ítems de la barra de menús) arranca/detiene la grabación sin traer a Scribe al frente ni robarle el foco a la app en la que está el usuario — mismo criterio de diseño que utilidades de dictado en background (p. ej. Wispr Flow). Mostrar la ventana queda reservado para una acción explícita del usuario ("Mostrar Scribe" del menú de la barra de menús, vía `showMainWindow()`). `WindowActivationServicing` existe como contrato mínimo separado de `DictationViewModel` para que el atajo pueda activar la ventana bajo demanda sin que la lógica de grabar/detener viva en dos lugares.

## Atajo global: de Option-solo a Fn + Espacio

El atajo original usaba Option solo, detectado vía `flagsChanged` (que solo informa cambios de modificadores). Se migró a Fn + Espacio porque Option solo bloquea el uso normal de Option para acentos/diacríticos en teclado español (Option+E, Option+U, etc.). Fn + Espacio combina un modificador (Fn) con una tecla no modificadora real (Space, keyCode 49), así que la detección pasó a usar `.keyDown` (chequeando `keyCode == 49` y `modifierFlags.contains(.function)`) en vez de `flagsChanged`.

Se descartó `RegisterEventHotKey` (Carbon) como alternativa a `NSEvent.addGlobalMonitorForEvents`: acepta esta combinación, pero introducir un segundo mecanismo de registro de atajos no se justificaba, y el modelo de permisos (Accesibilidad) es idéntico al que ya usaba el monitor de Option.

**Limitación conocida:** la tecla Fn físicamente reasignada en algunos contextos (Fn+flecha → Home/End, etc.) es interceptada por el driver de teclado antes de llegar a las apps; Space no es una de esas teclas reasignadas, así que Fn + Espacio llega como `keyDown` normal. El comportamiento no fue verificado en variedad de hardware real (Magic Keyboard vs. built-in, teclados de terceros sin tecla Fn dedicada) — ver checklist de QA manual. Tampoco hay modo "mantener presionado" (hold-to-talk) como alternativa al toggle actual.

## Monitor global + monitor local para el atajo

`NSEvent.addGlobalMonitorForEvents` solo entrega eventos destinados a *otras* apps: en cuanto Scribe pasa a ser la app activa, el sistema deja de mandarle esos eventos al monitor global, y Fn + Espacio dejaba de andar apenas Scribe tenía el foco. `NSEvent.addLocalMonitorForEvents` cubre el caso complementario (solo eventos mientras Scribe es la app activa). Ambos caminos de despacho son mutuamente excluyentes para un mismo evento físico, así que instalar los dos monitores no duplica el disparo del atajo; ambos delegan en el mismo `handleKeyDown`. El monitor local no depende del permiso de Accesibilidad (solo el global lo necesita), y devuelve el evento sin modificar para no tragarse teclas normales que el usuario escriba dentro de Scribe.

## Burbuja flotante no intrusiva

`RecordingOverlayController` usa un `NSPanel` `.nonactivatingPanel` sin foco propio, fuera del árbol de `Scene` de SwiftUI porque un panel con `orderFrontRegardless()` no tiene equivalente directo ahí — cualquier `Window`/`WindowGroup` de SwiftUI puede terminar activando la app y robando el foco, justo lo que la decisión de "atajo background-first" evitó. El controlador solo refleja `viewModel.overlayPhase`, sin decidir nada por su cuenta, para no duplicar el flujo centralizado de `DictationViewModel`.

`RecordingOverlayPhase` es deliberadamente más angosto que `PrimaryState`: no le importan permiso/modelo/Accesibilidad ni la transcripción en sí, solo grabar/transcribir y el instante posterior al éxito (`.done`, breve). `TranscriptionOutcome` (`.success`/`.failure`/`.cancelled`) existe porque `state.error` no alcanza por sí solo para distinguir "recién terminó bien" de "está en reposo desde antes" (por ejemplo, al abrir la app con una transcripción restaurada) — se limpia al arrancar la próxima grabación para que la burbuja no reabra un "Listo" viejo.

## Ítem de la barra de menús

Scribe puede usarse como utilitario en background sin depender de que la ventana principal esté abierta: la barra de menús ofrece acciones rápidas (iniciar/detener dictado, copiar, mostrar ventana) delegando siempre en `DictationViewModel`, el mismo punto de entrada centralizado que usa el botón de la ventana principal y el atajo global.
