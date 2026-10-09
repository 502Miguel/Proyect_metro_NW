/* =====================================================================
   SISTEMA DE GESTION - METRO DE NUEVA YORK
   05 - TRIGGERS
   Requiere 03_funciones.sql. Crear DESPUES de cargar los datos de prueba,
   para que las validaciones no interfieran con la carga inicial.

   Codigos de error: -20101 en adelante.
   ===================================================================== */

-- Auxiliar: escribe una fila en la BITACORA (dentro de la misma transaccion)
CREATE OR REPLACE PROCEDURE SP_BITACORA (
    p_tabla     IN VARCHAR2,
    p_id        IN VARCHAR2,
    p_operacion IN VARCHAR2,
    p_campo     IN VARCHAR2,
    p_anterior  IN VARCHAR2,
    p_nuevo     IN VARCHAR2)
IS
BEGIN
    INSERT INTO BITACORA (TABLA, ID_REGISTRO, OPERACION, CAMPO, VALOR_ANTERIOR, VALOR_NUEVO)
    VALUES (p_tabla, p_id, p_operacion, p_campo, p_anterior, p_nuevo);
END;
/

/* ---------------------------------------------------------------------
   1. Impedir que el saldo de una tarjeta sea negativo (regla 15)
   --------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER TRG_TARJETA_SALDO
BEFORE INSERT OR UPDATE OF SALDO ON TARJETA
FOR EACH ROW
BEGIN
    IF :NEW.SALDO < 0 THEN
        RAISE_APPLICATION_ERROR(-20101, 'Saldo insuficiente: la tarjeta ' || :NEW.NUMERO_TARJETA
            || ' quedaria con saldo negativo (' || :NEW.SALDO || ')');
    END IF;
END;
/

/* ---------------------------------------------------------------------
   2. Registrar cambios de estado de los trenes
   --------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER TRG_TREN_CAMBIO_ESTADO
AFTER UPDATE OF ESTADO_OPERATIVO ON TREN
FOR EACH ROW
WHEN (NEW.ESTADO_OPERATIVO <> OLD.ESTADO_OPERATIVO)
BEGIN
    SP_BITACORA('TREN', TO_CHAR(:NEW.ID_TREN), 'UPDATE', 'ESTADO_OPERATIVO',
                :OLD.ESTADO_OPERATIVO, :NEW.ESTADO_OPERATIVO);
END;
/

/* ---------------------------------------------------------------------
   3. Registrar cambios de tarifas y conservar su historial (reglas 17 y 18)
   El monto de una tarifa no se modifica: un cambio de precio se registra
   como una tarifa nueva con su propia vigencia.
   --------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER TRG_TARIFA_NO_CAMBIAR_MONTO
BEFORE UPDATE OF MONTO ON TARIFA
FOR EACH ROW
WHEN (NEW.MONTO <> OLD.MONTO)
BEGIN
    RAISE_APPLICATION_ERROR(-20102, 'No se modifica el monto de la tarifa ' || :OLD.CODIGO_TARIFA
        || ': registre una tarifa nueva con su fecha de inicio de vigencia y cierre la anterior');
END;
/

CREATE OR REPLACE TRIGGER TRG_TARIFA_BITACORA
AFTER INSERT OR UPDATE ON TARIFA
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        SP_BITACORA('TARIFA', TO_CHAR(:NEW.ID_TARIFA), 'INSERT', 'MONTO', NULL,
                    :NEW.CODIGO_TARIFA || ' = ' || TO_CHAR(:NEW.MONTO));
    ELSE
        IF :NEW.ESTADO <> :OLD.ESTADO THEN
            SP_BITACORA('TARIFA', TO_CHAR(:NEW.ID_TARIFA), 'UPDATE', 'ESTADO', :OLD.ESTADO, :NEW.ESTADO);
        END IF;
        IF NVL(:NEW.FECHA_FIN_VIGENCIA, DATE '9999-12-31') <> NVL(:OLD.FECHA_FIN_VIGENCIA, DATE '9999-12-31') THEN
            SP_BITACORA('TARIFA', TO_CHAR(:NEW.ID_TARIFA), 'UPDATE', 'FECHA_FIN_VIGENCIA',
                        TO_CHAR(:OLD.FECHA_FIN_VIGENCIA, 'YYYY-MM-DD'), TO_CHAR(:NEW.FECHA_FIN_VIGENCIA, 'YYYY-MM-DD'));
        END IF;
    END IF;
END;
/

/* ---------------------------------------------------------------------
   4. Actualizar el estado del tren al iniciar un viaje
   Al pasar a EN_ABORDAJE o EN_CURSO el tren queda EN_OPERACION; al pasar a
   EN_CURSO se registra la salida real si no se indico.
   --------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER TRG_VIAJE_INICIA_TREN
BEFORE UPDATE OF ESTADO_VIAJE ON VIAJE_PROGRAMADO
FOR EACH ROW
WHEN (NEW.ESTADO_VIAJE IN ('EN_ABORDAJE', 'EN_CURSO')
      AND OLD.ESTADO_VIAJE IN ('PROGRAMADO', 'RETRASADO', 'EN_ABORDAJE')
      AND NEW.ESTADO_VIAJE <> OLD.ESTADO_VIAJE)
DECLARE
    v_estado TREN.ESTADO_OPERATIVO%TYPE;
BEGIN
    IF :NEW.ID_TREN IS NULL THEN
        RAISE_APPLICATION_ERROR(-20103, 'El viaje ' || :NEW.NUMERO_VIAJE || ' no tiene tren asignado');
    END IF;

    SELECT ESTADO_OPERATIVO INTO v_estado FROM TREN WHERE ID_TREN = :NEW.ID_TREN;
    IF v_estado IN ('EN_MANTENIMIENTO', 'FUERA_DE_SERVICIO', 'RETIRADO') THEN
        RAISE_APPLICATION_ERROR(-20104, 'El tren ' || :NEW.ID_TREN || ' esta ' || v_estado
            || ' y no puede iniciar el viaje (regla 11)');
    END IF;

    IF :NEW.ESTADO_VIAJE = 'EN_CURSO' THEN
        :NEW.SALIDA_REAL := NVL(:NEW.SALIDA_REAL, SYSDATE);
    END IF;

    UPDATE TREN SET ESTADO_OPERATIVO = 'EN_OPERACION'
    WHERE ID_TREN = :NEW.ID_TREN AND ESTADO_OPERATIVO = 'DISPONIBLE';
END;
/

/* ---------------------------------------------------------------------
   5. Liberar el tren cuando el viaje finaliza (o se cancela en curso)
   Al completarse se registra la llegada real y se suma el kilometraje.
   --------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER TRG_VIAJE_LIBERA_TREN
BEFORE UPDATE OF ESTADO_VIAJE ON VIAJE_PROGRAMADO
FOR EACH ROW
WHEN (NEW.ESTADO_VIAJE IN ('COMPLETADO', 'CANCELADO')
      AND OLD.ESTADO_VIAJE IN ('EN_ABORDAJE', 'EN_CURSO'))
DECLARE
    v_km RUTA.DISTANCIA_TOTAL_KM%TYPE;
BEGIN
    v_km := 0;
    IF :NEW.ESTADO_VIAJE = 'COMPLETADO' THEN
        :NEW.SALIDA_REAL  := NVL(:NEW.SALIDA_REAL, SYSDATE);
        :NEW.LLEGADA_REAL := NVL(:NEW.LLEGADA_REAL, SYSDATE);
        SELECT NVL(DISTANCIA_TOTAL_KM, 0) INTO v_km FROM RUTA WHERE ID_RUTA = :NEW.ID_RUTA;
    END IF;

    UPDATE TREN
    SET ESTADO_OPERATIVO      = 'DISPONIBLE',
        KILOMETRAJE_ACUMULADO = KILOMETRAJE_ACUMULADO + v_km
    WHERE ID_TREN = :NEW.ID_TREN AND ESTADO_OPERATIVO = 'EN_OPERACION';
END;
/

/* ---------------------------------------------------------------------
   6. Impedir la asignacion de un tren en mantenimiento (regla 11) y de un
   conductor sin certificacion vigente para el modelo del tren (regla 10)
   --------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER TRG_VIAJE_VALIDA_ASIGNACION
BEFORE INSERT OR UPDATE OF ID_TREN, ID_CONDUCTOR ON VIAJE_PROGRAMADO
FOR EACH ROW
WHEN (NEW.ESTADO_VIAJE <> 'CANCELADO')
DECLARE
    v_estado     TREN.ESTADO_OPERATIVO%TYPE;
    v_modelo     TREN.ID_MODELO%TYPE;
    v_pendientes NUMBER;
BEGIN
    IF :NEW.ID_TREN IS NOT NULL THEN
        SELECT ESTADO_OPERATIVO, ID_MODELO INTO v_estado, v_modelo FROM TREN WHERE ID_TREN = :NEW.ID_TREN;

        IF v_estado IN ('EN_MANTENIMIENTO', 'FUERA_DE_SERVICIO', 'RETIRADO') THEN
            RAISE_APPLICATION_ERROR(-20105, 'El tren ' || :NEW.ID_TREN || ' esta ' || v_estado
                || ' y no puede asignarse a un viaje (regla 11)');
        END IF;

        SELECT COUNT(*) INTO v_pendientes
        FROM ORDEN_MANTENIMIENTO o JOIN EQUIPO e ON e.ID_EQUIPO = o.ID_EQUIPO
        WHERE e.ID_TREN = :NEW.ID_TREN AND o.ESTADO = 'EN_EJECUCION';
        IF v_pendientes > 0 THEN
            RAISE_APPLICATION_ERROR(-20106, 'El tren ' || :NEW.ID_TREN
                || ' tiene un mantenimiento en ejecucion (regla 11)');
        END IF;

        IF :NEW.ID_CONDUCTOR IS NOT NULL
           AND FN_CONDUCTOR_HABILITADO(:NEW.ID_CONDUCTOR, v_modelo, :NEW.SALIDA_PROGRAMADA) = 'N' THEN
            RAISE_APPLICATION_ERROR(-20107, 'El empleado ' || :NEW.ID_CONDUCTOR
                || ' no tiene certificacion vigente para el modelo de este tren o no esta habilitado (regla 10)');
        END IF;
    END IF;
END;
/

/* ---------------------------------------------------------------------
   7. Impedir que un tren o un conductor tengan dos viajes simultaneos
   (reglas 8 y 9). Es un trigger compuesto: guarda los viajes tocados y los
   revisa al final de la sentencia, porque un trigger de fila no puede
   consultar la misma tabla que esta modificando (error de tabla mutante).
   --------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER TRG_VIAJE_SIMULTANEO
FOR INSERT OR UPDATE OF ID_TREN, ID_CONDUCTOR, SALIDA_PROGRAMADA, LLEGADA_PROGRAMADA, ESTADO_VIAJE
ON VIAJE_PROGRAMADO
COMPOUND TRIGGER
    TYPE t_ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    g_ids    t_ids;
    g_cruces NUMBER;

    AFTER EACH ROW IS
    BEGIN
        g_ids(g_ids.COUNT + 1) := :NEW.ID_VIAJE;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
    BEGIN
        FOR i IN 1 .. g_ids.COUNT LOOP
            SELECT COUNT(*) INTO g_cruces
            FROM VIAJE_PROGRAMADO a
            JOIN VIAJE_PROGRAMADO b
              ON b.ID_VIAJE <> a.ID_VIAJE
             AND b.ESTADO_VIAJE <> 'CANCELADO'
             AND b.SALIDA_PROGRAMADA < a.LLEGADA_PROGRAMADA
             AND a.SALIDA_PROGRAMADA < b.LLEGADA_PROGRAMADA
             AND (b.ID_TREN = a.ID_TREN OR b.ID_CONDUCTOR = a.ID_CONDUCTOR)
            WHERE a.ID_VIAJE = g_ids(i)
              AND a.ESTADO_VIAJE <> 'CANCELADO';

            IF g_cruces > 0 THEN
                RAISE_APPLICATION_ERROR(-20108, 'El viaje ' || g_ids(i)
                    || ' se cruza en horario con otro viaje del mismo tren o del mismo conductor (reglas 8 y 9)');
            END IF;
        END LOOP;
    END AFTER STATEMENT;
END TRG_VIAJE_SIMULTANEO;
/

-- Turnos superpuestos del mismo empleado (modulo 4), mismo mecanismo
CREATE OR REPLACE TRIGGER TRG_TURNO_TRASLAPE
FOR INSERT OR UPDATE OF ID_EMPLEADO, HORA_INICIO, HORA_FIN ON TURNO
COMPOUND TRIGGER
    TYPE t_ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    g_ids    t_ids;
    g_cruces NUMBER;

    AFTER EACH ROW IS
    BEGIN
        g_ids(g_ids.COUNT + 1) := :NEW.ID_TURNO;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
    BEGIN
        FOR i IN 1 .. g_ids.COUNT LOOP
            SELECT COUNT(*) INTO g_cruces
            FROM TURNO a
            JOIN TURNO b
              ON b.ID_TURNO <> a.ID_TURNO
             AND b.ID_EMPLEADO = a.ID_EMPLEADO
             AND b.HORA_INICIO < a.HORA_FIN
             AND a.HORA_INICIO < b.HORA_FIN
            WHERE a.ID_TURNO = g_ids(i);

            IF g_cruces > 0 THEN
                RAISE_APPLICATION_ERROR(-20109, 'El turno ' || g_ids(i)
                    || ' se superpone con otro turno del mismo empleado');
            END IF;
        END LOOP;
    END AFTER STATEMENT;
END TRG_TURNO_TRASLAPE;
/

/* ---------------------------------------------------------------------
   8. Alerta de certificacion vencida
   Si una certificacion vigente tiene la fecha de vencimiento pasada, la
   marca como VENCIDA; toda certificacion que pasa a VENCIDA deja una
   ALERTA en la bitacora. SP_REVISAR_CERTIFICACIONES la revisa a diario.
   --------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER TRG_CERTIFICACION_ALERTA
BEFORE INSERT OR UPDATE ON CERTIFICACION
FOR EACH ROW
BEGIN
    IF :NEW.ESTADO = 'VIGENTE' AND :NEW.FECHA_VENCIMIENTO < TRUNC(SYSDATE) THEN
        :NEW.ESTADO := 'VENCIDA';
    END IF;

    IF :NEW.ESTADO = 'VENCIDA' AND (INSERTING OR :OLD.ESTADO <> 'VENCIDA') THEN
        SP_BITACORA('CERTIFICACION', NVL(TO_CHAR(:NEW.ID_CERTIFICACION), 'EMPLEADO ' || :NEW.ID_EMPLEADO), 'ALERTA', 'ESTADO',
                    CASE WHEN UPDATING THEN :OLD.ESTADO END,
                    'VENCIDA - empleado ' || :NEW.ID_EMPLEADO || ' - ' || :NEW.TIPO_CERTIFICACION);
    END IF;
END;
/

/* ---------------------------------------------------------------------
   9. Bitacora de cambios importantes
   --------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER TRG_BIT_TARJETA
AFTER UPDATE OF ESTADO ON TARJETA
FOR EACH ROW
WHEN (NEW.ESTADO <> OLD.ESTADO)
BEGIN
    SP_BITACORA('TARJETA', :NEW.NUMERO_TARJETA, 'UPDATE', 'ESTADO', :OLD.ESTADO, :NEW.ESTADO);
END;
/

CREATE OR REPLACE TRIGGER TRG_BIT_EMPLEADO
AFTER UPDATE OF ESTADO_LABORAL, SALARIO, ID_CARGO ON EMPLEADO
FOR EACH ROW
BEGIN
    IF :NEW.ESTADO_LABORAL <> :OLD.ESTADO_LABORAL THEN
        SP_BITACORA('EMPLEADO', TO_CHAR(:NEW.ID_EMPLEADO), 'UPDATE', 'ESTADO_LABORAL', :OLD.ESTADO_LABORAL, :NEW.ESTADO_LABORAL);
    END IF;
    IF :NEW.SALARIO <> :OLD.SALARIO THEN
        SP_BITACORA('EMPLEADO', TO_CHAR(:NEW.ID_EMPLEADO), 'UPDATE', 'SALARIO', TO_CHAR(:OLD.SALARIO), TO_CHAR(:NEW.SALARIO));
    END IF;
    IF :NEW.ID_CARGO <> :OLD.ID_CARGO THEN
        SP_BITACORA('EMPLEADO', TO_CHAR(:NEW.ID_EMPLEADO), 'UPDATE', 'ID_CARGO', TO_CHAR(:OLD.ID_CARGO), TO_CHAR(:NEW.ID_CARGO));
    END IF;
END;
/

CREATE OR REPLACE TRIGGER TRG_BIT_ESTACION
AFTER UPDATE OF ESTADO_OPERATIVO ON ESTACION
FOR EACH ROW
WHEN (NEW.ESTADO_OPERATIVO <> OLD.ESTADO_OPERATIVO)
BEGIN
    SP_BITACORA('ESTACION', TO_CHAR(:NEW.ID_ESTACION), 'UPDATE', 'ESTADO_OPERATIVO', :OLD.ESTADO_OPERATIVO, :NEW.ESTADO_OPERATIVO);
END;
/

CREATE OR REPLACE TRIGGER TRG_BIT_VIAJE
AFTER UPDATE OF ESTADO_VIAJE ON VIAJE_PROGRAMADO
FOR EACH ROW
WHEN (NEW.ESTADO_VIAJE <> OLD.ESTADO_VIAJE)
BEGIN
    SP_BITACORA('VIAJE_PROGRAMADO', TO_CHAR(:NEW.ID_VIAJE), 'UPDATE', 'ESTADO_VIAJE', :OLD.ESTADO_VIAJE, :NEW.ESTADO_VIAJE);
END;
/

CREATE OR REPLACE TRIGGER TRG_BIT_ORDEN
AFTER UPDATE OF ESTADO ON ORDEN_MANTENIMIENTO
FOR EACH ROW
WHEN (NEW.ESTADO <> OLD.ESTADO)
BEGIN
    SP_BITACORA('ORDEN_MANTENIMIENTO', TO_CHAR(:NEW.ID_ORDEN), 'UPDATE', 'ESTADO', :OLD.ESTADO, :NEW.ESTADO);
END;
/

CREATE OR REPLACE TRIGGER TRG_BIT_INCIDENTE
AFTER INSERT OR UPDATE OF ESTADO ON INCIDENTE
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        SP_BITACORA('INCIDENTE', TO_CHAR(:NEW.ID_INCIDENTE), 'INSERT', 'SEVERIDAD', NULL,
                    :NEW.TIPO_INCIDENTE || ' - ' || :NEW.SEVERIDAD);
    ELSIF :NEW.ESTADO <> :OLD.ESTADO THEN
        SP_BITACORA('INCIDENTE', TO_CHAR(:NEW.ID_INCIDENTE), 'UPDATE', 'ESTADO', :OLD.ESTADO, :NEW.ESTADO);
    END IF;
END;
/

/* ---------------------------------------------------------------------
   10. Los registros historicos no se eliminan fisicamente (regla 25)
   Para "dar de baja" se cambia el estado (CANCELADO, ANULADO, etc.).
   --------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER TRG_NOBORRAR_VIAJE
BEFORE DELETE ON VIAJE_PROGRAMADO
BEGIN
    RAISE_APPLICATION_ERROR(-20110, 'Los viajes no se eliminan: cambie su estado a CANCELADO (regla 25)');
END;
/

CREATE OR REPLACE TRIGGER TRG_NOBORRAR_VIAJE_PASAJERO
BEFORE DELETE ON VIAJE_PASAJERO
BEGIN
    RAISE_APPLICATION_ERROR(-20110, 'Los viajes de pasajeros no se eliminan: cambie su estado a ANULADO (regla 25)');
END;
/

CREATE OR REPLACE TRIGGER TRG_NOBORRAR_RECARGA
BEFORE DELETE ON RECARGA
BEGIN
    RAISE_APPLICATION_ERROR(-20110, 'Las recargas (pagos) no se eliminan (regla 25)');
END;
/

CREATE OR REPLACE TRIGGER TRG_NOBORRAR_COMPOSICION
BEFORE DELETE ON COMPOSICION_TREN
BEGIN
    RAISE_APPLICATION_ERROR(-20110, 'El historial de vagones no se elimina: cierre la asignacion con FECHA_FIN (regla 25)');
END;
/

CREATE OR REPLACE TRIGGER TRG_NOBORRAR_TURNO
BEFORE DELETE ON TURNO
BEGIN
    RAISE_APPLICATION_ERROR(-20110, 'Los turnos (asignaciones) no se eliminan (regla 25)');
END;
/

CREATE OR REPLACE TRIGGER TRG_NOBORRAR_ORDEN
BEFORE DELETE ON ORDEN_MANTENIMIENTO
BEGIN
    RAISE_APPLICATION_ERROR(-20110, 'Las ordenes de mantenimiento no se eliminan: cambie su estado a CANCELADA (regla 25)');
END;
/

CREATE OR REPLACE TRIGGER TRG_NOBORRAR_TARIFA
BEFORE DELETE ON TARIFA
BEGIN
    RAISE_APPLICATION_ERROR(-20110, 'Las tarifas no se eliminan: cambie su estado a INACTIVA (regla 17)');
END;
/

CREATE OR REPLACE TRIGGER TRG_NOBORRAR_BITACORA
BEFORE DELETE OR UPDATE ON BITACORA
BEGIN
    RAISE_APPLICATION_ERROR(-20110, 'La bitacora no se modifica ni se elimina');
END;
/
