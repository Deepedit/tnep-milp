classdef cOptACO < handle
    properties
        % punteros a clases
        pSEP = cSistemaElectricoPotencia.empty
        pAdmProy = cAdministradorProyectos.empty
        pParOpt = cParOptimizacionACO.empty
        pFeromona = cFeromonaACO.empty
        pAdmSc = cAdministradorEscenarios.empty

        Resultados
        
        PlanOptimo = cPlanExpansion.empty  % plan óptimo calculado de otra parte e importado aquí
        PlanEvaluar = cPlanExpansion.empty  % plan para realizar pruebas
        
        CostosOperacionSinRestriccion
        NPVCostosOperacionSinRestriccion
        
        CantPlanesValidos = 0
        %estructuras
        PlanesValidosPorIteracion
        PlanesValidosPorIteracionBase
        PlanesValidosPorIteracionBL
        PlanesValidosPorIteracionBLEliminaDesplaza
        PlanesValidosPorIteracionBLSecuencialCompleto
        
        MejoresPlanes
        CantMejoresPlanesAgregadosPorIter
        
        ValorMejorResultado   % de cada iteracion
        ValorMejorResultadoAcumulado % acumulado por nro iteraciones
        ValorMejorResultadoBase   % de cada iteracion
        ValorMejorResultadoAcumuladoBase  % acumulado por nro iteraciones
        ValorMejorResultadoBL   % de cada iteracion
        ValorMejorResultadoAcumuladoBL % acumulado por nro iteraciones
        ValorMejorResultadoBLEliminaDesplaza
        ValorMejorResultadoAcumuladoBLEliminaDesplaza
    	ValorMejorResultadoBLSecuencialCompleto
        ValorMejorResultadoAcumuladoBLSecuencialCompleto
                
        ExistenResultadosParciales = false
        ItResultadosParciales = 0
        %Nivel de debug
        iNivelDebug = 1
        
        % ID computo sirve para sacar los output de modo debug paralelo
        IdComputo
    end
    
    methods
        function this = cOptACO(sep, AdmSc, adm_proyectos, par_optimizacion, feromona)
            this.pSEP = sep;
            this.pAdmSc = AdmSc;
            this.pAdmProy = adm_proyectos;
            this.pParOpt = par_optimizacion; 
            this.pFeromona = feromona;
            this.MejoresPlanes = cPlanExpansion.empty;
            this.ValorMejorResultado = [];
            this.ValorMejorResultadoBase = [];
            this.ValorMejorResultadoBL = [];
            this.ValorMejorResultadoBLEliminaDesplaza = [];
            this.ValorMejorResultadoBLSecuencialCompleto = [];
        end
                
        function inserta_nivel_debug(this, nivel)
            this.iNivelDebug = nivel;
        end
        
        function inserta_id_computo(this, val)
            this.IdComputo = val;
        end
        
        function plan = genera_plan_expansion(this, indice)
            if this.iNivelDebug > 2
                t_inic = tic;
                tiempo_espacio_busqueda = 0;
                cantidad_espacio_busqueda = 0;
                tiempo_selecciona_proyecto = 0;
                cantidad_selecciona_proyecto = 0;
                tiempo_conectividad  = 0;
                cantidad_conectividad = 0;
            end
            plan = cPlanExpansion(indice);
            cantidad_etapas = this.pParOpt.CantidadEtapas;
            for nro_etapa = 1:cantidad_etapas
                plan.inicializa_etapa(nro_etapa);
            end
            
            alfa = this.pParOpt.FactorAlfa;
            %primero determina si hay que seleccionar proyectos
            %obligatorios
            cant_proy_obligatorios = length(this.pAdmProy.ProyectosObligatorios);
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
                    costo_potencial = this.pAdmProy.entrega_costo_potencial(espacio_busqueda, plan);
                    maxpot = max(costo_potencial);
                    costo_potencial = -(costo_potencial-maxpot)/maxpot;
                    if sum(costo_potencial) > 0
                        inf_heuristica = costo_potencial/sum(costo_potencial); % se obtiene densidad de probabilidad
                    else
                        % todos los costos son iguales
                        inf_heuristica = costo_potencial;
                    end
                    
                    if cant_proy_obligatorios > 0
                        fer_construccion = this.pFeromona.entrega_feromonas_etapa(1, espacio_busqueda); % proyecto con mayor prob. a construirse en etapa 1
                        fer_construccion = fer_construccion / sum(fer_construccion); % densidad de probabilidad entre los proyectos                    
                    else
                        fer_construccion = 100 - this.pFeromona.entrega_feromonas_no_construccion(espacio_busqueda); % proyecto con mayor prob. de construirse (en general)
                        fer_construccion = fer_construccion / sum(fer_construccion); % densidad de probabilidad entre los proyectos
                    end

                    prob = alfa*fer_construccion + (1-alfa)*inf_heuristica;
                    suma_acumulada = cumsum(prob);
                    indice = find(rand*suma_acumulada(end)<suma_acumulada, 1, 'first');

    % TODO DEBUG inicio: 
    %Siguiente condición se puede eliminar una
    % vez que el programa esté verificado
                    if isempty(indice) || indice == 0
                        error = MException('cOptACO:genera_plan_expansion',...
                            'Error de programacion. Indice de proyectos no existe o es cero, a pesar de que espacio de proyecto no es vacio');
                        throw(error)
                    end
    % TODO DEBUG fin                
                end

                proyecto_seleccionado = espacio_busqueda(indice);
                
                % selecciona etapa
                if cant_proy_obligatorios > 0
                    etapa = 1;
                else
                    primera_etapa_posible = primeras_etapas_posibles(indice);
                    % se determina etapa de construcción para proyecto escogido
                    % se acepta posibilidad de que no se construya
                    % solo para proyectos "no obligatorios"
                    costo_potencial = this.pAdmProy.entrega_costo_potencial(proyecto_seleccionado, plan);
                    costo_potencial_por_etapa = zeros(cantidad_etapas + 1, 1);
                    q = (1 + this.pParOpt.TasaDescuento);
                    detapa = this.pParOpt.DeltaEtapa;
                    for i = 1:cantidad_etapas
                        costo_potencial_por_etapa(i) = costo_potencial/q^(detapa*i);
                    end
                    maxpot = max(costo_potencial_por_etapa);
                    costo_potencial_por_etapa = -(costo_potencial_por_etapa-maxpot)/maxpot;
                    inf_heuristica = costo_potencial_por_etapa/sum(costo_potencial_por_etapa); % densidad de probabilidad. Suma = 1

                    %fer_etapas = this.pFeromona.entrega_feromonas_proyecto(proyecto_seleccionado);
                    %prob_etapas = fer_etapas/sum(fer_etapas);
                    prob_etapas = this.pFeromona.entrega_feromonas_proyecto(proyecto_seleccionado)/100;
                    prob = alfa*prob_etapas + (1-alfa)*inf_heuristica;
                    suma_acumulada = cumsum(prob);
                    etapa = find(rand*suma_acumulada(end)<suma_acumulada, 1, 'first');

                    % verifica si etapa es válida
                    if etapa < primera_etapa_posible
                        etapa = primera_etapa_posible;
                    elseif etapa > cantidad_etapas
                        etapa = 0; % no se construye
                    end
                end
                
                if etapa > 0
                    % proyecto se agrega. Verifica requisitos de
                    % conectividad
                    proy_conectividad_agregar = [];
                    proy_conectividad_adelantar = [];
                    etapas_originales_adelantar = [];
                    if this.pAdmProy.Proyectos(proyecto_seleccionado).TieneRequisitosConectividad
                        cantidad_req_conectividad = this.pAdmProy.Proyectos(proyecto_seleccionado).entrega_cantidad_grupos_conectividad();
                        for ii = 1:cantidad_req_conectividad
                            indice_proy_conect = this.pAdmProy.Proyectos(proyecto_seleccionado).entrega_indices_grupo_proyectos_conectividad(ii);
                            [existe_con, etapa_con, proy_con] = plan.conectividad_existe_con_etapa_y_proyecto(indice_proy_conect);
                            if ~existe_con
                                if cant_proy_obligatorios > 0
                                    id_proyecto_conectividad = this.selecciona_proyecto_conectividad(indice_proy_conect, 1);
                                else
                                    id_proyecto_conectividad = this.selecciona_proyecto_conectividad(indice_proy_conect, cantidad_etapas);
                                end
                                proy_conectividad_agregar = [proy_conectividad_agregar id_proyecto_conectividad];
                            else
                                % proyecto conectividad existe. Se verifica
                                % que año de construcción sea antes que
                                % etapa
                                if etapa_con > etapa
                                    proy_conectividad_adelantar = [proy_conectividad_adelantar proy_con];
                                    etapas_originales_adelantar = [etapas_originales_adelantar etapa_con];
                                end
                            end
                       end
                    end

                    % se agrega proyectos en primera etapa posible
                    for i = 1:length(proy_conectividad_adelantar)
                        plan.adelanta_proyectos(proy_conectividad_adelantar(i), etapas_originales_adelantar(i), etapa)
                    end
                    
                    for i = 1:length(proy_conectividad_agregar)
                        plan.agrega_proyecto(etapa, proy_conectividad_agregar(i));
                        cantidad_proyectos_seleccionados = cantidad_proyectos_seleccionados + 1;
                    end
                    plan.agrega_proyecto(etapa, proyecto_seleccionado);
                    cantidad_proyectos_seleccionados = cantidad_proyectos_seleccionados + 1;
                else
                    proyectos_restringidos = [proyectos_restringidos proyecto_seleccionado]; % ya se determinó que no se construye
                end

                cant_proy_obligatorios = cant_proy_obligatorios - 1;
                if cant_proy_obligatorios > 0
                    espacio_busqueda = this.pAdmProy.ProyectosObligatorios(cant_proy_obligatorios).Indice;
                else
                    [espacio_busqueda, primeras_etapas_posibles] = this.pAdmProy.determina_espacio_busqueda(plan, proyectos_restringidos);
                end
            end
            
            if this.iNivelDebug > 1
            	prot = cProtocolo.getInstance;
                texto = ['Cantidad proyectos seleccionados plan ' num2str(cantidad_proyectos_seleccionados)];
                prot.imprime_texto(texto);
                
                if this.iNivelDebug > 1
                    prot.imprime_texto('Se imprime plan generado');
                    plan.agrega_nombre_proyectos(this.pAdmProy);
                    plan.imprime_plan_expansion();
                end
            end
        end
        
        function indice_proyecto = selecciona_proyecto_conectividad(this, espacio_busqueda, varargin)
            % varargin indica etapa para probabilidad. Si no se indica, se
            % utiliza probabilidad de que proyecto se construya
            if nargin > 2
                nro_etapa = varargin{1};
            else
                nro_etapa = this.pParOpt.CantidadEtapas;
            end
                        
            alfa = this.pParOpt.FactorAlfa;
            if isempty(espacio_busqueda)
            	prot = cProtocolo.getInstance;
                texto = 'Espacio de busqueda vacio para seleccionar proyectos de conectividad. Error de programación';
                prot.imprime_texto(texto);
            elseif length(espacio_busqueda) == 1
                indice_proyecto = espacio_busqueda;
                return
            end
                
            %seleccion de proyectos con feromonas en etapa indicada
            costo_potencial = this.pAdmProy.entrega_costo_potencial(espacio_busqueda);
            maxpot = max(costo_potencial);
            costo_potencial = -(costo_potencial-maxpot)/maxpot;
            prob_costo_potencial = costo_potencial/sum(costo_potencial);

            prob_construccion = this.pFeromona.entrega_feromonas_acumuladas_hasta_etapa(nro_etapa, espacio_busqueda);
            prob_construccion = prob_construccion / sum(prob_construccion); % densidad de probabilidad
            
            prob = alfa*prob_construccion + (1-alfa)*prob_costo_potencial;
            suma_acumulada = cumsum(prob);
            indice_proyecto = espacio_busqueda(find(rand*suma_acumulada(end)<suma_acumulada, 1, 'first'));
        end
        
        function indice_proyectos = selecciona_proyectos_obligatorios(this, espacio_proyectos)
            indice_proyectos = [];
            
            alfa = this.pParOpt.FactorAlfa;
            
            cant_proy_obligatorios = length(this.pAdmProy.ProyectosObligatorios);
            if cant_proy_obligatorios == 0
                return;
            end
            % proyectos obligatorios se buscan "de atrás hacia
            % adelante"
            indices = ismember(espacio_proyectos, this.pAdmProy.ProyectosObligatorios(cant_proy_obligatorios).Indice);
            espacio_busqueda = espacio_proyectos(indices);

            while cant_proy_obligatorios > 0
            	%primero calcula probabilidad relativa entre proyectos de
                %espacio de búsqueda
                
                %seleccion de proyectos con feromonas. Como se quiere
                %seleccionar proyecto obligatorio, se utiliza
                %probabilidad en etapa 1
                costo_potencial = this.pAdmProy.entrega_costo_potencial(espacio_busqueda);
                maxpot = max(costo_potencial);
                costo_potencial = -(costo_potencial-maxpot)/maxpot;
                prob_costo_potencial = costo_potencial/sum(costo_potencial);

                prob_construccion = 100 - this.pFeromona.entrega_feromonas_etapa(1, espacio_busqueda); % feromonas en etapa 1
                prob_construccion = prob_construccion / sum(prob_construccion); % densidad de probabilidad entre los proyectos            

                prob = alfa*prob_construccion + (1-alfa)*prob_costo_potencial;
                suma_acumulada = cumsum(prob);
                indice = espacio_busqueda(find(rand*suma_acumulada(end)<suma_acumulada, 1, 'first'));
                
                if isempty(indice) || indice == 0
                    error = MException('cOptACO:selecciona_plan_expansion_busqueda_local',...
                        'Error de programacion. Indice de proyectos es cero, a pesar de que espacio de proyecto no es vacio');
                    throw(error)
                end
                
                % verifica si proyecto seleccionado tiene requisitos de
                % conectividad.
                id_proy_conectividad_a_agregar = [];
                if this.pAdmProy.Proyectos(indice).TieneRequisitosConectividad
                    cantidad_req_conectividad = this.pAdmProy.Proyectos(indice).entrega_cantidad_grupos_conectividad();
                    
                    for ii = 1:cantidad_req_conectividad
                    	indice_proy_conect = this.pAdmProy.Proyectos(indice).entrega_indices_grupo_proyectos_conectividad(ii);
                        indices_en_espacio_proyectos = espacio_proyectos(ismember(espacio_proyectos, indice_proy_conect));
                        if ~isempty(indices_en_espacio_proyectos)
                            % quiere decir que proyecto de conectividad
                            % está en el espacio de proyectos y por ende
                            % hay que seleccionarlo
                            if length(indices_en_espacio_proyectos) > 1
                                error = MException('cOptACO:selecciona_plan_expansion_busqueda_local',...
                                'Error de programacion. Hay más de un proyecto de conectividad dentro del espacio de proyectos. Estos debieran ser excluyentes');
                                throw(error)
                            end
                            id_proy_conectividad_a_agregar = [id_proy_conectividad_a_agregar indices_en_espacio_proyectos];
                            espacio_proyectos(ismember(espacio_proyectos,id_proy_conectividad_a_agregar)) = [];
                        end
                   end
                end
                
                if ~isempty(id_proy_conectividad_a_agregar)
                    indice_proyectos = [indice_proyectos id_proy_conectividad_a_agregar];
                end
                
                % agrega indice a resultado
                indice_proyectos = [indice_proyectos indice];
                espacio_proyectos(ismember(espacio_proyectos, indice_proyectos)) = [];
                cant_proy_obligatorios = cant_proy_obligatorios -1;
                if cant_proy_obligatorios > 0
                	indices = ismember(espacio_proyectos, this.pAdmProy.ProyectosObligatorios(cant_proy_obligatorios).Indice);
                    espacio_busqueda = espacio_proyectos(indices);
                end
            end
        end
        
        function [proyecto_seleccionado, proyectos_conectividad] = selecciona_proyecto_obligatorio_a_agregar(this, proy_obligatorios, espacio_proyectos)
            espacio_busqueda = this.pAdmProy.determina_espacio_busqueda_local(proy_obligatorios);
            if isempty(espacio_busqueda)
                error = MException('cOptACO:selecciona_proyecto_obligatorio_a_agregar',...
                                   'Error de programacion. Espacio de busqueda esta vacio. No debiera ocurrir');
                throw(error)
            end

            alfa = this.pParOpt.FactorAlfa;
            costo_potencial = this.pAdmProy.entrega_costo_potencial(espacio_busqueda);
            maxpot = max(costo_potencial);
            costo_potencial = -(costo_potencial-maxpot)/maxpot;
            prob_costo_potencial = costo_potencial/sum(costo_potencial);
            
            prob_construccion = this.pFeromona.entrega_feromonas_etapa(1, espacio_busqueda);
            prob_construccion = prob_construccion / sum(prob_construccion); % densidad de probabilidad entre los proyectos            

            prob = alfa*prob_construccion + (1-alfa)*prob_costo_potencial;
            suma_acumulada = cumsum(prob);
            proyecto_seleccionado = espacio_busqueda(find(rand*suma_acumulada(end)<suma_acumulada, 1, 'first'));

            % verifica si proyecto seleccionado tiene requisitos de
            % conectividad.

            proyectos_conectividad = [];
            if this.pAdmProy.Proyectos(proyecto_seleccionado).TieneRequisitosConectividad
            	cantidad_req_conectividad = this.pAdmProy.Proyectos(proyecto_seleccionado).entrega_cantidad_grupos_conectividad();
                    
                for ii = 1:cantidad_req_conectividad
                	indice_proy_conect = this.pAdmProy.Proyectos(proyecto_seleccionado).entrega_indices_grupo_proyectos_conectividad(ii);
                    indices_en_espacio_proyectos = espacio_proyectos(ismember(espacio_proyectos, indice_proy_conect));
                    if ~isempty(indices_en_espacio_proyectos)
                        % quiere decir que proyecto de conectividad
                        % está en el espacio de proyectos y por ende
                        % hay que seleccionarlo
                        if length(indices_en_espacio_proyectos) > 1
                            error = MException('cOptACO:selecciona_proyecto_a_agregar',...
                            'Error de programacion. Hay más de un proyecto de conectividad dentro del espacio de proyectos. Estos debieran ser excluyentes');
                            throw(error)
                        end
                        proyectos_conectividad = [proyectos_conectividad indices_en_espacio_proyectos];
                    end
               end
            end
        end
        
        function [proy_seleccionado, proy_conectividad_agregar, primera_etapa_posible, proy_conectividad_adelantar, etapa_adelantar] = selecciona_proyecto_a_agregar(this, plan, nro_etapa, espacio_proyectos)
            if isempty(espacio_proyectos)
                error = MException('cOptACO:selecciona_proyecto_a_agregar',...
                                   'Error de programacion. No hay proyectos en el espacio de proyectos');
                throw(error)
            end
                        
            % los proyectos obligatorios ya fueron seleccionados
            % se determina el espacio de búsqueda en base a los
            % proyectos a disposición (en espacio proyectos)
            
            espacio_busqueda = this.pAdmProy.determina_espacio_busqueda_local_agrega_proyectos(plan, nro_etapa, espacio_proyectos, this.pParOpt.BLSecuencialCompletoPrioridadSobrecargaElem);
            
            if isempty(espacio_busqueda)
                error = MException('cOptACO:selecciona_proyecto_a_agregar',...
                                   'Error de programacion. Espacio de busqueda esta vacio. No debiera ocurrir');
                throw(error)
            end
            
            %seleccion de proyectos con feromonas
            alfa = this.pParOpt.FactorAlfa;
            
            costo_potencial = this.pAdmProy.entrega_costo_potencial(espacio_busqueda, plan);
            maxpot = max(costo_potencial);
            costo_potencial = -(costo_potencial-maxpot)/maxpot;
            prob_costo_potencial = costo_potencial/sum(costo_potencial); % se obtiene densidad de probabilidad
                
            prob_construccion = 100 - this.pFeromona.entrega_feromonas_no_construccion(espacio_busqueda); % proyecto con mayor prob. de construirse (en general)
            prob_construccion = prob_construccion / sum(prob_construccion); % densidad de probabilidad entre los proyectos
                
            prob = alfa*prob_construccion + (1-alfa)*prob_costo_potencial;
            suma_acumulada = cumsum(prob);
            indice = espacio_busqueda(find(rand*suma_acumulada(end)<suma_acumulada, 1, 'first'));
              
            % determina primera etapa posible
            if this.pAdmProy.Proyectos(indice).TieneDependencia
                [~, primera_etapa_posible]= plan.entrega_proyecto_dependiente(this.pAdmProy.Proyectos(indice).entrega_indices_proyectos_dependientes());
            else
                primera_etapa_posible = 1;
            end
                
            % verifica si proyecto seleccionado tiene requisitos de
            % conectividad.
            proy_seleccionado = indice;            
            proy_conectividad_agregar = [];
            proy_conectividad_adelantar = [];
            etapa_adelantar = [];
            if this.pAdmProy.Proyectos(indice).TieneRequisitosConectividad
            	cantidad_req_conectividad = this.pAdmProy.Proyectos(indice).entrega_cantidad_grupos_conectividad();
                    
                for ii = 1:cantidad_req_conectividad
                	indice_proy_conect = this.pAdmProy.Proyectos(indice).entrega_indices_grupo_proyectos_conectividad(ii);
                    indices_en_espacio_proyectos = espacio_proyectos(ismember(espacio_proyectos, indice_proy_conect));
                    if ~isempty(indices_en_espacio_proyectos)
                        % quiere decir que proyecto de conectividad
                        % está en el espacio de proyectos y por ende
                        % hay que seleccionarlo
                        if length(indices_en_espacio_proyectos) > 1
                            error = MException('cOptACO:selecciona_proyecto_a_agregar',...
                            'Error de programacion. Hay más de un proyecto de conectividad dentro del espacio de proyectos. Estos debieran ser excluyentes');
                            throw(error)
                        end
                        proy_conectividad_agregar = [proy_conectividad_agregar indices_en_espacio_proyectos];
                    else
                        % quiere decir que proyecto de conectividad está en
                        % el plan. Se determina etapa en donde se encuentra
                        [proy, etapa]= plan.entrega_proyecto_conectividad_y_etapa(indice_proy_conect);
                        if etapa > primera_etapa_posible
                            % proyecto de conectividad tiene potencial para
                            % ser adelantado también
                            proy_conectividad_adelantar = [proy_conectividad_adelantar proy];
                            etapa_adelantar = [etapa_adelantar etapa];
                        end
                    end
               end
            end
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
            if this.pAdmProy.Proyectos(indice).TieneDependencia
                [~, result.primera_etapa_posible]= plan.entrega_proyecto_dependiente(this.pAdmProy.Proyectos(indice).entrega_indices_proyectos_dependientes());
            else
                result.primera_etapa_posible = 1;
            end
                
            % verifica si proyecto seleccionado tiene requisitos de
            % conectividad.
            if this.pAdmProy.Proyectos(indice).TieneRequisitosConectividad
            	cantidad_req_conectividad = this.pAdmProy.Proyectos(indice).entrega_cantidad_grupos_conectividad();
                    
                for ii = 1:cantidad_req_conectividad
                	indice_proy_conect = this.pAdmProy.Proyectos(indice).entrega_indices_grupo_proyectos_conectividad(ii);
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
        
        function valido = evalua_plan(this, plan, nro_etapa, varargin)
            detallado = false;
            if nargin > 3
                detallado = varargin{1};
            end

            % copia SEP base e incluye plan de expansion
            etapa_sep = plan.entrega_etapa_sep_actual();
            if etapa_sep > nro_etapa
                % en este caso hay que "volver" a generar el sep_actual
                plan.reinicia_sep_actual();
                etapa_sep = 0;
            end
            sep_plan = plan.entrega_sep_actual();
            %agrega plan de expansion
            tope = min(length(plan.Plan), nro_etapa);
            for i = etapa_sep + 1:tope
                for j = 1:length(plan.Plan(i).Proyectos)
                    indice = plan.Plan(i).Proyectos(j);
                    proyecto = this.pAdmProy.entrega_proyecto(indice);
                    protocoliza_accion_agrega_proyecto = false;
                    if this.iNivelDebug > 0
                        protocoliza_accion_agrega_proyecto =true;
                        
                        if this.iNivelDebug > 2
                            prot = cProtocolo.getInstance;
                            texto = ['      Evalua plan ' num2str(plan.entrega_no()) ' en etapa: ' num2str(nro_etapa) '. Agrega proyecto ' num2str(proyecto.entrega_indice()) ': ' proyecto.entrega_nombre()];
                            prot.imprime_texto(texto);
                        end
                    end
                    correcto = sep_plan.agrega_proyecto(proyecto, protocoliza_accion_agrega_proyecto);
                    if ~correcto
                        % Error (probablemente de programación). 
                        if this.iNivelDebug > 0
                            prot = cProtocolo.getInstance;
                            texto = ['Error de programacion. Plan ' num2str(plan.entrega_no()) ' no pudo ser implementado en SEP en etapa ' num2str(nro_etapa)];
                            prot.imprime_texto(texto);
                            %if ~plan.nombre_proyectos_disponibles()
                                plan.agrega_nombre_proyectos(this.pAdmProy);
                            %end
                            plan.imprime();
                        end
                        valido = false;
                        return
                    end
                end
            end
            plan.inserta_etapa_sep_actual(nro_etapa);
            
            %sep_plan.actualiza_indices();
            pOPF = sep_plan.entrega_opf();
            if isempty(pOPF)
                if strcmp(this.pParOpt.TipoFlujoPotencia, 'DC')
                    pOPF = cDCOPF(sep_plan, this.pAdmSc, this.pParOpt);
                    pOPF.inserta_resultados_en_sep(false);
                else
                    error = MException('cOptACO:evalua_plan','solo flujo DC implementado');
                    throw(error)
                end
            
                nivel_debug = this.pParOpt.NivelDebugOPF;
                if detallado
                    nivel_debug = 4;
                end
                pOPF.inserta_nivel_debug(nivel_debug);
            
                pOPF.inserta_etapa(nro_etapa);
            else
                pOPF.actualiza_etapa(nro_etapa);
            end
            
            pOPF.calcula_despacho_economico();  
            this.evalua_resultado_y_guarda_en_plan(plan, pOPF.entrega_evaluacion(), nro_etapa);
            valido = plan.es_valido(nro_etapa);
            if detallado 
                pOPF.entrega_evaluacion().imprime_resultados(['Evaluacion plan etapa ' num2str(etapa)]);
                
                if pOPF.entrega_nivel_debug() > 3
                    no_oper = this.pAdmSc.entrega_puntos_operacion();
                    for oper = 1:no_oper
                        evaluacion = pOPF.entrega_evaluacion();
                        evaluacion.inserta_resultados_en_sep(oper); 
                        id_grafico = sep_plan.grafica_sistema(['Evaluacion plan ' num2str(plan.entrega_no()) ' etapa ' num2str(nro_etapa) ' oper ' num2str(oper)], true);
                        sep_plan.grafica_resultado_flujo_potencia(id_grafico);
                    end
                end
            end            
        end

        function valido = evalua_plan_computo_paralelo(this, plan, nro_etapa, puntos_operacion, datos_escenario, sbase)
            etapa_sep = plan.entrega_etapa_sep_actual();
            if etapa_sep > nro_etapa
                % en este caso hay que "volver" a generar el sep_actual
                plan.reinicia_sep_actual();
                etapa_sep = 0;
            end
            sep_plan = plan.entrega_sep_actual();

            %agrega plan de expansion
            tope = min(length(plan.Plan), nro_etapa);
            for i = etapa_sep + 1:tope
                for j = 1:length(plan.Plan(i).Proyectos)
                    indice = plan.Plan(i).Proyectos(j);
                    proyecto = this.pAdmProy.entrega_proyecto(indice);
                    protocoliza_accion_agrega_proyecto = false;
                    correcto = sep_plan.agrega_proyecto(proyecto, protocoliza_accion_agrega_proyecto);
                    if ~correcto
                        valido = false;
                        return
                    end
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
            this.evalua_resultado_y_guarda_en_plan(plan, pOPF.entrega_evaluacion(), nro_etapa);
            valido = plan.es_valido(nro_etapa);
        end
        
        function proyectos_seleccionados = repara_plan(this, plan, nro_etapa, varargin)
            % FUNCION OBSOLETA!!!! No debiera entrar aquí. Si lo hace,
            % ocurre un error.
            proyectos_seleccionados = [];
            if nargin > 3
                % varargin contiene espacio de proyectos (para búsqueda
                % local)                
                espacio_busqueda = this.pAdmProy.determina_espacio_busqueda_repara_plan(plan, nro_etapa, varargin{1});
            else
                espacio_busqueda = this.pAdmProy.determina_espacio_busqueda_repara_plan(plan, nro_etapa);
            end
            
            if isempty(espacio_busqueda)
                % plan no se puede reparar porque no hay más proyectos en
                % espacio de búsqueda
 %espacio_busqueda = this.pAdmProy.determina_espacio_busqueda(plan);
                if nargin > 3
                    error = MException('cOptACO:repara_plan','Error de programacion. Plan no es valido en busqueda local pero espacio de busqueda esta vacio');
                    throw(error)
                else
                    return;
                end
            end
            
            alfa = this.pParOpt.FactorAlfa;
            max_nro_reparaciones = this.pParOpt.MaxCantidadReparaciones;
            cantidad_proyectos_seleccionados = 0;
            valido = true;
            while (cantidad_proyectos_seleccionados < max_nro_reparaciones) && valido
                valido = false;

                costo_potencial = this.pAdmProy.entrega_costo_potencial(espacio_busqueda);
                maxpot = max(costo_potencial );
                costo_potencial  = -(costo_potencial -maxpot)/maxpot;
                
                prob_espacio = this.pFeromona.entrega_feromonas_acumuladas_hasta_etapa(nro_etapa, espacio_busqueda);
                prob_espacio = prob_espacio/sum(prob_espacio);
                prob = alfa*prob_espacio + (1-alfa)*costo_potencial ;
                suma_acumulada = cumsum(prob);
                indice = espacio_busqueda(find(rand*suma_acumulada(end)<suma_acumulada, 1, 'first'));
                cantidad_proyectos_seleccionados = cantidad_proyectos_seleccionados + 1;
                % verifica si proyecto seleccionado tiene requisitos de
                % conectividad.
                if this.pAdmProy.Proyectos(indice).TieneRequisitosConectividad
                    cantidad_req_conectividad = this.pAdmProy.Proyectos(indice).entrega_cantidad_grupos_conectividad();
                    for ii = 1:cantidad_req_conectividad
                        indice_proy_conect = this.pAdmProy.Proyectos(indice).entrega_indices_grupo_proyectos_conectividad(ii);
                        [conect_existe, conect_etapa] = plan.conectividad_existe_con_etapa(indice_proy_conect);
                        if ~conect_existe
                            if nargin > 3
                               % se busca entre los proyectos disponibles
                               proyectos_disponibles = varargin{1};
                               id_proyecto_conectividad = proyectos_disponibles(ismember(proyectos_disponibles, indice_proy_conect));
                               if isempty(id_proyecto_conectividad) || length(id_proyecto_conectividad) > 1
                                    error = MException('cOptACO:repara_plan','Error de programación. En busqueda local, proyecto de conectividad no se encuentra o hay más de uno');
                                    throw(error)
                               end
                            else
                                id_proyecto_conectividad = this.selecciona_proyecto_conectividad(indice_proy_conect, nro_etapa);
                            end
                            plan.agrega_proyecto(nro_etapa, id_proyecto_conectividad);
                            proyectos_seleccionados = [proyectos_seleccionados id_proyecto_conectividad];
                        else
                            if conect_etapa > nro_etapa
                               % hay que adelantar proyecto de conectividad
                               plan.adelanta_proyectos(indice_proy_conect, conect_etapa, nro_etapa)
                               proyectos_seleccionados = [proyectos_seleccionados indice_proy_conect];
                            end
                        end
                   end
                end
                
                etapa_proy_seleccionado = plan.entrega_etapa_proyecto(indice, false);
                if etapa_proy_seleccionado ~= 0
                    plan.adelanta_proyectos(indice, etapa_proy_seleccionado, nro_etapa);
                else
                    plan.agrega_proyecto(nro_etapa, indice);
                end
                proyectos_seleccionados = [proyectos_seleccionados indice];
                espacio_busqueda(ismember(espacio_busqueda, proyectos_seleccionados)) = [];
                %espacio_busqueda(espacio_busqueda == indice) = [];
                if this.iNivelDebug > 1
                    prot = cProtocolo.getInstance;
                    texto = ['   Repara plan agrega proyecto: ' num2str(indice)];
                    prot.imprime_texto(texto);
                end
                
                if ~isempty(espacio_busqueda) 
                    valido = true;
                end
%disp(strcat(num2str(cantidad_proyectos_seleccionados), '/',num2str(cantidad_proyectos),'--  ',num2str(indice_proyecto), '--  ', num2str(length(espacio_busqueda))));    
            end
            plan.CantidadReparaciones = plan.CantidadReparaciones + 1;
        end

        function proy_candidatos = entrega_proyectos_candidatos_repara_plan(this, plan, nro_etapa, varargin)
            % proy_candidatos(nro_candidato).seleccionado = indice;
            % proy_candidatos(nro_candidato).etapa_seleccionado = 0;
            % proy_candidatos(nro_candidato).conectividad_agregar = [];
            % proy_candidatos(nro_candidato).conectividad_adelantar = [];
            % proy_candidatos(nro_candidato).etapas_orig_conectividad_adelantar = [];
            
            % varargin indica proyectos restringidos porque ya fueron
            % evaluados
            if nargin > 3
                proy_restringidos = varargin{1};
            else
                proy_restringidos = [];
            end
            
            [espacio_busqueda, directo] = this.pAdmProy.determina_espacio_busqueda_repara_plan(plan, nro_etapa);
            espacio_busqueda = espacio_busqueda(~ismember(espacio_busqueda, proy_restringidos));
            
            if isempty(espacio_busqueda)
                if directo
                    espacio_busqueda = this.pAdmProy.determina_espacio_busqueda_repara_plan_en_etapa(plan, nro_etapa);
                    espacio_busqueda = espacio_busqueda(~ismember(espacio_busqueda, proy_restringidos));
                    directo = false;
                    if isempty(espacio_busqueda)
                        % plan no se puede reparar porque no hay más proyectos en
                        % espacio de búsqueda
                        proy_candidatos = [];
                        return;
                    end
                else
                    % busqueda no era directa, es decir, no hay proyectos
                    % candidatos
                    proy_candidatos = [];
                    return;
                end
            end
            
            proy_candidatos = cell(length(espacio_busqueda),0);
            if this.pParOpt.ReparaPlanSecuencial
                tope = 1;
            elseif directo
                tope = length(espacio_busqueda);
            else
                tope = this.pParOpt.ReparaPlanCantCompararIndirecto;
            end
            
            alfa = this.pParOpt.FactorAlfa;
            nro_candidato = 0;
            valido = true;
            while (nro_candidato < tope) && valido
                nro_candidato = nro_candidato + 1;
                valido = false;

                costo_potencial = this.pAdmProy.entrega_costo_potencial(espacio_busqueda);
                maxpot = max(costo_potencial );
                costo_potencial  = -(costo_potencial -maxpot)/maxpot;
                
                prob_espacio = this.pFeromona.entrega_feromonas_acumuladas_hasta_etapa(nro_etapa, espacio_busqueda);
                suma_prob_espacio = sum(prob_espacio);
                if suma_prob_espacio > 0
                    prob_espacio = prob_espacio/sum(prob_espacio);
                else
                    % quiere decir que proyectos candidatos tienen
                    % probabilidad nula de ser incorporado en la etapa. Se
                    % considera probabilidad de construccion
                    prob_espacio = this.pFeromona.entrega_feromonas_construccion(espacio_busqueda);
                    suma_prob_espacio = sum(prob_espacio);
                    if suma_prob_espacio > 0
                        prob_espacio = prob_espacio/sum(prob_espacio);
                    else
                        % quiere decir que ninguno de los proyectos
                        % candidatos tiene probabilidad de ser construidos.
                        % Proyectos se consideran equiprobables
                        prob_espacio = ones(1, length(espacio_busqueda));
                        prob_espacio = prob_espacio/sum(prob_espacio);
                    end
                end
                        
                prob = alfa*prob_espacio + (1-alfa)*costo_potencial ;
                suma_acumulada = cumsum(prob);
                indice = espacio_busqueda(find(rand*suma_acumulada(end)<suma_acumulada, 1, 'first'));
                proy_candidatos(nro_candidato).seleccionado = indice;
                proy_candidatos(nro_candidato).etapa_seleccionado = 0;
                proy_candidatos(nro_candidato).conectividad_agregar = [];
                proy_candidatos(nro_candidato).conectividad_adelantar = [];
                proy_candidatos(nro_candidato).etapas_orig_conectividad_adelantar = [];
                
                % verifica si proyecto seleccionado tiene requisitos de
                % conectividad.
                if this.pAdmProy.Proyectos(indice).TieneRequisitosConectividad
                    cantidad_req_conectividad = this.pAdmProy.Proyectos(indice).entrega_cantidad_grupos_conectividad();
                    for ii = 1:cantidad_req_conectividad
                        indice_proy_conect = this.pAdmProy.Proyectos(indice).entrega_indices_grupo_proyectos_conectividad(ii);
                        [conect_existente, conect_etapa] = plan.entrega_conectividad_existente_con_etapa(indice_proy_conect);
                        if conect_existente == 0
                            id_proyecto_conectividad = this.selecciona_proyecto_conectividad(indice_proy_conect, nro_etapa);
                            proy_candidatos(nro_candidato).conectividad_agregar = [proy_candidatos(nro_candidato).conectividad_agregar id_proyecto_conectividad];
                        else
                            if conect_etapa > nro_etapa
                               % hay que adelantar proyecto de conectividad
                               proy_candidatos(nro_candidato).conectividad_adelantar = [proy_candidatos(nro_candidato).conectividad_adelantar conect_existente];
                               proy_candidatos(nro_candidato).etapas_orig_conectividad_adelantar = [proy_candidatos(nro_candidato).etapas_orig_conectividad_adelantar conect_etapa];;
                            end
                        end
                   end
                end
                proy_candidatos(nro_candidato).etapa_seleccionado = plan.entrega_etapa_proyecto(indice, false);
                espacio_busqueda(ismember(espacio_busqueda, indice)) = [];
                if ~isempty(espacio_busqueda) 
                    valido = true;
                end
%disp(strcat(num2str(cantidad_proyectos_seleccionados), '/',num2str(cantidad_proyectos),'--  ',num2str(indice_proyecto), '--  ', num2str(length(espacio_busqueda))));    
            end
        end
        
        function proyectos_seleccionados = selecciona_proyectos_a_desplazar(this, plan, nro_etapa, proy_restringidos)
            proyectos_seleccionados = [];
            proyectos_etapa = plan.entrega_proyectos(nro_etapa);
            proyectos_etapa(ismember(proyectos_etapa, proy_restringidos)) = [];
            if isempty(proyectos_etapa)
                return;
            end

            espacio_busqueda = this.pAdmProy.determina_espacio_busqueda_desplaza_proyectos(plan, nro_etapa, proy_restringidos);
            if isempty(espacio_busqueda)
                % no hay proyectos en espacio de busqueda
                return
            end
            if length(espacio_busqueda) == 1
                indice = espacio_busqueda(1);
            else
                alfa = this.pParOpt.FactorAlfa;
                costo_potencial = this.pAdmProy.entrega_costo_potencial(espacio_busqueda);
                costo_potencial = costo_potencial/sum(costo_potencial);
                
                prob_espacio = this.pFeromona.entrega_feromonas_acumuladas_desde_etapa(nro_etapa+1, espacio_busqueda);
                prob_espacio = prob_espacio/sum(prob_espacio);
                prob = alfa*prob_espacio + (1-alfa)*costo_potencial;
            
                suma_acumulada = cumsum(prob);
                indice = espacio_busqueda(find(rand*suma_acumulada(end)<suma_acumulada, 1, 'first'));

                % TODO DEBUG inicio: 
                %Siguiente condición se puede eliminar una
                % vez que el programa esté verificado
                if isempty(indice) || indice == 0
                    error = MException('cOptACO:selecciona_proyectos_a_desplazar',...
                        'Error de programacion. Indice de proyectos no existe o es cero, a pesar de que espacio de proyecto no es vacio');
                    throw(error)
                end
            end
            
            % verifica si proyecto seleccionado tiene requisitos de
            % conectividad.
            cant_proy_conectividad = 0;
            if this.pAdmProy.Proyectos(indice).TieneRequisitosConectividad
            	cantidad_req_conectividad = this.pAdmProy.Proyectos(indice).entrega_cantidad_grupos_conectividad();
                for ii = 1:cantidad_req_conectividad
                	indices_proyectos_conect = this.pAdmProy.Proyectos(indice).entrega_indices_grupo_proyectos_conectividad(ii);
                    % RAMRAM DEBUG: en teoría no hay que verificar que la
                    % conectividad exista, ya que tiene que existir. Esta
                    % verificación se hace sólo para verificar que el
                    % código sea correcto.
                    if ~plan.conectividad_existe(indices_proyectos_conect)
                        error = MException('cOptACO:selecciona_proyectos_a_desplazar','proyecto tiene requisito de conectividad, pero esta no se encuentra');
                        throw(error)
                    end

                    % verifica que no haya otro proyecto en el plan que
                    % tenga este requisito de conectividad (por ejemplo
                    % otra linea VU que llega a la misma SE. En este
                    % caso no se puede eliminar el transformador y/o la
                    % subestación.
                        
                    [id_proyecto_conectividad, etapa_conectividad]= plan.entrega_proyecto_conectividad_y_etapa(indices_proyectos_conect);
                    % RAMRAM DEBUG: siguiente verificación es sólo debug
                    % para verificar que el código es correcto
                    if isempty(id_proyecto_conectividad) || length(id_proyecto_conectividad) > 1
                        error = MException('cOptACO:selecciona_proyectos_a_desplazar','no se pudo encontrar requisito de conectividad o hay más de uno presente en el plan');
                        throw(error)
                    end
                    
                    if etapa_conectividad == nro_etapa
                        % verifica si hay más de un proyecto con el mismo
                        % requisito de conectividad
                        cantidad_requisito_conectividad_existente = this.pAdmProy.entrega_cantidad_proyectos_con_mismo_requisito_conectividad(plan, nro_etapa, id_proyecto_conectividad);
                        if cantidad_requisito_conectividad_existente == 1
                            % se desplaza proyecto de conectividad también
                            proyectos_seleccionados = [proyectos_seleccionados id_proyecto_conectividad];

                            % finalmente, en caso de que el requisito de
                            % conectividad es un transformador, hay que verificar que éste no tiene
                            % un trafo paralelo aún conectado
                            % en este caso se elimina el trafo paralelo también
                            % obviamente si el primer trafo (requisito de
                            % conectividad) se puede eliminar, entonces los
                            % trafos paralelos también
                            proyectos_paralelos = this.pAdmProy.entrega_proyectos_paralelos_parindex_creciente(plan, id_proyecto_conectividad,nro_etapa);
                            proy_paral_orden = [];
                            for jj = 1:length(proyectos_paralelos)
                                proy_paral_orden = [proyectos_paralelos(jj).entrega_indice() proy_paral_orden];
                            end
                            proyectos_seleccionados = [proyectos_seleccionados proy_paral_orden];
                        end
                    end
                end
            end
            
            proyectos_seleccionados = [proyectos_seleccionados indice];
            
            if this.iNivelDebug > 1
                prot = cProtocolo.getInstance;
                texto = ['   Proyectos seleccionados (' num2str(length(proyectos_seleccionados)) ') :'];
                for i = 1:length(proyectos_seleccionados)
                    texto = [texto ' ' num2str(proyectos_seleccionados(i))];
                end
                prot.imprime_texto(texto);
           	end
        end

        function result = selecciona_proyectos_a_eliminar_y_desplazar(this, plan, nro_etapa, proy_restringidos, varargin)
            % varargin indica proyecto base (en caso de que se indique)
            if nargin > 4
                result.seleccionado = varargin{1};
                result.seleccion_directa = 1;
                indice = result.seleccionado;
            else
                result.seleccionado = [];
            end
            result.etapa_seleccionado = [];
            result.conectividad_eliminar = [];
            result.etapas_conectividad_eliminar = [];
            result.conectividad_desplazar = [];
            result.etapas_orig_conectividad_desplazar = [];
            result.etapas_fin_conectividad_desplazar = [];
            
            if isempty(result.seleccionado)
                [espacio_busqueda, directo] = this.pAdmProy.determina_espacio_busqueda_elimina_proyectos(plan, nro_etapa, proy_restringidos);
                if isempty(espacio_busqueda)
                    % no hay proyectos en espacio de busqueda
                    return
                end
            
                result.seleccion_directa = directo;
            
                if length(espacio_busqueda) == 1
                    indice = espacio_busqueda(1);
                else                    
                    alfa = this.pParOpt.FactorAlfa;
%costo_potencial = this.pAdmProy.entrega_costo_potencial(espacio_busqueda);
                    costo_potencial = this.pAdmProy.entrega_costo_potencial_con_etapa(espacio_busqueda, plan, this.pParOpt.TasaDescuento, this.pParOpt.DeltaEtapa);
                    costo_potencial = costo_potencial/sum(costo_potencial);
                    
                    prob_espacio = this.pFeromona.entrega_feromonas_no_construccion(espacio_busqueda);
                    prob_espacio = prob_espacio/sum(prob_espacio);
                    prob = alfa*prob_espacio + (1-alfa)*costo_potencial;
                    suma_acumulada = cumsum(prob);
                    indice = espacio_busqueda(find(rand*suma_acumulada(end)<suma_acumulada, 1, 'first'));
                end
                result.seleccionado = indice;
            end
            
            result.etapa_seleccionado = plan.entrega_etapa_proyecto(indice);
            
            % verifica si proyecto seleccionado tiene requisitos de
            % conectividad.
            if this.pAdmProy.Proyectos(indice).TieneRequisitosConectividad
            	cantidad_req_conectividad = this.pAdmProy.Proyectos(indice).entrega_cantidad_grupos_conectividad();
                for ii = 1:cantidad_req_conectividad
                	indices_proyectos_conect = this.pAdmProy.Proyectos(indice).entrega_indices_grupo_proyectos_conectividad(ii);
                    % RAMRAM DEBUG: en teoría no hay que verificar que la
                    % conectividad exista, ya que tiene que existir. Esta
                    % verificación se hace sólo para verificar que el
                    % código sea correcto.
                    if ~plan.conectividad_existe(indices_proyectos_conect)
                        error = MException('cOptACO:selecciona_proyectos_a_eliminar_y_desplazar','proyecto tiene requisito de conectividad, pero esta no se encuentra');
                        throw(error)
                    end

                    % verifica que no haya otro proyecto en el plan que
                    % tenga este requisito de conectividad (por ejemplo
                    % otra linea VU que llega a la misma SE. En este
                    % caso no se puede eliminar el transformador y/o la
                    % subestación.
                        
                    [id_proyecto_conectividad, ~] = plan.entrega_proyecto_conectividad_y_etapa(indices_proyectos_conect);
                    % RAMRAM DEBUG: siguiente verificación es sólo debug
                    % para verificar que el código es correcto
                    if isempty(id_proyecto_conectividad) || length(id_proyecto_conectividad) > 1
                        error = MException('cOptACO:selecciona_proyectos_a_eliminar_y_desplazar','no se pudo encontrar requisito de conectividad o hay más de uno presente en el plan');
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
                texto = [texto ' ' num2str(result.seleccionado)];
                prot.imprime_texto(texto);
                                
                texto = ['   Proyectos seleccionados para desplazar (' num2str(length(result.conectividad_desplazar)) ') :'];
                for i = 1:length(result.conectividad_desplazar)
                    texto = [texto ' ' num2str(result.conectividad_desplazar(i)) ' de etapa ' num2str(result.etapas_orig_conectividad_desplazar(i)) ' a etapa ' num2str(result.etapas_fin_conectividad_desplazar(i)) ';'];
                end
                prot.imprime_texto(texto);
           	end
        end

        function result = selecciona_proyectos_a_intercambiar(this, plan, proyectos_restringidos)
            result.corredor = 0;
            result.ubicacion = 0; %Trafo VU
            result.estado_eliminar = 0;
            result.cant_estados = 0;
            
            result.eliminar = [];
            result.etapa_eliminar = [];
            result.conectividad_desplazar = [];
            result.etapas_orig_conectividad_desplazar = [];
            result.etapas_fin_conectividad_desplazar = [];
            result.trafos_paralelos_potenciales_a_eliminar = [];
            result.etapas_trafos_paralelos_potenciales_a_eliminar = [];

            result.agregar = [];
            
            proyectos_escoger = plan.entrega_proyectos();
            proyectos_escoger(ismember(proyectos_escoger,proyectos_restringidos)) = [];
                        
            id_seleccionado = [];
            valido = false;
            while ~valido
                proyectos_escoger(ismember(proyectos_escoger,id_seleccionado)) = [];
                if isempty(proyectos_escoger)
                    return
                end
                id = ceil(rand*length(proyectos_escoger));
                id_seleccionado = proyectos_escoger(id);
                proy_seleccionado = this.pAdmProy.entrega_proyecto(id_seleccionado);
                if strcmp(proy_seleccionado.entrega_tipo_proyecto(), 'AS') || ...
                    (strcmp(proy_seleccionado.entrega_tipo_proyecto(), 'AT') && ...
                     proy_seleccionado.Elemento(1).entrega_id_corredor() == 0 && ...
                     proy_seleccionado.Elemento(1).entrega_indice_paralelo() == 1)
                    valido = false;
                else
                    valido = true;
                end
            end
            result.corredor = proy_seleccionado.Elemento(end).entrega_id_corredor();
            result.estado_eliminar = proy_seleccionado.Elemento(end).entrega_id_estado_planificacion();
            if result.corredor == 0
                result.ubicacion = proy_seleccionado.Elemento(end).entrega_se2().entrega_ubicacion();
                [~,result.cant_estados] = size(this.pAdmProy.MatrizEstadosTrafosVU(result.ubicacion).Estado);
            else
                [~,result.cant_estados] = size(this.pAdmProy.MatrizEstadosCorredores(result.corredor).Estado);
            end
            
            proy_con_requisito_conectividad = cProyectoExpansion.empty;
            etapa_proy_con_requisito_conectividad = 0;
            result.eliminar = id_seleccionado;
            result.etapa_eliminar = plan.entrega_etapa_proyecto(id_seleccionado);

            if proy_seleccionado.TieneRequisitosConectividad
                proy_con_requisito_conectividad = proy_seleccionado;
                etapa_proy_con_requisito_conectividad = result.etapa_eliminar;
            end
            
            % busca todos los proyectos en el plan para el corredor
            % correspondiente
            % primero busca proyectos dependientes
            proy_dep_todos = proy_seleccionado.entrega_indices_proyectos_dependientes();
            proyectos_plan = plan.entrega_proyectos();

            while ~isempty(proy_dep_todos)
                proy_dep_plan = proyectos_plan(ismember(proyectos_plan, proy_dep_todos));
                result.eliminar = [proy_dep_plan result.eliminar];
                etapa_proy_dep_plan = plan.entrega_etapa_proyecto(proy_dep_plan);
                result.etapa_eliminar = [etapa_proy_dep_plan result.etapa_eliminar];
                proy_dependiente = this.pAdmProy.entrega_proyecto(proy_dep_plan);
                proy_dep_todos = proy_dependiente.entrega_indices_proyectos_dependientes();
                if proy_dependiente.TieneRequisitosConectividad
                    proy_con_requisito_conectividad = proy_dependiente;
                    etapa_proy_con_requisito_conectividad = etapa_proy_dep_plan;
                end
            end

            proy_aguas_arriba_todos = proy_seleccionado.entrega_indices_proyectos_aguas_arriba();
            while ~isempty(proy_aguas_arriba_todos)
                proy_siguiente = proyectos_plan(ismember(proyectos_plan, proy_aguas_arriba_todos));
                if ~isempty(proy_siguiente)
                    result.eliminar = [result.eliminar proy_siguiente];
                    result.etapa_eliminar = [result.etapa_eliminar plan.entrega_etapa_proyecto(proy_siguiente)];
                    proy_aguas_arriba_todos = this.pAdmProy.entrega_proyecto(proy_siguiente).entrega_indices_proyectos_aguas_arriba();
                else
                    break
                end
            end
            
            % finalmente, selecciona proyectos de conectividad
            % result.conectividad_desplazar = [];
            % result.etapas_originales_conectividad_desplazar = [];
            % result.etapas_finales_conectividad_desplazar = [];
            % result.trafos_paralelos_potenciales_a_eliminar = [];
            % verifica si proyecto tiene requisito de conectividad
            if ~isempty(proy_con_requisito_conectividad)
                conect_eliminar_ordenado = [];
                etapa_conect_eliminar_ordenado = [];
            	cantidad_req_conectividad = proy_con_requisito_conectividad.entrega_cantidad_grupos_conectividad();
                    
                for ii = 1:cantidad_req_conectividad
                	indice_proy_conect = proy_con_requisito_conectividad.entrega_indices_grupo_proyectos_conectividad(ii);
                    [~, etapa_con_en_plan, proy_conect_en_plan] = plan.conectividad_existe_con_etapa_y_proyecto(indice_proy_conect);
                    [id_proyectos_misma_conectividad, etapas_misma_conectividad] = this.pAdmProy.entrega_proyectos_con_mismo_requisito_conectividad(plan, proy_conect_en_plan);
                    % opciones:
                    % 1. Si hay sólo un proyecto, entonces conectividad se
                    %    puede eliminar. Además, hay que identificar
                    %    eventuales transformadores paralelos que existan
                    % 2. Si hay más de un proyecto, entonces conectividad
                    %    no se puede eliminar. Sin embargo, hay que identificar trafos paralelos por si se pueden eliminar. 
                    %    Las opciones son:
                    % 2.1 etapa de conectividad < etapa_del proyecto: en
                    %     este caso no hay nada que hacer
                    % 2.2. etapa de conectividad = etapa del proyecto: en
                    %      este caso hay que desplazar la conectividad
                    %
                    % Primero en todo caso, se verifican trafos paralelos.
                    % Estos se eliminan
                    
                    [proyectos_paralelos, etapas_proy_paralelos] = this.pAdmProy.entrega_id_proyectos_paralelos_parindex_creciente(plan, proy_conect_en_plan);
                    proy_paral_a_eliminar_orden = [];
                    etapa_proy_paral_a_eliminar_orden = [];
                    etapa_original_proy_paral_a_eliminar_orden = [];
                    for jj = 1:length(proyectos_paralelos)
                        proy_paral_a_eliminar_orden = [proyectos_paralelos(jj) proy_paral_a_eliminar_orden];
                        etapa_proy_paral_a_eliminar_orden = [etapas_proy_paralelos(jj) etapa_proy_paral_a_eliminar_orden];
                    end
                    result.trafos_paralelos_potenciales_a_eliminar = [result.trafos_paralelos_potenciales_a_eliminar proy_paral_a_eliminar_orden];
                    result.etapas_trafos_paralelos_potenciales_a_eliminar = [result.etapas_trafos_paralelos_potenciales_a_eliminar etapa_proy_paral_a_eliminar_orden];

                    % elimina trafos paralelos de proyectos paralelos
                    id_pos_trafos_par = ismember(id_proyectos_misma_conectividad, proyectos_paralelos);
                    id_proyectos_misma_conectividad(id_pos_trafos_par) = [];
                    etapas_misma_conectividad(id_pos_trafos_par) = [];
                    
                    if length(id_proyectos_misma_conectividad) == 1
                        % se elimina proyecto de conectividad también
                        %[proy_con, etapa_con] = plan.entrega_proyecto_conectividad_y_etapa(indice_proy_conect);
                        conect_eliminar_ordenado = [conect_eliminar_ordenado proy_conect_en_plan];
                        etapa_conect_eliminar_ordenado = [etapa_conect_eliminar_ordenado etapa_con_en_plan];                        
                    elseif length(id_proyectos_misma_conectividad) > 1
                        % requisito de conectividad no se puede eliminar,
                        % ya que hay más de un proyecto con la misma
                        % conectividad
                        % Hay que determinar si se tiene que desplazar y cuánto
                        if etapa_con_en_plan == etapa_proy_con_requisito_conectividad
                            % ver cuánto se puede desplazar
                            indice_proy_seleccionado = id_proyectos_misma_conectividad == proy_con_requisito_conectividad;
                            %id_proyectos_misma_conectividad(indice_proy_seleccionado) = [];
                            etapas_misma_conectividad(indice_proy_seleccionado) = [];
                            etapa_potencial_desplazar = min(etapas_misma_conectividad);
                            if etapa_potencial_desplazar > etapa_con_en_plan
                                result.conectividad_desplazar = [result.conectividad_desplazar proy_conect_en_plan];
                                result.etapas_orig_conectividad_desplazar = [result.etapas_orig_conectividad_desplazar etapa_con_en_plan];
                                result.etapas_fin_conectividad_desplazar = [result.etapas_fin_conectividad_desplazar etapa_potencial_desplazar];                                
                            end
                        end
                    end
                end
                result.eliminar = [conect_eliminar_ordenado result.eliminar];
                result.etapa_eliminar = [etapa_conect_eliminar_ordenado result.etapa_eliminar];
                
            end
            
            % se agregan proyectos a agregar
            no_estado_actual = 0;
            for i = 1:result.cant_estados
                if i ~= result.estado_eliminar
                    no_estado_actual = no_estado_actual + 1;
                    result.agregar{no_estado_actual} = [];
                    if result.corredor == 0
                        cant_proy = length(this.pAdmProy.MatrizEstadosTrafosVU(result.ubicacion).Estado(:,i));
                        j = 1;
                        while isempty(this.pAdmProy.MatrizEstadosTrafosVU(result.ubicacion).Estado(j,i).ProyectosEntrantes)
                            j = j + 1;
                        end
                        proy_agregar = this.pAdmProy.MatrizEstadosTrafosVU(result.ubicacion).Estado(j,i).ProyectosEntrantes;
                        result.agregar{no_estado_actual} = [result.agregar{no_estado_actual} proy_agregar.entrega_indice()];
                    else
                        cant_proy = length(this.pAdmProy.MatrizEstadosCorredores(result.corredor).Estado(:,i));
                        j = 1;
                        while isempty(this.pAdmProy.MatrizEstadosCorredores(result.corredor).Estado(j,i).ProyectosEntrantes)
                            j = j + 1;
                        end
                        proy_agregar = this.pAdmProy.MatrizEstadosCorredores(result.corredor).Estado(j,i).ProyectosEntrantes;
                        result.agregar{no_estado_actual} = [result.agregar{no_estado_actual} proy_agregar.entrega_indice()];                            
                    end
                end
            end            
        end
        
        function result = selecciona_proyectos_a_agregar(this, plan, proyecto_seleccionado)
            result.seleccionado = proyecto_seleccionado;
            indice = result.seleccionado;
            
            result.primera_etapa_posible = [];
            result.proy_conect_agregar = [];
            result.proy_conect_adelantar = [];
            result.etapas_orig_conect_adelantar = [];

            if isempty(result.seleccionado)
                error = MException('cOptACO:selecciona_proyectos_a_agregar','No se indica proyecto seleccionado');
                throw(error)
            end
                
            % determina primera etapa posible
            if this.pAdmProy.Proyectos(indice).TieneDependencia
                [~, result.primera_etapa_posible]= plan.entrega_proyecto_dependiente(this.pAdmProy.Proyectos(indice).entrega_indices_proyectos_dependientes(), false); % false indica que es sin error
                if result.primera_etapa_posible == 0
                   % proyecto dependiente no existe en el plan. Se descarta
                   return;
                end
            else
                result.primera_etapa_posible = 1;
            end
                
            % verifica si proyecto seleccionado tiene requisitos de
            % conectividad.
            if this.pAdmProy.Proyectos(indice).TieneRequisitosConectividad
            	cantidad_req_conectividad = this.pAdmProy.Proyectos(indice).entrega_cantidad_grupos_conectividad();
                    
                for ii = 1:cantidad_req_conectividad
                	indice_proy_conect = this.pAdmProy.Proyectos(indice).entrega_indices_grupo_proyectos_conectividad(ii);
                    % identifica proyecto de conectividad en el plan
                    [proy, etapa]= plan.entrega_proyecto_conectividad_y_etapa(indice_proy_conect);
                    if etapa ~= 0 && etapa > result.primera_etapa_posible
                        % proyecto de conectividad se tiene que adelantar
                        % también
                        result.proy_conect_adelantar= [result.proy_conect_adelantar proy];
                        result.etapas_orig_conect_adelantar = [result.etapas_orig_conect_adelantar etapa];
                    elseif etapa == 0
                        % hay que agregar proyecto de conectividad
                        id_proyecto_conectividad = this.selecciona_proyecto_conectividad(indice_proy_conect);
                        result.proy_conect_agregar = [result.proy_conect_agregar id_proyecto_conectividad];
                    end
               end
            end

            if this.iNivelDebug > 1
                prot = cProtocolo.getInstance;
                texto = ['   Proyectos seleccionados para agregar (1): ' num2str(result.seleccionado) '. Primera etapa posible: ' num2str(result.primera_etapa_posible)];
                prot.imprime_texto(texto);

                texto = ['   Proyectos conectividad para agregar (' num2str(length(result.proy_conect_agregar)) ') :'];
                for i = 1:length(result.proy_conect_agregar)
                    texto = [texto ' ' num2str(result.proy_conect_agregar(i))];
                end
                prot.imprime_texto(texto);
                
                texto = ['   Proyectos conectividad para adelantar (' num2str(length(result.proy_conect_adelantar)) ') :'];
                for i = 1:length(result.proy_conect_adelantar)
                    texto = [texto ' ' num2str(result.proy_conect_adelantar(i)) ' a partir de etapa ' num2str(result.etapas_orig_conect_adelantar(i))];
                end
                prot.imprime_texto(texto);
            end
        end
        
        function guarda_plan(this, pPlan, nro_iteracion, tipo)
            this.PlanesValidosPorIteracion(nro_iteracion).Planes(end+1) = pPlan;
            if tipo == 0
                % base
                this.PlanesValidosPorIteracionBase(nro_iteracion).Planes(end+1) = pPlan;
            else
                this.PlanesValidosPorIteracionBL(nro_iteracion).Planes(end+1) = pPlan;
                if tipo == 1
                    % búsqueda local elimina desplaza
                    this.PlanesValidosPorIteracionBLEliminaDesplaza(nro_iteracion).Planes (end+1) = pPlan;
                elseif tipo == 2
                    % agrega proyectos en forma secuencial completo
                    this.PlanesValidosPorIteracionBLSecuencialCompleto(nro_iteracion).Planes (end+1) = pPlan;
                else
                    error = MException('cOptACO:guarda_plan',['tipo ' num2str(tipo) ' aun no implementado']);
                    throw(error)
                end
            end
            
            pPlan.SEP_original = cSistemaElectricoPotencia.empty;
            pPlan.SEP_actual = cSistemaElectricoPotencia.empty;
        end
        
        function criterio = evalua_criterio_salida(this)
            criterio = false;
            nro_iteracion = length(this.ValorMejorResultado);
            if nro_iteracion > this.pParOpt.MaxItPlanificacion
            	criterio = true;
                return
            end
            
            if isempty(this.PlanOptimo)
                if nro_iteracion < this.pParOpt.MinItPlanificacion
                    return
                end
                %delta = this.pParOpt.DeltaObjetivoParaSalida;            
                cantidad_iter_sin_mejora = this.pParOpt.CantidadIteracionesSinMejora;
            
                tope = min(nro_iteracion - 1,cantidad_iter_sin_mejora); 
                diff_funcion_objetivo = this.ValorMejorResultadoAcumulado(end)-this.ValorMejorResultadoAcumulado(end-tope);
            
                if diff_funcion_objetivo == 0
                    criterio = true;
                end
            else
                % verifica si mejor plan es igual a plan óptimo
                mejor_plan = this.MejoresPlanes(1);
                totex_mejor_plan = this.MejoresPlanes(1).TotexTotal;
                totex_plan_optimo = this.PlanOptimo.TotexTotal;
                if totex_mejor_plan == totex_plan_optimo
                    debug = true;
                else
                    debug = false;
                end
                iguales = mejor_plan.compara_proyectos(this.PlanOptimo, debug);
                if iguales
                    % verifica que TOTEX sea el mismo
                    % RAMRAM DEBUG. Este paso no es necesario si se está
                    % 100% seguro del plan óptimo
                    if round(mejor_plan.TotexTotal,2) ~= round(this.PlanOptimo.TotexTotal,2)
                    	prot = cProtocolo.getInstance;
                        texto = 'Error de programación. Mejor plan actual es igual a plan optimo pero tienen distinto Totex. Se imprimen planes';
                        prot.imprime_texto(texto);
                        prot.imprime_texto('Se imprime plan optimo');
                        this.PlanOptimo.agrega_nombre_proyectos();
                        this.PlanOptimo.imprime();
                        
                        mejor_plan.agrega_nombre_proyectos(this.pAdmProy);
                        mejor_plan.imprime();

                        error = MException('cOptACO:evalua_criterio_salida','Error en datos de entrada. Planes son iguales pero con distinto TOTEX');
                        throw(error)
                    end
                    criterio = true;
                end
            end
        end
        
        function actualiza_resultados_parciales_iteracion(this, nro_iteracion, tipo)
            if tipo == 0
                %base
                if length(this.PlanesValidosPorIteracionBase) < nro_iteracion
                    error = MException('cOptACO:actualiza_resultados_iteracion',['Error de programación. planes válidos base no fue inicializado en la iteracion ' num2str(nro_iteracion)]);
                    throw(error)
                end
                [~,indice]=sort([this.PlanesValidosPorIteracionBase(nro_iteracion).Planes.TotexTotal]);
                this.PlanesValidosPorIteracionBase(nro_iteracion).Planes = this.PlanesValidosPorIteracionBase(nro_iteracion).Planes(indice);
                this.ValorMejorResultadoBase(nro_iteracion) = this.PlanesValidosPorIteracionBase(nro_iteracion).Planes(1).TotexTotal;
                if nro_iteracion > 1
                    this.ValorMejorResultadoAcumuladoBase(nro_iteracion) = min(this.ValorMejorResultadoBase(nro_iteracion),this.ValorMejorResultadoAcumuladoBase(nro_iteracion-1));
                else
                    this.ValorMejorResultadoAcumuladoBase(nro_iteracion) = this.ValorMejorResultadoBase(nro_iteracion);
                end
            elseif tipo == 1
                % BL elimina desplaza 
                if length(this.PlanesValidosPorIteracionBLEliminaDesplaza) < nro_iteracion
                    error = MException('cOptACO:actualiza_resultados_iteracion',['Error de programación. planes válidos BL elimina desplaza no fue inicializado para la iteracion ' num2str(nro_iteracion)]);
                    throw(error)
                end
                [~,indice]=sort([this.PlanesValidosPorIteracionBLEliminaDesplaza(nro_iteracion).Planes.TotexTotal]);
                this.PlanesValidosPorIteracionBLEliminaDesplaza(nro_iteracion).Planes = this.PlanesValidosPorIteracionBLEliminaDesplaza(nro_iteracion).Planes(indice);
                if ~isempty(this.PlanesValidosPorIteracionBLEliminaDesplaza(nro_iteracion).Planes)
                    this.ValorMejorResultadoBLEliminaDesplaza(nro_iteracion) = this.PlanesValidosPorIteracionBLEliminaDesplaza(nro_iteracion).Planes(1).TotexTotal;
                else
                    % no hubieron planes válidos de este tipo en la
                    % iteración. Debe haber un error ya que planes duplicados se guardan igual
                    error = MException('cOptACO:actualiza_resultados_iteracion','no existen planes válidos BL elimina desplaza. Tiene que haber un error');
                    throw(error)
                end
                if nro_iteracion > 1
                    this.ValorMejorResultadoAcumuladoBLEliminaDesplaza(nro_iteracion) = min(this.ValorMejorResultadoBLEliminaDesplaza(nro_iteracion),this.ValorMejorResultadoAcumuladoBLEliminaDesplaza(nro_iteracion-1));
                else
                    this.ValorMejorResultadoAcumuladoBLEliminaDesplaza(nro_iteracion) = this.ValorMejorResultadoBLEliminaDesplaza(nro_iteracion);
                end
            elseif tipo == 2
                % BL secuencial completo
                if length(this.PlanesValidosPorIteracionBLSecuencialCompleto) < nro_iteracion
                    error = MException('cOptACO:actualiza_resultados_iteracion',['Error de programación. planes válidos BL secuencial completo no fue inicializado en la iteracion ' num2str(nro_iteracion)]);
                    throw(error)
                end
                [~,indice]=sort([this.PlanesValidosPorIteracionBLSecuencialCompleto(nro_iteracion).Planes.TotexTotal]);
                this.PlanesValidosPorIteracionBLSecuencialCompleto(nro_iteracion).Planes = this.PlanesValidosPorIteracionBLSecuencialCompleto(nro_iteracion).Planes(indice);
                if ~isempty(this.PlanesValidosPorIteracionBLSecuencialCompleto(nro_iteracion).Planes)
                    this.ValorMejorResultadoBLSecuencialCompleto(nro_iteracion) = this.PlanesValidosPorIteracionBLSecuencialCompleto(nro_iteracion).Planes(1).TotexTotal;
                else
                    % no hubieron planes válidos de este tipo en la
                    % iteración. Error
                    error = MException('cOptACO:actualiza_resultados_iteracion','no existen planes válidos BL secuencial completo en la iteracion 1. Tiene que haber un error');
                    throw(error)
                end
                if nro_iteracion > 1
                    this.ValorMejorResultadoAcumuladoBLSecuencialCompleto(nro_iteracion) = min(this.ValorMejorResultadoBLSecuencialCompleto(nro_iteracion),this.ValorMejorResultadoAcumuladoBLSecuencialCompleto(nro_iteracion-1));
                else
                    this.ValorMejorResultadoAcumuladoBLSecuencialCompleto(nro_iteracion) = this.ValorMejorResultadoBLSecuencialCompleto(nro_iteracion);
                end
            end
        end
        
        function actualiza_resultados_globales_iteracion(this, nro_iteracion)
            % planes válidos por iteración base ya fue ordenado. Falta
            % ordenar planes válidos por iteración BL
            if this.pParOpt.considera_busqueda_local
                [~,indice]=sort([this.PlanesValidosPorIteracionBL(nro_iteracion).Planes.TotexTotal]);
                this.PlanesValidosPorIteracionBL(nro_iteracion).Planes = this.PlanesValidosPorIteracionBL(nro_iteracion).Planes(indice);
                this.ValorMejorResultadoBL(nro_iteracion) = this.PlanesValidosPorIteracionBL(nro_iteracion).Planes(1).TotexTotal;
                this.ValorMejorResultado(nro_iteracion) = min(this.ValorMejorResultadoBase(nro_iteracion), this.ValorMejorResultadoBL(nro_iteracion));
            else
                this.ValorMejorResultado(nro_iteracion) = this.ValorMejorResultadoBase(nro_iteracion);
            end
            
            if nro_iteracion == 1
                this.ValorMejorResultadoAcumulado(nro_iteracion) = this.ValorMejorResultado(nro_iteracion);

                if this.pParOpt.considera_busqueda_local
                    this.ValorMejorResultadoAcumuladoBL(nro_iteracion) = this.ValorMejorResultadoBL(nro_iteracion);
                end
            else
                this.ValorMejorResultadoAcumulado(nro_iteracion) = min(this.ValorMejorResultadoAcumulado(nro_iteracion-1),this.ValorMejorResultado(nro_iteracion));
                if this.pParOpt.considera_busqueda_local            
                    this.ValorMejorResultadoAcumuladoBL(nro_iteracion) = min(this.ValorMejorResultadoAcumuladoBL(nro_iteracion-1),this.ValorMejorResultadoBL(nro_iteracion));
                end
            end
            
%this.MejoresPlanes = [this.MejoresPlanes, this.PlanesValidosPorIteracion(nro_iteracion).Planes];
            
            [~,indice]=sort([this.PlanesValidosPorIteracion(nro_iteracion).Planes.TotexTotal]);
            this.PlanesValidosPorIteracion(nro_iteracion).Planes = this.PlanesValidosPorIteracion(nro_iteracion).Planes(indice);
            
            % agrega planes válidos a mejores planes en la medida que no
            % existan
            if ~isempty(this.MejoresPlanes)
                totex_maximo = this.MejoresPlanes(end).TotexTotal;
            else
                totex_maximo = inf;
            end
            
            nuevos_planes_agregados = 0;
            for i = 1:length(this.PlanesValidosPorIteracion(nro_iteracion).Planes)
                plan = this.PlanesValidosPorIteracion(nro_iteracion).Planes(i);
                if plan.TotexTotal < totex_maximo
                    % verifica que plan no exista
                    existe = false;
                    for j = 1:length(this.MejoresPlanes)
                        if plan.compara_proyectos(this.MejoresPlanes(j));
                            existe = true;
                            break;
                        end
                    end
                    if ~existe
                        nuevos_planes_agregados = nuevos_planes_agregados + 1;
                        this.MejoresPlanes = [this.MejoresPlanes plan];
                    end
                end
                if nuevos_planes_agregados >= this.pParOpt.CantidadMejoresPlanes
                    break
                end
            end
            this.CantMejoresPlanesAgregadosPorIter(nro_iteracion) = nuevos_planes_agregados;
            [~,indice]=sort([this.MejoresPlanes.TotexTotal]);
            this.MejoresPlanes = this.MejoresPlanes(indice);
            tope = min(this.pParOpt.CantidadMejoresPlanes, length(this.MejoresPlanes)); %se guarda 1 plan más para calcula maxima diferencia para feromonas
            this.MejoresPlanes = this.MejoresPlanes(1:tope);
        end
        
        function imprime_resultados_actuales(this, detallado)
            this.imprime_resultados_actuales_por_contenedor(this.MejoresPlanes, '\nMejores planes acumulados');
            if detallado
                this.imprime_resultados_actuales_por_contenedor(this.PlanesValidosPorIteracion(end).Planes, '\nPlanes validos por iteracion');
                this.imprime_resultados_actuales_por_contenedor(this.PlanesValidosPorIteracionBase(end).Planes, '\nPlanes validos por iteracion base');
                this.imprime_resultados_actuales_por_contenedor(this.PlanesValidosPorIteracionBL(end).Planes, '\nPlanes validos por iteracion busqueda local');
                if this.pParOpt.BLEliminaDesplazaProyectos > 0            
                    this.imprime_resultados_actuales_por_contenedor(this.PlanesValidosPorIteracionBLEliminaDesplaza(end).Planes, '\nPlanes validos por iteracion bl elimina desplaza ');
                end                
                if this.pParOpt.BLAgregaProyectosFormaSecuencialCompleto > 0
                    this.imprime_resultados_actuales_por_contenedor(this.PlanesValidosPorIteracionBLSecuencialCompleto(end).Planes, '\nPlanes validos por iteracion bl secuencial completo');
                end
            end
        end
        
        function imprime_resultados_actuales_por_contenedor(this, resultados, titulo)
            prot = cProtocolo.getInstance;            
            prot.imprime_texto(titulo);
            texto_etapa = sprintf('%-5s','1');
            for ii = 2:this.pParOpt.CantidadEtapas
            	texto_etapa = [texto_etapa sprintf('%-5s',num2str(ii))];
            end
            if ~isempty(this.PlanOptimo)
                proyectos_plan_optimo = this.PlanOptimo.entrega_proyectos();
            end
            
            texto = sprintf('%-5s %-5s %-10s %-10s %-10s %-5s %-10s %-7s %-12s %-50s', 'No', '*', 'CInv.', 'COper.', 'Total', 'Iter', 'P. base', 'Estr.', 'Cant. Proy', texto_etapa);
            prot.imprime_texto(texto);
            for i = 1:length(resultados)
            	no = resultados(i).entrega_no();
                cinv = resultados(i).CInvTotal;
                coper = resultados(i).COperTotal;
                total = resultados(i).TotexTotal;
                iter = resultados(i).entrega_iteracion();
                plan_base = resultados(i).entrega_plan_base();
                estrategia = resultados(i).entrega_estrategia_busqueda_local();
                cantidad_proyectos = resultados(i).cantidad_acumulada_proyectos();
                texto_etapa = [];
                texto_tag = '';
                if ~isempty(this.PlanOptimo)
                    proy_actuales = resultados(i).entrega_proyectos();
                    if sum(ismember(proyectos_plan_optimo, proy_actuales)) == length(proyectos_plan_optimo)
                        texto_tag = '*';
                    end
                end
                
                for jj = 1:this.pParOpt.CantidadEtapas
                    proy_cum = resultados(i).cantidad_acumulada_proyectos(jj);
                    texto_etapa = [texto_etapa sprintf('%-5s',num2str(proy_cum))];
                end
                texto = sprintf('%-5s %-5s %-10s %-10s %-10s %-5s %-10s %-7s %-12s %-50s', ...
                num2str(no), ...
                texto_tag, ...
                num2str(cinv), ...
                num2str(coper),...
                num2str(total), ...
                num2str(iter),...
                num2str(plan_base),...
                num2str(estrategia),...
                num2str(cantidad_proyectos),...
                texto_etapa);
                prot.imprime_texto(texto);
            end
        end
        
        function actualiza_feromonas(this, varargin)
            % varargin indica la iteración. Se utiliza para cargar
            % resultados parciales
            if nargin > 1
                iter = varargin{1};
                mejores_planes_parciales = [];
                for i = 1:iter
                    mejores_planes_parciales = [mejores_planes_parciales, this.PlanesValidosPorIteracion(iter).Planes];
                end
                
                [~,indice]=sort([mejores_planes_parciales.TotexTotal]);
                mejores_planes_parciales = mejores_planes_parciales(indice);
                mejores_planes = mejores_planes_parciales(1);
                for i = 2:length(mejores_planes_parciales)
                    plan = mejores_planes_parciales(i);
                    existe = false;
                    for j = 1:length(mejores_planes)
                        if plan.compara_proyectos(mejores_planes(j));
                            existe = true;
                            break;
                        end
                    end
                    if ~existe
                        mejores_planes = [mejores_planes plan];
                    end
                    if length(mejores_planes) == this.pParOpt.CantidadMejoresPlanes
                        break;
                    end
                end
            else
                mejores_planes = this.MejoresPlanes;
            end

            cantidad_mejores_planes = length(mejores_planes);            
            suma_inv_fobj_mejores_planes = 0;
            max_fobj = mejores_planes(end).TotexTotal;
            for i = 1:cantidad_mejores_planes
                suma_inv_fobj_mejores_planes = suma_inv_fobj_mejores_planes + max_fobj/mejores_planes(i).TotexTotal;
            end
            
            if this.iNivelDebug > 1
                prot = cProtocolo.getInstance;
                texto = sprintf('%-5s %-7s %-13s %-50s', 'Rank', 'Etapa', 'dvalor fer', 'Proyectos');
                prot.imprime_texto(texto);
                for i = 1:length(mejores_planes)
                    primero = true;
                    val_actual = mejores_planes(i).TotexTotal;
                    dvalor = 100*(1-this.pParOpt.TasaEvaporacion)*max_fobj/val_actual/suma_inv_fobj_mejores_planes;
                    for j = 1:length(mejores_planes(i).Plan) %etapas
                        if ~isempty(mejores_planes(i).Plan(j).Proyectos)
                            id_proy = '';
                            for k = 1:length(mejores_planes(i).Plan(j).Proyectos)
                                indice = mejores_planes(i).Plan(j).Proyectos(k);
                                id_proy = [id_proy ' ' num2str(indice)];
                            end
                            if primero
                                texto = sprintf('%-5s %-7s %-13s %-50s', num2str(i), num2str(j), num2str(dvalor), id_proy);
                                primero = false;
                            else
                                texto = sprintf('%-5s %-7s %-13s %-50s', '', num2str(j), ' ', id_proy);
                            end
                            prot.imprime_texto(texto);    
                        end
                    end
                end
            end
            
            dfer_proyectos = zeros(this.pParOpt.CantidadEtapas + 1, this.pAdmProy.CantidadProyectos);
            
            for id_plan = 1:cantidad_mejores_planes
                val_actual = mejores_planes(id_plan).TotexTotal;
                dvalor = 100*(1-this.pParOpt.TasaEvaporacion)*max_fobj/val_actual/suma_inv_fobj_mejores_planes;
                indice_proyectos_totales = mejores_planes(id_plan).entrega_proyectos();
                for id_proy = 1:this.pAdmProy.CantidadProyectos
                    if ~isempty(find(indice_proyectos_totales == id_proy, 1))
                        % quiere decir que proyecto se encuentra en el plan
                        etapa = mejores_planes(id_plan).entrega_etapa_proyecto(id_proy);
                        dfer_proyectos(etapa,id_proy) = dfer_proyectos(etapa,id_proy) + dvalor;
                    else
                        % proyecto no se encuentra en el plan. Feromona se
                        % agrega a etapa "sin proyecto"
                        dfer_proyectos(end,id_proy) = dfer_proyectos(end,id_proy) + dvalor;
                    end
                end
            end
            
            % guarda dfer
            this.pFeromona.DFerActual = dfer_proyectos;
            
            if this.iNivelDebug > 1
                prot.imprime_matriz(dfer_proyectos', 'dfer proyectos');
            end
            
            % Evapora feromonas
            this.pFeromona.evapora_feromonas(this.pParOpt.TasaEvaporacion);
%this.pFeromona.imprime_feromonas();

            % incrementa feromonas proyectos
            this.pFeromona.FerProyectos = this.pFeromona.FerProyectos + dfer_proyectos;
        end
        
        function calcula_costos_totales(this,plan)
            %costos de inversion
            q = (1 + this.pParOpt.TasaDescuento);
            detapa = this.pParOpt.DeltaEtapa;
            costo_inversion= zeros(this.pParOpt.CantidadEtapas,1);
            costo_inversion_tactual = zeros(this.pParOpt.CantidadEtapas,1);
            for etapa = 1:length(plan.Plan) %cantidad etapas
                for proyecto = 1:length(plan.Plan(etapa).Proyectos) %cantidad planes por etapa
                    indice = plan.Plan(etapa).Proyectos(proyecto);
                    %costo_inv = this.pAdmProy.Proyectos(indice).entrega_costos_inversion();
                    factor_desarrollo = this.pParOpt.entrega_factor_costo_desarrollo_proyectos();
                    %costo_inv = round(costo_inv*factor_desarrollo,5);
                    costo_inv = this.pAdmProy.calcula_costo_inversion_proyecto(this.pAdmProy.entrega_proyecto(indice), etapa, plan, factor_desarrollo);
                    costo_inversion(etapa) = costo_inversion(etapa) + costo_inv;
                    costo_inversion_tactual(etapa) = costo_inversion_tactual(etapa) + costo_inv/q^(detapa*etapa);
                end
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
                costo_operacion(i) = plan.entrega_costo_operacion(i)/1000000;
                costo_operacion_tactual(i) = costo_operacion(i)/q^(detapa*i);
                costo_generacion(i) = plan.entrega_costo_generacion(i)/1000000;
                costo_generacion_tactual(i) = costo_generacion(i)/q^(detapa*i);
                costo_ens(i) = plan.entrega_costo_ens(i)/1000000;
                costo_ens_tactual(i) = costo_ens(i)/q^(detapa*i);
                costo_recorte_res(i) = plan.entrega_costo_recorte_res(i)/1000000;
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

        function cinv = calcula_costos_inversion_actual(this,plan)
            %costos de inversion
            q = (1 + this.pParOpt.TasaDescuento);
            detapa = this.pParOpt.DeltaEtapa;
            cinv = 0;
            for etapa = 1:length(plan.Plan) %cantidad etapas
                for proyecto = 1:length(plan.Plan(etapa).Proyectos) %cantidad planes por etapa
                    indice = plan.Plan(etapa).Proyectos(proyecto);
                    %costo_inv = this.pAdmProy.Proyectos(indice).entrega_costos_inversion();
                    factor_desarrollo = this.pParOpt.entrega_factor_costo_desarrollo_proyectos();
                    %costo_inv = round(costo_inv*factor_desarrollo,5);
                    costo_inv = this.pAdmProy.calcula_costo_inversion_proyecto(this.pAdmProy.entrega_proyecto(indice), etapa, plan, factor_desarrollo);
                    cinv = cinv + costo_inv/q^(detapa*etapa);
                end
            end
        end
        
        function [cinv, coper, ctotal] = calcula_costos_parciales(this,plan, etapa)
            cinv = 0;
            for proyecto = 1:length(plan.Plan(etapa).Proyectos) %cantidad planes por etapa
                indice = plan.Plan(etapa).Proyectos(proyecto);
                costo = this.pAdmProy.calcula_costo_inversion_proyecto(this.pAdmProy.entrega_proyecto(indice), etapa, plan);
                cinv = cinv + costo;
            end
            
            %costos de operacion
            coper = plan.entrega_costo_operacion(etapa)/1000000;
            ctotal = cinv + coper;
        end
        
        function delta_cinv = calcula_delta_cinv_elimina_desplaza_proyectos(this, plan, nro_etapa, proyectos_eliminar, proyectos_desplazar, etapas_originales_desplazar, etapas_desplazar)
            cinv_actual = plan.CInvTotal;
            
            % "crea" plan objetivo. 
            plan_objetivo = cPlanExpansion(9999997);
            plan_objetivo.Plan = plan.Plan;

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
        
        function vpn = calcula_vpn_proyectos(this, plan, proyectos, etapas)
            q = (1 + this.pParOpt.TasaDescuento);
            detapa = this.pParOpt.DeltaEtapa;
            vpn = 0;
            for i = 1:length(proyectos)
                costo = this.pAdmProy.calcula_costo_inversion_proyecto(this.pAdmProy.entrega_proyecto(proyectos(i)), etapas(i), plan);            
                vpn = vpn + costo/q^(detapa*etapas(i));
            end
        end
        
        function imprime_planes_validos(this, nro_iteracion)
            disp('Nro. plan    Evaluacion')
            for i = 1:length(this.PlanesValidosPorIteracionBase(nro_iteracion).Planes)
                disp(strcat(num2str(this.PlanesValidosPorIteracionBase(nro_iteracion).Planes(i).NroPlan), '---', ...
                            num2str(this.PlanesValidosPorIteracionBase(nro_iteracion).Planes(i).TotexTotal)));
            end
            for i = 1:length(this.PlanesValidosPorIteracionBL(nro_iteracion).Planes)
                disp(strcat(num2str(this.PlanesValidosPorIteracionBL(nro_iteracion).Planes(i).NroPlan), '---', ...
                            num2str(this.PlanesValidosPorIteracionBL(nro_iteracion).Planes(i).TotexTotal)));
            end
        end

        function imprime_mejores_planes(this)
            disp('Nro. plan    Evaluacion')
            for i = 1:length(this.MejoresPlanes)
                disp(strcat(num2str(this.MejoresPlanes(i).NroPlan), '---', ...
                            num2str(this.MejoresPlanes(i).TotexTotal)));
            end
        end
        
        function evalua_resultado_y_guarda_en_plan(this, plan, evaluacion, nro_etapa)
            if this.pParOpt.PlanValidoConENS && this.pParOpt.PlanValidoConRecorteRES
                estructura_eval.Valido = evaluacion.ExisteResultado;
            elseif ~this.pParOpt.PlanValidoConENS && this.pParOpt.PlanValidoConRecorteRES
                estructura_eval.Valido = evaluacion.ExisteResultado && ...
                                        (isempty(evaluacion.PuntosOperacionInvalidos)) && ...
                                        evaluacion.entrega_ens() == 0;
            elseif this.pParOpt.PlanValidoConENS && ~this.pParOpt.PlanValidoConRecorteRES
                estructura_eval.Valido = evaluacion.ExisteResultado && ...
                                        (isempty(evaluacion.PuntosOperacionInvalidos)) && ...
                                        evaluacion.entrega_recorte_res() == 0;
            elseif ~this.pParOpt.PlanValidoConENS && ~this.pParOpt.PlanValidoConRecorteRES
                estructura_eval.Valido = evaluacion.ExisteResultado && ...
                                        (isempty(evaluacion.PuntosOperacionInvalidos)) && ...
                                        evaluacion.entrega_ens() == 0 && ...
                                        evaluacion.entrega_recorte_res() == 0;
            end
            costo_generacion = 0;
            costo_operacion = 0;
            costo_recorte_res = 0;
            costo_ens = 0;
            ens = 0;
            recorte_res = 0;
            if evaluacion.ExisteResultado 
                estructura_eval.Existe = true;
                for i = 1:this.pAdmSc.CantidadPuntosOperacion
                    representatividad =this.pAdmSc.RepresentatividadPuntosOperacion(i);
                    ens_po = sum(evaluacion.ENSConsumos(:,i));
                    ens = ens + ens_po*representatividad;
                    recorte_res_po = sum(evaluacion.RecorteGeneradoresRES(:,i));
                    recorte_res = recorte_res + recorte_res_po*representatividad;
                    costo_generacion = costo_generacion + evaluacion.CostoGeneracion(i)*representatividad;
                    costo_ens = costo_ens + evaluacion.CostoENS(i)*representatividad;
                    costo_recorte_res = costo_recorte_res + evaluacion.CostoRecorteGeneradoresRES(i)*representatividad;
                    costo_operacion = costo_operacion + (evaluacion.CostoGeneracion(i)+evaluacion.CostoENS(i)+evaluacion.CostoRecorteGeneradoresRES(i))*representatividad;
                end
                estructura_eval.CostoGeneracion = costo_generacion;
                estructura_eval.ENS = ens;
                estructura_eval.CostoENS = costo_ens;
                estructura_eval.RecorteRES = recorte_res;
                estructura_eval.CostoRecorteRES = costo_recorte_res;                
                estructura_eval.CostoOperacion = costo_operacion;
                estructura_eval.PuntosOperacionInvalidos = evaluacion.PuntosOperacionInvalidos;
                estructura_eval.LineasSobrecargadas = evaluacion.NombreElementosSobrecargados;
                estructura_eval.NivelSobrecarga = evaluacion.NivelSobrecarga;
                estructura_eval.LineasFlujoMaximo = evaluacion.entrega_lineas_flujo_maximo();
                estructura_eval.TrafosFlujoMaximo = evaluacion.entrega_trafos_flujo_maximo();
                estructura_eval.LineasPocoUso = evaluacion.entrega_lineas_poco_uso();
                estructura_eval.TrafosPocoUso = evaluacion.entrega_trafos_poco_uso();
                
            else
                estructura_eval.CostoGeneracion = 9999999999999;
                estructura_eval.ENS = 9999999999999;
                estructura_eval.CostoENS = 9999999999999;
                estructura_eval.RecorteRES = 9999999999999;
                estructura_eval.CostoRecorteRES = 9999999999999;                
                estructura_eval.CostoOperacion = 9999999999999;
                estructura_eval.PuntosOperacionInvalidos = 1;
                estructura_eval.LineasSobrecargadas = evaluacion.NombreElementosSobrecargados;
                estructura_eval.NivelSobrecarga = evaluacion.NivelSobrecarga;
                estructura_eval.LineasFlujoMaximo = evaluacion.entrega_lineas_flujo_maximo();
                estructura_eval.TrafosFlujoMaximo = evaluacion.entrega_trafos_flujo_maximo();
                estructura_eval.LineasPocoUso = evaluacion.entrega_lineas_poco_uso();
                estructura_eval.TrafosPocoUso = evaluacion.entrega_trafos_poco_uso();
                estructura_eval.Existe = false;
                % no existe resultado para el plan
                % imprime plan
                prot = cProtocolo.getInstance;
                prot.imprime_texto('Error de programacion. No existen resultados en la evaluacion. Se imprime plan fallido');
                prot.imprime_texto(['No. etapa: ' num2str(nro_etapa)]);
                plan.agrega_nombre_proyectos(this.pAdmProy);
                plan.imprime_plan_expansion();
            end
            plan.inserta_evaluacion_etapa(nro_etapa, estructura_eval);
        end

        function estructura_eval = entrega_estructura_evaluacion(this, evaluacion)
            if this.pParOpt.PlanValidoConENS && this.pParOpt.PlanValidoConRecorteRES
                estructura_eval.Valido = evaluacion.ExisteResultado;
            elseif ~this.pParOpt.PlanValidoConENS && this.pParOpt.PlanValidoConRecorteRES
                estructura_eval.Valido = evaluacion.ExisteResultado && ...
                                        (isempty(evaluacion.PuntosOperacionInvalidos)) && ...
                                        evaluacion.entrega_ens() == 0;
            elseif this.pParOpt.PlanValidoConENS && ~this.pParOpt.PlanValidoConRecorteRES
                estructura_eval.Valido = evaluacion.ExisteResultado && ...
                                        (isempty(evaluacion.PuntosOperacionInvalidos)) && ...
                                        evaluacion.entrega_recorte_res() == 0;
            elseif ~this.pParOpt.PlanValidoConENS && ~this.pParOpt.PlanValidoConRecorteRES
                estructura_eval.Valido = evaluacion.ExisteResultado && ...
                                        (isempty(evaluacion.PuntosOperacionInvalidos)) && ...
                                        evaluacion.entrega_ens() == 0 && ...
                                        evaluacion.entrega_recorte_res() == 0;
            end
            costo_generacion = 0;
            costo_operacion = 0;
            costo_recorte_res = 0;
            costo_ens = 0;
            ens = 0;
            recorte_res = 0;
            if evaluacion.ExisteResultado 
                estructura_eval.Existe = true;
                for i = 1:this.pAdmSc.CantidadPuntosOperacion
                    representatividad =this.pAdmSc.RepresentatividadPuntosOperacion(i);
                    ens_po = sum(evaluacion.ENSConsumos(:,i));
                    ens = ens + ens_po*representatividad;
                    recorte_res_po = sum(evaluacion.RecorteGeneradoresRES(:,i));
                    recorte_res = recorte_res + recorte_res_po*representatividad;
                    costo_generacion = costo_generacion + evaluacion.CostoGeneracion(i)*representatividad;
                    costo_ens = costo_ens + evaluacion.CostoENS(i)*representatividad;
                    costo_recorte_res = costo_recorte_res + evaluacion.CostoRecorteGeneradoresRES(i)*representatividad;
                    costo_operacion = costo_operacion + (evaluacion.CostoGeneracion(i)+evaluacion.CostoENS(i)+evaluacion.CostoRecorteGeneradoresRES(i))*representatividad;
                end
                estructura_eval.CostoGeneracion = costo_generacion;
                estructura_eval.ENS = ens;
                estructura_eval.CostoENS = costo_ens;
                estructura_eval.RecorteRES = recorte_res;
                estructura_eval.CostoRecorteRES = costo_recorte_res;                
                estructura_eval.CostoOperacion = costo_operacion;
                estructura_eval.PuntosOperacionInvalidos = evaluacion.PuntosOperacionInvalidos;
                estructura_eval.LineasSobrecargadas = evaluacion.NombreElementosSobrecargados;
                estructura_eval.NivelSobrecarga = evaluacion.NivelSobrecarga;
                estructura_eval.LineasFlujoMaximo = evaluacion.entrega_lineas_flujo_maximo();
                estructura_eval.TrafosFlujoMaximo = evaluacion.entrega_trafos_flujo_maximo();
                estructura_eval.LineasPocoUso = evaluacion.entrega_lineas_poco_uso();
                estructura_eval.TrafosPocoUso = evaluacion.entrega_trafos_poco_uso();
                
            else
                estructura_eval.CostoGeneracion = 9999999999999;
                estructura_eval.ENS = 9999999999999;
                estructura_eval.CostoENS = 9999999999999;
                estructura_eval.RecorteRES = 9999999999999;
                estructura_eval.CostoRecorteRES = 9999999999999;                
                estructura_eval.CostoOperacion = 9999999999999;
                estructura_eval.PuntosOperacionInvalidos = 1;
                estructura_eval.LineasSobrecargadas = evaluacion.NombreElementosSobrecargados;
                estructura_eval.NivelSobrecarga = evaluacion.NivelSobrecarga;
                estructura_eval.LineasFlujoMaximo = evaluacion.entrega_lineas_flujo_maximo();
                estructura_eval.TrafosFlujoMaximo = evaluacion.entrega_trafos_flujo_maximo();
                estructura_eval.LineasPocoUso = evaluacion.entrega_lineas_poco_uso();
                estructura_eval.TrafosPocoUso = evaluacion.entrega_trafos_poco_uso();
                estructura_eval.Existe = false;
                % no existe resultado para el plan
                % imprime plan
                prot = cProtocolo.getInstance;
                prot.imprime_texto('Error de programacion. No existen resultados en la evaluacion!!!');
            end            
        end
        
        function resultados = optimiza(this)
            tic
            t_inicio = toc;
            this.CantPlanesValidos = 0;
            if this.iNivelDebug > 0
                prot = cProtocolo.getInstance;
                prot.imprime_texto('Comienzo optimizacion heuristica ACO');
                prot.imprime_texto(['No. etapas: ' num2str(this.pParOpt.CantidadEtapas)]);
                prot.imprime_texto(['No. hormigas: ' num2str(this.pParOpt.CantidadHormigas)]);
            end
            
            if this.ExistenResultadosParciales
                nro_iteracion = this.ItResultadosParciales;
            else
                % Guarda principales criterios de optimizacion
                nro_iteracion = 0;
                this.guarda_parametros_optimizacion();
            end
                        
            % optimizacion
            criterio_salida = false;
            if ~isempty(this.PlanOptimo)
                text = sprintf('%-5s %-5s %-10s %-10s %-7s %-7s %-7s %-7s %-7s %-7s %-10s %-10s %-10s','It','#BP','FBPIt','FBPG','GAP', 'dTB','dT11','dT12','dT2','dTAcc','#NBP Iter','Tot BP','Tot WBP');                
            else
                text = sprintf('%-5s %-5s %-10s %-10s %-7s %-7s %-7s %-7s %-7s %-10s %-10s %-10s','It','#Pr','FBPIt','FBPG','dTB','dT11','dT12','dT2','dTAcc','#NBP Iter','Tot BP','Tot WBP');
            end
            
            disp(text);
            while true
                if nro_iteracion > this.pParOpt.MaxItPlanificacion
                    break;
                end
                
                if criterio_salida == true
                    break;
                end
                                
                %disp(strcat('Nro. iteracion: ',num2str(nro_iteracion)));
                nro_iteracion = nro_iteracion + 1;
                
                this.inicializa_contenedores_iteracion(nro_iteracion);

                tcomienzo_it = toc;
                nivel_debug_original = this.iNivelDebug;
                %planes base
                if this.pParOpt.computo_paralelo()
                    this.iNivelDebug = 0;
                    this.genera_planes_base_computo_paralelo(nro_iteracion);
                    this.iNivelDebug = nivel_debug_original;
                else
                    this.genera_planes_base(nro_iteracion);
                end
                this.actualiza_resultados_parciales_iteracion(nro_iteracion, 0); %0 indica que es base
                this.Resultados.TiempoBase(nro_iteracion) = toc - tcomienzo_it;
                t_bl_elimina_desplaza_normal_11 = 0;
                t_bl_elimina_desplaza_comienzo_12 = 0;
                t_bl_secuencial_completo_2 = 0;
                   
                if this.pParOpt.considera_busqueda_local()
                    % planes búsqueda local
                    if this.iNivelDebug > 0
                        prot = cProtocolo.getInstance;
                        prot.imprime_texto(['Comienzo de busqueda local en it ' num2str(nro_iteracion)]);
                    end
                    planes_originales_bl = this.entrega_planes_busqueda_local(nro_iteracion);
                    indice_planes = nro_iteracion*1000 + this.pParOpt.CantidadHormigas;
                    if this.pParOpt.BLEliminaDesplazaProyectos > 0
                        proy_al_comienzo = this.pParOpt.BLEliminaDesplazaProyAlComienzo;
                        proy_normal = this.pParOpt.BLEliminaDesplazaProyNormal;
                        tcomienzo_busqueda_local = toc;
                        if proy_al_comienzo
                            tcomienzo_caso_actual = toc;
                            if this.pParOpt.computo_paralelo()
                                this.iNivelDebug = 0;
                                [planes, indice_planes] = this.genera_planes_bl_elimina_desplaza_paralelo(nro_iteracion, planes_originales_bl, indice_planes, true);
                                t_bl_elimina_desplaza_comienzo_12 = toc - tcomienzo_caso_actual;
                                this.iNivelDebug = nivel_debug_original;
                            else
                                [planes, indice_planes] = this.genera_planes_bl_elimina_desplaza(nro_iteracion, planes_originales_bl, indice_planes, true);
                                t_bl_elimina_desplaza_comienzo_12 = toc - tcomienzo_caso_actual;
                            end
                            this.guarda_planes_generados(planes, nro_iteracion, 1);
                        end
                    
                        if proy_normal
                            tcomienzo_caso_actual = toc;
                            if this.pParOpt.computo_paralelo()
                                this.iNivelDebug = 0;
                                [planes, indice_planes] = this.genera_planes_bl_elimina_desplaza_paralelo(nro_iteracion, planes_originales_bl, indice_planes, false);
                                t_bl_elimina_desplaza_normal_11 = toc - tcomienzo_caso_actual;
                                this.iNivelDebug = nivel_debug_original;
                            else
                                [planes, indice_planes] = this.genera_planes_bl_elimina_desplaza(nro_iteracion, planes_originales_bl, indice_planes, false);
                                t_bl_elimina_desplaza_normal_11 = toc - tcomienzo_caso_actual;
                            end
                            this.guarda_planes_generados(planes, nro_iteracion, 1);
                        end
                    
                        this.actualiza_resultados_parciales_iteracion(nro_iteracion, 1); %4 indica que es bl elimina desplaza
                        this.Resultados.TiempoBusquedaLocalEliminaDesplaza(nro_iteracion) = toc - tcomienzo_busqueda_local;
                    end
                    if this.pParOpt.BLAgregaProyectosFormaSecuencialCompleto > 0
                        tcomienzo_busqueda_local = toc;
                        if this.pParOpt.computo_paralelo()
                            this.iNivelDebug = 0;
                            [planes, indice_planes] = this.genera_planes_busqueda_local_secuencial_completo_paralelo(nro_iteracion, planes_originales_bl, indice_planes);
                            this.iNivelDebug = nivel_debug_original;
                        else
                            [planes, indice_planes] = this.genera_planes_busqueda_local_secuencial_completo(nro_iteracion, planes_originales_bl, indice_planes);
                        end
                        this.guarda_planes_generados(planes, nro_iteracion, 2);
                        this.actualiza_resultados_parciales_iteracion(nro_iteracion, 2); %2 indica que es bl secuencial completo
                        this.Resultados.TiempoBusquedaLocalSecuencialCompleto(nro_iteracion) = toc - tcomienzo_busqueda_local;
                        t_bl_secuencial_completo_2 = this.Resultados.TiempoBusquedaLocalSecuencialCompleto(nro_iteracion);
                    end
                end
                
                % fin genera planes iteracion
                
                this.actualiza_resultados_globales_iteracion(nro_iteracion);
                
                this.guarda_resultados_iteracion(nro_iteracion);
                                    
                if this.iNivelDebug > 0
                    detallado = true;
                    this.imprime_resultados_actuales(detallado);
                end

                %libera memoria
                for i = 1:length(this.PlanesValidosPorIteracion(nro_iteracion).Planes)
                    this.PlanesValidosPorIteracion(nro_iteracion).Planes(i).ResultadoEvaluacion = [];
                end
                
                this.actualiza_feromonas();
                if this.iNivelDebug > 0
                    this.pFeromona.imprime_feromonas(nro_iteracion);
                end
                t_acumulado = toc - t_inicio;

                criterio_salida = this.evalua_criterio_salida();
                if ~isempty(this.PlanOptimo)
                    gap = round((this.MejoresPlanes(1).TotexTotal - this.PlanOptimo.TotexTotal)/this.PlanOptimo.TotexTotal*100,3);
                    texto_gap = [num2str(gap) '%'];

                    text = sprintf('%-5s %-5s %-10s %-10s %-7s %-7s %-7s %-7s %-7s %-7s %-10s %-10s %-10s',num2str(nro_iteracion),...
                           num2str(this.MejoresPlanes(1).cantidad_acumulada_proyectos()),...
                           num2str(this.ValorMejorResultado(nro_iteracion)),...
                           num2str(this.MejoresPlanes(1).TotexTotal),...
                           texto_gap,...
                           num2str(round(this.Resultados.TiempoBase(nro_iteracion),1)), ...
                           num2str(round(t_bl_elimina_desplaza_normal_11,1)), ...
                           num2str(round(t_bl_elimina_desplaza_comienzo_12,1)), ...
                           num2str(round(t_bl_secuencial_completo_2,1)), ...
                           num2str(round(t_acumulado,1)), ...
                           num2str(this.CantMejoresPlanesAgregadosPorIter(nro_iteracion)), ...
                           num2str(this.MejoresPlanes(1).TotexTotal), ...
                           num2str(this.MejoresPlanes(end).TotexTotal));
                else
                    text = sprintf('%-5s %-5s %-10s %-10s %-7s %-7s %-7s %-7s %-7s %-10s %-10s %-10s',num2str(nro_iteracion),...
                           num2str(this.MejoresPlanes(1).cantidad_acumulada_proyectos()),...
                           num2str(this.ValorMejorResultado(nro_iteracion)),...
                           num2str(this.MejoresPlanes(1).TotexTotal),...
                           num2str(round(this.Resultados.TiempoBase(nro_iteracion),1)), ...
                           num2str(round(t_bl_elimina_desplaza_normal_11,1)), ...
                           num2str(round(t_bl_elimina_desplaza_comienzo_12,1)), ...
                           num2str(round(t_bl_secuencial_completo_2,1)), ...
                           num2str(round(t_acumulado,1)), ...
                           num2str(this.CantMejoresPlanesAgregadosPorIter(nro_iteracion)), ...
                           num2str(this.MejoresPlanes(1).TotexTotal), ...
                           num2str(this.MejoresPlanes(end).TotexTotal));
                end

                disp(text);
                if this.iNivelDebug > 0
                    prot.imprime_texto(['Mejor plan hasta iteracion ' num2str(nro_iteracion)]);
                    this.MejoresPlanes(1).agrega_nombre_proyectos(this.pAdmProy);
                    this.MejoresPlanes(1).imprime();
                end

                if this.iNivelDebug > 2
                    prot.imprime_texto('Se vuelve a evaluar mejor plan');
                    plan_prueba = cPlanExpansion(99999997);
                    plan_prueba.inserta_iteracion(nro_iteracion);
                    plan_prueba.inserta_busqueda_local(false);
                    plan_prueba.inserta_plan_base(1);
                    plan_prueba.Plan = this.MejoresPlanes(1).Plan;
                    plan_prueba.inserta_sep_original(this.pSEP.crea_copia());
                    for nro_etapa = 1:this.pParOpt.CantidadEtapas
                        valido = this.evalua_plan(plan_prueba, nro_etapa);
                        if ~valido
                            texto = 'Error de programacion. Mejor plan obtenido hasta ahora no es valido';
                            error = MException('cOptACO:optimiza',texto);
                            throw(error)
                        end
                    end
                    this.calcula_costos_totales(plan_prueba);
    
                	texto = 'Imprime plan prueba para comparar (elimina/desplaza harta memoria)';
                    prot.imprime_texto(texto)

                    plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                    plan_prueba.imprime();
                end
            end %fin optimizacion
            
            this.Resultados.TiempoTotal = toc;
            this.Resultados.MejoresPlanes = this.MejoresPlanes;
            this.Resultados.PlanesValidosPorIteracion = this.PlanesValidosPorIteracion;
            this.Resultados.PlanesValidosPorIteracionBase = this.PlanesValidosPorIteracionBase;
            this.Resultados.PlanesValidosPorIteracionBL = this.PlanesValidosPorIteracionBL;
            this.Resultados.PlanesValidosPorIteracionBLEliminaDesplaza = this.PlanesValidosPorIteracionBLEliminaDesplaza;
            this.Resultados.PlanesValidosPorIteracionBLSecuencialCompleto = this.PlanesValidosPorIteracionBLSecuencialCompleto;
            
            resultados = this.Resultados;
        end

        function genera_planes_base(this, nro_iteracion)
            if this.iNivelDebug > 0
                prot = cProtocolo.getInstance;
            end
            
            for nro_plan =1:this.pParOpt.CantidadHormigas
                if this.iNivelDebug > 0
                    texto = ['Genera plan ' num2str(nro_plan) '/' num2str(this.pParOpt.CantidadHormigas) ' en it. ' num2str(nro_iteracion) '. Nro planes validos: ' num2str(this.CantPlanesValidos)];
                	prot.imprime_texto(texto);
                end
                    
                if nro_iteracion > 1 && nro_plan == 1
                    if nro_iteracion >= this.pParOpt.PlanMasProbableFeromonasDesdeIteracion 
                        pPlan = this.genera_plan_mas_probable(nro_iteracion*1000 + nro_plan, false);
                    else
                        pPlan = this.genera_plan_mas_probable(nro_iteracion*1000 + nro_plan, true);
                    end
                elseif nro_iteracion > 1 && nro_plan == 2
                    % genera plan en base a feromonas entregadas
                    pPlan = this.genera_plan_feromonas_entregadas(nro_iteracion*1000 + nro_plan);
                else
                    pPlan = this.genera_plan_expansion(nro_iteracion*1000 + nro_plan);
                end
                
                pPlan.inserta_iteracion(nro_iteracion);
                pPlan.inserta_busqueda_local(false);
                
                sep_actual = this.pSEP.crea_copia();

                % evalua plan de expansión por cada etapa
                nro_etapa = 0;
                while nro_etapa < this.pParOpt.CantidadEtapas
                	nro_etapa = nro_etapa +1;
                    
                    pPlan.CantidadReparaciones = 0;
                    
                    % agrega proyectos al sep
                    for j = 1:length(pPlan.Plan(nro_etapa).Proyectos)
                        indice = pPlan.Plan(nro_etapa).Proyectos(j);
                        proyecto = this.pAdmProy.entrega_proyecto(indice);
                        if ~sep_actual.agrega_proyecto(proyecto)
                            % Error (probablemente de programación). 
                            texto = ['Error de programacion. Plan ' num2str(pPlan.entrega_no()) ' no pudo ser implementado en SEP en etapa ' num2str(etapa_previa)];
                            error = MException('genera_planes_base:genera_planes_bl_elimina_desplaza',texto);
                            throw(error)
                        end
                    end

                    this.evalua_red(sep_actual, nro_etapa, [], false); % false indica que proyectos se eliminan
                    this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actual.entrega_opf().entrega_evaluacion(), nro_etapa);
                    valido = pPlan.es_valido(nro_etapa);

                    proy_candidatos_restringidos = [];
                    cant_intentos_reparacion = 0;
                    while ~valido && (pPlan.CantidadReparaciones < this.pParOpt.MaxNroReparacionesPorEtapa)
                        if this.iNivelDebug > 1
                            texto = ['   Plan ' num2str(pPlan.entrega_no()) ' no es valido en etapa ' num2str(nro_etapa) ...
                                ' (ENS: ' num2str(pPlan.entrega_ens(nro_etapa)) ' Recorte RES: ' num2str(pPlan.entrega_recorte_res(nro_etapa)) ...
                                '). Se intenta reparar. Cantidad de reparaciones: ' num2str(pPlan.CantidadReparaciones)];
                            prot.imprime_texto(texto);
                        end

                        cant_intentos_reparacion = cant_intentos_reparacion + 1;
                        estructura_eval_base = this.entrega_estructura_evaluacion(sep_actual.entrega_opf().entrega_evaluacion());
                        ens_base = estructura_eval_base.ENS;
                        recorte_res_base = estructura_eval_base.RecorteRES;
                        
                        %proy_seleccionados = this.repara_plan(pPlan, nro_etapa);
                        proy_candidatos = this.entrega_proyectos_candidatos_repara_plan(pPlan, nro_etapa,proy_candidatos_restringidos);
                        % proy_candidatos(nro_candidato).seleccionado = indice;
                        % proy_candidatos(nro_candidato).etapa_seleccionado = 0;
                        % proy_candidatos(nro_candidato).conectividad_agregar = [];
                        % proy_candidatos(nro_candidato).conectividad_adelantar = [];
                        % proy_candidatos(nro_candidato).etapas_orig_conectividad_adelantar = [];
                        
                        if isempty(proy_candidatos)
                        	valido = false;
%valido = this.evalua_plan(pPlan, nro_etapa, true);
                            if this.iNivelDebug > 1
                                texto = ['   Plan ' num2str(pPlan.entrega_no()) ' no se pudo reparar. Se descarta'];
                            	prot.imprime_texto(texto);
                            end
                            break;
                        else
                            if this.iNivelDebug > 1
                                texto = ['   Proy. candidatos etapa ' num2str(nro_etapa) ' intento ' num2str(cant_intentos_reparacion) ': '];
                                for kk = 1:length(proy_candidatos)
                                    texto = [texto num2str(proy_candidatos(kk).seleccionado)];
                                end
                                prot.imprime_texto(texto);
                                texto = '   Proy. restringidos: ';
                                for kk = 1:length(proy_candidatos_restringidos)
                                    texto = [texto num2str(proy_candidatos_restringidos(kk))];
                                end
                                prot.imprime_texto(texto);
                            end
                            
                        end
                        es_necesario_actualizar_sep = true;
                        mejor_intento = 0;
                        for cand = 1:length(proy_candidatos)
                            % evalua candidato
                            for k = 1:length(proy_candidatos(cand).conectividad_adelantar)
                                proyecto = this.pAdmProy.entrega_proyecto(proy_candidatos(cand).conectividad_adelantar(k));
                                sep_actual.agrega_proyecto(proyecto);
                            end
                            for k = 1:length(proy_candidatos(cand).conectividad_agregar)
                                proyecto = this.pAdmProy.entrega_proyecto(proy_candidatos(cand).conectividad_agregar(k));
                                sep_actual.agrega_proyecto(proyecto);
                            end
                            proyecto = this.pAdmProy.entrega_proyecto(proy_candidatos(cand).seleccionado);
                            sep_actual.agrega_proyecto(proyecto);
                            
                            this.evalua_red(sep_actual, nro_etapa, [], false); % false indica que proyectos se eliminan
                            estructura_eval = this.entrega_estructura_evaluacion(sep_actual.entrega_opf().entrega_evaluacion());
                            if estructura_eval.Valido
                                % quiere decir que plan fue reparado. Se
                                % deja hasta aquí (no es el objetivo
                                % minimizar costos de operación)
                                es_necesario_actualizar_sep = false;
                                mejor_intento = cand;
                                estructura_eval_mejor_intento = estructura_eval;
                                if this.iNivelDebug > 1
                                    texto = ['   Intento ' num2str(cand) ' hace que plan sea valido. No se continua. Proy seleccionado: ' num2str(proy_candidatos(cand).seleccionado)];
                                    prot.imprime_texto(texto);
                                end
                                
                                break;
                            else
                                % Reparación no hace que el plan sea valido.
                                % Se compara con los otros resultados
                                ens_cand = estructura_eval.ENS;
                                recorte_res_cand = estructura_eval.RecorteRES;
                                cop_cand = estructura_eval.CostoOperacion;
                                if this.iNivelDebug > 1                                    
                                    texto = ['   Intento ' num2str(cand) ' no es valido.'...
                                        ' ENS: ' num2str(ens_cand) '. Recorte RES: ' num2str(recorte_res_cand) ...
                                        '. COp: ' num2str(cop_cand) '. Proy seleccionado: ' num2str(proy_candidatos(cand).seleccionado)];                                        
                                    prot.imprime_texto(texto);
                                    
                                end
                                
                                if mejor_intento == 0
                                    if ens_base > 0
                                        if ens_cand < ens_base
                                            mejor_intento = cand;
                                            estructura_eval_mejor_intento = estructura_eval;
                                        end
                                    elseif recorte_res_base > 0
                                        if recorte_res_cand < recorte_res_base
                                            mejor_intento = cand;
                                            estructura_eval_mejor_intento = estructura_eval;
                                        end
                                    end
                                else
                                    if estructura_eval.CostoOperacion < estructura_eval_mejor_intento.CostoOperacion
                                        mejor_intento = cand;
                                        estructura_eval_mejor_intento = estructura_eval;
                                    end                                    
                                end                                  
                            end
                            % se deshacen los cambios en el sep
                            proyecto = this.pAdmProy.entrega_proyecto(proy_candidatos(cand).seleccionado);
                            sep_actual.elimina_proyecto(proyecto);
                            for k = length(proy_candidatos(cand).conectividad_agregar):-1:1
                                proyecto = this.pAdmProy.entrega_proyecto(proy_candidatos(cand).conectividad_agregar(k));
                                sep_actual.elimina_proyecto(proyecto);
                            end
                            for k = length(proy_candidatos(cand).conectividad_adelantar):-1:1
                                proyecto = this.pAdmProy.entrega_proyecto(proy_candidatos(cand).conectividad_adelantar(k));
                                sep_actual.elimina_proyecto(proyecto);
                            end
                        end
                        if mejor_intento ~= 0
                            proy_candidatos_restringidos = [];
                            valido = estructura_eval_mejor_intento.Valido;
                            pPlan.inserta_evaluacion_etapa(nro_etapa, estructura_eval_mejor_intento);
                            pPlan.CantidadReparaciones = pPlan.CantidadReparaciones + 1;
                            if this.iNivelDebug > 1
                                texto = ['      Mejor intento: ' num2str(mejor_intento)];
                                prot.imprime_texto(texto);
                            end

                            % se modifica plan de acuerdo al mejor candidato
                            for k = 1:length(proy_candidatos(mejor_intento).conectividad_adelantar)
                                pPlan.adelanta_proyectos(proy_candidatos(mejor_intento).conectividad_adelantar(k), proy_candidatos(mejor_intento).etapas_orig_conectividad_adelantar(k), nro_etapa);
                            end
                            for k = 1:length(proy_candidatos(mejor_intento).conectividad_agregar)
                                pPlan.agrega_proyecto(nro_etapa, proy_candidatos(mejor_intento).conectividad_agregar(k));
                            end
                            if proy_candidatos(mejor_intento).etapa_seleccionado == 0
                                pPlan.agrega_proyecto(nro_etapa, proy_candidatos(mejor_intento).seleccionado);
                            else
                                pPlan.adelanta_proyectos(proy_candidatos(mejor_intento).seleccionado, proy_candidatos(mejor_intento).etapa_seleccionado, nro_etapa);
                            end

                            if es_necesario_actualizar_sep
                                for k = 1:length(proy_candidatos(mejor_intento).conectividad_adelantar)
                                    proyecto = this.pAdmProy.entrega_proyecto(proy_candidatos(mejor_intento).conectividad_adelantar(k));
                                    sep_actual.agrega_proyecto(proyecto);
                                end
                                for k = 1:length(proy_candidatos(mejor_intento).conectividad_agregar)
                                    proyecto = this.pAdmProy.entrega_proyecto(proy_candidatos(mejor_intento).conectividad_agregar(k));
                                    sep_actual.agrega_proyecto(proyecto);
                                end
                                proyecto = this.pAdmProy.entrega_proyecto(proy_candidatos(mejor_intento).seleccionado);
                                sep_actual.agrega_proyecto(proyecto);
                            end
                            if this.iNivelDebug > 2
                                prot.imprime_texto('   Se imprime plan luego de la reparación');
                                pPlan.agrega_nombre_proyectos(this.pAdmProy);
                                pPlan.imprime_plan_expansion();
                            end
                        else
                            for kk = 1:length(proy_candidatos)
                                proy_candidatos_restringidos = [proy_candidatos_restringidos proy_candidatos(kk).seleccionado];
                            end
                            if this.iNivelDebug > 1
                                texto = '   Ningun proyecto cantidato ayuda a bajar ens o recorte res. Se agregan a proyectos restringidos';
                                prot.imprime_texto(texto);
                            end
                        end
                    end
                    
                    if ~valido
                        if this.iNivelDebug > 1
                            texto = ['   Plan ' num2str(pPlan.entrega_no()) ' no es valido en etapa ' num2str(nro_etapa) ...
                                '(ENS: ' num2str(pPlan.entrega_ens(nro_etapa)) ' Recorte RES: ' num2str(pPlan.entrega_recorte_res(nro_etapa)) ... 
                                '). No se puede reparar, por lo que se descarta. Cantidad de reparaciones: ' num2str(pPlan.CantidadReparaciones)];
                            prot.imprime_texto(texto);
                        end

                        pPlan.desecha_plan();
                        pPlan = this.genera_plan_expansion(nro_iteracion*1000 + nro_plan);
                        pPlan.inserta_iteracion(nro_iteracion);
                        pPlan.inserta_busqueda_local(false);
                        sep_actual.elimina_proyectos(this.pAdmProy);

                        nro_etapa = 0;
                    else
                        if this.iNivelDebug > 1
                            texto = ['   Plan es valido en etapa ' num2str(nro_etapa)];
                        	prot.imprime_texto(texto);
                        end
                    end
                end
                
                %fin de la generación y evaluación del plan de expansión. Ahora es
                %necesario determinar si el plan ya existe y, en caso contrario y
                %que este sea válido, calcular los costos totales y guardarlo
                this.calcula_costos_totales(pPlan);
                this.guarda_plan(pPlan, nro_iteracion, 0); %indica que es plan base
                this.CantPlanesValidos = this.CantPlanesValidos + 1;
            end %for. Todos los planes evaluados
        end

        function genera_planes_base_computo_paralelo(this, nro_iteracion)

            nivel_debug = this.pParOpt.NivelDebugParalelo;
            optimiza_uso_memoria = this.pParOpt.OptimizaUsoMemoriaParalelo;
            
            id_computo = this.IdComputo;
            cantidad_hormigas = this.pParOpt.CantidadHormigas;
            cantidad_etapas = this.pParOpt.CantidadEtapas;
            max_no_reparaciones_etapa = this.pParOpt.MaxNroReparacionesPorEtapa;
            planes_validos = cell(this.pParOpt.CantidadHormigas,1);
            puntos_operacion = this.pAdmSc.entrega_puntos_operacion();
            cantidad_puntos_operacion = length(puntos_operacion);
            
            if ~optimiza_uso_memoria
                CapacidadGeneradores = this.pAdmSc.entrega_capacidad_generadores();
                SerieGeneradoresERNC = this.pAdmSc.entrega_serie_generadores_ernc();
                SerieConsumos = this.pAdmSc.entrega_serie_consumos();
                sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            else
                CapacidadGeneradores = [];
                SerieGeneradoresERNC = [];
                SerieConsumos = [];
                sbase = 0;
            end
            
            cantidad_workers = this.pParOpt.CantWorkers;

            parfor (nro_plan = 1:cantidad_hormigas, cantidad_workers)
if nivel_debug > 0
tic
end
                if nivel_debug > 1
                    nombre_archivo = ['./output/debug/aco_id_', num2str(id_computo), '_hormiga_', num2str(nro_plan),'.dat'];
                    doc_id = fopen(nombre_archivo, 'a');
                    texto = ['Genera planes base en iteracion ' num2str(nro_iteracion) ' con hormiga ' num2str(nro_plan)];
                    fprintf(doc_id, strcat(texto, '\n'));
                    
                    tiempos_computo_opf = [];
                end
                
                if nro_iteracion > 1 && nro_plan == 1
                    if nro_iteracion >= this.pParOpt.PlanMasProbableFeromonasDesdeIteracion 
                        pPlan = this.genera_plan_mas_probable(nro_iteracion*1000 + nro_plan, false);
                    else
                        pPlan = this.genera_plan_mas_probable(nro_iteracion*1000 + nro_plan, true);
                    end
                elseif nro_iteracion > 1 && nro_plan == 2
                    % genera plan en base a feromonas entregadas
                    pPlan = this.genera_plan_feromonas_entregadas(nro_iteracion*1000 + nro_plan);
                else
                    pPlan = this.genera_plan_expansion(nro_iteracion*1000 + nro_plan);
                end
                
                if nivel_debug > 1
                    texto = ['Tiempo en generar plan expansion: ' num2str(toc)];
                    fprintf(doc_id, strcat(texto, '\n'));
                end
                
                pPlan.inserta_iteracion(nro_iteracion);
                pPlan.inserta_busqueda_local(false);


                if nivel_debug > 1
                    texto = ['Genera planes base plan ' num2str(nro_plan)];
                    fprintf(doc_id, strcat(texto, '\n'));
                    
                end

                %genera plan de expansión por cada etapa
                nro_etapa = 0;
                sep_actual = cSistemaElectricoPotencia.empty;
                sep_actual_generado = false;

                while nro_etapa < cantidad_etapas
                	nro_etapa = nro_etapa +1;

                    pPlan.CantidadReparaciones = 0;
                    
                    if ~sep_actual_generado
                        sep_actual = this.pSEP.crea_copia();
                        sep_actual_generado = true;
                    end
                    % agrega proyectos al sep actual
                    proyectos = pPlan.entrega_proyectos(nro_etapa);
                    for k = 1:length(proyectos)
                        proyecto = this.pAdmProy.entrega_proyecto(proyectos(k));
                        sep_actual.agrega_proyecto(proyecto);
                        if nivel_debug > 1
                            texto = ['   Nro etapa ' num2str(nro_etapa) ' agrega proyecto: ' num2str(proyectos(k))];
                            fprintf(doc_id, strcat(texto, '\n'));
                        end
                    end
                    pOPF = sep_actual.entrega_opf();
                    if isempty(pOPF)
                        if optimiza_uso_memoria
                            pOPF = cDCOPF(sep_actual, this.pAdmSc, this.pParOpt);
                            pOPF.inserta_nivel_debug(this.pParOpt.NivelDebugOPF);
                            pOPF.inserta_etapa(nro_etapa);
                            pOPF.inserta_resultados_en_sep(false);
                        else
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
                            
                            pOPF = cDCOPF(sep_actual);
                            pOPF.copia_parametros_optimizacion(this.pParOpt);
                            pOPF.inserta_puntos_operacion(puntos_operacion);
                            pOPF.inserta_datos_escenario(datos_escenario);
                            pOPF.inserta_etapa_datos_escenario(nro_etapa);
                            pOPF.inserta_sbase(sbase);
                        end                        
                    else
                        if optimiza_uso_memoria 
                            if pOPF.entrega_etapa() ~= nro_etapa
                                pOPF.actualiza_etapa(nro_etapa);
                            end
                        else
                            if pOPF.entrega_etapa_datos_escenario() ~= nro_etapa
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

                                pOPF.inserta_puntos_operacion(puntos_operacion);
                                pOPF.inserta_datos_escenario(datos_escenario);
                                pOPF.inserta_etapa_datos_escenario(nro_etapa);
                                pOPF.actualiza_etapa(nro_etapa);
                            end
                        end
                    end

                    if nivel_debug > 1
                        tinic_debug = toc;
                    end
                    
                    sep_actual.entrega_opf().calcula_despacho_economico();              
                    this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actual.entrega_opf().entrega_evaluacion(), nro_etapa);
                    valido = pPlan.es_valido(nro_etapa);

                    if nivel_debug > 1
                        tiempos_computo_opf(end+1) = toc-tinic_debug;
                    end
                    
                    if nivel_debug > 1
                        if valido 
                            texto = '   Plan es valido';
                            fprintf(doc_id, strcat(texto, '\n'));
                        else
                            texto = ['   Plan ' num2str(pPlan.entrega_no()) ' no es valido en etapa ' num2str(nro_etapa) ...
                                ' (ENS: ' num2str(pPlan.entrega_ens(nro_etapa)) ' Recorte RES: ' num2str(pPlan.entrega_recorte_res(nro_etapa)) ...
                                '). Se intenta reparar. Cantidad de reparaciones: ' num2str(pPlan.CantidadReparaciones)];
                            fprintf(doc_id, strcat(texto, '\n'));
                           
                            sep_actual.entrega_opf().entrega_evaluacion().imprime_resultados(['Res OPF en etapa' num2str(nro_etapa)], doc_id);
                            %%eval_opf = sep_actual.entrega_opf().entrega_evaluacion();
                            %if pPlan.entrega_ens(nro_etapa) > 0
                                
                            %end
                            %if pPlan.entrega_recorte_res(nro_etapa) > 0                                
                            %    gen_res = sep_actual.entrega_generadores_res();
                            %    eval_opf.imprime_resultado_recorte_res(gen_res,nro_etapa);
                            %end
                        end%
                    end
                    proy_candidatos_restringidos = [];
                    cant_intentos_reparacion = 0;
                    while ~valido && (pPlan.CantidadReparaciones < max_no_reparaciones_etapa)
                        cant_intentos_reparacion = cant_intentos_reparacion + 1;
                        estructura_eval_base = this.entrega_estructura_evaluacion(sep_actual.entrega_opf().entrega_evaluacion());
                        ens_base = estructura_eval_base.ENS;
                        recorte_res_base = estructura_eval_base.RecorteRES;

                        if nivel_debug > 1
                            tinic_debug = toc;
                        end
                        
                        proy_candidatos = this.entrega_proyectos_candidatos_repara_plan(pPlan, nro_etapa, proy_candidatos_restringidos);

                        % proy_candidatos(nro_candidato).seleccionado = indice;
                        % proy_candidatos(nro_candidato).etapa_seleccionado = 0;
                        % proy_candidatos(nro_candidato).conectividad_agregar = [];
                        % proy_candidatos(nro_candidato).conectividad_adelantar = [];
                        % proy_candidatos(nro_candidato).etapas_orig_conectividad_adelantar = [];
                        
                        if nivel_debug > 1
                            texto = ['Tiempo en generar candidatos repara plan: ' num2str(toc-tinic_debug)];
                            fprintf(doc_id, strcat(texto, '\n'));
                        end
                        
                        if isempty(proy_candidatos)
                        	valido = false;
                            if nivel_debug > 1
                                texto = ['   Plan ' num2str(pPlan.entrega_no()) ' no se pudo reparar en etapa ' num2str(nro_etapa) '. Se descarta'];
                                fprintf(doc_id, strcat(texto, '\n'));
                            end
                            break;
                        else
                            if nivel_debug > 1
                                texto = ['   Proy. candidatos etapa ' num2str(nro_etapa) ' intento ' num2str(cant_intentos_reparacion) ': '];
                                for kk = 1:length(proy_candidatos)
                                    texto = [texto ' ' num2str(proy_candidatos(kk).seleccionado)];
                                end
                                fprintf(doc_id, strcat(texto, '\n'));
                                texto = '   Proy. restringidos: ';
                                for kk = 1:length(proy_candidatos_restringidos)
                                    texto = [texto ' ' num2str(proy_candidatos_restringidos(kk))];
                                end
                                fprintf(doc_id, strcat(texto, '\n'));
                            end
                        end
                        es_necesario_actualizar_sep = true;
                        mejor_intento = 0;
                        
                        for cand = 1:length(proy_candidatos)
                            % evalua candidato
                            for k = 1:length(proy_candidatos(cand).conectividad_adelantar)
                                proyecto = this.pAdmProy.entrega_proyecto(proy_candidatos(cand).conectividad_adelantar(k));
                                sep_actual.agrega_proyecto(proyecto);
                            end
                            for k = 1:length(proy_candidatos(cand).conectividad_agregar)
                                proyecto = this.pAdmProy.entrega_proyecto(proy_candidatos(cand).conectividad_agregar(k));
                                sep_actual.agrega_proyecto(proyecto);
                            end
                            proyecto = this.pAdmProy.entrega_proyecto(proy_candidatos(cand).seleccionado);
                            sep_actual.agrega_proyecto(proyecto);

                            if nivel_debug > 1
                                tinic_debug = toc;
                            end

                            sep_actual.entrega_opf().calcula_despacho_economico();
                            estructura_eval = this.entrega_estructura_evaluacion(sep_actual.entrega_opf().entrega_evaluacion());
                            
                            if nivel_debug > 1
                                tiempos_computo_opf(end+1) = toc-tinic_debug;
                            end
                            
                            if estructura_eval.Valido
                                % quiere decir que plan fue reparado. Se
                                % deja hasta aquí (no es el objetivo
                                % minimizar costos de operación)
                                es_necesario_actualizar_sep = false;
                                mejor_intento = cand;
                                estructura_eval_mejor_intento = estructura_eval;
                                if nivel_debug > 1
                                    texto = ['   Intento ' num2str(cand) ' hace que plan sea valido. No se continua. Proy seleccionado: ' num2str(proy_candidatos(cand).seleccionado)];
                                    fprintf(doc_id, strcat(texto, '\n'));
                                end
                                
                                break;
                            else
                                % Reparación no hace que el plan sea valido.
                                % Se compara con los otros resultados
                                ens_cand = estructura_eval.ENS;
                                recorte_res_cand = estructura_eval.RecorteRES;
                                cop_cand = estructura_eval.CostoOperacion;
                                if nivel_debug > 1
                                    texto = ['   Intento ' num2str(cand) ' no es valido.'...
                                        ' ENS: ' num2str(ens_cand) '. Recorte RES: ' num2str(recorte_res_cand) ...
                                        '. COp: ' num2str(cop_cand) '. Proy seleccionado: ' num2str(proy_candidatos(cand).seleccionado)];                                        
                                    fprintf(doc_id, strcat(texto, '\n'));
                                    
                                    sep_actual.entrega_opf().entrega_evaluacion().imprime_resultados(['Res OPF en etapa' num2str(nro_etapa)], doc_id);

                                end
                                
                                if mejor_intento == 0
                                    if ens_base > 0
                                        if ens_cand < ens_base
                                            mejor_intento = cand;
                                            estructura_eval_mejor_intento = estructura_eval;
                                        end
                                    elseif recorte_res_base > 0
                                        if recorte_res_cand < recorte_res_base
                                            mejor_intento = cand;
                                            estructura_eval_mejor_intento = estructura_eval;
                                        end
                                    end
                                else
                                    if estructura_eval.CostoOperacion < estructura_eval_mejor_intento.CostoOperacion
                                        mejor_intento = cand;
                                        estructura_eval_mejor_intento = estructura_eval;
                                    end                                    
                                end                                  
                            end
                            % se deshacen los cambios en el sep
                            proyecto = this.pAdmProy.entrega_proyecto(proy_candidatos(cand).seleccionado);
                            sep_actual.elimina_proyecto(proyecto);
                            for k = length(proy_candidatos(cand).conectividad_agregar):-1:1
                                proyecto = this.pAdmProy.entrega_proyecto(proy_candidatos(cand).conectividad_agregar(k));
                                sep_actual.elimina_proyecto(proyecto);
                            end
                            for k = length(proy_candidatos(cand).conectividad_adelantar):-1:1
                                proyecto = this.pAdmProy.entrega_proyecto(proy_candidatos(cand).conectividad_adelantar(k));
                                sep_actual.elimina_proyecto(proyecto);
                            end
                        end
                        if mejor_intento ~= 0
                            proy_candidatos_restringidos = [];
                            valido = estructura_eval_mejor_intento.Valido;
                            pPlan.inserta_evaluacion_etapa(nro_etapa, estructura_eval_mejor_intento);
                            pPlan.CantidadReparaciones = pPlan.CantidadReparaciones + 1;
                            if nivel_debug > 1
                                texto = ['      Mejor intento: ' num2str(mejor_intento)];
                                fprintf(doc_id, strcat(texto, '\n'));
                            end
                        
                            % se modifica plan de acuerdo al mejor candidato
                            for k = 1:length(proy_candidatos(mejor_intento).conectividad_adelantar)
                                pPlan.adelanta_proyectos(proy_candidatos(mejor_intento).conectividad_adelantar(k), proy_candidatos(mejor_intento).etapas_orig_conectividad_adelantar(k), nro_etapa);
                            end
                            for k = 1:length(proy_candidatos(mejor_intento).conectividad_agregar)
                                pPlan.agrega_proyecto(nro_etapa, proy_candidatos(mejor_intento).conectividad_agregar(k));
                            end
                            if proy_candidatos(mejor_intento).etapa_seleccionado == 0
                                pPlan.agrega_proyecto(nro_etapa, proy_candidatos(mejor_intento).seleccionado);
                            else
                                pPlan.adelanta_proyectos(proy_candidatos(mejor_intento).seleccionado, proy_candidatos(mejor_intento).etapa_seleccionado, nro_etapa);
                            end
                        
                            if es_necesario_actualizar_sep
                                for k = 1:length(proy_candidatos(mejor_intento).conectividad_adelantar)
                                    proyecto = this.pAdmProy.entrega_proyecto(proy_candidatos(mejor_intento).conectividad_adelantar(k));
                                    sep_actual.agrega_proyecto(proyecto);
                                end
                                for k = 1:length(proy_candidatos(mejor_intento).conectividad_agregar)
                                    proyecto = this.pAdmProy.entrega_proyecto(proy_candidatos(mejor_intento).conectividad_agregar(k));
                                    sep_actual.agrega_proyecto(proyecto);
                                end
                                proyecto = this.pAdmProy.entrega_proyecto(proy_candidatos(mejor_intento).seleccionado);
                                sep_actual.agrega_proyecto(proyecto);
                            end
                            if nivel_debug > 1
                                texto = '   Se imprime plan luego de la reparacion';
                                fprintf(doc_id, strcat(texto, '\n'));

                                pPlan.agrega_nombre_proyectos(this.pAdmProy);
                                texto = pPlan.entrega_texto_plan_expansion();
                                fprintf(doc_id, strcat(texto, '\n'));
                            end
                        else
                            for kk = 1:length(proy_candidatos)
                                proy_candidatos_restringidos = [proy_candidatos_restringidos proy_candidatos(kk).seleccionado];
                            end
                            if nivel_debug > 1
                                texto = '   Ningun proyecto cantidato ayuda a bajar ens o recorte res. Se agregan a proyectos restringidos';
                                fprintf(doc_id, strcat(texto, '\n'));
                            end
                        end
                    end
                    
                    if ~valido

                        if nivel_debug > 1
                            texto = '   Plan no es valido luego de las reparaciones. Se desecha';
                            fprintf(doc_id, strcat(texto, '\n'));
                        end                        
                        % desecha plan y elimina proyectos del sep actual
                        pPlan.desecha_plan();
                        pPlan = this.genera_plan_expansion(nro_iteracion*1000 + nro_plan);
                        pPlan.inserta_iteracion(nro_iteracion);
                        pPlan.inserta_busqueda_local(false);
                        sep_actual.elimina_proyectos(this.pAdmProy);
                        
                        nro_etapa = 0;
                    end
                end
                this.calcula_costos_totales(pPlan);
                %fin de la generación y evaluación del plan de expansión. Ahora es
                %necesario determinar si el plan ya existe y, en caso contrario y
                %que este sea válido, calcular los costos totales y guardarlo
                if nivel_debug > 1
                    texto = 'Se imprime plan calculado';
                    fprintf(doc_id, strcat(texto, '\n'));
                    % imprime plan
                    pPlan.agrega_nombre_proyectos(this.pAdmProy);
                    texto = pPlan.entrega_texto_plan_expansion();
                    fprintf(doc_id, strcat(texto, '\n'));
                end

                planes_validos{nro_plan} = pPlan;
                
                if nivel_debug > 1
                    texto = 'Fin genera planes base para hormiga';
                    fprintf(doc_id, strcat(texto, '\n'));
                    
                    texto = ['Cantidad computos opf: ' num2str(length(tiempos_computo_opf))];
                    fprintf(doc_id, strcat(texto, '\n'));
                    texto = 'Tiempos de computo OPF:';
                    fprintf(doc_id, strcat(texto, '\n'));
                    for i = 1:length(tiempos_computo_opf)
                        fprintf(doc_id, strcat(num2str(tiempos_computo_opf(i)), '\n'));
                    end
                    
                    fclose(doc_id);
                end
if nivel_debug > 0                
disp(['dt base = ' num2str(toc)])
end
            end %for. Todos los planes evaluados
                        
            for i = 1:length(planes_validos)
                if ~isempty(planes_validos{i})
                    this.guarda_plan(planes_validos{i}, nro_iteracion, 0);
                    this.CantPlanesValidos = this.CantPlanesValidos + 1;                    
                end
            end
        end
                
        function [planes_generados, indice] = genera_planes_busqueda_local_secuencial_completo(this, nro_iteracion, planes_originales, indice_planes)
            if this.iNivelDebug > 0
                prot = cProtocolo.getInstance;
            end
            planes_generados = cell(1,0);
            cantidad_planes_generados = 0;
            
            cantidad_planes = length(planes_originales);
            for nro_plan = 1:cantidad_planes
            	plan_orig = planes_originales(nro_plan);

                if this.iNivelDebug > 1
                    texto = ['Busqueda local secuencial completo ' num2str(nro_plan) '/' num2str(cantidad_planes) '. Nro planes validos: ' num2str(this.CantPlanesValidos)];
                    prot.imprime_texto(texto);
                    
                    prot.imprime_texto('Se imprime plan base para busqueda local');
                    plan_orig.agrega_nombre_proyectos(this.pAdmProy);
                    plan_orig.imprime_plan_expansion();
                end
                
                for nro_intento = 1:this.pParOpt.BLAgregaProyectosFormaSecuencialCompleto
                    if this.iNivelDebug > 1
                        texto = ['Busqueda local secuencial completo ' num2str(nro_plan) '/' num2str(cantidad_planes) ' en nro busqueda ' num2str(nro_intento) '/' num2str(this.pParOpt.BLAgregaProyectosFormaSecuencialCompleto)];
                        prot.imprime_texto(texto);
                    end
                    indice_planes = indice_planes + 1;
                    pPlan = cPlanExpansion(indice_planes);
                    pPlan.inserta_iteracion(nro_iteracion);
                    pPlan.inserta_busqueda_local(true);
                    pPlan.inserta_plan_base(plan_orig.entrega_no());
                    pPlan.inserta_estrategia_busqueda_local(5);
                    espacio_proyectos = plan_orig.entrega_proyectos();                    
                    if isempty(espacio_proyectos)
                        % plan no contiene proyectos por lo que no
                        % tiene sentido hacer una búsqueda local
                        delete(pPlan);
                        continue;
                    end

                    sep_actuales = cell(this.pParOpt.CantidadEtapas, 0);
                    for nro_etapa = 1:this.pParOpt.CantidadEtapas
                        pPlan.inicializa_etapa(nro_etapa);
                    end
                    
                    cant_proy_obligatorios = length(this.pAdmProy.ProyectosObligatorios);
                    if cant_proy_obligatorios > 0
                        planes_obligatorios_generados = false;
                        % determina cantidad de combinaciones de proyectos
                        % obligatorios a agregar
                        pool_proy_obligatorios = cell(cant_proy_obligatorios, 0);
                        for j = cant_proy_obligatorios:-1:1
                            indices = ismember(espacio_proyectos, this.pAdmProy.ProyectosObligatorios(j).Indice);
                            pool_proy_obligatorios{j} = espacio_proyectos(indices);
                        end
%                        combinaciones_proy_obligatorios = [];
                        if cant_proy_obligatorios > 1
                            error = MException('cOptACO:genera_planes_busqueda_local_secuencial_completo','Código actual soporta máximo un grupo de proyectos obligatorios!');
                            throw(error)
                        end
                    else
                        planes_obligatorios_generados = true;
                    end

                    %evaluacion_actual = pPlan.entrega_evaluacion();
                    %estructura_costos_actual = pPlan.entrega_estructura_costos();
                    plan_actual = pPlan.Plan; %plan vacío
                    
                    % antes de comenzar, crea evaluación actual. En caso de
                    % haber proyectos obligatorios, escoge el proyecto
                    % obligatorio base
                    if ~planes_obligatorios_generados
                        intento_paralelo_actual = 0;
                        intentos_actuales = cell(1,0);
                        sep_actuales_generados = false;
                        while intento_paralelo_actual < this.pParOpt.BLSecuencialCompletoCantProyComparar
                            intento_paralelo_actual = intento_paralelo_actual +1;
                            if isempty(pool_proy_obligatorios{1})
                            	intentos_actuales{intento_paralelo_actual}.Existe = false;
                                continue;
                            end
                            [proyecto_seleccionado, proyectos_conectividad] = this.selecciona_proyecto_obligatorio_a_agregar(pool_proy_obligatorios{1}, espacio_proyectos);
                            pool_proy_obligatorios{1}(ismember(pool_proy_obligatorios{1}, proyecto_seleccionado)) = [];
                            plan_valido = true; % por ahora
                            for i = 1:length(proyectos_conectividad)
                                pPlan.agrega_proyecto(1, proyectos_conectividad(i));
                            end
                            pPlan.agrega_proyecto(1, proyecto_seleccionado);
                            
                            parfor nro_etapa = 1:this.pParOpt.CantidadEtapas
                                % genera sep en la etapa
                                if ~sep_actuales_generados
                                    sep_actuales{nro_etapa} = this.pSEP.crea_copia();
                                end
                                for i = 1:length(proyectos_conectividad)
                                    proy = this.pAdmProy.entrega_proyecto(proyectos_conectividad(i));
                                    sep_actuales{nro_etapa}.agrega_proyecto(proy);
                                end
                                    
                                proy = this.pAdmProy.entrega_proyecto(proyecto_seleccionado);
                                sep_actuales{nro_etapa}.agrega_proyecto(proy);

                                this.evalua_red(sep_actuales{nro_etapa}, nro_etapa, [], true);
                            end
                            if ~sep_actuales_generados
                                sep_actuales_generados = true;
                            end
                            for nro_etapa = 1:this.pParOpt.CantidadEtapas
                                this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa);
                                if ~pPlan.es_valido(nro_etapa);
                                    plan_valido = false;
                                end
                            end
                            this.calcula_costos_totales(pPlan);
                            intentos_actuales{intento_paralelo_actual}.Existe = true;
                            intentos_actuales{intento_paralelo_actual}.proyectos_seleccionados = [proyectos_conectividad proyecto_seleccionado];
                            intentos_actuales{intento_paralelo_actual}.Totex = pPlan.entrega_totex_total();
                            intentos_actuales{intento_paralelo_actual}.Valido = plan_valido;
                            intentos_actuales{intento_paralelo_actual}.Plan = pPlan.Plan;
                            intentos_actuales{intento_paralelo_actual}.estructura_costos = pPlan.entrega_estructura_costos();
                            intentos_actuales{intento_paralelo_actual}.evaluacion_actual = pPlan.entrega_evaluacion();
                        
                            %deshace los cambios
                            pPlan.Plan = plan_actual;
                            parfor nro_etapa = 1:this.pParOpt.CantidadEtapas
                                proy = this.pAdmProy.entrega_proyecto(proyecto_seleccionado);
                                sep_actuales{nro_etapa}.elimina_proyecto(proy);
                                for i = length(proyectos_conectividad):-1:1
                                    proy = this.pAdmProy.entrega_proyecto(proyectos_conectividad(i));
                                    sep_actuales{nro_etapa}.elimina_proyecto(proy);
                                end
                            end
                        end
                        % determina mejor intento
                        mejor_totex = 0;
                        id_mejor_plan_intento = 0;
                        for kk = 1:this.pParOpt.BLSecuencialCompletoCantProyComparar
                            if intentos_actuales{kk}.Existe
                                if id_mejor_plan_intento == 0
                                    id_mejor_plan_intento = kk;
                                    mejor_totex = intentos_actuales{kk}.Totex;
                                elseif intentos_actuales{kk}.Totex < mejor_totex
                                    id_mejor_plan_intento = kk;
                                    mejor_totex = intentos_actuales{kk}.Totex;
                                end
                                if this.iNivelDebug > 1
                                    texto = ['      Intento ' num2str(kk) ' tiene Totex: ' num2str(intentos_actuales{kk}.Totex) '. Es valido?: ' num2str(intentos_actuales{kk}.Valido) '. Proyectos seleccionados: '];
                                    for oo = 1:length(intentos_actuales{kk}.proyectos_seleccionados)
                                        texto = [texto ' ' num2str(intentos_actuales{kk}.proyectos_seleccionados(oo))];
                                    end
                                    prot.imprime_texto(texto);
                                end 
                            end
                        end

                        if this.iNivelDebug > 1
                            texto = ['      Mejor intento: ' num2str(id_mejor_plan_intento)];
                            prot.imprime_texto(texto);
                        end
                        
                        plan_actual = intentos_actuales{id_mejor_plan_intento}.Plan;
                        evaluacion_actual = intentos_actuales{id_mejor_plan_intento}.evaluacion_actual;
                        estructura_costos_actual = intentos_actuales{id_mejor_plan_intento}.estructura_costos_actual;
                        plan_actual_valido = intentos_actuales{id_mejor_plan}.Valido;
                        pPlan.Plan = plan_actual;
                        pPlan.inserta_estructura_costos(estructura_costos_actual);
                        pPlan.inserta_evaluacion(evaluacion_actual);
                        pPlan.Valido = plan_actual_valido;
                        
                        espacio_proyectos(ismember(espacio_proyectos, intentos_actuales{id_mejor_plan_intento}.proyectos_seleccionados)) = [];
                        % ingresa los proyectos seleccionados en los sep
                        parfor nro_etapa = 1:this.pParOpt.CantidadEtapas
                            for i = 1:length(intentos_actuales{intento_paralelo_actual}.proyectos_seleccionados)
                                proy = this.pAdmProy.entrega_proyecto(intentos_actuales{intento_paralelo_actual}.proyectos_seleccionados(i));
                                sep_actuales{nro_etapa}.agrega_proyecto(proy);
                            end
                        end
                    else
                        parfor nro_etapa = 1:this.pParOpt.CantidadEtapas
                            % genera sep en la etapa
                            sep_actuales{nro_etapa} = this.pSEP.crea_copia();
                            this.evalua_red(sep_actuales{nro_etapa}, nro_etapa, [], true);
                        end
                        for nro_etapa = 1:this.pParOpt.CantidadEtapas
                            this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa);
                        end
                        this.calcula_costos_totales(pPlan);
                        valido = pPlan.es_valido_hasta_etapa(this.pParOpt.CantidadEtapas);
                        evaluacion_actual = pPlan.entrega_evaluacion();
                        estructura_costos_actual = pPlan.entrega_estructura_costos();
                        pPlan.inserta_estructura_costos(estructura_costos_actual);
                        pPlan.Valido = valido;
                        pPlan.inserta_evaluacion(evaluacion_actual);
                        plan_actual_valido = valido;
                    end
                    
                    if this.iNivelDebug > 1
                        prot.imprime_texto('Comienzo proyceso agrega proyectos completo');
                        texto = ['      Totex plan vacio: ' num2str(pPlan.entrega_totex_total()) '. Es valido? ' num2str(pPlan.Valido)];
                        prot.imprime_texto(texto);
                        pPlan.agrega_nombre_proyectos(this.pAdmProy);
                    	pPlan.imprime_plan_expansion();
                    end
                    
                    % comienza proceso
                    cant_busqueda_fallida = 0;
                    proyectos_restringidos_a_agregar = [];
                    while cant_busqueda_fallida < this.pParOpt.BLSecuencialCompletoCantBusquedaFallida
                        intento_paralelo_actual = 0;
                        intentos_actuales = cell(1,0);
                        espacio_proyectos_intento = espacio_proyectos;
                        espacio_proyectos_intento(ismember(espacio_proyectos_intento, proyectos_restringidos_a_agregar)) = [];
                        while intento_paralelo_actual < this.pParOpt.BLSecuencialCompletoCantProyComparar
                            intento_paralelo_actual = intento_paralelo_actual +1;

                            intentos_actuales{intento_paralelo_actual}.Existe = false;
                            if isempty(espacio_proyectos_intento)
                                continue;
                            end
                            
                            % selecciona proyectos
                            
                            %[proyecto_seleccionado, proyectos_conectividad, primera_etapa_posible] = this.selecciona_proyecto_a_agregar(pPlan, this.pParOpt.CantidadEtapas, espacio_proyectos_intento);
                            [seleccionado, conectividad_agregar, primera_etapa_posible, conectividad_adelantar, etapa_adelantar] = this.selecciona_proyecto_a_agregar(pPlan, ...
                                                                                                                                                                      this.pParOpt.CantidadEtapas, ...
                                                                                                                                                                      espacio_proyectos_intento);
                            espacio_proyectos_intento(ismember(espacio_proyectos_intento, seleccionado)) = [];

                            % Evalua red en cada una de las
                            % etapas. Parte de atrás hacia adelante ya que
                            % es más fácil el cálculo de la etapa "óptima"
                            proyectos_a_agregar = [conectividad_agregar seleccionado];
                            mejor_etapa_actual = 0;
                            mejor_totex_actual = 9999999999999999;
                            mejor_etapa_actual_es_valido = false;
                            if this.iNivelDebug > 1
                                texto = ['      Intento ' num2str(intento_paralelo_actual) '. Proyectos (' num2str(length(proyectos_a_agregar)) '): '];
                                for oo = 1:length(proyectos_a_agregar)
                                    texto = [texto ' ' num2str(proyectos_a_agregar(oo))];
                                end
                                prot.imprime_texto(texto);
                                prot.imprime_texto(['      Primera etapa posible: ' num2str(primera_etapa_posible)]);
                                if ~isempty(conectividad_adelantar)
                                    texto = ['                 Proyectos conectividad adelantar (' num2str(length(conectividad_adelantar)) '): '];
                                    for oo = 1:length(conectividad_adelantar)
                                        texto = [texto ' ' num2str(conectividad_adelantar(oo)) ' a partir de etapa ' num2str(etapa_adelantar(oo))];
                                    end
                                    prot.imprime_texto(texto);
                                end
                                texto = ['      Totex actual intento: ' num2str(pPlan.entrega_totex_total())];
                                prot.imprime_texto(texto);
                            end
                            
                            max_cantidad_aumento_totex = this.pParOpt.BLSecuencialCompletoMaxCantAumentoTotexIntento;
                            cantidad_aumento_totex = 0;   
                            nro_etapa = this.pParOpt.CantidadEtapas;
                            flag_salida = false;
                            %for nro_etapa = this.pParOpt.CantidadEtapas:-1:primera_etapa_posible
                            while nro_etapa >= primera_etapa_posible && flag_salida == false
                                for i = 1:length(conectividad_adelantar)
                                    if nro_etapa < etapa_adelantar(i)
                                        % se adelanta proyecto de
                                        % conectividad
                                        proy = this.pAdmProy.entrega_proyecto(conectividad_adelantar(i));
                                        sep_actuales{nro_etapa}.agrega_proyecto(proy);
                                        pPlan.adelanta_proyectos(conectividad_adelantar(i), nro_etapa + 1, nro_etapa);
                                    end
                                end
                                
                                for i = 1:length(proyectos_a_agregar)
                                    proy = this.pAdmProy.entrega_proyecto(proyectos_a_agregar(i));
                                    sep_actuales{nro_etapa}.agrega_proyecto(proy);
                                    if nro_etapa == this.pParOpt.CantidadEtapas
                                        pPlan.agrega_proyecto(nro_etapa, proyectos_a_agregar(i));
                                    else
                                        pPlan.adelanta_proyectos(proyectos_a_agregar(i), nro_etapa + 1, nro_etapa);
                                    end
                                end                                
                                
                                this.evalua_red(sep_actuales{nro_etapa}, nro_etapa, [], true);
                                this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa);
                                valido = pPlan.es_valido_hasta_etapa(this.pParOpt.CantidadEtapas);
                                this.calcula_costos_totales(pPlan);
                                if this.iNivelDebug > 1
                                    texto = ['      Intento al agregar proyectos en etapa ' num2str(nro_etapa) ' tiene totex: ' num2str(pPlan.entrega_totex_total()) '. Es valido: ' num2str(valido)];
                                    prot.imprime_texto(texto);
                                end

                                if mejor_etapa_actual == 0 || pPlan.entrega_totex_total() < mejor_totex_actual || (~mejor_etapa_actual_es_valido && valido)
                                    intentos_actuales{intento_paralelo_actual}.Existe = true;
                                    intentos_actuales{intento_paralelo_actual}.proyectos_seleccionados = proyectos_a_agregar;
                                    intentos_actuales{intento_paralelo_actual}.Totex = pPlan.entrega_totex_total();
                                    intentos_actuales{intento_paralelo_actual}.Valido = valido;
                                    intentos_actuales{intento_paralelo_actual}.Plan = pPlan.Plan;
                                    intentos_actuales{intento_paralelo_actual}.estructura_costos = pPlan.entrega_estructura_costos();
                                    intentos_actuales{intento_paralelo_actual}.evaluacion = pPlan.entrega_evaluacion();
                                    intentos_actuales{intento_paralelo_actual}.NroEtapaAgregar = nro_etapa;                                    
                                    intentos_actuales{intento_paralelo_actual}.conectividad_adelantar = conectividad_adelantar;
                                    intentos_actuales{intento_paralelo_actual}.etapa_adelantar = etapa_adelantar;
                                    
                                    mejor_etapa_actual = nro_etapa;
                                    mejor_totex_actual = pPlan.entrega_totex_total();
                                    mejor_etapa_actual_es_valido = valido;
                                    cantidad_aumento_totex = 0;
                                else
                                    cantidad_aumento_totex = cantidad_aumento_totex + 1;
                                end
                                
                                % elimina proyectos del sep actual
                                for i = length(proyectos_a_agregar):-1:1
                                    proy = this.pAdmProy.entrega_proyecto(proyectos_a_agregar(i));
                                    sep_actuales{nro_etapa}.elimina_proyecto(proy);
                                end
                                % elimina proyectos de conectividad
                                % adelantados
                                for i = 1:length(conectividad_adelantar)
                                    if nro_etapa < etapa_adelantar(i)
                                        % se adelanta proyecto de
                                        % conectividad
                                        proy = this.pAdmProy.entrega_proyecto(conectividad_adelantar(i));
                                        sep_actuales{nro_etapa}.elimina_proyecto(proy);
                                    end
                                end
                                if cantidad_aumento_totex > max_cantidad_aumento_totex
                                    flag_salida = true;
                                end         
                                nro_etapa = nro_etapa - 1;
                            end % fin while nro de etapas
                            % vuelve atrás datos del plan
                            pPlan.Plan = plan_actual;
                            pPlan.inserta_estructura_costos(estructura_costos_actual);
                            pPlan.Valido = plan_actual_valido;
                            pPlan.inserta_evaluacion(evaluacion_actual);
                        end % fin intentos
                            
                        % determina mejor intento
                        mejor_totex = 0;
                        id_mejor_plan_intento = 0;
                        valido_mejor_intento = false;
                        for kk = 1:this.pParOpt.BLSecuencialCompletoCantProyComparar
                            if intentos_actuales{kk}.Existe
                                if id_mejor_plan_intento == 0 || (intentos_actuales{kk}.Totex < mejor_totex) || (~valido_mejor_intento && intentos_actuales{kk}.Valido)
                                    id_mejor_plan_intento = kk;
                                    mejor_totex = intentos_actuales{kk}.Totex;
                                    valido_mejor_intento = intentos_actuales{kk}.Valido;
                                end
                                if this.iNivelDebug > 1
                                    texto = ['      Intento ' num2str(kk) ' tiene Totex: ' num2str(intentos_actuales{kk}.Totex) ...
                                             '. Es valido?: ' num2str(intentos_actuales{kk}.Valido) '. Proyectos seleccionados: '];
                                    for oo = 1:length(intentos_actuales{kk}.proyectos_seleccionados)
                                        texto = [texto ' ' num2str(intentos_actuales{kk}.proyectos_seleccionados(oo))];
                                    end
                                    texto = [texto '. Se agregan a etapa: ' num2str(intentos_actuales{kk}.NroEtapaAgregar)];
                                    prot.imprime_texto(texto);

                                    if ~isempty(intentos_actuales{kk}.conectividad_adelantar)
                                        texto = '                                                        Conectividad adelantar: ';
                                        for oo = 1:length(intentos_actuales{kk}.conectividad_adelantar)
                                            if intentos_actuales{kk}.etapa_adelantar(oo) > intentos_actuales{kk}.NroEtapaAgregar
                                                texto = [texto ' ' num2str(intentos_actuales{kk}.conectividad_adelantar(oo))];
                                                texto = [texto ' desde etapa ' num2str(intentos_actuales{kk}.etapa_adelantar(oo)) '; '];
                                            end
                                        end
                                        prot.imprime_texto(texto);
                                    end
                                end
                            end
                        end

                        if this.iNivelDebug > 1
                            texto = ['      Mejor intento: ' num2str(id_mejor_plan_intento)];
                            prot.imprime_texto(texto);
                        end
                        
                        % determina si mejor intento mejora plan
                        if (id_mejor_plan_intento > 0) && ((intentos_actuales{id_mejor_plan_intento}.Totex < estructura_costos_actual.TotexTotal) || (~plan_actual_valido && intentos_actuales{id_mejor_plan_intento}.Valido))
                            if this.iNivelDebug > 1
                                texto = ['      Mejor intento mejora plan. Se acepta el cambio' ...
                                         '. Totex actual: ' num2str(estructura_costos_actual.TotexTotal) ' (Valido: ' num2str(plan_actual_valido) ...
                                         '). Totex mejor intento: ' num2str(intentos_actuales{id_mejor_plan_intento}.Totex) ' (' num2str(intentos_actuales{id_mejor_plan_intento}.Valido)];
                                prot.imprime_texto(texto);
                                texto = '      Proyectos seleccionados: ';
                                for oo = 1:length(intentos_actuales{id_mejor_plan_intento}.proyectos_seleccionados)
                                    texto = [texto ' ' num2str(intentos_actuales{id_mejor_plan_intento}.proyectos_seleccionados(oo))];
                                end
                                texto = [texto '. Se agregan a etapa: ' num2str(intentos_actuales{id_mejor_plan_intento}.NroEtapaAgregar)];
                                prot.imprime_texto(texto);
                                if ~isempty(intentos_actuales{id_mejor_plan_intento}.conectividad_adelantar)
                                    texto = '                                                        Conectividad adelantar: ';
                                    for oo = 1:length(intentos_actuales{id_mejor_plan_intento}.conectividad_adelantar)
                                        if intentos_actuales{id_mejor_plan_intento}.etapa_adelantar(oo) > intentos_actuales{id_mejor_plan_intento}.NroEtapaAgregar
                                            texto = [texto ' ' num2str(intentos_actuales{id_mejor_plan_intento}.conectividad_adelantar(oo))];
                                            texto = [texto ' desde etapa ' num2str(intentos_actuales{id_mejor_plan_intento}.etapa_adelantar(oo)) '; '];
                                        end
                                    end
                                end
                            end
                            
                            plan_actual = intentos_actuales{id_mejor_plan_intento}.Plan;
                            evaluacion_actual = intentos_actuales{id_mejor_plan_intento}.evaluacion;
                            estructura_costos_actual = intentos_actuales{id_mejor_plan_intento}.estructura_costos;
                            plan_actual_valido = intentos_actuales{id_mejor_plan_intento}.Valido;
                            pPlan.Plan = plan_actual;
                            pPlan.inserta_estructura_costos(estructura_costos_actual);
                            pPlan.inserta_evaluacion(evaluacion_actual);
                            pPlan.Valido = plan_actual_valido;

                            espacio_proyectos(ismember(espacio_proyectos, intentos_actuales{id_mejor_plan_intento}.proyectos_seleccionados)) = [];
                            % agrega proyectos en los sep
                            for nro_etapa = intentos_actuales{id_mejor_plan_intento}.NroEtapaAgregar:this.pParOpt.CantidadEtapas
                                for i = 1:length(intentos_actuales{id_mejor_plan_intento}.conectividad_adelantar)
                                    if nro_etapa < intentos_actuales{id_mejor_plan_intento}.etapa_adelantar(i)
                                        % se adelanta proyecto de
                                        % conectividad
                                        proy = this.pAdmProy.entrega_proyecto(intentos_actuales{id_mejor_plan_intento}.conectividad_adelantar(i));
                                        sep_actuales{nro_etapa}.agrega_proyecto(proy);
                                    end
                                end

                                for i = 1:length(intentos_actuales{id_mejor_plan_intento}.proyectos_seleccionados)
                                    proy = this.pAdmProy.entrega_proyecto(intentos_actuales{id_mejor_plan_intento}.proyectos_seleccionados(i));
                                    sep_actuales{nro_etapa}.agrega_proyecto(proy);
                                end
                            end
                        else
                            cant_busqueda_fallida = cant_busqueda_fallida + 1;
                            if this.iNivelDebug > 1
                                if id_mejor_plan_intento > 0 
                                    texto = ['      Mejor intento no mejora plan. Se rechaza el cambio y se agregan todos los proyectos de los intentos a proyectos_restringidor_a_agregar ya que ninguno mejoró' ...
                                             '. Totex actual: ' num2str(estructura_costos_actual.TotexTotal) ' (' num2str(plan_actual_valido) ...
                                             '. Totex mejor intento: ' num2str(intentos_actuales{id_mejor_plan_intento}.Totex) ' (' num2str(intentos_actuales{id_mejor_plan_intento}.Valido)];
                                    prot.imprime_texto(texto);
                                    for kk = 1:this.pParOpt.BLSecuencialCompletoCantProyComparar
                                        if intentos_actuales{kk}.Existe
                                            proyectos_restringidos_a_agregar = [proyectos_restringidos_a_agregar intentos_actuales{kk}.proyectos_seleccionados(end)];
                                        end
                                    end
                                else
                                    texto = ['      No hay mejor intento. ' ...
                                             '. Totex actual: ' num2str(estructura_costos_actual.TotexTotal) ' (' num2str(plan_actual_valido)];
                                    prot.imprime_texto(texto);
                                end
                            end
                        end
                        if this.iNivelDebug > 1
                            prot.imprime_texto('Se imprime plan actual');
                            pPlan.agrega_nombre_proyectos(this.pAdmProy);
                            pPlan.imprime_plan_expansion();
                        end
                    end

                    %guarda plan 
                    cantidad_planes_generados = cantidad_planes_generados + 1;
                    planes_generados{cantidad_planes_generados} = pPlan;
                end %todos los intentos terminados
            end  %plan local terminado
            indice = indice_planes;
        end                

        function [planes_generados, indice] = genera_planes_busqueda_local_secuencial_completo_paralelo(this, nro_iteracion, planes_originales, indice_planes_base)
% this.iNivelDebug = 3;
% this.pAdmProy.iNivelDebug = 2;
% if this.iNivelDebug > 1
% 	prot = cProtocolo.getInstance;
% end
            nivel_debug_paralelo = this.pParOpt.NivelDebugParalelo;
            cantidad_planes_generados = 0;
            planes_generados = cell(1,0);

            cantidad_bl_secuencial_completo = this.pParOpt.BLAgregaProyectosFormaSecuencialCompleto;
            cantidad_planes = length(planes_originales)*cantidad_bl_secuencial_completo;
            cantidad_planes_originales = length(planes_originales);
            cantidad_etapas = this.pParOpt.CantidadEtapas;
            planes_validos = cell(cantidad_planes,1);
            puntos_operacion = this.pAdmSc.entrega_puntos_operacion();
            cantidad_puntos_operacion = length(puntos_operacion);

            CapacidadGeneradores = this.pAdmSc.entrega_capacidad_generadores();
            SerieGeneradoresERNC = this.pAdmSc.entrega_serie_generadores_ernc();
            SerieConsumos = this.pAdmSc.entrega_serie_consumos();
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            
            cant_proy_obligatorios = length(this.pAdmProy.ProyectosObligatorios);
            
            cant_max_busqueda_fallida = this.pParOpt.BLSecuencialCompletoCantBusquedaFallida;
            cant_proy_a_comparar = this.pParOpt.BLSecuencialCompletoCantProyComparar;
            max_cantidad_aumento_totex = this.pParOpt.BLSecuencialCompletoMaxCantAumentoTotexIntento;
            procesos_fallidos = cell(cantidad_planes,1);
            
            cantidad_workers = this.pParOpt.CantWorkers;
            parfor (nro_plan = 1:cantidad_planes, cantidad_workers)
                id_plan_orig = mod(nro_plan,cantidad_planes_originales);
                if id_plan_orig == 0
                    id_plan_orig = cantidad_planes_originales;
                end
                plan_orig = planes_originales(id_plan_orig);
                pPlan = cPlanExpansion(indice_planes_base + nro_plan);
                pPlan.inserta_iteracion(nro_iteracion);
                pPlan.inserta_busqueda_local(true);
                pPlan.inserta_estrategia_busqueda_local(5);
                pPlan.inserta_plan_base(plan_orig.entrega_no());
                
                espacio_proyectos = plan_orig.entrega_proyectos();
                if isempty(espacio_proyectos)
                    % plan no contiene proyectos por lo que no
                    % tiene sentido hacer una búsqueda local
                    delete(pPlan);
                    continue;
                end

                sep_actuales = cell(cantidad_etapas, 0);
                for nro_etapa = 1:cantidad_etapas
                    pPlan.inicializa_etapa(nro_etapa);
                end

                if cant_proy_obligatorios > 0
                    planes_obligatorios_generados = false;
                    % determina cantidad de combinaciones de proyectos
                    % obligatorios a agregar
                    pool_proy_obligatorios = cell(cant_proy_obligatorios, 0);
                    for j = cant_proy_obligatorios:-1:1
                        indices = ismember(espacio_proyectos, this.pAdmProy.ProyectosObligatorios(j).Indice);
                        pool_proy_obligatorios{j} = espacio_proyectos(indices);
                    end
%                   combinaciones_proy_obligatorios = [];
                    if cant_proy_obligatorios > 1
                        error = MException('cOptACO:genera_planes_busqueda_local_secuencial_completo_paralelo','Código actual soporta máximo un grupo de proyectos obligatorios!');
                        throw(error)
                    end
                else
                    planes_obligatorios_generados = true;
                end
                
                %evaluacion_actual = pPlan.entrega_evaluacion();
                %estructura_costos_actual = pPlan.entrega_estructura_costos();
                plan_actual = pPlan.Plan; %plan vacío

                % antes de comenzar, crea evaluación actual. En caso de
                % haber proyectos obligatorios, escoge el proyecto
                % obligatorio base
                if ~planes_obligatorios_generados
                    intento_paralelo_actual = 0;
                    intentos_actuales = cell(1,0);
                    while intento_paralelo_actual < cant_proy_a_comparar
                        intento_paralelo_actual = intento_paralelo_actual +1;
                        sep_actuales_generados = false;
                        if isempty(pool_proy_obligatorios{1})
                            intentos_actuales{intento_paralelo_actual}.Existe = false;
                        else
                            [proyecto_seleccionado, proyectos_conectividad] = this.selecciona_proyecto_obligatorio_a_agregar(pool_proy_obligatorios{1}, espacio_proyectos);
                            pool_proy_obligatorios{1}(ismember(pool_proy_obligatorios{1}, proyecto_seleccionado)) = [];
                            plan_valido = true; % por ahora
                            for nro_etapa = 1:cantidad_etapas
                                % genera sep en la etapa
                                if nro_etapa == 1
                                    if ~sep_actuales_generados
                                        sep_actuales{nro_etapa} = this.pSEP.crea_copia();
                                    end
                                    for i = 1:length(proyectos_conectividad)
                                        proy = this.pAdmProy.entrega_proyecto(proyectos_conectividad(i));
                                        sep_actuales{nro_etapa}.agrega_proyecto(proy);
                                        pPlan.agrega_proyecto(1, proyectos_conectividad(i));
                                    end

                                    proy = this.pAdmProy.entrega_proyecto(proyecto_seleccionado);
                                    sep_actuales{nro_etapa}.agrega_proyecto(proy);
                                    pPlan.agrega_proyecto(1, proyecto_seleccionado);
                                else
                                    if ~sep_actuales_generados
                                        sep_actuales{nro_etapa} = sep_actuales{nro_etapa-1}.crea_copia();
                                    end
                                end

                                if ~sep_actuales_generados
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

                                    this.evalua_red_computo_paralelo(sep_actuales{nro_etapa}, nro_etapa, puntos_operacion, datos_escenario, sbase, [], true); %true indica que proyectos se agregan
                                else
                                    sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                end  
                                this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa);
                                if ~pPlan.es_valido(nro_etapa);
                                    plan_valido = false;
                                end
                            end
                            this.calcula_costos_totales(pPlan);
                            intentos_actuales{intento_paralelo_actual}.Existe = true;
                            intentos_actuales{intento_paralelo_actual}.proyectos_seleccionados = [proyectos_conectividad proyecto_seleccionado];
                            intentos_actuales{intento_paralelo_actual}.Totex = pPlan.entrega_totex_total();
                            intentos_actuales{intento_paralelo_actual}.Valido = plan_valido;
                            intentos_actuales{intento_paralelo_actual}.Plan = pPlan.Plan;
                            intentos_actuales{intento_paralelo_actual}.estructura_costos = pPlan.entrega_estructura_costos();
                            intentos_actuales{intento_paralelo_actual}.evaluacion_actual = pPlan.entrega_evaluacion();

                            %deshace los cambios
                            pPlan.Plan = plan_actual;
                            for nro_etapa = 1:cantidad_etapas
                                proy = this.pAdmProy.entrega_proyecto(proyecto_seleccionado);
                                sep_actuales{nro_etapa}.elimina_proyecto(proy);
                                for i = length(proyectos_conectividad):-1:1
                                    proy = this.pAdmProy.entrega_proyecto(proyectos_conectividad(i));
                                    sep_actuales{nro_etapa}.elimina_proyecto(proy);
                                end
                            end
                        end
                        if ~sep_actuales_generados
                            sep_actuales_generados = true;
                        end
                    end
                    % determina mejor intento
                    mejor_totex = 0;
                    id_mejor_plan_intento = 0;
                    for kk = 1:cant_proy_a_comparar
                        if intentos_actuales{kk}.Existe
                            if id_mejor_plan_intento == 0
                                id_mejor_plan_intento = kk;
                                mejor_totex = intentos_actuales{kk}.Totex;
                            elseif intentos_actuales{kk}.Totex < mejor_totex
                                id_mejor_plan_intento = kk;
                                mejor_totex = intentos_actuales{kk}.Totex;
                            end
% if this.iNivelDebug > 1
%     texto = ['      Intento ' num2str(kk) ' tiene Totex: ' num2str(intentos_actuales{kk}.Totex) '. Es valido?: ' num2str(intentos_actuales{kk}.Valido) '. Proyectos seleccionados: '];
%     for oo = 1:length(intentos_actuales{kk}.proyectos_seleccionados)
%         texto = [texto ' ' num2str(intentos_actuales{kk}.proyectos_seleccionados(oo))];
%     end
%     prot.imprime_texto(texto);
% end 
                        end
                    end

% if this.iNivelDebug > 1
%     texto = ['      Mejor intento: ' num2str(id_mejor_plan_intento)];
%     prot.imprime_texto(texto);
% end

                    plan_actual = intentos_actuales{id_mejor_plan_intento}.Plan;
                    evaluacion_actual = intentos_actuales{id_mejor_plan_intento}.evaluacion_actual;
                    estructura_costos_actual = intentos_actuales{id_mejor_plan_intento}.estructura_costos_actual;
                    plan_actual_valido = intentos_actuales{id_mejor_plan}.Valido;
                    pPlan.Plan = plan_actual;
                    pPlan.inserta_estructura_costos(estructura_costos_actual);
                    pPlan.inserta_evaluacion(evaluacion_actual);
                    pPlan.Valido = plan_actual_valido;

                    espacio_proyectos(ismember(espacio_proyectos, intentos_actuales{id_mejor_plan_intento}.proyectos_seleccionados)) = [];
                    % ingresa los proyectos seleccionados en los sep
                    for nro_etapa = 1:cantidad_etapas
                        for i = 1:length(intentos_actuales{intento_paralelo_actual}.proyectos_seleccionados)
                            proy = this.pAdmProy.entrega_proyecto(intentos_actuales{intento_paralelo_actual}.proyectos_seleccionados(i));
                            sep_actuales{nro_etapa}.agrega_proyecto(proy);
                        end
                    end
                else
                    for nro_etapa = 1:cantidad_etapas
                        % genera sep en la etapa
                        sep_actuales{nro_etapa} = this.pSEP.crea_copia();
                        
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
                        
                        this.evalua_red_computo_paralelo(sep_actuales{nro_etapa}, nro_etapa, puntos_operacion, datos_escenario, sbase, [], true); %true indica que proyectos se agregan
                        this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa);
                    end
                    this.calcula_costos_totales(pPlan);
                    valido = pPlan.es_valido_hasta_etapa(cantidad_etapas);
                    evaluacion_actual = pPlan.entrega_evaluacion();
                    estructura_costos_actual = pPlan.entrega_estructura_costos();
                    pPlan.inserta_estructura_costos(estructura_costos_actual);
                    pPlan.Valido = valido;
                    pPlan.inserta_evaluacion(evaluacion_actual);
                    plan_actual_valido = valido;
                end

% if this.iNivelDebug > 1
%     prot.imprime_texto('Comienzo proyceso agrega proyectos completo');
%     texto = ['      Totex plan vacio: ' num2str(pPlan.entrega_totex_total()) '. Es valido? ' num2str(pPlan.Valido)];
%     prot.imprime_texto(texto);
%     pPlan.agrega_nombre_proyectos(this.pAdmProy);
%     pPlan.imprime_plan_expansion();
% end
                
                % comienza proceso
                cant_busqueda_fallida = 0;
                proyectos_restringidos_a_agregar = [];
                while cant_busqueda_fallida < cant_max_busqueda_fallida
                    intento_paralelo_actual = 0;
                    intentos_actuales = cell(1,0);
                    espacio_proyectos_intento = espacio_proyectos;
                    espacio_proyectos_intento(ismember(espacio_proyectos_intento, proyectos_restringidos_a_agregar)) = [];
                    while intento_paralelo_actual < cant_proy_a_comparar
                        intento_paralelo_actual = intento_paralelo_actual +1;
                        
                        intentos_actuales{intento_paralelo_actual}.Existe = false;
                        if isempty(espacio_proyectos_intento)
                            continue;
                        end
                        % selecciona proyectos
                        
                        
                            
                        [seleccionado, conectividad_agregar, primera_etapa_posible, conectividad_adelantar, etapa_adelantar] = this.selecciona_proyecto_a_agregar(pPlan, ...
                                                                                                                                                                  this.pParOpt.CantidadEtapas, ...
                                                                                                                                                                  espacio_proyectos_intento);
                        espacio_proyectos_intento(ismember(espacio_proyectos_intento, seleccionado)) = [];

                        % Evalua red en cada una de las
                        % etapas. Parte de atrás hacia adelante ya que
                        % es más fácil el cálculo de la etapa "óptima"
                        proyectos_a_agregar = [conectividad_agregar seleccionado];
                        mejor_etapa_actual = 0;
                        mejor_totex_actual = 9999999999999999;
                        mejor_etapa_actual_es_valido = false;
% if this.iNivelDebug > 1
%     texto = ['      Intento ' num2str(intento_paralelo_actual) '. Proyectos (' num2str(length(proyectos_a_agregar)) '): '];
%     for oo = 1:length(proyectos_a_agregar)
%         texto = [texto ' ' num2str(proyectos_a_agregar(oo))];
%     end
%     prot.imprime_texto(texto);
%     if ~isempty(conectividad_adelantar)
%         texto = ['                 Proyectos conectividad adelantar (' num2str(length(conectividad_adelantar)) '): '];
%         for oo = 1:length(conectividad_adelantar)
%             texto = [texto ' ' num2str(conectividad_adelantar(oo)) ' a partir de etapa ' num2str(etapa_adelantar(oo))];
%         end
%         prot.imprime_texto(texto);
%     end
%     texto = ['      Totex actual intento: ' num2str(pPlan.entrega_totex_total())];
%     prot.imprime_texto(texto);
% end
                        cantidad_aumento_totex = 0;   
                        %for nro_etapa = cantidad_etapas:-1:primera_etapa_posible
                        nro_etapa = cantidad_etapas;
                        flag_salida = false;
                        while nro_etapa >= primera_etapa_posible && flag_salida == false
                            for i = 1:length(conectividad_adelantar)
                                if nro_etapa < etapa_adelantar(i)
                                    % se adelanta proyecto de
                                    % conectividad
                                    proy = this.pAdmProy.entrega_proyecto(conectividad_adelantar(i));
                                    sep_actuales{nro_etapa}.agrega_proyecto(proy);
                                    pPlan.adelanta_proyectos(conectividad_adelantar(i), nro_etapa + 1, nro_etapa);
                                end
                            end

                            for i = 1:length(proyectos_a_agregar)
                                proy = this.pAdmProy.entrega_proyecto(proyectos_a_agregar(i));
                                sep_actuales{nro_etapa}.agrega_proyecto(proy);
                                if nro_etapa == cantidad_etapas
                                    pPlan.agrega_proyecto(nro_etapa, proyectos_a_agregar(i));
                                else
                                    pPlan.adelanta_proyectos(proyectos_a_agregar(i), nro_etapa + 1, nro_etapa);
                                end
                            end
                            
                            sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                            this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa);
                            valido = pPlan.es_valido_hasta_etapa(cantidad_etapas);
                            this.calcula_costos_totales(pPlan);

                            if ~sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion().ExisteResultado
                                if isempty(procesos_fallidos{nro_plan})
                                    procesos_fallidos{nro_plan} = pPlan.Plan;
                                    id_fallido = 1;
                                else
                                    procesos_fallidos{nro_plan} = [procesos_fallidos{nro_plan} pPlan.Plan];
                                    id_fallido = length(procesos_fallidos{nro_plan});
                                end

                                nombre_proceso = ['./output/debug/dcopf_proc_fallido_id_' num2str(id_fallido) '_seq_completo_' num2str(pPlan.entrega_no()) '_etapa_' num2str(nro_etapa) '.dat'];
                                sep_actuales{nro_etapa}.entrega_opf().ingresa_nombres_problema();                            
                                sep_actuales{nro_etapa}.entrega_opf().imprime_problema_optimizacion(nombre_proceso);

                                nombre_proceso = ['./output/debug/dcopf_proc_fallido_id' num2str(id_fallido) '_seq_completo_' num2str(pPlan.entrega_no()) '_etapa_' num2str(nro_etapa) '_comparar.dat'];
                                plan_debug = cPlanExpansion(888888889);
                                plan_debug.Plan = pPlan.Plan;
                                plan_debug.inserta_sep_original(this.pSEP.crea_copia());
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
                                
                                this.evalua_plan_computo_paralelo(plan_debug, nro_etapa, puntos_operacion, datos_escenario_debug, sbase);
                                plan_debug.entrega_sep_actual().entrega_opf().ingresa_nombres_problema();
                                plan_debug.entrega_sep_actual().entrega_opf().imprime_problema_optimizacion(nombre_proceso);
                            end
                            
% if this.iNivelDebug > 1
%     texto = ['      Intento al agregar proyectos en etapa ' num2str(nro_etapa) ' tiene totex: ' num2str(pPlan.entrega_totex_total()) '. Es valido: ' num2str(valido)];
%     prot.imprime_texto(texto);
% end

                            if mejor_etapa_actual == 0 || pPlan.entrega_totex_total() < mejor_totex_actual || (~mejor_etapa_actual_es_valido && valido)
                                intentos_actuales{intento_paralelo_actual}.Existe = true;
                                intentos_actuales{intento_paralelo_actual}.proyectos_seleccionados = proyectos_a_agregar;
                                intentos_actuales{intento_paralelo_actual}.Totex = pPlan.entrega_totex_total();
                                intentos_actuales{intento_paralelo_actual}.Valido = valido;
                                intentos_actuales{intento_paralelo_actual}.Plan = pPlan.Plan;
                                intentos_actuales{intento_paralelo_actual}.estructura_costos = pPlan.entrega_estructura_costos();
                                intentos_actuales{intento_paralelo_actual}.evaluacion = pPlan.entrega_evaluacion();
                                intentos_actuales{intento_paralelo_actual}.NroEtapaAgregar = nro_etapa;                                    
                                intentos_actuales{intento_paralelo_actual}.conectividad_adelantar = conectividad_adelantar;
                                intentos_actuales{intento_paralelo_actual}.etapa_adelantar = etapa_adelantar;

                                mejor_etapa_actual = nro_etapa;
                                mejor_totex_actual = pPlan.entrega_totex_total();
                                mejor_etapa_actual_es_valido = valido;
                                cantidad_aumento_totex = 0;
                            else
                                cantidad_aumento_totex = cantidad_aumento_totex + 1;
                            end

                            % elimina proyectos del sep actual
                            for i = length(proyectos_a_agregar):-1:1
                                proy = this.pAdmProy.entrega_proyecto(proyectos_a_agregar(i));
                                sep_actuales{nro_etapa}.elimina_proyecto(proy);
                            end
                            % elimina proyectos de conectividad
                            % adelantados
                            for i = 1:length(conectividad_adelantar)
                                if nro_etapa < etapa_adelantar(i)
                                    % se adelanta proyecto de
                                    % conectividad
                                    proy = this.pAdmProy.entrega_proyecto(conectividad_adelantar(i));
                                    sep_actuales{nro_etapa}.elimina_proyecto(proy);
                                end
                            end

                            if cantidad_aumento_totex == max_cantidad_aumento_totex
                                flag_salida = true;
                            end
                            nro_etapa = nro_etapa - 1;
                        end % fin while nro de etapas
                        
                        % vuelve atrás datos del plan
                        pPlan.Plan = plan_actual;
                        pPlan.inserta_estructura_costos(estructura_costos_actual);
                        pPlan.Valido = plan_actual_valido;
                        pPlan.inserta_evaluacion(evaluacion_actual);
                    end % fin intentos
                            
                    % determina mejor intento
                    mejor_totex = 0;
                    id_mejor_plan_intento = 0;
                    valido_mejor_intento = false;
                    for kk = 1:cant_proy_a_comparar
                        if intentos_actuales{kk}.Existe
                            if id_mejor_plan_intento == 0 || (intentos_actuales{kk}.Totex < mejor_totex) || (~valido_mejor_intento && intentos_actuales{kk}.Valido)
                                id_mejor_plan_intento = kk;
                                mejor_totex = intentos_actuales{kk}.Totex;
                                valido_mejor_intento = intentos_actuales{kk}.Valido;
                            end
% if this.iNivelDebug > 1
%     texto = ['      Intento ' num2str(kk) ' tiene Totex: ' num2str(intentos_actuales{kk}.Totex) ...
%              '. Es valido?: ' num2str(intentos_actuales{kk}.Valido) '. Proyectos seleccionados: '];
%     for oo = 1:length(intentos_actuales{kk}.proyectos_seleccionados)
%         texto = [texto ' ' num2str(intentos_actuales{kk}.proyectos_seleccionados(oo))];
%     end
%     texto = [texto '. Se agregan a etapa: ' num2str(intentos_actuales{kk}.NroEtapaAgregar)];
%     prot.imprime_texto(texto);
% 
%     if ~isempty(intentos_actuales{kk}.conectividad_adelantar)
%         texto = '                                                        Conectividad adelantar: ';
%         for oo = 1:length(intentos_actuales{kk}.conectividad_adelantar)
%             if intentos_actuales{kk}.etapa_adelantar(oo) > intentos_actuales{kk}.NroEtapaAgregar
%                 texto = [texto ' ' num2str(intentos_actuales{kk}.conectividad_adelantar(oo))];
%                 texto = [texto ' desde etapa ' num2str(intentos_actuales{kk}.etapa_adelantar(oo)) '; '];
%             end
%         end
%         prot.imprime_texto(texto);
%     end
% end
                        end
                    end
% if this.iNivelDebug > 1
%     texto = ['      Mejor intento: ' num2str(id_mejor_plan_intento)];
%     prot.imprime_texto(texto);
% end

                    % determina si mejor intento mejora plan
                    if (id_mejor_plan_intento > 0) && (intentos_actuales{id_mejor_plan_intento}.Totex < estructura_costos_actual.TotexTotal) || (~plan_actual_valido && intentos_actuales{id_mejor_plan_intento}.Valido)
% if this.iNivelDebug > 1
%     texto = ['      Mejor intento mejora plan. Se acepta el cambio' ...
%              '. Totex actual: ' num2str(estructura_costos_actual.TotexTotal) ' (Valido: ' num2str(plan_actual_valido) ...
%              '). Totex mejor intento: ' num2str(intentos_actuales{id_mejor_plan_intento}.Totex) ' (' num2str(intentos_actuales{id_mejor_plan_intento}.Valido)];
%     prot.imprime_texto(texto);
%     texto = '      Proyectos seleccionados: ';
%     for oo = 1:length(intentos_actuales{id_mejor_plan_intento}.proyectos_seleccionados)
%         texto = [texto ' ' num2str(intentos_actuales{id_mejor_plan_intento}.proyectos_seleccionados(oo))];
%     end
%     texto = [texto '. Se agregan a etapa: ' num2str(intentos_actuales{id_mejor_plan_intento}.NroEtapaAgregar)];
%     prot.imprime_texto(texto);
%     if ~isempty(intentos_actuales{id_mejor_plan_intento}.conectividad_adelantar)
%         texto = '                                                        Conectividad adelantar: ';
%         for oo = 1:length(intentos_actuales{id_mejor_plan_intento}.conectividad_adelantar)
%             if intentos_actuales{id_mejor_plan_intento}.etapa_adelantar(oo) > intentos_actuales{id_mejor_plan_intento}.NroEtapaAgregar
%                 texto = [texto ' ' num2str(intentos_actuales{id_mejor_plan_intento}.conectividad_adelantar(oo))];
%                 texto = [texto ' desde etapa ' num2str(intentos_actuales{id_mejor_plan_intento}.etapa_adelantar(oo)) '; '];
%             end
%         end
%         prot.imprime_texto(texto);
%     end
% end
                        plan_actual = intentos_actuales{id_mejor_plan_intento}.Plan;
                        evaluacion_actual = intentos_actuales{id_mejor_plan_intento}.evaluacion;
                        estructura_costos_actual = intentos_actuales{id_mejor_plan_intento}.estructura_costos;
                        plan_actual_valido = intentos_actuales{id_mejor_plan_intento}.Valido;
                        pPlan.Plan = plan_actual;
                        pPlan.inserta_estructura_costos(estructura_costos_actual);
                        pPlan.inserta_evaluacion(evaluacion_actual);
                        pPlan.Valido = plan_actual_valido;

                        espacio_proyectos(ismember(espacio_proyectos, intentos_actuales{id_mejor_plan_intento}.proyectos_seleccionados)) = [];
                        % agrega proyectos en los sep
                        for nro_etapa = intentos_actuales{id_mejor_plan_intento}.NroEtapaAgregar:cantidad_etapas
                            for i = 1:length(intentos_actuales{id_mejor_plan_intento}.conectividad_adelantar)
                                if nro_etapa < intentos_actuales{id_mejor_plan_intento}.etapa_adelantar(i)
                                    % se adelanta proyecto de
                                    % conectividad
                                    proy = this.pAdmProy.entrega_proyecto(intentos_actuales{id_mejor_plan_intento}.conectividad_adelantar(i));
                                    sep_actuales{nro_etapa}.agrega_proyecto(proy);
                                end
                            end

                            for i = 1:length(intentos_actuales{id_mejor_plan_intento}.proyectos_seleccionados)
                                proy = this.pAdmProy.entrega_proyecto(intentos_actuales{id_mejor_plan_intento}.proyectos_seleccionados(i));
                                sep_actuales{nro_etapa}.agrega_proyecto(proy);
                            end
                        end
                    else
                        cant_busqueda_fallida = cant_busqueda_fallida + 1;
% if this.iNivelDebug > 1
%     texto = ['      Mejor intento no mejora plan. Se rechaza el cambio y se agregan todos los proyectos de los intentos a proyectos_restringidor_a_agregar ya que ninguno mejoró' ...
%              '. Totex actual: ' num2str(estructura_costos_actual.TotexTotal) ' (' num2str(plan_actual_valido) ...
%              '. Totex mejor intento: ' num2str(intentos_actuales{id_mejor_plan_intento}.Totex) ' (' num2str(intentos_actuales{id_mejor_plan_intento}.Valido)];
%     prot.imprime_texto(texto);
%     for kk = 1:this.pParOpt.BLSecuencialCompletoCantProyComparar
%         if intentos_actuales{kk}.Existe
%             proyectos_restringidos_a_agregar = [proyectos_restringidos_a_agregar intentos_actuales{kk}.proyectos_seleccionados(end)];
%         end
%     end
% end
                    end
% if this.iNivelDebug > 1
%     prot.imprime_texto('Se imprime plan actual');
%     pPlan.agrega_nombre_proyectos(this.pAdmProy);
%     pPlan.imprime_plan_expansion();
% end
                end % fin agrega proyectos para el parfor actual
                planes_validos{nro_plan} = [planes_validos{nro_plan} pPlan];
                pPlan.ResultadoEvaluacion = [];
                
                if nivel_debug_paralelo > 0
                    plan_debug = cPlanExpansion(888888889);
                    plan_debug.Plan = pPlan.Plan;
                    plan_debug.inserta_sep_original(this.pSEP);
                    for etapa_ii = 1:this.pParOpt.CantidadEtapas
                        valido = this.evalua_plan(plan_debug, etapa_ii, 0);
                        if ~valido
                            error = MException('cOptACO:genera_planes_busqueda_local_secuencial_completo_paralelo',...
                            ['Error. Plan debug no es valido en etapa ' num2str(etapa_ii)]);
                            throw(error)
                        end
                    end
                    this.calcula_costos_totales(plan_debug);
% prot.imprime_texto('Se imprime plan debug');
% plan_debug.imprime();
                    if round(plan_debug.entrega_totex_total(),2) ~= round(pPlan.entrega_totex_total(),2)
% texto = 'Totex total de plan debug es distinto de totex total de plan actual!';
% prot.imprime_texto(texto);
% texto = ['Totex total plan debug: ' num2str(round(plan_debug.entrega_totex_total(),3))];
% prot.imprime_texto(texto);
% texto = ['Totex total plan actual: ' num2str(round(pPlan.entrega_totex_total(),3))];
% prot.imprime_texto(texto);
                        texto_error = 'Totex total de plan debug es distinto de totex total de plan actual!';
                        texto_error = [texto_error ' Totex total plan debug: ' num2str(round(plan_debug.entrega_totex_total(),3))];
                        texto_error = [texto_error 'Totex total plan actual: ' num2str(round(pPlan.entrega_totex_total(),3))];

                        error = MException('cOptACO:genera_planes_busqueda_local_secuencial_completo_paralelo',texto_error);
                        throw(error)
                    end
                end
                
            end %fin parfor
            % guarda planes generados
            for i = 1:length(planes_validos)
                if ~isempty(planes_validos{i})
                    planes = planes_validos{i};
                    for j = 1:length(planes)
%                        planes(j).agrega_nombre_proyectos(this.pAdmProy);
%                        planes(j).imprime_plan_expansion();
                        cantidad_planes_generados = cantidad_planes_generados + 1;
                        planes_generados{cantidad_planes_generados} = planes(j);
                    end
                end
            end
            %imprime planes procesos fallidos
            for i = 1:length(procesos_fallidos)
                if ~isempty(procesos_fallidos{i})
                    for j = 1:length(procesos_fallidos{i})
                        plan_falla = cPlanExpansion(77777777777);
                        plan_falla.Plan = procesos_fallidos{i}(j);
                        prot = cProtocolo.getInstance;
                        prot.imprime_texto(['Se imprime plan fallido secuencial completo con proceso paralelo ' num2str(i)]);
                        plan_falla.imprime();
                    end
                end
            end
            
            indice = indice_planes_base + cantidad_planes;            
        end
        
        function indice = genera_planes_busqueda_local_cantidad(this, nro_iteracion, planes_originales, indice_planes)
            if this.iNivelDebug > 0
                prot = cProtocolo.getInstance;
            end
            
            cantidad_planes = length(planes_originales);
            for i = 1:cantidad_planes
            	plan_orig = planes_originales(i);

                if this.iNivelDebug > 1
                    texto = ['Busqueda local cantidad plan ' num2str(i) '/' num2str(cantidad_planes) '. Nro planes validos: ' num2str(this.CantPlanesValidos)];
                    prot.imprime_texto(texto);
                        
                    if this.iNivelDebug > 1
                    	prot.imprime_texto('Se imprime plan base para busqueda local');
                        %if ~plan_orig.nombre_proyectos_disponibles()
                        	plan_orig.agrega_nombre_proyectos(this.pAdmProy);
                        %end
                        plan_orig.imprime();
                    end
                end

                for j = 1:this.pParOpt.BLCantidadProyectos
                    if this.iNivelDebug > 1
                        texto = ['Busqueda local cantidad plan ' num2str(i) '/' num2str(cantidad_planes) ' en nro busqueda ' num2str(j) '/' num2str(this.pParOpt.BLCantidadProyectos)];
                        prot.imprime_texto(texto);
                    end
                    indice_planes = indice_planes + 1;
                    pPlan = cPlanExpansion(indice_planes);
                    pPlan.inserta_iteracion(nro_iteracion);
                    pPlan.inserta_busqueda_local(true);
                    pPlan.inserta_plan_base(plan_orig.entrega_no());
                    pPlan.inserta_estrategia_busqueda_local(2);
                    pPlan.inserta_sep_original(this.pSEP.crea_copia());

                    % genera nuevos planes con cantidad parecida a la
                    % actual
                    nro_etapa = 0;
                    pPlan.Valido = false;

                    while nro_etapa < this.pParOpt.CantidadEtapas
                    	nro_etapa = nro_etapa +1;
                        pPlan.inicializa_etapa(nro_etapa);
                        cant_proy_orig_etapa = plan_orig.cantidad_acumulada_proyectos(nro_etapa);
                        
                        delta_cantidad = this.pAdmProy.CantidadProyectos*this.pParOpt.BLPorcentajeBusquedaCantidad/100;
                        cantidad = max(cant_proy_orig_etapa + ceil(rand*2*delta_cantidad)-delta_cantidad,0);
                        cantidad_proy_obligatorios = length(this.pAdmProy.ProyectosObligatorios);
                        if nro_etapa == 1 && cantidad < cantidad_proy_obligatorios
                            cantidad = cantidad_proy_obligatorios;
                        elseif nro_etapa > 1
                            cantidad_actual = pPlan.cantidad_acumulada_proyectos(nro_etapa-1);
                            cantidad = max(0, cantidad-cantidad_actual);
                        end
                        
                        this.selecciona_plan_expansion(cantidad, nro_etapa, pPlan);
                        valido = this.evalua_plan(pPlan, nro_etapa);
                        while ~valido && (pPlan.CantidadReparaciones < this.pParOpt.MaxNroReparacionesPorEtapa)
                            if this.iNivelDebug > 1
                                texto = ['   Plan ' num2str(pPlan.entrega_no()) ' no es valido en etapa ' num2str(nro_etapa) '(ENS: ' num2str(pPlan.entrega_ens(nro_etapa)) ...
                                    ' Recorte RES: ' num2str(pPlan.entrega_recorte_res(nro_etapa)) ...
                                    '). Se intenta reparar'];
                                prot.imprime_texto(texto);
                            end
                            
                            indice_proy_reparacion = this.repara_plan(pPlan, nro_etapa);
                            if isempty(indice_proy_reparacion)
                                valido = false;
                                if this.iNivelDebug > 1
                                    texto = ['   Plan ' num2str(pPlan.entrega_no()) ' no se pudo reparar. Se descarta'];
                                	prot.imprime_texto(texto);
                                end
                                break;
                            end
                        
                            this.evalua_red(pPlan.entrega_sep_actual(), nro_etapa, indice_proy_reparacion, true); % true indica que proyectos se agregan
                            this.evalua_resultado_y_guarda_en_plan(pPlan, pPlan.entrega_sep_actual().entrega_opf().entrega_evaluacion(), nro_etapa);
                            valido = pPlan.es_valido(nro_etapa);
                            if this.iNivelDebug > 1
                                if valido
                                    texto = ['   Plan ' num2str(pPlan.entrega_no()) ' valido luego de la reparacion'];
                                    prot.imprime_texto(texto);
                                end
                            end
                        end
                    
                        if ~valido
                            if this.iNivelDebug > 1
                                texto = ['   Plan ' num2str(pPlan.entrega_no()) ' no es valido en etapa ' num2str(nro_etapa) ' (ENS: ' num2str(pPlan.entrega_ens(nro_etapa)) ...
                                    ' Recorte RES: ' num2str(pPlan.entrega_recorte_res(nro_etapa)) ...
                                    '). No se puede reparar, por lo que se descarta'];
                                prot.imprime_texto(texto);
                            end
                            pPlan.desecha_plan(nro_etapa)
                            if pPlan.CantidadVecesDesechadoEtapa < this.pParOpt.MaxCantidadGeneracionPlanesPorEtapa
                                nro_etapa = nro_etapa - 1;
                            else
                                pPlan.desecha_plan();
                                nro_etapa = 0;
                                if pPlan.CantidadVecesDesechadoTotal > this.pParOpt.MaxCantidadPlanesDesechados
                                    pPlan.Valido = false;
                                    break;
                                end
                            end
                        else
                            if this.iNivelDebug > 1
                                texto = ['   Plan es valido en etapa ' num2str(nro_etapa)];
                                prot.imprime_texto(texto);
                            end
                            
                            pPlan.Valido = true;
                            pPlan.inicializa_nueva_etapa();
                        end
                    end

                    %fin de la generación y evaluación del plan de expansión. Ahora es
                    %necesario determinar si el plan ya existe y, en caso contrario y
                    %que este sea válido, calcular los costos totales y guardarlo
                    if pPlan.Valido
                        this.calcula_costos_totales(pPlan);
                        this.guarda_plan(pPlan, nro_iteracion, 2); %indica que es busqueda local cantidad
                        this.CantPlanesValidos = this.CantPlanesValidos + 1;
                    else
                        pPlan.ResultadoEvaluacion = [];
                        delete(pPlan);
                    end
                end
            end
            indice = indice_planes;
        end

        function indice = genera_planes_busqueda_local_cantidad_computo_paralelo(this, nro_iteracion, planes_originales, indice_planes_base)
% this.iNivelDebug = 2;
% this.pAdmProy.iNivelDebug = 2;
% if this.iNivelDebug > 1
% 	prot = cProtocolo.getInstance;
% end
            nivel_debug_paralelo = this.pParOpt.NivelDebugParalelo;

            cantidad_bl_agrega_proyectos_cantidad = this.pParOpt.BLCantidadProyectos;
            cantidad_planes = length(planes_originales)*cantidad_bl_agrega_proyectos_cantidad;
            cantidad_planes_originales = length(planes_originales);
            cantidad_etapas = this.pParOpt.CantidadEtapas;
            planes_validos = cell(cantidad_planes,1);
            puntos_operacion = this.pAdmSc.entrega_puntos_operacion();
            cantidad_puntos_operacion = length(puntos_operacion);

            CapacidadGeneradores = this.pAdmSc.entrega_capacidad_generadores();
            SerieGeneradoresERNC = this.pAdmSc.entrega_serie_generadores_ernc();
            SerieConsumos = this.pAdmSc.entrega_serie_consumos();
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            
            delta_cantidad = this.pAdmProy.CantidadProyectos*this.pParOpt.BLPorcentajeBusquedaCantidad/100;
            cantidad_proy_obligatorios = length(this.pAdmProy.ProyectosObligatorios);
            max_cantidad_reparaciones_por_etapa = this.pParOpt.MaxNroReparacionesPorEtapa;
            max_cantidad_planes_desechados = this.pParOpt.MaxCantidadPlanesDesechados;
            max_cantidad_generacion_planes_por_etapa = this.pParOpt.MaxCantidadGeneracionPlanesPorEtapa;
            
            cantidad_workers = this.pParOpt.CantWorkers;
            parfor (nro_plan = 1:cantidad_planes, cantidad_workers)

                id_plan_orig = mod(nro_plan,cantidad_planes_originales);
                if id_plan_orig == 0
                    id_plan_orig = cantidad_planes_originales;
                end
                plan_orig = planes_originales(id_plan_orig);
                pPlan = cPlanExpansion(indice_planes_base + nro_plan);
                pPlan.inserta_iteracion(nro_iteracion);
                pPlan.inserta_busqueda_local(true);
                pPlan.inserta_plan_base(plan_orig.entrega_no());
                pPlan.inserta_estrategia_busqueda_local(2);
        
                % genera nuevos planes con cantidad parecida a la
                % actual
                nro_etapa = 0;
                pPlan.Valido = false;
                sep_actual = cSistemaElectricoPotencia.empty;
                sep_actual_generado = false;

                while nro_etapa < cantidad_etapas
                    nro_etapa = nro_etapa +1;
                    pPlan.inicializa_etapa(nro_etapa);
                    cant_proy_orig_etapa = plan_orig.cantidad_acumulada_proyectos(nro_etapa);
                        
                    cantidad = max(cant_proy_orig_etapa + ceil(rand*2*delta_cantidad)-delta_cantidad,0);
                    if nro_etapa == 1 && cantidad < cantidad_proy_obligatorios
                        cantidad = cantidad_proy_obligatorios;
                    elseif nro_etapa > 1
                        cantidad_actual = pPlan.cantidad_acumulada_proyectos(nro_etapa-1);
                        cantidad = max(0, cantidad-cantidad_actual);
                    end
                    
                    this.selecciona_plan_expansion(cantidad, nro_etapa, pPlan);

                    if ~sep_actual_generado
                        sep_actual = this.pSEP.crea_copia();
                        sep_actual_generado = true;
                    end
                    % agrega proyectos al sep actual
                    proyectos = pPlan.entrega_proyectos(nro_etapa);
                    for k = 1:length(proyectos)
                        proyecto = this.pAdmProy.entrega_proyecto(proyectos(k));
                        sep_actual.agrega_proyecto(proyecto);
% if this.iNivelDebug > 1
%     prot.imprime_texto(['   Nro etapa ' num2str(nro_etapa) ' agrega proyecto: ' num2str(proyectos(k))]);
% end
                    end
                    pOPF = sep_actual.entrega_opf();
                    if isempty(pOPF)
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
                        
                        if strcmp(this.pParOpt.TipoFlujoPotencia, 'DC')
                            pOPF = cDCOPF(sep_actual);
                            pOPF.copia_parametros_optimizacion(this.pParOpt);
                            pOPF.inserta_puntos_operacion(puntos_operacion);
                            pOPF.inserta_datos_escenario(datos_escenario);
                            pOPF.inserta_etapa_datos_escenario(nro_etapa);
                            pOPF.inserta_sbase(sbase);
                            pOPF.inserta_resultados_en_sep(false);
                        else
                            error = MException('cOptMCMC:evalua_red_computo_paralelo','solo flujo DC implementado');
                            throw(error)
                        end
                    else
                        if pOPF.entrega_etapa_datos_escenario() ~= nro_etapa
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

                            pOPF.inserta_puntos_operacion(puntos_operacion);
                            pOPF.inserta_datos_escenario(datos_escenario);
                            pOPF.inserta_etapa_datos_escenario(nro_etapa);
                            pOPF.actualiza_etapa(nro_etapa);
                        end
                    end

                    this.evalua_red(sep_actual, nro_etapa, [], true); % true indica que proyectos se agregan
                    this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actual.entrega_opf().entrega_evaluacion(), nro_etapa);
                    valido = pPlan.es_valido(nro_etapa);

                    while ~valido && (pPlan.CantidadReparaciones < max_cantidad_reparaciones_por_etapa)
% if this.iNivelDebug > 1               
%     texto = ['   Plan ' num2str(pPlan.entrega_no()) ' no es valido (ENS: ' num2str(pPlan.entrega_ens(nro_etapa)) '). Se intenta reparar'];
%     prot.imprime_texto(texto);
% end                        
                        proy_seleccionados = this.repara_plan(pPlan, nro_etapa);
                        if isempty(proy_seleccionados)
                        	valido = false;
% if this.iNivelDebug > 1
%     prot.imprime_texto('   No hay proyectos seleccionados');
% end
                            break;
                        end
                        
                        % ingresa proyectos seleccionados al sep actual
                        for k = 1:length(proy_seleccionados)
                            proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionados(k));
                            sep_actual.agrega_proyecto(proyecto);
% if this.iNivelDebug > 1
%     prot.imprime_texto(['   Proyectos seleccionados en numero intento ' num2str(pPlan.CantidadReparaciones) '/' num2str(max_no_reparaciones_etapa) ' en etapa ' num2str(nro_etapa) ': ' num2str(proy_seleccionados(k))]);
% end
                        end
                        
                        this.evalua_red(sep_actual, nro_etapa, [], true); % true indica que proyectos se agregan
                        this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actual.entrega_opf().entrega_evaluacion(), nro_etapa);
                        valido = pPlan.es_valido(nro_etapa);
% if this.iNivelDebug > 1
%     if valido 
%         prot.imprime_texto('   Plan es valido luego de reparacion');
%     else
%         prot.imprime_texto('   Plan no es valido luego de reparacion');
%     end
% end

                    end
                    
                    if ~valido

% if this.iNivelDebug > 1
%     prot.imprime_texto('   Plan no es valido luego de las reparaciones. Se desecha');
% end                        
                        % desecha plan y elimina proyectos del sep actual
                        proyectos_desechar = pPlan.entrega_proyectos(nro_etapa);
                        for k = length(proyectos_desechar):-1:1
                            proyecto = this.pAdmProy.entrega_proyecto(proyectos_desechar(k));
                            sep_actual.elimina_proyecto(proyecto);
% if this.iNivelDebug > 1
%     prot.imprime_texto(['   Proyecto ' num2str(proyectos_desechar(k)) ' se elimina del plan']);
% end
                        end
                            
                        pPlan.desecha_plan(nro_etapa)
                        if pPlan.CantidadVecesDesechadoEtapa < max_cantidad_generacion_planes_por_etapa
                        	nro_etapa = nro_etapa - 1;
                        else
% if this.iNivelDebug > 1
%     prot.imprime_texto('   Maxima cantidad de intentos alcanzados. Se desecha plan completo');
% end
                            % desecha plan completo
                            proyectos_desechar = pPlan.entrega_proyectos();
                            for k = length(proyectos_desechar):-1:1
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_desechar(k));
                                sep_actual.elimina_proyecto(proyecto);
% if this.iNivelDebug > 1
%     prot.imprime_texto(['   Proyecto ' num2str(proyectos_desechar(k)) ' se elimina del plan']);
% end
                            end
                            
                        	pPlan.desecha_plan();
                            nro_etapa = 0;
                            if pPlan.CantidadVecesDesechadoTotal > max_cantidad_planes_desechados
                            	pPlan.Valido = false;
                                break;
                            end
                        end
                    else                            
                        pPlan.Valido = true;
                        pPlan.inicializa_nueva_etapa();                                                
                    end
                end
                this.calcula_costos_totales(pPlan);
% if this.iNivelDebug > 1
%     prot.imprime_texto('Se imprime plan calculado');
%     % imprime plan
%     pPlan.imprime();
%end                    
                %fin de la generación y evaluación del plan de expansión
                if pPlan.Valido
                    planes_validos{nro_plan} = [planes_validos{nro_plan} pPlan];
                else
                    pPlan.ResultadoEvaluacion = [];
                	delete(pPlan);                    
                end
            end
            for i = 1:length(planes_validos)
                if ~isempty(planes_validos{i})
                    this.guarda_plan(planes_validos{i}, nro_iteracion, 2);
                    this.CantPlanesValidos = this.CantPlanesValidos + 1;
                    
                    if nivel_debug_paralelo > 0
                        plan_debug = cPlanExpansion(888888889);
                        plan_debug.Plan = planes_validos{i}.Plan;
                        plan_debug.inserta_sep_original(this.pSEP.crea_copia());
                        for etapa_ii = 1:this.pParOpt.CantidadEtapas

                            valido = this.evalua_plan(plan_debug, etapa_ii, 0);
                            if ~valido
                                error = MException('cOptACO:genera_planes_base_computo_paralelo',...
                                ['Error. Plan debug no es valido en etapa ' num2str(etapa_ii)]);
                                throw(error)
                            end
                        end
                        this.calcula_costos_totales(plan_debug);
                        if round(plan_debug.entrega_totex_total(),2) ~= round(planes_validos{i}.entrega_totex_total(),2)
                            prot = cProtocolo.getInstance;
                            texto = 'Totex total de plan debug es distinto de totex total de plan actual!';
                        
                            prot.imprime_texto(texto);
                            texto = ['Totex total plan debug: ' num2str(round(plan_debug.entrega_totex_total(),3))];
                            prot.imprime_texto(texto);
                            texto = ['Totex total plan actual: ' num2str(round(pPlan.entrega_totex_total(),3))];
                            prot.imprime_texto(texto);

                            prot.imprime_texto('Se imprime plan original');
                            planes_validos{i}.imprime();

                            prot.imprime_texto('Se imprime plan debug');
                            plan_debug.imprime();
                            
                            texto_error = 'Totex total de plan debug es distinto de totex total de plan actual!';
                            texto_error = [texto_error ' Totex total plan debug: ' num2str(round(plan_debug.entrega_totex_total(),3))];
                            texto_error = [texto_error 'Totex total plan actual: ' num2str(round(pPlan.entrega_totex_total(),3))];
                            error = MException('cOptACO:genera_planes_base_computo_paralelo',texto_error);
                            throw(error)
                        end
                    end 
                end
            end
            
            indice = indice_planes_base + cantidad_planes;
        end
        
        function indice = genera_planes_busqueda_local_desplaza(this, nro_iteracion, planes_originales, indice_planes)
            if this.iNivelDebug > 0
                prot = cProtocolo.getInstance;
            end

            cantidad_planes = length(planes_originales);
            for i = 1:cantidad_planes
            	plan_orig = planes_originales(i);
                nro_plan_orig = planes_originales(i).entrega_no();
                if this.iNivelDebug > 1
                    totex_orig = planes_originales(i).entrega_totex_total();
                    cantidad_proy_orig = planes_originales(i).cantidad_acumulada_proyectos();
                    texto = ['Busqueda local desplaza plan ' num2str(i) '/' num2str(cantidad_planes) '. Nro planes validos: ' num2str(this.CantPlanesValidos)];
                    prot.imprime_texto(texto);
                        
                    if this.iNivelDebug > 1
                    	prot.imprime_texto('Se imprime plan base para busqueda local');
                        plan_orig.agrega_nombre_proyectos(this.pAdmProy);
                        plan_orig.imprime();
                    end
                end
                
                indice_planes = indice_planes + 1;
                pPlan = plan_orig.crea_copia(indice_planes);
                pPlan.inserta_iteracion(nro_iteracion);
                pPlan.inserta_busqueda_local(true);
                pPlan.inserta_plan_base(nro_plan_orig);
                pPlan.inserta_estrategia_busqueda_local(3);
                pPlan.inserta_estructura_costos(plan_orig.entrega_estructura_costos());
                pPlan.Plan = plan_orig.Plan;
                pPlan.inserta_evaluacion(plan_orig.entrega_evaluacion());
                for nro_intento = 1:this.pParOpt.BLDesplazaProyectos
                    if this.iNivelDebug > 1
                        texto = ['Busqueda local desplaza proyectos plan ' num2str(i) '/' num2str(cantidad_planes) ' en nro busqueda ' num2str(nro_intento) '/' num2str(this.pParOpt.BLDesplazaProyectos)];
                        prot.imprime_texto(texto);
                    end
                    if nro_intento > 1
                        indice_planes = indice_planes + 1;
                        pPlan = cPlanExpansion(indice_planes);
                        pPlan.inserta_iteracion(nro_iteracion);
                        pPlan.inserta_busqueda_local(true);
                        pPlan.inserta_plan_base(nro_plan_orig);
                        pPlan.inserta_estrategia_busqueda_local(3);
                        pPlan.inserta_estructura_costos(plan_orig.entrega_estructura_costos());
                        pPlan.Plan = plan_orig.Plan;
                        pPlan.inserta_evaluacion(plan_orig.entrega_evaluacion());
                    end
                    
                    % evalua plan y retrasa entrada de proyectos hasta que
                    % costo total de la etapa sea mayor que costo base
                    nro_etapa = 0;
                    pPlan.Valido = true;  % se asume que plan es válido ya que se está en la búsqueda local. De todas formas, si resulta ser no válido entonces igual se ingresa

                    sep_actual = this.pSEP.crea_copia();
                    
                    while nro_etapa < this.pParOpt.CantidadEtapas
                    	nro_etapa = nro_etapa +1;
                        
                        %actualiza datos sep_actual
                        for j = 1:length(pPlan.Plan(nro_etapa).Proyectos)
                            indice = pPlan.Plan(nro_etapa).Proyectos(j);
                            proyecto = this.pAdmProy.entrega_proyecto(indice);
%sep_actual_debug.agrega_proyecto(proyecto)                            
                            if ~sep_actual.agrega_proyecto(proyecto)
                            	% Error (probablemente de programación). 
                                texto = ['Error de programacion. Plan ' num2str(pPlan.entrega_no()) ' no pudo ser implementado en SEP en etapa ' num2str(nro_etapa)];
                                error = MException('cOptACO:genera_planes_busqueda_local_desplaza',texto);
                                throw(error)
                            end
                        end

                        estructura_costos_actual = pPlan.entrega_estructura_costos();
                        plan_actual = pPlan.Plan;
                        evaluacion_actual = pPlan.entrega_evaluacion(nro_etapa);
                        
                        proyectos_restringidos_para_desplazar = []; % ya fueron analizados/desplazados en etapa anterior
                        proyectos_desplazados = [];
                        cant_busqueda_fallida = 0;
                        while cant_busqueda_fallida < this.pParOpt.BLEliminaDesplazaCantBusquedaFallida
                            proyectos_seleccionados = this.selecciona_proyectos_a_desplazar(pPlan, nro_etapa, proyectos_restringidos_para_desplazar);
                            if isempty(proyectos_seleccionados)
                                cant_busqueda_fallida = cant_busqueda_fallida + 1;
                                continue;
                            end
                            
                            % elimina proyectos de sep actual y desplaza
                            % proyectos en el plan. Ojo que se eliminan en
                            % orden inverso!
                            for k = length(proyectos_seleccionados):-1:1
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_seleccionados(k));
                                sep_actual.elimina_proyecto(proyecto);
                                if nro_etapa < this.pParOpt.CantidadEtapas
                                    pPlan.desplaza_proyectos(proyectos_seleccionados(k), nro_etapa, nro_etapa + 1);
                                else
                                    pPlan.elimina_proyectos(proyectos_seleccionados(k), nro_etapa);
                                end
                            end
                            
                            %evalua red (proyectos ya se ingresaron al sep)
                            this.evalua_red(sep_actual, nro_etapa, [], false); % false indica que proyectos se eliminan
                            this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actual.entrega_opf().entrega_evaluacion(), nro_etapa);
                            this.calcula_costos_totales(pPlan);

                            if pPlan.es_valido(nro_etapa) && pPlan.entrega_totex_total() < estructura_costos_actual.TotexTotal
                                % cambio produce mejora. Se acepta
                                estructura_costos_actual = pPlan.entrega_estructura_costos();
                                plan_actual = pPlan.Plan;
                                evaluacion_actual = pPlan.entrega_evaluacion(nro_etapa);
                                cant_busqueda_fallida = 0;                                
                                proyectos_desplazados = [proyectos_desplazados proyectos_seleccionados];
                                
                                if this.iNivelDebug > 1
                                    texto_desplazados = '';
                                    for jj = 1:length(proyectos_seleccionados)
                                        texto_desplazados = [texto_desplazados ' ' num2str(proyectos_seleccionados(jj))];
                                    end
                                    texto = ['   Nuevo(s) proyecto(s) desplazados etapa ' num2str(nro_etapa) ':' texto_desplazados ' generan mejora'];
                                    prot.imprime_texto(texto);
                                end
                            else
                                % cambio no produce mejora. Se deshace. 
                                if this.iNivelDebug > 1
                                    texto_desplazados = '';
                                    for jj = 1:length(proyectos_seleccionados)
                                        texto_desplazados = [texto_desplazados ' ' num2str(proyectos_seleccionados(jj))];
                                    end
                                    if pPlan.es_valido(nro_etapa)
                                        texto = ['   Proyectos desplazados etapa ' num2str(nro_etapa) ':' texto_desplazados ' no generan mejora. Se vuelven a insertar'];
                                    else
                                        texto = ['   Proyectos desplazados etapa ' num2str(nro_etapa) ':' texto_desplazados ' vuelven al plan invalido. Se vuelven a insertar'];
                                    end                                        
                                        prot.imprime_texto(texto);
                                end
                                pPlan.inserta_evaluacion_etapa(nro_etapa, evaluacion_actual);
                                pPlan.Plan = plan_actual;
                                pPlan.inserta_estructura_costos(estructura_costos_actual);
                            	proyectos_restringidos_para_desplazar = [proyectos_restringidos_para_desplazar proyectos_seleccionados];
                            
                                cant_busqueda_fallida = cant_busqueda_fallida + 1;
                                
                                % deshace los cambios hechos en los sep
                                % actuales
                                for k = 1:length(proyectos_seleccionados)
                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_seleccionados(k));
                                    sep_actual.agrega_proyecto(proyecto);
                                end
                            end
                        end
                        
                        % fin de desplazamiento para la etapa
                        if this.iNivelDebug > 1
                            texto = ['Cantidad de proyectos desplazados plan ' num2str(pPlan.entrega_no()) ' en etapa ' num2str(nro_etapa) ': ' num2str(length(proyectos_desplazados))];
                            prot.imprime_texto(texto)
                        end
                    end

                    if this.iNivelDebug > 2
                        % imprime plan
                        pPlan.agrega_nombre_proyectos(this.pAdmProy);
                        pPlan.imprime();
                    end
                    % guarda plan
%                    this.calcula_costos_totales(pPlan);
                    pPlan.ResultadoEvaluacion = [];
                    this.guarda_plan(pPlan, nro_iteracion, 3); %indica que es busqueda local desplaza proyectos

                    this.CantPlanesValidos = this.CantPlanesValidos + 1;
                    if this.iNivelDebug > 1
                        texto = ['   Plan bl desplaza ' num2str(pPlan.entrega_no()) ' Es valido. '];
                        texto = [texto 'Cantidad planes: ' num2str(pPlan.cantidad_acumulada_proyectos()) '. (Original: ' num2str(plan_orig.cantidad_acumulada_proyectos()) ')'];
                        prot.imprime_texto(texto);
                    end
                end %todas las hormigas de la búsqueda local finalizadas
            end  %plan local terminado                
            indice = indice_planes;
        end

        function indice = genera_planes_busqueda_local_desplaza_computo_paralelo(this, nro_iteracion, planes_originales, indice_planes_base)
% this.iNivelDebug = 3;
% this.pAdmProy.iNivelDebug = 2;
% if this.iNivelDebug > 1
% 	prot = cProtocolo.getInstance;
% end
            cantidad_planes = length(planes_originales);
            cantidad_bl_desplaza_proyectos = this.pParOpt.BLDesplazaProyectos;
            indice_planes = zeros(cantidad_planes,1);
            for i = 1:cantidad_planes
                indice_planes(i) = indice_planes_base + (i-1)*cantidad_bl_desplaza_proyectos;
            end
            cantidad_etapas = this.pParOpt.CantidadEtapas;
            planes_validos = cell(cantidad_planes,1);
            puntos_operacion = this.pAdmSc.entrega_puntos_operacion();
            datos_escenario_total = cell(cantidad_planes,1);

            for i = 1:cantidad_planes
                datos_escenario_total{i}.CapacidadGeneradores = this.pAdmSc.entrega_capacidad_generadores();
                datos_escenario_total{i}.SerieGeneradoresERNC = this.pAdmSc.entrega_serie_generadores_ernc();
                datos_escenario_total{i}.SerieConsumos = this.pAdmSc.entrega_serie_consumos();
            end
            sep_base = cSistemaElectricoPotencia.empty(cantidad_planes, cantidad_bl_desplaza_proyectos, 0);
            for i = 1:cantidad_planes
                for j = 1:cantidad_bl_desplaza_proyectos
                    sep_base{i,j} = this.pSEP.crea_copia();
                end
            end
            datos_escenario = cell(cantidad_planes,1);
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            cant_bl_desplaza_busqueda_fallida = this.pParOpt.BLEliminaDesplazaCantBusquedaFallida;

            cantidad_workers = this.pParOpt.CantWorkers;
            parfor (nro_plan = 1:cantidad_planes, cantidad_workers)
% for nro_plan = 1:cantidad_planes
            	plan_orig = planes_originales(nro_plan);
                nro_plan_orig = plan_orig.entrega_no();

% if this.iNivelDebug > 1
% 	prot = cProtocolo.getInstance;
%     prot.imprime_texto(['Busqueda local desplaza plan ' num2str(nro_plan) '/' num2str(cantidad_planes) '. Nro planes validos: ' num2str(this.CantPlanesValidos)]);
%     prot.imprime_texto('Se imprime plan base para busqueda local');
%     if ~plan_orig.nombre_proyectos_disponibles()
%     	plan_orig.agrega_nombre_proyectos(this.pAdmProy);
%     end
%     plan_orig.imprime();
%     totex_orig = planes_originales(nro_plan).entrega_totex_total();
%     cantidad_proy_orig = planes_originales(nro_plan).cantidad_acumulada_proyectos();
% end

                indice_planes(nro_plan) = indice_planes(nro_plan) + 1;
                pPlan = plan_orig.crea_copia(indice_planes(nro_plan));
                pPlan.inserta_iteracion(nro_iteracion);
                pPlan.inserta_busqueda_local(true);
                pPlan.inserta_plan_base(nro_plan_orig);
                pPlan.inserta_estrategia_busqueda_local(3);
                pPlan.inserta_estructura_costos(plan_orig.entrega_estructura_costos());
                pPlan.Plan = plan_orig.Plan;
                pPlan.inserta_evaluacion(plan_orig.entrega_evaluacion());
                cantidad_puntos_operacion = length(puntos_operacion);
                
                for nro_intento = 1:cantidad_bl_desplaza_proyectos
% if this.iNivelDebug > 1
% 	prot.imprime_texto(['Busqueda local desplaza proyectos plan ' num2str(nro_plan) '/' num2str(cantidad_planes) ' en nro busqueda ' num2str(nro_intento) '/' num2str(this.pParOpt.BLDesplazaProyectos)]);
% end

                    if nro_intento > 1
                        indice_planes(nro_plan) = indice_planes(nro_plan) + 1;
                        pPlan = cPlanExpansion(indice_planes(nro_plan));
                        pPlan.inserta_iteracion(nro_iteracion);
                        pPlan.inserta_busqueda_local(true);
                        pPlan.inserta_plan_base(nro_plan_orig);
                        pPlan.inserta_estrategia_busqueda_local(3);
                        pPlan.inserta_estructura_costos(plan_orig.entrega_estructura_costos());
                        pPlan.Plan = plan_orig.Plan;
                        pPlan.inserta_evaluacion(plan_orig.entrega_evaluacion());
                    end
                    
                    % evalua plan y retrasa entrada de proyectos hasta que
                    % costo total de la etapa sea mayor que costo base
                    nro_etapa = 0;
                    pPlan.Valido = true;  % se asume que plan es válido ya que se está en la búsqueda local. De todas formas, si resulta ser no válido entonces igual se ingresa

                    sep_actual = sep_base{nro_plan, nro_intento};
%this.pParOpt.NivelDebugOPF = 2;
%sep_actual_debug = sep_base{nro_plan, nro_intento}.crea_copia();
                    while nro_etapa < cantidad_etapas
                    	nro_etapa = nro_etapa +1;

% if this.iNivelDebug > 2
% 	prot = cProtocolo.getInstance;
%     prot.imprime_texto(['   Plan actual hasta etapa ' num2str(nro_etapa)]);
% 	pPlan.agrega_nombre_proyectos(this.pAdmProy);
%     pPlan.imprime_hasta_etapa(nro_etapa);
% end

                        % actualiza datos escenario
                        datos_escenario{nro_plan}.CapacidadGeneradores = datos_escenario_total{nro_plan}.CapacidadGeneradores(:,nro_etapa);
                        indice_1 = 1 + (nro_etapa - 1)*cantidad_puntos_operacion;
                        indice_2 = nro_etapa*cantidad_puntos_operacion;
                        if ~isempty(datos_escenario_total{nro_plan}.SerieGeneradoresERNC)
                        	datos_escenario{nro_plan}.SerieGeneradoresERNC{nro_plan} = datos_escenario_total{nro_plan}.SerieGeneradoresERNC(:,indice_1:indice_2);
                        else
                        	datos_escenario{nro_plan}.SerieGeneradoresERNC{nro_plan} = [];
                        end
                        datos_escenario{nro_plan}.SerieConsumos = datos_escenario_total{nro_plan}.SerieConsumos(:,indice_1:indice_2);
                        
                        %actualiza datos sep_actual
                        for j = 1:length(pPlan.Plan(nro_etapa).Proyectos)
                            indice = pPlan.Plan(nro_etapa).Proyectos(j);
                            proyecto = this.pAdmProy.entrega_proyecto(indice);
%sep_actual_debug.agrega_proyecto(proyecto)                            
                            if ~sep_actual.agrega_proyecto(proyecto)
                            	% Error (probablemente de programación). 
                                texto = ['Error de programacion. Plan ' num2str(pPlan.entrega_no()) ' no pudo ser implementado en SEP en etapa ' num2str(nro_etapa)];
                                error = MException('cOptACO:genera_planes_busqueda_local_desplaza',texto);
                                throw(error)
                            end
                        end
                        
                        estructura_costos_actual = pPlan.entrega_estructura_costos();
                        plan_actual = pPlan.Plan;
                        evaluacion_actual = pPlan.entrega_evaluacion(nro_etapa);
                        
                        proyectos_restringidos_para_desplazar = [];
% proyectos_desplazados = [];

                        cant_busqueda_fallida = 0;
                        while cant_busqueda_fallida < cant_bl_desplaza_busqueda_fallida
                            proyectos_seleccionados = this.selecciona_proyectos_a_desplazar(pPlan, nro_etapa, proyectos_restringidos_para_desplazar);
                            if isempty(proyectos_seleccionados)
                                cant_busqueda_fallida = cant_busqueda_fallida + 1;
                                continue;
                            end
                            
                            %evalua red (proyectos ya se ingresaron al sep)
%for k = 1:length(proyectos_seleccionados)
%	proyecto = this.pAdmProy.entrega_proyecto(proyectos_seleccionados(k));
%    sep_actual_debug.elimina_proyecto(proyecto);
%end
%evalua red (proyectos ya se ingresaron al sep)
%this.evalua_red(sep_actual_debug, nro_etapa, [], false); % false indica que proyectos se eliminan

                            % orden inverso

                            for kk = length(proyectos_seleccionados):-1:1
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_seleccionados(kk));
                                sep_actual.elimina_proyecto(proyecto);
                                if nro_etapa < this.pParOpt.CantidadEtapas
                                    pPlan.desplaza_proyectos(proyectos_seleccionados(kk), nro_etapa, nro_etapa + 1);
                                else
                                    pPlan.elimina_proyectos(proyectos_seleccionados(kk), nro_etapa);
                                end
                            end

                            this.evalua_red_computo_paralelo(sep_actual, nro_etapa, puntos_operacion, datos_escenario{nro_plan}, sbase, [], false);
                            this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actual.entrega_opf().entrega_evaluacion(), nro_etapa);
                            this.calcula_costos_totales(pPlan);
                            
                            if pPlan.es_valido(nro_etapa) && pPlan.entrega_totex_total() < estructura_costos_actual.TotexTotal
                                % cambio produce mejora. Se acepta
                                estructura_costos_actual = pPlan.entrega_estructura_costos();
                                plan_actual = pPlan.Plan;
                                evaluacion_actual = pPlan.entrega_evaluacion(nro_etapa);
                                cant_busqueda_fallida = 0;
                                
% proyectos_desplazados = [proyectos_desplazados proyectos_seleccionados];                                
% if this.iNivelDebug > 1
% 	prot = cProtocolo.getInstance;
% 	texto_desplazados = '';
% 	for jj = 1:length(proyectos_seleccionados)
%         texto_desplazados = [texto_desplazados ' ' num2str(proyectos_seleccionados(jj))];
%     end
% 	texto = ['   Nuevo(s) proyecto(s) desplazados etapa ' num2str(nro_etapa) ':' texto_desplazados ' generan mejora'];
% 	prot.imprime_texto(texto);
% end
                            else
                                % cambio no produce mejora. Se deshace. 
                                pPlan.inserta_evaluacion_etapa(nro_etapa, evaluacion_actual);
                                pPlan.Plan = plan_actual;
                                pPlan.inserta_estructura_costos(estructura_costos_actual);
                            	proyectos_restringidos_para_desplazar = [proyectos_restringidos_para_desplazar proyectos_seleccionados];
                            
                                cant_busqueda_fallida = cant_busqueda_fallida + 1;
                                
% if this.iNivelDebug > 1
%     prot = cProtocolo.getInstance;
% 	texto_desplazados = '';
% 	for jj = 1:length(proyectos_seleccionados)
%         texto_desplazados = [texto_desplazados ' ' num2str(proyectos_seleccionados(jj))];
%     end
% 	if pPlan.es_valido(nro_etapa)
%         texto = ['   Proyectos desplazados etapa ' num2str(nro_etapa) ':' texto_desplazados ' no generan mejora. Se vuelven a insertar'];
%     else
%         texto = ['   Proyectos desplazados etapa ' num2str(nro_etapa) ':' texto_desplazados ' vuelven al plan invalido. Se vuelven a insertar'];
%     end
% 	prot.imprime_texto(texto);
% end
                                
                                % deshace los cambios hechos en los sep
                                % actuales
                                for k = 1:length(proyectos_seleccionados)
                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_seleccionados(k));
                                    sep_actual.agrega_proyecto(proyecto);
                                end
                            end
                        end
                        
                        % fin de desplazamiento para la etapa
% if this.iNivelDebug > 1
% 	texto = ['Cantidad de proyectos desplazados plan ' num2str(pPlan.entrega_no()) ' en etapa ' num2str(nro_etapa) ': ' num2str(length(proyectos_desplazados))];
% 	prot.imprime_texto(texto)
% end
                    end % fin de todas las etapas
                    
                    % limpia la memoria
%                    sep_actual = cSistemaElectricoPotencia.empty;
%                    clear sep_actual
                    sep_actual = [];
                    sep_base{nro_plan, nro_intento} = cSistemaElectricoPotencia.empty;
                    %guarda plan si este es válido
                    
                    planes_validos{nro_plan} = [planes_validos{nro_plan} pPlan];
                    pPlan.ResultadoEvaluacion = [];
                end %todas las hormigas de la búsqueda local finalizadas
                
                % libera memoria
                datos_escenario_total{nro_plan} = [];
                datos_escenario{nro_plan} = [];
            end  %plan local terminado
            
            sep_base = [];
            clear sep_base
            
            % guarda planes validos 
            for i = 1:length(planes_validos)
                if ~isempty(planes_validos{i})
                    planes = planes_validos{i};
                    for j = 1:length(planes)
                        this.guarda_plan(planes(j), nro_iteracion, 3);
                        this.CantPlanesValidos = this.CantPlanesValidos + 1;
                    end
                end
            end
            indice = indice_planes(end);
% this.iNivelDebug = 1;
% this.pAdmProy.iNivelDebug = 0;

        end

        function [planes_generados, indice] = genera_planes_bl_elimina_desplaza(this, nro_iteracion, planes_originales, indice_planes, proyectos_al_comienzo)
            if this.iNivelDebug > 0
                prot = cProtocolo.getInstance;
            end
            
            cantidad_planes_generados = 0;
            planes_generados = cell(1,0);
            
            cantidad_planes = length(planes_originales);
            for nro_plan = 1:cantidad_planes
            	plan_orig = planes_originales(nro_plan);
                nro_plan_orig = planes_originales(nro_plan).entrega_no();
                if this.iNivelDebug > 1
                    totex_orig = planes_originales(nro_plan).entrega_totex_total();
                    cantidad_proy_orig = planes_originales(nro_plan).cantidad_acumulada_proyectos();
                    texto = ['Busqueda local elimina desplaza plan ' num2str(nro_plan) '/' num2str(cantidad_planes) '. Nro planes validos: ' num2str(this.CantPlanesValidos)];
                    prot.imprime_texto(texto);                        
                end
                
                if plan_orig.cantidad_acumulada_proyectos() == 0
                    if this.iNivelDebug > 1
                    	prot.imprime_texto('No se hace nada con el plan, ya que no contiene proyectos');
                    end
                    continue;
                end
                indice_planes = indice_planes + 1;
                pPlan = cPlanExpansion(indice_planes);
                pPlan.inserta_iteracion(nro_iteracion);
                pPlan.inserta_busqueda_local(true);
                pPlan.inserta_plan_base(nro_plan_orig);
                if proyectos_al_comienzo
                    pPlan.inserta_estrategia_busqueda_local(42);
                    proyectos = plan_orig.entrega_proyectos();
                    pPlan.inserta_sep_original(this.pSEP);
                    for nro_etapa = 1:this.pParOpt.CantidadEtapas
                        pPlan.inicializa_etapa(nro_etapa);
                        if nro_etapa == 1
                            pPlan.inserta_proyectos_etapa(1, proyectos);
                        end
                        valido = this.evalua_plan(pPlan, nro_etapa);
                        
                        if ~valido
                            texto = 'Error de programacion. Plan final de desplaza elimina no es válido';
                            error = MException('cOptACO:genera_planes_bl_elimina_desplaza',texto);
                            throw(error)
                        end
                    end
                    this.calcula_costos_totales(pPlan);
                else
                    pPlan.inserta_estrategia_busqueda_local(41);
                    pPlan.Plan = plan_orig.Plan;
                    pPlan.inserta_estructura_costos(plan_orig.entrega_estructura_costos());
                    pPlan.inserta_evaluacion(plan_orig.entrega_evaluacion());
                end
                
                if this.iNivelDebug > 1
                    prot.imprime_texto('Se imprime plan base para busqueda local');
                    pPlan.agrega_nombre_proyectos(this.pAdmProy);
                    pPlan.imprime();
                end
                
                estructura_costos_plan_base = pPlan.entrega_estructura_costos();
                plan_expansion_plan_base = pPlan.Plan;
                evaluacion_plan_base = pPlan.entrega_evaluacion();
                for nro_intento = 1:this.pParOpt.BLEliminaDesplazaProyectos
                    if this.iNivelDebug > 1
                        texto = ['Busqueda local elimina desplaza proyectos plan ' num2str(nro_plan) '/' num2str(cantidad_planes) ' en nro busqueda ' num2str(nro_intento) '/' num2str(this.pParOpt.BLEliminaDesplazaProyectos)];
                        
                        totex_despues_de_elimina = -1;
                        cantidad_proy_despues_de_elimina = -1;
                        totex_despues_de_nuevo_desplaza = -1;
                        cantidad_proy_despues_de_nuevo_desplaza = -1;
                        totex_despues_de_nuevo_agrega = -1;
                        cantidad_proy_despues_de_nuevo_agrega = -1;
                    end
                    if nro_intento > 1
                        indice_planes = indice_planes + 1;
                        
                        pPlan = cPlanExpansion(indice_planes);
                        pPlan.inserta_iteracion(nro_iteracion);
                        pPlan.inserta_busqueda_local(true);
                        pPlan.inserta_plan_base(nro_plan_orig);
                        if proyectos_al_comienzo
                            pPlan.inserta_estrategia_busqueda_local(42);
                        else
                            pPlan.inserta_estrategia_busqueda_local(41);
                        end
                        
                        pPlan.inserta_estructura_costos(estructura_costos_plan_base);
                        pPlan.Plan = plan_expansion_plan_base;
                        pPlan.inserta_evaluacion(evaluacion_plan_base);
                    end
    
                    pPlan.Valido = true;
                    % Primero se eliminan proyectos que no se
                    % necesitan. Estos se identifican en la etapa final
                    if this.iNivelDebug > 1
                    	texto = ['Elimina proyectos innecesarios en busqueda local elimina desplaza proyectos plan ' num2str(nro_plan) '/' num2str(cantidad_planes)];
                        prot.imprime_texto(texto);
                    end

                    % crea sep actuales por cada etapa (para mejorar
                    % performance del programa)
                    sep_actuales = cSistemaElectricoPotencia.empty(this.pParOpt.CantidadEtapas,0);
                    for nro_etapa = 1:this.pParOpt.CantidadEtapas
                        if nro_etapa == 1
                            sep_actuales{nro_etapa} = this.pSEP.crea_copia();
                        else
                            sep_actuales{nro_etapa} = sep_actuales{nro_etapa-1}.crea_copia();
                        end
                    
                        for j = 1:length(pPlan.Plan(nro_etapa).Proyectos)
                            indice = pPlan.Plan(nro_etapa).Proyectos(j);
                            proyecto = this.pAdmProy.entrega_proyecto(indice);
                            if ~sep_actuales{nro_etapa}.agrega_proyecto(proyecto)
                                % Error (probablemente de programación). 
                                texto = ['Error de programacion. Plan ' num2str(pPlan.entrega_no()) ' no pudo ser implementado en SEP en etapa ' num2str(etapa_previa)];
                                error = MException('cOptACO:genera_planes_bl_elimina_desplaza',texto);
                                throw(error)
                            end
                        end
                    end
                    
                    proyectos_restringidos_para_eliminar = [];
                    proyectos_eliminados = [];
                    proyectos_desplazados = [];
                    etapas_desplazados = [];

                    evaluacion_actual = pPlan.entrega_evaluacion();
                    estructura_costos_actual = pPlan.entrega_estructura_costos();
                    plan_actual = pPlan.Plan;
                    cant_busqueda_fallida = 0;
                    proy_potenciales_eliminar = []; % no se verifica adelanta
                    proy_potenciales_adelantar = []; %también se analiza elimina
                    
                    while cant_busqueda_fallida < this.pParOpt.BLEliminaDesplazaCantBusquedaFallida
                        intento_paralelo_actual = 0;
                        intentos_actuales = cell(this.pParOpt.BLEliminaDesplazaCantProyCompararBase,0);
                        proyectos_restringidos_para_eliminar_intento = proyectos_restringidos_para_eliminar;
                        fuerza_continuar_comparacion = false;
                        cantidad_mejores_intentos_completo = 0;
                        while intento_paralelo_actual < this.pParOpt.BLEliminaDesplazaCantProyCompararBase || fuerza_continuar_comparacion
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
                                
                                proy_seleccionados = this.selecciona_proyectos_a_eliminar_y_desplazar(pPlan, this.pParOpt.CantidadEtapas, proyectos_restringidos_para_eliminar_intento, proy_potenciales_evaluar(intento_paralelo_actual));
                            else
                                proy_seleccionados = this.selecciona_proyectos_a_eliminar_y_desplazar(pPlan, this.pParOpt.CantidadEtapas, proyectos_restringidos_para_eliminar_intento);
                            end
                            
%                           proy_seleccionados.seleccionado = [];
%                           proy_seleccionados.etapa_seleccionado = [];
%                           proy_seleccionados.conectividad_eliminar = [];
%                           proy_seleccionados.etapas_conectividad_eliminar = [];
%                           proy_seleccionados.conectividad_desplazar = [];
%                           proy_seleccionados.etapas_orig_conectividad_desplazar = [];
%                           proy_seleccionados.etapas_fin_conectividad_desplazar = [];
%                           proy_seleccionados.directo = 0/1

                            if isempty(proy_seleccionados.seleccionado)
                                intentos_actuales{intento_paralelo_actual}.Valido = false;
                                intentos_actuales{intento_paralelo_actual}.proy_seleccionados.seleccionado = [];
                                
                                if intento_paralelo_actual >= this.pParOpt.BLEliminaDesplazaCantProyCompararSinMejora
                                    fuerza_continuar_comparacion = false;
                                end

                                continue;
                            end

                            intentos_actuales{intento_paralelo_actual}.proy_seleccionados = proy_seleccionados;
                            intentos_actuales{intento_paralelo_actual}.Totex = 999999999999999999999;
                            intentos_actuales{intento_paralelo_actual}.Valido = false;
                            intentos_actuales{intento_paralelo_actual}.Plan = [];
                            intentos_actuales{intento_paralelo_actual}.SinMejoraIntermedia = false;
                            intentos_actuales{intento_paralelo_actual}.ExisteMejoraParcialAdelanta = false;
                            intentos_actuales{intento_paralelo_actual}.AdelantaProyectos = false;
                            intentos_actuales{intento_paralelo_actual}.AdelantaProyectosForzado = false;
                            intentos_actuales{intento_paralelo_actual}.DesplazaProyectosForzado = false;
                            
                            %intentos_actuales{intento_paralelo_actual}.estructura_costos_actual = [];
                            %intentos_actuales{intento_paralelo_actual}.evaluacion_actual = [];

                            if this.iNivelDebug > 1
                                texto = sprintf('%-25s %-10s %-20s %-10s',...
                                                '      Totex Plan Base ', num2str(estructura_costos_plan_base.TotexTotal), ...
                                                'Totex plan actual', num2str(estructura_costos_actual.TotexTotal));
                                prot.imprime_texto(texto);
                            end

                            % modifica sep y evalua plan a partir de primera etapa cambiada
                            desde_etapa = proy_seleccionados.etapa_seleccionado;  % etapas desplazar siempre es mayor que etapas eliminar
                            intentos_actuales{intento_paralelo_actual}.DesdeEtapaIntento = desde_etapa;
                            existe_mejora = false;
                            plan_actual_hasta_etapa = desde_etapa - 1;
                            plan_actual_intento_hasta_etapa = desde_etapa - 1;
                            proyectos_eliminar = [proy_seleccionados.conectividad_eliminar proy_seleccionados.seleccionado];
                            etapas_eliminar = [proy_seleccionados.etapas_conectividad_eliminar proy_seleccionados.etapa_seleccionado];
                            proyectos_desplazar = proy_seleccionados.conectividad_desplazar;
                            etapas_originales_desplazar = proy_seleccionados.etapas_orig_conectividad_desplazar;
                            etapas_desplazar = proy_seleccionados.etapas_fin_conectividad_desplazar;
                            for nro_etapa = desde_etapa:this.pParOpt.CantidadEtapas
                                % desplaza proyectos a eliminar 
                                for k = length(proyectos_eliminar):-1:1
                                    if etapas_eliminar(k) <= nro_etapa
                                        proyecto = this.pAdmProy.entrega_proyecto(proyectos_eliminar(k));
                                        
                                        sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                        if nro_etapa < this.pParOpt.CantidadEtapas
                                            pPlan.desplaza_proyectos(proyectos_eliminar(k), nro_etapa, nro_etapa + 1);
                                        else
                                            pPlan.elimina_proyectos(proyectos_eliminar(k), nro_etapa);
                                        end
                                    end
                                end
                                %desplaza proyectos
                                for k = length(proyectos_desplazar):-1:1
                                    if nro_etapa >= etapas_originales_desplazar(k) && nro_etapa < etapas_desplazar(k) 
                                        proyecto = this.pAdmProy.entrega_proyecto(proyectos_desplazar(k));
                                        sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                        pPlan.desplaza_proyectos(proyectos_desplazar(k), nro_etapa, nro_etapa + 1);
                                    end
                                end

                                %evalua red (proyectos ya se ingresaron al sep
                                this.evalua_red(sep_actuales{nro_etapa}, nro_etapa, [], false); % false indica que proyectos se eliminan
                                this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa);
                                this.calcula_costos_totales(pPlan);
                                ultima_etapa_evaluada = nro_etapa;

    %debug
    % plan_debug = cPlanExpansion(888888889);
    % plan_debug.Plan = pPlan.Plan;
    % plan_debug.inserta_sep_original(this.pSEP);
    % for etapa_ii = 1:this.pParOpt.CantidadEtapas
    % 	valido = this.evalua_plan(plan_debug, etapa_ii, 0);
    %     if ~valido
    %     	error = MException('cOptACO:genera_planes_bl_elimina_desplaza',...
    %         ['Error. Plan debug no es valido en etapa ' num2str(etapa_ii)]);
    %         throw(error)
    %     end
    % end
    % this.calcula_costos_totales(plan_debug);
    % if round(plan_debug.entrega_totex_total(),3) ~= round(pPlan.entrega_totex_total(),3)
    %     texto = 'Totex total de plan debug es distinto de totex total de plan actual!';
    %     prot.imprime_texto(texto);
    %     texto = ['Totex total plan debug: ' num2str(round(plan_debug.entrega_totex_total(),3))];
    %     prot.imprime_texto(texto);
    %     texto = ['Totex total plan actual: ' num2str(round(pPlan.entrega_totex_total(),3))];
    %     prot.imprime_texto(texto);
    %     
    % 	error = MException('cOptACO:genera_planes_bl_elimina_desplaza','Totex total de plan debug es distinto de totex total de plan actual!');
    %     throw(error)
    % end
                                
                                if pPlan.es_valido(nro_etapa) && pPlan.entrega_totex_total() < estructura_costos_actual_intento.TotexTotal
                                    % cambio intermedio produce mejora. Se
                                    % sigue evaluando
                                    % acepta y se guarda
                                    plan_actual_intento = pPlan.Plan;
                                    estructura_costos_actual_intento = pPlan.entrega_estructura_costos();
                                    evaluacion_actual_intento = pPlan.entrega_evaluacion();
                                    existe_mejora = true;
                                    plan_actual_intento_hasta_etapa = nro_etapa;
                                    if this.iNivelDebug > 1                                        
                                        if nro_etapa < this.pParOpt.CantidadEtapas
                                            texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' genera mejora. Totex actual etapa: ' num2str(pPlan.entrega_totex_total())];
                                            prot.imprime_texto(texto);
                                        else
                                            texto = ['      Desplazamiento en etapa final genera mejora. Proyectos se eliminan definitivamente. Totex final etapa: ' num2str(pPlan.entrega_totex_total())];
                                            prot.imprime_texto(texto);
                                        end
                                    end
                                elseif ~pPlan.es_valido(nro_etapa)
                                    intentos_actuales{intento_paralelo_actual}.SinMejoraIntermedia = true;
                                                                            
                                    if this.iNivelDebug > 1
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
                                    % plan es válido pero no genera mejora.
                                    % Se determina mejora "potencial" que
                                    % se puede obtener al eliminar el
                                    % proyecto, con tal de ver si vale la
                                    % pena o no seguir intentando. Esto a
                                    % menos que ya haya resultado válido y
                                    % flag prioridad desplaza sobre elimina
                                    % esté activo
                                    if this.pParOpt.PrioridadDesplazaSobreElimina && existe_mejora
                                        if this.iNivelDebug > 1
                                            texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' no genera mejora. ' ...
                                                     'Totex actual etapa: ' num2str(pPlan.entrega_totex_total()) ...
                                                     '. No se sigue evaluando ya que ya hay resultado valido y flag prioridad desplaza sobre elimina esta activo'];
                                            prot.imprime_texto(texto);
                                        end
                                        
                                        break;
                                    end
                                    intentos_actuales{intento_paralelo_actual}.SinMejoraIntermedia = true;
                                    if nro_etapa < this.pParOpt.CantidadEtapas
                                        delta_cinv = this.calcula_delta_cinv_elimina_desplaza_proyectos(pPlan, nro_etapa+1, proyectos_eliminar, proyectos_desplazar, etapas_originales_desplazar, etapas_desplazar);
                                        existe_potencial = (pPlan.entrega_totex_total() - delta_cinv) < estructura_costos_actual_intento.TotexTotal;
                                        if this.iNivelDebug > 1
                                            texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' no genera mejora. ' ...
                                                     'Totex actual etapa: ' num2str(pPlan.entrega_totex_total()) ...
                                                     '. Delta Cinv potencial: ' num2str(delta_cinv) ...
                                                     '. Totex potencial: ' num2str(pPlan.entrega_totex_total() - delta_cinv)];
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
                                            texto = ['      Desplazamiento en etapa final no genera mejora. Totex actual etapa: ' num2str(pPlan.entrega_totex_total())];
                                            prot.imprime_texto(texto);
                                        end
                                    end
                                end
                            end
                            
    %debug
    % plan_debug = cPlanExpansion(888888889);
    % plan_debug.Plan = pPlan.Plan;
    % plan_debug.inserta_sep_original(this.pSEP);
    % for etapa_ii = 1:this.pParOpt.CantidadEtapas
    % 	valido = this.evalua_plan(plan_debug, etapa_ii, 0);
    %     if ~valido
    %     	error = MException('cOptACO:genera_planes_bl_elimina_desplaza',...
    %         ['Error. Plan debug no es valido en etapa ' num2str(etapa_ii)]);
    %         throw(error)
    %     end
    % end
    % this.calcula_costos_totales(plan_debug);
    % if round(plan_debug.entrega_totex_total(),3) ~= round(pPlan.entrega_totex_total(),3)
    %     texto = 'Totex total de plan debug es distinto de totex total de plan actual!';
    %     prot.imprime_texto(texto);
    %     texto = ['Totex total plan debug: ' num2str(round(plan_debug.entrega_totex_total(),3))];
    %     prot.imprime_texto(texto);
    %     texto = ['Totex total plan actual: ' num2str(round(pPlan.entrega_totex_total(),3))];
    %     prot.imprime_texto(texto);
    %     
    % 	error = MException('cOptACO:genera_planes_bl_elimina_desplaza','Totex total de plan debug es distinto de totex total de plan actual!');
    %     throw(error)
    % end

                            % se evaluaron todas las etapas. Determina el
                            % estado final del plan y agrega proyectos ya
                            % evaluados para futuros intentos
                            proyectos_restringidos_para_eliminar_intento = [proyectos_restringidos_para_eliminar_intento proy_seleccionados.seleccionado];
                            
                            mejor_totex_elimina_desplaza = inf;
                            if existe_mejora
                                intentos_actuales{intento_paralelo_actual}.Plan = plan_actual_intento;
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
                            pPlan.Plan = plan_actual;
                            pPlan.inserta_estructura_costos(estructura_costos_actual);
                            pPlan.inserta_evaluacion(evaluacion_actual);

                            for nro_etapa = plan_actual_hasta_etapa + 1:ultima_etapa_evaluada
                            	% deshace los cambios hechos en los sep
                                % actuales hasta la etapa correcta
                                % Ojo! orden inverso entre desplaza y
                                % elimina proyectos!
                                for k = 1:length(proyectos_desplazar)
                                    if nro_etapa >= etapas_originales_desplazar(k) && nro_etapa < etapas_desplazar(k) 
                                    	proyecto = this.pAdmProy.entrega_proyecto(proyectos_desplazar(k));
                                        sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    end
                                end

                                for k = 1:length(proyectos_eliminar)
                                    if etapas_eliminar(k) <= nro_etapa
                                    	proyecto = this.pAdmProy.entrega_proyecto(proyectos_eliminar(k));
                                        sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    end
                                end
                            end

                            if desde_etapa > 1 && ~proy_actual_es_potencial_elimina
                                % verifica si adelantar el proyecto produce
                                % mejora
                                % determina primera etapa potencial a
                                % adelantar y proyectos de conectividad
                                
                                if this.iNivelDebug > 1                                        
                                    texto = '      Se verifica si adelantar proyectos produce mejora';
                                    prot.imprime_texto(texto);
                                end
                                
                                proy_adelantar = this.selecciona_proyectos_a_adelantar(pPlan, desde_etapa, proy_seleccionados.seleccionado);
                                % proy_adelantar.seleccionado
                                % proy_adelantar.etapa_seleccionado
                                % proy_adelantar.seleccion_directa
                                % proy_adelantar.primera_etapa_posible = [];
                                % proy_adelantar.proy_conect_adelantar = [];
                                % proy_adelantar.etapas_orig_conect = [];
                                
                                nro_etapa = desde_etapa;
                                flag_salida = false;
                                existe_resultado_adelanta = false;
                                max_cant_intentos_fallidos_adelanta = this.pParOpt.CantidadIntentosFallidosAdelanta;
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
                                            sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                            pPlan.adelanta_proyectos(proy_adelantar.proy_conect_adelantar(k), nro_etapa + 1, nro_etapa);
                                        end
                                    end
                                    proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.seleccionado);
                                    sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    pPlan.adelanta_proyectos(proy_adelantar.seleccionado, nro_etapa + 1, nro_etapa);
                                    
                                    %evalua red (proyectos ya se ingresaron
                                    %al sep)
                                    this.evalua_red(sep_actuales{nro_etapa}, nro_etapa, [], false); % false indica que proyectos se eliminan
                                    this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa);
                                    this.calcula_costos_totales(pPlan);
                                    ultima_etapa_evaluada = nro_etapa;
                                    
                                    if cant_intentos_adelanta == 1
                                        delta_actual_adelanta = pPlan.entrega_totex_total()-ultimo_totex_adelanta;
                                    else
                                        delta_nuevo_adelanta = pPlan.entrega_totex_total()-ultimo_totex_adelanta;
                                        if delta_nuevo_adelanta > 0 && delta_nuevo_adelanta > delta_actual_adelanta
                                            cant_intentos_fallidos_adelanta = cant_intentos_fallidos_adelanta + 1;
                                        elseif delta_nuevo_adelanta < 0
                                            cant_intentos_fallidos_adelanta = 0;
                                        end
                                        delta_actual_adelanta = delta_nuevo_adelanta;
                                    end
                                    ultimo_totex_adelanta = pPlan.entrega_totex_total();
                                    
                                    if ~existe_resultado_adelanta
                                        % resultado se compara con
                                        % estructura de costos actuales
                                        if pPlan.entrega_totex_total() < estructura_costos_actual.TotexTotal
                                            % adelantar el proyecto produce
                                            % mejora. Se guarda resultado
                                            existe_resultado_adelanta = true;
                                            existe_mejora_parcial = true;
                                            plan_actual_intento_adelanta = pPlan.Plan;
                                            estructura_costos_actual_intento_adelanta = pPlan.entrega_estructura_costos();
                                            evaluacion_actual_intento_adelanta = pPlan.entrega_evaluacion();
                                            plan_actual_intento_adelanta_hasta_etapa = nro_etapa;
                                            if this.iNivelDebug > 1                                        
                                                texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ' genera mejora parcial. Totex actual etapa: ' num2str(pPlan.entrega_totex_total())];
                                                prot.imprime_texto(texto);
                                            end
                                        else
                                            if this.iNivelDebug > 1                                        
                                                texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ...
                                                    ' no genera mejora. Totex actual etapa: ' num2str(pPlan.entrega_totex_total())...
                                                    ' Delta actual adelanta: ' num2str(delta_actual_adelanta) ...
                                                    ' Cant. intentos fallidos adelanta: ' num2str(cant_intentos_fallidos_adelanta)];                                                    
                                                prot.imprime_texto(texto);
                                            end                                            
                                        end
                                    else
                                        % resultado se compara con último
                                        % resultado
                                        if pPlan.entrega_totex_total() < estructura_costos_actual_intento_adelanta.TotexTotal
                                            % adelantar el proyecto produce
                                            % mejora. Se guarda resultado
                                            existe_mejora_parcial = true;
                                            plan_actual_intento_adelanta = pPlan.Plan;
                                            estructura_costos_actual_intento_adelanta = pPlan.entrega_estructura_costos();
                                            evaluacion_actual_intento_adelanta = pPlan.entrega_evaluacion();
                                            plan_actual_intento_adelanta_hasta_etapa = nro_etapa;
                                            if this.iNivelDebug > 1                                        
                                                texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ' genera mejora parcial. Totex actual etapa: ' num2str(pPlan.entrega_totex_total())];
                                                prot.imprime_texto(texto);
                                            end
                                        else
                                            if this.iNivelDebug > 1                                        
                                                texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ...
                                                    ' no genera mejora. Totex actual etapa: ' num2str(pPlan.entrega_totex_total()) ...
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
                                            this.pParOpt.PrioridadAdelantaProyectos
                                            
                                            if estructura_costos_actual_intento_adelanta.TotexTotal > mejor_totex_elimina_desplaza
                                                intentos_actuales{intento_paralelo_actual}.AdelantaProyectosForzado = true;
                                            else
                                                intentos_actuales{intento_paralelo_actual}.AdelantaProyectosForzado = false;                                                
                                            end
                                            % se acepta el cambio
                                            intentos_actuales{intento_paralelo_actual}.Plan = plan_actual_intento_adelanta;
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
                                pPlan.Plan = plan_actual;
                                pPlan.inserta_estructura_costos(estructura_costos_actual);
                                pPlan.inserta_evaluacion(evaluacion_actual);

                                for nro_etapa = ultima_etapa_evaluada:desde_etapa-1
                                    % deshace los cambios hechos en los sep
                                    % actuales hasta la etapa correcta
                                    % Ojo! orden inverso entre desplaza y
                                    % elimina proyectos!
                                    proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.seleccionado);
                                    sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    for k = length(proy_adelantar.proy_conect_adelantar):-1:1
                                        if nro_etapa < proy_adelantar.etapas_orig_conect(k) 
                                            proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.proy_conect_adelantar(k));
                                            sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                        end
                                    end
                                end
                            end
                            
                            % se verifica si hay que seguir comparando
                            if fuerza_continuar_comparacion == false && ...
                               intento_paralelo_actual == this.pParOpt.BLEliminaDesplazaCantProyCompararBase && ...
                               cantidad_mejores_intentos_completo < this.pParOpt.BLEliminaDesplazaCantProyCompararBase && ...
                               this.pParOpt.BLEliminaDesplazaCantProyCompararSinMejora > this.pParOpt.BLEliminaDesplazaCantProyCompararBase
                                    
                                fuerza_continuar_comparacion = true;
                            elseif fuerza_continuar_comparacion == true && intento_paralelo_actual == this.pParOpt.BLEliminaDesplazaCantProyCompararSinMejora
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
                                    elseif this.pParOpt.PrioridadDesplazaSobreElimina && ...
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
                                                if ~this.pParOpt.PrioridadDesplazaSobreElimina
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
                                                if ~this.pParOpt.PrioridadDesplazaSobreElimina
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
                            if this.iNivelDebug > 1
                            	texto = ['      Mejor intento: ' num2str(id_mejor_plan_intento)];
                                prot.imprime_texto(texto);
                            end
                            
                            plan_actual = intentos_actuales{id_mejor_plan_intento}.Plan;
                            evaluacion_actual = intentos_actuales{id_mejor_plan_intento}.evaluacion_actual;
                            estructura_costos_actual = intentos_actuales{id_mejor_plan_intento}.estructura_costos_actual;
                            pPlan.Plan = plan_actual;
                            pPlan.inserta_estructura_costos(estructura_costos_actual);
                            pPlan.inserta_evaluacion(evaluacion_actual);
                            
                            proy_potenciales_eliminar(proy_potenciales_eliminar == intentos_actuales{id_mejor_plan_intento}.proy_seleccionados.seleccionado) = [];
                            proy_potenciales_adelantar(proy_potenciales_adelantar == intentos_actuales{id_mejor_plan_intento}.proy_seleccionados.seleccionado) = [];
                                            
                            % se implementa plan hasta la etapa actual del
                            % mejor intento
                            desde_etapa = intentos_actuales{id_mejor_plan_intento}.DesdeEtapaIntento;
                            ultima_etapa_valida_intento = intentos_actuales{id_mejor_plan_intento}.PlanActualHastaEtapa;
                            
                            if intentos_actuales{id_mejor_plan_intento}.AdelantaProyectos
                                proy_adelantar = intentos_actuales{id_mejor_plan_intento}.proy_seleccionados;
                                if ~intentos_actuales{id_mejor_plan_intento}.AdelantaProyectosForzado
                                    proyectos_restringidos_para_eliminar = [proyectos_restringidos_para_eliminar proy_adelantar.seleccionado];
                                end
                                for nro_etapa = ultima_etapa_valida_intento:desde_etapa-1
                                    % agrega proyectos en sep actual en
                                    % etapa actual
                                    for k = 1:length(proy_adelantar.proy_conect_adelantar)
                                        if nro_etapa < proy_adelantar.etapas_orig_conect(k) 
                                            proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.proy_conect_adelantar(k));
                                            sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                        end
                                    end
                                    proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.seleccionado);
                                    sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                end
                            else
                                proy_seleccionados = intentos_actuales{id_mejor_plan_intento}.proy_seleccionados;
                                proyectos_eliminar = [proy_seleccionados.conectividad_eliminar proy_seleccionados.seleccionado];
                                etapas_eliminar = [proy_seleccionados.etapas_conectividad_eliminar proy_seleccionados.etapa_seleccionado];
                                proyectos_desplazar = proy_seleccionados.conectividad_desplazar;
                                etapas_originales_desplazar = proy_seleccionados.etapas_orig_conectividad_desplazar;
                                etapas_desplazar = proy_seleccionados.etapas_fin_conectividad_desplazar;

                                % elimina de lista todos los otros proyectos.
                                % Ocurre a veces que trafo paralelo es
                                % eliminado como proyecto de conectividad
                                proy_potenciales_eliminar(ismember(proy_potenciales_eliminar, proy_seleccionados.conectividad_eliminar)) = [];
                                proy_potenciales_adelantar(ismember(proy_potenciales_adelantar, proy_seleccionados.conectividad_eliminar)) = [];
                                
                                for nro_etapa = desde_etapa:ultima_etapa_valida_intento
                                    % desplaza proyectos a eliminar 
                                    for k = length(proyectos_eliminar):-1:1
                                        if etapas_eliminar(k) <= nro_etapa
                                            proyecto = this.pAdmProy.entrega_proyecto(proyectos_eliminar(k));
                                            sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                        end
                                    end
                                    %desplaza proyectos
                                    for k = length(proyectos_desplazar):-1:1
                                        if nro_etapa >= etapas_originales_desplazar(k) && nro_etapa < etapas_desplazar(k) 
                                            proyecto = this.pAdmProy.entrega_proyecto(proyectos_desplazar(k));
                                            sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                        end
                                    end
                                end
    
                                if ultima_etapa_valida_intento == this.pParOpt.CantidadEtapas
                                    % quiere decir que proyectos se eliminaron
                                    % definitivamente
                                    proyectos_eliminados = [proyectos_eliminados proyectos_eliminar];
                                else
                                    % quiere decir que proyecto no fue
                                    % eliminado completamente, pero sí
                                    % desplazado
                                    % se agrega proyectos_eliminar a proyectos
                                    % restringidos para eliminar, ya que ya fue
                                    % desplazado. A menos que haza sido
                                    % forzado...
                                    if ~intentos_actuales{id_mejor_plan_intento}.DesplazaProyectosForzado
                                        proyectos_restringidos_para_eliminar = [proyectos_restringidos_para_eliminar proy_seleccionados.seleccionado];
                                    end
                                 
                                    if this.iNivelDebug > 1
                                        proyectos_desplazados = [proyectos_desplazados proyectos_eliminar];
                                        etapas_desplazados = [etapas_desplazados (ultima_etapa_valida_intento+1)*ones(1, length(proyectos_eliminar))];
                                    end
                                end
                            end

                            if this.iNivelDebug > 1
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
                                                        
                            if this.iNivelDebug > 1
                                texto = 'Imprime plan actual despues de los intentos';
                                prot.imprime_texto(texto);
                                pPlan.agrega_nombre_proyectos(this.pAdmProy);
                                pPlan.imprime();
                            end 
                        else
                            cant_busqueda_fallida = cant_busqueda_fallida + 1;
                            % no hubo mejora por lo que no es necesario
                            % rehacer ningún plan
                            if this.iNivelDebug > 1
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
                    end
                    
                    if this.iNivelDebug > 1
                        totex_despues_de_elimina = pPlan.entrega_totex_total();
                        cantidad_proy_despues_de_elimina = pPlan.cantidad_acumulada_proyectos();

                        prot.imprime_texto('Fin elimina proyectos');
                        texto = sprintf('%-15s %-10s %-10s', ' ', 'No proy', 'Totex');
                        prot.imprime_texto(texto);
                        texto = sprintf('%-15s %-10s %-10s', 'Original', num2str(cantidad_proy_orig), num2str(totex_orig));
                        prot.imprime_texto(texto);
                        texto = sprintf('%-15s %-10s %-10s', 'Elimina', num2str(cantidad_proy_despues_de_elimina), num2str(totex_despues_de_elimina));
                        prot.imprime_texto(texto);
                        

                        texto_eliminados = '';
                        texto_desplazados = '';
                        for ii = 1:length(proyectos_eliminados)
                            texto_eliminados = [texto_eliminados ' ' num2str(proyectos_eliminados(ii))];
                        end
                        
                        for ii = 1:length(proyectos_desplazados)
                            texto_desplazados = [texto_desplazados ' Pr. ' num2str(proyectos_desplazados(ii)) ' hasta etapa ' num2str(etapas_desplazados(ii)) ';'];
                        end
                        texto = ['Proyectos eliminados (' num2str(length(proyectos_eliminados)) '): ' texto_eliminados];
                        prot.imprime_texto(texto);

                        texto = ['Proyectos desplazados (' num2str(length(proyectos_desplazados)) '): ' texto_desplazados];
                        prot.imprime_texto(texto);
                        
                        prot.imprime_texto('Plan actual despues de elimina proyectos');
                        pPlan.agrega_nombre_proyectos(this.pAdmProy);
                        pPlan.imprime();

% DEBUG
for nro_etapa = 1:this.pParOpt.CantidadEtapas
proyectos_en_sep = sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = pPlan.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
prot.imprime_texto(['Proyectos en SEP en etapa ' num2str(nro_etapa) ' es distinto a proyectos en plan']);
prot.imprime_texto(['Proyectos en SEP: ' num2str(proyectos_en_sep)]);
prot.imprime_texto(['Proyectos en plan: ' num2str(proyectos_en_plan)]);
error = MException('cOptACO:genera_planes_bl_elimina_desplaza',...
'Intento fallido 1 en Fin Elimina Proyectos. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end
end
                        
                    end

                    if this.pParOpt.BLEliminaDesplazaCambioUprating && pPlan.cantidad_acumulada_proyectos() ~= 0
                        % 1: escoge proyecto y determina corredor
                        % 2: toma primer proyecto desarrollado, y elige por otro
                        % 3: a partir de la primera etapa del proyecto, desarrolla proyecto escogido (primero)
                        % 4. evaluar red. si en algún momento no es válida, agrega nueva capacidad
                        % 5. verifica si incorporar/adelantar proyectos adicionales mejora performance

                        if this.iNivelDebug > 1
                            prot.imprime_texto('\nComienzo BL Cambio Uprating');
                        end
                        
                        evaluacion_plan_base = pPlan.entrega_evaluacion();
                        estructura_costos_plan_base = pPlan.entrega_estructura_costos();
                        plan_base = pPlan.Plan;
                        
                        proyectos_restringidos_para_eliminar = [];
                        
                        % los siguientes contenedores son sólo para fines
                        % informativos (debug)
                        proyectos_eliminados = [];
                        etapas_eliminados = [];
                        proyectos_agregados = [];
                        etapas_agregados = [];
                        conectividad_desplazar = [];
                        etapas_orig_conectividad_desplazar = [];
                        etapas_fin_conectividad_desplazar = [];

                        cant_busqueda_fallida = 0;
                        intento_total = 0;
                        while cant_busqueda_fallida < this.pParOpt.BLEliminaDesplazaCantBusquedaFallida
                            intento_paralelo_actual = 0;
                            intento_total = intento_total + 1;
                            evaluacion_actual = pPlan.entrega_evaluacion();
                            estructura_costos_actual = pPlan.entrega_estructura_costos();
                            plan_actual = pPlan.Plan;
                            existe_mejor_intento = false;
                            id_mejor_intento = 0;
                            proy_seleccionados = this.selecciona_proyectos_a_intercambiar(pPlan, proyectos_restringidos_para_eliminar);
                            % proy_seleccionados.corredor = 0;
                            % proy_seleccionados.ubicacion = 0; %Trafo VU
                            % proy_seleccionados.estado_eliminar = 0;
                            % proy_seleccionados.cant_estados = 0;
                            % proy_seleccionados.eliminar = [];
                            % proy_seleccionados.etapa_eliminar = [];
                            % proy_seleccionados.conectividad_desplazar = [];
                            % proy_seleccionados.etapas_orig_conectividad_desplazar = [];
                            % proy_seleccionados.etapas_fin_conectividad_desplazar = [];
                            % proy_seleccionados.trafos_paralelos_potenciales_a_eliminar = [];
                            % proy_seleccionados.etapas_trafos_paralelos_potenciales_a_eliminar = [];
                            % proy_seleccionados.agregar = [];

                            % elimina proyectos a eliminar del sep
                            proyectos_eliminar = proy_seleccionados.eliminar;
                            
                            % agrega proyectos seleccionados eliminar a
                            % grupo de proy. restringidos
                            proyectos_restringidos_para_eliminar = [proyectos_restringidos_para_eliminar proyectos_eliminar];

                            etapas_eliminar = proy_seleccionados.etapa_eliminar;
                            proyectos_desplazar = proy_seleccionados.conectividad_desplazar;
                            etapas_originales_desplazar = proy_seleccionados.etapas_orig_conectividad_desplazar;
                            etapas_desplazar = proy_seleccionados.etapas_fin_conectividad_desplazar;
                            trafos_paral_eliminados = proy_seleccionados.trafos_paralelos_potenciales_a_eliminar;
                            etapas_trafos_paral_eliminados = proy_seleccionados.etapas_trafos_paralelos_potenciales_a_eliminar;

                            if this.iNivelDebug > 1
                                prot.imprime_texto(['Intento total ' num2str(intento_total) '. Cant. fallida ' num2str(cant_busqueda_fallida) '/' num2str(this.pParOpt.BLEliminaDesplazaCantBusquedaFallida)]);
                                prot.imprime_texto(['Proy. seleccionados eliminar : ' num2str(proyectos_eliminar)]);
                                prot.imprime_texto(['Etapas Proy. selec. eliminar : ' num2str(etapas_eliminar)]);
                                prot.imprime_texto(['Proy. seleccionados desplazar: ' num2str(proyectos_desplazar)]);
                                prot.imprime_texto(['Etapas orig proyec. desplazar: ' num2str(etapas_originales_desplazar)]);
                                prot.imprime_texto(['Etapas fin proyect. desplazar: ' num2str(etapas_desplazar)]);
                                prot.imprime_texto(['Trafos potenciales a eliminar: ' num2str(trafos_paral_eliminados)]);
                                prot.imprime_texto(['Etapas trafos pot. a eliminar: ' num2str(etapas_trafos_paral_eliminados)]);
                                prot.imprime_texto(['Proy. restringidos a eliminar: ' num2str(proyectos_restringidos_para_eliminar)]);
                            end

                            % elimina trafos potenciales a eliminar
                            %desplaza proyectos
                            for k = length(trafos_paral_eliminados):-1:1
                                desde_etapa = etapas_trafos_paral_eliminados(k);
                                for nro_etapa = desde_etapa:this.pParOpt.CantidadEtapas
                                    proyecto = this.pAdmProy.entrega_proyecto(trafos_paral_eliminados(k));
                                    sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                end
                                pPlan.elimina_proyectos(trafos_paral_eliminados(k), desde_etapa);
                            end
                            
                            %desplaza proyectos
                            for k = length(proyectos_desplazar):-1:1
                                desde_etapa = etapas_originales_desplazar(k);
                                hasta_etapa = etapas_desplazar(k);
                                for nro_etapa = desde_etapa:hasta_etapa-1
                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_desplazar(k));
                                    sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                end
                                pPlan.desplaza_proyectos(proyectos_desplazar(k), desde_etapa, hasta_etapa);
                            end

                            for k = length(proyectos_eliminar):-1:1
                                desde_etapa = etapas_eliminar(k);
                                for nro_etapa = desde_etapa:this.pParOpt.CantidadEtapas
                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_eliminar(k));
                                    sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                end
                                pPlan.elimina_proyectos(proyectos_eliminar(k), desde_etapa);
                            end                            
                                                    
                            proy_agregados_mejor_intento = [];
                            etapas_agregados_mejor_intento = [];

                            conect_agregados_mejor_intento = [];
                            etapas_conect_agregados_mejor_intento = [];
                            conect_adelantado_mejor_intento = [];
                            etapas_fin_conect_adelantado_mejor_intento = [];
                            etapas_orig_conect_adelantado_mejor_intento = [];
                            
                            plan_antes_intentos = pPlan.Plan;
                            estructura_costos_mejor_intento = estructura_costos_actual;

% DEBUG
if this.iNivelDebug > 1
for nro_etapa = 1:this.pParOpt.CantidadEtapas
proyectos_en_sep = sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = pPlan.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
prot.imprime_texto(['Proyectos en SEP en etapa ' num2str(nro_etapa) ' es distinto a proyectos en plan']);
prot.imprime_texto(['Proyectos en SEP: ' num2str(proyectos_en_sep)]);
prot.imprime_texto(['Proyectos en plan: ' num2str(proyectos_en_plan)]);
error = MException('cOptACO:genera_planes_bl_elimina_desplaza',...
'Intento fallido 2 en BL Cambio Uprating antes de intentos paralelos. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end
end
end

                            totex_total_intentos = zeros(length(proy_seleccionados.agregar),1);
                            while intento_paralelo_actual < length(proy_seleccionados.agregar)
                                intento_paralelo_actual = intento_paralelo_actual +1;
                                
                                pPlan.Plan = plan_antes_intentos;
                                proy_agregados = proy_seleccionados.agregar{intento_paralelo_actual};
                                ultimo_proy_intento_agregado = proy_agregados;
                                etapas_agregados = etapas_eliminar(1);

                                conect_agregados = [];
                                etapas_conect_agregados = [];
                                conect_adelantado = [];
                                etapas_fin_conect_adelantado = [];
                                etapas_orig_conect_adelantado = [];
                                % determina si proy a agregar tienen
                                % requisito de conectividad
                                if this.pAdmProy.entrega_proyecto(proy_agregados).TieneRequisitosConectividad
                                    cantidad_req_conectividad = this.pAdmProy.entrega_proyecto(proy_agregados).entrega_cantidad_grupos_conectividad();

                                    for ii = 1:cantidad_req_conectividad
                                        indice_proy_conect = this.pAdmProy.entrega_proyecto(proy_agregados).entrega_indices_grupo_proyectos_conectividad(ii);
                                        [existe_conect_en_plan, etapa_conect_en_plan, proy_conect_en_plan] = pPlan.conectividad_existe_con_etapa_y_proyecto(indice_proy_conect);
                                        if existe_conect_en_plan
                                            % proyecto de conectividad
                                            % está. Hay que verificar si se
                                            % tiene que adelantar
                                            if etapa_conect_en_plan > etapas_agregados
                                                conect_adelantado = [conect_adelantado proy_conect_en_plan];
                                                etapas_orig_conect_adelantado = [etapas_orig_conect_adelantado etapa_conect_en_plan];
                                                etapas_fin_conect_adelantado = [etapas_fin_conect_adelantado etapas_agregados];
                                            end
                                        else
                                            % hay que agregar requisito de conectividad 
                                            % por ahora se agrega primer
                                            % proyecto de conectividad, ya
                                            % que es el más barato
                                            conect_agregados = [conect_agregados indice_proy_conect(1)];
                                            etapas_conect_agregados = [etapas_conect_agregados etapas_agregados];
                                        end
                                    end
                                end
                                                             
                                %intentos_actuales{intento_paralelo_actual}.estructura_costos_actual = [];
                                %intentos_actuales{intento_paralelo_actual}.evaluacion_actual = [];
                                
                                if this.iNivelDebug > 1
                                    texto = sprintf('%-25s %-10s %-20s %-10s',...
                                        '      Totex Plan Base ', num2str(estructura_costos_plan_base.TotexTotal), ...
                                        'Totex plan mejor intento', num2str(estructura_costos_mejor_intento.TotexTotal));
                                    prot.imprime_texto(texto);

                                    prot.imprime_texto(['Intento paralelo actual: ' num2str(intento_paralelo_actual) '/' num2str(length(proy_seleccionados.agregar))]);
                                    prot.imprime_texto(['Proy. agregados  : ' num2str(proy_agregados)]);
                                    prot.imprime_texto(['Etapa agregados  : ' num2str(etapas_agregados)]);
                                    prot.imprime_texto(['Conect. agregados: ' num2str(conect_agregados)]);
                                    prot.imprime_texto(['Etapa conect agre: ' num2str(etapas_conect_agregados)]);
                                    prot.imprime_texto(['Conect. adelantad: ' num2str(conect_adelantado)]);
                                    prot.imprime_texto(['Etapa orig. adel : ' num2str(etapas_orig_conect_adelantado)]);
                                    prot.imprime_texto(['Etapa final adel : ' num2str(etapas_fin_conect_adelantado)]);
                                end
                                
                                desde_etapa = min(etapas_agregados);
                                % modifica sep y evalua plan a partir de primera etapa cambiada
%                                 intentos_actuales{intento_paralelo_actual}.DesdeEtapaIntento = desde_etapa;
%                                 existe_mejora = false;
%                                 plan_actual_hasta_etapa = desde_etapa - 1;
%                                 plan_actual_intento_hasta_etapa = desde_etapa - 1;
                                % primero proyectos de conectividad
                                % agregados
                                for i = 1:length(conect_agregados)
                                    pPlan.agrega_proyecto(desde_etapa, conect_agregados(i));
                                end
                                
                                % ahora proyectos de conectividad
                                % adelantados
                                for i = 1:length(conect_adelantado)
                                    pPlan.adelanta_proyectos(conect_adelantado(i), etapas_orig_conect_adelantado(i), etapas_fin_conect_adelantado(i));
                                end
                                
                                % finalmente, proyecto agregado
                                pPlan.agrega_proyecto(desde_etapa, proy_agregados);
                                est_evaluacion_act.Valido = false;
                                ultima_etapa_evaluada = 0;

                                %intentos_actuales{intento_paralelo_actual}.proy_seleccionados = proy_agregados;
                                
                                for nro_etapa = desde_etapa:this.pParOpt.CantidadEtapas
                                    % agrega proyectos al sep de la etapa
                                    % primero proyectos de conectividad
                                    % agregados
                                    ultima_etapa_evaluada = nro_etapa;
                                    for j = 1:length(conect_agregados)
                                        proyecto = this.pAdmProy.entrega_proyecto(conect_agregados(j));
                                        sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    end
                                    
                                    %luego proyectos de conectividad
                                    %adelantados
                                    for j = 1:length(conect_adelantado)
                                        if nro_etapa >= etapas_fin_conect_adelantado(j) && ...
                                                nro_etapa < etapas_orig_conect_adelantado(j)
                                            proyecto = this.pAdmProy.entrega_proyecto(conect_adelantado(j));
                                            sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                        end
                                    end
                                    
                                    % finalmente, proyectos agregados
                                    for j = 1:length(proy_agregados)
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_agregados(j));
                                        sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    end
                                    this.evalua_red(sep_actuales{nro_etapa}, nro_etapa, [], false);
                                    est_evaluacion_act = this.entrega_estructura_evaluacion(sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                                    this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa)
                                    while ~est_evaluacion_act.Valido
                                        if this.iNivelDebug > 1
                                            prot = cProtocolo.getInstance;
                                            prot.imprime_texto(['   Plan no es valido en etapa ' num2str(nro_etapa) '. Se imprimen elementos con flujo maximo:']);
                                            texto = sprintf('%-3s %-25s %-5s', ' ', 'Elemento', 'Porcentaje carga');
                                            prot.imprime_texto(texto);
                                        end
                                        proy_agregado_es_ppal = false;
                                        proy_agregado_es_conect = false;
                                        el_flujo_maximo = pPlan.entrega_elementos_flujo_maximo(nro_etapa);
                                        [n, ~] = size(el_flujo_maximo);
                                        % primero verifica si
                                        % transformadores eliminados ayudan
                                        % a superar congestion
                                        proy_agregado = false;
                                        if ~isempty(trafos_paral_eliminados)
                                            for i = 1:n
                                                existente = el_flujo_maximo{i,4};
                                                id_adm_proy = el_flujo_maximo{i,3};
                                                if this.iNivelDebug > 1
                                                    texto = sprintf('%-3s %-25s %-5s', ' ', el_flujo_maximo{i,1}, num2str(el_flujo_maximo{i,7}));
                                                    prot.imprime_texto(texto);
                                                end

                                                if existente
                                                    el_red = this.pAdmProy.ElementosSerieExistentes(id_adm_proy);
                                                else
                                                    el_red = this.pAdmProy.ElementosSerie(id_adm_proy);
                                                end

                                                proy = this.pAdmProy.entrega_id_proyectos_salientes(el_red);
                                                if ismember(trafos_paral_eliminados, proy)
                                                    % trafo eliminado ayuda
                                                    % a superar congestión.
                                                    % Se agrega
                                                    id_trafo_a_agregar = trafos_paral_eliminados(ismember(trafos_paral_eliminados, proy));
                                                    if this.iNivelDebug > 1
                                                        texto = ['Agrega trafo paral eliminado con proyecto ' num2str(id_trafo_a_agregar)];
                                                        prot.imprime_texto(texto);
                                                    end
                                                    proy_agregados = [proy_agregados id_trafo_a_agregar];
                                                    etapas_agregados = [etapas_agregados nro_etapa];
                                                    pPlan.agrega_proyecto(nro_etapa, id_trafo_a_agregar);
                                                    sep_actuales{nro_etapa}.agrega_proyecto(this.pAdmProy.entrega_proyecto(id_trafo_a_agregar));
                                                    trafos_paral_eliminados(ismember(trafos_paral_eliminados, id_trafo_a_agregar)) = [];
                                                    proy_agregado_es_conect = true;
                                                    proy_agregado = true;
                                                end
                                            end
                                            if proy_agregado
                                                this.evalua_red(sep_actuales{nro_etapa}, nro_etapa, [], false);
                                                est_evaluacion_act = this.entrega_estructura_evaluacion(sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                                                this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa)
                                            end
                                        end
                                        if isempty(trafos_paral_eliminados) || ~proy_agregado
                                            posibles_proyectos_agregar = [];
                                            for i = 1:n
                                                existente = el_flujo_maximo{i,4};
                                                id_adm_proy = el_flujo_maximo{i,3};
                                                if this.iNivelDebug > 1
                                                    texto = sprintf('%-3s %-25s %-5s', ' ', el_flujo_maximo{i,1}, num2str(el_flujo_maximo{i,7}));
                                                    prot.imprime_texto(texto);
                                                end

                                                if existente
                                                    el_red = this.pAdmProy.ElementosSerieExistentes(id_adm_proy);
                                                else
                                                    el_red = this.pAdmProy.ElementosSerie(id_adm_proy);
                                                end
                                                % verifica si elemento
                                                % sobrecargado
                                                % pertenece al corredor
                                                % o ubicación que se
                                                % está evaluando
                                                corredor_el_sobrecargado = el_red.entrega_id_corredor();
                                                if corredor_el_sobrecargado ~= 0
                                                    if corredor_el_sobrecargado == proy_seleccionados.corredor
                                                        % corresponde
                                                        posibles_proyectos_agregar = this.pAdmProy.entrega_id_proyectos_salientes(el_red);
                                                        proy_agregado_es_ppal = true;
                                                    end
                                                else
                                                    ubicacion_el_sobrecargado = el_red.entrega_se2().entrega_ubicacion();
                                                    if ubicacion_el_sobrecargado == proy_seleccionados.ubicacion
                                                        % corresponde
                                                        posibles_proyectos_agregar = this.pAdmProy.entrega_id_proyectos_salientes(el_red);
                                                        proy_agregado_es_ppal = true;
                                                    else
                                                        for j = 1:length(conect_agregados)
                                                            if el_red == this.pAdmProy.entrega_proyecto(conect_agregados(j)).Elemento(end)
                                                                % corresponde
                                                                posibles_proyectos_agregar = this.pAdmProy.entrega_id_proyectos_salientes(el_red);
                                                                proy_agregado_es_conect = true;
                                                            end
                                                        end
                                                    end
                                                end
                                            end
                                            if isempty(posibles_proyectos_agregar)
                                                % se fuerza agregar
                                                % proyecto. Flujos pueden
                                                % cambiar
                                                ultimo_el_red = this.pAdmProy.entrega_proyecto(ultimo_proy_intento_agregado).Elemento(end);
                                                posibles_proyectos_agregar = this.pAdmProy.entrega_id_proyectos_salientes(ultimo_el_red);
                                                proy_agregado_es_ppal = true;
                                            end
                                            if ~isempty(posibles_proyectos_agregar)
                                                costos_potenciales = this.pAdmProy.entrega_costo_potencial(posibles_proyectos_agregar, pPlan);
                                                % ordena posibles proyectos de
                                                % acuerdo a costo
                                                [~, id] = sort(costos_potenciales);
                                                posibles_proyectos_agregar = posibles_proyectos_agregar(id);
                                                ultimo_proy_evaluado = 0;
                                                for j = 1:length(posibles_proyectos_agregar)
                                                    proy_a_agregar = this.pAdmProy.entrega_proyecto(posibles_proyectos_agregar(j));
                                                    if proy_a_agregar.TieneRequisitosConectividad
                                                        % se excluyen proyectos de AV ya que se ven al comienzo 
                                                        continue
                                                    end
                                                    ultimo_proy_evaluado = j;
                                                    if this.iNivelDebug > 1
                                                        texto = ['   Agrega posible proyecto a agregar ' num2str(j) '/' num2str(length(posibles_proyectos_agregar)) ' : ' num2str(posibles_proyectos_agregar(j))];
                                                        prot.imprime_texto(texto);
                                                    end

                                                    sep_actuales{nro_etapa}.agrega_proyecto(proy_a_agregar);
                                                    this.evalua_red(sep_actuales{nro_etapa}, nro_etapa, [], false);
                                                    est_eval_intermedia = this.entrega_estructura_evaluacion(sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                                                    if ~est_eval_intermedia.Valido
                                                        sep_actuales{nro_etapa}.elimina_proyecto(proy_a_agregar);
                                                    else
                                                        if this.iNivelDebug > 1
                                                            texto = ['Intento es valido en etapa ' num2str(nro_etapa) '. Se agrega proyecto: '  num2str(posibles_proyectos_agregar(j))];
                                                            prot.imprime_texto(texto);
                                                        end
                                                        est_evaluacion_act = est_eval_intermedia;
                                                        pPlan.agrega_proyecto(nro_etapa, posibles_proyectos_agregar(j));
                                                        proy_agregados = [proy_agregados posibles_proyectos_agregar(j)];
                                                        etapas_agregados = [etapas_agregados nro_etapa];

                                                        if proy_agregado_es_ppal
                                                            ultimo_proy_intento_agregado = posibles_proyectos_agregar(j);
                                                        end
                                                        this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa)
                                                        break;
                                                    end
                                                end
                                            end
                                            
                                            if ~est_evaluacion_act.Valido
                                                % quiere decir que ningún proyecto hizo que plan fuera válido. Se toma el último proyecto agregado (mayor capacidad)
                                                if ~isempty(posibles_proyectos_agregar) && ultimo_proy_evaluado ~= 0
                                                    if this.iNivelDebug > 1
                                                        texto = ['Intento no fue valido en etapa ' num2str(nro_etapa) ' pero se agrega proyecto: '  num2str(posibles_proyectos_agregar(ultimo_proy_evaluado))];
                                                        prot.imprime_texto(texto);
                                                    end
                                                    pPlan.agrega_proyecto(nro_etapa, posibles_proyectos_agregar(ultimo_proy_evaluado));
                                                    proy_agregados = [proy_agregados posibles_proyectos_agregar(ultimo_proy_evaluado)];
                                                    etapas_agregados = [etapas_agregados nro_etapa];
                                                    sep_actuales{nro_etapa}.agrega_proyecto(this.pAdmProy.entrega_proyecto(posibles_proyectos_agregar(ultimo_proy_evaluado)));
                                                    this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa)
                                                    if proy_agregado_es_ppal
                                                        ultimo_proy_intento_agregado = posibles_proyectos_agregar(ultimo_proy_evaluado);
                                                    end
                                                    
                                                else
                                                    % quiere decir que no hay
                                                    % más proyectos a agregar.
                                                    % Se descarta intento
                                                    if this.iNivelDebug > 1
                                                        texto = ['Intento no fue valido en etapa ' num2str(nro_etapa) ' y no hay mas proyectos a agregar. Se descarta'];
                                                        prot.imprime_texto(texto);
                                                    end
                                                    break
                                                end
                                            end
                                        end
                                    end
    
                                    if est_evaluacion_act.Valido
                                        this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa);                                            
                                    else
                                        break;
                                    end
                                end
                                                            
                                if est_evaluacion_act.Valido
                                    % evalua performance intento
                                    this.calcula_costos_totales(pPlan);
                                    totex_total_intentos(intento_paralelo_actual) = pPlan.entrega_totex_total();
                                    if pPlan.entrega_totex_total() < estructura_costos_mejor_intento.TotexTotal
                                        existe_mejor_intento = true;
                                        id_mejor_intento = intento_paralelo_actual;
                                        estructura_costos_mejor_intento = pPlan.entrega_estructura_costos();
                                        plan_actual_mejor_intento = pPlan.Plan;
                                        proy_agregados_mejor_intento = proy_agregados;
                                        etapas_agregados_mejor_intento = etapas_agregados;
                                        conect_agregados_mejor_intento = conect_agregados;
                                        etapas_conect_agregados_mejor_intento = etapas_conect_agregados;
                                        conect_adelantado_mejor_intento = conect_adelantado;
                                        etapas_fin_conect_adelantado_mejor_intento = etapas_fin_conect_adelantado;
                                        etapas_orig_conect_adelantado_mejor_intento = etapas_orig_conect_adelantado;
                                        if this.iNivelDebug > 1
                                            texto = ['   Intento ' num2str(intento_paralelo_actual) ' tiene totex: ' num2str(pPlan.entrega_totex_total()) ' . Mejora totex actual'];
                                            prot.imprime_texto(texto); 
                                        end  
                                    else
                                        if this.iNivelDebug > 1
                                            texto = ['   Intento ' num2str(intento_paralelo_actual) ' tiene totex: ' num2str(pPlan.entrega_totex_total()) '. Es valido, pero no es mejor que totex actual (' num2str(estructura_costos_mejor_intento.TotexTotal) ')'];      
                                            prot.imprime_texto(texto);
                                        end  
                                    end
                                else
                                    % intento actual no fue válido. No es
                                    % necesario guardar nada
                                    totex_total_intentos(intento_paralelo_actual) = 9999999;
                                    if this.iNivelDebug > 1
                                        texto = ['   Intento ' num2str(intento_paralelo_actual) ' no es valido'];      
                                        prot.imprime_texto(texto);
                                    end  
                                end
% DEBUG
if this.iNivelDebug > 1
for nro_etapa = 1:ultima_etapa_evaluada
proyectos_en_sep = sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = pPlan.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
prot.imprime_texto(['Proyectos en SEP en etapa ' num2str(nro_etapa) ' es distinto a proyectos en plan']);
prot.imprime_texto(['Proyectos en SEP: ' num2str(proyectos_en_sep)]);
prot.imprime_texto(['Proyectos en plan: ' num2str(proyectos_en_plan)]);
error = MException('cOptACO:genera_planes_bl_elimina_desplaza',...
'Intento fallido 3 en BL Cambio Uprating antes de deshacer los proyectos del intento. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end
end
end
    
                                % se deshacen los proyectos del intento
                                % actual
                                for j = length(proy_agregados):-1:1
                                    desde_etapa = etapas_agregados(j);
                                    for nro_etapa = desde_etapa:ultima_etapa_evaluada
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_agregados(j));
                                        sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    end
                                end
                                    
                                for j = length(conect_agregados):-1:1
                                    desde_etapa = etapas_conect_agregados;
                                    for nro_etapa = desde_etapa:ultima_etapa_evaluada
                                        proyecto = this.pAdmProy.entrega_proyecto(conect_agregados(j));
                                        sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    end
                                end
                                    
                                %finalmente proyectos de conectividad
                                %adelantados
                                for j = length(conect_adelantado):-1:1
                                    desde_etapa = etapas_fin_conect_adelantado(j);
                                    for nro_etapa = desde_etapa:ultima_etapa_evaluada
                                        if nro_etapa >= etapas_fin_conect_adelantado(j) && ...
                                                nro_etapa < etapas_orig_conect_adelantado(j) 
                                            proyecto = this.pAdmProy.entrega_proyecto(conect_adelantado(j));
                                            sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                        end
                                    end
                                end
% DEBUG
if this.iNivelDebug > 1
plan_prueba = cPlanExpansion(8888888);
plan_prueba.Plan = plan_antes_intentos;
for nro_etapa = 1:this.pParOpt.CantidadEtapas
proyectos_en_sep = sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = plan_prueba.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
prot.imprime_texto(['Proyectos en SEP en etapa ' num2str(nro_etapa) ' es distinto a proyectos en plan']);
prot.imprime_texto(['Proyectos en SEP: ' num2str(proyectos_en_sep)]);
prot.imprime_texto(['Proyectos en plan: ' num2str(proyectos_en_plan)]);
error = MException('cOptACO:genera_planes_bl_elimina_desplaza',...
'Intento fallido 4 en BL Cambio Uprating luego de deshacer los proyectos del intento. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end
end
end
                            end
                            % determina mejor intento y si hay mejora
                            if this.iNivelDebug > 1
                                texto = '\nResultados de los intentos:';      
                                prot.imprime_texto(texto);
                                texto = sprintf('%-10s %-10s', 'Intento', 'Totex');
                                prot.imprime_texto(texto);
                                for jj = 1:length(proy_seleccionados.agregar)
                                    texto = sprintf('%-10s %-10s', num2str(jj), num2str(totex_total_intentos(jj)));
                                    prot.imprime_texto(texto);
                                end
                            end
                            
                            if existe_mejor_intento
                                if this.iNivelDebug > 1
                                    texto = ['   Existe mejor intento. Nr: ' num2str(id_mejor_intento)];      
                                    prot.imprime_texto(texto);
                                end  
                                pPlan.Plan = plan_actual_mejor_intento;

                                % modifica sep de acuerdo al mejor
                                % intento
                                desde_etapa = min(etapas_agregados);
                                for nro_etapa = desde_etapa:this.pParOpt.CantidadEtapas
                                    % agrega proyectos al sep de la etapa
                                    % primero proyectos de conectividad
                                    % agregados
                                    for j = 1:length(conect_agregados_mejor_intento)
                                        if nro_etapa >= etapas_conect_agregados_mejor_intento(j)
                                            proyecto = this.pAdmProy.entrega_proyecto(conect_agregados_mejor_intento(j));
                                            sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                        end
                                    end

                                    %luego proyectos de conectividad
                                    %adelantados
                                    for j = 1:length(conect_adelantado_mejor_intento)
                                        if nro_etapa >= etapas_fin_conect_adelantado_mejor_intento(j) && ...
                                                nro_etapa < etapas_orig_conect_adelantado_mejor_intento(j)
                                            proyecto = this.pAdmProy.entrega_proyecto(conect_adelantado_mejor_intento(j));
                                            sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                        end
                                    end

                                    % finalmente, proyectos agregados
                                    for j = 1:length(proy_agregados_mejor_intento)
                                        if nro_etapa >= etapas_agregados_mejor_intento(j)
                                            proyecto = this.pAdmProy.entrega_proyecto(proy_agregados_mejor_intento(j));
                                            sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                        end
                                    end
                                end
                                proyectos_restringidos_para_eliminar = [proyectos_restringidos_para_eliminar proy_agregados_mejor_intento];
% DEBUG
if this.iNivelDebug > 1
for nro_etapa = 1:this.pParOpt.CantidadEtapas
proyectos_en_sep = sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = pPlan.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
prot.imprime_texto(['Proyectos en SEP en etapa ' num2str(nro_etapa) ' es distinto a proyectos en plan']);
prot.imprime_texto(['Proyectos en SEP: ' num2str(proyectos_en_sep)]);
prot.imprime_texto(['Proyectos en plan: ' num2str(proyectos_en_plan)]);
error = MException('cOptACO:genera_planes_bl_elimina_desplaza',...
'Intento fallido 6 en BL Cambio Uprating luego de determinar el mejor intento. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end
end
end
                                
                            else
                                cant_busqueda_fallida = cant_busqueda_fallida + 1;
                                % se deshacen los cambios en el SEP
                                pPlan.Plan = plan_actual;
                                proyectos_eliminar = proy_seleccionados.eliminar;
                                etapas_eliminar = proy_seleccionados.etapa_eliminar;
                                proyectos_desplazar = proy_seleccionados.conectividad_desplazar;
                                etapas_originales_desplazar = proy_seleccionados.etapas_orig_conectividad_desplazar;
                                etapas_desplazar = proy_seleccionados.etapas_fin_conectividad_desplazar;
                                trafos_paral_eliminados = proy_seleccionados.trafos_paralelos_potenciales_a_eliminar;
                                etapas_trafos_paral_eliminados = proy_seleccionados.etapas_trafos_paralelos_potenciales_a_eliminar;

                                %proyectos desplazados
                                for k = 1:length(proyectos_desplazar)
                                    desde_etapa = etapas_originales_desplazar(k);
                                    hasta_etapa = etapas_desplazar(k);
                                    for nro_etapa = desde_etapa:hasta_etapa-1
                                        proyecto = this.pAdmProy.entrega_proyecto(proyectos_desplazar(k));
                                        sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    end
                                end
                                %proyectos eliminados
                                for k = 1:length(proyectos_eliminar)
                                    desde_etapa = etapas_eliminar(k);
                                    for nro_etapa = desde_etapa:this.pParOpt.CantidadEtapas
                                        proyecto = this.pAdmProy.entrega_proyecto(proyectos_eliminar(k));
                                        sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    end
                                end               

                                % trafos potenciales eliminados
                                for k = 1:length(trafos_paral_eliminados)
                                    desde_etapa = etapas_trafos_paral_eliminados(k);
                                    for nro_etapa = desde_etapa:this.pParOpt.CantidadEtapas
                                        proyecto = this.pAdmProy.entrega_proyecto(trafos_paral_eliminados(k));
                                        sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    end
                                end
% DEBUG
if this.iNivelDebug > 1
for nro_etapa = 1:this.pParOpt.CantidadEtapas
proyectos_en_sep = sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = pPlan.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
prot.imprime_texto(['Proyectos en SEP en etapa ' num2str(nro_etapa) ' es distinto a proyectos en plan']);
prot.imprime_texto(['Proyectos en SEP: ' num2str(proyectos_en_sep)]);
prot.imprime_texto(['Proyectos en plan: ' num2str(proyectos_en_plan)]);
error = MException('cOptACO:genera_planes_bl_elimina_desplaza',...
'Intento fallido 7 en BL Cambio Uprating luego de busqueda fallida. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end
end
end
                                
                            end
                        end

                        if this.iNivelDebug > 1
                            totex_despues_de_cambio_ur = pPlan.entrega_totex_total();
                            cantidad_proy_despues_de_cambio_ur = pPlan.cantidad_acumulada_proyectos();

                            prot.imprime_texto('Fin cambio uprating');
                            texto = sprintf('%-15s %-10s %-10s', ' ', 'No proy', 'Totex');
                            prot.imprime_texto(texto);
                            texto = sprintf('%-15s %-10s %-10s', 'Original', num2str(cantidad_proy_orig), num2str(totex_orig));
                            prot.imprime_texto(texto);
                            texto = sprintf('%-15s %-10s %-10s', 'Elimina', num2str(cantidad_proy_despues_de_elimina), num2str(totex_despues_de_elimina));
                            prot.imprime_texto(texto);
                            texto = sprintf('%-15s %-10s %-10s', 'Cambio UR', num2str(cantidad_proy_despues_de_cambio_ur), num2str(totex_despues_de_cambio_ur));
                            prot.imprime_texto(texto);
                        end
                    else
                        if this.iNivelDebug > 1
                            totex_despues_de_cambio_ur = 0;
                            cantidad_proy_despues_de_cambio_ur = 0;
                        end                        
                    end
                    
                    if this.pParOpt.BLEliminaDesplazaNuevoDesplaza && pPlan.cantidad_acumulada_proyectos() ~= 0
                        plan_original_intermedio = pPlan.Plan;
                        nro_etapa = 0;
                        nuevos_proyectos_eliminados = [];
                        while nro_etapa < this.pParOpt.CantidadEtapas
                            nro_etapa = nro_etapa +1;
                            if this.iNivelDebug > 1
                                prot.imprime_texto(['   Desplaza proyectos en etapa ' num2str(nro_etapa)]);
                            end
                            
                            cantidad_proyectos_etapa = pPlan.entrega_cantidad_proyectos_etapa(nro_etapa);
                            if cantidad_proyectos_etapa == 0
                                continue;
                            end

                            estructura_costos_actual = pPlan.entrega_estructura_costos();
                            plan_actual = pPlan.Plan;
                            evaluacion_actual = pPlan.entrega_evaluacion();

                            proyectos_restringidos_para_desplazar = [];
                            proyectos_desplazados = [];
                            cant_busqueda_fallida = 0;
                            maxima_cant_busqueda_fallida = min(this.pParOpt.BLEliminaDesplazaCantBusquedaFallida, cantidad_proyectos_etapa);
                            while cant_busqueda_fallida < maxima_cant_busqueda_fallida 

                                intento_paralelo_actual = 0;
                                intentos_actuales = cell(1,0);
                                proyectos_restringidos_para_desplazar_intento = proyectos_restringidos_para_desplazar;
                                fuerza_continuar_comparacion = false;
                                cantidad_mejores_intentos = 0;
                                while intento_paralelo_actual < this.pParOpt.BLEliminaDesplazaCantProyCompararBase || fuerza_continuar_comparacion
                                    intento_paralelo_actual = intento_paralelo_actual +1;

                                    proyectos_seleccionados = this.selecciona_proyectos_a_desplazar(pPlan, nro_etapa, proyectos_restringidos_para_desplazar_intento);
                                    if isempty(proyectos_seleccionados)
                                        intentos_actuales{intento_paralelo_actual}.Valido = false;
                                        if this.iNivelDebug > 1
                                            prot.imprime_texto(['   En etapa ' num2str(nro_etapa) ' nro intento ' num2str(intento_paralelo_actual) ' no hay proyectos seleccionados']);
                                        end
                                        % no hay más proyectos. Se termina
                                        % la evaluación
                                        intento_paralelo_actual = intento_paralelo_actual -1;
                                        break
                                    end

                                    % se agregan proyectos seleccionados a
                                    % proyectos restringidor para desplazar
                                    % intento, con tal de que no vuelva a ser
                                    % seleccionado
                                    proyectos_restringidos_para_desplazar_intento = [proyectos_restringidos_para_desplazar_intento proyectos_seleccionados];

                                    intentos_actuales{intento_paralelo_actual}.proyectos_seleccionados = proyectos_seleccionados;
                                    intentos_actuales{intento_paralelo_actual}.Totex = 999999999999999999999;
                                    intentos_actuales{intento_paralelo_actual}.Valido = false;
                                    intentos_actuales{intento_paralelo_actual}.Plan = [];
                                    intentos_actuales{intento_paralelo_actual}.AdelantaProyectos = false;
                                    % elimina proyectos de sep actual y desplaza
                                    % proyectos en el plan. Ojo que se eliminan en
                                    % orden inverso!
                                    for k = length(proyectos_seleccionados):-1:1
                                        proyecto = this.pAdmProy.entrega_proyecto(proyectos_seleccionados(k));
                                        sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                        if nro_etapa < this.pParOpt.CantidadEtapas
                                            pPlan.desplaza_proyectos(proyectos_seleccionados(k), nro_etapa, nro_etapa + 1);
                                        else
                                            pPlan.elimina_proyectos(proyectos_seleccionados(k), nro_etapa);
                                        end
                                    end

                                    %evalua red (proyectos ya se ingresaron al sep)
                                    this.evalua_red(sep_actuales{nro_etapa}, nro_etapa, [], false); % false indica que proyectos se eliminan
                                    this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa);
                                    this.calcula_costos_totales(pPlan);

                                    if pPlan.es_valido(nro_etapa) && pPlan.entrega_totex_total() < estructura_costos_actual.TotexTotal
                                        % cambio produce mejora. Se acepta
                                        intentos_actuales{intento_paralelo_actual}.proyectos_seleccionados = proyectos_seleccionados;
                                        intentos_actuales{intento_paralelo_actual}.Totex = pPlan.entrega_totex_total();
                                        intentos_actuales{intento_paralelo_actual}.Valido = true;
                                        intentos_actuales{intento_paralelo_actual}.Plan = pPlan.Plan;
                                        intentos_actuales{intento_paralelo_actual}.estructura_costos_actual = pPlan.entrega_estructura_costos();
                                        intentos_actuales{intento_paralelo_actual}.evaluacion_actual = pPlan.entrega_evaluacion();
                                        cantidad_mejores_intentos = cantidad_mejores_intentos + 1;
                                        if this.iNivelDebug > 1
                                            texto_desplazados = '';
                                            for jj = 1:length(proyectos_seleccionados)
                                                texto_desplazados = [texto_desplazados ' ' num2str(proyectos_seleccionados(jj))];
                                            end
                                            texto = ['   Nuevo(s) proyecto(s) desplazados etapa ' num2str(nro_etapa) ':' texto_desplazados ' generan mejora'];
                                            prot.imprime_texto(texto);
                                        end
                                    else
                                        % cambio no produce mejora.
                                        % verificar si tiene potencial de ser eliminado o si adelandar 
                                        % proyecto seleccionado produce mejora
                                        if this.iNivelDebug > 1
                                            texto_desplazados = '';
                                            for jj = 1:length(proyectos_seleccionados)
                                                texto_desplazados = [texto_desplazados ' ' num2str(proyectos_seleccionados(jj))];
                                            end
                                            if pPlan.es_valido(nro_etapa)
                                                texto = ['   Proyectos desplazados etapa ' num2str(nro_etapa) ':' texto_desplazados ' no generan mejora. Totex total: ' num2str(pPlan.entrega_totex_total()) '. Se verifica si adelantarlo genera mejora'];
                                            else
                                                texto = ['   Proyectos desplazados etapa ' num2str(nro_etapa) ':' texto_desplazados ' vuelven al plan invalido. Se verifica si adelantarlos generan mejora'];
                                            end
                                            prot.imprime_texto(texto);
                                        end

                                        proyectos_restringidos_para_desplazar = [proyectos_restringidos_para_desplazar proyectos_seleccionados];
                                        intentos_actuales{intento_paralelo_actual}.Valido = false;

                                        %[p_elim, p_desp, e_orig_desp, e_desp]= this.determina_factibilidad_eliminar_proyecto(proyectos_seleccionados, nro_etapa);
                                        % linlin
                                        %proyectos_potenciales_eliminar
                                    end

                                    % deshace cambios en los sep actuales 
                                    pPlan.inserta_evaluacion_etapa(nro_etapa, evaluacion_actual(nro_etapa));
                                    pPlan.Plan = plan_actual;
                                    pPlan.inserta_estructura_costos(estructura_costos_actual);

                                    % deshace los cambios hechos en los sep
                                    % actuales
                                    for k = 1:length(proyectos_seleccionados)
                                        proyecto = this.pAdmProy.entrega_proyecto(proyectos_seleccionados(k));
                                        sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    end

                                    if ~intentos_actuales{intento_paralelo_actual}.Valido && ...
                                        ~isempty(plan_original_intermedio(nro_etapa).Proyectos == proyectos_seleccionados(end)) && ...
                                        nro_etapa > 1
                                        % se ve si proyecto se puede adelantar
                                        if this.iNivelDebug > 1                                        
                                            texto = '      No hubo mejora en desplazamiento. Se verifica si adelantar proyectos produce mejora';
                                            prot.imprime_texto(texto);
                                        end

                                        proy_adelantar = this.selecciona_proyectos_a_adelantar(pPlan, nro_etapa, proyectos_seleccionados(end));
                                        % proy_adelantar.seleccionado
                                        % proy_adelantar.etapa_seleccionado
                                        % proy_adelantar.seleccion_directa
                                        % proy_adelantar.primera_etapa_posible = [];
                                        % proy_adelantar.proy_conect_adelantar = [];
                                        % proy_adelantar.etapas_orig_conect = [];

                                        etapa_adelantar = nro_etapa;
                                        ultima_etapa_evaluada = nro_etapa;
                                        
                                        flag_salida = false;
                                        existe_resultado_adelanta = false;
                                        while etapa_adelantar > proy_adelantar.primera_etapa_posible && ~flag_salida
                                            etapa_adelantar = etapa_adelantar - 1;
                                            % agrega proyectos en sep actual en
                                            % etapa actual
                                            for k = 1:length(proy_adelantar.proy_conect_adelantar)
                                                if etapa_adelantar < proy_adelantar.etapas_orig_conect(k) 
                                                    proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.proy_conect_adelantar(k));
                                                    sep_actuales{etapa_adelantar}.agrega_proyecto(proyecto);
                                                    pPlan.adelanta_proyectos(proy_adelantar.proy_conect_adelantar(k), etapa_adelantar + 1, etapa_adelantar);
                                                end
                                            end
                                            proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.seleccionado);
                                            sep_actuales{etapa_adelantar}.agrega_proyecto(proyecto);
                                            pPlan.adelanta_proyectos(proy_adelantar.seleccionado, etapa_adelantar + 1, etapa_adelantar);

                                            %evalua red (proyectos ya se ingresaron
                                            %al sep)
                                            this.evalua_red(sep_actuales{etapa_adelantar}, etapa_adelantar, [], false); % false indica que proyectos se eliminan
                                            this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{etapa_adelantar}.entrega_opf().entrega_evaluacion(), etapa_adelantar);
                                            this.calcula_costos_totales(pPlan);
                                            ultima_etapa_evaluada = etapa_adelantar;
                                            hay_mejora = false;
                                            if (~existe_resultado_adelanta && pPlan.entrega_totex_total() < estructura_costos_actual.TotexTotal) || ...
                                               (existe_resultado_adelanta && pPlan.entrega_totex_total() < intentos_actuales{intento_paralelo_actual}.Totex)

                                                % adelantar el proyecto produce
                                                % mejora. Se guarda resultado
                                                hay_mejora = true;
                                                intentos_actuales{intento_paralelo_actual}.Plan = pPlan.Plan;
                                                intentos_actuales{intento_paralelo_actual}.estructura_costos_actual = pPlan.entrega_estructura_costos();
                                                intentos_actuales{intento_paralelo_actual}.evaluacion_actual = pPlan.entrega_evaluacion();
                                                intentos_actuales{intento_paralelo_actual}.Valido = true;
                                                intentos_actuales{intento_paralelo_actual}.Totex = pPlan.entrega_totex_total();
                                                intentos_actuales{intento_paralelo_actual}.PlanActualHastaEtapa = ultima_etapa_evaluada;
                                                intentos_actuales{intento_paralelo_actual}.AdelantaProyectos = true;
                                                intentos_actuales{intento_paralelo_actual}.proy_seleccionados = proy_adelantar;
                                                existe_resultado_adelanta = true;
                                                if this.iNivelDebug > 1                                        
                                                    texto = ['      Adelantar proyecto de etapa ' num2str(etapa_adelantar+1) ' a ' num2str(etapa_adelantar) ' genera mejora. Totex actual etapa: ' num2str(pPlan.entrega_totex_total())];
                                                    prot.imprime_texto(texto);
                                                end
                                            else
                                                if this.iNivelDebug > 1                                        
                                                    texto = ['      Adelantar proyecto de etapa ' num2str(etapa_adelantar+1) ' a ' num2str(etapa_adelantar) ' no genera mejora. Totex actual etapa: ' num2str(pPlan.entrega_totex_total())];
                                                    prot.imprime_texto(texto);
                                                end                                            
                                            end

                                            if ~existe_resultado_adelanta && hay_mejora
                                                % se elimina proyecto de
                                                % proyectos restringidos para
                                                % desplazar
                                                proyectos_restringidos_para_desplazar(proyectos_restringidos_para_desplazar == proyectos_seleccionados(end)) = [];
                                            end

                                            if ~hay_mejora
                                                flag_salida = true;
                                            end
                                        end

                                        % se deshacen los cambios en el sep
                                        pPlan.Plan = plan_actual;
                                        pPlan.inserta_estructura_costos(estructura_costos_actual);
                                        pPlan.inserta_evaluacion(evaluacion_actual);

                                        for etapa_adelantar = ultima_etapa_evaluada:nro_etapa-1
                                            % deshace los cambios hechos en los sep
                                            % actuales hasta la etapa correcta
                                            % Ojo! orden inverso entre desplaza y
                                            % elimina proyectos!
                                            proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.seleccionado);
                                            sep_actuales{etapa_adelantar}.elimina_proyecto(proyecto);
                                            for k = length(proy_adelantar.proy_conect_adelantar):-1:1
                                                if etapa_adelantar < proy_adelantar.etapas_orig_conect(k) 
                                                    proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.proy_conect_adelantar(k));
                                                    sep_actuales{etapa_adelantar}.elimina_proyecto(proyecto);
                                                end
                                            end
                                        end

                                        if existe_resultado_adelanta
                                            % quiere decir que hubo mejora
                                            cantidad_mejores_intentos = cantidad_mejores_intentos + 1;
                                        end
                                    end

                                    % se verifica si hay que seguir comparando
                                    if fuerza_continuar_comparacion == false && ...
                                       intento_paralelo_actual == this.pParOpt.BLEliminaDesplazaCantProyCompararBase && ...
                                       cantidad_mejores_intentos_completo > 0 && ...
                                       cantidad_mejores_intentos_completo < this.pParOpt.BLEliminaDesplazaCantProyCompararBase && ...
                                       this.pParOpt.BLEliminaDesplazaCantProyCompararSinMejora > this.pParOpt.BLEliminaDesplazaCantProyCompararBase

                                        fuerza_continuar_comparacion = true;
                                    elseif fuerza_continuar_comparacion && intento_paralelo_actual == this.pParOpt.BLEliminaDesplazaCantProyCompararSinMejora
                                        fuerza_continuar_comparacion = false;
                                    end
                                end

                                % determina mejor intento
                                existe_mejora = false;
                                mejor_totex = 0;
                                id_mejor_plan_intento = 0;
                                for kk = 1:intento_paralelo_actual
                                    if intentos_actuales{kk}.Valido
                                        existe_mejora = true;
                                        if id_mejor_plan_intento == 0
                                            id_mejor_plan_intento = kk;
                                            mejor_totex = intentos_actuales{kk}.Totex;
                                        elseif intentos_actuales{kk}.Totex < mejor_totex
                                            id_mejor_plan_intento = kk;
                                            mejor_totex = intentos_actuales{kk}.Totex;
                                        end

                                        if this.iNivelDebug > 1
                                            if intentos_actuales{kk}.AdelantaProyectos
                                                proyectos_adelantar = [intentos_actuales{kk}.proy_seleccionados.proy_conect_adelantar intentos_actuales{kk}.proy_seleccionados.seleccionado];
                                                texto = ['      Intento ' num2str(kk) ' es valido (adelantar)' ...
                                                         '. Totex intento: ' num2str(intentos_actuales{kk}.Totex) '. Proyectos adelantar: '];
                                                for oo = 1:length(proyectos_adelantar)
                                                    texto = [texto ' ' num2str(proyectos_adelantar(oo))];
                                                end
                                            else
                                                texto = ['      Intento ' num2str(kk) ' es valido (desplazar). Totex intento: ' num2str(intentos_actuales{kk}.Totex) '. Proyectos a desplazar: '];
                                                for oo = 1:length(intentos_actuales{kk}.proyectos_seleccionados)
                                                    texto = [texto ' ' num2str(intentos_actuales{kk}.proyectos_seleccionados(oo))];
                                                end
                                            end
                                            prot.imprime_texto(texto);
                                        end
                                    else
                                        if this.iNivelDebug > 1
                                            texto = ['      Intento ' num2str(kk) ' no es valido. Totex intento: ' num2str(intentos_actuales{kk}.Totex) '. Proyectos a desplazar: '];
                                            for oo = 1:length(intentos_actuales{kk}.proyectos_seleccionados)
                                                texto = [texto ' ' num2str(intentos_actuales{kk}.proyectos_seleccionados(oo))];
                                            end
                                            prot.imprime_texto(texto);
                                        end
                                        
                                    end
                                end

                                if existe_mejora
                                    if this.iNivelDebug > 1
                                        texto = ['      Mejor intento: ' num2str(id_mejor_plan_intento)];
                                    end

                                    plan_actual = intentos_actuales{id_mejor_plan_intento}.Plan;
                                    evaluacion_actual = intentos_actuales{id_mejor_plan_intento}.evaluacion_actual;
                                    estructura_costos_actual = intentos_actuales{id_mejor_plan_intento}.estructura_costos_actual;
                                    pPlan.Plan = plan_actual;
                                    pPlan.inserta_estructura_costos(estructura_costos_actual);
                                    pPlan.inserta_evaluacion(evaluacion_actual);

                                    % se implementa plan hasta la etapa actual del
                                    % mejor intento
                                    if intentos_actuales{id_mejor_plan_intento}.AdelantaProyectos
                                        proy_adelantar = intentos_actuales{id_mejor_plan_intento}.proy_seleccionados;
                                        ultima_etapa_valida_intento = intentos_actuales{id_mejor_plan_intento}.PlanActualHastaEtapa;

                                        for etapa_adelantar = ultima_etapa_valida_intento:nro_etapa-1
                                            % agrega proyectos en sep actual en
                                            % etapa actual
                                            for k = 1:length(proy_adelantar.proy_conect_adelantar)
                                                if etapa_adelantar < proy_adelantar.etapas_orig_conect(k) 
                                                    proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.proy_conect_adelantar(k));
                                                    sep_actuales{etapa_adelantar}.agrega_proyecto(proyecto);
                                                end
                                            end
                                            proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.seleccionado);
                                            sep_actuales{etapa_adelantar}.agrega_proyecto(proyecto);
                                        end
                                    else
                                        % se eliminan proyectos seleccionados del sep
                                        % actual en etapa actual
                                        for k = length(intentos_actuales{id_mejor_plan_intento}.proyectos_seleccionados):-1:1
                                            proyecto = this.pAdmProy.entrega_proyecto(intentos_actuales{id_mejor_plan_intento}.proyectos_seleccionados(k));
                                            sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                        end
                                        
                                        proyectos_desplazados = [proyectos_desplazados intentos_actuales{id_mejor_plan_intento}.proyectos_seleccionados(end)];
                                        % se agrega proyecto a la lista de
                                        % nuevos proyectos eliminados si
                                        % etapa actual corresponde a la
                                        % última etapa
                                        
                                        if nro_etapa == this.pParOpt.CantidadEtapas
                                            nuevos_proyectos_eliminados = [nuevos_proyectos_eliminados intentos_actuales{id_mejor_plan_intento}.proyectos_seleccionados(end)];
                                        end
                                    end
                                else
                                    cant_busqueda_fallida = cant_busqueda_fallida + 1;
                                    % no hubo mejora por lo que no es necesario
                                    % rehacer ningún plan
                                    if this.iNivelDebug > 1
                                        texto = '      No hubo mejora en ninguno de los intentos';
                                        prot.imprime_texto(texto);
                                    end                             
                                end                     
                            end

                            % fin de desplazamiento para la etapa
                            if this.iNivelDebug > 1
                                texto = ['Cantidad de proyectos desplazados plan ' num2str(pPlan.entrega_no()) ' en etapa ' num2str(nro_etapa) ': ' num2str(length(proyectos_desplazados))];
                                prot.imprime_texto(texto)
                            end
                        end

                        if this.iNivelDebug > 1
                            totex_despues_de_nuevo_desplaza = pPlan.entrega_totex_total();
                            cantidad_proy_despues_de_nuevo_desplaza = pPlan.cantidad_acumulada_proyectos();
                            
                            prot.imprime_texto('Fin nuevo desplaza proyectos');
                            texto = sprintf('%-15s %-10s %-10s', ' ', 'No proy', 'Totex');
                            prot.imprime_texto(texto);
                            texto = sprintf('%-15s %-10s %-10s', 'Original', num2str(cantidad_proy_orig), num2str(totex_orig));
                            prot.imprime_texto(texto);
                            texto = sprintf('%-15s %-10s %-10s', 'Elimina', num2str(cantidad_proy_despues_de_elimina), num2str(totex_despues_de_elimina));
                            prot.imprime_texto(texto);
                            texto = sprintf('%-15s %-10s %-10s', 'Cambio UR', num2str(cantidad_proy_despues_de_cambio_ur), num2str(totex_despues_de_cambio_ur));
                            prot.imprime_texto(texto);
                            texto = sprintf('%-15s %-10s %-10s', 'Desplaza', num2str(cantidad_proy_despues_de_nuevo_desplaza), num2str(totex_despues_de_nuevo_desplaza));
                            prot.imprime_texto(texto);

                            prot.imprime_texto('Plan actual despues de nuevo desplaza proyectos');
                            pPlan.agrega_nombre_proyectos(this.pAdmProy);
                            pPlan.imprime();

                        end
                        
                        proyectos_eliminados = [proyectos_eliminados nuevos_proyectos_eliminados];
                    end
                    
                    if this.pParOpt.BLEliminaDesplazaNuevoAgrega && ~isempty(proyectos_eliminados)
                        if this.iNivelDebug > 1
                            prot.imprime_texto('Verifica si agregar proyectos eliminados mejora plan');
                        end

                        proyectos_potenciales_agregar = flip(proyectos_eliminados);
                        id_eliminar = [];
                        for jj = 1:length(proyectos_potenciales_agregar)
                            id_proy_agregar = proyectos_potenciales_agregar(jj);
                            proy_agregar_actual = this.pAdmProy.entrega_proyecto(id_proy_agregar);
                            if strcmp(proy_agregar_actual.entrega_tipo_proyecto(), 'AS') || ...
                                    strcmp(proy_agregar_actual.entrega_tipo_proyecto(), 'AT') && ...
                                    proy_agregar_actual.Elemento(1).entrega_id_corredor() == 0 && ...
                                    proy_agregar_actual.Elemento(1).entrega_indice_paralelo() == 1
                                id_eliminar = [id_eliminar id_proy_agregar];
                            end
                        end
                        proyectos_potenciales_agregar(ismember(proyectos_potenciales_agregar, id_eliminar)) = [];
                        
                        evaluacion_actual = pPlan.entrega_evaluacion();
                        estructura_costos_actual = pPlan.entrega_estructura_costos();
                        plan_actual = pPlan.Plan;
                        proyectos_agregados_nuevamente = [];
                        proyectos_descartados = [];
                        while ~isempty(proyectos_potenciales_agregar)
                            cantidad_intentos = length(proyectos_potenciales_agregar);
                            intento_paralelo_actual = 0;
                            intentos_actuales = cell(cantidad_intentos,0);
                            while intento_paralelo_actual < cantidad_intentos
                                intento_paralelo_actual = intento_paralelo_actual +1;
                                estructura_costos_actual_intento = estructura_costos_actual;

                                proy_seleccionados = this.selecciona_proyectos_a_agregar(pPlan, proyectos_potenciales_agregar(intento_paralelo_actual));
                                % proy_seleccionados.seleccionado
                                % proy_seleccionados.primera_etapa_posible = [];
                                % proy_seleccionados.proy_conect_agregar = [];
                                % proy_seleccionados.proy_conect_adelantar = [];
                                % proy_seleccionados.etapas_orig_conect_adelantar = [];


                                if proy_seleccionados.primera_etapa_posible == 0
                                    intentos_actuales{intento_paralelo_actual}.Valido = false;
                                    intentos_actuales{intento_paralelo_actual}.proy_seleccionados = proy_seleccionados;
                                    intentos_actuales{intento_paralelo_actual}.Totex = 999999999999999999999;
                                    continue;
                                end

                                intentos_actuales{intento_paralelo_actual}.proy_seleccionados = proy_seleccionados;
                                intentos_actuales{intento_paralelo_actual}.Totex = 999999999999999999999;
                                intentos_actuales{intento_paralelo_actual}.Valido = false;
                                intentos_actuales{intento_paralelo_actual}.Plan = [];
                                %intentos_actuales{intento_paralelo_actual}.estructura_costos_actual = [];
                                %intentos_actuales{intento_paralelo_actual}.evaluacion_actual = [];

                                if this.iNivelDebug > 1
                                    texto = sprintf('%-25s %-10s %-20s %-10s %-10s %-10s',...
                                                    '      Totex Plan Base ', num2str(estructura_costos_plan_base.TotexTotal), ...
                                                    'Totex plan actual', num2str(estructura_costos_actual.TotexTotal), ...
                                                    'Intento: ', num2str(intento_paralelo_actual));
                                    prot.imprime_texto(texto);
                                end

                                nro_etapa = this.pParOpt.CantidadEtapas+1;
                                flag_salida = false;
                                max_cant_intentos_fallidos_agrega = this.pParOpt.CantidadIntentosFallidosAdelanta;
                                cant_intentos_fallidos_agrega = 0;
                                cant_intentos_agrega = 0;
                                ultimo_totex_agrega = estructura_costos_actual.TotexTotal;
                                while nro_etapa > proy_seleccionados.primera_etapa_posible && ~flag_salida
                                    nro_etapa = nro_etapa - 1;
                                    cant_intentos_agrega = cant_intentos_agrega + 1;
                                    % agrega proyectos en sep actual en
                                    % etapa actual
                                    for k = 1:length(proy_seleccionados.proy_conect_adelantar)
                                        if nro_etapa < proy_seleccionados.etapas_orig_conect_adelantar (k) 
                                            proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionados.proy_conect_adelantar(k));
                                            sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                            pPlan.adelanta_proyectos(proy_seleccionados.proy_conect_adelantar(k), nro_etapa + 1, nro_etapa);
                                        end
                                    end

                                    for k = 1:length(proy_seleccionados.proy_conect_agregar)
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionados.proy_conect_agregar(k));
                                        sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                        if nro_etapa == this.pParOpt.CantidadEtapas
                                            pPlan.agrega_proyecto(nro_etapa, proy_seleccionados.proy_conect_agregar(k));
                                        else
                                            pPlan.adelanta_proyectos(proy_seleccionados.proy_conect_agregar(k), nro_etapa + 1, nro_etapa);
                                        end
                                    end
                                    proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionados.seleccionado);
                                    sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    if nro_etapa == this.pParOpt.CantidadEtapas
                                        pPlan.agrega_proyecto(nro_etapa, proy_seleccionados.seleccionado);
                                    else
                                        pPlan.adelanta_proyectos(proy_seleccionados.seleccionado, nro_etapa + 1, nro_etapa);
                                    end
                                    %evalua red (proyectos ya se ingresaron
                                    %al sep)
                                    this.evalua_red(sep_actuales{nro_etapa}, nro_etapa, [], false); % false indica que proyectos se eliminan
                                    this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa);
                                    this.calcula_costos_totales(pPlan);
                                    ultima_etapa_evaluada = nro_etapa;

                                    if cant_intentos_agrega == 1
                                        delta_actual_agrega = pPlan.entrega_totex_total()-ultimo_totex_agrega;
                                    else
                                        delta_nuevo_agrega = pPlan.entrega_totex_total()-ultimo_totex_agrega;
                                        if delta_nuevo_agrega > 0 && delta_nuevo_agrega > delta_actual_agrega
                                            cant_intentos_fallidos_agrega = cant_intentos_fallidos_agrega + 1;
                                        elseif delta_nuevo_agrega < 0
                                            cant_intentos_fallidos_agrega = 0;
                                        end
                                        delta_actual_agrega = delta_nuevo_agrega;
                                    end
                                    ultimo_totex_agrega = pPlan.entrega_totex_total();

                                    if pPlan.entrega_totex_total() < estructura_costos_actual_intento.TotexTotal
                                        % adelantar el proyecto produce
                                        % mejora. Se guarda resultado
                                        estructura_costos_actual_intento = pPlan.entrega_estructura_costos();
                                        evaluacion_actual_intento = pPlan.entrega_evaluacion();

                                        intentos_actuales{intento_paralelo_actual}.Plan = pPlan.Plan;
                                        intentos_actuales{intento_paralelo_actual}.estructura_costos_actual = estructura_costos_actual_intento;
                                        intentos_actuales{intento_paralelo_actual}.evaluacion_actual = evaluacion_actual_intento;
                                        intentos_actuales{intento_paralelo_actual}.Valido = true;
                                        intentos_actuales{intento_paralelo_actual}.Totex = estructura_costos_actual_intento.TotexTotal;
                                        intentos_actuales{intento_paralelo_actual}.PlanActualHastaEtapa = nro_etapa;

                                        if this.iNivelDebug > 1                                        
                                            texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ' genera mejora parcial. Totex actual etapa: ' num2str(pPlan.entrega_totex_total())];
                                            prot.imprime_texto(texto);
                                        end
                                    else
                                        if this.iNivelDebug > 1                                        
                                            texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ...
                                                ' no genera mejora. Totex actual etapa: ' num2str(pPlan.entrega_totex_total()) ...
                                                ' Delta actual adelanta: ' num2str(delta_actual_agrega) ...
                                                ' Cant. intentos fallidos adelanta: ' num2str(cant_intentos_fallidos_agrega)];
                                            prot.imprime_texto(texto);
                                        end
                                        % se verifica si se alcanzó el máximo número de intentos fallidos adelanta
                                        if cant_intentos_fallidos_agrega >= max_cant_intentos_fallidos_agrega
                                            flag_salida = true;
                                        end
                                    end
                                end

                                % se deshacen los cambios en el sep
                                pPlan.Plan = plan_actual;
                                pPlan.inserta_estructura_costos(estructura_costos_actual);
                                pPlan.inserta_evaluacion(evaluacion_actual);

                                for nro_etapa = ultima_etapa_evaluada:this.pParOpt.CantidadEtapas
                                    % deshace los cambios hechos en los sep
                                    % actuales hasta la etapa correcta
                                    % Ojo! orden inverso entre desplaza y
                                    % elimina proyectos!
                                    proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionados.seleccionado);
                                    sep_actuales{nro_etapa}.elimina_proyecto(proyecto);

                                    for k = length(proy_seleccionados.proy_conect_agregar):-1:1
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionados.proy_conect_agregar(k));
                                        sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    end

                                    for k = length(proy_seleccionados.proy_conect_adelantar):-1:1
                                        if nro_etapa < proy_seleccionados.etapas_orig_conect_adelantar(k) 
                                            proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionados.proy_conect_adelantar(k));
                                            sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                        end
                                    end
                                end
                            end

                            % determina mejor intento
                            existe_mejora = false;
                            mejor_totex = 0;
                            id_mejor_plan_intento = 0;
                            for kk = 1:cantidad_intentos
                                if intentos_actuales{kk}.Valido
                                    existe_mejora = true;
                                    if id_mejor_plan_intento == 0
                                        id_mejor_plan_intento = kk;
                                        mejor_totex = intentos_actuales{kk}.Totex;
                                    elseif intentos_actuales{kk}.Totex < mejor_totex 
                                        id_mejor_plan_intento = kk;
                                        mejor_totex = intentos_actuales{kk}.Totex;
                                    end
                                    if this.iNivelDebug > 1                                    
                                        proyectos_agregar = [intentos_actuales{kk}.proy_seleccionados.proy_conect_agregar intentos_actuales{kk}.proy_seleccionados.proy_conect_adelantar intentos_actuales{kk}.proy_seleccionados.seleccionado];
                                        texto = ['      Intento ' num2str(kk) ' es valido' ...
                                                 '. Totex intento: ' num2str(intentos_actuales{kk}.Totex) '. Proyectos agregar: '];
                                        for oo = 1:length(proyectos_agregar)
                                            texto = [texto ' ' num2str(proyectos_agregar(oo))];
                                        end
                                        prot.imprime_texto(texto);
                                    end
                                else
                                    % intento no fue válido. Se elimina
                                    % proyecto de la lista a agregar y también
                                    % proyectos dependientes que estén en lista
                                    if this.iNivelDebug > 1
                                        proyectos_agregar = [intentos_actuales{kk}.proy_seleccionados.proy_conect_agregar intentos_actuales{kk}.proy_seleccionados.proy_conect_adelantar intentos_actuales{kk}.proy_seleccionados.seleccionado];
                                        texto = ['      Intento ' num2str(kk) ' no valido' ...
                                                 '. Totex intento: ' num2str(intentos_actuales{kk}.Totex) '. Proyectos agregar: '];
                                        for oo = 1:length(proyectos_agregar)
                                            texto = [texto ' ' num2str(proyectos_agregar(oo))];
                                        end
                                        prot.imprime_texto(texto);
                                    end
                                    proyectos_potenciales_agregar(proyectos_potenciales_agregar == intentos_actuales{kk}.proy_seleccionados.seleccionado) = [];
                                    for ii = 1:length(proyectos_potenciales_agregar)
                                        proy_lista = this.pAdmProy.entrega_proyecto(proyectos_potenciales_agregar(ii));
                                        if proy_lista.TieneDependencia
                                            for dep = 1:length(proy_lista.ProyectoDependiente)
                                                id_proy_dep = proy_lista.ProyectoDependiente(dep).Indice;
                                                if id_proy_dep == intentos_actuales{kk}.proy_seleccionados.seleccionado
                                                    proyectos_potenciales_agregar(proyectos_potenciales_agregar == id_proy_dep) = [];
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                            if existe_mejora
                                if this.iNivelDebug > 1
                                    texto = ['      Mejor intento: ' num2str(id_mejor_plan_intento)];
                                    prot.imprime_texto(texto);
                                end

                                plan_actual = intentos_actuales{id_mejor_plan_intento}.Plan;
                                evaluacion_actual = intentos_actuales{id_mejor_plan_intento}.evaluacion_actual;
                                estructura_costos_actual = intentos_actuales{id_mejor_plan_intento}.estructura_costos_actual;
                                pPlan.Plan = plan_actual;
                                pPlan.inserta_estructura_costos(estructura_costos_actual);
                                pPlan.inserta_evaluacion(evaluacion_actual);

                                proy_seleccionados = intentos_actuales{id_mejor_plan_intento}.proy_seleccionados;                            
                                proyectos_agregados_nuevamente = [proyectos_agregados_nuevamente proy_seleccionados.seleccionado];
                                proyectos_potenciales_agregar(proyectos_potenciales_agregar == proy_seleccionados.seleccionado) = [];

                                % se implementa plan hasta la etapa actual del
                                % mejor intento
                                ultima_etapa_valida_intento = intentos_actuales{id_mejor_plan_intento}.PlanActualHastaEtapa;
                                for nro_etapa = ultima_etapa_valida_intento:this.pParOpt.CantidadEtapas
                                    % agrega proyectos en sep actual en
                                    % etapa actual
                                    for k = 1:length(proy_seleccionados.proy_conect_adelantar)
                                        if nro_etapa < proy_seleccionados.etapas_orig_conect_adelantar (k) 
                                            proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionados.proy_conect_adelantar(k));
                                            sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                        end
                                    end

                                    for k = 1:length(proy_seleccionados.proy_conect_agregar)
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionados.proy_conect_agregar(k));
                                        sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    end
                                    proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionados.seleccionado);
                                    sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                end
                            else
                                if this.iNivelDebug > 1
                                    texto = '      No hubo mejora en ninguno de los intentos';
                                    prot.imprime_texto(texto);
                                end
                            end
                            if this.iNivelDebug > 1
                                texto = '      Lista proy potenciales a agregar: ';
                                for ii = 1:length(proyectos_potenciales_agregar)
                                    texto = [texto ' ' num2str(proyectos_potenciales_agregar(ii))];
                                end
                                prot.imprime_texto(texto);

                            end

                            if this.iNivelDebug > 1
                                texto = 'Imprime plan actual despues de los intentos';
                                prot.imprime_texto(texto);
                                pPlan.agrega_nombre_proyectos(this.pAdmProy);
                                pPlan.imprime();
                            end
                        end

                        if this.iNivelDebug > 1
                            totex_despues_de_nuevo_agrega = pPlan.entrega_totex_total();
                            cantidad_proy_despues_de_nuevo_agrega = pPlan.cantidad_acumulada_proyectos();
                            
                            prot.imprime_texto('Fin agrega proyectos eliminados');
                            texto = 'Proyectos agregados nuevamente:';
                            for ii = 1:length(proyectos_agregados_nuevamente)
                                texto = [texto ' ' num2str(proyectos_agregados_nuevamente(ii))];
                            end
                            prot.imprime_texto(texto);

                            texto = sprintf('%-15s %-10s %-10s', ' ', 'No proy', 'Totex');
                            prot.imprime_texto(texto);
                            texto = sprintf('%-15s %-10s %-10s', 'Original', num2str(cantidad_proy_orig), num2str(totex_orig));
                            prot.imprime_texto(texto);
                            texto = sprintf('%-15s %-10s %-10s', 'Elimina', num2str(cantidad_proy_despues_de_elimina), num2str(totex_despues_de_elimina));
                            prot.imprime_texto(texto);
                            texto = sprintf('%-15s %-10s %-10s', 'Desplaza', num2str(cantidad_proy_despues_de_nuevo_desplaza), num2str(totex_despues_de_nuevo_desplaza));
                            prot.imprime_texto(texto);
                            texto = sprintf('%-15s %-10s %-10s', 'Agrega', num2str(cantidad_proy_despues_de_nuevo_agrega), num2str(totex_despues_de_nuevo_agrega));
                            prot.imprime_texto(texto);
                        end
                    end

                    % fin busqueda local

                    if pPlan.cantidad_acumulada_proyectos() == 0
                        if this.iNivelDebug > 1
                        	prot.imprime_texto('Plan se elimina, ya que no contiene proyectos');
                        end
                        pPlan.ResultadoEvaluacion = [];
                        delete(pPlan);
                    
                        % borra sep actuales
                        for nro_etapa = 1:this.pParOpt.CantidadEtapas
                            sep_actuales{nro_etapa} = [];
                        end
                        continue;
                    end
                    
                    if this.iNivelDebug > 1
                        % imprime planes originales y nuevo
                    	prot.imprime_texto('Plan original en busqueda local elimina desplaza');
                        plan_orig.agrega_nombre_proyectos(this.pAdmProy);
                        plan_orig.imprime();

                    	prot.imprime_texto('Plan final en busqueda local elimina desplaza');
                        pPlan.agrega_nombre_proyectos(this.pAdmProy);
                        pPlan.imprime();
                    end
                    if this.iNivelDebug > 2
                        %verifica que totex total de plan nuevo es correcto
                        prot = cProtocolo.getInstance;
                        plan_prueba = cPlanExpansion(99999998);
                        plan_prueba.inserta_iteracion(nro_iteracion);
                        plan_prueba.inserta_busqueda_local(false);
                        plan_prueba.inserta_plan_base(1);
                        plan_prueba.Plan = pPlan.Plan;
                        plan_prueba.inserta_sep_original(this.pSEP.crea_copia());
                        for nro_etapa = 1:this.pParOpt.CantidadEtapas
                            valido = this.evalua_plan(plan_prueba, nro_etapa);
                            if ~valido
                                texto = 'Error de programacion. Plan final de desplaza elimina no es válido';
                                error = MException('cOptACO:genera_planes_bl_elimina_desplaza',texto);
                                throw(error)
                            end
                        end
                        this.calcula_costos_totales(plan_prueba);

                        texto = 'Imprime plan obtenido de busqueda local elimina/desplaza harta memoria';
                        prot.imprime_texto(texto)

                        pPlan.agrega_nombre_proyectos(this.pAdmProy);
                        pPlan.imprime();

                        texto = 'Imprime plan prueba para comparar (elimina/desplaza harta memoria)';
                        prot.imprime_texto(texto)

                        plan_prueba.agrega_nombre_proyectos(this.pAdmProy);
                        plan_prueba.imprime();

                        if round(plan_prueba.TotexTotal,2) ~= round(pPlan.TotexTotal,2)
                            texto = 'Error de programacion. Totex total de plan prueba es distinto al de pPlan!';
                            error = MException('cOptACO:genera_planes_bl_elimina_desplaza',texto);
                            throw(error)
                        end
                    end
              
                    % guarda plan generado
                    cantidad_planes_generados = cantidad_planes_generados + 1;
                    planes_generados{cantidad_planes_generados} = pPlan;

                    % borra sep actuales
                    for nro_etapa = 1:this.pParOpt.CantidadEtapas
                        sep_actuales{nro_etapa} = [];
                    end
                end %todas las hormigas de la búsqueda local finalizadas
            end  %plan local terminado                
            indice = indice_planes;
        end

        function [planes_generados, indice] = genera_planes_bl_elimina_desplaza_paralelo(this, nro_iteracion, planes_originales, indice_planes_base, proyectos_al_comienzo)

            nivel_debug = this.pParOpt.NivelDebugParalelo;
            id_computo = this.IdComputo;
            cantidad_planes_generados = 0;
            planes_generados = cell(1,0);
            
            cantidad_bl_desplaza_proyectos = this.pParOpt.BLEliminaDesplazaProyectos;
            cantidad_planes = length(planes_originales)*cantidad_bl_desplaza_proyectos;
            cantidad_planes_originales = length(planes_originales);
            cantidad_etapas = this.pParOpt.CantidadEtapas;
            planes_validos = cell(cantidad_planes,1);
            puntos_operacion = this.pAdmSc.entrega_puntos_operacion();
            cantidad_puntos_operacion = length(puntos_operacion);
            
            optimiza_uso_memoria = this.pParOpt.OptimizaUsoMemoriaParalelo;
            if optimiza_uso_memoria
                CapacidadGeneradores = [];
                SerieGeneradoresERNC = [];
                SerieConsumos = [];
                sbase = 0;
            else
                CapacidadGeneradores = this.pAdmSc.entrega_capacidad_generadores();
                SerieGeneradoresERNC = this.pAdmSc.entrega_serie_generadores_ernc();
                SerieConsumos = this.pAdmSc.entrega_serie_consumos();
                sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            end
            
            cant_bl_desplaza_busqueda_fallida = this.pParOpt.BLEliminaDesplazaCantBusquedaFallida;
            cant_proy_a_comparar = this.pParOpt.BLEliminaDesplazaCantProyCompararBase;
            cant_proy_a_comparar_sin_mejora = this.pParOpt.BLEliminaDesplazaCantProyCompararSinMejora;
            considera_desplaza_despues_de_elimina = this.pParOpt.BLEliminaDesplazaNuevoDesplaza;
            considera_agrega_planes_eliminados = this.pParOpt.BLEliminaDesplazaNuevoAgrega;
            prioridad_adelanta_proyectos = this.pParOpt.PrioridadAdelantaProyectos;
            prioridad_desplaza_sobre_elimina = this.pParOpt.PrioridadDesplazaSobreElimina;
            considera_cambio_uprating = this.pParOpt.BLEliminaDesplazaCambioUprating;
            
            cantidad_workers = this.pParOpt.CantWorkers;
            procesos_fallidos = cell(cantidad_planes,1);
            parfor (nro_plan = 1:cantidad_planes, cantidad_workers)
if nivel_debug > 0 
    tic                
end
                if nivel_debug > 1
                    tiempos_computo_opf = [];
                    nombre_archivo = ['./output/debug/aco_id_', num2str(id_computo), '_hormiga_', num2str(nro_plan),'.dat'];
                    doc_id = fopen(nombre_archivo, 'a');
                    texto = ['Genera planes bl elimina desplaza en iteracion ' num2str(nro_iteracion) ' con hormiga ' num2str(nro_plan)];
                    fprintf(doc_id, strcat(texto, '\n'));
                end

                id_plan_orig = mod(nro_plan,cantidad_planes_originales);
                if id_plan_orig == 0
                    id_plan_orig = cantidad_planes_originales;
                end
                
                plan_orig = planes_originales(id_plan_orig);
                pPlan = cPlanExpansion(indice_planes_base + nro_plan);
                pPlan.inserta_iteracion(nro_iteracion);
                pPlan.inserta_busqueda_local(true);
                pPlan.inserta_plan_base(plan_orig.entrega_no());
                if proyectos_al_comienzo
                    plan_base_se_tiene_que_evaluar = true;
                    pPlan.inserta_estrategia_busqueda_local(42);
                    pPlan.inicializa_etapa(1);
                    pPlan.inserta_proyectos_etapa(1, plan_orig.entrega_proyectos());
                    for nro_etapa = 2:cantidad_etapas
                        pPlan.inicializa_etapa(nro_etapa);
                    end
                else
                    pPlan.inserta_estrategia_busqueda_local(41);
                    pPlan.Plan = plan_orig.Plan;
                    pPlan.inserta_estructura_costos(plan_orig.entrega_estructura_costos());                
                    pPlan.inserta_evaluacion(plan_orig.entrega_evaluacion());
                    plan_base_se_tiene_que_evaluar = false;
                end
                
                % crea sep actuales por cada etapa (para mejorar
                % performance del programa)
                
                sep_actuales = cell(cantidad_etapas,0);
                for nro_etapa = 1:cantidad_etapas
                    if nro_etapa == 1
                        sep_actuales{nro_etapa} = this.pSEP.crea_copia();
                    else
                        sep_actuales{nro_etapa} = sep_actuales{nro_etapa-1}.crea_copia();
                    end

                    for j = 1:length(pPlan.Plan(nro_etapa).Proyectos)
                        indice = pPlan.Plan(nro_etapa).Proyectos(j);
                        proyecto = this.pAdmProy.entrega_proyecto(indice);
                        if ~sep_actuales{nro_etapa}.agrega_proyecto(proyecto)
                            % Error (probablemente de programación). 
                            texto = ['Error de programacion. Plan ' num2str(pPlan.entrega_no()) ' no pudo ser implementado en SEP en etapa ' num2str(nro_etapa)];
                            error = MException('cOptACO:genera_planes_bl_elimina_desplaza_paralelo',texto);
                            throw(error)
                        end
                    end
                    
                    if ~optimiza_uso_memoria
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
                    end

                    if plan_base_se_tiene_que_evaluar
                        if optimiza_memoria
                            this.evalua_red(sep_actuales{nro_etapa}, nro_etapa, indice_proyectos, agrega_proyectos)
                        else
                            this.evalua_red_computo_paralelo(sep_actuales{nro_etapa}, nro_etapa, puntos_operacion, datos_escenario, sbase, [], true); %true indica que proyectos se agregan
                        end
                        this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa);
                        if ~sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion().ExisteResultado
                            texto_warning = ' 1 - No existe resultado en evaluacion. Entra a proceso';
                            warning(texto_warning);
                            
                            if isempty(procesos_fallidos{nro_plan})
                                procesos_fallidos{nro_plan} = pPlan.Plan;
                                id_fallido = 1;
                            else
                                procesos_fallidos{nro_plan} = [procesos_fallidos{nro_plan} pPlan.Plan];
                                id_fallido = length(procesos_fallidos{nro_plan});
                            end

                            nombre_proceso = ['./output/debug/dcopf_proc_fallido_id_' num2str(id_fallido) '_elim_despl_par_eval_inicial_plan_' num2str(pPlan.entrega_no()) '_etapa_' num2str(nro_etapa) '.dat'];
                            sep_actuales{nro_etapa}.entrega_opf().ingresa_nombres_problema();                            
                            sep_actuales{nro_etapa}.entrega_opf().imprime_problema_optimizacion(nombre_proceso);

                            nombre_proceso = ['./output/debug/dcopf_proc_fallido_id' num2str(id_fallido) '_elim_despl_par_eval_inicial_plan_' num2str(pPlan.entrega_no()) '_etapa_' num2str(nro_etapa) '_comparar.dat'];
                            plan_debug = cPlanExpansion(888888889);
                            plan_debug.Plan = pPlan.Plan;
                            plan_debug.inserta_sep_original(this.pSEP.crea_copia());
                            this.evalua_plan_computo_paralelo(plan_debug, nro_etapa, puntos_operacion, datos_escenario, sbase);
                            plan_debug.entrega_sep_actual().entrega_opf().ingresa_nombres_problema();
                            plan_debug.entrega_sep_actual().entrega_opf().imprime_problema_optimizacion(nombre_proceso);
                            texto_warning = ' 1 - No existe resultado en evaluacion. Sale de proceso';
                            warning(texto_warning);                            
                        end
                        valido = pPlan.es_valido(nro_etapa);
                        if ~valido
                            texto = ['Error de programacion. Plan original con proyectos en la etapa inicial no es valido en etapa' num2str(nro_etapa)];
                            error = MException('cOptACO:genera_planes_bl_elimina_desplaza_paralelo',texto);
                            throw(error)
                        end
                    else
                        pOPF = sep_actuales{nro_etapa}.entrega_opf();
                        if isempty(pOPF)
                            if strcmp(this.pParOpt.TipoFlujoPotencia, 'DC')
                                if optimiza_uso_memoria
                                    pOPF = cDCOPF(sep_actuales{nro_etapa}, this.pAdmSc, this.pParOpt);
                                    pOPF.inserta_nivel_debug(this.pParOpt.NivelDebugOPF);
                                    pOPF.inserta_etapa(nro_etapa);
                                    pOPF.inserta_resultados_en_sep(false);
                                else
                                    pOPF = cDCOPF(sep_actuales{nro_etapa});
                                    pOPF.copia_parametros_optimizacion(this.pParOpt);
                                    pOPF.inserta_puntos_operacion(puntos_operacion);
                                    pOPF.inserta_datos_escenario(datos_escenario);
                                    pOPF.inserta_etapa_datos_escenario(nro_etapa);
                                    pOPF.inserta_sbase(sbase);
                                    pOPF.inserta_resultados_en_sep(false);
                                end
                                pOPF.formula_problema_despacho_economico();
                            else
                                error = MException('cOptMCMC:genera_planes_bl_elimina_desplaza_paralelo','solo flujo DC implementado');
                                throw(error)
                            end
                        else
                            if optimiza_uso_memoria
                                if pOPF.entrega_etapa() ~= nro_etapa
                                    pOPF.actualiza_etapa(nro_etapa);
                                end
                            else                            
                                if pOPF.entrega_etapa_datos_escenario() ~= nro_etapa
                                    pOPF.inserta_puntos_operacion(puntos_operacion);
                                    pOPF.inserta_datos_escenario(datos_escenario);
                                    pOPF.inserta_etapa_datos_escenario(nro_etapa);
                                    pOPF.actualiza_etapa(nro_etapa);
                                end
                            end
                        end
                    end
                end
                if plan_base_se_tiene_que_evaluar
                    this.calcula_costos_totales(pPlan);
                end
                
                if nivel_debug > 1
                    texto = ['Busqueda local elimina desplaza plan ' num2str(nro_plan)];
                    fprintf(doc_id, strcat(texto, '\n'));
                    texto = 'Se imprime plan base para busqueda local';
                    fprintf(doc_id, strcat(texto, '\n'));
                    pPlan.agrega_nombre_proyectos(this.pAdmProy);
                    texto = pPlan.entrega_texto_plan_expansion();
                    fprintf(doc_id, strcat(texto, '\n'));
                    totex_orig = pPlan.entrega_totex_total();
                    cantidad_proy_orig = pPlan.cantidad_acumulada_proyectos();
                end      
                
                pPlan.Valido = true;
                % Primero se eliminan proyectos que no se
                % necesitan. Estos se identifican en la etapa final
                if nivel_debug > 1
                    texto = ['Elimina proyectos innecesarios en busqueda local elimina desplaza proyectos plan ' num2str(nro_plan) '/' num2str(cantidad_planes)];
                    fprintf(doc_id, strcat(texto, '\n'));
                end
                    
                proyectos_restringidos_para_eliminar = [];
                proyectos_eliminados = [];
                if nivel_debug > 1
                    proyectos_desplazados = [];
                    etapas_desplazados = [];
                    estructura_costos_plan_base = pPlan.entrega_estructura_costos();
                end
                
                evaluacion_actual = pPlan.entrega_evaluacion();
                estructura_costos_actual = pPlan.entrega_estructura_costos();
                plan_actual = pPlan.Plan;
                cant_busqueda_fallida = 0;
                proy_potenciales_eliminar = [];
                proy_potenciales_adelantar = [];
                if nivel_debug > 1
                    cantidad_intentos_totales = 0;
                end
                
                while cant_busqueda_fallida < cant_bl_desplaza_busqueda_fallida
                    if nivel_debug > 1
                        cantidad_intentos_totales = cantidad_intentos_totales + 1;
                        texto = ['Intento total: ' num2str(cantidad_intentos_totales)];
                        fprintf(doc_id, strcat(texto, '\n'));
                        cantidad_proy_actuales = pPlan.cantidad_acumulada_proyectos()
                        texto = ['Cant. total proyectos en plan: ' num2str(cantidad_proy_actuales)];
                        fprintf(doc_id, strcat(texto, '\n'));
                    end
                    
                	intento_paralelo_actual = 0;
                    intentos_actuales = cell(cant_proy_a_comparar,0);
                    proyectos_restringidos_para_eliminar_intento = proyectos_restringidos_para_eliminar;
                    fuerza_continuar_comparacion = false;
                    cantidad_mejores_intentos_completo = 0;
                    while intento_paralelo_actual < cant_proy_a_comparar || fuerza_continuar_comparacion
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
                            proy_seleccionados = this.selecciona_proyectos_a_eliminar_y_desplazar(pPlan, cantidad_etapas, proyectos_restringidos_para_eliminar_intento, proy_potenciales_evaluar(intento_paralelo_actual));
                        else
                            proy_seleccionados = this.selecciona_proyectos_a_eliminar_y_desplazar(pPlan, cantidad_etapas, proyectos_restringidos_para_eliminar_intento);
                        end
                        
                        if isempty(proy_seleccionados.seleccionado)
                            intentos_actuales{intento_paralelo_actual}.Valido = false;
                            intentos_actuales{intento_paralelo_actual}.proy_seleccionados.seleccionado = [];

                            if intento_paralelo_actual >= cant_proy_a_comparar_sin_mejora
                                fuerza_continuar_comparacion = false;
                            end

                            continue;
                        end

                        intentos_actuales{intento_paralelo_actual}.proy_seleccionados = proy_seleccionados;
                        intentos_actuales{intento_paralelo_actual}.Totex = 999999999999999999999;
                        intentos_actuales{intento_paralelo_actual}.Valido = false;
                        intentos_actuales{intento_paralelo_actual}.Plan = [];
                        intentos_actuales{intento_paralelo_actual}.SinMejoraIntermedia = false;
                        intentos_actuales{intento_paralelo_actual}.AdelantaProyectos = false;
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
                        intentos_actuales{intento_paralelo_actual}.DesdeEtapaIntento = desde_etapa;
                        existe_mejora = false;
                        plan_actual_hasta_etapa = desde_etapa - 1;
                        plan_actual_intento_hasta_etapa = desde_etapa - 1;
                        proyectos_eliminar = [proy_seleccionados.conectividad_eliminar proy_seleccionados.seleccionado];
                        etapas_eliminar = [proy_seleccionados.etapas_conectividad_eliminar proy_seleccionados.etapa_seleccionado];
                        proyectos_desplazar = proy_seleccionados.conectividad_desplazar;
                        etapas_originales_desplazar = proy_seleccionados.etapas_orig_conectividad_desplazar;
                        etapas_desplazar = proy_seleccionados.etapas_fin_conectividad_desplazar;                 
                        for nro_etapa = desde_etapa:cantidad_etapas
                            % desplaza proyectos a eliminar 
                            for k = length(proyectos_eliminar):-1:1
                                if etapas_eliminar(k) <= nro_etapa
                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_eliminar(k));
                                    sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    if nro_etapa < cantidad_etapas
                                        pPlan.desplaza_proyectos(proyectos_eliminar(k), nro_etapa, nro_etapa + 1);
                                    else
                                        pPlan.elimina_proyectos(proyectos_eliminar(k), nro_etapa);
                                    end
                                end
                            end
                            %desplaza proyectos
                            for k = length(proyectos_desplazar):-1:1
                                if nro_etapa >= etapas_originales_desplazar(k) && nro_etapa < etapas_desplazar(k) 
                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_desplazar(k));
                                    sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    pPlan.desplaza_proyectos(proyectos_desplazar(k), nro_etapa, nro_etapa + 1);
                                end
                            end
                            if nivel_debug > 1
                                tinic_debug = toc;
                            end
                            sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                            this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa);
                            this.calcula_costos_totales(pPlan);

                            if nivel_debug > 1
                                tiempos_computo_opf(end+1) = toc-tinic_debug;
                            end
                            
                            ultima_etapa_evaluada = nro_etapa;

                            if ~sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion().ExisteResultado
                                texto_warning = ' 2 - No existe resultado en evaluacion. Entra a proceso';
                                warning(texto_warning);
                                
                                if isempty(procesos_fallidos{nro_plan})
                                    procesos_fallidos{nro_plan} = pPlan.Plan;
                                    id_fallido = 1;
                                else
                                    procesos_fallidos{nro_plan} = [procesos_fallidos{nro_plan} pPlan.Plan];
                                    id_fallido = length(procesos_fallidos{nro_plan});
                                end

                                nombre_proceso = ['./output/debug/dcopf_proc_fallido_id_' num2str(id_fallido) '_elim_despl_par_proy_eliminar_plan' num2str(pPlan.entrega_no()) '_etapa_' num2str(nro_etapa) '.dat'];
                                sep_actuales{nro_etapa}.entrega_opf().ingresa_nombres_problema();                            
                                sep_actuales{nro_etapa}.entrega_opf().imprime_problema_optimizacion(nombre_proceso);

                                datos_escenario_debug = [];
                                datos_escenario_debug.CapacidadGeneradores = CapacidadGeneradores(:,nro_etapa);
                                indice_1 = 1 + (nro_etapa - 1)*cantidad_puntos_operacion;
                                indice_2 = nro_etapa*cantidad_puntos_operacion;
                                if ~isempty(SerieGeneradoresERNC)
                                    datos_escenario_debug.SerieGeneradoresERNC = SerieGeneradoresERNC(:,indice_1:indice_2);
                                else
                                    datos_escenario_debug.SerieGeneradoresERNC = [];
                                end
                                datos_escenario_debug.SerieConsumos = SerieConsumos(:,indice_1:indice_2);
                                
                                nombre_proceso = ['./output/debug/dcopf_proc_fallido_id' num2str(id_fallido) '_elim_despl_par_proy_eliminar_plan_' num2str(pPlan.entrega_no()) '_etapa_' num2str(nro_etapa) '_comparar.dat'];
                                plan_debug = cPlanExpansion(888888889);
                                plan_debug.Plan = pPlan.Plan;
                                plan_debug.inserta_sep_original(this.pSEP.crea_copia());
                                this.evalua_plan_computo_paralelo(plan_debug, nro_etapa, puntos_operacion, datos_escenario_debug, sbase);
                                plan_debug.entrega_sep_actual().entrega_opf().ingresa_nombres_problema();
                                plan_debug.entrega_sep_actual().entrega_opf().imprime_problema_optimizacion(nombre_proceso);

                                texto_warning = ' 2 - No existe resultado en evaluacion. Sale de proceso';
                                warning(texto_warning);
                            end
                            
                            if pPlan.es_valido(nro_etapa) && pPlan.entrega_totex_total() < estructura_costos_actual_intento.TotexTotal
                                % cambio intermedio produce mejora. Se
                                % acepta y se guarda
                                plan_actual_intento = pPlan.Plan;
                                estructura_costos_actual_intento = pPlan.entrega_estructura_costos();
                                evaluacion_actual_intento = pPlan.entrega_evaluacion();
                                existe_mejora = true;
                                plan_actual_intento_hasta_etapa = nro_etapa;

                                if nivel_debug > 1
                                    if nro_etapa < this.pParOpt.CantidadEtapas
                                        texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' genera mejora. Totex actual etapa: ' num2str(pPlan.entrega_totex_total())];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    else
                                        texto = ['      Desplazamiento en etapa final genera mejora. Proyectos se eliminan definitivamente. Totex final etapa: ' num2str(pPlan.entrega_totex_total())];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                end
                            elseif ~pPlan.es_valido(nro_etapa)
                                intentos_actuales{intento_paralelo_actual}.SinMejoraIntermedia = true;
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
                                if prioridad_desplaza_sobre_elimina && existe_mejora
                                    break
                                end
                                intentos_actuales{intento_paralelo_actual}.SinMejoraIntermedia = true;
                                if nro_etapa < cantidad_etapas
                                    
                                    delta_cinv = this.calcula_delta_cinv_elimina_desplaza_proyectos(pPlan, nro_etapa+1, proyectos_eliminar, proyectos_desplazar, etapas_originales_desplazar, etapas_desplazar);
                                    existe_potencial = (pPlan.entrega_totex_total() - delta_cinv) < estructura_costos_actual_intento.TotexTotal;
                                    if nivel_debug > 1
                                        texto = ['      Desplazamiento de etapa ' num2str(nro_etapa) ' a ' num2str(nro_etapa + 1) ' no genera mejora. ' ...
                                                 'Totex actual etapa: ' num2str(pPlan.entrega_totex_total()) ...
                                                 '. Delta Cinv potencial: ' num2str(delta_cinv) ...
                                                 '. Totex potencial: ' num2str(pPlan.entrega_totex_total() - delta_cinv)];
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
                                        texto = ['      Desplazamiento en etapa final no genera mejora. Totex actual etapa: ' num2str(pPlan.entrega_totex_total())];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                end                                
                            end
                        end

%debug
% plan_debug = cPlanExpansion(888888889);
% plan_debug.Plan = pPlan.Plan;
% plan_debug.inserta_sep_original(this.pSEP);
% for etapa_ii = 1:this.pParOpt.CantidadEtapas
% 	valido = this.evalua_plan(plan_debug, etapa_ii, 0);
%     if ~valido
%     	error = MException('cOptACO:genera_planes_bl_elimina_desplaza',...
%         ['Error. Plan debug no es valido en etapa ' num2str(etapa_ii)]);
%         throw(error)
%     end
% end
% this.calcula_costos_totales(plan_debug);
% if round(plan_debug.entrega_totex_total(),2) ~= round(pPlan.entrega_totex_total(),2)
%     texto = 'Totex total de plan debug es distinto de totex total de plan actual!';
%     prot.imprime_texto(texto);
%     texto = ['Totex total plan debug: ' num2str(round(plan_debug.entrega_totex_total(),3))];
%     prot.imprime_texto(texto);
%     texto = ['Totex total plan actual: ' num2str(round(pPlan.entrega_totex_total(),3))];
%     prot.imprime_texto(texto);
%     
% 	error = MException('cOptACO:genera_planes_bl_elimina_desplaza','Totex total de plan debug es distinto de totex total de plan actual!');
%     throw(error)
% end
                        % se evaluaron todas las etapas. Determina el
                        % estado final del plan y agrega proyectos ya
                        % evaluados para futuros intentos
                        proyectos_restringidos_para_eliminar_intento = [proyectos_restringidos_para_eliminar_intento proy_seleccionados.seleccionado];
                        mejor_totex_elimina_desplaza = inf;

                        if existe_mejora
                            intentos_actuales{intento_paralelo_actual}.Plan = plan_actual_intento;
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
                        pPlan.Plan = plan_actual;
                        pPlan.inserta_estructura_costos(estructura_costos_actual);
                        pPlan.inserta_evaluacion(evaluacion_actual);

                        for nro_etapa = plan_actual_hasta_etapa + 1:ultima_etapa_evaluada
                            % deshace los cambios hechos en los sep
                            % actuales hasta la etapa correcta
                            % Ojo! orden inverso entre desplaza y
                            % elimina proyectos!
                            for k = 1:length(proyectos_desplazar)
                                if nro_etapa >= etapas_originales_desplazar(k) && nro_etapa < etapas_desplazar(k) 
                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_desplazar(k));
                                    sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                end
                            end

                            for k = 1:length(proyectos_eliminar)
                                if etapas_eliminar(k) <= nro_etapa
                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_eliminar(k));
                                    sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                end
                            end
                        end
                        
                        if desde_etapa > 1 && ~proy_actual_es_potencial_elimina
                            % verifica si adelantar el proyecto produce
                            % mejora
                            % determina primera etapa potencial a
                            % adelantar y proyectos de conectividad

                            if this.iNivelDebug > 1
                                texto = '      Se verifica si adelantar proyectos produce mejora';
                                fprintf(doc_id, strcat(texto, '\n'));
                            end

                            proy_adelantar = this.selecciona_proyectos_a_adelantar(pPlan, desde_etapa, proy_seleccionados.seleccionado);
                            % proy_adelantar.seleccionado
                            % proy_adelantar.etapa_seleccionado
                            % proy_adelantar.seleccion_directa
                            % proy_adelantar.primera_etapa_posible = [];
                            % proy_adelantar.proy_conect_adelantar = [];
                            % proy_adelantar.etapas_orig_conect = [];

                            nro_etapa = desde_etapa;
                            flag_salida = false;
                            existe_resultado_adelanta = false;
                            max_cant_intentos_fallidos_adelanta = this.pParOpt.CantidadIntentosFallidosAdelanta;
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
                                        sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                        pPlan.adelanta_proyectos(proy_adelantar.proy_conect_adelantar(k), nro_etapa + 1, nro_etapa);
                                    end
                                end
                                proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.seleccionado);
                                sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                pPlan.adelanta_proyectos(proy_adelantar.seleccionado, nro_etapa + 1, nro_etapa);

                                %evalua red (proyectos ya se ingresaron
                                %al sep)
                                if nivel_debug > 1
                                    tinic_debug = toc;
                                end
                                sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa);
                                this.calcula_costos_totales(pPlan);

                                if nivel_debug > 1
                                    tiempos_computo_opf(end+1) = toc-tinic_debug;
                                end

                                ultima_etapa_evaluada = nro_etapa;

                                if cant_intentos_adelanta == 1
                                    delta_actual_adelanta = pPlan.entrega_totex_total()-ultimo_totex_adelanta;
                                else
                                    delta_nuevo_adelanta = pPlan.entrega_totex_total()-ultimo_totex_adelanta;
                                    if delta_nuevo_adelanta > 0 && delta_nuevo_adelanta > delta_actual_adelanta
                                        cant_intentos_fallidos_adelanta = cant_intentos_fallidos_adelanta + 1;
                                    else
                                        if delta_nuevo_adelanta < 0
                                            cant_intentos_fallidos_adelanta = 0;
                                        end
                                    end
                                    delta_actual_adelanta = delta_nuevo_adelanta;
                                end
                                ultimo_totex_adelanta = pPlan.entrega_totex_total();
                                
                                if ~sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion().ExisteResultado
                                    if isempty(procesos_fallidos{nro_plan})
                                        procesos_fallidos{nro_plan} = pPlan.Plan;
                                        id_fallido = 1;
                                    else
                                        procesos_fallidos{nro_plan} = [procesos_fallidos{nro_plan} pPlan.Plan];
                                        id_fallido = length(procesos_fallidos{nro_plan});
                                    end

                                    nombre_proceso = ['./output/debug/dcopf_proc_fallido_id_' num2str(id_fallido) '_elim_despl_par_eliminar_adelanta_plan' num2str(pPlan.entrega_no()) '_etapa_' num2str(nro_etapa) '.dat'];
                                    sep_actuales{nro_etapa}.entrega_opf().ingresa_nombres_problema();                            
                                    sep_actuales{nro_etapa}.entrega_opf().imprime_problema_optimizacion(nombre_proceso);

                                    nombre_proceso = ['./output/debug/dcopf_proc_fallido_id' num2str(id_fallido) '_elim_despl_par_eliminar_adelanta_plan_' num2str(pPlan.entrega_no()) '_etapa_' num2str(nro_etapa) '_comparar.dat'];
                                    plan_debug = cPlanExpansion(888888889);
                                    plan_debug.Plan = pPlan.Plan;
                                    plan_debug.inserta_sep_original(this.pSEP.crea_copia());
                                    this.evalua_plan_computo_paralelo(plan_debug, nro_etapa, puntos_operacion, datos_escenario_debug, sbase);
                                    plan_debug.entrega_sep_actual().entrega_opf().ingresa_nombres_problema();
                                    plan_debug.entrega_sep_actual().entrega_opf().imprime_problema_optimizacion(nombre_proceso);
                                end
                                
                                if ~existe_resultado_adelanta
                                    % resultado se compara con
                                    % estructura de costos actuales
                                    if pPlan.entrega_totex_total() < estructura_costos_actual.TotexTotal
                                        % adelantar el proyecto produce
                                        % mejora. Se guarda resultado
                                        existe_resultado_adelanta = true;
                                        existe_mejora_parcial = true;
                                        plan_actual_intento_adelanta = pPlan.Plan;
                                        estructura_costos_actual_intento_adelanta = pPlan.entrega_estructura_costos();
                                        evaluacion_actual_intento_adelanta = pPlan.entrega_evaluacion();
                                        plan_actual_intento_adelanta_hasta_etapa = nro_etapa;
                                        if nivel_debug > 1
                                            texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ' genera mejora parcial. Totex actual etapa: ' num2str(pPlan.entrega_totex_total())];
                                            fprintf(doc_id, strcat(texto, '\n'));
                                        end
                                    else
                                        if nivel_debug > 1                                        
                                            texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ' no genera mejora. Totex actual etapa: ' num2str(pPlan.entrega_totex_total())];
                                            fprintf(doc_id, strcat(texto, '\n'));
                                        end                                            
                                    end
                                else
                                    % resultado se compara con último
                                    % resultado
                                    if pPlan.entrega_totex_total() < estructura_costos_actual_intento_adelanta.TotexTotal
                                        % adelantar el proyecto produce
                                        % mejora. Se guarda resultado
                                        existe_mejora_parcial = true;
                                        plan_actual_intento_adelanta = pPlan.Plan;
                                        estructura_costos_actual_intento_adelanta = pPlan.entrega_estructura_costos();
                                        evaluacion_actual_intento_adelanta = pPlan.entrega_evaluacion();
                                        plan_actual_intento_adelanta_hasta_etapa = nro_etapa;
                                        if nivel_debug > 1                                        
                                            texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ' genera mejora parcial. Totex actual etapa: ' num2str(pPlan.entrega_totex_total())];
                                            fprintf(doc_id, strcat(texto, '\n'));
                                        end
                                    else
                                        if nivel_debug > 1                                        
                                            texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ' no genera mejora. Totex actual etapa: ' num2str(pPlan.entrega_totex_total())];
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
                                        prioridad_adelanta_proyectos

                                        if estructura_costos_actual_intento_adelanta.TotexTotal > mejor_totex_elimina_desplaza
                                            intentos_actuales{intento_paralelo_actual}.AdelantaProyectosForzado = true;
                                        else
                                            intentos_actuales{intento_paralelo_actual}.AdelantaProyectosForzado = false;                                                
                                        end
                                        % se acepta el cambio
                                        intentos_actuales{intento_paralelo_actual}.Plan = plan_actual_intento_adelanta;
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
                            pPlan.Plan = plan_actual;
                            pPlan.inserta_estructura_costos(estructura_costos_actual);
                            pPlan.inserta_evaluacion(evaluacion_actual);

                            for nro_etapa = ultima_etapa_evaluada:desde_etapa-1
                                % deshace los cambios hechos en los sep
                                % actuales hasta la etapa correcta
                                % Ojo! orden inverso entre desplaza y
                                % elimina proyectos!
                                proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.seleccionado);
                                sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                for k = length(proy_adelantar.proy_conect_adelantar):-1:1
                                    if nro_etapa < proy_adelantar.etapas_orig_conect(k) 
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.proy_conect_adelantar(k));
                                        sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    end
                                end
                            end
                        end
                        
                        % se verifica si hay que seguir comparando
                        if fuerza_continuar_comparacion == false && ...
                           intento_paralelo_actual == cant_proy_a_comparar && ...
                           cantidad_mejores_intentos_completo < cant_proy_a_comparar && ...
                           cant_proy_a_comparar_sin_mejora > cant_proy_a_comparar

                            fuerza_continuar_comparacion = true;
                        elseif fuerza_continuar_comparacion == true && intento_paralelo_actual == cant_proy_a_comparar_sin_mejora
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
                                elseif this.pParOpt.PrioridadDesplazaSobreElimina && ...
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
                                            if ~this.pParOpt.PrioridadDesplazaSobreElimina
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
                                            if ~this.pParOpt.PrioridadDesplazaSobreElimina
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
                                    if intentos_actuales{id_mejor_plan_intento}.PlanActualHastaEtapa == this.pParOpt.CantidadEtapas
                                        texto_adicional = num2str(intento_actual_sin_mejora_intermedia);
                                    else
                                        texto_adicional = 'D';
                                    end
                                    proyectos_eliminar = [intentos_actuales{kk}.proy_seleccionados.conectividad_eliminar intentos_actuales{kk}.proy_seleccionados.seleccionado];
                                    texto = ['      Intento ' num2str(kk) ' es valido. Sin mejora intermedia: ' texto_adicional ...
                                             '. Totex intento: ' num2str(intentos_actuales{kk}.Totex) '. Proyectos eliminar: '];
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
                        if nivel_debug > 1
                            texto = ['      Mejor intento: ' num2str(id_mejor_plan_intento)];
                            fprintf(doc_id, strcat(texto, '\n'));
                        end
                        
                        plan_actual = intentos_actuales{id_mejor_plan_intento}.Plan;
                        evaluacion_actual = intentos_actuales{id_mejor_plan_intento}.evaluacion_actual;
                        estructura_costos_actual = intentos_actuales{id_mejor_plan_intento}.estructura_costos_actual;
                        pPlan.Plan = plan_actual;
                        pPlan.inserta_estructura_costos(estructura_costos_actual);
                        pPlan.inserta_evaluacion(evaluacion_actual);

                        proy_potenciales_eliminar(proy_potenciales_eliminar == intentos_actuales{id_mejor_plan_intento}.proy_seleccionados.seleccionado) = [];
                        proy_potenciales_adelantar(proy_potenciales_adelantar == intentos_actuales{id_mejor_plan_intento}.proy_seleccionados.seleccionado) = [];

                        % se implementa plan hasta la etapa actual del
                        % mejor intento
                        desde_etapa = intentos_actuales{id_mejor_plan_intento}.DesdeEtapaIntento;
                        ultima_etapa_valida_intento = intentos_actuales{id_mejor_plan_intento}.PlanActualHastaEtapa;
                        
                        if intentos_actuales{id_mejor_plan_intento}.AdelantaProyectos
                            proy_adelantar = intentos_actuales{id_mejor_plan_intento}.proy_seleccionados;
                            if ~intentos_actuales{id_mejor_plan_intento}.AdelantaProyectosForzado
                                proyectos_restringidos_para_eliminar = [proyectos_restringidos_para_eliminar proy_adelantar.seleccionado];
                            end
                            for nro_etapa = ultima_etapa_valida_intento:desde_etapa-1
                                % agrega proyectos en sep actual en
                                % etapa actual
                                for k = 1:length(proy_adelantar.proy_conect_adelantar)
                                    if nro_etapa < proy_adelantar.etapas_orig_conect(k) 
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.proy_conect_adelantar(k));
                                        sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    end
                                end
                                proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.seleccionado);
                                sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            end
                        else
                            proy_seleccionados = intentos_actuales{id_mejor_plan_intento}.proy_seleccionados;
                            proyectos_eliminar = [proy_seleccionados.conectividad_eliminar proy_seleccionados.seleccionado];
                            etapas_eliminar = [proy_seleccionados.etapas_conectividad_eliminar proy_seleccionados.etapa_seleccionado];
                            proyectos_desplazar = proy_seleccionados.conectividad_desplazar;
                            etapas_originales_desplazar = proy_seleccionados.etapas_orig_conectividad_desplazar;
                            etapas_desplazar = proy_seleccionados.etapas_fin_conectividad_desplazar;

                            % elimina de lista todos los otros proyectos.
                            % Ocurre a veces que trafo paralelo es
                            % eliminado como proyecto de conectividad
                            proy_potenciales_eliminar(ismember(proy_potenciales_eliminar, proy_seleccionados.conectividad_eliminar)) = [];
                            proy_potenciales_adelantar(ismember(proy_potenciales_adelantar, proy_seleccionados.conectividad_eliminar)) = [];
                            
                            for nro_etapa = desde_etapa:ultima_etapa_valida_intento
                                % desplaza proyectos a eliminar 
                                for k = length(proyectos_eliminar):-1:1
                                    if etapas_eliminar(k) <= nro_etapa
                                        proyecto = this.pAdmProy.entrega_proyecto(proyectos_eliminar(k));
                                        sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    end
                                end
                                %desplaza proyectos
                                for k = length(proyectos_desplazar):-1:1
                                    if nro_etapa >= etapas_originales_desplazar(k) && nro_etapa < etapas_desplazar(k) 
                                        proyecto = this.pAdmProy.entrega_proyecto(proyectos_desplazar(k));
                                        sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    end
                                end
                            end

                            if ultima_etapa_valida_intento == cantidad_etapas
                                % quiere decir que proyectos se eliminaron
                                % definitivamente
                                proyectos_eliminados = [proyectos_eliminados proyectos_eliminar];
                            else
                                % quiere decir que proyecto no fue
                                % eliminado completamente, pero sí
                                % desplazado
                                % se agrega proyectos_eliminar a proyectos
                                % restringidos para eliminar, ya que ya fue
                                % desplazado. A menos que haza sido
                                % forzado...
                                if ~intentos_actuales{id_mejor_plan_intento}.DesplazaProyectosForzado
                                    proyectos_restringidos_para_eliminar = [proyectos_restringidos_para_eliminar proy_seleccionados.seleccionado];
                                end
                                if nivel_debug > 1
                                    proyectos_desplazados = [proyectos_desplazados proyectos_eliminar];
                                    etapas_desplazados = [etapas_desplazados (ultima_etapa_valida_intento+1)*ones(1,length(proyectos_eliminar))];
                                end
                            end
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
                        end

                        if nivel_debug > 1
                            texto = 'Imprime plan actual despues de los intentos';
                            fprintf(doc_id, strcat(texto, '\n'));
                            pPlan.agrega_nombre_proyectos(this.pAdmProy);
                            texto = pPlan.entrega_texto_plan_expansion();
                            fprintf(doc_id, strcat(texto, '\n'));
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
                end
                        
                if nivel_debug > 1
                    totex_despues_de_elimina = pPlan.entrega_totex_total();
                    cantidad_proy_despues_de_elimina = pPlan.cantidad_acumulada_proyectos();

                    fprintf(doc_id, strcat('Fin elimina proyectos', '\n'));
                    texto = sprintf('%-15s %-10s %-10s', ' ', 'No proy', 'Totex');
                    fprintf(doc_id, strcat(texto, '\n'));
                    texto = sprintf('%-15s %-10s %-10s', 'Original', num2str(cantidad_proy_orig), num2str(totex_orig));
                    fprintf(doc_id, strcat(texto, '\n'));
                    texto = sprintf('%-15s %-10s %-10s', 'Elimina', num2str(cantidad_proy_despues_de_elimina), num2str(totex_despues_de_elimina));
                    fprintf(doc_id, strcat(texto, '\n'));


                    texto_eliminados = '';
                    texto_desplazados = '';
                    for ii = 1:length(proyectos_eliminados)
                        texto_eliminados = [texto_eliminados ' ' num2str(proyectos_eliminados(ii))];
                    end

%                     if length(proyectos_desplazados) ~= length(etapas_desplazados)
%                         texto = 'Error. Dimensiones de proyectos desplazados no coincide con etapas desplazados';
%                         fprintf(doc_id, strcat(texto, '\n'));
%                         texto = ['Dimension proyectos desplazados:' length(proyectos_desplazados)];
%                         fprintf(doc_id, strcat(texto, '\n'));
%                         texto = ['Dimension etapas desplazados:' length(etapas_desplazados)];
%                         fprintf(doc_id, strcat(texto, '\n'));
%                         
%                         error = MException('cOptACO:genera_planes_bl_elimina_desplaza_paralelo',...
%                         'Error. Dimensiones de proyectos desplazados no coincide con etapas desplazados');
%                         throw(error)
%                     end
                    
                    for ii = 1:length(proyectos_desplazados)
                        texto_desplazados = [texto_desplazados ' Pr. ' num2str(proyectos_desplazados(ii)) ' hasta etapa ' num2str(etapas_desplazados(ii)) ';'];
                    end
                    texto = ['Proyectos eliminados (' num2str(length(proyectos_eliminados)) '): ' texto_eliminados];
                    fprintf(doc_id, strcat(texto, '\n'));

                    texto = ['Proyectos desplazados (' num2str(length(proyectos_desplazados)) '): ' texto_desplazados];
                    fprintf(doc_id, strcat(texto, '\n'));

                    texto = 'Plan actual despues de elimina proyectos';
                    fprintf(doc_id, strcat(texto, '\n'));
                    pPlan.agrega_nombre_proyectos(this.pAdmProy);
                    texto = pPlan.entrega_texto_plan_expansion();
                    fprintf(doc_id, strcat(texto, '\n'));
                end

                if considera_cambio_uprating && pPlan.cantidad_acumulada_proyectos() ~= 0
%disp('comienzo ur')
                    if nivel_debug > 1
                        fprintf(doc_id, strcat('\nComienzo BL Cambio Uprating', '\n'));
                    end

                    evaluacion_plan_base = pPlan.entrega_evaluacion();
                    estructura_costos_plan_base = pPlan.entrega_estructura_costos();
                    plan_base = pPlan.Plan;

                    proyectos_restringidos_para_eliminar = [];

                    % los siguientes contenedores son sólo para fines
                    % informativos (debug)
                    proyectos_eliminados = [];
                    etapas_eliminados = [];
                    proyectos_agregados = [];
                    etapas_agregados = [];
                    conectividad_desplazar = [];
                    etapas_orig_conectividad_desplazar = [];
                    etapas_fin_conectividad_desplazar = [];

                    cant_busqueda_fallida = 0;
                    intento_total = 0;
                    while cant_busqueda_fallida < this.pParOpt.BLEliminaDesplazaCantBusquedaFallida
                        intento_paralelo_actual = 0;
                        intento_total = intento_total + 1;
                        evaluacion_actual = pPlan.entrega_evaluacion();
                        estructura_costos_actual = pPlan.entrega_estructura_costos();
                        plan_actual = pPlan.Plan;
                        existe_mejor_intento = false;
                        id_mejor_intento = 0;
                        proy_seleccionados = this.selecciona_proyectos_a_intercambiar(pPlan, proyectos_restringidos_para_eliminar);
                        % proy_seleccionados.corredor = 0;
                        % proy_seleccionados.ubicacion = 0; %Trafo VU
                        % proy_seleccionados.estado_eliminar = 0;
                        % proy_seleccionados.cant_estados = 0;
                        % proy_seleccionados.eliminar = [];
                        % proy_seleccionados.etapa_eliminar = [];
                        % proy_seleccionados.conectividad_desplazar = [];
                        % proy_seleccionados.etapas_orig_conectividad_desplazar = [];
                        % proy_seleccionados.etapas_fin_conectividad_desplazar = [];
                        % proy_seleccionados.trafos_paralelos_potenciales_a_eliminar = [];
                        % proy_seleccionados.etapas_trafos_paralelos_potenciales_a_eliminar = [];
                        % proy_seleccionados.agregar = [];

                        % elimina proyectos a eliminar del sep
                        proyectos_eliminar = proy_seleccionados.eliminar;

                        % agrega proyectos seleccionados eliminar a
                        % grupo de proy. restringidos
                        proyectos_restringidos_para_eliminar = [proyectos_restringidos_para_eliminar proyectos_eliminar];

                        etapas_eliminar = proy_seleccionados.etapa_eliminar;
                        proyectos_desplazar = proy_seleccionados.conectividad_desplazar;
                        etapas_originales_desplazar = proy_seleccionados.etapas_orig_conectividad_desplazar;
                        etapas_desplazar = proy_seleccionados.etapas_fin_conectividad_desplazar;
                        trafos_paral_eliminados = proy_seleccionados.trafos_paralelos_potenciales_a_eliminar;
                        etapas_trafos_paral_eliminados = proy_seleccionados.etapas_trafos_paralelos_potenciales_a_eliminar;

                        if nivel_debug > 1
                            texto = ['Intento total ' num2str(intento_total) '. Cant. fallida ' num2str(cant_busqueda_fallida) '/' num2str(this.pParOpt.BLEliminaDesplazaCantBusquedaFallida)];
                            fprintf(doc_id, strcat(texto, '\n'));
                            texto = ['Proy. seleccionados eliminar : ' num2str(proyectos_eliminar)];
                            fprintf(doc_id, strcat(texto, '\n'));
                            texto = ['Etapas Proy. selec. eliminar : ' num2str(etapas_eliminar)];
                            fprintf(doc_id, strcat(texto, '\n'));
                            texto = ['Proy. seleccionados desplazar: ' num2str(proyectos_desplazar)];
                            fprintf(doc_id, strcat(texto, '\n'));
                            texto = ['Etapas orig proyec. desplazar: ' num2str(etapas_originales_desplazar)];
                            fprintf(doc_id, strcat(texto, '\n'));
                            texto = ['Etapas fin proyect. desplazar: ' num2str(etapas_desplazar)];
                            fprintf(doc_id, strcat(texto, '\n'));
                            texto = ['Trafos potenciales a eliminar: ' num2str(trafos_paral_eliminados)];
                            fprintf(doc_id, strcat(texto, '\n'));
                            texto = ['Etapas trafos pot. a eliminar: ' num2str(etapas_trafos_paral_eliminados)];
                            fprintf(doc_id, strcat(texto, '\n'));
                            texto = ['Proy. restringidos a eliminar: ' num2str(proyectos_restringidos_para_eliminar)];
                            fprintf(doc_id, strcat(texto, '\n'));
                        end

                        % elimina trafos potenciales a eliminar
                        %desplaza proyectos
                        for k = length(trafos_paral_eliminados):-1:1
                            desde_etapa = etapas_trafos_paral_eliminados(k);
                            for nro_etapa = desde_etapa:this.pParOpt.CantidadEtapas
                                proyecto = this.pAdmProy.entrega_proyecto(trafos_paral_eliminados(k));
                                sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                            end
                            pPlan.elimina_proyectos(trafos_paral_eliminados(k), desde_etapa);
                        end

                        %desplaza proyectos
                        for k = length(proyectos_desplazar):-1:1
                            desde_etapa = etapas_originales_desplazar(k);
                            hasta_etapa = etapas_desplazar(k);
                            for nro_etapa = desde_etapa:hasta_etapa-1
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_desplazar(k));
                                sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                            end
                            pPlan.desplaza_proyectos(proyectos_desplazar(k), desde_etapa, hasta_etapa);
                        end

                        for k = length(proyectos_eliminar):-1:1
                            desde_etapa = etapas_eliminar(k);
                            for nro_etapa = desde_etapa:this.pParOpt.CantidadEtapas
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_eliminar(k));
                                sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                            end
                            pPlan.elimina_proyectos(proyectos_eliminar(k), desde_etapa);
                        end                            

                        proy_agregados_mejor_intento = [];
                        etapas_agregados_mejor_intento = [];

                        conect_agregados_mejor_intento = [];
                        etapas_conect_agregados_mejor_intento = [];
                        conect_adelantado_mejor_intento = [];
                        etapas_fin_conect_adelantado_mejor_intento = [];
                        etapas_orig_conect_adelantado_mejor_intento = [];

                        plan_antes_intentos = pPlan.Plan;
                        estructura_costos_mejor_intento = estructura_costos_actual;

% DEBUG
if nivel_debug > 1
for nro_etapa = 1:this.pParOpt.CantidadEtapas
proyectos_en_sep = sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = pPlan.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
texto = ['Proyectos en SEP en etapa ' num2str(nro_etapa) ' es distinto a proyectos en plan'];
fprintf(doc_id, strcat(texto, '\n'));
texto = ['Proyectos en SEP: ' num2str(proyectos_en_sep)];
fprintf(doc_id, strcat(texto, '\n'));
texto = ['Proyectos en plan: ' num2str(proyectos_en_plan)];
fprintf(doc_id, strcat(texto, '\n'));
error = MException('cOptACO:genera_planes_bl_elimina_desplaza_paralelo',...
'Intento fallido 2 en BL Cambio Uprating antes de intentos paralelos. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end
end
end

                        totex_total_intentos = zeros(length(proy_seleccionados.agregar),1);
                        while intento_paralelo_actual < length(proy_seleccionados.agregar)
                            intento_paralelo_actual = intento_paralelo_actual +1;

                            pPlan.Plan = plan_antes_intentos;
                            proy_agregados = proy_seleccionados.agregar{intento_paralelo_actual};
                            ultimo_proy_intento_agregado = proy_agregados;
                            etapas_agregados = etapas_eliminar(1);

                            conect_agregados = [];
                            etapas_conect_agregados = [];
                            conect_adelantado = [];
                            etapas_fin_conect_adelantado = [];
                            etapas_orig_conect_adelantado = [];
                            % determina si proy a agregar tienen
                            % requisito de conectividad
                            if this.pAdmProy.entrega_proyecto(proy_agregados).TieneRequisitosConectividad
                                cantidad_req_conectividad = this.pAdmProy.entrega_proyecto(proy_agregados).entrega_cantidad_grupos_conectividad();

                                for ii = 1:cantidad_req_conectividad
                                    indice_proy_conect = this.pAdmProy.entrega_proyecto(proy_agregados).entrega_indices_grupo_proyectos_conectividad(ii);
                                    [existe_conect_en_plan, etapa_conect_en_plan, proy_conect_en_plan] = pPlan.conectividad_existe_con_etapa_y_proyecto(indice_proy_conect);
                                    if existe_conect_en_plan
                                        % proyecto de conectividad
                                        % está. Hay que verificar si se
                                        % tiene que adelantar
                                        if etapa_conect_en_plan > etapas_agregados
                                            conect_adelantado = [conect_adelantado proy_conect_en_plan];
                                            etapas_orig_conect_adelantado = [etapas_orig_conect_adelantado etapa_conect_en_plan];
                                            etapas_fin_conect_adelantado = [etapas_fin_conect_adelantado etapas_agregados];
                                        end
                                    else
                                        % hay que agregar requisito de conectividad 
                                        % por ahora se agrega primer
                                        % proyecto de conectividad, ya
                                        % que es el más barato
                                        conect_agregados = [conect_agregados indice_proy_conect(1)];
                                        etapas_conect_agregados = [etapas_conect_agregados etapas_agregados];
                                    end
                                end
                            end

                            %intentos_actuales{intento_paralelo_actual}.estructura_costos_actual = [];
                            %intentos_actuales{intento_paralelo_actual}.evaluacion_actual = [];

                            if nivel_debug > 1
                                texto = sprintf('%-25s %-10s %-20s %-10s',...
                                    '      Totex Plan Base ', num2str(estructura_costos_plan_base.TotexTotal), ...
                                    'Totex plan mejor intento', num2str(estructura_costos_mejor_intento.TotexTotal));
                                fprintf(doc_id, strcat(texto, '\n'));

                                texto = ['Intento paralelo actual: ' num2str(intento_paralelo_actual) '/' num2str(length(proy_seleccionados.agregar))];
                                fprintf(doc_id, strcat(texto, '\n'));
                                texto = ['Proy. agregados  : ' num2str(proy_agregados)];
                                fprintf(doc_id, strcat(texto, '\n'));
                                texto = ['Etapa agregados  : ' num2str(etapas_agregados)];
                                fprintf(doc_id, strcat(texto, '\n'));
                                texto = ['Conect. agregados: ' num2str(conect_agregados)];
                                fprintf(doc_id, strcat(texto, '\n'));
                                texto = ['Etapa conect agre: ' num2str(etapas_conect_agregados)];
                                fprintf(doc_id, strcat(texto, '\n'));
                                texto = ['Conect. adelantad: ' num2str(conect_adelantado)];
                                fprintf(doc_id, strcat(texto, '\n'));
                                texto = ['Etapa orig. adel : ' num2str(etapas_orig_conect_adelantado)];
                                fprintf(doc_id, strcat(texto, '\n'));
                                texto = ['Etapa final adel : ' num2str(etapas_fin_conect_adelantado)];
                                fprintf(doc_id, strcat(texto, '\n'));
                            end

                            desde_etapa = min(etapas_agregados);
                            % modifica sep y evalua plan a partir de primera etapa cambiada
%                                 intentos_actuales{intento_paralelo_actual}.DesdeEtapaIntento = desde_etapa;
%                                 existe_mejora = false;
%                                 plan_actual_hasta_etapa = desde_etapa - 1;
%                                 plan_actual_intento_hasta_etapa = desde_etapa - 1;
                            % primero proyectos de conectividad
                            % agregados
                            for i = 1:length(conect_agregados)
                                pPlan.agrega_proyecto(desde_etapa, conect_agregados(i));
                            end

                            % ahora proyectos de conectividad
                            % adelantados
                            for i = 1:length(conect_adelantado)
                                pPlan.adelanta_proyectos(conect_adelantado(i), etapas_orig_conect_adelantado(i), etapas_fin_conect_adelantado(i));
                            end

                            % finalmente, proyecto agregado
                            pPlan.agrega_proyecto(desde_etapa, proy_agregados);
                            est_evaluacion_act.Valido = false;
                            ultima_etapa_evaluada = 0;

                            %intentos_actuales{intento_paralelo_actual}.proy_seleccionados = proy_agregados;

                            for nro_etapa = desde_etapa:this.pParOpt.CantidadEtapas
                                % agrega proyectos al sep de la etapa
                                % primero proyectos de conectividad
                                % agregados
                                ultima_etapa_evaluada = nro_etapa;
                                for j = 1:length(conect_agregados)
                                    proyecto = this.pAdmProy.entrega_proyecto(conect_agregados(j));
                                    sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                end

                                %luego proyectos de conectividad
                                %adelantados
                                for j = 1:length(conect_adelantado)
                                    if nro_etapa >= etapas_fin_conect_adelantado(j) && ...
                                            nro_etapa < etapas_orig_conect_adelantado(j)
                                        proyecto = this.pAdmProy.entrega_proyecto(conect_adelantado(j));
                                        sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    end
                                end

                                % finalmente, proyectos agregados
                                for j = 1:length(proy_agregados)
                                    proyecto = this.pAdmProy.entrega_proyecto(proy_agregados(j));
                                    sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                end
                                this.evalua_red(sep_actuales{nro_etapa}, nro_etapa, [], false);
                                est_evaluacion_act = this.entrega_estructura_evaluacion(sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                                this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa)
                                while ~est_evaluacion_act.Valido
                                    if nivel_debug > 1
                                        texto = ['   Plan no es valido en etapa ' num2str(nro_etapa) '. Se imprimen elementos con flujo maximo:'];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                        texto = sprintf('%-3s %-25s %-5s', ' ', 'Elemento', 'Porcentaje carga');
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                    proy_agregado_es_ppal = false;
                                    proy_agregado_es_conect = false;
                                    el_flujo_maximo = pPlan.entrega_elementos_flujo_maximo(nro_etapa);
                                    [n, ~] = size(el_flujo_maximo);
                                    % primero verifica si
                                    % transformadores eliminados ayudan
                                    % a superar congestion
                                    proy_agregado = false;
                                    if ~isempty(trafos_paral_eliminados)
                                        for i = 1:n
                                            existente = el_flujo_maximo{i,4};
                                            id_adm_proy = el_flujo_maximo{i,3};
                                            if nivel_debug > 1
                                                texto = sprintf('%-3s %-25s %-5s', ' ', el_flujo_maximo{i,1}, num2str(el_flujo_maximo{i,7}));
                                                fprintf(doc_id, strcat(texto, '\n'));
                                            end

                                            if existente
                                                el_red = this.pAdmProy.ElementosSerieExistentes(id_adm_proy);
                                            else
                                                el_red = this.pAdmProy.ElementosSerie(id_adm_proy);
                                            end

                                            proy = this.pAdmProy.entrega_id_proyectos_salientes(el_red);
                                            if ismember(trafos_paral_eliminados, proy)
                                                % trafo eliminado ayuda
                                                % a superar congestión.
                                                % Se agrega
                                                id_trafo_a_agregar = trafos_paral_eliminados(ismember(trafos_paral_eliminados, proy));
                                                if nivel_debug > 1
                                                    texto = ['Agrega trafo paral eliminado con proyecto ' num2str(id_trafo_a_agregar)];
                                                    fprintf(doc_id, strcat(texto, '\n'));
                                                end
                                                proy_agregados = [proy_agregados id_trafo_a_agregar];
                                                etapas_agregados = [etapas_agregados nro_etapa];
                                                pPlan.agrega_proyecto(nro_etapa, id_trafo_a_agregar);
                                                sep_actuales{nro_etapa}.agrega_proyecto(this.pAdmProy.entrega_proyecto(id_trafo_a_agregar));
                                                trafos_paral_eliminados(ismember(trafos_paral_eliminados, id_trafo_a_agregar)) = [];
                                                proy_agregado_es_conect = true;
                                                proy_agregado = true;
                                            end
                                        end
                                        if proy_agregado
                                            this.evalua_red(sep_actuales{nro_etapa}, nro_etapa, [], false);
                                            est_evaluacion_act = this.entrega_estructura_evaluacion(sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                                            this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa)
                                        end
                                    end
                                    if isempty(trafos_paral_eliminados) || ~proy_agregado
                                        posibles_proyectos_agregar = [];
                                        for i = 1:n
                                            existente = el_flujo_maximo{i,4};
                                            id_adm_proy = el_flujo_maximo{i,3};
                                            if nivel_debug > 1
                                                texto = sprintf('%-3s %-25s %-5s', ' ', el_flujo_maximo{i,1}, num2str(el_flujo_maximo{i,7}));
                                                fprintf(doc_id, strcat(texto, '\n'));
                                            end

                                            if existente
                                                el_red = this.pAdmProy.ElementosSerieExistentes(id_adm_proy);
                                            else
                                                el_red = this.pAdmProy.ElementosSerie(id_adm_proy);
                                            end
                                            % verifica si elemento
                                            % sobrecargado
                                            % pertenece al corredor
                                            % o ubicación que se
                                            % está evaluando
                                            corredor_el_sobrecargado = el_red.entrega_id_corredor();
                                            if corredor_el_sobrecargado ~= 0
                                                if corredor_el_sobrecargado == proy_seleccionados.corredor
                                                    % corresponde
                                                    posibles_proyectos_agregar = this.pAdmProy.entrega_id_proyectos_salientes(el_red);
                                                    proy_agregado_es_ppal = true;
                                                end
                                            else
                                                ubicacion_el_sobrecargado = el_red.entrega_se2().entrega_ubicacion();
                                                if ubicacion_el_sobrecargado == proy_seleccionados.ubicacion
                                                    % corresponde
                                                    posibles_proyectos_agregar = this.pAdmProy.entrega_id_proyectos_salientes(el_red);
                                                    proy_agregado_es_ppal = true;
                                                else
                                                    for j = 1:length(conect_agregados)
                                                        if el_red == this.pAdmProy.entrega_proyecto(conect_agregados(j)).Elemento(end)
                                                            % corresponde
                                                            posibles_proyectos_agregar = this.pAdmProy.entrega_id_proyectos_salientes(el_red);
                                                            proy_agregado_es_conect = true;
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                        if isempty(posibles_proyectos_agregar)
                                            % se fuerza agregar
                                            % proyecto. Flujos pueden
                                            % cambiar
                                            ultimo_el_red = this.pAdmProy.entrega_proyecto(ultimo_proy_intento_agregado).Elemento(end);
                                            posibles_proyectos_agregar = this.pAdmProy.entrega_id_proyectos_salientes(ultimo_el_red);
                                            proy_agregado_es_ppal = true;
                                        end
                                        if ~isempty(posibles_proyectos_agregar)
                                            costos_potenciales = this.pAdmProy.entrega_costo_potencial(posibles_proyectos_agregar, pPlan);
                                            % ordena posibles proyectos de
                                            % acuerdo a costo
                                            [~, id] = sort(costos_potenciales);
                                            posibles_proyectos_agregar = posibles_proyectos_agregar(id);
                                            ultimo_proy_evaluado = 0;
                                            for j = 1:length(posibles_proyectos_agregar)
                                                proy_a_agregar = this.pAdmProy.entrega_proyecto(posibles_proyectos_agregar(j));
                                                if proy_a_agregar.TieneRequisitosConectividad
                                                    % se excluyen proyectos de AV ya que se ven al comienzo 
                                                    continue
                                                end
                                                ultimo_proy_evaluado = j;
                                                if nivel_debug > 1
                                                    texto = ['   Agrega posible proyecto a agregar ' num2str(j) '/' num2str(length(posibles_proyectos_agregar)) ' : ' num2str(posibles_proyectos_agregar(j))];
                                                    fprintf(doc_id, strcat(texto, '\n'));
                                                end

                                                sep_actuales{nro_etapa}.agrega_proyecto(proy_a_agregar);
                                                this.evalua_red(sep_actuales{nro_etapa}, nro_etapa, [], false);
                                                est_eval_intermedia = this.entrega_estructura_evaluacion(sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion());
                                                if ~est_eval_intermedia.Valido
                                                    sep_actuales{nro_etapa}.elimina_proyecto(proy_a_agregar);
                                                else
                                                    if nivel_debug > 1
                                                        texto = ['Intento es valido en etapa ' num2str(nro_etapa) '. Se agrega proyecto: '  num2str(posibles_proyectos_agregar(j))];
                                                        fprintf(doc_id, strcat(texto, '\n'));
                                                    end
                                                    est_evaluacion_act = est_eval_intermedia;
                                                    pPlan.agrega_proyecto(nro_etapa, posibles_proyectos_agregar(j));
                                                    proy_agregados = [proy_agregados posibles_proyectos_agregar(j)];
                                                    etapas_agregados = [etapas_agregados nro_etapa];

                                                    if proy_agregado_es_ppal
                                                        ultimo_proy_intento_agregado = posibles_proyectos_agregar(j);
                                                    end
                                                    this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa)
                                                    break;
                                                end
                                            end
                                        end

                                        if ~est_evaluacion_act.Valido
                                            % quiere decir que ningún proyecto hizo que plan fuera válido. Se toma el último proyecto agregado (mayor capacidad)
                                            if ~isempty(posibles_proyectos_agregar) && ultimo_proy_evaluado ~= 0
                                                if nivel_debug > 1
                                                    texto = ['Intento no fue valido en etapa ' num2str(nro_etapa) ' pero se agrega proyecto: '  num2str(posibles_proyectos_agregar(ultimo_proy_evaluado))];
                                                    fprintf(doc_id, strcat(texto, '\n'));
                                                end
                                                pPlan.agrega_proyecto(nro_etapa, posibles_proyectos_agregar(ultimo_proy_evaluado));
                                                proy_agregados = [proy_agregados posibles_proyectos_agregar(ultimo_proy_evaluado)];
                                                etapas_agregados = [etapas_agregados nro_etapa];
                                                sep_actuales{nro_etapa}.agrega_proyecto(this.pAdmProy.entrega_proyecto(posibles_proyectos_agregar(ultimo_proy_evaluado)));
                                                this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa)
                                                if proy_agregado_es_ppal
                                                    ultimo_proy_intento_agregado = posibles_proyectos_agregar(ultimo_proy_evaluado);
                                                end

                                            else
                                                % quiere decir que no hay
                                                % más proyectos a agregar.
                                                % Se descarta intento
                                                if nivel_debug > 1
                                                    texto = ['Intento no fue valido en etapa ' num2str(nro_etapa) ' y no hay mas proyectos a agregar. Se descarta'];
                                                    fprintf(doc_id, strcat(texto, '\n'));
                                                end
                                                break
                                            end
                                        end
                                    end
                                end

                                if est_evaluacion_act.Valido
                                    this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa);                                            
                                else
                                    break;
                                end
                            end

                            if est_evaluacion_act.Valido
                                % evalua performance intento
                                this.calcula_costos_totales(pPlan);
                                totex_total_intentos(intento_paralelo_actual) = pPlan.entrega_totex_total();
                                if pPlan.entrega_totex_total() < estructura_costos_mejor_intento.TotexTotal
                                    existe_mejor_intento = true;
                                    id_mejor_intento = intento_paralelo_actual;
                                    estructura_costos_mejor_intento = pPlan.entrega_estructura_costos();
                                    plan_actual_mejor_intento = pPlan.Plan;
                                    proy_agregados_mejor_intento = proy_agregados;
                                    etapas_agregados_mejor_intento = etapas_agregados;
                                    conect_agregados_mejor_intento = conect_agregados;
                                    etapas_conect_agregados_mejor_intento = etapas_conect_agregados;
                                    conect_adelantado_mejor_intento = conect_adelantado;
                                    etapas_fin_conect_adelantado_mejor_intento = etapas_fin_conect_adelantado;
                                    etapas_orig_conect_adelantado_mejor_intento = etapas_orig_conect_adelantado;
                                    if nivel_debug > 1
                                        texto = ['   Intento ' num2str(intento_paralelo_actual) ' tiene totex: ' num2str(pPlan.entrega_totex_total()) ' . Mejora totex actual'];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end  
                                else
                                    if nivel_debug > 1
                                        texto = ['   Intento ' num2str(intento_paralelo_actual) ' tiene totex: ' num2str(pPlan.entrega_totex_total()) '. Es valido, pero no es mejor que totex actual (' num2str(estructura_costos_mejor_intento.TotexTotal) ')'];      
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end  
                                end
                            else
                                % intento actual no fue válido. No es
                                % necesario guardar nada
                                totex_total_intentos(intento_paralelo_actual) = 9999999;
                                if nivel_debug > 1
                                    texto = ['   Intento ' num2str(intento_paralelo_actual) ' no es valido'];      
                                    fprintf(doc_id, strcat(texto, '\n'));
                                end  
                            end
% DEBUG
if nivel_debug > 1
for nro_etapa = 1:ultima_etapa_evaluada
proyectos_en_sep = sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = pPlan.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
texto = ['Proyectos en SEP en etapa ' num2str(nro_etapa) ' es distinto a proyectos en plan'];
fprintf(doc_id, strcat(texto, '\n'));
texto = ['Proyectos en SEP: ' num2str(proyectos_en_sep)];
fprintf(doc_id, strcat(texto, '\n'));
texto = ['Proyectos en plan: ' num2str(proyectos_en_plan)];
fprintf(doc_id, strcat(texto, '\n'));
error = MException('cOptACO:genera_planes_bl_elimina_desplaza_paralelo',...
'Intento fallido 3 en BL Cambio Uprating antes de deshacer los proyectos del intento. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end
end
end

                            % se deshacen los proyectos del intento
                            % actual
                            for j = length(proy_agregados):-1:1
                                desde_etapa = etapas_agregados(j);
                                for nro_etapa = desde_etapa:ultima_etapa_evaluada
                                    proyecto = this.pAdmProy.entrega_proyecto(proy_agregados(j));
                                    sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                end
                            end

                            for j = length(conect_agregados):-1:1
                                desde_etapa = etapas_conect_agregados;
                                for nro_etapa = desde_etapa:ultima_etapa_evaluada
                                    proyecto = this.pAdmProy.entrega_proyecto(conect_agregados(j));
                                    sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                end
                            end

                            %finalmente proyectos de conectividad
                            %adelantados
                            for j = length(conect_adelantado):-1:1
                                desde_etapa = etapas_fin_conect_adelantado(j);
                                for nro_etapa = desde_etapa:ultima_etapa_evaluada
                                    if nro_etapa >= etapas_fin_conect_adelantado(j) && ...
                                            nro_etapa < etapas_orig_conect_adelantado(j) 
                                        proyecto = this.pAdmProy.entrega_proyecto(conect_adelantado(j));
                                        sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    end
                                end
                            end
% DEBUG
if nivel_debug > 1
plan_prueba = cPlanExpansion(8888888);
plan_prueba.Plan = plan_antes_intentos;
for nro_etapa = 1:this.pParOpt.CantidadEtapas
proyectos_en_sep = sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = plan_prueba.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
texto = ['Proyectos en SEP en etapa ' num2str(nro_etapa) ' es distinto a proyectos en plan'];
fprintf(doc_id, strcat(texto, '\n'));
texto = ['Proyectos en SEP: ' num2str(proyectos_en_sep)];
fprintf(doc_id, strcat(texto, '\n'));
texto = ['Proyectos en plan: ' num2str(proyectos_en_plan)];
fprintf(doc_id, strcat(texto, '\n'));
error = MException('cOptACO:genera_planes_bl_elimina_desplaza_paralelo',...
'Intento fallido 4 en BL Cambio Uprating luego de deshacer los proyectos del intento. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end
end
end
                        end
                        % determina mejor intento y si hay mejora
                        if nivel_debug > 1
                            texto = '\nResultados de los intentos:';      
                            fprintf(doc_id, strcat(texto, '\n'));
                            texto = sprintf('%-10s %-10s', 'Intento', 'Totex');
                            fprintf(doc_id, strcat(texto, '\n'));
                            for jj = 1:length(proy_seleccionados.agregar)
                                texto = sprintf('%-10s %-10s', num2str(jj), num2str(totex_total_intentos(jj)));
                                fprintf(doc_id, strcat(texto, '\n'));
                            end
                        end

                        if existe_mejor_intento
%disp('existe mejor intento')
                            if nivel_debug > 1
                                texto = ['   Existe mejor intento. Nr: ' num2str(id_mejor_intento)];      
                                fprintf(doc_id, strcat(texto, '\n'));
                            end  
                            pPlan.Plan = plan_actual_mejor_intento;

                            % modifica sep de acuerdo al mejor
                            % intento
                            desde_etapa = min(etapas_agregados);
                            for nro_etapa = desde_etapa:this.pParOpt.CantidadEtapas
                                % agrega proyectos al sep de la etapa
                                % primero proyectos de conectividad
                                % agregados
                                for j = 1:length(conect_agregados_mejor_intento)
                                    if nro_etapa >= etapas_conect_agregados_mejor_intento(j)
                                        proyecto = this.pAdmProy.entrega_proyecto(conect_agregados_mejor_intento(j));
                                        sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    end
                                end

                                %luego proyectos de conectividad
                                %adelantados
                                for j = 1:length(conect_adelantado_mejor_intento)
                                    if nro_etapa >= etapas_fin_conect_adelantado_mejor_intento(j) && ...
                                            nro_etapa < etapas_orig_conect_adelantado_mejor_intento(j)
                                        proyecto = this.pAdmProy.entrega_proyecto(conect_adelantado_mejor_intento(j));
                                        sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    end
                                end

                                % finalmente, proyectos agregados
                                for j = 1:length(proy_agregados_mejor_intento)
                                    if nro_etapa >= etapas_agregados_mejor_intento(j)
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_agregados_mejor_intento(j));
                                        sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    end
                                end
                            end
                            proyectos_restringidos_para_eliminar = [proyectos_restringidos_para_eliminar proy_agregados_mejor_intento];
% DEBUG
if nivel_debug > 1
for nro_etapa = 1:this.pParOpt.CantidadEtapas
proyectos_en_sep = sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = pPlan.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
texto = ['Proyectos en SEP en etapa ' num2str(nro_etapa) ' es distinto a proyectos en plan'];
fprintf(doc_id, strcat(texto, '\n'));
texto = ['Proyectos en SEP: ' num2str(proyectos_en_sep)];
fprintf(doc_id, strcat(texto, '\n'));
texto = ['Proyectos en plan: ' num2str(proyectos_en_plan)];
fprintf(doc_id, strcat(texto, '\n'));
error = MException('cOptACO:genera_planes_bl_elimina_desplaza',...
'Intento fallido 6 en BL Cambio Uprating luego de determinar el mejor intento. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end
end
end

                        else
                            cant_busqueda_fallida = cant_busqueda_fallida + 1;
                            % se deshacen los cambios en el SEP
                            pPlan.Plan = plan_actual;
                            proyectos_eliminar = proy_seleccionados.eliminar;
                            etapas_eliminar = proy_seleccionados.etapa_eliminar;
                            proyectos_desplazar = proy_seleccionados.conectividad_desplazar;
                            etapas_originales_desplazar = proy_seleccionados.etapas_orig_conectividad_desplazar;
                            etapas_desplazar = proy_seleccionados.etapas_fin_conectividad_desplazar;
                            trafos_paral_eliminados = proy_seleccionados.trafos_paralelos_potenciales_a_eliminar;
                            etapas_trafos_paral_eliminados = proy_seleccionados.etapas_trafos_paralelos_potenciales_a_eliminar;

                            %proyectos desplazados
                            for k = 1:length(proyectos_desplazar)
                                desde_etapa = etapas_originales_desplazar(k);
                                hasta_etapa = etapas_desplazar(k);
                                for nro_etapa = desde_etapa:hasta_etapa-1
                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_desplazar(k));
                                    sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                end
                            end
                            %proyectos eliminados
                            for k = 1:length(proyectos_eliminar)
                                desde_etapa = etapas_eliminar(k);
                                for nro_etapa = desde_etapa:this.pParOpt.CantidadEtapas
                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_eliminar(k));
                                    sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                end
                            end               

                            % trafos potenciales eliminados
                            for k = 1:length(trafos_paral_eliminados)
                                desde_etapa = etapas_trafos_paral_eliminados(k);
                                for nro_etapa = desde_etapa:this.pParOpt.CantidadEtapas
                                    proyecto = this.pAdmProy.entrega_proyecto(trafos_paral_eliminados(k));
                                    sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                end
                            end
% DEBUG
if nivel_debug > 1
for nro_etapa = 1:this.pParOpt.CantidadEtapas
proyectos_en_sep = sep_actuales{nro_etapa}.entrega_proyectos();
proyectos_en_plan = pPlan.entrega_proyectos_acumulados(nro_etapa);
if ~isempty(proyectos_en_sep) || ~isempty(proyectos_en_plan)
if ~isequal(sort(proyectos_en_sep), sort(proyectos_en_plan))
texto = ['Proyectos en SEP en etapa ' num2str(nro_etapa) ' es distinto a proyectos en plan'];
fprintf(doc_id, strcat(texto, '\n'));
texto = ['Proyectos en SEP: ' num2str(proyectos_en_sep)];
fprintf(doc_id, strcat(texto, '\n'));
texto = ['Proyectos en plan: ' num2str(proyectos_en_plan)];
fprintf(doc_id, strcat(texto, '\n'));
error = MException('cOptACO:genera_planes_bl_elimina_desplaza_paralelo',...
'Intento fallido 7 en BL Cambio Uprating luego de busqueda fallida. Proyectos en SEP distintos a proyectos en plan');
throw(error)
end
end
end
end

                        end
                    end
                    if nivel_debug > 1
                        totex_despues_de_cambio_ur = pPlan.entrega_totex_total();
                        cantidad_proy_despues_de_cambio_ur = pPlan.cantidad_acumulada_proyectos();

                        texto = 'Fin cambio uprating';
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = sprintf('%-15s %-10s %-10s', ' ', 'No proy', 'Totex');
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = sprintf('%-15s %-10s %-10s', 'Original', num2str(cantidad_proy_orig), num2str(totex_orig));
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = sprintf('%-15s %-10s %-10s', 'Elimina', num2str(cantidad_proy_despues_de_elimina), num2str(totex_despues_de_elimina));
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = sprintf('%-15s %-10s %-10s', 'Cambio UR', num2str(cantidad_proy_despues_de_cambio_ur), num2str(totex_despues_de_cambio_ur));
                        fprintf(doc_id, strcat(texto, '\n'));

                        texto = 'Plan actual despues de cambio uprating';
                        pPlan.agrega_nombre_proyectos(this.pAdmProy);
                        texto = pPlan.entrega_texto_plan_expansion();
                        fprintf(doc_id, strcat(texto, '\n'));
                    end    
                else
                    totex_despues_de_cambio_ur = 0;
                    cantidad_proy_despues_de_cambio_ur = 0;
                end

                if considera_desplaza_despues_de_elimina && pPlan.cantidad_acumulada_proyectos() ~= 0
                    plan_original_intermedio = pPlan.Plan;
                    nro_etapa = 0;
                    nuevos_proyectos_eliminados = [];
                    while nro_etapa < cantidad_etapas
                    	nro_etapa = nro_etapa +1;

                        cantidad_proyectos_etapa = pPlan.entrega_cantidad_proyectos_etapa(nro_etapa);
                        if cantidad_proyectos_etapa == 0
                            continue;
                        end
                        
                        estructura_costos_actual = pPlan.entrega_estructura_costos();
                        plan_actual = pPlan.Plan;
                        evaluacion_actual = pPlan.entrega_evaluacion();

% debug por si se quiere verificar pPlan utilizando parfor
% datos_escenario{nro_plan}.CapacidadGeneradores = datos_escenario_total{nro_plan}.CapacidadGeneradores(:,nro_etapa);
% indice_1 = 1 + (nro_etapa - 1)*cantidad_puntos_operacion;
% indice_2 = nro_etapa*cantidad_puntos_operacion;
% if ~isempty(datos_escenario_total{nro_plan}.SerieGeneradoresERNC)
%     datos_escenario{nro_plan}.SerieGeneradoresERNC{nro_plan} = datos_escenario_total{nro_plan}.SerieGeneradoresERNC(:,indice_1:indice_2);
% else
%     datos_escenario{nro_plan}.SerieGeneradoresERNC{nro_plan} = [];
% end
% datos_escenario{nro_plan}.SerieConsumos = datos_escenario_total{nro_plan}.SerieConsumos(:,indice_1:indice_2);
% 
                        proyectos_restringidos_para_desplazar = [];
                        proyectos_desplazados = [];
                        cant_busqueda_fallida = 0;
                        maxima_cant_busqueda_fallida = min(cant_bl_desplaza_busqueda_fallida, cantidad_proyectos_etapa);
                        while cant_busqueda_fallida < maxima_cant_busqueda_fallida
                            
                            intento_paralelo_actual = 0;
                            intentos_actuales = cell(1,0);
                            proyectos_restringidos_para_desplazar_intento = proyectos_restringidos_para_desplazar;
                            fuerza_continuar_comparacion = false;
                            cantidad_mejores_intentos = 0;
                            while intento_paralelo_actual < cant_proy_a_comparar || fuerza_continuar_comparacion
                                intento_paralelo_actual = intento_paralelo_actual +1;
                            
                                proyectos_seleccionados = this.selecciona_proyectos_a_desplazar(pPlan, nro_etapa, proyectos_restringidos_para_desplazar_intento);
                                if isempty(proyectos_seleccionados)
                                    intentos_actuales{intento_paralelo_actual}.Valido = false;
                                    if nivel_debug > 1
                                        texto = ['   En etapa ' num2str(nro_etapa) ' nro intento ' num2str(intento_paralelo_actual) ' no hay proyectos seleccionados'];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end

                                    % no hay más proyectos. Se termina
                                    % la evaluación
                                    intento_paralelo_actual = intento_paralelo_actual -1;
                                    break
                                end

                                % se agregan proyectos seleccionados a
                                % proyectos restringidor para desplazar
                                % intento, con tal de que no vuelva a ser
                                % seleccionado
                                proyectos_restringidos_para_desplazar_intento = [proyectos_restringidos_para_desplazar_intento proyectos_seleccionados];

                                intentos_actuales{intento_paralelo_actual}.proyectos_seleccionados = proyectos_seleccionados;
                                intentos_actuales{intento_paralelo_actual}.Totex = 999999999999999999999;
                                intentos_actuales{intento_paralelo_actual}.Valido = false;
                                intentos_actuales{intento_paralelo_actual}.Plan = [];
                                intentos_actuales{intento_paralelo_actual}.AdelantaProyectos = false;
                                % elimina proyectos de sep actual y desplaza
                                % proyectos en el plan. Ojo que se eliminan en
                                % orden inverso!
                                for k = length(proyectos_seleccionados):-1:1
                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_seleccionados(k));
                                    sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    if nro_etapa < cantidad_etapas
                                        pPlan.desplaza_proyectos(proyectos_seleccionados(k), nro_etapa, nro_etapa + 1);
                                    else
                                        pPlan.elimina_proyectos(proyectos_seleccionados(k), nro_etapa);
                                    end
                                end
                            
                                %evalua red (proyectos ya se ingresaron al sep
                                if nivel_debug > 1
                                    tinic_debug = toc;
                                end
                                
                                sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa);
                                this.calcula_costos_totales(pPlan);

                                if nivel_debug > 1
                                    tiempos_computo_opf(end+1) = toc-tinic_debug;
                                end
                                
                                if ~sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion().ExisteResultado
                                    texto_warning = ' 3 - No existe resultado en evaluacion. Entra a proceso';
                                    warning(texto_warning);
                                    
                                    if isempty(procesos_fallidos{nro_plan})
                                        procesos_fallidos{nro_plan} = pPlan.Plan;
                                        id_fallido = 1;
                                    else
                                        procesos_fallidos{nro_plan} = [procesos_fallidos{nro_plan} pPlan.Plan];
                                        id_fallido = length(procesos_fallidos{nro_plan});
                                    end

                                    nombre_proceso = ['./output/debug/dcopf_proc_fallido_id_' num2str(id_fallido) '_elim_despl_par_eliminar_desplaza_plan' num2str(pPlan.entrega_no()) '_etapa_' num2str(nro_etapa) '.dat'];
                                    sep_actuales{nro_etapa}.entrega_opf().ingresa_nombres_problema();                            
                                    sep_actuales{nro_etapa}.entrega_opf().imprime_problema_optimizacion(nombre_proceso);

                                    nombre_proceso = ['./output/debug/dcopf_proc_fallido_id' num2str(id_fallido) '_elim_despl_par_eliminar_desplaza_plan_' num2str(pPlan.entrega_no()) '_etapa_' num2str(nro_etapa) '_comparar.dat'];
                                    plan_debug = cPlanExpansion(888888889);
                                    plan_debug.Plan = pPlan.Plan;
                                    plan_debug.inserta_sep_original(this.pSEP.crea_copia());
                                    this.evalua_plan_computo_paralelo(plan_debug, nro_etapa, puntos_operacion, datos_escenario_debug, sbase);
                                    plan_debug.entrega_sep_actual().entrega_opf().ingresa_nombres_problema();
                                    plan_debug.entrega_sep_actual().entrega_opf().imprime_problema_optimizacion(nombre_proceso);

                                    texto_warning = ' 3 - No existe resultado en evaluacion. Sale de proceso';
                                    warning(texto_warning);
                                end
                                
                                if pPlan.es_valido(nro_etapa) && pPlan.entrega_totex_total() < estructura_costos_actual.TotexTotal
                                    % cambio produce mejora. Se acepta
                                    intentos_actuales{intento_paralelo_actual}.proyectos_seleccionados = proyectos_seleccionados;
                                    intentos_actuales{intento_paralelo_actual}.Totex = pPlan.entrega_totex_total();
                                    intentos_actuales{intento_paralelo_actual}.Valido = true;
                                    intentos_actuales{intento_paralelo_actual}.Plan = pPlan.Plan;
                                    intentos_actuales{intento_paralelo_actual}.estructura_costos_actual = pPlan.entrega_estructura_costos();
                                    intentos_actuales{intento_paralelo_actual}.evaluacion_actual = pPlan.entrega_evaluacion();
                                    cantidad_mejores_intentos = cantidad_mejores_intentos + 1;
                                    if nivel_debug > 1
                                        texto_desplazados = '';
                                        for jj = 1:length(proyectos_seleccionados)
                                            texto_desplazados = [texto_desplazados ' ' num2str(proyectos_seleccionados(jj))];
                                        end
                                        texto = ['   Nuevo(s) proyecto(s) desplazados etapa ' num2str(nro_etapa) ':' texto_desplazados ' generan mejora'];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                else
                                    % cambio no produce mejora.
                                    % verificar si tiene potencial de ser eliminado o si adelandar 
                                    % proyecto seleccionado produce mejora
                                    if nivel_debug > 1
                                        texto_desplazados = '';
                                        for jj = 1:length(proyectos_seleccionados)
                                            texto_desplazados = [texto_desplazados ' ' num2str(proyectos_seleccionados(jj))];
                                        end
                                        if pPlan.es_valido(nro_etapa)
                                            texto = ['   Proyectos desplazados etapa ' num2str(nro_etapa) ':' texto_desplazados ' no generan mejora. Totex total: ' num2str(pPlan.entrega_totex_total()) '. Se verifica si adelantarlo genera mejora'];
                                        else
                                            texto = ['   Proyectos desplazados etapa ' num2str(nro_etapa) ':' texto_desplazados ' vuelven al plan invalido. Se verifica si adelantarlos generan mejora'];
                                        end
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                    
                                    proyectos_restringidos_para_desplazar = [proyectos_restringidos_para_desplazar proyectos_seleccionados];
                                    intentos_actuales{intento_paralelo_actual}.Valido = false;
                                    
                                    %[p_elim, p_desp, e_orig_desp, e_desp]= this.determina_factibilidad_eliminar_proyecto(proyectos_seleccionados, nro_etapa);
                                    % linlin
                                    %proyectos_potenciales_eliminar
                                end
                                
                                % deshace cambios en los sep actuales 
                                pPlan.inserta_evaluacion_etapa(nro_etapa, evaluacion_actual(nro_etapa));
                                pPlan.Plan = plan_actual;
                                pPlan.inserta_estructura_costos(estructura_costos_actual);
                            
                                % deshace los cambios hechos en los sep
                                % actuales
                                for k = 1:length(proyectos_seleccionados)
                                    proyecto = this.pAdmProy.entrega_proyecto(proyectos_seleccionados(k));
                                    sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                end
                                
                                if ~intentos_actuales{intento_paralelo_actual}.Valido && ...
                                    ~isempty(plan_original_intermedio(nro_etapa).Proyectos == proyectos_seleccionados(end)) && ...
                                    nro_etapa > 1
                                    % se ve si proyecto se puede adelantar
                                    if nivel_debug > 1                                        
                                        texto = '      No hubo mejora en desplazamiento. Se verifica si adelantar proyectos produce mejora';
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end

                                    proy_adelantar = this.selecciona_proyectos_a_adelantar(pPlan, nro_etapa, proyectos_seleccionados(end));
                                    % proy_adelantar.seleccionado
                                    % proy_adelantar.etapa_seleccionado
                                    % proy_adelantar.seleccion_directa
                                    % proy_adelantar.primera_etapa_posible = [];
                                    % proy_adelantar.proy_conect_adelantar = [];
                                    % proy_adelantar.etapas_orig_conect = [];

                                    etapa_adelantar = nro_etapa;
                                    ultima_etapa_evaluada = nro_etapa;

                                    flag_salida = false;
                                    existe_resultado_adelanta = false;
                                    
                                    while etapa_adelantar > proy_adelantar.primera_etapa_posible && ~flag_salida
                                        etapa_adelantar = etapa_adelantar - 1;
                                        % agrega proyectos en sep actual en
                                        % etapa actual
                                        for k = 1:length(proy_adelantar.proy_conect_adelantar)
                                            if etapa_adelantar < proy_adelantar.etapas_orig_conect(k) 
                                                proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.proy_conect_adelantar(k));
                                                sep_actuales{etapa_adelantar}.agrega_proyecto(proyecto);
                                                pPlan.adelanta_proyectos(proy_adelantar.proy_conect_adelantar(k), etapa_adelantar + 1, etapa_adelantar);
                                            end
                                        end
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.seleccionado);
                                        sep_actuales{etapa_adelantar}.agrega_proyecto(proyecto);
                                        pPlan.adelanta_proyectos(proy_adelantar.seleccionado, etapa_adelantar + 1, etapa_adelantar);

                                        %evalua red (proyectos ya se ingresaron
                                        %al sep)
                                        if nivel_debug > 1
                                            tinic_debug = toc;
                                        end
                                        
                                        sep_actuales{etapa_adelantar}.entrega_opf().calcula_despacho_economico();
                                        this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{etapa_adelantar}.entrega_opf().entrega_evaluacion(), etapa_adelantar);
                                        this.calcula_costos_totales(pPlan);

                                        if nivel_debug > 1
                                            tiempos_computo_opf(end+1) = toc-tinic_debug;
                                        end
                                        
                                        ultima_etapa_evaluada = etapa_adelantar;
                                        hay_mejora = false;

                                        if ~sep_actuales{etapa_adelantar}.entrega_opf().entrega_evaluacion().ExisteResultado
                                            texto_warning = ' 4 - No existe resultado en evaluacion. Entra a proceso';
                                            warning(texto_warning);
                                            
                                            if isempty(procesos_fallidos{nro_plan})
                                                procesos_fallidos{nro_plan} = pPlan.Plan;
                                                id_fallido = 1;
                                            else
                                                procesos_fallidos{nro_plan} = [procesos_fallidos{nro_plan} pPlan.Plan];
                                                id_fallido = length(procesos_fallidos{nro_plan});
                                            end

                                            nombre_proceso = ['./output/debug/dcopf_proc_fallido_id_' num2str(id_fallido) '_elim_despl_par_desplaza_adelanta_plan' num2str(pPlan.entrega_no()) '_etapa_' num2str(etapa_adelantar) '.dat'];
                                            sep_actuales{nro_etapa}.entrega_opf().ingresa_nombres_problema();                            
                                            sep_actuales{nro_etapa}.entrega_opf().imprime_problema_optimizacion(nombre_proceso);

                                            nombre_proceso = ['./output/debug/dcopf_proc_fallido_id' num2str(id_fallido) '_elim_despl_par_desplaza_adelanta_plan_' num2str(pPlan.entrega_no()) '_etapa_' num2str(etapa_adelantar) '_comparar.dat'];
                                            plan_debug = cPlanExpansion(888888889);
                                            plan_debug.Plan = pPlan.Plan;
                                            plan_debug.inserta_sep_original(this.pSEP.crea_copia());
                                            this.evalua_plan_computo_paralelo(plan_debug, nro_etapa, puntos_operacion, datos_escenario_debug, sbase);
                                            plan_debug.entrega_sep_actual().entrega_opf().ingresa_nombres_problema();
                                            plan_debug.entrega_sep_actual().entrega_opf().imprime_problema_optimizacion(nombre_proceso);
                                            
                                            texto_warning = ' 4 - No existe resultado en evaluacion. Sale de proceso';
                                            warning(texto_warning);                            
                                        end
                                        
                                        if (~existe_resultado_adelanta && pPlan.entrega_totex_total() < estructura_costos_actual.TotexTotal) || ...
                                           (existe_resultado_adelanta && pPlan.entrega_totex_total() < intentos_actuales{intento_paralelo_actual}.Totex)

                                            % adelantar el proyecto produce
                                            % mejora. Se guarda resultado
                                            hay_mejora = true;
                                            intentos_actuales{intento_paralelo_actual}.Plan = pPlan.Plan;
                                            intentos_actuales{intento_paralelo_actual}.estructura_costos_actual = pPlan.entrega_estructura_costos();
                                            intentos_actuales{intento_paralelo_actual}.evaluacion_actual = pPlan.entrega_evaluacion();
                                            intentos_actuales{intento_paralelo_actual}.Valido = true;
                                            intentos_actuales{intento_paralelo_actual}.Totex = pPlan.entrega_totex_total();
                                            intentos_actuales{intento_paralelo_actual}.PlanActualHastaEtapa = ultima_etapa_evaluada;
                                            intentos_actuales{intento_paralelo_actual}.AdelantaProyectos = true;
                                            intentos_actuales{intento_paralelo_actual}.proy_seleccionados = proy_adelantar;
                                            existe_resultado_adelanta = true;
                                            if nivel_debug > 1                                        
                                                texto = ['      Adelantar proyecto de etapa ' num2str(etapa_adelantar+1) ' a ' num2str(etapa_adelantar) ' genera mejora. Totex actual etapa: ' num2str(pPlan.entrega_totex_total())];
                                                fprintf(doc_id, strcat(texto, '\n'));
                                            end
                                        else
                                            if nivel_debug > 1
                                                texto = ['      Adelantar proyecto de etapa ' num2str(etapa_adelantar+1) ' a ' num2str(etapa_adelantar) ' no genera mejora. Totex actual etapa: ' num2str(pPlan.entrega_totex_total())];
                                                fprintf(doc_id, strcat(texto, '\n'));
                                            end                                            
                                        end

                                        if ~existe_resultado_adelanta && hay_mejora
                                            % se elimina proyecto de
                                            % proyectos restringidos para
                                            % desplazar
                                            proyectos_restringidos_para_desplazar(proyectos_restringidos_para_desplazar == proyectos_seleccionados(end)) = [];
                                        end

                                        if ~hay_mejora
                                            flag_salida = true;
                                        end
                                    end

                                    % se deshacen los cambios en el sep
                                    pPlan.Plan = plan_actual;
                                    pPlan.inserta_estructura_costos(estructura_costos_actual);
                                    pPlan.inserta_evaluacion(evaluacion_actual);

                                    for etapa_adelantar = ultima_etapa_evaluada:nro_etapa-1
                                        % deshace los cambios hechos en los sep
                                        % actuales hasta la etapa correcta
                                        % Ojo! orden inverso entre desplaza y
                                        % elimina proyectos!
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.seleccionado);
                                        sep_actuales{etapa_adelantar}.elimina_proyecto(proyecto);
                                        for k = length(proy_adelantar.proy_conect_adelantar):-1:1
                                            if etapa_adelantar < proy_adelantar.etapas_orig_conect(k) 
                                                proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.proy_conect_adelantar(k));
                                                sep_actuales{etapa_adelantar}.elimina_proyecto(proyecto);
                                            end
                                        end
                                    end

                                    if existe_resultado_adelanta
                                        % quiere decir que hubo mejora
                                        cantidad_mejores_intentos = cantidad_mejores_intentos + 1;
                                    end
                                end

                                % se verifica si hay que seguir comparando
                                if fuerza_continuar_comparacion == false && ...
                                   intento_paralelo_actual == cant_proy_a_comparar && ...
                                   cantidad_mejores_intentos_completo > 0 && ...
                                   cantidad_mejores_intentos_completo < cant_proy_a_comparar && ...
                                   cant_proy_a_comparar_sin_mejora > cant_proy_a_comparar

                                    fuerza_continuar_comparacion = true;
                                elseif fuerza_continuar_comparacion && intento_paralelo_actual == cant_proy_a_comparar_sin_mejora
                                    fuerza_continuar_comparacion = false;
                                end
                            end

                            % determina mejor intento
                            existe_mejora = false;
                            mejor_totex = 0;
                            id_mejor_plan_intento = 0;
                            for kk = 1:intento_paralelo_actual
                                if intentos_actuales{kk}.Valido
                                    existe_mejora = true;
                                    if id_mejor_plan_intento == 0
                                        id_mejor_plan_intento = kk;
                                        mejor_totex = intentos_actuales{kk}.Totex;
                                    elseif intentos_actuales{kk}.Totex < mejor_totex
                                        id_mejor_plan_intento = kk;
                                        mejor_totex = intentos_actuales{kk}.Totex;
                                    end
                                    
                                    if nivel_debug > 1
                                        if intentos_actuales{kk}.AdelantaProyectos
                                            proyectos_adelantar = [intentos_actuales{kk}.proy_seleccionados.proy_conect_adelantar intentos_actuales{kk}.proy_seleccionados.seleccionado];
                                            texto = ['      Intento ' num2str(kk) ' es valido (adelantar)' ...
                                                     '. Totex intento: ' num2str(intentos_actuales{kk}.Totex) '. Proyectos adelantar: '];
                                            for oo = 1:length(proyectos_adelantar)
                                                texto = [texto ' ' num2str(proyectos_adelantar(oo))];
                                            end
                                        else
                                            texto = ['      Intento ' num2str(kk) ' es valido (desplazar). Totex intento: ' num2str(intentos_actuales{kk}.Totex) '. Proyectos a desplazar: '];
                                            for oo = 1:length(intentos_actuales{kk}.proyectos_seleccionados)
                                                texto = [texto ' ' num2str(intentos_actuales{kk}.proyectos_seleccionados(oo))];
                                            end
                                        end
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                end
                            end

                            if existe_mejora
                                if nivel_debug > 1
                                    texto = ['      Mejor intento: ' num2str(id_mejor_plan_intento)];
                                    fprintf(doc_id, strcat(texto, '\n'));
                                end

                                plan_actual = intentos_actuales{id_mejor_plan_intento}.Plan;
                                evaluacion_actual = intentos_actuales{id_mejor_plan_intento}.evaluacion_actual;
                                estructura_costos_actual = intentos_actuales{id_mejor_plan_intento}.estructura_costos_actual;
                                pPlan.Plan = plan_actual;
                                pPlan.inserta_estructura_costos(estructura_costos_actual);
                                pPlan.inserta_evaluacion(evaluacion_actual);

                                % se implementa plan hasta la etapa actual del
                                % mejor intento
                                
                                if intentos_actuales{id_mejor_plan_intento}.AdelantaProyectos
                                    proy_adelantar = intentos_actuales{id_mejor_plan_intento}.proy_seleccionados;
                                    ultima_etapa_valida_intento = intentos_actuales{id_mejor_plan_intento}.PlanActualHastaEtapa;

                                    for etapa_adelantar = ultima_etapa_valida_intento:nro_etapa-1
                                        % agrega proyectos en sep actual en
                                        % etapa actual
                                        for k = 1:length(proy_adelantar.proy_conect_adelantar)
                                            if etapa_adelantar < proy_adelantar.etapas_orig_conect(k) 
                                                proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.proy_conect_adelantar(k));
                                                sep_actuales{etapa_adelantar}.agrega_proyecto(proyecto);
                                            end
                                        end
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_adelantar.seleccionado);
                                        sep_actuales{etapa_adelantar}.agrega_proyecto(proyecto);
                                    end
                                else
                                    % se eliminan proyectos seleccionados del sep
                                    % actual en etapa actual
                                    for k = length(intentos_actuales{id_mejor_plan_intento}.proyectos_seleccionados):-1:1
                                        proyecto = this.pAdmProy.entrega_proyecto(intentos_actuales{id_mejor_plan_intento}.proyectos_seleccionados(k));
                                        sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    end
                                    
                                    proyectos_desplazados = [proyectos_desplazados intentos_actuales{id_mejor_plan_intento}.proyectos_seleccionados(end)];
                                    if nro_etapa == cantidad_etapas
                                        nuevos_proyectos_eliminados = [nuevos_proyectos_eliminados intentos_actuales{id_mejor_plan_intento}.proyectos_seleccionados(end)];
                                    end
                                end
                            else
                                cant_busqueda_fallida = cant_busqueda_fallida + 1;
                                % no hubo mejora por lo que no es necesario
                                % rehacer ningún plan
                                if nivel_debug > 1
                                    texto = '      No hubo mejora en ninguno de los intentos';
                                    fprintf(doc_id, strcat(texto, '\n'));
                                end                             
                            end                        
                        end
                        
                        % fin de desplazamiento para la etapa
                        if nivel_debug > 1
                            texto = ['Cantidad de proyectos desplazados plan ' num2str(pPlan.entrega_no()) ' en etapa ' num2str(nro_etapa) ': ' num2str(length(proyectos_desplazados))];
                            fprintf(doc_id, strcat(texto, '\n'));
                        end
                    end % fin de todas las etapas
                    
                    if nivel_debug > 1
                        totex_despues_de_nuevo_desplaza = pPlan.entrega_totex_total();
                        cantidad_proy_despues_de_nuevo_desplaza = pPlan.cantidad_acumulada_proyectos();

                        texto = 'Fin nuevo desplaza proyectos';
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = sprintf('%-15s %-10s %-10s', ' ', 'No proy', 'Totex');
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = sprintf('%-15s %-10s %-10s', 'Original', num2str(cantidad_proy_orig), num2str(totex_orig));
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = sprintf('%-15s %-10s %-10s', 'Elimina', num2str(cantidad_proy_despues_de_elimina), num2str(totex_despues_de_elimina));
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = sprintf('%-15s %-10s %-10s', 'Cambio UR', num2str(cantidad_proy_despues_de_cambio_ur), num2str(totex_despues_de_cambio_ur));
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = sprintf('%-15s %-10s %-10s', 'Desplaza', num2str(cantidad_proy_despues_de_nuevo_desplaza), num2str(totex_despues_de_nuevo_desplaza));
                        fprintf(doc_id, strcat(texto, '\n'));

                        texto = 'Plan actual despues de nuevo desplaza proyectos';
                        pPlan.agrega_nombre_proyectos(this.pAdmProy);
                        texto = pPlan.entrega_texto_plan_expansion();
                        fprintf(doc_id, strcat(texto, '\n'));
                    end
                        
                    proyectos_eliminados = [proyectos_eliminados nuevos_proyectos_eliminados];
                end
                
                if considera_agrega_planes_eliminados && ~isempty(proyectos_eliminados)
                    proyectos_potenciales_agregar = flip(proyectos_eliminados);
                    id_eliminar = [];
                    for jj = 1:length(proyectos_potenciales_agregar)
                        id_proy_agregar = proyectos_potenciales_agregar(jj);
                        proy_agregar_actual = this.pAdmProy.entrega_proyecto(id_proy_agregar);
                        if strcmp(proy_agregar_actual.entrega_tipo_proyecto(), 'AS') || ...
                                strcmp(proy_agregar_actual.entrega_tipo_proyecto(), 'AT') && ...
                                proy_agregar_actual.Elemento(1).entrega_id_corredor() == 0 && ...
                                proy_agregar_actual.Elemento(1).entrega_indice_paralelo() == 1
                            id_eliminar = [id_eliminar id_proy_agregar];
                        end
                    end
                    proyectos_potenciales_agregar(ismember(proyectos_potenciales_agregar, id_eliminar)) = [];
                    
                    evaluacion_actual = pPlan.entrega_evaluacion();
                    estructura_costos_actual = pPlan.entrega_estructura_costos();
                    plan_actual = pPlan.Plan;
                    proyectos_agregados_nuevamente = [];
                    proyectos_descartados = [];
                
                    while ~isempty(proyectos_potenciales_agregar)
                        cantidad_intentos = length(proyectos_potenciales_agregar);
                        intento_paralelo_actual = 0;
                        intentos_actuales = cell(cantidad_intentos,0);
                        while intento_paralelo_actual < cantidad_intentos
                            intento_paralelo_actual = intento_paralelo_actual +1;
                            estructura_costos_actual_intento = estructura_costos_actual;

                            proy_seleccionados = this.selecciona_proyectos_a_agregar(pPlan, proyectos_potenciales_agregar(intento_paralelo_actual));
                            % proy_seleccionados.seleccionado
                            % proy_seleccionados.primera_etapa_posible = [];
                            % proy_seleccionados.proy_conect_agregar = [];
                            % proy_seleccionados.proy_conect_adelantar = [];
                            % proy_seleccionados.etapas_orig_conect_adelantar = [];


                            if proy_seleccionados.primera_etapa_posible == 0
                                intentos_actuales{intento_paralelo_actual}.Valido = false;
                                intentos_actuales{intento_paralelo_actual}.proy_seleccionados = proy_seleccionados;
                                intentos_actuales{intento_paralelo_actual}.Totex = 999999999999999999999;
                                continue;
                            end

                            intentos_actuales{intento_paralelo_actual}.proy_seleccionados = proy_seleccionados;
                            intentos_actuales{intento_paralelo_actual}.Totex = 999999999999999999999;
                            intentos_actuales{intento_paralelo_actual}.Valido = false;
                            intentos_actuales{intento_paralelo_actual}.Plan = [];
                            %intentos_actuales{intento_paralelo_actual}.estructura_costos_actual = [];
                            %intentos_actuales{intento_paralelo_actual}.evaluacion_actual = [];
                
                            nro_etapa = cantidad_etapas +1;
                            flag_salida = false;
                            max_cant_intentos_fallidos_agrega = max_cant_intentos_fallidos_adelanta;
                            cant_intentos_fallidos_agrega = 0;
                            cant_intentos_agrega = 0;
                            ultimo_totex_agrega = estructura_costos_actual.TotexTotal;
                
                            while nro_etapa > proy_seleccionados.primera_etapa_posible && ~flag_salida
                                nro_etapa = nro_etapa - 1;
                                cant_intentos_agrega = cant_intentos_agrega + 1;
                                % agrega proyectos en sep actual en
                                % etapa actual
                                for k = 1:length(proy_seleccionados.proy_conect_adelantar)
                                    if nro_etapa < proy_seleccionados.etapas_orig_conect_adelantar (k) 
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionados.proy_conect_adelantar(k));
                                        sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                        pPlan.adelanta_proyectos(proy_seleccionados.proy_conect_adelantar(k), nro_etapa + 1, nro_etapa);
                                    end
                                end

                                for k = 1:length(proy_seleccionados.proy_conect_agregar)
                                    proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionados.proy_conect_agregar(k));
                                    sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    if nro_etapa == this.pParOpt.CantidadEtapas
                                        pPlan.agrega_proyecto(nro_etapa, proy_seleccionados.proy_conect_agregar(k));
                                    else
                                        pPlan.adelanta_proyectos(proy_seleccionados.proy_conect_agregar(k), nro_etapa + 1, nro_etapa);
                                    end
                                end
                                proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionados.seleccionado);
                                sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                if nro_etapa == this.pParOpt.CantidadEtapas
                                    pPlan.agrega_proyecto(nro_etapa, proy_seleccionados.seleccionado);
                                else
                                    pPlan.adelanta_proyectos(proy_seleccionados.seleccionado, nro_etapa + 1, nro_etapa);
                                end
                                %evalua red (proyectos ya se ingresaron
                                %al sep)
                                if nivel_debug > 1
                                    tinic_debug = toc;
                                end
                                
                                sep_actuales{nro_etapa}.entrega_opf().calcula_despacho_economico();
                                this.evalua_resultado_y_guarda_en_plan(pPlan, sep_actuales{nro_etapa}.entrega_opf().entrega_evaluacion(), nro_etapa);
                                this.calcula_costos_totales(pPlan);

                                if nivel_debug > 1
                                    tiempos_computo_opf(end+1) = toc-tinic_debug;
                                end
                                
                                ultima_etapa_evaluada = nro_etapa;
                                
                                if cant_intentos_agrega == 1
                                    delta_actual_agrega = pPlan.entrega_totex_total()-ultimo_totex_agrega;
                                else
                                    delta_nuevo_agrega = pPlan.entrega_totex_total()-ultimo_totex_agrega;
                                    if delta_nuevo_agrega > 0 && delta_nuevo_agrega > delta_actual_agrega
                                        cant_intentos_fallidos_agrega = cant_intentos_fallidos_agrega + 1;
                                    elseif delta_nuevo_agrega < 0
                                        cant_intentos_fallidos_agrega = 0;
                                    end
                                    delta_actual_agrega = delta_nuevo_agrega;
                                end
                                ultimo_totex_agrega = pPlan.entrega_totex_total();

                                if pPlan.entrega_totex_total() < estructura_costos_actual_intento.TotexTotal
                                    % adelantar el proyecto produce
                                    % mejora. Se guarda resultado
                                    estructura_costos_actual_intento = pPlan.entrega_estructura_costos();
                                    evaluacion_actual_intento = pPlan.entrega_evaluacion();

                                    intentos_actuales{intento_paralelo_actual}.Plan = pPlan.Plan;
                                    intentos_actuales{intento_paralelo_actual}.estructura_costos_actual = estructura_costos_actual_intento;
                                    intentos_actuales{intento_paralelo_actual}.evaluacion_actual = evaluacion_actual_intento;
                                    intentos_actuales{intento_paralelo_actual}.Valido = true;
                                    intentos_actuales{intento_paralelo_actual}.Totex = estructura_costos_actual_intento.TotexTotal;
                                    intentos_actuales{intento_paralelo_actual}.PlanActualHastaEtapa = nro_etapa;
                                else
                                    if nivel_debug > 1                                        
                                        texto = ['      Adelantar proyecto de etapa ' num2str(nro_etapa+1) ' a ' num2str(nro_etapa) ...
                                            ' no genera mejora. Totex actual etapa: ' num2str(pPlan.entrega_totex_total()) ...
                                            ' Delta actual adelanta: ' num2str(delta_actual_agrega) ...
                                            ' Cant. intentos fallidos adelanta: ' num2str(cant_intentos_fallidos_agrega)];
                                        fprintf(doc_id, strcat(texto, '\n'));
                                    end
                                    % se verifica si se alcanzó el máximo número de intentos fallidos adelanta
                                    if cant_intentos_fallidos_agrega >= max_cant_intentos_fallidos_agrega
                                        flag_salida = true;
                                    end
                                end
                            end

                            % se deshacen los cambios en el sep
                            pPlan.Plan = plan_actual;
                            pPlan.inserta_estructura_costos(estructura_costos_actual);
                            pPlan.inserta_evaluacion(evaluacion_actual);

                            for nro_etapa = ultima_etapa_evaluada:cantidad_etapas
                                % deshace los cambios hechos en los sep
                                % actuales hasta la etapa correcta
                                % Ojo! orden inverso entre desplaza y
                                % elimina proyectos!
                                proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionados.seleccionado);
                                sep_actuales{nro_etapa}.elimina_proyecto(proyecto);

                                for k = length(proy_seleccionados.proy_conect_agregar):-1:1
                                    proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionados.proy_conect_agregar(k));
                                    sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                end

                                for k = length(proy_seleccionados.proy_conect_adelantar):-1:1
                                    if nro_etapa < proy_seleccionados.etapas_orig_conect_adelantar(k) 
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionados.proy_conect_adelantar(k));
                                        sep_actuales{nro_etapa}.elimina_proyecto(proyecto);
                                    end
                                end
                            end
                        end
                        % determina mejor intento
                        existe_mejora = false;
                        mejor_totex = 0;
                        id_mejor_plan_intento = 0;
                        for kk = 1:cantidad_intentos
                            if intentos_actuales{kk}.Valido
                                existe_mejora = true;
                                if id_mejor_plan_intento == 0
                                    id_mejor_plan_intento = kk;
                                    mejor_totex = intentos_actuales{kk}.Totex;
                                elseif intentos_actuales{kk}.Totex < mejor_totex 
                                    id_mejor_plan_intento = kk;
                                    mejor_totex = intentos_actuales{kk}.Totex;
                                end
                                if nivel_debug > 1                                    
                                    proyectos_agregar = [intentos_actuales{kk}.proy_seleccionados.proy_conect_agregar intentos_actuales{kk}.proy_seleccionados.proy_conect_adelantar intentos_actuales{kk}.proy_seleccionados.seleccionado];
                                    texto = ['      Intento ' num2str(kk) ' es valido' ...
                                             '. Totex intento: ' num2str(intentos_actuales{kk}.Totex) '. Proyectos agregar: '];
                                    for oo = 1:length(proyectos_agregar)
                                        texto = [texto ' ' num2str(proyectos_agregar(oo))];
                                    end
                                    fprintf(doc_id, strcat(texto, '\n'));
                                end
                            else
                                % intento no fue válido. Se elimina
                                % proyecto de la lista a agregar y también
                                % proyectos dependientes que estén en lista
                                if nivel_debug > 1
                                    proyectos_agregar = [intentos_actuales{kk}.proy_seleccionados.proy_conect_agregar intentos_actuales{kk}.proy_seleccionados.proy_conect_adelantar intentos_actuales{kk}.proy_seleccionados.seleccionado];
                                    texto = ['      Intento ' num2str(kk) ' no valido' ...
                                             '. Totex intento: ' num2str(intentos_actuales{kk}.Totex) '. Proyectos agregar: '];
                                    for oo = 1:length(proyectos_agregar)
                                        texto = [texto ' ' num2str(proyectos_agregar(oo))];
                                    end
                                    fprintf(doc_id, strcat(texto, '\n'));
                                end
                                proyectos_potenciales_agregar(proyectos_potenciales_agregar == intentos_actuales{kk}.proy_seleccionados.seleccionado) = [];
                                for ii = 1:length(proyectos_potenciales_agregar)
                                    proy_lista = this.pAdmProy.entrega_proyecto(proyectos_potenciales_agregar(ii));
                                    if proy_lista.TieneDependencia
                                        for dep = 1:length(proy_lista.ProyectoDependiente)
                                            id_proy_dep = proy_lista.ProyectoDependiente(dep).Indice;
                                            if id_proy_dep == intentos_actuales{kk}.proy_seleccionados.seleccionado
                                                proyectos_potenciales_agregar(proyectos_potenciales_agregar == id_proy_dep) = [];
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        
                        if existe_mejora
                            if nivel_debug > 1
                                texto = ['      Mejor intento: ' num2str(id_mejor_plan_intento)];
                                fprintf(doc_id, strcat(texto, '\n'));
                            end

                            plan_actual = intentos_actuales{id_mejor_plan_intento}.Plan;
                            evaluacion_actual = intentos_actuales{id_mejor_plan_intento}.evaluacion_actual;
                            estructura_costos_actual = intentos_actuales{id_mejor_plan_intento}.estructura_costos_actual;
                            pPlan.Plan = plan_actual;
                            pPlan.inserta_estructura_costos(estructura_costos_actual);
                            pPlan.inserta_evaluacion(evaluacion_actual);

                            proy_seleccionados = intentos_actuales{id_mejor_plan_intento}.proy_seleccionados;                            
                            proyectos_agregados_nuevamente = [proyectos_agregados_nuevamente proy_seleccionados.seleccionado];
                            proyectos_potenciales_agregar(proyectos_potenciales_agregar == proy_seleccionados.seleccionado) = [];

                            % se implementa plan hasta la etapa actual del
                            % mejor intento
                            ultima_etapa_valida_intento = intentos_actuales{id_mejor_plan_intento}.PlanActualHastaEtapa;
                            for nro_etapa = ultima_etapa_valida_intento:cantidad_etapas
                                % agrega proyectos en sep actual en
                                % etapa actual
                                for k = 1:length(proy_seleccionados.proy_conect_adelantar)
                                    if nro_etapa < proy_seleccionados.etapas_orig_conect_adelantar (k) 
                                        proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionados.proy_conect_adelantar(k));
                                        sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                    end
                                end

                                for k = 1:length(proy_seleccionados.proy_conect_agregar)
                                    proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionados.proy_conect_agregar(k));
                                    sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                                end
                                proyecto = this.pAdmProy.entrega_proyecto(proy_seleccionados.seleccionado);
                                sep_actuales{nro_etapa}.agrega_proyecto(proyecto);
                            end
                        else
                            if nivel_debug > 1
                                texto = '      No hubo mejora en ninguno de los intentos';
                                fprintf(doc_id, strcat(texto, '\n'));
                            end
                        end
                        if nivel_debug > 1
                            texto = '      Lista proy potenciales a agregar: ';
                            for ii = 1:length(proyectos_potenciales_agregar)
                                texto = [texto ' ' num2str(proyectos_potenciales_agregar(ii))];
                            end
                            fprintf(doc_id, strcat(texto, '\n'));

                        end

                        if nivel_debug > 1
                            texto = 'Imprime plan actual despues de los intentos';
                            fprintf(doc_id, strcat(texto, '\n'));
                            pPlan.agrega_nombre_proyectos(this.pAdmProy);
                            texto = pPlan.entrega_texto_plan_expansion();
                            fprintf(doc_id, strcat(texto, '\n'));
                            
                        end
                    end

                    if nivel_debug > 1
                        totex_despues_de_nuevo_agrega = pPlan.entrega_totex_total();
                        cantidad_proy_despues_de_nuevo_agrega = pPlan.cantidad_acumulada_proyectos();

                        texto = 'Fin agrega proyectos eliminados';
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = 'Proyectos agregados nuevamente:';
                        for ii = 1:length(proyectos_agregados_nuevamente)
                            texto = [texto ' ' num2str(proyectos_agregados_nuevamente(ii))];
                        end
                        fprintf(doc_id, strcat(texto, '\n'));

                        texto = sprintf('%-15s %-10s %-10s', ' ', 'No proy', 'Totex');
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = sprintf('%-15s %-10s %-10s', 'Original', num2str(cantidad_proy_orig), num2str(totex_orig));
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = sprintf('%-15s %-10s %-10s', 'Elimina', num2str(cantidad_proy_despues_de_elimina), num2str(totex_despues_de_elimina));
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = sprintf('%-15s %-10s %-10s', 'Desplaza', num2str(cantidad_proy_despues_de_nuevo_desplaza), num2str(totex_despues_de_nuevo_desplaza));
                        fprintf(doc_id, strcat(texto, '\n'));
                        texto = sprintf('%-15s %-10s %-10s', 'Agrega', num2str(cantidad_proy_despues_de_nuevo_agrega), num2str(totex_despues_de_nuevo_agrega));
                        fprintf(doc_id, strcat(texto, '\n'));
                    end
                end
                                
                % fin busqueda local

                planes_validos{nro_plan} = pPlan;

  
                % limpia la memoria para plan actual
                for nro_etapa = 1:cantidad_etapas
                	sep_actuales{nro_etapa} = cSistemaElectricoPotencia.empty;
                end
                if nivel_debug > 1
                    texto = 'Fin busqueda local elimina desplaza';
                    fprintf(doc_id, strcat(texto, '\n'));

                    texto = ['Cantidad computos opf: ' num2str(length(tiempos_computo_opf))];
                    fprintf(doc_id, strcat(texto, '\n'));
                    texto = 'Tiempos de computo OPF:';
                    fprintf(doc_id, strcat(texto, '\n'));
                    for i = 1:length(tiempos_computo_opf)
                        fprintf(doc_id, strcat(num2str(tiempos_computo_opf(i)), '\n'));
                    end
                        
                    fclose(doc_id);
                end
if nivel_debug > 0
   disp(['dt bl = ' num2str(toc)])
end
            end % fin parfor

            % guarda planes generados
            for i = 1:length(planes_validos)
                if ~isempty(planes_validos{i})
                    cantidad_planes_generados = cantidad_planes_generados + 1;
                    planes_generados{cantidad_planes_generados} = planes_validos{i};
                    this.CantPlanesValidos = this.CantPlanesValidos + 1;
                    
                    if nivel_debug > 2                        
                        plan_debug = cPlanExpansion(888888889);
                        plan_debug.Plan = planes_validos{i}.Plan;
                        plan_debug.inserta_sep_original(this.pSEP.crea_copia());
                        for etapa_ii = 1:this.pParOpt.CantidadEtapas

                            valido = this.evalua_plan(plan_debug, etapa_ii, 0);
                            if ~valido
                                error = MException('cOptACO:genera_planes_bl_elimina_desplaza_paralelo',...
                                ['Error. Plan debug no es valido en etapa ' num2str(etapa_ii)]);
                                throw(error)
                            end
                        end
                        this.calcula_costos_totales(plan_debug);
                        if round(plan_debug.entrega_totex_total(),2) ~= round(planes_validos{i}.entrega_totex_total(),2)
                            prot = cProtocolo.getInstance;
                            texto = 'Totex total de plan debug es distinto de totex total de plan actual!';
                            prot.imprime_texto(texto);
                            texto = ['Totex total plan debug: ' num2str(round(plan_debug.entrega_totex_total(),3))];
                            prot.imprime_texto(texto);
                            texto = ['Totex total plan actual: ' num2str(round(planes_validos{i}.entrega_totex_total(),3))];
                            prot.imprime_texto(texto);

                            prot.imprime_texto('Se imprime plan valido calculado');
                            planes_validos{i}.imprime();

                            prot.imprime_texto('Se imprime plan debug');
                            plan_debug.imprime();
                            
                            prot.imprime_texto('Se imprime plan original');
                            id_plan_orig = mod(i,cantidad_planes_originales);
                            if id_plan_orig == 0
                                id_plan_orig = cantidad_planes_originales;
                            end
                            plan_orig = planes_originales(id_plan_orig);
                            plan_orig.imprime();
                            
                            texto_error = 'Totex total de plan debug es distinto de totex total de plan actual!';
                            texto_error = [texto_error ' Totex total plan debug: ' num2str(round(plan_debug.entrega_totex_total(),3))];
                            texto_error = [texto_error 'Totex total plan actual: ' num2str(round(planes_validos{i}.entrega_totex_total(),3))];
                            error = MException('cOptACO:genera_planes_bl_elimina_desplaza_paralelo',texto_error);
                            throw(error)
                        end
                    end
                    
                end
            end
            
            %imprime planes procesos fallidos
            for i = 1:length(procesos_fallidos)
                if ~isempty(procesos_fallidos{i})
                    for j = 1:length(procesos_fallidos{i})
                        plan_falla = cPlanExpansion(77777777777);
                        plan_falla.Plan = procesos_fallidos{i}(j);
                        prot = cProtocolo.getInstance;
                        prot.imprime_texto(['Se imprime plan fallido con proceso paralelo ' num2str(i)]);
                        plan_falla.imprime();
                    end
                end
            end
            indice = indice_planes_base + cantidad_planes;
% this.iNivelDebug = 1;
% this.pAdmProy.iNivelDebug = 0;
        end

        function plan = genera_plan_mas_probable(this, indice, delta_feromonas)
            % genera plan en base a feromonas actuales
            cant_proy_obligatorios = length(this.pAdmProy.ProyectosObligatorios);
            if cant_proy_obligatorios > 0
                planes_obligatorios_generados = false;
            else
                planes_obligatorios_generados = true;
            end
            
            plan = cPlanExpansion(indice);
            proyectos_totales = [];
            cantidad_etapas = this.pParOpt.CantidadEtapas;
            for nro_etapa = 1:cantidad_etapas
                plan.inicializa_etapa(nro_etapa);
            end
            
            %primero determina si hay que seleccionar proyectos
            %obligatorios
            cant_proy_obligatorios = length(this.pAdmProy.ProyectosObligatorios);
            if delta_feromonas
                dfer_actual = sum(this.pFeromona.DFerActual(1:end-1, :));
                indices_delta_pos_restringidos = dfer_actual == 0;
                proyectos_restringidos = indices_delta_pos_restringidos;
            else
                proyectos_restringidos = [];
            end
            if cant_proy_obligatorios > 0
                espacio_busqueda = this.pAdmProy.entrega_indices_proyectos_obligatorios(cant_proy_obligatorios); %parte con el último grupo de proyectos obligatorios
                if delta_feromonas
                    espacio_busqueda(ismember(espacio_busqueda, proyectos_restringidos)) = [];
                end
            else
                [espacio_busqueda, primeras_etapas_posibles] = this.pAdmProy.determina_espacio_busqueda(plan, proyectos_restringidos);
            end

            cantidad_proyectos_seleccionados = 0;
            while (cant_proy_obligatorios > 0) || ~isempty(espacio_busqueda)
            	%primero calcula probabilidad relativa entre los proyectos del espacio de búsqueda de que se construyan 

                if cant_proy_obligatorios > 0
                    if delta_feromonas
                        prob_construccion = this.pFeromona.entrega_delta_feromonas_acumuladas_hasta_etapa(1, espacio_busqueda); 
                    else
                        prob_construccion = this.pFeromona.entrega_feromonas_acumuladas_hasta_etapa(1, espacio_busqueda); % proyecto con mayor prob. a construirse en etapa 1
                    end
                else
                    if delta_feromonas
                        prob_construccion = this.pFeromona.entrega_delta_feromonas_acumuladas_hasta_etapa(cantidad_etapas, espacio_busqueda); % proyecto con mayor prob. de construirse (en general)
                    else
                        prob_construccion = this.pFeromona.entrega_feromonas_acumuladas_hasta_etapa(cantidad_etapas, espacio_busqueda); % proyecto con mayor prob. de construirse (en general)
                    end

                end
                prob_construccion = prob_construccion / sum(prob_construccion);
                [~, indice] = max(prob_construccion);                    
                
                proyecto_seleccionado = espacio_busqueda(indice);
                
                % selecciona etapa en proyecto seleccionado (puede ser
                % cero!)
                if cant_proy_obligatorios > 0
                    etapa = 1;
                else
                    primera_etapa_posible = primeras_etapas_posibles(indice);
                    if delta_feromonas
                        fer_etapa = this.pFeromona.entrega_delta_feromonas_proyecto(proyecto_seleccionado);
                    else
                        fer_etapa = this.pFeromona.entrega_feromonas_proyecto(proyecto_seleccionado);
                    end
                    % determina si se construye o no, y en qué etapa
                    if sum(fer_etapa(1:end-1)) > fer_etapa(end)
                        [~, etapa] = max(fer_etapa(1:end-1));
                        if etapa < primera_etapa_posible
                            etapa = primera_etapa_posible;
                        end
                    else
                        etapa = 0;
                    end
                end
                
                if etapa > 0
                    % proyecto se construye. Verifica conectividad
                    proy_conectividad = [];
                    if this.pAdmProy.Proyectos(proyecto_seleccionado).TieneRequisitosConectividad
                        cantidad_req_conectividad = this.pAdmProy.Proyectos(proyecto_seleccionado).entrega_cantidad_grupos_conectividad();
                        for ii = 1:cantidad_req_conectividad
                        	indices_proy_conect = this.pAdmProy.Proyectos(proyecto_seleccionado).entrega_indices_grupo_proyectos_conectividad(ii);
                            [id_conect_existente, etapa_conect_existente] = plan.entrega_conectividad_existente_con_etapa(indices_proy_conect);                            
                            if id_conect_existente == 0
                                % no existen las conectividades
                                if length(indices_proy_conect) > 1
                                    if delta_feromonas
                                        prob_construccion = this.pFeromona.entrega_delta_feromonas_acumuladas_hasta_etapa(etapa, indices_proy_conect); % proyecto con mayor prob. a construirse en etapa 1
                                    else
                                        prob_construccion = this.pFeromona.entrega_feromonas_acumuladas_hasta_etapa(etapa, indices_proy_conect); % proyecto con mayor prob. a construirse en etapa 1
                                    end
                                    [~, ubic_conectividad] = max(prob_construccion);
                                    id_conectividad = indices_proy_conect(ubic_conectividad);
                                else
                                    id_conectividad = indices_proy_conect;
                                end
                                proy_conectividad = [proy_conectividad id_conectividad];
                            else
                               % hay que asegurar que conectividad se
                               % encuentre en la etapa de entrada del
                               % proyecto
                               if etapa_conect_existente > etapa
                                   plan.adelanta_proyectos(id_conect_existente, etapa_conect_existente, etapa);
                               end
                            end                            
                        end
                    end
                    proyectos_seleccionados = [proy_conectividad proyecto_seleccionado];
                    % agrega proyectos en etapa
                    for i = 1:length(proyectos_seleccionados)
                        plan.agrega_proyecto(etapa, proyectos_seleccionados(i));
                        cantidad_proyectos_seleccionados = cantidad_proyectos_seleccionados + 1;
                    end                    
                else
                    proyectos_restringidos = [proyectos_restringidos proyecto_seleccionado]; % ya se determinó que no se construye
                end
                
                cant_proy_obligatorios = cant_proy_obligatorios - 1;
                if cant_proy_obligatorios > 0
                    espacio_busqueda = this.pAdmProy.ProyectosObligatorios(cant_proy_obligatorios).Indice;
                else
                    [espacio_busqueda, primeras_etapas_posibles] = this.pAdmProy.determina_espacio_busqueda(plan, proyectos_restringidos);
                end
            end
            
            if this.iNivelDebug > 0
            	prot = cProtocolo.getInstance;
                prot.imprime_texto('Plan mas probable:');
                %plan.agrega_nombre_proyectos(this.pAdmProy);
                plan.imprime_plan_expansion();
            end            
        end

        function plan = genera_plan_feromonas_entregadas(this, indice)
            % genera plan en base a delta feromonas actuales
            cant_proy_obligatorios = length(this.pAdmProy.ProyectosObligatorios);
            if cant_proy_obligatorios > 0
                planes_obligatorios_generados = false;
            else
                planes_obligatorios_generados = true;
            end
            
            plan = cPlanExpansion(indice);
            proyectos_totales = [];
            cantidad_etapas = this.pParOpt.CantidadEtapas;
            for nro_etapa = 1:cantidad_etapas
                plan.inicializa_etapa(nro_etapa);
            end
            
            %primero determina si hay que seleccionar proyectos
            %obligatorios
            cant_proy_obligatorios = length(this.pAdmProy.ProyectosObligatorios);
            proyectos_restringidos = [];
            if cant_proy_obligatorios > 0
                espacio_busqueda = this.pAdmProy.entrega_indices_proyectos_obligatorios(cant_proy_obligatorios); %parte con el último grupo de proyectos obligatorios
                dfer_actual = this.pFeromona.DFerActual(1, espacio_busqueda);
                indices_delta_pos = dfer_actual>0;
                espacio_busqueda = espacio_busqueda(indices_delta_pos);
                dfer_espacio = dfer_actual(indices_delta_pos);
            else
                [espacio_busqueda, primeras_etapas_posibles] = this.pAdmProy.determina_espacio_busqueda(plan, proyectos_restringidos);
                dfer_actual = sum(this.pFeromona.DFerActual(1:end-1, espacio_busqueda));
                indices_delta_pos = dfer_actual>0;
                espacio_busqueda = espacio_busqueda(indices_delta_pos);
                primeras_etapas_posibles = primeras_etapas_posibles(indices_delta_pos);
                dfer_espacio = dfer_actual(indices_delta_pos);
            end

            cantidad_proyectos_seleccionados = 0;
            while (cant_proy_obligatorios > 0) || ~isempty(espacio_busqueda)
            	%primero calcula probabilidad relativa entre los proyectos del espacio de búsqueda de que se construyan 

                prob_construccion = dfer_espacio/ sum(dfer_espacio);
                [~, indice] = max(prob_construccion);                    
                
                proyecto_seleccionado = espacio_busqueda(indice);
                
                % selecciona etapa en proyecto seleccionado
                if cant_proy_obligatorios > 0
                    etapa = 1;
                else
                    primera_etapa_posible = primeras_etapas_posibles(indice);
                    fer_etapa = this.pFeromona.DFerActual(1:end-1,proyecto_seleccionado);
                    [~, etapa] = max(fer_etapa);
                    if etapa < primera_etapa_posible
                        etapa = primera_etapa_posible;
                    end
                end
                
                % Verifica conectividad
                proy_conectividad = [];
                if this.pAdmProy.Proyectos(proyecto_seleccionado).TieneRequisitosConectividad
                    cantidad_req_conectividad = this.pAdmProy.Proyectos(proyecto_seleccionado).entrega_cantidad_grupos_conectividad();
                    for ii = 1:cantidad_req_conectividad
                        indices_proy_conect = this.pAdmProy.Proyectos(proyecto_seleccionado).entrega_indices_grupo_proyectos_conectividad(ii);
                        [id_conect_existente, etapa_conect_existente] = plan.entrega_conectividad_existente_con_etapa(indices_proy_conect);                            
                        if id_conect_existente == 0
                            % no existen las conectividades
                            if length(indices_proy_conect) > 1
                                prob_construccion = sum(this.pFeromona.DFerActual(1:etapa, indices_proy_conect));
                                if sum(prob_construccion) == 0
                                    prob_construccion = sum(this.pFeromona.DFerActual(1:end-1, indices_proy_conect));
                                end
                                [~, ubic_conectividad] = max(prob_construccion);
                                id_conectividad = indices_proy_conect(ubic_conectividad);
                            else
                                id_conectividad = indices_proy_conect;
                            end
                            proy_conectividad = [proy_conectividad id_conectividad];
                        else
                           % hay que asegurar que conectividad se
                           % encuentre en la etapa de entrada del
                           % proyecto
                           if etapa_conect_existente > etapa
                               plan.adelanta_proyectos(id_conect_existente, etapa_conect_existente, etapa);
                           end
                        end                            
                    end
                end
                proyectos_seleccionados = [proy_conectividad proyecto_seleccionado];
                % agrega proyectos en etapa
                for i = 1:length(proyectos_seleccionados)
                    plan.agrega_proyecto(etapa, proyectos_seleccionados(i));
                    cantidad_proyectos_seleccionados = cantidad_proyectos_seleccionados + 1;
                end                    
                
                cant_proy_obligatorios = cant_proy_obligatorios - 1;
                if cant_proy_obligatorios > 0
                    espacio_busqueda = this.pAdmProy.entrega_indices_proyectos_obligatorios(cant_proy_obligatorios); %parte con el último grupo de proyectos obligatorios
                    dfer_actual = this.pFeromona.DFerActual(1, espacio_busqueda);
                    indices_delta_pos = dfer_actual>0;
                    espacio_busqueda = espacio_busqueda(indices_delta_pos);
                    dfer_espacio = dfer_actual(indices_delta_pos);
                else
                    [espacio_busqueda, primeras_etapas_posibles] = this.pAdmProy.determina_espacio_busqueda(plan, proyectos_restringidos);
                    dfer_actual = sum(this.pFeromona.DFerActual(1:end-1, espacio_busqueda));
                    indices_delta_pos = dfer_actual>0;
                    espacio_busqueda = espacio_busqueda(indices_delta_pos);
                    primeras_etapas_posibles = primeras_etapas_posibles(indices_delta_pos);
                    dfer_espacio = dfer_actual(indices_delta_pos);
                end
            end
            
            if this.iNivelDebug > 0
            	prot = cProtocolo.getInstance;
                prot.imprime_texto('Plan delta feromonas:');
                %plan.agrega_nombre_proyectos(this.pAdmProy);
                plan.imprime_plan_expansion();
            end            
        end
        
        function evalua_red(this, sep, nro_etapa, indice_proyectos, agrega_proyectos)
            if this.iNivelDebug > 1
            	prot = cProtocolo.getInstance;
            end
            
            for k = 1:length(indice_proyectos)
                %agrega proyecto al SEP
                proyecto = this.pAdmProy.entrega_proyecto(indice_proyectos(k));
                if agrega_proyectos
                    correcto = sep.agrega_proyecto(proyecto);
                else
                    correcto = sep.elimina_proyecto(proyecto);
                end
                
                if this.iNivelDebug > 2
                    if agrega_proyectos
                        texto = ['      Evalua red. Agrega proyecto ' num2str(proyecto.entrega_indice()) ': ' proyecto.entrega_nombre()];
                    else
                        texto = ['      Evalua red. Elimina proyecto ' num2str(proyecto.entrega_indice()) ': ' proyecto.entrega_nombre()];
                    end
                    prot.imprime_texto(texto);
                end
                if ~correcto
                	% Error (probablemente de programación). 
                    if this.iNivelDebug > 1
                        texto = ['Error de programacion. Proyecto ' num2str(indice_proyectos(k)) ' no pudo se implementado/eliminado en etapa ' num2str(nro_etapa)];
                        prot.imprime_texto(texto);
                    end
                    error = MException('cOptACO:evalua_red','No se pudo agregar/eliminar proyecto al SEP. Detalles en protocolo');
                    throw(error)
                end
            end
            
            pOPF = sep.entrega_opf();
            if isempty(pOPF)
                if this.iNivelDebug > 2
                    texto = '      OPF no está creado. Se crea';
                    prot.imprime_texto(texto);
                end

                if strcmp(this.pParOpt.TipoFlujoPotencia, 'DC')
                	pOPF = cDCOPF(sep, this.pAdmSc, this.pParOpt);
                    pOPF.inserta_resultados_en_sep(false);
                else
                	error = MException('cOptACO:evalua_red','solo flujo DC implementado');
                    throw(error)
                end
            
                nivel_debug = this.pParOpt.NivelDebugOPF;
                pOPF.inserta_nivel_debug(nivel_debug);
                pOPF.inserta_etapa(nro_etapa);
            else
                if this.iNivelDebug > 2
                    texto = '      OPF existe. No se hace nada';
                    prot.imprime_texto(texto);
                end
                
                if pOPF.entrega_etapa() ~= nro_etapa
                    if this.iNivelDebug > 2
                        texto = ['      Se actualiza etapa OPF desde etapa ' num2str(pOPF.entrega_etapa()) ' a etapa ' num2str(nro_etapa)];
                        prot.imprime_texto(texto);
                    end    
                    pOPF.actualiza_etapa(nro_etapa);
                end
            end
            
            pOPF.calcula_despacho_economico();
        end

        function evalua_red_computo_paralelo(this, sep, nro_etapa, puntos_operacion, datos_escenario, sbase, indice_proyectos, agrega_proyectos)
%if this.iNivelDebug > 0
%	prot = cProtocolo.getInstance;
%end
            
            for k = 1:length(indice_proyectos)
                %agrega proyecto al SEP
                proyecto = this.pAdmProy.entrega_proyecto(indice_proyectos(k));
                if agrega_proyectos
                    correcto = sep.agrega_proyecto(proyecto);
                else
                    correcto = sep.elimina_proyecto(proyecto);
                end
                if ~correcto
                	% Error (probablemente de programación). 
%if this.iNivelDebug > 0
%	texto = ['Error de programacion. Proyecto ' num2str(indice_proyectos(k)) ' no pudo se implementado en etapa ' num2str(nro_etapa)];
%    prot.imprime_texto(texto);
%end
                    error = MException('cOptACO:evalua_red_computo_paralelo','No se pudo agregar/eliminar proyecto al SEP. Detalles en protocolo');
                    throw(error)
                end
            end
            
            pOPF = sep.entrega_opf();
            if isempty(pOPF)
                if strcmp(this.pParOpt.TipoFlujoPotencia, 'DC')
                    pOPF = cDCOPF(sep);
                    pOPF.copia_parametros_optimizacion(this.pParOpt);
                    pOPF.inserta_puntos_operacion(puntos_operacion);
                    pOPF.inserta_datos_escenario(datos_escenario);
                    pOPF.inserta_etapa_datos_escenario(nro_etapa);
                    pOPF.inserta_sbase(sbase);
                    pOPF.inserta_resultados_en_sep(false);
                else
                	error = MException('cOptACO:evalua_red_computo_paralelo','solo flujo DC implementado');
                    throw(error)
                end
            
%                pOPF.inserta_nivel_debug(0);  
            else
                if pOPF.entrega_etapa_datos_escenario() ~= nro_etapa
                    pOPF.inserta_puntos_operacion(puntos_operacion);
                    pOPF.inserta_datos_escenario(datos_escenario);
                    pOPF.inserta_etapa_datos_escenario(nro_etapa);
                    pOPF.actualiza_etapa(nro_etapa);
                end
            end
            
            pOPF.calcula_despacho_economico();
        end
        
        function guarda_parametros_optimizacion(this)
            this.Resultados.Parametros.CantidadHormigas = this.pParOpt.CantidadHormigas;
            this.Resultados.Parametros.CantidadPlanesBusquedaLocal = this.pParOpt.CantidadPlanesBusquedaLocal;
            this.Resultados.Parametros.TasaEvaporacion = this.pParOpt.TasaEvaporacion;
            this.Resultados.Parametros.CantidadMejoresPlanes = this.pParOpt.CantidadMejoresPlanes;
            this.Resultados.Parametros.FactorAlfa = this.pParOpt.FactorAlfa;
            this.Resultados.Parametros.MaxFeromona = this.pParOpt.MaxFeromona;
            this.Resultados.Parametros.BLEliminaDesplazaProyectos = this.pParOpt.BLEliminaDesplazaProyectos;
            this.Resultados.Parametros.BLAgregaProyectosFormaSecuencialCompleto = this.pParOpt.BLAgregaProyectosFormaSecuencialCompleto;
        end
        
        function guarda_estadistica_iteracion(this, nro_iteracion)
            %mejor plan iteracion
            this.Resultados.COperTotalMejor = this.PlanesValidosPorIteracion(nro_iteracion).Planes(1).COperTotal;
            this.Resultados.CInvTotalMejor = this.PlanesValidosPorIteracion(nro_iteracion).Planes(1).CInvTotal;
            this.Resultados.TotexTotal = this.PlanesValidosPorIteracion(nro_iteracion).Planes(1).TotexTotal;
            
            %limite de planes que entregan feromonas
            this.Resultados.COperLimiteMejoresPlanes = this.MejoresPlanes(end).COperTotal;
            this.Resultados.CInvLimiteMejoresPlanes = this.MejoresPlanes(end).CInvTotal;
            this.Resultados.CTotexLimiteMejoresPlanes = this.MejoresPlanes(end).TotexTotal;
            
            %promedio iteracion
            ctotex = 0;
            for i = 1:length(this.PlanesValidosPorIteracion(nro_iteracion).Planes)
                ctotex = ctotex + this.PlanesValidosPorIteracion(nro_iteracion).Planes(i).TotexTotal;
            end
            this.Resultados.CTotexPromedio = ctotex / length(this.PlanesValidosPorIteracion(nro_iteracion).Planes);
            
            %maximo
            this.Resultados.CTotexMax = this.PlanesValidosPorIteracion(nro_iteracion).Planes(end).TotexTotal;
        end
        
        function planes_orig = entrega_planes_busqueda_local(this, nro_iteracion)
            cantidad_planes_busqueda_local = this.pParOpt.CantidadPlanesBusquedaLocal;

            planes = this.PlanesValidosPorIteracion(nro_iteracion).Planes;
            [~,indice]=sort([planes.TotexTotal]);
            planes = planes(indice);
            planes_orig = planes(1);
            for i = 2:length(planes)
                existe = false;
                for j = 1:length(planes_orig)
                    if planes(i).compara_proyectos(planes_orig(j));
                        existe = true;
                        break;
                    end
                end
                if ~existe
                    planes_orig = [planes_orig planes(i)];
                end
                if length(planes_orig) == cantidad_planes_busqueda_local
                    break;
                end
            end
        end
                
        function inicializa_contenedores_iteracion(this, nro_iteracion)
            this.PlanesValidosPorIteracion(nro_iteracion).Planes = cPlanExpansion.empty;
            this.PlanesValidosPorIteracionBase(nro_iteracion).Planes = cPlanExpansion.empty;
            this.PlanesValidosPorIteracionBL(nro_iteracion).Planes = cPlanExpansion.empty;

            this.PlanesValidosPorIteracionBLEliminaDesplaza(nro_iteracion).Planes = cPlanExpansion.empty;
            this.PlanesValidosPorIteracionBLSecuencialCompleto(nro_iteracion).Planes = cPlanExpansion.empty;
        end
        
        function guarda_resultados_iteracion(this, nro_iteracion)
            this.guarda_estadistica_iteracion(nro_iteracion);
            this.Resultados.MejorResultadoIteracion(nro_iteracion) = this.ValorMejorResultado(nro_iteracion);
            this.Resultados.MejorResultadoGlobal(nro_iteracion) = this.MejoresPlanes(1).TotexTotal;
            this.Resultados.CantidadPlanesValidos(nro_iteracion) = length(this.PlanesValidosPorIteracion(nro_iteracion).Planes);
            this.Resultados.CantidadPlanesValidosBL(nro_iteracion) = length(this.PlanesValidosPorIteracionBL(nro_iteracion).Planes);
            this.Resultados.CantidadPlanesValidosBLEliminaDesplaza(nro_iteracion) = length(this.PlanesValidosPorIteracionBLEliminaDesplaza(nro_iteracion).Planes);
            this.Resultados.CantidadPlanesValidosBLSecuencialCompleto(nro_iteracion) = length(this.PlanesValidosPorIteracionBLSecuencialCompleto(nro_iteracion).Planes);
        end
        
        function crea_plan_optimo(this, data)
            this.PlanOptimo = cPlanExpansion(9999999);
            [~, m] = size(data.Plan);
            for etapa = 1:this.pParOpt.CantidadEtapas
                if data.Plan(etapa,1) ~= etapa
                    error = MException('cOptACO:crea_plan_optimo','Error. Formato de datos es antiguo. Corregir');
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
            this.PlanEvaluar = cPlanExpansion(9999998);
            [~, m] = size(data.PlanEvaluar);
            for etapa = 1:this.pParOpt.CantidadEtapas
                if data.PlanEvaluar(etapa,1) ~= etapa
                    error = MException('cOptACO:crea_plan_evaluar','Error. Formato de datos es antiguo. Corregir');
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
            this.PlanEvaluar.Plan = plan.Plan;
            this.PlanEvaluar.agrega_nombre_proyectos(this.pAdmProy);
            this.PlanEvaluar.inserta_sep_original(this.pSEP);            
        end
        
        function plan = entrega_plan_evaluar(this)
            plan = this.PlanEvaluar;
        end
        
        function evalua_plan_optimo(this, varargin)
            % varargin indica si se imprime o no el resultado del OPF por
            % etapas
            if nargin > 1
                detallado = varargin{1};
            else
                detallado = false;
            end
            
            for etapa = 1:this.pParOpt.CantidadEtapas
                valido = this.evalua_plan(this.PlanOptimo, etapa, 0);
                if ~valido
                    error = MException('cOptACO:evalua_plan_optimo',...
                        ['Error. Plan optimo no es valido en etapa ' num2str(etapa)]);
                    throw(error)
                end
                
                if detallado
                    sep_plan = this.PlanOptimo.entrega_sep_actual();
                    eval = sep_plan.entrega_opf().entrega_evaluacion();
                    eval.inserta_administrador_escenarios(this.pAdmSc)
                    eval.inserta_etapa(etapa);
                    eval.imprime_resultados(['Evaluacion plan optimo en etapa ' num2str(etapa)]);
                end
            end
            this.calcula_costos_totales(this.PlanOptimo);
        end

        function evalua_plan_evaluar(this)
            for etapa = 1:this.pParOpt.CantidadEtapas
                valido = this.evalua_plan(this.PlanEvaluar, etapa, 0);
                %if ~valido
                %    error = MException('cOptACO:evalua_plan_evaluar',...
                %        ['Error. Plan a evaluar no es valido en etapa ' num2str(etapa)]);
                %    throw(error)
                %end                
            end
            this.calcula_costos_totales(this.PlanEvaluar);
        end
        
        function guarda_planes_generados(this, planes, nro_iteracion, tipo)
            for i = 1:length(planes)
                planes{i}.ResultadoEvaluacion = [];
                this.guarda_plan(planes{i}, nro_iteracion, tipo); 

                this.CantPlanesValidos = this.CantPlanesValidos + 1;
                if this.iNivelDebug > 1
                    prot = cProtocolo.getInstance;
                    texto = ['   Plan tipo ' num2str(tipo) ' numero ' num2str(planes{i}.entrega_no()) ' Es valido'];
                    prot.imprime_texto(texto);
                end
            end
        end 
        
        function plan = entrega_plan_optimo(this)
            plan = this.PlanOptimo;
        end
        
        function carga_resultados_parciales(this, resultados_parciales_it, max_iter)
            this.verifica_y_guarda_parametros(resultados_parciales_it);
            
%            this.iNivelDebug = 0;
            tope = min(length(resultados_parciales_it.PlanesValidosPorIteracion), max_iter);
            this.ExistenResultadosParciales = true;
            this.ItResultadosParciales = tope;

            this.CantPlanesValidos = 0;
            for i = 1:tope
disp(['Carga resultados iteracion ' num2str(i)])

                this.PlanesValidosPorIteracion(i).Planes = resultados_parciales_it.PlanesValidosPorIteracion(i).Planes;
                this.PlanesValidosPorIteracionBase(i).Planes = resultados_parciales_it.PlanesValidosPorIteracionBase(i).Planes;
                this.PlanesValidosPorIteracionBL(i).Planes = resultados_parciales_it.PlanesValidosPorIteracionBL(i).Planes;
                this.PlanesValidosPorIteracionBLEliminaDesplaza(i).Planes = resultados_parciales_it.PlanesValidosPorIteracionBLEliminaDesplaza(i).Planes;
                this.PlanesValidosPorIteracionBLSecuencialCompleto(i).Planes = resultados_parciales_it.PlanesValidosPorIteracionBLSecuencialCompleto(i).Planes;

                if i == 1
                    this.MejoresPlanes = this.PlanesValidosPorIteracion(i).Planes;
                else
                    this.MejoresPlanes = [this.MejoresPlanes, this.PlanesValidosPorIteracion(i).Planes];
                end
                            
                % agrega planes válidos a mejores planes en la medida que no
                % existan
                totex_maximo = this.MejoresPlanes(end).TotexTotal;
            
                for j = 1:length(this.PlanesValidosPorIteracion(i).Planes)
                    plan = this.PlanesValidosPorIteracion(i).Planes(j);
                    if plan.TotexTotal < totex_maximo
                        % verifica que plan no exista
                        existe = false;
                        for k = 1:length(this.MejoresPlanes)
                            if plan.compara_proyectos(this.MejoresPlanes(k));
                                existe = true;
                                break;
                            end
                        end
                        if ~existe
                            this.MejoresPlanes = [this.MejoresPlanes plan];
                        end
                    end
                end

                [~,indice]=sort([this.MejoresPlanes.TotexTotal]);
                this.MejoresPlanes = this.MejoresPlanes(indice);
                tope_bp = min(this.pParOpt.CantidadMejoresPlanes, length(this.MejoresPlanes)); %se guarda 1 plan más para calcula maxima diferencia para feromonas
                this.MejoresPlanes = this.MejoresPlanes(1:tope_bp);
                
                this.ValorMejorResultado(i) = resultados_parciales_it.MejorResultadoIteracion(i);
                % actualización de variables que faltan
                this.ValorMejorResultadoBase(i) = this.PlanesValidosPorIteracionBase(i).Planes(1).TotexTotal;
                if i == 1
                    this.ValorMejorResultadoAcumulado(i) = this.ValorMejorResultado(i);
                    this.ValorMejorResultadoAcumuladoBase(i) = this.ValorMejorResultadoBase(i);
                else
                    this.ValorMejorResultadoAcumulado(i) = min(this.ValorMejorResultadoAcumulado(i-1),this.ValorMejorResultado(i));
                    this.ValorMejorResultadoAcumuladoBase(i) = min(this.ValorMejorResultadoAcumuladoBase(i-1),this.ValorMejorResultadoBase(i));
                end
            
                if this.pParOpt.considera_busqueda_local()
                    this.ValorMejorResultadoBL(i) = this.PlanesValidosPorIteracionBL(i).Planes(1).TotexTotal;
                    if i == 1
                        this.ValorMejorResultadoAcumuladoBL(i) = this.ValorMejorResultadoBL(i);
                    else
                        this.ValorMejorResultadoAcumuladoBL(i) = min(this.ValorMejorResultadoAcumuladoBL(i-1),this.ValorMejorResultadoBL(i));                        
                    end
                    
                    if this.pParOpt.BLEliminaDesplazaProyectos > 0
                        this.ValorMejorResultadoBLEliminaDesplaza(i) = this.PlanesValidosPorIteracionBLEliminaDesplaza(i).Planes(1).TotexTotal;
                        if i == 1
                            this.ValorMejorResultadoAcumuladoBLEliminaDesplaza(i) = this.ValorMejorResultadoBLEliminaDesplaza(i);
                        else
                            this.ValorMejorResultadoAcumuladoBLEliminaDesplaza(i) = min(this.ValorMejorResultadoAcumuladoBLEliminaDesplaza(i-1),this.ValorMejorResultadoBLEliminaDesplaza(i));
                        end
                    end
                    
                    if this.pParOpt.BLAgregaProyectosFormaSecuencialCompleto > 0
                        this.ValorMejorResultadoBLSecuencialCompleto(i) = this.PlanesValidosPorIteracionBLSecuencialCompleto(i).Planes(1).TotexTotal;
                        if i == 1
                            this.ValorMejorResultadoAcumuladoBLSecuencialCompleto(i) = this.ValorMejorResultadoBLSecuencialCompleto(i);
                        else
                            this.ValorMejorResultadoAcumuladoBLSecuencialCompleto(i) = min(this.ValorMejorResultadoAcumuladoBLSecuencialCompleto(i-1),this.ValorMejorResultadoBLSecuencialCompleto(i));
                        end
                    end
                end
                this.CantPlanesValidos = this.CantPlanesValidos + length(this.PlanesValidosPorIteracion(i));
                this.imprime_resultados_actuales(true);
                this.actualiza_feromonas();
                this.pFeromona.imprime_feromonas(i);
            end            
        end
        
        function verifica_y_guarda_parametros(this, resultados_parciales_it)
            % guarda resultados parciales y verifica que estos sean
            % correctos
            if resultados_parciales_it.Parametros.CantidadHormigas == this.pParOpt.CantidadHormigas
                this.Resultados.Parametros.CantidadHormigas = this.pParOpt.CantidadHormigas;
            else
                this.Resultados.Parametros.CantidadHormigas = resultados_parciales_it.Parametros.CantidadHormigas;
                texto = 'Se modifican parametro CantidadHormigas, ya que no concuerda.';
                texto = [texto ' Valor en parametros: ' num2str(this.pParOpt.CantidadHormigas)];
                texto = [texto ' Valor en resultados: ' num2str(resultados_parciales_it.Parametros.CantidadHormigas)];
                warning(texto)
                %this.pParOpt.CantidadHormigas = resultados_parciales_it.Parametros.CantidadHormigas;
            end
            
            if resultados_parciales_it.Parametros.CantidadPlanesBusquedaLocal == this.pParOpt.CantidadPlanesBusquedaLocal
                this.Resultados.Parametros.CantidadPlanesBusquedaLocal = this.pParOpt.CantidadPlanesBusquedaLocal;
            else
                this.Resultados.Parametros.CantidadPlanesBusquedaLocal = resultados_parciales_it.Parametros.CantidadPlanesBusquedaLocal;
                texto = 'Se modifican parametro CantidadPlanesBusquedaLocal, ya que no concuerda.';
                texto = [texto ' Valor en parametros: ' num2str(this.pParOpt.CantidadPlanesBusquedaLocal)];
                texto = [texto ' Valor en resultados: ' num2str(resultados_parciales_it.Parametros.CantidadPlanesBusquedaLocal)];
                warning(texto)
                this.pParOpt.CantidadPlanesBusquedaLocal = resultados_parciales_it.Parametros.CantidadPlanesBusquedaLocal;
            end
            if resultados_parciales_it.Parametros.TasaEvaporacion == this.pParOpt.TasaEvaporacion
                this.Resultados.Parametros.TasaEvaporacion = this.pParOpt.TasaEvaporacion;
            else
                this.Resultados.Parametros.TasaEvaporacion = resultados_parciales_it.Parametros.TasaEvaporacion;
                texto = 'Se modifican parametro TasaEvaporacion, ya que no concuerda.';
                texto = [texto ' Valor en parametros: ' num2str(this.pParOpt.TasaEvaporacion)];
                texto = [texto ' Valor en resultados: ' num2str(resultados_parciales_it.Parametros.TasaEvaporacion)];
                warning(texto)
                this.pParOpt.TasaEvaporacion = resultados_parciales_it.Parametros.TasaEvaporacion;
            end
            if resultados_parciales_it.Parametros.CantidadMejoresPlanes == this.pParOpt.CantidadMejoresPlanes
                this.Resultados.Parametros.CantidadMejoresPlanes = this.pParOpt.CantidadMejoresPlanes;
            else
                this.Resultados.Parametros.CantidadMejoresPlanes = resultados_parciales_it.Parametros.CantidadMejoresPlanes;
                texto = 'Se modifican parametro CantidadMejoresPlanes, ya que no concuerda.';
                texto = [texto ' Valor en parametros: ' num2str(this.pParOpt.CantidadMejoresPlanes)];
                texto = [texto ' Valor en resultados: ' num2str(resultados_parciales_it.Parametros.CantidadMejoresPlanes)];
                warning(texto)
                this.pParOpt.CantidadMejoresPlanes = resultados_parciales_it.Parametros.CantidadMejoresPlanes;
            end
            
            if resultados_parciales_it.Parametros.FactorAlfa == this.pParOpt.FactorAlfa
                this.Resultados.Parametros.FactorAlfa = this.pParOpt.FactorAlfa;
            else
                this.Resultados.Parametros.FactorAlfa = resultados_parciales_it.Parametros.FactorAlfa;
                texto = 'Se modifican parametro FactorAlfa, ya que no concuerda.';
                texto = [texto ' Valor en parametros: ' num2str(this.pParOpt.FactorAlfa)];
                texto = [texto ' Valor en resultados: ' num2str(resultados_parciales_it.Parametros.FactorAlfa)];
                warning(texto)
                this.pParOpt.FactorAlfa = resultados_parciales_it.Parametros.FactorAlfa;
            end
            
            if resultados_parciales_it.Parametros.MaxFeromona == this.pParOpt.MaxFeromona
                this.Resultados.Parametros.MaxFeromona = this.pParOpt.MaxFeromona;
            else
                this.Resultados.Parametros.MaxFeromona = resultados_parciales_it.Parametros.MaxFeromona;
                texto = 'Se modifican parametro MaxFeromona, ya que no concuerda.';
                texto = [texto ' Valor en parametros: ' num2str(this.pParOpt.MaxFeromona)];
                texto = [texto ' Valor en resultados: ' num2str(resultados_parciales_it.Parametros.MaxFeromona)];
                warning(texto)
                this.pParOpt.MaxFeromona = resultados_parciales_it.Parametros.MaxFeromona;
            end
            
            if resultados_parciales_it.Parametros.BLEliminaDesplazaProyectos == this.pParOpt.BLEliminaDesplazaProyectos
                this.Resultados.Parametros.BLEliminaDesplazaProyectos = this.pParOpt.BLEliminaDesplazaProyectos;
            else
                this.Resultados.Parametros.BLEliminaDesplazaProyectos = resultados_parciales_it.Parametros.BLEliminaDesplazaProyectos;
                texto = 'Se modifican parametro BLEliminaDesplazaProyectos, ya que no concuerda.';
                texto = [texto ' Valor en parametros: ' num2str(this.pParOpt.BLEliminaDesplazaProyectos)];
                texto = [texto ' Valor en resultados: ' num2str(resultados_parciales_it.Parametros.BLEliminaDesplazaProyectos)];
                warning(texto)
                this.pParOpt.BLEliminaDesplazaProyectos = resultados_parciales_it.Parametros.BLEliminaDesplazaProyectos;
            end
            
            if resultados_parciales_it.Parametros.BLAgregaProyectosFormaSecuencialCompleto == this.pParOpt.BLAgregaProyectosFormaSecuencialCompleto
                this.Resultados.Parametros.BLAgregaProyectosFormaSecuencialCompleto = this.pParOpt.BLAgregaProyectosFormaSecuencialCompleto;
            else
                this.Resultados.Parametros.BLAgregaProyectosFormaSecuencialCompleto = resultados_parciales_it.Parametros.BLAgregaProyectosFormaSecuencialCompleto;
                texto = 'Se modifican parametro BLAgregaProyectosFormaSecuencialCompleto, ya que no concuerda.';
                texto = [texto ' Valor en parametros: ' num2str(this.pParOpt.BLAgregaProyectosFormaSecuencialCompleto)];
                texto = [texto ' Valor en resultados: ' num2str(resultados_parciales_it.Parametros.BLAgregaProyectosFormaSecuencialCompleto)];
                warning(texto)
                this.pParOpt.BLAgregaProyectosFormaSecuencialCompleto = resultados_parciales_it.Parametros.BLAgregaProyectosFormaSecuencialCompleto;
            end            
        end
        
        function analiza_problema_expansion(this)
            % analiza caso base sin proyectos de expansion
            % 1. calcula costos de generación "óptimos", i.e. sin
            % restricciones de transmisión
            sep = this.pSEP.crea_copia();
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            cantidad_etapas = this.pParOpt.CantidadEtapas;
            puntos_operacion = this.pAdmSc.entrega_puntos_operacion();
            cantidad_puntos_operacion = length(puntos_operacion);
            CapacidadGeneradores = this.pAdmSc.entrega_capacidad_generadores();
            SerieGeneradoresERNC = this.pAdmSc.entrega_serie_generadores_ernc();
            SerieConsumos = this.pAdmSc.entrega_serie_consumos();
            evaluacion_sin_restricciones = cell(cantidad_etapas,0);
            plan_vacio = cPlanExpansion(7777);

%             evaluacion_con_restricciones = cell(cantidad_etapas,0);
%             evaluacion_plan_completo = cell(cantidad_etapas,0);
            for etapa = 1:cantidad_etapas
                plan_vacio.inicializa_etapa(etapa);                
                if etapa == 1
                    pOPF = cDCOPF(sep, this.pAdmSc, this.pParOpt);
                    pOPF.inserta_resultados_en_sep(false);
                    %pOPF.inserta_nivel_debug(0);
                    pOPF.inserta_etapa(etapa);
                else
                    pOPF.actualiza_etapa(etapa);
                end
%                pOPF.inserta_caso_estudio('con_restricciones');
%                pOPF.calcula_despacho_economico();
%                evaluacion_con_restricciones{etapa} = pOPF.entrega_evaluacion();
%                evaluacion_con_restricciones{etapa}.imprime_resultados(['Evaluacion con restricciones etapa ' num2str(etapa)]);
                pOPF.inserta_caso_estudio('sin_restricciones');
                pOPF.calcula_despacho_economico_sin_restricciones_red();
                this.evalua_resultado_y_guarda_en_plan(plan_vacio, pOPF.entrega_evaluacion(), etapa);                
                evaluacion_sin_restricciones{etapa} = pOPF.entrega_evaluacion();
                evaluacion_sin_restricciones{etapa}.imprime_resultados(['Evaluacion sin restricciones etapa ' num2str(etapa)]);
            end
            this.calcula_costos_totales(plan_vacio);
            plan_vacio.imprime();

            % 2. calcula costos de generación de plan óptimo
%             sep = this.pSEP.crea_copia();
%             for etapa = 1:cantidad_etapas
%                 proyectos = this.PlanOptimo.entrega_proyectos(etapa);
%                 for k = 1:length(proyectos)
%                     proyecto = this.pAdmProy.entrega_proyecto(proyectos(k));
%                     sep.agrega_proyecto(proyecto);
%                 end
%                 
%                 if etapa == 1
%                     pOPF = cDCOPF(sep, this.pAdmSc, this.pParOpt);
%                     pOPF.inserta_resultados_en_sep(false);
%                     %pOPF.inserta_nivel_debug(0);
%                     pOPF.inserta_etapa(etapa);
%                     pOPF.formula_problema_despacho_economico();
% 
%                 else
%                     pOPF.actualiza_etapa(etapa);
%                 end
%                 pOPF.inserta_caso_estudio('plan_optimo');
%                 pOPF.calcula_despacho_economico();
%                 evaluacion_plan_completo{etapa} = pOPF.entrega_evaluacion();
%                 evaluacion_plan_completo{etapa}.imprime_resultados(['Evaluacion plan optimo etapa ' num2str(etapa)]);
%             end
            
            % 2. calcula costos de generación considerando todos los
            % proyectos de transmisión
%             sep = this.pSEP.crea_copia();
%             for etapa = 1:cantidad_etapas                
%                 if etapa == 1
%                     pOPF = cDCOPF(sep, this.pAdmSc, this.pParOpt);
%                     pOPF.inserta_resultados_en_sep(false);
%                     %pOPF.inserta_nivel_debug(0);
%                     pOPF.inserta_etapa(etapa);
%                     pOPF.formula_problema_despacho_economico();
%                     
%                     proyectos = this.pAdmProy.Proyectos;
%                     for k = 1:length(proyectos)
%                         proyecto = proyectos(k);
%                         sep.agrega_proyecto(proyecto);
%                     end
%                 else
%                     pOPF.actualiza_etapa(etapa);
%                 end
%                 pOPF.inserta_caso_estudio('plan_completo');
%                 pOPF.calcula_despacho_economico();
%                 evaluacion_plan_completo{etapa} = pOPF.entrega_evaluacion();
%                 evaluacion_plan_completo{etapa}.imprime_resultados(['Evaluacion plan completo etapa ' num2str(etapa)]);
%             end
        end
        
        function calcula_costos_operacion_sin_restriccion(this, proy, varargin)
            % varargin indica si es detallado o no
            if nargin > 2
                detallado = varargin{1};
            else
                detallado = false;
            end
            cantidad_etapas = this.pParOpt.CantidadEtapas;
            sep = this.pSEP.crea_copia();
            if ~isempty(proy)
               proyecto = this.pAdmProy.entrega_proyecto(proy);
                sep.agrega_proyecto(proyecto);
            end
            
            this.CostosOperacionSinRestriccion = zeros(cantidad_etapas,1);
            this.NPVCostosOperacionSinRestriccion = 0;
            q = (1 + this.pParOpt.TasaDescuento);
            detapa = this.pParOpt.DeltaEtapa;

            for etapa = 1:cantidad_etapas
                if etapa == 1
                    pOPF = cDCOPF(sep, this.pAdmSc, this.pParOpt);
                    pOPF.inserta_resultados_en_sep(false);
                    %pOPF.inserta_nivel_debug(0);
                    pOPF.inserta_etapa(etapa);
                else
                    pOPF.actualiza_etapa(etapa);
                end
                pOPF.inserta_caso_estudio('sin_restricciones');
                pOPF.calcula_despacho_economico_sin_restricciones_red();
                % costos de operacion son solo costos de generacion. No hay
                % recorte RES ni ENS
                costo_operacion = 0;
                if detallado
                    evaluacion = pOPF.entrega_evaluacion();
                    
                    evaluacion.inserta_administrador_escenarios(this.pAdmSc)
                    evaluacion.inserta_etapa(etapa);
                    evaluacion.imprime_resultados(['Evaluacion sin restricciones etapa ' num2str(etapa)]);
                end
                for i = 1:this.pAdmSc.CantidadPuntosOperacion
                    representatividad =this.pAdmSc.RepresentatividadPuntosOperacion(i);
                    costo_operacion = costo_operacion + evaluacion.CostoGeneracion(i)*representatividad/1000000;
                end
                npv_costo_operacion = costo_operacion/q^(detapa*etapa);
                this.CostosOperacionSinRestriccion(etapa,1) = costo_operacion;
                this.NPVCostosOperacionSinRestriccion = this.NPVCostosOperacionSinRestriccion + npv_costo_operacion;
            end
        end        
    end
end