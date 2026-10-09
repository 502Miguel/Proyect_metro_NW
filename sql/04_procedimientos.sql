/* =====================================================================
   SISTEMA DE GESTION - METRO DE NUEVA YORK
   04 - PROCEDIMIENTOS ALMACENADOS
   Requiere 03_funciones.sql.

   Los 6 procedimientos que pide el enunciado (SP_PROGRAMAR_VIAJE,
   SP_REGISTRAR_INGRESO, SP_RECARGAR_TARJETA, SP_CREAR_ORDEN_MANTENIMIENTO,
   SP_REGISTRAR_INCIDENTE, SP_CANCELAR_VIAJES_AFECTADOS) mas algunos de apoyo
   para las funcionalidades de los modulos 4 a 7.

   Codigos de error: -20001 a -20099. Cada procedimiento confirma (COMMIT)
   si todo sale bien y deshace (ROLLBACK) si algo falla.
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. SP_PROGRAMAR_VIAJE
   Programa un viaje validando: ruta operativa, tren disponible (reglas 8
   y 11), conductor con certificacion vigente para el modelo (regla 10) y
   sin otro viaje en ese horario (regla 9).
   --------------------------------------------------------------------- */
CREATE OR REPLACE PROCEDURE SP_PROGRAMAR_VIAJE (
    p_numero_viaje        IN  VARCHAR2,
    p_id_ruta             IN  NUMBER,
    p_salida              IN  DATE,
    p_id_tren             IN  NUMBER,
    p_id_conductor        IN  NUMBER,
    p_id_horario          IN  NUMBER DEFAULT NULL,
    p_pasajeros_estimados IN  NUMBER DEFAULT NULL,
    p_id_viaje            OUT NUMBER)
IS
    v_duracion RUTA.DURACION_ESTIMADA_MIN%TYPE;
    v_llegada  DATE;
    v_modelo   TREN.ID_MODELO%TYPE;
    v_cruces   NUMBER;
BEGIN
    IF p_salida < SYSDATE THEN
        RAISE_APPLICATION_ERROR(-20001, 'La hora de salida debe ser futura');
    END IF;

    IF FN_RUTA_OPERATIVA(p_id_ruta, p_salida) = 'N' THEN
        RAISE_APPLICATION_ERROR(-20002, 'La ruta ' || p_id_ruta || ' no existe o no esta operativa');
    END IF;

    SELECT DURACION_ESTIMADA_MIN INTO v_duracion FROM RUTA WHERE ID_RUTA = p_id_ruta;
    v_llegada := p_salida + NVL(v_duracion, 60) / 1440;

    IF FN_TREN_DISPONIBLE(p_id_tren, p_salida, v_llegada) = 'N' THEN
        RAISE_APPLICATION_ERROR(-20003, 'El tren ' || p_id_tren || ' no esta disponible: revise su estado, '
            || 'mantenimientos pendientes, inspeccion vencida o si ya tiene un viaje en ese horario');
    END IF;

    SELECT ID_MODELO INTO v_modelo FROM TREN WHERE ID_TREN = p_id_tren;
    IF FN_CONDUCTOR_HABILITADO(p_id_conductor, v_modelo, p_salida) = 'N' THEN
        RAISE_APPLICATION_ERROR(-20004, 'El empleado ' || p_id_conductor || ' no puede conducir este tren: '
            || 'no es conductor activo, no tiene certificacion vigente para el modelo o esta ausente');
    END IF;

    SELECT COUNT(*) INTO v_cruces
    FROM VIAJE_PROGRAMADO
    WHERE ID_CONDUCTOR = p_id_conductor
      AND ESTADO_VIAJE <> 'CANCELADO'
      AND SALIDA_PROGRAMADA < v_llegada
      AND LLEGADA_PROGRAMADA > p_salida;
    IF v_cruces > 0 THEN
        RAISE_APPLICATION_ERROR(-20005, 'El conductor ' || p_id_conductor || ' ya tiene un viaje en ese horario');
    END IF;

    INSERT INTO VIAJE_PROGRAMADO (NUMERO_VIAJE, ID_RUTA, ID_HORARIO, FECHA_VIAJE, SALIDA_PROGRAMADA,
                                  LLEGADA_PROGRAMADA, ID_TREN, ID_CONDUCTOR, ESTADO_VIAJE, PASAJEROS_ESTIMADOS)
    VALUES (p_numero_viaje, p_id_ruta, p_id_horario, TRUNC(p_salida), p_salida,
            v_llegada, p_id_tren, p_id_conductor, 'PROGRAMADO', p_pasajeros_estimados)
    RETURNING ID_VIAJE INTO p_id_viaje;

    COMMIT;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20006, 'La ruta o el tren indicados no existen');
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

/* ---------------------------------------------------------------------
   2. SP_REGISTRAR_INGRESO
   Valida la tarjeta, calcula la tarifa vigente, descuenta el saldo y
   registra el ingreso. Si el ingreso no procede, deja registrado el
   intento como RECHAZADO y devuelve el motivo como error.
   Con p_tipo_acceso = 'BOLETO' registra un viaje anonimo sin tarjeta.
   --------------------------------------------------------------------- */
CREATE OR REPLACE PROCEDURE SP_REGISTRAR_INGRESO (
    p_numero_tarjeta    IN  VARCHAR2,
    p_id_estacion       IN  NUMBER,
    p_tipo_acceso       IN  VARCHAR2 DEFAULT 'TARJETA',
    p_id_viaje_pasajero OUT NUMBER)
IS
    v_estado_estacion ESTACION.ESTADO_OPERATIVO%TYPE;
    v_tarjeta         TARJETA%ROWTYPE;
    v_tarifa          TARIFA%ROWTYPE;
    v_codigo          TARIFA.CODIGO_TARIFA%TYPE;
    v_monto           NUMBER;
    v_cuenta          NUMBER;
    v_motivo          VARCHAR2(200);
    v_transaccion     VARCHAR2(30) := 'VP-' || TO_CHAR(SYSTIMESTAMP, 'YYMMDDHH24MISSFF6');
BEGIN
    SELECT ESTADO_OPERATIVO INTO v_estado_estacion FROM ESTACION WHERE ID_ESTACION = p_id_estacion;

    -- Viaje anonimo con boleto: tarifa de viaje individual vigente
    IF p_tipo_acceso = 'BOLETO' THEN
        IF v_estado_estacion <> 'OPERATIVA' THEN
            RAISE_APPLICATION_ERROR(-20010, 'Ingreso rechazado: la estacion no esta operativa');
        END IF;
        SELECT * INTO v_tarifa FROM TARIFA WHERE ID_TARIFA = FN_TARIFA_VIGENTE('VIAJE_IND');
        INSERT INTO VIAJE_PASAJERO (NUMERO_TRANSACCION, TIPO_ACCESO, NUMERO_TARJETA, ID_ESTACION_INGRESO,
                                    FECHA_HORA_INGRESO, ID_TARIFA, MONTO_COBRADO, ESTADO)
        VALUES (v_transaccion, 'BOLETO', NULL, p_id_estacion, SYSDATE, v_tarifa.ID_TARIFA, v_tarifa.MONTO, 'CERRADO')
        RETURNING ID_VIAJE_PASAJERO INTO p_id_viaje_pasajero;
        COMMIT;
        RETURN;
    END IF;

    -- Tarjeta (se bloquea la fila para que dos ingresos simultaneos no descuenten dos veces)
    SELECT * INTO v_tarjeta FROM TARJETA WHERE NUMERO_TARJETA = p_numero_tarjeta FOR UPDATE;

    -- Tarifa: el precio vigente HOY del producto de la tarjeta (regla 18: se guarda en el viaje)
    SELECT CODIGO_TARIFA INTO v_codigo FROM TARIFA WHERE ID_TARIFA = v_tarjeta.ID_TARIFA;
    SELECT * INTO v_tarifa FROM TARIFA WHERE ID_TARIFA = FN_TARIFA_VIGENTE(v_codigo);
    -- Los pases ilimitados se pagan al comprarlos, no en cada viaje
    v_monto := CASE WHEN v_tarifa.PRODUCTO IN ('PASE_DIARIO', 'PASE_SEMANAL', 'PASE_MENSUAL') THEN 0
                    ELSE v_tarifa.MONTO END;

    -- Validaciones (reglas 15, 16 y 21)
    IF v_estado_estacion <> 'OPERATIVA' THEN
        v_motivo := 'la estacion no esta operativa';
    ELSIF v_tarjeta.ESTADO <> 'ACTIVA' THEN
        v_motivo := 'la tarjeta esta ' || v_tarjeta.ESTADO;
    ELSIF v_tarjeta.FECHA_VENCIMIENTO < TRUNC(SYSDATE) THEN
        v_motivo := 'la tarjeta esta vencida';
        UPDATE TARJETA SET ESTADO = 'VENCIDA' WHERE NUMERO_TARJETA = p_numero_tarjeta;
    ELSE
        SELECT COUNT(*) INTO v_cuenta FROM VIAJE_PASAJERO
        WHERE NUMERO_TARJETA = p_numero_tarjeta AND ESTADO = 'ABIERTO';
        IF v_cuenta > 0 THEN
            v_motivo := 'la tarjeta ya tiene un viaje abierto';
        ELSIF v_tarifa.MAX_VIAJES IS NOT NULL THEN
            SELECT COUNT(*) INTO v_cuenta FROM VIAJE_PASAJERO
            WHERE NUMERO_TARJETA = p_numero_tarjeta
              AND ESTADO IN ('ABIERTO', 'CERRADO')
              AND FECHA_HORA_INGRESO >= TRUNC(SYSDATE);
            IF v_cuenta >= v_tarifa.MAX_VIAJES THEN
                v_motivo := 'se alcanzo el maximo de ' || v_tarifa.MAX_VIAJES || ' viajes del dia';
            END IF;
        END IF;
        IF v_motivo IS NULL AND v_tarjeta.SALDO < v_monto THEN
            v_motivo := 'saldo insuficiente (saldo ' || v_tarjeta.SALDO || ', tarifa ' || v_monto || ')';
        END IF;
    END IF;

    IF v_motivo IS NOT NULL THEN
        INSERT INTO VIAJE_PASAJERO (NUMERO_TRANSACCION, TIPO_ACCESO, NUMERO_TARJETA, ID_ESTACION_INGRESO,
                                    FECHA_HORA_INGRESO, ID_TARIFA, MONTO_COBRADO, ESTADO)
        VALUES (v_transaccion, 'TARJETA', p_numero_tarjeta, p_id_estacion, SYSDATE, v_tarifa.ID_TARIFA, 0, 'RECHAZADO');
        COMMIT;
        RAISE_APPLICATION_ERROR(-20012, 'Ingreso rechazado: ' || v_motivo);
    END IF;

    UPDATE TARJETA SET SALDO = SALDO - v_monto WHERE NUMERO_TARJETA = p_numero_tarjeta;

    INSERT INTO VIAJE_PASAJERO (NUMERO_TRANSACCION, TIPO_ACCESO, NUMERO_TARJETA, ID_ESTACION_INGRESO,
                                FECHA_HORA_INGRESO, ID_TARIFA, MONTO_COBRADO, ESTADO)
    VALUES (v_transaccion, 'TARJETA', p_numero_tarjeta, p_id_estacion, SYSDATE, v_tarifa.ID_TARIFA, v_monto, 'ABIERTO')
    RETURNING ID_VIAJE_PASAJERO INTO p_id_viaje_pasajero;

    COMMIT;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20011, 'La tarjeta o la estacion indicadas no existen');
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

-- Apoyo modulo 5: registrar la salida de un viaje abierto
CREATE OR REPLACE PROCEDURE SP_REGISTRAR_SALIDA (
    p_numero_tarjeta IN VARCHAR2,
    p_id_estacion    IN NUMBER)
IS
BEGIN
    UPDATE VIAJE_PASAJERO
    SET ID_ESTACION_SALIDA = p_id_estacion,
        FECHA_HORA_SALIDA  = SYSDATE,
        ESTADO             = 'CERRADO'
    WHERE NUMERO_TARJETA = p_numero_tarjeta
      AND ESTADO = 'ABIERTO';

    IF SQL%ROWCOUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20013, 'La tarjeta ' || p_numero_tarjeta || ' no tiene un viaje abierto');
    END IF;
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

/* ---------------------------------------------------------------------
   3. SP_RECARGAR_TARJETA
   Registra la recarga con saldo anterior y posterior y actualiza el saldo.
   --------------------------------------------------------------------- */
CREATE OR REPLACE PROCEDURE SP_RECARGAR_TARJETA (
    p_numero_tarjeta IN  VARCHAR2,
    p_monto          IN  NUMBER,
    p_medio_pago     IN  VARCHAR2,
    p_canal          IN  VARCHAR2 DEFAULT 'ESTACION',
    p_id_estacion    IN  NUMBER DEFAULT NULL,
    p_id_recarga     OUT NUMBER)
IS
    v_saldo       TARJETA.SALDO%TYPE;
    v_estado      TARJETA.ESTADO%TYPE;
    v_vencimiento TARJETA.FECHA_VENCIMIENTO%TYPE;
BEGIN
    IF p_monto IS NULL OR p_monto <= 0 THEN
        RAISE_APPLICATION_ERROR(-20020, 'El monto de la recarga debe ser mayor que cero');
    END IF;

    SELECT SALDO, ESTADO, FECHA_VENCIMIENTO INTO v_saldo, v_estado, v_vencimiento
    FROM TARJETA WHERE NUMERO_TARJETA = p_numero_tarjeta FOR UPDATE;

    IF v_estado <> 'ACTIVA' OR v_vencimiento < TRUNC(SYSDATE) THEN
        RAISE_APPLICATION_ERROR(-20021, 'No se puede recargar: la tarjeta esta '
            || CASE WHEN v_estado <> 'ACTIVA' THEN v_estado ELSE 'VENCIDA' END);
    END IF;

    INSERT INTO RECARGA (NUMERO_TRANSACCION, NUMERO_TARJETA, FECHA_HORA, MONTO, MEDIO_PAGO, CANAL,
                         ID_ESTACION, SALDO_ANTERIOR, SALDO_POSTERIOR)
    VALUES ('RC-' || TO_CHAR(SYSTIMESTAMP, 'YYMMDDHH24MISSFF6'), p_numero_tarjeta, SYSDATE, p_monto, p_medio_pago,
            p_canal, p_id_estacion, v_saldo, v_saldo + p_monto)
    RETURNING ID_RECARGA INTO p_id_recarga;

    UPDATE TARJETA SET SALDO = v_saldo + p_monto WHERE NUMERO_TARJETA = p_numero_tarjeta;

    COMMIT;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20022, 'La tarjeta ' || p_numero_tarjeta || ' no existe');
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

/* ---------------------------------------------------------------------
   4. SP_CREAR_ORDEN_MANTENIMIENTO
   Crea la orden (numero OM-AAAA-NNNN) y asigna al tecnico responsable.
   Si es correctiva de prioridad ALTA o URGENTE, el equipo pasa a
   EN_MANTENIMIENTO y, si el equipo es un tren, tambien el tren.
   --------------------------------------------------------------------- */
CREATE OR REPLACE PROCEDURE SP_CREAR_ORDEN_MANTENIMIENTO (
    p_id_equipo        IN  NUMBER,
    p_tipo             IN  VARCHAR2,
    p_descripcion      IN  VARCHAR2,
    p_prioridad        IN  VARCHAR2 DEFAULT 'MEDIA',
    p_fecha_programada IN  DATE DEFAULT NULL,
    p_id_tecnico       IN  NUMBER DEFAULT NULL,
    p_id_orden         OUT NUMBER)
IS
    v_estado_equipo EQUIPO.ESTADO%TYPE;
    v_id_tren       EQUIPO.ID_TREN%TYPE;
    v_anio          VARCHAR2(4) := TO_CHAR(SYSDATE, 'YYYY');
    v_siguiente     NUMBER;
BEGIN
    SELECT ESTADO, ID_TREN INTO v_estado_equipo, v_id_tren
    FROM EQUIPO WHERE ID_EQUIPO = p_id_equipo FOR UPDATE;

    IF v_estado_equipo = 'RETIRADO' THEN
        RAISE_APPLICATION_ERROR(-20030, 'El equipo ' || p_id_equipo || ' esta retirado');
    END IF;
    IF p_fecha_programada < TRUNC(SYSDATE) THEN
        RAISE_APPLICATION_ERROR(-20031, 'La fecha programada no puede ser pasada');
    END IF;

    SELECT NVL(MAX(TO_NUMBER(SUBSTR(NUMERO_ORDEN, 9))), 0) + 1 INTO v_siguiente
    FROM ORDEN_MANTENIMIENTO WHERE NUMERO_ORDEN LIKE 'OM-' || v_anio || '-%';

    INSERT INTO ORDEN_MANTENIMIENTO (NUMERO_ORDEN, ID_EQUIPO, TIPO_MANTENIMIENTO, DESCRIPCION, FECHA_SOLICITUD,
                                     FECHA_PROGRAMADA, ID_TECNICO_RESPONSABLE, PRIORIDAD, ESTADO)
    VALUES ('OM-' || v_anio || '-' || LPAD(v_siguiente, 4, '0'), p_id_equipo, p_tipo, p_descripcion, SYSDATE,
            p_fecha_programada, p_id_tecnico, p_prioridad,
            CASE WHEN p_fecha_programada IS NOT NULL THEN 'PROGRAMADA' ELSE 'SOLICITADA' END)
    RETURNING ID_ORDEN INTO p_id_orden;

    IF p_id_tecnico IS NOT NULL THEN
        INSERT INTO ORDEN_TECNICO (ID_ORDEN, ID_EMPLEADO) VALUES (p_id_orden, p_id_tecnico);
    END IF;

    IF p_tipo = 'CORRECTIVO' AND p_prioridad IN ('ALTA', 'URGENTE') THEN
        UPDATE EQUIPO SET ESTADO = 'EN_MANTENIMIENTO'
        WHERE ID_EQUIPO = p_id_equipo AND ESTADO = 'DISPONIBLE';
        IF v_id_tren IS NOT NULL THEN
            UPDATE TREN SET ESTADO_OPERATIVO = 'EN_MANTENIMIENTO'
            WHERE ID_TREN = v_id_tren AND ESTADO_OPERATIVO IN ('DISPONIBLE', 'EN_OPERACION');
        END IF;
    END IF;

    COMMIT;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20032, 'El equipo ' || p_id_equipo || ' no existe');
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

-- Apoyo modulo 6: cambiar el estado de una orden.
-- Al completarla, el equipo (y el tren, si aplica) vuelve a DISPONIBLE y se
-- actualizan la fecha de ultima revision y la proxima inspeccion.
CREATE OR REPLACE PROCEDURE SP_ACTUALIZAR_ESTADO_ORDEN (
    p_id_orden              IN NUMBER,
    p_nuevo_estado          IN VARCHAR2,
    p_dias_proxima_revision IN NUMBER DEFAULT 90)
IS
    v_estado    ORDEN_MANTENIMIENTO.ESTADO%TYPE;
    v_id_equipo ORDEN_MANTENIMIENTO.ID_EQUIPO%TYPE;
    v_id_tren   EQUIPO.ID_TREN%TYPE;
    v_abiertas  NUMBER;
BEGIN
    SELECT o.ESTADO, o.ID_EQUIPO, e.ID_TREN INTO v_estado, v_id_equipo, v_id_tren
    FROM ORDEN_MANTENIMIENTO o JOIN EQUIPO e ON e.ID_EQUIPO = o.ID_EQUIPO
    WHERE o.ID_ORDEN = p_id_orden FOR UPDATE OF o.ESTADO;

    IF v_estado IN ('COMPLETADA', 'CANCELADA') THEN
        RAISE_APPLICATION_ERROR(-20033, 'La orden ' || p_id_orden || ' ya esta ' || v_estado);
    END IF;

    UPDATE ORDEN_MANTENIMIENTO
    SET ESTADO       = p_nuevo_estado,
        FECHA_INICIO = CASE WHEN p_nuevo_estado IN ('EN_EJECUCION', 'COMPLETADA') THEN NVL(FECHA_INICIO, SYSDATE)
                            ELSE FECHA_INICIO END,
        FECHA_FIN    = CASE WHEN p_nuevo_estado = 'COMPLETADA' THEN SYSDATE ELSE FECHA_FIN END
    WHERE ID_ORDEN = p_id_orden;

    IF p_nuevo_estado = 'EN_EJECUCION' THEN
        UPDATE EQUIPO SET ESTADO = 'EN_MANTENIMIENTO' WHERE ID_EQUIPO = v_id_equipo AND ESTADO = 'DISPONIBLE';
        IF v_id_tren IS NOT NULL THEN
            UPDATE TREN SET ESTADO_OPERATIVO = 'EN_MANTENIMIENTO'
            WHERE ID_TREN = v_id_tren AND ESTADO_OPERATIVO = 'DISPONIBLE';
        END IF;

    ELSIF p_nuevo_estado = 'COMPLETADA' THEN
        SELECT COUNT(*) INTO v_abiertas FROM ORDEN_MANTENIMIENTO
        WHERE ID_EQUIPO = v_id_equipo AND ID_ORDEN <> p_id_orden AND ESTADO = 'EN_EJECUCION';

        UPDATE EQUIPO
        SET FECHA_ULTIMA_REVISION  = TRUNC(SYSDATE),
            FECHA_PROXIMA_REVISION = TRUNC(SYSDATE) + p_dias_proxima_revision,
            ESTADO = CASE WHEN v_abiertas = 0 AND ESTADO IN ('EN_MANTENIMIENTO', 'FUERA_DE_SERVICIO')
                          THEN 'DISPONIBLE' ELSE ESTADO END
        WHERE ID_EQUIPO = v_id_equipo;

        IF v_id_tren IS NOT NULL THEN
            UPDATE TREN
            SET FECHA_ULTIMA_INSPECCION  = TRUNC(SYSDATE),
                FECHA_PROXIMA_INSPECCION = TRUNC(SYSDATE) + p_dias_proxima_revision,
                ESTADO_OPERATIVO = CASE WHEN v_abiertas = 0 AND ESTADO_OPERATIVO IN ('EN_MANTENIMIENTO', 'FUERA_DE_SERVICIO')
                                        THEN 'DISPONIBLE' ELSE ESTADO_OPERATIVO END
            WHERE ID_TREN = v_id_tren;
        END IF;
    END IF;

    COMMIT;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20034, 'La orden ' || p_id_orden || ' no existe');
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

/* ---------------------------------------------------------------------
   Apoyo modulo 7: asociar un elemento afectado a un incidente y aplicar
   su efecto (cerrar estacion o plataforma, retirar tren, marcar equipo
   fuera de servicio o ruta afectada). Lo usa SP_REGISTRAR_INCIDENTE.
   Para un TRAMO: p_id_elemento = estacion inicial, mas linea y estacion final.
   --------------------------------------------------------------------- */
CREATE OR REPLACE PROCEDURE SP_AGREGAR_ELEMENTO_INCIDENTE (
    p_id_incidente    IN NUMBER,
    p_tipo_elemento   IN VARCHAR2,
    p_id_elemento     IN NUMBER,
    p_efecto          IN VARCHAR2 DEFAULT 'AFECTACION_PARCIAL',
    p_cod_linea       IN VARCHAR2 DEFAULT NULL,
    p_id_estacion_fin IN NUMBER DEFAULT NULL,
    p_confirmar       IN BOOLEAN DEFAULT TRUE)
IS
BEGIN
    -- Cada efecto solo tiene sentido para un tipo de elemento
    IF (p_efecto = 'CIERRE_ESTACION'   AND p_tipo_elemento <> 'ESTACION')
    OR (p_efecto = 'CIERRE_PLATAFORMA' AND p_tipo_elemento <> 'PLATAFORMA')
    OR (p_efecto = 'RETIRO_TREN'       AND p_tipo_elemento <> 'TREN')
    OR (p_efecto = 'FALLA_EQUIPO'      AND p_tipo_elemento <> 'EQUIPO')
    OR (p_efecto = 'CAMBIO_RUTA'       AND p_tipo_elemento <> 'RUTA')
    OR (p_efecto = 'SUSPENSION_TRAMO'  AND p_tipo_elemento <> 'TRAMO') THEN
        RAISE_APPLICATION_ERROR(-20040, 'El efecto ' || p_efecto || ' no aplica a un elemento de tipo ' || p_tipo_elemento);
    END IF;

    INSERT INTO INCIDENTE_ELEMENTO (ID_INCIDENTE, TIPO_ELEMENTO, ID_ESTACION, ID_ESTACION_FIN, COD_LINEA,
                                    ID_PLATAFORMA, ID_TREN, ID_RUTA, ID_EQUIPO, EFECTO)
    VALUES (p_id_incidente, p_tipo_elemento,
            CASE WHEN p_tipo_elemento IN ('ESTACION', 'TRAMO') THEN p_id_elemento END,
            CASE WHEN p_tipo_elemento = 'TRAMO' THEN p_id_estacion_fin END,
            CASE WHEN p_tipo_elemento = 'TRAMO' THEN p_cod_linea END,
            CASE WHEN p_tipo_elemento = 'PLATAFORMA' THEN p_id_elemento END,
            CASE WHEN p_tipo_elemento = 'TREN' THEN p_id_elemento END,
            CASE WHEN p_tipo_elemento = 'RUTA' THEN p_id_elemento END,
            CASE WHEN p_tipo_elemento = 'EQUIPO' THEN p_id_elemento END,
            p_efecto);

    IF p_efecto = 'CIERRE_ESTACION' THEN
        UPDATE ESTACION SET ESTADO_OPERATIVO = 'CERRADA_TEMPORAL' WHERE ID_ESTACION = p_id_elemento;
        -- Las rutas que se detienen en la estacion quedan afectadas
        UPDATE RUTA SET ESTADO = 'AFECTADA_POR_CIERRE'
        WHERE ESTADO = 'ACTIVA'
          AND ID_RUTA IN (SELECT ID_RUTA FROM DETALLE_RUTA WHERE ID_ESTACION = p_id_elemento AND SE_DETIENE = 'S');
    ELSIF p_efecto = 'CIERRE_PLATAFORMA' THEN
        UPDATE PLATAFORMA SET ESTADO_OPERATIVO = 'CERRADA' WHERE ID_PLATAFORMA = p_id_elemento;
    ELSIF p_efecto = 'RETIRO_TREN' THEN
        UPDATE TREN SET ESTADO_OPERATIVO = 'FUERA_DE_SERVICIO' WHERE ID_TREN = p_id_elemento;
    ELSIF p_efecto = 'FALLA_EQUIPO' THEN
        UPDATE EQUIPO SET ESTADO = 'FUERA_DE_SERVICIO' WHERE ID_EQUIPO = p_id_elemento;
    ELSIF p_efecto = 'CAMBIO_RUTA' THEN
        UPDATE RUTA SET ESTADO = 'AFECTADA_POR_CIERRE' WHERE ID_RUTA = p_id_elemento;
    END IF;

    IF p_confirmar THEN
        COMMIT;
    END IF;
END;
/

/* ---------------------------------------------------------------------
   5. SP_REGISTRAR_INCIDENTE
   Registra el incidente (numero INC-AAAA-NNNN) y, si se indica, su primer
   elemento afectado. Mas elementos: SP_AGREGAR_ELEMENTO_INCIDENTE.
   --------------------------------------------------------------------- */
CREATE OR REPLACE PROCEDURE SP_REGISTRAR_INCIDENTE (
    p_tipo                IN  VARCHAR2,
    p_descripcion         IN  VARCHAR2,
    p_lugar               IN  VARCHAR2,
    p_severidad           IN  VARCHAR2,
    p_id_reportado_por    IN  NUMBER,
    p_tipo_elemento       IN  VARCHAR2 DEFAULT NULL,
    p_id_elemento         IN  NUMBER DEFAULT NULL,
    p_efecto              IN  VARCHAR2 DEFAULT 'AFECTACION_PARCIAL',
    p_pasajeros_afectados IN  NUMBER DEFAULT NULL,
    p_id_incidente        OUT NUMBER)
IS
    v_anio      VARCHAR2(4) := TO_CHAR(SYSDATE, 'YYYY');
    v_siguiente NUMBER;
BEGIN
    SELECT NVL(MAX(TO_NUMBER(SUBSTR(NUMERO_INCIDENTE, 10))), 0) + 1 INTO v_siguiente
    FROM INCIDENTE WHERE NUMERO_INCIDENTE LIKE 'INC-' || v_anio || '-%';

    INSERT INTO INCIDENTE (NUMERO_INCIDENTE, TIPO_INCIDENTE, DESCRIPCION, FECHA_HORA_INICIO, LUGAR_AFECTADO,
                           SEVERIDAD, ID_REPORTADO_POR, ESTADO, PASAJEROS_AFECTADOS)
    VALUES ('INC-' || v_anio || '-' || LPAD(v_siguiente, 4, '0'), p_tipo, p_descripcion, SYSDATE, p_lugar,
            p_severidad, p_id_reportado_por, 'ABIERTO', p_pasajeros_afectados)
    RETURNING ID_INCIDENTE INTO p_id_incidente;

    IF p_tipo_elemento IS NOT NULL THEN
        SP_AGREGAR_ELEMENTO_INCIDENTE(p_id_incidente, p_tipo_elemento, p_id_elemento, p_efecto,
                                      p_confirmar => FALSE);
    END IF;

    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

-- Apoyo modulo 7: cerrar un incidente con su causa y acciones correctivas.
-- Reabre las estaciones y plataformas que cerro y reactiva las rutas que ya
-- no tengan paradas cerradas ni otro incidente abierto.
CREATE OR REPLACE PROCEDURE SP_CERRAR_INCIDENTE (
    p_id_incidente IN NUMBER,
    p_causa        IN VARCHAR2 DEFAULT NULL,
    p_acciones     IN VARCHAR2 DEFAULT NULL)
IS
BEGIN
    UPDATE INCIDENTE
    SET ESTADO              = 'CERRADO',
        FECHA_HORA_FIN      = SYSDATE,
        CAUSA_IDENTIFICADA  = NVL(p_causa, CAUSA_IDENTIFICADA),
        ACCIONES_REALIZADAS = NVL(p_acciones, ACCIONES_REALIZADAS)
    WHERE ID_INCIDENTE = p_id_incidente AND ESTADO <> 'CERRADO';

    IF SQL%ROWCOUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20041, 'El incidente ' || p_id_incidente || ' no existe o ya esta cerrado');
    END IF;

    FOR el IN (SELECT * FROM INCIDENTE_ELEMENTO WHERE ID_INCIDENTE = p_id_incidente) LOOP
        IF el.EFECTO = 'CIERRE_ESTACION' THEN
            UPDATE ESTACION SET ESTADO_OPERATIVO = 'OPERATIVA'
            WHERE ID_ESTACION = el.ID_ESTACION AND ESTADO_OPERATIVO = 'CERRADA_TEMPORAL';
        ELSIF el.EFECTO = 'CIERRE_PLATAFORMA' THEN
            UPDATE PLATAFORMA SET ESTADO_OPERATIVO = 'OPERATIVA'
            WHERE ID_PLATAFORMA = el.ID_PLATAFORMA AND ESTADO_OPERATIVO = 'CERRADA';
        END IF;
    END LOOP;

    UPDATE RUTA r SET ESTADO = 'ACTIVA'
    WHERE r.ESTADO = 'AFECTADA_POR_CIERRE'
      AND NOT EXISTS (SELECT 1 FROM DETALLE_RUTA d JOIN ESTACION e ON e.ID_ESTACION = d.ID_ESTACION
                      WHERE d.ID_RUTA = r.ID_RUTA AND d.SE_DETIENE = 'S' AND e.ESTADO_OPERATIVO <> 'OPERATIVA')
      AND NOT EXISTS (SELECT 1 FROM INCIDENTE_ELEMENTO ie JOIN INCIDENTE i ON i.ID_INCIDENTE = ie.ID_INCIDENTE
                      WHERE ie.ID_RUTA = r.ID_RUTA AND i.ESTADO <> 'CERRADO');

    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

/* ---------------------------------------------------------------------
   6. SP_CANCELAR_VIAJES_AFECTADOS
   Cancela los viajes pendientes afectados por el cierre de una estacion
   (los que se detienen en ella) o de una ruta, dentro de un rango de
   fechas. Si se indica el incidente, queda registrado en INCIDENTE_VIAJE.
   --------------------------------------------------------------------- */
CREATE OR REPLACE PROCEDURE SP_CANCELAR_VIAJES_AFECTADOS (
    p_tipo         IN  VARCHAR2,              -- 'ESTACION' o 'RUTA'
    p_id           IN  NUMBER,
    p_desde        IN  DATE DEFAULT SYSDATE,
    p_hasta        IN  DATE DEFAULT NULL,
    p_id_incidente IN  NUMBER DEFAULT NULL,
    p_cancelados   OUT NUMBER)
IS
BEGIN
    IF p_tipo NOT IN ('ESTACION', 'RUTA') THEN
        RAISE_APPLICATION_ERROR(-20050, 'p_tipo debe ser ESTACION o RUTA');
    END IF;

    p_cancelados := 0;
    FOR v IN (SELECT vp.ID_VIAJE
              FROM VIAJE_PROGRAMADO vp
              WHERE vp.ESTADO_VIAJE IN ('PROGRAMADO', 'RETRASADO', 'EN_ABORDAJE')
                AND vp.SALIDA_PROGRAMADA >= p_desde
                AND (p_hasta IS NULL OR vp.SALIDA_PROGRAMADA <= p_hasta)
                AND ((p_tipo = 'RUTA' AND vp.ID_RUTA = p_id)
                  OR (p_tipo = 'ESTACION' AND EXISTS (SELECT 1 FROM DETALLE_RUTA d
                                                      WHERE d.ID_RUTA = vp.ID_RUTA
                                                        AND d.ID_ESTACION = p_id
                                                        AND d.SE_DETIENE = 'S')))
              FOR UPDATE)
    LOOP
        UPDATE VIAJE_PROGRAMADO SET ESTADO_VIAJE = 'CANCELADO' WHERE ID_VIAJE = v.ID_VIAJE;

        IF p_id_incidente IS NOT NULL THEN
            MERGE INTO INCIDENTE_VIAJE iv
            USING (SELECT p_id_incidente AS ID_INCIDENTE, v.ID_VIAJE AS ID_VIAJE FROM DUAL) s
            ON (iv.ID_INCIDENTE = s.ID_INCIDENTE AND iv.ID_VIAJE = s.ID_VIAJE)
            WHEN MATCHED THEN UPDATE SET iv.TIPO_AFECTACION = 'CANCELACION'
            WHEN NOT MATCHED THEN INSERT (ID_INCIDENTE, ID_VIAJE, TIPO_AFECTACION)
                                  VALUES (s.ID_INCIDENTE, s.ID_VIAJE, 'CANCELACION');
        END IF;

        p_cancelados := p_cancelados + 1;
    END LOOP;

    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

-- Apoyo modulo 4: marca como vencidas las certificaciones cuya fecha ya paso.
-- El trigger TRG_CERTIFICACION_ALERTA deja la alerta en la BITACORA.
-- Se puede programar a diario con DBMS_SCHEDULER, por ejemplo:
--   BEGIN DBMS_SCHEDULER.CREATE_JOB(job_name => 'JOB_REVISAR_CERTIFICACIONES',
--     job_type => 'STORED_PROCEDURE', job_action => 'SP_REVISAR_CERTIFICACIONES',
--     repeat_interval => 'FREQ=DAILY;BYHOUR=6', enabled => TRUE); END;
CREATE OR REPLACE PROCEDURE SP_REVISAR_CERTIFICACIONES IS
BEGIN
    UPDATE CERTIFICACION SET ESTADO = 'VENCIDA'
    WHERE ESTADO = 'VIGENTE' AND FECHA_VENCIMIENTO < TRUNC(SYSDATE);
    COMMIT;
END;
/
