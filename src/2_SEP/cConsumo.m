classdef cConsumo < cElementoRed
        % clase que representa las lineas de transmision
    properties
        % datos generales
        % datos en cElementoRed:
        %  Nombre
        %  EnServicio (valor por defecto = true)
        SE = cSubestacion.empty
        Pmax = 0
        Cosp = 1
        CostoDesconexionCarga = 0 %USD/MWh
        
        % Parámetros de operación para flujo de potencia
        % valores nominales
        P0 = 0
        Q0 = 0
        DepVoltaje = false;
        
		% En Servicio está en clase cElementoRed
        
        % Parámetros para Administrador de escenarios
        % Indice operación indice dónde se pueden encontrar los datos del
        % consumo
        % Parámetro "Existente" se encuentra en cElementoRed
        % El siguiente índice se utiliza para consumos existentes, e indica
        % su posición
        IndiceAdmEscenarioPerfilP = 0
        IndiceAdmEscenarioPerfilQ = 0
        IndiceAdmEscenarioCapacidad = 0
        
        % Los siguientes índices son adicionales para consumos proyectados. 
        % ojo que por cada escenario se debe definir un consumo!
        EtapaEntrada = 0 %indice correspondiente dentro del escenario
        EtapaSalida = 0
        
        %Indices para optimizacion y resultados
        IndiceVarOptP = 0
        IndiceResultados = 0
        
        % resultado flujo de potencia. Ojo que puede diferir de P0 y Q0
        id_fp = 0
        Pfp = 0
        Qfp = 0
        
    end
    
    methods
        function this = cConsumo()
            this.TipoElementoRed = 'ElementoParalelo';
        end

        function consumo = crea_copia(this)
            % crea una copia pero sólo elementos que se
            % pueden copiar o que vale la pena copiar. No se copia ningún puntero
            % TODO: es necesario crear la clase cParametros(..) como global
            % para no tener que crear una instancia cada vez
            
            consumo = cConsumo();
            consumo.Nombre = this.Nombre;
            consumo.Id = this.Id;
            consumo.EnServicio = this.EnServicio;
            consumo.IndiceAdmEscenarioPerfilP = this.IndiceAdmEscenarioPerfilP;
            consumo.IndiceAdmEscenarioPerfilQ = this.IndiceAdmEscenarioPerfilQ;
            consumo.IndiceAdmEscenarioCapacidad = this.IndiceAdmEscenarioCapacidad;
            consumo.Pmax = this.Pmax;
            consumo.Cosp = this.Cosp;
            consumo.FlagObservacion = this.FlagObservacion;
            consumo.CostoDesconexionCarga = this.CostoDesconexionCarga;
            consumo.Existente = this.Existente;
            consumo.EtapaEntrada = this.EtapaEntrada;
            consumo.EtapaSalida = this.EtapaSalida;
        end
        
        function inserta_nombre(this, nombre)
            this.Nombre = nombre;
        end
        
        function nombre = entrega_nombre(this)
            nombre = this.Nombre;
        end
        
        function inserta_subestacion(this, se)
            if ~isa(se, 'cSubestacion')
                error = MException('cConsumo:inserta_subestacion','Elemento entregado no es una subestación');
                throw(error)
            end
            
            this.SE = se;
        end
        
        function nombre = entrega_nombre_se(this)
            if isempty(this.SE) 
                error = MException('cConsumo:entrega_nombre_se','Consumo aún no tiene subestación asociada');
                throw(error)
            end
            nombre = this.SE.Nombre;
        end
        
        function indice = entrega_indice_adm_escenario_perfil_p(this)
            indice = this.IndiceAdmEscenarioPerfilP;
        end
        
        function indice = entrega_indice_adm_escenario_perfil_q(this)
            indice = this.IndiceAdmEscenarioPerfilQ;
        end
        
        function indice = entrega_indice_adm_escenario_capacidad(this, escenario)
            indice = this.IndiceAdmEscenarioCapacidad(escenario);
        end
        
        function inserta_indice_adm_escenario_perfil_p(this, indice)
            this.IndiceAdmEscenarioPerfilP = indice;
        end
        
        function inserta_indice_adm_escenario_perfil_q(this, indice)
            this.IndiceAdmEscenarioPerfilQ = indice;
        end
        
        function inserta_indice_adm_escenario_capacidad(this, escenario, indice)
            this.IndiceAdmEscenarioCapacidad(escenario) = indice;
        end
        
        function se = entrega_se(this)
            se = this.SE;
        end
        
        
        function inserta_p0(this, value)
            this.P0 = value;
        end
        
        function valor = entrega_p0(this, varargin)
            % varargin indica el punto de operación
            if nargin > 1
                oper = varargin{1};
                valor = this.P0(oper);
            else
                valor = this.P0;
            end
        end
        
        function inserta_q0(this, value)
            this.Q0 = value;
        end
        
        function y0 = entrega_dipolo(this)
            vnom = this.SE.entrega_vn();
            y0 = complex(this.P0/vnom^2,this.Q0/vnom^2);
        end
        
        function valor = entrega_q0(this)
            valor = this.Q0;
        end
        
        function valor = tiene_dependencia_voltaje(this)
            valor = this.DepVoltaje;
        end
        
        function inserta_tiene_dependencia_voltaje(this, valor)
            this.DepVoltaje = valor;
        end
        
        function valor = entrega_p_const_nom(this)
            if ~this.DepVoltaje
                valor = -this.P0;
            else
                valor = 0;
            end
        end
        
        function valor = entrega_q_const_nom(this)
            if ~this.DepVoltaje
                valor = -this.Q0;
            else
                valor = 0;
            end
        end

        function valor = entrega_p_const_nom_pu(this, varargin)
            % varargin indica el punto de operación 
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            if nargin > 1
                oper = varargin{1};
                valor = this.entrega_p_const_nom(oper)/sbase;
            else
                valor = this.entrega_p_const_nom()/sbase;
            end
        end
        
        function valor = entrega_q_const_nom_pu(this, varargin)
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            valor = this.entrega_q_const_nom()/sbase;
        end
        
        function valor = entrega_p_const_nom_opf(this)
            % TODO RAMRAM: hay que ver qué se hace con consumos
            % dependientes del voltaje
            valor = this.entrega_p_const_nom_pu();
        end

        function valor = entrega_q_const_nom_opf(this)
            valor = this.entrega_q_const_nom_pu();
        end
        
        function inserta_resultados_flujo_potencia(this, id_fp, P, Q)
            % todos los resultados se entregan en pu. Aquí se debe hacer la
            % conversión
            this.id_fp = id_fp;
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            this.Pfp = P*sbase;
            this.Qfp = Q*sbase;
        end
   
        function inserta_q_fp(this, Q)
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            this.Qfp = Q*sbase;
        end
        
        function inserta_p_fp(this, P)
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            this.Pfp = P*sbase;
        end

        function inserta_p_fp_mw(this, P)
            this.Pfp = P;
        end
        
        function val = entrega_p_fp(this)
            if this.EnServicio
                val = this.Pfp;
            else
                val = 0;
            end
        end
        
        function val = entrega_p_fp_pu(this)
            if this.EnServicio
                sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
                val = this.Pfp/sbase;
            else
                val = 0;
            end
        end
            
        function val = entrega_q_fp(this)
            if this.EnServicio
                val = this.Qfp;
            else
                val = 0;
            end
        end
        
        function val = en_servicio(this)
            val = this.EnServicio;
        end
        
        function inicializa_variables_fp(this)
            if this.DepVoltaje
                this.Qfp = 0;
                this.Pfp = 0;
            else
                this.Qfp = this.Q0;
                this.Pfp = this.P0;
            end
        end
        function borra_resultados_fp(this)
            this.id_fp = 0;
            this.Pfp = 0;
            this.Qfp = 0;
        end
        
        function inserta_costo_desconexion_carga(this, val)
            this.CostoDesconexionCarga = val;
        end
        
        function val = entrega_costo_desconexion_carga(this)
            val = this.CostoDesconexionCarga;
        end
        
        function val = entrega_costo_desconexion_carga_pu(this)
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();            
            val = this.CostoDesconexionCarga*sbase;
        end
        
        function inicializa_varopt_operacion_milp_dc(this, cant_escenarios, cant_etapas)
            this.IndiceVarOptP = zeros(cant_escenarios, cant_etapas);
        end
        
        function inserta_varopt_operacion(this, unidad, escenario, etapa, valor)
            switch unidad
                case 'P'
                    this.IndiceVarOptP(escenario, etapa) = valor;
                otherwise
                	error = MException('cConsumo:inserta_varopt','unidad no implementada');
                    throw(error)
            end
        end
        
        function val = entrega_varopt_operacion(this, unidad, escenario, etapa)
            switch unidad
                case 'P'
                    val = this.IndiceVarOptP(escenario, etapa);
                otherwise
                	error = MException('cConsumo:inserta_varopt','unidad no implementada');
                    throw(error)
            end
        end
        function inserta_etapa_entrada(this, escenario, indice)
            this.EtapaEntrada(escenario) = indice;
        end
        
        function indice = entrega_etapa_entrada(this, escenario)
            indice = this.EtapaEntrada(escenario);
        end
        function inserta_etapa_salida(this, escenario, indice)
            this.EtapaSalida(escenario) = indice;
        end
        
        function indice = entrega_etapa_salida(this, escenario)
            if length(this.EtapaSalida) >= escenario
                indice = this.EtapaSalida(escenario);
            elseif length(this.EtapaSalida) == 1 && this.EtapaSalida == 0
                indice = 0;
            else
                error = MException('cConsumo:entrega_etapa_salida','Datos incorrectos');
                throw(error)
            end
        end
        
    end
end