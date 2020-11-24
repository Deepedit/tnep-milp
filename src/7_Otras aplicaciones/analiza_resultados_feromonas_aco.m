caso_estudio = 2;
max_iter = 50;
proyectos_optimos = [2 6 13 15 37 39 71 167 205 75 17 41 55];
pParOpt = cParOptimizacionACO;
importa_caso_estudio_aco(pParOpt, caso_estudio); %1 indica el caso de estudio


if strcmp(pParOpt.NombreSistema, 'Garver1')
    if pParOpt.ConsideraReconductoring || pParOpt.ConsideraCompensacionSerie || pParOpt.ConsideraVoltageUprating
        nombre_archivo = ['./output/prot_resultados_fer_aco_garver1_ur_', num2str(caso_estudio), '.dat'];
    else
        nombre_archivo = ['./output/prot_resultados_fer_aco_garver1_base_', num2str(caso_estudio), '.dat'];
    end
elseif strcmp(pParOpt.NombreSistema, 'Garver2')
    if pParOpt.ConsideraReconductoring || pParOpt.ConsideraCompensacionSerie || pParOpt.ConsideraVoltageUprating
        nombre_archivo = ['./output/prot_resultados_fer_aco_garver2_ur_', num2str(caso_estudio), '.dat'];
    else
        nombre_archivo = ['./output/prot_resultados_fer_aco_garver2_base_', num2str(caso_estudio), '.dat'];
    end
else
    if pParOpt.ConsideraReconductoring || pParOpt.ConsideraCompensacionSerie || pParOpt.ConsideraVoltageUprating
        nombre_archivo = ['./output/prot_resultados_fer_aco_118_ernc_ur_', num2str(caso_estudio), '.dat'];
    else
        nombre_archivo = ['./output/prot_resultados_fer_aco_118_ernc_base_', num2str(caso_estudio), '.dat'];
    end

end

prot = cProtocolo.getInstance(nombre_archivo);
id_puntos_operacion = pParOpt.IdPuntosOperacion;

if strcmp(pParOpt.NombreSistema, 'Garver1')
    data = garver_TNEP_caso_1;
elseif strcmp(pParOpt.NombreSistema, 'Garver2')
    data = garver_TNEP_caso_2;
else
    data = genera_datos_ieee_bus_118_ernc(pParOpt, id_puntos_operacion, pParOpt.NombreSistema);
end


% importa datos y crea objetos principales
pSEP = cSistemaElectricoPotencia;    
par_sep = cParametrosSistemaElectricoPotencia.getInstance;
sbase = data.baseMVA;
par_sep.inserta_sbase(sbase);

pAdmProy = cAdministradorProyectos;
pAdmProy.inserta_nivel_debug(pParOpt.NivelDebugAdmProy);
pAdmProy.inserta_delta_etapa(pParOpt.DeltaEtapa);
pAdmProy.inserta_t_inicio(pParOpt.TInicio);

pAdmSc = cAdministradorEscenarios.getInstance;
pAdmSc.inicializa_escenarios(pParOpt.CantidadEtapas, data.PuntosOperacion(:,2));

if strcmp(pParOpt.NombreSistema, 'Garver1') || strcmp(pParOpt.NombreSistema, 'Garver2')
    importa_problema_optimizacion_tnep_garver(data, pSEP, pAdmProy, pAdmSc, pParOpt);
else
    importa_problema_optimizacion_tnep_118_ernc(data, pSEP, pAdmProy, pAdmSc, pParOpt);
end

pAdmProy.genera_indices_proyectos();
pAdmProy.calcula_costo_promedio_proyectos();
%disp(strcat('Costo promedio proyectos: ', num2str(pAdmProy.CostoPromedioProyectos)));


proy_sin_feromonas = [];
inicio = true;
for i = 1:1000
    if i > 1
        clear pFerom
        clear pACO
    end
    
    path = 'C:\Users\ra\Desktop\ram\Nuevo_desde_robo\Publicaciones\201703 - Ant Colony Optimization for Multistage TNEP\Resultados\Nuevos resultados\Nuevos Garver con y sin ur';
    if exist([path '\TNEP_ACO_Garver_1_UR_Caso_2_iter_' num2str(i) '.mat'],'file') == 2
        resultados_parciales = load([path '\TNEP_ACO_Garver_1_UR_Caso_2_iter_' num2str(i)]);

        %if NivelDebug > 1
        %    pAdmProy.imprime_matriz_estados();
        %end
        % inicializa feromonas;
        pFerom = cFeromonaACO(pParOpt.CantidadEtapas, pAdmProy.CantidadProyectos);
        pFerom.inicializa_feromonas(pParOpt.CantidadEtapas, pAdmProy.CantidadProyectos, pParOpt.ProbabilidadConstruccionInicial);
        pFerom.imprime_feromonas(0);

        pACO = cOptACO(pSEP, pAdmSc, pAdmProy, pParOpt, pFerom);
        pACO.inserta_nivel_debug(pParOpt.NivelDebugACO);
        pACO.inserta_id_computo(1);

        pACO.carga_resultados_parciales(resultados_parciales, max_iter);

        % identifica proyectos sin feromonas
        fer_no_construccion = pFerom.entrega_feromonas_no_construccion();
        max_fer_no_construccion = max(fer_no_construccion);
        
        proyectos_expansion = pAdmProy.entrega_proyectos();
        todos_los_proyectos = 1:1:length(proyectos_expansion);
        if inicio == true
            inicio = false;
            proy_sin_feromonas = todos_los_proyectos;
        end
        
        proyectos_sin_feromonas_caso = todos_los_proyectos(fer_no_construccion == max_fer_no_construccion);
        proy_sin_feromonas = proy_sin_feromonas(ismember(proy_sin_feromonas,proyectos_sin_feromonas_caso));
        if sum(ismember(proyectos_optimos, proy_sin_feromonas)) == 0
            disp('todos los proyectos optimos tienen feromonas')
            break;
        end
%        proyectos_sin_feromonas_caso = proyectos_expansion(fer_no_construccion == max_fer_no_construccion);
%        proyectos_con_feromonas_caso = proyectos_expansion(fer_no_construccion ~= max_fer_no_construccion);

%        pAdmProy.imprime_proyectos_seleccionados(proyectos_sin_feromonas_caso,'Proyectos sin feromonas:\n');
%        pAdmProy.imprime_proyectos_seleccionados(proyectos_con_feromonas_caso,'Proyectos con feromonas:\n');
    end
end

proyectos_expansion = pAdmProy.entrega_proyectos();
proyectos_expansion_sin_feromonas = proyectos_expansion(proy_sin_feromonas);
pAdmProy.imprime_proyectos_seleccionados(proyectos_expansion_sin_feromonas,'Proyectos sin feromonas:\n');
