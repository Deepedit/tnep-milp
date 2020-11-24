classdef cTransformador2D < cElementoRed
        % clase que representa los transformadores
    properties (Access = private)
        % Propiedades básicas        
        SE1  % siempre alta tensión
		SE2  % siempre baja tensión
        Sr                    %MVA
        SrN1 = 0              %MVA. Límite post-falla
        Grupo1  %YY, DY11, etc.
        Grupo2
        DFase
        IdCorredor = 0
        IndiceParalelo = 0
        
        CantidadTaps  % 0 si no tiene tap, 1 si tiene un tap y 2 si tiene 2 taps
        LadoTap % vector con los lados: 1 para AT, 2 para BT
        TapMin  % vector con el tap mínimo (en entero) por cada uno de los tap 
		TapMax  % idem
        TapNom  % posición nominal
        DuTap  % vector con variación del voltaje en porcentaje del voltaje nominal del lado correspondiente
        
        uk   % voltaje cortocircuito en porcentaje 
        Pcu   % pérdidas del cobre en kW
        I0   % corriente en vacío número de veces Inom
        P0   % pérdidas en vacío en kW
        
        % Propiedades calculadas
		% Vr1 y Vr2 contienen los voltajes (valor absoluto)en el primario y
		% secundario respectivamente
        Vr1
		Vr2
        
        % Relación de transformación compleja, que depende del tipo de conexión
        RelTrans 
        
        % Ángulo para transformadores desfasadores. No confundir con ángulo de la relación de transformación
        AngDesfase

        ControlaTension = false
        IdTapRegulador  % indica si el tap controlador es el primero o el segundo
        VoltajeObjetivo = 0 
        SERegulada = cSubestacion.empty
        SENoRegulada = cSubestacion.empty

        % Parámetros económicos
        Costo_transformador %mio. USD. Incluye costo de conexión de los transformadores. No incluye costos de subestaciones
        AnioConstruccion % ej: 2005
        VidaUtil
        
        EtapaEntrada = 0 % es para elementos proyectados (ej. 3). Sólo para trafos en construcción 
        TipoTrafo = -1
        
        %ControlaTensionFP indica el estado actual del control de tensión del transformador
        %regulador. 
        ControlaTensionFP = false;
        
        %Flag OPF indica que elemento es considerado para el OPF (e.g. Tap)
        OPF = false
        
		%Indice para resultados y optimizacion de planificación
        % Ojo! No para despacho económico, ya que estos se encuentran en
        % sistema modal
        % Escenarios contiene:
        % IndiceResultados = 0;
        IndiceVarOptP = 0;
        IndiceEqFlujosAngulos = []
        
        % Indice de estado para planificación de la expansion
        IdEstadoPlanificacion = 0
        
        IndiceDecisionExpansion = [] % indica el índice del corredor o bus utilizado en expansión de MCMC
        IndiceDecisionExpansionSecundaria = [] % para trafos VU, ya que estos no se optimizan directamente
        
        % Resultado flujo de potencia
        % Tap actual está en esta parte por si el flujo de potencia
        % modifica el tap
        TapActual
        id_fp = 0
        I1
        I2
        ThetaI1
        ThetaI2
        S1
        S2
        Perdidas
        
        NivelDebug = 2;
    end
    
    methods
        function this = cTransformador2D()
            this.TipoElementoRed = 'ElementoSerie';
        end

        function valor = controla_tension(this)
            valor = this.ControlaTension();
        end

        function inserta_indice_paralelo(this, indice)
            this.IndiceParalelo = indice;
        end
        
        function inserta_voltaje_objetivo(this, val)
            this.ControlaTension = true;
            this.VoltajeObjetivo = val;
        end
        
        function valor = entrega_voltaje_objetivo(this)
            if this.ControlaTension
                valor = this.VoltajeObjetivo;
            else
                error = MException('cTransformador2D:entrega_voltaje_objetivo','transformador no controla tension');
                throw(error)
            end
        end

        function valor = entrega_voltaje_objetivo_pu(this)
            if this.ControlaTension
                vn = this.SERegulada.entrega_vn();
                valor = this.VoltajeObjetivo/vn;
            else
                error = MException('cTransformador2D:entrega_voltaje_objetivo','transformador no controla tension');
                throw(error)
            end
        end
        
        function inserta_id_tap_controlador(this, id)
            this.IdTapRegulador = id;
        end
        
        function id = entrega_id_tap_controlador(this)
            id = this.IdTapRegulador;
        end
            
        function inserta_indice_se_regulada(this, idx)
            if idx == 1
                this.SERegulada = this.SE1;
                this.SENoRegulada = this.SE2;
            else
                this.SERegulada = this.SE2;
                this.SENoRegulada = this.SE1;
            end
        end
        
        function se = entrega_subestacion_regulada(this)
            se = this.SERegulada;
        end
        
        function se = entrega_subestacion_no_regulada(this)
            se = this.SENoRegulada;
        end
                
        function se1 = entrega_se1(this)
            se1 = this.SE1;
        end
                
        function se2 = entrega_se2(this)
            se2 = this.SE2;
        end

        function vr = entrega_vr1(this)
            vr = this.Vr1;
        end
        
        function vr = entrega_vr2(this)
            vr = this.Vr2;
        end
        
        function el = entrega_P0(this)
            el = this.P0;
        end
        
        function el = entrega_I0(this)
            el = this.I0;
        end
        
        function el = entrega_Pcu(this)
            el = this.Pcu;
        end
        
        function el = entrega_uk(this)
            el = this.uk;
        end
        
        function el = entrega_TapMin(this)
            el = this.TapMin;
        end
        
        function el = entrega_TapMax(this)
            el = this.TapMax;
        end
        
        function el = entrega_DuTap(this)
            el = this.DuTap;
        end
        
        function el = entrega_LadoTap(this)
            el = this.LadoTap;
        end
        
        function el = entrega_TapActual(this)
            el = this.TapActual;
        end
        
        function el = entrega_TapNom(this)
            el = this.TapNom;
        end
        
        function el = entrega_cantidad_de_taps(this)
            el = this.CantidadTaps;
        end
        
        function [subestacion1, subestacion2] = entrega_subestaciones(this)
            subestacion1 = this.SE1;
            subestacion2 = this.SE2;
        end

        function val = entrega_ang_desfase(this)
            val = this.AngDesfase;
        end
        
        function val = entrega_ang_desfase_grad(this)
            val = this.AngDesfase/pi*180;
        end
        
        function inserta_tap_actual(this, val, varargin)
            if nargin > 2
                nrtap = varargin{1};
            else
                nrtap = 1;
            end
            this.TapActual(nrtap) = val;
        end
        
        function val = entrega_tap_actual(this, varargin)
            % varargin contiene el nro de tap. Si no se entrega nada, se
            % devuelve el paso actual del primer tap
            if nargin > 1
                nrtap = varargin{1};
            else
                nrtap = 1;
            end
            val = this.TapActual(nrtap);
        end    
        
        function val = entrega_tap_actual_regulador(this)
            val = this.TapActual(this.IdTapRegulador);
        end
        
        
        function val = entrega_id_tap_regulador(this)
            val = this.IdTapRegulador;
        end
        
        function inserta_tap_actual_regulador(this, val)
            this.TapActual(this.IdTapRegulador) = val;
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
        
        function [y11, y12, y21, y22] = entrega_cuadripolo(this, varargin)
            % varargin entrega el valor del tap regulador, en caso de que se indique
            tap_actual = this.TapActual;
            if nargin > 1
                valor_tap_regulador = varargin{1};
                tap_actual(this.IdTapRegulador) = valor_tap_regulador;
            end
            
            vbase = this.SE1.entrega_vbase();
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            zbase = vbase^2/sbase;
            
            % primero valores base convertidos a pu y luego consideran los
            % taps
            r = this.Pcu*(this.Vr1/this.Sr)^2/zbase;
            x = this.uk *this.Vr1^2/this.Sr/zbase;
            zk = complex(r, x);
            
            g = this.P0 / this.Vr1^2 / 1000 * zbase; 
            b = sqrt(3)* this.I0 / this.Vr1 * zbase;
            y0 = complex(0.5*g,0.5*b);

            if this.CantidadTaps == 0
                y11 =  (1/zk + y0);
                y12 =  -1/zk;
                y21 =  -1/zk;
                y22 =  (1/zk + y0);
            else
                % calcula diferencia de voltaje en el primario (dup) y
                % secundario (dus). Para ello, se calcula la diferencia de voltaje de cada uno de los taps y luego se asignan al lado correspondiente

                du_taps = (tap_actual - this.TapNom).*this.DuTap;
                angulo_taps = zeros(this.CantidadTaps,1);
                for i = 1:this.CantidadTaps
                    if this.LadoTap(i) == 2
                        angulo_taps(i) = angle(this.RelTrans);
                    end
                end
                du_taps = du_taps.*complex(cos(angulo_taps), sin(angulo_taps));
                
                % calcula diferencia de voltaje en el primario y secundario
                du_p = sum(du_taps(this.LadoTap == 1));
                du_s = sum(du_taps(this.LadoTap == 2));
                
                % utilizando la convensión: 
                % tp = (1+du_p)/|1+du_p|^2 para el primario y
                % ts = (1+du_s)/|1+du_s|^2 para el secundario
                % se tiene que la matriz de admitancia es:
                %
                % | (1/zk + y0)*|tp|^2   -1/zk(tp*)(ts)
                % | -1/zk (tp)(ts*)      (1/zk + yo)|ts|^2
                
                tp = (1+du_p)/abs(1+du_p)^2;
                ts = (1+du_s)/abs(1+du_s)^2;
                
                y11 =  (1/zk + y0)*abs(tp)^2;
                y12 =  -1/zk*conj(tp)*ts;
                y21 =  -1/zk*tp*conj(ts);
                y22 =  (1/zk + y0)/abs(ts)^2;
            end
        end

        function val = entrega_reactancia_pu(this)
            vbase = this.SE1.entrega_vbase();
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            zbase = vbase^2/sbase;

            val = this.uk *this.Vr1^2/this.Sr/zbase;
        end

        function val = entrega_reactancia(this)
            val = this.uk *this.Vr1^2/this.Sr;
        end
        
        function val = entrega_resistencia_pu(this)
            vbase = this.SE1.entrega_vbase();
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            zbase = vbase^2/sbase;

            val = this.Pcu*(this.Vr1/this.Sr)^2/zbase;
        end
        
        function val = entrega_susceptancia_pu(this)
            vbase = this.SE1.entrega_vbase();
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            zbase = vbase^2/sbase;
            val = sqrt(3)* this.I0 / this.Vr1 * zbase;  
        end
        
        function t_tap = entrega_t_tap_regulador_abs(this)
            tap_actual = this.TapActual(this.IdTapRegulador);
            tap_nom = this.TapNom(this.IdTapRegulador);
            du_tap = this.DuTap(this.IdTapRegulador);
            t_tap = 1 + (tap_actual - tap_nom)*du_tap;
        end
        
        function t_tap = entrega_t_tap_secundario(this, varargin)
            if this.CantidadTaps > 0
                du_taps = (tap_actual - this.TapNom).*this.DuTap;
                % calcula diferencia de voltaje en el primario y secundario
                du_s = sum(du_taps(this.LadoTap == 2));
                
                t_tap = 1+du_s;
            else
                t_tap = 1;
            end
        end

        function t_tap = entrega_t_tap_primario(this, varargin)
            if this.CantidadTaps > 0
                du_taps = (tap_actual - this.TapNom).*this.DuTap;
                % calcula diferencia de voltaje en el primario y secundario
                du_p = sum(du_taps(this.LadoTap == 1));
                
                t_tap = 1+du_p;
            else
                t_tap = 1;
            end
        end
            
        function inserta_resultados_fp_en_pu(this, id_fp, I1, I2, ThetaI1, ThetaI2, S1, S2, Perdidas)
            %se tiene que convertir todo a valores nominales
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
            % valores reales
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
        
        function val = entrega_nombre_se(this, nro)
            if nro == 1
                val = this.SE1.entrega_nombre();
            else
                val = this.SE2.entrega_nombre();
            end
        end
        
        function inserta_subestacion(this, subestacion, indice)
            if indice == 1
                this.SE1 = subestacion;
                this.Vr1 = subestacion.entrega_vn();
            elseif indice == 2
                this.SE2 = subestacion;
                this.Vr2 = subestacion.entrega_vn();
            else
                error = MException('cTrafo2D:inserta_subestacion','nro tiene que ser cero o uno');
                throw(error)
            end
        end
        
        function inserta_sr(this, sr)
            this.Sr = sr;
        end
        
        function val = entrega_sr(this)
            val = this.Sr;
        end
        
        function inserta_sr_n1(this, sr)
            this.SrN1 = sr;
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
        
        function inserta_tipo_conexion(this, grupo_primario, grupo_secundario, desfase)
            this.Grupo1 = grupo_primario;
            this.Grupo2 = grupo_secundario;
            grupo = strcat(grupo_primario, grupo_secundario, num2str(desfase));
            dv_base = this.Vr1/this.Vr2;
            angulo = desfase*pi/6;
            factor_conv = 1;
            switch grupo
                case 'Yy0'
                    % nada, ya que corresponde a factor de conversión base
                case 'Dy5'
                    factor_conv = 1/sqrt(3);
                case 'Yd5'
                    factor_conv = sqrt(3);
                case 'Yz5'
                    factor_conv = 2/aqrt(3);
                otherwise
                    error = MException('cTrafo2D:inserta_tipo_conexion','tipo conexion incorrecta o no implementada');
                    throw(error)
            end
            this.RelTrans = dv_base*factor_conv*complex(cos(angulo), sin(angulo));
        end
        
        function inserta_cantidad_de_taps(this, val)
            this.CantidadTaps = val;
        end
        
        function inserta_tap_min(this, val, varargin)
            if nargin > 2
                nrtap = varargin{1};
            else
                nrtap = 1;
            end
            this.TapMin(nrtap) = val;
        end

        function inserta_tap_max(this, val, varargin)
            if nargin > 2
                nrtap = varargin{1};
            else
                nrtap = 1;
            end
            this.TapMax(nrtap) = val;
        end
        
        function val = entrega_tap_max(this, varargin)
            % varargin indica el nro de tap. Si no se indica, entrega el
            % tap mínimo del tap regulador (si tiene). Si no tiene tap
            % regulador, entrega el primer tap
            if nargin > 1
                nrtap = varargin{1};
            else
                if this.ControlaTension
                    nrtap = this.IdTapRegulador;
                else
                    nrtap = 1;
                end
            end
            val = this.TapMax(nrtap);
        end            

        function val = entrega_tap_max_regulador(this)
            val = this.TapMax(this.IdTapRegulador);
        end            

        function val = entrega_tap_min_regulador(this)
            val = this.TapMin(this.IdTapRegulador);
        end            
        
        function val = entrega_tap_min(this, varargin)
            % varargin indica el nro de tap. Si no se indica, entrega el
            % tap mínimo del tap regulador (si tiene). Si no tiene tap
            % regulador, entrega el primer tap
            if nargin > 1
                nrtap = varargin{1};
            else
                if this.ControlaTension
                    nrtap = this.IdTapRegulador;
                else
                    nrtap = 1;
                end
            end
            val = this.TapMin(nrtap);
        end

        function inserta_tap_nom(this, val, varargin)
            if nargin > 2
                nrtap = varargin{1};
            else
                nrtap = 1;
            end
            this.TapNom(nrtap) = val;
        end

        function inserta_du_tap(this, val, varargin)
            if nargin > 2
                nrtap = varargin{1};
            else
                nrtap = 1;
            end
            this.DuTap(nrtap) = val;
        end
        
        function inserta_lado_tap(this, val, varargin)
            if nargin > 2
                nrtap = varargin{1};
            else
                nrtap = 1;
            end
            this.LadoTap(nrtap) = val;
        end
        
        function inserta_pcu(this, val)
            this.Pcu = val;
        end

        function inserta_uk(this, val)
            this.uk = val;
        end
        
        function inserta_i0(this, val)
            this.I0 = val;
        end
        
        function inserta_p0(this, val)
            this.P0 = val;
        end
        
        function du_a_ds = entrega_du_a_ds(this)
        	du_taps = (this.TapActual - this.TapNom).*this.DuTap;
            angulo_taps = zeros(this.CantidadTaps,1);
            for i = 1:this.CantidadTaps
                if this.LadoTap(i) == 2
                    angulo_taps(i) = angle(this.RelTrans);
                end
            end
            du_taps = du_taps.*complex(cos(angulo_taps), sin(angulo_taps));

            % calcula diferencia de voltaje en el primario y secundario
            du_p = 1 + sum(du_taps(this.LadoTap == 1));
            du_s = 1 + sum(du_taps(this.LadoTap == 2));
            
            id_tap_controlador = this.IdTapRegulador;
            du_tap_regulador = this.DuTap(id_tap_controlador);
            if this.SERegulada == this.SE1
                % tap regulador regula lado de alta tensión
                du_a_ds = du_tap_regulador/du_s;
            else
                % tal regulador regula lado de baja tensión
                du_a_ds = -1*du_tap_regulador/(du_s)^2*du_p;
            end
        end
        
        function inserta_controla_tension_fp(this, val)
            if val
                if ~this.ControlaTension && ~this.OPF
                    error = MException('cTransformador2D:inserta_controla_tension_fp','transformador no controla tension y flag OPF no está activada');
                    throw(error)
                end
                % se inicializan las variables para el control de tensión
                this.ControlaTensionFP = true;
            end
        end
        
        function val = entrega_flag_opf(this)
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
        
        function lado = entrega_nombre_lado_controlado(this)
            if this.ControlaTension
                if this.SERegulada == this.SE1
                    lado = 'primario';
                else
                    lado = 'secundario';
                end
            else
                error = MException('cTransformador2D:entrega_nombre_lado_controlado','transformador no controla tension');
                throw(error)
            end
        end
        
        function tap = entrega_tap_dado_t(this, id_tap, tact)
            tap_nom = this.TapNom(id_tap);
            du_tap = this.DuTap(id_tap);
            tap = (tact-1)/du_tap+tap_nom;
        end
        
        function trafo = crea_copia(this)
            % crea una copia pero sólo elementos que se
            % pueden copiar o que vale la pena copiar. El único puntero que
            % se copia es la subestación, la que tiene que ser ajustada en
            % caso de ser necesario
            trafo = cTransformador2D();
            trafo.Nombre = this.Nombre;
            trafo.Id = this.Id;
            trafo.Grupo1 = this.Grupo1;
            trafo.Grupo2 = this.Grupo2;
            trafo.DFase = this.DFase;
            trafo.IndiceParalelo = this.IndiceParalelo;
            trafo.EnServicio = this.EnServicio;
            trafo.CantidadTaps = this.CantidadTaps;
            trafo.LadoTap = this.LadoTap;
            trafo.TapMin = this.TapMin;
            trafo.TapMax = this.TapMax;
            trafo.TapNom = this.TapNom;
            trafo.DuTap = this.DuTap;            
            trafo.Sr = this.Sr;
            trafo.uk = this.uk;
            trafo.Pcu = this.Pcu;
            trafo.I0 = this.I0;
            trafo.Vr1 = this.Vr1;
            trafo.Vr2 = this.Vr2;
            trafo.RelTrans = this.RelTrans;
            trafo.AngDesfase = this.AngDesfase;
            trafo.ControlaTension = this.ControlaTension;
            trafo.IdTapRegulador = this.IdTapRegulador;
            trafo.VoltajeObjetivo = this.VoltajeObjetivo;
            trafo.SERegulada = this.SERegulada;
            trafo.SENoRegulada = this.SENoRegulada;
            trafo.ControlaTensionFP = this.ControlaTensionFP;
            trafo.OPF = this.OPF;
            trafo.IdCorredor = this.IdCorredor;
            
            trafo.Costo_transformador = this.Costo_transformador;
            trafo.SE1 = this.SE1;
            trafo.SE2 = this.SE2;
            trafo.AnioConstruccion = this.AnioConstruccion;
            trafo.VidaUtil = this.VidaUtil;
            trafo.IdEstadoPlanificacion = this.IdEstadoPlanificacion;
            trafo.IdAdmProyectos = this.IdAdmProyectos;
            trafo.Existente = this.Existente;
            trafo.FlagObservacion = this.FlagObservacion;
            trafo.IndiceDecisionExpansion = this.IndiceDecisionExpansion;
        end

        function inserta_costo_transformador(this, val)
            this.Costo_transformador = val;
        end
        
        function val = entrega_costo_transformador(this)
            val = this.Costo_transformador;
        end
                
        function inserta_vida_util(this, val)
            this.VidaUtil = val;
        end

        function val = entrega_vida_util(this)
            val = this.VidaUtil;
        end

        function val = entrega_costo_inversion(this)
            val = this.Costo_transformador;
        end 
        
        function val = entrega_ubicacion(this)
            val = this.SE1.entrega_ubicacion();
        end

        function inserta_tipo_trafo(this, tipo)
            this.TipoTrafo = tipo;
        end
        
        function tipo = entrega_tipo_trafo(this)
            tipo = this.TipoTrafo;
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
                    texto = sprintf('%-5s %-25s %-7s %-15s %-15s %-5s %-10s %-10s', 'Est', 'Nombre', 'Texto', 'Bus1', 'Bus2', 'Par', 'Sr MW', 'x Ohm');
                else
                    texto = sprintf('%-25s %-7s %-15s %-15s %-5s %-10s %-10s', 'Nombre', 'Texto', 'Bus1', 'Bus2', 'Par', 'Sr MW', 'x Ohm');
                end
                prot.imprime_texto(texto);
            end
            
            nombre = this.entrega_nombre();
            bus1 = this.SE1.entrega_nombre();
            bus2 = this.SE2.entrega_nombre();
            x_ohm = this.uk *this.Vr1^2/this.Sr;
            texto = this.Texto;
            if existe_prefijo
                texto = sprintf('%-5s %-25s %-7s %-15s %-15s %-5s %-10s %-10s', ...
                    prefijo, nombre, texto, bus1, bus2, num2str(this.IndiceParalelo), num2str(round(this.Sr)), ...
                    num2str(x_ohm));
                
            else
                texto = sprintf('%-25s %-7s %-15s %-15s %-5s %-10s %-10s', ...
                    nombre, texto, bus1, bus2, num2str(this.IndiceParalelo), num2str(round(this.Sr)), ...
                    num2str(x_ohm));
            end
            prot.imprime_texto(texto);
        end

        function inicializa_varopt_operacion_milp_dc(this, cant_escenarios, cant_etapas)
            this.IndiceVarOptP = zeros(cant_escenarios, cant_etapas);
        end
        
        function inserta_varopt_operacion(this, unidad, escenario, etapa, valor)
            switch unidad
                case 'P'
                    this.IndiceVarOptP(escenario, etapa) = valor;
                otherwise
                	error = MException('cTransformador2D:inserta_varopt_operacion','unidad no implementada');
                    throw(error)
            end
        end
        
        function val = entrega_varopt_operacion(this, unidad, escenario, etapa)
            switch unidad
                case 'P'
                    val = this.IndiceVarOptP(escenario, etapa);
                otherwise
                	error = MException('cTransformador2D:entrega_varopt_operacion','unidad no implementada');
                    throw(error)
            end
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
                error = MException('cTransformador2D:entrega_etapa_entrada','Datos incorrectos. Corregir');
                throw(error)
            end
        end
        
        function agrega_indice_restriccion_flujos_angulos(this, oper, indice)
            this.IndiceEqFlujosAngulos(oper) = indice;
        end
        
        function indice = entrega_indice_restriccion_flujos_angulos(this, oper)
            indice = this.IndiceEqFlujosAngulos(oper);
        end
        
        function inserta_indice_decision_expansion(this, val)
            this.IndiceDecisionExpansion = val;
        end
        
        function val = entrega_indice_decision_expansion(this)
            val = this.IndiceDecisionExpansion;
        end

        function inserta_indice_decision_expansion_secundaria(this, val)
            this.IndiceDecisionExpansion = val;
        end
        
        function val = entrega_indice_decision_expansion_secundaria(this)
            val = this.IndiceDecisionExpansionSecundaria;
        end
        
    end
end