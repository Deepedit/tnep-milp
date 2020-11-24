function main_milp_n(varargin)
    if ~isdeployed
%       cd '/home/ralvarez/TNEP_Actual'
%       addpath('/home/apps/xpressmp/8.4.4/matlab/')
%       addpath(genpath('/home/ralvarez/TNEP_Actual'))
    end

    if nargin > 0
        caso_estudio = varargin{1};
        %caso_estudio = str2double(caso_estudio);
    else
        caso_estudio = 1;
    end
    pParOpt = cParOptimizacionMILP;
    if caso_estudio > 0
        importa_caso_estudio_milp(pParOpt, caso_estudio); %1 indica el caso de estudio
    else
        importa_caso_estudio_milp(pParOpt); %1 indica el caso de estudio
    end
    
    %nombres archivos
    nombre_archivo = obten_nombres_archivos_caso_estudio(pParOpt, caso_estudio);
    prot = cProtocolo.getInstance(nombre_archivo);

    if pParOpt.IdEscenario == 3 && pParOpt.IdPuntosOperacion == 10 && pParOpt.ConsideraReconductoring
        if exist('aaadatos_caso_estudio_8y_5d_s3_ur.mat') == 2
        	datos = load('aaadatos_caso_estudio_8y_5d_s3_ur.mat');
            data = datos.data;
        else
            data = genera_datos_excel_generico(pParOpt);
        end
    elseif pParOpt.IdEscenario == 1 && pParOpt.IdPuntosOperacion == 6 && pParOpt.ConsideraReconductoring
        if exist('aaadatos_caso_estudio_ur_s1_po6.mat') == 2
        	datos = load('aaadatos_caso_estudio_ur_s1_po6.mat');
            data = datos.data;
        else
            data = genera_datos_excel_generico(pParOpt);
        end
    else
        data = genera_datos_excel_generico(pParOpt);
    end
    pParOpt.CantidadPuntosOperacion = data.CantidadPuntosOperacion;
    pParOpt.CantidadEscenarios = data.CantidadEscenarios;
    
%    NivelDebug = 2;
%    if strcmp(pParOpt.NombreSistema, 'Garver1')
%        data = garver_TNEP_caso_1;
%    elseif strcmp(pParOpt.NombreSistema, 'Garver2')
%        data = garver_TNEP_caso_2;
%    elseif strcmp(pParOpt.NombreSistema, './input/DataGarverERNC/GarverERNC.xlsx')
%    else
%        data = genera_datos_excel_generico(pParOpt);
%    else
%        data = genera_datos_ieee_bus_118_ernc(pParOpt);
%    end
    
    % importa datos y crea objetos principales
    pSEP = cSistemaElectricoPotencia;    
    par_sep = cParametrosSistemaElectricoPotencia.getInstance;
    sbase_matpower = data.baseMVA;
    par_sep.inserta_sbase(sbase_matpower);

    pAdmProy = cAdministradorProyectos;
    pAdmProy.inserta_nivel_debug(pParOpt.NivelDebug);
    pAdmProy.inserta_delta_etapa(pParOpt.DeltaEtapa);
    pAdmProy.inserta_t_inicio(pParOpt.TInicio);

    pAdmSc = cAdministradorEscenarios.getInstance;
%    pAdmSc.inicializa_escenarios(data.Escenarios(:,1), data.Escenarios(:,2), pParOpt.CantidadEtapas, data.PuntosOperacion(:,1), data.PuntosOperacion(:,2));
    importa_problema_optimizacion_generico(data, pSEP, pAdmProy, pAdmSc, pParOpt);
    
%    if strcmp(pParOpt.NombreSistema, 'Garver1') || strcmp(pParOpt.NombreSistema, 'Garver2')
%        importa_problema_optimizacion_tnep_garver(data, pSEP, pAdmProy, pAdmSc, pParOpt);
%    elseif strcmp(pParOpt.NombreSistema, './input/DataGarverERNC/GarverERNC.xlsx')
%        importa_problema_optimizacion_generico(data, pSEP, pAdmProy, pAdmSc, pParOpt);
%    else
%        importa_problema_optimizacion_generico(data, pSEP, pAdmProy, pAdmSc, pParOpt);
%        importa_problema_optimizacion_tnep_118_ernc(data, pSEP, pAdmProy, pAdmSc, pParOpt);
%    end

    if pParOpt.NivelDebug > 1
        pAdmProy.imprime_matriz_estados();
    end

    pMILP = cOptMILPN(pSEP, pAdmSc, pAdmProy, pParOpt);
 %   pMILP.iNivelDebug = 2;
        
  %  if strcmp(pParOpt.Solver, 'FICO')
  %      pMILP.ingresa_nombres_archivos_fico(nombre_archivo_modelo_fico,nombre_resultado_modelo_fico);
  %  end

    %evalúa solución
%     sol_a_evaluar_escenario_1 = [1 12; 1 13; 1 14; 1 25; 1 26; 1 27; 1 89; 1 97; 3 41; 3 50; 3 66; 4 4; 4 6; 4 17; 4 21; 4 46; 4 55; 5 3; 5 5; 5 16; 5 18; 5 39; 6 36]; 
%     sol_a_evaluar_escenario_2 = [1 12; 1 13; 1 14; 1 25; 1 26; 1 27; 1 89; 1 97; 2 10; 2 11; 2 23; 2 24; 2 80; 3 84; 3 116; 3 124; 5 112; 6 50; 6 133; 7 66; 7 9;7 22;  7 75;  8 41;  8 131; 9 55;  9 113]; 
%     sol_a_evaluar = [ones(length(sol_a_evaluar_escenario_1), 1) sol_a_evaluar_escenario_1; 2*ones(length(sol_a_evaluar_escenario_2), 1) sol_a_evaluar_escenario_2];
%     sol_a_evaluar_escenario_1 = [1 12; 1 13; 1 14; 1 25; 1 26; 1 27; 1 89; 1 97; 3 41; 3 50; 3 66; 4 4; 4 6; 4 17; 4 21; 4 46; 4 55; 5 3; 5 5; 5 16; 5 18; 5 39; 6 36]; 
%	sol_a_evaluar = [1 1 16; 1 1 19; 1 1 34; 1 1 39; 1 3 41; 1 7 35; 1 9 17]; % optimo mcmc
%	sol_a_evaluar = [1 1 16; 1 1 19; 1 1 34; 1 1 39; 1 3 41; 1 8 35; 1 9 26]; % optimo MILP
%	sol_a_evaluar = [1 1 16; 1 1 19; 1 1 34; 1 1 39; 1 3 41; 1 7 26; 1 9 35]; % optimo mcmc
%	sol_a_evaluar = [1 1 30; 1 1 19; 1 1 34; 1 1 10; 1 1 26; 1 1 27; 1 1 28; 1 1 29;1 1 11;1 1 16;1 2 20;1 5 35;1 6 17;1 9 31]; % optimo mcmc
    
%    pMILP.inserta_solucion_a_evaluar(sol_a_evaluar);

    
    pMILP.escribe_problema_optimizacion();
    if pParOpt.imprime_problema_optimizacion() && ~strcmp(pParOpt.Solver,'FICO')
        pMILP.imprime_problema_optimizacion();
    end
    %tic
    %pMILP.calcula_costos_operacion_sin_restricciones();
    %pMILP.imprime_plan_operacion_sin_restricciones();
disp(pParOpt.MaxGap)    
parfor i = 1:10
    j = i;
%    disp(i)
end
    
    pMILP.optimiza();
    %disp(['Tiempo en resolver problema optimizacion: ' num2str(toc)])
    
    pMILP.imprime_plan_optimo();
    pMILP.imprime_resultados_variables_al_limite();

    % evalua plan óptimo en detalle
%     plan_optimo = pMILP.entrega_plan_optimo();
% 
%     
%     cantidad_etapas = pParOpt.CantidadEtapas;
%     cantidad_escenarios = pParOpt.CantidadEscenarios;
%     for escenario = 1:cantidad_escenarios
%         sep = pSEP.crea_copia();
%         for etapa = 1:cantidad_etapas
%             for j = 1:length(plan_optimo{escenario}.Plan(etapa).Proyectos)
%                 indice = plan_optimo{escenario}.Plan(etapa).Proyectos(j);
%                 proyecto = pAdmProy.entrega_proyecto(indice);
%                 sep.agrega_proyecto(proyecto);
%             end
%             if etapa == 1
%                 pParOpt.Solver = 'Xpress';
%                 pOPF = cDCOPF(sep, pAdmSc, pParOpt);
%                 pOPF.inserta_resultados_en_sep(false);
%                 pOPF.inserta_etapa(etapa);
%             else
%                 pOPF.actualiza_etapa(etapa);
%             end
%             pOPF.inserta_caso_estudio(['sol_milp_escenario' num2str(escenario)]);
%             pOPF.calcula_despacho_economico();
%             pOPF.entrega_evaluacion().imprime_resultados(['Evaluacion milp etapa ' num2str(etapa)]);
%         end
%     end
    prot.cierra_archivo();
end

function nombre_archivo = obten_nombres_archivos_caso_estudio(pParOpt, caso_estudio)
    nombre_archivo = ['./output/' pParOpt.Output , '_', num2str(caso_estudio), '.dat'];
    nombre_sistema = pParOpt.NombreSistema;
    text = strcat(['TNEP ' nombre_sistema]);
    disp(text);
end
