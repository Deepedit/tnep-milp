classdef cOptMILPN4 < handle
    properties
		pSEP = cSistemaElectricoPotencia.empty
        pAdmSc = cAdministradorEscenarios.empty
        pAdmProy = cAdministradorProyectos.empty
        pParOpt = cParOptimizacionMILP.empty
        VarExpansion = cProyectoExpansion.empty
%VarOperacion = cElementoRed.empty
        VarOperacion = cElementoRed.empty % variables de operación por cada escenario
        
        VarAux = []
        pPlanOptimo = cell.empty
        pPlanOperSinRestriccion = cell.empty
        COperUninodal = []
        ResOptimizacion %resultado variables de decision
        Fval %valor funcion objetivo
        ExitFlag
        Output
        
		Fobj  = [] %funcion objetivo
        Aeq = []  % matriz con restricciones de igualdad
        beq = []  % vector objetivo restricciones de igualdad
        Aineq = [] % matriz con restricciones de desigualdad
        bineq = []  % vector de desigualdades
        lb = [] %valores mínimos de variables de decisión
        ub = [] %valores máximos de variables de decisión
        intcon % contiene índices de variables binarias
        
        iNZIneqActual = 0;
        FilasIneq = []
        ColIneq = []
        ValIneq = []

        iNZEqActual = 0;
        FilasEq = []
        ColEq = []
        ValEq = []
        
        TipoVarOpt = [] % 1: expansión, 2: operación (2nd-level)
        SubtipoVarOpt = [] % para variables de expansión: 1: decisión expansion, 2: var. auxiliar (incluye costos de inversión), 3) inv. acumulada. Se utiliza en operación también; para variables de operación: 1: UC, 2: operación
        EscenarioVarOpt = [] % 0: todos, i: escenario i
        EtapaVarOpt = [] % nro. etapa
        SubetapaVarOpt = [];
        
        TipoRestriccionIneq = []; % 1: expansión, 2: operación (2nd-level)
        TipoRestriccionEq = []; % 1: expansión, 2: operación (2nd-level)
        EscenarioRestriccionIneq = [];
        EscenarioRestriccionEq = [];
        EtapaRestriccionIneq = [];
        EtapaRestriccionEq = [];
        SubetapaRestriccionIneq = [];
        SubetapaRestriccionEq = [];
        
        RelSubetapasPO = [];
        %nombres de las restricciones
        NombreVariables = cell(1,0)
        NombreIneq = cell(1,0)
        NombreEq = cell(1,0)
        
        % variables para mandar el problema a FICO
        docIDFico
        NombreArchivoModeloFICO
        NombreArchivoResultadoFICO

        %ParDisyuntivosExistente
        
        ParDisyuntivosBase     % formuación base incluyendo uprating. 
        ParDisyuntivosCSCC
        ParDisyuntivosVU
        ParDisyuntivosConv
        
        % siguientes par. son para comparar
        ParDisyuntivosBaseOrig % formulacion original, sin considerar proyectos adyacentes. Sólo para comparar
        ParDisyuntivosCSCCOrig
        ParDisyuntivosVUOrig
        ParDisyuntivosConvOrig


        ExisteSolucionAEvaluar = false
        SolucionAEvaluar
        
        iIndiceIneq = 0
        iIndiceEq = 0
        iCantVarDecision = 0
        iCantPuntosOperacion = 0
        bConsideraDependenciaTemporal = false
        vIndicesPOConsecutivos = [] % cuando se consideran baterías y/o sistemas de almacenamiento. Largo indica cant. PO consecutivos. Ancho: indice po desde, indice po hasta
        
        iCantEscenarios = 0
        iCantEtapas = 0
        iCantSubetapas = 0
        iNivelDebug = 0
        
        %Estructura variables de decision
        % por cada etapa, se repite la siguiente estructura
        % [ Lineas               1..NL  ]    -->  variables de expansion
        % [ P Generadores        1..NG PO1 ] --> abajo: variables de operacion
        % [ Ang Subestaciones    1..NSE PO1 ]
        % [P lineas de expansion 1..NL PO1] inc. existentes para facilitar
        % [ Generadores          1..NG PO2 ]
        % [ Subestaciones        1..NSE PO2 ]
        % [P lineas totales      1..NL PO2]  
        % [ ... ]
        % [ Generadores          1..NG POM ]
        % [ Subestaciones        1..NSE POM ]
        % [P lineas de expansion 1..NL POM]
    end
    
    methods
	
        function this = cOptMILPN3(sep, adm_escenarios, adm_proy, par_opt)
			this.pSEP = sep;
            this.pAdmSc = adm_escenarios;
            this.pAdmProy = adm_proy;
            this.pParOpt = par_opt;
            this.iCantVarDecision = 0;
            this.iIndiceIneq = 0;
            this.iIndiceEq = 0;
            this.iNivelDebug = par_opt.NivelDebug;
            this.iCantEtapas = this.pParOpt.CantidadEtapas; 
            this.iCantEscenarios = this.pAdmSc.entrega_cantidad_escenarios();
            this.iCantPuntosOperacion = this.pAdmSc.entrega_cantidad_puntos_operacion();
            this.bConsideraDependenciaTemporal = this.pAdmSc.considera_dependencia_temporal();
            this.vIndicesPOConsecutivos = this.pAdmSc.entrega_indices_po_consecutivos();            

            if this.pParOpt.NivelSubetapasParaCortes == 1
                this.iCantSubetapas = 1;
                this.RelSubetapasPO = ones(this.iCantPuntosOperacion,1);
            elseif this.pParOpt.NivelSubetapasParaCortes == 2
                this.iCantSubetapas = size(this.vIndicesPOConsecutivos,1);
                this.RelSubetapasPO = zeros(this.iCantPuntosOperacion,1);
               for i = 1:this.iCantSubetapas
                   desde = this.vIndicesPOConsecutivos(i,1);
                   hasta = this.vIndicesPOConsecutivos(i,2);
                   this.RelSubetapasPO(desde:hasta) = i;
               end
            elseif this.pParOpt.NivelSubetapasParaCortes == 3
                this.iCantSubetapas = this.iCantPuntosOperacion;           
                this.RelSubetapasPO = (1:1:this.iCantPuntosOperacion)';
            end
            
            % uncertainties
            for i = 1:this.iCantEscenarios
                this.pPlanOptimo{i} = cPlanExpansion(1);
            end
		end
		
        function escribe_problema_optimizacion(this)
            %this.determina_dimension_problema();
            disp('inicializa variables decision');
            this.inicializa_variables_decision();
            
            disp('calcula parametros disyuntivos');
            this.calcula_parametros_disyuntivos();
            
            disp('inicializa contenedores');
            this.inicializa_contenedores();
            disp('escribe restricciones');
            this.escribe_restricciones();
                
            disp('escribe función objetivo');
            this.escribe_funcion_objetivo();

tic                
            this.Aineq = sparse(this.FilasIneq,this.ColIneq,this.ValIneq,this.iIndiceIneq,this.iCantVarDecision);
            this.Aeq = sparse(this.FilasEq,this.ColEq,this.ValEq, this.iIndiceEq,this.iCantVarDecision);
toc            
            disp('fin escribe problema optimización');
            if strcmp(this.pParOpt.Solver, 'FICO')
                this.inicializa_modelo_fico();
                this.escribe_modelo_fico();
                this.finaliza_modelo_fico();
            end            
        end
		
        function inicializa_variables_decision(this)
            
            % crea vector con variables de expansión 
            this.VarExpansion = this.pAdmProy.entrega_proyectos();

            % crea vector con variables de operación
            this.VarOperacion = this.pSEP.entrega_generadores_despachables();
            if this.pParOpt.considera_recorte_res()
                this.VarOperacion = [this.VarOperacion; this.pSEP.entrega_generadores_res()];
            end

            this.VarOperacion = [this.VarOperacion; this.pSEP.entrega_subestaciones()];

            if this.pParOpt.considera_desprendimiento_carga()
                this.VarOperacion = [this.VarOperacion; this.pSEP.entrega_consumos()];
            end

            this.VarOperacion = [this.VarOperacion; this.pSEP.entrega_lineas()];
            this.VarOperacion = [this.VarOperacion; this.pSEP.entrega_transformadores2d()];
            this.VarOperacion = [this.VarOperacion; this.pSEP.entrega_baterias()];
            
            % elementos de decision de expansion
            this.VarOperacion = [this.VarOperacion; this.pAdmProy.entrega_subestaciones_expansion()];
            this.VarOperacion = [this.VarOperacion; this.pAdmProy.entrega_elementos_serie_expansion()];
            this.VarOperacion = [this.VarOperacion; this.pAdmProy.entrega_baterias_expansion()];
            
            % elementos específicos escenario (entran en alguna etapa. No son variables de decisión de expansión)
            this.VarOperacion = [this.VarOperacion; this.pAdmProy.entrega_subestaciones_proyectadas_todas()'];
            this.VarOperacion = [this.VarOperacion; this.pAdmProy.entrega_generadores_despachables_proyectados_todos()'];
            if this.pParOpt.considera_recorte_res()
                this.VarOperacion = [this.VarOperacion; this.pAdmProy.entrega_generadores_ernc_proyectados_todos()'];
            end
            if this.pParOpt.considera_desprendimiento_carga()
                this.VarOperacion = [this.VarOperacion; this.pAdmProy.entrega_consumos_proyectados_todos()'];
            end
            
            % elementos serie proyectados son líneas y transformadores
            this.VarOperacion = [this.VarOperacion; this.pAdmProy.entrega_elementos_serie_proyectados_todos()'];
            
            % inicializa contenedores variables de operación (es ineficiente, pero no perjudica)
            if this.pParOpt.considera_valor_residual_elementos()
                this.VarAux = sparse(0, 0);
            end
            
            % inicializa contenedores en los elementos de red
            for escenario = 1:this.iCantEscenarios
                for varopt = 1:length(this.VarOperacion)
                    this.VarOperacion(varopt).inicializa_varopt_operacion_milp_dc(this.iCantEscenarios, this.iCantEtapas);
                end
            end

            % inicializa variables
            % [expansion escenario1, expansion escenario2, .., auxiliares, operacion escenario 1, operacion escenario 2, ...]
            
            % variables de decisión expansión
            this.iCantVarDecision = 0;
            for escenario = 1:this.iCantEscenarios
                this.inicializa_variables_decision_expansion(escenario);
            end
            if this.pParOpt.considera_valor_residual_elementos()
                for escenario = 1:this.iCantEscenarios
                    this.inicializa_variables_auxiliares(escenario);
                end
            end
            % variables de decisión operacion
            for escenario = 1:this.iCantEscenarios
                for etapa = 1:this.iCantEtapas
                    this.inicializa_variables_decision_operacion(escenario, etapa);
                end
            end
        end

        function inicializa_variables_decision_expansion(this, escenario)
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            for i=1:length(this.VarExpansion)
				cant_etapas_comunes = this.VarExpansion(i).entrega_etapas_entrada_en_operacion();
				if escenario == 1 && cant_etapas_comunes > 0
					% inserta variables de expansión comunes
					this.iCantVarDecision = this.iCantVarDecision + 1;
					indice_exp_comun_desde = this.iCantVarDecision;
					indice_exp_comun_hasta = indice_exp_comun_desde + cant_etapas_comunes - 1;
					this.iCantVarDecision = indice_exp_comun_hasta;
					this.VarExpansion(i).inserta_varopt_expansion_comun('Decision', indice_exp_comun_desde);

					this.intcon = [this.intcon indice_exp_comun_desde:1:indice_exp_comun_hasta];
					this.lb(indice_exp_comun_desde:indice_exp_comun_hasta) = 0;
					this.ub(indice_exp_comun_desde:indice_exp_comun_hasta) = 1;
					this.TipoVarOpt(indice_exp_comun_desde:indice_exp_comun_hasta) = 1;
					this.SubtipoVarOpt(indice_exp_comun_desde:indice_exp_comun_hasta) = 1;
					
					this.EscenarioVarOpt(indice_exp_comun_desde:indice_exp_comun_hasta) = 0;
					this.EtapaVarOpt(indice_exp_comun_desde:indice_exp_comun_hasta) = 1:1:cant_etapas_comunes;
					this.SubetapaVarOpt(indice_exp_comun_desde:indice_exp_comun_hasta) = 0;
				end
				
				% inserta el resto de las variables (particulares por cada escenario)
				this.iCantVarDecision = this.iCantVarDecision + 1;
				indice_exp_desde = this.iCantVarDecision;
				indice_exp_hasta = indice_exp_desde + this.iCantEtapas -cant_etapas_comunes - 1;
				this.iCantVarDecision = indice_exp_hasta;
					
				this.VarExpansion(i).inserta_varopt_expansion('Decision', escenario, indice_exp_desde);
					
				this.intcon = [this.intcon indice_exp_desde:1:indice_exp_hasta];
				this.lb(indice_exp_desde:indice_exp_hasta) = 0;
				this.ub(indice_exp_desde:indice_exp_hasta) = 1;
				this.TipoVarOpt(indice_exp_desde:indice_exp_hasta) = 1;
				this.SubtipoVarOpt(indice_exp_desde:indice_exp_hasta) = 1;
				
				this.EscenarioVarOpt(indice_exp_desde:indice_exp_hasta) = escenario;
				this.EtapaVarOpt(indice_exp_desde:indice_exp_hasta) = cant_etapas_comunes+1:1:this.iCantEtapas;
				this.SubetapaVarOpt(indice_exp_desde:indice_exp_hasta) = 0;
                
%linlinlin debug
%if proy.entrega_indice() >= 38
%    this.ub(indice_desde_exp:indice_hasta_exp) = 0;
%    if proy.entrega_indice() ==42
%        this.lb(indice_desde_exp:indice_desde_exp) = 1;
%        this.ub(indice_desde_exp:indice_desde_exp) = 1;
%    end
%end
    
%this.lb(indice_desde_exp:indice_desde_exp) = 1;
% linlinlinlin
% if ~proy.EsUprating
% 	this.lb(indice_desde_exp:indice_hasta_exp) = 0;
%     this.ub(indice_desde_exp:indice_hasta_exp) = 0;
% end
%if proy.entrega_indice() == 71
%    this.lb(indice_desde_exp + 2) = 1;
%end

%                if this.ExisteSolucionAEvaluar
%                    this.ub(indice_desde_exp:indice_hasta_exp) = 0;
%                    if ~isempty(find(ismember([this.SolucionAEvaluar(:,1) this.SolucionAEvaluar(:,3)], [escenario this.VarExpansion(i).entrega_indice],'rows'), 1))
%                        indice_solucion = ismember([this.SolucionAEvaluar(:,1) this.SolucionAEvaluar(:,3)], [escenario this.VarExpansion(i).entrega_indice],'rows');
%                        etapa_entrada = this.SolucionAEvaluar(indice_solucion,2);
%                        
%                        etapa_opt = indice_desde_exp + etapa_entrada - 1;
%                        this.lb(etapa_opt) = 1;
%                        this.ub(etapa_opt) = 1;
%                    end
%                end
                
                % variable acumulada
				if escenario == 1 && cant_etapas_comunes > 0
					%  variables comunes
					this.iCantVarDecision = this.iCantVarDecision + 1;
					indice_cum_comun_desde = this.iCantVarDecision;
					indice_cum_comun_hasta = indice_cum_comun_desde + cant_etapas_comunes - 1;
					this.iCantVarDecision = indice_cum_comun_hasta;
					this.VarExpansion(i).inserta_varopt_expansion_comun('Acumulada', indice_cum_comun_desde);

					this.intcon = [this.intcon indice_cum_comun_desde:1:indice_cum_comun_hasta];
					this.lb(indice_cum_comun_desde:indice_cum_comun_hasta) = 0;
					this.ub(indice_cum_comun_desde:indice_cum_comun_hasta) = 1;
					this.TipoVarOpt(indice_cum_comun_desde:indice_cum_comun_hasta) = 1;
					this.SubtipoVarOpt(indice_cum_comun_desde:indice_cum_comun_hasta) = 3;
					
					this.EscenarioVarOpt(indice_cum_comun_desde:indice_cum_comun_hasta) = 0;
					this.EtapaVarOpt(indice_cum_comun_desde:indice_cum_comun_hasta) = 1:1:cant_etapas_comunes;
					this.SubetapaVarOpt(indice_cum_comun_desde:indice_cum_comun_hasta) = 0;
				end
				
                this.iCantVarDecision = this.iCantVarDecision + 1;
                indice_cum_desde = this.iCantVarDecision;
                indice_cum_hasta = indice_cum_desde + this.iCantEtapas -cant_etapas_comunes - 1;
                this.iCantVarDecision = indice_cum_hasta;
                this.VarExpansion(i).inserta_varopt_expansion('Acumulada', escenario, indice_cum_desde);
                
                this.intcon = [this.intcon indice_cum_desde:1:indice_cum_hasta];
                this.lb(indice_cum_desde:indice_cum_hasta) = 0;
                this.ub(indice_cum_desde:indice_cum_hasta) = 1;
                this.TipoVarOpt(indice_cum_desde:indice_cum_hasta) = 1;
                this.SubtipoVarOpt(indice_cum_desde:indice_cum_hasta) = 3; % involucra tanto decisión de expansión como operación
                
                this.EscenarioVarOpt(indice_cum_desde:indice_cum_hasta) = escenario;
                this.EtapaVarOpt(indice_cum_desde:indice_cum_hasta) = cant_etapas_comunes + 1:1:this.iCantEtapas;
                this.SubetapaVarOpt(indice_cum_desde:indice_cum_hasta) = 0;

                if this.pParOpt.considera_valor_residual_elementos()
					if escenario == 1 && cant_etapas_comunes > 0
						indice_costo_cum_desde = this.iCantVarDecision+1;
						indice_costo_cum_hasta = indice_costo_cum_desde + cant_etapas_comunes - 1;
						this.iCantVarDecision = indice_costo_cum_hasta; % último valor actual de CantVarDecision

						this.VarExpansion(i).inserta_varopt_expansion_comun('Costo', indice_costo_cum_desde);
						costo_max = this.VarExpansion(i).entrega_costos_inversion();
						factor_desarrollo_proyecto = this.pParOpt.entrega_factor_costo_desarrollo_proyectos();
						costo_max = costo_max*factor_desarrollo_proyecto;
						this.lb(indice_costo_cum_desde:indice_costo_cum_hasta) = 0;
						this.ub(indice_costo_cum_desde:indice_costo_cum_hasta) = round(costo_max,dec_redondeo); % para estabilidad numérica
						this.TipoVarOpt(indice_costo_cum_desde:indice_costo_cum_hasta) = 1;
						this.SubtipoVarOpt(indice_costo_cum_desde:indice_costo_cum_hasta) = 2;
						this.EscenarioVarOpt(indice_costo_cum_desde:indice_costo_cum_hasta) = 0;
						this.EtapaVarOpt(indice_costo_cum_desde:indice_costo_cum_hasta) = 1:1:cant_etapas_comunes;
						this.SubetapaVarOpt(indice_costo_cum_desde:indice_costo_cum_hasta) = 0;
					end
					
                    indice_costo_desde = this.iCantVarDecision+1;
                    indice_costo_hasta = indice_costo_desde + this.iCantEtapas -cant_etapas_comunes - 1;
                    this.iCantVarDecision = indice_costo_hasta; % último valor actual de CantVarDecision
                
                    this.VarExpansion(i).inserta_varopt_expansion('Costo', escenario, indice_costo_desde);
                    costo_max = this.VarExpansion(i).entrega_costos_inversion();
                    factor_desarrollo_proyecto = this.pParOpt.entrega_factor_costo_desarrollo_proyectos();
                    costo_max = costo_max*factor_desarrollo_proyecto;
                    this.lb(indice_costo_desde:indice_costo_hasta) = 0;
                    this.ub(indice_costo_desde:indice_costo_hasta) = round(costo_max,dec_redondeo); % para estabilidad numérica
                    this.TipoVarOpt(indice_costo_desde:indice_costo_hasta) = 1;
                    this.SubtipoVarOpt(indice_costo_desde:indice_costo_hasta) = 2;
                    this.EscenarioVarOpt(indice_costo_desde:indice_costo_hasta) = escenario;
                    this.EtapaVarOpt(indice_costo_desde:indice_costo_hasta) = cant_etapas_comunes + 1:1:this.iCantEtapas;
                    this.SubetapaVarOpt(indice_costo_desde:indice_costo_hasta) = 0;
                end

                if this.iNivelDebug > 1
                    if escenario == 1 && cant_etapas_comunes > 0
						nombre = this.entrega_nombre_variables_expansion(this.VarExpansion(i), 1, cant_etapas_comunes, 0);
						indice_exp = (indice_exp_comun_desde:1:indice_exp_comun_hasta);
						this.NombreVariables(indice_exp) = cellstr(nombre);
							
						indice_cum = (indice_cum_comun_desde:1:indice_cum_comun_hasta);
						this.NombreVariables(indice_cum) = cellstr(strcat('Cum_', nombre));
						if this.pParOpt.considera_valor_residual_elementos()
							indice_costo = (indice_costo_cum_desde:1:indice_costo_cum_hasta)';
							this.NombreVariables(indice_costo) = cellstr(strcat('C', nombre));
						end
					end
					nombre = this.entrega_nombre_variables_expansion(this.VarExpansion(i), cant_etapas_comunes + 1, this.iCantEtapas, escenario);
                        
					indice_exp = (indice_exp_desde:1:indice_exp_hasta);
					this.NombreVariables(indice_exp) = cellstr(nombre);
                        
                    indice_cum = (indice_cum_desde:1:indice_cum_hasta); 
                    this.NombreVariables(indice_cum) = cellstr(strcat('Cum_', nombre));
					if this.pParOpt.considera_valor_residual_elementos()
						indice_costo = (indice_costo_desde:1:indice_costo_hasta)';
						this.NombreVariables(indice_costo) = cellstr(strcat('C', nombre));
                    end
                end
            end
        end
        
		function inicializa_variables_decision_operacion(this, escenario, etapa)
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            disp(['Inicializa variables decision operacion escenario ' num2str(escenario) ' etapa ' num2str(etapa)])
            contador = 10;
            for i = 1:length(this.VarOperacion)
                porcentaje = i/length(this.VarOperacion)*100;
                
                if porcentaje > contador
                    while contador + 10 < porcentaje
                        contador = contador + 10;
                    end

                    fprintf('%s %s',' ', [num2str(contador) '%']);
                    contador = contador + 10;
                    pause(0.1);
                end
 
%disp([num2str(i) '/' num2str(length(this.VarOperacion))])
                if isa(this.VarOperacion(i), 'cGenerador')
                    
                    if this.VarOperacion(i).Existente && ...
                            this.VarOperacion(i).entrega_retiro_proyectado() && ...
                            this.VarOperacion(i).entrega_etapa_retiro(escenario) <= etapa
                        continue
                    elseif ~this.VarOperacion(i).Existente && this.VarOperacion(i).Proyectado && (this.VarOperacion(i).entrega_etapa_entrada(escenario) == 0 || this.VarOperacion(i).entrega_etapa_entrada(escenario) > etapa)
                        continue
                    end
                    
                    this.iCantVarDecision = this.iCantVarDecision + 1;
                    indice_desde = this.iCantVarDecision;
                    indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;
                    this.iCantVarDecision = indice_hasta;
                    this.TipoVarOpt(indice_desde:indice_hasta) = 2;
                    this.SubtipoVarOpt(indice_desde:indice_hasta) = 2;
                    this.EscenarioVarOpt(indice_desde:indice_hasta) = escenario;
                    this.EtapaVarOpt(indice_desde:indice_hasta) = etapa;
                    this.SubetapaVarOpt(indice_desde:indice_hasta) = this.RelSubetapasPO;
                    
                    if this.VarOperacion(i).es_despachable()
                        this.VarOperacion(i).inserta_varopt_operacion('P', escenario, etapa, indice_desde);
                        if this.VarOperacion(i).entrega_evolucion_capacidad_a_futuro()
                            id_adm_sc = this.VarOperacion(i).entrega_indice_adm_escenario_capacidad(escenario);
                            capacidad = this.pAdmSc.entrega_capacidad_generador(id_adm_sc, etapa);
                        else                            
                            capacidad = this.VarOperacion(i).entrega_pmax();
                        end
                        this.lb(indice_desde:indice_hasta) = 0;
                        this.ub(indice_desde:indice_hasta) = round(capacidad/sbase,dec_redondeo);

                        if this.iNivelDebug > 1
                            oper = (1:1:this.iCantPuntosOperacion)';
                            %for oper = 1:this.iCantPuntosOperacion
                                id_se = this.VarOperacion(i).entrega_se().entrega_id();
                                id_generador = this.VarOperacion(i).entrega_id();
                                %indice = indice_desde + oper - 1;
                                indice = indice_desde:1:indice_desde + this.iCantPuntosOperacion - 1;
                                %this.NombreVariables{indice} = strcat('G', num2str(id_generador), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper));
                                nombre = strcat('G', num2str(id_generador), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                                this.NombreVariables(indice) = cellstr(nombre);
                            %end
                        end
                    else
                        %generador ernc
                        this.VarOperacion(i).inserta_varopt_operacion('P', escenario, etapa, indice_desde);
                        if this.VarOperacion(i).entrega_evolucion_capacidad_a_futuro()
                            id_adm_sc = this.VarOperacion(i).entrega_indice_adm_escenario_capacidad(escenario);
                            capacidad = this.pAdmSc.entrega_capacidad_generador(id_adm_sc, etapa);
                        else
                            capacidad = this.VarOperacion(i).entrega_pmax();
                        end
                        id_adm_sc = this.VarOperacion(i).entrega_indice_adm_escenario_perfil_ernc();
                        pmax = this.pAdmSc.entrega_perfil_ernc(id_adm_sc);
                        this.lb(indice_desde:indice_hasta) = 0;
                        this.ub(indice_desde:indice_hasta) = round(capacidad*pmax'/sbase,dec_redondeo);
                        if this.iNivelDebug > 1
                            oper = (1:1:this.iCantPuntosOperacion)';
                            id_se = this.VarOperacion(i).entrega_se().entrega_id();
                            id_generador = this.VarOperacion(i).entrega_id();
                            indice = indice_desde:1:indice_desde + this.iCantPuntosOperacion - 1;
                            nombre = strcat('GRES', num2str(id_generador), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                            this.NombreVariables(indice) = cellstr(nombre);
                            
%                             for oper = 1:this.iCantPuntosOperacion
%                                 id_se = this.VarOperacion(i).entrega_se().entrega_id();
%                                 id_generador = this.VarOperacion(i).entrega_id();
%                                 indice = indice_desde + oper - 1;
%                                 this.NombreVariables{indice} = strcat('GRES', num2str(id_generador), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper));
%                             end
                        end
                    end
                elseif isa(this.VarOperacion(i), 'cSubestacion')
                    if ~this.VarOperacion(i).Existente && this.VarOperacion(i).Proyectado
                        if this.VarOperacion(i).entrega_etapa_entrada(escenario) == 0 || this.VarOperacion(i).entrega_etapa_entrada(escenario) > etapa
                            continue
                        end
                    end
                    
                    this.iCantVarDecision = this.iCantVarDecision + 1;
                    indice_desde = this.iCantVarDecision;
                    indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;
                    this.iCantVarDecision = indice_hasta;
                    this.TipoVarOpt(indice_desde:indice_hasta) = 2;
                    this.SubtipoVarOpt(indice_desde:indice_hasta) = 2;
                    this.EscenarioVarOpt(indice_desde:indice_hasta) = escenario;
                    this.EtapaVarOpt(indice_desde:indice_hasta) = etapa;
                    this.SubetapaVarOpt(indice_desde:indice_hasta) = this.RelSubetapasPO;
                    
                    this.VarOperacion(i).inserta_varopt_operacion('Theta', escenario, etapa, indice_desde);
                    angulo_maximo = this.pParOpt.AnguloMaximoBuses;
                    if this.VarOperacion(i).es_slack()
                        this.lb(indice_desde:indice_hasta) = 0;
                        this.ub(indice_desde:indice_hasta) = 0;
                    else
                        this.lb(indice_desde:indice_hasta) = round(-angulo_maximo,dec_redondeo);
                        this.ub(indice_desde:indice_hasta) = round(angulo_maximo,dec_redondeo);
                    end
                    if this.iNivelDebug > 1
                        ubicacion = this.VarOperacion(i).entrega_ubicacion();
                        vn = this.VarOperacion(i).entrega_vn();
                        oper = (1:1:this.iCantPuntosOperacion)';
                        indice = indice_desde:1:indice_desde + this.iCantPuntosOperacion - 1;
                        nombre = strcat('B', num2str(ubicacion), '_V', num2str(vn), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                        this.NombreVariables(indice) = cellstr(nombre);
%                         for oper = 1:this.iCantPuntosOperacion
%                             indice = indice_desde + oper - 1;
%                             this.NombreVariables{indice} = strcat('B', num2str(ubicacion), '_V', num2str(vn), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper));
%                         end
                    end
                elseif isa(this.VarOperacion(i), 'cLinea') || isa(this.VarOperacion(i), 'cTransformador2D')
                    % si bien se restringe después dependiendo del estado
                    % de la línea (c.r. a los proyectos), limitar el valor
                    % aquí mejora la estabilidad numérica
                    if ~this.VarOperacion(i).Existente && this.VarOperacion(i).Proyectado
                        if this.VarOperacion(i).entrega_etapa_entrada(escenario) ~= 0 && this.VarOperacion(i).entrega_etapa_entrada(escenario) > etapa
                            continue
                        end
                    end
                    this.iCantVarDecision = this.iCantVarDecision + 1;
                    indice_desde = this.iCantVarDecision;
                    indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;
                    this.iCantVarDecision = indice_hasta;
                    this.TipoVarOpt(indice_desde:indice_hasta) = 2;
                    this.SubtipoVarOpt(indice_desde:indice_hasta) = 2;
                    this.EscenarioVarOpt(indice_desde:indice_hasta) = escenario;
                    this.EtapaVarOpt(indice_desde:indice_hasta) = etapa;
                    this.SubetapaVarOpt(indice_desde:indice_hasta) = this.RelSubetapasPO;
                    
                    this.VarOperacion(i).inserta_varopt_operacion('P', escenario, etapa, indice_desde);
                    sr = this.VarOperacion(i).entrega_sr_pu();
                    this.lb(indice_desde:indice_hasta) = round(-sr,dec_redondeo);
                    this.ub(indice_desde:indice_hasta) = round(sr,dec_redondeo);
                    
                    if this.iNivelDebug > 1
                        ubicacion_1= this.VarOperacion(i).entrega_se1().entrega_ubicacion();
                        ubicacion_2 = this.VarOperacion(i).entrega_se2().entrega_ubicacion();
                        id_par = this.VarOperacion(i).entrega_indice_paralelo();
                        oper = (1:1:this.iCantPuntosOperacion)';
                        indice = indice_desde:1:indice_desde + this.iCantPuntosOperacion - 1;
                        if isa(this.VarOperacion(i), 'cLinea')
                            tipo_conductor = this.VarOperacion(i).entrega_tipo_conductor();
                            compensacion = this.VarOperacion(i).entrega_compensacion_serie()*100;
                            vn = this.VarOperacion(i).entrega_se1().entrega_vn();
                            existe = this.pSEP.existe_elemento(this.VarOperacion(i));
                            if existe
                                tipo = 'LE';
                            else
                                if this.VarOperacion(i).Proyectado %&& this.VarOperacion(i).entrega_etapa_entrada(escenario) ~= 0
                                    tipo = 'LF';
                                else
                                    tipo = 'LP';
                                end
                            end
                            nombre = strcat('PL_', tipo, num2str(id_par), '_C', num2str(tipo_conductor), '_V', num2str(vn), '_CS_', num2str(compensacion), '_B', num2str(ubicacion_1), '_', num2str(ubicacion_2), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                            
%                             for oper = 1:this.iCantPuntosOperacion
%                                 indice = indice_desde + oper - 1;
%                                 nombre = ['PL_' tipo num2str(id_par) '_C' num2str(tipo_conductor) '_V' num2str(vn) '_CS_' num2str(compensacion) '_B' num2str(ubicacion_1) '_' num2str(ubicacion_2) '_S' num2str(escenario) '_E' num2str(etapa) '_O' num2str(oper)];
%                                 this.NombreVariables{indice} = nombre;
%                             end
                        else
                            existe = this.pSEP.existe_elemento(this.VarOperacion(i));
                            sr = this.VarOperacion(i).entrega_sr();
                            v1 = this.VarOperacion(i).entrega_se1().entrega_vn();
                            v2 = this.VarOperacion(i).entrega_se2().entrega_vn();
                            if existe
                                tipo = 'TE';
                            else
                                if this.VarOperacion(i).Proyectado %this.VarOperacion(i).entrega_etapa_entrada(escenario) ~= 0
                                    tipo = 'TF';
                                else
                                    tipo = 'TP';
                                end
                            end
                            nombre = strcat('PT_', tipo, num2str(id_par), '_Sr', num2str(sr), '_V', num2str(v1), '_', num2str(v2), '_B', num2str(ubicacion_1), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
%                             for oper = 1:this.iCantPuntosOperacion
%                                 indice = indice_desde + oper - 1;
%                                 nombre = ['PT_' tipo num2str(id_par) '_Sr' num2str(sr) '_V' num2str(v1) '_' num2str(v2) '_B' num2str(ubicacion_1) '_S' num2str(escenario) '_E' num2str(etapa) '_O' num2str(oper)];
%                                 this.NombreVariables{indice} = nombre;
%                             end
                        end
                        this.NombreVariables(indice) = cellstr(nombre);
                        
                    end
                elseif isa(this.VarOperacion(i), 'cConsumo')
                    if ~this.VarOperacion(i).Existente 
                        if this.VarOperacion(i).EtapaEntrada > etapa || this.VarOperacion(i).EtapaSalida <= etapa
                            continue
                        end
                    end

                    this.iCantVarDecision = this.iCantVarDecision + 1;
                    indice_desde = this.iCantVarDecision;
                    indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;
                    this.iCantVarDecision = indice_hasta;
                    this.TipoVarOpt(indice_desde:indice_hasta) = 2;
                    this.SubtipoVarOpt(indice_desde:indice_hasta) = 2;
                    this.EscenarioVarOpt(indice_desde:indice_hasta) = escenario;
                    this.EtapaVarOpt(indice_desde:indice_hasta) = etapa;
                    this.SubetapaVarOpt(indice_desde:indice_hasta) = this.RelSubetapasPO;
                    
                    sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
                    this.VarOperacion(i).inserta_varopt_operacion('P', escenario, etapa, indice_desde);
                    
                    indice_perfil = this.VarOperacion(i).entrega_indice_adm_escenario_perfil_p();
                    perfil = this.pAdmSc.entrega_perfil_consumo(indice_perfil);
                    indice_capacidad = this.VarOperacion(i).entrega_indice_adm_escenario_capacidad(escenario);
                    capacidad = this.pAdmSc.entrega_capacidad_consumo(indice_capacidad, etapa);
                    pmax = capacidad*perfil/sbase;
                    this.lb(indice_desde:indice_hasta) = 0;
                    this.ub(indice_desde:indice_hasta) = round(pmax',dec_redondeo);
                    if this.iNivelDebug > 1
                        id_se = this.VarOperacion(i).entrega_se().entrega_id();
                        id_consumo = this.VarOperacion(i).entrega_id();
                        oper = (1:1:this.iCantPuntosOperacion)';
                        indice = indice_desde:1:indice_desde + this.iCantPuntosOperacion - 1;
                        nombre = strcat('ENS', num2str(id_consumo), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                        this.NombreVariables(indice) = cellstr(nombre);
                        
%                         for oper = 1:this.iCantPuntosOperacion
%                             indice = indice_desde + oper - 1;
%                             this.NombreVariables{indice} = strcat('ENS', num2str(id_consumo), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper));
%                         end
                    end
                elseif isa(this.VarOperacion(i), 'cBateria')
                    
                    % Pdescarga
                    this.iCantVarDecision = this.iCantVarDecision + 1;
                    indice_desde = this.iCantVarDecision;
                    indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;
                    this.iCantVarDecision = indice_hasta;

                    this.TipoVarOpt(indice_desde:indice_hasta) = 2;
                    this.SubtipoVarOpt(indice_desde:indice_hasta) = 2;
                    this.EscenarioVarOpt(indice_desde:indice_hasta) = escenario;
                    this.EtapaVarOpt(indice_desde:indice_hasta) = etapa;
                    this.SubetapaVarOpt(indice_desde:indice_hasta) = this.RelSubetapasPO;
                    
                    pmax = this.VarOperacion(i).entrega_pmax_descarga();
                    this.VarOperacion(i).inserta_varopt_operacion('Pdescarga', escenario, etapa, indice_desde);
                    this.lb(indice_desde:indice_hasta) = 0;
                    this.ub(indice_desde:indice_hasta) = round(pmax/sbase,dec_redondeo);

                    if this.iNivelDebug > 1
                        id_se = this.VarOperacion(i).entrega_se().entrega_id();
                        id_bateria = this.VarOperacion(i).entrega_id();
                        oper = (1:1:this.iCantPuntosOperacion)';
                        indice = indice_desde:1:indice_desde + this.iCantPuntosOperacion - 1;
                        nombre = strcat('BPdesc', num2str(id_bateria), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                        this.NombreVariables(indice) = cellstr(nombre);
                        
%                         for oper = 1:this.iCantPuntosOperacion
%                             id_se = this.VarOperacion(i).entrega_se().entrega_id();
%                             id_bateria = this.VarOperacion(i).entrega_id();
%                             indice = indice_desde + oper - 1;
%                             this.NombreVariables{indice} = strcat('BPdesc', num2str(id_bateria), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper));
%                         end
                    end
                    
                    % Pcarga
                    this.iCantVarDecision = this.iCantVarDecision + 1;
                    indice_desde = this.iCantVarDecision;
                    indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;
                    this.iCantVarDecision = indice_hasta;
                    
                    this.TipoVarOpt(indice_desde:indice_hasta) = 2;
                    this.SubtipoVarOpt(indice_desde:indice_hasta) = 2;
                    this.EscenarioVarOpt(indice_desde:indice_hasta) = escenario;
                    this.EtapaVarOpt(indice_desde:indice_hasta) = etapa;
                    this.SubetapaVarOpt(indice_desde:indice_hasta) = this.RelSubetapasPO;
                    
                    pmax = this.VarOperacion(i).entrega_pmax_carga();
                    this.VarOperacion(i).inserta_varopt_operacion('Pcarga', escenario, etapa, indice_desde);
                    this.lb(indice_desde:indice_hasta) = 0;
                    this.ub(indice_desde:indice_hasta) = round(pmax/sbase,dec_redondeo);

                    if this.iNivelDebug > 1
                        id_se = this.VarOperacion(i).entrega_se().entrega_id();
                        id_bateria = this.VarOperacion(i).entrega_id();
                        oper = (1:1:this.iCantPuntosOperacion)';
                        indice = indice_desde:1:indice_desde + this.iCantPuntosOperacion - 1;
                        nombre = strcat('BPcarga', num2str(id_bateria), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                        this.NombreVariables(indice) = cellstr(nombre);
                        
%                         for oper = 1:this.iCantPuntosOperacion
%                             id_se = this.VarOperacion(i).entrega_se().entrega_id();
%                             id_bateria = this.VarOperacion(i).entrega_id();
%                             indice = indice_desde + oper - 1;
%                             this.NombreVariables{indice} = strcat('BPcarga', num2str(id_bateria), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper));
%                         end
                    end
                    
                    if this.bConsideraDependenciaTemporal
                        sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
                        this.iCantVarDecision = this.iCantVarDecision + 1;
                        indice_desde = this.iCantVarDecision;
                        indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;
                        this.iCantVarDecision = indice_hasta;
                        this.TipoVarOpt(indice_desde:indice_hasta) = 2;
                        this.SubtipoVarOpt(indice_desde:indice_hasta) = 2;
                        this.EscenarioVarOpt(indice_desde:indice_hasta) = escenario;
                        this.EtapaVarOpt(indice_desde:indice_hasta) = etapa;
                        this.SubetapaVarOpt(indice_desde:indice_hasta) = this.RelSubetapasPO;
                        
                        capacidad_max = this.VarOperacion(i).entrega_capacidad()/sbase;
                        soc_min = this.VarOperacion(i).entrega_soc_min();
                        capacidad_min = capacidad_max*soc_min;
                        
                        this.VarOperacion(i).inserta_varopt_operacion('E', escenario, etapa, indice_desde);
                        this.lb(indice_desde:indice_hasta) = round(capacidad_min,dec_redondeo);
                        this.ub(indice_desde:indice_hasta) = round(capacidad_max,dec_redondeo);
                        
                        % límites iniciales y finales en caso de que no se
                        % optimicen
                        if ~this.pParOpt.OptimizaSoCInicialBaterias
                            e_inicial = this.VarOperacion(i).entrega_soc_actual()*capacidad_max;
                            this.lb(indice_desde-1+this.vIndicesPOConsecutivos(:,1)) = round(e_inicial,dec_redondeo);
                            this.ub(indice_desde-1+this.vIndicesPOConsecutivos(:,1)) = round(e_inicial,dec_redondeo);
                            this.lb(indice_desde-1+this.vIndicesPOConsecutivos(:,2)) = round(e_inicial,dec_redondeo);
                            this.ub(indice_desde-1+this.vIndicesPOConsecutivos(:,2)) = round(e_inicial,dec_redondeo);
                        end
                        if this.iNivelDebug > 1
                            id_se = this.VarOperacion(i).entrega_se().entrega_id();
                            id_bateria = this.VarOperacion(i).entrega_id();
                            oper = (1:1:this.iCantPuntosOperacion)';
                            indice = indice_desde:1:indice_desde + this.iCantPuntosOperacion - 1;
                            nombre = strcat('BE', num2str(id_bateria), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                            this.NombreVariables(indice) = cellstr(nombre);
                            
%                             for oper = 1:this.iCantPuntosOperacion
%                                 id_se = this.VarOperacion(i).entrega_se().entrega_id();
%                                 id_bateria = this.VarOperacion(i).entrega_id();
%                                 indice = indice_desde + oper - 1;
%                                 this.NombreVariables{indice} = strcat('BE', num2str(id_bateria), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper));
%                             end
                        end
                        
                    end
                else
                    texto = ['Tipo elemento red "' class(this.VarOperacion(i)) '" no implementado. Nombre elemento: ' this.VarOperacion(i).entrega_nombre()];
                    error = MException('cOptMILP:inicializa_variables_decision_operacion',texto);
                    throw(error)
                end
            end
            fprintf('%s %s\n',' ', [num2str(100) '%']);            
        end

        function inicializa_variables_auxiliares(this, escenario)
            if this.iNivelDebug > 1
            	disp(['variables auxiliares escenario ' num2str(escenario)]);
            end
            
            
            contador = 10;
            for proy = 1:length(this.pAdmProy.ProyTransmision)
                if this.iNivelDebug > 1
                    porcentaje = proy/length(this.pAdmProy.ProyTransmision)*100;
                    if porcentaje > contador
                        while contador + 10 < porcentaje
                            contador = contador + 10;
                        end
                        
                        fprintf('%s %s',' ', [num2str(contador) '%']);
                        contador = contador + 10;
                        pause(0.1);
                    end
                end
                indice_exp_desde = this.pAdmProy.ProyTransmision(proy).entrega_varopt_expansion('Decision', escenario);
				cant_etapas_comunes = this.pAdmProy.ProyTransmision(proy).entrega_etapas_entrada_en_operacion();
				if cant_etapas_comunes > 0
					indice_exp_comun_desde = this.pAdmProy.ProyTransmision(proy).entrega_varopt_expansion_comun('Decision');
				end
                
				for etapa = 1:this.iCantEtapas
					if etapa <= cant_etapas_comunes
						if escenario > 1
							continue
						end
						indice_exp = indice_exp_comun_desde + etapa - 1;
					else
						indice_exp = indice_exp_desde + etapa -cant_etapas_comunes - 1;
					end					
                    
                    for id_el_red = 1:length(this.pAdmProy.ProyTransmision(proy).Elemento)
                        if strcmp(this.pAdmProy.ProyTransmision(proy).Accion{id_el_red}, 'R')
                            proyectos_dependientes = this.pAdmProy.ProyTransmision(proy).entrega_dependencias_elemento_a_remover(this.pAdmProy.ProyTransmision(proy).Elemento(id_el_red));
                            if ~isempty(proyectos_dependientes)
                                for dep = 1:length(proyectos_dependientes)
                                    indice_proy_dep_desde = proyectos_dependientes(dep).entrega_varopt_expansion('Decision', escenario);
									cant_etapas_comunes_proy_dep = proyectos_dependientes(dep).entrega_etapas_entrada_en_operacion();
                                    if cant_etapas_comunes_proy_dep > 1
										indice_proy_dep_comun_desde = proyectos_dependientes(dep).entrega_varopt_expansion_comun('Decision');
									end
									
									for etapa_previa = 1:etapa
										if etapa_previa <= cant_etapas_comunes_proy_dep
											indice_proy_dep = indice_proy_dep_comun_desde + etapa_previa - 1;
										else
											indice_proy_dep = indice_proy_dep_desde + etapa_previa - cant_etapas_comunes_proy_dep - 1;
										end					
                                        this.iCantVarDecision = this.iCantVarDecision + 1;
                                        this.VarAux(indice_exp, indice_proy_dep) = this.iCantVarDecision;
                                        this.intcon = [this.intcon this.iCantVarDecision];
                                        this.lb(this.iCantVarDecision) = 0;
                                        this.ub(this.iCantVarDecision) = 1;

                                        this.TipoVarOpt(this.iCantVarDecision) = 1;
                                        this.SubtipoVarOpt(this.iCantVarDecision) = 2;
                                        this.EscenarioVarOpt(this.iCantVarDecision) = escenario;
                                        this.EtapaVarOpt(this.iCantVarDecision) = etapa;
                                        this.SubetapaVarOpt(this.iCantVarDecision) = 0;
                                        
                                        %Nombres
                                        if this.iNivelDebug > 1
                                            idx_proy_dep = proyectos_dependientes(dep).entrega_indice();
                                            nombre = strcat('Aux_P', num2str(proy), '_E', num2str(etapa), '_P', num2str(idx_proy_dep), '_E', num2str(etapa_previa), '_S', num2str(escenario));
                                            this.NombreVariables{this.iCantVarDecision} = nombre;
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            if this.iNivelDebug > 1
                fprintf('%s %s\n',' ', [num2str(100) '%']);
            end
        end
        
        
        function inicializa_contenedores(this)
            
            % dimensión de variables se determina en forma estática para
            % descartar errores
            
            %dimensión de función objetivo es igual a la de variables de
            %decision
            this.Fobj = zeros(this.iCantVarDecision,1);
            
            %límites inferiores y superiores ya están inicializados al
            %momento de inicializar las variables de decision
            %this.lb = zeros(this.iCantVarDecision,1);
            %this.ub = zeros(this.iCantVarDecision,1);
            
            % Restricciones de igualdad contiene: 
            % 1. Calculo de decisión de expansión acumulada 
            %    Cantidad: #proyectos*#etapas*#escenarios
            % 1. Balance de energía por nodo (existente y proyectado), escenario, etapa y punto de operación
            %    Cantidad: #(seexistentes + #seproyectadas)*#etapas*#po*#escenarios
            % 2. Relaciones proyectos/costos (en caso de considerar valores residuales)
            %    Cantidad: #proyectos*#etapas*#escenarios
            n_se_existentes = length(this.pSEP.Subestaciones);
            n_se_proyectadas = length(this.pAdmProy.entrega_subestaciones_expansion());
            n_etapas = this.iCantEtapas;
            n_oper = this.iCantPuntosOperacion;
            n_proyectos = length(this.pAdmProy.ProyTransmision);
            n_escenarios = this.iCantEscenarios;
            cantidad_eq = n_proyectos*n_etapas*n_escenarios;
            cantidad_eq = cantidad_eq  + (n_se_existentes+n_se_proyectadas)*n_etapas*n_oper*n_escenarios;
            if this.pParOpt.considera_valor_residual_elementos()
                cantidad_eq = cantidad_eq + n_proyectos*n_etapas*n_escenarios;
            end
            if this.bConsideraDependenciaTemporal
                % balance energético de las baterías
                cant_baterias = length(this.pSEP.Baterias)+length(this.pAdmProy.entrega_baterias_expansion());
                cantidad_eq = cantidad_eq + cant_baterias*n_oper*n_etapas*n_escenarios;
            end
            
            % Restricciones entre escenarios
            if this.iCantEscenarios > 1
                cant_rest_entre_escenarios = 0;
                if this.pParOpt.TestRestriccionesProyEscenariosExhaustivas
                    cant_rest_por_etapa = factorial(this.iCantEscenarios)/(2*factorial(this.iCantEscenarios-2));
                else
                    cant_rest_por_etapa = this.iCantEscenarios - 1;
                end

                for proy = 1:length(this.pAdmProy.ProyTransmision)
                    etapas_para_entrada_en_operacion = this.pAdmProy.ProyTransmision(proy).entrega_etapas_entrada_en_operacion();
                    cant_rest_entre_escenarios = cant_rest_entre_escenarios + cant_rest_por_etapa*etapas_para_entrada_en_operacion;
                end
                cantidad_eq = cantidad_eq + cant_rest_entre_escenarios;
            end
            
            %this.Aeq = sparse(cantidad_eq, this.iCantVarDecision);
            %this.beq = zeros(cantidad_rest_igualdad, 1);
            this.beq = zeros(cantidad_eq, 1);
            %this.NombreEq = cell(cantidad_rest_igualdad,1);        
            this.NombreEq = cell(cantidad_eq,1);
            
            % Restricciones de desigualdad contienen:
            % 1. restricciones de proyectos: 
            % a) dependencias (#proy_con_dependencia * #etapas * #escenarios)
            % b) sets proy. obligatorios (#proy. obligatorios* #escenarios)
            % c) sets proy. excluyentes (1 vez por cada escenario)
            % 2. lím. operacionales líneas/trafos (2*elementos*etapas*po*escenarios)
            % YA NO 3. restricciones de flujos-ángulos para líneas proyectadas
            % 4. restricciones de variables auxiliares
            % 5. restricciones de requisito conectividad
            % 6. restricciones ángulos se proyectadas
            
            %n_proyectos;
            n_proy_dependencia = this.pAdmProy.entrega_cantidad_proyectos_con_dependencia();
            n_set_obligatorios = length(this.pAdmProy.ProyTransmisionObligatorios);
            n_set_excluyentes = length(this.pAdmProy.ProyTransmisionExcluyentes);
            n_aux = nnz(this.VarAux);
            n_lineas_trafos = length(this.pSEP.entrega_lineas())+length(this.pSEP.entrega_transformadores2d())+length(this.pAdmProy.entrega_elementos_serie_expansion());
            n_requisitos_conectividad = 0;
            for i = 1:length(this.pAdmProy.ProyTransmision)
                if this.pAdmProy.ProyTransmision(i).TieneRequisitosConectividad
                    cantidad = this.pAdmProy.ProyTransmision(i).entrega_cantidad_grupos_conectividad();
                    n_requisitos_conectividad = n_requisitos_conectividad + cantidad;
                end
            end
%            n_requisitos_angulo_se_proyectadas = length(this.pAdmProy.entrega_subestaciones_expansion());
n_requisitos_angulo_se_proyectadas = 0;            
            cantidad_ineq = (n_proy_dependencia*n_etapas + n_set_obligatorios +...
                            n_set_excluyentes + 4*n_lineas_trafos*n_etapas*n_oper + 3*n_aux +...
                            n_requisitos_conectividad*n_etapas+...
                            2*n_requisitos_angulo_se_proyectadas*n_etapas*n_oper)*n_escenarios;

            this.FilasIneq = [];
            this.ColIneq = [];
            this.ValIneq = [];

            this.FilasEq = [];
            this.ColEq = [];
            this.ValEq = [];
                        
%            this.Aineq = sparse(cantidad_ineq, this.iCantVarDecision);
            this.bineq = zeros(cantidad_ineq, 1);
            this.NombreIneq = cell(cantidad_ineq, 1);
            disp('Dimensión de contenedores (antes de escribir las restricciones)');
            disp(['Cantidad variables decisión: ' num2str(this.iCantVarDecision)]);
            disp(['Cantidad rest. igualdad: ' num2str(cantidad_eq)]);
            disp(['Cantidad rest. desigualdad: ' num2str(cantidad_ineq)]);
        end
        
		
        function escribe_funcion_objetivo(this)            
            % inversion
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            q = (1 + this.pParOpt.TasaDescuento);
            detapa = this.pParOpt.DeltaEtapa;
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();                

            vector_etapas = 1:detapa:this.iCantEtapas;
            
            descuento_etapas = 1./q.^vector_etapas;
            for i = 1:length(this.VarExpansion)
				cant_etapas_comunes = this.VarExpansion(i).entrega_etapas_entrada_en_operacion();
				if cant_etapas_comunes > 0
                    if this.pParOpt.considera_valor_residual_elementos()
                        indice_costo_desde = this.VarExpansion(i).entrega_varopt_expansion_comun('Costo');
                        indice_costo_hasta = indice_costo_desde + cant_etapas_comunes - 1;
                        this.Fobj(indice_costo_desde:indice_costo_hasta) = round(descuento_etapas(1:cant_etapas_comunes),dec_redondeo);
                    else
                        indice_expansion_desde = this.VarExpansion(i).entrega_varopt_expansion_comun('Decision');
                        indice_expansion_hasta = indice_expansion_desde + cant_etapas_comunes - 1;
                        costo_inversion = this.VarExpansion(i).entrega_costos_inversion();
                        factor_desarrollo = this.pParOpt.entrega_factor_costo_desarrollo_proyectos();
                        costo_inversion = costo_inversion*factor_desarrollo;

                        valor = round(costo_inversion*descuento_etapas(1:cant_etapas_comunes),dec_redondeo);
                        this.Fobj(indice_expansion_desde:indice_expansion_hasta) = valor;
                    end
				end
				
                for escenario = 1:this.iCantEscenarios
                    peso_escenario = this.pAdmSc.entrega_peso_escenario(escenario);
                    
                    if this.pParOpt.considera_valor_residual_elementos()
                        indice_costo_desde = this.VarExpansion(i).entrega_varopt_expansion('Costo', escenario);
                        indice_costo_hasta = indice_costo_desde + this.iCantEtapas -cant_etapas_comunes - 1;
                        this.Fobj(indice_costo_desde:indice_costo_hasta) = round(peso_escenario*descuento_etapas(cant_etapas_comunes +1:end),dec_redondeo);
                    else
                        indice_expansion_desde = this.VarExpansion(i).entrega_varopt_expansion('Decision', escenario);
                        indice_expansion_hasta = indice_expansion_desde + this.iCantEtapas - cant_etapas_comunes - 1;
                        costo_inversion = this.VarExpansion(i).entrega_costos_inversion();
                        factor_desarrollo = this.pParOpt.entrega_factor_costo_desarrollo_proyectos();
                        costo_inversion = costo_inversion*factor_desarrollo;

                        valor = round(costo_inversion*peso_escenario*descuento_etapas(cant_etapas_comunes +1:end),dec_redondeo);
                        this.Fobj(indice_expansion_desde:indice_expansion_hasta) = valor;
                    end
                end
            end
            % operacion 
            rep_puntos_operacion = this.pAdmSc.RepresentatividadPuntosOperacion;
            for escenario = 1:this.iCantEscenarios
                for etapa = 1:this.iCantEtapas
                    for varopt = 1:length(this.VarOperacion)
                        % verifica si varopt está operativa para escenario y etapa
                        if isa(this.VarOperacion(varopt), 'cGenerador') || (isa(this.VarOperacion(varopt), 'cConsumo') && this.pParOpt.considera_desprendimiento_carga())
                            indice_desde = this.VarOperacion(varopt).entrega_varopt_operacion('P', escenario, etapa);
                            if indice_desde == 0 
                               % quiere decir que generador no está operativo en esta etapa y escenario
                               continue
                            end
                            indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;
                        else
                            continue
                        end
                        
                        if isa(this.VarOperacion(varopt), 'cGenerador')

                            if this.VarOperacion(varopt).es_despachable()
                                % determina costo generador
                                if this.VarOperacion(varopt).entrega_evolucion_costos_a_futuro()
                                    id_adm_sc = this.VarOperacion(varopt).entrega_indice_adm_escenario_costos_futuros(escenario);
                                    costo_pu = this.pAdmSc.entrega_costos_generacion_etapa_pu(id_adm_sc, etapa);
                                else
                                    costo_pu = this.VarOperacion(varopt).entrega_costo_mwh_pu();
                                end
                                costo = round(costo_pu * rep_puntos_operacion/q^(detapa*etapa)/1000000,dec_redondeo); % en millones para equiparar con costos de expansión
                                this.Fobj(indice_desde:indice_hasta) = costo;
                                
                            elseif this.pParOpt.considera_recorte_res()
                                % generador es res y se consideran recortes res
                                costo_pu = sbase*this.pParOpt.entrega_penalizacion(); % en $/pu
                                costo = round(costo_pu * rep_puntos_operacion/q^(detapa*etapa)/1000000,dec_redondeo); % en millones para equiparar con costos de expansión
                                this.Fobj(indice_desde:indice_hasta) = costo;
                            end

                        elseif isa(this.VarOperacion(varopt), 'cConsumo') && this.pParOpt.considera_desprendimiento_carga()
                            costo_desconexion = sbase*this.pParOpt.entrega_penalizacion(); % en $/pu
                            costo = round(costo_desconexion * rep_puntos_operacion/q^(detapa*etapa)/1000000,dec_redondeo); % en millones para equiparar con costos de expansión                        
                            this.Fobj(indice_desde:indice_hasta) = costo;
                        end
                    end
                end
            end
        end
            
        function escribe_restricciones(this)
            disp('escribe restricciones expansion');
            this.escribe_restricciones_expansion();
            
            disp('escribe restricciones operación');
            this.escribe_restricciones_operacion();
        end
        
        function escribe_restricciones_expansion(this)
            disp('   escribe restricciones proyectos');
            this.escribe_restricciones_proyectos();
            
            if this.pParOpt.considera_valor_residual_elementos()
                disp('   escribe relaciones proyectos costos');
                this.escribe_relaciones_proyectos_costos();
            end
            
            disp('   escribe restricciones variables auxiliares');
            this.escribe_restricciones_variables_auxiliares();
        end
                
        function escribe_restricciones_proyectos(this)
            % restricciones de proyectos
            contador = 0;
            cant_proyectos = length(this.pAdmProy.ProyTransmision);
            ProyConectividad = [];
            RelProyConectProyPrimarios = struct;
            cant_proy_conectividad = 0;
            
            for proy = 1:cant_proyectos
                if this.iNivelDebug > 1
                    porcentaje = proy/cant_proyectos*100;
                    if porcentaje > contador
                        while contador + 10 < porcentaje
                            contador = contador + 10;
                        end
                        fprintf('%s %s',' ', [num2str(contador) '%']);
                        pause(0.1);
                        contador = contador + 10;
                    end
                end
                
                indice_base_proy_por_escenario = zeros(this.iCantEscenarios,1);
				cant_etapas_comunes = this.pAdmProy.ProyTransmision(proy).entrega_etapas_entrada_en_operacion();
				if cant_etapas_comunes > 0
					indice_comun_desde = this.pAdmProy.ProyTransmision(proy).entrega_varopt_expansion_comun('Decision');
					indice_comun_acumulado_desde = this.pAdmProy.ProyTransmision(proy).entrega_varopt_expansion_comun('Acumulada');
					for etapa = 1:cant_etapas_comunes
						this.iIndiceEq = this.iIndiceEq + 1;
						indice_comun_actual = indice_comun_desde + etapa - 1;
						indice_comun_acumulado_actual = indice_comun_acumulado_desde + etapa - 1;
						this.agrega_valores_matriz_igualdad(1,this.iIndiceEq, indice_comun_actual,-1);
						this.agrega_valores_matriz_igualdad(1,this.iIndiceEq, indice_comun_acumulado_actual,1);
						if etapa > 1
							this.agrega_valores_matriz_igualdad(1,this.iIndiceEq, indice_comun_acumulado_actual-1,-1);
						end

                        this.beq(this.iIndiceEq,1) = 0;
                        this.TipoRestriccionEq(this.iIndiceEq) = 1;
                        this.EscenarioRestriccionEq(this.iIndiceEq) = 0;
                        this.EtapaRestriccionEq(this.iIndiceEq) = etapa;
                        this.SubetapaRestriccionEq(this.iIndiceEq) = 0;

                        if this.iNivelDebug > 1
                            indice_proy = this.pAdmProy.ProyTransmision(proy).Indice;
                            this.NombreEq{this.iIndiceEq} = strcat('req_', num2str(this.iIndiceEq), '_acumulado_', 'P', num2str(indice_proy), '_S0');
                        end						
					end

                    % restricciones de dependencia
                    if this.pAdmProy.ProyTransmision(proy).TieneDependencia
                        for etapa = 1:cant_etapas_comunes
                            this.iIndiceIneq = this.iIndiceIneq + 1;

                            %indice_proy = indice_desde + etapa - 1;
                            indice_proy = indice_comun_acumulado_desde + etapa - 1;
                            this.agrega_valores_matriz_desigualdad(1,this.iIndiceIneq, indice_proy,1);
                            
                            this.bineq(this.iIndiceIneq,1) = 0;
                            this.TipoRestriccionIneq(this.iIndiceIneq) = 1;
                            this.EscenarioRestriccionIneq(this.iIndiceIneq) = 0;
                            this.EtapaRestriccionIneq(this.iIndiceIneq) = etapa;
                            this.SubetapaRestriccionIneq(this.iIndiceIneq) = 0;
                            
                            dependencias = this.pAdmProy.ProyTransmision(proy).ProyectoDependiente;
                            for dep = 1:length(dependencias)
                                indice_dependencia = dependencias(dep).entrega_varopt_expansion_comun('Acumulada') + etapa - 1;
                                this.agrega_valores_matriz_desigualdad(1,this.iIndiceIneq, indice_dependencia,-1);
                            end
                            
                            if this.iNivelDebug > 1
                                proy_id = this.pAdmProy.ProyTransmision(proy).entrega_indice();
                                this.NombreIneq{this.iIndiceIneq} = strcat('rineq_', num2str(this.iIndiceIneq), ...
                                    '_dependencias_', 'P', num2str(proy_id), '_E', num2str(etapa), '_S0');
                            end
                        end
                    end
                    %restricciones de conectividad
                    if this.pAdmProy.ProyTransmision(proy).TieneRequisitosConectividad
                        cantidad = this.pAdmProy.ProyTransmision(proy).entrega_cantidad_grupos_conectividad();
                        for etapa = 1:cant_etapas_comunes
                            indice_proy = indice_comun_acumulado_desde + etapa - 1;
                            
                            for no_grupo = 1:cantidad
                                this.iIndiceIneq = this.iIndiceIneq + 1;
                                %this.Aineq(this.iIndiceIneq,indice_proy) = 1;
                                this.agrega_valores_matriz_desigualdad(1,this.iIndiceIneq, indice_proy,1);
                                this.bineq(this.iIndiceIneq,1) = 0;
                                this.TipoRestriccionIneq(this.iIndiceIneq) = 1;
                                this.EscenarioRestriccionIneq(this.iIndiceIneq) = 0;
                                this.EtapaRestriccionIneq(this.iIndiceIneq) = etapa;
                                this.SubetapaRestriccionIneq(this.iIndiceIneq) = 0;
                                
                                proy_con = this.pAdmProy.ProyTransmision(proy).entrega_grupo_proyectos_conectividad(no_grupo);
                                for ii = 1:length(proy_con)
                                    indice_con = proy_con(ii).entrega_varopt_expansion_comun('Acumulada') + etapa - 1;
                                    this.agrega_valores_matriz_desigualdad(1,this.iIndiceIneq, indice_con,-1);
                                    
                                    % agrega relaciones con proyectos de conectividad
                                    if etapa == 1
                                        id_proy_con = proy_con(ii).entrega_indice();
                                        pos_proy_conect = find(ProyConectividad == id_proy_con);
                                        if isempty(pos_proy_conect)
                                            cant_proy_conectividad = cant_proy_conectividad + 1;
                                            ProyConectividad(cant_proy_conectividad) = id_proy_con;
                                            RelProyConectProyPrimarios(cant_proy_conectividad).ProyPrimario = proy;
                                        else
                                            RelProyConectProyPrimarios(pos_proy_conect).ProyPrimario = [RelProyConectProyPrimarios(pos_proy_conect).ProyPrimario proy];
                                        end
                                    end
                                end
                                if this.iNivelDebug > 1
                                    proy_id = this.pAdmProy.ProyTransmision(proy).entrega_indice();
                                    this.NombreIneq{this.iIndiceIneq} = strcat('rineq_', num2str(this.iIndiceIneq), ...
                                        '_conectividad_', 'P', num2str(proy_id), '_grupo_', num2str(no_grupo), '_E', num2str(etapa), '_S0');
                                end                                
                            end
                        end                        
                    end
				end
				
				% variables dependientes por escenario
                for escenario = 1:this.iCantEscenarios
                    % cálculo de decisión de expansión acumulada por proyecto
                    indice_desde = this.pAdmProy.ProyTransmision(proy).entrega_varopt_expansion('Decision', escenario);
                    indice_desde_acumulado = this.pAdmProy.ProyTransmision(proy).entrega_varopt_expansion('Acumulada', escenario);
                    indice_base_proy_por_escenario(escenario) = indice_desde; % para restricciones de proyectos entre escenarios
                    for etapa = cant_etapas_comunes+1:this.iCantEtapas
                        this.iIndiceEq = this.iIndiceEq + 1;
						indice_actual = indice_desde + etapa - cant_etapas_comunes - 1;
                        indice_acumulado_actual = indice_desde_acumulado + etapa -cant_etapas_comunes - 1;
                        
                        this.agrega_valores_matriz_igualdad(1,this.iIndiceEq, indice_actual,-1);
						this.agrega_valores_matriz_igualdad(1,this.iIndiceEq, indice_acumulado_actual,1);
                        
						if etapa == cant_etapas_comunes + 1
							if cant_etapas_comunes > 0
								% agrega indice acumulado final de etapa común
								indice_acumulado_anterior = indice_comun_acumulado_desde + cant_etapas_comunes - 1;
								this.agrega_valores_matriz_igualdad(1,this.iIndiceEq, indice_acumulado_anterior,-1);
							end
						else
							this.agrega_valores_matriz_igualdad(1,this.iIndiceEq, indice_actual-1,-1);
                        end
						
                        this.beq(this.iIndiceEq,1) = 0;
                        this.TipoRestriccionEq(this.iIndiceEq) = 1;
                        this.EscenarioRestriccionEq(this.iIndiceEq) = escenario;
                        this.EtapaRestriccionEq(this.iIndiceEq) = etapa;
                        this.SubetapaRestriccionEq(this.iIndiceEq) = 0;
                        
                        if this.iNivelDebug > 1
                            indice_proy = this.pAdmProy.ProyTransmision(proy).Indice;
                            this.NombreEq{this.iIndiceEq} = strcat('req_', num2str(this.iIndiceEq), '_acumulado_', 'P', num2str(indice_proy), '_S', num2str(escenario));
                        end
                    end
                
                    % restricciones de dependencia
                    if this.pAdmProy.ProyTransmision(proy).TieneDependencia
                        for etapa = cant_etapas_comunes+1:this.iCantEtapas
                            this.iIndiceIneq = this.iIndiceIneq + 1;

                            %indice_proy = indice_desde + etapa - 1;
                            indice_proy = indice_desde_acumulado + etapa - cant_etapas_comunes - 1;
                            %this.Aineq(this.iIndiceIneq,indice_proy) = 1;
                            this.agrega_valores_matriz_desigualdad(1,this.iIndiceIneq, indice_proy,1);
                            
                            this.bineq(this.iIndiceIneq,1) = 0;
                            this.TipoRestriccionIneq(this.iIndiceIneq) = 1;
                            this.EscenarioRestriccionIneq(this.iIndiceIneq) = escenario;
                            this.EtapaRestriccionIneq(this.iIndiceIneq) = etapa;
                            this.SubetapaRestriccionIneq(this.iIndiceIneq) = 0;
                            
                            dependencias = this.pAdmProy.ProyTransmision(proy).ProyectoDependiente;
                            for dep = 1:length(dependencias)
                                indice_dependencia = dependencias(dep).entrega_varopt_expansion('Acumulada',escenario) + etapa - cant_etapas_comunes - 1;
                                this.agrega_valores_matriz_desigualdad(1,this.iIndiceIneq, indice_dependencia,-1);
                            end
                            
                            if this.iNivelDebug > 1
                                proy_id = this.pAdmProy.ProyTransmision(proy).entrega_indice();
                                this.NombreIneq{this.iIndiceIneq} = strcat('rineq_', num2str(this.iIndiceIneq), ...
                                    '_dependencias_', 'P', num2str(proy_id), '_E', num2str(etapa), '_S', num2str(escenario));
                            end
                        end
                    end
                    
                    %restricciones de conectividad
                    if this.pAdmProy.ProyTransmision(proy).TieneRequisitosConectividad
                        cantidad = this.pAdmProy.ProyTransmision(proy).entrega_cantidad_grupos_conectividad();
                        for etapa = cant_etapas_comunes+1:this.iCantEtapas
                            %indice_proy = indice_desde + etapa - 1;
                            indice_proy = indice_desde_acumulado + etapa - cant_etapas_comunes - 1;
                            
                            for no_grupo = 1:cantidad
                                this.iIndiceIneq = this.iIndiceIneq + 1;
                                %this.Aineq(this.iIndiceIneq,indice_proy) = 1;
                                this.agrega_valores_matriz_desigualdad(1,this.iIndiceIneq, indice_proy,1);
                                this.bineq(this.iIndiceIneq,1) = 0;
                                this.TipoRestriccionIneq(this.iIndiceIneq) = 1;
                                this.EscenarioRestriccionIneq(this.iIndiceIneq) = escenario;
                                this.EtapaRestriccionIneq(this.iIndiceIneq) = etapa;
                                this.SubetapaRestriccionIneq(this.iIndiceIneq) = 0;
                                
                                proy_con = this.pAdmProy.ProyTransmision(proy).entrega_grupo_proyectos_conectividad(no_grupo);
                                for ii = 1:length(proy_con)
                                    %indice_con_base = proy_con(ii).entrega_varopt_expansion('Decision',escenario);
                                    %indice_con_hasta = indice_con_base + etapa - 1;
                                    %this.Aineq(this.iIndiceIneq,indice_con_base:indice_con_hasta) = -1;
                                    indice_con = proy_con(ii).entrega_varopt_expansion('Acumulada',escenario) + etapa - cant_etapas_comunes - 1;
                                    %this.Aineq(this.iIndiceIneq,indice_con) = -1;
                                    this.agrega_valores_matriz_desigualdad(1,this.iIndiceIneq, indice_con,-1);
                                    
                                    % agrega relaciones con proyectos de conectividad en caso de que proyecto no tenga cantidad de etapas comunes
                                    if etapa == 1
                                        id_proy_con = proy_con(ii).entrega_indice();
                                        pos_proy_conect = find(ProyConectividad == id_proy_con);
                                        if isempty(pos_proy_conect)
                                            cant_proy_conectividad = cant_proy_conectividad + 1;
                                            ProyConectividad(cant_proy_conectividad) = id_proy_con;
                                            RelProyConectProyPrimarios(cant_proy_conectividad).ProyPrimario = proy;
                                        else
                                            RelProyConectProyPrimarios(pos_proy_conect).ProyPrimario = [RelProyConectProyPrimarios(pos_proy_conect).ProyPrimario proy];
                                        end
                                    end
                                end
                                if this.iNivelDebug > 1
                                    proy_id = this.pAdmProy.ProyTransmision(proy).entrega_indice();
                                    this.NombreIneq{this.iIndiceIneq} = strcat('rineq_', num2str(this.iIndiceIneq), ...
                                        '_conectividad_', 'P', num2str(proy_id), '_grupo_', num2str(no_grupo), '_E', num2str(etapa), '_S', num2str(escenario));
                                end                                
                            end
                        end                        
                    end
                end                
            end

            if this.iNivelDebug > 1
                fprintf('%s %s\n',' ', [num2str(100) '%']);
                disp('   restricciones adicionales proyectos de conectividad');
            end
            for i = 1:cant_proy_conectividad
                id_proy_con = ProyConectividad(i);
                proy_con = this.pAdmProy.ProyTransmision(id_proy_con);
				if cant_etapas_comunes > 0
                    indice_ineq_desde = this.iIndiceIneq + 1;
                    indice_ineq_hasta = indice_ineq_desde + cant_etapas_comunes - 1;
                    this.iIndiceIneq = indice_ineq_hasta;
				
                    indice_proy_con_desde = proy_con.entrega_varopt_expansion_comun('Acumulada');
                    indice_proy_con_hasta = indice_proy_con_desde + cant_etapas_comunes - 1;

                    this.agrega_valores_matriz_desigualdad(cant_etapas_comunes,indice_ineq_desde:indice_ineq_hasta, indice_proy_con_desde:indice_proy_con_hasta,1);
                    this.bineq(indice_ineq_desde:indice_ineq_hasta) = 0;

                    this.TipoRestriccionIneq(indice_ineq_desde:indice_ineq_hasta) = 1;
                    this.EscenarioRestriccionIneq(indice_ineq_desde:indice_ineq_hasta) = 0;
                    this.EtapaRestriccionIneq(indice_ineq_desde:indice_ineq_hasta) = 1:1:cant_etapas_comunes;
                    this.SubetapaRestriccionIneq(indice_ineq_desde:indice_ineq_hasta) = 0;

                    for j = 1:length(RelProyConectProyPrimarios(i).ProyPrimario)
                        proy_ppal = this.pAdmProy.ProyTransmision(RelProyConectProyPrimarios(i).ProyPrimario(j));
                        indice_proy_ppal_desde = proy_ppal.entrega_varopt_expansion_comun('Acumulada');
                        indice_proy_ppal_hasta = indice_proy_ppal_desde + cant_etapas_comunes - 1;

                        %this.Aineq(indice_ineq_desde:indice_ineq_hasta,indice_proy_ppal_desde:indice_proy_ppal_hasta) = -diag(ones(this.iCantEtapas,1));
                        this.agrega_valores_matriz_desigualdad(cant_etapas_comunes,indice_ineq_desde:indice_ineq_hasta, indice_proy_ppal_desde:indice_proy_ppal_hasta,-1);
                    end
            
                    if this.iNivelDebug > 1
                        etapa = (1:1:cant_etapas_comunes)';
                        indices = (indice_ineq_desde:1:indice_ineq_desde+cant_etapas_comunes-1)';
                        nombre = strcat('rineq_', num2str(indices), '_lim_inf_proy_con_', 'P', num2str(id_proy_con), '_S0', '_E', num2str(etapa,'%02d'));
                        this.NombreIneq(indices') = cellstr(nombre);
                    end
				end
				
                for escenario = 1:this.iCantEscenarios
                    indice_ineq_desde = this.iIndiceIneq + 1;
                    indice_ineq_hasta = indice_ineq_desde + this.iCantEtapas - cant_etapas_comunes - 1;
                    this.iIndiceIneq = indice_ineq_hasta;
                    
                    indice_proy_con_desde = proy_con.entrega_varopt_expansion('Acumulada',escenario);
                    indice_proy_con_hasta = indice_proy_con_desde + this.iCantEtapas - cant_etapas_comunes - 1;
                    
                    this.agrega_valores_matriz_desigualdad(this.iCantEtapas-cant_etapas_comunes,indice_ineq_desde:indice_ineq_hasta, indice_proy_con_desde:indice_proy_con_hasta,1);
                    this.bineq(indice_ineq_desde:indice_ineq_hasta) = 0;

                    this.TipoRestriccionIneq(indice_ineq_desde:indice_ineq_hasta) = 1;
                    this.EscenarioRestriccionIneq(indice_ineq_desde:indice_ineq_hasta) = escenario;
                    this.EtapaRestriccionIneq(indice_ineq_desde:indice_ineq_hasta) = cant_etapas_comunes+1:1:this.iCantEtapas;
                    this.SubetapaRestriccionIneq(indice_ineq_desde:indice_ineq_hasta) = 0;
                    
                    for j = 1:length(RelProyConectProyPrimarios(i).ProyPrimario)
                        proy_ppal = this.pAdmProy.ProyTransmision(RelProyConectProyPrimarios(i).ProyPrimario(j));
                        indice_proy_ppal_desde = proy_ppal.entrega_varopt_expansion('Acumulada',escenario);
                        indice_proy_ppal_hasta = indice_proy_ppal_desde + this.iCantEtapas - cant_etapas_comunes - 1;

                        %this.Aineq(indice_ineq_desde:indice_ineq_hasta,indice_proy_ppal_desde:indice_proy_ppal_hasta) = -diag(ones(this.iCantEtapas,1));
                        this.agrega_valores_matriz_desigualdad(this.iCantEtapas-cant_etapas_comunes,indice_ineq_desde:indice_ineq_hasta, indice_proy_ppal_desde:indice_proy_ppal_hasta,-1);
                        
                    end
            
                    if this.iNivelDebug > 1
                        etapa = (cant_etapas_comunes+1:1:this.iCantEtapas)';
                        indices = (indice_ineq_desde:1:indice_ineq_desde+this.iCantEtapas-cant_etapas_comunes-1)';
                        nombre = strcat('rineq_', num2str(indices), '_lim_inf_proy_con_', 'P', num2str(id_proy_con), '_S', num2str(escenario), '_E', num2str(etapa,'%02d'));
                        this.NombreIneq(indices') = cellstr(nombre);
                    end
                end
            end
            
            if this.iNivelDebug > 1
                fprintf('%s %s\n',' ', [num2str(100) '%']);
                disp('   restricciones de proyectos obligatorios');
            end
            % restricciones de proyectos obligatorios. Cada set de
            % proyectos obligatorio se debe construir en la primera etapa
            contador = 0;
            for i = 1:length(this.pAdmProy.ProyTransmisionObligatorios)
                if this.iNivelDebug > 1
                    porcentaje = i/length(this.pAdmProy.ProyTransmisionObligatorios)*100;
                    if porcentaje > contador
                        while contador + 10 < porcentaje
                            contador = contador + 10;
                        end
                        fprintf('%s %s',' ', [num2str(contador) '%']);
                        pause(0.1);
                        contador = contador + 10;
                    end
                end
                %for escenario = 1:this.iCantEscenarios
                    % una restricción por cada set de proyectos obligatorios
					% TODO POR AHORA PROYECTOS OBLIGATORIOS SOLO EN ETAPA 1
                    this.iIndiceIneq = this.iIndiceIneq + 1;

                    for j = 1:length(this.pAdmProy.ProyTransmisionObligatorios(i).Proyectos)
                        indice_proy = this.pAdmProy.ProyTransmisionObligatorios(i).Proyectos(j).entrega_varopt_expansion_comun('Acumulada');
                        proy_id = this.pAdmProy.ProyTransmisionObligatorios(i).Proyectos(j).entrega_indice();

                        %this.Aineq(this.iIndiceIneq,indice_proy) = -1;
                        this.agrega_valores_matriz_desigualdad(1,this.iIndiceIneq, indice_proy,-1);
                    end

                    this.bineq(this.iIndiceIneq,1) = -1;
                    this.TipoRestriccionIneq(this.iIndiceIneq) = 1;
                    this.EscenarioRestriccionIneq(this.iIndiceIneq) = 0;
                    this.EtapaRestriccionIneq(this.iIndiceIneq) = 0;
                    this.SubetapaRestriccionIneq(this.iIndiceIneq) = 0;
                    
                    if this.iNivelDebug > 1
                        this.NombreIneq{this.iIndiceIneq} = strcat('rineq_', num2str(this.iIndiceIneq), '_oblig_exp_P', num2str(proy_id), '_E', num2str(1), '_S0'); % solo para la primera etapa
                    end
                %end
            end
            
            if this.iNivelDebug > 1
                fprintf('%s %s\n',' ', [num2str(100) '%']);
                disp('   restricciones de proyectos excluyentes');
            end
            
            % proyectos excluyentes. Por cada grupo, se pueden construir solo una vez
            contador = 0;
            for indice = 1:length(this.pAdmProy.ProyTransmisionExcluyentes)
                if this.iNivelDebug > 1
                    porcentaje = indice/length(this.pAdmProy.ProyTransmisionExcluyentes)*100;
                    if porcentaje > contador
                        while contador + 10 < porcentaje
                            contador = contador + 10;
                        end
                        fprintf('%s %s',' ', [num2str(contador) '%']);
                        pause(0.1);
                        contador = contador + 10;
                    end
                end

                % una restricción por cada set de proyectos excluyentes por escenario
                for escenario = 1:this.iCantEscenarios
                    this.iIndiceIneq = this.iIndiceIneq + 1;
                    for proy = 1:length(this.pAdmProy.ProyTransmisionExcluyentes(indice).Proyectos)
                        id_proy = this.pAdmProy.ProyTransmisionExcluyentes(indice).Proyectos(proy);
                        indice_proy = this.pAdmProy.entrega_proyecto(id_proy).entrega_varopt_expansion('Acumulada', escenario)+ this.iCantEtapas - 1;
                        this.agrega_valores_matriz_desigualdad(1,this.iIndiceIneq, indice_proy,1);
                        %indice_proy_desde = this.pAdmProy.entrega_proyecto(id_proy).entrega_varopt_expansion('Decision', escenario);
                        %indice_proy_hasta = indice_proy_desde + this.iCantEtapas - 1;
                        %this.Aineq(this.iIndiceIneq,indice_proy_desde:indice_proy_hasta) = 1;
                        %this.agrega_valores_matriz_desigualdad(this.iCantEtapas,this.iIndiceIneq, indice_proy_desde:indice_proy_hasta,1);
                        
                    end
                    
                    this.bineq(this.iIndiceIneq,1) = 1;
                    this.TipoRestriccionIneq(this.iIndiceIneq) = 1;
                    this.EscenarioRestriccionIneq(this.iIndiceIneq) = escenario;
                    this.EtapaRestriccionIneq(this.iIndiceIneq) = 0;
                    this.SubetapaRestriccionIneq(this.iIndiceIneq) = 0;
                    if this.iNivelDebug > 1 
                        this.NombreIneq{this.iIndiceIneq} = strcat('rineq_', num2str(this.iIndiceIneq), '_proy_excl_', num2str(indice), '_S', num2str(escenario));
                    end                    
                end
            end
            
            if this.iNivelDebug > 1
                fprintf('%s %s\n',' ', [num2str(100) '%']);
            end
        end
        
        function escribe_relaciones_proyectos_costos(this)
            if this.iNivelDebug > 1
                disp('   relaciones proyectos costos');
                prot = cProtocolo.getInstance;
                prot.imprime_texto('\nCosto de proyectos (sin valor residual para cc):');
                texto = sprintf('%-5s %-7s %-50s %-15s %-50s', 'Id', 'Tipo', 'Codigo', 'Costo mio. USD', 'Nombre');
                prot.imprime_texto(texto);
            end
            
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            contador = 0;
            for proy = 1:length(this.pAdmProy.ProyTransmision)
                if this.iNivelDebug > 1
                    porcentaje = proy/length(this.pAdmProy.ProyTransmision)*100;
                    if porcentaje > contador
                        while contador + 10 < porcentaje
                            contador = contador + 10;
                        end
                        fprintf('%s %s',' ', [num2str(contador) '%']);
                        pause(0.1);
                        contador = contador + 10;
                    end
                end
                for escenario = 1:this.iCantEscenarios
                    indice_eq_desde = this.iIndiceEq + 1;
                    indice_eq_hasta = indice_eq_desde + this.iCantEtapas - 1;
                    this.iIndiceEq = indice_eq_hasta;
                    
                    indice_exp_desde = this.pAdmProy.ProyTransmision(proy).entrega_varopt_expansion('Decision', escenario);
                    indice_exp_hasta = indice_exp_desde + this.iCantEtapas - 1;
                    
                    indice_costo_desde = this.pAdmProy.ProyTransmision(proy).entrega_varopt_expansion('Costo', escenario);
                    indice_costo_hasta = indice_costo_desde + this.iCantEtapas - 1;
                    
                    %this.Aeq(indice_eq_desde:indice_eq_hasta,indice_costo_desde:indice_costo_hasta) = -1*diag(ones(this.iCantEtapas,1));
                    this.agrega_valores_matriz_igualdad(this.iCantEtapas,indice_eq_desde:indice_eq_hasta, indice_costo_desde:indice_costo_hasta,-1);

                    costo_inversion = this.pAdmProy.ProyTransmision(proy).entrega_costos_inversion();
                    factor_desarrollo = this.pParOpt.entrega_factor_costo_desarrollo_proyectos();
                    costo_inversion = round(costo_inversion*factor_desarrollo,dec_redondeo);
                    
                    %this.Aeq(indice_eq_desde:indice_eq_hasta,indice_exp_desde:indice_exp_hasta) = costo_inversion*diag(ones(this.iCantEtapas,1));
                    this.agrega_valores_matriz_igualdad(this.iCantEtapas,indice_eq_desde:indice_eq_hasta, indice_exp_desde:indice_exp_hasta,costo_inversion);

                    this.beq(indice_eq_desde:indice_eq_hasta,1) = 0;
                    this.TipoRestriccionEq(indice_eq_desde:indice_eq_hasta) = 1;
                    this.EscenarioRestriccionEq(indice_eq_desde:indice_eq_hasta) = escenario;
                    this.EtapaRestriccionEq(indice_eq_desde:indice_eq_hasta) = 1:1:this.iCantEtapas;
                    this.SubetapaRestriccionEq(indice_eq_desde:indice_eq_hasta) = 0;
                    
                    % se descuenta la vida útil de elementos en caso de que
                    % estos sean removidos de la red
                    for id_el_red = 1:length(this.pAdmProy.ProyTransmision(proy).Elemento)
                        if strcmp(this.pAdmProy.ProyTransmision(proy).Accion{id_el_red}, 'R')
                            if strcmp(this.pAdmProy.ProyTransmision(proy).entrega_tipo_proyecto(), 'CS') || ...
                               (strcmp(this.pAdmProy.ProyTransmision(proy).entrega_tipo_proyecto(), 'AV') && ...
                               ~this.pAdmProy.ProyTransmision(proy).cambio_conductor_aumento_voltaje())
                                continue;
                            end
                            % costos de remover elemento de red                        
                            % elemento se busca en proyectos dependientes
                            % que lo agreguen. Esto se hace en forma
                            % iterativa por cada proyecto dependiente,
                            % hasta llegar a elemento existente (si existe)
                            costo_elemento = this.pAdmProy.ProyTransmision(proy).Elemento(id_el_red).entrega_costo_conductor();                            
                            vida_util = this.pAdmProy.ProyTransmision(proy).Elemento(id_el_red).entrega_vida_util();
                            proyectos_dependientes = this.pAdmProy.ProyTransmision(proy).entrega_dependencias_elemento_a_remover(this.pAdmProy.ProyTransmision(proy).Elemento(id_el_red));
                            if ~isempty(proyectos_dependientes)
                                for dep = 1:length(proyectos_dependientes)
                                    for etapa = 1:this.iCantEtapas
                                        indice_exp = indice_exp_desde + etapa-1;
                                        for etapa_previa = 1:etapa
                                            indice_proy_dep_base = proyectos_dependientes(dep).entrega_varopt_expansion('Decision', escenario);
                                            indice_proy_dep = indice_proy_dep_base + etapa_previa - 1;
                                            indice_aux = this.VarAux(indice_exp, indice_proy_dep);
                                            valor_residual = round(costo_elemento*(1-(etapa-etapa_previa)/vida_util),dec_redondeo);

                                            indice_eq_etapa = indice_eq_desde + etapa - 1;
                                            %this.Aeq(indice_eq_etapa,indice_aux) = this.Aeq(indice_eq_etapa,indice_aux) -valor_residual;
                                            this.agrega_valores_matriz_igualdad(1,indice_eq_etapa, indice_aux,-valor_residual);
                                        end
                                    end
                                end
                            else
                                % elemento de red existe en red inicial. Se
                                % obtiene valor residual
                                if ~this.pSEP.existe_elemento(this.pAdmProy.ProyTransmision(proy).Elemento(id_el_red)) && ...
                                   ~this.pAdmProy.existe_elemento_red_proyectado(escenario, this.pAdmProy.ProyTransmision(proy).Elemento(id_el_red))
                                    texto = ['Elemento base en red ' this.pAdmProy.ProyTransmision(proy).Elemento(id_el_red).entrega_nombre()];
                                    texto = [texto ' en proyecto ' this.pAdmProy.ProyTransmision(proy).entrega_indice() ':' this.pAdmProy.ProyTransmision(proy).entrega_nombre()];
                                    texto = [texto ' no fue encontrado'];
                                    error = MException('cOptMILP:escribe_relaciones_proyectos_costos', texto);
                                    throw(error)
                                end
                                anio_construccion = this.pAdmProy.ProyTransmision(proy).Elemento(id_el_red).entrega_anio_construccion();
                                for etapa = 1:this.iCantEtapas
                                    d_etapa = this.pParOpt.TInicio - anio_construccion + (etapa-1)*this.pParOpt.DeltaEtapa;
                                    valor_residual = round(costo_elemento*(1-d_etapa/vida_util),dec_redondeo);
                                    if valor_residual < 0
                                        valor_residual = 0;
                                    end
                                    % se resta valor al costo de agregar
                                    % elemento
                                    indice_eq_etapa = indice_eq_desde + etapa - 1;
                                    indice_exp = indice_exp_desde + etapa - 1;
                                    %this.Aeq(indice_eq_etapa,indice_exp) = this.Aeq(indice_eq_etapa,indice_exp) - valor_residual;
                                    this.agrega_valores_matriz_igualdad(1,indice_eq_etapa, indice_exp,-valor_residual);
                                end
                            end
                        end
                    end
                    
                    if this.iNivelDebug > 1
                        indice_proy = this.pAdmProy.ProyTransmision(proy).Indice;
                        for etapa = 1:this.iCantEtapas
                            indice_varopt = indice_costo_desde + etapa - 1;
                            codigo = this.NombreVariables{indice_varopt};
                            tipo_proyecto = this.pAdmProy.ProyTransmision(proy).entrega_tipo_proyecto();
                            nombre_proyecto = this.pAdmProy.ProyTransmision(proy).entrega_nombre();
                            indice_eq = indice_eq_desde + etapa - 1;
                            this.NombreEq{indice_eq} = strcat('req_', num2str(indice_eq), '_rel_proy_costos_', 'P', num2str(indice_proy), '_E', num2str(etapa), '_S', num2str(escenario));
                            texto = sprintf('%-5s %-7s %-50s %-15s %-50s', num2str(indice_proy),...
                                tipo_proyecto, ...
                                codigo, ...
                                num2str(costo_inversion), ...
                                nombre_proyecto);
                            prot.imprime_texto(texto);
                        end
                    end
                end
            end
            if this.iNivelDebug > 1
                fprintf('%s %s\n',' ', [num2str(100) '%']);
                prot.imprime_texto('\n');
            end
            
        end

        function escribe_restricciones_variables_auxiliares(this)
            [pi, pd, aux] = find(this.VarAux);
            contador = 10;
            for id = 1:length(pi)
                porcentaje = round(id/length(pi)*100,0);
                if porcentaje > contador
                    while contador + 10 < porcentaje
                    	contador = contador + 10;
                    end
                    fprintf('%s %s',' ', [num2str(contador) '%']);
                    pause(0.1);
                    contador = contador + 10;
                end
                
                indice_exp = pi(id);
                indice_proy_dep = pd(id);
                indice_aux = aux(id);
                    
                this.iIndiceIneq = this.iIndiceIneq + 1;

                %this.Aineq(this.iIndiceIneq,indice_aux) = 1;
                this.agrega_valores_matriz_desigualdad(1,this.iIndiceIneq,indice_aux,1);

                %this.Aineq(this.iIndiceIneq,indice_exp) = -1;
                this.agrega_valores_matriz_desigualdad(1,this.iIndiceIneq,indice_exp,-1);
                this.bineq(this.iIndiceIneq,1) = 0;
                this.TipoRestriccionIneq(this.iIndiceIneq) = 1;
                this.EscenarioRestriccionIneq(this.iIndiceIneq) = 0;
                this.EtapaRestriccionIneq(this.iIndiceIneq) = 0;
                this.SubetapaRestriccionIneq(this.iIndiceIneq) = 0;
                
                this.iIndiceIneq = this.iIndiceIneq + 1;

                %this.Aineq(this.iIndiceIneq,indice_aux) = 1;
                this.agrega_valores_matriz_desigualdad(1,this.iIndiceIneq,indice_aux,1);

                %this.Aineq(this.iIndiceIneq,indice_proy_dep) = -1;
                this.agrega_valores_matriz_desigualdad(1,this.iIndiceIneq,indice_proy_dep,-1);
                
                this.bineq(this.iIndiceIneq,1) = 0;
                this.TipoRestriccionIneq(this.iIndiceIneq) = 1;
                this.EscenarioRestriccionIneq(this.iIndiceIneq) = 0;
                this.EtapaRestriccionIneq(this.iIndiceIneq) = 0;
                this.SubetapaRestriccionIneq(this.iIndiceIneq) = 0;
                this.iIndiceIneq = this.iIndiceIneq + 1;

                %this.Aineq(this.iIndiceIneq,indice_aux) = -1;
                this.agrega_valores_matriz_desigualdad(1,this.iIndiceIneq,indice_aux,-1);

                %this.Aineq(this.iIndiceIneq,indice_exp) = 1;
                this.agrega_valores_matriz_desigualdad(1,this.iIndiceIneq,indice_exp,1);

                %this.Aineq(this.iIndiceIneq,indice_proy_dep) = 1;
                this.agrega_valores_matriz_desigualdad(1,this.iIndiceIneq,indice_proy_dep,1);

                this.bineq(this.iIndiceIneq,1) = 1;
                this.TipoRestriccionIneq(this.iIndiceIneq) = 1;
                this.EscenarioRestriccionIneq(this.iIndiceIneq) = 0;
                this.EtapaRestriccionIneq(this.iIndiceIneq) = 0;
                this.SubetapaRestriccionIneq(this.iIndiceIneq) = 0;
                
                %Nombres
                if this.iNivelDebug > 1 
                	nombre_varaux = this.NombreVariables{indice_aux};
                    nombre = strcat('rineq_', num2str(this.iIndiceIneq-2),...
                                    '_limaux1_', nombre_varaux);
                    this.NombreIneq{this.iIndiceIneq-2} = nombre;

                    nombre = strcat('rineq_', num2str(this.iIndiceIneq-1),...
                                    '_limaux2_', nombre_varaux);
                    this.NombreIneq{this.iIndiceIneq-1} = nombre;

                    nombre = strcat('rineq_', num2str(this.iIndiceIneq),...
                                    '_limaux3_', nombre_varaux);
                    this.NombreIneq{this.iIndiceIneq} = nombre;
                end
            end
            if this.iNivelDebug > 1
                fprintf('%s %s\n',' ', [num2str(100) '%']);
            end            
        end
        
        function escribe_restricciones_operacion(this)
            for escenario = 1:this.iCantEscenarios
                for etapa = 1:this.iCantEtapas
                    disp(['escribe restricciones operación escenario ' num2str(escenario) ' en etapa ' num2str(etapa)]);

                    %disp('   balance energía');
                    this.escribe_balance_energia(escenario, etapa);
                    
                    %disp('   límites operacionales líneas trafos');
                    this.escribe_limites_operacionales_lineas_trafos(escenario, etapa);

                    %disp('   limites operacionales baterias')
                    this.escribe_limites_operacionales_baterias(escenario, etapa);
                    
                    %disp('   restricciones flujos ángulos');
                    this.escribe_restricciones_flujos_angulos(escenario, etapa);

                    %disp('   restricciones ángulos se proyectadas');
%                    if this.pParOpt.EstrategiaAngulosSENuevas == 0
%                        this.escribe_restricciones_angulos_se_proyectadas_theta_ady(escenario, etapa);
%                    elseif this.pParOpt.EstrategiaAngulosSENuevas == 1
%                        this.escribe_restricciones_angulos_se_proyectadas_theta_max(escenario, etapa);
%                    end
                end
            end
        end

        function escribe_balance_energia(this, escenario, etapa)
            this.escribe_balance_energia_se_existentes(escenario, etapa);
            this.escribe_balance_energia_se_proyectadas(escenario, etapa);
            if this.bConsideraDependenciaTemporal
                this.escribe_balance_energia_baterias(escenario, etapa);
            end
        end

        function escribe_balance_energia_baterias(this, escenario, etapa)
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            cant_po = this.iCantPuntosOperacion;
            [cant_periodos_representativos, ~] = size(this.vIndicesPOConsecutivos);
            
            el_red = this.pAdmProy.entrega_baterias();
            for i = 1:length(el_red)
                if isa(el_red, 'cBateria')
                    indice_eq_desde = this.iIndiceEq + 1;
                    indice_eq_hasta = indice_eq_desde + this.iCantPuntosOperacion - 1;
                    this.iIndiceEq = indice_eq_hasta;

                    % Por ahora no se diferencia entre eta carga/descarga ni eta almacenamiento
                    eta_carga = el_red(i).entrega_eficiencia_carga();
                    eta_descarga = el_red(i).entrega_eficiencia_descarga();
                    
                    indice_e_desde = el_red(i).entrega_varopt_operacion('E', escenario, etapa);                
                    indice_p_descarga_desde = el_red(i).entrega_varopt_operacion('Pdescarga', escenario, etapa);
                    indice_p_carga_desde = el_red(i).entrega_varopt_operacion('Pcarga', escenario, etapa);

                    % forma las ecuaciones extendidas y luego borra las filas que no corresponden
                    %this.Aeq(indice_eq_desde:indice_eq_hasta,indice_e_desde:indice_e_hasta) = diag(ones(cant_po,1)); % E(t)
                    %this.Aeq(indice_eq_desde:indice_eq_hasta,indice_e_desde-1:indice_e_hasta-1) = this.Aeq(indice_eq_desde:indice_eq_hasta,indice_e_desde-1:indice_e_hasta-1) - diag(ones(cant_po,1)); % -E(t-1)
                    %this.Aeq(indice_eq_desde:indice_eq_hasta,indice_p_descarga_desde-1:indice_p_descarga_hasta-1) = round(1/eta_descarga, dec_redondeo)*diag(ones(cant_po,1)); % +Pdescarga(t-1)
                    %this.Aeq(indice_eq_desde:indice_eq_hasta,indice_p_carga_desde-1:indice_p_carga_hasta-1) = round(-eta_carga, dec_redondeo)*diag(ones(cant_po,1)); % -Pcarga(t-1)
                    %indices_a_corregir = indice_eq_desde -1 + this.vIndicesPOConsecutivos(:,1);
                    cant_acumulada = 0;
                    for periodo = 1:cant_periodos_representativos
                        ancho_periodo = this.vIndicesPOConsecutivos(periodo,2)-this.vIndicesPOConsecutivos(periodo,1)+1;
                        indice_eq_desde_periodo = indice_eq_desde + cant_acumulada;
                        indice_eq_hasta_periodo = indice_eq_desde_periodo + ancho_periodo -  1;
                        cant_acumulada = cant_acumulada + ancho_periodo;
                        
                        indice_e_desde_periodo = indice_e_desde + this.vIndicesPOConsecutivos(periodo,1)-1;
                        indice_e_hasta_periodo = indice_e_desde + this.vIndicesPOConsecutivos(periodo,2)-1;
                        indice_p_descarga_desde_periodo = indice_p_descarga_desde + this.vIndicesPOConsecutivos(periodo,1)-1;
                        indice_p_descarga_hasta_periodo = indice_p_descarga_desde + this.vIndicesPOConsecutivos(periodo,2)-1;
                        indice_p_carga_desde_periodo = indice_p_carga_desde + this.vIndicesPOConsecutivos(periodo,1)-1;
                        indice_p_carga_hasta_periodo = indice_p_carga_desde + this.vIndicesPOConsecutivos(periodo,2)-1;

                        this.agrega_valores_matriz_igualdad(ancho_periodo,indice_eq_desde_periodo:indice_eq_hasta_periodo,indice_e_desde_periodo:indice_e_hasta_periodo,1); % E(t)
                        this.agrega_valores_matriz_igualdad(ancho_periodo-1,indice_eq_desde_periodo+1:indice_eq_hasta_periodo,indice_e_desde_periodo:indice_e_hasta_periodo-1,-1); % -E(t-1)
                        this.agrega_valores_matriz_igualdad(ancho_periodo-1,indice_eq_desde_periodo+1:indice_eq_hasta_periodo,indice_p_descarga_desde_periodo:indice_p_descarga_hasta_periodo-1,round(1/eta_descarga, dec_redondeo)); % +Pdescarga(t-1)
                        this.agrega_valores_matriz_igualdad(ancho_periodo-1,indice_eq_desde_periodo+1:indice_eq_hasta_periodo,indice_p_carga_desde_periodo:indice_p_carga_hasta_periodo-1,round(-eta_carga, dec_redondeo)); % -Pcarga(t-1)
                        this.agrega_valores_matriz_igualdad(1,indice_eq_desde_periodo,indice_e_hasta_periodo,-1); % -E(t_fin)
                        
%                         this.Aeq(indices_a_corregir(periodo), indice_e_desde_periodo-1) = 0;
%                         this.Aeq(indices_a_corregir(periodo), indice_p_descarga_desde_periodo-1) = 0;
%                         this.Aeq(indices_a_corregir(periodo), indice_p_carga_desde_periodo-1) = 0;
%                         this.Aeq(indices_a_corregir(periodo), indice_e_hasta_periodo) = -1;
                    end

                    this.beq(indice_eq_desde:indice_eq_hasta) = 0;
                    this.TipoRestriccionEq(indice_eq_desde:indice_eq_hasta) = 2;
                    this.EscenarioRestriccionEq(indice_eq_desde:indice_eq_hasta) = escenario;
                    this.EtapaRestriccionEq(indice_eq_desde:indice_eq_hasta) = etapa;
                    this.SubetapaRestriccionEq(indice_eq_desde:indice_eq_hasta) = this.RelSubetapasPO;
                    if this.iNivelDebug > 1
                        id_bat = el_red(i).entrega_id();
                        oper = (1:1:this.iCantPuntosOperacion)';
                        indices = (indice_eq_desde:1:indice_eq_desde+this.iCantPuntosOperacion-1)';
                        nombre = strcat('req_be_temp_', num2str(indices), '_B', num2str(id_bat), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                        this.NombreEq(indices') = cellstr(nombre);
%                         for punto_operacion = 1:this.iCantPuntosOperacion
%                             indice_eq = indice_eq_desde + punto_operacion - 1;
%                             this.NombreEq{indice_eq} = strcat('req_be_temp_', num2str(indice_eq), '_B', num2str(id_bat), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(punto_operacion));
%                         end
                    end
                    
                else
                    error = MException('cOptMILP:escribe_balance_energia','Por ahora elementos paralelos sólo baterías');
                    throw(error)
                end
            end
        end
        
        function escribe_balance_energia_se_existentes(this, escenario, etapa)
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            cant_po = this.iCantPuntosOperacion;
            
            subestaciones = this.pSEP.Subestaciones;
            se_proyectadas = this.pAdmProy.entrega_subestaciones_proyectadas(escenario);            
            for ii = 1:length(se_proyectadas)
                if se_proyectadas(ii).EtapaEntrada(escenario) <= etapa
                    subestaciones = [subestaciones; se_proyectadas(ii)];
                end
            end
            
            for se = 1:length(subestaciones)
                indice_eq_desde = this.iIndiceEq + 1;
                indice_eq_hasta = indice_eq_desde + cant_po - 1;
                this.iIndiceEq = indice_eq_hasta;
                this.TipoRestriccionEq(indice_eq_desde:indice_eq_hasta) = 2;
                this.EscenarioRestriccionEq(indice_eq_desde:indice_eq_hasta) = escenario;
                this.EtapaRestriccionEq(indice_eq_desde:indice_eq_hasta) = etapa;
                this.SubetapaRestriccionEq(indice_eq_desde:indice_eq_hasta) = this.RelSubetapasPO;

                subestaciones(se).agrega_restriccion_balance_energia_desde(escenario, etapa, indice_eq_desde);
                if this.iNivelDebug > 1
                    id_se = subestaciones(se).entrega_id();
                    oper = (1:1:this.iCantPuntosOperacion)';
                    indices = (indice_eq_desde:1:indice_eq_desde+this.iCantPuntosOperacion-1)';
                    nombre = strcat('req_be_', num2str(indices), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                    this.NombreEq(indices') = cellstr(nombre);
                    
%                     for punto_operacion = 1:this.iCantPuntosOperacion
%                         indice_eq = indice_eq_desde + punto_operacion - 1;
%                         this.NombreEq{indice_eq} = strcat('req_be_', num2str(indice_eq), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(punto_operacion));
%                     end
                end
                
                % generadores despachables
                %generadores existentes
                generadores = [];
                gen_desp = subestaciones(se).entrega_generadores_despachables();
                for ii = 1:length(gen_desp)
                    if gen_desp(ii).entrega_varopt_operacion('P', escenario, etapa) ~= 0
                        generadores = [generadores; gen_desp(ii)];
                    end
                end
                gen_proy = this.pAdmProy.entrega_generadores_despachables_proyectados(escenario);
                for ii = 1:length(gen_proy)
                    if gen_proy(ii).entrega_se == subestaciones(se) && gen_proy(ii).entrega_varopt_operacion('P', escenario, etapa) ~= 0
                        generadores = [generadores; gen_proy(ii)];
                    end
                end
                
                for j = 1:length(generadores)
                    indice_gen_desde = generadores(j).entrega_varopt_operacion('P', escenario, etapa);
                    indice_gen_hasta = indice_gen_desde + this.iCantPuntosOperacion - 1;

                    %this.Aeq(indice_eq_desde:indice_eq_hasta,indice_gen_desde:indice_gen_hasta) = diag(ones(this.iCantPuntosOperacion,1));
                    this.agrega_valores_matriz_igualdad(cant_po,indice_eq_desde:indice_eq_hasta,indice_gen_desde:indice_gen_hasta,1);
                end
                
                % baterias
                baterias = this.pAdmProy.entrega_baterias_por_subestacion(subestaciones(se));
                for j = 1:length(baterias)
                    if isa(baterias(j),'cBateria')
                        indice_bat_descarga_desde = baterias(j).entrega_varopt_operacion('Pdescarga', escenario, etapa);
                        indice_bat_descarga_hasta = indice_bat_descarga_desde + this.iCantPuntosOperacion - 1;
                        indice_bat_carga_desde = baterias(j).entrega_varopt_operacion('Pcarga', escenario, etapa);
                        indice_bat_carga_hasta = indice_bat_carga_desde + this.iCantPuntosOperacion - 1;

                        %this.Aeq(indice_eq_desde:indice_eq_hasta,indice_bat_descarga_desde:indice_bat_descarga_hasta) = diag(ones(this.iCantPuntosOperacion,1));
                        this.agrega_valores_matriz_igualdad(cant_po,indice_eq_desde:indice_eq_hasta,indice_bat_descarga_desde:indice_bat_descarga_hasta,1);

                        %this.Aeq(indice_eq_desde:indice_eq_hasta,indice_bat_carga_desde:indice_bat_carga_hasta) = -diag(ones(this.iCantPuntosOperacion,1));
                        this.agrega_valores_matriz_igualdad(cant_po,indice_eq_desde:indice_eq_hasta,indice_bat_carga_desde:indice_bat_carga_hasta,-1);
                    else
                        error = MException('cOptMILP:escribe_balance_energia','Por ahora elementos paralelos sólo baterías');
                        throw(error)
                    end                        
                end
                
                %consumo residual
                consumo_residual = zeros(1, this.iCantPuntosOperacion);
                consumos = [];
                % existentes
                for ii = 1:length(subestaciones(se).Consumos)
                    etapa_salida = subestaciones(se).Consumos(ii).entrega_etapa_salida(escenario);
                    if etapa_salida == 0 || etapa_salida > etapa
                        consumos = [consumos; this.pSEP.Subestaciones(se).Consumos(ii)];
                    end
                end
                % proyectados
                con_proy = this.pAdmProy.entrega_consumos_proyectados(escenario);
                for ii = 1:length(con_proy)
                    if con_proy(ii).EtapaEntrada(escenario) <= etapa && ...
                            con_proy(ii).EtapaSalida(escenario) > etapa && ...
                            con_proy(ii).entrega_se() == subestaciones(se)
                        consumos = [consumos; con_proy(ii)];
                    end
                end
                
                for j = 1:length(consumos)
                    indice_perfil = consumos(j).entrega_indice_adm_escenario_perfil_p();
                    perfil = this.pAdmSc.entrega_perfil_consumo(indice_perfil);
                    indice_capacidad = consumos(j).entrega_indice_adm_escenario_capacidad(escenario);
                    capacidad = this.pAdmSc.entrega_capacidad_consumo(indice_capacidad, etapa);
                    
                    consumo_residual = consumo_residual + capacidad*perfil/sbase;
                end
                
                % se resta la inyección de generadores RES
                % se asume que generadores res no salen de operación
                gen_res = subestaciones(se).entrega_generadores_res;
                gen_proy = this.pAdmProy.entrega_generadores_ernc_proyectados(escenario);
                for ii = 1:length(gen_proy)
                    if gen_proy(ii).entrega_se == subestaciones(se) && gen_proy(ii).EtapaEntrada(escenario) <= etapa
                        gen_res = [gen_res; gen_proy(ii)];
                    end
                end

                for j = 1:length(gen_res)
                    indice_perfil = gen_res(j).entrega_indice_adm_escenario_perfil_ernc();
                    perfil_ernc = this.pAdmSc.entrega_perfil_ernc(indice_perfil);
                    if gen_res(j).entrega_evolucion_capacidad_a_futuro()
                        indice_capacidad = gen_res(j).entrega_indice_adm_escenario_capacidad(escenario);
                        capacidad = this.pAdmSc.entrega_capacidad_generador(indice_capacidad, etapa);
                    else
                        capacidad = gen_res(j).entrega_pmax();
                    end

                    consumo_residual = consumo_residual - capacidad*perfil_ernc/sbase;
                end
                
                this.beq(indice_eq_desde:indice_eq_hasta,1) = round(consumo_residual',dec_redondeo);

                %ENS
                if this.pParOpt.considera_desprendimiento_carga()
                    for j = 1:length(consumos)
                        indice_consumo_desde = consumos(j).entrega_varopt_operacion('P', escenario, etapa);
                        if indice_consumo_desde == 0
                            continue
                        end
                        indice_consumo_hasta = indice_consumo_desde + this.iCantPuntosOperacion - 1;

                        %this.Aeq(indice_eq_desde:indice_eq_hasta,indice_consumo_desde:indice_consumo_hasta) = diag(ones(this.iCantPuntosOperacion,1));
                        this.agrega_valores_matriz_igualdad(cant_po,indice_eq_desde:indice_eq_hasta,indice_consumo_desde:indice_consumo_hasta,1);
                    end
                end
                
                % Recorte RES.
                if this.pParOpt.considera_recorte_res()
                    for j = 1:length(gen_res)
                        indice_generador_desde = gen_res(j).entrega_varopt_operacion('P', escenario, etapa);
                        if indice_generador_desde == 0
                            continue
                        end
                        
                        indice_generador_hasta = indice_generador_desde + this.iCantPuntosOperacion - 1;

                        %this.Aeq(indice_eq_desde:indice_eq_hasta,indice_generador_desde:indice_generador_hasta) = -1*diag(ones(this.iCantPuntosOperacion,1));
                        this.agrega_valores_matriz_igualdad(cant_po,indice_eq_desde:indice_eq_hasta,indice_generador_desde:indice_generador_hasta,-1);
                    end
                end

                %lineas y transformadores existentes y en construcción
                el_serie = subestaciones(se).entrega_lineas();
                el_serie = [el_serie; subestaciones(se).entrega_transformadores2d()];
                el_serie_proy = this.pAdmProy.entrega_elementos_red_proyectados(escenario);
                for ii = 1:length(el_serie_proy)
                    if el_serie_proy(ii).entrega_se1() == se || ...
                            el_serie_proy(ii).entrega_etapa_entrada(escenario) <= etapa
                        el_serie = [el_serie; el_serie_proy(ii)];
                    end
                end
                for j = 1:length(el_serie)
                    [se_1, se_2] = el_serie(j).entrega_subestaciones();
                    indice_elserie_desde = el_serie(j).entrega_varopt_operacion('P', escenario, etapa);
                    indice_elserie_hasta = indice_elserie_desde + this.iCantPuntosOperacion - 1;
                    if se_1 == subestaciones(se)
                        signo = -1; % linea va de SE1 a SE2 por lo que flujo sale de la subestacion
                    elseif se_2 == subestaciones(se)
                        signo = 1;
                    else
                        error = MException('cOptMILP:escribe_balance_energia','Inconsistencia en los datos, ya que línea no pertenece a subestacion');
                        throw(error)
                    end
                    
                    %this.Aeq(indice_eq_desde:indice_eq_hasta,indice_elserie_desde:indice_elserie_hasta) = signo*diag(ones(this.iCantPuntosOperacion,1));
                    this.agrega_valores_matriz_igualdad(cant_po,indice_eq_desde:indice_eq_hasta,indice_elserie_desde:indice_elserie_hasta,signo);
                end
                
                %lineas y transformadores proyectados (var. decisión)
                el_proyectados = this.pAdmProy.entrega_elementos_serie_expansion_por_subestacion(this.pSEP.Subestaciones(se));
                for j = 1:length(el_proyectados)
                    el_red = el_proyectados(j);
                    if isa(el_red, 'cLinea') || isa(el_red, 'cTransformador2D')
                        [se_1, se_2] = el_red.entrega_subestaciones();
                        if se_1 == subestaciones(se)
                            corresponde = true;
                            signo = -1;
                        elseif se_2 == subestaciones(se)
                            corresponde = true;
                            signo = 1;
                        else
                            %redundante, pero para mejor entendimiento del
                            %programa
                            corresponde = false;
                        end
                    
                        if corresponde
                            indice_desde = el_red.entrega_varopt_operacion('P', escenario, etapa);
                            indice_hasta = indice_desde + cant_po - 1;

                            %this.Aeq(indice_eq_desde:indice_eq_hasta,indice_desde:indice_hasta) = signo*diag(ones(this.iCantPuntosOperacion,1));
                            this.agrega_valores_matriz_igualdad(cant_po,indice_eq_desde:indice_eq_hasta,indice_desde:indice_hasta,signo);
                        end
                    end
                end
            end
        end
        
        function escribe_restricciones_angulos_se_proyectadas_theta_max(this, escenario, etapa)
            % es necesario, ya que si no el ángulo queda "flotando" en caso
            % de que la subestación no se construya
            % balance energía subestaciones proyectadas
            nuevos_buses = this.pAdmProy.entrega_subestaciones_expansion();
            angulo_maximo = this.pParOpt.AnguloMaximoBuses;
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            cant_po = this.iCantPuntosOperacion;
            for i = 1:length(nuevos_buses)
                if ~isa(nuevos_buses(i), 'cSubestacion')
                    % esta verificación está de más. Siguiente throw error
                    % es sólo para confirmar, antes de eliminar esta parte
                    % del código
                    error = MException('cOptMILP:escribe_restricciones_angulos_se_proyectadas_theta_max',...
                        ['Nuevo bus id ' num2str(i) ' no es tipo cSubestacion']);
                    throw(error)                    
                    %continue;
                end
                
                se = nuevos_buses(i);
                this.iIndiceIneq = this.iIndiceIneq + 1;
                indice_lim_superior_desde = this.iIndiceIneq;
                indice_lim_superior_hasta = indice_lim_superior_desde + cant_po - 1;
                
                this.iIndiceIneq = indice_lim_superior_hasta + 1;
                indice_lim_inferior_desde = this.iIndiceIneq;
                indice_lim_inferior_hasta = indice_lim_inferior_desde + cant_po - 1;
                this.iIndiceIneq = indice_lim_inferior_hasta;
                
                indice_operacion_desde = se.entrega_varopt_operacion('Theta', escenario, etapa);
                indice_operacion_hasta = indice_operacion_desde + cant_po - 1;
                %límites superior e inferior

                %this.Aineq(indice_lim_superior_desde:indice_lim_superior_hasta,indice_operacion_desde:indice_operacion_hasta) = diag(ones(this.iCantPuntosOperacion,1));                
                this.agrega_valores_matriz_desigualdad(cant_po,indice_lim_superior_desde:indice_lim_superior_hasta,indice_operacion_desde:indice_operacion_hasta,1);

                %this.Aineq(indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_operacion_desde:indice_operacion_hasta) = -1*diag(ones(this.iCantPuntosOperacion,1));
                this.agrega_valores_matriz_desigualdad(cant_po,indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_operacion_desde:indice_operacion_hasta,-1);
                
                proy = this.pAdmProy.entrega_proyecto_subestacion(se);
                %indice_expansion_desde = proy.entrega_varopt_expansion('Decision', escenario);
                %indice_expansion_hasta = indice_expansion_desde + etapa - 1;
                indice_expansion = proy.entrega_varopt_expansion('Acumulada', escenario) + etapa - 1;
                valor = round(-angulo_maximo,dec_redondeo);
                %this.Aineq(indice_lim_superior_desde:indice_lim_superior_hasta,indice_expansion) = valor;                
                this.agrega_valores_matriz_desigualdad(cant_po,indice_lim_superior_desde:indice_lim_superior_hasta,indice_expansion,valor);

                %this.Aineq(indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_expansion) = valor;
                this.agrega_valores_matriz_desigualdad(cant_po,indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_expansion,valor);

                this.bineq(indice_lim_superior_desde:indice_lim_superior_hasta,1) = 0;
                this.bineq(indice_lim_inferior_desde:indice_lim_inferior_hasta,1) = 0;
                this.TipoRestriccionIneq(indice_lim_superior_desde:indice_lim_superior_hasta) = 2;
                this.EscenarioRestriccionIneq(indice_lim_superior_desde:indice_lim_superior_hasta) = escenario;
                this.EtapaRestriccionIneq(indice_lim_superior_desde:indice_lim_superior_hasta) = etapa;
                this.SubetapaRestriccionIneq(indice_lim_superior_desde:indice_lim_superior_hasta) = this.RelSubetapasPO;
%this.vIndicesPOConsecutivos                 
% linlinlinlinlinlinlin
                this.TipoRestriccionIneq(indice_lim_inferior_desde:indice_lim_inferior_hasta) = 2;
                this.EscenarioRestriccionIneq(indice_lim_inferior_desde:indice_lim_inferior_hasta) = escenario;
                this.EtapaRestriccionIneq(indice_lim_inferior_desde:indice_lim_inferior_hasta) = etapa;
                this.SubetapaRestriccionIneq(indice_lim_inferior_desde:indice_lim_inferior_hasta) = this.RelSubetapasPO;
                
                if this.iNivelDebug > 1
                    vn = se.entrega_vn();
                    ubicacion = se.entrega_ubicacion();
                    oper = (1:1:this.iCantPuntosOperacion)';
                    indices_sup = (indice_lim_superior_desde:1:indice_lim_superior_desde+this.iCantPuntosOperacion-1)';
                    indices_inf = (indice_lim_inferior_desde:1:indice_lim_inferior_desde+this.iCantPuntosOperacion-1)';
                    nombre_sup = strcat('rineq_', num2str(indices_sup), '_limsup_angulo_nuevas_se_B', num2str(ubicacion), '_V_', num2str(vn), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                    this.NombreIneq(indices_sup') = cellstr(nombre_sup);
                    nombre_inf = strcat('rineq_', num2str(indices_inf), '_liminf_angulo_nuevas_se_B', num2str(ubicacion), '_V_', num2str(vn), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                    this.NombreIneq(indices_inf') = cellstr(nombre_inf);
                    
%                     for punto_operacion = 1:this.iCantPuntosOperacion
%                         indice_lim_superior = indice_lim_superior_desde + punto_operacion - 1;
%                         indice_lim_inferior = indice_lim_inferior_desde + punto_operacion - 1;
%                         
%                         this.NombreIneq{indice_lim_superior} = strcat('rineq_', num2str(indice_lim_superior), '_limsup_angulo_nuevas_se_B', num2str(ubicacion), '_V_', num2str(vn), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(punto_operacion));
%                         this.NombreIneq{indice_lim_inferior} = strcat('rineq_', num2str(indice_lim_inferior), '_liminf_angulo_nuevas_se_B', num2str(ubicacion), '_V_', num2str(vn), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(punto_operacion));
%                     end
                end
            end
        end

        function escribe_restricciones_angulos_se_proyectadas_theta_ady(this, escenario, etapa)
            % es necesario, ya que si no el ángulo queda "flotando" en caso
            % de que la subestación no se construya
            % balance energía subestaciones proyectadas
            nuevos_buses = this.pAdmProy.entrega_buses();
            for i = 1:length(nuevos_buses)
                if ~isa(nuevos_buses(i), 'cSubestacion')
                    % esta verificación está de más. Siguiente throw error
                    % es sólo para confirmar, antes de eliminar esta parte
                    % del código
                    error = MException('cOptMILP:escribe_restricciones_angulos_se_proyectadas_theta_ady',...
                        ['Nuevo bus id ' num2str(i) ' no es tipo cSubestacion']);
                    throw(error)                    
                    %continue;
                end
                
                se = nuevos_buses(i);
                indice_lim_superior_desde = this.iIndiceIneq + 1;
                indice_lim_superior_hasta = indice_lim_superior_desde + this.iCantPuntosOperacion - 1;
                
                indice_lim_inferior_desde = indice_lim_superior_hasta + 1;
                indice_lim_inferior_hasta = indice_lim_inferior_desde + this.iCantPuntosOperacion - 1;
                this.iIndiceIneq = indice_lim_inferior_hasta;
                
                indice_operacion_desde = se.entrega_varopt_operacion('Theta', escenario, etapa);
                indice_operacion_hasta = indice_operacion_desde + this.iCantPuntosOperacion - 1;
                
                % identifica subestacion "adyacente"
                se_adyacente = this.entrega_subestacion_adyacente(se);
                indice_operacion_adyacente_desde = se_adyacente.entrega_varopt_operacion('Theta', escenario, etapa);
                indice_operacion_adyacente_hasta = indice_operacion_adyacente_desde + this.iCantPuntosOperacion - 1;

                %límites superior e inferior

                %this.Aineq(indice_lim_superior_desde:indice_lim_superior_hasta,indice_operacion_desde:indice_operacion_hasta) = diag(ones(this.iCantPuntosOperacion,1));                
                this.agrega_valores_matriz_desigualdad(cant_po,indice_lim_superior_desde:indice_lim_superior_hasta,indice_operacion_desde:indice_operacion_hasta,1);

                %this.Aineq(indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_operacion_desde:indice_operacion_hasta) = -1*diag(ones(this.iCantPuntosOperacion,1));
                this.agrega_valores_matriz_desigualdad(cant_po,indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_operacion_desde:indice_operacion_hasta,-1);

                %this.Aineq(indice_lim_superior_desde:indice_lim_superior_hasta,indice_operacion_adyacente_desde:indice_operacion_adyacente_hasta) = -1*diag(ones(this.iCantPuntosOperacion,1));                
                this.agrega_valores_matriz_desigualdad(cant_po,indice_lim_superior_desde:indice_lim_superior_hasta,indice_operacion_adyacente_desde:indice_operacion_adyacente_hasta,-1);

                %this.Aineq(indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_operacion_adyacente_desde:indice_operacion_adyacente_hasta) = diag(ones(this.iCantPuntosOperacion,1));
                this.agrega_valores_matriz_desigualdad(cant_po,indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_operacion_adyacente_desde:indice_operacion_adyacente_hasta,1);
                
                proy = this.pAdmProy.entrega_proyecto_subestacion(se);
                indice_expansion_desde = proy.entrega_varopt_expansion('Decision', escenario);
                indice_expansion_hasta = indice_expansion_desde + etapa - 1;
                
                %valor = round(-angulo_maximo,dec_redondeo);

                valor = this.entrega_parametro_disyuntivo_base(se.entrega_id(), se_adyacente.entrega_id());
                
                %this.Aineq(indice_lim_superior_desde:indice_lim_superior_hasta,indice_expansion_desde:indice_expansion_hasta) = -1*valor;
                this.agrega_valores_matriz_desigualdad(cant_po,indice_lim_superior_desde:indice_lim_superior_hasta,indice_expansion_desde:indice_expansion_hasta,-valor);

                %this.Aineq(indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_expansion_desde:indice_expansion_hasta) = -1*valor;
                this.agrega_valores_matriz_desigualdad(cant_po,indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_expansion_desde:indice_expansion_hasta,-valor);

                this.bineq(indice_lim_superior_desde:indice_lim_superior_hasta,1) = 0;
                this.bineq(indice_lim_inferior_desde:indice_lim_inferior_hasta,1) = 0;

                this.TipoRestriccionIneq(indice_lim_superior_desde:indice_lim_superior_hasta) = 2;
                this.TipoRestriccionIneq(indice_lim_inferior_desde:indice_lim_inferior_hasta) = 2;
                
                this.EscenarioRestriccionIneq(indice_lim_superior_desde:indice_lim_superior_hasta) = escenario;
                this.EscenarioRestriccionIneq(indice_lim_inferior_desde:indice_lim_inferior_hasta) = escenario;
                this.EtapaRestriccionIneq(indice_lim_superior_desde:indice_lim_superior_hasta) = etapa;
                this.EtapaRestriccionIneq(indice_lim_inferior_desde:indice_lim_inferior_hasta) = etapa;
                this.SubetapaRestriccionIneq(indice_lim_superior_desde:indice_lim_superior_hasta) = this.RelSubetapasPO;
                this.SubetapaRestriccionIneq(indice_lim_inferior_desde:indice_lim_inferior_hasta) = this.RelSubetapasPO;
                
                if this.iNivelDebug > 1
                    vn = se.entrega_vn();
                    ubicacion = se.entrega_ubicacion();
                    oper = (1:1:this.iCantPuntosOperacion)';
                    indices_sup = (indice_lim_superior_desde:1:indice_lim_superior_desde+this.iCantPuntosOperacion-1)';
                    indices_inf = (indice_lim_inferior_desde:1:indice_lim_inferior_desde+this.iCantPuntosOperacion-1)';
                    nombre_sup = strcat('rineq_', num2str(indices_sup), '_limsup_angulo_nuevas_se_B', num2str(ubicacion), '_V_', num2str(vn), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                    this.NombreIneq(indices_sup') = cellstr(nombre_sup);
                    nombre_inf = strcat('rineq_', num2str(indices_inf), '_liminf_angulo_nuevas_se_B', num2str(ubicacion), '_V_', num2str(vn), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                    this.NombreIneq(indices_inf') = cellstr(nombre_inf);
                    
%                     for punto_operacion = 1:this.iCantPuntosOperacion
%                         indice_lim_superior = indice_lim_superior_desde + punto_operacion - 1;
%                         indice_lim_inferior = indice_lim_inferior_desde + punto_operacion - 1;
%                         
%                         this.NombreIneq{indice_lim_superior} = strcat('rineq_', num2str(indice_lim_superior), '_limsup_angulo_nuevas_se_B', num2str(ubicacion), '_V_', num2str(vn), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(punto_operacion));
%                         this.NombreIneq{indice_lim_inferior} = strcat('rineq_', num2str(indice_lim_inferior), '_liminf_angulo_nuevas_se_B', num2str(ubicacion), '_V_', num2str(vn), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(punto_operacion));
%                     end
                end
            end
        end
        
        function escribe_balance_energia_se_proyectadas(this, escenario, etapa)
            % balance energía subestaciones proyectadas
            nuevos_buses = this.pAdmProy.entrega_subestaciones_expansion();
            cant_po = this.iCantPuntosOperacion;
            for i = 1:length(nuevos_buses)
                if ~isa(nuevos_buses(i), 'cSubestacion')
                    % esta verificación está de más. Siguiente throw error
                    % es sólo para confirmar, antes de eliminar esta parte
                    % del código
                    error = MException('cOptMILP:escribe_balance_energia_se_proyectadas',...
                        ['Nuevo bus id ' num2str(i) ' no es tipo cSubestacion']);
                    throw(error)                    
                    %continue;
                end
                
                se = nuevos_buses(i);
                indice_eq_desde = this.iIndiceEq + 1;
                indice_eq_hasta = this.iIndiceEq + cant_po;
                this.iIndiceEq = indice_eq_hasta;

                
                if this.iNivelDebug > 1
                    id_se = se.entrega_id();
                    oper = (1:1:this.iCantPuntosOperacion)';
                    indices = (indice_eq_desde:1:indice_eq_desde+cant_po-1)';
                    nombre = strcat('req_be_se_proyectada_', num2str(indices), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                    this.NombreEq(indices') = cellstr(nombre);
%                     for punto_operacion = 1:this.iCantPuntosOperacion
%                         indice_eq = indice_eq_desde + punto_operacion - 1;
%                         id_se = se.entrega_id();
%                         this.NombreEq{indice_eq} = strcat('req_be_se_proyectada_', num2str(indice_eq), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(punto_operacion));
%                     end
                end
                
                % por ahora, se asume que nuevas subestaciones es sólo para
                % voltage uprating. No se consideran ni nuevos generadores
                % o consumos. Balance energético es por ende cero.
                this.beq(indice_eq_desde:indice_eq_hasta,1) = 0;
                this.TipoRestriccionEq(indice_eq_desde:indice_eq_hasta) = 2;
                this.EscenarioRestriccionEq(indice_eq_desde:indice_eq_hasta) = escenario;
                this.EtapaRestriccionEq(indice_eq_desde:indice_eq_hasta) = etapa;
                this.SubetapaRestriccionEq(indice_eq_desde:indice_eq_hasta) = this.RelSubetapasPO;
                
                % sólo transformadores, líneas y baterías proyectadas. No habrán
                % líneas o transformadores existentes conectados a esta
                % subestación
                el_serie = this.pAdmProy.entrega_elementos_serie_expansion_por_subestacion(se);
                for j = 1:length(el_serie)
                    if isa(el_serie(j), 'cLinea') || isa(el_serie(j), 'cTransformador2D')
                        [se_1, se_2] = el_serie(j).entrega_subestaciones();
                        if se_1 == se
                            corresponde = true;
                            signo = -1;
                        elseif se_2 == se
                            corresponde = true;
                            signo = 1;
                        else
                            %redundante, pero para mejor entendimiento del
                            %programa
                            corresponde = false;
                        end
                    
                        if corresponde
                            indice_desde = el_serie(j).entrega_varopt_operacion('P', escenario, etapa);
                            indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;
                            %this.Aeq(indice_eq_desde:indice_eq_hasta, indice_desde:indice_hasta) = signo*diag(ones(this.iCantPuntosOperacion,1));
                            this.agrega_valores_matriz_igualdad(cant_po,indice_eq_desde:indice_eq_hasta, indice_desde:indice_hasta,signo);
                            
                        end
                    end
                end
%                 el_par = this.pAdmProy.entrega_baterias_por_subestacion(se);
%                 for j = 1:length(el_par)
%                     indice_desde = el_par(j).entrega_varopt_operacion('P', escenario, etapa);
%                     indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;
%                     %this.Aeq(indice_eq_desde:indice_eq_hasta, indice_desde:indice_hasta) = diag(ones(this.iCantPuntosOperacion,1));
%                     this.agrega_valores_matriz_igualdad(cant_po,indice_eq_desde:indice_eq_hasta, indice_desde:indice_hasta,1);
%                 end
            end
        end
        
        function escribe_limites_operacionales_lineas_trafos(this, escenario, etapa)
            % 1. Límites operacionales de las lineas existentes y
            % proyectadas
            el_red = this.pSEP.entrega_lineas();
            el_red = [el_red; this.pSEP.entrega_transformadores2d()];
            cant_po = this.iCantPuntosOperacion;
            el_serie_proy = this.pAdmProy.entrega_elementos_red_proyectados(escenario);
            for ii = 1:length(el_serie_proy)
                if el_serie_proy(ii).entrega_etapa_entrada(escenario) <= etapa
                    el_red = [el_red; el_serie_proy(ii)];
                end
            end
            
            el_red = [el_red; this.pAdmProy.entrega_elementos_serie_expansion()];
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            for i = 1:length(el_red)
                %existe_elred = this.pSEP.existe_elemento(el_red(i));
                existe_elred = el_red(i).Existente || el_red(i).Proyectado  && (el_red(i).entrega_etapa_entrada(escenario) ~= 0 && el_red(i).entrega_etapa_entrada(escenario) <= etapa) ;
                
                this.iIndiceIneq = this.iIndiceIneq + 1;
                indice_lim_superior_desde = this.iIndiceIneq;
                indice_lim_superior_hasta = indice_lim_superior_desde + cant_po - 1;
                
                this.iIndiceIneq = indice_lim_superior_hasta + 1;
                indice_lim_inferior_desde = this.iIndiceIneq;
                indice_lim_inferior_hasta = indice_lim_inferior_desde + cant_po - 1;
                this.iIndiceIneq = indice_lim_inferior_hasta;
                
                indice_operacion_desde = el_red(i).entrega_varopt_operacion('P', escenario, etapa);
                indice_operacion_hasta = indice_operacion_desde + this.iCantPuntosOperacion - 1;
                
                capacidad = el_red(i).entrega_sr_pu();

                %límites superior e inferior
                %this.Aineq(indice_lim_superior_desde:indice_lim_superior_hasta,indice_operacion_desde:indice_operacion_hasta) = diag(ones(this.iCantPuntosOperacion,1));                
                this.agrega_valores_matriz_desigualdad(cant_po,indice_lim_superior_desde:indice_lim_superior_hasta,indice_operacion_desde:indice_operacion_hasta,1);
                %this.Aineq(indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_operacion_desde:indice_operacion_hasta) = -1*diag(ones(this.iCantPuntosOperacion,1));
                this.agrega_valores_matriz_desigualdad(cant_po,indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_operacion_desde:indice_operacion_hasta,-1);

                proyectos_agregar = this.pAdmProy.entrega_proyectos_agregar_reforzamiento_serie(el_red(i));
                proyectos_remover = this.pAdmProy.entrega_proyectos_remover_reforzamiento_serie(el_red(i));
                % Identifica proyectos que contienen esta línea. Se
                % incluye variable que indica si proyecto se construye
                % o no
                for proy = 1:length(proyectos_agregar)
                    indice_expansion = proyectos_agregar(proy).entrega_varopt_expansion('Acumulada', escenario) + etapa - 1;

                    %this.Aineq(indice_lim_superior_desde:indice_lim_superior_hasta,indice_expansion) = round(-1*capacidad,dec_redondeo);
                    this.agrega_valores_matriz_desigualdad(cant_po,indice_lim_superior_desde:indice_lim_superior_hasta,indice_expansion,round(-capacidad,dec_redondeo));
                    %this.Aineq(indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_expansion) = round(-1*capacidad,dec_redondeo);
                    this.agrega_valores_matriz_desigualdad(cant_po,indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_expansion,round(-capacidad,dec_redondeo));
                    
                end
                for proy = 1:length(proyectos_remover)
                    indice_expansion = proyectos_remover(proy).entrega_varopt_expansion('Acumulada', escenario) + etapa -1;

                    %this.Aineq(indice_lim_superior_desde:indice_lim_superior_hasta,indice_expansion) = round(capacidad,dec_redondeo);
                    this.agrega_valores_matriz_desigualdad(cant_po, indice_lim_superior_desde:indice_lim_superior_hasta,indice_expansion,round(capacidad,dec_redondeo));
                    %this.Aineq(indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_expansion) = round(capacidad,dec_redondeo);
                    this.agrega_valores_matriz_desigualdad(cant_po, indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_expansion,round(capacidad,dec_redondeo));
                end
                if existe_elred
                    this.bineq(indice_lim_superior_desde:indice_lim_superior_hasta,1) = round(capacidad,dec_redondeo);
                    this.bineq(indice_lim_inferior_desde:indice_lim_inferior_hasta,1) = round(capacidad,dec_redondeo);
                else
                    this.bineq(indice_lim_superior_desde:indice_lim_superior_hasta,1) = 0;
                    this.bineq(indice_lim_inferior_desde:indice_lim_inferior_hasta,1) = 0;
                end

                this.TipoRestriccionIneq(indice_lim_superior_desde:indice_lim_superior_hasta) = 2;
                this.TipoRestriccionIneq(indice_lim_inferior_desde:indice_lim_inferior_hasta) = 2;

                this.EscenarioRestriccionIneq(indice_lim_superior_desde:indice_lim_superior_hasta) = escenario;
                this.EscenarioRestriccionIneq(indice_lim_inferior_desde:indice_lim_inferior_hasta) = escenario;
                this.EtapaRestriccionIneq(indice_lim_superior_desde:indice_lim_superior_hasta) = etapa;
                this.EtapaRestriccionIneq(indice_lim_inferior_desde:indice_lim_inferior_hasta) = etapa;
                this.SubetapaRestriccionIneq(indice_lim_superior_desde:indice_lim_superior_hasta) = this.RelSubetapasPO;
                this.SubetapaRestriccionIneq(indice_lim_inferior_desde:indice_lim_inferior_hasta) = this.RelSubetapasPO;
                
                if this.iNivelDebug > 1
                    [se_1, se_2] = el_red(i).entrega_subestaciones();
                    id_se_1 = se_1.entrega_id();
                    id_se_2 = se_2.entrega_id();
                    id_paralelo = el_red(i).entrega_indice_paralelo();
                    if isa(el_red(i), 'cLinea')
                        if existe_elred
                            tipo = 'LE';
                        else
                            tipo = 'LP';
                        end
                    else
                        if existe_elred
                            tipo = 'TE';
                        else
                            tipo = 'TP';
                        end
                    end
                    oper = (1:1:this.iCantPuntosOperacion)';
                    indices_sup = (indice_lim_superior_desde:1:indice_lim_superior_desde+this.iCantPuntosOperacion-1)';
                    indices_inf = (indice_lim_inferior_desde:1:indice_lim_inferior_desde+this.iCantPuntosOperacion-1)';
                    nombre_sup = strcat('rineq_', num2str(indices_sup), '_lim_op_sup_', tipo, num2str(id_paralelo), '_B', num2str(id_se_1), '_', num2str(id_se_2), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                    this.NombreIneq(indices_sup') = cellstr(nombre_sup);
                    nombre_inf = strcat('rineq_', num2str(indices_inf), '_lim_op_inf_', tipo, num2str(id_paralelo), '_B', num2str(id_se_1), '_', num2str(id_se_2), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                    this.NombreIneq(indices_inf') = cellstr(nombre_inf);
                    
%                     for punto_operacion = 1:this.iCantPuntosOperacion
%                         indice_lim_superior = indice_lim_superior_desde + punto_operacion - 1;
%                         indice_lim_inferior = indice_lim_inferior_desde + punto_operacion - 1;
%                         this.NombreIneq{indice_lim_superior} = strcat('rineq_', num2str(indice_lim_superior), '_lim_op_sup_', tipo, num2str(id_paralelo), '_B', num2str(id_se_1), '_', num2str(id_se_2), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(punto_operacion));
%                         this.NombreIneq{indice_lim_inferior} = strcat('rineq_', num2str(indice_lim_inferior), '_lim_op_inf_', tipo, num2str(id_paralelo), '_B', num2str(id_se_1), '_', num2str(id_se_2), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(punto_operacion));
%                     end
                end
            end
        end

        function escribe_limites_operacionales_baterias(this, escenario, etapa)
            % 1. Límites operacionales de las baterías existentes y proyectadas
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            el_red = this.pAdmProy.entrega_baterias();
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            cant_po = this.iCantPuntosOperacion;
            for i = 1:length(el_red)
                %existe_elred = this.pSEP.existe_elemento(el_red(i));
                existe_elred = el_red(i).Existente;
                
                this.iIndiceIneq = this.iIndiceIneq + 1;
                indice_lim_sup_descarga_desde = this.iIndiceIneq;
                indice_lim_sup_descarga_hasta = indice_lim_sup_descarga_desde + this.iCantPuntosOperacion - 1;
                
                this.iIndiceIneq = indice_lim_sup_descarga_hasta + 1;
                indice_lim_sup_carga_desde = this.iIndiceIneq;
                indice_lim_sup_carga_hasta = indice_lim_sup_carga_desde + this.iCantPuntosOperacion - 1;
                this.iIndiceIneq = indice_lim_sup_carga_hasta;
                
                indice_op_descarga_desde = el_red(i).entrega_varopt_operacion('Pdescarga', escenario, etapa);
                indice_op_descarga_hasta = indice_op_descarga_desde + this.iCantPuntosOperacion - 1;
                
                indice_op_carga_desde = el_red(i).entrega_varopt_operacion('Pcarga', escenario, etapa);
                indice_op_carga_hasta = indice_op_carga_desde + this.iCantPuntosOperacion - 1;
                
                pmax_carga = el_red(i).entrega_pmax_carga()/sbase;
                pmax_descarga = el_red(i).entrega_pmax_descarga()/sbase;
                %límites superior e inferior

                %this.Aineq(indice_lim_sup_descarga_desde:indice_lim_sup_descarga_hasta,indice_op_descarga_desde:indice_op_descarga_hasta) = diag(ones(this.iCantPuntosOperacion,1));                
                this.agrega_valores_matriz_desigualdad(cant_po, indice_lim_sup_descarga_desde:indice_lim_sup_descarga_hasta,indice_op_descarga_desde:indice_op_descarga_hasta,1);

                %this.Aineq(indice_lim_sup_carga_desde:indice_lim_sup_carga_hasta,indice_op_carga_desde:indice_op_carga_hasta) = diag(ones(this.iCantPuntosOperacion,1));
                this.agrega_valores_matriz_desigualdad(cant_po, indice_lim_sup_carga_desde:indice_lim_sup_carga_hasta,indice_op_carga_desde:indice_op_carga_hasta,1);
                
                proyectos_agregar = this.pAdmProy.entrega_proyectos_agregar_reforzamiento_paralelo(el_red(i));
                % por ahora no se remueven las baterías
                %proyectos_remover = this.pAdmProy.entrega_proyectos_remover(el_red(i));
                % Identifica proyectos que contienen esta línea. Se
                % incluye variable que indica si proyecto se construye
                % o no
                for proy = 1:length(proyectos_agregar)
                    indice_expansion = proyectos_agregar(proy).entrega_varopt_expansion('Acumulada', escenario) + etapa -1;

                    %this.Aineq(indice_lim_sup_descarga_desde:indice_lim_sup_descarga_hasta,indice_expansion) = round(-pmax_descarga,dec_redondeo);
                    this.agrega_valores_matriz_desigualdad(cant_po, indice_lim_sup_descarga_desde:indice_lim_sup_descarga_hasta,indice_expansion,round(-pmax_descarga,dec_redondeo));
                    
                    this.Aineq(indice_lim_sup_carga_desde:indice_lim_sup_carga_hasta,indice_expansion) = round(-pmax_carga,dec_redondeo);
                    this.agrega_valores_matriz_desigualdad(cant_po, indice_lim_sup_carga_desde:indice_lim_sup_carga_hasta,indice_expansion,round(-pmax_carga,dec_redondeo));
                end
                if existe_elred
                    this.bineq(indice_lim_sup_descarga_desde:indice_lim_sup_descarga_hasta,1) = round(pmax_descarga,dec_redondeo);
                    this.bineq(indice_lim_sup_carga_desde:indice_lim_sup_carga_hasta,1) = round(pmax_carga,dec_redondeo);
                else
                    this.bineq(indice_lim_sup_descarga_desde:indice_lim_sup_descarga_hasta,1) = 0;
                    this.bineq(indice_lim_sup_carga_desde:indice_lim_sup_carga_hasta,1) = 0;
                end
                this.TipoRestriccionIneq(indice_lim_sup_descarga_desde:indice_lim_sup_descarga_hasta) = 2;
                this.TipoRestriccionIneq(indice_lim_sup_carga_desde:indice_lim_sup_carga_hasta) = 2;
                
                this.EscenarioRestriccionIneq(indice_lim_sup_descarga_desde:indice_lim_sup_descarga_hasta) = escenario;
                this.EscenarioRestriccionIneq(indice_lim_sup_carga_desde:indice_lim_sup_carga_hasta) = escenario;
                this.EtapaRestriccionIneq(indice_lim_sup_descarga_desde:indice_lim_sup_descarga_hasta) = etapa;
                this.EtapaRestriccionIneq(indice_lim_sup_carga_desde:indice_lim_sup_carga_hasta) = etapa;
                this.SubetapaRestriccionIneq(indice_lim_sup_descarga_desde:indice_lim_sup_descarga_hasta) = this.RelSubetapasPO;
                this.SubetapaRestriccionIneq(indice_lim_sup_carga_desde:indice_lim_sup_carga_hasta) = this.RelSubetapasPO;

                if this.iNivelDebug > 1
                    se = el_red(i).entrega_se();
                    id_se = se.entrega_id();
                    id_paralelo = el_red(i).entrega_indice_paralelo();
                    if existe_elred
                        tipo = 'BE';
                    else
                        tipo = 'BP';
                    end
                    oper = (1:1:this.iCantPuntosOperacion)';
                    indices_carga = (indice_lim_sup_descarga_desde:1:indice_lim_sup_descarga_desde+this.iCantPuntosOperacion-1)';
                    nombre_carga = strcat('rineq_', num2str(indices_carga), '_lim_sup_bdesc', tipo, num2str(id_paralelo), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                    this.NombreIneq(indices_carga') = cellstr(nombre_carga);
                    indices_descarga = (indice_lim_sup_carga_desde:1:indice_lim_sup_carga_desde+this.iCantPuntosOperacion-1)';
                    nombre_descarga = strcat('rineq_', num2str(indices_descarga), '_lim_sup_bcarga', tipo, num2str(id_paralelo), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                    this.NombreIneq(indices_descarga') = cellstr(nombre_descarga);
                    
%                     for punto_operacion = 1:this.iCantPuntosOperacion
%                         indice_lim_sup_descarga = indice_lim_sup_descarga_desde + punto_operacion - 1;
%                         indice_lim_sup_carga = indice_lim_sup_carga_desde + punto_operacion - 1;
%                         this.NombreIneq{indice_lim_sup_descarga} = strcat('rineq_', num2str(indice_lim_sup_descarga), '_lim_sup_bdesc', tipo, num2str(id_paralelo), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(punto_operacion));
%                         this.NombreIneq{indice_lim_sup_carga} = strcat('rineq_', num2str(indice_lim_sup_carga), '_lim_sup_bcarga', tipo, num2str(id_paralelo), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(punto_operacion));
%                     end
                end
            end
        end
        
        function escribe_restricciones_flujos_angulos(this, escenario, etapa)
            % por cada línea y transformador, tanto existente, proyectado y de expansio´n, se deben
            % escribir las restricciones con los ángulos
            % las restricciones son siempre de desigualdad, ya que una
            % línea existente puede ser removida
            cant_po = this.iCantPuntosOperacion;
            el_red = this.pSEP.entrega_lineas();
            el_red = [el_red; this.pSEP.entrega_transformadores2d()];

            el_serie_proy = this.pAdmProy.entrega_elementos_red_proyectados(escenario);
            for ii = 1:length(el_serie_proy)
                if (el_serie_proy(ii).entrega_etapa_entrada(escenario) ~= 0 && el_serie_proy(ii).entrega_etapa_entrada(escenario) <= etapa)
                    el_red = [el_red; el_serie_proy(ii)];
                end
            end
            
            el_red = [el_red; this.pAdmProy.entrega_elementos_serie_expansion()];
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            for i = 1:length(el_red)
% if strcmp(el_red(i).Nombre, "L1_C4_SE1_7_V110")
%     linlinlinlin = 1
% end
                this.iIndiceIneq = this.iIndiceIneq + 1;
                indice_lim_superior_desde = this.iIndiceIneq;
                indice_lim_superior_hasta = indice_lim_superior_desde + cant_po - 1;
                
                this.iIndiceIneq = indice_lim_superior_hasta + 1;
                indice_lim_inferior_desde = this.iIndiceIneq;
                indice_lim_inferior_hasta = indice_lim_inferior_desde + cant_po - 1;
                this.iIndiceIneq = indice_lim_inferior_hasta;
                
                reactancia = el_red(i).entrega_reactancia_pu();
                indice_elred_desde = el_red(i).entrega_varopt_operacion('P', escenario, etapa);
                indice_elred_hasta = indice_elred_desde + cant_po - 1;
                
                [se_1, se_2] = el_red(i).entrega_subestaciones();
                indice_se_1_desde = se_1.entrega_varopt_operacion('Theta', escenario, etapa);
                indice_se_1_hasta = indice_se_1_desde + cant_po - 1;
                
                indice_se_2_desde = se_2.entrega_varopt_operacion('Theta', escenario, etapa);
                indice_se_2_hasta = indice_se_2_desde + cant_po - 1;
                
                % Parámetros disyuntivos
                par_disy = this.entrega_parametro_disyuntivo_base(se_1.entrega_id(), se_2.entrega_id());
                factor_bigm = this.pParOpt.FactorMultiplicadorBigM;
                
                big_m_sistema = round(factor_bigm*par_disy/reactancia,dec_redondeo);
                big_m_vu = round(factor_bigm*this.entrega_parametro_disyuntivo_vu(se_1.entrega_id(), se_2.entrega_id())/reactancia,dec_redondeo);
                big_m_cscc = round(factor_bigm*this.entrega_parametro_disyuntivo_cscc(se_1.entrega_id(), se_2.entrega_id())/reactancia,dec_redondeo);
                big_m_conv = round(factor_bigm*this.entrega_parametro_disyuntivo_conv(se_1.entrega_id(), se_2.entrega_id())/reactancia,dec_redondeo);

                %this.Aineq(indice_lim_superior_desde:indice_lim_superior_hasta,indice_elred_desde:indice_elred_hasta) = diag(ones(this.iCantPuntosOperacion,1));
                this.agrega_valores_matriz_desigualdad(cant_po, indice_lim_superior_desde:indice_lim_superior_hasta,indice_elred_desde:indice_elred_hasta,1);
                
                %this.Aineq(indice_lim_superior_desde:indice_lim_superior_hasta,indice_se_1_desde:indice_se_1_hasta) = round(-1/reactancia,dec_redondeo)*diag(ones(this.iCantPuntosOperacion,1));
                this.agrega_valores_matriz_desigualdad(cant_po, indice_lim_superior_desde:indice_lim_superior_hasta,indice_se_1_desde:indice_se_1_hasta,round(-1/reactancia,dec_redondeo));
                
                %this.Aineq(indice_lim_superior_desde:indice_lim_superior_hasta,indice_se_2_desde:indice_se_2_hasta) = round(1/reactancia,dec_redondeo)*diag(ones(this.iCantPuntosOperacion,1));
                this.agrega_valores_matriz_desigualdad(cant_po, indice_lim_superior_desde:indice_lim_superior_hasta,indice_se_2_desde:indice_se_2_hasta,round(1/reactancia,dec_redondeo));
                
                %this.Aineq(indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_elred_desde:indice_elred_hasta) = -1*diag(ones(this.iCantPuntosOperacion,1));
                this.agrega_valores_matriz_desigualdad(cant_po, indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_elred_desde:indice_elred_hasta,-1);
                
                %this.Aineq(indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_se_1_desde:indice_se_1_hasta) = round(1/reactancia,dec_redondeo)*diag(ones(this.iCantPuntosOperacion,1));
                this.agrega_valores_matriz_desigualdad(cant_po, indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_se_1_desde:indice_se_1_hasta,round(1/reactancia,dec_redondeo));
                
                %this.Aineq(indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_se_2_desde:indice_se_2_hasta) = round(-1/reactancia,dec_redondeo)*diag(ones(this.iCantPuntosOperacion,1));
                this.agrega_valores_matriz_desigualdad(cant_po, indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_se_2_desde:indice_se_2_hasta,round(-1/reactancia,dec_redondeo));
                
                existe_elred_sep_actual = el_red(i).Existente || el_red(i).entrega_etapa_entrada(escenario) ~= 0; % ya se verificó el caso de que la etapa de entrada es menor a la etapa actual
                if ~existe_elred_sep_actual
                    big_m_agrega = big_m_sistema;
                    % casos:
                    if strcmp(el_red(i).TipoExpansion,'Base')
                        big_m_agrega = max(big_m_agrega, max(big_m_vu, max(big_m_cscc, big_m_conv)));
                        
                        % big-M remueve
%                        if el_red(i).entrega_indice_paralelo() > 1
                            big_m_remueve_cc = big_m_cscc;
                            big_m_remueve_cs = big_m_cscc;
                            big_m_remueve_vu = big_m_vu;
%                        else % es la primera línea pero no existe en sep actual
%                            big_m_remueve_cc = min(big_m_sistema, big_m_cscc);
%                            big_m_remueve_cs = min(big_m_sistema, big_m_cscc);
%                            big_m_remueve_vu = min(big_m_sistema, big_m_vu);
%                        end 
                    else
                        %TODO: Por ahora no se considera remover línea de
                        %VU, CC, o CS
                        if el_red(i).entrega_indice_paralelo() > 1
                            big_m_agrega = max(big_m_agrega, max(big_m_vu, max(big_m_cscc, big_m_conv)));
                        else
                            if strcmp(el_red(i).TipoExpansion,'VU')
                                big_m_agrega = max(big_m_agrega, max(big_m_cscc, big_m_conv));
                            elseif strcmp(el_red(i).TipoExpansion,'CS') || strcmp(el_red(i).TipoExpansion,'CC') 
                                big_m_agrega = max(big_m_agrega, max(big_m_vu, big_m_conv));
                            end
                        end
                    end
                else
                    % línea existente
%                     big_m_sistema_n_menos_1 = inf;
%                     big_m_remueve_cc = min(big_m_sistema_n_menos_1, big_m_cscc);
%                     big_m_remueve_cs = min(big_m_sistema_n_menos_1, big_m_cscc);
%                     big_m_remueve_vu = min(big_m_sistema_n_menos_1, big_m_vu);
                    big_m_remueve_cc = big_m_cscc;
                    big_m_remueve_cs = big_m_cscc;
                    big_m_remueve_vu = big_m_vu;                    
                end
                
                proyectos_agregar = this.pAdmProy.entrega_proyectos_agregar_reforzamiento_serie(el_red(i));
                proyectos_remover = this.pAdmProy.entrega_proyectos_remover_reforzamiento_serie(el_red(i));
                % Identifica proyectos que contienen este elemento. Se
                % incluye variable que indica si proyecto se construye
                % o no
                for proy = 1:length(proyectos_agregar)
                    indice_expansion = proyectos_agregar(proy).entrega_varopt_expansion('Acumulada', escenario) + etapa - 1;

                    %this.Aineq(indice_lim_superior_desde:indice_lim_superior_hasta,indice_expansion) = big_m_agrega;
                    this.agrega_valores_matriz_desigualdad(cant_po, indice_lim_superior_desde:indice_lim_superior_hasta,indice_expansion,big_m_agrega);
                    
                    %this.Aineq(indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_expansion) = big_m_agrega;
                    this.agrega_valores_matriz_desigualdad(cant_po, indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_expansion,big_m_agrega);
                end
                
                for proy = 1:length(proyectos_remover)
                    if strcmp(proyectos_remover(proy).Tipo, 'CC')
                        big_m_remover = big_m_remueve_cc;
                    elseif strcmp(proyectos_remover(proy).Tipo, 'CS')
                        big_m_remover = big_m_remueve_cs;
                    elseif strcmp(proyectos_remover(proy).Tipo, 'AV')
                        big_m_remover = big_m_remueve_vu;
                    end
                    indice_expansion = proyectos_remover(proy).entrega_varopt_expansion('Acumulada', escenario) + etapa -1;

                    %this.Aineq(indice_lim_superior_desde:indice_lim_superior_hasta,indice_expansion) = -big_m_remover;
                    this.agrega_valores_matriz_desigualdad(cant_po, indice_lim_superior_desde:indice_lim_superior_hasta,indice_expansion,-big_m_remover);
                    %this.Aineq(indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_expansion) = -big_m_remover;
                    this.agrega_valores_matriz_desigualdad(cant_po, indice_lim_inferior_desde:indice_lim_inferior_hasta,indice_expansion,-big_m_remover);
                end
                if existe_elred_sep_actual
                    this.bineq(indice_lim_superior_desde:indice_lim_superior_hasta,1) = 0;
                    this.bineq(indice_lim_inferior_desde:indice_lim_inferior_hasta,1) = 0;
                else
                    this.bineq(indice_lim_superior_desde:indice_lim_superior_hasta,1) = big_m_agrega;
                    this.bineq(indice_lim_inferior_desde:indice_lim_inferior_hasta,1) = big_m_agrega;
                end

                this.TipoRestriccionIneq(indice_lim_superior_desde:indice_lim_superior_hasta) = 2;
                this.TipoRestriccionIneq(indice_lim_inferior_desde:indice_lim_inferior_hasta) = 2;
                
                this.EscenarioRestriccionIneq(indice_lim_superior_desde:indice_lim_superior_hasta) = escenario;
                this.EscenarioRestriccionIneq(indice_lim_inferior_desde:indice_lim_inferior_hasta) = escenario;
                this.EtapaRestriccionIneq(indice_lim_superior_desde:indice_lim_superior_hasta) = etapa;
                this.EtapaRestriccionIneq(indice_lim_inferior_desde:indice_lim_inferior_hasta) = etapa;
                this.SubetapaRestriccionIneq(indice_lim_superior_desde:indice_lim_superior_hasta) = this.RelSubetapasPO;
                this.SubetapaRestriccionIneq(indice_lim_inferior_desde:indice_lim_inferior_hasta) = this.RelSubetapasPO;
                
                if this.iNivelDebug > 1
                    id_paralelo = el_red(i).entrega_indice_paralelo();
                    id_se_1 = se_1.entrega_id();
                    id_se_2 = se_2.entrega_id();
                    if isa(el_red(i),'cLinea')
                        tipo = 'L';
                    else
                        tipo = 'T';
                    end
                    if existe_elred_sep_actual
                        tipo = [tipo 'E'];
                    else
                        tipo = [tipo 'P'];
                    end
                    oper = (1:1:cant_po)';
                    indices_sup = (indice_lim_superior_desde:1:indice_lim_superior_desde+cant_po-1)';
                    indices_inf = (indice_lim_inferior_desde:1:indice_lim_inferior_desde+cant_po-1)';
                    nombre_sup = strcat('rineq_', num2str(indices_sup), '_op_flujo_angulo_ub_',tipo, num2str(id_paralelo), '_B', num2str(id_se_1), '_', num2str(id_se_2), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                    this.NombreIneq(indices_sup') = cellstr(nombre_sup);
                    nombre_inf = strcat('rineq_', num2str(indices_inf), '_op_flujo_angulo_lb_',tipo, num2str(id_paralelo), '_B', num2str(id_se_1), '_', num2str(id_se_2), '_E', num2str(etapa), '_O', num2str(oper,'%03d'));
                    this.NombreIneq(indices_inf') = cellstr(nombre_inf);
                    
%                     for punto_operacion = 1:this.iCantPuntosOperacion
%                         indice_lim_superior = indice_lim_superior_desde + punto_operacion -1;
%                         indice_lim_inferior = indice_lim_inferior_desde + punto_operacion -1;
%                         this.NombreIneq{indice_lim_superior} = strcat('rineq_', num2str(indice_lim_superior), '_op_flujo_angulo_ub_',tipo, num2str(id_paralelo), '_B', num2str(id_se_1), '_', num2str(id_se_2), '_E', num2str(etapa), '_O', num2str(punto_operacion));
%                         this.NombreIneq{indice_lim_inferior} = strcat('rineq_', num2str(indice_lim_inferior), '_op_flujo_angulo_lb_',tipo, num2str(id_paralelo), '_B', num2str(id_se_1), '_', num2str(id_se_2), '_E', num2str(etapa), '_O', num2str(punto_operacion));
%                     end
                end
            end
        end
        
		function optimiza(this)
            %options = optimoptions('linprog','Display','off');
            if this.iNivelDebug > 0
                disp('dimensiones problema');
                disp(strcat('Cantidad de variables de decisión: ', num2str(this.iCantVarDecision)));
                disp(strcat('Dimension de funcion objetivo: ', num2str(length(this.Fobj))));
                disp(strcat('Dimension variables binarias: ', num2str(length(this.intcon))));
                [m, n] = size(this.Aineq);
                disp(strcat('Dimension matriz de desigualdad: ', num2str(m), 'x', num2str(n)));
                disp(strcat('Dimension vector de desigualdad: ', num2str(length(this.bineq))));
                disp(strcat('Cantidad desigualdades: ', num2str(this.iIndiceIneq)));
                [m, n] = size(this.Aeq);
                disp(strcat('Dimension matriz de igualdad: ', num2str(m), 'x', num2str(n)));
                disp(strcat('Dimension vector de igualdad: ', num2str(length(this.beq))));
                disp(strcat('Cantidad igualdades: ', num2str(this.iIndiceEq)));
                disp(strcat('Dimension vector lb: ', num2str(length(this.lb))));
                disp(strcat('Dimension vector ub: ', num2str(length(this.ub))));
            end

            if this.pParOpt.guarda_problema_optimizacion()
                % guarda problema optimizacion
                ProblemaOptimizacion.Fobj = this.Fobj;
                ProblemaOptimizacion.intcon = this.intcon;
                ProblemaOptimizacion.Aineq = this.Aineq;
                ProblemaOptimizacion.bineq = this.bineq;
                ProblemaOptimizacion.Aeq = this.Aeq;
                ProblemaOptimizacion.beq = this.beq;
                ProblemaOptimizacion.lb = this.lb;
                ProblemaOptimizacion.ub = this.ub;
                
                savefile = './output/MILP_Formulacion.mat';
                Res = ProblemaOptimizacion;
                save(savefile,'-struct', 'Res');
 
            end
            
            if strcmp(this.pParOpt.EstrategiaOptimizacion,'SingleMILP')
                if strcmp(this.pParOpt.Solver, 'Intlinprog')
                    options = optimoptions('intlinprog');
                    options.ConstraintTolerance = 1e-9;
                    options.IntegerTolerance = 1e-6;
                    options.RelativeGapTolerance = 1e-8;
                    [this.ResOptimizacion,this.Fval,this.ExitFlag,this.Output] = intlinprog(this.Fobj,this.intcon,this.Aineq,this.bineq,this.Aeq,this.beq,this.lb,this.ub, options);
                elseif strcmp(this.pParOpt.Solver, 'Xpress')
                    options= xprsoptimset('MAXMEMORY',this.pParOpt.MaxMemory,'MAXTIME',this.pParOpt.MaxTime);
                    if this.pParOpt.MaxGap > 0
                        options = xprsoptimset(options,'MIPRELSTOP',this.pParOpt.MaxGap); 
                    end

                    rtype = [repmat('L',[1 size(this.Aineq,1)]) repmat('E',[1 size(this.Aeq,1)])];
                    ctype = repmat('C', [1 size(this.Fobj,1)]);
                    ctype(this.intcon) = 'B';
                    %[this.ResOptimizacion,this.Fval,this.ExitFlag,this.Output] = xprsmip(this.Fobj,[this.Aineq; this.Aeq], [this.bineq; this.beq], rtype, ctype, [], [], this.lb,this.ub, x0);%, options);
                    tic
                    [this.ResOptimizacion,this.Fval,this.ExitFlag,this.Output] = xprsmip(this.Fobj,[this.Aineq; this.Aeq], [this.bineq; this.beq], rtype, ctype, [], [], this.lb,this.ub, [], options);%, options);
                    disp(['Tiempo en resolver problema optimizacion: ' num2str(toc)])
                elseif strcmp(this.pParOpt.Solver, 'FICO')
                    % por ahora nada
                    tic
                    [retcode, exitcode] = moselexec(this.NombreArchivoModeloFICO);
                    disp(['Tiempo en resolver problema optimizacion: ' num2str(toc)])
                    if retcode ~= 0
                        error = MException('cOptMILP:optimiza',...
                            ['Optimizador "' this.pParOpt.Solver ' entrega error. Retcode: ' num2str(retcode) '. Exitcode: ' num2str(exitcode) ]);
                        throw(error)
                    end
                    this.lee_y_guarda_solucion_fico();

                else
                    error = MException('cOptMILP:optimiza',...
                                       ['Optimizador "' this.pParOpt.Solver ' no está implementado']);
                    throw(error)
                end
            elseif strcmp(this.pParOpt.EstrategiaOptimizacion,'Benders')
                if this.pParOpt.ConsideraAlphaMin
                    this.COperUninodal = this.calcula_coper_sin_restricciones();
                end
                estrategia = 1;
                if estrategia == 1                    
                    if this.pParOpt.ComputoParalelo
                    	%this.optimiza_benders_paralelo();
                        this.optimiza_benders_paralelo_nuevo2();
                    else
                        this.optimiza_benders_secuencial();
                    end
                elseif estrategia == 2
                    this.optimiza_benders_primal_dual();
                elseif estrategia == 3
                    this.optimiza_benders_primal_dual_etapas();                    
                end
            else
                error = MException('cOptMILP:optimiza',...
                    ['Estrategia de optimizacion "' this.pParOpt.EstrategiaOptimizacion ' no implementada']);
                throw(error)
            end
            
            %redondea resultados
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            this.ResOptimizacion = round(this.ResOptimizacion,dec_redondeo);
            this.escribe_resultados_en_plan(this.ResOptimizacion, this.pPlanOptimo);

            if this.pParOpt.ImprimeResultadosProtocolo
                this.imprime_resultados_protocolo();
            end
            
            if this.pParOpt.ExportaResultadosFormatoExcel
                this.exporta_resultados_formato_excel();
            end
            if this.pParOpt.GraficaResultados
                this.grafica_resultados();
            end            
        end
		
        function optimiza_benders_paralelo(this)
            options = xprsoptimset('OUTPUTLOG',0);
            t_inicio = clock;
            t_inicio_master = clock;
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            id_master = this.TipoVarOpt == 1;
            cant_master = sum(id_master);
            %id_expansion_master = this.TipoVarOpt == 1 & this.SubtipoVarOpt == 1;
            fobj_master = this.Fobj(id_master);

            lb_master = this.lb(id_master);
            ub_master = this.ub(id_master);

            aineq_master = this.Aineq(this.TipoRestriccionIneq == 1,id_master);
            bineq_master = this.bineq(this.TipoRestriccionIneq == 1);

            aeq_master = this.Aeq(this.TipoRestriccionEq == 1,id_master);
            beq_master = this.beq(this.TipoRestriccionEq == 1);

            rtype_master = [repmat('L',[1 size(aineq_master,1)]) repmat('E',[1 size(aeq_master,1)])];

            id_intcon_var_orig = zeros(length(this.Fobj),1);
            id_intcon_var_orig(this.intcon) = 1;
            id_intcon_master = id_intcon_var_orig(id_master);
            intcon_master = find(id_intcon_master);
%disp('Verificar que variables de decisión de la expansión estén en bloques')

            ctype_master = repmat('C', [1 size(fobj_master,1)]);
            ctype_master(intcon_master) = 'B';
            %if this.pParOpt.MaxGap > 0
            %    options = xprsoptimset('MIPRELSTOP',this.pParOpt.MaxGap); 
            %end

            if this.iNivelDebug > 2
                % imprime problema master
                nombres_var_master = this.NombreVariables(this.TipoVarOpt == 1);
                nombres_restricciones_master = this.NombreIneq(this.TipoRestriccionIneq == 1);
                nombres_restricciones_master = [nombres_restricciones_master ; this.NombreEq(this.TipoRestriccionEq == 1)];
                this.imprime_problema_optimizacion_elementos_dados(fobj_master, [aineq_master; aeq_master], [bineq_master; beq_master], rtype_master, lb_master, ub_master, intcon_master, nombres_var_master, nombres_restricciones_master, 'milp_master_0');
                
                % define nombres de los alphas (para imprimir después)
                nombres_alpha = cell(1,this.iCantEscenarios*this.iCantEtapas);
                for j = 1: this.iCantEscenarios*this.iCantEtapas
                    [escenario, etapa] = ind2sub([this.iCantEscenarios, this.iCantEtapas],j);
                    nombres_alpha{j} = ['Alpha_S' num2str(escenario) '_E' num2str(etapa)];
                end
                nombres_cortes = cell(1,0);
            end
            
            [y_master,fval_master,exit_master,output_master] = xprsmip(fobj_master, [aineq_master; aeq_master], [bineq_master; beq_master],rtype_master, ctype_master, [], [], lb_master,ub_master, [],options);%, options);
            y_master = round(y_master, dec_redondeo);
            dt_master = etime(clock,t_inicio_master);
            
            % aumenta dimensiones para incluir los alphas 
            alpha = zeros(1,this.iCantEscenarios*this.iCantEtapas);
            aineq_master = [aineq_master zeros(size(aineq_master,1),length(alpha))];
            aeq_master = [aeq_master zeros(size(aeq_master,1),length(alpha))];
            q = (1 + this.pParOpt.TasaDescuento);
            vector_etapas = 1:this.pParOpt.DeltaEtapa:this.iCantEtapas;            
            descuento_etapas = 1./q.^vector_etapas;
            pesos_alpha = zeros(this.iCantEscenarios*this.iCantEtapas,1);
            for j = 1:this.iCantEscenarios*this.iCantEtapas
                [escenario, etapa] = ind2sub([this.iCantEscenarios, this.iCantEtapas],j);
                peso_escenario = this.pAdmSc.entrega_peso_escenario(escenario);
                peso_etapa = descuento_etapas(etapa);
                pesos_alpha(j) = round(peso_escenario*peso_etapa,dec_redondeo);
            end
            fobj_master = [fobj_master; pesos_alpha];
            %fobj_master = [fobj_master; ones(this.iCantEscenarios*this.iCantEtapas,1)];
            %lb_master = [lb_master -inf*ones(1,length(pesos_alpha))];
            %ub_master = [ub_master inf*ones(1,length(pesos_alpha))];
            %ctype_master = [ctype_master repmat('C', [1 length(pesos_alpha)])];

            lb_alphas = zeros(1,this.iCantEscenarios*this.iCantEtapas);
            for j = 1:this.iCantEscenarios*this.iCantEtapas
                %[escenario, etapa] = ind2sub([this.iCantEscenarios, this.iCantEtapas],j);
                lb_alphas(j) = this.COperUninodal(j)/pesos_alpha(j);
            end
            if this.pParOpt.ConsideraAlphaMin
                lb_master = [lb_master lb_alphas];
            else
            	lb_master = [lb_master zeros(1,this.iCantEscenarios*this.iCantEtapas)];
            end
            %lb_master = [lb_master -inf*ones(1,this.iCantEscenarios*this.iCantEtapas)];
            ub_master = [ub_master inf*ones(1,this.iCantEscenarios*this.iCantEtapas)];
            ctype_master = [ctype_master repmat('C', [1 this.iCantEscenarios*this.iCantEtapas])];
            
            % define contenedores para los cortes
            bineq_cortes = [];
            aineq_cortes = zeros(0, length(fobj_master));
            cant_cortes = 0;
            
            z_upper = 0;
            z_lower = 0;
            
            best_z_upper = inf;
            best_sol = 0;
            texto = sprintf('%-5s %-5s %-15s %-15s %-15s %-15s %-10s %-10s %-10s','It', 'Sol', 'ZUpper(k)', 'ZUpperB', 'ZLower(k)', 'Gap%', 'Dtmaster', 'Dtslave', 'DtTotal');
            disp(texto)

            % verifica que cantidad de variables de expansión en esclavos sea siempre la misma
            cant_expansion_en_slave_todos = zeros(this.iCantEscenarios*this.iCantEtapas,1);
            parfor j = 1:this.iCantEscenarios*this.iCantEtapas
                [etapa,escenario]=ind2sub([this.iCantEtapas, this.iCantEscenarios],j);
                id_slave = (this.TipoVarOpt == 1 & this.SubtipoVarOpt == 3 & this.EscenarioVarOpt == escenario & this.EtapaVarOpt == etapa) | ...
                    (this.TipoVarOpt == 2 &  this.EscenarioVarOpt == escenario & this.EtapaVarOpt == etapa);
                id_expansion_en_slave = id_master & id_slave;
                pos_sol_expansion_para_slave = find(id_expansion_en_slave); % posiciones de solución de expansión en variable y_master

                cant_expansion_en_slave_todos(j) = length(pos_sol_expansion_para_slave);
            end
            cant_expansion_en_slave = unique(cant_expansion_en_slave_todos);
            if length(cant_expansion_en_slave) > 1
                error = MException('cOptMILP:optimiza_benders_paralelo',...
                    'Cantidad de variables expansión difere en las distintas etapas. No se puede simular en forma paralela');
                throw(error)
            end
            
            for k = 1:this.pParOpt.MaxIterBenders
                if k > 1
                    % resuelve problema master con los cortes
                    t_inicio_master = clock;
                    rtype_master = [repmat('L',[1 size(aineq_master,1)]) repmat('E',[1 size(aeq_master,1)]) repmat('G',[1 size(aineq_cortes,1)])];
                    if this.iNivelDebug > 2
                        % imprime problema master
                        nombres_variables = [nombres_var_master nombres_alpha];
                        nombres_restricciones = [nombres_restricciones_master ; nombres_cortes];
                        this.imprime_problema_optimizacion_elementos_dados(fobj_master, [aineq_master; aeq_master; aineq_cortes], [bineq_master; beq_master; bineq_cortes], rtype_master, lb_master, ub_master, intcon_master, nombres_variables, nombres_restricciones, ['milp_master_' num2str(k)]);
                    end

                    [y_master,fval_master,exit_master,output_master] = xprsmip(fobj_master, [aineq_master; aeq_master;aineq_cortes], [bineq_master; beq_master; bineq_cortes],rtype_master, ctype_master, [], [], lb_master,ub_master, [], options);%, options);
                    dt_master = etime(clock,t_inicio_master);
                    y_master = round(y_master, dec_redondeo);
                    z_lower(k) = fval_master;
                else
                    z_lower(k) = 0;                    
                end
                z_upper(k) = fobj_master(1:cant_master)'*y_master(1:cant_master);
                fval_slave_oper = zeros(this.iCantEscenarios*this.iCantEtapas,1);
                bineq_cortes_oper = zeros(this.iCantEscenarios*this.iCantEtapas,1);
                lambda_aineq_cortes_oper = zeros(this.iCantEscenarios*this.iCantEtapas,cant_expansion_en_slave);
                pos_expansion_en_slave_cortes_oper = zeros(this.iCantEscenarios*this.iCantEtapas,cant_expansion_en_slave);
                nombres_cortes_oper = cell(this.iCantEscenarios*this.iCantEtapas,1);
                
                t_inicio_slave = clock;
                parfor j = 1:this.iCantEscenarios*this.iCantEtapas
                    [etapa,escenario]=ind2sub([this.iCantEtapas, this.iCantEscenarios],j);

                    % 1. elimina variables de decisión de expansión de la función objetivo. Después de eliminan las variables que no corresponden
                    peso_caso = pesos_alpha(j);
                    fobj_slave = this.Fobj/peso_caso;
                    fobj_slave(this.TipoVarOpt == 1) = 0;

                    % 2. Identifica todas variables válidas para el escenario y la etapa. Incluyendo las decisiones de expansión del problema master
                    id_slave = (this.TipoVarOpt == 1 & this.SubtipoVarOpt == 3 & this.EscenarioVarOpt == escenario & this.EtapaVarOpt == etapa) | ...
                        (this.TipoVarOpt == 2 &  this.EscenarioVarOpt == escenario & this.EtapaVarOpt == etapa);
                    %id_expansion_en_slave = this.TipoVarOpt == 1 & this.SubtipoVarOpt == 1 & this.EscenarioVarOpt == escenario & this.EtapaVarOpt <= etapa;

                    fobj_slave = fobj_slave(id_slave);
                    lb_slave = this.lb(id_slave);
                    ub_slave = this.ub(id_slave);

                    aineq_slave = this.Aineq(this.TipoRestriccionIneq == 2 & this.EscenarioRestriccionIneq == escenario & this.EtapaRestriccionIneq == etapa,id_slave);
                    bineq_slave = this.bineq(this.TipoRestriccionIneq == 2 & this.EscenarioRestriccionIneq == escenario & this.EtapaRestriccionIneq == etapa);

                    aeq_slave = this.Aeq(this.TipoRestriccionEq == 2 & this.EscenarioRestriccionEq == escenario & this.EtapaRestriccionEq == etapa,id_slave);
                    beq_slave = this.beq(this.TipoRestriccionEq == 2 & this.EscenarioRestriccionEq == escenario & this.EtapaRestriccionEq == etapa);

                    % agrega restricciones que fija el valor de expansión de las variables válidas de expansión (correspondientes a la etapa y escenario)
                    id_expansion_en_slave = id_master & id_slave;
                    pos_sol_expansion_para_slave = find(id_expansion_en_slave); % posiciones de solución de expansión en variable y_master
                    sol_expansion = y_master(pos_sol_expansion_para_slave);

                    %cant_expansion_en_slave = length(pos_sol_expansion_para_slave);
                    aeq_expansion_slave = zeros(cant_expansion_en_slave, length(fobj_slave));
                    aeq_expansion_slave(1:cant_expansion_en_slave, 1:cant_expansion_en_slave) = diag(ones(cant_expansion_en_slave,1));
                    beq_expansion_slave = sol_expansion;

                    % agrega restricción de igualdad con resultado de expansión de la transmisión

                    rtype_slave = [repmat('L',[1 size(aineq_slave,1)]) repmat('E',[1 size(aeq_slave,1)]) repmat('E',[1 size(aeq_expansion_slave,1)])];

                    if this.iNivelDebug > 2
                        % imprime problema master
                        nombres_variables = this.NombreVariables(id_slave);
                        id_ineq = this.TipoRestriccionIneq == 2 & this.EscenarioRestriccionIneq == escenario & this.EtapaRestriccionIneq == etapa;
                        id_eq = this.TipoRestriccionEq == 2 & this.EscenarioRestriccionEq == escenario & this.EtapaRestriccionEq == etapa;
                        nombres_restricciones = this.NombreIneq(id_ineq);
                        nombres_restricciones = [nombres_restricciones ; this.NombreEq(id_eq)];
                        nombres_eq_fija_exp_en_slave = cell(1,cant_expansion_en_slave);
                        for ii = 1:cant_expansion_en_slave
                            nombres_eq_fija_exp_en_slave{ii} = ['Fija_Sol_' nombres_variables{ii}];
                        end
                        nombres_restricciones = [nombres_restricciones; nombres_eq_fija_exp_en_slave'];
                        this.imprime_problema_optimizacion_elementos_dados(fobj_slave, [aineq_slave; aeq_slave; aeq_expansion_slave], [bineq_slave; beq_slave; beq_expansion_slave], rtype_slave, lb_slave, ub_slave, [], nombres_variables, nombres_restricciones, ['lp_slave_It' num2str(k) '_S' num2str(escenario) '_E' num2str(etapa)]);
                    end
                    [x_slave,fval_slave,flag_slave,output_slave, lambda_slave] = xprslp(fobj_slave, [aineq_slave; aeq_slave; aeq_expansion_slave], [bineq_slave; beq_slave; beq_expansion_slave],rtype_slave, lb_slave,ub_slave,options);%, options);

                    % agrega costos de operación a z_upper
                    fval_slave_oper(j) = fval_slave*peso_caso;

                    lambda_slave.lin = round(lambda_slave.lin, dec_redondeo);
                    % agrega corte
                    %cant_cortes = cant_cortes + 1;
                    pos_id_expansion_slave_en_master = find(id_expansion_en_slave);
                    %pos_alpha = etapa + this.iCantEtapas*(escenario -1);
                    bineq_cortes_oper(j,1) = fval_slave + lambda_slave.lin(end-cant_expansion_en_slave+1:end)'*sol_expansion;
                    lambda_aineq_cortes_oper(j,:) = lambda_slave.lin(end-cant_expansion_en_slave+1:end);
                    pos_expansion_en_slave_cortes_oper(j,:) = pos_id_expansion_slave_en_master;

                    if this.iNivelDebug > 2
                        % agrega nombre cortes
                        nombres_cortes_oper{j} = ['Corte_It' num2str(k) '_S' num2str(escenario) '_E' num2str(etapa)];
                    end
                end
                
                z_upper(k) = z_upper(k) + sum(fval_slave_oper);
                for j = 1:this.iCantEscenarios*this.iCantEtapas
                    cant_cortes = cant_cortes + 1;
                    %pos_id_expansion_slave_en_master = find(id_expansion_en_slave_cortes(j,:));
                    aineq_cortes(cant_cortes,pos_expansion_en_slave_cortes_oper(j,:)) = lambda_aineq_cortes_oper(j,:);
                    aineq_cortes(cant_cortes, cant_master + j) = 1;
                end
                bineq_cortes = [bineq_cortes; bineq_cortes_oper];
                
                dt_slave = etime(clock,t_inicio_slave);
                if this.iNivelDebug > 2
                    % agrega nombre cortes
                    nombres_cortes = [nombres_cortes; nombres_cortes_oper];
                end
                    
                texto_nueva_sol = '';
                if z_upper(k) < best_z_upper
                    best_z_upper = z_upper(k);
                    best_sol = y_master;
                    texto_nueva_sol = '*';
                end
                dt_total = etime(clock, t_inicio);
                texto = sprintf('%-5s %-5s %-15s %-15s %-15s %-15s %-10s %-10s %-10s',num2str(k), texto_nueva_sol, num2str(round(z_upper(k),5)), num2str(round(best_z_upper,5)), ...
                    num2str(round(z_lower(k),5)), num2str(round((best_z_upper-z_lower(k))/best_z_upper*100,5)), num2str(dt_master), num2str(dt_slave), num2str(dt_total));
                disp(texto)
                
                if (best_z_upper-z_lower(k))/best_z_upper < 0.0001
                    break
                end

                if this.iNivelDebug > 3
                    % verifica que suma de bineq de cortes en cada
                    % escenario y etapa coincida con solucion completa
                    fobj_slave = this.Fobj;
                    fobj_slave(this.TipoVarOpt == 1) = 0;

                    % 2. Identifica todas variables válidas para el escenario y la etapa. Incluyendo las decisiones de expansión del problema master
                    id_slave = (this.TipoVarOpt == 1 & this.SubtipoVarOpt == 3) | (this.TipoVarOpt == 2);
                    %id_expansion_en_slave = this.TipoVarOpt == 1 & this.SubtipoVarOpt == 1 & this.EscenarioVarOpt == escenario & this.EtapaVarOpt <= etapa;

                    fobj_slave = fobj_slave(id_slave);
                    lb_slave = this.lb(id_slave);
                    ub_slave = this.ub(id_slave);

                    aineq_slave = this.Aineq(this.TipoRestriccionIneq == 2,id_slave);
                    bineq_slave = this.bineq(this.TipoRestriccionIneq == 2);

                    aeq_slave = this.Aeq(this.TipoRestriccionEq == 2,id_slave);
                    beq_slave = this.beq(this.TipoRestriccionEq == 2);

                    % agrega restricciones que fija el valor de expansión de las variables válidas de expansión (correspondientes a la etapa y escenario)
                    id_expansion_en_slave = id_master & id_slave;
                    pos_sol_expansion_para_slave = find(id_expansion_en_slave); % posiciones de solución de expansión en variable y_master
                    sol_expansion = y_master(pos_sol_expansion_para_slave);

                    %cant_expansion_en_slave = length(pos_sol_expansion_para_slave);
                    cant_expansion_en_slave_debug = length(pos_sol_expansion_para_slave);
                    aeq_expansion_slave = zeros(cant_expansion_en_slave_debug, length(fobj_slave));
                    aeq_expansion_slave(1:cant_expansion_en_slave_debug, 1:cant_expansion_en_slave_debug) = diag(ones(cant_expansion_en_slave_debug,1));
                    beq_expansion_slave = sol_expansion;

                    % agrega restricción de igualdad con resultado de expansión de la transmisión

                    rtype_slave = [repmat('L',[1 size(aineq_slave,1)]) repmat('E',[1 size(aeq_slave,1)]) repmat('E',[1 size(aeq_expansion_slave,1)])];

                    % imprime problema master
                    nombres_variables_debug = this.NombreVariables(id_slave);
                    id_ineq = this.TipoRestriccionIneq == 2;
                    id_eq = this.TipoRestriccionEq == 2;
                    nombres_restricciones_debug = this.NombreIneq(id_ineq);
                    nombres_restricciones_debug = [nombres_restricciones_debug ; this.NombreEq(id_eq)];
                    nombres_eq_fija_exp_en_slave_debug = cell(1,cant_expansion_en_slave_debug);
                    for ii = 1:cant_expansion_en_slave_debug
                        nombres_eq_fija_exp_en_slave_debug{ii} = ['Fija_Sol_' nombres_variables_debug{ii}];
                    end
                    nombres_restricciones_debug = [nombres_restricciones_debug; nombres_eq_fija_exp_en_slave_debug'];
                    this.imprime_problema_optimizacion_elementos_dados(fobj_slave, [aineq_slave; aeq_slave; aeq_expansion_slave], [bineq_slave; beq_slave; beq_expansion_slave], rtype_slave, lb_slave, ub_slave, [], nombres_variables_debug, nombres_restricciones_debug, ['lp_slave_It' num2str(k) 'completo']);

                        [x_slave,fval_slave,flag_slave,output_slave, lambda_slave] = xprslp(fobj_slave, [aineq_slave; aeq_slave; aeq_expansion_slave], [bineq_slave; beq_slave; beq_expansion_slave],rtype_slave, lb_slave,ub_slave,options);%, options);

                    % agrega costos de operación a z_upper
                    fval_slave_oper_completo = fval_slave;

                    %lambda_slave.lin = round(lambda_slave.lin, dec_redondeo);
                    % agrega corte
                    %cant_cortes = cant_cortes + 1;
                    pos_id_expansion_slave_en_master = find(id_expansion_en_slave);
                    %pos_alpha = etapa + this.iCantEtapas*(escenario -1);
                    bineq_cortes_completo = fval_slave + lambda_slave.lin(end-cant_expansion_en_slave_debug+1:end)'*sol_expansion;
                    lambda_aineq_cortes_oper_completo = lambda_slave.lin(end-cant_expansion_en_slave_debug+1:end);
                    pos_expansion_en_slave_cortes_oper_completo = pos_id_expansion_slave_en_master;
                end                
            end
            % optimiza nuevamente fijando la solución y guarda solución encontrada
            id_sol_expansion_en_slave = (this.TipoVarOpt == 1 & this.SubtipoVarOpt == 1);
            pos_sol_expansion = find(id_sol_expansion_en_slave);
            this.lb(pos_sol_expansion) = best_sol(pos_sol_expansion);
            this.ub(pos_sol_expansion) = best_sol(pos_sol_expansion);
            rtype = [repmat('L',[1 size(this.Aineq,1)]) repmat('E',[1 size(this.Aeq,1)])];
            ctype = repmat('C', [1 size(this.Fobj,1)]);
            ctype(this.intcon) = 'B';
            [this.ResOptimizacion,this.Fval,this.ExitFlag,this.Output] = xprsmip(this.Fobj,[this.Aineq; this.Aeq], [this.bineq; this.beq], rtype, ctype, [], [], this.lb,this.ub, []);%, options);            
        end

        function optimiza_benders_secuencial(this)
            options = xprsoptimset('OUTPUTLOG',0);
            if this.iNivelDebug > 1
                prot = cProtocolo.getInstance;
            end
% pos_cortes_primarios = zeros(length(this.VarExpansion),1);
% for ii = 1:length(this.VarExpansion)
%     if strcmp(this.VarExpansion(ii).entrega_tipo_proyecto(), 'AS') || ...
%             (strcmp(this.VarExpansion(ii).entrega_tipo_proyecto(), 'AT') && this.VarExpansion(ii).EsUprating)
%         pos_cortes_primarios(ii) = 0;
%     else
%         pos_cortes_primarios(ii) = 1;
%     end
% end
    
            t_inicio = clock;
            t_inicio_master = clock;
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            id_master = this.TipoVarOpt == 1;
            cant_master = sum(id_master);
            %id_expansion_master = this.TipoVarOpt == 1 & this.SubtipoVarOpt == 1;
            fobj_master = this.Fobj(id_master);

            lb_master = this.lb(id_master);
            ub_master = this.ub(id_master);

            aineq_master = this.Aineq(this.TipoRestriccionIneq == 1,id_master);
            bineq_master = this.bineq(this.TipoRestriccionIneq == 1);

            aeq_master = this.Aeq(this.TipoRestriccionEq == 1,id_master);
            beq_master = this.beq(this.TipoRestriccionEq == 1);

            rtype_master = [repmat('L',[1 size(aineq_master,1)]) repmat('E',[1 size(aeq_master,1)])];

            id_intcon_var_orig = zeros(length(this.Fobj),1);
            id_intcon_var_orig(this.intcon) = 1;
            id_intcon_master = id_intcon_var_orig(id_master);
            intcon_master = find(id_intcon_master);
%disp('Verificar que variables de decisión de la expansión estén en bloques')

            ctype_master = repmat('C', [1 size(fobj_master,1)]);
            ctype_master(intcon_master) = 'B';
            %if this.pParOpt.MaxGap > 0
            %    options = xprsoptimset('MIPRELSTOP',this.pParOpt.MaxGap); 
            %end

            if this.iNivelDebug > 1
                % imprime problema master
                nombres_var_master = this.NombreVariables(this.TipoVarOpt == 1);
                nombres_restricciones_master = this.NombreIneq(this.TipoRestriccionIneq == 1);
                nombres_restricciones_master = [nombres_restricciones_master ; this.NombreEq(this.TipoRestriccionEq == 1)];
                if this.iNivelDebug > 2
                    this.imprime_problema_optimizacion_elementos_dados(fobj_master, [aineq_master; aeq_master], [bineq_master; beq_master], rtype_master, lb_master, ub_master, intcon_master, nombres_var_master, nombres_restricciones_master, 'milp_master_0');
                end
                
                % define nombres de los alphas (para imprimir después)
                nombres_alpha = cell(1,this.iCantEscenarios*this.iCantEtapas);
                for j = 1:this.iCantEscenarios*this.iCantEtapas
                    [escenario, etapa] = ind2sub([this.iCantEscenarios, this.iCantEtapas],j);
                    nombres_alpha{j} = ['Alpha_S' num2str(escenario) '_E' num2str(etapa)];
                end
                nombres_cortes = cell(1,0);
            end
            
            [y_master,fval_master,exit_master,output_master] = xprsmip(fobj_master, [aineq_master; aeq_master], [bineq_master; beq_master],rtype_master, ctype_master, [], [], lb_master,ub_master, [],options);%, options);
            y_master = round(y_master, dec_redondeo);
            dt_master = etime(clock,t_inicio_master);
            
            % aumenta dimensiones para incluir los alphas 
            alpha = zeros(1,this.iCantEscenarios*this.iCantEtapas);
            aineq_master = [aineq_master zeros(size(aineq_master,1),length(alpha))];
            aeq_master = [aeq_master zeros(size(aeq_master,1),length(alpha))];
            q = (1 + this.pParOpt.TasaDescuento);
            vector_etapas = 1:this.pParOpt.DeltaEtapa:this.iCantEtapas;            
            descuento_etapas = 1./q.^vector_etapas;
            pesos_alpha = zeros(this.iCantEscenarios*this.iCantEtapas,1);
            for j = 1:this.iCantEscenarios*this.iCantEtapas
                [escenario, etapa] = ind2sub([this.iCantEscenarios, this.iCantEtapas],j);            
                peso_escenario = this.pAdmSc.entrega_peso_escenario(escenario);
                peso_etapa = descuento_etapas(etapa);
                pesos_alpha(j) = round(peso_escenario*peso_etapa,dec_redondeo);
            end
            
            fobj_master = [fobj_master; pesos_alpha];
            %fobj_master = [fobj_master; ones(this.iCantEscenarios*this.iCantEtapas,1)];
            %lb_master = [lb_master -inf*ones(1,length(pesos_alpha))];
            %ub_master = [ub_master inf*ones(1,length(pesos_alpha))];
            %ctype_master = [ctype_master repmat('C', [1 length(pesos_alpha)])];

            lb_alphas = zeros(1,this.iCantEscenarios*this.iCantEtapas);
lb_alphas_gap = zeros(1,this.iCantEscenarios*this.iCantEtapas);
            for j = 1:this.iCantEscenarios*this.iCantEtapas
                %[escenario, etapa] = ind2sub([this.iCantEscenarios, this.iCantEtapas],j);            
                lb_alphas(j) = this.COperUninodal(j)/pesos_alpha(j);
            end
lb_alphas_gap = this.COperUninodal;            
lb_alphas = zeros(1,this.iCantEscenarios*this.iCantEtapas);
            %lb_master = [lb_master zeros(1,this.iCantEscenarios*this.iCantEtapas)];
            lb_master = [lb_master lb_alphas];

            %lb_master = [lb_master -inf*ones(1,this.iCantEscenarios*this.iCantEtapas)];
            ub_master = [ub_master inf*ones(1,this.iCantEscenarios*this.iCantEtapas)];
            ctype_master = [ctype_master repmat('C', [1 this.iCantEscenarios*this.iCantEtapas])];
            
            % define contenedores para los cortes
            bineq_cortes = [];
            aineq_cortes = zeros(0, length(fobj_master));
            cant_cortes = 0;
            
            z_upper = 0;
            z_lower = 0;
z_lower_gap = 0;            
            best_z_upper = inf;
            best_sol = 0;
            %texto = sprintf('%-5s %-5s %-15s %-15s %-15s %-15s %-10s %-10s %-10s','It', 'Sol', 'ZUpper(k)', 'ZUpperB', 'ZLower(k)', 'Gap%', 'Dtmaster', 'Dtslave', 'DtTotal');
texto = sprintf('%-5s %-5s %-15s %-15s %-15s %-15s %-15s %-10s %-10s %-10s','It', 'Sol', 'ZUpper(k)', 'ZUpperB', 'ZLower(k)', 'Gap%', 'GapReal%', 'Dtmaster', 'Dtslave', 'DtTotal');
            disp(texto)

            % verifica que cantidad de variables de expansión en esclavos sea siempre la misma
            cant_expansion_en_slave_todos = zeros(this.iCantEscenarios*this.iCantEtapas,1);
            for j = 1:this.iCantEscenarios*this.iCantEtapas
                [etapa,escenario]=ind2sub([this.iCantEtapas, this.iCantEscenarios],j);
                id_slave = (this.TipoVarOpt == 1 & this.SubtipoVarOpt == 3 & this.EscenarioVarOpt == escenario & this.EtapaVarOpt == etapa) | ...
                    (this.TipoVarOpt == 2 &  this.EscenarioVarOpt == escenario & this.EtapaVarOpt == etapa);
                id_expansion_en_slave = id_master & id_slave;
                pos_sol_expansion_para_slave = find(id_expansion_en_slave); % posiciones de solución de expansión en variable y_master

                cant_expansion_en_slave_todos(j) = length(pos_sol_expansion_para_slave);
            end
            cant_expansion_en_slave = unique(cant_expansion_en_slave_todos);
            if length(cant_expansion_en_slave) > 1
                error = MException('cOptMILP:optimiza_benders_secuencial',...
                    'Cantidad de variables expansión difere en las distintas etapas. No se puede simular en forma paralela');
                throw(error)
            end
            
            for k = 1:this.pParOpt.MaxIterBenders
                if k > 1
                    % resuelve problema master con los cortes
                    t_inicio_master = clock;
                    rtype_master = [repmat('L',[1 size(aineq_master,1)]) repmat('E',[1 size(aeq_master,1)]) repmat('G',[1 size(aineq_cortes,1)])];
                    if this.iNivelDebug > 1
                        % imprime problema master
                        nombres_variables = [nombres_var_master nombres_alpha];
                        nombres_restricciones = [nombres_restricciones_master ; nombres_cortes];
                        if this.iNivelDebug > 2
                            this.imprime_problema_optimizacion_elementos_dados(fobj_master, [aineq_master; aeq_master; aineq_cortes], [bineq_master; beq_master; bineq_cortes], rtype_master, lb_master, ub_master, intcon_master, nombres_variables, nombres_restricciones, ['milp_master_' num2str(k)]);
                        end
                    end

                    [y_master,fval_master,exit_master,output_master] = xprsmip(fobj_master, [aineq_master; aeq_master;aineq_cortes], [bineq_master; beq_master; bineq_cortes],rtype_master, ctype_master, [], [], lb_master,ub_master, [], options);%, options);
                    dt_master = etime(clock,t_inicio_master);
                    y_master = round(y_master, dec_redondeo);
                    z_lower(k) = fval_master;
z_lower_gap(k) = fobj_master(1:cant_master)'*y_master(1:cant_master) +sum(lb_alphas_gap);
                    if this.iNivelDebug > 1
                        id_decision_expansion_prot = this.TipoVarOpt == 1 & this.SubtipoVarOpt == 1;
                        pos_sol_expansion_prot = find(id_decision_expansion_prot); % posiciones de solución de expansión en variable y_master
                        sol = y_master(pos_sol_expansion_prot);
                        nombre_validos = nombres_variables(pos_sol_expansion_prot);
                        texto_alpha = '';
                        for ii = 1:this.iCantEscenarios*this.iCantEtapas
                            [etapa,escenario]=ind2sub([this.iCantEtapas, this.iCantEscenarios],ii);
                            texto_alpha = [texto_alpha sprintf('%-10s %-10s',['Alpha_S' num2str(escenario) ' _E' num2str(etapa)],num2str(y_master(cant_master + ii)))];
                        end
%                        prot.imprime_vector_texto(nombre_validos(sol == 1)', ['\nSol. expansion en iteracion ' num2str(k)]);
                        texto = sprintf('%-10s %-10s %-15s %-10s %-15s %-10s',...
                            'Cinv sol: ',num2str(fobj_master(1:cant_master)'*y_master(1:cant_master)),...
                            'Sum alpha: ', num2str(fobj_master(cant_master+1:end)'*y_master(cant_master+1:end)), ...
                            'Fval master: ', num2str(fval_master));
                        texto = [texto texto_alpha];
                        prot.imprime_texto(texto);
                    end
%evalua solución óptima
% lb_optima = lb_master;
% ub_optima = ub_master;
% etapas_optima = [1 1 1 1 1 1 1 1 1 1 1 1 1 1 3 3 3 3 3];
% proy_optimos = [2 3 4 5 6 10 12 14 16 18 41 47 53 59 1 7 8 20 71];
% for ii = 1:length(this.VarExpansion)
% 	id_var = this.VarExpansion(ii).entrega_indice();
%     id_expansion_desde = this.VarExpansion(ii).entrega_varopt_expansion('Decision', 1);
%     id_expansion_hasta = id_expansion_desde + this.iCantEtapas - 1;
%     ub_optima(id_expansion_desde:id_expansion_hasta) = 0;
%     if ~isempty(find(ismember(proy_optimos, id_var), 1))
%         indice_opt = find(ismember(proy_optimos, id_var));
%         etapa = etapas_optima(indice_opt);
%         lb_optima(id_expansion_desde + etapa - 1) = 1;
%         ub_optima(id_expansion_desde + etapa - 1) = 1;
%     end
% end
% [y_test,fval_test,exit_test,output_test] = xprsmip(fobj_master, [aineq_master; aeq_master;aineq_cortes], [bineq_master; beq_master; bineq_cortes],rtype_master, ctype_master, [], [], lb_optima,ub_optima, [],options);%, options);
% texto = sprintf('%-20s %-15s %-20s %-15s %-20s %-15s',...
%     'Cinv opt: ',num2str(fobj_master(1:cant_master)'*y_test(1:cant_master)),...
%     'Suma alpha opt: ', num2str(fobj_master(cant_master+1:end)'*y_test(cant_master+1:end)), ...
%     'Fval opt: ', num2str(fval_test));
% prot.imprime_texto(texto);
% 
%sol_opt = y_test(pos_sol_expansion_prot);
%nombre_validos = nombres_variables(pos_sol_expansion_prot);
%prot.imprime_vector_texto(nombre_validos(sol_opt == 1)', ['Sol. optima ' num2str(k)]);

% linlinlin = 1

                else
                    z_lower(k) = 0;
z_lower_gap(k) = sum(lb_alphas_gap);                    
                end
                z_upper(k) = fobj_master(1:cant_master)'*y_master(1:cant_master);
                fval_slave_oper = zeros(this.iCantEscenarios*this.iCantEtapas,1);
                bineq_cortes_oper = zeros(this.iCantEscenarios*this.iCantEtapas,1);
                lambda_aineq_cortes_oper = zeros(this.iCantEscenarios*this.iCantEtapas,cant_expansion_en_slave);
                pos_expansion_en_slave_cortes_oper = zeros(this.iCantEscenarios*this.iCantEtapas,cant_expansion_en_slave);
                nombres_cortes_oper = cell(this.iCantEscenarios*this.iCantEtapas,1);
                
                t_inicio_slave = clock;
                for j = 1:this.iCantEscenarios*this.iCantEtapas
                    [etapa,escenario]=ind2sub([this.iCantEtapas, this.iCantEscenarios],j);

                    % 1. elimina variables de decisión de expansión de la función objetivo. Después de eliminan las variables que no corresponden
                    peso_caso = pesos_alpha(j);
                    fobj_slave = this.Fobj/peso_caso;
                    fobj_slave(this.TipoVarOpt == 1) = 0;

                    % 2. Identifica todas variables válidas para el escenario y la etapa. Incluyendo las decisiones de expansión del problema master
                    id_slave = (this.TipoVarOpt == 1 & this.SubtipoVarOpt == 3 & this.EscenarioVarOpt == escenario & this.EtapaVarOpt == etapa) | ...
                        (this.TipoVarOpt == 2 &  this.EscenarioVarOpt == escenario & this.EtapaVarOpt == etapa);
                    %id_expansion_en_slave = this.TipoVarOpt == 1 & this.SubtipoVarOpt == 1 & this.EscenarioVarOpt == escenario & this.EtapaVarOpt <= etapa;

                    fobj_slave = fobj_slave(id_slave);
                    lb_slave = this.lb(id_slave);
                    ub_slave = this.ub(id_slave);

                    aineq_slave = this.Aineq(this.TipoRestriccionIneq == 2 & this.EscenarioRestriccionIneq == escenario & this.EtapaRestriccionIneq == etapa,id_slave);
                    bineq_slave = this.bineq(this.TipoRestriccionIneq == 2 & this.EscenarioRestriccionIneq == escenario & this.EtapaRestriccionIneq == etapa);

                    aeq_slave = this.Aeq(this.TipoRestriccionEq == 2 & this.EscenarioRestriccionEq == escenario & this.EtapaRestriccionEq == etapa,id_slave);
                    beq_slave = this.beq(this.TipoRestriccionEq == 2 & this.EscenarioRestriccionEq == escenario & this.EtapaRestriccionEq == etapa);

                    % agrega restricciones que fija el valor de expansión de las variables válidas de expansión (correspondientes a la etapa y escenario)
                    id_expansion_en_slave = id_master & id_slave;
                    pos_sol_expansion_para_slave = find(id_expansion_en_slave); % posiciones de solución de expansión en variable y_master
                    sol_expansion = y_master(pos_sol_expansion_para_slave);

                    %cant_expansion_en_slave = length(pos_sol_expansion_para_slave);
                    aeq_expansion_slave = zeros(cant_expansion_en_slave, length(fobj_slave));
                    aeq_expansion_slave(1:cant_expansion_en_slave, 1:cant_expansion_en_slave) = diag(ones(cant_expansion_en_slave,1));
                    beq_expansion_slave = sol_expansion;

                    % agrega restricción de igualdad con resultado de expansión de la transmisión

                    rtype_slave = [repmat('L',[1 size(aineq_slave,1)]) repmat('E',[1 size(aeq_slave,1)]) repmat('E',[1 size(aeq_expansion_slave,1)])];

                    if this.iNivelDebug > 1
                        % imprime problema master
                        nombres_variables = this.NombreVariables(id_slave);
                        id_ineq = this.TipoRestriccionIneq == 2 & this.EscenarioRestriccionIneq == escenario & this.EtapaRestriccionIneq == etapa;
                        id_eq = this.TipoRestriccionEq == 2 & this.EscenarioRestriccionEq == escenario & this.EtapaRestriccionEq == etapa;
                        nombres_restricciones = this.NombreIneq(id_ineq);
                        nombres_restricciones = [nombres_restricciones ; this.NombreEq(id_eq)];
                        nombres_eq_fija_exp_en_slave = cell(1,cant_expansion_en_slave);
                        for ii = 1:cant_expansion_en_slave
                            nombres_eq_fija_exp_en_slave{ii} = ['Fija_Sol_' nombres_variables{ii}];
                        end
                        nombres_restricciones = [nombres_restricciones; nombres_eq_fija_exp_en_slave'];
                        if this.iNivelDebug > 2
                            this.imprime_problema_optimizacion_elementos_dados(fobj_slave, [aineq_slave; aeq_slave; aeq_expansion_slave], [bineq_slave; beq_slave; beq_expansion_slave], rtype_slave, lb_slave, ub_slave, [], nombres_variables, nombres_restricciones, ['lp_slave_It' num2str(k) '_S' num2str(escenario) '_E' num2str(etapa)]);
                        end
                    end
                    [x_slave,fval_slave,flag_slave,output_slave, lambda_slave] = xprslp(fobj_slave, [aineq_slave; aeq_slave; aeq_expansion_slave], [bineq_slave; beq_slave; beq_expansion_slave],rtype_slave, lb_slave,ub_slave,options);%, options);

                    % agrega costos de operación a z_upper
                    fval_slave_oper(j) = fval_slave*peso_caso;

                    %lambda_slave.lin = round(lambda_slave.lin, dec_redondeo);
                    % agrega corte
                    %cant_cortes = cant_cortes + 1;
                    pos_id_expansion_slave_en_master = find(id_expansion_en_slave);
                    %pos_alpha = etapa + this.iCantEtapas*(escenario -1);
                    bineq_cortes_oper(j,1) = fval_slave + lambda_slave.lin(end-cant_expansion_en_slave+1:end)'*sol_expansion;
                    lambda_aineq_cortes_oper(j,:) = lambda_slave.lin(end-cant_expansion_en_slave+1:end);
                    pos_expansion_en_slave_cortes_oper(j,:) = pos_id_expansion_slave_en_master;
% lambda_alternativo = lambda_slave.lin(end-cant_expansion_en_slave+1:end);
% lambda_alternativo(pos_cortes_primarios == 0) = 0;
% bineq_cortes_oper(j,1) = fval_slave + lambda_alternativo'*sol_expansion;
% lambda_aineq_cortes_oper(j,:) = lambda_alternativo;
                    if this.iNivelDebug > 1
                        % agrega nombre cortes
                        nombres_cortes_oper{j} = ['Corte_It' num2str(k) '_S' num2str(escenario) '_E' num2str(etapa)];
                    end
                end
                
                z_upper(k) = z_upper(k) + sum(fval_slave_oper);
                for j = 1:this.iCantEscenarios*this.iCantEtapas
                    cant_cortes = cant_cortes + 1;
                    %pos_id_expansion_slave_en_master = find(id_expansion_en_slave_cortes(j,:));
                    aineq_cortes(cant_cortes,pos_expansion_en_slave_cortes_oper(j,:)) = lambda_aineq_cortes_oper(j,:);
                    aineq_cortes(cant_cortes, cant_master + j) = 1;
                end
                bineq_cortes = [bineq_cortes; bineq_cortes_oper];
                
                dt_slave = etime(clock,t_inicio_slave);
                if this.iNivelDebug > 1
                    % agrega nombre cortes
                    nombres_cortes = [nombres_cortes; nombres_cortes_oper];
                end
                    
                texto_nueva_sol = '';
                if z_upper(k) < best_z_upper
                    best_z_upper = z_upper(k);
                    best_sol = y_master;
                    texto_nueva_sol = '*';
                end
                dt_total = etime(clock, t_inicio);
                %texto = sprintf('%-5s %-5s %-15s %-15s %-15s %-15s %-10s %-10s %-10s',num2str(k), texto_nueva_sol, num2str(round(z_upper(k),5)), num2str(round(best_z_upper,5)), ...
                %    num2str(round(z_lower(k),5)), num2str(round((best_z_upper-z_lower(k))/best_z_upper*100,5)), num2str(dt_master), num2str(dt_slave), num2str(dt_total));
texto = sprintf('%-5s %-5s %-15s %-15s %-15s %-15s %-15s %-10s %-10s %-10s',num2str(k), texto_nueva_sol, num2str(round(z_upper(k),5)), num2str(round(best_z_upper,5)), ...
                num2str(round(z_lower(k),5)), num2str(round((best_z_upper-z_lower(k))/best_z_upper*100,5)), num2str(round((best_z_upper-z_lower_gap(k))/best_z_upper*100,5)), num2str(dt_master), num2str(dt_slave), num2str(dt_total));

                disp(texto)
                
                if (best_z_upper-z_lower(k))/best_z_upper < 0.0001
                    break
                end

                if this.iNivelDebug > 3
                    % verifica que suma de bineq de cortes en cada
                    % escenario y etapa coincida con solucion completa
                    fobj_slave = this.Fobj;
                    fobj_slave(this.TipoVarOpt == 1) = 0;

                    % 2. Identifica todas variables válidas para el escenario y la etapa. Incluyendo las decisiones de expansión del problema master
                    id_slave = (this.TipoVarOpt == 1 & this.SubtipoVarOpt == 3) | (this.TipoVarOpt == 2);
                    %id_expansion_en_slave = this.TipoVarOpt == 1 & this.SubtipoVarOpt == 1 & this.EscenarioVarOpt == escenario & this.EtapaVarOpt <= etapa;

                    fobj_slave = fobj_slave(id_slave);
                    lb_slave = this.lb(id_slave);
                    ub_slave = this.ub(id_slave);

                    aineq_slave = this.Aineq(this.TipoRestriccionIneq == 2,id_slave);
                    bineq_slave = this.bineq(this.TipoRestriccionIneq == 2);

                    aeq_slave = this.Aeq(this.TipoRestriccionEq == 2,id_slave);
                    beq_slave = this.beq(this.TipoRestriccionEq == 2);

                    % agrega restricciones que fija el valor de expansión de las variables válidas de expansión (correspondientes a la etapa y escenario)
                    id_expansion_en_slave = id_master & id_slave;
                    pos_sol_expansion_para_slave = find(id_expansion_en_slave); % posiciones de solución de expansión en variable y_master
                    sol_expansion = y_master(pos_sol_expansion_para_slave);

                    %cant_expansion_en_slave = length(pos_sol_expansion_para_slave);
                    cant_expansion_en_slave_debug = length(pos_sol_expansion_para_slave);
                    aeq_expansion_slave = zeros(cant_expansion_en_slave_debug, length(fobj_slave));
                    aeq_expansion_slave(1:cant_expansion_en_slave_debug, 1:cant_expansion_en_slave_debug) = diag(ones(cant_expansion_en_slave_debug,1));
                    beq_expansion_slave = sol_expansion;

                    % agrega restricción de igualdad con resultado de expansión de la transmisión

                    rtype_slave = [repmat('L',[1 size(aineq_slave,1)]) repmat('E',[1 size(aeq_slave,1)]) repmat('E',[1 size(aeq_expansion_slave,1)])];

                    % imprime problema master
                    nombres_variables_debug = this.NombreVariables(id_slave);
                    id_ineq = this.TipoRestriccionIneq == 2;
                    id_eq = this.TipoRestriccionEq == 2;
                    nombres_restricciones_debug = this.NombreIneq(id_ineq);
                    nombres_restricciones_debug = [nombres_restricciones_debug ; this.NombreEq(id_eq)];
                    nombres_eq_fija_exp_en_slave_debug = cell(1,cant_expansion_en_slave_debug);
                    for ii = 1:cant_expansion_en_slave_debug
                        nombres_eq_fija_exp_en_slave_debug{ii} = ['Fija_Sol_' nombres_variables_debug{ii}];
                    end
                    nombres_restricciones_debug = [nombres_restricciones_debug; nombres_eq_fija_exp_en_slave_debug'];
                    this.imprime_problema_optimizacion_elementos_dados(fobj_slave, [aineq_slave; aeq_slave; aeq_expansion_slave], [bineq_slave; beq_slave; beq_expansion_slave], rtype_slave, lb_slave, ub_slave, [], nombres_variables_debug, nombres_restricciones_debug, ['lp_slave_It' num2str(k) 'completo']);

                        [x_slave,fval_slave,flag_slave,output_slave, lambda_slave] = xprslp(fobj_slave, [aineq_slave; aeq_slave; aeq_expansion_slave], [bineq_slave; beq_slave; beq_expansion_slave],rtype_slave, lb_slave,ub_slave,options);%, options);

                    % agrega costos de operación a z_upper
                    fval_slave_oper_completo = fval_slave;

                    %lambda_slave.lin = round(lambda_slave.lin, dec_redondeo);
                    % agrega corte
                    %cant_cortes = cant_cortes + 1;
                    pos_id_expansion_slave_en_master = find(id_expansion_en_slave);
                    %pos_alpha = etapa + this.iCantEtapas*(escenario -1);
                    bineq_cortes_completo = fval_slave + lambda_slave.lin(end-cant_expansion_en_slave_debug+1:end)'*sol_expansion;
                    lambda_aineq_cortes_oper_completo = lambda_slave.lin(end-cant_expansion_en_slave_debug+1:end);
                    pos_expansion_en_slave_cortes_oper_completo = pos_id_expansion_slave_en_master;
                end                
            end
            % optimiza nuevamente fijando la solución y guarda solución encontrada
            id_sol_expansion_en_slave = (this.TipoVarOpt == 1 & this.SubtipoVarOpt == 1);
            pos_sol_expansion = find(id_sol_expansion_en_slave);
            this.lb(pos_sol_expansion) = best_sol(pos_sol_expansion);
            this.ub(pos_sol_expansion) = best_sol(pos_sol_expansion);
            rtype = [repmat('L',[1 size(this.Aineq,1)]) repmat('E',[1 size(this.Aeq,1)])];
            ctype = repmat('C', [1 size(this.Fobj,1)]);
            ctype(this.intcon) = 'B';
            [this.ResOptimizacion,this.Fval,this.ExitFlag,this.Output] = xprsmip(this.Fobj,[this.Aineq; this.Aeq], [this.bineq; this.beq], rtype, ctype, [], [], this.lb,this.ub, []);%, options);
        end

        function optimiza_benders_secuencial_subetapas(this)
            options = xprsoptimset('OUTPUTLOG',0);
            if this.iNivelDebug > 1
                prot = cProtocolo.getInstance;
            end
% pos_cortes_primarios = zeros(length(this.VarExpansion),1);
% for ii = 1:length(this.VarExpansion)
%     if strcmp(this.VarExpansion(ii).entrega_tipo_proyecto(), 'AS') || ...
%             (strcmp(this.VarExpansion(ii).entrega_tipo_proyecto(), 'AT') && this.VarExpansion(ii).EsUprating)
%         pos_cortes_primarios(ii) = 0;
%     else
%         pos_cortes_primarios(ii) = 1;
%     end
% end
    
            t_inicio = clock;
            t_inicio_master = clock;
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            id_master = this.TipoVarOpt == 1;
            cant_master = sum(id_master);
            %id_expansion_master = this.TipoVarOpt == 1 & this.SubtipoVarOpt == 1;
            fobj_master = this.Fobj(id_master);

            lb_master = this.lb(id_master);
            ub_master = this.ub(id_master);

            aineq_master = this.Aineq(this.TipoRestriccionIneq == 1,id_master);
            bineq_master = this.bineq(this.TipoRestriccionIneq == 1);

            aeq_master = this.Aeq(this.TipoRestriccionEq == 1,id_master);
            beq_master = this.beq(this.TipoRestriccionEq == 1);

            rtype_master = [repmat('L',[1 size(aineq_master,1)]) repmat('E',[1 size(aeq_master,1)])];

            id_intcon_var_orig = zeros(length(this.Fobj),1);
            id_intcon_var_orig(this.intcon) = 1;
            id_intcon_master = id_intcon_var_orig(id_master);
            intcon_master = find(id_intcon_master);
%disp('Verificar que variables de decisión de la expansión estén en bloques')

            ctype_master = repmat('C', [1 size(fobj_master,1)]);
            ctype_master(intcon_master) = 'B';
            %if this.pParOpt.MaxGap > 0
            %    options = xprsoptimset('MIPRELSTOP',this.pParOpt.MaxGap); 
            %end

            if this.iNivelDebug > 1
                % imprime problema master
                nombres_var_master = this.NombreVariables(this.TipoVarOpt == 1);
                nombres_restricciones_master = this.NombreIneq(this.TipoRestriccionIneq == 1);
                nombres_restricciones_master = [nombres_restricciones_master ; this.NombreEq(this.TipoRestriccionEq == 1)];
                if this.iNivelDebug > 2
                    this.imprime_problema_optimizacion_elementos_dados(fobj_master, [aineq_master; aeq_master], [bineq_master; beq_master], rtype_master, lb_master, ub_master, intcon_master, nombres_var_master, nombres_restricciones_master, 'milp_master_0');
                end
                
                % define nombres de los alphas (para imprimir después)
                nombres_alpha = cell(1,this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas);
                for j = 1:this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas
                    [escenario, etapa, subetapa] = ind2sub([this.iCantEscenarios, this.iCantEtapas, this.iCantSubetapas],j);
                    nombres_alpha{j} = ['Alpha_S' num2str(escenario) '_E' num2str(etapa), '_SE' num2str(subetapa)];
                end
                nombres_cortes = cell(1,0);
            end
            
            [y_master,fval_master,exit_master,output_master] = xprsmip(fobj_master, [aineq_master; aeq_master], [bineq_master; beq_master],rtype_master, ctype_master, [], [], lb_master,ub_master, [],options);%, options);
            y_master = round(y_master, dec_redondeo);
            dt_master = etime(clock,t_inicio_master);
            
            % aumenta dimensiones para incluir los alphas 
            alpha = zeros(1,this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas);
            aineq_master = [aineq_master zeros(size(aineq_master,1),length(alpha))];
            aeq_master = [aeq_master zeros(size(aeq_master,1),length(alpha))];
            q = (1 + this.pParOpt.TasaDescuento);
            vector_etapas = 1:this.pParOpt.DeltaEtapa:this.iCantEtapas;   
            descuento_etapas = 1./q.^vector_etapas;
            pesos_alpha = zeros(this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas,1);
            for j = 1:this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas
                [escenario, etapa, subetapa] = ind2sub([this.iCantEscenarios, this.iCantEtapas, this.iCantSubetapas],j);
                peso_escenario = this.pAdmSc.entrega_peso_escenario(escenario);
                peso_etapa = descuento_etapas(etapa);
                pesos_alpha(j) = round(peso_escenario*peso_etapa, dec_redondeo);
            end
            
            fobj_master = [fobj_master; pesos_alpha];
            %fobj_master = [fobj_master; ones(this.iCantEscenarios*this.iCantEtapas,1)];
            %lb_master = [lb_master -inf*ones(1,length(pesos_alpha))];
            %ub_master = [ub_master inf*ones(1,length(pesos_alpha))];
            %ctype_master = [ctype_master repmat('C', [1 length(pesos_alpha)])];

            lb_alphas = zeros(1,this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas);
            for j = 1:this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas
                %[escenario, etapa, subetapa] = ind2sub([this.iCantEscenarios, this.iCantEtapas, this.iCantSubetapas],j);
                lb_alphas(j) = this.COperUninodal(j)/pesos_alpha(j);
            end
lb_alphas = zeros(1,this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas);
            %lb_master = [lb_master zeros(1,this.iCantEscenarios*this.iCantEtapas)];
            lb_master = [lb_master lb_alphas];

            %lb_master = [lb_master -inf*ones(1,this.iCantEscenarios*this.iCantEtapas)];
            ub_master = [ub_master inf*ones(1,this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas)];
            ctype_master = [ctype_master repmat('C', [1 this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas])];
            
            % define contenedores para los cortes
            bineq_cortes = [];
            aineq_cortes = zeros(0, length(fobj_master));
            cant_cortes = 0;
            
            z_upper = 0;
            z_lower = 0;
            
            best_z_upper = inf;
            best_sol = 0;
            texto = sprintf('%-5s %-5s %-15s %-15s %-15s %-15s %-10s %-10s %-10s','It', 'Sol', 'ZUpper(k)', 'ZUpperB', 'ZLower(k)', 'Gap%', 'Dtmaster', 'Dtslave', 'DtTotal');
            disp(texto)

            % verifica que cantidad de variables de expansión en esclavos sea siempre la misma
            cant_expansion_en_slave_todos = zeros(this.iCantEscenarios*this.iCantEtapas,1);
            for j = 1:this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas
                [escenario, etapa, subetapa] = ind2sub([this.iCantEscenarios, this.iCantEtapas, this.iCantSubetapas],j);
                
                id_slave = (this.TipoVarOpt == 1 & this.SubtipoVarOpt == 3 & this.EscenarioVarOpt == escenario & this.EtapaVarOpt == etapa) | ...
                    (this.TipoVarOpt == 2 &  this.EscenarioVarOpt == escenario & this.EtapaVarOpt == etapa & this.SubetapaVarOpt == subetapa);

                id_expansion_en_slave = id_master & id_slave;
                pos_sol_expansion_para_slave = find(id_expansion_en_slave); % posiciones de solución de expansión en variable y_master

                cant_expansion_en_slave_todos(j) = length(pos_sol_expansion_para_slave);
            end
            cant_expansion_en_slave = unique(cant_expansion_en_slave_todos);
            if length(cant_expansion_en_slave) > 1
                error = MException('cOptMILP:optimiza_benders_secuencial',...
                    'Cantidad de variables expansión difere en las distintas etapas. No se puede simular en forma paralela');
                throw(error)
            end
            
            for k = 1:this.pParOpt.MaxIterBenders
                if k > 1
                    % resuelve problema master con los cortes
                    t_inicio_master = clock;
                    rtype_master = [repmat('L',[1 size(aineq_master,1)]) repmat('E',[1 size(aeq_master,1)]) repmat('G',[1 size(aineq_cortes,1)])];
                    if this.iNivelDebug > 1
                        % imprime problema master
                        nombres_variables = [nombres_var_master nombres_alpha];
                        nombres_restricciones = [nombres_restricciones_master ; nombres_cortes];
                        if this.iNivelDebug > 2
                            this.imprime_problema_optimizacion_elementos_dados(fobj_master, [aineq_master; aeq_master; aineq_cortes], [bineq_master; beq_master; bineq_cortes], rtype_master, lb_master, ub_master, intcon_master, nombres_variables, nombres_restricciones, ['milp_master_' num2str(k)]);
                        end
                    end

                    [y_master,fval_master,exit_master,output_master] = xprsmip(fobj_master, [aineq_master; aeq_master;aineq_cortes], [bineq_master; beq_master; bineq_cortes],rtype_master, ctype_master, [], [], lb_master,ub_master, [], options);%, options);
                    dt_master = etime(clock,t_inicio_master);
                    y_master = round(y_master, dec_redondeo);
                    z_lower(k) = fval_master;
                    
                    if this.iNivelDebug > 1
                        id_decision_expansion_prot = this.TipoVarOpt == 1 & this.SubtipoVarOpt == 1;
                        pos_sol_expansion_prot = find(id_decision_expansion_prot); % posiciones de solución de expansión en variable y_master
                        sol = y_master(pos_sol_expansion_prot);
                        nombre_validos = nombres_variables(pos_sol_expansion_prot);
                        texto_alpha = '';
                        for ii = 1:this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas
                            [escenario, etapa, subetapa]=ind2sub([this.iCantEscenarios, this.iCantEtapas, this.iCantSubetapas],ii);
                            texto_alpha = [texto_alpha sprintf('%-10s %-10s',['Alpha_S' num2str(escenario) ' _E' num2str(etapa) ' _SE' num2str(subetapa)],num2str(y_master(cant_master + ii)))];
                        end
%                        prot.imprime_vector_texto(nombre_validos(sol == 1)', ['\nSol. expansion en iteracion ' num2str(k)]);
                        texto = sprintf('%-10s %-10s %-15s %-10s %-15s %-10s',...
                            'Cinv sol: ',num2str(fobj_master(1:cant_master)'*y_master(1:cant_master)),...
                            'Sum alpha: ', num2str(fobj_master(cant_master+1:end)'*y_master(cant_master+1:end)), ...
                            'Fval master: ', num2str(fval_master));
                        texto = [texto texto_alpha];
                        prot.imprime_texto(texto);
                    end
%evalua solución óptima
% lb_optima = lb_master;
% ub_optima = ub_master;
% etapas_optima = [1 1 1 1 1 1 1 1 1 1 1 1 1 1 3 3 3 3 3];
% proy_optimos = [2 3 4 5 6 10 12 14 16 18 41 47 53 59 1 7 8 20 71];
% for ii = 1:length(this.VarExpansion)
% 	id_var = this.VarExpansion(ii).entrega_indice();
%     id_expansion_desde = this.VarExpansion(ii).entrega_varopt_expansion('Decision', 1);
%     id_expansion_hasta = id_expansion_desde + this.iCantEtapas - 1;
%     ub_optima(id_expansion_desde:id_expansion_hasta) = 0;
%     if ~isempty(find(ismember(proy_optimos, id_var), 1))
%         indice_opt = find(ismember(proy_optimos, id_var));
%         etapa = etapas_optima(indice_opt);
%         lb_optima(id_expansion_desde + etapa - 1) = 1;
%         ub_optima(id_expansion_desde + etapa - 1) = 1;
%     end
% end
% [y_test,fval_test,exit_test,output_test] = xprsmip(fobj_master, [aineq_master; aeq_master;aineq_cortes], [bineq_master; beq_master; bineq_cortes],rtype_master, ctype_master, [], [], lb_optima,ub_optima, [],options);%, options);
% texto = sprintf('%-20s %-15s %-20s %-15s %-20s %-15s',...
%     'Cinv opt: ',num2str(fobj_master(1:cant_master)'*y_test(1:cant_master)),...
%     'Suma alpha opt: ', num2str(fobj_master(cant_master+1:end)'*y_test(cant_master+1:end)), ...
%     'Fval opt: ', num2str(fval_test));
% prot.imprime_texto(texto);
% 
%sol_opt = y_test(pos_sol_expansion_prot);
%nombre_validos = nombres_variables(pos_sol_expansion_prot);
%prot.imprime_vector_texto(nombre_validos(sol_opt == 1)', ['Sol. optima ' num2str(k)]);

% linlinlin = 1

                else
                    z_lower(k) = 0;                    
                end
                z_upper(k) = fobj_master(1:cant_master)'*y_master(1:cant_master);
                fval_slave_oper = zeros(this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas,1);
                bineq_cortes_oper = zeros(this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas,1);
                lambda_aineq_cortes_oper = zeros(this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas,cant_expansion_en_slave);
                pos_expansion_en_slave_cortes_oper = zeros(this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas,cant_expansion_en_slave);
                nombres_cortes_oper = cell(this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas,1);
                
                t_inicio_slave = clock;
                for j = 1:this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas
                    [escenario, etapa, subetapa]=ind2sub([this.iCantEscenarios, this.iCantEtapas, this.iCantSubetapas],j);

                    % 1. elimina variables de decisión de expansión de la función objetivo. Después de eliminan las variables que no corresponden
                    peso_caso = pesos_alpha(j);
                    fobj_slave = this.Fobj/peso_caso;
                    fobj_slave(this.TipoVarOpt == 1) = 0;

                    % 2. Identifica todas variables válidas para el escenario y la etapa. Incluyendo las decisiones de expansión del problema master
                    id_slave = (this.TipoVarOpt == 1 & this.SubtipoVarOpt == 3 & this.EscenarioVarOpt == escenario & this.EtapaVarOpt == etapa) | ...
                        (this.TipoVarOpt == 2 &  this.EscenarioVarOpt == escenario & this.EtapaVarOpt == etapa & this.SubetapaVarOpt == subetapa);
                    %id_expansion_en_slave = this.TipoVarOpt == 1 & this.SubtipoVarOpt == 1 & this.EscenarioVarOpt == escenario & this.EtapaVarOpt <= etapa;

                    fobj_slave = fobj_slave(id_slave);
                    lb_slave = this.lb(id_slave);
                    ub_slave = this.ub(id_slave);

                    aineq_slave = this.Aineq(this.TipoRestriccionIneq == 2 & this.EscenarioRestriccionIneq == escenario & this.EtapaRestriccionIneq == etapa & this.SubetapaRestriccionIneq == subetapa,id_slave);
                    bineq_slave = this.bineq(this.TipoRestriccionIneq == 2 & this.EscenarioRestriccionIneq == escenario & this.EtapaRestriccionIneq == etapa & this.SubetapaRestriccionIneq == subetapa);

                    aeq_slave = this.Aeq(this.TipoRestriccionEq == 2 & this.EscenarioRestriccionEq == escenario & this.EtapaRestriccionEq == etapa & this.SubetapaRestriccionEq == subetapa,id_slave);
                    beq_slave = this.beq(this.TipoRestriccionEq == 2 & this.EscenarioRestriccionEq == escenario & this.EtapaRestriccionEq == etapa & this.SubetapaRestriccionEq == subetapa);

                    % agrega restricciones que fija el valor de expansión de las variables válidas de expansión (correspondientes a la etapa y escenario)
                    id_expansion_en_slave = id_master & id_slave;
                    pos_sol_expansion_para_slave = find(id_expansion_en_slave); % posiciones de solución de expansión en variable y_master
                    sol_expansion = y_master(pos_sol_expansion_para_slave);

                    %cant_expansion_en_slave = length(pos_sol_expansion_para_slave);
                    aeq_expansion_slave = zeros(cant_expansion_en_slave, length(fobj_slave));
                    aeq_expansion_slave(1:cant_expansion_en_slave, 1:cant_expansion_en_slave) = diag(ones(cant_expansion_en_slave,1));
                    beq_expansion_slave = sol_expansion;

                    % agrega restricción de igualdad con resultado de expansión de la transmisión

                    rtype_slave = [repmat('L',[1 size(aineq_slave,1)]) repmat('E',[1 size(aeq_slave,1)]) repmat('E',[1 size(aeq_expansion_slave,1)])];

                    if this.iNivelDebug > 1
                        % imprime problema master
                        nombres_variables = this.NombreVariables(id_slave);
                        id_ineq = this.TipoRestriccionIneq == 2 & this.EscenarioRestriccionIneq == escenario & this.EtapaRestriccionIneq == etapa & this.SubetapaRestriccionIneq == subetapa;
                        id_eq = this.TipoRestriccionEq == 2 & this.EscenarioRestriccionEq == escenario & this.EtapaRestriccionEq == etapa & this.SubetapaRestriccionEq == subetapa;
                        nombres_restricciones = this.NombreIneq(id_ineq);
                        nombres_restricciones = [nombres_restricciones ; this.NombreEq(id_eq)];
                        nombres_eq_fija_exp_en_slave = cell(1,cant_expansion_en_slave);
                        for ii = 1:cant_expansion_en_slave
                            nombres_eq_fija_exp_en_slave{ii} = ['Fija_Sol_' nombres_variables{ii}];
                        end
                        nombres_restricciones = [nombres_restricciones; nombres_eq_fija_exp_en_slave'];
                        if this.iNivelDebug > 2
                            this.imprime_problema_optimizacion_elementos_dados(fobj_slave, [aineq_slave; aeq_slave; aeq_expansion_slave], [bineq_slave; beq_slave; beq_expansion_slave], rtype_slave, lb_slave, ub_slave, [], nombres_variables, nombres_restricciones, ['lp_slave_It' num2str(k) '_S' num2str(escenario) '_E' num2str(etapa) '_SE' num2str(subetapa)]);
                        end
                    end
                    [x_slave,fval_slave,flag_slave,output_slave, lambda_slave] = xprslp(fobj_slave, [aineq_slave; aeq_slave; aeq_expansion_slave], [bineq_slave; beq_slave; beq_expansion_slave],rtype_slave, lb_slave,ub_slave,options);

                    % agrega costos de operación a z_upper
                    fval_slave_oper(j) = fval_slave*peso_caso;

                    %lambda_slave.lin = round(lambda_slave.lin, dec_redondeo);
                    % agrega corte
                    %cant_cortes = cant_cortes + 1;
                    pos_id_expansion_slave_en_master = find(id_expansion_en_slave);
                    %pos_alpha = etapa + this.iCantEtapas*(escenario -1);
                    bineq_cortes_oper(j,1) = fval_slave + lambda_slave.lin(end-cant_expansion_en_slave+1:end)'*sol_expansion;
                    lambda_aineq_cortes_oper(j,:) = lambda_slave.lin(end-cant_expansion_en_slave+1:end);
                    pos_expansion_en_slave_cortes_oper(j,:) = pos_id_expansion_slave_en_master;
% lambda_alternativo = lambda_slave.lin(end-cant_expansion_en_slave+1:end);
% lambda_alternativo(pos_cortes_primarios == 0) = 0;
% bineq_cortes_oper(j,1) = fval_slave + lambda_alternativo'*sol_expansion;
% lambda_aineq_cortes_oper(j,:) = lambda_alternativo;
                    if this.iNivelDebug > 1
                        % agrega nombre cortes
                        nombres_cortes_oper{j} = ['Corte_It' num2str(k) '_S' num2str(escenario) '_E' num2str(etapa) '_SE' num2str(etapa)];
                    end
                end
                
                z_upper(k) = z_upper(k) + sum(fval_slave_oper);
                for j = 1:this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas
                    cant_cortes = cant_cortes + 1;
                    %pos_id_expansion_slave_en_master = find(id_expansion_en_slave_cortes(j,:));
                    aineq_cortes(cant_cortes,pos_expansion_en_slave_cortes_oper(j,:)) = lambda_aineq_cortes_oper(j,:);
                    aineq_cortes(cant_cortes, cant_master + j) = 1;
                end
                bineq_cortes = [bineq_cortes; bineq_cortes_oper];
                
                dt_slave = etime(clock,t_inicio_slave);
                if this.iNivelDebug > 1
                    % agrega nombre cortes
                    nombres_cortes = [nombres_cortes; nombres_cortes_oper];
                end
                    
                texto_nueva_sol = '';
                if z_upper(k) < best_z_upper
                    best_z_upper = z_upper(k);
                    best_sol = y_master;
                    texto_nueva_sol = '*';
                end
                dt_total = etime(clock, t_inicio);
                texto = sprintf('%-5s %-5s %-15s %-15s %-15s %-15s %-10s %-10s %-10s',num2str(k), texto_nueva_sol, num2str(round(z_upper(k),5)), num2str(round(best_z_upper,5)), ...
                    num2str(round(z_lower(k),5)), num2str(round((best_z_upper-z_lower(k))/best_z_upper*100,5)), num2str(dt_master), num2str(dt_slave), num2str(dt_total));
                disp(texto)
                
                if (best_z_upper-z_lower(k))/best_z_upper < 0.0001
                    break
                end

                if this.iNivelDebug > 3
                    % verifica que suma de bineq de cortes en cada
                    % escenario y etapa coincida con solucion completa
                    fobj_slave = this.Fobj;
                    fobj_slave(this.TipoVarOpt == 1) = 0;

                    % 2. Identifica todas variables válidas para el escenario y la etapa. Incluyendo las decisiones de expansión del problema master
                    id_slave = (this.TipoVarOpt == 1 & this.SubtipoVarOpt == 3) | (this.TipoVarOpt == 2);
                    %id_expansion_en_slave = this.TipoVarOpt == 1 & this.SubtipoVarOpt == 1 & this.EscenarioVarOpt == escenario & this.EtapaVarOpt <= etapa;

                    fobj_slave = fobj_slave(id_slave);
                    lb_slave = this.lb(id_slave);
                    ub_slave = this.ub(id_slave);

                    aineq_slave = this.Aineq(this.TipoRestriccionIneq == 2,id_slave);
                    bineq_slave = this.bineq(this.TipoRestriccionIneq == 2);

                    aeq_slave = this.Aeq(this.TipoRestriccionEq == 2,id_slave);
                    beq_slave = this.beq(this.TipoRestriccionEq == 2);

                    % agrega restricciones que fija el valor de expansión de las variables válidas de expansión (correspondientes a la etapa y escenario)
                    id_expansion_en_slave = id_master & id_slave;
                    pos_sol_expansion_para_slave = find(id_expansion_en_slave); % posiciones de solución de expansión en variable y_master
                    sol_expansion = y_master(pos_sol_expansion_para_slave);

                    %cant_expansion_en_slave = length(pos_sol_expansion_para_slave);
                    cant_expansion_en_slave_debug = length(pos_sol_expansion_para_slave);
                    aeq_expansion_slave = zeros(cant_expansion_en_slave_debug, length(fobj_slave));
                    aeq_expansion_slave(1:cant_expansion_en_slave_debug, 1:cant_expansion_en_slave_debug) = diag(ones(cant_expansion_en_slave_debug,1));
                    beq_expansion_slave = sol_expansion;

                    % agrega restricción de igualdad con resultado de expansión de la transmisión

                    rtype_slave = [repmat('L',[1 size(aineq_slave,1)]) repmat('E',[1 size(aeq_slave,1)]) repmat('E',[1 size(aeq_expansion_slave,1)])];

                    % imprime problema master
                    nombres_variables_debug = this.NombreVariables(id_slave);
                    id_ineq = this.TipoRestriccionIneq == 2;
                    id_eq = this.TipoRestriccionEq == 2;
                    nombres_restricciones_debug = this.NombreIneq(id_ineq);
                    nombres_restricciones_debug = [nombres_restricciones_debug ; this.NombreEq(id_eq)];
                    nombres_eq_fija_exp_en_slave_debug = cell(1,cant_expansion_en_slave_debug);
                    for ii = 1:cant_expansion_en_slave_debug
                        nombres_eq_fija_exp_en_slave_debug{ii} = ['Fija_Sol_' nombres_variables_debug{ii}];
                    end
                    nombres_restricciones_debug = [nombres_restricciones_debug; nombres_eq_fija_exp_en_slave_debug'];
                    this.imprime_problema_optimizacion_elementos_dados(fobj_slave, [aineq_slave; aeq_slave; aeq_expansion_slave], [bineq_slave; beq_slave; beq_expansion_slave], rtype_slave, lb_slave, ub_slave, [], nombres_variables_debug, nombres_restricciones_debug, ['lp_slave_It' num2str(k) 'completo']);

                        [x_slave,fval_slave,flag_slave,output_slave, lambda_slave] = xprslp(fobj_slave, [aineq_slave; aeq_slave; aeq_expansion_slave], [bineq_slave; beq_slave; beq_expansion_slave],rtype_slave, lb_slave,ub_slave,options);%, options);

                    % agrega costos de operación a z_upper
                    fval_slave_oper_completo = fval_slave;

                    %lambda_slave.lin = round(lambda_slave.lin, dec_redondeo);
                    % agrega corte
                    %cant_cortes = cant_cortes + 1;
                    pos_id_expansion_slave_en_master = find(id_expansion_en_slave);
                    %pos_alpha = etapa + this.iCantEtapas*(escenario -1);
                    bineq_cortes_completo = fval_slave + lambda_slave.lin(end-cant_expansion_en_slave_debug+1:end)'*sol_expansion;
                    lambda_aineq_cortes_oper_completo = lambda_slave.lin(end-cant_expansion_en_slave_debug+1:end);
                    pos_expansion_en_slave_cortes_oper_completo = pos_id_expansion_slave_en_master;
                end                
            end
            % optimiza nuevamente fijando la solución y guarda solución encontrada
            id_sol_expansion_en_slave = (this.TipoVarOpt == 1 & this.SubtipoVarOpt == 1);
            pos_sol_expansion = find(id_sol_expansion_en_slave);
            this.lb(pos_sol_expansion) = best_sol(pos_sol_expansion);
            this.ub(pos_sol_expansion) = best_sol(pos_sol_expansion);
            rtype = [repmat('L',[1 size(this.Aineq,1)]) repmat('E',[1 size(this.Aeq,1)])];
            ctype = repmat('C', [1 size(this.Fobj,1)]);
            ctype(this.intcon) = 'B';
            [this.ResOptimizacion,this.Fval,this.ExitFlag,this.Output] = xprsmip(this.Fobj,[this.Aineq; this.Aeq], [this.bineq; this.beq], rtype, ctype, [], [], this.lb,this.ub, []);%, options);
        end
        
        function optimiza_benders_primal_dual(this)
            options = xprsoptimset('OUTPUTLOG',0);
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            id_master = this.TipoVarOpt == 1;
            cant_master = sum(id_master);
            %id_expansion_master = this.TipoVarOpt == 1 & this.SubtipoVarOpt == 1;
            fobj_master = [0*this.Fobj(id_master); 1];
            lb_master = [this.lb(id_master) 0];
            ub_master = [this.ub(id_master) inf];

            aineq_master = this.Aineq(this.TipoRestriccionIneq == 1,id_master);
            aineq_master = [aineq_master zeros(size(aineq_master,1),1)];
            bineq_master = this.bineq(this.TipoRestriccionIneq == 1);

            aeq_master = this.Aeq(this.TipoRestriccionEq == 1,id_master);
            aeq_master = [aeq_master zeros(size(aeq_master,1), 1)];
            beq_master = this.beq(this.TipoRestriccionEq == 1);

            aineq_alpha = zeros(1,cant_master + 1);
            aineq_alpha(1,1:end-1) = -this.Fobj(id_master)';
            aineq_alpha(1,end) = 1;
            bineq_alpha = 0;

            id_intcon_var_orig = zeros(length(this.Fobj),1);
            id_intcon_var_orig(this.intcon) = 1;
            id_intcon_master = id_intcon_var_orig(id_master);
            intcon_master = find(id_intcon_master);

            ctype_master = repmat('C', [1 size(fobj_master,1)]);
            ctype_master(intcon_master) = 'B';

            texto = sprintf('%-5s %-5s %-15s %-15s %-15s %-15s','It', 'Sol', 'ZUpper(k)', 'ZLower(k)', 'ZUpperB','Gap%');
            disp(texto)
            if this.iNivelDebug > 2
                % imprime problema master
                nombres_var_master = [this.NombreVariables(this.TipoVarOpt == 1) 'Alpha'];
                nombres_restricciones_master = this.NombreIneq(this.TipoRestriccionIneq == 1);
                nombres_restricciones_master = [nombres_restricciones_master ; this.NombreEq(this.TipoRestriccionEq == 1)];
                nombres_cortes = cell(1,0);
                nombres_cortes{1} = 'RestAlphaBase';
            end
            
            z_lower = 0;
            z_upper = 0;
            best_z_upper = inf;
            cant_cortes = 0;
            for k = 1:50
                if k == 1
                    aineq_cortes = aineq_alpha;
                    bineq_cortes = bineq_alpha;
                    rtype_master = [repmat('L',[1 size(aineq_master,1)]) repmat('E',[1 size(aeq_master,1)]) repmat('G',[1 k])];
                else
                    rtype_master = [repmat('L',[1 size(aineq_master,1)]) repmat('E',[1 size(aeq_master,1)]) repmat('G',[1 k-1])];
                end
                                    
                if this.iNivelDebug > 2
                    % imprime problema master
                    nombres_restricciones_master = [nombres_restricciones_master ; nombres_cortes];
                    this.imprime_problema_optimizacion_elementos_dados(fobj_master, [aineq_master; aeq_master; aineq_cortes], [bineq_master; beq_master; bineq_cortes], rtype_master, lb_master, ub_master, intcon_master, nombres_var_master, nombres_restricciones_master, ['milp_master_' num2str(k)]);
                end
                
                % 1. resuelve problema master
                [y_master,fval_master,exit_master,output_master] = xprsmip(fobj_master, [aineq_master; aeq_master; aineq_cortes], [bineq_master; beq_master; bineq_cortes],rtype_master, ctype_master, [], [], lb_master,ub_master, [],options);%, options);
                y_master = round(y_master, dec_redondeo);
                
                z_lower(k) = fval_master;
                
                % 2. resuelve esclavo primal
                % 2.1. elimina variables de decisión de expansión de la función objetivo
                fobj_slave_p = this.Fobj(this.TipoVarOpt == 2);
                        
                % 2.2. Identifica todas variables válidas para el esclavo
                id_slave_p = this.TipoVarOpt == 2;
                lb_slave_p = this.lb(id_slave_p);
                ub_slave_p = this.ub(id_slave_p);

                aineq_slave_p = this.Aineq(this.TipoRestriccionIneq == 2,id_slave_p);
                bineq_slave_p = this.bineq(this.TipoRestriccionIneq == 2);

                aeq_slave_p = this.Aeq(this.TipoRestriccionEq == 2,id_slave_p);
                beq_slave_p = this.beq(this.TipoRestriccionEq == 2);

                % 2.3. fija solución de expansión
                ysol_completa = zeros(length(this.Fobj),1);
                ysol_completa(id_master) = y_master(1:end-1);
                bsol_ineq_completa = this.Aineq*ysol_completa;
                bsol_ineq_en_slave = bsol_ineq_completa(this.TipoRestriccionIneq == 2);
                
                bsol_eq_completa = this.Aeq*ysol_completa;
                bsol_eq_en_slave = bsol_eq_completa(this.TipoRestriccionEq == 2);
                
                bineq_slave_p = bineq_slave_p - bsol_ineq_en_slave;
                beq_slave_p = beq_slave_p - bsol_eq_en_slave;
                
                rtype_slave_p = [repmat('L',[1 size(aineq_slave_p,1)]) repmat('E',[1 size(aeq_slave_p,1)])];

                if this.iNivelDebug > 2
                    % imprime problema slave
                    nombres_variables = this.NombreVariables(id_slave_p);
                    nombres_restricciones = this.NombreIneq(this.TipoRestriccionIneq == 2);
                    nombres_restricciones = [nombres_restricciones ; this.NombreEq(this.TipoRestriccionEq == 2)];
                    this.imprime_problema_optimizacion_elementos_dados(fobj_slave_p, [aineq_slave_p; aeq_slave_p], [bineq_slave_p; beq_slave_p], rtype_slave_p, lb_slave_p, ub_slave_p, [], nombres_variables, nombres_restricciones, ['lp_slave_primal_It' num2str(k)]);
                end
                % 2.4. optimiza esclavo primal
                [x_slave_p,fval_slave_p,flag_slave_p,output_slave_p, lambda_slave_p] = xprslp(fobj_slave_p, [aineq_slave_p; aeq_slave_p], [bineq_slave_p; beq_slave_p],rtype_slave_p, lb_slave_p,ub_slave_p,options);%, options);

                % 2.5. Determina z_upper
                fval_expansion = this.Fobj(id_master)'*y_master(1:end-1); % última posición del master es el alpha
                z_upper(k) = fval_expansion + fval_slave_p;
                
                % 3. Resuelve esclavo dual
                % b_slave_d = Nvar_oper x 1 (costos asociados a las variables de operación)
                % u = Nrest_ineq + Nrest_eq --> vector solución
                
                % E_ineq_d = Nrest_ineq x Nvar_oper
                % E_ineq_d_t = Nvar_oper x Nrest_ineq
                % E_ineq_d_t x u_ineq = Nvar_oper

                % E_eq_d = Nrest_eq x Nvar_oper                
                % E_eq_d_t = Nvar_oper x Nrest_eq
                % E_eq_d_t x u_eq = Nvar_oper
                
                % E_d: (Nrest_ineq + Nrest_eq) x Nvar_oper
                % E_d_t: Nvar_oper x (Nrest_ineq + Nrest_eq)
                % E_d_t x u = Nvar_oper
                
                cant_ineq = sum(this.TipoRestriccionIneq == 2);
                cant_eq = sum(this.TipoRestriccionEq == 2);
                cant_vars = sum(this.TipoVarOpt == 2);
                E_ineq_d = this.Aineq(this.TipoRestriccionIneq == 2,this.TipoVarOpt == 2);
                %E_ineq_d = [this.Aineq(this.TipoRestriccionIneq == 2,this.TipoVarOpt == 2); zeros(cant_eq, cant_vars)];

                E_eq_d = this.Aeq(this.TipoRestriccionEq == 2,this.TipoVarOpt == 2);
                %E_eq_d = [zeros(cant_ineq, cant_vars); this.Aeq(this.TipoRestriccionEq == 2,this.TipoVarOpt == 2)];
                %E_d = [E_ineq_d; E_eq_d];

                id_unrestricted = find(this.lb(this.TipoVarOpt == 2) < 0 & this.ub(this.TipoVarOpt == 2) > 0);
                id_fija = find(this.lb(this.TipoVarOpt == 2) == this.ub(this.TipoVarOpt == 2));
                id_pos = find(this.lb(this.TipoVarOpt == 2) >= 0 & this.lb(this.TipoVarOpt == 2) ~= this.ub(this.TipoVarOpt == 2));
                id_neg = find(this.ub(this.TipoVarOpt == 2) <= 0 & this.lb(this.TipoVarOpt == 2) ~= this.ub(this.TipoVarOpt == 2));
                cant_fija = length(id_fija);
                cant_unrestricted = length(id_unrestricted);
                cant_pos = length(id_pos);
                cant_neg = length(id_neg);
                                
                E_ineq_adicional = zeros(cant_pos+ cant_neg+cant_fija, cant_vars);
                bineq_adicional = zeros(cant_pos+cant_neg+cant_fija,1);
                % restricción adicional para id_pos
                lb_validos = this.lb(this.TipoVarOpt == 2);
                ub_validos = this.ub(this.TipoVarOpt == 2);
                row_validas = (1:1:cant_pos)';
                idx = sub2ind(size(E_ineq_adicional), row_validas, id_pos');
                E_ineq_adicional(idx) = 1;
                bineq_adicional(1:cant_pos) = ub_validos(id_pos);
                
                % restriccion adicional para id_neg
                row_validas = (cant_pos + 1:1:cant_pos+cant_neg)';
                idx = sub2ind(size(E_ineq_adicional), row_validas, id_neg');
                E_ineq_adicional(idx) = 1;
                bineq_adicional(cant_pos + 1:+cant_pos+cant_neg) = lb_validos(id_neg);

                % restriccion adicional para id_fija
                row_validas = (cant_pos + cant_neg + 1:1:cant_pos+cant_neg+cant_fija)';
                idx = sub2ind(size(E_ineq_adicional), row_validas, id_fija');
                E_ineq_adicional(idx) = 1;
                bineq_adicional(cant_pos + cant_neg + 1:1:cant_pos+cant_neg+cant_fija) = lb_validos(id_fija);
                
                E_d = [E_ineq_d; E_eq_d; E_ineq_adicional];
                
                if this.iNivelDebug > 2
                   % imprime problema esclavo dual
                   %nombres_variables = this.NombreVariables(id_slave_d);
                   nombres_var_d_adicionales = cell(cant_pos+cant_neg+cant_fija,0);
                   nombres_var_validas_slave = this.NombreVariables(this.TipoVarOpt == 2);
                   
                   for i = 1:cant_pos
                       nombres_var_d_adicionales{i} = ['D_upper_' nombres_var_validas_slave{id_pos(i)}];
                   end

                   for i = 1:cant_neg
                       nombres_var_d_adicionales{cant_pos + i} = ['D_lower_' nombres_var_validas_slave{id_neg(i)}];
                   end
                   for i = 1:cant_fija
                       nombres_var_d_adicionales{cant_pos + cant_neg + i} = ['D_eq_' nombres_var_validas_slave{id_fija(i)}];
                   end
                end
                
                
                F_ineq_d = this.Aineq(this.TipoRestriccionIneq == 2,this.TipoVarOpt == 1);
                F_eq_d = this.Aeq(this.TipoRestriccionEq == 2,this.TipoVarOpt == 1);
                F_d = [F_ineq_d; F_eq_d];
                
                h_ineq_d = this.bineq(this.TipoRestriccionIneq == 2);
                h_eq_d = this.beq(this.TipoRestriccionEq == 2);
                h_d = [h_ineq_d; h_eq_d];
                
                fobj_slave_d = [-(h_d-F_d*y_master(1:end-1)); -bineq_adicional];
                % dim_h_ineq_d = Nrest_ineq;
                % dim_h_eq_d = Nrest_eq;
                % dim_fobj = Nrest_ineq + Nrest_eq;

                % fija límites variables
                % si rest >=  --> var es positiva
                % si rest <=  --> var es negativa
                % si rest ==  --> var es unrest.
                
                b_slave_d = this.Fobj(this.TipoVarOpt == 2);
                lb_slave_d = zeros(1,length(fobj_slave_d));
                ub_slave_d = zeros(1,length(fobj_slave_d));
                lb_slave_d(1:cant_ineq) = -inf;
                ub_slave_d(1:cant_ineq) = 0;
                lb_slave_d(cant_ineq + 1:cant_ineq + cant_eq) = -inf;
                ub_slave_d(cant_ineq + 1:cant_ineq + cant_eq) = inf;
                lb_slave_d(cant_ineq + cant_eq+1:cant_ineq + cant_eq+cant_pos) = -inf;
                ub_slave_d(cant_ineq + cant_eq+1:cant_ineq + cant_eq+cant_pos) = 0; 
                lb_slave_d(cant_ineq + cant_eq+cant_pos+1:cant_ineq + cant_eq+cant_pos+cant_neg) = 0;
                ub_slave_d(cant_ineq + cant_eq+cant_pos+1:cant_ineq + cant_eq+cant_pos+cant_neg) = inf; 
                lb_slave_d(cant_ineq + cant_eq+cant_pos+cant_neg+1:cant_ineq + cant_eq+cant_pos+cant_neg+cant_fija) = -inf;
                ub_slave_d(cant_ineq + cant_eq+cant_pos+cant_neg+1:cant_ineq + cant_eq+cant_pos+cant_neg+cant_fija) = inf; 
                
                % restricciones:
                %aineq_slave_d = E_ineq_d';
                %bineq_slave_d = c_slave_d;
                %aeq_slave_d = E_eq_d';
                %beq_slave_d = c_slave_d;
                %a_slave_d = [E_ineq_d; E_eq_d]';
                %aineq_slave_d = E_ineq_d';
                %aeq_slave_d = E_eq_d';
                %bineq_slave_d = c_slave_d;
                %beq_slave_d = c_slave_d;
                a_slave_d = E_d';
                % a_slave: Nvar_oper x (N_rest_ineq + N_rest_eq)

                % var >= 0         --> restriccion <= 0
                % var <= 0         --> restriccion >= 0
                % var unrestricted --> restriccion = 0
                rtype_slave_d = repmat('N',[1 size(a_slave_d,1)]);
                rtype_slave_d(id_unrestricted) = 'E';
                rtype_slave_d(id_fija) = 'E';
                rtype_slave_d(id_pos) = 'L';
                rtype_slave_d(id_neg) = 'G';
                if ~isempty(find(rtype_slave_d == 'N', 1))
                    error = MException('cOptMILP:optimiza_benders_moreno',...
                        'No todas las variables fueron encontradas para determinar los límites de las restricciones');
                    throw(error)
                end
                %rtype_slave_d = [repmat('L',[1 size(aineq_slave_d,1)]) repmat('E',[1 size(aeq_slave_d,1)])];
                %rtype_slave_d = [repmat('G',[1 size(aineq_slave_d,1)]) repmat('L',[1 size(aeq_slave_d,1)])];
                if this.iNivelDebug > 2
                   % imprime problema esclavo dual
                   %nombres_variables = this.NombreVariables(id_slave_d);
                   nombres_variables = cell(1,0);
                   nombres_ineq = this.NombreIneq(this.TipoRestriccionIneq == 2);
                   nombres_eq = this.NombreEq(this.TipoRestriccionEq == 2);
                   for ii = 1:cant_ineq
                       nombres_variables{ii} = ['D' nombres_ineq{ii}];
                   end
                   for ii = 1:cant_eq
                       nombres_variables{cant_ineq + ii} = ['D_var_' nombres_eq{ii}];
                   end
                   nombres_variables = [nombres_variables nombres_var_d_adicionales];
                   nombres_restricciones = cell(1,0);
                   nombres_variables_orig = this.NombreVariables(this.TipoVarOpt == 2);
                   for ii = 1:cant_vars
                       nombres_restricciones{ii} = ['D_rest_' nombres_variables_orig{ii}];
                   end
                   this.imprime_problema_optimizacion_elementos_dados(fobj_slave_d, a_slave_d, b_slave_d, rtype_slave_d, lb_slave_d, ub_slave_d, [], nombres_variables, nombres_restricciones, ['lp_slave_dual_It' num2str(k)]);
                end
                % 3.2. soluciona esclavo dual
                [x_slave_d,fval_slave_d,flag_slave_d,output_slave_d, lambda_slave_d] = xprslp(fobj_slave_d, a_slave_d, b_slave_d,rtype_slave_d, lb_slave_d,ub_slave_d,options);%, options);
                %[x_slave_d,fval_slave_d,flag_slave_d,output_slave_d, lambda_slave_d] = xprslp(fobj_slave_d, a_slave_d, b_slave_d,rtype_slave_d, lb_slave_d,ub_slave_d,options);%, options);
                
                % 3.3. Escribe corte
                cant_cortes = cant_cortes + 1;
                                
                aineq_cortes(k,:) = aineq_alpha;
                aineq_cortes(k,1:end-1) = aineq_cortes(k,1:end-1) + (F_d'*x_slave_d(1:cant_ineq+cant_eq))';
                bineq_cortes(k,1) = h_d'*x_slave_d(1:cant_ineq+cant_eq)+bineq_adicional'*x_slave_d(cant_ineq+cant_eq+1:cant_ineq+cant_eq+cant_pos+cant_neg+cant_fija);
                
                if this.iNivelDebug > 2
                    nombres_cortes{k,1} = ['Cortes_' num2str(k)];
                end
                
                texto_nueva_sol = '';
                if z_upper(k) < best_z_upper
                    best_z_upper = z_upper(k);
                    best_sol = y_master(1:end-1);
                    texto_nueva_sol = '*';
                end
                
                texto = sprintf('%-5s %-5s %-15s %-15s %-15s %-15s',num2str(k), texto_nueva_sol, num2str(round(z_upper(k),5)), num2str(round(z_lower(k),5)), num2str(round(best_z_upper,5)), num2str(round((best_z_upper-z_lower(k))/best_z_upper*100,5)));
                disp(texto)
                
                if (best_z_upper-z_lower(k))/best_z_upper < 0.0001
                    break
                end
            end
            % optimiza nuevamente fijando la solución y guarda solución encontrada
            this.lb(id_master) = best_sol;
            this.ub(id_master) = best_sol;
            rtype = [repmat('L',[1 size(this.Aineq,1)]) repmat('E',[1 size(this.Aeq,1)])];
            ctype = repmat('C', [1 size(this.Fobj,1)]);
            ctype(this.intcon) = 'B';
            [this.ResOptimizacion,this.Fval,this.ExitFlag,this.Output] = xprsmip(this.Fobj,[this.Aineq; this.Aeq], [this.bineq; this.beq], rtype, ctype, [], [], this.lb,this.ub, []);%, options);            
        end
        
        function optimiza_benders_primal_dual_etapas(this)
            % En este caso, cortes son por cada escenario y etapa
            options = xprsoptimset('OUTPUTLOG',0);
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            id_master = this.TipoVarOpt == 1;
            cant_master = sum(id_master);
            %id_expansion_master = this.TipoVarOpt == 1 & this.SubtipoVarOpt == 1;
            fobj_master = [0*this.Fobj(id_master); ones(this.iCantEscenarios*this.iCantEtapas,1)];
            lb_master = [this.lb(id_master) zeros(1,this.iCantEscenarios*this.iCantEtapas)];
            ub_master = [this.ub(id_master) inf*ones(1,this.iCantEscenarios*this.iCantEtapas)];

            aineq_master = this.Aineq(this.TipoRestriccionIneq == 1,id_master);
            aineq_master = [aineq_master zeros(size(aineq_master,1),this.iCantEscenarios*this.iCantEtapas)];
            bineq_master = this.bineq(this.TipoRestriccionIneq == 1);

            aeq_master = this.Aeq(this.TipoRestriccionEq == 1,id_master);
            aeq_master = [aeq_master zeros(size(aeq_master,1), this.iCantEscenarios*this.iCantEtapas)];
            beq_master = this.beq(this.TipoRestriccionEq == 1);

            aineq_alpha = zeros(this.iCantEscenarios*this.iCantEtapas,cant_master + this.iCantEscenarios*this.iCantEtapas);
            bineq_alpha = zeros(this.iCantEscenarios*this.iCantEtapas,1);
            for escenario = 1:this.iCantEscenarios
                for etapa = 1:this.iCantEtapas
                    % 2. Identifica todas variables válidas para el escenario y la etapa. Incluyendo las decisiones de expansión del problema master
                    id_fobj_escenario_etapa = (this.TipoVarOpt == 1 & this.EscenarioVarOpt == escenario & this.EtapaVarOpt == etapa);
                    pos_alpha = etapa + this.iCantEtapas*(escenario -1);
                    aineq_alpha(pos_alpha,id_fobj_escenario_etapa) = -this.Fobj(id_fobj_escenario_etapa)';
                    aineq_alpha(pos_alpha,cant_master+pos_alpha) = 1;
                end
            end
            
            id_intcon_var_orig = zeros(length(this.Fobj),1);
            id_intcon_var_orig(this.intcon) = 1;
            id_intcon_master = id_intcon_var_orig(id_master);
            intcon_master = find(id_intcon_master);
%disp('Verificar que variables de decisión de la expansión estén en bloques')

            ctype_master = repmat('C', [1 size(fobj_master,1)]);
            ctype_master(intcon_master) = 'B';
            %if this.pParOpt.MaxGap > 0
            %    options = xprsoptimset('MIPRELSTOP',this.pParOpt.MaxGap); 
            %end

            texto = sprintf('%-5s %-5s %-15s %-15s %-15s %-15s','It', 'Sol', 'ZUpper(k)', 'ZLower(k)', 'ZUpperB','Gap%');
            disp(texto)
            if this.iNivelDebug > 2
                % imprime problema master
                nombres_var_master = this.NombreVariables(this.TipoVarOpt == 1);
                nombres_cortes = cell(this.iCantEscenarios*this.iCantEtapas,1);
                for escenario = 1:this.iCantEscenarios
                    for etapa = 1:this.iCantEtapas
                        nombres_var_master = [nombres_var_master ['Alpha_S' num2str(escenario) '_E' num2str(etapa)]];
                        pos_corte = etapa + this.iCantEtapas*(escenario -1);
                        nombres_cortes{pos_corte,1} = ['Corte_It_0_S' num2str(escenario) '_E' num2str(etapa)];
                    end
                end
                
                nombres_restricciones_master = this.NombreIneq(this.TipoRestriccionIneq == 1);
                nombres_restricciones_master = [nombres_restricciones_master ; this.NombreEq(this.TipoRestriccionEq == 1)];
            end
            
            z_lower = 0;
            z_upper = 0;
            best_z_upper = inf;
            cant_cortes = 0;
            for k = 1:50
                if k == 1
                    aineq_cortes = aineq_alpha;
                    bineq_cortes = bineq_alpha;
                end
                
                rtype_master = [repmat('L',[1 size(aineq_master,1)]) repmat('E',[1 size(aeq_master,1)]) repmat('G',[1 size(aineq_cortes,1)])];
                                    
                if this.iNivelDebug > 2
                    % imprime problema master
                    nombres_rest_master = [nombres_restricciones_master ; nombres_cortes];
                    this.imprime_problema_optimizacion_elementos_dados(fobj_master, [aineq_master; aeq_master; aineq_cortes], [bineq_master; beq_master; bineq_cortes], rtype_master, lb_master, ub_master, intcon_master, nombres_var_master, nombres_rest_master, ['milp_master_' num2str(k)]);
                end
                
                % 1. resuelve problema master
                [y_master,fval_master,exit_master,output_master] = xprsmip(fobj_master, [aineq_master; aeq_master; aineq_cortes], [bineq_master; beq_master; bineq_cortes],rtype_master, ctype_master, [], [], lb_master,ub_master, [],options);%, options);
                y_master = round(y_master, dec_redondeo);
                
                z_lower(k) = fval_master;
                
                % 2. resuelve esclavo primal
                % 2.1. elimina variables de decisión de expansión de la función objetivo
                fobj_slave_p = this.Fobj(this.TipoVarOpt == 2);
                        
                % 2.2. Identifica todas variables válidas para el esclavo
                id_slave_p = this.TipoVarOpt == 2;
                lb_slave_p = this.lb(id_slave_p);
                ub_slave_p = this.ub(id_slave_p);

                aineq_slave_p = this.Aineq(this.TipoRestriccionIneq == 2,id_slave_p);
                bineq_slave_p = this.bineq(this.TipoRestriccionIneq == 2);

                aeq_slave_p = this.Aeq(this.TipoRestriccionEq == 2,id_slave_p);
                beq_slave_p = this.beq(this.TipoRestriccionEq == 2);

                % 2.3. fija solución de expansión
                ysol_completa = zeros(length(this.Fobj),1);
                ysol_completa(id_master) = y_master(1:cant_master);
                bsol_ineq_completa = this.Aineq*ysol_completa;
                bsol_ineq_en_slave = bsol_ineq_completa(this.TipoRestriccionIneq == 2);
                
                bsol_eq_completa = this.Aeq*ysol_completa;
                bsol_eq_en_slave = bsol_eq_completa(this.TipoRestriccionEq == 2);
                
                bineq_slave_p = bineq_slave_p - bsol_ineq_en_slave;
                beq_slave_p = beq_slave_p - bsol_eq_en_slave;
                
                rtype_slave_p = [repmat('L',[1 size(aineq_slave_p,1)]) repmat('E',[1 size(aeq_slave_p,1)])];

                if this.iNivelDebug > 2
                    % imprime problema slave
                    nombres_variables = this.NombreVariables(id_slave_p);
                    nombres_restricciones = this.NombreIneq(this.TipoRestriccionIneq == 2);
                    nombres_restricciones = [nombres_restricciones ; this.NombreEq(this.TipoRestriccionEq == 2)];
                    this.imprime_problema_optimizacion_elementos_dados(fobj_slave_p, [aineq_slave_p; aeq_slave_p], [bineq_slave_p; beq_slave_p], rtype_slave_p, lb_slave_p, ub_slave_p, [], nombres_variables, nombres_restricciones, ['lp_slave_primal_It' num2str(k)]);
                end
                % 2.4. optimiza esclavo primal
                [x_slave_p,fval_slave_p,flag_slave_p,output_slave_p, lambda_slave_p] = xprslp(fobj_slave_p, [aineq_slave_p; aeq_slave_p], [bineq_slave_p; beq_slave_p],rtype_slave_p, lb_slave_p,ub_slave_p,options);%, options);

                % 2.5. Determina z_upper
                fval_expansion = this.Fobj(id_master)'*y_master(1:cant_master); % últimas posiciones del master son los alpha
                z_upper(k) = fval_expansion + fval_slave_p;
                
                % 3. Resuelve esclavo dual
                % b_slave_d = Nvar_oper x 1 (costos asociados a las variables de operación)
                % u = Nrest_ineq + Nrest_eq --> vector solución
                
                % E_ineq_d = Nrest_ineq x Nvar_oper
                % E_ineq_d_t = Nvar_oper x Nrest_ineq
                % E_ineq_d_t x u_ineq = Nvar_oper

                % E_eq_d = Nrest_eq x Nvar_oper                
                % E_eq_d_t = Nvar_oper x Nrest_eq
                % E_eq_d_t x u_eq = Nvar_oper
                
                % E_d: (Nrest_ineq + Nrest_eq) x Nvar_oper
                % E_d_t: Nvar_oper x (Nrest_ineq + Nrest_eq)
                % E_d_t x u = Nvar_oper
                
                cant_ineq = sum(this.TipoRestriccionIneq == 2);
                cant_eq = sum(this.TipoRestriccionEq == 2);
                cant_vars = sum(this.TipoVarOpt == 2);
                E_ineq_d = this.Aineq(this.TipoRestriccionIneq == 2,this.TipoVarOpt == 2);
                %E_ineq_d = [this.Aineq(this.TipoRestriccionIneq == 2,this.TipoVarOpt == 2); zeros(cant_eq, cant_vars)];

                E_eq_d = this.Aeq(this.TipoRestriccionEq == 2,this.TipoVarOpt == 2);
                %E_eq_d = [zeros(cant_ineq, cant_vars); this.Aeq(this.TipoRestriccionEq == 2,this.TipoVarOpt == 2)];
                %E_d = [E_ineq_d; E_eq_d];

%                 % agrega restricciones para límites de variables
%                 id_unrestricted_orig = find((this.lb(this.TipoVarOpt == 2) < 0 & this.ub(this.TipoVarOpt == 2) > 0) | (this.lb(this.TipoVarOpt == 2) == this.ub(this.TipoVarOpt == 2)));
%                 indices_borrar = [];
%                 for i = 1:length(this.VarOperacion)
%                     if isa(this.VarOperacion(i), 'cLinea') || isa(this.VarOperacion(i), 'cTransformador2D')
%                         for escenario = 1:this.iCantEscenarios
%                             for etapa = 1:this.iCantEtapas
%                                 indice_desde = this.VarOperacion(i).entrega_varopt_operacion('P', escenario, etapa);
%                                 indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;
%                                 indices_borrar = [indices_borrar indice_desde:1:indice_hasta];
%                             end
%                         end
%                     end
%                 end
%                 id_unrestricted = id_unrestricted_orig;
%                 id_unrestricted(ismember(id_unrestricted, indices_borrar)) = [];
                id_unrestricted = find(this.lb(this.TipoVarOpt == 2) < 0 & this.ub(this.TipoVarOpt == 2) > 0);
                id_fija = find(this.lb(this.TipoVarOpt == 2) == this.ub(this.TipoVarOpt == 2));
                id_pos = find(this.lb(this.TipoVarOpt == 2) >= 0 & this.lb(this.TipoVarOpt == 2) ~= this.ub(this.TipoVarOpt == 2));
                id_neg = find(this.ub(this.TipoVarOpt == 2) <= 0 & this.lb(this.TipoVarOpt == 2) ~= this.ub(this.TipoVarOpt == 2));
                cant_fija = length(id_fija);
                cant_unrestricted = length(id_unrestricted);
                cant_pos = length(id_pos);
                cant_neg = length(id_neg);
                
%                 % dos restricciones para las id_unrestricted y id_cero                
%                 E_ineq_adicional = zeros(2*cant_unrestricted+cant_pos+ cant_neg, cant_vars);
%                 bineq_adicional = zeros(2*cant_unrestricted+cant_pos+ cant_neg, 1);
%                 
%                 row_validas = (1:1:cant_unrestricted)';
%                 idx = sub2ind(size(E_ineq_adicional), row_validas, id_unrestricted');
%                 E_ineq_adicional(idx) = 1;
%                 bineq_adicional(1:cant_unrestricted) = this.ub(id_unrestricted);
%                 
%                 row_validas = (cant_unrestricted+1:1:2*cant_unrestricted)';
%                 idx = sub2ind(size(E_ineq_adicional), row_validas, id_unrestricted');
%                 E_ineq_adicional(idx) = -1;
%                 bineq_adicional(cant_unrestricted + 1:2*cant_unrestricted) = -this.lb(id_unrestricted);
                
                E_ineq_adicional = zeros(cant_pos+ cant_neg+cant_fija, cant_vars);
                bineq_adicional = zeros(cant_pos+cant_neg+cant_fija,1);
                % restricción adicional para id_pos
                lb_validos = this.lb(this.TipoVarOpt == 2);
                ub_validos = this.ub(this.TipoVarOpt == 2);
                row_validas = (1:1:cant_pos)';
                idx = sub2ind(size(E_ineq_adicional), row_validas, id_pos');
                E_ineq_adicional(idx) = 1;
                bineq_adicional(1:cant_pos) = ub_validos(id_pos);

                escenarios_validos = this.EscenarioVarOpt(this.TipoVarOpt == 2);
                etapas_validos = this.EtapaVarOpt(this.TipoVarOpt == 2);
                
                Escenario_E_ineq_adicional = escenarios_validos(id_pos);
                Etapa_E_ineq_adicional = etapas_validos(id_pos);
                
                % restriccion adicional para id_neg
                row_validas = (cant_pos + 1:1:cant_pos+cant_neg)';
                idx = sub2ind(size(E_ineq_adicional), row_validas, id_neg');
                E_ineq_adicional(idx) = 1;
                bineq_adicional(cant_pos + 1:+cant_pos+cant_neg) = lb_validos(id_neg);

                Escenario_E_ineq_adicional = [Escenario_E_ineq_adicional escenarios_validos(id_neg)];
                Etapa_E_ineq_adicional = [Etapa_E_ineq_adicional etapas_validos(id_neg)];
                
                % restriccion adicional para id_fija
                row_validas = (cant_pos + cant_neg + 1:1:cant_pos+cant_neg+cant_fija)';
                idx = sub2ind(size(E_ineq_adicional), row_validas, id_fija');
                E_ineq_adicional(idx) = 1;
                bineq_adicional(cant_pos + cant_neg + 1:1:cant_pos+cant_neg+cant_fija) = lb_validos(id_fija);

                Escenario_E_ineq_adicional = [Escenario_E_ineq_adicional escenarios_validos(id_fija)];
                Etapa_E_ineq_adicional = [Etapa_E_ineq_adicional etapas_validos(id_fija)];
                
                E_d = [E_ineq_d; E_eq_d; E_ineq_adicional];
                
                if this.iNivelDebug > 2
                   % imprime problema esclavo dual
                   %nombres_variables = this.NombreVariables(id_slave_d);
                   nombres_var_d_adicionales = cell(cant_pos+cant_neg+cant_fija,0);
                   nombres_var_validas_slave = this.NombreVariables(this.TipoVarOpt == 2);
%                    for i = 1:cant_unrestricted
%                        nombres_var_d_adicionales{i} = ['D_upper_' nombres_var_validas_slave{id_unrestricted(i)}];
%                    end
%                    for i = 1:cant_unrestricted
%                        nombres_var_d_adicionales{cant_unrestricted + i} = ['D_lower_' nombres_var_validas_slave{id_unrestricted(i)}];
%                    end
                   
                   for i = 1:cant_pos
                       nombres_var_d_adicionales{i} = ['D_upper_' nombres_var_validas_slave{id_pos(i)}];
                   end

                   for i = 1:cant_neg
                       nombres_var_d_adicionales{cant_pos + i} = ['D_lower_' nombres_var_validas_slave{id_neg(i)}];
                   end
                   for i = 1:cant_fija
                       nombres_var_d_adicionales{cant_pos + cant_neg + i} = ['D_eq_' nombres_var_validas_slave{id_fija(i)}];
                   end
                end
                
                
                F_ineq_d = this.Aineq(this.TipoRestriccionIneq == 2,this.TipoVarOpt == 1);
                F_eq_d = this.Aeq(this.TipoRestriccionEq == 2,this.TipoVarOpt == 1);
                F_d = [F_ineq_d; F_eq_d];
                
                h_ineq_d = this.bineq(this.TipoRestriccionIneq == 2);
                h_eq_d = this.beq(this.TipoRestriccionEq == 2);
                h_d = [h_ineq_d; h_eq_d];
                
                fobj_slave_d = [-(h_d-F_d*y_master(1:cant_master)); -bineq_adicional];
                % dim_h_ineq_d = Nrest_ineq;
                % dim_h_eq_d = Nrest_eq;
                % dim_fobj = Nrest_ineq + Nrest_eq;

                % fija límites variables
                % si rest >=  --> var es positiva
                % si rest <=  --> var es negativa
                % si rest ==  --> var es unrest.
                
                b_slave_d = this.Fobj(this.TipoVarOpt == 2);
                lb_slave_d = zeros(1,length(fobj_slave_d));
                ub_slave_d = zeros(1,length(fobj_slave_d));
                lb_slave_d(1:cant_ineq) = -inf;
                ub_slave_d(1:cant_ineq) = 0;
                lb_slave_d(cant_ineq + 1:cant_ineq + cant_eq) = -inf;
                ub_slave_d(cant_ineq + 1:cant_ineq + cant_eq) = inf;
                lb_slave_d(cant_ineq + cant_eq+1:cant_ineq + cant_eq+cant_pos) = -inf;
                ub_slave_d(cant_ineq + cant_eq+1:cant_ineq + cant_eq+cant_pos) = 0; 
                lb_slave_d(cant_ineq + cant_eq+cant_pos+1:cant_ineq + cant_eq+cant_pos+cant_neg) = 0;
                ub_slave_d(cant_ineq + cant_eq+cant_pos+1:cant_ineq + cant_eq+cant_pos+cant_neg) = inf; 
                lb_slave_d(cant_ineq + cant_eq+cant_pos+cant_neg+1:cant_ineq + cant_eq+cant_pos+cant_neg+cant_fija) = -inf;
                ub_slave_d(cant_ineq + cant_eq+cant_pos+cant_neg+1:cant_ineq + cant_eq+cant_pos+cant_neg+cant_fija) = inf; 
                
                % restricciones:
                %aineq_slave_d = E_ineq_d';
                %bineq_slave_d = c_slave_d;
                %aeq_slave_d = E_eq_d';
                %beq_slave_d = c_slave_d;
                %a_slave_d = [E_ineq_d; E_eq_d]';
                %aineq_slave_d = E_ineq_d';
                %aeq_slave_d = E_eq_d';
                %bineq_slave_d = c_slave_d;
                %beq_slave_d = c_slave_d;
                a_slave_d = E_d';
                % a_slave: Nvar_oper x (N_rest_ineq + N_rest_eq)

                % var >= 0         --> restriccion <= 0
                % var <= 0         --> restriccion >= 0
                % var unrestricted --> restriccion = 0
                rtype_slave_d = repmat('N',[1 size(a_slave_d,1)]);
                rtype_slave_d(id_unrestricted) = 'E';
                rtype_slave_d(id_fija) = 'E';
                rtype_slave_d(id_pos) = 'L';
                rtype_slave_d(id_neg) = 'G';
                if ~isempty(find(rtype_slave_d == 'N', 1))
                    error = MException('cOptMILP:optimiza_benders_primal_dual_etapas',...
                        'No todas las variables fueron encontradas para determinar los límites de las restricciones');
                    throw(error)
                end
                %rtype_slave_d = [repmat('L',[1 size(aineq_slave_d,1)]) repmat('E',[1 size(aeq_slave_d,1)])];
                %rtype_slave_d = [repmat('G',[1 size(aineq_slave_d,1)]) repmat('L',[1 size(aeq_slave_d,1)])];
                if this.iNivelDebug > 2
                   % imprime problema esclavo dual
                   %nombres_variables = this.NombreVariables(id_slave_d);
                   nombres_variables = cell(1,0);
                   nombres_ineq = this.NombreIneq(this.TipoRestriccionIneq == 2);
                   nombres_eq = this.NombreEq(this.TipoRestriccionEq == 2);
                   for ii = 1:cant_ineq
                       nombres_variables{ii} = ['D' nombres_ineq{ii}];
                   end
                   for ii = 1:cant_eq
                       nombres_variables{cant_ineq + ii} = ['D_var_' nombres_eq{ii}];
                   end
                   nombres_variables = [nombres_variables nombres_var_d_adicionales];
                   nombres_restricciones = cell(1,0);
                   nombres_variables_orig = this.NombreVariables(this.TipoVarOpt == 2);
                   for ii = 1:cant_vars
                       nombres_restricciones{ii} = ['D_rest_' nombres_variables_orig{ii}];
                   end
                   this.imprime_problema_optimizacion_elementos_dados(fobj_slave_d, a_slave_d, b_slave_d, rtype_slave_d, lb_slave_d, ub_slave_d, [], nombres_variables, nombres_restricciones, ['lp_slave_dual_It' num2str(k)]);
                end
                
                % 3.2. optimiza esclavo dual
                [x_slave_d,fval_slave_d,flag_slave_d,output_slave_d, lambda_slave_d] = xprslp(fobj_slave_d, a_slave_d, b_slave_d,rtype_slave_d, lb_slave_d,ub_slave_d,options);%, options);
                %[x_slave_d,fval_slave_d,flag_slave_d,output_slave_d, lambda_slave_d] = xprslp(fobj_slave_d, a_slave_d, b_slave_d,rtype_slave_d, lb_slave_d,ub_slave_d,options);%, options);
                
                % 3.3. Escribe cortes: por cada escenario y etapa
                for escenario = 1:this.iCantEscenarios
                    for etapa = 1:this.iCantEtapas
                        cant_cortes = cant_cortes + 1;
                        pos_alpha = etapa + this.iCantEtapas*(escenario -1);

                        id_ineq_actual = this.TipoRestriccionIneq == 2 & this.EscenarioRestriccionIneq == escenario & this.EtapaRestriccionIneq == etapa;
                        id_eq_actual = this.TipoRestriccionEq == 2 & this.EscenarioRestriccionEq == escenario & this.EtapaRestriccionEq == etapa;
                        %id_varopt_actual = this.TipoVarOpt == 2 &  this.EscenarioVarOpt == escenario & this.EtapaVarOpt == etapa;
                        id_fobj_escenario_etapa = (this.TipoVarOpt == 1 & this.SubtipoVarOpt == 1 & this.EscenarioVarOpt == escenario & this.EtapaVarOpt == etapa);
                        id_ineq_adicional_actual = Escenario_E_ineq_adicional == escenario & Etapa_E_ineq_adicional == etapa;
                        F_ineq_d_actual = this.Aineq(id_ineq_actual,id_fobj_escenario_etapa);
                        F_eq_d_actual = this.Aeq(id_eq_actual, id_fobj_escenario_etapa);
                        F_d_actual = [F_ineq_d_actual; F_eq_d_actual];
                        
                        h_ineq_d_actual = this.bineq(id_ineq_actual);
                        h_eq_d_actual = this.beq(id_eq_actual);
                        h_d_actual = [h_ineq_d_actual; h_eq_d_actual];
                        
                        aineq_cortes(cant_cortes,:) = aineq_alpha(pos_alpha,:);
                        aineq_cortes(cant_cortes,id_fobj_escenario_etapa) = ...
                            aineq_cortes(cant_cortes,id_fobj_escenario_etapa) + round((F_d_actual'*x_slave_d([id_ineq_actual id_eq_actual])),dec_redondeo)';

                        id_x_ineq_slave_actual = this.EscenarioRestriccionIneq(this.TipoRestriccionIneq == 2 ) == escenario & this.EtapaRestriccionIneq(this.TipoRestriccionIneq == 2 ) == etapa;
                        id_x_eq_slave_actual = this.EscenarioRestriccionEq(this.TipoRestriccionEq == 2 ) == escenario & this.EtapaRestriccionEq(this.TipoRestriccionEq == 2 ) == etapa;
                        
                        id_ineq_adicional_en_x_slave_d = [false(1,cant_ineq+cant_eq) id_ineq_adicional_actual];
                        bineq_cortes(cant_cortes,1) = round(h_d_actual'*x_slave_d([id_x_ineq_slave_actual id_x_eq_slave_actual])+bineq_adicional(id_ineq_adicional_actual)'*x_slave_d(id_ineq_adicional_en_x_slave_d),dec_redondeo);

                        if this.iNivelDebug > 2
                            nombres_cortes{cant_cortes,1} = ['Corte_It' num2str(k) '_S' num2str(escenario) '_E' num2str(etapa)];
                        end
                    end
                end
                
                
                texto_nueva_sol = '';
                if z_upper(k) < best_z_upper
                    best_z_upper = z_upper(k);
                    best_sol = y_master(1:cant_master);
                    texto_nueva_sol = '*';
                end
                
                texto = sprintf('%-5s %-5s %-15s %-15s %-15s %-15s',num2str(k), texto_nueva_sol, num2str(round(z_upper(k),5)), num2str(round(z_lower(k),5)), num2str(round(best_z_upper,5)), num2str(round((best_z_upper-z_lower(k))/best_z_upper*100,5)));
                disp(texto)
                
                if (best_z_upper-z_lower(k))/best_z_upper < 0.0001
                    break
                end
            end
            % optimiza nuevamente fijando la solución y guarda solución encontrada
            this.lb(id_master) = best_sol;
            this.ub(id_master) = best_sol;
            rtype = [repmat('L',[1 size(this.Aineq,1)]) repmat('E',[1 size(this.Aeq,1)])];
            ctype = repmat('C', [1 size(this.Fobj,1)]);
            ctype(this.intcon) = 'B';
            %[this.ResOptimizacion,this.Fval,this.ExitFlag,this.Output] = xprsmip(this.Fobj,[this.Aineq; this.Aeq], [this.bineq; this.beq], rtype, ctype, [], [], this.lb,this.ub, x0);%, options);
            [this.ResOptimizacion,this.Fval,this.ExitFlag,this.Output] = xprsmip(this.Fobj,[this.Aineq; this.Aeq], [this.bineq; this.beq], rtype, ctype, [], [], this.lb,this.ub, []);%, options);             
        end
        
		function escribe_resultados_en_plan(this, resultado, plan)
            
            q = (1 + this.pParOpt.TasaDescuento);
            detapa = this.pParOpt.DeltaEtapa;
            
            % proyectos de expansion
            costo_inversion = cell.empty;
            costo_inversion_valor_presente = cell.empty;
            
            costo_operacion = cell.empty;
            costo_operacion_valor_presente = cell.empty;
            costo_generacion = cell.empty;
            costo_generacion_valor_presente = cell.empty;
            recorte_res = cell.empty;
            costo_recorte_res = cell.empty;
            costo_recorte_res_valor_presente = cell.empty;
            ens = cell.empty;
            costo_ens = cell.empty;
            costo_ens_valor_presente = cell.empty;

            for escenario = 1:this.iCantEscenarios
                plan{escenario}.Valido = true;
                costo_inversion{escenario} = zeros(this.iCantEtapas, 1);
                costo_inversion_valor_presente{escenario} = zeros(this.iCantEtapas, 1);

                for etapa = 1:this.iCantEtapas
                    plan{escenario}.inicializa_etapa(etapa);
                    for proy = 1:length(this.pAdmProy.ProyTransmision)    
                        indice_desde = this.pAdmProy.ProyTransmision(proy).entrega_varopt_expansion('Decision', escenario);
                        indice = indice_desde + etapa - 1;
                        val = resultado(indice);
                        if val > 0
                            plan{escenario}.agrega_proyecto(etapa, proy, this.pAdmProy.ProyTransmision(proy).entrega_nombre());
                            if this.pParOpt.considera_valor_residual_elementos()
                                indice_costo_desde = this.pAdmProy.ProyTransmision(proy).entrega_varopt_expansion('Costo', escenario);
                                indice_costo = indice_costo_desde + etapa - 1;
                                costo_inv = resultado(indice_costo);
                            else
                                costo_inversion_total = this.pAdmProy.ProyTransmision(proy).entrega_costos_inversion();
                                factor_desarrollo = this.pParOpt.entrega_factor_costo_desarrollo_proyectos();
                                costo_inversion_total = costo_inversion_total*factor_desarrollo;
                                costo_inv = costo_inversion_total/q^(detapa*etapa);
                            end
                            costo_inversion{escenario}(etapa) = costo_inversion{escenario}(etapa) + costo_inv;
                        end
                    end
                end
                for etapa = 1:this.iCantEtapas
                    costo_inversion_valor_presente{escenario}(etapa) = costo_inversion{escenario}(etapa)/q^(detapa*etapa);
                end
                plan{escenario}.CInv = costo_inversion{escenario};  %por cada etapa, sin llevarlo a valor actual
                plan{escenario}.CInvTActual = costo_inversion_valor_presente{escenario};
                plan{escenario}.CInvTotal = sum(costo_inversion_valor_presente{escenario});
            
                costo_operacion{escenario} = zeros(this.iCantEtapas, 1);
                costo_operacion_valor_presente{escenario} = zeros(this.iCantEtapas, 1);
                costo_generacion{escenario} = zeros(this.iCantEtapas, 1);
                costo_generacion_valor_presente{escenario} = zeros(this.iCantEtapas, 1);
                
                generadores = [this.pSEP.entrega_generadores_despachables(); this.pAdmProy.entrega_generadores_despachables_proyectados(escenario)];
                for i = 1:length(generadores)
                    for etapa = 1:this.iCantEtapas
                        indice_desde = generadores(i).entrega_varopt_operacion('P', escenario, etapa);
                        if indice_desde == 0
                            continue
                        end
                        if generadores(i).entrega_evolucion_costos_a_futuro()
                            id_adm_sc = generadores(i).entrega_indice_adm_escenario_costos_futuros(escenario);
                            costo_mwh_pu = this.pAdmSc.entrega_costos_generacion_etapa_pu(id_adm_sc, etapa);
                        else
                            costo_mwh_pu = generadores(i).entrega_costo_mwh_pu();
                        end
                        
                        indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;
                        inyecciones = resultado(indice_desde:indice_hasta);
                        rep = this.pAdmSc.RepresentatividadPuntosOperacion;
                        costo_generacion{escenario}(etapa) = costo_generacion{escenario}(etapa) + sum(costo_mwh_pu*inyecciones.*rep)/1000000;
                    end
                end
                costo_operacion{escenario} = costo_generacion{escenario};
            
                recorte_res{escenario} = zeros(this.iCantEtapas, 1);
                costo_recorte_res{escenario} = zeros(this.iCantEtapas, 1);
                costo_recorte_res_valor_presente{escenario} = zeros(this.iCantEtapas, 1);
                if this.pParOpt.considera_recorte_res()
                    generadores_res = [this.pSEP.entrega_generadores_res(); this.pAdmProy.entrega_generadores_ernc_proyectados(escenario)];
                    for i = 1:length(generadores_res)
                        sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
                        penalizacion = sbase*this.pParOpt.entrega_penalizacion(); % en $/pu
                        for etapa = 1:this.iCantEtapas
                            indice_desde = generadores_res(i).entrega_varopt_operacion('P', escenario, etapa);
                            if indice_desde == 0
                                continue
                            end
                            indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;
                            recorte = resultado(indice_desde:indice_hasta);
                            rep = this.pAdmSc.RepresentatividadPuntosOperacion;
                            recorte_res{escenario}(etapa) = recorte_res{escenario}(etapa) + sum(sbase*recorte.*rep)/1000000;
                            costo_recorte_res{escenario}(etapa) = costo_recorte_res{escenario}(etapa) + sum(penalizacion*recorte.*rep)/1000000;
                        end
                    end
                end
                costo_operacion{escenario} = costo_operacion{escenario} + costo_recorte_res{escenario};
            
                ens{escenario} = zeros(this.iCantEtapas, 1);
                costo_ens{escenario} = zeros(this.iCantEtapas, 1);
                costo_ens_valor_presente{escenario} = zeros(this.iCantEtapas, 1);
                if this.pParOpt.considera_desprendimiento_carga()
                    consumos = [this.pSEP.Consumos; this.pAdmProy.entrega_consumos_proyectados(escenario)];
                    for i = 1:length(consumos)
                        sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
                        penalizacion = sbase*this.pParOpt.entrega_penalizacion(); 
                        for etapa = 1:this.iCantEtapas
                            indice_desde = consumos(i).entrega_varopt_operacion('P', escenario, etapa);
                            if indice_desde == 0
                                continue
                            end
                            
                            indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;
                            ens_consumo = resultado(indice_desde:indice_hasta);
                            rep = this.pAdmSc.RepresentatividadPuntosOperacion;
                            ens{escenario}(etapa) = ens{escenario}(etapa) + sum(sbase*ens_consumo.*rep)/1000000;
                            costo_ens{escenario}(etapa) = costo_ens{escenario}(etapa) + sum(penalizacion*ens_consumo.*rep)/1000000;
                        end
                    end
                end
                costo_operacion{escenario} = costo_operacion{escenario} + costo_ens{escenario};
                for etapa = 1:this.iCantEtapas
                    costo_generacion_valor_presente{escenario}(etapa) = costo_generacion{escenario}(etapa)/q^(detapa*etapa);
                    costo_operacion_valor_presente{escenario}(etapa) = costo_operacion{escenario}(etapa)/q^(detapa*etapa);
                    costo_ens_valor_presente{escenario}(etapa) = costo_ens_valor_presente{escenario}(etapa)/q^(detapa*etapa);
                    costo_recorte_res_valor_presente{escenario}(etapa) = costo_recorte_res_valor_presente{escenario}(etapa)/q^(detapa*etapa);
                    res_eval = struct('Existe', true, ...
                                      'Valido', true,...
                                      'CostoGeneracion',costo_generacion{escenario}(etapa),...
                                      'CostoENS', costo_ens{escenario}(etapa),...
                                      'CostoRecorteRES', costo_recorte_res{escenario}(etapa),...
                                      'CostoOperacion', costo_operacion{escenario}(etapa), ...
                                      'LineasFlujoMaximo', [], ...
                                      'TrafosFlujoMaximo', [], ...
                                      'LineasPocoUso', [], ...
                                      'TrafosPocoUso', []);

                    plan{escenario}.inserta_evaluacion_etapa(etapa, res_eval);
                end

                plan{escenario}.COper = costo_operacion{escenario};  %por cada etapa, sin llevarlo a valor actual
                plan{escenario}.COperTActual = costo_operacion_valor_presente{escenario};
                plan{escenario}.COperTotal = sum(costo_operacion_valor_presente{escenario});

                plan{escenario}.CGen = costo_generacion{escenario};
                plan{escenario}.CGenTActual = costo_generacion_valor_presente{escenario};
                plan{escenario}.CGenTotal = sum(costo_generacion_valor_presente{escenario});

                plan{escenario}.CENS = costo_ens{escenario};
                plan{escenario}.CENSTActual = costo_ens_valor_presente{escenario};
                plan{escenario}.CENSTotal = sum(costo_ens_valor_presente{escenario});

                plan{escenario}.CRecorteRES = costo_recorte_res{escenario};
                plan{escenario}.CRecorteRESTActual = costo_recorte_res_valor_presente{escenario};
                plan{escenario}.CRecorteRESTotal = sum(costo_recorte_res_valor_presente{escenario});

                %costos totales
                plan{escenario}.Totex = plan{escenario}.CInv + plan{escenario}.COper;
                plan{escenario}.TotexTActual = plan{escenario}.CInvTActual + plan{escenario}.COperTActual;
                plan{escenario}.TotexTotal = plan{escenario}.CInvTotal + plan{escenario}.COperTotal;
            end
        end
        
        function imprime_resultados_protocolo(this)
            prot = cProtocolo.getInstance;
            prot.imprime_texto('Resultados variables optimizacion')
            prot.imprime_texto('Variables de expansion (solo proyectos desarrollados)');
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            indices_a_borrar = [];
            for escenario = 1:this.iCantEscenarios
            for etapa = 1:this.iCantEtapas
                for i=1:length(this.VarExpansion)
                    indice_expansion_base = this.VarExpansion(i).entrega_varopt_expansion('Decision', escenario);
                    indice_expansion = indice_expansion_base + etapa -1;
                    resultado_expansion = this.ResOptimizacion(indice_expansion);
                    
                    if round(resultado_expansion,dec_redondeo) == 1
                        texto = sprintf('%10s %5s %40s %3s %10s %5s %10s ', ...
                            num2str(this.lb(indice_expansion)), '<=', this.NombreVariables{indice_expansion}, '=', ...
                            num2str(this.ResOptimizacion(indice_expansion)), '<=', num2str(this.ub(indice_expansion)));
                        prot.imprime_texto(texto);
                        if this.pParOpt.considera_valor_residual_elementos()
                            indice_costo = this.VarExpansion(i).entrega_varopt_expansion('Costo', escenario) + etapa - 1;
                            texto = sprintf('%10s %5s %40s %3s %10s %5s %10s ', ...
                                num2str(this.lb(indice_costo)), '<=', this.NombreVariables{indice_costo}, '=', ...
                                num2str(this.ResOptimizacion(indice_costo)), '<=', num2str(this.ub(indice_costo)));
                            prot.imprime_texto(texto);
                            
                        end
                    end
                    indices_a_borrar = [indices_a_borrar; indice_expansion];
                    if this.pParOpt.considera_valor_residual_elementos()
                        indice_costo = this.VarExpansion(i).entrega_varopt_expansion('Costo', escenario) + etapa - 1;
                        indices_a_borrar = [indices_a_borrar; indice_costo];
                    end
                end
            end
            end
            
            prot.imprime_texto('Variables auxiliares (solo proyectos desarrollados)');
            [pinic, pd, aux] = find(this.VarAux);
            for id = 1:length(pinic)
                indice_exp = pinic(id);
                indice_proy_dep = pd(id);
                indice_aux = aux(id);
                resultado_varaux = this.ResOptimizacion(indice_aux);
                if round(resultado_varaux,dec_redondeo) == 1
                    texto = sprintf('%10s %5s %40s %3s %10s %5s %10s ', ...
                    	num2str(this.lb(indice_aux)), '<=', this.NombreVariables{indice_aux}, '=', ...
                        num2str(this.ResOptimizacion(indice_aux)), '<=', num2str(this.ub(indice_aux)));
                    prot.imprime_texto(texto);
                end
                indices_a_borrar = [indices_a_borrar; indice_aux];
            end
            theta_max = -9999;
            theta_min = 9999;
            prot.imprime_texto('Variables de operacion');
            for escenario = 1:this.iCantEscenarios
            for etapa = 1:this.iCantEtapas
                for oper = 1:this.iCantPuntosOperacion
                    for i = 1:length(this.VarOperacion)
                        if isa(this.VarOperacion(i), 'cSubestacion')
                            indice_oper = this.VarOperacion(i).entrega_varopt_operacion('Theta', escenario, etapa) + oper - 1;
                        elseif isa(this.VarOperacion(i), 'cBateria')
                            indice_oper_descarga = this.VarOperacion(i).entrega_varopt_operacion('Pdescarga', escenario, etapa) + oper - 1;
                            indice_oper_carga = this.VarOperacion(i).entrega_varopt_operacion('Pcarga', escenario, etapa) + oper - 1;
                            indice_oper_energia = this.VarOperacion(i).entrega_varopt_operacion('E', escenario, etapa) + oper - 1;
                        else
                            indice_oper = this.VarOperacion(i).entrega_varopt_operacion('P', escenario, etapa) + oper - 1;
                        end
                        if indice_oper == 0
                            % puede ser generador proyectado que aún no
                            % entra en operación
                            continue;
                        end
                        if isa(this.VarOperacion(i), 'cBateria')
                            resultado_descarga= this.ResOptimizacion(indice_oper_descarga);
                            resultado_carga = this.ResOptimizacion(indice_oper_carga);
                            resultado_energia = this.ResOptimizacion(indice_oper_energia);
                            texto = sprintf('%10s %5s %35s %3s %10s %5s %10s ', ...
                                num2str(this.lb(indice_oper_descarga)), '<=', this.NombreVariables{indice_oper_descarga}, '=', ...
                                num2str(this.ResOptimizacion(indice_oper_descarga)), '<=', num2str(this.ub(indice_oper_descarga)));
                            prot.imprime_texto(texto);

                            texto = sprintf('%10s %5s %35s %3s %10s %5s %10s ', ...
                                num2str(this.lb(indice_oper_carga)), '<=', this.NombreVariables{indice_oper_carga}, '=', ...
                                num2str(this.ResOptimizacion(indice_oper_carga)), '<=', num2str(this.ub(indice_oper_carga)));
                            prot.imprime_texto(texto);

                            texto = sprintf('%10s %5s %35s %3s %10s %5s %10s ', ...
                                num2str(this.lb(indice_oper_energia)), '<=', this.NombreVariables{indice_oper_energia}, '=', ...
                                num2str(this.ResOptimizacion(indice_oper_energia)), '<=', num2str(this.ub(indice_oper_energia)));
                            prot.imprime_texto(texto);
                            indices_a_borrar = [indices_a_borrar; indice_oper_descarga; indice_oper_carga; indice_oper_energia];
                        else
                            resultado_oper = this.ResOptimizacion(indice_oper);
                            texto = sprintf('%10s %5s %35s %3s %10s %5s %10s ', ...
                                num2str(this.lb(indice_oper)), '<=', this.NombreVariables{indice_oper}, '=', ...
                                num2str(this.ResOptimizacion(indice_oper)), '<=', num2str(this.ub(indice_oper)));
                            prot.imprime_texto(texto);
                            indices_a_borrar = [indices_a_borrar; indice_oper];
                        end
                        if isa(this.VarOperacion(i), 'cSubestacion')
                            if resultado_oper < theta_min
                                theta_min = resultado_oper;
                            elseif resultado_oper > theta_max
                                theta_max = resultado_oper;
                            end
                        end                        
                    end
                end
            end
            end
            prot.imprime_texto(['Theta min: ' num2str(theta_min)]);
            prot.imprime_texto(['Theta max: ' num2str(theta_max)]);

            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            prot.imprime_texto('');
            dec_redondeo = 2;
            for escenario = 1:this.iCantEscenarios
            for etapa = 1:this.iCantEtapas
            	prot.imprime_texto(['Escenario ' num2str(escenario) ' Etapa: ' num2str(etapa)]);
                baterias_todas = this.pAdmProy.entrega_baterias();
                p_baterias_descarga = zeros(length(baterias_todas),this.iCantPuntosOperacion);
                p_baterias_carga = zeros(length(baterias_todas),this.iCantPuntosOperacion);
                e_baterias = zeros(length(baterias_todas),this.iCantPuntosOperacion);
                estado_baterias_en_etapa = zeros(length(baterias_todas),1);
                for oper = 1:this.iCantPuntosOperacion
                    gen_total_oper = 0;
                    gen_bat_total_oper = 0;
                    res_total_oper = 0;
                    consumo_total_oper = 0;
                    spill_total_oper = 0;
                    ens_total_oper = 0;
                    
                	prot.imprime_texto(['PO: ' num2str(oper)]);
                    prot.imprime_texto('Balance de energia');
                    texto = sprintf('%-15s %-15s %-15s %-10s %-10s %-10s %-10s %-10s %-10s %-10s', 'Subestacion', 'Generacion', 'Bateria', 'ERNC', 'Consumo', 'Spill', 'ENS', 'Pin', 'Pout', 'Balance');
                    prot.imprime_texto(texto);
                    
                    subestaciones = this.pSEP.entrega_subestaciones();
                    se_proyectadas = this.pAdmProy.entrega_subestaciones_proyectadas(escenario);            
                    for ii = 1:length(se_proyectadas)
                        if se_proyectadas(ii).entrega_etapa_entrada(escenario)<= etapa
                            subestaciones = [subestaciones; se_proyectadas(ii)];
                        end
                    end
                    subestaciones = [subestaciones; this.pAdmProy.entrega_subestaciones_expansion()];
                    
                    for se = 1:length(subestaciones)
                        suma_gen = 0;
                        suma_capacidad_gen = 0;
                        %generadores
                        generadores = [];
                        gen_desp = subestaciones(se).entrega_generadores_despachables();
                        for ii = 1:length(gen_desp)
                            if gen_desp(ii).entrega_varopt_operacion('P', escenario, etapa) ~= 0
                                generadores = [generadores; gen_desp(ii)];
                            end
                        end
                        gen_proy = this.pAdmProy.entrega_generadores_despachables_proyectados(escenario);
                        for ii = 1:length(gen_proy)
                            if gen_proy(ii).entrega_se == subestaciones(se) && gen_proy(ii).entrega_varopt_operacion('P', escenario, etapa) ~= 0
                                generadores = [generadores; gen_proy(ii)];
                            end
                        end
                        
                        for gen = 1:length(generadores)
                        	indice_gen = generadores(gen).entrega_varopt_operacion('P', escenario, etapa) + oper - 1;
                            if generadores(gen).entrega_evolucion_capacidad_a_futuro()
                                id_adm_sc = generadores(gen).entrega_indice_adm_escenario_capacidad(escenario);
                                capacidad = this.pAdmSc.entrega_capacidad_generador(id_adm_sc, etapa);
                            else
                                capacidad = generadores(gen).entrega_pmax();
                            end
                            
                            suma_capacidad_gen = suma_capacidad_gen + capacidad;
                            valor = this.ResOptimizacion(indice_gen)*sbase;
                            suma_gen = suma_gen + valor;
                        end
                        
                        % baterías
                        suma_bat = 0;
                        suma_capacidad_bat = 0;
                        baterias = this.pAdmProy.entrega_baterias_por_subestacion(subestaciones(se));
                        for bat = 1:length(baterias)
                            indice_bat_p_descarga = baterias(bat).entrega_varopt_operacion('Pdescarga', escenario, etapa) + oper - 1;
                            indice_bat_p_carga = baterias(bat).entrega_varopt_operacion('Pcarga', escenario, etapa) + oper - 1;
                            indice_bat_e = baterias(bat).entrega_varopt_operacion('E', escenario, etapa) + oper - 1;
                            p_bat_descarga = this.ResOptimizacion(indice_bat_p_descarga);
                            p_bat_carga = this.ResOptimizacion(indice_bat_p_carga);
                            e_bat = this.ResOptimizacion(indice_bat_e);
                            existe_en_sep_actual = baterias(bat).Existente;
                            
                            p_baterias_descarga(baterias(bat).entrega_id_adm_proyectos(), oper) = p_bat_descarga;
                            p_baterias_carga(baterias(bat).entrega_id_adm_proyectos(), oper) = p_bat_carga;
                            e_baterias(baterias(bat).entrega_id_adm_proyectos(), oper) = e_bat;
                            
                            existente = false;
                            removido = false;
                            agregado = false;
                            etapa_agregado = 0;
                            etapa_removido = 0;

                            for etapa_previa = 1:etapa
                                % Identifica proyectos que contienen este elemento. Se incluye variable que indica si proyecto se construye o no
                                for proy = 1:length(this.pAdmProy.ProyTransmision)
                                    [existe, accion] = this.pAdmProy.ProyTransmision(proy).existe_elemento(baterias(bat));
                                    if existe
                                        indice_expansion = this.pAdmProy.ProyTransmision(proy).entrega_varopt_expansion('Decision', escenario) + etapa_previa - 1;
                                        valor_exp = round(this.ResOptimizacion(indice_expansion),dec_redondeo);
                                        if valor_exp == 1
                                        	% proyecto se ejecuta en etapa "etapa_previa"
                                            if strcmp(accion, 'A')
                                                if existe_en_sep_actual
                                                    texto = ['Inconsistencia en los datos, ya que línea existente ' baterias(bat).entrega_nombre() ' no puede ser agregada como proyecto de expansión'];
                                                    error = MException('cOptMILP:imprime_resultados_protocolo',texto);
                                                    throw(error)
                                                end
                                                if etapa_agregado ~= 0
                                                    error = MException('cOptMILP:imprime_resultados_protocolo',...
                                                    	'Inconsistencia en los resultados, ya que línea ya fue agregada en otro proyecto');
                                                    throw(error)
                                                else
                                                	etapa_agregado = etapa_previa;
                                                    agregado = true;
                                                end
                                            else % acción es de remover
                                                if etapa_removido ~= 0
                                                    error = MException('cOptMILP:imprime_resultados_protocolo',...
                                                    	'Inconsistencia en los resultados, ya que línea ya fue removida en otro proyecto');
                                                    throw(error)
                                                else
                                                	etapa_removido = etapa_previa;
                                                    removido = true;
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                            %verifica consistencia en los datos. Bateria tiene que ser agregada/o antes de ser removida
                            if existe_en_sep_actual
                                if removido
                                    existente = false; % redundante pero para mayor comprensión del código
                                else
                                    existente = true;
                                end
                            else %elemento proyectado
                                if agregado && removido
                                    if etapa_removido < etapa_agregado
                                        error = MException('cOptMILP:imprime_resultados_protocolo',...
                                        	'Inconsistencia en los resultados, ya que elemento fue removido antes de ser agregada');
                                        throw(error)
                                    else
                                        existente = false; % redundante, pero para mayor comprensión del código
                                    end
                                elseif removido && ~agregado
                                    error = MException('cOptMILP:imprime_resultados_protocolo',...
                                        'Inconsistencia en los resultados, ya que línea proyectada fue removida pero no agregada previamente');
                                    throw(error)
                                elseif agregado
                                    existente = true;
                                end
                            end
                            if ~existente
                                if p_bat_descarga ~= 0 || p_bat_carga ~= 0
                                    texto = 'Inconsistencia en los datos, ya que batería no existe ';
                                    texto = [texto bateria(bat).entrega_nombre()];
                                    texto = [texto ' tiene potencia distinta de cero. PBateria: ' num2str(p_bat)];
                                    %warning(texto)
                                    error = MException('cOptMILP:imprime_resultados_protocolo',texto);
                                    throw(error)
                                end
                            else
                                suma_bat = suma_bat + (p_bat_descarga-p_bat_carga)*sbase;
                                suma_capacidad_bat = suma_capacidad_bat + baterias(bat).entrega_pmax_carga();
                                gen_bat_total_oper = gen_bat_total_oper + suma_bat;
                                estado_baterias_en_etapa(baterias(bat).entrega_id_adm_proyectos()) = 1;
                            end
                        end %fin baterias

                        %consumos
                        p_consumo = 0;
                        
                        consumos = [];
                        for ii = 1:length(subestaciones(se).Consumos)
                            if subestaciones(se).Consumos(ii).EtapaSalida == 0 || ...
                               (subestaciones(se).Consumos(ii).EtapaSalida > etapa)
                                consumos = [consumos; subestaciones(se).Consumos(ii)];
                            end
                        end
                        % proyectados
                        con_proy = this.pAdmProy.entrega_consumos_proyectados(escenario);
                        for ii = 1:length(con_proy)
                            if con_proy(ii).EtapaEntrada <= etapa && ...
                                    con_proy(ii).EtapaSalida > etapa && ...
                                    con_proy(ii).entrega_se() == subestaciones(se)
                                consumos = [consumos; con_proy(ii)];
                            end
                        end
                        
                        ens = 0;
                        for con = 1:length(consumos)
                            indice_perfil = consumos(con).entrega_indice_adm_escenario_perfil_p();
                            perfil = this.pAdmSc.entrega_perfil_consumo(indice_perfil);
                            indice_capacidad = consumos(con).entrega_indice_adm_escenario_capacidad(escenario);
                            capacidad = this.pAdmSc.entrega_capacidad_consumo(indice_capacidad, etapa);

                            p_consumo = p_consumo + capacidad*perfil(oper);
                            if this.pParOpt.considera_desprendimiento_carga()
                                indice_cons = consumos(con).entrega_varopt_operacion('P', escenario, etapa) + oper - 1;
                                valor = this.ResOptimizacion(indice_cons)*sbase;
                                ens = ens + valor;
                            end
                        end
                        
                        gen_res = 0;
                        spill = 0;
                        generadores_res = subestaciones(se).entrega_generadores_res();
                        gen_proy = this.pAdmProy.entrega_generadores_ernc_proyectados(escenario);
                        for ii = 1:length(gen_proy)
                            if gen_proy(ii).entrega_se == subestaciones(se) && gen_proy(ii).EtapaEntrada(escenario) <= etapa
                                generadores_res = [generadores_res; gen_proy(ii)];
                            end
                        end

                        for gen = 1:length(generadores_res)
                            indice_perfil = generadores_res(gen).entrega_indice_adm_escenario_perfil_ernc();
                            perfil_ernc = this.pAdmSc.entrega_perfil_ernc(indice_perfil);
                            if generadores_res(gen).entrega_evolucion_capacidad_a_futuro()
                                indice_capacidad = generadores_res(gen).entrega_indice_adm_escenario_capacidad(escenario);
                                capacidad = this.pAdmSc.entrega_capacidad_generador(indice_capacidad, etapa);
                            else
                                capacidad = generadores_res(gen).entrega_pmax();
                            end
                            
                            gen_res = gen_res + capacidad*perfil_ernc(oper);
                            if this.pParOpt.considera_recorte_res()
                                indice_gen_res = generadores_res(gen).entrega_varopt_operacion('P', escenario, etapa) + oper - 1;
                                valor = this.ResOptimizacion(indice_gen_res)*sbase;
                                spill = spill + valor;
                            end
                        end
                        
                        %lineas y trafos
                        el_serie = this.pAdmProy.entrega_elementos_serie_por_subestacion(subestaciones(se));
                        el_proy = this.pAdmProy.entrega_elementos_red_proyectados_por_subestacion(escenario, subestaciones(se));
                        for jj = 1:length(el_proy)
                            if el_proy(jj).EtapaEntrada <= etapa
                                el_serie = [el_serie; el_proy(jj)];
                            end
                        end
                        el_serie = [el_serie; el_proy];
                        
                        pin = 0;
                        pout = 0;
                        for serie = 1:length(el_serie)
                        	[se_1, se_2] = el_serie(serie).entrega_subestaciones();
                            indice_elserie = el_serie(serie).entrega_varopt_operacion('P', escenario, etapa) + oper - 1;
                            p_serie = this.ResOptimizacion(indice_elserie);
                            if se_1 == subestaciones(se)
                            	signo = -1; % linea va de SE1 a SE2 por lo que flujo sale de la subestacion
                            elseif se_2 == subestaciones(se)
                            	signo = 1;
                            else
                            	error = MException('cOptMILP:imprime_resultados_protocolo',...
                                    'Inconsistencia en los datos, ya que elemento serie no pertenece a subestacion');
                                throw(error)
                            end
                            
                            % identifica si elemento está operativo o no. Una
                            % línea/trafo existente sólo puede ser removida/o de la
                            % red, pero no puede ser nuevamente agregada
                            existe_en_sep_actual = el_serie(serie).Existente || (el_serie(serie).entrega_etapa_entrada(escenario) ~= 0 && el_serie(serie).entrega_etapa_entrada(escenario) <= etapa);
                            
                            existente = false;
                            removido = false;
                            agregado = false;
                            etapa_agregado = 0;
                            etapa_removido = 0;
                            
                            for etapa_previa = 1:etapa
                                % Identifica proyectos que contienen este elemento. Se
                                % incluye variable que indica si proyecto se construye
                                % o no
                                for proy = 1:length(this.pAdmProy.ProyTransmision)
                                    [existe, accion] = this.pAdmProy.ProyTransmision(proy).existe_elemento(el_serie(serie));
                                    if existe
                                        indice_expansion = this.pAdmProy.ProyTransmision(proy).entrega_varopt_expansion('Decision', escenario) + etapa_previa - 1;
                                        valor_exp = round(this.ResOptimizacion(indice_expansion),dec_redondeo);
                                        if valor_exp == 1
                                        	% proyecto se ejecuta en
                                            % etapa "etapa_previa"
                                            if strcmp(accion, 'A')
                                                if existe_en_sep_actual
                                                    texto = ['Inconsistencia en los datos, ya que línea existente ' el_serie(serie).entrega_nombre() ' no puede ser agregada como proyecto de expansión'];
                                                    error = MException('cOptMILP:imprime_resultados_protocolo',texto);
                                                    throw(error)
                                                end
                                                if etapa_agregado ~= 0
                                                    error = MException('cOptMILP:imprime_resultados_protocolo',...
                                                    	'Inconsistencia en los resultados, ya que línea ya fue agregada en otro proyecto');
                                                    throw(error)
                                                else
                                                	etapa_agregado = etapa_previa;
                                                    agregado = true;
                                                end
                                            else % acción es de remover
                                                if etapa_removido ~= 0
                                                    error = MException('cOptMILP:imprime_resultados_protocolo',...
                                                    	'Inconsistencia en los resultados, ya que línea ya fue removida en otro proyecto');
                                                    throw(error)
                                                else
                                                	etapa_removido = etapa_previa;
                                                    removido = true;
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                            %verifica consistencia en los datos.
                            %Línea/trafo tiene que ser agregada/o antes de
                            %ser removida/o
                            if existe_en_sep_actual
                                if removido
                                    existente = false; % redundante pero para mayor comprensión del código
                                else
                                    existente = true;
                                end
                            else %elemento proyectado
                                if agregado && removido
                                    if etapa_removido < etapa_agregado
                                        error = MException('cOptMILP:imprime_resultados_protocolo',...
                                        	'Inconsistencia en los resultados, ya que elemento fue removido antes de ser agregada');
                                        throw(error)
                                    else
                                        existente = false; % redundante, pero para mayor comprensión del código
                                    end
                                elseif removido && ~agregado
                                    error = MException('cOptMILP:imprime_resultados_protocolo',...
                                        'Inconsistencia en los resultados, ya que línea proyectada fue removida pero no agregada previamente');
                                    throw(error)
                                elseif agregado
                                    existente = true;
                                end
                            end
                            if ~existente
                                if p_serie ~= 0
                                    texto = 'Inconsistencia en los datos, ya que línea no existente ';
                                    texto = [texto el_serie(serie).entrega_nombre()];
                                    texto = [texto ' tiene potencia distinta de cero. Plinea: ' num2str(p_serie)];
                                    %warning(texto)
                                    error = MException('cOptMILP:imprime_resultados_protocolo',texto);
                                    throw(error)
                                end
                            else
                                if signo*p_serie < 0
                                	pout = pout - signo*p_serie*sbase;
                                else
                                	pin = pin + signo*p_serie*sbase;
                                end
                            end
                        end %fin elementos de red proyectos
                        gen_total_oper = gen_total_oper + suma_gen;

                        res_total_oper = res_total_oper + gen_res;
                        consumo_total_oper = consumo_total_oper + p_consumo;
                        spill_total_oper = spill_total_oper + spill;
                        ens_total_oper = ens_total_oper + ens;
                        
                        texto_generacion = [num2str(suma_gen) '/' num2str(suma_capacidad_gen)];
                        texto_bateria = [num2str(suma_bat) '/' num2str(suma_capacidad_bat)];
                        texto = sprintf('%-15s %-15s %-15s %-10s %-10s %-10s %-10s %-10s %-10s %-10s', subestaciones(se).entrega_nombre(), ...
                            texto_generacion,...
                            texto_bateria, ...
                            num2str(round(gen_res,dec_redondeo)),...
                            num2str(round(p_consumo,dec_redondeo)),...
                            num2str(round(spill,dec_redondeo)),...
                            num2str(round(ens,dec_redondeo)),...
                            num2str(round(pin,dec_redondeo)),...
                            num2str(round(pout,dec_redondeo)),...
                            num2str(round(suma_gen+gen_res+suma_bat-p_consumo+ens-spill+pin-pout,dec_redondeo)));
                        prot.imprime_texto(texto); 
                    end %fin subestaciones
                    
                    texto = sprintf('%-15s %-15s %-15s %-10s %-10s %-10s %-10s %-10s %-10s', 'Total', ...
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
                    texto = sprintf('%-25s %-15s %-15s %-7s %-8s %-8s %-8s %-8s %-8s %-8s %-15s %-10s', ...
                        'Linea', 'SE1', 'SE2', 'Signo', 'T1rad', 'T2rad', 'T1-T2', 'Xel', 'PMW', 'Pmax', 'Dif.calculado', 'dT>=ParDisy');
                    prot.imprime_texto(texto);
                    for se1 = 1:length(subestaciones)
                        el_serie = this.pAdmProy.entrega_elementos_serie_por_subestacion(subestaciones(se1));
                        el_proy = this.pAdmProy.entrega_elementos_red_proyectados_por_subestacion(escenario, subestaciones(se1));
                        for jj = 1:length(el_proy)
                            if el_proy(jj).EtapaEntrada <= etapa
                                el_serie = [el_serie; el_proy(jj)];
                            end
                        end
                        el_serie = [el_serie; el_proy];
                        for se2 = se1+1:length(subestaciones)
                            se_conectan = false;
                        	indice_se1 = subestaciones(se1).entrega_varopt_operacion('Theta', escenario, etapa) + oper - 1;
                            t1 = this.ResOptimizacion(indice_se1);
                        	indice_se2 = subestaciones(se2).entrega_varopt_operacion('Theta', escenario, etapa) + oper - 1;
                            t2 = this.ResOptimizacion(indice_se2);
                            for serie = 1:length(el_serie)
                                [se_1, se_2] = el_serie(serie).entrega_subestaciones();
                                if se_1 ~= subestaciones(se2) && se_2 ~= subestaciones(se2)
                                    continue;
                                end
                                indice_elserie = el_serie(serie).entrega_varopt_operacion('P', escenario, etapa) + oper - 1;
                                par_disy = this.entrega_parametro_disyuntivo_base(se_1.entrega_id(), se_2.entrega_id())/el_serie(serie).entrega_reactancia_pu();
                                p_serie = this.ResOptimizacion(indice_elserie)*sbase;
                                sr = el_serie(serie).entrega_sr();
                                if se_1 == subestaciones(se1)
                                    signo = 1; % linea va de SE1 a SE2 por lo que flujo sale de la subestacion
                                else
                                    signo = -1;
                                end
                                
                                if p_serie ~= 0
                                    se_conectan = true;
                                    x = el_serie(serie).entrega_reactancia_pu();
                                    angulo_1 = round(t1/pi*180,1);
                                    angulo_2 = round(t2/pi*180,1);
                                        
                                    diff_angulo = round((t1-t2)/pi*180,1);
                                    diff_calculado = signo*(t1-t2)/x*sbase;
                                    diff_calculado = diff_calculado-p_serie;
                                    texto_par_disy = '';
                                    if abs((t1-t2)) >= par_disy
                                        texto_par_disy = '*';
                                    end
                                    texto = sprintf('%-25s %-15s %-15s %-7s %-8s %-8s %-8s %-8s %-8s %-8s %-15s %-10s ', ...
                                        el_serie(serie).entrega_nombre(), ...
                                        subestaciones(se1).entrega_nombre(), ...
                                        subestaciones(se2).entrega_nombre(), ...
                                        num2str(signo), ...
                                        num2str(round(t1,4)), ...
                                        num2str(round(t2,4)), ...
                                        num2str(round((t1-t2),4)), ...
                                        num2str(round(x,3)), ...
                                        num2str(round(p_serie,3)), ...
                                        num2str(round(sr,3)), ...
                                        num2str(round(diff_calculado,2)), ...
                                        texto_par_disy);
                                    prot.imprime_texto(texto);
                                end
                            end
                        end
                    end %fin subestaciones
                    prot.imprime_texto('');
                end % fin puntos de operación
                
                % balance energético baterías
                if ~isempty(baterias)
                    prot.imprime_texto('');
                    prot.imprime_texto(['Balance energetico baterias en etapa ' num2str(etapa) ':']);

                    baterias = this.pAdmProy.entrega_baterias();
                    p_baterias_descarga = round(p_baterias_descarga*sbase,2);
                    p_baterias_carga = round(p_baterias_carga*sbase,2);
                    e_baterias = round(e_baterias*sbase, 2);
                    texto_base = sprintf('%-30s','');
                    for j = 1:this.iCantPuntosOperacion
                        texto_base = [texto_base sprintf('%-10s',num2str(j))];
                    end
                    prot.imprime_texto(texto_base);
                    for i = 1:length(baterias)
                        eta_bat_descarga = baterias(i).entrega_eficiencia_descarga();
                        eta_bat_carga = baterias(i).entrega_eficiencia_carga();                    
                        if estado_baterias_en_etapa(i) > 0
                            nombre_bat = baterias(i).entrega_nombre();
                            prot.imprime_texto(nombre_bat);
                            texto_base_p = sprintf('%-30s','Pbat');
                            texto_base_e = sprintf('%-30s','Ebat');
                            texto_base_bal = sprintf('%-30s','Balance');
                            indice_po_consecutivo_actual = 1;
                            [cant_po_consecutivos,~] = size(this.vIndicesPOConsecutivos);
                            for j = 1:this.iCantPuntosOperacion
                                if indice_po_consecutivo_actual < cant_po_consecutivos && j == this.vIndicesPOConsecutivos(indice_po_consecutivo_actual,1)
                                   inicio_nuevo_periodo = true;
                                   indice_po_consecutivo_actual = indice_po_consecutivo_actual + 1;
                                else
                                    inicio_nuevo_periodo = false;
                                end

                                texto_base_p = [texto_base_p sprintf('%-10s',num2str(p_baterias_descarga(i,j)-p_baterias_carga(i,j)))];
                                texto_base_e = [texto_base_e  sprintf('%-10s',num2str(e_baterias(i,j)))];
                                if inicio_nuevo_periodo == 1
                                    balance_calculado = 0;
                                else
                                    balance_calculado = round(e_baterias(i,j)-e_baterias(i,j-1)+1/eta_bat_descarga*p_baterias_descarga(i,j-1)-eta_bat_carga*p_baterias_carga(i,j-1),4);
                                end
                                texto_base_bal = [texto_base_bal sprintf('%-10s',num2str(balance_calculado))];
                            end
                            prot.imprime_texto(texto_base_p);
                            prot.imprime_texto(texto_base_e);
                            prot.imprime_texto(texto_base_bal);
                        end
                    end
                end
            end % fin cantidad de etapas
            end
        end

        function imprime_resultados_variables_al_limite(this)
            prot = cProtocolo.getInstance;
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            prot.imprime_texto('Resultados variables optimizacion')
            prot.imprime_texto('Variables de expansion (solo proyectos desarrollados)');
            for escenario = 1:this.iCantEscenarios
            for etapa = 1:this.iCantEtapas
                for i=1:length(this.VarExpansion)
                    indice_expansion = this.VarExpansion(i).entrega_varopt_expansion('Decision', escenario) + etapa - 1;
                    resultado_expansion = this.ResOptimizacion(indice_expansion);
                    
                    if round(resultado_expansion,dec_redondeo) == 1
                        texto = sprintf('%10s %5s %40s %3s %10s %5s %10s ', ...
                            num2str(this.lb(indice_expansion)), '<=', this.NombreVariables{indice_expansion}, '=', ...
                            num2str(this.ResOptimizacion(indice_expansion)), '<=', num2str(this.ub(indice_expansion)));
                        prot.imprime_texto(texto);

                        if this.pParOpt.considera_valor_residual_elementos()
                            indice_costo = this.VarExpansion(i).entrega_varopt_expansion('Costo', escenario) + etapa - 1;
                            texto = sprintf('%10s %5s %40s %3s %10s %5s %10s ', ...
                                num2str(this.lb(indice_costo)), '<=', this.NombreVariables{indice_costo}, '=', ...
                                num2str(this.ResOptimizacion(indice_costo)), '<=', num2str(this.ub(indice_costo)));
                            prot.imprime_texto(texto);
                        end
                    end
                end
            end
            end
            prot.imprime_texto('Variables auxiliares (solo proyectos desarrollados)');
            [pinic, ~, aux] = find(this.VarAux);
            for id = 1:length(pinic)
                indice_aux = aux(id);
                resultado_varaux = this.ResOptimizacion(indice_aux);
                if round(resultado_varaux,dec_redondeo) == 1
                    texto = sprintf('%10s %5s %40s %3s %10s %5s %10s ', ...
                    	num2str(this.lb(indice_aux)), '<=', this.NombreVariables{indice_aux}, '=', ...
                        num2str(this.ResOptimizacion(indice_aux)), '<=', num2str(this.ub(indice_aux)));
                    prot.imprime_texto(texto);
                end
            end
            prot.imprime_texto('Variables de operacion (que llegaron al limite o cerca de el)');
            for escenario = 1:this.iCantEscenarios
            for etapa = 1:this.iCantEtapas
                for oper = 1:this.iCantPuntosOperacion                
                    for i = 1:length(this.VarOperacion)
                        if isa(this.VarOperacion(i), 'cSubestacion')
                            indice_oper = this.VarOperacion(i).entrega_varopt_operacion('Theta', escenario, etapa) + oper - 1;
                        elseif isa(this.VarOperacion(i), 'cLinea') || isa(this.VarOperacion(i), 'cTransformador2D')
                            indice_oper = this.VarOperacion(i).entrega_varopt_operacion('P', escenario, etapa) + oper - 1;
                        elseif isa(this.VarOperacion(i), 'cBateria')
                            indice_oper = this.VarOperacion(i).entrega_varopt_operacion('E', escenario, etapa) + oper - 1;
                        else
                            indice_oper = 0;
                        end
                        if indice_oper == 0
                            continue
                        end
                        resultado_oper = this.ResOptimizacion(indice_oper);
                        lim_inferior = this.lb(indice_oper);
                        lim_superior = this.ub(indice_oper);
                        if isa(this.VarOperacion(i), 'cSubestacion') || ...
                                isa(this.VarOperacion(i), 'cLinea') || ...
                                isa(this.VarOperacion(i), 'cTransformador2D')                                
                            if resultado_oper >= lim_superior*0.99 || ...
                                resultado_oper <= lim_inferior*0.99
                                texto = sprintf('%10s %5s %35s %3s %10s %5s %10s ', ...
                                    num2str(this.lb(indice_oper)), '<=', this.NombreVariables{indice_oper}, '=', ...
                                    num2str(this.ResOptimizacion(indice_oper)), '<=', num2str(this.ub(indice_oper)));
                                prot.imprime_texto(texto);
                            end
                        elseif isa(this.VarOperacion(i), 'cBateria')
                            if resultado_oper == lim_inferior
                                texto = sprintf('%10s %5s %35s %3s %10s %5s %10s ', ...
                                    num2str(this.lb(indice_oper)), '<=', this.NombreVariables{indice_oper}, '=', ...
                                    num2str(this.ResOptimizacion(indice_oper)), '<=', num2str(this.ub(indice_oper)));
                                prot.imprime_texto(texto);                                
                            end
                        end
                    end
                end
            end
            end
        end
        
        function imprime_problema_optimizacion_elementos_dados(this, Fobj, A, b, rtype, lb, ub, intcon, nombres_var, nombres_restricciones, nombre_output)
            docID = fopen(['./output/debug/' nombre_output '.dat'],'w');
            fprintf(docID, 'Problema de optimizacion\n');
            fprintf(docID, '\n\n');
            fprintf(docID, 'Funcion objetivo\n');
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            indices_validos = find(Fobj ~= 0);
            primero = true;
            for i = 1:length(indices_validos)
                id = indices_validos(i);
                val = round(Fobj(id),dec_redondeo);
                if primero
                    text = strcat(num2str(val),'*',nombres_var{id});
                    primero = false;
                else
                    if Fobj(id) > 0
                        text = strcat(text, ' + ',num2str(val),'*', nombres_var{id});
                    else
                        text = strcat(text, ' - ',num2str(abs(val)),'*',nombres_var{id});
                    end
                    if length(text) > 135
                        text = strcat(text,'\n');
                        fprintf(docID, text);
                        primero = true;
                        text = '';
                    end
                end
            end
            text = strcat(text,'\n');
            fprintf(docID, text);
            % restricciones
            % restricciones de desigualdad
            fprintf(docID, 'Restricciones:\n');
            for i = 1:length(b)                
                fprintf(docID, strcat('R', num2str(i), '_', nombres_restricciones{i},':\n'));
                primero = true;
                indices_validos = find(A(i,:) ~= 0);
                text = '';
                for id = 1:length(indices_validos)
                    j = indices_validos(id);
                    val = A(i,j);
                    
                    if primero
                        if val == 1
                            text = nombres_var{j};
                        elseif val == -1
                            text = strcat('- ', nombres_var{j});
                        else
                            text = strcat(num2str(val), '*', nombres_var{j});
                            %error = MException('cOptMILP:imprime_problema_optimizacion','valor restriccion de desigualdad debe ser 1 o -1');
                            %throw(error)
                        end
                        primero = false;
                    else
                        if val == 1
                            text = strcat(text, ' + ', nombres_var{j});
                        elseif val == -1
                            text = strcat(text, ' - ', nombres_var{j});
                        elseif val > 0
                            text = strcat(text, ' + ', num2str(val), '*', nombres_var{j});
                        else
                            text = strcat(text, ' - ', num2str(abs(val)), '*', nombres_var{j});
                            %error = MException('cOptMILP:imprime_problema_optimizacion','valor restriccion de desigualdad debe ser 1 o -1');
                            %throw(error)
                        end
                        if length(text) > 135
                            text = strcat(text,'\n');
                            fprintf(docID, text);
                            primero = true;
                            text = '';
                        end
                    end
                end
                if strcmp(rtype(i),'L')
                    text = strcat(text,' <= ', num2str(b(i)),'\n\n');
                elseif strcmp(rtype(i),'E')
                    text = strcat(text,' = ', num2str(b(i)),'\n\n');
                elseif strcmp(rtype(i),'G')
                    text = strcat(text,' >= ', num2str(b(i)),'\n\n');
                end
                fprintf(docID, text);
            end
            
            % límites de las variables
            fprintf(docID, 'Limites variables de decision:\n');
            for i = 1:length(lb)
                text = strcat(num2str(lb(i)), ' <= ', nombres_var{i}, ' <= ', num2str(ub(i)), '\n');
                fprintf(docID, text);
            end
            
            %variables binarias
            if ~isempty(intcon)
                fprintf(docID, '\nVariables binarias:\n');
                for i = 1:length(intcon)
                    text = nombres_var{intcon(i)};
                    text = strcat(text, '\n');
                    fprintf(docID, text);
                end
                text = strcat(text,'\n');
                fprintf(docID, text);
            end
            
            %todas las variables por índice
            fprintf(docID, '\nTodas las variables:\n');
            for i = 1:length(nombres_var)
                text = [num2str(i) ' ' nombres_var{i} '\n'];
                fprintf(docID, text);
            end
            fprintf(docID, '\nfin');
            fclose(docID);            
        end
        
        function imprime_problema_optimizacion(this)
            disp('imprime problema optimizacion');
            
            % funcion objetivo
            docID = fopen('./output/milp.dat','w');
            fprintf(docID, 'Problema de optimizacion\n');
            if this.iCantEscenarios == 1
                fprintf(docID, 'Problema deterministico\n');
            else
                fprintf(docID, 'Problema con incertidumbre\n');                
            end
            fprintf(docID, '\n\n');
            fprintf(docID, 'Funcion objetivo\n');
            con_indices = this.pParOpt.ImprimeConIndices;
            if con_indices
                nombres = cell(length(this.NombreVariables),1);
                for i = 1:length(this.NombreVariables)
                    nombres{i} = ['x' '(' num2str(i) ')'];
                end
            else
                nombres = this.NombreVariables;
            end

            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            indices_validos = find(this.Fobj ~= 0);
            primero = true;
            for i = 1:length(indices_validos)
                id = indices_validos(i);
                val = round(this.Fobj(id),dec_redondeo);
                if primero
                    text = strcat(num2str(val),'*',nombres{id});
                    primero = false;
                else
                    if this.Fobj(id) > 0
                        text = strcat(text, ' + ',num2str(val),'*', nombres{id});
                    else
                        text = strcat(text, ' - ',num2str(abs(val)),'*',nombres{id});
                    end
                    if length(text) > 135
                        text = strcat(text,'\n');
                        fprintf(docID, text);
                        primero = true;
                        text = '';
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
                indices_validos = find(this.Aineq(i,:) ~= 0);
                for id = 1:length(indices_validos)
                    j = indices_validos(id);
                    val = this.Aineq(i,j);
                    
                    if primero
                        if val == 1
                            text = nombres{j};
                        elseif val == -1
                            text = strcat('- ', nombres{j});
                        else
                            text = strcat(num2str(val), '*', nombres{j});
                            %error = MException('cOptMILP:imprime_problema_optimizacion','valor restriccion de desigualdad debe ser 1 o -1');
                            %throw(error)
                        end
                        primero = false;
                    else
                        if val == 1
                            text = strcat(text, ' + ', nombres{j});
                        elseif val == -1
                            text = strcat(text, ' - ', nombres{j});
                        elseif val > 0
                            text = strcat(text, ' + ', num2str(val), '*', nombres{j});
                        else
                            text = strcat(text, ' - ', num2str(abs(val)), '*', nombres{j});
                            %error = MException('cOptMILP:imprime_problema_optimizacion','valor restriccion de desigualdad debe ser 1 o -1');
                            %throw(error)
                        end
                        if length(text) > 135
                            text = strcat(text,'\n');
                            fprintf(docID, text);
                            primero = true;
                            text = '';
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
                indices_validos = find(this.Aeq(i,:) ~= 0);
                for id = 1:length(indices_validos)
                    j = indices_validos(id);
                    val = this.Aeq(i,j);
                    
                    if primero
                        if val == 1
                            text = nombres{j};
                        elseif val == -1
                            text = strcat(' - ',nombres{j});
                        elseif val > 0
                            text = strcat(num2str(round(val,dec_redondeo)),'*',nombres{j});
                        else
                            text = strcat(' - ', num2str(abs(round(val,dec_redondeo))),'*',nombres{j});
                        end
                        primero = false;
                    else
                        if val == 1
                            text = strcat(text, ' + ',nombres{j});
                        elseif val == -1
                            text = strcat(text, ' - ',nombres{j});
                        elseif val > 0
                            text = strcat(text, ' + ', num2str(round(val,dec_redondeo)),'*',nombres{j});
                        else
                            text = strcat(text, ' - ', num2str(abs(round(val,dec_redondeo))),'*',nombres{j});
                        end
                        if length(text) > 135
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
            for i = 1:this.iCantVarDecision
                
                text = strcat(num2str(this.lb(i)), ' <= ', nombres{i}, ' <= ', num2str(this.ub(i)), '\n');
                fprintf(docID, text);
            end
            
            %variables binarias
            fprintf(docID, '\nVariables binarias:\n');
            primero = true;
            for i = 1:length(this.intcon)
                if primero
                    text = nombres{this.intcon(i)};
                    primero = false;
                else
                    text = strcat(text, ', ', this.NombreVariables{this.intcon(i)});
                    if length(text) > 170
                        text = strcat(text, '\n');
                        fprintf(docID, text);
                        primero = true;
                    end
                end
            end
            text = strcat(text,'\n');
            fprintf(docID, text);
            
            %todas las variables por índice
            fprintf(docID, '\nTodas las variables:\n');
            for i = 1:length(nombres)
                text = [num2str(i) ' ' nombres{i} '\n'];
                fprintf(docID, text);
            end
            fprintf(docID, '\nfin');
            fclose(docID);
        end
        
        function imprime_plan_optimo(this)
            for i = 1:this.iCantEscenarios
                %this.pPlanOptimo{i}.imprime(['Plan optimo escenario ' num2str(i)]);
                this.pPlanOptimo{i}.imprime_en_detalle(this.pAdmProy, this.pParOpt, ['Plan optimo escenario ' num2str(i)])
            end
        end
        
        function imprime_plan_operacion_sin_restricciones(this)
            for i = 1:this.iCantEscenarios
                this.pPlanOperSinRestriccion{i}.imprime(['Plan operacion sin restriccion ' num2str(i)]);
            end            
        end
        
        function plan = entrega_plan_optimo(this)
            plan = this.pPlanOptimo;
        end
        
        function grafica_resultados(this)
            close all
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            for etapa = 1:this.iCantEtapas
                for oper = 1:this.iCantPuntosOperacion
                    graficos = cAdministradorGraficos.getInstance();
                    id = graficos.crea_nueva_figura(['Etapa ' num2str(etapa) ', PO ' num2str(oper)]);
                    clear corredores
                    cant_corredores = 0;
                    p_corredores = [];
                    nro_lineas = [];
                    reactancia_lineas = [];
                    
                    for se = 1:length(this.pSEP.Subestaciones)
                        indice_se = this.pSEP.Subestaciones(se).entrega_varopt_operacion('Theta', etapa, oper);
                        angulo = this.ResOptimizacion(indice_se)/pi*180;
                        ubicacion = this.pSEP.Subestaciones(se).entrega_ubicacion();
                        vn = this.pSEP.Subestaciones(se).entrega_vn();
                        this.pSEP.Subestaciones(se).inserta_resultados_fp(1, vn, angulo)
                        graficos.grafica_elemento(this.pSEP.Subestaciones(se));
                        
                        %generadores
                        for gen = 1:length(this.pSEP.Subestaciones(se).Generadores)
                        	indice_gen = this.pSEP.Subestaciones(se).Generadores(gen).entrega_varopt_operacion('P', etapa, oper);
                            valor = this.ResOptimizacion(indice_gen)*sbase;
                            this.pSEP.Subestaciones(se).Generadores(gen).inserta_p_fp_mw(valor);
                            graficos.grafica_elemento(this.pSEP.Subestaciones(se).Generadores(gen));
                                
                            %prot.imprime_texto(texto);
                        end

                        %consumos
                        for cons = 1:length(this.pSEP.Subestaciones(se).Consumos)
                        	indice_escenario = this.pSEP.Subestaciones(se).Consumos(cons).entrega_indice_escenario();
                            valor = this.pAdmSc.entrega_consumo(indice_escenario, etapa, oper);
                            this.pSEP.Subestaciones(se).Consumos(cons).inserta_p_fp_mw(valor);
                            graficos.grafica_elemento(this.pSEP.Subestaciones(se).Consumos(cons));
                        end
                        
                        % se resta la inyección de generadores RES
                        for gen = 1:length(this.pSEP.Subestaciones(se).GeneradoresRES)
                        	indice_escenario = this.pSEP.Subestaciones(se).GeneradoresRES(gen).entrega_indice_escenario();
                            valor = this.pAdmSc.entrega_inyeccion(indice_escenario, etapa, oper);
                            this.pSEP.Subestaciones(se).GeneradoresRES(gen).inserta_p_fp_mw(valor);
                            graficos.grafica_elemento(this.pSEP.Subestaciones(se).GeneradoresRES(gen));
                        end

                        %lineas existentes
                        for linea = 1:length(this.pSEP.Subestaciones(se).Lineas)
                        	[se_1, se_2] = this.pSEP.Subestaciones(se).Lineas(linea).entrega_subestaciones();
                            ubic = se_1.entrega_ubicacion();
                            %if se_1 ~= this.pSEP.Subestaciones(se)
                            if ubic ~= ubicacion
                            	continue;
                            end
                            
                            indice_linea = this.pSEP.Subestaciones(se).Lineas(linea).entrega_varopt_operacion('P', etapa, oper);
                            p_linea = this.ResOptimizacion(indice_linea)*sbase;
                            
                            % identifica si línea está operativa o no. Una
                            % línea existente sólo puede ser removida de la
                            % red, pero no puede ser nuevamente agregada
                            removida = false;
                            for etapa_previa = 1:etapa
                                % Identifica proyectos que contienen esta línea. Se
                                % incluye variable que indica si proyecto se construye
                                % o no
                                for proy = 1:length(this.pAdmProy.ProyTransmision)
                                    [existe, accion] = this.pAdmProy.ProyTransmision(proy).existe_elemento(this.pSEP.Subestaciones(se).Lineas(linea));
                                    if existe
                                        indice_expansion = this.pAdmProy.ProyTransmision(proy).entrega_varopt_expansion('Decision', etapa_previa);
                                        if strcmp(accion, 'A')
                                        	error = MException('cOptMILP:grafica_resultados',...
                                                'Inconsistencia en los datos, ya que línea existente no puede ser agregada como proyecto de expansión');
                                            throw(error)
                                        else
                                            valor_exp = this.ResOptimizacion(indice_expansion);
                                            if valor_exp == 1
                                                if removida
                                                	error = MException('cOptMILP:grafica_resultados',...
                                                        'Inconsistencia en los datos, ya que línea existente ya fue removida en otro proyecto');
                                                    throw(error)                                    
                                                else
                                                    removida = true;
                                                end
                                            end
                                        end
                                    end
                                end
                            end

                            if removida 
                                if p_linea ~= 0
                                    error = MException('cOptMILP:grafica_resultados',...
                                        'Inconsistencia en los datos, ya que línea existente ya fue removida en otro proyecto');
                                    throw(error)
                                end 
                            else
                                S1 = complex(p_linea, 0);
                                S2 = complex(-p_linea, 0);
                                I1 = S1/(sqrt(3)*vn*p_linea);
                                I2 = S2/(sqrt(3)*vn*p_linea);
                                ThetaI1 = 0;
                                ThetaI2 = 0;
                                Perdidas = 0;
                                this.pSEP.Subestaciones(se).Lineas(linea).inserta_resultados_fp(1, I1, I2, ThetaI1, ThetaI2, S1, S2, Perdidas);
                                id_corr = [];
                                if cant_corredores ~= 0
                                    id_corr = find(ismember(corredores, [se_1 se_2], 'rows'));
                                end
                                if ~isempty(id_corr)
                                    p_corredores(id_corr) = p_corredores(id_corr) + p_linea;
                                    nro_lineas(id_corr) = nro_lineas(id_corr) + 1;
                                    % verifica reactancia
                                    x = this.pSEP.Subestaciones(se).Lineas(linea).entrega_reactancia();
                                    if reactancia_lineas(id_corr) ~= x
                                        error = MException('cOptMILP:grafica_resultado','reactancia de las líneas paralelas no coincide');
                                        throw(error)
                                    end
                                else
                                    cant_corredores = cant_corredores + 1;
                                    corredores(cant_corredores,1) = se_1;
                                    corredores(cant_corredores,2) = se_2;
                                    p_corredores(cant_corredores,1) = p_linea;
                                    nro_lineas(cant_corredores,1) = 1;
                                    x = this.pSEP.Subestaciones(se).Lineas(linea).entrega_reactancia();
                                    reactancia_lineas(cant_corredores,1) = x;
                                end
                                
                                graficos.grafica_elemento(this.pSEP.Subestaciones(se).Lineas(linea), false);
                            end
                        end
                
                        %lineas proyectadas
                        for el_red = 1:length(this.pAdmProy.ElementosSerie)
                        	[se_1, se_2] = this.pAdmProy.ElementosSerie(el_red).entrega_subestaciones();
                            ubic = se_1.entrega_ubicacion();
%                            if se_1 ~= this.pSEP.Subestaciones(se)
                            if ubic ~= ubicacion || isa(this.pAdmProy.ElementosSerie(el_red), 'cTransformador2D')
                            	continue;
                            end
                    
                            indice = this.pAdmProy.ElementosSerie(el_red).entrega_varopt_operacion('P', etapa, oper);
                            p_linea = this.ResOptimizacion(indice)*sbase;

                            % identifica si línea está operativa o no. Una
                            existente = false;
                            agregada = false;
                            removida = false;
                            etapa_agregada = 0;
                            etapa_removida = 0;
                            for etapa_previa = 1:etapa
                            	% Identifica proyectos que contienen esta línea. Se
                                % incluye variable que indica si proyecto se construye
                                % o no
                                for proy = 1:length(this.pAdmProy.ProyTransmision)
                                	[existe, accion] = this.pAdmProy.ProyTransmision(proy).existe_elemento(this.pAdmProy.ElementosSerie(el_red));
                                    if existe
                                    	indice_expansion = this.pAdmProy.ProyTransmision(proy).entrega_varopt_expansion('Decision', etapa_previa);
                                        val_exp = this.ResOptimizacion(indice_expansion);
                                        if val_exp == 1
                                        	% proyecto se ejecuta en
                                            % etapa "etapa_previa"
                                            if strcmp(accion, 'A')
                                                if etapa_agregada ~= 0
                                                	error = MException('cOptMILP:grafica_resultados',...
                                                    	'Inconsistencia en los resultados, ya que línea ya fue agregada en otro proyecto');
                                                    throw(error)
                                                else
                                                	etapa_agregada = etapa_previa;
                                                    agregada = true;
                                                end
                                            else % acción es de remover
                                                if etapa_removida ~= 0
                                                	error = MException('cOptMILP:grafica_resultados',...
                                                    	'Inconsistencia en los resultados, ya que línea ya fue removida en otro proyecto');
                                                    throw(error)
                                                else
                                                	etapa_removida = etapa_previa;
                                                    removida = true;
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                                
                            %verifica consistencia en los datos. Línea
                            %proyectada tiene que ser agregada antes de
                            %ser removida
                            if agregada && removida
                                if etapa_removida < etapa_agregada
                                    error = MException('cOptMILP:grafica_resultados',...
                                        'Inconsistencia en los resultados, ya que línea proyectada fue removida antes de ser agregada');
                                    throw(error)
                                else
                                	existente = false; % redundante, pero para mayor comprensión del código
                                end
                            elseif removida && ~agregada
                            	error = MException('cOptMILP:grafica_resultados',...
                                	'Inconsistencia en los resultados, ya que línea proyectada fue removida pero no agregada previamente');
                                throw(error)
                            elseif agregada
                            	existente = true;
                            end
                                
                            if ~existente
                                if p_linea ~= 0
                                	error = MException('cOptMILP:grafica_resultados',...
                                    	'Inconsistencia en los datos, ya que línea no existente tiene potencia distinta de cero');
                                    throw(error)
                                end
                            else
                            	S1 = complex(p_linea, 0);
                                S2 = complex(-p_linea, 0);
                                I1 = S1/(sqrt(3)*vn*p_linea);
                                I2 = S2/(sqrt(3)*vn*p_linea);
                                ThetaI1 = 0;
                                ThetaI2 = 0;
                                Perdidas = 0;
                                id_corr = [];
                                if cant_corredores ~= 0
                                    id_corr = find(ismember(corredores, [se_1 se_2], 'rows'));
                                end
                                if ~isempty(id_corr)
                                	p_corredores(id_corr) = p_corredores(id_corr) + p_linea;
                                    nro_lineas(id_corr) = nro_lineas(id_corr) + 1;
                                    % verifica reactancia
                                    x = this.pAdmProy.ElementosSerie(el_red).entrega_reactancia();
                                    if reactancia_lineas(id_corr) ~= x
                                        error = MException('cOptMILP:grafica_resultado','reactancia de las líneas paralelas no coincide');
                                        throw(error)
                                    end
                                else
                                	cant_corredores = cant_corredores + 1;
                                    corredores(cant_corredores,1) = se_1;
                                    corredores(cant_corredores,2) = se_2;
                                    p_corredores(cant_corredores,1) = p_linea;
                                    nro_lineas(cant_corredores,1) = 1;
                                    x = this.pAdmProy.ElementosSerie(el_red).entrega_reactancia();
                                    reactancia_lineas(cant_corredores,1) = x;
                                end
                                    
                                this.pAdmProy.ElementosSerie(el_red).inserta_resultados_fp(1, I1, I2, ThetaI1, ThetaI2, S1, S2, Perdidas);
                                graficos.fija_color_linea('azul');
                                graficos.grafica_elemento(this.pAdmProy.ElementosSerie(el_red), false);
                                graficos.fija_color_linea('negro');
                            end
                        end %fin elementos de red proyectos
                    end %fin subestaciones
                    
                    % se agregan los resultados de los corredores
                    for corr = 1:length(corredores)
                        se_1 = corredores(corr,1);
                        se_2 = corredores(corr,2);
                        p = p_corredores(corr);
                        cant_lineas = nro_lineas(corr);
                        x_linea = reactancia_lineas(id_corr);
                        graficos.agrega_resultado_corredor(se_1, se_2, p, cant_lineas, x_linea);
                    end
                end % fin puntos de operación
            end % fin cantidad de etapas
        end
        
        function calcula_despacho_optimo_sin_restricciones(this)
            this.iCantEtapas = this.pParOpt.CantidadEtapas;
            this.iCantEscenarios = this.pParOpt.CantidadEscenarios;
            this.iCantPuntosOperacion = this.pParOpt.CantidadPuntosOperacion;
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            
            % elementos existentes
            CantVarDec = 0;
            % elementos existentes (válidos para todos los escenarios)            
            VarOper = this.pSEP.entrega_generadores_despachables();
            VarOper = [VarOper; this.pAdmProy.entrega_generadores_despachables_proyectados_todos()];
            VarOper = [VarOper; this.pSEP.entrega_generadores_res()];            
            VarOper = [VarOper; this.pSEP.entrega_consumos()];
            VarOper = [VarOper; this.pAdmProy.entrega_generadores_ernc_proyectados_todos()];
            VarOper = [VarOper; this.pAdmProy.entrega_consumos_proyectados_todos()];                
            
            for varopt = 1:length(VarOper)
                VarOper(varopt).inicializa_varopt_operacion_milp_dc(this.iCantEscenarios, this.iCantEtapas);
            end
  
            for escenario = 1:this.iCantEscenarios
                for etapa = 1:this.iCantEtapas
                    for i = 1:length(VarOper)                        
                        if isa(VarOper(i), 'cGenerador')                        
                            if VarOper(i).Existente && VarOper(i).entrega_retiro_proyectado() && VarOper(i).EtapaRetiro(escenario) <= etapa
                                continue                                
                            elseif ~VarOper(i).Existente && (VarOper(i).entrega_etapa_entrada(escenario) == 0 || VarOper(i).entrega_etapa_entrada(escenario) > etapa)                                
                                continue
                            end

                            CantVarDec = CantVarDec + 1;
                            indice_desde = CantVarDec;
                            indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;                
                            CantVarDec = indice_hasta;

                            if this.VarOperacion(i).es_despachable()
                                sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
                                VarOper(i).inserta_varopt_operacion('P', escenario, etapa, indice_desde);
                                if VarOper(i).entrega_evolucion_capacidad_a_futuro()
                                    id_adm_sc = VarOper(i).entrega_indice_adm_escenario_capacidad(escenario);
                                    capacidad = this.pAdmSc.entrega_capacidad_generador(id_adm_sc, etapa);
                                else
                                    capacidad = VarOper(i).entrega_pmax();
                                end
                                lower(indice_desde:indice_hasta) = 0;
                                upper(indice_desde:indice_hasta) = round(capacidad/sbase,dec_redondeo);

                                if this.iNivelDebug > 1
                                    for oper = 1:this.iCantPuntosOperacion
                                        id_se = VarOper(i).entrega_se().entrega_id();
                                        id_generador = VarOper(i).entrega_id();
                                        indice = indice_desde + oper - 1;
                                        NombreVar{indice} = strcat('G', num2str(id_generador), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper));
                                    end
                                end
                            else
                                %generador ernc
                                sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
                                VarOper(i).inserta_varopt_operacion('P', escenario, etapa, indice_desde);
                                if VarOper(i).entrega_evolucion_capacidad_a_futuro()
                                    id_adm_sc = VarOper(i).entrega_indice_adm_escenario_capacidad(escenario);
                                    capacidad = this.pAdmSc.entrega_capacidad_generador(id_adm_sc, etapa);
                                else
                                    capacidad = VarOper(i).entrega_pmax();
                                end
                                id_adm_sc = VarOper(i).entrega_indice_adm_escenario_perfil_ernc();
                                pmax = this.pAdmSc.entrega_perfil_ernc(id_adm_sc, po_desde, po_hasta);
                                this.lb(indice_desde:indice_hasta) = 0;
                                this.ub(indice_desde:indice_hasta) = round(capacidad*pmax'/sbase,dec_redondeo);
                                if this.iNivelDebug > 1
                                    for oper = 1:this.iCantPuntosOperacion
                                        id_se = VarOper(i).entrega_se().entrega_id();
                                        id_generador = VarOper(i).entrega_id();
                                        indice = indice_desde + oper - 1;
                                        NombreVar{indice} = strcat('GRES', num2str(id_generador), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper));
                                    end
                                end
                            end
                        elseif isa(VarOper(i), 'cConsumo')
                            if ~VarOper(i).Existente 
                                if VarOper(i).EtapaEntrada(escenario) > etapa || VarOper(i).EtapaSalida <= etapa
                                    continue
                                end
                            end

                            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
                            VarOper(i).inserta_varopt_operacion('P', escenario, etapa, indice_desde);

                            indice_perfil = VarOper(varopt).entrega_indice_adm_escenario_perfil_p();
                            perfil = this.pAdmSc.entrega_perfil_consumo(indice_perfil);
                            indice_capacidad = VarOper(varopt).entrega_indice_adm_escenario_capacidad(escenario);
                            capacidad = this.pAdmSc.entrega_capacidad_consumo(indice_capacidad, etapa);
							
                            pmax = capacidad*perfil/sbase;
                            this.lb(indice_desde:indice_hasta) = 0;
                            this.ub(indice_desde:indice_hasta) = round(pmax',dec_redondeo);
                            if this.iNivelDebug > 1
                                id_se = VarOper(i).entrega_se().entrega_id();
                                id_consumo = VarOper(i).entrega_id();
                                for oper = 1:this.iCantPuntosOperacion
                                    indice = indice_desde + oper - 1;
                                    NombreVar{indice} = strcat('ENS', num2str(id_consumo), '_B', num2str(id_se), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(oper));
                                end
                            end
                        else
                            texto = ['Tipo elemento red "' class(VarOper(i)) '" no implementado. Nombre elemento: ' VarOper(i).entrega_nombre()];
                            error = MException('cOptMILP:inicializa_variables_decision_operacion',texto);
                            throw(error)
                        end
                    end
                end
            end
            
            %escribe función objetivo
            q = (1 + this.pParOpt.TasaDescuento);
            detapa = this.pParOpt.DeltaEtapa;
            rep_puntos_operacion = this.pAdmSc.RepresentatividadPuntosOperacion;
            
            for escenario = 1:this.iCantEscenarios
                for etapa = 1:this.iCantEtapas
                    for varopt = 1:length(VarOper)
                        % verifica si varopt está operativa para escenario y etapa
                        indice_desde = VarOper(varopt).entrega_varopt_operacion('P', escenario, etapa);                               
                        if indice_desde == 0 
                           % quiere decir que generador no está operativo en esta etapa y escenario
                           continue
                        end
                        indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;
                        
                        if isa(VarOper(varopt), 'cGenerador')
                            if VarOper(varopt).es_despachable()
                            
                                % determina costo generador
                                if VarOper(varopt).entrega_evolucion_costos_a_futuro()
                                    id_adm_sc = VarOper(varopt).entrega_indice_adm_escenario_costos_futuros(escenario);
                                    costo_pu = this.pAdmSc.entrega_costos_generacion_etapa_pu(id_adm_sc, etapa);
                                else
                                    costo_pu = VarOper(varopt).entrega_costo_mwh_pu();
                                end
                                costo = round(costo_pu * rep_puntos_operacion/q^(detapa*etapa)/1000000,dec_redondeo); % en millones para equiparar con costos de expansión
                                Fobjetivo(indice_desde:indice_hasta) = costo;
                            else
                                % generador es res 
                                sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();                
                                costo_pu = sbase*this.pParOpt.entrega_penalizacion_recorte_res(); % en $/pu
                                costo = round(costo_pu * rep_puntos_operacion/q^(detapa*etapa)/1000000,dec_redondeo); % en millones para equiparar con costos de expansión
                                Fobjetivo(indice_desde:indice_hasta) = costo;
                            end
                        else
                            costo_desconexion = VarOper(varopt).entrega_costo_desconexion_carga_pu();
                            costo = round(costo_desconexion * rep_puntos_operacion/q^(detapa*etapa)/1000000,dec_redondeo); % en millones para equiparar con costos de expansión                        
                            Fobjetivo(indice_desde:indice_hasta) = costo;
                        end
                    end
                end
            end
                        
            % escribe balance energía
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            IndiceEq = 0;
            for escenario = 1:this.iCantEscenarios
                for etapa = 1:this.iCantEtapas
                    indice_eq_desde = IndiceEq + 1;
                    indice_eq_hasta = indice_eq_desde + this.iCantPuntosOperacion - 1;
                    IndiceEq = indice_eq_hasta;
                    
                    consumo_residual = zeros(1, this.iCantPuntosOperacion);
                    
                    for varopt = 1:length(VarOper)
                        indice_desde = VarOper(varopt).entrega_varopt_operacion('P', escenario, etapa);
                        if indice_desde == 0
                            continue
                        end
                        indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;

                        if isa(VarOper(varopt),'cGenerador')
                            if VarOper(varopt).es_despachable()
                                A_eq(indice_eq_desde:indice_eq_hasta,indice_desde:indice_hasta) = diag(ones(this.iCantPuntosOperacion,1));
                            else
                                indice_perfil = VarOper(varopt).entrega_indice_adm_escenario_perfil_ernc();
                                perfil_ernc = this.pAdmSc.entrega_perfil_ernc(indice_perfil);
                                if VarOper(varopt).entrega_evolucion_capacidad_a_futuro()
                                    indice_capacidad = VarOper(varopt).entrega_indice_adm_escenario_capacidad(escenario);
                                    capacidad = this.pAdmSc.entrega_capacidad_generador(indice_capacidad, etapa);
                                else
                                    capacidad = VarOper(varopt).entrega_pmax();
                                end
                                consumo_residual = consumo_residual - capacidad*perfil_ernc/sbase;
                                
                                A_eq(indice_eq_desde:indice_eq_hasta,indice_desde:indice_hasta) = -1*diag(ones(this.iCantPuntosOperacion,1));
                            end
                        elseif isa(VarOper(varopt),'cConsumo')
                            indice_perfil = VarOper(varopt).entrega_indice_adm_escenario_perfil_p();
                            perfil = this.pAdmSc.entrega_perfil_consumo(indice_perfil);
                            indice_capacidad = VarOper(varopt).entrega_indice_adm_escenario_capacidad(escenario);
                            capacidad = this.pAdmSc.entrega_capacidad_consumo(indice_capacidad, etapa);

                            consumo_residual = consumo_residual + capacidad*perfil/sbase;
                            
                            A_eq(indice_eq_desde:indice_eq_hasta,indice_desde:indice_hasta) = diag(ones(this.iCantPuntosOperacion,1));
                        end
                    end
                    
                    b_eq(indice_eq_desde:indice_eq_hasta,1) = round(consumo_residual',dec_redondeo);

                    if this.iNivelDebug > 1
                        for punto_operacion = 1:this.iCantPuntosOperacion
                            indice_eq = indice_eq_desde + punto_operacion - 1;
                            NombresEcuaciones{indice_eq} = strcat('req_be_', num2str(indice_eq), '_S', num2str(escenario), '_E', num2str(etapa), '_O', num2str(punto_operacion));
                        end
                    end
                end
            end
            
            %optimiza
            rtype = [repmat('E',[1 size(A_eq,1)])];
            [Res_Opt,F_val,Exit_Flag,Output] = xprslp(Fobjetivo,A_eq, b_eq, rtype, lower,upper);%, options);
            % imprime resultados
            prot = cProtocolo.getInstance;
            
            prot.imprime_texto('Resultados globales despacho optimo sin restricciones');
            costos_generacion = cell.empty;
            costos_generacion_valor_presente = cell.empty;
            ens = cell.empty;
            costos_ens = cell.empty;
            costos_ens_valor_presente = cell.empty;
            recorte_res = cell.empty;
            costos_recorte_res = cell.empty;
            costos_recorte_res_valor_presente = cell.empty;
            costos_operacion = cell.empty;
            costos_operacion_valor_presente = cell.empty;
            texto = sprintf('%25s', '');
            
            for escenario = 1:this.iCantEscenarios
                texto = [texto sprintf('%15s', ['Escenario ' num2str(escenario)])];
            end
            texto = [texto sprintf('%15s', 'Total Esperado')];
            prot.imprime_texto(texto);
                        
            for escenario = 1:this.iCantEscenarios
                costos_generacion{escenario} = zeros(this.iCantEtapas,1);
                costos_generacion_valor_presente{escenario} = zeros(this.iCantEtapas,1);
                ens{escenario} = zeros(this.iCantEtapas,1);
                costos_ens{escenario} = zeros(this.iCantEtapas,1);
                costos_ens_valor_presente{escenario} = zeros(this.iCantEtapas,1);
                recorte_res{escenario} = zeros(this.iCantEtapas,1);
                costos_recorte_res{escenario} = zeros(this.iCantEtapas,1);
                costos_recorte_res_valor_presente{escenario} = zeros(this.iCantEtapas,1);
                costos_operacion{escenario} = zeros(this.iCantEtapas,1);
                costos_operacion_valor_presente{escenario} = zeros(this.iCantEtapas,1);
                
                for etapa = 1:this.iCantEtapas
                    for varopt = 1:length(VarOper)
                        indice_oper_desde = VarOper(varopt).entrega_varopt_operacion('P', escenario, etapa);
                        indice_oper_hasta = indice_oper_desde + this.iCantPuntosOperacion - 1;
                        resultados = Res_Opt(indice_oper_desde:indice_oper_hasta);
                        if isa(VarOper(varopt),'cGenerador')
                            if VarOper(varopt).es_despachable()
                                if VarOper(varopt).entrega_evolucion_costos_a_futuro()
                                    id_adm_sc = VarOper(varopt).entrega_indice_adm_escenario_costos_futuros(escenario);
                                    costo_pu = this.pAdmSc.entrega_costos_generacion_etapa_pu(id_adm_sc, etapa);
                                else
                                    costo_pu = VarOper(varopt).entrega_costo_mwh_pu();
                                end
                                valor = sum(costo_pu*resultados.*rep_puntos_operacion)/1000000; % en millones
                                costos_generacion{escenario}(etapa) = costos_generacion{escenario}(etapa) + valor;
                                costos_generacion_valor_presente{escenario}(etapa) = costos_generacion_valor_presente{escenario}(etapa) + valor/q^(detapa*etapa);
                            else
                                penalizacion_pu = sbase*this.pParOpt.entrega_penalizacion_recorte_res();
                                cant_recorte_res = sbase*sum(resultados.*rep_puntos_operacion);
                                valor_recorte_res = penalizacion_pu*sum(resultados.*rep_puntos_operacion)/1000000; % en millones
                                
                                recorte_res{escenario}(etapa) = recorte_res{escenario}(etapa) + cant_recorte_res;
                                costos_recorte_res{escenario}(etapa) = costos_recorte_res{escenario}(etapa) + valor_recorte_res;
                                costos_recorte_res_valor_presente{escenario}(etapa) = costos_recorte_res_valor_presente{escenario}(etapa) + valor_recorte_res/q^(detapa*etapa);
                            end
                        elseif isa(VarOper(varopt),'cConsumo')
                            costo_desconexion_pu = VarOper(varopt).entrega_costo_desconexion_carga_pu();
                            cant_ens = sbase*sum(resultados.*rep_puntos_operacion);
                            valor_ens = costo_desconexion_pu*sum(resultados.*rep_puntos_operacion)/1000000; % en millones

                            ens{escenario}(etapa) = ens{escenario}(etapa) + cant_ens;
                            costos_ens{escenario}(etapa) = costos_ens{escenario}(etapa) + valor_ens;
                            costos_ens_valor_presente{escenario}(etapa) = costos_ens_valor_presente{escenario}(etapa) + valor_ens/q^(detapa*etapa);
                        end
                    end
                end
                costos_operacion{escenario} = costos_generacion{escenario} + costos_recorte_res{escenario} + costos_ens{escenario};
                costos_operacion_valor_presente{escenario} = costos_generacion_valor_presente{escenario} + costos_recorte_res_valor_presente{escenario} + costos_ens_valor_presente{escenario};
            end

            texto_costo_generacion = sprintf('%25s', 'Costo generacion');
            texto_costo_recorte_res = sprintf('%25s', 'Costo recorte res');
            texto_costo_ens = sprintf('%25s', 'Costo ENS');
            texto_costo_operacion = sprintf('%25s', 'Costo operacion');
            texto_ens = sprintf('%25s', 'ENS');
            texto_recorte_res = sprintf('%25s', 'Recorte RES');

            costos_gen_esperado = 0;
            costos_ens_esperado = 0;
            costos_recorte_res_esperado = 0;
            costos_operacion_esperado = 0;
            ens_esperado = 0;
            recorte_res_esperado = 0;
            
            for escenario = 1:this.iCantEscenarios
                peso_escenario = this.pAdmSc.entrega_peso_escenario(escenario);
                costo_gen_total = sum(costos_generacion_valor_presente{escenario});
                ens_total = sum(ens{escenario});
                costos_ens_total = sum(costos_ens_valor_presente{escenario});
                recorte_res_total = sum(recorte_res{escenario});
                costos_recorte_res_total = sum(costos_recorte_res_valor_presente{escenario});
                costos_operacion_total = sum(costos_operacion_valor_presente{escenario});
                texto_costo_generacion = [texto_costo_generacion sprintf('%15s', num2str(costo_gen_total))];
                texto_costo_recorte_res = [texto_costo_recorte_res  sprintf('%15s', num2str(costos_recorte_res_total))];
                texto_costo_ens = [texto_costo_ens  sprintf('%15s', num2str(costos_ens_total))];
                texto_costo_operacion = [texto_costo_operacion  sprintf('%15s', num2str(costos_operacion_total))];
                texto_ens = [texto_ens sprintf('%15s', num2str(ens_total))];
                texto_recorte_res = [texto_recorte_res sprintf('%15s', num2str(recorte_res_total))];

                costos_gen_esperado = costos_gen_esperado + peso_escenario*costo_gen_total;
                costos_ens_esperado = costos_ens_esperado + peso_escenario*costos_ens_total;
                costos_recorte_res_esperado = costos_recorte_res_esperado + peso_escenario*costos_recorte_res_total ;
                costos_operacion_esperado = costos_operacion_esperado + peso_escenario*costos_operacion_total;
                ens_esperado = ens_esperado + peso_escenario*ens_total;
                recorte_res_esperado = recorte_res_esperado + peso_escenario*recorte_res_total;
            end
            texto_costo_generacion = [texto_costo_generacion sprintf('%15s', num2str(costos_gen_esperado))];
            texto_costo_recorte_res = [texto_costo_recorte_res  sprintf('%15s', num2str(costos_recorte_res_esperado))];
            texto_costo_ens = [texto_costo_ens  sprintf('%15s', num2str(costos_ens_esperado))];
            texto_costo_operacion = [texto_costo_operacion  sprintf('%15s', num2str(costos_operacion_esperado))];
            texto_ens = [texto_ens sprintf('%15s', num2str(ens_esperado))];
            texto_recorte_res = [texto_recorte_res sprintf('%15s', num2str(recorte_res_esperado))];
            
            prot.imprime_texto(texto_costo_generacion);
            prot.imprime_texto(texto_costo_recorte_res);
            prot.imprime_texto(texto_costo_ens);
            prot.imprime_texto(texto_costo_operacion);
            prot.imprime_texto(texto_ens);
            prot.imprime_texto(texto_recorte_res);
                        
            prot.imprime_texto('Variables de operacion despacho sin restricciones');
            for escenario = 1:this.iCantEscenarios
                for etapa = 1:this.iCantEtapas
                    for oper = 1:this.iCantPuntosOperacion
                        for i = 1:length(this.VarOperacion)
                            indice_oper = VarOper{escenario}(i).entrega_varopt_operacion('P', escenario, etapa) + oper - 1;
                            texto = sprintf('%10s %5s %35s %3s %10s %5s %10s ', ...
                                num2str(lower(indice_oper)), '<=', NombreVar{indice_oper}, '=', ...
                                num2str(Res_Opt(indice_oper)), '<=', num2str(upperr(indice_oper)));
                                prot.imprime_texto(texto);
                        end
                    end
                end
            end
            
        end
        
        function calcula_parametros_disyuntivos(this)
            subestaciones_base = this.pSEP.entrega_subestaciones();
            subestaciones_base = [subestaciones_base; this.pAdmProy.entrega_subestaciones_expansion()];

            id_par_dis_se_aisladas = [];
            el_red = this.pSEP.entrega_lineas();
            el_red = [el_red; this.pSEP.entrega_transformadores2d()];
            el_red = [el_red; this.pAdmProy.entrega_elementos_serie_expansion()];

            % determina parámetros disyuntivos a calcular
            % corredores_a_calcular: [id_se1, id_se2, 0 si corredor existe en SEP actual; 1 si una subestacion no existe (conexion trafo); 2 si ambas subestaciones no existen (linea VU)]
            corredores_a_calcular = zeros(0,3);
            cant_corredores = 0;
            contador = 10;
            disp('Calcula parametros disyuntivos base')
            for i = 1:length(el_red)
                porcentaje = i/length(el_red)*100;
                if porcentaje > contador
                    while contador + 10 < porcentaje
                        contador = contador + 10;
                    end

                    fprintf('%s %s',' ', [num2str(contador) '%']);
                    contador = contador + 10;
                    pause(0.1);
                end
                
                [se_1, se_2] = el_red(i).entrega_subestaciones();
                id_se_1 = se_1.entrega_id();
                id_se_2 = se_2.entrega_id();

                if se_1 ~= subestaciones_base(id_se_1) || se_2 ~= subestaciones_base(id_se_2) 
                    error = MException('calcula_parametros_disyuntivos:caso_base','Subestaciones no coinciden');
                    throw(error)
                end
                    
                if ismember([id_se_1 id_se_2], corredores_a_calcular(:,1:2),'rows') || ...
                   ismember([id_se_2 id_se_1], corredores_a_calcular(:,1:2),'rows')
                    continue;
                end
                
                cant_corredores = cant_corredores + 1;
                corredores_a_calcular(cant_corredores, 1:2) = [id_se_1 id_se_2];
                if ~this.pSEP.existe_subestacion(se_1)
                    corredores_a_calcular(cant_corredores,3) = corredores_a_calcular(cant_corredores,3) + 1;
                end

                if ~this.pSEP.existe_subestacion(se_2)
                    corredores_a_calcular(cant_corredores,3) = corredores_a_calcular(cant_corredores,3) + 1;
                end
                
            end
            fprintf('%s %s\n',' ', [num2str(100) '%']);            
            
            this.ParDisyuntivosBase = zeros(cant_corredores,3);
            this.ParDisyuntivosBaseOrig = zeros(cant_corredores,3);  % para comparar

            this.ParDisyuntivosConv = zeros(0,3);
            this.ParDisyuntivosCSCC = zeros(0,3);
            this.ParDisyuntivosVU = zeros(0,3);
            this.ParDisyuntivosConvOrig = zeros(0,3);
            this.ParDisyuntivosCSCCOrig = zeros(0,3);
            this.ParDisyuntivosVUOrig = zeros(0,3);
            
            cantidad_par_disy_conv = 0;
            cantidad_par_disy_cscc = 0;
            cantidad_par_disy_vu = 0;
            
            plan_vacio = cPlanExpansion(-1);
            plan_vacio.inicializa_etapa(1);

            % sólo proyectos principales. Ningún proyecto de conectividad
            % ni proyectos convencionales de líneas paralelas
            [id_proy_elegibles, ~] = this.pAdmProy.determina_espacio_busqueda_calculo_pardis(plan_vacio);

            contador = 10;
            disp('Incorpora proyectos subestaciones existentes')
            for corr = 1:cant_corredores
                porcentaje = corr/cant_corredores*100;
                if porcentaje > contador
                    while contador + 10 < porcentaje
                        contador = contador + 10;
                    end

                    fprintf('%s %s',' ', [num2str(contador) '%']);
                    contador = contador + 10;
                    pause(0.1);
                end

                % caso 1: ambas subestaciones existen
                if corredores_a_calcular(corr,3) == 0
                    % primero determina proyectos a construir en este
                    % corredor. Se incluyen proyectos de VU que conectan
                    % ambos buses
                    id_se_1_base = corredores_a_calcular(corr,1);
                    id_se_2_base = corredores_a_calcular(corr,2);
                    
                    nombre_se_1_base = subestaciones_base(id_se_1_base).entrega_nombre();
                    nombre_se_2_base = subestaciones_base(id_se_2_base).entrega_nombre();
                    
                    id_proyectos_corredor = this.entrega_proyectos_corredor(nombre_se_1_base, nombre_se_2_base, id_proy_elegibles);

                    % z_corr indica el caso que se está estudiando:
                    % 0: significa que es el caso base; > 0 significa que
                    % hay un proyecto construido
                    for z_corr = 0:length(id_proyectos_corredor)
                        plan_actual = cPlanExpansion(-2);
                        plan_actual.inicializa_etapa(1);
                        sep_actual = this.pSEP.crea_copia();
                        
                        corredores_visitados = zeros(0,2);
                        cant_corredores_visitados = 0;
                        if z_corr > 0
                            % crea plan expansión auxiliar, copia de sep y
                            % agrega proyecto al plan y al sep 

                            proyecto_base = this.pAdmProy.entrega_proyecto(id_proyectos_corredor(z_corr));
                            conectividad_agregar = [];
                            if proyecto_base.tiene_requisitos_conectividad()
                                cantidad_req_conectividad = proyecto_base.entrega_cantidad_grupos_conectividad();
                                conectividad_agregar = zeros(1,cantidad_req_conectividad);
                                for ii = 1:cantidad_req_conectividad
                                    indice_proy_conect = proyecto_base.entrega_indices_grupo_proyectos_conectividad(ii);
                                    if length(indice_proy_conect) > 1
                                        % TODO existe más de un tipo de
                                        % transformador que se puede
                                        % conectar. Este caso no se ha
                                        % visto aún
                                        error = MException('calcula_parametros_disyuntivos:caso_base','existe más de un proyecto de conectividad. Caso no se ha visto aún');
                                        throw(error)
                                    end
                                    conectividad_agregar(ii) = indice_proy_conect;
                                end
                            end

                            % agrega proyectos al plan y al SEP                            
                            for k = 1:length(conectividad_agregar)
                                proyecto_conectividad = this.pAdmProy.entrega_proyecto(conectividad_agregar(k));
                                sep_actual.agrega_proyecto(proyecto_conectividad);
                                plan_actual.agrega_proyecto(1, conectividad_agregar(k));
                            end
                            plan_actual.agrega_proyecto(1, proyecto_base.entrega_indice());
                            sep_actual.agrega_proyecto(proyecto_base);
                        end

                        % calcula parámetro disyuntivo "base", i.e. sin
                        % proyectos en corredores adyacentes
                    
                        subestaciones = sep_actual.entrega_subestaciones();
                        dist = [(1:1:length(subestaciones))' inf*ones(length(subestaciones),1)];
                        
                        % identifica posicion se_1 y se_2 en subestaciones
                        % del SEP
                        id_se_1 = this.entrega_posicion_subestacion(nombre_se_1_base, subestaciones);
                        id_se_2 = this.entrega_posicion_subestacion(nombre_se_2_base, subestaciones);

                        % verifica que subestaciones no estén aisladas
                        se_aislada = false;
                        conexiones_base = subestaciones(id_se_1).entrega_lineas();
                        conexiones_base = [conexiones_base; subestaciones(id_se_1).entrega_transformadores2d()];
                        if isempty(conexiones_base)
                            % se1 aislada
                            se_aislada = true;
                        end

                        conexiones_base = subestaciones(id_se_2).entrega_lineas();
                        conexiones_base = [conexiones_base; subestaciones(id_se_2).entrega_transformadores2d()];
                        if isempty(conexiones_base)
                            % se1 aislada
                            se_aislada = true;
                        end
                        
                        if se_aislada
                            this.ParDisyuntivosBaseOrig(corr, 1) = corredores_a_calcular(corr,1);
                            this.ParDisyuntivosBaseOrig(corr, 2) = corredores_a_calcular(corr,2);
                            this.ParDisyuntivosBaseOrig(corr, 3) = 0;
                            this.ParDisyuntivosBase(corr, 1) = corredores_a_calcular(corr,1);
                            this.ParDisyuntivosBase(corr, 2) = corredores_a_calcular(corr,2);
                            this.ParDisyuntivosBase(corr, 3) = 0;
                            continue
                        end
                        
                        dist(id_se_1,2) = 0;
                        while true
                            if isempty(dist)
                                error = MException('cOptMILP:calcula_parametros_disyuntivos','No hay nodos por visitar, pero aún no se encontró nodo objetivo');
                                throw(error)
                            end
                    
                            % selecciona nodo no visitado con menor distancia
                            [val_nodo_actual, id] = min(dist(:,2));
                            nodo_actual = dist(id, 1);
                            if nodo_actual == id_se_2
                                distancia_nodo_fin = val_nodo_actual;
                                break;
                            end
                            dist(id, :) = [];
                            
                            conexiones = subestaciones(nodo_actual).entrega_lineas();
                            conexiones = [conexiones; subestaciones(nodo_actual).entrega_transformadores2d()];
                            for ii = 1:length(conexiones)
                                ubic_se_adyacente = find(dist(:,1) == conexiones(ii).entrega_se1().entrega_id(), 1);
                                if isempty(ubic_se_adyacente)
                                    ubic_se_adyacente = find(dist(:,1) == conexiones(ii).entrega_se2().entrega_id());
                                end
                                if isempty(ubic_se_adyacente)
                                    continue;
                                end
                                xpu_conexion = conexiones(ii).entrega_reactancia_pu();
                                fmax_pu_conexion = conexiones(ii).entrega_sr_pu();
                                dmax_conexion = fmax_pu_conexion*xpu_conexion;
                                valor_nodo = val_nodo_actual + dmax_conexion;
                                if valor_nodo < dist(ubic_se_adyacente,2)
                                    dist(ubic_se_adyacente,2) = valor_nodo;
                                end
                                
                                cant_corredores_visitados = cant_corredores_visitados + 1;
                                corredores_visitados(cant_corredores_visitados,1) = nodo_actual;
                                corredores_visitados(cant_corredores_visitados,2) = dist(ubic_se_adyacente,1);
                            end
                        end
                        
                        if z_corr == 0
                            this.ParDisyuntivosBaseOrig(corr, 1) = corredores_a_calcular(corr,1);
                            this.ParDisyuntivosBaseOrig(corr, 2) = corredores_a_calcular(corr,2);
                            this.ParDisyuntivosBaseOrig(corr, 3) = distancia_nodo_fin;
                            this.ParDisyuntivosBase(corr, 1) = corredores_a_calcular(corr,1);
                            this.ParDisyuntivosBase(corr, 2) = corredores_a_calcular(corr,2);
                            this.ParDisyuntivosBase(corr, 3) = distancia_nodo_fin;
                        else
                            proyecto_base = this.pAdmProy.entrega_proyecto(id_proyectos_corredor(z_corr));
                            if strcmp(proyecto_base.entrega_tipo_proyecto(), 'AV')
                                cantidad_par_disy_vu = cantidad_par_disy_vu + 1;
                                this.ParDisyuntivosVU(cantidad_par_disy_vu, 1) = corredores_a_calcular(corr,1);
                                this.ParDisyuntivosVU(cantidad_par_disy_vu, 2) = corredores_a_calcular(corr,2);
                                this.ParDisyuntivosVU(cantidad_par_disy_vu, 3) = distancia_nodo_fin;
                                this.ParDisyuntivosVUOrig(cantidad_par_disy_vu, 1) = corredores_a_calcular(corr,1);
                                this.ParDisyuntivosVUOrig(cantidad_par_disy_vu, 2) = corredores_a_calcular(corr,2);
                                this.ParDisyuntivosVUOrig(cantidad_par_disy_vu, 3) = distancia_nodo_fin;
                                
                            elseif strcmp(proyecto_base.entrega_tipo_proyecto(), 'CC') || strcmp(proyecto_base.entrega_tipo_proyecto(), 'CS')
                                cantidad_par_disy_cscc = cantidad_par_disy_cscc + 1;
                                this.ParDisyuntivosCSCC(cantidad_par_disy_cscc, 1) = corredores_a_calcular(corr,1);
                                this.ParDisyuntivosCSCC(cantidad_par_disy_cscc, 2) = corredores_a_calcular(corr,2);
                                this.ParDisyuntivosCSCC(cantidad_par_disy_cscc, 3) = distancia_nodo_fin;
                                this.ParDisyuntivosCSCCOrig(cantidad_par_disy_cscc, 1) = corredores_a_calcular(corr,1);
                                this.ParDisyuntivosCSCCOrig(cantidad_par_disy_cscc, 2) = corredores_a_calcular(corr,2);
                                this.ParDisyuntivosCSCCOrig(cantidad_par_disy_cscc, 3) = distancia_nodo_fin;
                            elseif strcmp(proyecto_base.entrega_tipo_proyecto(), 'AL')
                                cantidad_par_disy_conv = cantidad_par_disy_conv + 1;
                                this.ParDisyuntivosConv(cantidad_par_disy_conv, 1) = corredores_a_calcular(corr,1);
                                this.ParDisyuntivosConv(cantidad_par_disy_conv, 2) = corredores_a_calcular(corr,2);
                                this.ParDisyuntivosConv(cantidad_par_disy_conv, 3) = distancia_nodo_fin;
                                this.ParDisyuntivosConvOrig(cantidad_par_disy_conv, 1) = corredores_a_calcular(corr,1);
                                this.ParDisyuntivosConvOrig(cantidad_par_disy_conv, 2) = corredores_a_calcular(corr,2);
                                this.ParDisyuntivosConvOrig(cantidad_par_disy_conv, 3) = distancia_nodo_fin;
                            else
                                error = MException('cOptMILP:calcula_parametros_disyuntivos','Caso de tipo de proyecto no se encuentra');
                                throw(error)
                            end
                        end
                        
                        % calcula par_dis para proyectos adyacentes
                        cant_descartar = sum(ismember(corredores_visitados, [id_se_1 id_se_2],'rows'));
                        corredores_visitados(ismember(corredores_visitados, [id_se_1 id_se_2],'rows'),:) = [];
                        cant_corredores_visitados = cant_corredores_visitados -cant_descartar;
                        
                        if z_corr > 0
                            [id_proy_elegibles_caso_actual, ~] = this.pAdmProy.determina_espacio_busqueda_calculo_pardis(plan_actual);
                        else
                            id_proy_elegibles_caso_actual = id_proy_elegibles;
                        end
                        
                        
                        grupos_id_proy_adyacentes = cell(0,1);
                        cant_grupos_adyacentes = 0;
                        for j = 1:cant_corredores_visitados
                            nombre_se_1_visitados = subestaciones(corredores_visitados(j,1)).entrega_nombre();
                            nombre_se_2_visitados = subestaciones(corredores_visitados(j,2)).entrega_nombre();
                            
                            id_nuevos = this.entrega_proyectos_corredor(nombre_se_1_visitados, nombre_se_2_visitados, id_proy_elegibles_caso_actual);
                            if ~isempty(id_nuevos)
                                cant_grupos_adyacentes = cant_grupos_adyacentes + 1;
                                grupos_id_proy_adyacentes{cant_grupos_adyacentes} = id_nuevos;
                                grupos_id_proy_adyacentes{cant_grupos_adyacentes} = [0 grupos_id_proy_adyacentes{cant_grupos_adyacentes}];
                            end
                        end

                        if cant_grupos_adyacentes == 0
                            combinaciones = [];
                        elseif cant_grupos_adyacentes == 1
                            combinaciones = grupos_id_proy_adyacentes{1}';
                        else
                            combinaciones = grupos_id_proy_adyacentes{1}';
                            for j = 2:cant_grupos_adyacentes
                                actual = grupos_id_proy_adyacentes{j}';
                                idx = transpose(ndgrid(1:size(combinaciones,1), 1:size(actual,1))); 
                                combinaciones = [repmat(actual,size(combinaciones,1),1), combinaciones(idx(:),:)];
                            end
                        end
                        
%                         if cant_grupos_adyacentes == 0
%                             combinaciones = [];
%                         elseif cant_grupos_adyacentes == 1
%                             combinaciones = combvec(grupos_id_proy_adyacentes{1});
%                         elseif cant_grupos_adyacentes == 2
%                             combinaciones = combvec(grupos_id_proy_adyacentes{1}, grupos_id_proy_adyacentes{2});
%                         elseif cant_grupos_adyacentes == 3
%                             combinaciones = combvec(grupos_id_proy_adyacentes{1}, grupos_id_proy_adyacentes{2}, grupos_id_proy_adyacentes{3});
%                         elseif cant_grupos_adyacentes == 4
%                             combinaciones = combvec(grupos_id_proy_adyacentes{1}, grupos_id_proy_adyacentes{2}, grupos_id_proy_adyacentes{3}, grupos_id_proy_adyacentes{4});
%                         elseif cant_grupos_adyacentes == 5
%                             combinaciones = combvec(grupos_id_proy_adyacentes{1}, grupos_id_proy_adyacentes{2}, grupos_id_proy_adyacentes{3}, grupos_id_proy_adyacentes{4}, grupos_id_proy_adyacentes{5});
%                         elseif cant_grupos_adyacentes == 6
%                             combinaciones = combvec(grupos_id_proy_adyacentes{1}, grupos_id_proy_adyacentes{2}, grupos_id_proy_adyacentes{3}, grupos_id_proy_adyacentes{4}, grupos_id_proy_adyacentes{5}, grupos_id_proy_adyacentes{6});
%                         elseif cant_grupos_adyacentes == 7
%                             combinaciones = combvec(grupos_id_proy_adyacentes{1}, grupos_id_proy_adyacentes{2}, grupos_id_proy_adyacentes{3}, grupos_id_proy_adyacentes{4}, grupos_id_proy_adyacentes{5}, grupos_id_proy_adyacentes{6}, grupos_id_proy_adyacentes{7});
%                         elseif cant_grupos_adyacentes == 8
%                             combinaciones = combvec(grupos_id_proy_adyacentes{1}, grupos_id_proy_adyacentes{2}, grupos_id_proy_adyacentes{3}, grupos_id_proy_adyacentes{4}, grupos_id_proy_adyacentes{5}, grupos_id_proy_adyacentes{6}, grupos_id_proy_adyacentes{7}, grupos_id_proy_adyacentes{8});
%                         else
%                             error = MException('cOptMILP:calcula_parametros_disyuntivos','Existen más cantidad de grupos adyacentes de los considerados');
%                             throw(error)
%                         end
%                         
%                         combinaciones = combinaciones';
                        [cant_combinaciones, ~] = size(combinaciones);
                                                
                        %for comb = 1:cant_combinaciones
for comb = 1:0
                            if sum(combinaciones(comb,:)) == 0
                                continue
                            end
                            
                            proyectos_agregar = combinaciones(comb,combinaciones(comb,:) ~= 0);
% disp(['Corr: ' num2str(corr) '. z_corr: ' num2str(z_corr) '. comb: ' num2str(comb) ' proy: ' num2str(proyectos_agregar)])
% if comb == 7
%     linlinlin = 1
% end
                            conect_agregar = [];
                            for j = 1:length(proyectos_agregar)
                                proy_base_agregar = this.pAdmProy.entrega_proyecto(proyectos_agregar(j));                                
                                
                                if proy_base_agregar.tiene_requisitos_conectividad()
                                    cantidad_req_conectividad = proy_base_agregar.entrega_cantidad_grupos_conectividad();
                                    
                                    for ii = 1:cantidad_req_conectividad
                                        indice_proy_conect = proy_base_agregar.entrega_indices_grupo_proyectos_conectividad(ii);
                                        if length(indice_proy_conect) > 1
                                            % TODO existe más de un tipo de
                                            % transformador que se puede
                                            % conectar. Este caso no se ha
                                            % visto aún
                                            error = MException('calcula_parametros_disyuntivos:caso_base','existe más de un proyecto de conectividad. Caso no se ha visto aún');
                                            throw(error)
                                        end
                                        if ~sep_actual.existe_proyecto(indice_proy_conect,1)
                                            conect_agregar = [conect_agregar indice_proy_conect];
                                            sep_actual.agrega_proyecto(this.pAdmProy.entrega_proyecto(indice_proy_conect));
                                        end
                                    end
                                end
                                sep_actual.agrega_proyecto(proy_base_agregar);
                            end
                             
                            % se calculan nuevamente los parámetros
                            % disyuntivos
                            % eventualmente cambiaron las subestaciones
                            
                            subestaciones_nuevas = sep_actual.entrega_subestaciones();
                            dist = [(1:1:length(subestaciones_nuevas))' inf*ones(length(subestaciones_nuevas),1)];
                                                        
                            % identifica posicion se_1 y se_2 en subestaciones
                            % del SEP
                            id_se_1 = this.entrega_posicion_subestacion(nombre_se_1_base, subestaciones_nuevas);
                            id_se_2 = this.entrega_posicion_subestacion(nombre_se_2_base, subestaciones_nuevas);
                            
                            dist(id_se_1,2) = 0;
                            while true
                                if isempty(dist)
                                    error = MException('cOptMILP:calcula_parametros_disyuntivos','No hay nodos por visitar, pero aún no se encontró nodo objetivo');
                                    throw(error)
                                end
                    
                                % selecciona nodo no visitado con menor distancia
                                [val_nodo_actual, id] = min(dist(:,2));
                                nodo_actual = dist(id, 1);
                                if nodo_actual == id_se_2
                                    distancia_nodo_fin = val_nodo_actual;
                                    break;
                                end
                                dist(id, :) = [];
                   
                                conexiones = subestaciones_nuevas(nodo_actual).entrega_lineas();
                                conexiones = [conexiones; subestaciones_nuevas(nodo_actual).entrega_transformadores2d()];
                                for ii = 1:length(conexiones)
                                    ubic_se_adyacente = find(dist(:,1) == conexiones(ii).entrega_se1().entrega_id(), 1);
                                    if isempty(ubic_se_adyacente)
                                        ubic_se_adyacente = find(dist(:,1) == conexiones(ii).entrega_se2().entrega_id());
                                    end
                                    if isempty(ubic_se_adyacente)
                                        continue;
                                    end
                                    xpu_conexion = conexiones(ii).entrega_reactancia_pu();
                                    fmax_pu_conexion = conexiones(ii).entrega_sr_pu();
                                    dmax_conexion = fmax_pu_conexion*xpu_conexion;
                                    valor_nodo = val_nodo_actual + dmax_conexion;
                                    if valor_nodo < dist(ubic_se_adyacente,2)
                                        dist(ubic_se_adyacente,2) = valor_nodo;
                                    end
                                end
                            end
                        
                            if z_corr == 0
                                if distancia_nodo_fin > this.ParDisyuntivosBase(corr, 3)
                                    this.ParDisyuntivosBase(corr, 3) = distancia_nodo_fin;
                                end
                            else
                                proyecto_base = this.pAdmProy.entrega_proyecto(id_proyectos_corredor(z_corr));
                                if strcmp(proyecto_base.entrega_tipo_proyecto(), 'AV')
                                    if distancia_nodo_fin > this.ParDisyuntivosVU(cantidad_par_disy_vu, 3)
                                        this.ParDisyuntivosVU(cantidad_par_disy_vu, 3) = distancia_nodo_fin;
                                    end
                                elseif strcmp(proyecto_base.entrega_tipo_proyecto(), 'CC') || strcmp(proyecto_base.entrega_tipo_proyecto(), 'CS')
                                    if distancia_nodo_fin > this.ParDisyuntivosCSCC(cantidad_par_disy_cscc,3)
                                        this.ParDisyuntivosCSCC(cantidad_par_disy_cscc, 3) = distancia_nodo_fin;
                                    end
                                elseif strcmp(proyecto_base.entrega_tipo_proyecto(), 'AL')
                                    if distancia_nodo_fin > this.ParDisyuntivosConv(cantidad_par_disy_conv,3)
                                        this.ParDisyuntivosConv(cantidad_par_disy_conv, 3) = distancia_nodo_fin;
                                    end
                                else
                                    error = MException('cOptMILP:calcula_parametros_disyuntivos','Caso de tipo de proyecto no se encuentra');
                                    throw(error)
                                end
                            end
                            
                            % Fin de cálculo de pardisy para combinación
                            % se deshacen los cambios en el SEP para
                            % combinación actual
                            for ii = 1:length(proyectos_agregar)
                                proyecto = this.pAdmProy.entrega_proyecto(proyectos_agregar(ii));
                                sep_actual.elimina_proyecto(proyecto);
                            end
                            for k = length(conect_agregar):-1:1
                                proyecto = this.pAdmProy.entrega_proyecto(conect_agregar(k));
                                sep_actual.elimina_proyecto(proyecto);
                            end                                                        
                        end
                    end
                end
            end
            fprintf('%s %s\n',' ', [num2str(100) '%']);            
            
            % Ahora se calculan valores para subestaciones que no existen
            contador = 10;
            disp('Incorpora proyectos subestaciones no existentes')
            for corr = 1:cant_corredores
                porcentaje = corr/cant_corredores*100;
                if porcentaje > contador
                    while contador + 10 < porcentaje
                        contador = contador + 10;
                    end

                    fprintf('%s %s',' ', [num2str(contador) '%']);
                    contador = contador + 10;
                    pause(0.1);
                end
                if corredores_a_calcular(corr,3) > 0
                    % hay que identificar las subestaciones que se
                    % conectan, y tomar el mayor valor de los parámetros
                    % disyuntivos base
                    id_se_1 = corredores_a_calcular(corr,1);
                    id_se_2 = corredores_a_calcular(corr,2);
                    
                    if this.pParOpt.EstrategiaAngulosSENuevas == 0
                        % Ángulo SE nuevas es igual a SE Adyacentes
                        
                        if corredores_a_calcular(corr,3) == 1
                            % quiere decir que es parametro disyuntivo que
                            % conecta a una subestación
                            id_proyectos_corredor = this.entrega_proyectos_trafo_vu(id_se_1, id_se_2, id_proy_elegibles);
                            proyecto_vu = this.pAdmProy.entrega_proyecto(id_proyectos_corredor);
                            elred = proyecto_vu.Elemento(end);
                            xpu_conexion = elred.entrega_reactancia_pu();
                            fmax_pu_conexion = elred.entrega_sr_pu();
                            dmax_conexion = fmax_pu_conexion*xpu_conexion;

                            this.ParDisyuntivosBaseOrig(corr, 1) = corredores_a_calcular(corr,1);
                            this.ParDisyuntivosBaseOrig(corr, 2) = corredores_a_calcular(corr,2);
                            this.ParDisyuntivosBaseOrig(corr, 3) = dmax_conexion;
                            this.ParDisyuntivosBase(corr, 1) = corredores_a_calcular(corr,1);
                            this.ParDisyuntivosBase(corr, 2) = corredores_a_calcular(corr,2);
                            this.ParDisyuntivosBase(corr, 3) = dmax_conexion;

                        elseif corredores_a_calcular(corr,3) == 2  
                            % ambas subestaciones faltan
                            % en este caso los parámetros disyuntivos
                            % corresponden a Base, CSCC y Conv y VU de
                            % subestaciones existentes

                            se_1_existente = cSubestacion.empty;
                            se_2_existente = cSubestacion.empty;

                            id_proyectos_corredor = this.entrega_proyectos_corredor_vu(id_se_1, id_se_2, id_proy_elegibles);
                            proyecto_vu = this.pAdmProy.entrega_proyecto(id_proyectos_corredor);
                            cantidad_grupos_conectividad = proyecto_vu.entrega_cantidad_grupos_conectividad();
                            for no_grupo = 1:cantidad_grupos_conectividad
                                proy_con = proyecto_vu.entrega_grupo_proyectos_conectividad(no_grupo);
                                if strcmp(proy_con(1).entrega_tipo_proyecto(), 'AS')
                                    continue;
                                end
                                for ii = 1:length(proy_con)
                                    elred = proy_con(ii).Elemento(1);                                
                                    if isempty(se_1_existente)
                                        if elred.entrega_se1().Existente
                                            se_1_existente = elred.entrega_se1();
                                        else
                                            se_1_existente = elred.entrega_se2();
                                        end
                                    else
                                        if elred.entrega_se1().Existente
                                            se_2_existente = elred.entrega_se1();
                                        else
                                            se_2_existente = elred.entrega_se2();
                                        end
                                    end
                                end
                            end
                            if isempty(se_1_existente) || isempty(se_2_existente)
                                error = MException('cOptMILP:calcula_parametros_disyuntivos','No se pudo encontrar subestaciones existentes en proyecto VU');
                                throw(error)
                            end                    

                            % obten parametros disyuntivos
                            par_dis_base = this.entrega_parametro_disyuntivo_base(se_1_existente.entrega_id(), se_2_existente.entrega_id());
                            this.ParDisyuntivosBaseOrig(corr, 1) = corredores_a_calcular(corr,1);
                            this.ParDisyuntivosBaseOrig(corr, 2) = corredores_a_calcular(corr,2);
                            this.ParDisyuntivosBaseOrig(corr, 3) = par_dis_base;
                            this.ParDisyuntivosBase(corr, 1) = corredores_a_calcular(corr,1);
                            this.ParDisyuntivosBase(corr, 2) = corredores_a_calcular(corr,2);
                            this.ParDisyuntivosBase(corr, 3) = par_dis_base;

                            % pardis VU 
                            par_dis_vu = this.entrega_parametro_disyuntivo_vu(se_1_existente.entrega_id(), se_2_existente.entrega_id());
                            if par_dis_vu == 0
                                error = MException('cOptMILP:calcula_parametros_disyuntivos','No se pudo encontrar par. dis. VU para subestaciones existentes');
                                throw(error)                            
                            end

                            cantidad_par_disy_vu = cantidad_par_disy_vu + 1;
                            this.ParDisyuntivosVU(cantidad_par_disy_vu, 1) = corredores_a_calcular(corr,1);
                            this.ParDisyuntivosVU(cantidad_par_disy_vu, 2) = corredores_a_calcular(corr,2);
                            this.ParDisyuntivosVU(cantidad_par_disy_vu, 3) = par_dis_vu;
                            this.ParDisyuntivosVUOrig(cantidad_par_disy_vu, 1) = corredores_a_calcular(corr,1);
                            this.ParDisyuntivosVUOrig(cantidad_par_disy_vu, 2) = corredores_a_calcular(corr,2);
                            this.ParDisyuntivosVUOrig(cantidad_par_disy_vu, 3) = par_dis_vu;

                            par_dis_cscc = this.entrega_parametro_disyuntivo_cscc(se_1_existente.entrega_id(), se_2_existente.entrega_id());
                            if par_dis_cscc > 0
                                cantidad_par_disy_cscc = cantidad_par_disy_cscc + 1;
                                this.ParDisyuntivosCSCC(cantidad_par_disy_cscc, 1) = corredores_a_calcular(corr,1);
                                this.ParDisyuntivosCSCC(cantidad_par_disy_cscc, 2) = corredores_a_calcular(corr,2);
                                this.ParDisyuntivosCSCC(cantidad_par_disy_cscc, 3) = par_dis_cscc;
                                this.ParDisyuntivosCSCCOrig(cantidad_par_disy_cscc, 1) = corredores_a_calcular(corr,1);
                                this.ParDisyuntivosCSCCOrig(cantidad_par_disy_cscc, 2) = corredores_a_calcular(corr,2);
                                this.ParDisyuntivosCSCCOrig(cantidad_par_disy_cscc, 3) = par_dis_cscc;
                            end

                            par_dis_conv = this.entrega_parametro_disyuntivo_conv(se_1_existente.entrega_id(), se_2_existente.entrega_id());
                            if par_dis_conv > 0
                                cantidad_par_disy_conv = cantidad_par_disy_conv + 1;
                                this.ParDisyuntivosConv(cantidad_par_disy_conv, 1) = corredores_a_calcular(corr,1);
                                this.ParDisyuntivosConv(cantidad_par_disy_conv, 2) = corredores_a_calcular(corr,2);
                                this.ParDisyuntivosConv(cantidad_par_disy_conv, 3) = par_dis_conv;
                                this.ParDisyuntivosConvOrig(cantidad_par_disy_conv, 1) = corredores_a_calcular(corr,1);
                                this.ParDisyuntivosConvOrig(cantidad_par_disy_conv, 2) = corredores_a_calcular(corr,2);
                                this.ParDisyuntivosConvOrig(cantidad_par_disy_conv, 3) = par_dis_conv;
                            end
                        end
                    else
                        % Angulo SE nuevas se pone igual a cero
                        angulo_maximo = this.pParOpt.AnguloMaximoBuses;
                        this.ParDisyuntivosBaseOrig(corr, 1) = corredores_a_calcular(corr,1);
                        this.ParDisyuntivosBaseOrig(corr, 2) = corredores_a_calcular(corr,2);
                        this.ParDisyuntivosBaseOrig(corr, 3) = angulo_maximo;
                        this.ParDisyuntivosBase(corr, 1) = corredores_a_calcular(corr,1);
                        this.ParDisyuntivosBase(corr, 2) = corredores_a_calcular(corr,2);
                        this.ParDisyuntivosBase(corr, 3) = angulo_maximo;
                    end
                end
            end
            fprintf('%s %s\n',' ', [num2str(100) '%']);            
            
            
            if this.iNivelDebug > 1
                prot = cProtocolo.getInstance;
                prot.imprime_texto('\nParametros disyuntivos. Elemento es solo de referencia:');
                texto = sprintf('%-30s %-15s %-15s %-10s         %-5s     %-10s %-10s %-10s %-10s     %-5s            %-10s     %-5s      %-10s        %-5s  %-10s         %-5s      %-10s ', ...
                    'Elemento', 'Bus1', 'Bus2',   'ValElem' ,'F.E', 'MBase','MVU','MCC','MConv','F.B', 'MBaseOrig', 'F.VU', 'MVUOrig', 'F.CC', 'MCCOrig','F.Co', 'MConvOrig');
                prot.imprime_texto(texto);
                % siguientes contenedores son sólo para verificar que todos
                % los parámetros disyuntivos fueron seleccionados para
                % imprimir
                
                for i = 1:length(el_red)
                    [se_1, se_2] = el_red(i).entrega_subestaciones();
                    id_se_1 = se_1.entrega_id();
                    id_se_2 = se_2.entrega_id();
                    
                    par_disy_base = this.entrega_parametro_disyuntivo_base(id_se_1, id_se_2);
                    par_disy_base_orig = this.entrega_parametro_disyuntivo_base_orig(id_se_1, id_se_2);
                    texto_adicional_base = '';
                    if par_disy_base ~= par_disy_base_orig
                        texto_adicional_base = '*';
                    end

                    par_disy_vu = this.entrega_parametro_disyuntivo_vu(id_se_1, id_se_2);
                    par_disy_vu_orig = this.entrega_parametro_disyuntivo_vu_orig(id_se_1, id_se_2);
                    if par_disy_vu == 0
                        texto_par_disy_vu = '-';
                        texto_par_disy_vu_orig = '-';
                    else
                        texto_par_disy_vu = num2str(par_disy_vu);
                        texto_par_disy_vu_orig = num2str(par_disy_vu_orig);
                    end
                    texto_adicional_vu = '';
                    if par_disy_vu ~= par_disy_vu_orig
                        texto_adicional_vu = '*';
                    end
                    
                    par_disy_cscc = this.entrega_parametro_disyuntivo_cscc(id_se_1, id_se_2);
                    par_disy_cscc_orig = this.entrega_parametro_disyuntivo_cscc_orig(id_se_1, id_se_2);
                    if par_disy_cscc == 0
                        texto_par_disy_cscc = '-';
                        texto_par_disy_cscc_orig = '-';
                    else
                        texto_par_disy_cscc = num2str(par_disy_cscc);
                        texto_par_disy_cscc_orig = num2str(par_disy_cscc_orig);
                    end
                    texto_adicional_cscc = '';
                    if ~strcmp(texto_par_disy_cscc,texto_par_disy_cscc_orig)
                        texto_adicional_cscc = '*';
                    end

                    par_disy_conv = this.entrega_parametro_disyuntivo_conv(id_se_1, id_se_2);
                    par_disy_conv_orig = this.entrega_parametro_disyuntivo_conv_orig(id_se_1, id_se_2);
                    if par_disy_conv == 0
                        texto_par_disy_conv = '-';
                        texto_par_disy_conv_orig = '-';
                    else
                        texto_par_disy_conv = num2str(par_disy_conv);
                        texto_par_disy_conv_orig = num2str(par_disy_conv_orig);
                    end
                    texto_adicional_conv = '';
                    if ~strcmp(texto_par_disy_conv,texto_par_disy_conv_orig)
                        texto_adicional_conv = '*';
                    end
                    
                    nombre_elred = el_red(i).entrega_nombre();
                    nombre_se_1 = se_1.entrega_nombre();
                    nombre_se_2 = se_2.entrega_nombre();
                    xpu_conexion = el_red(i).entrega_reactancia_pu();
                    fmax_pu_conexion = el_red(i).entrega_sr_pu();
                    par_disy_directo = fmax_pu_conexion*xpu_conexion;
                    texto_adicional_directo = '';
                    if par_disy_directo > par_disy_base
                        texto_adicional_directo = '*';
                    end

                    texto = sprintf('%-30s %-15s %-15s %-10s         %-5s     %-10s %-10s %-10s %-10s     %-5s            %-10s     %-5s      %-10s        %-5s  %-10s         %-5s      %-10s ', ...
                        nombre_elred, nombre_se_1, nombre_se_2, ...
                        num2str(par_disy_directo), texto_adicional_directo, ...
                        num2str(par_disy_base), texto_par_disy_vu, texto_par_disy_cscc, texto_par_disy_conv, ...
                        texto_adicional_base, num2str(par_disy_base_orig), ...
                        texto_adicional_vu, texto_par_disy_vu_orig, ...
                        texto_adicional_cscc, texto_par_disy_cscc_orig, ...
                        texto_adicional_conv, texto_par_disy_conv_orig);
                    prot.imprime_texto(texto);                    
                end
            end
        end
        
        function par_disy = entrega_parametro_disyuntivo_base(this, id_se_1, id_se_2)
            [~, ubic] = ismember([id_se_1 id_se_2], this.ParDisyuntivosBase(:,1:2), 'rows');
            if ubic == 0
                [~, ubic] = ismember([id_se_2 id_se_1], this.ParDisyuntivosBase(:,1:2), 'rows');
            end
            if ubic == 0
                error = MException('cOptMILP:calcula_parametros_disyuntivos','Parametro disyuntivo no encontrado');
                throw(error)
            end
            par_disy = this.ParDisyuntivosBase(ubic,3);
        end

        function par_disy = entrega_parametro_disyuntivo_base_orig(this, id_se_1, id_se_2)
            [~, ubic] = ismember([id_se_1 id_se_2], this.ParDisyuntivosBaseOrig(:,1:2), 'rows');
            if ubic == 0
                [~, ubic] = ismember([id_se_2 id_se_1], this.ParDisyuntivosBaseOrig(:,1:2), 'rows');
            end
            if ubic == 0
                error = MException('cOptMILP:calcula_parametros_disyuntivos','Parametro disyuntivo no encontrado');
                throw(error)
            end
            par_disy = this.ParDisyuntivosBaseOrig(ubic,3);
        end
        
        function par_disy = entrega_parametro_disyuntivo_vu(this, id_se_1, id_se_2)
            [~, ubic] = ismember([id_se_1 id_se_2], this.ParDisyuntivosVU(:,1:2), 'rows');
            par_disy = 0;
            if ubic == 0
                [~, ubic] = ismember([id_se_2 id_se_1], this.ParDisyuntivosVU(:,1:2), 'rows');
            end
            if ubic ~= 0
                par_disy = this.ParDisyuntivosVU(ubic,3);
            end
        end

        function par_disy = entrega_parametro_disyuntivo_vu_orig(this, id_se_1, id_se_2)
            [~, ubic] = ismember([id_se_1 id_se_2], this.ParDisyuntivosVUOrig(:,1:2), 'rows');
            par_disy = 0;
            if ubic == 0
                [~, ubic] = ismember([id_se_2 id_se_1], this.ParDisyuntivosVUOrig(:,1:2), 'rows');
            end
            if ubic ~= 0
                par_disy = this.ParDisyuntivosVUOrig(ubic,3);
            end
        end
        
        function par_disy = entrega_parametro_disyuntivo_cscc(this, id_se_1, id_se_2)
            [~, ubic] = ismember([id_se_1 id_se_2], this.ParDisyuntivosCSCC(:,1:2), 'rows');
            par_disy = 0;
            if ubic == 0
                [~, ubic] = ismember([id_se_2 id_se_1], this.ParDisyuntivosCSCC(:,1:2), 'rows');
            end
            if ubic ~= 0
                par_disy = this.ParDisyuntivosCSCC(ubic,3);
            end
        end
        
        function par_disy = entrega_parametro_disyuntivo_cscc_orig(this, id_se_1, id_se_2)
            [~, ubic] = ismember([id_se_1 id_se_2], this.ParDisyuntivosCSCCOrig(:,1:2), 'rows');
            par_disy = 0;
            if ubic == 0
                [~, ubic] = ismember([id_se_2 id_se_1], this.ParDisyuntivosCSCCOrig(:,1:2), 'rows');
            end
            if ubic ~= 0
                par_disy = this.ParDisyuntivosCSCCOrig(ubic,3);
            end
        end

        function par_disy = entrega_parametro_disyuntivo_conv(this, id_se_1, id_se_2)
            [~, ubic] = ismember([id_se_1 id_se_2], this.ParDisyuntivosConv(:,1:2), 'rows');
            par_disy = 0;
            if ubic == 0
                [~, ubic] = ismember([id_se_2 id_se_1], this.ParDisyuntivosConv(:,1:2), 'rows');
            end
            if ubic ~= 0
                par_disy = this.ParDisyuntivosConv(ubic,3);
            end
        end
        
        function par_disy = entrega_parametro_disyuntivo_conv_orig(this, id_se_1, id_se_2)
            [~, ubic] = ismember([id_se_1 id_se_2], this.ParDisyuntivosConvOrig(:,1:2), 'rows');
            par_disy = 0;
            if ubic == 0
                [~, ubic] = ismember([id_se_2 id_se_1], this.ParDisyuntivosConvOrig(:,1:2), 'rows');
            end
            if ubic ~= 0
                par_disy = this.ParDisyuntivosConvOrig(ubic,3);
            end
        end
        
        function inicializa_modelo_fico(this)
            this.docIDFico = fopen(this.NombreArchivoModeloFICO,'w');
            fprintf(this.docIDFico, 'model TNEP\n');
            %fprintf(this.docIDFico, 'uses "mmxprs","mmsheet";\n');
            fprintf(this.docIDFico, 'uses "mmxprs";\n');
            fprintf(this.docIDFico, '\n');
%            fprintf(this.docIDFico, 'parameters\n');
%            fprintf(this.docIDFico, 'Resultados = ''results.xlsx''\n');
%            fprintf(this.docIDFico, 'end-parameters\n');
            fprintf(this.docIDFico, '\n');
            fprintf(this.docIDFico, 'declarations\n');
            fprintf(this.docIDFico, ['x: array(1..' num2str(this.iCantVarDecision) ') of mpvar\n']);
                        
%            fprintf(this.docIDFico, ['results: array(1..' num2str(this.iCantVarDecision) ') of real\n']);
            fprintf(this.docIDFico, '\n');
            
            fprintf(this.docIDFico, 'Objective:linctr\n');
            fprintf(this.docIDFico, 'end-declarations\n');

            fprintf(this.docIDFico, ['setparam("XPRS_MAXTIME", ' num2str(this.pParOpt.MaxTime) ')\n']);
            fprintf(this.docIDFico, ['setparam("XPRS_MAXMEMORY", ' num2str(this.pParOpt.MaxMemory) ')\n']);
            fprintf(this.docIDFico, 'setparam("XPRS_VERBOSE", true)\n');
            if this.pParOpt.MaxGap > 0
                fprintf(this.docIDFico, ['setparam("XPRS_MIPRELSTOP", ' num2str(this.pParOpt.MaxGap) ')\n']);
            end
            
            for i = 1:this.iCantVarDecision
                if ismember(i,this.intcon)
                    fprintf(this.docIDFico, ['x(' num2str(i) ') is_binary\n']);
                else
                    if this.lb(i) < 0
                        fprintf(this.docIDFico, ['x(' num2str(i) ') is_free\n']);
                        fprintf(this.docIDFico, ['x(' num2str(i) ') >= ' num2str(this.lb(i)) '\n']);
                    end
                    fprintf(this.docIDFico, ['x(' num2str(i) ') <= ' num2str(this.ub(i)) '\n']);
                end
            end
            
        end
        
        function finaliza_modelo_fico(this)
            fprintf(this.docIDFico, '\nminimise(Objective)\n');
            texto = ['fopen("' this.NombreArchivoResultadoFICO '", F_OUTPUT)\n'];            
            fprintf(this.docIDFico, texto);
            texto = ['forall(i in 1..' num2str(this.iCantVarDecision) ') do \n'];
            fprintf(this.docIDFico, texto);
            texto = 'writeln(getsol(x(i)))\n';
            fprintf(this.docIDFico, texto);
            texto = 'end-do\n';
            fprintf(this.docIDFico, texto);
            texto = 'fclose(F_OUTPUT)';
            fprintf(this.docIDFico, texto);
                
            fprintf(this.docIDFico, '\nend-model\n');
            fclose(this.docIDFico);
        end
        
        function ingresa_nombres_archivos_fico(this, nombre_archivo_modelo_fico,nombre_archivo_resultado_fico)
            this.NombreArchivoModeloFICO = nombre_archivo_modelo_fico;
            this.NombreArchivoResultadoFICO = nombre_archivo_resultado_fico;
        end
        
        function lee_y_guarda_solucion_fico(this)
            docID = fopen(this.NombreArchivoResultadoFICO,'r');
            tline = fgetl(docID);
            id_var = 0;
            this.ResOptimizacion = zeros(this.iCantVarDecision,1);
            while tline ~= -1
                id_var = id_var + 1;
                this.ResOptimizacion(id_var) = str2double(tline);
                tline = fgetl(docID);
            end
        end
        
        function calcula_coper_sin_restricciones_subetapas(this)
            t_inicio = clock;
            this.COperUninodal = zeros(1,this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas);
            % límites de variables de decisión se ponen a cero
            lb_oper = this.lb;
            ub_oper = this.ub;

            % variables de operación de subestaciones, líneas y
            % transformadores se ponen a cero
            for i = 1:length(this.VarOperacion)
                if isa(this.VarOperacion(i), 'cSubestacion')
                    for escenario = 1:this.iCantEscenarios
                        for etapa = 1:this.iCantEtapas
                            indice_desde = this.VarOperacion(i).entrega_varopt_operacion('Theta', escenario, etapa);
                            indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;                        

                            lb_oper(indice_desde:indice_hasta) = 0;
                            ub_oper(indice_desde:indice_hasta) = 0;
                        end
                    end
                elseif isa(this.VarOperacion(i), 'cLinea') || isa(this.VarOperacion(i), 'cTransformador2D')
                    for escenario = 1:this.iCantEscenarios
                        for etapa = 1:this.iCantEtapas
                            indice_desde = this.VarOperacion(i).entrega_varopt_operacion('P', escenario, etapa);
                            indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;

                            lb_oper(indice_desde:indice_hasta) = 0;
                            ub_oper(indice_desde:indice_hasta) = 0;
                        end
                    end
                end
            end

            if this.pParOpt.ComputoParalelo
                disp('Calcula costos de operacion sin restricciones subetapas modo paralelo')

                coper = zeros(1,this.iCantEscenarios*this.iCantEtapas);
                parfor j = 1:this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas
                    t_inicio_parfor = clock;
                    [escenario, etapa, subetapa] = ind2sub([this.iCantEscenarios, this.iCantEtapas, this.iCantSubetapas],j);
                    
                    % Identifica todas variables válidas para el escenario y la etapa
                    id_vars = this.TipoVarOpt == 2 &  this.EscenarioVarOpt == escenario & this.EtapaVarOpt == etapa & this.SubetapaVarOpt == subetapa;

                    fobj_actual = this.Fobj(id_vars);
                    lb_actual = lb_oper(id_vars);
                    ub_actual = ub_oper(id_vars);

                    [Aeq_oper_sr, beq_actual] = this.entrega_rest_be_uninodal_por_caso(escenario, etapa, subetapa);
                    Aeq_actual = Aeq_oper_sr(:,id_vars);
                    if strcmp(this.pParOpt.Solver, 'Intlinprog')
                        options = optimoptions('intlinprog');
                        options.ConstraintTolerance = 1e-9;
                        options.IntegerTolerance = 1e-6;
                        options.RelativeGapTolerance = 1e-8;
                        [x_oper,fval,exitflag_oper_sr,output] = intlinprog(fobj_actual,intcon_oper_sr,Aineq_oper_sr,bineq_oper_sr,Aeq_oper_sr,beq_oper_sr,lb_oper_sr,ub_oper_sr, options);
                    elseif strcmp(this.pParOpt.Solver, 'Xpress')
                        %options= xprsoptimset('MAXMEMORY',this.pParOpt.MaxMemory,'MAXTIME',this.pParOpt.MaxTime);
                        %if this.pParOpt.MaxGap > 0
                        %    options = xprsoptimset(options,'MIPRELSTOP',this.pParOpt.MaxGap); 
                        %end
                        options = xprsoptimset('OUTPUTLOG',0);
                        rtype = repmat('E',[1 size(Aeq_actual,1)]);
                        [x_oper,fval,exitflag,output, lambda] = xprslp(fobj_actual, Aeq_actual, beq_actual,rtype, lb_actual,ub_actual,options);%, options);
                    end
                    tiempo = etime(clock,t_inicio_parfor);
                    disp(['Coper sin restricciones escenario ' num2str(escenario) ' etapa ' num2str(etapa) ' subetapa ' num2str(subetapa) ': ' num2str(fval) '. Dt:' num2str(tiempo)])
                    coper(j) = fval;
                end
                this.COperUninodal = coper;
            else
                disp('Calcula costos de operacion sin restricciones subetapas modo secuencial')
                
                for j = 1:this.iCantEscenarios*this.iCantEtapas*this.iCantSubetapas
                    [escenario, etapa, subetapa] = ind2sub([this.iCantEscenarios, this.iCantEtapas, this.iCantSubetapas],j);
                    t_inicio_for = clock;
                    % Identifica todas variables válidas para el escenario y la etapa
                    id_vars = this.TipoVarOpt == 2 &  this.EscenarioVarOpt == escenario & this.EtapaVarOpt == etapa & this.SubetapaVarOpt == subetapa;

                    fobj_actual = this.Fobj(id_vars);
                    lb_actual = lb_oper(id_vars);
                    ub_actual = ub_oper(id_vars);

                    [Aeq_oper_sr, beq_actual] = this.entrega_rest_be_uninodal_por_caso(escenario, etapa, subetapa);
                    Aeq_actual = Aeq_oper_sr(:,id_vars);
                    if strcmp(this.pParOpt.Solver, 'Intlinprog')
                        options = optimoptions('intlinprog');
                        options.ConstraintTolerance = 1e-9;
                        options.IntegerTolerance = 1e-6;
                        options.RelativeGapTolerance = 1e-8;
                        [x_oper,fval,exitflag_oper_sr,output] = intlinprog(fobj_actual,intcon_oper_sr,Aineq_oper_sr,bineq_oper_sr,Aeq_oper_sr,beq_oper_sr,lb_oper_sr,ub_oper_sr, options);
                    elseif strcmp(this.pParOpt.Solver, 'Xpress')
                        %options= xprsoptimset('MAXMEMORY',this.pParOpt.MaxMemory,'MAXTIME',this.pParOpt.MaxTime);
                        %if this.pParOpt.MaxGap > 0
                        %    options = xprsoptimset(options,'MIPRELSTOP',this.pParOpt.MaxGap); 
                        %end
                        options = xprsoptimset('OUTPUTLOG',0);
                        rtype = repmat('E',[1 size(Aeq_actual,1)]);
                        [x_oper,fval,exitflag,output, lambda] = xprslp(fobj_actual, Aeq_actual, beq_actual,rtype, lb_actual,ub_actual,options);%, options);
                    end
                    tiempo = etime(clock,t_inicio_for);
                    disp(['Coper sin restricciones escenario ' num2str(escenario) ' etapa ' num2str(etapa) ' subetapa ' num2str(subetapa) ': ' num2str(fval) '. Dt:' num2str(tiempo)])
                    this.COperUninodal(j) = fval;
                end
            end
            tiempo = etime(clock,t_inicio);
            disp(['Tiempo total: ' num2str(tiempo)])
        end
        
        function calcula_coper_sin_restricciones(this)
            t_inicio = clock;
            this.COperUninodal = zeros(1,this.iCantEscenarios*this.iCantEtapas);
            % límites de variables de decisión se ponen a cero
            lb_oper = this.lb;
            ub_oper = this.ub;

            % variables de operación de subestaciones, líneas y
            % transformadores se ponen a cero
            for i = 1:length(this.VarOperacion)
                if isa(this.VarOperacion(i), 'cSubestacion')
                    for escenario = 1:this.iCantEscenarios
                        for etapa = 1:this.iCantEtapas
                            indice_desde = this.VarOperacion(i).entrega_varopt_operacion('Theta', escenario, etapa);
                            indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;                        

                            lb_oper(indice_desde:indice_hasta) = 0;
                            ub_oper(indice_desde:indice_hasta) = 0;
                        end
                    end
                elseif isa(this.VarOperacion(i), 'cLinea') || isa(this.VarOperacion(i), 'cTransformador2D')
                    for escenario = 1:this.iCantEscenarios
                        for etapa = 1:this.iCantEtapas
                            indice_desde = this.VarOperacion(i).entrega_varopt_operacion('P', escenario, etapa);
                            indice_hasta = indice_desde + this.iCantPuntosOperacion - 1;

                            lb_oper(indice_desde:indice_hasta) = 0;
                            ub_oper(indice_desde:indice_hasta) = 0;
                        end
                    end
                end
            end
            
            if this.pParOpt.ComputoParalelo
                disp('Calcula costos de operacion sin restricciones modo paralelo')

                coper = zeros(1,this.iCantEscenarios*this.iCantEtapas);
                parfor j = 1:this.iCantEscenarios*this.iCantEtapas
                    t_inicio_parfor = clock;
                    [escenario,etapa]=ind2sub([this.iCantEscenarios, this.iCantEtapas],j);

                    % Identifica todas variables válidas para el escenario y la etapa
                    id_vars = this.TipoVarOpt == 2 &  this.EscenarioVarOpt == escenario & this.EtapaVarOpt == etapa;

                    fobj_actual = this.Fobj(id_vars);
                    lb_actual = lb_oper(id_vars);
                    ub_actual = ub_oper(id_vars);

                    [Aeq_oper_sr, beq_actual] = this.entrega_rest_be_uninodal_por_caso(escenario, etapa);
                    Aeq_actual = Aeq_oper_sr(:,id_vars);
                    if strcmp(this.pParOpt.Solver, 'Intlinprog')
                        options = optimoptions('intlinprog');
                        options.ConstraintTolerance = 1e-9;
                        options.IntegerTolerance = 1e-6;
                        options.RelativeGapTolerance = 1e-8;
                        [x_oper,fval,exitflag_oper_sr,output] = intlinprog(fobj_actual,intcon_oper_sr,Aineq_oper_sr,bineq_oper_sr,Aeq_oper_sr,beq_oper_sr,lb_oper_sr,ub_oper_sr, options);
                    elseif strcmp(this.pParOpt.Solver, 'Xpress')
                        %options= xprsoptimset('MAXMEMORY',this.pParOpt.MaxMemory,'MAXTIME',this.pParOpt.MaxTime);
                        %if this.pParOpt.MaxGap > 0
                        %    options = xprsoptimset(options,'MIPRELSTOP',this.pParOpt.MaxGap); 
                        %end
                        options = xprsoptimset('OUTPUTLOG',0);
                        rtype = repmat('E',[1 size(Aeq_actual,1)]);
                        [x_oper,fval,exitflag,output, lambda] = xprslp(fobj_actual, Aeq_actual, beq_actual,rtype, lb_actual,ub_actual,options);%, options);
                    end
                    coper(j) = fval;
                    tiempo = etime(clock,t_inicio_parfor)
                    disp(['Coper sin restricciones escenario ' num2str(escenario) ' etapa ' num2str(etapa) ':' num2str(fval) '. DT: ' num2str(tiempo)])
                end
                this.COperUninodal = coper;
            else
                disp('Calcula costos de operacion sin restricciones modo secuencial')

                for j = 1:this.iCantEscenarios*this.iCantEtapas
                    t_inicio_for = clock;
                    [escenario,etapa]=ind2sub([this.iCantEscenarios, this.iCantEtapas],j);

                    % Identifica todas variables válidas para el escenario y la etapa
                    id_vars = this.TipoVarOpt == 2 &  this.EscenarioVarOpt == escenario & this.EtapaVarOpt == etapa;

                    fobj_actual = this.Fobj(id_vars);
                    lb_actual = lb_oper(id_vars);
                    ub_actual = ub_oper(id_vars);

                    [Aeq_oper_sr, beq_actual] = this.entrega_rest_be_uninodal_por_caso(escenario, etapa);
                    Aeq_actual = Aeq_oper_sr(:,id_vars);
                    if strcmp(this.pParOpt.Solver, 'Intlinprog')
                        options = optimoptions('intlinprog');
                        options.ConstraintTolerance = 1e-9;
                        options.IntegerTolerance = 1e-6;
                        options.RelativeGapTolerance = 1e-8;
                        [x_oper,fval,exitflag_oper_sr,output] = intlinprog(fobj_actual,intcon_oper_sr,Aineq_oper_sr,bineq_oper_sr,Aeq_oper_sr,beq_oper_sr,lb_oper_sr,ub_oper_sr, options);
                    elseif strcmp(this.pParOpt.Solver, 'Xpress')
                        %options= xprsoptimset('MAXMEMORY',this.pParOpt.MaxMemory,'MAXTIME',this.pParOpt.MaxTime);
                        %if this.pParOpt.MaxGap > 0
                        %    options = xprsoptimset(options,'MIPRELSTOP',this.pParOpt.MaxGap); 
                        %end
                        options = xprsoptimset('OUTPUTLOG',0);
                        rtype = repmat('E',[1 size(Aeq_actual,1)]);
                        [x_oper,fval,exitflag,output, lambda] = xprslp(fobj_actual, Aeq_actual, beq_actual,rtype, lb_actual,ub_actual,options);%, options);
                    end
                    this.COperUninodal(j) = fval;
                    tiempo = etime(clock,t_inicio_for);
                    disp(['Coper sin restricciones escenario ' num2str(escenario) ' etapa ' num2str(etapa) ':' num2str(fval) '. DT: ' num2str(tiempo)])
                end
            end            
            tiempo = etime(clock,t_inicio);
            disp(['Tiempo total: ' num2str(tiempo)])            
        end
        
        function [Aeq_oper_sr, beq_oper_sr] = entrega_rest_be_uninodal_por_caso(this, escenario, etapa, varargin)
            % varargin indica la subetapa si se considera
            % dimensiones
            
            cant_variables_decision = size(this.Aeq,2);
            if nargin == 3
                subetapa = 0;
                cant_po = this.iCantPuntosOperacion;
                Aeq_oper_sr = sparse(cant_po, cant_variables_decision);
                beq_oper_sr = zeros(cant_po,1);
            else
                subetapa = varargin{1};
                cant_po = length(find(this.RelSubetapasPO == subetapa));
                Aeq_oper_sr = sparse(cant_po, cant_variables_decision);
                beq_oper_sr = zeros(cant_po,1);
            end

            subestaciones = this.pSEP.Subestaciones;
            se_proyectadas = this.pAdmProy.entrega_subestaciones_proyectadas(escenario);            
            %se_proyectadas = [];
            for ii = 1:length(se_proyectadas)
                if se_proyectadas(ii).entrega_etapa_entrada(escenario) <= etapa
                    subestaciones = [subestaciones; se_proyectadas(ii)];
                end
            end

            for se = 1:length(subestaciones)
                if subetapa == 0
                    id_be_desde = subestaciones(se).entrega_restriccion_balance_energia_desde(escenario, etapa);
                    id_be_hasta = id_be_desde + cant_po - 1;
                else
                    id_rel_desde = find(this.RelSubetapasPO == subetapa, 1,'first');
                    id_rel_hasta = find(this.RelSubetapasPO == subetapa, 1,'last');
                    id_be_desde = subestaciones(se).entrega_restriccion_balance_energia_desde(escenario, etapa) + id_rel_desde - 1;
                    id_be_hasta = id_be_desde + id_rel_hasta - id_rel_desde ;
                end
                Aeq_oper_sr = Aeq_oper_sr + this.Aeq(id_be_desde:id_be_hasta,:);
                beq_oper_sr = beq_oper_sr + this.beq(id_be_desde:id_be_hasta);        
            end
        end
        
        function [Aeq_oper_sr, beq_oper_sr] = escribe_restricciones_balance_energetico_uninodal(this)
            indice_be = 0;
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            dec_redondeo = this.pParOpt.DecimalesRedondeo;
            % dimensiones
            [~,cant_variables_decision] = size(this.Aeq);
            
            cant_restricciones = this.iCantEscenarios*this.iCantEtapas*this.iCantPuntosOperacion;
            Aeq_oper_sr = zeros(cant_restricciones, cant_variables_decision);
            beq_oper_sr = zeros(cant_restricciones,1);
            for escenario = 1:this.iCantEscenarios
                for etapa = 1:this.iCantEtapas
                    % sólo balance de energía uninodal
                    indice_eq_desde = indice_be + 1;
                    indice_eq_hasta = indice_eq_desde + this.iCantPuntosOperacion - 1;                    
                    indice_be = indice_eq_hasta;
                    
                    subestaciones = this.pSEP.Subestaciones;
                    se_proyectadas = this.pAdmProy.entrega_subestaciones_proyectadas(escenario);            
                    for ii = 1:length(se_proyectadas)
                        if se_proyectadas(ii).EtapaEntrada <= etapa
                            subestaciones = [subestaciones; se_proyectadas(ii)];
                        end
                    end
            
                    for se = 1:length(subestaciones)
                        %generadores existentes
                        generadores = [];
                        gen_desp = this.pSEP.Subestaciones(se).entrega_generadores_despachables();
                        for ii = 1:length(gen_desp)
                            if gen_desp(ii).entrega_varopt_operacion('P', escenario, etapa) ~= 0
                                generadores = [generadores; gen_desp(ii)];
                            end
                        end
                        gen_proy = this.pAdmProy.entrega_generadores_despachables_proyectados(escenario);
                        for ii = 1:length(gen_proy)
                            if gen_proy(ii).entrega_se == this.pSEP.Subestaciones(se) && gen_proy(ii).entrega_varopt_operacion('P', escenario, etapa) ~= 0
                                generadores = [generadores; gen_proy(ii)];
                            end
                        end
                
                        for j = 1:length(generadores)
                            indice_gen_desde = generadores(j).entrega_varopt_operacion('P', escenario, etapa);
                            indice_gen_hasta = indice_gen_desde + this.iCantPuntosOperacion - 1;

                            Aeq_oper_sr(indice_eq_desde:indice_eq_hasta,indice_gen_desde:indice_gen_hasta) = diag(ones(this.iCantPuntosOperacion,1)); 
                        end
                
                        %consumo residual
                        consumo_residual = zeros(1, this.iCantPuntosOperacion);
                        consumos = [];
                        % existentes
                        for ii = 1:length(this.pSEP.Subestaciones(se).Consumos)
                            if this.pSEP.Subestaciones(se).Consumos(ii).EtapaSalida == 0 || ...
                               (this.pSEP.Subestaciones(se).Consumos(ii).EtapaSalida > etapa)
                                consumos = [consumos; this.pSEP.Subestaciones(se).Consumos(ii)];
                            end
                        end
                        % proyectados
                        con_proy = this.pAdmProy.entrega_consumos_proyectados(escenario);
                        for ii = 1:length(con_proy)
                            if con_proy(ii).EtapaEntrada <= etapa && ...
                                    con_proy(ii).EtapaSalida > etapa && ...
                                    con_proy(ii).entrega_se() == this.pSEP.Subestaciones(se)
                                consumos = [consumos; con_proy(ii)];
                            end
                        end
                
                        for j = 1:length(consumos)
                            indice_perfil = consumos(j).entrega_indice_adm_escenario_perfil_p();
                            perfil = this.pAdmSc.entrega_perfil_consumo(indice_perfil);
                            indice_capacidad = consumos(j).entrega_indice_adm_escenario_capacidad(escenario);
                            capacidad = this.pAdmSc.entrega_capacidad_consumo(indice_capacidad, etapa);

                            consumo_residual = consumo_residual + capacidad*perfil/sbase;
                        end
                
                        % se resta la inyección de generadores RES
                        % se asume que generadores res no salen de operación
                        gen_res = this.pSEP.Subestaciones(se).entrega_generadores_res();
                        gen_proy = this.pAdmProy.entrega_generadores_ernc_proyectados(escenario);
                        for ii = 1:length(gen_proy)
                            if gen_proy(ii).entrega_se == this.pSEP.Subestaciones(se) && gen_proy(ii).EtapaEntrada <= etapa
                                gen_res = [gen_res; gen_proy(ii)];
                            end
                        end

                        for j = 1:length(gen_res)
                            indice_perfil = gen_res(j).entrega_indice_adm_escenario_perfil_ernc();
                            perfil_ernc = this.pAdmSc.entrega_perfil_ernc(indice_perfil);
                            if gen_res(j).entrega_evolucion_capacidad_a_futuro()
                                indice_capacidad = gen_res(j).entrega_indice_adm_escenario_capacidad(escenario);
                                capacidad = this.pAdmSc.entrega_capacidad_generador(indice_capacidad, etapa);
                            else
                                capacidad = gen_res(j).entrega_pmax();
                            end

                            consumo_residual = consumo_residual - capacidad*perfil_ernc/sbase;
                        end
                
                        beq_oper_sr(indice_eq_desde:indice_eq_hasta,1) = beq_oper_sr(indice_eq_desde:indice_eq_hasta,1) + round(consumo_residual',dec_redondeo);

                        %ENS
                        if this.pParOpt.considera_desprendimiento_carga()
                            for j = 1:length(consumos)
                                indice_consumo_desde = consumos(j).entrega_varopt_operacion('P', escenario, etapa);
                                if indice_consumo_desde == 0
                                    continue
                                end
                                indice_consumo_hasta = indice_consumo_desde + this.iCantPuntosOperacion - 1;

                                Aeq_oper_sr(indice_eq_desde:indice_eq_hasta,indice_consumo_desde:indice_consumo_hasta) = diag(ones(this.iCantPuntosOperacion,1));
                            end
                        end
                
                        % Recorte RES.
                        if this.pParOpt.considera_recorte_res()
                            for j = 1:length(gen_res)
                                indice_generador_desde = gen_res(j).entrega_varopt_operacion('P', escenario, etapa);
                                if indice_generador_desde == 0
                                    continue
                                end

                                indice_generador_hasta = indice_generador_desde + this.iCantPuntosOperacion - 1;

                                Aeq_oper_sr(indice_eq_desde:indice_eq_hasta,indice_generador_desde:indice_generador_hasta) = -1*diag(ones(this.iCantPuntosOperacion,1));
                            end
                        end
                    end
                end
            end
        end
        
        function id_proyectos = entrega_proyectos_corredor(this, nombre_se_1, nombre_se_2, id_proy_posibles)
            id_proyectos = [];
            for i = 1:length(id_proy_posibles)
                proy = this.pAdmProy.entrega_proyecto(id_proy_posibles(i));
                if strcmp(proy.entrega_tipo_proyecto(), 'AV')
                    % determina si se conectan las subestaciones
                    % correspondientes
                    
                    se_1_red_orig = cSubestacion.empty;
                    se_2_red_orig = cSubestacion.empty;
                    cantidad_grupos_conectividad = proy.entrega_cantidad_grupos_conectividad();
                    
                    for no_grupo = 1:cantidad_grupos_conectividad
                        proy_con = proy.entrega_grupo_proyectos_conectividad(no_grupo);
                        if strcmp(proy_con(1).entrega_tipo_proyecto(), 'AS')
                            continue;
                        end
                        if proy_con(1).Elemento(1).entrega_se1().Existente
                            se_existente = proy_con(1).Elemento(1).entrega_se1();
                        elseif proy_con(1).Elemento(1).entrega_se2().Existente
                            se_existente = proy_con(1).Elemento(1).entrega_se2();
                        else
                            error = MException('cOptMILP:entrega_proyectos_corredor',...
                                ['Para proyecto ' num2str(proy) ': SE existente no pudo ser identificada. Error en datos de entrada']);
                            throw(error)
                        end
                            
                        if isempty(se_1_red_orig)
                            se_1_red_orig = se_existente;
                        elseif isempty(se_2_red_orig)
                            se_2_red_orig = se_existente;
                        else
                            error = MException('cOptMILP:entrega_proyectos_corredor','Todas las subestaciones existentes fueron identificadas. Error de programacion');
                            throw(error)                            
                        end
                    end
                    if (strcmp(se_1_red_orig.entrega_nombre(), nombre_se_1) && strcmp(se_2_red_orig.entrega_nombre(), nombre_se_2)) || ...
                       (strcmp(se_2_red_orig.entrega_nombre(), nombre_se_1) && strcmp(se_1_red_orig.entrega_nombre(), nombre_se_2))
                        id_proyectos = [id_proyectos id_proy_posibles(i)];
                    end
                elseif strcmp(proy.entrega_tipo_proyecto(), 'CC') || ...
                   strcmp(proy.entrega_tipo_proyecto(), 'CS')
                    if strcmp(proy.Accion(end),'A') ~= 1
                        error = MException('cOptMILP:entrega_proyectos_corredor','Accion final de proyecto de cambio de estado no es agrega elemento');
                        throw(error)
                    end                        
               
                    elred = proy.Elemento(end);
                    nombre_se_1_proy = elred.entrega_se1().entrega_nombre();
                    nombre_se_2_proy = elred.entrega_se2().entrega_nombre();
                    if (strcmp(nombre_se_1_proy, nombre_se_1) && strcmp(nombre_se_2_proy, nombre_se_2)) || ...
                       (strcmp(nombre_se_2_proy, nombre_se_1) && strcmp(nombre_se_1_proy, nombre_se_2))
                        id_proyectos = [id_proyectos id_proy_posibles(i)];
                    end
                elseif strcmp(proy.entrega_tipo_proyecto(), 'AL') || ...
                       strcmp(proy.entrega_tipo_proyecto(), 'AT')
                   
                    elred = proy.Elemento(end);
                    if elred.entrega_indice_paralelo() == 1
                        % corredor no tiene líneas aún. Se agrega
                        nombre_se_1_proy = elred.entrega_se1().entrega_nombre();
                        nombre_se_2_proy = elred.entrega_se2().entrega_nombre();
                        if (strcmp(nombre_se_1_proy, nombre_se_1) && strcmp(nombre_se_2_proy, nombre_se_2)) || ...
                           (strcmp(nombre_se_2_proy, nombre_se_1) && strcmp(nombre_se_1_proy, nombre_se_2))
                            id_proyectos = [id_proyectos id_proy_posibles(i)];
                        end                        
                    end
                end
            end
        end

        function id_proyectos = entrega_proyectos_corredor_vu(this, id_se_1, id_se_2, id_proy_posibles)
            % se entregan los proyectos de VU que conectan al menos una de
            % las subestaciones involucradas
            
            id_proyectos = [];
            for i = 1:length(id_proy_posibles)
                proy = this.pAdmProy.entrega_proyecto(id_proy_posibles(i));
                if strcmp(proy.entrega_tipo_proyecto(), 'AV')
                    % determina si se conectan otras subestaciones a las
                    % indicadas
                    
                    se_1_vu = proy.Elemento(end).entrega_se1();
                    se_2_vu  = proy.Elemento(end).entrega_se2();
                    
                    if (se_1_vu.entrega_id() == id_se_1 && se_2_vu.entrega_id() == id_se_2) || ...
                       (se_2_vu.entrega_id() == id_se_1 && se_1_vu.entrega_id() == id_se_2)
                        id_proyectos = [id_proyectos id_proy_posibles(i)];
                    end
                end
            end
            if length(id_proyectos) > 1
                error = MException('cOptMILP:entrega_proyectos_corredor_vu','Error de programacion. Se encontró más de un proyecto VU para el bus proyectado');
                throw(error)
            end
            if isempty(id_proyectos)
                error = MException('cOptMILP:entrega_proyectos_corredor_vu','Error de programacion. No se encontraron proyectos de VU para el bus proyectado');
                throw(error)
            end
        end

        function id_proyectos = entrega_proyectos_trafo_vu(this, id_se_1, id_se_2, id_proy_posibles)
            % se entregan los proyectos de VU que conectan al menos una de
            % las subestaciones involucradas
            
            for i = 1:length(id_proy_posibles)
                proy = this.pAdmProy.entrega_proyecto(id_proy_posibles(i));
                if strcmp(proy.entrega_tipo_proyecto(), 'AV')
                    % determina si se conectan otras subestaciones a las
                    % indicadas
                    
                    cantidad_grupos_conectividad = proy.entrega_cantidad_grupos_conectividad();                    
                    for no_grupo = 1:cantidad_grupos_conectividad
                        proy_con = proy.entrega_grupo_proyectos_conectividad(no_grupo);
                        if strcmp(proy_con(1).entrega_tipo_proyecto(), 'AS')
                            continue;
                        end
                        se1_vu = proy_con(1).Elemento(1).entrega_se1().entrega_id();
                        se2_vu = proy_con(1).Elemento(1).entrega_se2().entrega_id();
                        if  (se1_vu == id_se_1 && se2_vu == id_se_2) || ...
                            (se2_vu == id_se_1 && se1_vu == id_se_2)
                            id_proyectos = proy_con(1).entrega_indice();
                            return
                        end
                    end                                        
                end
            end
            error = MException('cOptMILP:entrega_proyectos_trafo_vu','Error de programacion. Trafo VU no se encontró');
            throw(error)
            
        end
        
        function posicion = entrega_posicion_subestacion(this, nombre_se, subestaciones)
            for i = 1:length(subestaciones)
                if strcmp(subestaciones(i).entrega_nombre(), nombre_se)
                    posicion = i;
                    return
                end
            end
            error = MException('cOptMILP:entrega_posicion_subestacion','Subestacion no pudo ser encontrada');
            throw(error)
            
        end
        
        function se_adyacente = entrega_subestacion_adyacente(this, se_nueva)
            proyectos = this.pAdmProy.entrega_proyectos();
            for i = 1:length(proyectos)
                if strcmp(proyectos(i).entrega_tipo_proyecto(), 'AV')
                    cantidad_grupos_conectividad = proyectos(i).entrega_cantidad_grupos_conectividad();
                    for no_grupo = 1:cantidad_grupos_conectividad
                        proy_con = proyectos(i).entrega_grupo_proyectos_conectividad(no_grupo);
                        if strcmp(proy_con(1).entrega_tipo_proyecto(), 'AS')
                            continue;
                        end
                        se1_vu = proy_con(1).Elemento(1).entrega_se1();
                        se2_vu = proy_con(1).Elemento(1).entrega_se2();
                        if  se1_vu == se_nueva
                            if ~se2_vu.Existente                                
                                error = MException('cOptMILP:entrega_subestacion_adyacente','Subestacion adyacente no existe en sep');
                                throw(error)
                            end
                            se_adyacente = se2_vu;
                            return
                        elseif se2_vu == se_nueva
                            if ~se1_vu.Existente                                
                                error = MException('cOptMILP:entrega_subestacion_adyacente','Subestacion adyacente no existe en sep');
                                throw(error)
                            end
                            se_adyacente = se1_vu;
                            return
                        end
                    end
                end
            end
            error = MException('cOptMILP:entrega_subestacion_adyacente','No se pudo encontrar subestacion adyacente');
            throw(error)
            
        end
        
        function inserta_solucion_a_evaluar(this, sol_a_evaluar)
            this.ExisteSolucionAEvaluar = true;
            this.SolucionAEvaluar = sol_a_evaluar;
        end

        function agrega_valores_matriz_igualdad(this, cantidad,filas,columnas,valores)
            nz_desde = this.iNZEqActual + 1;
            nz_hasta = this.iNZEqActual + cantidad;
            this.iNZEqActual = nz_hasta;
            this.FilasEq(nz_desde:nz_hasta,1) = filas;
            this.ColEq(nz_desde:nz_hasta,1) = columnas;
            this.ValEq(nz_desde:nz_hasta,1) = valores;
        end
        
        function agrega_valores_matriz_desigualdad(this, cantidad,filas,columnas,valores)
            nz_desde = this.iNZIneqActual + 1;
            nz_hasta = this.iNZIneqActual + cantidad;
            this.iNZIneqActual = nz_hasta;
            this.FilasIneq(nz_desde:nz_hasta,1) = filas;
            this.ColIneq(nz_desde:nz_hasta,1) = columnas;
            this.ValIneq(nz_desde:nz_hasta,1) = valores;
        end

		function nombre = entrega_nombre_variables_expansion(this, proy, etapa_desde, etapa_hasta, escenario)
			proy = this.VarExpansion(i);
            etapa = (etapa_desde:1:etapa_hasta)';
            tipo_proyecto = proy.entrega_tipo_proyecto();
            cap_inicial = proy.entrega_capacidad_inicial();
            cap_final = proy.entrega_capacidad_final();
            if strcmp(tipo_proyecto, 'AL')
				id_ubic_1 = proy.Elemento(1).entrega_se1().entrega_id();
                id_ubic_2 = proy.Elemento(1).entrega_se2().entrega_id();
                id_par = proy.Elemento(1).entrega_indice_paralelo();
                tipo_cond = proy.Elemento(1).entrega_tipo_conductor();
                compensacion = proy.Elemento(1).entrega_compensacion_serie()*100;
                vn = proy.Elemento(1).entrega_se1().entrega_vn();
                nombre = strcat('Pr_', num2str(i), '_AL_', num2str(id_par), '_C', num2str(tipo_cond), '_CS', num2str(compensacion), '_V', num2str(vn), ...
					'_B', num2str(id_ubic_1), '_', num2str(id_ubic_2), '_E', num2str(etapa,'%02d'), '_S', num2str(escenario));
            elseif strcmp(tipo_proyecto, 'AB')
				id_ubic = proy.Elemento(1).entrega_se().entrega_id();
                id_par = proy.Elemento(1).entrega_indice_paralelo();
                tipo_bat = proy.Elemento(1).entrega_tipo_bateria();
                vn = proy.Elemento(1).entrega_se().entrega_vn();
                nombre = strcat('Pr_', num2str(i), '_AB_', num2str(id_par), '_C', num2str(tipo_bat), '_V', num2str(vn), ...
					'_B', num2str(id_ubic), '_E', num2str(etapa, '%02d'), '_S', num2str(escenario));

			elseif strcmp(tipo_proyecto, 'CC')
				%Cambio conductor
                id_ubic_1 = proy.Elemento(1).entrega_se1().entrega_ubicacion();
                id_ubic_2 = proy.Elemento(1).entrega_se2().entrega_ubicacion();
                id_par = length(proy.Elemento)/2;
                compensacion = proy.Elemento(end).entrega_compensacion_serie()*100;
                vn = proy.Elemento(end).entrega_se1().entrega_vn();
				nombre = strcat('Pr_', num2str(i), '_CC_', num2str(id_par), '_', cap_inicial, '_', cap_final, '_CS', num2str(compensacion), '_V', num2str(vn), ...
					'_B', num2str(id_ubic_1), '_', num2str(id_ubic_2), '_E', num2str(etapa,'%02d'), '_S', num2str(escenario));
			elseif strcmp(tipo_proyecto, 'AV')
				id_ubic_1 = proy.Elemento(1).entrega_se1().entrega_ubicacion();
                id_ubic_2 = proy.Elemento(1).entrega_se2().entrega_ubicacion();
				id_par = length(proy.Elemento)/2;
                tipo_conductor = proy.Elemento(1).entrega_tipo_conductor();
				nombre = strcat('Pr_', num2str(i), '_AV_', num2str(id_par), '_', cap_inicial, '_', cap_final, '_C', num2str(tipo_conductor), ...
					'_B', num2str(id_ubic_1), '_', num2str(id_ubic_2), '_E', num2str(etapa,'%02d'), '_S', num2str(escenario));
			elseif strcmp(tipo_proyecto, 'CS')
				%Compensación serie
                id_ubic_1 = proy.Elemento(1).entrega_se1().entrega_ubicacion();
                id_ubic_2 = proy.Elemento(1).entrega_se2().entrega_ubicacion();
                id_par = length(proy.Elemento)/2;
                tipo_conductor = proy.Elemento(end).entrega_tipo_conductor();
                vn = proy.Elemento(end).entrega_se1().entrega_vn();
				nombre = strcat('Pr_', num2str(i), '_CS_', num2str(id_par), '_', cap_inicial, '_', cap_final, '_C', num2str(tipo_conductor), '_V', num2str(vn), ...
					'_B', num2str(id_ubic_1), '_', num2str(id_ubic_2), '_E', num2str(etapa,'%02d'), '_S', num2str(escenario));
			elseif strcmp(tipo_proyecto, 'AT')
				id_ubic_1 = proy.Elemento(1).entrega_se1().entrega_ubicacion();
                id_par = proy.Elemento(1).entrega_indice_paralelo();
                tipo_trafo = proy.Elemento(1).entrega_tipo_trafo();
                sr = proy.Elemento(1).entrega_sr();
                vat = proy.Elemento(1).entrega_se1().entrega_vn();
                vbt = proy.Elemento(1).entrega_se2().entrega_vn();
				nombre = strcat('Pr_', num2str(i), '_AT_', num2str(id_par), '_T', num2str(tipo_trafo), '_Sr_', num2str(sr), '_V_', num2str(vat), '_', num2str(vbt), ...
					'_B', num2str(id_ubic_1), '_E', num2str(etapa,'%02d'), '_S', num2str(escenario));
			elseif strcmp(tipo_proyecto, 'AS')
				id_ubic = proy.Elemento(1).entrega_ubicacion();
				vn = proy.Elemento(1).entrega_vn();
				nombre = strcat('Pr_', num2str(i), '_AS_B_', num2str(id_ubic), '_V_', num2str(vn), '_E', num2str(etapa,'%02d'), '_S', num2str(escenario));
			end
		end		
    end
end