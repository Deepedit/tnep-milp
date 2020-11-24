classdef cGenerador < cElementoRed
        % clase que representa las lineas de transmision
    properties
        %datos generales
        % Nombre está en clase cElementoRed
        SE = cSubestacion.empty
        
        % IdResEvaluacion separa entre generadores despachables y ERNC
        % TODO: parámetro IdResEvaluacion no va más
        %IdResEvaluacion = 0
        
        %parámetros técnicos
        % valores nominales
        Snom = []
 		Cosp = 0.9
        TipoCosp = 1 %1: inductivo; -1: capacitivo
        
        % Parametros técnicos de operacion
        Pmax = 0
        Pmin = 0
        Qmin = 0
        Qmax = 0
        QmaxPmax = 0
        QmaxPmin = 0
        QminPmax = 0
        QminPmin = 0
        
		ControlaTension = false
        VoltajeObjetivo = 0 %en kV
        Slack = false
        Despachable = true
        EntregaReservas = true
        LimiteReservasPositivas = 0
        LimiteReservasNegativas = 0
        
        %ERNC = false
        IndiceOperacion = 0  % si generador no es despachable, entonces indice de operacion es distinto de cero
        TipoCentral = 0  % 1:central térmicas, 2: ercn; 3: central hidráulica; 4: CSP
        TipoTecnologia = 1 % se utiliza para expansión de la generación. Permite diferenciar distintas tecnologías
        TMinOperacion = 0
        TMinFueraServicio = 0
        TasaTomaCarga = 9999        
        CoefEmisionCO2 = 0

        %parámetros económicos
        Costo_MWh = 0
        CostoFijo = 0
        CostoPartida = 0
        CostoDetencion = 0
        CostoReservasPos = 0
        CostoReservasNeg = 0
        
        % parámetros de centrales hidráulicas
        AfluenteMinimo = 0
        AfluenteMaximo = 0
        AlturaCaida = 0
        Embalse = cEmbalse.empty
        Eficiencia = 0
        
        % parámetros de centrales con almacenamiento térmico
        Almacenamiento = cAlmacenamiento.empty
        
        % EnServicio está en clase cElementoRed

        % Parámetro "Existente" se encuentra en cElementoRed
        % Si generador no es existente, entonces se indica su etapa de entrada 
        % ojo que por cada escenario se debe definir un generador!
        EtapaEntrada = 0 %indice correspondiente dentro del escenario
        
        % Para generadores existentes en donde se tiene contemplado su
        % retiro. 
        RetiroProyectado = false  % true para retiro de unidades térmicas
        EtapaRetiro = 0 % en caso de que se contemple retiro
                
        % Siguientes parámetros son para generadores existentes, e indica
        % si su capacidad evoluciona a futuro.
        EvolucionCapacidadAFuturo = false % en caso de se contemple aumento de capacidad, valor es true
        IndiceAdmEscenarioCapacidad = 0

        % Siguientes parámetros son para generadores convencionales, e
        % indica si los precios evolucionan a futuro. El índice es único,
        % es decir, todos los escenarios contienen los mismos generadores
        % convencionales, cuando los costos evolucionan a futuro.
        EvolucionCostosAFuturo = false
        IndiceAdmEscenarioCostosFuturos = 0
        
        % Para generadores ERNC. Perfil de inyecciones horarias
        IndiceAdmEscenarioPerfilERNC = 0
        
        % Los siguientes índices son para programa de planificación, y son los mismos para todos los generadores, 
        % independiente de los escenarios
        IndiceVarOptExpansion %por si a futuro se hace expansion de la transmisión y generación
        IndiceVarOptP = 0
        IndiceVarOptQ = 0
        
        % Valores nominales para el flujo de potencias
        P0 = 0
        Q0 = 0
        
        % resultado del flujo de potencias. Eventualmente generador puede
        % participar en regulación primaria y por ende no coincide con
        % valores nominales
        % controla tension FP indica si como resultado del fp el
        % generador aún controla tensión.
        % Pfp puede diferir de P0 no sólo por si bus es slack, sino que
        % también en caso de que participe en el control primario
        id_fp = 0
        ControlaTensionFP
        Pfp = 0
        Qfp = 0        
    end
    
    methods
        function this = cGenerador()
            this.TipoElementoRed = 'ElementoParalelo';
        end
        
        function capacidad = entrega_capacidad(this)
            capacidad = this.Snom;
        end
        
        function pmax = entrega_pmax(this)
            pmax = this.Pmax;
        end

        function pmin = entrega_pmin(this)
            pmin = this.Pmin;
        end

        function generador = crea_copia(this)
            % crea una copia pero sólo elementos que se
            % pueden copiar o que vale la pena copiar. No se copia ningún puntero
            % no se copian resultados del flujo de potencia

            generador = cGenerador();
            generador.Nombre = this.Nombre;
            generador.Id = this.Id;
            %generador.IdResEvaluacion = this.IdResEvaluacion;
            generador.Snom = this.Snom;
            generador.Cosp = this.Cosp;
            generador.Costo_MWh = this.Costo_MWh;
            generador.CostoFijo = this.CostoFijo;
            generador.CostoPartida = this.CostoPartida;
            generador.CostoDetencion = this.CostoDetencion;
            generador.ControlaTension = this.ControlaTension;
            generador.VoltajeObjetivo = this.VoltajeObjetivo;
            generador.Despachable = this.Despachable;
            %generador.ERNC = this.ERNC;
            generador.IndiceOperacion = this.IndiceOperacion;
            generador.Pmax = this.Pmax;
            generador.Pmin = this.Pmin;
            generador.TipoCentral = this.TipoCentral;
            generador.TipoTecnologia = this.TipoTecnologia;
            generador.TMinFueraServicio = this.TMinFueraServicio;
            generador.TMinOperacion = this.TMinOperacion;
            generador.Slack = this.Slack;
            generador.P0 = this.P0;
            generador.Q0 = this.Q0;
            generador.QmaxPmax = this.QmaxPmax;
            generador.QmaxPmin = this.QmaxPmin;
            generador.QminPmax = this.QminPmax;
            generador.QminPmin = this.QminPmin;
            generador.Qmax  = this.Qmax;
            generador.Qmin = this.Qmin;
            generador.FlagObservacion = this.FlagObservacion;
			generador.Existente = this.Existente;
            generador.SE = this.SE;
            generador.EntregaReservas = this.EntregaReservas;
            generador.CostoReservasPos = this.CostoReservasPos;
            generador.CostoReservasNeg = this.CostoReservasNeg;            
            
            generador.AfluenteMinimo = this.AfluenteMinimo;
            generador.AfluenteMaximo = this.AfluenteMaximo;
            generador.AlturaCaida = this.AlturaCaida;
            generador.Embalse = this.Embalse;
            generador.Eficiencia = this.Eficiencia;
            
            generador.Almacenamiento = this.Almacenamiento;
            
            % parámetros de expansión
            generador.EtapaEntrada = this.EtapaEntrada;
            generador.RetiroProyectado = this.RetiroProyectado;
            generador.EtapaRetiro = this.EtapaRetiro;
            generador.EvolucionCapacidadAFuturo = this.EvolucionCapacidadAFuturo;
            generador.IndiceAdmEscenarioCapacidad = this.IndiceAdmEscenarioCapacidad;
            generador.EvolucionCostosAFuturo = this.EvolucionCostosAFuturo;
			generador.IndiceAdmEscenarioPerfilERNC = this.IndiceAdmEscenarioPerfilERNC;
            generador.IndiceAdmEscenarioCostosFuturos = this.IndiceAdmEscenarioCostosFuturos;            
        end
        
        function nombre = entrega_nombre_se(this)
            nombre = this.SE.Nombre;
        end
        
        function inserta_subestacion(this, se)
            this.SE = se;
        end
            
        function indice = entrega_indice_operacion(this)
            indice = this.IndiceOperacion;
        end
        
        function inserta_etapa_entrada(this, escenario, indice)
            this.EtapaEntrada(escenario) = indice;
        end
        
        function indice = entrega_etapa_entrada(this, escenario)
            indice = this.EtapaEntrada(escenario);
        end
        
        function inserta_evolucion_capacidad_a_futuro(this, val)
            this.EvolucionCapacidadAFuturo = val;
        end
        
        function val = entrega_evolucion_capacidad_a_futuro(this)
            val = this.EvolucionCapacidadAFuturo;
        end
        
        function inserta_indice_adm_escenario_capacidad(this, escenario, val)
            this.IndiceAdmEscenarioCapacidad(escenario) = val;
        end
        
        function val = entrega_indice_adm_escenario_capacidad(this, escenario)
            val = this.IndiceAdmEscenarioCapacidad(escenario);
        end
                
        function inserta_evolucion_costos_a_futuro(this, val)
            this.EvolucionCostosAFuturo = val;
        end
        
        function val = entrega_evolucion_costos_a_futuro(this)
            val = this.EvolucionCostosAFuturo;
        end

        function inserta_indice_adm_escenario_costos_futuros(this, escenario, val)
            this.IndiceAdmEscenarioCostosFuturos(escenario) = val;
        end
        
        function val = entrega_indice_adm_escenario_costos_futuros(this, escenario)
            val = this.IndiceAdmEscenarioCostosFuturos(escenario);
        end
                
        function inserta_retiro_proyectado(this,val)
            this.RetiroProyectado = val;
        end
        
        function val = entrega_retiro_proyectado(this)
            val = this.RetiroProyectado;
        end
        
        function inserta_etapa_retiro(this, escenario, val)
            this.EtapaRetiro(escenario) = val;
        end
        
        function val = entrega_etapa_retiro(this, escenario)
            val = this.EtapaRetiro(escenario);
        end
        
        function se = entrega_se(this)
            se = this.SE;
        end
        
        function inserta_es_slack(this)
            this.Slack = true;
        end
        
        function valor = es_slack(this)
            valor = this.Slack;
        end
        
        function val = entrega_p_const_nom(this)
            % para flujo de potencias
            val = this.Pfp;
        end

        function val = entrega_p_const_nom_opf(this, varargin)
            % para OPF. valores siempre en pu
            if this.Despachable
                val = 0;
            else
                sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
                val = this.P0/sbase;
            end
        end
        
        function val = entrega_p_const_nom_pu(this)
            % para flujo de potencias
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            val = this.Pfp/sbase;
        end
        
        function val = entrega_p0(this, varargin)
            % varargin indica el punto de operación
            if nargin > 1
                po = varargin{1};
                val = this.P0(po);
            else
                val = this.P0;
            end
        end

        function val = entrega_p0_pu(this)
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            val = this.P0/sbase;
        end
        
        function val = entrega_q_const_nom(this)
            if this.ControlaTensionFP
                val = 0;
            else
                % bus no controla tensión como resultado del flujo de
                % potencias. Se entrega Q como resultado del flujo de
                % potencias
                val = this.Qfp;
            end
        end

        function val = entrega_q_const_nom_opf(this)
            % valores siempre en pu
            if this.ControlaTensionFP
                val = 0;
            else
                % bus no controla tensión como resultado del flujo de
                % potencias. Se entrega Q como resultado del flujo de
                % potencias
                sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
                val = this.Qfp/sbase;
            end
        end
        
        function val = entrega_q_const_nom_pu(this)
            if this.ControlaTensionFP
                val = 0;
            else
                % bus no controla tensión como resultado del flujo de
                % potencias. Se entrega Q como resultado del flujo de
                % potencias
                sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
                val = this.Qfp/sbase;
            end
        end
        
        function val = entrega_q0(this)
            val = this.Q0;
        end
        
        function val = entrega_q0_pu(this)
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            val = this.Q0*sbase;
        end
        
        function inserta_controla_tension(this)
            this.ControlaTension = true;
        end

        function inserta_controla_tension_fp(this, val)
            this.ControlaTensionFP = val;
        end
        
        function valor = controla_tension(this)
            valor = this.ControlaTension;
        end
        
        function inserta_voltaje_objetivo(this, val)
            this.VoltajeObjetivo = val;
        end
        
        function valor = entrega_voltaje_objetivo(this)
            if this.ControlaTension
                valor = this.VoltajeObjetivo;
            else
                error = MException('cGenerador:entrega_voltaje_objetivo','generador no controla tension');
                throw(error)
            end
        end

        function valor = entrega_voltaje_objetivo_pu(this)
            if this.ControlaTension
                vbase = this.SE.entrega_vbase();
                valor = this.VoltajeObjetivo/vbase;
            else
                error = MException('cGenerador:entrega_voltaje_objetivo','generador no controla tension');
                throw(error)
            end
        end
        
        function valor = entrega_qmin_p(this, p)
            if this.QminPmax == this.QminPmin || this.QminPmax == 0 || this.QminPmin == 0
                % no hay valores. Se calcula en base a la capacidad del generador
                valor = max(-1*sqrt(this.Snom^2 - p^2), this.Qmin);
                return;
            end
            
            pendiente = (this.QminPmax - this.QminPmin)/(this.Pmax - this.Pmin);
            y0 = this.QminPmin - pendiente * this.Pmin;
            valor = y0 + pendiente * p;
        end

        function valor = entrega_qmax_p(this, p)
            if this.QmaxPmax == this.QmaxPmin || this.QmaxPmax == 0 || this.QmaxPmin == 0
                % no hay valores. Se calcula en base a la capacidad del generador
                valor = min(sqrt(this.Snom^2 - p^2), this.Qmax);
                return;
            end
            
            pendiente = (this.QmaxPmax - this.QmaxPmin)/(this.Pmax - this.Pmin);
            y0 = this.QminPmin - pendiente * this.Pmin;
            valor = y0 + pendiente * p;
        end

        function valor = entrega_qmin_p_pu(this, p_pu)
            % primero cambio de base, luego calcula y finalmente cambio de
            % base nuevamente
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            p = p_pu * sbase;
            valor = this.entrega_qmin_p(p)/sbase;
        end

        function valor = entrega_qmax_p_pu(this, p_pu)
            % primero cambio de base, luego calcula y finalmente cambio de
            % base nuevamente
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            p = p_pu * sbase;
            valor = this.entrega_qmax_p(p)/sbase;
            
        end
        
        function val = entrega_p_fp(this)
            val = this.Pfp;
        end

        function val = entrega_p_fp_pu(this)
            % Eventualmente lo necesita el sistema modal
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            val = this.Pfp/sbase;
        end
        
        function val = entrega_q_fp(this)
            val = this.Qfp;
        end
        
        function val = entrega_q_fp_pu(this)
            % Eventualmente lo necesita el sistema modal
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            val = this.Qfp/sbase;
        end
        
        function val = en_servicio(this)
            val = this.EnServicio;
        end
        
        function inserta_p0(this, val)
            if (val > this.Pmax || val < this.Pmin) && ~this.Slack
                texto = ['P0 dado (' num2str(val) ') está fuera de los límites del generador (PMin/Pmax = ' num2str(this.Pmin) '/' num2str(this.Pmax) ')'];
                warning(texto);
                if val > this.Pmax
                    this.P0 = this.Pmax;
                else
                    this.P0 = this.Pmin;
                end
                %error = MException('cGenerador:inserta_p0',texto);
                %throw(error)
            end
            this.P0 = val;
        end

        function inserta_q0(this, val)
            if (val > this.Qmax || val < this.Qmin) && ~this.Slack
                texto = ['Q0 dado (' num2str(val) ') está fuera de los límites del generador (QMin/Qmax = ' num2str(this.Qmin) '/' num2str(this.Qmax) ')'];
                warning(texto);
                if val > this.Qmax
                    this.Q0 = this.Qmax;
                else
                    this.Q0 = this.Qmin;
                end
                %error = MException('cGenerador:inserta_p0',texto);
                %throw(error)
            end
            this.Q0 = val;
        end
        
        function inserta_pmax(this, val)
            this.Pmax = val;
            if isempty(this.Snom)
                this.Snom = 1.1*val;
            end
        end
        
        function pmax = entrega_pmax_pu(this)
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            pmax = this.Pmax/sbase;
        end
        
        function inserta_pmin(this, val)
            this.Pmin = val;
        end
                
        function pmin = entrega_pmin_pu(this)
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            pmin = this.Pmin/sbase;
        end
        
        function inserta_qmin(this, val)
            this.Qmin = val;
        end
        
        function qmin = entrega_qmin(this)
            qmin = this.Qmin;
        end

        function qmin = entrega_qmin_pu(this)
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            qmin = this.Qmin/sbase;
        end
        
        function inserta_qmax(this, val)
            this.Qmax = val;
        end
        
        function qmax = entrega_qmax(this)
            qmax = this.Qmax;
        end

        function qmax = entrega_qmax_pu(this)
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            qmax = this.Qmax/sbase;
        end
        
        function inserta_nombre(this, nombre)
            this.Nombre = nombre;
        end
        
        function nombre = entrega_nombre(this)
            nombre = this.Nombre;
        end
        
        function inserta_p_fp(this, P)
            % desde el sistema modal viene todo en pu. Conversión se hace
            % aquí
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            this.Pfp = P*sbase;
        end
        
        function inserta_p_fp_mw(this,P)
            this.Pfp = P;
        end
        
        function inserta_q_fp(this, Q)
            % desde el sistema modal viene todo en pu. Conversión se hace
            % aquí
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            this.Qfp = Q*sbase;
        end
        
        function inicializa_variables_fp(this)
            this.ControlaTensionFP = this.ControlaTension;
            this.Pfp = this.P0;
            if this.ControlaTensionFP
                this.Qfp = 0;
            else
                this.Qfp = this.Q0;
            end
        end
                
        function val = controla_tension_fp(this)
            val = this.ControlaTensionFP;
        end
        
        function tipo = entrega_tipo_central(this)
            tipo = this.TipoCentral;
        end
        
        function inserta_tipo_tecnologia(this, tipo)
            this.TipoTecnologia = tipo;
        end
        
        function tipo = entrega_tipo_tecnologia(this)
            tipo = this.TipoTecnologia;
        end
        
        function val = es_turbina_hidraulica(this)
            val = this.TipoCentral == 3;
        end
        
        function inserta_tipo_central(this, tipo)
            this.TipoCentral = tipo;
        end
        
        function inserta_id_fp(this, id)
            this.id_fp = id;
        end
                
        function inicializa_varopt_operacion_milp_dc(this, cant_escenarios, cant_etapas)
            this.IndiceVarOptP = zeros(cant_escenarios, cant_etapas);
        end
        
        function inserta_varopt_operacion(this, unidad, escenario, etapa, valor)
            switch unidad
                case 'P'
                    this.IndiceVarOptP(escenario, etapa) = valor;
                case 'Q'
                    this.IndiceVarOptQ(escenario, etapa) = valor;
                otherwise
                	error = MException('cGenerador:inserta_varopt','unidad no implementada');
                    throw(error)
            end
        end
        
        function val = entrega_varopt_operacion(this, unidad, escenario, etapa)
            % no necesariamente es escenario etapa. También puede ser
            % etapa, punto de operación para DC-OPF en TNEP heurístico
            switch unidad
                case 'P'
                    val = this.IndiceVarOptP(escenario, etapa);
                case 'Q'
                    val = this.IndiceVarOptQ(escenario, etapa);
                otherwise
                	error = MException('cGenerador:inserta_varopt','unidad no implementada');
                    throw(error)
            end
        end
        
        function inserta_costo_mwh(this, val)
            this.Costo_MWh = val;
        end
        
        function val = entrega_costo_mwh(this)
            val = this.Costo_MWh;
        end
        
        function val = entrega_costo_mwh_pu(this)
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            val = this.Costo_MWh * sbase;
        end
        
        function borra_resultados_fp(this)
            this.id_fp = 0;
            this.ControlaTensionFP = this.ControlaTension;
            this.Pfp = 0;
            this.Qfp = 0;
        end
        
        function inserta_es_despachable(this, val)
            this.Despachable = val;
        end
        
        function val = es_despachable(this)
            val = this.Despachable;
        end
        
        function val = es_ernc(this)
            val = ~this.Despachable;
        end
        
        function inserta_indice_adm_escenario_perfil_ernc(this, val)
            this.IndiceAdmEscenarioPerfilERNC = val;
        end
        
        function val = entrega_indice_adm_escenario_perfil_ernc(this)
            val = this.IndiceAdmEscenarioPerfilERNC;
        end
        
        function val = entrega_max_agua_turbinada(this)
            val = this.AfluenteMaximo;
        end

        function val = entrega_min_agua_turbinada(this)
            val = this.AfluenteMinimo;
        end
        
        function inicializa_central_hidraulica(this)
            this.AfluenteMaximo = 1000*this.Pmax/(this.Eficiencia*9.81*(this.AlturaCaida + this.Embalse.AlturaMin)*1);
            this.AfluenteMinimo = 1000*this.Pmin/(this.Eficiencia*9.81*(this.AlturaCaida + this.Embalse.AlturaMin)*1);
        end

        function embalse = entrega_embalse(this)
            embalse = this.Embalse;
        end
        
        function val = tiene_almacenamiento(this)
            val = ~isempty(this.Almacenamiento);
        end
        
        function inserta_almacenamiento(this, almacenamiento)
            this.Almacenamiento = almacenamiento;
        end
        
        function almacenamiento = entrega_almacenamiento(this)
            almacenamiento = this.Almacenamiento;
        end
        
        function nombre = entrega_nombre_almacenamiento(this)
            nombre = this.Almacenamiento.entrega_nombre();
        end
        
        function inserta_eficiencia(this, val)
            this.Eficiencia = val;
        end
        
        function val = entrega_eficiencia(this)
            val = this.Eficiencia;
        end
        
        function inserta_entrega_reservas(this, val)
            this.EntregaReservas = val;
        end
        
        function val = entrega_reservas(this)
            val = this.EntregaReservas;
        end
        
        function inserta_costo_reservas_positivas(this, val)
            this.CostoReservasPos = val;
        end
        
        function val = entrega_costo_reservas_positivas(this)
            val = this.CostoReservasPos;
        end
        
        function inserta_costo_reservas_negativas(this, val)
            this.CostoReservasNeg = val;
        end
        
        function val = entrega_costo_reservas_negativas(this)
            val = this.CostoReservasNeg;
        end
        
        function val = entrega_costo_partida(this)
            val = this.CostoPartida;
        end
        
        function inserta_costo_partida(this, val)
            this.CostoPartida = val;
        end
        function val = entrega_costo_detencion(this)
            val = this.CostoDetencion;
        end
        
        function inserta_costo_detencion(this, val)
            this.CostoDetencion = val;
        end
        
        function inserta_tiempo_minimo_operacion(this,val)
            this.TMinOperacion = val;
        end
        
        function val = entrega_tiempo_minimo_operacion(this)
            val = this.TMinOperacion;
        end

        function inserta_tiempo_minimo_detencion(this, val)
            this.TMinFueraServicio = val;
        end
        
        function val = entrega_tiempo_minimo_detencion(this)
            val = this.TMinFueraServicio;
        end
        
        function inserta_limite_reservas_positivas(this, val)
            this.LimiteReservasPositivas = val;
        end
        
        function inserta_limite_reservas_negativas(this, val)
            this.LimiteReservasNegativas = val;
        end
        
        function val = entrega_limite_reservas_positivas(this)
            val = this.LimiteReservasPositivas;
        end
        
        function val = entrega_limite_reservas_negativas(this)
            val = this.LimiteReservasNegativas;
        end
        
    end
end