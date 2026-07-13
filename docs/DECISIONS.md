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

## Atajo global: de Fn + Espacio (toggle) a Control (push-to-talk)

Se migró de Fn + Espacio (toggle: una presión arranca, otra detiene) a mantener Control presionado (push-to-talk: presionar arranca, soltar detiene y transcribe), igual que Whispr. Control es un modificador puro — no genera `keyDown` al presionarlo solo — así que la detección pasó de `.keyDown` (chequeando `keyCode == 49` y `.function`) a `.flagsChanged` (comparando `.control` contra el último estado conocido para quedarse solo con los flancos de subida/bajada).

El contrato de `GlobalHotkeyServicing` no cambió: sigue exponiendo un único callback (`onHotkeyPressed`), ahora invocado en ambos flancos en vez de una vez por toggle. Esto alcanza porque `handlePrimaryDictationAction` ya decide qué hacer mirando solo el estado actual de la sesión (idle → arranca, recording → detiene) — no hizo falta separar "abajo" de "arriba" en dos callbacks distintos, ni tocar `DictationViewModel`, `FakeGlobalHotkeyService`, ni ninguno de los tests que ejercitan el flujo a través de `simulateHotkeyPressed()` (una llamada por flanco, exactamente como ya estaban escritos para el toggle).

**Compromiso conocido:** Control es un modificador de uso constante en combos del sistema y de apps (Ctrl+C, Ctrl+Tab, atajos de Terminal, etc.); mantenerlo presionado como parte de cualquiera de esos combos también dispara este atajo. Este compromiso quedó documentado como parte del paso intermedio de esta migración; el default terminó cambiando a Fn (ver siguiente sección) antes de validar si molestaba en uso real, así que sigue sin resolverse — no es relevante mientras Fn siga siendo el default, pero queda registrado por si `HotkeyModifierTrigger` vuelve a usarse para caer a Control.

## Atajo global: de Control (push-to-talk) a Fn (push-to-talk, default de Whispr)

Control fue un paso intermedio: al validarlo contra el comportamiento real de Whispr, se confirmó que su atajo por defecto es Fn sola, no Control. Se migró el default a Fn manteniendo exactamente el mismo mecanismo de detección (`.flagsChanged`, comparando `.function` en vez de `.control` contra el último estado conocido) — el cambio fue de qué modificador mira `HotkeyModifierTrigger.function` (ahora el default), no de cómo se detecta push-to-talk. `GlobalHotkeyServicing`, `DictationViewModel`, y la relación con `handlePrimaryDictationAction` no cambiaron en absoluto respecto a la migración anterior (ver sección de arriba).

**Compromiso conocido, y el que de verdad importa con Fn:** macOS tiene su propia función bajo Ajustes del Sistema → Teclado → "Presionar la tecla 🌐 Fn para:" (cambiar la fuente de entrada, mostrar Emojis y Símbolos, iniciar Dictado). El gesto que dispara esa función — Fn sola, presionada y soltada sin otra tecla de por medio — es exactamente el mismo que usa este atajo. Si el usuario tiene esa opción del sistema en algo distinto de "No hacer nada" (por ejemplo, el caso real que motivó esta nota: cambiar el idioma del teclado), cada uso del atajo de Scribe *también* dispara esa función del sistema. La única mitigación real es que el usuario ponga esa opción en "No hacer nada" en Ajustes del Sistema → Teclado — mismo requisito que documenta Whispr para su atajo por defecto (ver README). Si eso no fuera viable en un caso concreto, `HotkeyModifierTrigger` (ver siguiente sección) sigue siendo el punto de cambio para volver a Control u otro modificador.

**Actualización:** la afirmación de que "no hay evento que Scribe pueda interceptar o consumir para evitarlo" quedó desactualizada — ver la sección "Atajo global: `CGEventTap`..." más abajo, que reemplaza el mecanismo de detección por uno que sí puede consumir el evento (con la supresión de la función de sistema como hipótesis no verificada en hardware real, no como garantía).

## `HotkeyModifierTrigger`: el modificador del atajo, separado de su detección

`LiveGlobalHotkeyService.handleFlagsChanged` no compara `event.modifierFlags` inline contra una constante hardcodeada; delega en un `HotkeyModifierTrigger` (el `NSEvent.ModifierFlags` requerido) inyectado por el caller, con `.function` como valor por defecto (`.control` sigue existiendo como valor alternativo, del paso intermedio de la migración anterior). Esto no es una preferencia de usuario ni abre una UI de configuración — el atajo sigue sin ser configurable (ver `docs/ROADMAP.md`) — es solo un seam interno: si la validación en hardware real o de uso (limitaciones conocidas arriba) confirma que Fn no es viable en algún teclado o flujo de trabajo concreto, cambiarlo pasa por instanciar `LiveGlobalHotkeyService(trigger:)` con otro `HotkeyModifierTrigger` (por ejemplo, `.control`), sin tocar el monitor de eventos, el modelo de permisos de Accesibilidad, ni `DictationViewModel`.

## Monitor global + monitor local para el atajo (superseded)

`NSEvent.addGlobalMonitorForEvents` solo entrega eventos destinados a *otras* apps: en cuanto Scribe pasa a ser la app activa, el sistema deja de mandarle esos eventos al monitor global, y el atajo dejaba de andar apenas Scribe tenía el foco. `NSEvent.addLocalMonitorForEvents` cubre el caso complementario (solo eventos mientras Scribe es la app activa). Ambos caminos de despacho son mutuamente excluyentes para un mismo evento físico, así que instalar los dos monitores no duplica el disparo del atajo; ambos delegan en el mismo `handleFlagsChanged`. El monitor local no depende del permiso de Accesibilidad (solo el global lo necesita), y devuelve el evento sin modificar para no tragarse ningún cambio de modificador que el sistema o Scribe mismo necesiten ver.

**Superado por la sección siguiente:** este par de monitores fue reemplazado por un único `CGEventTap`, que cubre ambos casos (Scribe activa o no) con un solo mecanismo y, a diferencia de `NSEvent`, puede consumir el evento en vez de solo observarlo. Se deja esta sección para el registro histórico de por qué existían dos monitores en primer lugar.

## Atajo global: `CGEventTap` para suprimir la función de sistema del Fn, y modo manos libres (doble toque)

La sección anterior asumía que no había forma de interceptar el gesto Fn-sola antes de que macOS disparara su propia función de sistema, porque `NSEvent.addGlobalMonitorForEvents`/`addLocalMonitorForEvents` son observadores puros: pueden mirar el evento pasar, pero no consumirlo. Investigando cómo lo resuelve Whispr Flow (que sí logra que su atajo Fn no dispare "Presionar la tecla 🌐 Fn para:" del sistema, sin pedirle al usuario que lo ponga en "No hacer nada") se encontró el mecanismo real: un `CGEventTap` (`CGEvent.tapCreate` en `.cghidEventTap`, con `options: .defaultTap`, no `.listenOnly`) sí puede consumir el evento devolviendo `nil` desde el callback en vez de pasarlo (`Unmanaged.passRetained(event)`). Eso es lo que reemplaza el par de monitores `NSEvent`: `LiveGlobalHotkeyService` ahora instala un único `CGEventTap` sobre `flagsChanged`, y cuando `handleFlagsChanged` detecta un flanco real del trigger configurado, el callback devuelve `nil` en vez de pasar el evento — evitando, en la medida en que macOS respete la supresión de un tap con `.defaultTap`, que la función de sistema vea ese evento.

**No verificado en hardware real:** no hay forma en este entorno de confirmar que macOS efectivamente deja de disparar "Presionar la tecla 🌐 Fn para:" con este mecanismo — es la hipótesis de diseño (y lo que aparenta hacer Whispr Flow), pero la única prueba real es probarlo en una Mac con esa opción del sistema en algo distinto de "No hacer nada". Si no suprime la función de sistema en la práctica, la mitigación de la sección "Atajo global: de Control (push-to-talk) a Fn" (ponerla en "No hacer nada") sigue siendo necesaria como respaldo.

Esto trae un permiso nuevo: `CGEvent.tapCreate` requiere permiso de **Monitoreo de entrada** (Input Monitoring), no Accesibilidad — son dos permisos TCC distintos, y el atajo global usaba Accesibilidad hasta esta migración. A diferencia del monitor `NSEvent` viejo (que se instalaba igual sin el permiso, simplemente sin recibir eventos), `CGEvent.tapCreate` devuelve `nil` directamente si el permiso no está otorgado — no existe un estado intermedio "instalado pero sordo". Por eso `start()` y `currentStatus()` comparten `attemptTapCreation()`: reintenta crear el tap de forma perezosa en cada chequeo de estado, en vez de una sola vez al arrancar, para conservar el mismo comportamiento de "se cura solo" que tenía el diseño anterior (el usuario otorga el permiso en Ajustes del Sistema, y el próximo chequeo de estado lo detecta sin necesidad de reiniciar Scribe). `AutoPasteService` sigue usando su propio chequeo de Accesibilidad (`AXIsProcessTrusted()`) para su ⌘V sintético — es un permiso completamente separado, no afectado por este cambio.

### Modo manos libres: doble toque para bloquear la grabación

Wispr Flow permite, además del push-to-talk normal (mantener presionado, soltar para transcribir), tocar el atajo dos veces rápido para quedar grabando sin mantenerlo presionado ("bloqueado"), y un toque más para detener. Se replicó ese comportamiento sin tocar el contrato de `GlobalHotkeyServicing` (sigue exponiendo un único callback, `onHotkeyPressed`, sin distinguir presionar de soltar de cara afuera): `LiveGlobalHotkeyService` agrega un `PushToTalkState` interno (`.idle`/`.recording`/`.locked`) que decide, en cada flanco de bajada o subida del trigger, si corresponde emitir el callback, absorberlo en silencio, o (al soltar) esperar un `doubleTapWindow` breve (`NSEvent.doubleClickInterval` por defecto, igual que el resto de macOS) antes de emitir, por si ese soltar es en realidad el primer toque de un doble toque que todavía no llegó.

Transiciones: `.idle` + bajada → arranca y emite (push-to-talk normal); `.recording` + bajada → pasa a `.locked` sin emitir (es el segundo toque de un doble toque, ya está grabando); `.locked` + bajada → vuelve a `.idle` y emite de inmediato (un toque simple mientras está bloqueado detiene ahí mismo, sin esperar a que lo suelten); `.recording` + subida → programa la emisión diferida descrita arriba, y la re-chequea contra el estado actual antes de disparar (si en el ínterin llegó el segundo toque y el estado ya es `.locked`, esa emisión diferida se cancela en vez de detener una grabación que el usuario acaba de bloquear).

**Compromiso conocido:** el `doubleTapWindow` agrega esa misma latencia a *todo* soltar del atajo, no solo a los dobles toques reales — cada push-to-talk normal tarda `doubleTapWindow` extra en detener y empezar a transcribir. Tampoco está verificado en hardware real si esa ventana (el default de doble clic del sistema) se siente bien para un toque de teclado en vez de un clic de mouse; es un punto de ajuste si en uso real resulta muy larga o muy corta.

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
