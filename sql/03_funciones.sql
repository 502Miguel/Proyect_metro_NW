/* =====================================================================
   SISTEMA DE GESTION - METRO DE NUEVA YORK
   03 - FUNCIONES PL/SQL
   Ejecutar despues de crear las tablas. Orden: 03 -> 04 -> 05 -> 06.

   Las funciones que responden "si / no" devuelven 'S' o 'N' (y no BOOLEAN)
   para poder usarlas dentro de consultas SQL y vistas.
   ===================================================================== */

-- 1. Duracion real de un viaje, en minutos (NULL si aun no termina)
CREATE OR REPLACE FUNCTION FN_DURACION_REAL_VIAJE (p_id_viaje IN NUMBER)
RETURN NUMBER IS
    v_salida  VIAJE_PROGRAMADO.SALIDA_REAL%TYPE;
    v_llegada VIAJE_PROGRAMADO.LLEGADA_REAL%TYPE;
BEGIN
    SELECT SALIDA_REAL, LLEGADA_REAL INTO v_salida, v_llegada
    FROM VIAJE_PROGRAMADO WHERE ID_VIAJE = p_id_viaje;

    IF v_salida IS NULL OR v_llegada IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN ROUND((v_llegada - v_salida) * 1440, 1);
EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN NULL;
END;
/

-- 2. Minutos de retraso en la salida de un viaje.
--    Si el viaje aun no sale y ya paso su hora, cuenta el retraso hasta ahora.
CREATE OR REPLACE FUNCTION FN_MINUTOS_RETRASO (p_id_viaje IN NUMBER)
RETURN NUMBER IS
    v_programada VIAJE_PROGRAMADO.SALIDA_PROGRAMADA%TYPE;
    v_real       VIAJE_PROGRAMADO.SALIDA_REAL%TYPE;
    v_estado     VIAJE_PROGRAMADO.ESTADO_VIAJE%TYPE;
BEGIN
    SELECT SALIDA_PROGRAMADA, SALIDA_REAL, ESTADO_VIAJE INTO v_programada, v_real, v_estado
    FROM VIAJE_PROGRAMADO WHERE ID_VIAJE = p_id_viaje;

    IF v_estado = 'CANCELADO' THEN
        RETURN NULL;
    ELSIF v_real IS NOT NULL THEN
        RETURN GREATEST(0, ROUND((v_real - v_programada) * 1440));
    ELSIF v_estado IN ('PROGRAMADO', 'EN_ABORDAJE', 'RETRASADO') AND SYSDATE > v_programada THEN
        RETURN ROUND((SYSDATE - v_programada) * 1440);
    END IF;
    RETURN 0;
EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN NULL;
END;
/

-- 3. Saldo de una tarjeta
CREATE OR REPLACE FUNCTION FN_SALDO_TARJETA (p_numero_tarjeta IN VARCHAR2)
RETURN NUMBER IS
    v_saldo TARJETA.SALDO%TYPE;
BEGIN
    SELECT SALDO INTO v_saldo FROM TARJETA WHERE NUMERO_TARJETA = p_numero_tarjeta;
    RETURN v_saldo;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20090, 'La tarjeta ' || p_numero_tarjeta || ' no existe');
END;
/

-- 4. Tarjeta valida: activa y no vencida (regla 16)
CREATE OR REPLACE FUNCTION FN_TARJETA_VALIDA (p_numero_tarjeta IN VARCHAR2)
RETURN VARCHAR2 IS
    v_estado      TARJETA.ESTADO%TYPE;
    v_vencimiento TARJETA.FECHA_VENCIMIENTO%TYPE;
BEGIN
    SELECT ESTADO, FECHA_VENCIMIENTO INTO v_estado, v_vencimiento
    FROM TARJETA WHERE NUMERO_TARJETA = p_numero_tarjeta;

    IF v_estado = 'ACTIVA' AND v_vencimiento >= TRUNC(SYSDATE) THEN
        RETURN 'S';
    END IF;
    RETURN 'N';
EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN 'N';
END;
/

-- Auxiliar: ID de la tarifa vigente de un codigo en una fecha (regla 17).
-- Un cambio de precio es una fila nueva con el mismo CODIGO_TARIFA.
CREATE OR REPLACE FUNCTION FN_TARIFA_VIGENTE (p_codigo IN VARCHAR2, p_fecha IN DATE DEFAULT SYSDATE)
RETURN NUMBER IS
    v_id TARIFA.ID_TARIFA%TYPE;
BEGIN
    SELECT ID_TARIFA INTO v_id FROM (
        SELECT ID_TARIFA FROM TARIFA
        WHERE CODIGO_TARIFA = p_codigo
          AND ESTADO <> 'INACTIVA'
          AND FECHA_INICIO_VIGENCIA <= p_fecha
          AND (FECHA_FIN_VIGENCIA IS NULL OR p_fecha < FECHA_FIN_VIGENCIA + 1)
        ORDER BY FECHA_INICIO_VIGENCIA DESC)
    WHERE ROWNUM = 1;
    RETURN v_id;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20091, 'No hay tarifa vigente para el codigo ' || p_codigo);
END;
/

-- 5. Ingresos (tarifas cobradas) de una estacion, opcionalmente entre dos fechas
CREATE OR REPLACE FUNCTION FN_INGRESOS_ESTACION (
    p_id_estacion IN NUMBER,
    p_desde       IN DATE DEFAULT NULL,
    p_hasta       IN DATE DEFAULT NULL)
RETURN NUMBER IS
    v_total NUMBER;
BEGIN
    SELECT NVL(SUM(MONTO_COBRADO), 0) INTO v_total
    FROM VIAJE_PASAJERO
    WHERE ID_ESTACION_INGRESO = p_id_estacion
      AND ESTADO IN ('ABIERTO', 'CERRADO')
      AND (p_desde IS NULL OR FECHA_HORA_INGRESO >= TRUNC(p_desde))
      AND (p_hasta IS NULL OR FECHA_HORA_INGRESO < TRUNC(p_hasta) + 1);
    RETURN v_total;
END;
/

-- 6. Pasajeros transportados por una linea.
--    El torniquete no sabe que linea toma el pasajero: en estaciones con
--    varias lineas, cada ingreso se reparte en partes iguales entre ellas.
CREATE OR REPLACE FUNCTION FN_PASAJEROS_LINEA (
    p_cod_linea IN VARCHAR2,
    p_desde     IN DATE DEFAULT NULL,
    p_hasta     IN DATE DEFAULT NULL)
RETURN NUMBER IS
    v_total NUMBER;
BEGIN
    SELECT NVL(SUM(1 / n.N_LINEAS), 0) INTO v_total
    FROM VIAJE_PASAJERO vp
    JOIN LINEA_ESTACION le ON le.ID_ESTACION = vp.ID_ESTACION_INGRESO
    JOIN (SELECT ID_ESTACION, COUNT(*) AS N_LINEAS FROM LINEA_ESTACION GROUP BY ID_ESTACION) n
      ON n.ID_ESTACION = vp.ID_ESTACION_INGRESO
    WHERE le.COD_LINEA = p_cod_linea
      AND vp.ESTADO IN ('ABIERTO', 'CERRADO')
      AND (p_desde IS NULL OR vp.FECHA_HORA_INGRESO >= TRUNC(p_desde))
      AND (p_hasta IS NULL OR vp.FECHA_HORA_INGRESO < TRUNC(p_hasta) + 1);
    RETURN ROUND(v_total, 1);
END;
/

-- 7. Tren disponible para un horario (reglas 8 y 11):
--    estado utilizable, inspeccion al dia, sin mantenimiento pendiente que
--    impida usarlo y sin otro viaje que se cruce en ese horario.
CREATE OR REPLACE FUNCTION FN_TREN_DISPONIBLE (
    p_id_tren         IN NUMBER,
    p_salida          IN DATE DEFAULT SYSDATE,
    p_llegada         IN DATE DEFAULT NULL,
    p_id_viaje_excluir IN NUMBER DEFAULT NULL)
RETURN VARCHAR2 IS
    v_estado      TREN.ESTADO_OPERATIVO%TYPE;
    v_inspeccion  TREN.FECHA_PROXIMA_INSPECCION%TYPE;
    v_llegada     DATE := NVL(p_llegada, p_salida + 1 / 1440);
    v_cuenta      NUMBER;
BEGIN
    SELECT ESTADO_OPERATIVO, FECHA_PROXIMA_INSPECCION INTO v_estado, v_inspeccion
    FROM TREN WHERE ID_TREN = p_id_tren;

    IF v_estado NOT IN ('DISPONIBLE', 'EN_OPERACION') THEN
        RETURN 'N';
    END IF;
    IF v_inspeccion IS NOT NULL AND v_inspeccion < TRUNC(p_salida) THEN
        RETURN 'N';   -- inspeccion vencida
    END IF;

    -- Mantenimiento pendiente que impide usarlo: orden en ejecucion o de prioridad alta/urgente
    SELECT COUNT(*) INTO v_cuenta
    FROM ORDEN_MANTENIMIENTO o
    JOIN EQUIPO e ON e.ID_EQUIPO = o.ID_EQUIPO
    WHERE e.ID_TREN = p_id_tren
      AND o.ESTADO IN ('SOLICITADA', 'PROGRAMADA', 'EN_EJECUCION', 'SUSPENDIDA')
      AND (o.ESTADO = 'EN_EJECUCION' OR o.PRIORIDAD IN ('ALTA', 'URGENTE'));
    IF v_cuenta > 0 THEN
        RETURN 'N';
    END IF;

    -- Otro viaje del mismo tren que se cruce en el horario
    SELECT COUNT(*) INTO v_cuenta
    FROM VIAJE_PROGRAMADO
    WHERE ID_TREN = p_id_tren
      AND ESTADO_VIAJE <> 'CANCELADO'
      AND ID_VIAJE <> NVL(p_id_viaje_excluir, -1)
      AND SALIDA_PROGRAMADA < v_llegada
      AND LLEGADA_PROGRAMADA > p_salida;
    IF v_cuenta > 0 THEN
        RETURN 'N';
    END IF;

    RETURN 'S';
EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN 'N';
END;
/

-- Auxiliar: conductor habilitado para un modelo de tren en una fecha (regla 10):
-- empleado activo con cargo CONDUCTOR, certificacion vigente que autorice
-- ese modelo y sin ausencia registrada ese dia.
CREATE OR REPLACE FUNCTION FN_CONDUCTOR_HABILITADO (
    p_id_empleado IN NUMBER,
    p_id_modelo   IN NUMBER,
    p_fecha       IN DATE DEFAULT SYSDATE)
RETURN VARCHAR2 IS
    v_estado EMPLEADO.ESTADO_LABORAL%TYPE;
    v_cargo  CARGO.NOMBRE_CARGO%TYPE;
    v_cuenta NUMBER;
BEGIN
    SELECT e.ESTADO_LABORAL, c.NOMBRE_CARGO INTO v_estado, v_cargo
    FROM EMPLEADO e JOIN CARGO c ON c.ID_CARGO = e.ID_CARGO
    WHERE e.ID_EMPLEADO = p_id_empleado;

    IF v_estado <> 'ACTIVO' OR v_cargo <> 'CONDUCTOR' THEN
        RETURN 'N';
    END IF;

    SELECT COUNT(*) INTO v_cuenta
    FROM CERTIFICACION ce
    JOIN CERTIFICACION_MODELO cm ON cm.ID_CERTIFICACION = ce.ID_CERTIFICACION
    WHERE ce.ID_EMPLEADO = p_id_empleado
      AND cm.ID_MODELO = p_id_modelo
      AND ce.ESTADO = 'VIGENTE'
      AND ce.FECHA_VENCIMIENTO >= TRUNC(p_fecha);
    IF v_cuenta = 0 THEN
        RETURN 'N';
    END IF;

    SELECT COUNT(*) INTO v_cuenta
    FROM AUSENCIA
    WHERE ID_EMPLEADO = p_id_empleado
      AND TRUNC(p_fecha) BETWEEN FECHA_INICIO AND FECHA_FIN;
    IF v_cuenta > 0 THEN
        RETURN 'N';
    END IF;

    RETURN 'S';
EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN 'N';
END;
/

-- 8. Ruta operativa: ruta y linea activas, ruta vigente en la fecha y
--    ninguna de sus paradas en una estacion cerrada.
CREATE OR REPLACE FUNCTION FN_RUTA_OPERATIVA (p_id_ruta IN NUMBER, p_fecha IN DATE DEFAULT SYSDATE)
RETURN VARCHAR2 IS
    v_estado_ruta  RUTA.ESTADO%TYPE;
    v_inicio       RUTA.FECHA_VIGENCIA_INICIO%TYPE;
    v_fin          RUTA.FECHA_VIGENCIA_FIN%TYPE;
    v_estado_linea LINEA.ESTADO_OPERATIVO%TYPE;
    v_cerradas     NUMBER;
BEGIN
    SELECT r.ESTADO, r.FECHA_VIGENCIA_INICIO, r.FECHA_VIGENCIA_FIN, l.ESTADO_OPERATIVO
    INTO v_estado_ruta, v_inicio, v_fin, v_estado_linea
    FROM RUTA r JOIN LINEA l ON l.COD_LINEA = r.COD_LINEA
    WHERE r.ID_RUTA = p_id_ruta;

    IF v_estado_ruta <> 'ACTIVA' OR v_estado_linea <> 'ACTIVA' THEN
        RETURN 'N';
    END IF;
    IF p_fecha < v_inicio OR (v_fin IS NOT NULL AND p_fecha >= v_fin + 1) THEN
        RETURN 'N';
    END IF;

    SELECT COUNT(*) INTO v_cerradas
    FROM DETALLE_RUTA d JOIN ESTACION e ON e.ID_ESTACION = d.ID_ESTACION
    WHERE d.ID_RUTA = p_id_ruta
      AND d.SE_DETIENE = 'S'
      AND e.ESTADO_OPERATIVO <> 'OPERATIVA';
    IF v_cerradas > 0 THEN
        RETURN 'N';
    END IF;

    RETURN 'S';
EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN 'N';
END;
/

-- 9. Costo total de una orden de mantenimiento: mano de obra + repuestos
CREATE OR REPLACE FUNCTION FN_COSTO_ORDEN (p_id_orden IN NUMBER)
RETURN NUMBER IS
    v_mano_obra ORDEN_MANTENIMIENTO.COSTO_MANO_OBRA%TYPE;
    v_repuestos NUMBER;
BEGIN
    SELECT COSTO_MANO_OBRA INTO v_mano_obra
    FROM ORDEN_MANTENIMIENTO WHERE ID_ORDEN = p_id_orden;

    SELECT NVL(SUM(CANTIDAD * COSTO_UNITARIO), 0) INTO v_repuestos
    FROM ORDEN_REPUESTO WHERE ID_ORDEN = p_id_orden;

    RETURN v_mano_obra + v_repuestos;
EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN NULL;
END;
/

-- Auxiliar (modulo 7): duracion de un incidente en horas (si sigue abierto, hasta ahora)
CREATE OR REPLACE FUNCTION FN_DURACION_INCIDENTE (p_id_incidente IN NUMBER)
RETURN NUMBER IS
    v_inicio INCIDENTE.FECHA_HORA_INICIO%TYPE;
    v_fin    INCIDENTE.FECHA_HORA_FIN%TYPE;
BEGIN
    SELECT FECHA_HORA_INICIO, FECHA_HORA_FIN INTO v_inicio, v_fin
    FROM INCIDENTE WHERE ID_INCIDENTE = p_id_incidente;
    RETURN ROUND((NVL(v_fin, SYSDATE) - v_inicio) * 24, 2);
EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN NULL;
END;
/
