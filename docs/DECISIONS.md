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

**Limitación conocida:** la tecla Fn físicamente reasignada en algunos contextos (Fn+flecha → Home/End, etc.) es interceptada por el driver de teclado antes de llegar a las apps; Space no es una de esas teclas reasignadas, así que Fn + Espacio llega como `keyDown` normal. El comportamiento no fue verificado en variedad de hardware real (Magic Keyboard vs. built-in, teclados de terceros sin tecla Fn dedicada) — ver checklist de QA manual en el README. Tampoco hay modo "mantener presionado" (hold-to-talk) como alternativa al toggle actual.

## `HotkeyTrigger`: el combo del atajo, separado de su detección

`LiveGlobalHotkeyService.handleKeyDown` no compara `event.keyCode`/`event.modifierFlags` inline contra constantes hardcodeadas; delega en un `HotkeyTrigger` (keyCode + modificador requerido) inyectado por el caller, con `.fnSpace` como valor por defecto. Esto no es una preferencia de usuario ni abre una UI de configuración — el atajo sigue sin ser configurable (ver `docs/ROADMAP.md`) — es solo un seam interno: si la validación en hardware real (limitación conocida arriba) confirma que Fn + Espacio no es fiable en algún teclado concreto, cambiarlo pasa por instanciar `LiveGlobalHotkeyService(trigger:)` con otro `HotkeyTrigger`, sin tocar el monitor de eventos, el modelo de permisos de Accesibilidad, ni `DictationViewModel`.

## Monitor global + monitor local para el atajo

`NSEvent.addGlobalMonitorForEvents` solo entrega eventos destinados a *otras* apps: en cuanto Scribe pasa a ser la app activa, el sistema deja de mandarle esos eventos al monitor global, y Fn + Espacio dejaba de andar apenas Scribe tenía el foco. `NSEvent.addLocalMonitorForEvents` cubre el caso complementario (solo eventos mientras Scribe es la app activa). Ambos caminos de despacho son mutuamente excluyentes para un mismo evento físico, así que instalar los dos monitores no duplica el disparo del atajo; ambos delegan en el mismo `handleKeyDown`. El monitor local no depende del permiso de Accesibilidad (solo el global lo necesita), y devuelve el evento sin modificar para no tragarse teclas normales que el usuario escriba dentro de Scribe.

## Burbuja flotante no intrusiva

`RecordingOverlayController` usa un `NSPanel` `.nonactivatingPanel` sin foco propio, fuera del árbol de `Scene` de SwiftUI porque un panel con `orderFrontRegardless()` no tiene equivalente directo ahí — cualquier `Window`/`WindowGroup` de SwiftUI puede terminar activando la app y robando el foco, justo lo que la decisión de "atajo background-first" evitó. El controlador solo refleja `viewModel.overlayPhase`, sin decidir nada por su cuenta, para no duplicar el flujo centralizado de `DictationViewModel`.

`RecordingOverlayPhase` es deliberadamente más angosto que `PrimaryState`: no le importan permiso/modelo/Accesibilidad ni la transcripción en sí, solo grabar/transcribir y el instante posterior al éxito (`.done`, breve). `TranscriptionOutcome` (`.success`/`.failure`/`.cancelled`) existe porque `state.error` no alcanza por sí solo para distinguir "recién terminó bien" de "está en reposo desde antes" (por ejemplo, al abrir la app con una transcripción restaurada) — se limpia al arrancar la próxima grabación para que la burbuja no reabra un "Listo" viejo.

## Ítem de la barra de menús

Scribe puede usarse como utilitario en background sin depender de que la ventana principal esté abierta: la barra de menús ofrece acciones rápidas (iniciar/detener dictado, copiar, mostrar ventana) delegando siempre en `DictationViewModel`, el mismo punto de entrada centralizado que usa el botón de la ventana principal y el atajo global.

## Reabrir la ventana principal si se cerró del todo

Si la ventana se cerró por completo (no queda un `NSWindow` para reactivar), `LiveWindowActivationService` recurre a un closure `reopenHandler` que `ScribeApp` registra una sola vez, al arrancar, envolviendo la acción `@Environment(\.openWindow)` de SwiftUI para el `WindowGroup(id: "main")`. Al ser un `WindowGroup` singleton (sin tipo de dato asociado por ventana), llamar `openWindow(id:)` mientras ya existe una ventana simplemente la trae al frente en vez de crear una segunda, así que activaciones repetidas nunca producen ventanas duplicadas.

**Limitación conocida:** este registro depende de que `ContentView.onAppear` haya corrido al menos una vez antes de que la ventana se cierre. Es confiable en el caso normal (la app arranca, la ventana se cierra después), pero no está probado en estados de arranque atípicos (por ejemplo, si la ventana fallara al abrirse en el primer lanzamiento).

## Identidad de la app estable para TCC (rename LocalDictate → Scribe)

El Bundle Identifier se mantuvo como `com.localdictate.app` a propósito durante el rename de LocalDictate a Scribe, aunque el nombre visible y el módulo cambiaron. TCC (el sistema de permisos de macOS) asocia el permiso de micrófono otorgado al Bundle Identifier, no al nombre visible ni al módulo — cambiarlo habría reseteado el permiso de micrófono de todo el mundo sin ningún beneficio funcional. Los datos existentes de `LocalDictate` en disco (transcripción, modelo descargado) y las claves chicas de `UserDefaults` se migraron hacia adelante (la transcripción se copia, el modelo se lee donde ya está sin copiarlo, las preferencias se renombran) sin borrar nunca los archivos legados.

## `PrimaryState` separado de `statusText`

`PrimaryState` es un mapeo derivado aparte, usado solo para el título grande de `DictationStatusView` — a diferencia de `statusText` (la línea de detalle ad hoc que se va seteando inline a lo largo de los métodos del flujo). El área central necesita un string fijo y predecible por caso, no cualquier texto intermedio que una transición async haya dejado seteado de paso. `DictationViewModel.primaryState` lo resuelve con una prioridad fija: una sesión en curso (grabando/transcribiendo/etc.) siempre gana, por ser la verdad viva más urgente, incluso si falta el modelo o no está otorgada la Accesibilidad — ninguna de las dos bloquea la grabación en sí. Solo en reposo (`.idle`) se consultan permiso/modelo/Accesibilidad y transcripción lista, en ese orden.
