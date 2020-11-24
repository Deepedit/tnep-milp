classdef cPlanExpansion < handle
    % Clase que representa un plan de expansión
    % En los planes de expansión se guarda sólo el índice del proyecto (en
    % este caso líneas de transmisión). Para implementar el plan es
    % necesario la clase cAdministradorProyectos (contiene línea exacta) y
    % el sistema eléctrico de potencia (clase cSistemaElectricoPotencia)
    
    properties
        %propiedades generales
        NroPlan
        Iteracion = 0 % guarda el no iteración cuando fue generado
        BusquedaLocal = false % indica si fue generado con busqueda local o no
        EstrategiaBusquedaLocal = 0  % Nro de estrategia de busqueda local que se utilizó para generar el plan
        PlanBase = 0  % guarda el plan base utilizado para búsqueda local
        
        % plan de expansion. Contiene sólo el índice del proyecto
        % Plan(nro_etapa).Proyectos = [indice_proyecto1 ... ]
        % está la opción de ingresar nombres también
        
        Plan
        
        NombresDisponibles = false;
        
        %Resultados operacion
        ResultadoEvaluacion = struct('Existe', false, ...
                                     'Valido', false,...
                                     'CostoGeneracion',0,...
                                     'CostoENS', 0,...
                                     'CostoRecorteRES', 0,...
                                     'CostoOperacion', 0, ...
                                     'LineasFlujoMaximo', [], ...
                                     'TrafosFlujoMaximo', [], ...
                                     'LineasPocoUso', [], ...
                                     'TrafosPocoUso', []);
                                 
        % resultados parciales y globales
        CantidadReparaciones = 0
        CantidadVecesDesechadoEtapa = 0
        CantidadVecesDesechadoTotal = 0
        Valido = false
        CInv
        CInvTActual
        CInvTotal
        
        COper
        COperTActual
        COperTotal

        CGen % costos de generación
        CGenTActual
        CGenTotal
            
        CENS  % costos de energía no suministrada
        CENSTActual
        CENSTotal
    
        CRecorteRES
        CRecorteRESTActual
        CRecorteRESTotal
        
        Totex
        TotexTActual
        TotexTotal 
        
        % SEP Original, actual y etapa actual. Para mejorar performance del programa
        SEP_original = cSistemaElectricoPotencia.empty
        SEP_actual = cSistemaElectricoPotencia.empty
        Etapa_sep_actual = 0
    end
    
    methods
        function this = cPlanExpansion(nro_plan)
            this.NroPlan = nro_plan;
            %plan = zeros(nro_etapas,1);
            this.Plan = [];
        end

        function copia = crea_copia(this, nro_plan_copia)
            copia = cPlanExpansion(nro_plan_copia);
            copia.Plan = this.Plan;
            copia.NombresDisponibles = this.NombresDisponibles;
            copia.ResultadoEvaluacion = this.ResultadoEvaluacion;
            copia.Valido = this.Valido;
            copia.CInv = this.CInv;
            copia.CInvTActual = this.CInvTActual;
            copia.CInvTotal = this.CInvTotal;
        
        
            copia.COper = this.COper;
            copia.COperTActual = this.COperTActual;
            copia.COperTotal = this.COperTotal;
        
            copia.Totex = this.Totex;
            copia.TotexTActual = this.TotexTActual;
            copia.TotexTotal = this.TotexTotal;
        end
        
        function estructura = entrega_estructura_costos(this)
            estructura.CInv = this.CInv;
            estructura.CInvTActual = this.CInvTActual;
            estructura.CInvTotal = this.CInvTotal;

            estructura.CGen = this.CGen;
            estructura.CGenTActual = this.CGenTActual;
            estructura.CGenTotal = this.CGenTotal;
            
            estructura.CENS = this.CENS; 
            estructura.CENSTActual = this.CENSTActual;
            estructura.CENSTotal = this.CENSTotal;
    
            estructura.CRecorteRES = this.CRecorteRES;
            estructura.CRecorteRESTActual = this.CRecorteRESTActual;
            estructura.CRecorteRESTotal = this.CRecorteRESTotal;
            
            estructura.COper = this.COper;
            estructura.COperTActual = this.COperTActual;
            estructura.COperTotal = this.COperTotal;
        
            estructura.Totex = this.Totex;
            estructura.TotexTActual = this.TotexTActual;
            estructura.TotexTotal = this.TotexTotal;
        end
        
        function inserta_estructura_costos(this, estructura)
            this.CInv = estructura.CInv;
            this.CInvTActual = estructura.CInvTActual;
            this.CInvTotal = estructura.CInvTotal;
        
            this.CGen = estructura.CGen;
            this.CGenTActual = estructura.CGenTActual;
            this.CGenTotal = estructura.CGenTotal;
            
            this.CENS = estructura.CENS; 
            this.CENSTActual = estructura.CENSTActual;
            this.CENSTotal = estructura.CENSTotal;
    
            this.CRecorteRES = estructura.CRecorteRES;
            this.CRecorteRESTActual = estructura.CRecorteRESTActual;
            this.CRecorteRESTotal = estructura.CRecorteRESTotal;

            this.COper = estructura.COper;
            this.COperTActual = estructura.COperTActual;
            this.COperTotal = estructura.COperTotal;
        
            this.Totex = estructura.Totex;
            this.TotexTActual = estructura.TotexTActual;
            this.TotexTotal = estructura.TotexTotal;
        end
        
        function cantidad = cantidad_acumulada_proyectos(this, nro_etapa)
            cantidad = 0;
            if nargin > 1
                tope = min(length(this.Plan), nro_etapa);
            else
                tope = length(this.Plan);
            end
            for i=1:tope
                cantidad = cantidad + length(this.Plan(i).Proyectos);
            end
        end
        
        function agrega_proyecto(this, nro_etapa, indice_proyecto, varargin)
            %varargin indica el nombre del proyecto
            if length(this.Plan) < nro_etapa
                error = MException('cPlanExpansion:agrega_proyecto',['Error de programación. Plan aún no inicializado en etapa ' num2str(nro_etapa)]);
                throw(error)
            end
            % verifica que proyecto no esté en plan
            for i = 1:length(this.Plan)
                if any(this.Plan(i).Proyectos == indice_proyecto)
%disp(['Error de programación. Proyecto ' num2str(indice_proyecto) ' ya se encuentra incluido en plan'])
                   error = MException('cPlanExpansion:agrega_proyecto',['Error de programación. Proyecto ' num2str(indice_proyecto) ' ya se encuentra incluido en plan']);
                   throw(error)
                end
            end
            
            this.Plan(nro_etapa).Proyectos(end+1) = indice_proyecto;

            if nargin > 3
            	nombre_proyecto = varargin{1};
                if length(this.Plan(nro_etapa).Proyectos) == 1
                	this.Plan(nro_etapa).Nombres{1} = nombre_proyecto;
                else
                	this.Plan(nro_etapa).Nombres{end+1} = nombre_proyecto;
                end
                this.NombresDisponibles = true;
            end
        end
        
        function inserta_proyectos_etapa(this, nro_etapa, proyectos)
            this.Plan(nro_etapa).Proyectos = proyectos;
        end
        
        function inicializa_etapa(this, nro_etapa)
            this.Plan(nro_etapa).Creado = true;
            this.Plan(nro_etapa).Proyectos = [];
        end
        
        function desecha_plan(this, varargin)
            this.CantidadReparaciones = 0;
            if nargin < 2
                this.Plan = [];
                this.CantidadVecesDesechadoTotal = this.CantidadVecesDesechadoTotal +1;
                this.CantidadVecesDesechadoEtapa = 0;
            else
                nro_etapa = varargin{1};
                if length(this.Plan) == nro_etapa
                    this.Plan = this.Plan(1:end-1);
                    this.CantidadVecesDesechadoEtapa = this.CantidadVecesDesechadoEtapa + 1;
                else
                    error = MException('cPlanExpansion:desecha_plan','nro etapa no coincide con último plan guardado');
                    throw(error)
                end
            end
            %this.reinicia_sep_actual();
            this.ResultadoEvaluacion = [];
        end
        
        function inicializa_nueva_etapa(this)
            this.CantidadReparaciones = 0;
            this.CantidadVecesDesechadoEtapa = 0;
        end
        
        function inserta_evaluacion_etapa(this, nro_etapa, evaluacion)
            this.ResultadoEvaluacion(nro_etapa) = evaluacion;
        end
        
        function inserta_evaluacion(this, evaluacion)
            this.ResultadoEvaluacion = evaluacion;
        end
        
        function evaluacion = entrega_evaluacion(this, varargin)
            %varargin indica si es para una etapa en particular
            if nargin > 1
                nro_etapa = varargin{1};
                
                if length(this.ResultadoEvaluacion) >= nro_etapa
                    evaluacion = this.ResultadoEvaluacion(nro_etapa);
                else
                    evaluacion = struct('Existe', false, ...
                                        'Valido', false,...
                                        'CostoGeneracion',0,...
                                        'CostoENS', 0,...
                                        'CostoRecorteRES', 0,...
                                        'CostoOperacion', 0, ...
                                        'LineasFlujoMaximo', [], ...
                                        'LineasFlujoMaximo', [], ...
                                        'TrafosFlujoMaximo', [], ...
                                        'LineasPocoUso', [], ...
                                        'TrafosPocoUso', []);
                end
            else
                evaluacion = this.ResultadoEvaluacion;
            end
        end
        
        function imprime_evaluacion(this)
            disp('----------------------');
            text = ['Imprime evaluacion de Plan ' num2str(this.NroPlan)];
            disp(text);
            for etapa = 1:length(this.ResultadoEvaluacion)
                text = sprintf('%30s %5s','Etapa:',num2str(etapa));
                disp(text);
                text = sprintf('%30s %5s','   Plan es válido: ', num2str(this.ResultadoEvaluacion(etapa).Valido));
                disp(text);
                text = sprintf('%30s %5s','   Costo generacion: ', num2str(this.ResultadoEvaluacion(etapa).CostoGeneracion));  
                disp(text);
                text = sprintf('%30s %5s','   Costo ENS: ', num2str(this.ResultadoEvaluacion(etapa).CostoENS));  
                disp(text);
                text = sprintf('%30s %5s','   Costo Recorte RES: ', num2str(this.ResultadoEvaluacion(etapa).CostoRecorteRES));  
                disp(text);
                text = sprintf('%30s %5s','   Costo Operacion: ', num2str(this.ResultadoEvaluacion(etapa).CostoOperacion));  
                disp(text);                
            end
        end
        
        function existe = proyecto_existe(this, indice_proyecto, varargin)
            %varargin indica el número de etapa
            existe = false;
            if nargin >2
                nro_etapa = varargin{1};
                if length(this.Plan) < nro_etapa
                    error = MException('cPlanExpansion:proyecto_existe','Error de programación. Nro etapa es mayor a dimensión del plan');
                    throw(error)
                end
                if ~isempty(find(this.Plan(nro_etapa).Proyectos == indice_proyecto, 1))
                    existe = true;
                    return
                end
            else
                for i = 1:length(this.Plan)
                    if ~isempty(find(this.Plan(i).Proyectos == indice_proyecto, 1))
                        existe = true;
                        return
                    end
                end
            end
        end

        function id_proy_existentes = algun_proyecto_existe_a_partir_de_etapa(this, indice_proyectos, etapa_inicial)
            % id proy existente indica el proyecto dentro del grupo que
            % existe en el plan. Si id = 0, entonces ningún proyecto existe
            id_proy_existentes = 0;
            if length(this.Plan) < etapa_inicial
                % no hay error porque función viene de administrador de
                % proyectos, que no "sabe" la cantidad de etapas"
                % simplemente retorna 0
                return
                %error = MException('cPlanExpansion:algun_proyecto_existe_a_partir_de_etapa','Error de programación. Nro etapa es mayor a dimensión del plan');
                %throw(error)
            end
            
            for i = etapa_inicial:length(this.Plan)
                proy_existente = indice_proyectos(ismember(indice_proyectos,this.Plan(i).Proyectos));
                if ~isempty(proy_existente)
                    id_proy_existentes = proy_existente;
                    return
                end
            end
        end

        function [id_proy_existentes, etapas] = entrega_proyectos_implementados_de_lista_a_partir_de_etapa(this, indice_proyectos, etapa_inicial)
            % id proy existente indica el proyecto dentro del grupo que
            % existe en el plan. Si id = 0, entonces ningún proyecto existe
            id_proy_existentes = [];
            etapas = [];
            if length(this.Plan) < etapa_inicial
                % plan aún no ha sido implementado en la etapa indicada
                % simplemente retorna 0
                return
                %error = MException('cPlanExpansion:algun_proyecto_existe_a_partir_de_etapa','Error de programación. Nro etapa es mayor a dimensión del plan');
                %throw(error)
            end
            
            for i = etapa_inicial:length(this.Plan)
                proy_existentes = indice_proyectos(ismember(indice_proyectos,this.Plan(i).Proyectos));
                if ~isempty(proy_existentes)
                    id_proy_existentes = [id_proy_existentes proy_existentes];
                    etapas = [etapas i*ones(1,length(proy_existentes))];
                end
            end
        end

        function id_proy_implementados = entrega_proyectos_implementados_de_lista_en_etapa(this, indice_proyectos, etapa)
            % id proy existente indica el proyecto dentro del grupo que
            % existe en el plan. Si id = 0, entonces ningún proyecto existe
            id_proy_implementados = ismember(indice_proyectos,this.Plan(etapa).Proyectos);
        end
        
        function etapas = entrega_etapas_implementacion_proyectos_de_lista(this, proyectos, varargin)
            % varargin indica etapa inicial
            % si proyecto de lista no ha sido implementado, etapa = 0
            if nargin > 2
                etapa_inicial = varargin{1};
            else
                etapa_inicial = 1;
            end
            etapas = zeros(1,length(proyectos));
            if length(this.Plan) < etapa_inicial
                return
            end
            for i = etapa_inicial:length(this.Plan)
                id_existente = ismember(proyectos, this.Plan(i).Proyectos);
                etapas(id_existente) = i;
            end
        end
        
        function [id_proy, nro_etapa] = entrega_ultimo_proyecto_realizado_de_grupo(this, id_proyectos)
            for etapa = length(this.Plan):-1:1
                id = find(ismember(this.Plan(etapa).Proyectos, id_proyectos),1,'last');
                if ~isempty(id)
                    id_proy = this.Plan(etapa).Proyectos(id);
                    nro_etapa = etapa;
                    return
                end
            end
            id_proy = 0;
            nro_etapa = 0;
        end

        function id_proy = entrega_primer_proyecto_realizado_de_grupo_y_etapa(this, id_proyectos, etapa)
            try
                id_proy = this.Plan(etapa).Proyectos(find(ismember(this.Plan(etapa).Proyectos, id_proyectos),1,'first'));
            catch
                warning('Plan de expansión. Ocurre un error'); 
                id_proy = 0;
            end
        end
        
        function id_proy = entrega_ultimo_proyecto_realizado_de_grupo_y_etapa(this, id_proyectos, etapa)
            id_proy = this.Plan(etapa).Proyectos(find(ismember(this.Plan(etapa).Proyectos, id_proyectos),1,'last'));
        end
        
        function existe = proyecto_existe_acumulado(this, indice_proyecto, nro_etapa_final)
            existe = false;
            if length(this.Plan) < nro_etapa_final
                error = MException('cPlanExpansion:proyecto_existe_acumulado','Error de programación. Nro etapa es mayor a dimensión del plan');
                throw(error)
            end
            for i = 1:nro_etapa_final
                if ~isempty(find(this.Plan(i).Proyectos == indice_proyecto, 1))
                	existe = true;
                    return
                end
            end
        end
        
        function etapa = entrega_etapa_proyecto(this, indice_proyecto, varargin)
            %varargin indica si se entrega error en caso de que proyecto no
            %esté en el plan
            if nargin > 2
                con_error = varargin{1};
            else
                con_error = true;
            end
            
            for i = 1:length(this.Plan)
                if ~isempty(find(this.Plan(i).Proyectos == indice_proyecto, 1))
                    etapa = i;
                    return
                end
            end
            if con_error
                error = MException('cPlanExpansion:entrega_etapa_proyecto',['Error de programación. Proyecto ' num2str(indice_proyecto) ' no se encuentra en el plan']);
                throw(error)
            else
                etapa = 0;
            end
        end
        
        function [existe, nro_etapa] = dependencia_existe(this, indice_proyectos_dependientes)
            existe = false;
            nro_etapa = 0;
            for i = 1:length(this.Plan)
                if sum(ismember(this.Plan(i).Proyectos, indice_proyectos_dependientes)) > 0
                    existe = true;
                    nro_etapa = i;
                    return
                end
            end
        end

        function [proy, etapa]= entrega_proyecto_dependiente(this, indice_proyectos_dependientes, varargin)
            %varargin indica si es con o sin error
            con_error = true;
            if nargin > 2
                con_error = varargin{1};
            end
            for i = 1:length(this.Plan)
                if sum(ismember(this.Plan(i).Proyectos, indice_proyectos_dependientes)) > 0
                    proy = this.Plan(i).Proyectos(ismember(this.Plan(i).Proyectos, indice_proyectos_dependientes));
                    etapa = i;
                    return;
                end
            end
            if con_error
                texto = '';
                for i = 1:length(indice_proyectos_dependientes)
                    texto = [texto ' ' num2str(indice_proyectos_dependientes(i))];
                end
                error = MException('cPlanExpansion:entrega_proyecto_dependiente',['Error de programación. Proyecto(s) dependiente(s) no se encuentran en plan. Proyectos: ' texto]);
                throw(error)
            else
                proy = 0;
                etapa = 0;
            end
        end
        
        function [proy, etapa]= entrega_proyectos_y_etapa_de_lista(this, indice_proyectos)
            for i = 1:length(this.Plan)
                if sum(ismember(this.Plan(i).Proyectos, indice_proyectos)) > 0
                    proy = this.Plan(i).Proyectos(ismember(this.Plan(i).Proyectos, indice_proyectos));
                    etapa = i;
                    return;
                end
            end
            proy = 0;
            etapa = 0;
        end

        function ultima_etapa = entrega_ultima_etapa_posible_modificacion_proyecto(this, proy_aguas_arriba, desde_etapa)
            ultima_etapa = length(this.Plan)+1;
            for i = desde_etapa:length(this.Plan)
                if sum(ismember(proy_aguas_arriba, this.Plan(i).Proyectos)) > 0
                    ultima_etapa = i;
                    return
                end
            end
        end
        
        function etapas = entrega_etapas_con_proyectos(this)
            etapas = [];
            for i = 1:length(this.Plan)
                if ~isempty(this.Plan(i).Proyectos)
                    etapas = [etapas i];
                end
            end
        end
            
        function existe = proyecto_excluyente_existe(this, indice_proyectos_excluyentes)
            existe = false;
            for i = 1:length(this.Plan)
                if sum(ismember(this.Plan(i).Proyectos, indice_proyectos_excluyentes)) > 0
                    existe = true;
                    return
                end
            end
        end

        function existe = conectividad_existe(this, indice_proyectos_conectividad)
            existe = false;
            for i = 1:length(this.Plan)
                if sum(ismember(this.Plan(i).Proyectos, indice_proyectos_conectividad)) > 0
                    existe = true;
                    return
                end
            end
        end

        function [existe, etapa] = conectividad_existe_con_etapa(this, indice_proyectos_conectividad)
            existe = false;
            etapa = 0;
            for i = 1:length(this.Plan)
                if sum(ismember(this.Plan(i).Proyectos, indice_proyectos_conectividad)) > 0
                    existe = true;
                    etapa = i;
                    return
                end
            end
        end

        function [existe, etapa, proyecto] = conectividad_existe_con_etapa_y_proyecto(this, indice_proyectos_conectividad)
            existe = false;
            etapa = 0;
            proyecto = 0;
            for i = 1:length(this.Plan)
                if sum(ismember(this.Plan(i).Proyectos, indice_proyectos_conectividad)) > 0
                    existe = true;
                    etapa = i;
                    proyecto = this.Plan(i).Proyectos(ismember(this.Plan(i).Proyectos, indice_proyectos_conectividad));
                    return
                end
            end
        end
        
        function [id_conect, etapa] = entrega_conectividad_existente_con_etapa(this, indice_proyectos_conectividad)
            id_conect = 0;
            etapa = 0;
            for i = 1:length(this.Plan)
                id_existente = indice_proyectos_conectividad(ismember(indice_proyectos_conectividad, this.Plan(i).Proyectos));
                if ~isempty(id_existente)
                    id_conect = id_existente;
                    etapa = i;
                    return
                end
            end
        end
        
        function [proy, etapa]= entrega_proyecto_conectividad(this, indice_proyectos_conectividad)
            proy = 0;
            etapa = 0;
            for i = 1:length(this.Plan)
                if sum(ismember(this.Plan(i).Proyectos, indice_proyectos_conectividad)) > 0
                    proy = this.Plan(i).Proyectos(ismember(this.Plan(i).Proyectos, indice_proyectos_conectividad));
                    etapa = i;
                    return;
                end
            end
        end

        function proyectos = entrega_proyectos(this, varargin)
            % varargin indica la etapa
            if nargin > 1
                etapa = varargin{1};
                proyectos = this.Plan(etapa).Proyectos;
            else
                proyectos = [];
                for i = 1:length(this.Plan)
                    proyectos = [proyectos this.Plan(i).Proyectos];
                end
            end
        end

        function cantidad = entrega_cantidad_proyectos_etapa(this, nro_etapa)
            cantidad = length(this.Plan(nro_etapa).Proyectos);
        end
        
        function [proyectos, etapas]= entrega_proyectos_y_etapas(this)
            proyectos = [];
            etapas = [];
            for i = 1:length(this.Plan)
                proyectos = [proyectos this.Plan(i).Proyectos];
                etapas = [etapas i*ones(1,length(this.Plan(i).Proyectos))];
            end
        end
        
        function proyectos = entrega_proyectos_acumulados(this, nro_etapa)
            proyectos = [];
            for i = 1:nro_etapa
            	proyectos = [proyectos this.Plan(i).Proyectos];
            end
        end

        function [proyectos, etapas] = entrega_proyectos_acumulados_y_etapas_a_partir_de_etapa(this, nro_etapa)
            proyectos = [];
            etapas = [];
            for i = nro_etapa:length(this.Plan)
                proyectos = [proyectos this.Plan(i).Proyectos];
            	etapas = [etapas i*ones(1, length(this.Plan(i).Proyectos))];
            end            
        end
        
        function [proyectos, etapas] = entrega_proyectos_acumulados_y_etapas(this, nro_etapa)
            proyectos = [];
            etapas = [];
            for i = 1:nro_etapa
                proyectos = [proyectos this.Plan(i).Proyectos];
            	etapas = [etapas i*ones(1, length(this.Plan(i).Proyectos))];
            end            
        end
        
        function iguales = compara_proyectos(this, plan, varargin)
            debug = false;
            if nargin > 2
                debug = varargin{1};
            end
            iguales = false;
            %primero determina si número de etapas coincide
            if length(this.Plan) ~= length(plan.Plan)
                return;
            end
            for i = 1:length(this.Plan) % etapas
                if ~isequal(sort(this.Plan(i).Proyectos),sort(plan.Plan(i).Proyectos))
                    if debug
                        disp(['etapa_fallo = ' num2str(i)]);
                        proyectos_mejor_plan = sort(this.Plan(i).Proyectos)
                        proyectos_plan_optimo = sort(plan.Plan(i).Proyectos)
                    end
                    return;
                end
            end
            % si salió del for quiere decir que planes son iguales
            iguales = true;
        end
        
        function valido = es_valido(this, varargin)
            if nargin > 1
                nro_etapa = varargin{1};
                valido = this.ResultadoEvaluacion(nro_etapa).Valido;
                return
            else
                valido = true;
                for nro_etapa = 1:length(this.ResultadoEvaluacion)
                    if ~this.ResultadoEvaluacion(nro_etapa).Valido
                        valido = false;
                        return
                    end
                end            
            end
        end
        
        function valido = es_valido_hasta_etapa(this, nro_etapa)
            valido = true;
            for i = 1:nro_etapa
                if ~this.ResultadoEvaluacion(nro_etapa).Valido
                    valido = false;
                    return
                end
            end
        end
        
        function costo_operacion = entrega_costo_operacion(this, nro_etapa)
            costo_operacion = sum(this.ResultadoEvaluacion(nro_etapa).CostoOperacion);
        end

        function costo_generacion = entrega_costo_generacion(this, nro_etapa)
            costo_generacion = sum(this.ResultadoEvaluacion(nro_etapa).CostoGeneracion);
        end
        
        function costo_ens = entrega_costo_ens(this, nro_etapa)
            costo_ens = sum(this.ResultadoEvaluacion(nro_etapa).CostoENS);
        end
        
        function costo_recorte_res = entrega_costo_recorte_res(this, nro_etapa)
            costo_recorte_res = sum(this.ResultadoEvaluacion(nro_etapa).CostoRecorteRES);
        end
        
        function imprime(this, varargin)
            % varargin indica el nombre
            prot = cProtocolo.getInstance;
            if nargin > 1
                nombre = varargin{1};
                prot.imprime_texto(nombre);
            end
            
            texto = ['Plannr =' num2str(this.NroPlan)];
            prot.imprime_texto(texto);

            texto = ['NPV C. Gen = ' num2str(this.CGenTotal)];
            prot.imprime_texto(texto);

            texto = ['NPV C. ENS = ' num2str(this.CENSTotal)];
            prot.imprime_texto(texto);

            texto = ['NPV C. Recorte RES = ' num2str(this.CRecorteRESTotal)];
            prot.imprime_texto(texto);
            
            texto = ['NPV C. Oper = ' num2str(this.COperTotal)];
            prot.imprime_texto(texto);
            
            texto = ['NPV C. Inv. = ' num2str(this.CInvTotal)];
            prot.imprime_texto(texto);
            
            texto = ['NPV Total = ' num2str(this.TotexTotal)];
            prot.imprime_texto(texto);

            
            prot.imprime_texto('\nProyectos');
            if this.NombresDisponibles
                texto = sprintf('%-7s %-7s %-50s', 'Etapa', 'Proy.', 'Nombre');
            else
                texto = sprintf('%-7s %-7s', 'Etapa', 'Proy.');
            end
            prot.imprime_texto(texto);
            
            for i = 1:length(this.Plan)
                if isempty(this.Plan(i).Proyectos)
                    %texto = sprintf('%-7s %-7s', num2str(i), '-');
                    %prot.imprime_texto(texto);
                else
                    primero = true;
                    for j = 1:length(this.Plan(i).Proyectos)
                        id_proy = num2str(this.Plan(i).Proyectos(j));
                        if this.NombresDisponibles
                            nombre_proy = this.Plan(i).Nombres{j};
                            if primero
                                texto = sprintf('%-7s %-7s %-50s', num2str(i), id_proy, nombre_proy);
                                primero = false;
                            else
                                texto = sprintf('%-7s %-7s %-50s', '', id_proy, nombre_proy);
                            end
                        else
                            if primero
                                texto = sprintf('%-7s %-7s', num2str(i), id_proy);
                                primero = false;
                            else
                                texto = sprintf('%-7s %-7s', '', id_proy);
                            end
                        end
                        prot.imprime_texto(texto);
                    end
                end
            end
            prot.imprime_texto('\nCostos por etapa');
            texto = sprintf('%-7s %-10s %-10s %-12s %-12s', 'Etapa', 'C. Inv.', 'C. Oper', 'NPV C. Inv', 'NPV C. Oper');
            prot.imprime_texto(texto);
            total_cinv_act = 0;
            total_coper_act = 0;
            for i = 1:length(this.Totex)
                total_cinv_act = total_cinv_act + this.CInvTActual(i);
                total_coper_act = total_coper_act + this.COperTActual(i);
                
                texto = sprintf('%-7s %-10s %-10s %-12s %-12s', num2str(i), ...
                                             num2str(this.CInv(i)), ...
                                             num2str(this.COper(i)), ...
                                             num2str(this.CInvTActual(i)), ...
                                             num2str(this.COperTActual(i)));
                prot.imprime_texto(texto);
            end
            prot.imprime_texto(['Suma Cinv. actual: ' num2str(total_cinv_act)]);
            prot.imprime_texto(['Suma Coper. actual: ' num2str(total_coper_act)]);
            prot.imprime_texto(['Total: ' num2str(total_cinv_act + total_coper_act)]);
        end
        
        function imprime_plan_expansion(this)

            prot = cProtocolo.getInstance;
            texto = ['Plannr =' num2str(this.NroPlan)];
            prot.imprime_texto(texto);

            prot.imprime_texto('\nProyectos');
            if this.NombresDisponibles
                texto = sprintf('%-7s %-7s %-50s', 'Etapa', 'Proy.', 'Nombre');
            else
                texto = sprintf('%-7s %-7s', 'Etapa', 'Proy.');
            end
            prot.imprime_texto(texto);
            
            for i = 1:length(this.Plan)
                if isempty(this.Plan(i).Proyectos)
                    %texto = sprintf('%-7s %-7s', num2str(i), '-');
                    %prot.imprime_texto(texto);
                else
                    primero = true;
                    for j = 1:length(this.Plan(i).Proyectos)
                        id_proy = num2str(this.Plan(i).Proyectos(j));
                        if this.NombresDisponibles
                            nombre_proy = this.Plan(i).Nombres{j};
                            if primero
                                texto = sprintf('%-7s %-7s %-50s', num2str(i), id_proy, nombre_proy);
                                primero = false;
                            else
                                texto = sprintf('%-7s %-7s %-50s', '', id_proy, nombre_proy);
                            end
                        else
                            if primero
                                texto = sprintf('%-7s %-7s', num2str(i), id_proy);
                                primero = false;
                            else
                                texto = sprintf('%-7s %-7s', '', id_proy);
                            end
                        end
                        prot.imprime_texto(texto);
                    end
                end
            end
        end

        function texto_completo = entrega_texto_plan_expansion(this)

            texto_completo = ['Plannr =' num2str(this.NroPlan) '\n'];
            if this.NombresDisponibles
                texto = sprintf('%-7s %-7s %-50s', 'Etapa', 'Proy.', 'Nombre');
            else
                texto = sprintf('%-7s %-7s', 'Etapa', 'Proy.');
            end
            texto_completo = [texto_completo texto '\n'];
            
            for i = 1:length(this.Plan)
                if isempty(this.Plan(i).Proyectos)
                    %texto = sprintf('%-7s %-7s', num2str(i), '-');
                    %prot.imprime_texto(texto);
                else
                    primero = true;
                    for j = 1:length(this.Plan(i).Proyectos)
                        id_proy = num2str(this.Plan(i).Proyectos(j));
                        if this.NombresDisponibles
                            nombre_proy = this.Plan(i).Nombres{j};
                            if primero
                                texto = sprintf('%-7s %-7s %-50s', num2str(i), id_proy, nombre_proy);
                                primero = false;
                            else
                                texto = sprintf('%-7s %-7s %-50s', '', id_proy, nombre_proy);
                            end
                        else
                            if primero
                                texto = sprintf('%-7s %-7s', num2str(i), id_proy);
                                primero = false;
                            else
                                texto = sprintf('%-7s %-7s', '', id_proy);
                            end
                        end
                        texto_completo = [texto_completo texto '\n'];
                    end
                end
            end
        end
        
        function imprime_hasta_etapa(this, nro_etapa)
            
            prot = cProtocolo.getInstance;
            texto = ['Plannr =' num2str(this.NroPlan)];
            prot.imprime_texto(texto);

            prot.imprime_texto('\nProyectos');
            if this.NombresDisponibles
                texto = sprintf('%-7s %-7s %-50s', 'Etapa', 'Proy.', 'Nombre');
            else
                texto = sprintf('%-7s %-7s', 'Etapa', 'Proy.');
            end
            prot.imprime_texto(texto);
            
            for i = 1:nro_etapa
                if isempty(this.Plan(i).Proyectos)
                    %texto = sprintf('%-7s %-7s', num2str(i), '-');
                    %prot.imprime_texto(texto);
                else
                    primero = true;
                    for j = 1:length(this.Plan(i).Proyectos)
                        id_proy = num2str(this.Plan(i).Proyectos(j));
                        if this.NombresDisponibles
                            nombre_proy = this.Plan(i).Nombres{j};
                            if primero
                                texto = sprintf('%-7s %-7s %-50s', num2str(i), id_proy, nombre_proy);
                                primero = false;
                            else
                                texto = sprintf('%-7s %-7s %-50s', '', id_proy, nombre_proy);
                            end
                        else
                            if primero
                                texto = sprintf('%-7s %-7s', num2str(i), id_proy);
                                primero = false;
                            else
                                texto = sprintf('%-7s %-7s', '', id_proy);
                            end
                        end
                        prot.imprime_texto(texto);
                    end
                end
            end
        end

        function imprime_en_detalle(this, adm_proy, paropt, varargin)
            % varargin indica el nombre
            prot = cProtocolo.getInstance;
            if nargin > 3
                nombre = varargin{1};
                prot.imprime_texto(nombre);
            end
            
            texto = ['Plannr =' num2str(this.NroPlan)];
            prot.imprime_texto(texto);

            texto = ['NPV C. Oper = ' num2str(this.COperTotal)];
            prot.imprime_texto(texto);
            texto = ['NPV C. Inv. = ' num2str(this.CInvTotal)];
            prot.imprime_texto(texto);
            texto = ['NPV Total = ' num2str(this.TotexTotal)];
            prot.imprime_texto(texto);
            texto = ['C. ENS Total = ' num2str(this.CENSTotal)];
            prot.imprime_texto(texto);

            texto = ['C. Recorte RES Total = ' num2str(this.CRecorteRESTotal)];
            prot.imprime_texto(texto);
                        
            if ~this.NombresDisponibles
                this.agrega_nombre_proyectos(adm_proy);
            end
            
            prot.imprime_texto('\nProyectos');
            texto = sprintf('%-7s %-7s %-13s %-13s %-13s %-13s %-50s', 'Etapa', 'Proy.', 'C.Inv', 'Cum etapa', 'C.Inv. Act', 'Cum etapa', 'Nombre');
            prot.imprime_texto(texto);

            q = (1 + paropt.TasaDescuento);
            detapa = paropt.DeltaEtapa;
            cum = 0;
            cum_actual = 0;
            for i = 1:length(this.Plan)
                if isempty(this.Plan(i).Proyectos)
                    %texto = sprintf('%-7s %-7s', num2str(i), '-');
                    %prot.imprime_texto(texto);
                else
                    cum_etapa = 0;
                    cum_actual_etapa = 0;
                    primero = true;
                    for j = 1:length(this.Plan(i).Proyectos)
                        id_proy = num2str(this.Plan(i).Proyectos(j));
                        nombre_proy = this.Plan(i).Nombres{j};
                        indice = this.Plan(i).Proyectos(j);
                        costo_inv = adm_proy.Proyectos(indice).entrega_costos_inversion();
                        factor_desarrollo = paropt.entrega_factor_costo_desarrollo_proyectos();
                        costo_inv = round(costo_inv*factor_desarrollo,5);
                        costo_inv_act = costo_inv/q^(detapa*i);
                        cum_etapa = cum_etapa + costo_inv;
                        cum_actual_etapa = cum_actual_etapa + costo_inv_act;
                        cum = cum + costo_inv;
                        cum_actual = cum_actual + costo_inv_act;
                        if primero
                            texto_etapa = num2str(i);
                            primero = false;
                        else
                            texto_etapa = '';
                        end
                        texto = sprintf('%-7s %-7s %-13s %-13s %-13s %-13s %-50s', texto_etapa, ...
                                                                                   id_proy, ...
                                                                                   num2str(costo_inv), ...
                                                                                   num2str(cum_etapa), ...
                                                                                   num2str(costo_inv_act), ...
                                                                                   num2str(cum_actual_etapa), ...
                                                                                   nombre_proy);                        
                        prot.imprime_texto(texto);
                    end
                end
            end
            prot.imprime_texto([' CInv. totales NPV: ' num2str(cum_actual)]);
            prot.imprime_texto('\nCostos por etapa');
            texto = sprintf('%-7s %-10s %-10s %-12s %-12s %-12s %-12s', 'Etapa', 'C. Inv.', 'C. Oper', 'NPV C. Inv', 'NPV C. Oper', 'C.ENS', 'C.Spill');
            prot.imprime_texto(texto);
            total_cinv_act = 0;
            total_coper_act = 0;
            for i = 1:length(this.Totex)
                total_cinv_act = total_cinv_act + this.CInvTActual(i);
                total_coper_act = total_coper_act + this.COperTActual(i);
                
                texto = sprintf('%-7s %-10s %-10s %-12s %-12s %-12s %-12s', num2str(i), ...
                                             num2str(this.CInv(i)), ...
                                             num2str(this.COper(i)), ...
                                             num2str(this.CInvTActual(i)), ...
                                             num2str(this.COperTActual(i)), ...
                                             num2str(this.CENSTActual(i)), ...
                                             num2str(this.CRecorteRESTActual(i)));
                prot.imprime_texto(texto);
            end
            prot.imprime_texto(['Suma Cinv. actual: ' num2str(total_cinv_act)]);
            prot.imprime_texto(['Suma Coper. actual: ' num2str(total_coper_act)]);
            prot.imprime_texto(['Suma CENS actual: ' num2str(sum(this.CENSTActual))]);
            prot.imprime_texto(['Suma CSpill actual: ' num2str(sum(this.CRecorteRESTActual))]);
            prot.imprime_texto(['Total: ' num2str(total_cinv_act + total_coper_act)]);
        end
        
        function inserta_no(this, val)
            this.NroPlan = val;
        end
        
        function nro = entrega_no(this)
            nro = this.NroPlan;
        end
        
        function val = nombre_proyectos_disponibles(this)
            val = this.NombresDisponibles;
        end
        
        function agrega_nombre_proyectos(this, adm_pr)
            for i = 1:length(this.Plan)
                this.Plan(i).Nombres = cell(1);
                for j = 1:length(this.Plan(i).Proyectos)
                    indice_proyecto = this.Plan(i).Proyectos(j);
                    proyecto = adm_pr.entrega_proyecto(indice_proyecto);
                	this.Plan(i).Nombres{j} = proyecto.entrega_nombre();
                end
            end
            this.NombresDisponibles = true;
        end
        
        function inserta_iteracion(this, nro_iteracion)
            this.Iteracion = nro_iteracion;
        end
        
        function val = entrega_iteracion(this)
            val = this.Iteracion;
        end
        
        function inserta_busqueda_local(this, val)
            this.BusquedaLocal = val;
        end
        
        function val = entrega_busqueda_local(this)
            val = this.BusquedaLocal;
        end

        function inserta_estrategia_busqueda_local(this, val)
            this.EstrategiaBusquedaLocal = val;
        end

        function val = entrega_estrategia_busqueda_local(this)
            val = this.EstrategiaBusquedaLocal;
        end
        
        function inserta_plan_base(this, val)
            this.PlanBase = val;
        end
        
        function val = entrega_plan_base(this)
            val = this.PlanBase;
        end
        
        function plan = entrega_plan_expansion(this)
            plan = this.Plan;
        end
        
        function plan = inserta_plan_expansion(this, plan)
            this.Plan = plan;
        end
        
        function totex = entrega_totex_total(this)
            totex = this.TotexTotal;
        end
        
        function elimina_proyectos(this, proyectos, varargin)
            % varargin indica las etapas. Si no se indica, entonces se
            % busca en todas las etapas
            
            if nargin > 2
                etapas = varargin{1};
                for i = 1:length(proyectos)
                    this.Plan(etapas(i)).Proyectos(ismember(this.Plan(etapas(i)).Proyectos, proyectos(i))) = [];
                    if isempty(this.Plan(etapas(i)).Proyectos)
                        this.Plan(etapas(i)).Proyectos = [];
                    end
                end
            else
                for i = 1:length(this.Plan)
                    encontrados = this.Plan(i).Proyectos(ismember(this.Plan(i).Proyectos, proyectos));
                    if ~isempty(encontrados)
                        this.Plan(i).Proyectos(ismember(this.Plan(i).Proyectos, encontrados)) = [];
                        proyectos(ismember(proyectos, encontrados)) = [];
                        if isempty(this.Plan(i).Proyectos)
                            this.Plan(i).Proyectos = [];
                        end
                        if isempty(proyectos)
                            return;
                        end
                    end
                end
            end
        end
        
        function desplaza_proyectos(this, proyectos, etapas_originales, etapas_desplazar)
            for i = 1:length(proyectos)                
                id = find(this.Plan(etapas_originales(i)).Proyectos == proyectos(i));
                if ~isempty(id)
                    this.Plan(etapas_originales(i)).Proyectos(id) = [];
                    if isempty(this.Plan(etapas_originales(i)).Proyectos)
                        this.Plan(etapas_originales(i)).Proyectos = [];
                    end
                    this.Plan(etapas_desplazar(i)).Proyectos = [proyectos(i) this.Plan(etapas_desplazar(i)).Proyectos];
                else
%                    disp('error')
                    error = MException('cPlanExpansion:desplaza_proyectos','Error de programación. Proyecto a desplazar no se encuentra en etapa indicada');
                    throw(error)
                end
            end
        end
                
        function adelanta_proyectos(this, proyectos, etapas_originales, etapas_adelantar)
            for i = 1:length(proyectos)                
                id = find(this.Plan(etapas_originales(i)).Proyectos == proyectos(i));
                if ~isempty(id)
                    this.Plan(etapas_originales(i)).Proyectos(id) = [];
                    if isempty(this.Plan(etapas_originales(i)).Proyectos)
                        this.Plan(etapas_originales(i)).Proyectos = [];
                    end
                    this.Plan(etapas_adelantar(i)).Proyectos = [this.Plan(etapas_adelantar(i)).Proyectos proyectos(i)];
                else
                    disp('error adelanta proyecto')
%                     error = MException('cPlanExpansion:adelanta_proyectos','Error de programación. Proyecto a adelantar no se encuentra en etapa indicada');
%                     throw(error)
                end
            end
        end
        
        function inserta_sep_original(this, sep)
            this.SEP_original = sep;
            this.Etapa_sep_actual = 0;
        end
        
        function sep = entrega_sep_actual(this)
            if isempty(this.SEP_actual)
                this.SEP_actual = this.SEP_original.crea_copia();
                this.Etapa_sep_actual = 0;
            end
            sep = this.SEP_actual;
        end
        
        function etapa = entrega_etapa_sep_actual(this)
            etapa = this.Etapa_sep_actual;
        end
        
        function inserta_etapa_sep_actual(this, etapa)
            this.Etapa_sep_actual = etapa;
        end
        
        function reinicia_sep_actual(this)
            this.SEP_actual = cSistemaElectricoPotencia.empty;
            this.SEP_actual = this.SEP_original.crea_copia();
            this.Etapa_sep_actual = 0;
        end
        
        function crea_estructura_e_inserta_evaluacion_etapa(this, nro_etapa, costo_operacion_totales, costo_generacion_totales, costo_ens_totales, costo_recorte_res_totales)
            estructura_eval.Existe = true;
            estructura_eval.Valido = costo_ens_totales == 0 && costo_recorte_res_totales == 0;
            estructura_eval.CostoGeneracion = costo_generacion_totales;
            estructura_eval.CostoENS = costo_ens_totales;
            estructura_eval.CostoRecorteRES = costo_recorte_res_totales;
            estructura_eval.CostoOperacion = costo_operacion_totales;
            estructura_eval.LineasFlujoMaximo = [];
            estructura_eval.TrafosFlujoMaximo = [];
            estructura_eval.LineasPocoUso = [];
            estructura_eval.TrafosPocoUso = [];
            
            this.ResultadoEvaluacion(nro_etapa) = estructura_eval;
            error = MException('cPlanExpansion:crea_estructura_e_inserta_evaluacion_etapa','Esta funcion no está actualizada. Falta incorporar lineas/trafos flujo maximo/poco uso');
            throw(error)
        end

        function val = entrega_lineas_flujo_maximo(this, etapa)
           val =  this.ResultadoEvaluacion(etapa).LineasFlujoMaximo;
        end
        
        function val = entrega_trafos_flujo_maximo(this, etapa)
           val =  this.ResultadoEvaluacion(etapa).TrafosFlujoMaximo;
        end
        
        function val = entrega_elementos_flujo_maximo(this, etapa)
            val = [this.ResultadoEvaluacion(etapa).LineasFlujoMaximo; this.ResultadoEvaluacion(etapa).TrafosFlujoMaximo];
        end
        
        function val = entrega_lineas_poco_uso(this, etapa)
           val =  this.ResultadoEvaluacion(etapa).LineasPocoUso;
        end
        
        function val = entrega_trafos_poco_uso(this, etapa)
           val =  this.ResultadoEvaluacion(etapa).TrafosPocoUso;
        end
        
        function val = entrega_elementos_poco_uso(this, etapa)
            val = [this.ResultadoEvaluacion(etapa).LineasPocoUso; this.ResultadoEvaluacion(etapa).TrafosPocoUso];
        end
        
    end
end