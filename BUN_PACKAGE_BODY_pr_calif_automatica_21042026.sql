CREATE OR REPLACE PACKAGE BODY    pr.pr_calif_automatica IS
  /*
  30/03/2020
  SPATTY
  se quito la contaminacion implementada por HALVAREZ, porque aun persiste el problema  y por ende el contagio desarolado por RUSARAVIA

   ULTIMO 26-01-2011
    Autor: HJimenez
--        Fecha: 20/12/2007
        Proc.: Califica_X_Ejecucion4
        Prop.: Usar los interes en suspenso para deteminar calificacion por ejecucion.
    --
    Autor: HJimenez
        Fecha: 24/07/2007
        Proc.: Califica_op_Cliente
                     Califica_x_reprogramacion (nuevo)
        Prop.: Incluir las pol�ticas del banco aprobadas en el Directorio 07/2007 sobre calificaci�n a cr�ditos
                    hipotecarios, de consumo y microcr�dito reprogramados.
                                La calificaci�n por reprogramaci�n no tiene mayor precedencia que la calificaci�n por antiguedad de la mora.
   --
    Autor: HJimenez
     Fecha: 06/06/2006
         Prop.: Invalidar la modificaci�n del 04/05/2006.
         Proc.: Act_Calif_X_cliente
                        De: Henrry Sejas Lazarte
                        Enviado el: Martes, 06 de Junio de 2006 02:58 p.m.
                        Para: Herman Jimenez
                        CC: Eduardo Lunabarrera
                        Asunto: RE: Creacion nuevo ente de calificacion
                        Si el cliente es NO comercial, solo se debe tener la opci�n del ente PROHIB, los dem�s entes no se deben considerar en calificaciones autom�ticas. Es decir cuando un cliente es calificado de acuerdo al criterio de los cr�ditos autom�ticos, la morosidad determina la categor�a de riesgo, salvo que este calificado por ente PROHIB, lo cual significa que cayo en las prohibiciones de la norma y el mismo permanece hasta que se extinga la deuda.
     --
         Autor: HJimenez
     Fecha: 23/05/2006
         Prop.: Incorporar el ente PROHIB para fijar las calificaciones seg�n normativa SB494.
         Proc.: Act_Calif_x_Cliente
     --
         Autor: HJimenez
     Fecha: 04/05/2006
     Prop.: Anular la validaci�n que impide calificar por ente a clientes no comerciales.
     Prop.: Act_Calif_X_Cliente
     --
     Autor: HJimenez
     Fecha: 24/01/2006
         Prop.: Eliminar la calificaci�n m�nima para creditos no comerciales en ejecuci�n.
         Proc.: Califica_X_Mora
         --
         Autor: HJimenez
     Fecha: 26/09/2005
         Prop.: Invocar a la funci�n mapea_calif_actual al obtener la calificaci�n por ente.
         Proc.: Obt_Calif_Entes_Calif
                Obt_Calif_Entes_Calif_His
     --
     Autor: HJImenez
     Fecha: Mayo/2005
         Prop.: Modificar el proceso de calificaci�n y previsi�n seg�n circular SB/494
                Cambios en los c�digos de calificaci�n y previsi�n.
                        Este es un resumen de los cambios:
                        * Se elimina la calificaci�n de microcr�ditos debidamente garantizado.
                        * Cr�ditos comerciales en ejecuci�n se califican de acuerdo al siguiente esquema:
                           - Si las garant�as hipotecarias en primer grado >= 50% del saldo + intereses -> calificaci�n F
                           - Si las garant�as hipotecarias en primer grado < 50% del saldo + intereses -> calificaci�n G
                           - Si no posee garant�as hipotecarias en primer grado -> calificaci�n H
                        * Se elimina calificaci�n por reprogramaciones
                        * Cr�ditos no comerciales deben ser calificados F como m�nimo si est�n en ejecuci�n.
                        --
                        Guardar un valor m�s en pr_tmp_calif_x_cliente, plazo en d�as de la operaci�n.
                        Ser� utilizado en el proceso de previsi�n para evaluar
  */
--------------------------------------------------------------------------------
/* Modif: 22/08/2003
   Autor: HJimenez
   Proposito: Tomar los datos de tablas historicas...
*/
--------------------------------------------------------------------------------
  /*
     Autor: HJimenez.
         Fecha: 30/03/2005.
         Prop.: Retornar calificaciones de clientes y tr�mites de las carteras
                externas de Fideicomiso y CrediCasas.
     Proc.: Obt_Calif_X_Cliente.
     --
         Autor: HJimenez
     Fecha: 03/02/2005.
         Proc.: Obt_Datos_Tramite
         Prop.: Obtener el monto regularizador de los instrumentos parametrizados
         para cr�ditos por venta de bienes a plazo.
  */
  /*
  --Se Incorpora la calificacion x producto, ahora puede parametrizar que productos califican o no
  --JCRS-26-01-2011
  --Proc: CAlificacion
  */
  /*
  --Se incorporan los nuevos tipos de creditos de Pyme, Empresarial, Microcreditos
  --JCRS-04-01-2013
  */
  -- para no modificar el spec...
  vconst_tipcred_micro_garreal CONSTANT PR_TIP_CREDITO_SUPER.cod_tip_cred_s%TYPE := '6';
  vproc_bit                    VARCHAR2(20);
  cempresa_busa                CONSTANT VARCHAR2(1) := '1';
  cpeor_calif                  CONSTANT VARCHAR2(2) := 'H';
  cente_calif_fijo             CONSTANT PR_ENTES_CALIFICACION.abr_ente_calif%TYPE := 'SB494';
  cente_prohibiciones          CONSTANT PR_ENTES_CALIFICACION.abr_ente_calif%TYPE := 'PROHIB';
  cente_Com_Ejecutivo          CONSTANT PR_ENTES_CALIFICACION.abr_ente_calif%TYPE := 'C.EJE.';
  cente_calif_asfi047          CONSTANT PR_ENTES_CALIFICACION.abr_ente_calif%TYPE := 'ASFI47';
  ctipgarnopropia              CONSTANT NUMBER(5) := 187;
  ctipgarotropropi             CONSTANT NUMBER(5) := 227;
  --
PROCEDURE conversion_moneda(pEmpresa    IN VARCHAR2,
                              PMonto      IN NUMBER,         -- Monto a convertir
                              pFecha      IN DATE,           -- Fecha Actual
                              pMonOrigen  IN VARCHAR2,       -- Moneda Origen
                              pMonDestino IN VARCHAR2,       -- Moneda Destino
                              pError      IN OUT VARCHAR2,   -- Mensaje de error
                              pMonConv    IN OUT NUMBER) IS  -- Monto convertido
  BEGIN
    pError := NULL;
    IF pMonOrigen != pMonDestino THEN
       DECLARE
         vtc    NUMBER(12,4);
         vtcUfv NUMBER(12,5);
       BEGIN
         cg_utl.Obtiene_TC_CONTA(1, pFecha, vtc, pError);
         IF pError IS NULL THEN
            IF pMonOrigen = '1' THEN -- Bolivianos...
               IF (vtc >= 1) THEN
                  pMonConv := PMonto / vtc;
               ELSE
                  pMonConv := PMonto * vtc;
               END IF;
            ELSE
               IF pMonDestino = '1' THEN
                  IF (vtc >= 1) THEN
                     pMonConv := PMonto * vtc;
                  ELSE
                     pMonConv := PMonto / vtc;
                  END IF;
               ELSE
                  IF pMonOrigen = '4' THEN --UFV
                     cg_utl.Obtiene_TC_CONTA(4, pFecha, vtcUfv, pError);
                     pMonConv := ((PMonto * vtcUfv) / vtc);
                  ELSE
                     pMonConv := PMonto;
                  END IF;
               END IF;
            END IF;
         END IF;
       END;
    ELSE
       pMonConv := PMonto;
    END IF;
  END conversion_moneda;
  --
  FUNCTION Mapea_Calif_Actual(pCalif IN VARCHAR2) RETURN VARCHAR2 IS
    /* Autor: HJimenez
           Fecha: 13/05/2005
           Prop.: Mapea a los c�digos vigentes a Mayo/2005 de Calificaci�n
                  si pCalif est� entre 1, 2, 3, 3A, 3B, 4, 5
    */
        vcod_calif VARCHAR2(5) := pCalif;
  BEGIN
        IF pCalif IN ('1', '2', '3', '3A', '3B', '4', '5') THEN
           IF pCalif = '1' THEN
              vcod_calif := 'A';
           ELSIF pCalif = '2' THEN
              vcod_calif := 'B';
           ELSIF pCalif = '3' THEN
              vcod_calif := 'D';
       ELSIF pCalif = '3A' THEN
              vcod_calif := 'C';
           ELSIF pCalif = '3B' THEN
              vcod_calif := 'F';
           ELSIF pCalif = '4' THEN
              vcod_calif := 'F';
           ELSE -- '5'
              vcod_calif := 'H';
           END IF;
        END IF;
        RETURN vcod_calif;
  END Mapea_Calif_Actual;
  --
  PROCEDURE Realiza_Commit IS
  BEGIN
    vconst_Cont_Commit := 0;
--    COMMIT;
  END Realiza_Commit;
  --
  --
  PROCEDURE Contador_Commit IS
  BEGIN
    vconst_Cont_Commit := NVL(vconst_Cont_Commit,0) + 1;
    IF vconst_Cont_Commit = 1000 THEN
       Realiza_Commit;
    END IF;
  END Contador_Commit;
  --
  --
  FUNCTION Nuevo_Proceso (p_cod_empresa IN VARCHAR2,
                          p_fecha       IN DATE,
                          p_califica    IN VARCHAR2,
                          p_cod_error   IN OUT VARCHAR2 ) RETURN NUMBER IS
    v_nuevo NUMBER;
    -- OBJETIVO   : Crear nuevo proceso de calificacion
    -- REALIZA    : Toma la siguiente secuencia de procesos de prevision
    --              Crea un registro en PR_PREVISION con ella
    -- HISTORIA   : ggs , 3/1999
  BEGIN
    SELECT pr.pr_s_provisiones.NEXTVAL
      INTO v_nuevo
        FROM dual;
    --
    INSERT INTO PR_PROVISIONES (cod_empresa,num_proceso,fec_ult_calificacion,
                                provisionado,ind_califica,adicionado_por,fec_adicion)
      VALUES (p_cod_empresa,v_nuevo,p_fecha,'N',p_califica,
              USER,SYSDATE);
    /* Modificacion: HJimenez
              Fecha: 30/04/2001
          Prop�sito: El nuevo proceso nace con el indicador de provisionado en S, eso es para que el proceso de generaci�n
                         del archivo ASCII, pueda tomar los datos correspondientes al proceso actual de calificaci�n.
    */
    RETURN v_nuevo;
    --
     EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
             p_cod_error := '002138';
             RETURN NULL;
        WHEN OTHERS THEN
             mnj_errores.fijar_error('002139', 'PR', SQLERRM, 'NUEVO_PROCESO',
                                     NULL, 'OTHERS');
             p_cod_error := '002139';
             RETURN NULL;
  END;
  --
  PROCEDURE Ins_Tmp_Calif_X_Cliente (pv_empresa       IN VARCHAR2,
                                     pv_fecha         IN DATE,
                                     pv_tramite       IN NUMBER,
                                     pv_tip_cred_s    IN NUMBER,
                                     pv_moneda        IN VARCHAR2,
                                     pv_estado        IN VARCHAR2,
                                     pv_mon_operacion IN NUMBER,
                                     pv_saldo         IN NUMBER,
                                     pv_saldo_diferido IN number,  --- SSPM 30/05/2020
                                     pv_saldo_cont    IN NUMBER,
                                     pv_saldo_venc    IN NUMBER,
                                     pv_int_dev       IN NUMBER,
                                     pv_dias_mora     IN NUMBER,
                                     pv_num_operacion IN VARCHAR2,
                                                                         pPlazo_dias      IN NUMBER,
                                     p_cod_error      IN OUT VARCHAR2) IS
    CURSOR cur_clientes IS
      SELECT num_tramite, cod_persona, ind_titular
        FROM PERSONAS_X_PR_TRAMITE
          WHERE cod_empresa = pv_empresa
            AND num_tramite = pv_tramite
            AND estado      = 'V';
    --
    vtip_cred_s PR_TIP_CREDITO_SUPER.cod_tip_cred_s%TYPE;
  BEGIN
    FOR cli IN cur_clientes LOOP
        -- buscar el tipo de cr�dito seg�n la super...
            vtip_cred_s := NVL(Pr_Utl2.obt_tipo_sbef(pv_empresa, pv_tramite), pv_tip_cred_s);
        -- Insertar en la temporal...
        INSERT INTO PR_TMP_CALIF_X_CLIENTE
           (cod_empresa, num_tramite, cod_persona, cod_tip_cred_s, cod_moneda,
            saldo_tra, saldo_cont, saldo_venc, int_deveng, num_dias_mora, cod_calif, motivo,
            codigo_estado, ind_crediagil, mon_operacion, deuda_total, num_operacion, ind_titular,
                        plazo_dias, mon_diferido) --- SSPM 30/05/2020
          VALUES
           (pv_empresa, cli.num_tramite, cli.cod_persona, vtip_cred_s, pv_moneda,
                    NVL(pv_saldo,0)  , NVL(pv_saldo_cont,0)  , NVL(pv_saldo_venc,0)  , NVL(pv_int_dev,0)   , NVL(pv_dias_mora,0), NULL, NULL,
            pv_estado, 'N', pv_mon_operacion, NULL, pv_num_operacion, NVL(cli.ind_titular, 'N'),
                        pPlazo_dias, pv_saldo_diferido); -- SSPM 30/05/2020 adicionando monto diferido
    END LOOP;
    --
    EXCEPTION
       WHEN OTHERS THEN
            mnj_errores.fijar_error('002140', 'PR', SQLERRM, 'INS_TMP_CALIF_X_CLIENTE',
                                     NULL, 'OTHERS');
            p_cod_error := '002140';
  END Ins_Tmp_Calif_X_Cliente;
  --
FUNCTION Obt_Calificacion_Adicional (p_cod_empresa IN VARCHAR2,
                                     p_tramite IN NUMBER,
                                                         p_cod_error IN OUT VARCHAR2)RETURN VARCHAR2 IS
-- OBJETIVO  : Obtener calificaci�n para calcular prevision adicional
-- REALIZA   : Obtiene la calificaci�n de acuerdo a parametro del credito para su prevision adicional.
-- HISTORIA  : jcrs , 6/2008
   v_cod_calif PR_CALIFICACION.cod_calif%TYPE;
BEGIN
   p_cod_error := NULL;
   SELECT cod_calif
   INTO   v_cod_calif
   FROM   PR_TRAMITE_PRE_ADICIONAL
   WHERE  cod_empresa    = p_cod_empresa
   AND    num_tramite    = p_tramite
   AND    estado         = 'V';
   RETURN v_cod_calif;
   EXCEPTION
     WHEN NO_DATA_FOUND THEN
              v_cod_calif := NULL;
          RETURN NULL;
     WHEN OTHERS THEN
          mnj_errores.fijar_error('002135', 'PR', SQLERRM, 'OBT_CALIFICACION_ADICIONAL',
                            NULL, 'Others');
          p_cod_error := '002135';
          RETURN NULL;
END;
  --
  PROCEDURE Obt_Datos_Tramite(pv_empresa        IN VARCHAR2,
                              pv_fecha          IN DATE,
                              pv_tramite        IN NUMBER,
                              pv_cod_tip_op     IN NUMBER,
                              pv_tip_prod       IN NUMBER,
                              pv_codigo_origen  IN NUMBER,
                              pv_cod_estado_tra IN VARCHAR2,
                              ps_num_Operacion OUT VARCHAR2,
                              ps_mon_operacion OUT NUMBER,
                              ps_saldo         OUT NUMBER,
                              ps_saldo_cont    OUT NUMBER,
                              ps_saldo_venc    OUT NUMBER,
                              ps_int_dev       OUT NUMBER,
                              ps_dias_mora     OUT NUMBER,
                                                          ps_plazo_dias    OUT NUMBER,
                                                          ps_error      IN OUT VARCHAR2) IS
/*  Autor: Hjimenez
    MOdificaci�n: 28/06/2001
        Prop�sito   : Restar del saldo total de la operaci�n la fracci�n que corresponde a vencido.
                  y as� en ps_saldo va el saldo vigente y en saldo vencido la fracci�n vencida o atrasada.
    Modificaci�n: 02/07/2002
                      Se cambia la forma de obtener cuando una operaci�n maneja dos saldos
                                  Parece que el select anterior estaba trucho pues no cubre la totalidad
                                  de operaciones que pueden manejar dos saldos.
                                  Se sustituye por una funci�n que la usa rtabora en su consoiidado
    Modificacion: 22/08/2003
                  Utilizar la interfaz historica
    --
    Modificaci�n: 03/02/2005.
        Proposito: Buscar monto regularizador en los instrumentos que est�n parametrizados
                   como venta de bienes a plazo.
*/
    V_CodigoOrigen PR_TRAMITE.Codigo_Origen%TYPE;
    --
    V_NoOperacion     VARCHAR2(20);
    V_TasaInteres     NUMBER(10,4);
    V_PlazoDias       NUMBER(5);
    V_FechaInicio     DATE;
    V_FechaVenc       DATE;
    V_FechaCanc       DATE;
    V_DiasAtraso      NUMBER(5);
    V_MontoOperacion  NUMBER(16,2);
    V_SaldoCont       NUMBER(16,2);
    V_SaldoOpe        NUMBER(16,2);
    V_InteresesOpe    NUMBER(16,2);
    V_ComisionOpe     NUMBER(16,2);
    V_CargosOpe       NUMBER(16,2);
    V_MoratoriosOpe   NUMBER(16,2);
    V_PunitoriosOpe   NUMBER(16,2);
    V_PolizaOpe       NUMBER(16,2);
    V_MensajeError    VARCHAR2(6);
    V_IndRefinanciado VARCHAR2(1) := 'N';
    V_TasaMora        NUMBER(10,4);
    V_SaldoVenc       NUMBER(16,2);
    V_Moratorios      NUMBER(16,2);
    V_DiasMora        NUMBER(5);
    V_CodTipOperacion NUMBER(5);
    V_CodigoEstado    VARCHAR2(2);
    --
    vdeuda_total      NUMBER(18,2) := 0;
    vdeuda            NUMBER(18,2);
    V_DiasAtraso_aux    NUMBER(5);
    --


    vint_doctos_desc   NUMBER(18,2);
    vmto_regularizador NUMBER(18,2);
  BEGIN
    ps_error := NULL;
    V_SaldoVenc := 0;
    -- busca los datos del tr�mite...
    -- Traer Saldo y D�as de Atraso; de cada m�dulo
    -- Saldo no utilizado ; s�lo para sobregiros y tarjetas
--    Pr_Abon3_Bd.Datos_Generales_Tramite(pv_empresa      , pv_tramite,
    Pr_Historico.Datos_Generales_Tramite_His(pv_empresa      , pv_tramite,
                                             pv_fecha        ,
                                             pv_fecha        , V_NoOperacion,
                                             V_TasaInteres   , V_PlazoDias,
                                             V_FechaInicio   , V_FechaVenc,
                                             V_FechaCanc     , V_DiasAtraso,
                                             V_MontoOperacion, V_SaldoCont,
                                             V_SaldoOpe      , V_InteresesOpe,
                                             V_ComisionOpe   , V_CargosOpe,
                                             V_MoratoriosOpe , V_PunitoriosOpe,
                                             V_PolizaOpe     , ps_Error);

    --<<--vespejo-22-16 - adecuacion cuotas  18/01/2022
    IF pv_cod_tip_op = vconst_CODOPERTC THEN
        DECLARE
            vcuotas number(22,2):=0;
        BEGIN
                vcuotas:=0;
                BEGIN
                    vcuotas:=0;
                    SELECT nvl(h.cuotas,0)
                    INTO   vcuotas
                    FROM   tc.tc_opera_mensual_hi h , pr_sol_adic_trj_cr trj, pr_his_tramite tra
                    WHERE  h.cod_empresa       = pv_empresa
                    AND    h.fec_corte         = pv_fecha
                    AND    h.cuenta_tarjeta    = trj.cuenta_tarjeta
                    AND    trj.cod_empresa     = h.cod_empresa
                    AND    trj.num_solicitud   = pv_tramite
                    AND    tra.cod_empresa     = h.cod_empresa
                    AND    tra.num_tramite     = trj.num_solicitud
                    AND    tra.fec_registro_hi = h.fec_corte
                    AND    tra.cod_tip_operacion = vconst_CODOPERTC;--pv_cod_tip_op;--vconst_CODOPERTC;
                EXCEPTION
                    WHEN no_data_found THEN
                        NULL;
                END;
                IF vcuotas >0 THEN
                     V_SaldoOpe   := V_SaldoOpe+vcuotas;
                     V_SaldoCont  := V_SaldoCont-vcuotas;
                     IF V_SaldoCont < 0 THEN
                        V_SaldoCont :=0;
                     END IF;
                END IF;--if vcuotas >0 then
        EXCEPTION
            WHEN others THEN
                NULL;
        END;
    END IF;--if pv_cod_tip_op = vconst_CODOPERTC then
    -->>--vespejo-22-16 - adecuacion cuotas 18/01/2022

    IF NOT(Ps_Error IS NULL) THEN
       mnj_errores.fijar_error('000032', 'PR', SQLERRM, 'OBT_DATOS_TRAMITE',
                               PS_Error, 'Datos_Generales_Tramite');
       ps_error := 'Error en Tr�mite :'||TO_CHAR(pv_tramite);
       DBMS_OUTPUT.PUT_LINE('Error en Tr�mite :'||TO_CHAR(pv_tramite));
    ELSE
       IF pv_cod_tip_op     = vconst_CodOperPr AND
          pv_cod_estado_Tra = Pr_Utl_Estados.Verif_Estado_Vencido(pv_cod_estado_Tra) THEN
                  --
                  -- Modificado por Moises Alvarez
                  -- Fecha 30/03/2005
          V_IndRefinanciado := Pr_Sbef2_Bd.dos_Saldos( pv_empresa,
                                                              pv_cod_tip_op,
                                                      pv_tip_prod,
                                                      pv_codigo_origen,
                                                      pv_fecha,
                                                      'PR0434',
                                                      100,
                                                      ps_Error);
          IF NOT(Ps_Error IS NULL) THEN
             mnj_errores.fijar_error('000032', 'PR', NULL, 'Pr_Sbef2_Bd.dos_Saldos', ps_error, 'Datos_Generales_Tramite');
             ps_error := 'Error en dos saldos: ' || TO_CHAR(pv_tramite);
                         RETURN;
          END IF;
          --
          IF NVL(V_IndRefinanciado, 'N') = 'S' THEN
--             Pr_Procs_Bd.Saldo_Atrasado (pv_Empresa,
               Saldo_Atrasado_His(pv_Empresa,
                                         'ESPA',
                                         V_NoOperacion,
                                         pv_Fecha,
                                         V_TasaMora,
                                         V_SaldoVenc,
                                         V_Moratorios,
                                         V_DiasAtraso_aux,
                                         V_DiasMora,
                                         Ps_Error);
             IF NOT(Ps_Error =  '000030') AND
                NOT(Ps_Error IS NULL) THEN
                RETURN;
             ELSE
                Ps_Error := NULL;
             END IF;
          END IF; -- if V_IndRefinanciado = 'S'
       END IF; -- if P_Cod_Tip_Op = :Variables.CodOperPr and P_Cod_Estado_Tra = Pr_Utl_Estados.Verif_Estado_Vencido(V_Codigo_Estado)
       --
       ps_mon_operacion := V_MontoOperacion;
       --
       ps_saldo         := V_SaldoOpe; -- si la operaci�n maneja dos saldos, el saldo en atraso o vencido
                                           -- ya viene sumado...
           -- controlar que por error de datos el contingente no venga negativo...o que venga contingente si el tipo de operacion es PRESTAMOS
           --
           IF NVL(v_saldoCont,0) <= 0 THEN
              ps_saldo_cont    := 0;
           ELSE
              IF pv_cod_tip_op = vconst_CodOperPr THEN  -- no puede existir contingencia para tipo operaci�n PRESTAMOS...
                         ps_saldo_cont := 0;
          ELSE
             ps_saldo_cont := v_SaldoCont;
          END IF;
           END IF;
           -- controlar que por error de datos el vencido no venga negativo...
           IF NVL(V_SaldoVenc,0) <= 0 THEN
              ps_saldo_venc := 0;
       ELSE
          ps_saldo_venc := V_SaldoVenc; -- porci�n del saldo total que corresponde a atraso o vencido seg�n el estado de la operaci�n...
           END IF;
           --
       ps_num_Operacion := V_NoOperacion;
       ps_int_dev       := V_InteresesOpe;
       ps_dias_mora     := v_DiasAtraso;
           ps_plazo_dias    := V_PlazoDias;
       --
       -- Intereses por documentos descontados
       -- Se busca el monto de intereses y se restan al saldo del cr�dito.
       BEGIN
          SELECT NVL(c.monto_pagado_intereses, 0)
            INTO vint_doctos_desc
            FROM PR_HIS_TRAMITE b, PR_CREDITOS_HI c
           WHERE b.num_tramite     = pv_tramite
             AND b.fec_registro_hi = pv_fecha
             AND b.cod_empresa     = pv_empresa
             AND b.codigo_estado   = Pr_Utl_Estados.verif_estado_activo(b.codigo_estado)
             AND c.num_tramite     = b.num_tramite
             AND c.codigo_empresa  = b.cod_empresa
             AND c.fec_registro_hi = pv_fecha
             AND b.cod_tip_credito IN ( SELECT cod_tip_credito
                                                      FROM PR_TIP_CREDITO
                                                                                 WHERE es_docto_descont = 'S'
                                                                                   AND cod_empresa      = pv_empresa);
         --  se resta los intereses al saldo de la operacion
--         ps_saldo := V_SaldoOpe - vint_doctos_desc;
         ps_saldo := ps_saldo - vint_doctos_desc;
DBMS_OUTPUT.PUT_LINE('vint_doctos_desc: ' || vint_doctos_desc);
DBMS_OUTPUT.PUT_LINE('saldo2: ' || ps_saldo);
         --
         EXCEPTION
            WHEN NO_DATA_FOUND THEN
                 NULL;
            WHEN OTHERS THEN
                 mnj_errores.fijar_error('000031', 'PR', SQLERRM, 'OBT_DATOS_TRAMITE', 'Interes doctos descontados', NULL);
                 ps_error := 'Buscando intereses descontados: '|| SQLERRM;
       END;
       --
       -- venta de bienes
       -- buscar el monto regularizados por la ganancia por venta de bienes
       -- este monto se resta al saldo conocido de la operaci�n
       BEGIN
         SELECT NVL(c.saldo_promedio, 0)
           INTO vmto_regularizador
           FROM PR_HIS_TRAMITE b, PR_CREDITOS_HI c, PR_TIP_CREDITO A
             WHERE b.num_tramite     = pv_tramite
               AND b.fec_registro_hi = pv_fecha
               AND b.cod_empresa     = pv_empresa
               --AND b.cod_tip_credito = 7
               AND c.num_tramite     = b.num_tramite
               AND c.fec_registro_hi = pv_fecha
               AND c.codigo_empresa  = b.cod_empresa
                           --
                           AND A.cod_empresa     = pv_empresa
                           AND A.cod_tip_credito = b.cod_tip_credito
                           AND A.vta_bienes      = 'S';
         --  se resta los intereses al saldo de la operacion
--         ps_saldo := V_SaldoOpe - vmto_regularizador;
         IF (ps_saldo - vmto_regularizador) < 0 THEN
            ps_saldo := 0;
         ELSE
            ps_saldo := ps_saldo - vmto_regularizador;
         END IF;
         --
         EXCEPTION
            WHEN NO_DATA_FOUND THEN
                 NULL;
            WHEN OTHERS THEN
                 mnj_errores.fijar_error('000031', 'PR', SQLERRM, 'OBT_DATOS_TRAMITE', 'Mto Regularizador Venta Bienes', NULL);
                 ps_error := 'Buscando monto regularizador: '|| SQLERRM;
       END;
    END IF;
    --
  END Obt_Datos_Tramite;
  --
  --
  PROCEDURE Act_Calificacion_Tmp(pv_empresa      IN VARCHAR2,
                                 pv_tramite      IN NUMBER,
                                 pv_cliente      IN VARCHAR2,
                                 pv_calif        IN VARCHAR2,
                                 pv_motivo       IN VARCHAR2,
                                 pv_reprog       IN NUMBER,
                                                                 pv_deu_total    IN NUMBER,
                                                                 pv_tip_cred_cal IN NUMBER,
                                 pv_error        IN OUT VARCHAR2,
                                 pRowid          IN VARCHAR2) IS
  BEGIN
    IF pRowid IS NULL THEN
       UPDATE PR_TMP_CALIF_X_CLIENTE
          SET cod_calif      = pv_calif,
              motivo         = pv_motivo,
              no_reprog      = pv_reprog,
              deuda_total    = pv_deu_total,  -- expresado en la moneda de consolidaci�n ($us).
              tip_cred_calif = pv_tip_cred_cal
            WHERE cod_empresa = pv_empresa
              AND num_tramite = pv_tramite
              AND cod_persona = NVL(pv_cliente, cod_persona)
              AND cod_calif   IS NULL;  -- no solapar la calificacion dada por un ente externo...
    ELSE
       UPDATE PR_TMP_CALIF_X_CLIENTE
          SET cod_calif      = pv_calif,
              motivo         = pv_motivo,
              no_reprog      = pv_reprog,
              deuda_total    = pv_deu_total,  -- expresado en la moneda de consolidaci�n ($us).
              tip_cred_calif = pv_tip_cred_cal
            WHERE ROWID = pRowid;  -- no solapar la calificacion dada por un ente externo...
    END IF;
    --
    IF SQL%ROWCOUNT = 0 THEN
       mnj_errores.fijar_error('002145', 'PR', 'NO ACTUALIZO TEMPORAL(: ' || pRowid || ')', 'ACT_CALIFICACION_TMP',
                               NULL, NULL);
       pv_error := '002145';
    END IF;
    --
    EXCEPTION
      WHEN OTHERS THEN
           mnj_errores.fijar_error('002145', 'PR', SQLERRM, 'ACT_CALIFICACION_TMP',
                                   NULL, 'OTHERS');
           pv_error := '002145';
  END Act_Calificacion_Tmp;
  --
  --
  PROCEDURE Obt_Calif_Entes_Calif(pv_empresa   IN VARCHAR2,
                                  pv_persona   IN VARCHAR2,
                                  ps_calif     IN OUT VARCHAR2,
                                                                  ps_fec_calif IN OUT DATE,
                                  ps_ente      IN OUT VARCHAR2) IS
    /* Autor: HJimenez
       Fecha: 23/04/2001
       Prop�sito: retorna la calificaci�n de otros entes para el cliente.
                  Seg�n el siguiente criterio:
                  Se retorna la calificaci�n con la fecha superior.
                  Si existen varias calificaciones para una misma fecha, se retorna
                  la calificaci�n del ente seg�n la prioridad de la tabla pr_entes_calificacion
                  es decir el menor es la mayor.
       Modificaci�n: 23/04/2002
                     Se modifica la prelaci�n de la calificaci�n por ente seg�n los siguientes
                                         criterios dados por LRevollar de Evaluaci�n y Calificaci�n de Cartera.
                                         * Entre los Entes SBEF, PWC, AI y CRC, se debe asignar la calificaci�n mayor.
                     * Si la calificaci�n Fere es la �ltima registrada entonces esa es la que
                                           debe tener la prelaci�n.
                     * Si tiene calificaci�n Fere y tiene una calificaci�n mayor de cualquier
                                           otro ente en una fecha posterior, debe ser calificado con la del otro ente.
                     * Si tiene calificaci�n mayor por d�as mora, esa es la que debe
                                           predominar.
                                         ----
                                         Basado en lo anterior se hace lo siguiente:
                                         1. Primero se busca quien tiene la prelaci�n entre los entes
                                            SBEF, PWC, AI y CRC buscando la fecha de �ltima calificaci�n.
                                                Se supone que un ente de menor jerarqu�a no va a mejorar la calificaci�n
                                                de uno con mayor jerarqu�a, por ej. SBEF 3, PWC 4 (NO).
                                         2. Se busca si el cliente tiene calificaci�n por FERE y se compara
                                            la fecha y cual es mayor con la calificaci�n de los anteriores entes.
    */
    CURSOR cur_calif (p_ente_fere IN VARCHAR2) IS
      SELECT A.fec_calif, A.cod_calif, b.abr_ente_calif
        FROM PR_CALIF_X_ENTE A, PR_ENTES_CALIFICACION b
              WHERE A.cod_empresa     = pv_empresa
                AND A.cod_persona     = pv_persona
                        AND A.cod_ente_calif != p_ente_fere
            AND b.cod_empresa     = A.cod_empresa
                    AND b.cod_ente_calif  = A.cod_ente_calif
    ORDER BY A.fec_calif DESC, A.cod_ente_calif;
    -- se ordena las calificaciones de la �ltima hacia abajo, y por prioridad del ente...
    --
        CURSOR cur_fere (p_ente_fere IN VARCHAR2) IS -- busca calificaci�n de fere
          SELECT A.fec_calif, A.cod_calif, b.abr_ente_calif
        FROM PR_CALIF_X_ENTE A, PR_ENTES_CALIFICACION b
              WHERE A.cod_empresa     = pv_empresa
                AND A.cod_persona     = pv_persona
                        AND A.cod_ente_calif  = p_ente_fere
                    AND b.cod_empresa     = A.cod_empresa
                    AND b.cod_ente_calif  = A.cod_ente_calif
      ORDER BY A.fec_calif DESC;
    --
        vente_fere PR_ENTES_CALIFICACION.cod_ente_calif%TYPE;
        rcal       cur_calif%ROWTYPE;
        rfere      cur_fere%ROWTYPE;
        vhay_calif BOOLEAN;
        vhay_fere  BOOLEAN;
        verror     VARCHAR(200);
  BEGIN
    Pr_Utl.Parametro_x_Empresa(pv_empresa, 'COD_ENTECALIF_FERE', 'PR', vente_fere, verror);
    -- un solo fetch hace que se traiga la �ltima calificaci�n del ente que tenga mayor prioridad;
    OPEN cur_calif(vente_fere);
    FETCH cur_calif INTO rcal;
        vhay_calif := cur_calif%FOUND;
    CLOSE cur_calif;
        --
        OPEN cur_fere(vente_fere);
        FETCH cur_fere INTO rfere;
        vhay_fere := cur_fere%FOUND;
        CLOSE cur_fere;
        --
        IF NOT(vhay_calif) AND NOT(vhay_fere) THEN
       ps_fec_calif := NULL;
       ps_calif     := NULL;
       ps_ente      := NULL;
        ELSIF NOT(vhay_calif) AND vhay_fere THEN
       ps_fec_calif := rfere.fec_calif;
       ps_calif     := rfere.cod_calif;
       ps_ente      := rfere.abr_ente_calif;
        ELSIF vhay_calif AND NOT(vhay_fere) THEN
       ps_fec_calif := rcal.fec_calif;
       ps_calif     := rcal.cod_calif;
       ps_ente      := rcal.abr_ente_calif;
        ELSE
           IF rfere.fec_calif > rcal.fec_calif THEN -- fere manda...
          ps_fec_calif := rfere.fec_calif;
              ps_calif     := rfere.cod_calif;
                  ps_ente      := rfere.abr_ente_calif;
       ELSE
          ps_fec_calif := rcal.fec_calif;
              ps_calif     := rcal.cod_calif;
                  ps_ente      := rcal.abr_ente_calif;
           END IF;
        END IF;
        --
        ps_calif := Mapea_Calif_Actual(ps_calif);
  END Obt_Calif_Entes_Calif;
  --
  PROCEDURE Obt_Calif_Entes_Calif_His(pv_empresa   IN VARCHAR2,
                                      pv_persona   IN VARCHAR2,
                                      pv_fecha     IN DATE,
                                      ps_calif     IN OUT VARCHAR2,
                                                                  ps_fec_calif IN OUT DATE,
                                      ps_ente      IN OUT VARCHAR2) IS
    /* Autor: HJimenez
       Fecha: 22/08/2003
       Prop�sito: Adaptar Obt_Calif_Entes_Calif a funcionamiento hist�rico...
    */
    CURSOR cur_calif (p_ente_fere IN VARCHAR2) IS
      SELECT A.fec_calif, A.cod_calif, b.abr_ente_calif
        FROM PR_CALIF_X_ENTE A, PR_ENTES_CALIFICACION b
              WHERE A.cod_empresa     = pv_empresa
                AND A.cod_persona     = pv_persona
            AND A.fec_calif      <= pv_fecha
                        AND A.cod_ente_calif != p_ente_fere
            AND b.cod_empresa     = A.cod_empresa
                    AND b.cod_ente_calif  = A.cod_ente_calif
    ORDER BY A.fec_calif DESC, A.cod_ente_calif;
    -- se ordena las calificaciones de la �ltima hacia abajo, y por prioridad del ente...
    --
        CURSOR cur_fere (p_ente_fere IN VARCHAR2) IS -- busca calificaci�n de fere
          SELECT A.fec_calif, A.cod_calif, b.abr_ente_calif
        FROM PR_CALIF_X_ENTE A, PR_ENTES_CALIFICACION b
              WHERE A.cod_empresa     = pv_empresa
                AND A.cod_persona     = pv_persona
                        AND A.cod_ente_calif  = p_ente_fere
            AND A.fec_calif      <= pv_fecha
                    AND b.cod_empresa     = A.cod_empresa
                    AND b.cod_ente_calif  = A.cod_ente_calif
      ORDER BY A.fec_calif DESC;
    --
        vente_fere PR_ENTES_CALIFICACION.cod_ente_calif%TYPE;
        rcal       cur_calif%ROWTYPE;
        rfere      cur_fere%ROWTYPE;
        vhay_calif BOOLEAN;
        vhay_fere  BOOLEAN;
        verror     VARCHAR(200);
  BEGIN
    Pr_Utl.Parametro_x_Empresa(pv_empresa, 'COD_ENTECALIF_FERE', 'PR', vente_fere, verror);
    -- un solo fetch hace que se traiga la �ltima calificaci�n del ente que tenga mayor prioridad;
    OPEN cur_calif(vente_fere);
    FETCH cur_calif INTO rcal;
        vhay_calif := cur_calif%FOUND;
    CLOSE cur_calif;
        --
        OPEN cur_fere(vente_fere);
        FETCH cur_fere INTO rfere;
        vhay_fere := cur_fere%FOUND;
        CLOSE cur_fere;
        --
        IF NOT(vhay_calif) AND NOT(vhay_fere) THEN
       ps_fec_calif := NULL;
       ps_calif     := NULL;
       ps_ente      := NULL;
        ELSIF NOT(vhay_calif) AND vhay_fere THEN
       ps_fec_calif := rfere.fec_calif;
       ps_calif     := rfere.cod_calif;
       ps_ente      := rfere.abr_ente_calif;
        ELSIF vhay_calif AND NOT(vhay_fere) THEN
       ps_fec_calif := rcal.fec_calif;
       ps_calif     := rcal.cod_calif;
       ps_ente      := rcal.abr_ente_calif;
        ELSE
           IF rfere.fec_calif > rcal.fec_calif THEN -- fere manda...
          ps_fec_calif := rfere.fec_calif;
              ps_calif     := rfere.cod_calif;
                  ps_ente      := rfere.abr_ente_calif;
       ELSE
          ps_fec_calif := rcal.fec_calif;
              ps_calif     := rcal.cod_calif;
                  ps_ente      := rcal.abr_ente_calif;
           END IF;
        END IF;
        ps_calif := Mapea_Calif_Actual(ps_calif);
  END Obt_Calif_Entes_Calif_His;
  --
  PROCEDURE Obt_Deuda_Total_Cliente (pv_empresa       IN VARCHAR2,
                                     pv_cliente       IN VARCHAR2,
                                     pv_fecha         IN DATE,
                                     pv_mon_consolida IN VARCHAR2,
                                     ps_deuda         IN OUT NUMBER,
                                     pv_error         IN OUT VARCHAR2) IS
    /* Autor: HJimenez
       Fecha: 19/04/2001
       Prop�sito: Obtener la deuda total del cliente, sumando el saldo de todas sus operaciones y consolidando
                  a una sola moneda.
                  Se supone que todas las operaciones v�lidas del cliente se insertaron en el temporal...
                  La deuda total del cliente se define como:
                  DT = DD + ID + DI
                  Donde:
                    DT: Deuda Total
                    DD: Deuda Directa
                    ID: Intereses Devengados
                    DI: Deuda Indirecta  (deuda donde el cliente aparece como garante).
                    El algoritmo de este procedimiento primero obtiene la suma de la deuda y de los intereses
                    devengados de todas las operaciones de un cliente y luego suma la deuda indirecta del mismo.
       Modificaci�n:  Se elimina la deuda indirecta de esta f�rmula, a solicitud de Riesgo Crediticio
                      HJimenez: 30/04/2001
       Modificaci�n:  Se suma a la deuda total del cliente, el saldo contingente de las operaciones que lo tengan.
                      Seg�n la normativa vigente, circular SB/333/00 y Riesgo Crediticio (Luis Revollar).
           Modificaci�n: 28/06/2001
                         Al saldo de la operaci�n, se le suma el saldo vencido.
       Modificaci�n: 29/08/2001
                         Por mandato de la SBEF la deuda total del cliente se basa sobre el monto original de
                                         la operaci�n
    */
/*
    -- obtener por moneda el saldo y los intereses devengadosde de las operaciones del cliente
    CURSOR cur_saldos IS
      SELECT cod_moneda,
                 SUM(NVL(saldo_tra, 0) + NVL(saldo_cont, 0)) saldo,
                         SUM(NVL(int_deveng, 0)) int_deveng
            FROM pr_tmp_calif_x_cliente
              WHERE cod_empresa = pv_empresa
                    AND cod_persona = pv_cliente
    GROUP BY cod_moneda;
*/
    -- obtener los montos originales por cada operaci�n del cliente...
    -- Se cambio el tipo de evaluaciones para clientes comerciales, ahora se evalua por saldo total del credito
    --20-10-2009 -JCRS
    CURSOR cur_saldos IS
      SELECT cod_moneda, --SUM(NVL(mon_operacion,0)) mon_operacion
             --SUM(NVL(saldo_tra, 0)  + NVL(saldo_cont, 0)) mon_operacion -- ANTES
             SUM(NVL(saldo_tra, 0) + nvl(mon_diferido,0) + NVL(saldo_cont, 0)) mon_operacion --- SSPM 30/04/2020
            FROM PR_TMP_CALIF_X_CLIENTE
              WHERE cod_empresa = pv_empresa
                    AND cod_persona = pv_cliente
    GROUP BY cod_moneda;
    --
    vdeuda_total    NUMBER(18,2) := 0;
    vmto_convertido NUMBER(18,2);
  BEGIN
    ps_deuda := 0;
    pv_error := NULL;
    FOR sal IN cur_saldos LOOP
        -- ver si la moneda es la misma que la moneda de consolidacion...
        IF sal.cod_moneda != pv_mon_consolida THEN
               -- convertir a la moneda de consolidaci�n... el saldo de y los intereses devengados...
           conversion_moneda(pv_empresa,
                                            sal.mon_operacion, -- Monto a convertir
                                            pv_fecha, -- Fecha Actual
                                            sal.cod_moneda, -- Moneda Origen
                                            pv_mon_consolida, -- Moneda Destino
                                            pv_error, -- Mensaje de error
                                            vmto_convertido); -- Monto convertido
           IF pv_error IS NOT NULL THEN
                      pv_error := NULL;
                      vmto_convertido := 0;
                   END IF;
        ELSE  -- asignar saldo e intereses devengados, m�s saldo contingente...ver modificaci�n.
               vmto_convertido := sal.mon_operacion;
        END IF;
        vdeuda_total := vdeuda_total + vmto_convertido;
    END LOOP;
    ps_deuda := vdeuda_total; --+ Obt_Saldo_Indirecto(pv_empresa, pv_cliente, pv_fecha);
        --
  END Obt_Deuda_Total_Cliente;
  --
  PROCEDURE Valida_Tama�o_Cliente (pv_empresa       IN VARCHAR2,
                                   pv_cliente       IN VARCHAR2,
                                   pv_TipoCredito   IN OUT NUMBER,
                                   pv_error         IN OUT VARCHAR2) IS
    /* Autor: JRamirez
       Fecha: 07/09/2010
       Prop�sito: Obtener el tama�o del cliente de acuerdo a los parametros obtenidos en Clientes, con estos parametros se define el indice
                  el cual define el tama�o del cliente.
    */
    --
   vdeuda_total    NUMBER(18,2) := 0;
   vmto_convertido NUMBER(18,2);
   Codigo_Cliente  VARCHAR2(15);
   Cod2_Cliente    VARCHAR2(15);
   Num_Error       NUMBER(1);
   Codigo_Producto VARCHAR2(4);
   Cod2_Producto   VARCHAR2(4);
   Codigo_Moneda   NUMBER(4);
   vl_ind_estado   cuenta_efectivo.ind_estado%TYPE;
   vpatrimonio     NUMBER(16,2);
   vventas         NUMBER(16,2);
   vempleados      NUMBER(5);
   vsector         VARCHAR2(30);
   vindice         NUMBER(8,4);
  BEGIN
    BEGIN
          SELECT patrimonio, ventas, empleados, sector, indice
            INTO vpatrimonio, vventas, vempleados, vsector, vindice
            FROM cliente
           WHERE cod_cliente = pv_cliente
             AND cod_empresa = pv_empresa;
    EXCEPTION
         WHEN no_data_found THEN
          NULL;
    END;
    IF (vindice IS NULL) OR
       (vindice = 0) THEN
       RETURN;
    END IF;
    --Evaluamos el indice para poder evaluar el credito
    IF vindice > 1 THEN
       pv_TipoCredito := vconst_tip_cred_comercial;
    ELSIF vindice > 0.035 AND vIndice <= 1 THEN
       pv_TipoCredito := vconst_tip_cred_pyme;
    ELSE
       pv_TipoCredito := vconst_tip_cred_micro;
    END IF;
  END Valida_Tama�o_Cliente;
  --
  PROCEDURE Obt_Saldo_Deudor(pv_empresa       IN VARCHAR2,
                             pv_cliente       IN VARCHAR2,
                             pv_fecha         IN DATE,
                             pv_mon_consolida IN VARCHAR2,
                             ps_deuda         IN OUT NUMBER,
                                                         ps_Int           IN OUT NUMBER,
                             pv_error         IN OUT VARCHAR2) IS
    /* Autor: HJimenez
       Fecha: 17/12/2003
       Prop�sito: Obtener el saldo deudor del cliente, sumando el saldo directo y contingente
                  de todas sus operaciones y consolidando a una sola moneda.
    */
    -- obtener por moneda el saldo y los intereses devengadosde de las operaciones del cliente
    CURSOR cur_saldos IS
      SELECT cod_moneda,
                 --SUM(NVL(saldo_tra, 0) + NVL(saldo_cont, 0)) saldo,
                 SUM(NVL(saldo_tra, 0)+ nvl(mon_diferido,0) + NVL(saldo_cont, 0)) saldo, -- SSPM 30/05/2020
                         SUM(NVL(int_deveng, 0)) int_deveng
            FROM PR_TMP_CALIF_X_CLIENTE
              WHERE cod_empresa = pv_empresa
                    AND cod_persona = pv_cliente
    GROUP BY cod_moneda;
    --
    vdeuda_total    NUMBER(18,2) := 0;
    vmto_convertido NUMBER(18,2);
        vint_conv       NUMBER(18,2) := 0;
        vint_total      NUMBER(18,2) := 0;
  BEGIN
    ps_deuda := 0;
    pv_error := NULL;
    FOR sal IN cur_saldos LOOP
        -- ver si la moneda es la misma que la moneda de consolidacion...
        IF sal.cod_moneda != pv_mon_consolida THEN
               -- convertir a la moneda de consolidaci�n... el saldo de y los intereses devengados...
           conversion_moneda(pv_empresa,
                             sal.saldo, -- Monto a convertir
                             pv_fecha, -- Fecha Actual
                             sal.cod_moneda, -- Moneda Origen
                             pv_mon_consolida, -- Moneda Destino
                             pv_error, -- Mensaje de error
                             vmto_convertido); -- Monto convertido
           IF pv_error IS NOT NULL THEN
                      pv_error := NULL;
                      vmto_convertido := 0;
                   END IF;
                   --
               -- convertir a la moneda de consolidaci�n el monto de los intereses
           conversion_moneda(pv_empresa,
                             sal.int_deveng, -- Monto a convertir
                             pv_fecha, -- Fecha Actual
                             sal.cod_moneda, -- Moneda Origen
                             pv_mon_consolida, -- Moneda Destino
                             pv_error, -- Mensaje de error
                             vint_conv); -- Monto convertido
           IF pv_error IS NOT NULL THEN
                      pv_error := NULL;
                      vint_conv := 0;
                   END IF;
                   --
        ELSE  -- asignar saldo e intereses devengados, m�s saldo contingente...ver modificaci�n.
               vmto_convertido := sal.saldo;
                   vint_conv       := sal.int_deveng;
        END IF;
        vdeuda_total := vdeuda_total + vmto_convertido;
                vint_total   := vint_total   + vint_conv;
    END LOOP;
    ps_deuda := vdeuda_total;
        ps_Int   := vint_total;
        --
  END Obt_Saldo_Deudor;
  --
  FUNCTION Obt_Garantia_Real_Hipoteca(pv_empresa IN VARCHAR2,
                                      pv_tramite IN NUMBER,
                                                                          pv_moneda  IN VARCHAR2,
                                      pv_fecha   IN DATE) RETURN NUMBER IS
    /* Autor: HJimenez
       Fecha: 19/04/2001
           Prop�sito: Obtener el monto de la garant�a de una operaci�n hipotecaria.
                      Para ello multiplica el indice de prorrateo del tr�mite por el monto
                              de la garantia.
                                  Siempre y cuando la clase de las garant�as de la operaci�n sean hipotecarias.
       Modificaci�n: 13/08/2001
                         Preguntar antes si el tr�mite est� bajo l�nea de cr�dito, porque el prorrateo lo tiene la l�nea y no
                                         el tramite hijo.
       Modificacion: 21/07/2003
              Autor: HJimenez
                     Por solicitud de HSejas se adicion� un campo en pr_garant�as para las garantias hipotecarias
                     que toma el 85% del valor comercial de la garant�a si esta cubre el saldo deudor, caso contrario el 100%.
       Modificacion: 22/08/2003
                     Tomar datos historicos..
    */
    --
    CURSOR cur_garantia IS
      SELECT b.cod_moneda, (NVL(A.ind_prorrateo, 0) * NVL(b.valor_realizacion, b.monto_garantia)) monto_garantia
--        FROM PR_GAR_X_PR_TRAMITE a, PR_GARANTIAS b
        FROM PR_GAR_X_TRAMITE_HIS A, PR_HI_GARANTIAS b
              WHERE A.num_tramite     = pv_tramite
            AND A.fec_registro_hi = pv_fecha
                AND A.cod_empresa     = pv_empresa
            AND A.estado          =  'V'          -- estado vigente de la garantia
            AND b.cod_empresa     = A.cod_empresa
            AND b.cod_garantia    = A.cod_garantia
            AND b.fec_registro_hi = pv_fecha
            AND EXISTS (SELECT 's'
                          FROM PR_TIP_GAR c
                            WHERE c.cod_tip_garantia = b.cod_tip_garantia
                              AND c.cod_clase        = vconst_cla_gar_hipotecaria);
    --
    vmto_garantia NUMBER(18,2) := 0;
        vtotal        NUMBER(18,2) := 0;
    verror        VARCHAR2(200);
        vtramite      PR_TRAMITE.num_tramite%TYPE;
  BEGIN

  /*------------------------------------------------------------------------------------*/
  --HEALVAREZ-01/2018 - Cambio para contagio interno.
  Pr_Utl.Parametro_General('CLA_GAR_HIPOTECA', 'PR', vconst_cla_gar_hipotecaria, verror);
  /*------------------------------------------------------------------------------------*/

    FOR gar IN cur_garantia LOOP
            verror := NULL;
        IF gar.cod_moneda != pv_moneda THEN
           -- llevar a dolares el monto de la garantia... se asume que el indice de prorrateo fue
           -- obtenido dolarizando la garantia y el tr�mite que avala...
           conversion_moneda(pv_empresa,
                                            gar.monto_garantia,    -- Monto a convertir
                                            pv_fecha,               -- Fecha Actual
                                            gar.cod_moneda,        -- Moneda Origen
                                            pv_Moneda,              -- Moneda Destino
                                            verror,                 -- Mensaje de error
                                            vmto_garantia);         -- Monto convertido
           IF verror IS NOT NULL THEN
              vmto_garantia := 0;
           END IF;
        ELSE
           vmto_garantia := gar.monto_garantia;
            END IF;
                vtotal := vtotal + vmto_garantia;
    END LOOP;
    RETURN vtotal;
    --
  END Obt_Garantia_Real_Hipoteca;
  --
  --
  PROCEDURE Deudas_Hipotecarias_Consumo(pv_empresa         IN VARCHAR2,
                                        pv_fecha           IN DATE,
                                        pv_persona         IN VARCHAR2,      -- cliente
                                        pv_moneda          IN VARCHAR2,      -- moneda de consolidaci�n
                                        ps_gar_real        IN OUT NUMBER,    -- garant�a real hipotecaria
                                        ps_mto_hipotecario IN OUT NUMBER,    -- saldo de la deuda hipotecaria en la moneda de consolidaci�n
                                        ps_mto_consumo     IN OUT NUMBER) IS -- saldo de la deuda de las operaciones de consumo del cliente, en la moneda de consolid.
    /* Autor: Hjimenez
       Fecha: 19/04/2001
           Prop�sito: Este procedimiento tiene por objetivo devolver el monto de la garant�a real hipotecaria,
                      el monto de la deuda hipotecaria y el monto de la deuda de cr�ditos de consumo...
                  Estas �ltimas se calculan de la tabla pr_tmp_calif_x_cliente
                  Mientras que la garant�a real hipotecaria la retorna la funci�n Obt_Garantia_Real_Hipoteca.
       Algoritmo: Toma la operaci�n hipotecaria y las de consumo del cliente.
                      Por cada operaci�n de consumo se acumula su saldo (deuda).
                  Para la operaci�n hipotecaria se convierte su saldo a la moneda de consolidaci�n
                  y adicionalmente acumula el monto de la garant�a real de esa operaci�n.
                  Al final se asignan los valores para los par�metros de salida.
           Modificaci�n: 29/08/2001
                         Por instrucci�n de la SBEF se corrige este programa.
                                         Este procedimiento solo ser� utilizado si el cliente puede ser calificado
                                         como de consumo y tiene operaciones hipotecarias...
    */
    -- obtener los tr�mites del cliente donde el tipo de credito sea hipotecario de vivienda...
    CURSOR cur_hipot_consumo IS
      --SELECT num_tramite, cod_tip_cred_s, cod_moneda, (saldo_tra  + saldo_cont) saldo_tra ANTES
      SELECT num_tramite, cod_tip_cred_s, cod_moneda, (saldo_tra + nvl(mon_diferido,0) + saldo_cont) saldo_tra  --- SSPM 30/05/2020
            FROM PR_TMP_CALIF_X_CLIENTE
              WHERE cod_empresa    = pv_empresa
                    AND cod_persona    = pv_persona;
    --
    vmto_convertido   NUMBER(18,2) := 0;
    verror            VARCHAR2(200);
  BEGIN
    ps_gar_real        := 0;
    ps_mto_hipotecario := 0;
    ps_mto_consumo     := 0;
        --
    -- primero convertir el saldo de la deuda hipotecaria a la moneda de consolidaci�n y obtener el monto de su garant�a real...
        FOR tra IN cur_hipot_consumo LOOP
            verror := NULL;
        IF tra.cod_moneda != pv_moneda THEN
           conversion_moneda(pv_empresa,
                                                 tra.saldo_tra,    -- Monto a convertir
                                                 pv_fecha,         -- Fecha Actual
                                                 tra.cod_moneda,   -- Moneda Origen
                                                 pv_moneda,        -- Moneda Destino
                                                 verror,           -- Mensaje de error
                                                 vmto_convertido); -- Monto convertido
           IF verror IS NOT NULL THEN
              vmto_convertido := 0;
           END IF;
        ELSE
           vmto_convertido := tra.saldo_tra;
        END IF;
        IF tra.cod_tip_cred_s IN (vconst_tip_cred_hipotecario,vconst_tip_cred_hipotecario19,
                                  vconst_tip_cred_hipotecario20,vconst_tip_cred_hipotecario21,vconst_tip_cred_hipotecario9) THEN
           ps_mto_hipotecario := ps_mto_hipotecario + vmto_convertido;
           --
           -- ahora obtener el monto de la garant�a real del tr�mite..
           ps_gar_real := ps_gar_real + Obt_Garantia_Real_Hipoteca(pv_empresa, tra.num_tramite, pv_moneda, pv_fecha);
        ELSE
           ps_mto_consumo := ps_mto_consumo + vmto_convertido;
        END IF;
                --
    END LOOP;
  END Deudas_Hipotecarias_Consumo;
  --
  --
  PROCEDURE Garantias_Hipotecarias(pv_empresa            IN VARCHAR2,
                                   pv_fecha              IN DATE,        -- fecha de proceso
                                   pv_tramite            IN NUMBER,
                                   pv_moneda             IN VARCHAR2,    -- su moneda
                                   pv_tipgar_hipo_rural  IN NUMBER,      -- tipo de garant�a hipotecaria sobre bienes inmuebles rurales
                                   pv_tipgar_hipo_urbano IN NUMBER,      -- tipo de garant�a hipotecaria sobre bienes inmuebles urbanos
                                                                   pv_derechos_reales    IN VARCHAR2,    -- c�digo de ente de 'Derechos Reales'
                                                                   pv_codigo_busa        IN VARCHAR2,    -- c�digo de persona del BUSA
                                                                   pv_valor_prorrateado  IN BOOLEAN,     -- valor prorrateado o del aval�o de la garant�a...
                                   ps_gar_hipotecaria    IN OUT BOOLEAN, -- es garant�a hipotecaria...
                                   ps_mon_garantia       IN OUT NUMBER,  -- monto de la garant�a hipotecaria (en moneda de consolidaci�n)...
                                   ps_error              IN OUT VARCHAR2) IS
    /* Autor: HJimenez
       Fecha: 07/05/2001
       Prop�sito: Retorna en ps_mon_garantia, el monto de las garant�as de una operaci�n si estas son hipotecarias
                      sobre bienes inmuebles, registradas en Derechos Reales, en grado preferente (1er. grado) en favor
                                  del banco.
    */
    -- determina el tipo de garant�a...
    CURSOR cur_gar IS
      SELECT
             b.cod_moneda, A.ind_prorrateo, NVL(b.VALOR_REALIZACION, b.monto_garantia) monto_garantia
--        FROM PR_GAR_X_PR_TRAMITE a, PR_GARANTIAS b, PR_GRAVAMEN c
        FROM PR_GAR_X_TRAMITE_HIS A,  PR_HI_GARANTIAS b, PR_GRAVAMEN c
          WHERE A.cod_empresa       = pv_empresa
            AND A.num_tramite       = pv_tramite
            AND A.fec_registro_hi   = pv_fecha
            AND A.estado            = 'V'
            AND A.grado             = 1 -- (1er. grado)
            AND b.cod_empresa       = A.cod_empresa
            AND b.cod_garantia      = A.cod_garantia
            AND b.fec_registro_hi   = pv_fecha
            AND b.cod_tip_garantia IN (pv_tipgar_hipo_rural, pv_tipgar_hipo_urbano, ctipgarnopropia, ctipgarotropropi)
            AND c.cod_empresa       = b.cod_empresa
            AND c.cod_garantia      = b.cod_garantia
            AND c.grado             = A.grado
            AND c.cod_ente_registro = pv_derechos_reales   -- Registro en Derechos Reales
            AND c.cod_persona       = pv_codigo_busa;      -- a favor del Banco Uni�n
    --
    vmon_garantia NUMBER(18,2);
        vavaluo       NUMBER(18,2);
    vexito        BOOLEAN := FALSE;
  BEGIN
    --
        ps_mon_garantia    := 0;
        ps_gar_hipotecaria := FALSE; -- se inicializa...
    FOR gar IN cur_gar LOOP -- por si hay m�s de 1 garant�a por operaci�n...
        ps_gar_hipotecaria := TRUE;
                IF pv_valor_prorrateado THEN
           vmon_garantia := gar.ind_prorrateo * gar.monto_garantia;
                ELSE
           vmon_garantia := gar.monto_garantia;
                END IF;
        -- consolidar a la misma moneda de la operaci�n...
        IF pv_moneda != gar.cod_moneda THEN -- son diferentes
           ps_error := NULL;
           conversion_moneda(pv_empresa,
                                                 vmon_garantia, -- Monto a convertir
                                                 pv_fecha,         -- Fecha Actual
                                                 gar.cod_moneda,   -- Moneda Origen
                                                 pv_moneda,        -- Moneda Destino
                                                 ps_error,         -- Mensaje de error
                                                 vavaluo);         -- Monto convertido
           IF ps_error IS NOT NULL THEN
              vavaluo := 0;
           END IF;
            ELSE
           vavaluo := vmon_garantia;
        END IF;
        ps_mon_garantia := ps_mon_garantia + vavaluo;
    END LOOP;
  END Garantias_Hipotecarias;
  --
  --
  PROCEDURE Califica_X_Incobrable(pv_empresa IN VARCHAR2,
                                  pv_error   IN OUT VARCHAR2) IS
    /* Autor: HJimenez
       Fecha: 27/04/2001
           Prop�sito: Toda operaci�n que est� castigada, debe ser calificada con la peor
                      calificaci�n posibles.  Esta calificaci�n es heredada por los codeudores
                  de la operaci�n.
    */
    -- seleccionar todos los tramites que est�n castigados (incobrables).
    CURSOR cur_tramites IS
      SELECT num_tramite, COUNT('s')
            FROM PR_TMP_CALIF_X_CLIENTE
              WHERE cod_empresa   = pv_empresa
                    AND codigo_estado = Pr_Utl_Estados.Verif_Estado_Castigado(codigo_estado) -- s�lo operaciones castigadas...
                    AND cod_calif    IS NULL
      GROUP BY num_tramite;
    --
    vtramite PR_TRAMITE.num_tramite%TYPE;
  BEGIN
    FOR tra IN cur_tramites LOOP
        vtramite := tra.num_tramite;
        UPDATE PR_TMP_CALIF_X_CLIENTE A
           SET A.cod_calif = vconst_califpeor,
               A.motivo    = 'Por incobrabilidad'
             WHERE A.cod_empresa = pv_empresa
                   AND A.num_tramite = tra.num_tramite;
        Contador_Commit;
    END LOOP;
    Realiza_Commit;
    --
    EXCEPTION
       WHEN OTHERS THEN
            mnj_errores.fijar_error('002140', 'PR', 'Tramite: ' || vtramite || SQLERRM, UPPER('Califica_X_Incobrable'),
                                     NULL, 'OTHERS');
            pv_error := '002140';
  END Califica_X_Incobrable;
  --
  PROCEDURE Califica_X_Ejecucion4(pv_empresa   IN VARCHAR2,
                                  pv_fecha     IN DATE,
                                  pv_persona   IN VARCHAR2,
                                                                  pv_tramite   IN NUMBER,
                                                                  pv_moneda    IN VARCHAR2,
                                                                  pv_dias_mora IN NUMBER,
                                  pv_sal_total IN NUMBER,
                                                                  pIntereses   IN NUMBER,
                                                                  ps_calif     IN OUT VARCHAR2,
                                                                  ps_motivo    IN OUT VARCHAR2,
                                  pv_error     IN OUT VARCHAR2) IS
    /* Autor: HJimenez
       Versi�n modificada del Califica_X_Ejecucion4
       Modificacion: 15/12/2003
                     Seg�n requerimiento de HSEJAS.
                     Se obtiene el monto total de las garant�as hipotecarias del cliente.
                     Si estas cubren el total de la deuda se califica la operaci�n seg�n esta tabla.
                        Si Mora <= 450 entonces calificaci�n 3B
                        Si Mora > 450 entonces calificaci�n 4
                        Si Mora > 810 entonces calificaci�n 5.
                     Si no entonces.
                        Calificaci�n 5.
De:     Henrry Sejas Lazarte
Enviado el:     viernes, 12 de diciembre de 2003 18:57
Para:   Alvaro Dorado Sanchez
CC:     Julian Seco; Miguel Sepulveda; Miguel Papadopulos S.; Ronald Mariscal Flores; Juan Carlos Fernandez Vasquez
Asunto: Modificacion del programa de calificacion de cartera
Importancia:    Alta

Estimado Alvaro:
De acuerdo a la normativa vigente, cuando se inicia el proceso de recuperaci�n de
cartera por la v�a judicial o cuando un cr�dito cambie al Estado Ejecuci�n y en
caso de que el pr�stamo no cuente con garant�as reales en primer grado que cubran
la deuda, se debe calificar al prestatario en la categor�a 5 (perdidos). Favor
instruir a quien corresponda realizar esta modificaci�n en el programa de
calificaci�n de cartera.
Atte.
Henry Sejas Lazarte
Sub Gerente
 Evaluaci�n y Calificaci�n de Cartera
    --
    Modificacion: 09/05/2005
                  Por interpretaci�n de HSEJAS a la Circular SB/494:
                         Cr�ditos comerciales en ejecuci�n:
                       o        Si las garant�as hipotecarias en primer grado >= 50% del saldo + intereses -> calificaci�n F
                       o        Si las garant�as hipotecarias en primer grado < 50% del saldo + intereses -> calificaci�n G
                       o        Si no posee garant�as hipotecarias en primer grado -> calificaci�n H
    --
        Autor: HJimenez
        Fecha: 20/12/2007
        Prop.: De: Henrry Sejas Lazarte
                   Enviado el: jueves, 06 de diciembre de 2007 10:42
                   Para: Herman Jimenez Fuentes
                   CC: Eduardo Lunabarrera
                   Asunto: RV: Operaciones con deficiencia de prevision
                   Seg�n observaciones de la SBEF, han identificado algunos casos de clientes comerciales en
                   ejecuci�n cuya calificaci�n depende de la garant�a, la misma no llega a cubrir el 50% de la
                   deuda (capital e intereses), sin embargo estar�an siendo calificados "F". Al parecer el
                   programa de calificaci�n no estar�a considerando los productos en suspenso para realizar
                   esa relaci�n. Favor confirmar esta situaci�n y en su caso realizar las modificaciones
                   necesarias al programa de calificaci�n.
                   --
                   ** Obtener los intereses en suspenso no los devengados...
    */
    CURSOR cur_tramite IS
      --SELECT ROWID, num_tramite, cod_moneda, (saldo_tra + saldo_cont) saldo_tra
      SELECT ROWID, num_tramite, cod_moneda, (saldo_tra+ nvl(mon_diferido,0) + saldo_cont) saldo_tra --- SSPM 30/05/2020
            FROM PR_TMP_CALIF_X_CLIENTE
          WHERE cod_empresa = pv_empresa
            AND cod_persona = pv_persona
    ORDER BY cod_empresa, num_tramite;
    --
    vtot_hipotecario NUMBER(18,2) := 0;
    vgar_hipotecaria BOOLEAN := FALSE;
    vmon_garantia    NUMBER(18,2);
    vInt_Sus_Estado  NUMBER(18,2) := 0;
  BEGIN
    ps_calif  := NULL;
    -- saber si las garantias hipotecarias cubren el total de la deuda el riesgo...
    FOR tra IN cur_tramite LOOP
        vgar_hipotecaria := FALSE;
        vmon_garantia    := 0;
        --
        Garantias_Hipotecarias(pv_empresa,
                               pv_fecha,                  -- fecha de proceso
                               tra.num_tramite,
                               tra.cod_moneda,                 -- su moneda
                               vconst_tipgar_hipo_rural,  -- tipo de garant�a hipotecaria sobre bienes inmuebles rurales
                               vconst_tipgar_hipo_urbano, -- tipo de garant�a hipotecaria sobre bienes inmuebles urbanos
                               vconst_derechos_reales,    -- c�digo de ente de 'Derechos Reales'
                               vconst_codigo_busa,        -- c�digo de persona del BUSA
                               TRUE,                      -- valor prorrateado (TRUE) o del aval�o de la garant�a...
                               vgar_hipotecaria,          -- es garant�a hipotecaria...
                               vmon_garantia,             -- monto de la garant�a hipotecaria (en moneda de consolidaci�n)...
                               pv_error);
        IF pv_error IS NULL AND vgar_hipotecaria THEN -- es garant�a hipotecaria...acumular
           vtot_hipotecario := vtot_hipotecario + NVL(vmon_garantia,0);
        END IF;
        pv_error := NULL;
    END LOOP;
        /* Autor: HJimenez
           Fecha: 20/12/2007
           Prop.: Obtener los intereses en suspenso de la operaci�n...
    */
        DECLARE
      vInt_Sus_Desembolsado  NUMBER(18,2) := 0;
      vInt_Acum_Desembolsado NUMBER(18,2) := 0;
      vInt_Acum_Estado       NUMBER(18,2) := 0;
      vcod_error             VARCHAR2(200):= NULL;
          vcod_tip_operacion     PR_TRAMITE.cod_tip_operacion%TYPE;
          vno_credito            PR_CREDITOS.no_credito%TYPE;
          vcodigo_sucursal       NUMBER(5);
    BEGIN
          BEGIN
            SELECT A.cod_tip_operacion, b.no_credito, c.codigo_sucursal
                  INTO vcod_tip_operacion, vno_credito, vcodigo_sucursal
                    FROM PR_TRAMITE A, PR_CREDITOS b, cg_unidades_ejecutoras c
                          WHERE A.cod_empresa = pv_empresa
                            AND A.num_tramite = pv_tramite
                                --
                                AND b.codigo_empresa = A.cod_empresa
                                AND b.num_tramite = A.num_tramite
                                --
                                AND c.codigo_empresa = A.cod_empresa
                                AND c.unidad_ejecutora = A.unidad_ejecutora;
        EXCEPTION
                   WHEN OTHERS THEN
                        pv_error := 'Error obteniendo no_credito: ' || pv_tramite ||';'|| SQLERRM;
                                RETURN;
      END;
          --
      Pr_Sbef2_Bd.Calcular_Interes_Estado_His (pv_empresa, -- P_Cod_Empresa           IN  VARCHAR2,
                                               vno_credito, -- P_No_Credito            IN  NUMBER,
                                               pv_fecha,  -- P_Fec_Corte             IN  DATE,
                                               vInt_Acum_Desembolsado, -- OUT NUMBER,
                                               vInt_Acum_Estado      , -- OUT NUMBER,
                                               vInt_Sus_Desembolsado , -- OUT NUMBER,
                                               vInt_Sus_Estado       , -- OUT NUMBER, � ESTE ES LO QUE LE SIRVE
                                               vcod_tip_operacion, -- P_Tip_opera             IN  NUMBER,
                                               'PR747', -- P_Cod_Forma             IN  VARCHAR2,
                                               vcodigo_sucursal, -- P_Sucursal              IN  NUMBER,
                                               pv_error); --              IN  VARCHAR2
      EXCEPTION
         WHEN OTHERS THEN
                  pv_error := 'Error obteniendo int suspenso: ' || pv_tramite ||';'|| SQLERRM;
                      RETURN;
    END;
    --
    IF vtot_hipotecario > 0 THEN -- tiene garant�a hipotecaria...
           -- Si la garant�a cubre el 50% del saldo + intereses entonces calif F, de otro modo G.
--       IF vtot_hipotecario >= 0.50 * (pv_sal_total + pIntereses) THEN
       IF vtot_hipotecario >= 0.50 * (pv_sal_total + vInt_Sus_Estado) THEN
          ps_motivo := 'Operaci�n C0 en ejecuci�n con gar.hipo >= 50% saldo+int';
          ps_calif := 'F';
       ELSE
          ps_motivo := 'Operaci�n C0 en ejecuci�n con gar.hipo < 50% saldo+int';
          ps_calif := 'G';
       END IF;
    ELSE
       ps_motivo := 'Operaci�n C0 en ejecuci�n sin garant�a hipotecaria';
       ps_calif := 'H';
    END IF;
    --
  END Califica_X_Ejecucion4;
  --
  FUNCTION Obt_Garantia_Real(pv_empresa IN VARCHAR2,
                             pv_cliente IN VARCHAR2,
                                                         pv_moneda  IN VARCHAR2,
                             pv_fecha   IN DATE) RETURN NUMBER IS
    /* Autor: HJimenez
       Fecha: 15/11/2002
           Prop�sito: Obtener el monto total de la garant�a real de un cliente
                      Para ello multiplica el indice de prorrateo del tr�mite por el monto
                              de la garantia.
                  Se excluyen las garant�as personales que tiene grado 0 en pr_gar_x_pr_tramite...
       ---------------
       Modificacion: 19/11/2002
          Prop�sito: La garant�a real debe entenderse como el monto de la garant�a
                     hipotecaria registrada en Derechos Reales en grado preferente
                     a favor del banco.
                     Lee primero todas las operaciones calificables del cliente
                     y calcula el monto total de sus garantias reales.
       ---------------
       Modificacion: 22/11/2002
          Prop�sito: Seg�n Riesgo se debe considerar como garant�a real el monto
                     de garant�as autoliquidables
    */
    --
    CURSOR cur_tramites IS
      SELECT num_tramite, cod_moneda, saldo_tra, saldo_cont, int_deveng
        FROM PR_TMP_CALIF_X_CLIENTE
         WHERE cod_empresa   = pv_empresa
           AND cod_persona   = pv_cliente;
    --
    vmon_garantia    NUMBER(18,2);
        vtotal           NUMBER(18,2) := 0;
    verror           VARCHAR2(200);
    vgar_hipotecaria BOOLEAN;
    vexcep           BOOLEAN;
    vgar_auto        NUMBER(18,2);
    vmon_conv        NUMBER(18,2);
  BEGIN
    FOR tra IN cur_tramites LOOP
            verror           := NULL;
        vmon_garantia    := 0;
        vexcep           := FALSE;
        vgar_auto        := 0;
        vgar_hipotecaria := FALSE;
        vmon_conv        := 0;
        Garantias_Hipotecarias(pv_empresa,
                               pv_fecha,                  -- fecha de proceso
                               tra.num_tramite,
                               tra.cod_moneda,            -- su moneda
                               vconst_tipgar_hipo_rural,  -- tipo de garant�a hipotecaria sobre bienes inmuebles rurales
                               vconst_tipgar_hipo_urbano, -- tipo de garant�a hipotecaria sobre bienes inmuebles urbanos
                               vconst_derechos_reales,    -- c�digo de ente de 'Derechos Reales'
                               vconst_codigo_busa,        -- c�digo de persona del BUSA
                               TRUE,                      -- valor prorrateado (TRUE) o del aval�o de la garant�a...
                               vgar_hipotecaria,          -- es garant�a hipotecaria...
                               vmon_garantia,             -- monto de la garant�a hipotecaria (en moneda de consolidaci�n)...
                               verror);
        IF verror IS NULL AND vgar_hipotecaria THEN -- es garant�a hipotecaria...acumular
           vtotal := vtotal + NVL(vmon_garantia,0);
        END IF;
        --
        verror := NULL;
        --
        Oper_Autoliquidable_His(pv_empresa,
                                tra.num_tramite,
                                pv_fecha,
                                tra.cod_moneda,
                                tra.saldo_tra,
                                tra.saldo_cont,
                                tra.int_deveng,
                                vexcep, -- es excepci�n por tener garant�as autoliquidables o no...
                                vgar_auto,
                                verror);
        IF verror IS NULL THEN
           IF tra.cod_moneda != pv_moneda THEN -- son diferentes
              conversion_moneda(pv_empresa,
                                               vgar_auto, -- Monto a convertir
                                               pv_fecha,         -- Fecha Actual
                                               tra.cod_moneda,   -- Moneda Origen
                                               pv_moneda,        -- Moneda Destino
                                               verror,         -- Mensaje de error
                                               vmon_conv);         -- Monto convertido
              IF verror IS NULL THEN
                 -- aumentar las garant�as autoliquidables...
                 vtotal := vtotal + NVL(vmon_conv, 0);
              END IF;
           ELSE
              vtotal := vtotal + NVL(vgar_auto,0);
           END IF;
        END IF;
    END LOOP;
    --
    RETURN NVL(vtotal, 0);
    --
  END Obt_Garantia_Real;
  --
  FUNCTION Cred_C0_Ejecucion(pEmpresa IN VARCHAR2,
                             pPersona IN VARCHAR2) RETURN BOOLEAN IS
    /* Autor: HJimenez
           Fecha: 09/05/2005
           Prop.: Retorna TRUE si el cliente tiene una operaci�n en ejecuci�n.
                  De otro modo, retorna FALSE.
                          Previamente se categoriz� el cliente como comercial.
    */
        vCount NUMBER(5) := 0;
  BEGIN
    SELECT COUNT('s')
          INTO vCount
        FROM PR_TMP_CALIF_X_CLIENTE
              WHERE cod_empresa = pEmpresa
                    AND cod_persona = pPersona
                        AND codigo_estado = Pr_Utl_Estados.verif_estado_ejecucion(codigo_estado);
    RETURN vCount > 0;
        --
        EXCEPTION
           WHEN OTHERS THEN
                RETURN FALSE;
  END Cred_C0_Ejecucion;
  --
  PROCEDURE Califica_X_Mora (pv_empresa IN VARCHAR2,
                             pv_fecha   IN DATE,
                             pv_error   IN OUT VARCHAR2) IS
    /* Autor: HJimenez
           Fecha: 18/04/2001
       Prop�sito:  Calificar a los clientes seg�n el n�mero de d�as de atraso de sus operacioens...
                   Primero debe determinarse c�mo calificar al cliente, seg�n los siguiente criterios:
                   1. Si tiene un cr�dito comercial pero el total de su deuda es menor a $us 35000, entonces las operaciones
                      del cliente se califican como de consumo, de otro modo se califica como comercial.
                   2. Si el cliente tuviera cr�ditos hipotecarios y de consumo, debe ser calificado como Hipotecario si la
                      garant�a real cubre ambas deudas, de otro modo ser� calificado como de consumo.
           -------------
           Modificaci�n(1): 23/10/2001
                        Para todo cliente a ser calificada se consulta su deuda total y se inserta en la tabla temporal
       Modificaci�n(2): 23/10/2001 (a solicitud de Riesgo Crediticio -- Henrry Sejas)
                            La Aud. Externa ha observado que hay cr�ditos de consumo e hipotecarios en ejecuci�n que han sido calificados
                                                con 1 y 2.  Esto es porque se califican solamente por su antiguedad de la mora pero est�n en ejecuci�n
                                                porque tienen cargos judiciales pendientes aunque el cliente haya pagado o porque manualmente se haya
                                                ejecutado.
                                                Lo que se quiere es que adicionalmente a la antiguedad de la mora se verifique el estado de la operaci�n
                                                y si est� en ejecuci�n califique con 3 como m�nimo.
           -------------
       Modificacion: 15/11/2002
                     Seg�n DS. 26838 se introducen dos nuevas categor�as para cr�ditos comerciales...
                     3A con porc. prev: 10%
                     3B con porc. prev: 20%
                     Diviendo la categor�a 3.
                     Para solucionar esto el sistema calificar� 3 seg�n la antiguedad de mora
                     pero dependiendo si la operaci�n est� vigente se califica con 3A, si est� en
                     mora con 3B.
       -------------
       Modificaci�n: 15/11/2002
                     Seg�n DS. 26838 y correo de HSejas:
                     "3. Los clientes calificados como Microcr�dito con garant�a real, asumen el par�metro
                     de los clientes hipotecarios.  Se debe entender como Micr�cr�ditos, adem�s de los identificados
                     originalmente como tal, a los clientes comerciales con endeudamiento original menor a $us 35 mil
                     pero que tengan garant�a real.
       --------------
       Modificaci�n: 21/11/2002
                     Seg�n Riesgo para cr�ditos de consumo, microcr�ditos con garant�a real y sin
                     garant�a real se calificar�n:
                     3: Si tienen dos reprogramaciones
                     4: Si tienen tres reprogramaciones
                     5: Si tienen m�s de cuatro reprogramaciones
                     Leer pr_ran_calif.cant_reprogra
       Modificaci�n: 16/06/2003
                     En algunos casos, la calificacion de CREDIAGIL manda sobre la del Openbank, aunque
                     globalmente el cliente sea comercial o hipotecario de Vivienda.
       Modificacion: 22/08/2003
                     Usar interfaces historicas
       Modificaci�n: 09/05/2005
                         Si el cliente es comercial determinar si tiene un cr�dito comercial en ejecuci�n.
                                         Eliminar calificaci�n por cr�dito de consumo debidamente garantizado
                                         Eliminar calificaci�n por reprogramaciones
       Modificacion : 07/09/2010 Para aplicar circular 047/2010 ASFI
                      Se cambia la denominacion de creditos comerciales x empresariales y Pyme, se los
                      sigue evaluando igual a un credito comercial por el monto total de la deuda del cliente.
    */
    -- obtener los clientes que no han sido calificados ni por un ente externo ni por tener reprogramaciones....
    CURSOR cur_clientes IS
      SELECT cod_persona
            FROM PR_TMP_CALIF_X_CLIENTE
              WHERE cod_empresa = pv_empresa
                    AND cod_calif   IS NULL
      GROUP BY cod_persona
      ORDER BY cod_persona;
    --
    -- obtener el n�mero de cr�ditos por tipo que tiene un cliente espec�fico...
    --Se incorpora los Creditos Pyme y microcreditos-- Circ. 047/2010
    --Se incorporan los otros tipo de credito Agropecuarios. 04-01-2013 - JCRS.
    CURSOR cur_creditos (p_persona IN VARCHAR2) IS
      SELECT SUM(DECODE(cod_tip_cred_s, vconst_tip_cred_comercial,1,vconst_tip_cred_comercialC2,1,vconst_tip_cred_comercialC3,1,0)) cred_comercial,
             SUM(DECODE(cod_tip_cred_s, vconst_tip_cred_pyme,1,vconst_tip_cred_pymeP5,1,vconst_tip_cred_pymeP6,1,0)) cred_pyme,
             ----SUM(DECODE(cod_tip_cred_s, vconst_tip_cred_micro      , 1, 0)) cred_micro, ---- antes el sistema no considera los nuevos tipos de credito aSFI Microcreditos
             SUM(DECODE(cod_tip_cred_s, vconst_tip_cred_micro  , 1, 10, 1, 6, 1, 11, 1, 12, 1 , 0)) cred_micro,  --- SSPM 05/12/2016  tomando encuenta los nuevos tipos de creditos ASFI micro
             SUM(DECODE(cod_tip_cred_s, vconst_tip_cred_hipotecario, 1, 0)) cred_hipotecario,
             SUM(DECODE(cod_tip_cred_s, vconst_tip_cred_hipotecario19, 1, 0)) cred_hipotecario19,
             SUM(DECODE(cod_tip_cred_s, vconst_tip_cred_hipotecario20, 1, 0)) cred_hipotecario20,
             SUM(DECODE(cod_tip_cred_s, vconst_tip_cred_hipotecario21, 1, 0)) cred_hipotecario21,
             SUM(DECODE(cod_tip_cred_s, vconst_tip_cred_hipotecario9, 1, 0)) cred_hipotecario9,
             --SUM(DECODE(cod_tip_cred_s, vconst_tip_cred_consumo    , 1, vconst_tip_cred_consumo_dg, 1, 2, 1, 6, 1, 0)) cred_consumo
             SUM(DECODE(cod_tip_cred_s, vconst_tip_cred_consumo , 1, 4, 1, 0)) cred_consumo
        FROM PR_TMP_CALIF_X_CLIENTE
       WHERE cod_empresa = pv_empresa
         AND cod_persona = p_persona;
    --
    -- obtiene todos los tr�mites sin calificar asociados a un cliente espec�fico...
    CURSOR cur_tramites (p_persona IN VARCHAR2) IS
      --SELECT ROWID, num_tramite, codigo_estado, cod_tip_cred_s, num_dias_mora, cod_moneda, (saldo_tra + saldo_cont) saldo_tra, int_deveng  --- ANTES
      SELECT ROWID, num_tramite, codigo_estado, cod_tip_cred_s, num_dias_mora, cod_moneda, (saldo_tra + nvl(MON_DIFERIDO,0) + saldo_cont) saldo_tra, int_deveng  --- SSPM 30/05/2020
            FROM PR_TMP_CALIF_X_CLIENTE
          WHERE cod_empresa = pv_empresa
            AND cod_persona = p_persona
            AND cod_calif   IS NULL
    ORDER BY cod_empresa, cod_tip_cred_s;
    --
    -- obtiene el c�digo de calificaci�n seg�n el tipo de cr�dito y los d�as de atraso...
    CURSOR cur_califica (p_tip_cred_s  IN NUMBER,
                         p_dias_atraso IN NUMBER) IS
        -- LSALAS 24/06/2024 - MA 523505 Validacion Obtencion Calificacion Operaciones con mas de 9999 Dias Mora --
        -- Casos Empresa 10 - Fideicomiso LA PAZ EFV --
        /*SELECT cod_calif
          FROM pr_ran_calif
         WHERE cod_empresa    = pv_empresa
           AND cod_tip_cred_s = p_tip_cred_s
           AND dias_desde    <= p_dias_atraso
           AND dias_hasta    >= p_dias_atraso;*/

        SELECT cod_calif
          FROM pr_ran_calif
         WHERE cod_empresa = pv_empresa
           AND cod_tip_cred_s = p_tip_cred_s
           AND ((dias_desde <= p_dias_atraso AND dias_hasta >= p_dias_atraso)
                OR (dias_hasta = 9999 AND dias_hasta <= p_dias_atraso));
        -- LSALAS 24/06/2024 - MA 523505 Validacion Obtencion Calificacion Operaciones con mas de 9999 Dias Mora --
    --
    CURSOR cur_tip_cred_s (p_tip_cred_s IN NUMBER) IS
      SELECT cod_sbef
            FROM PR_TIP_CREDITO_SUPER
              WHERE cod_empresa = pv_empresa
            AND cod_tip_cred_s = p_tip_cred_s;
    --
    vdeuda_total        NUMBER(18,2) := 0;
    vcod_calif          PR_CALIFICACION.cod_calif%TYPE;
    vmotivo             PR_TMP_CALIF_X_CLIENTE.motivo%TYPE;
    --
    vmoneda             NUMBER(5);
    vcliente            VARCHAR2(15):= NULL;
    --
    rcre                cur_creditos%ROWTYPE;
    vtip_cred_s         PR_TIP_PRODUCTO.cod_tip_cred_s%TYPE;
    vaux_cred_s         PR_TIP_PRODUCTO.cod_tip_cred_s%TYPE;
    vgaran_real         NUMBER(18,2) := 0;
    vmto_hipotecario    NUMBER(18,2) := 0;
    vmto_consumo        NUMBER(18,2) := 0;
    vsaldo_deudor       NUMBER(18,2) := 0;
    vtip_credito_s      PR_TIP_CREDITO_SUPER.cod_sbef%TYPE;
    etermina            EXCEPTION;
    vC0_ejecucion       BOOLEAN := FALSE;
    vintereses          NUMBER(18,2) := 0;
    vl_es_calif_manual  VARCHAR2(2) := 'N';
    vl_cotiz_Sus        number ( 18,5);     -- SSPM 23/04/2020
    vl_cotiz_UFV        number(18,5);       -- SSPM 23/04/2020
    --
  BEGIN

    CG_UTL.Obtiene_TC_CONTA (1,pv_fecha, vl_cotiz_Sus, pv_error); --- 23/04/2020
    IF pv_error IS NOT NULL THEN
        RETURN;
    END IF;

    CG_UTL.Obtiene_TC_CONTA(4,pv_fecha, vl_cotiz_UFV, pv_error); -- 23/04/2020
    IF pv_error IS NOT NULL THEN
        RETURN;
    END IF;

    pv_error := NULL;
    FOR cli IN cur_clientes LOOP

        -- inicializar variables de control por cliente...
                vintereses    := 0;
                vC0_ejecucion := FALSE;
                vtip_cred_s   := NULL;
                vdeuda_total  := NULL;
                vgaran_real   := 0;
                vmto_consumo  := 0;
                --
        -- contar el n�mero de operaciones que tiene seg�n su tipo...
            OPEN cur_creditos(cli.cod_persona);
            FETCH cur_creditos INTO rcre;
            CLOSE cur_creditos;
                -- por modificaci�n 23/10/2001...para todos los clientes se consulta su deuda total...
        Obt_Deuda_Total_Cliente(pv_empresa,  --- SSPM 30/05/2020 revisado
                                cli.cod_persona,
                                pv_fecha,
                                vconst_moneda_consolid,
                                vdeuda_total,
                                pv_error);
        -- verificar si se produjo error...
        IF pv_error IS NOT NULL THEN
                   RAISE etermina;
        END IF;
            -- ver si tiene cr�ditos comerciales ahora llamados  Empresarial..
        -- Circ 047/2010 --JCRS
        IF rcre.cred_comercial > 0 THEN -- si tiene cr�ditos comerciales entonces obtener el monto total de su deuda...
           -- analizar el monto total de la deuda del cliente para ver si califica como comercial o de consumo...
           IF vdeuda_total <= VConst_MontoComercial THEN
              --Se quita a pedido de henrry sejas en fecha 22-09-2010 pq ya no debemos calificacarlos como consumo si no como Microcredito
              --vtip_cred_s := vconst_tip_cred_consumo; -- si es menor debe ser calificado como consumo...
              vtip_cred_s := vconst_tip_cred_micro; -- si es menor debe ser calificado como consumo...
              --
           ELSE
              vtip_cred_s := vconst_tip_cred_comercial; -- de otro modo como comercial
              --Validamos de acuerdo al Indice de Actividad(Tama�o del cliente)
              --Circ. 047/2010
              --JCRS -07-09-2010
              Valida_Tama�o_Cliente (pv_empresa,
                                     cli.cod_persona,
                                     vtip_cred_s,
                                     pv_error);
              -- verificar si se produjo error...
              IF pv_error IS NOT NULL THEN
                 RAISE etermina;
              END IF;
              -- Seg�n SB/494 si tiene un cr�dito comercial en ejecuci�n calificar todas sus operaciones con ese criterio...
              --Ya no Aplica de acuerdo a nueva circular 047/2010
              --vC0_ejecucion := Cred_C0_Ejecucion(pv_empresa, cli.cod_persona);
           END IF;
        --Se incorpora los PYME para evaluarlos como creditos empresarial
        --Circ 047/2010
        ELSIF rcre.cred_pyme > 0 THEN -- si tiene cr�ditos Pyme entonces obtener el monto total de su deuda...
              -- analizar el monto total de la deuda del cliente para ver si califica como Pyme o de consumo...
              IF vdeuda_total <= VConst_MontoComercial THEN
                 vtip_cred_s := vconst_tip_cred_micro; -- si es menor debe ser calificado como consumo...
              ELSE
                 vtip_cred_s := vconst_tip_cred_pyme; -- de otro modo como comercial
                 --Validamos de acuerdo al Indice de Actividad(Tama�o del cliente)
                 --Circ. 047/2010
                 --JCRS -07-09-2010
                 Valida_Tama�o_Cliente (pv_empresa,
                                        cli.cod_persona,
                                        vtip_cred_s,
                                        pv_error);
                 -- verificar si se produjo error...
                 IF pv_error IS NOT NULL THEN
                    RAISE etermina;
                 END IF;
              --
              END IF;
        ELSIF rcre.cred_hipotecario > 0 AND   -- si tiene cr�ditos hipotecario...
              rcre.cred_consumo     > 0 THEN  -- y tiene cr�ditos de consumo...
              Deudas_Hipotecarias_Consumo(pv_empresa, pv_fecha, cli.cod_persona, vconst_moneda_consolid,
                                                      vgaran_real, vmto_hipotecario, vmto_consumo);
           --
           -- analizar si la garant�a real cubre la deuda del cr�dito hipotecario y de consumo...
           IF vgaran_real >= vmto_hipotecario + vmto_consumo THEN
              vtip_cred_s := vconst_tip_cred_hipotecario; -- se califica como hipotecario...
           ELSE
              vtip_cred_s := vconst_tip_cred_consumo; -- si no, se califica como consumo...
           END IF;
        ELSIF rcre.cred_hipotecario > 0 AND   -- si tiene cr�ditos hipotecario...
              rcre.cred_consumo     = 0 THEN  -- y NO tiene cr�ditos de consumo...
              vtip_cred_s := vconst_tip_cred_hipotecario; -- se califica como hipotecario...
        --NUEVO
        ELSIF rcre.cred_hipotecario19 > 0 AND   -- si tiene cr�ditos hipotecario...
              rcre.cred_consumo     > 0 THEN  -- y tiene cr�ditos de consumo...
              Deudas_Hipotecarias_Consumo(pv_empresa, pv_fecha, cli.cod_persona, vconst_moneda_consolid,
                                                      vgaran_real, vmto_hipotecario, vmto_consumo);
           --
           -- analizar si la garant�a real cubre la deuda del cr�dito hipotecario y de consumo...
           IF vgaran_real >= vmto_hipotecario + vmto_consumo THEN
              vtip_cred_s := vconst_tip_cred_hipotecario19; -- se califica como hipotecario...
           ELSE
              vtip_cred_s := vconst_tip_cred_consumo; -- si no, se califica como consumo...
           END IF;
        ELSIF rcre.cred_hipotecario19 > 0 AND   -- si tiene cr�ditos hipotecario...
              rcre.cred_consumo       = 0 THEN  -- y NO tiene cr�ditos de consumo...
              vtip_cred_s := vconst_tip_cred_hipotecario19; -- se califica como hipotecario...
        ELSIF rcre.cred_hipotecario20 > 0 AND   -- si tiene cr�ditos hipotecario...
              rcre.cred_consumo     > 0 THEN  -- y tiene cr�ditos de consumo...
              Deudas_Hipotecarias_Consumo(pv_empresa, pv_fecha, cli.cod_persona, vconst_moneda_consolid,
                                                      vgaran_real, vmto_hipotecario, vmto_consumo);
           --
           -- analizar si la garant�a real cubre la deuda del cr�dito hipotecario y de consumo...
           IF vgaran_real >= vmto_hipotecario + vmto_consumo THEN
              vtip_cred_s := vconst_tip_cred_hipotecario20; -- se califica como hipotecario...
           ELSE
              vtip_cred_s := vconst_tip_cred_consumo; -- si no, se califica como consumo...
           END IF;
        ELSIF rcre.cred_hipotecario20 > 0 AND   -- si tiene cr�ditos hipotecario...
              rcre.cred_consumo       = 0 THEN  -- y NO tiene cr�ditos de consumo...
              vtip_cred_s := vconst_tip_cred_hipotecario20; -- se califica como hipotecario...
        ELSIF rcre.cred_hipotecario21 > 0 AND   -- si tiene cr�ditos hipotecario...
              rcre.cred_consumo     > 0 THEN  -- y tiene cr�ditos de consumo...
              Deudas_Hipotecarias_Consumo(pv_empresa, pv_fecha, cli.cod_persona, vconst_moneda_consolid,
                                                      vgaran_real, vmto_hipotecario, vmto_consumo);
           --
           -- analizar si la garant�a real cubre la deuda del cr�dito hipotecario y de consumo...
           IF vgaran_real >= vmto_hipotecario + vmto_consumo THEN
              vtip_cred_s := vconst_tip_cred_hipotecario21; -- se califica como hipotecario...
           ELSE
              vtip_cred_s := vconst_tip_cred_consumo; -- si no, se califica como consumo...
           END IF;
        ELSIF rcre.cred_hipotecario21 > 0 AND   -- si tiene cr�ditos hipotecario...
              rcre.cred_consumo       = 0 THEN  -- y NO tiene cr�ditos de consumo...
              vtip_cred_s := vconst_tip_cred_hipotecario21; -- se califica como hipotecario...
        ELSIF rcre.cred_hipotecario9 > 0 AND   -- si tiene cr�ditos hipotecario...
              rcre.cred_consumo     > 0 THEN  -- y tiene cr�ditos de consumo...
              Deudas_Hipotecarias_Consumo(pv_empresa, pv_fecha, cli.cod_persona, vconst_moneda_consolid,
                                                      vgaran_real, vmto_hipotecario, vmto_consumo);
           --
           -- analizar si la garant�a real cubre la deuda del cr�dito hipotecario y de consumo...
           IF vgaran_real >= vmto_hipotecario + vmto_consumo THEN
              vtip_cred_s := vconst_tip_cred_hipotecario9; -- se califica como hipotecario...
           ELSE
              vtip_cred_s := vconst_tip_cred_consumo; -- si no, se califica como consumo...
           END IF;
        ELSIF rcre.cred_hipotecario9 > 0 AND   -- si tiene cr�ditos hipotecario...
              rcre.cred_consumo       = 0 THEN  -- y NO tiene cr�ditos de consumo...
              vtip_cred_s := vconst_tip_cred_hipotecario9; -- se califica como hipotecario...
        -- AQUI
        ELSE
--            vtip_cred_s := vconst_tip_cred_consumo; -- si no, se califica como consumo...
              vtip_cred_s := NULL; -- si no, se califica como lo que es...
        END IF;
/*
        -- seg�n DS 26838: para clientes no comerciales ni hipotecarios de vivienda..analizar
        -- si pueden ser calificados como microcr�ditos con garant�a real...
        IF NVL(vtip_cred_s, vconst_tip_cred_consumo) NOT IN (vconst_tip_cred_comercial, vconst_tip_cred_hipotecario) THEN
           -- analizar el monto de la garant�a real si cubre toda su deuda...
           vgaran_real := Obt_Garantia_Real(pv_empresa, cli.cod_persona, vconst_moneda_consolid, pv_fecha);
           IF vgaran_real >= vdeuda_total THEN
              vtip_cred_s := vconst_tipcred_micro_garreal;
           END IF;
        END IF;
*/

----- SSPM 17/03/2020 (*****)
----- Objetivo:  Determinacion del mayor riesgo,
----- 1.- CE y  M/C y  H entonces  CE
----- 2.- M/C y (H0, H3) y Gh >= Pasivo  entonces H
----- 3.- M/C y (H0, H3) y Gh < Pasivo  entonces  Mayor dias mora
----- 4.- M/C y (H1, H2,H4) entonces  Mayor dias mora
----- 5.- M/C y (H0, H3 ) y (H1,H2,H4)  and Gh >= PAsivo entonces H
----- 6.- M/C y (H0, H3 ) y (H1,H2,H4)  and Gh < PAsivo entonces mayor dias mora
----- 7.- (H0, H3) y (H1,H2,H4) entonces H
----- 7.- (H1,H2,H4) entonces H
----- 7.- (H0, H3) entonces H
----- TABLAS DE CALIFICACION
----EMPRESARIAL         1
----MICROCREDITO        2
----VIVIENDA            5
----AGROPECUAIO         10

    /*SELECT  max(CE) CE, max(MC) MC, max(HGH) HGH, MAX(HSGH) HSGH, MAX(MONTO_SUS) PASIVO, substr(max(DIAS_MORA),1, instr(max(DIAS_MORA),'-')-1) DIAS_MORA, sum(case when cod_sbef in('H0','H3') then MONTO_GAR_SUS else 0 end ) GAR_HGH,
        CASE WHEN max(CE) is not null then 'EMPRESARIAL'
        WHEN max(MC) is not null and max(HGH) is not null and  sum(case when cod_sbef in('H0','H3') then MONTO_GAR_SUS else 0 end ) >=  MAX(MONTO_SUS) then 'VIVIENDA'
        WHEN max(MC) is not null and max(HGH) is not null and  sum(case when cod_sbef in('H0','H3') then MONTO_GAR_SUS else 0 end ) <  MAX(MONTO_SUS) then  (case when substr(max(DIAS_MORA), instr(max(DIAS_MORA),'-')+1, 2) in('M7','M8','M9') then 'AGROPECUARIO' else 'MICRO_CONSUMO' end)-- max(DIAS_MORA)
        WHEN max(MC) is not null and MAX(HSGH) is not null then (case when substr(max(DIAS_MORA), instr(max(DIAS_MORA),'-')+1, 2) in('M7','M8','M9') then 'AGROPECUARIO' else 'MICRO_CONSUMO' end) --  max(DIAS_MORA))
        WHEN max(MC) is not null and max(HGH) is not null and MAX(HSGH) is not null and  sum(case when cod_sbef in('H0','H3') then MONTO_GAR_SUS else 0 end ) >=  MAX(MONTO_SUS) then 'VIVIENDA'
        WHEN max(MC) is not null and max(HGH) is not null and MAX(HSGH) is not null and  sum(case when cod_sbef in('H0','H3') then MONTO_GAR_SUS else 0 end ) <  MAX(MONTO_SUS) then (case when substr(max(DIAS_MORA), instr(max(DIAS_MORA),'-')+1, 2) in('M7','M8','M9') then 'AGROPECUARIO' else 'MICRO_CONSUMO' end)-- max(DIAS_MORA)
        WHEN max(HGH) is not null and MAX(HSGH) is not null then 'VIVIENDA'
        WHEN max(HGH) is not null then 'VIVIENDA'
        WHEN max(HSGH) is not null then 'VIVIENDA'
        end MAYOR_RIESGO  */
     DECLARE
             vl_CE varchar2(30);vl_MC varchar2(30);vl_HGH varchar2(30);vl_HSGH varchar2(30);vl_Pasivo number(18,2);vl_dias_mora varchar2(10);vl_GAR_HGH  number(18,2);
    BEGIN
       vaux_cred_s := vtip_cred_s;
    SELECT  --max(CE) CE, max(MC) MC, max(HGH) HGH, MAX(HSGH) HSGH, MAX(nvl(MONTO_SUS,0)) PASIVO, substr(max(DIAS_MORA),1, instr(max(DIAS_MORA),'-')-1) DIAS_MORA, sum(case when cod_sbef in('H0','H3') then MONTO_GAR_SUS else 0 end ) GAR_HGH,
        /*CASE WHEN max(CE) is not null then '1'
        WHEN max(MC) is not null and max(HGH) is not null and  sum(decode(cod_sbef,'H0',nvl(MONTO_GAR_SUS,0),decode(cod_sbef,'H3',nvl(MONTO_GAR_SUS,0),0))) >=  MAX(nvl(MONTO_SUS,0)) then '5'
        WHEN max(MC) is not null and max(HGH) is not null and  sum(decode(cod_sbef,'H0',nvl(MONTO_GAR_SUS,0),decode(cod_sbef,'H3',nvl(MONTO_GAR_SUS,0),0))) <  MAX(nvl(MONTO_SUS,0)) then  decode(substr(max(DIAS_MORA), instr(max(DIAS_MORA),'-')+1, 2),'M7','10', decode(substr(max(DIAS_MORA), instr(max(DIAS_MORA),'-')+1, 2),'M8','10', decode(substr(max(DIAS_MORA), instr(max(DIAS_MORA),'-')+1, 2),'M9','10','2') ) )  -- max(DIAS_MORA)
        WHEN max(MC) is not null and MAX(HSGH) is not null then decode(substr(max(DIAS_MORA), instr(max(DIAS_MORA),'-')+1, 2),'M7','10', decode(substr(max(DIAS_MORA), instr(max(DIAS_MORA),'-')+1, 2),'M8','10', decode(substr(max(DIAS_MORA), instr(max(DIAS_MORA),'-')+1, 2),'M9','10','2') ) ) --  max(DIAS_MORA))
        WHEN max(MC) is not null and max(HGH) is not null and MAX(HSGH) is not null and  sum(decode(cod_sbef,'H0',nvl(MONTO_GAR_SUS,0),decode(cod_sbef,'H3',nvl(MONTO_GAR_SUS,0),0))) >=  MAX(nvl(MONTO_SUS,0)) then '5'
        WHEN max(MC) is not null and max(HGH) is not null and MAX(HSGH) is not null and  sum(decode(cod_sbef,'H0',nvl(MONTO_GAR_SUS,0),decode(cod_sbef,'H3',nvl(MONTO_GAR_SUS,0),0))) <  MAX(nvl(MONTO_SUS,0)) then decode(substr(max(DIAS_MORA), instr(max(DIAS_MORA),'-')+1, 2),'M7','10', decode(substr(max(DIAS_MORA), instr(max(DIAS_MORA),'-')+1, 2),'M8','10', decode(substr(max(DIAS_MORA), instr(max(DIAS_MORA),'-')+1, 2),'M9','10','2') ) )
        WHEN max(HGH) is not null and MAX(HSGH) is not null then '5'
        WHEN max(HGH) is not null then '5'
        WHEN max(HSGH) is not null then '5'
        WHEN max(MC) is not null then decode(substr(max(DIAS_MORA), instr(max(DIAS_MORA),'-')+1, 2),'M7','10', decode(substr(max(DIAS_MORA), instr(max(DIAS_MORA),'-')+1, 2),'M8','10', decode(substr(max(DIAS_MORA), instr(max(DIAS_MORA),'-')+1, 2),'M9','10','2') ) )
        end MAYOR_RIESGO*/
        --- NUEVA DEFINICION
        --  SSPM 11/08/2021
        --CASE WHEN max(CE) IS NOT NULL THEN '1'
        CASE WHEN max(CE) IS NOT NULL and max(sal_act)>400000 THEN '1'--healvarez--12/2022
            WHEN max(CE) IS NOT NULL and max(sal_act)<=400000 and max(CODIGO_EMPRESA)='5' THEN '2'--healvarez--12/2022
            WHEN max(CE) IS NOT NULL and max(CODIGO_EMPRESA) not in('5') THEN '1'--healvarez--12/2022
        WHEN max(MC) IS NOT NULL AND max(HGH) IS NOT NULL AND  sum(decode(cod_sbef,'H0',nvl(MONTO_GAR_SUS,0),decode(cod_sbef,'H3',nvl(MONTO_GAR_SUS,0),0))) >=  MAX(nvl(MONTO_SUS,0)) THEN '5'
        WHEN max(MC) IS NOT NULL OR  MAX(HGH) IS NOT NULL OR MAX(HSGH) IS NOT NULL THEN decode(substr(max(DIAS_MORA), instr(max(DIAS_MORA),'-')+1, 2),'M7','10', decode(substr(max(DIAS_MORA), instr(max(DIAS_MORA),'-')+1, 2),'M8','10', decode(substr(max(DIAS_MORA), instr(max(DIAS_MORA),'-')+1, 2),'M9','10', decode(substr(max(DIAS_MORA), instr(max(DIAS_MORA),'-')+1, 1),'H','5',   (CASE WHEN substr(max(DIAS_MORA), instr(max(DIAS_MORA),'-')+1, 3) LIKE 'M_D' THEN 30 ELSE 2 END) ) ) )   )  --  max(DIAS_MORA))
        END MAYOR_RIESGO
    INTO  /*vl_CE, vl_MC, vl_HGH,vl_HSGH, vl_Pasivo,vl_dias_mora ,vl_GAR_HGH ,*/  vtip_cred_s
    FROM (
            SELECT round(decode(hiscre.codigo_moneda,1,hiscre.saldo_actual/6.86,2,hiscre.saldo_actual,hiscre.saldo_actual),2) sal_act, --healvarez--12/2022
                   hiscre.CODIGO_EMPRESA,hiscre.NUM_TRAMITE  ,ASFI.COD_SBEF , (CASE WHEN ASFI.COD_SBEF IN ('C0','C3','P0','P5','P6') THEN 'EMPRESARIAL' ELSE NULL END) CE,
                   (CASE WHEN ASFI.COD_SBEF IN ('C1','P1','P2','P3','M0','M1','M2','M3','M4','M5','M6','M7','M8','M9', 'N0','N1','N2','N3' ) THEN 'MICRO_CONSUMO' ELSE NULL END) MC,
                   (CASE WHEN ASFI.COD_SBEF IN ('H0','H3' ) THEN 'VIVIENDA_GH' ELSE NULL END) HGH,
                   --(case when ASFI.COD_SBEF in ('H1','H2','H4') then 'VIVIENDA_SGH' else null end) HSGH
                    decode(ASFI.COD_SBEF,'H1','VIVIENDA_SGH',decode(ASFI.COD_SBEF,'H2','VIVIENDA_SGH',decode(ASFI.COD_SBEF,'H4','VIVIENDA_SGH', NULL ))) HSGH,
                   --(SELECT SUM( Decode(cod_moneda,1, (NVL(saldo_tra,0)+NVL(saldo_cont,0))/vl_cotiz_Sus,4,((NVL(saldo_tra,0)+NVL(saldo_cont,0))*vl_cotiz_UFV)/vl_cotiz_Sus , NVL(saldo_tra,0)+NVL(saldo_cont,0))) mon_operacion  ANTES
                   (SELECT SUM( Decode(cod_moneda,1, (NVL(saldo_tra,0)+nvl(mon_diferido,0)+NVL(saldo_cont,0))/vl_cotiz_Sus,4,((NVL(saldo_tra,0)+nvl(mon_diferido,0)+NVL(saldo_cont,0))*vl_cotiz_UFV)/vl_cotiz_Sus , NVL(saldo_tra,0)+nvl(mon_diferido,0)+NVL(saldo_cont,0))) mon_operacion  -- SSPM 30/05/2020
                    FROM PR_TMP_CALIF_X_CLIENTE c2 WHERE c2.cod_empresa = CRE.CODIGO_EMPRESA AND c2.cod_persona = CRE.CODIGO_CLIENTE ) MONTO_SUS,
                   ( to_char(pv_fecha- nvl(HISCRE.F_ULTIMO_ING_VENCIDO, pv_fecha)) ||'-'|| ASFI.COD_SBEF  || (decode(sign(nvl(DIF.MONTO_CAPITAL_DIF,0)-nvl(DIF.MONTO_PAGADO_CAPITAL_DIF,0)),1,'D','') )   ) dias_mora ,
                    (SELECT-- sum(case when gar.cod_moneda = 1 then  nvl(gar.valor_realizacion,gar.valor_producto)*NVL(gartra.ind_prorrateo,1)/vl_cotiz_Sus
                        --when gar.cod_moneda =4 then  (nvl(valor_realizacion,valor_producto)*NVL(gartra.ind_prorrateo,1)* vl_cotiz_UFV )/vl_cotiz_Sus
                        --else nvl(valor_realizacion,valor_producto)*NVL(gartra.ind_prorrateo,1) end ) monto_gar
                        sum (decode(gar.cod_moneda,1, nvl(gar.valor_realizacion,gar.valor_producto)*NVL(gartra.ind_prorrateo,1)/vl_cotiz_Sus, decode(gar.cod_moneda,4, (nvl(valor_realizacion,valor_producto)*NVL(gartra.ind_prorrateo,1)* vl_cotiz_UFV )/vl_cotiz_Sus, nvl(valor_realizacion,valor_producto)*NVL(gartra.ind_prorrateo,1))))
                        FROM pr_gar_X_tramite_his gartra
                        INNER JOIN pr_hi_garantias gar
                        ON GARTRA.COD_EMPRESA = GAR.COD_EMPRESA AND GARTRA.COD_GARANTIA = GAR.COD_GARANTIA AND GARTRA.FEC_REGISTRO_HI = GAR.FEC_REGISTRO_HI
                        INNER JOIN pr_Grados_X_tip_gar grad
                        ON GRAD.COD_TIP_GARANTIA = GAR.COD_TIP_GARANTIA AND GRAD.CON_DESPLAZAMIENTO = GAR.CON_DESPLAZAMIENTO AND GRAD.ES_HABITACION = GAR.ES_HABITACION AND GRAD.GRADO = GARTRA.GRADO
                        AND GRAD.MNEMONICO IN ('HI1','HO1','HR1')
                        INNER JOIN pr_gravamen grav
                        ON GRAV.COD_EMPRESA = GAR.COD_EMPRESA AND GRAV.COD_GARANTIA = GAR.COD_GARANTIA  AND GRAV.COD_PERSONA = '1100' AND grav.cod_ente_registro = '1235' AND nvl(grav.estado_Gar_perfec,1) = 1
                        WHERE GARTRA.COD_EMPRESA = hiscre.codigo_Empresa AND gartra.num_Tramite =hiscre.num_tramite AND gartra.fec_registro_Hi = pv_fecha
                        ) MONTO_GAR_SUS
            FROM pr_Creditos_hi hiscre
            INNER JOIN pr_creditos cre
            ON HISCRE.CODIGO_EMPRESA = CRE.CODIGO_EMPRESA AND HISCRE.NO_CREDITO = CRE.NO_CREDITO ---AND CRE.CODIGO_CLIENTE=cli.cod_persona  --- SSPM 27/09/2022
            inner join personas_x_tramite_his pertra  --- SSPM 27/09/2022  incluye codeudores.
            on pertra.COD_EMPRESA = cre.CODIGO_EMPRESA and pertra.num_tramite = cre.num_tramite and pertra.FEC_REGISTRO_HI = hiscre.FEC_REGISTRO_HI and pertra.COD_PERSONA= cli.cod_persona
            INNER JOIN pr_tramite tra
            ON TRA.COD_EMPRESA = HISCRE.CODIGO_EMPRESA AND HISCRE.NUM_TRAMITE = TRA.NUM_TRAMITE
            INNER JOIN pr_tip_Credito_super asfi
            ON ASFI.COD_EMPRESA = tra.COD_EMPRESA AND ASFI.COD_TIP_CRED_S = tra.COD_TIP_CRED_S
            LEFT JOIN pr_Creditos_dif_hi dif  --- SSPM  11/08/2021
            ON DIF.COD_EMPRESA = HISCRE.CODIGO_EMPRESA AND DIF.NO_CREDITO = HISCRE.NO_CREDITO AND DIF.FEC_REGISTRO_HI = HISCRE.FEC_REGISTRO_HI
           --WHERE hiscre.cod_empresa = pv_empresa --AND t1.cod_persona = cli.cod_persona
           WHERE ---hiscre.codigo_empresa in ('1','5') --  pv_empresa --- SSPM 19/01/2023
           instr(decode(pv_empresa,'1', '|1|5|','5' ,'|1|5|', pv_empresa), hiscre.codigo_empresa ) >0  --- SSPM
           AND HISCRE.FEC_REGISTRO_HI = pv_fecha
           AND hiscre.estado NOT IN('P')--HEALVAREZ--02/02/2022--Cambios segun lo observado por Riesgos.
      )Q;
     EXCEPTION
         WHEN NO_DATA_FOUND THEN
            pv_error := SQLERRM;
            INSERT INTO pr_operaciones_tmp (sesion, cod_persona, observaciones) VALUES ( 'SSPM54321', cli.cod_persona, pv_error);
            vtip_cred_s := vaux_cred_s;
            pv_error := NULL;
         WHEN OTHERS THEN
             pv_error := SQLERRM;
            INSERT INTO pr_operaciones_tmp (sesion, cod_persona, observaciones) VALUES ( 'SSPM54321', cli.cod_persona, pv_error);
            vtip_cred_s := vaux_cred_s;
            pv_error := NULL;
             --RETURN;
     END;
---- SSPM fin 17/03/2020
        --
            -- ahora empezar a calificar todos los tr�mites de un cliente que no hayan sido calificados anteriormente...
            FOR tra IN cur_tramites(cli.cod_persona) LOOP
                    --
                        vsaldo_deudor := 0;
                        vintereses    := 0;
                        vcod_calif    := NULL;
                        vmotivo       := NULL;
                        vtip_cred_s   := NVL(vtip_cred_s, tra.cod_tip_cred_s);
                        --
            --Se incorpora los diferentes tipos de empresarial
            --JCRS-04-01-2013
            --IF vtip_cred_s = vconst_tip_cred_comercial THEN -- el cliente se debe calificar como comercial ANTERIOR
            --NUEVO JCRS 04-01-2013
            IF vtip_cred_s IN (vconst_tip_cred_comercial,vconst_tip_cred_comercialC2,vconst_tip_cred_comercialC3) THEN -- el cliente se debe calificar como comercial
               -- cliente comercial y la operaci�n est� en ejecuci�n...seg�n 347
               --
               -- seg�n SB/492 si es cliente c0 con al menos una operaci�n en ejecuci�n...
               IF vC0_ejecucion THEN
                  Obt_Saldo_Deudor(pv_empresa,
                                   cli.cod_persona,
                                   pv_fecha,
                                   vconst_moneda_consolid,
                                   vsaldo_deudor,
                                   vintereses,
                                   pv_error);
                                   pv_error := NULL;
                                  --
                  Califica_X_Ejecucion4(pv_empresa,
                                        pv_fecha,
                                        cli.cod_persona,
                                        tra.num_tramite,
                                        tra.cod_moneda,
                                        tra.num_dias_mora,
                                        vSaldo_Deudor,
                                        vIntereses,
                                        vcod_calif,
                                        vmotivo,
                                        pv_error);
               ELSE -- la operaci�n NO est� en ejecuci�n...
                  OPEN cur_califica (vtip_cred_s, tra.num_dias_mora);
                  FETCH cur_califica INTO vcod_calif;
                  CLOSE cur_califica;
               END IF;
            ELSE
               OPEN cur_califica (vtip_cred_s, tra.num_dias_mora);
               FETCH cur_califica INTO vcod_calif;
               CLOSE cur_califica;
               -- por modificacion 23/10/2001 (2) si la operaci�n est� en ejecuci�n m�nimo debe ser calificada con un 3.
               /* Eliminar la calificaci�n m�nima para cr�ditos no comerciales.
                  Basarse en la tabla de calificaci�n por rango de d�as mora
               IF tra.codigo_estado = Pr_Utl_Estados.verif_estado_ejecucion(tra.codigo_estado) THEN
                  IF vcod_calif < 'F' THEN  -- si ha sido ejecutado antes de cumplir con el par�metro de tiempo o tiene gastos judiciales pendientes
                     vcod_calif := 'F';
                             vmotivo    := 'Operaci�n en ejecuci�n';
                      END IF;
               END IF;
               */
            END IF;
            --
            IF NVL(vcod_calif, '0') != '0' THEN
               -- Ultima validaci�n: No calificar A si el cr�dito est� en Vencido...
               IF vcod_calif = 'A' AND tra.codigo_estado = 'V' THEN
                  vcod_calif := 'B';
               END IF;
               -- obtiene el c�digo del tipo de cr�dito seg�n la SBEF...
               OPEN cur_tip_cred_s (vtip_cred_s);
               FETCH cur_tip_cred_s INTO vtip_credito_s;
               CLOSE cur_tip_cred_s;
               --
               -- actualizar la calificaci�n...motivo: d�as de atraso.. para cada tr�mite sin calificar del cliente...
               -- que no hayan sido calificados anteriormente...

                ---- SSPM 12/10/2016 la recalificacion por mora no aplica a C0, C3, P0, P5 y P6  solicitud de Riesgos Fernando ponce y Eric Cerspo
                ---- 09/11/2016 a las operacion con tipo de credito ASFI indicados no debe afectar la calificacion por mora, debe mantener la calificacion anterior o bien asignar A
                --- SSPM 09/11/2016 INPUT califacion mora ,  OUTPUT mantien calificacion mora sino es  C0, C3, P0, P5 y P6 de lo contrario calificacion mes anterior o A

                Pr.PR_RIESGO_TC.ES_CALIF_MANUAL_O_AUTO ( pv_empresa, tra.num_tramite, pv_fecha, vl_es_calif_manual, vcod_calif , pv_error ); --- SSPM 09/11/2016
                IF pv_error IS NOT NULL THEN
                    INSERT INTO pr_operaciones_tmp (sesion, num_tramite, observaciones) VALUES ('PREV'||TO_CHAR(pv_fecha,'ddmmyyyy'),  tra.num_tramite, pv_error );
                    pv_error := NULL;
                END IF;
                ---- fin SSPM 12/10/2016
               Act_Calificacion_Tmp(pv_empresa, tra.num_tramite, cli.cod_persona, vcod_calif, NVL(vmotivo,'Por Dias de Mora (' || vtip_credito_s || ')'), NULL, vdeuda_total, vtip_cred_s, pv_error, tra.ROWID);
                           --
               IF pv_error IS NOT NULL THEN
                  RAISE etermina;
               END IF;
               Contador_Commit;
            END IF;
        END LOOP;
    END LOOP;
    --
    Realiza_Commit;
    --
    EXCEPTION
       WHEN etermina THEN
                NULL;
           WHEN OTHERS THEN
                RAISE;
  END Califica_X_Mora;
  --
  PROCEDURE Califica_x_Reprogramacion (pv_empresa     IN VARCHAR2,
                                       pFecha IN DATE,
                                       pv_error   IN OUT VARCHAR2) IS
    /* Autor: HJimenez
           Fecha: 24/07/2007
                         Seg�n requerimiento de Evaluaci�n y Calificaci�n de Cartera (ELUNA, con copia a HSEJAS y JPARADA).
                                         "Se solicita implementar una funcionalidad que realice la verificaci�n del numero de
                                         reprogramaciones en el proceso de calificaci�n de cartera, que se realiza  de forma mensual,
                                         seg�n los par�metros establecidos, adem�s el tiempo qu� se tomar�a en realizar
                                         este requerimiento o en volver  ha activar la funcionalidad  de recalificaci�n por numero
                                         de reprogramaci�n, que exist�a en la anterior norma"
                                         Los par�metros son:
                                         --
Cr�ditos Hipotecario de Vivienda:
                 3 Reprogramaciones = Categor�a B
                 4 Reprogramaciones = Categor�a D
                 5 Reprogramaciones = Categor�a F
                 6 Reprogramaciones = Categor�a H
Cr�ditos de Consumo y Microcr�dito:
                 3 Reprogramaciones = Categor�a D
                 4 Reprogramaciones = Categor�a F
                 5 Reprogramaciones = Categor�a H
    */
    -- cursor con las operaciones que han sido reprogramadas y su n�mero de veces...
    CURSOR cur_tramite IS
      SELECT A.ROWID, A.num_tramite, A.cod_calif, A.tip_cred_calif, COUNT('s') no_reprog, A.cod_tip_cred_s
            FROM PR_TMP_CALIF_X_CLIENTE A, PR_REPROGRAMACIONES b
              WHERE A.cod_empresa = pv_empresa
            AND A.codigo_estado NOT IN (Pr_Utl_Estados.Verif_Estado_Castigado(A.codigo_estado)) -- no incluir operaciones castigadas...
                    AND b.cod_empresa = A.cod_empresa
                    AND b.num_tramite = A.num_tramite
    GROUP BY A.ROWID, A.num_tramite, A.cod_calif, A.tip_cred_calif, A.cod_tip_cred_s
    ORDER BY A.num_tramite;
    --
    -- cursor que retornala calificaci�n seg�n el n�mero de reprogramaciones...
    CURSOR Cur_Calif (ptip_cred_s IN NUMBER,
                                                p_reprog IN NUMBER) IS
      SELECT cod_calif
         FROM PR_RAN_CALIF
          WHERE cod_empresa = '1'
                    AND cod_tip_cred_s = ptip_cred_s
                    AND (cant_reprogra  = p_reprog
                        OR cant_reprogra  < p_reprog)
                        ORDER BY cod_calif DESC;
    --
    vcalif  PR_RAN_CALIF.Cod_Calif%TYPE;
    vreprog NUMBER(4);
  BEGIN
    pv_error := NULL;
    -- calificar tr�mites por reprogramaci�n...
    FOR tra IN cur_tramite LOOP
        IF NVL(tra.no_reprog, 0) > 0 THEN  -- si tiene, calificar a los clientes en el tr�mite seg�n el n�mero de reprogramaciones del mismo...
               -- obtener la calificaci�n...
            vCalif := NULL;
           OPEN cur_calif(tra.tip_cred_calif, tra.no_reprog);
           FETCH cur_calif INTO vcalif;
           CLOSE Cur_Calif;
           IF tra.tip_cred_calif IS NULL THEN
              tra.tip_cred_calif := tra.cod_tip_cred_s;
           END IF;
           --
           IF NVL(vcalif, '0') > '0' THEN
              -- actualizar la calificaci�n...motivo reprogracion.. para cada uno de los clientes en el tr�mite..
              -- que no hayan sido calificados por un ente externo...
             IF vCalif > tra.cod_calif THEN
                  --Act_Calificacion_Tmp(pv_empresa, tra.num_tramite, NULL, vcalif, 'Por n�mero de reprogramaciones', tra.no_reprog, NULL, NULL, pv_error, tra.ROWID);
                  Act_Calificacion_Tmp(pv_empresa, tra.num_tramite, NULL, vcalif, 'Por n�mero de reprogramaciones', tra.no_reprog, NULL, tra.tip_cred_calif, pv_error, tra.ROWID);
                  IF pv_error IS NOT NULL THEN
                       EXIT;
                  END IF;
                                  Contador_Commit;
             END IF;
                   END IF;
        END IF;
    END LOOP;
    IF pv_error IS NULL THEN
       Realiza_Commit;
    END IF;
    --
  END Califica_x_Reprogramacion;
  --
  PROCEDURE Califica_Op_Cliente ( p_cod_empresa    IN     VARCHAR2,
                                  p_fecha          IN     DATE,
                                  p_cod_error      IN OUT VARCHAR2) IS
    /* Autor: HJimenez
       Prop�sito:  Invocar a los procedimientos de calificaci�n aumtom�tica de cartera.
                       Esta calificaci�n incluye los siguientes aspectos:
                   1. Califica con la peor calificaci�n posible a los incobrables.
                   2. Calificaci�n por n�mero de reprogramaciones de operacioens. Mediana Prioridad.
                                      Se califican las operaciones y los clientes relacionados seg�n el n�mero de reprogramaciones
                                          que estas posean.
                   3. Calificaci�n por d�as de atraso.  M�nima Prioridad
                                      Los clientes que no han sido calificados por un ente externo, por el n�mero de reprogramaciones,
                                          entonces deber�n ser calificados por los d�as de atraso de sus operaciones.  Reglas adicionales para
                                          calificar por este concepto se encuentran en el procedimiento respectivo.
       Fecha: 18/04/2001
           --
           Autor: HJimenez
           Fecha: 24/07/2007
           Prop.: Calificar por reprogramaci�n las operaciones de cr�ditos hipotecarios y de consumo seg�n
           aprobaci�n del Directorio de Julio 2007.
    */
    --
    --
    vl_calif_x_repro VARCHAR2(5); ---- RUSARAVIA

  BEGIN
    p_cod_error := NULL;
    -- primero califica operaciones incobrables con la peor posible...
    -- BITACORA: controlar duracion Califica_X_Incobrable
    BEGIN
       vproc_bit := TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS');
       INSERT INTO PR_BIT_CALIFPROCS (num_proceso, ini_proceso, ind_proceso)
       VALUES (vproc_bit, SYSDATE, 8);
      --
      EXCEPTION
         WHEN OTHERS THEN
              ROLLBACK; RAISE_APPLICATION_ERROR('-20500', 'Error bitacora insert 8' || SQLERRM);
    END;
    --
    Califica_X_Incobrable(p_cod_empresa,
                          p_cod_error);
    --
    IF p_cod_error IS NULL THEN
       -- BITACORA: actualizar duracion Califica_X_Incobrable
       BEGIN
         UPDATE PR_BIT_CALIFPROCS SET fin_proceso = SYSDATE WHERE num_proceso = vproc_bit;
         --
         EXCEPTION
            WHEN OTHERS THEN
                 ROLLBACK; RAISE_APPLICATION_ERROR('-20500', 'Error bitacora UPDATE 8' || SQLERRM);
       END;
       --
       -- BITACORA: controlar duracion Califica_X_Mora
       BEGIN
         vproc_bit := TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS');
         INSERT INTO PR_BIT_CALIFPROCS (num_proceso, ini_proceso, ind_proceso)
         VALUES (vproc_bit, SYSDATE, 9);
         --
         EXCEPTION
            WHEN OTHERS THEN
                 ROLLBACK; RAISE_APPLICATION_ERROR('-20500', 'Error bitacora insert 9' || SQLERRM);
       END;
       --
       Califica_X_Mora(p_cod_empresa,
                       p_fecha,
                       p_cod_error);
       -- BITACORA: actualizar duracion Califica_X_Mora
       BEGIN
         UPDATE PR_BIT_CALIFPROCS SET fin_proceso = SYSDATE WHERE num_proceso = vproc_bit;
         --
         EXCEPTION
            WHEN OTHERS THEN
                 ROLLBACK; RAISE_APPLICATION_ERROR('-20500', 'Error bitacora UPDATE 9' || SQLERRM);
       END;
           /* Autor: HJimenez
               Fecha: 25/07/2007
                   Prop.: Invocar al procedimiento Califica_X_Reprogramaci�n, de acuerdo a las nuevas pol�ticas de reprogramaci�n
                               introducidas en Julio/2007.
      */

      /*/RUSARAVIA se realiza la calificacion por el numero de reprogramaciones de acuerdo a parametro x empresa*/
      BEGIN
        SELECT VALOR
        INTO vl_calif_x_repro
        FROM PARAMETROS_X_EMPRESA
        WHERE COD_EMPRESA=p_cod_empresa
        AND COD_SISTEMA='PR'
        AND abrev_parametro='CALIFICA_X_REPRO';
      EXCEPTION WHEN OTHERS THEN
        vl_calif_x_repro:='S';
      END;

       IF p_cod_error IS NULL  AND vl_calif_x_repro ='S' THEN
           Califica_X_Reprogramacion(p_cod_empresa, p_fecha, p_cod_error);
       END IF;
    END IF;
  END;
  --
  --
  PROCEDURE Actualiza_Calif_Tramite (pv_empresa IN VARCHAR2,
                                     pv_error   IN OUT VARCHAR2) IS
    /* Autor: HJimenez
       Fecha:19/04/2001
           Prop�sito: Actualizar la calificaci�n de los tr�mites que tengan m�s de un deudor y que sus calificaciones
                      sean diferentes.  En este caso, la calificaci�n ser� la peor es decir la mayor.
    */
  -- buscar la mayor calificaci�n para los tr�mites que tiene m�s de un deudor.
  CURSOR cur_act IS
    SELECT A.num_tramite, MAX(NVL(A.cod_calif,0)) calif
          FROM PR_TMP_CALIF_X_CLIENTE A
            WHERE A.cod_empresa = pv_empresa
                  AND 1 < (SELECT COUNT('s')
                             FROM PR_TMP_CALIF_X_CLIENTE b
                                           WHERE b.cod_empresa = A.cod_empresa
                                             AND b.num_tramite = A.num_tramite)
        GROUP BY A.num_tramite;
  BEGIN
    FOR act IN cur_act LOOP
        UPDATE PR_TMP_CALIF_X_CLIENTE
           SET cod_calif = act.calif,
               motivo    = 'Por actualizaci�n de peor calificaci�n'
             WHERE cod_empresa = pv_empresa
               AND num_tramite = act.num_tramite;
        Contador_Commit;
    END LOOP;
    Realiza_Commit;
    --
    EXCEPTION
       WHEN OTHERS THEN
            mnj_errores.fijar_error('002145', 'PR', SQLERRM, UPPER('Actualiza_Calif_Tramite'),
                                    NULL, 'OTHERS');
            pv_error := '002145';
  END Actualiza_Calif_Tramite;
  --
  --
  PROCEDURE Calificacion (p_cod_empresa      IN VARCHAR2,
                          p_fecha            IN DATE    ,
                          P_Ind_Revisa_Calif IN VARCHAR2,
                          p_califica         IN VARCHAR2,
                                                  p_cod_error     IN OUT VARCHAR2)IS
    /* Autor: HJimenez
       Prop�sito:  Seleccionar el tipo de operaci�n y las operaciones v�lidas que ser�n calificadas
                       en este proceso.  Todas estas operaciones ser�n insertadas en una tabla temporal
                   PR_TMP_CALIF_X_CLIENTE con los datos necesarios para los procesos de calificaci�n.
                   La calificaci�n por tr�mite se actualizar� en esta tabla.
       Fecha: 20/04/2001
           -----------------
           Modificaci�n: HJimenez
                  Fecha: 05/07/2001
          Prop�sito: Por medio de cajeros autom�ticos a cualquier hora puede entrar sobregiros, pero estos
                             no han sido procesados por el cierre diario de cuentas de efectivo antes de la calificaci�n.
                                         Por eso, todas las operaciones de sobregiros se leer�n de PR_HIS_TRAMITE a la fecha de proceso.
       -----------------
       Modificacion: HJimenez
              Fecha: 05/09/2003
          Prop�sito: Precalificacion:
                     Se debe considerar solo las operaciones que han tenido movimiento
                     en un rango de fechas.
                     Insertar el resto de operaciones de un cliente.
       --
       Modificacion: JCRS
              Fecha: 26-01-2011
          Proposito: Para ejecutar la calificacion x producto
    */
    --
    -- Cursor operaciones "vivas" de clientes , l�neas no se califican
    -- Tomar los tramites de todos los tipos de operacion del historico...
    --
    CURSOR c_operaciones IS
          SELECT tra.cod_tip_operacion, tpr.cod_tip_cred_s, tra.num_tramite,
             tra.cod_tip_producto,  tra.codigo_estado , tra.codigo_origen, tra.cod_moneda
        FROM PR_HIS_TRAMITE tra, PR_TIP_PRODUCTO tpr
          WHERE tra.cod_empresa       = p_cod_empresa
            AND tra.fec_registro_hi   = p_fecha
            --tramite para pruebas
            ---AND tra.num_tramite IN (1163599,3121869,3838575,3804175,3757319,3635366)--HEALVAREZ-12/2017-QUITAR.! SOLO PARA PRUEBA.!
            --
            AND tra.cod_tip_operacion NOT IN ( 122 )  -- no se califican l�neas de cr�dito
            --AND tra.cod_tip_producto  NOT IN ( 942, 21, 275, 278, 648 )  -- no se califican multicreditos pasivos...deudas del banco con otras instituciones financieras...
            AND tra.ind_enviar_super  = 'S'
            AND tra.codigo_estado     = Pr_Utl_Estados.Verif_Estado_Act_Cast (Tra.Codigo_Estado)
            AND tpr.cod_empresa       = tra.cod_empresa
            AND tpr.cod_tip_operacion = tra.cod_tip_operacion
            AND tpr.cod_tip_producto  = tra.cod_tip_producto
            AND tpr.IND_CALIFICA      = 'S';
    --
    vnum_operacion VARCHAR2(30);
    vmon_operacion NUMBER(18,2);
    vsaldo         NUMBER(18,2);
    vsaldo_cont    NUMBER(18,2);
    vsaldo_venc    NUMBER(18,2);
    vint_dev       NUMBER(18,2);
    vdias_mora     NUMBER(18,2);
    vplazo_dias    NUMBER(6) := 0;
    vsaldo_dif      NUMBER(18,2);
  BEGIN
    p_cod_error := NULL;
    BEGIN
      SELECT MAX(cod_calif)
        INTO vconst_califpeor
          FROM PR_CALIFICACION;
          --
      EXCEPTION
        WHEN OTHERS THEN
             p_cod_error:='Error al obtener la calificacion';
             RETURN;
    END;
    -- BITACORA: controlar duracion del borrado...
    BEGIN
       vproc_bit := TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS');
       INSERT INTO PR_BIT_CALIFPROCS (num_proceso, ini_proceso, ind_proceso)
       VALUES (vproc_bit, SYSDATE, 6);
      --
      EXCEPTION
         WHEN OTHERS THEN
              ROLLBACK; RAISE_APPLICATION_ERROR('-20500', 'Error bitacora insert 6' || SQLERRM);
    END;
    -- borrar calificaciones anteriores en el temporal...que no sean de crediagil porque fueron subidas
    -- antes de generar este proceso...
    BEGIN
      DELETE PR_TMP_CALIF_X_CLIENTE
            WHERE cod_empresa = p_cod_empresa
              AND ind_crediagil != 'S';
      --
          Realiza_Commit;
          --
      EXCEPTION
        WHEN OTHERS THEN
             p_cod_error:='Error al borrar registros antiguos del temporal';
             RETURN;
    END;
    --
    -- BITACORA: actualizar duracion del borrado...
    BEGIN
       UPDATE PR_BIT_CALIFPROCS SET fin_proceso = SYSDATE WHERE num_proceso = vproc_bit;
      --
      EXCEPTION
         WHEN OTHERS THEN
              ROLLBACK; RAISE_APPLICATION_ERROR('-20500', 'Error bitacora UPDATE 6' || SQLERRM);
    END;
    --
    vconst_Cont_Commit := 0;
    -- BITACORA: controlar duracion de la insercion de datos...
    BEGIN
       vproc_bit := TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS');
       INSERT INTO PR_BIT_CALIFPROCS (num_proceso, ini_proceso, ind_proceso)
       VALUES (vproc_bit, SYSDATE, 7);
      --
      EXCEPTION
         WHEN OTHERS THEN
              ROLLBACK; RAISE_APPLICATION_ERROR('-20500', 'Error bitacora insert 7' || SQLERRM);
    END;
    -- primero insertar en el temporal de calificaciones todos los clientes con operaciones vivas
    FOR f_operaciones IN c_operaciones LOOP
        -- obtenemos el saldo del tr�mite, los intereses devengados y los d�as de mora...entre otros..
        Obt_Datos_Tramite(p_cod_empresa, p_fecha, f_operaciones.num_tramite,
                          f_operaciones.cod_tip_operacion, f_operaciones.cod_tip_producto,
                          f_operaciones.codigo_origen, f_operaciones.codigo_estado,
                          vnum_operacion, vmon_operacion, vsaldo, vsaldo_cont, vsaldo_venc, vint_dev, vdias_mora, vplazo_dias, p_cod_error);
        IF p_cod_error IS NOT NULL THEN
           EXIT;
        END IF;
        --
        BEGIN  --- SSPM 30/05720202 incorporacion de saldo diferido
            SELECT HI.SALDO_CAPITAL_DIF INTO vsaldo_dif
            FROM pr.pr_creditos_dif_hi hi
            WHERE cod_empresa = p_cod_empresa AND num_tramite=f_operaciones.num_tramite AND fec_registro_hi = p_fecha ;
        EXCEPTION
            WHEN no_data_found THEN
                 vsaldo_dif := 0;
           WHEN others THEN
                p_cod_error := SQLERRM;
                RETURN;
        END;

        Ins_Tmp_Calif_X_Cliente (p_cod_empresa,
                                 p_fecha,
                                 f_operaciones.num_tramite,
                                 f_operaciones.cod_tip_cred_s,
                                 f_operaciones.cod_moneda,
                                 f_operaciones.codigo_estado,
                                 vmon_operacion,
                                 vsaldo,
                                 vsaldo_dif,  --- SSPM 30/05/2020
                                 vsaldo_cont,
                                 vsaldo_venc,
                                 vint_dev,
                                 vdias_mora,
                                 vnum_operacion,
                                                                 vplazo_dias,
                                 p_cod_error);
        IF p_cod_error IS NOT NULL THEN
           EXIT;
        END IF;
        Contador_Commit;
    END LOOP; -- for f_operaciones in c_operaciones (Reg_Tip_Ope.Cod_Tip_Operacion)
    --
    -- BITACORA: actualizar duracion de la carga de datos...
    BEGIN
       UPDATE PR_BIT_CALIFPROCS SET fin_proceso = SYSDATE WHERE num_proceso = vproc_bit;
      --
      EXCEPTION
         WHEN OTHERS THEN
              ROLLBACK; RAISE_APPLICATION_ERROR('-20500', 'Error bitacora UPDATE 7' || SQLERRM);
    END;
    IF p_cod_error IS NULL THEN
       -- calificar las operaciones de los clientes...
       Califica_Op_Cliente (p_cod_empresa,
                            p_fecha,
                            p_cod_error);
       --
    END IF;
  END Calificacion;
  --
  --
  PROCEDURE Act_Calif_X_Tramite(pv_empresa  IN VARCHAR2,
                                pv_fecha    IN DATE,
                                                                pv_proceso  IN NUMBER,
                                                                pv_persona  IN VARCHAR2,
                                p_cod_error IN OUT VARCHAR2) IS
    /* Autor: HJimenez
       Fecha: 23/04/2001
       Prop�sito:  Esta nueva versi�n (al parecer definitiva) de Act_Calif_X_Tramite, requiere que se corra primero
                       Act_Calif_X_Cliente, para que existan calificaciones unificadas por clientes.
                   Arma un cursor de todos los tr�mites con sus clientes y recupera la calificaci�n por cliente.
                   Si un tr�mite tiene varios deudores le pone la calificaci�n del peor deudor.
                   El efecto general es que todos los tr�mites de un cliente ser�n calificados con su peor calificaci�n.
       Modificaci�n: 30/05/2001
                     No se insertan en la tabla PR_HIS_CALIF_X_PR_TRAMITE las operaciones de CREDIAGIL
       Modificacion: 04/09/2003
                     La calificacion del tr�mite la determina la m�xima calificacion del deudor prinicipal de este...
                     Ya no se consideran codeudores para calificar...
    */
    CURSOR cur_tramite IS
      --SELECT b.num_tramite  , a.cod_persona, b.codigo_estado, b.saldo_cont, b.saldo_tra,
      SELECT b.num_tramite  , A.cod_persona, b.codigo_estado, b.saldo_cont, b.saldo_tra, nvl(B.MON_DIFERIDO,0) MON_DIFERIDO,
                 b.saldo_venc   , A.cod_calif, A.mot_calif, A.tip_calif, b.cod_moneda,
             b.num_dias_mora, b.tip_cred_calif, b.int_deveng, b.num_operacion, b.plazo_dias
        FROM PR_CALIF_X_CLIENTE A, PR_TMP_CALIF_X_CLIENTE b
          WHERE A.cod_empresa   = pv_empresa
            AND A.cod_persona   = NVL(pv_persona, A.cod_persona)
            AND A.fec_calif     = TRUNC(pv_fecha)
                        AND b.cod_empresa   = A.cod_empresa
                        AND b.cod_persona   = A.cod_persona
            AND b.ind_titular   = 'S'
                        AND b.ind_crediagil = 'N'
      ORDER BY b.num_tramite;
    --
    vtramite    PR_TRAMITE.num_tramite%TYPE := NULL;
    rtra_aux    cur_tramite%ROWTYPE;
    vpeor_aux   PR_CALIFICACION.cod_calif%TYPE;
    vpeor_calif PR_CALIFICACION.cod_calif%TYPE := 'A';
    vcalif_ente PR_CALIFICACION.cod_calif%TYPE;
    vmotivo     PR_HIS_CALIF_X_PR_TRAMITE.mot_calif%TYPE;
    vente       PR_ENTES_CALIFICACION.abr_ente_calif%TYPE;
        v_califica_adicional PR_CALIFICACION.cod_calif%TYPE;
  BEGIN
    --
    FOR tra IN cur_tramite LOOP
        IF NVL(vtramite, 0) != tra.num_tramite THEN -- estamos cambiando de tr�mite...
           -- insertar la calificaci�n de la peor calificaci�n del tramite anterior...
           IF vtramite IS NOT NULL THEN -- ya fue asignado un valor a la variable en una iteraci�n anterior...
              -- insertar los datos guardados en la iteraci�n anterior...
                          BEGIN
                INSERT INTO PR_HIS_CALIF_X_PR_TRAMITE
                  (cod_empresa   , num_tramite    , num_proceso  , codigo_estado_tra,
                   cod_calif     , por_prevision  , mon_prevision, mon_pre_sin_def,
                   mon_pre_contin, mon_contingente, sal_operacion, sal_venc,
                                   mon_prevision_venc,
                   tip_calif     , adicionado_por , fec_adicion,   mot_calif, cod_moneda,
                   ind_garantia  , mon_garantia   , num_dias_mora, tip_cred_calif,
                                   int_deveng    , num_operacion, plazo_dias, mon_pre_adicional, cod_calif_adicional, mon_diferido ) --- SSPM 30/05/2020
                  VALUES
                  (pv_empresa   , vtramite            , pv_proceso            , rtra_aux.codigo_estado,
                   vpeor_calif  , 0                   , 0                     , 0,
                   0            , rtra_aux.saldo_cont , rtra_aux.saldo_tra    , rtra_aux.saldo_venc,
                                   0            ,
                   rtra_aux.tip_calif, USER           , SYSDATE               , vmotivo, rtra_aux.cod_moneda,
                   'O'          , 0                   , rtra_aux.num_dias_mora, rtra_aux.tip_cred_calif,
                                   rtra_aux.int_deveng, rtra_aux.num_operacion, rtra_aux.plazo_dias,0, v_califica_adicional, rtra_aux.mon_diferido );  --SSPM 30/05/2020
                                EXCEPTION
                                   WHEN DUP_VAL_ON_INDEX THEN
                                        UPDATE PR_HIS_CALIF_X_PR_TRAMITE
                                                   SET codigo_estado_tra = rtra_aux.codigo_estado,
                               mon_contingente   = rtra_aux.saldo_cont,
                               sal_operacion     = rtra_aux.saldo_tra,
                               mon_diferido      = rtra_aux.mon_diferido,  --- SSPM 30/04/2020
                               sal_venc          = rtra_aux.saldo_venc,
                               cod_calif         = vpeor_calif,
                                                       mot_calif         = vmotivo,
                                                           tip_calif         = rtra_aux.tip_calif,
                               cod_moneda        = rtra_aux.cod_Moneda,
                               num_dias_mora     = rtra_aux.num_dias_mora,
                               tip_cred_calif    = rtra_aux.tip_cred_calif,
                                                           int_deveng        = rtra_aux.int_deveng,
                                                           num_operacion     = rtra_aux.num_operacion,
                                                           plazo_dias        = rtra_aux.plazo_dias
                                                         WHERE cod_empresa = pv_empresa
                                                           AND num_tramite = vtramite
                                                           AND num_proceso = pv_proceso;
                   WHEN OTHERS THEN
                                        RAISE;
                          END;
              --
              Contador_Commit;
           END IF;
           -- inicializar la peor calificaci�n...
           vpeor_calif := 'A';
           vmotivo     := NULL;
           -- es un nuevo tramite...
           vtramite := tra.num_tramite;
           -- salvamos el registro actual...con los datos del tramite...
           rtra_aux := tra;
           -- Obtiene calificacion adicional impuesta x SBEF que es practicamente fija
           -- JCRS- 12-06-2008
           v_califica_adicional := Obt_Calificacion_adicional(pv_empresa,tra.num_tramite,p_cod_error);
        END IF;
        --
        IF tra.cod_calif >= vpeor_calif THEN
           vpeor_calif := tra.cod_calif; -- guardar la peor calificaci�n hasta el momento..
           vmotivo     := tra.mot_calif; -- se guarda el motivo de calificaci�n del tr�mite...
        END IF;
    END LOOP;
    --
    IF vtramite IS NOT NULL THEN -- ya fue asignado un valor a la variable en una iteraci�n anterior...
       -- insertar los datos guardados en la iteraci�n anterior...
           BEGIN
         INSERT INTO PR_HIS_CALIF_X_PR_TRAMITE
           (cod_empresa,    num_tramite,        codigo_estado_tra, num_proceso,
            cod_calif,      por_prevision,      mon_prevision,     mon_pre_sin_def,
            mon_pre_contin, mon_contingente,    sal_operacion,     sal_venc,
            mon_prevision_venc,
            tip_calif,      adicionado_por,     fec_adicion,       mot_calif, cod_moneda,
            ind_garantia,   mon_garantia,       num_dias_mora,     tip_cred_calif,
                        int_deveng  ,   num_operacion, plazo_dias, mon_pre_adicional, cod_calif_adicional, mon_diferido)  --- SSPM 30/05/2020
           VALUES
            (pv_empresa   , vtramite            , rtra_aux.codigo_estado, pv_proceso,
             vpeor_calif  , 0                   , 0                     , 0,
             0            , rtra_aux.saldo_cont , rtra_aux.saldo_tra    , rtra_aux.saldo_venc,
                         0            ,
             rtra_aux.tip_calif, USER           , SYSDATE               , vmotivo, rtra_aux.cod_moneda,
             'O'          , 0                   , rtra_aux.num_dias_mora, rtra_aux.tip_cred_calif,
                         rtra_aux.int_deveng, rtra_aux.num_operacion, rtra_aux.plazo_dias, 0, v_califica_adicional, rtra_aux.mon_diferido); -- SSPM 30/05/2020
         EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN
                 UPDATE PR_HIS_CALIF_X_PR_TRAMITE
                    SET codigo_estado_tra = rtra_aux.codigo_estado,
                        mon_contingente   = rtra_aux.saldo_cont,
                        sal_operacion     = rtra_aux.saldo_tra,
                        mon_diferido      = rtra_aux.mon_diferido, --- SSPM 30/05/2020
                        sal_venc          = rtra_aux.saldo_venc,
                        cod_calif         = vpeor_calif,
                        mot_calif         = vmotivo,
                        tip_calif         = rtra_aux.tip_calif,
                        cod_moneda        = rtra_aux.cod_Moneda,
                        num_dias_mora     = rtra_aux.num_dias_mora,
                        tip_cred_calif    = rtra_aux.tip_cred_calif,
                                                int_deveng        = rtra_aux.int_deveng,
                        num_operacion     = rtra_aux.num_operacion,
                                                plazo_dias        = rtra_aux.plazo_dias
                      WHERE cod_empresa = pv_empresa
                        AND num_tramite = vtramite
                        AND num_proceso = pv_proceso;
            WHEN OTHERS THEN
                             RAISE;
       END;
       --
    END IF;
    Realiza_Commit;
    --
    EXCEPTION
       WHEN OTHERS THEN
            mnj_errores.fijar_error('002140', 'PR', SQLERRM, UPPER('Act_Calif_X_Tramite') || 'Tramite: ' || vtramite,
                                    NULL, 'OTHERS');
            p_cod_error := '002140';
  END Act_Calif_X_Tramite;
  --
  --
  PROCEDURE Act_Calif_X_Tramite_Cliente(pv_empresa  IN VARCHAR2,
                                        pv_fecha    IN DATE,
                                        pv_proceso  IN NUMBER,
                                        pv_persona  IN VARCHAR2,
                                        p_cod_error IN OUT VARCHAR2) IS
    /* Autor: JCarlosRamirez
       Fecha: 22/01/2014
       Prop�sito:  Actualizamos la calificacion del cliente en base a la nueva circular 217/2014 Asfi que indica
                   que todos los cliente empresariales y pyme que cuando exista discrepancia en mas de una categoria
                   entre la calificacion otorgada por el Banco y la otorgada por otra entidades del sistema financiero
                   en categoria de mayor riesgo a la asignada x el Busa, en estos casos el sistema de asumir la calificacion
                   y prevision de mayor riesgo.
    */
    CURSOR cur_tramite IS
      SELECT b.num_tramite  , A.cod_persona, b.codigo_estado, b.saldo_cont, b.saldo_tra,
             b.saldo_venc   , A.cod_calif, A.mot_calif, A.tip_calif, b.cod_moneda,
             b.num_dias_mora, b.tip_cred_calif, b.int_deveng, b.num_operacion, b.plazo_dias,
             NVL(c.prioridad,0)prioridad
        FROM PR_CALIF_X_CLIENTE A, PR_TMP_CALIF_X_CLIENTE b, PR_CALIFICACION c
       WHERE A.cod_empresa   = pv_empresa
         AND A.cod_persona   = NVL(pv_persona, A.cod_persona)
         AND A.fec_calif     = TRUNC(pv_fecha)
         --
         AND b.cod_empresa   = A.cod_empresa
         AND b.cod_persona   = A.cod_persona
         AND b.ind_titular   = 'S'
         AND b.ind_crediagil = 'N'
         AND b.tip_cred_calif IN (vconst_tip_cred_comercial,vconst_tip_cred_pyme,vconst_tip_cred_pymeP5,vconst_tip_cred_pymeP6) --Solo Creditos Empresariales y Pymes
         --
         AND c.cod_calif = A.cod_calif
      ORDER BY A.cod_persona, b.num_tramite;
    --
    vtramite    PR_TRAMITE.num_tramite%TYPE := NULL;
    rtra_aux    cur_tramite%ROWTYPE;
    vpeor_aux   PR_CALIFICACION.cod_calif%TYPE;
    vpeor_calif PR_CALIFICACION.cod_calif%TYPE := 'A';
    vcalif_ente PR_CALIFICACION.cod_calif%TYPE;
    vmotivo     PR_HIS_CALIF_X_PR_TRAMITE.mot_calif%TYPE;
    vente       PR_ENTES_CALIFICACION.abr_ente_calif%TYPE;
    v_califica_adicional PR_CALIFICACION.cod_calif%TYPE;
    vcod_calif  PR_CALIFICACION.cod_calif%TYPE;
    vprioridad       NUMBER(2);
    vl_tipo_credito  VARCHAR2(10);
    vl_error         VARCHAR2(500);
    vl_reclasifica   VARCHAR2(5);
  BEGIN
    --
    FOR tra IN cur_tramite LOOP

    vl_reclasifica:='S';
    /*
    RUSARAVIA 19/09/2016
    De acuerdo a las condificiones no se hace la reclasificacion */
    PR.PR_RIESGO_TC.TIPO_CREDITO_ASFI_CLIENTE ( pv_empresa       ,
                                                tra.NUM_TRAMITE,
                                                pv_fecha,
                                                vl_tipo_credito  ,
                                                vl_error         );
    BEGIN
    SELECT 'N'
    INTO vl_reclasifica
    FROM PARAM_DINAM
    WHERE TP1COD=pv_empresa
    AND TP1COD1=134
    AND TP1DESC1=vl_tipo_credito;
    EXCEPTION WHEN OTHERS THEN
    vl_reclasifica:='S';

    END;
    /*--------------------------------------------------------------------*/
    --HEALVAREZ-12/2017 - No permitir el cambio de calificaci�n por contagio externo, segun FFR.
        vl_reclasifica:='N';
    /*--------------------------------------------------------------------*/

      IF vl_reclasifica='S' THEN
        vcod_calif := tra.cod_calif;
        --evaluamos calificacion en el sistema financiero
        SELECT MAX(SUBSTR(cod_calif,1,1))
          INTO vcod_calif
          FROM pr_his_deu_sbef A
         WHERE A.cod_persona = tra.cod_persona
           --and a.fec_carga <= pv_fecha
           AND A.cod_calif IS NOT NULL
           AND A.cod_financiera NOT IN ('1') --Otras Entidades y no Banco Union
           AND A.fec_carga IN (SELECT MAX(b.fec_carga)
                               FROM pr_his_deu_sbef b
                              WHERE b.cod_persona = A.cod_persona);
        --Obtenemos la prioridad
        BEGIN
          SELECT NVL(prioridad,0)
            INTO vprioridad
            FROM pr_calificacion
           WHERE cod_calif = SUBSTR(vcod_calif,1,1);
        EXCEPTION
          WHEN others THEN
            vprioridad := tra.prioridad;
        END;
        --ya tenemos las 2 calificaciones y las prioridades
        IF NVL(vcod_calif,tra.cod_calif) > tra.cod_calif THEN
           IF (vprioridad - tra.prioridad) > 1 THEN --discrepancia en mas de una categoria
              --asumimos la mayor calificacion
              UPDATE pr_his_calif_x_pr_tramite
                 set cod_calif = vcod_calif
               WHERE num_tramite = tra.num_tramite
                 AND cod_empresa = pv_empresa
                 AND num_proceso = pv_proceso;
              --
              UPDATE pr_calif_x_cliente
                 set cod_calif = vcod_calif
                WHERE cod_empresa = pv_empresa
                  AND cod_persona = tra.cod_persona
                  AND fec_calif = pv_fecha;
           --Para pruebas
           INSERT INTO pr_operaciones_tmp
           (sesion,
           num_tramite,
           cod_persona,
           observaciones2,
           observaciones3,
           cod_tip_operacion,
           cod_tip_credito,
           no_credito,
           fec_primer_desembolso)
           VALUES
           ('CALIF',
            tra.num_tramite,
            tra.cod_persona,
            tra.cod_calif,
            vcod_calif,
            tra.prioridad,
            vprioridad,
            pv_proceso,
            pv_fecha
           );
           END IF;
        END IF;
        END IF;--end rusaravia

        /*-------------------------------------------------*/
        --HEALVAREZ-01/2018 - Cambio para contagio interno.
        --pr.pr_calif_contagio_interno( pv_empresa, tra.cod_persona, pv_fecha);
        /*-------------------------------------------------*/

    END LOOP;



    /*------------------------------------------------------------------------------------------------------*/
    --HEALVAREZ-01/2018 - Cambio para contagio interno.
    DECLARE
        vl_conteo_cli_calif NUMBER(10):=0;
    BEGIN

        /*DELETE FROM pr.pr_operaciones_tmp
        WHERE SESION=SUBSTR('CALIFXCLI'||USER,1,15) AND FEC_PRIMER_DESEMBOLSO/*FECHA PROCESO*//*=pv_fecha;*/

        NULL;  --- NO ESTA  CORRECTAMENTE DEFINIDO 30/03/2020

        /*

        FOR tramites_procs IN (
                            SELECT DISTINCT(a.cod_persona)
                            FROM PR_CALIF_X_CLIENTE a INNER JOIN PR_TMP_CALIF_X_CLIENTE b
                            ON b.cod_empresa   = a.cod_empresa
                             AND b.cod_persona   = a.cod_persona AND a.cod_empresa=pv_empresa AND b.cod_empresa=pv_empresa
                            WHERE  a.fec_calif     = pv_fecha
                             AND b.ind_titular   = 'S'
                             AND b.ind_crediagil = 'N'
                             AND a.cod_persona=NVL(NULL,a.cod_persona)
                            )
          LOOP

                -------------------------------------------------
                --HEALVAREZ-01/2018 - Cambio para contagio interno.

--                SELECT COUNT(1)
--                    INTO vl_conteo_cli_calif
--                FROM PR_OPERACIONES_TMP
--                WHERE SESION=SUBSTR('CALIFXCLI'||USER,1,15) AND cod_persona=tramites_procs.cod_persona;--AND observaciones2 empresa =pv_empresa

--                IF vl_conteo_cli_calif=0 THEN

                    ---pr.pr_calif_contagio_interno(pv_empresa, tramites_procs.cod_persona, pv_fecha); --- SSPM 30/03/2020
                    null;

--                    INSERT INTO PR.PR_OPERACIONES_TMP
--                    (SESION, observaciones2, cod_persona)  -- empresa
--                    SELECT SUBSTR('CALIFXCLI'||USER,1,15),pv_empresa,tramites_procs.cod_persona
--                    FROM DUAL;

--                END IF;

                -------------------------------------------------

          END LOOP;
          */ ---  FIN SSPM
     EXCEPTION
    WHEN OTHERS THEN
        p_cod_error := 'Ocurrio un error en proceso de contagio interno '||SQLERRM;
    END;
    /*------------------------------------------------------------------------------------------------------*/


    --
    Realiza_Commit;
    --
  EXCEPTION
    WHEN OTHERS THEN
       mnj_errores.fijar_error('002140', 'PR', SQLERRM, UPPER('Act_Calif_X_Tramite_Cliente') || 'Tramite: ' || vtramite,
                                NULL, 'OTHERS');
       p_cod_error := '002140';
  END Act_Calif_X_Tramite_Cliente;
  --
  --
  FUNCTION Obt_Peor_Calif(pv_calif1 IN VARCHAR2,
                          pv_calif2 IN VARCHAR2) RETURN VARCHAR2 IS
    /* Autor: HJimenez
           Fecha: 04/05/2001
           Prop�sito:  Esta funci�n evalua dos calificaciones y determina cual es la peor
                       Si las dos son iguales retorna retorna su valor.
        */
        vcalif1 PR_CALIFICACION.cod_calif%TYPE;
        vcalif2 PR_CALIFICACION.cod_calif%TYPE;
        vpeor   PR_CALIFICACION.cod_calif%TYPE;
  BEGIN
    vcalif1 := NVL(pv_calif1, 0);
        vcalif2 := NVL(pv_calif2, 0);
    IF vcalif1 > vcalif2 THEN
           vpeor := vcalif1;
        ELSIF vcalif1 < vcalif2 THEN
           vpeor := vcalif2;
        ELSE
           vpeor := vcalif1;
        END IF;
        --
    RETURN vpeor;
  END Obt_Peor_Calif;
  --
  --
  PROCEDURE Act_Calif_X_Cliente(pv_empresa   IN VARCHAR2,
                                pv_fecha     IN DATE,
                                pv_cod_error IN OUT VARCHAR2) IS
    /* Autor: HJimenez
       Fecha: 25/04/2001
           Prop�sito:  Este procedimiento se encarga de crear una calificaci�n �nica para un cliente en la
                       tabla PR_CALIF_X_CLIENTE y para ello toma la calificaci�n m�s alta del proceso de calificaci�n
                   autom�tica.
                       Si hay varias operaciones del mismo cliente con la calificaci�n m�s alta o peor, se toma los datos de
                                   la operaci�n unicamente.
       Modificaci�n: 03/05/2001
                         Se recupera por cliente, su calificaci�n de ente calificador si esta existe y se utiliza
                     como calificaci�n m�nima es decir s�lo se puede empeorar, jam�s mejorar.
       Modificaci�n: 23/10/2001
                         Por orden la SBEF, no se congelan las calificaciones generadas del sistema cuando la deuda total
                                         del cliente es inferior a $35000, es decir puede calificarse con una mejor calificaci�n que la otorgada
                                         por un ente calificador.
                                         Ejemplo:
                                         SBEF:              4
                                         Calif. Autom�tica: 3
                                         Deuda Cliente:     28,000.
                                         Calif Final:       3
       Modificaci�n: 18/04/2002
                         (1) Por requerimiento de LRevollar, Evaluaci�n y Calificaci�n de Cartera.
                         "Ning�n cliente comercial con desembolso mayor a 35 mil podr� bajar
                                         de calificaci�n sin previo an�lisis del departamento.
                                         Es para todos los clientes, incluso los calificados 2.
                     El cliente se queda con la calificaci�n obtenida hasta ese momento,
                                         es decir si el ciente ha ido subiendo su calificaci�n
                                         progresivamente de 1 a 2 a 3 a 4 y luego reprograma su operaci�n,
                                         entonces este se queda con 4 hasta que el �rea le asigne una
                                         nueva calificaci�n"
                                         (2) Por requerimiento de LRevollar de Evaluaci�n y Calificaci�n de Cartera:
                                         "Art�culo 14� - Por su naturaleza los cr�ditos hipotecarios de vivienda ser�n
                                         calificados fundamentalmente en funci�n a la morosidad en el servicio de las cuotas
                                         pactadas y la formalizaci�n de sus garant�as de acuerdo a ley:....."
                     Entonces si este cliente tuviera una calificaci�n por ente, no
                                         importa tal calificaci�n, por que se calcula de acuerdo a los d�as
                                         mora.
       Modificacion: 27/05/2003
                     Debido a la carta circular SB/330/2003 donde se establece que en la
                     Central de Riesgos se distingue como 1A al deudor principal y como 1B al codeudor, se
                     modifica este proceso para que la calificaci�n por cliente sea igual a la peor
                     calificaci�n de sus operaciones donde sea codeudor principal.
                     Si el cliente no tienen operaciones como titular igual se califica.
       --
       Modificacion: 04/05/2006
                     A requerimiento de HSEJAS, anular la validaci�n de la modificacion (2) del 18/04/2002.
                     De: Henrry Sejas Lazarte
                     Enviado el: Jueves, 04 de Mayo de 2006 03:07 p.m.
                     Para: Herman Jimenez
                     CC: Eduardo Lunabarrera; Alvaro Dorado Sanchez
                     Asunto: RE: Modificaci�n de previsi�n constituida al 30.04.06
La normativa actual en Secci�n 9, Articulo 1� del Titulo V, Anexo 1, instruye lo siguiente:
Art�culo 2� - Prohibiciones.- Las EIFs no podr�n:
1. Conceder nuevos cr�ditos ni recibir la garant�a de personas: (i) calificadas en categor�a H,
(ii) que tengan cr�ditos castigados por insolvencia o (iii) que mantengan cr�ditos en
ejecuci�n con alguna EIF, en tanto no regularicen dichas operaciones. Las operaciones
reprogramadas que no impliquen la concesi�n de nuevos cr�ditos no ser�n consideradas
como nuevas operaciones de cr�dito1.
La EIF que otorgue cr�ditos incumpliendo lo dispuesto en el p�rrafo anterior deber� calificar
el endeudamiento total del prestatario en la categor�a H, constituir la previsi�n del cien por
cien (100%) y no podr� contabilizar como ingresos los intereses, comisiones y otros
productos devengados.
Por tal motivo, considero que se debe activar esta condici�n en los programas de calificaci�n para todos los tipos de cr�dito, cuando se trate de esta prohibici�n o cuando sea calificado por Ente SBEF
       --
           Modificacion: 23/05/2006
       De: Henrry Sejas Lazarte
       Enviado el: Lunes, 22 de Mayo de 2006 02:43 p.m.
       Para: Herman Jimenez
       Asunto: RE: CLIENTE RECALIFICADOS BALANCE DE MEDIO MES
       El ente 8 � SB494 fue creado con un objetivo especifico que fue la reclasificaci�n de cartera por la nueva norma. Este no es el caso de la calificaci�n por prohibici�n de la norma, aunque la prelaci�n deber�a ser la misma. Sugiero que exista un ente espec�fico para los casos de prohibici�n.
           --
           Modificacion: 06/06/2006
           Seg�n requerimiento de HSEJAS.
           Si el cliente es NO comercial, solo se debe tener la opci�n del ente PROHIB, los dem�s entes no se deben considerar en calificaciones autom�ticas. Es decir cuando un cliente es calificado de acuerdo al criterio de los cr�ditos autom�ticos, la morosidad determina la categor�a de riesgo, salvo que este calificado por ente PROHIB, lo cual significa que cayo en las prohibiciones de la norma y el mismo permanece hasta que se extinga la deuda.
   */
    --
    CURSOR cur_calif IS
      SELECT DISTINCT A.cod_empresa, A.cod_persona, A.cod_calif, A.motivo, A.deuda_total, A.tip_cred_calif
        FROM PR_TMP_CALIF_X_CLIENTE A
          WHERE A.cod_empresa = pv_empresa
            AND A.cod_calif   = (SELECT MAX(b.cod_calif)
                                   FROM PR_TMP_CALIF_X_CLIENTE b
                                     WHERE b.cod_empresa = pv_empresa
                                       AND b.cod_persona = A.cod_persona
                                       AND (b.ind_titular = 'S' -- evaluar primero donde es titular...
                                        OR  b.ind_titular = 'N'))  -- si no, donde sea codeudor porque debe tener calificacion...

      ORDER BY 1, 2, 4 DESC;
    --
    vpersona   personas.cod_persona%TYPE := NULL;
    vcalif     PR_CALIFICACION.cod_calif%TYPE;
        vcalant    PR_CALIFICACION.cod_calif%TYPE;
    vmotivo    PR_CALIF_X_CLIENTE.mot_calif%TYPE;
    vente      PR_ENTES_CALIFICACION.abr_ente_calif%TYPE;
    vtip_calif PR_CALIF_X_CLIENTE.tip_calif%TYPE;
    --
    vdeuda_total NUMBER(18,2);
    verror       VARCHAR2(200) := NULL;
    vente_fere   PR_ENTES_CALIFICACION.cod_ente_calif%TYPE;
    vfec_ente    DATE;
    vl_es_manual    VARCHAR2(2); ---- SSPM 31/10/2019

  BEGIN
    FOR cal IN cur_calif LOOP
        IF NVL(vpersona, '0') != cal.cod_persona THEN
           vcalif       := NULL; vente  := NULL; vcalant    := NULL;
           vdeuda_total := NULL; verror := NULL; vtip_calif := 'A';
           --
           BEGIN
             -- verificar si tengo la deuda total del cliente...
             IF NVL(cal.deuda_total, 0) = 0 THEN  -- si no ha sido calculada, calcularla...
                Obt_Deuda_Total_Cliente(pv_empresa, cal.cod_persona, pv_fecha,
                                        vconst_moneda_consolid, vdeuda_total, verror);
                IF verror IS NOT NULL THEN
                   vdeuda_total := 0;
                END IF;
             ELSE
                vdeuda_total := cal.deuda_total;
             END IF;
             -- (2) Si el cliente no es comercial, no se eval�a su calificaci�n por ente...
             -- 04/05/2006 Anular la validaci�n anterior...
             --- SSPM 27/05/2020

            /*      select max('S') es_manual  into vl_es_manual
                  from pr_tramite tra
                  inner join personas_x_pr_tramite pertra
                  on TRA.COD_EMPRESA = PERTRA.COD_EMPRESA and TRA.NUM_TRAMITE = PERTRA.NUM_TRAMITE
                  inner join pr_tip_Credito_super  asfi
                  on TRA.COD_EMPRESA = ASFI.COD_EMPRESA and TRA.COD_TIP_CRED_S = ASFI.COD_TIP_CRED_S and ASFI.COD_SBEF in ('C0','C3','P0','P5','P6')
                  where tra.cod_empresa = pv_empresa and PERTRA.COD_PERSONA = cal.cod_persona and tra.codigo_estado in ('D','E','V','J');
                            */

                            SELECT max('S')  INTO  vl_es_manual
                        FROM pr_tramite tra
              INNER JOIN personas_x_pr_tramite pertra
               ON TRA.COD_EMPRESA = PERTRA.COD_EMPRESA AND TRA.NUM_TRAMITE = PERTRA.NUM_TRAMITE
                        INNER JOIN pr_tip_credito_super asfi
                        ON TRA.COD_EMPRESA = ASFI.COD_EMPRESA AND TRA.COD_TIP_CRED_S = ASFI.COD_TIP_CRED_S
                        WHERE tra.cod_empresa = pv_empresa AND pertra.cod_persona  =cal.cod_persona AND tra.codigo_estado IN ('D','E','V','J')
                        AND EXISTS (
                                            SELECT 1 FROM  param_dinam p1
                                            INNER JOIN param_dinam_adic p2
                                            ON P1.TP1COD = P2.TP1COD AND P1.TP1COD1 = P2.TP1COD1 AND P1.TP1CORR1 = P2.TP1CORR1 AND P1.TP1CORR2 = P2.TP1CORR2
                                            WHERE p1.tp1cod1 = 320  AND P1.TP1DESC1 = 'N' -- and  tp1sql7 --like '%99999%'--AND  tp1sql4 =  '
                                            AND ASFI.COD_SBEF = p2.tp1sql4  );

             --- no existe calificacion manual cuando cuando es dias mora.
             --- SSPM 27/06/2020  solo aceptamos calificacion fija si es manual o mayor a $us 400,000
             IF  nvl(vl_es_manual,'N') = 'S' THEN
                    Obt_Calif_Entes_Calif_his(pv_empresa, cal.cod_persona, pv_fecha, vcalif, vfec_ente, vente);
             END IF;
             --Aumentado JCRS-047/2010 circular
             IF vente IS NOT NULL THEN -- Ya no debe jalar estas calificaciones ya q no existen mas
                IF vcalif IN ('G','H') THEN
                   vcalif    := NULL;
                   vfec_ente := NULL;
                   vente     := NULL;
                END IF;
             END IF;
             --IF NVL(cal.tip_cred_calif, vconst_tip_cred_consumo) != vconst_tip_cred_comercial THEN
             --NUEVO TIPO DE CREDITO AGROPECUARIO - JCRS-04-01-2013
             IF NVL(cal.tip_cred_calif, vconst_tip_cred_consumo)
                NOT IN (vconst_tip_cred_comercial,vconst_tip_cred_comercialC2,vconst_tip_cred_comercialC3,vconst_tip_cred_pyme,vconst_tip_cred_pymeP5,vconst_tip_cred_pymeP6) THEN
                -- si no es comercial solo la calificacion del ente PROHIB puede prevalecer...
                IF vente NOT IN (cente_prohibiciones)  THEN
                   vcalif    := NULL;
                   vfec_ente := NULL;
                   vente     := NULL;
                END IF;
             END IF;
             -- solo si la calificacion de sus operaciones es peor a la del ente calificador, esta es v�lida...
             IF vente IN (cente_calif_fijo, cente_prohibiciones, cEnte_Com_Ejecutivo, cente_calif_asfi047)  THEN  -- hay calificaci�n del ente fijador...
                /* Autor: HJimenez
                   Fecha: 25/05/2005
                   Prop.: Fijar la calificaci�n de un cliente por medio del ente calificacion 8.
                   Solic: HSEJAS
                  Favor crear un nuevo ente calificador en el Sistema de Prestamos/Riesgo/Procesos/Calificaci�n Autom�tica/Calificaci�n por Ente: C�digo 8. RECLASIFICACION SB 494
                */
                vmotivo := 'Calificaci�n fijada por ente ' || vente;
             ELSE

                    --- VERIFICAR EL TIPO DE CREDITO ASFI para aplicar la peor calificacion
                    --- SSPM  31/10/2019
                    --- Solicitud de Subgerente de Riesgo Crediticio (CEYZARGUIRR)
                    --- esta solucion fue trasladado hacia arriba para mejor control y optimizacion
                  /*select max('S') es_manual  into vl_es_manual
                  from pr_tramite tra
                  inner join personas_x_pr_tramite pertra
                  on TRA.COD_EMPRESA = PERTRA.COD_EMPRESA and TRA.NUM_TRAMITE = PERTRA.NUM_TRAMITE
                  inner join pr_tip_Credito_super  asfi
                  on TRA.COD_EMPRESA = ASFI.COD_EMPRESA and TRA.COD_TIP_CRED_S = ASFI.COD_TIP_CRED_S and ASFI.COD_SBEF in ('C0','C3','P0','P5','P6')
                  where tra.cod_empresa = pv_empresa and PERTRA.COD_PERSONA = cal.cod_persona and tra.codigo_estado in ('D','E','V','J');*/

                IF cal.cod_calif > NVL(vcalif, '0') AND nvl(vl_es_manual,'N') = 'N' THEN  --- SSPM 31/10/2019
                   vcalif  := cal.cod_calif;
                   vmotivo := cal.motivo;
                ELSE  -- si manda la calificaci�n del ente entonces..verificar el total de la deuda del cliente...
                   IF vdeuda_total <= VConst_MontoComercial THEN -- puede mejorar la calificaci�n
                      vcalif := cal.cod_calif;
                      vmotivo := cal.motivo;
                   --ELSIF vdeuda_total <= vconst_tip_cred_pyme THEN -- puede mejorar la calificaci�n
                   --   vcalif := cal.cod_calif;
                   --   vmotivo := cal.motivo;
                   ELSE -- si no, dejar la calificaci�n del ente
                      vmotivo := 'Por calificaci�n ente: ' || vente;
                   END IF;
                END IF;
                IF  cal.cod_calif > NVL(vcalif, '0') AND vcalif IS NULL THEN ---- SSPM 21/11/2019 si y solo si la vcalif es nulo y se debe asignar calificacion
                   vcalif  := cal.cod_calif;
                   vmotivo := cal.motivo;
                END IF;

             END IF;
                     -- (1)
                     -- una vez obtenida la calificaci�n autom�tica...verificar si esta se graba
                     -- o se congela con la calificaci�n del mes anterior...
                     --Se aumenta para incluir a pyme circular 047/2010 JCRS-17-09-2010
                     --IF cal.tip_cred_calif = vconst_tip_cred_comercial AND
                         IF cal.tip_cred_calif IN (vconst_tip_cred_comercial,vconst_tip_cred_comercialC2,vconst_tip_cred_comercialC3, vconst_tip_cred_pyme,vconst_tip_cred_pymeP5,vconst_tip_cred_pymeP6) AND
                            (vdeuda_total > VConst_MontoComercial) AND
                                NVL(vente, '0')    NOT IN (cente_calif_fijo, cente_prohibiciones, cEnte_Com_Ejecutivo, cente_calif_asfi047) THEN
                                /* Autor: HJimenez
                                   Fecha: 23/05/2005
                                   Proposito: Omitir congelaci�n para el mes de Mayo/2005 de los clientes calificados por ente CRC.
                                   HSEJAS: Por tratarse este mes de mayo el primer mes con el cual
                                   vamos a aplicar la nueva tabla de calificaciones literales,
                                   considero que no hay inconveniente en mantener la calificaci�n de
                                   los clientes comerciales asignada por el Comit�, la que se carga en
                                   bloque al sistema. significa que no se debe considerar el proceso de
                                   congelamiento de la calificaci�n que hace una comparaci�n con la
                                   anterior categor�a de riesgo.
                */
                                IF vMotivo LIKE 'Por calificaci�n ente: ' || 'CRC' AND
                                   TO_CHAR(pv_fecha, 'YYYYMM') = '200505' THEN
                                   NULL;
                                ELSE
                                   -- fue calificado como comercial con deuda total mayor a 50000
                                   -- obtener la �ltima calificaci�n v�lida de ese cliente...
                                   DECLARE
                                     CURSOR cur_calant IS
                                           SELECT A.cod_calif
                                             FROM PR_CALIF_X_CLIENTE A
                                            WHERE A.cod_empresa = pv_empresa
                                              AND A.cod_persona = cal.cod_persona
                                              AND A.fec_calif   = (SELECT MAX(b.fec_ult_calificacion)
                                                                            FROM PR_PROVISIONES b
                                                                                      WHERE b.cod_empresa = pv_empresa
                                                                                                        AND b.fec_ult_calificacion < pv_fecha
                                                        AND b.provisionado = 'S');
                                     BEGIN
                                        OPEN cur_calant;
                                       FETCH cur_calant INTO vcalant;
                                       CLOSE cur_calant;
                                     END;
                                   --
                                   --Aumentado JCRS - 047/2010 cicular
                                   IF vcalant IN ('G','H') THEN --Si tiene estas calificaciones debe hacerlo x automatica
                                      vcalant := vcalif;
                                   END IF;
                                   IF NVL(Mapea_Calif_Actual(vcalant), 'A') > vcalif THEN
                                      -- se congela la calificaci�n anterior...
                                      vmotivo    := 'Cliente C0, Deuda > ' || VConst_MontoComercial || ' Calif. Anterior: ' || vcalant || '( ' || Mapea_Calif_Actual(vcalant) || ' ) ' || ' Calif. Automatica: ' || vcalif;
                                      vcalif     := Mapea_Calif_Actual(vcalant);
                                      --vtip_calif := 'R';
                                      --Modificado por JCR- 047/2010 circular
                                      vtip_calif := 'M';
                                   END IF;
                                END IF;
             END IF;
                         --
             INSERT INTO PR_CALIF_X_CLIENTE
               (cod_empresa, cod_persona, fec_calif, cod_calif, mot_calif,
                            adicionado_por, fec_adicion, modificado_por, fec_modificacion, tip_calif)
               VALUES
               (cal.cod_empresa, cal.cod_persona, TRUNC(pv_fecha), vcalif, vmotivo,
                            USER, SYSDATE, NULL, NULL, vtip_calif);
             --
             EXCEPTION
                WHEN DUP_VAL_ON_INDEX THEN
                     BEGIN
                       UPDATE PR_CALIF_X_CLIENTE
                          SET cod_calif = vcalif,
                              mot_calif = vmotivo,
                              tip_calif = vtip_calif,
                              modificado_por = USER,
                              fec_modificacion = SYSDATE
                            WHERE cod_empresa = cal.cod_empresa
                              AND cod_persona = cal.cod_persona
                              AND fec_calif   = TRUNC(pv_fecha);
                        --
                                            EXCEPTION
                                               WHEN OTHERS THEN
                                                        RAISE;
                     END;
                                WHEN OTHERS THEN
                                     RAISE;
           END;
           vpersona := cal.cod_persona;
           Contador_Commit;
        END IF;
    END LOOP;
    Realiza_Commit;
    --
    EXCEPTION
       WHEN OTHERS THEN
            mnj_errores.fijar_error('002140', 'PR', SQLERRM, UPPER('Act_Calif_X_Cliente') || 'Cliente: ' || vpersona,
                                    NULL, 'OTHERS');
            pv_cod_error := '002140';
    --
  END Act_Calif_X_Cliente;
  --
  --
  FUNCTION Proceso_Calif (pv_empresa      IN VARCHAR2,
                          pv_fecha        IN DATE     DEFAULT NULL,
                                                  pv_previsionado IN VARCHAR2 DEFAULT NULL) RETURN NUMBER IS
    /* Autor:  HJimenez
           Fecha:  03/05/2001
           Prop�sito:  Retornar el n�mero del �ltimo proceso de calificaci�n corrido.
                       Actualmente, este n�mero es el mismo n�mero de proceso de previsi�n generado
                                   al correr el proceso de calificaci�n autom�tica.
        */
        CURSOR cur_prevision IS
          SELECT MAX(num_proceso)
            FROM PR_PROVISIONES
                  WHERE cod_empresa = pv_empresa
                    AND fec_ult_calificacion <= NVL(pv_fecha, fec_ult_calificacion)
                        AND provisionado          = NVL(pv_previsionado, provisionado);
        vnum_proceso NUMBER(10);
        vmensaje_err VARCHAR2(500);
  BEGIN
    OPEN cur_prevision;
        FETCH cur_prevision INTO vnum_proceso;
        CLOSE cur_prevision;
        -- no se utiliza el procedimiento obt_ultima_prevision porque este busca el �ltimo
        -- proceso con indicador de prevsionado en 'S' y actualmente el proceso de calificaci�n est� separado
        -- del proceso de previsi�n..
        /*
    -- retorna el �ltimo proceso generado que tenga el indicador S.
    pr_utl2.Obt_Ultima_Prevision (pv_empresa, vnum_proceso, vmensaje_err);
        IF vmensaje_err IS NOT NULL THEN
           vnum_proceso := 0;
    END IF;
        */
        --
        RETURN NVL(vnum_proceso,0);

  END Proceso_Calif;
  --
  --
  FUNCTION Obt_Calif_X_Cliente(pv_empresa IN VARCHAR2,
                               pv_cliente IN VARCHAR2,
                                                           pv_fecha   IN DATE DEFAULT NULL) RETURN VARCHAR2 IS
    /* Autor:  HJimenez
           Fecha:  25/04/2001
           Prop�sito:  Retorna la �ltima calificaci�n generada para un cliente.
           Modificaci�n:  Caso especial:  Un cliente puede tener una l�nea de cr�dito aperturada (estado P) y
                          no tener operaciones con calificaci�n, ya sea porque no tiene m�s operaciones o porque
                      sus otras operaciones est�n canceladas o tenga uno de estos estados:
                                          R - A - X - N - H - O - S - M
                                          Entonces por tener la l�nea de cr�dito aperturada debe retornar la calificaci�n 1 por defecto.
       Modificaci�n: 15/04/2002
                         Riesgo pide que si modifican la calificaci�n por ente despu�s del �ltimo
                                         proceso v�lido de calificaci�n, entonces sea esta primera la que se muestre
                                         como calificaci�n del cliente siempre y cuando sea peor a la del proceso
                                         autom�tico.
       Modificaci�n: 18/06/2002.  Por conversaci�n con LREVOLLAR, si anula de la modificaci�n del
                         15/04/2002 que la calificaci�n por ente sea peor a la automatica.
                                         Si es mejor igual se muestra la del ente.
       Modificacion: 12/07/2007. Se adiciono el c�digo para que busque la calificacion del cliente en la
                         empresa BDP, sino estaba devolviendo H, JLDS.
        */
        CURSOR cur_ult_calif(pEmpresa IN VARCHAR2) IS
          SELECT MAX(fec_ult_calificacion)
            FROM PR_PROVISIONES
                  WHERE cod_empresa  = pEmpresa
                    AND fec_ult_calificacion <= NVL(pv_fecha,fec_ult_calificacion)
                    AND provisionado = 'S';
    --
        CURSOR cur_calif (pEmpresa IN VARCHAR2, p_fecha IN DATE) IS
          SELECT cod_calif
            FROM PR_CALIF_X_CLIENTE
                  WHERE cod_empresa = pEmpresa
                    AND cod_persona = pv_cliente
                        AND fec_calif   = p_fecha
      ORDER BY fec_calif DESC;
    --
        CURSOR cur_linea IS
          SELECT 'A' -- calificaci�n por defecto para un l�nea...
            FROM PERSONAS_X_PR_TRAMITE A, PR_TRAMITE b
                  WHERE A.cod_empresa = pv_empresa
                    AND A.cod_persona = pv_cliente
                        AND b.cod_empresa = A.cod_empresa
                        AND b.num_tramite = A.num_tramite
                        AND b.codigo_estado = 'P'; -- l�nea de cr�dito aperturada..
        --
        vfec_calif  DATE := NULL;
        vfecha      DATE := NULL;
        vcod_calif  PR_CALIF_X_CLIENTE.cod_calif%TYPE := NULL;
        vexito      BOOLEAN;
        --
    vemp_fideicomiso VARCHAR2(5);
    vMensajeError    VARCHAR2(200);
        vemp_BDP         VARCHAR2(5);
        vemp_MLF         VARCHAR2(5);
        vemp_MDP         VARCHAR2(5);
BEGIN
   --
   Pr_Utl.parametro_general ( 'COD_EMPRESA_BDP',
                                  'PR'             ,
                                                          vemp_BDP         ,
                              vMensajeError    );
   --
   Pr_Utl.parametro_general ( 'COD_EMPRESA_MLF',
                                  'PR'             ,
                                                          vemp_MLF         ,
                              vMensajeError    );
   --
   Pr_Utl.parametro_general ( 'COD_EMPRESA_MDP',
                                  'PR'             ,
                                                          vemp_MDP         ,
                              vMensajeError    );
   --
    --IF pv_empresa = cempresa_busa OR pv_empresa = vemp_BDP OR pv_empresa = vemp_MLF OR pv_empresa = vemp_MDP  THEN
    --IF pv_empresa = cempresa_busa OR pv_empresa = vemp_BDP OR pv_empresa = vemp_MLF OR pv_empresa = vemp_MDP  OR pv_empresa IN (8,9) THEN --- SSPM 14/03/2017
    --IF pv_empresa = cempresa_busa OR pv_empresa = vemp_BDP OR pv_empresa = vemp_MLF OR pv_empresa = vemp_MDP  OR pv_empresa IN (8,9,11) THEN --- SSPM 12/06/2023
    IF pv_empresa = cempresa_busa OR pv_empresa = vemp_BDP OR pv_empresa = vemp_MLF OR pv_empresa = vemp_MDP  OR pv_empresa IN (8,9,11,10) THEN --- vespejo-emp10-11/01/2024 adecuacion empresa 10
    OPEN cur_ult_calif(pv_empresa);
    FETCH cur_ult_calif INTO vfecha;
    CLOSE cur_ult_calif;
    --
    OPEN cur_calif(pv_empresa, vfecha);
        FETCH cur_calif INTO vcod_calif;
        vexito := cur_calif%FOUND;
        CLOSE cur_calif;
        --
        IF NOT(vexito) THEN
       -- verificar si el cliente tiene l�neas de cr�dito aperturadas...
           -- suficiente con que encuentre al menos una l�nea...
           OPEN cur_linea;
           FETCH cur_linea INTO vcod_calif;
           CLOSE cur_linea;
        END IF;
        --
    -- si la fecha de consulta es mayor a la fecha de ultima calificaci�n
        -- se consulta la calificaci�n por ente...
        DECLARE
      CURSOR cur_ult IS
        SELECT MAX(fec_ult_calificacion)
          FROM PR_PROVISIONES
            WHERE cod_empresa  = pv_empresa
              AND provisionado = 'S';
       --
       vult_calif DATE;
       vcal_ente  PR_TMP_CALIF_X_CLIENTE.cod_calif%TYPE;
       vfec_ente  DATE;
       vente      VARCHAR2(200);
    BEGIN
          OPEN cur_ult;
      FETCH cur_ult INTO vult_calif;
      CLOSE cur_ult;
      IF NVL(pv_fecha, vult_calif + 1) > vult_calif THEN
         -- se consulta despu�s de efectuada la �ltima calificaci�n...
         -- obtener calificaci�n por ente...
         Obt_Calif_Entes_Calif(pv_empresa, pv_cliente, vcal_ente, vfec_ente, vente);
         IF vfec_ente > vult_calif THEN
            vcod_calif := vcal_ente;
         END IF;
          END IF;
    END;
        --
        RETURN NVL(vcod_calif, 'A');  -- si no encontr� calificaci�n, retorna 1 por defecto...
        --
        ELSE
           Pr_Utl.parametro_general('COD_CARTERA_COBRAR1',
                                    'CJ',
                                                                vemp_fideicomiso,
                                vMensajeError);
       IF pv_empresa = vemp_fideicomiso THEN
          OPEN cur_ult_calif(cempresa_busa);
          FETCH cur_ult_calif INTO vfecha;
          CLOSE cur_ult_calif;
          --
          OPEN cur_calif(cempresa_busa, vfecha);
          FETCH cur_calif INTO vcod_calif;
          vexito := cur_calif%FOUND;
          CLOSE cur_calif;
          --
          IF vexito THEN
             RETURN vcod_calif;
                  ELSE
                 RETURN cpeor_calif;
          END IF;
           END IF;
        END IF;
  END Obt_Calif_X_Cliente;
  --
  --
  FUNCTION Obt_Calif_x_Tramite (pv_empresa IN VARCHAR2,
                                pv_tramite IN NUMBER,
                                                                pv_fecha   IN DATE DEFAULT NULL) RETURN VARCHAR2 IS
    /* Autor: HJimenez
           Fecha: 25/04/2001
           Proposito:  Obtiene la �ltima calificaci�n generada por operaci�n.
                       NO interesa si ha sido previsionada o no.
    */
        CURSOR cur_calif (p_proceso IN NUMBER) IS
          SELECT cod_calif
            FROM PR_HIS_CALIF_X_PR_TRAMITE
           WHERE cod_empresa = pv_empresa
             AND num_tramite = pv_tramite
                 AND num_proceso = p_proceso;
    --
        CURSOR cur_hist IS
          SELECT num_proceso
            FROM PR_PROVISIONES
                  WHERE cod_empresa  = pv_empresa
                    AND fec_ult_calificacion <= pv_fecha
                        AND provisionado = 'S'
          ORDER BY cod_empresa, num_proceso DESC;
        --
        vnum_proceso PR_HIS_CALIF_X_PR_TRAMITE.num_proceso%TYPE := NULL;
        vcod_calif   PR_HIS_CALIF_X_PR_TRAMITE.cod_calif%TYPE := NULL;
        vmens_error  VARCHAR2(200);
        --
    vemp_fideicomiso VARCHAR2(5);
    vMensajeError    VARCHAR2(200);
  BEGIN
    IF pv_fecha IS NULL THEN -- obtiene la calificaci�n vigente
       Pr_Utl2.OBT_ULTIMA_PREVISION(pv_empresa,
                                    vnum_proceso,
                                    vmens_error);
    ELSE -- obtiene un calificaci�n hist�rica...
           OPEN cur_hist;
           FETCH cur_hist INTO vnum_proceso;
           CLOSE cur_hist;
        END IF;
        --
        OPEN cur_calif(vnum_proceso);
        FETCH cur_calif INTO vcod_calif;
        CLOSE cur_calif;
        RETURN vcod_calif;
  END Obt_Calif_x_Tramite;
  --
  --
  PROCEDURE Calificacion_Automatica(p_cod_empresa       IN VARCHAR2,
                                    p_act_califica      IN VARCHAR2,
                                    p_fecha             IN DATE,
                                    p_agencia           IN VARCHAR2,
                                    p_mto_min_comercial IN NUMBER,
                                    p_cod_error     IN OUT VARCHAR2 )IS
    v_numproce  NUMBER;
  BEGIN

    /*------------------------------------------------------------------------------------------------------*/
    --HEALVAREZ-01/2018 - Cambio para contagio interno.
        --DELETE FROM pr.pr_operaciones_tmp
        --WHERE SESION=SUBSTR('CALIFXCLI'||USER,1,15);--AND FEC_PRIMER_DESEMBOLSO/*FECHA PROCESO*/=p_fecha;
    /*------------------------------------------------------------------------------------------------------*/


    --aqui
    --DBMS_TRANSACTION.use_rollback_segment('RBSG');
    --
    --Se cargan las variables
    -- Tipos de Operaci�n
    Pr_Utl.Parametro_General('COD_OPER_LINEAS_CR','PR',vconst_CODOPERLC,p_cod_error);
    Pr_Utl.Parametro_General('COD_OPER_CARTERA','PR',vconst_CODOPERPR,p_cod_error);
    Pr_Utl.Parametro_General('COD_OPER_BOLETAS','PR',vconst_CODOPERGT,p_cod_error);
    Pr_Utl.Parametro_General('COD_OPER_TARJETA','PR',vconst_CODOPERTC,p_cod_error);
    Pr_Utl.Parametro_General('COD_OPER_SOBREGIRO','PR',vconst_CODOPERSG,p_cod_error);
    Pr_Utl.Parametro_General('COD_OPER_COMEX','PR',vconst_CODOPERCM,p_cod_error);
    Pr_Utl.Parametro_General('COD_OPER_FACTORAJE','PR',vconst_CODOPERDF,p_cod_error);
    Pr_Utl.Parametro_General('CODPRPREPAG','PR',vconst_CODPRPREPAG,p_cod_error);
    --
    -- mis constantes...
    Pr_Utl.Parametro_General('COD_TIP_CRED_COMER', 'PR', vconst_tip_cred_comercial  , p_cod_error);
    Pr_Utl.Parametro_General('COD_TIP_CRED_PYME',  'PR', vconst_tip_cred_pyme       , p_cod_error);
    Pr_Utl.Parametro_General('COD_TIP_CRED_MICR',  'PR', vconst_tip_cred_micro      , p_cod_error);
    Pr_Utl.Parametro_General('COD_TIP_CRED_CONS' , 'PR', vconst_tip_cred_consumo    , p_cod_error);
    Pr_Utl.Parametro_General('COD_TIP_CRED_CONDG', 'PR', vconst_tip_cred_consumo_dg , p_cod_error);
    Pr_Utl.Parametro_General('COD_TIP_CRED_HIPO' , 'PR', vconst_tip_cred_hipotecario, p_cod_error);
    --Nuevo Circular 217/2014
    Pr_Utl.Parametro_General('COD_TIP_CRED_HIPO19' , 'PR', vconst_tip_cred_hipotecario19, p_cod_error);
    Pr_Utl.Parametro_General('COD_TIP_CRED_HIPO20' , 'PR', vconst_tip_cred_hipotecario20, p_cod_error);
    Pr_Utl.Parametro_General('COD_TIP_CRED_HIPO21' , 'PR', vconst_tip_cred_hipotecario21, p_cod_error);
    Pr_Utl.Parametro_General('COD_TIP_CRED_HIPO9' , 'PR',  vconst_tip_cred_hipotecario9, p_cod_error);
    --
    --Nuevo Tipos de Creditos 04-01-2013 --JCRS
    Pr_Utl.Parametro_General('COD_TIP_CRED_COMERC3', 'PR', vconst_tip_cred_comercialC3  , p_cod_error);
    Pr_Utl.Parametro_General('COD_TIP_CRED_COMERC2', 'PR', vconst_tip_cred_comercialC2  , p_cod_error);
    Pr_Utl.Parametro_General('COD_TIP_CRED_MICROM1', 'PR', vconst_tip_cred_microM1     , p_cod_error);
    Pr_Utl.Parametro_General('COD_TIP_CRED_MICROM7', 'PR', vconst_tip_cred_microM7     , p_cod_error);
    Pr_Utl.Parametro_General('COD_TIP_CRED_MICROM8', 'PR', vconst_tip_cred_microM8     , p_cod_error);
    Pr_Utl.Parametro_General('COD_TIP_CRED_MICROM9', 'PR', vconst_tip_cred_microM9     , p_cod_error);
    Pr_Utl.Parametro_General('COD_TIP_CRED_PYMEP2',  'PR', vconst_tip_cred_pymeP2      , p_cod_error);
    Pr_Utl.Parametro_General('COD_TIP_CRED_PYMEP3',  'PR', vconst_tip_cred_pymeP3      , p_cod_error);
    Pr_Utl.Parametro_General('COD_TIP_CRED_PYMEP4',  'PR', vconst_tip_cred_pymeP4      , p_cod_error);
    Pr_Utl.Parametro_General('COD_TIP_CRED_PYMEP5',  'PR', vconst_tip_cred_pymeP5      , p_cod_error);
    Pr_Utl.Parametro_General('COD_TIP_CRED_PYMEP6',  'PR', vconst_tip_cred_pymeP6      , p_cod_error);
    --
    Pr_Utl.Parametro_General('CLA_GAR_HIPOTECA', 'PR', vconst_cla_gar_hipotecaria, p_cod_error);
    --
    -- moneda de consolidacion...
    Pr_Utl.Parametro_General('MONEDA_BASE', 'PA', vconst_moneda_consolid, P_cod_error);
    --
    -- tipos de garantia
    Pr_Utl.Parametro_General('TIP_GAR_DPF','PR',vconst_tipgardpf,p_cod_error);
    Pr_Utl.Parametro_General('TIP_GAR_CONTRA','PR',vconst_tipgarcon,p_cod_error);
    -- Porcentaje a disminuir por garant�as autoliquidables
    Pr_Utl.parametro_general('PORC_DISM_AUTOLIQ','PR',VConst_PorcDismAutoLiq, P_Cod_Error);
    --
    -- tipo de garant�a hipotecaria rural..
    Pr_Utl.Parametro_General('TIP_GAR_RURAL'     ,'PR',vconst_tipgar_hipo_rural , p_cod_error);
    -- tipo de garant�a hipotecaria urbana...
    Pr_Utl.Parametro_General('TIP_GAR_URBANO'    ,'PR',vconst_tipgar_hipo_urbano, p_cod_error);
    --
    -- c�digo de ente de 'Derechos Reales'
    Pr_Utl.Parametro_x_Empresa(p_cod_empresa, 'COD_DERECHOS_REALES', 'PR', vconst_derechos_reales, p_cod_error); -- c�digo de ente de 'Derechos Reales
    -- c�digo de persona del BUSA
    Pr_Utl.Parametro_x_Empresa(p_cod_empresa, 'COD_CLIENTE_BUSA'   , 'PA', vconst_codigo_busa    , p_cod_error); -- c�digo de ente de 'Derechos Reales
    --
    VConst_MontoComercial := p_mto_min_comercial;
    --
    -- CALIFICACION
    --
    -- SSPM 30/05/2020 revisado para diferimiento
    calificacion(p_cod_empresa,
                 p_fecha,
                 'S',
                 'S',
                 p_cod_error);
    IF p_cod_error IS NULL THEN
       --
       COMMIT;
       --
           --aqui
       --DBMS_TRANSACTION.use_rollback_segment('RBSG');
       --
       IF p_act_califica = 'S' THEN
          -- BITACORA: controlar duracion de Act_Calif_X_Cliente
          BEGIN
            vproc_bit := TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS');
            INSERT INTO PR_BIT_CALIFPROCS (num_proceso, ini_proceso, ind_proceso)
            VALUES (vproc_bit, SYSDATE, 10);
            --
            EXCEPTION
               WHEN OTHERS THEN
                    ROLLBACK; RAISE_APPLICATION_ERROR('-20500', 'Error bitacora insert 10' || SQLERRM);
          END;
          --@sspm
          Act_Calif_X_Cliente(p_cod_empresa,
                                      p_fecha,
                              p_cod_error);
          IF p_cod_error IS NULL THEN
             --
             -- BITACORA: actualizar duracion de Act_Calif_X_Cliente
             BEGIN
               UPDATE PR_BIT_CALIFPROCS SET fin_proceso = SYSDATE WHERE num_proceso = vproc_bit;
               --
               EXCEPTION
                  WHEN OTHERS THEN
                       ROLLBACK; RAISE_APPLICATION_ERROR('-20500', 'Error bitacora UPDATE 10' || SQLERRM);
             END;
             --
             COMMIT;
             --
             DBMS_TRANSACTION.use_rollback_segment('RBSG');
                     -- obtenemos el n�mero de proceso de calificaci�n/prevision...
             v_numproce  := Nuevo_Proceso (p_cod_empresa, p_fecha, 'S', p_cod_error);
                         --
             IF p_cod_error IS NULL THEN
                --
                -- BITACORA: controlar duracion Act_Calif_X_Tramite
                BEGIN
                  vproc_bit := TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS');
                  INSERT INTO PR_BIT_CALIFPROCS (num_proceso, ini_proceso, ind_proceso)
                  VALUES (vproc_bit, SYSDATE, 11);
                  --
                  EXCEPTION
                     WHEN OTHERS THEN
                          ROLLBACK; RAISE_APPLICATION_ERROR('-20500', 'Error bitacora insert 11' || SQLERRM);
                END;
                ---SSPM 30/05/2020  revisado
                Act_Calif_X_Tramite(p_cod_empresa,
                                    p_fecha,
                                    v_numproce,
                                    NULL,
                                    p_cod_error);
                IF p_cod_error IS NOT NULL THEN
                           ROLLBACK;
                ELSE
                   -- BITACORA: actualizar duracion de Act_Calif_X_Tramite
                   BEGIN
                     UPDATE PR_BIT_CALIFPROCS SET fin_proceso = SYSDATE WHERE num_proceso = vproc_bit;
                     --
                     EXCEPTION
                        WHEN OTHERS THEN
                             NULL;
                   END;
                   COMMIT;
                END IF;
                --Actualizamos la calificacion del cliente segun circular 217/2014 donde se evalua la discrepancia
                --entre las categorias de calificacion, esta debe ser comparada con la informacioncarga mensualmente.
                --JCRS-24-01-2014  Circular 217/2014
                -- SSPM 30/05/2020 revisado
                Act_Calif_X_Tramite_Cliente(p_cod_empresa,
                                            p_fecha,
                                            v_numproce,
                                            NULL,
                                            p_cod_error);
                IF p_cod_error IS NOT NULL THEN
                           ROLLBACK;
                ELSE
                   -- BITACORA: actualizar duracion de Act_Calif_X_Tramite
                   BEGIN
                     UPDATE PR_BIT_CALIFPROCS SET fin_proceso = SYSDATE WHERE num_proceso = vproc_bit;
                     --
                     EXCEPTION
                        WHEN OTHERS THEN
                             NULL;
                   END;



                   /*---------------------------------------------------------*/
                   --healvarez--20/07/2021--FSN calificacion
                   DECLARE
                   vl_retorno number(10);
                   BEGIN
                    vl_retorno:=PR.f_calificacion_excep (p_cod_empresa, v_numproce);
                    PA.log_proceso ('f_calificacion_excep'||to_char(v_numproce), 'Registros procesados -> '||to_char(vl_retorno));
                   END;
                   /*---------------------------------------------------------*/


                   if p_cod_empresa='1' then--01/2024

                    /*---------------------------------------------------------*/

                        --healvarez--17/11/2023--Cambios segun FSN.
                        /* Formatted on 30/11/2023 16:01:20 (QP5 v5.256.13226.35538) %HEALVAREZ% */
                        DECLARE
                           vl_cod_per_ev        VARCHAR2 (50);
                           vl_estado_ev         VARCHAR2 (50);
                           vl_estado_ev1        VARCHAR2 (50);
                           --vl_desc_ant varchar2(500);
                           vl_emp_ev            VARCHAR2 (50);
                           vl_cont_est_ev       NUMBER (5);
                           vl_cont_est_ev1      NUMBER (5);
                           vl_cont_est_ev_tot   NUMBER (5);
                           vl_valor_p           VARCHAR2 (50);


                           vl_calif_man         VARCHAR2 (50);
                           vl_desc_man          VARCHAR2 (500);
                           lv_cod_empresa_man   VARCHAR2 (50);
                        --vl_cod_emp_cc varchar2(50);
                        BEGIN
                           --PR.PK_CALIF_X_CLIENTE
                           --vl_desc_ant, vl_cod_emp_cc

                           BEGIN
                              SELECT valor
                                INTO vl_valor_p
                                FROM parametros_x_empresa
                               WHERE cod_empresa = '1' AND abrev_parametro = 'CALIF_X_CLI_OP_CANC';
                           EXCEPTION
                              WHEN OTHERS
                              THEN
                                 vl_valor_p := 'N';
                           END;

                           --vl_valor_p := 'S';                                            --ojo--quitar

                           IF vl_valor_p = 'S'
                           THEN
                              --dbms_output.put_line('inicio 1');

                              vl_emp_ev :=p_cod_empresa;--p_cod_empresa;

                              --vl_emp_ev := '1';                                          --ojo--quitar


                              DELETE FROM pr_operaciones_tmp
                                    WHERE sesion = 'SESCALICANC' || vl_emp_ev;

                              --orig
                              /*INSERT INTO pr_operaciones_tmp (sesion, cod_persona)
                                 SELECT 'SESCALICANC' || vl_emp_ev, CC.COD_PERSONA
                                   FROM pr_tramite a, personas_x_pr_tramite cc, PR_CALIF_X_CLIENTE b
                                  WHERE     A.COD_EMPRESA = CC.COD_EMPRESA
                                        AND A.NUM_TRAMITE = CC.NUM_TRAMITE
                                        AND B.COD_EMPRESA = A.COD_empresa
                                        AND CC.COD_PERSONA = B.COD_PERSONA
                                        AND B.FEC_CALIF = (SELECT MAX (c.fec_calif)
                                                             FROM PR_CALIF_X_CLIENTE c
                                                            WHERE --C.COD_EMPRESA=a.cod_empresa and --11/2023
                                                                 c    .cod_empresa IN (1,
                                                                                       5,
                                                                                       8,
                                                                                       11)
                                                                  AND c.cod_persona = cc.cod_persona)
                                        --and A.COD_EMPRESA=vl_emp_ev--11/2023
                                        AND a.cod_empresa IN (1,
                                                              5,
                                                              8,
                                                              11)
                                        AND a.codigo_estado = 'C'
                                        AND B.COD_CALIF <> 'A'
                                        AND a.num_tramite IN (SELECT pcred.num_tramite
                                                                FROM pr_Tramite pcred
                                                               WHERE     pcred.cod_empresa =
                                                                            a.cod_empresa
                                                                     AND pcred.codigo_estado = 'C') --aqui
                                        AND 0 =
                                               (SELECT SUM (
                                                          CASE
                                                             WHEN pr1.codigo_estado = 'C' THEN 0
                                                             ELSE 1
                                                          END)
                                                  FROM pr_tramite pr1, personas_x_pr_Tramite pr2
                                                 WHERE     PR1.COD_EMPRESA = PR2.COD_EMPRESA
                                                       AND PR1.NUM_TRAMITE = PR2.NUM_TRAMITE
                                                       AND pr1.codigo_estado NOT IN ('N',
                                                                                     'R',
                                                                                     'A',
                                                                                     'H',
                                                                                     'X')
                                                       AND PR1.COD_EMPRESA IN (1,
                                                                               5,
                                                                               8,
                                                                               11)
                                                       AND pr2.cod_persona = CC.COD_PERSONA);*/


                            INSERT INTO pr_operaciones_tmp (sesion, cod_persona)
                           SELECT 'SESCALICANC' || vl_emp_ev, CC.COD_PERSONA
                                   FROM pr_tramite a, personas_x_pr_tramite cc, PR_CALIF_X_CLIENTE b
                                  WHERE     A.COD_EMPRESA = CC.COD_EMPRESA
                                        AND A.NUM_TRAMITE = CC.NUM_TRAMITE
                                        --ojo--AND B.COD_EMPRESA = A.COD_empresa--2024
                                        AND CC.COD_PERSONA = B.COD_PERSONA
                                        AND B.FEC_CALIF = (SELECT MAX (c.fec_calif)
                                                             FROM PR_CALIF_X_CLIENTE c
                                                            WHERE --C.COD_EMPRESA=a.cod_empresa and --11/2023
                                                                 c    .cod_empresa IN (1,
                                                                                       5,
                                                                                       8,
                                                                                       11)
                                                                  AND c.cod_persona = cc.cod_persona)
                                        --and A.COD_EMPRESA=vl_emp_ev--11/2023
                                        AND a.cod_empresa IN (1,
                                                              5,
                                                              8,
                                                              11)
                                        AND a.codigo_estado = 'C'
                                        AND B.COD_CALIF <> 'A'
                                        /*AND a.num_tramite IN (SELECT pcred.num_tramite
                                                                FROM pr_Tramite pcred
                                                               WHERE     pcred.cod_empresa =
                                                                            a.cod_empresa
                                                                     AND pcred.codigo_estado = 'C') --aqui*/--21/12/2023
                                        /*AND 0 =
                                               (SELECT SUM (
                                                          CASE
                                                             WHEN pr1.codigo_estado = 'C' THEN 0
                                                             ELSE 1
                                                          END)
                                                  FROM pr_tramite pr1, personas_x_pr_Tramite pr2
                                                 WHERE     PR1.COD_EMPRESA = PR2.COD_EMPRESA
                                                       AND PR1.NUM_TRAMITE = PR2.NUM_TRAMITE
                                                       AND pr1.codigo_estado NOT IN ('N',
                                                                                     'R',
                                                                                     'A',
                                                                                     'H',
                                                                                     'X','S')
                                                       AND PR1.COD_EMPRESA IN (1,
                                                                               5,
                                                                               8,
                                                                               11)
                                                       AND pr2.cod_persona = CC.COD_PERSONA)*/
                                                       and a.num_tramite in(
                                                       select prant.num_tramite from pr_his_tramite prant
                                                       where prant.fec_registro_hi=to_Date(TRUNC(p_fecha, 'MM')-1)
                                                       and prant.num_tramite not in(
                                                       select pract.num_tramite from pr_his_tramite pract
                                                       where pract.fec_registro_hi=p_fecha
                                                       )
                                                       );





                              --dbms_output.put_line('inicio 2');

                              /*FOR i IN (SELECT DISTINCT (cod_persona)
                                          FROM pr_operaciones_tmp
                                         WHERE sesion = 'SESCALICANC' || vl_emp_ev)*/
                              FOR i
                                 IN (SELECT DISTINCT (ptem.cod_persona)
                                       FROM pr_operaciones_tmp ptem
                                      WHERE     sesion = 'SESCALICANC' || vl_emp_ev--empresa env
                                            AND 1 =
                                                   (SELECT COUNT (DISTINCT (pra.codigo_estado))
                                                              codigo_estado
                                                      FROM pr_tramite pra
                                                     WHERE     pra.codigo_estado NOT IN ('N',
                                                                                         'R',
                                                                                         'A',
                                                                                         'H',
                                                                                         'X','S')
                                                           AND pra.num_tramite IN (SELECT pppr.num_tramite
                                                                                     FROM personas_x_pr_Tramite pppr
                                                                                    WHERE     pppr.cod_persona =
                                                                                                 ptem.cod_persona
                                                                                          AND pppr.cod_empresa IN (1,
                                                                                                                   5,
                                                                                                                   8,
                                                                                                                   11)))
                                            AND 1 =
                                                   (SELECT DECODE (
                                                              COUNT (DISTINCT (b.codigo_estado)),
                                                              0, 1,
                                                              COUNT (DISTINCT (b.codigo_estado)))
                                                              resp
                                                      --INTO vl_estado_ev1, vl_cont_est_ev1
                                                      FROM pr_v_garantes a, pr_tramite b
                                                     WHERE    --a.cod_empresa = vl_emp_ev and--11/2023
                                                          a    .cod_empresa IN (1,
                                                                                5,
                                                                                8,
                                                                                11)
                                                           AND a.quirografaria = 'N'
                                                           AND a.cod_cliente = ptem.cod_persona --'163372'--'163372'
                                                           AND a.cod_empresa = b.cod_empresa
                                                           AND a.num_tramite = b.num_tramite
                                                           AND (b.codigo_estado IN ('D',
                                                                                    'E',
                                                                                    'V',
                                                                                    'J',
                                                                                    'G',
                                                                                    'I',
                                                                                    'L',
                                                                                    'T',
                                                                                    'P'))))
                              LOOP
                                 vl_cod_per_ev := i.cod_persona;
                                 --dbms_output.put_line('# '||vl_cod_per_ev);
                                 vl_cont_est_ev := 0;
                                 vl_cont_est_ev1 := 0;

                                 BEGIN
                                      SELECT DISTINCT (codigo_estado), COUNT (1)
                                        INTO vl_estado_ev, vl_cont_est_ev
                                        FROM pr_tramite
                                       WHERE     codigo_estado NOT IN ('N',
                                                                       'R',
                                                                       'A',
                                                                       'H',
                                                                       'X','S')
                                             AND num_tramite IN (SELECT pppr.num_tramite
                                                                   FROM personas_x_pr_Tramite pppr
                                                                  WHERE     pppr.cod_persona =
                                                                               vl_cod_per_ev
                                                                        AND pppr.cod_empresa IN (1,
                                                                                                 5,
                                                                                                 8,
                                                                                                 11))
                                    GROUP BY codigo_estado;
                                 EXCEPTION
                                    WHEN OTHERS
                                    THEN
                                       vl_estado_ev := 'X';
                                 END;


                                 IF vl_estado_ev = 'C'
                                 THEN
                                    BEGIN
                                         --deuda ind
                                         SELECT DISTINCT (b.codigo_estado), COUNT (1)
                                           INTO vl_estado_ev1, vl_cont_est_ev1
                                           FROM pr_v_garantes a, pr_tramite b
                                          WHERE               --a.cod_empresa = vl_emp_ev and--11/2023
                                               a    .cod_empresa IN (1,
                                                                     5,
                                                                     8,
                                                                     11)
                                                AND a.quirografaria = 'N'
                                                AND a.cod_cliente = vl_cod_per_ev
                                                AND a.cod_empresa = b.cod_empresa
                                                AND a.num_tramite = b.num_tramite
                                                AND (b.codigo_estado IN ('D',
                                                                         'E',
                                                                         'V',
                                                                         'J',
                                                                         'G',
                                                                         'I',
                                                                         'L',
                                                                         'T',
                                                                         'P'))
                                       GROUP BY b.codigo_estado;
                                    EXCEPTION
                                       WHEN NO_DATA_FOUND
                                       THEN
                                          vl_estado_ev1 := 'C';
                                       WHEN OTHERS
                                       THEN
                                          vl_estado_ev1 := 'X';
                                    END;
                                 END IF;

                                 vl_cont_est_ev_tot := vl_cont_est_ev + vl_cont_est_ev1;



                                 IF vl_estado_ev = 'C' AND vl_estado_ev1 = 'C'
                                 THEN
                                    FOR j
                                       IN (SELECT SUBSTR (
                                                        'Calif A x Op Cancel Tot('
                                                     || vl_cont_est_ev_tot
                                                     || ') - Ant: '
                                                     || cod_calif
                                                     || ' - '
                                                     || mot_calif
                                                     || ' - '
                                                     || fec_calif,
                                                     1,
                                                     500)
                                                     vl_desc_ant,
                                                  cod_empresa vl_cod_emp_cc
                                             --into vl_desc_ant, vl_cod_emp_cc
                                             FROM pr_calif_x_cliente a
                                            WHERE                   --A.COD_EMPRESA=vl_emp_ev--11/2023
                                                 a    .cod_empresa IN (1,
                                                                       5,
                                                                       8,
                                                                       11)
                                                  AND a.cod_persona = vl_cod_per_ev
                                                  AND a.fec_calif =
                                                         (SELECT MAX (c.fec_calif)
                                                            FROM PR_CALIF_X_CLIENTE c
                                                           WHERE   /*C.COD_EMPRESA=a.cod_empresa and*/
                                                                c    .cod_empresa IN (1,
                                                                                      5,
                                                                                      8,
                                                                                      11)
                                                                 AND c.cod_persona = a.cod_persona))
                                    LOOP

                                    /*select sesion,des_moneda,cod_persona,fec_primer_desembolso,des_sucursal,observaciones2
                                    from pr_operaciones_tmp
                                    where  sesion='TEMPCALIF_CF'
                                    order by fecha_reprogramacion*/


                                       begin
                                            INSERT INTO PR.PR_CALIF_X_CLIENTE (COD_EMPRESA,
                                                                          COD_PERSONA,
                                                                          FEC_CALIF,
                                                                          COD_CALIF,
                                                                          MOT_CALIF,
                                                                          ADICIONADO_POR,
                                                                          FEC_ADICION,
                                                                          TIP_CALIF)
                                            VALUES (j.vl_cod_emp_cc,
                                                    vl_cod_per_ev,
                                                    p_fecha,--TRUNC (SYSDATE),--2024--fecha proceso
                                                    'A',
                                                    SUBSTR (j.vl_desc_ant, 1, 500),
                                                    USER,
                                                    SYSDATE,
                                                    'A');
                                        exception when others then--24/01/2024--para control de exception

                                            insert into pr_operaciones_tmp (sesion,des_moneda,cod_persona,fec_primer_desembolso,des_sucursal,observaciones2, fecha_reprogramacion)
                                            values ('TEMPCALIF_CF',j.vl_cod_emp_cc,
                                                        vl_cod_per_ev,
                                                        p_fecha,
                                                        'A',
                                                        SUBSTR (j.vl_desc_ant, 1, 500), sysdate);
                                        end;

                                    END LOOP;

                                    --calif x ente--11/2023
                                    BEGIN
                                       SELECT cod_calif, cod_empresa
                                         INTO vl_calif_man, lv_cod_empresa_man
                                         FROM pr_calif_x_ente a
                                        WHERE     a.cod_empresa IN (1,
                                                                    5,
                                                                    8,
                                                                    11)
                                              AND a.cod_persona = vl_cod_per_ev
                                              AND a.fec_calif IN (SELECT MAX (mf.fec_calif)
                                                                    FROM pr_calif_x_ente mf
                                                                   WHERE mf.cod_persona =
                                                                            a.cod_persona);
                                    EXCEPTION
                                       WHEN OTHERS
                                       THEN
                                          vl_calif_man := 'A';
                                    END;

                                    IF vl_calif_man <> 'A'
                                    THEN
                                       lv_cod_empresa_man := '1';   --solo en la 1 existe el codigo 11

                                       SELECT SUBSTR (
                                                    'Calif A x Op C('
                                                 || vl_cont_est_ev_tot
                                                 || ')->:'
                                                 || fec_calif
                                                 || '-'
                                                 || cod_calif
                                                 || ' - '
                                                 || des_calif,
                                                 1,
                                                 80)
                                         INTO vl_desc_man
                                         FROM pr_calif_x_ente a
                                        WHERE     a.cod_empresa IN (1,
                                                                    5,
                                                                    8,
                                                                    11)
                                              AND a.cod_persona = vl_cod_per_ev
                                              AND a.fec_calif IN (SELECT MAX (mf.fec_calif)
                                                                    FROM pr_calif_x_ente mf
                                                                   WHERE mf.cod_persona =
                                                                            a.cod_persona);

                                       begin

                                       INSERT INTO PR.PR_CALIF_X_ENTE (COD_EMPRESA,
                                                                       COD_ENTE_CALIF,
                                                                       COD_PERSONA,
                                                                       FEC_CALIF,
                                                                       COD_CALIF,
                                                                       DES_CALIF,
                                                                       ADICIONADO_POR,
                                                                       FEC_ADICION)
                                            VALUES (lv_cod_empresa_man,
                                                    '11',
                                                    vl_cod_per_ev,
                                                    p_fecha,--TRUNC (SYSDATE),--2024, par fecha de proceso
                                                    'A',
                                                    vl_desc_man,
                                                    USER,
                                                    SYSDATE);
                                        exception when others then--24/01/2024--para control de exception

                                            insert into pr_operaciones_tmp (sesion,des_moneda,cod_persona,des_sucursal,observaciones2, fecha_reprogramacion)
                                            values ('TEMPCALIF_CF',lv_cod_empresa_man,
                                                    '11',
                                                    vl_cod_per_ev, vl_desc_man, sysdate);
                                        end;



                                    END IF;
                                 END IF;
                              END LOOP;
                           END IF;
                        END;

                    end if;--

                    /*---------------------------------------------------------*/




/*-------------------------------------------------------------------------------------*/
                    --healvarez-05/09/2022--FSN contagio interempresa.
                    declare
                        vl_proces_inter_emp varchar2(200);
                        vl_res number(5);
                    begin

                        select valor
                        into vl_proces_inter_emp
                        from parametros_x_empresa
                        where abrev_parametro='CONTAGIO_INTER_EMP';

                        if vl_proces_inter_emp<>'N' then

                            select instr(vl_proces_inter_emp,p_cod_empresa)
                            into vl_res
                            from dual;

                            if vl_res=0 then

                                PR.PR_CONTAGIO (    p_cod_empresa,
                                                v_numproce,
                                                p_fecha,
                                                p_cod_error
                                                 );
                                IF p_cod_error IS NOT NULL THEN
                                    ROLLBACK;
                                END IF;

                            end if;

                        else
                            PR.PR_CONTAGIO (    p_cod_empresa,
                                            v_numproce,
                                            p_fecha,
                                            p_cod_error
                                             );
                            IF p_cod_error IS NOT NULL THEN
                                ROLLBACK;
                            END IF;
                        end if;

                    exception when others then
                        PR.PR_CONTAGIO (    p_cod_empresa,
                                        v_numproce,
                                        p_fecha,
                                        p_cod_error
                                         );
                        IF p_cod_error IS NOT NULL THEN
                            ROLLBACK;
                        END IF;
                    end;
                    /*-------------------------------------------------------------------------------------*/



                    --healvarez--09/2022--fsn interempresas.
                    ---- SSPM 30/03/2020 contagio (*****)
                    /*PR.PR_CONTAGIO (    p_cod_empresa,
                                        v_numproce,
                                        p_fecha,
                                        p_cod_error
                                         );
                    IF p_cod_error IS NOT NULL THEN
                        ROLLBACK;
                    END IF;*/

                    /*---------------------------------------------------------*/
                    --healvarez--20/07/2021--FSN prevision
                       DECLARE
                       vl_retorno number(10);
                       BEGIN
                        vl_retorno:=PR.f_prev_excep_op (p_cod_empresa, v_numproce);
                        PA.log_proceso ('f_prev_excep_op'||to_char(v_numproce), 'Registros procesados -> '||to_char(vl_retorno));
                       END;
                    /*---------------------------------------------------------*/





                   COMMIT;

                END IF;
             ELSE
                ROLLBACK;
                         END IF;
                  ELSE
                     ROLLBACK;
                  END IF;
           END IF;
    ELSE
       ROLLBACK;
    END IF;
    --
  END Calificacion_Automatica;
  --
  --
END Pr_Calif_Automatica;
