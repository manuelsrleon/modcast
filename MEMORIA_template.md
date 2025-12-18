## Nombre del equipo

Modcast Team


## Autores

  - David Javier Montes Fernández - david.j.montes - deivisi
  - Manuel Santamariña Ruiz de León - manuel.santamarina - manuelsrleon
  - Roi Millán Míguez - roi.millan.miguez - roimm1
  - Pablo Masián Carro - pablo.masian.carro - pablomasian
  - Antonio Pernas González - antonio.pernasg - antonioPernas
  
  
## Descripción de la aplicación

**Modcast** es un sistema P2P descentralizado de sincronización automática de mods (modificaciones) para videojuegos multijugador, desarrollado en Elixir. El sistema permite que los jugadores compartan contenido personalizado (modelos 3D, texturas, skins) sin necesidad de servidores centrales, facilitando a los desarrolladores la integración de contenido generado por usuarios en sus juegos.

### Requisitos Funcionales

1. **Gestión de Sesiones P2P**
   - Iniciar sesión como host
   - Unirse a sesión existente
   - Desconectarse de sesión
   - Mantener lista de jugadores conectados
### Formato

- Se utiliza `mix format` con la configuración estándar de Elixir.
- Indentación: 2 espacios.
- Longitud máxima de línea: 98 caracteres.

### Documentación

- Todos los módulos públicos deben incluir `@moduledoc`.
- Todas las funciones públicas deben incluir `@doc`.
- Se utiliza ExDoc para generar documentación HTML.
- Formato: Markdown para documentación.

### Guía de estilo

Se sigue [The Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide):

- Nombres de módulos: PascalCase (`Modcast.GameStateComponent`)
- Nombres de funciones: snake_case (`put_entity/2`)
- Nombres de variables: snake_case (`player_id`)
- Constantes: módulos de atributo (`@game_port 5050`)
- Pattern matching preferido sobre condicionales
- Uso de pipe operator `|>` para cadenas de transformación
- Guards para validación de tipos cuando sea apropiadoe Entidades (Sync Status Ledger)**
   - Crear entidades vinculadas a mods
   - Transferir propiedad de entidades entre jugadores
   - Mantener registro sincronizado entre todos los peers
   - Consultar entidades por jugador/mod/asset

4. **Interfaz con Motor de Juego (MSAPI)**
   - Comunicación TCP/JSON
   - Comandos: start_session, join_session, select_mods, register_entity, start_game
   - Eventos asíncronos: mod_ready, game_started, entity_created

### Requisitos No Funcionales

1. **Disponibilidad**
   - Arquitectura P2P sin punto único de fallo
   - Resistencia a desconexiones de peers
   - Reconexión automática

2. **Rendimiento**
   - Límite de tamaño de archivo: 10 MB por mod
   - Transferencias simultáneas entre múltiples peers
   - Detección de mods duplicados por hash

3. **Consistencia**
   - Resolución de conflictos mediante Last Write Wins (LWW)
   - Versionado del Sync Status Ledger
   - Sincronización periódica automática

4. **Interoperabilidad**
   - Interfaz agnóstica al motor de juego
   - Protocolo JSON sobre TCP
   - Formato de mods: archivos ZIP estándar

5. **Seguridad**
   - Validación de integridad mediante MD5
   - Validación de sesión en transferencias
   - Verificación de formato de archivos


# Información a incluir en la documentación del proyecto

## Normas para el código

- Documentar el código con _ExDoc_.

- Documentar las normas para  el formato del código.
  Recomendación: usar `mix format` y documentar la configuración del mismo.

- Crear, y cumplir, una guía de estilo para el código.
  Recomendación:
  [https://github.com/christopheradams/elixir_style_guide](The Elixir
  Style Guide).
  
  
## Normas para el proyecto y el control de versiones

### Estructura del proyecto



### Mensajes de commit

Formato: 

**Tipos:**

**Ejemplo:**


### Estrategia de ramas

**Feature Branch Workflow:**

- `main`: Rama principal estable (releases)
- `develop`: Rama de integración
- `F##-feature-name`: Ramas de features individuales

**Proceso:**
1. Crear rama desde `develop`: `git checkout -b F04-SSL-implementation`
2. Desarrollar y hacer commits
3. Merge a `develop` cuando esté completo
4. `develop` se mergea a `main` para releases

**Ramas del proyecto:**
- F01: Godot project initialization
- F02: GSC implementation  
- F03: MSAPI Initialization
- F04: SSL implementation
- F08: MDF player car definition


## Documentación de la aplicación

### Aplicación

**Ver:** `README.md` y `documentatio.md` para documentación completa.

#### Casos de Uso Principales

**UC1: Compartir mods en sesión multijugador**
- Actor: Jugadores (2-N)
- Flujo:
  1. Player1 inicia sesión con mod personalizado
  2. Player2 se une a la sesión
  3. Sistema detecta mod faltante en Player2
  4. Transferencia automática P2P del mod
  5. Verificación de integridad (MD5)
  6. Ambos jugadores pueden ver el contenido personalizado

**UC2: Registrar entidad con mod en el juego**
- Actor: Motor de juego
- Flujo:
  1. Juego crea objeto (ej: coche del jugador)
  2. Vincula objeto a mod mediante `register_entity`
  3. SSL registra la relación entity-player-mod
  4. Broadcast a todos los peers
  5. Peers cargan el mod correcto para ese objeto

**UC3: Transferir propiedad de entidad**
- Actor: Motor de juego
- Flujo:
  1. Evento del juego (ej: jugador abandona vehículo)
  2. Llamada a `transfer_entity` con nuevo propietario
  3. SSL actualiza registro con timestamp
  4. Sincronización con todos los peers
  5. Juego actualiza lógica de propiedad
  

### Diseño

**Ver:** `documentatio.md` para diagramas de arquitectura completos.

#### Arquitectura Principal

**Estilo arquitectónico:** P2P (Peer-to-Peer) con componentes de Event-Driven Architecture

**Componentes principales:**
1. **MSAPI** - Interfaz JSON/TCP con motor de juego (puerto 5050)
2. **GSC (Game State Component)** - Orquestador P2P (GenServer)
3. **SSL (Sync Status Ledger)** - Registro distribuido CRDT-like
4. **FTC (File Transfer Component)** - Transferencia de archivos
5. **Persistence** - Almacenamiento local DETS

#### Decisiones de Diseño (ADR)

**ADR-001: Arquitectura P2P sin servidor central**
- Contexto: Evitar costos de servidor y punto único de fallo
- Decisión: Arquitectura P2P pura con mesh network
- Consecuencias: Mayor complejidad en sincronización, pero mayor disponibilidad

**ADR-002: Protocolo JSON sobre TCP**
- Contexto: Necesidad de interoperar con múltiples motores de juego
- Decisión: API basada en JSON sobre TCP (puerto 5050)
- Consecuencias: Facilita integración pero sacrifica algo de rendimiento

**ADR-003: Hash MD5 para identificación de mods**
- Contexto: Necesidad de identificar archivos únicamente
- Decisión: Usar MD5 hash del archivo completo
- Consecuencias: Rápido y suficiente para el scope del proyecto

**ADR-004: Resolución de conflictos LWW (Last Write Wins)**
- Contexto: Conflictos en SSL cuando peers editan simultáneamente
- Decisión: El cambio más reciente (por timestamp) prevalece
- Consecuencias: Simple y determinista, pero puede perder datos

**ADR-005: GenServer para gestión de estado P2P**
- Contexto: Necesidad de manejar estado compartido y concurrencia
- Decisión: Usar GenServer para GSC y MSAPI
- Consecuencias: Modelo de actores facilita manejo de mensajes P2P

#### Tácticas Aplicadas

**Disponibilidad:**
- Redundancia: Mesh P2P (sin SPOF)
- Heartbeat: Detección de peers desconectados
- Exception handling: Supervisión con restart strategies

**Rendimiento:**
- Caching: Almacenamiento persistente de mods en `./mods`
- Deduplicación: Hash-based detection de archivos duplicados
- Concurrencia: Task.Supervisor para conexiones simultáneas

**Consistencia:**
- Versionado: Contador incremental en SSL
- Conflict resolution: LWW basado en timestamps
- Sincronización periódica: Full sync broadcasts

**Seguridad:**
- Validación de integridad: MD5 hash checking
- Session validation: Verificar session_id en transfers
- Input validation: Pattern matching y guards


### Instrucciones

#### Requisitos previos

- Elixir 1.12 o superior
- Erlang/OTP 24 o superior
- Python 3.8+ (para tests de integración)
- Godot 4.x (opcional, para demo)

#### Compilación

```bash
# Clonar repositorio
git clone https://github.com/[team]/modcast.git
cd modcast

# Instalar dependencias
mix deps.get

# Compilar
mix compile
```

#### Ejecución

**Iniciar servidor Modcast:**
```bash
# Terminal 1 - Player 1
iex -S mix

# En la consola IEx
iex> Modcast.MSAPI.start_link()
```

**Integración con juego:**
```python
import socket
import json

# Conectar al puerto MSAPI
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.connect(("127.0.0.1", 5050))

# Iniciar sesión
cmd = {"action": "start_session", "session": "game_123", "player": "Player1"}
sock.send((json.dumps(cmd) + "\n").encode())

# Seleccionar mods
cmd = {"action": "select_mods", "player": "Player1", "hashes": ["abc123"]}
sock.send((json.dumps(cmd) + "\n").encode())
```

#### Tests

**Tests unitarios (Elixir):**
```bash
# Todos los tests
mix test

# Tests específicos
mix test test/sync_status_ledger_test.exs

# Con coverage
mix test --cover
```

**Tests de integración (Python):**
```bash
cd tests
python test_file_transfer.py
```

#### Demo con Godot

```bash
# 1. Abrir Godot
godot demo/car-sumo/project.godot

# 2. En otra terminal, iniciar Modcast
iex -S mix

# 3. Ejecutar juego desde Godot
# El juego se conectará automáticamente al puerto 5050
```


### Tests

Documentación de los tests implementados:

  - Tipos de tests.
  
  - Escenarios cubiertos por las pruebas.
  
  - Escenarios no cubiertos por las pruebas.


# Presentación

Durante la última clase del cuatrimestre cada grupo realizará una
breve presentación del proyecto desarrollado.

  - Deben participar todos los integrantes del grupo.
  
  - El material audiovisual de apoyo a la presentación se debe incluir
    en este repositorio.
	
  - También se debe incluir en el repositorio las instrucciones
    necesarias para replicar la demostración realizada durante la
    presentación.
	
  - La presentación debe contener los siguientes aspectos:
  
      - Presentación del proyecto, incluyendo:
  
        * Descripción de los requisitos funcionales
          
        * Descripción de los requisitos no funcionales
          
      - Presentación de la solución arquitectónica diseñada, incluyendo:
  
        * Representación C4
          
        * Tácticas aplicadas para afrontar los requisitos no
          funcionales
          
      - Aspectos relevantes de la implementación realizada:
  
        * Estructura del proyecto en el repositorio
          
        * Elementos destacados (posible uso de Agents, Tasks,
          GenServer, Supervisor, ...)
          
        * Alcance de las pruebas
          
        * Documentación
		
		* Cualquier otro aspecto que pudiera ser relevante
          
      - Realización de una demostración de funcionamiento

  - La presentación seguirá el guión que el equipo de desarrollo
    considere oportuno. No es necesario seguir el orden establecido en
    el punto anterior.


Al finalizar la exposición, habrá una ronda de preguntas por parte de
los asistentes: profesorado y estudiantes.


# Guía para la evaluación

La evaluación de la práctica se basa en los siguientes criterios:

- Arquitectura distribuida. 1 punto.

	Se considera si se ha desarrollado una arquitectura distribuida.
    Para considerar si la arquitectura es distribuida no se tienen en
    cuenta los posibles clientes de la aplicación.
  
  
- Calidad del diseño. Hasta 3 puntos.

	Algunos indicadores típicos son:
	
    - La arquitectura o combinación/adaptación de la/s arquitectura/s
      es adecuada para resolver el proyecto planteado.
   
    - El desarrollo de la arquitectura es correcto.

    - Las tácticas aplicadas resuelven los requisitos no funcionales.
   
    - Las tácticas encajan y se aplican correctamente a la
      arquitectura diseñada.
   
    - La documentación de la arquitectura no se limita a los diagramas
      C4.
	
	
- Calidad del desarrollo. Hasta 3 puntos.

	Algunos indicadores típicos son:
	
    - Existe una planificación y asignación eficaz de tareas.
	
    - El uso del control de versiones es coherente con las normas
      establecidas, y se corresponde con la asignación de tareas a los
      miembros del equipo.

    - Se han desarrollado pruebas a distintos niveles: unidad,
      integración, sistema, ... y cubren los aspectos claves de la
      aplicación.
	  
    - El estilo del código es homogéneo en todo el proyecto y adecuado
      para el lenguaje de programación empleado.
	  
    - Se usan las librerías estándar, herramientas y abstracciones
      habituales. Por ejemplo, en _elixir_: _behaviours_, _mix_,
      _heartbeat_, ...
	  
    - No se detectan bugs ni problemas de rendimiento.

    - El proyecto se ha implementado en su totalidad. No existen
      partes de la aplicación diseñadas, pero no implementadas.

	  
- Calidad de la documentación. Hasta 1 punto.

	Se tendrá en cuenta que:
	
    - Están documentados todos los aspectos recogidos en la sección de
      documentación: requisitos funcionales y no funcionales, tácticas
      implementadas, decisiones de diseño, diagramas C4, etc.
	  
    - El código y las pruebas están documentados.
	
    - Se han establecido las normas para la redacción de mensajes de
      commit, estilo de código, etc.
	  
    - Contiene toda la información solicitada en este README.
	
	
- Calidad de la presentación. Hasta 1 punto.

	Se valorará:
	
    - El cumplimiento de las instrucciones dadas para las
      presentaciones.
	
    - La claridad de la exposición.
	
    - La participación en el resto de presentaciones.
   

- Calidad global del proyecto. Hasta 1 punto.

	En este apartado el profesorado evaluará cualquier otro aspecto no
    contenido en los apartados anteriores.
          
          


> [!CAUTION]
> Si se detecta una participación desigual en el desarrollo
> del proyecto, el profesorado puede optar por una evaluación
> individual del trabajo.
