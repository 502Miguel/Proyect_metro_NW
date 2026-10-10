/* =====================================================================
   SISTEMA DE GESTION - METRO DE NUEVA YORK
   DEMOSTRACION EN VIVO (entregable 16)
   Llamadas listas para ejecutar durante la presentacion, por modulo.

   - Ejecutar DESPUES de 99_ejecutar_todo.sql, de preferencia el mismo dia
     de la presentacion (las fechas de los datos son relativas a SYSDATE).
   - Se puede correr completo con F5 o un bloque a la vez (seleccionar el
     bloque y F5). Cada bloque se puede repetir.
   - Los procedimientos confirman (COMMIT) sus cambios. Para volver al
     estado inicial, ejecutar de nuevo 99_ejecutar_todo.sql.

   Datos utiles para llamadas improvisadas:
     Tarjetas    : 7000000000000002 activa con saldo, ...0005 adulto mayor,
                   ...0009 bloqueada, ...0014 vencida, ...0044 sin saldo
     Estaciones  : 4 Times Sq-42 St, 5 34 St-Penn Station, 8 Fulton St,
                   18 Grand Central-42 St, 14 Christopher St (cerrada)
     Rutas       : 1 A-DT-EXP, 2 A-UT-EXP, 3 C-DT-LOC, 11 A-DT-NOC (nocturna),
                   5 y 6 linea 1 (afectadas por el cierre de Christopher St)
     Horarios    : 23 = ruta nocturna, dias laborales 00:00-04:59 cada 20 min
     Trenes      : 1 a 14 disponibles, 16 en mantenimiento, 17 fuera de
                   servicio, 12 (T7-1903) de reserva = equipo 27
     Conductores : 6, 7 y 8 habilitados para los trenes 1 a 3 (modelo R179),
                   17 con certificacion vencida, 18 suspendido
     Tecnicos    : 19, 20 y 21          Supervisores de estacion: 2 y 3
   ===================================================================== */

SET SERVEROUTPUT ON SIZE UNLIMITED
SET PAGESIZE 100
SET LINESIZE 200
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI';
COLUMN ESTACION FORMAT A26
COLUMN NOMBRE FORMAT A30
COLUMN ENTRADA FORMAT A24
COLUMN SALIDA FORMAT A24
COLUMN DESTINO FORMAT A26
COLUMN LINEA FORMAT A30
COLUMN LUGAR_AFECTADO FORMAT A30
COLUMN UBICACION FORMAT A40
COLUMN EMPLEADO FORMAT A22
COLUMN CONDUCTOR FORMAT A22
COLUMN SUSTITUTO FORMAT A22
COLUMN PASAJERO FORMAT A22
COLUMN TECNICO_RESPONSABLE FORMAT A22
COLUMN TIPO_CERTIFICACION FORMAT A34

PROMPT ================= MODULO 1. RED: lineas de una estacion y estado de la red =================

SELECT E.NOMBRE AS ESTACION, L.COD_LINEA, L.NOMBRE AS LINEA, LE.NUMERO_SECUENCIA
FROM ESTACION E
JOIN LINEA_ESTACION LE ON LE.ID_ESTACION = E.ID_ESTACION
JOIN LINEA L           ON L.COD_LINEA = LE.COD_LINEA
WHERE E.ID_ESTACION = 4
ORDER BY L.COD_LINEA;

SELECT COD_LINEA, NOMBRE, ESTADO_OPERATIVO, TOTAL_ESTACIONES, ESTACIONES_CERRADAS,
       RUTAS_ACTIVAS, RUTAS_AFECTADAS, VIAJES_PENDIENTES
FROM VW_ESTADO_LINEAS ORDER BY COD_LINEA;

PROMPT ================= MODULO 2. PROGRAMAR UN VIAJE (SP_PROGRAMAR_VIAJE) =================

DECLARE
    v_id     NUMBER;
    v_salida DATE;
BEGIN
    -- Cada ejecucion usa un dia distinto a las 22:30 para poder repetir la demostracion
    SELECT TRUNC(SYSDATE) + 4 + COUNT(*) + 22.5/24 INTO v_salida
    FROM VIAJE_PROGRAMADO WHERE NUMERO_VIAJE LIKE 'A-UT-EXP-DEMO-%';

    SP_PROGRAMAR_VIAJE('A-UT-EXP-DEMO-' || TO_CHAR(v_salida, 'MMDD'), 2, v_salida, 2, 7, p_id_viaje => v_id);
    DBMS_OUTPUT.PUT_LINE('Viaje programado con ID ' || v_id || ' para el ' || TO_CHAR(v_salida, 'YYYY-MM-DD HH24:MI')
        || ' (tren TA-3020, conductora Carmen Reyes)');
END;
/

PROMPT ----- Validaciones al programar (todas deben rechazarse) -----

DECLARE
    PROCEDURE intentar(p_caso VARCHAR2, p_ruta NUMBER, p_salida DATE, p_tren NUMBER, p_conductor NUMBER) IS
        v_id NUMBER;
    BEGIN
        SP_PROGRAMAR_VIAJE('DEMO-RECHAZO', p_ruta, p_salida, p_tren, p_conductor, p_id_viaje => v_id);
        DBMS_OUTPUT.PUT_LINE(p_caso || ': se programo (no esperado)');
    EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE(p_caso || ' -> ' || SQLERRM);
    END;
BEGIN
    intentar('Hora pasada',                                    1, SYSDATE - 1,               1, 6);
    intentar('Ruta afectada por un cierre',                    5, TRUNC(SYSDATE) + 4 + 9/24, 7, 11);
    intentar('Tren en mantenimiento (regla 11)',               3, TRUNC(SYSDATE) + 4 + 9/24, 16, 9);
    intentar('Conductor con certificacion vencida (regla 10)', 3, TRUNC(SYSDATE) + 4 + 9/24, 7, 17);
    intentar('Conductor con otro viaje a esa hora (regla 9)',  1, TRUNC(SYSDATE) + 4 + 9/24, 3, 6);
    intentar('Tren con otro viaje a esa hora (regla 8)',       1, TRUNC(SYSDATE) + 4 + 9/24, 1, 7);
END;
/

PROMPT ================= MODULO 2. GENERAR LOS VIAJES DE UN HORARIO (SP_GENERAR_VIAJES) =================

DECLARE
    v_fecha DATE := TRUNC(SYSDATE) + 8;
    v_hay   NUMBER;
    v_n     NUMBER;
BEGIN
    -- Primer dia laboral desde dentro de 8 dias que aun no tenga viajes del horario 23
    LOOP
        SELECT COUNT(*) INTO v_hay FROM VIAJE_PROGRAMADO WHERE ID_HORARIO = 23 AND FECHA_VIAJE = v_fecha;
        EXIT WHEN v_hay = 0 AND TO_CHAR(v_fecha, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') NOT IN ('SAT', 'SUN');
        v_fecha := v_fecha + 1;
    END LOOP;

    SP_GENERAR_VIAJES(23, v_fecha, v_n);
    DBMS_OUTPUT.PUT_LINE(v_n || ' viajes generados para el ' || TO_CHAR(v_fecha, 'YYYY-MM-DD')
        || ' segun la frecuencia del horario 23 (todavia sin tren ni conductor)');

    -- Asignar tren y conductor al viaje de las 00:00 (lo validan los triggers)
    UPDATE VIAJE_PROGRAMADO SET ID_TREN = 3, ID_CONDUCTOR = 8
    WHERE ID_HORARIO = 23 AND SALIDA_PROGRAMADA = v_fecha;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Asignados el tren TA-3030 y el conductor Tyrone Mitchell al viaje de las 00:00');
END;
/

PROMPT ----- Asignaciones que deben rechazarse (triggers) -----

DECLARE
    v_fecha DATE;
    PROCEDURE intentar(p_caso VARCHAR2, p_minuto NUMBER, p_tren NUMBER, p_conductor NUMBER) IS
    BEGIN
        UPDATE VIAJE_PROGRAMADO SET ID_TREN = p_tren, ID_CONDUCTOR = p_conductor
        WHERE ID_HORARIO = 23 AND SALIDA_PROGRAMADA = v_fecha + p_minuto / 1440;
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE(p_caso || ': asignado (no esperado)');
    EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE(p_caso || ' -> ' || SQLERRM);
    END;
BEGIN
    SELECT MAX(FECHA_VIAJE) INTO v_fecha FROM VIAJE_PROGRAMADO WHERE ID_HORARIO = 23 AND ID_TREN = 3;
    intentar('Mismo tren en dos viajes a la vez (regla 8)',      20, 3, 7);
    intentar('Mismo conductor en dos viajes a la vez (regla 9)', 20, 2, 8);
    intentar('Conductor sin certificacion vigente (regla 10)',   40, 1, 17);
    intentar('Tren en mantenimiento (regla 11)',                 60, 16, NULL);
END;
/

SELECT V.NUMERO_VIAJE, V.SALIDA_PROGRAMADA, V.LLEGADA_PROGRAMADA, T.CODIGO_INTERNO AS TREN,
       C.NOMBRES || ' ' || C.APELLIDOS AS CONDUCTOR, V.ESTADO_VIAJE
FROM VIAJE_PROGRAMADO V
LEFT JOIN TREN T     ON T.ID_TREN = V.ID_TREN
LEFT JOIN EMPLEADO C ON C.ID_EMPLEADO = V.ID_CONDUCTOR
WHERE V.ID_HORARIO = 23
  AND V.FECHA_VIAJE = (SELECT MAX(FECHA_VIAJE) FROM VIAJE_PROGRAMADO WHERE ID_HORARIO = 23 AND ID_TREN = 3)
ORDER BY V.SALIDA_PROGRAMADA
FETCH FIRST 5 ROWS ONLY;

PROMPT ================= MODULO 3. TRENES: disponibilidad y composicion =================

SELECT CODIGO_INTERNO, NOMBRE_MODELO, DEPOSITO, FECHA_PROXIMA_INSPECCION FROM VW_TRENES_DISPONIBLES ORDER BY ID_TREN;

SELECT T.CODIGO_INTERNO AS TREN, C.POSICION, V.NUMERO_SERIE, V.TIPO_VAGON, C.FECHA_INICIO, C.FECHA_FIN
FROM COMPOSICION_TREN C
JOIN TREN T  ON T.ID_TREN = C.ID_TREN
JOIN VAGON V ON V.ID_VAGON = C.ID_VAGON
WHERE C.ID_VAGON IN (SELECT ID_VAGON FROM COMPOSICION_TREN GROUP BY ID_VAGON HAVING COUNT(*) > 1)
ORDER BY V.NUMERO_SERIE, C.FECHA_INICIO;

PROMPT ================= MODULO 4. PERSONAL: turnos, traslapes y ausencias =================

DECLARE
    v_dia DATE;
BEGIN
    -- Un dia distinto en cada ejecucion para poder repetir la demostracion
    SELECT TRUNC(SYSDATE) + 9 + COUNT(*) INTO v_dia FROM TURNO WHERE CODIGO_TURNO LIKE 'TU-DEMO-%';

    INSERT INTO TURNO (CODIGO_TURNO, ID_EMPLEADO, FECHA, HORA_INICIO, HORA_FIN, TIPO_LUGAR, ID_ESTACION, FUNCION)
    VALUES ('TU-DEMO-' || TO_CHAR(v_dia, 'MMDD'), 3, v_dia, v_dia + 8/24, v_dia + 16/24, 'ESTACION', 4, 'SUPERVISION');
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Turno programado para Denise Carter el ' || TO_CHAR(v_dia, 'YYYY-MM-DD') || ' de 08:00 a 16:00');

    BEGIN
        INSERT INTO TURNO (CODIGO_TURNO, ID_EMPLEADO, FECHA, HORA_INICIO, HORA_FIN, TIPO_LUGAR, ID_ESTACION, FUNCION)
        VALUES ('TU-DEMO-' || TO_CHAR(v_dia, 'MMDD') || 'B', 3, v_dia, v_dia + 14/24, v_dia + 22/24, 'ESTACION', 18, 'APOYO');
        DBMS_OUTPUT.PUT_LINE('Turno superpuesto: permitido (no esperado)');
    EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Turno superpuesto de 14:00 a 22:00 -> ' || SQLERRM);
    END;

    INSERT INTO AUSENCIA (ID_EMPLEADO, TIPO_AUSENCIA, FECHA_INICIO, FECHA_FIN, MOTIVO, ID_APROBADO_POR, ID_SUSTITUTO)
    VALUES (3, 'PERMISO', v_dia + 1, v_dia + 1, 'Tramite personal', 1, 2);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Permiso registrado para el dia siguiente, con Roberto Salinas como sustituto');
END;
/

SELECT E.NOMBRES || ' ' || E.APELLIDOS AS EMPLEADO, A.TIPO_AUSENCIA, A.FECHA_INICIO, A.FECHA_FIN,
       S.NOMBRES || ' ' || S.APELLIDOS AS SUSTITUTO
FROM AUSENCIA A
JOIN EMPLEADO E      ON E.ID_EMPLEADO = A.ID_EMPLEADO
LEFT JOIN EMPLEADO S ON S.ID_EMPLEADO = A.ID_SUSTITUTO
ORDER BY A.FECHA_INICIO;

SELECT NUMERO_EMPLEADO, EMPLEADO, TIPO_CERTIFICACION, FECHA_VENCIMIENTO, DIAS_RESTANTES, SITUACION
FROM VW_CERTIFICACIONES_POR_VENCER ORDER BY DIAS_RESTANTES;

PROMPT ================= MODULO 5. PASAJEROS: registro, tarjeta, ingreso, salida y recarga =================

DECLARE
    v_pasajero NUMBER;
    v_tarjeta  VARCHAR2(20) := '7999' || TO_CHAR(SYSDATE, 'YYMMDDHH24MISS');
    v_id       NUMBER;
BEGIN
    INSERT INTO PASAJERO (NOMBRES, APELLIDOS, FECHA_NACIMIENTO, CORREO, TELEFONO, TIPO_PASAJERO, FECHA_REGISTRO, ESTADO)
    VALUES ('Laura', 'Demo', DATE '2003-05-14', 'laura.demo' || TO_CHAR(SYSDATE, 'YYMMDDHH24MISS') || '@example.com',
            '+1-212-555-0199', 'REGULAR', SYSDATE, 'ACTIVO')
    RETURNING ID_PASAJERO INTO v_pasajero;
    -- Tarjeta personalizada con la tarifa de viaje individual vigente
    INSERT INTO TARJETA (NUMERO_TARJETA, ID_PASAJERO, FECHA_EMISION, FECHA_VENCIMIENTO, SALDO, ID_TARIFA, ESTADO)
    VALUES (v_tarjeta, v_pasajero, TRUNC(SYSDATE), ADD_MONTHS(TRUNC(SYSDATE), 60), 0, FN_TARIFA_VIGENTE('VIAJE_IND'), 'ACTIVA');
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Pasajero ' || v_pasajero || ' registrado con la tarjeta ' || v_tarjeta || ' (saldo 0)');

    SP_RECARGAR_TARJETA(v_tarjeta, 20, 'TARJETA_DEBITO', 'ESTACION', 4, v_id);
    DBMS_OUTPUT.PUT_LINE('Recarga de 20.00, saldo: ' || FN_SALDO_TARJETA(v_tarjeta));
    SP_REGISTRAR_INGRESO(v_tarjeta, 4, 'TARJETA', v_id);              -- entra en Times Sq-42 St
    DBMS_OUTPUT.PUT_LINE('Ingreso en Times Sq-42 St (viaje ' || v_id || '), saldo: ' || FN_SALDO_TARJETA(v_tarjeta));
    SP_REGISTRAR_SALIDA(v_tarjeta, 8);                               -- sale en Fulton St
    DBMS_OUTPUT.PUT_LINE('Salida en Fulton St');

    SP_REGISTRAR_INGRESO(NULL, 5, 'BOLETO', v_id);                    -- viaje anonimo
    DBMS_OUTPUT.PUT_LINE('Viaje anonimo con boleto en 34 St-Penn Station (viaje ' || v_id || ')');

    UPDATE TARJETA SET ESTADO = 'BLOQUEADA' WHERE NUMERO_TARJETA = v_tarjeta;   -- queda en la bitacora
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Tarjeta bloqueada por reporte del pasajero; valida = ' || FN_TARJETA_VALIDA(v_tarjeta));
END;
/

PROMPT ----- Ingresos que deben rechazarse (quedan registrados como RECHAZADO) -----

DECLARE
    PROCEDURE intentar(p_caso VARCHAR2, p_tarjeta VARCHAR2, p_estacion NUMBER) IS
        v_id NUMBER;
    BEGIN
        SP_REGISTRAR_INGRESO(p_tarjeta, p_estacion, 'TARJETA', v_id);
        DBMS_OUTPUT.PUT_LINE(p_caso || ': ingreso permitido (no esperado)');
    EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE(p_caso || ' -> ' || SQLERRM);
    END;
BEGIN
    intentar('Tarjeta bloqueada (regla 16)',  '7000000000000009', 4);
    intentar('Tarjeta vencida (regla 16)',    '7000000000000014', 4);
    intentar('Saldo insuficiente (regla 15)', '7000000000000044', 4);
    intentar('Estacion cerrada (regla 21)',   '7000000000000003', 14);
END;
/

PROMPT ----- Saldo e historial de una tarjeta -----

SELECT FN_SALDO_TARJETA('7000000000000002') AS SALDO, FN_TARJETA_VALIDA('7000000000000002') AS VALIDA FROM DUAL;

SELECT V.NUMERO_TRANSACCION, V.FECHA_HORA_INGRESO, EI.NOMBRE AS ENTRADA, ES.NOMBRE AS SALIDA,
       V.MONTO_COBRADO, V.ESTADO
FROM VIAJE_PASAJERO V
JOIN ESTACION EI      ON EI.ID_ESTACION = V.ID_ESTACION_INGRESO
LEFT JOIN ESTACION ES ON ES.ID_ESTACION = V.ID_ESTACION_SALIDA
WHERE V.NUMERO_TARJETA = '7000000000000002'
ORDER BY V.FECHA_HORA_INGRESO DESC
FETCH FIRST 8 ROWS ONLY;

SELECT NUMERO_TRANSACCION, FECHA_HORA, MONTO, SALDO_ANTERIOR, SALDO_POSTERIOR
FROM RECARGA WHERE NUMERO_TARJETA = '7000000000000002'
ORDER BY FECHA_HORA DESC
FETCH FIRST 5 ROWS ONLY;

PROMPT ================= MODULO 6. MANTENIMIENTO: orden correctiva sobre el tren T7-1903 =================

DECLARE
    v_orden  NUMBER;
    v_estado TREN.ESTADO_OPERATIVO%TYPE;
BEGIN
    -- Correctiva de prioridad ALTA: el equipo y el tren pasan a EN_MANTENIMIENTO
    SP_CREAR_ORDEN_MANTENIMIENTO(27, 'CORRECTIVO', 'Falla en el sistema de puertas', 'ALTA', NULL, 21, v_orden);
    SELECT ESTADO_OPERATIVO INTO v_estado FROM TREN WHERE ID_TREN = 12;
    DBMS_OUTPUT.PUT_LINE('Orden ' || v_orden || ' creada; el tren T7-1903 quedo ' || v_estado
        || ' (disponible = ' || FN_TREN_DISPONIBLE(12) || ')');

    -- Un segundo tecnico (regla 19), horas trabajadas, repuestos y mano de obra
    INSERT INTO ORDEN_TECNICO (ID_ORDEN, ID_EMPLEADO, HORAS_TRABAJADAS) VALUES (v_orden, 20, 3);
    UPDATE ORDEN_TECNICO SET HORAS_TRABAJADAS = 4 WHERE ID_ORDEN = v_orden AND ID_EMPLEADO = 21;
    INSERT INTO ORDEN_REPUESTO (ID_ORDEN, ID_REPUESTO, CANTIDAD, COSTO_UNITARIO)
        SELECT v_orden, ID_REPUESTO, 2, COSTO_UNITARIO FROM REPUESTO WHERE CODIGO_REPUESTO = 'RP-PUE-070';
    UPDATE ORDEN_MANTENIMIENTO SET COSTO_MANO_OBRA = 600 WHERE ID_ORDEN = v_orden;
    COMMIT;
END;
/

SELECT CODIGO_INTERNO, ESTADO_OPERATIVO, NUMERO_ORDEN, PRIORIDAD, ESTADO_ORDEN, TECNICO_RESPONSABLE
FROM VW_TRENES_MANTENIMIENTO ORDER BY ID_TREN;

DECLARE
    v_orden  NUMBER;
    v_estado TREN.ESTADO_OPERATIVO%TYPE;
BEGIN
    SELECT MAX(ID_ORDEN) INTO v_orden FROM ORDEN_MANTENIMIENTO
    WHERE ID_EQUIPO = 27 AND DESCRIPCION = 'Falla en el sistema de puertas' AND ESTADO = 'SOLICITADA';
    SP_ACTUALIZAR_ESTADO_ORDEN(v_orden, 'EN_EJECUCION');
    SP_ACTUALIZAR_ESTADO_ORDEN(v_orden, 'COMPLETADA', 90);           -- proxima revision en 90 dias
    SELECT ESTADO_OPERATIVO INTO v_estado FROM TREN WHERE ID_TREN = 12;
    DBMS_OUTPUT.PUT_LINE('Orden completada; el tren T7-1903 quedo ' || v_estado
        || '. Costo total de la orden: ' || FN_COSTO_ORDEN(v_orden));
END;
/

SELECT T.NUMERO_EMPLEADO, T.NOMBRES || ' ' || T.APELLIDOS AS EMPLEADO, OT.HORAS_TRABAJADAS
FROM ORDEN_TECNICO OT
JOIN EMPLEADO T ON T.ID_EMPLEADO = OT.ID_EMPLEADO
WHERE OT.ID_ORDEN = (SELECT MAX(ID_ORDEN) FROM ORDEN_MANTENIMIENTO WHERE ID_EQUIPO = 27);

PROMPT ----- Equipos con revision vencida o fuera de servicio -----

SELECT CODIGO_EQUIPO, TIPO_EQUIPO, UBICACION, ESTADO, FECHA_PROXIMA_REVISION,
       CASE WHEN ESTADO = 'FUERA_DE_SERVICIO' THEN 'FUERA DE SERVICIO' ELSE 'REVISION VENCIDA' END AS SITUACION
FROM EQUIPO
WHERE ESTADO = 'FUERA_DE_SERVICIO'
   OR (ESTADO <> 'RETIRADO' AND FECHA_PROXIMA_REVISION < TRUNC(SYSDATE))
ORDER BY FECHA_PROXIMA_REVISION;

PROMPT ================= MODULO 7. INCIDENTES: registrar, cancelar viajes afectados y cerrar =================

DECLARE
    v_inc NUMBER;
    v_n   NUMBER;
BEGIN
    -- Cierra la estacion y marca las rutas que paran en ella como afectadas
    SP_REGISTRAR_INCIDENTE('FALLA_ELECTRICA', 'Corte de energia en el anden de la linea 7', 'Grand Central-42 St',
                           'ALTO', 4, 'ESTACION', 18, 'CIERRE_ESTACION', 1500, v_inc);
    -- Cierre estimado hasta manana a las 12:00
    SP_CANCELAR_VIAJES_AFECTADOS('ESTACION', 18, SYSDATE, TRUNC(SYSDATE) + 1 + 12/24, v_inc, v_n);
    DBMS_OUTPUT.PUT_LINE('Incidente ' || v_inc || ' registrado; viajes cancelados por el cierre: ' || v_n);
END;
/

SELECT NUMERO_INCIDENTE, TIPO_INCIDENTE, SEVERIDAD, ESTADO, LUGAR_AFECTADO, HORAS_ABIERTO,
       ELEMENTOS_AFECTADOS, VIAJES_AFECTADOS
FROM VW_INCIDENTES_ABIERTOS ORDER BY FECHA_HORA_INICIO DESC;

SELECT COD_LINEA, ESTACIONES_CERRADAS, RUTAS_ACTIVAS, RUTAS_AFECTADAS, VIAJES_PENDIENTES
FROM VW_ESTADO_LINEAS ORDER BY COD_LINEA;

DECLARE
    v_inc NUMBER;
BEGIN
    SELECT MAX(ID_INCIDENTE) INTO v_inc FROM INCIDENTE
    WHERE LUGAR_AFECTADO = 'Grand Central-42 St' AND ESTADO <> 'CERRADO';
    SP_CERRAR_INCIDENTE(v_inc, 'Falla en la subestacion electrica', 'Cambio de interruptor y prueba de energia');
    DBMS_OUTPUT.PUT_LINE('Incidente cerrado: la estacion vuelve a operar. Duracion: '
        || FN_DURACION_INCIDENTE(v_inc) || ' h');
END;
/

PROMPT ----- Incidentes criticos y estadisticas por tipo, linea y estacion -----

SELECT NUMERO_INCIDENTE, TIPO_INCIDENTE, ESTADO, LUGAR_AFECTADO, FECHA_HORA_INICIO,
       FN_DURACION_INCIDENTE(ID_INCIDENTE) AS HORAS
FROM INCIDENTE WHERE SEVERIDAD = 'CRITICO' ORDER BY FECHA_HORA_INICIO DESC;

SELECT TIPO_INCIDENTE, COUNT(*) AS INCIDENTES,
       SUM(CASE WHEN SEVERIDAD IN ('ALTO', 'CRITICO') THEN 1 ELSE 0 END) AS ALTOS_O_CRITICOS,
       ROUND(AVG(FN_DURACION_INCIDENTE(ID_INCIDENTE)), 1) AS HORAS_PROMEDIO,
       SUM(PASAJEROS_AFECTADOS) AS PASAJEROS_AFECTADOS
FROM INCIDENTE
GROUP BY TIPO_INCIDENTE
ORDER BY INCIDENTES DESC;

SELECT R.COD_LINEA, COUNT(DISTINCT IV.ID_INCIDENTE) AS INCIDENTES, COUNT(*) AS VIAJES_AFECTADOS,
       SUM(CASE WHEN IV.TIPO_AFECTACION = 'CANCELACION' THEN 1 ELSE 0 END) AS CANCELADOS,
       SUM(NVL(IV.MINUTOS_RETRASO, 0)) AS MINUTOS_DE_RETRASO
FROM INCIDENTE_VIAJE IV
JOIN VIAJE_PROGRAMADO V ON V.ID_VIAJE = IV.ID_VIAJE
JOIN RUTA R             ON R.ID_RUTA = V.ID_RUTA
GROUP BY R.COD_LINEA
ORDER BY INCIDENTES DESC;

SELECT E.NOMBRE AS ESTACION, COUNT(*) AS INCIDENTES
FROM INCIDENTE_ELEMENTO IE
JOIN ESTACION E ON E.ID_ESTACION = IE.ID_ESTACION
WHERE IE.TIPO_ELEMENTO = 'ESTACION'
GROUP BY E.NOMBRE
ORDER BY INCIDENTES DESC
FETCH FIRST 8 ROWS ONLY;

PROMPT ================= REGLAS PROTEGIDAS POR TRIGGERS (deben rechazarse) =================

BEGIN
    UPDATE TARJETA SET SALDO = -5 WHERE NUMERO_TARJETA = '7000000000000002';
    DBMS_OUTPUT.PUT_LINE('Saldo negativo: permitido (no esperado)');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Saldo negativo (regla 15) -> ' || SQLERRM);
END;
/

BEGIN
    UPDATE TARIFA SET MONTO = 3.50 WHERE ID_TARIFA = 2;                -- viaje individual vigente
    DBMS_OUTPUT.PUT_LINE('Cambio de precio: permitido (no esperado)');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Cambiar el precio de una tarifa (reglas 17 y 18) -> ' || SQLERRM);
END;
/

BEGIN
    UPDATE VIAJE_PROGRAMADO SET ID_TREN = 16 WHERE NUMERO_VIAJE = 'C-DT-LOC-P2-1000';
    DBMS_OUTPUT.PUT_LINE('Tren en mantenimiento: asignado (no esperado)');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Asignar un tren en mantenimiento (regla 11) -> ' || SQLERRM);
END;
/

BEGIN
    DELETE FROM VIAJE_PASAJERO WHERE ID_VIAJE_PASAJERO = 1;
    DBMS_OUTPUT.PUT_LINE('Borrado de historial: permitido (no esperado)');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Borrar un viaje del historial (regla 25) -> ' || SQLERRM);
END;
/

PROMPT ================= CONSULTAS OPERATIVAS CON LAS VISTAS Y FUNCIONES =================

SELECT ESTACION, COD_LINEA, SENTIDO, DESTINO, NUMERO_VIAJE, HORA_SALIDA_ESTIMADA, TREN
FROM VW_PROXIMAS_SALIDAS WHERE ID_ESTACION = 4
ORDER BY HORA_SALIDA_ESTIMADA FETCH FIRST 8 ROWS ONLY;

SELECT POSICION, NOMBRE, BOROUGH, INGRESOS, SALIDAS, FLUJO_TOTAL, MONTO_RECAUDADO
FROM VW_ESTACIONES_MAS_PASAJEROS ORDER BY POSICION FETCH FIRST 5 ROWS ONLY;

SELECT FECHA, COD_LINEA, PASAJEROS, MONTO_RECAUDADO FROM VW_INGRESOS_DIARIOS_LINEA
WHERE FECHA >= TRUNC(SYSDATE) - 2 ORDER BY FECHA, COD_LINEA;

SELECT FN_SALDO_TARJETA('7000000000000002')                       AS SALDO_TARJETA_2,
       FN_TARJETA_VALIDA('7000000000000009')                      AS VALIDA_9,
       FN_TREN_DISPONIBLE(16)                                     AS TREN_16_DISPONIBLE,
       FN_RUTA_OPERATIVA(5)                                       AS RUTA_5_OPERATIVA,
       FN_INGRESOS_ESTACION(4, TRUNC(SYSDATE) - 7, TRUNC(SYSDATE)) AS INGRESOS_TIMES_SQ_7D,
       FN_PASAJEROS_LINEA('7', TRUNC(SYSDATE) - 7, TRUNC(SYSDATE)) AS PASAJEROS_LINEA_7_7D
FROM DUAL;

PROMPT ----- Ultimos movimientos de la bitacora (generados por los triggers) -----

COLUMN VALOR_ANTERIOR FORMAT A20
COLUMN VALOR_NUEVO FORMAT A40
SELECT TABLA, ID_REGISTRO, OPERACION, CAMPO, VALOR_ANTERIOR, VALOR_NUEVO, FECHA_HORA
FROM BITACORA ORDER BY ID_BITACORA DESC FETCH FIRST 12 ROWS ONLY;
