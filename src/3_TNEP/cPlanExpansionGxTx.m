classdef cPlanExpansionGxTx < handle
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
        UltimaEtapaInicializada = 0
        
        % plan de expansion. Contiene sólo el índice del proyecto
        % Plan(nro_etapa).ProyTransmision = [indice_proyecto1 ... ]
        % está la opción de ingresar nombres también
        
        ProyTransmision = [] % por defecto, proyectos contiene sólo proyectos de transmisión (inlcuye baterías)
        EtapasTransmision = []

        ProyGeneracion = [] % específico para proyectos de generación
        EtapasGeneracion = []
        
        NombresDisponibles = false;
        NombresTransmision = cell(0,1);
        NombresGeneracion = cell(0,1);
        
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
        CInv = [];
        CInvTActual = [];
        CInvTotal = [];
        
        CInvTransmision = [];
        CInvTransmisionTActual = [];
        CInvTransmisionTotal = [];

        CInvGeneracion = [];
        CInvGeneracionTActual = [];
        CInvGeneracionTotal = [];
        
        COper = [];
        COperTActual = [];
        COperTotal = [];

        CGen  = [];% costos de generación
        CGenTActual = [];
        CGenTotal = [];

        CENS  = [];% costos de energía no suministrada
        CENSTActual = [];
        CENSTotal = [];
    
        CRecorteRES = [];
        CRecorteRESTActual = [];
        CRecorteRESTotal = [];
        
        Totex = [];
        TotexTActual = [];
        TotexTotal = [];
        
        % SEP Original, actual y etapa actual. Para mejorar performance del programa
        SEP_original = cSistemaElectricoPotencia.empty
        SEP_actual = cSistemaElectricoPotencia.empty
        Etapa_sep_actual = 0
    end
    
    methods
        function this = cPlanExpansionGxTx(nro_plan)
            this.NroPlan = nro_plan;
        end

        function copia = crea_copia(this, nro_plan_copia)
            copia = cPlanExpansionGxTx(nro_plan_copia);
            copia.ProyTransmision = this.ProyTransmision;
            copia.EtapasTransmision = this.EtapasTransmision;
            copia.ProyGeneracion = this.ProyGeneracion;
            copia.EtapasGeneracion = this.EtapasGeneracion;
            
            copia.NombresDisponibles = this.NombresDisponibles;
            copia.ResultadoEvaluacion = this.ResultadoEvaluacion;
            copia.Valido = this.Valido;
            copia.CInv = this.CInv;
            copia.CInvTActual = this.CInvTActual;
            copia.CInvTotal = this.CInvTotal;
        
            copia.CInvTransmision = this.CInvTransmision;
            copia.CInvTransmisionTActual = this.CInvTransmisionTActual;
            copia.CInvTransmisionTotal = this.CInvTransmisionTotal;

            copia.CInvGeneracion = this.CInvGeneracion;
            copia.CInvGeneracionTActual = this.CInvGeneracionTActual;
            copia.CInvGeneracionTotal = this.CInvGeneracionTotal;
        
            copia.COper = this.COper;
            copia.COperTActual = this.COperTActual;
            copia.COperTotal = this.COperTotal;
        
            copia.Totex = this.Totex;
            copia.TotexTActual = this.TotexTActual;
            copia.TotexTotal = this.TotexTotal;
            
            copia.UltimaEtapaInicializada = this.UltimaEtapaInicializada;
        end
        
        function estructura = entrega_estructura_costos(this)
            estructura.CInv = this.CInv;
            estructura.CInvTActual = this.CInvTActual;
            estructura.CInvTotal = this.CInvTotal;

            estructura.CInvTransmision = this.CInvTransmision;
            estructura.CInvTransmisionTActual = this.CInvTransmisionTActual;
            estructura.CInvTransmisionTotal = this.CInvTransmisionTotal;

            estructura.CInvGeneracion = this.CInvGeneracion;
            estructura.CInvGeneracionTActual = this.CInvGeneracionTActual;
            estructura.CInvGeneracionTotal = this.CInvGeneracionTotal;
            
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
        
            this.CInvTransmision = estructura.CInvTransmision;
            this.CInvTransmisionTActual = estructura.CInvTransmisionTActual;
            this.CInvTransmisionTotal = estructura.CInvTransmisionTotal;
            this.CInvGeneracion = estructura.CInvGeneracion;
            this.CInvGeneracionTActual = estructura.CInvGeneracionTActual;
            this.CInvGeneracionTotal = estructura.CInvGeneracionTotal;
            
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
        
        function cantidad = cantidad_acumulada_proyectos_tx(this, varargin)
            if nargin > 1
                nro_etapa = varargin{1};
                cantidad = length(this.ProyTransmision(this.EtapasTransmision <= nro_etapa));
            else
                cantidad = length(this.ProyTransmision);
            end
        end

        function cantidad = cantidad_acumulada_proyectos_gx(this, varargin)
            if nargin > 1
                nro_etapa = varargin{1};
                cantidad = length(this.ProyGeneracion(this.EtapasGeneracion <= nro_etapa));
            else
                cantidad = length(this.ProyGeneracion);
            end
        end
        
        function inicializa_etapa(this, etapa)
            this.UltimaEtapaInicializada = etapa;
        end
        
        function agrega_proyecto_tx(this, nro_etapa, indice_proyecto, varargin)
            % proyectos se agregan siempre al final de la etapa, y antes de la etapa anterior
            % varargin indica el nombre del proyecto
            if ~isempty(this.ProyTransmision)
                % verifica que proyecto no esté en plan
                if ismember(indice_proyecto, this.ProyTransmision)
                   error = MException('cPlanExpansionGxTx:agrega_proyecto_tx',['Error de programación. Proyecto ' num2str(indice_proyecto) ' ya se encuentra incluido en plan']);
                   throw(error)
                end
                posicion = find(this.EtapasTransmision <= nro_etapa,1,'last');
                this.ProyTransmision = [this.ProyTransmision(1:posicion) indice_proyecto this.ProyTransmision(posicion+1:end)];
                this.EtapasTransmision = [this.EtapasTransmision(1:posicion) nro_etapa this.EtapasTransmision(posicion+1:end)];
                if nargin > 3
                    nombre_proyecto = varargin{1};
                    this.NombresTransmision = [this.NombresTransmision(1:posicion) nombre_proyecto this.NombresTransmision(posicion+1:end)];
                end
            else
                this.ProyTransmision = indice_proyecto;
                this.EtapasTransmision = nro_etapa;
                if nargin > 3
                    nombre_proyecto = varargin{1};
                    this.NombresTransmision{1} = nombre_proyecto;
                end
            end            
        end

        function agrega_proyecto_gx(this, nro_etapa, indice_proyecto, varargin)
            % proyectos se agregan siempre al final de la etapa, y antes de la etapa anterior
            % varargin indica el nombre del proyecto
            if ~isempty(this.ProyGeneracion)
                % verifica que proyecto no esté en plan
                if ismember(indice_proyecto, this.ProyGeneracion)
                   error = MException('cPlanExpansionGxTx:agrega_proyecto_gx',['Error de programación. Proyecto ' num2str(indice_proyecto) ' ya se encuentra incluido en plan']);
                   throw(error)
                end
                posicion = find(this.EtapasGeneracion <= nro_etapa,1,'last');
                this.ProyGeneracion = [this.ProyGeneracion(1:posicion) indice_proyecto this.ProyGeneracion(posicion+1:end)];
                this.EtapasGeneracion = [this.EtapasGeneracion(1:posicion) nro_etapa this.EtapasGeneracion(posicion+1:end)];
                if nargin > 3
                    nombre_proyecto = varargin{1};
                    this.NombresGeneracion = [this.NombresGeneracion(1:posicion) nombre_proyecto this.NombresGeneracion(posicion+1:end)];
                end
            else
                this.ProyGeneracion = indice_proyecto;
                this.EtapasGeneracion = nro_etapa;
                if nargin > 3
                    nombre_proyecto = varargin{1};
                    this.NombresGeneracion{1} = nombre_proyecto;
                end
            end            
        end
        
        function inserta_proyectos_etapa_tx(this, nro_etapa, proyectos)
            if ~isempty(this.ProyTransmision)
                posicion = find(this.EtapasTransmision <= nro_etapa,1,'last');
                this.ProyTransmision = [this.ProyTransmision(1:posicion) proyectos this.ProyTransmision(posicion+1:end)];
                this.EtapasTransmision = [this.EtapasTransmision(1:posicion) nro_etapa*ones(1,length(proyectos)) this.EtapasTransmision(posicion+1:end)];
            else
                this.ProyTransmision = proyectos;
                this.EtapasTransmision = nro_etapa*ones(1,length(proyectos));                
            end
        end

        function inserta_proyectos_etapa_gx(this, nro_etapa, proyectos)
            if ~isempty(this.ProyGeneracion)
                posicion = find(this.EtapasGeneracion <= nro_etapa,1,'last');
                this.ProyGeneracion = [this.ProyGeneracion(1:posicion) proyectos this.ProyGeneracion(posicion+1:end)];
                this.EtapasGeneracion = [this.EtapasGeneracion(1:posicion) nro_etapa*ones(1,length(proyectos)) this.EtapasGeneracion(posicion+1:end)];
            else
                this.ProyGeneracion = proyectos;
                this.EtapasGeneracion = nro_etapa*ones(1,length(proyectos));                
            end
        end
        
        function desecha_plan(this, varargin)
            % nargin indica la etapa a desechar
            this.CantidadReparaciones = 0;
            if nargin < 2
                % desecha plan completo
                this.ProyTransmision = [];
                this.EtapasTransmision = [];
                this.NombresTransmision = cell(1,0);
                this.ProyGeneracion = [];
                this.EtapasGeneracion = [];
                this.NombresGeneracion = cell(1,0);
                this.CantidadVecesDesechadoTotal = this.CantidadVecesDesechadoTotal +1;
                this.CantidadVecesDesechadoEtapa = 0;
                this.ResultadoEvaluacion = [];
            else
                nro_etapa = varargin{1};
                ultima_etapa = max(max(this.EtapasTransmision),max(this.EtapasGeneracion));
                if nro_etapa == ultima_etapa
                    this.ProyTransmision(this.EtapasTransmision == nro_etapa) = [];
                    this.ProyGeneracion(this.EtapasGeneracion == nro_etapa) = [];
                    if ~isempty(this.NombresTransmision)
                        this.NombresTransmision(this.EtapasTransmision == nro_etapa) = [];
                        this.NombresGeneracion(this.EtapasGeneracion == nro_etapa) = [];
                    end
                    this.EtapasTransmision(this.EtapasTransmision == nro_etapa) = [];
                    this.EtapasGeneracion(this.EtapasGeneracion == nro_etapa) = [];
                else
                    error = MException('cPlanExpansionGxTx:desecha_plan','nro etapa no coincide con último plan guardado');
                    throw(error)
                end
                this.ResultadoEvaluacion(nro_etapa) = [];
            end
            %this.reinicia_sep_actual();
        end

        function desecha_plan_tx(this, varargin)
            % nargin indica la etapa a desechar
            this.CantidadReparaciones = 0;
            if nargin < 2
                % desecha plan completo
                this.ProyTransmision = [];
                this.EtapasTransmision = [];
                this.NombresTransmision = cell(1,0);
                this.CantidadVecesDesechadoTotal = this.CantidadVecesDesechadoTotal +1;
                this.CantidadVecesDesechadoEtapa = 0;
                this.ResultadoEvaluacion = [];
            else
                nro_etapa = varargin{1};
                ultima_etapa = max(this.EtapasTransmision);
                if nro_etapa == ultima_etapa
                    this.ProyTransmision(this.EtapasTransmision == nro_etapa) = [];
                    if ~isempty(this.NombresTransmision)
                        this.NombresTransmision(this.EtapasTransmision == nro_etapa) = [];
                    end
                    this.EtapasTransmision(this.EtapasTransmision == nro_etapa) = [];
                else
                    error = MException('cPlanExpansionGxTx:desecha_plan','nro etapa no coincide con último plan guardado');
                    throw(error)
                end
                this.ResultadoEvaluacion(nro_etapa) = [];
            end
            %this.reinicia_sep_actual();
        end

        function desecha_plan_gx(this, varargin)
            % nargin indica la etapa a desechar
            this.CantidadReparaciones = 0;
            if nargin < 2
                % desecha plan completo
                this.ProyGeneracion = [];
                this.EtapasGeneracion = [];
                this.NombresGeneracion = cell(1,0);
                this.CantidadVecesDesechadoTotal = this.CantidadVecesDesechadoTotal +1;
                this.CantidadVecesDesechadoEtapa = 0;
                this.ResultadoEvaluacion = [];
            else
                nro_etapa = varargin{1};
                ultima_etapa = max(this.EtapasGeneracion);
                if nro_etapa == ultima_etapa
                    this.ProyGeneracion(this.EtapasGeneracion == nro_etapa) = [];
                    if ~isempty(this.NombresGeneracion)
                        this.NombresGeneracion(this.EtapasGeneracion == nro_etapa) = [];
                    end
                    this.EtapasGeneracion(this.EtapasGeneracion == nro_etapa) = [];
                else
                    error = MException('cPlanExpansionGxTx:desecha_plan','nro etapa no coincide con último plan guardado');
                    throw(error)
                end
                this.ResultadoEvaluacion(nro_etapa) = [];
            end
            %this.reinicia_sep_actual();
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
        
        function existe = proyecto_tx_existe(this, indice_proyecto, varargin)
            %varargin indica el número de etapa
            if nargin >2
                nro_etapa = varargin{1};
                existe = ismember(indice_proyecto, this.ProyTransmision(this.EtapasTransmision == nro_etapa));
                return
            else
                existe = ismember(indice_proyecto, this.ProyTransmision);
            end
        end

        function existe = proyecto_gx_existe(this, indice_proyecto, varargin)
            %varargin indica el número de etapa
            if nargin >2
                nro_etapa = varargin{1};
                existe = ismember(indice_proyecto, this.ProyGeneracion(this.EtapasGeneracion == nro_etapa));
                return
            else
                existe = ismember(indice_proyecto, this.ProyGeneracion);
            end
        end
        
        function [id_proy_existentes, etapas] = entrega_proyectos_tx_implementados_de_lista_a_partir_de_etapa(this, indice_proyectos, etapa_inicial)
            id_etapas_validas = this.EtapasTransmision >= etapa_inicial;
            id_proyectos_validos = ismember(this.ProyTransmision, indice_proyectos);
            
            id_proy_existentes = this.ProyTransmision(id_etapas_validas & id_proyectos_validos);
            if isempty(id_proy_existentes)
                id_proy_existentes = [];
                etapas = [];
            else
                etapas = this.EtapasTransmision(id_etapas_validas & id_proyectos_validos);
            end
        end

        function [id_proy_existentes, etapas] = entrega_proyectos_gx_implementados_de_lista_a_partir_de_etapa(this, indice_proyectos, etapa_inicial)
            id_etapas_validas = this.EtapasGeneracion >= etapa_inicial;
            id_proyectos_validos = ismember(this.ProyGeneracion, indice_proyectos);
            
            id_proy_existentes = this.ProyGeneracion(id_etapas_validas & id_proyectos_validos);
            if isempty(id_proy_existentes)
                id_proy_existentes = [];
                etapas = [];
            else
                etapas = this.EtapasGeneracion(id_etapas_validas & id_proyectos_validos);
            end
        end
        
        function id_proy_implementados = entrega_proyectos_tx_implementados_de_lista_en_etapa(this, indice_proyectos, etapa)
            id_etapas_validas = this.EtapasTransmision == etapa;
            id_proyectos_validos = ismember(this.ProyTransmision, indice_proyectos);
            
            id_proy_implementados = this.ProyTransmision(id_etapas_validas & id_proyectos_validos);
        end

        function id_proy_implementados = entrega_proyectos_gx_implementados_de_lista_en_etapa(this, indice_proyectos, etapa)
            id_etapas_validas = this.EtapasGeneracion == etapa;
            id_proyectos_validos = ismember(this.ProyGeneracion, indice_proyectos);
            
            id_proy_implementados = this.ProyGeneracion(id_etapas_validas & id_proyectos_validos);
        end
        
        function etapas = entrega_etapas_implementacion_proyectos_tx_de_lista(this, proyectos, varargin)
            % varargin indica etapa inicial
            % si proyecto de lista no ha sido implementado, etapa = 0
            if nargin > 2
                etapa_inicial = varargin{1};
            else
                etapa_inicial = 1;
            end
            
            [~,pos] = ismember(proyectos, this.ProyTransmision);
            etapas = this.EtapasTransmision(pos);
            etapas(etapas < etapa_inicial) = 0;
            if isempty(etapas)
                etapas = 0;
            end
        end

        function etapas = entrega_etapas_implementacion_proyectos_gx_de_lista(this, proyectos, varargin)
            % varargin indica etapa inicial
            % si proyecto de lista no ha sido implementado, etapa = 0
            if nargin > 2
                etapa_inicial = varargin{1};
            else
                etapa_inicial = 1;
            end
            id_etapas_validas = this.EtapasGeneracion >= etapa_inicial;
            id_proyectos_validos = ismember(this.ProyGeneracion, proyectos);
            
            etapas = this.EtapasGeneracion(id_etapas_validas & id_proyectos_validos);
            if isempty(etapas)
                etapas = 0;
            end
        end
        
        function [id_proy, nro_etapa] = entrega_ultimo_proyecto_tx_realizado_de_grupo(this, id_proyectos)
            id = find(ismember(this.ProyTransmision, id_proyectos),1,'last');
            if ~isempty(id)
                id_proy = this.ProyTransmision(id);
                nro_etapa = this.EtapasTransmision(id);
            else
                id_proy = 0;
                nro_etapa = 0;
            end
        end
        
        function [id_proy, nro_etapa] = entrega_ultimo_proyecto_gx_realizado_de_grupo(this, id_proyectos)
            id = find(ismember(this.ProyGeneracion, id_proyectos),1,'last');
            if ~isempty(id)
                id_proy = this.ProyGeneracion(id);
                nro_etapa = this.EtapasGeneracion(id);
            else
                id_proy = 0;
                nro_etapa = 0;
            end
        end

        
        function id_proy = entrega_primer_proyecto_tx_realizado_de_grupo_y_etapa(this, id_proyectos, etapa)
            proy_etapa = this.ProyTransmision(this.EtapasTransmision == etapa);
            id_proy = proy_etapa(find(ismember(proy_etapa, id_proyectos),1,'first'));
            if isempty(id_proy)
                error = MException('cPlanExpansionGxTx:entrega_primer_proyecto_tx_realizado_de_grupo_y_etapa','Error de programación. Ningun proyecto indicado se encuentra en el plan');
                throw(error)
            end
        end

        function id_proy = entrega_primer_proyecto_gx_realizado_de_grupo_y_etapa(this, id_proyectos, etapa)
            proy_etapa = this.ProyGeneracion(this.EtapasGeneracion == etapa);
            id_proy = proy_etapa(find(ismember(proy_etapa, id_proyectos),1,'first'));
            if isempty(id_proy)
                error = MException('cPlanExpansionGxTx:entrega_primer_proyecto_gx_realizado_de_grupo_y_etapa','Error de programación. Ningun proyecto indicado se encuentra en el plan');
                throw(error)
            end
        end
        
        function id_proy = entrega_ultimo_proyecto_tx_realizado_de_grupo_y_etapa(this, id_proyectos, etapa)
            proy_etapa = this.ProyTransmision(this.EtapasTransmision == etapa);
            id_proy = proy_etapa(find(ismember(proy_etapa, id_proyectos),1,'last'));
            if isempty(id_proy)
                error = MException('cPlanExpansionGxTx:entrega_ultimo_proyecto_tx_realizado_de_grupo_y_etapa','Error de programación. Ningun proyecto indicado se encuentra en el plan');
                throw(error)
            end
        end

        function id_proy = entrega_ultimo_proyecto_gx_realizado_de_grupo_y_etapa(this, id_proyectos, etapa)
            proy_etapa = this.ProyGeneracion(this.EtapasGeneracion == etapa);
            id_proy = proy_etapa(find(ismember(proy_etapa, id_proyectos),1,'last'));
            if isempty(id_proy)
                error = MException('cPlanExpansionGxTx:entrega_ultimo_proyecto_gx_realizado_de_grupo_y_etapa','Error de programación. Ningun proyecto indicado se encuentra en el plan');
                throw(error)
            end
        end
        
        function existe = proyecto_tx_existe_acumulado(this, indice_proyecto, nro_etapa_final)
            existe = ismember(indice_proyecto, this.ProyTransmision(this.EtapasTransmision <= nro_etapa_final));
        end

        function existe = proyecto_gx_existe_acumulado(this, indice_proyecto, nro_etapa_final)
            existe = ismember(indice_proyecto, this.ProyGeneracion(this.EtapasGeneracion <= nro_etapa_final));
        end
        
        function etapa = entrega_etapa_proyecto_tx(this, indice_proyecto, varargin)
            %varargin indica si se entrega error en caso de que proyecto no
            %esté en el plan
            if nargin > 2
                con_error = varargin{1};
            else
                con_error = true;
            end
            etapa = this.EtapasTransmision(this.ProyTransmision == indice_proyecto);
            if isempty(etapa)
                etapa = 0;
                if con_error
                    error = MException('cPlanExpansionGxTx:entrega_etapa_proyecto_tx',['Error de programación. Proyecto ' num2str(indice_proyecto) ' no se encuentra en el plan']);
                    throw(error)
                end
            end
        end

        function etapa = entrega_etapa_proyecto_gx(this, indice_proyecto, varargin)
            %varargin indica si se entrega error en caso de que proyecto no
            %esté en el plan
            if nargin > 2
                con_error = varargin{1};
            else
                con_error = true;
            end
            etapa = this.EtapasGeneracion(this.ProyGeneracion == indice_proyecto);
            if isempty(etapa)
                etapa = 0;
                if con_error
                    error = MException('cPlanExpansionGxTx:entrega_etapa_proyecto_gx',['Error de programación. Proyecto ' num2str(indice_proyecto) ' no se encuentra en el plan']);
                    throw(error)
                end
            end
        end
        
        function [existe, nro_etapa] = dependencia_tx_existe(this, indice_proyectos_dependientes)
            id = find(ismember(this.ProyTransmision, indice_proyectos_dependientes),1);
            if ~isempty(id)
                existe = true;
                nro_etapa = this.EtapasTransmision(id);
            else
                existe = true;
                nro_etapa = 0;
            end
        end

        function [existe, nro_etapa] = dependencia_gx_existe(this, indice_proyectos_dependientes)
            id = find(ismember(this.ProyGeneracion, indice_proyectos_dependientes),1);
            if ~isempty(id)
                existe = true;
                nro_etapa = this.EtapasGeneracion(id);
            else
                existe = true;
                nro_etapa = 0;
            end
        end
        
        function [proy, etapa]= entrega_proyecto_tx_dependiente(this, indice_proyectos_dependientes, varargin)
            %varargin indica si es con o sin error
            con_error = true;
            if nargin > 2
                con_error = varargin{1};
            end
            id = find(ismember(this.ProyTransmision, indice_proyectos_dependientes),1);
            if ~isempty(id)
                proy = this.ProyTransmision(id);
                etapa = this.EtapasTransmision(id);
            else
                proy = true;
                etapa = 0;
                if con_error
                    texto = '';
                    for i = 1:length(indice_proyectos_dependientes)
                        texto = [texto ' ' num2str(indice_proyectos_dependientes(i))];
                    end
                    error = MException('cPlanExpansionGxTx:entrega_proyecto_dependiente',['Error de programación. Proyecto(s) dependiente(s) no se encuentran en plan. Proyectos: ' texto]);
                    throw(error)
                end
            end
        end

        function [proy, etapa]= entrega_proyecto_gx_dependiente(this, indice_proyectos_dependientes, varargin)
            %varargin indica si es con o sin error
            con_error = true;
            if nargin > 2
                con_error = varargin{1};
            end
            id = find(ismember(this.ProyGeneracion, indice_proyectos_dependientes),1);
            if ~isempty(id)
                proy = this.ProyGeneracion(id);
                etapa = this.EtapasGeneracion(id);
            else
                proy = true;
                etapa = 0;
                if con_error
                    texto = '';
                    for i = 1:length(indice_proyectos_dependientes)
                        texto = [texto ' ' num2str(indice_proyectos_dependientes(i))];
                    end
                    error = MException('cPlanExpansionGxTx:entrega_proyecto_dependiente',['Error de programación. Proyecto(s) dependiente(s) no se encuentran en plan. Proyectos: ' texto]);
                    throw(error)
                end
            end
        end
        
        function [proy, etapa]= entrega_proyectos_tx_y_etapa_de_lista(this, indice_proyectos)
            id_proyectos_validos = ismember(this.ProyTransmision, indice_proyectos);
            proy = this.ProyTransmision(id_proyectos_validos);            
            if ~isempty(proy)
                etapa = this.EtapasTransmision(id_proyectos_validos);
            else
                proy = [];
                etapa = [];
            end
        end

        function [proy, etapa]= entrega_proyectos_gx_y_etapa_de_lista(this, indice_proyectos)
            id_proyectos_validos = ismember(this.ProyGeneracion, indice_proyectos);
            proy = this.ProyGeneracion(id_proyectos_validos);            
            if ~isempty(proy)
                etapa = this.EtapasGeneracion(id_proyectos_validos);
            else
                proy = [];
                etapa = [];
            end
        end
        
        function ultima_etapa = entrega_ultima_etapa_posible_modificacion_proyecto_tx(this, proy_aguas_arriba, desde_etapa)
            id_etapas_validas = this.EtapasTransmision >= desde_etapa;
            id_proy_validos = ismember(this.ProyTransmision, proy_aguas_arriba);
            ultima_etapa = this.EtapasTransmision(id_etapas_validas & id_proy_validos);
            if isempty(ultima_etapa)
                ultima_etapa = 0;
            end
        end

        function ultima_etapa = entrega_ultima_etapa_posible_modificacion_proyecto_gx(this, proy_aguas_arriba, desde_etapa)
            id_etapas_validas = this.EtapasGeneracion >= desde_etapa;
            id_proy_validos = ismember(this.ProyGeneracion, proy_aguas_arriba);
            ultima_etapa = this.EtapasGeneracion(id_etapas_validas & id_proy_validos);
            if isempty(ultima_etapa)
                ultima_etapa = 0;
            end
        end
        
        function etapas = entrega_etapas_con_proyectos_tx(this)
            if ~isempty(this.EtapasTransmision)
                etapas = unique(this.EtapasTransmision);
            else
                etapas = [];
            end
        end

        function etapas = entrega_etapas_con_proyectos_gx(this)
            if ~isempty(this.EtapasGeneracion)
                etapas = unique(this.EtapasGeneracion);
            else
                etapas = [];
            end
        end
        
        function existe = proyecto_tx_excluyente_existe(this, indice_proyectos_excluyentes)
            existe = ~isempty(find(ismember(indice_proyectos_excluyentes, this.ProyTransmision), 1));
        end
        
        function existe = conectividad_tx_existe(this, indice_proyectos_conectividad)
            existe = ~isempty(find(ismember(indice_proyectos_conectividad, this.ProyTransmision), 1));
        end
        
        function [proy, etapa]= entrega_proyecto_conectividad_tx_y_etapa(this, indice_proyectos_conectividad)
            id = find(ismember(this.ProyTransmision, indice_proyectos_conectividad), 1,'first');
            if ~isempty(id)
                proy = this.ProyTransmision(id);
                etapa = this.EtapasTransmision(id);
            else
                etapa = 0;
                proy = 0;
            end
        end

        function proyectos = entrega_proyectos(this, varargin)
            % varargin indica la etapa
            if nargin > 1
                etapa = varargin{1};
                proyectos = [this.ProyTransmision(this.EtapasTransmision == etapa) this.ProyGeneracion(this.EtapasGeneracion == etapa)];
            else
                proyectos = [this.ProyTransmision this.ProyGeneracion];
            end
        end
        
        function proyectos = entrega_proyectos_tx(this, varargin)
            % varargin indica la etapa
            if nargin > 1
                etapa = varargin{1};
                proyectos = this.ProyTransmision(this.EtapasTransmision == etapa);
            else
                proyectos = this.ProyTransmision;
            end
        end

        function proyectos = entrega_proyectos_gx(this, varargin)
            % varargin indica la etapa
            if nargin > 1
                etapa = varargin{1};
                proyectos = this.ProyGeneracion(this.EtapasGeneracion == etapa);
            else
                proyectos = this.ProyGeneracion;
            end
        end

        function cantidad = entrega_cantidad_proyectos_etapa(this, nro_etapa)
            cantidad = length(this.ProyTransmision(this.EtapasTransmision == nro_etapa)) + ...
                length(this.ProyGeneracion(this.EtapasGeneracion == nro_etapa));
        end
        
        function cantidad = entrega_cantidad_proyectos_tx_etapa(this, nro_etapa)
            cantidad = length(this.ProyTransmision(this.EtapasTransmision == nro_etapa));
        end

        function cantidad = entrega_cantidad_proyectos_gx_etapa(this, nro_etapa)
            cantidad = length(this.ProyGeneracion(this.EtapasGeneracion == nro_etapa));
        end
        
        function [proyectos, etapas]= entrega_proyectos_tx_y_etapas(this)
            proyectos = this.ProyTransmision;
            etapas = this.EtapasTransmision;
        end

        function [proyectos, etapas]= entrega_proyectos_gx_y_etapas(this)
            proyectos = this.ProyTransmision;
            etapas = this.EtapasTransmision;
        end

        function [proyectos, etapas]= entrega_proyectos_y_etapas(this)
            proyectos = [this.ProyGeneracion this.ProyTransmision];
            etapas = [this.EtapasGeneracion this.EtapasTransmision];
        end
        
        function proyectos = entrega_proyectos_acumulados(this, nro_etapa)
            proyectos = [this.ProyGeneracion(this.EtapasGeneracion <= nro_etapa) this.ProyTransmision(this.EtapasTransmision <= nro_etapa)];
        end

        function proyectos = entrega_proyectos_tx_acumulados(this, nro_etapa)
            proyectos = this.ProyTransmision(this.EtapasTransmision <= nro_etapa);
        end

        function proyectos = entrega_proyectos_gx_acumulados(this, nro_etapa)
            proyectos = this.ProyGeneracion(this.EtapasGeneracion <= nro_etapa);
        end
        
        function proyectos = entrega_proyectos_acumulados_desde_hasta_etapa(this, desde_etapa, hasta_etapa)
            proyectos = [this.ProyGeneracion(this.EtapasGeneracion >= desde_etapa & this.EtapasGeneracion <= hasta_etapa) ...
                this.ProyTransmision(this.EtapasTransmision >= desde_etapa & this.EtapasTransmision <= hasta_etapa)];
        end

        function proyectos = entrega_proyectos_tx_acumulados_desde_hasta_etapa(this, desde_etapa, hasta_etapa)
            proyectos = this.ProyTransmision(this.EtapasTransmision >= desde_etapa & this.EtapasTransmision <= hasta_etapa);
        end

        function proyectos = entrega_proyectos_gx_acumulados_desde_hasta_etapa(this, desde_etapa, hasta_etapa)
            proyectos = this.ProyGeneracion(this.EtapasGeneracion >= desde_etapa & this.EtapasGeneracion <= hasta_etapa);
        end
        
        function [proyectos, etapas] = entrega_proyectos_acumulados_y_etapas_a_partir_de_etapa(this, nro_etapa)
            proyectos = [this.ProyGeneracion(this.EtapasGeneracion >= nro_etapa) this.ProyTransmision(this.EtapasTransmision >= nro_etapa)];
            etapas = [this.EtapasGeneracion(this.EtapasGeneracion >= nro_etapa) this.EtapasTransmision(this.EtapasTransmision >= nro_etapa)];
        end

        function [proyectos, etapas] = entrega_proyectos_tx_acumulados_y_etapas_a_partir_de_etapa(this, nro_etapa)
            proyectos = this.ProyTransmision(this.EtapasTransmision >= nro_etapa);
            etapas = this.EtapasTransmision(this.EtapasTransmision >= nro_etapa);
        end

        function [proyectos, etapas] = entrega_proyectos_gx_acumulados_y_etapas_a_partir_de_etapa(this, nro_etapa)
            proyectos = this.ProyGeneracion(this.EtapasGeneracion >= nro_etapa);
            etapas = this.EtapasGeneracion(this.EtapasGeneracion >= nro_etapa);
        end
        
        function [proyectos, etapas] = entrega_proyectos_acumulados_y_etapas(this, nro_etapa)
            proyectos = [this.ProyGeneracion(this.EtapasGeneracion <= nro_etapa) this.ProyTransmision(this.EtapasTransmision <= nro_etapa)];
            etapas = [this.EtapasGeneracion(this.EtapasGeneracion <= nro_etapa) this.EtapasTransmision(this.EtapasTransmision <= nro_etapa)];
        end

        function [proyectos, etapas] = entrega_proyectos_tx_acumulados_y_etapas(this, nro_etapa)
            proyectos = this.ProyTransmision(this.EtapasTransmision <= nro_etapa);
            etapas = this.EtapasTransmision(this.EtapasTransmision <= nro_etapa);
        end
        
        function [proyectos, etapas] = entrega_proyectos_gx_acumulados_y_etapas(this, nro_etapa)
            proyectos = this.ProyGeneracion(this.EtapasGeneracion <= nro_etapa);
            etapas = this.EtapasGeneracion(this.EtapasGeneracion <= nro_etapa);
        end
        
        function iguales = compara_proyectos(this, plan, varargin)
            iguales = compara_proyectos_tx(this, plan, varargin);
            if iguales
                iguales = compara_proyectos_gx(this, plan, varargin);
            end
        end
        
        function iguales = compara_proyectos_tx(this, plan, varargin)
            debug = false;
            if nargin > 2
                debug = varargin{1};
            end
            
            %primero determina si número de etapas coincide
            if length(this.ProyTransmision) ~= length(plan.ProyTransmision)
                iguales = false;
            else
                [proy_act_sort, id_act_sort] = sort(this.ProyTransmision);
                etapas_act_sort = this.EtapasTransmision(id_act_sort);

                [proy_plan_sort, id_plan_sort] = sort(plan.ProyTransmision);
                etapas_plan_sort = plan.EtapasTransmision(id_plan_sort);

                if proy_act_sort ~= proy_plan_sort || etapas_act_sort ~= etapas_plan_sort
                    iguales = false;
                else
                    iguales = true;
                    return
                end
            end

            if debug
                disp('Planes no son iguales');
                if length(this.ProyTransmision) ~= length(plan.ProyTransmision)
                    disp('Cantidad de proyectos transmisión implementados es distinta')
                else
                    disp('Proyectos y/o etapas son distintos')
                    [proy_mejor_plan etapas_mejor_plan]= [proy_act_sort etapas_act_sort]
                    [proy_plan_optimo etapas_plan_optimo] = [proy_plan_sort etapas_plan_sort]
                    error = MException('cPlanExpansionGxTx:compara_proyectos','Proyectos no son iguales pero flag de debug está activa');
                    throw(error)
                end
            end
        end

        function iguales = compara_proyectos_gx(this, plan, varargin)
            debug = false;
            if nargin > 2
                debug = varargin{1};
            end
            
            %primero determina si número de etapas coincide
            if length(this.ProyGeneracion) ~= length(plan.ProyGeneracion)
                iguales = false;
            else
                [proy_act_sort, id_act_sort] = sort(this.ProyGeneracion);
                etapas_act_sort = this.EtapasGeneracion(id_act_sort);

                [proy_plan_sort, id_plan_sort] = sort(plan.ProyGeneracion);
                etapas_plan_sort = plan.EtapasGeneracion(id_plan_sort);

                if proy_act_sort ~= proy_plan_sort || etapas_act_sort ~= etapas_plan_sort
                    iguales = false;
                else
                    iguales = true;
                    return
                end
            end

            if debug
                disp('Planes no son iguales');
                if length(this.ProyGeneracion) ~= length(plan.ProyGeneracion)
                    disp('Cantidad de proyectos generación implementados es distinta')
                else
                    disp('Proyectos y/o etapas son distintos')
                    [proy_mejor_plan etapas_mejor_plan]= [proy_act_sort etapas_act_sort]
                    [proy_plan_optimo etapas_plan_optimo] = [proy_plan_sort etapas_plan_sort]
                    error = MException('cPlanExpansionGxTx:compara_proyectos','Proyectos no son iguales pero flag de debug está activa');
                    throw(error)
                end
            end
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

            
            prot.imprime_texto('\nProyectos Tx');
            if this.NombresDisponibles
                texto = sprintf('%-7s %-7s %-50s', 'Etapa', 'Proy.', 'Nombre');
            else
                texto = sprintf('%-7s %-7s', 'Etapa', 'Proy.');
            end
            prot.imprime_texto(texto);

            etapa_actual = 0;
            for i = 1:length(this.ProyTransmision)
                etapa_proy = this.EtapasTransmision(i);
                id_proy = num2str(this.ProyTransmision(i));
                if etapa_proy ~= etapa_actual
                    primero = true;
                    etapa_actual = etapa_proy;
                else
                    primero = false;
                end
                
                if this.NombresDisponibles
                    nombre_proy = this.NombresTransmision{i};
                    if primero
                        texto = sprintf('%-7s %-7s %-50s', num2str(etapa_actual), id_proy, nombre_proy);
                    else
                        texto = sprintf('%-7s %-7s %-50s', '', id_proy, nombre_proy);
                    end
                else
                    if primero
                        texto = sprintf('%-7s %-7s', num2str(etapa_actual), id_proy);
                    else
                        texto = sprintf('%-7s %-7s', '', id_proy);
                    end
                end
                prot.imprime_texto(texto);
            end

            prot.imprime_texto('\nProyectos Gx');
            if this.NombresDisponibles
                texto = sprintf('%-7s %-7s %-50s', 'Etapa', 'Proy.', 'Nombre');
            else
                texto = sprintf('%-7s %-7s', 'Etapa', 'Proy.');
            end
            prot.imprime_texto(texto);

            etapa_actual = 0;
            for i = 1:length(this.ProyGeneracion)
                etapa_proy = this.EtapasGeneracion(i);
                id_proy = num2str(this.ProyGeneracion(i));
                if etapa_proy ~= etapa_actual
                    primero = true;
                    etapa_actual = etapa_proy;
                else
                    primero = false;
                end
                
                if this.NombresDisponibles
                    nombre_proy = this.NombresGeneracion{i};
                    if primero
                        texto = sprintf('%-7s %-7s %-50s', num2str(etapa_actual), id_proy, nombre_proy);
                    else
                        texto = sprintf('%-7s %-7s %-50s', '', id_proy, nombre_proy);
                    end
                else
                    if primero
                        texto = sprintf('%-7s %-7s', num2str(etapa_actual), id_proy);
                    else
                        texto = sprintf('%-7s %-7s', '', id_proy);
                    end
                end
                prot.imprime_texto(texto);
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

            prot.imprime_texto('\nProyectos Tx');
            if this.NombresDisponibles
                texto = sprintf('%-7s %-7s %-50s', 'Etapa', 'Proy.', 'Nombre');
            else
                texto = sprintf('%-7s %-7s', 'Etapa', 'Proy.');
            end
            prot.imprime_texto(texto);
            
            etapa_actual = 0;
            for i = 1:length(this.ProyTransmision)
                etapa_proy = this.EtapasTransmision(i);
                id_proy = num2str(this.ProyTransmision(i));
                if etapa_proy ~= etapa_actual
                    primero = true;
                    etapa_actual = etapa_proy;
                else
                    primero = false;
                end
                
                if this.NombresDisponibles
                    nombre_proy = this.NombresTransmision{i};
                    if primero
                        texto = sprintf('%-7s %-7s %-50s', num2str(etapa_actual), id_proy, nombre_proy);
                    else
                        texto = sprintf('%-7s %-7s %-50s', '', id_proy, nombre_proy);
                    end
                else
                    if primero
                        texto = sprintf('%-7s %-7s', num2str(etapa_actual), id_proy);
                    else
                        texto = sprintf('%-7s %-7s', '', id_proy);
                    end
                end
                prot.imprime_texto(texto);
            end

            prot.imprime_texto('\nProyectos Gx');
            if this.NombresDisponibles
                texto = sprintf('%-7s %-7s %-50s', 'Etapa', 'Proy.', 'Nombre');
            else
                texto = sprintf('%-7s %-7s', 'Etapa', 'Proy.');
            end
            prot.imprime_texto(texto);
            
            etapa_actual = 0;
            for i = 1:length(this.ProyGeneracion)
                etapa_proy = this.EtapasGeneracion(i);
                id_proy = num2str(this.ProyGeneracion(i));
                if etapa_proy ~= etapa_actual
                    primero = true;
                    etapa_actual = etapa_proy;
                else
                    primero = false;
                end
                
                if this.NombresDisponibles
                    nombre_proy = this.NombresGeneracion{i};
                    if primero
                        texto = sprintf('%-7s %-7s %-50s', num2str(etapa_actual), id_proy, nombre_proy);
                    else
                        texto = sprintf('%-7s %-7s %-50s', '', id_proy, nombre_proy);
                    end
                else
                    if primero
                        texto = sprintf('%-7s %-7s', num2str(etapa_actual), id_proy);
                    else
                        texto = sprintf('%-7s %-7s', '', id_proy);
                    end
                end
                prot.imprime_texto(texto);
            end
            
        end

        function texto_completo = entrega_texto_plan_expansion(this)

            texto_completo = ['Plannr =' num2str(this.NroPlan) '\n'];
            texto_completo = [texto_completo 'Proyectos Tx\n'];
            if this.NombresDisponibles
                texto = sprintf('%-7s %-7s %-50s', 'Etapa', 'Proy.', 'Nombre');
            else
                texto = sprintf('%-7s %-7s', 'Etapa', 'Proy.');
            end
            texto_completo = [texto_completo texto '\n'];
            
            etapa_actual = 0;
            for i = 1:length(this.ProyTransmision)
                etapa_proy = this.EtapasTransmision(i);
                id_proy = num2str(this.ProyTransmision(i));
                if etapa_proy ~= etapa_actual
                    primero = true;
                    etapa_actual = etapa_proy;
                else
                    primero = false;
                end
                
                if this.NombresDisponibles
                    nombre_proy = this.NombresTransmision{i};
                    if primero
                        texto = sprintf('%-7s %-7s %-50s', num2str(etapa_actual), id_proy, nombre_proy);
                    else
                        texto = sprintf('%-7s %-7s %-50s', '', id_proy, nombre_proy);
                    end
                else
                    if primero
                        texto = sprintf('%-7s %-7s', num2str(etapa_actual), id_proy);
                    else
                        texto = sprintf('%-7s %-7s', '', id_proy);
                    end
                end
            end
            
            texto_completo = [texto_completo 'Proyectos Gx\n'];
            if this.NombresDisponibles
                texto = sprintf('%-7s %-7s %-50s', 'Etapa', 'Proy.', 'Nombre');
            else
                texto = sprintf('%-7s %-7s', 'Etapa', 'Proy.');
            end
            texto_completo = [texto_completo texto '\n'];
            
            etapa_actual = 0;
            for i = 1:length(this.ProyGeneracion)
                etapa_proy = this.EtapasGeneracion(i);
                id_proy = num2str(this.ProyGeneracion(i));
                if etapa_proy ~= etapa_actual
                    primero = true;
                    etapa_actual = etapa_proy;
                else
                    primero = false;
                end
                
                if this.NombresDisponibles
                    nombre_proy = this.NombresGeneracion{i};
                    if primero
                        texto = sprintf('%-7s %-7s %-50s', num2str(etapa_actual), id_proy, nombre_proy);
                    else
                        texto = sprintf('%-7s %-7s %-50s', '', id_proy, nombre_proy);
                    end
                else
                    if primero
                        texto = sprintf('%-7s %-7s', num2str(etapa_actual), id_proy);
                    else
                        texto = sprintf('%-7s %-7s', '', id_proy);
                    end
                end
            end
        end
        
        function imprime_hasta_etapa(this, nro_etapa)
            
            prot = cProtocolo.getInstance;
            texto = ['Plannr =' num2str(this.NroPlan)];
            prot.imprime_texto(texto);

            prot.imprime_texto('\nProyectos Tx');
            if this.NombresDisponibles
                texto = sprintf('%-7s %-7s %-50s', 'Etapa', 'Proy.', 'Nombre');
            else
                texto = sprintf('%-7s %-7s', 'Etapa', 'Proy.');
            end
            prot.imprime_texto(texto);
            
            etapa_actual = 0;
            for i = 1:length(this.ProyTransmision)
                etapa_proy = this.EtapasTransmision(i);
                if etapa_proy > nro_etapa
                    break
                end
                id_proy = num2str(this.ProyTransmision(i));
                if etapa_proy ~= etapa_actual
                    primero = true;
                    etapa_actual = etapa_proy;
                else
                    primero = false;
                end
                
                if this.NombresDisponibles
                    nombre_proy = this.NombresTransmision{i};
                    if primero
                        texto = sprintf('%-7s %-7s %-50s', num2str(etapa_actual), id_proy, nombre_proy);
                    else
                        texto = sprintf('%-7s %-7s %-50s', '', id_proy, nombre_proy);
                    end
                else
                    if primero
                        texto = sprintf('%-7s %-7s', num2str(etapa_actual), id_proy);
                    else
                        texto = sprintf('%-7s %-7s', '', id_proy);
                    end
                end
                prot.imprime_texto(texto);
            end

            prot.imprime_texto('\nProyectos Gx');
            if this.NombresDisponibles
                texto = sprintf('%-7s %-7s %-50s', 'Etapa', 'Proy.', 'Nombre');
            else
                texto = sprintf('%-7s %-7s', 'Etapa', 'Proy.');
            end
            prot.imprime_texto(texto);
            
            etapa_actual = 0;
            for i = 1:length(this.ProyGeneracion)
                etapa_proy = this.EtapasGeneracion(i);
                if etapa_proy > nro_etapa
                    break
                end
                id_proy = num2str(this.ProyGeneracion(i));
                if etapa_proy ~= etapa_actual
                    primero = true;
                    etapa_actual = etapa_proy;
                else
                    primero = false;
                end
                
                if this.NombresDisponibles
                    nombre_proy = this.NombresGeneracion{i};
                    if primero
                        texto = sprintf('%-7s %-7s %-50s', num2str(etapa_actual), id_proy, nombre_proy);
                    else
                        texto = sprintf('%-7s %-7s %-50s', '', id_proy, nombre_proy);
                    end
                else
                    if primero
                        texto = sprintf('%-7s %-7s', num2str(etapa_actual), id_proy);
                    else
                        texto = sprintf('%-7s %-7s', '', id_proy);
                    end
                end
                prot.imprime_texto(texto);
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
            
            prot.imprime_texto('\nProyectos Tx');
            texto = sprintf('%-7s %-7s %-13s %-13s %-13s %-13s %-50s', 'Etapa', 'Proy.', 'C.Inv', 'Cum etapa', 'C.Inv. Act', 'Cum etapa', 'Nombre');
            prot.imprime_texto(texto);

            q = (1 + paropt.TasaDescuento);
            detapa = paropt.DeltaEtapa;
            cum = 0;
            cum_actual = 0;
            etapa_actual = 0;
            for i = 1:length(this.ProyTransmision)
                etapa_proy = this.EtapasTransmision(i);
                if etapa_proy ~= etapa_actual
                    etapa_actual = etapa_proy;
                    cum_etapa = 0;
                    cum_actual_etapa = 0;
                    primero = true;
                else
                    primero = false;
                end
                id_proy = num2str(this.ProyTransmision(i));
                nombre_proy = this.NombresTransmision{i};
                indice = this.ProyTransmision(i);
                costo_inv = adm_proy.ProyTransmision(indice).entrega_costos_inversion();
                factor_desarrollo = paropt.entrega_factor_costo_desarrollo_proyectos();
                costo_inv = round(costo_inv*factor_desarrollo,5);
                costo_inv_act = costo_inv/q^(detapa*i);
                cum_etapa = cum_etapa + costo_inv;
                cum_actual_etapa = cum_actual_etapa + costo_inv_act;
                cum = cum + costo_inv;
                cum_actual = cum_actual + costo_inv_act;
                if primero
                    texto_etapa = num2str(etapa_actual);
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

            prot.imprime_texto('\nProyectos Gx');
            texto = sprintf('%-7s %-7s %-13s %-13s %-13s %-13s %-50s', 'Etapa', 'Proy.', 'C.Inv', 'Cum etapa', 'C.Inv. Act', 'Cum etapa', 'Nombre');
            prot.imprime_texto(texto);

            q = (1 + paropt.TasaDescuento);
            detapa = paropt.DeltaEtapa;
            cum = 0;
            cum_actual = 0;
            etapa_actual = 0;
            for i = 1:length(this.ProyGeneracion)
                etapa_proy = this.EtapasGeneracion(i);
                if etapa_proy ~= etapa_actual
                    cum_etapa = 0;
                    cum_actual_etapa = 0;
                    primero = true;
                else
                    primero = false;
                end
                id_proy = num2str(this.ProyGeneracion(i));
                nombre_proy = this.NombresGeneracion{i};
                indice = this.ProyGeneracion(i);
                costo_inv = adm_proy.ProyGeneracion(indice).entrega_costos_inversion();
                factor_desarrollo = paropt.entrega_factor_costo_desarrollo_proyectos();
                costo_inv = round(costo_inv*factor_desarrollo,5);
                costo_inv_act = costo_inv/q^(detapa*i);
                cum_etapa = cum_etapa + costo_inv;
                cum_actual_etapa = cum_actual_etapa + costo_inv_act;
                cum = cum + costo_inv;
                cum_actual = cum_actual + costo_inv_act;
                if primero
                    texto_etapa = num2str(etapa_actual);
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
            this.NombresTransmision = cell(0,1);
            for i = 1:length(this.ProyTransmision)                
                indice_proyecto = this.ProyTransmision(i);
                proyecto = adm_pr.entrega_proyecto_tx(indice_proyecto);
                this.NombresTransmision{i} = proyecto.entrega_nombre();
            end

            this.NombresGeneracion = cell(0,1);
            for i = 1:length(this.ProyGeneracion)                
                indice_proyecto = this.ProyGeneracion(i);
                proyecto = adm_pr.entrega_proyecto_gx(indice_proyecto);
                this.NombresGeneracion{i} = proyecto.entrega_nombre();
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
            plan.ProyTransmision = this.ProyTransmision;
            plan.EtapasTransmision = this.EtapasTransmision;
            plan.ProyGeneracion = this.ProyGeneracion;
            plan.EtapasGeneracion = this.EtapasGeneracion;
        end
        
        function plan = inserta_plan_expansion(this, plan)
            this.ProyTransmision = plan.ProyTransmision;
            this.EtapasTransmision = plan.EtapasTransmision;
            this.ProyGeneracion = plan.ProyGeneracion;
            this.EtapasGeneracion = plan.EtapasGeneracion;
        end

        function plan = inserta_plan_expansion_tx(this, plan)
            this.ProyTransmision = plan.ProyTransmision;
            this.EtapasTransmision = plan.EtapasTransmision;
        end
        
        function plan = inserta_plan_expansion_gx(this, plan)
            this.ProyGeneracion = plan.ProyGeneracion;
            this.EtapasGeneracion = plan.EtapasGeneracion;
        end
        
        function totex = entrega_totex_total(this)
            totex = this.TotexTotal;
        end
        
        function elimina_proyectos_tx(this, proyectos, varargin)
            % varargin indica las etapas. En este caso, se verifica que etapas coincidan. 
            %Si no se indica, entonces se busca en todas las etapas
            if nargin > 2
                etapas = varargin{1};
                [etapas, id_etapas] = sort(etapas);
                proyectos = proyectos(id_etapas);
                id_eliminar = find(ismember(this.ProyTransmision, proyectos));
                if this.EtapasTransmision(id_eliminar) ~= etapas
                    error = MException('cPlanExpansionGxTx:elimina_proyectos','Error de programación. Proyectos a eliminar no coinciden con las etapas indicadas');
                    throw(error)
                end
            else
                id_eliminar = find(ismember(this.ProyTransmision, proyectos));
            end
            this.ProyTransmision(id_eliminar) = [];
            this.EtapasTransmision(id_eliminar) = [];
            
%            if this.NombresDisponibles
%                this.NombresTransmision(id_eliminar) = [];
%            end
        end
        
        function elimina_proyectos_gx(this, proyectos, varargin)
            % varargin indica las etapas. En este caso, se verifica que etapas coincidan. 
            %Si no se indica, entonces se busca en todas las etapas
            if nargin > 2
                etapas = varargin{1};
                [etapas, id_etapas] = sort(etapas);
                proyectos = proyectos(id_etapas);
                id_eliminar = find(ismember(this.ProyGeneracion, proyectos));
                if this.EtapasGeneracion(id_eliminar) ~= etapas
                    error = MException('cPlanExpansionGxTx:elimina_proyectos','Error de programación. Proyectos a eliminar no coinciden con las etapas indicadas');
                    throw(error)
                end
            else
                id_eliminar = find(ismember(this.ProyGeneracion, proyectos));
            end
            this.ProyGeneracion(id_eliminar) = [];
            this.EtapasGeneracion(id_eliminar) = [];
            
            if this.NombresDisponibles
                this.NombresGeneracion(id_eliminar) = [];
            end
        end
        
        function desplaza_proyectos_tx(this, proyectos, etapas_originales, etapas_desplazar)
            % cada proyecto se agrega al comienzo de la etapa desplazar
            for i = 1:length(proyectos)
                pos_proy = find(this.ProyTransmision == proyectos(i));
                if isempty(pos_proy) || this.EtapasTransmision(pos_proy) ~= etapas_originales(i)
                    error = MException('cPlanExpansionGxTx:desplaza_proyectos','Error de programación. Proyecto a desplazar no se encuentra o no se encuentra en etapa indicada');
                    throw(error)
                end
                
                this.ProyTransmision(pos_proy) = [];
                this.EtapasTransmision(pos_proy) = [];
                
                pos_nueva = find(this.EtapasTransmision >= etapas_desplazar(i), 1, 'first');
                if isempty(pos_nueva)
                    % proyecto se agrega al final del plan
                    this.ProyTransmision = [this.ProyTransmision proyectos(i)];
                    this.EtapasTransmision = [this.EtapasTransmision etapas_desplazar(i)];
                else
                    this.ProyTransmision = [this.ProyTransmision(1:pos_nueva-1) proyectos(i) this.ProyTransmision(pos_nueva:end)];
                    this.EtapasTransmision = [this.EtapasTransmision(1:pos_nueva-1) etapas_desplazar(i) this.EtapasTransmision(pos_nueva:end)];
                end
            end
        end
                
        function desplaza_proyectos_gx(this, proyectos, etapas_originales, etapas_desplazar)
            % cada proyecto se agrega al comienzo de la etapa desplazar
            for i = 1:length(proyectos)
                pos_proy = find(this.ProyGeneracion == proyectos(i));
                if isempty(pos_proy) || this.EtapasGeneracion(pos_proy) ~= etapas_originales(i)
                    error = MException('cPlanExpansionGxTx:desplaza_proyectos','Error de programación. Proyecto a desplazar no se encuentra o no se encuentra en etapa indicada');
                    throw(error)
                end
                
                this.ProyGeneracion(pos_proy) = [];
                this.EtapasGeneracion(pos_proy) = [];
                
                pos_nueva = find(this.EtapasGeneracion >= etapas_desplazar(i), 1, 'first');
                if isempty(pos_nueva)
                    % proyecto se agrega al final del plan
                    this.ProyGeneracion = [this.ProyGeneracion proyectos(i)];
                    this.EtapasGeneracion = [this.EtapasGeneracion etapas_desplazar(i)];
                else
                    this.ProyGeneracion = [this.ProyGeneracion(1:pos_nueva-1) proyectos(i) this.ProyGeneracion(pos_nueva:end)];
                    this.EtapasGeneracion = [this.EtapasGeneracion(1:pos_nueva-1) etapas_desplazar(i) this.EtapasGeneracion(pos_nueva:end)];
                end
            end
        end
        
        function adelanta_proyectos_tx(this, proyectos, etapas_originales, etapas_adelantar)
            % cada proyecto se agrega al final de la etapa a adelantar
            for i = 1:length(proyectos)                
                pos_proy = find(this.ProyTransmision == proyectos(i));
                if isempty(pos_proy) || this.EtapasTransmision(pos_proy) ~= etapas_originales(i)
                    disp('Aqui ocurre un error')
%                    error = MException('cPlanExpansionGxTx:desplaza_proyectos','Error de programación. Proyecto a desplazar no se encuentra o no se encuentra en etapa indicada');
%                    throw(error)
                end
                
                this.ProyTransmision(pos_proy) = [];
                this.EtapasTransmision(pos_proy) = [];
                
                pos_nueva = find(this.EtapasTransmision > etapas_adelantar(i), 1, 'first');
                if isempty(pos_nueva)
                    % proyecto se agrega al final del plan
                    this.ProyTransmision = [this.ProyTransmision proyectos(i)];
                    this.EtapasTransmision = [this.EtapasTransmision etapas_adelantar(i)];
                else
                    this.ProyTransmision = [this.ProyTransmision(1:pos_nueva-1) proyectos(i) this.ProyTransmision(pos_nueva:end)];
                    this.EtapasTransmision = [this.EtapasTransmision(1:pos_nueva-1) etapas_adelantar(i) this.EtapasTransmision(pos_nueva:end)];
                end
            end
        end

        function adelanta_proyectos_gx(this, proyectos, etapas_originales, etapas_adelantar)
            % cada proyecto se agrega al final de la etapa a adelantar
            for i = 1:length(proyectos)                
                pos_proy = find(this.ProyGeneracion == proyectos(i));
                if isempty(pos_proy) || this.EtapasGeneracion(pos_proy) ~= etapas_originales(i)
                    error = MException('cPlanExpansionGxTx:desplaza_proyectos','Error de programación. Proyecto a desplazar no se encuentra o no se encuentra en etapa indicada');
                    throw(error)
                end
                
                this.ProyGeneracion(pos_proy) = [];
                this.EtapasGeneracion(pos_proy) = [];
                
                pos_nueva = find(this.EtapasGeneracion > etapas_adelantar(i), 1, 'first');
                if isempty(pos_nueva)
                    % proyecto se agrega al final del plan
                    this.ProyGeneracion = [this.ProyGeneracion proyectos(i)];
                    this.EtapasGeneracion = [this.EtapasGeneracion etapas_adelantar(i)];
                else
                    this.ProyGeneracion = [this.ProyGeneracion(1:pos_nueva-1) proyectos(i) this.ProyGeneracion(pos_nueva:end)];
                    this.EtapasGeneracion = [this.EtapasGeneracion(1:pos_nueva-1) etapas_adelantar(i) this.EtapasGeneracion(pos_nueva:end)];
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
            error = MException('cPlanExpansionGxTx:crea_estructura_e_inserta_evaluacion_etapa','Esta funcion no está actualizada. Falta incorporar lineas/trafos flujo maximo/poco uso');
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