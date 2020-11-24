classdef cBateria < cElementoRed
        % clase que representa los transformadores
    properties 
        SE
        %parámetros técnicos
		Capacidad %MWh
        PmaxCarga % MW
        PmaxDescarga % MW
        Sr % MW

        SoCMin = 0 % SOC siempre en porcentaje de la capacidad
        Qmin = 0
        Qmax = 0
        
        CostoReservas = 0
        
        EtaCarga = 1
        EtaDescarga = 1
        EtaAlmacenamiento = 1

        ControlaTension = true
        VoltajeObjetivo = 0 % kV
        
        AnioConstruccion = 0
        VidaUtil

		CInvPotencia = 0  % mio. USD
		CInvCapacidad = 0  % mio. USD
        
        % Estado para planificacion.
        IdEstadoPlanificacion = 0
        IndiceDecisionExpansion = [] % indica el índice del corredor o bus utilizado en expansión de MCMC

        IndiceVarOptPdescarga = 0 % se utiliza en el MILP
        IndiceVarOptPcarga = 0 % se utiliza en el MILP
        IndiceVarOptE = 0
        
        IdTecnologia = -1
        IndiceParalelo = 0
        
        SoCActual = 1
        P0
        Q0
        
        % resultados del flujo de potencia
        id_fp = 0
        Pfp = 0
        Qfp = 0        
        SoCfp = 0
    end
    
    methods
        function this = cBateria()
            this.TipoElementoRed = 'ElementoParalelo';
        end
        
        
        function se = entrega_se(this)
            se = this.SE;
        end

        function inserta_subestacion(this, se)
            this.SE = se;
        end

        function inserta_indice_paralelo(this, indice)
            this.IndiceParalelo = indice;
        end
        
        function indice = entrega_indice_paralelo(this)
            indice = this.IndiceParalelo;
        end
        
        function inserta_costo_inversion_potencia(this, val)
    		this.CInvPotencia = val;
        end

        function inserta_costo_inversion_capacidad(this, val)
    		this.CInvCapacidad = val;
        end

        function val = entrega_costo_inversion(this)
            val = this.CInvPotencia + this.CInvCapacidad;
        end
                
        function inserta_vida_util(this, val)
            this.VidaUtil = val;
        end

        function val = entrega_vida_util(this)
            val = this.VidaUtil;
        end
        
        function inserta_id_tecnologia(this,val)
            this.IdTecnologia = val;
        end
        
        function val = entrega_id_tecnologia(this)
            val = this.IdTecnologia;
        end
        
        function inserta_resultados_fp(this, id_fp, P, Q, SoC)
            % resultados se entregan en valores reales
            this.id_fp = id_fp;
            this.Pfp = P;
            this.Qfp = Q;
            this.SoCfp = SoC;
        end
        
        function val = entrega_q(this)
            if this.EnServicio
                val = this.Qfp;
            else
                val = 0;
            end
        end

        function copia = crea_copia(this)
            copia = cBateria();
            copia.Nombre = this.Nombre;

            copia.Capacidad = this.Capacidad;
            copia.PmaxCarga = this.PmaxCarga;
            copia.PmaxDescarga = this.PmaxDescarga;
            copia.Sr = this.Sr;
            copia.SoCMin = this.SoCMin;
            copia.Qmin = this.Qmin;
            copia.Qmax = this.Qmax;
            
            copia.EtaCarga = this.EtaCarga;
            copia.EtaDescarga = this.EtaDescarga;
            copia.EtaAlmacenamiento = this.EtaAlmacenamiento;
        
            copia.VidaUtil = this.VidaUtil;

            copia.CInvPotencia = this.CInvPotencia;
            copia.CInvCapacidad = this.CInvCapacidad;
        
            copia.IdEstadoPlanificacion = this.IdEstadoPlanificacion;
            copia.IndiceDecisionExpansion = this.IndiceDecisionExpansion;
            copia.IndiceParalelo = this.IndiceParalelo;
            copia.SoCActual = this.SoCActual;
            copia.P0 = this.P0;
            copia.Q0 = this.Q0;
            copia.ControlaTension = this.ControlaTension;
            copia.VoltajeObjetivo = this.VoltajeObjetivo;
            copia.SE = this.SE;
            copia.AnioConstruccion = this.AnioConstruccion;
            copia.Existente = this.Existente;
            copia.IdTecnologia = this.IdTecnologia;
            copia.CostoReservas = this.CostoReservas;
        end
        
        function inserta_id_estado_planificacion(this, val)
            this.IdEstadoPlanificacion = val;
        end
        
        function val = entrega_id_estado_planificacion(this)
            val = this.IdEstadoPlanificacion;
        end

        function inserta_indice_decision_expansion(this, val)
            this.IndiceDecisionExpansion = val;
        end
        
        function val = entrega_indice_decision_expansion(this)
            val = this.IndiceDecisionExpansion;
        end

        
        function val = en_servicio(this)
            val = this.EnServicio;
        end
        
        function val = entrega_p_fp(this)
            val = this.Pfp;
        end
        
        function val = entrega_q_fp(this)
            val = this.Qfp;
        end
        
        function val = entrega_soc_fp(this)
            val = this.SoCfp;
        end

        function val = entrega_capacidad(this)
            val = this.Capacidad;
        end
        
        function inserta_capacidad(this, val)
            this.Capacidad = val;
        end
        
        function val = entrega_pmax_carga(this)
            val = this.PmaxCarga;
        end

        function inserta_pmax_carga(this, val)
            this.PmaxCarga = val;
        end

        function inserta_sr(this, val)
            this.Sr = val;
        end
        
        function val = entrega_sr(this)
            val = this.Sr;
        end
        
        function val = entrega_qmax_p(this, p)
            val = sqrt(this.Sr^2-p^2);
        end
        
        function inserta_pmax_descarga(this, val)
            this.PmaxDescarga = val;
        end
        
        function val = entrega_pmax_descarga(this)
            val = this.PmaxDescarga;
        end
        
        function val = entrega_soc_actual(this)
            val = this.SoCActual;
        end
        
        function inseta_soc_actual(this, val)
            this.SoCActual = val;
        end
        
        function inserta_soc_min(this, val)
            this.SoCMin = val;
        end
        
        function val = entrega_soc_min(this)
            val = this.SoCMin;
        end
        
        function inserta_eficiencia_carga(this, val)
            this.EtaCarga = val;
        end
        
        function val = entrega_eficiencia_carga(this)
            val = this.EtaCarga;
        end
        
        function inserta_eficiencia_descarga(this, val)
            this.EtaDescarga = val;
        end
        
        function val = entrega_eficiencia_descarga(this)
            val = this.EtaDescarga;
        end
        
        function inserta_eficiencia_almacenamiento(this, val)
            this.EtaAlmacenamiento = val;
        end
        
        function val = entrega_eficiencia_almacenamiento(this)
            val = this.EtaAlmacenamiento;
        end
        
        function valor = controla_tension(this)
            valor = this.ControlaTension;
        end
            
        function inserta_controla_tension(this)
            this.ControlaTension = true;
        end

        function inserta_voltaje_objetivo(this, val)
            this.VoltajeObjetivo = val;
        end
        
        function valor = entrega_voltaje_objetivo(this)
            if this.ControlaTension
                valor = this.VoltajeObjetivo;
            else
                error = MException('cBateria:entrega_voltaje_objetivo','bateria no controla tension');
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
        
        function inserta_anio_construccion(this, val)
            this.AnioConstruccion = val;
        end
        
        function val = entrega_anio_construccion(this)
            val = this.AnioConstruccion;
        end

        function val = entrega_potencia_maxima_descarga_actual(this)
            val = min(this.PmaxDescarga, this.Capacidad*(this.SoCActual - this.SoCMin)/this.EtaDescarga);
        end

        function val = entrega_potencia_maxima_carga_actual(this)
            val = min(this.PmaxCarga, this.Capacidad*(1-this.SoCActual)/this.EtaCarga);
        end
        
        function val = entrega_energia_minima(this)
            val = this.Capacidad*this.SoCMin;
        end
        
        function val = entrega_capacidad_efectiva(this)
            val = this.Capacidad(1-this.SoCMin);
        end
        
        function inicializa_varopt_operacion_milp_dc(this, cant_escenarios, cant_etapas)
            this.IndiceVarOptPdescarga = zeros(cant_escenarios, cant_etapas);
            this.IndiceVarOptPcarga = zeros(cant_escenarios, cant_etapas);
            this.IndiceVarOptE = zeros(cant_escenarios, cant_etapas);
        end

        function inserta_varopt_operacion(this, unidad, escenario, etapa, valor)
            switch unidad
                case 'Pcarga'
                    this.IndiceVarOptPcarga(escenario, etapa) = valor;
                case 'Pdescarga'
                    this.IndiceVarOptPdescarga(escenario, etapa) = valor;
                case 'E'
                    this.IndiceVarOptE(escenario, etapa) = valor;
                otherwise
                	error = MException('cLinea:inserta_varopt_operacion','unidad no implementada');
                    throw(error)
            end
        end
        
        function val = entrega_varopt_operacion(this, unidad, escenario, etapa)
            switch unidad
                case 'Pcarga'
                    val = this.IndiceVarOptPcarga(escenario, etapa);
                case 'Pdescarga'
                    val = this.IndiceVarOptPdescarga(escenario, etapa);
                case 'E'
                    val = this.IndiceVarOptE(escenario, etapa);
                otherwise
                	error = MException('cLinea:entrega_varopt_operacion','unidad no implementada');
                    throw(error)
            end
        end
        
        function nombre = entrega_nombre_se(this)
            nombre = this.SE.Nombre;
        end
        
        function inserta_costo_reserva(this, val)
            this.CostoReservas = val;
        end
        
        function val = entrega_costo_reserva(this)
            val = this.CostoReservas;
        end
    end
end