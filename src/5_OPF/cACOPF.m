classdef cACOPF < cOPF
    properties
		pSEP = cSistemaElectricoPotencia.empty
        pSM = cmSistemaModal.empty
        %pAdmOper = cAdministradorEscenariosOperacion.empty
		pResEvaluacion = cResultadoEvaluacionSEP.empty
        pParOpt = cParOptimizacionOPF.empty
        pAdmSc = cAdministradorEscenarios.empty
        
        % resultados problema de optimizacion
        ResOptimizacion
        ExitFlag
        Fval
        Output
        Lambda
        
        % vectores con punteros a elementos de red que corresponden a las
        % variables de operación
        VarOpt= cmElementoModal.empty;
        TipoVarOpt = cell.empty;
        UnidadesVarOpt = cell.empty;
        CantidadVariablesPuntoOperacion = 0;
        
        % vector que contiene los puntos de operación
        % si no se ingresa en forma externa
        vPuntosOperacion = 1  
        
        % Parámetro de ACO. Indica la etapa correspondiente. TODO: Hay que eliminar esta variables. 
        % Por ahora se necesita para cargar los límites de la etapa
        % correspondiente. Estas se tienen que manejar directamente en el SEP
        iEtapa = 0
        
		Fobj  = [] %funcion objetivo
        Aeq = []  % matriz con restricciones de igualdad
        beq = []  % vector objetivo restricciones de igualdad
        Aineq = [] % matriz con restricciones de desigualdad
        bineq = []  % vector de desigualdades
        lb = [] %valores mínimos de variables de decisión
        ub = [] %valores máximos de variables de decisión

        % Sólo en modo debug
        NombreVariables = []
        NombreDetalladoVariables = []
        NombreIneq = []
        NombreEq = []
        
        iIndiceIneq = 0
        iIndiceEq = 0
        iNivelDebug = 2
        nombre_archivo = './output/opf.dat'
        nombre_archivo_problema_opt = './output/opf_problem_formulation.dat'
        nombre_archivo_detalle_variables = './output/variables_opf.dat'
    end
    
    methods
	
		function this = cACOPF(sep, varargin)                
			this.pSEP = sep;
            this.pResEvaluacion = cResultadoEvaluacionSEP(sep);
            this.pParOpt = cParOptimizacionOPF();
            this.pSM = cmSistemaModal(sep, 1);
            this.iNivelDebug = 2;
            
            if nargin > 2
                %OPF para planificación
                this.pAdmSc = varargin{1};
                this.vPuntosOperacion = this.pAdmSc.entrega_puntos_operacion();
                % reemplaza parámetros del OPF por los indicados en ACO
                this.copia_parametros_optimizacion(varargin{2})
            end
        end        
        
        function inserta_etapa(this, nro_etapa)
            % etapa se utiliza para ACO
            this.iEtapa = nro_etapa;
        end
        
        function inserta_nivel_debug(this, nivel)
            this.iNivelDebug = nivel;
        end
        
		function calcula_despacho_economico(this)    
            this.iIndiceIneq = 0;
            this.iIndiceEq = 0;
            this.inicializa_variables();
            this.inicializa_matrices_problema_optimizacion();
			
            this.escribe_funcion_objetivo();
			this.escribe_restricciones();
            if this.iNivelDebug > 1
                this.imprime_problema_optimizacion();
            end
            
			this.optimiza();
            if this.ExitFlag == 1
                % problema tiene solucion óptima
                this.pResEvaluacion.ExisteResultado = true;
                this.escribe_resultados();
                
            else
                this.pResEvaluacion.ExisteResultado = false;
                % problema no tiene solucion
                % no se escriben resultados porque no tiene sentido
                
            end
        end
		
        function inicializa_matrices_problema_optimizacion(this)
            % se inicializan las dimensiones de las matrices. 
            % por ahora, sólo las dimensiones de algunas matrices 
            % eventualmente se pueden inicializar todas las matrices para mejorar
            % performance. 

            this.Fobj = zeros(1,length(this.lb));
            %this.Aeq = zeros(cantidad_po*(cantidad_subestaciones + cantidad_lineas), cantidad_var_decision);
            %this.beq = zeros(cantidad_po*(cantidad_subestaciones + cantidad_lineas),1);
            %this.Aineq = zeros(2*cantidad_po*cantidad_lineas, cantidad_var_decision); % para incluir sobrecarga de las líneas
            %this.bineq = zeros(2*cantidad_po*cantidad_lineas,1);

        end
                
		function inicializa_variables(this)
            % para mejor comprensión del código, se separa esta parte
            % dependiendo si el flujo es AC o DC
            if strcmp(this.pParOpt.entrega_tipo_flujo(), 'AC')
                this.inicializa_variables_ac_opf();
            else
                this.inicializa_variables_dc_opf();
            end
        end
        
        function inicializa_variables_ac_opf(this)
            % Primero crea las variables de optimización y luego las
            % inicializa
            
            % variables de control (cuando flag opf esté activada): 
            % 1. potencia activa (despacho) de los generadores
            % 2. Voltaje en los buses que tienen algún generador 
            %    con flag OPF y parámetros así lo indican
            % 3. Posición del tap de los transformadores
            % 4. Posición del tap de los capacitores y reactores
            % 5. Cantidad de carga desconectada, o desconexión de carga?
            % 
            % Variables de estado:
            % 1. Voltajes en los buses sin flag OPF
            % 2. Ángulos de los buses (la Slack se fija en cero pero se incluye como variable)
            %
            % Variables auxiliares (ayudan a la formulación del problema)
            % 1. Potencia reactiva de los generadores que controlan tensión
            %    (sólo flujo AC)
            % 2. Flujos por las líneas y transformadores. Se incluyen para relajar las restricciones de transmisiónn
            %    en caso de que el programa no encuentre solución
            % 3. Error+ y Error- en los flujos por las líneas y los
            %    transformadores. Idem anterior
            
            % variables de control.
            this.inserta_varopt(this.pSM.entrega_elemento_paralelo_flag_opf('cGenerador'), 'VariableControl', 'P');
            if this.pParOpt.entrega_optimiza_voltaje_operacion()
                % voltaje en los buses con generadores opf también es variable de control
                this.inserta_varopt(this.pSM.entrega_buses_opf(), 'VariableControl', 'V');
            end
            
            this.inserta_varopt(this.pSM.entrega_elemento_serie_flag_opf('cTransformador2D'), 'VariableControl', 'Tap');
            this.inserta_varopt(this.pSM.entrega_elemento_paralelo_flag_opf('cCondensador'), 'VariableControl', 'Tap');
            this.inserta_varopt(this.pSM.entrega_elemento_paralelo_flag_opf('cReactor'), 'VariableControl', 'Tap');
            %this.inserta_variable_control(sep.entrega_consumo_opf(), 'P'];
            
            % variables de estado
            if this.pParOpt.entrega_optimiza_voltaje_operacion()
                % se agrega el voltaje sólo en los buses sin generadores
                % opf. En el resto la variable ya está definida como de
                % control
                this.inserta_varopt(this.pSM.entrega_buses_no_opf(), 'VariableEstado', 'V');
            else
                % el voltaje en los buses es variable de estado siempre
                this.inserta_varopt(this.pSM.entrega_buses(), 'VariableEstado', 'V');
            end
            this.inserta_varopt(this.pSM.entrega_buses(), 'VariableEstado', 'Theta');
            
            % variables auxiliares.
            % Generadores con control de tensión se ingresan como variable
            % auxiliar, pero con límite fijo. El límite se va modificando
            % en forma iterativa dependiendo del P del generador
            mgen_controlv = this.pSM.entrega_generadores_control_tension();
            this.inserta_varopt(mgen_controlv, 'VariableAuxiliar', 'Q');
            
            mlineas = this.pSM.entrega_elemento_serie('cLinea');
            this.inserta_varopt(mlineas, 'VariableAuxiliar', 'P');
            this.inserta_varopt(mlineas, 'VariableAuxiliar', 'Q');
            
            this.inserta_varopt(mlineas, 'VariableAuxiliar', 'Error_pos');
            this.inserta_varopt(mlineas, 'VariableAuxiliar', 'Error_neg');
            
            mtrafo2d = this.pSM.entrega_elemento_serie('cTransformador2D');
            this.inserta_varopt(mtrafo2d, 'VariableAuxiliar', 'P')
            this.inserta_varopt(mtrafo2d, 'VariableAuxiliar', 'Q')
            
            this.inserta_varopt(mtrafo2d, 'VariableAuxiliar', 'Error_pos');
            this.inserta_varopt(mtrafo2d, 'VariableAuxiliar', 'Error_neg');
            
            this.inserta_varopt(this.pSM.entrega_buses(), 'VariableAuxiliar', 'Error_pos');
            this.inserta_varopt(this.pSM.entrega_buses(), 'VariableAuxiliar', 'Error_neg');
            
            % Inicializa las variables
            indice = 0;
            for oper = 1:length(this.vPuntosOperacion)
                for i = 1:length(this.VarOpt)
                    indice = indice + 1;                    
                    elred = this.VarOpt(i).entrega_elemento_red();
                    switch this.TipoVarOpt{i}
                        case 'VariableControl'
                            switch this.UnidadesVarOpt{i}
                                case 'P'
                                    % Potencia de inyección del generador
                                    if ~isempty(this.pAdmSc)
                                        % factor de expansión para TNEP
                                        id_generador_sc = this.VarOpt(i).entrega_elemento_red().entrega_indice_escenario();
                                        pmax = this.pAdmSc.entrega_capacidad_generador(id_generador_sc, this.iEtapa);
                                        sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
                                        pmax = pmax/sbase;
                                    else
                                        pmax = elred.entrega_pmax_pu();
                                    end
                                    
                                    pmin = elred.entrega_pmin_pu();
                                        
                                    if strcmp(this.pParOpt.entrega_tipo_problema(), 'Redespacho')
                                        % problema de redespacho. se
                                        % consideran los delta de los
                                        % límites
                                        p0 = elred.entrega_p0_pu();
                                        pmax = pmax - p0;
                                        pmin = p0 - pmin;
                                    end
                                    this.VarOpt(i).inserta_varopt_operacion('P', oper, indice);
                                    this.lb(indice) = pmin;
                                    this.ub(indice) = pmax;
                                    if this.iNivelDebug > 1
                                        this.ingresa_nombres(indice, oper, this.TipoVarOpt{i}, this.UnidadesVarOpt{i});
                                    end
                           
                                case 'V'
                                    % En este caso el voltaje es variable de optimización
                                    % Para dar prioridad a la obtención de
                                    % resultados, el voltaje no se
                                    % restringe aquí, sino que a través de
                                    % las variables auxiliares de error
                                    this.VarOpt(i).inserta_varopt_operacion('V', oper, indice);
                                    this.lb(indice) = -inf;
                                    this.ub(indice) = inf;
                                    if this.iNivelDebug > 1
                                        this.ingresa_nombres(indice, oper, this.TipoVarOpt{i}, this.UnidadesVarOpt{i});
                                    end
                                    
                                case 'Tap'
                                    % Condensador, reactor o
                                    % transformador2D con tap
                                    this.VarOpt(i).inserta_varopt_operacion('Tap', oper, indice);
                                    tap_min = elred.entrega_tap_min();
                                    tap_max = elred.entrega_tap_max();
                                    this.lb(indice) = tap_min;
                                    this.ub(indice) = tap_max;
                                    if this.iNivelDebug > 1
                                        this.ingresa_nombres(indice, oper, this.TipoVarOpt{i}, this.UnidadesVarOpt{i});
                                    end
                                otherwise
                                    error = MException('cOPF:inicializa_variables',...
                                        ['Inconsistencia en los datos en variable de control. Tipo ' this.UnidadesVarOpt{i} ' no corresponde']);
                                    throw(error)
                            end
                        case 'VariableEstado'
                            switch this.UnidadesVarOpt{i}
                                case 'V'
                                    % Voltaje de buses
                                    % Para dar prioridad a la obtención de
                                    % una solución, el voltaje no se
                                    % restringe aquí, sino que a través de
                                    % las variablex auxiliares
                                    this.VarOpt(i).inserta_varopt_operacion('V', oper, indice);
                                    this.lb(indice) = -inf;
                                    this.ub(indice) = inf;
                                    if this.iNivelDebug > 1
                                        this.ingresa_nombres(indice, oper, this.TipoVarOpt{i}, this.UnidadesVarOpt{i});
                                    end
                                case 'Theta'
                                    % ángulo de las subestaciones 
                                    this.VarOpt(i).inserta_varopt_operacion('Theta', oper, indice);
                                    %this.lb(indice) = -pi/2;
                                    %this.ub(indice) = pi/2;
                                    this.lb(indice) = -inf;
                                    this.ub(indice) = inf;
                                    if this.iNivelDebug > 1
                                        this.ingresa_nombres(indice, oper, this.TipoVarOpt{i}, this.UnidadesVarOpt{i});
                                    end
                                otherwise
                                    error = MException('cOPF:inicializa_variables',...
                                        ['Inconsistencia en los datos en variable de estado. Tipo ' this.UnidadesVarOpt{i} ' no corresponde']);
                                    throw(error)
                            end
                        case 'VariableAuxiliar'
                            switch this.UnidadesVarOpt{i}
                                case 'P'
                                    % potencia P de línea o transformador
                                    this.VarOpt(i).inserta_varopt_operacion('P', oper, indice);
                                    this.lb(indice) = -Inf;
                                    this.ub(indice) = Inf;
                                    if this.iNivelDebug > 1
                                        this.ingresa_nombres(indice, oper, this.TipoVarOpt{i}, this.UnidadesVarOpt{i});
                                    end
                                case 'Q'
                                    % potencia Q de línea o transformador,
                                    % o límite de generadores con
                                    % regulación de tensión
                                    this.VarOpt(i).inserta_varopt_operacion('Q', oper, indice);
                                    elred = this.VarOpt(i).entrega_elemento_red();
                                    if isa(elred, 'cGenerador')
                                        qmax = elred.entrega_qmax();
                                        qmin = elred.entrega_qmin();
                                        this.lb(indice) = qmin;
                                        this.ub(indice) = qmax;
                                    else
                                        this.lb(indice) = -Inf;
                                        this.ub(indice) = Inf;
                                    end
                                    if this.iNivelDebug > 1
                                        this.ingresa_nombres(indice, oper, this.TipoVarOpt{i}, this.UnidadesVarOpt{i});
                                    end
                                    
                                case 'Error_pos'
                                    this.VarOpt(i).inserta_varopt_operacion('Error_pos', oper, indice);
                                    this.lb(indice) = 0;
                                    this.ub(indice) = Inf;
                                    if this.iNivelDebug > 1
                                        this.ingresa_nombres(indice, oper, this.TipoVarOpt{i}, this.UnidadesVarOpt{i});
                                    end
                                case 'Error_neg'
                                    this.VarOpt(i).inserta_varopt_operacion('Error_neg', oper, indice);
                                    this.lb(indice) = 0;
                                    this.ub(indice) = Inf;
                                    if this.iNivelDebug > 1
                                        this.ingresa_nombres(indice, oper, this.TipoVarOpt{i}, this.UnidadesVarOpt{i});
                                    end
                                otherwise
                                    error = MException('cOPF:inicializa_variables',...
                                        ['Inconsistencia en los datos en variable auxiliar. Tipo ' this.UnidadesVarOpt{i} ' no corresponde']);
                                    throw(error)
                            end
                        otherwise
                            error = MException('cOPF:inicializa_variables',...
                                ['Inconsistencia en los datos. Tipo de variable de control ' this.TipoVarOpt{i} ' no corresponde']);
                            throw(error)
                    end
                end
            end
        end

        function inicializa_variables_dc_opf(this)
            % Primero crea las variables de optimización y luego las
            % inicializa
            
            % variables de control (cuando flag opf esté activada): 
            % 1. potencia activa (despacho) de los generadores
            % 
            % Variables de estado:
            % 2. Ángulos de los buses (la Slack se fija en cero pero se incluye como variable)
            %
            % Variables auxiliares (ayudan a la formulación del problema)
            % 2. Flujos por las líneas y transformadores. Se incluyen para relajar las restricciones de transmisiónn
            %    en caso de que el programa no encuentre solución
            % 3. Error+ y Error- en los flujos por las líneas y los
            %    transformadores. Idem anterior
            
            % variables de control.
            this.inserta_varopt(this.pSM.entrega_elemento_paralelo_flag_opf('cGenerador'), 'VariableControl', 'P');
            %this.inserta_variable_control(sep.entrega_consumo_opf(), 'P'];
            
            % variables de estado
            this.inserta_varopt(this.pSM.entrega_buses(), 'VariableEstado', 'Theta');
            
            % variables auxiliares.
            mlineas = this.pSM.entrega_elemento_serie('cLinea');
            this.inserta_varopt(mlineas, 'VariableAuxiliar', 'P');
            this.inserta_varopt(mlineas, 'VariableAuxiliar', 'Error_pos');
            this.inserta_varopt(mlineas, 'VariableAuxiliar', 'Error_neg');
            
            mtrafo2d = this.pSM.entrega_elemento_serie('cTransformador2D');
            this.inserta_varopt(mtrafo2d, 'VariableAuxiliar', 'P')
            this.inserta_varopt(mtrafo2d, 'VariableAuxiliar', 'Error_pos');
            this.inserta_varopt(mtrafo2d, 'VariableAuxiliar', 'Error_neg');

            % Inicializa las variables
            if this.iNivelDebug > 1
                this.NombreVariables = cell(length(this.VarOpt)*length(this.vPuntosOperacion));
                this.NombreDetalladoVariables = cell(length(this.VarOpt)*length(this.vPuntosOperacion));
            end
            indice = 0;
            for oper = 1:length(this.vPuntosOperacion)
                for i = 1:length(this.VarOpt)
                    indice = indice + 1;                    
                    elred = this.VarOpt(i).entrega_elemento_red();
                    switch this.TipoVarOpt{i}
                        case 'VariableControl'
                            % Potencia de inyección del generador
                            if ~isempty(this.pAdmSc)
                            	% factor de expansión para TNEP
                                id_generador_sc = this.VarOpt(i).entrega_elemento_red().entrega_indice_escenario();
                                pmax = this.pAdmSc.entrega_capacidad_generador(id_generador_sc, this.iEtapa);
                                sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
                                pmax = pmax/sbase;
                                
                            else
                                pmax = elred.entrega_pmax_pu();                                
                            end
                            pmin = elred.entrega_pmin_pu();

                            if strcmp(this.pParOpt.entrega_tipo_problema(), 'Redespacho')
                            	% problema de redespacho. se
                                % consideran los delta de los
                                % límites
                                p0 = elred.entrega_p0_pu();
                                pmax = pmax - p0;
                                pmin = p0 - pmin;
                            end
                            this.VarOpt(i).inserta_varopt_operacion('P', oper, indice);
                            this.lb(indice) = pmin;
                            this.ub(indice) = pmax;
                            if this.iNivelDebug > 1
                                this.ingresa_nombres(indice, oper, this.TipoVarOpt{i}, this.UnidadesVarOpt{i});
                            end
                        case 'VariableEstado'
                            % ángulo de las subestaciones 
                            this.VarOpt(i).inserta_varopt_operacion('Theta', oper, indice);
                            this.lb(indice) = -pi/3;
                            this.ub(indice) = pi/3;
                            if this.iNivelDebug > 1
                                this.ingresa_nombres(indice, oper, this.TipoVarOpt{i}, this.UnidadesVarOpt{i});
                            end
                        case 'VariableAuxiliar'
                            switch this.UnidadesVarOpt{i}
                                case 'P'
                                    % potencia activa de líneas y
                                    % transformadores
                                    this.VarOpt(i).inserta_varopt_operacion('P', oper, indice);
                                    this.lb(indice) = -Inf;
                                    this.ub(indice) = Inf;
                                    if this.iNivelDebug > 1
                                        this.ingresa_nombres(indice, oper, this.TipoVarOpt{i}, this.UnidadesVarOpt{i});
                                    end
                                case 'Error_pos'
                                    this.VarOpt(i).inserta_varopt_operacion('Error_pos', oper, indice);
                                    this.lb(indice) = 0;
                                    this.ub(indice) = Inf;
                                    if this.iNivelDebug > 1
                                        this.ingresa_nombres(indice, oper, this.TipoVarOpt{i}, this.UnidadesVarOpt{i});
                                    end
                                case 'Error_neg'
                                    this.VarOpt(i).inserta_varopt_operacion('Error_neg', oper, indice);
                                    this.lb(indice) = 0;
                                    this.ub(indice) = Inf;
                                    if this.iNivelDebug > 1
                                        this.ingresa_nombres(indice, oper, this.TipoVarOpt{i}, this.UnidadesVarOpt{i});
                                    end
                                otherwise
                                    error = MException('cOPF:inicializa_variables',...
                                        ['Inconsistencia en los datos en variable auxiliar. Tipo ' this.UnidadesVarOpt{i} ' no corresponde']);
                                    throw(error)
                            end
                        otherwise
                            error = MException('cOPF:inicializa_variables',...
                                ['Inconsistencia en los datos. Tipo de variable de control ' this.TipoVarOpt{i} ' no corresponde']);
                            throw(error)
                    end
                end
            end
        end
        
        function escribe_funcion_objetivo(this)
            penalizacion = this.pParOpt.entrega_factor_penalizacion();
            if strcmp(this.pParOpt.entrega_funcion_objetivo(), 'MinC')
                for oper = 1:length(this.vPuntosOperacion)
                    % Costo de generación
                    % no es eficiente pero en este punto no se necesita
                    % rapidez (... o si? TODO: Evaluar!)
                    for i = 1:length(this.VarOpt)
                        elred = this.VarOpt(i).entrega_elemento_red();
                        if isa(elred, 'cGenerador') && ...
                           strcmp(this.TipoVarOpt{i}, 'VariableControl') && ...
                           strcmp(this.UnidadesVarOpt{i}, 'P')
                            % esta comparación se hace por si a futuro se
                            % agregan otro tipo de elementos con variable
                            % de control P que no sean generadores y no
                            % tengan costos asociados... (TODO: verificar
                            % si es necesario!)
                            costo_mwh = elred.entrega_costo_mwh_pu();
                            indice = this.VarOpt(i).entrega_varopt_operacion('P',oper);
                            this.Fobj(indice) = costo_mwh;
                        elseif strcmp(this.UnidadesVarOpt{i}, 'Error_pos') || strcmp(this.UnidadesVarOpt{i}, 'Error_neg')
                            indice = this.VarOpt(i).entrega_varopt_operacion(this.UnidadesVarOpt{i}, oper);
                            this.Fobj(indice) = penalizacion;
                        end
                    end
                end
            else
                error = MException('cOPF:escribe_funcion_objetivo','Función objetivo indicada no implementada');
                throw(error)
            end
        end
        
        function escribe_restricciones(this)
            % inicializa containers. Se asume que habrá por lo menos una
            % restricción de igualdad y una de desigualdad
            this.Aineq = zeros(1, length(this.VarOpt));
            this.Aeq = zeros(1, length(this.VarOpt));
            for oper = 1:length(this.vPuntosOperacion)
                escribe_balance_energia(this, oper);
                escribe_relaciones_flujos_angulos(this, oper);
                escribe_restricciones_flujos_serie(this, oper);
            end
        end
        		
		function optimiza(this)
            if strcmp(this.pParOpt.entrega_tipo_flujo(), 'AC')
                this.optimiza_ac();
            else
                this.optimiza_dc();
            end
        end
        
        function optimiza_dc(this)
            if this.pParOpt.entrega_flujo_dc_con_perdidas()
                error = MException('cOPF:optimiza_dc','OPF DC con pérdidas aún no implementado');
                throw(error)
            else
                if this.iNivelDebug > 0
                    options = optimoptions('linprog','Display','final');
                else
                    options = optimoptions('linprog','Display','off');
                end
                if this.iNivelDebug > 1
                    prot = cProtocolo.getInstance;
                    prot.imprime_vector(this.Fobj, 'Funcion objetivo');
                    prot.imprime_vector(this.lb, 'Lower bounds');
                    prot.imprime_vector(this.ub, 'Upper bounds');
                    %disp('Size Fobj: ')
                    %size(this.Fobj)
                    %disp('Size Aineq: ')
                    %size(this.Aineq)
                    %disp('Size Aeq: ')
                    %size(this.Aeq)
                    %disp('Size bineq: ')
                    %size(this.bineq)
                end
                
                [this.ResOptimizacion, this.Fval,this.ExitFlag,this.Output,this.Lambda]= linprog(this.Fobj,this.Aineq,this.bineq,this.Aeq,this.beq,this.lb,this.ub, [], options);
            end
        end

        function optimiza_ac(this)
            error = MException('cOPF:optimiza_ac','OPF AC aún no implementado');
            throw(error)
        end
        
		function escribe_resultados(this)
            this.inicializa_resultados();
            %primero una función de chequeo
            delta_error = 0.001;

            for oper = 1:length(this.vPuntosOperacion)
                for i = 1:length(this.VarOpt)
                    switch this.TipoVarOpt{i}
                        case 'VariableControl'
                            switch this.UnidadesVarOpt{i}
                                case 'P'
                                    % Potencia de inyección del generador
                                    sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
                                    costo_mwh = this.VarOpt(i).entrega_elemento_red().entrega_costo_mwh();
                                    id_global = this.VarOpt(i).entrega_id_global();
                                    indice_opt = this.VarOpt(i).entrega_varopt_operacion('P', oper);
                                    p_mw = this.ResOptimizacion(indice_opt)*sbase;
                                    if strcmp(this.pParOpt.entrega_tipo_problema(), 'Redespacho')
                                        this.pResEvaluacion.CostoRedespacho(oper) = this.pResEvaluacion.CostoRedespacho(oper) + costo_mwh * p_mw;
                                        p0 = this.VarOpt(i).entrega_elemento_red().entrega_p0();
                                        p_mw = p_mw + p0;
                                    end
                                    
                                    this.pResEvaluacion.InyeccionParalP(id_global, oper) = p_mw;
                                    this.pResEvaluacion.CostoGeneracion(oper) = this.pResEvaluacion.CostoGeneracion(oper) + costo_mwh*p_mw;
                                    if this.iNivelDebug > 1
                                        % se muestran los resultados detallados en pantalla
                                        el_red = this.VarOpt(i).entrega_elemento_red();
                                        text = ['Generador '  el_red.entrega_nombre() ...
                                                ' despacha '  num2str(p_mw)  ...
                                                ' (Pmax/Pmin: '  num2str(el_red.entrega_pmax()) ...
                                                '/'  num2str(el_red.entrega_pmin()) ...
                                                '). Punto de operación ' num2str(this.vPuntosOperacion(oper)) ...
                                                ' P0: ' num2str(this.VarOpt(i).entrega_elemento_red().entrega_p0())];
                                        disp(text);
                                    end
                                case 'V'
                                    % En este caso el voltaje es variable de optimización
                                    vn = this.VarOpt(i).entrega_vn();
                                    id_global = this.VarOpt(i).entrega_id_global();
                                    indice_opt = this.VarOpt(i).entrega_varopt_operacion('V', oper);
                                    voltaje = this.ResOptimizacion(indice_opt)*vn;
                                    
                                    this.pResEvaluacion.VoltajeBuses(id_global, oper) = voltaje;
                                    if this.iNivelDebug > 1
                                        % se muestran los resultados detallados en pantalla
                                        el_red = this.VarOpt(i).entrega_elemento_red();
                                        text = ['Subestacion '  el_red.entrega_nombre() ...
                                                ' tiene voltaje'  num2str(voltaje)];
                                        disp(text);
                                    end
                                    
                                case 'Tap'
                                    % Condensador, reactor o
                                    % transformador2D con tap
                                    id_global = this.VarOpt(i).entrega_id_global();
                                    indice_opt = this.VarOpt(i).entrega_varopt_operacion('Tap', oper);
                                    tap = this.ResOptimizacion(indice_opt);
                                    
                                    % busca índice en TapSerie o TapParal
                                    encontrado = false;
                                    if isa(this.VarOpt(i), 'cmElementoSerie')
                                        for j = 1:length(this.pResEvaluacion.IdTapSerie)
                                            if this.pResEvaluacion.IdTapSerie(j,1) == id_global
                                                id_res = this.pResEvaluacion.IdTapSerie(j,2);
                                                this.pResEvaluacion.TapSerie(id_res, oper) = tap;
                                                encontrado = true;
                                                break;
                                            end
                                        end
                                    else
                                        for j = 1:length(this.pResEvaluacion.IdTapParal)
                                            if this.pResEvaluacion.IdTapParal(j,1) == id_global
                                                id_res = this.pResEvaluacion.IdTapParal(j,2);
                                                this.pResEvaluacion.TapParal(id_res, oper) = tap;
                                                encontrado = true;
                                                break;
                                            end
                                        end
                                    end
                                    if ~encontrado
                                        error = MException('cOPF:escribe_resultados','Error de programación. No se encontró la relación para tap serie o paralelo');
                                        throw(error)
                                    end
                                otherwise
                                    error = MException('cOPF:escribe_resultados',...
                                        ['Inconsistencia en los datos en variable de control. Tipo ' this.UnidadesVarOpt{i} ' no corresponde']);
                                    throw(error)
                            end
                        case 'VariableEstado'
                            switch this.UnidadesVarOpt{i}
                                case 'V'
                                    % Voltaje de buses
                                    vn = this.VarOpt(i).entrega_vn();
                                    id_global = this.VarOpt(i).entrega_id_global();
                                    indice_opt = this.VarOpt(i).entrega_varopt_operacion('V', oper);
                                    voltaje = this.ResOptimizacion(indice_opt)*vn;
                                    
                                    this.pResEvaluacion.VoltajeBuses(id_global, oper) = voltaje;
                                    if this.iNivelDebug > 1
                                        % se muestran los resultados detallados en pantalla
                                        el_red = this.VarOpt(i).entrega_elemento_red();
                                        text = ['Subestacion '  el_red.entrega_nombre() ...
                                                ' tiene voltaje'  num2str(voltaje)];
                                        disp(text);
                                    end
                                case 'Theta'
                                    % ángulo de las subestaciones 
                                    id_global = this.VarOpt(i).entrega_id_global();
                                    indice_opt = this.VarOpt(i).entrega_varopt_operacion('Theta', oper);
                                    theta = this.ResOptimizacion(indice_opt);
                                    
                                    this.pResEvaluacion.AnguloBuses(id_global, oper) = theta/pi*180;
                                    if this.iNivelDebug > 1
                                        % se muestran los resultados detallados en pantalla
                                        el_red = this.VarOpt(i).entrega_elemento_red();
                                        text = ['Subestacion '  el_red.entrega_nombre() ...
                                                ' tiene angulo '  num2str(theta/pi*180)];
                                        disp(text);
                                    end
                                otherwise
                                    error = MException('cOPF:escribe_resultados',...
                                        ['Inconsistencia en los datos en variable de estado. Tipo ' this.UnidadesVarOpt{i} ' no corresponde']);
                                    throw(error)
                            end
                        case 'VariableAuxiliar'
                            switch this.UnidadesVarOpt{i}
                                case 'P'
                                    % elemento en serie (línea o
                                    % transformador 2D)
                                    sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
                                    id_global = this.VarOpt(i).entrega_id_global();
                                    indice_opt = this.VarOpt(i).entrega_varopt_operacion('P', oper);
                                    flujo_p = this.ResOptimizacion(indice_opt)*sbase;
                                    this.pResEvaluacion.FlujoSerieP(id_global, oper) = flujo_p;
                                case 'Q'
                                    sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
                                    % en este caso puede ser un elemento en
                                    % serie o paralelo, por lo que hay que
                                    % identificar el tipo
                                    id_global = this.VarOpt(i).entrega_id_global();
                                    indice_opt = this.VarOpt(i).entrega_varopt_operacion('Q', oper);
                                    flujo_q = this.ResOptimizacion(indice_opt)*sbase;
                                    if isa(this.VarOpt(i), 'cmElementoParalelo')
                                        this.pResEvaluacion.InyeccionParalQ(id_global, oper) = flujo_q;
                                    elseif isa(this.VarOpt(i), 'cmElementoSerie')
                                        this.pResEvaluacion.InyeccionSerieQ(id_global, oper) = flujo_q;
                                    else
                                        error = MException('cOPF:escribe_resultados','Tipo de elemento no coincide');
                                        throw(error)
                                    end
                                case 'Error_pos'
                                    % en este caso puede ser linea, trafo o
                                    % buses
                                    if isa(this.VarOpt(i), 'cmElementoSerie')
                                        % En teoría no hay que hacer nada,
                                        % ya que los flujos por los
                                        % elementos en serie se calculan a
                                        % partir de los voltajes y ángulos.
                                        % Esta variable sirve sólo para
                                        % facilitar la solución del
                                        % problema de optimización
                                    elseif isa(this.VarOpt(i), 'cmBus')
                                        vn = this.VarOpt(i).entrega_vn();
                                        id_global = this.VarOpt(i).entrega_id_global();
                                        indice_opt = this.VarOpt(i).entrega_varopt_operacion('Error_pos', oper);
                                        error_voltaje = this.ResOptimizacion(indice_opt)*vn;
                                    
                                        this.pResEvaluacion.VoltajeBuses(id_global, oper) = this.pResEvaluacion.VoltajeBuses(id_global, oper) + error_voltaje;
                                        if this.iNivelDebug > 1
                                            % se muestran los resultados detallados en pantalla
                                            el_red = this.VarOpt(i).entrega_elemento_red();
                                            text = ['Subestacion '  el_red.entrega_nombre() ...
                                                    ' tiene error de voltaje: '  num2str(error_voltaje)...
                                                    ' Voltaje original: ' num2str(this.pResEvaluacion.VoltajeBuses(id_global, oper)-error_voltaje)...
                                                    ' Voltaje nuevo: ' num2str(this.pResEvaluacion.VoltajeBuses(id_global, oper))];
                                            disp(text);
                                        end
                                    end
                                case 'Error_neg'
                                    % en este caso puede ser linea, trafo o
                                    % buses
                                    if isa(this.VarOpt(i), 'cmElementoSerie')
                                        % En teoría no hay que hacer nada,
                                        % ya que los flujos por los
                                        % elementos en serie se calculan a
                                        % partir de los voltajes y ángulos.
                                        % Esta variable sirve sólo para
                                        % facilitar la solución del
                                        % problema de optimización
                                    elseif isa(this.VarOpt(i), 'cmBus')
                                        vn = this.VarOpt(i).entrega_vn();
                                        id_global = this.VarOpt(i).entrega_id_global();
                                        indice_opt = this.VarOpt(i).entrega_varopt_operacion('Error_neg', oper);
                                        error_voltaje = this.ResOptimizacion(indice_opt)*vn;
                                    
                                        this.pResEvaluacion.VoltajeBuses(id_global, oper) = this.pResEvaluacion.VoltajeBuses(id_global, oper) - error_voltaje;
                                        if this.iNivelDebug > 1
                                            % se muestran los resultados detallados en pantalla
                                            el_red = this.VarOpt(i).entrega_elemento_red();
                                            text = ['Subestacion '  el_red.entrega_nombre() ...
                                                    ' tiene error de voltaje negativo: '  num2str(error_voltaje)...
                                                    ' Voltaje original: ' num2str(this.pResEvaluacion.VoltajeBuses(id_global, oper)+error_voltaje)...
                                                    ' Voltaje nuevo: ' num2str(this.pResEvaluacion.VoltajeBuses(id_global, oper))];
                                            disp(text);
                                        end
                                    end
                                otherwise
                                    error = MException('cOPF:escribe_resultados',...
                                        ['Inconsistencia en los datos en variable auxiliar. Tipo ' this.UnidadesVarOpt{i} ' no corresponde']);
                                    throw(error)
                            end
                        otherwise
                            error = MException('cOPF:escribe_resultados',...
                                ['Inconsistencia en los datos. Tipo de variable de control ' this.TipoVarOpt{i} ' no corresponde']);
                            throw(error)
                    end
                end
            end
                    
            % cálculo del flujo en líneas y transformadores
            % valores de flujos no fueron incluido en etapa anterior, ya
            % que sólo sirven para facilitar la optimización
            eserie = this.pSM.entrega_elementos_serie();
            for oper = 1:length(this.vPuntosOperacion)
                for i = 1:length(eserie)
                    % se extrae información de los flujos para comparar si
                    % es correcto o no
                    id_eserie_p = eserie(i).entrega_varopt_operacion('P', oper);
                    bus1 = eserie(i).entrega_bus1();
                    bus2 = eserie(i).entrega_bus2();
                    id_t1 = bus1.entrega_varopt_operacion('Theta', oper);
                    id_t2 = bus2.entrega_varopt_operacion('Theta', oper);
                    t1 = this.ResOptimizacion(id_t1);
                    t2 = this.ResOptimizacion(id_t2);
                    if strcmp(this.pParOpt.entrega_tipo_flujo(), 'DC')
                        x = eserie(i).entrega_reactancia();
                        if this.pParOpt.entrega_flujo_dc_con_perdidas()
                            error = MException('cOPF:escribe_resultados','Flujo DC con pérdidas aún no implementado');
                            throw(error)
                        else
                            flujo_p = (t1-t2)/x;
                            flujo_q = 0;
                        end
                    else
                        v1 = bus1.entrega_varopt_operacion('V', oper);
                        v2 = bus2.entrega_varopt_operacion('V', oper);
                        error = MException('cOPF:escribe_resultados','Flujo AC aún no implementado');
                        throw(error)
                    end
                    id_global = eserie(i).entrega_id_global();
                    this.pResEvaluacion.FlujoSerieP(id_global, oper) = flujo_p;
                    this.pResEvaluacion.FlujoSerieQ(id_global, oper) = flujo_q;

                    if this.iNivelDebug > 1
                        text = ['Flujo elemento serie (S = P + jQ): ', eserie(i).entrega_elemento_red().entrega_nombre(), ...
                                ' = ', num2str(flujo_p), '+ j(', num2str(flujo_q)];
                        disp(text);
                        text = ['Abs. Flujo ||S|| = ', ...
                                num2str(abs(complex(flujo_p, flujo_q))), '. Capacidad linea: ', num2str(eserie(i).entrega_elemento_red().entrega_sr())];
                        disp(text);
                    end
                    % TODO RAMRAM: evalúa el error cometido por la optimización, e.g.
                    % el valor del flujo Error_pos y Error_neg
                end
            end
            this.pResEvaluacion.inserta_resultados_en_sep();
        end
        
        function escribe_balance_energia(this, oper)
            if strcmp(this.pParOpt.entrega_tipo_flujo(), 'AC')
                this.escribe_balance_energia_ac(oper);
            else
                this.escribe_balance_energia_dc(oper);
            end
        end

        function escribe_balance_energia_dc(this, oper)
            pBuses = this.pSM.entrega_buses();
            for i = 1:length(pBuses)
                this.iIndiceEq = this.iIndiceEq +1;
                
                % Balance de potencia activa en bus
                %generadores
                pGeneradores = pBuses(i).entrega_generadores();
                for j = 1:length(pGeneradores)
                    if pGeneradores(j).entrega_flag_opf()
                        indice_gen = pGeneradores(j).entrega_varopt_operacion('P', oper);
                        this.Aeq(this.iIndiceEq,indice_gen) = 1;
                    end
                end
                
                %consumos
                if ~isempty(this.pAdmSc)
                    consumo_residual_p = pBuses(i).entrega_p_const_nom_opf(this.iEtapa, oper);
                else
                    consumo_residual_p = pBuses(i).entrega_p_const_nom_opf();
                end
                this.beq(this.iIndiceEq) = -consumo_residual_p;
                
                % elementos serie
                eserie = pBuses(i).entrega_elementos_serie();
                for j = 1:length(eserie)
                    indice_eserie_p = eserie(j).entrega_varopt_operacion('P', oper);
                    
                    bus1 = eserie(j).entrega_bus1();
                    bus2 = eserie(j).entrega_bus2();
                    if bus1 == pBuses(i)
                        % inicio linea corresponde a este bus, por lo tanto
                        % flujo sale
                        signo = -1;
                    elseif bus2 == pBuses(i)
                        signo = 1;
                    else
                        error = MException('cOPF:escribe_balance_energia','Inconsistencia en los datos, ya que elemento serie no pertenece a bus');
                        throw(error)
                    end
                    this.Aeq(this.iIndiceEq,indice_eserie_p) = signo;
                    if this.iNivelDebug > 1
                        this.NombreEq{this.iIndiceEq} = strcat('req_be_', 'B', num2str(pBuses(i).entrega_id_global()), '_O', num2str(oper));
                    end
                end
            end
        end
        
        function escribe_balance_energia_ac(this, oper)
            pBuses = this.pSM.entrega_buses();
            for i = 1:length(pBuses)
                indice_p = this.iIndiceEq + 1; %indice para potencia activa
                indice_q = this.iIndiceEq + 2; % indice para potencia reactiva
                this.iIndiceEq = this.iIndiceEq +2;
                
                % Balance de potencia activa y reactiva por bus
                %generadores
                pGeneradores = pBuses(i).entrega_generadores();
                for j = 1:length(pGeneradores)
                    if pGeneradores(j).entrega_flag_opf()
                        indice_gen = pGeneradores(j).entrega_varopt_operacion('P', oper);
                        this.Aeq(indice_p,indice_gen) = 1;
                    end
                    
                    if pGeneradores(j).controla_tension()
                        indice_gen = pGeneradores(j).entrega_varopt_operacion('Q', oper);
                        this.Aeq(indice_q,indice_gen) = 1;
                    end
                end
                
                %consumos
                if ~isempty(this.pAdmSc)
                    consumo_residual_p = pBuses(i).entrega_p_const_nom_opf(this.iEtapa, oper);
                else
                    consumo_residual_p = pBuses(i).entrega_p_const_nom_opf();
                end
                this.beq(indice_p) = -consumo_residual_p;

                consumo_residual_q = pBuses(i).entrega_q_const_nom_opf();
                this.beq(indice_q) = consumo_residual_q;
                
                % elementos serie
                eserie = pBuses(i).entrega_elementos_serie();
                for j = 1:length(eserie)
                    indice_eserie_p = eserie(j).entrega_varopt_operacion('P', oper);
                    indice_eserie_q = eserie(j).entrega_varopt_operacion('Q', oper);
                    
                    bus1 = eserie(j).entrega_bus1();
                    bus2 = eserie(j).entrega_bus2();                    

                    if bus1 == pBuses(i)
                        signo = -1;
                    elseif bus2 == pBuses(i)
                        signo = 1;
                    else
                        error = MException('cOPF:escribe_balance_energia','Inconsistencia en los datos, ya que elemento serie no pertenece a bus');
                        throw(error)
                    end
                    
                    this.Aeq(indice_p,indice_eserie_p) = signo;
                    this.Aeq(indice_q,indice_eserie_q) = signo;
                    if this.iNivelDebug > 1
                        this.NombreEq{indice_p} = strcat('req_be_P_', 'B', num2str(pBuses(i).entrega_id_global()), '_O', num2str(oper));
                        this.NombreEq{indice_q} = strcat('req_be_Q_', 'B', num2str(pBuses(i).entrega_id_global()), '_O', num2str(oper));
                    end
                    
                end
            end
        end
        
        function escribe_relaciones_flujos_angulos(this, oper)
            if strcmp(this.pParOpt.entrega_tipo_flujo(), 'AC')
                this.escribe_relaciones_flujos_angulos_ac(oper)
            else
                this.escribe_relaciones_flujos_angulos_dc(oper)
            end
        end
        
        function escribe_relaciones_flujos_angulos_dc(this, oper)
            eserie = this.pSM.entrega_elementos_serie();
            for i = 1:length(eserie)
                this.iIndiceEq = this.iIndiceEq +1;
                
                id_eserie = eserie(i).entrega_varopt_operacion('P', oper);
                bus1 = eserie(i).entrega_bus1();
                bus2 = eserie(i).entrega_bus2();
                id_t1 = bus1.entrega_varopt_operacion('Theta', oper);
                id_t2 = bus2.entrega_varopt_operacion('Theta', oper);
                
                % TODO RAMRAM: HAY QUE VER SI ES CORRECTO PARA TRANSFORMADORES!!!
                x = eserie(i).entrega_reactancia();

                this.Aeq(this.iIndiceEq,id_eserie) = x;
                this.Aeq(this.iIndiceEq,id_t1) = -1;
                this.Aeq(this.iIndiceEq,id_t2) = 1;
                this.beq(this.iIndiceEq) = 0;
                
                if this.pParOpt.entrega_flujo_dc_con_perdidas()
                    % se agregan las pérdidas. Aún no está implementado
                    % porque introduce relaciones cuadráticas con los
                    % ángulos
                    % fórmula: r/(2x^2)*(t1-t2)^2
                    r = eserie(i).entrega_resistencia_pu();
                    factor = r/(2*x^2);
                    %...
                end
                
                if this.iNivelDebug > 1
                    if isa(eserie(i).entrega_elemento_red(), 'cLinea')
                        texto = 'L';
                    else
                        texto = 'Tr';
                    end
                	this.NombreEq{this.iIndiceEq} = strcat('req_flujos_angulos', texto, num2str(eserie(i).entrega_id_global()), '_O', num2str(oper));
                end
                
            end
        end
        
        function escribe_relaciones_flujos_angulos_ac(this, oper)
%             eserie = this.pSM.entrega_elementos_serie();
%             for i = 1:length(eserie)
%                 this.iIndiceEq = this.iIndiceEq +1;
%                 idx_p = this.iIndiceEq;
%                 if strcmp(this.pParOpt.tipo_flujo(), 'AC')
%                     this.iIndiceEq = this.iIndiceEq +1;
%                     idx_q = this.iIndiceEq;
%                 end
%                 
%                 bus1 = eserie(i).entrega_bus1();
%                 bus2 = eserie(i).entrega_bus2();
%                 if strcmp(this.pParOpt.tipo_flujo(), 'AC')
%                     v1 = bus1.entrega_varopt_operacion('V', oper);
%                     v2 = bus2.entrega_varopt_operacion('V', oper);
%                 else
%                     v1 = 1;
%                     v2 = 1;
%                 end
%                 t1 = bus1.entrega_varopt_operacion('Theta', oper);
%                 t2 = bus2.entrega_varopt_operacion('Theta', oper);
%                 
%                 id_p = eserie(i).entrega_varopt_operacion('P', oper);
%                 if strcmp(this.pParOpt.tipo_flujo(), 'AC')
%                     id_q = eserie(i).entrega_varopt_operacion('Q', oper);
%                 end
%                 [~, y12, ~, ~] = eserie.entrega_cuadripolo();
%                 
%                 this.Aeq(idx_p,id_p) = -1;
%                 % RELACIONES NO LINEARES!!!! Hay que ver cómo se hace
%                 % aweonado!!!
%             end
        end
        
        function escribe_restricciones_flujos_serie(this, oper)
            if strcmp(this.pParOpt.entrega_tipo_flujo(), 'AC')
                this.escribe_restricciones_flujos_serie_ac(oper);
            else
                this.escribe_restricciones_flujos_serie_dc(oper);
            end
        end
        
        function escribe_restricciones_flujos_serie_dc(this, oper)
            eserie = this.pSM.entrega_elemento_serie();
            for i = 1:length(eserie)
                this.iIndiceIneq = this.iIndiceIneq + 1;
                capacidad = eserie(i).entrega_sr();
                
                indice_elemento = eserie(i).entrega_varopt_operacion('P', oper);
                indice_error_pos = eserie(i).entrega_varopt_operacion('Error_pos', oper);
                indice_error_neg = eserie(i).entrega_varopt_operacion('Error_neg', oper);
                
                % restricciones del flujo máximo positivo
                this.Aineq(this.iIndiceIneq, indice_elemento) = 1;
                this.Aineq(this.iIndiceIneq, indice_error_pos) = -1;
                this.bineq(this.iIndiceIneq) = capacidad;

                if this.iNivelDebug > 1
                    if isa(eserie(i).entrega_elemento_red(), 'cLinea')
                        texto = 'L';
                    else
                        texto = 'Tr';
                    end
                	this.NombreIneq{this.iIndiceIneq} = strcat('rdes_ErrorPos_', texto, num2str(eserie(i).entrega_id_global()), '_O', num2str(oper));
                end
                
                % restricciones del flujo máximo negativo
                this.iIndiceIneq = this.iIndiceIneq + 1;
                this.Aineq(this.iIndiceIneq, indice_elemento) = -1;
                this.Aineq(this.iIndiceIneq, indice_error_neg) = -1;
                this.bineq(this.iIndiceIneq) = capacidad;
                if this.iNivelDebug > 1
                    if isa(eserie(i).entrega_elemento_red(), 'cLinea')
                        texto = 'L';
                    else
                        texto = 'Tr';
                    end
                	this.NombreIneq{this.iIndiceIneq} = strcat('rdes_ErrorNeg_', texto, num2str(eserie(i).entrega_id_global()), '_O', num2str(oper));
                end
            end
        end

        function escribe_restricciones_flujos_serie_ac(this, oper)
            % TODO RAMRAM: Falta implementar
            eserie = this.pSM.entrega_elemento_serie();
            for i = 1:length(eserie)
                this.iIndiceIneq = this.iIndiceIneq + 1;
                capacidad = eserie(i).entrega_sr();
                
                indice_elemento = eserie(i).entrega_varopt_operacion('P', oper);
                indice_error_pos = eserie(i).entrega_varopt_operacion('Error_pos', oper);
                indice_error_neg = eserie(i).entrega_varopt_operacion('Error_neg', oper);
                
            end
        end
        function evaluacion = entrega_evaluacion(this)
            evaluacion = this.pResEvaluacion;
        end
        
        function inicializa_resultados(this)
            % los resultados se ingresan independiente del subsistema, ya
            % que OPF se resuelve automáticamente para todos los
            % subsistemas
            % elementos serie

            % inicializa punteros y containers
            eserie = this.pSM.entrega_elemento_serie();
            epar = this.pSM.entrega_elemento_paralelo();
            buses = this.pSM.entrega_buses();
            
            % tap de los elementos serie y paralelos
            eserie_tap = this.pSM.entrega_elemento_serie_flag_opf('cTransformador2D');
            eparal_tap = this.pSM.entrega_elemento_paralelo_flag_opf('cCondensador');
            eparal_tap = [eparal_tap this.pSM.entrega_elemento_paralelo_flag_opf('cReactor')];

            this.pResEvaluacion.IdTapSerie = zeros(length(eserie_tap), 2);
            this.pResEvaluacion.IdTapParal = zeros(length(eparal_tap), 2);
            this.pResEvaluacion.TapSerie = zeros(length(eserie_tap),length(this.vPuntosOperacion));
            this.pResEvaluacion.TapParal = zeros(length(eparal_tap),length(this.vPuntosOperacion));
            % inicializa los índices
            for i = 1:length(eserie_tap)
                id_global = eserie_tap(i).entrega_id_global();
                this.pResEvaluacion.IdTapSerie(i, 1) = id_global;
                this.pResEvaluacion.IdTapSerie(i, 2) = i;
            end
            for i = 1:length(eparal_tap)
                id_global = eparal_tap(i).entrega_id_global();
                this.pResEvaluacion.IdTapParal(i, 1) = id_global;
                this.pResEvaluacion.IdTapParal(i, 2) = i;
            end
            
            this.pResEvaluacion.FlujoSerieP = zeros(length(eserie), length(this.vPuntosOperacion));
            this.pResEvaluacion.FlujoSerieQ = zeros(length(eserie), length(this.vPuntosOperacion));
            this.pResEvaluacion.InyeccionParalP = zeros(length(epar), length(this.vPuntosOperacion));
            this.pResEvaluacion.InyeccionParalQ = zeros(length(epar), length(this.vPuntosOperacion));
            this.pResEvaluacion.AnguloBuses = zeros(length(buses), length(this.vPuntosOperacion));
            this.pResEvaluacion.VoltajeBuses = zeros(length(buses), length(this.vPuntosOperacion));
            this.pResEvaluacion.CostoGeneracion = zeros(length(this.vPuntosOperacion),1);
            this.pResEvaluacion.CostoRedespacho = zeros(length(this.vPuntosOperacion),1);
            
            % Nombres
            this.pResEvaluacion.ElementosSerie = eserie;
            this.pResEvaluacion.ElementosParalelo = epar;
            this.pResEvaluacion.Buses = buses;            
        end

        function imprime_problema_optimizacion(this)
            % sólo en modo debug. imprime el problema en archivo externo
            % determina nombre de variables de optimización
            % esto se hace sólo aquí, para no afectar la performance del
            % programa con datos que no se necesitan
            %[NombreIneq, NombreEq] = this.escribe_nombre_restricciones();
            
            %cantidad_var_decision = length(this.vPuntosOperacion) * (length(this.pSEP.GeneradoresDespachables) + ...
            %    length(this.pSEP.Subestaciones) + 3*length(this.pSEP.Lineas));

            % nombre detallado de las variables
            docID = fopen(this.nombre_archivo_detalle_variables,'w');
            fprintf(docID, 'Detalle de variables en OPF\n\n');
            texto = sprintf('%5s %50s', 'Variable', 'Detalle');
            fprintf(docID, strcat(texto, '\n'));
            for i = 1:length(this.NombreVariables)
                texto = sprintf('%5s %50s', this.NombreVariables{i}, this.NombreDetalladoVariables{i});
                fprintf(docID, strcat(texto, '\n'));
            end
            fclose(docID);
            
            NombreVariablesUtilizar = this.NombreDetalladoVariables;
            %NombreVariablesUtilizar = this.NombreVariables;
            
            docID = fopen(this.nombre_archivo_problema_opt,'w');
            fprintf(docID, 'Formulacion matemática OPF\n');
            fprintf(docID, ['Tipo problema : ' this.pParOpt.entrega_tipo_problema()]);
            fprintf(docID, ['\nFunción objetivo: ' this.pParOpt.entrega_funcion_objetivo()]);
            fprintf(docID, ['\nTipo flujo de potencia: ' this.pParOpt.entrega_tipo_flujo()]);
            fprintf(docID, ['\nTipo restricciones seguridad: ' this.pParOpt.entrega_tipo_restricciones_seguridad()]);
            if strcmp(this.pParOpt.entrega_tipo_flujo(),'AC')
                fprintf(docID, ['\nMétodo optimización: ' this.pParOpt.entrega_metodo_optimizacion()]);
                fprintf(docID, ['\nOptimiza voltaje operación: ' this.pParOpt.entrega_optimiza_voltaje_operacion()]);
            else
                if this.pParOpt.entrega_flujo_dc_con_perdidas()
                    val = 'si';
                else
                    val = 'no';
                end
                fprintf(docID, ['\nConsidera pérdidas: ' val]);
            end
            fprintf(docID, '\n\n');
            
            fprintf(docID, 'Funcion objetivo\n');
            primero = true;
            for i = 1:length(this.Fobj)
                if this.Fobj(i) ~= 0
                    val = round(this.Fobj(i),3);                    
                    if primero
                        text = strcat(num2str(val),'(',NombreVariablesUtilizar{i},')');
                        primero = false;
                    else
                        if this.Fobj(i) > 0
                            text = strcat(text, ' + ',num2str(val),'(', NombreVariablesUtilizar{i},')');
                        else
                            text = strcat(text, ' - ',num2str(abs(val)),'(',NombreVariablesUtilizar{i},')');
                        end
                        if length(text) > 170
                            text = strcat(text,'\n');
                            fprintf(docID, text);
                            primero = true;
                        end
                    end
                end
            end
            text = strcat(text,'\n');
            fprintf(docID, text);
            % restricciones
            % restricciones de desigualdad
            fprintf(docID, 'Restricciones de desigualdad:\n');
            for i = 1:length(this.bineq)
                nombre_ineq = this.NombreIneq{i};
                fprintf(docID, strcat(nombre_ineq,':\n'));
                primero = true;
                for j = 1:length(this.VarOpt)
                    if this.Aineq(i,j) ~= 0
                        val = this.Aineq(i,j);                    
                        if primero
                            if val == 1
                                text = strcat('(',NombreVariablesUtilizar{j},')');
                            elseif val == -1
                                text = strcat('-', '(' ,NombreVariablesUtilizar{j}, ')');
                            else
                                text = strcat(num2str(val), '(', NombreVariablesUtilizar{j}, ')');
                                %error = MException('cMILPOpt:imprime_problema_optimizacion','valor restriccion de desigualdad debe ser 1 o -1');
                                %throw(error)
                            end
                            primero = false;
                        else
                            if val == 1
                                text = strcat(text, ' + ', '(', NombreVariablesUtilizar{j}, ')');
                            elseif val == -1
                                text = strcat(text, ' - ', '(', NombreVariablesUtilizar{j}, ')');
                            elseif val > 0
                                text = strcat(text, ' + ', num2str(val), '(', NombreVariablesUtilizar{j}, ')');
                            else
                                text = strcat(text, ' - ', num2str(abs(val)), '(', NombreVariablesUtilizar{j}, ')');
                                %error = MException('cMILPOpt:imprime_problema_optimizacion','valor restriccion de desigualdad debe ser 1 o -1');
                                %throw(error)
                            end
                            if length(text) > 170
                                text = strcat(text,'\n');
                                fprintf(docID, text);
                                primero = true;
                            end
                        end
                    end
                end
                text = strcat(text,' <= ', num2str(this.bineq(i)),'\n\n');
                fprintf(docID, text);
            end

            fprintf(docID, 'Restricciones de igualdad:\n');
            for i = 1:length(this.beq)
                nombre_eq = this.NombreEq{i};
                fprintf(docID, strcat(nombre_eq,':\n'));
                primero = true;
                for j = 1:length(this.VarOpt)
                    if this.Aeq(i,j) ~= 0
                        val = this.Aeq(i,j);                    
                        if primero
                            if val == 1
                                text = strcat('(',NombreVariablesUtilizar{j},')');
                            elseif val == -1
                                text = strcat('-','(',NombreVariablesUtilizar{j},')');
                            elseif val > 0
                                text = strcat(num2str(round(val,3)),'(',NombreVariablesUtilizar{j},')');
                            else
                                text = strcat('-', num2str(abs(round(val,3))),'(',NombreVariablesUtilizar{j},')');
                            end
                            primero = false;
                        else
                            if val == 1
                                text = strcat(text, ' + ','(',NombreVariablesUtilizar{j},')');
                            elseif val == -1
                                text = strcat(text, ' - ','(',NombreVariablesUtilizar{j},')');
                            elseif val > 0
                                text = strcat(text, ' + ', num2str(round(val,3)),'(',NombreVariablesUtilizar{j},')');
                            else
                                text = strcat(text, ' - ', num2str(abs(round(val,3))),'(',NombreVariablesUtilizar{j},')');
                            end
                            if length(text) > 170
                                text = strcat(text,'\n');
                                fprintf(docID, text);
                                primero = true;
                            end
                        end
                    end
                end
                text = strcat(text,' = ', num2str(this.beq(i)),'\n\n');
                fprintf(docID, text);
            end
            
            % límites de las variables
            fprintf(docID, 'Limites variables de decision:\n');
            for i = 1:length(this.VarOpt)
                text = strcat(num2str(this.lb(i)), ' <= ', NombreVariablesUtilizar{i}, ' <= ', num2str(this.ub(i)), '\n');
                fprintf(docID, text);
            end
            fprintf(docID, 'fin');
            fclose(docID);
        end
        
        function inserta_varopt(this, vector, tipo_variable, unidades)
            if ~isempty(vector)
                this.VarOpt = [this.VarOpt; vector];
                for i = 1:length(vector)
                    this.TipoVarOpt{end+1} = tipo_variable;
                    this.UnidadesVarOpt{end+1} = unidades;
                end
            end
        end
                
        function ingresa_nombres(this, indice_varopt, oper, tipo_varopt, unidades_varopt)
            switch tipo_varopt
                case 'VariableControl'
                    this.NombreVariables{indice_varopt} = strcat('u', num2str(indice_varopt));
                    if strcmp(unidades_varopt, 'P')
                        % Se trata de un generador
                        id_bus = this.VarOpt(indice_varopt).entrega_bus().entrega_elemento_red().entrega_id();
                        texto = strcat('P_G', num2str(this.VarOpt(indice_varopt).entrega_elemento_red().entrega_id()), ...
                                       '_B', num2str(id_bus), '_O', num2str(oper));
                        this.NombreDetalladoVariables{indice_varopt} = texto;
                    elseif strcmp(unidades_varopt, 'V')
                        % voltaje en bus (como variable de control)
                        id_bus = this.VarOpt(indice_varopt).entrega_elemento_red().entrega_id();
                        texto = strcat('Theta_B', num2str(id_bus), ...
                                       '_O', num2str(oper));
                        this.NombreDetalladoVariables{indice_varopt} = texto;
                    else
                        error = MException('cOPF:ingresa_nombres',...
                                           ['Inconsistencia en los datos. Tipo de variable unidad en variable de control '...
                                             unidades_varopt ' no implementada']);
                        throw(error)
                    end
                case 'VariableEstado'
                    this.NombreVariables{indice_varopt} = strcat('x', num2str(indice_varopt));
                    if strcmp(unidades_varopt, 'V')
                        % voltaje en bus (como variable de estado)
                    elseif strcmp(unidades_varopt, 'Theta')
                        id_bus = this.VarOpt(indice_varopt).entrega_elemento_red().entrega_id();
                        texto = strcat('Theta_B', num2str(id_bus), ...
                                       '_O', num2str(oper));
                        this.NombreDetalladoVariables{indice_varopt} = texto;
                    else
                        error = MException('cOPF:ingresa_nombres',...
                                           ['Inconsistencia en los datos. Tipo de variable unidad en variable de estado '...
                                             unidades_varopt ' no implementada']);
                        throw(error)
                    end
                case 'VariableAuxiliar'
                    this.NombreVariables{indice_varopt} = strcat('y', num2str(indice_varopt));
                    if strcmp(unidades_varopt, 'P')
                        % Potencia activa en una línea o un trafo
                        id_global = this.VarOpt(indice_varopt).entrega_elemento_red().entrega_id();
                        id_global_bus1 = this.VarOpt(indice_varopt).entrega_bus1().entrega_elemento_red().entrega_id();
                        id_global_bus2 = this.VarOpt(indice_varopt).entrega_bus2().entrega_elemento_red().entrega_id();
                        if isa(this.VarOpt(indice_varopt).entrega_elemento_red(), 'cLinea')
                            texto = strcat('P_L', num2str(id_global), ...
                                           '_B', num2str(id_global_bus1), ...
                                           '_', num2str(id_global_bus2), ...
                                           '_O', num2str(oper));
                            this.NombreDetalladoVariables{indice_varopt} = texto;
                        elseif isa(this.VarOpt(indice_varopt).entrega_elemento_red(), 'cTransformador2D')
                            texto = strcat('P_Tr', num2str(id_global), ...
                                           '_B', num2str(id_global_bus1), ...
                                           '_', num2str(id_global_bus2), ...
                                           '_O', num2str(oper));
                            this.NombreDetalladoVariables{indice_varopt} = texto;
                        else
                            error = MException('cOPF:ingresa_nombres',...
                                               ['Inconsistencia en los datos. Tipo elemento de red ' ...
                                               class(this.VarOpt(indice_varopt).entrega_elemento_red())...
                                               ' no está implementado en variable auxiliar y tipo variable P']);
                            throw(error)
                        end
                    elseif strcmp(unidades_varopt, 'Q')
                        % Puede ser Q de un generador, en una línea o un
                        % trafo
                        id_global = this.VarOpt(indice_varopt).entrega_elemento_red().entrega_id();
                        if isa(this.VarOpt(indice_varopt).entrega_elemento_red(), 'cLinea')
                            id_global_bus1 = this.VarOpt(indice_varopt).entrega_bus1().entrega_elemento_red().entrega_id();
                            id_global_bus2 = this.VarOpt(indice_varopt).entrega_bus2().entrega_elemento_red().entrega_id();
                            texto = strcat('Q_L', num2str(id_global), ...
                                           '_B', num2str(id_global_bus1), ...
                                           '_', num2str(id_global_bus2), ...
                                           '_O', num2str(oper));
                            this.NombreDetalladoVariables{indice_varopt} = texto;
                        elseif isa(this.VarOpt(indice_varopt).entrega_elemento_red(), 'cTransformador2D')
                            id_global_bus1 = this.VarOpt(indice_varopt).entrega_bus1().entrega_elemento_red().entrega_id();
                            id_global_bus2 = this.VarOpt(indice_varopt).entrega_bus2().entrega_elemento_red().entrega_id();
                            texto = strcat('Q_Tr', num2str(id_global), ...
                                           '_B', num2str(id_global_bus1), ...
                                           '_', num2str(id_global_bus2), ...
                                           '_O', num2str(oper));
                            this.NombreDetalladoVariables{indice_varopt} = texto;
                        elseif isa(this.VarOpt(indice_varopt).entrega_elemento_red(), 'cGenerador')
                            id_global_bus = this.VarOpt(indice_varopt).entrega_bus().entrega_elemento_red().entrega_id();
                            texto = strcat('Q_G', num2str(id_global), ...
                                           '_B', num2str(id_global_bus), ...
                                           '_O', num2str(oper));
                            this.NombreDetalladoVariables{indice} = texto;
                        else
                            error = MException('cOPF:ingresa_nombres',...
                                               ['Inconsistencia en los datos. Tipo elemento de red ' ...
                                               class(this.VarOpt(indice_varopt).entrega_elemento_red())...
                                               ' no está implementado en variable auxiliar y tipo variable Q']);
                            throw(error)
                        end
                    elseif strcmp(unidades_varopt, 'Error_pos') || strcmp(unidades_varopt, 'Error_neg')
                        % puede ser una línea, un trafo o el voltaje de un
                        % bus
                        id_global = this.VarOpt(indice_varopt).entrega_elemento_red().entrega_id();
                        if isa(this.VarOpt(indice_varopt).entrega_elemento_red(), 'cLinea')
                            id_global_bus1 = this.VarOpt(indice_varopt).entrega_bus1().entrega_elemento_red().entrega_id();
                            id_global_bus2 = this.VarOpt(indice_varopt).entrega_bus2().entrega_elemento_red().entrega_id();
                            texto = strcat(unidades_varopt, '_S_L', num2str(id_global), ...
                                           '_B', num2str(id_global_bus1), ...
                                           '_', num2str(id_global_bus2), ...
                                           '_O', num2str(oper));
                            this.NombreDetalladoVariables{indice_varopt} = texto;
                        elseif isa(this.VarOpt(indice_varopt).entrega_elemento_red(), 'cTransformador2D')
                            id_global_bus1 = this.VarOpt(indice_varopt).entrega_bus1().entrega_elemento_red().entrega_id();
                            id_global_bus2 = this.VarOpt(indice_varopt).entrega_bus2().entrega_elemento_red().entrega_id();
                            texto = strcat(unidades_varopt, '_S_Tr', num2str(id_global), ...
                                           '_B', num2str(id_global_bus1), ...
                                           '_', num2str(id_global_bus2), ...
                                           '_O', num2str(oper));
                            this.NombreDetalladoVariables{indice_varopt} = texto;
                        elseif isa(this.VarOpt(indice_varopt), 'cmBus')
                            id_global_bus = this.VarOpt(indice_varopt).entrega_elemento_red().entrega_id();
                            texto = strcat(unidades_varopt, '_Volt_B', num2str(id_global_bus), ...
                                           '_O', num2str(oper));
                            this.NombreDetalladoVariables{indice} = texto;
                        else
                            error = MException('cOPF:ingresa_nombres',...
                                               ['Inconsistencia en los datos. Tipo elemento de red ' ...
                                               class(this.VarOpt(indice_varopt).entrega_elemento_red())...
                                               ' no está implementado en variable auxiliar y tipo variable Q']);
                            throw(error)
                        end
                    else
                        error = MException('cOPF:ingresa_nombres',...
                                           ['Inconsistencia en los datos. Tipo de variable auxiliar con tipo de estado '...
                                             unidades_varopt ' no implementada']);
                        throw(error)
                    end                        
                otherwise
                        error = MException('cOPF:ingresa_nombres',...
                                           ['Inconsistencia en los datos. Tipo de variable '...
                                             tipo_varopt ' no implementada']);
                        throw(error)
            end
        end
        
        function copia_parametros_optimizacion(this, parametros)
            this.pParOpt.FuncionObjetivo = parametros.FuncionObjetivo;
            this.pParOpt.TipoFlujoPotencia = parametros.TipoFlujoPotencia;
            this.pParOpt.TipoRestriccionesSeguridad = parametros.TipoRestriccionesSeguridad;
            this.pParOpt.TipoProblema = parametros.TipoProblema;
            this.pParOpt.MetodoOptimizacionAC = parametros.MetodoOptimizacionAC;
            this.pParOpt.OptimizaVoltajeOperacion = parametros.OptimizaVoltajeOperacion;
        end

 	end
end