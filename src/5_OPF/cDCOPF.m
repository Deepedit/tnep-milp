classdef cDCOPF < cOPF
    properties
		pSEP = cSistemaElectricoPotencia.empty
        %pAdmOper = cAdministradorEscenariosOperacion.empty
		pResEvaluacion = cResultadoEvaluacionSEP.empty
        pParOpt = cParOptimizacionOPF.empty
        pAdmSc = cAdministradorEscenarios.empty
        Sbase = 0;
        
        VariablesInicializadas = false

        % resultados problema de optimizacion
        ResOptimizacion
        ExitFlag
        DescripcionFlag
        Fval
        Output
        Lambda
                
        % Estructuras con elementos del sep. Contiene indices de operación,
        % indices a balances de energía, indices de restricciones (cuando corresponda), etc.
        Subestaciones = struct()
        Generadores = struct()
        Lineas = struct()
        Trafos = struct()
        Consumos = struct()
        Baterias = struct()
        Embalses = struct()
                
        %UnidadesVarOpt = cell.empty
        iIndiceVarOpt
        iCantPuntosOperacion = 0
        vRepresentatividadPO = []
        bConsideraDependenciaTemporal = false
        vIndicesPOConsecutivos = [] % cuando se consideran baterías y/o sistemas de almacenamiento. Largo indica cant. PO consecutivos. Ancho: indice po desde, indice po hasta
        
        iCantContingenciasGenCons = 0
        iCantContingenciasElSerie = 0
        
        pContingenciasGenCons = cElementoRed.empty
        pContingenciasElSerie = cElementoRed.empty

        % restricciones de reservas mínimas del sistema
        IdRestriccionIResPosDesde = 0
        IdRestriccionIResNegDesde = 0
        IdVarOptPmaxGenDespDesde = 0 % en caso de que estrategia para calcular reservas máximas de subida == 2 (i.e. potencia máxima de inyección de los generadores despachables)

        % restricciones inercia y/o ROCOF. Por cada generador que puede fallar
        IdVarOptInerciaDesde = [] % varopt de la inercia del sistema en caso de falla de los generadores
        IdRestriccionEInerciaDesde = [] % restricciones que calcula la inercia del sistema en caso de falla de los generadores
        IdRestriccionIROCOFDesde = [] % restricción del rocof en caso de falla de los generadores
        
        % Parámetro de ACO. Indica la etapa correspondiente. TODO: Hay que eliminar esta variables. 
        % Por ahora se necesita para cargar los límites de la etapa
        % correspondiente. Estas se tienen que manejar directamente en el SEP
        iEtapa = 0
        iEscenario = 1
        
		Fobj  = [] %funcion objetivo
        Aeq = []  % matriz con restricciones de igualdad
        beq = []  % vector objetivo restricciones de igualdad
        Aineq = [] % matriz con restricciones de desigualdad
        bineq = []  % vector de desigualdades
        lb = [] %valores mínimos de variables de decisión
        ub = [] %valores máximos de variables de decisión
        intcon = [] % indices con las variables binarias
        
        % Sólo en modo debug
        NombreVariables = []
        NombreIneq = []
        NombreEq = []
        
        MuestraDetalleIteraciones = false
        
        iIndiceIneq = 0
        iIndiceEq = 0
        iNivelDebug = 2
        caso_estudio = 'caso_base'
        nombre_archivo = './output/dc_opf.dat'
        nombre_archivo_problema_opt = './output/dc_opf_problem_formulation.dat'
        nombre_archivo_detalle_variables = './output/variables_dc_opf.dat'
    end
    
    methods
	
		function this = cDCOPF(sep, varargin)
			this.pSEP = sep;
            sep.pOPF = this;
            
            this.pParOpt = cParOptimizacionOPF();
            this.Sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            if nargin > 1
                %OPF para planificación
                this.pAdmSc = varargin{1};
                this.iCantPuntosOperacion = this.pAdmSc.entrega_cantidad_puntos_operacion();
                this.vRepresentatividadPO = this.pAdmSc.RepresentatividadPuntosOperacion; % columnas

                this.bConsideraDependenciaTemporal = this.pAdmSc.considera_dependencia_temporal();
                if this.bConsideraDependenciaTemporal
                    this.vIndicesPOConsecutivos = this.pAdmSc.entrega_indices_po_consecutivos();
                end
                % reemplaza parámetros del OPF por los indicados en
                % programa optimización correspondiente
                if nargin > 2
                    this.copia_parametros_optimizacion(varargin{2});
                end
            else
                this.iCantPuntosOperacion = 1;
                this.vRepresentatividadPO = 1;
            end
            % crea resultado evaluacion
            if isempty(sep.pResEvaluacion)
                this.pResEvaluacion = cResultadoEvaluacionSEP(sep, 1, this.pParOpt.NivelDetalleResultados, this.iCantPuntosOperacion); % 1 indica que es OPF
            else
                this.pResEvaluacion = sep.pResEvaluacion;
                if ~this.pResEvaluacion.ContenedoresInicializadosOPF
                    this.pResEvaluacion.inserta_nuevo_tipo_resultado(1, this.pParOpt.NivelDetalleResultados, this.iCantPuntosOperacion);
                end
            end
        end
        
        function inserta_escenario(this, val)
            this.iEscenario = val;
        end
        
        function inserta_cantidad_puntos_operacion(this, cant_po)
            this.iCantPuntosOperacion = cant_po;
        end
        
        function inserta_representatividad_puntos_operacion(this, rep)
            this.vRepresentatividadPO = rep;
        end
        
        function inserta_caso_estudio(this, caso_estudio)
            this.caso_estudio = caso_estudio;
        end
        
        function inserta_etapa(this, nro_etapa)
            % etapa se utiliza para ACO
            this.iEtapa = nro_etapa;
        end
        
        function etapa = entrega_etapa(this)
            etapa = this.iEtapa;
        end
                
        function inserta_sbase(this, val)
            this.Sbase = val;
        end        
                
        function inserta_nivel_debug(this, nivel)
            this.iNivelDebug = nivel;
        end
        
        function nivel = entrega_nivel_debug(this)
            nivel = this.iNivelDebug;
        end
                
		function calcula_despacho_economico(this)
            if this.VariablesInicializadas == false    
                this.iIndiceIneq = 0;
                this.iIndiceEq = 0;
                this.iIndiceVarOpt = 0;
                this.inicializa_variables();
                this.inicializa_contenedores();
                
                this.escribe_funcion_objetivo();
                this.escribe_restricciones();
                this.VariablesInicializadas = true;
            end
            
            if this.iNivelDebug > 1
                this.imprime_problema_optimizacion();
            end
            
			this.optimiza();
            
            if this.pResEvaluacion.ExisteResultadoOPF
                this.pResEvaluacion.borra_evaluacion_actual();
            end
            
            if this.ExitFlag == 1
                % problema tiene solucion óptima
                this.pResEvaluacion.ExisteResultadoOPF = true;
                this.escribe_resultados();
                if this.iNivelDebug > 0
                    this.imprime_resultados_protocolo();
                end
                if this.pParOpt.ExportaResultadosFormatoExcel
                    this.pResEvaluacion.exporta_resultados_formato_excel();
                end  
            else
                this.pResEvaluacion.ExisteResultadoOPF = false;
                if this.iNivelDebug > 0
                    prot = cProtocolo.getInstance;
                    prot.imprime_texto('Problema de optimizacion invalido');
                    prot.imprime_texto(['Estado flag: ' num2str(this.ExitFlag)]);
                end
                % problema no tiene solucion
                % no se escriben resultados porque no tiene sentido
            end
        end
        
        function formula_problema_despacho_economico(this)
            % Esta función se utiliza en caso de querer formular el
            % problema de operación de cero a partir del SEP
            this.iIndiceIneq = 0;
            this.iIndiceEq = 0;
            this.inicializa_variables();
            this.inicializa_contenedores();
			
            this.escribe_funcion_objetivo();
            this.escribe_restricciones();
            this.VariablesInicializadas = true;            
        end
        
        function inicializa_variables(this)
            this.inicializa_variables_sistema();
            this.inicializa_subestaciones();
            this.inicializa_consumos();
            this.inicializa_generadores();
            this.inicializa_embalses();
            this.inicializa_lineas();
            this.inicializa_trafos();
            this.inicializa_baterias();
        end

        function inicializa_variables_sistema(this)
            if this.pParOpt.ConsideraReservasMinimasSistema && this.pParOpt.EstrategiaReservasMinimasSistema == 2
                % reservas dinámicas: igual a la máxima potencia inyectada por los generadores convencionales
                % se crea variable que calcula potencia máxima de los generadores en forma dinámica
                indice_desde = this.iIndiceVarOpt + 1;
                indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                this.iIndiceVarOpt = indice_hasta;
                this.IdVarOptPmaxGenDespDesde = indice_desde;
                if this.iNivelDebug > 0
                    this.ingresa_nombre_variable_sistema(this.pSEP, indice_desde,'PmaxGenSist')
                end
            end
            
            if this.pParOpt.ConsideraRestriccionROCOF
                this.IdVarOptInerciaDesde = zeros(this.iCantContingenciasGenCons,1); % varopt de la inercia del sistema en caso de falla de los generadores
                this.IdRestriccionEInerciaDesde = zeros(this.iCantContingenciasGenCons,1); % restricciones que calcula la inercia del sistema en caso de falla de los generadores
                this.IdRestriccionIROCOFDesde = zeros(this.iCantContingenciasGenCons,1); % restricción del rocof en caso de falla de los generadores

                for cont = 1:this.iCantContingenciasGenCons
                    indice_desde = this.iIndiceVarOpt + 1;
                    indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                    this.iIndiceVarOpt = indice_hasta;

                    this.IdVarOptInerciaDesde(cont) = indice_desde;

                    if this.iNivelDebug > 0
                        this.ingresa_nombre_variable_sistema(this.pSEP, indice_desde,'HSist', cont)
                    end
                end
            end
        end
        
        function inicializa_generadores(this)
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            
            gen = this.pSEP.entrega_generadores();
            this.Generadores.n = length(gen);
            this.Generadores.ElRed = gen;
            this.Generadores.Despachable = zeros(this.Generadores.n,1);
            this.Generadores.IdAdmEscenarioCapacidad = zeros(this.Generadores.n,1);
            this.Generadores.IdAdmEscenarioPerfil = zeros(this.Generadores.n,1);
            this.Generadores.Pmax = zeros(this.Generadores.n,1);
            this.Generadores.Pmin = zeros(this.Generadores.n,1);
            this.Generadores.IdVarOptDesde = zeros(this.Generadores.n,1);
            
            if this.pParOpt.ConsideraReservasMinimasSistema
                % reservas mínimas a guardar en operación normal. No es lo
                % mismo que despliegue de reservas en contingencia. Por
                % ahora sólo generadores convencionales (no ernc)
                this.Generadores.EntreganReservas = zeros(this.Generadores.n,1); % sólo para generadores despachables
                this.Generadores.IdVarOptResPosDesde = zeros(this.Generadores.n,1);
                this.Generadores.IdVarOptResNegDesde = zeros(this.Generadores.n,1);
                this.Generadores.IdRestriccionIResPosDesde = zeros(this.Generadores.n,1);
                this.Generadores.IdRestriccionIResNegDesde = zeros(this.Generadores.n,1);
                
                if this.pParOpt.EstrategiaReservasMinimasSistema == 2
                    this.Generadores.IdRestriccionIPmaxGenDespDesde = zeros(this.Generadores.n,1); % restricciones para calcular la potencia máxima de los generadores despachables
                end
            end
            
            if this.pParOpt.ConsideraEstadoPostContingencia
                this.Generadores.EntreganReservas = zeros(this.Generadores.n,1); % repetido, pero no hace daño. Sólo para generadores despachables
                this.Generadores.IdVarOptPCResPosDesde = zeros(this.Generadores.n,this.iCantContingenciasGenCons); % despliegue de reservas positivas
                this.Generadores.IdVarOptPCResNegDesde = zeros(this.Generadores.n,this.iCantContingenciasGenCons); % despliegue de reservas negativas
                this.Generadores.IdRestriccionIPCResPosDesde = zeros(this.Generadores.n,this.iCantContingenciasGenCons);
                this.Generadores.IdRestriccionIPCResNegDesde = zeros(this.Generadores.n,this.iCantContingenciasGenCons);
            end
                        
            if this.pParOpt.DeterminaUC
                % Por ahora sólo se considera costo de partida. Hay que ver
                % si es necesario modelar los costos de detención también
                this.Generadores.IdVarOptUCDesde = zeros(this.Generadores.n,1);
                this.Generadores.IdVarOptCostoPartidaDesde = zeros(this.Generadores.n,1);
                this.Generadores.TiempoMinimoOperacion = zeros(this.Generadores.n,1); 
                this.Generadores.TiempoMinimoDetencion = zeros(this.Generadores.n,1); 
                %this.Generadores.IdVarOptCostoDetencionDesde = zeros(this.Generadores.n,1);
                
                this.Generadores.IdRestriccionIPotenciasUCDesde = zeros(this.Generadores.n,1);
                this.Generadores.IdRestriccionICostoPartidaDesde = zeros(this.Generadores.n,1);
                this.Generadores.IdRestriccionITMinOperacionDesdeHasta = zeros(this.Generadores.n,2);
                this.Generadores.IdRestriccionITMinDetencionDesdeHasta = zeros(this.Generadores.n,2);                
            end
            
            for i = 1:this.Generadores.n
                this.Generadores.Despachable(i) = gen(i).Despachable;
                if gen(i).Despachable
                    indice_desde = this.iIndiceVarOpt + 1;
                    indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                    this.iIndiceVarOpt = indice_hasta;
                    this.Generadores.IdVarOptDesde(i) = indice_desde;

                    if ~isempty(this.pAdmSc)
                        if gen(i).entrega_evolucion_capacidad_a_futuro(this.iEscenario)
                            id_adm_sc = gen(i).entrega_indice_adm_escenario_capacidad(this.iEscenario);
                            this.Generadores.IdAdmEscenarioCapacidad(i) = id_adm_sc;
                            this.Generadores.Pmax(i) = this.pAdmSc.entrega_capacidad_generador(id_adm_sc, this.iEtapa)/this.Sbase;
                        else
                            this.Generadores.Pmax(i) = gen(i).entrega_pmax()/this.Sbase;
                        end
                    else
                        this.Generadores.Pmax(i) = gen(i).entrega_pmax()/this.Sbase;
                    end
                    
                    this.Generadores.Pmin(i) = gen(i).entrega_pmin()/this.Sbase;
                    if this.pParOpt.DeterminaUC
                        this.lb(indice_desde:indice_hasta) = 0; % Pmin puede ser cero en caso de que el generador se encuentre fuera de servicio
                    else
                        this.lb(indice_desde:indice_hasta) = round(this.Generadores.Pmin(i),dec_redondeo);
                    end
                    this.ub(indice_desde:indice_hasta) = round(this.Generadores.Pmax(i),dec_redondeo);

                    if this.iNivelDebug > 0
                        this.ingresa_nombres(gen(i), indice_desde,'P')
                    end
                    
                    if this.pParOpt.ConsideraReservasMinimasSistema
                        if gen(i).entrega_reservas()
                            this.Generadores.EntreganReservas(i) = 1;
                            
                            % Reservas positivas
                            indice_desde = this.iIndiceVarOpt + 1;
                            indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                            this.iIndiceVarOpt = indice_hasta;
                            this.Generadores.IdVarOptResPosDesde(i) = indice_desde;
                            this.lb(indice_desde:indice_hasta) = round(0,dec_redondeo);
                            if gen(i).entrega_limite_reservas_positivas() > 0
                                this.ub(indice_desde:indice_hasta) = round(gen(i).entrega_limite_reservas_positivas()/this.Sbase, dec_redondeo);
                            else
                                this.ub(indice_desde:indice_hasta) = round(this.Generadores.Pmax(i)-this.Generadores.Pmin(i),dec_redondeo);
                            end

                            if this.iNivelDebug > 0
                                this.ingresa_nombres(gen(i), indice_desde,'RPos');
                            end

                            % Reservas negativas
                            indice_desde = this.iIndiceVarOpt + 1;
                            indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                            this.iIndiceVarOpt = indice_hasta;
                            
                            this.Generadores.IdVarOptResNegDesde(i) = indice_desde;
                            this.lb(indice_desde:indice_hasta) = round(0,dec_redondeo);
                            if gen(i).entrega_limite_reservas_negativas() > 0
                                this.ub(indice_desde:indice_hasta) = round(gen(i).entrega_limite_reservas_negativas()/this.Sbase,dec_redondeo);
                            else
                                this.ub(indice_desde:indice_hasta) = round(this.Generadores.Pmax(i)-this.Generadores.Pmin(i),dec_redondeo);
                            end

                            if this.iNivelDebug > 0
                                this.ingresa_nombres(gen(i), indice_desde,'RNeg');
                            end                            
                        end
                    end
                    
                    if this.pParOpt.DeterminaUC
                        if gen(i).entrega_pmin() > 0
                            this.Generadores.TiempoMinimoOperacion(i) = gen(i).entrega_tiempo_minimo_operacion();
                            this.Generadores.TiempoMinimoDetencion(i) = gen(i).entrega_tiempo_minimo_detencion();
                            
                            indice_desde = this.iIndiceVarOpt + 1;
                            indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                            this.iIndiceVarOpt = indice_hasta;
                            this.Generadores.IdVarOptUCDesde(i) = indice_desde; 
                            this.lb(indice_desde:indice_hasta) = 0;
                            this.ub(indice_desde:indice_hasta) = 1;
                            this.intcon = [this.intcon indice_desde:indice_hasta];

                            if this.iNivelDebug > 0
                                this.ingresa_nombres(gen(i), indice_desde,'UC');
                            end

                            indice_desde = this.iIndiceVarOpt + 1;
                            indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                            this.iIndiceVarOpt = indice_hasta;
                            this.Generadores.IdVarOptCostoPartidaDesde(i) = indice_desde; 
                            this.lb(indice_desde:indice_hasta) = 0;
                            %this.ub(indice_desde:indice_hasta) = gen(i).entrega_costo_partida()/this.Sbase;
                            this.ub(indice_desde:indice_hasta) = 1;
                            
                            if this.iNivelDebug > 0
                                this.ingresa_nombres(gen(i), indice_desde,'CPart');
                            end
                        end
                    end
                    
                    if this.pParOpt.ConsideraEstadoPostContingencia
                        if gen(i).entrega_reservas()
                            this.Generadores.EntreganReservas(i) = 1;                            
                            for cont = 1:this.iCantContingenciasGenCons
                                
                                % Reservas positivas
                                indice_desde = this.iIndiceVarOpt + 1;
                                indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                                this.iIndiceVarOpt = indice_hasta;
                                this.Generadores.IdVarOptPCResPosDesde(i, cont) = indice_desde;
                                this.lb(indice_desde:indice_hasta) = round(0,dec_redondeo);                                
                                if this.pContingenciasGenCons(cont) ~= gen(i)
                                    if gen(i).entrega_limite_reservas_positivas() > 0
                                        this.ub(indice_desde:indice_hasta) = round(gen(i).entrega_limite_reservas_positivas()/this.Sbase, dec_redondeo);
                                    else
                                        this.ub(indice_desde:indice_hasta) = round(this.Generadores.Pmax(i)-this.Generadores.Pmin(i),dec_redondeo);
                                    end
                                else
                                    this.ub(indice_desde:indice_hasta) = 0;
                                end
                                    
                                if this.iNivelDebug > 0
                                    this.ingresa_nombres(gen(i), indice_desde,'PCRPos');
                                end

                                % Reservas negativas
                                indice_desde = this.iIndiceVarOpt + 1;
                                indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                                this.iIndiceVarOpt = indice_hasta;
                                this.Generadores.IdVarOptPCResNegDesde(i, cont) = indice_desde;
                                this.lb(indice_desde:indice_hasta) = round(0,dec_redondeo);
                                if this.pContingenciasGenCons(cont) ~= gen(i)
                                    if gen(i).entrega_limite_reservas_negativas() > 0
                                        this.ub(indice_desde:indice_hasta) = round(gen(i).entrega_limite_reservas_negativas()/this.Sbase,dec_redondeo);
                                    else
                                        this.ub(indice_desde:indice_hasta) = round(this.Generadores.Pmax(i)-this.Generadores.Pmin(i),dec_redondeo);
                                    end
                                else
                                    this.ub(indice_desde:indice_hasta) = 0;
                                end
                                
                                if this.iNivelDebug > 0
                                    this.ingresa_nombres(gen(i), indice_desde,'PCRNeg');
                                end
                            end
                        end
                    end
                else
                    % generador ernc
                    if ~isempty(this.pAdmSc)
                        if gen(i).entrega_evolucion_capacidad_a_futuro(this.iEscenario)
                            id_adm_sc = gen(i).entrega_indice_adm_escenario_capacidad(this.iEscenario);
                            this.Generadores.IdAdmEscenarioCapacidad(i) = id_adm_sc;
                            this.Generadores.Pmax(i) = this.pAdmSc.entrega_capacidad_generador(id_adm_sc, this.iEtapa)/this.Sbase;
                        else
                            this.Generadores.Pmax(i) = gen(i).entrega_pmax()/this.Sbase;
                        end
                        id_adm_sc = gen(i).entrega_indice_adm_escenario_perfil_ernc();
                        this.Generadores.IdAdmEscenarioPerfil(i) = id_adm_sc;
                        pmax = this.Generadores.Pmax(i)*this.pAdmSc.entrega_perfil_ernc(id_adm_sc);                                        
                    else
                        % datos locales
                        this.Generadores.Pmax(i) = gen(i).entrega_pmax()/this.Sbase;
                        pmax = gen(i).entrega_p_const_nom_opf();                                    
                    end
                    % PMin generadores renovables es cero
                    indice_desde = this.iIndiceVarOpt + 1;
                    indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                    this.iIndiceVarOpt = indice_hasta;
                    this.Generadores.IdVarOptDesde(i) = indice_desde;
                    this.lb(indice_desde:indice_hasta) = round(0,dec_redondeo);
                    this.ub(indice_desde:indice_hasta) = round(pmax',dec_redondeo);        

                    if this.iNivelDebug > 0
                        this.ingresa_nombres(gen(i), indice_desde, 'P')
                    end

                    if this.pParOpt.ConsideraEstadoPostContingencia
                        % recorte RES ante contingencias. Sólo se considera
                        % recorte (i.e. reservas negativas), no aumento de generación
                        for cont = 1:this.iCantContingenciasGenCons
                        
                            indice_desde = this.iIndiceVarOpt + 1;
                            indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                            this.iIndiceVarOpt = indice_hasta;

                            this.Generadores.IdVarOptPCResNegDesde(i, cont) = indice_desde;
                            this.lb(indice_desde:indice_hasta) = round(0,dec_redondeo);
                            if this.pContingenciasGenCons(cont) ~= gen(i)
                                this.ub(indice_desde:indice_hasta) = round(pmax',dec_redondeo);
                            else
                                this.ub(indice_desde:indice_hasta) = 0;
                            end

                            if this.iNivelDebug > 0
                                this.ingresa_nombres(gen(i), indice_desde,'RNegERNC')
                            end
                        end
                    end
                end
            end
        end
        
        function inicializa_baterias(this)
            % Si no se considera balance temporal, entonces los límites de
            % potencia de las baterías se deben ajustar a la energía
            % actual, máxima y mínima de la batería. No se realiza balance
            % de energía
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            baterias = this.pSEP.entrega_baterias();
            this.Baterias.n = length(baterias);
            this.Baterias.ElRed = baterias;
            this.Baterias.IdVarOptDesdeDescarga = zeros(this.Baterias.n,1); % inyecta potencia a la red
            this.Baterias.IdVarOptDesdeCarga = zeros(this.Baterias.n,1); % consume potencia desde la red

            if this.bConsideraDependenciaTemporal
                this.Baterias.IdVarOptDesdeE = zeros(this.Baterias.n,1); % energía almacenada en la bateria
                this.Baterias.IdRestriccionEBalanceDesde = zeros(this.Baterias.n,1);
            end
            
            if this.pParOpt.ConsideraReservasMinimasSistema
                this.Baterias.IdVarOptResDescargaDesde = zeros(this.Baterias.n,1);
                this.Baterias.IdVarOptResCargaDesde = zeros(this.Baterias.n,1);
                this.Baterias.IdRestriccionIResDescargaDesde = zeros(this.Baterias.n,1);
                this.Baterias.IdRestriccionIResCargaDesde = zeros(this.Baterias.n,1);

                if this.bConsideraDependenciaTemporal
                    this.Baterias.IdRestriccionIResBalanceDescargaDesde = zeros(this.Baterias.n,1);
                    this.Baterias.IdRestriccionIResBalanceCargaDesde = zeros(this.Baterias.n,1);
                end
            end
            
            if this.pParOpt.ConsideraEstadoPostContingencia
                this.Baterias.IdVarOptPCResDescargaDesde = zeros(this.Baterias.n,this.iCantContingenciasGenCons); % potencia postcontingencia entregada (positiva)
                this.Baterias.IdVarOptPCResCargaDesde = zeros(this.Baterias.n,this.iCantContingenciasGenCons); % potencia postcontingencia consumida (negativa)
                this.Baterias.IdRestriccionIPCResDescargaDesde = zeros(this.Baterias.n,this.iCantContingenciasGenCons);
                this.Baterias.IdRestriccionIPCResCargaDesde = zeros(this.Baterias.n,this.iCantContingenciasGenCons);
                
                if this.bConsideraDependenciaTemporal
                    this.Baterias.IdRestriccionIPCResBalanceDescargaDesde = zeros(this.Baterias.n,this.iCantContingenciasGenCons);
                    this.Baterias.IdRestriccionIPCResBalanceCargaDesde = zeros(this.Baterias.n,this.iCantContingenciasGenCons);                    
                end
            end
            
            for i = 1:this.Baterias.n
                % Potencia inyectada a la red
                indice_desde = this.iIndiceVarOpt + 1;
                indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                this.iIndiceVarOpt = indice_hasta;
                this.Baterias.IdVarOptDesdeDescarga(i) = indice_desde;
                
                this.lb(indice_desde:indice_hasta) = 0;
                if this.bConsideraDependenciaTemporal
                    pmax_descarga = baterias(i).entrega_pmax_descarga()/this.Sbase;
                    this.ub(indice_desde:indice_hasta) = round(pmax_descarga,dec_redondeo);
                else
                    % en este caso, la potencia inyectada a la red debe coincidir con la energía actual almacenada por la batería y la energía mínima de la batería
                    pmax_descarga = baterias(i).entrega_potencia_maxima_descarga_actual();
                    this.ub(indice_desde:indice_hasta) = round(pmax_descarga,dec_redondeo);                    
                end
                
                if this.iNivelDebug > 0
                    this.ingresa_nombres(baterias(i), indice_desde,'Pdescarga')
                end

                % Potencia consumida desde la red
                indice_desde = this.iIndiceVarOpt + 1;
                indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                this.iIndiceVarOpt = indice_hasta;
                this.Baterias.IdVarOptDesdeCarga(i) = indice_desde;
                
                this.lb(indice_desde:indice_hasta) = 0;
                if this.bConsideraDependenciaTemporal
                    pmax_carga = baterias(i).entrega_pmax_carga()/this.Sbase;
                    this.ub(indice_desde:indice_hasta) = round(pmax_carga,dec_redondeo);
                else
                    pmax_carga = baterias(i).entrega_potencia_maxima_carga_actual();
                    this.ub(indice_desde:indice_hasta) = round(pmax_carga,dec_redondeo);                    
                end
                
                if this.iNivelDebug > 0
                    this.ingresa_nombres(baterias(i), indice_desde,'Pcarga')
                end
                
                if this.pParOpt.ConsideraReservasMinimasSistema
                    indice_desde = this.iIndiceVarOpt + 1;
                    indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                    this.iIndiceVarOpt = indice_hasta;

                    this.Baterias.IdVarOptResDescargaDesde(i) = indice_desde;
                    this.lb(indice_desde:indice_hasta) = 0;
                    this.ub(indice_desde:indice_hasta) = round(pmax_descarga,dec_redondeo); % pmax_descarga ya considera si hay dependencia temporal o no

                    if this.iNivelDebug > 0
                        this.ingresa_nombres(baterias(i), indice_desde, 'ResDescarga')
                    end

                    indice_desde = this.iIndiceVarOpt + 1;
                    indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                    this.iIndiceVarOpt = indice_hasta;

                    this.Baterias.IdVarOptResCargaDesde(i) = indice_desde;
                    this.lb(indice_desde:indice_hasta) = 0;
                    this.ub(indice_desde:indice_hasta) = round(pmax_carga,dec_redondeo); % pmax_carga ya considera si hay dependencia temporal o no

                    if this.iNivelDebug > 0
                        this.ingresa_nombres(baterias(i), indice_desde, 'ResCarga')
                    end
                end
                
                if this.bConsideraDependenciaTemporal
                    % variables para la energía almacenada en la batería
                    capacidad = baterias(i).entrega_capacidad()/this.Sbase;

                    indice_desde = this.iIndiceVarOpt + 1;
                    indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                    this.iIndiceVarOpt = indice_hasta;
                    
                    this.Baterias.IdVarOptDesdeE(i) = indice_desde;
                    emin = baterias(i).entrega_energia_minima()/this.Sbase;
                    this.lb(indice_desde:indice_hasta) = round(emin,dec_redondeo); 
                    this.ub(indice_desde:indice_hasta) = round(capacidad,dec_redondeo);
                    if ~this.pParOpt.OptimizaSoCInicialBaterias
                        energia_inicial = baterias(i).entrega_soc_actual()*capacidad;
                        this.lb(indice_desde-1+this.vIndicesPOConsecutivos(:,1)) = round(energia_inicial,dec_redondeo);
                        this.ub(indice_desde-1+this.vIndicesPOConsecutivos(:,1)) = round(energia_inicial,dec_redondeo);
                        this.lb(indice_desde-1+this.vIndicesPOConsecutivos(:,2)) = round(energia_inicial,dec_redondeo);
                        this.ub(indice_desde-1+this.vIndicesPOConsecutivos(:,2)) = round(energia_inicial,dec_redondeo);
                    end
                    
                    if this.iNivelDebug > 0
                        this.ingresa_nombres(baterias(i), indice_desde, 'E')
                    end
                end

                if this.pParOpt.ConsideraEstadoPostContingencia
                    for cont = 1:this.iCantContingenciasGenCons                    
                        indice_desde = this.iIndiceVarOpt + 1;
                        indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                        this.iIndiceVarOpt = indice_hasta;
                        
                        this.Baterias.IdVarOptPCResDescargaDesde(i, cont) = indice_desde;
                        this.lb(indice_desde:indice_hasta) = 0;
                        if this.pContingenciasGenCons(cont) ~= baterias(i)
                            this.ub(indice_desde:indice_hasta) = round(pmax_descarga,dec_redondeo);
                        else
                            this.ub(indice_desde:indice_hasta) = 0;
                        end
                        
                        if this.iNivelDebug > 0
                            this.ingresa_nombres(baterias(i), indice_desde, 'PCResDescarga', cont)
                        end

                        indice_desde = this.iIndiceVarOpt + 1;
                        indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                        this.iIndiceVarOpt = indice_hasta;
                        
                        this.Baterias.IdVarOptPCResCargaDesde(i, cont) = indice_desde;
                        this.lb(indice_desde:indice_hasta) = 0;
                        if this.pContingenciasGenCons(cont) ~= baterias(i)
                            this.ub(indice_desde:indice_hasta) = round(pmax_carga,dec_redondeo);
                        else
                            this.ub(indice_desde:indice_hasta) = 0;
                        end

                        if this.iNivelDebug > 0
                            this.ingresa_nombres(baterias(i), indice_desde, 'PCResCarga', cont)
                        end
                    end
                end
            end
        end

        function inicializa_embalses(this)
            % Sólo si se considera balance temporal. En caso contrario, se asume que los volúmenes de los embalses son lo suficiente como para generar la potencia máxima
            if ~this.bConsideraDependenciaTemporal
                this.Embalses.n = 0;
                return
            end
            
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            embalses = this.pSEP.entrega_embalses();
            this.Embalses.n = length(embalses);
            this.Embalses.ElRed = embalses;
            this.Embalses.IdAdmEscenarioAfluentes = zeros(this.Embalses.n,1);
            this.Embalses.IdVarOptVertimientoDesde = zeros(this.Embalses.n,1);
            this.Embalses.IdRestriccionEBalanceDesde = zeros(this.Embalses.n,1);
            this.Embalses.IdVarOptDesde = zeros(this.Embalses.n,1); % volumen del embalse

            this.Embalses.IdVarOptFiltracionDesde = zeros(this.Embalses.n,1);
            this.Embalses.IdRestriccionEFiltracionDesde = zeros(this.Embalses.n,1);                
            
            for i = 1:this.Embalses.n
                this.Embalses.IdAdmEscenarioAfluentes(i) = embalses(i).entrega_indice_adm_escenario_afluentes();

                % volumen del embalse
                vol_max = embalses(i).entrega_vol_max()/3600;
                vol_min = embalses(i).entrega_vol_min()/3600;

                indice_desde = this.iIndiceVarOpt + 1;
                indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                this.iIndiceVarOpt = indice_hasta;
                this.Embalses.IdVarOptDesde(i) = indice_desde; 

                this.lb(indice_desde:indice_hasta) = round(vol_min,dec_redondeo);
                this.ub(indice_desde:indice_hasta) = round(vol_max,dec_redondeo);

                % fija volumenes iniciales y finales
                vol_inicial = embalses(i).entrega_vol_inicial()/3600;
                vol_final = embalses(i).entrega_vol_final()/3600;

                this.lb(indice_desde) = round(vol_inicial,dec_redondeo);
                this.ub(indice_desde) = round(vol_inicial,dec_redondeo);
                this.lb(indice_hasta) = round(vol_final,dec_redondeo);
                this.ub(indice_hasta) = round(vol_final,dec_redondeo);
                
                if this.iNivelDebug > 0
                    this.ingresa_nombres(embalses(i), indice_desde, 'Vol')
                end
                
                % vertimiento
                indice_desde = this.iIndiceVarOpt + 1;
                indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                this.iIndiceVarOpt = indice_hasta;
                this.Embalses.IdVarOptVertimientoDesde(i) = indice_desde;

                max_caudal_vertimiento = embalses(i).entrega_maximo_caudal_vertimiento();
                if max_caudal_vertimiento == 0
                    max_caudal_vertimiento = inf;
                end
                
                id_adm_sc_vert_obligatorio = embalses(i).entrega_indice_adm_escenario_vertimiento_obligatorio();
                if id_adm_sc_vert_obligatorio > 0
                    vert_obligatorio = this.pAdmSc.entrega_perfil_vertimiento(id_adm_sc_vert_obligatorio);
                    this.lb(indice_desde:indice_hasta) = round(vert_obligatorio',dec_redondeo);
                else
                    this.lb(indice_desde:indice_hasta) = round(0,dec_redondeo);
                end
                this.ub(indice_desde:indice_hasta) = round(max_caudal_vertimiento,dec_redondeo);

                if this.iNivelDebug > 0
                    this.ingresa_nombres(embalses(i), indice_desde, 'Vertimiento')
                end
                
                % filtraciones
                if this.Embalses.ElRed(i).tiene_filtracion()
                    indice_desde = this.iIndiceVarOpt + 1;
                    indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                    this.iIndiceVarOpt = indice_hasta;
                    this.Embalses.IdVarOptFiltracionDesde(i) = indice_desde;

                    max_caudal_filtracion = this.Embalses.ElRed(i).entrega_maximo_caudal_filtracion()/3600;
                    this.lb(indice_desde:indice_hasta) = round(0,dec_redondeo);
                    this.ub(indice_desde:indice_hasta) = round(max_caudal_filtracion,dec_redondeo);

                    if this.iNivelDebug > 0
                        this.ingresa_nombres(embalses(i), indice_desde, 'Filtracion')
                    end
                end
            end            
        end
        
        function inicializa_subestaciones(this)
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            theta_max = this.pParOpt.AnguloMaximoBuses;
            
            ses = this.pSEP.entrega_subestaciones();
            this.Subestaciones.ElRed = ses;
            this.Subestaciones.n = length(ses);
            this.Subestaciones.IdRestriccionEBalanceDesde = zeros(this.Subestaciones.n,1);
            
            indice_desde = this.iIndiceVarOpt + 1;
            indices = indice_desde:this.iCantPuntosOperacion:indice_desde+this.iCantPuntosOperacion*(this.Subestaciones.n-1);
            this.Subestaciones.IdVarOptDesde = indices';
            indice_hasta = indice_desde + this.iCantPuntosOperacion*this.Subestaciones.n-1;
            this.iIndiceVarOpt = indice_hasta;

            this.lb(indice_desde:indice_hasta) = round(-theta_max,dec_redondeo);
            this.ub(indice_desde:indice_hasta) = round(theta_max,dec_redondeo);
            
            id_se_slack = this.pSEP.entrega_id_se_slack();
            indice_desde_slack = indice_desde + this.iCantPuntosOperacion*(id_se_slack-1);
            indice_hasta_slack = indice_desde_slack + this.iCantPuntosOperacion-1;
            
            this.lb(indice_desde_slack:indice_hasta_slack) = 0;
            this.ub(indice_desde_slack:indice_hasta_slack) = 0;

            if this.iNivelDebug > 0
                indice_base = indice_desde-1;
                for i = 1:this.Subestaciones.n
                    indice_desde_actual = indice_base + 1;
                    this.ingresa_nombres(ses(i), indice_desde_actual, 'N0');
                    indice_base = indice_base + this.iCantPuntosOperacion;
                end
            end

            if this.pParOpt.ConsideraContingenciaN1
                this.Subestaciones.IdRestriccionEBalanceN1Desde = zeros(this.Subestaciones.n,this.iCantContingenciasElSerie);
                this.Subestaciones.IdVarOptN1Desde = zeros(this.Subestaciones.n,this.iCantContingenciasElSerie);
                for i = 1:this.Subestaciones.n
                    for cont = 1:this.iCantContingenciasElSerie
                        indice_desde = this.iIndiceVarOpt + 1;
                        indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                        this.iIndiceVarOpt = indice_hasta;

                        this.Subestaciones.IdVarOptN1Desde(i,cont) = indice_desde;

                        this.lb(indice_desde:indice_hasta) = round(-theta_max,dec_redondeo);
                        this.ub(indice_desde:indice_hasta) = round(theta_max,dec_redondeo);

                        if this.pSEP.entrega_id_se_slack() == i
                            this.lb(indice_desde:indice_hasta) = 0;
                            this.ub(indice_desde:indice_hasta) = 0;
                        end

                        if this.iNivelDebug > 0
                            this.ingresa_nombres(ses(i), indice_desde, 'N1', cont);
                        end
                    end
                end
            end
            
            if this.pParOpt.ConsideraEstadoPostContingencia
                this.Subestaciones.IdRestriccionEBalancePCDesde = zeros(this.Subestaciones.n,this.iCantContingenciasGenCons);
                this.Subestaciones.IdVarOptPCDesde = zeros(this.Subestaciones.n,this.iCantContingenciasGenCons);

                for i = 1:this.Subestaciones.n
                    for cont = 1:this.iCantContingenciasGenCons
                        indice_desde = this.iIndiceVarOpt + 1;
                        indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                        this.iIndiceVarOpt = indice_hasta;
                
                        this.Subestaciones.IdVarOptPCDesde(i,cont) = indice_desde;

                        this.lb(indice_desde:indice_hasta) = round(-theta_max,dec_redondeo);
                        this.ub(indice_desde:indice_hasta) = round(theta_max,dec_redondeo);

                        if this.pSEP.entrega_id_se_slack() == i
                            this.lb(indice_desde:indice_hasta) = 0;
                            this.ub(indice_desde:indice_hasta) = 0;
                        end
                        
                        if this.iNivelDebug > 0
                            this.ingresa_nombres(ses(i), indice_desde, 'PC', cont);
                        end
                    end
                end
            end
        end
        
        function inicializa_lineas(this)
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            lineas = this.pSEP.entrega_lineas();
            this.Lineas.n = length(lineas);
            this.Lineas.IdVarOptDesde = zeros(this.Lineas.n,1);
            this.Lineas.ElRed = lineas;
            this.Lineas.IdRestriccionEFlujosAngulosDesde = zeros(this.Lineas.n,1);
            this.Lineas.FlagObservacion = zeros(this.Lineas.n,1);
            this.Lineas.Pmax = zeros(this.Lineas.n,1);
            
            if this.pParOpt.ConsideraContingenciaN1
                this.Lineas.IdVarOptN1Desde = zeros(this.Lineas.n,this.iCantContingenciasElSerie);
                this.Lineas.IdRestriccionEFlujosAngulosN1Desde = zeros(this.Lineas.n,this.iCantContingenciasElSerie);
            end
            
            if this.pParOpt.ConsideraEstadoPostContingencia
                this.Lineas.IdVarOptPCDesde = zeros(this.Lineas.n,this.iCantContingenciasGenCons);
                this.Lineas.IdRestriccionEFlujosAngulosPCDesde = zeros(this.Lineas.n,this.iCantContingenciasGenCons);
            end
            
            for i = 1:this.Lineas.n
                indice_desde = this.iIndiceVarOpt + 1;
                indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                this.iIndiceVarOpt = indice_hasta;
                this.Lineas.IdVarOptDesde(i) = indice_desde;
                this.Lineas.FlagObservacion(i) = lineas(i).tiene_flag_observacion();
                sr = lineas(i).entrega_sr()/this.Sbase;
                this.Lineas.Pmax(i) = sr;
                this.lb(indice_desde:indice_hasta) = round(-sr,dec_redondeo);
                this.ub(indice_desde:indice_hasta) = round(sr,dec_redondeo);

                if this.iNivelDebug > 0
                    this.ingresa_nombres(lineas(i), indice_desde, 'N0');
                end
                
                if this.pParOpt.ConsideraContingenciaN1
                    sr = lineas(i).entrega_sr_n1()/this.Sbase;
                    for cont = 1:this.iCantContingenciasElSerie
                        
                        indice_desde = this.iIndiceVarOpt + 1;
                        indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                        this.iIndiceVarOpt = indice_hasta;
                        
                        this.Lineas.IdVarOptN1Desde(i, cont) = indice_desde;
                        if this.pContingenciasElSerie(cont) ~= lineas(i)
                            this.lb(indice_desde:indice_hasta) = round(-sr,dec_redondeo);
                            this.ub(indice_desde:indice_hasta) = round(sr,dec_redondeo);
                        else
                            this.lb(indice_desde:indice_hasta) = 0;
                            this.ub(indice_desde:indice_hasta) = 0;
                        end                            
                        if this.iNivelDebug > 0
                            this.ingresa_nombres(lineas(i), indice_desde, 'N1', cont);
                        end
                    end
                end
                
                if this.pParOpt.ConsideraEstadoPostContingencia
                    for cont = 1:this.iCantContingenciasGenCons
                        indice_desde = this.iIndiceVarOpt + 1;
                        indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                        this.iIndiceVarOpt = indice_hasta;

                        this.Lineas.IdVarOptPCDesde(i, cont) = indice_desde;
                        this.lb(indice_desde:indice_hasta) = round(-sr,dec_redondeo);
                        this.ub(indice_desde:indice_hasta) = round(sr,dec_redondeo);

                        if this.iNivelDebug > 0
                            this.ingresa_nombres(lineas(i), indice_desde, 'PC', cont);
                        end
                    end
                end
            end
        end

        function inicializa_trafos(this)
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            trafos = this.pSEP.entrega_transformadores2d();
            this.Trafos.n = length(trafos);
            this.Trafos.IdVarOptDesde = zeros(this.Trafos.n,1);
            this.Trafos.ElRed = trafos;
            this.Trafos.IdRestriccionEFlujosAngulosDesde = zeros(this.Trafos.n,1);
            this.Trafos.FlagObservacion = zeros(this.Trafos.n,1);
            this.Trafos.Pmax = zeros(this.Trafos.n,1);
            
            if this.pParOpt.ConsideraContingenciaN1
                this.Trafos.IdVarOptN1Desde = zeros(this.Trafos.n,this.iCantContingenciasElSerie);
                this.Trafos.IdRestriccionEFlujosAngulosN1Desde = zeros(this.Trafos.n,this.iCantContingenciasElSerie);
            end
            
            if this.pParOpt.ConsideraEstadoPostContingencia
                this.Trafos.IdVarOptPCDesde = zeros(this.Trafos.n,this.iCantContingenciasGenCons);
                this.Trafos.IdRestriccionEFlujosAngulosPCDesde = zeros(this.Trafos.n,this.iCantContingenciasGenCons);
            end
            
            for i = 1:this.Trafos.n
                indice_desde = this.iIndiceVarOpt + 1;
                indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                this.iIndiceVarOpt = indice_hasta;
                this.Trafos.IdVarOptDesde(i) = indice_desde;
                this.Trafos.FlagObservacion(i) = trafos(i).tiene_flag_observacion();
                sr = trafos(i).entrega_sr()/this.Sbase;
                this.Trafos.Pmax(i) = sr;
                
                this.lb(indice_desde:indice_hasta) = round(-sr,dec_redondeo);
                this.ub(indice_desde:indice_hasta) = round(sr,dec_redondeo);

                if this.iNivelDebug > 0
                    this.ingresa_nombres(trafos(i), indice_desde, 'N0');
                end
                
                if this.pParOpt.ConsideraContingenciaN1
                    sr = trafos(i).entrega_sr_n1()/this.Sbase;
                    for cont = 1:this.iCantContingenciasElSerie
                        indice_desde = this.iIndiceVarOpt + 1;
                        indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                        this.iIndiceVarOpt = indice_hasta;
                        
                        this.Trafos.IdVarOptN1Desde(i, cont) = indice_desde;
                        if this.pContingenciasElSerie(cont) ~= trafos(i)
                            this.lb(indice_desde:indice_hasta) = round(-sr,dec_redondeo);
                            this.ub(indice_desde:indice_hasta) = round(sr,dec_redondeo);
                        else
                            this.lb(indice_desde:indice_hasta) = 0;
                            this.ub(indice_desde:indice_hasta) = 0;                            
                        end
                        
                        if this.iNivelDebug > 0
                            this.ingresa_nombres(trafos(i), indice_desde, 'N1', cont);
                        end
                    end
                end
                
                if this.pParOpt.ConsideraEstadoPostContingencia
                    sr = trafos(i).entrega_sr()/this.Sbase;
                    for cont = 1:this.iCantContingenciasGenCons
                        indice_desde = this.iIndiceVarOpt + 1;
                        indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                        this.iIndiceVarOpt = indice_hasta;
                        
                        this.Trafos.IdVarOptPCDesde(i, cont) = indice_desde;
                        this.lb(indice_desde:indice_hasta) = round(-sr,dec_redondeo);
                        this.ub(indice_desde:indice_hasta) = round(sr,dec_redondeo);

                        if this.iNivelDebug > 0
                            this.ingresa_nombres(trafos(i), indice_desde, 'PC', cont);
                        end
                    end
                end                
            end
        end
        
        function inicializa_consumos(this)
            dec_redondeo = this.pParOpt.DecimalesRedondeo;            
            cons = this.pSEP.entrega_consumos();
            this.Consumos.n = length(cons);
            this.Consumos.ElRed = cons;
            this.Consumos.Pmax = zeros(this.Consumos.n,1);
            this.Consumos.IdAdmEscenarioPerfil = zeros(this.Consumos.n,1);
            this.Consumos.IdAdmEscenarioCapacidad = zeros(this.Consumos.n,1);
            this.Consumos.IdVarOptDesde = zeros(this.Consumos.n,1);

            if this.pParOpt.ConsideraEstadoPostContingencia
                this.Consumos.IdVarOptPCDesde = zeros(this.Lineas.n,this.iCantContingenciasGenCons);
            end
            
            for i = 1:this.Consumos.n
                if ~isempty(this.pAdmSc)
                    indice_perfil = cons(i).entrega_indice_adm_escenario_perfil_p();
                    this.Consumos.IdAdmEscenarioPerfil(i) = indice_perfil;
                    indice_capacidad = cons(i).entrega_indice_adm_escenario_capacidad(this.iEscenario);
                    this.Consumos.IdAdmEscenarioCapacidad(i) = indice_capacidad;
                    
                    this.Consumos.Pmax(i) = this.pAdmSc.entrega_capacidad_consumo(indice_capacidad, this.iEtapa)/this.Sbase;           
                    perfil = this.pAdmSc.entrega_perfil_consumo(indice_perfil);
                    consumo = this.Consumos.Pmax(i)*perfil;
                else
                    % TODO: Hay que ver bien qué se hace aquí
                    this.Consumos.Pmax(i)= cons(i).entrega_pmax()/this.Sbase;
                    consumo = -cons(i).entrega_p_const_nom_pu(); %valor positivo
                end

                indice_desde = this.iIndiceVarOpt + 1;
                indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                this.iIndiceVarOpt = indice_hasta;

                this.lb(indice_desde:indice_hasta) = 0;
                this.ub(indice_desde:indice_hasta) = round(consumo',dec_redondeo);

                this.Consumos.IdVarOptDesde(i) = indice_desde;

                if this.iNivelDebug > 0
                    this.ingresa_nombres(cons(i), indice_desde, 'N0');
                end
                
                if this.pParOpt.ConsideraEstadoPostContingencia
                    for cont = 1:this.iCantContingenciasGenCons
                        indice_desde = this.iIndiceVarOpt + 1;
                        indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                        this.iIndiceVarOpt = indice_hasta;
                        
                        this.Consumos.IdVarOptPCDesde(i, cont) = indice_desde;
                        this.lb(indice_desde:indice_hasta) = 0;
                        if this.pContingenciasGenCons(cont) ~= cons(i)
                            this.ub(indice_desde:indice_hasta) = round(consumo',dec_redondeo);
                        else
                            this.ub(indice_desde:indice_hasta) = 0;
                        end
                        
                        if this.iNivelDebug > 0
                            this.ingresa_nombres(cons(i), indice_desde, 'PC', cont);
                        end
                    end
                end
            end
        end

        function agrega_variable(this, variable)
            if isa(variable, 'cLinea')
                this.agrega_linea(variable);
            elseif isa(variable, 'cTransformador2D')
                this.agrega_trafo(variable);
            elseif isa(variable, 'cBateria')
                this.agrega_bateria(variable);
            elseif isa(variable,'cSubestacion')
                this.agrega_subestacion(variable);
            elseif isa(variable, 'cGenerador')
                this.agrega_generador(variable)
            else
                error = MException('cOPF:agrega_variable','Tipo de variable a agregar no implementado');
                throw(error)
            end            
        end
        
        function agrega_generador(this, variable)
            dec_redondeo = this.pParOpt.DecimalesRedondeo;            

            % aumenta dimensión de contenedores
            % 1. estado de operación normal
            this.Fobj = [this.Fobj; zeros(this.iCantPuntosOperacion, 1)];
            this.Aeq = [this.Aeq zeros(this.iIndiceEq, this.iCantPuntosOperacion)];
            if ~isempty(this.Aineq)
                this.Aineq = [this.Aineq zeros(this.iIndiceIneq, this.iCantPuntosOperacion)];
            end
            
            indice_p_desde = this.iIndiceVarOpt + 1;
            indice_p_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
            this.iIndiceVarOpt = indice_p_hasta;
            
            this.Generadores.n = this.Generadores.n + 1;
            n_gen = this.Generadores.n;
            this.Generadores.ElRed(n_gen) = variable;
            this.Generadores.IdVarOptDesde(n_gen) = indice_p_desde;
            this.Generadores.Despachable(n_gen) = variable.Despachable;
            this.Generadores.IdAdmEscenarioPerfil(n_gen) = 0; % valor por defecto
            this.Generadores.IdAdmEscenarioCapacidad(n_gen) = 0; % valor por defecto

            if this.pParOpt.ConsideraReservasMinimasSistema || this.pParOpt.ConsideraEstadoPostContingencia
                this.Generadores.EntreganReservas(n_gen) = variable.Despachable && variable.entrega_reservas();
                if this.pParOpt.EstrategiaReservasMinimasSistema == 2
                    this.Generadores.IdRestriccionIPmaxGenDespDesde(n_gen) = 0; % restricciones para calcular la potencia máxima de los generadores despachables
                end
            end
            
            if ~isempty(this.pAdmSc)
                if variable.entrega_evolucion_capacidad_a_futuro(this.iEscenario)
                    id_adm_sc = variable.entrega_indice_adm_escenario_capacidad(this.iEscenario);
                    this.Generadores.IdAdmEscenarioCapacidad(n_gen) = id_adm_sc;
                    this.Generadores.Pmax(n_gen) = this.pAdmSc.entrega_capacidad_generador(id_adm_sc, this.iEtapa)/this.Sbase;
                else
                    this.Generadores.Pmax(n_gen) = variable.entrega_pmax()/this.Sbase;
                end
            else
                this.Generadores.Pmax(n_gen) = variable.entrega_pmax()/this.Sbase;
            end
            
            if variable.Despachable
                this.Generadores.Pmin(n_gen) = variable.entrega_pmin()/this.Sbase;
                if this.pParOpt.DeterminaUC
                    this.lb(indice_p_desde:indice_p_hasta) = 0; % Pmin puede ser cero en caso de que el generador se encuentre fuera de servicio
                else
                    this.lb(indice_p_desde:indice_p_hasta) = round(this.Generadores.Pmin(n_gen),dec_redondeo);
                end
                this.ub(indice_p_desde:indice_p_hasta) = round(this.Generadores.Pmax(n_gen),dec_redondeo);
            else % generador ernc
                this.Generadores.Pmin(n_gen) = 0;
                if ~isempty(this.pAdmSc)
                    id_adm_sc = variable.entrega_indice_adm_escenario_perfil_ernc();
                    this.Generadores.IdAdmEscenarioPerfil(n_gen) = id_adm_sc;
                    pmax = this.Generadores.Pmax(n_gen)*this.pAdmSc.entrega_perfil_ernc(id_adm_sc);                                        
                else % datos locales
                    pmax = variable.entrega_p_const_nom_opf();                                    
                end            
                this.lb(indice_p_desde:indice_p_hasta) = round(0,dec_redondeo);
                this.ub(indice_p_desde:indice_p_hasta) = round(pmax',dec_redondeo);        
            end            

            if this.iNivelDebug > 0
                this.ingresa_nombres(variable, indice_p_desde,'P')
            end

            this.agrega_generador_a_funcion_objetivo(variable, indice_p_desde, indice_p_hasta);
            this.agrega_generador_a_balance_energia(variable, indice_p_desde, indice_p_hasta);

            if this.pParOpt.DeterminaUC
                this.Generadores.IdVarOptUCDesde(n_gen) = 0;
                this.Generadores.IdVarOptCostoPartidaDesde(n_gen) = 0;
                this.Generadores.TiempoMinimoOperacion(n_gen) = 0;
                this.Generadores.TiempoMinimoDetencion(n_gen) = 0;
                this.Generadores.IdRestriccionIPotenciasUCDesde(n_gen) = 0;
                this.Generadores.IdRestriccionICostoPartidaDesde(n_gen) = 0;
                this.Generadores.IdRestriccionITMinOperacionDesdeHasta(n_gen,:) = 0;
                this.Generadores.IdRestriccionITMinDetencionDesdeHasta(n_gen,:) = 0;
                
                if variable.entrega_pmin() > 0
                    this.Generadores.TiempoMinimoOperacion(n_gen) = variable.entrega_tiempo_minimo_operacion();
                    this.Generadores.TiempoMinimoDetencion(n_gen) = variable.entrega_tiempo_minimo_detencion();

                    % 2 tipos de variables: una para índice UC y otra para
                    % los costos de partida
                    this.Fobj = [this.Fobj; zeros(2*this.iCantPuntosOperacion, 1)];
                    this.Aeq = [this.Aeq zeros(this.iIndiceEq, 2*this.iCantPuntosOperacion)];
                    if ~isempty(this.Aineq)
                        this.Aineq = [this.Aineq zeros(this.iIndiceIneq, 2*this.iCantPuntosOperacion)];
                    end
                    
                    indice_uc_desde = this.iIndiceVarOpt + 1;
                    indice_uc_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                    this.iIndiceVarOpt = indice_uc_hasta;
                    
                    this.Generadores.IdVarOptUCDesde(n_gen) = indice_uc_desde; 
                    this.lb(indice_uc_desde:indice_uc_hasta) = 0;
                    this.ub(indice_uc_desde:indice_uc_hasta) = 1;
                    this.intcon = [this.intcon indice_uc_desde:indice_uc_hasta];

                    if this.iNivelDebug > 0
                        this.ingresa_nombres(variable, indice_uc_desde,'UC');
                    end

                    indice_cpartida_desde = this.iIndiceVarOpt + 1;
                    indice_cpartida_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                    this.iIndiceVarOpt = indice_cpartida_desde;
                    
                    this.Generadores.IdVarOptCostoPartidaDesde(n_gen) = indice_cpartida_desde; 
                    this.lb(indice_cpartida_desde:indice_cpartida_hasta) = 0;
                    this.ub(indice_cpartida_desde:indice_cpartida_hasta) = 1;

                    if this.iNivelDebug > 0
                        this.ingresa_nombres(variable, indice_cpartida_desde,'CPart');
                    end
                    
                    this.agrega_generador_a_funcion_objetivo_uc(variable, indice_cpartida_desde, indice_cpartida_hasta);
                    
                    this.agrega_restriccion_potencias_min_max_generadores_n0(variable, indice_p_desde, indice_p_hasta, indice_uc_desde, indice_uc_hasta)
                    this.agrega_restriccion_costo_partida_generadores(this, variable, indice_cpartida_desde, indice_cpartida_hasta, indice_uc_desde, indice_uc_hasta)
                    if this.Generadores.TiempoMinimoOperacion(n_gen) > 1
                        this.agrega_restriccion_tiempo_minimo_operacion_generadores(this, variable, indice_uc_desde);
                    end
                    if this.Generadores.TiempoMinimoDetencion(n_gen) > 1
                        this.agrega_restriccion_tiempo_minimo_detencion_generadores(this, variable, indice_uc_desde);
                    end
                end
            end
            
            if this.pParOpt.ConsideraReservasMinimasSistema
                this.Generadores.IdVarOptResPosDesde(n_gen) = 0;
                this.Generadores.IdVarOptResNegDesde(n_gen) = 0;
                this.Generadores.IdRestriccionIResPosDesde(n_gen) = 0;
                this.Generadores.IdRestriccionIResNegDesde(n_gen) = 0;
                if this.pParOpt.EstrategiaReservasMinimasSistema == 2
                    this.Generadores.IdRestriccionIPmaxGenDespDesde(n_gen) = 0; % restricciones para calcular la potencia máxima de los generadores despachables
                    if variable.Despachable
                        % para calcular monto de reserva
                        this.agrega_restriccion_calculo_pmax_generadores(variable, indice_p_desde);
                    end
                end
                
                if variable.Despachable && variable.entrega_reservas()
                    % aumenta dimensión de contenedores. Dos variables:
                    % para reservas positivas y negativas
                    this.Fobj = [this.Fobj; zeros(2*this.iCantPuntosOperacion, 1)];
                    this.Aeq = [this.Aeq zeros(this.iIndiceEq, 2*this.iCantPuntosOperacion)];
                    if ~isempty(this.Aineq)
                        this.Aineq = [this.Aineq zeros(this.iIndiceIneq, 2*this.iCantPuntosOperacion)];
                    end
                    
                    % Reservas positivas
                    indice_res_pos_desde = this.iIndiceVarOpt + 1;
                    indice_res_pos_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                    this.iIndiceVarOpt = indice_res_pos_hasta;
                    
                    this.Generadores.IdVarOptResPosDesde(n_gen) = indice_res_pos_desde;
                    this.lb(indice_res_pos_desde:indice_res_pos_hasta) = round(0,dec_redondeo);
                    if variable.entrega_limite_reservas_positivas() > 0
                        this.ub(indice_res_pos_desde:indice_res_pos_hasta) = round(variable.entrega_limite_reservas_positivas()/this.Sbase, dec_redondeo);
                    else
                        this.ub(indice_res_pos_desde:indice_res_pos_hasta) = round(this.Generadores.Pmax(n_gen)-this.Generadores.Pmin(n_gen),dec_redondeo);
                    end

                    if this.iNivelDebug > 0
                        this.ingresa_nombres(variable, indice_res_pos_desde,'RPos');
                    end

                    % Reservas negativas
                    indice_res_neg_desde = this.iIndiceVarOpt + 1;
                    indice_res_neg_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                    this.iIndiceVarOpt = indice_res_neg_hasta;

                    this.Generadores.IdVarOptResNegDesde(n_gen) = indice_res_neg_desde;
                    this.lb(indice_res_neg_desde:indice_res_neg_hasta) = round(0,dec_redondeo);
                    if variable.entrega_limite_reservas_negativas() > 0
                        this.ub(indice_res_neg_desde:indice_res_neg_hasta) = round(variable.entrega_limite_reservas_negativas()/this.Sbase,dec_redondeo);
                    else
                        this.ub(indice_res_neg_desde:indice_res_neg_hasta) = round(this.Generadores.Pmax(n_gen)-this.Generadores.Pmin(n_gen),dec_redondeo);
                    end

                    if this.iNivelDebug > 0
                        this.ingresa_nombres(variable, indice_res_neg_desde,'RNeg');
                    end
                    
                    this.agrega_generador_a_restricciones_reservas_minimas_sistema(indice_res_pos_desde, indice_res_neg_desde);
                    this.agrega_restriccion_reservas_generador(variable, indice_p_desde, indice_res_pos_desde, indice_res_neg_desde)
                end
            end
            
            if this.pParOpt.ConsideraContingenciaN1
                for cont = 1:this.iCantContingenciasElSerie
                    this.agrega_generador_a_balance_energia_n1(variable, indice_p_desde, indice_p_hasta, cont);
                end
            end

            if this.pParOpt.ConsideraEstadoPostContingencia
                % Por ahora generadores nuevos no se consideran para contingencias!                
                this.Generadores.IdVarOptPCResPosDesde(n_gen,:) = 0;
                this.Generadores.IdVarOptPCResNegDesde(n_gen,:) = 0;
                this.Generadores.IdRestriccionIPCResPos(n_gen,:) = 0;
                this.Generadores.IdRestriccionIPCResNeg(n_gen,:) = 0;
                
                if variable.Despachable && variable.entrega_reservas()
                    this.Fobj = [this.Fobj; zeros(2*this.iCantPuntosOperacion*this.iCantContingenciasGenCons, 1)];
                    this.Aeq = [this.Aeq zeros(this.iIndiceEq, 2*this.iCantPuntosOperacion*this.iCantContingenciasGenCons)];
                    if ~isempty(this.Aineq)
                        this.Aineq = [this.Aineq zeros(this.iIndiceIneq, 2*this.iCantPuntosOperacion*this.iCantContingenciasGenCons)];
                    end

                    if variable.entrega_limite_reservas_positivas() > 0
                        lim_res_pos = round(variable.entrega_limite_reservas_positivas()/this.Sbase,dec_redondeo);
                    else
                        lim_res_pos = round(this.Generadores.Pmax(n_gen)-this.Generadores.Pmin(n_gen),dec_redondeo);
                    end
                    if variable.entrega_limite_reservas_negativas() > 0
                        lim_res_neg = round(variable.entrega_limite_reservas_negativas()/this.Sbase,dec_redondeo);
                    else
                        lim_res_neg = round(this.Generadores.Pmax(n_gen)-this.Generadores.Pmin(n_gen),dec_redondeo);
                    end
                    
                    for cont = 1:this.iCantContingenciasGenCons
                        % Reservas positivas
                        indice_res_pos_desde = this.iIndiceVarOpt + 1;
                        indice_res_pos_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                        this.iIndiceVarOpt = indice_res_pos_hasta;

                        this.Generadores.IdVarOptPCResPosDesde(n_gen,cont) = indice_res_pos_desde;
                        this.lb(indice_res_pos_desde:indice_res_pos_hasta) = 0;
                        this.ub(indice_res_pos_desde:indice_res_pos_hasta) = lim_res_pos;

                        if this.iNivelDebug > 0
                            this.ingresa_nombres(variable, indice_res_pos_desde,'PCRPos', cont);
                        end

                        % Reservas negativas
                        indice_res_neg_desde = this.iIndiceVarOpt + 1;
                        indice_res_neg_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                        this.iIndiceVarOpt = indice_res_neg_hasta;

                        this.Generadores.IdVarOptPCResNegDesde(n_gen, cont) = indice_res_neg_desde;
                        this.lb(indice_res_neg_desde:indice_res_neg_hasta) = 0;
                        this.ub(indice_res_neg_desde:indice_res_neg_hasta) = lim_res_neg;

                        if this.iNivelDebug > 0
                            this.ingresa_nombres(variable, indice_res_neg_desde,'PCRNeg', cont);
                        end                        
                    end
                    this.agrega_limite_generadores_pc(variable);
                elseif ~variable.Despachable % renovable
                    % una variable adicional (por cada punto de operación y contingencia) para el recorte de res en caso de contingencia
                    this.Fobj = [this.Fobj; zeros(this.iCantPuntosOperacion*this.iCantContingenciasGenCons, 1)];
                    this.Aeq = [this.Aeq zeros(this.iIndiceEq, this.iCantPuntosOperacion*this.iCantContingenciasGenCons)];
                    if ~isempty(this.Aineq)
                        this.Aineq = [this.Aineq zeros(this.iIndiceIneq, this.iCantPuntosOperacion*this.iCantContingenciasGenCons)];
                    end

                    for cont = 1:this.iCantContingenciasGenCons
                        indice_desde = this.iIndiceVarOpt + 1;
                        indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                        this.iIndiceVarOpt = indice_hasta;

                        this.Generadores.IdVarOptPCResNegDesde(n_gen, cont) = indice_desde;
                        this.lb(indice_desde:indice_hasta) = round(0,dec_redondeo);
                        this.ub(indice_desde:indice_hasta) = round(pmax',dec_redondeo);

                        if this.iNivelDebug > 0
                            this.ingresa_nombres(variable, indice_desde,'PCRNegERNC', cont)
                        end
                    end
                end
                this.agrega_generador_a_balance_energia_pc(variable);
            end
        end

        function agrega_subestacion(this, variable)
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            theta_max = this.pParOpt.AnguloMaximoBuses;

            % aumenta dimensión contenedores
            this.Fobj = [this.Fobj; zeros(this.iCantPuntosOperacion, 1)];
            this.Aeq = [this.Aeq zeros(this.iIndiceEq, this.iCantPuntosOperacion)];
            if ~isempty(this.Aineq)
                this.Aineq = [this.Aineq zeros(this.iIndiceIneq, this.iCantPuntosOperacion)];
            end
            
            indice_desde = this.iIndiceVarOpt + 1;
            indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
            this.iIndiceVarOpt = indice_hasta;
            
            this.Subestaciones.n = this.Subestaciones.n + 1;
            n_se = this.Subestaciones.n;
            
            this.Subestaciones.ElRed(n_se) = variable;
            this.Subestaciones.IdVarOptDesde(n_se) = indice_desde;

            this.lb(indice_desde:indice_hasta) = round(-theta_max,dec_redondeo);
            this.ub(indice_desde:indice_hasta) = round(theta_max,dec_redondeo);
            if this.iNivelDebug > 0
                this.ingresa_nombres(variable, indice_desde, 'N0');
            end
            
            % agrega nueva restricción para balance de energía
            this.agrega_balance_energia(variable);
            
            if this.pParOpt.ConsideraContingenciaN1                
                % aumenta dimensión contenedores
                this.Fobj = [this.Fobj; zeros(this.iCantPuntosOperacion*this.iCantContingenciasElSerie, 1)];
                this.Aeq = [this.Aeq zeros(this.iIndiceEq, this.iCantPuntosOperacion*this.iCantContingenciasElSerie)];
                if ~isempty(this.Aineq)
                    this.Aineq = [this.Aineq zeros(this.iIndiceIneq, this.iCantPuntosOperacion*this.iCantContingenciasElSerie)];
                end
                
                for cont = 1:this.iCantContingenciasElSerie
                    indice_desde = this.iIndiceVarOpt + 1;
                    indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                    this.iIndiceVarOpt = indice_hasta;

                    this.Subestaciones.IdVarOptN1Desde(n_se,cont) = indice_desde;

                    this.lb(indice_desde:indice_hasta) = round(-theta_max,dec_redondeo);
                    this.ub(indice_desde:indice_hasta) = round(theta_max,dec_redondeo);

                    if this.iNivelDebug > 0
                        this.ingresa_nombres(variable, indice_desde, 'N1', cont);
                    end
                end

                this.agrega_balance_energia_n1(variable);
            end

            if this.pParOpt.ConsideraEstadoPostContingencia
                % aumenta dimensión contenedores
                this.Fobj = [this.Fobj; zeros(this.iCantPuntosOperacion*this.iCantContingenciasGenCons, 1)];
                this.Aeq = [this.Aeq zeros(this.iIndiceEq, this.iCantPuntosOperacion*this.iCantContingenciasGenCons)];
                if ~isempty(this.Aineq)
                    this.Aineq = [this.Aineq zeros(this.iIndiceIneq, this.iCantPuntosOperacion*this.iCantContingenciasGenCons)];
                end
                
                for cont = 1:this.iCantContingenciasGenCons
                    indice_desde = this.iIndiceVarOpt + 1;
                    indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                    this.iIndiceVarOpt = indice_hasta;

                    this.Subestaciones.IdVarOptPCDesde(n_se,cont) = indice_desde;

                    this.lb(indice_desde:indice_hasta) = round(-theta_max,dec_redondeo);
                    this.ub(indice_desde:indice_hasta) = round(theta_max,dec_redondeo);

                    if this.iNivelDebug > 0
                        this.ingresa_nombres(variable, indice_desde, 'PC', cont);
                    end
                end
                
                this.agrega_balance_energia_pc(variable);
            end
        end
        
        function agrega_linea(this, variable)
            dec_redondeo = this.pParOpt.DecimalesRedondeo;            

            % aumenta dimensión contenedores
            this.Fobj = [this.Fobj; zeros(this.iCantPuntosOperacion, 1)];
            this.Aeq = [this.Aeq zeros(this.iIndiceEq, this.iCantPuntosOperacion)];
            if ~isempty(this.Aineq)
                this.Aineq = [this.Aineq zeros(this.iIndiceIneq, this.iCantPuntosOperacion)];
            end

            indice_desde = this.iIndiceVarOpt + 1;
            indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
            this.iIndiceVarOpt = indice_hasta;
            
            this.Lineas.n = this.Lineas.n + 1;
            this.Lineas.ElRed(this.Lineas.n) = variable;
            this.Lineas.IdVarOptDesde(this.Lineas.n) = indice_desde;
            this.Lineas.FlagObservacion(this.Lineas.n) = variable.tiene_flag_observacion();

            sr = variable.entrega_sr()/this.Sbase;
            this.Lineas.Pmax(this.Lineas.n) = sr;
            
            this.lb(indice_desde:indice_hasta) = round(-sr,dec_redondeo);
            this.ub(indice_desde:indice_hasta) = round(sr,dec_redondeo);
            
            if this.iNivelDebug > 0
                this.ingresa_nombres(variable, indice_desde,'N0');
            end
            
            this.agrega_eserie_a_balance_energia(variable, indice_desde, indice_hasta);
            this.agrega_relaciones_flujos_angulos_linea(variable, indice_desde, indice_hasta);
            
            if this.pParOpt.ConsideraContingenciaN1
                sr = variable.entrega_sr_n1()/this.Sbase;
                
                % aumenta dimensión contenedores
                this.Fobj = [this.Fobj; zeros(this.iCantPuntosOperacion*this.iCantContingenciasElSerie, 1)];
                this.Aeq = [this.Aeq zeros(this.iIndiceEq, this.iCantPuntosOperacion*this.iCantContingenciasElSerie)];
                if ~isempty(this.Aineq)
                    this.Aineq = [this.Aineq zeros(this.iIndiceIneq, this.iCantPuntosOperacion*this.iCantContingenciasElSerie)];
                end
                
                % agrega elemento a contingencias actuales. Después se verifica si hay que agregar una nueva contingencia
                for cont = 1:this.iCantContingenciasElSerie

                    indice_desde = this.iIndiceVarOpt + 1;
                    indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                    this.iIndiceVarOpt = indice_hasta;

                    this.Lineas.IdVarOptN1Desde(this.Lineas.n, cont) = indice_desde;
                    this.lb(indice_desde:indice_hasta) = round(-sr,dec_redondeo);
                    this.ub(indice_desde:indice_hasta) = round(sr,dec_redondeo);

                    if this.iNivelDebug > 0
                        this.ingresa_nombres(variable, indice_desde, 'N1', cont);
                    end
                    this.agrega_eserie_a_balance_energia_n1(variable, indice_desde, indice_hasta, cont);
                    this.agrega_relaciones_flujos_angulos_linea_n1(variable, indice_desde, indice_hasta, cont);
                end
            end
            
            if this.pParOpt.ConsideraEstadoPostContingencia
                sr = variable.entrega_sr()/this.Sbase;
                
                % aumenta dimensión contenedores
                this.Fobj = [this.Fobj; zeros(this.iCantPuntosOperacion*this.iCantContingenciasGenCons, 1)];
                this.Aeq = [this.Aeq zeros(this.iIndiceEq, this.iCantPuntosOperacion*this.iCantContingenciasGenCons)];
                if ~isempty(this.Aineq)
                    this.Aineq = [this.Aineq zeros(this.iIndiceIneq, this.iCantPuntosOperacion*this.iCantContingenciasGenCons)];
                end
                
                % agrega elemento a contingencias actuales. Después se verifica si hay que agregar una nueva contingencia
                for cont = 1:this.iCantContingenciasGenCons

                    indice_desde = this.iIndiceVarOpt + 1;
                    indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                    this.iIndiceVarOpt = indice_hasta;

                    this.Lineas.IdVarOptPCDesde(this.Lineas.n, cont) = indice_desde;
                    this.lb(indice_desde:indice_hasta) = round(-sr,dec_redondeo);
                    this.ub(indice_desde:indice_hasta) = round(sr,dec_redondeo);

                    if this.iNivelDebug > 0
                        this.ingresa_nombres(variable, indice_desde, 'PC', cont);
                    end
                    this.agrega_eserie_a_balance_energia_pc(variable, indice_desde, indice_hasta, cont);
                    this.agrega_relaciones_flujos_angulos_linea_pc(variable, indice_desde, indice_hasta, cont);
                end
            end
        end

        function agrega_trafo(this, variable)
            dec_redondeo = this.pParOpt.DecimalesRedondeo;            

            % aumenta dimensión contenedores
            this.Fobj = [this.Fobj; zeros(this.iCantPuntosOperacion, 1)];
            this.Aeq = [this.Aeq zeros(this.iIndiceEq, this.iCantPuntosOperacion)];
            if ~isempty(this.Aineq)
                this.Aineq = [this.Aineq zeros(this.iIndiceIneq, this.iCantPuntosOperacion)];
            end

            indice_desde = this.iIndiceVarOpt + 1;
            indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
            this.iIndiceVarOpt = indice_hasta;
            
            this.Trafos.n = this.Trafos.n + 1;
            this.Trafos.ElRed(this.Trafos.n) = variable;
            this.Trafos.IdVarOptDesde(this.Trafos.n) = indice_desde;

            sr = variable.entrega_sr()/this.Sbase;

            this.Trafos.FlagObservacion(this.Trafos.n) = variable.tiene_flag_observacion();
            this.Trafos.Pmax(this.Trafos.n) = sr;
            
            this.lb(indice_desde:indice_hasta) = round(-sr,dec_redondeo);
            this.ub(indice_desde:indice_hasta) = round(sr,dec_redondeo);
            
            if this.iNivelDebug > 0
                this.ingresa_nombres(variable, indice_desde,'N0');
            end
            
            this.agrega_eserie_a_balance_energia(variable, indice_desde, indice_hasta);
            this.agrega_relaciones_flujos_angulos_trafo(variable, indice_desde, indice_hasta);

            if this.pParOpt.ConsideraContingenciaN1
                sr = variable.entrega_sr_n1()/this.Sbase;
                
                % aumenta dimensión contenedores
                this.Fobj = [this.Fobj; zeros(this.iCantPuntosOperacion*this.iCantContingenciasElSerie, 1)];
                this.Aeq = [this.Aeq zeros(this.iIndiceEq, this.iCantPuntosOperacion*this.iCantContingenciasElSerie)];
                if ~isempty(this.Aineq)
                    this.Aineq = [this.Aineq zeros(this.iIndiceIneq, this.iCantPuntosOperacion*this.iCantContingenciasElSerie)];
                end

                % agrega elemento a contingencias actuales. Después se verifica si hay que agregar una nueva contingencia
                for cont = 1:this.iCantContingenciasElSerie

                    indice_desde = this.iIndiceVarOpt + 1;
                    indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                    this.iIndiceVarOpt = indice_hasta;

                    this.Trafos.IdVarOptN1Desde(this.Trafos.n, cont) = indice_desde;
                    this.lb(indice_desde:indice_hasta) = round(-sr,dec_redondeo);
                    this.ub(indice_desde:indice_hasta) = round(sr,dec_redondeo);

                    if this.iNivelDebug > 0
                        this.ingresa_nombres(variable, indice_desde, 'N1', cont);
                    end
                    this.agrega_eserie_a_balance_energia_n1(variable, indice_desde, indice_hasta, cont);
                    this.agrega_relaciones_flujos_angulos_trafo_n1(variable, indice_desde, indice_hasta, cont);
                end
            end

            if this.pParOpt.ConsideraEstadoPostContingencia
                sr = variable.entrega_sr()/this.Sbase;
                
                % aumenta dimensión contenedores
                this.Fobj = [this.Fobj; zeros(this.iCantPuntosOperacion*this.iCantContingenciasGenCons, 1)];
                this.Aeq = [this.Aeq zeros(this.iIndiceEq, this.iCantPuntosOperacion*this.iCantContingenciasGenCons)];
                if ~isempty(this.Aineq)
                    this.Aineq = [this.Aineq zeros(this.iIndiceIneq, this.iCantPuntosOperacion*this.iCantContingenciasGenCons)];
                end
                
                % agrega elemento a contingencias actuales. Después se verifica si hay que agregar una nueva contingencia
                for cont = 1:this.iCantContingenciasGenCons

                    indice_desde = this.iIndiceVarOpt + 1;
                    indice_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                    this.iIndiceVarOpt = indice_hasta;

                    this.Trafos.IdVarOptPCDesde(this.Lineas.n, cont) = indice_desde;
                    this.lb(indice_desde:indice_hasta) = round(-sr,dec_redondeo);
                    this.ub(indice_desde:indice_hasta) = round(sr,dec_redondeo);

                    if this.iNivelDebug > 0
                        this.ingresa_nombres(variable, indice_desde, 'PC', cont);
                    end
                    this.agrega_eserie_a_balance_energia_pc(variable, indice_desde, indice_hasta, cont);
                    this.agrega_relaciones_flujos_angulos_trafo_pc(variable, indice_desde, indice_hasta, cont);
                end
            end            
        end

        function agrega_bateria(this, variable)
            dec_redondeo = this.pParOpt.DecimalesRedondeo;            
            
            this.Baterias.n = this.Baterias.n + 1;
            this.Baterias.ElRed(this.Baterias.n) = variable;
                        
            % primero variables de potencia
            this.Fobj = [this.Fobj; zeros(2*this.iCantPuntosOperacion, 1)];
            this.Aeq = [this.Aeq zeros(this.iIndiceEq, 2*this.iCantPuntosOperacion)];
            if ~isempty(this.Aineq)
                this.Aineq = [this.Aineq zeros(this.iIndiceIneq, 2*this.iCantPuntosOperacion)];
            end
            
            % Potencia inyectada a la red
            indice_p_descarga_desde = this.iIndiceVarOpt + 1;
            indice_p_descarga_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
            this.iIndiceVarOpt = indice_p_descarga_hasta;
            this.Baterias.IdVarOptDesdeDescarga(this.Baterias.n) = indice_p_descarga_desde;
            
            this.lb(indice_p_descarga_desde:indice_p_descarga_hasta) = 0;
            if this.bConsideraDependenciaTemporal
                pmax_descarga = variable.entrega_pmax_descarga()/this.Sbase;
                this.ub(indice_p_descarga_desde:indice_p_descarga_hasta) = round(pmax_descarga,dec_redondeo);
            else
                % en este caso, la potencia inyectada a la red debe coincidir con la energía actual almacenada por la batería y la energía mínima de la batería
                pmax_descarga = variable.entrega_potencia_maxima_descarga_actual();
                this.ub(indice_p_descarga_desde:indice_p_descarga_hasta) = round(pmax_descarga',dec_redondeo);                    
            end

            if this.iNivelDebug > 0
                this.ingresa_nombres(variable, indice_p_descarga_desde, 'Pdescarga');
            end
            
            % Potencia consumida desde la red
            indice_p_carga_desde = this.iIndiceVarOpt + 1;
            indice_p_carga_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
            this.iIndiceVarOpt = indice_p_carga_hasta;
            this.Baterias.IdVarOptDesdeCarga(this.Baterias.n) = indice_p_carga_desde;

            this.lb(indice_p_carga_desde:indice_p_carga_hasta) = 0;
            if this.bConsideraDependenciaTemporal
                pmax_carga = variable.entrega_pmax_carga()/this.Sbase;
                this.ub(indice_p_carga_desde:indice_p_carga_hasta) = round(pmax_carga,dec_redondeo);
            else
                % en este caso, la potencia inyectada a la red debe coincidir con la energía actual almacenada por la batería y la energía mínima de la batería
                pmax_carga = variable.entrega_potencia_maxima_carga_actual();
                this.ub(indice_p_carga_desde:indice_p_carga_hasta) = round(pmax_carga',dec_redondeo);                    
            end

            if this.iNivelDebug > 0
                this.ingresa_nombres(variable, indice_p_carga_desde, 'Pcarga');
            end
            
            this.agrega_bateria_a_balance_energia(variable, indice_p_descarga_desde, indice_p_descarga_hasta, indice_p_carga_desde, indice_p_carga_hasta);
            
            if this.bConsideraDependenciaTemporal
                % variables de optimización energía
                this.Fobj = [this.Fobj; zeros(this.iCantPuntosOperacion, 1)];
                this.Aeq = [this.Aeq zeros(this.iIndiceEq, this.iCantPuntosOperacion)];
                if ~isempty(this.Aineq)
                    this.Aineq = [this.Aineq zeros(this.iIndiceIneq, this.iCantPuntosOperacion)];
                end
                
                indice_e_desde = this.iIndiceVarOpt + 1;
                indice_e_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                this.iIndiceVarOpt = indice_e_hasta;
                this.Baterias.IdVarOptDesdeE(this.Baterias.n) = indice_e_desde;

                emax = variable.entrega_capacidad()/this.Sbase;
                emin = variable.entrega_energia_minima()/this.Sbase;
                
                this.lb(indice_e_desde:indice_e_hasta) = round(emin,dec_redondeo); 
                this.ub(indice_e_desde:indice_e_hasta) = round(emax,dec_redondeo);
                if ~this.pParOpt.OptimizaSoCInicialBaterias
                    einicial = variable.entrega_soc_actual()*emax;
                    this.lb(indice_e_desde-1+this.vIndicesPOConsecutivos(:,1)) = round(einicial,dec_redondeo);
                    this.ub(indice_e_desde-1+this.vIndicesPOConsecutivos(:,1)) = round(einicial,dec_redondeo);
                    this.lb(indice_e_desde-1+this.vIndicesPOConsecutivos(:,2)) = round(einicial,dec_redondeo);
                    this.ub(indice_e_desde-1+this.vIndicesPOConsecutivos(:,2)) = round(einicial,dec_redondeo);
                end

                this.agrega_balance_temporal_baterias(variable, indice_p_descarga_desde, indice_p_descarga_hasta, indice_p_carga_desde, indice_p_carga_hasta, indice_e_desde, indice_e_hasta);

                if this.iNivelDebug > 0
                    this.ingresa_nombres(variable, indice_e_desde, 'E');
                end
            else
                indice_e_desde = 0;
            end

            if this.pParOpt.ConsideraReservasMinimasSistema
                % variables de reservas
                this.Fobj = [this.Fobj; zeros(2*this.iCantPuntosOperacion, 1)];
                this.Aeq = [this.Aeq zeros(this.iIndiceEq, 2*this.iCantPuntosOperacion)];
                if ~isempty(this.Aineq)
                    this.Aineq = [this.Aineq zeros(this.iIndiceIneq, 2*this.iCantPuntosOperacion)];
                end
                
                indice_res_descarga_desde = this.iIndiceVarOpt + 1;
                indice_res_descarga_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                this.iIndiceVarOpt = indice_res_descarga_desde;

                this.Baterias.IdVarOptResDescargaDesde(this.Baterias.n) = indice_res_descarga_desde;
                this.lb(indice_res_descarga_desde:indice_res_descarga_hasta) = 0;
                this.ub(indice_res_descarga_desde:indice_res_descarga_hasta) = round(pmax_descarga,dec_redondeo); % pmax_descarga ya considera si hay dependencia temporal o no

                if this.iNivelDebug > 0
                    this.ingresa_nombres(variable, indice_res_descarga_desde, 'ResDescarga')
                end

                indice_res_carga_desde = this.iIndiceVarOpt + 1;
                indice_res_carga_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                this.iIndiceVarOpt = indice_res_carga_hasta;

                this.Baterias.IdVarOptResCargaDesde(this.Baterias.n) = indice_res_carga_desde;
                this.lb(indice_res_carga_desde:indice_res_carga_hasta) = 0;
                this.ub(indice_res_carga_desde:indice_res_carga_hasta) = round(pmax_carga,dec_redondeo); % pmax_carga ya considera si hay dependencia temporal o no

                if this.iNivelDebug > 0
                    this.ingresa_nombres(variable, indice_res_carga_desde, 'ResCarga')
                end
                
                this.agrega_bateria_a_restricciones_reservas_minimas_sistema(indice_res_descarga_desde, indice_res_carga_desde);
                this.agrega_restriccion_reservas_baterias(variable, indice_p_descarga_desde, indice_p_descarga_hasta, indice_e_desde, indice_res_descarga_desde, indice_res_carga_desde)
            end

            if this.pParOpt.ConsideraContingenciaN1
                for cont = 1:this.iCantContingenciasElSerie
                    this.agrega_bateria_a_balance_energia_n1(variable, indice_p_descarga_desde, indice_p_carga_desde, cont);
                end
            end
            
            if this.pParOpt.ConsideraEstadoPostContingencia
                this.Fobj = [this.Fobj; zeros(2*this.iCantPuntosOperacion*this.iCantContingenciasGenCons, 1)];
                this.Aeq = [this.Aeq zeros(this.iIndiceEq, 2*this.iCantPuntosOperacion*this.iCantContingenciasGenCons)];
                if ~isempty(this.Aineq)
                    this.Aineq = [this.Aineq zeros(this.iIndiceIneq, 2*this.iCantPuntosOperacion*this.iCantContingenciasGenCons)];
                end

                for cont = 1:this.iCantContingenciasGenCons         
                    indice_pc_descarga_desde = this.iIndiceVarOpt + 1;
                    indice_pc_descarga_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                    this.iIndiceVarOpt = indice_hasta;

                    this.Baterias.IdVarOptPCResDescargaDesde(this.Baterias.n, cont) = indice_pc_descarga_desde;
                    this.lb(indice_pc_descarga_desde:indice_pc_descarga_hasta) = 0;
                    this.ub(indice_pc_descarga_desde:indice_pc_descarga_hasta) = round(pmax_descarga,dec_redondeo);

                    if this.iNivelDebug > 0
                        this.ingresa_nombres(variable, indice_pc_descarga_desde, 'PCResDescarga', cont)
                    end

                    indice_pc_carga_desde = this.iIndiceVarOpt + 1;
                    indice_pc_carga_hasta = this.iIndiceVarOpt + this.iCantPuntosOperacion;
                    this.iIndiceVarOpt = indice_pc_carga_hasta;

                    this.Baterias.IdVarOptPCResCargaDesde(this.Baterias.n, cont) = indice_pc_carga_desde;
                    this.lb(indice_pc_carga_desde:indice_pc_carga_hasta) = 0;
                    this.ub(indice_pc_carga_desde:indice_pc_carga_hasta) = round(pmax_carga,dec_redondeo);
                    
                    if this.iNivelDebug > 0
                        this.ingresa_nombres(variable, indice_pc_carga_desde, 'PCResCarga', cont)
                    end
                end
                this.agrega_bateria_a_balance_energia_pc(variable);
                this.agrega_limites_baterias_pc(variable);
            end
        end
        
        function elimina_variable(this, variable)
            if isa(variable, 'cLinea')
                this.elimina_linea(variable);
            elseif isa(variable, 'cTransformador2D')
                this.elimina_trafo(variable);
            elseif isa(variable, 'cBateria')
                this.elimina_bateria(variable);
            elseif isa(variable,'cSubestacion')
                this.elimina_subestacion(variable);
            elseif isa(variable,'cGenerador')
                this.elimina_generador(variable);
            else
                error = MException('cOPF:agrega_variable','Tipo de variable a agregar no implementado');
                throw(error)
            end            
        end
        
        function elimina_subestacion(this, variable)
            cant_po = this.iCantPuntosOperacion;
            n_se = variable.entrega_id();
            
            indice_varopt_desde = this.Subestaciones.IdVarOptDesde(n_se);
            indice_varopt_hasta = indice_varopt_desde + cant_po - 1;
            % se elimina balance de energía. Se verifica eso sí que no
            % haya ningún elemento conectado aún
            id_restriccion_desde = this.Subestaciones.IdRestriccionEBalanceDesde(n_se);
            id_restriccion_hasta = id_restriccion_desde + cant_po - 1;

            if ~isempty(nonzeros(this.Aeq(id_restriccion_desde:id_restriccion_hasta,:)))
                error = MException('cOPF:elimina_subestacion','Error de programación. No se puede eliminar subestacion, porque aún existen variables en balance de energía!');
                throw(error)
            end

            % elimina restriccion
            this.Aeq(id_restriccion_desde:id_restriccion_hasta,:) = [];
            this.beq(id_restriccion_desde:id_restriccion_hasta) = [];
            this.iIndiceEq = this.iIndiceEq - cant_po;

            if ~isempty(this.NombreEq)
                this.NombreEq(id_restriccion_desde:id_restriccion_hasta) = [];
            end

            % borra subestacion de indice de restricciones de igualdad y actualiza índices 
            this.Subestaciones.IdRestriccionEBalanceDesde(n_se) = [];
            this.actualiza_indices_restriccion_igualdad(id_restriccion_desde);
            
            % elimina variable de contenedores
            this.Fobj(indice_varopt_desde:indice_varopt_hasta) = [];
            this.lb(indice_varopt_desde:indice_varopt_hasta) = [];
            this.ub(indice_varopt_desde:indice_varopt_hasta) = [];
            if ~isempty(this.NombreVariables)
                this.NombreVariables(indice_varopt_desde:indice_varopt_hasta) = [];
            end
            this.Aeq(:,indice_varopt_desde:indice_varopt_hasta) = [];
            if ~isempty(this.Aineq)
                this.Aineq(:,indice_varopt_desde:indice_varopt_hasta) = [];
            end
            this.iIndiceVarOpt = this.iIndiceVarOpt - cant_po;

            % borra subestacion de indice de variables de optimización y actualiza índices
            this.Subestaciones.IdVarOptDesde(n_se) = [];
            this.actualiza_indice_variables(indice_varopt_desde);

            if this.pParOpt.ConsideraContingenciaN1
                indice_varopt_desde = this.Subestaciones.IdVarOptN1Desde(n_se,1);
                indice_varopt_hasta = this.Subestaciones.IdVarOptN1Desde(n_se,this.iCantContingenciasElSerie) + cant_po - 1;

                % se elimina balance de energía N-1
                id_restriccion_desde = this.Subestaciones.IdRestriccionEBalanceN1Desde(n_se,1);
                id_restriccion_hasta = this.Subestaciones.IdRestriccionEBalanceN1Desde(n_se,this.iCantContingenciasElSerie) + cant_po - 1;

                if ~isempty(nonzeros(this.Aeq(id_restriccion_desde:id_restriccion_hasta,:)))
                    error = MException('cOPF:elimina_subestacion','Error de programación. No se puede eliminar subestacion, porque aún existen variables en balance de energía!');
                    throw(error)
                end

                % elimina restriccion
                this.Aeq(id_restriccion_desde:id_restriccion_hasta,:) = [];
                this.beq(id_restriccion_desde:id_restriccion_hasta) = [];
                this.iIndiceEq = this.iIndiceEq - cant_po*this.iCantContingenciasElSerie;

                if ~isempty(this.NombreEq)
                    this.NombreEq(id_restriccion_desde:id_restriccion_hasta) = [];
                end

                % borra subestacion de indice de restricciones de igualdad y actualiza índices 
                this.Subestaciones.IdRestriccionEBalanceN1Desde(n_se,:) = [];
                this.actualiza_indices_restriccion_igualdad(id_restriccion_desde, this.iCantContingenciasElSerie);

                % elimina variable de contenedores
                this.Fobj(indice_varopt_desde:indice_varopt_hasta) = [];
                this.lb(indice_varopt_desde:indice_varopt_hasta) = [];
                this.ub(indice_varopt_desde:indice_varopt_hasta) = [];
                if ~isempty(this.NombreVariables)
                    this.NombreVariables(indice_varopt_desde:indice_varopt_hasta) = [];
                end
                this.Aeq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                if ~isempty(this.Aineq)
                    this.Aineq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                end

                this.iIndiceVarOpt = this.iIndiceVarOpt - cant_po*this.iCantContingenciasElSerie;

                % borra subestacion de indice de variables de optimización y actualiza índices
                this.Subestaciones.IdVarOptN1Desde(n_se, :) = [];
                this.actualiza_indice_variables(indice_varopt_desde, this.iCantContingenciasElSerie);                
            end

            if this.pParOpt.ConsideraEstadoPostContingencia
                indice_varopt_desde = this.Subestaciones.IdVarOptPCDesde(n_se,1);
                indice_varopt_hasta = this.Subestaciones.IdVarOptPCDesde(n_se,this.iCantContingenciasGenCons) + cant_po - 1;

                % se elimina balance de energía PC
                id_restriccion_desde = this.Subestaciones.IdRestriccionEBalancePCDesde(n_se,1);
                id_restriccion_hasta = this.Subestaciones.IdRestriccionEBalancePCDesde(n_se,this.iCantContingenciasGenCons) + cant_po - 1;

                if ~isempty(nonzeros(this.Aeq(id_restriccion_desde:id_restriccion_hasta,:)))
                    error = MException('cOPF:elimina_subestacion','Error de programación. No se puede eliminar subestacion, porque aún existen variables en balance de energía!');
                    throw(error)
                end

                % elimina restriccion
                this.Aeq(id_restriccion_desde:id_restriccion_hasta,:) = [];
                this.beq(id_restriccion_desde:id_restriccion_hasta) = [];
                this.iIndiceEq = this.iIndiceEq - cant_po*this.iCantContingenciasGenCons;

                if ~isempty(this.NombreEq)
                    this.NombreEq(id_restriccion_desde:id_restriccion_hasta) = [];
                end

                % borra subestacion de indice de restricciones de igualdad y actualiza índices 
                this.Subestaciones.IdRestriccionEBalancePCDesde(n_se,:) = [];
                this.actualiza_indices_restriccion_igualdad(id_restriccion_desde, this.iCantContingenciasGenCons);

                % elimina variable de contenedores
                this.Fobj(indice_varopt_desde:indice_varopt_hasta) = [];
                this.lb(indice_varopt_desde:indice_varopt_hasta) = [];
                this.ub(indice_varopt_desde:indice_varopt_hasta) = [];
                if ~isempty(this.NombreVariables)
                    this.NombreVariables(indice_varopt_desde:indice_varopt_hasta) = [];
                end
                this.Aeq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                if ~isempty(this.Aineq)
                    this.Aineq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                end

                this.iIndiceVarOpt = this.iIndiceVarOpt - cant_po*this.iCantContingenciasGenCons;

                % borra subestacion de indice de variables de optimización y actualiza índices
                this.Subestaciones.IdVarOptPCDesde(n_se, :) = [];
                this.actualiza_indice_variables(indice_varopt_desde, this.iCantContingenciasGenCons);                
            end
            
            % se borra la variable de los contenedores
            this.Subestaciones.ElRed(variable.entrega_id()) = [];
            this.Subestaciones.n = this.Subestaciones.n - 1;

        end
        
        function elimina_linea(this, variable)
            cant_po = this.iCantPuntosOperacion;
            n_linea = variable.entrega_id();
            
            indice_varopt_desde = this.Lineas.IdVarOptDesde(n_linea);
            indice_varopt_hasta = indice_varopt_desde + cant_po - 1;
            % se elimina balance de energía. Se verifica eso sí que no
            % haya ningún elemento conectado aún
            id_restriccion_desde = this.Lineas.IdRestriccionEFlujosAngulosDesde(n_linea);
            id_restriccion_hasta = id_restriccion_desde + cant_po - 1;

            % elimina restriccion
            this.Aeq(id_restriccion_desde:id_restriccion_hasta,:) = [];
            this.beq(id_restriccion_desde:id_restriccion_hasta) = [];
            this.iIndiceEq = this.iIndiceEq - cant_po;

            if ~isempty(this.NombreEq)
                this.NombreEq(id_restriccion_desde:id_restriccion_hasta) = [];
            end

            % borra linea de indice de restricciones de igualdad y actualiza índices 
            this.Lineas.IdRestriccionEFlujosAngulosDesde(n_linea) = [];
            this.actualiza_indices_restriccion_igualdad(id_restriccion_desde);

            % elimina variable de contenedores
            this.Fobj(indice_varopt_desde:indice_varopt_hasta) = [];
            this.lb(indice_varopt_desde:indice_varopt_hasta) = [];
            this.ub(indice_varopt_desde:indice_varopt_hasta) = [];
            if ~isempty(this.NombreVariables)
                this.NombreVariables(indice_varopt_desde:indice_varopt_hasta) = [];
            end
            this.Aeq(:,indice_varopt_desde:indice_varopt_hasta) = [];
            if ~isempty(this.Aineq)
                this.Aineq(:,indice_varopt_desde:indice_varopt_hasta) = [];
            end

            % borra línea de indice de variables de optimización y actualiza índices
            this.Lineas.IdVarOptDesde(n_linea) = [];
            this.actualiza_indice_variables(indice_varopt_desde);
            
            this.iIndiceVarOpt = this.iIndiceVarOpt - cant_po;

            if this.pParOpt.ConsideraContingenciaN1
                if ismember(variable, this.pContingenciasElSerie)
                    error = MException('cOPF:elimina_linea','Linea tiene contingencia N-1. Por ahora no se puede borrar. Error de programación');
                    throw(error)
                end
                
                indice_varopt_desde = this.Lineas.IdVarOptN1Desde(n_linea, 1);
                indice_varopt_hasta = this.Lineas.IdVarOptN1Desde(n_linea, this.iCantContingenciasElSerie) + cant_po - 1;
                
                % se elimina balance de energía n-1. Se verifica eso sí que no
                % haya ningún elemento conectado aún
                id_restriccion_desde = this.Lineas.IdRestriccionEFlujosAngulosN1Desde(n_linea, 1);
                id_restriccion_hasta = this.Lineas.IdRestriccionEFlujosAngulosN1Desde(n_linea, this.iCantContingenciasElSerie) + cant_po - 1;

                % elimina restriccion
                this.Aeq(id_restriccion_desde:id_restriccion_hasta,:) = [];
                this.beq(id_restriccion_desde:id_restriccion_hasta) = [];
                this.iIndiceEq = this.iIndiceEq - cant_po*this.iCantContingenciasElSerie;

                if ~isempty(this.NombreEq)
                    this.NombreEq(id_restriccion_desde:id_restriccion_hasta) = [];
                end

                this.actualiza_indices_restriccion_igualdad(id_restriccion_desde, this.iCantContingenciasElSerie);

                % elimina variable de contenedores
                this.Fobj(indice_varopt_desde:indice_varopt_hasta) = [];
                this.lb(indice_varopt_desde:indice_varopt_hasta) = [];
                this.ub(indice_varopt_desde:indice_varopt_hasta) = [];
                if ~isempty(this.NombreVariables)
                    this.NombreVariables(indice_varopt_desde:indice_varopt_hasta) = [];
                end
                this.Aeq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                if ~isempty(this.Aineq)
                    this.Aineq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                end

                this.actualiza_indice_variables(indice_varopt_desde, this.iCantContingenciasElSerie);

                this.iIndiceVarOpt = this.iIndiceVarOpt - cant_po*this.iCantContingenciasElSerie;
                
                % borra linea de indice de restricciones de igualdad y actualiza índices 
                this.Lineas.IdRestriccionEFlujosAngulosN1Desde(n_linea,:) = [];
                
                % borra línea de indice de variables de optimización y actualiza índices
                this.Lineas.IdVarOptN1Desde(n_linea,:) = [];
            end

            if this.pParOpt.ConsideraEstadoPostContingencia                
                indice_varopt_desde = this.Lineas.IdVarOptPCDesde(n_linea, 1);
                indice_varopt_hasta = this.Lineas.IdVarOptPCDesde(n_linea, this.iCantContingenciasGenCons) + cant_po - 1;
                
                % se elimina balance de energía n-1. Se verifica eso sí que no
                % haya ningún elemento conectado aún
                id_restriccion_desde = this.Lineas.IdRestriccionEFlujosAngulosPCDesde(n_linea, 1);
                id_restriccion_hasta = this.Lineas.IdRestriccionEFlujosAngulosPCDesde(n_linea, this.iCantContingenciasGenCons) + cant_po - 1;

                % elimina restriccion
                this.Aeq(id_restriccion_desde:id_restriccion_hasta,:) = [];
                this.beq(id_restriccion_desde:id_restriccion_hasta) = [];
                this.iIndiceEq = this.iIndiceEq - cant_po*this.iCantContingenciasGenCons;

                if ~isempty(this.NombreEq)
                    this.NombreEq(id_restriccion_desde:id_restriccion_hasta) = [];
                end

                this.actualiza_indices_restriccion_igualdad(id_restriccion_desde, this.iCantContingenciasGenCons);

                % elimina variable de contenedores
                this.Fobj(indice_varopt_desde:indice_varopt_hasta) = [];
                this.lb(indice_varopt_desde:indice_varopt_hasta) = [];
                this.ub(indice_varopt_desde:indice_varopt_hasta) = [];
                if ~isempty(this.NombreVariables)
                    this.NombreVariables(indice_varopt_desde:indice_varopt_hasta) = [];
                end
                this.Aeq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                if ~isempty(this.Aineq)
                    this.Aineq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                end

                this.actualiza_indice_variables(indice_varopt_desde, this.iCantContingenciasGenCons);

                this.iIndiceVarOpt = this.iIndiceVarOpt - cant_po*this.iCantContingenciasGenCons;
                
                % borra linea de indice de restricciones de igualdad y actualiza índices 
                this.Lineas.IdRestriccionEFlujosAngulosPCDesde(n_linea,:) = [];
                
                % borra línea de indice de variables de optimización y actualiza índices
                this.Lineas.IdVarOptPCDesde(n_linea,:) = [];
            end
            
            % se borra la variable de los contenedores
            this.Lineas.ElRed(n_linea) = [];
            this.Lineas.FlagObservacion(n_linea) = [];
            this.Lineas.Pmax(n_linea) = [];
            
            this.Lineas.n = this.Lineas.n - 1;
        end

        function elimina_trafo(this, variable)
            cant_po = this.iCantPuntosOperacion;
            n_trafo = variable.entrega_id();
            
            indice_varopt_desde = this.Trafos.IdVarOptDesde(n_trafo);
            indice_varopt_hasta = indice_varopt_desde + cant_po - 1;
            % se elimina balance de energía. Se verifica eso sí que no
            % haya ningún elemento conectado aún
            id_restriccion_desde = this.Trafos.IdRestriccionEFlujosAngulosDesde(n_trafo);
            id_restriccion_hasta = id_restriccion_desde + cant_po - 1;

            % elimina restriccion
            this.Aeq(id_restriccion_desde:id_restriccion_hasta,:) = [];
            this.beq(id_restriccion_desde:id_restriccion_hasta) = [];
            this.iIndiceEq = this.iIndiceEq - cant_po;

            if ~isempty(this.NombreEq)
                this.NombreEq(id_restriccion_desde:id_restriccion_hasta) = [];
            end

            % borra linea de indice de restricciones de igualdad y actualiza índices 
            this.Trafos.IdRestriccionEFlujosAngulosDesde(n_trafo) = [];
            this.actualiza_indices_restriccion_igualdad(id_restriccion_desde);            
            
            % elimina variable de contenedores
            this.Fobj(indice_varopt_desde:indice_varopt_hasta) = [];
            this.lb(indice_varopt_desde:indice_varopt_hasta) = [];
            this.ub(indice_varopt_desde:indice_varopt_hasta) = [];
            if ~isempty(this.NombreVariables)
                this.NombreVariables(indice_varopt_desde:indice_varopt_hasta) = [];
            end
            this.Aeq(:,indice_varopt_desde:indice_varopt_hasta) = [];
            if ~isempty(this.Aineq)
                this.Aineq(:,indice_varopt_desde:indice_varopt_hasta) = [];
            end

            % borra subestacion de indice de variables de optimización y actualiza índices
            this.Trafos.IdVarOptDesde(n_trafo) = [];
            this.actualiza_indice_variables(indice_varopt_desde);

            this.iIndiceVarOpt = this.iIndiceVarOpt - cant_po;

            if this.pParOpt.ConsideraContingenciaN1
                if ismember(variable, this.pContingenciasElSerie)
                    error = MException('cOPF:elimina_trafo','Trafo tiene contingencia N-1. Por ahora no se puede borrar. Error de programación');
                    throw(error)
                end
                
                indice_varopt_desde = this.Trafos.IdVarOptN1Desde(n_trafo, 1);
                indice_varopt_hasta = this.Trafos.IdVarOptN1Desde(n_trafo, this.iCantContingenciasElSerie) + cant_po - 1;
                % se elimina balance de energía n-1. Se verifica eso sí que no
                % haya ningún elemento conectado aún
                id_restriccion_desde = this.Trafos.IdRestriccionEFlujosAngulosN1Desde(n_trafo, 1);
                id_restriccion_hasta = this.Trafos.IdRestriccionEFlujosAngulosN1Desde(n_trafo, this.iCantContingenciasElSerie) + cant_po - 1;

                % elimina restriccion
                this.Aeq(id_restriccion_desde:id_restriccion_hasta,:) = [];
                this.beq(id_restriccion_desde:id_restriccion_hasta) = [];
                this.iIndiceEq = this.iIndiceEq - cant_po;

                if ~isempty(this.NombreEq)
                    this.NombreEq(id_restriccion_desde:id_restriccion_hasta) = [];
                end

                this.actualiza_indices_restriccion_igualdad(id_restriccion_desde, this.iCantContingenciasElSerie);

                % elimina variable de contenedores
                this.Fobj(indice_varopt_desde:indice_varopt_hasta) = [];
                this.lb(indice_varopt_desde:indice_varopt_hasta) = [];
                this.ub(indice_varopt_desde:indice_varopt_hasta) = [];
                if ~isempty(this.NombreVariables)
                    this.NombreVariables(indice_varopt_desde:indice_varopt_hasta) = [];
                end
                this.Aeq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                if ~isempty(this.Aineq)
                    this.Aineq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                end

                this.actualiza_indice_variables(indice_varopt_desde, this.iCantContingenciasElSerie);

                this.iIndiceVarOpt = this.iIndiceVarOpt - cant_po*this.iCantContingenciasElSerie;
                
                % borra trafo de indice de restricciones de igualdad y actualiza índices 
                this.Trafos.IdRestriccionEFlujosAngulosN1Desde(n_trafo,:) = [];
                
                % borra trafo de indice de variables de optimización y actualiza índices
                this.Trafos.IdVarOptN1Desde(n_trafo,:) = [];
            end

            if this.pParOpt.ConsideraEstadoPostContingencia
                
                indice_varopt_desde = this.Trafos.IdVarOptPCDesde(n_trafo, 1);
                indice_varopt_hasta = this.Trafos.IdVarOptPCDesde(n_trafo, this.iCantContingenciasGenCons) + cant_po - 1;
                % se elimina balance de energía n-1. Se verifica eso sí que no
                % haya ningún elemento conectado aún
                id_restriccion_desde = this.Trafos.IdRestriccionEFlujosAngulosPCDesde(n_trafo, 1);
                id_restriccion_hasta = this.Trafos.IdRestriccionEFlujosAngulosPCDesde(n_trafo, this.iCantContingenciasGenCons) + cant_po - 1;

                % elimina restriccion
                this.Aeq(id_restriccion_desde:id_restriccion_hasta,:) = [];
                this.beq(id_restriccion_desde:id_restriccion_hasta) = [];
                this.iIndiceEq = this.iIndiceEq - cant_po;

                if ~isempty(this.NombreEq)
                    this.NombreEq(id_restriccion_desde:id_restriccion_hasta) = [];
                end

                this.actualiza_indices_restriccion_igualdad(id_restriccion_desde, this.iCantContingenciasGenCons);

                % elimina variable de contenedores
                this.Fobj(indice_varopt_desde:indice_varopt_hasta) = [];
                this.lb(indice_varopt_desde:indice_varopt_hasta) = [];
                this.ub(indice_varopt_desde:indice_varopt_hasta) = [];
                if ~isempty(this.NombreVariables)
                    this.NombreVariables(indice_varopt_desde:indice_varopt_hasta) = [];
                end
                this.Aeq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                if ~isempty(this.Aineq)
                    this.Aineq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                end

                this.actualiza_indice_variables(indice_varopt_desde, this.iCantContingenciasGenCons);

                this.iIndiceVarOpt = this.iIndiceVarOpt - cant_po*this.iCantContingenciasGenCons;
                
                % borra trafo de indice de restricciones de igualdad y actualiza índices 
                this.Trafos.IdRestriccionEFlujosAngulosPCDesde(n_trafo,:) = [];
                
                % borra trafo de indice de variables de optimización y actualiza índices
                this.Trafos.IdVarOptPCDesde(n_trafo,:) = [];
            end
            
            % se borra la variable de los contenedores
            this.Trafos.ElRed(n_trafo) = [];
            this.Trafos.FlagObservacion(n_trafo) = [];
            this.Trafos.Pmax(n_trafo) = [];
            this.Trafos.n = this.Trafos.n - 1;
        end

        function elimina_bateria(this, variable)
            cant_po = this.iCantPuntosOperacion;
            n_bat = variable.entrega_id();
            
            % primero variables de potencia
            % Importante: indices de carga van directamente después de indices de descarga!
            indice_varopt_desde = this.Baterias.IdVarOptDesdeDescarga(n_bat);
            indice_varopt_hasta = this.Baterias.IdVarOptDesdeCarga(n_bat) + cant_po - 1;
            
            % elimina variable de contenedores
            this.Fobj(indice_varopt_desde:indice_varopt_hasta) = [];
            this.lb(indice_varopt_desde:indice_varopt_hasta) = [];
            this.ub(indice_varopt_desde:indice_varopt_hasta) = [];
            if ~isempty(this.NombreVariables)
                this.NombreVariables(indice_varopt_desde:indice_varopt_hasta) = [];
            end
            this.Aeq(:,indice_varopt_desde:indice_varopt_hasta) = [];
            if ~isempty(this.Aineq)
                this.Aineq(:,indice_varopt_desde:indice_varopt_hasta) = [];
            end

            % borra bateria de indice de variables de optimización y actualiza índices
            this.Baterias.IdVarOptDesdeDescarga(n_bat) = [];
            this.Baterias.IdVarOptDesdeCarga(n_bat) = [];
            this.actualiza_indice_variables(indice_varopt_desde, 2); % 2 indica que se eliminan dos veces cantidad de puntos de operación (por descarga y carga)
            
            this.iIndiceVarOpt = this.iIndiceVarOpt - 2*cant_po;
            
            % variables de energia
            if this.bConsideraDependenciaTemporal
                indice_varopt_desde = this.Baterias.IdVarOptDesdeE(n_bat);
                indice_varopt_hasta = indice_varopt_desde + cant_po - 1;

                % elimina variable de contenedores
                this.Fobj(indice_varopt_desde:indice_varopt_hasta) = [];
                this.lb(indice_varopt_desde:indice_varopt_hasta) = [];
                this.ub(indice_varopt_desde:indice_varopt_hasta) = [];
                if ~isempty(this.NombreVariables)
                    this.NombreVariables(indice_varopt_desde:indice_varopt_hasta) = [];
                end
                this.Aeq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                if ~isempty(this.Aineq)
                    this.Aineq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                end
            
                this.iIndiceVarOpt = this.iIndiceVarOpt - cant_po;

                % restricciones
                id_restriccion_desde = this.Baterias.IdRestriccionEBalanceDesde(n_bat);
                id_restriccion_hasta = id_restriccion_desde + cant_po - 1;

                % elimina restriccion
                this.Aeq(id_restriccion_desde:id_restriccion_hasta,:) = [];
                this.beq(id_restriccion_desde:id_restriccion_hasta) = [];
                this.iIndiceEq = this.iIndiceEq - cant_po;

                if ~isempty(this.NombreEq)
                    this.NombreEq(id_restriccion_desde:id_restriccion_hasta) = [];
                end
            
                % borra bateria de indice de restricciones de igualdad y actualiza índices 
                this.Baterias.IdRestriccionEBalanceDesde(n_bat) = [];
                this.actualiza_indices_restriccion_igualdad(id_restriccion_desde);

                % borra bateria de indice de variables de optimización y actualiza índices
                this.Baterias.IdVarOptDesdeE(n_bat) = [];
                this.actualiza_indice_variables(indice_varopt_desde);                
            end
            
            if this.pParOpt.ConsideraReservasMinimasSistema
                indice_varopt_desde = this.Baterias.IdVarOptResDescargaDesde(n_bat);
                indice_varopt_hasta = this.Baterias.IdVarOptResCargaDesde(n_bat) + cant_po - 1;

                % elimina variable de contenedores
                this.Fobj(indice_varopt_desde:indice_varopt_hasta) = [];
                this.lb(indice_varopt_desde:indice_varopt_hasta) = [];
                this.ub(indice_varopt_desde:indice_varopt_hasta) = [];
                if ~isempty(this.NombreVariables)
                    this.NombreVariables(indice_varopt_desde:indice_varopt_hasta) = [];
                end
                this.Aeq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                if ~isempty(this.Aineq)
                    this.Aineq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                end
            
                this.iIndiceVarOpt = this.iIndiceVarOpt - 2*cant_po;

                % restricciones                
                id_restriccion_desde = this.Baterias.IdRestriccionIResDescargaDesde(n_bat);
                id_restriccion_hasta = this.Baterias.IdRestriccionIResCargaDesde(n_bat) + cant_po - 1;

                % elimina restriccion
                this.AIneq(id_restriccion_desde:id_restriccion_hasta,:) = [];
                this.bineq(id_restriccion_desde:id_restriccion_hasta) = [];
                this.iIndiceIneq = this.iIndiceIneq - 2*cant_po;

                if ~isempty(this.NombreIneq)
                    this.NombreIneq(id_restriccion_desde:id_restriccion_hasta) = [];
                end
            
                % borra bateria de indice de restricciones de igualdad y actualiza índices 
                this.Baterias.IdRestriccionIResDescargaDesde(n_bat) = [];
                this.Baterias.IdRestriccionIResCargaDesde(n_bat) = [];
                this.actualiza_indices_restriccion_desigualdad(id_restriccion_desde, 2);

                % borra bateria de indice de variables de optimización y actualiza índices
                this.Baterias.IdVarOptResDescargaDesde(n_bat) = [];
                this.Baterias.IdVarOptResCargaDesde(n_bat) = [];
                this.actualiza_indice_variables(indice_varopt_desde,2);                
                
                if this.bConsideraDependenciaTemporal
					id_restriccion_desde = this.Baterias.IdRestriccionIResBalanceDescargaDesde(n_bat);
					id_restriccion_hasta = this.Baterias.IdRestriccionIResBalanceCargaDesde(n_bat) + cant_po - 1;

                    % elimina restriccion
                    this.AIneq(id_restriccion_desde:id_restriccion_hasta,:) = [];
                    this.bineq(id_restriccion_desde:id_restriccion_hasta) = [];
                    this.iIndiceIneq = this.iIndiceIneq - 2*cant_po;

                    if ~isempty(this.NombreIneq)
                        this.NombreIneq(id_restriccion_desde:id_restriccion_hasta) = [];
                    end

                    % borra bateria de indice de restricciones de igualdad y actualiza índices 
                    this.Baterias.IdRestriccionIResBalanceDescargaDesde(n_bat) = [];
                    this.Baterias.IdRestriccionIResBalanceCargaDesde(n_bat) = [];
                    this.actualiza_indices_restriccion_desigualdad(id_restriccion_desde, 2);
                end
            end
            
            if this.pParOpt.ConsideraEstadoPostContingencia
                indice_varopt_desde = this.Baterias.IdVarOptPCResDescargaDesde(n_bat,1);
                indice_varopt_hasta = this.Baterias.IdVarOptPCResCargaDesde(n_bat, this.iCantContingenciasGenCons) + cant_po -1;

                % elimina variable de contenedores
                this.Fobj(indice_varopt_desde:indice_varopt_hasta) = [];
                this.lb(indice_varopt_desde:indice_varopt_hasta) = [];
                this.ub(indice_varopt_desde:indice_varopt_hasta) = [];
                if ~isempty(this.NombreVariables)
                    this.NombreVariables(indice_varopt_desde:indice_varopt_hasta) = [];
                end
                this.Aeq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                if ~isempty(this.Aineq)
                    this.Aineq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                end
            
                this.iIndiceVarOpt = this.iIndiceVarOpt - 2*cant_po*this.iCantContingenciasGenCons;

                % restricciones                
                id_restriccion_desde = this.Baterias.IdRestriccionIPCResDescargaDesde(n_bat,1);
                id_restriccion_hasta = this.Baterias.IdRestriccionIPCResCargaDesde(n_bat,this.iCantContingenciasGenCons) + cant_po - 1;

                % elimina restriccion
                this.AIneq(id_restriccion_desde:id_restriccion_hasta,:) = [];
                this.bineq(id_restriccion_desde:id_restriccion_hasta) = [];
                this.iIndiceIneq = this.iIndiceIneq - 2*cant_po*this.iCantContingenciasGenCons;

                if ~isempty(this.NombreIneq)
                    this.NombreIneq(id_restriccion_desde:id_restriccion_hasta) = [];
                end
            
                % borra bateria de indice de restricciones de igualdad y actualiza índices 
                this.Baterias.IdRestriccionIPCResDescargaDesde(n_bat,:) = [];
                this.Baterias.IdRestriccionIPCResCargaDesde(n_bat,:) = [];
                this.actualiza_indices_restriccion_desigualdad(id_restriccion_desde, 2*this.iCantContingenciasGenCons);

                % borra bateria de indice de variables de optimización y actualiza índices
                this.Baterias.IdVarOptPCResDescargaDesde(n_bat,:) = [];
                this.Baterias.IdVarOptPCResCargaDesde(n_bat,:) = [];
                
                this.actualiza_indice_variables(indice_varopt_desde,2*this.iCantContingenciasGenCons);
                
                if this.bConsideraDependenciaTemporal
					id_restriccion_desde = this.Baterias.IdRestriccionIPCResBalanceDescargaDesde(n_bat,1);
					id_restriccion_hasta = this.Baterias.IdRestriccionIPCResBalanceCargaDesde(n_bat,this.iCantContingenciasGenCons) + cant_po - 1;

                    % elimina restriccion
                    this.AIneq(id_restriccion_desde:id_restriccion_hasta,:) = [];
                    this.bineq(id_restriccion_desde:id_restriccion_hasta) = [];
                    this.iIndiceIneq = this.iIndiceIneq - 2*cant_po*this.iCantContingenciasGenCons;

                    if ~isempty(this.NombreIneq)
                        this.NombreIneq(id_restriccion_desde:id_restriccion_hasta) = [];
                    end

                    % borra bateria de indice de restricciones de igualdad y actualiza índices 
                    this.Baterias.IdRestriccionIPCResBalanceDescargaDesde(n_bat,:) = [];
                    this.Baterias.IdRestriccionIPCResBalanceCargaDesde(n_bat,:) = [];
                    this.actualiza_indices_restriccion_desigualdad(id_restriccion_desde, 2*this.iCantContingenciasGenCons);
                end
            end
            
            % se borra la variable de los contenedores
            this.Baterias.ElRed(n_bat) = [];
            this.Baterias.n = this.Baterias.n - 1;
        end

        function elimina_generador(this, variable)
            cant_po = this.iCantPuntosOperacion;
            dec_redondeo= this.pParOpt.DecimalesRedondeo;
            
            n_gen = variable.entrega_id();
            
            % primero variables de potencia
            % Importante: indices de carga van directamente después de indices de descarga!
            indice_varopt_p_desde = this.Generadores.IdVarOptDesde(n_gen);
            indice_varopt_p_hasta = indice_varopt_p_desde + cant_po - 1;
            
            % elimina variable de contenedores
            this.Fobj(indice_varopt_p_desde:indice_varopt_p_hasta) = [];
            this.lb(indice_varopt_p_desde:indice_varopt_p_hasta) = [];
            this.ub(indice_varopt_p_desde:indice_varopt_p_hasta) = [];
            if ~isempty(this.NombreVariables)
                this.NombreVariables(indice_varopt_p_desde:indice_varopt_p_hasta) = [];
            end
            this.Aeq(:,indice_varopt_p_desde:indice_varopt_p_hasta) = [];
            if ~isempty(this.Aineq)
                this.Aineq(:,indice_varopt_p_desde:indice_varopt_p_hasta) = [];
            end

            if ~variable.Despachable
                if ~isempty(this.pAdmSc)
                    id_adm_sc = variable.entrega_indice_adm_escenario_perfil_ernc();
                    this.Generadores.IdAdmEscenarioPerfil(n_gen) = id_adm_sc;
                    pmax = round(this.Generadores.Pmax(n_gen)*this.pAdmSc.entrega_perfil_ernc(id_adm_sc),dec_redondeo);                                        
                else % datos locales
                    pmax = round(variable.entrega_p_const_nom_opf(), dec_redondeo);
                end
                % resta inyección ERNC de beq
                id_se = variable.entrega_se().entrega_id();
                indice_eq_desde = this.Subestaciones.IdRestriccionEBalanceDesde(id_se);
                indice_eq_hasta = indice_eq_desde + cant_po - 1;
                
                this.beq(indice_eq_desde:indice_eq_hasta) = this.beq(indice_eq_desde:indice_eq_hasta) + pmax';
            end
            
            % borra generador de indice de variables de optimización y actualiza índices
            this.Generadores.IdVarOptDesde(n_gen) = [];
            this.actualiza_indice_variables(indice_varopt_p_desde);
            
            this.iIndiceVarOpt = this.iIndiceVarOpt - cant_po;

            if this.pParOpt.DeterminaUC
                if variable.Despachable && variable.entrega_pmin() > 0
                    
                    indice_varopt_desde = this.Generadores.IdVarOptUCDesde(n_gen);
                    indice_varopt_hasta = this.Generadores.IdVarOptCostoPartidaDesde(n_gen) + cant_po - 1;

                    % elimina variable de contenedores
                    this.Fobj(indice_varopt_desde:indice_varopt_hasta) = [];
                    this.lb(indice_varopt_desde:indice_varopt_hasta) = [];
                    this.ub(indice_varopt_desde:indice_varopt_hasta) = [];
                    if ~isempty(this.NombreVariables)
                        this.NombreVariables(indice_varopt_desde:indice_varopt_hasta) = [];
                    end
                    this.Aeq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                    if ~isempty(this.Aineq)
                        this.Aineq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                    end

                    this.iIndiceVarOpt = this.iIndiceVarOpt - 2*cant_po;

                    % restricciones
                    id_restriccion_desde = this.Generadores.IdRestriccionIPotenciasUCDesde(n_gen);
                    id_restriccion_hasta = this.Generadores.IdRestriccionICostoPartidaDesde(n_gen) + cant_po - 1;
                    factor = 2;
                    if this.Generadores.TiempoMinimoOperacion(n_gen) > 1
                        id_restriccion_hasta = this.Generadores.IdRestriccionITMinOperacionDesdeHasta(n_gen,2) + cant_po - 1;
                        factor = factor + 1;
                    end
                    if this.Generadores.TiempoMinimoDetencion(n_gen) > 1
                        id_restriccion_hasta = this.Generadores.IdRestriccionITMinDetencionDesdeHasta(n_gen,2) + cant_po - 1;
                        factor = factor + 1;
                    end
                    
                    % elimina restriccion
                    this.Aeq(id_restriccion_desde:id_restriccion_hasta,:) = [];
                    this.beq(id_restriccion_desde:id_restriccion_hasta) = [];
                    this.iIndiceEq = this.iIndiceEq - cant_po;

                    if ~isempty(this.NombreEq)
                        this.NombreEq(id_restriccion_desde:id_restriccion_hasta) = [];
                    end
            
                    this.actualiza_indices_restriccion_desigualdad(id_restriccion_desde, factor);
                    this.actualiza_indice_variables(indice_varopt_desde,2);
                end
                % borra contenedores
                this.Generadores.IdVarOptUCDesde(n_gen) = [];
                this.Generadores.IdVarOptCostoPartidaDesde(n_gen) = [];
                this.Generadores.IdRestriccionIPotenciasUCDesde(n_gen) = [];
                this.Generadores.IdRestriccionICostoPartidaDesde(n_gen) = [];
                this.Generadores.IdRestriccionITMinOperacionDesdeHasta(n_gen,:) = [];
                this.Generadores.IdRestriccionITMinDetencionDesdeHasta(n_gen,:) = [];
                this.Generadores.TiempoMinimoOperacion(n_gen) = [];                
                this.Generadores.TiempoMinimoDetencion(n_gen) = [];
            end
            
            if this.pParOpt.ConsideraReservasMinimasSistema
                if variable.Despachable && variable.entrega_reservas()
                    indice_varopt_desde = this.Generadores.IdVarOptResPosDesde(n_gen);
                    indice_varopt_hasta = this.Generadores.IdVarOptResNegDesde(n_gen) +  cant_po - 1;

                    % elimina variable de contenedores
                    this.Fobj(indice_varopt_desde:indice_varopt_hasta) = [];
                    this.lb(indice_varopt_desde:indice_varopt_hasta) = [];
                    this.ub(indice_varopt_desde:indice_varopt_hasta) = [];
                    if ~isempty(this.NombreVariables)
                        this.NombreVariables(indice_varopt_desde:indice_varopt_hasta) = [];
                    end
                    this.Aeq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                    if ~isempty(this.Aineq)
                        this.Aineq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                    end

                    this.iIndiceVarOpt = this.iIndiceVarOpt - 2*cant_po;

                    % restricciones
                    id_restriccion_desde = this.Generadores.IdRestriccionIResPosDesde(n_gen);
                    id_restriccion_hasta = this.Generadores.IdRestriccionIResNegDesde(n_gen) + cant_po - 1;

                    % elimina restriccion
                    this.AIneq(id_restriccion_desde:id_restriccion_hasta,:) = [];
                    this.bineq(id_restriccion_desde:id_restriccion_hasta) = [];
                    this.iIndiceIneq = this.iIndiceIneq - 2*cant_po;

                    if ~isempty(this.NombreIneq)
                        this.NombreIneq(id_restriccion_desde:id_restriccion_hasta) = [];
                    end

                    this.actualiza_indices_restriccion_desigualdad(id_restriccion_desde, 2);
                    this.actualiza_indice_variables(indice_varopt_desde,2);

                    if this.pParOpt.EstrategiaReservasMinimasSistema == 2
                        id_restriccion_desde = this.Generadores.IdRestriccionIPmaxGenDespDesde(n_gen);
                        id_restriccion_hasta = id_restriccion_desde + cant_po - 1;

                        % elimina restriccion
                        this.AIneq(id_restriccion_desde:id_restriccion_hasta,:) = [];
                        this.bineq(id_restriccion_desde:id_restriccion_hasta) = [];
                        this.iIndiceIneq = this.iIndiceIneq - cant_po;

                        if ~isempty(this.NombreIneq)
                            this.NombreIneq(id_restriccion_desde:id_restriccion_hasta) = [];
                        end

                        % borra generador de indice de restricciones de desigualdad y actualiza índices 
                        this.actualiza_indices_restriccion_desigualdad(id_restriccion_desde);
                    end
                end
                % borra cotenedores
                this.Generadores.IdVarOptResPosDesde(n_gen) = [];
                this.Generadores.IdVarOptResNegDesde(n_gen) = [];
                this.Generadores.IdRestriccionIResPosDesde(n_gen) = [];
                this.Generadores.IdRestriccionIResNegDesde(n_gen) = [];
                this.Generadores.IdRestriccionIPmaxGenDespDesde(n_gen) = [];                    
            end

            if this.pParOpt.ConsideraContingenciaN1 && ~variable.Despachable
                % resta inyeccion renovable. En caso de que generador sea
                % convencional, no hay nada que hacer ya que variable fue
                % eliminada de ecuaciones de balance de energía N-1
                id_se = variable.entrega_se().entrega_id();
                
                for cont = 1:this.iCantContingenciasElSerie
                    indice_eq_bus_desde = this.Subestaciones.IdRestriccionEBalanceN1Desde(id_se, cont);
                    indice_eq_bus_hasta = indice_eq_bus1_desde + cant_po - 1;

                    this.beq(indice_eq_bus_desde:indice_eq_bus_hasta) = ...
                        this.beq(indice_eq_bus_desde:indice_eq_bus_hasta) + pmax;
                end
            end
            
            if this.pParOpt.ConsideraEstadoPostContingencia
                if variable.Despachable
                    indice_varopt_desde = this.Generadores.IdVarOptPCResPosDesde(n_gen,1);
                    indice_varopt_hasta = this.Generadores.IdVarOptPCResNegDesde(n_gen, this.iCantContingenciasGenCons) + cant_po -1;

                    % elimina variable de contenedores
                    this.Fobj(indice_varopt_desde:indice_varopt_hasta) = [];
                    this.lb(indice_varopt_desde:indice_varopt_hasta) = [];
                    this.ub(indice_varopt_desde:indice_varopt_hasta) = [];
                    if ~isempty(this.NombreVariables)
                        this.NombreVariables(indice_varopt_desde:indice_varopt_hasta) = [];
                    end
                    this.Aeq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                    if ~isempty(this.Aineq)
                        this.Aineq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                    end

                    this.iIndiceVarOpt = this.iIndiceVarOpt - 2*cant_po*this.iCantContingenciasGenCons;

                    % restricciones                
                    id_restriccion_desde = this.Generadores.IdRestriccionIPCResPosDesde(n_gen,1);
                    id_restriccion_hasta = this.Generadores.IdRestriccionIPCResNegDesde(n_gen,this.iCantContingenciasGenCons) + cant_po - 1;

                    % elimina restriccion
                    this.AIneq(id_restriccion_desde:id_restriccion_hasta,:) = [];
                    this.bineq(id_restriccion_desde:id_restriccion_hasta) = [];
                    this.iIndiceIneq = this.iIndiceIneq - 2*cant_po*this.iCantContingenciasGenCons;

                    if ~isempty(this.NombreIneq)
                        this.NombreIneq(id_restriccion_desde:id_restriccion_hasta) = [];
                    end
            
                    this.actualiza_indices_restriccion_desigualdad(id_restriccion_desde, 2*this.iCantContingenciasGenCons);
                    this.actualiza_indice_variables(indice_varopt_desde,2*this.iCantContingenciasGenCons);
                else
                    indice_varopt_desde = this.Generadores.IdVarOptPCResNegDesde(n_gen,1);
                    indice_varopt_hasta = this.Generadores.IdVarOptPCResNegDesde(n_gen, this.iCantContingenciasGenCons) + cant_po -1;                    

                    % elimina variable de contenedores
                    this.Fobj(indice_varopt_desde:indice_varopt_hasta) = [];
                    this.lb(indice_varopt_desde:indice_varopt_hasta) = [];
                    this.ub(indice_varopt_desde:indice_varopt_hasta) = [];
                    if ~isempty(this.NombreVariables)
                        this.NombreVariables(indice_varopt_desde:indice_varopt_hasta) = [];
                    end
                    this.Aeq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                    if ~isempty(this.Aineq)
                        this.Aineq(:,indice_varopt_desde:indice_varopt_hasta) = [];
                    end

                    this.iIndiceVarOpt = this.iIndiceVarOpt - cant_po*this.iCantContingenciasGenCons;

                    this.actualiza_indice_variables(indice_varopt_desde,this.iCantContingenciasGenCons);

                    % actualiza balance de energía PC
                    id_se = variable.entrega_se().entrega_id();
                    for cont = 1:this.iCantContingenciasGenCons
                        indice_eq_bus_desde = this.Subestaciones.IdRestriccionEBalancePCDesde(id_se, cont);
                        indice_eq_bus_hasta = indice_eq_bus1_desde + cant_po - 1;

                        this.beq(indice_eq_bus_desde:indice_eq_bus_hasta) = ...
                            this.beq(indice_eq_bus_desde:indice_eq_bus_hasta) + pmax;
                    end
                end
                % borra contenedores
                this.Generadores.IdVarOptPCResPosDesde(n_gen,:) = [];
                this.Generadores.IdVarOptPCResNegDesde(n_gen,:) = [];
                this.Generadores.IdRestriccionIPCResPosDesde(n_gen,:) = [];
                this.Generadores.IdRestriccionIPCResNegDesde(n_gen,:) = [];
            end
            
            % se borra la variable de los contenedores base
            this.Generadores.ElRed(n_gen) = [];
            this.Generadores.n = this.Generadores.n - 1;
            this.Generadores.Despachable(n_gen) = [];
            this.Generadores.IdAdmEscenarioCapacidad(n_gen) = [];
            this.Generadores.IdAdmEscenarioPerfil(n_gen) = [];
            this.Generadores.Pmax(n_gen) = [];
            this.Generadores.Pmin(n_gen) = [];
            if this.pParOpt.ConsideraReservasMinimasSistema || this.pParOpt.ConsideraEstadoPostContingencia
                this.Generadores.EntreganReservas(n_gen) = [];
            end
        end
        
        function actualiza_indices_restriccion_igualdad(this, id_restriccion_desde, varargin)
            % varargin indica la cantidad de veces que se repite la
            % restricción (por ejemplo, caso N-1 se repite por la cantidad
            % de contingencias de elementos en serie consideradas
            cant_po = this.iCantPuntosOperacion;
            if nargin > 2
                factor = varargin{1};
                cant_po = cant_po*factor;
            end
            
            % Subestaciones            
            this.Subestaciones.IdRestriccionEBalanceDesde(this.Subestaciones.IdRestriccionEBalanceDesde > id_restriccion_desde) = ...
                this.Subestaciones.IdRestriccionEBalanceDesde(this.Subestaciones.IdRestriccionEBalanceDesde > id_restriccion_desde)- cant_po;
            
            % Lineas
            this.Lineas.IdRestriccionEFlujosAngulosDesde(this.Lineas.IdRestriccionEFlujosAngulosDesde > id_restriccion_desde) = ...
                this.Lineas.IdRestriccionEFlujosAngulosDesde(this.Lineas.IdRestriccionEFlujosAngulosDesde > id_restriccion_desde) - cant_po;
            
            % Trafos
            this.Trafos.IdRestriccionEFlujosAngulosDesde(this.Trafos.IdRestriccionEFlujosAngulosDesde > id_restriccion_desde) = ...
                this.Trafos.IdRestriccionEFlujosAngulosDesde(this.Trafos.IdRestriccionEFlujosAngulosDesde > id_restriccion_desde) - cant_po;
            
            % Baterias y embalses (cuando hay dependencia temporal)
            if this.bConsideraDependenciaTemporal
                this.Baterias.IdRestriccionEBalanceDesde(this.Baterias.IdRestriccionEBalanceDesde > id_restriccion_desde) = ...
                    this.Baterias.IdRestriccionEBalanceDesde(this.Baterias.IdRestriccionEBalanceDesde > id_restriccion_desde) - cant_po;

                this.Embalses.IdRestriccionEBalanceDesde(this.Embalses.IdRestriccionEBalanceDesde > id_restriccion_desde) = ...
                    this.Embalses.IdRestriccionEBalanceDesde(this.Embalses.IdRestriccionEBalanceDesde > id_restriccion_desde) - cant_po;

                this.Embalses.IdRestriccionEFiltracionDesde(this.Embalses.IdRestriccionEFiltracionDesde> id_restriccion_desde) = ...
                    this.Embalses.IdRestriccionEFiltracionDesde(this.Embalses.IdRestriccionEFiltracionDesde > id_restriccion_desde) - cant_po;
            end
                        
            if this.pParOpt.ConsideraContingenciaN1
                this.Subestaciones.IdRestriccionEBalanceN1Desde(this.Subestaciones.IdRestriccionEBalanceN1Desde > id_restriccion_desde) = ...
                    this.Subestaciones.IdRestriccionEBalanceN1Desde(this.Subestaciones.IdRestriccionEBalanceN1Desde > id_restriccion_desde)- cant_po;

                % Lineas
                this.Lineas.IdRestriccionEFlujosAngulosN1Desde(this.Lineas.IdRestriccionEFlujosAngulosN1Desde > id_restriccion_desde) = ...
                    this.Lineas.IdRestriccionEFlujosAngulosN1Desde(this.Lineas.IdRestriccionEFlujosAngulosN1Desde > id_restriccion_desde) - cant_po;

                % Trafos
                this.Trafos.IdRestriccionEFlujosAngulosN1Desde(this.Trafos.IdRestriccionEFlujosAngulosN1Desde > id_restriccion_desde) = ...
                    this.Trafos.IdRestriccionEFlujosAngulosN1Desde(this.Trafos.IdRestriccionEFlujosAngulosN1Desde > id_restriccion_desde) - cant_po;
            end
            
            if this.pParOpt.ConsideraEstadoPostContingencia
                this.Subestaciones.IdRestriccionEBalancePCDesde(this.Subestaciones.IdRestriccionEBalancePCDesde > id_restriccion_desde) = ...
                    this.Subestaciones.IdRestriccionEBalancePCDesde(this.Subestaciones.IdRestriccionEBalancePCDesde > id_restriccion_desde)- cant_po;

                % Lineas
                this.Lineas.IdRestriccionEFlujosAngulosPCDesde(this.Lineas.IdRestriccionEFlujosAngulosPCDesde > id_restriccion_desde) = ...
                    this.Lineas.IdRestriccionEFlujosAngulosPCDesde(this.Lineas.IdRestriccionEFlujosAngulosPCDesde > id_restriccion_desde) - cant_po;

                % Trafos
                this.Trafos.IdRestriccionEFlujosAngulosPCDesde(this.Trafos.IdRestriccionEFlujosAngulosPCDesde > id_restriccion_desde) = ...
                    this.Trafos.IdRestriccionEFlujosAngulosPCDesde(this.Trafos.IdRestriccionEFlujosAngulosPCDesde > id_restriccion_desde) - cant_po;
            end
        end

        function actualiza_indices_restriccion_desigualdad(this, id_restriccion_desde, varargin)
            % varargin indica la cantidad de veces que se repite la
            % restricción (por ejemplo, caso N-1 se repite por la cantidad
            % de contingencias de elementos en serie consideradas
            cant_po = this.iCantPuntosOperacion;
            if nargin > 2
                factor = varargin{1};
                cant_po = cant_po*factor;
            end

            if this.IdRestriccionIResPosDesde > id_restriccion_desde
                this.IdRestriccionIResPosDesde = this.IdRestriccionIResPosDesde - cant_po;
                this.IdRestriccionIResNegDesde = this.IdRestriccionIResNegDesde - cant_po; % IdRestriccionIResNegDesde siempre definida después de IdRestriccionIResPosDesde
            end
            
            if this.pParOpt.ConsideraReservasMinimasSistema
                this.Generadores.IdRestriccionIResPosDesde(this.Generadores.IdRestriccionIResPosDesde > id_restriccion_desde) = ...
                    this.Generadores.IdRestriccionIResPosDesde(this.Generadores.IdRestriccionIResPosDesde > id_restriccion_desde) - cant_po;
                
                this.Generadores.IdRestriccionIResNegDesde(this.Generadores.IdRestriccionIResNegDesde > id_restriccion_desde) = ...
                    this.Generadores.IdRestriccionIResNegDesde(this.Generadores.IdRestriccionIResNegDesde > id_restriccion_desde) - cant_po;
				
                if this.pParOpt.EstrategiaReservasMinimasSistema == 2
                    this.Generadores.IdRestriccionIPmaxGenDespDesde(this.Generadores.IdRestriccionIPmaxGenDespDesde > id_restriccion_desde) = ...
                        this.Generadores.IdRestriccionIPmaxGenDespDesde(this.Generadores.IdRestriccionIPmaxGenDespDesde > id_restriccion_desde) - cant_po;
                end

                this.Baterias.IdRestriccionIResDescargaDesde(this.Baterias.IdRestriccionIResDescargaDesde > id_restriccion_desde) = ...
                    this.Baterias.IdRestriccionIResDescargaDesde(this.Baterias.IdRestriccionIResDescargaDesde > id_restriccion_desde) - cant_po;
				
                this.Baterias.IdRestriccionIResCargaDesde(this.Baterias.IdRestriccionIResCargaDesde > id_restriccion_desde) = ...
                    this.Baterias.IdRestriccionIResCargaDesde(this.Baterias.IdRestriccionIResCargaDesde > id_restriccion_desde) - cant_po;

                if this.bConsideraDependenciaTemporal
                    this.Baterias.IdRestriccionIResBalanceDescargaDesde(this.Baterias.IdRestriccionIResBalanceDescargaDesde > id_restriccion_desde) = ...
                        this.Baterias.IdRestriccionIResBalanceDescargaDesde(this.Baterias.IdRestriccionIResBalanceDescargaDesde > id_restriccion_desde) - cant_po;
					
                    this.Baterias.IdRestriccionIResBalanceCargaDesde(this.Baterias.IdRestriccionIResBalanceCargaDesde > id_restriccion_desde) = ...
                        this.Baterias.IdRestriccionIResBalanceCargaDesde(this.Baterias.IdRestriccionIResBalanceCargaDesde > id_restriccion_desde) - cant_po;
                end
            end
			
            if this.pParOpt.DeterminaUC
                this.Generadores.IdRestriccionIPotenciasUCDesde(this.Generadores.IdRestriccionIPotenciasUCDesde > id_restriccion_desde) = ...
                    this.Generadores.IdRestriccionIPotenciasUCDesde(this.Generadores.IdRestriccionIPotenciasUCDesde > id_restriccion_desde) - cant_po;

                this.Generadores.IdRestriccionICostoPartidaDesde(this.Generadores.IdRestriccionICostoPartidaDesde > id_restriccion_desde) = ...
                    this.Generadores.IdRestriccionICostoPartidaDesde(this.Generadores.IdRestriccionICostoPartidaDesde > id_restriccion_desde) - cant_po;

                this.Generadores.IdRestriccionITMinOperacionDesdeHasta(this.Generadores.IdRestriccionITMinOperacionDesdeHasta > id_restriccion_desde) = ...
                    this.Generadores.IdRestriccionITMinOperacionDesdeHasta(this.Generadores.IdRestriccionITMinOperacionDesdeHasta > id_restriccion_desde) - cant_po;

                this.Generadores.IdRestriccionITMinDetencionDesdeHasta(this.Generadores.IdRestriccionITMinDetencionDesdeHasta > id_restriccion_desde) = ...
                    this.Generadores.IdRestriccionITMinDetencionDesdeHasta(this.Generadores.IdRestriccionITMinDetencionDesdeHasta > id_restriccion_desde) - cant_po;
            end
            
            if this.pParOpt.ConsideraEstadoPostContingencia
                this.Generadores.IdRestriccionIPCResPosDesde(this.Generadores.IdRestriccionIPCResPosDesde > id_restriccion_desde) = ...
                    this.Generadores.IdRestriccionIPCResPosDesde(this.Generadores.IdRestriccionIPCResPosDesde > id_restriccion_desde) - cant_po;

                this.Generadores.IdRestriccionIPCResNegDesde(this.Generadores.IdRestriccionIPCResNegDesde > id_restriccion_desde) = ...
                    this.Generadores.IdRestriccionIPCResNegDesde(this.Generadores.IdRestriccionIPCResNegDesde > id_restriccion_desde) - cant_po;

                this.Baterias.IdRestriccionIPCResDescargaDesde(this.Baterias.IdRestriccionIPCResDescargaDesde > id_restriccion_desde) = ...
                    this.Baterias.IdRestriccionIPCResDescargaDesde(this.Baterias.IdRestriccionIPCResDescargaDesde > id_restriccion_desde) - cant_po;

                this.Baterias.IdRestriccionIPCResCargaDesde(this.Baterias.IdRestriccionIPCResCargaDesde > id_restriccion_desde) = ...
                    this.Baterias.IdRestriccionIPCResCargaDesde(this.Baterias.IdRestriccionIPCResCargaDesde > id_restriccion_desde) - cant_po;
			
                if this.bConsideraDependenciaTemporal
                    this.Baterias.IdRestriccionIPCResBalanceDescargaDesde(this.Baterias.IdRestriccionIPCResBalanceDescargaDesde > id_restriccion_desde) = ...
                        this.Baterias.IdRestriccionIPCResBalanceDescargaDesde(this.Baterias.IdRestriccionIPCResBalanceDescargaDesde > id_restriccion_desde) - cant_po;

                    this.Baterias.IdRestriccionIPCResBalanceCargaDesde(this.Baterias.IdRestriccionIPCResBalanceCargaDesde > id_restriccion_desde) = ...
                        this.Baterias.IdRestriccionIPCResBalanceCargaDesde(this.Baterias.IdRestriccionIPCResBalanceCargaDesde > id_restriccion_desde) - cant_po;
                end
            end            
        end
        
        function actualiza_indice_variables(this, indice_varopt_operacion_desde, varargin)
            % varargin indica la cantidad de puntos de operación que se
            % repiten. Por ejemplo, en caso de contingencia N-1, se repite
            % la cantidad de contingencias de elementos en serie
            % consideradas
            cant_po = this.iCantPuntosOperacion;
            if nargin > 2
                cant_po = varargin{1}*cant_po;
            end
            
            % generadores
            this.Generadores.IdVarOptDesde(this.Generadores.IdVarOptDesde > indice_varopt_operacion_desde) = ...
                this.Generadores.IdVarOptDesde(this.Generadores.IdVarOptDesde > indice_varopt_operacion_desde) - cant_po;
                        
            % consumos
            this.Consumos.IdVarOptDesde(this.Consumos.IdVarOptDesde > indice_varopt_operacion_desde) = ...
                this.Consumos.IdVarOptDesde(this.Consumos.IdVarOptDesde > indice_varopt_operacion_desde) - cant_po;
            
            % Subestaciones            
            this.Subestaciones.IdVarOptDesde(this.Subestaciones.IdVarOptDesde > indice_varopt_operacion_desde) = ...
                this.Subestaciones.IdVarOptDesde(this.Subestaciones.IdVarOptDesde > indice_varopt_operacion_desde)- cant_po;
            
            % Lineas
            this.Lineas.IdVarOptDesde(this.Lineas.IdVarOptDesde > indice_varopt_operacion_desde) = ...
                this.Lineas.IdVarOptDesde(this.Lineas.IdVarOptDesde > indice_varopt_operacion_desde) - cant_po;
            
            % Trafos
            this.Trafos.IdVarOptDesde(this.Trafos.IdVarOptDesde > indice_varopt_operacion_desde) = ...
                this.Trafos.IdVarOptDesde(this.Trafos.IdVarOptDesde > indice_varopt_operacion_desde) - cant_po;
            
            % Baterias
            this.Baterias.IdVarOptDesdeDescarga(this.Baterias.IdVarOptDesdeDescarga> indice_varopt_operacion_desde) = ...
                this.Baterias.IdVarOptDesdeDescarga(this.Baterias.IdVarOptDesdeDescarga > indice_varopt_operacion_desde) - cant_po;

            this.Baterias.IdVarOptDesdeCarga(this.Baterias.IdVarOptDesdeCarga> indice_varopt_operacion_desde) = ...
                this.Baterias.IdVarOptDesdeCarga(this.Baterias.IdVarOptDesdeCarga> indice_varopt_operacion_desde) - cant_po;
            
            % Embalses
            this.Embalses.IdVarOptDesde(this.Embalses.IdVarOptDesde > indice_varopt_operacion_desde) = ...
                this.Embalses.IdVarOptDesde(this.Embalses.IdVarOptDesde > indice_varopt_operacion_desde) - cant_po;

            % Baterías y embalses cuando hay dependencia temporal
            if this.bConsideraDependenciaTemporal
                this.Baterias.IdVarOptDesdeE(this.Baterias.IdVarOptDesdeE > indice_varopt_operacion_desde) = ...
                    this.Baterias.IdVarOptDesdeE(this.Baterias.IdVarOptDesdeE > indice_varopt_operacion_desde) - cant_po;
                
                this.Embalses.IdVarOptVertimientoDesde(this.Embalses.IdVarOptVertimientoDesde > indice_varopt_operacion_desde) = ...
                    this.Embalses.IdVarOptVertimientoDesde(this.Embalses.IdVarOptVertimientoDesde > indice_varopt_operacion_desde) - cant_po;

                this.Embalses.IdVarOptFiltracionDesde(this.Embalses.IdVarOptFiltracionDesde > indice_varopt_operacion_desde) = ...
                    this.Embalses.IdVarOptFiltracionDesde(this.Embalses.IdVarOptFiltracionDesde > indice_varopt_operacion_desde) - cant_po;
            end
            
            if this.pParOpt.ConsideraReservasMinimasSistema
                this.Generadores.IdVarOptResPosDesde(this.Generadores.IdVarOptResPosDesde > indice_varopt_operacion_desde) = ...
                    this.Generadores.IdVarOptResPosDesde(this.Generadores.IdVarOptResPosDesde > indice_varopt_operacion_desde) - cant_po;
                
                this.Generadores.IdVarOptResNegDesde(this.Generadores.IdVarOptResNegDesde > indice_varopt_operacion_desde) = ...
                    this.Generadores.IdVarOptResNegDesde(this.Generadores.IdVarOptResNegDesde > indice_varopt_operacion_desde) - cant_po;
                
                this.Baterias.IdVarOptResDescargaDesde(this.Baterias.IdVarOptResDescargaDesde > indice_varopt_operacion_desde) = ...
                    this.Baterias.IdVarOptResDescargaDesde(this.Baterias.IdVarOptResDescargaDesde > indice_varopt_operacion_desde) - cant_po;

                this.Baterias.IdVarOptResCargaDesde(this.Baterias.IdVarOptResCargaDesde > indice_varopt_operacion_desde) = ...
                    this.Baterias.IdVarOptResCargaDesde(this.Baterias.IdVarOptResCargaDesde > indice_varopt_operacion_desde) - cant_po;
                
                % siguiente varibale es sistémica y se define al comienzo, por lo que no es necesario actualizarla
                %if this.pParOpt.EstrategiaReservasMinimasSistema == 2
                %   if this.IdVarOptPmaxGenDespDesde >  indice_varopt_operacion_desde
                %       this.IdVarOptPmaxGenDespDesde = this.IdVarOptPmaxGenDespDesde - cant_po;
                %   end
                %end
            end
            
            if this.pParOpt.DeterminaUC
                this.Generadores.IdVarOptUCDesde(this.Generadores.IdVarOptUCDesde > indice_varopt_operacion_desde) = ...
                    this.Generadores.IdVarOptUCDesde(this.Generadores.IdVarOptUCDesde > indice_varopt_operacion_desde) - cant_po;
                
                this.Generadores.IdVarOptCostoPartidaDesde(this.Generadores.IdVarOptCostoPartidaDesde > indice_varopt_operacion_desde) = ...
                    this.Generadores.IdVarOptCostoPartidaDesde(this.Generadores.IdVarOptCostoPartidaDesde > indice_varopt_operacion_desde) - cant_po;
            end
            
            if this.pParOpt.ConsideraContingenciaN1
                this.Subestaciones.IdVarOptN1Desde(this.Subestaciones.IdVarOptN1Desde > indice_varopt_operacion_desde) = ...
                    this.Subestaciones.IdVarOptN1Desde(this.Subestaciones.IdVarOptN1Desde > indice_varopt_operacion_desde) - cant_po;
                
                this.Lineas.IdVarOptN1Desde(this.Lineas.IdVarOptN1Desde > indice_varopt_operacion_desde) = ...
                    this.Lineas.IdVarOptN1Desde(this.Lineas.IdVarOptN1Desde > indice_varopt_operacion_desde) - cant_po;

                this.Trafos.IdVarOptN1Desde(this.Trafos.IdVarOptN1Desde > indice_varopt_operacion_desde) = ...
                    this.Trafos.IdVarOptN1Desde(this.Trafos.IdVarOptN1Desde > indice_varopt_operacion_desde) - cant_po;
            end
            
            if this.pParOpt.ConsideraEstadoPostContingencia
                this.Generadores.IdVarOptPCResPosDesde(this.Generadores.IdVarOptPCResPosDesde > indice_varopt_operacion_desde) = ...
                    this.Generadores.IdVarOptPCResPosDesde(this.Generadores.IdVarOptPCResPosDesde > indice_varopt_operacion_desde) - cant_po;

                this.Generadores.IdVarOptPCResNegDesde(this.Generadores.IdVarOptPCResNegDesde > indice_varopt_operacion_desde) = ...
                    this.Generadores.IdVarOptPCResNegDesde(this.Generadores.IdVarOptPCResNegDesde > indice_varopt_operacion_desde) - cant_po;
                
                this.Baterias.IdVarOptPCResDescargaDesde(this.Baterias.IdVarOptPCResDescargaDesde > indice_varopt_operacion_desde) = ...
                    this.Baterias.IdVarOptPCResDescargaDesde(this.Baterias.IdVarOptPCResDescargaDesde > indice_varopt_operacion_desde) - cant_po;

                this.Baterias.IdVarOptPCResCargaDesde(this.Baterias.IdVarOptPCResCargaDesde > indice_varopt_operacion_desde) = ...
                    this.Baterias.IdVarOptPCResCargaDesde(this.Baterias.IdVarOptPCResCargaDesde > indice_varopt_operacion_desde) - cant_po;

                this.Subestaciones.IdVarOptPCDesde(this.Subestaciones.IdVarOptPCDesde > indice_varopt_operacion_desde) = ...
                    this.Subestaciones.IdVarOptPCDesde(this.Subestaciones.IdVarOptPCDesde > indice_varopt_operacion_desde) - cant_po;
                
                this.Lineas.IdVarOptPCDesde(this.Lineas.IdVarOptPCDesde > indice_varopt_operacion_desde) = ...
                    this.Lineas.IdVarOptPCDesde(this.Lineas.IdVarOptPCDesde > indice_varopt_operacion_desde) - cant_po;

                this.Trafos.IdVarOptPCDesde(this.Trafos.IdVarOptPCDesde > indice_varopt_operacion_desde) = ...
                    this.Trafos.IdVarOptPCDesde(this.Trafos.IdVarOptPCDesde > indice_varopt_operacion_desde) - cant_po;

                this.Consumos.IdVarOptPCDesde(this.Consumos.IdVarOptPCDesde > indice_varopt_operacion_desde) = ...
                    this.Consumos.IdVarOptPCDesde(this.Consumos.IdVarOptPCDesde > indice_varopt_operacion_desde) - cant_po;
            end
        end
        
        function inicializa_contenedores(this)
            % se inicializan las dimensiones de las matrices.

            % 1. Variables
            % 1.1. Operación normal: cant_po por:
            %   - cant_generadores(Pgen)
            %   - 2*cant_baterias(P_carga + P_descarga)
            %   - cant_se(ángulo)
            %   - cant_lineas+cant_trafos+cant_consumos
            %   Si se considera dependencia temporal:
            %   - 2*cant_embalses(vol_embalse + vertimientos)
            %	- Cant. embalses con filtración
            %   - energía de las baterías
            n_var = this.Generadores.n + 2*this.Baterias.n + this.Subestaciones.n + this.Lineas.n + this.Trafos.n + this.Consumos.n;
            if this.bConsideraDependenciaTemporal
                cant_filt = length(find(this.Embalses.IdVarOptFiltracionDesde > 0));
                n_var = n_var + this.Baterias.n + 2*this.Embalses.n + cant_filt;
            end
            % 1.2 Si se consideran reservas mínimas sistema:
            %   - 2*cant_generadores_conv_que aportan_reservas (positivas y negativas)
            %   - 2*cant_baterias (positivas y negativas)
            if this.pParOpt.ConsideraReservasMinimasSistema
                cant_gen_res = length(find(this.Generadores.IdVarOptResPosDesde > 0));
                n_var = n_var + 2*(cant_gen_res + this.Baterias.n);
                
                if this.pParOpt.EstrategiaReservasMinimasSistema == 2
                    % variables para calcular la potencia máxima de los
                    % generadores convencionales en todas las horas
                    n_var = n_var + 1;
                end
            end
            % si se considera restricción de ROCOF:
            %   - 1 variable para calculo de la inercia por cada generador que falla y por cada PO
            if this.pParOpt.ConsideraRestriccionROCOF
                n_var = n_var + this.iCantContingenciasGenCons;
                
            end
            n_var = n_var*this.iCantPuntosOperacion;
            
            
            % 1.2. Variables de UC
            if this.pParOpt.DeterminaUC
                % UC generadores: cant_generadores_uc * cant. puntos operación
                % costo partida: cant_generadores_uc * cant. puntos operación
                cant_gen_uc = length(find(this.Generadores.IdVarOptUCDesde > 0));
                n_var = n_var + 2*this.iCantPuntosOperacion*cant_gen_uc;
            end

            % 1.3. Variables de contingencia N-1
            %  - Ángulos SE N-1: cant_se*cant_po*cant_contingencia_n1
            %  - Flujos líneas/trafos N-1: cant_lineas_trafos*cant_po*cant_contingencia_n1
            if this.pParOpt.ConsideraContingenciaN1
                n_var = n_var + this.iCantPuntosOperacion*this.iCantContingenciasElSerie*(this.Subestaciones.n + this.Lineas.n + this.Trafos.n);
            end
            
            % 1.4. Variables de estado post-contingencia
            %  - Ángulos SE PC: cant_se*cant_po*cant_contingencias_gen_cons
            %  - Flujos líneas/trafos PC: cant_lineas_trafos*cant_po*cant_contingencias_cons_gen
            %  - Despliegue de reservas de generadores y baterías en PC:(2*cant_generadores_con_reserva + 2*cant_baterias)*cant_po*cant_contingencia_pc
            if this.pParOpt.ConsideraEstadoPostContingencia
                can_gen_conv_reserva = sum(this.Generadores.EntreganReservas);
                cant_gen_res = sum(this.Generadores.Despachable == 0);
                n_var_adicionales = this.Subestaciones.n + this.Lineas.n + this.Trafos.n + ...
                    2*this.Baterias.n + 2*can_gen_conv_reserva + cant_gen_res;
                n_var = n_var + this.iCantPuntosOperacion*this.iCantContingenciasGenCons*n_var_adicionales;
            end

            this.Fobj = zeros(n_var, 1);
            
            % Restricciones de igualdad contiene:
            % 1.  Estado de operación normal
            % 1.1 Balance de energía por nodo y punto de operación
            %     Cantidad: #buses *#po
            % 1.2 Restricciones flujos-ángulos
            %     Cantidad: #elementos serie *#po
            % Si se consideran restricciones temporales:
            % 1.3 Restricciones temporales balance energético baterías
            % 1.4 Restricciones temporales balance hidráulico
            cantidad_eq = (this.Subestaciones.n + this.Lineas.n + this.Trafos.n)*this.iCantPuntosOperacion;            
            if this.bConsideraDependenciaTemporal
                % Eq. de balance de las baterías y filtración de los embalses
                n_var_adicionales = this.Embalses.n + this.Baterias.n + cant_filt;
                cantidad_eq = cantidad_eq + this.iCantPuntosOperacion*n_var_adicionales;
            end
            
            % 2.  Si se consideran contingencias N-1:
            % 2.1 restricciones balance energía = cant_se*cant_po*cant_contingencias
            % 2.2 restricciones flujos angulos N-1 = cant_lineas_trafos*cant_po*cant_contingencia_n1 (uno por cada línea con flujos n-1)
            if this.pParOpt.ConsideraContingenciaN1
                n_var_adicionales = this.Subestaciones.n + this.Lineas.n + this.Trafos.n;
                cantidad_eq = cantidad_eq + n_var_adicionales*this.iCantPuntosOperacion*this.iCantContingenciasElSerie;
            end

            % 3.   Si se considera restricción de ROCOF
            % 3.1. una ecuación para el cálculo de la inercia por cada generador que falla y por cada punto de operación
            if this.pParOpt.ConsideraRestriccionROCOF
                cantidad_eq = cantidad_eq + this.iCantContingenciasGenCons*this.iCantPuntosOperacion;
            end
            
            this.Aeq = sparse(cantidad_eq, n_var);
            this.beq = zeros(cantidad_eq, 1);
            if this.iNivelDebug > 0
                this.NombreEq = cell(cantidad_eq,1);
            end

            % restricciones de desigualdad
            cantidad_ineq = 0;
            if this.pParOpt.ConsideraReservasMinimasSistema
                % restricción de reservas máximas y mínimas
                cantidad_ineq = 2;

                n_gen_desp_res = sum(this.Generadores.EntreganReservas);
                cantidad_ineq = cantidad_ineq + this.iCantPuntosOperacion*(2*n_gen_desp_res + this.Baterias.n);
                if this.bConsideraDependenciaTemporal
                    % límites superior e inferior de energía de las baterías
                    cantidad_ineq = cantidad_ineq + 2*this.iCantPuntosOperacion*this.Baterias.n;
                end
                
                if this.pParOpt.EstrategiaReservasMinimasSistema == 2
                    % una restricción por cada generador convencional por cada hora para calcular la candidad de reservas necesarias en todas las horas
                    cantidad_ineq = cantidad_ineq + this.iCantPuntosOperacion*sum(this.Generadores.Despachable);
                end
            end

            if this.pParOpt.ConsideraRestriccionROCOF
                % una restricción para el ROCOF por cada generador que falla y por cada punto de operación
                cantidad_ineq = cantidad_ineq + this.iCantContingenciasGenCons*this.iCantPuntosOperacion;
            end
            
            if this.pParOpt.DeterminaUC
                % restricciones de desigualdad aparecen si se considera UC. Estas contienen:
                % 1. costo partida: cant_generadores_uc * cant. puntos operación
                % 2. Pmin/max de generadores con UC: 2*cant_generadores_uc*cant_po
                % 3. Tmin operación: cant_generadores_uc_con_tmin_oper>1* (cant_po - cant_periodos_representativos, ya que primera hora en cada periodo no se considera)
                % 4. Tmin detención: cant_generadores_uc_con_tmin_detencion>1* (cant_po - cant_periodos_representativos, ya que primera hora en cada periodo no se considera)
                
                cantidad_ineq = 3*cant_gen_uc*this.iCantPuntosOperacion;

                [cant_periodos_representativos, ~] = size(this.vIndicesPOConsecutivos);
                cant_gen_uc_con_tmin_oper = length(find(this.Generadores.TiempoMinimoOperacion > 1));
                cantidad_ineq = cantidad_ineq + cant_gen_uc_con_tmin_oper*(this.iCantPuntosOperacion - cant_periodos_representativos);

                cant_gen_uc_con_tmin_detencion = length(find(this.Generadores.TiempoMinimoDetencion > 1));
                cantidad_ineq = cantidad_ineq + cant_gen_uc_con_tmin_detencion*(this.iCantPuntosOperacion - cant_periodos_representativos);

                this.Aineq = sparse(cantidad_ineq, n_var);
                this.bineq = zeros(cantidad_ineq, 1);
            end
            
            if this.iNivelDebug > 1
                % Siguiente debug es para verificar que dimensión de los contenedores definida a priori coincide con dimensión real del problema (si es menor el programa se demora mucho en formular el problema)
                prot = cProtocolo.getInstance;
                prot.imprime_texto('Dimension de contenedores (antes de escribir las restricciones)');
                prot.imprime_texto(['Cantidad variables decision: ' num2str(n_var)]);
                prot.imprime_texto(['Cantidad rest. igualdad: ' num2str(cantidad_eq)]);
                prot.imprime_texto(['Cantidad rest. desigualdad: ' num2str(cantidad_ineq)]);
            end
        end
        
        function escribe_funcion_objetivo(this)
            % Función objetivo en millones de $
            dec_redondeo= this.pParOpt.DecimalesRedondeo;
            
            if strcmp(this.pParOpt.entrega_funcion_objetivo(), 'MinC')

                if this.pParOpt.ConsideraReservasMinimasSistema && this.pParOpt.EstrategiaReservasMinimasSistema == 2
                    % Penalización para calcular potencia generada por los
                    % generadores despachables
                    penalizacion = this.pParOpt.entrega_penalizacion()*this.Sbase;
                    indice_pmax_gen_desp_desde = this.IdVarOptPmaxGenDespDesde;
                    indice_pmax_gen_desp_hasta = indice_pmax_gen_desp_desde + this.iCantPuntosOperacion -1;
                    this.Fobj(indice_pmax_gen_desp_desde:indice_pmax_gen_desp_hasta) = round(this.vRepresentatividadPO*penalizacion/1000000,dec_redondeo);
                end
                
                % generadores despachables
                id_gen_desp = find(this.Generadores.Despachable == 1);
                for i = 1:length(id_gen_desp)
                    costos_mw = this.Generadores.ElRed(id_gen_desp(i)).entrega_costo_mwh()*this.Sbase;
                    indice_desde = this.Generadores.IdVarOptDesde(id_gen_desp(i));
                    indice_hasta = indice_desde + this.iCantPuntosOperacion -1;
                    this.Fobj(indice_desde:indice_hasta) = round(this.vRepresentatividadPO*costos_mw/1000000,dec_redondeo);

                    if this.pParOpt.DeterminaUC && this.Generadores.IdVarOptCostoPartidaDesde(id_gen_desp(i)) ~= 0
                        costo_partida = this.Generadores.ElRed(id_gen_desp(i)).entrega_costo_partida()*this.Sbase;
                        indice_desde = this.Generadores.IdVarOptCostoPartidaDesde(id_gen_desp(i));
                        indice_hasta = indice_desde + this.iCantPuntosOperacion -1;
                        this.Fobj(indice_desde:indice_hasta) = round(this.vRepresentatividadPO*costo_partida/1000000,dec_redondeo);
                    end
                    
                    if this.pParOpt.ConsideraEstadoPostContingencia && this.Generadores.IdVarOptPCResPosDesde(id_gen_desp(i)) ~= 0
                        % se asume que si el generador entrega reservas positivas, entonces también entrega reservas negativas
                        costo_reserva_pos = this.Generadores.ElRed(id_gen_desp(i)).entrega_costo_reservas_positivas()*this.Sbase;
                        indice_desde = this.Generadores.IdVarOptPCResPosDesde(id_gen_desp(i));
                        indice_hasta = indice_desde + this.iCantPuntosOperacion -1;
                        this.Fobj(indice_desde:indice_hasta) = round(this.vRepresentatividadPO*costo_reserva_pos/1000000,dec_redondeo);

                        costo_reserva_neg = this.Generadores.ElRed(id_gen_desp(i)).entrega_costo_reservas_negativas()*this.Sbase;
                        indice_desde = this.Generadores.IdVarOptPCResNegDesde(id_gen_desp(i));
                        indice_hasta = indice_desde + this.iCantPuntosOperacion -1;
                        this.Fobj(indice_desde:indice_hasta) = round(this.vRepresentatividadPO*costo_reserva_neg/1000000,dec_redondeo);
                    end
                end
                
                % generadores res
                penalizacion = this.pParOpt.entrega_penalizacion()*this.Sbase; % penalización base (no estado post-contingencia)
                id_gen_res = find(this.Generadores.Despachable == 0);
                for i = 1:length(id_gen_res)
                    indice_desde = this.Generadores.IdVarOptDesde(id_gen_res(i));
                    indice_hasta = indice_desde + this.iCantPuntosOperacion -1;
                    this.Fobj(indice_desde:indice_hasta) = round(this.vRepresentatividadPO*penalizacion/1000000,dec_redondeo);
                    
                    if this.pParOpt.ConsideraEstadoPostContingencia
                        % Todos los generadores RES deben poder disminuir su potencia de salida en caso de contingencia, con la penalización correspondiente
                        penalizacion_recorte_res = this.pParOpt.entrega_penalizacion_recorte_res()*this.Sbase;
                        indice_desde = this.Generadores.IdVarOptPCResNegDesde(id_gen_res(i));
                        indice_hasta = indice_desde + this.iCantPuntosOperacion -1;
                        this.Fobj(indice_desde:indice_hasta) = round(this.vRepresentatividadPO*penalizacion_recorte_res/1000000,dec_redondeo);
                    end
                end
                
                % consumos
                for i = 1:this.Consumos.n
                    indice_desde = this.Consumos.IdVarOptDesde(i);
                    indice_hasta = indice_desde + this.iCantPuntosOperacion -1;
                    this.Fobj(indice_desde:indice_hasta) = round(this.vRepresentatividadPO*penalizacion/1000000,dec_redondeo);
                    
                    if this.pParOpt.ConsideraEstadoPostContingencia
                        % Todos los generadores RES deben poder disminuir su potencia de salida en caso de contingencia, con la penalización correspondiente
                        penalizacion_ens = this.pParOpt.entrega_penalizacion_ens()*this.Sbase;
                        indice_desde = this.Consumos.IdVarOptPCDesde(i);
                        indice_hasta = indice_desde + this.iCantPuntosOperacion -1;
                        this.Fobj(indice_desde:indice_hasta) = round(this.vRepresentatividadPO*penalizacion_ens/1000000,dec_redondeo);
                    end                    
                end
            else
                error = MException('cOPF:escribe_funcion_objetivo','Función objetivo indicada no implementada');
                throw(error)
            end
        end
        
        function escribe_restricciones(this)
            % estado normal
            this.escribe_balance_energia(); 
            this.escribe_relaciones_flujos_angulos();

            if this.pParOpt.ConsideraReservasMinimasSistema
                this.escribe_restricciones_reservas_minimas_sistema();
                this.escribe_restricciones_reservas_generadores();
                this.escribe_restricciones_reservas_baterias();
                if this.pParOpt.EstrategiaReservasMinimasSistema == 2
                    this.escribe_restricciones_calculo_pmax_generadores();
                end
            end
            
            if this.bConsideraDependenciaTemporal
                this.escribe_balance_temporal_baterias();
                this.escribe_balance_hidrico(); 
            end

            if this.pParOpt.ConsideraRestriccionROCOF
                this.escribe_restriccion_calculo_inercia();
                this.escribe_restricciones_rocof();                
            end
            
            if this.pParOpt.DeterminaUC
                id_validos = find(this.Generadores.IdVarOptUCDesde > 0);
                for i = 1:length(id_validos)
                    this.escribe_restriccion_potencias_min_max_generadores_n0(this.Generadores.ElRed(id_validos(i)));
                    this.escribe_restriccion_costo_partida_generadores(this.Generadores.ElRed(id_validos(i)));
                    if this.Generadores.TiempoMinimoOperacion(id_validos(i)) > 1
                        this.escribe_restriccion_tiempo_minimo_operacion_generadores(this.Generadores.ElRed(id_validos(i)));
                    end
                    if this.Generadores.TiempoMinimoDetencion(id_validos(i)) > 1
                        this.escribe_restriccion_tiempo_minimo_detencion_generadores(this.Generadores.ElRed(id_validos(i)));
                    end
                end
            end
     
            % contingencia N1
            if this.pParOpt.ConsideraContingenciaN1
                this.escribe_balance_energia_n1();
                this.escribe_relaciones_flujos_angulos_n1();
            end

            if this.pParOpt.ConsideraEstadoPostContingencia
                this.escribe_balance_energia_pc(); 
                this.escribe_relaciones_flujos_angulos_pc();
                this.escribe_limites_generadores_pc();
                this.escribe_limites_baterias_pc();                
            end
        end

        function escribe_restricciones_calculo_pmax_generadores(this)
            % una restriccion por cada generador convencional
            % pmax_gen_sist(t) >= pmax_gen(t)
            cant_po = this.iCantPuntosOperacion;
            id_validos = find(this.Generadores.Despachable > 0);
            indice_p_max_gen_desp_sist_desde = this.IdVarOptPmaxGenDespDesde;
            indice_p_max_gen_desp_sist_hasta =  indice_p_max_gen_desp_sist_desde + cant_po - 1;
            for i = 1:length(id_validos)
                % indices reservas positivas
                indice_ineq_desde = this.iIndiceIneq + 1;
                indice_ineq_hasta = this.iIndiceIneq + cant_po;
                this.iIndiceIneq = indice_ineq_hasta;
                
                indice_p_desde = this.Generadores.IdVarOptDesde(id_validos(i));
                indice_p_hasta = indice_p_desde + cant_po - 1;
                this.Aineq(indice_ineq_desde:indice_ineq_hasta, indice_p_max_gen_desp_sist_desde:indice_p_max_gen_desp_sist_hasta) = - diag(ones(cant_po,1));
                this.Aineq(indice_ineq_desde:indice_ineq_hasta, indice_p_desde:indice_p_hasta) = diag(ones(cant_po,1));
                this.bineq(indice_ineq_desde:indice_ineq_hasta) = 0;

                this.Generadores.IdRestriccionIPmaxGenDespDesde(id_validos(i)) = indice_ineq_desde;
                
                if this.iNivelDebug > 0
                    this.ingresa_nombre_restriccion_desigualdad(this.Generadores.ElRed(id_validos(i)), indice_ineq_desde, 'PmaxGenDespSist');
                end
                
            end
        end

        function agrega_restriccion_calculo_pmax_generadores(this, variable, indice_p_desde)
            cant_po = this.iCantPuntosOperacion;
            indice_p_max_gen_desp_sist_desde = this.IdVarOptPmaxGenDespDesde;
            indice_p_max_gen_desp_sist_hasta =  indice_p_max_gen_desp_sist_desde + cant_po - 1;

            % indices reservas positivas
            indice_ineq_desde = this.iIndiceIneq + 1;
            indice_ineq_hasta = this.iIndiceIneq + cant_po;
            this.iIndiceIneq = indice_ineq_hasta;
                
            indice_p_hasta = indice_p_desde + cant_po - 1;
            this.Aineq(indice_ineq_desde:indice_ineq_hasta, indice_p_max_gen_desp_sist_desde:indice_p_max_gen_desp_sist_hasta) = - diag(ones(cant_po,1));
            this.Aineq(indice_ineq_desde:indice_ineq_hasta, indice_p_desde:indice_p_hasta) = diag(ones(cant_po,1));
            this.bineq(indice_ineq_desde:indice_ineq_hasta) = 0;

            this.Generadores.IdRestriccionIPmaxGenDespDesde(variable.entrega_id()) = indice_ineq_desde;

            if this.iNivelDebug > 0
                this.ingresa_nombre_restriccion_desigualdad(variable, indice_ineq_desde, 'PmaxGenDespSist');
            end
        end
        
        function escribe_restricciones_reservas_minimas_sistema(this)
            % res_pos_g1(t) + res_pos_g2(t) + ... + res_pos_bat1(t) +  ... + res_pos_batn(t) >= RminPosSist
            % res_neg_g1(t) + res_neg_g2(t) + ... + res_neg_bat1(t) + ... + res_neg_batn(t) >= RminNegSist
            
            cant_po = this.iCantPuntosOperacion;
            id_validos = find(this.Generadores.IdVarOptResPosDesde > 0);
            
            % indices reservas positivas
            indice_ineq_pos_desde = this.iIndiceIneq + 1;
            indice_ineq_pos_hasta = this.iIndiceIneq + cant_po;
            this.iIndiceIneq = indice_ineq_pos_hasta;
            
            % indices reservas negativas
            indice_ineq_neg_desde = this.iIndiceIneq + 1;
            indice_ineq_neg_hasta = this.iIndiceIneq + cant_po;
            this.iIndiceIneq = indice_ineq_neg_hasta;

            this.IdRestriccionIResPosDesde = indice_ineq_pos_desde;
            this.IdRestriccionIResNegDesde = indice_ineq_neg_desde;
            
            for i = 1:length(id_validos)
                % reservas positivas
                indice_res_pos_desde = this.Generadores.IdVarOptResPosDesde(id_validos(i));
                indice_res_pos_hasta = indice_res_pos_desde + cant_po - 1;
                this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_res_pos_desde:indice_res_pos_hasta) = - diag(ones(cant_po,1));

                % reservas negativas
                indice_res_neg_desde = this.Generadores.IdVarOptResNegDesde(id_validos(i));
                indice_res_neg_hasta = indice_res_neg_desde + cant_po - 1;
                this.Aineq(indice_ineq_neg_desde:indice_ineq_neg_hasta, indice_res_neg_desde:indice_res_neg_hasta) = - diag(ones(cant_po,1));
            end
            
            for i = 1:this.Baterias.n
                % reservas positivas
                indice_res_pos_desde = this.Baterias.IdVarOptResDescargaDesde(i);
                indice_res_pos_hasta = indice_res_pos_desde + cant_po - 1;
                this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_res_pos_desde:indice_res_pos_hasta) = - diag(ones(cant_po,1));

                % reservas negativas
                indice_res_neg_desde = this.Baterias.IdVarOptResCargaDesde(i);
                indice_res_neg_hasta = indice_res_neg_desde + cant_po - 1;
                this.Aineq(indice_ineq_neg_desde:indice_ineq_neg_hasta, indice_res_neg_desde:indice_res_neg_hasta) = - diag(ones(cant_po,1));
            end
            
            if this.pParOpt.EstrategiaReservasMinimasSistema == 1
                % reservas de subida: potencia máxima del generador despachable más grande
                % res_pos_g1(t) + res_pos_g2(t) + ... + res_pos_bat1(t) +  ... + res_pos_batn(t) >= max(Pmax_gen_despachable)
                reservas_minimas_pos = max(this.Generadores.Pmax(this.Generadores.Despachable == 1));
                this.bineq(indice_ineq_pos_desde:indice_ineq_pos_hasta) = -reservas_minimas_pos;
            elseif this.pParOpt.EstrategiaReservasMinimasSistema == 2
                % potencia actual generador más grande
                % res_pos_g1(t) + res_pos_g2(t) + ... + res_pos_bat1(t) +  ... + res_pos_batn(t) - Pmax_gen_despachables(t)>= 0
                indice_pmax_gen_desp_desde = this.IdVarOptPmaxGenDespDesde;
                indice_pmax_gen_desp_hasta = indice_pmax_gen_desp_desde + this.iCantPuntosOperacion -1;
                this.Aineq(indice_ineq_neg_desde:indice_ineq_neg_hasta, indice_pmax_gen_desp_desde:indice_pmax_gen_desp_hasta) = - diag(ones(cant_po,1));
            end
            % reservas mínimas negativas igual a mayor consumo
            % res_neg_g1(t) + res_neg_g2(t) + ... + res_neg_bat1(t) + ... + res_neg_batn(t) >= Max(consumo(t)
            reservas_minimas_neg = -inf*ones(this.iCantPuntosOperacion,1);
            for i = 1:this.Consumos.n
                indice_desde = this.Consumos.IdVarOptDesde(i);
                indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;
                pmax_cons = this.ub(indice_desde:indice_hasta);
                reservas_minimas_neg = max(reservas_minimas_neg, pmax_cons);
            end
            this.bineq(indice_ineq_neg_desde:indice_ineq_neg_hasta) = -reservas_minimas_neg;
            
            if this.iNivelDebug > 0
                this.ingresa_nombre_restriccion_desigualdad(this.pSEP, indice_ineq_pos_desde, 'ResMinPos');
                this.ingresa_nombre_restriccion_desigualdad(this.pSEP, indice_ineq_neg_desde, 'ResMinNeg');
            end
        end
        
        function escribe_restriccion_calculo_inercia(this)
            % H - sum(Hg_i) = 0, excepto generador que falla
            % Consideraciones de UC:
            %  - si no se considera UC la inercia corresponde a la suma de las inercias de todos los generadores
            %  - si se considera UC, para aquéllos generadores que no tienen
            %    variable de UC (porque Pmin = 0) se considera la inercia de todas formas, porque la solución obvia es que el generador
            %    inyecte al menos epsilon, lo que no influye en los resultados económicos
            cant_po = this.iCantPuntosOperacion;
            for cont = 1:this.iCantContingenciasGenCons            
                % indices restricción
                indice_eq_desde = this.iIndiceEq + 1;
                indice_eq_hasta = this.iIndiceEq + cant_po;
                this.iIndiceEq = indice_eq_hasta;
                this.IdRestriccionEInerciaDesde(cont) = indice_eq_desde;

                indice_h_desde = this.IdVarOptInerciaDesde(cont);
                indice_h_hasta = indice_h_desde + cant_po - 1;
                this.Aeq(indice_eq_desde:indice_eq_hasta, indice_h_desde:indice_h_hasta) = diag(ones(cant_po,1));
                this.beq(indice_eq_desde:indice_eq_hasta) = 0;
            
                id_validos = find(this.Generadores.Despachable > 0);
                for i = 1:length(id_validos)
                    if this.pContingenciasGenCons(cont) == this.Generadores.ElRed(id_validos(i))
                        continue
                    end
                    hgen = this.Generadores.ElRed(id_validos(i)).entrega_inercia();
                    indice_uc_desde = 0;
                    if this.pParOpt.DeterminaUC
                        indice_uc_desde = this.Generadores.IdVarOptUCDesde(id_validos(i));
                        if indice_uc_desde > 0
                            indice_uc_hasta = indice_uc_desde + cant_po - 1;
                        end
                    end
                    if indice_uc_desde > 0
                        this.Aeq(indice_eq_desde:indice_eq_hasta, indice_uc_desde:indice_uc_hasta) = -hgen*diag(ones(cant_po,1));
                    else
                        this.beq(indice_eq_desde:indice_eq_hasta) = this.beq(indice_eq_desde:indice_eq_hasta) + hgen;
                    end
                end
                
                if this.iNivelDebug > 0
                    this.ingresa_nombre_restriccion_igualdad(this.pSEP, indice_eq_desde, 'HSist', cont);
                end
            end
        end

        function escribe_restricciones_rocof(this)
            % dP = caída generador en contingencia (positiva)
            % rocof_max: máxima pendiente (positiva) del rocof
            % rocof = 1/2H*(dP - aportes_baterias - aportes_renovables) <= rocof_max
            % -rocof_max*2*H + dP - aportes_baterias - aportes_renovables <= 0
            cant_po = this.iCantPuntosOperacion;
            
            for cont = 1:this.iCantContingenciasGenCons            
                % indice de restricion
                indice_ineq_desde = this.iIndiceIneq + 1;
                indice_ineq_hasta = this.iIndiceIneq + cant_po;
                this.iIndiceIneq = indice_ineq_hasta;
                this.IdRestriccionIROCOFDesde(cont) = indice_ineq_desde;

                rocof_max = round(this.pParOpt.ROCOFMax,this.pParOpt.DecimalesRedondeo);

                % indice de inercia del sistema
                indice_h_desde = this.IdVarOptInerciaDesde(cont);
                indice_h_hasta = indice_h_desde + cant_po - 1;
                this.Aineq(indice_ineq_desde:indice_ineq_hasta, indice_h_desde:indice_h_hasta) = -2*rocof_max*diag(ones(cant_po,1));
                this.bineq(indice_ineq_desde:indice_ineq_hasta) = 0;

                id_gen_cont = this.pContingenciasGenCons(cont).entrega_id();
                indice_dp_desde = this.Generadores.IdVarOptDesde(id_gen_cont);
                indice_dp_hasta = indice_dp_desde + cant_po - 1;
                this.Aineq(indice_ineq_desde:indice_ineq_hasta, indice_dp_desde:indice_dp_hasta) = diag(ones(cant_po,1));

                for i = 1:this.Baterias.n
                    % reservas positivas
                    indice_res_pos_desde = this.Baterias.IdVarOptResDescargaDesde(i);
                    indice_res_pos_hasta = indice_res_pos_desde + cant_po - 1;
                    this.Aineq(indice_ineq_desde:indice_ineq_hasta, indice_res_pos_desde:indice_res_pos_hasta) = - diag(ones(cant_po,1));
                end

                % aporte generadores ERNC. En este caso iIndiceVarOpt indica el derate
                id_ernc = find(this.Generadores.Despachable == 0);
                for i = 1:length(id_ernc)
                    indice_desde = this.Generadores.IdVarOptDesde(id_ernc(i));
                    indice_hasta = indice_desde + cant_po - 1;
                    this.Aineq(indice_ineq_desde:indice_ineq_hasta, indice_desde:indice_hasta) = - diag(ones(cant_po,1));
                end

                if this.iNivelDebug > 0
                    this.ingresa_nombre_restriccion_desigualdad(this.pSEP, indice_ineq_desde, 'ROCOF', cont);
                end
            end
        end
        
        function agrega_generador_a_restricciones_reservas_minimas_sistema(this, indice_res_pos_desde, indice_res_neg_desde)
            cant_po = this.iCantPuntosOperacion;
            
            indice_ineq_pos_desde = this.IdRestriccionIResPosDesde;
            indice_ineq_pos_hasta = indice_ineq_pos_desde + cant_po - 1;

            indice_ineq_neg_desde = this.IdRestriccionIResNegDesde;
            indice_ineq_neg_hasta = indice_ineq_neg_desde + cant_po - 1;
            
            % reservas positivas
            indice_res_pos_hasta = indice_res_pos_desde + cant_po - 1;
            this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_res_pos_desde:indice_res_pos_hasta) = - diag(ones(cant_po,1));

            % reservas negativas
            indice_res_neg_hasta = indice_res_neg_desde + cant_po - 1;
            this.Aineq(indice_ineq_neg_desde:indice_ineq_neg_hasta, indice_res_neg_desde:indice_res_neg_hasta) = - diag(ones(cant_po,1));
        end

        function agrega_bateria_a_restricciones_reservas_minimas_sistema(this, indice_res_descarga_desde, indice_res_carga_desde)
            cant_po = this.iCantPuntosOperacion;
            
            indice_ineq_pos_desde = this.IdRestriccionIResPosDesde;
            indice_ineq_pos_hasta = indice_ineq_pos_desde + cant_po - 1;

            indice_ineq_neg_desde = this.IdRestriccionIResNegDesde;
            indice_ineq_neg_hasta = indice_ineq_neg_desde + cant_po - 1;
            
            % reservas positivas (descarga)
            indice_res_descarga_hasta = indice_res_descarga_desde + cant_po - 1;
            this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_res_descarga_desde:indice_res_descarga_hasta) = - diag(ones(cant_po,1));

            % reservas negativas (carga)
            indice_res_carga_hasta = indice_res_carga_desde + cant_po - 1;
            this.Aineq(indice_ineq_neg_desde:indice_ineq_neg_hasta, indice_res_carga_desde:indice_res_carga_hasta) = - diag(ones(cant_po,1));
        end
        
        function escribe_restricciones_reservas_generadores(this)
            cant_po = this.iCantPuntosOperacion;
            id_validos = find(this.Generadores.EntreganReservas > 0);

            for i = 1:length(id_validos)
                % reservas positivas
                % Sin UC: Pg(t) + rpos(t) <= Pmax
                % Con UC: Pg(t) + rpos(t) - Pmax*UC(t) <= 0
                indice_ineq_pos_desde = this.iIndiceIneq + 1;
                indice_ineq_pos_hasta = this.iIndiceIneq + cant_po;
                this.iIndiceIneq = indice_ineq_pos_hasta;

                this.Generadores.IdRestriccionIResPosDesde(id_validos(i)) = indice_ineq_pos_desde;
                
                % reservas negativas
                % Sin UC: Pg(t) - rneg(t) >= Pmin
                % Con UC: Pg(t) - rneg(t) - Pmin*UC(t) >= 0
                indice_ineq_neg_desde = this.iIndiceIneq + 1;
                indice_ineq_neg_hasta = this.iIndiceIneq + cant_po;
                this.iIndiceIneq = indice_ineq_neg_hasta;

                this.Generadores.IdRestriccionIResNegDesde(id_validos(i)) = indice_ineq_neg_desde;
                
                % potencia del generador
                indice_p_desde = this.Generadores.IdVarOptDesde(id_validos(i));
                indice_p_hasta = indice_p_desde + cant_po - 1;
                this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_p_desde:indice_p_hasta) = diag(ones(cant_po,1));
                this.Aineq(indice_ineq_neg_desde:indice_ineq_neg_hasta, indice_p_desde:indice_p_hasta) = -diag(ones(cant_po,1));
                
                % reservas positivas
                indice_res_pos_desde = this.Generadores.IdVarOptResPosDesde(id_validos(i));
                indice_res_pos_hasta = indice_res_pos_desde + cant_po - 1;
                this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_res_pos_desde:indice_res_pos_hasta) = diag(ones(cant_po,1));

                % reservas negativas
                indice_res_neg_desde = this.Generadores.IdVarOptResNegDesde(id_validos(i));
                indice_res_neg_hasta = indice_res_neg_desde + cant_po - 1;
                this.Aineq(indice_ineq_neg_desde:indice_ineq_neg_hasta, indice_res_neg_desde:indice_res_neg_hasta) = diag(ones(cant_po,1));
      
                pmax = this.Generadores.Pmax(id_validos(i));
                pmin = this.Generadores.Pmin(id_validos(i));
                
                if this.pParOpt.DeterminaUC && this.Generadores.IdVarOptUCDesde(id_validos(i)) > 0
                    indice_uc_desde = this.Generadores.IdVarOptUCDesde(id_validos(i));
                    indice_uc_hasta = indice_uc_desde + cant_po - 1;
                    this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_uc_desde:indice_uc_hasta) = -pmax*diag(ones(cant_po,1));
                    this.Aineq(indice_ineq_neg_desde:indice_ineq_neg_hasta, indice_uc_desde:indice_uc_hasta) = pmin*diag(ones(cant_po,1));
                    
                    this.bineq(indice_ineq_pos_desde:indice_ineq_pos_hasta) = 0;
                    this.bineq(indice_ineq_neg_desde:indice_ineq_neg_hasta) = 0;
                else
                    this.bineq(indice_ineq_pos_desde:indice_ineq_pos_hasta) = pmax;
                    this.bineq(indice_ineq_neg_desde:indice_ineq_neg_hasta) = -pmin;
                end

                if this.iNivelDebug > 0
                    this.ingresa_nombre_restriccion_desigualdad(this.Generadores.ElRed(id_validos(i)), indice_ineq_pos_desde, 'LimResPos');
                    this.ingresa_nombre_restriccion_desigualdad(this.Generadores.ElRed(id_validos(i)), indice_ineq_neg_desde, 'LimResNeg');
                end
            end
        end

        function escribe_limites_generadores_pc(this)
            cant_po = this.iCantPuntosOperacion;
            
            % sólo generadores convencionales
            id_validos = find(this.Generadores.EntreganReservas > 0);
            for i = 1:length(id_validos)
                % potencia del generador
                pmax = this.Generadores.Pmax(id_validos(i));
                pmin = this.Generadores.Pmin(id_validos(i));
                indice_p_desde = this.Generadores.IdVarOptDesde(id_validos(i));
                indice_p_hasta = indice_p_desde + cant_po - 1;
                for cont = 1:this.iCantContingenciasGenCons                
                    % reservas positivas
                    % Sin UC: Pg(t) + rpos(t) <= Pmax
                    % Con UC: Pg(t) + rpos(t) - Pmax*UC(t) <= 0
                    indice_ineq_pos_desde = this.iIndiceIneq + 1;
                    indice_ineq_pos_hasta = this.iIndiceIneq + cant_po;
                    this.iIndiceIneq = indice_ineq_pos_hasta;

                    this.Generadores.IdRestriccionIPCResPosDesde(id_validos(i), cont) = indice_ineq_pos_desde;

                    % reservas negativas
                    % Sin UC: Pg(t) - rneg(t) >= Pmin
                    % Con UC: Pg(t) - rneg(t) - Pmin*UC(t) >= 0
                    indice_ineq_neg_desde = this.iIndiceIneq + 1;
                    indice_ineq_neg_hasta = this.iIndiceIneq + cant_po;
                    this.iIndiceIneq = indice_ineq_neg_hasta;

                    this.Generadores.IdRestriccionIPCResNegDesde(id_validos(i), cont) = indice_ineq_neg_desde;
                    
                    % potencia del generador
                    this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_p_desde:indice_p_hasta) = diag(ones(cant_po,1));
                    this.Aineq(indice_ineq_neg_desde:indice_ineq_neg_hasta, indice_p_desde:indice_p_hasta) = -diag(ones(cant_po,1));

                    % despliegue de reservas positivas
                    indice_res_pos_desde = this.Generadores.IdVarOptPCResPosDesde(id_validos(i), cont);
                    indice_res_pos_hasta = indice_res_pos_desde + cant_po - 1;
                    this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_res_pos_desde:indice_res_pos_hasta) = diag(ones(cant_po,1));

                    % despliegue de reservas negativas
                    indice_res_neg_desde = this.Generadores.IdVarOptPCResNegDesde(id_validos(i), cont);
                    indice_res_neg_hasta = indice_res_neg_desde + cant_po - 1;
                    this.Aineq(indice_ineq_neg_desde:indice_ineq_neg_hasta, indice_res_neg_desde:indice_res_neg_hasta) = diag(ones(cant_po,1));

                    if this.pParOpt.DeterminaUC && this.Generadores.IdVarOptUCDesde(id_validos(i)) > 0
                        indice_uc_desde = this.Generadores.IdVarOptUCDesde(id_validos(i));
                        indice_uc_hasta = indice_uc_desde + cant_po - 1;
                        this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_uc_desde:indice_uc_hasta) = -pmax*diag(ones(cant_po,1));
                        this.Aineq(indice_ineq_neg_desde:indice_ineq_neg_hasta, indice_uc_desde:indice_uc_hasta) = pmin*diag(ones(cant_po,1));

                        this.bineq(indice_ineq_pos_desde:indice_ineq_pos_hasta) = 0;
                        this.bineq(indice_ineq_neg_desde:indice_ineq_neg_hasta) = 0;
                    else
                        this.bineq(indice_ineq_pos_desde:indice_ineq_pos_hasta) = pmax;
                        this.bineq(indice_ineq_neg_desde:indice_ineq_neg_hasta) = -pmin;
                    end

                    if this.iNivelDebug > 0
                        this.ingresa_nombre_restriccion_desigualdad(this.Generadores.ElRed(id_validos(i)), indice_ineq_pos_desde, 'LimResPos', cont);
                        this.ingresa_nombre_restriccion_desigualdad(this.Generadores.ElRed(id_validos(i)), indice_ineq_neg_desde, 'LimResNeg', cont);
                    end
                end
            end
        end

        function agrega_limite_generadores_pc(this, variable)
            cant_po = this.iCantPuntosOperacion;
            n_gen = variable.entrega_id();
            % potencia del generador
            pmax = this.Generadores.Pmax(n_gen);
            pmin = this.Generadores.Pmin(n_gen);
            indice_p_desde = this.Generadores.IdVarOptDesde(n_gen);
            indice_p_hasta = indice_p_desde + cant_po - 1;
            for cont = 1:this.iCantContingenciasGenCons                
                % reservas positivas
                % Sin UC: Pg(t) + rpos(t) <= Pmax
                % Con UC: Pg(t) + rpos(t) - Pmax*UC(t) <= 0
                indice_ineq_pos_desde = this.iIndiceIneq + 1;
                indice_ineq_pos_hasta = this.iIndiceIneq + cant_po;
                this.iIndiceIneq = indice_ineq_pos_hasta;

                this.Generadores.IdRestriccionIPCResPosDesde(n_gen, cont) = indice_ineq_pos_desde;

                % reservas negativas
                % Sin UC: Pg(t) - rneg(t) >= Pmin
                % Con UC: Pg(t) - rneg(t) - Pmin*UC(t) >= 0
                indice_ineq_neg_desde = this.iIndiceIneq + 1;
                indice_ineq_neg_hasta = this.iIndiceIneq + cant_po;
                this.iIndiceIneq = indice_ineq_neg_hasta;

                this.Generadores.IdRestriccionIPCResNegDesde(n_gen, cont) = indice_ineq_neg_desde;

                % potencia del generador
                this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_p_desde:indice_p_hasta) = diag(ones(cant_po,1));
                this.Aineq(indice_ineq_neg_desde:indice_ineq_neg_hasta, indice_p_desde:indice_p_hasta) = -diag(ones(cant_po,1));

                % despliegue de reservas positivas
                indice_res_pos_desde = this.Generadores.IdVarOptPCResPosDesde(n_gen, cont);
                indice_res_pos_hasta = indice_res_pos_desde + cant_po - 1;
                this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_res_pos_desde:indice_res_pos_hasta) = diag(ones(cant_po,1));

                % despliegue de reservas negativas
                indice_res_neg_desde = this.Generadores.IdVarOptPCResNegDesde(n_gen, cont);
                indice_res_neg_hasta = indice_res_neg_desde + cant_po - 1;
                this.Aineq(indice_ineq_neg_desde:indice_ineq_neg_hasta, indice_res_neg_desde:indice_res_neg_hasta) = diag(ones(cant_po,1));

                if this.pParOpt.DeterminaUC && this.Generadores.IdVarOptUCDesde(n_gen) > 0
                    indice_uc_desde = this.Generadores.IdVarOptUCDesde(n_gen);
                    indice_uc_hasta = indice_uc_desde + cant_po - 1;
                    this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_uc_desde:indice_uc_hasta) = -pmax*diag(ones(cant_po,1));
                    this.Aineq(indice_ineq_neg_desde:indice_ineq_neg_hasta, indice_uc_desde:indice_uc_hasta) = pmin*diag(ones(cant_po,1));

                    this.bineq(indice_ineq_pos_desde:indice_ineq_pos_hasta) = 0;
                    this.bineq(indice_ineq_neg_desde:indice_ineq_neg_hasta) = 0;
                else
                    this.bineq(indice_ineq_pos_desde:indice_ineq_pos_hasta) = pmax;
                    this.bineq(indice_ineq_neg_desde:indice_ineq_neg_hasta) = -pmin;
                end

                if this.iNivelDebug > 0
                    this.ingresa_nombre_restriccion_desigualdad(variable, indice_ineq_pos_desde, 'LimResPos', cont);
                    this.ingresa_nombre_restriccion_desigualdad(variable, indice_ineq_neg_desde, 'LimResNeg', cont);
                end
            end
        end
        
        function agrega_restriccion_reservas_generador(this, variable, indice_p_desde, indice_res_pos_desde, indice_res_neg_desde)
            cant_po = this.iCantPuntosOperacion;
            n_gen = variable.entrega_id();
            % reservas positivas
            % Sin UC: Pg(t) + rpos(t) <= Pmax
            % Con UC: Pg(t) + rpos(t) - Pmax*UC(t) <= 0
            indice_ineq_pos_desde = this.iIndiceIneq + 1;
            indice_ineq_pos_hasta = this.iIndiceIneq + cant_po;
            this.iIndiceIneq = indice_ineq_pos_hasta;

            this.Generadores.IdRestriccionIResPosDesde(n_gen) = indice_ineq_pos_desde;
                
            % reservas negativas
            % Sin UC: Pg(t) - rneg(t) >= Pmin
            % Con UC: Pg(t) - rneg(t) - Pmin*UC(t) >= 0
            indice_ineq_neg_desde = this.iIndiceIneq + 1;
            indice_ineq_neg_hasta = this.iIndiceIneq + cant_po;
            this.iIndiceIneq = indice_ineq_neg_hasta;

            this.Generadores.IdRestriccionIResNegDesde(n_gen) = indice_ineq_neg_desde;
                
            % potencia del generador
            indice_p_hasta = indice_p_desde + cant_po - 1;
            this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_p_desde:indice_p_hasta) = diag(ones(cant_po,1));
            this.Aineq(indice_ineq_neg_desde:indice_ineq_neg_hasta, indice_p_desde:indice_p_hasta) = -diag(ones(cant_po,1));
                
            % reservas positivas
            indice_res_pos_hasta = indice_res_pos_desde + cant_po - 1;
            this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_res_pos_desde:indice_res_pos_hasta) = diag(ones(cant_po,1));

            % reservas negativas
            indice_res_neg_hasta = indice_res_neg_desde + cant_po - 1;
            this.Aineq(indice_ineq_neg_desde:indice_ineq_neg_hasta, indice_res_neg_desde:indice_res_neg_hasta) = diag(ones(cant_po,1));
      
            pmax = this.Generadores.Pmax(n_gen);
            pmin = this.Generadores.Pmin(n_gen);
                
            if this.pParOpt.DeterminaUC && this.Generadores.IdVarOptUCDesde(n_gen) > 0
                indice_uc_desde = this.Generadores.IdVarOptUCDesde(n_gen);
                indice_uc_hasta = indice_uc_desde + cant_po - 1;
                this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_uc_desde:indice_uc_hasta) = -pmax*diag(ones(cant_po,1));
                this.Aineq(indice_ineq_neg_desde:indice_ineq_neg_hasta, indice_uc_desde:indice_uc_hasta) = pmin*diag(ones(cant_po,1));

                this.bineq(indice_ineq_pos_desde:indice_ineq_pos_hasta) = 0;
                this.bineq(indice_ineq_neg_desde:indice_ineq_neg_hasta) = 0;
            else
                this.bineq(indice_ineq_pos_desde:indice_ineq_pos_hasta) = pmax;
                this.bineq(indice_ineq_neg_desde:indice_ineq_neg_hasta) = -pmin;
            end
            
            if this.iNivelDebug > 0
                this.ingresa_nombre_restriccion_desigualdad(variable, indice_ineq_pos_desde, 'LimResPos');
                this.ingresa_nombre_restriccion_desigualdad(variable, indice_ineq_neg_desde, 'LimResNeg');
            end
        end

        function agrega_restriccion_reservas_baterias(this, variable, indice_descarga_desde, indice_carga_desde, indice_e_bateria_desde, indice_res_descarga_desde, indice_res_carga_desde)
            % p_bateria_op_normal + p_bateria_pc tiene que mantenerse dentro de los límites
            % p_descarga_bateria - p_carga_bateria + p_descarga_bateria_pc <= Pmax_descarga
            % p_carga_bateria - p_descarga_bateria + p_carga_bateria_pc <= Pmax_carga
            
            % energía de la batería debe ser suficiente para operación normal y el despliegue de las reservas por una hora
            % E(t) - 1/eta_descarga*p_descarga_bateria(t) + eta_carga*p_carga_bateria(t) + eta_carga*p_carga_pc(t) <= Emax
            % E(t) - 1/eta_descarga*p_descarga_bateria(t) + eta_carga*p_carga_bateria(t) - 1/eta_descarga*p_descarga_pc(t)  >= Emin
            cant_po = this.iCantPuntosOperacion;
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            n_bat = variable.entrega_id();
            
            % potencias de la batería en operación normal
            indice_descarga_hasta = indice_descarga_desde + cant_po - 1;
            indice_carga_hasta = indice_carga_desde + cant_po - 1;

            eta_descarga = variable.entrega_eficiencia_descarga();
            eta_carga = variable.entrega_eficiencia_carga();

            % reserva descarga y carga
            indice_res_descarga_hasta = indice_res_descarga_desde + cant_po - 1;
            indice_res_carga_hasta = indice_res_carga_desde + cant_po - 1;

            % 1. reservas positivas
            % p_descarga_bateria(t) - p_carga_bateria(t) + p_descarga_bateria_pc(t) <= Pmax_descarga
            indice_ineq_pos_desde = this.iIndiceIneq + 1;
            indice_ineq_pos_hasta = this.iIndiceIneq + cant_po;
            this.iIndiceIneq = indice_ineq_pos_hasta;
            this.Baterias.IdRestriccionIResDescargaDesde(n_bat) = indice_ineq_pos_desde;

            this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_descarga_desde:indice_descarga_hasta) = diag(ones(cant_po,1));
            this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_carga_desde:indice_carga_hasta) = -diag(ones(cant_po,1));
            this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_res_descarga_desde:indice_res_descarga_hasta) = diag(ones(cant_po,1));                
            this.bineq(indice_ineq_pos_desde:indice_ineq_pos_hasta) = variable.entrega_pmax_descarga()/this.Sbase;

            if this.iNivelDebug > 0
                this.ingresa_nombre_restriccion_desigualdad(variable, indice_ineq_pos_desde, 'LimResPos');
            end

            % 2. reservas negativas
            % p_carga_bateria(t) - p_descarga_bateria(t) + p_carga_bateria_pc(t) <= Pmax_carga
            indice_ineq_neg_desde = this.iIndiceIneq + 1;
            indice_ineq_neg_hasta = this.iIndiceIneq + cant_po;
            this.iIndiceIneq = indice_ineq_neg_hasta;
            this.Baterias.IdRestriccionIResCargaDesde(n_bat) = indice_ineq_neg_desde;

            this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_carga_desde:indice_carga_hasta) = diag(ones(cant_po,1));
            this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_descarga_desde:indice_descarga_hasta) = -diag(ones(cant_po,1));
            this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_res_carga_desde:indice_res_carga_hasta) = diag(ones(cant_po,1));                
            this.bineq(indice_ineq_pos_desde:indice_ineq_pos_hasta) = variable.entrega_pmax_carga()/this.Sbase;

            if this.iNivelDebug > 0
                this.ingresa_nombre_restriccion_desigualdad(variable, indice_ineq_neg_desde, 'LimResNeg');
            end

            if this.bConsideraDependenciaTemporal
                indice_e_bateria_hasta = indice_e_bateria_desde + cant_po - 1;

                % 3. Límite superior energía
                % E(t) - 1/eta_descarga*p_descarga_bateria(t) + eta_carga*p_carga_bateria(t) + eta_carga*p_carga_pc(t) <= Emax                
                indice_ineq_be_carga_desde = this.iIndiceIneq + 1;
                indice_ineq_be_carga_hasta = this.iIndiceIneq + cant_po;
                this.iIndiceIneq = indice_ineq_be_carga_hasta;
                this.Baterias.IdRestriccionIResBalanceCargaDesde(n_bat) = indice_ineq_be_carga_desde;

                this.Aineq(indice_ineq_be_carga_desde:indice_ineq_be_carga_hasta, indice_e_bateria_desde:indice_e_bateria_hasta) = diag(ones(cant_po,1));
                this.Aineq(indice_ineq_be_carga_desde:indice_ineq_be_carga_hasta, indice_descarga_desde:indice_descarga_hasta) = round(-1/eta_descarga*diag(ones(cant_po,1)),dec_redondeo);
                this.Aineq(indice_ineq_be_carga_desde:indice_ineq_be_carga_hasta, indice_carga_desde:indice_carga_hasta) = round(eta_carga*diag(ones(cant_po,1)),dec_redondeo);
                this.Aineq(indice_ineq_be_carga_desde:indice_ineq_be_carga_hasta, indice_res_carga_desde:indice_res_carga_desde) = round(eta_carga*diag(ones(cant_po,1)),dec_redondeo);
                this.bineq(indice_ineq_be_carga_desde:indice_ineq_be_carga_hasta) = variable.entrega_capacidad()/this.Sbase;

                if this.iNivelDebug > 0
                    this.ingresa_nombre_restriccion_desigualdad(variable, indice_ineq_be_carga_desde, 'LimESupRes');
                end

                % 4. Límite inferior energía                
                % E(t) - 1/eta_descarga*p_descarga_bateria(t) + eta_carga*p_carga_bateria(t) - 1/eta_descarga*p_descarga_pc(t)  >= Emin
                indice_ineq_be_descarga_desde = this.iIndiceIneq + 1;
                indice_ineq_be_descarga_hasta = this.iIndiceIneq + cant_po;
                this.iIndiceIneq = indice_ineq_be_descarga_hasta;
                this.Baterias.IdRestriccionIResBalanceDescargaDesde(n_bat) = indice_ineq_be_descarga_desde;

                this.Aineq(indice_ineq_be_descarga_desde:indice_ineq_be_descarga_hasta, indice_e_bateria_desde:indice_e_bateria_hasta) = -diag(ones(cant_po,1));
                this.Aineq(indice_ineq_be_descarga_desde:indice_ineq_be_descarga_hasta, indice_descarga_desde:indice_descarga_hasta) = round(1/eta_descarga*diag(ones(cant_po,1)),dec_redondeo);
                this.Aineq(indice_ineq_be_descarga_desde:indice_ineq_be_descarga_hasta, indice_carga_desde:indice_carga_hasta) = round(-eta_carga*diag(ones(cant_po,1)),dec_redondeo);
                this.Aineq(indice_ineq_be_descarga_desde:indice_ineq_be_descarga_hasta, indice_res_descarga_desde:indice_res_descarga_desde) = round(1/eta_descarga*diag(ones(cant_po,1)),dec_redondeo);
                this.bineq(indice_ineq_be_descarga_desde:indice_ineq_be_descarga_hasta) = -variable.entrega_energia_minima()/this.Sbase;

                if this.iNivelDebug > 0
                    this.ingresa_nombre_restriccion_desigualdad(variable, indice_ineq_be_descarga_desde, 'LimEInfRes');
                end
            end
        end
        
        function escribe_restricciones_reservas_baterias(this)
            % p_bateria_op_normal + p_bateria_pc tiene que mantenerse dentro de los límites
            % p_descarga_bateria - p_carga_bateria + p_descarga_bateria_pc <= Pmax_descarga
            % p_carga_bateria - p_descarga_bateria + p_carga_bateria_pc <= Pmax_carga
            
            % energía de la batería debe ser suficiente para operación normal y el despliegue de las reservas por una hora
            % E(t) - 1/eta_descarga*p_descarga_bateria(t) + eta_carga*p_carga_bateria(t) + eta_carga*p_carga_pc(t) <= Emax
            % E(t) - 1/eta_descarga*p_descarga_bateria(t) + eta_carga*p_carga_bateria(t) - 1/eta_descarga*p_descarga_pc(t)  >= Emin
            cant_po = this.iCantPuntosOperacion;
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            for i = 1:this.Baterias.n
                % potencias de la batería en operación normal
                indice_descarga_desde = this.Baterias.IdVarOptDesdeDescarga(i);
                indice_descarga_hasta = indice_descarga_desde + cant_po - 1;
                indice_carga_desde = this.Baterias.IdVarOptDesdeCarga(i);
                indice_carga_hasta = indice_carga_desde + cant_po - 1;
                
                eta_descarga = this.Baterias.ElRed(i).entrega_eficiencia_descarga();
                eta_carga = this.Baterias.ElRed(i).entrega_eficiencia_carga();
                                
                % reserva descarga y carga
                indice_res_descarga_desde = this.Baterias.IdVarOptResDescargaDesde(i);
                indice_res_descarga_hasta = indice_res_descarga_desde + cant_po - 1;
                indice_res_carga_desde = this.Generadores.IdVarOptResCargaDesde(id_validos(i));
                indice_res_carga_hasta = indice_res_carga_desde + cant_po - 1;

                % 1. reservas positivas
                % p_descarga_bateria(t) - p_carga_bateria(t) + p_descarga_bateria_pc(t) <= Pmax_descarga
                indice_ineq_pos_desde = this.iIndiceIneq + 1;
                indice_ineq_pos_hasta = this.iIndiceIneq + cant_po;
                this.iIndiceIneq = indice_ineq_pos_hasta;
                this.Baterias.IdRestriccionIResDescargaDesde(i) = indice_ineq_pos_desde;
                
                this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_descarga_desde:indice_descarga_hasta) = diag(ones(cant_po,1));
                this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_carga_desde:indice_carga_hasta) = -diag(ones(cant_po,1));
                this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_res_descarga_desde:indice_res_descarga_hasta) = diag(ones(cant_po,1));                
                this.bineq(indice_ineq_pos_desde:indice_ineq_pos_hasta) = this.Baterias.ElRed(i).entrega_pmax_descarga()/this.Sbase;

                if this.iNivelDebug > 0
                    this.ingresa_nombre_restriccion_desigualdad(this.Baterias.ElRed(i), indice_ineq_pos_desde, 'LimResPos');
                end
                
                % 2. reservas negativas
                % p_carga_bateria(t) - p_descarga_bateria(t) + p_carga_bateria_pc(t) <= Pmax_carga
                indice_ineq_neg_desde = this.iIndiceIneq + 1;
                indice_ineq_neg_hasta = this.iIndiceIneq + cant_po;
                this.iIndiceIneq = indice_ineq_neg_hasta;
                this.Baterias.IdRestriccionIResCargaDesde(i) = indice_ineq_neg_desde;
                
                this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_carga_desde:indice_carga_hasta) = diag(ones(cant_po,1));
                this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_descarga_desde:indice_descarga_hasta) = -diag(ones(cant_po,1));
                this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_res_carga_desde:indice_res_carga_hasta) = diag(ones(cant_po,1));                
                this.bineq(indice_ineq_pos_desde:indice_ineq_pos_hasta) = this.Baterias.ElRed(i).entrega_pmax_carga()/this.Sbase;
                
                if this.iNivelDebug > 0
                    this.ingresa_nombre_restriccion_desigualdad(this.Baterias.ElRed(i), indice_ineq_neg_desde, 'LimResNeg');
                end

                if this.bConsideraDependenciaTemporal
                    % energía de la batería

                    indice_e_bateria_desde = this.Baterias.IdVarOptDesdeE(i);
                    indice_e_bateria_hasta = indice_e_bateria_desde + cant_po - 1;
                
                    % 3. Límite superior energía
                    % E(t) - 1/eta_descarga*p_descarga_bateria(t) + eta_carga*p_carga_bateria(t) + eta_carga*p_carga_pc(t) <= Emax                
                    indice_ineq_be_carga_desde = this.iIndiceIneq + 1;
                    indice_ineq_be_carga_hasta = this.iIndiceIneq + cant_po;
                    this.iIndiceIneq = indice_ineq_be_carga_hasta;
                    this.Baterias.IdRestriccionIResBalanceCargaDesde(i) = indice_ineq_be_carga_desde;

                    this.Aineq(indice_ineq_be_carga_desde:indice_ineq_be_carga_hasta, indice_e_bateria_desde:indice_e_bateria_hasta) = diag(ones(cant_po,1));
                    this.Aineq(indice_ineq_be_carga_desde:indice_ineq_be_carga_hasta, indice_descarga_desde:indice_descarga_hasta) = round(-1/eta_descarga*diag(ones(cant_po,1)),dec_redondeo);
                    this.Aineq(indice_ineq_be_carga_desde:indice_ineq_be_carga_hasta, indice_carga_desde:indice_carga_hasta) = round(eta_carga*diag(ones(cant_po,1)),dec_redondeo);
                    this.Aineq(indice_ineq_be_carga_desde:indice_ineq_be_carga_hasta, indice_res_carga_desde:indice_res_carga_desde) = round(eta_carga*diag(ones(cant_po,1)),dec_redondeo);
                    this.bineq(indice_ineq_be_carga_desde:indice_ineq_be_carga_hasta) = this.Baterias.ElRed(i).entrega_capacidad()/this.Sbase;

                    if this.iNivelDebug > 0
                        this.ingresa_nombre_restriccion_desigualdad(this.Baterias.ElRed(i), indice_ineq_be_carga_desde, 'LimESupRes');
                    end

                    % 4. Límite inferior energía                
                    % E(t) - 1/eta_descarga*p_descarga_bateria(t) + eta_carga*p_carga_bateria(t) - 1/eta_descarga*p_descarga_pc(t)  >= Emin
                    indice_ineq_be_descarga_desde = this.iIndiceIneq + 1;
                    indice_ineq_be_descarga_hasta = this.iIndiceIneq + cant_po;
                    this.iIndiceIneq = indice_ineq_be_descarga_hasta;
                    this.Baterias.IdRestriccionIResBalanceDescargaDesde(i) = indice_ineq_be_descarga_desde;

                    this.Aineq(indice_ineq_be_descarga_desde:indice_ineq_be_descarga_hasta, indice_e_bateria_desde:indice_e_bateria_hasta) = -diag(ones(cant_po,1));
                    this.Aineq(indice_ineq_be_descarga_desde:indice_ineq_be_descarga_hasta, indice_descarga_desde:indice_descarga_hasta) = round(1/eta_descarga*diag(ones(cant_po,1)),dec_redondeo);
                    this.Aineq(indice_ineq_be_descarga_desde:indice_ineq_be_descarga_hasta, indice_carga_desde:indice_carga_hasta) = round(-eta_carga*diag(ones(cant_po,1)),dec_redondeo);
                    this.Aineq(indice_ineq_be_descarga_desde:indice_ineq_be_descarga_hasta, indice_res_descarga_desde:indice_res_descarga_desde) = round(1/eta_descarga*diag(ones(cant_po,1)),dec_redondeo);
                    this.bineq(indice_ineq_be_descarga_desde:indice_ineq_be_descarga_hasta) = -this.Baterias.ElRed(i).entrega_energia_minima()/this.Sbase;

                    if this.iNivelDebug > 0
                        this.ingresa_nombre_restriccion_desigualdad(this.Baterias.ElRed(i), indice_ineq_be_descarga_desde, 'LimEInfRes');
                    end
                else
                    % Por ahora, se asume que hay energía suficiente para
                    % que aporten reservas positivas y negativas
                end
            end
        end

        function escribe_limites_baterias_pc(this)
            % p_bateria_op_normal + p_bateria_pc tiene que mantenerse dentro de los límites
            % p_descarga_bateria - p_carga_bateria + p_descarga_bateria_pc <= Pmax_descarga
            % p_carga_bateria - p_descarga_bateria + p_carga_bateria_pc <= Pmax_carga
            
            % energía de la batería debe ser suficiente para operación normal y el despliegue de las reservas por una hora
            % E(t) - 1/eta_descarga*p_descarga_bateria(t) + eta_carga*p_carga_bateria(t) + eta_carga*p_carga_pc(t) <= Emax
            % E(t) - 1/eta_descarga*p_descarga_bateria(t) + eta_carga*p_carga_bateria(t) - 1/eta_descarga*p_descarga_pc(t)  >= Emin
            cant_po = this.iCantPuntosOperacion;
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            for i = 1:this.Baterias.n
                % potencias de la batería en operación normal
                indice_descarga_desde = this.Baterias.IdVarOptDesdeDescarga(i);
                indice_descarga_hasta = indice_descarga_desde + cant_po - 1;
                indice_carga_desde = this.Baterias.IdVarOptDesdeCarga(i);
                indice_carga_hasta = indice_carga_desde + cant_po - 1;

                eta_descarga = this.Baterias.ElRed(i).entrega_eficiencia_descarga();
                eta_carga = this.Baterias.ElRed(i).entrega_eficiencia_carga();
                pmax_carga = this.Baterias.ElRed(i).entrega_pmax_carga()/this.Sbase;
                pmax_descarga = this.Baterias.ElRed(i).entrega_pmax_descarga()/this.Sbase;
                energia_maxima_bateria = this.Baterias.ElRed(i).entrega_capacidad()/this.Sbase;
                energia_minima_bateria = this.Baterias.ElRed(i).entrega_energia_minima()/this.Sbase;
                
                % energía de la batería
                indice_e_bateria_desde = this.Baterias.IdVarOptDesdeE(i);
                indice_e_bateria_hasta = indice_e_bateria_desde + cant_po - 1;
                
                for cont = 1:this.iCantContingenciasGenCons
                    % reserva descarga y carga
                    indice_res_descarga_desde = this.Baterias.IdVarOptPCResDescargaDesde(i, cont);
                    indice_res_descarga_hasta = indice_res_descarga_desde + cant_po - 1;
                    indice_res_carga_desde = this.Baterias.IdVarOptPCResCargaDesde(i, cont);
                    indice_res_carga_hasta = indice_res_carga_desde + cant_po - 1;

                    % 1. reservas positivas
                    % p_descarga_bateria(t) - p_carga_bateria(t) + p_descarga_bateria_pc(t) <= Pmax_descarga
                    indice_ineq_pos_desde = this.iIndiceIneq + 1;
                    indice_ineq_pos_hasta = this.iIndiceIneq + cant_po;
                    this.iIndiceIneq = indice_ineq_pos_hasta;
                    this.Baterias.IdRestriccionIPCResDescargaDesde(i, cont) = indice_ineq_pos_desde;

                    this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_descarga_desde:indice_descarga_hasta) = diag(ones(cant_po,1));
                    this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_carga_desde:indice_carga_hasta) = -diag(ones(cant_po,1));
                    this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_res_descarga_desde:indice_res_descarga_hasta) = diag(ones(cant_po,1));                
                    this.bineq(indice_ineq_pos_desde:indice_ineq_pos_hasta) = pmax_descarga;

                    if this.iNivelDebug > 0
                        this.ingresa_nombre_restriccion_desigualdad(this.Baterias.ElRed(i), indice_ineq_pos_desde, 'LimResPos', cont);
                    end

                    % 2. reservas negativas
                    % p_carga_bateria(t) - p_descarga_bateria(t) + p_carga_bateria_pc(t) <= Pmax_carga
                    indice_ineq_neg_desde = this.iIndiceIneq + 1;
                    indice_ineq_neg_hasta = this.iIndiceIneq + cant_po;
                    this.iIndiceIneq = indice_ineq_neg_hasta;
                    this.Baterias.IdRestriccionIPCResCargaDesde(i, cont) = indice_ineq_neg_desde;

                    this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_carga_desde:indice_carga_hasta) = diag(ones(cant_po,1));
                    this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_descarga_desde:indice_descarga_hasta) = -diag(ones(cant_po,1));
                    this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_res_carga_desde:indice_res_carga_hasta) = diag(ones(cant_po,1));                
                    this.bineq(indice_ineq_pos_desde:indice_ineq_pos_hasta) = pmax_carga;

                    if this.iNivelDebug > 0
                        this.ingresa_nombre_restriccion_desigualdad(this.Baterias.ElRed(i), indice_ineq_neg_desde, 'LimResNeg', cont);
                    end

                    if this.bConsideraDependenciaTemporal
                        % 3. Límite superior energía
                        % E(t) - 1/eta_descarga*p_descarga_bateria(t) + eta_carga*p_carga_bateria(t) + eta_carga*p_carga_pc(t) <= Emax                
                        indice_ineq_be_carga_desde = this.iIndiceIneq + 1;
                        indice_ineq_be_carga_hasta = this.iIndiceIneq + cant_po;
                        this.iIndiceIneq = indice_ineq_be_carga_hasta;
                        this.Baterias.IdRestriccionIPCResBalanceCargaDesde(i, cont) = indice_ineq_be_carga_desde;

                        this.Aineq(indice_ineq_be_carga_desde:indice_ineq_be_carga_hasta, indice_e_bateria_desde:indice_e_bateria_hasta) = diag(ones(cant_po,1));
                        this.Aineq(indice_ineq_be_carga_desde:indice_ineq_be_carga_hasta, indice_descarga_desde:indice_descarga_hasta) = round(-1/eta_descarga*diag(ones(cant_po,1)),dec_redondeo);
                        this.Aineq(indice_ineq_be_carga_desde:indice_ineq_be_carga_hasta, indice_carga_desde:indice_carga_hasta) = round(eta_carga*diag(ones(cant_po,1)),dec_redondeo);
                        this.Aineq(indice_ineq_be_carga_desde:indice_ineq_be_carga_hasta, indice_res_carga_desde:indice_res_carga_desde) = round(eta_carga*diag(ones(cant_po,1)),dec_redondeo);
                        this.bineq(indice_ineq_be_carga_desde:indice_ineq_be_carga_hasta) = energia_maxima_bateria;

                        if this.iNivelDebug > 0
                            this.ingresa_nombre_restriccion_desigualdad(this.Baterias.ElRed(i), indice_ineq_be_carga_desde, 'LimESupRes', cont);
                        end

                        % 4. Límite inferior energía                
                        % E(t) - 1/eta_descarga*p_descarga_bateria(t) + eta_carga*p_carga_bateria(t) - 1/eta_descarga*p_descarga_pc(t)  >= Emin
                        indice_ineq_be_descarga_desde = this.iIndiceIneq + 1;
                        indice_ineq_be_descarga_hasta = this.iIndiceIneq + cant_po;
                        this.iIndiceIneq = indice_ineq_be_descarga_hasta;
                        this.Baterias.IdRestriccionIPCResBalanceDescargaDesde(i, cont) = indice_ineq_be_descarga_desde;

                        this.Aineq(indice_ineq_be_descarga_desde:indice_ineq_be_descarga_hasta, indice_e_bateria_desde:indice_e_bateria_hasta) = -diag(ones(cant_po,1));
                        this.Aineq(indice_ineq_be_descarga_desde:indice_ineq_be_descarga_hasta, indice_descarga_desde:indice_descarga_hasta) = round(1/eta_descarga*diag(ones(cant_po,1)),dec_redondeo);
                        this.Aineq(indice_ineq_be_descarga_desde:indice_ineq_be_descarga_hasta, indice_carga_desde:indice_carga_hasta) = round(-eta_carga*diag(ones(cant_po,1)),dec_redondeo);
                        this.Aineq(indice_ineq_be_descarga_desde:indice_ineq_be_descarga_hasta, indice_res_descarga_desde:indice_res_descarga_desde) = round(1/eta_descarga*diag(ones(cant_po,1)),dec_redondeo);
                        this.bineq(indice_ineq_be_descarga_desde:indice_ineq_be_descarga_hasta) = -energia_minima_bateria;

                        if this.iNivelDebug > 0
                            this.ingresa_nombre_restriccion_desigualdad(this.Baterias.ElRed(i), indice_ineq_be_descarga_desde, 'LimEInfRes', cont);
                        end
                    end
                end
            end
        end

        function agrega_limites_baterias_pc(this, variable)
            % p_bateria_op_normal + p_bateria_pc tiene que mantenerse dentro de los límites
            % p_descarga_bateria - p_carga_bateria + p_descarga_bateria_pc <= Pmax_descarga
            % p_carga_bateria - p_descarga_bateria + p_carga_bateria_pc <= Pmax_carga
            
            % energía de la batería debe ser suficiente para operación normal y el despliegue de las reservas por una hora
            % E(t) - 1/eta_descarga*p_descarga_bateria(t) + eta_carga*p_carga_bateria(t) + eta_carga*p_carga_pc(t) <= Emax
            % E(t) - 1/eta_descarga*p_descarga_bateria(t) + eta_carga*p_carga_bateria(t) - 1/eta_descarga*p_descarga_pc(t)  >= Emin
            cant_po = this.iCantPuntosOperacion;
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            
            % potencias de la batería en operación normal
            indice_descarga_desde = this.Baterias.IdVarOptDesdeDescarga(this.Baterias.n);
            indice_descarga_hasta = indice_descarga_desde + cant_po - 1;
            indice_carga_desde = this.Baterias.IdVarOptDesdeCarga(this.Baterias.n);
            indice_carga_hasta = indice_carga_desde + cant_po - 1;

            eta_descarga = variable.entrega_eficiencia_descarga();
            eta_carga = variable.entrega_eficiencia_carga();
            pmax_carga = variable.entrega_pmax_carga()/this.Sbase;
            pmax_descarga = variable.entrega_pmax_descarga()/this.Sbase;
            energia_maxima_bateria = variable.entrega_capacidad()/this.Sbase;
            energia_minima_bateria = variable.entrega_energia_minima()/this.Sbase;

            % energía de la batería
            indice_e_bateria_desde = this.Baterias.IdVarOptDesdeE(this.Baterias.n);
            indice_e_bateria_hasta = indice_e_bateria_desde + cant_po - 1;

            for cont = 1:this.iCantContingenciasGenCons
                % reserva descarga y carga
                indice_res_descarga_desde = this.Baterias.IdVarOptPCResDescargaDesde(this.Baterias.n, cont);
                indice_res_descarga_hasta = indice_res_descarga_desde + cant_po - 1;
                indice_res_carga_desde = this.Baterias.IdVarOptPCResCargaDesde(this.Baterias.n, cont);
                indice_res_carga_hasta = indice_res_carga_desde + cant_po - 1;

                % 1. reservas positivas
                % p_descarga_bateria(t) - p_carga_bateria(t) + p_descarga_bateria_pc(t) <= Pmax_descarga
                indice_ineq_pos_desde = this.iIndiceIneq + 1;
                indice_ineq_pos_hasta = this.iIndiceIneq + cant_po;
                this.iIndiceIneq = indice_ineq_pos_hasta;
                this.Baterias.IdRestriccionIPCResDescargaDesde(this.Baterias.n, cont) = indice_ineq_pos_desde;

                this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_descarga_desde:indice_descarga_hasta) = diag(ones(cant_po,1));
                this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_carga_desde:indice_carga_hasta) = -diag(ones(cant_po,1));
                this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_res_descarga_desde:indice_res_descarga_hasta) = diag(ones(cant_po,1));                
                this.bineq(indice_ineq_pos_desde:indice_ineq_pos_hasta) = pmax_descarga;

                if this.iNivelDebug > 0
                    this.ingresa_nombre_restriccion_desigualdad(variable, indice_ineq_pos_desde, 'LimResPos', cont);
                end

                % 2. reservas negativas
                % p_carga_bateria(t) - p_descarga_bateria(t) + p_carga_bateria_pc(t) <= Pmax_carga
                indice_ineq_neg_desde = this.iIndiceIneq + 1;
                indice_ineq_neg_hasta = this.iIndiceIneq + cant_po;
                this.iIndiceIneq = indice_ineq_neg_hasta;
                this.Baterias.IdRestriccionIPCResCargaDesde(this.Baterias.n, cont) = indice_ineq_neg_desde;

                this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_carga_desde:indice_carga_hasta) = diag(ones(cant_po,1));
                this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_descarga_desde:indice_descarga_hasta) = -diag(ones(cant_po,1));
                this.Aineq(indice_ineq_pos_desde:indice_ineq_pos_hasta, indice_res_carga_desde:indice_res_carga_hasta) = diag(ones(cant_po,1));                
                this.bineq(indice_ineq_pos_desde:indice_ineq_pos_hasta) = pmax_carga;

                if this.iNivelDebug > 0
                    this.ingresa_nombre_restriccion_desigualdad(variable, indice_ineq_neg_desde, 'LimResNeg', cont);
                end

                if this.bConsideraDependenciaTemporal
                    % 3. Límite superior energía
                    % E(t) - 1/eta_descarga*p_descarga_bateria(t) + eta_carga*p_carga_bateria(t) + eta_carga*p_carga_pc(t) <= Emax                
                    indice_ineq_be_carga_desde = this.iIndiceIneq + 1;
                    indice_ineq_be_carga_hasta = this.iIndiceIneq + cant_po;
                    this.iIndiceIneq = indice_ineq_be_carga_hasta;
                    this.Baterias.IdRestriccionIPCResBalanceCargaDesde(this.Baterias.n, cont) = indice_ineq_be_carga_desde;

                    this.Aineq(indice_ineq_be_carga_desde:indice_ineq_be_carga_hasta, indice_e_bateria_desde:indice_e_bateria_hasta) = diag(ones(cant_po,1));
                    this.Aineq(indice_ineq_be_carga_desde:indice_ineq_be_carga_hasta, indice_descarga_desde:indice_descarga_hasta) = round(-1/eta_descarga*diag(ones(cant_po,1)),dec_redondeo);
                    this.Aineq(indice_ineq_be_carga_desde:indice_ineq_be_carga_hasta, indice_carga_desde:indice_carga_hasta) = round(eta_carga*diag(ones(cant_po,1)),dec_redondeo);
                    this.Aineq(indice_ineq_be_carga_desde:indice_ineq_be_carga_hasta, indice_res_carga_desde:indice_res_carga_desde) = round(eta_carga*diag(ones(cant_po,1)),dec_redondeo);
                    this.bineq(indice_ineq_be_carga_desde:indice_ineq_be_carga_hasta) = energia_maxima_bateria;

                    if this.iNivelDebug > 0
                        this.ingresa_nombre_restriccion_desigualdad(variable, indice_ineq_be_carga_desde, 'LimESupRes', cont);
                    end

                    % 4. Límite inferior energía                
                    % E(t) - 1/eta_descarga*p_descarga_bateria(t) + eta_carga*p_carga_bateria(t) - 1/eta_descarga*p_descarga_pc(t)  >= Emin
                    indice_ineq_be_descarga_desde = this.iIndiceIneq + 1;
                    indice_ineq_be_descarga_hasta = this.iIndiceIneq + cant_po;
                    this.iIndiceIneq = indice_ineq_be_descarga_hasta;
                    this.Baterias.IdRestriccionIPCResBalanceDescargaDesde(this.Baterias.n, cont) = indice_ineq_be_descarga_desde;

                    this.Aineq(indice_ineq_be_descarga_desde:indice_ineq_be_descarga_hasta, indice_e_bateria_desde:indice_e_bateria_hasta) = -diag(ones(cant_po,1));
                    this.Aineq(indice_ineq_be_descarga_desde:indice_ineq_be_descarga_hasta, indice_descarga_desde:indice_descarga_hasta) = round(1/eta_descarga*diag(ones(cant_po,1)),dec_redondeo);
                    this.Aineq(indice_ineq_be_descarga_desde:indice_ineq_be_descarga_hasta, indice_carga_desde:indice_carga_hasta) = round(-eta_carga*diag(ones(cant_po,1)),dec_redondeo);
                    this.Aineq(indice_ineq_be_descarga_desde:indice_ineq_be_descarga_hasta, indice_res_descarga_desde:indice_res_descarga_desde) = round(1/eta_descarga*diag(ones(cant_po,1)),dec_redondeo);
                    this.bineq(indice_ineq_be_descarga_desde:indice_ineq_be_descarga_hasta) = -energia_minima_bateria;

                    if this.iNivelDebug > 0
                        this.ingresa_nombre_restriccion_desigualdad(variable, indice_ineq_be_descarga_desde, 'LimEInfRes', cont);
                    end
                end
            end
        end
        
        function escribe_restriccion_tiempo_minimo_detencion_generadores(this, generador)
            [cant_periodos_representativos, ~] = size(this.vIndicesPOConsecutivos);
            n_gen = generador.entrega_id();

            tpo_minimo_detencion = this.Generadores.TiempoMinimoDetencion(n_gen);
            indice_uc_desde = this.Generadores.IdVarOptUCDesde(n_gen);

            primero = true;
            for periodo = 1:cant_periodos_representativos
                hora_desde_periodo = this.vIndicesPOConsecutivos(periodo,1);
                hora_hasta_periodo = this.vIndicesPOConsecutivos(periodo,2);
                ancho_periodo = hora_hasta_periodo - hora_desde_periodo + 1;

                indice_uc_desde_periodo_actual = indice_uc_desde + hora_desde_periodo - 1;

                for hora_rel = 2:ancho_periodo
                    hora = hora_desde_periodo + hora_rel-1;
                    indice_uc_t = indice_uc_desde_periodo_actual + hora_rel-1;
                    if hora_rel <= tpo_minimo_detencion
                        % generador no se puede encender en t si fue apagado la hora anterior (en t-1)
                        % UC(t) - UC(t-1) <= 0
                        this.iIndiceIneq = this.iIndiceIneq + 1;
                        if primero
                            this.Generadores.IdRestriccionITMinDetencionDesdeHasta(n_gen, 1) = this.iIndiceIneq;
                            primero = false;
                        end
                        this.Aineq(this.iIndiceIneq, indice_uc_t) = 1;
                        this.Aineq(this.iIndiceIneq, indice_uc_t-1) = -1;
                        this.bineq(this.iIndiceIneq) = 0;
                    else
                        % Si generador está apagado en t-1, se puede encender en t sólo si suma de horas apagadas es mayor a tiempo mínimo de detención
                        % TMIN*(UC(t) - UC(t-1)) + UC(t-1) + UC(t-2) + ... + UC(t-TMIN) <= TMIN
                        this.iIndiceIneq = this.iIndiceIneq + 1;
                        this.bineq(this.iIndiceIneq) = tpo_minimo_detencion;
                        this.Aineq(this.iIndiceIneq, indice_uc_t) = tpo_minimo_detencion;
                        this.Aineq(this.iIndiceIneq, indice_uc_t-1) = 1-tpo_minimo_detencion;
                        this.Aineq(this.iIndiceIneq,indice_uc_t-tpo_minimo_detencion:indice_uc_t-2) = 1;
                    end
                    if this.iNivelDebug > 0
                        this.ingresa_nombre_restriccion_desigualdad(generador, this.iIndiceIneq, 'TMinDetencion', hora);
                    end
                end
            end
            this.Generadores.IdRestriccionITMinDetencionDesdeHasta(n_gen, 2) = this.iIndiceIneq;
        end

        function agrega_restriccion_tiempo_minimo_detencion_generadores(this, variable, indice_uc_desde)
            [cant_periodos_representativos, ~] = size(this.vIndicesPOConsecutivos);

            n_gen = variable.entrega_id();
            tpo_minimo_detencion = this.Generadores.TiempoMinimoDetencion(n_gen);

            primero = true;
            for periodo = 1:cant_periodos_representativos
                hora_desde_periodo = this.vIndicesPOConsecutivos(periodo,1);
                hora_hasta_periodo = this.vIndicesPOConsecutivos(periodo,2);
                ancho_periodo = hora_hasta_periodo - hora_desde_periodo + 1;

                indice_uc_desde_periodo_actual = indice_uc_desde + hora_desde_periodo - 1;

                for hora_rel = 2:ancho_periodo
                    hora = hora_desde_periodo + hora_rel-1;
                    indice_uc_t = indice_uc_desde_periodo_actual + hora_rel-1;
                    if hora_rel <= tpo_minimo_detencion
                        % generador no se puede encender en t si fue apagado la hora anterior (en t-1)
                        % UC(t) - UC(t-1) <= 0
                        this.iIndiceIneq = this.iIndiceIneq + 1;
                        if primero
                            this.Generadores.IdRestriccionITMinDetencionDesdeHasta(n_gen, 1) = this.iIndiceIneq;
                            primero = false;
                        end
                        this.Aineq(this.iIndiceIneq, indice_uc_t) = 1;
                        this.Aineq(this.iIndiceIneq, indice_uc_t-1) = -1;
                        this.bineq(this.iIndiceIneq) = 0;
                    else
                        % Si generador está apagado en t-1, se puede encender en t sólo si suma de horas apagadas es mayor a tiempo mínimo de detención
                        % TMIN*(UC(t) - UC(t-1)) + UC(t-1) + UC(t-2) + ... + UC(t-TMIN) <= TMIN
                        this.iIndiceIneq = this.iIndiceIneq + 1;
                        this.bineq(this.iIndiceIneq) = tpo_minimo_detencion;
                        this.Aineq(this.iIndiceIneq, indice_uc_t) = tpo_minimo_detencion;
                        this.Aineq(this.iIndiceIneq, indice_uc_t-1) = 1-tpo_minimo_detencion;
                        this.Aineq(this.iIndiceIneq,indice_uc_t-tpo_minimo_detencion:indice_uc_t-2) = 1;
                    end
                    if this.iNivelDebug > 0
                        this.ingresa_nombre_restriccion_desigualdad(variable, this.iIndiceIneq, 'TMinDetencion', hora);
                    end
                end
            end
            this.Generadores.IdRestriccionITMinDetencionDesdeHasta(n_gen, 2) = this.iIndiceIneq;
        end
        
        function escribe_restriccion_tiempo_minimo_operacion_generadores(this, generador)
            [cant_periodos_representativos, ~] = size(this.vIndicesPOConsecutivos);
            n_gen = generador.entrega_id();
            
            tpo_minimo_operacion = this.Generadores.TiempoMinimoOperacion(n_gen);
            indice_uc_desde = this.Generadores.IdVarOptUCDesde(n_gen);

            primero = true;
            for periodo = 1:cant_periodos_representativos
                hora_desde_periodo = this.vIndicesPOConsecutivos(periodo,1);
                hora_hasta_periodo = this.vIndicesPOConsecutivos(periodo,2);
                ancho_periodo = hora_hasta_periodo - hora_desde_periodo + 1;

                indice_uc_desde_periodo_actual = indice_uc_desde + hora_desde_periodo - 1;

                for hora_rel = 2:ancho_periodo
                    hora = hora_desde_periodo + hora_rel - 1;
                    indice_uc_t = indice_uc_desde_periodo_actual + hora_rel-1;
                    if hora_rel <= tpo_minimo_operacion
                        % generador no se puede apagar si fue encendido la hora anterior
                        % UC(t-1) - UC(t) <= 0
                        this.iIndiceIneq = this.iIndiceIneq + 1;
                        if primero
                            this.Generadores.IdRestriccionITMinOperacionDesdeHasta(n_gen,1) = this.iIndiceIneq;
                            primero = false;
                        end

                        this.Aineq(this.iIndiceIneq, indice_uc_t-1) = 1;
                        this.Aineq(this.iIndiceIneq, indice_uc_t) = -1;
                        this.bineq(this.iIndiceIneq) = 0;
                    else
                        % Si generador está encendido en t-1, se puede apagar en t sólo si suma de horas en operación es mayor a tiempo mínimo de operación
                        % TMIN*(UC(t-1) - UC(t)) - UC(t-1) - UC(t-2) - ... - UC(t-tmin) <= 0
                        this.iIndiceIneq = this.iIndiceIneq + 1;
                        this.bineq(this.iIndiceIneq) = 0;
                        this.Aineq(this.iIndiceIneq, indice_uc_t-1) = tpo_minimo_operacion-1;
                        this.Aineq(this.iIndiceIneq, indice_uc_t) = -tpo_minimo_operacion;
                        this.Aineq(this.iIndiceIneq,indice_uc_t-tpo_minimo_operacion:indice_uc_t-2) = -1;
                    end
                    if this.iNivelDebug > 0
                        this.ingresa_nombre_restriccion_desigualdad(generador, this.iIndiceIneq, 'TMinOperacion', hora);
                    end
                end
            end
            this.Generadores.IdRestriccionITMinOperacionDesdeHasta(n_gen,2) = this.iIndiceIneq;
        end

        function agrega_restriccion_tiempo_minimo_operacion_generadores(this, variable, indice_uc_desde)
            [cant_periodos_representativos, ~] = size(this.vIndicesPOConsecutivos);

            n_gen = variable.entrega_id();
            tpo_minimo_operacion = this.Generadores.TiempoMinimoOperacion(n_gen);

            primero = true;
            for periodo = 1:cant_periodos_representativos
                hora_desde_periodo = this.vIndicesPOConsecutivos(periodo,1);
                hora_hasta_periodo = this.vIndicesPOConsecutivos(periodo,2);
                ancho_periodo = hora_hasta_periodo - hora_desde_periodo + 1;

                indice_uc_desde_periodo_actual = indice_uc_desde + hora_desde_periodo - 1;

                for hora_rel = 2:ancho_periodo
                    hora = hora_desde_periodo + hora_rel - 1;
                    indice_uc_t = indice_uc_desde_periodo_actual + hora_rel-1;
                    if hora_rel <= tpo_minimo_operacion
                        % generador no se puede apagar si fue encendido la hora anterior
                        % UC(t-1) - UC(t) <= 0
                        this.iIndiceIneq = this.iIndiceIneq + 1;
                        if primero
                            this.Generadores.IdRestriccionITMinOperacionDesdeHasta(n_gen,1) = this.iIndiceIneq;
                            primero = false;
                        end
                        this.Aineq(this.iIndiceIneq, indice_uc_t-1) = 1;
                        this.Aineq(this.iIndiceIneq, indice_uc_t) = -1;
                        this.bineq(this.iIndiceIneq) = 0;
                    else
                        % Si generador está encendido en t-1, se puede apagar en t sólo si suma de horas en operación es mayor a tiempo mínimo de operación
                        % TMIN*(UC(t-1) - UC(t)) - UC(t-1) - UC(t-2) - ... - UC(t-tmin) <= 0
                        this.iIndiceIneq = this.iIndiceIneq + 1;
                        this.bineq(this.iIndiceIneq) = 0;
                        this.Aineq(this.iIndiceIneq, indice_uc_t-1) = tpo_minimo_operacion-1;
                        this.Aineq(this.iIndiceIneq, indice_uc_t) = -tpo_minimo_operacion;
                        this.Aineq(this.iIndiceIneq,indice_uc_t-tpo_minimo_operacion:indice_uc_t-2) = -1;
                    end
                    if this.iNivelDebug > 0
                        this.ingresa_nombre_restriccion_desigualdad(variable, this.iIndiceIneq, 'TMinOperacion', hora);
                    end
                end
            end
            this.Generadores.IdRestriccionITMinOperacionDesdeHasta(n_gen,2) = this.iIndiceIneq;
        end
        
        function escribe_restriccion_costo_partida_generadores(this, generador)
            cant_po = this.iCantPuntosOperacion;
            n_gen = generador.entrega_id();
            [cant_periodos_representativos, ~] = size(this.vIndicesPOConsecutivos);
            indice_cpartida_desde = this.Generadores.IdVarOptCostoPartidaDesde(n_gen);
            indice_cpartida_hasta = indice_cpartida_desde + cant_po - 1;

            indice_uc_desde = this.Generadores.IdVarOptUCDesde(n_gen);
            indice_uc_hasta = indice_uc_desde + cant_po - 1;

            % CPartida(t) >= CPARTIDA(UC(t) - UC(t-1))
            % -CPartida(t) + CPARTIDA*UC(t) - CPARTIDA*UC(t-1) <= 0

            %costo_partida = this.Generadores.ElRed(id_validos(i)).entrega_costo_partida()*this.Sbase;

            indice_ineq_desde = this.iIndiceIneq + 1;
            indice_ineq_hasta = this.iIndiceIneq + cant_po;
            this.iIndiceIneq = indice_ineq_hasta;

            this.Generadores.IdRestriccionICostoPartidaDesde(n_gen) = indice_ineq_desde;

            this.Aineq(indice_ineq_desde:indice_ineq_hasta,indice_cpartida_desde:indice_cpartida_hasta) = -diag(ones(cant_po,1));
            %this.Aineq(indice_ineq_desde:indice_ineq_hasta,indice_uc_desde:indice_uc_hasta) = -costo_partida*diag(ones(cant_po,1));
            %this.Aineq(indice_ineq_desde:indice_ineq_hasta,indice_uc_desde-1:indice_uc_hasta-1) = costo_partida*diag(ones(cant_po,1));
            this.Aineq(indice_ineq_desde:indice_ineq_hasta,indice_uc_desde:indice_uc_hasta) = diag(ones(cant_po,1));
            this.Aineq(indice_ineq_desde:indice_ineq_hasta,indice_uc_desde-1:indice_uc_hasta-1) = ...
                this.Aineq(indice_ineq_desde:indice_ineq_hasta,indice_uc_desde-1:indice_uc_hasta-1) - diag(ones(cant_po,1));

            this.bineq(indice_ineq_desde:indice_ineq_hasta) = 0;

            % costo de partida al comienzo de cada periodo es cero
            indices_a_corregir = indice_ineq_desde -1 + this.vIndicesPOConsecutivos(:,1);
            for periodo = 1:cant_periodos_representativos
                indice_uc_desde_actual = indice_uc_desde + this.vIndicesPOConsecutivos(periodo,1)-1;

                this.Aineq(indices_a_corregir(periodo), indice_uc_desde_actual) = 0;
                this.Aineq(indices_a_corregir(periodo), indice_uc_desde_actual-1) = 0;
            end

            if this.iNivelDebug > 0
                this.ingresa_nombre_restriccion_desigualdad(generador, indice_ineq_desde, 'CPartida');
            end
        end

        function agrega_restriccion_costo_partida_generadores(this, variable, indice_cpartida_desde, indice_cpartida_hasta, indice_uc_desde, indice_uc_hasta)
            cant_po = this.iCantPuntosOperacion;
            [cant_periodos_representativos, ~] = size(this.vIndicesPOConsecutivos);            

            % CPartida(t) >= CPARTIDA(UC(t) - UC(t-1))
            % -CPartida(t) + CPARTIDA*UC(t) - CPARTIDA*UC(t-1) <= 0

            indice_ineq_desde = this.iIndiceIneq + 1;
            indice_ineq_hasta = this.iIndiceIneq + cant_po;
            this.iIndiceIneq = indice_ineq_hasta;

            this.Generadores.IdRestriccionICostoPartidaDesde(variable.entrega_id()) = indice_ineq_desde;
            
            this.Aineq(indice_ineq_desde:indice_ineq_hasta,indice_cpartida_desde:indice_cpartida_hasta) = -diag(ones(cant_po,1));
            this.Aineq(indice_ineq_desde:indice_ineq_hasta,indice_uc_desde:indice_uc_hasta) = diag(ones(cant_po,1));
            this.Aineq(indice_ineq_desde:indice_ineq_hasta,indice_uc_desde-1:indice_uc_hasta-1) = ...
                this.Aineq(indice_ineq_desde:indice_ineq_hasta,indice_uc_desde-1:indice_uc_hasta-1) - diag(ones(cant_po,1));

            this.bineq(indice_ineq_desde:indice_ineq_hasta) = 0;

            % costo de partida al comienzo de cada periodo es cero
            indices_a_corregir = indice_ineq_desde -1 + this.vIndicesPOConsecutivos(:,1);
            for periodo = 1:cant_periodos_representativos
                indice_uc_desde_actual = indice_uc_desde + this.vIndicesPOConsecutivos(periodo,1)-1;

                this.Aineq(indices_a_corregir(periodo), indice_uc_desde_actual) = 0;
                this.Aineq(indices_a_corregir(periodo), indice_uc_desde_actual-1) = 0;
            end

            if this.iNivelDebug > 0
                this.ingresa_nombre_restriccion_desigualdad(variable, indice_ineq_desde, 'CPartida');
            end
        end
        
        function escribe_restriccion_potencias_min_max_generadores_n0(this, generador)
            cant_po = this.iCantPuntosOperacion;
            n_gen = generador.entrega_id();
            indice_p_desde = this.Generadores.IdVarOptDesde(n_gen);
            indice_p_hasta = indice_p_desde + cant_po - 1;

            indice_uc_desde = this.Generadores.IdVarOptUCDesde(n_gen);
            indice_uc_hasta = indice_uc_desde + cant_po - 1;

            % Límite Pmax
            % P - UC*PMAX <= 0
            indice_ineq_desde = this.iIndiceIneq + 1;
            indice_ineq_hasta = this.iIndiceIneq + cant_po;
            this.iIndiceIneq = indice_ineq_hasta;

            this.Generadores.IdRestriccionIPotenciasUCDesde(n_gen) = indice_ineq_desde;

            this.Aineq(indice_ineq_desde:indice_ineq_hasta,indice_p_desde:indice_p_hasta) = diag(ones(cant_po,1));
            this.Aineq(indice_ineq_desde:indice_ineq_hasta,indice_uc_desde:indice_uc_hasta) = -this.Generadores.Pmax(n_gen)*diag(ones(cant_po,1));

            this.bineq(indice_ineq_desde:indice_ineq_hasta) = 0;

            if this.iNivelDebug > 0
                this.ingresa_nombre_restriccion_desigualdad(generador, indice_ineq_desde, 'Pmax');
            end

            % Límite Pmin
            % P -UC*PMIN >= 0 ==> UC*PMIN - P <= 0
            indice_ineq_desde = this.iIndiceIneq + 1;
            indice_ineq_hasta = this.iIndiceIneq + cant_po;
            this.iIndiceIneq = indice_ineq_hasta;

            this.Aineq(indice_ineq_desde:indice_ineq_hasta,indice_p_desde:indice_p_hasta) = -diag(ones(cant_po,1));
            this.Aineq(indice_ineq_desde:indice_ineq_hasta,indice_uc_desde:indice_uc_hasta) = this.Generadores.Pmin(n_gen)*diag(ones(cant_po,1));

            this.bineq(indice_ineq_desde:indice_ineq_hasta) = 0;

            if this.iNivelDebug > 0
                this.ingresa_nombre_restriccion_desigualdad(generador, indice_ineq_desde, 'Pmin');
            end
        end

        function agrega_restriccion_potencias_min_max_generadores_n0(this, variable, indice_p_desde, indice_p_hasta, indice_uc_desde, indice_uc_hasta)
            cant_po = this.iCantPuntosOperacion;
            n_gen = variable.entrega_id();
            
            % Límite Pmax
            % P - UC*PMAX <= 0
            indice_ineq_desde = this.iIndiceIneq + 1;
            indice_ineq_hasta = this.iIndiceIneq + cant_po;
            this.iIndiceIneq = indice_ineq_hasta;

            this.Generadores.IdRestriccionIPotenciasUCDesde(n_gen) = indice_ineq_desde;
            
            this.Aineq(indice_ineq_desde:indice_ineq_hasta,indice_p_desde:indice_p_hasta) = diag(ones(cant_po,1));
            this.Aineq(indice_ineq_desde:indice_ineq_hasta,indice_uc_desde:indice_uc_hasta) = -this.Generadores.Pmax(n_gen)*diag(ones(cant_po,1));

            this.bineq(indice_ineq_desde:indice_ineq_hasta) = 0;

            if this.iNivelDebug > 0
                this.ingresa_nombre_restriccion_desigualdad(variable, indice_ineq_desde, 'Pmax');
            end

            % Límite Pmin
            % P -UC*PMIN >= 0 ==> UC*PMIN - P <= 0
            indice_ineq_desde = this.iIndiceIneq + 1;
            indice_ineq_hasta = this.iIndiceIneq + cant_po;
            this.iIndiceIneq = indice_ineq_hasta;

            this.Aineq(indice_ineq_desde:indice_ineq_hasta,indice_p_desde:indice_p_hasta) = -diag(ones(cant_po,1));
            this.Aineq(indice_ineq_desde:indice_ineq_hasta,indice_uc_desde:indice_uc_hasta) = this.Generadores.Pmin(n_gen)*diag(ones(cant_po,1));

            this.bineq(indice_ineq_desde:indice_ineq_hasta) = 0;

            if this.iNivelDebug > 0
                this.ingresa_nombre_restriccion_desigualdad(variable, indice_ineq_desde, 'Pmin');
            end
        end
        
        function escribe_balance_energia(this)
            cant_po = this.iCantPuntosOperacion;
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            for i = 1:this.Subestaciones.n
                indice_eq_desde = this.iIndiceEq +1;
                indice_eq_hasta = this.iIndiceEq + cant_po;
                this.iIndiceEq = indice_eq_hasta;
                this.Subestaciones.IdRestriccionEBalanceDesde(i) = indice_eq_desde;

                consumo_residual_p = zeros(cant_po,1);
                
                % Balance de potencia activa en bus
                % generadores
                pGeneradores = this.Subestaciones.ElRed(i).entrega_generadores_despachables();
                for j = 1:length(pGeneradores)
                    indice_gen_desde = this.Generadores.IdVarOptDesde(pGeneradores(j).entrega_id());
                    indice_gen_hasta = indice_gen_desde + cant_po -1;
                    %this.Aeq(indice_eq_desde:indice_eq_hasta,indice_gen_desde:indice_gen_hasta) = diag(ones(cant_po,1));
                    indices = sub2ind(size(this.Aeq), indice_eq_desde:indice_eq_hasta,indice_gen_desde:indice_gen_hasta);
                    this.Aeq(indices) = 1;
                    %for oper = 1:cant_po
                    %    this.Aeq(indice_eq_desde + oper - 1,indice_gen_desde + oper - 1) = 1;
                    %end
                end

                % baterías
                pBaterias = this.Subestaciones.ElRed(i).entrega_baterias();
                for j = 1:length(pBaterias)
                    indice_bat_descarga_desde = this.Baterias.IdVarOptDesdeDescarga(pBaterias(j).entrega_id());
                    indice_bat_descarga_hasta = indice_bat_descarga_desde + cant_po -1;
                    indice_bat_carga_desde = this.Baterias.IdVarOptDesdeCarga(pBaterias(j).entrega_id());
                    indice_bat_carga_hasta = indice_bat_carga_desde + cant_po -1;
                    this.Aeq(indice_eq_desde:indice_eq_hasta,indice_bat_descarga_desde:indice_bat_descarga_hasta) = diag(ones(cant_po,1));
                    this.Aeq(indice_eq_desde:indice_eq_hasta,indice_bat_carga_desde:indice_bat_carga_hasta) = -diag(ones(cant_po,1));
                end
                
                %ENS
                pConsumos = this.Subestaciones.ElRed(i).entrega_consumos();
                for j = 1:length(pConsumos)
                    id_consumo = pConsumos(j).entrega_id();
                    
                    % primerio ENS y después consumo residual
                    indice_consumo_desde = this.Consumos.IdVarOptDesde(id_consumo);
                    indice_consumo_hasta = indice_consumo_desde + cant_po -1;
                    this.Aeq(indice_eq_desde:indice_eq_hasta,indice_consumo_desde:indice_consumo_hasta) = diag(ones(cant_po,1));

                    % consumo residual
                    perfil_consumo = this.Consumos.IdAdmEscenarioPerfil(id_consumo);
                    if  perfil_consumo ~= 0
                        perfil = this.pAdmSc.entrega_perfil_consumo(perfil_consumo);
                        valor_elemento = this.Consumos.Pmax(id_consumo)*perfil;
                    else
                        % datos locales
                        valor_elemento = pConsumos(j).entrega_p_const_nom_pu(); %valor positivo
                    end
 
                    consumo_residual_p = consumo_residual_p + valor_elemento';
                end
                
                % Generadores RES.
                pGeneradores_ernc = this.Subestaciones.ElRed(i).entrega_generadores_res();
                for j = 1:length(pGeneradores_ernc)
                    % primero recorte res
                    id_gen_res = pGeneradores_ernc(j).entrega_id();
                    indice_generador_desde = this.Generadores.IdVarOptDesde(id_gen_res);
                    indice_generador_hasta = indice_generador_desde + cant_po - 1;
                    this.Aeq(indice_eq_desde:indice_eq_hasta,indice_generador_desde:indice_generador_hasta) = -diag(ones(cant_po,1));
                    
                    %consumo residual
                    id_perfil = this.Generadores.IdAdmEscenarioPerfil(id_gen_res);
                    if id_perfil ~= 0
                        perfil = this.pAdmSc.entrega_perfil_ernc(id_perfil);
                        valor_elemento = this.Generadores.Pmax(id_gen_res)*perfil;
                    else
                        % quiere decir que datos son locales
                        valor_elemento = this.Generadores.ElRed(id_gen_res).entrega_p_const_nom_opf(); % ya está en pu
                    end
                    consumo_residual_p = consumo_residual_p - valor_elemento';
                end
                
                this.beq(indice_eq_desde:indice_eq_hasta) = round(consumo_residual_p,dec_redondeo);

                % elementos serie
                eserie = this.Subestaciones.ElRed(i).entrega_elementos_serie();
                for j = 1:length(eserie)
                    id_eserie = eserie(j).entrega_id();
                    if isa(eserie(j),'cLinea')
                        indice_eserie_p_desde = this.Lineas.IdVarOptDesde(id_eserie);
                    else
                        indice_eserie_p_desde = this.Trafos.IdVarOptDesde(id_eserie);
                    end
                    indice_eserie_p_hasta = indice_eserie_p_desde + cant_po - 1;
                    
                    se1 = eserie(j).entrega_se1();
                    se2 = eserie(j).entrega_se2();
                    if se1 == this.Subestaciones.ElRed(i)
                        % inicio linea corresponde a este bus, por lo tanto
                        % flujo sale
                        signo = -1;
                    elseif se2 == this.Subestaciones.ElRed(i)
                        signo = 1;
                    else
                        error = MException('cOPF:escribe_balance_energia','Inconsistencia en los datos, ya que elemento serie no pertenece a bus');
                        throw(error)
                    end
                    
                    this.Aeq(indice_eq_desde:indice_eq_hasta,indice_eserie_p_desde:indice_eserie_p_hasta) = signo*diag(ones(cant_po,1));
                    %for oper = 1:cant_po
                    %    this.Aeq(indice_eq_desde + oper - 1,indice_eserie_p_desde + oper - 1) = signo;
                    %end
                end
                
                if this.iNivelDebug > 0
                    this.ingresa_nombre_restriccion_igualdad(this.Subestaciones.ElRed(i), indice_eq_desde);
                end
            end
        end

        function escribe_balance_energia_n1(this)
            cant_po = this.iCantPuntosOperacion;
            for i = 1:this.Subestaciones.n
                indice_eq_desde_base = this.Subestaciones.IdRestriccionEBalanceDesde(i);
                indice_eq_hasta_base = indice_eq_desde_base + cant_po - 1;
                for cont = 1:this.iCantContingenciasElSerie
                    indice_eq_desde = this.iIndiceEq +1;
                    indice_eq_hasta = this.iIndiceEq + cant_po;
                    this.iIndiceEq = indice_eq_hasta;
                    this.Subestaciones.IdRestriccionEBalanceN1Desde(i,cont) = indice_eq_desde;

                    % copia ecuaciones de balance de energía base y reemplaza índices de subestaciones, líneas y trafos
                    this.Aeq(indice_eq_desde:indice_eq_hasta,:) = this.Aeq(indice_eq_desde_base:indice_eq_hasta_base,:);
                    this.beq(indice_eq_desde:indice_eq_hasta) = this.beq(indice_eq_desde_base:indice_eq_hasta_base);
                    
                    % corrige elementos serie
                    eserie = this.Subestaciones.ElRed(i).entrega_elementos_serie();
                    for j = 1:length(eserie)
                        id_eserie = eserie(j).entrega_id();
                        if isa(eserie(j),'cLinea')
                            indice_eserie_p_desde_base = this.Lineas.IdVarOptDesde(id_eserie);
                            indice_eserie_p_desde = this.Lineas.IdVarOptN1Desde(id_eserie, cont);
                        else
                            indice_eserie_p_desde_base = this.Trafos.IdVarOptDesde(id_eserie);
                            indice_eserie_p_desde = this.Trafos.IdVarOptN1Desde(id_eserie, cont);
                        end
                        indice_eserie_p_hasta = indice_eserie_p_desde + cant_po - 1;
                        indice_eserie_p_hasta_base = indice_eserie_p_desde_base + cant_po - 1;
                    
                        se1 = eserie(j).entrega_se1();
                        se2 = eserie(j).entrega_se2();
                        if se1 == this.Subestaciones.ElRed(i)
                            % inicio linea corresponde a este bus, por lo tanto
                            % flujo sale
                            signo = -1;
                        elseif se2 == this.Subestaciones.ElRed(i)
                            signo = 1;
                        else
                            error = MException('cOPF:escribe_balance_energia_n1','Inconsistencia en los datos, ya que elemento serie no pertenece a bus');
                            throw(error)
                        end
                    
                        this.Aeq(indice_eq_desde:indice_eq_hasta,indice_eserie_p_desde_base:indice_eserie_p_hasta_base) = diag(zeros(cant_po,1));
                        if indice_eserie_p_desde > 0
                            this.Aeq(indice_eq_desde:indice_eq_hasta,indice_eserie_p_desde:indice_eserie_p_hasta) = signo*diag(ones(cant_po,1));
                        end
                        %for oper = 1:cant_po
                        %    this.Aeq(indice_eq_desde + oper - 1,indice_eserie_p_desde + oper - 1) = signo;
                        %end
                    end                    
                    if this.iNivelDebug > 0
                        this.ingresa_nombre_restriccion_igualdad(this.Subestaciones.ElRed(i), indice_eq_desde, 'n1', cont);
                    end
                end
            end
        end

        function escribe_balance_energia_pc(this)
            cant_po = this.iCantPuntosOperacion;
            for i = 1:this.Subestaciones.n
                pGeneradores = this.Subestaciones.ElRed(i).entrega_generadores_despachables();
                pBaterias = this.Subestaciones.ElRed(i).entrega_baterias();
                pConsumos = this.Subestaciones.ElRed(i).entrega_consumos();
                pGeneradores_ernc = this.Subestaciones.ElRed(i).entrega_generadores_res();
                eserie = this.Subestaciones.ElRed(i).entrega_elementos_serie();

                % copia consumo residual de ecuación base
                indice_eq_desde_base = this.Subestaciones.IdRestriccionEBalanceDesde(i);
                indice_eq_hasta_base = indice_eq_desde_base + cant_po - 1;
                beq_base = this.beq(indice_eq_desde_base:indice_eq_hasta_base);
                
                for cont = 1:this.iCantContingenciasGenCons
                    indice_eq_desde = this.iIndiceEq +1;
                    indice_eq_hasta = this.iIndiceEq + cant_po;
                    this.iIndiceEq = indice_eq_hasta;
                    
                    this.Subestaciones.IdRestriccionEBalancePCDesde(i,cont) = indice_eq_desde;
                    this.beq(indice_eq_desde:indice_eq_hasta) = beq_base;

                    for j = 1:length(pGeneradores)
                        % operacion normal
                        indice_gen_desde = this.Generadores.IdVarOptDesde(pGeneradores(j).entrega_id());
                        indice_gen_hasta = indice_gen_desde + cant_po -1;
                        this.Aeq(indice_eq_desde:indice_eq_hasta,indice_gen_desde:indice_gen_hasta) = diag(ones(cant_po,1));
                        
                        % despliegue de reservas positivas
                        indice_gen_res_pos_desde = this.Generadores.IdVarOptPCResPosDesde(pGeneradores(j).entrega_id(), cont);
                        if indice_gen_res_pos_desde > 0
                            indice_gen_res_pos_hasta = indice_gen_res_pos_desde + cant_po -1;
                            this.Aeq(indice_eq_desde:indice_eq_hasta,indice_gen_res_pos_desde:indice_gen_res_pos_hasta) = diag(ones(cant_po,1));
                        
                            % si puede entregar reservas positivas, entonces también puede entregar reservas negativas
                            indice_gen_res_neg_desde = this.Generadores.IdVarOptPCResNegDesde(pGeneradores(j).entrega_id(), cont);
                            indice_gen_res_neg_hasta = indice_gen_res_neg_desde + cant_po - 1;
                            this.Aeq(indice_eq_desde:indice_eq_hasta,indice_gen_res_neg_desde:indice_gen_res_neg_hasta) = -diag(ones(cant_po,1));
                        end
                    end

                    for j = 1:length(pBaterias)
                        indice_bat_descarga_desde = this.Baterias.IdVarOptDesdeDescarga(pBaterias(j).entrega_id());
                        indice_bat_descarga_hasta = indice_bat_descarga_desde + cant_po -1;
                        indice_bat_carga_desde = this.Baterias.IdVarOptDesdeCarga(pBaterias(j).entrega_id());
                        indice_bat_carga_hasta = indice_bat_carga_desde + cant_po -1;
                        this.Aeq(indice_eq_desde:indice_eq_hasta,indice_bat_descarga_desde:indice_bat_descarga_hasta) = diag(ones(cant_po,1));
                        this.Aeq(indice_eq_desde:indice_eq_hasta,indice_bat_carga_desde:indice_bat_carga_hasta) = -diag(ones(cant_po,1));
                        
                        % reservas positivas y negativas
                        indice_bat_res_descarga_desde = this.Baterias.IdVarOptResDescargaDesde(pBaterias(j).entrega_id(), cont);
                        indice_bat_res_descarga_hasta = indice_bat_res_descarga_desde + cant_po -1;
                        indice_bat_res_carga_desde = this.Baterias.IdVarOptResCargaDesde(pBaterias(j).entrega_id(), cont);
                        indice_bat_res_carga_hasta = indice_bat_res_carga_desde + cant_po -1;
                        this.Aeq(indice_eq_desde:indice_eq_hasta,indice_bat_res_descarga_desde:indice_bat_res_descarga_hasta) = diag(ones(cant_po,1));
                        this.Aeq(indice_eq_desde:indice_eq_hasta,indice_bat_res_carga_desde:indice_bat_res_carga_hasta) = -diag(ones(cant_po,1));
                    end

                    for j = 1:length(pConsumos)
                        % sólo ENS, ya que beq ya se determinó
                        id_consumo = pConsumos(j).entrega_id();
                        indice_consumo_desde = this.Consumos.IdVarOptPCDesde(id_consumo, cont);
                        indice_consumo_hasta = indice_consumo_desde + cant_po -1;
                        this.Aeq(indice_eq_desde:indice_eq_hasta,indice_consumo_desde:indice_consumo_hasta) = diag(ones(cant_po,1));
                    end

                    for j = 1:length(pGeneradores_ernc)
                        % Sólo recorte (reservas negativas)
                        id_gen_res = pGeneradores_ernc(j).entrega_id();
                        indice_generador_desde = this.Generadores.IdVarOptPCResNegDesde(id_gen_res, cont);
                        indice_generador_hasta = indice_generador_desde + cant_po - 1;
                        this.Aeq(indice_eq_desde:indice_eq_hasta,indice_generador_desde:indice_generador_hasta) = -diag(ones(cant_po,1));
                    end

                    for j = 1:length(eserie)
                        id_eserie = eserie(j).entrega_id();
                        if isa(eserie(j),'cLinea')
                            indice_eserie_p_desde = this.Lineas.IdVarOptPCDesde(id_eserie, cont);
                        else
                            indice_eserie_p_desde = this.Trafos.IdVarOptPCDesde(id_eserie, cont);
                        end
                        indice_eserie_p_hasta = indice_eserie_p_desde + cant_po - 1;

                        se1 = eserie(j).entrega_se1();
                        if se1 == this.Subestaciones.ElRed(i)
                            % inicio linea corresponde a este bus, por lo tanto
                            % flujo sale
                            signo = -1;
                        else
                            signo = 1;
                        end

                        this.Aeq(indice_eq_desde:indice_eq_hasta,indice_eserie_p_desde:indice_eserie_p_hasta) = signo*diag(ones(cant_po,1));
                        %for oper = 1:cant_po
                        %    this.Aeq(indice_eq_desde + oper - 1,indice_eserie_p_desde + oper - 1) = signo;
                        %end
                    end

                    if this.iNivelDebug > 0
                        this.ingresa_nombre_restriccion_igualdad(this.Subestaciones.ElRed(i), indice_eq_desde, 'pc', cont);
                    end
                end
            end
        end

        function agrega_generador_a_balance_energia_pc(this, variable)
            cant_po = this.iCantPuntosOperacion;
            id_se = variable.entrega_se().entrega_id();
            
            if variable.Despachable
                indice_p_desde = this.Generadores.IdVarOptDesde(this.Generadores.n);
                indice_p_hasta = indice_p_desde + cant_po -1;
                for cont = 1:this.iCantContingenciasGenCons
                    indice_eq_desde = this.Subestaciones.IdRestriccionEBalancePCDesde(id_se,cont);
                    indice_eq_hasta = indice_eq_desde + cant_po - 1;

                    this.Aeq(indice_eq_desde:indice_eq_hasta,indice_p_desde:indice_p_hasta) = diag(ones(cant_po,1));

                    indice_res_pos_desde = this.Generadores.IdVarOptPCResPosDesde(this.Generadores.n, cont);                    
                    if indice_res_pos_desde > 0
                        indice_res_pos_hasta = indice_res_pos_desde + cant_po -1;
                        this.Aeq(indice_eq_desde:indice_eq_hasta,indice_res_pos_desde:indice_res_pos_hasta) = diag(ones(cant_po,1));

                        indice_res_neg_desde = this.Generadores.IdVarOptPCResNegDesde(this.Generadores.n);                    
                        indice_res_neg_hasta = indice_res_neg_desde + cant_po - 1;
                        this.Aeq(indice_eq_desde:indice_eq_hasta,indice_res_neg_desde:indice_res_neg_hasta) = -diag(ones(cant_po,1));
                    end
                end
            else % generador ernc
                %consumo residual
                id_perfil = this.Generadores.IdAdmEscenarioPerfil(this.Generadores.n);
                if id_perfil ~= 0
                    perfil = this.pAdmSc.entrega_perfil_ernc(id_perfil);
                    valor_elemento = this.Generadores.Pmax(this.Generadores.n)*perfil;
                else
                    % quiere decir que datos son locales
                    valor_elemento = this.Generadores.ElRed(this.Generadores.n).entrega_p_const_nom_opf(); % ya está en pu
                end
                for cont = 1:this.iCantContingenciasGenCons
                    indice_eq_desde = this.Subestaciones.IdRestriccionEBalancePCDesde(id_se,cont);
                    indice_eq_hasta = indice_eq_desde + cant_po - 1;
                
                    this.beq(indice_eq_desde:indice_eq_hasta) = this.beq(indice_eq_desde:indice_eq_hasta) - valor_elemento';
                    
                    indice_recorte_desde = this.Generadores.IdVarOptPCResNegDesde(this.Generadores.n, cont);
                    indice_recorte_hasta = indice_recorte_desde + cant_po - 1;
                    this.Aeq(indice_eq_desde:indice_eq_hasta,indice_recorte_desde:indice_recorte_hasta) = -diag(ones(cant_po,1));
                end
            end
        end

        function agrega_bateria_a_balance_energia_pc(this, variable)
            cant_po = this.iCantPuntosOperacion;
            id_se = variable.entrega_se().entrega_id();

            indice_bat_descarga_desde = this.Baterias.IdVarOptDesdeDescarga(this.Baterias.n);
            indice_bat_descarga_hasta = indice_bat_descarga_desde + cant_po -1;
            indice_bat_carga_desde = this.Baterias.IdVarOptDesdeCarga(this.Baterias.n);
            indice_bat_carga_hasta = indice_bat_carga_desde + cant_po -1;
            
            for cont = 1:this.iCantContingenciasGenCons
                indice_eq_desde = this.Subestaciones.IdRestriccionEBalancePCDesde(id_se,cont);
                indice_eq_hasta = indice_eq_desde + cant_po - 1;
            
                this.Aeq(indice_eq_desde:indice_eq_hasta,indice_bat_descarga_desde:indice_bat_descarga_hasta) = diag(ones(cant_po,1));
                this.Aeq(indice_eq_desde:indice_eq_hasta,indice_bat_carga_desde:indice_bat_carga_hasta) = -diag(ones(cant_po,1));

                % reservas positivas y negativas
                indice_bat_res_descarga_desde = this.Baterias.IdVarOptResDescargaDesde(this.Baterias.n, cont);
                indice_bat_res_descarga_hasta = indice_bat_res_descarga_desde + cant_po -1;
                indice_bat_res_carga_desde = this.Baterias.IdVarOptResCargaDesde(this.Baterias.n, cont);
                indice_bat_res_carga_hasta = indice_bat_res_carga_desde + cant_po -1;
                this.Aeq(indice_eq_desde:indice_eq_hasta,indice_bat_res_descarga_desde:indice_bat_res_descarga_hasta) = diag(ones(cant_po,1));
                this.Aeq(indice_eq_desde:indice_eq_hasta,indice_bat_res_carga_desde:indice_bat_res_carga_hasta) = -diag(ones(cant_po,1));
            end
        end
        
        function escribe_relaciones_flujos_angulos(this)
            cant_po = this.iCantPuntosOperacion;
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            for i = 1:this.Lineas.n
                indice_eq_desde = this.iIndiceEq +1;
                indice_eq_hasta = this.iIndiceEq + cant_po;
                this.iIndiceEq = this.iIndiceEq +cant_po;
                
                this.Lineas.IdRestriccionEFlujosAngulosDesde(i) = indice_eq_desde;
                
                id_eserie_desde = this.Lineas.IdVarOptDesde(i);
                id_eserie_hasta = id_eserie_desde + cant_po - 1;
                
                id_se1 = this.Lineas.ElRed(i).entrega_se1().entrega_id();
                id_se2 = this.Lineas.ElRed(i).entrega_se2().entrega_id();
                id_t1_desde = this.Subestaciones.IdVarOptDesde(id_se1);
                id_t1_hasta = id_t1_desde + cant_po - 1;
                id_t2_desde = this.Subestaciones.IdVarOptDesde(id_se2);
                id_t2_hasta = id_t2_desde + cant_po - 1;

                x = round(this.Lineas.ElRed(i).entrega_reactancia_pu(),dec_redondeo);
                
                this.Aeq(indice_eq_desde:indice_eq_hasta,id_eserie_desde:id_eserie_hasta) = this.Aeq(indice_eq_desde:indice_eq_hasta,id_eserie_desde:id_eserie_hasta) + diag(ones(cant_po,1))*x;
                this.Aeq(indice_eq_desde:indice_eq_hasta,id_t1_desde:id_t1_hasta) = this.Aeq(indice_eq_desde:indice_eq_hasta,id_t1_desde:id_t1_hasta) + -diag(ones(cant_po,1));
                this.Aeq(indice_eq_desde:indice_eq_hasta,id_t2_desde:id_t2_hasta) = this.Aeq(indice_eq_desde:indice_eq_hasta,id_t2_desde:id_t2_hasta) + diag(ones(cant_po,1));
                %for oper = 1:cant_po
                %    this.Aeq(indice_eq_desde + oper - 1,id_eserie_desde + oper - 1) = x;
                %    this.Aeq(indice_eq_desde + oper - 1,id_t1_desde + oper - 1) = -1;
                %    this.Aeq(indice_eq_desde + oper - 1,id_t2_desde + oper - 1) = 1;
                %end
                this.beq(indice_eq_desde:indice_eq_hasta) = 0;
                                
                if this.iNivelDebug > 0
                    this.ingresa_nombre_restriccion_igualdad(this.Lineas.ElRed(i), indice_eq_desde);
                end
            end
            
            %Trafos
            for i = 1:this.Trafos.n
                indice_eq_desde = this.iIndiceEq +1;
                indice_eq_hasta = this.iIndiceEq + cant_po;
                this.iIndiceEq = this.iIndiceEq +cant_po;
                
                this.Trafos.IdRestriccionEFlujosAngulosDesde(i) = indice_eq_desde;
                
                id_eserie_desde = this.Trafos.IdVarOptDesde(i);
                id_eserie_hasta = id_eserie_desde + cant_po - 1;
                
                id_se1 = this.Trafos.ElRed(i).entrega_se1().entrega_id();
                id_se2 = this.Trafos.ElRed(i).entrega_se2().entrega_id();
                id_t1_desde = this.Subestaciones.IdVarOptDesde(id_se1);
                id_t1_hasta = id_t1_desde + cant_po - 1;
                id_t2_desde = this.Subestaciones.IdVarOptDesde(id_se2);
                id_t2_hasta = id_t2_desde + cant_po - 1;

                x = round(this.Trafos.ElRed(i).entrega_reactancia_pu(),dec_redondeo);
                
                this.Aeq(indice_eq_desde:indice_eq_hasta,id_eserie_desde:id_eserie_hasta) = this.Aeq(indice_eq_desde:indice_eq_hasta,id_eserie_desde:id_eserie_hasta) + diag(ones(cant_po,1))*x;
                this.Aeq(indice_eq_desde:indice_eq_hasta,id_t1_desde:id_t1_hasta) = this.Aeq(indice_eq_desde:indice_eq_hasta,id_t1_desde:id_t1_hasta) + -diag(ones(cant_po,1));
                this.Aeq(indice_eq_desde:indice_eq_hasta,id_t2_desde:id_t2_hasta) = this.Aeq(indice_eq_desde:indice_eq_hasta,id_t2_desde:id_t2_hasta) + diag(ones(cant_po,1));
                %for oper = 1:cant_po
                %    this.Aeq(indice_eq_desde + oper - 1,id_eserie_desde + oper - 1) = x;
                %    this.Aeq(indice_eq_desde + oper - 1,id_t1_desde + oper - 1) = -1;
                %    this.Aeq(indice_eq_desde + oper - 1,id_t2_desde + oper - 1) = 1;
                %end
                this.beq(indice_eq_desde:indice_eq_hasta) = 0;
                                
                if this.iNivelDebug > 0
                    this.ingresa_nombre_restriccion_igualdad(this.Trafos.ElRed(i), indice_eq_desde);                    
                end
            end
        end
        
        function escribe_relaciones_flujos_angulos_n1(this)
            cant_po = this.iCantPuntosOperacion;
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            for i = 1:this.Lineas.n
                for cont = 1:this.iCantContingenciasElSerie
                    if this.Lineas.IdVarOptN1Desde(i, cont) == 0
                        continue
                    end
                    
                    indice_eq_desde = this.iIndiceEq +1;
                    indice_eq_hasta = this.iIndiceEq + cant_po;
                    this.iIndiceEq = this.iIndiceEq +cant_po;
                
                    this.Lineas.IdRestriccionEFlujosAngulosN1Desde(i, cont) = indice_eq_desde;
                
                    id_eserie_desde = this.Lineas.IdVarOptN1Desde(i, cont);
                    id_eserie_hasta = id_eserie_desde + cant_po - 1;
                
                    id_se1 = this.Lineas.ElRed(i).entrega_se1().entrega_id();
                    id_se2 = this.Lineas.ElRed(i).entrega_se2().entrega_id();
                    id_t1_desde = this.Subestaciones.IdVarOptN1Desde(id_se1, cont);
                    id_t1_hasta = id_t1_desde + cant_po - 1;
                    id_t2_desde = this.Subestaciones.IdVarOptN1Desde(id_se2, cont);
                    id_t2_hasta = id_t2_desde + cant_po - 1;

                    x = round(this.Lineas.ElRed(i).entrega_reactancia_pu(),dec_redondeo);
                
                    this.Aeq(indice_eq_desde:indice_eq_hasta,id_eserie_desde:id_eserie_hasta) = this.Aeq(indice_eq_desde:indice_eq_hasta,id_eserie_desde:id_eserie_hasta) + diag(ones(cant_po,1))*x;
                    this.Aeq(indice_eq_desde:indice_eq_hasta,id_t1_desde:id_t1_hasta) = this.Aeq(indice_eq_desde:indice_eq_hasta,id_t1_desde:id_t1_hasta) + -diag(ones(cant_po,1));
                    this.Aeq(indice_eq_desde:indice_eq_hasta,id_t2_desde:id_t2_hasta) = this.Aeq(indice_eq_desde:indice_eq_hasta,id_t2_desde:id_t2_hasta) + diag(ones(cant_po,1));

                    this.beq(indice_eq_desde:indice_eq_hasta) = 0;

                    if this.iNivelDebug > 0
                        this.ingresa_nombre_restriccion_igualdad(this.Lineas.ElRed(i), indice_eq_desde, 'N1', cont);
                    end
                end
            end
            
            %Trafos
            for i = 1:this.Trafos.n
                for cont = 1:this.iCantContingenciasElSerie
                    if this.Trafos.IdVarOptN1Desde(i, cont) == 0
                        continue
                    end
                
                    indice_eq_desde = this.iIndiceEq +1;
                    indice_eq_hasta = this.iIndiceEq + cant_po;
                    this.iIndiceEq = this.iIndiceEq +cant_po;
                
                    this.Trafos.IdRestriccionEFlujosAngulosN1Desde(i, cont) = indice_eq_desde;
                
                    id_eserie_desde = this.Trafos.IdVarOptN1Desde(i, cont);
                    id_eserie_hasta = id_eserie_desde + cant_po - 1;
                
                    id_se1 = this.Trafos.ElRed(i).entrega_se1().entrega_id();
                    id_se2 = this.Trafos.ElRed(i).entrega_se2().entrega_id();
                    id_t1_desde = this.Subestaciones.IdVarOptN1Desde(id_se1, cont);
                    id_t1_hasta = id_t1_desde + cant_po - 1;
                    id_t2_desde = this.Subestaciones.IdVarOptN1Desde(id_se2, cont);
                    id_t2_hasta = id_t2_desde + cant_po - 1;

                    x = round(this.Trafos.ElRed(i).entrega_reactancia_pu(),dec_redondeo);
                
                    this.Aeq(indice_eq_desde:indice_eq_hasta,id_eserie_desde:id_eserie_hasta) = this.Aeq(indice_eq_desde:indice_eq_hasta,id_eserie_desde:id_eserie_hasta) + diag(ones(cant_po,1))*x;
                    this.Aeq(indice_eq_desde:indice_eq_hasta,id_t1_desde:id_t1_hasta) = this.Aeq(indice_eq_desde:indice_eq_hasta,id_t1_desde:id_t1_hasta) + -diag(ones(cant_po,1));
                    this.Aeq(indice_eq_desde:indice_eq_hasta,id_t2_desde:id_t2_hasta) = this.Aeq(indice_eq_desde:indice_eq_hasta,id_t2_desde:id_t2_hasta) + diag(ones(cant_po,1));

                    this.beq(indice_eq_desde:indice_eq_hasta) = 0;

                    if this.iNivelDebug > 0
                        this.ingresa_nombre_restriccion_igualdad(this.Trafos.ElRed(i), indice_eq_desde, 'N1', cont);                    
                    end
                end
            end
        end

        function escribe_relaciones_flujos_angulos_pc(this)
            cant_po = this.iCantPuntosOperacion;
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            for i = 1:this.Lineas.n
                for cont = 1:this.this.iCantContingenciasGenCons
                    
                    indice_eq_desde = this.iIndiceEq +1;
                    indice_eq_hasta = this.iIndiceEq + cant_po;
                    this.iIndiceEq = this.iIndiceEq +cant_po;
                
                    this.Lineas.IdRestriccionEFlujosAngulosPCDesde(i, cont) = indice_eq_desde;
                
                    id_eserie_desde = this.Lineas.IdVarOptPCDesde(i, cont);
                    id_eserie_hasta = id_eserie_desde + cant_po - 1;
                
                    id_se1 = this.Lineas.ElRed(i).entrega_se1().entrega_id();
                    id_se2 = this.Lineas.ElRed(i).entrega_se2().entrega_id();
                    id_t1_desde = this.Subestaciones.IdVarOptPCDesde(id_se1, cont);
                    id_t1_hasta = id_t1_desde + cant_po - 1;
                    id_t2_desde = this.Subestaciones.IdVarOptPCDesde(id_se2, cont);
                    id_t2_hasta = id_t2_desde + cant_po - 1;

                    x = round(this.Lineas.ElRed(i).entrega_reactancia_pu(),dec_redondeo);
                
                    this.Aeq(indice_eq_desde:indice_eq_hasta,id_eserie_desde:id_eserie_hasta) = this.Aeq(indice_eq_desde:indice_eq_hasta,id_eserie_desde:id_eserie_hasta) + diag(ones(cant_po,1))*x;
                    this.Aeq(indice_eq_desde:indice_eq_hasta,id_t1_desde:id_t1_hasta) = this.Aeq(indice_eq_desde:indice_eq_hasta,id_t1_desde:id_t1_hasta) + -diag(ones(cant_po,1));
                    this.Aeq(indice_eq_desde:indice_eq_hasta,id_t2_desde:id_t2_hasta) = this.Aeq(indice_eq_desde:indice_eq_hasta,id_t2_desde:id_t2_hasta) + diag(ones(cant_po,1));

                    this.beq(indice_eq_desde:indice_eq_hasta) = 0;

                    if this.iNivelDebug > 0
                        this.ingresa_nombre_restriccion_igualdad(this.Lineas.ElRed(i), indice_eq_desde, 'PC', cont);
                    end
                end
            end
            
            %Trafos
            for i = 1:this.Trafos.n
                for cont = 1:this.iCantContingenciasGenCons                
                    indice_eq_desde = this.iIndiceEq +1;
                    indice_eq_hasta = this.iIndiceEq + cant_po;
                    this.iIndiceEq = this.iIndiceEq +cant_po;
                
                    this.Trafos.IdRestriccionEFlujosAngulosPCDesde(i, cont) = indice_eq_desde;
                
                    id_eserie_desde = this.Trafos.IdVarOptPCDesde(i, cont);
                    id_eserie_hasta = id_eserie_desde + cant_po - 1;
                
                    id_se1 = this.Trafos.ElRed(i).entrega_se1().entrega_id();
                    id_se2 = this.Trafos.ElRed(i).entrega_se2().entrega_id();
                    id_t1_desde = this.Subestaciones.IdVarOptPCDesde(id_se1, cont);
                    id_t1_hasta = id_t1_desde + cant_po - 1;
                    id_t2_desde = this.Subestaciones.IdVarOptPCDesde(id_se2, cont);
                    id_t2_hasta = id_t2_desde + cant_po - 1;

                    x = round(this.Trafos.ElRed(i).entrega_reactancia_pu(),dec_redondeo);
                
                    this.Aeq(indice_eq_desde:indice_eq_hasta,id_eserie_desde:id_eserie_hasta) = this.Aeq(indice_eq_desde:indice_eq_hasta,id_eserie_desde:id_eserie_hasta) + diag(ones(cant_po,1))*x;
                    this.Aeq(indice_eq_desde:indice_eq_hasta,id_t1_desde:id_t1_hasta) = this.Aeq(indice_eq_desde:indice_eq_hasta,id_t1_desde:id_t1_hasta) + -diag(ones(cant_po,1));
                    this.Aeq(indice_eq_desde:indice_eq_hasta,id_t2_desde:id_t2_hasta) = this.Aeq(indice_eq_desde:indice_eq_hasta,id_t2_desde:id_t2_hasta) + diag(ones(cant_po,1));

                    this.beq(indice_eq_desde:indice_eq_hasta) = 0;

                    if this.iNivelDebug > 0
                        this.ingresa_nombre_restriccion_igualdad(this.Trafos.ElRed(i), indice_eq_desde, 'PC', cont);                    
                    end
                end
            end
        end
        
        function escribe_balance_temporal_baterias(this)
            cant_po = this.iCantPuntosOperacion;
            [cant_periodos_representativos, ~] = size(this.vIndicesPOConsecutivos);
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            
            for i = 1:this.Baterias.n
                indice_eq_desde = this.iIndiceEq +1;
                indice_eq_hasta = this.iIndiceEq + cant_po;
                this.iIndiceEq = indice_eq_hasta;

                this.Baterias.IdRestriccionEBalanceDesde(i) = indice_eq_desde;

                eta_carga = this.Baterias.ElRed(i).entrega_eficiencia_carga();
                eta_descarga = this.Baterias.ElRed(i).entrega_eficiencia_descarga();
                
                indice_bat_e_desde = this.Baterias.IdVarOptDesdeE(i);
                indice_bat_e_hasta = indice_bat_e_desde + cant_po - 1;

                indice_p_descarga_desde = this.Baterias.IdVarOptDesdeDescarga(i);
                indice_p_descarga_hasta = indice_p_descarga_desde + cant_po -1;

                indice_p_carga_desde = this.Baterias.IdVarOptDesdeCarga(i);
                indice_p_carga_hasta = indice_p_carga_desde + cant_po -1;
                
                % forma las ecuaciones extendidas y luego borra las filas que no corresponden
                this.Aeq(indice_eq_desde:indice_eq_hasta,indice_bat_e_desde:indice_bat_e_hasta) = diag(ones(cant_po,1)); % E(t)
                this.Aeq(indice_eq_desde:indice_eq_hasta,indice_bat_e_desde-1:indice_bat_e_hasta-1) = this.Aeq(indice_eq_desde:indice_eq_hasta,indice_bat_e_desde-1:indice_bat_e_hasta-1) - diag(ones(cant_po,1)); % -E(t-1)

                this.Aeq(indice_eq_desde:indice_eq_hasta,indice_p_descarga_desde-1:indice_p_descarga_hasta-1) = round(1/eta_descarga, dec_redondeo)*diag(ones(cant_po,1)); % +Pdescarga(t-1)
                this.Aeq(indice_eq_desde:indice_eq_hasta,indice_p_carga_desde-1:indice_p_carga_hasta-1) = round(-eta_carga, dec_redondeo)*diag(ones(cant_po,1)); % -Pcarga(t-1)
                
                this.beq(indice_eq_desde:indice_eq_hasta) = 0;
                
                % corrige la primera hora de cada periodo con tal que
                % energía almacenada al comienzo y al final del periodo sean iguales
                indices_a_corregir = indice_eq_desde -1 + this.vIndicesPOConsecutivos(:,1);
                for periodo = 1:cant_periodos_representativos
                    indice_bat_e_desde_actual = indice_bat_e_desde + this.vIndicesPOConsecutivos(periodo,1)-1;
                    indice_bat_e_hasta_actual = indice_bat_e_desde + this.vIndicesPOConsecutivos(periodo,2)-1;
                    indice_bat_p_descarga_desde_actual = indice_p_descarga_desde + this.vIndicesPOConsecutivos(periodo,1) - 1;
                    indice_bat_p_carga_desde_actual = indice_p_carga_desde + this.vIndicesPOConsecutivos(periodo,1) -1;
                    
                    this.Aeq(indices_a_corregir(periodo), indice_bat_e_desde_actual-1) = 0;
                    this.Aeq(indices_a_corregir(periodo), indice_bat_p_descarga_desde_actual-1) = 0;
                    this.Aeq(indices_a_corregir(periodo), indice_bat_p_carga_desde_actual-1) = 0;
                    this.Aeq(indices_a_corregir(periodo), indice_bat_e_hasta_actual) = -1;
                end

                if this.iNivelDebug > 0
                    this.ingresa_nombre_restriccion_igualdad(this.Baterias.ElRed(i), indice_eq_desde);
                end                
            end
        end

        function escribe_balance_hidrico(this)
            cant_po = this.iCantPuntosOperacion;
            [cant_periodos_representativos, ~] = size(this.vIndicesPOConsecutivos);
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            
            for i = 1:this.Embalses.n
                indice_eq_desde = this.iIndiceEq +1;
                indice_eq_hasta = this.iIndiceEq + cant_po;
                this.iIndiceEq = indice_eq_hasta;

                this.Embalses.IdRestriccionEBalanceDesde(i) = indice_eq_desde;
                
                indice_vol_desde = this.Embalses.IdVarOptDesde(i);
                indice_vol_hasta = indice_vol_desde + cant_po - 1;
 
                % Primero cre las matrices y luego "arregla" límites iniciales y finales
                this.Aeq(indice_eq_desde:indice_eq_hasta,indice_vol_desde:indice_vol_hasta) = diag(ones(cant_po,1)); % Vol(t)
                this.Aeq(indice_eq_desde:indice_eq_hasta,indice_vol_desde-1:indice_vol_hasta-1) = ...
                    this.Aeq(indice_eq_desde:indice_eq_hasta,indice_vol_desde-1:indice_vol_hasta-1) -diag(ones(cant_po,1)); % -Vol(t-1)

                % turbinas de descarga
                turbinas_descarga = this.Embalses.ElRed(i).entrega_turbinas_descarga();
                indices_t_descarga_desde = zeros(length(turbinas_descarga),1);
                for j = 1:length(turbinas_descarga)
                    id_turbina = turbinas_descarga(j).entrega_id();
                    indice_p_desde = this.Generadores.IdVarOptDesde(id_turbina);
                    indice_p_hasta = indice_p_desde + cant_po -1;
                    indices_t_descarga_desde(j) = indice_p_desde;
                    
                    eficiencia_turbina = turbinas_descarga(j).entrega_eficiencia();
                    altura_caida = this.Embalses.ElRed(i).entrega_altura_caida();
                    eficiencia_embalse = this.Embalses.ElRed(i).entrega_eficiencia();
                    agua_turbinada_por_mwh = this.Sbase*1000/(eficiencia_turbina * 9.81 * altura_caida * eficiencia_embalse);
                    
                    this.Aeq(indice_eq_desde:indice_eq_hasta,indice_p_desde-1:indice_p_hasta-1) = ...
						this.Aeq(indice_eq_desde:indice_eq_hasta,indice_p_desde-1:indice_p_hasta-1) + round(agua_turbinada_por_mwh, dec_redondeo)*diag(ones(cant_po,1)); % + P_descarga(t-1)
                end

                % turbinas de carga
                turbinas_carga = this.Embalses.ElRed(i).entrega_turbinas_carga();
                indices_t_carga_desde = zeros(length(turbinas_carga),1);                
                for j = 1:length(turbinas_carga)
                    id_turbina = turbinas_carga(j).entrega_id();
                    indice_p_desde = this.Generadores.IdVarOptDesde(id_turbina);
                    indice_p_hasta = indice_p_desde + cant_po -1;
                    indices_t_carga_desde(j) = indice_p_desde;
                    
                    eficiencia_turbina = turbinas_carga(j).entrega_eficiencia();
                    altura_caida = this.Embalses.ElRed(i).entrega_altura_caida();
                    eficiencia_embalse = this.Embalses.ElRed(i).entrega_eficiencia();
                    agua_turbinada_por_mwh = -this.Sbase*1000/(eficiencia_turbina * 9.81 * altura_caida * eficiencia_embalse);
                    
                    this.Aeq(indice_eq_desde:indice_eq_hasta,indice_p_desde-1:indice_p_hasta-1) = ...
						this.Aeq(indice_eq_desde:indice_eq_hasta,indice_p_desde-1:indice_p_hasta-1) + round(agua_turbinada_por_mwh, dec_redondeo)*diag(ones(cant_po,1)); % - P_carga(t-1)
                end
                
                % Spillage
                indice_spill_desde = this.Embalses.IdVarOptVertimientoDesde(i);
                indice_spill_hasta = indice_spill_desde + cant_po -1;
                this.Aeq(indice_eq_desde:indice_eq_hasta,indice_spill_desde-1:indice_spill_hasta-1) = ...
					this.Aeq(indice_eq_desde:indice_eq_hasta,indice_spill_desde-1:indice_spill_hasta-1) + diag(ones(cant_po,1)); % + H_spillage(t-1)
                
                % Filtracion
                if this.Embalses.IdVarOptFiltracionDesde(i) ~= 0
                    indice_filt_desde = this.Embalses.IdVarOptFiltracionDesde(i);
                    indice_filt_hasta = indice_filt_desde + cant_po -1;
                    this.Aeq(indice_eq_desde:indice_eq_hasta,indice_filt_desde-1:indice_filt_hasta-1) = ...
						this.Aeq(indice_eq_desde:indice_eq_hasta,indice_filt_desde-1:indice_filt_hasta-1) + diag(ones(cant_po,1)); % + H_filtracion(t-1)
                end
                
                % afluentes
                id_afluentes = this.Embalses.IdAdmEscenarioAfluentes(i);
                afluentes = this.pAdmSc.entrega_perfil_afluente(id_afluentes); %m3/s
                this.beq(indice_eq_desde:indice_eq_hasta) = [0 ; afluentes(1:end-1)'];
                
                % aportes adicionales. Vertimientos y filtraciones desde otros embalses
                aportes_adicionales = this.Embalses.ElRed(i).entrega_aportes_adicionales();
                indices_aportes_adicionales_desde = zeros(length(aportes_adicionales),1);
                for j = 1:length(aportes_adicionales)
                    embalse_orig = aportes_adicionales(j).entrega_embalse();
                    if embalse_orig.es_vertimiento(aportes_adicionales(j))
                        indice_aporte_desde = this.Embalses.IdVarOptVertimientoDesde(embalse_orig.entrega_id());
                    elseif embalse_orig.es_filtracion(aportes_adicionales(j))
                        indice_aporte_desde = this.Embalses.IdVarOptFiltracionDesde(embalse_orig.entrega_id());
                    else
                        error = MException('cOPF:escribe_balance_hidrico',...
                            ['Error en datos de entrada de embalse ' this.Embalses.ElRed(i).entrega_nombre() '. Aporte adicional ' aportes_adicionales(j).entrega_nombre() ...
                            ' asociado a embalse ' embalse_orig.entrega_nombre() ' no es ni vertimiento ni filtración']);
                        throw(error)
                    end
                    
                    indices_aportes_adicionales_desde(j) = indice_aporte_desde;
                    indice_aporte_hasta = indice_aporte_desde + cant_po - 1;
                    this.Aeq(indice_eq_desde:indice_eq_hasta,indice_aporte_desde-1:indice_aporte_hasta-1) = ...
						this.Aeq(indice_eq_desde:indice_eq_hasta,indice_aporte_desde-1:indice_aporte_hasta-1) -diag(ones(cant_po,1)); % - aporte_adicional(t-1)
                end
                
                % corrige la primera hora y determina balance entre periodos
                indices_a_corregir = indice_eq_desde -1 + this.vIndicesPOConsecutivos(:,1);
                for periodo = 1:cant_periodos_representativos
                    indice_vol_desde_periodo_actual = indice_vol_desde + this.vIndicesPOConsecutivos(periodo,1)-1;
                    indices_t_carga_desde_periodo_actual = indices_t_carga_desde + this.vIndicesPOConsecutivos(periodo,1)-1;
                    indices_t_descarga_desde_periodo_actual = indices_t_descarga_desde + this.vIndicesPOConsecutivos(periodo,1)-1;
                    indice_spill_desde_periodo_actual = indice_spill_desde + this.vIndicesPOConsecutivos(periodo,1)-1;
                    indices_aportes_adicionales_desde_periodo_actual = indices_aportes_adicionales_desde + this.vIndicesPOConsecutivos(periodo,1)-1;
                    
                    this.Aeq(indices_a_corregir(periodo), indice_vol_desde_periodo_actual-1) = 0;
                    this.Aeq(indices_a_corregir(periodo), indices_t_carga_desde_periodo_actual-1) = 0;
                    this.Aeq(indices_a_corregir(periodo), indices_t_descarga_desde_periodo_actual-1) = 0;
                    this.Aeq(indices_a_corregir(periodo), indice_spill_desde_periodo_actual-1) = 0;
                    this.Aeq(indices_a_corregir(periodo), indices_aportes_adicionales_desde_periodo_actual-1) = 0;
                    
                    if this.Embalses.IdVarOptFiltracionDesde(i) ~= 0
                        indice_filt_desde_periodo_actual = indice_filt_desde + this.vIndicesPOConsecutivos(periodo,1)-1;
                        this.Aeq(indices_a_corregir(periodo), indice_filt_desde_periodo_actual-1) = 0;
                    end
                    
                    if periodo == 1
                        indice_final = indice_vol_desde + this.vIndicesPOConsecutivos(end,2)-1;
                        this.Aeq(indices_a_corregir(periodo), indice_final) = -1; % vol inicial y final del embalse tienen que ser iguales
                    else
                        % Vol_inicio_periodo + Vol_inicio_periodo_ant*(rep_periodo - 1) - Vol_fin_periodo_ant*(rep_periodo) = 0
                        % Vol_inicio_periodo =  Vol_inicio_periodo_ant + (Vol_fin_periodo_ant - Vol_inicio_periodo_ant)*rep_periodo 
                        % Vol_inicio_periodo =  Vol_inicio_periodo_ant + agua_turbinada_periodo_anterior
                        po_ant_desde = this.vIndicesPOConsecutivos(periodo-1,1);
                        po_ant_hasta = this.vIndicesPOConsecutivos(periodo-1,2);
                        representatividad_periodo_anterior = sum(this.vRepresentatividadPO(po_ant_desde:po_ant_hasta));
                        
                        indice_vol_desde_periodo_anterior = indice_vol_desde + this.vIndicesPOConsecutivos(periodo-1,1)-1;
                        indice_vol_hasta_periodo_anterior = indice_vol_desde + this.vIndicesPOConsecutivos(periodo-1,2)-1;
                        
                        this.Aeq(indices_a_corregir(periodo), indice_vol_desde_periodo_anterior) = representatividad_periodo_anterior-1;
                        this.Aeq(indices_a_corregir(periodo), indice_vol_hasta_periodo_anterior) = -representatividad_periodo_anterior;
                        this.beq(indices_a_corregir(periodo)) = 0;
                    end
                end
                if this.iNivelDebug > 0
                    this.ingresa_nombre_restriccion_igualdad(this.Embalses.ElRed(i), indice_eq_desde, 'Vol');
                end
                
                if this.Embalses.IdVarOptFiltracionDesde(i) ~= 0
                    % restricciones adicionales de las filtraciones. Estas son lineales c/r al volumen del embalse
                    indice_eq_desde = this.iIndiceEq +1;
                    indice_eq_hasta = this.iIndiceEq + cant_po;
                    this.iIndiceEq = indice_eq_hasta;

                    this.Embalses.IdRestriccionEFiltracionDesde(i) = indice_eq_desde;
                    porcentaje_filtracion = this.Embalses.ElRed(i).entrega_porcentaje_filtracion();
                    this.Aeq(indice_eq_desde:indice_eq_hasta,indice_filt_desde:indice_filt_hasta) = diag(ones(cant_po,1));
                    this.Aeq(indice_eq_desde:indice_eq_hasta,indice_vol_desde:indice_vol_hasta) = -porcentaje_filtracion*diag(ones(cant_po,1));

                    if this.iNivelDebug > 0
                        this.ingresa_nombre_restriccion_igualdad(this.Embalses.ElRed(i), indice_eq_desde, 'Filt');
                    end
                    
                end
            end
        end
        
        function agrega_balance_temporal_baterias(this, bateria, indice_p_descarga_desde, indice_p_descarga_hasta, indice_p_carga_desde, indice_p_carga_hasta, indice_e_desde, indice_e_hasta)            
            cant_po = this.iCantPuntosOperacion;
            [cant_periodos_representativos, ~] = size(this.vIndicesPOConsecutivos);
            %cant_po_por_periodo = cant_po/cant_periodos_representativos;
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            
            indice_eq_desde = this.iIndiceEq +1;
            indice_eq_hasta = this.iIndiceEq + cant_po;
            this.iIndiceEq = indice_eq_hasta;

            this.Baterias.IdRestriccionEBalanceDesde(bateria.entrega_id()) = indice_eq_desde;

            eta_carga = bateria.entrega_eficiencia_carga();
            eta_descarga = bateria.entrega_eficiencia_descarga();
            
            % forma las ecuaciones extendidas y luego borra las filas que no corresponden
            this.Aeq(indice_eq_desde:indice_eq_hasta,indice_e_desde:indice_e_hasta) = diag(ones(cant_po,1)); % E(t)
            this.Aeq(indice_eq_desde:indice_eq_hasta,indice_e_desde-1:indice_e_hasta-1) = this.Aeq(indice_eq_desde:indice_eq_hasta,indice_e_desde-1:indice_e_hasta-1) - diag(ones(cant_po,1)); % -E(t-1)

            this.Aeq(indice_eq_desde:indice_eq_hasta,indice_p_descarga_desde-1:indice_p_descarga_hasta-1) = round(1/eta_descarga, dec_redondeo)*diag(ones(cant_po,1)); % +Pdescarga(t-1)
            this.Aeq(indice_eq_desde:indice_eq_hasta,indice_p_carga_desde-1:indice_p_carga_hasta-1) = round(-eta_carga, dec_redondeo)*diag(ones(cant_po,1)); % -Pcarga(t-1)

            % corrige la primera hora de cada periodo con tal que energía almacenada al comienzo y al final del periodo sean iguales
            indices_a_corregir = indice_eq_desde + this.vIndicesPOConsecutivos(:,1) -1 ;
            for periodo = 1:cant_periodos_representativos
                indice_bat_e_desde_actual = indice_e_desde + this.vIndicesPOConsecutivos(periodo,1) - 1;
                indice_bat_e_hasta_actual = indice_e_desde + this.vIndicesPOConsecutivos(periodo,2) - 1;
                indice_bat_p_descarga_desde_actual = indice_p_descarga_desde + this.vIndicesPOConsecutivos(periodo,1) - 1;
                indice_bat_p_carga_desde_actual = indice_p_carga_desde + this.vIndicesPOConsecutivos(periodo,1) -1;

                this.Aeq(indices_a_corregir(periodo), indice_bat_e_desde_actual-1) = 0;
                this.Aeq(indices_a_corregir(periodo), indice_bat_p_descarga_desde_actual-1) = 0;
                this.Aeq(indices_a_corregir(periodo), indice_bat_p_carga_desde_actual-1) = 0;
                this.Aeq(indices_a_corregir(periodo), indice_bat_e_hasta_actual) = -1;
            end

            this.beq(indice_eq_desde:indice_eq_hasta) = 0;

            if this.iNivelDebug > 0
                this.ingresa_nombre_restriccion_igualdad(bateria, indice_eq_desde);
            end
        end
        
        function actualiza_etapa(this, etapa)            
            this.iEtapa = etapa;
            cant_po = this.iCantPuntosOperacion;
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            %actualiza potencias de los generadores y consumos (ens) de acuerdo a
            %la etapa
            
            % generadores despachables con evolución de capacidad
            indices = find(this.Generadores.Despachable == 1 & this.Generadores.IdAdmEscenarioCapacidad ~= 0);
            for i = 1:length(indices)
                id = indices(i);
                id_adm_sc = this.Generadores.IdAdmEscenarioCapacidad(id);
                this.Generadores.Pmax(id) = this.pAdmSc.entrega_capacidad_generador(id_adm_sc, this.iEtapa)/this.Sbase;
                
                indice_desde = this.Generadores.IdVarOptDesde(id);
                indice_hasta = indice_desde + cant_po - 1;
                this.ub(indice_desde:indice_hasta) = round(this.Generadores.Pmax(id),dec_redondeo);
            end
            
            % generadores renovables con evolución de capacidad
            indices = find(this.Generadores.Despachable == 0 & this.Generadores.IdAdmEscenarioCapacidad ~= 0);
            for i = 1:length(indices)
                id = indices(i);
                pmax_orig = this.Generadores.Pmax(id);
                
                id_adm_sc = this.Generadores.IdAdmEscenarioCapacidad(id);
                this.Generadores.Pmax(id) = this.pAdmSc.entrega_capacidad_generador(id_adm_sc, this.iEtapa)/this.Sbase;

                indice_varopt_operacion_desde = this.Generadores.IdVarOptDesde(id);
                indice_varopt_operacion_hasta = indice_varopt_operacion_desde + cant_po - 1;
                
                id_adm_sc = this.Generadores.IdAdmEscenarioPerfil(id);
                perfil = this.pAdmSc.entrega_perfil_ernc(id_adm_sc);
                inyeccion_nueva = this.Generadores.Pmax(id)*perfil;
                this.ub(indice_varopt_operacion_desde:indice_varopt_operacion_hasta) = round(inyeccion_nueva',dec_redondeo);
    
                %actualiza balance de energía
                inyeccion_orig = pmax_orig*perfil;
                delta_inyeccion = inyeccion_nueva - inyeccion_orig;
                id_se = this.Generadores.ElRed(id).entrega_se().entrega_id();
                
                indice_eq_desde = this.Subestaciones.IdRestriccionEBalanceDesde(id_se);
                indice_eq_hasta = indice_eq_desde + cant_po - 1;
                this.beq(indice_eq_desde:indice_eq_hasta) = this.beq(indice_eq_desde:indice_eq_hasta) - round(delta_inyeccion',dec_redondeo);
            end

            %consumo. Se asume que siempre cambian de capacidad
            for i = 1:this.Consumos.n
                pmax_orig = this.Consumos.Pmax(i);

                indice_capacidad = this.Consumos.IdAdmEscenarioCapacidad(i);
                this.Consumos.Pmax(i) = this.pAdmSc.entrega_capacidad_consumo(indice_capacidad, this.iEtapa)/this.Sbase;

                indice_perfil = this.Consumos.IdAdmEscenarioPerfil(i);
                perfil = this.pAdmSc.entrega_perfil_consumo(indice_perfil);
                
                indice_desde = this.Consumos.IdVarOptDesde(i);
                indice_hasta = indice_desde + cant_po - 1;

                % ENS
                delta_consumo = (this.Consumos.Pmax(i)-pmax_orig)*perfil;
                this.ub(indice_desde:indice_hasta) = this.ub(indice_desde:indice_hasta) + delta_consumo;
                
                % Balance energía
                id_se = this.Consumos.ElRed(i).entrega_se().entrega_id();
                indice_eq_desde = this.Subestaciones.IdRestriccionEBalanceDesde(id_se);
                indice_eq_hasta = indice_eq_desde + cant_po - 1;
                this.beq(indice_eq_desde:indice_eq_hasta) = this.beq(indice_eq_desde:indice_eq_hasta) + round(delta_consumo',dec_redondeo);
            end
        end
        
		function calcula_despacho_economico_sin_restricciones_red(this)
            if this.VariablesInicializadas == false
                this.iIndiceIneq = 0;
                this.iIndiceEq = 0;
                this.iIndiceVarOpt = 0;
                this.inicializa_variables();
                this.inicializa_contenedores();
			
                this.escribe_funcion_objetivo();
                this.escribe_restricciones();
                this.VariablesInicializadas = true;
            end
            
            % desactiva las restricciones de red
            this.desactiva_restricciones_red();
            
            if this.iNivelDebug > 1
                this.imprime_problema_optimizacion();
            end
            
			this.optimiza();
            this.pResEvaluacion.inicializa_contenedores_opf(this.iCantPuntosOperacion);
            if this.ExitFlag == 1
                % problema tiene solucion óptima
                this.pResEvaluacion.ExisteResultadoOPF = true;
                this.escribe_resultados();
                if this.iNivelDebug > 0
                    this.imprime_resultados_protocolo();
                end
            else
                this.pResEvaluacion.ExisteResultadoOPF = false;
                if this.iNivelDebug > 0
                    prot = cProtocolo.getInstance;
                    prot.imprime_texto('Problema de optimizacion invalido');
                    prot.imprime_texto(['Estado flag: ' num2str(this.ExitFlag)]);
                end
                % problema no tiene solucion
                % no se escriben resultados porque no tiene sentido
                
            end            
            this.activa_restricciones_red();
        end
        
        function desactiva_restricciones_red(this)
            cant_po = this.iCantPuntosOperacion;

            % subestaciones
            for i = 1:this.Subestaciones.n
                indice_desde = this.Subestaciones.IdVarOptDesde(i);
                indice_hasta = indice_desde + cant_po - 1;

                this.lb(indice_desde:indice_hasta) = 4*this.lb(indice_desde:indice_hasta);
                this.ub(indice_desde:indice_hasta) = 4*this.ub(indice_desde:indice_hasta);
            end
            
            % Líneas
            for i = 1:this.Lineas.n
                indice_desde = this.Lineas.IdVarOptDesde(i);
                indice_hasta = indice_desde + cant_po - 1;
                
                this.lb(indice_desde:indice_hasta) = 100*this.lb(indice_desde:indice_hasta);
                this.ub(indice_desde:indice_hasta) = 100*this.ub(indice_desde:indice_hasta);
            end
            
            % Trafos
            for i = 1:this.Trafos.n
                indice_desde = this.Trafos.IdVarOptDesde(i);
                indice_hasta = indice_desde + cant_po - 1;
                
                this.lb(indice_desde:indice_hasta) = 100*this.lb(indice_desde:indice_hasta);
                this.ub(indice_desde:indice_hasta) = 100*this.ub(indice_desde:indice_hasta);
            end            
        end
        
        function activa_restricciones_red(this)
            cant_po = this.iCantPuntosOperacion;
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            theta_max = this.pParOpt.AnguloMaximoBuses;
            
            % subestaciones
            for i = 1:this.Subestaciones.n
                indice_desde = this.Subestaciones.IdVarOptDesde(i);
                indice_hasta = indice_desde + cant_po - 1;

                this.lb(indice_desde:indice_hasta) = round(-theta_max,dec_redondeo);
                this.ub(indice_desde:indice_hasta) = round(theta_max,dec_redondeo);
            end
            id_slack = this.pSEP.entrega_id_se_slack();
            indice_desde_slack = this.Subestaciones.IdVarOptDesde(id_slack);
            indice_hasta_slack = indice_desde_slack + cant_po -1;

            this.lb(indice_desde_slack:indice_hasta_slack) = 0;
            this.ub(indice_desde_slack:indice_hasta_slack) = 0;
            
            % Líneas
            for i = 1:this.Lineas.n
                indice_desde = this.Lineas.IdVarOptDesde(i);
                indice_hasta = indice_desde + cant_po - 1;
                
                sr = this.Lineas.ElRed(i).entrega_sr()/this.Sbase;
                this.lb(indice_desde:indice_hasta) = round(-sr,dec_redondeo);
                this.ub(indice_desde:indice_hasta) = round(sr,dec_redondeo);
            end
            
            % Trafos
            for i = 1:this.Trafos.n
                indice_desde = this.Trafos.IdVarOptDesde(i);
                indice_hasta = indice_desde + cant_po - 1;
                
                sr = this.Trafos.ElRed(i).entrega_sr()/this.Sbase;
                this.lb(indice_desde:indice_hasta) = round(-sr,dec_redondeo);
                this.ub(indice_desde:indice_hasta) = round(sr,dec_redondeo);
            end            

        end        
        
        function agrega_eserie_a_balance_energia(this, variable, indice_eserie_p_desde, indice_eserie_p_hasta)
            cant_po = this.iCantPuntosOperacion;
            id_se1 = variable.entrega_se1().entrega_id();
            indice_eq_bus1_desde = this.Subestaciones.IdRestriccionEBalanceDesde(id_se1);
            indice_eq_bus1_hasta = indice_eq_bus1_desde + cant_po - 1;

            id_se2 = variable.entrega_se2().entrega_id();
            indice_eq_bus2_desde = this.Subestaciones.IdRestriccionEBalanceDesde(id_se2);
            indice_eq_bus2_hasta = indice_eq_bus2_desde + cant_po - 1;
            
            this.Aeq(indice_eq_bus1_desde:indice_eq_bus1_hasta,indice_eserie_p_desde:indice_eserie_p_hasta) = -diag(ones(cant_po,1));
            this.Aeq(indice_eq_bus2_desde:indice_eq_bus2_hasta,indice_eserie_p_desde:indice_eserie_p_hasta) = diag(ones(cant_po,1));
        end

        function agrega_generador_a_balance_energia(this, variable, indice_p_desde, indice_p_hasta)
            cant_po = this.iCantPuntosOperacion;
            id_se = variable.entrega_se().entrega_id();
            indice_eq_bus_desde = this.Subestaciones.IdRestriccionEBalanceDesde(id_se);
            indice_eq_bus_hasta = indice_eq_bus_desde + cant_po - 1;

            if variable.Despachable
                this.Aeq(indice_eq_bus_desde:indice_eq_bus_hasta,indice_p_desde:indice_p_hasta) = diag(ones(cant_po,1));
            else
                this.Aeq(indice_eq_bus_desde:indice_eq_bus_hasta,indice_p_desde:indice_p_hasta) = -diag(ones(cant_po,1));
                
                id_gen = variable.entrega_id();
                id_perfil = this.Generadores.IdAdmEscenarioPerfil(id_gen);
                if id_perfil ~= 0
                    perfil = this.pAdmSc.entrega_perfil_ernc(id_perfil);
                    valor_elemento = this.Generadores.Pmax(id_gen)*perfil;
                else
                    % quiere decir que datos son locales
                    valor_elemento = this.Generadores.ElRed(id_gen).entrega_p_const_nom_opf(); % ya está en pu
                end
                this.beq(indice_eq_bus_desde:indice_eq_bus_hasta) = ...
                    this.beq(indice_eq_bus_desde:indice_eq_bus_hasta) - round(valor_elemento,this.pParOpt.DecimalesRedondeo);
                
            end
        end
        
        function agrega_eserie_a_balance_energia_n1(this, variable, indice_eserie_p_desde, indice_eserie_p_hasta, cont)
            cant_po = this.iCantPuntosOperacion;
            id_se1 = variable.entrega_se1().entrega_id();
            indice_eq_bus1_desde = this.Subestaciones.IdRestriccionEBalanceN1Desde(id_se1, cont);
            indice_eq_bus1_hasta = indice_eq_bus1_desde + cant_po - 1;

            id_se2 = variable.entrega_se2().entrega_id();
            indice_eq_bus2_desde = this.Subestaciones.IdRestriccionEBalanceN1Desde(id_se2, cont);
            indice_eq_bus2_hasta = indice_eq_bus2_desde + cant_po - 1;
            
            this.Aeq(indice_eq_bus1_desde:indice_eq_bus1_hasta,indice_eserie_p_desde:indice_eserie_p_hasta) = -diag(ones(cant_po,1));
            this.Aeq(indice_eq_bus2_desde:indice_eq_bus2_hasta,indice_eserie_p_desde:indice_eserie_p_hasta) = diag(ones(cant_po,1));
        end

        function agrega_eserie_a_balance_energia_pc(this, variable, indice_eserie_p_desde, indice_eserie_p_hasta, cont)
            cant_po = this.iCantPuntosOperacion;
            id_se1 = variable.entrega_se1().entrega_id();
            indice_eq_bus1_desde = this.Subestaciones.IdRestriccionEBalancePCDesde(id_se1, cont);
            indice_eq_bus1_hasta = indice_eq_bus1_desde + cant_po - 1;

            id_se2 = variable.entrega_se2().entrega_id();
            indice_eq_bus2_desde = this.Subestaciones.IdRestriccionEBalancePCDesde(id_se2, cont);
            indice_eq_bus2_hasta = indice_eq_bus2_desde + cant_po - 1;
            
            this.Aeq(indice_eq_bus1_desde:indice_eq_bus1_hasta,indice_eserie_p_desde:indice_eserie_p_hasta) = -diag(ones(cant_po,1));
            this.Aeq(indice_eq_bus2_desde:indice_eq_bus2_hasta,indice_eserie_p_desde:indice_eserie_p_hasta) = diag(ones(cant_po,1));
        end

        
        function agrega_generador_a_balance_energia_n1(this, variable, indice_p_desde, indice_p_hasta, cont)
            cant_po = this.iCantPuntosOperacion;
            id_se = variable.entrega_se().entrega_id();
            indice_eq_bus_desde = this.Subestaciones.IdRestriccionEBalanceN1Desde(id_se, cont);
            indice_eq_bus_hasta = indice_eq_bus1_desde + cant_po - 1;

            if variable.Despachable
                this.Aeq(indice_eq_bus_desde:indice_eq_bus_hasta,indice_p_desde:indice_p_hasta) = diag(ones(cant_po,1));
            else
                this.Aeq(indice_eq_bus_desde:indice_eq_bus_hasta,indice_p_desde:indice_p_hasta) = -diag(ones(cant_po,1));
                
                id_gen = variable.entrega_id();
                id_perfil = this.Generadores.IdAdmEscenarioPerfil(id_gen);
                if id_perfil ~= 0
                    perfil = this.pAdmSc.entrega_perfil_ernc(id_perfil);
                    valor_elemento = this.Generadores.Pmax(id_gen)*perfil;
                else
                    % quiere decir que datos son locales
                    valor_elemento = this.Generadores.ElRed(id_gen).entrega_p_const_nom_opf(); % ya está en pu
                end
                this.beq(indice_eq_bus_desde:indice_eq_bus_hasta) = ...
                    this.beq(indice_eq_bus_desde:indice_eq_bus_hasta) - round(valor_elemento,this.pParOpt.DecimalesRedondeo);
                
            end
        end

        function agrega_bateria_a_balance_energia_n1(this, variable, indice_descarga_desde, indice_carga_desde, cont)
            cant_po = this.iCantPuntosOperacion;
            id_se = variable.entrega_se().entrega_id();
            indice_eq_desde = this.Subestaciones.IdRestriccionEBalanceN1Desde(id_se, cont);
            indice_eq_hasta = indice_eq_bus1_desde + cant_po - 1;

            indice_descarga_hasta = indice_descarga_desde + cant_po - 1;
            indice_carga_hasta = indice_carga_desde + cant_po - 1;

            this.Aeq(indice_eq_desde:indice_eq_hasta,indice_descarga_desde:indice_descarga_hasta) = diag(ones(cant_po,1));
            this.Aeq(indice_eq_desde:indice_eq_hasta,indice_carga_desde:indice_carga_hasta) = -diag(ones(cant_po,1));
        end
        
        function agrega_generador_a_funcion_objetivo(this, variable, indice_desde, indice_hasta)
            if variable.Despachable
                costos_mw = variable.entrega_costo_mwh()*this.Sbase;
                this.Fobj(indice_desde:indice_hasta) = round(this.vRepresentatividadPO*costos_mw/1000000,dec_redondeo);
            else % generadores res
                penalizacion = this.pParOpt.entrega_penalizacion()*this.Sbase; % penalización base (no estado post-contingencia)
                this.Fobj(indice_desde:indice_hasta) = round(this.vRepresentatividadPO*penalizacion/1000000,dec_redondeo);
            end
        end
        
        function agrega_generador_a_funcion_objetivo_uc(this, variable, indice_desde, indice_hasta)
            costo_partida = variable.entrega_costo_partida()*this.Sbase;
            this.Fobj(indice_desde:indice_hasta) = round(this.vRepresentatividadPO*costo_partida/1000000,dec_redondeo);            
        end
        
        function agrega_bateria_a_balance_energia(this, variable, indice_p_descarga_desde, indice_p_descarga_hasta, indice_p_carga_desde, indice_p_carga_hasta)
            cant_po = this.iCantPuntosOperacion;
            id_se = variable.entrega_se().entrega_id();
            indice_eq_bus_desde = this.Subestaciones.IdRestriccionEBalanceDesde(id_se);
            indice_eq_bus_hasta = indice_eq_bus_desde + cant_po - 1;

            this.Aeq(indice_eq_bus_desde:indice_eq_bus_hasta,indice_p_descarga_desde:indice_p_descarga_hasta) = diag(ones(cant_po,1));
            this.Aeq(indice_eq_bus_desde:indice_eq_bus_hasta,indice_p_carga_desde:indice_p_carga_hasta) = -diag(ones(cant_po,1));
        end
        
        function agrega_balance_energia(this, se)
            % Función sólo para utilizar con TNEP.
            cant_po = this.iCantPuntosOperacion;
            indice_eq_desde = this.iIndiceEq +1;
            indice_eq_hasta = this.iIndiceEq + cant_po;
            this.iIndiceEq = this.iIndiceEq +cant_po;
            
            this.Subestaciones.IdRestriccionEBalanceDesde(end+1) = indice_eq_desde;
            
            this.Aeq = [this.Aeq; zeros(cant_po,length(this.Fobj))];
            % Balance de potencia activa en bus
            %generadores
            pGeneradores = se.entrega_generadores_despachables();
            if ~isempty(pGeneradores)
                error = MException('cOPF:agrega_balance_energia','Error de programación. Función no acepta generadores en nuevos buses');
                throw(error)
            end
                    
            elpar = se.entrega_elementos_paralelos();
            if ~isempty(elpar)
                error = MException('cOPF:agrega_balance_energia','Error de programación. Función no acepta elementos paralelos en nuevos buses');
                throw(error)
            end
            this.beq(indice_eq_desde:indice_eq_hasta) = 0;
                
            pConsumos = se.entrega_consumos();
            if ~isempty(pConsumos)
                error = MException('cOPF:agrega_balance_energia','Error de programación. Función no acepta consumos en nuevos buses');
                throw(error)
            end
            
            % elementos serie
            eserie = se.entrega_elementos_serie();
            if ~isempty(eserie)
                error = MException('cOPF:agrega_balance_energia','Error de programación. Bus se acaba de agregar como variable independiente, por lo que aún no debiera tener elementos en serie conectados');
                throw(error)
            end
            
            if this.iNivelDebug > 0
                this.ingresa_nombre_restriccion_igualdad(se, indice_eq_desde);
            end
        end

        function agrega_balance_energia_n1(this, se)
            % Función sólo para utilizar con TNEP.
            n_se = se.entrega_id();
            
            % Aumenta dimensión de contenedor
            this.Aeq = [this.Aeq; zeros(this.iCantPuntosOperacion*this.iCantContingenciasElSerie,this.iIndiceVarOpt)];
            
            for cont = 1:this.iCantContingenciasElSerie

                indice_eq_desde = this.iIndiceEq +1;
                indice_eq_hasta = this.iIndiceEq + this.iCantPuntosOperacion;
                this.iIndiceEq = this.iIndiceEq +this.iCantPuntosOperacion;

                this.Subestaciones.IdRestriccionEBalanceN1Desde(n_se, cont) = indice_eq_desde;

                this.beq(indice_eq_desde:indice_eq_hasta) = 0;

                if this.iNivelDebug > 0
                    this.ingresa_nombre_restriccion_igualdad(se, indice_eq_desde, 'n1', cont);
                end
            end
        end

        function agrega_balance_energia_pc(this, se)
            % Función sólo para utilizar con TNEP.
            n_se = se.entrega_id();
            
            % Aumenta dimensión de contenedor
            this.Aeq = [this.Aeq; zeros(this.iCantPuntosOperacion*this.iCantContingenciasGenCons,length(this.Fobj))];
            
            for cont = 1:this.iCantContingenciasGenCons

                indice_eq_desde = this.iIndiceEq +1;
                indice_eq_hasta = this.iIndiceEq + this.iCantPuntosOperacion;
                this.iIndiceEq = indice_eq_hasta;

                this.Subestaciones.IdRestriccionEBalancePCDesde(n_se, cont) = indice_eq_desde;

                this.beq(indice_eq_desde:indice_eq_hasta) = 0;

                if this.iNivelDebug > 0
                    this.ingresa_nombre_restriccion_igualdad(se, indice_eq_desde, 'pc', cont);
                end
            end
        end

        function agrega_relaciones_flujos_angulos_linea(this, variable, id_eserie_desde, id_eserie_hasta)
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            cant_po = this.iCantPuntosOperacion;
            indice_eq_desde = this.iIndiceEq +1;
            indice_eq_hasta = this.iIndiceEq + cant_po;
            this.iIndiceEq = this.iIndiceEq +cant_po;
            
            this.Lineas.IdRestriccionEFlujosAngulosDesde(end+1) = indice_eq_desde;
                        
            id_se1 = variable.entrega_se1().entrega_id();
            id_se2 = variable.entrega_se2().entrega_id();
            id_t1_desde = this.Subestaciones.IdVarOptDesde(id_se1);
            id_t1_hasta = id_t1_desde + cant_po -1;
            id_t2_desde = this.Subestaciones.IdVarOptDesde(id_se2);
            id_t2_hasta = id_t2_desde + cant_po -1;

            x = round(variable.entrega_reactancia_pu(),dec_redondeo);
            this.Aeq = [this.Aeq; zeros(cant_po, length(this.Fobj))];
            this.Aeq(indice_eq_desde:indice_eq_hasta,id_eserie_desde:id_eserie_hasta) = x*diag(ones(cant_po,1));
            this.Aeq(indice_eq_desde:indice_eq_hasta,id_t1_desde:id_t1_hasta) = -diag(ones(cant_po,1));
            this.Aeq(indice_eq_desde:indice_eq_hasta,id_t2_desde:id_t2_hasta) = diag(ones(cant_po,1));
            
            %for oper = 1:cant_po
            %    this.Aeq(indice_eq_desde + oper - 1,id_eserie_desde + oper - 1) = x;
            %    this.Aeq(indice_eq_desde + oper - 1,id_t1_desde + oper - 1) = -1;
            %    this.Aeq(indice_eq_desde + oper - 1,id_t2_desde + oper - 1) = 1;
            %end
            this.beq(indice_eq_desde:indice_eq_hasta) = 0;

%             if this.pParOpt.entrega_flujo_dc_con_perdidas()
%                 error = MException('cDCOPF:agrega_relaciones_flujos_angulos','OPF DC con pérdidas aún no implementado');
%                 throw(error)
%             end
                
            if this.iNivelDebug > 0
                this.ingresa_nombre_restriccion_igualdad(variable, indice_eq_desde);
            end
        end

        function agrega_relaciones_flujos_angulos_linea_n1(this, variable, id_eserie_desde, id_eserie_hasta, cont)
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            cant_po = this.iCantPuntosOperacion;
            indice_eq_desde = this.iIndiceEq +1;
            indice_eq_hasta = this.iIndiceEq + cant_po;
            this.iIndiceEq = this.iIndiceEq +cant_po;
            
            this.Lineas.IdRestriccionEFlujosAngulosN1Desde(this.Lineas.n,cont) = indice_eq_desde;

            id_se1 = variable.entrega_se1().entrega_id();
            id_se2 = variable.entrega_se2().entrega_id();
            id_t1_desde = this.Subestaciones.IdVarOptN1Desde(id_se1, cont);
            id_t1_hasta = id_t1_desde + cant_po -1;
            id_t2_desde = this.Subestaciones.IdVarOptN1Desde(id_se2, cont);
            id_t2_hasta = id_t2_desde + cant_po -1;

            x = round(variable.entrega_reactancia_pu(),dec_redondeo);
            this.Aeq = [this.Aeq; zeros(cant_po, length(this.Fobj))];
            this.Aeq(indice_eq_desde:indice_eq_hasta,id_eserie_desde:id_eserie_hasta) = x*diag(ones(cant_po,1));
            this.Aeq(indice_eq_desde:indice_eq_hasta,id_t1_desde:id_t1_hasta) = -diag(ones(cant_po,1));
            this.Aeq(indice_eq_desde:indice_eq_hasta,id_t2_desde:id_t2_hasta) = diag(ones(cant_po,1));
            
            this.beq(indice_eq_desde:indice_eq_hasta) = 0;
                
            if this.iNivelDebug > 0
                this.ingresa_nombre_restriccion_igualdad(variable, indice_eq_desde, 'N1', cont);
            end
        end

        function agrega_relaciones_flujos_angulos_linea_pc(this, variable, id_eserie_desde, id_eserie_hasta, cont)
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            cant_po = this.iCantPuntosOperacion;
            indice_eq_desde = this.iIndiceEq +1;
            indice_eq_hasta = this.iIndiceEq + cant_po;
            this.iIndiceEq = this.iIndiceEq +cant_po;
            
            this.Lineas.IdRestriccionEFlujosAngulosPCDesde(this.Lineas.n,cont) = indice_eq_desde;

            id_se1 = variable.entrega_se1().entrega_id();
            id_se2 = variable.entrega_se2().entrega_id();
            id_t1_desde = this.Subestaciones.IdVarOptPCDesde(id_se1, cont);
            id_t1_hasta = id_t1_desde + cant_po -1;
            id_t2_desde = this.Subestaciones.IdVarOptPCDesde(id_se2, cont);
            id_t2_hasta = id_t2_desde + cant_po -1;

            x = round(variable.entrega_reactancia_pu(),dec_redondeo);
            this.Aeq = [this.Aeq; zeros(cant_po, length(this.Fobj))];
            this.Aeq(indice_eq_desde:indice_eq_hasta,id_eserie_desde:id_eserie_hasta) = x*diag(ones(cant_po,1));
            this.Aeq(indice_eq_desde:indice_eq_hasta,id_t1_desde:id_t1_hasta) = -diag(ones(cant_po,1));
            this.Aeq(indice_eq_desde:indice_eq_hasta,id_t2_desde:id_t2_hasta) = diag(ones(cant_po,1));
            
            this.beq(indice_eq_desde:indice_eq_hasta) = 0;
                
            if this.iNivelDebug > 0
                this.ingresa_nombre_restriccion_igualdad(variable, indice_eq_desde, 'PC', cont);
            end
        end
        
        function agrega_relaciones_flujos_angulos_trafo(this, variable, id_eserie_desde, id_eserie_hasta)
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            cant_po = this.iCantPuntosOperacion;
            indice_eq_desde = this.iIndiceEq +1;
            indice_eq_hasta = this.iIndiceEq + cant_po;
            this.iIndiceEq = this.iIndiceEq +cant_po;
            
            this.Trafos.IdRestriccionEFlujosAngulosDesde(this.Trafos.n) = indice_eq_desde;
                        
            id_se1 = variable.entrega_se1().entrega_id();
            id_se2 = variable.entrega_se2().entrega_id();
            id_t1_desde = this.Subestaciones.IdVarOptDesde(id_se1);
            id_t1_hasta = id_t1_desde + cant_po -1;
            id_t2_desde = this.Subestaciones.IdVarOptDesde(id_se2);
            id_t2_hasta = id_t2_desde + cant_po -1;

            x = round(variable.entrega_reactancia_pu(),dec_redondeo);
            this.Aeq = [this.Aeq; zeros(cant_po, length(this.Fobj))];
            this.Aeq(indice_eq_desde:indice_eq_hasta,id_eserie_desde:id_eserie_hasta) = x*diag(ones(cant_po,1));
            this.Aeq(indice_eq_desde:indice_eq_hasta,id_t1_desde:id_t1_hasta) = -diag(ones(cant_po,1));
            this.Aeq(indice_eq_desde:indice_eq_hasta,id_t2_desde:id_t2_hasta) = diag(ones(cant_po,1));
            
            %for oper = 1:cant_po
            %    this.Aeq(indice_eq_desde + oper - 1,id_eserie_desde + oper - 1) = x;
            %    this.Aeq(indice_eq_desde + oper - 1,id_t1_desde + oper - 1) = -1;
            %    this.Aeq(indice_eq_desde + oper - 1,id_t2_desde + oper - 1) = 1;
            %end
            this.beq(indice_eq_desde:indice_eq_hasta) = 0;

%             if this.pParOpt.entrega_flujo_dc_con_perdidas()
%                 error = MException('cDCOPF:agrega_relaciones_flujos_angulos','OPF DC con pérdidas aún no implementado');
%                 throw(error)
%             end
                
            if this.iNivelDebug > 0
                this.ingresa_nombre_restriccion_igualdad(variable, indice_eq_desde);
            end
        end

        function agrega_relaciones_flujos_angulos_trafo_n1(this, variable, id_eserie_desde, id_eserie_hasta, cont)
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            cant_po = this.iCantPuntosOperacion;
            indice_eq_desde = this.iIndiceEq +1;
            indice_eq_hasta = this.iIndiceEq + cant_po;
            this.iIndiceEq = this.iIndiceEq +cant_po;
            
            this.Trafos.IdRestriccionEFlujosAngulosN1Desde(this.Trafos.n, cont) = indice_eq_desde;
                        
            id_se1 = variable.entrega_se1().entrega_id();
            id_se2 = variable.entrega_se2().entrega_id();
            id_t1_desde = this.Subestaciones.IdVarOptN1Desde(id_se1, cont);
            id_t1_hasta = id_t1_desde + cant_po -1;
            id_t2_desde = this.Subestaciones.IdVarOptN1Desde(id_se2, cont);
            id_t2_hasta = id_t2_desde + cant_po -1;

            x = round(variable.entrega_reactancia_pu(),dec_redondeo);
            this.Aeq = [this.Aeq; zeros(cant_po, length(this.Fobj))];
            this.Aeq(indice_eq_desde:indice_eq_hasta,id_eserie_desde:id_eserie_hasta) = x*diag(ones(cant_po,1));
            this.Aeq(indice_eq_desde:indice_eq_hasta,id_t1_desde:id_t1_hasta) = -diag(ones(cant_po,1));
            this.Aeq(indice_eq_desde:indice_eq_hasta,id_t2_desde:id_t2_hasta) = diag(ones(cant_po,1));
            
            this.beq(indice_eq_desde:indice_eq_hasta) = 0;
                
            if this.iNivelDebug > 0
                this.ingresa_nombre_restriccion_igualdad(variable, indice_eq_desde, 'N1', cont);
            end
        end

        function agrega_relaciones_flujos_angulos_trafo_pc(this, variable, id_eserie_desde, id_eserie_hasta, cont)
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            cant_po = this.iCantPuntosOperacion;
            indice_eq_desde = this.iIndiceEq +1;
            indice_eq_hasta = this.iIndiceEq + cant_po;
            this.iIndiceEq = this.iIndiceEq +cant_po;
            
            this.Trafos.IdRestriccionEFlujosAngulosPCDesde(this.Trafos.n, cont) = indice_eq_desde;
                        
            id_se1 = variable.entrega_se1().entrega_id();
            id_se2 = variable.entrega_se2().entrega_id();
            id_t1_desde = this.Subestaciones.IdVarOptPCDesde(id_se1, cont);
            id_t1_hasta = id_t1_desde + cant_po -1;
            id_t2_desde = this.Subestaciones.IdVarOptPCDesde(id_se2, cont);
            id_t2_hasta = id_t2_desde + cant_po -1;

            x = round(variable.entrega_reactancia_pu(),dec_redondeo);
            this.Aeq = [this.Aeq; zeros(cant_po, length(this.Fobj))];
            this.Aeq(indice_eq_desde:indice_eq_hasta,id_eserie_desde:id_eserie_hasta) = x*diag(ones(cant_po,1));
            this.Aeq(indice_eq_desde:indice_eq_hasta,id_t1_desde:id_t1_hasta) = -diag(ones(cant_po,1));
            this.Aeq(indice_eq_desde:indice_eq_hasta,id_t2_desde:id_t2_hasta) = diag(ones(cant_po,1));
            
            this.beq(indice_eq_desde:indice_eq_hasta) = 0;
                
            if this.iNivelDebug > 0
                this.ingresa_nombre_restriccion_igualdad(variable, indice_eq_desde, 'PC', cont);
            end
        end
        
        function optimiza(this)
            if this.pParOpt.entrega_flujo_dc_con_perdidas()
                error = MException('cDCOPF:optimiza','OPF DC con pérdidas aún no implementado');
                throw(error)
            else
                if this.iNivelDebug > 1
                    prot = cProtocolo.getInstance;
                    prot.imprime_texto('Comienzo proceso optimizacion OPF DC');
                    if this.iNivelDebug > 1
                        prot.imprime_texto('Dimensiones del problema:');
                        prot.imprime_texto(strcat('Cantidad de variables de decision: ', num2str(this.iIndiceVarOpt)));
                        prot.imprime_texto(strcat('Dimension de funcion objetivo: ', num2str(length(this.Fobj))));
                        [m, n] = size(this.Aineq);
                        prot.imprime_texto(strcat('Dimension matriz de desigualdad: ', num2str(m), 'x', num2str(n)));
                        prot.imprime_texto(strcat('Dimension vector de desigualdad: ', num2str(length(this.bineq))));
                        prot.imprime_texto(strcat('Cantidad desigualdades: ', num2str(this.iIndiceIneq)));
                        [m, n] = size(this.Aeq);
                        prot.imprime_texto(strcat('Dimension matriz de igualdad: ', num2str(m), 'x', num2str(n)));
                        prot.imprime_texto(strcat('Dimension vector de igualdad: ', num2str(length(this.beq))));
                        prot.imprime_texto(strcat('Cantidad igualdades: ', num2str(this.iIndiceEq)));
                        prot.imprime_texto(strcat('Dimension vector lb: ', num2str(length(this.lb))));
                        prot.imprime_texto(strcat('Dimension vector ub: ', num2str(length(this.ub))));
                    end
                end
                if strcmp(this.pParOpt.Solver, 'Intlinprog')
                    if this.iNivelDebug > 0
                        if this.iNivelDebug > 1
                            options = optimoptions('linprog','Display','iter');
                        else
                            options = optimoptions('linprog','Display','final');
                        end
                    else
                        options = optimoptions('linprog','Display','off');
                    end

                    if this.MuestraDetalleIteraciones
                        % fuerza mostrar el detalle de las iteraciones,
                        % independiente del nivel de debug
                        options = optimoptions('linprog','Display','iter');
                    end
                    if ~this.pParOpt.DeterminaUC
                        [this.ResOptimizacion, this.Fval,this.ExitFlag,this.Output,this.Lambda]= linprog(this.Fobj,this.Aineq,this.bineq,this.Aeq,this.beq,this.lb,this.ub, [], options);
                    else
                        error = MException('cDCOPF:optimiza',...
                                           ['Optimizador "' this.pParOpt.Solver ' no está implementado para UC']);
                        throw(error)    
                    end
                elseif strcmp(this.pParOpt.Solver, 'Xpress')
                    options = xprsoptimset(optimset('Display', 'off'));
                    if this.iNivelDebug > 1 || this.MuestraDetalleIteraciones
                        options = xprsoptimset(optimset('Display', 'iter'));
                    end
                    
                    if ~this.pParOpt.DeterminaUC
                        rtype = [repmat('L',[1 size(this.Aineq,1)]) repmat('E',[1 size(this.Aeq,1)])];
                        [this.ResOptimizacion,this.Fval,this.ExitFlag,this.Output] = xprslp(this.Fobj,[this.Aineq; this.Aeq], [this.bineq; this.beq], rtype, this.lb,this.ub, options);%, options);
                    else
                        rtype = [repmat('L',[1 size(this.Aineq,1)]) repmat('E',[1 size(this.Aeq,1)])];
                        ctype = repmat('C', [1 size(this.Fobj,1)]);
                        ctype(this.intcon) = 'B';
                        %[this.ResOptimizacion,this.Fval,this.ExitFlag,this.Output] = xprsmip(this.Fobj,[this.Aineq; this.Aeq], [this.bineq; this.beq], rtype, ctype, [], [], this.lb,this.ub, x0);%, options);
                        [this.ResOptimizacion,this.Fval,this.ExitFlag,this.Output] = xprsmip(this.Fobj,[this.Aineq; this.Aeq], [this.bineq; this.beq], rtype, ctype, [], [], this.lb,this.ub, [], options);%, options);
                        
                    end
                else
                    error = MException('cDCOPF:optimiza',...
                                       ['Optimizador "' this.pParOpt.Solver ' no está implementado']);
                    throw(error)    
                end
                %redondea resultados
                this.ResOptimizacion = round(this.ResOptimizacion,this.pParOpt.DecimalesRedondeo);
            end
        end
        
		function escribe_resultados(this)
            cant_po = this.iCantPuntosOperacion;
            this.pResEvaluacion.ExisteResultadoOPF = true;
            
            if this.pParOpt.NivelDetalleResultados < 2 
                % se guardan sólo los resultados relevantes
                % consumos con ENS, Generadores con recorte y elementos de
                % red sobrecargados

                this.pResEvaluacion.CostoGeneracion = this.Fval;
                if this.pParOpt.ConsideraReservasMinimasSistema && this.pParOpt.EstrategiaReservasMinimasSistema == 2
                    indice_pmax_gen_desp_desde = this.IdVarOptPmaxGenDespDesde;
                    indice_pmax_gen_desp_hasta = indice_pmax_gen_desp_desde + this.iCantPuntosOperacion -1;
                    valor_var_aux = this.Fobj(indice_pmax_gen_desp_desde:indice_pmax_gen_desp_hasta)'*this.ResOptimizacion(indice_pmax_gen_desp_desde:indice_pmax_gen_desp_hasta);
                    this.pResEvaluacion.CostoGeneracion = this.pResEvaluacion.CostoGeneracion - valor_var_aux;
                end

                if this.pParOpt.NivelDetalleResultados == 1
                    % despacho generadores
                    p_generadores = zeros(this.Generadores.n, this.iCantPuntosOperacion);
                    for i = 1:this.Generadores.n
                        indice_desde = this.Generadores.IdVarOptDesde(i);
                        indice_hasta = indice_desde + cant_po - 1;
                        p_generadores(i,:) = this.ResOptimizacion(indice_desde:indice_hasta)';
                    end
                    if this.pParOpt.DeterminaUC
                        this.pResEvaluacion.UCGeneradores = ones(this.Generadores.n,this.iCantPuntosOperacion);
                        id_gen_uc = find(this.Generadores.IdVarOptUCDesde > 0);
                        for i = 1:length(id_gen_uc)
                            indice_desde = this.Generadores.IdVarOptUCDesde(id_gen_uc(i));
                            indice_hasta = indice_desde + cant_po - 1;
                            this.pResEvaluacion.UCGeneradores(id_gen_uc(i),:) = this.ResOptimizacion(indice_desde:indice_hasta)';
                        end
                    end
                end

                % verifica recorte res
                indices_gen_res = find(this.Generadores.Despachable == 0);
                for i = 1:length(indices_gen_res)
                    id_gen = indices_gen_res(i);
                    indice_desde = this.Generadores.IdVarOptDesde(id_gen);
                    indice_hasta = indice_desde + cant_po - 1;

                    if ~isempty(find(this.ResOptimizacion(indice_desde:indice_hasta) ~= 0, 1,'first'))
                        costo_recorte = this.Fobj(indice_desde:indice_hasta)'*this.ResOptimizacion(indice_desde:indice_hasta);
                        this.pResEvaluacion.CostoRecorteRES = this.pResEvaluacion.CostoRecorteRES + costo_recorte;
                        this.pResEvaluacion.inserta_generador_con_recorte_res(id_gen);
                        this.pResEvaluacion.CostoGeneracion = this.pResEvaluacion.CostoGeneracion - costo_recorte;
                    end
                    
                    if this.pParOpt.NivelDetalleResultados == 1
                        p_generadores(id_gen,:) = p_generadores(id_gen,:) - this.ResOptimizacion(indice_desde:indice_hasta)';
                    end
                end
                if this.pParOpt.NivelDetalleResultados == 1
                    this.pResEvaluacion.GeneradoresP = p_generadores*this.Sbase;
                end
                
                % verifica ENS
                for i = 1:this.Consumos.n
                    indice_desde = this.Consumos.IdVarOptDesde(i);
                    indice_hasta = indice_desde + cant_po - 1;

                    if ~isempty(find(this.ResOptimizacion(indice_desde:indice_hasta) ~= 0, 1,'first'))
                        costo_ens = this.Fobj(indice_desde:indice_hasta)'*this.ResOptimizacion(indice_desde:indice_hasta);
                        this.pResEvaluacion.CostoENS = this.pResEvaluacion.CostoENS + costo_ens;
                        this.pResEvaluacion.inserta_consumo_con_ens(i);                        
                                                
                        this.pResEvaluacion.CostoGeneracion = this.pResEvaluacion.CostoGeneracion - costo_ens;
                    end
                    if this.pParOpt.NivelDetalleResultados == 1
                        this.pResEvaluacion.ConsumosP(i,:) = this.Sbase*(this.ub(indice_desde:indice_hasta)-this.ResOptimizacion(indice_desde:indice_hasta))';
                    end
                end

                % líneas flujo máximo y poco uso
                id_observacion = find(this.Lineas.FlagObservacion == 1);
                for i = 1:length(id_observacion)
                    id_linea = id_observacion(i);
                    indice_desde = this.Lineas.IdVarOptDesde(id_linea);
                    indice_hasta = indice_desde + cant_po - 1;
                    max_p_mw = max(abs(this.ResOptimizacion(indice_desde:indice_hasta)));

                    if this.Lineas.Pmax(id_linea)*this.pParOpt.PorcentajeUsoFlujosAltos <= max_p_mw
                        el_red = this.Lineas.ElRed(id_linea);
                        id_par = el_red.entrega_indice_paralelo();
                        id_se1 = el_red.entrega_se1().entrega_id();
                        id_se2 = el_red.entrega_se2().entrega_id();
                        if ~isempty(this.pResEvaluacion.LineasFlujoMaximo)
                            existente = find(this.pResEvaluacion.LineasFlujoMaximo(:,3) == id_se1 & this.pResEvaluacion.LineasFlujoMaximo(:,4) == id_se2);
                            if isempty(existente)
                                this.pResEvaluacion.LineasFlujoMaximo = [this.pResEvaluacion.LineasFlujoMaximo; ...
                                    [id_linea id_par id_se1 id_se2 max_p_mw/this.Lineas.Pmax(id_linea)]];
                            else
                                if this.pResEvaluacion.LineasFlujoMaximo(existente, 2) < id_par
                                    this.pResEvaluacion.LineasFlujoMaximo(existente, 1:2) = [id_linea id_par];
                                end
                            end
                        else
                            this.pResEvaluacion.LineasFlujoMaximo = [id_linea id_par id_se1 id_se2 max_p_mw/this.Lineas.Pmax(id_linea)];
                        end
                    elseif this.Lineas.Pmax(id_linea)*this.pParOpt.PorcentajeUsoFlujosBajos >= max_p_mw
                        el_red = this.Lineas.ElRed(id_linea);
                        id_par = el_red.entrega_indice_paralelo();
                        id_se1 = el_red.entrega_se1().entrega_id();
                        id_se2 = el_red.entrega_se2().entrega_id();
                        
                        if ~isempty(this.pResEvaluacion.LineasPocoUso)
                            existente = find(this.pResEvaluacion.LineasPocoUso(:,3) == id_se1 & this.pResEvaluacion.LineasPocoUso(:,4) == id_se2);
                            if isempty(existente)
                                this.pResEvaluacion.LineasPocoUso = [this.pResEvaluacion.LineasPocoUso; ...
                                    [id_linea id_par id_se1 id_se2 max_p_mw/this.Lineas.Pmax(id_linea)]];
                            else
                                if this.pResEvaluacion.LineasPocoUso(existente, 2) < id_par
                                    this.pResEvaluacion.LineasPocoUso(existente, 1:2) = [id_linea id_par];
                                end
                            end
                        else
                            this.pResEvaluacion.LineasPocoUso = [id_linea id_par id_se1 id_se2 max_p_mw/this.Lineas.Pmax(id_linea)];
                        end
                    end
                end
                
                % trafos flujo máximo y poco uso
                id_observacion = find(this.Trafos.FlagObservacion == 1);
                for i = 1:length(id_observacion)
                    id_trafo = id_observacion(i);
                    indice_desde = this.Trafos.IdVarOptDesde(id_trafo);
                    indice_hasta = indice_desde + cant_po - 1;
                    max_p_mw = max(abs(this.ResOptimizacion(indice_desde:indice_hasta)));

                    if this.Trafos.Pmax(id_trafo)*this.pParOpt.PorcentajeUsoFlujosAltos <= max_p_mw
                        el_red = this.Trafos.ElRed(id_trafo);
                        id_par = el_red.entrega_indice_paralelo();
                        id_se1 = el_red.entrega_se1().entrega_id();
                        id_se2 = el_red.entrega_se2().entrega_id();
                        if ~isempty(this.pResEvaluacion.TrafosFlujoMaximo)
                            existente = find(this.pResEvaluacion.TrafosFlujoMaximo(:,3) == id_se1 & this.pResEvaluacion.TrafosFlujoMaximo(:,4) == id_se2);
                            if isempty(existente)
                                this.pResEvaluacion.TrafosFlujoMaximo = [this.pResEvaluacion.TrafosFlujoMaximo; ...
                                    [id_trafo id_par id_se1 id_se2 max_p_mw/this.Trafos.Pmax(id_trafo)]];
                            else
                                if this.pResEvaluacion.TrafosFlujoMaximo(existente, 2) < id_par
                                    this.pResEvaluacion.TrafosFlujoMaximo(existente, 1:2) = [id_trafo id_par];
                                end
                            end
                        else
                            this.pResEvaluacion.TrafosFlujoMaximo = [id_trafo id_par id_se1 id_se2 max_p_mw/this.Trafos.Pmax(id_trafo)];
                        end
                    elseif this.Trafos.Pmax(id_trafo)*this.pParOpt.PorcentajeUsoFlujosBajos >= max_p_mw
                        el_red = this.Trafos.ElRed(id_trafo);
                        id_par = el_red.entrega_indice_paralelo();
                        id_se1 = el_red.entrega_se1().entrega_id();
                        id_se2 = el_red.entrega_se2().entrega_id();
                        if ~isempty(this.pResEvaluacion.TrafosPocoUso)
                            existente = find(this.pResEvaluacion.TrafosPocoUso(:,3) == id_se1 & this.pResEvaluacion.TrafosPocoUso(:,4) == id_se2);
                            if isempty(existente)
                                this.pResEvaluacion.TrafosPocoUso = [this.pResEvaluacion.TrafosPocoUso; ...
                                    [id_trafo id_par id_se1 id_se2 max_p_mw/this.Trafos.Pmax(id_trafo)]];
                            else
                                if this.pResEvaluacion.TrafosPocoUso(existente, 2) < id_par
                                    this.pResEvaluacion.TrafosPocoUso(existente, 1:2) = [id_trafo id_par];
                                end
                            end
                        else
                            this.pResEvaluacion.TrafosPocoUso = [id_trafo id_par id_se1 id_se2 max_p_mw/this.Trafos.Pmax(id_trafo)];
                        end
                    end
                end
                
                % baterías uso máximo y poco uso
                if this.bConsideraDependenciaTemporal
                    for i = 1:this.Baterias.n
                        indice_desde = this.Baterias.IdVarOptDesdeE(i);
                        indice_hasta = indice_desde + cant_po - 1;
                        e_bateria = this.ResOptimizacion(indice_desde:indice_hasta)*this.Sbase;
                        uso_bat = max(e_bateria)-min(e_bateria);
                        delta_e_max = this.Baterias.ElRed(i).entrega_capacidad_efectiva();
                        uso_efectivo = uso_bat/delta_e_max;
                        if uso_efectivo > this.pParOpt.PorcentajeUsoAltoBateria
                            this.pResEvaluacion.inserta_bateria_uso_maximo(this.Baterias.ElRed(i), uso_efectivo);
                        elseif uso_efectivo < this.pParOpt.PorcentajeUsoBajoBateria
                            this.pResEvaluacion.inserta_bateria_poco_uso(this.Baterias.ElRed(i), uso_efectivo);
                        end
                    end
                end
            else
                % en este caso se guardan los datos detallados por cada punto de operación

                % subestaciones
                for i = 1:this.Subestaciones.n
                    indice_desde = this.Subestaciones.IdVarOptDesde(i);
                    indice_hasta = indice_desde + cant_po -1;
                    theta = this.ResOptimizacion(indice_desde:indice_hasta);
                    this.pResEvaluacion.AnguloSubestaciones(i, :) = theta'/pi*180;
                end
                
                % generadores despachables
                indices_gen_desp = find(this.Generadores.Despachable == 1);
                for i = 1:length(indices_gen_desp)
                    id_gen = indices_gen_desp(i);
                    indice_desde = this.Generadores.IdVarOptDesde(id_gen);
                    indice_hasta = indice_desde + cant_po - 1;

                    costo_generacion = this.Fobj(indice_desde:indice_hasta).*this.ResOptimizacion(indice_desde:indice_hasta);
                    this.pResEvaluacion.GeneradoresP(id_gen, :) = (this.ResOptimizacion(indice_desde:indice_hasta)*this.Sbase)';
                    this.pResEvaluacion.CostoGeneracion = this.pResEvaluacion.CostoGeneracion + costo_generacion';
                end

                if this.pParOpt.DeterminaUC
                    this.pResEvaluacion.UCGeneradores = ones(this.Generadores.n,this.iCantPuntosOperacion);
                    this.pResEvaluacion.CostoEncendidoGeneradores = zeros(1,this.iCantPuntosOperacion);
                    id_gen_uc = find(this.Generadores.IdVarOptUCDesde > 0);
                    for i = 1:length(id_gen_uc)
                        indice_desde = this.Generadores.IdVarOptUCDesde(id_gen_uc(i));
                        indice_hasta = indice_desde + cant_po - 1;
                        this.pResEvaluacion.UCGeneradores(id_gen_uc(i),:) = this.ResOptimizacion(indice_desde:indice_hasta)';

                        indice_desde = this.Generadores.IdVarOptCostoPartidaDesde(id_gen_uc(i));
                        indice_hasta = indice_desde + cant_po - 1;
                        costo_encendido = this.Fobj(indice_desde:indice_hasta).*this.ResOptimizacion(indice_desde:indice_hasta)/this.Sbase;
                        this.pResEvaluacion.CostoEncendidoGeneradores = this.pResEvaluacion.CostoEncendidoGeneradores + costo_encendido';
                    end
                end

                % generadores ernc
                indices_gen_res = find(this.Generadores.Despachable == 0);
                for i = 1:length(indices_gen_res)
                    id_gen = indices_gen_res(i);
                    indice_desde = this.Generadores.IdVarOptDesde(id_gen);
                    indice_hasta = indice_desde + cant_po - 1;

                    this.pResEvaluacion.RecorteRES(id_gen, :) = (this.ResOptimizacion(indice_desde:indice_hasta)*this.Sbase)';
            
                    if ~isempty(find(this.ResOptimizacion(indice_desde:indice_hasta) ~= 0, 1,'first'))
                        costo_recorte = this.Fobj(indice_desde:indice_hasta).*this.ResOptimizacion(indice_desde:indice_hasta);
                        this.pResEvaluacion.CostoRecorteRES = this.pResEvaluacion.CostoRecorteRES + costo_recorte';
                        this.pResEvaluacion.inserta_generador_con_recorte_res(id_gen);                        
                    end
                    
                    if ~isempty(this.pAdmSc)
                        perfil = this.pAdmSc.entrega_perfil_ernc(this.Generadores.IdAdmEscenarioPerfil(id_gen));
                        pnom = this.Generadores.Pmax(id_gen)*perfil*this.Sbase;
                    else
                        pnom = this.Generadores.ElRed(id_gen).entrega_p0();
                    end
                    this.pResEvaluacion.GeneradoresP(id_gen, :) = pnom - this.pResEvaluacion.RecorteRES(id_gen, :);
                end

                % baterias
                for i = 1:this.Baterias.n
                    indice_descarga_desde = this.Baterias.IdVarOptDesdeDescarga(i);
                    indice_descarga_hasta = indice_descarga_desde + cant_po - 1;

                    indice_carga_desde = this.Baterias.IdVarOptDesdeCarga(i);
                    indice_carga_hasta = indice_carga_desde + cant_po - 1;
                    
                    p_baterias = (this.ResOptimizacion(indice_descarga_desde:indice_descarga_hasta)-this.ResOptimizacion(indice_carga_desde:indice_carga_hasta))*this.Sbase;
                    this.pResEvaluacion.BateriasP(i,:) = p_baterias';
                    
                    if this.bConsideraDependenciaTemporal
                        indice_desde = this.Baterias.IdVarOptDesdeE(i);
                        indice_hasta = indice_desde + cant_po - 1;
                        e_bateria = this.ResOptimizacion(indice_desde:indice_hasta)*this.Sbase;
                        this.pResEvaluacion.BateriasE(i,:) = e_bateria';

                        uso_bat = max(e_bateria)-min(e_bateria);
                        delta_e_max = this.Baterias.ElRed(i).entrega_capacidad_efectiva();
                        uso_efectivo = uso_bat/delta_e_max;
                        if uso_efectivo > this.pParOpt.PorcentajeUsoAltoBateria
                            this.pResEvaluacion.inserta_bateria_uso_maximo(this.Baterias.ElRed(i), uso_efectivo);
                        elseif uso_efectivo < this.pParOpt.PorcentajeUsoBajoBateria
                            this.pResEvaluacion.inserta_bateria_poco_uso(this.Baterias.ElRed(i), uso_efectivo);
                        end
                    end
                end
                
                % consumos
                for i = 1:this.Consumos.n
                    indice_desde = this.Consumos.IdVarOptDesde(i);
                    indice_hasta = indice_desde + cant_po - 1;

                    p_mw_ens = (this.ResOptimizacion(indice_desde:indice_hasta)*this.Sbase)';
                    this.pResEvaluacion.ENS(i, :) = p_mw_ens;
                    
                    if ~isempty(this.pAdmSc)
                        perfil = this.pAdmSc.entrega_perfil_consumo(this.Consumos.IdAdmEscenarioPerfil(i));
                        p_consumo = this.Consumos.Pmax(i)*perfil*this.Sbase;
                    else
                        p_consumo = -this.Consumos.ElRed(i).entrega_p_const_nom(); % valor positivo y en unidades reales
                    end
                    
                    this.pResEvaluacion.ConsumosP(i, :) = (p_consumo-p_mw_ens);
                    if ~isempty(find(p_mw_ens ~= 0, 1, 'first'))
                        costo_ens = this.Fobj(indice_desde:indice_hasta).*this.ResOptimizacion(indice_desde:indice_hasta);
                        this.pResEvaluacion.CostoENS = this.pResEvaluacion.CostoENS + costo_ens';
                        this.pResEvaluacion.inserta_consumo_con_ens(i);
                    end
                end

                % lineas
                for i = 1:this.Lineas.n
                    indice_desde = this.Lineas.IdVarOptDesde(i);
                    indice_hasta = indice_desde + cant_po - 1;
                    p_mw = this.ResOptimizacion(indice_desde:indice_hasta)*this.Sbase;
                    this.pResEvaluacion.FlujoLineasP(i, :) = p_mw';
                                        
                    if this.Lineas.FlagObservacion(i) == 1
                        max_p_mw = max(abs(this.ResOptimizacion(indice_desde:indice_hasta)));
                        
                        if this.Lineas.Pmax(i)*this.pParOpt.PorcentajeUsoFlujosAltos <= max_p_mw
                            el_red = this.Lineas.ElRed(i);
                            id_par = el_red.entrega_indice_paralelo();
                            id_se1 = el_red.entrega_se1().entrega_id();
                            id_se2 = el_red.entrega_se2().entrega_id();
                            if ~isempty(this.pResEvaluacion.LineasFlujoMaximo)
                                existente = find(this.pResEvaluacion.LineasFlujoMaximo(:,3) == id_se1 & this.pResEvaluacion.LineasFlujoMaximo(:,4) == id_se2);
                                if isempty(existente)
                                    this.pResEvaluacion.LineasFlujoMaximo = [this.pResEvaluacion.LineasFlujoMaximo; ...
                                        [i id_par id_se1 id_se2 max_p_mw/this.Lineas.Pmax(i)]];
                                else
                                    if this.pResEvaluacion.LineasFlujoMaximo(existente, 2) < id_par
                                        this.pResEvaluacion.LineasFlujoMaximo(existente, 1:2) = [i id_par];
                                    end
                                end
                            else
                                this.pResEvaluacion.LineasFlujoMaximo = [this.pResEvaluacion.LineasFlujoMaximo; ...
                                    [i id_par id_se1 id_se2 max_p_mw/this.Lineas.Pmax(i)]];
                            end                                
                        elseif this.Lineas.Pmax(i)*this.pParOpt.PorcentajeUsoFlujosBajos >= max_p_mw
                            el_red = this.Lineas.ElRed(i);
                            id_par = el_red.entrega_indice_paralelo();
                            id_se1 = el_red.entrega_se1().entrega_id();
                            id_se2 = el_red.entrega_se2().entrega_id();
                            if ~isempty(this.pResEvaluacion.LineasPocoUso)
                                existente = find(this.pResEvaluacion.LineasPocoUso(:,3) == id_se1 & this.pResEvaluacion.LineasPocoUso(:,4) == id_se2);
                                if isempty(existente)
                                    this.pResEvaluacion.LineasPocoUso = [this.pResEvaluacion.LineasPocoUso; ...
                                        [i id_par id_se1 id_se2 max_p_mw/this.Lineas.Pmax(i)]];
                                else
                                    if this.pResEvaluacion.LineasPocoUso(existente, 2) < id_par
                                        this.pResEvaluacion.LineasPocoUso(existente, 1:2) = [i id_par];
                                    end
                                end
                            else
                                this.pResEvaluacion.LineasPocoUso = [this.pResEvaluacion.LineasPocoUso; ...
                                    [i id_par id_se1 id_se2 max_p_mw/this.Lineas.Pmax(i)]];
                            end
                        end
                    end
                end
                
                % trafos
                for i = 1:this.Trafos.n
                    indice_desde = this.Trafos.IdVarOptDesde(i);
                    indice_hasta = indice_desde + cant_po - 1;
                    p_mw = this.ResOptimizacion(indice_desde:indice_hasta)*this.Sbase;
                    this.pResEvaluacion.FlujoTransformadoresP(i, :) = p_mw';

                    if this.Trafos.FlagObservacion(i) == 1
                        max_p_mw = max(abs(this.ResOptimizacion(indice_desde:indice_hasta)));
                                                
                        if this.Trafos.Pmax(i)*this.pParOpt.PorcentajeUsoFlujosAltos <= max_p_mw
                            el_red = this.Trafos.ElRed(i);
                            id_par = el_red.entrega_indice_paralelo();
                            id_se1 = el_red.entrega_se1().entrega_id();
                            id_se2 = el_red.entrega_se2().entrega_id();
                            if ~isempty(this.pResEvaluacion.TrafosFlujoMaximo)
                                existente = find(this.pResEvaluacion.TrafosFlujoMaximo(:,3) == id_se1 & this.pResEvaluacion.TrafosFlujoMaximo(:,4) == id_se2);
                                if isempty(existente)
                                    this.pResEvaluacion.TrafosFlujoMaximo = [this.pResEvaluacion.TrafosFlujoMaximo; ...
                                        [i id_par id_se1 id_se2 max_p_mw/this.Trafos.Pmax(i)]];
                                else
                                    if this.pResEvaluacion.TrafosFlujoMaximo(existente, 2) < id_par
                                        this.pResEvaluacion.TrafosFlujoMaximo(existente, 1:2) = [i id_par];
                                    end
                                end
                            else
                                this.pResEvaluacion.TrafosFlujoMaximo = [this.pResEvaluacion.TrafosFlujoMaximo; ...
                                    [i id_par id_se1 id_se2 max_p_mw/this.Trafos.Pmax(i)]];
                            end                                
                        elseif this.Trafos.Pmax(i)*this.pParOpt.PorcentajeUsoFlujosBajos >= max_p_mw
                            el_red = this.Trafos.ElRed(i);
                            id_par = el_red.entrega_indice_paralelo();
                            id_se1 = el_red.entrega_se1().entrega_id();
                            id_se2 = el_red.entrega_se2().entrega_id();
                            if ~isempty(this.pResEvaluacion.TrafosPocoUso)
                                existente = find(this.pResEvaluacion.TrafosPocoUso(:,3) == id_se1 & this.pResEvaluacion.TrafosPocoUso(:,4) == id_se2);
                                if isempty(existente)
                                    this.pResEvaluacion.TrafosPocoUso = [this.pResEvaluacion.TrafosPocoUso; ...
                                        [i id_par id_se1 id_se2 max_p_mw/this.Trafos.Pmax(i)]];
                                else
                                    if this.pResEvaluacion.TrafosPocoUso(existente, 2) < id_par
                                        this.pResEvaluacion.TrafosPocoUso(existente, 1:2) = [i id_par];
                                    end
                                end
                            else
                                this.pResEvaluacion.TrafosPocoUso = [this.pResEvaluacion.TrafosPocoUso; ...
                                    [i id_par id_se1 id_se2 max_p_mw/this.Trafos.Pmax(i)]];
                            end
                        end
                    end
                end
                
                % embalses
                for i = 1:this.Embalses.n
                    indice_vol_desde = this.Embalses.IdVarOptDesde(i);
                    indice_vol_hasta = indice_vol_desde + cant_po - 1;                    
                    vol_embalse = 3600*this.ResOptimizacion(indice_vol_desde:indice_vol_hasta);
                    this.pResEvaluacion.EmbalsesVol(i,:) = vol_embalse';

                    indice_vert_desde = this.Embalses.IdVarOptVertimientoDesde(i);
                    indice_vert_hasta = indice_vert_desde + cant_po - 1;
                    vert_embalse = 3600*this.ResOptimizacion(indice_vert_desde:indice_vert_hasta);
                    this.pResEvaluacion.EmbalsesVert(i,:) = vert_embalse';
                    
                    indice_filt_desde = this.Embalses.IdVarOptFiltracionDesde(i);
                    if indice_filt_desde > 0
                        indice_filt_hasta = indice_filt_desde + cant_po - 1;
                        filt_embalses = 3600*this.ResOptimizacion(indice_filt_desde:indice_filt_hasta);
                        this.pResEvaluacion.EmbalsesFilt(i,:) = filt_embalses';
                    end
                end
            end
        end

        function imprime_resultados_protocolo(this)
            if this.pParOpt.NivelDetalleResultados
                dec_redondeo = this.pParOpt.DecimalesRedondeo;

                prot = cProtocolo.getInstance;
                sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
                if this.iNivelDebug > 1
                    prot.imprime_texto('');
                    prot.imprime_texto('Resultados DC-OPF');
                    prot.imprime_texto('Resultado variables optimizacion');
                    for i = 1:length(this.ResOptimizacion)
                        texto = sprintf('%10s %5s %35s %3s %10s %5s %10s ', ...
                            num2str(this.lb(i)), '<=', this.NombreVariables{i}, '=', ...
                            num2str(this.ResOptimizacion(i)), '<=', num2str(this.ub(i)));
                        prot.imprime_texto(texto);
                    end
                end

                baterias_todas = this.Baterias.ElRed;
                p_baterias_carga = zeros(this.Baterias.n,this.iCantPuntosOperacion);
                p_baterias_descarga = zeros(this.Baterias.n,this.iCantPuntosOperacion);
                e_baterias = zeros(this.Baterias.n,this.iCantPuntosOperacion);
                
                if this.pParOpt.DeterminaUC
                    id_gen_uc = find(this.Generadores.IdVarOptUCDesde > 0);
                    cant_gen_uc = length(id_gen_uc);
                    p_gen_uc = zeros(cant_gen_uc, this.iCantPuntosOperacion);
                    estado_gen_uc = zeros(cant_gen_uc, this.iCantPuntosOperacion);
                    costo_partida_gen_uc = zeros(cant_gen_uc, this.iCantPuntosOperacion);
                end
                
                prot.imprime_texto(['Etapa: ' num2str(this.iEtapa)]);
                for oper = 1:this.iCantPuntosOperacion
                    prot.imprime_texto('');
                    prot.imprime_texto(['PO: ' num2str(oper)]);
                    prot.imprime_texto('Balance de energia');
                    texto = sprintf('%-15s %-15s %-15s %-10s %-10s %-10s %-10s %-10s %-10s %-10s', 'Subestacion', 'Generacion', 'Bateria', 'ERNC', 'Consumo', 'Spill', 'ENS', 'Pin', 'Pout', 'Balance');
                    prot.imprime_texto(texto);

                    gen_total_oper = 0;
                    res_total_oper = 0;
                    gen_bat_total_oper = 0;
                    consumo_total_oper = 0;
                    spill_total_oper = 0;
                    ens_total_oper = 0;

                    buses = this.pSEP.entrega_subestaciones();
                    for bus = 1:length(buses)
                        suma_gen = 0;
                        suma_capacidad_gen = 0;
                        
                        generadores = buses(bus).entrega_generadores_despachables();
                        for gen = 1:length(generadores)
                            id_gen = generadores(gen).entrega_id();
                            indice_opt = this.Generadores.IdVarOptDesde(id_gen) + oper - 1;
                            p_mw = this.ResOptimizacion(indice_opt)*sbase;
                            pmax = this.Generadores.Pmax(id_gen)*sbase;
                            suma_capacidad_gen = suma_capacidad_gen + pmax;
                            suma_gen = suma_gen + p_mw;
                        end
                        
                        % baterías
                        suma_bat = 0;
                        suma_capacidad_bat = 0;
                        baterias = buses(bus).entrega_baterias();
                        for bat = 1:length(baterias)
                            id_bat = baterias(bat).entrega_id();                            
                            indice_opt_descarga = this.Baterias.IdVarOptDesdeDescarga(id_bat) + oper -1;
                            indice_opt_carga = this.Baterias.IdVarOptDesdeCarga(id_bat) + oper -1;
                            p_mw = (this.ResOptimizacion(indice_opt_descarga)-this.ResOptimizacion(indice_opt_carga))*sbase;
                            if round(this.ResOptimizacion(indice_opt_descarga), 2) ~= 0 && round(this.ResOptimizacion(indice_opt_carga),2) ~= 0
                                %warning('Bateria se descarga y carga a la vez!')
                            end

                            pmax_descarga = baterias(bat).entrega_pmax_descarga();
                            %pmax_carga = this.Baterias.Carga(id_bat)*sbase;
                            suma_capacidad_bat = suma_capacidad_bat + pmax_descarga;
                            suma_bat = suma_bat + p_mw;
                            gen_bat_total_oper = gen_bat_total_oper + suma_bat;

                            indice_opt_e = this.Baterias.IdVarOptDesdeE(id_bat) + oper - 1;
                            e_bat = this.ResOptimizacion(indice_opt_e)*sbase;
                            p_baterias_carga(id_bat, oper) = this.ResOptimizacion(indice_opt_carga)*sbase;
                            p_baterias_descarga(id_bat, oper) = this.ResOptimizacion(indice_opt_descarga)*sbase;
                            e_baterias(id_bat, oper) = e_bat;
                        end
                        
                        % generadores RES
                        spill = 0;
                        gen_res = 0;
                        generadores_ernc = buses(bus).entrega_generadores_res();
                        for gen = 1:length(generadores_ernc)
                            id_gen = generadores_ernc(gen).entrega_id();
                            if this.Generadores.IdAdmEscenarioPerfil(id_gen) ~= 0
                                perfil = this.pAdmSc.entrega_perfil_ernc(this.Generadores.IdAdmEscenarioPerfil(id_gen));
                                pnom = this.Generadores.Pmax(id_gen)*perfil(oper)*sbase;
                            else
                                pnom = generadores_ernc(gen).entrega_p0(oper);
                            end

                            gen_res = gen_res + pnom;
                            indice_opt = this.Generadores.IdVarOptDesde(id_gen) + oper - 1;
                            p_mw_recorte = this.ResOptimizacion(indice_opt)*sbase;
                            spill = spill + p_mw_recorte;
                        end

                        %consumos
                        p_consumo_nom = 0;
                        p_ens = 0;
                        consumos = buses(bus).entrega_consumos();
                        for con = 1:length(consumos)
                            id_con = consumos(con).entrega_id();
                            indice_opt = this.Consumos.IdVarOptDesde(id_con) + oper - 1;
                            ens = this.ResOptimizacion(indice_opt)*sbase;

                            if this.Consumos.IdAdmEscenarioPerfil(id_con) ~= 0
                                indice_perfil = this.Consumos.IdAdmEscenarioPerfil(id_con);
                                perfil = this.pAdmSc.entrega_perfil_consumo(indice_perfil);
                                capacidad = this.Consumos.Pmax(id_con)*sbase;
                                p0 = capacidad*perfil(oper);
                            else
                                % sólo un punto de operación
                                p0 = -consumos(con).entrega_p_const_nom(oper); %p0 tiene valor positivo
                            end

                            p_consumo_nom = p_consumo_nom + p0;
                            p_ens = p_ens + ens;
                        end

                        %lineas y trafos
                        pin = 0;
                        pout = 0;
                        eserie = buses(bus).entrega_elementos_serie();
                        for j = 1:length(eserie)
                            id_eserie = eserie(j).entrega_id();
                            bus1 = eserie(j).entrega_se1();
                            if bus1 == buses(bus)
                                signo = -1;
                            else
                                signo = 1;
                            end

                            if isa(eserie(j),'cLinea')
                                indice_opt = this.Lineas.IdVarOptDesde(id_eserie) + oper - 1;
                            else
                                indice_opt = this.Trafos.IdVarOptDesde(id_eserie) + oper - 1;
                            end
                            flujo_p = this.ResOptimizacion(indice_opt)*sbase;
                            if signo*flujo_p < 0
                                pout = pout - signo*flujo_p;
                            else
                                pin = pin + signo*flujo_p;
                            end                        
                        end % fin elementos serie

                        gen_total_oper = gen_total_oper + suma_gen;
                        res_total_oper = res_total_oper + gen_res;
                        consumo_total_oper = consumo_total_oper + p_consumo_nom;
                        spill_total_oper = spill_total_oper + spill;
                        ens_total_oper = ens_total_oper + p_ens;

                        texto_generacion = [num2str(suma_gen) '/' num2str(suma_capacidad_gen)];
                        texto_bateria = [num2str(suma_bat) '/' num2str(suma_capacidad_bat)];
                        texto = sprintf('%-15s %-15s %-15s %-10s %-10s %-10s %-10s %-10s %-10s %-10s', buses(bus).entrega_nombre(), ...
                            texto_generacion,...
                            texto_bateria, ...
                            num2str(round(gen_res,dec_redondeo)),...
                            num2str(round(p_consumo_nom,dec_redondeo)),...
                            num2str(round(spill,dec_redondeo)),...
                            num2str(round(p_ens,dec_redondeo)),...
                            num2str(round(pin,dec_redondeo)),...
                            num2str(round(pout,dec_redondeo)),...
                            num2str(round(suma_gen+gen_res+suma_bat-p_consumo_nom+p_ens-spill+pin-pout,dec_redondeo)));
                        prot.imprime_texto(texto);
                    end %fin buses

                    if this.pParOpt.DeterminaUC                        
                        for gen_uc = 1:cant_gen_uc
                            id_gen = id_gen_uc(gen_uc);
                            indice_opt = this.Generadores.IdVarOptDesde(id_gen) + oper - 1;
                            p_gen_uc(gen_uc, oper) = this.ResOptimizacion(indice_opt)*sbase;

                            indice_opt = this.Generadores.IdVarOptUCDesde(id_gen) + oper - 1;
                            estado_gen_uc(gen_uc, oper) = this.ResOptimizacion(indice_opt);

                            indice_opt = this.Generadores.IdVarOptCostoPartidaDesde(id_gen) + oper - 1;
                            costo_partida_gen_uc(gen_uc, oper) = this.ResOptimizacion(indice_opt)*this.Sbase;
                        end
                    end                            
                    
                    texto = sprintf('%-15s %-15s %-15s %-10s %-10s %-10s %-10s %-10s %-10s %-10s', 'Total', ...
                        num2str(round(gen_total_oper,dec_redondeo)),...
                        num2str(round(gen_bat_total_oper,dec_redondeo)),...
                        num2str(round(res_total_oper,dec_redondeo)),...
                        num2str(round(consumo_total_oper,dec_redondeo)),...
                        num2str(round(spill_total_oper,dec_redondeo)),...
                        num2str(round(ens_total_oper,dec_redondeo)),...
                        '-',...
                        '-',...
                        '-');
                    prot.imprime_texto(texto);

                    % ahora se imprimen los resultados por subestación detallando
                    % las líneas/trafos
                    prot.imprime_texto('');
                    prot.imprime_texto('Detalle de flujos por subestacion');
                    texto = sprintf('%-25s %-15s %-15s %-7s %-8s %-8s %-8s %-8s %-8s %-8s %-25s', ...
                            'Linea', 'SE1', 'SE2', 'Signo', 'T1grad', 'T2grad', 'T1-T2', 'Xel', 'PMW', 'Pmax', 'Dif.calculado');
                    prot.imprime_texto(texto);
                    for bus1 = 1:length(buses)
                        eserie = buses(bus1).entrega_elementos_serie();
                        for bus2 = bus1+1:length(buses)
                            for j = 1:length(eserie)
                                bus_inicial = eserie(j).entrega_se1();
                                bus_final = eserie(j).entrega_se2();

                                if bus_inicial ~= buses(bus2) && bus_final ~= buses(bus2)
                                    continue;
                                end
                                    if isa(eserie(j),'cLinea')
                                        indice_eserie_p = this.Lineas.IdVarOptDesde(eserie(j).entrega_id()) + oper - 1;
                                    else
                                        indice_eserie_p = this.Trafos.IdVarOptDesde(eserie(j).entrega_id()) + oper - 1;
                                    end
                                
                                    p_serie = this.ResOptimizacion(indice_eserie_p)*sbase;
                                    sr = eserie(j).entrega_sr();

                                    indice_bus1 = this.Subestaciones.IdVarOptDesde(bus1) + oper - 1;
                                    t1 = this.ResOptimizacion(indice_bus1);
                                    indice_bus2 = this.Subestaciones.IdVarOptDesde(bus2) + oper - 1;
                                    t2 = this.ResOptimizacion(indice_bus2);

                                    if bus_inicial == buses(bus1)
                                        signo = 1; % linea va de SE1 a SE2 por lo que flujo sale de la subestacion
                                    else
                                        signo = -1;
                                    end
                                    x = eserie(j).entrega_reactancia_pu();
                                    angulo_1 = round(t1/pi*180,dec_redondeo);
                                    angulo_2 = round(t2/pi*180,dec_redondeo);

                                    diff_angulo = round((t1-t2)/pi*180,dec_redondeo);
                                    diff_calculado = signo*(t1-t2)/x*sbase;
                                    diff_calculado = diff_calculado-p_serie;
                                    texto = sprintf('%-25s %-15s %-15s %-7s %-8s %-8s %-8s %-8s %-8s %-8s %-25s', ...
                                            eserie(j).entrega_nombre(), ...
                                            buses(bus1).entrega_nombre(), ...
                                            buses(bus2).entrega_nombre(), ...
                                            num2str(signo), ...
                                            num2str(round(angulo_1,dec_redondeo)), ...
                                            num2str(round(angulo_2,dec_redondeo)), ...
                                            num2str(round(diff_angulo,dec_redondeo)), ...
                                            num2str(round(x,dec_redondeo)), ...
                                            num2str(round(p_serie,dec_redondeo)), ...
                                            num2str(round(sr,dec_redondeo)), ...
                                            num2str(round(diff_calculado,dec_redondeo)));
                                        prot.imprime_texto(texto);
                            end
                        end %fin subestaciones destino
                    end % fin subestaciones origen
                end % fin puntos de operación

                % balance energético baterías
                if ~isempty(baterias_todas)
                    prot.imprime_texto('');
                    prot.imprime_texto(['Balance energetico baterias en etapa ' num2str(this.iEtapa) ':']);

                    p_baterias_carga = round(p_baterias_carga,2);
                    p_baterias_descarga = round(p_baterias_descarga,2);
                    e_baterias = round(e_baterias, 2);
                    [cant_po_consecutivos,~] = size(this.vIndicesPOConsecutivos);
                    for i = 1:length(baterias_todas)
                        prot.imprime_texto(['Balance energetico bateria ' baterias_todas(i).entrega_nombre()]);
                        
                        eta_descarga = baterias_todas(i).entrega_eficiencia_descarga();                    
                        eta_carga = baterias_todas(i).entrega_eficiencia_carga();                    

                        for periodo = 1:cant_po_consecutivos
                            prot.imprime_texto(['Periodo ' num2str(periodo) '/' num2str(cant_po_consecutivos)]);

                            hora_desde_periodo = this.vIndicesPOConsecutivos(periodo,1);
                            hora_hasta_periodo = this.vIndicesPOConsecutivos(periodo,2);
                            ancho_periodo = hora_hasta_periodo - hora_desde_periodo + 1;

                            texto_base = sprintf('%-15s','Hora Act');
                            for j = hora_desde_periodo:hora_hasta_periodo
                                texto_base = [texto_base sprintf('%-10s',num2str(j))];
                            end
                            prot.imprime_texto(texto_base);
                            texto_base = sprintf('%-15s','Hora rel');
                            for j = 1:ancho_periodo
                                texto_base = [texto_base sprintf('%-10s',num2str(j))];
                            end
                            prot.imprime_texto(texto_base);
                    
                            texto_base_p = sprintf('%-15s','Pbat');
                            texto_base_e = sprintf('%-15s','Ebat');
                            texto_base_bal = sprintf('%-15s','Balance');
                            for hora_rel = 1:ancho_periodo
                                t_actual = hora_desde_periodo + hora_rel - 1;
                                texto_base_p = [texto_base_p sprintf('%-10s',num2str(p_baterias_descarga(i,t_actual)-p_baterias_carga(i,t_actual)))];
                                texto_base_e = [texto_base_e  sprintf('%-10s',num2str(e_baterias(i,t_actual)))];
                                if hora_rel > 1
                                    balance_calculado = round(e_baterias(i,t_actual)-e_baterias(i,t_actual-1)+1/eta_descarga*p_baterias_descarga(i,t_actual-1) - eta_carga*p_baterias_carga(i,t_actual-1),4);
                                else
                                    balance_calculado = 0;
                                end
                                texto_base_bal = [texto_base_bal sprintf('%-10s',num2str(balance_calculado))];
                            end
                            
                            prot.imprime_texto(texto_base_p);
                            prot.imprime_texto(texto_base_e);
                            prot.imprime_texto(texto_base_bal);
                        end
                        prot.imprime_texto('');
                    end
                end
                
                % balance hidráulico
                if this.bConsideraDependenciaTemporal && this.Embalses.n > 0
                    prot.imprime_texto('');
                    prot.imprime_texto(['Balance hidráulico embalses en etapa ' num2str(this.iEtapa) '. Vols. en Mm3, el resto en m3/s']);
                    [cant_po_consecutivos,~] = size(this.vIndicesPOConsecutivos);

                    for emb = 1:this.Embalses.n
                        prot.imprime_texto(['Balance hidráulico embalse ' this.Embalses.ElRed(emb).entrega_nombre()]);

                        turbinas_descarga = this.Embalses.ElRed(emb).entrega_turbinas_descarga();
                        turbinas_carga = this.Embalses.ElRed(emb).entrega_turbinas_carga();
                        aportes_adicionales = this.Embalses.ElRed(emb).entrega_aportes_adicionales();

                        indice_vol_desde = this.Embalses.IdVarOptDesde(emb);
                        indice_spill_desde = this.Embalses.IdVarOptVertimientoDesde(emb);
                        indice_filt_desde = this.Embalses.IdVarOptFiltracionDesde(emb);
                        id_afluentes = this.Embalses.IdAdmEscenarioAfluentes(emb);
                        afluentes = this.pAdmSc.entrega_perfil_afluente(id_afluentes); %m3/s
                        
                        for periodo = 1:cant_po_consecutivos
                            prot.imprime_texto(['Periodo ' num2str(periodo) '/' num2str(cant_po_consecutivos)]);
                            
                            hora_desde_periodo = this.vIndicesPOConsecutivos(periodo,1);
                            hora_hasta_periodo = this.vIndicesPOConsecutivos(periodo,2);
                            ancho_periodo = hora_hasta_periodo - hora_desde_periodo + 1;
                            balance_hidraulico = zeros(1, ancho_periodo);
                            
                            texto_base = sprintf('%-15s','Hora Act');
                            for j = hora_desde_periodo:hora_hasta_periodo
                                texto_base = [texto_base sprintf('%-10s',num2str(j))];
                            end
                            prot.imprime_texto(texto_base);
                            texto_base = sprintf('%-15s','Hora rel');
                            for j = 1:ancho_periodo
                                texto_base = [texto_base sprintf('%-10s',num2str(j))];
                            end
                            prot.imprime_texto(texto_base);
                            
                            indice_vol_desde_actual = indice_vol_desde + hora_desde_periodo - 1;
                            
                            vol_inic_periodo = this.ResOptimizacion(indice_vol_desde_actual);
                            texto_vol = sprintf('%-15s','Vol (Mm3)');
                            % vol_t = vol_t-1 + aportes_t-1 - descargas_t-1
                            % balance_t = vol_t - vol_t-1 - aporte_t-1 + descargas_t-1
                            % balance_t0 = 0;
                            for hora_rel = 1:ancho_periodo
                                vol_t = this.ResOptimizacion(indice_vol_desde_actual + hora_rel - 1);
                                texto_vol = [texto_vol sprintf('%-10s',num2str(round(vol_t*3600/1000000,1)))];
                                if hora_rel > 1
                                    balance_hidraulico(hora_rel) = balance_hidraulico(hora_rel) + vol_t;                                    
                                end
                                if hora_rel < ancho_periodo
                                    balance_hidraulico(hora_rel+1) = balance_hidraulico(hora_rel+1) - vol_t;                                    
                                end                                    
                            end
                            
                            vol_final_periodo = this.ResOptimizacion(indice_vol_desde_actual + ancho_periodo - 1);
                            
                            prot.imprime_texto(texto_vol);
                            
                            for j = 1:length(turbinas_descarga)
                                id_turbina = turbinas_descarga(j).entrega_id();
                                indice_p_desde = this.Generadores.IdVarOptDesde(id_turbina);
                                indice_p_desde_actual = indice_p_desde + hora_desde_periodo - 1;

                                eficiencia_turbina = turbinas_descarga(j).entrega_eficiencia();
                                altura_caida = this.Embalses.ElRed(emb).entrega_altura_caida();
                                eficiencia_embalse = this.Embalses.ElRed(emb).entrega_eficiencia();
                                agua_turbinada_por_mwh = this.Sbase*1000/(eficiencia_turbina * 9.81 * altura_caida * eficiencia_embalse);

                                texto_turb = sprintf('%-15s',turbinas_descarga(j).entrega_nombre());
                                for hora_rel = 1:ancho_periodo
                                    h_descarga_t = agua_turbinada_por_mwh*this.ResOptimizacion(indice_p_desde_actual + hora_rel - 1);
                                    texto_turb = [texto_turb sprintf('%-10s',num2str(round(-h_descarga_t,2)))];
                                    if hora_rel < ancho_periodo
                                        balance_hidraulico(hora_rel+1) = balance_hidraulico(hora_rel+1) + h_descarga_t;                                    
                                    end                                    
                                end
                                prot.imprime_texto(texto_turb);
                            end

                            for j = 1:length(turbinas_carga)
                                id_turbina = turbinas_carga(j).entrega_id();
                                indice_p_desde = this.Generadores.IdVarOptDesde(id_turbina);
                                indice_p_desde_actual = indice_p_desde + hora_desde_periodo - 1;

                                eficiencia_turbina = turbinas_carga(j).entrega_eficiencia();
                                altura_caida = this.Embalses.ElRed(emb).entrega_altura_caida();
                                eficiencia_embalse = this.Embalses.ElRed(emb).entrega_eficiencia();
                                agua_turbinada_por_mwh = this.Sbase*1000/(eficiencia_turbina * 9.81 * altura_caida * eficiencia_embalse);

                                texto_turb = sprintf('%-15s',turbinas_carga(j).entrega_nombre());
                                for hora_rel = 1:ancho_periodo
                                    h_carga_t = agua_turbinada_por_mwh*this.ResOptimizacion(indice_p_desde_actual + hora_rel - 1);
                                    texto_turb = [texto_turb sprintf('%-10s',num2str(round(h_carga_t,2)))];
                                    if hora_rel < ancho_periodo
                                        balance_hidraulico(hora_rel+1) = balance_hidraulico(hora_rel+1) - h_carga_t;                                    
                                    end                                    
                                end
                                prot.imprime_texto(texto_turb);
                            end

                            % Spillage
                            texto_spill = sprintf('%-15s','Spillage');
                            indice_spill_desde_periodo = indice_spill_desde + hora_desde_periodo - 1;                                
                            for hora_rel = 1:ancho_periodo
                                h_spill = this.ResOptimizacion(indice_spill_desde_periodo + hora_rel - 1);
                                texto_spill = [texto_spill sprintf('%-10s',num2str(round(-h_spill,2)))];
                                if hora_rel < ancho_periodo
                                    balance_hidraulico(hora_rel+1) = balance_hidraulico(hora_rel+1) + h_spill;                                    
                                end                                    
                                
                            end
                            prot.imprime_texto(texto_spill);

                            % Filtracion
                            if indice_filt_desde ~= 0
                                texto_filt = sprintf('%-15s','Filtracion');
                                
                                indice_filt_desde_periodo = indice_filt_desde + hora_desde_periodo - 1;
                                for hora_rel = 1:ancho_periodo
                                    h_filt = this.ResOptimizacion(indice_filt_desde_periodo + hora_rel - 1);
                                    texto_filt = [texto_filt sprintf('%-10s',num2str(round(-h_filt,2)))];
                                    if hora_rel < ancho_periodo
                                        balance_hidraulico(hora_rel+1) = balance_hidraulico(hora_rel+1) + h_filt;                                    
                                    end                                    
                                    
                                end
                                prot.imprime_texto(texto_spill);
                            end
                            
                            % afluentes
                            texto_afluentes = sprintf('%-15s','Afluentes');
                            indice_afluente_desde_periodo = hora_desde_periodo;
                            for hora_rel = 1:ancho_periodo
                                val_afluente = afluentes(indice_afluente_desde_periodo + hora_rel - 1);
                                texto_afluentes = [texto_afluentes sprintf('%-10s',num2str(round(val_afluente,2)))];
                                if hora_rel < ancho_periodo
                                    balance_hidraulico(hora_rel+1) = balance_hidraulico(hora_rel+1) - val_afluente;                                    
                                end                                    
                            end
                            prot.imprime_texto(texto_afluentes);
                            
                            % aportes adicionales. Vertimientos y filtraciones desde otros embalses
                            for j = 1:length(aportes_adicionales)
                                embalse_orig = aportes_adicionales(j).entrega_embalse();
                                if embalse_orig.es_vertimiento(aportes_adicionales(j))
                                    indice_aporte_desde = this.Embalses.IdVarOptVertimientoDesde(embalse_orig.entrega_id());
                                else
                                    % aporte es filtración
                                    indice_aporte_desde = this.Embalses.IdVarOptFiltracionDesde(embalse_orig.entrega_id());
                                end
                                indice_aporte_desde_actual = indice_aporte_desde + hora_desde_periodo - 1;
                                
                                texto_aporte = sprintf('%-15s',aportes_adicionales(j).entrega_nombre());
                                for hora_rel = 1:ancho_periodo
                                    h_aporte_t = this.ResOptimizacion(indice_aporte_desde_actual + hora_rel - 1);
                                    texto_aporte = [texto_aporte sprintf('%-10s',num2str(round(h_aporte_t,2)))];
                                    if hora_rel < ancho_periodo
                                        balance_hidraulico(hora_rel+1) = balance_hidraulico(hora_rel+1) - h_aporte_t;                                    
                                    end
                                end
                                prot.imprime_texto(texto_aporte);
                            end
                            
                            % balance hidráulico calculado a mano
                            texto_balance = sprintf('%-15s','Balance manual');
                            for hora_rel = 1:ancho_periodo
                                texto_balance = [texto_balance sprintf('%-10s',num2str(round(balance_hidraulico(hora_rel),2)))];
                            end
                            prot.imprime_texto(texto_balance);
                            
                            % Vol_inicio_periodo + Vol_inicio_periodo_ant*(rep_periodo - 1) - Vol_fin_periodo_ant*(rep_periodo) = 0
                            % Vol_inicio_periodo =  Vol_inicio_periodo_ant + (Vol_fin_periodo_ant - Vol_inicio_periodo_ant)*rep_periodo 
                            % Vol_inicio_periodo =  Vol_inicio_periodo_ant + agua_turbinada_periodo_anterior
                            po_desde = this.vIndicesPOConsecutivos(periodo,1);
                            po_hasta = this.vIndicesPOConsecutivos(periodo,2);
                            representatividad_periodo = sum(this.vRepresentatividadPO(po_desde:po_hasta));

                            prot.imprime_texto(['Agua turbinada horas representativas: ' num2str(round((vol_inic_periodo - vol_final_periodo)*3600/1000000,2))]);
                            prot.imprime_texto(['Agua turbinada total periodo: ' num2str(round(representatividad_periodo*((vol_inic_periodo - vol_final_periodo)*3600/1000000),2))]);
                            if periodo < cant_po_consecutivos
                                prot.imprime_texto(['Vol. inicial siguiente periodo: ' num2str(round(vol_inic_periodo - representatividad_periodo*((vol_inic_periodo - vol_final_periodo)*3600/1000000),2))]);
                            end
                        end
                    end
                end
                
                if this.pParOpt.DeterminaUC
                    prot.imprime_texto('');
                    prot.imprime_texto('UC generadores');
                    [cant_po_consecutivos,~] = size(this.vIndicesPOConsecutivos);
                    for i = 1:cant_gen_uc
                        id_gen = id_gen_uc(i);
                        prot.imprime_texto(['UC generador ' this.Generadores.ElRed(id_gen).entrega_nombre()]);
                        
                        for periodo = 1:cant_po_consecutivos
                            prot.imprime_texto(['Periodo ' num2str(periodo) '/' num2str(cant_po_consecutivos)]);
                            
                            hora_desde_periodo = this.vIndicesPOConsecutivos(periodo,1);
                            hora_hasta_periodo = this.vIndicesPOConsecutivos(periodo,2);
                            ancho_periodo = hora_hasta_periodo - hora_desde_periodo + 1;
                            
                            texto_base = sprintf('%-15s','Hora Act');
                            for j = hora_desde_periodo:hora_hasta_periodo
                                texto_base = [texto_base sprintf('%-10s',num2str(j))];
                            end
                            prot.imprime_texto(texto_base);
                            texto_base = sprintf('%-15s','Hora rel');
                            for j = 1:ancho_periodo
                                texto_base = [texto_base sprintf('%-10s',num2str(j))];
                            end
                            prot.imprime_texto(texto_base);
                                                    
                            texto_base_uc = sprintf('%-15s','UC');
                            texto_base_p = sprintf('%-15s','Pgen');
                            texto_base_costo = sprintf('%-15s','CostoPartida');
                            for hora_rel = 1:ancho_periodo
                                t_actual = hora_desde_periodo + hora_rel - 1;
                            
                                texto_base_uc = [texto_base_uc sprintf('%-10s',num2str(estado_gen_uc(i,t_actual)))];
                                texto_base_p = [texto_base_p sprintf('%-10s',num2str(p_gen_uc(i,t_actual)))];
                                texto_base_costo = [texto_base_costo sprintf('%-10s',num2str(costo_partida_gen_uc(i,t_actual)))];
                            end
                            prot.imprime_texto(texto_base_uc);
                            prot.imprime_texto(texto_base_p);
                            prot.imprime_texto(texto_base_costo);
                            prot.imprime_texto('');
                        end
                    end
                end
                
                if this.pParOpt.ConsideraReservasMinimasSistema && this.pParOpt.EstrategiaReservasMinimasSistema == 2
                    prot.imprime_texto('');
                    prot.imprime_texto('Reservas minimas de subida del sistema (igual a maxima potencia de subida de los generadores despachables)');
                    texto_base = sprintf('%-15s','Hora');
                    for j = 1:this.iCantPuntosOperacion
                        texto_base = [texto_base sprintf('%-10s',num2str(j))];
                    end
                    prot.imprime_texto(texto_base);
                    indice_reservas_sist_desde = this.IdVarOptPmaxGenDespDesde;
                    indice_reservas_sist_hasta =  indice_reservas_sist_desde + this.iCantPuntosOperacion - 1;
                    valor_reservas = round(this.ResOptimizacion(indice_reservas_sist_desde:indice_reservas_sist_hasta)*this.Sbase,2);
                    
                    indice_gen_desp = find(this.Generadores.Despachable == 1);
                    valor_pgen = zeros(length(indice_gen_desp),this.iCantPuntosOperacion);
                    for j = 1:length(indice_gen_desp)
                        id_gen = indice_gen_desp(j);
                        indice_desde = this.Generadores.IdVarOptDesde(id_gen);
                        indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;
                        valor = this.ResOptimizacion(indice_desde:indice_hasta)*this.Sbase;
                        
                        valor_pgen(j,:) = valor';
                    end
                    texto_reserva = sprintf('%-15s','Reservas sist');
                    for oper = 1:this.iCantPuntosOperacion
                        texto_reserva = [texto_reserva sprintf('%-10s',num2str(valor_reservas(oper)))];
                    end
                    prot.imprime_texto(texto_reserva);
                    for j = 1:length(indice_gen_desp)
                        texto_pgen = sprintf('%-15s',['P' this.Generadores.ElRed(indice_gen_desp).entrega_nombre()]);
                        for oper = 1:this.iCantPuntosOperacion
                            texto_pgen = [texto_pgen sprintf('%-10s',num2str(valor_pgen(j,oper)))];
                        end
                        prot.imprime_texto(texto_pgen);
                    end
                    
                    % balance
                    balance = valor_reservas - sum(valor_pgen);
                    texto_balance = sprintf('%-15s','Balance');
                    for oper = 1:this.iCantPuntosOperacion
                        texto_balance = [texto_balance sprintf('%-10s',num2str(balance(oper)))];
                    end
                    prot.imprime_texto(texto_balance);
                end
                
                if this.pParOpt.ConsideraRestriccionROCOF
                    % restricciones inercia y/o ROCOF. Por cada generador que puede fallar
                    IdVarOptInerciaDesde = [] % varopt de la inercia del sistema en caso de falla de los generadores
                    IdRestriccionEInerciaDesde = [] % restricciones que calcula la inercia del sistema en caso de falla de los generadores
                    IdRestriccionIROCOFDesde = [] % restricción del rocof en caso de falla de los generadores
                    
                    prot.imprime_texto('');
                    prot.imprime_texto('ROCOF del sistema por cada contingencia\n');
                    for cont = 1:this.iCantContingenciasGenCons
                        prot.imprime_texto(['Falla generador' num2str(this.pContingenciasGenCons(cont).entrega_nombre())]);
                        texto_base = sprintf('%-15s','Hora');
                        for j = 1:this.iCantPuntosOperacion
                            texto_base = [texto_base sprintf('%-10s',num2str(j))];
                        end
                        prot.imprime_texto(texto_base);
                        
                        indice_inercia_desde = this.IdVarOptInerciaDesde(cont);
                        indice_inercia_hasta =  indice_inercia_desde + this.iCantPuntosOperacion - 1;
                        valor_inercia = round(this.ResOptimizacion(indice_inercia_desde:indice_inercia_hasta),dec_redondeo);
                        texto_inercia = sprintf('%-15s','Inercia sist');
                        for oper = 1:this.iCantPuntosOperacion
                            texto_inercia = [texto_inercia sprintf('%-10s',num2str(valor_inercia(oper)))];
                        end
                        prot.imprime_texto(texto_inercia);

                        id_gen_cont = this.pContigenciasGenCons(cont).entrega_id();
                        indice_dp_desde = this.IdVarOptDesde(id_gen_cont);
                        indice_dp_hasta = indice_dp_desde + this.iCantPuntosOperacion - 1;
                        valor_dp = round(this.ResOptimizacion(indice_dp_desde:indice_dp_hasta)*this.Sbase,dec_redondeo);
                        texto_dp = sprintf('%-15s','Dp');
                        for oper = 1:this.iCantPuntosOperacion
                            texto_dp = [texto_sp sprintf('%-10s',num2str(valor_dp(oper)))];
                        end
                        prot.imprime_texto(texto_dp);
                        
                        valor_cum_bateria = zeros(this.iCantPuntosOperacion,1);
                        for j = 1:this.Baterias.n                            
                            indice_res_descarga_desde = this.Baterias.IdVarOptResDescargaDesde(j);
                            indice_res_descarga_hasta = indice_res_descarga_desde + this.iCantPuntosOperacion - 1;
                            valor_bateria = this.ResOptimizacion(indice_res_descarga_desde:indice_res_descarga_hasta)*this.Sbase;
                            valor_cum_bateria = valor_cum_bateria + valor_bateria;
                            texto_bateria = sprintf('%-15s','Res. Baterias');
                            for oper = 1:this.iCantPuntosOperacion
                                texto_bateria = [texto_bateria sprintf('%-10s',num2str(valor_bateria(oper)))];
                            end
                            prot.imprime_texto(texto_bateria);
                        end
                        
                        id_gen_ernc = find(this.Generadores.Despachable == 0);
                        valor_cum_ernc = zeros(this.iCantPuntosOperacion,1);
                        for j = 1:length(id_gen_ernc)
                            indice_res_ernc_desde = this.Generadores.IdVarOptDesde(id_gen_ernc(j));
                            indice_res_ernc_hasta = indice_res_ernc_desde +  this.iCantPuntosOperacion - 1;
                            valor_res_ernc = round(this.ResOptimizacion(indice_res_ernc_desde:indice_res_ernc_hasta)*this.Sbase,dec_redondeo);
                            valor_cum_ernc = valor_cum_ernc + valor_res_ernc;
                            texto_ernc = sprintf('%-15s','Res. ERNC');
                            for oper = 1:this.iCantPuntosOperacion
                                texto_ernc = [texto_ernc sprintf('%-10s',num2str(valor_res_ernc(oper)))];
                            end
                            prot.imprime_texto(texto_ernc);
                        end
                        
                        % rocof calculado
                        texto_rocof = sprintf('%-15s','ROCOF Calc.');
                        valor_rocof = 1./(2*valor_inercia).*(valor_dp - valor_cum_bateria - valor_cum_res_ernc);
                        for oper = 1:this.iCantPuntosOperacion
                            texto_rocof = [texto_rocof sprintf('%-10s',num2str(valor_rocof(oper)))];
                        end
                        prot.imprime_texto(texto_rocof);

                        % balance (delta rocof en comparación con el mínimo
                        texto_balance = sprintf('%-15s','dROCOF - Max');
                        balance = round(valor_rocof - this.pParOpt.ROCOFMax,this.pParOpt.DecimalesRedondeo);
                        for oper = 1:this.iCantPuntosOperacion
                            texto_balance = [texto_balance sprintf('%-10s',num2str(balance(oper)))];
                        end
                        prot.imprime_texto(texto_balance);
                        
                    end
                end
            else
                error = MException('cMILPOpt:imprime_resultados_protocolo','Resultados no detallados. Aún no está implementada esta función');
                throw(error)
            end
        end
        
        function evaluacion = entrega_evaluacion(this)
            evaluacion = this.pResEvaluacion;
        end
        
        function inserta_evaluacion(this, eval)
            this.pResEvaluacion = eval;
        end
        
        function imprime_problema_optimizacion(this, varargin)
            % varargin indica el nombre del documento donde se quiere
            % imprimir. Si no se indica nada, entonces lo imprime con un
            % nombre predeterminado
            % sólo en modo debug. imprime el problema en archivo externo
            % determina nombre de variables de optimización
            % esto se hace sólo aquí, para no afectar la performance del
            % programa con datos que no se necesitan
            %[NombreIneq, NombreEq] = this.escribe_nombre_restricciones();
            
            if nargin > 1
                nombre_documento = varargin{1};
            else
                nombre_documento = [this.nombre_archivo_problema_opt '_' this.caso_estudio '_' num2str(this.iEtapa)];
            end
            docID = fopen(nombre_documento,'w');
            fprintf(docID, 'Formulacion matematica OPF\n');
            fprintf(docID, ['Tipo problema : ' this.pParOpt.entrega_tipo_problema()]);
            fprintf(docID, ['\nFuncion objetivo: ' this.pParOpt.entrega_funcion_objetivo()]);
            fprintf(docID, ['\nTipo flujo de potencia: ' this.pParOpt.entrega_tipo_flujo()]);
            fprintf(docID, ['\nTipo restricciones seguridad: ' this.pParOpt.entrega_tipo_restricciones_seguridad()]);
            if this.pParOpt.entrega_flujo_dc_con_perdidas()
            	val = 'si';
            else
            	val = 'no';
            end
                fprintf(docID, ['\nConsidera pérdidas: ' val]);
            fprintf(docID, '\n');
            
            fprintf(docID, 'Funcion objetivo\n');
            primero = true;
            indices_validos = find(this.Fobj ~= 0);
            for id = 1:length(indices_validos)
                i = indices_validos(id);
                val = round(this.Fobj(i),3);                    
                if primero
                    text = strcat(num2str(val),'(',this.NombreVariables{i},')');
                    primero = false;
                else
                    if this.Fobj(i) > 0
                        text = strcat(text, ' + ',num2str(val),'(', this.NombreVariables{i},')');
                    else
                        text = strcat(text, ' - ',num2str(abs(val)),'(',this.NombreVariables{i},')');
                    end
                    if length(text) > 170
                        text = strcat(text,'\n');
                        fprintf(docID, text);
                        primero = true;
                    end
                end
            end
            text = strcat(text,'\n');
            fprintf(docID, text);
            % restricciones
            % restricciones de desigualdad
            if ~isempty(this.bineq)
                fprintf(docID, 'Restricciones de desigualdad:\n');
            end
            
            for i = 1:length(this.bineq)    
                nombre_ineq = this.NombreIneq{i};
                fprintf(docID, strcat(nombre_ineq,':\n'));
                primero = true;
                indices_validos = find(this.Aineq(i,:) ~= 0);
                for id_val = 1:length(indices_validos)
                    j = indices_validos(id_val);
                    val = this.Aineq(i,j);                    
                    if primero
                        if val == 1
                            text = strcat('(',this.NombreVariables{j},')');
                        elseif val == -1
                            text = strcat('-', '(' ,this.NombreVariables{j}, ')');
                        else
                            text = strcat(num2str(val), '(', this.NombreVariables{j}, ')');
                            %error = MException('cMILPOpt:imprime_problema_optimizacion','valor restriccion de desigualdad debe ser 1 o -1');
                            %throw(error)
                        end
                        primero = false;
                    else
                        if val == 1
                            text = strcat(text, ' + ', '(', this.NombreVariables{j}, ')');
                        elseif val == -1
                            text = strcat(text, ' - ', '(', this.NombreVariables{j}, ')');
                        elseif val > 0
                            text = strcat(text, ' + ', num2str(val), '(', this.NombreVariables{j}, ')');
                        else
                            text = strcat(text, ' - ', num2str(abs(val)), '(', this.NombreVariables{j}, ')');
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
                text = strcat(text,' <= ', num2str(this.bineq(i)),'\n\n');
                fprintf(docID, text);
            end

            fprintf(docID, 'Restricciones de igualdad:\n');
            for i = 1:length(this.beq)
                nombre_eq = this.NombreEq{i};

                fprintf(docID, strcat(nombre_eq,':\n'));
                primero = true;
                id = find(this.Aeq(i,:));
                if isempty(id)
                    error = MException('cDCOPF:imprime_problema_optimizacion',...
                                       ['Inconsistencia en los datos. Ecuación de igualdad ' nombre_eq ' no tiene variables activas']);
                    throw(error)
                end
                
                for kk = 1:length(id)
                    id_var = id(kk);
                    val = this.Aeq(i,id_var);
                    if primero
                        if val == 1
                            text = strcat(this.NombreVariables{id_var});
                        elseif val == -1
                            text = strcat('-',this.NombreVariables{id_var});
                        elseif val > 0
                            text = strcat(num2str(round(val,3)),'*',this.NombreVariables{id_var});
                        else
                            text = strcat('-', num2str(abs(round(val,3))),'*',this.NombreVariables{id_var});
                        end
                        primero = false;
                    else
                        if val == 1
                            text = strcat(text, ' + ',this.NombreVariables{id_var});
                        elseif val == -1
                            text = strcat(text, ' - ',this.NombreVariables{id_var});
                        elseif val > 0
                            text = strcat(text, ' + ', num2str(round(val,3)),'*',this.NombreVariables{id_var});
                        else
                            text = strcat(text, ' - ', num2str(abs(round(val,3))),'*',this.NombreVariables{id_var});
                        end
                        if length(text) > 170
                            text = strcat(text,'\n');
                            fprintf(docID, text);
                            primero = true;
                            text = '';
                        end
                    end
                end
                text = strcat(text,' = ', num2str(this.beq(i)),'\n\n');
                fprintf(docID, text);
            end
            
            % límites de las variables
            fprintf(docID, 'Limites variables de decision:\n');
            for i = 1:length(this.Fobj)
                text = strcat(num2str(this.lb(i)), ' <= ', this.NombreVariables{i}, ' <= ', num2str(this.ub(i)), '\n');
                fprintf(docID, text);
            end
            fprintf(docID, 'fin');
            fclose(docID);
        end
        
        function copia_parametros_optimizacion(this, parametros)
            this.pParOpt.FuncionObjetivo = parametros.FuncionObjetivo;
            this.pParOpt.TipoFlujoPotencia = parametros.TipoFlujoPotencia;
            this.pParOpt.TipoRestriccionesSeguridad = parametros.TipoRestriccionesSeguridad;
            this.pParOpt.Solver = parametros.Solver;
            this.pParOpt.NivelDetalleResultados = parametros.NivelDetalleResultadosOPF;
            this.pParOpt.PorcentajeUsoFlujosAltos = parametros.PorcentajeUsoFlujosAltos;
            this.pParOpt.PorcentajeUsoFlujosBajos = parametros.PorcentajeUsoFlujosBajos;

            this.pParOpt.DeterminaUC = parametros.DeterminaUC;
            this.pParOpt.ConsideraContingenciaN1 = parametros.ConsideraContingenciaN1;
            this.pParOpt.ConsideraEstadoPostContingencia = parametros.ConsideraEstadoPostContingencia;
            this.pParOpt.NivelDetalleResultados = parametros.NivelDetalleResultadosOPF;
            
            this.iNivelDebug = parametros.NivelDebugOPF;
        end
        
        function ingresa_nombres_problema(this)
            this.NombreVariables = cell(this.iIndiceVarOpt*this.iCantPuntosOperacion,1);
            this.NombreEq = cell(this.iIndiceEq,1);
        
            for i = 1:this.Subestaciones.n
                indice_global_desde = this.Subestaciones.IdVarOptDesde(i); 
                this.ingresa_nombres(this.Subestaciones.ElRed(i), indice_global_desde,'N0');
                
                indice_restriccion_desde = this.Subestaciones.IdRestriccionEBalanceDesde(i);
                this.ingresa_nombre_restriccion_igualdad(this.Subestaciones.ElRed(i), indice_restriccion_desde);

                if this.pParOpt.ConsideraContingenciaN1
                    indice_global_desde = this.Subestaciones.IdVarOptN1Desde(i); 
                    this.ingresa_nombres(this.Subestaciones.ElRed(i), indice_global_desde,'N1');
                end
                
                if this.pParOpt.ConsideraEstadoPostContingencia
                    indice_global_desde = this.Subestaciones.IdVarOptPCDesde(i); 
                    this.ingresa_nombres(this.Subestaciones.ElRed(i), indice_global_desde,'PC');
                end
            end

            for i = 1:this.Generadores.n
                indice_global_desde = this.Generadores.IdVarOptDesde(i);
                this.ingresa_nombres(this.Generadores.ElRed(i), indice_global_desde,'P');
                
                if this.pParOpt.DeterminaUC
                    if this.Generadores.IdVarOptUCDesde(i) ~= 0
                        indice_global_desde = this.Generadores.IdVarOptUCDesde(i);
                        this.ingresa_nombres(this.Generadores.ElRed(i), indice_global_desde,'UC');

                        indice_global_desde = this.Generadores.IdVarOptCostoPartidaDesde(i);
                        this.ingresa_nombres(this.Generadores.ElRed(i), indice_global_desde,'CPart');
                    end
                end
                
                if this.pParOpt.ConsideraEstadoPostContingencia
                    if this.Generadores.ElRed(i).Despachable && this.Generadores.IdVarOptPCResPosDesde(i) ~= 0
                        indice_global_desde = this.Generadores.IdVarOptPCResPosDesde(i);
                        this.ingresa_nombres(this.Generadores.ElRed(i), indice_global_desde,'PCRPos');

                        indice_global_desde = this.Generadores.IdVarOptPCResNegDesde(i);
                        this.ingresa_nombres(this.Generadores.ElRed(i), indice_global_desde,'PCRNeg');
                    elseif ~this.Generadores.ElRed(i).Despachable
                        indice_global_desde = this.Generadores.IdVarOptPCResNegDesde(i);
                        this.ingresa_nombres(this.Generadores.ElRed(i), indice_global_desde,'PCRNegERNC');
                    end
                end
            end

            for i = 1:this.Lineas.n
                indice_global_desde = this.Lineas.IdVarOptDesde(i);
                this.ingresa_nombres(this.Lineas.ElRed(i), indice_global_desde,'N0');

                indice_restriccion_desde = this.Lineas.IdRestriccionEFlujosAngulosDesde(i);
                this.ingresa_nombre_restriccion_igualdad(this.Lineas.ElRed(i), indice_restriccion_desde);

                if this.pParOpt.ConsideraContingenciaN1
                    indice_global_desde = this.Lineas.IdVarOptN1Desde(i);
                    this.ingresa_nombres(this.Lineas.ElRed(i), indice_global_desde,'N1');
                end
                
                if this.pParOpt.ConsideraEstadoPostContingencia
                    indice_global_desde = this.Lineas.IdVarOptPCDesde(i);
                    this.ingresa_nombres(this.Lineas.ElRed(i), indice_global_desde,'PC');
                end
            end

            for i = 1:this.Trafos.n
                indice_global_desde = this.Trafos.IdVarOptDesde(i);
                this.ingresa_nombres(this.Trafos.ElRed(i), indice_global_desde,'N0');

                indice_restriccion_desde = this.Trafos.IdRestriccionEFlujosAngulosDesde(i);
                this.ingresa_nombre_restriccion_igualdad(this.Trafos.ElRed(i), indice_restriccion_desde);
                
                if this.pParOpt.ConsideraContingenciaN1
                    indice_global_desde = this.Trafos.IdVarOptN1Desde(i);
                    this.ingresa_nombres(this.Trafos.ElRed(i), indice_global_desde,'N1');
                end
                
                if this.pParOpt.ConsideraEstadoPostContingencia
                    indice_global_desde = this.Trafos.IdVarOptPCDesde(i);
                    this.ingresa_nombres(this.Trafos.ElRed(i), indice_global_desde,'PC');
                end
            end

            for i = 1:this.Consumos.n
                indice_global_desde = this.Consumos.IdVarOptDesde(i);
                this.ingresa_nombres(this.Consumos.ElRed(i), indice_global_desde,'N0');
                
                if this.pParOpt.ConsideraEstadoPostContingencia
                    indice_global_desde = this.Consumos.IdVarOptPCDesde(i);
                    this.ingresa_nombres(this.Consumos.ElRed(i), indice_global_desde,'PC');
                end
            end

            for i = 1:this.Baterias.n
                indice_global_desde = this.Baterias.IdVarOptDesdeDescarga(i); 
                this.ingresa_nombres(this.Baterias.ElRed(i), indice_global_desde, 'Pdescarga');

                indice_global_desde = this.Baterias.IdVarOptDesdeCarga(i); 
                this.ingresa_nombres(this.Baterias.ElRed(i), indice_global_desde, 'Pcarga');
                
                if this.bConsideraDependenciaTemporal
                    indice_global_desde = this.Baterias.IdVarOptDesdeE(i); 
                    this.ingresa_nombres(this.Baterias.ElRed(i), indice_global_desde, 'E');

                    indice_restriccion_desde = this.Baterias.IdRestriccionEBalanceDesde(i);
                    this.ingresa_nombre_restriccion_igualdad(this.Baterias.ElRed(i), indice_restriccion_desde);
                end
                
                if this.pParOpt.ConsideraEstadoPostContingencia
                    indice_global_desde = this.Baterias.IdVarOptResDescargaDesde(i);
                    this.ingresa_nombres(this.Baterias.ElRed(i), indice_global_desde,'ResDescarga');

                    indice_global_desde = this.Baterias.IdVarOptResCargaDesde(i);
                    this.ingresa_nombres(this.Baterias.ElRed(i), indice_global_desde,'PCCarga');
                end
            end
        end

        function ingresa_nombre_restriccion_igualdad(this, el_red, indice_eq_desde, varargin)
            cant_po = this.iCantPuntosOperacion;
            if isa(el_red, 'cSubestacion')
                if nargin == 3
                    for oper = 1:cant_po                        
                        this.NombreEq{indice_eq_desde + oper - 1} = strcat('req_', num2str(indice_eq_desde + oper - 1), '_be_', 'B', num2str(el_red.entrega_id()), '_O', num2str(oper));
                    end
                else
                    tipo = varargin{1};
                    cont = varargin{2};
                    for oper = 1:cant_po                        
                        this.NombreEq{indice_eq_desde + oper - 1} = strcat('req_', num2str(indice_eq_desde + oper - 1), '_be_', tipo, '_B', num2str(el_red.entrega_id()), '_O', num2str(oper), 'Cont', num2str(cont));
                    end
                end
            elseif isa(el_red, 'cLinea')

                id_par = el_red.entrega_indice_paralelo();
                id_se1 = el_red.entrega_se1().entrega_id();
                id_se2 = el_red.entrega_se2().entrega_id();                
                texto = 'L';
                if nargin == 3
                    for oper = 1:cant_po
                        this.NombreEq{indice_eq_desde + oper - 1} = strcat('req_', num2str(indice_eq_desde + oper - 1), '_flujos_angulos_', texto, num2str(id_par), ...
                            '_B', num2str(id_se1), '_', num2str(id_se2), '_O', num2str(oper));
                    end
                else
                    tipo = varargin{1};
                    cont = varargin{2};
                    for oper = 1:cant_po
                        this.NombreEq{indice_eq_desde + oper - 1} = strcat('req_', num2str(indice_eq_desde + oper - 1), tipo, '_flujos_angulos_', texto, num2str(id_par), ...
                            '_F', num2str(cont), '_B', num2str(id_se1), '_', num2str(id_se2), '_O', num2str(oper));
                    end
                end
            elseif isa(el_red, 'cTransformador2D')
                id_par = el_red.entrega_indice_paralelo();
                id_se1 = el_red.entrega_se1().entrega_id();
                id_se2 = el_red.entrega_se2().entrega_id();                
                texto = 'Tr';
                if nargin == 3                
                    for oper = 1:cant_po
                        this.NombreEq{indice_eq_desde + oper - 1} = strcat('req_', num2str(indice_eq_desde + oper - 1), '_flujos_angulos_', texto, num2str(id_par), ...
                            '_B', num2str(id_se1), '_', num2str(id_se2), '_O', num2str(oper));
                    end
                else
                    tipo = varargin{1};
                    cont = varargin{2};
                    for oper = 1:cant_po
                        this.NombreEq{indice_eq_desde + oper - 1} = strcat('req_', num2str(indice_eq_desde + oper - 1), tipo, '_flujos_angulos_', texto, num2str(id_par), ...
                            '_F', num2str(cont), '_B', num2str(id_se1), '_', num2str(id_se2), '_O', num2str(oper));
                    end                    
                end
            elseif isa(el_red, 'cBateria')
                [cant_periodos_representativos, ~] = size(this.vIndicesPOConsecutivos);
                id_bat = el_red.entrega_id();
                for periodo = 1:cant_periodos_representativos
                    oper_inicio = this.vIndicesPOConsecutivos(periodo,1);
                    oper_fin = this.vIndicesPOConsecutivos(periodo,2);
                    % primero estados iniciales y finales de la batería
                    this.NombreEq{indice_eq_desde + oper_inicio - 1} = strcat('req_', num2str(indice_eq_desde + oper_inicio - 1), '_be_bat_', num2str(id_bat), ...
                        'periodo_', num2str(periodo), '_O', num2str(oper_inicio), '_',num2str(oper_fin),'_einicio_efin' );

                    for j = 1:cant_po-1
                        this.NombreEq{indice_eq_desde + oper_inicio - 1 + j} = strcat('req_', num2str(indice_eq_desde + oper_inicio - 1 + j), '_be_bat_', num2str(id_bat), ...
                            'periodo_', num2str(periodo), '_O', num2str(oper_inicio+j-1), '_',num2str(oper_inicio+j));
                    end
                end
            elseif isa(el_red, 'cEmbalse')
                id_embalse = el_red.entrega_id();                
                if strcmp(varargin{1},'Vol')
                    [cant_periodos_representativos, ~] = size(this.vIndicesPOConsecutivos);
                    for periodo = 1:cant_periodos_representativos
                        oper_inicio = this.vIndicesPOConsecutivos(periodo,1);
                        oper_fin = this.vIndicesPOConsecutivos(periodo,2);
                        % primero estados iniciales y finales del embalse

                        this.NombreEq{indice_eq_desde + oper_inicio - 1} = strcat('req_', num2str(indice_eq_desde + oper_inicio - 1), '_bh_embalse_', num2str(id_embalse), ...
                            '_periodo_', num2str(periodo), '_O', num2str(oper_inicio), '_',num2str(oper_fin),'_vinicio_vfin' );

                        for j = 1:cant_po-1
                            this.NombreEq{indice_eq_desde + oper_inicio - 1 + j} = strcat('req_', num2str(indice_eq_desde + oper_inicio - 1 + j), '_bh_embalse_', num2str(id_embalse), ...
                                'periodo_', num2str(periodo), '_O', num2str(oper_inicio+j-1), '_',num2str(oper_inicio+j));
                        end
                    end
                else
                    % filtraciones
                    for oper = 1:cant_po
                        this.NombreEq{indice_eq_desde + oper - 1} = strcat('req_', num2str(indice_eq_desde + oper - 1), '_filt_embalse_', num2str(id_embalse), ...
                            '_O', num2str(oper));                            
                    end
                end
            elseif isa(el_red, 'cSistemaElectricoPotencia')
                cont = varargin{1};
                for oper = 1:cant_po
                    this.NombreEq{indice_eq_desde + oper - 1} = strcat('req_', num2str(indice_eq_desde + oper - 1), '_Hsist_', 'F_', num2str(cont), ...
                        '_O', num2str(oper));
                end
            else
                error = MException('cOPF:ingresa_nombre_restriccion_igualdad',...
                    ['Restriccion de igualdad para elemento tipo ' class(el_red) ' aun no implementada']);
                throw(error)
            end
        end

        function ingresa_nombre_restriccion_desigualdad(this, el_red, indice_ineq_desde, tipo, varargin)
            if isa(el_red, 'cGenerador')
                if strcmp(tipo, 'TMinOperacion')
                    oper = varargin{1};
                    this.NombreIneq{indice_ineq_desde} = strcat('rineq_', num2str(indice_ineq_desde), '_TminOp_', 'G', num2str(el_red.entrega_id()), '_O', num2str(oper));
                elseif strcmp(tipo, 'TMinDetencion')
                    oper = varargin{1};
                    this.NombreIneq{indice_ineq_desde} = strcat('rineq_', num2str(indice_ineq_desde), '_TminDet_', 'G', num2str(el_red.entrega_id()), '_O', num2str(oper));                    
                elseif strcmp(tipo, 'LimResPos') || strcmp(tipo, 'LimResNeg')
                    if nargin == 4
                        % reservas sistémicas
                        for oper = 1:this.iCantPuntosOperacion
                            this.NombreIneq{indice_ineq_desde + oper - 1} = strcat('rineq_', num2str(indice_ineq_desde + oper - 1), tipo, '_G', num2str(el_red.entrega_id()), '_O', num2str(oper));
                        end
                    else
                        % despliegue de reservas post-contingencia
                        for oper = 1:this.iCantPuntosOperacion
                            this.NombreIneq{indice_ineq_desde + oper - 1} = strcat('rineq_', num2str(indice_ineq_desde + oper - 1), tipo, '_F', num2str(cont), '_G', num2str(el_red.entrega_id()), '_O', num2str(oper));
                        end
                    end
                elseif strcmp(tipo, 'PmaxGenDespSist')
                    % restricción para el cálculo de potencia máxima de operación de los generadores despachables
                    for oper = 1:this.iCantPuntosOperacion
                        this.NombreIneq{indice_ineq_desde + oper - 1} = strcat('rineq_', num2str(indice_ineq_desde + oper - 1), tipo, '_G', num2str(el_red.entrega_id()), '_O', num2str(oper));
                    end
                else
                    if strcmp(tipo, 'Pmax')
                        tipo_rest = '_uc_pmax_';
                    elseif strcmp(tipo, 'Pmin')
                        tipo_rest = '_uc_pmin_';
                    elseif strcmp(tipo, 'CPartida')
                        tipo_rest = '_uc_cpartida_';
                    end

                    for oper = 1:this.iCantPuntosOperacion
                        this.NombreIneq{indice_ineq_desde + oper - 1} = strcat('rineq_', num2str(indice_ineq_desde + oper - 1), tipo_rest, 'G', num2str(el_red.entrega_id()), '_O', num2str(oper));
                    end
                end
            elseif isa(el_red, 'cSistemaElectricoPotencia')
                cont = varargin{1};
                for oper = 1:this.iCantPuntosOperacion
                    this.NombreIneq{indice_ineq_desde + oper - 1} = strcat('rineq_', num2str(indice_ineq_desde + oper - 1), tipo, '_F', num2str(cont), '_O', num2str(oper));
                end
            elseif isa(el_red, 'cBateria')
                if strcmp(tipo, 'LimResPos') || strcmp(tipo, 'LimResNeg')
                    if nargin == 4
                        % reservas sistemicas
                        for oper = 1:this.iCantPuntosOperacion
                            this.NombreIneq{indice_ineq_desde + oper - 1} = strcat('rineq_', num2str(indice_ineq_desde + oper - 1), tipo, '_B', num2str(el_red.entrega_id()), '_O', num2str(oper));
                        end
                    else
                        for oper = 1:this.iCantPuntosOperacion
                            this.NombreIneq{indice_ineq_desde + oper - 1} = strcat('rineq_', num2str(indice_ineq_desde + oper - 1), tipo, '_F', num2str(cont), '_B', num2str(el_red.entrega_id()), '_O', num2str(oper));
                        end
                    end
                else
                    % operación normal
                    error = MException('cOPF:ingresa_nombre_restriccion_desigualdad',...
                        ['Para variable ' class(el_red) ' tipo de restriccion ' tipo, ' aun no implementada']);
                    throw(error)
                end
            end
        end
        
        function ingresa_nombres(this, el_red, indice_global_desde, tipo_var, varargin)
            if isa(el_red, 'cGenerador')
                this.ingresa_nombre_generador(el_red, indice_global_desde, tipo_var)
            elseif isa(el_red, 'cBateria')
                this.ingresa_nombre_bateria(el_red, indice_global_desde, tipo_var)
            elseif isa(el_red,'cSubestacion')
                this.ingresa_nombre_subestacion(el_red, indice_global_desde, tipo_var, varargin)
            elseif isa(el_red, 'cConsumo')
                this.ingresa_nombre_consumo(el_red, indice_global_desde, tipo_var)
            elseif isa(el_red, 'cTransformador2D') || isa(el_red, 'cLinea')
                this.ingresa_nombre_trafo_linea(el_red, indice_global_desde, tipo_var, varargin)
            elseif isa(el_red, 'cEmbalse')
                this.ingresa_nombre_embalse(el_red, indice_global_desde, tipo_var)
            elseif isa(el_red, 'CSistemaElectricoPotencia')
                this.ingresa_nombre_variable_sistema(indice_global_desde, tipo_var, varargin)
            else
                error = MException('cOPF:ingresa_nombres',...
                    ['Variable ' class(el_red) ' aun no implementada']);
                throw(error)
            end
        end

        function ingresa_nombre_variable_sistema(this, indice_global_desde, tipo_var, varargin)
            if strcmp(tipo_var, 'PmaxGenSist')
                for oper = 1:this.iCantPuntosOperacion
                    indice_nombre = indice_global_desde + oper -1;
                    texto = strcat('PmaxGenDesp', '_O', num2str(oper));
                    this.NombreVariables{indice_nombre} = texto;
                end
            elseif strcmp(tipo_var, 'HSist')
                cont = varargin{1};
                for oper = 1:this.iCantPuntosOperacion
                    indice_nombre = indice_global_desde + oper -1;
                    texto = strcat('HSist', 'F', num2str(cont),'_O', num2str(oper));
                    this.NombreVariables{indice_nombre} = texto;
                end
            else
                error = MException('cOPF:ingresa_nombre_variable_sistema',...
                    ['Tipo ' tipo_var ' aun no implementada']);
                throw(error)       
            end
        end
        
        function ingresa_nombre_generador(this, el_red, indice_global_desde, tipo_var)
            id_bus = el_red.entrega_se().entrega_id();
            if strcmp(tipo_var,'P')
                % potencia generador normal
                for oper = 1:this.iCantPuntosOperacion
                    indice_nombre = indice_global_desde + oper -1;
                    if el_red.es_despachable()
                        texto = strcat('P_G', num2str(el_red.entrega_id()), ...
                            '_B', num2str(id_bus), '_O', num2str(oper));
                        this.NombreVariables{indice_nombre} = texto;
                    else
                        texto = strcat('RRES_G', num2str(el_red.entrega_id()), ...
                            '_B', num2str(id_bus), '_O', num2str(oper));
                        this.NombreVariables{indice_nombre} = texto;
                    end                        
                end
            elseif strcmp(tipo_var,'ResPos') || strcmp(tipo_var,'ResNeg')
                % reservas del generador (ojo que no es el despliegue de reservas post-contingencia
                for oper = 1:this.iCantPuntosOperacion
                    indice_nombre = indice_global_desde + oper -1;
                    if el_red.es_despachable()
                        texto = strcat(tipo_var, '_G', num2str(el_red.entrega_id()), ...
                            '_B', num2str(id_bus), '_O', num2str(oper));
                        this.NombreVariables{indice_nombre} = texto;
                    else
                        texto = strcat('RRES_G', num2str(el_red.entrega_id()), ...
                            '_B', num2str(id_bus), '_O', num2str(oper));
                        this.NombreVariables{indice_nombre} = texto;
                    end                        
                end                
            elseif strcmp(tipo_var,'UC')
                for oper = 1:this.iCantPuntosOperacion
                    indice_nombre = indice_global_desde + oper -1;
                    texto = strcat('UC_G', num2str(el_red.entrega_id()), ...
                        '_B', num2str(id_bus), '_O', num2str(oper));
                    this.NombreVariables{indice_nombre} = texto;
                end
            elseif strcmp(tipo_var, 'CPart')
                for oper = 1:this.iCantPuntosOperacion
                    indice_nombre = indice_global_desde + oper -1;
                    texto = strcat('CPart_G', num2str(el_red.entrega_id()), ...
                        '_B', num2str(id_bus), '_O', num2str(oper));
                    this.NombreVariables{indice_nombre} = texto;
                end                
            elseif strcmp(tipo_var,'PCRPos') || strcmp(tipo_var,'PCRNeg') || strcmp(tipo_var,'PCRNegERNC')
                indice_actual = indice_global_desde - 1;
                for cont = 1:this.iCantContingenciasGenCons
                    for oper = 1:this.iCantPuntosOperacion
                        indice_actual = indice_actual + 1;
                        texto = strcat(tipo_var, '_G', num2str(el_red.entrega_id()), ...
                            'F', num2str(cont), '_B', num2str(id_bus), '_O', num2str(oper));
                        this.NombreVariables{indice_actual} = texto;
                    end
                end
            else
                error = MException('cOPF:ingresa_nombres',...
                    ['Tipo variable ' tipo_var ' aun no implementada para generadores']);
                throw(error)                
            end
        end
        
        function ingresa_nombre_bateria(this, el_red, indice_global_desde, tipo_var, varargin)
            id_bus = el_red.entrega_se().entrega_id();
            if strcmp(tipo_var, 'Pdescarga')
                for oper = 1:this.iCantPuntosOperacion
                    indice_nombre = indice_global_desde + oper -1;
                    texto = strcat('PBatDesc_', num2str(el_red.entrega_id()), ...
                                   '_B', num2str(id_bus), '_O', num2str(oper));
                    this.NombreVariables{indice_nombre} = texto;
                end
            elseif strcmp(tipo_var, 'Pcarga')
                for oper = 1:this.iCantPuntosOperacion
                    indice_nombre = indice_global_desde + oper -1;
                    texto = strcat('PBatCarga_', num2str(el_red.entrega_id()), ...
                                   '_B', num2str(id_bus), '_O', num2str(oper));
                    this.NombreVariables{indice_nombre} = texto;
                end
            elseif strcmp(tipo_var, 'ResDescarga')
                for oper = 1:this.iCantPuntosOperacion
                    indice_nombre = indice_global_desde + oper -1;
                    texto = strcat('ResBatDesc_', num2str(el_red.entrega_id()), ...
                                   '_B', num2str(id_bus), '_O', num2str(oper));
                    this.NombreVariables{indice_nombre} = texto;
                end
            elseif strcmp(tipo_var, 'ResCarga')
                for oper = 1:this.iCantPuntosOperacion
                    indice_nombre = indice_global_desde + oper -1;
                    texto = strcat('ResBatCarga_', num2str(el_red.entrega_id()), ...
                                   '_B', num2str(id_bus), '_O', num2str(oper));
                    this.NombreVariables{indice_nombre} = texto;
                end
            elseif strcmp(tipo_var,'E')
                for oper = 1:this.iCantPuntosOperacion
                    indice_nombre = indice_global_desde + oper -1;
                    texto = strcat('EBat_', num2str(el_red.entrega_id()), ...
                                   '_B', num2str(id_bus), '_O', num2str(oper));
                    this.NombreVariables{indice_nombre} = texto;
                end
            elseif strcmp(tipo_var, 'PCResDescarga')
                cont = varargin{1};
                for oper = 1:this.iCantPuntosOperacion
                    indice_actual = indice_global_desde + oper - 1;
                    texto = strcat('PBatPCDesc_', num2str(el_red.entrega_id()), ...
                        'F', num2str(cont), '_B', num2str(id_bus), '_O', num2str(oper));
                    this.NombreVariables{indice_actual} = texto;
                end
            elseif strcmp(tipo_var, 'PCResCarga')
                cont = varargin{1};
                for oper = 1:this.iCantPuntosOperacion
                    indice_actual = indice_global_desde + oper - 1;
                    texto = strcat('PBatResCarga_', num2str(el_red.entrega_id()), ...
                        'F', num2str(cont), '_B', num2str(id_bus), '_O', num2str(oper));
                    this.NombreVariables{indice_actual} = texto;
                end
            else
                error = MException('cOPF:ingresa_nombres',...
                    ['Tipo variable ' tipo_var ' aun no implementada para baterias']);
                throw(error)
            end
        end
        
        function ingresa_nombre_subestacion(this, el_red, indice_global_desde, tipo_var, varargin)
            id_bus = el_red.entrega_id();
            if strcmp(tipo_var, 'N0')
                for oper = 1:this.iCantPuntosOperacion
                    indice_nombre = indice_global_desde + oper -1;
                    texto = strcat('Theta_B', num2str(id_bus), ...
                                           '_O', num2str(oper));
                    this.NombreVariables{indice_nombre} = texto;
                end
            elseif strcmp(tipo_var, 'N1')
                cont = varargin{1};
                indice_actual = indice_global_desde - 1;
                for oper = 1:this.iCantPuntosOperacion
                    indice_actual = indice_actual + 1;
                    texto = strcat('ThetaN1_B', num2str(id_bus), ...
                        'F', num2str(cont), '_O', num2str(oper));
                    this.NombreVariables{indice_actual} = texto;
                end
            elseif strcmp(tipo_var, 'PC')
                cont = varargin{1};
                indice_actual = indice_global_desde - 1;
                for oper = 1:this.iCantPuntosOperacion
                    indice_actual = indice_actual + 1;
                    texto = strcat('ThetaPC_B', num2str(id_bus), ...
                        'F', num2str(cont), '_O', num2str(oper));
                    this.NombreVariables{indice_actual} = texto;
                end
            else
                error = MException('cOPF:ingresa_nombres',...
                    ['Tipo variable ' tipo_var ' aun no implementada para subestaciones']);
                throw(error)  
            end
        end
        
        function ingresa_nombre_consumo(this, el_red, indice_global_desde, tipo_var)        
            id_consumo = el_red.entrega_id();
            id_global_bus = el_red.entrega_se().entrega_id();
            if strcmp(tipo_var, 'N0')
                for oper = 1:this.iCantPuntosOperacion
                    indice_nombre = indice_global_desde + oper -1;
                    texto = strcat('ENS_C', num2str(id_consumo), ...
                                   '_B', num2str(id_global_bus), ...
                                   '_O', num2str(oper));
                    this.NombreVariables{indice_nombre} = texto;
                end
            elseif strcmp(tipo_var, 'N1')
                indice_actual = indice_global_desde - 1;
                for cont = 1:this.iCantContingenciasElSerie
                    for oper = 1:this.iCantPuntosOperacion
                        indice_actual = indice_actual + 1;
                        texto = strcat('ENS_N1_C', num2str(id_consumo), ...
                                   'F', num2str(cont), '_B', num2str(id_global_bus), ...
                                   '_O', num2str(oper));
                        this.NombreVariables{indice_actual} = texto;
                    end
                end
            elseif strcmp(tipo_var, 'PC')
                indice_actual = indice_global_desde - 1;
                for cont = 1:this.iCantContingenciasGenCons
                    for oper = 1:this.iCantPuntosOperacion
                        indice_actual = indice_actual + 1;
                        texto = strcat('ENS_PC_C', num2str(id_consumo), ...
                                   'F', num2str(cont), '_B', num2str(id_global_bus), ...
                                   '_O', num2str(oper));
                        this.NombreVariables{indice_actual} = texto;
                    end
                end
            else
                error = MException('cOPF:ingresa_nombres',...
                    ['Tipo variable ' tipo_var ' aun no implementada para consumos']);
                throw(error)  
            end
        end
        
        function ingresa_nombre_trafo_linea(this, el_red, indice_global_desde, tipo_var, varargin)
            id_par = el_red.entrega_indice_paralelo();
            id_global_bus1 = el_red.entrega_se1().entrega_id();
            id_global_bus2 = el_red.entrega_se2().entrega_id();
            if isa(el_red, 'cLinea')
                tipo_cond = el_red.entrega_tipo_conductor();
            else
                tipo_cond = el_red.entrega_tipo_trafo();
            end

            if strcmp(tipo_var,'N0')
                for oper = 1:this.iCantPuntosOperacion
                    indice_nombre = indice_global_desde + oper -1;
                    if isa(el_red, 'cLinea')
                        texto = strcat('PL', num2str(id_par), ...
                            '_C', num2str(tipo_cond), ...
                            '_B', num2str(id_global_bus1), ...
                            '_', num2str(id_global_bus2), ...
                            '_O', num2str(oper));
                        this.NombreVariables{indice_nombre} = texto;
                    else
                        texto = strcat('PT', num2str(id_par), ...
                            '_Tipo', num2str(tipo_cond), ... 
                            '_B', num2str(id_global_bus1), ...
                            '_', num2str(id_global_bus2), ...
                            '_O', num2str(oper));
                        this.NombreVariables{indice_nombre} = texto;
                    end
                end
            elseif strcmp(tipo_var,'N1')
                indice_actual = indice_global_desde - 1;
                cont = varargin{1};
                for oper = 1:this.iCantPuntosOperacion
                    indice_actual = indice_actual + 1;
                    if isa(el_red, 'cLinea')
                        texto_base = 'PN1_L';
                    else
                        texto_base = 'PN1_T';
                    end
                    texto = strcat(texto_base, num2str(id_par), ...
                        'F', num2str(cont), '_Tipo', num2str(tipo_cond), ... 
                        '_B', num2str(id_global_bus1), '_', num2str(id_global_bus2), ...
                        '_O', num2str(oper));
                    this.NombreVariables{indice_actual} = texto;
                end
            elseif strcmp(tipo_var,'PC')
                indice_actual = indice_global_desde - 1;
                for cont = 1:this.iCantContingenciasGenCons
                    for oper = 1:this.iCantPuntosOperacion
                        indice_actual = indice_actual + 1;
                        if isa(el_red, 'cLinea')
                            texto_base = 'PPC_L';
                        else
                            texto_base = 'PPC_T';
                        end
                        texto = strcat(texto_base, num2str(id_par), ...
                            'F', num2str(cont), '_Tipo', num2str(tipo_cond), ... 
                            '_B', num2str(id_global_bus1), '_', num2str(id_global_bus2), ...
                            '_O', num2str(oper));
                        this.NombreVariables{indice_actual} = texto;
                    end
                end
            else
                error = MException('cOPF:ingresa_nombres',...
                    ['Tipo Variable ' tipo_var ' aun no implementada para lineas y trafos']);
                throw(error)
            end
        end
        
        function ingresa_nombre_embalse(this, el_red, indice_global_desde, tipo_var)
            for oper = 1:this.iCantPuntosOperacion
                indice_nombre = indice_global_desde + oper -1;
                if strcmp(tipo_var, 'Vol')
                    texto = strcat('VE', num2str(el_red.entrega_id()), '_O', num2str(oper));
                    this.NombreVariables{indice_nombre} = texto;
                elseif strcmp(tipo_var, 'Vertimiento')
                    texto = strcat('VertE', num2str(el_red.entrega_id()), '_O', num2str(oper));
                    this.NombreVariables{indice_nombre} = texto;
                elseif strcmp(tipo_var, 'Filtracion')
                    texto = strcat('FiltE', num2str(el_red.entrega_id()), '_O', num2str(oper));
                    this.NombreVariables{indice_nombre} = texto;
                end
            end
        end
        
        function elimina_nombres_problema(this)
            this.NombreVariables = [];
            this.NombreIneq = [];
            this.NombreEq = [];
        end
        
        function muestra_detalle_iteraciones(this,val)
            this.MuestraDetalleIteraciones = val;
        end
        
        function inserta_solver(this,val)
            this.pParOpt.Solver = val;
        end
        
        function debug_fuerza_opt_sin_ens_ni_recorte_res(this)
            % MODO DEBUG. IMPIDE QUE HAYA ENS NI RECORTE RES. TODO TIENE
            % QUE ESTAR PREVIAMENTE INICIALIZADO
            for i = 1:this.Consumos.n            
                indice_desde = this.Consumos.IdVarOptDesde(i);
                indice_hasta = indice_desde + this.iCantPuntosOperacion -1;

                this.lb(indice_desde:indice_hasta) = 0;
                this.ub(indice_desde:indice_hasta) = 0;
            end
            
            gen_res = fid(this.Generadores.Despachable == 0);
            for i = 1:length(gen_res)
                indice_desde = this.Generadores.IdVarOptDesde(gen_res(i));
                indice_hasta = indice_desde + this.iCantPuntosOperacion -1;
                this.lb(indice_desde:indice_hasta) = 0;
                this.ub(indice_desde:indice_hasta) = 0;
            end
            this.optimiza();

            if this.pResEvaluacion.ExisteResultadoOPF
                this.pResEvaluacion.borra_evaluacion_actual();
            end
            
            if this.ExitFlag == 1
                % problema tiene solucion óptima
                this.pResEvaluacion.ExisteResultadoOPF = true;
                this.escribe_resultados();
                if this.iNivelDebug > 0
                    this.imprime_resultados_protocolo();
                end
            else
                this.pResEvaluacion.ExisteResultadoOPF = false;
                if this.iNivelDebug > 0
                    prot = cProtocolo.getInstance;
                    prot.imprime_texto('Problema de optimizacion invalido');
                    prot.imprime_texto(['Estado flag: ' num2str(this.ExitFlag)]);
                end
                % problema no tiene solucion
                % no se escriben resultados porque no tiene sentido
            end
        end
 	end
end