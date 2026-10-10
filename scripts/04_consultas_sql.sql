-- ============================================================================
-- PROYECTO: METRO DE NUEVA YORK (MTA NYCT)
-- ENTREGABLE: 15 CONSULTAS SQL REQUERIDAS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. ¿Qué líneas pasan por una estación determinada? (Ej. primera estación registrada)
-- ----------------------------------------------------------------------------
SELECT E.NOMBRE AS ESTACION, L.COD_LINEA, L.NOMBRE AS LINEA, L.COLOR_HEX
FROM ESTACION E
JOIN LINEA_ESTACION LE ON E.ID_ESTACION = LE.ID_ESTACION
JOIN LINEA L ON LE.COD_LINEA = L.COD_LINEA
WHERE E.ID_ESTACION = (SELECT MIN(ID_ESTACION) FROM ESTACION)
ORDER BY L.COD_LINEA;

-- ----------------------------------------------------------------------------
-- 2. ¿Cuáles son las estaciones de una ruta y en qué orden se visitan?
-- ----------------------------------------------------------------------------
SELECT R.COD_RUTA, DR.ORDEN_PARADA, E.NOMBRE AS ESTACION, DR.PERMITE_PARADA_PASAJERO
FROM RUTA R
JOIN DETALLE_RUTA DR ON R.ID_RUTA = DR.ID_RUTA
JOIN ESTACION E ON DR.ID_ESTACION = E.ID_ESTACION
WHERE R.ID_RUTA = (SELECT MIN(ID_RUTA) FROM RUTA)
ORDER BY DR.ORDEN_PARADA ASC;

-- ----------------------------------------------------------------------------
-- 3. ¿Qué estaciones permiten transferencia entre líneas?
-- ----------------------------------------------------------------------------
SELECT E.NOMBRE AS ESTACION_TRANSFERENCIA, T.COD_LINEA_ORIGEN, T.COD_LINEA_DESTINO, T.TIEMPO_ESTIMADO_MIN
FROM TRANSFERENCIA T
JOIN ESTACION E ON E.ID_ESTACION = T.ID_ESTACION
ORDER BY E.NOMBRE, T.COD_LINEA_ORIGEN, T.COD_LINEA_DESTINO;

-- ----------------------------------------------------------------------------
-- 4. ¿Qué viajes están programados para una fecha específica?
-- ----------------------------------------------------------------------------
SELECT V.COD_VIAJE, R.COD_RUTA, V.HORA_PROGRAMADA_SALIDA, V.ESTADO_VIAJE
FROM VIAJE_PROGRAMADO V
JOIN RUTA R ON V.ID_RUTA = R.ID_RUTA
WHERE TRUNC(V.FECHA_VIAJE) = TO_DATE('2026-10-10', 'YYYY-MM-DD')
ORDER BY V.HORA_PROGRAMADA_SALIDA ASC;

-- ----------------------------------------------------------------------------
-- 5. ¿Qué viajes presentan retrasos mayores a 15 minutos?
-- ----------------------------------------------------------------------------
SELECT V.COD_VIAJE, V.HORA_PROGRAMADA_SALIDA, V.HORA_REAL_SALIDA,
       ROUND((CAST(V.HORA_REAL_SALIDA AS DATE) - CAST(V.HORA_PROGRAMADA_SALIDA AS DATE)) * 1440, 0) AS MINUTOS_RETRASO
FROM VIAJE_PROGRAMADO V
WHERE V.HORA_REAL_SALIDA IS NOT NULL
  AND (CAST(V.HORA_REAL_SALIDA AS DATE) - CAST(V.HORA_PROGRAMADA_SALIDA AS DATE)) * 1440 > 15
ORDER BY MINUTOS_RETRASO DESC;

-- ----------------------------------------------------------------------------
-- 6. ¿Qué trenes están disponibles para operación?
-- ----------------------------------------------------------------------------
SELECT T.COD_IDENTIFICADOR, M.NOMBRE_MODELO, T.CAPACIDAD_TOTAL, T.ESTADO_OPERATIVO
FROM TREN T
JOIN MODELO_TREN M ON T.ID_MODELO = M.ID_MODELO
WHERE UPPER(T.ESTADO_OPERATIVO) IN ('DISPONIBLE', 'OPERATIVO', 'ACTIVO')
ORDER BY T.COD_IDENTIFICADOR;

-- ----------------------------------------------------------------------------
-- 7. ¿Qué trenes tienen inspección o mantenimiento vencido?
-- ----------------------------------------------------------------------------
SELECT COD_IDENTIFICADOR, FECHA_PROX_INSPECCION, ESTADO_OPERATIVO
FROM TREN
WHERE FECHA_PROX_INSPECCION < SYSDATE;

-- ----------------------------------------------------------------------------
-- 8. ¿Qué conductor fue asignado a cada viaje?
-- ----------------------------------------------------------------------------
SELECT V.COD_VIAJE, E.ID_EMPLEADO, E.NOMBRE || ' ' || E.APELLIDO AS CONDUCTOR, AP.ROL_DESEMPENADO
FROM VIAJE_PROGRAMADO V
JOIN ASIGNACION_PERSONAL AP ON V.ID_VIAJE = AP.ID_VIAJE
JOIN EMPLEADO E ON AP.ID_EMPLEADO = E.ID_EMPLEADO;

-- ----------------------------------------------------------------------------
-- 9. ¿Cuántos pasajeros utilizaron cada línea durante un período?
-- ----------------------------------------------------------------------------
SELECT L.COD_LINEA, L.NOMBRE AS LINEA, COUNT(VA.ID_VALIDACION) AS TOTAL_PASAJEROS
FROM LINEA L
JOIN LINEA_ESTACION LE ON L.COD_LINEA = LE.COD_LINEA
JOIN DISPOSITIVO_ACCESO DA ON LE.ID_ESTACION = DA.ID_ESTACION
JOIN VALIDACION_ACCESO VA ON DA.ID_DISPOSITIVO = VA.ID_DISPOSITIVO
WHERE VA.FECHA_HORA_INGRESO BETWEEN TO_TIMESTAMP('2026-10-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS')
                                AND TO_TIMESTAMP('2026-10-31 23:59:59', 'YYYY-MM-DD HH24:MI:SS')
GROUP BY L.COD_LINEA, L.NOMBRE
ORDER BY TOTAL_PASAJEROS DESC;

-- ----------------------------------------------------------------------------
-- 10. ¿Cuánto dinero se recaudó por día, estación y tipo de tarifa?
-- ----------------------------------------------------------------------------
SELECT TRUNC(VA.FECHA_HORA_INGRESO) AS FECHA, E.NOMBRE AS ESTACION, CTT.NOMBRE_TARIFA,
       SUM(VA.MONTO_COBRADO) AS TOTAL_RECAUDADO
FROM VALIDACION_ACCESO VA
JOIN DISPOSITIVO_ACCESO DA ON VA.ID_DISPOSITIVO = DA.ID_DISPOSITIVO
JOIN ESTACION E ON DA.ID_ESTACION = E.ID_ESTACION
JOIN CAT_TIPO_TARIFA CTT ON VA.ID_TIPO_TARIFA_APLICADA = CTT.ID_TIPO_TARIFA
GROUP BY TRUNC(VA.FECHA_HORA_INGRESO), E.NOMBRE, CTT.NOMBRE_TARIFA
ORDER BY FECHA DESC, ESTACION ASC;

-- ----------------------------------------------------------------------------
-- 11. ¿Cuáles son las estaciones con mayor flujo de pasajeros?
-- ----------------------------------------------------------------------------
SELECT E.ID_ESTACION, E.NOMBRE AS ESTACION, E.BOROUGH, COUNT(VA.ID_VALIDACION) AS TOTAL_ACCESOS
FROM ESTACION E
JOIN DISPOSITIVO_ACCESO DA ON E.ID_ESTACION = DA.ID_ESTACION
JOIN VALIDACION_ACCESO VA ON DA.ID_DISPOSITIVO = VA.ID_DISPOSITIVO
GROUP BY E.ID_ESTACION, E.NOMBRE, E.BOROUGH
ORDER BY TOTAL_ACCESOS DESC;

-- ----------------------------------------------------------------------------
-- 12. ¿Qué incidentes permanecen abiertos?
-- ----------------------------------------------------------------------------
SELECT NUM_INCIDENTE, TIPO_INCIDENTE, DESCRIPCION, NIVEL_SEVERIDAD, FECHA_HORA_INICIO
FROM INCIDENTE
WHERE UPPER(ESTADO) IN ('ABIERTO', 'EN PROCESO', 'PENDIENTE')
ORDER BY FECHA_HORA_INICIO DESC;

-- ----------------------------------------------------------------------------
-- 13. ¿Qué línea acumuló más retrasos?
-- ----------------------------------------------------------------------------
SELECT L.COD_LINEA, L.NOMBRE AS LINEA,
       COUNT(V.ID_VIAJE) AS VIAJES_CON_RETRASO,
       NVL(SUM(ROUND((CAST(V.HORA_REAL_SALIDA AS DATE) - CAST(V.HORA_PROGRAMADA_SALIDA AS DATE)) * 1440, 0)), 0) AS MINUTOS_TOTALES_RETRASO
FROM LINEA L
JOIN RUTA R ON L.COD_LINEA = R.COD_LINEA
JOIN VIAJE_PROGRAMADO V ON R.ID_RUTA = V.ID_RUTA
WHERE V.HORA_REAL_SALIDA > V.HORA_PROGRAMADA_SALIDA
GROUP BY L.COD_LINEA, L.NOMBRE
ORDER BY MINUTOS_TOTALES_RETRASO DESC;

-- ----------------------------------------------------------------------------
-- 14. ¿Qué tarjetas fueron bloqueadas o vencieron?
-- ----------------------------------------------------------------------------
SELECT TP.ID_TARJETA, TP.NUMERO_TARJETA, TP.TIPO_TECNOLOGIA, TP.SALDO_DISPONIBLE, TP.FECHA_VENCIMIENTO, TP.ESTADO
FROM TARJETA_PAGO TP
WHERE TP.ESTADO = 'Bloqueada'
   OR TP.FECHA_VENCIMIENTO < SYSDATE
ORDER BY TP.FECHA_VENCIMIENTO ASC;

-- ----------------------------------------------------------------------------
-- 15. ¿Qué técnicos participaron en una orden de mantenimiento?
-- ----------------------------------------------------------------------------
SELECT OM.ID_ORDEN, OM.NUM_ORDEN, OM.FECHA_PROGRAMADA, OM.ESTADO_ORDEN,
       E.ID_EMPLEADO, E.NOMBRE || ' ' || E.APELLIDO AS TECNICO,
       MT.HORAS_TRABAJADAS, MT.ES_LIDER_CUADRILLA
FROM ORDEN_MANTENIMIENTO OM
JOIN MANTENIMIENTO_TECNICO MT ON OM.ID_ORDEN = MT.ID_ORDEN
JOIN EMPLEADO E ON MT.ID_EMPLEADO_TECNICO = E.ID_EMPLEADO
ORDER BY OM.ID_ORDEN, E.APELLIDO;
