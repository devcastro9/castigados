CREATE OR REPLACE PROCEDURE    PR.PR_CASTIGO_PROD_DIF (  P_EMPRESA       IN          VARCHAR2,
                                                        P_NUM_PROCESO   IN          NUMBER,
                                                        P_FECHA         IN          DATE,
                                                        P_AGENCIA       IN          NUMBER,
                                                        P_ERROR         OUT         VARCHAR2
                                                        )
------------------------------------------------------------

   -- CASTIGO DE PRODUCTOS DIFERIDOS  SHC : 05/01/2022
IS
  vl_sw_cabecera    NUMBER(5):=0;
  vP_NUMERO_ASIENTO NUMBER (10);
  vl_empresa_BUSA   VARCHAR2(5);
  vl_AD_BUSA        NUMBER(10);
  vl_sub_aplicacion NUMBER(5);
  vl_transaccion    NUMBER(5);
  vl_subtrans       NUMBER(5);
  v_id_proceso      NUMBER(10);            --> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11
  v_empresa_Fassil  VARCHAR2(5):= '11';    --> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11
  v_empresa_BUSA    VARCHAR2(5):= '1';    --> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11
  v_empresa_BDP     VARCHAR2(5):= '5';    --> FSN 705555 Castigo de productos empresa 5 BDP
  v_interes_castigado_contab NUMBER(16,2); --> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11
  v_interes_suspenso_contab  NUMBER(16,2); --> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11
  v_monto_interes_dif        NUMBER(16,2); --> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11
  v_interes_corriente_contab NUMBER(16,2); --> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11
  V_DESCRIPCION              VARCHAR2 (200) := 'CASTIGO DE PRODUCTOS *DIFERIDOS MORA >90 Y/0 CALIF >D';
  V_FECHA_PROC               DATE := P_FECHA;
  V_MENSAJE_ERROR2           VARCHAR2 (500);

BEGIN

begin
   --> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11
   --> FSN 705555: Empresa 5 BDP sigue logica de empresa 11 Fassil
   IF P_EMPRESA IN (v_empresa_Fassil, v_empresa_BDP) THEN
     SELECT s_id_cast_prod.NEXTVAL
      INTO v_id_proceso
     FROM DUAL;
   END IF;
   --> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11
   ---
    for di in(
               SELECT h.codigo_empresa cod_empresa,
                      h.no_credito,
                      h.monto_desembolsado,
                      h.saldo_actual,
                      dif.interes_castigado_contab,
                      dif.interes_corriente_contab,
                      dif.monto_interes_dif,
                      dif.interes_suspenso_contab,
                      h.num_dias_mora,
                      h.codigo_moneda,
                     ((((h.intereses_acumulados - h.intereses_castigados + h.intereses_en_suspenso) - h.monto_pagado_intereses)) - h.intereses_en_suspenso ) interes_corriente,
                     --(dif.MONTO_INTERES_DIF - dif.INTERES_CASTIGADO_CONTAB - dif.MONTO_PAGADO_INTERES_DIF)interes_diferidos,
                      (dif.monto_interes_dif - dif.monto_pagado_interes_dif) interes_diferidos,
                      h.intereses_en_suspenso interes_suspenso,
                      h.estado,
                      'D' cod_calif,
                      h.intereses_castigados,
                      h.num_tramite
                FROM pr_creditos_hi h,
                     pr_creditos_dif_hi dif
                WHERE h.codigo_empresa = p_empresa
                 AND  h.estado not in ('C','N','I','L')
                 AND  h.fec_registro_hi = p_fecha
                --and H.num_tramite=3010590
                 AND dif.cod_empresa=h.codigo_empresa
                 AND dif.fec_registro_hi=h.fec_registro_hi
                 AND dif.no_credito=h.no_credito
                 AND (nvl(dif.monto_interes_dif,0) - nvl(dif.monto_pagado_interes_dif,0)) > 0.01
                 AND nvl(dif.saldo_interes_dif,0) > 0 --
                 AND h.saldo_actual>0
                 --> FSN 705555: Correccion condicion calificacion IN ('D','E','F') en lugar de >= 'D'
                 AND EXISTS (SELECT 1
                               FROM  pr_his_calif_x_pr_tramite calif
                             WHERE  calif.cod_empresa = p_empresa
                                and calif.num_proceso = p_num_proceso
                                and calif.num_tramite  = to_number(h.num_tramite)
                                and (calif.cod_calif IN ('D','E','F') or calif.num_dias_mora >90 )  )
                 order by h.num_tramite
      )

      -- cobranza  aumentar el suspenso interes normal + interes suspenso - interes paga (DIF)
   LOOP
       --
       vl_sw_cabecera:=vl_sw_cabecera+1;
       IF vl_sw_cabecera=1 THEN
        --Caratula_Del_Asiento (P_EMPRESA,
            Cg_Utl.Caratula_del_Asiento(P_EMPRESA,
                                        P_AGENCIA,
                                       'BPR', --'BPR', /* CODIGO APLICACION */
                                        201,--vl_sub_aplicacion,
                                        8,----vl_transaccion, --3,     /* DESEMBOLSO */--ojo
                                        null,--149,--vl_subtrans, --Null,  /* TRANSACCION DE INTERFASE */
                                        0, --vl_movimiento  --NO HAY NUM MOV CC ->0
                                        V_DESCRIPCION,
                                        V_FECHA_PROC, --P_FECHA_Sistema,--09/07/2018
                                        V_FECHA_PROC, --P_FECHA_Sistema,--09/07/2018
                                        vP_NUMERO_ASIENTO,
                                        USER,
                                        V_MENSAJE_ERROR2);

            IF V_MENSAJE_ERROR2 IS NOT NULL THEN
               P_ERROR := '-2 ' || V_MENSAJE_ERROR2||' #:'||di.no_credito;
               return;
            END IF;
       END IF;


      --> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11
      --> FSN 705555: Empresa 5 BDP sigue logica de empresa 11 Fassil
   	  IF P_EMPRESA IN (v_empresa_Fassil, v_empresa_BDP) THEN
   	    v_interes_castigado_contab := nvl(di.interes_castigado_contab,0) + di.interes_diferidos;
        v_interes_suspenso_contab := nvl(di.interes_suspenso_contab,0) + di.interes_diferidos;
        v_monto_interes_dif      :=nvl(di.monto_interes_dif,0)-di.interes_diferidos;
        v_interes_corriente_contab := nvl(di.interes_corriente_contab,0) - di.interes_diferidos;
        --
          INSERT INTO PR_DET_CAST_PROD_DIF
            (codigo_empresa,                 no_credito,                     id_movimiento,                f_castigo,
             interes_castigado_contab_ant,   interes_suspenso_contab_ant,     monto_interes_dif_ant,       interes_corriente_contab_ant,
             interes_castigado_contab,       interes_suspenso_contab,         monto_interes_dif,           interes_corriente_contab,
             interes_diferidos,              cod_calif,                       dias_mora_cast,              adicionado_por,
             fec_adicion,                    modificado_por,                  fec_modificacion,            observaciones,
             num_asiento)
           VALUES
            ( P_EMPRESA,                    di.no_credito,                    v_id_proceso,                  P_FECHA,
              di.interes_castigado_contab,  di.interes_suspenso_contab,       di.monto_interes_dif,          di.interes_corriente_contab,
             v_interes_castigado_contab,    v_interes_suspenso_contab,        v_monto_interes_dif,           v_interes_corriente_contab,
             di.interes_diferidos,          di.cod_Calif,                     di.num_dias_mora,              user,
             sysdate,                       null,                             null,                         'PR0047',
             vP_NUMERO_ASIENTO);
       END IF;
       --> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11
         --contab......
            DECLARE
               --V_NUMERO_ASIENTO   NUMBER (10);
               vl_Error           VARCHAR (500);
               vl_diferencia      NUMBER (18, 2);
               vl_monto_contabilizar number(18,2);

            BEGIN
                  /*-----------------------------------------------------------------*/

                  vl_monto_contabilizar:=di.interes_suspenso;/*monto actualizar*/--???????????????
                    ---  SHC : 05/01/2022
                  UPDATE pr_creditos_dif A
                    SET A.INTERES_CASTIGADO_CONTAB = nvl(A.INTERES_CASTIGADO_CONTAB,0) + di.interes_diferidos,
                    A.interes_suspenso_contab = nvl(A.interes_suspenso_contab,0) + di.interes_diferidos,
                    a.monto_interes_dif=nvl(a.monto_interes_dif,0)-di.interes_diferidos,
                    a.interes_corriente_contab = nvl(interes_corriente_contab,0) - di.interes_diferidos
                    WHERE A.cod_empresa=di.cod_empresa AND A.no_credito=di.no_credito;


                  UPDATE pr_creditos_dif_hi A
                    SET A.INTERES_CASTIGADO_CONTAB = nvl(A.INTERES_CASTIGADO_CONTAB,0) + di.interes_diferidos,
                    A.interes_suspenso_contab = nvl(A.interes_suspenso_contab,0) + di.interes_diferidos,
                    a.monto_interes_dif=nvl(a.monto_interes_dif,0)-di.interes_diferidos,
                    a.interes_corriente_contab = nvl(interes_corriente_contab,0) - di.interes_diferidos,
                    a.saldo_interes_dif = a.saldo_interes_dif -di.interes_diferidos
                    WHERE A.cod_empresa=di.cod_empresa AND A.no_credito=di.no_credito and  a.fec_registro_hi = P_FECHA ;

                    -- intereses_suspenso_contab

                    ---  SHC : 05/01/2022 FIN
                    /*-----------------------------------------------------------------*/


                IF P_EMPRESA = v_empresa_BUSA THEN
                                BEGIN
                SELECT TP1NRO2, /*Codigo Sub Aplicacion*/
                       TP1NRO3, /*Transaccion*/
                       TP1IMP1 /*Subtransaccion*/
                 into  vl_sub_aplicacion,
                       vl_transaccion,
                       vl_subtrans
                FROM   param_dinam
                WHERE  tp1cod = P_EMPRESA /*Codigo Empresa*/
                   AND tp1cod1 = 970
                   AND tp1corr1 = 2 /*COMISION AGETIC*/
                   AND TP1NRO1 = P_EMPRESA;
                  --> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11
                  EXCEPTION
                    wHEN NO_DATA_FOUND THEN
                      NULL;
                END;
                END IF;
               --
               --> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11
               --> FSN 705555: Empresa 5 BDP sigue logica de empresa 11 Fassil
	           IF P_EMPRESA IN (v_empresa_Fassil, v_empresa_BDP) THEN
	      	     vl_empresa_BUSA := P_EMPRESA;
	      	     vl_AD_BUSA      := vp_numero_asiento;
	           END IF;
	          --> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11
                PR.DESEMBOLSOs.PR_INTERFACE_CONTA (P_EMPRESA,
                                     --INTERESES_CASTIGADOS,
                                     vl_empresa_BUSA,
                                     di.NUM_TRAMITE,
                                     V_FECHA_PROC,--:BKFECHA.FECHA_MOVIMIENTO,--to_date('31/03/2020','dd/mm/yyyy'),
                                     220,--200,--         P_TRANSACCION       IN      NUMBER,
                                     '01',--vl_sub_trans,--'01',--         P_SUBTRANS          IN      VARCHAR2,--healvarez--13/06/2020
                                     di.interes_diferidos, --di.interes_corriente,--:BKTotal.capital_diferido,
                                     0,--60000,--:BKTotal.Intereses_diferidos,
                                     0,
                                     0,-- PR.PR_FORMULA1(:BKCREDIT.CODIGO_EMPRESA,:bkCREDIT.NO_CREDITO,:bkcredit.NUM_TRAMITE, P_FECHA,'F10'),--         P_MONTO4             IN      NUMBER,
                                     0,--         P_MONTO5             IN      NUMBER,
                                     0,--         P_MONTO6              IN      NUMBER,
                                     0,-- PR.PR_FORMULA1(:BKCREDIT.CODIGO_EMPRESA,:bkCREDIT.NO_CREDITO,:bkcredit.NUM_TRAMITE, P_FECHA,'C10'),--         P_MONTO4             IN      NUMBER,
                                     0,--         P_MONTO8             IN      NUMBER,
                                     --V_DESCRIPCION|| ' NroCred:'||j.No_credito ,--'PAGO TOTAL DE DIFERIMIENTO No.'||:BKCREDIT.NO_CREDITO,--         P_DESCRIPCION       IN         VARCHAR2,--healvarez-08/07/2020--se adiciona descripcion..
                                     V_DESCRIPCION||': TrDif:'||di.num_tramite|| ' CrDif:'||di.No_credito , -- SHC : 05/01/2022 Productos  Diferidos
                                     '+',--         P_SIGNO            IN        VARCHAR2,
                                     vP_NUMERO_ASIENTO,--         P_AD_ORIGEN         IN OUT     NUMBER,
                                     vl_AD_BUSA,--0,--         P_AD_DESTINO        IN OUT     NUMBER,
                                     vl_Error);
                IF (vl_Error IS NOT NULL) THEN
                    P_ERROR :=  '-3 '||vl_error||' #:'||di.no_credito;
                    return;
                END IF;
                Cg_Utl.Cuadre_Asiento ( P_EMPRESA,
                                    V_FECHA_PROC,
                                    vP_NUMERO_ASIENTO,
                                    vl_diferencia,
                                    V_MENSAJE_ERROR2);

                IF V_MENSAJE_ERROR2 IS NOT NULL THEN
                    P_ERROR :=  '-4 '|| V_MENSAJE_ERROR2||' #:'||di.no_credito;
                    return;
                END IF;
            END;

   END LOOP;
 END;
   -- CASTIGO DE PRODUCTOS DIFERIDOS END SHC : 05/01/2022
   -- CASTIGO DE PRODUCTOS TOTALMENTE DIFERIDOS  SHC : 05/01/2022
declare
    vl_sw_cabecera_dif       NUMBER(5):=0;
    vp_numero_asiento_dif    NUMBER (10);
    vl_empresa_BUSA          VARCHAR2(2):='1';
    vl_AD_BUSA               NUMBER(10);
begin

    for di in(
            Select h.codigo_empresa cod_empresa,
                   h.no_credito,
                   h.monto_desembolsado, h.saldo_actual,
                   dif.interes_castigado_contab,
                   dif.interes_corriente_contab,
                   dif.monto_interes_dif,
                   dif.interes_suspenso_contab,
                   h.num_dias_mora,
                   h.codigo_moneda,
                   ((((h.intereses_acumulados - h.intereses_castigados + h.intereses_en_suspenso) - h.monto_pagado_intereses)) - h.intereses_en_suspenso ) interes_corriente,
                   --(dif.MONTO_INTERES_DIF - dif.INTERES_CASTIGADO_CONTAB - dif.MONTO_PAGADO_INTERES_DIF)interes_diferidos,
                   (dif.monto_interes_dif - dif.monto_pagado_interes_dif) interes_diferidos,
                   h.intereses_en_suspenso interes_suspenso,
                   h.estado,
                   'D' cod_calif,
                   h.intereses_castigados,
                   h.num_tramite
                FROM PR_CREDITOS_HI     H,
                     PR_CREDITOS_DIF_HI dif
                WHERE h.codigo_empresa = p_empresa
                AND   h.estado not in ('C','N','I','L')
                AND   h.fec_registro_hi = p_fecha
                AND   dif.cod_empresa=H.CODigo_EMPRESA
                AND   dif.fec_registro_hi=H.fec_registro_hi
                AND   dif.no_credito=H.No_credito
                AND   (NVL(dif.MONTO_INTERES_DIF,0) - NVL(dif.MONTO_PAGADO_INTERES_DIF,0)) > 0.01
                AND    NVL(dif.saldo_interes_dif,0) > 0 --
                AND h.saldo_actual=0
                AND EXISTS (SELECT 1
                              FROM  pr_his_calif_x_pr_tramite calif
                             WHERE  CALIF.COD_EMPRESA = P_EMPRESA
                                AND calif.num_proceso = P_NUM_PROCESO
                                AND calif.num_tramite  = H.num_tramite
                                --> FSN 705555: Correccion condicion calificacion IN ('D','E','F') en lugar de >= 'D'
                AND (CALIF.COD_CALIF IN ('D','E','F') OR CALIF.NUM_DIAS_MORA >90 )  )
                ORDER BY H.num_tramite)
      -- cobranza  aumentar el suspenso interes normal + interes suspenso - interes paga (DIF)
   LOOP
      vl_sw_cabecera_dif:= vl_sw_cabecera_dif+1;
      IF vl_sw_cabecera_dif=1 THEN
         --Caratula_Del_Asiento (P_EMPRESA,
          V_DESCRIPCION := 'CASTIGO DE PRODUCTOS *TDIFERIDOS MORA >90 Y/0 CALIF >D';
          --
          Cg_Utl.Caratula_del_Asiento(P_EMPRESA,
                                      P_AGENCIA,
                                     'BPR', --'BPR', /* CODIGO APLICACION */
                                      201,--vl_sub_aplicacion,
                                      8,----vl_transaccion, --3,     /* DESEMBOLSO */--ojo
                                      null,--149,--vl_subtrans, --Null,  /* TRANSACCION DE INTERFASE */
                                      0, --vl_movimiento  --NO HAY NUM MOV CC ->0
                                      V_DESCRIPCION,
                                      V_FECHA_PROC, --P_FECHA_Sistema,--09/07/2018
                                      V_FECHA_PROC, --P_FECHA_Sistema,--09/07/2018
                                      vp_numero_asiento_dif,
                                      USER,
                                      V_MENSAJE_ERROR2);

           IF V_MENSAJE_ERROR2 IS NOT NULL THEN
                P_ERROR :=  '-5 '|| V_MENSAJE_ERROR2||' #:'||di.no_credito;
                return;
           END IF;
        END IF;

      --> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11
      --> FSN 705555: Empresa 5 BDP sigue logica de empresa 11 Fassil
   	  IF P_EMPRESA IN (v_empresa_Fassil, v_empresa_BDP) THEN
   	    v_interes_castigado_contab := nvl(di.interes_castigado_contab,0) + di.interes_diferidos;
        v_interes_suspenso_contab := nvl(di.interes_suspenso_contab,0) + di.interes_diferidos;
        v_monto_interes_dif      :=nvl(di.monto_interes_dif,0)-di.interes_diferidos;
        v_interes_corriente_contab := nvl(di.interes_corriente_contab,0) - di.interes_diferidos;
        --
          INSERT INTO PR_DET_CAST_PROD_DIF
            (codigo_empresa,                 no_credito,                     id_movimiento,                f_castigo,
             interes_castigado_contab_ant,   interes_suspenso_contab_ant,     monto_interes_dif_ant,       interes_corriente_contab_ant,
             interes_castigado_contab,       interes_suspenso_contab,         monto_interes_dif,           interes_corriente_contab,
             interes_diferidos,              cod_calif,                       dias_mora_cast,              adicionado_por,
             fec_adicion,                    modificado_por,                  fec_modificacion,            observaciones,
             num_asiento)
           VALUES
            ( P_EMPRESA,                    di.no_credito,                    v_id_proceso,                  P_FECHA,
              di.interes_castigado_contab,  di.interes_suspenso_contab,       di.monto_interes_dif,          di.interes_corriente_contab,
             v_interes_castigado_contab,    v_interes_suspenso_contab,        v_monto_interes_dif,           v_interes_corriente_contab,
             di.interes_diferidos,          di.cod_Calif,                     di.num_dias_mora,              user,
             sysdate,                       null,                             null,                         'PR0047',
             vp_numero_asiento_dif);
       END IF;
       --> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11

            --contab......
            DECLARE
               --V_NUMERO_ASIENTO   NUMBER (10);
               V_FECHA_PROC       DATE := P_FECHA;
               V_MENSAJE_ERROR2   VARCHAR2 (500);
               vl_tipc1           NUMBER (16, 5);
               vl_tipc2           NUMBER (16, 5);
               vl_errAplic        NUMBER (18);
               vl_Error           VARCHAR (500);
               vl_diferencia      NUMBER (18, 2);
               vl_monto_contabilizar number(18,2);

            BEGIN
                  /*-----------------------------------------------------------------*/

                  vl_monto_contabilizar:=di.interes_suspenso;/*monto actualizar*/--???????????????
                    ---  SHC : 05/01/2022
                  UPDATE pr_creditos_dif A
                    SET A.INTERES_CASTIGADO_CONTAB = nvl(A.INTERES_CASTIGADO_CONTAB,0) + di.interes_diferidos,
                    A.interes_suspenso_contab = nvl(A.interes_suspenso_contab,0) + di.interes_diferidos,
                    a.monto_interes_dif=nvl(a.monto_interes_dif,0)-di.interes_diferidos,
                    a.interes_corriente_contab = nvl(interes_corriente_contab,0) - di.interes_diferidos
                    WHERE A.cod_empresa=di.cod_empresa AND A.no_credito=di.no_credito;


                  UPDATE pr_creditos_dif_hi A
                    SET A.INTERES_CASTIGADO_CONTAB = nvl(A.INTERES_CASTIGADO_CONTAB,0) + di.interes_diferidos,
                    A.interes_suspenso_contab = nvl(A.interes_suspenso_contab,0) + di.interes_diferidos,
                    a.monto_interes_dif=nvl(a.monto_interes_dif,0)-di.interes_diferidos,
                    a.interes_corriente_contab = nvl(interes_corriente_contab,0) - di.interes_diferidos,
                    a.saldo_interes_dif = a.saldo_interes_dif -di.interes_diferidos
                    WHERE A.cod_empresa=di.cod_empresa AND A.no_credito=di.no_credito and  a.fec_registro_hi = P_FECHA ;

                    ---  SHC : 05/01/2022 FIN
                    /*-----------------------------------------------------------------*/
             IF P_EMPRESA = v_empresa_BUSA THEN
                BEGIN
                    SELECT TP1NRO2, /*Codigo Sub Aplicacion*/
                           TP1NRO3, /*Transaccion*/
                           TP1IMP1 /*Subtransaccion*/
                INTO   vl_sub_aplicacion, vl_transaccion, vl_subtrans
                FROM   param_dinam
                WHERE  tp1cod = P_EMPRESA /*Codigo Empresa*/
                  AND tp1cod1 = 970
                  AND tp1corr1 = 2 /*COMISION AGETIC*/
                  AND TP1NRO1 = P_EMPRESA;
                  --> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11
                  EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                      NULL;
                END;
             END IF;
			  --> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11
               --> FSN 705555: Empresa 5 BDP sigue logica de empresa 11 Fassil
	           IF P_EMPRESA IN (v_empresa_Fassil, v_empresa_BDP) THEN
	      	     vl_empresa_BUSA := P_EMPRESA;
	      	     vl_AD_BUSA      := vp_numero_asiento_dif;
	           END IF;
	          --> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11
                PR.DESEMBOLSOs.PR_INTERFACE_CONTA (P_EMPRESA,
                                     --INTERESES_CASTIGADOS,
                                     vl_empresa_BUSA,
                                     di.NUM_TRAMITE,
                                     V_FECHA_PROC,--:BKFECHA.FECHA_MOVIMIENTO,--to_date('31/03/2020','dd/mm/yyyy'),
                                     220,--200,--         P_TRANSACCION       IN      NUMBER,
                                     '01',--vl_sub_trans,--'01',--         P_SUBTRANS          IN      VARCHAR2,--healvarez--13/06/2020
                                     di.interes_diferidos, --di.interes_corriente,--:BKTotal.capital_diferido,
                                     0,--60000,--:BKTotal.Intereses_diferidos,
                                     0,
                                     0,-- PR.PR_FORMULA1(:BKCREDIT.CODIGO_EMPRESA,:bkCREDIT.NO_CREDITO,:bkcredit.NUM_TRAMITE, P_FECHA,'F10'),--         P_MONTO4             IN      NUMBER,
                                     0,--         P_MONTO5             IN      NUMBER,
                                     0,--         P_MONTO6              IN      NUMBER,
                                     0,-- PR.PR_FORMULA1(:BKCREDIT.CODIGO_EMPRESA,:bkCREDIT.NO_CREDITO,:bkcredit.NUM_TRAMITE, P_FECHA,'C10'),--         P_MONTO4             IN      NUMBER,
                                     0,--         P_MONTO8             IN      NUMBER,
                                     --V_DESCRIPCION|| ' NroCred:'||j.No_credito ,--'PAGO TOTAL DE DIFERIMIENTO No.'||:BKCREDIT.NO_CREDITO,--         P_DESCRIPCION       IN         VARCHAR2,--healvarez-08/07/2020--se adiciona descripcion..
                                     V_DESCRIPCION||': TrDif:'||di.num_tramite|| ' CrDif:'||di.No_credito , -- SHC : 05/01/2022 Productos  Diferidos
                                     '+',--         P_SIGNO            IN        VARCHAR2,
                                     vp_numero_asiento_dif,--         P_AD_ORIGEN         IN OUT     NUMBER,
                                     vl_AD_BUSA,--0,--         P_AD_DESTINO        IN OUT     NUMBER,
                                     vl_Error);
                IF (vl_Error IS NOT NULL) THEN
                    P_ERROR := '-6 '|| vl_Error||' #:'||di.no_credito;
                    return;
                END IF;

                Cg_Utl.Cuadre_Asiento ( P_EMPRESA,
                                    V_FECHA_PROC,
                                    vp_numero_asiento_dif,
                                    vl_diferencia,
                                    V_MENSAJE_ERROR2);

                IF V_MENSAJE_ERROR2 IS NOT NULL THEN
                    P_ERROR := '-7'|| V_MENSAJE_ERROR2||' #:'||di.no_credito ;
                    return;
                END IF;
            END;

   END LOOP;
END;
   -- CASTIGO DE PRODUCTOS TOTALMENTE DIFERIDOS END SHC : 05/01/2022
   ------------------------------------------------------------------------------------
   -- FSN 705555: CASTIGO DE PRODUCTOS DIFERIDOS POST 2025 (Ley 1670)
   -- Tablas: PR_CREDITOS_DIF_POST / pr_cred_dif_post_hi
   ------------------------------------------------------------------------------------
declare
    vl_sw_cabecera_post      NUMBER(5):=0;
    vp_numero_asiento_post   NUMBER (10);
    vl_empresa_BUSA          VARCHAR2(5);
    vl_AD_BUSA               NUMBER(10);
begin
    for di in(
               SELECT h.codigo_empresa cod_empresa,
                      h.no_credito,
                      h.monto_desembolsado,
                      h.saldo_actual,
                      dif.interes_castigado_contab,
                      dif.interes_corriente_contab,
                      dif.monto_interes_dif,
                      dif.interes_suspenso_contab,
                      h.num_dias_mora,
                      h.codigo_moneda,
                     ((((h.intereses_acumulados - h.intereses_castigados + h.intereses_en_suspenso) - h.monto_pagado_intereses)) - h.intereses_en_suspenso ) interes_corriente,
                      (dif.monto_interes_dif - dif.monto_pagado_interes_dif) interes_diferidos,
                      h.intereses_en_suspenso interes_suspenso,
                      h.estado,
                      'D' cod_calif,
                      h.intereses_castigados,
                      h.num_tramite
                FROM pr_creditos_hi h,
                     pr_cred_dif_post_hi dif
                WHERE h.codigo_empresa = p_empresa
                 AND  h.estado not in ('C','N','I','L')
                 AND  h.fec_registro_hi = p_fecha
                 AND dif.cod_empresa=h.codigo_empresa
                 AND dif.fec_registro_hi=h.fec_registro_hi
                 AND dif.no_credito=h.no_credito
                 AND (nvl(dif.monto_interes_dif,0) - nvl(dif.monto_pagado_interes_dif,0)) > 0.01
                 AND nvl(dif.saldo_interes_dif,0) > 0
                 AND h.saldo_actual>0
                 AND EXISTS (SELECT 1
                               FROM  pr_his_calif_x_pr_tramite calif
                             WHERE  calif.cod_empresa = p_empresa
                                and calif.num_proceso = p_num_proceso
                                and calif.num_tramite  = to_number(h.num_tramite)
                                and (calif.cod_calif IN ('D','E','F') or calif.num_dias_mora >90 )  )
                 order by h.num_tramite
      )
   LOOP
       vl_sw_cabecera_post:=vl_sw_cabecera_post+1;
       IF vl_sw_cabecera_post=1 THEN
          V_DESCRIPCION := 'CASTIGO DE PRODUCTOS *DIFERIDOS POST 2025 MORA >90 Y/0 CALIF >D';
            Cg_Utl.Caratula_del_Asiento(P_EMPRESA,
                                        P_AGENCIA,
                                       'BPR',
                                        201,
                                        8,
                                        null,
                                        0,
                                        V_DESCRIPCION,
                                        V_FECHA_PROC,
                                        V_FECHA_PROC,
                                        vp_numero_asiento_post,
                                        USER,
                                        V_MENSAJE_ERROR2);

            IF V_MENSAJE_ERROR2 IS NOT NULL THEN
               P_ERROR := '-8 ' || V_MENSAJE_ERROR2||' #:'||di.no_credito;
               return;
            END IF;
       END IF;

      --> FSN 705555: Empresa 5 BDP y 11 Fassil registran detalle
   	  IF P_EMPRESA IN (v_empresa_Fassil, v_empresa_BDP) THEN
   	    v_interes_castigado_contab := nvl(di.interes_castigado_contab,0) + di.interes_diferidos;
        v_interes_suspenso_contab := nvl(di.interes_suspenso_contab,0) + di.interes_diferidos;
        v_monto_interes_dif      :=nvl(di.monto_interes_dif,0)-di.interes_diferidos;
        v_interes_corriente_contab := nvl(di.interes_corriente_contab,0) - di.interes_diferidos;
        --
          INSERT INTO PR_DET_CAST_PROD_DIF
            (codigo_empresa,                 no_credito,                     id_movimiento,                f_castigo,
             interes_castigado_contab_ant,   interes_suspenso_contab_ant,     monto_interes_dif_ant,       interes_corriente_contab_ant,
             interes_castigado_contab,       interes_suspenso_contab,         monto_interes_dif,           interes_corriente_contab,
             interes_diferidos,              cod_calif,                       dias_mora_cast,              adicionado_por,
             fec_adicion,                    modificado_por,                  fec_modificacion,            observaciones,
             num_asiento)
           VALUES
            ( P_EMPRESA,                    di.no_credito,                    v_id_proceso,                  P_FECHA,
              di.interes_castigado_contab,  di.interes_suspenso_contab,       di.monto_interes_dif,          di.interes_corriente_contab,
             v_interes_castigado_contab,    v_interes_suspenso_contab,        v_monto_interes_dif,           v_interes_corriente_contab,
             di.interes_diferidos,          di.cod_Calif,                     di.num_dias_mora,              user,
             sysdate,                       null,                             null,                         'PR0047-POST',
             vp_numero_asiento_post);
       END IF;

            DECLARE
               vl_Error           VARCHAR (500);
               vl_diferencia      NUMBER (18, 2);
               vl_monto_contabilizar number(18,2);

            BEGIN
                  vl_monto_contabilizar:=di.interes_suspenso;

                  UPDATE PR_CREDITOS_DIF_POST A
                    SET A.INTERES_CASTIGADO_CONTAB = nvl(A.INTERES_CASTIGADO_CONTAB,0) + di.interes_diferidos,
                    A.interes_suspenso_contab = nvl(A.interes_suspenso_contab,0) + di.interes_diferidos,
                    a.monto_interes_dif=nvl(a.monto_interes_dif,0)-di.interes_diferidos,
                    a.interes_corriente_contab = nvl(interes_corriente_contab,0) - di.interes_diferidos
                    WHERE A.cod_empresa=di.cod_empresa AND A.no_credito=di.no_credito;

                  UPDATE pr_cred_dif_post_hi A
                    SET A.INTERES_CASTIGADO_CONTAB = nvl(A.INTERES_CASTIGADO_CONTAB,0) + di.interes_diferidos,
                    A.interes_suspenso_contab = nvl(A.interes_suspenso_contab,0) + di.interes_diferidos,
                    a.monto_interes_dif=nvl(a.monto_interes_dif,0)-di.interes_diferidos,
                    a.interes_corriente_contab = nvl(interes_corriente_contab,0) - di.interes_diferidos,
                    a.saldo_interes_dif = a.saldo_interes_dif -di.interes_diferidos
                    WHERE A.cod_empresa=di.cod_empresa AND A.no_credito=di.no_credito and  a.fec_registro_hi = P_FECHA ;

                IF P_EMPRESA = v_empresa_BUSA THEN
                   BEGIN
                    SELECT TP1NRO2, TP1NRO3, TP1IMP1
                    INTO   vl_sub_aplicacion, vl_transaccion, vl_subtrans
                    FROM   param_dinam
                    WHERE  tp1cod = P_EMPRESA
                      AND tp1cod1 = 970
                      AND tp1corr1 = 2
                      AND TP1NRO1 = P_EMPRESA;
                    EXCEPTION
                      WHEN NO_DATA_FOUND THEN
                        NULL;
                   END;
                END IF;
               --> FSN 705555: Empresa 5 BDP sigue logica de empresa 11 Fassil
	           IF P_EMPRESA IN (v_empresa_Fassil, v_empresa_BDP) THEN
	      	     vl_empresa_BUSA := P_EMPRESA;
	      	     vl_AD_BUSA      := vp_numero_asiento_post;
	           END IF;
                PR.DESEMBOLSOs.PR_INTERFACE_CONTA (P_EMPRESA,
                                     vl_empresa_BUSA,
                                     di.NUM_TRAMITE,
                                     V_FECHA_PROC,
                                     220,
                                     '01',
                                     di.interes_diferidos,
                                     0, 0, 0, 0, 0, 0, 0,
                                     V_DESCRIPCION||': TrDifPost:'||di.num_tramite|| ' CrDifPost:'||di.No_credito ,
                                     '+',
                                     vp_numero_asiento_post,
                                     vl_AD_BUSA,
                                     vl_Error);
                IF (vl_Error IS NOT NULL) THEN
                    P_ERROR :=  '-9 '||vl_error||' #:'||di.no_credito;
                    return;
                END IF;
                Cg_Utl.Cuadre_Asiento ( P_EMPRESA,
                                    V_FECHA_PROC,
                                    vp_numero_asiento_post,
                                    vl_diferencia,
                                    V_MENSAJE_ERROR2);

                IF V_MENSAJE_ERROR2 IS NOT NULL THEN
                    P_ERROR :=  '-10 '|| V_MENSAJE_ERROR2||' #:'||di.no_credito;
                    return;
                END IF;
            END;

   END LOOP;
END;
   -- FSN 705555: CASTIGO DE PRODUCTOS DIFERIDOS POST 2025 END
   ------------------------------------------------------------------------------------
   -- FSN 705555: CASTIGO DE PRODUCTOS TOTALMENTE DIFERIDOS POST 2025 (saldo_actual=0)
   ------------------------------------------------------------------------------------
declare
    vl_sw_cabecera_tpost     NUMBER(5):=0;
    vp_numero_asiento_tpost  NUMBER (10);
    vl_empresa_BUSA          VARCHAR2(5);
    vl_AD_BUSA               NUMBER(10);
begin
    for di in(
            Select h.codigo_empresa cod_empresa,
                   h.no_credito,
                   h.monto_desembolsado, h.saldo_actual,
                   dif.interes_castigado_contab,
                   dif.interes_corriente_contab,
                   dif.monto_interes_dif,
                   dif.interes_suspenso_contab,
                   h.num_dias_mora,
                   h.codigo_moneda,
                   ((((h.intereses_acumulados - h.intereses_castigados + h.intereses_en_suspenso) - h.monto_pagado_intereses)) - h.intereses_en_suspenso ) interes_corriente,
                   (dif.monto_interes_dif - dif.monto_pagado_interes_dif) interes_diferidos,
                   h.intereses_en_suspenso interes_suspenso,
                   h.estado,
                   'D' cod_calif,
                   h.intereses_castigados,
                   h.num_tramite
                FROM PR_CREDITOS_HI     H,
                     pr_cred_dif_post_hi dif
                WHERE h.codigo_empresa = p_empresa
                AND   h.estado not in ('C','N','I','L')
                AND   h.fec_registro_hi = p_fecha
                AND   dif.cod_empresa=H.CODigo_EMPRESA
                AND   dif.fec_registro_hi=H.fec_registro_hi
                AND   dif.no_credito=H.No_credito
                AND   (NVL(dif.MONTO_INTERES_DIF,0) - NVL(dif.MONTO_PAGADO_INTERES_DIF,0)) > 0.01
                AND    NVL(dif.saldo_interes_dif,0) > 0
                AND h.saldo_actual=0
                AND EXISTS (SELECT 1
                              FROM  pr_his_calif_x_pr_tramite calif
                             WHERE  CALIF.COD_EMPRESA = P_EMPRESA
                                AND calif.num_proceso = P_NUM_PROCESO
                                AND calif.num_tramite  = H.num_tramite
                                AND (CALIF.COD_CALIF IN ('D','E','F') OR CALIF.NUM_DIAS_MORA >90 )  )
                ORDER BY H.num_tramite)
   LOOP
      vl_sw_cabecera_tpost:= vl_sw_cabecera_tpost+1;
      IF vl_sw_cabecera_tpost=1 THEN
          V_DESCRIPCION := 'CASTIGO DE PRODUCTOS *TDIFERIDOS POST 2025 MORA >90 Y/0 CALIF >D';
          Cg_Utl.Caratula_del_Asiento(P_EMPRESA,
                                      P_AGENCIA,
                                     'BPR',
                                      201,
                                      8,
                                      null,
                                      0,
                                      V_DESCRIPCION,
                                      V_FECHA_PROC,
                                      V_FECHA_PROC,
                                      vp_numero_asiento_tpost,
                                      USER,
                                      V_MENSAJE_ERROR2);

           IF V_MENSAJE_ERROR2 IS NOT NULL THEN
                P_ERROR :=  '-11 '|| V_MENSAJE_ERROR2||' #:'||di.no_credito;
                return;
           END IF;
        END IF;

      --> FSN 705555: Empresa 5 BDP y 11 Fassil registran detalle
   	  IF P_EMPRESA IN (v_empresa_Fassil, v_empresa_BDP) THEN
   	    v_interes_castigado_contab := nvl(di.interes_castigado_contab,0) + di.interes_diferidos;
        v_interes_suspenso_contab := nvl(di.interes_suspenso_contab,0) + di.interes_diferidos;
        v_monto_interes_dif      :=nvl(di.monto_interes_dif,0)-di.interes_diferidos;
        v_interes_corriente_contab := nvl(di.interes_corriente_contab,0) - di.interes_diferidos;
        --
          INSERT INTO PR_DET_CAST_PROD_DIF
            (codigo_empresa,                 no_credito,                     id_movimiento,                f_castigo,
             interes_castigado_contab_ant,   interes_suspenso_contab_ant,     monto_interes_dif_ant,       interes_corriente_contab_ant,
             interes_castigado_contab,       interes_suspenso_contab,         monto_interes_dif,           interes_corriente_contab,
             interes_diferidos,              cod_calif,                       dias_mora_cast,              adicionado_por,
             fec_adicion,                    modificado_por,                  fec_modificacion,            observaciones,
             num_asiento)
           VALUES
            ( P_EMPRESA,                    di.no_credito,                    v_id_proceso,                  P_FECHA,
              di.interes_castigado_contab,  di.interes_suspenso_contab,       di.monto_interes_dif,          di.interes_corriente_contab,
             v_interes_castigado_contab,    v_interes_suspenso_contab,        v_monto_interes_dif,           v_interes_corriente_contab,
             di.interes_diferidos,          di.cod_Calif,                     di.num_dias_mora,              user,
             sysdate,                       null,                             null,                         'PR0047-POST',
             vp_numero_asiento_tpost);
       END IF;

            DECLARE
               V_FECHA_PROC       DATE := P_FECHA;
               V_MENSAJE_ERROR2   VARCHAR2 (500);
               vl_Error           VARCHAR (500);
               vl_diferencia      NUMBER (18, 2);
               vl_monto_contabilizar number(18,2);

            BEGIN
                  vl_monto_contabilizar:=di.interes_suspenso;

                  UPDATE PR_CREDITOS_DIF_POST A
                    SET A.INTERES_CASTIGADO_CONTAB = nvl(A.INTERES_CASTIGADO_CONTAB,0) + di.interes_diferidos,
                    A.interes_suspenso_contab = nvl(A.interes_suspenso_contab,0) + di.interes_diferidos,
                    a.monto_interes_dif=nvl(a.monto_interes_dif,0)-di.interes_diferidos,
                    a.interes_corriente_contab = nvl(interes_corriente_contab,0) - di.interes_diferidos
                    WHERE A.cod_empresa=di.cod_empresa AND A.no_credito=di.no_credito;

                  UPDATE pr_cred_dif_post_hi A
                    SET A.INTERES_CASTIGADO_CONTAB = nvl(A.INTERES_CASTIGADO_CONTAB,0) + di.interes_diferidos,
                    A.interes_suspenso_contab = nvl(A.interes_suspenso_contab,0) + di.interes_diferidos,
                    a.monto_interes_dif=nvl(a.monto_interes_dif,0)-di.interes_diferidos,
                    a.interes_corriente_contab = nvl(interes_corriente_contab,0) - di.interes_diferidos,
                    a.saldo_interes_dif = a.saldo_interes_dif -di.interes_diferidos
                    WHERE A.cod_empresa=di.cod_empresa AND A.no_credito=di.no_credito and  a.fec_registro_hi = P_FECHA ;

             IF P_EMPRESA = v_empresa_BUSA THEN
                BEGIN
                    SELECT TP1NRO2, TP1NRO3, TP1IMP1
                    INTO   vl_sub_aplicacion, vl_transaccion, vl_subtrans
                    FROM   param_dinam
                    WHERE  tp1cod = P_EMPRESA
                      AND tp1cod1 = 970
                      AND tp1corr1 = 2
                      AND TP1NRO1 = P_EMPRESA;
                    EXCEPTION
                      WHEN NO_DATA_FOUND THEN
                        NULL;
                END;
             END IF;
               --> FSN 705555: Empresa 5 BDP sigue logica de empresa 11 Fassil
	           IF P_EMPRESA IN (v_empresa_Fassil, v_empresa_BDP) THEN
	      	     vl_empresa_BUSA := P_EMPRESA;
	      	     vl_AD_BUSA      := vp_numero_asiento_tpost;
	           END IF;
                PR.DESEMBOLSOs.PR_INTERFACE_CONTA (P_EMPRESA,
                                     vl_empresa_BUSA,
                                     di.NUM_TRAMITE,
                                     V_FECHA_PROC,
                                     220,
                                     '01',
                                     di.interes_diferidos,
                                     0, 0, 0, 0, 0, 0, 0,
                                     V_DESCRIPCION||': TrDifPost:'||di.num_tramite|| ' CrDifPost:'||di.No_credito ,
                                     '+',
                                     vp_numero_asiento_tpost,
                                     vl_AD_BUSA,
                                     vl_Error);
                IF (vl_Error IS NOT NULL) THEN
                    P_ERROR := '-12 '|| vl_Error||' #:'||di.no_credito;
                    return;
                END IF;

                Cg_Utl.Cuadre_Asiento ( P_EMPRESA,
                                    V_FECHA_PROC,
                                    vp_numero_asiento_tpost,
                                    vl_diferencia,
                                    V_MENSAJE_ERROR2);

                IF V_MENSAJE_ERROR2 IS NOT NULL THEN
                    P_ERROR := '-13 '|| V_MENSAJE_ERROR2||' #:'||di.no_credito ;
                    return;
                END IF;
            END;

   END LOOP;
END;
   -- FSN 705555: CASTIGO DE PRODUCTOS TOTALMENTE DIFERIDOS POST 2025 END
--> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11
update parametros_x_empresa
   set valor = to_char(P_FECHA,'dd/mm/yyyy')
 Where abrev_parametro = 'FEC_ULT_CAST_PRO_DIF'
   and cod_empresa      = p_empresa;
--> AQUINTAN; 18/08/2025; FSN 1727 Castigo de productos empresa 11
EXCEPTION
    WHEN OTHERS THEN
        P_ERROR := '-1 '||SQLERRM;

END;

   -- CASTIGO DE PRODUCTOS TOTALMENTE DIFERIDOS END SHC : 05/01/2022
