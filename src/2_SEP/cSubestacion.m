classdef cSubestacion < cElementoRed
        % clase que representa las lineas de transmision
    properties
        % datos generales
        % Nombre Id y EnServicio se encuentran en clase cElementoRed
        Ubicacion = 0
        PosX = 0
		PosY = 0
        
        %Terminales = cTerminal.empty
        Generadores = cGenerador.empty
        IndiceGeneradoresDespachables = []
        Baterias = cBateria.empty
        
        Consumos = cConsumo.empty
        Lineas = cLinea.empty
        Transformadores2D = cTransformador2D.empty
        Condensadores = cElementoRed.empty % condensadores y reactores paralelos
        Reactores = cElementoRed.empty % condensadores y reactores paralelos
        
        SEAdyacentesLineas = cSubestacion.empty
        ParIndexLineas = []

        SEAdyacentesTrafos = cSubestacion.empty
        ParIndexTrafos = []
        
        %Transformadores3D = cTransformador3D.empty
        
        %parámetros técnicos
        Vn = 0 % en kV
        Vmax = 0 % en kV
        Vmin = 0 % en kV
        
        VidaUtil = 40 %años
        % parámetros económicos
        Costo = 0
        
        Slack = false
        IdGenSlack = []
        % Flag OPF indica si el voltaje de la SE es variable de
        % optimización. Si la SE tiene un generador con flag OPF, entonces
        % el voltaje de la SE automáticamente se considera para el OPF
        OPF

        % En caso de que la subestacion no sea existente
        EtapaEntrada = 0
        
        % A continuación índices para optimización expansión
        IndiceVarOptExpansion = 0
        IndiceVarOptV
        IndiceVarOptTheta
        IndiceEqBalanceEnergia = [] % indica dónde se encuentra el balance de energía. Para TNEP heurística utilizando DC-OPF
        
        % Resultado del flujo de potencia
        id_fp
        Vfp
        Angulofp % en grados

    end
    
    methods
        function this = cSubestacion()
            this.TipoElementoRed = 'Bus';
        end

        function inserta_vmax_pu(this, val)
            this.Vmax = val*this.Vn;
        end
        
        function inserta_vmax(this, val)
            this.Vmax = val;
        end

        function val = entrega_vmax(this)
            val = this.Vmax;
        end
        
        function val = entrega_vmax_pu(this)
            val = this.Vmax/this.Vn;
        end
        
        function inserta_vmin_pu(this, val)
            this.Vmin = val*this.Vn;
        end
        
        function inserta_vmin(this, val)
            this.Vmin = val;
        end

        function val = entrega_vmin(this)
            val = this.Vmin;
        end
        
        function val = entrega_vmin_pu(this)
            val = this.Vmin/this.Vn;
        end
        
        function agrega_linea(obj, linea)
            obj.Lineas = [obj.Lineas; linea];
            if linea.entrega_se1() == obj
                obj.SEAdyacentesLineas(1,length(obj.Lineas)) = linea.entrega_se2();
            else
                obj.SEAdyacentesLineas(1,length(obj.Lineas)) = linea.entrega_se1();
            end
            obj.ParIndexLineas(1,length(obj.Lineas)) = linea.entrega_indice_paralelo();
        end
        
        function agrega_generador(obj, generador)
            obj.Generadores = [obj.Generadores; generador];
            obj.IndiceGeneradoresDespachables(length(obj.Generadores),1) = generador.Despachable;
            if generador.es_slack()
               obj.Slack = true;
               obj.IdGenSlack = length(obj.Generadores);
            end
        end

        function gen = entrega_generador_slack(this)
            if this.Slack
                gen = this.Generadores(this.IdGenSlack);
            else
                error = MException('cSubestacion:entrega_generador_slack','Subestacion no es slack');
                throw(error)
            end
        end
        
        function agrega_bateria(obj, bateria)
            obj.Baterias = [obj.Baterias; bateria];            
        end
        
        function agrega_compensacion_reactiva(this, el_red)
            if isa(el_red, 'cCondensador')
                this.Condensadores = [this.Condensadores; el_red];
            else
                this.Reactores = [this.Reactores; el_red];
            end
        end
        
        function agrega_consumo(obj, consumo)
            obj.Consumos = [obj.Consumos; consumo];
        end

        function agrega_transformador2D(obj, trafo)
            obj.Transformadores2D = [obj.Transformadores2D; trafo];
            if trafo.entrega_se1() == obj
                obj.SEAdyacentesTrafos(1,length(obj.Transformadores2D)) = trafo.entrega_se2();
            else
                obj.SEAdyacentesTrafos(1,length(obj.Transformadores2D)) = trafo.entrega_se1();
            end
            obj.ParIndexTrafos(1,length(obj.Transformadores2D)) = trafo.entrega_indice_paralelo();
        end

        function agrega_elemento_red(this, el_red)
            if isa(el_red, 'cLinea')
                this.agrega_linea(el_red);
            elseif isa(el_red, 'cGenerador')
                this.agrega_generador(el_red);
            elseif isa(el_red, 'cConsumo')
                this.agrega_consumo(el_red)
            elseif isa(el_red, 'cTransformador2D')
                this.agrega_transformador2D(el_red);
            elseif isa(el_red, 'cBateria')
                this.agrega_bateria(el_red);
            elseif isa(el_red, 'cCondensador') || isa(el_red, 'cReactor')
                this.agrega_compensacion_reactiva(el_red);
            else
                error = MException('cSubestacion:agrega_elemento_red','elemento no implementado');
                throw(error)
            end
        end

%        function agrega_transformador3D(obj, trafo)
%            obj.Transformadores3D = [obj.Transformadores3D trafo];
%        end
        
        function conectividad = existe_conectividad(obj)
            conectividad = true;
            if isempty(obj.Lineas) && isempty(obj.Transformadores2D) %&& isempty(obj.Transformadores3D)
                conectividad = false;
            end
        end
        
        function conectividad = existe_conectividad_operacional(this)
            if ~this.existe_conectividad()
                conectividad = false;
                return
            end
            
            for i = 1:length(this.Lineas)
                if this.Lineas(i).en_servicio()
                    conectividad = true;
                    return
                end
            end

            for i = 1:length(this.Transformadores2D)
                if this.Transformadores2D(i).en_servicio()
                    conectividad = true;
                    return
                end
            end

            %for i = 1:length(this.Transformadores3D)
            %    if this.Transformadores3D(i).en_servicio()
            %        conectividad = true;
            %        return
            %    end
            %end
            
            conectividad = false;
        end
                
        function subestacion = crea_copia(obj)
            % crea una copia de la subestación pero sólo elementos que se
            % pueden copiar o que vale la pena copiar. No se copia ningún puntero
            subestacion = cSubestacion();
            subestacion.Nombre = obj.Nombre;
            subestacion.Id = obj.Id;
            subestacion.IdElementoRed = obj.IdElementoRed;
            subestacion.EnServicio = obj.EnServicio;
            subestacion.PosX = obj.PosX;
            subestacion.PosY = obj.PosY;
            subestacion.Vn = obj.Vn;
            subestacion.Vmax = obj.Vmax;
            subestacion.Vmin = obj.Vmin;
            subestacion.Costo = obj.Costo;
            subestacion.Ubicacion = obj.Ubicacion;
            subestacion.VidaUtil = obj.VidaUtil;
            subestacion.FlagObservacion = obj.FlagObservacion;
            subestacion.EtapaEntrada = obj.EtapaEntrada;
            subestacion.IdAdmProyectos = obj.IdAdmProyectos;
        end
        
        function volt = entrega_vn(this)
            volt = this.Vn;
        end

        function vbase = entrega_vbase(this)
            vbase = this.Vn;
        end
        
        function inserta_nombre(this, nombre)
            this.Nombre = nombre;
        end
        
        function nombre = entrega_nombre(this)
            nombre = this.Nombre;
        end
        
        function inserta_posicion(this, posX, posY)
            this.PosX = posX;
            this.PosY = posY;
        end
        
        function [posx, posy] = entrega_posicion(this)
            posx = this.PosX;
            posy = this.PosY;
        end
        
        function lineas = entrega_lineas(this)
            lineas = this.Lineas;
        end
        
        function trafos = entrega_transformadores2d(this)
            trafos = this.Transformadores2D;
        end

        function gen = entrega_generadores(this)
            gen = this.Generadores;
        end

        function gen = entrega_generadores_despachables(this)
            gen = this.Generadores(this.IndiceGeneradoresDespachables == 1);            
        end

        function gen = entrega_generadores_res(this)
            gen = this.Generadores(this.IndiceGeneradoresDespachables == 0);
        end
        
        function con = entrega_consumos(this)
            con = this.Consumos;
        end
        
        function inserta_vn(this, vn)
            this.Vn = vn;
        end
        
        function bat = entrega_baterias(this)
            bat = this.Baterias;
        end
        
        function elem = entrega_elemtos_compensacion_reactivos(this)
            elem = [this.Condensadores; this.Reactores];
        end
        
        function inserta_resultados_fp_en_pu(this, id_fp, voltaje, angulo)
            this.id_fp = id_fp;
            this.Vfp = voltaje*this.Vn;
            this.Angulofp = angulo/pi*180;
        end
        
        function inserta_resultados_fp(this, id_fp, voltaje, angulo)
            % en este caso los datos ya están en valores reales
            this.id_fp = id_fp;
            this.Vfp = voltaje;
            this.Angulofp = angulo;
        end
        
        function val = entrega_voltaje_fp(this)
            val = this.Vfp;
        end
        
        function val = entrega_angulo_fp(this)
            val = this.Angulofp;
        end
        
        function inserta_es_slack(this, val)
            this.Slack = val;
        end
        
        function val = es_slack(this)
            val = this.Slack;
        end
        
        function inserta_flag_opf(this, varargin)
            % varargin contiene 1 o 0 dependiendo si participa o no en OPF.
            % Si no se entrega, nada, valor por defecto es 1 (participa)
            if nargin > 1
                val = varargin{1};
            else
                val = 1;
            end
            this.OPF = val;
        end
        
        function val = entrega_flag_opf(this)
            if this.OPF
                val = 1;
                return;
            else
                % se verifica si hay generadores con flag OPF
                for i = 1:length(this.Generadores)
                    if this.Generadores(i).entrega_flag_opf()
                        val = 1;
                        return;
                    end
                end
            end
            % la subestación no tiene el flag y tampoco hay generadores con
            % el flag
            val = 0;
        end
        function borra_resultados_fp(this)
            this.id_fp = 0;
            this.Vfp = 0;
            this.Angulofp = 0;
        end

        function inicializa_varopt_operacion_milp_dc(this, cant_escenarios, cant_etapas)
            this.IndiceVarOptTheta = zeros(cant_escenarios, cant_etapas);
        end
        
        function inserta_varopt_operacion(this, unidad, escenario, etapa, valor)
            switch unidad
                case 'Theta'
                    this.IndiceVarOptTheta(escenario, etapa) = valor;
                case 'V'
                    this.IndiceVarOptV(escenario, etapa) = valor;
                otherwise
                	error = MException('cSubestacion:inserta_varopt_operacion','unidad no implementada');
                    throw(error)
            end
        end
        
        function val = entrega_varopt_operacion(this, unidad, escenario, etapa)
            switch unidad
                case 'Theta'
                    val = this.IndiceVarOptTheta(escenario, etapa);
                case 'V'
                    val = this.IndiceVarOptV(escenario, etapa);
                otherwise
                	error = MException('cSubestacion:inserta_varopt_operacion','unidad no implementada');
                    throw(error)
            end
        end
        
        function elimina_elemento_red(this, el_red)
            if isa(el_red, 'cGenerador')
                id = find(this.Generadores == el_red);
                if ~isempty(id)
                    this.Generadores(id) = [];
                    this.IndiceGeneradoresDespachables(id) = [];
                end
            elseif isa(el_red, 'cConsumo')
                id = find(this.Consumos == el_red);
                if ~isempty(id)
                    this.Consumos(id) = [];
                    return
                end
            elseif isa(el_red, 'cLinea')
                id = find(this.Lineas == el_red);
                if ~isempty(id)
                    this.Lineas(id) = [];
                    this.SEAdyacentesLineas(id) = [];
                    this.ParIndexLineas(id) = [];
                    return
                end                        
            elseif isa(el_red, 'cTransformador2D')
                id = find(this.Transformadores2D == el_red);
                if ~isempty(id)
                    this.Transformadores2D(id) = [];
                    this.SEAdyacentesTrafos(id) = [];
                    this.ParIndexTrafos(id) = [];
                    return
                end
            elseif isa(el_red, 'cBateria')
                id = find(this.Baterias == el_red);
                if ~isempty(id)
                    this.Baterias(id) = [];
                    return
                end
            elseif isa(el_red, 'cCondensador')
                id = find(this.Condensadores == el_red);
                if ~isempty(id)
                    this.Condensadores(id) = [];
                    return
                end
            elseif isa(el_red, 'cReactor')
                id = find(this.Reactores == el_red);
                if ~isempty(id)
                    this.Reactores(id) = [];
                    return
                end
            else
                error = MException('cSubestacion:elimina_elemento_red','tipo de elemento aún no implementado');
                throw(error)
            end
            error = MException('cSubestacion:elimina_elemento_red','elemento de red a eliminar no se encuentra en el sistema');
            throw(error)
        end
        
        function inserta_ubicacion(this, val)
            this.Ubicacion = val;
        end
        
        function val = entrega_ubicacion(this)
            val = this.Ubicacion;
        end
        function inserta_costo(this, val)
            this.Costo = val;
        end
        
        function val = entrega_costo(this)
            val = this.Costo;
        end
        function val = entrega_costo_inversion(this)
            val = this.Costo;
        end 
        
        function inserta_vida_util(this, val)
            this.VidaUtil = val;
        end
        
        function val = entrega_vida_util(this)
            val = this.VidaUtil;
        end
        
        function se_adyacentes = entrega_subestaciones_adyacentes(this)
            se_adyacentes = unique(this.SEAdyacentesLineas);
            se_adyacentes = [se_adyacentes unique(this.SEAdyacentesTrafos)];            
        end
        
        function el_red_adyacentes = entrega_conexiones_con_se_excluyente(this, se_excluyente)
            el_red_adyacentes = this.Lineas(this.SEAdyacentesLineas ~= se_excluyente);
            el_red_adyacentes = [el_red_adyacentes this.Transformadores2D(this.SEAdyacentesTrafos ~= se_excluyente)];
        end

        function el_red_adyacentes = entrega_ultimas_conexiones_con_se_excluyente(this, se_excluyente)
            id = this.SEAdyacentesLineas ~= se_excluyente;
            se_candidatas = this.SEAdyacentesLineas(id);
            lineas_candidatas = this.Lineas(id);
            [~, id, ~] = unique(se_candidatas,'last');
            el_red_adyacentes = lineas_candidatas(id);

            id = this.SEAdyacentesTrafos ~= se_excluyente;
            se_candidatas = this.SEAdyacentesTrafos(id);
            trafos_candidatos = this.Transformadores2D(id);
            [~, id, ~] = unique(se_candidatas,'last');                
            el_red_adyacentes = [el_red_adyacentes trafos_candidatos(id)];                
        end
        
        function inserta_etapa_entrada(this, escenario, indice)
            this.EtapaEntrada(escenario) = indice;
        end
        
        function indice = entrega_etapa_entrada(this, escenario)
            if length(this.EtapaEntrada) >= escenario
                indice = this.EtapaEntrada(escenario);
            elseif length(this.EtapaEntrada) == 1 && this.EtapaEntrada == 0
                indice = 0;
            else
                error = MException('cSubestacion:entrega_etapa_entrada','Datos no son correctos. Corregir');
                throw(error)
            end
        end

        function agrega_restriccion_balance_energia_desde(this, escenario, etapa, indice)
            this.IndiceEqBalanceEnergia(escenario, etapa) = indice;
        end
        
        function indice = entrega_restriccion_balance_energia_desde(this, escenario, etapa)
            indice = this.IndiceEqBalanceEnergia(escenario, etapa);
        end

        function elem = entrega_elementos_paralelos(this)
            elem = [this.Generadores; this.Baterias; this.Consumos; this.Condensadores; this.Reactores];
        end
        
        function elem = entrega_elementos_serie(this, varargin)
            if nargin > 1
                solo_ultima_conexion = varargin{1};
            else
                solo_ultima_conexion = false; %todos
            end
            
            if solo_ultima_conexion 
                [~, id, ~] = unique(this.SEAdyacentesLineas,'last');
                elem = this.Lineas(id);

                [~, id, ~] = unique(this.SEAdyacentesTrafos,'last');
                elem = [elem this.Transformadores2D(id)];
            else
                elem = this.Lineas;
                elem = [elem ; this.Transformadores2D];
            end
        end

        function elem = entrega_ultimas_conexiones_elementos_serie(this)
            [~, id, ~] = unique(this.SEAdyacentesLineas,'last');
            elem = this.Lineas(id);

            [~, id, ~] = unique(this.SEAdyacentesTrafos,'last');
            elem = [elem this.Transformadores2D(id)];
        end
        
    end
end