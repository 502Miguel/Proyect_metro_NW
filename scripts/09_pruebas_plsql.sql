/* =====================================================================
   SISTEMA DE GESTION - METRO DE NUEVA YORK
   ENTREGABLE 13: PRUEBAS DE FUNCIONES, PROCEDIMIENTOS, TRIGGERS Y VISTAS
   (sirve como evidencia de pruebas, entregable 13)

   Ejecutar en SQL Developer con "Run Script" (F5), despues de 01 a 08 y
   con los datos de prueba cargados. Cada prueba imprime "OK ..." si el
   resultado es el esperado; las que deben fallar imprimen "OK rechazado".

   OJO: este script MODIFICA los datos (programa viajes, recarga tarjetas,
   cancela viajes...). Para volver al estado inicial: ejecutar de nuevo
   99_ejecutar_todo.sql (o 00 -> 01 -> ... -> 08).
   ===================================================================== */

SET SERVEROUTPUT ON SIZE UNLIMITED
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI';
SET PAGESIZE 500
SET LINESIZE 200
-- Ancho de columnas calculadas (si no, Oracle las muestra de 4000 caracteres)
COLUMN VALIDA_1 FORMAT A8
COLUMN VALIDA_9_BLOQUEADA FORMAT A18
COLUMN VALIDA_14_VENCIDA FORMAT A17
COLUMN DISPONIBLE FORMAT A10
COLUMN OPERATIVA FORMAT A9
COLUMN CONDUCTOR FORMAT A22
COLUMN REPORTADO_POR FORMAT A22
COLUMN TECNICO_RESPONSABLE FORMAT A22
COLUMN EMPLEADO FORMAT A22
COLUMN NOMBRE FORMAT A30
COLUMN ESTACION FORMAT A28
COLUMN DESTINO FORMAT A28
COLUMN LUGAR_AFECTADO FORMAT A40
COLUMN TERMINAL_ORIGEN FORMAT A26
COLUMN TERMINAL_DESTINO FORMAT A26
COLUMN VALOR_ANTERIOR FORMAT A20
COLUMN VALOR_NUEVO FORMAT A45
COLUMN TIPO_CERTIFICACION FORMAT A36

PROMPT ================= FUNCIONES =================

-- Duracion real y minutos de retraso (A-DT-EXP de ayer salio 18 min tarde)
SELECT NUMERO_VIAJE, ESTADO_VIAJE,
       FN_DURACION_REAL_VIAJE(ID_VIAJE) AS DURACION_MIN,
       FN_MINUTOS_RETRASO(ID_VIAJE)     AS RETRASO_MIN
FROM VIAJE_PROGRAMADO
WHERE NUMERO_VIAJE IN ('A-DT-EXP-M1-0700', 'C-DT-LOC-M1-0700', '1-DT-LOC-M2-1000', 'A-DT-EXP-P1-0700');

-- Saldo y validez de tarjetas (1 activa, 9 bloqueada, 14 vencida)
SELECT FN_SALDO_TARJETA('7000000000000001')  AS SALDO_TARJETA_1,
       FN_TARJETA_VALIDA('7000000000000001') AS VALIDA_1,
       FN_TARJETA_VALIDA('7000000000000009') AS VALIDA_9_BLOQUEADA,
       FN_TARJETA_VALIDA('7000000000000014') AS VALIDA_14_VENCIDA
FROM DUAL;

-- Ingresos de Times Sq y pasajeros de la linea A
SELECT FN_INGRESOS_ESTACION(4) AS INGRESOS_TIMES_SQ,
       FN_PASAJEROS_LINEA('A') AS PASAJEROS_LINEA_A
FROM DUAL;

-- Disponibilidad de trenes (9: inspeccion vencida, 15: retirado, 16: mantenimiento, 17: fuera de servicio)
SELECT ID_TREN, CODIGO_INTERNO, ESTADO_OPERATIVO, FECHA_PROXIMA_INSPECCION,
       FN_TREN_DISPONIBLE(ID_TREN) AS DISPONIBLE
FROM TREN ORDER BY ID_TREN;

-- Rutas operativas (5 y 6 pasan por Christopher St, cerrada)
SELECT ID_RUTA, CODIGO_RUTA, ESTADO, FN_RUTA_OPERATIVA(ID_RUTA) AS OPERATIVA
FROM RUTA ORDER BY ID_RUTA;

-- Costo total de las ordenes y duracion de los incidentes
SELECT NUMERO_ORDEN, ESTADO, COSTO_MANO_OBRA, FN_COSTO_ORDEN(ID_ORDEN) AS COSTO_TOTAL
FROM ORDEN_MANTENIMIENTO ORDER BY ID_ORDEN;

SELECT NUMERO_INCIDENTE, ESTADO, FN_DURACION_INCIDENTE(ID_INCIDENTE) AS DURACION_HORAS
FROM INCIDENTE ORDER BY ID_INCIDENTE;

PROMPT ================= SP_PROGRAMAR_VIAJE =================

DECLARE
    v_id NUMBER;
BEGIN
    SP_PROGRAMAR_VIAJE('A-DT-EXP-P2-2230', 1, TRUNC(SYSDATE) + 2 + 22.5/24, 1, 6, p_id_viaje => v_id);
    DBMS_OUTPUT.PUT_LINE('OK viaje programado con ID ' || v_id);
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('FALLO inesperado: ' || SQLERRM);
END;
/

DECLARE
    v_id NUMBER;
    PROCEDURE probar(p_caso VARCHAR2, p_num VARCHAR2, p_ruta NUMBER, p_salida DATE, p_tren NUMBER, p_cond NUMBER) IS
    BEGIN
        SP_PROGRAMAR_VIAJE(p_num, p_ruta, p_salida, p_tren, p_cond, p_id_viaje => v_id);
        DBMS_OUTPUT.PUT_LINE('FALLO (' || p_caso || '): se programo y debia rechazarse');
    EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('OK rechazado (' || p_caso || '): ' || SQLERRM);
    END;
BEGIN
    probar('fecha pasada',              'PRUEBA-01', 1, SYSDATE - 1,                  2, 7);
    probar('ruta no operativa',         'PRUEBA-02', 5, TRUNC(SYSDATE) + 2 + 9/24,    7, 11);
    probar('tren en mantenimiento',     'PRUEBA-03', 3, TRUNC(SYSDATE) + 2 + 9/24,   16, 9);
    probar('tren inspeccion vencida',   'PRUEBA-04', 3, TRUNC(SYSDATE) + 2 + 9/24,    9, 9);
    probar('certificacion vencida',     'PRUEBA-05', 3, TRUNC(SYSDATE) + 2 + 9/24,    7, 17);
    probar('conductor ocupado (regla 9)', 'PRUEBA-06', 2, TRUNC(SYSDATE) + 2 + 23/24, 3, 6);
    probar('tren ocupado (regla 8)',    'PRUEBA-07', 2, TRUNC(SYSDATE) + 2 + 23/24,  1, 7);
END;
/

PROMPT ================= SP_RECARGAR_TARJETA =================

DECLARE
    v_id NUMBER;
BEGIN
    SP_RECARGAR_TARJETA('7000000000000013', 10, 'EFECTIVO', 'ESTACION', 18, v_id);
    DBMS_OUTPUT.PUT_LINE('OK recarga ' || v_id || ', nuevo saldo de la tarjeta 13: ' || FN_SALDO_TARJETA('7000000000000013'));
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('FALLO inesperado: ' || SQLERRM);
END;
/

DECLARE
    v_id NUMBER;
BEGIN
    SP_RECARGAR_TARJETA('7000000000000009', 10, 'EFECTIVO', 'ESTACION', 6, v_id);
    DBMS_OUTPUT.PUT_LINE('FALLO: se recargo una tarjeta bloqueada');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('OK rechazado (tarjeta bloqueada): ' || SQLERRM);
END;
/

PROMPT ================= SP_REGISTRAR_INGRESO / SALIDA =================

DECLARE
    v_id NUMBER;
    PROCEDURE rechazo(p_caso VARCHAR2, p_tarjeta VARCHAR2, p_estacion NUMBER) IS
    BEGIN
        SP_REGISTRAR_INGRESO(p_tarjeta, p_estacion, 'TARJETA', v_id);
        DBMS_OUTPUT.PUT_LINE('FALLO (' || p_caso || '): el ingreso debia rechazarse');
    EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('OK rechazado (' || p_caso || '): ' || SQLERRM);
    END;
BEGIN
    rechazo('viaje ya abierto',         '7000000000000001', 4);
    rechazo('estacion cerrada (regla 21)', '7000000000000012', 14);
    rechazo('tarjeta vencida (regla 16)', '7000000000000014', 6);
    rechazo('tarjeta bloqueada (regla 16)', '7000000000000009', 6);

    SP_REGISTRAR_INGRESO('7000000000000013', 18, 'TARJETA', v_id);
    DBMS_OUTPUT.PUT_LINE('OK ingreso tarjeta 13 (viaje ' || v_id || '), saldo: ' || FN_SALDO_TARJETA('7000000000000013'));

    SP_REGISTRAR_INGRESO('7000000000000005', 3, 'TARJETA', v_id);
    DBMS_OUTPUT.PUT_LINE('OK ingreso adulto mayor con tarifa reducida (viaje ' || v_id || '), saldo: ' || FN_SALDO_TARJETA('7000000000000005'));

    SP_REGISTRAR_INGRESO(NULL, 5, 'BOLETO', v_id);
    DBMS_OUTPUT.PUT_LINE('OK viaje anonimo con boleto (viaje ' || v_id || ')');

    SP_REGISTRAR_SALIDA('7000000000000013', 4);
    DBMS_OUTPUT.PUT_LINE('OK salida registrada para la tarjeta 13');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('FALLO inesperado: ' || SQLERRM);
END;
/

SELECT NUMERO_TRANSACCION, TIPO_ACCESO, NUMERO_TARJETA, ID_ESTACION_INGRESO, ID_ESTACION_SALIDA,
       MONTO_COBRADO, ESTADO
FROM VIAJE_PASAJERO
WHERE FECHA_HORA_INGRESO >= SYSDATE - 1/24
ORDER BY ID_VIAJE_PASAJERO;

PROMPT ================= SP_CREAR_ORDEN_MANTENIMIENTO / SP_ACTUALIZAR_ESTADO_ORDEN =================

DECLARE
    v_orden  NUMBER;
    v_estado TREN.ESTADO_OPERATIVO%TYPE;
BEGIN
    -- El equipo 1 es el tren 9 (inspeccion vencida)
    SP_CREAR_ORDEN_MANTENIMIENTO(1, 'CORRECTIVO', 'Inspeccion general vencida y revision de frenos',
                                 'ALTA', NULL, 20, v_orden);
    SELECT ESTADO_OPERATIVO INTO v_estado FROM TREN WHERE ID_TREN = 9;
    DBMS_OUTPUT.PUT_LINE('OK orden ' || v_orden || ' creada; tren 9 quedo ' || v_estado);

    SP_ACTUALIZAR_ESTADO_ORDEN(v_orden, 'EN_EJECUCION');
    SP_ACTUALIZAR_ESTADO_ORDEN(v_orden, 'COMPLETADA', 90);
    SELECT ESTADO_OPERATIVO INTO v_estado FROM TREN WHERE ID_TREN = 9;
    DBMS_OUTPUT.PUT_LINE('OK orden completada; tren 9 quedo ' || v_estado
        || ' y disponible = ' || FN_TREN_DISPONIBLE(9));
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('FALLO inesperado: ' || SQLERRM);
END;
/

PROMPT ================= SP_REGISTRAR_INCIDENTE / SP_CANCELAR_VIAJES_AFECTADOS =================

DECLARE
    v_inc        NUMBER;
    v_cancelados NUMBER;
    v_estado     ESTACION.ESTADO_OPERATIVO%TYPE;
BEGIN
    SP_REGISTRAR_INCIDENTE('OBJETO_EN_VIA', 'Objeto metalico en la via expresa', '14 St-8 Av', 'ALTO', 4,
                           'ESTACION', 6, 'CIERRE_ESTACION', 2000, v_inc);
    SELECT ESTADO_OPERATIVO INTO v_estado FROM ESTACION WHERE ID_ESTACION = 6;
    DBMS_OUTPUT.PUT_LINE('OK incidente ' || v_inc || ' registrado; estacion 6 quedo ' || v_estado);

    SP_CANCELAR_VIAJES_AFECTADOS('ESTACION', 6, SYSDATE, NULL, v_inc, v_cancelados);
    DBMS_OUTPUT.PUT_LINE('OK viajes cancelados por el cierre: ' || v_cancelados);

    SP_CERRAR_INCIDENTE(v_inc, 'Objeto caido de una obra cercana', 'Retiro del objeto e inspeccion de la via');
    SELECT ESTADO_OPERATIVO INTO v_estado FROM ESTACION WHERE ID_ESTACION = 6;
    DBMS_OUTPUT.PUT_LINE('OK incidente cerrado; estacion 6 quedo ' || v_estado
        || ', duracion ' || FN_DURACION_INCIDENTE(v_inc) || ' h');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('FALLO inesperado: ' || SQLERRM);
END;
/

-- Las rutas vuelven a ACTIVA salvo 5 y 6 (Christopher St sigue cerrada por INC-2026-0004)
SELECT CODIGO_RUTA, ESTADO FROM RUTA ORDER BY ID_RUTA;

PROMPT ================= TRIGGERS =================

-- Saldo negativo (regla 15)
BEGIN
    UPDATE TARJETA SET SALDO = -5 WHERE NUMERO_TARJETA = '7000000000000001';
    DBMS_OUTPUT.PUT_LINE('FALLO: se permitio saldo negativo');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('OK rechazado (saldo negativo): ' || SQLERRM);
END;
/

-- Historicos no se borran (regla 25)
BEGIN
    DELETE FROM RECARGA WHERE ID_RECARGA = 1;
    DBMS_OUTPUT.PUT_LINE('FALLO: se borro una recarga');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('OK rechazado (borrar recarga): ' || SQLERRM);
END;
/

-- El monto de una tarifa no se modifica (reglas 17 y 18)
BEGIN
    UPDATE TARIFA SET MONTO = 3.25 WHERE ID_TARIFA = 2;
    DBMS_OUTPUT.PUT_LINE('FALLO: se modifico el monto de una tarifa');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('OK rechazado (cambiar monto): ' || SQLERRM);
END;
/

-- Iniciar y terminar un viaje: el tren pasa a EN_OPERACION y luego vuelve a DISPONIBLE
DECLARE
    v_estado TREN.ESTADO_OPERATIVO%TYPE;
    v_km     TREN.KILOMETRAJE_ACUMULADO%TYPE;
BEGIN
    UPDATE VIAJE_PROGRAMADO SET ESTADO_VIAJE = 'EN_CURSO' WHERE NUMERO_VIAJE = '7-OE-LOC-P1-0700';
    SELECT ESTADO_OPERATIVO INTO v_estado FROM TREN WHERE ID_TREN = 10;
    DBMS_OUTPUT.PUT_LINE('OK viaje en curso; tren 10 quedo ' || v_estado);

    UPDATE VIAJE_PROGRAMADO SET ESTADO_VIAJE = 'COMPLETADO' WHERE NUMERO_VIAJE = '7-OE-LOC-P1-0700';
    SELECT ESTADO_OPERATIVO, KILOMETRAJE_ACUMULADO INTO v_estado, v_km FROM TREN WHERE ID_TREN = 10;
    DBMS_OUTPUT.PUT_LINE('OK viaje completado; tren 10 quedo ' || v_estado || ' con ' || v_km || ' km');
    COMMIT;
EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('FALLO inesperado: ' || SQLERRM);
END;
/

-- Asignar un tren en mantenimiento (regla 11)
BEGIN
    UPDATE VIAJE_PROGRAMADO SET ID_TREN = 16 WHERE NUMERO_VIAJE = '7-ES-LOC-P1-1000';
    DBMS_OUTPUT.PUT_LINE('FALLO: se asigno un tren en mantenimiento');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('OK rechazado (tren en mantenimiento): ' || SQLERRM);
END;
/

-- Conductor con certificacion vencida (regla 10)
BEGIN
    UPDATE VIAJE_PROGRAMADO SET ID_CONDUCTOR = 17 WHERE NUMERO_VIAJE = '7-ES-LOC-P1-1000';
    DBMS_OUTPUT.PUT_LINE('FALLO: se asigno un conductor sin certificacion vigente');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('OK rechazado (certificacion vencida): ' || SQLERRM);
END;
/

-- Mismo tren en dos viajes a la misma hora (regla 8)
BEGIN
    UPDATE VIAJE_PROGRAMADO SET ID_TREN = 10 WHERE NUMERO_VIAJE = '7-ES-LOC-P1-0700';
    DBMS_OUTPUT.PUT_LINE('FALLO: se permitio un tren en dos viajes simultaneos');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('OK rechazado (tren simultaneo): ' || SQLERRM);
END;
/

-- Turnos superpuestos del mismo empleado
BEGIN
    INSERT INTO TURNO (CODIGO_TURNO, ID_EMPLEADO, FECHA, HORA_INICIO, HORA_FIN, TIPO_LUGAR, ID_ESTACION, FUNCION)
    VALUES ('TU-002-PRUEBA', 2, TRUNC(SYSDATE) + 1, TRUNC(SYSDATE) + 1 + 10/24, TRUNC(SYSDATE) + 1 + 18/24,
            'ESTACION', 4, 'APOYO');
    DBMS_OUTPUT.PUT_LINE('FALLO: se permitio un turno superpuesto');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('OK rechazado (turno superpuesto): ' || SQLERRM);
END;
/

-- Certificacion registrada ya vencida: queda VENCIDA y genera una alerta
INSERT INTO CERTIFICACION (ID_EMPLEADO, TIPO_CERTIFICACION, FECHA_EMISION, FECHA_VENCIMIENTO, INSTITUCION_EMISORA)
VALUES (18, 'PRIMEROS AUXILIOS', TRUNC(SYSDATE) - 400, TRUNC(SYSDATE) - 1, 'CRUZ ROJA');

-- Bloquear una tarjeta (queda en la bitacora)
UPDATE TARJETA SET ESTADO = 'BLOQUEADA' WHERE NUMERO_TARJETA = '7000000000000012';
COMMIT;

-- Ultimos movimientos de la bitacora generados por los triggers
SELECT ID_BITACORA, TABLA, ID_REGISTRO, OPERACION, CAMPO, VALOR_ANTERIOR, VALOR_NUEVO, FECHA_HORA
FROM BITACORA
WHERE FECHA_HORA >= SYSDATE - 1/24
ORDER BY ID_BITACORA;

PROMPT ================= VISTAS =================

SELECT * FROM VW_ESTADO_LINEAS ORDER BY COD_LINEA;

SELECT * FROM VW_PROXIMAS_SALIDAS WHERE ID_ESTACION = 4 ORDER BY HORA_SALIDA_ESTIMADA FETCH FIRST 10 ROWS ONLY;

SELECT * FROM VW_VIAJES_RETRASADOS ORDER BY MINUTOS_RETRASO_SALIDA DESC;

SELECT * FROM VW_TRENES_DISPONIBLES ORDER BY ID_TREN;

SELECT * FROM VW_TRENES_MANTENIMIENTO ORDER BY ID_TREN;

SELECT * FROM VW_INCIDENTES_ABIERTOS ORDER BY FECHA_HORA_INICIO;

SELECT * FROM VW_INGRESOS_DIARIOS_LINEA ORDER BY FECHA, COD_LINEA;

SELECT * FROM VW_ESTACIONES_MAS_PASAJEROS ORDER BY POSICION FETCH FIRST 10 ROWS ONLY;

SELECT * FROM VW_CERTIFICACIONES_POR_VENCER ORDER BY DIAS_RESTANTES;

PROMPT ================= OBJETOS COMPILADOS (todos deben estar VALID) =================

-- Recompila lo que haya quedado invalido por cambios de dependencias
EXEC DBMS_UTILITY.COMPILE_SCHEMA(schema => USER, compile_all => FALSE);

COLUMN OBJECT_TYPE FORMAT A10
COLUMN OBJECT_NAME FORMAT A32
SELECT OBJECT_TYPE, OBJECT_NAME, STATUS FROM USER_OBJECTS
WHERE OBJECT_TYPE IN ('FUNCTION', 'PROCEDURE', 'TRIGGER', 'VIEW')
ORDER BY 1, 2;

-- Errores de compilacion (no debe devolver filas)
SELECT NAME, TYPE, LINE, TEXT FROM USER_ERRORS;
