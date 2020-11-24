classdef cProyectoExpansion < handle
    % Clase que representa un proyecto de expansión
    
    properties
        Nombre = ''

        Tipo = ''
        % Tipo proyecto:
        % 'AL' agrega nueva línea 
        % 'AT' agrega nuevo transformador
        % 'AS' agrega nueva subestación
        % 'CC' cambio de conductores
        % 'AV' voltage uprating
        % 'CS' compensación en serie
        % 'AB' agrega baterías
        % 'AG' agrega generador 
        % 'AC' agrega consumo
        % 'ACSP' agrega generador CSP
        % 'ARS' agrega reactor shunt
        % 'ACS' agrega condensador shunt
        IdTipo = 0 % 1: Tx, 2: Gx, 3: Compensación reactiva
        TipoDecision = 1 % 1: discreta; 2: continua
        CantDecisiones = 1 % para baterías continuas y plantas CSP es 2
        
        % Para variables de decisión continua (eventualmente baterías, generadores renovables y plantas CSP
        % Se indica Pmax de la variables de decisión y Emax (cuando
        % corresponde). Además se indica límites para Pmax/Emax
        Pmax = 1; % valor máximo para la expansión
        Emax = 1;
        EmaxPmaxMin = 0;
        EmaxPmaxMax = 0;
        
        % Elementos de red y acción del proyecto        
        Elemento = cElementoRed.empty;
        Accion = cell.empty;
        Indice = 0 % indica la posición del proyecto dentro del administrador de proyecto en el contenedor correspondiente (transmisión, generación o consumos)

        % parámetros específicos de MCMC/ACO
        IndiceDecisionExpansion = 0 % indica corredor/bus donde proyecto aumenta la capacidad (Se utiliza en MCMC)
        EstadoConducente = [] % [lpar, id_estado_final]
        EstadoInicial = [] % [lpar, id_estado_inicial]
        
        CapacidadAdicional = 0 %capacidad adicional que agrega el proyecto
        
        % Costo inversión contiene los costos asociados al proyecto, sin
        % contabilizar el valor residual de los elementos a remover (cuando
        % corresponda)
        CostoInversion = 0

        % Índice que contiene la variable de optimización para la expansión
        IndiceVarOptExpansionDecision = 0
        IndiceVarOptExpansionDecision2 = 0
        IndiceVarOptExpansionCosto = 0
        IndiceVarOptExpansionDecisionAcumulada = 0

        IndiceVarOptExpansionDecisionComun = 0;
        IndiceVarOptExpansionCostoComun = 0;
        IndiceVarOptExpansionDecisionAcumuladaComun = 0;
        IndiceVarOptExpansionDecision2Comun = 0;
        
        % PARAMETROS EXCLUSIVOS PARA EXPANSION DE LA TRANSMISION
        
        EsUprating   % true or false
        
        % Capacidad inicial y final entregan el tipo de uprate
        % para AL, CC: tipo de conductor inicial/final (Cxxx)
        % para AV: voltaje inicial/final (Vxxx)
        % para CS: tipo compensacion en serie (Sxxx) (nada en inicial)
        CapacidadInicial = ''
        CapacidadFinal = ''

        CambioConductorVU = false;
                
        % Costo potencial se utiliza para TNEP ACO
        CostoPotencial = 0;
        
        ProbabilidadRetraso = []  % [0.5 0.3 0.2] 0.5 sin retraso; 0.3 pbb 1 año retraso; 0.2 pnn 2 años retraso
        
        % ProyectoDependiente guarda el o los proyectos dependientes
        TieneDependencia = false;
        ProyectoDependiente = cProyectoExpansion.empty;
        
        % Indice proyecto dependiente contiene sólo los índices. Se utilza
        % para métodos heurísticos
        IndiceProyectoDependiente;
        
        % Grupo de proyectos para asegurar la conectividad. Se utiliza para
        % voltage uprating.
        % al igual que proyectos dependientes, por cada grupo se debe
        % cumplir que al menos un proyecto esté ya implementado
        TieneRequisitosConectividad = false;
        ProyectosConectividad = []
        
        ElementoARemover = []
        
        % Formato ElementoEnProyectoDependiente:
        % ElementoEnProyectoDependiente(id en ElementoARemover).Proyectos =
        % [proy1, proy2, ...];
        ElementoEnProyectoDependiente
        
        CantidadEtapasEntradaOperacion 
    end
    
    methods
        function inicializa_varopt_expansion_milp_dc(this, cant_escenarios, cant_etapas, valor_residual)
            this.IndiceVarOptExpansionDecision = zeros(cant_escenarios, cant_etapas);
            this.IndiceVarOptExpansionDecisionAcumulada = zeros(cant_escenarios, cant_etapas);
            if valor_residual
                this.IndiceVarOptExpansionCosto = zeros(cant_escenarios, cant_etapas);
            end
        end
        
        function inserta_varopt_expansion(this, tipo, escenario, valor)
            switch tipo
                case 'Decision'
                    this.IndiceVarOptExpansionDecision(escenario,:) = valor;
                case 'Costo'
                    this.IndiceVarOptExpansionCosto(escenario,:) = valor;
                case 'Acumulada'
                    this.IndiceVarOptExpansionDecisionAcumulada(escenario,:) = valor;
                case 'Decision2'
                    this.IndiceVarOptExpansionDecision2(escenario,:) = valor;
                otherwise
                    error = MException('cProyectoExpansion:inserta_varopt_expansion','Caso no implementado');
                    throw(error)
            end
        end
                
        function val = entrega_varopt_expansion(this, tipo, escenario)
            switch tipo 
                case 'Decision'
                    val = this.IndiceVarOptExpansionDecision(escenario,:);
                case 'Costo'
                    val = this.IndiceVarOptExpansionCosto(escenario,:);
                case 'Acumulada'
                    val = this.IndiceVarOptExpansionDecisionAcumulada(escenario,:);
                case 'Decision2'
                    val = this.IndiceVarOptExpansionDecision2(escenario,:);
                otherwise
                    error = MException('cProyectoExpansion:entrega_varopt_expansion','Caso no implementado');
                    throw(error)
            end
        end
        
        function inserta_cantidad_decisiones(this, val)
            this.CantDecisiones = val;
        end
        
        function val = entrega_cantidad_decisiones(this)
            val = this.CantDecisiones;
        end
        
        function inserta_tipo_proyecto(this, tipo)
            this.Tipo = tipo;
            if strcmp(tipo, 'AG')
                this.IdTipo = 2;
            elseif strcmp(tipo, 'ACS') || strcmp(tipo, 'ARS')
                this.IdTipo = 3;
            else
                this.IdTipo = 1;
            end
        end
        
        function inserta_tipo_decision(this, tipo)
            this.TipoDecision = tipo;
        end
        
        function val = entrega_tipo_decision(this)
            val = this.TipoDecision;
        end
        
        function tipo = entrega_tipo_proyecto(this)
            tipo = this.Tipo;
        end
        
        function id_tipo = entrega_id_tipo_proyecto(this)
            id_tipo = this.IdTipo;
        end
        
        function inserta_capacidad_inicial(this, tipo)
            this.CapacidadInicial= tipo;
        end
        
        function tipo = entrega_capacidad_inicial(this)
            tipo = this.CapacidadInicial;
        end

        function inserta_capacidad_final(this, tipo)
            this.CapacidadFinal= tipo;
        end
        
        function tipo = entrega_capacidad_final(this)
            tipo = this.CapacidadFinal;
        end
        
        function inserta_proyectos_dependientes(this, proyectos)
            this.ProyectoDependiente = proyectos;
            this.IndiceProyectoDependiente = zeros(length(proyectos),1);
            for i = 1:length(proyectos)
                this.IndiceProyectoDependiente(i,1) = proyectos.entrega_indice();
            end
        end
        
        function inserta_grupo_proyectos_conectividad(this, proyectos)
            this.TieneRequisitosConectividad = true;
            n_grupos = length(this.ProyectosConectividad);
            this.ProyectosConectividad(n_grupos+1).Proyectos = proyectos;
        end
        
        function val = es_proyecto_conectividad(this, proy)
            val = ismember(proy, this.ProyectosConectividad);
        end
        
        function val = tiene_requisitos_conectividad(this)
            val = this.TieneRequisitosConectividad;
        end
        
        function val = entrega_cantidad_grupos_conectividad(this)
            val = length(this.ProyectosConectividad);
        end
        
        function proy = entrega_grupo_proyectos_conectividad(this, nro)
            proy = this.ProyectosConectividad(nro).Proyectos;
        end
 
        function indices = entrega_indices_grupo_proyectos_conectividad(this, nro)
            indices = zeros(length(this.ProyectosConectividad(nro).Proyectos),1);
            for i = 1:length(this.ProyectosConectividad(nro).Proyectos)
                indices(i) = this.ProyectosConectividad(nro).Proyectos(i).Indice;
            end
        end
        
        function indice = entrega_indice(this)
            indice = this.Indice;
        end
        
        function [existe, accion] = existe_elemento(this, elemento)
            for i = 1:length(this.Elemento)
                if this.Elemento(i) == elemento
                    existe = true;
                    accion = this.Accion{i};
                    return
                end
            end
            existe = false;
            accion = '';
        end
        
        function val = entrega_costos_inversion(this)
            val = this.CostoInversion;
        end
        
        function inserta_costo_inversion(this, val)
            this.CostoInversion = val;
        end
        
        function agrega_dependencias_elementos_a_remover(this, elementos, dependencias)
            this.ElementoARemover = elementos;
            this.ElementoEnProyectoDependiente = dependencias;
        end
        
        function proy = entrega_dependencias_elemento_a_remover(this, elemento)
            for i = 1:length(this.ElementoARemover)
                if this.ElementoARemover(i) == elemento
                    proy = this.ElementoEnProyectoDependiente(i).Proyectos;
                    return
                end
            end
            proy = cProyectoExpansion.empty;
        end
        
        function calcula_costo_potencial(this)
            % sólo se consideran costos de agregar elementos de red
            if this.CostoPotencial > 0
                error = MException('cProyectoExpansion:calcula_costo_potencial','Error de programación. Costo potencial ya fue calculado');
                throw(error)
            end
                
            for i = 1:length(this.Elemento)
                if strcmp(this.Accion{i},'A')
                    this.CostoPotencial = this.CostoPotencial + this.Elemento(i).entrega_costo_inversion();
                end
            end            
        end
        
        function val = entrega_costo_potencial(this)
            val = this.CostoPotencial;
        end
                
        function indices = entrega_indices_proyectos_dependientes(this)
            indices = this.IndiceProyectoDependiente;
        end
                
        function inserta_nombre(this, nombre)
            this.Nombre = nombre;
        end
        
        function nombre = entrega_nombre(this)
            nombre = this.Nombre;
        end
        
        function val = tiene_dependencia(this)
            val = this.TieneDependencia;
        end
        
        function inserta_cambio_conductor_aumento_voltaje(this, val)
            this.CambioConductorVU = val;
        end
        
        function val = cambio_conductor_aumento_voltaje(this)
            val = this.CambioConductorVU;
        end
        
        function pbb = entrega_probabilidad_retraso(this)
            pbb = this.ProbabilidadRetraso;
        end
        
        function inserta_etapas_entrada_en_operacion(this, val)
            this.CantidadEtapasEntradaOperacion = val;
        end
        
        function val = entrega_etapas_entrada_en_operacion(this)
            val = this.CantidadEtapasEntradaOperacion;
        end
        
        function inserta_indice_decision_expansion(this, val)
            this.IndiceDecisionExpansion = val;
        end

        function val = entrega_indice_decision_expansion(this)
            val = this.IndiceDecisionExpansion;
        end
        
        function val = entrega_capacidad_adicional(this)
            try
                val = this.CapacidadAdicional;
            catch
                warning('Aquí aparece el error');
                val = 0;
            end
        end
        
        function inserta_capacidad_adicional(this, val)
            this.CapacidadAdicional = val;
        end
        
        function inserta_estado_conducente(this, ipar, iestado)
            this.EstadoConducente = [ipar, iestado];
        end
        
        function inserta_estado_inicial(this, ipar, iestado)
            this.EstadoInicial = [ipar, iestado];
        end
        
        function val = entrega_estado_conducente(this)
            val = this.EstadoConducente;
        end
        
        function val = entrega_estado_inicial(this)
            val = this.EstadoInicial;
        end

        function inserta_pmax(this, val)
            this.Pmax = val;
        end

        function val = entrega_pmax(this)
            val = this.Pmax;
        end
        
        function inserta_emax(this, val)
            this.Emax = val;
        end

        function val = entrega_emax(this)
            val = this.Emax;
        end
        
        function inserta_limites_pmax_emax(this, liminf, limsup)
            this.EmaxPmaxMin = liminf;
            this.EmaxPmaxMax = limsup;
        end        
    end
end