/* =====================================================================
   SISTEMA DE GESTION - METRO DE NUEVA YORK
   99 - EJECUTAR TODO DESDE CERO
   Borra todo y vuelve a crear la base de datos completa en orden:
   tablas (script exportado del modelo) -> datos -> funciones ->
   procedimientos -> triggers -> vistas -> pruebas.

   Abrir este archivo en SQL Developer (conexion METRO) y ejecutar con F5.
   ===================================================================== */

@@00_borrar_tablas.sql
@@../NYC_metro_DDL.sql
@@02_datos_prueba.sql
@@03_funciones.sql
@@04_procedimientos.sql
@@05_triggers.sql
@@06_vistas.sql
@@07_pruebas_plsql.sql
