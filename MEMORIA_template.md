# Práctica grupal

El desarrollo de esta práctica incluye la propuesta, diseño, documentación,
implementación, testing y presentación de un sistema propuesto por el grupo
de trabajo.

La propuesta se debe realizar teniendo en cuenta los siguientes
aspectos:

  - Debe incluir la descripción tanto de los requisitos funcionales,
    como no funcionales.

  - Debe ser validada por el profesor de la asignatura.

  - La funcionalidad del sistema no es el objetivo de la práctica.

  - El diseño de la aplicación debe seguir alguna de las
    arquitecturas estudiadas durante el cuatrimestre, una combinación
    de las mismas, o alguna otra arquitectura propuesta por el
    grupo. Dicho diseño tiene que ser una solución efectiva para el
    problema planteado.
	
  - Los requisitos no funcionales más habituales están relacionados
    con el rendimiento, disponibilidad y seguridad, aunque no son los
    únicos. En cualquier caso, dichos requisitos deben materializarse
    en la aplicación de las tácticas estudiadas durante el cuatrimestre.




# Datos a cubrir en este README

## Nombre del equipo

N/A El nombre usado en moodle, si existe.


## Autores

  [X] - Nombre, apellidos, login udc, login github
  
  
## Descripción de la aplicación

Breve descripción del sistema desarrollado, así como los requisitos
funcionales y no funcionales del mismo, y cualquier otra información
que contribuya a una mejor comprensión del mismo.


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

- Estructura del proyecto.
  Recomendación: basarse en la estructura creada por `mix new`.

- Formato y convenciones para la redacción de mensajes de
  commit. Ejemplo:
  [https://www.freecodecamp.org/news/how-to-write-better-git-commit-messages/](How
  to Write Better Git Commit Messages)
  
- Si se usan ramas en el repositorio, estrategia para la gestión de
  ramas. Ejemplos:
  [https://www.abtasty.com/blog/git-branching-strategies/](What Are
  the Best Git Branching Strategies)


## Documentación de la aplicación

### Aplicación

  - Requisitos funcionales.
  
  - Requisitos no funcionales.
  
  - Cualquier otra documentación relacionada. Por ejemplo: casos de
    uso.
  

### Diseño

Toda la documentación propia de un desarrollo software. En los
siguientes formatos:

- Documentación del diseño. Los cuatro niveles del C4. Ficheros en
  formato PDF o PNG.

- Decisiones de diseño. No hay formato concreto, pero se pueden
  encontrar algunas ideas [https://adr.github.io/](aquí). Incluir:
 
    - Decisiones relativas a la arquitectura y sus variantes.
	
	- Decisiones relativas a las tácticas.
	
	- Otros tipos de decisiones adoptadas a lo largo del proyecto.


### Instrucciones

Instrucciones para compilar, desplegar, utilizar, ejecutar los tests, ...


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
