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
| `scripts/00_borrar_tablas.sql` | Borra tablas y secuencias para volver a empezar. |
| `scripts/01_creacion_tablas.sql` | Entregable 7: creación de las 36 tablas, índices y secuencias de IDs. |
| `scripts/02_restricciones.sql` | Entregable 8: restricciones PRIMARY KEY, UNIQUE, CHECK y FOREIGN KEY. |
| `scripts/03_datos_prueba.sql` | Entregable 9: 4.414 filas de prueba que simulan 13 días de operación (fechas relativas a la fecha actual). |
| `scripts/04_consultas_sql.sql` | Entregable 10: las 15 consultas mínimas del enunciado. |
| `scripts/05_funciones.sql` | Entregable 11: funciones PL/SQL. |
| `scripts/06_procedimientos.sql` | Entregable 11: procedimientos almacenados. |
| `scripts/07_triggers.sql` | Entregable 11: triggers. |
| `scripts/08_vistas.sql` | Entregable 12: vistas para consultas operativas. |
| `scripts/09_pruebas_plsql.sql` | Entregable 13: pruebas de funciones, procedimientos, triggers y vistas. |
| `scripts/99_ejecutar_todo.sql` | Ejecuta en orden los scripts 00 a 09. |
| `scripts/10_demostracion.sql` | Entregable 16: llamadas listas para la demostración en vivo (se ejecuta aparte, después de `99`). |
| `NYC_metro_DDL.sql` | Exportación DDL del modelo (base de `scripts/01` y `scripts/02`). |
| `Documentacion/Documentacion_Metro_NYC.pdf` | **Documento final** con todos los entregables escritos y, como anexos, la salida de las consultas y de las pruebas. |
| `Documentacion/Evidencias/` | Salida de Oracle de las 15 consultas y de las pruebas de PL/SQL. |
| `Documentacion/versiones_anteriores/` | Primeras versiones de los puntos 1, 2, 4 y 6 (referencia). |
| `Diagramas/ER/` | Diagrama entidad-relación general y una subvista por módulo. |
| `Diagramas/` | Diagrama relacional general y diagramas relacionales por módulo. |

## Entregables

| # | Entregable | Dónde está |
|---|---|---|
| 1 | Documento de análisis del problema | Documento final, sección 1 |
| 2 | Identificación de entidades y atributos | Documento final, sección 2 |
| 3 | Modelo entidad-relación | `modelo_corregido/`, `Diagramas/ER/` y documento final, sección 3 |
| 4 | Diccionario de datos | Documento final, sección 4 (las 301 columnas, generado desde los scripts) |
| 5 | Transformación al modelo relacional | `Diagramas/` y documento final, sección 5 |
| 6 | Normalización hasta 3FN | Documento final, sección 6 |
| 7 | Script de creación en Oracle | `scripts/01_creacion_tablas.sql` |
| 8 | Restricciones PK, FK, UNIQUE, CHECK y NOT NULL | `scripts/02_restricciones.sql` (NOT NULL en `01`) |
| 9 | Datos de prueba | `scripts/03_datos_prueba.sql` |
| 10 | Consultas SQL | `scripts/04_consultas_sql.sql` y `Documentacion/Evidencias/10_consultas_sql.pdf` |
| 11 | Procedimientos, funciones y triggers | `scripts/05_funciones.sql`, `06_procedimientos.sql`, `07_triggers.sql` |
| 12 | Vistas | `scripts/08_vistas.sql` |
| 13 | Evidencias de pruebas | `scripts/09_pruebas_plsql.sql`, `Documentacion/Evidencias/` y documento final, sección 8 |
| 14 | Manual breve de uso | Documento final, sección 9 |
| 15 | Carátula | Documento final, portada |
| 16 | Presentación y demostración | Demostración: `scripts/10_demostracion.sql`. Presentación: en preparación |

## Orden de ejecución en Oracle SQL Developer

Ejecutar con **F5 (Run Script)** en un esquema de pruebas. La forma más simple es abrir `scripts/99_ejecutar_todo.sql` y ejecutarlo: borra todo y corre los demás en este orden:

1. `00_borrar_tablas.sql`
2. `01_creacion_tablas.sql`
3. `02_restricciones.sql`
4. `03_datos_prueba.sql` (al final sincroniza las secuencias de IDs con los datos cargados)
5. `04_consultas_sql.sql`
6. `05_funciones.sql`
7. `06_procedimientos.sql`
8. `07_triggers.sql`
9. `08_vistas.sql`
10. `09_pruebas_plsql.sql` (modifica datos de prueba: para volver al estado inicial, ejecutar de nuevo `99_ejecutar_todo.sql`)

Las fechas de los datos son relativas al día en que se ejecuta `03`: para una presentación conviene ejecutar `99_ejecutar_todo.sql` ese mismo día. Después se puede abrir `10_demostracion.sql` y ejecutarlo completo (F5) o por bloques para mostrar cada módulo en vivo.

> No ejecutar scripts de creación sobre un esquema que contenga datos que deban conservarse. Validar primero en una base de pruebas. La limpieza de archivos del sistema no sustituye las pruebas de ejecución de Oracle.

## Trabajo colaborativo con Git

- Mantener `modelo_corregido/` como la única fuente oficial del modelo.
- Antes de trabajar, revisar los cambios compartidos y sincronizar la rama de trabajo según el flujo del equipo.
- No agregar archivos temporales, metadatos de macOS (`._*`, `.DS_Store`) ni configuraciones locales del IDE.
- Después de verificar los cambios, revisar `git status` y confirmar que solo se incluyan archivos del proyecto.
