# Sistema de Gestión del Metro de Nueva York

Repositorio académico para el diseño e implementación de una base de datos Oracle para una versión simplificada del metro de Nueva York.

## Fuente oficial del modelo

La única versión del modelo que debe utilizarse para realizar cambios es `modelo_corregido/`. No mantener ni editar modelos paralelos. El DDL exportado está en `NYC_metro_DDL.sql` y los scripts de trabajo están en `scripts/`.

## Módulos del sistema

1. **Red e infraestructura:** líneas, estaciones, plataformas, servicios y transferencias.
2. **Rutas y horarios:** rutas, detalles de recorrido, horarios y viajes programados.
3. **Flota:** depósitos, modelos de tren, trenes, vagones y composición.
4. **Personal:** cargos, empleados, certificaciones, turnos y ausencias.
5. **Pasajeros y tarjetas:** pasajeros, tarjetas, tarifas, recargas y viajes de pasajeros.
6. **Mantenimiento:** equipos, órdenes, técnicos, repuestos y sus asignaciones.
7. **Incidentes:** incidentes, elementos afectados, viajes afectados y bitácora.

## Contenido principal

| Ruta | Contenido |
|---|---|
| `modelo_corregido/` | Modelo oficial de Oracle SQL Developer Data Modeler. |
| `scripts/01_creacion_tablas.sql` | Creación de tablas. |
| `scripts/02_restricciones.sql` | Restricciones complementarias. |
| `scripts/03_datos_prueba.sql` | Inserción de datos de prueba. |
| `scripts/04_consultas_sql.sql` | Consultas SQL de verificación y explotación. |
| `NYC_metro_DDL.sql` | Exportación DDL del modelo. |
| `Documentacion/` | Documentos de los entregables disponibles. |
| `Diagramas/` | Diagrama relacional general y diagramas modulares. |

## Orden de ejecución en Oracle SQL Developer

Ejecutar los scripts con **F5 (Run Script)** y en este orden, preferiblemente en un esquema de pruebas vacío:

1. `scripts/01_creacion_tablas.sql`
2. `scripts/02_restricciones.sql`
3. `scripts/03_datos_prueba.sql`
4. `scripts/04_consultas_sql.sql`

El archivo `05_sincronizar_secuencias.sql` **no está incluido en esta copia del repositorio**. Si se incorpora una versión compatible con el modelo oficial, revisar su contenido y ejecutarlo después de cargar los datos de prueba (`03_datos_prueba.sql`) y antes de realizar nuevas inserciones que dependan de secuencias o identidades.

> No ejecutar scripts de creación sobre un esquema que contenga datos que deban conservarse. Validar primero en una base de pruebas. La limpieza de archivos del sistema no sustituye las pruebas de ejecución de Oracle.

## Trabajo colaborativo con Git

- Mantener `modelo_corregido/` como la única fuente oficial del modelo.
- Antes de trabajar, revisar los cambios compartidos y sincronizar la rama de trabajo según el flujo del equipo.
- No agregar archivos temporales, metadatos de macOS (`._*`, `.DS_Store`) ni configuraciones locales del IDE.
- Después de verificar los cambios, revisar `git status` y confirmar que solo se incluyan archivos del proyecto.
