classdef cAdministradorProyectos < handle
    % clase que guarda y administra los proyectos de expansión
    properties
        
        % Escenarios contiene los proyectos en construcción de transmisión, generación y consumos
        % Escenarios{i}.GenERNC = [Gen1, Gen2, ...]
        % Escenarios{i}.EtapasGenERNC = [EtapaGen1, EtapaGen2, ...]        
        % Escenarios{i}.GenDespachables = [Gen1, Gen2, ...]
        % Escenarios{i}.EtapasGenDespachables = [EtapaGen1, EtapaGen2, ...]      
        % Escenarios{i}.Consumos = [Con1, Con2, ...]
        % Escenarios{i}.EtapasConsumos = [EtapaCon1, EtapaCon2, ...]        
        % Escenarios{i}.Transmision = [Elem1,Elem2, ...]  % incluye condensadores, baterías, etc.
        % Escenarios{i}.EtapasTransmision = [EtapaElem1,EtapaElem2, ...]  
        % Escenarios{i}.Subestaciones = [Se1, Se2, ...]
        % Escenarios{i}.EtapasSubestaciones = [Se1, Se2, ...]
        Escenarios = cell.empty

        Proyectos = cProyectoExpansion.empty
        
        RelProyIdDecisionExpansion % indica el índice del corredor o bus utilizado en expansión de MCMC. Tanto para decisiones primarias como secundarias
        
        IDProyectosVetados = [] % son los proyectos que se excluyen para la fase 2 del programa
        
        DeltaEtapa = 0   %anios
        TInicio = 0 %anio inicial (por ejemplo 2015)
        EtapaFinal = 0  %etapa final (por ejemplo, 10)
        CantidadEscenarios = 0
        CantidadEtapas = 0
        
        ProyectosObligatorios
        
        % ProyectosNuevosCorredores contiene el primer elemento de red de
        % nuevos corredores por cada subestación
        % ProyectosNuevosCorredores = [id_SE1 id_proyecto; id_SE2 id_proyecto; ...] 
        % es necesario para repara plan y para buscar nuevas opciones de
        % mejorar un plan al buscar construir nuevos corredores
        ProyectosNuevosCorredores = []
        
        % Estructura proyectos excluyentes:
        %ProyectosExcluyentes(indice).Proyectos= [id_p1, id_p2, ..., id_pn] 
        ProyectosExcluyentes
        CantidadProyectos = 0
        CantidadProyectosConDependencia = 0
        
        % ElementosSerie guarda todos los elementos de red pertenecientes a
        % los proyectos, incluyendo elementos existentes. Define la dimensión de las variables de estado.
        % por ahora sólo líneas y transformadores
        % RelElementosSerieSE: [id_bus1 admproy, id_bus2 admproy]
        ElementosSerie = cElementoRed.empty;
        EstadoElementosSerie = [] % 0: no existentes, 1: existentes        
        RelElementosSerieSE = [];
        
        % ElementosParalelos guarda los elementos de red paralelos
        % pertenecientes a los proyectos, incluyendo elementos existentes.
        % Por ahora sólo baterías. A futuro puede incluir también elementos
        % de compensación reactiva
        ElementosParalelos = cElementoRed.empty;
        EstadoElementosParalelos = []; % 0: no existentes, 1: existentes
        RelElementosParalelosSE = []; % id_bus admproy

        Subestaciones = cElementoRed.empty;
        EstadoSubestaciones = [] % 0: no existentes, 1: existentes
        
        %ElementosSerieExistentes = cElementoRed.empty;
        CostoPromedioProyectos = 0

        % Matrices de estados para trafos y corredores
        % MatrizEstadosDecisionSecundaria(id).Estado(parindex,no_estado).ProyectosEntrantes = [Pr1; Pr2;...] 
        % MatrizEstadosDecisionSecundaria(id).Estado(parindex,no_estado).ProyectosSalientes= [Pr1; Pr2;...] 
        % MatrizEstadosDecisionSecundaria(id).Estado(parindex, no_estado).ProyectosEntrantes = [Pr1; Pr2; ...]
        % MatrizEstadosDecisionSecundaria(id).Estado(parindex, no_estado).ProyectosSalientes = [Pr1; Pr2; ...]
        % MatrizEstadosDecisionPrimaria(idCorredor).Largo 
        % EstadosInicialesDecisionPrimaria = can_corr x 2: [estado i, estado j]
        % por cada corredor
        MatrizEstadosDecisionPrimaria % cada corredor y bus (para baterías) tiene una matriz de estados donde se indican los 
        CapacidadPorEstadoDecisionPrimaria
        EstadosInicialesDecisionPrimaria
        MatrizEstadosDecisionSecundaria % Para trafos VU
        CapacidadPorEstadoDecisionSecundaria
        % Por cada corredor, indica subestaciones de inicio y fin
        
        
        RelCorredoresSE
        
        % ProyectosConducentes(idCorredor).Estado(parindex, no estados).Proyectos = [Pr1; Pr2; ...] 
        ProyectosConducentes
        
        ProyPorElementosSerieAgregar = [];
        ProyPorElementosSerieRemover = [];

        ProyPorElementosParalelosAgregar = [];
        ProyPorElementosParalelosRemover = [];

        iNivelDebug = 0
        
    end
    
    methods
        function inserta_nivel_debug(this, nivel_debug)
            this.iNivelDebug = nivel_debug;
        end
                
        function inserta_id_proyectos_vetados(this, proy_vetados)
            this.IDProyectosVetados = proy_vetados;
        end
        
        function agrega_proyecto_primario(this, nuevo_proyecto, id_decision)
            this.CantidadProyectos = this.CantidadProyectos + 1;
            this.Proyectos(this.CantidadProyectos, 1) = nuevo_proyecto;
            nuevo_proyecto.Indice = this.CantidadProyectos;
            if nuevo_proyecto.tiene_dependencia()
                this.CantidadProyectosConDependencia = this.CantidadProyectosConDependencia + 1;
            end
            this.RelProyIdDecisionExpansion(this.CantidadProyectos,1) = id_decision;

        end
        
        function proy = entrega_id_proyectos_dado_id_decision(this, id_decision, varargin)
            % varargin indica si se toman proyectos de una lista en
            % particular
            if nargin == 2
                proy = find(ismember(this.RelProyIdDecisionExpansion, id_decision));
            else
                proy_lista = varargin{1};
                indices = ismember(this.RelProyIdDecisionExpansion(proy_lista), id_decision);
                proy = proy_lista(indices);
            end                
        end
        
        function id_decision = entrega_id_decision_dado_id_proyectos(this, id_proyectos)
            id_decision = this.RelProyIdDecisionExpansion(id_proyectos);
        end
        
        function agrega_proyecto_secundario(this, nuevo_proyecto, id_decision)
            this.CantidadProyectos = this.CantidadProyectos + 1;
            this.Proyectos(this.CantidadProyectos, 1) = nuevo_proyecto;
            nuevo_proyecto.Indice = this.CantidadProyectos;
            if nuevo_proyecto.tiene_dependencia()
                this.CantidadProyectosConDependencia = this.CantidadProyectosConDependencia + 1;
            end
            this.RelProyIdDecisionExpansion(this.CantidadProyectos,1) = id_decision;
        end
        
        function val = entrega_indice_decision_expansion_proyecto(this, proy)
            val = this.RelProyIdDecisionExpansion(proy.entrega_indice());
        end
        
        function agrega_proyecto_auxiliar(this, nuevo_proyecto)
            % agrega subestación para voltage uprating. No es ni primario
            % ni secundario
            this.CantidadProyectos = this.CantidadProyectos + 1;
            this.Proyectos(this.CantidadProyectos, 1) = nuevo_proyecto;
            nuevo_proyecto.Indice = this.CantidadProyectos;
            if nuevo_proyecto.tiene_dependencia()
                this.CantidadProyectosConDependencia = this.CantidadProyectosConDependencia + 1;
            end
            this.RelProyIdDecisionExpansion(this.CantidadProyectos,1) = 0;
        end
        
        function inicializa_escenarios(this, cantidad_escenarios, cantidad_etapas)
            this.CantidadEscenarios = cantidad_escenarios;
            this.CantidadEtapas = cantidad_etapas;
            for i = 1:this.CantidadEscenarios
                this.Escenarios{i}.GenERNC = cGenerador.empty;
                this.Escenarios{i}.EtapasGenERNC = [];
                this.Escenarios{i}.GenDespachables = cGenerador.empty;
                this.Escenarios{i}.EtapasGenDespachables  = [];
                this.Escenarios{i}.Consumos = cConsumo.empty;
                this.Escenarios{i}.EtapasConsumos = [];
                this.Escenarios{i}.Transmision = cElementoRed.empty;
                this.Escenarios{i}.EtapasTransmision = [];
                this.Escenarios{i}.Subestaciones = cSubestacion.empty;
                this.Escenarios{i}.EtapasSubestaciones = [];
            end
        end
        
        function elem = entrega_elementos_proyectados_por_etapa(this, escenario, etapa)
            elem = this.Escenarios{escenario}.Subestaciones(this.Escenarios{escenario}.EtapasSubestaciones == etapa);
            elem = [elem this.Escenarios{escenario}.GenDespachables(this.Escenarios{escenario}.EtapasGenDespachables == etapa)];
            elem = [elem this.Escenarios{escenario}.GenERNC(this.Escenarios{escenario}.EtapasGenERNC == etapa)];
            elem = [elem this.Escenarios{escenario}.Consumos(this.Escenarios{escenario}.EtapasConsumos == etapa)];
            elem = [elem this.Escenarios{escenario}.Transmision(this.Escenarios{escenario}.EtapasTransmision == etapa)];
        end
        
        function gen = entrega_generadores_despachables_proyectados(this, escenario, varargin)
            % varargin indica etapa
            if nargin == 2
                gen = this.Escenarios{escenario}.GenDespachables;
            else
                etapa = varargin{1};
                gen = this.Escenarios{escenario}.GenDespachables(this.Escenarios{escenario}.EtapasGenDespachables == etapa);
            end
        end

        function gen = entrega_generadores_despachables_proyectados_todos(this)
            gen = [];
            for escenario = 1:length(this.Escenarios)
                gen = [gen this.Escenarios{escenario}.GenDespachables];
            end
            gen = unique(gen);            
        end
        
        function gen = entrega_generadores_ernc_proyectados(this, escenario, varargin)
            % varargin indica etapa
            if nargin == 2
                gen = this.Escenarios{escenario}.GenERNC;
            else
                etapa = varargin{1};
                gen = this.Escenarios{escenario}.GenERNC(this.Escenarios{escenario}.EtapasGenERNC == etapa);
            end
        end

        function gen = entrega_generadores_ernc_proyectados_todos(this)
            gen = [];
            for escenario = 1:length(this.Escenarios)
                gen = [gen this.Escenarios{escenario}.GenERNC];
            end
            gen = unique(gen);
        end
        
        function elem = entrega_consumos_proyectados(this, escenario, varargin)
            % varargin indica etapa
            if nargin == 2
                elem = this.Escenarios{escenario}.Consumos;
            else
                etapa = varargin{1};
                elem = this.Escenarios{escenario}.Consumos(this.Escenarios{escenario}.EtapasConsumos == etapa);
            end            
        end

        function elem = entrega_consumos_proyectados_todos(this)
            elem = [];
            for escenario = 1:length(this.Escenarios)
                elem = [elem this.Escenarios{escenario}.Consumos];
            end
            elem = unique(elem);
        end
        
        function elem = entrega_subestaciones_proyectadas(this, escenario, varargin)
            % varargin indica etapa
            if nargin == 2
                elem = this.Escenarios{escenario}.Subestaciones;
            else
                etapa = varargin{1};
                elem = this.Escenarios{escenario}.Subestaciones(this.Escenarios{escenario}.EtapasSubestaciones == etapa);
            end            
        end

        function se = entrega_subestacion_proyectada_por_nombre(this, nombre)
            for escenario = 1:length(this.Escenarios)
                for j = 1:length(this.Escenarios{escenario}.Subestaciones)
                    if strcmp(this.Escenarios{escenario}.Subestaciones(j).Nombre, nombre)
                        se = this.Escenarios{escenario}.Subestaciones(j);
                        return
                    end
                end
            end
            error = MException('cAdministradorProyectos:entrega_subestacion_proyectada_por_nombre','no se encuentra la subestacion');
            throw(error)
        end
        
        function elem = entrega_subestaciones_proyectadas_todas(this)
            elem = [];
            for escenario = 1:length(this.Escenarios)
                elem = [elem this.Escenarios{escenario}.Subestaciones];
            end
            elem = unique(elem);
        end
        
        function etapa = entrega_etapa_subestacion_proyectada(this, se, escenario)
            etapa = this.Escenarios{escenario}.EtapasSubestaciones(this.Escenarios{escenario}.Subestaciones == se);
        end

        function elem = entrega_elementos_red_proyectados(this, escenario, varargin)
            % varargin indica etapa
            if nargin == 2
                elem = this.Escenarios{escenario}.Transmision;
            else
                etapa = varargin{1};
                elem = this.Escenarios{escenario}.Transmision(this.Escenarios{escenario}.EtapasTransmision == etapa);
            end
        end

        function elem = entrega_elementos_serie_proyectados_todos(this)
            elem = [];
            for escenario = 1:length(this.Escenarios)
                elem = [elem this.Escenarios{escenario}.Transmision];
            end
            elem = unique(elem);
        end
        
        function elem = entrega_elementos_red_proyectados_por_subestacion(this, escenario, se)
            elem = [];
            for i = 1:length(this.Escenarios{escenario}.Transmision)
                if this.Escenarios{escenario}.Transmision(i).entrega_se1() == se || ...
                        this.Escenarios{escenario}.Transmision(i).entrega_se2() == se
                    elem = [elem this.Escenarios{escenario}.Transmision(i)];
                end
            end
        end
                
        
        function agrega_generador_proyectado(this, generador, escenario, etapa)
			if generador.es_despachable()
				this.Escenarios{escenario}.GenDespachables = [this.Escenarios{escenario}.GenDespachables  generador];
                this.Escenarios{escenario}.EtapasGenDespachables = [this.Escenarios{escenario}.EtapasGenDespachables  etapa];
			else
				this.Escenarios{escenario}.GenERNC= [this.Escenarios{escenario}.GenERNC generador];
                this.Escenarios{escenario}.EtapasGenERNC = [this.Escenarios{escenario}.EtapasGenERNC etapa];
			end
        end
        
        function agrega_consumo_proyectado(this, consumo, escenario, etapa)
            this.Escenarios{escenario}.Consumos = [this.Escenarios{escenario}.Consumos consumo];
            this.Escenarios{escenario}.EtapasConsumos = [this.Escenarios{escenario}.EtapasConsumos etapa];
        end

        function agrega_elemento_transmision_proyectado(this, el_serie, escenario, etapa)
            this.Escenarios{escenario}.Transmision = [this.Escenarios{escenario}.Transmision el_serie];
            this.Escenarios{escenario}.EtapasTransmision = [this.Escenarios{escenario}.EtapasTransmision etapa];
        end

        function agrega_subestacion_proyectada(this, subestacion, escenario, etapa)
            this.Escenarios{escenario}.Subestaciones = [this.Escenarios{escenario}.Subestaciones subestacion];
            this.Escenarios{escenario}.EtapasSubestaciones = [this.Escenarios{escenario}.EtapasSubestaciones etapa];
        end
        
        function proy = entrega_proyecto_subestacion(this, se)
            for i = 1:length(this.Proyectos)
                if strcmp(this.Proyectos(i).entrega_tipo_proyecto(),'AS') && this.Proyectos(i).Elemento(1) == se
                    proy = this.Proyectos(i);
                    return;
                end
            end
            error = MException('cAdministradorProyectos:entrega_proyecto_subestacion','proyecto con subestacion indicada no fue encontrado');
            throw(error)
        end
                    
        function [espacio_busqueda, primera_etapa_posible] = determina_espacio_busqueda(this, plan, varargin)
            % varargin indica si hay proyectos restringidos
            proyectos_restringidos = [];
            if nargin > 2
                proyectos_restringidos = varargin{1};
            end
            proyectos_restringidos = [proyectos_restringidos this.IDProyectosVetados];
            
            espacio_busqueda = zeros(length(this.Proyectos), 1);
            primera_etapa_posible = zeros(length(this.Proyectos), 1);
            cantidad_proyectos = 0;
            for i=1:length(this.Proyectos)
                if ~isempty(find(proyectos_restringidos == i, 1))
                    continue;
                end
                proy = this.Proyectos(i);
                if strcmp(proy.entrega_tipo_proyecto(), 'AS') || ...
                        (strcmp(proy.entrega_tipo_proyecto(), 'AT') && proy.Elemento(1).entrega_indice_decision_expansion() == 0 && proy.Elemento(1).entrega_indice_paralelo() == 1)
                    % agrega subestación o tipo de transformador. Estos
                    % proyectos se escogen sólo si aparece VU (o sea, si un
                    % proyecto seleccionado tiene requisitos de
                    % conectividad)
                    continue;
                end
                
                if ~plan.proyecto_existe(proy.entrega_indice())
                    % sólo proyectos que no están en el plan
                    
                    % elimina proyecto si proyecto excluyente está en el
                    % plan
                    %ProyectosExcluyentes(indice).Proyectos= [id_p1, id_p2, ..., id_pn] 
                    aplica = true;
                    nro_etapa = 1;
                    for grupo = 1:length(this.ProyectosExcluyentes)
                        if ~isempty(find(this.ProyectosExcluyentes(grupo).Proyectos == proy.entrega_indice(), 1))
                            % proyecto tiene proyectos excluyentes
                            if plan.proyecto_excluyente_existe(this.ProyectosExcluyentes(grupo).Proyectos)
                                aplica = false;
                                break
                            end
                        end
                    end
                    if ~aplica
                        continue;
                    end
                    
                    % elimina los proyectos con dependencia, que tampoco
                    % están en el plan
                    aplica = false;
                    if proy.TieneDependencia == false
                        aplica = true;
                    else
                        [existe, etapa] = plan.dependencia_existe(proy.entrega_indices_proyectos_dependientes());
                        if existe
                            aplica = true;
                            nro_etapa = etapa;
                        end
                    end
                    
                    if aplica
                        cantidad_proyectos = cantidad_proyectos +1;
                        espacio_busqueda(cantidad_proyectos) = i;
                        primera_etapa_posible(cantidad_proyectos) = nro_etapa;
                    end
                end
            end
            espacio_busqueda = espacio_busqueda(1:cantidad_proyectos);
            primera_etapa_posible = primera_etapa_posible(1:cantidad_proyectos);
        end

        function espacio_busqueda = determina_espacio_busqueda_repara_plan_en_etapa(this, plan, nro_etapa)
            espacio_busqueda = zeros(length(this.Proyectos), 1);
            cantidad_proyectos = 0;
            for i=1:length(this.Proyectos)
                if ~isempty(find(this.IDProyectosVetados == i, 1))
                    continue;
                end
                
                proy = this.Proyectos(i);
                if strcmp(proy.entrega_tipo_proyecto(), 'AS') || ...
                        (strcmp(proy.entrega_tipo_proyecto(), 'AT') && proy.Elemento(1).entrega_indice_decision_expansion() == 0 && proy.Elemento(1).entrega_indice_paralelo() == 1)
                    % agrega subestación o tipo de transformador. Estos
                    % proyectos se escogen sólo si aparece VU (o sea, si un
                    % proyecto seleccionado tiene requisitos de
                    % conectividad)
                    continue;
                end
                aplica = false;
                etapa_proyecto = plan.entrega_etapa_proyecto(proy.entrega_indice(), false);
                if etapa_proyecto == 0
                    % proyecto no está en el plan
                    % elimina proyecto si proyecto excluyente está en el
                    % plan
                    %ProyectosExcluyentes(indice).Proyectos= [id_p1, id_p2, ..., id_pn] 
                    aplica = true;
                    for grupo = 1:length(this.ProyectosExcluyentes)
                        if ~isempty(find(this.ProyectosExcluyentes(grupo).Proyectos == proy.entrega_indice(), 1))
                            % proyecto tiene proyectos excluyentes
                            if plan.proyecto_excluyente_existe(this.ProyectosExcluyentes(grupo).Proyectos)
                                aplica = false;
                                break
                            end
                        end
                    end
                    if ~aplica
                        continue;
                    end
                    
                    % elimina los proyectos con dependencia, que tampoco
                    % están en el plan
                    aplica = false;
                    if proy.TieneDependencia == false
                        aplica = true;
                    else
                        % si dependencia está en una etapa posterior,
                        % entonces proyecto no aplica, ya que es la
                        % dependencia que debiera adelantarse
                        [existe_dependencia, etapa_dependencia] = plan.dependencia_existe(proy.entrega_indices_proyectos_dependientes());
                        if existe_dependencia && etapa_dependencia <= nro_etapa
                            aplica = true;
                        end
                    end                    
                elseif etapa_proyecto > nro_etapa
                    % proyecto está en el plan, pero en una etapa
                    % posterior. Hay que verificar si se puede adelantar
                    % hasta nro_etapa
                    if proy.TieneDependencia == false
                        aplica = true;
                    else
                        [existe_dependencia, etapa_dependencia] = plan.dependencia_existe(proy.entrega_indices_proyectos_dependientes());
                        if existe_dependencia && etapa_dependencia <= nro_etapa
                            aplica = true;
                        end
                    end
                end
                if aplica
                    cantidad_proyectos = cantidad_proyectos +1;
                    espacio_busqueda(cantidad_proyectos) = i;
                end
            end
            espacio_busqueda = espacio_busqueda(1:cantidad_proyectos);
        end
        
        function espacio_busqueda = determina_espacio_busqueda_local(this, espacio_proyectos)
            espacio_busqueda = [];
            espacio_proyectos = espacio_proyectos(~ismember(espacio_proyectos,this.IDProyectosVetados));
            
            for i=1:length(espacio_proyectos)
                proy = this.Proyectos(espacio_proyectos(i));
                % busca proyecto en índice de proyectos
                % se sacan proyectos de subestaciones y transformadores
                % para VU, ya que estos se construyen en la medida que
                % proyecto de VU aparece
                if strcmp(proy.entrega_tipo_proyecto(), 'AS')
                    continue;
                elseif strcmp(proy.entrega_tipo_proyecto(), 'AT') && ...
                       proy.Elemento(1).entrega_indice_decision_expansion() == 0 && ...
                       proy.Elemento(1).entrega_indice_paralelo() == 1
                        % corresponde al primer transformador de VU, por lo
                        % que su inclusión depende si aparece proyecto VU
                        % principal
                        continue;
                end
                aplica = false;
                if proy.TieneDependencia == false
                    aplica = true;
                else
                    dependencias = proy.IndiceProyectoDependiente;
                    if sum(ismember(dependencias, espacio_proyectos)) == 0
                        %proyecto tiene dependencia(s) pero esta(s) no se
                        %encuentra(n) en el espacio de proyectos, por lo
                        %que ya fueron incorporadas al plan. Es decir,
                        %proyecto aplica
                        aplica = true;
                    end
                end
                if aplica
                    espacio_busqueda(end+1) = espacio_proyectos(i);
                end
            end
        end

        function [espacio_busqueda, directo]= determina_espacio_busqueda_repara_plan(this, plan, nro_etapa, varargin)
            espacio_busqueda = [];
            proyectos_disponibles = [];
            if nargin >3
                proyectos_disponibles = varargin{1};
            end
            if this.iNivelDebug > 1
                prot = cProtocolo.getInstance;
                prot.imprime_texto('   Espacio busqueda repara plan. Elementos sobrecargados:');
                texto = sprintf('%-3s %-25s %-5s', ' ', 'Elemento', 'Porcentaje carga');
                prot.imprime_texto(texto);
            end
            
            el_flujo_maximo = plan.entrega_elementos_flujo_maximo(nro_etapa);
            [n, ~] = size(el_flujo_maximo);
            for i = 1:n
                id_adm_proy = el_flujo_maximo{i,3};
                if this.iNivelDebug > 1
                    texto = sprintf('%-3s %-25s %-5s', ' ', el_flujo_maximo{i,1}, num2str(el_flujo_maximo{i,7}));
                    prot.imprime_texto(texto);
                end
                
                el_red = this.ElementosSerie(id_adm_proy);
                
                proy = this.entrega_id_proyectos_salientes(el_red);
                if isempty(proyectos_disponibles)
                    % verifica si alguno de los proyectos salientes se
                    % encuentra en el plan. En este caso, sólo ese proyecto
                    % se considera (ya que los proyectos salientes son
                    % excluyentes entre sí)
                    id_proy_existente = plan.algun_proyecto_existe_a_partir_de_etapa(proy, nro_etapa + 1);
                    if id_proy_existente == 0
                        % no hay proyectos existentes. Todos se agregan a
                        % la lista
                        espacio_busqueda = [espacio_busqueda; proy];
                    else
                        id_proy_existente = id_proy_existente(~ismember(id_proy_existente, this.IDProyectosVetados));
                        espacio_busqueda = [espacio_busqueda; id_proy_existente]; 
                    end
                else
                    % busca en proyectos disponibles 
                    espacio_busqueda = [espacio_busqueda proy(ismember(proy, proyectos_disponibles))'];
                end
            end
            
            directo = true;
            if isempty(espacio_busqueda) && ~isempty(proyectos_disponibles)
                % quiere decir que reparación no es "directa"
                % se buscan proyectos desde búsqueda local
                espacio_busqueda = this.determina_espacio_busqueda_local(proyectos_disponibles);
                directo = false;
            elseif isempty(espacio_busqueda)
                espacio_busqueda = this.determina_espacio_busqueda_repara_plan_en_etapa(plan, nro_etapa);
                directo = false;
            end
            
            if this.iNivelDebug > 1
                if directo
                    prot.imprime_texto('   Proyectos candidatos que ayudan a descongestionar');
                else
                    prot.imprime_texto('   Proyectos candidatos de pool de proyectos, ya que ninguno ayuda a descongestionar directamente');
                end
                
                texto = sprintf('%-3s %-5s %-7s %-30s %-10s', ' ', 'Id', 'Tipo', 'Elemento', 'Accion');
                prot.imprime_texto(texto);
                for ii = 1:length(espacio_busqueda)
                    candidatos = this.Proyectos(espacio_busqueda(ii));
                    primero = true;
                    for elem= 1:length(candidatos.Elemento)
                        if primero
                            texto = sprintf('%-3s %-5s %-7s %-30s %-10s', ' ', num2str(espacio_busqueda(ii)), ...
                                                        candidatos.entrega_tipo_proyecto(), ... 
                                                        candidatos.Elemento(elem).entrega_nombre(), ...
                                                        candidatos.Accion{elem});
                            primero = false;
                        else
                            texto = sprintf('%-3s %-5s %-7s %-30s %-10s', '', '', '',...
                                                        candidatos.Elemento(elem).entrega_nombre(), ...
                                                        candidatos.Accion{elem});
                        end
                        prot.imprime_texto(texto);
                    end
                end
            end
        end
            
        function [espacio_busqueda, desde_etapa, hasta_etapa] = determina_espacio_busqueda_desplaza_proyectos(this, plan, nro_etapa, proy_restringidos, acumulados, varargin)
%prot = cProtocolo.getInstance;
%for jj = length(plan.Plan)
%   for kk = 1:length(plan.Plan(jj).Proyectos)
%        prot.imprime_texto(['Proyecto : ' num2str(plan.Plan(jj).Proyectos(kk))]);
%    end
%end
            % varargin indica proyectos que están en evaluación
            if nargin > 5
                proy_en_evaluacion = varargin{1};
            else
                proy_en_evaluacion = [];
            end
            
            espacio_busqueda = [];
            desde_etapa = [];
            hasta_etapa = [];
            % no hay elementos con poco uso o los proyectos que quedaron eran restringidos. Espacio de búsqueda son
            % los proyectos actuales menos los restringidos, sacando
            % los proyectos en donde otro depende de él
            if acumulados
                [proy_todos, etapas_todos] = plan.entrega_proyectos_y_etapas();
                id_cum_hasta_etapa = etapas_todos <= nro_etapa;
                espacio_completo = proy_todos(id_cum_hasta_etapa);
                proy_etapas_siguientes = proy_todos(~id_cum_hasta_etapa);
                etapas_espacio_completo = etapas_todos(id_cum_hasta_etapa);
                etapas_siguientes = etapas_todos(~id_cum_hasta_etapa);
                %[espacio_completo, etapas_espacio_completo] = plan.entrega_proyectos_acumulados_y_etapas(nro_etapa);
            else
                espacio_completo = plan.entrega_proyectos(nro_etapa);
                etapas_espacio_completo = nro_etapa*ones(1,length(espacio_completo));
            end

            if isempty(espacio_completo)
                return;
            end
            %espacio_busqueda(ismember(espacio_busqueda, proy_restringidos)) = [];
            proy_a_descartar = [proy_restringidos this.IDProyectosVetados];
            % verifica conectividad
            
            if nro_etapa == 1 || acumulados                
                for ii = 1:length(this.ProyectosObligatorios)
                    proy_obligatorios = this.entrega_indices_proyectos_obligatorios(ii);
                    proy_plan_etapa_1 = plan.entrega_proyectos(1);
                    proy_obligatorios_a_considerar = proy_obligatorios(ismember(proy_obligatorios, proy_plan_etapa_1));
                    proy_en_primera_etapa = ismember(espacio_completo,proy_obligatorios_a_considerar);
                    if sum(proy_en_primera_etapa) == 1
                        % sólo hay un proyecto obligatorio en el
                        % espacio de búsqueda. Se elimina del espacio
                        % de búsqueda
                        proy_a_descartar = [proy_a_descartar espacio_completo(proy_en_primera_etapa)];
                    end
                end
            end
            % descarta proyectos AT para VU y con dependencia que esté en el espacio de búsqueda proy_a_descartar = [];
            for ii = 1:length(espacio_completo)
                proy = this.Proyectos(espacio_completo(ii));
                if strcmp(proy.entrega_tipo_proyecto(), 'AS') || ...
                    strcmp(proy.entrega_tipo_proyecto(), 'AT') && ...
                    proy.Elemento(1).entrega_indice_decision_expansion() == 0 && ...
                    proy.Elemento(1).entrega_indice_paralelo() == 1
                    proy_a_descartar = [proy_a_descartar espacio_completo(ii)];
                    continue;
                end

                if proy.TieneDependencia
                    id_proy_dep = proy.entrega_indices_proyectos_dependientes();
                    proy_dep_en_espacio_busqueda = id_proy_dep(ismember(id_proy_dep, espacio_completo));
                    while ~isempty(proy_dep_en_espacio_busqueda)
                        proy_a_descartar = [proy_a_descartar proy_dep_en_espacio_busqueda];
                        
                        nuevo_proy = this.Proyectos(proy_dep_en_espacio_busqueda);
                        id_proy_dep = nuevo_proy.entrega_indices_proyectos_dependientes();
                        proy_dep_en_espacio_busqueda = id_proy_dep(ismember(id_proy_dep, espacio_completo));
                    end
                end
            end
            
            id_validos = ~ismember(espacio_completo,proy_a_descartar);
            espacio_completo = espacio_completo(id_validos);
            etapas_espacio_completo = etapas_espacio_completo(id_validos);
            
            if isempty(espacio_completo)
                return;
            end

            % descarta proyectos en que proyecto que depende de él está en evaluación
            for i = 1:length(proy_en_evaluacion)
                proy_eval = this.Proyectos(proy_en_evaluacion(i));
                if proy_eval.TieneDependencia
                    id_proy_dep = proy_eval.entrega_indices_proyectos_dependientes();
                    proy_dep_en_espacio_busqueda = id_proy_dep(ismember(id_proy_dep, espacio_completo));
                    while ~isempty(proy_dep_en_espacio_busqueda)
                        id_validos = ~ismember(espacio_completo, proy_dep_en_espacio_busqueda);
                        espacio_completo = espacio_completo(id_validos);
                        etapas_espacio_completo = etapas_espacio_completo(id_validos);
                        % nuevos proyectos dependientes
                        nuevo_proy = this.Proyectos(proy_dep_en_espacio_busqueda);
                        id_proy_dep = nuevo_proy.entrega_indices_proyectos_dependientes();
                        proy_dep_en_espacio_busqueda = id_proy_dep(ismember(id_proy_dep, espacio_completo));
                    end
                end
            end
            
            if this.iNivelDebug > 1
                prot = cProtocolo.getInstance;
                prot.imprime_texto('   Espacio busqueda desplaza proyectos. Elementos con poco uso:');
                texto = sprintf('%-3s %-25s', ' ', 'Id', 'Nombre');
                prot.imprime_texto(texto);
            end

            % se determina espacio de búsqueda
            % prioridad a elementos con poco uso
            el_poco_uso = plan.entrega_elementos_poco_uso(nro_etapa);
            if ~isempty(el_poco_uso)
                [n, ~] = size(el_poco_uso);
                for i = 1:n
                    id_adm_proy = el_poco_uso(i);
                    el_red = this.ElementosSerie(id_adm_proy);
                    if this.iNivelDebug > 1
                        texto = sprintf('%-3s %-25s', num2str(el_poco_uso(i)), el_red.entrega_nombre());
                        prot.imprime_texto(texto);
                    end
                    
                    proy = this.entrega_id_proyectos_entrantes(el_red);

                    id_encontrados = ismember(espacio_completo, proy);
                    espacio_busqueda = [espacio_busqueda espacio_completo(id_encontrados)];
                    desde_etapa = [desde_etapa etapas_espacio_completo(id_encontrados)];                    
                end
                
                % verifica conectividad VU: TODO
            else
                if this.iNivelDebug > 1
                    prot.imprime_texto('No hay elementos con poco uso');
                end
            end
            if isempty(espacio_busqueda)
                espacio_busqueda = espacio_completo;
                desde_etapa = etapas_espacio_completo;
                directa = false; %indica si proyectos se encontraron en forma directa (por los elementos de poco uso)
            else
                directa = true;
            end
            
            % determina hasta etapas
            hasta_etapa = (this.CantidadEtapas+1)*ones(1, length(espacio_busqueda));
            for i = 1:length(proy_etapas_siguientes)
                proy_sig = this.Proyectos(proy_etapas_siguientes(i));
                if proy_sig.TieneDependencia
                    id_proy_dep = proy_sig.entrega_indices_proyectos_dependientes();
                    id_encontrado = ismember(espacio_busqueda, id_proy_dep);
                    if ~isempty(find(id_encontrado>0, 1))
                        hasta_etapa(id_encontrado) = etapas_siguientes(i);
                    end
                end
            end
            
            if this.iNivelDebug > 1
                if directa
                    prot.imprime_texto('   Proyectos candidatos en base a elementos de poco uso');
                else
                    prot.imprime_texto('   Proyectos candidatos en base a pool (ya que elementos de poco uso no arrojo ningun resultado)');                    
                end
                texto = sprintf('%-3s %-5s %-7s %-30s %-10s', ' ', 'Id', 'Tipo', 'Elemento', 'Accion');
                prot.imprime_texto(texto);
                for ii = 1:length(espacio_busqueda)
                    candidatos = this.Proyectos(espacio_busqueda(ii));
                    primero = true;
                    for elem= 1:length(candidatos.Elemento)
                        if primero
                            texto = sprintf('%-3s %-5s %-7s %-30s %-10s', ' ', num2str(espacio_busqueda(ii)), ...
                                                        candidatos.entrega_tipo_proyecto(), ... 
                                                        candidatos.Elemento(elem).entrega_nombre(), ...
                                                        candidatos.Accion{elem});
                            primero = false;
                        else
                            texto = sprintf('%-3s %-5s %-7s %-30s %-10s', '', '', '',...
                                                        candidatos.Elemento(elem).entrega_nombre(), ...
                                                        candidatos.Accion{elem});
                        end
                        prot.imprime_texto(texto);
                    end
                end
            end
        end

        function espacio_busqueda = determina_espacio_busqueda_local_agrega_proyectos(this, plan, nro_etapa, espacio_proyectos, prioridad_sobrecarga_elementos)
            if ~prioridad_sobrecarga_elementos
                espacio_busqueda = this.determina_espacio_busqueda_local(espacio_proyectos);
            else
%prot = cProtocolo.getInstance;
%for jj = length(plan.Plan)
%   for kk = 1:length(plan.Plan(jj).Proyectos)
%        prot.imprime_texto(['Proyecto : ' num2str(plan.Plan(jj).Proyectos(kk))]);
%    end
%end
                if this.iNivelDebug > 1
                    prot = cProtocolo.getInstance;
                    prot.imprime_texto('   Espacio busqueda agrega proyectos. Elementos con flujos maximos:');
                    texto = sprintf('%-3s %-25s %-5s', ' ', 'Elemento', 'Porcentaje carga');
                    prot.imprime_texto(texto);
                end

                espacio_busqueda = [];
                directa = true; %indica si proyectos se encontraron en forma directa (por los elementos con harto uso)
                el_harto_uso = plan.entrega_elementos_flujo_maximo(nro_etapa);
                if ~isempty(el_harto_uso)
                    [n, ~] = size(el_harto_uso);
                    espacio_busqueda = [];
                    for i = 1:n
                        id_adm_proy = el_harto_uso{i,3};
                        if this.iNivelDebug > 1
                            texto = sprintf('%-3s %-25s %-5s', ' ', el_harto_uso{i,1}, num2str(el_harto_uso{i,7}));
                            prot.imprime_texto(texto);
                        end
                        
                        el_red = this.ElementosSerie(id_adm_proy);

                        proy = this.entrega_id_proyectos_salientes(el_red);
                        for ii = 1:length(proy)
                            espacio_busqueda = [espacio_busqueda; proy(ii)];
                        end
                    end
                    espacio_busqueda = espacio_busqueda(~ismember(espacio_busqueda, this.IDProyectosVetados));
                else
                    if this.iNivelDebug > 1
                        prot.imprime_texto('No hay elementos con poco uso');
                    end
                end
                if isempty(espacio_busqueda)
                    directa = false;
                    espacio_busqueda = determina_espacio_busqueda_local(espacio_proyectos);
                end

                if this.iNivelDebug > 1
                    if directa
                        prot.imprime_texto('   Proyectos candidatos en base a elementos harto uso');
                    else
                        prot.imprime_texto('   Proyectos candidatos en base a pool (ya que elementos de harto uso no arrojo ningun resultado)');                    
                    end
                    texto = sprintf('%-3s %-5s %-7s %-30s %-10s', ' ', 'Id', 'Tipo', 'Elemento', 'Accion');
                    prot.imprime_texto(texto);
                    for ii = 1:length(espacio_busqueda)
                        candidatos = this.Proyectos(espacio_busqueda(ii));
                        primero = true;
                        for elem= 1:length(candidatos.Elemento)
                            if primero
                                texto = sprintf('%-3s %-5s %-7s %-30s %-10s', ' ', num2str(espacio_busqueda(ii)), ...
                                                            candidatos.entrega_tipo_proyecto(), ... 
                                                            candidatos.Elemento(elem).entrega_nombre(), ...
                                                            candidatos.Accion{elem});
                                primero = false;
                            else
                                texto = sprintf('%-3s %-5s %-7s %-30s %-10s', '', '', '',...
                                                            candidatos.Elemento(elem).entrega_nombre(), ...
                                                            candidatos.Accion{elem});
                            end
                            prot.imprime_texto(texto);
                        end
                    end
                end
            end
        end
        
        function [espacio_busqueda, desde_etapa]= determina_espacio_busqueda_elimina_proyectos(this, plan, nro_etapa, proy_restringidos)
            % espacio de búsqueda contiene sólo proyectos aptos para ser eliminados 
            % determina espacio completo
            espacio_busqueda = [];
            desde_etapa = [];
            [espacio_completo, etapas_espacio_completo] = plan.entrega_proyectos_y_etapas();
            %espacio_busqueda(ismember(espacio_busqueda, proy_restringidos)) = [];
            proy_a_descartar = proy_restringidos;
            % verifica conectividad
            for ii = 1:length(this.ProyectosObligatorios)
                proy_obligatorios = this.entrega_indices_proyectos_obligatorios(ii);
                proy_plan_etapa_1 = plan.entrega_proyectos(1);
                proy_obligatorios_a_considerar = proy_obligatorios(ismember(proy_obligatorios, proy_plan_etapa_1));
                proy_en_primera_etapa = ismember(espacio_completo,proy_obligatorios_a_considerar);
                if sum(proy_en_primera_etapa) == 1
                    % sólo hay un proyecto obligatorio en el
                    % espacio de búsqueda. Se elimina del espacio
                    % de búsqueda
                    proy_a_descartar = [proy_a_descartar espacio_completo(proy_en_primera_etapa)];
                end
            end
            % descarta proyectos AT para VU y con dependencia que esté
            % en el espacio de búsqueda
            %proy_a_descartar = [];
            for ii = 1:length(espacio_completo)
                proy = this.Proyectos(espacio_completo(ii));
                if strcmp(proy.entrega_tipo_proyecto(), 'AS') || ...
                    strcmp(proy.entrega_tipo_proyecto(), 'AT') && ...
                    proy.Elemento(1).entrega_indice_decision_expansion() == 0 && ...
                    proy.Elemento(1).entrega_indice_paralelo() == 1
                    proy_a_descartar = [proy_a_descartar espacio_completo(ii)];
                    continue;
                end
                % elimina este proyecto si algún otro proyecto en el
                % espacio de búsqueda depende de él
                if proy.TieneDependencia
                    proy_a_descartar = [proy_a_descartar proy.entrega_indices_proyectos_dependientes()'];
                end
            end
            indices_validos = ~ismember(espacio_completo,proy_a_descartar);
            espacio_completo = espacio_completo(indices_validos);
            etapas_espacio_completo = etapas_espacio_completo(indices_validos);
            
            if isempty(espacio_completo)
                return;
            end
            
            if this.iNivelDebug > 1
                prot = cProtocolo.getInstance;
                prot.imprime_texto(['   Espacio busqueda elimina proyectos. Elementos con poco uso en etapa ' num2str(nro_etapa) ':']);
                texto = sprintf('%-3s %-25s', 'Id', 'Nombre');
                prot.imprime_texto(texto);
            end
            
            el_poco_uso = plan.entrega_elementos_poco_uso(nro_etapa);
            if ~isempty(el_poco_uso)
                [n, ~] = size(el_poco_uso);
                espacio_busqueda = [];
                for i = 1:n
                    id_adm_proy = el_poco_uso(i);
                    el_red = this.ElementosSerie(id_adm_proy);

                    if this.iNivelDebug > 1
                        texto = sprintf('%-3s %-25s', num2str(el_poco_uso(i)), el_red.entrega_nombre());
                        prot.imprime_texto(texto);
                    end                     
                    
                    proy = this.entrega_id_proyectos_entrantes(el_red);
                    % identifica el proyecto en el plan (tiene que haber solo uno!)
                    id_encontrados = ismember(espacio_completo, proy);
                    espacio_busqueda = [espacio_busqueda espacio_completo(id_encontrados)];
                    desde_etapa = [desde_etapa etapas_espacio_completo(id_encontrados)];
                    
%                     encontrado = false;
%                     for ii = 1:length(proy)
%                         
%                         if plan.proyecto_existe_acumulado(proy(ii), nro_etapa)
%                             if encontrado
%                                 texto = ['Error de programacion. Elemento ' el_red.entrega_nombre() ' ya fue encontrado en otro proyecto. No debiera ser'];
%                                 error = MException('cAdministradorProyectos:determina_espacio_busqueda_elimina_proyectos',texto);
%                                 throw(error)
%                             else
%                                 % se excluyen proyectos AT para VU si el
%                                 % transformador tiene índice paralelo 1. En
%                                 % este caso se eliminan si se elimina toda
%                                 % la línea
%                                 encontrado = true;
%                                 if strcmp(this.Proyectos(proy(ii)).entrega_tipo_proyecto(), 'AT') && ...
%                                    this.Proyectos(proy(ii)).Elemento(1).entrega_indice_decision_expansion() == 0 && ...
%                                    this.Proyectos(proy(ii)).Elemento(1).entrega_indice_paralelo() == 1
%                                     continue;
%                                 else
%                                     espacio_busqueda = [espacio_busqueda proy(ii)];
%                                 end
%                             end
%                         end
%                     end
                    %if ~encontrado && ~existente
                    %    texto = ['Error de programacion. Proyecto con elemento ' el_red.entrega_nombre() ' no fue encontrado y no es existente. No debiera ser'];
                    %    error = MException('cAdministradorProyectos:determina_espacio_busqueda_elimina_proyectos',texto);
                    %    throw(error)
                    %end
                end
                %id_validos = ~ismember(espacio_busqueda, proy_restringidos);
                %espacio_busqueda = espacio_busqueda(id_validos);
                %desde_etapa = desde_etapa(id_validos);
                
                % verifica conectividad proyectos VU
                % TODO FALTA
            else
                if this.iNivelDebug > 1
                    prot.imprime_texto('No hay elementos con poco uso');
                end
            end
            if isempty(espacio_busqueda)
                espacio_busqueda = espacio_completo;
                desde_etapa = etapas_espacio_completo;
            end
            
            if this.iNivelDebug > 1
                prot.imprime_texto('   Proyectos candidatos');
                texto = sprintf('%-3s %-5s %-7s %-30s %-10s', ' ', 'Id', 'Tipo', 'Elemento', 'Accion');
                prot.imprime_texto(texto);
                for ii = 1:length(espacio_busqueda)
                    candidatos = this.Proyectos(espacio_busqueda(ii));
                    primero = true;
                    for elem= 1:length(candidatos.Elemento)
                        if primero
                            texto = sprintf('%-3s %-5s %-7s %-30s %-10s', ' ', num2str(espacio_busqueda(ii)), ...
                                                        candidatos.entrega_tipo_proyecto(), ... 
                                                        candidatos.Elemento(elem).entrega_nombre(), ...
                                                        candidatos.Accion{elem});
                            primero = false;
                        else
                            texto = sprintf('%-3s %-5s %-7s %-30s %-10s', '', '', '',...
                                                        candidatos.Elemento(elem).entrega_nombre(), ...
                                                        candidatos.Accion{elem});
                        end
                        prot.imprime_texto(texto);
                    end
                end
            end
        end
        
        function [proyectos_paralelos, etapas]= entrega_proyectos_paralelos_parindex_creciente(this, plan, id_proyecto_principal, varargin)
            % varargin indica el número de etapa.
            % si se indica número de etapa entonces se buscan proyectos
            % sólo en la etapa indicada. Si no se indica nada, entonces se
            % buscan los proyectos en todo el espacio de búsqueda
            con_nro_etapa = false;
            if nargin > 3
                nro_etapa = varargin{1};
                con_nro_etapa = true;
            end
            proyectos_paralelos = [];
            etapas = [];
            proy_principal = this.Proyectos(id_proyecto_principal);
            if strcmp(proy_principal.entrega_tipo_proyecto(), 'AT') || strcmp(proy_principal.entrega_tipo_proyecto(), 'AL')
                par_index = proy_principal.Elemento(1).entrega_indice_paralelo();
                se1 = proy_principal.Elemento(1).entrega_se1();
                se2 = proy_principal.Elemento(1).entrega_se2();
                if con_nro_etapa
                    id_proyectos_plan = plan.entrega_proyectos(nro_etapa);
                else
                    id_proyectos_plan = plan.entrega_proyectos();
                end
                for i = 1:length(id_proyectos_plan)
                    proy = this.Proyectos(id_proyectos_plan(i));
                    if strcmp(proy.entrega_tipo_proyecto(), 'AT') || strcmp(proy.entrega_tipo_proyecto(), 'AL')
                        se1_proy = proy.Elemento(1).entrega_se1();
                        se2_proy = proy.Elemento(1).entrega_se2();
                        par_index_proy = proy.Elemento(1).entrega_indice_paralelo();
                        if se1 == se1_proy && se2 == se2_proy && par_index < par_index_proy
                            proyectos_paralelos = [proyectos_paralelos proy];
                            if con_nro_etapa
                                etapas = [etapas nro_etapa];
                            else
                                etapa_proy_paralelo = plan.entrega_etapa_proyecto(id_proyectos_plan(i));
                                etapas = [etapas etapa_proy_paralelo];
                            end
                        end
                    end
                end
            end
        end

        function [id_proyectos_paralelos, etapas]= entrega_id_proyectos_paralelos_parindex_creciente(this, plan, id_proyecto_principal, varargin)
            % varargin indica el número de etapa.
            % si se indica número de etapa entonces se buscan proyectos
            % sólo en la etapa indicada. Si no se indica nada, entonces se
            % buscan los proyectos en todo el espacio de búsqueda
            if nargin > 3
                nro_etapa = varargin{1};
                [proyectos_paralelos, etapas] = this.entrega_proyectos_paralelos_parindex_creciente(plan, id_proyecto_principal, nro_etapa);
            else
                [proyectos_paralelos, etapas] = this.entrega_proyectos_paralelos_parindex_creciente(plan, id_proyecto_principal);                
            end
            id_proyectos_paralelos = zeros(1,length(proyectos_paralelos));
            for i = 1:length(proyectos_paralelos)
                id_proyectos_paralelos(i) = proyectos_paralelos(i).entrega_indice();
            end
        end
        
        function proyectos_paralelos = entrega_proyectos_paralelos_parindex_creciente_acumulado(this, plan, nro_etapa, id_proyecto_principal)
            proyectos_paralelos = [];
            proy_principal = this.Proyectos(id_proyecto_principal);
            if strcmp(proy_principal.entrega_tipo_proyecto(), 'AT') || strcmp(proy_principal.entrega_tipo_proyecto(), 'AL')
                par_index = proy_principal.Elemento(1).entrega_indice_paralelo();
                se1 = proy_principal.Elemento(1).entrega_se1();
                se2 = proy_principal.Elemento(1).entrega_se2();
                id_proyectos_plan = plan.entrega_proyectos(nro_etapa);
                for i = 1:length(id_proyectos_plan)
                    proy = this.Proyectos(id_proyectos_plan(i));
                    if strcmp(proy.entrega_tipo_proyecto(), 'AT') || strcmp(proy.entrega_tipo_proyecto(), 'AL')
                        se1_proy = proy.Elemento(1).entrega_se1();
                        se2_proy = proy.Elemento(1).entrega_se2();
                        par_index_proy = proy.Elemento(1).entrega_indice_paralelo();
                        if se1 == se1_proy && se2 == se2_proy && par_index < par_index_proy
                            proyectos_paralelos = [proyectos_paralelos proy];
                        end
                    end
                end
            end
        end
        
        function costo_potencial = entrega_costo_potencial(this, espacio_busqueda, varargin)
            plan = cPlanExpansion.empty;
            if nargin > 2
                plan = varargin{1};
            end
            costo_potencial = zeros(1, length(espacio_busqueda));
            for i =1:length(espacio_busqueda)
                costo_potencial(i) = this.Proyectos(espacio_busqueda(i)).CostoPotencial;
                if ~isempty(plan)
                    % agrega costo potencial de requisitos de conectividad
                   proy = this.Proyectos(espacio_busqueda(i));
                   if proy.tiene_requisitos_conectividad()
                       % verifica si requisitos de conectividad están en el
                       % plan. En caso de que no, se agrega el promedio de
                       % los costos al costo potencial
                       cantidad = proy.entrega_cantidad_grupos_conectividad();
                       for ii = 1:cantidad
                           indice_proy_conect = proy.entrega_indices_grupo_proyectos_conectividad(ii);
                           if ~plan.conectividad_existe(indice_proy_conect)
                               costo_potencial(i) = costo_potencial(i) + this.entrega_costo_potencial_promedio(indice_proy_conect);
                           end
                       end
                   end
                end
            end
        end

        function costo_potencial = entrega_costo_potencial_con_etapa(this, espacio_busqueda, plan, tasa_descuento, detapa)
            costo_potencial = zeros(1, length(espacio_busqueda));
            for i =1:length(espacio_busqueda)
                costo_potencial(i) = this.Proyectos(espacio_busqueda(i)).CostoPotencial;
                etapa = plan.entrega_etapa_proyecto(espacio_busqueda(i));
                q = (1 + tasa_descuento);
                costo_potencial(i) = costo_potencial(i)/q^(detapa*etapa);
                
                % agrega costo potencial de requisitos de conectividad
                proy = this.Proyectos(espacio_busqueda(i));
                if proy.tiene_requisitos_conectividad()
                    % verifica si requisitos de conectividad están en el
                    % plan. En caso de que no, se agrega el promedio de
                    % los costos al costo potencial
                    cantidad = proy.entrega_cantidad_grupos_conectividad();
                    for ii = 1:cantidad
                        indice_proy_conect = proy.entrega_indices_grupo_proyectos_conectividad(ii);
                        if ~plan.conectividad_existe(indice_proy_conect)
                            costo_potencial(i) = costo_potencial(i) + this.entrega_costo_potencial_promedio(indice_proy_conect)/q^(detapa*etapa);
                        end
                    end
                end
            end
        end
        
        function cantidad = entrega_cantidad_proyectos_con_mismo_requisito_conectividad(this, plan, nro_etapa, id_proy_conectividad)
            % se verifica sólo hasta el número de etapa
            cantidad = 0;
            proy_conectividad = this.Proyectos(id_proy_conectividad);
            for i = 1:nro_etapa
                for j = 1:length(plan.Plan(i).Proyectos)
                    proy = this.Proyectos(plan.Plan(i).Proyectos(j));
                    if proy.TieneRequisitosConectividad
                        for k = 1:length(proy.ProyectosConectividad)
                            if sum(proy.ProyectosConectividad(k).Proyectos == proy_conectividad) == 1
                                cantidad = cantidad + 1;
                            end
                        end
                    end
                end
            end
        end

        function [id_proyectos, etapas] = entrega_proyectos_con_mismo_requisito_conectividad(this, plan, id_proy_conectividad)
            id_proyectos = [];
            etapas = [];
            proy_conectividad = this.Proyectos(id_proy_conectividad);
            for i = 1:length(plan.Plan)
                for j = 1:length(plan.Plan(i).Proyectos)
                    proy = this.Proyectos(plan.Plan(i).Proyectos(j));
                    if proy.TieneRequisitosConectividad
                        for k = 1:length(proy.ProyectosConectividad)
                            if sum(proy.ProyectosConectividad(k).Proyectos == proy_conectividad) == 1
                                id_proyectos = [id_proyectos proy.Indice];
                                etapas = [etapas i];
                                break; % ProyectosConectividad
                            end
                        end
                    end
                end
            end
        end
        
        function costo_potencial = entrega_costo_potencial_promedio(this, indices)
            costo_potencial = 0;
            for i = 1:length(indices)
                costo_potencial = costo_potencial + this.Proyectos(indices(i)).CostoPotencial;
            end
            costo_potencial = costo_potencial/length(indices);
        end
                
        function calcula_costo_promedio_proyectos(this)
            costo = 0;
            for i = 1:length(this.Proyectos)
                this.Proyectos(i).calcula_costo_potencial();
                costo = costo + this.Proyectos(i).entrega_costo_potencial();
            end
            
            this.CostoPromedioProyectos = costo/length(this.Proyectos);
        end
        
        function proyecto = entrega_proyecto(this, indice)
            %entrega una copia del proyecto            
            proyecto = this.Proyectos(indice);
        end
     
        function agrega_proyectos_obligatorios(this, subestacion)
           %busca proyectos que conecten la subestacion y los guarda en
           %ProyectosObligatorios.
           indice = length(this.ProyectosObligatorios)+1;
           primero = true;
           ubicacion = subestacion.entrega_ubicacion();
           for i = 1:length(this.Proyectos)
               if ~strcmp(this.Proyectos(i).entrega_tipo_proyecto(),'AL')
                   % sólo proyectos consistentes en agregar linea
                   continue;
               end
               if this.Proyectos(i).TieneDependencia
                   %no se consideran proyectos con dependencia para los
                   %proyectos obligatorios
                   continue;
               end
               [se1, se2] = this.Proyectos(i).Elemento(1).entrega_subestaciones();
               ubic_1 = se1.entrega_ubicacion();
               ubic_2 = se2.entrega_ubicacion();
               if (ubic_1 == ubicacion) || (ubic_2 == ubicacion)
                   if primero
                       this.ProyectosObligatorios(indice).Proyectos = this.Proyectos(i);
                       if subestacion.Existente
                           % obligatorio para todos los escenarios en la
                           % primera etapa de entrada
                           this.ProyectosObligatorios(indice).Entrada = [1:1:length(this.Escenarios); ones(1,length(this.Escenarios))]';
                       else
                           % hay que identificar en qué escenario y etapa
                           for jj = 1:length(this.Escenarios)
                               etapa_entrada = this.entrega_etapa_subestacion_proyectada(subestacion, jj);
                               this.ProyectosObligatorios(indice).Entrada(jj,1) = jj; %escenario y etapa
                               this.ProyectosObligatorios(indice).Entrada(jj,2) = etapa_entrada; %escenario y etapa
                           end
                       end
                       primero = false;
                   else
                       this.ProyectosObligatorios(indice).Proyectos = [this.ProyectosObligatorios(indice).Proyectos this.Proyectos(i)];
                   end
               end
           end
        end
        
        function agrega_proyectos_excluyentes(this, proyectos)
            indice = length(this.ProyectosExcluyentes)+1;
            id_proyectos = zeros(length(proyectos), 1);
            for i = 1:length(proyectos)
                id_proyectos(i) = proyectos(i).entrega_indice();
            end
            this.ProyectosExcluyentes(indice).Proyectos= id_proyectos;
        end
        
        function imprime_proyectos(this)
            prot = cProtocolo.getInstance;
            prot.imprime_texto('Proyectos de expansion:\n');

            texto = sprintf('%-5s %-7s %-5s %-30s %-10s %-20s %-20s %-50s', 'Id', 'Tipo', 'UpR', 'Elemento', 'Accion', 'Dep', 'Conect', 'Nombre');
            prot.imprime_texto(texto);
            for i = 1:length(this.Proyectos)
                indice = num2str(this.Proyectos(i).Indice);
                %prot.imprime_texto(num2str(this.Proyectos(i).Indice));
                if this.Proyectos(i).TieneDependencia
                    dependencias = '';
                    for dep = 1:length(this.Proyectos(i).ProyectoDependiente)
                        dependencias = [dependencias ' ' num2str(this.Proyectos(i).ProyectoDependiente(dep).Indice)];
                    end
                else
                    dependencias = '-';
                end
                
                if this.Proyectos(i).TieneRequisitosConectividad
                    conectividad = '';
                    for con = 1:length(this.Proyectos(i).ProyectosConectividad)
                        for ii = 1:length(this.Proyectos(i).ProyectosConectividad(con).Proyectos)
                            conectividad = [conectividad ' ' num2str(this.Proyectos(i).ProyectosConectividad(con).Proyectos(ii).Indice)];
                        end
                        conectividad = [conectividad ' ;'];
                    end
                else
                    conectividad = '-';
                end
                for elem = 1:length(this.Proyectos(i).Elemento)
                    if elem == 1
                        texto = sprintf('%-5s %-7s %-5s %-30s %-10s %-20s %-20s %-50s', indice, ...
                                                        this.Proyectos(i).entrega_tipo_proyecto(), ... 
                                                        num2str(this.Proyectos(i).EsUprating), ... 
                                                        this.Proyectos(i).Elemento(elem).entrega_nombre(), ...
                                                        this.Proyectos(i).Accion{elem},...
                                                        dependencias, ...
                                                        conectividad,...
                                                        this.Proyectos(i).entrega_nombre());
                    else
                        texto = sprintf('%-5s %-7s %-5s %-30s %-10s', ' ', ' ', ' ', this.Proyectos(i).Elemento(elem).entrega_nombre(), this.Proyectos(i).Accion{elem});
                    end
                    prot.imprime_texto(texto);
                end
            end

            prot.imprime_texto('');
            prot.imprime_texto('Proyectos obligatorios:');
            for i = 1:length(this.ProyectosObligatorios)
                prot.imprime_texto(['Grupo: ' num2str(i)]);
                for j = 1:length(this.ProyectosObligatorios(i).Proyectos)
                    prot.imprime_texto(num2str(this.ProyectosObligatorios(i).Proyectos(j).entrega_indice()));
                end
            end

            prot.imprime_texto('');
            prot.imprime_texto('Proyectos excluyentes:');
            texto = sprintf('%-5s %-10s', 'Indice', 'Proyectos');
            prot.imprime_texto(texto);
            for i = 1:length(this.ProyectosExcluyentes)
                id_proy = '';
                for proy = 1:length(this.ProyectosExcluyentes(i).Proyectos)
                    id_proy = [id_proy ' ' num2str(this.ProyectosExcluyentes(i).Proyectos(proy))];
                end
                texto = sprintf('%-5s %-10s', num2str(i), id_proy);
                prot.imprime_texto(texto);
            end

            prot.imprime_texto('');
            prot.imprime_texto('Dependencias cambios de estado:');
            texto = sprintf('%-5s %-30s %-50s %-50s', 'Id', 'Elemento a remover', 'Proyectos dependientes', 'Nombre proyecto');
            prot.imprime_texto(texto);
            for i = 1:length(this.Proyectos)
                if strcmp(this.Proyectos(i).entrega_tipo_proyecto(), 'CC') || ...
                    strcmp(this.Proyectos(i).entrega_tipo_proyecto(), 'CS') || ...
                    strcmp(this.Proyectos(i).entrega_tipo_proyecto(), 'AV')
                    primero = true;
                    for j = 1:length(this.Proyectos(i).Elemento)
                        if strcmp(this.Proyectos(i).Accion(j),'R')
                            proy_dep = this.Proyectos(i).entrega_dependencias_elemento_a_remover(this.Proyectos(i).Elemento(j));
                            id_proyectos = '';
                            for k = 1:length(proy_dep)
                                id_proyectos = [id_proyectos ' ' num2str(proy_dep(k).entrega_indice())];
                            end
                            
                            if primero
                            	texto = sprintf('%-5s %-30s %-50s %-50s',num2str(this.Proyectos(i).entrega_indice()) , ...
                                                                         this.Proyectos(i).Elemento(j).entrega_nombre(), ...
                                                                         id_proyectos, ...
                                                                         this.Proyectos(i).entrega_nombre());
                                primero = false;
                            else
                            	texto = sprintf('%-5s %-30s %-50s ',' ' , ...
                                                                         this.Proyectos(i).Elemento(j).entrega_nombre(), ...
                                                                         id_proyectos);
                            end
                            
                            prot.imprime_texto(texto);
                        end
                    end
                end
            end
            
            prot.imprime_texto('');
            prot.imprime_texto('Costo proyectos por elemento (no es costo total de inversion):');
            texto = sprintf('%-5s %-7s %-30s %-8s %-10s %-10s %-50s', 'Id', 'Tipo', 'Elemento', 'Accion', 'Costo', 'Cum', 'Nombre proyecto');
            prot.imprime_texto(texto);
            for i = 1:length(this.Proyectos)
                primero = true;
                cambio = false;
                cum_costo = 0;
                for j = length(this.Proyectos(i).Elemento):-1:1
                    if strcmp(this.Proyectos(i).entrega_tipo_proyecto(),'CS')
                        costo_individual = this.Proyectos(i).Elemento(j).entrega_costo_compensacion_serie();
                    elseif strcmp(this.Proyectos(i).entrega_tipo_proyecto(),'CC')
                        costo_individual = this.Proyectos(i).Elemento(j).entrega_costo_conductor();
                    else
                        costo_individual = this.Proyectos(i).Elemento(j).entrega_costo_inversion();
                    end
                    if strcmp(this.Proyectos(i).Accion{j},'A')
                    	cum_costo = cum_costo + costo_individual;
                        if primero
                        	texto = sprintf('%-5s %-7s %-30s %-8s %-10s %-10s %-50s',num2str(this.Proyectos(i).entrega_indice()) , ...
                                                                          this.Proyectos(i).entrega_tipo_proyecto(), ...
                                                                          this.Proyectos(i).Elemento(j).entrega_nombre(), ...
                                                                          this.Proyectos(i).Accion{j}, ...
                                                                          num2str(costo_individual), ...
                                                                          num2str(cum_costo), ...
                                                                          this.Proyectos(i).entrega_nombre());
                            primero = false;
                        else
                            texto = sprintf('%-5s %-7s %-30s %-8s %-10s %-10s',' ' , ' ', ...
                                                                         this.Proyectos(i).Elemento(j).entrega_nombre(), ...
                                                                         this.Proyectos(i).Accion{j}, ...
                                                                         num2str(costo_individual), ...
                                                                         num2str(cum_costo));
                        end
                        prot.imprime_texto(texto);
                    else
                        if ~cambio
                        	cambio = true;
                            cum_costo = 0;
                        end
                        cum_costo = cum_costo - costo_individual;
                        texto = sprintf('%-5s %-7s %-30s %-8s %-10s %-10s',' ', ' ', ...
                                                                     this.Proyectos(i).Elemento(j).entrega_nombre(), ...
                                                                     this.Proyectos(i).Accion{j}, ...
                                                                     num2str(costo_individual), ...
                                                                     num2str(cum_costo));
                        prot.imprime_texto(texto);
                    end
                end
            end
        end

        function imprime_proyectos_publicacion(this)
            prot = cProtocolo.getInstance;
            prot.imprime_texto('Proyectos de expansion:\n');

            texto = sprintf('%-5s %-7s %-5s %-30s %-10s %-20s %-20s %-50s', 'Nr', 'Tipo', 'UpR', 'Elemento', 'Accion', 'Dep', 'Conect', 'Nombre');
            prot.imprime_texto(texto);
            for i = 1:length(this.Proyectos)
                indice = num2str(this.Proyectos(i).Indice);
                %prot.imprime_texto(num2str(this.Proyectos(i).Indice));
                if this.Proyectos(i).TieneDependencia
                    dependencias = '';
                    for dep = 1:length(this.Proyectos(i).ProyectoDependiente)
                        dependencias = [dependencias ' ' num2str(this.Proyectos(i).ProyectoDependiente(dep).Indice)];
                    end
                else
                    dependencias = '-';
                end
                
                if this.Proyectos(i).TieneRequisitosConectividad
                    conectividad = '';
                    for con = 1:length(this.Proyectos(i).ProyectosConectividad)
                        for ii = 1:length(this.Proyectos(i).ProyectosConectividad(con).Proyectos)
                            conectividad = [conectividad ' ' num2str(this.Proyectos(i).ProyectosConectividad(con).Proyectos(ii).Indice)];
                        end
                        conectividad = [conectividad ' ;'];
                    end
                else
                    conectividad = '-';
                end
                for elem = 1:length(this.Proyectos(i).Elemento)
                    if elem == 1
                        texto = sprintf('%-5s %-7s %-5s %-30s %-10s %-20s %-20s %-50s', indice, ...
                                                        this.Proyectos(i).entrega_tipo_proyecto(), ... 
                                                        num2str(this.Proyectos(i).EsUprating), ... 
                                                        this.Proyectos(i).Elemento(elem).entrega_nombre(), ...
                                                        this.Proyectos(i).Accion{elem},...
                                                        dependencias, ...
                                                        conectividad,...
                                                        this.Proyectos(i).entrega_nombre());
                    else
                        texto = sprintf('%-5s %-7s %-5s %-30s %-10s', ' ', ' ', ' ', this.Proyectos(i).Elemento(elem).entrega_nombre(), this.Proyectos(i).Accion{elem});
                    end
                    prot.imprime_texto(texto);
                end
            end

            prot.imprime_texto('');
            prot.imprime_texto('Proyectos obligatorios:');
            for i = 1:length(this.ProyectosObligatorios)
                prot.imprime_texto(['Grupo: ' num2str(i)]);
                for j = 1:length(this.ProyectosObligatorios(i).Proyectos)
                    prot.imprime_texto(num2str(this.ProyectosObligatorios(i).Proyectos(j).entrega_indice()));
                end
            end

            prot.imprime_texto('');
            prot.imprime_texto('Proyectos excluyentes:');
            texto = sprintf('%-5s %-10s', 'Indice', 'Proyectos');
            prot.imprime_texto(texto);
            for i = 1:length(this.ProyectosExcluyentes)
                id_proy = '';
                for proy = 1:length(this.ProyectosExcluyentes(i).Proyectos)
                    id_proy = [id_proy ' ' num2str(this.ProyectosExcluyentes(i).Proyectos(proy))];
                end
                texto = sprintf('%-5s %-10s', num2str(i), id_proy);
                prot.imprime_texto(texto);
            end

            prot.imprime_texto('');
            prot.imprime_texto('Dependencias cambios de estado:');
            texto = sprintf('%-5s %-30s %-50s %-50s', 'Id', 'Elemento a remover', 'Proyectos dependientes', 'Nombre proyecto');
            prot.imprime_texto(texto);
            for i = 1:length(this.Proyectos)
                if strcmp(this.Proyectos(i).entrega_tipo_proyecto(), 'CC') || ...
                    strcmp(this.Proyectos(i).entrega_tipo_proyecto(), 'CS') || ...
                    strcmp(this.Proyectos(i).entrega_tipo_proyecto(), 'AV')
                    primero = true;
                    for j = 1:length(this.Proyectos(i).Elemento)
                        if strcmp(this.Proyectos(i).Accion(j),'R')
                            proy_dep = this.Proyectos(i).entrega_dependencias_elemento_a_remover(this.Proyectos(i).Elemento(j));
                            id_proyectos = '';
                            for k = 1:length(proy_dep)
                                id_proyectos = [id_proyectos ' ' num2str(proy_dep(k).entrega_indice())];
                            end
                            
                            if primero
                            	texto = sprintf('%-5s %-30s %-50s %-50s',num2str(this.Proyectos(i).entrega_indice()) , ...
                                                                         this.Proyectos(i).Elemento(j).entrega_nombre(), ...
                                                                         id_proyectos, ...
                                                                         this.Proyectos(i).entrega_nombre());
                                primero = false;
                            else
                            	texto = sprintf('%-5s %-30s %-50s ',' ' , ...
                                                                         this.Proyectos(i).Elemento(j).entrega_nombre(), ...
                                                                         id_proyectos);
                            end
                            
                            prot.imprime_texto(texto);
                        end
                    end
                end
            end
            
            prot.imprime_texto('');
            prot.imprime_texto('Costo proyectos por elemento (no es costo total de inversion):');
            texto = sprintf('%-5s %-7s %-30s %-8s %-10s %-10s %-50s', 'Id', 'Tipo', 'Elemento', 'Accion', 'Costo', 'Cum', 'Nombre proyecto');
            prot.imprime_texto(texto);
            for i = 1:length(this.Proyectos)
                primero = true;
                cambio = false;
                cum_costo = 0;
                for j = length(this.Proyectos(i).Elemento):-1:1
                    if strcmp(this.Proyectos(i).entrega_tipo_proyecto(),'CS')
                        costo_individual = this.Proyectos(i).Elemento(j).entrega_costo_compensacion_serie();
                    elseif strcmp(this.Proyectos(i).entrega_tipo_proyecto(),'CC')
                        costo_individual = this.Proyectos(i).Elemento(j).entrega_costo_conductor();
                    else
                        costo_individual = this.Proyectos(i).Elemento(j).entrega_costo_inversion();
                    end
                    if strcmp(this.Proyectos(i).Accion{j},'A')
                    	cum_costo = cum_costo + costo_individual;
                        if primero
                        	texto = sprintf('%-5s %-7s %-30s %-8s %-10s %-10s %-50s',num2str(this.Proyectos(i).entrega_indice()) , ...
                                                                          this.Proyectos(i).entrega_tipo_proyecto(), ...
                                                                          this.Proyectos(i).Elemento(j).entrega_nombre(), ...
                                                                          this.Proyectos(i).Accion{j}, ...
                                                                          num2str(costo_individual), ...
                                                                          num2str(cum_costo), ...
                                                                          this.Proyectos(i).entrega_nombre());
                            primero = false;
                        else
                            texto = sprintf('%-5s %-7s %-30s %-8s %-10s %-10s',' ' , ' ', ...
                                                                         this.Proyectos(i).Elemento(j).entrega_nombre(), ...
                                                                         this.Proyectos(i).Accion{j}, ...
                                                                         num2str(costo_individual), ...
                                                                         num2str(cum_costo));
                        end
                        prot.imprime_texto(texto);
                    else
                        if ~cambio
                        	cambio = true;
                            cum_costo = 0;
                        end
                        cum_costo = cum_costo - costo_individual;
                        texto = sprintf('%-5s %-7s %-30s %-8s %-10s %-10s',' ', ' ', ...
                                                                     this.Proyectos(i).Elemento(j).entrega_nombre(), ...
                                                                     this.Proyectos(i).Accion{j}, ...
                                                                     num2str(costo_individual), ...
                                                                     num2str(cum_costo));
                        prot.imprime_texto(texto);
                    end
                end
            end
        end
        
        function imprime_proyectos_seleccionados(this, proyectos, varargin)
            if nargin > 2
                titulo = varargin{1};
            else
                titulo = 'Proyectos seleccionados:\n';
            end
            prot = cProtocolo.getInstance;
            prot.imprime_texto(titulo);

            texto = sprintf('%-5s %-7s %-5s %-30s %-10s %-20s %-20s %-50s', 'Id', 'Tipo', 'UpR', 'Elemento', 'Accion', 'Dep', 'Conect', 'Nombre');
            prot.imprime_texto(texto);
            for i = 1:length(proyectos)
                indice = num2str(proyectos(i).Indice);
                %prot.imprime_texto(num2str(this.Proyectos(i).Indice));
                if proyectos(i).TieneDependencia
                    dependencias = '';
                    for dep = 1:length(proyectos(i).ProyectoDependiente)
                        dependencias = [dependencias ' ' num2str(proyectos(i).ProyectoDependiente(dep).Indice)];
                    end
                else
                    dependencias = '-';
                end
                
                if proyectos(i).TieneRequisitosConectividad
                    conectividad = '';
                    for con = 1:length(proyectos(i).ProyectosConectividad)
                        for ii = 1:length(proyectos(i).ProyectosConectividad(con).Proyectos)
                            conectividad = [conectividad ' ' num2str(proyectos(i).ProyectosConectividad(con).Proyectos(ii).Indice)];
                        end
                        conectividad = [conectividad ' ;'];
                    end
                else
                    conectividad = '-';
                end
                for elem = 1:length(proyectos(i).Elemento)
                    if elem == 1
                        texto = sprintf('%-5s %-7s %-5s %-30s %-10s %-20s %-20s %-50s', indice, ...
                                                        proyectos(i).entrega_tipo_proyecto(), ... 
                                                        num2str(proyectos(i).EsUprating), ... 
                                                        proyectos(i).Elemento(elem).entrega_nombre(), ...
                                                        proyectos(i).Accion{elem},...
                                                        dependencias, ...
                                                        conectividad,...
                                                        proyectos(i).entrega_nombre());
                    else
                        texto = sprintf('%-5s %-7s %-5s %-30s %-10s', ' ', ' ', ' ', proyectos(i).Elemento(elem).entrega_nombre(), proyectos(i).Accion{elem});
                    end
                    prot.imprime_texto(texto);
                end
            end
        end
        
        function inserta_elemento_serie_expansion(this, el_red)
            % primero verifica si elemento de red ya se encuentra o no.
            % Este paso no afecta la performance
            if ~ismember(el_red, this.ElementosSerie)
                cantidad = length(this.ElementosSerie); 
                this.ElementosSerie(cantidad+1,1) = el_red;
                el_red.IdAdmProyectos = cantidad + 1;
                this.EstadoElementosSerie(cantidad+1,1) = 0;
                this.RelElementosSerieSE(cantidad+1,1) = el_red.entrega_se1().entrega_id_adm_proyectos();
                this.RelElementosSerieSE(cantidad+1,2) = el_red.entrega_se2().entrega_id_adm_proyectos();
            else
                error = MException('cAdministradorProyectos:inserta_elemento_serie_expansion','elemento de red ya se encuentra incorporado');
                throw(error)
            end
        end

        function inserta_elemento_serie_existente(this, el_red)
            % primero verifica si elemento de red ya se encuentra o no.
            % Este paso no afecta la performance
            if ~ismember(el_red, this.ElementosSerie)
                cantidad = length(this.ElementosSerie); 
                this.ElementosSerie(cantidad+1,1) = el_red;
                el_red.IdAdmProyectos = cantidad + 1;
                this.EstadoElementosSerie(cantidad+1,1) = 1;
                this.RelElementosSerieSE(cantidad+1,1) = el_red.entrega_se1().entrega_id_adm_proyectos();
                this.RelElementosSerieSE(cantidad+1,2) = el_red.entrega_se2().entrega_id_adm_proyectos();
            else
                error = MException('cAdministradorProyectos:inserta_elemento_serie_existente','elemento de red ya se encuentra incorporado');
                throw(error)
            end
        end

        function inserta_elemento_paralelo_expansion(this, el_red)
            % primero verifica si elemento de red ya se encuentra o no.
            % Este paso no afecta la performance
            if ~ismember(el_red, this.ElementosParalelos)
                cantidad = length(this.ElementosParalelos); 
                this.ElementosParalelos(cantidad+1,1) = el_red;
                el_red.IdAdmProyectos = cantidad+1;
                this.EstadoElementosParalelos(cantidad+1,1) = 0;
                this.RelElementosParalelosSE(cantidad+1,1) = el_red.entrega_se().entrega_id_adm_proyectos();
            else
                error = MException('cAdministradorProyectos:inserta_elemento_paralelo_existente','elemento de red ya se encuentra incorporado');
                throw(error)
            end
        end
        
        function inserta_elemento_paralelo_existente(this, el_red)
            % primero verifica si elemento de red ya se encuentra o no.
            % Este paso no afecta la performance
            if ~ismember(el_red, this.ElementosParalelos)
                cantidad = length(this.ElementosParalelos); 
                this.ElementosParalelos(cantidad+1,1) = el_red;
                el_red.IdAdmProyectos = cantidad+1;
                this.EstadoElementosParalelos(cantidad+1,1) = 1;
                this.RelElementosParalelosSE(cantidad+1,1) = el_red.entrega_se().entrega_id_adm_proyectos();
            else
                error = MException('cAdministradorProyectos:inserta_elemento_paralelo_existente','elemento de red ya se encuentra incorporado');
                throw(error)
            end
        end
        
        function inserta_subestacion_existente(this, el_red)
            % primero verifica si elemento de red ya se encuentra o no.
            % Este paso no afecta la performance
            if ~ismember(el_red, this.Subestaciones)
                cantidad = length(this.Subestaciones); 
                this.Subestaciones(cantidad+1,1) = el_red;
                this.EstadoSubestaciones(cantidad+1,1) = 1;
                el_red.IdAdmProyectos = cantidad + 1;
            else
                error = MException('cAdministradorProyectos:inserta_subestacion_existente','elemento de red ya se encuentra incorporado');
                throw(error)
            end
        end

        function inserta_subestacion_expansion(this, el_red)
            % primero verifica si elemento de red ya se encuentra o no.
            % Este paso no afecta la performance
            if ~ismember(el_red, this.Subestaciones)
                cantidad = length(this.Subestaciones); 
                this.Subestaciones(cantidad+1,1) = el_red;
                this.EstadoSubestaciones(cantidad+1,1) = 0;
                el_red.IdAdmProyectos = cantidad + 1;
            else
                error = MException('cAdministradorProyectos:inserta_subestacion_expansion','elemento de red ya se encuentra incorporado');
                throw(error)
            end
        end
        
        function el_red = entrega_elementos_serie(this)
            el_red = this.ElementosSerie;
        end
        
        function el_red = entrega_elementos_serie_expansion(this)
            el_red = this.ElementosSerie(this.EstadoElementosSerie == 0);
        end

        function el_red = entrega_elementos_paralelos_expansion(this)
            el_red = this.ElementosParalelos(this.EstadoElementosParalelos == 0);
        end
        
        function el_red = entrega_elementos_paralelos(this)
            el_red = this.ElementosParalelos;
        end
        
        function el_red = entrega_elementos_serie_por_subestacion(this, se)
            id_adm_proy = se.entrega_id_adm_proyectos();
            el_red = this.ElementosSerie(this.RelElementosSerieSE(:,1) == id_adm_proy);
            el_red = [el_red; this.ElementosSerie(this.RelElementosSerieSE(:,2) == id_adm_proy)];
        end

        function el_red = entrega_elementos_paralelos_por_subestacion(this, se)
            % Sólo elementos de expansión. Por ahora, baterías
            id_adm_proy = se.entrega_id_adm_proyectos();
            if ~isempty(this.ElementosParalelos)
                el_red = this.ElementosParalelos(this.RelElementosParalelosSE(:,1) == id_adm_proy);
            else
                el_red = cElementoRed.empty;
            end
        end
        
        function el_red = entrega_elementos_serie_por_caracteristicas(this, tipo, varargin)
            el_red = cElementoRed.empty;
            if strcmp(tipo,'cTransformador2D')
                ubicacion = varargin{1};
                vat = varargin{2};
                vbt = varargin{3};
                lpar = varargin{4};
                for i = 1:length(this.ElementosSerie)
                    if isa(this.ElementosSerie(i),'cTransformador2D')
                        vat_elred = this.ElementosSerie(i).entrega_se1().entrega_vn();
                        vbt_elred = this.ElementosSerie(i).entrega_se2().entrega_vn();
                        ubicacion_elred = this.ElementosSerie(i).entrega_se1().entrega_ubicacion();
                        idpar = this.ElementosSerie(i).entrega_indice_paralelo();
                        if vat == vat_elred && ...
                           vbt == vbt_elred && ...
                           ubicacion == ubicacion_elred && ...
                           idpar == lpar
                            el_red = this.ElementosSerie(i);
                        end
                    end
                end
            else
                error = MException('cAdministradorProyectos:entrega_elementos_serie_por_caracteristicas','tipo entregado no implementado');
                throw(error)
            end
        end
        
        function el_red = entrega_subestaciones_existentes(this)
            el_red = this.Subestaciones(this.EstadoSubestaciones == 1);
        end
        
        function el_red = entrega_subestaciones_expansion(this)
            el_red = this.Subestaciones(this.EstadoSubestaciones == 0);
        end
        
        function val = entrega_cantidad_subestaciones_existentes(this)
            val = length(this.Subestaciones(this.EstadoSubestaciones == 1));
        end
        
        function proyectos = entrega_proyectos(this)
            proyectos = this.Proyectos;
        end
        
        function el_red = entrega_elemento_serie_por_nombre(this, nombre)
            for i = 1:length(this.ElementosSerie)
                if strcmp(this.ElementosSerie(i).entrega_nombre(), nombre)
                    el_red = this.ElementosSerie(i);
                    return;
                end
            end
            error = MException('cAdministradorProyectos:entrega_elemento_serie','elemento de red no se encuentra');
            throw(error)
        end

        function el_red = entrega_subestacion_por_nombre(this, nombre, varargin)
            obligatorio = true;
            if nargin >2
                obligatorio = varargin{1};
            end
            for i = 1:length(this.Subestaciones)
                if strcmp(this.Subestaciones(i).entrega_nombre(), nombre)
                    el_red = this.Subestaciones(i);
                    return;
                end
            end
            if obligatorio
                error = MException('cAdministradorProyectos:entrega_subestacion_por_nombre','Subestacion no se encuentra y flag obligatorio activa');
                throw(error)
            else
                el_red = cElementoRed.empty;
            end
        end
        
        function genera_dependencias_cambios_estado(this)
            if this.iNivelDebug > 1
                disp('genera dependencias cambios estado ');
            end
            % genera dependencias de elementos a remover con respectivos
            % proyectos que contienen agregar el elemento respectivo
            contador_disp = 10;
            for i = 1:length(this.Proyectos)
                if this.iNivelDebug > 1
                    porcentaje =i/length(this.Proyectos)*100;
                    if porcentaje > contador_disp
                        fprintf('%s %s',' ', [num2str(contador_disp) '%']);
                        pause(0.1)
                        contador_disp = contador_disp + 10;
                    end
                end
                if strcmp(this.Proyectos(i).entrega_tipo_proyecto(), 'CC') || ...
                    strcmp(this.Proyectos(i).entrega_tipo_proyecto(), 'CS') || ...
                    strcmp(this.Proyectos(i).entrega_tipo_proyecto(), 'AV')
                    elementos = cElementoRed.empty;
                    contador = 0;
                    for j = 1:length(this.Proyectos(i).Elemento)
                        if strcmp(this.Proyectos(i).Accion(j),'R')
                            contador = contador + 1;
                            elementos(contador) = this.Proyectos(i).Elemento(j);
                            dependencias(contador).Proyectos = cProyectoExpansion.empty;
                        end
                    end
                    dependencias_res = this.entrega_proyectos_dependientes(this.Proyectos(i),elementos, 'A',dependencias);
                    this.Proyectos(i).agrega_dependencias_elementos_a_remover(elementos, dependencias_res);
                end
            end
            if this.iNivelDebug > 1
                fprintf('%s %s\n',' ', [num2str(100) '%']);
            end
            
        end
        function proyectos = entrega_proyectos_dependientes(this, proyecto_base, elementos, accion, proyectos)
            % busca todos los proyectos que contienen elred y accion en
            % forma recursiva a partir del proyecto base
            %proyectos = cProyectoExpansion.empty;
            dependientes = proyecto_base.ProyectoDependiente;
            for i = 1:length(dependientes)
                for j = 1:length(dependientes(i).Elemento)
                    for k = 1:length(elementos)
                        elred = elementos(k);
                        if dependientes(i).Elemento(j) == elred && strcmp(dependientes(i).Accion(j), accion)
                            encontrado = false;
                            for proy_acum = 1:length(proyectos(k).Proyectos)
                                if proyectos(k).Proyectos(proy_acum) == dependientes(i)
                                    encontrado = true;
                                end
                            end
                            if ~encontrado
                                proyectos(k).Proyectos = [proyectos(k).Proyectos dependientes(i)];
                            end
                        end
                    end
                end
                % busca en "sus" proyectos dependientes
                proyectos_nuevo = this.entrega_proyectos_dependientes(dependientes(i), elementos, accion, proyectos);
                proyectos = proyectos_nuevo;
           end
        end
        
        function genera_indices_proyectos(this)
            % índices de proyectos obligatorios
            for i = 1:length(this.ProyectosObligatorios)
                for j = 1:length(this.ProyectosObligatorios(i).Proyectos)
                    this.ProyectosObligatorios(i).Indice(j) = this.ProyectosObligatorios(i).Proyectos(j).entrega_indice();
                end
            end
            %índices de proyectos dependientes. Por cada proyecto. Esto se hace sólo una vez
            for i = 1:length(this.Proyectos)
                this.Proyectos(i).genera_indices_proyectos_dependientes();
            end
%             for i = 1:length(this.Proyectos)
%                 this.Proyectos(i).IndiceProyectosAguasArriba = [];
%                 for j = i+1:length(this.Proyectos)
%                     proy_dep = this.Proyectos(j).entrega_indices_proyectos_dependientes();
%                     if ismember(i, proy_dep)
%                         this.Proyectos(i).IndiceProyectosAguasArriba = [this.Proyectos(i).IndiceProyectosAguasArriba j];
%                     end
%                 end
%             end
        end
        
        function consistente = verifica_consistencia_plan(this, plan)
            cantidad_etapas = length(plan.Plan);
            for nro_etapa = 1:cantidad_etapas
                cantidad_proyectos = length(plan.Plan(nro_etapa).Proyectos);
                for nro_proy_etapa = 1:cantidad_proyectos
                    proyecto = this.Proyectos(plan.Plan(nro_etapa).Proyectos(nro_proy_etapa));
                    if proyecto.TieneDependencia
                       % busca si proyecto dependiente está en el plan
                       proy_dep = proyecto.IndiceProyectoDependiente;
                       [existe, etapa] = plan.dependencia_existe(proy_dep);
                       if ~existe
                           consistente = false;
                           return
                       elseif etapa > nro_etapa
                           consistente = false;
                           return
                       end
                    end
                end
            end
            consistente = true;
        end
        
        function indices = entrega_indices_proyectos_obligatorios(this, grupo)
            indices = this.ProyectosObligatorios(grupo).Indice;
        end
        
        function cantidad = entrega_cantidad_proyectos_obligatorios(this)
            cantidad = length(this.ProyectosObligatorios);
        end
        
        function proy = entrega_proyectos_obligatorios_por_etapa(this, escenario, etapa)
            cant_proy = 0;
            proy = [];
            for i = 1:length(this.ProyectosObligatorios)
                if(ismember([escenario etapa], this.ProyectosObligatorios(i).Entrada,'rows'))
                	cant_proy = cant_proy + 1;
                    proy(cant_proy).Proyectos = this.ProyectosObligatorios(i).Proyectos;
                end
            end
        end
        
        function costo_inversion = calcula_costo_inversion_proyecto(this, proyecto, etapa_inv, plan, factor_desarrollo)
            costo_inversion = proyecto.entrega_costos_inversion()*factor_desarrollo;
            
            for i = 1:length(proyecto.Elemento)
                if strcmp(proyecto.Accion{i}, 'R')
                    if strcmp(proyecto.entrega_tipo_proyecto(), 'CS') || ...
                             (strcmp(proyecto.entrega_tipo_proyecto(), 'AV') && ...
                        	  ~proyecto.cambio_conductor_aumento_voltaje())
                          continue;
                    end
                    
                    vida_util = proyecto.Elemento(i).entrega_vida_util();
                    % elemento se remueve. Hay que calcular valor residual
                    proy_dependientes = proyecto.entrega_dependencias_elemento_a_remover(proyecto.Elemento(i));
                    costo_elemento = proyecto.Elemento(i).entrega_costo_conductor();
                    if isempty(proy_dependientes)
                        % elemento pertenece al SEP
                        anio_construccion = proyecto.Elemento(i).entrega_anio_construccion();
                        d_etapa = this.TInicio - anio_construccion + (etapa_inv-1)*this.DeltaEtapa;
                        valor_residual = costo_elemento*(1-d_etapa/vida_util);
                        if valor_residual < 0
                        	valor_residual = 0;
                        end
                    else
                        % identifica proyecto dependiente
                        proy_dep_identificado = false;
                        for j = 1:length(proy_dependientes)
                            etapa = plan.entrega_etapa_proyecto(proy_dependientes(j).entrega_indice(), false);
                            if etapa > 0
                                proy_dep_identificado = true;
                                valor_residual = costo_elemento*(1-(etapa_inv-etapa)*this.DeltaEtapa/vida_util);
                                break;
                            end
                        end
                        if ~proy_dep_identificado
                            error = MException('cAdministradorProyectos:calcula_costo_inversion_proyecto','Proyecto dependiente no fue identificado');
                            throw(error)
                        end
                    end
                    costo_inversion = costo_inversion - valor_residual;
                end
            end
        end
        
        function inserta_delta_etapa(this, detapa)
            this.DeltaEtapa = detapa;
        end
        
        function inserta_t_inicio(this, t_inicio)
            this.TInicio = t_inicio;
        end
        
        function inserta_etapa_final(this, etapa_final)
            this.EtapaFinal = etapa_final;
        end
        
        function inserta_cantidad_escenarios(this, cant_escenarios)
            this.CantidadEscenarios = cant_escenarios;
        end
        
        function val = entrega_cantidad_proyectos_con_dependencia(this)
            val = this.CantidadProyectosConDependencia;
        end
        
        function inserta_elementos_serie_existentes(this, elementos)
            cant_base = length(this.ElementosSerie);
            this.ElementosSerie = [this.ElementosSerie; elementos];
            this.EstadoElementosSerie = [this.EstadoElementosSerie; ones(length(elementos),1)];
            for i = 1:length(elementos)
                elementos(i).IdAdmProyectos = cant_base + i;
                elementos(i).Existente = true;
                this.RelElementosSerieSE(cant_base + i,1) = elementos(i).entrega_se1().entrega_id_adm_proyectos();
                this.RelElementosSerieSE(cant_base + i,2) = elementos(i).entrega_se2().entrega_id_adm_proyectos();
            end
        end

        function inserta_elementos_serie_expansion(this, elementos)
            cant_base = length(this.ElementosSerie);
            this.ElementosSerie = [this.ElementosSerie; elementos];
            this.EstadoElementosSerie = [this.EstadoElementosSerie; zeros(length(elementos),1)];
            for i = 1:length(elementos)
                elementos(i).IdAdmProyectos = cant_base + i;
                elementos(i).Existente = true;
                this.RelElementosSerieSE(cant_base + i,1) = elementos(i).entrega_se1().entrega_id_adm_proyectos();
                this.RelElementosSerieSE(cant_base + i,2) = elementos(i).entrega_se2().entrega_id_adm_proyectos();
            end
        end
        
        function determina_proyectos_por_elementos(this)
            % elementos serie
            for i = 1:length(this.ElementosSerie)
                this.ProyPorElementosSerieAgregar(i).Proyectos = cProyectoExpansion.empty;
                this.ProyPorElementosSerieRemover(i).Proyectos = cProyectoExpansion.empty;
            end

            for i = 1:length(this.ElementosParalelos)
                this.ProyPorElementosParalelosAgregar(i).Proyectos = cProyectoExpansion.empty;
                this.ProyPorElementosParalelosRemover(i).Proyectos = cProyectoExpansion.empty;
            end
            
            for i = 1:length(this.Proyectos)
                if strcmp(this.Proyectos(i).entrega_tipo_proyecto(),'AS')
                    continue;
                end
                                
                for j = 1:length(this.Proyectos(i).Elemento)
                    el_red = this.Proyectos(i).Elemento(j);
                    existente = this.Proyectos(i).Elemento(j).Existente;
                    id_admproy = el_red.IdAdmProyectos;
                    
                    if strcmp(this.Proyectos(i).entrega_tipo_proyecto(),'AB')
                        %agrega batería. Elemento paralelo
                        if strcmp(this.Proyectos(i).Accion(j),'A')
                            if ~existente
                                this.ProyPorElementosParalelosAgregar(id_admproy).Proyectos = [this.ProyPorElementosParalelosAgregar(id_admproy).Proyectos this.Proyectos(i)];
                            else
                                texto = ['modo debug: elemento de red ' this.Proyectos(i).Elemento(j).entrega_nombre() ' existe en red por lo que no puede haber un proyecto que lo agregue. Proyecto que lo agrega: ' this.Proyectos(i).entrega_nombre()];
                                error = MException('cAdministradorProyectos:determina_proyectos_por_elementos',texto);
                                throw(error)
                            end
                        else
                            this.ProyPorElementosParalelosRemover(id_admproy).Proyectos = [this.ProyPorElementosParalelosRemover(id_admproy).Proyectos this.Proyectos(i)];
                        end
                    else
                        if strcmp(this.Proyectos(i).Accion(j),'A')
                            if ~existente
                                this.ProyPorElementosSerieAgregar(id_admproy).Proyectos = [this.ProyPorElementosSerieAgregar(id_admproy).Proyectos this.Proyectos(i)];
                            else
                                texto = ['modo debug: elemento de red ' this.Proyectos(i).Elemento(j).entrega_nombre() ' existe en red por lo que no puede haber un proyecto que lo agregue. Proyecto que lo agrega: ' this.Proyectos(i).entrega_nombre()];
                                error = MException('cAdministradorProyectos:determina_proyectos_por_elementos',texto);
                                throw(error)
                            end
                        else
                            this.ProyPorElementosSerieRemover(id_admproy).Proyectos = [this.ProyPorElementosSerieRemover(id_admproy).Proyectos this.Proyectos(i)];
                        end
                    end
                end
            end
        end
        
        function proy = entrega_proyectos_agregar_reforzamiento_serie(this, el_red)
            proy = this.ProyPorElementosSerieAgregar(el_red.IdAdmProyectos).Proyectos;
        end
        
        function proy = entrega_proyectos_remover_reforzamiento_serie(this, el_red)
            proy = this.ProyPorElementosSerieRemover(el_red.IdAdmProyectos).Proyectos;
        end

        function proy = entrega_proyectos_agregar_reforzamiento_paralelo(this, el_red)
            proy = this.ProyPorElementosParalelosAgregar(el_red.IdAdmProyectos).Proyectos;
        end
        
        function proy = entrega_proyectos_remover_reforzamiento_paralelo(this, el_red)
            proy = this.ProyPorElementosParalelosRemover(el_red.IdAdmProyectos).Proyectos;
        end
        
        function proy = entrega_proyectos_transformadores(this, se, ipar)
            % función entrega todos los proyectos que conectan a la se
            % ingresada como se en el lado de AT
            proy = cProyectoExpansion.empty;
            for i = 1:length(this.Proyectos)
                if strcmp(this.Proyectos(i).entrega_tipo_proyecto(),'AT')
                    if this.Proyectos(i).Elemento(1).entrega_se1() == se && ...
                            this.Proyectos(i).Elemento(1).entrega_indice_paralelo == ipar
                        proy = [proy; this.Proyectos(i)];
                    end
                end
            end
        end
        
        function inserta_matriz_estados_decision_secundaria(this, matriz)
            this.MatrizEstadosDecisionSecundaria = matriz;
        end
        
        function val = entrega_cantidad_decisiones_secundarias(this)
            val = length(this.MatrizEstadosDecisionSecundaria);
        end
        
        function inserta_capacidad_por_estado_decisiones_secundarias(this, matriz)
           this.CapacidadPorEstadoDecisionSecundaria = matriz; 
        end

        function inserta_matriz_estados_decision_primaria(this, matriz)
            this.MatrizEstadosDecisionPrimaria = matriz;
        end
        
        function val = entrega_cantidad_decisiones_primarias(this)
            val = length(this.MatrizEstadosDecisionPrimaria);
        end

        function inserta_capacidad_por_estado_decisiones_primarias(this, capacidades_corr_estados)
            this.CapacidadPorEstadoDecisionPrimaria = capacidades_corr_estados;
        end
        
        function inserta_estados_iniciales_decision_primaria(this, estados_iniciales)
            this.EstadosInicialesDecisionPrimaria = estados_iniciales;
        end
        
        function estado = entrega_estado_inicial_decision_primaria(this, id_decision)
            estado = this.EstadosInicialesDecisionPrimaria(id_decision,:);
        end
        
        function val = entrega_capacidad_inicial_decisiones_primarias(this)
            val = zeros(1, length(this.EstadosInicialesDecisionPrimaria));
            indices = find(this.EstadosInicialesDecisionPrimaria(:,1) > 0);
            for i = 1:length(indices)
                parindex = this.EstadosInicialesDecisionPrimaria(indices(i),1);
                estado = this.EstadosInicialesDecisionPrimaria(indices(i),2);
                capacidad = this.CapacidadPorEstadoDecisionPrimaria(indices(i)).Capacidad(parindex, estado);
                val(indices(i)) = capacidad;
            end
        end

        function capacidad = entrega_capacidad_inicial_decision_primaria(this, id_decision)
            estado_inicial = this.EstadosInicialesDecisionPrimaria(id_decision,:);
            if estado_inicial(1) > 0
                capacidad = this.CapacidadPorEstadoDecisionPrimaria(id_decision).Capacidad(estado_inicial(1), estado_inicial(2));
            else
                capacidad = 0;
            end
        end
                    
        function val = entrega_capacidad_estado_primario(this, id_decision, estado)
            val = this.CapacidadPorEstadoDecisionPrimaria(id_decision).Capacidad(estado(1), estado(2));
        end
            
        function inserta_relacion_corredores_se(this, rel_corr_subestaciones)
            this.RelCorredoresSE = rel_corr_subestaciones;
        end
        
        function imprime_matriz_estados(this)
            prot = cProtocolo.getInstance;
            prot.imprime_texto('Matriz de estados:\n');
            prot.imprime_texto('Corredores:');
            for i = 1:length(this.MatrizEstadosDecisionPrimaria)
                texto = ['Decision expansion ' num2str(i)];
                prot.imprime_texto(texto);
                texto = sprintf('%-20s %-20s %-30s %-30s', 'Lpar', 'Estado', 'Proyectos entrantes', 'Proyectos salientes');
                prot.imprime_texto(texto);
                [cant_lineas,cant_estados] = size(this.MatrizEstadosDecisionPrimaria(i).Estado);
                for j = 1:cant_lineas
                    for k = 1:cant_estados
                        texto_proyectos_entrantes = '';
                        texto_proyectos_salientes = '';
                        for proy = 1:length(this.MatrizEstadosDecisionPrimaria(i).Estado(j,k).ProyectosEntrantes)
                            id_proy = this.MatrizEstadosDecisionPrimaria(i).Estado(j,k).ProyectosEntrantes(proy).Indice;
                            texto_proyectos_entrantes = [texto_proyectos_entrantes ' ' num2str(id_proy)];
                        end
                        for proy = 1:length(this.MatrizEstadosDecisionPrimaria(i).Estado(j,k).ProyectosSalientes)
                            id_proy = this.MatrizEstadosDecisionPrimaria(i).Estado(j,k).ProyectosSalientes(proy).Indice;
                            texto_proyectos_salientes = [texto_proyectos_salientes ' ' num2str(id_proy)];
                        end
                        if ~isempty(this.MatrizEstadosDecisionPrimaria(i).Estado(j,k).Nombre)
                            texto_lpar = this.MatrizEstadosDecisionPrimaria(i).Estado(j,k).Nombre{1,1};
                            texto_estado = this.MatrizEstadosDecisionPrimaria(i).Estado(j,k).Nombre{1,2};
                            texto = sprintf('%-20s %-20s %-30s %-30s', ...
                                texto_lpar, texto_estado, texto_proyectos_entrantes, texto_proyectos_salientes);
                            prot.imprime_texto(texto);
                        end
                    end
                end
            end
            prot.imprime_texto('Trafos:');
            for i = 1:length(this.MatrizEstadosDecisionSecundaria)
                if ~this.MatrizEstadosDecisionSecundaria(i).Existe
                    continue;
                end
                texto = ['Ubicacion ' num2str(i)];
                prot.imprime_texto(texto);
                texto = sprintf('%-20s %-20s %-30s %-30s', 'Lpar', 'Estado', 'Proyectos entrantes', 'Proyectos salientes');
                prot.imprime_texto(texto);
                [cant_trafos,cant_estados] = size(this.MatrizEstadosDecisionSecundaria(i).Estado);
                for j = 1:cant_trafos
                    for k = 1:cant_estados
                        texto_proyectos_entrantes = '';
                        texto_proyectos_salientes = '';
                        for proy = 1:length(this.MatrizEstadosDecisionSecundaria(i).Estado(j,k).ProyectosEntrantes)
                            id_proy = this.MatrizEstadosDecisionSecundaria(i).Estado(j,k).ProyectosEntrantes(proy).Indice;
                            texto_proyectos_entrantes = [texto_proyectos_entrantes ' ' num2str(id_proy)];
                        end
                        for proy = 1:length(this.MatrizEstadosDecisionSecundaria(i).Estado(j,k).ProyectosSalientes)
                            id_proy = this.MatrizEstadosDecisionSecundaria(i).Estado(j,k).ProyectosSalientes(proy).Indice;
                            texto_proyectos_salientes = [texto_proyectos_salientes ' ' num2str(id_proy)];
                        end
                        texto_lpar = this.MatrizEstadosDecisionSecundaria(i).Estado(j,k).Nombre{1,1};
                        texto_estado = this.MatrizEstadosDecisionSecundaria(i).Estado(j,k).Nombre{1,2};
                        texto = sprintf('%-20s %-20s %-30s %-30s', ...
                            texto_lpar, texto_estado, texto_proyectos_entrantes, texto_proyectos_salientes);
                        prot.imprime_texto(texto);
                    end
                end
            end
        end
        
        function proy = entrega_proyectos_salientes(this, el_red)
            par_index = el_red.entrega_indice_paralelo();
            id_estado = el_red.entrega_id_estado_planificacion();
            if isa(el_red, 'cLinea')
                id_corredor = el_red.entrega_indice_decision_expansion();
                proy = this.MatrizEstadosDecisionPrimaria(id_corredor).Estado(par_index, id_estado).ProyectosSalientes;
            elseif isa(el_red, 'cTransformador2D')
                id_corredor = el_red.entrega_indice_decision_expansion();
                if id_corredor ~= 0
                    % se trata de transformador normal (no VU)
                    proy = this.MatrizEstadosDecisionPrimaria(id_corredor).Estado(par_index, id_estado).ProyectosSalientes;
                else
                    % se trata de transformador VU
                    ubicacion = el_red.entrega_ubicacion();
                    if this.MatrizEstadosDecisionSecundaria(ubicacion).Existe
                        proy = this.MatrizEstadosDecisionSecundaria(ubicacion).Estado(par_index,id_estado).ProyectosSalientes;
                    else
                        proy = cProyectoExpansion.empty;
                    end
                end
            else
                error = MException('cAdministradorProyectos:entrega_proyectos_salientes','tipo elemento red no implementado');
                throw(error)
            end
        end
        
        function proy = entrega_id_proyectos_primarios_por_indice_decision(this, id_decision)
            [cant_parindex, cant_estados] = size(this.MatrizEstadosDecisionPrimaria(id_decision).Estado);
            proy = [];
            for ipar = 1:cant_parindex
                for iest = 1:cant_estados
                    proy = [proy this.MatrizEstadosDecisionPrimaria(id_decision).Estado(ipar, iest).IdProyectosEntrantes];
                end
            end
        end
        
        function proy = entrega_id_proyectos_salientes_por_indice_decision_y_estado(this, id_decision, par_index, id_estado)
            if par_index > 0
                proy = this.MatrizEstadosDecisionPrimaria(id_decision).Estado(par_index, id_estado).IdProyectosSalientes;
            else
                proy = this.MatrizEstadosDecisionPrimaria(id_decision).Estado(par_index+1, id_estado).IdProyectosEntrantes;
            end
        end
        
        function proy = entrega_id_proyectos_entrantes_por_indice_decision_y_estado(this, id_decision, par_index, id_estado)
            if par_index > 0          
                proy = this.MatrizEstadosDecisionPrimaria(id_decision).Estado(par_index, id_estado).IdProyectosEntrantes;
            else
                proy = this.MatrizEstadosDecisionPrimaria(id_decision).Estado(par_index+1, id_estado).IdProyectosEntrantes;
            end
        end
        
        function [parindex, id_estado] = entrega_estado_por_capacidad(this, id_decision,capacidad)
            if capacidad == 0
                parindex = 0;
                id_estado = 1;
                return
            else
                [parindex, id_estado] = find(this.CapacidadPorEstadoDecisionPrimaria(id_decision).Capacidad == capacidad);
            end
        end
        
        function proy = entrega_id_proyectos_salientes(this, el_red)
            par_index = el_red.entrega_indice_paralelo();
            id_estado = el_red.entrega_id_estado_planificacion();
            if isa(el_red, 'cLinea')
                id_corredor = el_red.entrega_indice_decision_expansion();
                proy = this.MatrizEstadosDecisionPrimaria(id_corredor).Estado(par_index, id_estado).IdProyectosSalientes;
            elseif isa(el_red, 'cTransformador2D')
                id_corredor = el_red.entrega_indice_decision_expansion();
                if id_corredor ~= 0
                    proy = this.MatrizEstadosDecisionPrimaria(id_corredor).Estado(par_index, id_estado).IdProyectosSalientes;
                else
                    ubicacion = el_red.entrega_ubicacion();
                    if this.MatrizEstadosDecisionSecundaria(ubicacion).Existe
                        proy = this.MatrizEstadosDecisionSecundaria(ubicacion).Estado(par_index,id_estado).IdProyectosSalientes;
                    else
                        proy = [];
                    end
                end
            elseif isa(el_red, 'cBateria')
                id_bus = el_red.entrega_indice_decision_expansion();
                proy = this.MatrizEstadosDecisionPrimaria(id_bus).Estado(par_index, id_estado).IdProyectosSalientes;
            else
                error = MException('cAdministradorProyectos:entrega_proyectos_salientes','tipo elemento red no implementado');
                throw(error)
            end
        end
        
        function id_proy_corredor = entrega_id_proyectos_corredor(this, el_red)
            id_proy_corredor = [];
            id_corredor = el_red.entrega_indice_decision_expansion();
            if id_corredor ~= 0
                [cant_lineas,cant_estados] = size(this.MatrizEstadosDecisionPrimaria(id_corredor).Estado);
                for j = 1:cant_lineas
                    for k = 1:cant_estados
                        id_proy_corredor = [id_proy_corredor this.MatrizEstadosDecisionPrimaria(id_corredor).Estado(j,k).IdProyectosEntrantes];
                    end
                end
            else
                % proyecto VU
                ubicacion = el_red.entrega_ubicacion();
                if this.MatrizEstadosDecisionSecundaria(ubicacion).Existe
                    [cant_trafos,cant_estados] = size(this.MatrizEstadosDecisionSecundaria(id_corredor).Estado);
                    for j = 1:cant_trafos
                        for k = 1:cant_estados
                            for proy = 1: length(this.MatrizEstadosDecisionSecundaria(ubicacion).Estado(j,k).ProyectosEntrantes)
                                id_proy_corredor = [id_proy_corredor this.MatrizEstadosDecisionSecundaria(ubicacion).Estado(j,k).ProyectosEntrantes(proy).Indice];
                            end
                        end
                    end
                end
            end
        end
        
        function proy = entrega_id_proyectos_entrantes(this, el_red)
            par_index = el_red.entrega_indice_paralelo();
            id_estado = el_red.entrega_id_estado_planificacion();
            if isa(el_red, 'cLinea')
                id_corredor = el_red.entrega_indice_decision_expansion();
                proy = this.MatrizEstadosDecisionPrimaria(id_corredor).Estado(par_index, id_estado).IdProyectosEntrantes;
            elseif isa(el_red, 'cTransformador2D')
                id_corredor = el_red.entrega_indice_decision_expansion();
                if id_corredor ~= 0
                    proy = this.MatrizEstadosDecisionPrimaria(id_corredor).Estado(par_index, id_estado).IdProyectosEntrantes;
                else
                    ubicacion = el_red.entrega_ubicacion();
                    if this.MatrizEstadosDecisionSecundaria(ubicacion).Existe
                        proy = this.MatrizEstadosDecisionSecundaria(ubicacion).Estado(par_index,id_estado).IdProyectosEntrantes;
                    else
                        proy = [];
                    end
                end
            elseif isa(el_red, 'cBateria')
                id_corredor = el_red.entrega_indice_decision_expansion();
                proy = this.MatrizEstadosDecisionPrimaria(id_corredor).Estado(par_index, id_estado).IdProyectosEntrantes;
            else
                error = MException('cAdministradorProyectos:entrega_proyectos_entrantes','tipo elemento red no implementado');
                throw(error)
            end
        end
        
        function [proyectos_a_eliminar, proyectos_a_agregar] = entrega_plan_implementacion_proyectos(this, proyectos_actuales_sep, proyectos_acumulados_estado)
           % primero elimina proyectos sobrantes y luego agrega los restantes
           % TODO RAMRAM: por ahora sin line uprating

           diferencia_proyectos = proyectos_actuales_sep - proyectos_acumulados_estado;
           proyectos_a_agregar = find(diferencia_proyectos < 0);
           proyectos_a_eliminar = find(diferencia_proyectos > 0);
        end
        
        function inserta_proyecto_nuevo_corredor(this, proy, varargin)
            [cant, ~] = size(this.ProyectosNuevosCorredores);
            if nargin > 2
                id_se1 = varargin{1};
                id_se2 = varargin{2};
            else
                id_se1 = proy.Elemento(end).entrega_se1().entrega_id();
                id_se2 = proy.Elemento(end).entrega_se2().entrega_id();
            end
            
            this.ProyectosNuevosCorredores(cant+1,1) = id_se1;
            this.ProyectosNuevosCorredores(cant+1,2) = proy.entrega_indice();
            this.ProyectosNuevosCorredores(cant+2,1) = id_se2;
            this.ProyectosNuevosCorredores(cant+2,2) = proy.entrega_indice();
        end
        
        function proy = entrega_id_proyecto_nuevo_corredor(this, id_se)
            id = this.ProyectosNuevosCorredores(:,1) == id_se;
            proy = this.ProyectosNuevosCorredores(id,2);
        end

        function proy = entrega_id_proyectos_nuevos_corredores(this)
            proy = unique(this.ProyectosNuevosCorredores(:,2));
        end
    end
end