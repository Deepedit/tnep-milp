classdef cLinea < cElementoRed
        % clase que representa las lineas de transmision
    properties (Access = private)
        % Datos generales
        % Nombre e ID están en clase cElementoRed
        IdCorredor = 0
        IndiceParalelo = 0
        SE1 = cSubestacion.empty
        SE2 = cSubestacion.empty
        Largo = 0
        
        %parámetros técnicos
		Sr = 0  % Capacidad nominal en MVA
        Sth = 0 % Capacidad térmica en MVA
        
        SrN1 = 0 % Capacidad de la línea post-falla
        
        TipoConductor = -1
        AnioConstruccion = 0 % ej: 2005
        VidaUtil = 0
        
        EtapaEntrada = 0  %No confundir con anio de construccion (ej: 4). Sólo para líneas en construcción. 
        
        % compensación serie en porcentaje
        % Estado de la compensación indica si está activa o no (bypass)
        % 1: activa
        % 0: by-pass
        PorcentajeCompensacion = 0 
        EstadoCompensacion = 0
        
        % Variables para la optimización de la expansión
        % Estado para planificacion.
        IdEstadoPlanificacion = 0 % se utiliza en programas heurísticos
        IndiceVarOptP = 0 % se utiliza en el MILP

        % por unidad de longitud
        Xpul = 0 % Ohm/km
		Rpul = 0 % Ohm/km
        Cpul = 0 % uF/km
        Gpul = 0 % mS/Km
        
		%parámetros económicos
		Costo_conductor = 0  % mio. USD
        Costo_torre = 0  % mio. USD
        Costo_compensacion_serie = 0 % mio. USD
        Costo_servidumbre = 0  %mio. USD
        ROW = 0 % Ha totales
        Diametro_conductor = 0 %mm
        % Flag OPF para líneas compensadas. Se determina el estado de la
        % compensación (abierta/cerrada)
        OPF = false
        
		%Indice para resultados y optimizacion de planificación y despacho
		%económico
        IndiceDecisionExpansion = [] % indica el índice del corredor o bus utilizado en expansión de MCMC
                
        % Resultados de flujo de potencia para ambos lados de la línea
        id_fp = 0
        I1
        I2
        ThetaI1 %en grados
        ThetaI2
        S1
        S2
        Perdidas % complejo        
    end
    
    methods
        function this = cLinea()
            this.TipoElementoRed = 'ElementoSerie';
        end

        function inserta_nombre(this, nombre)
            this.Nombre = nombre;
        end
        
        function nombre = entrega_nombre(this)
            nombre = this.Nombre;
        end
        
        function [subestacion1, subestacion2] = entrega_subestaciones(this)
            subestacion1 = this.SE1;
            subestacion2 = this.SE2;
        end
        
        function reactancia = entrega_reactancia(this)
            reactancia = this.Largo * this.Xpul;
            if this.EstadoCompensacion
                reactancia = reactancia*(1-this.PorcentajeCompensacion);
            end
        end
        
        function val = entrega_reactancia_pul(this)
            val = this.Xpul*(1-this.PorcentajeCompensacion);
        end
        
        function reactancia = entrega_reactancia_pu(this)
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            zbase = this.SE1.entrega_vbase()^2/sbase;
            if this.EstadoCompensacion
                reactancia = this.Largo * this.Xpul/zbase*(1-this.PorcentajeCompensacion);
            else
                reactancia = this.Largo * this.Xpul/zbase;
            end
        end

        function val = entrega_susceptancia(this)
            val = this.Largo * this.Cpul* 2 *pi *50;
        end
        
        function val = entrega_susceptancia_pu(this)
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            zbase = this.SE1.entrega_vbase()^2/sbase;
            val = this.Largo * this.Cpul * 2 *pi *50 / 1000000 *zbase;
        end
        
        function inserta_largo(this, largo)
            this.Largo = largo;
        end
        
        function val = largo(this)
            val = this.Largo;
        end

        function resistencia = entrega_resistencia(this)
            resistencia = this.Largo * this.Rpul;
        end
        
        function resistencia = entrega_resistencia_pu(this)
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            zbase = this.SE1.entrega_vbase()^2/sbase;
            resistencia = this.Largo * this.Rpul/zbase;
        end
                
        function inserta_xpul(this, val)
            this.Xpul = val;
        end
        
        function inserta_rpul(this, val)
            this.Rpul = val;
        end

        function inserta_cpul(this, val)
            this.Cpul = val;
        end

        function inserta_gpul(this, val)
            this.Gpul = val;
        end
        
        function val = entrega_xpul(this)
            val = this.Xpul;
        end
        
        function val = entrega_rpul(this)
            val = this.Rpul;
        end
        
        function val = entrega_cpul(this)
            val = this.Cpul;
        end
        
        function val = entrega_gpul(this)
            val = this.Gpul;
        end

        function linea = crea_copia(this)
            % crea una copia pero sólo elementos que se
            % pueden copiar o que vale la pena copiar. El único puntero que
            % se copia es la subestación, la que tiene que ser ajustada en
            % caso de ser necesario
            linea = cLinea();
            linea.Nombre = this.Nombre;
            linea.Id = this.Id;
            linea.IndiceParalelo = this.IndiceParalelo;
            linea.EnServicio = this.EnServicio;
            linea.Largo = this.Largo;
            linea.Sr = this.Sr;
            linea.SrN1 = this.SrN1;
            linea.Sth = this.Sth;
            linea.Xpul = this.Xpul;
            linea.Rpul = this.Rpul;
            linea.Cpul = this.Cpul;
            linea.Gpul = this.Gpul;
            linea.SE1 = this.SE1;
            linea.SE2 = this.SE2;
            linea.TipoConductor = this.TipoConductor;
            linea.PorcentajeCompensacion = this.PorcentajeCompensacion;
            linea.EstadoCompensacion = this.EstadoCompensacion;
            linea.Costo_conductor = this.Costo_conductor;
            linea.Costo_torre = this.Costo_torre;
            linea.Costo_compensacion_serie = this.Costo_compensacion_serie;
            linea.Costo_servidumbre = this.Costo_servidumbre;
            linea.ROW = this.ROW;
            linea.Diametro_conductor = this.Diametro_conductor;
            linea.AnioConstruccion = this.AnioConstruccion;
            linea.VidaUtil = this.VidaUtil;
            linea.IdEstadoPlanificacion = this.IdEstadoPlanificacion;
            linea.IdCorredor = this.IdCorredor;
            linea.IdAdmProyectos = this.IdAdmProyectos;
            linea.Existente = this.Existente;
            linea.FlagObservacion = this.FlagObservacion;
            linea.IndiceDecisionExpansion = this.IndiceDecisionExpansion;
        end

        function nombre = entrega_nombre_se(this, nro)
            if nro == 1
                nombre = this.SE1.Nombre;
            elseif nro == 2
                nombre = this.SE2.Nombre;
            else
                error = MException('cLinea:entrega_nombre_se','nro tiene que ser cero o uno');
                throw(error)
            end
        end
  
        function inserta_sr(this, val)
            this.Sr = val;
        end
        
        function val = entrega_sr(this)
            val = this.Sr;
        end
        
        function inserta_sth(this, val)
            this.Sth = val;
        end

        function val = entrega_sth(this)
            val = this.Sth;
        end

        function inserta_sr_n1(this, val)
            this.SrN1 = val;
        end
        
        function val = entrega_sr_n1(this)
            if this.SrN1 == 0
                val = this.Sr;
            else
                val = this.SrN1;
            end
        end
        
        function val = entrega_sr_pu(this)
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            val = this.Sr/sbase;
        end
        
        function inserta_subestacion(this, subestacion, indice)
            if indice == 1
                this.SE1 = subestacion;
            elseif indice == 2
                this.SE2 = subestacion;
            else
                error = MException('cLinea:inserta_subestacion','nro tiene que ser cero o uno');
                throw(error)
            end
        end
        
        function se1 = entrega_se1(this)
            se1 = this.SE1;
        end

        function se2 = entrega_se2(this)
            se2 = this.SE2;
        end
                
        function [y11, y12, y21, y22] = entrega_cuadripolo(this)
            % Siempre en pu. 
            if this.Largo == 0
                error = MException('cLinea:entrega_cuadripolo','largo de la línea no definido');
                throw(error)
            end
            
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            zbase = this.SE1.entrega_vbase()^2/sbase;
            x = this.Largo * this.Xpul;
            if this.EstadoCompensacion
                x = x*(1-this.PorcentajeCompensacion);
            end
            r = this.Largo * this.Rpul;
            b = this.Largo * this.Cpul * 2 *pi *50 / 1000000;
            g = this.Largo * this.Gpul;
            yserie = 1/complex(r,x);
            y0 = complex(0.5*g,0.5*b);

            y12 = -yserie*zbase;
            y21 = -yserie*zbase;
            y11 = (y0 + yserie)*zbase;
            y22 = (y0 + yserie)*zbase;
        end
        
        function inserta_resultados_fp_en_pu(this, id_fp, I1, I2, ThetaI1, ThetaI2, S1, S2, Perdidas)
            % todos los resultados se entregan en pu. Aquí hay que hacer la
            % conversión
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            vbase = this.SE1.entrega_vbase();
            ibase = sbase/vbase;
            
            this.id_fp = id_fp;
            this.I1 = I1*ibase/sqrt(3); %unidades? x1000?
            this.I2 = I2*ibase/sqrt(3);
            this.ThetaI1 = ThetaI1/pi*180;
            this.ThetaI2 = ThetaI2/pi*180;
            this.S1 = S1*sbase;
            this.S2 = S2*sbase;
            this.Perdidas = Perdidas*sbase;
        end

        function inserta_resultados_fp(this, id_fp, I1, I2, ThetaI1, ThetaI2, S1, S2, Perdidas)
            % resultados se entregan en valores reales
            
            this.id_fp = id_fp;
            this.I1 = I1;
            this.I2 = I2;
            this.ThetaI1 = ThetaI1;
            this.ThetaI2 = ThetaI2;
            this.S1 = S1;
            this.S2 = S2;
            this.Perdidas = Perdidas;
        end
        
        function val = entrega_perdidas_activas(this)
            if this.EnServicio
                val = real(this.Perdidas);
            else
                val = 0;
            end
        end
        
        function val = entrega_perdidas_reactivas(this)
            if this.EnServicio
                val = imag(this.Perdidas);
            else
                val = 0;
            end
        end
        
        function val = entrega_p_in(this)
            % potencia real al comienzo / entrada de la linea
            if this.EnServicio
                val = real(this.S1);
            else
                val = 0;
            end
        end
        
        function val = entrega_p_out(this)
            % potencia real al final /salida de la línea
            if this.EnServicio
                val = real(this.S2);
            else
                val = 0;
            end
        end
        
        function val = entrega_q_in(this)
            if this.EnServicio
                val = imag(this.S1);
            else
                val = 0;
            end
        end
        
        function val = entrega_q_out(this)
            if this.EnServicio
                val = imag(this.S2);
            else
                val = 0;
            end
        end
        
        function val = en_servicio(this)
            val = this.EnServicio;
        end
        
        function val = entrega_i_in(this)
            if this.EnServicio
                val = this.I1;
            else
                val = 0;
            end
        end
        
        function val = entrega_i_out(this)
            if this.EnServicio
                val = this.I2;
            else
                val = 0;
            end
        end
        
        function val = entrega_s_in(this)
            if this.EnServicio
                val = this.S1;
            else
                val = 0;
            end
        end
        function val = entrega_s_out(this)
            if this.EnServicio
                val = this.S2;
            else
                val = 0;
            end
        end
        
        function val = entrega_flag_opf(this)
            % flag opf en caso de que línea esté compensada. En este caso,
            % OPF determina el estado de la compensación (abierta/cerrada)
            val = this.OPF;
        end
        function borra_resultados_fp(this)
            this.id_fp = 0;
            this.I1 = 0;
            this.I2 = 0;
            this.ThetaI1 = 0;
            this.ThetaI2 = 0;
            this.S1 = 0;
            this.S2 = 0;
            this.Perdidas = 0;
        end
        
        function inserta_tipo_conductor(this, tipo)
            this.TipoConductor = tipo;
        end
        
        function tipo = entrega_tipo_conductor(this)
            tipo = this.TipoConductor;
        end
        
        function inserta_costo_conductor(this, val)
            this.Costo_conductor = val;
        end
        
        function val = entrega_costo_conductor(this)
            val = this.Costo_conductor;
        end
        
        function inserta_costo_torre(this, val)
            this.Costo_torre = val;
        end
                
        function val = entrega_costo_torre(this)
            val = this.Costo_torre;
        end
        
        function inserta_costo_compensacion_serie(this, val)
            this.Costo_compensacion_serie = val;
        end

        function val = entrega_costo_compensacion_serie(this)
            val = this.Costo_compensacion_serie;
        end

        function inserta_costo_servidumbre(this, val)
            this.Costo_servidumbre = val;
        end

        function val = entrega_costo_servidumbre(this)
            val = this.Costo_servidumbre;
        end
        
        function inserta_row(this, val)
            this.ROW = val;
        end
        
        function val = entrega_row(this)
            val = this.ROW;
        end
        
        function inserta_diametro_conductor(this, val)
            this.Diametro_conductor = val;
        end
        
        function val = entrega_diametro_conductor(this)
            val = this.Diametro_conductor;
        end
        
        function inserta_indice_paralelo(this, indice)
            this.IndiceParalelo = indice;
        end
        
        function indice = entrega_indice_paralelo(this)
            indice = this.IndiceParalelo;
        end
        
        function inserta_anio_construccion(this, val)
            this.AnioConstruccion = val;
        end
        
        function val = entrega_anio_construccion(this)
            val = this.AnioConstruccion;
        end
                
        function val = entrega_costo_inversion(this)
            val = this.Costo_conductor + this.Costo_torre + this.Costo_compensacion_serie + this.Costo_servidumbre;
        end
                
        function inserta_vida_util(this, val)
            this.VidaUtil = val;
        end
        
        function val = entrega_vida_util(this)
            val = this.VidaUtil;
        end
        
        function imprime_parametros_pu(this, varargin)
            %varargin{1} indica si se imprime header o no
            %varargin{2} indica prefijo (por ahora, E para existente y P proyectada)
            header = false;
            existe_prefijo = false;
            prefijo = '';
            if nargin > 1
                header = varargin{1};
                if nargin > 2
                    existe_prefijo = true;
                    prefijo = varargin{2};
                end
            end
            prot = cProtocolo.getInstance;
            if header
                if existe_prefijo
                    texto = sprintf('%-5s %-25s %-15s %-15s %-5s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s', 'Est', 'Nombre', 'Bus1', 'Bus2', 'Par', 'Km', 'Sr', 'Sth', 'SIL', 'rpu', 'xpu', 'cpu', 'gpu', 'bpu*', 'porc. comp');
                else
                    texto = sprintf('%-25s %-15s %-15s %-5s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s', 'Nombre', 'Bus1', 'Bus2', 'Par', 'Km', 'Sr', 'Sth', 'SIL', 'rpu', 'xpu', 'cpu', 'gpu', 'bpu*', 'porc. comp');
                end
                prot.imprime_texto(texto);
            end
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            zbase = this.SE1.entrega_vbase()^2/sbase;
            
            nombre = this.entrega_nombre();
            bus1 = this.SE1.entrega_nombre();
            bus2 = this.SE2.entrega_nombre();
            rpu = this.Rpul*this.Largo/zbase;
            xpu = this.Xpul*this.Largo/zbase*(1-this.PorcentajeCompensacion);
            cpu = this.Cpul*this.Largo*zbase;
            gpu = this.Gpul*this.Largo*zbase;
            bpu = this.Largo * this.Cpul * 2 *pi *50 / 1000000 * zbase;
            vn = this.SE1.entrega_vn();
            zc = sqrt(this.Xpul/(this.Cpul * 2 *pi *50 / 1000000));
            sil = round(vn^2/zc);
            if existe_prefijo
                texto = sprintf('%-5s %-25s %-15s %-15s %-5s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s', ...
                    prefijo, nombre, bus1, bus2, num2str(this.IndiceParalelo), num2str(this.Largo), num2str(round(this.Sr)), num2str(round(this.Sth)), ...
                    num2str(sil), num2str(rpu), num2str(xpu), num2str(cpu), num2str(gpu), num2str(bpu), num2str(this.PorcentajeCompensacion));
            else
                texto = sprintf('%-25s %-15s %-15s %-5s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s', ...
                    nombre, bus1, bus2, num2str(this.IndiceParalelo), num2str(this.Largo), num2str(round(this.Sr)), num2str(round(this.Sth)), ...
                    num2str(sil), num2str(rpu), num2str(xpu), num2str(cpu), num2str(gpu), num2str(bpu), num2str(this.PorcentajeCompensacion));
            end
            prot.imprime_texto(texto);
        end
        function imprime_parametros_fisicos(this, varargin)
            %varargin{1} indica si se imprime header o no
            %varargin{2} indica prefijo (por ahora, E para existente y P proyectada)
            header = false;
            existe_prefijo = false;
            prefijo = '';
            if nargin > 1
                header = varargin{1};
                if nargin > 2
                    existe_prefijo = true;
                    prefijo = varargin{2};
                end
            end
            prot = cProtocolo.getInstance;
            if header
                if existe_prefijo
                    texto = sprintf('%-5s %-25s %-7s %-15s %-15s %-5s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s', 'Est', 'Nombre', 'Texto', 'Bus1', 'Bus2', 'Par', 'Km', 'Sr MW', 'Sth MW', 'SIL MW', 'r Ohm/km', 'x Ohm/km', 'c uF/km', 'g mS/km', 'b* uS/km', 'porc. comp');                    
                else
                    texto = sprintf('%-25s %-7s %-15s %-15s %-5s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s', 'Nombre', 'Texto', 'Bus1', 'Bus2', 'Par', 'Km', 'Sr MW', 'Sth MW', 'SIL MW', 'r Ohm/km', 'x Ohm/km', 'c uF/km', 'g mS/km', 'b* uS/km', 'porc. comp');
                end
                prot.imprime_texto(texto);
            end
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            zbase = this.SE1.entrega_vbase()^2/sbase;
            
            nombre = this.entrega_nombre();
            bus1 = this.SE1.entrega_nombre();
            bus2 = this.SE2.entrega_nombre();
            rpul = this.Rpul;
            xpul = this.Xpul*(1-this.PorcentajeCompensacion);
            cpul = this.Cpul;
            gpul = this.Gpul;
            bpul = this.Cpul * 2 *pi *50;
            vn = this.SE1.entrega_vn();
            zc = sqrt(this.Xpul/(this.Cpul * 2 *pi *50 / 1000000));
            sil = round(vn^2/zc);
            texto = this.Texto;
            if existe_prefijo
                texto = sprintf('%-5s %-25s %-7s %-15s %-15s %-5s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s', ...
                    prefijo, nombre, texto, bus1, bus2, num2str(this.IndiceParalelo), num2str(this.Largo), num2str(round(this.Sr,4)), num2str(round(this.Sth)), ...
                    num2str(sil), num2str(rpul), num2str(xpul), num2str(cpul), num2str(gpul), num2str(bpul), num2str(this.PorcentajeCompensacion));
                
            else
                texto = sprintf('%-25s %-7s %-15s %-15s %-5s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s', ...
                    nombre, texto, bus1, bus2, num2str(this.IndiceParalelo), num2str(this.Largo), num2str(round(this.Sr,4)), num2str(round(this.Sth)), ...
                    num2str(sil), num2str(rpul), num2str(xpul), num2str(cpul), num2str(gpul), num2str(bpul), num2str(this.PorcentajeCompensacion));
            end
            prot.imprime_texto(texto);
        end
        
        function inserta_compensacion_serie(this, porcentaje)
            if porcentaje < 0 || porcentaje > 0.7
                error = MException('cLinea:inserta_compensacion_serie','compensación tiene que ser entre 0 y 0.7');
                throw(error)
            end
            this.PorcentajeCompensacion = porcentaje;
            this.EstadoCompensacion = 1; % por defecto compensación está operativa
        end
        
        function val = entrega_compensacion_serie(this)
            val = this.PorcentajeCompensacion;
        end
        
        function inserta_id_estado_planificacion(this, val)
            this.IdEstadoPlanificacion = val;
        end
        
        function val = entrega_id_estado_planificacion(this)
            val = this.IdEstadoPlanificacion;
        end
        
        function inserta_id_corredor(this, val)
            this.IdCorredor = val;
        end
        
        function val = entrega_id_corredor(this)
            val = this.IdCorredor;
        end

        function inserta_etapa_entrada(this, escenario, val)
            this.EtapaEntrada(escenario) = val;
        end
        
        function val = entrega_etapa_entrada(this, escenario)
            if length(this.EtapaEntrada) >= escenario
                val = this.EtapaEntrada(escenario);
            elseif this.EtapaEntrada == 0
                val = 0;
            else
                error = MException('cLinea:entrega_etapa_entrada','Error en datos de entrada');
                throw(error)
            end
        end
        
        function inserta_indice_decision_expansion(this, val)
            this.IndiceDecisionExpansion = val;
        end
        
        function val = entrega_indice_decision_expansion(this)
            val = this.IndiceDecisionExpansion;
        end

        function inicializa_varopt_operacion_milp_dc(this, cant_escenarios, cant_etapas)
            this.IndiceVarOptP = zeros(cant_escenarios, cant_etapas);
        end

        function inserta_varopt_operacion(this, unidad, escenario, etapa, valor)
            switch unidad
                case 'P'
                    this.IndiceVarOptP(escenario, etapa) = valor;
                otherwise
                	error = MException('cLinea:inserta_varopt_operacion','unidad no implementada');
                    throw(error)
            end
        end
        
        function val = entrega_varopt_operacion(this, unidad, escenario, etapa)
            switch unidad
                case 'P'
                    val = this.IndiceVarOptP(escenario, etapa);
                otherwise
                	error = MException('cLinea:entrega_varopt_operacion','unidad no implementada');
                    throw(error)
            end
        end        
    end
end