# Sistema de Gestión - Metro de Nueva York (Proyect_metro_NW)

Este repositorio contiene la arquitectura y modelo de base de datos para la gestión del sistema de transporte subterráneo de Nueva York, compuesto por 20 entidades organizadas en 4 módulos principales.

## Módulos del Sistema

### 1. Red e Infraestructura
Gestiona la estructura física del sistema:
- **LINEA, ESTACION, LINEA_ESTACION:** Trazado de líneas, orden de secuencias y distancias.
- **PLATAFORMA, SERVICIO_ESTACION, CAT_SERVICIO_ESTACION:** Control de accesos, infraestructura de plataformas y catálogo de servicios al usuario.
- **TRANSFERENCIA:** Conexiones físicas e intermodales entre estaciones.

### 2. Rutas y Horarios
Gestiona la logística y los viajes:
- **RUTA, DETALLE_RUTA:** Distinción entre líneas físicas y rutas operativas (expresas y locales).
- **HORARIO, VIAJE_PROGRAMADO, EXCEPCION_HORARIO:** Planificación temporal de salidas, frecuencias e incidencias en el servicio.

### 3. Flota de Trenes
Gestiona el material rodante:
- **MODELO_TREN, TREN, VAGON:** Clasificación por divisiones (División A y B), unidades físicas y vagones individuales.
- **ASIGNACION_TREN_VIAJE:** Control de qué tren realiza cada viaje programado.

### 4. Personal y Tripulación
Gestiona los recursos humanos operativos:
- **EMPLEADO, CARGO, TURNO:** Estructura organizativa, licencias y turnos de trabajo.
- **ASIGNACION_PERSONAL_TRIPULACION:** Asignación de personal fijo a estaciones y tripulación a viajes.