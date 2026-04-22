CREATE OR REPLACE PROCEDURE          pr.PR_CONTAGIO (    P_EMPRESA           IN    VARCHAR2,
                                                P_NUM_PROCESO       IN      NUMBER,
                                                P_FECHA             IN       DATE,
                                                P_ERROR             OUT      VARCHAR2
                                             )
IS
---------------------------- ITERACION
--CM = CAlificacion Manual
--CA = Calificacion Automatica
-- cod_cm_max = la peor calificacon manual
-- cod_calif_max = la peor calificacion del proceso
--DECLARE
    vl_SW  varchar2(2) := 'S';
    --healvarez-05/09/2022--FSN contagio interempresa.
    vl_proc_unico_cont varchar(5);
    vl_proces_inter_emp_nros varchar2(200);
    vl_proces_inter_emp varchar2(200);
    vl_proces_inter_emp1 varchar2(200);
    vl_num number(10);
    vl_conteo  number(5);
    vl_emp1 varchar2(5);
    vl_emp2 varchar2(5);
    vl_emp3 varchar2(5);
    vl_emp4 varchar2(5);
    vl_emp5 varchar2(5);
    vl_proc1 number(8);
    vl_proc2 number(8);
    vl_proc3 number(8);
    vl_proc4 number(8);
    vl_proc5 number(8);
    -------------------------------------------------

BEGIN

P_ERROR:=NULL;

/*-------------------------------------------------------------------------------------*/
                    --healvarez-05/09/2022--FSN contagio interempresa.
                    declare
                        vl_res number(5);
                    begin

                    vl_num:=0;

                    vl_proc_unico_cont:='NO';

                        select valor
                        into vl_proces_inter_emp
                        from parametros_x_empresa
                        where abrev_parametro='CONTAGIO_INTER_EMP';


                        select substr(valor,2,length(valor)-2)
                        into vl_proces_inter_emp1
                        from parametros_x_empresa
                        where abrev_parametro='CONTAGIO_INTER_EMP';



                        vl_conteo:=0;
                        for ii in 1..5
                        loop

                            vl_conteo:=vl_conteo+1;

                                    if vl_conteo=1 then
                                        vl_emp1:=PA.PA_RETORNA_VALOR(vl_proces_inter_emp1, '|', 1);
                                    end if;
                                    if vl_conteo=2 then
                                        vl_emp2:=PA.PA_RETORNA_VALOR(vl_proces_inter_emp1, '|', 2);
                                    end if;
                                    if vl_conteo=3 then
                                        vl_emp3:=PA.PA_RETORNA_VALOR(vl_proces_inter_emp1, '|', 3);
                                    end if;
                                    if vl_conteo=4 then
                                        vl_emp4:=PA.PA_RETORNA_VALOR(vl_proces_inter_emp1, '|', 4);
                                    end if;
                                    if vl_conteo=5 then
                                        vl_emp5:=PA.PA_RETORNA_VALOR(vl_proces_inter_emp1, '|', 5);
                                    end if;

                        end loop;




                        if vl_proces_inter_emp<>'N' then

                            select instr(vl_proces_inter_emp,P_EMPRESA)
                            into vl_res
                            from dual;

                            if vl_res=0 then

                                vl_proc_unico_cont:= 'SI';
                            else
                                vl_proc_unico_cont:= 'NO';

                                /*for j in (select num_proceso from pr_provisiones
                                where fec_ult_calificacion =P_FECHA
                                and instr(vl_proces_inter_emp,'|'||cod_empresa||'|')>0)
                                loop
                                    vl_proces_inter_emp_nros:=vl_proces_inter_emp_nros||j.num_proceso||'|';
                                end loop;
                                vl_proces_inter_emp_nros:='|'||vl_proces_inter_emp_nros;*/

                                vl_conteo:=0;
                                for j in (select num_proceso from pr_provisiones
                                where fec_ult_calificacion =P_FECHA
                                and instr(vl_proces_inter_emp,'|'||cod_empresa||'|')>0)
                                loop
                                vl_conteo:=vl_conteo+1;

                                    if vl_conteo=1 then
                                        vl_proc1:=j.num_proceso;
                                    end if;
                                    if vl_conteo=2 then
                                        vl_proc2:=j.num_proceso;
                                    end if;
                                    if vl_conteo=3 then
                                        vl_proc3:=j.num_proceso;
                                    end if;
                                    if vl_conteo=4 then
                                        vl_proc4:=j.num_proceso;
                                    end if;
                                    if vl_conteo=5 then
                                        vl_proc5:=j.num_proceso;
                                    end if;

                                end loop;



                            end if;

                        else
                            vl_proc_unico_cont:= 'SI';
                        end if;

                    exception when others then
                        vl_proc_unico_cont:= 'SI';
                    end;

    while (nvl(vl_SW,'N') = 'S')

    LOOP


    for I in (
            SELECT cod_persona, max(calif_cm) cod_cm_max, min(calif_cm) cod_cm_min , max(cod_calif)cod_calif_max , min(cod_calif) cod_calif_min, max(tipo) tipo_max, min(tipo) tipo_min
            FROM (
            select
            calif.sal_operacion,--healvarez--12/2022
            PERTRA.COD_PERSONA , CALIF.COD_CALIF, CALIF.NUM_TRAMITE, ASFI.COD_SBEF,
            (case when ASFI.COD_SBEF in  ('P0','C3','P5','P6','C0') then 'CM' else 'AU' end) TIPO,
            --(case when ASFI.COD_SBEF in  ('P0','C3','P5','P6','C0') then cod_calif else null end) CALIF_CM
            (case when ASFI.COD_SBEF in  ('P0','C3','P5','P6','C0') and round(decode(tra.cod_moneda,1,calif.sal_operacion/6.86,2,calif.sal_operacion,calif.sal_operacion),2)>400000 then cod_calif--healvarez--12/2022
            when ASFI.COD_SBEF in  ('P0','C3','P5','P6','C0') and round(decode(tra.cod_moneda,1,calif.sal_operacion/6.86,2,calif.sal_operacion,calif.sal_operacion),2)<=400000 and TRA.COD_EMPRESA='5' THEN cod_calif--healvarez--12/2022
            when ASFI.COD_SBEF in  ('P0','C3','P5','P6','C0') and TRA.COD_EMPRESA not in('5') THEN cod_calif
            else null end) CALIF_CM--healvarez--12/2022
            from pr_his_calif_x_pr_tramite calif
            inner join pr_tramite tra
            on TRA.COD_EMPRESA = CALIF.COD_EMPRESA and TRA.NUM_TRAMITE = CALIF.NUM_TRAMITE
            inner join pr_tip_producto prod
            on PROD.COD_EMPRESA = TRA.COD_EMPRESA and PROD.COD_TIP_OPERACION = TRA.COD_TIP_OPERACION and PROD.COD_TIP_PRODUCTO = TRA.COD_TIP_PRODUCTO
            inner join personas_x_pr_tramite pertra
            on CALIF.COD_EMPRESA = PERTRA.COD_EMPRESA and CALIF.NUM_TRAMITE = PERTRA.NUM_TRAMITE
            inner join pr_tip_credito_super asfi
            on ASFI.COD_EMPRESA = tra.COD_EMPRESA and ASFI.COD_TIP_CRED_S = nvl(tra.COD_TIP_CRED_S, PROD.COD_TIP_CRED_S)  --and ASFI.COD_SBEF in ('P0','C3','P5','P6','C0')
            --where calif.cod_empresa = P_EMPRESA and calif.num_proceso = P_NUM_PROCESO
            --healvarez--segun fsn contagio interempresas.
            where (calif.cod_empresa = P_EMPRESA and calif.num_proceso = P_NUM_PROCESO and vl_proc_unico_cont='SI')
            --or ( instr(vl_proces_inter_emp,'|'||calif.cod_empresa||'|')>0 and instr(vl_proces_inter_emp_nros,'|'||to_char(calif.num_proceso)||'|')>0 and vl_proc_unico_cont='NO')
            or ( calif.cod_empresa in(vl_emp1,vl_emp2,vl_emp3,vl_emp4,vl_emp5) and calif.num_proceso in(vl_proc1,vl_proc2,vl_proc3,vl_proc4,vl_proc5) and vl_proc_unico_cont='NO')
            ---------------------------------------------
            )Q
            group by cod_persona
            having (max(cod_calif)<> min(cod_calif) or max(tipo)<> min(tipo)) and not (max(calif_cm) = min(calif_cm) and max(cod_calif)= min(cod_calif) and max(calif_cm)=min(cod_calif) )
    ) LOOP

    vl_num:=vl_num+1;



        update pr_his_calif_x_pr_tramite c2
        set cod_calif = nvl(i.cod_cm_max, i.cod_calif_max)  -- la peor calificacion respetando la calificacion manual
        --where cod_empresa = P_EMPRESA and num_proceso = P_NUM_PROCESO
        --healvarez--segun fsn contagio interempresas.
            where ( --healvarez--03/07/2023
            (cod_empresa = P_EMPRESA and num_proceso = P_NUM_PROCESO and vl_proc_unico_cont='SI')
            --or ( instr(vl_proces_inter_emp,'|'||cod_empresa||'|')>0 and instr(vl_proces_inter_emp_nros,'|'||to_char(num_proceso)||'|')>0 and vl_proc_unico_cont='NO')
            or ( cod_empresa in(vl_emp1,vl_emp2,vl_emp3,vl_emp4,vl_emp5) and num_proceso in(vl_proc1,vl_proc2,vl_proc3,vl_proc4,vl_proc5) and vl_proc_unico_cont='NO')
            )--HEALVAREZ--03/07/2023
        ---------------------------------------------
        and
        exists (select 1 from  personas_x_pr_tramite  pertra
                where PERTRA.COD_EMPRESA = C2.COD_EMPRESA and PERTRA.NUM_TRAMITE = c2.num_tramite and PERTRA.COD_PERSONA = i.cod_persona);

        --select * from pr_calif_x_cliente calif

        /*update pr_calif_x_cliente calif---healvarez 25/05/2023
        set CALIF.COD_CALIF = nvl(i.cod_cm_max, i.cod_calif_max)  -- la peor calificacion respetando la calificacion manual
        --where cod_empresa = P_EMPRESA
        --healvarez--segun fsn contagio interempresas.
            where (cod_empresa = P_EMPRESA and vl_proc_unico_cont='SI')
            --or ( instr(vl_proces_inter_emp,'|'||cod_empresa||'|')>0 and vl_proc_unico_cont='NO')
            or ( calif.cod_empresa in(vl_emp1,vl_emp2,vl_emp3,vl_emp4,vl_emp5) and vl_proc_unico_cont='NO')
        ---------------------------------------------
        and fec_calif = P_FECHA
        --and CALIF.COD_EMPRESA = i.cod_persona --- ANIBANEZ 27/04/2020  incluir la condicional de codigo de cliente para corregir problema de calificacion repetida--HEALVAREZ--01/2023--se comenta porque esta mal planteado.
        and calif.COD_PERSONA=i.cod_persona;*/--HEALVAREZ--01/2023--CAMBIOS SEGUN fsn.
        /*and exists (select 1 from personas_x_pr_tramite pertra
                    where PERTRA.COD_EMPRESA = calif.COD_EMPRESA and PERTRA.COD_PERSONA = i.cod_persona );*/--HEALVAREZ--01/2023, se quita porque no es funcional, cambios segun FSN.


        --optimizado ---- healvarez 25/05/2023
        /* Formatted on 25/5/2023 11:56:00 (QP5 v5.256.13226.35538) %HEALVAREZ% */
        UPDATE PR_CALIF_X_CLIENTE CALIF
           SET CALIF.COD_CALIF = NVL (i.cod_cm_max, i.cod_calif_max)
         WHERE     (   (COD_EMPRESA = P_EMPRESA AND vl_proc_unico_cont = 'SI')
                    OR (    COD_EMPRESA IN (vl_emp1,
                                            vl_emp2,
                                            vl_emp3,
                                            vl_emp4,
                                            vl_emp5)
                        AND vl_proc_unico_cont = 'NO'))
               AND FEC_CALIF = P_FECHA
               AND CALIF.COD_PERSONA = i.cod_persona
               AND ROWNUM <= 5;

        ------------------------------


        --select * from pr_consolidado_creditos_his consol
        update pr_consolidado_creditos_his consol
        set calificacion =nvl(i.cod_cm_max, i.cod_calif_max)  -- la peor calificacion respetando la calificacion manual
        --where consol.cod_empresa = P_EMPRESA
        --healvarez--segun fsn contagio interempresas.
            where ((consol.cod_empresa = P_EMPRESA and vl_proc_unico_cont='SI')
            --or ( instr(vl_proces_inter_emp,'|'||consol.cod_empresa||'|')>0 and vl_proc_unico_cont='NO')
            or ( consol.cod_empresa in(vl_emp1,vl_emp2,vl_emp3,vl_emp4,vl_emp5) and vl_proc_unico_cont='NO'))
        ---------------------------------------------
        and CONSOL.fecha_corte = P_FECHA
        and exists (select 1 from personas_x_pr_tramite pertra
                    where PERTRA.COD_EMPRESA = CONSOL.COD_EMPRESA and PERTRA.NUM_TRAMITE = CONSOL.NUM_TRAMITE and PERTRA.COD_PERSONA = i.cod_persona );



    END LOOP;

            vl_SW := 'N'; --- reinicilizacion de variable

            SELECT max('S') into vl_SW
            FROM (
                SELECT cod_persona, max(calif_cm) cod_cm_max, min(calif_cm) cod_cm_min , max(cod_calif)cod_calif_max , min(cod_calif) cod_calif_min, max(tipo) tipo_max, min(tipo) tipo_min
                FROM (
                select  PERTRA.COD_PERSONA , CALIF.COD_CALIF, CALIF.NUM_TRAMITE, ASFI.COD_SBEF, (case when ASFI.COD_SBEF in  ('P0','C3','P5','P6','C0') then 'CM' else 'AU' end) TIPO,
                --(case when ASFI.COD_SBEF in  ('P0','C3','P5','P6','C0') then cod_calif else null end) CALIF_CM
                (case when ASFI.COD_SBEF in  ('P0','C3','P5','P6','C0') and round(decode(tra.cod_moneda,1,calif.sal_operacion/6.86,2,calif.sal_operacion,calif.sal_operacion),2)>400000 then cod_calif--healvarez--12/2022
                when ASFI.COD_SBEF in  ('P0','C3','P5','P6','C0') and round(decode(tra.cod_moneda,1,calif.sal_operacion/6.86,2,calif.sal_operacion,calif.sal_operacion),2)<=400000 and TRA.COD_EMPRESA='5' THEN cod_calif--healvarez--12/2022
                when ASFI.COD_SBEF in  ('P0','C3','P5','P6','C0') and TRA.COD_EMPRESA not in('5') THEN cod_calif
                else null end) CALIF_CM--healvarez--12/2022
                from pr_his_calif_x_pr_tramite calif
                inner join pr_tramite tra
                on TRA.COD_EMPRESA = CALIF.COD_EMPRESA and TRA.NUM_TRAMITE = CALIF.NUM_TRAMITE
                inner join pr_tip_producto prod
                on PROD.COD_EMPRESA = TRA.COD_EMPRESA and PROD.COD_TIP_OPERACION = TRA.COD_TIP_OPERACION and PROD.COD_TIP_PRODUCTO = TRA.COD_TIP_PRODUCTO
                inner join personas_x_pr_tramite pertra
                on CALIF.COD_EMPRESA = PERTRA.COD_EMPRESA and CALIF.NUM_TRAMITE = PERTRA.NUM_TRAMITE
                inner join pr_tip_credito_super asfi
                on ASFI.COD_EMPRESA = tra.COD_EMPRESA and ASFI.COD_TIP_CRED_S = nvl(tra.COD_TIP_CRED_S, PROD.COD_TIP_CRED_S) --and ASFI.COD_SBEF in ('P0','C3','P5','P6','C0')
                --where calif.cod_empresa = P_EMPRESA and calif.num_proceso = P_NUM_PROCESO
                --healvarez--segun fsn contagio interempresas.
                where (calif.cod_empresa = P_EMPRESA and calif.num_proceso = P_NUM_PROCESO and vl_proc_unico_cont='SI')
                --or ( instr(vl_proces_inter_emp,'|'||calif.cod_empresa||'|')>0 and instr(vl_proces_inter_emp_nros,'|'||to_char(calif.num_proceso)||'|')>0 and vl_proc_unico_cont='NO')
                or ( calif.cod_empresa in(vl_emp1,vl_emp2,vl_emp3,vl_emp4,vl_emp5) and calif.num_proceso in(vl_proc1,vl_proc2,vl_proc3,vl_proc4,vl_proc5) and vl_proc_unico_cont='NO')
                ---------------------------------------------
                )Q
                group by cod_persona
                having (max(cod_calif)<> min(cod_calif) or max(tipo)<> min(tipo)) and not (max(calif_cm) = min(calif_cm) and max(cod_calif)= min(cod_calif) and max(calif_cm)=min(cod_calif) )
            ) Q1;



    END LOOP;  --- iterancion hasta que no existe mas casos de involucrados con la contaminacion

EXCEPTION
    WHEN OTHERS THEN
        P_ERROR := SQLERRM;
END;
