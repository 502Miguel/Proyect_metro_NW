# Sistema de Gestión - Metro de Nueva York (Proyect_metro_NW)

Este repositorio contiene la arquitectura y modelo de base de datos para la gestión del sistema de transporte subterráneo de Nueva York, compuesto por 36 entidades (30 entidades y 6 entidades asociativas) organizadas en 7 módulos.

## Módulos del Sistema

### 1. Red e Infraestructura
Gestiona la estructura física del sistema:
- **LINEA, ESTACION, LINEA_ESTACION:** Trazado de líneas, terminales de origen y destino, orden de secuencias, distancias y tiempos entre estaciones.
- **PLATAFORMA, SERVICIO_ESTACION, CAT_SERVICIO:** Plataformas de cada estación y catálogo de servicios al usuario.
- **TRANSFERENCIA:** Líneas entre las que se puede transbordar en una estación y tiempo estimado.

### 2. Rutas y Horarios
Gestiona la logística y los viajes:
- **RUTA, DETALLE_RUTA:** Rutas operativas (locales, expresas, nocturnas) con estación de origen y destino, y secuencia de paradas indicando si el tren se detiene o solo pasa.
- **HORARIO:** Horarios por tipo de día con frecuencia y vigencia.
- **VIAJE_PROGRAMADO:** Ejecución concreta de una ruta con horas programadas y reales, tren y conductor asignados.

### 3. Flota de Trenes
Gestiona el material rodante:
- **DEPOSITO, MODELO_TREN, TREN:** Depósitos, modelos por división (A y B) y trenes con kilometraje e inspecciones.
- **VAGON, COMPOSICION_TREN:** Vagones individuales e historial de su asignación y posición en cada tren.

### 4. Personal
Gestiona los recursos humanos operativos:
- **CARGO, EMPLEADO:** Estructura organizativa y supervisores.
- **CERTIFICACION, CERTIFICACION_MODELO:** Certificaciones y modelos de tren autorizados.
- **TURNO, AUSENCIA:** Turnos por lugar de trabajo, asistencia, ausencias, permisos, vacaciones y sustituciones.

### 5. Pasajeros y Tarjetas
- **PASAJERO, TARJETA:** Pasajeros registrados y tarjetas personales o anónimas.
- **TARIFA:** Tarifas con historial de vigencia.
- **RECARGA, VIAJE_PASAJERO:** Recargas de saldo y registro de ingresos y salidas.

### 6. Mantenimiento
- **EQUIPO:** Equipos mantenibles (trenes, vagones, vías, señales, plataformas, elevadores y escaleras eléctricas).
- **ORDEN_MANTENIMIENTO, ORDEN_TECNICO:** Órdenes de mantenimiento y técnicos asignados.
- **REPUESTO, ORDEN_REPUESTO:** Repuestos utilizados con cantidad y costo.

### 7. Incidentes
- **INCIDENTE:** Incidentes operativos por tipo y severidad.
- **INCIDENTE_ELEMENTO, INCIDENTE_VIAJE:** Elementos de la red y viajes afectados.
- **BITACORA:** Registro de cambios importantes.

## Contenido del Repositorio

| Carpeta | Contenido |
|---|---|
| `modelo_corregido/` | **Modelo oficial** en Oracle SQL Developer Data Modeler, con una subvista por módulo |
| `modelo_anterior/` | Primera versión del modelo (referencia) |

## Reglas para Trabajar
- Solo una persona edita el modelo (`modelo_corregido.dmd`).
- Antes de trabajar hacer `git pull`, y al subir algo avisar en el grupo.
