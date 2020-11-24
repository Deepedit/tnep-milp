classdef cOptMCMC < handle
    properties
        % punteros a clases
        pSEP = cSistemaElectricoPotencia.empty
        pAdmProy = cAdministradorProyectos.empty
        pParOpt = cParOptimizacionMCMC.empty
        pAdmSc = cAdministradorEscenarios.empty
        
        CostosOperacionSinRestriccion
        NPVCostosOperacionSinRestriccion

        CostosOperacionSinExpansion
        NPVCostosOperacionSinExpansion
        
        ResultadosGlobales
        
        PlanOptimo = cPlanExpansion.empty  % plan óptimo calculado de otra parte e importado aquí
        FObjPlanOptimo                     % NPV Costos inversion + congestion
        TotexPlanOptimo                    % NPV Costos inversion + operacion
        PlanEvaluar = cPlanExpansion.empty  % plan para realizar pruebas
        
        %estructuras
        PlanesValidos

        % CapacidadDecisionesPrimariasPorCadenas: por cada corredor, indica la
        % capacidad en cada etapa. NxM donde N = cant corr, es la cantidad de etapas. Por cada fila se guardan los
        % CapacidadDecisionesPrimariasPorCadenas{2}(3,5) indica la capacidad del
        % corredor 2, para la cadena 3 en la etapa 5
        CapacidadDecisionesPrimariasPorCadenas = []
        CantDecisionesPrimarias = 0
        CantCadenas = 0
        
        ExistenResultadosParciales = false
        ItResultadosParciales = 0
        %Nivel de debug
        iNivelDebug = 1
        
        IdArchivoSalida = 0
    end
    
    methods
        function this = cOptMCMC(sep, AdmSc, adm_proyectos, par_optimizacion)
            this.pSEP = sep;
            this.pAdmSc = AdmSc;
            this.pAdmProy = adm_proyectos;
            this.pParOpt = par_optimizacion;
            this.CantDecisionesPrimarias = adm_proyectos.entrega_cantidad_decisiones_primarias();
            this.CantCadenas = this.pParOpt.CantidadCadenas;
        end
                
        function inserta_nivel_debug(this, nivel)
            this.iNivelDebug = nivel;
        end

        function optimiza(this)
            t_inicio_optimizacion = clock;
            prot = cProtocolo.getInstance;
            prot.imprime_texto('Comienzo optimizacion heuristica MC-MC');
            prot.imprime_texto(['Cantidad etapas: ' num2str(this.pParOpt.CantidadEtapas)]);
            prot.imprime_texto(['Cantidad escenarios: ' num2str(this.pParOpt.CantidadEscenarios)]);
            prot.imprime_texto(['Considera incertidumbre: ' num2str(this.pParOpt.ConsideraIncertidumbre)]);
            prot.imprime_texto(['Cantidad realizaciones escenarios: ' num2str(this.pParOpt.CantidadSimulacionesEscenarios)]);

            this.calcula_costos_operacion_sin_restriccion();
            
            prot.imprime_texto(['NPV Costos oper. sin restriccion: ' num2str(this.NPVCostosOperacionSinRestriccion)]);
            if ~isempty(this.PlanOptimo)
                this.FObjPlanOptimo = this.PlanOptimo.TotexTotal-this.NPVCostosOperacionSinRestriccion;
                this.TotexPlanOptimo = this.PlanOptimo.TotexTotal;
            end
            
            if this.pParOpt.ConsideraIncertidumbre
                % TODO: Debiera cambiarse a sigma por parámetro
                this.optimiza_con_incertidumbre_sigma_unico_computo_paralelo();
            else
                res_cadenas = this.optimiza_deterministico();
            end
            this.ResultadosGlobales.TiempoTotalSimulacion = etime(clock, t_inicio_optimizacion);
            this.exporta_resultados(res_cadenas);
        end
        
        function cadenas = optimiza_deterministico(this)
            nivel_debug = this.pParOpt.NivelDebug;
            
            cadenas = this.inicializa_cadenas();

            % comienza proceso de markov
            this.imprime_estadisticas(0, 0, 0, 0);
            max_cantidad_pasos = this.pParOpt.MaxCantidadPasos;
                        
            t_inicio_proceso = clock;
            t_inicial_iteracion = clock;
            t_acumulado = etime(clock, t_inicio_proceso);
            paso_actual = 1;

            siguiente_paso_actualizacion = this.pParOpt.PasoActualizacion;

            if this.iNivelDebug > 1
                texto = sprintf('%-7s %-5s %-7s %-15s %-15s %-15s %-10s %-10s %-10s %-10s','Cad','Paso', 'Valido', 'TotexAct', 'TotexAnt', 'TotexBest','GapA', 'GapB', 'dt');
                fprintf([texto '\n']);
            end
            while paso_actual < max_cantidad_pasos && t_acumulado < this.pParOpt.MaxTiempoSimulacion
                paso_actual = paso_actual + 1;
                
                cadenas = this.mapea_espacio(cadenas, paso_actual, t_inicio_proceso, nivel_debug);
                                
                if paso_actual == siguiente_paso_actualizacion
                    dt_iteracion = etime(clock, t_inicial_iteracion);
                    t_acumulado = etime(clock, t_inicio_proceso);
                    t_inicial_iteracion = clock;
                    
                    % imprime estadísticas de iteración actual
                    this.imprime_estadisticas(cadenas, paso_actual, dt_iteracion, t_acumulado);
                    this.ResultadosGlobales.TiempoIteracion(paso_actual) = dt_iteracion;
                    siguiente_paso_actualizacion = siguiente_paso_actualizacion + this.pParOpt.PasoActualizacion;
                end
            end
        end
        
        function cadenas = inicializa_cadenas(this)
            if this.iNivelDebug > 0
                prot = cProtocolo.getInstance;
            end            
            disp('Inicializa cadenas');
            cantidad_cadenas = this.CantCadenas;
            cantidad_etapas = this.pParOpt.CantidadEtapas;

            max_cantidad_pasos = this.pParOpt.MaxCantidadPasos;
            cantidad_decisiones_primarias = this.pAdmProy.entrega_cantidad_decisiones_primarias();
            cadenas = cell(cantidad_cadenas,1);
            capacidad_inicial_corredores = this.pAdmProy.entrega_capacidad_inicial_decisiones_primarias();
            for i = 1:cantidad_cadenas
                cadenas{i}.Proyectos = zeros(max_cantidad_pasos, this.pAdmProy.CantidadProyTransmision);
                cadenas{i}.CambiosEstado = -1*ones(max_cantidad_pasos,1);
                cadenas{i}.Totex = zeros(max_cantidad_pasos,1);
                cadenas{i}.FObj = zeros(max_cantidad_pasos,1);
                cadenas{i}.CapacidadDecisionesPrimarias = ones(cantidad_decisiones_primarias, cantidad_etapas).*capacidad_inicial_corredores';
                cadenas{i}.TiempoEnLlegarAlOptimo = 0;
                cadenas{i}.plan_actual = cPlanExpansion(i*max_cantidad_pasos*10 + 1);
                %pPlan.Plan = this.PlanOptimo.Plan;                
                cadenas{i}.sep_actuales = cSistemaElectricoPotencia.empty(cantidad_etapas,0);
                for etapa = 1:cantidad_etapas
                    if etapa == 1
                        cadenas{i}.sep_actuales{etapa} = this.pSEP.crea_copia();
                    else
                        cadenas{i}.sep_actuales{etapa} = cadenas{i}.sep_actuales{etapa-1}.crea_copia();                        
                    end
                    this.agrega_elementos_proyectados_a_sep_en_etapa(cadenas{i}.sep_actuales{etapa}, etapa)                    
                end
            end
            this.ResultadosGlobales.TiempoIteracion = zeros(max_cantidad_pasos/this.pParOpt.PasoActualizacion,1);
            
            
            % genera planes base
            if this.pParOpt.EstrategiaGeneraPlanesBase == 1
                %greedy
                estrategia_genera_planes = ones(cantidad_cadenas,1);
            elseif this.pParOpt.EstrategiaGeneraPlanesBase == 2
                % random
                estrategia_genera_planes = 2*ones(cantidad_cadenas,1);
            else
                %mixto
                estrategia_genera_planes = ones(cantidad_cadenas,1);
                cantidad_greedy = round(cantidad_cadenas*this.pParOpt.EstrategiaGeneraPlanesBase,0);
                estrategia_genera_planes(cantidad_greedy+1:end) = 2;
            end
            if this.pParOpt.GeneraPlanOptimoComoBase
                estrategia_genera_planes(1) = 0;
            end
            
            for nro_cadena = 1:cantidad_cadenas
                pPlan = cadenas{nro_cadena}.plan_actual;
                for etapa = 1:cantidad_etapas
                    % incorpora proyectos etapas anteriores
                    proy_agregar = pPlan.entrega_proyectos_acumulados(etapa-1);
                    for j = 1:length(proy_agregar)
                        proyecto = this.pAdmProy.entrega_proyecto(proy_agregar(i));
                        if ~cadenas{nro_cadena}.sep_actuales{etapa}.agrega_proyecto(proyecto)
                            % Error (probablemente de programación). 
                            texto = ['Error de programacion. Plan ' num2str(pPlan.entrega_no()) ' no pudo ser implementado en SEP en etapa ' num2str(etapa_previa)];
                            error = MException('cOptMCMC:inicializa_cadenas',texto);
                            throw(error)
                        end
                    end
                    
                    pPlan.inicializa_etapa(etapa);
                    
                    grupos_proy = this.pAdmProy.entrega_proyectos_obligatorios_por_etapa(1, etapa); %1 indica el escenario. Por ahora sólo un escenario
                    if estrategia_genera_planes(nro_cadena) ~= 0
                        if ~isempty(grupos_proy)
                            for j = 1:length(grupos_proy)
                                % escoge un proyecto en forma aleatoria
                                [proy_ppal, proy_conect] = this.selecciona_proyectos_obligatorios(grupos_proy(j).Proyectos, cadenas{nro_cadena}.plan_actual);
                                for k = 1:length(proy_conect)
                                    pPlan.agrega_proyecto(etapa, proy_conect(k).entrega_indice());
                                    cadenas{nro_cadena}.sep_actuales{etapa}.agrega_proyecto(proy_conect(k));
                                end
                                pPlan.agrega_proyecto(etapa, proy_ppal.entrega_indice());
                                cadenas{nro_cadena}.sep_actuales{etapa}.agrega_proyecto(proy_ppal);
                                id_decision = proy_ppal.entrega_indice_decision_expansion();
                                delta_capacidad = proy_ppal.entrega_capacidad_adicional();
                                cadenas{nro_cadena}.CapacidadDecisionesPrimarias(id_decision, etapa:end) = cadenas{nro_cadena}.CapacidadDecisionesPrimarias(id_decision, etapa:end) + delta_capacidad;
                            end
                        end
                    end
                    
                    if estrategia_genera_planes(nro_cadena) == 2
                        cant_proyectos = length(this.pAdmProy.ProyTransmision);
                        prob_construir = (1-this.pParOpt.ProbNoConstruirPlanBase)/cantidad_etapas;
                        cant_total = round(cantidad_decisiones_primarias/prob_construir,0);
                        espacio_dec_primarias = [1:1:cantidad_decisiones_primarias zeros(1,cant_total-cantidad_decisiones_primarias)];
                        decision = espacio_dec_primarias(ceil(rand(cant_proyectos,1)*length(espacio_dec_primarias)));
                        indice_dec_primaria = decision(decision > 0);
                        for i = 1:length(indice_dec_primaria)
                            dec_prim = indice_dec_primaria(i);
                            id_proy = this.pAdmProy.entrega_id_proyectos_primarios_por_indice_decision(dec_prim);
                            % verifica si algún proyecto se encuentra en
                            % plan
                            [proy_realizado, etapa_proy] = pPlan.entrega_ultimo_proyecto_realizado_de_grupo(id_proy);
                            if etapa_proy == 0
                                % ningún proyecto realizado. Se agrega el
                                % primero
                                estado_inicial = this.pAdmProy.entrega_estado_inicial_decision_primaria(dec_prim);
                                id_proy_salientes = this.pAdmProy.entrega_id_proyectos_salientes_por_indice_decision_y_estado(dec_prim, estado_inicial(1), estado_inicial(2));
                            else
                                estado_conducente = this.pAdmProy.entrega_proyecto(proy_realizado).entrega_estado_conducente();
                                id_proy_salientes = this.pAdmProy.entrega_id_proyectos_salientes_por_indice_decision_y_estado(dec_prim, estado_conducente(1), estado_conducente(2));
                            end

                            if ~isempty(id_proy_salientes)
                                %elige uno al azar. Si id_proy_salientes
                                %está vacío, entonces todos los proyectos
                                %del corredor se realizaron
                                id_proy_seleccionado = id_proy_salientes(ceil(rand*length(id_proy_salientes)));
                                pPlan.agrega_proyecto(etapa, id_proy_seleccionado);
                                proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                cadenas{nro_cadena}.sep_actuales{etapa}.agrega_proyecto(proy_seleccionado);

                                id_decision = proy_seleccionado.entrega_indice_decision_expansion();
                                delta_capacidad = proy_seleccionado.entrega_capacidad_adicional();
                                cadenas{nro_cadena}.CapacidadDecisionesPrimarias(id_decision, etapa:end) = cadenas{nro_cadena}.CapacidadDecisionesPrimarias(id_decision, etapa:end) + delta_capacidad;
                                
                            end
                        end
                    end
                    
                    if estrategia_genera_planes(nro_cadena) == 0
                        id_proy_plan_optimo = this.PlanOptimo.entrega_proyectos(etapa);
                        proy_plan_optimo = this.pAdmProy.ProyTransmision(id_proy_plan_optimo);
                        for i = 1:length(proy_plan_optimo)
                            proy_seleccionado = proy_plan_optimo(i);
                            id_proy_seleccionado = proy_plan_optimo(i).entrega_indice();

                            pPlan.agrega_proyecto(etapa, id_proy_seleccionado);
                            cadenas{nro_cadena}.sep_actuales{etapa}.agrega_proyecto(proy_seleccionado);

                            id_decision = proy_seleccionado.entrega_indice_decision_expansion();
                            delta_capacidad = proy_seleccionado.entrega_capacidad_adicional();
                            cadenas{nro_cadena}.CapacidadDecisionesPrimarias(id_decision, etapa:end) = cadenas{nro_cadena}.CapacidadDecisionesPrimarias(id_decision, etapa:end) + delta_capacidad;                                
                        end
                    end
                    % inicializa opf, FP y evalua sep actual en etapa
                    pOPF = cDCOPF(cadenas{nro_cadena}.sep_actuales{etapa},this.pAdmSc, this.pParOpt);
                    pOPF.inserta_etapa(etapa);
                    pOPF.calcula_despacho_economico();
                    %cadenas{nro_cadena}.sep_actuales{etapa}.inserta_opf(pOPF);

                    if this.pParOpt.considera_flujos_ac()
                        pFP = cFlujoPotencia(cadenas{nro_cadena}.sep_actuales{etapa},this.pAdmSc, this.pParOpt);
                        pFP.evalua_red();
                    end
    
                    this.evalua_resultado_y_guarda_en_plan(pPlan, etapa, cadenas{nro_cadena}.sep_actuales{etapa}.entrega_evaluacion());
                    % genera plan sin ENS y sin recorte RES
                    while ~pPlan.es_valido(etapa)
                        if this.iNivelDebug > 1
                            prot.imprime_texto(['Plan cadena ' num2str(nro_cadena) ' no es valido en etapa ' num2str(etapa) '. Se intenta reparar']);
                        end
                        
                        cant_proy_comparar = this.pParOpt.CantProyCompararReparaPlan;
                        % ENS
                        [proy_candidatos_ens, ~] = this.determina_espacio_busqueda_repara_plan(pPlan, cadenas{nro_cadena}.sep_actuales{etapa}.entrega_evaluacion(), etapa, 1);
                        proy_agregado = false;
                        if ~isempty(proy_candidatos_ens)
                            proy_candidatos_ens = proy_candidatos_ens(randperm(length(proy_candidatos_ens)));
                            tope = min(length(proy_candidatos_ens),cant_proy_comparar);
                            costo_falla_intento = zeros(tope, 1);
                            mejor_intento = 0;
                            
                            for i = 1:tope
                                id_proy_selec = proy_candidatos_ens(i);
                                proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_selec);
                                cadenas{nro_cadena}.sep_actuales{etapa}.agrega_proyecto(proy_seleccionado);
                                pOPF.calcula_despacho_economico();

                                evaluacion_opf = pOPF.entrega_evaluacion();
                                costo_falla_intento(i) = sum(evaluacion_opf.CostoENS)+sum(evaluacion_opf.CostoRecorteRES);

                                if this.iNivelDebug > 2
                                    OPF_debug = cDCOPF(cadenas{nro_cadena}.sep_actuales{etapa}, this.pAdmSc, this.pParOpt);
                                    OPF_debug.inserta_etapa(etapa);
                                    OPF_debug.calcula_despacho_economico()
                                    eval_debug = OPF_debug.entrega_evaluacion();
                                    costo_falla_debug = sum(eval_debug.CostoENS)+sum(eval_debug.CostoRecorteRES);
                                    if round(costo_falla_debug,2) ~= round(costo_falla_intento(i),2)
                                        disp('Error en opf');
                                    end
                                end
                                if this.iNivelDebug > 2
                                    prot.imprime_texto('');
                                    prot.imprime_texto(['Evaluacion despues de intento ' num2str(i) '. Costo ENS: ' num2str(sum(evaluacion_opf.CostoENS)) '. Costo Recorte RES: ' num2str(sum(evaluacion_opf.CostoRecorteRES))]);
                                    prot.imprime_texto(['Agrega proyecto: ' num2str(id_proy_selec)]);
                                    texto = sprintf('%-25s %-10s %-10s %-30s', 'Elemento', 'Tipo Rep', 'Carga', 'Proyectos');
                                    prot.imprime_texto(texto);

                                    elem_flujo_max = evaluacion_opf.entrega_lineas_flujo_maximo();
                                    elem_flujo_max = [elem_flujo_max evaluacion_opf.entrega_trafos_flujo_maximo()];
                                    
                                    for j = 1:length(elem_flujo_max)
                                        texto_imp{j,1} = sprintf('%-25s', elem_flujo_max(j).entrega_nombre());
                                        texto_imp{j,2} = sprintf('%-10s', '-');
                                        texto_imp{j,3} = sprintf('%-10s', num2str(round(max(abs(evaluacion_opf.entrega_flujo_linea(elem_flujo_max(j))))/elem_flujo_max(j).entrega_sr(),2)));
                                        texto_imp{j,4} = sprintf('%-30s', '-');
                                        prot.imprime_texto(sprintf('%-25s %-10s %-10s %-30s', texto_imp{j,1}, texto_imp{j,2}, texto_imp{j,3}, texto_imp{j,4}));
                                    end
                                end
                                    
                                if costo_falla_intento(i) == 0 || tope == 1
                                    mejor_intento = i;
                                    break
                                else
                                    cadenas{nro_cadena}.sep_actuales{etapa}.elimina_proyecto(proy_seleccionado);
                                end
                            end
                            if mejor_intento == 0
                                mejor_intento = find(costo_falla_intento == min(costo_falla_intento),1);
                                % implementa mejor intento en SEP
                                id_proy_seleccionado = proy_candidatos_ens(mejor_intento);
                                proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                cadenas{nro_cadena}.sep_actuales{etapa}.agrega_proyecto(proy_seleccionado);
                                pOPF.calcula_despacho_economico(); % hay que calcularlo nuevamente si no no se actualizan los índices. TODO: se puede mejorar
                            else
                                % no es necesario agregarlo al SEP porque ya está
                                id_proy_seleccionado = proy_candidatos_ens(mejor_intento);
                                proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                            end
                            if this.iNivelDebug > 1
                                eval_actual = pOPF.entrega_evaluacion();
                                prot.imprime_texto('');
                                prot.imprime_texto('Evaluacion actual mejor intento');
                                prot.imprime_texto(['Agrega proyecto: ' num2str(id_proy_seleccionado)]);
                                texto = sprintf('%-25s %-10s %-10s %-30s', 'Elemento', 'Tipo Rep', 'Carga', 'Proyectos');
                                prot.imprime_texto(texto);

                                elem_flujo_max = eval_actual.entrega_lineas_flujo_maximo();
                                elem_flujo_max = [elem_flujo_max eval_actual.entrega_trafos_flujo_maximo()];

                                for j = 1:length(elem_flujo_max)
                                    texto_imp{j,1} = sprintf('%-25s', elem_flujo_max(j).entrega_nombre());
                                    texto_imp{j,2} = sprintf('%-10s', '-');
                                    texto_imp{j,3} = sprintf('%-10s', num2str(round(max(abs(eval_actual.entrega_flujo_linea(elem_flujo_max(j))))/elem_flujo_max(j).entrega_sr(),2)));
                                    texto_imp{j,4} = sprintf('%-30s', '-');
                                    prot.imprime_texto(sprintf('%-25s %-10s %-10s %-30s', texto_imp{j,1}, texto_imp{j,2}, texto_imp{j,3}, texto_imp{j,4}));
                                end
                            end
                            
                            pPlan.agrega_proyecto(etapa, id_proy_seleccionado);
                            this.evalua_resultado_y_guarda_en_plan(pPlan, etapa, pOPF.entrega_evaluacion());

                            id_decision = proy_seleccionado.entrega_indice_decision_expansion();
                            delta_capacidad = proy_seleccionado.entrega_capacidad_adicional();
                            cadenas{nro_cadena}.CapacidadDecisionesPrimarias(id_decision, etapa:end) = cadenas{nro_cadena}.CapacidadDecisionesPrimarias(id_decision, etapa:end) + delta_capacidad;

                            proy_agregado = true;
                            if this.iNivelDebug > 1
                                prot.imprime_texto(['Proyecto de ENS agregado: ' num2str(id_proy_seleccionado)]);
                            end
                        end
                        
                        % Recorte RES
                        [proy_candidatos_recorte, ~] = this.determina_espacio_busqueda_repara_plan(pPlan, pOPF.entrega_evaluacion(), etapa, 2);
                        if ~isempty(proy_candidatos_recorte)
                            proy_candidatos_recorte = proy_candidatos_recorte(randperm(length(proy_candidatos_recorte)));
                            tope = min(length(proy_candidatos_recorte),cant_proy_comparar);
                            costo_falla_intento = zeros(tope, 1);
                            mejor_intento = 0;
                            for i = 1:tope
                                id_proy_selec = proy_candidatos_recorte(i);
                                proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_selec);
                                cadenas{nro_cadena}.sep_actuales{etapa}.agrega_proyecto(proy_seleccionado);
                                pOPF.calcula_despacho_economico();
                                evaluacion_opf = pOPF.entrega_evaluacion();
                                costo_falla_intento(i) = sum(evaluacion_opf.CostoENS)+sum(evaluacion_opf.CostoRecorteRES);

                                if this.iNivelDebug > 1
                                    prot.imprime_texto('');
                                    prot.imprime_texto(['Evaluacion despues de intento ' num2str(i) '. Costo ENS: ' num2str(sum(evaluacion_opf.CostoENS)) '. Costo Recorte RES: ' num2str(sum(evaluacion_opf.CostoRecorteRES))]);
                                    prot.imprime_texto(['Agrega proyecto: ' num2str(id_proy_selec)]);
                                    texto = sprintf('%-25s %-10s %-10s %-30s', 'Elemento', 'Tipo Rep', 'Carga', 'Proyectos');
                                    prot.imprime_texto(texto);

                                    elem_flujo_max = evaluacion_opf.entrega_lineas_flujo_maximo();
                                    elem_flujo_max = [elem_flujo_max evaluacion_opf.entrega_trafos_flujo_maximo()];
                                    
                                    for j = 1:length(elem_flujo_max)
                                        texto_imp{j,1} = sprintf('%-25s', elem_flujo_max(j).entrega_nombre());
                                        texto_imp{j,2} = sprintf('%-10s', '-');
                                        texto_imp{j,3} = sprintf('%-10s', num2str(round(max(abs(evaluacion_opf.entrega_flujo_linea(elem_flujo_max(j))))/elem_flujo_max(j).entrega_sr(),2)));
                                        texto_imp{j,4} = sprintf('%-30s', '-');
                                        prot.imprime_texto(sprintf('%-25s %-10s %-10s %-30s', texto_imp{j,1}, texto_imp{j,2}, texto_imp{j,3}, texto_imp{j,4}));
                                    end
                                end
                                
                                if costo_falla_intento(i) == 0 || tope == 1
                                    mejor_intento = i;
                                    break
                                else
                                    cadenas{nro_cadena}.sep_actuales{etapa}.elimina_proyecto(proy_seleccionado);
                                end
                            end
                            if mejor_intento == 0
                                mejor_intento = find(costo_falla_intento == min(costo_falla_intento),1);
                                % implementa mejor intento en SEP
                                id_proy_seleccionado = proy_candidatos_recorte(mejor_intento);
                                proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                cadenas{nro_cadena}.sep_actuales{etapa}.agrega_proyecto(proy_seleccionado);
                                pOPF.calcula_despacho_economico(); % hay que calcularlo nuevamente si no no se actualizan los índices. TODO: se puede mejorar
                            else
                                % no es necesario agregarlo al SEP porque ya está
                                id_proy_seleccionado = proy_candidatos_recorte(mejor_intento);
                                proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                            end

                            pPlan.agrega_proyecto(etapa, id_proy_seleccionado);
                            this.evalua_resultado_y_guarda_en_plan(pPlan, etapa, pOPF.entrega_evaluacion());
                            
                            if this.iNivelDebug > 1
                                eval_actual = pOPF.entrega_evaluacion();
                                prot.imprime_texto('');
                                prot.imprime_texto('Evaluacion actual mejor intento');
                                prot.imprime_texto(['Agrega proyecto: ' num2str(id_proy_seleccionado)]);
                                texto = sprintf('%-25s %-10s %-10s %-30s', 'Elemento', 'Tipo Rep', 'Carga', 'Proyectos');
                                prot.imprime_texto(texto);

                                elem_flujo_max = eval_actual.entrega_lineas_flujo_maximo();
                                elem_flujo_max = [elem_flujo_max eval_actual.entrega_trafos_flujo_maximo()];

                                for j = 1:length(elem_flujo_max)
                                    texto_imp{j,1} = sprintf('%-25s', elem_flujo_max(j).entrega_nombre());
                                    texto_imp{j,2} = sprintf('%-10s', '-');
                                    texto_imp{j,3} = sprintf('%-10s', num2str(round(max(abs(eval_actual.entrega_flujo_linea(elem_flujo_max(j))))/elem_flujo_max(j).entrega_sr(),2)));
                                    texto_imp{j,4} = sprintf('%-30s', '-');
                                    prot.imprime_texto(sprintf('%-25s %-10s %-10s %-30s', texto_imp{j,1}, texto_imp{j,2}, texto_imp{j,3}, texto_imp{j,4}));
                                end
                            end
                                                        
                            id_decision = proy_seleccionado.entrega_indice_decision_expansion();
                            delta_capacidad = proy_seleccionado.entrega_capacidad_adicional();
                            cadenas{nro_cadena}.CapacidadDecisionesPrimarias(id_decision, etapa:end) = cadenas{nro_cadena}.CapacidadDecisionesPrimarias(id_decision, etapa:end) + delta_capacidad;

                            proy_agregado = true;
                            if this.iNivelDebug > 1
                                prot.imprime_texto(['Proyecto Recorte RES agregado: ' num2str(id_proy_seleccionado)]);
                            end                            
                        end
                        
                        if ~proy_agregado
                            % plan no es válido pero no pudo ser reparado
                            pOPF.imprime_resultados_protocolo()
                            error = MException('cOptMCMC:inicializa_cadenas','Plan no es valido pero no pudo ser reparado');
                            throw(error)
                        end
                    end
                end
                
                % ingresa resultados de etapas por proyectos 
                [proy, etapas] = pPlan.entrega_proyectos_y_etapas();
                cadenas{nro_cadena}.Proyectos(1,proy) = etapas;
                this.calcula_costos_totales(pPlan);
                
                % guarda resultados cadena
                cadenas{nro_cadena}.CambiosEstado(1) = 0;
                cadenas{nro_cadena}.Totex(1) = pPlan.entrega_totex_total();
                cadenas{nro_cadena}.FObj(1) = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
%                cadenas{nro_cadena}.plan_actual = pPlan;
                cadenas{nro_cadena}.MejorTotex = cadenas{nro_cadena}.Totex(1);
                cadenas{nro_cadena}.MejorFObj = cadenas{nro_cadena}.FObj(1);
%                cadenas{nro_cadena}.Sigma(1,:) = this.pParOpt.SigmaParametros*ones(1, this.pAdmProy.CantidadProyTransmision);
%                cadenas{nro_cadena}.SigmaActual = this.pParOpt.SigmaParametros*ones(1, this.pAdmProy.CantidadProyTransmision);
%                cadenas{nro_cadena}.IntercambioCadena(1) = 0;
                
            end

            for corr = 1:cantidad_decisiones_primarias
                this.CapacidadDecisionesPrimariasPorCadenas{corr} = zeros(cantidad_cadenas, cantidad_etapas);
                for cad = 1:cantidad_cadenas
                    this.CapacidadDecisionesPrimariasPorCadenas{corr}(cad,:) = cadenas{cad}.CapacidadDecisionesPrimarias(corr,:);
                end
            end
            
            if this.iNivelDebug > 0
                prot = cProtocolo.getInstance;
                prot.imprime_texto('Evaluacion planes base');
                for nro_cadena = 1:cantidad_cadenas
                    prot.imprime_texto(['Plan cadena ' num2str(nro_cadena)]);
                    plan = cadenas{nro_cadena}.plan_actual;
                    plan.imprime_plan_expansion();
                    prot.imprime_texto(['Totex total plan: ' num2str(cadenas{nro_cadena}.Totex(1))]);
                end
            end
        end
        
        function cadenas = mapea_espacio(this, cadenas, paso_actual, t_inicio_proceso, nivel_debug)
            % por ahora existen 2 estrategias de búsqueda local: una simple
            % y otra completa
            % además, en cada caso depende si se trata de computo paralelo
            % o cómputo secuencial
            if this.pParOpt.ComputoParalelo
                if this.pParOpt.EstrategiaBusquedaLocal == 0
                    cadenas = this.mapea_espacio_paralelo_sin_bl(cadenas, paso_actual, t_inicio_proceso, nivel_debug);
                elseif this.pParOpt.EstrategiaBusquedaLocal == 1
                    cadenas = this.mapea_espacio_paralelo_bl_simple(cadenas, paso_actual, t_inicio_proceso, nivel_debug);
                else
                    cadenas = this.mapea_espacio_paralelo_bl_detallada(cadenas, paso_actual, t_inicio_proceso, nivel_debug);
                end
            else
                if this.pParOpt.EstrategiaBusquedaLocal == 0
                    cadenas = this.mapea_espacio_secuencial_sin_bl(cadenas, paso_actual, t_inicio_proceso, nivel_debug);
                elseif this.pParOpt.EstrategiaBusquedaLocal == 1
                    cadenas = this.mapea_espacio_secuencial_bl_simple(cadenas, paso_actual, t_inicio_proceso, nivel_debug);
                else
                    cadenas = this.mapea_espacio_secuencial_bl_detallada(cadenas, paso_actual, t_inicio_proceso, nivel_debug);
                end
            end
        end
        
        function cadenas = mapea_espacio_secuencial_sin_bl(this, cadenas, paso_actual, t_inicio_proceso, nivel_debug)
            cantidad_cadenas = this.pParOpt.CantidadCadenas;
            cantidad_etapas = this.pParOpt.CantidadEtapas;
            for nro_cadena = 1:cantidad_cadenas
                if nivel_debug > 0
                    prot = cProtocolo.getInstance;
                    texto = ['Comienzo proceso mapea espacio sin busqueda local cadena ' num2str(nro_cadena) ' en paso actual ' num2str(paso_actual)];
                    prot.imprime_texto(texto);
                end

                pPlan = cadenas{nro_cadena}.plan_actual;
                if nivel_debug > 1
                    texto = ['Imprime plan actual cadena en paso ' num2str(paso_actual)];
                    prot.imprime_texto(texto);
                    pPlan.agrega_nombre_proyectos(this.pAdmProy);
                    pPlan.imprime_plan_expansion();

                    tinicio_paso = clock;
                end
%                    cadenas{nro_cadena}.Sigma(paso_actual,:) = cadenas{nro_cadena}.SigmaActual;

                plan_prueba = cPlanExpansion(pPlan.entrega_no() + 1);
                plan_prueba.Proyectos = pPlan.Proyectos;
                plan_prueba.Etapas = pPlan.Etapas;
                plan_prueba.inserta_evaluacion(pPlan.entrega_evaluacion());
                plan_prueba.inserta_estructura_costos(pPlan.entrega_estructura_costos());

                if nivel_debug > 2
                    this.debug_verifica_capacidades_corredores(plan_prueba, cadenas{nro_cadena}.CapacidadDecisionesPrimarias, 'Punto verificacion 1');
                end

                existe_cambio_global = false;

                proyectos_cambiados_prueba = [];
                etapas_originales_plan_actual = [];
                etapas_nuevas_plan_prueba = [];
                % genera nuevo trial

                [proyectos_modificar, etapas_originales, nuevas_etapas, capacidades_plan_prueba]= this.modifica_plan(plan_prueba, nro_cadena, cadenas{nro_cadena}.CapacidadDecisionesPrimarias);

                if nivel_debug > 2
                    debug_verifica_capacidades_corredores(plan_prueba, capacidades_plan_prueba, 'Punto verificacion 2');
                end

                if nivel_debug > 1
                    texto = ['      Proyectos modificados (' num2str(length(proyectos_modificar)) '):'];
                    prot.imprime_texto(texto);
                    for ii = 1:length(proyectos_modificar)
                        texto = ['       ' num2str(proyectos_modificar(ii)) ' de etapa ' num2str(etapas_originales(ii)) ' a etapa ' num2str(nuevas_etapas(ii))];
                        prot.imprime_texto(texto);
                    end

                    texto = ['Imprime plan modificado en paso ' num2str(paso_actual)];
                    prot.imprime_texto(texto);
                    plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                    plan_prueba.imprime_plan_expansion();
                end

                if ~isequal(etapas_originales, nuevas_etapas)
                    existe_cambio_global = true;
                    % se actualiza la red y se calcula nuevo totex de
                    % proyectos modificados
                    desde_etapa = min(min(etapas_originales), min(nuevas_etapas));
                    hasta_etapa = min(cantidad_etapas, max(max(etapas_originales), max(nuevas_etapas)));

                    for nro_etapa = desde_etapa:hasta_etapa
                        for jj = 1:length(proyectos_modificar)
                            if etapas_originales(jj) < cantidad_etapas + 1 && ...
                                etapas_originales(jj) < nuevas_etapas(jj) && ...
                                nro_etapa >= etapas_originales(jj) && ...
                                nro_etapa < nuevas_etapas(jj) 

                                % proyecto se retrasa, por lo que hay que eliminarlo del SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_modificar(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                            elseif etapas_originales(jj) > nuevas_etapas(jj) && ...
                                    nro_etapa >=  nuevas_etapas(jj) && ...
                                    nro_etapa < etapas_originales(jj) 
                                % proyecto se adelanta, por lo que hay que
                                % agregarlo al SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_modificar(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            end
                        end
                        
                        if nivel_debug >2
                            this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 3')
                        end
                        
                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                        this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                    
                        % genera plan sin ENS y sin recorte RES
                        while ~plan_prueba.es_valido(nro_etapa)
                            if nivel_debug >1
                                prot.imprime_texto(['Plan prueba no es valido en etapa ' num2str(nro_etapa) '. Se repara']);
                            end

                            cant_proy_comparar = this.pParOpt.CantProyCompararReparaPlan;

                            % ENS
                            [candidatos_ens, etapas_ens] = this.determina_espacio_busqueda_repara_plan(plan_prueba, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa,1);
                            proy_agregado = false;                            
                            if ~isempty(candidatos_ens)
                                proy_candidatos_ens = [];
                                etapas_cand_ens = [];
                                tope = min(length(candidatos_ens),cant_proy_comparar);                

                                % prioridad a proyectos que están en plan
                                id_existentes = find(etapas_ens ~= cantidad_etapas+1);
                                if ~isempty(id_existentes)
                                    if length(id_existentes) > tope
                                        orden = randperm(length(id_existentes));
                                        proy_candidatos_ens = candidatos_ens(id_existentes(orden));
                                        etapas_cand_ens = etapas_ens(id_existentes(orden));
                                        proy_candidatos_ens = proy_candidatos_ens(1:tope);
                                        etapas_cand_ens = etapas_cand_ens(1:tope);
                                    else
                                        proy_candidatos_ens = candidatos_ens(id_existentes);
                                        etapas_cand_ens = etapas_ens(id_existentes);
                                    end
                                    tope = tope-length(proy_candidatos_ens);
                                end
                                if tope > 0
                                    id_no_existentes = find(etapas_ens == cantidad_etapas+1);
                                    if length(id_no_existentes) > tope
                                        orden = randperm(length(id_no_existentes));
                                        nuevos_cand = candidatos_ens(id_no_existentes(orden));
                                        nuevas_etapas_cand = etapas_ens(id_no_existentes(orden));
                                        
                                        proy_candidatos_ens = [proy_candidatos_ens nuevos_cand(1:tope)];
                                        etapas_cand_ens = [etapas_cand_ens nuevas_etapas_cand(1:tope)];
                                    else
                                        proy_candidatos_ens = [proy_candidatos_ens candidatos_ens(id_no_existentes)];
                                        etapas_cand_ens = [etapas_cand_ens etapas_ens(id_no_existentes)];
                                    end
                                end
                                
                                costo_falla_intento = zeros(tope, 1);
                                mejor_intento = 0;
                                tope = length(proy_candidatos_ens);
                                for i = 1:tope
                                    id_proy_selec = proy_candidatos_ens(i);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_selec);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                    eval = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion();
                                    costo_falla_intento(i) = sum(eval.CostoENS)+sum(eval.CostoRecorteRES);
                                    if costo_falla_intento(i) == 0 || tope == 1
                                        mejor_intento = i;
                                        break
                                    else
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proy_seleccionado);
                                    end
                                end
                                if mejor_intento == 0
                                    mejor_intento = find(costo_falla_intento == min(costo_falla_intento),1);
                                    % implementa mejor intento en SEP
                                    id_proy_seleccionado = proy_candidatos_ens(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                else
                                    % no es necesario agregarlo al SEP porque ya está
                                    id_proy_seleccionado = proy_candidatos_ens(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                end
                                etapa_seleccionado = etapas_cand_ens(mejor_intento);
                                
                                % implementa mejor intento en el plan
                                if etapas_cand_ens(mejor_intento) == cantidad_etapas+1
                                    plan_prueba.agrega_proyecto(nro_etapa, id_proy_seleccionado);
                                    if nivel_debug > 1
                                        prot.imprime_texto(['ENS: Se agrega proyecto ' num2str(id_proy_seleccionado) ' a etapa ' num2str(nro_etapa)]);
                                    end
                                else
                                    plan_prueba.adelanta_proyectos(id_proy_seleccionado, etapa_seleccionado, nro_etapa);
                                    if nivel_debug > 1
                                        prot.imprime_texto(['ENS: Se adelanta proyecto ' num2str(id_proy_seleccionado) ' de etapa ' num2str(etapa_seleccionado) ' a etapa ' num2str(nro_etapa)]);
                                    end
                                end
                                
                                this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                                
                                % actualiza capacidades
                                id_decision = proy_seleccionado.entrega_indice_decision_expansion();
                                delta_capacidad = proy_seleccionado.entrega_capacidad_adicional();
                                capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) = capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) + delta_capacidad;
                                proy_agregado = true;

                                % agrega proyecto seleccionado a proyectos modificar
                                id_proyectos_modificar = find(proyectos_modificar == id_proy_seleccionado);
                                if ~isempty(id_proyectos_modificar)
                                    % proyecto seleccionado pertenece a proyectos modificar. Se actualiza etapa fin
                                    nuevas_etapas(id_proyectos_modificar) = nro_etapa;
                                else
                                    % nuevo proyecto. Se agrega a proyectos modificar
                                    proyectos_modificar = [proyectos_modificar id_proy_seleccionado];
                                    etapas_originales = [etapas_originales etapa_seleccionado];
                                    nuevas_etapas = [nuevas_etapas nro_etapa];
                                end
                                
                                % modifica etapa fin de evaluación 
                                hasta_etapa = min(cantidad_etapas, max(max(etapas_originales), max(nuevas_etapas)));
                            end

                            % recorte RES
                            [candidatos_recorte, etapas_recorte] = this.determina_espacio_busqueda_repara_plan(plan_prueba, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa,2);
                            if ~isempty(candidatos_recorte)
                                proy_candidatos_recorte = [];
                                etapas_cand_recorte = [];
                                tope = min(length(candidatos_recorte),cant_proy_comparar);                                

                                % prioridad a proyectos que están en plan
                                id_existentes = find(etapas_recorte ~= cantidad_etapas+1);
                                if ~isempty(id_existentes)
                                    if length(id_existentes) > tope
                                        orden = randperm(length(id_existentes));
                                        proy_candidatos_recorte = candidatos_recorte(id_existentes(orden));
                                        etapas_cand_recorte = etapas_recorte(id_existentes(orden));
                                        proy_candidatos_recorte = proy_candidatos_recorte(1:tope);
                                        etapas_cand_recorte = etapas_cand_recorte(1:tope);
                                    else
                                        proy_candidatos_recorte = candidatos_recorte(id_existentes);
                                        etapas_cand_recorte = etapas_recorte(id_existentes);
                                    end
                                    tope = tope-length(proy_candidatos_recorte);
                                end
                                if tope > 0
                                    id_no_existentes = find(etapas_recorte == cantidad_etapas+1);
                                    if length(id_no_existentes) > tope
                                        orden = randperm(length(id_no_existentes));
                                        nuevos_cand = candidatos_recorte(id_no_existentes(orden));
                                        nuevas_etapas_cand = etapas_recorte(id_no_existentes(orden));
                                        
                                        proy_candidatos_recorte = [proy_candidatos_recorte nuevos_cand(1:tope)];
                                        etapas_cand_recorte = [etapas_cand_recorte nuevas_etapas_cand(1:tope)];
                                    else
                                        proy_candidatos_recorte = [proy_candidatos_recorte candidatos_recorte(id_no_existentes)];
                                        etapas_cand_recorte = [etapas_cand_recorte etapas_recorte(id_no_existentes)];
                                    end
                                end
                                
                                costo_falla_intento = zeros(tope, 1);
                                mejor_intento = 0;
                                tope = length(proy_candidatos_recorte);
                                for i = 1:tope
                                    id_proy_selec = proy_candidatos_recorte(i);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_selec);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                    eval = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion();
                                    costo_falla_intento(i) = sum(eval.CostoENS)+sum(eval.CostoRecorteRES);
                                    if costo_falla_intento(i) == 0 || tope == 1
                                        mejor_intento = i;
                                        break
                                    else
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proy_seleccionado);
                                    end
                                end
                                if mejor_intento == 0
                                    mejor_intento = find(costo_falla_intento == min(costo_falla_intento),1);
                                    % implementa mejor intento en SEP
                                    id_proy_seleccionado = proy_candidatos_recorte(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                else
                                    % no es necesario agregarlo al SEP porque ya está
                                    id_proy_seleccionado = proy_candidatos_recorte(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                end
                                etapa_seleccionado = etapas_cand_recorte(mejor_intento);
                                % implementa mejor intento en el plan
                                if etapas_cand_recorte(mejor_intento) == cantidad_etapas+1
                                    plan_prueba.agrega_proyecto(nro_etapa, id_proy_seleccionado);
                                    if nivel_debug > 1
                                        prot.imprime_texto(['Recorte: Se agrega proyecto ' num2str(id_proy_seleccionado) ' a etapa ' num2str(nro_etapa)]);
                                    end
                                else
                                    plan_prueba.adelanta_proyectos(id_proy_seleccionado, etapa_seleccionado, nro_etapa);
                                    if nivel_debug > 1
                                        prot.imprime_texto(['Recorte: Se adelanta proyecto ' num2str(id_proy_seleccionado) ' de etapa ' num2str(etapa_seleccionado) ' a etapa ' num2str(nro_etapa)]);
                                    end
                                end
                                
                                this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());

                                % actualiza capacidades
                                id_decision = proy_seleccionado.entrega_indice_decision_expansion();
                                delta_capacidad = proy_seleccionado.entrega_capacidad_adicional();
                                capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) = capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) + delta_capacidad;
                                proy_agregado = true;

                                % agrega proyecto seleccionado a proyectos modificar
                                id_proyectos_modificar = find(proyectos_modificar == id_proy_seleccionado);
                                if ~isempty(id_proyectos_modificar)
                                    % proyecto seleccionado pertenece a proyectos modificar. Se actualiza etapa fin
                                    nuevas_etapas(id_proyectos_modificar) = nro_etapa;
                                else
                                    % nuevo proyecto. Se agrega a proyectos modificar
                                    proyectos_modificar = [proyectos_modificar id_proy_seleccionado];
                                    etapas_originales = [etapas_originales etapa_seleccionado];
                                    nuevas_etapas = [nuevas_etapas nro_etapa];
                                end
                                
                                % modifica etapa fin de evaluación 
                                hasta_etapa = min(cantidad_etapas, max(max(etapas_originales), max(nuevas_etapas)));
                            end
                            

                            if ~proy_agregado
                                error = MException('cOptMCMC:mapea_espacio',['plan prueba no es válido en etapa ' num2str(nro_etapa) ' pero no se pudo reparar']);
                                throw(error)
                            end
                            
                            if nivel_debug >2
                                this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 3')
                            end
                            
                            if nivel_debug >2
                                this.debug_verifica_resultados_despacho_economico(cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), plan_prueba, nro_etapa, 'Punto verificacion 3')
                            end                            
                        end
                    end
                    proyectos_cambiados_prueba = proyectos_modificar;
                    etapas_originales_plan_actual = etapas_originales;
                    etapas_nuevas_plan_prueba = nuevas_etapas;
                    
                    this.calcula_costos_totales(plan_prueba);

                    if nivel_debug > 2
                        this.debug_verifica_consistencia_plan_valido(plan_prueba, 'Punto verificacion 4');
                    end
                end

                if nivel_debug > 1
                    prot.imprime_texto('Fin proyectos modificar');
                    texto = ['      Totex plan actual: ' num2str(pPlan.entrega_totex_total())];
                    prot.imprime_texto(texto);
                    texto = ['      Totex plan prueba: ' num2str(plan_prueba.entrega_totex_total())];
                    prot.imprime_texto(texto);
                    prot.imprime_texto('      Se imprime plan prueba (modificado)');
                    plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                    plan_prueba.imprime_plan_expansion();
                    prot.imprime_texto('Comienzo proyectos optimizar');
                end

                % determina si hay cambio o no
                if existe_cambio_global
                    if plan_prueba.entrega_totex_total() <= pPlan.entrega_totex_total()
                        acepta_cambio = true;
                    else
                        f_obj_prueba = plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                        f_obj_actual = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                        sigma = this.pParOpt.SigmaFuncionLikelihood;
                        prob_cambio = exp((-f_obj_prueba^2+f_obj_actual^2)/(2*sigma^2));

                        if nivel_debug > 1
                            prot.imprime_texto(['Probabilidad de cambio cadena ' num2str(nro_cadena) ': ' num2str(prob_cambio)]);
                        end
                        if rand < prob_cambio
                            acepta_cambio = true;
                        else
                            acepta_cambio = false;
                        end
                    end
                else
                    acepta_cambio = false;
                end

                if acepta_cambio
                    if nivel_debug > 1
                        prot.imprime_texto('Se acepta cambio de plan');
                        prot.imprime_texto(['Totex actual (f objetivo): ' num2str(pPlan.entrega_totex_total()) ' (' num2str(pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')']);
                        prot.imprime_texto(['Totex nuevo (f objetivo): ' num2str(plan_prueba.entrega_totex_total()) ' (' num2str(plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')']);
                    end
                    % se guarda nuevo plan en cadena
                    pPlan = plan_prueba;
                    cadenas{nro_cadena}.plan_actual = plan_prueba;
                    cadenas{nro_cadena}.CambiosEstado(paso_actual) = 1;
                    cadenas{nro_cadena}.Proyectos(paso_actual,:) = cadenas{nro_cadena}.Proyectos(paso_actual-1,:);
                    cadenas{nro_cadena}.CapacidadDecisionesPrimarias = capacidades_plan_prueba;
                    for ii = 1:length(proyectos_cambiados_prueba)
                        if etapas_nuevas_plan_prueba(ii) <= cantidad_etapas
                            cadenas{nro_cadena}.Proyectos(paso_actual,proyectos_cambiados_prueba(ii)) = etapas_nuevas_plan_prueba(ii);
                        else
                            cadenas{nro_cadena}.Proyectos(paso_actual,proyectos_cambiados_prueba(ii)) = 0;
                        end
                    end
                    cadenas{nro_cadena}.Totex(paso_actual) = pPlan.entrega_totex_total();                        
                    cadenas{nro_cadena}.FObj(paso_actual) = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                    % estadística
                    if pPlan.entrega_totex_total() < cadenas{nro_cadena}.MejorTotex
                        cadenas{nro_cadena}.MejorTotex = pPlan.entrega_totex_total();
                        cadenas{nro_cadena}.MejorFObj = pPlan.entrega_totex_total() - this.NPVCostosOperacionSinRestriccion;
                        if cadenas{nro_cadena}.TiempoEnLlegarAlOptimo == 0 && ...
                           round(cadenas{nro_cadena}.MejorTotex,5) == round(this.PlanOptimo.TotexTotal,5)
                            cadenas{nro_cadena}.TiempoEnLlegarAlOptimo = etime(clock,t_inicio_proceso);
                        end
                    end
                else
                    if nivel_debug > 1
                        prot.imprime_texto('No se acepta cambio de plan');
                        prot.imprime_texto(['Totex actual (f objetivo): ' num2str(pPlan.entrega_totex_total()) '(' num2str(pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')']);
                        prot.imprime_texto(['Totex no aceptado (f objetivo): ' num2str(plan_prueba.entrega_totex_total()) '(' num2str(plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')']);
                    end
                    cadenas{nro_cadena}.CambiosEstado(paso_actual) = 0;
                    cadenas{nro_cadena}.Proyectos(paso_actual,:) = cadenas{nro_cadena}.Proyectos(paso_actual-1,:);
                    cadenas{nro_cadena}.Totex(paso_actual) = pPlan.entrega_totex_total();
                    cadenas{nro_cadena}.FObj(paso_actual) = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                    % se deshacen los cambios en el SEP
                    desde_etapa = min(min(etapas_originales_plan_actual), min(etapas_nuevas_plan_prueba));
                    hasta_etapa = min(cantidad_etapas, max(max(etapas_originales_plan_actual), max(etapas_nuevas_plan_prueba)));

                    for nro_etapa = desde_etapa:hasta_etapa
                        for jj = 1:length(proyectos_cambiados_prueba)
                            if etapas_nuevas_plan_prueba(jj) < cantidad_etapas + 1 && ...
                               etapas_nuevas_plan_prueba(jj) < etapas_originales_plan_actual(jj) && ...
                               nro_etapa >= etapas_nuevas_plan_prueba(jj) && ...
                               nro_etapa < etapas_originales_plan_actual(jj) 
                                % proyecto se retrasa, por lo que hay que eliminarlo del SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_cambiados_prueba(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                            elseif etapas_nuevas_plan_prueba(jj) > etapas_originales_plan_actual(jj) && ...
                                   nro_etapa >=  etapas_originales_plan_actual(jj) && ...
                                   nro_etapa < etapas_nuevas_plan_prueba(jj) 
                                % proyecto se adelanta, por lo que hay que
                                % agregarlo al SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_cambiados_prueba(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            end
                        end
                        
                        if nivel_debug > 1
                            proyectos_en_sep = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_proyectos();
                            proyectos_en_plan = pPlan.entrega_proyectos_acumulados(nro_etapa);
                            if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
                            if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
                            error = MException('cOptMCMC:optimiza_deterministico',...
                            'Intento fallido 7. Proyectos en SEP distintos a proyectos en plan');
                            throw(error)
                            end
                            end
                        end

                    end
                end

                if nivel_debug > 1
                    prot.imprime_matriz([cadenas{nro_cadena}.Proyectos(paso_actual-1,:); cadenas{nro_cadena}.Proyectos(paso_actual,:)], 'Matriz proyectos pasos anterior y actual');
                    prot.imprime_texto([' Totex paso anterior: ' num2str(cadenas{nro_cadena}.Totex(paso_actual-1))]);
                    prot.imprime_texto([' Totex paso actual  : ' num2str(cadenas{nro_cadena}.Totex(paso_actual))]);                        
                end
                
                if nivel_debug > 1
                    dt_paso = etime(clock,tinicio_paso);

                    totex_anterior = num2str(round(cadenas{nro_cadena}.Totex(paso_actual-1),4));

                    gap = round((cadenas{nro_cadena}.MejorTotex-this.TotexPlanOptimo)/(this.TotexPlanOptimo)*100,3);
                    gap_actual = round((cadenas{nro_cadena}.plan_actual.entrega_totex_total()-this.TotexPlanOptimo)/this.TotexPlanOptimo*100,3);
                    valido = cadenas{nro_cadena}.plan_actual.es_valido();
                    if ~valido
                        texto_valido = 'no';
                    else
                        texto_valido = '';
                    end
                    text = sprintf('%-7s %-5s %-7s %-15s %-15s %-15s %-10s %-10s %-10s %-10s',num2str(nro_cadena), ...
                                                                         num2str(paso_actual),...
                                                                         texto_valido,...
                                                                         num2str(round(cadenas{nro_cadena}.plan_actual.entrega_totex_total(),4)),...
                                                                         totex_anterior,...
                                                                         num2str(cadenas{nro_cadena}.MejorTotex),...
                                                                         num2str(gap_actual), ...
                                                                         num2str(gap), ...
                                                                         num2str(dt_paso));

                    disp(text);
                end

            end % fin todas las cadenas
            
            % actualiza capacidades
            cantidad_decisiones_primarias = this.pAdmProy.entrega_cantidad_decisiones_primarias();
            for corr = 1:cantidad_decisiones_primarias
                for cad = 1:cantidad_cadenas
                    this.CapacidadDecisionesPrimariasPorCadenas{corr}(cad,:) = cadenas{cad}.CapacidadDecisionesPrimarias(corr,:); 
                end
            end
        end
        
        function cadenas = mapea_espacio_secuencial_bl_simple(this, cadenas, paso_actual, t_inicio_proceso, nivel_debug)

            cantidad_cadenas = this.pParOpt.CantidadCadenas;
            cantidad_etapas = this.pParOpt.CantidadEtapas;
            for nro_cadena = 1:cantidad_cadenas
                if nivel_debug > 0
                    prot = cProtocolo.getInstance;
                    texto = ['Comienzo proceso cadena ' num2str(nro_cadena) ' en paso actual ' num2str(paso_actual)];
                    prot.imprime_texto(texto);
                end

                pPlan = cadenas{nro_cadena}.plan_actual;
                if nivel_debug > 1
                    texto = ['Imprime plan actual cadena en paso ' num2str(paso_actual)];
                    prot.imprime_texto(texto);
                    pPlan.agrega_nombre_proyectos(this.pAdmProy);
                    pPlan.imprime_plan_expansion();

                    tinicio_paso = clock;
                end
%                    cadenas{nro_cadena}.Sigma(paso_actual,:) = cadenas{nro_cadena}.SigmaActual;

                plan_prueba = cPlanExpansion(pPlan.entrega_no() + 1);
                plan_prueba.Proyectos = pPlan.Proyectos;
                plan_prueba.Etapas = pPlan.Etapas;
                
                plan_prueba.inserta_evaluacion(pPlan.entrega_evaluacion());
                plan_prueba.inserta_estructura_costos(pPlan.entrega_estructura_costos());

                if nivel_debug > 2
                    this.debug_verifica_capacidades_corredores(plan_prueba, cadenas{nro_cadena}.CapacidadDecisionesPrimarias, 'Punto verificacion 1');
                end

                existe_cambio_global = false;

                proyectos_cambiados_prueba = [];
                etapas_originales_plan_actual = [];
                etapas_nuevas_plan_prueba = [];
                % genera nuevo trial

                [proyectos_modificar, etapas_originales, nuevas_etapas, capacidades_plan_prueba]= this.modifica_plan(plan_prueba, nro_cadena, cadenas{nro_cadena}.CapacidadDecisionesPrimarias);

                if nivel_debug > 2
                    this.debug_verifica_capacidades_corredores(plan_prueba, capacidades_plan_prueba, 'Punto verificacion 2');
                end

                if nivel_debug > 1
                    texto = ['      Proyectos modificados (' num2str(length(proyectos_modificar)) '):'];
                    prot.imprime_texto(texto);
                    for ii = 1:length(proyectos_modificar)
                        texto = ['       ' num2str(proyectos_modificar(ii)) ' de etapa ' num2str(etapas_originales(ii)) ' a etapa ' num2str(nuevas_etapas(ii))];
                        prot.imprime_texto(texto);
                    end

                    texto = ['Imprime plan modificado en paso ' num2str(paso_actual)];
                    prot.imprime_texto(texto);
                    plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                    plan_prueba.imprime_plan_expansion();
                end

                if ~isequal(etapas_originales, nuevas_etapas)
                    existe_cambio_global = true;
                    % se actualiza la red y se calcula nuevo totex de
                    % proyectos modificados
                    desde_etapa = min(min(etapas_originales), min(nuevas_etapas));
                    hasta_etapa = min(cantidad_etapas, max(max(etapas_originales), max(nuevas_etapas)));

                    nro_etapa = desde_etapa-1;
%                    for nro_etapa = desde_etapa:hasta_etapa
                    while nro_etapa < hasta_etapa
                        nro_etapa = nro_etapa + 1;
                        for jj = 1:length(proyectos_modificar)
                            if etapas_originales(jj) < cantidad_etapas + 1 && ...
                                etapas_originales(jj) < nuevas_etapas(jj) && ...
                                nro_etapa >= etapas_originales(jj) && ...
                                nro_etapa < nuevas_etapas(jj) 

                                % proyecto se retrasa, por lo que hay que eliminarlo del SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_modificar(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                            elseif etapas_originales(jj) > nuevas_etapas(jj) && ...
                                    nro_etapa >=  nuevas_etapas(jj) && ...
                                    nro_etapa < etapas_originales(jj) 
                                % proyecto se adelanta, por lo que hay que
                                % agregarlo al SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_modificar(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            end
                        end
                        
                        if nivel_debug >1
                            it_repara_plan = 0;
                            if nivel_debug >2
                                this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 3')
                            end
                        end
                        
                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                        this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                    
                        % genera plan sin ENS y sin recorte RES
                        while ~plan_prueba.es_valido(nro_etapa)
                            if nivel_debug >1
                                it_repara_plan = it_repara_plan + 1;
                                prot.imprime_texto(['Plan prueba no es valido en etapa ' num2str(nro_etapa) '. Se repara (cant. reparaciones: ' num2str(it_repara_plan)]);
                            end

                            cant_proy_comparar = this.pParOpt.CantProyCompararReparaPlan;

                            % ENS
                            [candidatos_ens, etapas_ens] = this.determina_espacio_busqueda_repara_plan(plan_prueba, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa,1);
                            proy_agregado = false;                            
                            if ~isempty(candidatos_ens)
                                proy_candidatos_ens = [];
                                etapas_cand_ens = [];
                                tope = min(length(candidatos_ens),cant_proy_comparar);                                

                                % prioridad a proyectos que están en plan
                                id_existentes = find(etapas_ens ~= cantidad_etapas+1);
                                if ~isempty(id_existentes)
                                    if length(id_existentes) > tope
                                        orden = randperm(length(id_existentes));
                                        proy_candidatos_ens = candidatos_ens(id_existentes(orden));
                                        etapas_cand_ens = etapas_ens(id_existentes(orden));
                                        proy_candidatos_ens = proy_candidatos_ens(1:tope);
                                        etapas_cand_ens = etapas_cand_ens(1:tope);
                                    else
                                        proy_candidatos_ens = candidatos_ens(id_existentes);
                                        etapas_cand_ens = etapas_ens(id_existentes);
                                    end
                                    tope = tope-length(proy_candidatos_ens);
                                end
                                if tope > 0
                                    id_no_existentes = find(etapas_ens == cantidad_etapas+1);
                                    if length(id_no_existentes) > tope
                                        orden = randperm(length(id_no_existentes));
                                        nuevos_cand = candidatos_ens(id_no_existentes(orden));
                                        nuevas_etapas_cand = etapas_ens(id_no_existentes(orden));
                                        
                                        proy_candidatos_ens = [proy_candidatos_ens nuevos_cand(1:tope)];
                                        etapas_cand_ens = [etapas_cand_ens nuevas_etapas_cand(1:tope)];
                                    else
                                        proy_candidatos_ens = [proy_candidatos_ens candidatos_ens(id_no_existentes)];
                                        etapas_cand_ens = [etapas_cand_ens etapas_ens(id_no_existentes)];
                                    end
                                end
                                
                                costo_falla_intento = zeros(tope, 1);
                                mejor_intento = 0;
                                tope = length(proy_candidatos_ens);
                                for i = 1:tope
                                    id_proy_selec = proy_candidatos_ens(i);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_selec);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                    eval = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion();
                                    costo_falla_intento(i) = sum(eval.CostoENS)+sum(eval.CostoRecorteRES);
                                    if costo_falla_intento(i) == 0 || tope == 1
                                        mejor_intento = i;
                                        break
                                    else
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proy_seleccionado);
                                    end
                                end
                                if mejor_intento == 0
                                    mejor_intento = find(costo_falla_intento == min(costo_falla_intento),1);
                                    % implementa mejor intento en SEP
                                    id_proy_seleccionado = proy_candidatos_ens(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                else
                                    % no es necesario agregarlo al SEP porque ya está
                                    id_proy_seleccionado = proy_candidatos_ens(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                end
                                etapa_seleccionado = etapas_cand_ens(mejor_intento);
                                
                                % implementa mejor intento en el plan
                                if etapas_cand_ens(mejor_intento) == cantidad_etapas+1
                                    plan_prueba.agrega_proyecto(nro_etapa, id_proy_seleccionado);
                                    if nivel_debug > 1
                                        prot.imprime_texto(['ENS: Se agrega proyecto ' num2str(id_proy_seleccionado) ' a etapa ' num2str(nro_etapa)]);
                                    end
                                else
                                    plan_prueba.adelanta_proyectos(id_proy_seleccionado, etapa_seleccionado, nro_etapa);
                                    if nivel_debug > 1
                                        prot.imprime_texto(['ENS: Se adelanta proyecto ' num2str(id_proy_seleccionado) ' de etapa ' num2str(etapa_seleccionado) ' a etapa ' num2str(nro_etapa)]);
                                    end
                                end
                                
                                this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                                
                                % actualiza capacidades
                                id_decision = proy_seleccionado.entrega_indice_decision_expansion();
                                delta_capacidad = proy_seleccionado.entrega_capacidad_adicional();
                                capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) = capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) + delta_capacidad;
                                proy_agregado = true;

                                % agrega proyecto seleccionado a proyectos modificar
                                id_proyectos_modificar = find(proyectos_modificar == id_proy_seleccionado);
                                if ~isempty(id_proyectos_modificar)
                                    % proyecto seleccionado pertenece a proyectos modificar. Se actualiza etapa fin
                                    nuevas_etapas(id_proyectos_modificar) = nro_etapa;
                                else
                                    % nuevo proyecto. Se agrega a proyectos modificar
                                    proyectos_modificar = [proyectos_modificar id_proy_seleccionado];
                                    etapas_originales = [etapas_originales etapa_seleccionado];
                                    nuevas_etapas = [nuevas_etapas nro_etapa];
                                end
                                
                                % modifica etapa fin de evaluación 
                                hasta_etapa = min(cantidad_etapas, max(max(etapas_originales), max(nuevas_etapas)));
                            end

                            % recorte RES
                            [candidatos_recorte, etapas_recorte] = this.determina_espacio_busqueda_repara_plan(plan_prueba, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa,2);
                            if ~isempty(candidatos_recorte)
                                proy_candidatos_recorte = [];
                                etapas_cand_recorte = [];
                                tope = min(length(candidatos_recorte),cant_proy_comparar);                                

                                % prioridad a proyectos que están en plan
                                id_existentes = find(etapas_recorte ~= cantidad_etapas+1);
                                if ~isempty(id_existentes)
                                    if length(id_existentes) > tope
                                        orden = randperm(length(id_existentes));
                                        proy_candidatos_recorte = candidatos_recorte(id_existentes(orden));
                                        etapas_cand_recorte = etapas_recorte(id_existentes(orden));
                                        proy_candidatos_recorte = proy_candidatos_recorte(1:tope);
                                        etapas_cand_recorte = etapas_cand_recorte(1:tope);
                                    else
                                        proy_candidatos_recorte = candidatos_recorte(id_existentes);
                                        etapas_cand_recorte = etapas_recorte(id_existentes);
                                    end
                                    tope = tope-length(proy_candidatos_recorte);
                                end
                                if tope > 0
                                    id_no_existentes = find(etapas_recorte == cantidad_etapas+1);
                                    if length(id_no_existentes) > tope
                                        orden = randperm(length(id_no_existentes));
                                        nuevos_cand = candidatos_recorte(id_no_existentes(orden));
                                        nuevas_etapas_cand = etapas_recorte(id_no_existentes(orden));
                                        
                                        proy_candidatos_recorte = [proy_candidatos_recorte nuevos_cand(1:tope)];
                                        etapas_cand_recorte = [etapas_cand_recorte nuevas_etapas_cand(1:tope)];
                                    else
                                        proy_candidatos_recorte = [proy_candidatos_recorte candidatos_recorte(id_no_existentes)];
                                        etapas_cand_recorte = [etapas_cand_recorte etapas_recorte(id_no_existentes)];
                                    end
                                end
                                
                                costo_falla_intento = zeros(tope, 1);
                                mejor_intento = 0;
                                tope = length(proy_candidatos_recorte);
                                for i = 1:tope
                                    id_proy_selec = proy_candidatos_recorte(i);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_selec);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                    eval = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion();
                                    costo_falla_intento(i) = sum(eval.CostoENS)+sum(eval.CostoRecorteRES);
                                    if costo_falla_intento(i) == 0 || tope == 1
                                        mejor_intento = i;
                                        break
                                    else
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proy_seleccionado);
                                    end
                                end
                                if mejor_intento == 0
                                    mejor_intento = find(costo_falla_intento == min(costo_falla_intento),1);
                                    % implementa mejor intento en SEP
                                    id_proy_seleccionado = proy_candidatos_recorte(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                else
                                    % no es necesario agregarlo al SEP porque ya está
                                    id_proy_seleccionado = proy_candidatos_recorte(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                end
                                etapa_seleccionado = etapas_cand_recorte(mejor_intento);
                                % implementa mejor intento en el plan
                                if etapas_cand_recorte(mejor_intento) == cantidad_etapas+1
                                    plan_prueba.agrega_proyecto(nro_etapa, id_proy_seleccionado);
                                    if nivel_debug > 1
                                        prot.imprime_texto(['Recorte: Se agrega proyecto ' num2str(id_proy_seleccionado) ' a etapa ' num2str(nro_etapa)]);
                                    end
                                else
                                    plan_prueba.adelanta_proyectos(id_proy_seleccionado, etapa_seleccionado, nro_etapa);
                                    if nivel_debug > 1
                                        prot.imprime_texto(['Recorte: Se adelanta proyecto ' num2str(id_proy_seleccionado) ' de etapa ' num2str(etapa_seleccionado) ' a etapa ' num2str(nro_etapa)]);
                                    end
                                end
                                
                                this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());

                                % actualiza capacidades
                                id_decision = proy_seleccionado.entrega_indice_decision_expansion();
                                delta_capacidad = proy_seleccionado.entrega_capacidad_adicional();
                                capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) = capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) + delta_capacidad;
                                proy_agregado = true;

                                % agrega proyecto seleccionado a proyectos modificar
                                id_proyectos_modificar = find(proyectos_modificar == id_proy_seleccionado);
                                if ~isempty(id_proyectos_modificar)
                                    % proyecto seleccionado pertenece a proyectos modificar. Se actualiza etapa fin
                                    nuevas_etapas(id_proyectos_modificar) = nro_etapa;
                                else
                                    % nuevo proyecto. Se agrega a proyectos modificar
                                    proyectos_modificar = [proyectos_modificar id_proy_seleccionado];
                                    etapas_originales = [etapas_originales etapa_seleccionado];
                                    nuevas_etapas = [nuevas_etapas nro_etapa];
                                end
                                
                                % modifica etapa fin de evaluación 
                                hasta_etapa = min(cantidad_etapas, max(max(etapas_originales), max(nuevas_etapas)));
                            end
                            

                            if ~proy_agregado
                                error = MException('cOptMCMC:mapea_espacio',['plan prueba no es válido en etapa ' num2str(nro_etapa) ' pero no se pudo reparar']);
                                throw(error)
                            end
                            
                            if nivel_debug >2
                                this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 3')
                            end
                            
                            if nivel_debug >2
                                this.debug_verifica_resultados_despacho_economico(cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), plan_prueba, nro_etapa, 'Punto verificacion 3')
                            end                            
                        end
                    end
                    id_sin_cambiar = (etapas_originales_plan_actual - etapas_nuevas_plan_prueba) == 0;
                    proyectos_modificar(id_sin_cambiar) = [];
                    etapas_originales(id_sin_cambiar) = [];
                    nuevas_etapas(id_sin_cambiar) = [];
                    
                    proyectos_cambiados_prueba = proyectos_modificar;
                    etapas_originales_plan_actual = etapas_originales;
                    etapas_nuevas_plan_prueba = nuevas_etapas;
                    
                    this.calcula_costos_totales(plan_prueba);

                    if nivel_debug > 2
                        for etapa_debug = 1:cantidad_etapas
                            this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{etapa_debug}, plan_prueba, etapa_debug, 'Punto verificacion 4')
                        end
                        this.debug_verifica_consistencia_plan_valido(plan_prueba, 'Punto verificacion 4');
                    end
                end

                if nivel_debug > 1
                    prot.imprime_texto('Fin proyectos modificar');
                    texto = ['      Totex plan actual: ' num2str(pPlan.entrega_totex_total())];
                    prot.imprime_texto(texto);
                    texto = ['      Totex plan prueba: ' num2str(plan_prueba.entrega_totex_total())];
                    prot.imprime_texto(texto);
                    prot.imprime_texto('      Se imprime plan prueba (modificado)');
                    plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                    plan_prueba.imprime_plan_expansion();
                    prot.imprime_texto('Comienzo proyectos optimizar');
                end

                % búsqueda local
                % los proyectos a optimizar ya están en orden aleatorio o
                % en base a las prioridades (en caso de haberlas)
%                proyectos_optimizar = this.selecciona_proyectos_optimizar(plan_prueba, proyectos_modificar);

                proyectos_optimizar = this.selecciona_proyectos_optimizar_bl_simple(plan_prueba, proyectos_modificar);
                if nivel_debug > 1
                    texto = ['      Proyectos seleccionados a optimizar(' num2str(length(proyectos_optimizar)) '):'];
                    for ii = 1:length(proyectos_optimizar)
                        texto = [texto ' ' num2str(proyectos_optimizar(ii))];
                    end
                    prot.imprime_texto(texto);                    
                end
                % optimiza proyectos seleccionados
                % TODO: Por ahora no se consideran opciones de uprating, en
                % donde hay proyectos secundarios (nuevas subestaciones)
                indice_optimizar_actual = 0;
                while indice_optimizar_actual < length(proyectos_optimizar)
                    indice_optimizar_actual = indice_optimizar_actual + 1;
                    proy_seleccionado = proyectos_optimizar(indice_optimizar_actual);
                                        
                    if nivel_debug > 1
                        texto = ['      Proyecto seleccionado optimizar ' num2str(indice_optimizar_actual) '/' num2str(length(proyectos_optimizar)) ':' num2str(proy_seleccionado)];																					  
                        prot.imprime_texto(texto);
                    end
                                        
                    evaluacion_actual = plan_prueba.entrega_evaluacion();
                    estructura_costos_actual = plan_prueba.entrega_estructura_costos();
                    plan_actual.Proyectos = plan_prueba.Proyectos; % plan_actual.Proyectos; plan_actual.Etapas;
                    plan_actual.Etapas = plan_prueba.Etapas; % plan_actual.Proyectos; plan_actual.Etapas;
                    totex_mejor_etapa = plan_prueba.entrega_totex_total();
                    mejor_etapa = 0;
                    
                    % modifica sep y evalua plan a partir de primera etapa cambiada
                    desde_etapa = plan_prueba.entrega_etapa_proyecto(proy_seleccionado, true); % true indica que entrega error si proyecto seleccionado no está en plan
                    proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionado);

                    if desde_etapa == 0
                        % por ahora se mantiene esta parte del código por si a futuro se consideran también proyectos que no están en el plan. Sin embargo, no debiera entrar aquí
                        desde_etapa = cantidad_etapas+1;
                        ultima_etapa_posible = cantidad_etapas;
                        hay_desplazamiento = false;
                    else
                        id_decision = proyecto.entrega_indice_decision_expansion();
                        estado_conducente = proyecto.entrega_estado_conducente();
                        proy_aguas_arriba = this.pAdmProy.entrega_id_proyectos_salientes_por_indice_decision_y_estado(id_decision, estado_conducente(1), estado_conducente(2));
                        ultima_etapa_posible = plan_prueba.entrega_ultima_etapa_posible_modificacion_proyecto(proy_aguas_arriba, desde_etapa)-1;
                        if desde_etapa <= ultima_etapa_posible
                            hay_desplazamiento = true;
                        else
                            hay_desplazamiento = false;
                        end
                    end
                    
                    for nro_etapa = desde_etapa:ultima_etapa_posible
                        % desplaza proyecto
                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                        if nro_etapa < cantidad_etapas
                            plan_prueba.desplaza_proyectos(proy_seleccionado, nro_etapa, nro_etapa + 1);
                        else
                            plan_prueba.elimina_proyectos(proy_seleccionado, nro_etapa);
                        end
                        
                        if nivel_debug > 2
                            this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 3');
                        end
                        
                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                        this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                        this.calcula_costos_totales(plan_prueba);
                        ultima_etapa_evaluada = nro_etapa;
                        
                        if plan_prueba.es_valido(nro_etapa) && plan_prueba.entrega_totex_total() < totex_mejor_etapa
                            % cambio intermedio produce mejora. Se
                            % acepta y se guarda
    
                            mejor_etapa = nro_etapa+1;
                            totex_mejor_etapa = plan_prueba.entrega_totex_total();
                            estructura_costos_actual_mejor_etapa = plan_prueba.entrega_estructura_costos();
                            plan_actual_mejor_etapa.Proyectos = plan_prueba.Proyectos;
                            plan_actual_mejor_etapa.Etapas = plan_prueba.Etapas;
                            evaluacion_actual_mejor_etapa = plan_prueba.entrega_evaluacion();

                            if nivel_debug > 1
                                if nro_etapa < this.pParOpt.CantidadEtapas
                                    texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' genera mejora. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                    prot.imprime_texto(texto);
                                else
                                    texto = ['      Desplazamiento en etapa final genera mejora. Proyectos se eliminan definitivamente. Totex final etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                    prot.imprime_texto(texto);
                                end
                            end

                            if nivel_debug > 2
                                this.debug_verifica_consistencia_plan_valido(plan_prueba, 'Punto verificacion 5');
                            end
                            
                        elseif ~plan_prueba.es_valido(nro_etapa)
                            if nivel_debug > 1
                                if nro_etapa < this.pParOpt.CantidadEtapas
                                    texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' hace que plan sea invalido. Se queda hasta aqui la evaluacion'];
                                    prot.imprime_texto(texto);
                                else
                                    texto = '      Desplazamiento en etapa final hace que plan sea invalido. Se deja hasta aqui la evaluacion';
                                    prot.imprime_texto(texto);
                                end
                            end
                                % Plan no es válido. No se sigue evaluando
                                % porque no tiene sentido
                                break;
                        else
                            % plan no genera mejora pero es válido
                            % Se determina mejora "potencial" que
                            % se puede obtener al eliminar el
                            % proyecto, con tal de ver si vale la
                            % pena o no seguir intentando                                
                            if nro_etapa < cantidad_etapas
                                delta_cinv_proyectado = this.calcula_delta_cinv_elimina_proyectos(plan_prueba, nro_etapa+1, proy_seleccionado);
                                existe_potencial = (plan_prueba.entrega_totex_total() - delta_cinv_proyectado) < totex_mejor_etapa;

                                if nivel_debug > 1
                                    texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' no genera mejora. ' ...
                                         'Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total()) ...
                                         '. Delta Cinv potencial: ' num2str(delta_cinv_proyectado) ...
                                         '. Totex potencial: ' num2str(plan_prueba.entrega_totex_total() - delta_cinv_proyectado)];
                                    if ~existe_potencial
                                        texto = [texto ' (*)'];
                                    end
                                    prot.imprime_texto(texto);
                                end
                                if ~existe_potencial
                                    % no hay potencial de mejora. No
                                    % intenta más
                                    break;
                                end 
                            else
                                if nivel_debug > 1
                                    texto = ['      Desplazamiento en etapa final no genera mejora. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                    prot.imprime_texto(texto);
                                end
                            end
                        end
                    end

                    % se deshace el cambio en el sep
                    plan_prueba.Proyectos = plan_actual.Proyectos;
                    plan_prueba.Etapas = plan_actual.Etapas;
                    
                    plan_prueba.inserta_estructura_costos(estructura_costos_actual);
                    plan_prueba.inserta_evaluacion(evaluacion_actual);

                    if hay_desplazamiento
                        for nro_etapa = desde_etapa:ultima_etapa_evaluada
                            % deshace los cambios hechos en los sep
                            % actuales hasta la etapa correcta
                            proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionado);
                            cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            
                            if nivel_debug > 2
                                this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 6')
                            end
                        end
                    end

                    if desde_etapa > 1
                        % verifica si adelantar el proyecto produce
                        % mejora
                        % determina primera etapa potencial a
                        % adelantar y proyectos de conectividad

                        if nivel_debug > 1                                        
                            texto = '      Se verifica si adelantar proyectos produce mejora';
                            prot.imprime_texto(texto);
                        end

                        nro_etapa = desde_etapa;
                        cantidad_intentos_fallidos_adelanta = 0;
                        cant_intentos_adelanta = 0;
                        cant_intentos_seguidos_sin_mejora_global = 0;
                        max_cant_intentos_fallidos_adelanta = this.pParOpt.CantIntentosFallidosAdelantaOptimiza;
                        ultimo_totex_adelanta = estructura_costos_actual.TotexTotal;
                        flag_salida = false;
                        % si proyecto a optimizar tiene proyecto
                        % dependiente, verifica que proyecto
                        % dependiente esté en el plan
                        proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionado);
                        if proyecto.TieneDependencia
                            [~, primera_etapa_posible]= plan_prueba.entrega_proyecto_dependiente(proyecto.entrega_indices_proyectos_dependientes(), false);
                            if primera_etapa_posible == 0
                                % proyecto dependiente no está en el plan. No se
                                % hace nada
                                flag_salida = true;
                            end
                        else
                            primera_etapa_posible = 1;
                        end
                        hay_adelanto = false;
                        if nro_etapa > primera_etapa_posible && ~flag_salida
                            hay_adelanto = true;
                        end

                        while nro_etapa > primera_etapa_posible && ~flag_salida
                            nro_etapa = nro_etapa - 1;
                            cant_intentos_adelanta = cant_intentos_adelanta + 1;
                            coper_previo_adelanta = plan_prueba.entrega_evaluacion(nro_etapa).CostoOperacion;

                            % agrega proyectos en sep actual en
                            % etapa actual

                            if nivel_debug > 2
                                this.debug_verifica_consistencia_plan_valido(plan_prueba, 'Punto verificacion 7');
                            end                        
                            
                            cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            if nro_etapa == cantidad_etapas
                                plan_prueba.agrega_proyecto(nro_etapa, proy_seleccionado);
                            else
                                plan_prueba.adelanta_proyectos(proy_seleccionado, nro_etapa + 1, nro_etapa);
                            end

                            if nivel_debug > 2
                                this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 8')
                            end
                            
                            %evalua red (proyectos ya se ingresaron
                            %al sep)
                            cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                            this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                            this.calcula_costos_totales(plan_prueba);
                            
                            ultima_etapa_evaluada = nro_etapa;                                
                            totex_actual_adelanta = plan_prueba.entrega_totex_total();
                            delta_totex_actual_adelanta = totex_actual_adelanta-ultimo_totex_adelanta;
                            coper_actual_adelanta = plan_prueba.entrega_evaluacion(nro_etapa).CostoOperacion;
                            delta_coper_actual_adelanta = coper_actual_adelanta - coper_previo_adelanta;
                            if cant_intentos_adelanta == 1
                                delta_totex_anterior_adelanta = delta_totex_actual_adelanta;
                                delta_coper_anterior_adelanta = delta_coper_actual_adelanta;
                            end
                            ultimo_totex_adelanta = totex_actual_adelanta;

                            if plan_prueba.es_valido(nro_etapa) && totex_actual_adelanta < totex_mejor_etapa
                                % adelantar el proyecto produce
                                % mejora. Se guarda resultado
                                cant_intentos_seguidos_sin_mejora_global = 0;
                                mejor_etapa = nro_etapa;
                                totex_mejor_etapa = plan_prueba.entrega_totex_total();
                                estructura_costos_actual_mejor_etapa = plan_prueba.entrega_estructura_costos();
                                plan_actual_mejor_etapa.Proyectos = plan_prueba.Proyectos;
                                plan_actual_mejor_etapa.Etapas = plan_prueba.Etapas;
                                evaluacion_actual_mejor_etapa = plan_prueba.entrega_evaluacion();
                                if nivel_debug > 1                                        
                                    texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ' genera mejora parcial. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                    prot.imprime_texto(texto);
                                end
                            elseif plan_prueba.es_valido(nro_etapa)
                                cant_intentos_seguidos_sin_mejora_global = cant_intentos_seguidos_sin_mejora_global + 1;

                                % se analizan las tendencias en delta
                                % totex y delta totex proyectados

                                delta_cinv_proyectado = this.calcula_delta_cinv_adelanta_proyectos(plan_prueba, nro_etapa, proy_seleccionado);
                                delta_coper_proyectado = this.estima_delta_coper_adelanta_proyectos(nro_etapa, delta_coper_actual_adelanta, delta_coper_anterior_adelanta);
                                totex_actual_proyectado = totex_actual_adelanta + delta_cinv_proyectado + delta_coper_proyectado;
                                if cant_intentos_seguidos_sin_mejora_global == 1
                                    totex_anterior_proyectado= totex_actual_proyectado;
                                end

                                if delta_totex_actual_adelanta > 0 && ...
                                        delta_totex_actual_adelanta > delta_totex_anterior_adelanta && ...
                                        totex_actual_proyectado > totex_anterior_proyectado
                                    cantidad_intentos_fallidos_adelanta = cantidad_intentos_fallidos_adelanta + 1;
                                elseif delta_totex_actual_adelanta < 0
                                    cantidad_intentos_fallidos_adelanta = max(0, cantidad_intentos_fallidos_adelanta -1);
                                end

                                totex_anterior_proyectado = totex_actual_proyectado;

                                if nivel_debug > 1
                                    if totex_actual_proyectado > totex_mejor_etapa
                                        texto_adicional = '(+)';
                                    else
                                        texto_adicional = '(-)';
                                    end
                                    if abs(delta_coper_anterior_adelanta) > 0
                                        correccion = (delta_coper_actual_adelanta - delta_coper_anterior_adelanta)/delta_coper_anterior_adelanta;
                                        if correccion > 0.5
                                            correccion = 0.5;
                                        elseif correccion < -0.5
                                            correccion = -0.5;
                                        end
                                    else
                                        correccion = 0;
                                    end

                                    texto_base = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ...
                                        ' no genera mejora. Totex actual etapa: ' num2str(round(totex_actual_adelanta,4))];
                                    texto = sprintf('%-88s %-15s %-10s %-15s %-10s %-17s %-10s %-14s %-6s %-19s %-10s %-17s %-10s %-4s %-16s %-5s ', ...
                                        texto_base, ' DtotexActual: ',num2str(round(delta_totex_actual_adelanta,4)),...
                                        ' DCoperActual: ', num2str(round(delta_coper_actual_adelanta,4)), ...
                                        ' DCoperAnterior: ',num2str(round(delta_coper_anterior_adelanta,4)), ...
                                        ' FCorreccion: ', num2str(correccion,4), ...
                                        ' DCoperProyectado: ', num2str(round(delta_coper_proyectado,4)), ...
                                        ' DTotalEstimado: ', num2str(round(totex_actual_proyectado,4)), ...
                                        texto_adicional, ...
                                        ' Cant. fallida: ', num2str(cantidad_intentos_fallidos_adelanta));

                                    prot.imprime_texto(texto);
                                end                                            
                            else
                                % Plan prueba no es valido
                                flag_salida = true;

                                if nivel_debug > 1
                                    texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ...
                                        ' hace que plan sea inválido. Se deja hasta aquí la evaluación'];
                                    prot.imprime_texto(texto);
                                end
                            end
                            % se verifica si hay que dejar el proceso
                            if cantidad_intentos_fallidos_adelanta >= max_cant_intentos_fallidos_adelanta
                                flag_salida = true;
                            end

                            delta_totex_anterior_adelanta = delta_totex_actual_adelanta;
                            delta_coper_anterior_adelanta = delta_coper_actual_adelanta;
                        end

                        % se deshacen los cambios en el sep
                        plan_prueba.Proyectos = plan_actual.Proyectos;
                        plan_prueba.Etapas = plan_actual.Etapas;
                        
                        plan_prueba.inserta_estructura_costos(estructura_costos_actual);
                        plan_prueba.inserta_evaluacion(evaluacion_actual);

                        if hay_adelanto
                            for nro_etapa = ultima_etapa_evaluada:desde_etapa-1
                                % deshace los cambios hechos en los sep
                                % actuales hasta la etapa correcta
                                % Ojo! orden inverso entre desplaza y
                                % elimina proyectos!
                                proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionado);
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);

                                if nivel_debug > 2
                                    this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 9')
                                end                                
                            end
                        end
                    end

                    if mejor_etapa ~=0
                        existe_cambio_global = true;
                        plan_prueba.Proyectos = plan_actual_mejor_etapa.Proyectos;
                        plan_prueba.Etapas = plan_actual_mejor_etapa.Etapas;
                        
                        plan_prueba.inserta_estructura_costos(estructura_costos_actual_mejor_etapa);
                        plan_prueba.inserta_evaluacion(evaluacion_actual_mejor_etapa);
                        id_existente = find(proyectos_cambiados_prueba == proy_seleccionado);

                        delta_capacidad = proyecto.entrega_capacidad_adicional();
                        id_decision = proyecto.entrega_indice_decision_expansion();
                        
                        if ~isempty(id_existente)
                            etapa_orig = etapas_nuevas_plan_prueba(id_existente);
                            etapas_nuevas_plan_prueba(id_existente) = mejor_etapa;
                            
                            % actualiza capacidades plan prueba
                            if etapa_orig > mejor_etapa
                                capacidades_plan_prueba(id_decision, mejor_etapa:etapa_orig-1) = ...
                                    capacidades_plan_prueba(id_decision, mejor_etapa:etapa_orig-1) + delta_capacidad;                                
                            else
                                %mejor_etapa > etapa_orig
                                capacidades_plan_prueba(id_decision, etapa_orig:mejor_etapa-1) = ...
                                    capacidades_plan_prueba(id_decision, etapa_orig:mejor_etapa-1) - delta_capacidad;                                
                            end
                        else
                            proyectos_cambiados_prueba = [proyectos_cambiados_prueba proy_seleccionado];
                            etapas_originales_plan_actual = [etapas_originales_plan_actual desde_etapa];
                            etapas_nuevas_plan_prueba = [etapas_nuevas_plan_prueba mejor_etapa];
                            
                            if desde_etapa > mejor_etapa
                                capacidades_plan_prueba(id_decision, mejor_etapa:desde_etapa-1) = ...
                                    capacidades_plan_prueba(id_decision, mejor_etapa:desde_etapa-1) + delta_capacidad;
                            else
                                % mejor_etapa > desde_etapa
                                capacidades_plan_prueba(id_decision, desde_etapa:mejor_etapa-1) = ...
                                    capacidades_plan_prueba(id_decision, desde_etapa:mejor_etapa-1) - delta_capacidad;
                            end
                        end
                        if nivel_debug > 1
                            texto = ['      Mejor etapa: ' num2str(mejor_etapa) '. Totex mejor etapa: ' num2str(plan_prueba.entrega_totex_total())];
                            prot.imprime_texto(texto);
                        end
                        
                        if nivel_debug > 2
                            this.debug_verifica_consistencia_plan_valido(plan_prueba, 'Punto verificacion 10');
                        end                        
                    else
                        plan_prueba.Proyectos = plan_actual.Proyectos;
                        plan_prueba.Etapas = plan_actual.Etapas;
                        plan_prueba.inserta_estructura_costos(estructura_costos_actual);
                        plan_prueba.inserta_evaluacion(evaluacion_actual);
                        
                        if nivel_debug > 2
                            this.debug_verifica_consistencia_plan_valido(plan_prueba, 'Punto verificacion 11');
                        end
                        
                        mejor_etapa = desde_etapa;
                        if nivel_debug > 1
                            prot.imprime_texto('      Cambio de etapa no produjo mejora ');
                        end
                    end
                    %lleva los cambios al sep hasta la mejor etapa
                    if mejor_etapa > desde_etapa 
                        for nro_etapa = desde_etapa:mejor_etapa-1
                            proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionado);
                            cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                        end
                    elseif mejor_etapa ~= 0 && mejor_etapa < desde_etapa
                        for nro_etapa = mejor_etapa:desde_etapa-1
                                proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionado);
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                        end
                    else
                        % nada. nro_etapa se fija en
                        % cantidad_etapas para verificación
                        % siguiente. En teoría no es necesario ya
                        % que no hubieron cambios
                        nro_etapa = cantidad_etapas;
                    end
                    
                    if this.iNivelDebug > 2
                        this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 12');
                        this.debug_verifica_capacidades_corredores(plan_prueba, capacidades_plan_prueba, 'Punto verificacion 12');
                    end

                end % fin busqueda local

                    
                if nivel_debug > 1
                    prot.imprime_texto('Fin busqueda local');
                    if ~existe_cambio_global
                        prot.imprime_texto('No hubo cambio en el plan');
                    else
                        prot.imprime_texto(['Totex original: ' num2str(pPlan.entrega_totex_total())]);
                        prot.imprime_texto(['Totex prueba  : ' num2str(plan_prueba.entrega_totex_total())]);
                        texto = sprintf('%-25s %-10s %-15s %-15s', 'Proy. seleccionados', 'Modificar', 'Etapa original', 'Nueva etapa');
                        prot.imprime_texto(texto);
                        for ii = 1:length(proyectos_cambiados_prueba)
                            proy_orig = proyectos_cambiados_prueba(ii);
                            etapa_orig = pPlan.entrega_etapa_proyecto(proy_orig, false);
                            nueva_etapa = plan_prueba.entrega_etapa_proyecto(proy_orig, false);
                            if ii <= length(proyectos_modificar)
                                texto = sprintf('%-25s %-10s %-15s %-15s', num2str(proy_orig), 'si', num2str(etapa_orig), num2str(nueva_etapa));
                            else
                                texto = sprintf('%-25s %-10s %-15s %-15s', num2str(proy_orig), 'no', num2str(etapa_orig), num2str(nueva_etapa));
                            end
                            prot.imprime_texto(texto);
                        end
                    end

                    if nivel_debug > 2
                        prot.imprime_texto('Plan original:');
                        pPlan.agrega_nombre_proyectos(this.pAdmProy);
                        pPlan.imprime_plan_expansion();

                        prot.imprime_texto('Plan prueba:');
                        plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                        plan_prueba.imprime_plan_expansion();
                    end
                end

                % determina si hay cambio o no
                if existe_cambio_global
                    if plan_prueba.entrega_totex_total() <= pPlan.entrega_totex_total()
                        acepta_cambio = true;
                    else
                        f_obj_prueba = plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                        f_obj_actual = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                        sigma = this.pParOpt.SigmaFuncionLikelihood;
                        prob_cambio = exp((-f_obj_prueba^2+f_obj_actual^2)/(2*sigma^2));

                        if nivel_debug > 1
                            prot.imprime_texto(['Probabilidad de cambio cadena ' num2str(nro_cadena) ': ' num2str(prob_cambio)]);
                        end
                        if rand < prob_cambio
                            acepta_cambio = true;
                        else
                            acepta_cambio = false;
                        end
                    end
                else
                    acepta_cambio = false;
                end

                if acepta_cambio
                    if nivel_debug > 1
                        prot.imprime_texto('Se acepta cambio de plan');
                        prot.imprime_texto(['Totex actual (f objetivo): ' num2str(pPlan.entrega_totex_total()) ' (' num2str(pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')']);
                        prot.imprime_texto(['Totex nuevo (f objetivo): ' num2str(plan_prueba.entrega_totex_total()) ' (' num2str(plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')']);
                    end
                    % se guarda nuevo plan en cadena
                    pPlan = plan_prueba;
                    cadenas{nro_cadena}.plan_actual = plan_prueba;
                    cadenas{nro_cadena}.CambiosEstado(paso_actual) = 1;
                    cadenas{nro_cadena}.Proyectos(paso_actual,:) = cadenas{nro_cadena}.Proyectos(paso_actual-1,:);
                    cadenas{nro_cadena}.CapacidadDecisionesPrimarias = capacidades_plan_prueba;
                    for ii = 1:length(proyectos_cambiados_prueba)
                        if etapas_nuevas_plan_prueba(ii) <= cantidad_etapas
                            cadenas{nro_cadena}.Proyectos(paso_actual,proyectos_cambiados_prueba(ii)) = etapas_nuevas_plan_prueba(ii);
                        else
                            cadenas{nro_cadena}.Proyectos(paso_actual,proyectos_cambiados_prueba(ii)) = 0;
                        end
                    end
                    cadenas{nro_cadena}.Totex(paso_actual) = pPlan.entrega_totex_total();                        
                    cadenas{nro_cadena}.FObj(paso_actual) = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                    % estadística
                    if pPlan.entrega_totex_total() < cadenas{nro_cadena}.MejorTotex
                        cadenas{nro_cadena}.MejorTotex = pPlan.entrega_totex_total();
                        cadenas{nro_cadena}.MejorFObj = pPlan.entrega_totex_total() - this.NPVCostosOperacionSinRestriccion;
                        if cadenas{nro_cadena}.TiempoEnLlegarAlOptimo == 0 && ...
                           round(cadenas{nro_cadena}.MejorTotex,5) == round(this.PlanOptimo.TotexTotal,5)
                            cadenas{nro_cadena}.TiempoEnLlegarAlOptimo = etime(clock,t_inicio_proceso);
                        end
                    end
                else
                    if nivel_debug > 1
                        prot.imprime_texto('No se acepta cambio de plan');
                        prot.imprime_texto(['Totex actual (f objetivo): ' num2str(pPlan.entrega_totex_total()) '(' num2str(pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')']);
                        prot.imprime_texto(['Totex no aceptado (f objetivo): ' num2str(plan_prueba.entrega_totex_total()) '(' num2str(plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')']);
                    end
                    cadenas{nro_cadena}.CambiosEstado(paso_actual) = 0;
                    cadenas{nro_cadena}.Proyectos(paso_actual,:) = cadenas{nro_cadena}.Proyectos(paso_actual-1,:);
                    cadenas{nro_cadena}.Totex(paso_actual) = pPlan.entrega_totex_total();
                    cadenas{nro_cadena}.FObj(paso_actual) = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                    % se deshacen los cambios en el SEP
                    desde_etapa = min(min(etapas_originales_plan_actual), min(etapas_nuevas_plan_prueba));
                    hasta_etapa = min(cantidad_etapas, max(max(etapas_originales_plan_actual), max(etapas_nuevas_plan_prueba)));

                    for nro_etapa = desde_etapa:hasta_etapa
                        for jj = 1:length(proyectos_cambiados_prueba)
                            if etapas_nuevas_plan_prueba(jj) < cantidad_etapas + 1 && ...
                               etapas_nuevas_plan_prueba(jj) < etapas_originales_plan_actual(jj) && ...
                               nro_etapa >= etapas_nuevas_plan_prueba(jj) && ...
                               nro_etapa < etapas_originales_plan_actual(jj) 
                                % proyecto se retrasa, por lo que hay que eliminarlo del SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_cambiados_prueba(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                            elseif etapas_nuevas_plan_prueba(jj) > etapas_originales_plan_actual(jj) && ...
                                   nro_etapa >=  etapas_originales_plan_actual(jj) && ...
                                   nro_etapa < etapas_nuevas_plan_prueba(jj) 
                                % proyecto se adelanta, por lo que hay que
                                % agregarlo al SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_cambiados_prueba(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            end
                        end
                        
                        if nivel_debug > 2
                            this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, pPlan, nro_etapa, 'Punto verificacion 6');
                        end

                    end
                end

                if nivel_debug > 1
                    prot.imprime_matriz([cadenas{nro_cadena}.Proyectos(paso_actual-1,:); cadenas{nro_cadena}.Proyectos(paso_actual,:)], 'Matriz proyectos pasos anterior y actual');
                    prot.imprime_texto([' Totex paso anterior: ' num2str(cadenas{nro_cadena}.Totex(paso_actual-1))]);
                    prot.imprime_texto([' Totex paso actual  : ' num2str(cadenas{nro_cadena}.Totex(paso_actual))]);                        

                    dt_paso = etime(clock,tinicio_paso);

                    totex_anterior = num2str(round(cadenas{nro_cadena}.Totex(paso_actual-1),4));

                    gap = round((cadenas{nro_cadena}.MejorTotex-this.TotexPlanOptimo)/(this.TotexPlanOptimo)*100,3);
                    gap_actual = round((cadenas{nro_cadena}.plan_actual.entrega_totex_total()-this.TotexPlanOptimo)/this.TotexPlanOptimo*100,3);
                    valido = cadenas{nro_cadena}.plan_actual.es_valido();
                    if ~valido
                        texto_valido = 'no';
                    else
                        texto_valido = '';
                    end
                    text = sprintf('%-7s %-5s %-7s %-15s %-15s %-15s %-10s %-10s %-10s %-10s',num2str(nro_cadena), ...
                                                                         num2str(paso_actual),...
                                                                         texto_valido,...
                                                                         num2str(round(cadenas{nro_cadena}.plan_actual.entrega_totex_total(),4)),...
                                                                         totex_anterior,...
                                                                         num2str(cadenas{nro_cadena}.MejorTotex),...
                                                                         num2str(gap_actual), ...
                                                                         num2str(gap), ...
                                                                         num2str(dt_paso));

                    disp(text);
                end

            end % fin todas las cadenas
            
            % actualiza capacidades
            cantidad_decisiones_primarias = this.pAdmProy.entrega_cantidad_decisiones_primarias();
            for corr = 1:cantidad_decisiones_primarias
                for cad = 1:cantidad_cadenas
                    this.CapacidadDecisionesPrimariasPorCadenas{corr}(cad,:) = cadenas{cad}.CapacidadDecisionesPrimarias(corr,:); 
                end
            end
        end

        function cadenas = mapea_espacio_secuencial_bl_detallada(this, cadenas, paso_actual, t_inicio_proceso, nivel_debug)
            cantidad_cadenas = this.pParOpt.CantidadCadenas;
            cantidad_etapas = this.pParOpt.CantidadEtapas;
            for nro_cadena = 1:cantidad_cadenas
                if nivel_debug > 0
                    prot = cProtocolo.getInstance;
                    texto = ['Comienzo proceso cadena ' num2str(nro_cadena) ' en paso actual ' num2str(paso_actual)];
                    prot.imprime_texto(texto);
                end

                pPlan = cadenas{nro_cadena}.plan_actual;
                if nivel_debug > 1
                    texto = ['Imprime plan actual cadena en paso ' num2str(paso_actual)];
                    prot.imprime_texto(texto);
                    pPlan.agrega_nombre_proyectos(this.pAdmProy);
                    pPlan.imprime_plan_expansion();

                    tinicio_paso = clock;
                end
%                    cadenas{nro_cadena}.Sigma(paso_actual,:) = cadenas{nro_cadena}.SigmaActual;

                plan_prueba = cPlanExpansion(pPlan.entrega_no() + 1);
                plan_prueba.Proyectos = pPlan.Proyectos;
                plan_prueba.Etapas = pPlan.Etapas;
                
                plan_prueba.inserta_evaluacion(pPlan.entrega_evaluacion());
                plan_prueba.inserta_estructura_costos(pPlan.entrega_estructura_costos());

                if nivel_debug > 2
                    this.debug_verifica_capacidades_corredores(plan_prueba, cadenas{nro_cadena}.CapacidadDecisionesPrimarias, 'Punto verificacion 1');
                end

                existe_cambio_global = false;

                proyectos_cambiados_prueba = [];
                etapas_originales_plan_actual = [];
                etapas_nuevas_plan_prueba = [];
                % genera nuevo trial

                [proyectos_modificar, etapas_originales, nuevas_etapas, capacidades_plan_prueba]= this.modifica_plan(plan_prueba, nro_cadena, cadenas{nro_cadena}.CapacidadDecisionesPrimarias);

                if nivel_debug > 1
                    texto = ['      Proyectos modificados (' num2str(length(proyectos_modificar)) '):'];
                    prot.imprime_texto(texto);
                    for ii = 1:length(proyectos_modificar)
                        texto = ['       ' num2str(proyectos_modificar(ii)) ' de etapa ' num2str(etapas_originales(ii)) ' a etapa ' num2str(nuevas_etapas(ii))];
                        prot.imprime_texto(texto);
                    end

                    texto = ['Imprime plan modificado en paso ' num2str(paso_actual)];
                    prot.imprime_texto(texto);
                    plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                    plan_prueba.imprime_plan_expansion();

                    if nivel_debug > 2
                        this.debug_verifica_capacidades_corredores(plan_prueba, capacidades_plan_prueba, 'Punto verificacion 2');
                    end                    
                end

                if ~isequal(etapas_originales, nuevas_etapas)
                    existe_cambio_global = true;
                    % se actualiza la red y se calcula nuevo totex de
                    % proyectos modificados
                    desde_etapa = min(min(etapas_originales), min(nuevas_etapas));
                    hasta_etapa = min(cantidad_etapas, max(max(etapas_originales), max(nuevas_etapas)));

                    nro_etapa = desde_etapa-1;
%                    for nro_etapa = desde_etapa:hasta_etapa
                    while nro_etapa < hasta_etapa
                        nro_etapa = nro_etapa + 1;
                        for jj = 1:length(proyectos_modificar)
                            if etapas_originales(jj) < cantidad_etapas + 1 && ...
                                etapas_originales(jj) < nuevas_etapas(jj) && ...
                                nro_etapa >= etapas_originales(jj) && ...
                                nro_etapa < nuevas_etapas(jj) 

                                % proyecto se retrasa, por lo que hay que eliminarlo del SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_modificar(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                            elseif etapas_originales(jj) > nuevas_etapas(jj) && ...
                                    nro_etapa >=  nuevas_etapas(jj) && ...
                                    nro_etapa < etapas_originales(jj) 
                                % proyecto se adelanta, por lo que hay que
                                % agregarlo al SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_modificar(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            end
                        end
                        
                        if nivel_debug >1
                            it_repara_plan = 0;
                            if nivel_debug > 2
                                this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 3')
                            end
                        end
                        
                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                        this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                    
                        if nivel_debug >2
                            this.debug_verifica_resultados_despacho_economico(cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), plan_prueba, nro_etapa, 'Punto verificacion 3')
                        end
                        
                        % genera plan sin ENS y sin recorte RES
                        while ~plan_prueba.es_valido(nro_etapa)
                            if nivel_debug >1
                                it_repara_plan = it_repara_plan + 1;
                                prot.imprime_texto(['Plan prueba no es valido en etapa ' num2str(nro_etapa) '. Se repara (cant. reparaciones: ' num2str(it_repara_plan)]);
                            end
                            
                            cant_proy_comparar = this.pParOpt.CantProyCompararReparaPlan;

                            % ENS
                            [candidatos_ens, etapas_ens] = this.determina_espacio_busqueda_repara_plan(plan_prueba, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa,1);
                            proy_agregado = false;                            
                            if ~isempty(candidatos_ens)
                                proy_candidatos_ens = [];
                                etapas_cand_ens = [];
                                tope = min(length(candidatos_ens),cant_proy_comparar);                                

                                % prioridad a proyectos que están en plan
                                id_existentes = find(etapas_ens ~= cantidad_etapas+1);
                                if ~isempty(id_existentes)
                                    if length(id_existentes) > tope
                                        orden = randperm(length(id_existentes));
                                        proy_candidatos_ens = candidatos_ens(id_existentes(orden));
                                        etapas_cand_ens = etapas_ens(id_existentes(orden));
                                        proy_candidatos_ens = proy_candidatos_ens(1:tope);
                                        etapas_cand_ens = etapas_cand_ens(1:tope);
                                    else
                                        proy_candidatos_ens = candidatos_ens(id_existentes);
                                        etapas_cand_ens = etapas_ens(id_existentes);
                                    end
                                    tope = tope-length(proy_candidatos_ens);
                                end
                                if tope > 0
                                    id_no_existentes = find(etapas_ens == cantidad_etapas+1);
                                    if length(id_no_existentes) > tope
                                        orden = randperm(length(id_no_existentes));
                                        nuevos_cand = candidatos_ens(id_no_existentes(orden));
                                        nuevas_etapas_cand = etapas_ens(id_no_existentes(orden));
                                        
                                        proy_candidatos_ens = [proy_candidatos_ens nuevos_cand(1:tope)];
                                        etapas_cand_ens = [etapas_cand_ens nuevas_etapas_cand(1:tope)];
                                    else
                                        proy_candidatos_ens = [proy_candidatos_ens candidatos_ens(id_no_existentes)];
                                        etapas_cand_ens = [etapas_cand_ens etapas_ens(id_no_existentes)];
                                    end
                                end
                                
                                costo_falla_intento = zeros(tope, 1);
                                mejor_intento = 0;
                                tope = length(proy_candidatos_ens);
                                for i = 1:tope
                                    id_proy_selec = proy_candidatos_ens(i);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_selec);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                    eval = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion();
                                    costo_falla_intento(i) = sum(eval.CostoENS)+sum(eval.CostoRecorteRES);
                                    if costo_falla_intento(i) == 0 || tope == 1
                                        mejor_intento = i;
                                        break
                                    else
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proy_seleccionado);
                                    end
                                end
                                if mejor_intento == 0
                                    mejor_intento = find(costo_falla_intento == min(costo_falla_intento),1);
                                    % implementa mejor intento en SEP
                                    id_proy_seleccionado = proy_candidatos_ens(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                else
                                    % no es necesario agregarlo al SEP porque ya está
                                    id_proy_seleccionado = proy_candidatos_ens(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                end
                                etapa_seleccionado = etapas_cand_ens(mejor_intento);
                                
                                % implementa mejor intento en el plan
                                if etapas_cand_ens(mejor_intento) == cantidad_etapas+1
                                    plan_prueba.agrega_proyecto(nro_etapa, id_proy_seleccionado);
                                    if nivel_debug > 1
                                        prot.imprime_texto(['ENS: Se agrega proyecto ' num2str(id_proy_seleccionado) ' a etapa ' num2str(nro_etapa)]);
                                    end
                                else
                                    plan_prueba.adelanta_proyectos(id_proy_seleccionado, etapa_seleccionado, nro_etapa);
                                    if nivel_debug > 1
                                        prot.imprime_texto(['ENS: Se adelanta proyecto ' num2str(id_proy_seleccionado) ' de etapa ' num2str(etapa_seleccionado) ' a etapa ' num2str(nro_etapa)]);
                                    end
                                end
                                
                                this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                                
                                % actualiza capacidades
                                id_decision = proy_seleccionado.entrega_indice_decision_expansion();
                                delta_capacidad = proy_seleccionado.entrega_capacidad_adicional();
                                capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) = capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) + delta_capacidad;
                                proy_agregado = true;

                                % agrega proyecto seleccionado a proyectos modificar
                                id_proyectos_modificar = find(proyectos_modificar == id_proy_seleccionado);
                                if ~isempty(id_proyectos_modificar)
                                    % proyecto seleccionado pertenece a proyectos modificar. Se actualiza etapa fin
                                    nuevas_etapas(id_proyectos_modificar) = nro_etapa;
                                else
                                    % nuevo proyecto. Se agrega a proyectos modificar
                                    proyectos_modificar = [proyectos_modificar id_proy_seleccionado];
                                    etapas_originales = [etapas_originales etapa_seleccionado];
                                    nuevas_etapas = [nuevas_etapas nro_etapa];
                                end
                                
                                % modifica etapa fin de evaluación 
                                hasta_etapa = min(cantidad_etapas, max(max(etapas_originales), max(nuevas_etapas)));
                            end

                            % recorte RES
                            [candidatos_recorte, etapas_recorte] = this.determina_espacio_busqueda_repara_plan(plan_prueba, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa,2);
                            if ~isempty(candidatos_recorte)
                                proy_candidatos_recorte = [];
                                etapas_cand_recorte = [];
                                tope = min(length(candidatos_recorte),cant_proy_comparar);                                

                                % prioridad a proyectos que están en plan
                                id_existentes = find(etapas_recorte ~= cantidad_etapas+1);
                                if ~isempty(id_existentes)
                                    if length(id_existentes) > tope
                                        orden = randperm(length(id_existentes));
                                        proy_candidatos_recorte = candidatos_recorte(id_existentes(orden));
                                        etapas_cand_recorte = etapas_recorte(id_existentes(orden));
                                        proy_candidatos_recorte = proy_candidatos_recorte(1:tope);
                                        etapas_cand_recorte = etapas_cand_recorte(1:tope);
                                    else
                                        proy_candidatos_recorte = candidatos_recorte(id_existentes);
                                        etapas_cand_recorte = etapas_recorte(id_existentes);
                                    end
                                    tope = tope-length(proy_candidatos_recorte);
                                end
                                if tope > 0
                                    id_no_existentes = find(etapas_recorte == cantidad_etapas+1);
                                    if length(id_no_existentes) > tope
                                        orden = randperm(length(id_no_existentes));
                                        nuevos_cand = candidatos_recorte(id_no_existentes(orden));
                                        nuevas_etapas_cand = etapas_recorte(id_no_existentes(orden));
                                        
                                        proy_candidatos_recorte = [proy_candidatos_recorte nuevos_cand(1:tope)];
                                        etapas_cand_recorte = [etapas_cand_recorte nuevas_etapas_cand(1:tope)];
                                    else
                                        proy_candidatos_recorte = [proy_candidatos_recorte candidatos_recorte(id_no_existentes)];
                                        etapas_cand_recorte = [etapas_cand_recorte etapas_recorte(id_no_existentes)];
                                    end
                                end
                                
                                costo_falla_intento = zeros(tope, 1);
                                mejor_intento = 0;
                                tope = length(proy_candidatos_recorte);
                                for i = 1:tope
                                    id_proy_selec = proy_candidatos_recorte(i);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_selec);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                    eval = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion();
                                    costo_falla_intento(i) = sum(eval.CostoENS)+sum(eval.CostoRecorteRES);
                                    if costo_falla_intento(i) == 0 || tope == 1
                                        mejor_intento = i;
                                        break
                                    else
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proy_seleccionado);
                                    end
                                end
                                if mejor_intento == 0
                                    mejor_intento = find(costo_falla_intento == min(costo_falla_intento),1);
                                    % implementa mejor intento en SEP
                                    id_proy_seleccionado = proy_candidatos_recorte(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                else
                                    % no es necesario agregarlo al SEP porque ya está
                                    id_proy_seleccionado = proy_candidatos_recorte(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                end
                                etapa_seleccionado = etapas_cand_recorte(mejor_intento);
                                % implementa mejor intento en el plan
                                if etapas_cand_recorte(mejor_intento) == cantidad_etapas+1
                                    plan_prueba.agrega_proyecto(nro_etapa, id_proy_seleccionado);
                                    if nivel_debug > 1
                                        prot.imprime_texto(['Recorte: Se agrega proyecto ' num2str(id_proy_seleccionado) ' a etapa ' num2str(nro_etapa)]);
                                    end
                                else
                                    plan_prueba.adelanta_proyectos(id_proy_seleccionado, etapa_seleccionado, nro_etapa);
                                    if nivel_debug > 1
                                        prot.imprime_texto(['Recorte: Se adelanta proyecto ' num2str(id_proy_seleccionado) ' de etapa ' num2str(etapa_seleccionado) ' a etapa ' num2str(nro_etapa)]);
                                    end
                                end
                                
                                this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());

                                % actualiza capacidades
                                id_decision = proy_seleccionado.entrega_indice_decision_expansion();
                                delta_capacidad = proy_seleccionado.entrega_capacidad_adicional();
                                capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) = capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) + delta_capacidad;
                                proy_agregado = true;

                                % agrega proyecto seleccionado a proyectos modificar
                                id_proyectos_modificar = find(proyectos_modificar == id_proy_seleccionado);
                                if ~isempty(id_proyectos_modificar)
                                    % proyecto seleccionado pertenece a proyectos modificar. Se actualiza etapa fin
                                    nuevas_etapas(id_proyectos_modificar) = nro_etapa;
                                else
                                    % nuevo proyecto. Se agrega a proyectos modificar
                                    proyectos_modificar = [proyectos_modificar id_proy_seleccionado];
                                    etapas_originales = [etapas_originales etapa_seleccionado];
                                    nuevas_etapas = [nuevas_etapas nro_etapa];
                                end
                                
                                % modifica etapa fin de evaluación 
                                hasta_etapa = min(cantidad_etapas, max(max(etapas_originales), max(nuevas_etapas)));
                            end
                            

                            if ~proy_agregado
                               error = MException('cOptMCMC:mapea_espacio',['plan prueba no es válido en etapa ' num2str(nro_etapa) ' pero no se pudo reparar']);
                               throw(error)
                            end
                            
                            if nivel_debug >2
                                this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 3')
                            end
                            
                            if nivel_debug >2
                                this.debug_verifica_resultados_despacho_economico(cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), plan_prueba, nro_etapa, 'Punto verificacion 3')
                            end

                        end
                    end
                    id_sin_cambiar = (etapas_originales_plan_actual - etapas_nuevas_plan_prueba) == 0;
                    proyectos_modificar(id_sin_cambiar) = [];
                    etapas_originales(id_sin_cambiar) = [];
                    nuevas_etapas(id_sin_cambiar) = [];
                    
                    proyectos_cambiados_prueba = proyectos_modificar;
                    etapas_originales_plan_actual = etapas_originales;
                    etapas_nuevas_plan_prueba = nuevas_etapas;
                    
                    this.calcula_costos_totales(plan_prueba);

                    if nivel_debug > 2
                        for etapa_debug = 1:cantidad_etapas
                            this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{etapa_debug}, plan_prueba, etapa_debug, 'Punto verificacion 4')
                        end
                        this.debug_verifica_consistencia_plan_valido(plan_prueba, 'Punto verificacion 4');
                        this.debug_verifica_capacidades_corredores(plan_prueba, capacidades_plan_prueba, 'Punto verificacion 2');
                    end
                end

                if nivel_debug > 1
                    prot.imprime_texto('Fin proyectos modificar');
                    texto = ['      Totex plan actual: ' num2str(pPlan.entrega_totex_total())];
                    prot.imprime_texto(texto);
                    texto = ['      Totex plan prueba: ' num2str(plan_prueba.entrega_totex_total())];
                    prot.imprime_texto(texto);
                    prot.imprime_texto('      Se imprime plan prueba (modificado)');
                    plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                    plan_prueba.imprime_plan_expansion();
                    prot.imprime_texto('Comienzo proyectos optimizar');
                    
                    estructura_costos_plan_base = plan_prueba.entrega_estructura_costos();
                    plan_expansion_plan_base.Proyectos = plan_prueba.Proyectos;
                    plan_expansion_plan_base.Etapas = plan_prueba.Etapas;
                    evaluacion_plan_base = plan_prueba.entrega_evaluacion();
                end

                % búsqueda local detallada
                proyectos_restringidos_para_eliminar = [];
                
                evaluacion_actual = plan_prueba.entrega_evaluacion();
                estructura_costos_actual = plan_prueba.entrega_estructura_costos();
                plan_actual.Proyectos = plan_prueba.Proyectos;
                plan_actual.Etapas = plan_prueba.Etapas;
                cant_busqueda_fallida = 0;
                proy_potenciales_eliminar = []; % no se verifica adelanta
                proy_potenciales_adelantar = []; %también se analiza elimina

                while cant_busqueda_fallida < this.pParOpt.BLDetalladaCantFallida
                    intento_paralelo_actual = 0;
                    intentos_actuales = cell(this.pParOpt.BLDetalladaCantProyCompararBase,0);
                    proyectos_restringidos_para_eliminar_intento = proyectos_restringidos_para_eliminar;
                    fuerza_continuar_comparacion = false;
                    cantidad_mejores_intentos_completo = 0;

                    proy_en_evaluacion = [];
                    while intento_paralelo_actual < this.pParOpt.BLDetalladaCantProyCompararBase || fuerza_continuar_comparacion
                        intento_paralelo_actual = intento_paralelo_actual +1;
                        plan_actual_intento = plan_actual;
                        evaluacion_actual_intento = evaluacion_actual;
                        estructura_costos_actual_intento = estructura_costos_actual;

                        proy_potenciales_evaluar = [proy_potenciales_eliminar proy_potenciales_adelantar];
                        proy_actual_es_potencial_elimina = false;
                        if length(proy_potenciales_evaluar) >= intento_paralelo_actual
                            if length(proy_potenciales_eliminar) >= intento_paralelo_actual
                                proy_actual_es_potencial_elimina = true;
                            end
                            proy_seleccionados = this.selecciona_proyectos_eliminar_desplazar_bl_detallada(plan_prueba, proyectos_restringidos_para_eliminar_intento, proy_en_evaluacion, proy_potenciales_evaluar(intento_paralelo_actual));
                        else
                            proy_seleccionados = this.selecciona_proyectos_eliminar_desplazar_bl_detallada(plan_prueba, proyectos_restringidos_para_eliminar_intento, proy_en_evaluacion);
                        end

%                       proy_seleccionados.seleccionado = [];
%                       proy_seleccionados.etapa_seleccionado = [];
%                       proy_seleccionados.conectividad_eliminar = [];
%                       proy_seleccionados.etapas_conectividad_eliminar = [];
%                       proy_seleccionados.conectividad_desplazar = [];
%                       proy_seleccionados.etapas_orig_conectividad_desplazar = [];
%                       proy_seleccionados.etapas_fin_conectividad_desplazar = [];
%                       proy_seleccionados.directo = 0/1

                        if isempty(proy_seleccionados.seleccionado)
                            intentos_actuales{intento_paralelo_actual}.Valido = false;
                            intentos_actuales{intento_paralelo_actual}.proy_seleccionados.seleccionado = [];

                            if intento_paralelo_actual >= this.pParOpt.BLDetalladaCantProyCompararSinMejora
                                fuerza_continuar_comparacion = false;
                            end

                            continue;
                        end

                        proy_en_evaluacion = [proy_en_evaluacion proy_seleccionados.seleccionado];
                        intentos_actuales{intento_paralelo_actual}.proy_seleccionados = proy_seleccionados;
                        intentos_actuales{intento_paralelo_actual}.Totex = 999999999999999999999;
                        intentos_actuales{intento_paralelo_actual}.Valido = false;
                        intentos_actuales{intento_paralelo_actual}.Proyectos = [];
                        intentos_actuales{intento_paralelo_actual}.Etapas = [];
                        intentos_actuales{intento_paralelo_actual}.SinMejoraIntermedia = false;
                        intentos_actuales{intento_paralelo_actual}.ExisteMejoraParcialAdelanta = false;
                        intentos_actuales{intento_paralelo_actual}.AdelantaProyectos = false;
                        intentos_actuales{intento_paralelo_actual}.AdelantaProyectosForzado = false;
                        intentos_actuales{intento_paralelo_actual}.DesplazaProyectosForzado = false;

                        %intentos_actuales{intento_paralelo_actual}.estructura_costos_actual = [];
                        %intentos_actuales{intento_paralelo_actual}.evaluacion_actual = [];
                        
                        if nivel_debug > 1
                            texto = sprintf('%-25s %-10s %-20s %-10s',...
                                            '      Totex Plan Base ', num2str(estructura_costos_plan_base.TotexTotal), ...
                                            'Totex plan actual', num2str(estructura_costos_actual.TotexTotal));
                            prot.imprime_texto(texto);
                        end
                    
                        % modifica sep y evalua plan a partir de primera etapa cambiada
                        desde_etapa = proy_seleccionados.etapa_seleccionado;  % etapas desplazar siempre es mayor que etapas eliminar
                        hasta_etapa = proy_seleccionados.ultima_etapa_posible - 1;

                        intentos_actuales{intento_paralelo_actual}.DesdeEtapaIntento = desde_etapa;
                        existe_mejora = false;
                        plan_actual_hasta_etapa = desde_etapa - 1;
                        plan_actual_intento_hasta_etapa = desde_etapa - 1;
                        proyectos_eliminar = [proy_seleccionados.conectividad_eliminar proy_seleccionados.seleccionado];
                        etapas_eliminar = [proy_seleccionados.etapas_conectividad_eliminar proy_seleccionados.etapa_seleccionado];
                        proyectos_desplazar = proy_seleccionados.conectividad_desplazar;
                        etapas_originales_desplazar = proy_seleccionados.etapas_orig_conectividad_desplazar;
                        etapas_desplazar = proy_seleccionados.etapas_fin_conectividad_desplazar;

                        for nro_etapa = desde_etapa:hasta_etapa
                            % desplaza proyectos a eliminar 
                            for k = length(proyectos_eliminar):-1:1
                                if etapas_eliminar(k) <= nro_etapa
                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_eliminar(k));
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    if nro_etapa < cantidad_etapas
                                        plan_prueba.desplaza_proyectos(proyectos_eliminar(k), nro_etapa, nro_etapa + 1);
                                    else
                                        plan_prueba.elimina_proyectos(proyectos_eliminar(k), nro_etapa);
                                    end
                                end
                            end
                            %desplaza proyectos
                            for k = length(proyectos_desplazar):-1:1
                                if nro_etapa >= etapas_originales_desplazar(k) && nro_etapa < etapas_desplazar(k) 
                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_desplazar(k));
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    plan_prueba.desplaza_proyectos(proyectos_desplazar(k), nro_etapa, nro_etapa + 1);
                                end
                            end

                            %evalua red 
                            cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                            this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());                            
                            this.calcula_costos_totales(plan_prueba);
                            ultima_etapa_evaluada = nro_etapa;

                            if nivel_debug > 2
                                this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 5');
                                this.debug_verifica_consistencia_costos_totales_plan(plan_prueba, 'Punto verificacion 5');
                            end

                            if plan_prueba.es_valido(nro_etapa) && plan_prueba.entrega_totex_total() < estructura_costos_actual_intento.TotexTotal
                                % cambio intermedio produce mejora. Se
                                % sigue evaluando
                                % acepta y se guarda
                                plan_actual_intento.Proyectos = plan_prueba.Proyectos;
                                plan_actual_intento.Etapas = plan_prueba.Etapas;
                                estructura_costos_actual_intento = plan_prueba.entrega_estructura_costos();
                                evaluacion_actual_intento = plan_prueba.entrega_evaluacion();
                                existe_mejora = true;
                                plan_actual_intento_hasta_etapa = nro_etapa;
                                if this.iNivelDebug > 1                                        
                                    if nro_etapa < cantidad_etapas
                                        texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' genera mejora. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                        prot.imprime_texto(texto);
                                    else
                                        texto = ['      Desplazamiento en etapa final genera mejora. Proyectos se eliminan definitivamente. Totex final etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                        prot.imprime_texto(texto);
                                    end
                                end
                            elseif ~plan_prueba.es_valido(nro_etapa)
                                intentos_actuales{intento_paralelo_actual}.SinMejoraIntermedia = true;

                                if this.iNivelDebug > 1
                                    if nro_etapa < cantidad_etapas
                                        texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' hace que plan sea invalido. Se queda hasta aqui la evaluacion'];
                                        prot.imprime_texto(texto);
                                    else
                                        texto = '      Desplazamiento en etapa final hace que plan sea invalido. Se deja hasta aqui la evaluacion';
                                        prot.imprime_texto(texto);
                                    end
                                end
                                % Plan no es válido. No se sigue evaluando
                                % porque no tiene sentido
                                break;
                            else
                                % plan es válido pero no genera mejora.
                                % Se determina mejora "potencial" que
                                % se puede obtener al eliminar el
                                % proyecto, con tal de ver si vale la
                                % pena o no seguir intentando. 
                                if this.pParOpt.BLDetalladaPrioridadDesplazaSobreElimina && existe_mejora
                                    if this.iNivelDebug > 1
                                        texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' no genera mejora. ' ...
                                                 'Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total()) ...
                                                 '. No se sigue evaluando ya que ya hay resultado valido y flag prioridad desplaza sobre elimina esta activo'];
                                        prot.imprime_texto(texto);
                                    end

                                    break;
                                end
                                intentos_actuales{intento_paralelo_actual}.SinMejoraIntermedia = true;
                                if nro_etapa < cantidad_etapas
                                    delta_cinv = this.calcula_delta_cinv_elimina_desplaza_proyectos(plan_prueba, nro_etapa+1, proyectos_eliminar, proyectos_desplazar, etapas_originales_desplazar, etapas_desplazar);
                                    existe_potencial = (plan_prueba.entrega_totex_total() - delta_cinv) < estructura_costos_actual_intento.TotexTotal;
                                    if this.iNivelDebug > 1
                                        texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' no genera mejora. ' ...
                                                 'Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total()) ...
                                                 '. Delta Cinv potencial: ' num2str(delta_cinv) ...
                                                 '. Totex potencial: ' num2str(plan_prueba.entrega_totex_total() - delta_cinv)];
                                        if ~existe_potencial
                                            texto = [texto ' (*)'];
                                        end
                                        prot.imprime_texto(texto);
                                    end
                                    if ~existe_potencial
                                        break;
                                    end
                                else
                                    if this.iNivelDebug > 1
                                        texto = ['      Desplazamiento en etapa final no genera mejora. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                        prot.imprime_texto(texto);
                                    end
                                end
                            end
                        end

                        if nivel_debug > 2
                            this.debug_verifica_consistencia_costos_totales_plan(plan_prueba, 'Punto verificacion 6');
                        end


                        % se evaluaron todas las etapas. Determina el estado final del plan y agrega proyectos ya evaluados para futuros intentos
                        proyectos_restringidos_para_eliminar_intento = [proyectos_restringidos_para_eliminar_intento proy_seleccionados.seleccionado];

                        mejor_totex_elimina_desplaza = inf;
                        if existe_mejora
                            intentos_actuales{intento_paralelo_actual}.Proyectos = plan_actual_intento.Proyectos;
                            intentos_actuales{intento_paralelo_actual}.Etapas = plan_actual_intento.Etapas;
                            intentos_actuales{intento_paralelo_actual}.estructura_costos_actual = estructura_costos_actual_intento;
                            intentos_actuales{intento_paralelo_actual}.evaluacion_actual = evaluacion_actual_intento;
                            intentos_actuales{intento_paralelo_actual}.Valido = true;
                            intentos_actuales{intento_paralelo_actual}.Totex = estructura_costos_actual_intento.TotexTotal;
                            intentos_actuales{intento_paralelo_actual}.PlanActualHastaEtapa = plan_actual_intento_hasta_etapa;
                            if intentos_actuales{intento_paralelo_actual}.SinMejoraIntermedia == false
                                cantidad_mejores_intentos_completo = cantidad_mejores_intentos_completo + 1;
                            end
                            mejor_totex_elimina_desplaza = estructura_costos_actual_intento.TotexTotal;
                        else
                            % quiere decir que no existe mejora en
                            % ningún desplazamiento
                            % proyectos_eliminar se agrega a grupo de
                            % proyectos restringidos a eliminar
                            intentos_actuales{intento_paralelo_actual}.Valido = false;
                            proyectos_restringidos_para_eliminar = [proyectos_restringidos_para_eliminar proy_seleccionados.seleccionado];
                        end

                        % se deshace el cambio en el sep
                        plan_prueba.Proyectos = plan_actual.Proyectos;
                        plan_prueba.Etapas = plan_actual.Etapas;
                        plan_prueba.inserta_estructura_costos(estructura_costos_actual);
                        plan_prueba.inserta_evaluacion(evaluacion_actual);

                        for nro_etapa = plan_actual_hasta_etapa + 1:ultima_etapa_evaluada
                            % deshace los cambios hechos en los sep
                            % actuales hasta la etapa correcta
                            % Ojo! orden inverso entre desplaza y
                            % elimina proyectos!
                            for k = 1:length(proyectos_desplazar)
                                if nro_etapa >= etapas_originales_desplazar(k) && nro_etapa < etapas_desplazar(k) 
                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_desplazar(k));
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                end
                            end

                            for k = 1:length(proyectos_eliminar)
                                if etapas_eliminar(k) <= nro_etapa
                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_eliminar(k));
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                end
                            end
                        end

                        if nivel_debug > 2
                            this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{etapa_debug}, plan_prueba, etapa_debug, 'Punto verificacion 7')
                            this.debug_verifica_consistencia_costos_totales_plan(plan_prueba, 'Punto verificacion 7')
                        end
                        
                        if desde_etapa > 1 && ~proy_actual_es_potencial_elimina
                            % verifica si adelantar el proyecto produce mejora. Determina primera etapa potencial a adelantar y proyectos de conectividad

                            if nivel_debug > 1                                        
                                texto = '      Se verifica si adelantar proyectos produce mejora';
                                prot.imprime_texto(texto);
                            end

                            proy_adelantar = this.selecciona_proyectos_a_adelantar(plan_prueba, desde_etapa, proy_seleccionados.seleccionado);
                            % proy_adelantar.seleccionado
                            % proy_adelantar.etapa_seleccionado
                            % proy_adelantar.seleccion_directa
                            % proy_adelantar.primera_etapa_posible = [];
                            % proy_adelantar.proy_conect_adelantar = [];
                            % proy_adelantar.etapas_orig_conect = [];

                            nro_etapa = desde_etapa;
                            flag_salida = false;
                            existe_resultado_adelanta = false;
                            max_cant_intentos_fallidos_adelanta = this.pParOpt.CantIntentosFallidosAdelantaOptimiza;
                            cant_intentos_fallidos_adelanta = 0;
                            cant_intentos_adelanta = 0;
                            ultimo_totex_adelanta = estructura_costos_actual.TotexTotal;

                            while nro_etapa > proy_adelantar.primera_etapa_posible && ~flag_salida
                                nro_etapa = nro_etapa - 1;
                                existe_mejora_parcial = false;
                                cant_intentos_adelanta = cant_intentos_adelanta + 1;
                                % agrega proyectos en sep actual en
                                % etapa actual
                                for k = 1:length(proy_adelantar.proy_conect_adelantar)
                                    if nro_etapa < proy_adelantar.etapas_orig_conect(k) 
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.proy_conect_adelantar(k));
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                        plan_prueba.adelanta_proyectos(proy_adelantar.proy_conect_adelantar(k), nro_etapa + 1, nro_etapa);
                                    end
                                end
                                proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.seleccionado);
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                plan_prueba.adelanta_proyectos(proy_adelantar.seleccionado, nro_etapa + 1, nro_etapa);

                                %evalua red
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());                            
                                this.calcula_costos_totales(plan_prueba);
                                ultima_etapa_evaluada = nro_etapa;

                                if nivel_debug > 2
                                    this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 8')
                                    this.debug_verifica_consistencia_costos_totales_plan(plan_prueba, 'Punto verificacion 8')
                                end
                                
                                if cant_intentos_adelanta == 1
                                    delta_actual_adelanta = plan_prueba.entrega_totex_total()-ultimo_totex_adelanta;
                                else
                                    delta_nuevo_adelanta = plan_prueba.entrega_totex_total()-ultimo_totex_adelanta;
                                    if delta_nuevo_adelanta > 0 && delta_nuevo_adelanta > delta_actual_adelanta
                                        cant_intentos_fallidos_adelanta = cant_intentos_fallidos_adelanta + 1;
                                    elseif delta_nuevo_adelanta < 0
                                        cant_intentos_fallidos_adelanta = 0;
                                    end
                                    delta_actual_adelanta = delta_nuevo_adelanta;
                                end
                                ultimo_totex_adelanta = plan_prueba.entrega_totex_total();

                                if ~existe_resultado_adelanta
                                    % resultado se compara con
                                    % estructura de costos actuales
                                    if plan_prueba.entrega_totex_total() < estructura_costos_actual.TotexTotal
                                        % adelantar el proyecto produce
                                        % mejora. Se guarda resultado
                                        existe_resultado_adelanta = true;
                                        existe_mejora_parcial = true;
                                        plan_actual_intento_adelanta.Proyectos = plan_prueba.Proyectos;
                                        plan_actual_intento_adelanta.Etapas = plan_prueba.Etapas;
                                        estructura_costos_actual_intento_adelanta = plan_prueba.entrega_estructura_costos();
                                        evaluacion_actual_intento_adelanta = plan_prueba.entrega_evaluacion();
                                        plan_actual_intento_adelanta_hasta_etapa = nro_etapa;
                                        if this.iNivelDebug > 1                                        
                                            texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ' genera mejora parcial. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                            prot.imprime_texto(texto);
                                        end
                                    else
                                        if nivel_debug > 1
                                            texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ...
                                                ' no genera mejora. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())...
                                                ' Delta actual adelanta: ' num2str(delta_actual_adelanta) ...
                                                ' Cant. intentos fallidos adelanta: ' num2str(cant_intentos_fallidos_adelanta)];                                                    
                                            prot.imprime_texto(texto);
                                        end    
                                    end
                                else
                                    % resultado se compara con último
                                    % resultado
                                    if plan_prueba.entrega_totex_total() < estructura_costos_actual_intento_adelanta.TotexTotal
                                        % adelantar el proyecto produce
                                        % mejora. Se guarda resultado
                                        existe_mejora_parcial = true;
                                        plan_actual_intento_adelanta.Proyectos = plan_prueba.Proyectos;
                                        plan_actual_intento_adelanta.Etapas = plan_prueba.Etapas;
                                        estructura_costos_actual_intento_adelanta = plan_prueba.entrega_estructura_costos();
                                        evaluacion_actual_intento_adelanta = plan_prueba.entrega_evaluacion();
                                        plan_actual_intento_adelanta_hasta_etapa = nro_etapa;
                                        if this.iNivelDebug > 1                                        
                                            texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ' genera mejora parcial. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                            prot.imprime_texto(texto);
                                        end
                                    else
                                        if this.iNivelDebug > 1                                        
                                            texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ...
                                                ' no genera mejora. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total()) ...
                                                ' Delta actual adelanta: ' num2str(delta_actual_adelanta) ...
                                                ' Cant. intentos fallidos adelanta: ' num2str(cant_intentos_fallidos_adelanta)];
                                            prot.imprime_texto(texto);
                                        end                                            
                                    end
                                end

                                if existe_mejora_parcial
                                    % verifica si mejora parcial es
                                    % mejor que resultado de
                                    % elimina/desplaza
                                    intentos_actuales{intento_paralelo_actual}.ExisteMejoraParcialAdelanta = true;
                                    if ~intentos_actuales{intento_paralelo_actual}.Valido || ...
                                        estructura_costos_actual_intento_adelanta.TotexTotal < intentos_actuales{intento_paralelo_actual}.Totex || ...
                                        this.pParOpt.BLDetalladaPrioridadAdelantaSobreDesplaza

                                        if estructura_costos_actual_intento_adelanta.TotexTotal > mejor_totex_elimina_desplaza
                                            intentos_actuales{intento_paralelo_actual}.AdelantaProyectosForzado = true;
                                        else
                                            intentos_actuales{intento_paralelo_actual}.AdelantaProyectosForzado = false;                                                
                                        end
                                        % se acepta el cambio
                                        intentos_actuales{intento_paralelo_actual}.Proyectos = plan_actual_intento_adelanta.Proyectos;
                                        intentos_actuales{intento_paralelo_actual}.Etapas = plan_actual_intento_adelanta.Etapas;
                                        intentos_actuales{intento_paralelo_actual}.estructura_costos_actual = estructura_costos_actual_intento_adelanta;
                                        intentos_actuales{intento_paralelo_actual}.evaluacion_actual = evaluacion_actual_intento_adelanta;
                                        intentos_actuales{intento_paralelo_actual}.Valido = true;
                                        intentos_actuales{intento_paralelo_actual}.Totex = estructura_costos_actual_intento_adelanta.TotexTotal;
                                        intentos_actuales{intento_paralelo_actual}.PlanActualHastaEtapa = plan_actual_intento_adelanta_hasta_etapa;
                                        intentos_actuales{intento_paralelo_actual}.AdelantaProyectos = true;
                                        intentos_actuales{intento_paralelo_actual}.proy_seleccionados = proy_adelantar;
                                        intentos_actuales{intento_paralelo_actual}.SinMejoraIntermedia = false;
                                        cantidad_mejores_intentos_completo = cantidad_mejores_intentos_completo + 1;
                                    end
                                else
                                    % se verifica si se alcanzó el máximo número de intentos fallidos adelanta
                                    if cant_intentos_fallidos_adelanta >= max_cant_intentos_fallidos_adelanta
                                        flag_salida = true;
                                    end
                                end
                            end
                            % se deshacen los cambios en el sep
                            plan_prueba.Proyectos = plan_actual.Proyectos;
                            plan_prueba.Etapas = plan_actual.Etapas;
                            plan_prueba.inserta_estructura_costos(estructura_costos_actual);
                            plan_prueba.inserta_evaluacion(evaluacion_actual);

                            for nro_etapa = ultima_etapa_evaluada:desde_etapa-1
                                % deshace los cambios hechos en los sep
                                % actuales hasta la etapa correcta
                                % Ojo! orden inverso entre desplaza y
                                % elimina proyectos!
                                proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.seleccionado);
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                for k = length(proy_adelantar.proy_conect_adelantar):-1:1
                                    if nro_etapa < proy_adelantar.etapas_orig_conect(k) 
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.proy_conect_adelantar(k));
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    end
                                end

                                if nivel_debug > 2
                                    this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 8')
                                end                                
                            end
                            
                            if nivel_debug > 2
                                this.debug_verifica_consistencia_costos_totales_plan(plan_prueba, 'Punto verificacion 9')
                            end
                        end
                        
                        % se verifica si hay que seguir comparando
                        if fuerza_continuar_comparacion == false && ...
                           intento_paralelo_actual == this.pParOpt.BLDetalladaCantProyCompararBase && ...
                           cantidad_mejores_intentos_completo < this.pParOpt.BLDetalladaCantProyCompararBase && ...
                           this.pParOpt.BLDetalladaCantProyCompararSinMejora > this.pParOpt.BLDetalladaCantProyCompararBase

                            fuerza_continuar_comparacion = true;
                        elseif fuerza_continuar_comparacion == true && intento_paralelo_actual == this.pParOpt.BLDetalladaCantProyCompararSinMejora
                            fuerza_continuar_comparacion = false;
                        end
                    end
                    
                    % determina mejor intento
                    existe_mejora = false;
                    mejor_intento_sin_mejora_intermedia = false;
                    mejor_totex = 0;
                    mejor_intento_es_adelanta = false;
                    mejor_intento_es_elimina = false;
                    mejor_intento_es_desplaza = false;
                    id_mejor_plan_intento = 0;
                    for kk = 1:intento_paralelo_actual
                        if intentos_actuales{kk}.Valido
                            existe_mejora = true;
                            intento_actual_sin_mejora_intermedia = intentos_actuales{kk}.SinMejoraIntermedia;
                            intento_actual_es_adelanta = intentos_actuales{kk}.AdelantaProyectos;
                            intento_actual_es_elimina = intentos_actuales{kk}.PlanActualHastaEtapa == this.pParOpt.CantidadEtapas;
                            intento_actual_es_desplaza = intentos_actuales{kk}.PlanActualHastaEtapa < this.pParOpt.CantidadEtapas;
                            existe_mejora_adelanta = intentos_actuales{kk}.ExisteMejoraParcialAdelanta;
                            if ~intento_actual_sin_mejora_intermedia && ~intento_actual_es_adelanta && ~existe_mejora_adelanta
                                if isempty(find(proy_potenciales_eliminar == intentos_actuales{kk}.proy_seleccionados.seleccionado, 1))
                                    proy_potenciales_eliminar = [proy_potenciales_eliminar intentos_actuales{kk}.proy_seleccionados.seleccionado];
                                end
                                % elimina proyecto seleccionado de
                                % potenciales a adelantar en caso de que
                                % esté
                                proy_potenciales_adelantar(proy_potenciales_adelantar == intentos_actuales{kk}.proy_seleccionados.seleccionado) = [];
                            elseif intento_actual_es_adelanta || existe_mejora_adelanta
                                if isempty(find(proy_potenciales_adelantar == intentos_actuales{kk}.proy_seleccionados.seleccionado, 1))
                                    proy_potenciales_adelantar = [proy_potenciales_adelantar intentos_actuales{kk}.proy_seleccionados.seleccionado];
                                end
                                % elimina proyecto seleccionado de
                                % potenciales a eliminar en caso de que
                                % esté
                                proy_potenciales_eliminar(proy_potenciales_eliminar == intentos_actuales{kk}.proy_seleccionados.seleccionado) = [];
                            end
                            es_mejor_intento = false;
                            if id_mejor_plan_intento == 0
                                es_mejor_intento = true;
                            else
                                if intento_actual_es_adelanta
                                    if ~mejor_intento_es_adelanta
                                        es_mejor_intento = true;
                                    else
                                        if intentos_actuales{kk}.Totex < mejor_totex
                                            es_mejor_intento = true;
                                        end
                                    end 
                                elseif this.pParOpt.BLDetalladaPrioridadDesplazaSobreElimina && ...
                                        intento_actual_es_desplaza
                                    if mejor_intento_es_elimina
                                        es_mejor_intento = true;
                                    elseif mejor_intento_es_desplaza
                                        if intentos_actuales{kk}.Totex < mejor_totex
                                            es_mejor_intento = true;
                                        end
                                    end
                                else
                                    % intento es elimina. 
                                    if intentos_actuales{kk}.Totex < mejor_totex
                                        if ~mejor_intento_es_adelanta 
                                            if ~this.pParOpt.BLDetalladaPrioridadDesplazaSobreElimina
                                                if intento_actual_sin_mejora_intermedia <= mejor_intento_sin_mejora_intermedia
                                                    es_mejor_intento = true;
                                                end
                                            else
                                                if ~mejor_intento_es_desplaza
                                                    if intento_actual_sin_mejora_intermedia <= mejor_intento_sin_mejora_intermedia
                                                        es_mejor_intento = true;
                                                    end
                                                end
                                            end
                                        end
                                    else
                                        if ~mejor_intento_es_adelanta 
                                            if ~this.pParOpt.BLDetalladaPrioridadDesplazaSobreElimina
                                                if intento_actual_sin_mejora_intermedia < mejor_intento_sin_mejora_intermedia
                                                    es_mejor_intento = true;
                                                end
                                            else
                                                if ~mejor_intento_es_desplaza
                                                    if intento_actual_sin_mejora_intermedia < mejor_intento_sin_mejora_intermedia
                                                        es_mejor_intento = true;
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end

                            if es_mejor_intento
                                id_mejor_plan_intento = kk;
                                mejor_totex = intentos_actuales{kk}.Totex;
                                mejor_intento_sin_mejora_intermedia = intento_actual_sin_mejora_intermedia;
                                mejor_intento_es_adelanta = intento_actual_es_adelanta;
                                mejor_intento_es_elimina = intento_actual_es_elimina;
                                mejor_intento_es_desplaza = intento_actual_es_desplaza;                                
                            end

                            if this.iNivelDebug > 1
                                if intentos_actuales{kk}.AdelantaProyectos
                                    proyectos_adelantar = [intentos_actuales{kk}.proy_seleccionados.proy_conect_adelantar intentos_actuales{kk}.proy_seleccionados.seleccionado];
                                    texto = ['      Intento ' num2str(kk) ' es valido. Sin mejora intermedia: A' ...
                                             '. Totex intento: ' num2str(intentos_actuales{kk}.Totex) '. Proyectos adelantar: '];
                                    for oo = 1:length(proyectos_adelantar)
                                        texto = [texto ' ' num2str(proyectos_adelantar(oo))];
                                    end
                                else
                                    % elimina o desplaza proyectos
                                    if intentos_actuales{kk}.PlanActualHastaEtapa == this.pParOpt.CantidadEtapas
                                        texto_adicional = num2str(intento_actual_sin_mejora_intermedia);
                                        texto_adicional_2 = '. Proyectos eliminar: ';
                                    else
                                        texto_adicional = 'D';
                                        texto_adicional_2 = '. Proyectos desplazar: ';
                                    end
                                    proyectos_eliminar = [intentos_actuales{kk}.proy_seleccionados.conectividad_eliminar intentos_actuales{kk}.proy_seleccionados.seleccionado];
                                    texto = ['      Intento ' num2str(kk) ' es valido. Sin mejora intermedia: ' texto_adicional ...
                                             '. Totex intento: ' num2str(intentos_actuales{kk}.Totex) texto_adicional_2];
                                    for oo = 1:length(proyectos_eliminar)
                                        texto = [texto ' ' num2str(proyectos_eliminar(oo))];
                                    end
                                end
                                prot.imprime_texto(texto);
                            end 
                        else
                            if ~isempty(intentos_actuales{kk}.proy_seleccionados.seleccionado)
                                proy_potenciales_eliminar(proy_potenciales_eliminar == intentos_actuales{kk}.proy_seleccionados.seleccionado) = [];
                                proy_potenciales_adelantar(proy_potenciales_adelantar == intentos_actuales{kk}.proy_seleccionados.seleccionado) = [];
                            end
                        end
                    end

                    if existe_mejora
                        existe_cambio_global = true;
                        if nivel_debug > 1
                            texto = ['      Mejor intento: ' num2str(id_mejor_plan_intento)];
                            prot.imprime_texto(texto);
                        end

                        plan_actual.Proyectos = intentos_actuales{id_mejor_plan_intento}.Proyectos;
                        plan_actual.Etapas = intentos_actuales{id_mejor_plan_intento}.Etapas;
                        evaluacion_actual = intentos_actuales{id_mejor_plan_intento}.evaluacion_actual;
                        estructura_costos_actual = intentos_actuales{id_mejor_plan_intento}.estructura_costos_actual;
                        plan_prueba.Proyectos = plan_actual.Proyectos;
                        plan_prueba.Etapas = plan_actual.Etapas;
                        
                        plan_prueba.inserta_estructura_costos(estructura_costos_actual);
                        plan_prueba.inserta_evaluacion(evaluacion_actual);

                        proy_potenciales_eliminar(proy_potenciales_eliminar == intentos_actuales{id_mejor_plan_intento}.proy_seleccionados.seleccionado) = [];
                        proy_potenciales_adelantar(proy_potenciales_adelantar == intentos_actuales{id_mejor_plan_intento}.proy_seleccionados.seleccionado) = [];

                        % se implementa plan hasta la etapa actual del mejor intento
                        desde_etapa = intentos_actuales{id_mejor_plan_intento}.DesdeEtapaIntento;
                        ultima_etapa_valida_intento = intentos_actuales{id_mejor_plan_intento}.PlanActualHastaEtapa;

                        if intentos_actuales{id_mejor_plan_intento}.AdelantaProyectos
                            proy_adelantar = intentos_actuales{id_mejor_plan_intento}.proy_seleccionados;
                            if ~intentos_actuales{id_mejor_plan_intento}.AdelantaProyectosForzado
                                proyectos_restringidos_para_eliminar = [proyectos_restringidos_para_eliminar proy_adelantar.seleccionado];
                            end
                            for nro_etapa = ultima_etapa_valida_intento:desde_etapa-1
                                % agrega proyectos en sep actual en etapa actual
                                for k = 1:length(proy_adelantar.proy_conect_adelantar)
                                    if nro_etapa < proy_adelantar.etapas_orig_conect(k)
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.proy_conect_adelantar(k));
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    end
                                end
                                proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.seleccionado);
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            end
                            
                            % guarda cambios globales en plan prueba y actualiza capacidades proyectos de conectividad adelantar
                            for k = 1:length(proy_adelantar.proy_conect_adelantar)
                                id_existente = find(proyectos_cambiados_prueba == proy_adelantar.proy_conect_adelantar(k));
                                
                                if ~isempty(id_existente)
                                    etapas_nuevas_plan_prueba(id_existente) = ultima_etapa_valida_intento;
                                else
                                    proyectos_cambiados_prueba = [proyectos_cambiados_prueba proy_adelantar.proy_conect_adelantar(k)];
                                    etapas_originales_plan_actual = [etapas_originales_plan_actual proy_adelantar.etapas_orig_conect(k)];
                                    etapas_nuevas_plan_prueba = [etapas_nuevas_plan_prueba ultima_etapa_valida_intento];
                                end
                            end
                            % proyecto principal adelantar
                            
                            id_existente = find(proyectos_cambiados_prueba == proy_adelantar.seleccionado);
                            if ~isempty(id_existente)
                                etapas_nuevas_plan_prueba(id_existente) = ultima_etapa_valida_intento;
                            else
                                proyectos_cambiados_prueba = [proyectos_cambiados_prueba proy_adelantar.seleccionado];
                                etapas_originales_plan_actual = [etapas_originales_plan_actual desde_etapa];
                                etapas_nuevas_plan_prueba = [etapas_nuevas_plan_prueba ultima_etapa_valida_intento];
                            end
                            
                            % actualiza capacidades plan prueba. Sólo proyectos principales
                            %etapa_orig = desde_etapa;
                            %etapa_nuevas = ultima_etapa_valida_intento;
                            proy_ppal = this.pAdmProy.entrega_proyecto(proy_adelantar.seleccionado);                            
                            delta_capacidad = proy_ppal.entrega_capacidad_adicional();
                            id_decision = proy_ppal.entrega_indice_decision_expansion();
                            
                            capacidades_plan_prueba(id_decision, ultima_etapa_valida_intento:desde_etapa-1) = ...
                                capacidades_plan_prueba(id_decision, ultima_etapa_valida_intento:desde_etapa-1) + delta_capacidad;                                
                        else
                            proy_seleccionados = intentos_actuales{id_mejor_plan_intento}.proy_seleccionados;
                            proyectos_eliminar = [proy_seleccionados.conectividad_eliminar proy_seleccionados.seleccionado];
                            etapas_eliminar = [proy_seleccionados.etapas_conectividad_eliminar proy_seleccionados.etapa_seleccionado];
                            proyectos_desplazar = proy_seleccionados.conectividad_desplazar;
                            etapas_originales_desplazar = proy_seleccionados.etapas_orig_conectividad_desplazar;
                            etapas_desplazar = proy_seleccionados.etapas_fin_conectividad_desplazar;

                            % elimina de lista todos los otros proyectos. Ocurre a veces que trafo paralelo es eliminado como proyecto de conectividad
                            proy_potenciales_eliminar(ismember(proy_potenciales_eliminar, proy_seleccionados.conectividad_eliminar)) = [];
                            proy_potenciales_adelantar(ismember(proy_potenciales_adelantar, proy_seleccionados.conectividad_eliminar)) = [];

                            for nro_etapa = desde_etapa:ultima_etapa_valida_intento
                                % desplaza proyectos a eliminar 
                                for k = length(proyectos_eliminar):-1:1
                                    if etapas_eliminar(k) <= nro_etapa
                                        proyecto = this.pAdmProy.entrega_proyecto(proyectos_eliminar(k));
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    end
                                end
                                %desplaza proyectos
                                for k = length(proyectos_desplazar):-1:1
                                    if nro_etapa >= etapas_originales_desplazar(k) && nro_etapa < etapas_desplazar(k) 
                                        proyecto = this.pAdmProy.entrega_proyecto(proyectos_desplazar(k));
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    end
                                end
                            end

                            if ultima_etapa_valida_intento ~= cantidad_etapas && ~intentos_actuales{id_mejor_plan_intento}.DesplazaProyectosForzado
                                % quiere decir que proyecto no fue eliminado completamente, pero sí desplazado se agrega proyectos_eliminar a proyectos restringidos para eliminar, ya que ya fue
                                % desplazado. A menos que haza sido forzado...
                                proyectos_restringidos_para_eliminar = [proyectos_restringidos_para_eliminar proy_seleccionados.seleccionado];
                            end
                            
                            % guarda cambios globales en plan prueba
                            for k = length(proyectos_eliminar):-1:1
                                id_existente = find(proyectos_cambiados_prueba == proyectos_eliminar(k));
                                if ~isempty(id_existente)
                                    etapas_nuevas_plan_prueba(id_existente) = ultima_etapa_valida_intento+1;
                                else
                                    proyectos_cambiados_prueba = [proyectos_cambiados_prueba proyectos_eliminar(k)];
                                    etapas_originales_plan_actual = [etapas_originales_plan_actual desde_etapa];
                                    etapas_nuevas_plan_prueba = [etapas_nuevas_plan_prueba ultima_etapa_valida_intento+1];
                                end
                            end
                            %desplaza proyectos
                            for k = length(proyectos_desplazar):-1:1
                                id_existente = find(proyectos_cambiados_prueba == proyectos_desplazar(k));
                                if ~isempty(id_existente)
                                    etapas_nuevas_plan_prueba(id_existente) = etapas_desplazar(k)+1;
                                else
                                    proyectos_cambiados_prueba = [proyectos_cambiados_prueba proyectos_desplazar(k)];
                                    etapas_originales_plan_actual = [etapas_originales_plan_actual etapas_originales_desplazar(k)];
                                    etapas_nuevas_plan_prueba = [etapas_nuevas_plan_prueba etapas_desplazar(k)+1];
                                end                                
                            end
                            
                            % Actualiza capacidades plan prueba. Sólo proyecto principal
                            %etapa_orig = proy_seleccionados.etapa_seleccionado;
                            %etapa_nuevas = ultima_etapa_valida_intento;
                            proy_ppal = this.pAdmProy.entrega_proyecto(proy_seleccionados.seleccionado);                            
                            delta_capacidad = proy_ppal.entrega_capacidad_adicional();
                            id_decision = proy_ppal.entrega_indice_decision_expansion();
                            
                            capacidades_plan_prueba(id_decision, proy_seleccionados.etapa_seleccionado:ultima_etapa_valida_intento) = ...
                                capacidades_plan_prueba(id_decision, proy_seleccionados.etapa_seleccionado:ultima_etapa_valida_intento) - delta_capacidad;                                
                        end

                        if nivel_debug > 1
                            texto = '      Lista proy potenciales a eliminar: ';
                            for ii = 1:length(proy_potenciales_eliminar)
                                texto = [texto ' ' num2str(proy_potenciales_eliminar(ii))];
                            end
                            prot.imprime_texto(texto);

                            texto = '      Lista proy potenciales a adelantar: ';
                            for ii = 1:length(proy_potenciales_adelantar)
                                texto = [texto ' ' num2str(proy_potenciales_adelantar(ii))];
                            end
                            prot.imprime_texto(texto);

                            if nivel_debug > 2
                                texto = 'Imprime plan actual despues de los intentos';
                                prot.imprime_texto(texto);
                                plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                                plan_prueba.imprime();
                                
                                for etapa_debug = 1:cantidad_etapas
                                    this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{etapa_debug}, plan_prueba, etapa_debug, 'Punto verificacion 9')
                                end
                                this.debug_verifica_consistencia_plan_valido(plan_prueba, 'Punto verificacion 9');
                                this.debug_verifica_capacidades_corredores(plan_prueba, capacidades_plan_prueba, 'Punto verificacion 10');

                            end
                        end
                    else
                        cant_busqueda_fallida = cant_busqueda_fallida + 1;
                        % no hubo mejora por lo que no es necesario
                        % rehacer ningún plan
                        if nivel_debug > 1
                            texto = '      No hubo mejora en ninguno de los intentos';
                            prot.imprime_texto(texto);

                            texto = '      Lista proy potenciales a eliminar: ';
                            for ii = 1:length(proy_potenciales_eliminar)
                                texto = [texto ' ' num2str(proy_potenciales_eliminar(ii))];
                            end
                            prot.imprime_texto(texto);                                

                            texto = '      Lista proy potenciales a adelantar: ';
                            for ii = 1:length(proy_potenciales_adelantar)
                                texto = [texto ' ' num2str(proy_potenciales_adelantar(ii))];
                            end
                            prot.imprime_texto(texto);                                
                        end
                    end
                end % fin búsqueda local
                                
                if nivel_debug > 1
                    prot.imprime_texto('Fin busqueda local');
                    if ~existe_cambio_global
                        prot.imprime_texto('No hubo cambio en el plan');
                    else
                        prot.imprime_texto(['Totex original: ' num2str(pPlan.entrega_totex_total())]);
                        prot.imprime_texto(['Totex prueba  : ' num2str(plan_prueba.entrega_totex_total())]);
                        texto = sprintf('%-25s %-10s %-15s %-15s', 'Proy. seleccionados', 'Modificar', 'Etapa original', 'Nueva etapa');
                        prot.imprime_texto(texto);
                        for ii = 1:length(proyectos_cambiados_prueba)
                            proy_orig = proyectos_cambiados_prueba(ii);
                            etapa_orig = pPlan.entrega_etapa_proyecto(proy_orig, false);
                            nueva_etapa = plan_prueba.entrega_etapa_proyecto(proy_orig, false);
                            if ii <= length(proyectos_modificar)
                                texto = sprintf('%-25s %-10s %-15s %-15s', num2str(proy_orig), 'si', num2str(etapa_orig), num2str(nueva_etapa));
                            else
                                texto = sprintf('%-25s %-10s %-15s %-15s', num2str(proy_orig), 'no', num2str(etapa_orig), num2str(nueva_etapa));
                            end
                            prot.imprime_texto(texto);
                        end
                    end

                    if nivel_debug > 2
                        prot.imprime_texto('Plan original:');
                        pPlan.agrega_nombre_proyectos(this.pAdmProy);
                        pPlan.imprime_plan_expansion();

                        prot.imprime_texto('Plan prueba:');
                        plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                        plan_prueba.imprime_plan_expansion();
                        
                        for etapa_debug = 1:cantidad_etapas
                            this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{etapa_debug}, plan_prueba, etapa_debug, 'Punto verificacion 10')
                        end
                        this.debug_verifica_capacidades_corredores(plan_prueba, capacidades_plan_prueba, 'Punto verificacion 10');
                        this.debug_verifica_consistencia_plan_valido(plan_prueba, 'Punto verificacion 10');
                    end
                end

                % determina si hay cambio o no
                if existe_cambio_global
                    if plan_prueba.entrega_totex_total() <= pPlan.entrega_totex_total()
                        acepta_cambio = true;
                    else
                        f_obj_prueba = plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                        f_obj_actual = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                        sigma = this.pParOpt.SigmaFuncionLikelihood;
                        prob_cambio = exp((-f_obj_prueba^2+f_obj_actual^2)/(2*sigma^2));

                        if nivel_debug > 1
                            prot.imprime_texto(['Probabilidad de cambio cadena ' num2str(nro_cadena) ': ' num2str(prob_cambio)]);
                        end
                        if rand < prob_cambio
                            acepta_cambio = true;
                        else
                            acepta_cambio = false;
                        end
                    end
                else
                    acepta_cambio = false;
                end

                if acepta_cambio
                    if nivel_debug > 1
                        prot.imprime_texto('Se acepta cambio de plan');
                        prot.imprime_texto(['Totex actual (f objetivo): ' num2str(pPlan.entrega_totex_total()) ' (' num2str(pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')']);
                        prot.imprime_texto(['Totex nuevo (f objetivo): ' num2str(plan_prueba.entrega_totex_total()) ' (' num2str(plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')']);
                    end
                    % se guarda nuevo plan en cadena
                    pPlan = plan_prueba;
                    cadenas{nro_cadena}.plan_actual = plan_prueba;
                    cadenas{nro_cadena}.CambiosEstado(paso_actual) = 1;
                    cadenas{nro_cadena}.Proyectos(paso_actual,:) = cadenas{nro_cadena}.Proyectos(paso_actual-1,:);
                    cadenas{nro_cadena}.CapacidadDecisionesPrimarias = capacidades_plan_prueba;
                    for ii = 1:length(proyectos_cambiados_prueba)
                        if etapas_nuevas_plan_prueba(ii) <= cantidad_etapas
                            cadenas{nro_cadena}.Proyectos(paso_actual,proyectos_cambiados_prueba(ii)) = etapas_nuevas_plan_prueba(ii);
                        else
                            cadenas{nro_cadena}.Proyectos(paso_actual,proyectos_cambiados_prueba(ii)) = 0;
                        end
                    end
                    cadenas{nro_cadena}.Totex(paso_actual) = pPlan.entrega_totex_total();                        
                    cadenas{nro_cadena}.FObj(paso_actual) = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                    % estadística
                    if pPlan.entrega_totex_total() < cadenas{nro_cadena}.MejorTotex
                        cadenas{nro_cadena}.MejorTotex = pPlan.entrega_totex_total();
                        cadenas{nro_cadena}.MejorFObj = pPlan.entrega_totex_total() - this.NPVCostosOperacionSinRestriccion;
                        if cadenas{nro_cadena}.TiempoEnLlegarAlOptimo == 0 && ...
                           round(cadenas{nro_cadena}.MejorTotex,5) == round(this.PlanOptimo.TotexTotal,5)
                            cadenas{nro_cadena}.TiempoEnLlegarAlOptimo = etime(clock,t_inicio_proceso);
                        end
                    end
                else
                    if nivel_debug > 1
                        prot.imprime_texto('No se acepta cambio de plan');
                        prot.imprime_texto(['Totex actual (f objetivo): ' num2str(pPlan.entrega_totex_total()) '(' num2str(pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')']);
                        prot.imprime_texto(['Totex no aceptado (f objetivo): ' num2str(plan_prueba.entrega_totex_total()) '(' num2str(plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')']);
                    end
                    cadenas{nro_cadena}.CambiosEstado(paso_actual) = 0;
                    cadenas{nro_cadena}.Proyectos(paso_actual,:) = cadenas{nro_cadena}.Proyectos(paso_actual-1,:);
                    cadenas{nro_cadena}.Totex(paso_actual) = pPlan.entrega_totex_total();
                    cadenas{nro_cadena}.FObj(paso_actual) = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                    % se deshacen los cambios en el SEP
                    desde_etapa = min(min(etapas_originales_plan_actual), min(etapas_nuevas_plan_prueba));
                    hasta_etapa = min(cantidad_etapas, max(max(etapas_originales_plan_actual), max(etapas_nuevas_plan_prueba)));

                    if nivel_debug > 2
                        prot.imprime_texto('Resumen proyectos modificados prueba');
                        texto = sprintf('%-15s %-15s %-15s', 'Proyecto', 'Etapa orig', 'Nueva etapa');
                        prot.imprime_texto(texto);
                        for jj = 1:length(proyectos_cambiados_prueba)
                            texto = sprintf('%-15s %-15s %-15s', num2str(proyectos_cambiados_prueba(jj)), num2str(etapas_originales_plan_actual(jj)), num2str(etapas_nuevas_plan_prueba(jj)));
                            prot.imprime_texto(texto);
                        end
                    end
                    
                    for nro_etapa = desde_etapa:hasta_etapa
                        for jj = 1:length(proyectos_cambiados_prueba)
                            if etapas_nuevas_plan_prueba(jj) < cantidad_etapas + 1 && ...
                               etapas_nuevas_plan_prueba(jj) < etapas_originales_plan_actual(jj) && ...
                               nro_etapa >= etapas_nuevas_plan_prueba(jj) && ...
                               nro_etapa < etapas_originales_plan_actual(jj) 
                                % proyecto se retrasa, por lo que hay que eliminarlo del SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_cambiados_prueba(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                            elseif etapas_nuevas_plan_prueba(jj) > etapas_originales_plan_actual(jj) && ...
                                   nro_etapa >=  etapas_originales_plan_actual(jj) && ...
                                   nro_etapa < etapas_nuevas_plan_prueba(jj) 
                                % proyecto se adelanta, por lo que hay que
                                % agregarlo al SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_cambiados_prueba(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            end
                        end
                        
                        if nivel_debug > 2
                            this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, pPlan, nro_etapa, 'Punto verificacion 11');
                        end
                    end
                end

                if nivel_debug > 1
                    prot.imprime_matriz([cadenas{nro_cadena}.Proyectos(paso_actual-1,:); cadenas{nro_cadena}.Proyectos(paso_actual,:)], 'Matriz proyectos pasos anterior y actual');
                    prot.imprime_texto([' Totex paso anterior: ' num2str(cadenas{nro_cadena}.Totex(paso_actual-1))]);
                    prot.imprime_texto([' Totex paso actual  : ' num2str(cadenas{nro_cadena}.Totex(paso_actual))]);                        

                    dt_paso = etime(clock,tinicio_paso);

                    totex_anterior = num2str(round(cadenas{nro_cadena}.Totex(paso_actual-1),4));

                    gap = round((cadenas{nro_cadena}.MejorTotex-this.TotexPlanOptimo)/(this.TotexPlanOptimo)*100,3);
                    gap_actual = round((cadenas{nro_cadena}.plan_actual.entrega_totex_total()-this.TotexPlanOptimo)/this.TotexPlanOptimo*100,3);
                    valido = cadenas{nro_cadena}.plan_actual.es_valido();
                    if ~valido
                        texto_valido = 'no';
                    else
                        texto_valido = '';
                    end
                    text = sprintf('%-7s %-5s %-7s %-15s %-15s %-15s %-10s %-10s %-10s %-10s',num2str(nro_cadena), ...
                                                                         num2str(paso_actual),...
                                                                         texto_valido,...
                                                                         num2str(round(cadenas{nro_cadena}.plan_actual.entrega_totex_total(),4)),...
                                                                         totex_anterior,...
                                                                         num2str(cadenas{nro_cadena}.MejorTotex),...
                                                                         num2str(gap_actual), ...
                                                                         num2str(gap), ...
                                                                         num2str(dt_paso));

                    disp(text);
                end

            end % fin todas las cadenas
            
            % actualiza capacidades
            cantidad_decisiones_primarias = this.pAdmProy.entrega_cantidad_decisiones_primarias();
            for corr = 1:cantidad_decisiones_primarias
                for cad = 1:cantidad_cadenas
                    this.CapacidadDecisionesPrimariasPorCadenas{corr}(cad,:) = cadenas{cad}.CapacidadDecisionesPrimarias(corr,:); 
                end
            end
        end
        
        function cadenas = mapea_espacio_paralelo_sin_bl(this, cadenas, paso_actual, t_inicio_proceso, nivel_debug)
            cantidad_cadenas = this.pParOpt.CantidadCadenas;
            cantidad_etapas = this.pParOpt.CantidadEtapas;
            parfor nro_cadena = 1:cantidad_cadenas
                if nivel_debug > 1
                    nombre_archivo = ['./output/debug/mcmc_', num2str(nro_cadena),'.dat'];
                    doc_id = fopen(nombre_archivo, 'a');
                    texto = ['Comienzo proceso cadena ' num2str(nro_cadena) ' en paso actual ' num2str(paso_actual)];
                    fprintf(doc_id, strcat(texto, '\n'));
                end

                pPlan = cadenas{nro_cadena}.plan_actual;
                if nivel_debug > 1
                    texto = ['Imprime plan actual cadena en paso ' num2str(paso_actual)];
                    fprintf(doc_id, strcat(texto, '\n'));
                    pPlan.agrega_nombre_proyectos(this.pAdmProy);
                    texto = pPlan.entrega_texto_plan_expansion();
                    fprintf(doc_id, strcat(texto, '\n'));

                    tinicio_paso = clock;                    
                end

                plan_prueba = cPlanExpansion(pPlan.entrega_no() + 1);
                plan_prueba.Proyectos = pPlan.Proyectos;
                plan_prueba.Etapas = pPlan.Etapas;
                plan_prueba.inserta_evaluacion(pPlan.entrega_evaluacion());
                plan_prueba.inserta_estructura_costos(pPlan.entrega_estructura_costos());

                if nivel_debug > 2
                    this.debug_verifica_capacidades_corredores(plan_prueba, cadenas{nro_cadena}.CapacidadDecisionesPrimarias, 'Punto verificacion 1');
                end
                
                existe_cambio_global = false;

                proyectos_cambiados_prueba = [];
                etapas_originales_plan_actual = [];
                etapas_nuevas_plan_prueba = [];

                % genera nuevo trial
                [proyectos_modificar, etapas_originales, nuevas_etapas, capacidades_plan_prueba]= this.modifica_plan(plan_prueba, nro_cadena, cadenas{nro_cadena}.CapacidadDecisionesPrimarias);

                if nivel_debug > 1
                    texto = ['      Proyectos modificados (' num2str(length(proyectos_modificar)) '):'];
                    fprintf(doc_id, strcat(texto, '\n'));
                    for ii = 1:length(proyectos_modificar)
                        texto = ['       ' num2str(proyectos_modificar(ii)) ' de etapa ' num2str(etapas_originales(ii)) ' a etapa ' num2str(nuevas_etapas(ii))];
                        fprintf(doc_id, strcat(texto, '\n'));
                    end

                    texto = ['Imprime plan modificado en paso ' num2str(paso_actual)];
                    fprintf(doc_id, strcat(texto, '\n'));
                    plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                    texto = plan_prueba.entrega_texto_plan_expansion();
                    fprintf(doc_id, strcat(texto, '\n'));

                    if nivel_debug > 2
                        this.debug_verifica_capacidades_corredores(plan_prueba, capacidades_plan_prueba, 'Punto verificacion 2');
                    end
                    
                end


                if ~isequal(etapas_originales, nuevas_etapas)
                    existe_cambio_global = true;
                    % se actualiza la red y se calcula nuevo totex de
                    % proyectos modificados
                    desde_etapa = min(min(etapas_originales), min(nuevas_etapas));
                    hasta_etapa = min(cantidad_etapas, max(max(etapas_originales), max(nuevas_etapas)));

                    nro_etapa = desde_etapa-1;
                    while nro_etapa < hasta_etapa
                        nro_etapa = nro_etapa + 1;
                        for jj = 1:length(proyectos_modificar)
                            if etapas_originales(jj) < cantidad_etapas + 1 && ...
                                etapas_originales(jj) < nuevas_etapas(jj) && ...
                                nro_etapa >= etapas_originales(jj) && ...
                                nro_etapa < nuevas_etapas(jj) 

                                % proyecto se retrasa, por lo que hay que eliminarlo del SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_modificar(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                            elseif etapas_originales(jj) > nuevas_etapas(jj) && ...
                                    nro_etapa >=  nuevas_etapas(jj) && ...
                                    nro_etapa < etapas_originales(jj) 
                                % proyecto se adelanta, por lo que hay que
                                % agregarlo al SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_modificar(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            end
                        end
                        
                        if nivel_debug >1
                            it_repara_plan = 0;
                            if nivel_debug >2
                                this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 3')
                            end
                        end
                        
                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                        this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());

                        % genera plan válido (sin ENS y sin recorte RES)
                        while ~plan_prueba.es_valido(nro_etapa)
                            if nivel_debug >1
                                it_repara_plan = it_repara_plan + 1;
                                texto = ['Plan prueba no es valido en etapa ' num2str(nro_etapa) '. Se repara (cant. reparaciones: ' num2str(it_repara_plan)];
                                fprintf(doc_id, strcat(texto, '\n'));
                            end
                            cant_proy_comparar = this.pParOpt.CantProyCompararReparaPlan;

                            % ENS
                            [candidatos_ens, etapas_ens] = this.determina_espacio_busqueda_repara_plan(plan_prueba, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa,1);
                            proy_agregado = false;                            
                            if ~isempty(candidatos_ens)
                                proy_candidatos_ens = [];
                                etapas_cand_ens = [];
                                tope = min(length(candidatos_ens),cant_proy_comparar);                                

                                % prioridad a proyectos que están en plan
                                id_existentes = find(etapas_ens ~= cantidad_etapas+1);
                                if ~isempty(id_existentes)
                                    if length(id_existentes) > tope
                                        orden = randperm(length(id_existentes));
                                        proy_candidatos_ens = candidatos_ens(id_existentes(orden));
                                        etapas_cand_ens = etapas_ens(id_existentes(orden));
                                        proy_candidatos_ens = proy_candidatos_ens(1:tope);
                                        etapas_cand_ens = etapas_cand_ens(1:tope);
                                    else
                                        proy_candidatos_ens = candidatos_ens(id_existentes);
                                        etapas_cand_ens = etapas_ens(id_existentes);
                                    end
                                    tope = tope-length(proy_candidatos_ens);
                                end
                                if tope > 0
                                    id_no_existentes = find(etapas_ens == cantidad_etapas+1);
                                    if length(id_no_existentes) > tope
                                        orden = randperm(length(id_no_existentes));
                                        nuevos_cand = candidatos_ens(id_no_existentes(orden));
                                        nuevas_etapas_cand = etapas_ens(id_no_existentes(orden));
                                        
                                        proy_candidatos_ens = [proy_candidatos_ens nuevos_cand(1:tope)];
                                        etapas_cand_ens = [etapas_cand_ens nuevas_etapas_cand(1:tope)];
                                    else
                                        proy_candidatos_ens = [proy_candidatos_ens candidatos_ens(id_no_existentes)];
                                        etapas_cand_ens = [etapas_cand_ens etapas_ens(id_no_existentes)];
                                    end
                                end
                                
                                costo_falla_intento = zeros(tope, 1);
                                mejor_intento = 0;
                                tope = length(proy_candidatos_ens);
                                for i = 1:tope
                                    id_proy_selec = proy_candidatos_ens(i);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_selec);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                    eval = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion();
                                    costo_falla_intento(i) = sum(eval.CostoENS)+sum(eval.CostoRecorteRES);
                                    if costo_falla_intento(i) == 0 || tope == 1
                                        mejor_intento = i;
                                        break
                                    else
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proy_seleccionado);
                                    end
                                end
                                if mejor_intento == 0
                                    mejor_intento = find(costo_falla_intento == min(costo_falla_intento),1);
                                    % implementa mejor intento en SEP
                                    id_proy_seleccionado = proy_candidatos_ens(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                else
                                    % no es necesario agregarlo al SEP porque ya está
                                    id_proy_seleccionado = proy_candidatos_ens(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                end
                                etapa_seleccionado = etapas_cand_ens(mejor_intento);
                                
                                % implementa mejor intento en el plan
                                if etapas_cand_ens(mejor_intento) == cantidad_etapas+1
                                    plan_prueba.agrega_proyecto(nro_etapa, id_proy_seleccionado);
                                    if nivel_debug > 1
                                        texto = ['ENS: Se agrega proyecto ' num2str(id_proy_seleccionado) ' a etapa ' num2str(nro_etapa)];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                else
                                    plan_prueba.adelanta_proyectos(id_proy_seleccionado, etapa_seleccionado, nro_etapa);
                                    if nivel_debug > 1
                                        texto = ['ENS: Se adelanta proyecto ' num2str(id_proy_seleccionado) ' de etapa ' num2str(etapa_seleccionado) ' a etapa ' num2str(nro_etapa)];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                end
                                
                                this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                                
                                % actualiza capacidades
                                id_decision = proy_seleccionado.entrega_indice_decision_expansion();
                                delta_capacidad = proy_seleccionado.entrega_capacidad_adicional();
                                capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) = capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) + delta_capacidad;
                                proy_agregado = true;

                                % agrega proyecto seleccionado a proyectos modificar
                                id_proyectos_modificar = find(proyectos_modificar == id_proy_seleccionado);
                                if ~isempty(id_proyectos_modificar)
                                    % proyecto seleccionado pertenece a proyectos modificar. Se actualiza etapa fin
                                    nuevas_etapas(id_proyectos_modificar) = nro_etapa;
                                else
                                    % nuevo proyecto. Se agrega a proyectos modificar
                                    proyectos_modificar = [proyectos_modificar id_proy_seleccionado];
                                    etapas_originales = [etapas_originales etapa_seleccionado];
                                    nuevas_etapas = [nuevas_etapas nro_etapa];
                                end
                                
                                % modifica etapa fin de evaluación 
                                hasta_etapa = min(cantidad_etapas, max(max(etapas_originales), max(nuevas_etapas)));
                            end

                            % recorte RES
                            [candidatos_recorte, etapas_recorte] = this.determina_espacio_busqueda_repara_plan(plan_prueba, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa,2);
                            if ~isempty(candidatos_recorte)
                                proy_candidatos_recorte = [];
                                etapas_cand_recorte = [];
                                tope = min(length(candidatos_recorte),cant_proy_comparar);                                

                                % prioridad a proyectos que están en plan
                                id_existentes = find(etapas_recorte ~= cantidad_etapas+1);
                                if ~isempty(id_existentes)
                                    if length(id_existentes) > tope
                                        orden = randperm(length(id_existentes));
                                        proy_candidatos_recorte = candidatos_recorte(id_existentes(orden));
                                        etapas_cand_recorte = etapas_recorte(id_existentes(orden));
                                        proy_candidatos_recorte = proy_candidatos_recorte(1:tope);
                                        etapas_cand_recorte = etapas_cand_recorte(1:tope);
                                    else
                                        proy_candidatos_recorte = candidatos_recorte(id_existentes);
                                        etapas_cand_recorte = etapas_recorte(id_existentes);
                                    end
                                    tope = tope-length(proy_candidatos_recorte);
                                end
                                if tope > 0
                                    id_no_existentes = find(etapas_recorte == cantidad_etapas+1);
                                    if length(id_no_existentes) > tope
                                        orden = randperm(length(id_no_existentes));
                                        nuevos_cand = candidatos_recorte(id_no_existentes(orden));
                                        nuevas_etapas_cand = etapas_recorte(id_no_existentes(orden));
                                        
                                        proy_candidatos_recorte = [proy_candidatos_recorte nuevos_cand(1:tope)];
                                        etapas_cand_recorte = [etapas_cand_recorte nuevas_etapas_cand(1:tope)];
                                    else
                                        proy_candidatos_recorte = [proy_candidatos_recorte candidatos_recorte(id_no_existentes)];
                                        etapas_cand_recorte = [etapas_cand_recorte etapas_recorte(id_no_existentes)];
                                    end
                                end
                                
                                costo_falla_intento = zeros(tope, 1);
                                mejor_intento = 0;
                                tope = length(proy_candidatos_recorte);
                                for i = 1:tope
                                    id_proy_selec = proy_candidatos_recorte(i);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_selec);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                    eval = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion();
                                    costo_falla_intento(i) = sum(eval.CostoENS)+sum(eval.CostoRecorteRES);
                                    if costo_falla_intento(i) == 0 || tope == 1
                                        mejor_intento = i;
                                        break
                                    else
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proy_seleccionado);
                                    end
                                end
                                if mejor_intento == 0
                                    mejor_intento = find(costo_falla_intento == min(costo_falla_intento),1);
                                    % implementa mejor intento en SEP
                                    id_proy_seleccionado = proy_candidatos_recorte(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                else
                                    % no es necesario agregarlo al SEP porque ya está
                                    id_proy_seleccionado = proy_candidatos_recorte(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                end
                                etapa_seleccionado = etapas_cand_recorte(mejor_intento);
                                % implementa mejor intento en el plan
                                if etapas_cand_recorte(mejor_intento) == cantidad_etapas+1
                                    plan_prueba.agrega_proyecto(nro_etapa, id_proy_seleccionado);
                                    if nivel_debug > 1
                                        texto = ['Recorte: Se agrega proyecto ' num2str(id_proy_seleccionado) ' a etapa ' num2str(nro_etapa)];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                else
                                    plan_prueba.adelanta_proyectos(id_proy_seleccionado, etapa_seleccionado, nro_etapa);
                                    if nivel_debug > 1
                                        texto = ['Recorte: Se adelanta proyecto ' num2str(id_proy_seleccionado) ' de etapa ' num2str(etapa_seleccionado) ' a etapa ' num2str(nro_etapa)];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                end
                                
                                this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());

                                % actualiza capacidades
                                id_decision = proy_seleccionado.entrega_indice_decision_expansion();
                                delta_capacidad = proy_seleccionado.entrega_capacidad_adicional();
                                capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) = capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) + delta_capacidad;
                                proy_agregado = true;

                                % agrega proyecto seleccionado a proyectos modificar
                                id_proyectos_modificar = find(proyectos_modificar == id_proy_seleccionado);
                                if ~isempty(id_proyectos_modificar)
                                    % proyecto seleccionado pertenece a proyectos modificar. Se actualiza etapa fin
                                    nuevas_etapas(id_proyectos_modificar) = nro_etapa;
                                else
                                    % nuevo proyecto. Se agrega a proyectos modificar
                                    proyectos_modificar = [proyectos_modificar id_proy_seleccionado];
                                    etapas_originales = [etapas_originales etapa_seleccionado];
                                    nuevas_etapas = [nuevas_etapas nro_etapa];
                                end
                                
                                % modifica etapa fin de evaluación 
                                hasta_etapa = min(cantidad_etapas, max(max(etapas_originales), max(nuevas_etapas)));
                            end
                            

                            if ~proy_agregado
                                error = MException('cOptMCMC:mapea_espacio',['plan prueba no es válido en etapa ' num2str(nro_etapa) ' pero no se pudo reparar']);
                                throw(error)
                            end
                            
                            if nivel_debug >2
                                this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 3')
                            end
                            
                            if nivel_debug >2
                                this.debug_verifica_resultados_despacho_economico(cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), plan_prueba, nro_etapa, 'Punto verificacion 3')
                            end
                        end
                    end                    
                    id_sin_cambiar = (etapas_originales_plan_actual - etapas_nuevas_plan_prueba) == 0;
                    proyectos_modificar(id_sin_cambiar) = [];
                    etapas_originales(id_sin_cambiar) = [];
                    nuevas_etapas(id_sin_cambiar) = [];
                    
                    proyectos_cambiados_prueba = proyectos_modificar;
                    etapas_originales_plan_actual = etapas_originales;
                    etapas_nuevas_plan_prueba = nuevas_etapas;
                    
                    this.calcula_costos_totales(plan_prueba);

                    if nivel_debug > 2
                        for etapa_debug = 1:cantidad_etapas
                            this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{etapa_debug}, plan_prueba, etapa_debug, 'Punto verificacion 4')
                        end
                        this.debug_verifica_consistencia_plan_valido(plan_prueba, 'Punto verificacion 4');
                    end
                end

                if nivel_debug > 1
                    texto = 'Fin proyectos modificar';
                    fprintf(doc_id, strcat(texto, '\n'));
                    texto = ['      Totex plan actual: ' num2str(pPlan.entrega_totex_total())];
                    fprintf(doc_id, strcat(texto, '\n'));
                    texto = ['      Totex plan prueba: ' num2str(plan_prueba.entrega_totex_total())];
                    fprintf(doc_id, strcat(texto, '\n'));
                    texto = '      Se imprime plan prueba (modificado)';
                    fprintf(doc_id, strcat(texto, '\n'));
                    plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                    texto = plan_prueba.entrega_texto_plan_expansion();
                    fprintf(doc_id, strcat(texto, '\n'));
                end

                % determina si hay cambio o no
                if existe_cambio_global
                    if plan_prueba.entrega_totex_total() <= pPlan.entrega_totex_total()
                        acepta_cambio = true;
                    else
                        f_obj_prueba = plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                        f_obj_actual = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                        sigma = this.pParOpt.SigmaFuncionLikelihood;
                        prob_cambio = exp((-f_obj_prueba^2+f_obj_actual^2)/(2*sigma^2));

                        if nivel_debug > 1
                            texto = ['Probabilidad de cambio cadena ' num2str(nro_cadena) ': ' num2str(prob_cambio)];
                            fprintf(doc_id, strcat(texto, '\n'));
                        end
                        if rand < prob_cambio
                            acepta_cambio = true;
                        else
                            acepta_cambio = false;
                        end
                    end
                else
                    acepta_cambio = false;
                end

                if acepta_cambio
                    if nivel_debug > 1
                        texto = 'Se acepta cambio de plan';
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = ['Totex actual (f objetivo): ' num2str(pPlan.entrega_totex_total()) ' (' num2str(pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')'];
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = ['Totex nuevo (f objetivo): ' num2str(plan_prueba.entrega_totex_total()) ' (' num2str(plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')'];
                        fprintf(doc_id, strcat(texto, '\n'));                        
                    end
                    % se guarda nuevo plan en cadena
                    pPlan = plan_prueba;
                    cadenas{nro_cadena}.plan_actual = plan_prueba;
                    cadenas{nro_cadena}.CambiosEstado(paso_actual) = 1;
                    cadenas{nro_cadena}.Proyectos(paso_actual,:) = cadenas{nro_cadena}.Proyectos(paso_actual-1,:);
                    cadenas{nro_cadena}.CapacidadDecisionesPrimarias = capacidades_plan_prueba;
                    for ii = 1:length(proyectos_cambiados_prueba)
                        if etapas_nuevas_plan_prueba(ii) <= cantidad_etapas
                            cadenas{nro_cadena}.Proyectos(paso_actual,proyectos_cambiados_prueba(ii)) = etapas_nuevas_plan_prueba(ii);
                        else
                            cadenas{nro_cadena}.Proyectos(paso_actual,proyectos_cambiados_prueba(ii)) = 0;
                        end
                    end
                    cadenas{nro_cadena}.Totex(paso_actual) = pPlan.entrega_totex_total();
                    cadenas{nro_cadena}.FObj(paso_actual) = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                    % estadística
                    if pPlan.entrega_totex_total() < cadenas{nro_cadena}.MejorTotex
                        cadenas{nro_cadena}.MejorTotex = pPlan.entrega_totex_total();
                        cadenas{nro_cadena}.MejorFObj = pPlan.entrega_totex_total() - this.NPVCostosOperacionSinRestriccion;
                        if cadenas{nro_cadena}.TiempoEnLlegarAlOptimo == 0 && ...
                           round(cadenas{nro_cadena}.MejorTotex,5) == round(this.PlanOptimo.TotexTotal,5)
                            cadenas{nro_cadena}.TiempoEnLlegarAlOptimo = etime(clock,t_inicio_proceso);
                        end
                    end
                else
                    if nivel_debug > 1
                        texto = 'No se acepta cambio de plan';
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = ['Totex actual (f objetivo): ' num2str(pPlan.entrega_totex_total()) '(' num2str(pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')'];
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = ['Totex no aceptado (f objetivo): ' num2str(plan_prueba.entrega_totex_total()) '(' num2str(plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')'];
                        fprintf(doc_id, strcat(texto, '\n'));
                    end
                    cadenas{nro_cadena}.CambiosEstado(paso_actual) = 0;
                    cadenas{nro_cadena}.Proyectos(paso_actual,:) = cadenas{nro_cadena}.Proyectos(paso_actual-1,:);
                    cadenas{nro_cadena}.Totex(paso_actual) = pPlan.entrega_totex_total();
                    cadenas{nro_cadena}.FObj(paso_actual) = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                    % se deshacen los cambios en el SEP
                    desde_etapa = min(min(etapas_originales_plan_actual), min(etapas_nuevas_plan_prueba));
                    hasta_etapa = min(cantidad_etapas, max(max(etapas_originales_plan_actual), max(etapas_nuevas_plan_prueba)));

                    for nro_etapa = desde_etapa:hasta_etapa
                        for jj = 1:length(proyectos_cambiados_prueba)
                            if etapas_nuevas_plan_prueba(jj) < cantidad_etapas + 1 && ...
                               etapas_nuevas_plan_prueba(jj) < etapas_originales_plan_actual(jj) && ...
                               nro_etapa >= etapas_nuevas_plan_prueba(jj) && ...
                               nro_etapa < etapas_originales_plan_actual(jj) 
                                % proyecto se retrasa, por lo que hay que eliminarlo del SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_cambiados_prueba(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                            elseif etapas_nuevas_plan_prueba(jj) > etapas_originales_plan_actual(jj) && ...
                                   nro_etapa >=  etapas_originales_plan_actual(jj) && ...
                                   nro_etapa < etapas_nuevas_plan_prueba(jj) 
                                % proyecto se adelanta, por lo que hay que
                                % agregarlo al SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_cambiados_prueba(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            end
                        end
                        
                        if nivel_debug > 2
                            this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, pPlan, nro_etapa, 'Punto verificacion 13');
                        end
                    end
                end

                if nivel_debug > 1
                    texto = [' Totex paso anterior: ' num2str(cadenas{nro_cadena}.Totex(paso_actual-1))];
                    fprintf(doc_id, strcat(texto, '\n'));
                    texto = [' Totex paso actual  : ' num2str(cadenas{nro_cadena}.Totex(paso_actual))];
                    fprintf(doc_id, strcat(texto, '\n'));

                    dt_paso = etime(clock,tinicio_paso);

                    totex_anterior = num2str(round(cadenas{nro_cadena}.Totex(paso_actual-1),4));

                    gap = round((cadenas{nro_cadena}.MejorTotex-this.TotexPlanOptimo)/(this.TotexPlanOptimo)*100,3);
                    gap_actual = round((cadenas{nro_cadena}.plan_actual.entrega_totex_total()-this.TotexPlanOptimo)/this.TotexPlanOptimo*100,3);
                    valido = cadenas{nro_cadena}.plan_actual.es_valido();
                    if ~valido
                        texto_valido = 'no';
                    else
                        texto_valido = '';
                    end
                    text = sprintf('%-7s %-5s %-7s %-15s %-15s %-15s %-10s %-10s %-10s %-10s',num2str(nro_cadena), ...
                                                                         num2str(paso_actual),...
                                                                         texto_valido,...
                                                                         num2str(round(cadenas{nro_cadena}.plan_actual.entrega_totex_total(),4)),...
                                                                         totex_anterior,...
                                                                         num2str(cadenas{nro_cadena}.MejorTotex),...
                                                                         num2str(gap_actual), ...
                                                                         num2str(gap), ...
                                                                         num2str(dt_paso));

                    disp(text);

                    fclose(doc_id);
                end
            end % todas las cadenas
        end
        
        function cadenas = mapea_espacio_paralelo_bl_simple(this, cadenas, paso_actual, t_inicio_proceso, nivel_debug)
            cantidad_cadenas = this.pParOpt.CantidadCadenas;
            cantidad_etapas = this.pParOpt.CantidadEtapas;
            parfor nro_cadena = 1:cantidad_cadenas
%            for nro_cadena = 1:cantidad_cadenas
                if nivel_debug > 1
                    nombre_archivo = ['./output/debug/mcmc_', num2str(nro_cadena),'.dat'];
                    doc_id = fopen(nombre_archivo, 'a');
                    texto = ['Comienzo proceso cadena ' num2str(nro_cadena) ' en paso actual ' num2str(paso_actual)];
                    fprintf(doc_id, strcat(texto, '\n'));
                end

                pPlan = cadenas{nro_cadena}.plan_actual;
                if nivel_debug > 1
                    texto = ['Imprime plan actual cadena en paso ' num2str(paso_actual)];
                    fprintf(doc_id, strcat(texto, '\n'));
                    pPlan.agrega_nombre_proyectos(this.pAdmProy);
                    texto = pPlan.entrega_texto_plan_expansion();
                    fprintf(doc_id, strcat(texto, '\n'));

                    tinicio_paso = clock;                    
                end

                plan_prueba = cPlanExpansion(pPlan.entrega_no() + 1);
                plan_prueba.Proyectos = pPlan.Proyectos;
                plan_prueba.Etapas = pPlan.Etapas;
                
                plan_prueba.inserta_evaluacion(pPlan.entrega_evaluacion());
                plan_prueba.inserta_estructura_costos(pPlan.entrega_estructura_costos());

                if nivel_debug > 2
                    this.debug_verifica_capacidades_corredores(plan_prueba, cadenas{nro_cadena}.CapacidadDecisionesPrimarias, 'Punto verificacion 1');
                end
                
                existe_cambio_global = false;

                proyectos_cambiados_prueba = [];
                etapas_originales_plan_actual = [];
                etapas_nuevas_plan_prueba = [];

                % genera nuevo trial
                [proyectos_modificar, etapas_originales, nuevas_etapas, capacidades_plan_prueba]= this.modifica_plan(plan_prueba, nro_cadena, cadenas{nro_cadena}.CapacidadDecisionesPrimarias);

                if nivel_debug > 1
                    texto = ['      Proyectos modificados (' num2str(length(proyectos_modificar)) '):'];
                    fprintf(doc_id, strcat(texto, '\n'));
                    for ii = 1:length(proyectos_modificar)
                        texto = ['       ' num2str(proyectos_modificar(ii)) ' de etapa ' num2str(etapas_originales(ii)) ' a etapa ' num2str(nuevas_etapas(ii))];
                        fprintf(doc_id, strcat(texto, '\n'));
                    end

                    texto = ['Imprime plan modificado en paso ' num2str(paso_actual)];
                    fprintf(doc_id, strcat(texto, '\n'));
                    plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                    texto = plan_prueba.entrega_texto_plan_expansion();
                    fprintf(doc_id, strcat(texto, '\n'));

                    if nivel_debug > 2
                        this.debug_verifica_capacidades_corredores(plan_prueba, capacidades_plan_prueba, 'Punto verificacion 2');
                    end
                    
                end


                if ~isequal(etapas_originales, nuevas_etapas)
                    existe_cambio_global = true;
                    % se actualiza la red y se calcula nuevo totex de
                    % proyectos modificados
                    desde_etapa = min(min(etapas_originales), min(nuevas_etapas));
                    hasta_etapa = min(cantidad_etapas, max(max(etapas_originales), max(nuevas_etapas)));

                    nro_etapa = desde_etapa-1;
                    while nro_etapa < hasta_etapa
                        nro_etapa = nro_etapa + 1;
                        for jj = 1:length(proyectos_modificar)
                            if etapas_originales(jj) < cantidad_etapas + 1 && ...
                                etapas_originales(jj) < nuevas_etapas(jj) && ...
                                nro_etapa >= etapas_originales(jj) && ...
                                nro_etapa < nuevas_etapas(jj) 

                                % proyecto se retrasa, por lo que hay que eliminarlo del SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_modificar(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                            elseif etapas_originales(jj) > nuevas_etapas(jj) && ...
                                    nro_etapa >=  nuevas_etapas(jj) && ...
                                    nro_etapa < etapas_originales(jj) 
                                % proyecto se adelanta, por lo que hay que
                                % agregarlo al SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_modificar(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            end
                        end
                        
                        if nivel_debug >1
                            it_repara_plan = 0;
                            if nivel_debug >2
                                this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 3')
                            end
                        end
                        
                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                        this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());

                        % genera plan válido (sin ENS y sin recorte RES)
                        while ~plan_prueba.es_valido(nro_etapa)
                            if nivel_debug >1
                                it_repara_plan = it_repara_plan + 1;
                                texto = ['Plan prueba no es valido en etapa ' num2str(nro_etapa) '. Se repara (cant. reparaciones: ' num2str(it_repara_plan)];
                                fprintf(doc_id, strcat(texto, '\n'));
                            end
                            cant_proy_comparar = this.pParOpt.CantProyCompararReparaPlan;

                            % ENS
                            [candidatos_ens, etapas_ens] = this.determina_espacio_busqueda_repara_plan(plan_prueba, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa,1);
                            proy_agregado = false;                            
                            if ~isempty(candidatos_ens)
                                proy_candidatos_ens = [];
                                etapas_cand_ens = [];
                                tope = min(length(candidatos_ens),cant_proy_comparar);                                

                                % prioridad a proyectos que están en plan
                                id_existentes = find(etapas_ens ~= cantidad_etapas+1);
                                if ~isempty(id_existentes)
                                    if length(id_existentes) > tope
                                        orden = randperm(length(id_existentes));
                                        proy_candidatos_ens = candidatos_ens(id_existentes(orden));
                                        etapas_cand_ens = etapas_ens(id_existentes(orden));
                                        proy_candidatos_ens = proy_candidatos_ens(1:tope);
                                        etapas_cand_ens = etapas_cand_ens(1:tope);
                                    else
                                        proy_candidatos_ens = candidatos_ens(id_existentes);
                                        etapas_cand_ens = etapas_ens(id_existentes);
                                    end
                                    tope = tope-length(proy_candidatos_ens);
                                end
                                if tope > 0
                                    id_no_existentes = find(etapas_ens == cantidad_etapas+1);
                                    if length(id_no_existentes) > tope
                                        orden = randperm(length(id_no_existentes));
                                        nuevos_cand = candidatos_ens(id_no_existentes(orden));
                                        nuevas_etapas_cand = etapas_ens(id_no_existentes(orden));
                                        
                                        proy_candidatos_ens = [proy_candidatos_ens nuevos_cand(1:tope)];
                                        etapas_cand_ens = [etapas_cand_ens nuevas_etapas_cand(1:tope)];
                                    else
                                        proy_candidatos_ens = [proy_candidatos_ens candidatos_ens(id_no_existentes)];
                                        etapas_cand_ens = [etapas_cand_ens etapas_ens(id_no_existentes)];
                                    end
                                end
                                
                                costo_falla_intento = zeros(tope, 1);
                                mejor_intento = 0;
                                tope = length(proy_candidatos_ens);
                                for i = 1:tope
                                    id_proy_selec = proy_candidatos_ens(i);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_selec);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                    eval = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion();
                                    costo_falla_intento(i) = sum(eval.CostoENS)+sum(eval.CostoRecorteRES);
                                    if costo_falla_intento(i) == 0 || tope == 1
                                        mejor_intento = i;
                                        break
                                    else
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proy_seleccionado);
                                    end
                                end
                                if mejor_intento == 0
                                    mejor_intento = find(costo_falla_intento == min(costo_falla_intento),1);
                                    % implementa mejor intento en SEP
                                    id_proy_seleccionado = proy_candidatos_ens(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                else
                                    % no es necesario agregarlo al SEP porque ya está
                                    id_proy_seleccionado = proy_candidatos_ens(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                end
                                etapa_seleccionado = etapas_cand_ens(mejor_intento);
                                
                                % implementa mejor intento en el plan
                                if etapas_cand_ens(mejor_intento) == cantidad_etapas+1
                                    plan_prueba.agrega_proyecto(nro_etapa, id_proy_seleccionado);
                                    if nivel_debug > 1
                                        texto = ['ENS: Se agrega proyecto ' num2str(id_proy_seleccionado) ' a etapa ' num2str(nro_etapa)];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                else
                                    plan_prueba.adelanta_proyectos(id_proy_seleccionado, etapa_seleccionado, nro_etapa);
                                    if nivel_debug > 1
                                        texto = ['ENS: Se adelanta proyecto ' num2str(id_proy_seleccionado) ' de etapa ' num2str(etapa_seleccionado) ' a etapa ' num2str(nro_etapa)];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                end
                                
                                this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                                
                                % actualiza capacidades
                                id_decision = proy_seleccionado.entrega_indice_decision_expansion();
                                delta_capacidad = proy_seleccionado.entrega_capacidad_adicional();
                                capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) = capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) + delta_capacidad;
                                proy_agregado = true;

                                % agrega proyecto seleccionado a proyectos modificar
                                id_proyectos_modificar = find(proyectos_modificar == id_proy_seleccionado);
                                if ~isempty(id_proyectos_modificar)
                                    % proyecto seleccionado pertenece a proyectos modificar. Se actualiza etapa fin
                                    nuevas_etapas(id_proyectos_modificar) = nro_etapa;
                                else
                                    % nuevo proyecto. Se agrega a proyectos modificar
                                    proyectos_modificar = [proyectos_modificar id_proy_seleccionado];
                                    etapas_originales = [etapas_originales etapa_seleccionado];
                                    nuevas_etapas = [nuevas_etapas nro_etapa];
                                end
                                
                                % modifica etapa fin de evaluación 
                                hasta_etapa = min(cantidad_etapas, max(max(etapas_originales), max(nuevas_etapas)));
                            end

                            % recorte RES
                            [candidatos_recorte, etapas_recorte] = this.determina_espacio_busqueda_repara_plan(plan_prueba, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa,2);
                            if ~isempty(candidatos_recorte)
                                proy_candidatos_recorte = [];
                                etapas_cand_recorte = [];
                                tope = min(length(candidatos_recorte),cant_proy_comparar);                                

                                % prioridad a proyectos que están en plan
                                id_existentes = find(etapas_recorte ~= cantidad_etapas+1);
                                if ~isempty(id_existentes)
                                    if length(id_existentes) > tope
                                        orden = randperm(length(id_existentes));
                                        proy_candidatos_recorte = candidatos_recorte(id_existentes(orden));
                                        etapas_cand_recorte = etapas_recorte(id_existentes(orden));
                                        proy_candidatos_recorte = proy_candidatos_recorte(1:tope);
                                        etapas_cand_recorte = etapas_cand_recorte(1:tope);
                                    else
                                        proy_candidatos_recorte = candidatos_recorte(id_existentes);
                                        etapas_cand_recorte = etapas_recorte(id_existentes);
                                    end
                                    tope = tope-length(proy_candidatos_recorte);
                                end
                                if tope > 0
                                    id_no_existentes = find(etapas_recorte == cantidad_etapas+1);
                                    if length(id_no_existentes) > tope
                                        orden = randperm(length(id_no_existentes));
                                        nuevos_cand = candidatos_recorte(id_no_existentes(orden));
                                        nuevas_etapas_cand = etapas_recorte(id_no_existentes(orden));
                                        
                                        proy_candidatos_recorte = [proy_candidatos_recorte nuevos_cand(1:tope)];
                                        etapas_cand_recorte = [etapas_cand_recorte nuevas_etapas_cand(1:tope)];
                                    else
                                        proy_candidatos_recorte = [proy_candidatos_recorte candidatos_recorte(id_no_existentes)];
                                        etapas_cand_recorte = [etapas_cand_recorte etapas_recorte(id_no_existentes)];
                                    end
                                end
                                
                                costo_falla_intento = zeros(tope, 1);
                                mejor_intento = 0;
                                tope = length(proy_candidatos_recorte);
                                for i = 1:tope
                                    id_proy_selec = proy_candidatos_recorte(i);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_selec);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                    eval = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion();
                                    costo_falla_intento(i) = sum(eval.CostoENS)+sum(eval.CostoRecorteRES);
                                    if costo_falla_intento(i) == 0 || tope == 1
                                        mejor_intento = i;
                                        break
                                    else
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proy_seleccionado);
                                    end
                                end
                                if mejor_intento == 0
                                    mejor_intento = find(costo_falla_intento == min(costo_falla_intento),1);
                                    % implementa mejor intento en SEP
                                    id_proy_seleccionado = proy_candidatos_recorte(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                else
                                    % no es necesario agregarlo al SEP porque ya está
                                    id_proy_seleccionado = proy_candidatos_recorte(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                end
                                etapa_seleccionado = etapas_cand_recorte(mejor_intento);
                                % implementa mejor intento en el plan
                                if etapas_cand_recorte(mejor_intento) == cantidad_etapas+1
                                    plan_prueba.agrega_proyecto(nro_etapa, id_proy_seleccionado);
                                    if nivel_debug > 1
                                        texto = ['Recorte: Se agrega proyecto ' num2str(id_proy_seleccionado) ' a etapa ' num2str(nro_etapa)];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                else
                                    plan_prueba.adelanta_proyectos(id_proy_seleccionado, etapa_seleccionado, nro_etapa);
                                    if nivel_debug > 1
                                        texto = ['Recorte: Se adelanta proyecto ' num2str(id_proy_seleccionado) ' de etapa ' num2str(etapa_seleccionado) ' a etapa ' num2str(nro_etapa)];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                end
                                
                                this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());

                                % actualiza capacidades
                                id_decision = proy_seleccionado.entrega_indice_decision_expansion();
                                delta_capacidad = proy_seleccionado.entrega_capacidad_adicional();
                                capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) = capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) + delta_capacidad;
                                proy_agregado = true;

                                % agrega proyecto seleccionado a proyectos modificar
                                id_proyectos_modificar = find(proyectos_modificar == id_proy_seleccionado);
                                if ~isempty(id_proyectos_modificar)
                                    % proyecto seleccionado pertenece a proyectos modificar. Se actualiza etapa fin
                                    nuevas_etapas(id_proyectos_modificar) = nro_etapa;
                                else
                                    % nuevo proyecto. Se agrega a proyectos modificar
                                    proyectos_modificar = [proyectos_modificar id_proy_seleccionado];
                                    etapas_originales = [etapas_originales etapa_seleccionado];
                                    nuevas_etapas = [nuevas_etapas nro_etapa];
                                end
                                
                                % modifica etapa fin de evaluación 
                                hasta_etapa = min(cantidad_etapas, max(max(etapas_originales), max(nuevas_etapas)));
                            end
                            

                            if ~proy_agregado
                                error = MException('cOptMCMC:mapea_espacio',['plan prueba no es válido en etapa ' num2str(nro_etapa) ' pero no se pudo reparar']);
                                throw(error)
                            end
                            
                            if nivel_debug >2
                                this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 3')
                            end
                            
                            if nivel_debug >2
                                this.debug_verifica_resultados_despacho_economico(cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), plan_prueba, nro_etapa, 'Punto verificacion 3')
                            end                            
                            
                        end
                    end                    
                    id_sin_cambiar = (etapas_originales_plan_actual - etapas_nuevas_plan_prueba) == 0;
                    proyectos_modificar(id_sin_cambiar) = [];
                    etapas_originales(id_sin_cambiar) = [];
                    nuevas_etapas(id_sin_cambiar) = [];
                    
                    proyectos_cambiados_prueba = proyectos_modificar;
                    etapas_originales_plan_actual = etapas_originales;
                    etapas_nuevas_plan_prueba = nuevas_etapas;
                    
                    this.calcula_costos_totales(plan_prueba);

                    if nivel_debug > 2
                        for etapa_debug = 1:cantidad_etapas
                            this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{etapa_debug}, plan_prueba, etapa_debug, 'Punto verificacion 4')
                        end
                        this.debug_verifica_consistencia_plan_valido(plan_prueba, 'Punto verificacion 4');
                    end
                end

                if nivel_debug > 1
                    texto = 'Fin proyectos modificar';
                    fprintf(doc_id, strcat(texto, '\n'));
                    texto = ['      Totex plan actual: ' num2str(pPlan.entrega_totex_total())];
                    fprintf(doc_id, strcat(texto, '\n'));
                    texto = ['      Totex plan prueba: ' num2str(plan_prueba.entrega_totex_total())];
                    fprintf(doc_id, strcat(texto, '\n'));
                    texto = '      Se imprime plan prueba (modificado)';
                    fprintf(doc_id, strcat(texto, '\n'));
                    plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                    texto = plan_prueba.entrega_texto_plan_expansion();
                    fprintf(doc_id, strcat(texto, '\n'));
                    texto = 'Comienzo proyectos optimizar';
                    fprintf(doc_id, strcat(texto, '\n'));
                end

                % búsqueda local
                % los proyectos a optimizar ya están en orden aleatorio o
                % en base a las prioridades (en caso de haberlas)

                proyectos_optimizar = this.selecciona_proyectos_optimizar_bl_simple(plan_prueba, proyectos_modificar);
                if nivel_debug > 1
                    texto = ['      Proyectos seleccionados a optimizar(' num2str(length(proyectos_optimizar)) '):'];
                    for ii = 1:length(proyectos_optimizar)
                        texto = [texto ' ' num2str(proyectos_optimizar(ii))];
                    end
                    fprintf(doc_id, strcat(texto, '\n'));
                end
                % optimiza proyectos seleccionados
                % TODO: Por ahora no se consideran opciones de uprating, en
                % donde hay proyectos secundarios (nuevas subestaciones)
                indice_optimizar_actual = 0;
                while indice_optimizar_actual < length(proyectos_optimizar)
                    indice_optimizar_actual = indice_optimizar_actual + 1;
                    proy_seleccionado = proyectos_optimizar(indice_optimizar_actual);
                                        
                    if nivel_debug > 1
                        texto = ['      Proyecto seleccionado optimizar ' num2str(indice_optimizar_actual) '/' num2str(length(proyectos_optimizar)) ':' num2str(proy_seleccionado)];																					  
                        fprintf(doc_id, strcat(texto, '\n'));
                    end
                                        
                    evaluacion_actual = plan_prueba.entrega_evaluacion();
                    estructura_costos_actual = plan_prueba.entrega_estructura_costos();
                    
                    expansion_actual = struct;
                    expansion_actual.Proyectos = plan_prueba.Proyectos;
                    expansion_actual.Etapas = plan_prueba.Etapas;
                    totex_mejor_etapa = plan_prueba.entrega_totex_total();
                    mejor_etapa = 0;
                    
                    % modifica sep y evalua plan a partir de primera etapa cambiada
                    desde_etapa = plan_prueba.entrega_etapa_proyecto(proy_seleccionado, true); % true indica que entrega error si proyecto seleccionado no está en plan
                    proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionado);

                    if desde_etapa == 0
                        % por ahora se mantiene esta parte del código por si a futuro se consideran también proyectos que no están en el plan. Sin embargo, no debiera entrar aquí
                        desde_etapa = cantidad_etapas+1;
                        ultima_etapa_posible = cantidad_etapas;
                        hay_desplazamiento = false;
                    else
                        id_decision = proyecto.entrega_indice_decision_expansion();
                        estado_conducente = proyecto.entrega_estado_conducente();
                        proy_aguas_arriba = this.pAdmProy.entrega_id_proyectos_salientes_por_indice_decision_y_estado(id_decision, estado_conducente(1), estado_conducente(2));
                        ultima_etapa_posible = plan_prueba.entrega_ultima_etapa_posible_modificacion_proyecto(proy_aguas_arriba, desde_etapa)-1;
                        if desde_etapa <= ultima_etapa_posible
                            hay_desplazamiento = true;
                        else
                            hay_desplazamiento = false;
                        end
                    end
                    
                    for nro_etapa = desde_etapa:ultima_etapa_posible
                        % desplaza proyecto
                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                        if nro_etapa < cantidad_etapas
                            plan_prueba.desplaza_proyectos(proy_seleccionado, nro_etapa, nro_etapa + 1);
                        else
                            plan_prueba.elimina_proyectos(proy_seleccionado, nro_etapa);
                        end
                        
                        if nivel_debug > 2
                            this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 3');
                        end
                        
                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                        this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                        this.calcula_costos_totales(plan_prueba);
                        ultima_etapa_evaluada = nro_etapa;
                        
                        if plan_prueba.es_valido(nro_etapa) && plan_prueba.entrega_totex_total() < totex_mejor_etapa
                            % cambio intermedio produce mejora. Se
                            % acepta y se guarda
    
                            mejor_etapa = nro_etapa+1;
                            totex_mejor_etapa = plan_prueba.entrega_totex_total();
                            estructura_costos_actual_mejor_etapa = plan_prueba.entrega_estructura_costos();
                            
                            expansion_actual_mejor_etapa = struct;
                            expansion_actual_mejor_etapa.Proyectos = plan_prueba.Proyectos;
                            expansion_actual_mejor_etapa.Etapas = plan_prueba.Etapas;
                            evaluacion_actual_mejor_etapa = plan_prueba.entrega_evaluacion();

                            if nivel_debug > 1
                                if nro_etapa < this.pParOpt.CantidadEtapas
                                    texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' genera mejora. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                else
                                    texto = ['      Desplazamiento en etapa final genera mejora. Proyectos se eliminan definitivamente. Totex final etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                end
                                fprintf(doc_id, strcat(texto, '\n'));
                            end

                            if nivel_debug > 2
                                this.debug_verifica_consistencia_plan_valido(plan_prueba, 'Punto verificacion 5');
                            end
                            
                        elseif ~plan_prueba.es_valido(nro_etapa)
                            if nivel_debug > 1
                                if nro_etapa < this.pParOpt.CantidadEtapas
                                    texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' hace que plan sea invalido. Se queda hasta aqui la evaluacion'];
                                else
                                    texto = '      Desplazamiento en etapa final hace que plan sea invalido. Se deja hasta aqui la evaluacion';
                                end
                                fprintf(doc_id, strcat(texto, '\n'));
                                
                            end
                                % Plan no es válido. No se sigue evaluando
                                % porque no tiene sentido
                                break;
                        else
                            % plan no genera mejora pero es válido
                            % Se determina mejora "potencial" que
                            % se puede obtener al eliminar el
                            % proyecto, con tal de ver si vale la
                            % pena o no seguir intentando                                
                            if nro_etapa < cantidad_etapas
                                delta_cinv_proyectado = this.calcula_delta_cinv_elimina_proyectos(plan_prueba, nro_etapa+1, proy_seleccionado);
                                existe_potencial = (plan_prueba.entrega_totex_total() - delta_cinv_proyectado) < totex_mejor_etapa;

                                if nivel_debug > 1
                                    texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' no genera mejora. ' ...
                                         'Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total()) ...
                                         '. Delta Cinv potencial: ' num2str(delta_cinv_proyectado) ...
                                         '. Totex potencial: ' num2str(plan_prueba.entrega_totex_total() - delta_cinv_proyectado)];
                                    if ~existe_potencial
                                        texto = [texto ' (*)'];
                                    end
                                    fprintf(doc_id, strcat(texto, '\n'));
                                end
                                if ~existe_potencial
                                    % no hay potencial de mejora. No
                                    % intenta más
                                    break;
                                end 
                            else
                                if nivel_debug > 1
                                    texto = ['      Desplazamiento en etapa final no genera mejora. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                    fprintf(doc_id, strcat(texto, '\n'));
                                end
                            end
                        end
                    end

                    % se deshace el cambio en el sep
                    plan_prueba.Proyectos = expansion_actual.Proyectos;
                    plan_prueba.Etapas = expansion_actual.Etapas;
                    
                    plan_prueba.inserta_estructura_costos(estructura_costos_actual);
                    plan_prueba.inserta_evaluacion(evaluacion_actual);

                    if hay_desplazamiento
                        for nro_etapa = desde_etapa:ultima_etapa_evaluada
                            % deshace los cambios hechos en los sep
                            % actuales hasta la etapa correcta
                            proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionado);
                            cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            
                            if nivel_debug > 2
                                this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 6')
                            end
                        end
                    end

                    if desde_etapa > 1
                        % verifica si adelantar el proyecto produce
                        % mejora
                        % determina primera etapa potencial a
                        % adelantar y proyectos de conectividad

                        if nivel_debug > 1                                        
                            texto = '      Se verifica si adelantar proyectos produce mejora';
                            fprintf(doc_id, strcat(texto, '\n'));
                        end

                        nro_etapa = desde_etapa;
                        cantidad_intentos_fallidos_adelanta = 0;
                        cant_intentos_adelanta = 0;
                        cant_intentos_seguidos_sin_mejora_global = 0;
                        max_cant_intentos_fallidos_adelanta = this.pParOpt.CantIntentosFallidosAdelantaOptimiza;
                        ultimo_totex_adelanta = estructura_costos_actual.TotexTotal;
                        flag_salida = false;
                        % si proyecto a optimizar tiene proyecto
                        % dependiente, verifica que proyecto
                        % dependiente esté en el plan
                        proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionado);
                        if proyecto.TieneDependencia
                            [~, primera_etapa_posible]= plan_prueba.entrega_proyecto_dependiente(proyecto.entrega_indices_proyectos_dependientes(), false);
                            if primera_etapa_posible == 0
                                % proyecto dependiente no está en el plan. No se
                                % hace nada
                                flag_salida = true;
                            end
                        else
                            primera_etapa_posible = 1;
                        end
                        hay_adelanto = false;
                        if nro_etapa > primera_etapa_posible && ~flag_salida
                            hay_adelanto = true;
                        end

                        while nro_etapa > primera_etapa_posible && ~flag_salida
                            nro_etapa = nro_etapa - 1;
                            cant_intentos_adelanta = cant_intentos_adelanta + 1;
                            coper_previo_adelanta = plan_prueba.entrega_evaluacion(nro_etapa).CostoOperacion;

                            % agrega proyectos en sep actual en
                            % etapa actual

                            if nivel_debug > 2
                                this.debug_verifica_consistencia_plan_valido(plan_prueba, 'Punto verificacion 7');
                            end                        
                            
                            cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            if nro_etapa == cantidad_etapas
                                plan_prueba.agrega_proyecto(nro_etapa, proy_seleccionado);
                            else
                                plan_prueba.adelanta_proyectos(proy_seleccionado, nro_etapa + 1, nro_etapa);
                            end

                            if nivel_debug > 2
                                this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 8')
                            end
                            
                            %evalua red (proyectos ya se ingresaron
                            %al sep)
                            cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                            this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                            this.calcula_costos_totales(plan_prueba);
                            
                            ultima_etapa_evaluada = nro_etapa;                                
                            totex_actual_adelanta = plan_prueba.entrega_totex_total();
                            delta_totex_actual_adelanta = totex_actual_adelanta-ultimo_totex_adelanta;
                            coper_actual_adelanta = plan_prueba.entrega_evaluacion(nro_etapa).CostoOperacion;
                            delta_coper_actual_adelanta = coper_actual_adelanta - coper_previo_adelanta;
                            if cant_intentos_adelanta == 1
                                delta_totex_anterior_adelanta = delta_totex_actual_adelanta;
                                delta_coper_anterior_adelanta = delta_coper_actual_adelanta;
                            end
                            ultimo_totex_adelanta = totex_actual_adelanta;

                            if plan_prueba.es_valido(nro_etapa) && totex_actual_adelanta < totex_mejor_etapa
                                % adelantar el proyecto produce
                                % mejora. Se guarda resultado
                                cant_intentos_seguidos_sin_mejora_global = 0;
                                mejor_etapa = nro_etapa;
                                totex_mejor_etapa = plan_prueba.entrega_totex_total();
                                estructura_costos_actual_mejor_etapa = plan_prueba.entrega_estructura_costos();
                                expansion_actual_mejor_etapa.Proyectos = plan_prueba.Proyectos;
                                expansion_actual_mejor_etapa.Etapas = plan_prueba.Etapas;
                                
                                evaluacion_actual_mejor_etapa = plan_prueba.entrega_evaluacion();
                                if nivel_debug > 1                                        
                                    texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ' genera mejora parcial. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                    fprintf(doc_id, strcat(texto, '\n'));
                                end
                            elseif plan_prueba.es_valido(nro_etapa)
                                cant_intentos_seguidos_sin_mejora_global = cant_intentos_seguidos_sin_mejora_global + 1;

                                % se analizan las tendencias en delta
                                % totex y delta totex proyectados

                                delta_cinv_proyectado = this.calcula_delta_cinv_adelanta_proyectos(plan_prueba, nro_etapa, proy_seleccionado);
                                delta_coper_proyectado = this.estima_delta_coper_adelanta_proyectos(nro_etapa, delta_coper_actual_adelanta, delta_coper_anterior_adelanta);
                                totex_actual_proyectado = totex_actual_adelanta + delta_cinv_proyectado + delta_coper_proyectado;
                                if cant_intentos_seguidos_sin_mejora_global == 1
                                    totex_anterior_proyectado= totex_actual_proyectado;
                                end

                                if delta_totex_actual_adelanta > 0 && ...
                                        delta_totex_actual_adelanta > delta_totex_anterior_adelanta && ...
                                        totex_actual_proyectado > totex_anterior_proyectado
                                    cantidad_intentos_fallidos_adelanta = cantidad_intentos_fallidos_adelanta + 1;
                                elseif delta_totex_actual_adelanta < 0
                                    cantidad_intentos_fallidos_adelanta = max(0, cantidad_intentos_fallidos_adelanta -1);
                                end

                                totex_anterior_proyectado = totex_actual_proyectado;

                                if nivel_debug > 1
                                    if totex_actual_proyectado > totex_mejor_etapa
                                        texto_adicional = '(+)';
                                    else
                                        texto_adicional = '(-)';
                                    end
                                    if abs(delta_coper_anterior_adelanta) > 0
                                        correccion = (delta_coper_actual_adelanta - delta_coper_anterior_adelanta)/delta_coper_anterior_adelanta;
                                        if correccion > 0.5
                                            correccion = 0.5;
                                        elseif correccion < -0.5
                                            correccion = -0.5;
                                        end
                                    else
                                        correccion = 0;
                                    end

                                    texto_base = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ...
                                        ' no genera mejora. Totex actual etapa: ' num2str(round(totex_actual_adelanta,4))];
                                    texto = sprintf('%-88s %-15s %-10s %-15s %-10s %-17s %-10s %-14s %-6s %-19s %-10s %-17s %-10s %-4s %-16s %-5s ', ...
                                        texto_base, ' DtotexActual: ',num2str(round(delta_totex_actual_adelanta,4)),...
                                        ' DCoperActual: ', num2str(round(delta_coper_actual_adelanta,4)), ...
                                        ' DCoperAnterior: ',num2str(round(delta_coper_anterior_adelanta,4)), ...
                                        ' FCorreccion: ', num2str(correccion,4), ...
                                        ' DCoperProyectado: ', num2str(round(delta_coper_proyectado,4)), ...
                                        ' DTotalEstimado: ', num2str(round(totex_actual_proyectado,4)), ...
                                        texto_adicional, ...
                                        ' Cant. fallida: ', num2str(cantidad_intentos_fallidos_adelanta));

                                    fprintf(doc_id, strcat(texto, '\n'));
                                end                                            
                            else
                                % Plan prueba no es valido
                                flag_salida = true;

                                if nivel_debug > 1
                                    texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ...
                                        ' hace que plan sea inválido. Se deja hasta aquí la evaluación'];
                                    fprintf(doc_id, strcat(texto, '\n'));
                                end
                            end
                            % se verifica si hay que dejar el proceso
                            if cantidad_intentos_fallidos_adelanta >= max_cant_intentos_fallidos_adelanta
                                flag_salida = true;
                            end

                            delta_totex_anterior_adelanta = delta_totex_actual_adelanta;
                            delta_coper_anterior_adelanta = delta_coper_actual_adelanta;
                        end

                        % se deshacen los cambios en el sep
                        plan_prueba.Proyectos = expansion_actual.Proyectos;
                        plan_prueba.Etapas = expansion_actual.Etapas;
                        
                        plan_prueba.inserta_estructura_costos(estructura_costos_actual);
                        plan_prueba.inserta_evaluacion(evaluacion_actual);

                        if hay_adelanto
                            for nro_etapa = ultima_etapa_evaluada:desde_etapa-1
                                % deshace los cambios hechos en los sep
                                % actuales hasta la etapa correcta
                                % Ojo! orden inverso entre desplaza y
                                % elimina proyectos!
                                proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionado);
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);

                                if nivel_debug > 2
                                    this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 9')
                                end                                
                            end
                        end
                    end

                    if mejor_etapa ~=0
                        existe_cambio_global = true;
                        plan_prueba.Proyectos = expansion_actual_mejor_etapa.Proyectos;
                        plan_prueba.Etapas = expansion_actual_mejor_etapa.Etapas;
                        
                        plan_prueba.inserta_estructura_costos(estructura_costos_actual_mejor_etapa);
                        plan_prueba.inserta_evaluacion(evaluacion_actual_mejor_etapa);
                        id_existente = find(proyectos_cambiados_prueba == proy_seleccionado);

                        delta_capacidad = proyecto.entrega_capacidad_adicional();
                        id_decision = proyecto.entrega_indice_decision_expansion();
                        
                        if ~isempty(id_existente)
                            etapa_orig = etapas_nuevas_plan_prueba(id_existente);
                            etapas_nuevas_plan_prueba(id_existente) = mejor_etapa;
                            
                            % actualiza capacidades plan prueba
                            if etapa_orig > mejor_etapa
                                capacidades_plan_prueba(id_decision, mejor_etapa:etapa_orig-1) = ...
                                    capacidades_plan_prueba(id_decision, mejor_etapa:etapa_orig-1) + delta_capacidad;                                
                            else
                                %mejor_etapa > etapa_orig
                                capacidades_plan_prueba(id_decision, etapa_orig:mejor_etapa-1) = ...
                                    capacidades_plan_prueba(id_decision, etapa_orig:mejor_etapa-1) - delta_capacidad;                                
                            end
                        else
                            proyectos_cambiados_prueba = [proyectos_cambiados_prueba proy_seleccionado];
                            etapas_originales_plan_actual = [etapas_originales_plan_actual desde_etapa];
                            etapas_nuevas_plan_prueba = [etapas_nuevas_plan_prueba mejor_etapa];
                            
                            if desde_etapa > mejor_etapa
                                capacidades_plan_prueba(id_decision, mejor_etapa:desde_etapa-1) = ...
                                    capacidades_plan_prueba(id_decision, mejor_etapa:desde_etapa-1) + delta_capacidad;
                            else
                                % mejor_etapa > desde_etapa
                                capacidades_plan_prueba(id_decision, desde_etapa:mejor_etapa-1) = ...
                                    capacidades_plan_prueba(id_decision, desde_etapa:mejor_etapa-1) - delta_capacidad;
                            end
                        end
                        if nivel_debug > 1
                            texto = ['      Mejor etapa: ' num2str(mejor_etapa) '. Totex mejor etapa: ' num2str(plan_prueba.entrega_totex_total())];
                            fprintf(doc_id, strcat(texto, '\n'));
                        end
                        
                        if nivel_debug > 2
                            this.debug_verifica_consistencia_plan_valido(plan_prueba, 'Punto verificacion 10');
                        end                        
                    else
                        plan_prueba.Proyectos = expansion_actual.Proyectos;
                        plan_prueba.Etapas = expansion_actual.Etapas;
                        
                        plan_prueba.inserta_estructura_costos(estructura_costos_actual);
                        plan_prueba.inserta_evaluacion(evaluacion_actual);
                        
                        if nivel_debug > 2
                            this.debug_verifica_consistencia_plan_valido(plan_prueba, 'Punto verificacion 11');
                        end
                        
                        mejor_etapa = desde_etapa;
                        if nivel_debug > 1
                            texto = '      Cambio de etapa no produjo mejora ';
                            fprintf(doc_id, strcat(texto, '\n'));
                        end
                    end
                    %lleva los cambios al sep hasta la mejor etapa
                    if mejor_etapa > desde_etapa 
                        for nro_etapa = desde_etapa:mejor_etapa-1
                            proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionado);
                            cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                        end
                    elseif mejor_etapa ~= 0 && mejor_etapa < desde_etapa
                        for nro_etapa = mejor_etapa:desde_etapa-1
                                proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionado);
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                        end
                    else
                        % nada. nro_etapa se fija en
                        % cantidad_etapas para verificación
                        % siguiente. En teoría no es necesario ya
                        % que no hubieron cambios
                        nro_etapa = cantidad_etapas;
                    end
                    
                    if this.iNivelDebug > 2
                        this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 12');
                        this.debug_verifica_capacidades_corredores(plan_prueba, capacidades_plan_prueba, 'Punto verificacion 12');
                    end

                end % fin busqueda local

                    
                if nivel_debug > 1
                    texto = 'Fin busqueda local';
                    fprintf(doc_id, strcat(texto, '\n'));
                    if ~existe_cambio_global
                        texto = 'No hubo cambio en el plan';
                        fprintf(doc_id, strcat(texto, '\n'));
                    else
                        texto = ['Totex original: ' num2str(pPlan.entrega_totex_total())];
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = ['Totex prueba  : ' num2str(plan_prueba.entrega_totex_total())];
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = sprintf('%-25s %-10s %-15s %-15s', 'Proy. seleccionados', 'Modificar', 'Etapa original', 'Nueva etapa');
                        fprintf(doc_id, strcat(texto, '\n'));
                        for ii = 1:length(proyectos_cambiados_prueba)
                            proy_orig = proyectos_cambiados_prueba(ii);
                            etapa_orig = pPlan.entrega_etapa_proyecto(proy_orig, false);
                            nueva_etapa = plan_prueba.entrega_etapa_proyecto(proy_orig, false);
                            if ii <= length(proyectos_modificar)
                                texto = sprintf('%-25s %-10s %-15s %-15s', num2str(proy_orig), 'si', num2str(etapa_orig), num2str(nueva_etapa));
                            else
                                texto = sprintf('%-25s %-10s %-15s %-15s', num2str(proy_orig), 'no', num2str(etapa_orig), num2str(nueva_etapa));
                            end
                            fprintf(doc_id, strcat(texto, '\n'));
                        end
                    end

                    if nivel_debug > 2
                        texto = 'Plan original:';
                        fprintf(doc_id, strcat(texto, '\n'));

                        pPlan.agrega_nombre_proyectos(this.pAdmProy);
                        texto = pPlan.entrega_texto_plan_expansion();
                        fprintf(doc_id, strcat(texto, '\n'));

                        texto = 'Plan prueba:';
                        fprintf(doc_id, strcat(texto, '\n'));
                        plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                        texto = plan_prueba.entrega_texto_plan_expansion();
                        fprintf(doc_id, strcat(texto, '\n'));
                    end
                end

                % determina si hay cambio o no
                if existe_cambio_global
                    if plan_prueba.entrega_totex_total() <= pPlan.entrega_totex_total()
                        acepta_cambio = true;
                    else
                        f_obj_prueba = plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                        f_obj_actual = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                        sigma = this.pParOpt.SigmaFuncionLikelihood;
                        prob_cambio = exp((-f_obj_prueba^2+f_obj_actual^2)/(2*sigma^2));

                        if nivel_debug > 1
                            texto = ['Probabilidad de cambio cadena ' num2str(nro_cadena) ': ' num2str(prob_cambio)];
                            fprintf(doc_id, strcat(texto, '\n'));
                        end
                        if rand < prob_cambio
                            acepta_cambio = true;
                        else
                            acepta_cambio = false;
                        end
                    end
                else
                    acepta_cambio = false;
                end

                if acepta_cambio
                    if nivel_debug > 1
                        texto = 'Se acepta cambio de plan';
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = ['Totex actual (f objetivo): ' num2str(pPlan.entrega_totex_total()) ' (' num2str(pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')'];
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = ['Totex nuevo (f objetivo): ' num2str(plan_prueba.entrega_totex_total()) ' (' num2str(plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')'];
                        fprintf(doc_id, strcat(texto, '\n'));                        
                    end
                    % se guarda nuevo plan en cadena
                    pPlan = plan_prueba;
                    cadenas{nro_cadena}.plan_actual = plan_prueba;
                    cadenas{nro_cadena}.CambiosEstado(paso_actual) = 1;
                    cadenas{nro_cadena}.Proyectos(paso_actual,:) = cadenas{nro_cadena}.Proyectos(paso_actual-1,:);
                    cadenas{nro_cadena}.CapacidadDecisionesPrimarias = capacidades_plan_prueba;
                    for ii = 1:length(proyectos_cambiados_prueba)
                        if etapas_nuevas_plan_prueba(ii) <= cantidad_etapas
                            cadenas{nro_cadena}.Proyectos(paso_actual,proyectos_cambiados_prueba(ii)) = etapas_nuevas_plan_prueba(ii);
                        else
                            cadenas{nro_cadena}.Proyectos(paso_actual,proyectos_cambiados_prueba(ii)) = 0;
                        end
                    end
                    cadenas{nro_cadena}.Totex(paso_actual) = pPlan.entrega_totex_total();
                    cadenas{nro_cadena}.FObj(paso_actual) = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                    % estadística
                    if pPlan.entrega_totex_total() < cadenas{nro_cadena}.MejorTotex
                        cadenas{nro_cadena}.MejorTotex = pPlan.entrega_totex_total();
                        cadenas{nro_cadena}.MejorFObj = pPlan.entrega_totex_total() - this.NPVCostosOperacionSinRestriccion;
                        if cadenas{nro_cadena}.TiempoEnLlegarAlOptimo == 0 && ...
                           round(cadenas{nro_cadena}.MejorTotex,5) == round(this.PlanOptimo.TotexTotal,5)
                            cadenas{nro_cadena}.TiempoEnLlegarAlOptimo = etime(clock,t_inicio_proceso);
                        end
                    end
                else
                    if nivel_debug > 1
                        texto = 'No se acepta cambio de plan';
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = ['Totex actual (f objetivo): ' num2str(pPlan.entrega_totex_total()) '(' num2str(pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')'];
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = ['Totex no aceptado (f objetivo): ' num2str(plan_prueba.entrega_totex_total()) '(' num2str(plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')'];
                        fprintf(doc_id, strcat(texto, '\n'));
                    end
                    cadenas{nro_cadena}.CambiosEstado(paso_actual) = 0;
                    cadenas{nro_cadena}.Proyectos(paso_actual,:) = cadenas{nro_cadena}.Proyectos(paso_actual-1,:);
                    cadenas{nro_cadena}.Totex(paso_actual) = pPlan.entrega_totex_total();
                    cadenas{nro_cadena}.FObj(paso_actual) = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                    % se deshacen los cambios en el SEP
                    desde_etapa = min(min(etapas_originales_plan_actual), min(etapas_nuevas_plan_prueba));
                    hasta_etapa = min(cantidad_etapas, max(max(etapas_originales_plan_actual), max(etapas_nuevas_plan_prueba)));

                    for nro_etapa = desde_etapa:hasta_etapa
                        for jj = 1:length(proyectos_cambiados_prueba)
                            if etapas_nuevas_plan_prueba(jj) < cantidad_etapas + 1 && ...
                               etapas_nuevas_plan_prueba(jj) < etapas_originales_plan_actual(jj) && ...
                               nro_etapa >= etapas_nuevas_plan_prueba(jj) && ...
                               nro_etapa < etapas_originales_plan_actual(jj) 
                                % proyecto se retrasa, por lo que hay que eliminarlo del SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_cambiados_prueba(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                            elseif etapas_nuevas_plan_prueba(jj) > etapas_originales_plan_actual(jj) && ...
                                   nro_etapa >=  etapas_originales_plan_actual(jj) && ...
                                   nro_etapa < etapas_nuevas_plan_prueba(jj) 
                                % proyecto se adelanta, por lo que hay que
                                % agregarlo al SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_cambiados_prueba(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            end
                        end
                        
                        if nivel_debug > 2
                            this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, pPlan, nro_etapa, 'Punto verificacion 13');
                        end
                    end
                end

                if nivel_debug > 1
                    texto = [' Totex paso anterior: ' num2str(cadenas{nro_cadena}.Totex(paso_actual-1))];
                    fprintf(doc_id, strcat(texto, '\n'));
                    texto = [' Totex paso actual  : ' num2str(cadenas{nro_cadena}.Totex(paso_actual))];
                    fprintf(doc_id, strcat(texto, '\n'));

                    dt_paso = etime(clock,tinicio_paso);

                    totex_anterior = num2str(round(cadenas{nro_cadena}.Totex(paso_actual-1),4));

                    gap = round((cadenas{nro_cadena}.MejorTotex-this.TotexPlanOptimo)/(this.TotexPlanOptimo)*100,3);
                    gap_actual = round((cadenas{nro_cadena}.plan_actual.entrega_totex_total()-this.TotexPlanOptimo)/this.TotexPlanOptimo*100,3);
                    valido = cadenas{nro_cadena}.plan_actual.es_valido();
                    if ~valido
                        texto_valido = 'no';
                    else
                        texto_valido = '';
                    end
                    text = sprintf('%-7s %-5s %-7s %-15s %-15s %-15s %-10s %-10s %-10s %-10s',num2str(nro_cadena), ...
                                                                         num2str(paso_actual),...
                                                                         texto_valido,...
                                                                         num2str(round(cadenas{nro_cadena}.plan_actual.entrega_totex_total(),4)),...
                                                                         totex_anterior,...
                                                                         num2str(cadenas{nro_cadena}.MejorTotex),...
                                                                         num2str(gap_actual), ...
                                                                         num2str(gap), ...
                                                                         num2str(dt_paso));

                    disp(text);

                    fclose(doc_id);
                end
            end % todas las cadenas
        end

        function cadenas = mapea_espacio_paralelo_bl_detallada(this, cadenas, paso_actual, t_inicio_proceso, nivel_debug)
            cantidad_cadenas = this.pParOpt.CantidadCadenas;
            %for nro_cadena = 1:cantidad_cadenas
            parfor nro_cadena = 1:cantidad_cadenas
                cantidad_etapas = this.pParOpt.CantidadEtapas;
                cant_proy_compara_base = this.pParOpt.BLDetalladaCantProyCompararBase;
                cant_proy_compara_sin_mejora = this.pParOpt.BLDetalladaCantProyCompararSinMejora;
                prio_desplaza_sobre_elimina = this.pParOpt.BLDetalladaPrioridadDesplazaSobreElimina;
                cant_fallida = this.pParOpt.BLDetalladaCantFallida;
                intentos_fallidos_adelanta = this.pParOpt.CantIntentosFallidosAdelantaOptimiza;
                prio_adelanta_sobre_desplaza = this.pParOpt.BLDetalladaPrioridadAdelantaSobreDesplaza;
                if nivel_debug > 1
                    nombre_archivo = ['./output/debug/mcmc_', num2str(nro_cadena),'.dat'];
                    doc_id = fopen(nombre_archivo, 'a');
                    texto = ['Comienzo proceso cadena ' num2str(nro_cadena) ' en paso actual ' num2str(paso_actual)];
                    fprintf(doc_id, strcat(texto, '\n'));
                end

                pPlan = cadenas{nro_cadena}.plan_actual;
                if nivel_debug > 1
                    texto = ['Imprime plan actual cadena en paso ' num2str(paso_actual)];
                    fprintf(doc_id, strcat(texto, '\n'));
                    pPlan.agrega_nombre_proyectos(this.pAdmProy);
                    texto = pPlan.entrega_texto_plan_expansion();
                    fprintf(doc_id, strcat(texto, '\n'));

                    tinicio_paso = clock;                    
                end

                plan_prueba = cPlanExpansion(pPlan.entrega_no() + 1);
                plan_prueba.Proyectos = pPlan.Proyectos;
                plan_prueba.Etapas = pPlan.Etapas;
                plan_prueba.inserta_evaluacion(pPlan.entrega_evaluacion());
                plan_prueba.inserta_estructura_costos(pPlan.entrega_estructura_costos());

                if nivel_debug > 2
                    this.debug_verifica_capacidades_corredores(plan_prueba, cadenas{nro_cadena}.CapacidadDecisionesPrimarias, 'Punto verificacion 1');
                end
                
                existe_cambio_global = false;

                proyectos_cambiados_prueba = [];
                etapas_originales_plan_actual = [];
                etapas_nuevas_plan_prueba = [];

                % genera nuevo trial
                [proyectos_modificar, etapas_originales, nuevas_etapas, capacidades_plan_prueba]= this.modifica_plan(plan_prueba, nro_cadena, cadenas{nro_cadena}.CapacidadDecisionesPrimarias);

                if nivel_debug > 1
                    texto = ['      Proyectos modificados (' num2str(length(proyectos_modificar)) '):'];
                    fprintf(doc_id, strcat(texto, '\n'));
                    for ii = 1:length(proyectos_modificar)
                        texto = ['       ' num2str(proyectos_modificar(ii)) ' de etapa ' num2str(etapas_originales(ii)) ' a etapa ' num2str(nuevas_etapas(ii))];
                        fprintf(doc_id, strcat(texto, '\n'));
                    end

                    texto = ['Imprime plan modificado en paso ' num2str(paso_actual)];
                    fprintf(doc_id, strcat(texto, '\n'));
                    plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                    texto = plan_prueba.entrega_texto_plan_expansion();
                    fprintf(doc_id, strcat(texto, '\n'));

                    if nivel_debug > 2
                        this.debug_verifica_capacidades_corredores(plan_prueba, capacidades_plan_prueba, 'Punto verificacion 2');
                    end
                    
                end

                if ~isequal(etapas_originales, nuevas_etapas)
                    existe_cambio_global = true;
                    % se actualiza la red y se calcula nuevo totex de
                    % proyectos modificados
                    desde_etapa = min(min(etapas_originales), min(nuevas_etapas));
                    hasta_etapa = min(cantidad_etapas, max(max(etapas_originales), max(nuevas_etapas)));

                    nro_etapa = desde_etapa-1;
                    while nro_etapa < hasta_etapa
                        nro_etapa = nro_etapa + 1;
                        for jj = 1:length(proyectos_modificar)
                            if etapas_originales(jj) < cantidad_etapas + 1 && ...
                                etapas_originales(jj) < nuevas_etapas(jj) && ...
                                nro_etapa >= etapas_originales(jj) && ...
                                nro_etapa < nuevas_etapas(jj) 

                                % proyecto se retrasa, por lo que hay que eliminarlo del SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_modificar(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                            elseif etapas_originales(jj) > nuevas_etapas(jj) && ...
                                    nro_etapa >=  nuevas_etapas(jj) && ...
                                    nro_etapa < etapas_originales(jj) 
                                % proyecto se adelanta, por lo que hay que
                                % agregarlo al SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_modificar(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            end
                        end
                        
                        if nivel_debug >1
                            it_repara_plan = 0;
                            if nivel_debug >2
                                this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 3')
                            end
                        end
                        
                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                        this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());

                        if nivel_debug >2
                            this.debug_verifica_resultados_despacho_economico(cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), plan_prueba, nro_etapa, 'Punto verificacion 3')
                        end
                        
                        % genera plan válido (sin ENS y sin recorte RES)
                        while ~plan_prueba.es_valido(nro_etapa)
                            if nivel_debug >1
                                it_repara_plan = it_repara_plan + 1;
                                texto = ['Plan prueba no es valido en etapa ' num2str(nro_etapa) '. Se repara (cant. reparaciones: ' num2str(it_repara_plan)];
                                fprintf(doc_id, strcat(texto, '\n'));
                            end
                            
                            cant_proy_comparar = this.pParOpt.CantProyCompararReparaPlan;

                            % ENS
                            [candidatos_ens, etapas_ens] = this.determina_espacio_busqueda_repara_plan(plan_prueba, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa,1);
                            proy_agregado = false;                            
                            if ~isempty(candidatos_ens)
                                proy_candidatos_ens = [];
                                etapas_cand_ens = [];
                                tope = min(length(candidatos_ens),cant_proy_comparar);                                

                                % prioridad a proyectos que están en plan
                                id_existentes = find(etapas_ens ~= cantidad_etapas+1);
                                if ~isempty(id_existentes)
                                    if length(id_existentes) > tope
                                        orden = randperm(length(id_existentes));
                                        proy_candidatos_ens = candidatos_ens(id_existentes(orden));
                                        etapas_cand_ens = etapas_ens(id_existentes(orden));
                                        proy_candidatos_ens = proy_candidatos_ens(1:tope);
                                        etapas_cand_ens = etapas_cand_ens(1:tope);
                                    else
                                        proy_candidatos_ens = candidatos_ens(id_existentes);
                                        etapas_cand_ens = etapas_ens(id_existentes);
                                    end
                                    tope = tope-length(proy_candidatos_ens);
                                end
                                if tope > 0
                                    id_no_existentes = find(etapas_ens == cantidad_etapas+1);
                                    if length(id_no_existentes) > tope
                                        orden = randperm(length(id_no_existentes));
                                        nuevos_cand = candidatos_ens(id_no_existentes(orden));
                                        nuevas_etapas_cand = etapas_ens(id_no_existentes(orden));
                                        
                                        proy_candidatos_ens = [proy_candidatos_ens nuevos_cand(1:tope)];
                                        etapas_cand_ens = [etapas_cand_ens nuevas_etapas_cand(1:tope)];
                                    else
                                        proy_candidatos_ens = [proy_candidatos_ens candidatos_ens(id_no_existentes)];
                                        etapas_cand_ens = [etapas_cand_ens etapas_ens(id_no_existentes)];
                                    end
                                end
                                
                                costo_falla_intento = zeros(tope, 1);
                                mejor_intento = 0;
                                tope = length(proy_candidatos_ens);
                                for i = 1:tope
                                    id_proy_selec = proy_candidatos_ens(i);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_selec);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                    eval = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion();
                                    costo_falla_intento(i) = sum(eval.CostoENS)+sum(eval.CostoRecorteRES);
                                    if costo_falla_intento(i) == 0 || tope == 1
                                        mejor_intento = i;
                                        break
                                    else
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proy_seleccionado);
                                    end
                                end
                                if mejor_intento == 0
                                    mejor_intento = find(costo_falla_intento == min(costo_falla_intento),1);
                                    % implementa mejor intento en SEP
                                    id_proy_seleccionado = proy_candidatos_ens(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                else
                                    % no es necesario agregarlo al SEP porque ya está
                                    id_proy_seleccionado = proy_candidatos_ens(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                end
                                etapa_seleccionado = etapas_cand_ens(mejor_intento);
                                
                                % implementa mejor intento en el plan
                                if etapas_cand_ens(mejor_intento) == cantidad_etapas+1
                                    plan_prueba.agrega_proyecto(nro_etapa, id_proy_seleccionado);
                                    if nivel_debug > 1
                                        texto = ['ENS: Se agrega proyecto ' num2str(id_proy_seleccionado) ' a etapa ' num2str(nro_etapa)];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                else
                                    plan_prueba.adelanta_proyectos(id_proy_seleccionado, etapa_seleccionado, nro_etapa);
                                    if nivel_debug > 1
                                        texto = ['ENS: Se adelanta proyecto ' num2str(id_proy_seleccionado) ' de etapa ' num2str(etapa_seleccionado) ' a etapa ' num2str(nro_etapa)];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                end
                                
                                this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                                
                                % actualiza capacidades
                                id_decision = proy_seleccionado.entrega_indice_decision_expansion();
                                delta_capacidad = proy_seleccionado.entrega_capacidad_adicional();
                                capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) = capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) + delta_capacidad;
                                proy_agregado = true;

                                % agrega proyecto seleccionado a proyectos modificar
                                id_proyectos_modificar = find(proyectos_modificar == id_proy_seleccionado);
                                if ~isempty(id_proyectos_modificar)
                                    % proyecto seleccionado pertenece a proyectos modificar. Se actualiza etapa fin
                                    nuevas_etapas(id_proyectos_modificar) = nro_etapa;
                                else
                                    % nuevo proyecto. Se agrega a proyectos modificar
                                    proyectos_modificar = [proyectos_modificar id_proy_seleccionado];
                                    etapas_originales = [etapas_originales etapa_seleccionado];
                                    nuevas_etapas = [nuevas_etapas nro_etapa];
                                end
                                
                                % modifica etapa fin de evaluación 
                                hasta_etapa = min(cantidad_etapas, max(max(etapas_originales), max(nuevas_etapas)));
                            end

                            % recorte RES
                            [candidatos_recorte, etapas_recorte] = this.determina_espacio_busqueda_repara_plan(plan_prueba, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa,2);
                            if ~isempty(candidatos_recorte)
                                proy_candidatos_recorte = [];
                                etapas_cand_recorte = [];
                                tope = min(length(candidatos_recorte),cant_proy_comparar);                                

                                % prioridad a proyectos que están en plan
                                id_existentes = find(etapas_recorte ~= cantidad_etapas+1);
                                if ~isempty(id_existentes)
                                    if length(id_existentes) > tope
                                        orden = randperm(length(id_existentes));
                                        proy_candidatos_recorte = candidatos_recorte(id_existentes(orden));
                                        etapas_cand_recorte = etapas_recorte(id_existentes(orden));
                                        proy_candidatos_recorte = proy_candidatos_recorte(1:tope);
                                        etapas_cand_recorte = etapas_cand_recorte(1:tope);
                                    else
                                        proy_candidatos_recorte = candidatos_recorte(id_existentes);
                                        etapas_cand_recorte = etapas_recorte(id_existentes);
                                    end
                                    tope = tope-length(proy_candidatos_recorte);
                                end
                                if tope > 0
                                    id_no_existentes = find(etapas_recorte == cantidad_etapas+1);
                                    if length(id_no_existentes) > tope
                                        orden = randperm(length(id_no_existentes));
                                        nuevos_cand = candidatos_recorte(id_no_existentes(orden));
                                        nuevas_etapas_cand = etapas_recorte(id_no_existentes(orden));
                                        
                                        proy_candidatos_recorte = [proy_candidatos_recorte nuevos_cand(1:tope)];
                                        etapas_cand_recorte = [etapas_cand_recorte nuevas_etapas_cand(1:tope)];
                                    else
                                        proy_candidatos_recorte = [proy_candidatos_recorte candidatos_recorte(id_no_existentes)];
                                        etapas_cand_recorte = [etapas_cand_recorte etapas_recorte(id_no_existentes)];
                                    end
                                end
                                
                                costo_falla_intento = zeros(tope, 1);
                                mejor_intento = 0;
                                tope = length(proy_candidatos_recorte);
                                for i = 1:tope
                                    id_proy_selec = proy_candidatos_recorte(i);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_selec);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                    eval = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion();
                                    costo_falla_intento(i) = sum(eval.CostoENS)+sum(eval.CostoRecorteRES);
                                    if costo_falla_intento(i) == 0 || tope == 1
                                        mejor_intento = i;
                                        break
                                    else
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proy_seleccionado);
                                    end
                                end
                                if mejor_intento == 0
                                    mejor_intento = find(costo_falla_intento == min(costo_falla_intento),1);
                                    % implementa mejor intento en SEP
                                    id_proy_seleccionado = proy_candidatos_recorte(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proy_seleccionado);
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                else
                                    % no es necesario agregarlo al SEP porque ya está
                                    id_proy_seleccionado = proy_candidatos_recorte(mejor_intento);
                                    proy_seleccionado = this.pAdmProy.entrega_proyecto(id_proy_seleccionado);
                                end
                                etapa_seleccionado = etapas_cand_recorte(mejor_intento);
                                % implementa mejor intento en el plan
                                if etapas_cand_recorte(mejor_intento) == cantidad_etapas+1
                                    plan_prueba.agrega_proyecto(nro_etapa, id_proy_seleccionado);
                                    if nivel_debug > 1
                                        texto = ['Recorte: Se agrega proyecto ' num2str(id_proy_seleccionado) ' a etapa ' num2str(nro_etapa)];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                else
                                    plan_prueba.adelanta_proyectos(id_proy_seleccionado, etapa_seleccionado, nro_etapa);
                                    if nivel_debug > 1
                                        texto = ['Recorte: Se adelanta proyecto ' num2str(id_proy_seleccionado) ' de etapa ' num2str(etapa_seleccionado) ' a etapa ' num2str(nro_etapa)];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                end
                                
                                this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());

                                % actualiza capacidades
                                id_decision = proy_seleccionado.entrega_indice_decision_expansion();
                                delta_capacidad = proy_seleccionado.entrega_capacidad_adicional();
                                capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) = capacidades_plan_prueba(id_decision, nro_etapa:etapa_seleccionado-1) + delta_capacidad;
                                proy_agregado = true;

                                % agrega proyecto seleccionado a proyectos modificar
                                id_proyectos_modificar = find(proyectos_modificar == id_proy_seleccionado);
                                if ~isempty(id_proyectos_modificar)
                                    % proyecto seleccionado pertenece a proyectos modificar. Se actualiza etapa fin
                                    nuevas_etapas(id_proyectos_modificar) = nro_etapa;
                                else
                                    % nuevo proyecto. Se agrega a proyectos modificar
                                    proyectos_modificar = [proyectos_modificar id_proy_seleccionado];
                                    etapas_originales = [etapas_originales etapa_seleccionado];
                                    nuevas_etapas = [nuevas_etapas nro_etapa];
                                end
                                
                                % modifica etapa fin de evaluación 
                                hasta_etapa = min(cantidad_etapas, max(max(etapas_originales), max(nuevas_etapas)));
                            end
                            

                            if ~proy_agregado
                                error = MException('cOptMCMC:mapea_espacio',['plan prueba no es válido en etapa ' num2str(nro_etapa) ' pero no se pudo reparar']);
                                throw(error)
                            end
                            
                            if nivel_debug >2
                                this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 3')
                            end
                            
                            if nivel_debug >2
                                this.debug_verifica_resultados_despacho_economico(cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), plan_prueba, nro_etapa, 'Punto verificacion 3')
                            end                            
                        end
                    end                    
                    id_sin_cambiar = (etapas_originales_plan_actual - etapas_nuevas_plan_prueba) == 0;
                    proyectos_modificar(id_sin_cambiar) = [];
                    etapas_originales(id_sin_cambiar) = [];
                    nuevas_etapas(id_sin_cambiar) = [];
                    
                    proyectos_cambiados_prueba = proyectos_modificar;
                    etapas_originales_plan_actual = etapas_originales;
                    etapas_nuevas_plan_prueba = nuevas_etapas;
                    
                    this.calcula_costos_totales(plan_prueba);

                    if nivel_debug > 2
                        for etapa_debug = 1:cantidad_etapas
                            this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{etapa_debug}, plan_prueba, etapa_debug, 'Punto verificacion 4')
                        end
                        this.debug_verifica_consistencia_plan_valido(plan_prueba, 'Punto verificacion 4');
                        this.debug_verifica_capacidades_corredores(plan_prueba, capacidades_plan_prueba, 'Punto verificacion 4');
                    end
                end

                if nivel_debug > 1
                    texto = 'Fin proyectos modificar';
                    fprintf(doc_id, strcat(texto, '\n'));
                    texto = ['      Totex plan actual: ' num2str(pPlan.entrega_totex_total())];
                    fprintf(doc_id, strcat(texto, '\n'));
                    texto = ['      Totex plan prueba: ' num2str(plan_prueba.entrega_totex_total())];
                    fprintf(doc_id, strcat(texto, '\n'));
                    texto = '      Se imprime plan prueba (modificado)';
                    fprintf(doc_id, strcat(texto, '\n'));
                    plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                    texto = plan_prueba.entrega_texto_plan_expansion();
                    fprintf(doc_id, strcat(texto, '\n'));
                    texto = 'Comienzo proyectos optimizar';
                    fprintf(doc_id, strcat(texto, '\n'));
                    
                    estructura_costos_plan_base = plan_prueba.entrega_estructura_costos();
                    
                    expansion_plan_base = struct;
                    expansion_plan_base.Proyectos = plan_prueba.Proyectos;
                    expansion_plan_base.Etapas = plan_prueba.Etapas;
                    evaluacion_plan_base = plan_prueba.entrega_evaluacion();
                    
                end

                % búsqueda local detallada
                proyectos_restringidos_para_eliminar = [];
                
                evaluacion_actual = plan_prueba.entrega_evaluacion();
                estructura_costos_actual = plan_prueba.entrega_estructura_costos();
                
                expansion_actual = struct;
                expansion_actual.Proyectos = plan_prueba.Proyectos;
                expansion_actual.Etapas = plan_prueba.Etapas;
                cant_busqueda_fallida = 0;
                proy_potenciales_eliminar = []; % no se verifica adelanta
                proy_potenciales_adelantar = []; %también se analiza elimina

                while cant_busqueda_fallida < cant_fallida
                    intento_paralelo_actual = 0;
                    intentos_actuales = cell(cant_proy_compara_base,0);
                    proyectos_restringidos_para_eliminar_intento = proyectos_restringidos_para_eliminar;
                    fuerza_continuar_comparacion = false;
                    cantidad_mejores_intentos_completo = 0;

                    proy_en_evaluacion = [];
                    while intento_paralelo_actual < cant_proy_compara_base || fuerza_continuar_comparacion
                        intento_paralelo_actual = intento_paralelo_actual +1;
                        plan_actual_intento = expansion_actual;
                        evaluacion_actual_intento = evaluacion_actual;
                        estructura_costos_actual_intento = estructura_costos_actual;

                        proy_potenciales_evaluar = [proy_potenciales_eliminar proy_potenciales_adelantar];
                        proy_actual_es_potencial_elimina = false;
                        
                        if length(proy_potenciales_evaluar) >= intento_paralelo_actual
                            if length(proy_potenciales_eliminar) >= intento_paralelo_actual
                                proy_actual_es_potencial_elimina = true;
                            end
                            proy_seleccionados = this.selecciona_proyectos_eliminar_desplazar_bl_detallada(plan_prueba, proyectos_restringidos_para_eliminar_intento, proy_en_evaluacion, proy_potenciales_evaluar(intento_paralelo_actual));
                        else
                            proy_seleccionados = this.selecciona_proyectos_eliminar_desplazar_bl_detallada(plan_prueba, proyectos_restringidos_para_eliminar_intento, proy_en_evaluacion);
                        end

%                       proy_seleccionados.seleccionado = [];
%                       proy_seleccionados.etapa_seleccionado = [];
%                       proy_seleccionados.conectividad_eliminar = [];
%                       proy_seleccionados.etapas_conectividad_eliminar = [];
%                       proy_seleccionados.conectividad_desplazar = [];
%                       proy_seleccionados.etapas_orig_conectividad_desplazar = [];
%                       proy_seleccionados.etapas_fin_conectividad_desplazar = [];
%                       proy_seleccionados.directo = 0/1

                        if isempty(proy_seleccionados.seleccionado)
                            intentos_actuales{intento_paralelo_actual}.Valido = false;
                            intentos_actuales{intento_paralelo_actual}.proy_seleccionados.seleccionado = [];

                            if intento_paralelo_actual >= cant_proy_compara_sin_mejora
                                fuerza_continuar_comparacion = false;
                            end

                            continue;
                        end

                        proy_en_evaluacion = [proy_en_evaluacion proy_seleccionados.seleccionado];
                        
                        intentos_actuales{intento_paralelo_actual}.proy_seleccionados = proy_seleccionados;
                        intentos_actuales{intento_paralelo_actual}.Totex = 999999999999999999999;
                        intentos_actuales{intento_paralelo_actual}.Valido = false;
                        intentos_actuales{intento_paralelo_actual}.Proyectos = [];
                        intentos_actuales{intento_paralelo_actual}.Etapas = [];
                        intentos_actuales{intento_paralelo_actual}.SinMejoraIntermedia = false;
                        intentos_actuales{intento_paralelo_actual}.ExisteMejoraParcialAdelanta = false;
                        intentos_actuales{intento_paralelo_actual}.AdelantaProyectos = false;
                        intentos_actuales{intento_paralelo_actual}.AdelantaProyectosForzado = false;
                        intentos_actuales{intento_paralelo_actual}.DesplazaProyectosForzado = false;

                        %intentos_actuales{intento_paralelo_actual}.estructura_costos_actual = [];
                        %intentos_actuales{intento_paralelo_actual}.evaluacion_actual = [];
                        
                        if nivel_debug > 1
                            texto = sprintf('%-25s %-10s %-20s %-10s',...
                                            '      Totex Plan Base ', num2str(estructura_costos_plan_base.TotexTotal), ...
                                            'Totex plan actual', num2str(estructura_costos_actual.TotexTotal));
                            fprintf(doc_id, strcat(texto, '\n'));

                        end
                    
                        % modifica sep y evalua plan a partir de primera etapa cambiada
                        desde_etapa = proy_seleccionados.etapa_seleccionado;  % etapas desplazar siempre es mayor que etapas eliminar
                        hasta_etapa = proy_seleccionados.ultima_etapa_posible - 1;
                        
                        intentos_actuales{intento_paralelo_actual}.DesdeEtapaIntento = desde_etapa;
                        existe_mejora = false;
                        plan_actual_hasta_etapa = desde_etapa - 1;
                        plan_actual_intento_hasta_etapa = desde_etapa - 1;
                        proyectos_eliminar = [proy_seleccionados.conectividad_eliminar proy_seleccionados.seleccionado];
                        etapas_eliminar = [proy_seleccionados.etapas_conectividad_eliminar proy_seleccionados.etapa_seleccionado];
                        proyectos_desplazar = proy_seleccionados.conectividad_desplazar;
                        etapas_originales_desplazar = proy_seleccionados.etapas_orig_conectividad_desplazar;
                        etapas_desplazar = proy_seleccionados.etapas_fin_conectividad_desplazar;

                        for nro_etapa = desde_etapa:hasta_etapa
                            % desplaza proyectos a eliminar 
                            for k = length(proyectos_eliminar):-1:1
                                if etapas_eliminar(k) <= nro_etapa
                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_eliminar(k));

                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    if nro_etapa < cantidad_etapas
                                        plan_prueba.desplaza_proyectos(proyectos_eliminar(k), nro_etapa, nro_etapa + 1);
                                    else
                                        plan_prueba.elimina_proyectos(proyectos_eliminar(k), nro_etapa);
                                    end
                                end
                            end
                            %desplaza proyectos
                            for k = length(proyectos_desplazar):-1:1
                                if nro_etapa >= etapas_originales_desplazar(k) && nro_etapa < etapas_desplazar(k) 
                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_desplazar(k));
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    plan_prueba.desplaza_proyectos(proyectos_desplazar(k), nro_etapa, nro_etapa + 1);
                                end
                            end

                            %evalua red 
                            cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                            this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());                            
                            this.calcula_costos_totales(plan_prueba);
                            ultima_etapa_evaluada = nro_etapa;

                            if nivel_debug > 2
                                this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 5');
                                this.debug_verifica_consistencia_costos_totales_plan(plan_prueba, 'Punto verificacion 5');
                            end

                            if plan_prueba.es_valido(nro_etapa) && plan_prueba.entrega_totex_total() < estructura_costos_actual_intento.TotexTotal
                                % cambio intermedio produce mejora. Se
                                % sigue evaluando
                                % acepta y se guarda
                                plan_actual_intento.Proyectos = plan_prueba.Proyectos;
                                plan_actual_intento.Etapas = plan_prueba.Etapas;
                                estructura_costos_actual_intento = plan_prueba.entrega_estructura_costos();
                                evaluacion_actual_intento = plan_prueba.entrega_evaluacion();
                                existe_mejora = true;
                                plan_actual_intento_hasta_etapa = nro_etapa;
                                if nivel_debug > 1                                        
                                    if nro_etapa < cantidad_etapas
                                        texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' genera mejora. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                    else
                                        texto = ['      Desplazamiento en etapa final genera mejora. Proyectos se eliminan definitivamente. Totex final etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                    end
                                    fprintf(doc_id, strcat(texto, '\n'));
                                end
                            elseif ~plan_prueba.es_valido(nro_etapa)
                                intentos_actuales{intento_paralelo_actual}.SinMejoraIntermedia = true;

                                if nivel_debug > 1
                                    if nro_etapa < cantidad_etapas
                                        texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' hace que plan sea invalido. Se queda hasta aqui la evaluacion'];
                                    else
                                        texto = '      Desplazamiento en etapa final hace que plan sea invalido. Se deja hasta aqui la evaluacion';
                                    end
                                    fprintf(doc_id, strcat(texto, '\n'));
                                end
                                % Plan no es válido. No se sigue evaluando
                                % porque no tiene sentido
                                break;
                            else
                                % plan es válido pero no genera mejora.
                                % Se determina mejora "potencial" que
                                % se puede obtener al eliminar el
                                % proyecto, con tal de ver si vale la
                                % pena o no seguir intentando. 
                                if prio_desplaza_sobre_elimina && existe_mejora
                                    if nivel_debug > 1
                                        texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' no genera mejora. ' ...
                                                 'Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total()) ...
                                                 '. No se sigue evaluando ya que ya hay resultado valido y flag prioridad desplaza sobre elimina esta activo'];
                                        fprintf(doc_id, strcat(texto, '\n'));                             
                                    end

                                    break;
                                end
                                intentos_actuales{intento_paralelo_actual}.SinMejoraIntermedia = true;
                                if nro_etapa < cantidad_etapas
                                    delta_cinv = this.calcula_delta_cinv_elimina_desplaza_proyectos(plan_prueba, nro_etapa+1, proyectos_eliminar, proyectos_desplazar, etapas_originales_desplazar, etapas_desplazar);
                                    existe_potencial = (plan_prueba.entrega_totex_total() - delta_cinv) < estructura_costos_actual_intento.TotexTotal;
                                    if nivel_debug > 1
                                        texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' no genera mejora. ' ...
                                                 'Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total()) ...
                                                 '. Delta Cinv potencial: ' num2str(delta_cinv) ...
                                                 '. Totex potencial: ' num2str(plan_prueba.entrega_totex_total() - delta_cinv)];
                                        if ~existe_potencial
                                            texto = [texto ' (*)'];
                                        end
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                    if ~existe_potencial
                                        break;
                                    end
                                else
                                    if nivel_debug > 1
                                        texto = ['      Desplazamiento en etapa final no genera mejora. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                end
                            end
                        end

                        if nivel_debug > 2
                            this.debug_verifica_consistencia_costos_totales_plan(plan_prueba, 'Punto verificacion 6');
                        end


                        % se evaluaron todas las etapas. Determina el estado final del plan y agrega proyectos ya evaluados para futuros intentos
                        proyectos_restringidos_para_eliminar_intento = [proyectos_restringidos_para_eliminar_intento proy_seleccionados.seleccionado];

                        mejor_totex_elimina_desplaza = inf;
                        if existe_mejora
                            intentos_actuales{intento_paralelo_actual}.Proyectos = plan_actual_intento.Proyectos;
                            intentos_actuales{intento_paralelo_actual}.Etapas = plan_actual_intento.Etapas;
                            intentos_actuales{intento_paralelo_actual}.estructura_costos_actual = estructura_costos_actual_intento;
                            intentos_actuales{intento_paralelo_actual}.evaluacion_actual = evaluacion_actual_intento;
                            intentos_actuales{intento_paralelo_actual}.Valido = true;
                            intentos_actuales{intento_paralelo_actual}.Totex = estructura_costos_actual_intento.TotexTotal;
                            intentos_actuales{intento_paralelo_actual}.PlanActualHastaEtapa = plan_actual_intento_hasta_etapa;
                            if intentos_actuales{intento_paralelo_actual}.SinMejoraIntermedia == false
                                cantidad_mejores_intentos_completo = cantidad_mejores_intentos_completo + 1;
                            end
                            mejor_totex_elimina_desplaza = estructura_costos_actual_intento.TotexTotal;
                        else
                            % quiere decir que no existe mejora en
                            % ningún desplazamiento
                            % proyectos_eliminar se agrega a grupo de
                            % proyectos restringidos a eliminar
                            intentos_actuales{intento_paralelo_actual}.Valido = false;
                            proyectos_restringidos_para_eliminar = [proyectos_restringidos_para_eliminar proy_seleccionados.seleccionado];
                        end

                        % se deshace el cambio en el sep
                        plan_prueba.Proyectos = expansion_actual.Proyectos;
                        plan_prueba.Etapas = expansion_actual.Etapas;
                        plan_prueba.inserta_estructura_costos(estructura_costos_actual);
                        plan_prueba.inserta_evaluacion(evaluacion_actual);

                        for nro_etapa = plan_actual_hasta_etapa + 1:ultima_etapa_evaluada
                            % deshace los cambios hechos en los sep
                            % actuales hasta la etapa correcta
                            % Ojo! orden inverso entre desplaza y
                            % elimina proyectos!
                            for k = 1:length(proyectos_desplazar)
                                if nro_etapa >= etapas_originales_desplazar(k) && nro_etapa < etapas_desplazar(k) 
                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_desplazar(k));
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                end
                            end

                            for k = 1:length(proyectos_eliminar)
                                if etapas_eliminar(k) <= nro_etapa
                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_eliminar(k));
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                end
                            end
                        end

                        if nivel_debug > 2
                            this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{etapa_debug}, plan_prueba, etapa_debug, 'Punto verificacion 7')
                            this.debug_verifica_consistencia_costos_totales_plan(plan_prueba, 'Punto verificacion 7')
                        end
                        
                        if desde_etapa > 1 && ~proy_actual_es_potencial_elimina
                            % verifica si adelantar el proyecto produce mejora. Determina primera etapa potencial a adelantar y proyectos de conectividad

                            if nivel_debug > 1                                        
                                texto = '      Se verifica si adelantar proyectos produce mejora';
                                fprintf(doc_id, strcat(texto, '\n'));
                            end

                            proy_adelantar = this.selecciona_proyectos_a_adelantar(plan_prueba, desde_etapa, proy_seleccionados.seleccionado);
                            % proy_adelantar.seleccionado
                            % proy_adelantar.etapa_seleccionado
                            % proy_adelantar.seleccion_directa
                            % proy_adelantar.primera_etapa_posible = [];
                            % proy_adelantar.proy_conect_adelantar = [];
                            % proy_adelantar.etapas_orig_conect = [];

                            nro_etapa = desde_etapa;
                            flag_salida = false;
                            existe_resultado_adelanta = false;
                            max_cant_intentos_fallidos_adelanta = intentos_fallidos_adelanta;
                            cant_intentos_fallidos_adelanta = 0;
                            cant_intentos_adelanta = 0;
                            ultimo_totex_adelanta = estructura_costos_actual.TotexTotal;

                            while nro_etapa > proy_adelantar.primera_etapa_posible && ~flag_salida
                                nro_etapa = nro_etapa - 1;
                                existe_mejora_parcial = false;
                                cant_intentos_adelanta = cant_intentos_adelanta + 1;
                                % agrega proyectos en sep actual en
                                % etapa actual
                                for k = 1:length(proy_adelantar.proy_conect_adelantar)
                                    if nro_etapa < proy_adelantar.etapas_orig_conect(k) 
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.proy_conect_adelantar(k));
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                        plan_prueba.adelanta_proyectos(proy_adelantar.proy_conect_adelantar(k), nro_etapa + 1, nro_etapa);
                                    end
                                end
                                proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.seleccionado);
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                plan_prueba.adelanta_proyectos(proy_adelantar.seleccionado, nro_etapa + 1, nro_etapa);

                                %evalua red
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());                            
                                this.calcula_costos_totales(plan_prueba);
                                ultima_etapa_evaluada = nro_etapa;

                                if nivel_debug > 2
                                    this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{etapa_debug}, plan_prueba, etapa_debug, 'Punto verificacion 8')
                                    this.debug_verifica_consistencia_costos_totales_plan(plan_prueba, 'Punto verificacion 8')
                                end
                                
                                if cant_intentos_adelanta == 1
                                    delta_actual_adelanta = plan_prueba.entrega_totex_total()-ultimo_totex_adelanta;
                                else
                                    delta_nuevo_adelanta = plan_prueba.entrega_totex_total()-ultimo_totex_adelanta;
                                    if delta_nuevo_adelanta > 0 && delta_nuevo_adelanta > delta_actual_adelanta
                                        cant_intentos_fallidos_adelanta = cant_intentos_fallidos_adelanta + 1;
                                    elseif delta_nuevo_adelanta < 0
                                        cant_intentos_fallidos_adelanta = 0;
                                    end
                                    delta_actual_adelanta = delta_nuevo_adelanta;
                                end
                                ultimo_totex_adelanta = plan_prueba.entrega_totex_total();

                                if ~existe_resultado_adelanta
                                    % resultado se compara con
                                    % estructura de costos actuales
                                    if plan_prueba.entrega_totex_total() < estructura_costos_actual.TotexTotal
                                        % adelantar el proyecto produce
                                        % mejora. Se guarda resultado
                                        existe_resultado_adelanta = true;
                                        existe_mejora_parcial = true;
                                        
                                        expansion_actual_intento_adelanta = struct;
                                        expansion_actual_intento_adelanta.Proyectos = plan_prueba.Proyectos;
                                        expansion_actual_intento_adelanta.Etapas = plan_prueba.Etapas;
                                        estructura_costos_actual_intento_adelanta = plan_prueba.entrega_estructura_costos();
                                        evaluacion_actual_intento_adelanta = plan_prueba.entrega_evaluacion();
                                        plan_actual_intento_adelanta_hasta_etapa = nro_etapa;
                                        if nivel_debug > 1                                        
                                            texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ' genera mejora parcial. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                            fprintf(doc_id, strcat(texto, '\n'));
                                        end
                                    else
                                        if nivel_debug > 1
                                            texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ...
                                                ' no genera mejora. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())...
                                                ' Delta actual adelanta: ' num2str(delta_actual_adelanta) ...
                                                ' Cant. intentos fallidos adelanta: ' num2str(cant_intentos_fallidos_adelanta)];                                                    
                                            fprintf(doc_id, strcat(texto, '\n'));
                                        end
                                    end
                                else
                                    % resultado se compara con último
                                    % resultado
                                    if plan_prueba.entrega_totex_total() < estructura_costos_actual_intento_adelanta.TotexTotal
                                        % adelantar el proyecto produce
                                        % mejora. Se guarda resultado
                                        existe_mejora_parcial = true;
                                        expansion_actual_intento_adelanta.Proyectos = plan_prueba.Proyectos;
                                        expansion_actual_intento_adelanta.Etapas = plan_prueba.Etapas;
                                        estructura_costos_actual_intento_adelanta = plan_prueba.entrega_estructura_costos();
                                        evaluacion_actual_intento_adelanta = plan_prueba.entrega_evaluacion();
                                        plan_actual_intento_adelanta_hasta_etapa = nro_etapa;
                                        if nivel_debug > 1                                        
                                            texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ' genera mejora parcial. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                            fprintf(doc_id, strcat(texto, '\n'));
                                        end
                                    else
                                        if nivel_debug > 1                                        
                                            texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ...
                                                ' no genera mejora. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total()) ...
                                                ' Delta actual adelanta: ' num2str(delta_actual_adelanta) ...
                                                ' Cant. intentos fallidos adelanta: ' num2str(cant_intentos_fallidos_adelanta)];
                                                fprintf(doc_id, strcat(texto, '\n'));
                                        end  
                                    end
                                end

                                if existe_mejora_parcial
                                    % verifica si mejora parcial es
                                    % mejor que resultado de
                                    % elimina/desplaza
                                    intentos_actuales{intento_paralelo_actual}.ExisteMejoraParcialAdelanta = true;
                                    if ~intentos_actuales{intento_paralelo_actual}.Valido || ...
                                        estructura_costos_actual_intento_adelanta.TotexTotal < intentos_actuales{intento_paralelo_actual}.Totex || ...
                                        prio_adelanta_sobre_desplaza

                                        if estructura_costos_actual_intento_adelanta.TotexTotal > mejor_totex_elimina_desplaza
                                            intentos_actuales{intento_paralelo_actual}.AdelantaProyectosForzado = true;
                                        else
                                            intentos_actuales{intento_paralelo_actual}.AdelantaProyectosForzado = false;                                                
                                        end
                                        % se acepta el cambio
                                        intentos_actuales{intento_paralelo_actual}.Proyectos = expansion_actual_intento_adelanta.Proyectos;
                                        intentos_actuales{intento_paralelo_actual}.Etapas = expansion_actual_intento_adelanta.Etapas;
                                        intentos_actuales{intento_paralelo_actual}.estructura_costos_actual = estructura_costos_actual_intento_adelanta;
                                        intentos_actuales{intento_paralelo_actual}.evaluacion_actual = evaluacion_actual_intento_adelanta;
                                        intentos_actuales{intento_paralelo_actual}.Valido = true;
                                        intentos_actuales{intento_paralelo_actual}.Totex = estructura_costos_actual_intento_adelanta.TotexTotal;
                                        intentos_actuales{intento_paralelo_actual}.PlanActualHastaEtapa = plan_actual_intento_adelanta_hasta_etapa;
                                        intentos_actuales{intento_paralelo_actual}.AdelantaProyectos = true;
                                        intentos_actuales{intento_paralelo_actual}.proy_seleccionados = proy_adelantar;
                                        intentos_actuales{intento_paralelo_actual}.SinMejoraIntermedia = false;
                                        cantidad_mejores_intentos_completo = cantidad_mejores_intentos_completo + 1;
                                    end
                                else
                                    % se verifica si se alcanzó el máximo número de intentos fallidos adelanta
                                    if cant_intentos_fallidos_adelanta >= max_cant_intentos_fallidos_adelanta
                                        flag_salida = true;
                                    end
                                end
                            end
                            % se deshacen los cambios en el sep
                            plan_prueba.Proyectos = expansion_actual.Proyectos;
                            plan_prueba.Etapas = expansion_actual.Etapas;
                            plan_prueba.inserta_estructura_costos(estructura_costos_actual);
                            plan_prueba.inserta_evaluacion(evaluacion_actual);

                            for nro_etapa = ultima_etapa_evaluada:desde_etapa-1
                                % deshace los cambios hechos en los sep
                                % actuales hasta la etapa correcta
                                % Ojo! orden inverso entre desplaza y
                                % elimina proyectos!
                                proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.seleccionado);
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                for k = length(proy_adelantar.proy_conect_adelantar):-1:1
                                    if nro_etapa < proy_adelantar.etapas_orig_conect(k) 
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.proy_conect_adelantar(k));
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    end
                                end

                                if nivel_debug > 2
                                    this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, plan_prueba, nro_etapa, 'Punto verificacion 8')
                                end                                
                            end
                            
                            if nivel_debug > 2
                                this.debug_verifica_consistencia_costos_totales_plan(plan_prueba, 'Punto verificacion 9')
                            end
                        end
                        
                        % se verifica si hay que seguir comparando
                        if fuerza_continuar_comparacion == false && ...
                           intento_paralelo_actual == cant_proy_compara_base && ...
                           cantidad_mejores_intentos_completo < cant_proy_compara_base && ...
                           cant_proy_compara_sin_mejora > cant_proy_compara_base

                            fuerza_continuar_comparacion = true;
                        elseif fuerza_continuar_comparacion == true && intento_paralelo_actual == cant_proy_compara_sin_mejora
                            fuerza_continuar_comparacion = false;
                        end
                    end
                    
                    % determina mejor intento
                    existe_mejora = false;
                    mejor_intento_sin_mejora_intermedia = false;
                    mejor_totex = 0;
                    mejor_intento_es_adelanta = false;
                    mejor_intento_es_elimina = false;
                    mejor_intento_es_desplaza = false;
                    id_mejor_plan_intento = 0;
                    for kk = 1:intento_paralelo_actual
                        if intentos_actuales{kk}.Valido
                            existe_mejora = true;
                            intento_actual_sin_mejora_intermedia = intentos_actuales{kk}.SinMejoraIntermedia;
                            intento_actual_es_adelanta = intentos_actuales{kk}.AdelantaProyectos;
                            intento_actual_es_elimina = intentos_actuales{kk}.PlanActualHastaEtapa == cantidad_etapas;
                            intento_actual_es_desplaza = intentos_actuales{kk}.PlanActualHastaEtapa < cantidad_etapas;
                            existe_mejora_adelanta = intentos_actuales{kk}.ExisteMejoraParcialAdelanta;
                            if ~intento_actual_sin_mejora_intermedia && ~intento_actual_es_adelanta && ~existe_mejora_adelanta
                                if isempty(find(proy_potenciales_eliminar == intentos_actuales{kk}.proy_seleccionados.seleccionado, 1))
                                    proy_potenciales_eliminar = [proy_potenciales_eliminar intentos_actuales{kk}.proy_seleccionados.seleccionado];
                                end
                                % elimina proyecto seleccionado de
                                % potenciales a adelantar en caso de que
                                % esté
                                proy_potenciales_adelantar(proy_potenciales_adelantar == intentos_actuales{kk}.proy_seleccionados.seleccionado) = [];
                            elseif intento_actual_es_adelanta || existe_mejora_adelanta
                                if isempty(find(proy_potenciales_adelantar == intentos_actuales{kk}.proy_seleccionados.seleccionado, 1))
                                    proy_potenciales_adelantar = [proy_potenciales_adelantar intentos_actuales{kk}.proy_seleccionados.seleccionado];
                                end
                                % elimina proyecto seleccionado de
                                % potenciales a eliminar en caso de que
                                % esté
                                proy_potenciales_eliminar(proy_potenciales_eliminar == intentos_actuales{kk}.proy_seleccionados.seleccionado) = [];
                            end
                            es_mejor_intento = false;
                            if id_mejor_plan_intento == 0
                                es_mejor_intento = true;
                            else
                                if intento_actual_es_adelanta
                                    if ~mejor_intento_es_adelanta
                                        es_mejor_intento = true;
                                    else
                                        if intentos_actuales{kk}.Totex < mejor_totex
                                            es_mejor_intento = true;
                                        end
                                    end 
                                elseif prio_desplaza_sobre_elimina && ...
                                        intento_actual_es_desplaza
                                    if mejor_intento_es_elimina
                                        es_mejor_intento = true;
                                    elseif mejor_intento_es_desplaza
                                        if intentos_actuales{kk}.Totex < mejor_totex
                                            es_mejor_intento = true;
                                        end
                                    end                                    
                                else
                                    % intento es elimina. 
                                    if intentos_actuales{kk}.Totex < mejor_totex
                                        if ~mejor_intento_es_adelanta 
                                            if ~prio_desplaza_sobre_elimina
                                                if intento_actual_sin_mejora_intermedia <= mejor_intento_sin_mejora_intermedia
                                                    es_mejor_intento = true;
                                                end
                                            else
                                                if ~mejor_intento_es_desplaza
                                                    if intento_actual_sin_mejora_intermedia <= mejor_intento_sin_mejora_intermedia
                                                        es_mejor_intento = true;
                                                    end
                                                end
                                            end
                                        end
                                    else
                                        if ~mejor_intento_es_adelanta 
                                            if ~prio_desplaza_sobre_elimina
                                                if intento_actual_sin_mejora_intermedia < mejor_intento_sin_mejora_intermedia
                                                    es_mejor_intento = true;
                                                end
                                            else
                                                if ~mejor_intento_es_desplaza
                                                    if intento_actual_sin_mejora_intermedia < mejor_intento_sin_mejora_intermedia
                                                        es_mejor_intento = true;
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end

                            if es_mejor_intento
                                id_mejor_plan_intento = kk;
                                mejor_totex = intentos_actuales{kk}.Totex;
                                mejor_intento_sin_mejora_intermedia = intento_actual_sin_mejora_intermedia;
                                mejor_intento_es_adelanta = intento_actual_es_adelanta;
                                mejor_intento_es_elimina = intento_actual_es_elimina;
                                mejor_intento_es_desplaza = intento_actual_es_desplaza;                                
                            end

                            if nivel_debug > 1
                                if intentos_actuales{kk}.AdelantaProyectos
                                    proyectos_adelantar = [intentos_actuales{kk}.proy_seleccionados.proy_conect_adelantar intentos_actuales{kk}.proy_seleccionados.seleccionado];
                                    texto = ['      Intento ' num2str(kk) ' es valido. Sin mejora intermedia: A' ...
                                             '. Totex intento: ' num2str(intentos_actuales{kk}.Totex) '. Proyectos adelantar: '];
                                    for oo = 1:length(proyectos_adelantar)
                                        texto = [texto ' ' num2str(proyectos_adelantar(oo))];
                                    end
                                else
                                    % elimina o desplaza proyectos
                                    if intentos_actuales{kk}.PlanActualHastaEtapa == cantidad_etapas
                                        texto_adicional = num2str(intento_actual_sin_mejora_intermedia);
                                        texto_adicional_2 = '. Proyectos eliminar: ';
                                    else
                                        texto_adicional = 'D';
                                        texto_adicional_2 = '. Proyectos desplazar: ';
                                    end
                                    proyectos_eliminar = [intentos_actuales{kk}.proy_seleccionados.conectividad_eliminar intentos_actuales{kk}.proy_seleccionados.seleccionado];
                                    texto = ['      Intento ' num2str(kk) ' es valido. Sin mejora intermedia: ' texto_adicional ...
                                             '. Totex intento: ' num2str(intentos_actuales{kk}.Totex) texto_adicional_2];
                                    for oo = 1:length(proyectos_eliminar)
                                        texto = [texto ' ' num2str(proyectos_eliminar(oo))];
                                    end
                                end
                                fprintf(doc_id, strcat(texto, '\n'));
                            end 
                        else
                            if ~isempty(intentos_actuales{kk}.proy_seleccionados.seleccionado)
                                proy_potenciales_eliminar(proy_potenciales_eliminar == intentos_actuales{kk}.proy_seleccionados.seleccionado) = [];
                                proy_potenciales_adelantar(proy_potenciales_adelantar == intentos_actuales{kk}.proy_seleccionados.seleccionado) = [];
                            end
                        end
                    end

                    if existe_mejora
                        existe_cambio_global = true;
                        if nivel_debug > 1
                            texto = ['      Mejor intento: ' num2str(id_mejor_plan_intento)];
                            fprintf(doc_id, strcat(texto, '\n'));
                        end

                        expansion_actual.Proyectos = intentos_actuales{id_mejor_plan_intento}.Proyectos;
                        expansion_actual.Etapas = intentos_actuales{id_mejor_plan_intento}.Etapas;
                        evaluacion_actual = intentos_actuales{id_mejor_plan_intento}.evaluacion_actual;
                        estructura_costos_actual = intentos_actuales{id_mejor_plan_intento}.estructura_costos_actual;
                        plan_prueba.Proyectos = expansion_actual.Proyectos;
                        plan_prueba.Etapas = expansion_actual.Etapas;
                        plan_prueba.inserta_estructura_costos(estructura_costos_actual);
                        plan_prueba.inserta_evaluacion(evaluacion_actual);

                        proy_potenciales_eliminar(proy_potenciales_eliminar == intentos_actuales{id_mejor_plan_intento}.proy_seleccionados.seleccionado) = [];
                        proy_potenciales_adelantar(proy_potenciales_adelantar == intentos_actuales{id_mejor_plan_intento}.proy_seleccionados.seleccionado) = [];

                        % se implementa plan hasta la etapa actual del mejor intento
                        desde_etapa = intentos_actuales{id_mejor_plan_intento}.DesdeEtapaIntento;
                        ultima_etapa_valida_intento = intentos_actuales{id_mejor_plan_intento}.PlanActualHastaEtapa;

                        if intentos_actuales{id_mejor_plan_intento}.AdelantaProyectos
                            proy_adelantar = intentos_actuales{id_mejor_plan_intento}.proy_seleccionados;
                            if ~intentos_actuales{id_mejor_plan_intento}.AdelantaProyectosForzado
                                proyectos_restringidos_para_eliminar = [proyectos_restringidos_para_eliminar proy_adelantar.seleccionado];
                            end
                            for nro_etapa = ultima_etapa_valida_intento:desde_etapa-1
                                % agrega proyectos en sep actual en etapa actual
                                for k = 1:length(proy_adelantar.proy_conect_adelantar)
                                    if nro_etapa < proy_adelantar.etapas_orig_conect(k)
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.proy_conect_adelantar(k));
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    end
                                end
                                proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.seleccionado);
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            end
                            
                            % guarda cambios globales en plan prueba y actualiza capacidades proyectos de conectividad adelantar
                            for k = 1:length(proy_adelantar.proy_conect_adelantar)
                                id_existente = find(proyectos_cambiados_prueba == proy_adelantar.proy_conect_adelantar(k));
                                
                                if ~isempty(id_existente)
                                    etapas_nuevas_plan_prueba(id_existente) = ultima_etapa_valida_intento;
                                else
                                    proyectos_cambiados_prueba = [proyectos_cambiados_prueba proy_adelantar.proy_conect_adelantar(k)];
                                    etapas_originales_plan_actual = [etapas_originales_plan_actual proy_adelantar.etapas_orig_conect(k)];
                                    etapas_nuevas_plan_prueba = [etapas_nuevas_plan_prueba ultima_etapa_valida_intento];
                                end
                            end
                            % proyecto principal adelantar
                            
                            id_existente = find(proyectos_cambiados_prueba == proy_adelantar.seleccionado);
                            if ~isempty(id_existente)
                                etapas_nuevas_plan_prueba(id_existente) = ultima_etapa_valida_intento;
                            else
                                proyectos_cambiados_prueba = [proyectos_cambiados_prueba proy_adelantar.seleccionado];
                                etapas_originales_plan_actual = [etapas_originales_plan_actual desde_etapa];
                                etapas_nuevas_plan_prueba = [etapas_nuevas_plan_prueba ultima_etapa_valida_intento];
                            end
                            
                            % actualiza capacidades plan prueba. Sólo proyectos principales
                            %etapa_orig = desde_etapa;
                            %etapa_nuevas = ultima_etapa_valida_intento;
                            proy_ppal = this.pAdmProy.entrega_proyecto(proy_adelantar.seleccionado);                            
                            delta_capacidad = proy_ppal.entrega_capacidad_adicional();
                            id_decision = proy_ppal.entrega_indice_decision_expansion();
                            
                            capacidades_plan_prueba(id_decision, ultima_etapa_valida_intento:desde_etapa-1) = ...
                                capacidades_plan_prueba(id_decision, ultima_etapa_valida_intento:desde_etapa-1) + delta_capacidad;                                
                        else
                            proy_seleccionados = intentos_actuales{id_mejor_plan_intento}.proy_seleccionados;
                            proyectos_eliminar = [proy_seleccionados.conectividad_eliminar proy_seleccionados.seleccionado];
                            etapas_eliminar = [proy_seleccionados.etapas_conectividad_eliminar proy_seleccionados.etapa_seleccionado];
                            proyectos_desplazar = proy_seleccionados.conectividad_desplazar;
                            etapas_originales_desplazar = proy_seleccionados.etapas_orig_conectividad_desplazar;
                            etapas_desplazar = proy_seleccionados.etapas_fin_conectividad_desplazar;

                            % elimina de lista todos los otros proyectos. Ocurre a veces que trafo paralelo es eliminado como proyecto de conectividad
                            proy_potenciales_eliminar(ismember(proy_potenciales_eliminar, proy_seleccionados.conectividad_eliminar)) = [];
                            proy_potenciales_adelantar(ismember(proy_potenciales_adelantar, proy_seleccionados.conectividad_eliminar)) = [];

                            for nro_etapa = desde_etapa:ultima_etapa_valida_intento
                                % desplaza proyectos a eliminar 
                                for k = length(proyectos_eliminar):-1:1
                                    if etapas_eliminar(k) <= nro_etapa
                                        proyecto = this.pAdmProy.entrega_proyecto(proyectos_eliminar(k));
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    end
                                end
                                %desplaza proyectos
                                for k = length(proyectos_desplazar):-1:1
                                    if nro_etapa >= etapas_originales_desplazar(k) && nro_etapa < etapas_desplazar(k) 
                                        proyecto = this.pAdmProy.entrega_proyecto(proyectos_desplazar(k));
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    end
                                end
                            end

                            if ultima_etapa_valida_intento ~= cantidad_etapas && ~intentos_actuales{id_mejor_plan_intento}.DesplazaProyectosForzado
                                % quiere decir que proyecto no fue eliminado completamente, pero sí desplazado se agrega proyectos_eliminar a proyectos restringidos para eliminar, ya que ya fue
                                % desplazado. A menos que haza sido forzado...
                                proyectos_restringidos_para_eliminar = [proyectos_restringidos_para_eliminar proy_seleccionados.seleccionado];
                            end
                            
                            % guarda cambios globales en plan prueba
                            for k = length(proyectos_eliminar):-1:1
                                id_existente = find(proyectos_cambiados_prueba == proyectos_eliminar(k));
                                if ~isempty(id_existente)
                                    etapas_nuevas_plan_prueba(id_existente) = ultima_etapa_valida_intento+1;
                                else
                                    proyectos_cambiados_prueba = [proyectos_cambiados_prueba proyectos_eliminar(k)];
                                    etapas_originales_plan_actual = [etapas_originales_plan_actual desde_etapa];
                                    etapas_nuevas_plan_prueba = [etapas_nuevas_plan_prueba ultima_etapa_valida_intento+1];
                                end
                            end
                            %desplaza proyectos
                            for k = length(proyectos_desplazar):-1:1
                                id_existente = find(proyectos_cambiados_prueba == proyectos_desplazar(k));
                                if ~isempty(id_existente)
                                    etapas_nuevas_plan_prueba(id_existente) = etapas_desplazar(k)+1;
                                else
                                    proyectos_cambiados_prueba = [proyectos_cambiados_prueba proyectos_desplazar(k)];
                                    etapas_originales_plan_actual = [etapas_originales_plan_actual etapas_originales_desplazar(k)];
                                    etapas_nuevas_plan_prueba = [etapas_nuevas_plan_prueba etapas_desplazar(k)+1];
                                end                                
                            end
                            
                            % Actualiza capacidades plan prueba. Sólo proyecto principal
                            %etapa_orig = proy_seleccionados.etapa_seleccionado;
                            %etapa_nuevas = ultima_etapa_valida_intento;
                            proy_ppal = this.pAdmProy.entrega_proyecto(proy_seleccionados.seleccionado);                            
                            delta_capacidad = proy_ppal.entrega_capacidad_adicional();
                            id_decision = proy_ppal.entrega_indice_decision_expansion();
                            
                            capacidades_plan_prueba(id_decision, proy_seleccionados.etapa_seleccionado:ultima_etapa_valida_intento) = ...
                                capacidades_plan_prueba(id_decision, proy_seleccionados.etapa_seleccionado:ultima_etapa_valida_intento) - delta_capacidad;                                
                        end

                        if nivel_debug > 1
                            texto = '      Lista proy potenciales a eliminar: ';
                            for ii = 1:length(proy_potenciales_eliminar)
                                texto = [texto ' ' num2str(proy_potenciales_eliminar(ii))];
                            end
                            fprintf(doc_id, strcat(texto, '\n'));

                            texto = '      Lista proy potenciales a adelantar: ';
                            for ii = 1:length(proy_potenciales_adelantar)
                                texto = [texto ' ' num2str(proy_potenciales_adelantar(ii))];
                            end
                            fprintf(doc_id, strcat(texto, '\n'));

                            if nivel_debug > 2
                                texto = 'Imprime plan actual despues de los intentos';
                                fprintf(doc_id, strcat(texto, '\n'));
                                plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                                texto = plan_prueba.entrega_texto_plan_expansion();
                                fprintf(doc_id, strcat(texto, '\n'));
                                
                                for etapa_debug = 1:cantidad_etapas
                                    this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{etapa_debug}, plan_prueba, etapa_debug, 'Punto verificacion 9')
                                end
                                this.debug_verifica_consistencia_plan_valido(plan_prueba, 'Punto verificacion 9');
                                this.debug_verifica_capacidades_corredores(plan_prueba, capacidades_plan_prueba, 'Punto verificacion 10');

                            end
                        end
                    else
                        cant_busqueda_fallida = cant_busqueda_fallida + 1;
                        % no hubo mejora por lo que no es necesario
                        % rehacer ningún plan
                        if nivel_debug > 1
                            texto = '      No hubo mejora en ninguno de los intentos';
                            fprintf(doc_id, strcat(texto, '\n'));

                            texto = '      Lista proy potenciales a eliminar: ';
                            for ii = 1:length(proy_potenciales_eliminar)
                                texto = [texto ' ' num2str(proy_potenciales_eliminar(ii))];
                            end
                            fprintf(doc_id, strcat(texto, '\n'));

                            texto = '      Lista proy potenciales a adelantar: ';
                            for ii = 1:length(proy_potenciales_adelantar)
                                texto = [texto ' ' num2str(proy_potenciales_adelantar(ii))];
                            end
                            fprintf(doc_id, strcat(texto, '\n'));
                        end
                    end
                end % fin búsqueda local
                
                if nivel_debug > 1
                    texto = 'Fin busqueda local';
                    fprintf(doc_id, strcat(texto, '\n'));
                    if ~existe_cambio_global
                        texto = 'No hubo cambio en el plan';
                        fprintf(doc_id, strcat(texto, '\n'));
                    else
                        texto = ['Totex original: ' num2str(pPlan.entrega_totex_total())];
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = ['Totex prueba  : ' num2str(plan_prueba.entrega_totex_total())];
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = sprintf('%-25s %-10s %-15s %-15s', 'Proy. seleccionados', 'Modificar', 'Etapa original', 'Nueva etapa');
                        fprintf(doc_id, strcat(texto, '\n'));
                        for ii = 1:length(proyectos_cambiados_prueba)
                            proy_orig = proyectos_cambiados_prueba(ii);
                            etapa_orig = pPlan.entrega_etapa_proyecto(proy_orig, false);
                            nueva_etapa = plan_prueba.entrega_etapa_proyecto(proy_orig, false);
                            if ii <= length(proyectos_modificar)
                                texto = sprintf('%-25s %-10s %-15s %-15s', num2str(proy_orig), 'si', num2str(etapa_orig), num2str(nueva_etapa));
                            else
                                texto = sprintf('%-25s %-10s %-15s %-15s', num2str(proy_orig), 'no', num2str(etapa_orig), num2str(nueva_etapa));
                            end
                            fprintf(doc_id, strcat(texto, '\n'));
                        end
                    end

                    if nivel_debug > 2
                        texto = 'Plan original:';
                        fprintf(doc_id, strcat(texto, '\n'));

                        pPlan.agrega_nombre_proyectos(this.pAdmProy);
                        texto = pPlan.entrega_texto_plan_expansion();
                        fprintf(doc_id, strcat(texto, '\n'));

                        texto = 'Plan prueba:';
                        fprintf(doc_id, strcat(texto, '\n'));
                        plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                        texto = plan_prueba.entrega_texto_plan_expansion();
                        fprintf(doc_id, strcat(texto, '\n'));
                    end
                end

                % determina si hay cambio o no
                if existe_cambio_global
                    if plan_prueba.entrega_totex_total() <= pPlan.entrega_totex_total()
                        acepta_cambio = true;
                    else
                        f_obj_prueba = plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                        f_obj_actual = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                        sigma = this.pParOpt.SigmaFuncionLikelihood;
                        prob_cambio = exp((-f_obj_prueba^2+f_obj_actual^2)/(2*sigma^2));

                        if nivel_debug > 1
                            texto = ['Probabilidad de cambio cadena ' num2str(nro_cadena) ': ' num2str(prob_cambio)];
                            fprintf(doc_id, strcat(texto, '\n'));
                        end
                        if rand < prob_cambio
                            acepta_cambio = true;
                        else
                            acepta_cambio = false;
                        end
                    end
                else
                    acepta_cambio = false;
                end

                if acepta_cambio
                    if nivel_debug > 1
                        texto = 'Se acepta cambio de plan';
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = ['Totex actual (f objetivo): ' num2str(pPlan.entrega_totex_total()) ' (' num2str(pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')'];
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = ['Totex nuevo (f objetivo): ' num2str(plan_prueba.entrega_totex_total()) ' (' num2str(plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')'];
                        fprintf(doc_id, strcat(texto, '\n'));                        
                    end
                    % se guarda nuevo plan en cadena
                    pPlan = plan_prueba;
                    cadenas{nro_cadena}.plan_actual = plan_prueba;
                    cadenas{nro_cadena}.CambiosEstado(paso_actual) = 1;
                    cadenas{nro_cadena}.Proyectos(paso_actual,:) = cadenas{nro_cadena}.Proyectos(paso_actual-1,:);
                    cadenas{nro_cadena}.CapacidadDecisionesPrimarias = capacidades_plan_prueba;
                    for ii = 1:length(proyectos_cambiados_prueba)
                        if etapas_nuevas_plan_prueba(ii) <= cantidad_etapas
                            cadenas{nro_cadena}.Proyectos(paso_actual,proyectos_cambiados_prueba(ii)) = etapas_nuevas_plan_prueba(ii);
                        else
                            cadenas{nro_cadena}.Proyectos(paso_actual,proyectos_cambiados_prueba(ii)) = 0;
                        end
                    end
                    cadenas{nro_cadena}.Totex(paso_actual) = pPlan.entrega_totex_total();
                    cadenas{nro_cadena}.FObj(paso_actual) = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                    % estadística
                    if pPlan.entrega_totex_total() < cadenas{nro_cadena}.MejorTotex
                        cadenas{nro_cadena}.MejorTotex = pPlan.entrega_totex_total();
                        cadenas{nro_cadena}.MejorFObj = pPlan.entrega_totex_total() - this.NPVCostosOperacionSinRestriccion;
                        if cadenas{nro_cadena}.TiempoEnLlegarAlOptimo == 0 && ...
                           round(cadenas{nro_cadena}.MejorTotex,5) == round(this.PlanOptimo.TotexTotal,5)
                            cadenas{nro_cadena}.TiempoEnLlegarAlOptimo = etime(clock,t_inicio_proceso);
                        end
                    end
                else
                    if nivel_debug > 1
                        texto = 'No se acepta cambio de plan';
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = ['Totex actual (f objetivo): ' num2str(pPlan.entrega_totex_total()) '(' num2str(pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')'];
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = ['Totex no aceptado (f objetivo): ' num2str(plan_prueba.entrega_totex_total()) '(' num2str(plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')'];
                        fprintf(doc_id, strcat(texto, '\n'));
                    end
                    cadenas{nro_cadena}.CambiosEstado(paso_actual) = 0;
                    cadenas{nro_cadena}.Proyectos(paso_actual,:) = cadenas{nro_cadena}.Proyectos(paso_actual-1,:);
                    cadenas{nro_cadena}.Totex(paso_actual) = pPlan.entrega_totex_total();
                    cadenas{nro_cadena}.FObj(paso_actual) = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                    % se deshacen los cambios en el SEP
                    desde_etapa = min(min(etapas_originales_plan_actual), min(etapas_nuevas_plan_prueba));
                    hasta_etapa = min(cantidad_etapas, max(max(etapas_originales_plan_actual), max(etapas_nuevas_plan_prueba)));

                    for nro_etapa = desde_etapa:hasta_etapa
                        for jj = 1:length(proyectos_cambiados_prueba)
                            if etapas_nuevas_plan_prueba(jj) < cantidad_etapas + 1 && ...
                               etapas_nuevas_plan_prueba(jj) < etapas_originales_plan_actual(jj) && ...
                               nro_etapa >= etapas_nuevas_plan_prueba(jj) && ...
                               nro_etapa < etapas_originales_plan_actual(jj) 
                                % proyecto se retrasa, por lo que hay que eliminarlo del SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_cambiados_prueba(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                            elseif etapas_nuevas_plan_prueba(jj) > etapas_originales_plan_actual(jj) && ...
                                   nro_etapa >=  etapas_originales_plan_actual(jj) && ...
                                   nro_etapa < etapas_nuevas_plan_prueba(jj) 
                                % proyecto se adelanta, por lo que hay que
                                % agregarlo al SEP
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_cambiados_prueba(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            end
                        end
                        
                        if nivel_debug > 2
                            this.debug_verifica_consistencia_proyectos_en_sep_y_plan(cadenas{nro_cadena}.sep_actuales{nro_etapa}, pPlan, nro_etapa, 'Punto verificacion 13');
                        end
                    end
                end

                if nivel_debug > 1
                    texto = [' Totex paso anterior: ' num2str(cadenas{nro_cadena}.Totex(paso_actual-1))];
                    fprintf(doc_id, strcat(texto, '\n'));
                    texto = [' Totex paso actual  : ' num2str(cadenas{nro_cadena}.Totex(paso_actual))];
                    fprintf(doc_id, strcat(texto, '\n'));

                    dt_paso = etime(clock,tinicio_paso);

                    totex_anterior = num2str(round(cadenas{nro_cadena}.Totex(paso_actual-1),4));

                    gap = round((cadenas{nro_cadena}.MejorTotex-this.TotexPlanOptimo)/(this.TotexPlanOptimo)*100,3);
                    gap_actual = round((cadenas{nro_cadena}.plan_actual.entrega_totex_total()-this.TotexPlanOptimo)/this.TotexPlanOptimo*100,3);
                    valido = cadenas{nro_cadena}.plan_actual.es_valido();
                    if ~valido
                        texto_valido = 'no';
                    else
                        texto_valido = '';
                    end
                    text = sprintf('%-7s %-5s %-7s %-15s %-15s %-15s %-10s %-10s %-10s %-10s',num2str(nro_cadena), ...
                                                                         num2str(paso_actual),...
                                                                         texto_valido,...
                                                                         num2str(round(cadenas{nro_cadena}.plan_actual.entrega_totex_total(),4)),...
                                                                         totex_anterior,...
                                                                         num2str(cadenas{nro_cadena}.MejorTotex),...
                                                                         num2str(gap_actual), ...
                                                                         num2str(gap), ...
                                                                         num2str(dt_paso));

                    disp(text);

                    fclose(doc_id);
                end
            end % todas las cadenas
        end
        
        function cadenas = intercambia_cadenas(this, cadenas, paso_actual)
            cantidad_cadenas_principales = this.pParOpt.CantidadCadenas;
            delta_cadenas = length(this.pParOpt.BetaCadenas);

            for id_cadena = 1:cantidad_cadenas_principales
                i = (id_cadena-1)*delta_cadenas+1;

                cant_intercambios = min(sum(rand(this.pParOpt.PasoActualizacion,1) < 1/this.pParOpt.NsIntercambioCadenas),delta_cadenas-1);
                cadena_intercambiada = [];
                while cant_intercambios > 0
                    cant_intercambios = cant_intercambios - 1;
                    % se intercambian cadenas
                    cadena_inferior = floor(rand*(delta_cadenas-1))+i; %i a i+3 (1 a 4)
                    while ismember(cadena_inferior, cadena_intercambiada)
                        cadena_inferior = floor(rand*(delta_cadenas-1))+i;
                    end
                    cadena_intercambiada = [cadena_intercambiada cadena_inferior];
                    cadena_superior = cadena_inferior+1;
                    beta_inferior = cadenas{cadena_inferior}.Beta;
                    beta_superior = cadenas{cadena_superior}.Beta;
                    %beta_cadenas = [0.01 0.2575 0.505 0.7525 1];
                    % r = min(1, 
                    sigma = this.pParOpt.SigmaFuncionLikelihood;
                    totex_inferior = cadenas{cadena_inferior}.plan_actual.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                    totex_superior = cadenas{cadena_superior}.plan_actual.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                    prob_cambio = exp(beta_inferior*(-totex_superior^2+totex_inferior^2)/(2*sigma^2))*exp(beta_superior*(-totex_inferior^2+totex_superior^2)/(2*sigma^2));
                    prob_cambio = min(1, prob_cambio);
if this.iNivelDebug > 2
prot.imprime_texto(['Probabilidad de cambio para intercambio de cadenas ' num2str(cadena_inferior) ' y ' num2str(cadena_superior) ':' num2str(prob_cambio)] );    
end

                    if rand < prob_cambio
if this.iNivelDebug > 2
prot.imprime_texto(['Se intercambian cadenas ' num2str(cadena_inferior) ' y ' num2str(cadena_superior)]);
end
                        % se intercambian los planes actuales de las
                        % cadenas
                        plan_cadena_inferior = cadenas{cadena_superior}.plan_actual;
                        plan_cadena_superior = cadenas{cadena_inferior}.plan_actual;
                        cadenas{cadena_superior}.plan_actual = plan_cadena_superior;
                        cadenas{cadena_inferior}.plan_actual = plan_cadena_inferior;

                        % intercambia sep actuales
                        sep_actuales_inferior = cadenas{cadena_superior}.sep_actuales;
                        sep_actuales_superior = cadenas{cadena_inferior}.sep_actuales;
                        cadenas{cadena_inferior}.sep_actuales = sep_actuales_inferior;
                        cadenas{cadena_superior}.sep_actuales = sep_actuales_superior;

                        %estadísticas
                        cadenas{cadena_inferior}.IntercambioCadena(paso_actual) = cadena_superior;
                        cadenas{cadena_superior}.IntercambioCadena(paso_actual) = cadena_inferior;

                    end
                end
            end
        end
        
        function cadenas = calcula_tolerancia_sigmas(this, cadenas)
            nivel_debug = this.pParOpt.NivelDebug;
%           parfor nro_cadena = 1:cantidad_cadenas
            cantidad_calculos = this.pParOpt.NToleranciaSigma;
            cantidad_cadenas_principales = this.pParOpt.CantidadCadenas;
            delta_cadenas = length(this.pParOpt.BetaCadenas);

            for id_cadena = 1:cantidad_cadenas_principales
                nro_cadena = (id_cadena-1)*delta_cadenas+1;

                if nivel_debug > 1
                    prot = cProtocolo.getInstance;
                    texto = ['Comienzo proceso calcula tolerancia sigma en cadena ' num2str(nro_cadena)];
                    prot.imprime_texto(texto);
                end
                pPlan = cadenas{nro_cadena}.plan_actual;
                cantidad_parametros = this.pAdmProy.CantidadProyTransmision;
                for id_parametro = 1:cantidad_parametros
                    if nivel_debug > 1
                        prot.imprime_texto('');
                        texto = ['Proyecto a modificar ' num2str(id_parametro) '. Sigma proyecto: ' num2str(cadenas{nro_cadena}.SigmaActual(id_parametro))];
                        prot.imprime_texto(texto);
                        texto = sprintf('%-7s %-5s %-13s %-13s %-15s %-15s %-15s %-10s %-10s', 'Trial', 'Proy', 'Etapa orig', 'Etapa Nueva', 'Totex orig', 'Totex nuevo', 'Pbb cambio', 'Cambio', 'Tasa');
                        prot.imprime_texto(texto);
                        %pPlan.agrega_nombre_proyectos(this.pAdmProy);
                        %pPlan.imprime_plan_expansion();
                        %end
                    end
                    paso_actual = 1;
                    cantidad_cambios = 0;
                    cantidad_etapas = this.pParOpt.CantidadEtapas;
                    etapa_original_parametro = pPlan.entrega_etapa_proyecto(id_parametro, false);
                    if etapa_original_parametro == 0
                        etapa_original_parametro = cantidad_etapas + 1;
                    end

                    while paso_actual <= cantidad_calculos


                        plan_prueba = cPlanExpansion(pPlan.entrega_no() + 1);
                        plan_prueba.Proyectos = pPlan.Proyectos;
                        plan_prueba.Etapas = pPlan.Etapas;
                        plan_prueba.inserta_evaluacion(pPlan.entrega_evaluacion());
                        plan_prueba.inserta_estructura_costos(pPlan.entrega_estructura_costos());

                        existe_cambio_global = false;

                        proyectos_cambiados_prueba = [];
                        etapas_originales_plan_actual = [];
                        etapas_nuevas_plan_prueba = [];
                        % genera nuevo trial

                        [proyectos_modificar, etapas_originales, nuevas_etapas]= this.modifica_parametro(plan_prueba, id_parametro, cadenas{nro_cadena}.SigmaActual(id_parametro));
                            if nivel_debug > 1
                                texto = ['      Proyectos modificados (' num2str(length(proyectos_modificar)) '):'];
                                prot.imprime_texto(texto);
                                for ii = 1:length(proyectos_modificar)
                                   texto = ['       ' num2str(proyectos_modificar(ii)) ' de etapa ' num2str(etapas_originales(ii)) ' a etapa ' num2str(nuevas_etapas(ii))];
                                   prot.imprime_texto(texto);
                                end
                            end
                        if ~isequal(etapas_originales, nuevas_etapas)
                            proyectos_cambiados_prueba = proyectos_modificar;
                            etapas_originales_plan_actual = etapas_originales;
                            etapas_nuevas_plan_prueba = nuevas_etapas;

                            existe_cambio_global = true;
                            % se actualiza la red y se calcula nuevo totex de
                            % proyectos modificados
                            desde_etapa = min(min(etapas_originales), min(nuevas_etapas));
                            hasta_etapa = min(cantidad_etapas, max(max(etapas_originales), max(nuevas_etapas)));

                            for nro_etapa = desde_etapa:hasta_etapa
                                for jj = 1:length(proyectos_modificar)
                                    if etapas_originales(jj) < cantidad_etapas + 1 && ...
                                        etapas_originales(jj) < nuevas_etapas(jj) && ...
                                        nro_etapa >= etapas_originales(jj) && ...
                                        nro_etapa < nuevas_etapas(jj) 

                                        % proyecto se retrasa, por lo que hay que eliminarlo del SEP
                                        proyecto = this.pAdmProy.entrega_proyecto(proyectos_modificar(jj));
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    elseif etapas_originales(jj) > nuevas_etapas(jj) && ...
                                            nro_etapa >=  nuevas_etapas(jj) && ...
                                            nro_etapa < etapas_originales(jj) 
                                        % proyecto se adelanta, por lo que hay que
                                        % agregarlo al SEP
                                        proyecto = this.pAdmProy.entrega_proyecto(proyectos_modificar(jj));
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    end
                                end
proyectos_en_sep = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = plan_prueba.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
prot.imprime_texto(['Proyectos en SEP en etapa ' num2str(nro_etapa) ' es distinto a proyectos en plan']);
prot.imprime_texto(['Proyectos en SEP: ' num2str(proyectos_en_sep)]);
prot.imprime_texto(['Proyectos en plan: ' num2str(proyectos_en_plan)]);
    
error = MException('cOptMCMC:optimiza_deterministico',...
'Intento fallido 1. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                            end
                            this.calcula_costos_totales(plan_prueba);
                        end  

                        if nivel_debug > 1
                            texto = ['      Totex plan actual: ' num2str(pPlan.entrega_totex_total())];
                            prot.imprime_texto(texto);
                            texto = ['      Totex plan prueba: ' num2str(plan_prueba.entrega_totex_total())];
                            prot.imprime_texto(texto);
                            prot.imprime_texto('      Se imprime plan prueba (modificado)');
                            plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                            plan_prueba.imprime_plan_expansion();
                        end
                        if this.pParOpt.OptimizaEnCalculosTolerancia
                            % por ahora no implementado
                        end
                        if nivel_debug > 1
                            prot.imprime_texto('Fin proceso de cambio de plan en tolerancia sigma');
                            prot.imprime_texto(['Totex original: ' num2str(pPlan.entrega_totex_total())]);
                            prot.imprime_texto(['Totex prueba  : ' num2str(plan_prueba.entrega_totex_total())]);
                            texto = sprintf('%-25s %-10s %-15s %-15s', 'Proyectos seleccionados', 'Modificar', 'Etapa original', 'Nueva etapa');
                            prot.imprime_texto(texto);
                            for ii = 1:length(proyectos_modificar)
                                proy_orig = proyectos_modificar(ii);
                                etapa_orig = pPlan.entrega_etapa_proyecto(proy_orig, false);
                                nueva_etapa = plan_prueba.entrega_etapa_proyecto(proy_orig, false);
                                texto = sprintf('%-25s %-10s %-15s %-15s', num2str(proyectos_modificar(ii)), 'si', num2str(etapa_orig), num2str(nueva_etapa));
                                prot.imprime_texto(texto);
                            end
                            for ii = 1:length(proyectos_seleccionados_original)
                                proy_orig = proyectos_seleccionados_original(ii);
                                etapa_orig = pPlan.entrega_etapa_proyecto(proy_orig, false);
                                nueva_etapa = plan_prueba.entrega_etapa_proyecto(proy_orig, false);
                                texto = sprintf('%-25s %-10s %-15s %-15s', num2str(proyectos_seleccionados_original(ii)), ' ', num2str(etapa_orig), num2str(nueva_etapa));
                                prot.imprime_texto(texto);
                            end
                        end

                        % determina si hay cambio o no
                        if existe_cambio_global
                            if plan_prueba.entrega_totex_total() <= pPlan.entrega_totex_total()
                                acepta_cambio = true;
                            else
                                f_obj_prueba = plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                                f_obj_actual = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                                sigma = this.pParOpt.SigmaFuncionLikelihood;
                                prob_cambio = exp(cadenas{nro_cadena}.Beta*(-f_obj_prueba^2+f_obj_actual^2)/(2*sigma^2));

                                if nivel_debug > 1
                                    prot.imprime_texto(['Probabilidad de cambio cadena ' num2str(nro_cadena) ': ' num2str(prob_cambio)]);
                                end
                                if rand < prob_cambio
                                    acepta_cambio = true;
                                else
                                    acepta_cambio = false;
                                end
                            end
                        else
                            acepta_cambio = false;
                        end
                        if nivel_debug > 1
                            etapa_orig = pPlan.entrega_etapa_proyecto(id_parametro, false);
                            nueva_etapa = plan_prueba.entrega_etapa_proyecto(id_parametro, false);
                            f_obj_actual = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                            f_obj_prueba = plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                            if existe_cambio_global
                                sigma = this.pParOpt.SigmaFuncionLikelihood;
                                prob_cambio = exp(cadenas{nro_cadena}.Beta*(-f_obj_prueba^2+f_obj_actual^2)/(2*sigma^2));
                            else
                                prob_cambio = 0;
                            end
                            if acepta_cambio
                                texto_cambio = '1';
                                cambios_tot = cantidad_cambios + 1;
                            else
                                texto_cambio = '0';
                                cambios_tot=  cantidad_cambios ;
                            end
                            texto_cum_cambios = [num2str(cambios_tot) '/' num2str(cantidad_calculos)];
                            texto = sprintf('%-7s %-5s %-13s %-13s %-15s %-15s %-15s %-10s %-10s', num2str(paso_actual), num2str(id_parametro), num2str(etapa_orig), num2str(nueva_etapa), num2str(f_obj_actual), num2str(f_obj_prueba), num2str(prob_cambio), texto_cambio, texto_cum_cambios);
                            prot.imprime_texto(texto);
                        end
                        if acepta_cambio
                            if nivel_debug > 1
                                prot.imprime_texto('Se acepta cambio de plan');
                                prot.imprime_texto(['Totex actual (f objetivo): ' num2str(pPlan.entrega_totex_total()) ' (' num2str(pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')']);
                                prot.imprime_texto(['Totex nuevo (f objetivo): ' num2str(plan_prueba.entrega_totex_total()) ' (' num2str(plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')']);
                            end
                            % se guarda nuevo plan en cadena
                            pPlan = plan_prueba;
                            cantidad_cambios = cantidad_cambios + 1;
                        else
                            if nivel_debug > 1
                                prot.imprime_texto('No se acepta cambio de plan');
                                prot.imprime_texto(['Totex actual (f objetivo): ' num2str(pPlan.entrega_totex_total()) '(' num2str(pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')']);
                                prot.imprime_texto(['Totex no aceptado (f objetivo): ' num2str(plan_prueba.entrega_totex_total()) '(' num2str(plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')']);
                            end

                            % se deshacen los cambios en el SEP
                            desde_etapa = min(min(etapas_originales_plan_actual), min(etapas_nuevas_plan_prueba));
                            hasta_etapa = min(cantidad_etapas, max(max(etapas_originales_plan_actual), max(etapas_nuevas_plan_prueba)));

                            for nro_etapa = desde_etapa:hasta_etapa
                                for jj = 1:length(proyectos_cambiados_prueba)
                                    if etapas_nuevas_plan_prueba(jj) < cantidad_etapas + 1 && ...
                                       etapas_nuevas_plan_prueba(jj) < etapas_originales_plan_actual(jj) && ...
                                       nro_etapa >= etapas_nuevas_plan_prueba(jj) && ...
                                       nro_etapa < etapas_originales_plan_actual(jj) 
                                        % proyecto se retrasa, por lo que hay que eliminarlo del SEP
                                        proyecto = this.pAdmProy.entrega_proyecto(proyectos_cambiados_prueba(jj));
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    elseif etapas_nuevas_plan_prueba(jj) > etapas_originales_plan_actual(jj) && ...
                                           nro_etapa >=  etapas_originales_plan_actual(jj) && ...
                                           nro_etapa < etapas_nuevas_plan_prueba(jj) 
                                        % proyecto se adelanta, por lo que hay que
                                        % agregarlo al SEP
                                        proyecto = this.pAdmProy.entrega_proyecto(proyectos_cambiados_prueba(jj));
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    end
                                end
proyectos_en_sep = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = pPlan.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
error = MException('cOptMCMC:optimiza_deterministico',...
'Intento fallido 7. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end

                            end
                        end

                        paso_actual = paso_actual +1;
                    end % pasos cadena terminados
                    
                    % determina tasa de cambios y evalúa si es necesario
                    % modificar el sigma
                    r = cantidad_cambios/cantidad_calculos;
                    sigma_actual = cadenas{nro_cadena}.SigmaActual(id_parametro);
                    if r < this.pParOpt.LimiteInferiorR
                        min_sigma = this.pParOpt.SigmaMin;
                        cadenas{nro_cadena}.SigmaActual(id_parametro) = max(min_sigma, sigma_actual/this.pParOpt.FactorMultCambioSigma);
                    elseif r > this.pParOpt.LimiteSuperiorR
                        max_sigma = this.pParOpt.SigmaMax;
                        cadenas{nro_cadena}.SigmaActual = min(max_sigma, sigma_actual*this.pParOpt.FactorMultCambioSigma);
                    end
                    
                    % deshace cambios hechos
                    etapa_final_parametro = pPlan.entrega_etapa_proyecto(id_parametro, false);
                    if etapa_final_parametro == 0
                        etapa_final_parametro = cantidad_etapas + 1;
                    end
                    if etapa_final_parametro ~= etapa_original_parametro
                        desde_etapa = min(etapa_final_parametro, etapa_original_parametro);
                        hasta_etapa = min(cantidad_etapas, max(etapa_final_parametro, etapa_original_parametro));

                        for nro_etapa = desde_etapa:hasta_etapa
                            if etapa_final_parametro < cantidad_etapas + 1 && ...
                               etapa_final_parametro < etapa_original_parametro && ...
                               nro_etapa >= etapa_final_parametro && ...
                               nro_etapa < etapa_original_parametro
                                % proyecto se retrasa, por lo que hay que eliminarlo del SEP
                                proyecto = this.pAdmProy.entrega_proyecto(id_parametro);
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                            elseif etapa_final_parametro > etapa_original_parametro && ...
                                   nro_etapa >=  etapa_original_parametro && ...
                                   nro_etapa < etapa_final_parametro 
                                % proyecto se adelanta, por lo que hay que
                                % agregarlo al SEP
                                proyecto = this.pAdmProy.entrega_proyecto(id_parametro);
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            end
                        end
                 
                    end
                    pPlan = cadenas{nro_cadena}.plan_actual;

                    % modo debug. Verifica que proyectos en plan original coinciden 100% con
% proyectos en los SEP
for nro_etapa = 1:cantidad_etapas
proyectos_en_sep = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = pPlan.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
prot.imprime_texto(['Proyectos en SEP en etapa ' num2str(nro_etapa) ' es distinto a proyectos en plan']);
prot.imprime_texto(['Proyectos en SEP: ' num2str(proyectos_en_sep)]);
prot.imprime_texto(['Proyectos en plan: ' num2str(proyectos_en_plan)]);
error = MException('cOptMCMC:optimiza_deterministico',...
'Intento fallido 8. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end
end

                end % todos los parámetros
            end
            
            % copia sigmas al resto de las cadenas
            for id_cadena = 1:cantidad_cadenas_principales
                nro_cadena = (id_cadena-1)*delta_cadenas+1;
                for j = 1:delta_cadenas %delta_cadenas = 4
                    cadenas{nro_cadena+j}.SigmaActual = cadenas{nro_cadena}.SigmaActual;
                end
            end
        end

        function cadenas = calcula_tolerancia_sigmas_paralelo(this, cadenas, nivel_debug)
%nivel_debug = this.pParOpt.NivelDebug;
%           parfor nro_cadena = 1:cantidad_cadenas
            cantidad_calculos = this.pParOpt.NToleranciaSigma;
            cantidad_cadenas_principales = this.pParOpt.CantidadCadenas;
            delta_cadenas = length(this.pParOpt.BetaCadenas);
            cantidad_cadenas = this.pParOpt.CantidadCadenas*length(this.pParOpt.BetaCadenas);
            cantidad_parametros = this.pAdmProy.CantidadProyTransmision;
            cantidad_etapas = this.pParOpt.CantidadEtapas;
            parfor nro_cadena = 1:cantidad_cadenas
            
                if cadenas{nro_cadena}.EsPrincipal

                    if nivel_debug > 1    
                        nombre_archivo = ['./output/debug/mcmc_', num2str(nro_cadena),'.dat'];
                        doc_id = fopen(nombre_archivo, 'a');
                        texto = ['Comienzo proceso calcula tolerancia sigma en cadena ' num2str(nro_cadena)];
                        fprintf(doc_id, strcat(texto, '\n'));
                    end
                    
                    pPlan = cadenas{nro_cadena}.plan_actual;
                    for id_parametro = 1:cantidad_parametros
                        if nivel_debug > 1
                            texto = ['Proyecto a modificar ' num2str(id_parametro) '. Sigma proyecto: ' num2str(cadenas{nro_cadena}.SigmaActual(id_parametro))];
                            fprintf(doc_id, strcat(texto, '\n'));
                        end
                        paso_actual = 1;
                        cantidad_cambios = 0;
                        etapa_original_parametro = pPlan.entrega_etapa_proyecto(id_parametro, false);
                        if etapa_original_parametro == 0
                            etapa_original_parametro = cantidad_etapas + 1;
                        end
                        
                        while paso_actual <= cantidad_calculos


                            plan_prueba = cPlanExpansion(pPlan.entrega_no() + 1);
                            plan_prueba.Proyectos = pPlan.Proyectos;
                            plan_prueba.Etapas = pPlan.Etapas;
                            plan_prueba.inserta_evaluacion(pPlan.entrega_evaluacion());
                            plan_prueba.inserta_estructura_costos(pPlan.entrega_estructura_costos());

                            existe_cambio_global = false;

                            proyectos_cambiados_prueba = [];
                            etapas_originales_plan_actual = [];
                            etapas_nuevas_plan_prueba = [];
                            % genera nuevo trial

                            [proyectos_modificar, etapas_originales, nuevas_etapas]= this.modifica_parametro(plan_prueba, id_parametro, cadenas{nro_cadena}.SigmaActual(id_parametro));

                            if ~isequal(etapas_originales, nuevas_etapas)
                                proyectos_cambiados_prueba = proyectos_modificar;
                                etapas_originales_plan_actual = etapas_originales;
                                etapas_nuevas_plan_prueba = nuevas_etapas;

                                existe_cambio_global = true;
                                % se actualiza la red y se calcula nuevo totex de
                                % proyectos modificados
                                desde_etapa = min(min(etapas_originales), min(nuevas_etapas));
                                hasta_etapa = min(cantidad_etapas, max(max(etapas_originales), max(nuevas_etapas)));

                                for nro_etapa = desde_etapa:hasta_etapa
                                    for jj = 1:length(proyectos_modificar)
                                        if etapas_originales(jj) < cantidad_etapas + 1 && ...
                                            etapas_originales(jj) < nuevas_etapas(jj) && ...
                                            nro_etapa >= etapas_originales(jj) && ...
                                            nro_etapa < nuevas_etapas(jj) 

                                            % proyecto se retrasa, por lo que hay que eliminarlo del SEP
                                            proyecto = this.pAdmProy.entrega_proyecto(proyectos_modificar(jj));
                                            cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                        elseif etapas_originales(jj) > nuevas_etapas(jj) && ...
                                                nro_etapa >=  nuevas_etapas(jj) && ...
                                                nro_etapa < etapas_originales(jj) 
                                            % proyecto se adelanta, por lo que hay que
                                            % agregarlo al SEP
                                            proyecto = this.pAdmProy.entrega_proyecto(proyectos_modificar(jj));
                                            cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                        end
                                    end
proyectos_en_sep = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = plan_prueba.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
error = MException('cOptMCMC:optimiza_deterministico',...
'Intento fallido 1. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end
                                    cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                    this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                                end
                                this.calcula_costos_totales(plan_prueba);
                            end

                            if nivel_debug > 1
                                texto = ['      Totex plan actual: ' num2str(pPlan.entrega_totex_total())];
                                fprintf(doc_id, strcat(texto, '\n'));
                                texto = ['      Totex plan prueba: ' num2str(plan_prueba.entrega_totex_total())];
                                fprintf(doc_id, strcat(texto, '\n'));
                                texto = '      Se imprime plan prueba (modificado)';
                                fprintf(doc_id, strcat(texto, '\n'));
                                plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                                texto = plan_prueba.entrega_texto_plan_expansion();
                                fprintf(doc_id, strcat(texto, '\n'));
                            end
                            
                            proyectos_seleccionados_original = [];
                            if this.pParOpt.OptimizaEnCalculosTolerancia && existe_cambio_global
                                proyectos_optimizar_prueba = this.selecciona_proyectos_optimizar_tolerancia_sigma(plan_prueba, proyectos_modificar);

                                if nivel_debug > 1
                                    texto = ['      Proyectos seleccionados a optimizar(' num2str(length(proyectos_optimizar_prueba)) '):'];
                                    for ii = 1:length(proyectos_optimizar_prueba)
                                        texto = [texto ' ' num2str(proyectos_optimizar_prueba(ii))];
                                    end
                                    fprintf(doc_id, strcat(texto, '\n'));
                                    proyectos_seleccionados_original = proyectos_optimizar_prueba;
                                    indice_optimizar_actual = 0;
                                end
                                % optimiza proyectos seleccionados

                                while ~isempty(proyectos_optimizar_prueba)
                                    if length(proyectos_optimizar_prueba) == 1
                                        indice_seleccionado = 1;
                                    else
                                        indice_seleccionado = floor(rand*length(proyectos_optimizar_prueba))+1;
                                    end
                                    proy_seleccionado = proyectos_optimizar_prueba(indice_seleccionado);
                                    proyectos_optimizar_prueba(indice_seleccionado) = [];

                                    if nivel_debug > 1
                                        indice_optimizar_actual = indice_optimizar_actual + 1;
                                        texto = ['      Proyecto seleccionado optimizar ' num2str(indice_optimizar_actual) '/' num2str(length(proyectos_seleccionados_original)) ':' num2str(proy_seleccionado)];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end                        
                                    evaluacion_actual = plan_prueba.entrega_evaluacion();
                                    estructura_costos_actual = plan_prueba.entrega_estructura_costos();
                                    
                                    expansion_actual = struct;
                                    expansion_actual.Proyectos = plan_prueba.Proyectos;
                                    expansion_actual.Etapas = plan_prueba.Etapas;

                                    totex_mejor_etapa = plan_prueba.entrega_totex_total();
                                    plan_valido_mejor_etapa = plan_prueba.es_valido();
                                    mejor_etapa = 0;                        

                                    % modifica sep y evalua plan a partir de primera etapa cambiada
                                    desde_etapa = plan_prueba.entrega_etapa_proyecto(proy_seleccionado, false); % false indica que es sin error. Si proyecto no está en el plan entrega 0
                                    proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionado);
                                    %ultima_etapa_evaluada = desde_etapa;
                                    if desde_etapa == 0
                                        desde_etapa = cantidad_etapas+1;
                                        ultima_etapa_posible = cantidad_etapas;
                                        hay_desplazamiento = false;
                                    else
                                        proy_aguas_arriba = proyecto.IndiceProyectosAguasArriba;
                                        ultima_etapa_posible = plan_prueba.entrega_ultima_etapa_posible_modificacion_proyecto(proy_aguas_arriba, desde_etapa)-1;
                                        if desde_etapa <= ultima_etapa_posible
                                            hay_desplazamiento = true;
                                        else
                                            hay_desplazamiento = false;
                                        end
                                    end


                                    for nro_etapa = desde_etapa:ultima_etapa_posible
                                        % desplaza proyecto
                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                        if nro_etapa < cantidad_etapas
                                            plan_prueba.desplaza_proyectos(proy_seleccionado, nro_etapa, nro_etapa + 1);
                                        else
                                            plan_prueba.elimina_proyectos(proy_seleccionado, nro_etapa);
                                        end
proyectos_en_sep = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = plan_prueba.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
error = MException('cOptMCMC:mapea_espacio_paralelo',...
'Intento fallido 2. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end

                                        cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                        this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                                        this.calcula_costos_totales(plan_prueba);
                                        ultima_etapa_evaluada = nro_etapa;
        %                                 if nivel_debug_paralelo > 1
        %                                     % debug para verificar que opf está funcionando correctamente dentro de
        %                                     % modo de calculo paralelo
        %                                     datos_escenario_debug = [];
        %                                     datos_escenario_debug.CapacidadGeneradores = CapacidadGeneradores(:,nro_etapa);
        %                                     indice_1 = 1 + (nro_etapa - 1)*cantidad_puntos_operacion;
        %                                     indice_2 = nro_etapa*cantidad_puntos_operacion;
        %                                     if ~isempty(SerieGeneradoresERNC)
        %                                         datos_escenario_debug.SerieGeneradoresERNC = SerieGeneradoresERNC(:,indice_1:indice_2);
        %                                     else
        %                                         datos_escenario_debug.SerieGeneradoresERNC = [];
        %                                     end
        % 
        %                                     datos_escenario_debug.SerieConsumos = SerieConsumos(:,indice_1:indice_2);
        % 
        %                                     plan_debug = cPlanExpansion(888888889);
        %                                     plan_debug.Plan = plan_prueba.Plan;
        %                                     plan_debug.inserta_sep_original(this.pSEP.crea_copia());
        %                                     this.evalua_plan_computo_paralelo(plan_debug, nro_etapa, puntos_operacion, datos_escenario_debug, sbase);                                
        %                                     this.evalua_resultado_y_guarda_en_plan(plan_debug, nro_etapa, plan_debug.entrega_sep_actual().entrega_opf().entrega_evaluacion());
        %                                     if round(plan_debug.entrega_evaluacion(nro_etapa).CostoOperacion/1000000,2) ~= round(plan_prueba.entrega_evaluacion(nro_etapa).CostoOperacion/1000000,2)
        %                                         texto_warning = [' Error en genera_planes_bl_elimina_desplaza_paralelo primera etapa para nro plan ' num2str(nro_plan)];
        %                                         warning(texto_warning);
        %                                         texto_warning = ['Costos de operacion de plan debug en nro etapa ' num2str(nro_etapa) ' es distinto de plan actual!'];
        %                                         warning(texto_warning);
        %                                         texto_warning = ['COp. plan debug: ' num2str(round(plan_debug.entrega_evaluacion(nro_etapa).CostoOperacion/1000000,3))];
        %                                         warning(texto_warning);
        %                                         texto_warning = ['COp. plan actual: ' num2str(round(plan_prueba.entrega_evaluacion(nro_etapa).CostoOperacion/1000000,3))];
        %                                         warning(texto_warning);
        % 
        % if nivel_debug > 1
        % prot.imprime_texto('Se imprime plan debug');
        % plan_debug.imprime();
        % 
        % prot.imprime_texto('Se imprime plan actual');
        % plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
        % plan_prueba.imprime();
        % 
        % prot.imprime_texto('Formulacion OPF en documento externo');
        % plan_debug.entrega_sep_actual().entrega_opf().ingresa_nombres_problema();
        % plan_debug.entrega_sep_actual().entrega_opf().imprime_problema_optimizacion('./output/debug/dc_opf_problem_formulation_plan_debug.dat');
        % 
        % cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().ingresa_nombres_problema();
        % cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().imprime_problema_optimizacion('./output/debug/dc_opf_problem_formulation_plan_actual.dat');    
        % end
        %                                     end
        %                                 end

                                        if plan_prueba.entrega_totex_total() < totex_mejor_etapa
                                            % cambio intermedio produce mejora. Se
                                            % acepta y se guarda
                                            mejor_etapa = nro_etapa+1;
                                            totex_mejor_etapa = plan_prueba.entrega_totex_total();
                                            estructura_costos_actual_mejor_etapa = plan_prueba.entrega_estructura_costos();
                                            
                                            expansion_actual_mejor_etapa = struct;
                                            expansion_actual_mejor_etapa.Proyectos = plan_prueba.Proyectos;
                                            expansion_actual_mejor_etapa.Etapas = plan_prueba.Etapas;
                                            evaluacion_actual_mejor_etapa = plan_prueba.entrega_evaluacion();

                                            if nivel_debug > 1
                                                if nro_etapa < this.pParOpt.CantidadEtapas
                                                    texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' genera mejora. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                                    fprintf(doc_id, strcat(texto, '\n'));
                                                else
                                                    texto = ['      Desplazamiento en etapa final genera mejora. Proyectos se eliminan definitivamente. Totex final etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                                    fprintf(doc_id, strcat(texto, '\n'));
                                                end
                                            end
                                        elseif plan_valido_mejor_etapa && ~plan_prueba.es_valido(nro_etapa)
                                            if nivel_debug > 1
                                                if nro_etapa < this.pParOpt.CantidadEtapas
                                                    texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' hace que plan sea invalido. Se queda hasta aqui la evaluacion'];
                                                    fprintf(doc_id, strcat(texto, '\n'));
                                                else
                                                    texto = '      Desplazamiento en etapa final hace que plan sea invalido. Se deja hasta aqui la evaluacion';
                                                    fprintf(doc_id, strcat(texto, '\n'));
                                                end
                                            end
                                                % Plan no es válido. No se sigue evaluando
                                                % porque no tiene sentido
                                                break;
                                        else
                                            % plan no genera mejora.
                                            % Se determina mejora "potencial" que
                                            % se puede obtener al eliminar el
                                            % proyecto, con tal de ver si vale la
                                            % pena o no seguir intentando                                
                                            if nro_etapa < cantidad_etapas
                                                delta_cinv_proyectado = this.calcula_delta_cinv_elimina_proyectos(plan_prueba, nro_etapa+1, proy_seleccionado);
                                                existe_potencial = (plan_prueba.entrega_totex_total() - delta_cinv_proyectado) < totex_mejor_etapa;

                                                if nivel_debug > 1
                                                    texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' no genera mejora. ' ...
                                                         'Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total()) ...
                                                         '. Delta Cinv potencial: ' num2str(delta_cinv_proyectado) ...
                                                         '. Totex potencial: ' num2str(plan_prueba.entrega_totex_total() - delta_cinv_proyectado)];
                                                    if ~existe_potencial
                                                        texto = [texto ' (*)'];
                                                    end
                                                    fprintf(doc_id, strcat(texto, '\n'));
                                                end

                                                if ~existe_potencial
                                                    % no hay potencial de mejora. No
                                                    % intenta más
                                                    break;
                                                end 
                                            else
                                                if nivel_debug > 1
                                                    texto = ['      Desplazamiento en etapa final no genera mejora. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                                    fprintf(doc_id, strcat(texto, '\n'));
                                                end
                                            end
                                        end
                                    end

                                    % se deshace el cambio en el sep
                                    plan_prueba.Proyectos = expansion_actual.Proyectos;
                                    plan_prueba.Etapas = expansion_actual.Etapas;
                                    
                                    plan_prueba.inserta_estructura_costos(estructura_costos_actual);
                                    plan_prueba.inserta_evaluacion(evaluacion_actual);

                                    if hay_desplazamiento
                                        for nro_etapa = desde_etapa:ultima_etapa_evaluada
                                            % deshace los cambios hechos en los sep
                                            % actuales hasta la etapa correcta
                                            proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionado);
                                            cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
proyectos_en_sep = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = plan_prueba.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
error = MException('cOptMCMC:mapea_espacio_paralelo',...
'Intento fallido 3. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end
                                        end
                                    end


%debug
% plan_debug = cPlanExpansion(888888889);
% plan_debug.Plan = plan_prueba.Plan;
% plan_debug.inserta_sep_original(this.pSEP);
% for etapa_ii = 1:this.pParOpt.CantidadEtapas
% 	valido = this.evalua_plan(plan_debug, etapa_ii);
%     if ~valido
%     	error = MException('cOptMCMC:genera_planes_bl_elimina_desplaza',...
%         ['Error. Plan debug no es valido en etapa ' num2str(etapa_ii)]);
%         throw(error)
%     end
% end
% this.calcula_costos_totales(plan_debug);
% if round(plan_debug.entrega_totex_total(),2) ~= round(plan_prueba.entrega_totex_total(),2)
%     texto = 'Totex total de plan debug es distinto de totex total de plan actual!';
%     prot.imprime_texto(texto);
%     texto = ['Totex total plan debug: ' num2str(round(plan_debug.entrega_totex_total(),3))];
%     prot.imprime_texto(texto);
%     texto = ['Totex total plan actual: ' num2str(round(plan_prueba.entrega_totex_total(),3))];
%     prot.imprime_texto(texto);
%     
% 	error = MException('cOptMCMC:genera_planes_bl_elimina_desplaza','Totex total de plan debug es distinto de totex total de plan actual!');
%     throw(error)
% end


                                    if desde_etapa > 1
                                        % verifica si adelantar el proyecto produce
                                        % mejora
                                        % determina primera etapa potencial a
                                        % adelantar y proyectos de conectividad

                                        if nivel_debug > 1                                        
                                            texto = '      Se verifica si adelantar proyectos produce mejora';
                                            fprintf(doc_id, strcat(texto, '\n'));
                                        end

                                        nro_etapa = desde_etapa;
                                        cantidad_intentos_fallidos_adelanta = 0;
                                        cant_intentos_adelanta = 0;
                                        cant_intentos_seguidos_sin_mejora_global = 0;
                                        max_cant_intentos_fallidos_adelanta = this.pParOpt.CantIntentosFallidosAdelantaOptimiza;
                                        ultimo_totex_adelanta = estructura_costos_actual.TotexTotal;
                                        flag_salida = false;
                                        % si proyecto a optimizar tiene proyecto
                                        % dependiente, verifica que proyecto
                                        % dependiente esté en el plan
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionado);
                                        if proyecto.TieneDependencia
                                            [~, primera_etapa_posible]= plan_prueba.entrega_proyecto_dependiente(proyecto.entrega_indices_proyectos_dependientes(), false);
                                            if primera_etapa_posible == 0
                                                % proyecto dependiente no está en el plan. No se
                                                % hace nada
                                                flag_salida = true;
                                            end
                                        else
                                            primera_etapa_posible = 1;
                                        end
                                        hay_adelanto = false;
                                        if nro_etapa > primera_etapa_posible && ~flag_salida
                                            hay_adelanto = true;
                                        end

                                        while nro_etapa > primera_etapa_posible && ~flag_salida
                                            nro_etapa = nro_etapa - 1;
                                            cant_intentos_adelanta = cant_intentos_adelanta + 1;
                                            coper_previo_adelanta = plan_prueba.entrega_evaluacion(nro_etapa).CostoOperacion/1000000;

                                            % agrega proyectos en sep actual en
                                            % etapa actual

                                            cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                            if nro_etapa == cantidad_etapas
                                                plan_prueba.agrega_proyecto(nro_etapa, proy_seleccionado);
                                            else
                                                plan_prueba.adelanta_proyectos(proy_seleccionado, nro_etapa + 1, nro_etapa);
                                            end
proyectos_en_sep = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = plan_prueba.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
error = MException('cOptMCMC:mapea_espacio_paralelo',...
'Intento fallido 4. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end
                                            %evalua red (proyectos ya se ingresaron
                                            %al sep)
                                            cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                            this.evalua_resultado_y_guarda_en_plan(plan_prueba, nro_etapa, cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                                            this.calcula_costos_totales(plan_prueba);
                                            ultima_etapa_evaluada = nro_etapa;                                
                                            totex_actual_adelanta = plan_prueba.entrega_totex_total();
                                            delta_totex_actual_adelanta = totex_actual_adelanta-ultimo_totex_adelanta;
                                            coper_actual_adelanta = plan_prueba.entrega_evaluacion(nro_etapa).CostoOperacion/1000000;
                                            delta_coper_actual_adelanta = coper_actual_adelanta - coper_previo_adelanta;
                                            if cant_intentos_adelanta == 1
                                                delta_totex_anterior_adelanta = delta_totex_actual_adelanta;
                                                delta_coper_anterior_adelanta = delta_coper_actual_adelanta;
                                            end
                                            ultimo_totex_adelanta = totex_actual_adelanta;
                                            if totex_actual_adelanta < totex_mejor_etapa
                                                % adelantar el proyecto produce
                                                % mejora. Se guarda resultado
                                                cant_intentos_seguidos_sin_mejora_global = 0;
                                                mejor_etapa = nro_etapa;
                                                totex_mejor_etapa = plan_prueba.entrega_totex_total();
                                                estructura_costos_actual_mejor_etapa = plan_prueba.entrega_estructura_costos();
                                                expansion_actual_mejor_etapa.Proyectos = plan_prueba.Proyectos;
                                                expansion_actual_mejor_etapa.Etapas = plan_prueba.Etapas;
                                                evaluacion_actual_mejor_etapa = plan_prueba.entrega_evaluacion();
                                                if nivel_debug > 1                                        
                                                    texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ' genera mejora parcial. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                                    fprintf(doc_id, strcat(texto, '\n'));
                                                end
                                            else
                                                cant_intentos_seguidos_sin_mejora_global = cant_intentos_seguidos_sin_mejora_global + 1;

                                                % se analizan las tendencias en delta
                                                % totex y delta totex proyectados

                                                delta_cinv_proyectado = this.calcula_delta_cinv_adelanta_proyectos(plan_prueba, nro_etapa, proy_seleccionado);
                                                delta_coper_proyectado = this.estima_delta_coper_adelanta_proyectos(nro_etapa, delta_coper_actual_adelanta, delta_coper_anterior_adelanta);
                                                totex_actual_proyectado = totex_actual_adelanta + delta_cinv_proyectado + delta_coper_proyectado;
                                                if cant_intentos_seguidos_sin_mejora_global == 1
                                                    totex_anterior_proyectado= totex_actual_proyectado;
                                                end

                                                if delta_totex_actual_adelanta > 0 && ...
                                                        delta_totex_actual_adelanta > delta_totex_anterior_adelanta && ...
                                                        totex_actual_proyectado > totex_anterior_proyectado
                                                    cantidad_intentos_fallidos_adelanta = cantidad_intentos_fallidos_adelanta + 1;
                                                elseif delta_totex_actual_adelanta < 0
                                                    cantidad_intentos_fallidos_adelanta = max(0, cantidad_intentos_fallidos_adelanta -1);
                                                end

                                                totex_anterior_proyectado = totex_actual_proyectado;

                                                if nivel_debug > 1
                                                    if totex_actual_proyectado > totex_mejor_etapa
                                                        texto_adicional = '(+)';
                                                    else
                                                        texto_adicional = '(-)';
                                                    end
                                                    if abs(delta_coper_anterior_adelanta) > 0
                                                        correccion = (delta_coper_actual_adelanta - delta_coper_anterior_adelanta)/delta_coper_anterior_adelanta;
                                                        if correccion > 0.5
                                                            correccion = 0.5;
                                                        elseif correccion < -0.5
                                                            correccion = -0.5;
                                                        end
                                                    else
                                                        correccion = 0;
                                                    end

                                                    texto_base = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ...
                                                        ' no genera mejora. Totex actual etapa: ' num2str(round(totex_actual_adelanta,4))];
                                                    texto = sprintf('%-88s %-15s %-10s %-15s %-10s %-17s %-10s %-14s %-6s %-19s %-10s %-17s %-10s %-4s %-16s %-5s ', ...
                                                        texto_base, ' DtotexActual: ',num2str(round(delta_totex_actual_adelanta,4)),...
                                                        ' DCoperActual: ', num2str(round(delta_coper_actual_adelanta,4)), ...
                                                        ' DCoperAnterior: ',num2str(round(delta_coper_anterior_adelanta,4)), ...
                                                        ' FCorreccion: ', num2str(correccion,4), ...
                                                        ' DCoperProyectado: ', num2str(round(delta_coper_proyectado,4)), ...
                                                        ' DTotalEstimado: ', num2str(round(totex_actual_proyectado,4)), ...
                                                        texto_adicional, ...
                                                        ' Cant. fallida: ', num2str(cantidad_intentos_fallidos_adelanta));

                                                    fprintf(doc_id, strcat(texto, '\n'));
                                                end                       

                                            end
                                            % se verifica si hay que dejar el proceso
                                            if cantidad_intentos_fallidos_adelanta >= max_cant_intentos_fallidos_adelanta
                                                flag_salida = true;
                                            end

                                            delta_totex_anterior_adelanta = delta_totex_actual_adelanta;
                                            delta_coper_anterior_adelanta = delta_coper_actual_adelanta;
                                        end

                                        % se deshacen los cambios en el sep
                                        plan_prueba.Proyectos = expansion_actual.Proyectos;
                                        plan_prueba.Etapas = expansion_actual.Etapas;
                                        plan_prueba.inserta_estructura_costos(estructura_costos_actual);
                                        plan_prueba.inserta_evaluacion(evaluacion_actual);

                                        if hay_adelanto 
                                            for nro_etapa = ultima_etapa_evaluada:desde_etapa-1
                                                % deshace los cambios hechos en los sep
                                                % actuales hasta la etapa correcta
                                                % Ojo! orden inverso entre desplaza y
                                                % elimina proyectos!
                                                proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionado);
                                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
proyectos_en_sep = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = plan_prueba.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
error = MException('cOptMCMC:mapea_espacio_paralelo',...
'Intento fallido 5. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end
                                            end
                                        end
                                    end

                                    if mejor_etapa ~=0
                                        existe_cambio_global = true;
                                        plan_prueba.Proyectos = expansion_actual_mejor_etapa.Proyectos;
                                        plan_prueba.Etapas = expansion_actual_mejor_etapa.Etapas;
                                        plan_prueba.inserta_estructura_costos(estructura_costos_actual_mejor_etapa);
                                        plan_prueba.inserta_evaluacion(evaluacion_actual_mejor_etapa);
                                        proyectos_cambiados_prueba = [proyectos_cambiados_prueba proy_seleccionado];
                                        etapas_originales_plan_actual = [etapas_originales_plan_actual desde_etapa];
                                        etapas_nuevas_plan_prueba = [etapas_nuevas_plan_prueba mejor_etapa];

                                        if nivel_debug > 1
                                            texto = ['      Mejor etapa: ' num2str(mejor_etapa) '. Totex mejor etapa: ' num2str(plan_prueba.entrega_totex_total())];
                                            fprintf(doc_id, strcat(texto, '\n'));
                                        end
                                    else
                                        plan_prueba.Proyectos = expansion_actual.Proyectos;
                                        plan_prueba.Etapas = expansion_actual.Etapas;
                                        plan_prueba.inserta_estructura_costos(estructura_costos_actual);
                                        plan_prueba.inserta_evaluacion(evaluacion_actual);
                                        mejor_etapa = desde_etapa;
                                        if nivel_debug > 1
                                            texto = '      Cambio de etapa no produjo mejora ';
                                            fprintf(doc_id, strcat(texto, '\n'));
                                        end
                                    end
                                %lleva los cambios al sep hasta la mejor etapa

                                    if mejor_etapa > desde_etapa 
                                        for nro_etapa = desde_etapa:mejor_etapa-1
                                            proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionado);
                                            cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                        end
                                    elseif mejor_etapa ~= 0 && mejor_etapa < desde_etapa
                                        for nro_etapa = mejor_etapa:desde_etapa-1
                                                proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionado);
                                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                        end
                                    else
                                        % nada. nro_etapa se fija en
                                        % cantidad_etapas para verificación
                                        % siguiente. En teoría no es necesario ya
                                        % que no hubieron cambios
                                        nro_etapa = cantidad_etapas;
                                    end
                                    if nivel_debug > 1
                                        proyectos_en_sep = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_proyectos();
                                        texto = ['      Proyectos en sep etapa ' num2str(nro_etapa) ': '];
                                        for jj = 1:length(proyectos_en_sep)
                                            texto = [texto num2str(proyectos_en_sep(jj)) ' '];
                                        end
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
proyectos_en_sep = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = plan_prueba.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
error = MException('cOptMCMC:mapea_espacio_paralelo',...
'Intento fallido 6. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end
                                end
plan_es_consistente = this.pAdmProy.verifica_consistencia_plan(plan_prueba);
if ~plan_es_consistente
error = MException('cOptMCMC:mapea_espacio_paralelo',...
'Intento fallido 6. Plan no es consistente');
throw(error)
end

                            end
                            if nivel_debug > 1
                                fprintf(doc_id, strcat('Fin proceso de cambio de plan', '\n'));
                                texto = (['Totex original: ' num2str(pPlan.entrega_totex_total())]);
                                fprintf(doc_id, strcat(texto, '\n'));
                                texto = ['Totex prueba  : ' num2str(plan_prueba.entrega_totex_total())];
                                fprintf(doc_id, strcat(texto, '\n'));
                                texto = sprintf('%-25s %-10s %-15s %-15s', 'Proyectos seleccionados', 'Modificar', 'Etapa original', 'Nueva etapa');
                               	fprintf(doc_id, strcat(texto, '\n'));
                                for ii = 1:length(proyectos_modificar)
                                    proy_orig = proyectos_modificar(ii);
                                    etapa_orig = pPlan.entrega_etapa_proyecto(proy_orig, false);
                                    nueva_etapa = plan_prueba.entrega_etapa_proyecto(proy_orig, false);
                                    texto = sprintf('%-25s %-10s %-15s %-15s', num2str(proyectos_modificar(ii)), 'si', num2str(etapa_orig), num2str(nueva_etapa));
                                   	fprintf(doc_id, strcat(texto, '\n'));
                                end
                                for ii = 1:length(proyectos_seleccionados_original)
                                    proy_orig = proyectos_seleccionados_original(ii);
                                    etapa_orig = pPlan.entrega_etapa_proyecto(proy_orig, false);
                                    nueva_etapa = plan_prueba.entrega_etapa_proyecto(proy_orig, false);
                                    texto = sprintf('%-25s %-10s %-15s %-15s', num2str(proyectos_seleccionados_original(ii)), ' ', num2str(etapa_orig), num2str(nueva_etapa));
                                    fprintf(doc_id, strcat(texto, '\n'));
                                end
                            end

                            % determina si hay cambio o no
                            if existe_cambio_global
                                if plan_prueba.entrega_totex_total() <= pPlan.entrega_totex_total()
                                    acepta_cambio = true;
                                else
                                    f_obj_prueba = plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                                    f_obj_actual = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                                    sigma = this.pParOpt.SigmaFuncionLikelihood;
                                    prob_cambio = exp(cadenas{nro_cadena}.Beta*(-f_obj_prueba^2+f_obj_actual^2)/(2*sigma^2));

                                    if nivel_debug > 1
                                        texto = ['Probabilidad de cambio plan ' num2str(nro_cadena) ': ' num2str(prob_cambio)];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                    if rand < prob_cambio
                                        acepta_cambio = true;
                                    else
                                        acepta_cambio = false;
                                    end
                                end
                            else
                                acepta_cambio = false;
                            end
                            
                            if nivel_debug > 1
                                etapa_orig = pPlan.entrega_etapa_proyecto(id_parametro, false);
                                nueva_etapa = plan_prueba.entrega_etapa_proyecto(id_parametro, false);
                                f_obj_actual = pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                                f_obj_prueba = plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion;
                                if existe_cambio_global
                                    sigma = this.pParOpt.SigmaFuncionLikelihood;
                                    prob_cambio = exp(cadenas{nro_cadena}.Beta*(-f_obj_prueba^2+f_obj_actual^2)/(2*sigma^2));
                                else
                                    prob_cambio = 0;
                                end
                                if acepta_cambio
                                    texto_cambio = '1';
                                    cambios_tot = cantidad_cambios + 1;
                                else
                                    texto_cambio = '0';
                                    cambios_tot=  cantidad_cambios ;
                                end
                                texto_cum_cambios = [num2str(cambios_tot) '/' num2str(cantidad_calculos)];
                                texto = sprintf('%-7s %-5s %-13s %-13s %-15s %-15s %-15s %-10s %-10s', num2str(paso_actual), num2str(id_parametro), num2str(etapa_orig), num2str(nueva_etapa), num2str(f_obj_actual), num2str(f_obj_prueba), num2str(prob_cambio), texto_cambio, texto_cum_cambios);
                                fprintf(doc_id, strcat(texto, '\n'));
                            end
                            
                            if acepta_cambio
                                if nivel_debug > 1
                                    fprintf(doc_id, strcat('Se acepta cambio de plan', '\n'));
                                    texto = ['Totex actual (f objetivo): ' num2str(pPlan.entrega_totex_total()) ' (' num2str(pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')'];
                                    fprintf(doc_id, strcat(texto, '\n'));
                                    texto = ['Totex nuevo (f objetivo): ' num2str(plan_prueba.entrega_totex_total()) ' (' num2str(plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')'];
                                    fprintf(doc_id, strcat(texto, '\n'));
                                end
                                % se guarda nuevo plan en cadena
                                pPlan = plan_prueba;
                                cantidad_cambios = cantidad_cambios + 1;
                            else
                                if nivel_debug > 1
                                    texto = 'No se acepta cambio de plan';
                                    fprintf(doc_id, strcat(texto, '\n'));
                                    texto = ['Totex actual (f objetivo): ' num2str(pPlan.entrega_totex_total()) '(' num2str(pPlan.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')'];
                                    fprintf(doc_id, strcat(texto, '\n'));
                                    texto = ['Totex no aceptado (f objetivo): ' num2str(plan_prueba.entrega_totex_total()) '(' num2str(plan_prueba.entrega_totex_total()-this.NPVCostosOperacionSinRestriccion) ')'];
                                    fprintf(doc_id, strcat(texto, '\n'));
                                end

                                % se deshacen los cambios en el SEP
                                desde_etapa = min(min(etapas_originales_plan_actual), min(etapas_nuevas_plan_prueba));
                                hasta_etapa = min(cantidad_etapas, max(max(etapas_originales_plan_actual), max(etapas_nuevas_plan_prueba)));

                                for nro_etapa = desde_etapa:hasta_etapa
                                    for jj = 1:length(proyectos_cambiados_prueba)
                                        if etapas_nuevas_plan_prueba(jj) < cantidad_etapas + 1 && ...
                                           etapas_nuevas_plan_prueba(jj) < etapas_originales_plan_actual(jj) && ...
                                           nro_etapa >= etapas_nuevas_plan_prueba(jj) && ...
                                           nro_etapa < etapas_originales_plan_actual(jj) 
                                            % proyecto se retrasa, por lo que hay que eliminarlo del SEP
                                            proyecto = this.pAdmProy.entrega_proyecto(proyectos_cambiados_prueba(jj));
                                            cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                        elseif etapas_nuevas_plan_prueba(jj) > etapas_originales_plan_actual(jj) && ...
                                               nro_etapa >=  etapas_originales_plan_actual(jj) && ...
                                               nro_etapa < etapas_nuevas_plan_prueba(jj) 
                                            % proyecto se adelanta, por lo que hay que
                                            % agregarlo al SEP
                                            proyecto = this.pAdmProy.entrega_proyecto(proyectos_cambiados_prueba(jj));
                                            cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                        end
                                    end
proyectos_en_sep = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = pPlan.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
error = MException('cOptMCMC:optimiza_deterministico',...
'Intento fallido 7. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end

                                end
                            end

                            paso_actual = paso_actual +1;
                        end % pasos cadena terminados

                        % determina tasa de cambios y evalúa si es necesario
                        % modificar el sigma
                        r = cantidad_cambios/cantidad_calculos*100;
                        sigma_actual = cadenas{nro_cadena}.SigmaActual(id_parametro);
                        if r < this.pParOpt.LimiteInferiorR
                            min_sigma = this.pParOpt.SigmaMin;
                            cadenas{nro_cadena}.SigmaActual(id_parametro) = max(min_sigma, sigma_actual/this.pParOpt.FactorMultCambioSigma);
                        elseif r > this.pParOpt.LimiteSuperiorR
                            max_sigma = this.pParOpt.SigmaMax;
                            cadenas{nro_cadena}.SigmaActual(id_parametro) = min(max_sigma, sigma_actual*this.pParOpt.FactorMultCambioSigma);
                        end

                        % se deshacen los cambios hechos
                        pPlan = cadenas{nro_cadena}.plan_actual;
                        for nro_etapa = 1:cantidad_etapas
                            proyectos_en_sep = sort(cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_proyectos());
                            proyectos_en_plan = sort(pPlan.entrega_proyectos_acumulados(nro_etapa));
                            faltan_en_sep = proyectos_en_plan(~ismember(proyectos_en_plan,proyectos_en_sep))
                            sobran_en_sep = proyectos_en_sep(~ismember(proyectos_en_sep,proyectos_en_plan))
                            for jj = 1:length(faltan_en_sep)
                                proyecto = this.pAdmProy.entrega_proyecto(faltan_en_sep(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            end
                            for jj = 1:length(sobran_en_sep)
                                proyecto = this.pAdmProy.entrega_proyecto(sobran_en_sep(jj));
                                cadenas{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                            end
                        end                        

                        % modo debug. Verifica que proyectos en plan original coinciden 100% con
% proyectos en los SEP
for nro_etapa = 1:cantidad_etapas
proyectos_en_sep = cadenas{nro_cadena}.sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = pPlan.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
% prot.imprime_texto(['Proyectos en SEP en etapa ' num2str(nro_etapa) ' es distinto a proyectos en plan']);
% prot.imprime_texto(['Proyectos en SEP: ' num2str(proyectos_en_sep)]);
% prot.imprime_texto(['Proyectos en plan: ' num2str(proyectos_en_plan)]);
error = MException('cOptMCMC:optimiza_deterministico',...
'Intento fallido 8. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end
end

                    end % todos los parámetros
                end
            end
            
            % copia sigmas al resto de las cadenas
            for id_cadena = 1:cantidad_cadenas_principales
                nro_cadena = (id_cadena-1)*delta_cadenas+1;
                for j = 1:delta_cadenas %delta_cadenas = 4
                    cadenas{nro_cadena+j}.SigmaActual = cadenas{nro_cadena}.SigmaActual;
                end
            end
        end
        
        function imprime_estadisticas(this, cadenas, paso_actual, dt_iteracion, dt_acumulado)
            prot = cProtocolo.getInstance;
            cantidad_cadenas = this.pParOpt.CantidadCadenas;

            if paso_actual == 0
                %headers
                if ~isempty(this.PlanOptimo)
                    text = sprintf('%-5s %-5s %-10s %-10s %-10s %-10s %-7s %-7s %-7s %-7s %-7s %-10s %-10s %-10s', 'Paso', 'CadB','TotexB','GapTotB','FObjB','GapFObjB', 'dTIt', 'dTTot', 'rMin', 'rProm', 'rMax', 'CantGap0', 'CantGap<1', 'CantGap<5');
                else
                    text = sprintf('%-5s %-5s %-10s %-10s %-7s %-7s %-7s %-7s %-7s', 'Paso', 'CadB','TotexB','FObjB', 'dTIt', 'dTTot', 'rMin', 'rProm', 'rMax', 'CantB', 'Cant1.1', 'Cant1.15');
                end
                disp(text);
                prot.imprime_texto(text);
            else
                best_totex_all = zeros(cantidad_cadenas, 1);
                best_fobj_all = zeros(cantidad_cadenas, 1);
                r_total = zeros(cantidad_cadenas,1);
                if ~isempty(this.PlanOptimo)
                    best_gap_totex_all = zeros(cantidad_cadenas, 1);
                    best_gap_fobj_all = zeros(cantidad_cadenas, 1);                    
                end
                
                for nro_cadena = 1:cantidad_cadenas
                    r = round(sum(cadenas{nro_cadena}.CambiosEstado(paso_actual-this.pParOpt.PasoActualizacion+1:paso_actual))/this.pParOpt.PasoActualizacion*100,3);
                    r_total(nro_cadena) = r;
                    best_totex_all(nro_cadena) = cadenas{nro_cadena}.MejorTotex;
                    best_fobj_all(nro_cadena) = cadenas{nro_cadena}.MejorFObj;
                    if ~isempty(this.PlanOptimo)
                        best_gap_totex_all(nro_cadena) = round((cadenas{nro_cadena}.MejorTotex-this.TotexPlanOptimo)/this.TotexPlanOptimo*100,4);
                        best_gap_fobj_all(nro_cadena) = round((cadenas{nro_cadena}.MejorFObj-this.FObjPlanOptimo)/this.FObjPlanOptimo*100,4);
                    end
                end
                mejor_cadena = find(best_totex_all == min(best_totex_all),1,'first');
                if ~isempty(this.PlanOptimo)
                    texto = sprintf('%-5s %-5s %-10s %-10s %-10s %-10s %-7s %-7s %-7s %-7s %-7s %-10s %-10s %-10s', ...
                        num2str(paso_actual), num2str(mejor_cadena),num2str(round(min(best_totex_all),2)),num2str(round(min(best_gap_totex_all),2)),...
                        num2str(round(min(best_fobj_all),2)),num2str(round(min(best_gap_fobj_all),2)),...
                        num2str(round(dt_iteracion/60,0)), num2str(round(dt_acumulado/60,0)), ...
                        num2str(min(r_total)), num2str(mean(r_total)), num2str(max(r_total)), num2str(sum(best_gap_totex_all == 0)), num2str(sum(best_gap_totex_all<1)),num2str(sum(best_gap_totex_all<5)));
                else
                    cant_b = sum(find(best_totex_all == min(best_totex_all)));
                    cant_b_5por = sum(find(best_totex_all <= 1.05*min(best_totex_all)));
                    cant_b_10por = sum(find(best_totex_all <= 1.1*min(best_totex_all)));
                    texto_principal = sprintf('%-5s %-5s %-10s %-10s %-7s %-7s %-7s %-7s %-7s', ...
                        num2str(paso_actual), num2str(mejor_cadena),num2str(round(min(best_totex_all),2)),...
                        num2str(round(min(best_fobj_all),2)),num2str(round(dt_iteracion/60,0)), num2str(round(dt_acumulado/60,0)), ...
                        num2str(min(r_total)), num2str(mean(r_total)), num2str(max(r_total)), num2str(cant_b), num2str(cant_b_5por),num2str(cant_b_10por));
                end
                prot.imprime_texto(texto);
                disp(texto);
            end
        end
                        
        function resultados = optimiza_con_incertidumbre_sigma_unico_computo_paralelo(this)
            cantidad_cadenas = length(this.pParOpt.BetaCadenas);
            cantidad_escenarios = this.pParOpt.CantidadSimulacionesEscenarios;
            
            % la primera cadena es la que lidera
            cantidad_etapas = this.pParOpt.CantidadEtapas;
            puntos_operacion = this.pAdmSc.entrega_puntos_operacion();
            cantidad_puntos_operacion = length(puntos_operacion);
            CapacidadGeneradores = this.pAdmSc.entrega_capacidad_generadores();
            SerieGeneradoresERNC = this.pAdmSc.entrega_serie_generadores_ernc();
            SerieConsumos = this.pAdmSc.entrega_serie_consumos();
            max_cantidad_pasos = this.pParOpt.MaxCantidadPasos;
            
            resultados = cell(cantidad_cadenas,1);
            for i = 1:cantidad_cadenas
                resultados{i}.Proyectos = zeros(max_cantidad_pasos, this.pAdmProy.CantidadProyTransmision);
                resultados{i}.CambiosEstado = -1*ones(max_cantidad_pasos,1);
                resultados{i}.Totex = zeros(max_cantidad_pasos,1);
                resultados{i}.Sigma = zeros(max_cantidad_pasos,1);
                resultados{i}.IntercambioCadena = zeros(max_cantidad_pasos,1);
            end

            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();

            %inicializa cadenas
            disp('Inicializa cadenas');
            for nro_cadena = 1:cantidad_cadenas
                pPlan = this.genera_plan_expansion(nro_cadena*max_cantidad_pasos*10 + 1);

%pPlan.Plan = this.PlanOptimo.Plan;

if this.iNivelDebug > 1
    prot = cProtocolo.getInstance;
    texto = ['      Se imprime plan de expansion base en cadena ' num2str(nro_cadena)];
    prot.imprime_texto(texto);
    pPlan.imprime();
end

                % genera escenario proyectos
                [escenarios, estados_red] = this.genera_escenarios_realizacion_plan(pPlan, cantidad_etapas);
                
                % crea sep actuales por cada etapa (para mejorar
                % performance del programa) y evalúa plan base
                resultados{nro_cadena}.sep_actuales = cSistemaElectricoPotencia.empty(cantidad_etapas,0);
                
if this.iNivelDebug > 2
    prot.imprime_texto('Estados generados');
    text = sprintf('%-7s %-7s %-10s %-20s','Etapa','Estado', 'COper','Proyectos');
    prot.imprime_texto(text);
end
                for nro_etapa = 1:cantidad_etapas                    
                    nro_estado = 0;
                    while nro_estado < length(estados_red{nro_etapa}.Estado)
                        nro_estado = nro_estado + 1;
                        if nro_estado == 1
                            resultados{nro_cadena}.sep_actuales{nro_etapa} = this.pSEP.crea_copia();
                            % tiene que crear todos los proyectos que
                            % aparecen. Para el resto se crea sólo la
                            % diferencia

                            proyectos_operativos_estado = estados_red{nro_etapa}.Estado(nro_estado).Proyectos;
                            for ii = 1:length(proyectos_operativos_estado)
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_operativos_estado(ii));
                                resultados{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            end
                            %crea opf
                            datos_escenario = [];
                            datos_escenario.CapacidadGeneradores = CapacidadGeneradores(:,nro_etapa);
                            indice_1 = 1 + (nro_etapa - 1)*cantidad_puntos_operacion;
                            indice_2 = nro_etapa*cantidad_puntos_operacion;
                            if ~isempty(SerieGeneradoresERNC)
                                datos_escenario.SerieGeneradoresERNC = SerieGeneradoresERNC(:,indice_1:indice_2);
                            else
                                datos_escenario.SerieGeneradoresERNC = [];
                            end
                            datos_escenario.SerieConsumos = SerieConsumos(:,indice_1:indice_2);

                            % agrega datos de escenarios al opf
                            pOPF = cDCOPF(resultados{nro_cadena}.sep_actuales{nro_etapa});
                            pOPF.copia_parametros_optimizacion(this.pParOpt);
                            pOPF.inserta_puntos_operacion(puntos_operacion);
                            pOPF.inserta_datos_escenario(datos_escenario);
                            pOPF.inserta_etapa_datos_escenario(nro_etapa);
                            pOPF.inserta_sbase(sbase);
                            pOPF.inserta_resultados_en_sep(false);
                            pOPF.formula_problema_despacho_economico();
                            % pOPF.inserta_nivel_debug(0);                              
                        else
                            % se agregan o eliminan diferencias de
                            % proyectos con estado anterior

                            proyectos_en_sep = resultados{nro_cadena}.sep_actuales{nro_etapa}.entrega_proyectos();
                            proyectos_estado = estados_red{nro_etapa}.Estado(nro_estado).Proyectos;
                            proyectos_a_agregar = proyectos_estado(~ismember(proyectos_estado,proyectos_en_sep));
                            proyectos_a_eliminar = proyectos_en_sep(~ismember(proyectos_en_sep,proyectos_estado));
                            for ii = 1:length(proyectos_a_agregar)
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_a_agregar(ii));
                                resultados{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            end
                            for ii = 1:length(proyectos_a_eliminar)
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_a_eliminar(ii));
                                resultados{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                            end
                        end

                        resultados{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                        evaluacion = resultados{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion();
                        costo_operacion = 0;
                        costo_generacion = 0;
                        for jj = 1:this.pAdmSc.CantidadPuntosOperacion
                            representatividad =this.pAdmSc.RepresentatividadPuntosOperacion(jj);
                            costo_generacion = costo_generacion + evaluacion.CostoGeneracion(jj)*representatividad;
                            costo_operacion = costo_operacion + (evaluacion.CostoENS(jj)+evaluacion.CostoGeneracion(jj))*representatividad;
                        end
                        estados_red{nro_etapa}.Estado(nro_estado).CostosOperacion = costo_operacion;
                        estados_red{nro_etapa}.Estado(nro_estado).CostosGeneracion = costo_generacion;
                        estados_red{nro_etapa}.Estado(nro_estado).ENS = evaluacion.entrega_ens();
if this.iNivelDebug > 2
    text = sprintf('%-7s %-7s %-10s %-20s',num2str(nro_etapa),num2str(nro_estado), num2str(round(costo_operacion/1000000,3)),...
        num2str(estados_red{nro_etapa}.Estado(nro_estado).Proyectos));
    prot.imprime_texto(text);
end
                    end
                end

if this.iNivelDebug > 2
    prot.imprime_texto('Retrasos por escenario');
    for ii = 1:cantidad_escenarios
        prot.imprime_texto(['Escenario' num2str(ii)]);
        prot.imprime_matriz([escenarios{ii}.Proyectos; escenarios{ii}.RetrasoProyectos'], 'Proyectos y retrasos');
    end
    prot.imprime_texto('Evaluacion escenarios');
    text = sprintf('%-7s %-7s %-10s %-20s','Etapa','Escen.', 'Estado', 'COper','Proyectos');
    prot.imprime_texto(text);
end
                
                % guarda los resultados en los escenarios
                for nro_etapa = 1:cantidad_etapas
                    costo_operacion_totales = 0;
                    costo_generacion_totales = 0;
                    ens_totales = 0;
                    for escenario = 1:cantidad_escenarios
                        estado_base = escenarios{escenario}.IdEstadoRed(nro_etapa);
                        escenarios{escenario}.CostosOperacion(nro_etapa) = estados_red{nro_etapa}.Estado(estado_base).CostosOperacion;
                        escenarios{escenario}.CostosGeneracion(nro_etapa) = estados_red{nro_etapa}.Estado(estado_base).CostosGeneracion;
                        escenarios{escenario}.ENS(nro_etapa) = estados_red{nro_etapa}.Estado(estado_base).ENS;
                        costo_operacion_totales = costo_operacion_totales + estados_red{nro_etapa}.Estado(estado_base).CostosOperacion;
                        costo_generacion_totales = costo_generacion_totales + estados_red{nro_etapa}.Estado(estado_base).CostosGeneracion;
                        ens_totales = ens_totales + estados_red{nro_etapa}.Estado(estado_base).ENS;
if this.iNivelDebug > 2
    text = sprintf('%-7s %-7s %-10s %-20s',num2str(nro_etapa),num2str(escenario), num2str(estado_base), ...
        num2str(round(escenarios{escenario}.CostosOperacion(nro_etapa)/1000000,3)),...
        num2str(escenarios{escenario}.Proyectos(escenarios{escenario}.EstadoEtapas(:,nro_etapa)==1)));
    prot.imprime_texto(text);
end
                    end
                    costo_operacion_totales = costo_operacion_totales/cantidad_escenarios;
                    costo_generacion_totales = costo_generacion_totales/cantidad_escenarios;
                    ens_totales = ens_totales/cantidad_escenarios;
if this.iNivelDebug > 2
    text = sprintf('%-7s %-7s %-10s %-20s','','', '', ...
        num2str(round(costo_operacion_totales/1000000,3)),...
        '');
    prot.imprime_texto(text);
end
                    
                    % guarda estructura de evaluación en plan
                    pPlan.crea_estructura_e_inserta_evaluacion_etapa(nro_etapa, costo_operacion_totales, costo_generacion_totales, ens_totales);
                end
                this.calcula_costos_totales(pPlan);

                % guarda resultados cadena
                resultados{nro_cadena}.CambiosEstado(1) = 0;
                resultados{nro_cadena}.Totex(1) = pPlan.entrega_totex_total();
                resultados{nro_cadena}.plan_actual = pPlan;
                resultados{nro_cadena}.estados_red_plan_actual = estados_red;
                resultados{nro_cadena}.MejorTotex = resultados{nro_cadena}.Totex(1);
                resultados{nro_cadena}.SigmaActual = this.pParOpt.SigmaParametros;
                resultados{nro_cadena}.Sigma(1) = this.pParOpt.SigmaParametros;
                resultados{nro_cadena}.IntercambioCadena(1) = 0;
            end
            
            if this.iNivelDebug > 0
                prot = cProtocolo.getInstance;
                prot.imprime_texto('Evaluacion planes base');
                for nro_cadena = 1:cantidad_cadenas
                    prot.imprime_texto(['Plan cadena ' num2str(nro_cadena)]);
                    plan = resultados{nro_cadena}.plan_actual;
%                    plan. imprime_plan_expansion();
                    prot.imprime_texto(['Totex total plan ' num2str(plan.entrega_no()) ': ' num2str(resultados{nro_cadena}.Totex(1))]);
                end
            end
                                
            % comienza proceso de markov
            disp('Comienza proceso de markov');
            prot.imprime_texto('Comienza proceso de markov');
            if ~isempty(this.PlanOptimo)
                text = sprintf('%-10s %-5s %-10s %-10s %-10s %-7s %-7s %-7s %-15s','Cadena','Paso', 'FBP','GAP best', 'GAP act', 'r', 'Sigma', 'dTit', 'Cambio cadenas');
            else
                text = sprintf('%-10s %-5s %-10s %-7s %-7s %-7s %-15s','Cadena','Paso', 'FBP','r','Sigma', 'dTit', 'Cambio cadenas');
            end
            disp(text);
            prot.imprime_texto(text);
            
            siguiente_paso_actualizacion = 0;
            iteracion_actual = 0;
            cantidad_iteraciones = max_cantidad_pasos/this.pParOpt.PasoActualizacion;
            cambio_cadenas = '';
            
            t_inicial = toc;
            while iteracion_actual < cantidad_iteraciones
                iteracion_actual = iteracion_actual + 1;
                siguiente_paso_actualizacion = siguiente_paso_actualizacion + this.pParOpt.PasoActualizacion;
                paso_base = this.pParOpt.PasoActualizacion*(iteracion_actual-1);
                t_inicial_iteracion = toc;
                dt_cadena = zeros(cantidad_cadenas,1);
nivel_debug = 0;
                parfor nro_cadena = 1:cantidad_cadenas
                    tic
                    tinicio_cadena = toc;
                %parfor nro_cadena = 1:cantidad_cadenas
                    paso_actual = paso_base;
                    if paso_actual == 0
                        paso_actual = 1;
                    end
if nivel_debug > 1
    nombre_archivo = ['./output/debug/mcmc_', num2str(nro_cadena),'.dat'];
    doc_id = fopen(nombre_archivo, 'a');
    texto = ['Comienzo proceso cadena ' num2str(nro_cadena) ' en paso actual ' num2str(paso_actual)];
    fprintf(doc_id, strcat(texto, '\n'));
end

                    pPlan = resultados{nro_cadena}.plan_actual;
if nivel_debug > 1
    texto = 'Imprime plan actual cadena';
    fprintf(doc_id, strcat(texto, '\n'));    
    pPlan.agrega_nombre_proyectos(this.pAdmProy);
    texto = pPlan.entrega_texto_plan_expansion();
    fprintf(doc_id, strcat(texto, '\n'));
end
                    while paso_actual < siguiente_paso_actualizacion
                        
                        tinicio_paso = toc;
                        paso_actual = paso_actual +1;
                        plan_prueba = cPlanExpansion(pPlan.entrega_no() + 1);
                        plan_prueba.Proyectos = pPlan.Proyectos;
                        plan_prueba.Etapas = pPlan.Etapas;
                        plan_prueba.inserta_evaluacion(pPlan.entrega_evaluacion());
                        plan_prueba.inserta_estructura_costos(pPlan.entrega_estructura_costos());

                        existe_cambio_global = false;

                        proyectos_cambiados_prueba = [];
                        etapas_originales_plan_actual = [];
                        etapas_nuevas_plan_prueba = [];
                        % genera nuevo trial
                        [proyectos_modificar, etapas_originales, nuevas_etapas]= this.modifica_plan(plan_prueba, resultados{nro_cadena}.SigmaActual);
if nivel_debug > 1
    texto = ['      Proyectos modificados (' num2str(length(proyectos_modificar)) '):'];
    fprintf(doc_id, strcat(texto, '\n'));    
    for ii = 1:length(proyectos_modificar)
        texto = ['       ' num2str(proyectos_modificar(ii)) ' de etapa ' num2str(etapas_originales(ii)) ' a etapa ' num2str(nuevas_etapas(ii))];
        fprintf(doc_id, strcat(texto, '\n'));    
    end
end
                        % se evalua nuevo plan
                        % genera escenario proyectos plan prueba
                        [escenarios_plan_prueba, estados_red_plan_prueba] = this.genera_escenarios_realizacion_plan(plan_prueba, cantidad_etapas);

                        if ~isequal(etapas_originales, nuevas_etapas)
                            proyectos_cambiados_prueba = proyectos_modificar;
                            etapas_originales_plan_actual = etapas_originales;
                            etapas_nuevas_plan_prueba = nuevas_etapas;
                        end
                        existe_cambio_global = true;
                        % se evalua plan prueba con nuevos escenarios
                        estados_plan_actual = resultados{nro_cadena}.estados_red_plan_actual;
                        for nro_etapa = 1:cantidad_etapas
if nivel_debug > 2
    text = sprintf('%-7s %-7s %-10s %-7s %-20s','Etapa','Estado', 'Actual', 'COper','Proyectos');
    fprintf(doc_id, strcat(text, '\n'));    
end
                            % identifica estados actuales que se encuentran
                            % en estados plan prueba. Si no están, se
                            % agregan por si a futuro aparecen
                            cantidad_estados_red_prueba_originales = length(estados_red_plan_prueba{nro_etapa}.Estado);
estados_prueba_asociados = zeros(cantidad_estados_red_prueba_originales,1);

                            for estado_actual = 1:length(estados_plan_actual{nro_etapa}.Estado)
                                proy_estado_actual = sort(estados_plan_actual{nro_etapa}.Estado(estado_actual).Proyectos);
                                encontrado = false;
                                for nro_estado = 1:length(estados_red_plan_prueba{nro_etapa}.Estado)
                                    if isequal(sort(estados_red_plan_prueba{nro_etapa}.Estado(nro_estado).Proyectos), proy_estado_actual)
                                        estados_red_plan_prueba{nro_etapa}.Estado(nro_estado).CostosOperacion = estados_plan_actual{nro_etapa}.Estado(estado_actual).CostosOperacion;
                                        estados_red_plan_prueba{nro_etapa}.Estado(nro_estado).CostosGeneracion = estados_plan_actual{nro_etapa}.Estado(estado_actual).CostosGeneracion;
                                        estados_red_plan_prueba{nro_etapa}.Estado(nro_estado).ENS = estados_plan_actual{nro_etapa}.Estado(estado_actual).ENS;
                                        encontrado = true;
estados_prueba_asociados(nro_estado) = estado_actual;                                        
                                        break;
                                    end
                                end
                                if ~encontrado
                                    %agrega estado actual a estados de plan
                                    %prueba
                                    estados_red_plan_prueba{nro_etapa}.Estado(end+1) = estados_plan_actual{nro_etapa}.Estado(estado_actual);
                                end
                            end
                            
                            % calcula operacion estados faltantes
                            for nro_estado = 1:cantidad_estados_red_prueba_originales
                                if estados_red_plan_prueba{nro_etapa}.Estado(nro_estado).CostosOperacion ~= 0
if nivel_debug > 2
    text = sprintf('%-7s %-7s %-10s %-7s %-20s',num2str(nro_etapa),num2str(nro_estado), num2str(estados_prueba_asociados(nro_estado)), ...
        num2str(round(estados_red_plan_prueba{nro_etapa}.Estado(nro_estado).CostosOperacion/1000000,3)),...
        num2str(estados_red_plan_prueba{nro_etapa}.Estado(nro_estado).Proyectos));
    fprintf(doc_id, strcat(text, '\n'));    
end
                                else
                                    % evalua estado
                                    proyectos_en_sep = resultados{nro_cadena}.sep_actuales{nro_etapa}.entrega_proyectos();
                                    proyectos_estado = estados_red_plan_prueba{nro_etapa}.Estado(nro_estado).Proyectos;
                                    proyectos_a_agregar = proyectos_estado(~ismember(proyectos_estado,proyectos_en_sep));
                                    proyectos_a_eliminar = proyectos_en_sep(~ismember(proyectos_en_sep,proyectos_estado));
                                    for ii = 1:length(proyectos_a_agregar)
                                        proyecto = this.pAdmProy.entrega_proyecto(proyectos_a_agregar(ii));
                                        resultados{nro_cadena}.sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    end
                                    for ii = 1:length(proyectos_a_eliminar)
                                        proyecto = this.pAdmProy.entrega_proyecto(proyectos_a_eliminar(ii));
                                        resultados{nro_cadena}.sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    end
                                    resultados{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                    evaluacion = resultados{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion();
                                    costo_operacion = 0;
                                    costo_generacion = 0;
                                    for jj = 1:this.pAdmSc.CantidadPuntosOperacion
                                        representatividad =this.pAdmSc.RepresentatividadPuntosOperacion(jj);
                                        costo_generacion = costo_generacion + evaluacion.CostoGeneracion(jj)*representatividad;
                                        costo_operacion = costo_operacion + (evaluacion.CostoENS(jj)+evaluacion.CostoGeneracion(jj))*representatividad;
                                    end
                                    estados_red_plan_prueba{nro_etapa}.Estado(nro_estado).CostosOperacion = costo_operacion;
                                    estados_red_plan_prueba{nro_etapa}.Estado(nro_estado).CostosGeneracion = costo_generacion;
                                    estados_red_plan_prueba{nro_etapa}.Estado(nro_estado).ENS = evaluacion.entrega_ens();
if nivel_debug > 2
    text = sprintf('%-7s %-7s %-10s %-7s %-20s',num2str(nro_etapa),num2str(nro_estado), num2str(0), ...
        num2str(round(estados_red_plan_prueba{nro_etapa}.Estado(nro_estado).CostosOperacion/1000000,3)),...
        num2str(estados_red_plan_prueba{nro_etapa}.Estado(nro_estado).Proyectos));
    fprintf(doc_id, strcat(text, '\n'));    
end  
                                end
                            end
                        end


if nivel_debug > 2
    fprintf(doc_id, strcat('Retrasos por escenario', '\n'));
    for ii = 1:cantidad_escenarios
        fprintf(doc_id, strcat(['Escenario' num2str(ii)], '\n'));
        fprintf(doc_id, strcat('OPCION PARA IMPRIMIR MATRIZ AUN NO IMPLEMENTADA', '\n'));
    end
    text = sprintf('%-7s %-7s %-10s %-20s','Etapa','Escen.', 'Estado', 'COper','Proyectos');
    fprintf(doc_id, strcat(text, '\n'));
end
                
                        % guarda los resultados en los escenarios
                        for nro_etapa = 1:cantidad_etapas
                            costo_operacion_totales = 0;
                            costo_generacion_totales = 0;
                            ens_totales = 0;
                            for escenario = 1:cantidad_escenarios
                                estado_base = escenarios_plan_prueba{escenario}.IdEstadoRed(nro_etapa);
                                escenarios_plan_prueba{escenario}.CostosOperacion(nro_etapa) = estados_red_plan_prueba{nro_etapa}.Estado(estado_base).CostosOperacion;
                                escenarios_plan_prueba{escenario}.CostosGeneracion(nro_etapa) = estados_red_plan_prueba{nro_etapa}.Estado(estado_base).CostosGeneracion;
                                escenarios_plan_prueba{escenario}.ENS(nro_etapa) = estados_red_plan_prueba{nro_etapa}.Estado(estado_base).ENS;
                                costo_operacion_totales = costo_operacion_totales + estados_red_plan_prueba{nro_etapa}.Estado(estado_base).CostosOperacion;
                                costo_generacion_totales = costo_generacion_totales + estados_red_plan_prueba{nro_etapa}.Estado(estado_base).CostosGeneracion;
                                ens_totales = ens_totales + estados_red_plan_prueba{nro_etapa}.Estado(estado_base).ENS;
if nivel_debug > 2
    text = sprintf('%-7s %-7s %-10s %-20s',num2str(nro_etapa),num2str(escenario), num2str(estado_base), ...
        num2str(round(escenarios_plan_prueba{escenario}.CostosOperacion(nro_etapa)/1000000,3)),...
        num2str(escenarios_plan_prueba{escenario}.Proyectos(escenarios_plan_prueba{escenario}.EstadoEtapas(:,nro_etapa)==1)));
    fprintf(doc_id, strcat(text, '\n'));
end
                            end
                            costo_operacion_totales = costo_operacion_totales/cantidad_escenarios;
                            costo_generacion_totales = costo_generacion_totales/cantidad_escenarios;
                            ens_totales = ens_totales/cantidad_escenarios;
if nivel_debug > 2
    text = sprintf('%-7s %-7s %-10s %-20s','','', '', ...
        num2str(round(costo_operacion_totales/1000000,3)),...
        '');
    fprintf(doc_id, strcat(text, '\n'));
end
                    
                            % guarda estructura de evaluación en plan
                            plan_prueba.crea_estructura_e_inserta_evaluacion_etapa(nro_etapa, costo_operacion_totales, costo_generacion_totales, ens_totales);
                        end
                        this.calcula_costos_totales(plan_prueba);
    
if nivel_debug > 1
    texto = ['      Totex plan actual: ' num2str(pPlan.entrega_totex_total())];
    fprintf(doc_id, strcat(texto, '\n'));
    texto = ['      Totex plan prueba: ' num2str(plan_prueba.entrega_totex_total())];
    fprintf(doc_id, strcat(texto, '\n'));
    fprintf(doc_id, strcat('      Se imprime plan prueba (modificado)', '\n'));
    texto = plan_prueba.entrega_texto_plan_expansion();
    fprintf(doc_id, strcat(texto, '\n'));
end
                    
                        proyectos_optimizar_prueba = this.selecciona_proyectos_optimizar(plan_prueba, proyectos_modificar);                        

if nivel_debug > 1
    texto = ['      Proyectos seleccionados a optimizar(' num2str(length(proyectos_optimizar_prueba)) '):'];
    for ii = 1:length(proyectos_optimizar_prueba)
        texto = [texto ' ' num2str(proyectos_optimizar_prueba(ii))];
    end
    fprintf(doc_id, strcat(texto, '\n'));
    proyectos_seleccionados_original = proyectos_optimizar_prueba;
    indice_optimizar_actual = 0;
end
                        % optimiza proyectos seleccionados

                        while ~isempty(proyectos_optimizar_prueba)
                            if length(proyectos_optimizar_prueba) == 1
                                indice_seleccionado = 1;
                            else
                                indice_seleccionado = floor(rand*length(proyectos_optimizar_prueba))+1;
                            end
                            proy_seleccionado = proyectos_optimizar_prueba(indice_seleccionado);
                            proyectos_optimizar_prueba(indice_seleccionado) = [];

if nivel_debug > 1
    indice_optimizar_actual = indice_optimizar_actual + 1;
    texto = ['      Proyecto seleccionado optimizar ' num2str(indice_optimizar_actual) '/' num2str(length(proyectos_seleccionados_original)) ':' num2str(proy_seleccionado)];
    fprintf(doc_id, strcat(texto, '\n'));
    texto = [];
end                        
                            evaluacion_actual = plan_prueba.entrega_evaluacion();
                            estructura_costos_actual = plan_prueba.entrega_estructura_costos();
                            
                            expansion_actual = struct;
                            expansion_actual.Proyectos = plan_prueba.Proyectos;
                            expansion_actual.Etapas = plan_prueba.Etapas;

                            totex_mejor_etapa = plan_prueba.entrega_totex_total();
                            mejor_etapa = 0;                        

                            % modifica sep y evalua plan a partir de primera etapa cambiada
                            desde_etapa = plan_prueba.entrega_etapa_proyecto(proy_seleccionado, false); % false indica que es sin error. Si proyecto no está en el plan entrega 0
                            if desde_etapa == 0
                                desde_etapa = cantidad_etapas+1;
                            end

                            for nro_etapa = desde_etapa:cantidad_etapas
                                % desplaza proyecto
                                if nro_etapa < cantidad_etapas
                                    plan_prueba.desplaza_proyectos(proy_seleccionado, nro_etapa, nro_etapa + 1);
                                else
                                    plan_prueba.elimina_proyectos(proy_seleccionado, nro_etapa);
                                end
                                
                                % genera escenario proyectos plan prueba
                                % desplaza
                                [d_escenarios_desplaza, d_estados_red_desplaza, d_etapas] = this.genera_escenarios_desplaza_proyecto(escenarios_plan_prueba, estados_red_plan_prueba, proy_seleccionado, nro_etapa);
                                
                                % calcula operacion nuevos estados
if nivel_debug > 2
    texto = sprintf('%-7s %-7s %-5s %-7s %-20s','Etapa','Estado', 'Calc', 'COper','Proyectos');
    fprintf(doc_id, strcat(texto, '\n'));
end
                                for etapa_desplaza = nro_etapa:nro_etapa + d_etapas
                                    detapa = etapa_desplaza - nro_etapa + 1;
                                    for nro_estado = 1:length(d_estados_red_desplaza{detapa}.Estado)
                                        if d_estados_red_desplaza{detapa}.Estado(nro_estado).CostosOperacion ~= 0
if nivel_debug > 2
    texto = sprintf('%-7s %-7s %-5s %-7s %-20s',num2str(etapa_desplaza),num2str(nro_estado), 'No', ...
        num2str(round(d_estados_red_desplaza{detapa}.Estado(nro_estado).CostosOperacion/1000000,3)),...
        num2str(d_estados_red_desplaza{detapa}.Estado(nro_estado).Proyectos));
    fprintf(doc_id, strcat(texto, '\n'));
end
                                        else
                                            % evalua estado
                                            proyectos_en_sep = resultados{nro_cadena}.sep_actuales{etapa_desplaza}.entrega_proyectos();
                                            proyectos_estado = d_estados_red_desplaza{detapa}.Estado(nro_estado).Proyectos;
                                            proyectos_a_agregar = proyectos_estado(~ismember(proyectos_estado,proyectos_en_sep));
                                            proyectos_a_eliminar = proyectos_en_sep(~ismember(proyectos_en_sep,proyectos_estado));
                                            for ii = 1:length(proyectos_a_agregar)
                                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_a_agregar(ii));
                                                resultados{nro_cadena}.sep_actuales{etapa_desplaza}.agrega_proyecto(proyecto);
                                            end
                                            for ii = 1:length(proyectos_a_eliminar)
                                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_a_eliminar(ii));
                                                resultados{nro_cadena}.sep_actuales{etapa_desplaza}.elimina_proyecto(proyecto);
                                            end
                                            resultados{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                            evaluacion = resultados{nro_cadena}.sep_actuales{etapa_desplaza}.entrega_opf().entrega_evaluacion();
                                            costo_operacion = 0;
                                            costo_generacion = 0;
                                            for jj = 1:this.pAdmSc.CantidadPuntosOperacion
                                                representatividad =this.pAdmSc.RepresentatividadPuntosOperacion(jj);
                                                costo_generacion = costo_generacion + evaluacion.CostoGeneracion(jj)*representatividad;
                                                costo_operacion = costo_operacion + (evaluacion.CostoENS(jj)+evaluacion.CostoGeneracion(jj))*representatividad;
                                            end
                                            d_estados_red_desplaza{detapa}.Estado(nro_estado).CostosOperacion = costo_operacion;
                                            d_estados_red_desplaza{detapa}.Estado(nro_estado).CostosGeneracion = costo_generacion;
                                            d_estados_red_desplaza{detapa}.Estado(nro_estado).ENS = evaluacion.entrega_ens();
if nivel_debug > 2
    texto = sprintf('%-7s %-7s %-5s %-7s %-20s',num2str(etapa_desplaza),num2str(nro_estado), 'Si', ...
        num2str(round(d_estados_red_desplaza{detapa}.Estado(nro_estado).CostosOperacion/1000000,3)),...
        num2str(d_estados_red_desplaza{detapa}.Estado(nro_estado).Proyectos));
    fprintf(doc_id, strcat(texto, '\n'));
end
                                        end
                                    end
                                end
                            
                                % guarda los resultados en los escenarios
if nivel_debug > 2
    fprintf(doc_id, strcat('Retrasos por escenario', '\n'));
    for ii = 1:cantidad_escenarios
        fprintf(doc_id, strcat(['Escenario' num2str(ii)], '\n'));
        fprintf(doc_id, strcat('FUNCION PARA IMPRIMIR MATRIZ AUN NO IMPLEMENTADA', '\n'));
        
%        prot.imprime_matriz([d_escenarios_desplaza{ii}.Proyectos; d_escenarios_desplaza{ii}.RetrasoProyectos'], 'Proyectos y retrasos');
    end

    texto = sprintf('%-7s %-7s %-10s %-20s','Etapa','Escen.', 'Estado', 'COper','Proyectos');
    fprintf(doc_id, strcat(texto, '\n'));
end
                                for etapa_desplaza = nro_etapa:nro_etapa + d_etapas
                                    detapa = etapa_desplaza - nro_etapa + 1;
                                    costo_operacion_totales = 0;
                                    costo_generacion_totales = 0;
                                    ens_totales = 0;
                                    for escenario = 1:cantidad_escenarios
                                        estado_base = d_escenarios_desplaza{escenario}.IdEstadoRed(detapa);
                                        d_escenarios_desplaza{escenario}.CostosOperacion(detapa) = d_estados_red_desplaza{detapa}.Estado(estado_base).CostosOperacion;
                                        d_escenarios_desplaza{escenario}.CostosGeneracion(detapa) = d_estados_red_desplaza{detapa}.Estado(estado_base).CostosGeneracion;
                                        d_escenarios_desplaza{escenario}.ENS(detapa) = d_estados_red_desplaza{detapa}.Estado(estado_base).ENS;
                                        costo_operacion_totales = costo_operacion_totales + d_estados_red_desplaza{detapa}.Estado(estado_base).CostosOperacion;
                                        costo_generacion_totales = costo_generacion_totales + d_estados_red_desplaza{detapa}.Estado(estado_base).CostosGeneracion;
                                        ens_totales = ens_totales + d_estados_red_desplaza{detapa}.Estado(estado_base).ENS;
if nivel_debug > 2
    texto = sprintf('%-7s %-7s %-10s %-20s',num2str(etapa_desplaza),num2str(escenario), num2str(estado_base), ...
        num2str(round(d_escenarios_desplaza{escenario}.CostosOperacion(detapa)/1000000,3)),...
        num2str(d_escenarios_desplaza{escenario}.Proyectos(d_escenarios_desplaza{escenario}.EstadoEtapas(:,detapa)==1)));
    fprintf(doc_id, strcat(texto, '\n'));
end
                                    end
                                    costo_operacion_totales = costo_operacion_totales/cantidad_escenarios;
                                    costo_generacion_totales = costo_generacion_totales/cantidad_escenarios;
                                    ens_totales = ens_totales/cantidad_escenarios;
if nivel_debug > 2
    texto = sprintf('%-7s %-7s %-10s %-20s','','', '', ...
        num2str(round(costo_operacion_totales/1000000,3)),...
        '');
    fprintf(doc_id, strcat(texto, '\n'));
end                    
                                    % guarda estructura de evaluación en plan
                                    plan_prueba.crea_estructura_e_inserta_evaluacion_etapa(etapa_desplaza, costo_operacion_totales, costo_generacion_totales, ens_totales);
                                end
                                this.calcula_costos_totales(plan_prueba);

                                if plan_prueba.es_valido(nro_etapa) && plan_prueba.entrega_totex_total() < totex_mejor_etapa
                                    % cambio intermedio produce mejora. Se
                                    % acepta y se guarda
                                    mejor_etapa = nro_etapa+1;
                                    totex_mejor_etapa = plan_prueba.entrega_totex_total();
                                    estructura_costos_actual_mejor_etapa = plan_prueba.entrega_estructura_costos();
                                    
                                    expansion_actual_mejor_etapa = struct;
                                    expansion_actual_mejor_etapa.Proyectos = plan_prueba.Proyectos;
                                    expansion_actual_mejor_etapa.Etapas = plan_prueba.Etapas;
                                    evaluacion_actual_mejor_etapa = plan_prueba.entrega_evaluacion();

if nivel_debug > 1
    if nro_etapa < this.pParOpt.CantidadEtapas
        texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' genera mejora. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())];
        fprintf(doc_id, strcat(texto, '\n'));
    else
        texto = ['      Desplazamiento en etapa final genera mejora. Proyectos se eliminan definitivamente. Totex final etapa: ' num2str(plan_prueba.entrega_totex_total())];
        fprintf(doc_id, strcat(texto, '\n'));
    end
end
                                elseif ~plan_prueba.es_valido(nro_etapa)
if nivel_debug > 1
    if nro_etapa < this.pParOpt.CantidadEtapas
        texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' hace que plan sea invalido. Se queda hasta aqui la evaluacion'];
        fprintf(doc_id, strcat(texto, '\n'));
    else
        texto = '      Desplazamiento en etapa final hace que plan sea invalido. Se deja hasta aqui la evaluacion';
        fprintf(doc_id, strcat(texto, '\n'));
    end
end
                                    % Plan no es válido. No se sigue evaluando
                                    % porque no tiene sentido
                                    break;
                                else
                                    % plan es válido pero no genera mejora.
                                    % Se determina mejora "potencial" que
                                    % se puede obtener al eliminar el
                                    % proyecto, con tal de ver si vale la
                                    % pena o no seguir intentando                                
                                    if nro_etapa < cantidad_etapas
                                        delta_cinv_proyectado = this.calcula_delta_cinv_elimina_proyectos(plan_prueba, nro_etapa+1, proy_seleccionado);
                                        existe_potencial = (plan_prueba.entrega_totex_total() - delta_cinv_proyectado) < totex_mejor_etapa;
if nivel_debug > 1
    texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' no genera mejora. ' ...
             'Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total()) ...
             '. Delta Cinv potencial: ' num2str(delta_cinv_proyectado) ...
             '. Totex potencial: ' num2str(plan_prueba.entrega_totex_total() - delta_cinv_proyectado)];
    if ~existe_potencial
        texto = [texto ' (*)'];
    end
    fprintf(doc_id, strcat(texto, '\n'));
end
                                        if ~existe_potencial
                                            % no hay potencial de mejora. No
                                            % intenta más
                                            break;
                                        end 
                                    else
if nivel_debug > 1
    texto = ['      Desplazamiento en etapa final no genera mejora. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())];
    fprintf(doc_id, strcat(texto, '\n'));
end
                                    end
                                end
                            end

                            % se deshace el cambio en el plan
                            plan_prueba.Proyectos = expansion_actual.Proyectos;
                            plan_prueba.Etapas = expansion_actual.Etapas;
                            plan_prueba.inserta_estructura_costos(estructura_costos_actual);
                            plan_prueba.inserta_evaluacion(evaluacion_actual);
                                
                            % verifica si adelantar proyecto produce mejora 
                            if desde_etapa > 1
if nivel_debug > 1
    texto = '      Se verifica si adelantar proyectos produce mejora';
    fprintf(doc_id, strcat(texto, '\n'));
end

                                nro_etapa = desde_etapa;
                                cantidad_intentos_fallidos_adelanta = 0;
                                cant_intentos_adelanta = 0;
                                cant_intentos_seguidos_sin_mejora_global = 0;
                                max_cant_intentos_fallidos_adelanta = this.pParOpt.CantIntentosFallidosAdelantaOptimiza;
                                ultimo_totex_adelanta = estructura_costos_actual.TotexTotal;
                                flag_salida = false;
                                while nro_etapa > 1 && ~flag_salida
                                    nro_etapa = nro_etapa - 1;
                                    cant_intentos_adelanta = cant_intentos_adelanta + 1;
                                    coper_previo_adelanta = plan_prueba.entrega_evaluacion(nro_etapa).CostoOperacion/1000000;

                                    % agrega proyectos en sep actual en
                                    % etapa actual
                                    if nro_etapa == cantidad_etapas
                                        plan_prueba.agrega_proyecto(nro_etapa, proy_seleccionado);
                                    else
                                        plan_prueba.adelanta_proyectos(proy_seleccionado, nro_etapa + 1, nro_etapa);
                                    end
                                    % genera escenario proyectos plan prueba
                                    % desplaza
                                    %[d_escenarios_adelanta, d_estados_red_adelanta, d_etapas] = this.genera_escenarios_adelanta_proyecto(escenarios_plan_prueba, estados_red_plan_prueba, proy_seleccionado, nro_etapa);
                                    [escenarios_plan_prueba, estados_red_plan_prueba, d_etapas] = this.genera_escenarios_adelanta_proyecto(escenarios_plan_prueba, estados_red_plan_prueba, proy_seleccionado, nro_etapa);

                                    % calcula operacion nuevos estados
if nivel_debug > 2
    texto = sprintf('%-7s %-7s %-5s %-7s %-20s','Etapa','Estado', 'Calc', 'COper','Proyectos');
    fprintf(doc_id, strcat(texto, '\n'));
end
                                    for etapa_adelanta = nro_etapa:nro_etapa + d_etapas
                                        for nro_estado = 1:length(estados_red_plan_prueba{etapa_adelanta}.Estado)
                                            if estados_red_plan_prueba{etapa_adelanta}.Estado(nro_estado).CostosOperacion ~= 0
if nivel_debug > 2
    texto = sprintf('%-7s %-7s %-5s %-7s %-20s',num2str(etapa_adelanta),num2str(nro_estado), 'No', ...
        num2str(round(estados_red_plan_prueba{etapa_adelanta}.Estado(nro_estado).CostosOperacion/1000000,3)),...
        num2str(estados_red_plan_prueba{etapa_adelanta}.Estado(nro_estado).Proyectos));
    fprintf(doc_id, strcat(texto, '\n'));
end
                                            else
                                                % evalua estado
                                                proyectos_en_sep = resultados{nro_cadena}.sep_actuales{etapa_adelanta}.entrega_proyectos();
                                                proyectos_estado = estados_red_plan_prueba{etapa_adelanta}.Estado(nro_estado).Proyectos;
                                                proyectos_a_agregar = proyectos_estado(~ismember(proyectos_estado,proyectos_en_sep));
                                                proyectos_a_eliminar = proyectos_en_sep(~ismember(proyectos_en_sep,proyectos_estado));
                                                for ii = 1:length(proyectos_a_agregar)
                                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_a_agregar(ii));
                                                    resultados{nro_cadena}.sep_actuales{etapa_adelanta}.agrega_proyecto(proyecto);
                                                end
                                                for ii = 1:length(proyectos_a_eliminar)
                                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_a_eliminar(ii));
                                                    resultados{nro_cadena}.sep_actuales{etapa_adelanta}.elimina_proyecto(proyecto);
                                                end
                                                resultados{nro_cadena}.sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                                evaluacion = resultados{nro_cadena}.sep_actuales{etapa_adelanta}.entrega_opf().entrega_evaluacion();
                                                costo_operacion = 0;
                                                costo_generacion = 0;
                                                for jj = 1:this.pAdmSc.CantidadPuntosOperacion
                                                    representatividad =this.pAdmSc.RepresentatividadPuntosOperacion(jj);
                                                    costo_generacion = costo_generacion + evaluacion.CostoGeneracion(jj)*representatividad;
                                                    costo_operacion = costo_operacion + (evaluacion.CostoENS(jj)+evaluacion.CostoGeneracion(jj))*representatividad;
                                                end
                                                estados_red_plan_prueba{etapa_adelanta}.Estado(nro_estado).CostosOperacion = costo_operacion;
                                                estados_red_plan_prueba{etapa_adelanta}.Estado(nro_estado).CostosGeneracion = costo_generacion;
                                                estados_red_plan_prueba{etapa_adelanta}.Estado(nro_estado).ENS = evaluacion.entrega_ens();
if nivel_debug > 2
    texto = sprintf('%-7s %-7s %-5s %-7s %-20s',num2str(etapa_adelanta),num2str(nro_estado), 'Si', ...
        num2str(round(estados_red_plan_prueba{etapa_adelanta}.Estado(nro_estado).CostosOperacion/1000000,3)),...
        num2str(estados_red_plan_prueba{etapa_adelanta}.Estado(nro_estado).Proyectos));
    fprintf(doc_id, strcat(texto, '\n'));
end
                                            end
                                        end
                                    end
                            
                                    % guarda los resultados en los escenarios
if nivel_debug > 2
    fprintf(doc_id, strcat('Retrasos por escenario. AUN NO IMPLEMENTADO PARA PODER IMPRIMIR MATRIZ EN COMPUTO PARALELO', '\n'));
%     for ii = 1:cantidad_escenarios
%         prot.imprime_texto(['Escenario' num2str(ii)]);
%         prot.imprime_matriz([escenarios_plan_prueba{ii}.Proyectos; escenarios_plan_prueba{ii}.RetrasoProyectos'], 'Proyectos y retrasos');
%     end
    texto = sprintf('%-7s %-7s %-10s %-20s','Etapa','Escen.', 'Estado', 'COper','Proyectos');
    fprintf(doc_id, strcat(texto, '\n'));
end
                                    for etapa_adelanta = nro_etapa:nro_etapa + d_etapas
                                        detapa = etapa_adelanta - nro_etapa + 1;
                                        costo_operacion_totales = 0;
                                        costo_generacion_totales = 0;
                                        ens_totales = 0;
                                        for escenario = 1:cantidad_escenarios
                                            estado_base = escenarios_plan_prueba{escenario}.IdEstadoRed(etapa_adelanta);
                                            escenarios_plan_prueba{escenario}.CostosOperacion(etapa_adelanta) = estados_red_plan_prueba{etapa_adelanta}.Estado(estado_base).CostosOperacion;
                                            escenarios_plan_prueba{escenario}.CostosGeneracion(etapa_adelanta) = estados_red_plan_prueba{etapa_adelanta}.Estado(estado_base).CostosGeneracion;
                                            escenarios_plan_prueba{escenario}.ENS(etapa_adelanta) = estados_red_plan_prueba{etapa_adelanta}.Estado(estado_base).ENS;
                                            costo_operacion_totales = costo_operacion_totales + estados_red_plan_prueba{etapa_adelanta}.Estado(estado_base).CostosOperacion;
                                            costo_generacion_totales = costo_generacion_totales + estados_red_plan_prueba{etapa_adelanta}.Estado(estado_base).CostosGeneracion;
                                            ens_totales = ens_totales + estados_red_plan_prueba{etapa_adelanta}.Estado(estado_base).ENS;
if nivel_debug > 2
    texto = sprintf('%-7s %-7s %-10s %-20s',num2str(etapa_adelanta),num2str(escenario), num2str(estado_base), ...
        num2str(round(escenarios_plan_prueba{escenario}.CostosOperacion(etapa_adelanta)/1000000,3)),...
        num2str(escenarios_plan_prueba{escenario}.Proyectos(escenarios_plan_prueba{escenario}.EstadoEtapas(:,etapa_adelanta)==1)));
    fprintf(doc_id, strcat(texto, '\n'));
end
                                        end
                                        costo_operacion_totales = costo_operacion_totales/cantidad_escenarios;
                                        costo_generacion_totales = costo_generacion_totales/cantidad_escenarios;
                                        ens_totales = ens_totales/cantidad_escenarios;
if nivel_debug > 2
    texto = sprintf('%-7s %-7s %-10s %-20s','','', '', ...
        num2str(round(costo_operacion_totales/1000000,3)),...
        '');
    fprintf(doc_id, strcat(texto, '\n'));
end                    
                                        % guarda estructura de evaluación en plan
                                        plan_prueba.crea_estructura_e_inserta_evaluacion_etapa(etapa_adelanta, costo_operacion_totales, costo_generacion_totales, ens_totales);
                                    end
                                    this.calcula_costos_totales(plan_prueba);
if nivel_debug > 2
    fprintf(doc_id, strcat('Plan prueba actual', '\n'));
    texto = plan_prueba.entrega_texto_plan_expansion();
    fprintf(doc_id, strcat(texto, '\n'));
end                    
                                    totex_actual_adelanta = plan_prueba.entrega_totex_total();
                                    delta_totex_actual_adelanta = totex_actual_adelanta-ultimo_totex_adelanta;
                                    coper_actual_adelanta = plan_prueba.entrega_evaluacion(nro_etapa).CostoOperacion/1000000;
                                    delta_coper_actual_adelanta = coper_actual_adelanta - coper_previo_adelanta;
                                    if cant_intentos_adelanta == 1
                                        delta_totex_anterior_adelanta = delta_totex_actual_adelanta;
                                        delta_coper_anterior_adelanta = delta_coper_actual_adelanta;
                                    end
                                    ultimo_totex_adelanta = totex_actual_adelanta;
                                    if totex_actual_adelanta < totex_mejor_etapa
                                        % adelantar el proyecto produce
                                        % mejora. Se guarda resultado
                                        cant_intentos_seguidos_sin_mejora_global = 0;
                                        mejor_etapa = nro_etapa;
                                        totex_mejor_etapa = plan_prueba.entrega_totex_total();
                                        estructura_costos_actual_mejor_etapa = plan_prueba.entrega_estructura_costos();
                                        expansion_actual_mejor_etapa.Proyectos = plan_prueba.Proyectos;
                                        expansion_actual_mejor_etapa.Etapas = plan_prueba.Etapas;
                                        evaluacion_actual_mejor_etapa = plan_prueba.entrega_evaluacion();
if nivel_debug > 1
    texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ' genera mejora parcial. Totex actual etapa: ' num2str(plan_prueba.entrega_totex_total())];
    fprintf(doc_id, strcat(texto, '\n'));
end
                                    else
                                        cant_intentos_seguidos_sin_mejora_global = cant_intentos_seguidos_sin_mejora_global + 1;

                                        % se analizan las tendencias en delta
                                        % totex y delta totex proyectados

                                        delta_cinv_proyectado = this.calcula_delta_cinv_adelanta_proyectos(plan_prueba, nro_etapa, proy_seleccionado);
                                        delta_coper_proyectado = this.estima_delta_coper_adelanta_proyectos(nro_etapa, delta_coper_actual_adelanta, delta_coper_anterior_adelanta);
                                        totex_actual_proyectado = totex_actual_adelanta + delta_cinv_proyectado + delta_coper_proyectado;
                                        if cant_intentos_seguidos_sin_mejora_global == 1
                                            totex_anterior_proyectado= totex_actual_proyectado;
                                        end

                                        if delta_totex_actual_adelanta > 0 && ...
                                                delta_totex_actual_adelanta > delta_totex_anterior_adelanta && ...
                                                totex_actual_proyectado > totex_anterior_proyectado
                                            cantidad_intentos_fallidos_adelanta = cantidad_intentos_fallidos_adelanta + 1;
                                        elseif delta_totex_actual_adelanta < 0
                                            cantidad_intentos_fallidos_adelanta = max(0, cantidad_intentos_fallidos_adelanta -1);
                                        end

                                        totex_anterior_proyectado = totex_actual_proyectado;

if nivel_debug > 1
    if totex_actual_proyectado > totex_mejor_etapa
        texto_adicional = '(+)';
    else
        texto_adicional = '(-)';
    end
    if abs(delta_coper_anterior_adelanta) > 0
        correccion = (delta_coper_actual_adelanta - delta_coper_anterior_adelanta)/delta_coper_anterior_adelanta;
        if correccion > 0.5
            correccion = 0.5;
        elseif correccion < -0.5
            correccion = -0.5;
        end
    else
        correccion = 0;
    end
    
    texto_base = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ...
        ' no genera mejora. Totex actual etapa: ' num2str(round(totex_actual_adelanta,4))];
    texto = sprintf('%-88s %-15s %-10s %-15s %-10s %-17s %-10s %-14s %-6s %-19s %-10s %-17s %-10s %-4s %-16s %-5s ', ...
        texto_base, ' DtotexActual: ',num2str(round(delta_totex_actual_adelanta,4)),...
        ' DCoperActual: ', num2str(round(delta_coper_actual_adelanta,4)), ...
        ' DCoperAnterior: ',num2str(round(delta_coper_anterior_adelanta,4)), ...
        ' FCorreccion: ', num2str(correccion,4), ...
        ' DCoperProyectado: ', num2str(round(delta_coper_proyectado,4)), ...
        ' DTotalEstimado: ', num2str(round(totex_actual_proyectado,4)), ...
        texto_adicional, ...
        ' Cant. fallida: ', num2str(cantidad_intentos_fallidos_adelanta));

    fprintf(doc_id, strcat(texto, '\n'));
end                                            
                                    end
                                    % se verifica si hay que dejar el proceso
                                    if cantidad_intentos_fallidos_adelanta >= max_cant_intentos_fallidos_adelanta
                                        flag_salida = true;
                                    end

                                    delta_totex_anterior_adelanta = delta_totex_actual_adelanta;
                                    delta_coper_anterior_adelanta = delta_coper_actual_adelanta;

                                end

                                % se deshacen los cambios en el plan
                                plan_prueba.Proyectos = expansion_actual.Proyectos;
                                plan_prueba.Etapas = expansion_actual.Etapas;
                                plan_prueba.inserta_estructura_costos(estructura_costos_actual);
                                plan_prueba.inserta_evaluacion(evaluacion_actual);
                            end
                        
                            if mejor_etapa ~=0
                                existe_cambio_global = true;
                                plan_prueba.Proyectos = expansion_actual_mejor_etapa.Proyectos;
                                plan_prueba.Etapas = expansion_actual_mejor_etapa.Etapas;
                                plan_prueba.inserta_estructura_costos(estructura_costos_actual_mejor_etapa);
                                plan_prueba.inserta_evaluacion(evaluacion_actual_mejor_etapa);
                                proyectos_cambiados_prueba = [proyectos_cambiados_prueba proy_seleccionado];
                                etapas_originales_plan_actual = [etapas_originales_plan_actual desde_etapa];
                                etapas_nuevas_plan_prueba = [etapas_nuevas_plan_prueba mejor_etapa];
if nivel_debug > 1
    texto = ['      Mejor etapa: ' num2str(mejor_etapa) '. Totex mejor etapa: ' num2str(plan_prueba.entrega_totex_total())];
    fprintf(doc_id, strcat(texto, '\n'));
end
                            else
                                plan_prueba.Proyectos = expansion_actual.Proyectos;
                                plan_prueba.Etapas = expansion_actual.Etapas;
                                plan_prueba.inserta_estructura_costos(estructura_costos_actual);
                                plan_prueba.inserta_evaluacion(evaluacion_actual);
                                mejor_etapa = desde_etapa;
if nivel_debug > 1
    fprintf(doc_id, strcat('      Cambio de etapa no produjo mejora ', '\n'));    
end
                            end
                        end
if nivel_debug > 1
    fprintf(doc_id, strcat('Fin proceso de cambio de plan', '\n'));
    if ~existe_cambio_global
        fprintf(doc_id, strcat('No hubo cambio en el plan', '\n'));        
    else
    fprintf(doc_id, strcat(texto, '\n'));
        fprintf(doc_id, strcat(['Totex original: ' num2str(pPlan.entrega_totex_total())], '\n'));
        fprintf(doc_id, strcat(['Totex prueba  : ' num2str(plan_prueba.entrega_totex_total())], '\n'));
        texto = sprintf('%-25s %-10s %-15s %-15s', 'Proyectos seleccionados', 'Modificar', 'Etapa original', 'Nueva etapa');
        fprintf(doc_id, strcat(texto, '\n'));
        for ii = 1:length(proyectos_modificar)
            proy_orig = proyectos_modificar(ii);
            etapa_orig = pPlan.entrega_etapa_proyecto(proy_orig, false);
            nueva_etapa = plan_prueba.entrega_etapa_proyecto(proy_orig, false);
            texto = sprintf('%-25s %-10s %-15s %-15s', num2str(proyectos_modificar(ii)), 'si', num2str(etapa_orig), num2str(nueva_etapa));
            fprintf(doc_id, strcat(texto, '\n'));
        end
        for ii = 1:length(proyectos_seleccionados_original)
            proy_orig = proyectos_seleccionados_original(ii);
            etapa_orig = pPlan.entrega_etapa_proyecto(proy_orig, false);
            nueva_etapa = plan_prueba.entrega_etapa_proyecto(proy_orig, false);
            texto = sprintf('%-25s %-10s %-15s %-15s', num2str(proyectos_seleccionados_original(ii)), ' ', num2str(etapa_orig), num2str(nueva_etapa));
            fprintf(doc_id, strcat(texto, '\n'));
        end
    end

    if nivel_debug > 2
        fprintf(doc_id, strcat('Plan original', '\n'));
        texto = pPlan.entrega_texto_plan_expansion();
        fprintf(doc_id, strcat(texto, '\n'));

        fprintf(doc_id, strcat('Plan prueba', '\n'));
        texto = plan_prueba.entrega_texto_plan_expansion();
        fprintf(doc_id, strcat(texto, '\n'));
    end
end

                        % determina si hay cambio o no
                        if existe_cambio_global
                            if plan_prueba.entrega_totex_total() <= pPlan.entrega_totex_total()
                                acepta_cambio = true;
                            else
                                sigma = this.pParOpt.SigmaFuncionLikelihood;
                                prob_cambio = exp(cadenas{nro_cadena}.Beta*(-plan_prueba.entrega_totex_total()^2+pPlan.entrega_totex_total()^2)/(2*sigma^2));
if nivel_debug > 1
    fprintf(doc_id, strcat(['Probabilidad de cambio cadena ' num2str(nro_cadena) ': ' num2str(prob_cambio)], '\n'));
end
                                if rand < prob_cambio
                                    acepta_cambio = true;
                                else
                                    acepta_cambio = false;
                                end
                            end
                        else
                            acepta_cambio = false;
                        end

                        if acepta_cambio
if nivel_debug > 1
    fprintf(doc_id, strcat('Se acepta cambio de plan', '\n'));
    fprintf(doc_id, strcat(['Totex actual: ' num2str(pPlan.entrega_totex_total())], '\n'));
    fprintf(doc_id, strcat(['Totex nuevo : ' num2str(plan_prueba.entrega_totex_total())], '\n'));
end
                            % se guarda nuevo plan en cadena
                            pPlan = plan_prueba;
                            resultados{nro_cadena}.plan_actual = plan_prueba;
                            resultados{nro_cadena}.CambiosEstado(paso_actual) = 1;
                            resultados{nro_cadena}.Proyectos(paso_actual,:) = resultados{nro_cadena}.Proyectos(paso_actual-1,:);
                              for ii = 1:length(proyectos_cambiados_prueba)
                                  if etapas_nuevas_plan_prueba(ii) <= cantidad_etapas
                                    resultados{nro_cadena}.Proyectos(paso_actual,proyectos_cambiados_prueba(ii)) = etapas_nuevas_plan_prueba(ii);
                                  else
                                      resultados{nro_cadena}.Proyectos(paso_actual,proyectos_cambiados_prueba(ii)) = 0;
                                  end
                              end
                            resultados{nro_cadena}.Totex(paso_actual) = pPlan.entrega_totex_total();                        
                            % estadística
                            if pPlan.entrega_totex_total() < resultados{nro_cadena}.MejorTotex
                                resultados{nro_cadena}.MejorTotex = pPlan.entrega_totex_total();
                            end

                        else
if nivel_debug > 1
    fprintf(doc_id, strcat('No se acepta cambio de plan', '\n'));
    fprintf(doc_id, strcat(['Totex actual: ' num2str(pPlan.entrega_totex_total())], '\n'));
    fprintf(doc_id, strcat(['Totex no aceptado: ' num2str(plan_prueba.entrega_totex_total())], '\n'));    
end
                            resultados{nro_cadena}.CambiosEstado(paso_actual) = 0;
                            resultados{nro_cadena}.Proyectos(paso_actual,:) = resultados{nro_cadena}.Proyectos(paso_actual-1,:);
                            resultados{nro_cadena}.Totex(paso_actual) = pPlan.entrega_totex_total();

                        end
                        
if nivel_debug > 1
    fprintf(doc_id, strcat('No se puede imprimir matriz, porque aun no esta implementada', '\n'));
    fprintf(doc_id, strcat([' Totex paso anterior: ' num2str(resultados{nro_cadena}.Totex(paso_actual-1))], '\n'));
    fprintf(doc_id, strcat([' Totex paso actual  : ' num2str(resultados{nro_cadena}.Totex(paso_actual))], '\n'));
    %prot.imprime_matriz([resultados{nro_cadena}.Proyectos(paso_actual-1,:); resultados{nro_cadena}.Proyectos(paso_actual,:)], 'Matriz proyectos pasos anterior y actual');
end

                        dt_paso = toc - tinicio_paso;

if this.iNivelDebug > 1
    texto = ['Resultados paso ' num2str(paso_actual) '. Tiempo paso (s): ' num2str(dt_paso)];
    disp(texto);
    text = sprintf('%-7s %-15s %-15s %-15s %-10s %-10s %-10s','Cadena', ...
                                                        'Totex actual',...
                                                        'Totex anterior',...
                                                        'Mejor totex',...
                                                        'Gap actual', ...
                                                        'Mejor gap', ...
                                                        'Dt paso');
    disp(text);
    if paso_actual > 1
        totex_anterior = num2str(round(resultados{nro_cadena}.Totex(paso_actual-1),4));
    else
        totex_anterior = '-';
    end
    gap = round((resultados{nro_cadena}.MejorTotex-this.PlanOptimo.TotexTotal)/this.PlanOptimo.TotexTotal*100,3);
    gap_actual = round((resultados{nro_cadena}.plan_actual.entrega_totex_total()-this.PlanOptimo.TotexTotal)/this.PlanOptimo.TotexTotal*100,3);

    text = sprintf('%-7s %-15s %-15s %-15s %-10s %-10s %-10s',num2str(nro_cadena), ...
                                                         num2str(round(resultados{nro_cadena}.plan_actual.entrega_totex_total(),4)),...
                                                         totex_anterior,...
                                                         num2str(resultados{nro_cadena}.MejorTotex),...
                                                         num2str(gap_actual), ...
                                                         num2str(gap), ...
                                                         num2str(dt_paso));

    disp(text);
end

                    end % pasos cadena terminados
                    dt_cadena(nro_cadena) = toc - tinicio_cadena;
                end % todas las cadenas

                % se verifica si hay que intercambiar cadenas
                if rand<this.pParOpt.PasoActualizacion/this.pParOpt.NsIntercambioCadenas
                    % se intercambian cadenas
                    
                    cadena_inferior = floor(rand*(cantidad_cadenas-1))+1;
                    cadena_superior = cadena_inferior+1;
                    beta_inferior = this.BetaCadenas(cadena_inferior);
                    beta_superior = this.BetaCadenas(cadena_superior);
                    sigma_inferior = resultados{cadena_inferior}.SigmaActual;
                    sigma_superior = resultados{cadena_superior}.SigmaActual;
                    %beta_cadenas = [0.01 0.2575 0.505 0.7525 1];
                    % r = min(1, 
                    
                    totex_inferior = resultados{cadena_inferior}.plan_actual.entrega_totex_total();
                    totex_superior = resultados{cadena_superior}.plan_actual.entrega_totex_total();
                    prob_cambio = exp(beta_inferior*(-totex_superior^2+totex_inferior^2)/(2*sigma_inferior^2))*exp(beta_superior*(-totex_inferior^2+totex_superior^2)/(2*sigma_superior^2));
                    prob_cambio = min(1, prob_cambio);
if this.iNivelDebug > 2
    prot.imprime_texto(['Probabilidad de cambio para intercambio de cadenas ' num2str(cadena_inferior) ' y ' num2str(cadena_superior) ':' num2str(prob_cambio)] );    
end
                    
                    if rand < prob_cambio
if this.iNivelDebug > 2
    prot.imprime_texto(['Se intercambian cadenas ' num2str(cadena_inferior) ' y ' num2str(cadena_superior)]);
end
                        cambio_cadenas = [cambio_cadenas num2str(cadena_superior) ' ' ];
                        % se intercambian los planes actuales de las
                        % cadenas
                        plan_cadena_inferior = resultados{cadena_superior}.plan_actual;
                        plan_cadena_superior = resultados{cadena_inferior}.plan_actual;
                        resultados{cadena_superior}.plan_actual = plan_cadena_superior;
                        resultados{cadena_inferior}.plan_actual = plan_cadena_inferior;
                                                                        
                        % intercambia sep actuales
                        sep_actuales_inferior = resultados{cadena_superior}.sep_actuales;
                        sep_actuales_superior = resultados{cadena_inferior}.sep_actuales;
                        resultados{cadena_inferior}.sep_actuales = sep_actuales_inferior;
                        resultados{cadena_superior}.sep_actuales = sep_actuales_superior;

                        %estadísticas
                        resultados{cadena_inferior}.IntercambioCadena(siguiente_paso_actualizacion) = cadena_superior;
                        resultados{cadena_superior}.IntercambioCadena(siguiente_paso_actualizacion) = cadena_inferior;
                        
                    end
                end
                
                % actualiza parámetros
                dt_iteracion = toc - t_inicial_iteracion;
                t_acumulado = toc - t_inicial;
                prot = cProtocolo.getInstance;
                prot.imprime_texto(['Fin iteracion ' num2str(iteracion_actual) '/' num2str(cantidad_iteraciones) '. Tiempo iteracion (min): ' num2str(round(dt_iteracion/60,2)) '. Tiempo acumulado (min): ' num2str(round(t_acumulado/60,2))]);
                for nro_cadena = 1:cantidad_cadenas
                    r = sum(resultados{nro_cadena}.CambiosEstado(siguiente_paso_actualizacion-this.pParOpt.PasoActualizacion+1:siguiente_paso_actualizacion))/this.pParOpt.PasoActualizacion*100;
                    gap = round((resultados{nro_cadena}.MejorTotex-this.PlanOptimo.TotexTotal)/this.PlanOptimo.TotexTotal*100,3);
                    gap_actual = round((resultados{nro_cadena}.plan_actual.entrega_totex_total()-this.PlanOptimo.TotexTotal)/this.PlanOptimo.TotexTotal*100,3);
                    sigma_actual = resultados{nro_cadena}.SigmaActual;

                    %estadística
                    resultados{nro_cadena}.Sigma(siguiente_paso_actualizacion-this.pParOpt.PasoActualizacion+1:siguiente_paso_actualizacion) = sigma_actual;
                    
                    if ~isempty(this.PlanOptimo)
                        text = sprintf('%-10s %-5s %-10s %-10s %-10s %-7s %-7s %-7s %-15s',num2str(nro_cadena), ...
                                                                            num2str(siguiente_paso_actualizacion),...
                                                                            num2str(resultados{nro_cadena}.MejorTotex),...
                                                                            num2str(gap), ...
                                                                            num2str(gap_actual), ...
                                                                            num2str(r), ...
                                                                            num2str(sigma_actual), ...
                                                                            num2str(round(dt_cadena(nro_cadena),0)), ...
                                                                            num2str(cambio_cadenas));
                    else
                        text = sprintf('%-10s %-5s %-10s %-10s %-7s %-7s %-7s %-15s',num2str(nro_cadena), ...
                                                                      num2str(siguiente_paso_actualizacion),...
                                                                      num2str(resultados{nro_cadena}.MejorTotex),...
                                                                      num2str(resultados{nro_cadena}.plan_actual.entrega_totex_total()),...
                                                                      num2str(r), ...
                                                                      num2str(sigma_actual), ...
                                                                      num2str(round(dt_cadena(nro_cadena),0)), ...
                                                                      num2str(cambio_cadenas));
                    end
                    prot.imprime_texto(text);
                    disp(text);
                    if nro_cadena == 1 && siguiente_paso_actualizacion >= this.pParOpt.ModificaSigmaAPartirdePaso
                        if r < this.pParOpt.LimiteInferiorR
                            min_sigma = this.pParOpt.SigmaMin;
                            resultados{nro_cadena}.SigmaActual = max(min_sigma, sigma_actual/this.pParOpt.FactorMultCambioSigma);
                        elseif r > this.pParOpt.LimiteSuperiorR
                            max_sigma = this.pParOpt.SigmaMax;
                            resultados{nro_cadena}.SigmaActual = min(max_sigma, sigma_actual*this.pParOpt.FactorMultCambioSigma);
                        end
                    end
                    % Se copia sigma de la cadena principal
                    resultados{nro_cadena}.SigmaActual = resultados{1}.SigmaActual;
                end
                cambio_cadenas = '';
                dt_cadena = zeros(cantidad_cadenas,1);
            end
        end

        function [proy_ppal, proy_conectividad]= selecciona_proyectos_obligatorios(this, proy_candidatos, plan)
            % en forma aleatoria
            indice = ceil(rand*length(proy_candidatos));
            proy_ppal = proy_candidatos(indice);
            
            proy_conectividad = [];
            if proy_ppal.TieneRequisitosConectividad
                cantidad_req_conectividad = proy_ppal.entrega_cantidad_grupos_conectividad();
                for ii = 1:cantidad_req_conectividad
                    indice_proy_conect = proy_ppal.entrega_indices_grupo_proyectos_conectividad(ii);
                    if ~plan.conectividad_existe(indice_proy_conect)
                        indice_con = indice_proy_conect(ceil(rand*length(indice_proy_conect))); 
                        proy_conectividad = [proy_conectividad this.pAdmProy.ProyTransmision(indice_con)];
                    end
               end
            end
        end
        
        function plan = genera_plan_expansion(this, indice)
            plan = cPlanExpansion(indice);
            cantidad_etapas = this.pParOpt.CantidadEtapas;
            for nro_etapa = 1:cantidad_etapas
                plan.inicializa_etapa(nro_etapa);
            end
            
            %primero determina si hay que seleccionar proyectos
            %obligatorios
            cant_proy_obligatorios = length(this.pAdmProy.ProyTransmisionObligatorios);
            proyectos_restringidos = [];
            if cant_proy_obligatorios > 0
                espacio_busqueda = this.pAdmProy.entrega_indices_proyectos_obligatorios(cant_proy_obligatorios); %parte con el último grupo de proyectos obligatorios
            else
                [espacio_busqueda, primeras_etapas_posibles] = this.pAdmProy.determina_espacio_busqueda(plan, proyectos_restringidos);
            end

            cantidad_proyectos_seleccionados = 0;
            while (cant_proy_obligatorios > 0) || ~isempty(espacio_busqueda)
            	%primero calcula probabilidad relativa entre los proyectos del espacio de búsqueda de que se construyan 

                if length(espacio_busqueda) == 1
                    indice = 1;
                else
                    indice = floor(rand*length(espacio_busqueda)) + 1;
                end
                
                % TODO DEBUG inicio: 
                % Siguiente condición se puede eliminar una
                % vez que el programa esté verificado
                if isempty(indice) || indice == 0
                    error = MException('cOptMCMC:genera_plan_expansion',...
                        'Error de programacion. Indice de proyectos no existe o es cero, a pesar de que espacio de proyecto no es vacio');
                    throw(error)
                end
                % TODO DEBUG fin                

                proyecto_seleccionado = espacio_busqueda(indice);

 
                % verifica si proyecto seleccionado tiene requisitos de
                % conectividad.
                proy_conectividad = [];
                if this.pAdmProy.ProyTransmision(indice).TieneRequisitosConectividad
                    cantidad_req_conectividad = this.pAdmProy.ProyTransmision(indice).entrega_cantidad_grupos_conectividad();
                    for ii = 1:cantidad_req_conectividad
                       	indice_proy_conect = this.pAdmProy.ProyTransmision(indice).entrega_indices_grupo_proyectos_conectividad(ii);
                        if ~plan.conectividad_existe(indice_proy_conect)
                            id_proyecto_conectividad = this.selecciona_proyecto_conectividad(indice_proy_conect);
                            proy_conectividad = [proy_conectividad id_proyecto_conectividad];
                        end
                   end
                end

                proyectos_seleccionados = [proy_conectividad proyecto_seleccionado];
                if cant_proy_obligatorios > 0
                    etapa = 1;
                else
                    % primero determina si proyecto se construye o no
                    construye = round(rand, 0);
                    if construye
                        primera_etapa_posible = primeras_etapas_posibles(indice);
                        % se determina etapa de construcción para proyecto escogido
                        % se acepta posibilidad de que no se construya
                        % solo para proyectos "no obligatorios"
                        etapa = floor(rand*(this.pParOpt.CantidadEtapas)+1);

                        % verifica si etapa es válida
                        if etapa < primera_etapa_posible
                            etapa = primera_etapa_posible;
                        end
                    else
                        etapa = 0;
                    end
                end
                
                if etapa > 0
                    % agrega proyectos en primera etapa posible
                    for i = 1:length(proyectos_seleccionados)
                        plan.agrega_proyecto(etapa, proyectos_seleccionados(i));
                        cantidad_proyectos_seleccionados = cantidad_proyectos_seleccionados + 1;
                    end
                else
                    proyectos_restringidos = [proyectos_restringidos proyecto_seleccionado]; % ya se determinó que no se construye
                end
                
                cant_proy_obligatorios = cant_proy_obligatorios - 1;
                if cant_proy_obligatorios > 0
                    espacio_busqueda = this.pAdmProy.entrega_indices_proyectos_obligatorios(cant_proy_obligatorios); %parte con el último grupo de proyectos obligatorios
                else
                    [espacio_busqueda, primeras_etapas_posibles] = this.pAdmProy.determina_espacio_busqueda(plan, proyectos_restringidos);
                end
            end
            
            if this.iNivelDebug > 1
            	prot = cProtocolo.getInstance;
                texto = ['Cantidad proyectos seleccionados plan ' num2str(cantidad_proyectos_seleccionados)];
                prot.imprime_texto(texto);
                
%                if this.iNivelDebug > 2
%                    prot.imprime_texto('Se imprime plan generado');
%                    plan.agrega_nombre_proyectos(this.pAdmProy);
%                    plan.imprime_plan_expansion();
%                end
            end
        end
        
        function crea_plan_optimo(this, data)
            this.PlanOptimo = cPlanExpansion(9999999);
            [~, m] = size(data.Plan);
            for etapa = 1:this.pParOpt.CantidadEtapas
                if data.Plan(etapa,1) ~= etapa
                    error = MException('cOptMCMC:crea_plan_optimo','Error. Formato de datos es antiguo. Corregir');
                    throw(error)
                end
                this.PlanOptimo.inicializa_etapa(etapa);
                if sum(data.Plan(etapa,2:end)) > 0
                    for i = 2:m
                        if data.Plan(etapa,i) > 0
                        	indice = data.Plan(etapa,i);
                            this.PlanOptimo.agrega_proyecto(etapa, indice);
                        else
                            break
                        end
                    end
                end
            end
            this.PlanOptimo.agrega_nombre_proyectos(this.pAdmProy);
            this.PlanOptimo.inserta_sep_original(this.pSEP);
        end

        function crea_plan_evaluar(this, data)
            % data proviene de archivo .m
            this.PlanEvaluar = cPlanExpansion(9999999);
            [~, m] = size(data.PlanEvaluar);
            for etapa = 1:this.pParOpt.CantidadEtapas
                if data.PlanEvaluar(etapa,1) ~= etapa
                    error = MException('cOptMCMC:crea_plan_evaluar','Error. Formato de datos es antiguo. Corregir');
                    throw(error)
                end
                this.PlanEvaluar.inicializa_etapa(etapa);
                if sum(data.PlanEvaluar(etapa,2:end)) > 0
                    for i = 2:m
                        if data.PlanEvaluar(etapa,i) > 0
                        	indice = data.PlanEvaluar(etapa,i);
                            this.PlanEvaluar.agrega_proyecto(etapa, indice);
                        else
                            break
                        end
                    end
                end
            end
            this.PlanEvaluar.agrega_nombre_proyectos(this.pAdmProy);
            this.PlanEvaluar.inserta_sep_original(this.pSEP);
        end
        
        function crea_plan_evaluar_de_cplanexpansion(this, plan)
            % plan corresponde al plan de expansión
            this.PlanEvaluar = cPlanExpansion(9999998);
            this.PlanEvaluar.inserta_iteracion(1);
            this.PlanEvaluar.inserta_busqueda_local(false);
            this.PlanEvaluar.Proyectos = plan.Proyectos;
            this.PlanEvaluar.Etapas = plan.Etapas;
            this.PlanEvaluar.agrega_nombre_proyectos(this.pAdmProy);
            this.PlanEvaluar.inserta_sep_original(this.pSEP);            
        end
        
        function plan = entrega_plan_evaluar(this)
            plan = this.PlanEvaluar;
        end
        
        function evalua_plan_optimo(this, varargin)
            if nargin > 1
                con_detalle = varargin{1};
            end
            % por ahora sin incertidumbre!
            for etapa = 1:this.pParOpt.CantidadEtapas
                valido = this.evalua_plan(this.PlanOptimo, etapa, con_detalle);
                if ~valido
%                    error = MException('cOptMCMC:evalua_plan_optimo',...
%                        ['Error. Plan optimo no es valido en etapa ' num2str(etapa)]);
%                    throw(error)
                    texto_warning = [' Error en evalua plan optimo. Plan no es vaildo en etapa ' num2str(etapa)];
                    warning(texto_warning);
                    
                end                
            end
            this.calcula_costos_totales(this.PlanOptimo);
        end

        function evalua_plan_evaluar(this)
            for etapa = 1:this.pParOpt.CantidadEtapas
                valido = this.evalua_plan(this.PlanEvaluar, etapa);
                if ~valido
                    error = MException('cOptMCMC:evalua_plan_evaluar',...
                        ['Error. Plan a evaluar no es valido en etapa ' num2str(etapa)]);
                    throw(error)
                end                
            end
            this.calcula_costos_totales(this.PlanEvaluar);
        end
        
        function plan = entrega_plan_optimo(this)
            plan = this.PlanOptimo;
        end

        function indice_proyecto = selecciona_proyecto_conectividad(this, espacio_busqueda)
            if isempty(espacio_busqueda)
            	prot = cProtocolo.getInstance;
                texto = 'Espacio de búsqueda vacío para seleccionar proyectos de conectividad. Error de programación';
                prot.imprime_texto(texto);
            elseif length(espacio_busqueda) == 1
                indice_proyecto = espacio_busqueda;
                return
            end

            %selecciona proyecto en forma aleatoria
            indice_proyecto = espacio_busqueda(ceil(rand*length(espacio_busqueda))); 
        end        

        function [proyectos_seleccionados, etapas_originales, nuevas_etapas, nuevas_capacidades]= modifica_plan(this, plan, nro_cadena, capacidad_orig)
%disp(['Modifica plan cadena ' num2str(nro_cadena)])
            % TODO: Por ahora sólo agregar líneas nuevas. Aún no se han
            % implemetado los casos de line uprating ni baterías
            proyectos_seleccionados = [];
            etapas_originales = [];
            nuevas_etapas = [];
            cant_etapas = this.pParOpt.CantidadEtapas;
            etapa_zero = cant_etapas+1;
            if this.pParOpt.EstrategiaMCMC == 1
                % por ahora es la única estategia implementada
                dim_subset_s = this.pParOpt.DimensionSubsetS;
                
                % escoge los corredores

                candenas_posibles = [1:1:(nro_cadena-1) (nro_cadena +1):1:this.CantCadenas];
                cadenas_seleccionadas = candenas_posibles(randperm(this.CantCadenas-1,dim_subset_s));
                factor_z = normrnd(0, this.pParOpt.SigmaParametros, dim_subset_s,1);

                corr_modificar_orden = randperm(this.CantDecisionesPrimarias);
                cant_corr_modificar = this.pParOpt.CantCorredoresModificar;
                cant_corr_modificados = 0;
                for i = 1:this.CantDecisionesPrimarias
                    hubo_cambio = false;
                    corr = corr_modificar_orden(i);
                    cap_corredores = this.CapacidadDecisionesPrimariasPorCadenas{corr}(cadenas_seleccionadas,:);
                    prom_capacidades = mean(cap_corredores);
                    delta_capacidades = sum(factor_z.*(cap_corredores-prom_capacidades));
                    
                    nueva_capacidad = capacidad_orig(corr,:) + delta_capacidades;
                    etapas_nuevas_capacidades = find(delta_capacidades ~= 0,1,'first');
                    for etapa = etapas_nuevas_capacidades:cant_etapas
                        %identifica si se debe disminuir capacidad o
                        %aumentar
                        continua_siguiente_etapa = false;
                        if delta_capacidades(etapa) > 0
                            % Se debe aumentar capacidad. Se van agregando proyectos hasta "cumplir"
                            % con la capacidad adicional.
                            while delta_capacidades(etapa) > 0 && ~continua_siguiente_etapa
                                % Se verifica si es posible adelantar la entrada de un proyecto.
                                % Si no, se escoge un nuevo proyecto
                                etapa_aumento_capacidad = find(capacidad_orig(corr,:) - capacidad_orig(corr, etapa) > 0.00001 ,1,'first');
                                if ~isempty(etapa_aumento_capacidad)
                                    % adelanta proyecto
                                    id_proy_plan = plan.entrega_proyectos(etapa_aumento_capacidad);
                                    id_proy_corr = this.pAdmProy.entrega_id_proyectos_dado_id_decision(corr, id_proy_plan);
                                    if length(id_proy_corr) > 1
                                        % encuentra primer proyecto
                                        % desarrollado
                                        id_proy_corr = plan.entrega_primer_proyecto_realizado_de_grupo_y_etapa(id_proy_corr, etapa_aumento_capacidad);
                                    end                                        
                                    % adelanta proyecto y verifica
                                    % capacidad
                                    plan.adelanta_proyectos(id_proy_corr, etapa_aumento_capacidad, etapa);
                                    hubo_cambio = true;
                                    
                                    capacidad_adicional_proyecto = this.pAdmProy.entrega_proyecto(id_proy_corr).entrega_capacidad_adicional();
                                    capacidad_orig(corr, etapa:etapa_aumento_capacidad-1) = capacidad_orig(corr, etapa:etapa_aumento_capacidad-1) + capacidad_adicional_proyecto;
                                    delta_capacidades = nueva_capacidad - capacidad_orig(corr, :);
                                    proy_ya_modificado = find(proyectos_seleccionados == id_proy_corr, 1);
                                    if ~isempty(proy_ya_modificado)
                                        nuevas_etapas(proy_ya_modificado) = etapa;
                                    else
                                        proyectos_seleccionados = [proyectos_seleccionados id_proy_corr];
                                        etapas_originales = [etapas_originales etapa_aumento_capacidad];
                                        nuevas_etapas = [nuevas_etapas etapa];
                                    end
                                else
                                    % se elige nuevo proyecto
                                    id_proy_corr = this.pAdmProy.entrega_id_proyectos_primarios_por_indice_decision(corr);
                                    [proy_realizado, ~] = plan.entrega_ultimo_proyecto_realizado_de_grupo(id_proy_corr);
                                    if proy_realizado ~= 0
                                        estado_conducente = this.pAdmProy.entrega_proyecto(proy_realizado).entrega_estado_conducente();
                                        proy_candidatos = this.pAdmProy.entrega_id_proyectos_salientes_por_indice_decision_y_estado(corr, estado_conducente(1), estado_conducente(2));
                                    else
                                        estado_inicial = this.pAdmProy.entrega_estado_inicial_decision_primaria(corr);
                                        proy_candidatos = this.pAdmProy.entrega_id_proyectos_salientes_por_indice_decision_y_estado(corr, estado_inicial(1), estado_inicial(2));
                                    end
                                    if ~isempty(proy_candidatos)
                                        % elige uno al azar. Si id_proy_salientes
                                        % está vacío, entonces todos los proyectos
                                        % del corredor se realizaron
                                        % Dado que la nueva capacidad es
                                        % aleatoria y en cualquier
                                        % dirección, puede que no existan
                                        % más proyectos
                                        proy_seleccionado = proy_candidatos(ceil(rand*length(proy_candidatos)));
                                        plan.agrega_proyecto(etapa, proy_seleccionado);
                                        hubo_cambio = true;
                                        capacidad_adicional_proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionado).entrega_capacidad_adicional();
                                        capacidad_orig(corr, etapa:end) = capacidad_orig(corr, etapa:end) + capacidad_adicional_proyecto;
                                        delta_capacidades = nueva_capacidad - capacidad_orig(corr, :);
                                        
                                        proy_ya_modificado = find(proyectos_seleccionados == proy_seleccionado, 1);
                                        if ~isempty(proy_ya_modificado)
                                            nuevas_etapas(proy_ya_modificado) = etapa;
                                        else
                                            proyectos_seleccionados = [proyectos_seleccionados proy_seleccionado];
                                            etapas_originales = [etapas_originales etapa_zero];
                                            nuevas_etapas = [nuevas_etapas etapa];
                                        end
                                    else
                                        continua_siguiente_etapa = true;
                                    end
                                end
                            end
                        else
                            % se evalua disminuir la capacidad. Verifica
                            % si hay proyectos en esta etapa. No se
                            % verifican etapas anteriores ya que las
                            % capacidades coinciden
                            while delta_capacidades(etapa) < 0 && ~continua_siguiente_etapa

                                existe_aumento = false;
                                if etapa > 1
                                    % verifica primero si hubo aumento de la
                                    % capacidad en esta etapa
                                    if capacidad_orig(corr,etapa) > capacidad_orig(corr, etapa-1)
                                        existe_aumento = true;
                                    end
                                else
                                    capacidad_inicial = this.pAdmProy.entrega_capacidad_inicial_decision_primaria(corr);
                                    if capacidad_orig(corr,etapa) > capacidad_inicial
                                        existe_aumento = true;
                                    end
                                end

                                if existe_aumento
                                    id_proy_plan = plan.entrega_proyectos(etapa);
                                    id_proy_corr = this.pAdmProy.entrega_id_proyectos_dado_id_decision(corr, id_proy_plan);
                                    if length(id_proy_corr) > 1
                                        % encuentra último proyecto
                                        % desarrollado
                                        id_proy_corr = plan.entrega_ultimo_proyecto_realizado_de_grupo_y_etapa(id_proy_corr, etapa);
                                    end
                                    % retrasa entrada de proyecto. Para ello hay que verificar:
                                    % 1) última etapa posible (de acuerdo a líneas paralelas adicionales que entran después)
                                    % 2) última etapa que tiene sentido de acuerdo a delta capacidades

                                    proy_corr = this.pAdmProy.entrega_proyecto(id_proy_corr);
                                    capacidad_proyecto = proy_corr.entrega_capacidad_adicional();
                                    
                                    % Verifica si al desplazar proyecto queda aún suficiente capacidad
                                    corresponde = true;
                                    if delta_capacidades(etapa) + capacidad_proyecto > 0
                                        corresponde = false;
                                    end
                                    
                                    if corresponde
                                        capacidades_proyectadas = delta_capacidades + capacidad_proyecto;
                                        id_ultima_etapa_con_sentido = find(capacidades_proyectadas(etapa+1:end)>0 == 1,1,'first');
                                        if ~isempty(id_ultima_etapa_con_sentido)
                                            ultima_etapa_con_sentido = etapa+id_ultima_etapa_con_sentido;
                                        else
                                            ultima_etapa_con_sentido = etapa_zero;
                                        end
                                        
                                        estado_conducente = proy_corr.entrega_estado_conducente();
                                        proy_aguas_arriba = this.pAdmProy.entrega_id_proyectos_salientes_por_indice_decision_y_estado(corr, estado_conducente(1), estado_conducente(2));
                                        ultima_etapa_posible = plan.entrega_ultima_etapa_posible_modificacion_proyecto(proy_aguas_arriba, etapa+1);
                                        etapa_modificar = min(ultima_etapa_con_sentido, ultima_etapa_posible);
                                        if etapa_modificar > cant_etapas
                                            % se elimina proyecto
                                            plan.elimina_proyectos(id_proy_corr, etapa);
                                        else
                                            plan.desplaza_proyectos(id_proy_corr, etapa, etapa_modificar);
                                        end
                                        hubo_cambio= true;
                                        proy_ya_modificado = find(proyectos_seleccionados == id_proy_corr, 1);
                                        if ~isempty(proy_ya_modificado)
                                            nuevas_etapas(proy_ya_modificado) = etapa_modificar;
                                        else
                                            proyectos_seleccionados = [proyectos_seleccionados id_proy_corr];
                                            etapas_originales = [etapas_originales etapa];
                                            nuevas_etapas = [nuevas_etapas etapa_modificar];
                                        end

                                        capacidad_orig(corr, etapa:etapa_modificar-1) = capacidad_orig(corr, etapa:etapa_modificar-1) - capacidad_proyecto;
                                        delta_capacidades = nueva_capacidad - capacidad_orig(corr, :);
                                    else
                                        % Nada que hacer
                                        continua_siguiente_etapa = true;                                        
                                    end
                                else
                                    % Nada que hacer
                                    continua_siguiente_etapa = true;
                                end
                            end
                        end
                    end
                    if hubo_cambio
                        cant_corr_modificados = cant_corr_modificados + 1;
                        if cant_corr_modificados >= cant_corr_modificar
                            break;
                        end
                    end
                end
                nuevas_capacidades = capacidad_orig;
%                 etapas_originales = zeros(1,cantidad_proyectos);
%                 nuevas_etapas = zeros(1,cantidad_proyectos);
%                 etapa_cero = this.pParOpt.CantidadEtapas + 1;
%                 %sigma = this.SigmaParametrosActual;
%                 for i = 1:length(proyectos_seleccionados)
%                     etapas_originales(i) = plan.entrega_etapa_proyecto(proyectos_seleccionados(i), false); % false indica que no entrega error si el proyecto no está en el plan
%                     if etapas_originales(i) == 0
%                         etapas_originales(i) = etapa_cero;
%                     end
%                     nuevas_etapas(i) = round(normrnd(etapas_originales(i),sigma(proyectos_seleccionados(i))),0);
%                     if nuevas_etapas(i) < 1
%                         nuevas_etapas(i) = 1;
%                     elseif nuevas_etapas(i) > this.pParOpt.CantidadEtapas
%                         nuevas_etapas(i) = etapa_cero;
%                     end
%                 end
% 
%             else
%                 error = MException('cOptMCMC:modifica_plan','esta opción está obsoleta! Estrategia solo puede ser 2');
%                 throw(error)
%             end
%                 
%             % modifica plan
%             for i = 1:length(proyectos_seleccionados)
%                 % verifica que cambios sean factibles. Por ahora sin
%                 % uprating!!! Para considerar uprating hay que hacer
%                 % modificaciones
%                 % casos: 
%                 % 1. proyecto no está y se agrega 
%                 %    --> hay que verificar que proyecto dependiente está en una etapa previa
%                 %   Casos: 
%                 %       1.1. Si proyecto dependiente está en el plan, se
%                 %       agrega considerando la primera etapa posible
%                 %       1.2. Si proyecto dependiente no está en el plan, no se
%                 %       hace nada
%                 % 2. proyecto está, y se adelanta su entrada 
%                 %    --> hay que verificar que, si tiene proyecto dependiente, este se encuentra en plan antes de la "nueva etapa"
%                 % 3. proyecto está, y se retrasa su entrada
%                 %    --> hay que verificar si es proyecto dependiente de otro y
%                 %    ese "otro" entra después de la nueva etapa
%                 % 4. proyecto está y se elimina
%                 %    --> hay que verificar que proyecto se puede eliminar
%                 if etapas_originales(i) == nuevas_etapas(i)
%                     % no se hace nada.
%                 elseif etapas_originales(i) == etapa_cero && nuevas_etapas(i) ~= etapa_cero
%                     % caso 1: proyecto no está y se agrega en etapa "nueva
%                     % etapa". Hay que ver si proyecto dependiente está en
%                     % el plan
%                     if this.pAdmProy.ProyTransmision(proyectos_seleccionados(i)).TieneDependencia
%                         [~, primera_etapa_posible]= plan.entrega_proyecto_dependiente(this.pAdmProy.ProyTransmision(proyectos_seleccionados(i)).entrega_indices_proyectos_dependientes(), false);
%                         if primera_etapa_posible == 0
%                             % proyecto dependiente no está en el plan. No se
%                             % hace nada
%                             nuevas_etapas(i) = etapa_cero;
%                         else
%                             if primera_etapa_posible > nuevas_etapas(i)
%                                 nuevas_etapas(i) = primera_etapa_posible;
%                             end
%                             plan.agrega_proyecto(nuevas_etapas(i), proyectos_seleccionados(i));
%                         end
%                     else
%                         plan.agrega_proyecto(nuevas_etapas(i), proyectos_seleccionados(i));
%                     end
%                 elseif etapas_originales(i) ~= etapa_cero && nuevas_etapas(i) ~= etapa_cero && nuevas_etapas(i) < etapas_originales(i)
%                     % caso 2: proyecto se "adelanta". Hay que verificar que
%                     % proyecto dependiente se encuentre "antes" de etapa a
%                     % adelantar
%                     if this.pAdmProy.ProyTransmision(proyectos_seleccionados(i)).TieneDependencia
%                         proy_dependientes = this.pAdmProy.ProyTransmision(proyectos_seleccionados(i)).entrega_indices_proyectos_dependientes();
%                         if isempty(proy_dependientes)
%                             error = MException('cOptMCMC:modifica_plan',['Proyecto seleccionado' num2str(proyectos_seleccionados(i)) ' tiene dependencia, pero no tiene proyectos dependientes']);
%                             throw(error)
%                         end
%                         
%                         [~, primera_etapa_posible]= plan.entrega_proyecto_dependiente(proy_dependientes);
%                         if primera_etapa_posible > nuevas_etapas(i)
%                             nuevas_etapas(i) = primera_etapa_posible;
%                         end
%                         plan.adelanta_proyectos(proyectos_seleccionados(i), etapas_originales(i), nuevas_etapas(i));
%                     else
%                         plan.adelanta_proyectos(proyectos_seleccionados(i), etapas_originales(i), nuevas_etapas(i));
%                     end
%                 elseif etapas_originales(i) ~= etapa_cero && nuevas_etapas(i) ~= etapa_cero && nuevas_etapas(i) > etapas_originales(i)
%                     % caso 3: proyecto se "retrasa". Hay que verificar si es
%                     % proyecto dependiente de otro que se encuentra en
%                     % una etapa posterior. OJO que eliminé el caso de
%                     % proyectos obligatorios!!!
%                     proy_dep_aguas_arriba = this.pAdmProy.entrega_id_proyectos_salientes(this.pAdmProy.ProyTransmision(proyectos_seleccionados(i)).Elemento(end));
%                     if ~isempty(proy_dep_aguas_arriba)
%                         [~, ultima_etapa_posible]= plan.entrega_proyectos_y_etapa_de_lista(proy_dep_aguas_arriba);
%                     else
%                         ultima_etapa_posible = 0;
%                     end
%                     if ultima_etapa_posible == 0
%                         % quiere decir que ninguno de los proyectos aguas
%                         % arriba está en el plan. Se puede retrasar
%                         plan.desplaza_proyectos(proyectos_seleccionados(i), etapas_originales(i), nuevas_etapas(i));
%                     else
%                         % hay un proyecto aguas arriba en el plan. Se
%                         % modifica (eventualmente) etapa a retrasar
%                         if ultima_etapa_posible < nuevas_etapas(i)
%                             nuevas_etapas(i) = ultima_etapa_posible;
%                         end
%                         plan.desplaza_proyectos(proyectos_seleccionados(i), etapas_originales(i), nuevas_etapas(i));
%                     end 
%                 elseif etapas_originales(i) ~= etapa_cero && nuevas_etapas(i) == etapa_cero
%                     % caso 4: proyecto está y se elimina
%                     % proyecto se puede eliminar sólo si proyecto
%                     % dependiente aguas arriba no está en el plan. En caso contrario, se
%                     % ajusta la etapa de entrada a la última etapa posible
%                     proy_dep_aguas_arriba = this.pAdmProy.entrega_id_proyectos_salientes(this.pAdmProy.ProyTransmision(proyectos_seleccionados(i)).Elemento(end));
%                     if ~isempty(proy_dep_aguas_arriba)
%                         [~, ultima_etapa_posible]= plan.entrega_proyectos_y_etapa_de_lista(proy_dep_aguas_arriba);
%                     else
%                         ultima_etapa_posible = 0;
%                     end
%                     
%                     if ultima_etapa_posible == 0
%                         % proyecto se puede eliminar
%                         plan.elimina_proyectos(proyectos_seleccionados(i), etapas_originales(i));
%                     else
%                         nuevas_etapas(i) = ultima_etapa_posible;
%                         plan.desplaza_proyectos(proyectos_seleccionados(i), etapas_originales(i), nuevas_etapas(i));
%                     end
%                 end
            else
                error = MException('cOptMCMC:modifica_plan','estrategia no implementada');
                throw(error)
            end
        end
        
        function [proyectos_seleccionados, etapas_originales, nuevas_etapas] = modifica_parametro(this, plan, id_parametro, sigma)
                
            % escoge los proyectos
            proyectos_seleccionados = id_parametro;

            etapa_cero = this.pParOpt.CantidadEtapas + 1;
            etapas_originales = plan.entrega_etapa_proyecto(proyectos_seleccionados, false);
            if etapas_originales == 0
                etapas_originales = etapa_cero;
            end

            nuevas_etapas = round(normrnd(etapas_originales,sigma),0);
            if nuevas_etapas < 1
                nuevas_etapas = 1;
            elseif nuevas_etapas > this.pParOpt.CantidadEtapas
                nuevas_etapas = etapa_cero;
            end
            
            % modifica plan
            if etapas_originales == nuevas_etapas
                % no se hace nada.
            elseif etapas_originales == etapa_cero && nuevas_etapas ~= etapa_cero
                % caso 1: proyecto no está y se agrega en etapa "nueva
                % etapa". Hay que ver si proyecto dependiente está en
                % el plan
                if this.pAdmProy.ProyTransmision(proyectos_seleccionados).TieneDependencia
                    [~, primera_etapa_posible]= plan.entrega_proyecto_dependiente(this.pAdmProy.ProyTransmision(proyectos_seleccionados).entrega_indices_proyectos_dependientes(), false);
                    if primera_etapa_posible == 0
                        % proyecto dependiente no está en el plan. No se
                        % hace nada
                        nuevas_etapas = etapa_cero;
                    else
                        if primera_etapa_posible > nuevas_etapas
                            nuevas_etapas = primera_etapa_posible;
                        end
                        plan.agrega_proyecto(nuevas_etapas, proyectos_seleccionados);
                    end
                else
                    plan.agrega_proyecto(nuevas_etapas, proyectos_seleccionados);
                end
            elseif etapas_originales ~= etapa_cero && nuevas_etapas ~= etapa_cero && nuevas_etapas < etapas_originales
                % caso 2: proyecto se "adelanta". Hay que verificar que
                % proyecto dependiente se encuentre "antes" de etapa a
                % adelantar
                if this.pAdmProy.ProyTransmision(proyectos_seleccionados).TieneDependencia
                    [~, primera_etapa_posible]= plan.entrega_proyecto_dependiente(this.pAdmProy.ProyTransmision(proyectos_seleccionados).entrega_indices_proyectos_dependientes());
                    if primera_etapa_posible > nuevas_etapas
                        nuevas_etapas = primera_etapa_posible;
                    end
                    plan.adelanta_proyectos(proyectos_seleccionados, etapas_originales, nuevas_etapas);
                else
                    plan.adelanta_proyectos(proyectos_seleccionados, etapas_originales, nuevas_etapas);
                end
            elseif etapas_originales ~= etapa_cero && nuevas_etapas ~= etapa_cero && nuevas_etapas > etapas_originales
                % caso 3: proyecto se "retrasa". Hay que verificar si es
                % proyecto dependiente de otro que se encuentra en
                % una etapa posterior. OJO que eliminé el caso de
                % proyectos obligatorios!!!
                proy_dep_aguas_arriba = this.pAdmProy.entrega_id_proyectos_salientes(this.pAdmProy.ProyTransmision(proyectos_seleccionados).Elemento(end));
                if ~isempty(proy_dep_aguas_arriba)
                    [~, ultima_etapa_posible]= plan.entrega_proyectos_y_etapa_de_lista(proy_dep_aguas_arriba);
                else
                    ultima_etapa_posible = 0;
                end
                if ultima_etapa_posible == 0
                    % quiere decir que ninguno de los proyectos aguas
                    % arriba está en el plan. Se puede retrasar
                    plan.desplaza_proyectos(proyectos_seleccionados, etapas_originales, nuevas_etapas);
                else
                    % hay un proyecto aguas arriba en el plan. Se
                    % modifica (eventualmente) etapa a retrasar
                    if ultima_etapa_posible < nuevas_etapas
                        nuevas_etapas = ultima_etapa_posible;
                    end
                    plan.desplaza_proyectos(proyectos_seleccionados, etapas_originales, nuevas_etapas);
                end 
            elseif etapas_originales ~= etapa_cero && nuevas_etapas == etapa_cero
                % caso 4: proyecto está y se elimina
                % proyecto se puede eliminar sólo si proyecto
                % dependiente aguas arriba no está en el plan. En caso contrario, se
                % ajusta la etapa de entrada a la última etapa posible
                proy_dep_aguas_arriba = this.pAdmProy.entrega_id_proyectos_salientes(this.pAdmProy.ProyTransmision(proyectos_seleccionados).Elemento(end));
                if ~isempty(proy_dep_aguas_arriba)
                    [~, ultima_etapa_posible]= plan.entrega_proyectos_y_etapa_de_lista(proy_dep_aguas_arriba);
                else
                    ultima_etapa_posible = 0;
                end

                if ultima_etapa_posible == 0
                    % proyecto se puede eliminar
                    plan.elimina_proyectos(proyectos_seleccionados, etapas_originales);
                else
                    nuevas_etapas = ultima_etapa_posible;
                    plan.desplaza_proyectos(proyectos_seleccionados, etapas_originales, nuevas_etapas);
                end
            end            
        end
        
        function proyectos_seleccionados = selecciona_proyectos_optimizar_bl_simple(this, plan, proy_modificados)
            
            if this.pParOpt.EstrategiaProyectosOptimizar == 0
                % no se optimiza
                proyectos_seleccionados = [];
                return;
            end
		
																							
            if ~this.pParOpt.OptimizaCorredoresModificados
                % se eliminan proyectos en los corredores ya modificados
                corr_ya_modificados = this.pAdmProy.entrega_id_decision_de_lista(proy_modificados);
                proy_restringidos = this.pAdmProy.entrega_id_proyectos_dado_id_decision(corr_ya_modificados);
            else
                proy_restringidos = [];
            end
            
																   
            if this.pParOpt.EstrategiaProyectosOptimizar == 1
                % orden aleatorio
                proyectos_seleccionados = plan.entrega_proyectos();
                proyectos_seleccionados(ismember(proyectos_seleccionados, proy_restringidos)) = [];
                indices = randperm(length(proyectos_seleccionados));
                proyectos_seleccionados = proyectos_seleccionados(indices);
            elseif this.pParOpt.EstrategiaProyectosOptimizar == 2
                % por prioridad.
                % primera prioridad: elementos con poca carga última etapa (para eliminar)
                % luego el resto
                [espacio_busqueda, ~]= this.pAdmProy.determina_espacio_busqueda_elimina_proyectos(plan, this.pParOpt.CantidadEtapas, proy_restringidos);
                % orden aleatorio para espacio de búsqueda
                indices = randperm(length(espacio_busqueda));
                proyectos_seleccionados = espacio_busqueda(indices);
                
                % otros proyectos
                proyectos_todos = plan.entrega_proyectos();
                proyectos_todos(ismember(proyectos_todos, proy_restringidos)) = [];
                
                proyectos_faltantes = proyectos_todos(~ismember(proyectos_todos,proyectos_seleccionados));
                indices = randperm(length(proyectos_faltantes));
                proyectos_restantes = proyectos_faltantes(indices);
                proyectos_seleccionados = [proyectos_seleccionados proyectos_restantes];
            else
                error = MException('cOptMCMC:selecciona_proyectos_optimizar','estrategia no implementada');
                throw(error)
            end
            
            % limita la cantidad de proyectos 
            if this.pParOpt.MaximaCantProyectosOptimizar ~= 0
                tope = min(length(proyectos_seleccionados), this.pParOpt.MaximaCantProyectosOptimizar);
                proyectos_seleccionados = proyectos_seleccionados(1:tope);
            end
        end
        
        function proyectos_seleccionados = selecciona_proyectos_optimizar_tolerancia_sigma(this, plan, proy_restringidos)
            proyectos_seleccionados = [];
            cantidad_proyectos = this.pParOpt.CantidadProyOptimizarTolSigma;
            min_proy_en_plan = this.pParOpt.MinCantidadProyEnPlanOptimizarTolSigma;
                    
            % escoge los proyectos
            if min_proy_en_plan > 0
                proy_en_plan = plan.entrega_proyectos();
                proy_en_plan(ismember(proy_en_plan, proy_restringidos)) = [];
                if length(proy_en_plan) > min_proy_en_plan
                    indices_seleccionados = randperm(length(proy_en_plan));
                    indices_seleccionados = indices_seleccionados(1:min_proy_en_plan);
                    proyectos_seleccionados = proy_en_plan(indices_seleccionados);
                    cantidad_proyectos = cantidad_proyectos - min_proy_en_plan;
                else
                    proyectos_seleccionados = proy_en_plan;
                    cantidad_proyectos = cantidad_proyectos - length(proyectos_seleccionados);
                end
                proy_restringidos = [proy_restringidos proyectos_seleccionados];
            end

            if cantidad_proyectos > 0
                nuevos_proyectos = randperm(length(this.pAdmProy.ProyTransmision));
                nuevos_proyectos(ismember(nuevos_proyectos, proy_restringidos)) = [];
                nuevos_proyectos = nuevos_proyectos(1:cantidad_proyectos);
                proyectos_seleccionados = [proyectos_seleccionados nuevos_proyectos];
            end
        end
        
        function [escenarios, estados_red] = genera_escenarios_realizacion_plan(this, plan, cantidad_etapas)
            % estructuras
            % escenarios{i} = escenario_proyectos;
            % escenario_proyectos.Proyectos = proy_en_plan;
            % escenario_proyectos.EstadoEtapas = zeros(cantidad_proyectos_en_plan, cantidad_etapas);
            % escenario_proyectos.IdEstadoRed= zeros(1,cantidad_etapas); 
            % escenario_proyectos.CostosOperacion = zeros(1,cantidad_etapas);
            % escenario_proyectos.COperTotal = 0;
            % estados_red{nro_etapa}.Estado(id).IndiceProyectosAcumulados = zeros(id_proyectos,1);
            % estados_red{nro_etapa}.Estado(id).CostosOperacion = 0;

            cantidad_simulaciones = this.pParOpt.CantidadSimulacionesEscenarios;
            [proyectos_plan, etapas_plan]= plan.entrega_proyectos_y_etapas();
            retrasos_proyectos = zeros(length(proyectos_plan), cantidad_simulaciones);
            for i = 1:length(proyectos_plan)
                proy = this.pAdmProy.entrega_proyecto(proyectos_plan(i));
                pbb_retraso = proy.entrega_probabilidad_retraso(); % [0.5 0.3 0.2] pbbs: [sin retraso, 1 año retraso , 2 años retraso]
                suma_acumulada = cumsum(pbb_retraso);
                for j = 1:cantidad_simulaciones
                    retraso = find(rand*suma_acumulada(end)<suma_acumulada, 1, 'first') - 1;
                    retrasos_proyectos(i,j) = retraso;
                end
            end
            
            % genera escenarios
            escenarios = cell(cantidad_simulaciones, 0);
            for nro_sim = 1:cantidad_simulaciones
                escenario_proyectos = struct('Proyectos', proyectos_plan,...
											 'EstadoEtapas', zeros(length(proyectos_plan), cantidad_etapas), ...
                                             'IdEstadoRed', zeros(1,cantidad_etapas),...
                                             'CostosOperacion', zeros(1,cantidad_etapas), ...
                                             'CostosGeneracion', zeros(1,cantidad_etapas), ...
                                             'ENS', zeros(1,cantidad_etapas), ...
											 'RetrasoProyectos', zeros(length(proyectos_plan),1), ...
                                             'COperTotal', 0);
                                             
                for nro_proy = 1:length(proyectos_plan)
                    etapa = etapas_plan(nro_proy) + retrasos_proyectos(nro_proy,nro_sim);
                    escenario_proyectos.EstadoEtapas(nro_proy, etapa:cantidad_etapas)=1;
                end
				escenario_proyectos.RetrasoProyectos = retrasos_proyectos(:,nro_sim);
                escenarios{nro_sim} = escenario_proyectos;
            end
                    
            % determina estados de la red y asocia escenarios
            estados_red = cell(cantidad_etapas, 0);
            for etapa = 1:cantidad_etapas
                %escenarios{nro_sim}.IndiceProyectos = [length(proyectos_plan), cantidad_etapas]
                estados_totales = zeros(length(proyectos_plan), cantidad_simulaciones);
                for nro_sim = 1:cantidad_simulaciones
                    estados_totales(:,nro_sim) = escenarios{nro_sim}.EstadoEtapas(:,etapa);
                end
                [estados_unicos, ~, id_estados_totales] = unique(estados_totales','rows');
                estados_unicos = estados_unicos';
                [~, m] = size(estados_unicos);
                for i = 1:m
                    estados_red{etapa}.Estado(i).Proyectos = proyectos_plan(estados_unicos(:,i) == 1);
                    estados_red{etapa}.Estado(i).CostosOperacion = 0;
					estados_red{etapa}.Estado(i).CostosGeneracion = 0;
					estados_red{etapa}.Estado(i).ENS = 0;
                end
                for nro_sim = 1:length(id_estados_totales)
                    escenarios{nro_sim}.IdEstadoRed(etapa) = id_estados_totales(nro_sim);
                end
            end
        end

        function [delta_escenarios, delta_estados_red, delta_etapas] = genera_escenarios_desplaza_proyecto(this, escenarios_orig, estados_red_orig, proy_desplaza, nro_etapa_orig)
            % proyeco se desplaza desde nro_etapa_orig a nro_etapa_orig + 1
            % estructuras. Delta etapa indica cantidad de etapas
            % influenciadas
            % escenarios{i} = escenario_proyectos;
            % escenario_proyectos.Proyectos = proy_en_plan;
            % escenario_proyectos.EstadoEtapas = zeros(cantidad_proyectos_en_plan, cantidad_etapas);
            % escenario_proyectos.IdEstadoRed= zeros(1,cantidad_etapas); 
            % escenario_proyectos.CostosOperacion = zeros(1,cantidad_etapas);
            % escenario_proyectos.COperTotal = 0;
            % estados_red{nro_etapa}.Estado(id).IndiceProyectosAcumulados = zeros(id_proyectos,1);
            % estados_red{nro_etapa}.Estado(id).CostosOperacion = 0;

            cantidad_simulaciones = this.pParOpt.CantidadSimulacionesEscenarios;
            delta_escenarios = cell(cantidad_simulaciones, 0);
            maximo_retraso = 0;
            id_proy = escenarios_orig{1}.Proyectos == proy_desplaza;
            proyectos_plan = escenarios_orig{1}.Proyectos;
            for nro_sim = 1:cantidad_simulaciones
                retraso_en_escenario = escenarios_orig{nro_sim}.RetrasoProyectos(id_proy);
                if retraso_en_escenario > maximo_retraso
                    maximo_retraso = retraso_en_escenario;
                end
            end
            
            ultima_etapa = min(nro_etapa_orig + maximo_retraso,this.pParOpt.CantidadEtapas);
            delta_etapas = min(maximo_retraso, ultima_etapa-nro_etapa_orig);
            for nro_sim = 1:cantidad_simulaciones
                nuevo_escenario = struct('Proyectos', proyectos_plan,...
                                         'EstadoEtapas', escenarios_orig{nro_sim}.EstadoEtapas(:, nro_etapa_orig:nro_etapa_orig + delta_etapas), ...
                                         'IdEstadoRed', zeros(1,delta_etapas+1),...
                                         'CostosOperacion', zeros(1,delta_etapas+1), ...
                                         'CostosGeneracion', zeros(1,delta_etapas+1), ...
                                         'ENS', zeros(1,delta_etapas+1), ...
                                         'RetrasoProyectos', escenarios_orig{nro_sim}.RetrasoProyectos, ...
                                         'COperTotal', 0);

                nuevo_escenario.EstadoEtapas(id_proy, 1) = 0;
                if delta_etapas > 0
                    nuevo_escenario.EstadoEtapas(id_proy, 2:end) = escenarios_orig{nro_sim}.EstadoEtapas(id_proy, nro_etapa_orig:nro_etapa_orig+delta_etapas-1);
                end
                delta_escenarios{nro_sim} = nuevo_escenario;
            end
                        
            % Calcula nuevamente los estados de red
            cantidad_proyectos = length(proyectos_plan);
            delta_estados_red = cell(delta_etapas+1, 0);
            for d_etapa = 1:delta_etapas+1
                %escenarios{nro_sim}.IndiceProyectos = [length(proyectos_plan), cantidad_etapas]
                estados_totales = zeros(cantidad_proyectos, cantidad_simulaciones);
                for nro_sim = 1:cantidad_simulaciones
                    estados_totales(:,nro_sim) = delta_escenarios{nro_sim}.EstadoEtapas(:,d_etapa);
                end
                [estados_unicos, ~, id_estados_totales] = unique(estados_totales','rows');
                estados_unicos = estados_unicos';
                [~, m] = size(estados_unicos);
                for i = 1:m
                    delta_estados_red{d_etapa}.Estado(i).Proyectos = proyectos_plan(estados_unicos(:,i) == 1);
                    delta_estados_red{d_etapa}.Estado(i).CostosOperacion = 0;
					delta_estados_red{d_etapa}.Estado(i).CostosGeneracion = 0;
					delta_estados_red{d_etapa}.Estado(i).ENS = 0;
                end
                for nro_sim = 1:length(id_estados_totales)
                    delta_escenarios{nro_sim}.IdEstadoRed(d_etapa) = id_estados_totales(nro_sim);
                end
            end
            
            % verifica si estados red originales coincide con algunos de
            % los delta estados
            for d_etapa = 1:delta_etapas + 1
                for d_estado = 1:length(delta_estados_red{d_etapa}.Estado)
                    proy_d_estado = sort(delta_estados_red{d_etapa}.Estado(d_estado).Proyectos);
                    for estado_orig = 1:length(estados_red_orig{nro_etapa_orig + d_etapa-1}.Estado)
                        proy_estado_orig = sort(estados_red_orig{nro_etapa_orig + d_etapa-1}.Estado(estado_orig).Proyectos);
                        if isequal(proy_estado_orig, proy_d_estado)
                            delta_estados_red{d_etapa}.Estado(i).CostosOperacion = estados_red_orig{nro_etapa_orig + d_etapa-1}.Estado(estado_orig).CostosOperacion;
                            delta_estados_red{d_etapa}.Estado(i).CostosGeneracion = estados_red_orig{nro_etapa_orig + d_etapa-1}.Estado(estado_orig).CostosGeneracion;
                            delta_estados_red{d_etapa}.Estado(i).ENS = estados_red_orig{nro_etapa_orig + d_etapa-1}.Estado(estado_orig).ENS;
                            break;
                        end
                    end
                end
            end
        end

        function [escenarios, estados_red, delta_etapas] = genera_escenarios_adelanta_proyecto(this, escenarios_orig, estados_red_orig, proy_adelanta, nueva_etapa)
            % proyeco se adelanta desde nueva_etapa +1 a nueva_etapa
            % estructuras. Delta etapa indica cantidad de etapas
            % influenciadas
            % escenarios{i} = escenario_proyectos;
            % escenario_proyectos.Proyectos = proy_en_plan;
            % escenario_proyectos.EstadoEtapas = zeros(cantidad_proyectos_en_plan, cantidad_etapas);
            % escenario_proyectos.IdEstadoRed= zeros(1,cantidad_etapas); 
            % escenario_proyectos.CostosOperacion = zeros(1,cantidad_etapas);
            % escenario_proyectos.COperTotal = 0;
            % estados_red{nro_etapa}.Estado(id).IndiceProyectosAcumulados = zeros(id_proyectos,1);
            % estados_red{nro_etapa}.Estado(id).CostosOperacion = 0;

            cantidad_simulaciones = this.pParOpt.CantidadSimulacionesEscenarios;
            maximo_retraso = 0;
            escenarios = escenarios_orig;
            estados_red = estados_red_orig;
            if nueva_etapa == this.pParOpt.CantidadEtapas
                proyectos_plan = [escenarios{1}.Proyectos proy_adelanta];
                id_proy = length(proyectos_plan);
                retrasos_proyecto = zeros(1,cantidad_simulaciones);
                proy = this.pAdmProy.entrega_proyecto(proy_adelanta);
                pbb_retraso = proy.entrega_probabilidad_retraso(); % [0.5 0.3 0.2] pbbs: [sin retraso, 1 año retraso , 2 años retraso]
                suma_acumulada = cumsum(pbb_retraso);
                for j = 1:cantidad_simulaciones
                    retraso = find(rand*suma_acumulada(end)<suma_acumulada, 1, 'first') - 1;
                    retrasos_proyecto(1,j) = retraso;
                    if retraso > maximo_retraso
                        maximo_retraso = retraso;
                    end
                    escenarios{j}.Proyectos = proyectos_plan;
                    escenarios{j}.EstadoEtapas = [escenarios{j}.EstadoEtapas; zeros(1, this.pParOpt.CantidadEtapas)];
                    escenarios{j}.EstadoEtapas(id_proy, this.pParOpt.CantidadEtapas) = retraso == 0;
                    escenarios{j}.RetrasoProyectos(id_proy) = retraso;
                end
            else
                proyectos_plan = escenarios{1}.Proyectos;
                id_proy = proyectos_plan == proy_adelanta;
                for nro_sim = 1:cantidad_simulaciones
                    retraso_en_escenario = escenarios_orig{nro_sim}.RetrasoProyectos(id_proy);
                    primera_etapa_operativa = nueva_etapa + retraso_en_escenario;
                    if primera_etapa_operativa > this.pParOpt.CantidadEtapas
                        escenarios{nro_sim}.EstadoEtapas(id_proy, :) = 0;
                    else
                        escenarios{nro_sim}.EstadoEtapas(id_proy, 1:primera_etapa_operativa-1) = 0;
                        escenarios{nro_sim}.EstadoEtapas(id_proy, primera_etapa_operativa:end) = 1;
                    end
                    if retraso_en_escenario > maximo_retraso
                        maximo_retraso = retraso_en_escenario;
                    end
                end
            end
            
            ultima_etapa = min(nueva_etapa + maximo_retraso,this.pParOpt.CantidadEtapas);
            delta_etapas = min(maximo_retraso, ultima_etapa-nueva_etapa);
        
            % Calcula nuevamente los estados de red
            cantidad_proyectos = length(proyectos_plan);
            delta_estados_red = cell(delta_etapas+1, 0);
            for etapa = nueva_etapa:ultima_etapa
                d_etapa = etapa-nueva_etapa + 1;
                %escenarios{nro_sim}.IndiceProyectos = [length(proyectos_plan), cantidad_etapas]
                estados_totales = zeros(cantidad_proyectos, cantidad_simulaciones);
                for nro_sim = 1:cantidad_simulaciones
                    estados_totales(:,nro_sim) = escenarios{nro_sim}.EstadoEtapas(:,etapa);
                end
                [estados_unicos, ~, id_estados_totales] = unique(estados_totales','rows');
                estados_unicos = estados_unicos';
                [~, m] = size(estados_unicos);
                cantidad_estados_actuales = length(estados_red{etapa}.Estado);
                asociacion_delta_estados_con_actuales = zeros(m,1);
                for i = 1:m
                    delta_estados_red{d_etapa}.Estado(i).Proyectos = proyectos_plan(estados_unicos(:,i) == 1);
                    delta_estados_red{d_etapa}.Estado(i).CostosOperacion = 0;
					delta_estados_red{d_etapa}.Estado(i).CostosGeneracion = 0;
					delta_estados_red{d_etapa}.Estado(i).ENS = 0;
                    proy_ordenados_delta_estado = sort(delta_estados_red{d_etapa}.Estado(i).Proyectos);
                    % verifica si delta estado ya se encuentra en la etapa
                    % y asocia
                    estado_actual_encontrado = 0;
                    for j = 1:cantidad_estados_actuales
                        if isequal(proy_ordenados_delta_estado, sort(estados_red{etapa}.Estado(j).Proyectos))
                            estado_actual_encontrado = j;
                        end
                    end
                    if estado_actual_encontrado > 0
                        asociacion_delta_estados_con_actuales(i) = estado_actual_encontrado;
                    else
                        % agrega nuevo estado
                        %estados_red{etapa}.Estado = [estados_red{etapa}.Estado delta_estados_red{d_etapa}.Estado(i)];
                        estados_red{etapa}.Estado(end+1) = delta_estados_red{d_etapa}.Estado(i);
                        asociacion_delta_estados_con_actuales(i) = length(estados_red{etapa}.Estado);
                    end                        
                end
                for nro_sim = 1:length(id_estados_totales)
                    delta_estado_asociado = id_estados_totales(nro_sim);
                    escenarios{nro_sim}.IdEstadoRed(etapa) = asociacion_delta_estados_con_actuales(delta_estado_asociado);
                    escenarios{nro_sim}.CostosOperacion(etapa) = 0;
                    escenarios{nro_sim}.CostosGeneracion(etapa) = 0;
                    escenarios{nro_sim}.ENS(etapa) = 0;
                end
            end
        end
        
        function valido = evalua_plan(this, plan, nro_etapa, varargin)
            %varargin indica si es con detalle o no
            con_detalle = 0;
            if nargin > 3
                con_detalle = varargin{1};
            end
            % sin incertidumbre. Funcion para evaluar con incerdidumbre es:
            % evalua_plan_con_incertidumbre
            % varargin indica el nivel de debug, en caso de que se quiera

            % copia SEP base e incluye plan de expansion
            etapa_sep = plan.entrega_etapa_sep_actual();
            if etapa_sep > nro_etapa
                % en este caso hay que "volver" a generar el sep_actual
                plan.reinicia_sep_actual();
                etapa_sep = 0;
            end
            sep_plan = plan.entrega_sep_actual();
            %agrega plan de expansion
            tope = min(plan.UltimaEtapa, nro_etapa);
            for etapa = etapa_sep + 1:tope
                this.agrega_proyectos_etapa_a_sep(sep_plan, plan, etapa);
                this.agrega_elementos_proyectados_a_sep_en_etapa(sep_plan, etapa)
            end
            plan.inserta_etapa_sep_actual(nro_etapa);
            
            %sep_plan.actualiza_indices();
            pOPF = sep_plan.entrega_opf();
            if isempty(pOPF)
                if strcmp(this.pParOpt.TipoFlujoPotencia, 'DC')
                    pOPF = cDCOPF(sep_plan, this.pAdmSc, this.pParOpt);
                else
                    error = MException('cOptMCMC:evalua_plan','solo flujo DC implementado');
                    throw(error)
                end
                        
                pOPF.inserta_etapa(nro_etapa);
            else
                pOPF.actualiza_etapa(nro_etapa);
            end
            
            pOPF.inserta_nivel_debug(con_detalle);
            
            pOPF.calcula_despacho_economico();  
            
            if this.pParOpt.considera_flujos_ac()
                pFP = cFlujoPotencia(sep_plan,this.pAdmSc, this.pParOpt);
                pFP.inserta_etapa(nro_etapa);
                pFP.evalua_red();
            end
            
            this.evalua_resultado_y_guarda_en_plan(plan, nro_etapa, sep_plan.entrega_evaluacion());
            valido = plan.es_valido(nro_etapa);
        end

        function evalua_plan_con_incertidumbre(this, plan)
            % determina estados por etapa
            estados_por_etapas = this.determina_estados_por_etapa_plan(plan);
            
            % evalúa SEP para cada estado
            sep = this.pSEP.crea_copia();
            for nro_etapa = 1:this.pParOpt.CantidadEtapas
                costo_operacion_etapa = 0;
                costo_generacion_etapa = 0; 
                ens_etapa = 0;
                for nro_estado = 1:length(estados_por_etapas{nro_etapa}.Estado)
                    pbb_estado = estados_por_etapas{nro_etapa}.Estado(nro_estado).Probabilidad;

                    proyectos_en_sep = sep.entrega_proyectos();
                    proyectos_estado = estados_por_etapas{nro_etapa}.Estado(nro_estado).Proyectos;
                    proyectos_a_agregar = proyectos_estado(~ismember(proyectos_estado,proyectos_en_sep));
                    proyectos_a_eliminar = proyectos_en_sep(~ismember(proyectos_en_sep,proyectos_estado));
                    for ii = 1:length(proyectos_a_agregar)
                        proyecto = this.pAdmProy.entrega_proyecto(proyectos_a_agregar(ii));
                        sep.agrega_proyecto(proyecto);
                    end
                    for ii = 1:length(proyectos_a_eliminar)
                        proyecto = this.pAdmProy.entrega_proyecto(proyectos_a_eliminar(ii));
                        sep.elimina_proyecto(proyecto);
                    end
                    pOPF = sep.entrega_opf();
                    if isempty(pOPF)
                        if strcmp(this.pParOpt.TipoFlujoPotencia, 'DC')
                            pOPF = cDCOPF(sep, this.pAdmSc, this.pParOpt);
                            pOPF.inserta_resultados_en_sep(false);
                        else
                            error = MException('cOptMCMC:evalua_plan_con_incertidumbre','solo flujo DC implementado');
                            throw(error)
                        end

                        pOPF.inserta_nivel_debug(this.pParOpt.NivelDebugOPF);
                        pOPF.inserta_etapa(nro_etapa);
                    else
                        if pOPF.entrega_etapa() ~= nro_etapa
                            pOPF.actualiza_etapa(nro_etapa);
                        end
                    end

                    pOPF.calcula_despacho_economico();
                    evaluacion = pOPF.entrega_evaluacion();
                    costo_operacion = 0;
                    costo_generacion = 0;
                    for jj = 1:this.pAdmSc.CantidadPuntosOperacion
                        representatividad =this.pAdmSc.RepresentatividadPuntosOperacion(jj);
                        costo_generacion = costo_generacion + evaluacion.CostoGeneracion(jj)*representatividad;
                        costo_operacion = costo_operacion + (evaluacion.CostoENS(jj)+evaluacion.CostoGeneracion(jj))*representatividad;
                    end
                    estados_por_etapas{nro_etapa}.Estado(nro_estado).CostosOperacion = costo_operacion;
                    estados_por_etapas{nro_etapa}.Estado(nro_estado).CostosGeneracion = costo_generacion;
                    estados_por_etapas{nro_etapa}.Estado(nro_estado).ENS = evaluacion.entrega_ens();   
                    costo_operacion_etapa = costo_operacion_etapa + costo_operacion*pbb_estado;
                    costo_generacion_etapa = costo_generacion_etapa + costo_generacion*pbb_estado; 
                    ens_etapa = evaluacion.entrega_ens()*pbb_estado;
                end
                plan.crea_estructura_e_inserta_evaluacion_etapa(nro_etapa, costo_operacion_etapa, costo_generacion_etapa, ens_etapa);
            end
            this.calcula_costos_totales(plan);
        end
        
        function estados_por_etapas = determina_estados_por_etapa_plan(this, plan)
            [proyectos, etapas]= plan.entrega_proyectos_y_etapas();
            estados_por_etapas = cell(this.pParOpt.CantidadEtapas, 0);
            proyectos_con_incertidumbre = cell(this.pParOpt.CantidadEtapas, 1);
            probabilidad_realizacion = cell(this.pParOpt.CantidadEtapas, 1);
            proyectos_seguros = cell(this.pParOpt.CantidadEtapas, 1);
            for i = 1:length(proyectos)
                proy = this.pAdmProy.entrega_proyecto(proyectos(i));
                pbb_realizacion = proy.entrega_probabilidad_retraso(); % [0.5 0.3 0.2] pbbs: [sin retraso, 1 año retraso , 2 años retraso]
                ultima_etapa_con_incertidumbre = etapas(i) + length(pbb_realizacion)-2;
                retraso = 0;
                for nro_etapa = etapas(i):ultima_etapa_con_incertidumbre
                    retraso = retraso + 1;
                    proyectos_con_incertidumbre{nro_etapa} = [proyectos_con_incertidumbre{nro_etapa} proyectos(i)];
                    probabilidad_realizacion{nro_etapa} = [probabilidad_realizacion{nro_etapa} sum(pbb_realizacion(1:retraso))];
                end
                for nro_etapa = ultima_etapa_con_incertidumbre+1:this.pParOpt.CantidadEtapas
                    proyectos_seguros{nro_etapa} = [proyectos_seguros{nro_etapa} proyectos(i)];
                end
            end
            for nro_etapa = 1:this.pParOpt.CantidadEtapas
                proyectos_nodo_base = proyectos_seguros{nro_etapa};
                cantidad_estados = 2^length(proyectos_con_incertidumbre{nro_etapa});
                if cantidad_estados == 1
                    estados_por_etapas{nro_etapa}.Estado(1).Proyectos = proyectos_nodo_base;
                    estados_por_etapas{nro_etapa}.Estado(1).Probabilidad = 1;
                else
                    for i = 0:cantidad_estados-1
                        vec = convierte_decimal_a_binario(i,length(proyectos_con_incertidumbre{nro_etapa}));
                        %vec_test = de2bi(i,length(proyectos_con_incertidumbre{nro_etapa}));
                        proyectos_realizados = proyectos_con_incertidumbre{nro_etapa}(vec == 1);
                        pbb_proyectos_realizados = probabilidad_realizacion{nro_etapa}(vec == 1);
                        proyectos_no_realizados = proyectos_con_incertidumbre{nro_etapa}(vec == 0);
                        pbb_proyectos_no_realizados = probabilidad_realizacion{nro_etapa}(vec == 0);
                        estados_por_etapas{nro_etapa}.Estado(i+1).Proyectos = [proyectos_nodo_base proyectos_realizados];
                        % calcula probabilidad del estado
                        if nro_etapa == 1
                            vector_prob_estado = [pbb_proyectos_realizados (1-pbb_proyectos_no_realizados)];
                            estados_por_etapas{nro_etapa}.Estado(i+1).Probabilidad = prod(vector_prob_estado);
                        else
                            estados_por_etapas{nro_etapa}.Estado(i+1).Probabilidad = 0;
                            proy_estado_actual = estados_por_etapas{nro_etapa}.Estado(i+1).Proyectos; % todos, tanto con y sin incertidumbre
                            for j = 1:length(estados_por_etapas{nro_etapa-1}.Estado)
                                proy_estado_anterior = estados_por_etapas{nro_etapa-1}.Estado(j).Proyectos; % todos, tanto con y sin incertidumbre
                                % verifica si estado es conducente. Esto
                                % ocurre sólo si todos los proyectos del
                                % estado anterior están en el estado actual
                                if sum(ismember(proy_estado_actual, proy_estado_anterior)) == length(proy_estado_anterior)
                                    % nodos se conectan.
                                    prob_estado_base = estados_por_etapas{nro_etapa-1}.Estado(j).Probabilidad;
                                    proyectos_construir = proy_estado_actual(~ismember(proy_estado_actual,proy_estado_anterior));
                                    proyectos_no_construir = proyectos_con_incertidumbre{nro_etapa}(~ismember(proyectos_con_incertidumbre{nro_etapa},proy_estado_actual));
                                    pbb_cambio_estado = 1;
                                    for ii = 1:length(proyectos_construir)
                                        if ismember(proyectos_con_incertidumbre{nro_etapa}, proyectos_construir(ii))
                                            pbb_proyectos_construir = pbb_proyectos_realizados(proyectos_realizados == proyectos_construir(ii));
                                            pbb_cambio_estado = pbb_cambio_estado*pbb_proyectos_construir;
                                        else
                                           % nada que hacer, ya que proyecto se construye con pbb 1 
                                        end
                                    end
                                    for ii = 1:length(proyectos_no_construir)
                                        pbb_proyectos_no_construir = pbb_proyectos_no_realizados(proyectos_no_realizados == proyectos_no_construir(ii));
                                        pbb_cambio_estado = pbb_cambio_estado*(1-pbb_proyectos_no_construir);
                                    end
                                    estados_por_etapas{nro_etapa}.Estado(i+1).Probabilidad = estados_por_etapas{nro_etapa}.Estado(i+1).Probabilidad + prob_estado_base*pbb_cambio_estado;
                                end
                            end
                        end
                    end
                end
            end            
        end
        
        function evalua_resultado_y_guarda_en_plan(this, plan, nro_etapa, evaluacion)
            estructura_eval = this.entrega_estructura_evaluacion_opf(evaluacion);
            plan.inserta_evaluacion_etapa(nro_etapa, estructura_eval);
        end
        
        function estructura_eval = entrega_estructura_evaluacion_opf(this, evaluacion)
            if this.pParOpt.PlanValidoConENS && this.pParOpt.PlanValidoConRecorteRES
                estructura_eval.Valido = evaluacion.ExisteResultadoOPF;
            elseif ~this.pParOpt.PlanValidoConENS && this.pParOpt.PlanValidoConRecorteRES
                estructura_eval.Valido = evaluacion.ExisteResultadoOPF && ...
                                        evaluacion.hay_ens() == 0;
            elseif this.pParOpt.PlanValidoConENS && ~this.pParOpt.PlanValidoConRecorteRES
                estructura_eval.Valido = evaluacion.ExisteResultadoOPF && ...
                                        evaluacion.hay_recorte_res() == 0;
            elseif ~this.pParOpt.PlanValidoConENS && ~this.pParOpt.PlanValidoConRecorteRES
                estructura_eval.Valido = evaluacion.ExisteResultadoOPF && ...
                                        evaluacion.hay_ens() == 0 && ...
                                        evaluacion.hay_recorte_res() == 0;
            else
                error = MException('cOptACO:evalua_resultado_y_guarda_en_plan','caso no existe');
                throw(error)
            end
            
            if evaluacion.ExisteResultadoOPF
                estructura_eval.Existe = true;
                estructura_eval.CostoGeneracion = sum(evaluacion.CostoGeneracion);
                estructura_eval.CostoENS = sum(evaluacion.CostoENS);
                estructura_eval.CostoRecorteRES = sum(evaluacion.CostoRecorteRES);
                estructura_eval.CostoOperacion = estructura_eval.CostoGeneracion + estructura_eval.CostoENS + estructura_eval.CostoRecorteRES;
                lineas_flujo_maximo = evaluacion.entrega_lineas_flujo_maximo();
                estructura_eval.LineasFlujoMaximo = zeros(length(lineas_flujo_maximo),1);
                for i = 1:length(lineas_flujo_maximo)
                    estructura_eval.LineasFlujoMaximo(i) = lineas_flujo_maximo(i).entrega_id_adm_proyectos();
                end
                trafos_flujo_maximo = evaluacion.entrega_trafos_flujo_maximo();
                estructura_eval.TrafosFlujoMaximo = zeros(length(trafos_flujo_maximo),1);
                for i = 1:length(trafos_flujo_maximo)
                    estructura_eval.TrafosFlujoMaximo(i) = trafos_flujo_maximo(i).entrega_id_adm_proyectos();
                end
                lineas_poco_uso = evaluacion.entrega_lineas_poco_uso();
                estructura_eval.LineasPocoUso = zeros(length(lineas_poco_uso),1);
                for i = 1:length(lineas_poco_uso)
                    estructura_eval.LineasPocoUso(i) = lineas_poco_uso(i).entrega_id_adm_proyectos();
                end
                trafos_poco_uso = evaluacion.entrega_trafos_poco_uso();
                estructura_eval.TrafosPocoUso = zeros(length(trafos_poco_uso),1);
                for i = 1:length(trafos_poco_uso)
                    estructura_eval.TrafosPocoUso(i) = trafos_poco_uso(i).entrega_id_adm_proyectos();
                end
            else
                estructura_eval.CostoGeneracion = 9999999999999;
                estructura_eval.CostoENS = 9999999999999;
                estructura_eval.CostoRecorteRES = 9999999999999;                
                estructura_eval.CostoOperacion = 9999999999999;
                estructura_eval.LineasFlujoMaximo = [];
                estructura_eval.TrafosFlujoMaximo = [];
                estructura_eval.LineasPocoUso = [];
                estructura_eval.TrafosPocoUso = [];
                
%                 estructura_eval.PuntosOperacionInvalidos = 1;
%                 estructura_eval.LineasSobrecargadas = evaluacion.NombreElementosSobrecargados;
%                 estructura_eval.NivelSobrecarga = evaluacion.NivelSobrecarga;
%                 estructura_eval.LineasFlujoMaximo = evaluacion.entrega_lineas_flujo_maximo();
%                 estructura_eval.TrafosFlujoMaximo = evaluacion.entrega_trafos_flujo_maximo();
%                 estructura_eval.LineasPocoUso = evaluacion.entrega_lineas_poco_uso();
%                 estructura_eval.TrafosPocoUso = evaluacion.entrega_trafos_poco_uso();
                estructura_eval.Existe = false;
                % no existe resultado para el plan
                % imprime plan
                prot = cProtocolo.getInstance;
                prot.imprime_texto('Error de programacion. No existen resultados en la evaluacion. Se imprime plan fallido');
                prot.imprime_texto(['No. etapa: ' num2str(nro_etapa)]);
                plan.agrega_nombre_proyectos(this.pAdmProy);
                plan.imprime_plan_expansion();
            end            
        end
        
        
        function calcula_costos_totales(this,plan)
            %costos de inversion
            q = (1 + this.pParOpt.TasaDescuento);
            detapa = this.pParOpt.DeltaEtapa;
            costo_inversion= zeros(this.pParOpt.CantidadEtapas,1);
            costo_inversion_tactual = zeros(this.pParOpt.CantidadEtapas,1);
            for i= 1:length(plan.Proyectos) %cantidad etapas
                etapa = plan.Etapas(i);
                indice = plan.Proyectos(i);
                %costo_inv = this.pAdmProy.ProyTransmision(indice).entrega_costos_inversion();
                factor_desarrollo = this.pParOpt.entrega_factor_costo_desarrollo_proyectos();
                %costo_inv = round(costo_inv*factor_desarrollo,5);
                costo_inv = this.pAdmProy.calcula_costo_inversion_proyecto(this.pAdmProy.entrega_proyecto(indice), etapa, plan, factor_desarrollo);
                costo_inversion(etapa) = costo_inversion(etapa) + costo_inv;
                costo_inversion_tactual(etapa) = costo_inversion_tactual(etapa) + costo_inv/q^(detapa*etapa);
            end
            plan.CInv = costo_inversion;  %por cada etapa, sin llevarlo a valor actual
            plan.CInvTActual = costo_inversion_tactual;
            plan.CInvTotal = sum(costo_inversion_tactual);
            
            %costos de operacion
            costo_operacion = zeros(this.pParOpt.CantidadEtapas,1);
            costo_operacion_tactual = zeros(this.pParOpt.CantidadEtapas,1);
            costo_generacion = zeros(this.pParOpt.CantidadEtapas,1);
            costo_generacion_tactual = zeros(this.pParOpt.CantidadEtapas,1);
            costo_recorte_res = zeros(this.pParOpt.CantidadEtapas, 1);
            costo_recorte_res_tactual = zeros(this.pParOpt.CantidadEtapas, 1);
            costo_ens = zeros(this.pParOpt.CantidadEtapas, 1);
            costo_ens_tactual = zeros(this.pParOpt.CantidadEtapas, 1);
            for i = 1:this.pParOpt.CantidadEtapas %cantidad etapas
                costo_operacion(i) = plan.entrega_costo_operacion(i);
                costo_operacion_tactual(i) = costo_operacion(i)/q^(detapa*i);
                costo_generacion(i) = plan.entrega_costo_generacion(i);
                costo_generacion_tactual(i) = costo_generacion(i)/q^(detapa*i);
                costo_ens(i) = plan.entrega_costo_ens(i);
                costo_ens_tactual(i) = costo_ens(i)/q^(detapa*i);
                costo_recorte_res(i) = plan.entrega_costo_recorte_res(i);
                costo_recorte_res_tactual(i) = costo_recorte_res(i)/q^(detapa*i);
            end
            
            plan.COper = costo_operacion;
            plan.COperTActual = costo_operacion_tactual;
            plan.COperTotal = sum(costo_operacion_tactual);

            plan.CGen = costo_generacion; 
            plan.CGenTActual = costo_generacion_tactual;
            plan.CGenTotal = sum(costo_generacion_tactual);
            
            plan.CENS = costo_ens;
            plan.CENSTActual = costo_ens_tactual;
            plan.CENSTotal = sum(costo_ens_tactual);
    
            plan.CRecorteRES = costo_recorte_res;
            plan.CRecorteRESTActual = costo_recorte_res_tactual;
            plan.CRecorteRESTotal = sum(costo_recorte_res_tactual);
            
            %costos totales
            plan.Totex = plan.CInv + plan.COper;
            plan.TotexTActual = plan.CInvTActual + plan.COperTActual;
            plan.TotexTotal = plan.CInvTotal + plan.COperTotal;            
        end
        
        function delta_cinv = calcula_delta_cinv_elimina_proyectos(this, plan, nro_etapa, proyectos_eliminar)
            cinv_actual = plan.CInvTotal;
            
            % "crea" plan objetivo. 
            plan_objetivo = cPlanExpansion(9999997);
            plan_objetivo.Proyectos = plan.Proyectos;
            plan_objetivo.Etapas = plan.Etapas;

            for k = length(proyectos_eliminar):-1:1
                plan_objetivo.elimina_proyectos(proyectos_eliminar(k), nro_etapa);
            end
            % calcula costos de inversión de plan_objetivo
            cinv_plan_objetivo = this.calcula_costos_inversion_actual(plan_objetivo);
            delta_cinv = cinv_actual - cinv_plan_objetivo;
        end

        function delta_cinv = calcula_delta_cinv_adelanta_proyectos(this, plan, nro_etapa, proyectos_adelantar)
            cinv_actual = plan.CInvTotal;
            
            % "crea" plan objetivo. 
            plan_objetivo = cPlanExpansion(9999997);
            plan_objetivo.Proyectos = plan.Proyectos;
            plan_objetivo.Etapas = plan.Etapas;

            for k = length(proyectos_adelantar):-1:1
                plan_objetivo.adelanta_proyectos(proyectos_adelantar(k), nro_etapa,1);
            end
            % calcula costos de inversión de plan_objetivo
            cinv_plan_objetivo = this.calcula_costos_inversion_actual(plan_objetivo);
            delta_cinv = cinv_plan_objetivo - cinv_actual;
        end

        function delta_coper = estima_delta_coper_adelanta_proyectos(this, etapa_actual, delta_coper_actual, delta_coper_anterior)
            if abs(delta_coper_anterior) > 0
                correccion = (delta_coper_actual - delta_coper_anterior)/delta_coper_anterior;
                if correccion > 0.5
                    correccion = 0.5;
                elseif correccion < -0.5
                    correccion = -0.5;
                end
            else
                correccion = 0;
            end
                
            q = (1 + this.pParOpt.TasaDescuento);
            detapa = this.pParOpt.DeltaEtapa;
            delta_coper = 0;
            dcoper_etapa = delta_coper_actual;
            for nro_etapa = etapa_actual-1:-1:1
                dcoper_etapa = dcoper_etapa + correccion*dcoper_etapa;
                delta_coper = delta_coper + dcoper_etapa/q^(detapa*nro_etapa); 
            end
        end
        
        function cinv = calcula_costos_inversion_actual(this,plan)
            %costos de inversion
            q = (1 + this.pParOpt.TasaDescuento);
            detapa = this.pParOpt.DeltaEtapa;
            cinv = 0;
            for i = 1:length(plan.Proyectos)
                etapa = plan.Etapas(i);
                indice = plan.Proyectos(i);
                %costo_inv = this.pAdmProy.ProyTransmision(indice).entrega_costos_inversion();
                factor_desarrollo = this.pParOpt.entrega_factor_costo_desarrollo_proyectos();
                %costo_inv = round(costo_inv*factor_desarrollo,5);
                costo_inv = this.pAdmProy.calcula_costo_inversion_proyecto(this.pAdmProy.entrega_proyecto(indice), etapa, plan, factor_desarrollo);
                cinv = cinv + costo_inv/q^(detapa*etapa);
            end
        end
        
        function valido = evalua_plan_computo_paralelo(this, plan, nro_etapa, puntos_operacion, datos_escenario, sbase)
            plan.inserta_sep_original(this.pSEP);
            etapa_sep = plan.entrega_etapa_sep_actual();
            if etapa_sep > nro_etapa
                % en este caso hay que "volver" a generar el sep_actual
                plan.reinicia_sep_actual();
                etapa_sep = 0;
            end
            sep_plan = plan.entrega_sep_actual();

            %agrega plan de expansion
            proyectos = plan.entrega_proyectos_acumulados_desde_hasta_etapa(etapa_sep + 1, nro_etapa);
            for i = length(proyectos)
                indice = proyectos(i);
                proyecto = this.pAdmProy.entrega_proyecto(indice);
                protocoliza_accion_agrega_proyecto = false;
                correcto = sep_plan.agrega_proyecto(proyecto, protocoliza_accion_agrega_proyecto);
                if ~correcto
                    valido = false;
                    return
                end
            end

            plan.inserta_etapa_sep_actual(nro_etapa);            
            %sep_plan.actualiza_indices();
            pOPF = sep_plan.entrega_opf();
            if isempty(pOPF)            
                if strcmp(this.pParOpt.TipoFlujoPotencia, 'DC')
                    pOPF = cDCOPF(sep_plan);
                    pOPF.copia_parametros_optimizacion(this.pParOpt);
                    pOPF.inserta_puntos_operacion(puntos_operacion);
                    pOPF.inserta_datos_escenario(datos_escenario);
                    pOPF.inserta_sbase(sbase);
                    pOPF.inserta_resultados_en_sep(false);
                else
                    error = MException('cOptACO:evalua_plan','solo flujo DC implementado');
                    throw(error)
                end
            
                pOPF.inserta_nivel_debug(0);            
                pOPF.inserta_etapa(nro_etapa);
            else
                pOPF.inserta_puntos_operacion(puntos_operacion);
                pOPF.inserta_datos_escenario(datos_escenario);
                pOPF.actualiza_etapa(nro_etapa);
            end
            pOPF.calcula_despacho_economico();  
            this.evalua_resultado_y_guarda_en_plan(plan, nro_etapa, pOPF.entrega_evaluacion());
            valido = plan.es_valido(nro_etapa);
        end
        
        function calcula_costos_operacion_sin_restriccion(this)
            cantidad_etapas = this.pParOpt.CantidadEtapas;
            sep = this.pSEP.crea_copia();
            this.CostosOperacionSinRestriccion = zeros(cantidad_etapas,1);
            this.NPVCostosOperacionSinRestriccion = 0;
            q = (1 + this.pParOpt.TasaDescuento);
            detapa = this.pParOpt.DeltaEtapa;

            for etapa = 1:cantidad_etapas
                this.agrega_elementos_proyectados_a_sep_en_etapa(sep, etapa)
                grupos_proy = this.pAdmProy.entrega_proyectos_obligatorios_por_etapa(1, etapa);
                if ~isempty(grupos_proy)
                    for j = 1:length(grupos_proy)
                        % escoge primer proyecto
                        proy = grupos_proy(j).Proyectos(1);
                        sep.agrega_proyecto(proy);
                    end
                end
                if etapa == 1                    
                    pOPF = cDCOPF(sep, this.pAdmSc, this.pParOpt);
                    pOPF.inserta_nivel_debug(this.pParOpt.NivelDebugOPF);
                    pOPF.inserta_etapa(etapa);
                else
                    pOPF.actualiza_etapa(etapa);
                end
                pOPF.inserta_caso_estudio('sin_restricciones');
                pOPF.calcula_despacho_economico_sin_restricciones_red();
                % costos de operacion son solo costos de generacion. No hay
                % recorte RES ni ENS
                evaluacion = pOPF.entrega_evaluacion();

                costo_operacion = sum(evaluacion.CostoGeneracion + evaluacion.CostoRecorteRES+evaluacion.CostoENS);
                npv_costo_operacion = costo_operacion/q^(detapa*etapa);
                this.CostosOperacionSinRestriccion(etapa,1) = costo_operacion;
                this.NPVCostosOperacionSinRestriccion = this.NPVCostosOperacionSinRestriccion + npv_costo_operacion;
            end
        end
        
        function exporta_resultados(this, cadenas)
            doc_id_1 = fopen(['./output/parametros_sim_id_' num2str(this.IdArchivoSalida) '.txt'], 'w');
            heather = sprintf('%-45s %-15s', 'Parametro', 'Valor');
            fprintf(doc_id_1, strcat(heather, '\n'));
            parametros = this.pParOpt;
            texto = sprintf('%-45s %-15s', 'Considera incertidumbre', num2str(parametros.ConsideraIncertidumbre));
            fprintf(doc_id_1, strcat(texto, '\n'));
            if parametros.ConsideraIncertidumbre
                texto = sprintf('%-45s %-15s', 'Cantidad simulaciones por escenario', num2str(parametros.CantidadSimulacionesEscenarios));
                fprintf(doc_id_1, strcat(texto, '\n'));
            end
            texto = sprintf('%-45s %-15s', 'Cantidad cadenas ', num2str(parametros.CantidadCadenas));
            fprintf(doc_id_1, strcat(texto, '\n'));
            
            texto = sprintf('%-45s %-15s', 'Sigma likelihood', num2str(parametros.SigmaFuncionLikelihood));
            fprintf(doc_id_1, strcat(texto, '\n'));
            texto = sprintf('%-45s %-15s', 'Sigma parametros inicial', num2str(parametros.SigmaParametros));
            fprintf(doc_id_1, strcat(texto, '\n'));
            texto = sprintf('%-45s %-15s', 'Paso actualizacion', num2str(parametros.PasoActualizacion));
            fprintf(doc_id_1, strcat(texto, '\n'));

            fclose(doc_id_1);

            cantidad_cadenas = parametros.CantidadCadenas;
            tiempo_total_simulacion = this.ResultadosGlobales.TiempoTotalSimulacion;
            tiempo_promedio_por_iteracion = mean(this.ResultadosGlobales.TiempoIteracion);
            doc_id_2 = fopen(['./output/resultados_globales_id_' num2str(this.IdArchivoSalida) '.txt'], 'w');
            texto = sprintf('%-45s %-15s', 'Tiempo simulacion (horas)', num2str(tiempo_total_simulacion/60/60));
            fprintf(doc_id_2, strcat(texto, '\n'));
            texto = sprintf('%-45s %-15s', 'Tiempo promedio por iteracion (min)', num2str(tiempo_promedio_por_iteracion/60));
            fprintf(doc_id_2, strcat(texto, '\n'));
            for nro_cadena = 1:cantidad_cadenas
                if cadenas{nro_cadena}.TiempoEnLlegarAlOptimo ~= 0
                    texto_paso_optimo = find(cadenas{nro_cadena}.Totex == min(cadenas{nro_cadena}.Totex),1,'first');
                else
                    texto_paso_optimo = 0;
                end
                texto = sprintf('%-45s %-15s', ['Tiempo (paso) en llegar al optimo cadena (P) ' num2str(nro_cadena) ' (min)'], [num2str(cadenas{nro_cadena}.TiempoEnLlegarAlOptimo/60) '(' num2str(texto_paso_optimo) ')']);
                fprintf(doc_id_2, strcat(texto, '\n'));
            end
            fclose(doc_id_2);

            for nro_cadena = 1:cantidad_cadenas
                doc_id = fopen(['./output/resultados_sim_id_' num2str(this.IdArchivoSalida) '_cadena_' num2str(nro_cadena) '.txt'], 'w');
                [n, cantidad_proyectos] = size(cadenas{nro_cadena}.Proyectos);
                heather = sprintf('%-5s %-10s %-7s','Paso', 'Totex', 'Cambio');
                for i = 1:cantidad_proyectos
                    texto = sprintf('%-10s', ['EtP' num2str(i)]);
                    heather = [heather texto];
                end
                fprintf(doc_id, strcat(heather, '\n'));
                for i = 1:n
                    texto = sprintf('%-5s %-10s %-7s', num2str(i), ...
                        num2str(cadenas{nro_cadena}.Totex(i)), ...
                        num2str(cadenas{nro_cadena}.CambiosEstado(i)));
                    for j = 1:cantidad_proyectos
                        texto_proy = sprintf('%-10s',num2str(cadenas{nro_cadena}.Proyectos(i,j)));
                        texto = [texto texto_proy];
                    end
                    fprintf(doc_id, strcat(texto, '\n'));
                end
                fclose(doc_id);
            end
        end
        
        function inserta_identificador_archivos_salida(this, identificador)
            this.IdArchivoSalida = identificador;
        end
        
        function agrega_proyectos_etapa_a_sep(this, sep, plan, etapa)
            proyectos = plan.entrega_proyectos(etapa);
            for j = 1:length(proyectos)
                indice = proyectos(j);
                proyecto = this.pAdmProy.entrega_proyecto(indice);
                protocoliza_accion_agrega_proyecto = false;
                if this.iNivelDebug > 0
                    protocoliza_accion_agrega_proyecto =true;

                    if this.iNivelDebug > 3
                        prot = cProtocolo.getInstance;
                        texto = ['      Evalua plan ' num2str(plan.entrega_no()) ' en etapa: ' num2str(etapa) '. Agrega proyecto ' num2str(proyecto.entrega_indice()) ': ' proyecto.entrega_nombre()];
                        prot.imprime_texto(texto);
                    end
                end
                correcto = sep.agrega_proyecto(proyecto, protocoliza_accion_agrega_proyecto);
                if ~correcto
                    % Error (probablemente de programación). 
                    if this.iNivelDebug > 0
                        prot = cProtocolo.getInstance;
                        texto = ['Error de programacion. Plan ' num2str(plan.entrega_no()) ' no pudo ser implementado en SEP en etapa ' num2str(etapa)];
                        prot.imprime_texto(texto);
                        %if ~plan.nombre_proyectos_disponibles()
                            plan.agrega_nombre_proyectos(this.pAdmProy);
                        %end
                        plan.imprime();
                    end
                    return
                end
            end
        end
        
        function agrega_elementos_proyectados_a_sep_en_etapa(this, sep, etapa)
            elem = this.pAdmProy.entrega_elementos_proyectados_por_etapa(1, etapa);
            for i = 1:length(elem)
                nuevo_elem = elem(i).crea_copia();
                sep.agrega_y_conecta_elemento_red(nuevo_elem);
            end
        end
        
        function [proy_candidatos, etapas] = determina_espacio_busqueda_repara_plan(this, plan, evaluacion, etapa, tipo)
            % tipo: 1) ENS, 2) Recorte RES
            % Se da prioridad a las congestiones directas. Si no hay
            % proyectos, entonces se empiezan a agregar otros proyectos de
            % líneas congestionadas
            % etapas indica la etapa en el plan del proyecto candidato. Si
            % aparece un 0 indica que el proyecto candidato no está en el
            % plan.
            % dado que los problemas pueden ser de ENS y Recorte RES, se
            % solucionan ambos problemas en forma simultánea (y por eso se
            % hace la diferenciación)
            if tipo == 1
                consumos_ens = evaluacion.entrega_consumos_ens();
                if isempty(consumos_ens)
                    proy_candidatos = [];
                    etapas = [];
                    return
                end
                elementos_todos = consumos_ens;
            else
                gen_recorte_res = evaluacion.entrega_generadores_res_con_recorte();
                if isempty(gen_recorte_res)
                    proy_candidatos = [];
                    etapas = [];
                    return
                end
                elementos_todos = gen_recorte_res;
            end

            nivel_debug = this.iNivelDebug;
            if nivel_debug > 1
                prot = cProtocolo.getInstance;
                if tipo == 1
                    texto_tipo = 'ENS';
                else
                    texto_tipo = 'Recorte RES';
                end
                prot.imprime_texto(['   Espacio busqueda repara plan debido a ' texto_tipo '. Elementos sobrecargados:']);
                texto = sprintf('%-25s %-10s %-10s %-30s', 'Elemento', 'Tipo Rep', 'Carga', 'Proyectos');
                prot.imprime_texto(texto);
            end
            
            elem_flujo_max = evaluacion.entrega_lineas_flujo_maximo();
            elem_flujo_max = [elem_flujo_max evaluacion.entrega_trafos_flujo_maximo()];
            elem_flujo_max_revisados = zeros(length(elem_flujo_max),1);

            se_visitadas_nuevos_corr = []; % subestaciones con posibles nuevos corredores
            se_adyacentes_visitadas_tx = [];
            se_adyacentes_visitadas_bat = [];
            
            if nivel_debug > 1
                for j = 1:length(elem_flujo_max)
                    texto_imp{j,1} = sprintf('%-25s', elem_flujo_max(j).entrega_nombre());
                    texto_imp{j,2} = sprintf('%-10s', '-');
                    texto_imp{j,3} = sprintf('%-10s', num2str(round(max(abs(evaluacion.entrega_flujo_linea(elem_flujo_max(j))))/elem_flujo_max(j).entrega_sr(),2)));
                    texto_imp{j,4} = sprintf('%-30s', '-');
                end
                if isempty(elem_flujo_max)
                    texto_imp = cell(4,0);
                end
            end
            
            proy_candidatos= [];
            etapas = [];
                        
            for elem = 1:length(elementos_todos)
                se = elementos_todos(elem).entrega_se();
                conexiones = se.entrega_ultimas_conexiones_elementos_serie(); %1 indica que son sólo las últimas conexiones

                id_conexiones = ismember(elem_flujo_max, conexiones);
                elem_flujo_max_no_vistos = elem_flujo_max(id_conexiones == 1 & elem_flujo_max_revisados == 0);

                if nivel_debug > 1
                    indices = find(id_conexiones == 1);
                    for j = 1:length(indices)
                        texto_imp{indices(j),2} = sprintf('%-10s', 'Dir');
                    end
                end

                if isempty(elem_flujo_max_no_vistos)
                    % verifica subestaciones adyacentes
                    se_adyacentes = se.entrega_subestaciones_adyacentes();
                    se_adyacentes_validas = se_adyacentes(~ismember(se_adyacentes, se_adyacentes_visitadas_tx));
                    se_adyacentes_visitadas_tx = [se_adyacentes_visitadas_tx se_adyacentes_validas];
                    for i = 1:length(se_adyacentes_validas)
                        conexiones = se_adyacentes_validas(i).entrega_ultimas_conexiones_con_se_excluyente(se); % 1 indica que son sólo las últimas conexiones

                        id_conexiones = ismember(elem_flujo_max, conexiones);
                        nuevos_elem_flujo_max_no_vistos = elem_flujo_max(id_conexiones == 1 & elem_flujo_max_revisados == 0);

                        if ~isempty(nuevos_elem_flujo_max_no_vistos)
                            elem_flujo_max_revisados(ismember(elem_flujo_max,nuevos_elem_flujo_max_no_vistos)) = 1;
                            elem_flujo_max_no_vistos = [elem_flujo_max_no_vistos nuevos_elem_flujo_max_no_vistos];
                            id_conexiones = ismember(elem_flujo_max, nuevos_elem_flujo_max_no_vistos);
                            if nivel_debug > 1
                                indices = find(id_conexiones == 1);
                                for j = 1:length(indices)
                                    texto_imp{indices(j),2} = sprintf('%-10s', 'Ady');
                                end
                            end
                        end
                    end
                end

                if ~isempty(elem_flujo_max_no_vistos)
                    elem_flujo_max_revisados(ismember(elem_flujo_max,elem_flujo_max_no_vistos)) = 1;

                    for i = 1:length(elem_flujo_max_no_vistos)
                        proy = this.pAdmProy.entrega_id_proyectos_salientes(elem_flujo_max_no_vistos(i));
                        if nivel_debug > 1
                            indice = elem_flujo_max == elem_flujo_max_no_vistos(i);
                            texto_proy = '';
                            for k = 1:length(proy)
                                if k == 1
                                    texto_proy = num2str(proy(k));
                                else
                                    texto_proy = [texto_proy ' ' num2str(proy(k))];
                                end
                            end
                            texto_imp{indice,4} = sprintf('%-30s', texto_proy);
                        end

                        % determina si proyectos se encuentran en el plan en
                        % una etapa posterior
                        etapas_proy = plan.entrega_etapas_implementacion_proyectos_de_lista(proy, etapa+1);
                        proy_candidatos = [proy_candidatos proy];
                        etapas = [etapas etapas_proy];
                    end
                end
                
                % Baterías
                % prioridades: 
                % 1. adelantar "siguiente" batería implementada en etapa posterior
                % 2. agregar última batería posible
                baterias = this.pAdmProy.entrega_baterias_por_subestacion(se);
                proy_candidato_bat_encontrado = false;
                for i = 1:length(baterias)
                    id_proy_bat = this.pAdmProy.entrega_id_proyectos_entrantes(baterias(i));
                    etapa_bat = plan.entrega_etapas_implementacion_proyectos_de_lista(id_proy_bat);
                    
                    if etapa_bat ~= 0
                        if etapa_bat > etapa
                            % proyecto implementado y candidato a adelantarlo
                            proy_candidato_bat_encontrado = true;
                            proy_candidatos = [proy_candidatos id_proy_bat];
                            etapas = [etapas etapa_bat];

                            if nivel_debug > 1
                                [n, ~] = size(texto_imp);
                                texto_imp{n+1,2} = sprintf('%-10s', 'Bateria');
                                texto_imp{n+1,1} = sprintf('%-25s', this.pAdmProy.entrega_proyecto(id_proy_bat).Elemento(end).entrega_nombre());
                                texto_imp{n+1,3} = sprintf('%-10s', '-');
                                texto_imp{n+1,4} = sprintf('%-30s', num2str(id_proy_bat));
                            end
                            
                        end
                    else
                        % proyecto no se ha implementado, por lo tanto es candidato
                        proy_candidato_bat_encontrado = true;
                        proy_candidatos = [proy_candidatos id_proy_bat];
                        etapas = [etapas etapa_bat];

                        if nivel_debug > 1
                            [n, ~] = size(texto_imp);
                            texto_imp{n+1,2} = sprintf('%-10s', 'Bateria');
                            texto_imp{n+1,1} = sprintf('%-25s', this.pAdmProy.entrega_proyecto(id_proy_bat).Elemento(end).entrega_nombre());
                            texto_imp{n+1,3} = sprintf('%-10s', '-');
                            texto_imp{n+1,4} = sprintf('%-30s', num2str(id_proy_bat));
                        end
                        
                    end
                    
                    if proy_candidato_bat_encontrado
                        break
                    end
                end

                % incorpora proyectos de nuevos corredores, en caso de que aún no hayan sido incorporados
                if ~ismember(se.entrega_id(), se_visitadas_nuevos_corr)
                    se_visitadas_nuevos_corr = [se_visitadas_nuevos_corr se.entrega_id()];                    
                    proy_nuevo_corredor = this.pAdmProy.entrega_id_proyecto_nuevo_corredor(se.entrega_id());
                    if ~isempty(proy_nuevo_corredor)
                        % existe(n) proyecto(s). Verifica si alguno está implementado
                        etapas_proy_existente = plan.entrega_etapas_implementacion_proyectos_de_lista(proy_nuevo_corredor, 1);
                        proy_no_implementados = proy_nuevo_corredor(etapas_proy_existente == 0 | etapas_proy_existente > etapa);
                        if ~isempty(proy_no_implementados)
                            % se agregan proyectos no implementados. 
                            proy_candidatos = [proy_candidatos proy_no_implementados'];
                            etapas = [etapas etapas_proy_existente(etapas_proy_existente == 0 | etapas_proy_existente > etapa)];

                            if nivel_debug > 1
                                for k = 1:length(proy_no_implementados)
                                    [n, ~] = size(texto_imp);
                                    texto_imp{n+1,2} = sprintf('%-10s', 'NuevoCorr');
                                    texto_imp{n+1,1} = sprintf('%-25s', this.pAdmProy.entrega_proyecto(proy_no_implementados(k)).Elemento(end).entrega_nombre());
                                    texto_imp{n+1,3} = sprintf('%-10s', '-');
                                    texto_imp{n+1,4} = sprintf('%-30s', num2str(proy_no_implementados(k)));
                                end
                            end                                    
                        end                        
                    end
                end
            end
            
            % RAM: Ojo que este if se encontraba dentro del for anterior.
            % Ahora, sólo se buscan en los elementos con flujo maximo
            % restantes sólo si no se encontraron proyectos con elementos
            % flujo máximo en las subestaciones con ENS/Recorte y las
            % adyacentes. Habría que ver bien las implicancias
            if isempty(proy_candidatos)
                % no se encontraron proyectos candidatos, ni en las conexiones de las
                % subestaciones ni conexiones adyacentes. Se busca
                % en el resto de los elementos
                elem_flujo_max_restantes = elem_flujo_max(elem_flujo_max_revisados == 0);
                for j = 1:length(elem_flujo_max_restantes)
                    id_proy_salientes = this.pAdmProy.entrega_id_proyectos_salientes(elem_flujo_max_restantes(j));
                    if ~isempty(id_proy_salientes)

                        etapas_proy_salientes = plan.entrega_etapas_implementacion_proyectos_de_lista(id_proy_salientes, etapa+1);
                        pos_proy_implementado = find(etapas_proy_salientes ~= 0);
                        if ~isempty(pos_proy_implementado)
                            % existe un proyecto saliente implementado
                            proy_candidatos = [proy_candidatos id_proy_salientes(pos_proy_implementado)];
                            etapas = [etapas etapas_proy_salientes(pos_proy_implementado)];
                            if nivel_debug > 1
                                id = elem_flujo_max == elem_flujo_max_restantes(j);
                                texto_proy = num2str(id_proy_salientes(pos_proy_implementado));
                                texto_imp{id,4} = sprintf('%-30s', texto_proy);
                            end
                        else
                            % ninguno de los proyectos ha sido implementado. Se agregan
                            proy_candidatos = [proy_candidatos id_proy_salientes'];
                            etapas = [etapas zeros(1, length(id_proy_salientes))];

                            if nivel_debug > 1
                                id = elem_flujo_max == elem_flujo_max_restantes(j);
                                for k = 1:length(id_proy_salientes)
                                    if k == 1
                                        texto_proy = num2str(id_proy_salientes(k));
                                    else
                                        texto_proy = [texto_proy ' ' num2str(id_proy_salientes(k))];
                                    end
                                end
                                texto_imp{id,4} = sprintf('%-30s', texto_proy);
                            end
                        end
                    end
                    se_adyacente_1 = elem_flujo_max_restantes(j).entrega_se1();
                    if ~ismember(se_adyacente_1.entrega_id(), se_visitadas_nuevos_corr)
                        proy_nuevo_corredor = this.pAdmProy.entrega_id_proyecto_nuevo_corredor(se_adyacente_1.entrega_id());
                        if ~isempty(proy_nuevo_corredor)
                            % existe(n) proyecto(s). Verifica si alguno
                            % está implementado
                            etapas_proy_existente = plan.entrega_etapas_implementacion_proyectos_de_lista(proy_nuevo_corredor, 1);
                            proy_no_implementados = proy_nuevo_corredor(etapas_proy_existente == 0 | etapas_proy_existente > etapa);
                            if ~isempty(proy_no_implementados)
                                % se agregan proyectos no implementados. 
                                proy_candidatos = [proy_candidatos proy_no_implementados'];
                                etapas = [etapas etapas_proy_existente(etapas_proy_existente == 0 | etapas_proy_existente > etapa)];

                                if nivel_debug > 1
                                    for k = 1:length(proy_no_implementados)
                                        [n, ~] = size(texto_imp);
                                        texto_imp{n+1,2} = sprintf('%-10s', 'NuevoCorr');
                                        texto_imp{n+1,1} = sprintf('%-25s', this.pAdmProy.entrega_proyecto(proy_no_implementados(k)).Elemento(end).entrega_nombre());
                                        texto_imp{n+1,3} = sprintf('%-10s', '-');
                                        texto_imp{n+1,4} = sprintf('%-30s', num2str(proy_no_implementados(k)));
                                    end
                                end                
                            end
                        end
                        se_visitadas_nuevos_corr = [se_visitadas_nuevos_corr se_adyacente_1.entrega_id()];
                    end
                    se_adyacente_2 = elem_flujo_max_restantes(j).entrega_se2();
                    if ~ismember(se_adyacente_2.entrega_id(), se_visitadas_nuevos_corr)
                        proy_nuevo_corredor = this.pAdmProy.entrega_id_proyecto_nuevo_corredor(se_adyacente_2.entrega_id());
                        if ~isempty(proy_nuevo_corredor)
                            % existe(n) proyecto(s). Verifica si alguno
                            % está implementado en etapas posteriores
                            etapas_proy_existente = plan.entrega_etapas_implementacion_proyectos_de_lista(proy_nuevo_corredor, 1);
                            proy_no_implementados = proy_nuevo_corredor(etapas_proy_existente == 0 | etapas_proy_existente > etapa);
                            if ~isempty(proy_no_implementados)
                                % se agregan proyectos no implementados. 
                                proy_candidatos = [proy_candidatos proy_no_implementados'];
                                etapas = [etapas etapas_proy_existente(etapas_proy_existente == 0 | etapas_proy_existente > etapa)];

                                if this.iNivelDebug > 1
                                    for k = 1:length(proy_no_implementados)
                                        [n, ~] = size(texto_imp);
                                        texto_imp{n+1,2} = sprintf('%-10s', 'NuevoCorr');
                                        texto_imp{n+1,1} = sprintf('%-25s', this.pAdmProy.entrega_proyecto(proy_no_implementados(k)).Elemento(end).entrega_nombre());
                                        texto_imp{n+1,3} = sprintf('%-10s', '-');
                                        texto_imp{n+1,4} = sprintf('%-30s', num2str(proy_no_implementados(k)));
                                    end
                                end                                    
                            end                                
                        end
                        se_visitadas_nuevos_corr = [se_visitadas_nuevos_corr se_adyacente_2.entrega_id()];
                    end
                end
            end
            
            if ~isempty(proy_candidatos)
                % elimina proyectos repetidos
                [~, id_ens] = unique(proy_candidatos);
                proy_candidatos = proy_candidatos(id_ens);
                etapas = etapas(id_ens);

                if nivel_debug > 1
                    [n, ~] = size(texto_imp);
                    for j = 1:n
                        prot.imprime_texto(sprintf('%-25s %-10s %-10s %-30s', texto_imp{j,1}, texto_imp{j,2}, texto_imp{j,3}, texto_imp{j,4}));
                    end
                end
            else
                % no hay proyectos. Se incorporan proyectos nuevos corredores (todos)
                proy_nuevo_corredor = this.pAdmProy.entrega_id_proyectos_nuevos_corredores();
                if ~isempty(proy_nuevo_corredor)
                    % existe(n) proyecto(s). Verifica si alguno
                    % está implementado
                    etapas_proy_existente = plan.entrega_etapas_implementacion_proyectos_de_lista(proy_nuevo_corredor, 1);
                    proy_no_implementados = proy_nuevo_corredor(etapas_proy_existente == 0);
                    if ~isempty(proy_no_implementados)
                        % se agregan proyectos no implementados. 
                        proy_candidatos = [proy_candidatos proy_no_implementados'];
                        etapas = [etapas etapas_proy_existente(etapas_proy_existente == 0 | etapas_proy_existente > etapa)];
                        if nivel_debug > 1
                            for k = 1:length(proy_no_implementados)
                                [n, ~] = size(texto_imp);
                                texto_imp{n+1,2} = sprintf('%-10s', 'NuevoCorr');
                                texto_imp{n+1,1} = sprintf('%-25s', this.pAdmProy.entrega_proyecto(proy_no_implementados(k)).Elemento(end).entrega_nombre());
                                texto_imp{n+1,3} = sprintf('%-10s', '-');
                                texto_imp{n+1,4} = sprintf('%-30s', num2str(proy_no_implementados(k)));
                            end
                            prot.imprime_texto('No hay proyectos. Se incorporan todos los proyectos de nuevos corredores');
                            [n, ~] = size(texto_imp);
                            for j = 1:n
                                prot.imprime_texto(sprintf('%-25s %-10s %-10s %-30s', texto_imp{j,1}, texto_imp{j,2}, texto_imp{j,3}, texto_imp{j,4}));
                            end
                        end
                    end
                end
            end
            etapas(etapas == 0) = this.pParOpt.CantidadEtapas+1;
        end
        
        function debug_verifica_capacidades_corredores(this, plan, capacidades, texto_falla)
            % verifica capacidades corredores
            cantidad_etapas = this.pParOpt.CantidadEtapas;
            cantidad_decisiones_primarias = this.CantDecisionesPrimarias;
            
            [id_proyectos, etapas] = plan.entrega_proyectos_y_etapas();
            id_decision = this.pAdmProy.entrega_id_decision_dado_id_proyectos(id_proyectos);

            cantidad_decisiones_primarias = this.pAdmProy.entrega_cantidad_decisiones_primarias();
            capacidad_inicial_corredores = this.pAdmProy.entrega_capacidad_inicial_decisiones_primarias();
            capacidades_calculadas = ones(cantidad_decisiones_primarias, cantidad_etapas).*capacidad_inicial_corredores';
            for i = 1:length(id_proyectos)
                etapa_proy =etapas(i);
                id_decision_proy = id_decision(i);
                proyecto = this.pAdmProy.entrega_proyecto(id_proyectos(i));
                estado_conducente = proyecto.entrega_estado_conducente();
                capacidad_estado = this.pAdmProy.entrega_capacidad_estado_primario(id_decision_proy, estado_conducente);
                capacidades_calculadas(id_decision_proy, etapa_proy:end) = capacidad_estado;
            end
            if ~isempty(find(round(capacidades_calculadas,0) -round(capacidades,0) ~= 0, 1))
                disp('Aqui ocurre el error')
%                error = MException('cOptMCMC:debug_verifica_capacidades_corredores',['Capacidades no coinciden. ' texto_falla]);
%                throw(error)
            end
        end
        
        function debug_verifica_consistencia_proyectos_en_sep_y_plan(this, sep, plan, nro_etapa, texto_falla)
            proyectos_en_sep = sep.entrega_proyectos();
            proyectos_en_plan = plan.entrega_proyectos_acumulados(nro_etapa);
            if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
                if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
%                    error = MException('cOptMCMC:debug_verifica_consistencia_proyectos_en_sep_y_plan',...
%                        ['Proyectos en SEP distintos a proyectos en plan. ' texto_falla]);
%                    throw(error)
                    disp('Aquí ocurre el error')
                end
            end
        end

        function debug_verifica_consistencia_plan_valido(this, plan, texto_verificacion)
            if ~plan.es_valido()
%                error = MException('cOptMCMC:debug_verifica_consistencia_plan_valido',['Plan no es válido!. ' texto_verificacion]);
%                throw(error)
                warning('Aqui ocurre el error')
            end

            plan_debug = cPlanExpansion(888888889);
            plan_debug.Proyectos = plan.Proyectos;
            plan_debug.Etapas = plan.Etapas;
            plan_debug.inserta_sep_original(this.pSEP);
            for etapa_ii = 1:this.pParOpt.CantidadEtapas
                valido = this.evalua_plan(plan_debug, etapa_ii);
            end
            this.calcula_costos_totales(plan_debug);
            if round(plan_debug.entrega_totex_total(),2) ~= round(plan.entrega_totex_total(),2)
                prot = cProtocolo.getInstance;
                texto = 'Totex total de plan debug es distinto de totex total de plan actual!';
                prot.imprime_texto(texto);
                texto = ['Totex total plan debug: ' num2str(round(plan_debug.entrega_totex_total(),3))];
                prot.imprime_texto(texto);
                texto = ['Totex total plan actual: ' num2str(round(plan.entrega_totex_total(),3))];
                prot.imprime_texto(texto);

                disp('Aqui ocurre el error')
%                error = MException('cOptMCMC:debug_verifica_consistencia_plan_valido',['Totex total de plan debug es distinto de totex total de plan actual! ' texto_verificacion]);
%                throw(error)
            end
        end

        function debug_verifica_consistencia_costos_totales_plan(this, plan, texto_verificacion)
            plan_debug = cPlanExpansion(888888889);
            plan_debug.Proyectos = plan.Proyectos;
            plan_debug.Etapas = plan.Etapas;
            plan_debug.inserta_sep_original(this.pSEP);
            for etapa_ii = 1:this.pParOpt.CantidadEtapas
                valido = this.evalua_plan(plan_debug, etapa_ii);
            end
            this.calcula_costos_totales(plan_debug);
            if round(plan_debug.entrega_totex_total(),2) ~= round(plan.entrega_totex_total(),2)
                prot = cProtocolo.getInstance;
                texto = 'Totex total de plan debug es distinto de totex total de plan actual!';
                prot.imprime_texto(texto);
                texto = ['Totex total plan debug: ' num2str(round(plan_debug.entrega_totex_total(),3))];
                prot.imprime_texto(texto);
                texto = ['Totex total plan actual: ' num2str(round(plan.entrega_totex_total(),3))];
                prot.imprime_texto(texto);

                disp('Aqui ocurre el error')
                error = MException('cOptMCMC:debug_verifica_consistencia_plan_valido',['Totex total de plan debug es distinto de totex total de plan actual! ' texto_verificacion]);
                throw(error)
            end
        end
        
        function debug_verifica_coherencia_etapas_entrada(etapas, texto_verificacion)
            if length(etapas) > 1
                if ~isempty(find((etapas(2:end)-etapas(1:end-1)) < 0, 1))
                    error = MException('cOptMCMC:debug_verifica_coherencia_etapas_entrada',['Etapas de los proyectos no están en orden' texto_verificacion]);
                    throw(error)
                end
            end
        end
        
        function result = selecciona_proyectos_eliminar_desplazar_bl_detallada(this, plan, proy_restringidos, proy_en_evaluacion, varargin)
            % varargin indica proyecto base (en caso de que se indique)
            if nargin > 4
                result.seleccionado = varargin{1};
                result.seleccion_directa = 1;
                indice = result.seleccionado;
            else
                result.seleccionado = [];
            end
            result.etapa_seleccionado = [];
            result.ultima_etapa_posible = [];
            result.conectividad_eliminar = [];
            result.etapas_conectividad_eliminar = [];
            result.conectividad_desplazar = [];
            result.etapas_orig_conectividad_desplazar = [];
            result.etapas_fin_conectividad_desplazar = [];
            
            if isempty(result.seleccionado)
                nro_etapa = this.pParOpt.CantidadEtapas;
                [espacio_busqueda, desde_etapa] = this.pAdmProy.determina_espacio_busqueda_elimina_proyectos(plan, nro_etapa, [proy_restringidos proy_en_evaluacion]);
                ultima_etapa_posible = (this.pParOpt.CantidadEtapas+1)*ones(1,length(espacio_busqueda));
                result.seleccion_directa = 1;
                while isempty(espacio_busqueda) && nro_etapa > 0
                    if this.iNivelDebug > 1
                        prot = cProtocolo.getInstance;
                        prot.imprime_texto(['Espacio de busqueda vacio en etapa ' num2str(nro_etapa) '. Se busca en etapa anterior']);
                    end
                    
                    nro_etapa = nro_etapa - 1;
                    [espacio_busqueda, desde_etapa, ultima_etapa_posible] = this.pAdmProy.determina_espacio_busqueda_desplaza_proyectos(plan, nro_etapa, proy_restringidos, true, proy_en_evaluacion); % true indica que son acumulados
                    result.seleccion_directa = 0;
                    % no hay proyectos en espacio de busqueda

                end
                if isempty(espacio_busqueda) && nro_etapa == 0
                    % no hay proyectos
                    return
                end
            
                if length(espacio_busqueda) == 1
                    indice = espacio_busqueda(1);
                    result.seleccionado = indice;
                    result.etapa_seleccionado = desde_etapa;
                    result.ultima_etapa_posible = ultima_etapa_posible;
                else
                    % escoge proyecto en forma aleatoria
                    pos_escogido = ceil(rand*length(espacio_busqueda));
                    indice = espacio_busqueda(pos_escogido);
                    result.seleccionado = indice;
                    result.etapa_seleccionado = desde_etapa(pos_escogido);
                    result.ultima_etapa_posible = ultima_etapa_posible(pos_escogido);
                end
            else
                result.etapa_seleccionado = plan.entrega_etapa_proyecto(indice);
                [proy_siguientes, etapas_sig] = plan.entrega_proyectos_acumulados_y_etapas_a_partir_de_etapa(result.etapa_seleccionado+1);
                encontrado = false;
                for i = 1:length(proy_siguientes)
                    if this.pAdmProy.ProyTransmision(proy_siguientes(i)).TieneDependencia
                        id_proy_dep = this.pAdmProy.ProyTransmision(proy_siguientes(i)).entrega_indices_proyectos_dependientes();
                        if id_proy_dep == indice
                            encontrado = true;
                            result.ultima_etapa_posible = etapas_sig(i);
                            return
                        end
                    end
                end
                if ~encontrado
                    result.ultima_etapa_posible = this.pParOpt.CantidadEtapas+1;
                end
            end
            
            % verifica si proyecto seleccionado tiene requisitos de
            % conectividad.
            if this.pAdmProy.ProyTransmision(indice).TieneRequisitosConectividad
            	cantidad_req_conectividad = this.pAdmProy.ProyTransmision(indice).entrega_cantidad_grupos_conectividad();
                for ii = 1:cantidad_req_conectividad
                	indices_proyectos_conect = this.pAdmProy.ProyTransmision(indice).entrega_indices_grupo_proyectos_conectividad(ii);
                    % TODO DEBUG: en teoría no hay que verificar que la
                    % conectividad exista, ya que tiene que existir. Esta
                    % verificación se hace sólo para verificar que el
                    % código sea correcto.
                    if ~plan.conectividad_existe(indices_proyectos_conect)
                        error = MException('cOptMCMC:selecciona_proyectos_a_eliminar_y_desplazar','proyecto tiene requisito de conectividad, pero esta no se encuentra');
                        throw(error)
                    end

                    % verifica que no haya otro proyecto en el plan que
                    % tenga este requisito de conectividad (por ejemplo
                    % otra linea VU que llega a la misma SE. En este
                    % caso no se puede eliminar el transformador y/o la
                    % subestación.
                        
                    [id_proyecto_conectividad, ~] = plan.entrega_proyecto_conectividad_y_etapa(indices_proyectos_conect);
                    % TODO DEBUG: siguiente verificación es sólo debug
                    % para verificar que el código es correcto
                    if isempty(id_proyecto_conectividad) || length(id_proyecto_conectividad) > 1
                        error = MException('cOptMCMC:selecciona_proyectos_a_eliminar_y_desplazar','no se pudo encontrar requisito de conectividad o hay más de uno presente en el plan');
                        throw(error)
                    end
                    % verifica si hay más de un proyecto con el mismo
                    % requisito de conectividad
                    [id_proyectos_misma_conectividad, etapas_misma_conectividad] = this.pAdmProy.entrega_proyectos_con_mismo_requisito_conectividad(plan, id_proyecto_conectividad);
                    if length(id_proyectos_misma_conectividad) == 1
                        % se elimina proyecto de conectividad también
                        result.conectividad_eliminar = [result.conectividad_eliminar id_proyecto_conectividad];
                        result.etapas_conectividad_eliminar = [result.etapas_conectividad_eliminar etapas_misma_conectividad(1)];
                        
                        % finalmente, en caso de que el requisito de
                        % conectividad es un transformador, hay que verificar que éste no tiene
                        % un trafo paralelo. En este caso se elimina el trafo paralelo también
                        % obviamente si el primer trafo (requisito de
                        % conectividad) se puede eliminar, entonces los
                        % trafos paralelos también
                       
                        [proyectos_paralelos, etapas_proy_paralelos] = this.pAdmProy.entrega_id_proyectos_paralelos_parindex_creciente(plan, id_proyecto_conectividad);
                        result.conectividad_eliminar = [result.conectividad_eliminar proyectos_paralelos];
                        result.etapas_conectividad_eliminar = [result.etapas_conectividad_eliminar etapas_proy_paralelos];
                        
                    elseif length(id_proyectos_misma_conectividad) >1
                        % requisito de conectividad no se puede eliminar,
                        % ya que hay más de un proyecto con la misma
                        % conectividad
                        % Hay que determinar si se puede desplazar y cuánto
                        etapa_proyecto_seleccionado = plan.entrega_etapa_proyecto(indice);
                        etapa_proyecto_conectividad = plan.entrega_etapa_proyecto(id_proyecto_conectividad);
                        if etapa_proyecto_conectividad == etapa_proyecto_seleccionado
                            % ver cuánto se puede desplazar
                            indice_proy_seleccionado = id_proyectos_misma_conectividad == indice;
                            id_proyectos_misma_conectividad(indice_proy_seleccionado) = [];
                            etapas_misma_conectividad(indice_proy_seleccionado) = [];
                            etapa_potencial_desplazar = min(etapas_misma_conectividad);
                            if etapa_potencial_desplazar > etapa_proyecto_conectividad
                                result.conectividad_desplazar = [result.conectividad_desplazar id_proyecto_conectividad];
                                result.etapas_orig_conectividad_desplazar = [result.etapas_orig_conectividad_desplazar etapa_proyecto_conectividad];
                                result.etapas_fin_conectividad_desplazar = [result.etapas_fin_conectividad_desplazar etapa_potencial_desplazar];
                                
                                % verifica si hay que desplazar proyectos
                                % paralelos
                                [proyectos_paralelos, etapas_proy_paralelos] = this.pAdmProy.entrega_proyectos_paralelos_parindex_creciente(plan, id_proyecto_conectividad);
                                proy_paral_a_desplazar_orden = [];
                                etapa_proy_paral_a_desplazar_orden = [];
                                etapa_original_proy_paral_a_desplazar_orden = [];
                                for jj = 1:length(proyectos_paralelos)
                                    etapa_proyecto_paralelo = etapas_proy_paralelos(jj);
                                    if etapa_proyecto_paralelo < etapa_potencial_desplazar
                                        proy_paral_a_desplazar_orden = [proyectos_paralelos(jj).entrega_indice() proy_paral_a_desplazar_orden];
                                        etapa_proy_paral_a_desplazar_orden = [etapa_potencial_desplazar etapa_proy_paral_a_desplazar_orden];
                                        etapa_original_proy_paral_a_desplazar_orden = [etapa_proyecto_paralelo etapa_original_proy_paral_a_desplazar_orden];
                                    end
                                end
                                result.conectividad_desplazar = [result.conectividad_desplazar proy_paral_a_desplazar_orden];
                                result.etapas_orig_conectividad_desplazar = [result.etapas_orig_conectividad_desplazar etapa_original_proy_paral_a_desplazar_orden];
                                result.etapas_fin_conectividad_desplazar = [result.etapas_fin_conectividad_desplazar etapa_proy_paral_a_desplazar_orden];
                            end
                        end
                    end
                end
            end
            
            if this.iNivelDebug > 1
                prot = cProtocolo.getInstance;
                if result.seleccion_directa
                    texto_directo = 'd';
                else
                    texto_directo = 'i';
                end
                texto = ['   Proyectos seleccionados (' texto_directo ') para eliminar (' num2str(1 + length(result.conectividad_eliminar)) ') :'];
                for i = 1:length(result.conectividad_eliminar)
                    texto = [texto ' ' num2str(result.conectividad_eliminar(i))];
                end
                texto = [texto ' ' num2str(result.seleccionado) ' desde etapa: ' num2str(result.etapa_seleccionado) ' hasta etapa: ' num2str(result.ultima_etapa_posible)];                
                prot.imprime_texto(texto);
                                
                texto = ['   Proyectos seleccionados para desplazar (' num2str(length(result.conectividad_desplazar)) ') :'];
                for i = 1:length(result.conectividad_desplazar)
                    texto = [texto ' ' num2str(result.conectividad_desplazar(i)) ' de etapa ' num2str(result.etapas_orig_conectividad_desplazar(i)) ' a etapa ' num2str(result.etapas_fin_conectividad_desplazar(i)) ';'];
                end
                prot.imprime_texto(texto);
                
                texto = 'Proyectos en evaluacion: ';
                for i = 1:length(proy_en_evaluacion)
                    texto = [texto ' ' num2str(proy_en_evaluacion(i))];
                end
                prot.imprime_texto(texto);
           	end
        end
        
        function delta_cinv = calcula_delta_cinv_elimina_desplaza_proyectos(this, plan, nro_etapa, proyectos_eliminar, proyectos_desplazar, etapas_originales_desplazar, etapas_desplazar)
            cinv_actual = plan.CInvTotal;

            % "crea" plan objetivo. 
            plan_objetivo = cPlanExpansion(9999997);
            plan_objetivo.Proyectos = plan.Proyectos;
            plan_objetivo.Etapas= plan.Etapas;

            for k = length(proyectos_eliminar):-1:1
                plan_objetivo.elimina_proyectos(proyectos_eliminar(k), nro_etapa);
            end
            %desplaza proyectos
            for k = length(proyectos_desplazar):-1:1
                if nro_etapa < etapas_originales_desplazar(k)
                    % proyecto aún no se ha desplazado
                    plan_objetivo.desplaza_proyectos(proyectos_desplazar(k), etapas_originales_desplazar(k), etapas_desplazar(k));
                elseif nro_etapa >= etapas_originales_desplazar(k) && nro_etapa < etapas_desplazar(k)
                    % proyecto se comenzó a desplazar, pero desplazamiento
                    % aún no termina
                    plan_objetivo.desplaza_proyectos(proyectos_desplazar(k), nro_etapa, etapas_desplazar(k));
                else
                    % nada que hacer. Proyecto ya fue desplazado lo que
                    % tenía que desplazarse
                end
            end
            % calcula costos de inversión de plan_objetivo
            cinv_plan_objetivo = this.calcula_costos_inversion_actual(plan_objetivo);
            delta_cinv = cinv_actual - cinv_plan_objetivo;
        end

        function result = selecciona_proyectos_a_adelantar(this, plan, nro_etapa, varargin)
            if nargin > 3
                result.seleccionado = varargin{1};
                result.etapa_seleccionado = nro_etapa;
                result.seleccion_directa = 1;
                indice = result.seleccionado;
            else
                result.seleccionado = [];
                result.etapa_seleccionado = [];
            end
            
            result.primera_etapa_posible = [];
            result.proy_conect_adelantar = [];
            result.etapas_orig_conect = [];

            if isempty(result.seleccionado)
                error = MException('cOptACO:selecciona_proyectos_a_adelantar','Funcion aún no implementada');
                throw(error)
            end
                
            % determina primera etapa posible
            if this.pAdmProy.ProyTransmision(indice).TieneDependencia
                [~, result.primera_etapa_posible]= plan.entrega_proyecto_dependiente(this.pAdmProy.ProyTransmision(indice).entrega_indices_proyectos_dependientes());
            else
                result.primera_etapa_posible = 1;
            end
                
            % verifica si proyecto seleccionado tiene requisitos de
            % conectividad.
            if this.pAdmProy.ProyTransmision(indice).TieneRequisitosConectividad
            	cantidad_req_conectividad = this.pAdmProy.ProyTransmision(indice).entrega_cantidad_grupos_conectividad();
                    
                for ii = 1:cantidad_req_conectividad
                	indice_proy_conect = this.pAdmProy.ProyTransmision(indice).entrega_indices_grupo_proyectos_conectividad(ii);
                    % identifica proyecto de conectividad en el plan
                    [proy, etapa]= plan.entrega_proyecto_conectividad_y_etapa(indice_proy_conect);
                    if etapa == nro_etapa || (etapa < nro_etapa && etapa > result.primera_etapa_posible)
                        % proyecto de conectividad se tiene que adelantar
                        % también
                        result.proy_conect_adelantar= [result.proy_conect_adelantar proy];
                        result.etapas_orig_conect = [result.etapas_orig_conect etapa];
                    end
               end
            end

            if this.iNivelDebug > 1
                prot = cProtocolo.getInstance;
                if result.seleccion_directa
                    texto_directo = 'd';
                else
                    texto_directo = 'i';
                end
                texto = ['   Proyectos seleccionados (' texto_directo ') para adelantar (1): ' num2str(result.seleccionado) '. Primera etapa posible: ' num2str(result.primera_etapa_posible)];
                prot.imprime_texto(texto);
                
                texto = ['   Proyectos conectividad para adelantar (' num2str(length(result.proy_conect_adelantar)) ') :'];
                for i = 1:length(result.proy_conect_adelantar)
                    texto = [texto ' ' num2str(result.proy_conect_adelantar(i)) ' de etapa ' num2str(result.etapas_orig_conect(i))];
                end
                prot.imprime_texto(texto);
            end
        end
                    
        function debug_verifica_resultados_despacho_economico(this, opf, plan, nro_etapa, texto_verificacion)
            plan_debug = cPlanExpansion(888888889);
            plan_debug.Proyectos = plan.Proyectos;
            plan_debug.Etapas = plan.Etapas;
            plan_debug.inserta_sep_original(this.pSEP);
            valido = this.evalua_plan(plan_debug, nro_etapa);
            
            evaluacion_plan = plan.entrega_evaluacion(nro_etapa);
            evaluacion_debug = plan_debug.entrega_evaluacion(nro_etapa);
            if round(evaluacion_debug.CostoGeneracion,2) ~= round(evaluacion_plan.CostoGeneracion,2) || ...
                    round(evaluacion_debug.CostoENS,2) ~= round(evaluacion_plan.CostoENS,2) || ...
                    round(evaluacion_debug.CostoRecorteRES,2) ~= round(evaluacion_plan.CostoRecorteRES,2) || ...
                    round(evaluacion_debug.CostoOperacion,2) ~= round(evaluacion_plan.CostoOperacion,2)

                prot = cProtocolo.getInstance;
                texto = 'Evaluacion de plan debug es distinto a la de plan actual!';
                prot.imprime_texto(texto);
                texto = ['Costo operacion plan debug: ' num2str(round(evaluacion_debug.CostoGeneracion,3))];
                prot.imprime_texto(texto);
                texto = ['Costo operacion plan actual: ' num2str(round(evaluacion_plan.CostoGeneracion,3))];
                prot.imprime_texto(texto);

                disp('Aqui ocurre el error')
                error = MException('cOptMCMC:debug_verifica_resultados_despacho_economico',['Costos de plan debug son distintos a los costos del plan actual! ' texto_verificacion]);
                throw(error)
            end            
        end
    end
end