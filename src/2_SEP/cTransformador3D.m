classdef cTransformador3D < cElementoRed
        % clase que representa los transformadores
    properties
        pGPar = cParametrosSistemaElectricoPotencia.empty;
        SE1     % AT
		SE2     % MT
        SE3     % BT
		
        Sr1
        Sr2
        Sr3
        Vr1
		Vr2
        Vr3

        Grupo1_AT  %YY, DY11, etc.
        Grupo2_AT
        DFase_AT
        
        Grupo1_MT  %YY, DY11, etc.
        Grupo2_MT
        DFase_MT

        Grupo1_BT  %YY, DY11, etc.
        Grupo2_BT
        DFase_BT
 
        TieneTap  % 0 índices indican el lado de los taps: [1 3] significa que tiene un tap en AT y otro en BT
        TapMin  % vector con el tap mínimo por cada uno de los tap de acuerdo a los índices indicados en TieneTap
		TapMax  % idem
        TapNom  % posición nominal
        DuTap  % vector con variación del voltaje en porcentaje del voltaje nominal del lado correspondiente
        LadoTap % vector con los lados: 1 para AT, 2 para BT
        
        uk_12   % AT-MT 
        uk_13   % AT-BT
        uk_23   % MT-BT
        
        Pcu_12   % pérdidas del cobre en kW
        Pcu_13   % pérdidas del cobre en kW
        Pcu_23   % pérdidas del cobre en kW
        I0_12   % corriente en vacío número de veces Inom
        I0_13   % corriente en vacío número de veces Inom
        I0_23   % corriente en vacío número de veces Inom
        P0_12   % pérdidas en vacío en kW
        P0_13   % pérdidas en vacío en kW
        P0_23   % pérdidas en vacío en kW

        ControlaTension = false
        VoltajeObjetivo = 0
        SERegulada = cSubestacion.empty
        SENoRegulada = cSubestacion.empty
        
        % Propiedades calculadas
		% Vr1 y Vr2 contienen los voltajes (valor absoluto)en el primario,
		% secundario y terciario respectivamente
        Vr1
		Vr2
        Vr3
        
        % Relación de transformación compleja, que depende del tipo de conexión
        RelTrans 
        
        % Ángulo para transformadores desfasadores. No confundir con ángulo de la relación de transformación
        AngDesfase  
        
        % parámetros operacionales en/para flujo de potencia
        TapActual
        
        % Resultado flujo de potencia
        id_fp = 0
        I1
        I2
        ThetaI1
        ThetaI2
        S1
        S2
        Perdidas        
        
        % parámetros operacionales en/para flujo de potencia
        PasoActual
    end
    
    methods
        function this = cTransformador3D()
            this.TipoElementoRed = 'ElementoSerie';
            this.pGPar = cParametrosSistemaElectricoPotencia();
        end

        function valor = regula_tension(this)
            valor = this.RegulaTension();
        end
        
        function se = entrega_subestacion_regulada(this)
            se = this.SubestacionRegulada;
        end
        
        function se = entrega_subestacion_no_regulada(this)
            se = this.SubestacionNoRegulada;
        end
        
        function conexion1 = entrega_conexion_1(this)
            conexion1 = this.SE1;
        end
        
        function conexion2 = entrega_conexion_2(this)
            conexion2 = this.SE2;
        end
        
        function rel = entrega_relacion_transformacion(this)
            rel = this.RelacionTransformacion;
        end
        
        function inserta_paso_actual(this, val)
            this.PasoActual = val;
        end
        
        function val = entrega_paso_actual(this)
            val = this.PasoActual;
        end
        
        function val = entrega_cantidad_devanados(this)
            val = this.CantidadDevanados;
        end
        function [y11, y12, y21, y22] = entrega_cuadripolo(this, varargin)
            % TODO: Esto tiene que estar implementado en los distintos
            % devanados!
            if nargin > 1
                factor = varargin{1};
            else
                factor = 1;
            end
            
            % primero valores base y luego considera tap
            
            x_12 = this.uk_12 * this.Vr1^2 / this.Sr2;
            x_13 = this.uk_13 * this.Vr1^2 / this.Sr3;
            x_23 = this.uk_23 * this.Vr1^2 / this.Sr3;
            r_12 = this.Pcu_12 * (this.Vr1 / this.Sr2)^2;  % TODO: falta verificar el lado de Vr y Sr!!!
            r_13 = this.Pcu_13 * (this.Vr1 / this.Sr3)^2;  % TODO: falta verificar el lado de Vr y Sr!!!
            r_23 = this.Pcu_23 * (this.Vr1 / this.Sr3)^2;  % TODO: falta verificar el lado de Vr y Sr!!!
            
            zk_12 = complex(r_12, x_12);
            zk_13 = complex(r_13, x_13);
            zk_23 = complex(r_23, x_23);
            
            g_12 = this.P0_12 / this.Vr1^2 / 1000; %verificar unidades!
            g_13 = this.P0_13 / this.Vr1^2 / 1000; %verificar unidades!
            g_23 = this.P0_23 / this.Vr1^2 / 1000; %verificar unidades!
            
            b_12 = sqrt(3)* this.I0_12/ this.Vr1;  %verificar unidades
            b_13 = sqrt(3)* this.I0_12/ this.Vr1;  %verificar unidades
            b_23 = sqrt(3)* this.I0_12/ this.Vr1;  %verificar unidades
            
            y0_12 = complex(0.5*g_12,0.5*b_12);
            y0_13 = complex(0.5*g_13,0.5*b_13);
            y0_23 = complex(0.5*g_23,0.5*b_23);
            
            rel_trans = this.RelTrans;

            if this.TieneTap > 0
                %TODO: Falta terminar... código abajo copiado del
                %transformador 2D
                %Vr = [this.Vr1;this.Vr2];
                %factor_interno = Vr(this.LadoTap)/this.Vr1;
                %du_real = (this.TapActual - this.TapNom).*this.DuTap.*factor_interno; % todo al lado de alta tensión del transformador
                %%ángulos entre el lado del tap y el lado de alta tensión
                
                %angulo_desfase = angle(this.RelTrans);
                %angulo = angulo_desfase(this.LadoTap);
                %du = complex(du_real.*cos(angulo), du_real.*sin(angulo));
                
                % % se separan los taps que regulan los lados primarios y
                % % secundarios
                %du_lado = zeros(2,1);
                %du_lado(1) = sum(du(this.LadoTap == 1));
                %du_lado(2) = sum(du(this.LadoTap == 2));
                %zk = zk*abs(1+du_lado(1))^2;
                %y0 = y0/abs(1+du_lado(1))^2;
                %v1_a_v2 = this.Vr1*(1+du_lado(1))/(this.Vr2*(1+du_lado(2)));
            end
            
            y11 =  (1/zk + y0)/factor;
            y12 =  -1/zk*rel_trans/factor;
            y21 =  -1/zk*conj(rel_trans)/factor;
            y22 =  (1/zk + y0)*abs(rel_trans)^2/factor;
        end
    end
end

    