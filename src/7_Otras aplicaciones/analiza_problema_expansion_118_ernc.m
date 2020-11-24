function analiza_problema_expansion_118_ernc(id_protocolo) 
% a futuro tiene que ir como dato de entrada: id_caso_estudio
tic
nombre_archivo = ['./output/analisis_problema_expansion_118_ernc_', num2str(id_protocolo),'.dat'];
prot = cProtocolo.getInstance(nombre_archivo);

%importa parametros caso de estudio
pParOpt = cParOptimizacionACO;
%pParOpt.carga_datos_caso_estudio(id_caso_estudio);
id_puntos_operacion = 1;
% ...
% hasta aquí carga de datos de caso de estudio

data = genera_datos_ieee_bus_118_ernc(pParOpt, id_puntos_operacion);

% importa datos y crea objetos principales
pSEP = cSistemaElectricoPotencia;
par_sep = cParametrosSistemaElectricoPotencia.getInstance;
sbase_matpower = data.baseMVA;
par_sep.inserta_sbase(sbase_matpower);

pAdmProy = cAdministradorProyectos;
pAdmProy.inserta_nivel_debug(pParOpt.NivelDebugAdmProy);
pAdmProy.inserta_delta_etapa(pParOpt.DeltaEtapa);
pAdmProy.inserta_t_inicio(pParOpt.TInicio);

pAdmSc = cAdministradorEscenarios.getInstance;
pAdmSc.inicializa_escenarios(pParOpt.CantidadEtapas, data.PuntosOperacion(:,2));

importa_problema_optimizacion_tnep_118_ernc(data, pSEP, pAdmProy, pAdmSc, pParOpt);

pAdmProy.genera_indices_proyectos();
pAdmProy.calcula_costo_promedio_proyectos();
disp(strcat('Costo promedio proyectos: ', num2str(pAdmProy.CostoPromedioProyectos)));

if pParOpt.NivelDebugACO > 1
    pAdmProy.imprime_matriz_estados();
end

% inicializa feromonas;
pFerom = cFeromonaACO(pParOpt.CantidadEtapas, pAdmProy.CantidadProyectos);
pFerom.inicializa_feromonas(pParOpt.CantidadEtapas, pAdmProy.CantidadProyectos, pParOpt.ProbabilidadConstruccionInicial);
%pFerom
pFerom.imprime_feromonas(0);

pACO = cOptACO(pSEP, pAdmSc, pAdmProy, pParOpt, pFerom);
pACO.inserta_nivel_debug(pParOpt.NivelDebugACO);
pSEP.imprime_sep(true, pAdmSc); % imprime detallado
%resultados_disponibles = 1;

%pACO.crea_plan_optimo(Plan_optimo_118_bus_15_uprating_ernc);
% pACO.evalua_plan_optimo();
% plan_optimo = pACO.entrega_plan_optimo();
% plan_optimo.imprime_en_detalle(pAdmProy, pParOpt);

%pACO.crea_plan_evaluar(Plan_optimo_118_bus_15_uprating_ernc);
%pACO.evalua_plan_evaluar();
%plan_evaluar = pACO.entrega_plan_evaluar();
%plan_evaluar.imprime_en_detalle(pAdmProy, pParOpt);
%plan_evaluar.imprime();
pACO.analiza_problema_expansion();

tfin = toc