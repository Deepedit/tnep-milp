classdef cFlujoPotencia < handle
    % clase que representa las subestaciones
    properties
        % handle tiene las variables de todos los elementos, incluso los que están fuera de servicio
        pSEP = cSistemaElectricoPotencia.empty
        pAdmSc = cAdministradorEscenarios.empty
        
        handle = struct()
        % Variables de los elementos que estan en servicio en la hora de calculo
        Subestaciones = struct()
        Generadores = struct()
        Lineas = struct()
        Consumos = struct()
        Trafos = struct()
        Condensadores = struct()
        Reactores = struct()
        Baterias = struct()
        num = struct() % todas las cantidades
        
        Adm
        J
        % BusesConRegPorTrafo: contiene lista con Id de buses con transformadores reguladores
        % TrafosReg: contiene lista con Id de trasformadores reguladores
        BusesConRegPorTrafo = [];
        TrafosReg = [];
        
        NivelDebug = 0
        pParFP = cParametrosFlujoPotencia().empty
        Flag
        
        pResEvaluacion = cResultadoEvaluacionSEP.empty
        NivelDetalleResultados = 0
        
        iCantPuntosOperacion = 1
        
        % Variables por el criterio N-1
        ListaLineas
        ListaTrafos
        FlagN1 = 0
        
        Adm_init
        Subestaciones_init
        
        POActual = 0
        iCantSubsistemas = 0 % cantidad de subsistemas de punto de operación actual
        bCantSubsistemasCalculados = false % si al cambio de punto de operación hay líneas/trafos que quedan fuera de servicio, entonces se pone true, para calcular nuevamente la cantidad de subsistemas
        
        iEtapa = 1 % para utilizar con programa de expansión
        iEscenario = 1 % para utilizar con programa de expansión
        VariablesInicializadas = false
        
    end
    methods
        function this = cFlujoPotencia(sep, varargin)
            % varargin contiene administrador de escenarios, en caso de que FP se utilice para programas de análisis anual o expansión del sep
            sep.pFP = this;
            this.pSEP = sep;
            this.pParFP = cParametrosFlujoPotencia();
            if nargin > 2
                this.pAdmSc = varargin{1};
                this.iCantPuntosOperacion = this.pAdmSc.entrega_cantidad_puntos_operacion();
                % reemplaza parámetros del FP por los indicados en programa optimización correspondiente
                this.copia_parametros_optimizacion(varargin{2});
            end
            
            if isempty(sep.pResEvaluacion)
                this.pResEvaluacion = cResultadoEvaluacionSEP(sep, 2, this.NivelDetalleResultados, this.iCantPuntosOperacion); % 2 indica que es FP
            else
                this.pResEvaluacion = sep.pResEvaluacion;
                if ~this.pResEvaluacion.ContenedoresInicializadosFP
                    this.pResEvaluacion.inserta_nuevo_tipo_resultado(2, this.NivelDetalleResultados, this.iCantPuntosOperacion);
                end
            end
                        
            this.genera_version_struct(sep); % "carga" directamente el primer punto de operación
            this.calcula_cant_subsistemas();
        end
        
        function inserta_etapa(this, etapa)
            this.iEtapa = etapa;
        end

        function inserta_escenario(this, escenario)
            this.iEscenario= escenario;
        end
        
        function varargout = genera_version_struct(this, sep, varargin)
            % handle: tiene structs con todo los Variables sobre
            % - Subestaciones:
            %   Id, Id_real, Nombre, Vn, IdSubsistema, Lineas, Trafos, Generadores, Consumos
            % - Lineas:
            %   Id, Id_real, Nombre, Bus1, Bus2, Rpul, Xpul, Cpul, Gpul, Largo Sr,
            %   PorcentajeCompensacion, EnServicio, IdSubsistema
            % - Transformadores:
            %   Id, Id_real, Nombre, Bus1, Bus2, TapMin, TapMax, DuTap, Sr, Vr1, Vr2, P0, I0,
            %   Pcu, Uk, CantidadTaps, LadoTap, TapActual, TapNom, ControlaTension,
            %   IdTapRegulador, VoltajeObjetivo, EnServicio, IdSubsistema
            % - Generadores:
            %   Id, Id_real, Nombre, Bus, P0, Q0, Pmax, Qmin, Qmax, Slack, ControlaTension,
            %   VoltajeObjetivo, Despachable, EnServicio, IdSubsistema
            %   Pfp, Qfp, ControlaTensionFP
            % - Consumos:
            %   Id, Id_real, Nombre, Bus, P0, Q0, Pmax, Pmin, DepVoltaje, EnServicio, IdSubsistema
            % si hay resultados de evaluación (pResEvaluacion), carga directamente el primer punto de operación
            % Cantidades
            
            this.POActual = 1; % carga siempre datos del primer punto de operación
            if nargin > 2
                h.num.(varargin{1}) = 1;
                elemento = sep;
                sep = struct();
                sep.(varargin{1}) = elemento;
            else
                h.num.Subestaciones = length(sep.Subestaciones);
                h.num.Generadores = length(sep.Generadores);
                h.num.Trafos = length(sep.Transformadores2D);
                h.num.Lineas = length(sep.Lineas);
                h.num.Consumos = length(sep.Consumos);
                h.num.Baterias = length(sep.Baterias);
                h.num.Condensadores = length(sep.Condensadores);
                h.num.Reactores = length(sep.Reactores);
            end
            
            % Subestaciones
            if nargin == 2 || strcmp(varargin{1},'Subestaciones')
                %   Id, Nombre, Vn, IdSubsistema, Lineas, Trafos, Generadores, Consumos
                h.Subestaciones.Id = zeros(h.num.Subestaciones,1);
                h.Subestaciones.Vn = zeros(h.num.Subestaciones,1);
                h.Subestaciones.IdSubsistema = ones(h.num.Subestaciones,1);
                h.Subestaciones.Lineas = cell(h.num.Subestaciones,1);
                h.Subestaciones.Trafos = cell(h.num.Subestaciones,1);
                h.Subestaciones.Generadores = cell(h.num.Subestaciones,1);
                h.Subestaciones.Consumos = cell(h.num.Subestaciones,1);
                h.Subestaciones.Baterias = cell(h.num.Subestaciones,1);
                h.Subestaciones.Condensadores = cell(h.num.Subestaciones,1);
                h.Subestaciones.Reactores = cell(h.num.Subestaciones,1);
                
                for s = 1:h.num.Subestaciones
                    h.Subestaciones.Id(s) = sep.Subestaciones(s, 1).Id;
                    h.Subestaciones.Vn(s) = sep.Subestaciones(s, 1).Vn;
                    if ~isempty(sep.Subestaciones(s, 1).Lineas)
                        lin = zeros(length(sep.Subestaciones(s, 1).Lineas),1);
                        for i = 1:length(sep.Subestaciones(s, 1).Lineas)
                            lin(i) = sep.Subestaciones(s, 1).Lineas(i, 1).Id;
                        end
                        h.Subestaciones.Lineas{s} = lin;
                    end
                    if ~isempty(sep.Subestaciones(s, 1).Transformadores2D)
                        lin = zeros(length(sep.Subestaciones(s, 1).Transformadores2D),1);
                        for i = 1:length(sep.Subestaciones(s, 1).Transformadores2D)
                            lin(i) = sep.Subestaciones(s, 1).Transformadores2D(i, 1).Id;
                        end
                        h.Subestaciones.Trafos{s} = lin;
                    end
                    if ~isempty(sep.Subestaciones(s, 1).Generadores)
                        lin = zeros(length(sep.Subestaciones(s, 1).Generadores),1);
                        for i = 1:length(sep.Subestaciones(s, 1).Generadores)
                            lin(i) = sep.Subestaciones(s, 1).Generadores(i, 1).Id;
                        end
                        h.Subestaciones.Generadores{s} = lin;
                    end
                    if ~isempty(sep.Subestaciones(s, 1).Consumos)
                        lin = zeros(length(sep.Subestaciones(s, 1).Consumos),1);
                        for i = 1:length(sep.Subestaciones(s, 1).Consumos)
                            lin(i) = sep.Subestaciones(s, 1).Consumos(i, 1).Id;
                        end
                        h.Subestaciones.Consumos{s} = lin;
                    end
                    if ~isempty(sep.Subestaciones(s, 1).Baterias)
                        lin = zeros(length(sep.Subestaciones(s, 1).Baterias),1);
                        for i = 1:length(sep.Subestaciones(s, 1).Baterias)
                            lin(i) = sep.Subestaciones(s, 1).Baterias(i, 1).Id;
                        end
                        h.Subestaciones.Baterias{s} = lin;
                    end
                    if ~isempty(sep.Subestaciones(s, 1).Condensadores)
                        lin = zeros(length(sep.Subestaciones(s, 1).Condensadores),1);
                        for i = 1:length(sep.Subestaciones(s, 1).Condensadores)
                            lin(i) = sep.Subestaciones(s, 1).Condensadores(i, 1).Id;
                        end
                        h.Subestaciones.Condensadores{s} = lin;
                    end
                    if ~isempty(sep.Subestaciones(s, 1).Reactores)
                        lin = zeros(length(sep.Subestaciones(s, 1).Reactores),1);
                        for i = 1:length(sep.Subestaciones(s, 1).Reactores)
                            lin(i) = sep.Subestaciones(s, 1).Reactores(i, 1).Id;
                        end
                        h.Subestaciones.Reactores{s} = lin;
                    end
                end
                h.Subestaciones.Id_real = h.Subestaciones.Id;
            end
            
            % Lineas
            if nargin == 2 || strcmp(varargin{1},'Lineas')
                %   Id, Nombre, Bus1, Bus2, Rpul, Xpul, Cpul, Gpul, Largo Sr,
                %   PorcentajeCompensacion, EnServicio, IdSubsistema
                h.Lineas.Id = zeros(h.num.Lineas,1);
                h.Lineas.Bus1 = zeros(h.num.Lineas,1);
                h.Lineas.Bus2 = zeros(h.num.Lineas,1);
                h.Lineas.Rpul = zeros(h.num.Lineas,1);
                h.Lineas.Xpul = zeros(h.num.Lineas,1);
                h.Lineas.Cpul = zeros(h.num.Lineas,1);
                h.Lineas.Gpul = zeros(h.num.Lineas,1);
                h.Lineas.Largo = zeros(h.num.Lineas,1);
                h.Lineas.Sr = zeros(h.num.Lineas,1);
                h.Lineas.PorcentajeCompensacion = zeros(h.num.Lineas,1);
                h.Lineas.EnServicio = true(h.num.Lineas,1);
                h.Lineas.IdSubsistema = ones(h.num.Lineas,1);
                
                for s = 1:h.num.Lineas
                    h.Lineas.Id(s) = sep.Lineas(s, 1).Id;
                    [Bus1, Bus2] = sep.Lineas(s, 1).entrega_subestaciones();
                    h.Lineas.Bus1(s) = Bus1.entrega_id();
                    h.Lineas.Bus2(s) = Bus2.entrega_id();
                    h.Lineas.Rpul(s) = sep.Lineas(s, 1).entrega_rpul();
                    h.Lineas.Xpul(s) = sep.Lineas(s, 1).entrega_xpul();
                    h.Lineas.Cpul(s) = sep.Lineas(s, 1).entrega_cpul();
                    h.Lineas.Gpul(s) = sep.Lineas(s, 1).entrega_gpul();
                    h.Lineas.Largo(s) = sep.Lineas(s, 1).largo();
                    h.Lineas.Sr(s) = sep.Lineas(s, 1).entrega_sr();
                    h.Lineas.PorcentajeCompensacion(s) = sep.Lineas(s, 1).entrega_compensacion_serie();
                    h.Lineas.EnServicio(s) = sep.Lineas(s, 1).EnServicio;
                end
                h.Lineas.Id_real = h.Lineas.Id;
            end
            % Trafos
            if nargin == 2 || strcmp(varargin{1},'Trafos')
                %   Id, Nombre, Bus1, Bus2, Sr, Vr1, Vr2, P0, I0, Pcu, Uk, TapMin,
                %   TapMax, DuTap, CantidadTaps, LadoTap, TapActual, TapNom, ControlaTension,
                %   IdTapRegulador, VoltajeObjetivo, EnServicio, IdSubsistema
                h.Trafos.Id = zeros(h.num.Trafos,1);
                h.Trafos.Bus1 = zeros(h.num.Trafos,1);
                h.Trafos.Bus2 = zeros(h.num.Trafos,1);
                h.Trafos.Sr = zeros(h.num.Trafos,1);
                h.Trafos.Vr1 = zeros(h.num.Trafos,1);
                h.Trafos.Vr2 = zeros(h.num.Trafos,1);
                h.Trafos.P0 = zeros(h.num.Trafos,1);
                h.Trafos.I0 = zeros(h.num.Trafos,1);
                h.Trafos.Pcu = zeros(h.num.Trafos,1);
                h.Trafos.Uk = zeros(h.num.Trafos,1);
                h.Trafos.TapMin = zeros(h.num.Trafos,1);
                h.Trafos.TapMax = zeros(h.num.Trafos,1);
                h.Trafos.DuTap = zeros(h.num.Trafos,1);
                h.Trafos.CantidadTaps = zeros(h.num.Trafos,1);
                h.Trafos.LadoTap = zeros(h.num.Trafos,1);
                h.Trafos.TapActual = zeros(h.num.Trafos,1);
                h.Trafos.TapNom = zeros(h.num.Trafos,1);
                h.Trafos.ControlaTension = false(h.num.Trafos,1);
                h.Trafos.IdTapRegulador = zeros(h.num.Trafos,1);
                h.Trafos.VoltajeObjetivo = zeros(h.num.Trafos,1);
                h.Trafos.EnServicio = true(h.num.Trafos,1);
                h.Trafos.IdSubsistema = ones(h.num.Trafos,1);
                
                for s = 1:h.num.Trafos
                    h.Trafos.Id(s) = sep.Transformadores2D(s, 1).Id;
                    h.Trafos.Bus1(s) = sep.Transformadores2D(s, 1).entrega_se1().entrega_id();
                    h.Trafos.Bus2(s) = sep.Transformadores2D(s, 1).entrega_se2().entrega_id();
                    h.Trafos.Sr(s) = sep.Transformadores2D(s, 1).entrega_sr();
                    h.Trafos.Vr1(s) = sep.Transformadores2D(s, 1).entrega_vr1();
                    h.Trafos.Vr2(s) = sep.Transformadores2D(s, 1).entrega_vr2();
                    h.Trafos.P0(s) = sep.Transformadores2D(s, 1).entrega_P0();
                    h.Trafos.I0(s) = sep.Transformadores2D(s, 1).entrega_I0();
                    h.Trafos.Pcu(s) = sep.Transformadores2D(s, 1).entrega_Pcu();
                    h.Trafos.Uk(s) = sep.Transformadores2D(s, 1).entrega_uk();
                    h.Trafos.TapMin(s) = sep.Transformadores2D(s, 1).entrega_TapMin();
                    h.Trafos.TapMax(s) = sep.Transformadores2D(s, 1).entrega_TapMax();
                    h.Trafos.DuTap(s) = sep.Transformadores2D(s, 1).entrega_DuTap();
                    h.Trafos.LadoTap(s) = sep.Transformadores2D(s, 1).entrega_LadoTap();
                    h.Trafos.TapActual(s) = sep.Transformadores2D(s, 1).entrega_TapActual();
                    h.Trafos.TapNom(s) = sep.Transformadores2D(s, 1).entrega_TapNom();
                    h.Trafos.CantidadTaps(s) = sep.Transformadores2D(s, 1).entrega_cantidad_de_taps();
                    h.Trafos.ControlaTension(s) = sep.Transformadores2D(s, 1).controla_tension();
                    h.Trafos.IdTapRegulador(s) = sep.Transformadores2D(s, 1).entrega_id_tap_regulador();
                    if h.Trafos.ControlaTension(s)
                        h.Trafos.VoltajeObjetivo = sep.Transformadores2D(s, 1).entrega_voltaje_objetivo();
                    end
                    h.Trafos.EnServicio(s) = sep.Transformadores2D(s, 1).EnServicio;
                end
                h.Trafos.Id_real = h.Trafos.Id;
            end
            % Generadores
            if nargin == 2 || strcmp(varargin{1},'Generadores')
                %   Id, Nombre, Bus, P0, Q0, Pmax, Qmin, Qmax, Slack, ControlaTension,
                %   VoltajeObjetivo, Despachable, EnServicio, IdSubsistema
                %   Pfp, Qfp, ControlaTensionFP
                h.Generadores.Id = zeros(h.num.Generadores,1);
                h.Generadores.Bus = zeros(h.num.Generadores,1);
                h.Generadores.P0 = zeros(h.num.Generadores,1);
                h.Generadores.Q0 = zeros(h.num.Generadores,1);
                h.Generadores.Qmax = zeros(h.num.Generadores,1);
                h.Generadores.Pmax = zeros(h.num.Generadores,1);
                h.Generadores.Qmin = zeros(h.num.Generadores,1); 
                h.Generadores.Slack = false(h.num.Generadores,1);
                h.Generadores.ControlaTension = true(h.num.Generadores,1);
                h.Generadores.VoltajeObjetivo = zeros(h.num.Generadores,1);
                h.Generadores.Despachable = true(h.num.Generadores,1);
                h.Generadores.EnServicio = true(h.num.Generadores,1);
                h.Generadores.IdSubsistema = ones(h.num.Generadores,1);
                h.Generadores.Pfp = zeros(h.num.Generadores,1);
                h.Generadores.Qfp = zeros(h.num.Generadores,1);
                h.Generadores.ControlaTensionFP = true(h.num.Generadores,1);
                
                for s = 1:h.num.Generadores
                    h.Generadores.Id(s) = sep.Generadores(s, 1).Id;
                    h.Generadores.Bus(s) = sep.Generadores(s, 1).SE.Id;
                    h.Generadores.Despachable(s) = sep.Generadores(s, 1).Despachable;

                    % Verifica si capacidad del generador evoluciona a futuro
                    if ~isempty(this.pAdmSc) && sep.Generadores(s, 1).entrega_evolucion_capacidad_a_futuro(this.iEscenario)
                        id_adm_sc = sep.Generadores(s, 1).entrega_indice_adm_escenario_capacidad(this.iEscenario);
                        pmax = this.pAdmSc.entrega_capacidad_generador(id_adm_sc, this.iEtapa);
                        h.Generadores.Pmax(s) = pmax;
                        sep.Generadores(s, 1).inserta_pmax(pmax);

                        cosp = sep.Generadores(s, 1).Cosp;
                        qmax = pmax*sqrt(1/cosp^2 - 1);
                        sep.Generadores(s, 1).inserta_qmax(qmax);
                        sep.Generadores(s, 1).inserta_qmin(-qmax);
                    else
                        h.Generadores.Pmax(s) = sep.Generadores(s, 1).Pmax;
                    end
                    
                    h.Generadores.Slack(s) = sep.Generadores(s, 1).Slack;
                    h.Generadores.ControlaTension(s) = sep.Generadores(s, 1).ControlaTension;
                    h.Generadores.ControlaTensionFP(s) = h.Generadores.ControlaTension(s);
                    
                    if this.pResEvaluacion.ExisteResultadoOPF
                        h.Generadores.P0(s) = this.pResEvaluacion.GeneradoresP(s, 1); % por defecto se carga primer punto de operación
                    else
                        h.Generadores.P0(s) = sep.Generadores(s, 1).P0;
                    end
                    h.Generadores.Pfp(s) = h.Generadores.P0(s);
                    
                    if ~sep.Generadores(s, 1).ControlaTension
                        cos_phi = sep.Generadores(s, 1).Cosp;
                        if sep.Generadores(s, 1).TipoCosp > 0
                            qmax = sep.Generadores(s, 1).entrega_qmax_p(h.Generadores.P0(s));
                            h.Generadores.Q0(s) = min(qmax, h.Generadores.P0(s)*sqrt(1/cos_phi^2 - 1));
                        else
                            qmin = sep.Generadores(s, 1).entrega_qmin_p(h.Generadores.P0(s));
                            h.Generadores.Q0(s) = max(qmin, -1*h.Generadores.P0(s)*sqrt(1/cos_phi^2 - 1));
                        end
                        h.Generadores.Qfp(s) = h.Generadores.Q0(s);
                    else
                        h.Generadores.Qmax(s) = sep.Generadores(s, 1).entrega_qmax_p(h.Generadores.P0(s));
                        h.Generadores.Qmin(s) = sep.Generadores(s, 1).entrega_qmin_p(h.Generadores.P0(s));
                    end

                    if ~isempty(this.pResEvaluacion.EstadoOperacionGeneradores)
                        h.Generadores.EnServicio(s) = this.pResEvaluacion.EstadoOperacionGeneradores(s, 1);
                    else
                        %h.Generadores.EnServicio(s) = h.Generadores.P0(s) ~= 0;
                        h.Generadores.EnServicio(s) = sep.Generadores(s, 1).EnServicio;
                    end
                    
                    h.Generadores.VoltajeObjetivo(s) = sep.Generadores(s, 1).VoltajeObjetivo;
                end
                h.Generadores.Id_real = h.Generadores.Id;
            end
            
            % Consumos
            if nargin == 2 || strcmp(varargin{1},'Consumos')
                %   Id, Nombre, Bus, P0, Q0, Pmax, Pmin, IndiceAdmEscenarioPerfilP,
                %   IndiceAdmEscenarioPerfilQ, DepVoltaje, EnServicio, IdSubsistema, Pfp, Qfp
                h.Consumos.Id = zeros(h.num.Consumos,1);
                h.Consumos.Bus = zeros(h.num.Consumos,1);
                h.Consumos.P0 = zeros(h.num.Consumos,1);
                h.Consumos.Q0 = zeros(h.num.Consumos,1);
                h.Consumos.Pmax = zeros(h.num.Consumos,1);
                h.Consumos.IndiceAdmEscenarioPerfilP = zeros(h.num.Consumos,1);
                h.Consumos.IndiceAdmEscenarioPerfilQ = zeros(h.num.Consumos,1);
                h.Consumos.IdAdmEscenarioCapacidad = zeros(h.num.Consumos,1);
                
                h.Consumos.DepVoltaje = false(h.num.Consumos,1);
                h.Consumos.EnServicio = true(h.num.Consumos,1);
                h.Consumos.IdSubsistema = ones(h.num.Consumos,1);
                
                h.Consumos.Pfp = zeros(h.num.Consumos,1);
                h.Consumos.Qfp = zeros(h.num.Consumos,1);
                for s = 1:h.num.Consumos
                    h.Consumos.Id(s) = sep.Consumos(s,1).Id;
                    h.Consumos.Bus(s) = sep.Consumos(s, 1).SE.Id;
                    if ~isempty(this.pAdmSc)
                        h.Consumos.IndiceAdmEscenarioPerfilP(s) = sep.Consumos(s,1).IndiceAdmEscenarioPerfilP;
                        h.Consumos.IndiceAdmEscenarioPerfilQ(s) = sep.Consumos(s,1).IndiceAdmEscenarioPerfilQ;
                        h.Consumos.IdAdmEscenarioCapacidad(s) = sep.Consumos(s,1).IndiceAdmEscenarioCapacidad(this.iEscenario);
                        h.Consumos.Pmax(s) = this.pAdmSc.entrega_capacidad_consumo(h.Consumos.IdAdmEscenarioCapacidad(s), this.iEtapa);
                        h.Consumos.P0(s) = h.Consumos.Pmax(s)*this.pAdmSc.PerfilesConsumo(h.Consumos.IndiceAdmEscenarioPerfilP(s),1);
                        cosp = this.pAdmSc.PerfilesConsumo(h.Consumos.IndiceAdmEscenarioPerfilQ(s),1);
                        h.Consumos.Q0(s) = h.Consumos.P0(s)*sqrt((1/cosp)^2-1); % TODO: por ahora sólo demanda inductiva
                    else
                        h.Consumos.P0(s) = sep.Consumos(s,1).P0;
                        h.Consumos.Q0(s) = sep.Consumos(s,1).Q0;
                        h.Consumos.Pmax(s) = sep.Consumos(s,1).Pmax;
                    end
                    h.Consumos.DepVoltaje(s) = sep.Consumos(s,1).DepVoltaje;
                    if ~h.Consumos.DepVoltaje(s)
                        h.Consumos.Pfp(s) = h.Consumos.P0(s);
                        h.Consumos.Qfp(s) = h.Consumos.Q0(s);
                    end
                    
                    h.Consumos.EnServicio(s) = sep.Consumos(s,1).EnServicio;
                end
                h.Consumos.Id_real = h.Consumos.Id;
            end
            % Baterias
            if nargin == 2 || strcmp(varargin{1},'Baterias')
                %   Id, Nombre, Bus, P0, Q0, Pmax, Pmin, IndiceAdmEscenarioPerfilP,
                %   IndiceAdmEscenarioPerfilQ, DepVoltaje, EnServicio, IdSubsistema, Pfp, Qfp
                h.Baterias.Id = zeros(h.num.Baterias,1);
                h.Baterias.Bus = zeros(h.num.Baterias,1);
                h.Baterias.P0 = zeros(h.num.Baterias,1);
                h.Baterias.Q0 = zeros(h.num.Baterias,1);
                h.Baterias.Pfp = zeros(h.num.Baterias,1);
                h.Baterias.Qfp = zeros(h.num.Baterias,1);
                h.Baterias.Qmax = zeros(h.num.Baterias,1);
                h.Baterias.Qmin = zeros(h.num.Baterias,1);
                h.Baterias.Sr = zeros(h.num.Baterias,1);
                h.Baterias.EnServicio = true(h.num.Baterias,1);
                h.Baterias.ControlaTension = true(h.num.Baterias,1);
                h.Baterias.ControlaTensionFP = true(h.num.Generadores,1);
                h.Baterias.VoltajeObjetivo = zeros(h.num.Baterias,1);
                h.Baterias.IdSubsistema = ones(h.num.Baterias,1);
                
                for s = 1:h.num.Baterias
                    h.Baterias.Id(s) = sep.Baterias(s,1).Id;
                    h.Baterias.Bus(s) = sep.Baterias(s, 1).SE.Id;
                    h.Baterias.Sr(s) = sep.Baterias(s,1).Sr;
                    if this.pResEvaluacion.ExisteResultadoOPF
                        h.Baterias.P0(s) = this.pResEvaluacion.BateriasP(s);
                    else
                        h.Baterias.P0(s) = sep.Baterias(s,1).P0;
                    end
                    h.Baterias.Pfp(s) = h.Baterias.P0(s);
                    h.Baterias.Qmax(s) = sqrt(h.Baterias.Sr(s)^2-h.Baterias.P0(s)^2);
                    h.Baterias.Qmin(s) = -h.Baterias.Qmax(s);
                    h.Baterias.EnServicio(s) = sep.Baterias(s,1).EnServicio;
                    h.Baterias.VoltajeObjetivo(s) = sep.Baterias(s, 1).VoltajeObjetivo;                    
                    h.Baterias.ControlaTension(s) = sep.Baterias(s,1).ControlaTension;
                    h.Baterias.ControlaTensionFP(s) = h.Baterias.ControlaTension(s);
                    if ~h.Baterias.ControlaTension
                        h.Baterias.Q0(s) = sep.Baterias(s,1).Q0;
                        h.Baterias.Qfp(s) = h.Baterias.Q0(s);
                    end
                end
                h.Baterias.Id_real = h.Baterias.Id;
            end
            % Condensadores
            if nargin == 2 || strcmp(varargin{1},'Condensadores')
                %   Id, Bus, Q0, Qmax, Qmin, Paso,DepVoltaje, EnServicio, IdSubsistema
                h.Condensadores.Id = zeros(h.num.Condensadores,1);
                h.Condensadores.Bus = zeros(h.num.Condensadores,1);
                h.Condensadores.Qr = zeros(h.num.Condensadores,1);
                h.Condensadores.Vr = zeros(h.num.Condensadores,1);
                h.Condensadores.Qmax = zeros(h.num.Condensadores,1);
                h.Condensadores.Qmin = zeros(h.num.Condensadores,1);
                h.Condensadores.TapMax = zeros(h.num.Condensadores,1);
                h.Condensadores.TapActual = zeros(h.num.Condensadores,1);
                h.Condensadores.IdSubsistema = ones(h.num.Condensadores,1);
                h.Condensadores.ControlaTension = true(h.num.Condensadores,1);
                h.Condensadores.VoltajeObjetivo = zeros(h.num.Condensadores,1);
                h.Condensadores.EnServicio = true(h.num.Condensadores,1);
                
                for s = 1:h.num.Condensadores
                    h.Condensadores.Id(s) = sep.Condensadores(s,1).Id;
                    h.Condensadores.Bus(s) = sep.Condensadores(s, 1).SE.Id;
                    h.Condensadores.Qr(s) = sep.Condensadores(s,1).Qr;
                    h.Condensadores.Vr(s) = sep.Condensadores(s,1).Vr;
                    h.Condensadores.QMax(s) = sep.Condensadores(s,1).QMax;
                    h.Condensadores.TapMax(s) = sep.Condensadores(s,1).TapMax;
                    h.Condensadores.TapActual(s) = sep.Condensadores(s,1).TapActual;
                    h.Condensadores.EnServicio(s) = sep.Condensadores(s,1).EnServicio;
                    h.Condensadores.ControlaTension(s) = sep.Condensadores(s,1).ControlaTension;
                    h.Condensadores.VoltajeObjetivo(s) = sep.Condensadores(s,1).VoltajeObjetivo;
                end
                h.Condensadores.Id_real = h.Condensadores.Id;
            end
            
            % Reactores
            if nargin == 2 || strcmp(varargin{1},'Reactores')
                %   Id, Bus, Q0, Qmax, Qmin, Paso,DepVoltaje, EnServicio, IdSubsistema
                h.Reactores.Id = zeros(h.num.Reactores,1);
                h.Reactores.Bus = zeros(h.num.Reactores,1);
                h.Reactores.Qr = zeros(h.num.Reactores,1);
                h.Reactores.Vr = zeros(h.num.Reactores,1);
                h.Reactores.Qmin = zeros(h.num.Reactores,1);
                h.Reactores.Qmax = zeros(h.num.Reactores,1);
                h.Reactores.TapMax = zeros(h.num.Reactores,1);
                h.Reactores.TapActual = zeros(h.num.Reactores,1);
                h.Reactores.EnServicio = true(h.num.Reactores,1);
                h.Reactores.ControlaTension = true(h.num.Reactores,1);
                h.Reactores.VoltajeObjetivo = zeros(h.num.Reactores,1);
                h.Reactores.IdSubsistema = ones(h.num.Reactores,1);
                
                for s = 1:h.num.Reactores
                    h.Reactores.Id(s) = sep.Reactores(s,1).Id;
                    h.Reactores.Bus(s) = sep.Reactores(s, 1).SE.Id;
                    h.Reactores.Qr(s) = sep.Reactores(s,1).Qr;
                    h.Reactores.Vr(s) = sep.Reactores(s,1).Vr;
                    h.Reactores.Qmin(s) = sep.Reactores(s,1).QMin;
                    h.Reactores.TapMax(s) = sep.Reactores(s,1).TapMax;
                    h.Reactores.TapActual(s) = sep.Reactores(s,1).TapActual;
                    h.Reactores.EnServicio(s) = sep.Reactores(s,1).EnServicio;
                    h.Reactores.ControlaTension(s) = sep.Reactores(s,1).ControlaTension;
                    h.Reactores.VoltajeObjetivo(s) = sep.Reactores(s,1).VoltajeObjetivo;
                end
                h.Reactores.Id_real = h.Reactores.Id;
            end
            
            if nargin > 2
                varargout{1} = h.(varargin{1});
            else
                this.handle = h;
            end
        end
        
        function agrega_variable(this, variable)
            if isa(variable, 'cLinea')
                elem_name = 'Lineas';
                elemento = this.genera_version_struct(variable, elem_name);
            elseif isa(variable, 'cTransformador2D')
                elem_name = 'Lineas';
                elemento = this.genera_version_struct(variable, elem_name);
            elseif isa(variable,'cSubestacion')
                elem_name = 'Subestaciones';
                elemento = this.genera_version_struct(variable, elem_name);
            elseif isa(variable, 'cBateria')
                elem_name = 'Baterias';
                elemento = this.genera_version_struct(variable, elem_name);
            elseif isa(variable, 'cCondensador')
                elem_name = 'Condensadores';
                elemento = this.genera_version_struct(variable, elem_name);
            elseif isa(variable, 'cReactores')
                elem_name = 'Reactores';
                elemento = this.genera_version_struct(variable, elem_name);
            else
                error = MException('cFlujoPotencia:agrega_variable','Tipo de variable a agregar no implementado');
                throw(error)
            end
            f = fieldnames(elemento);
            for i = 1:numel(f)
                this.handle.(elem_name).(f{i})(end+1) = elemento.(f{i});
            end
            this.handle.num.(elem_name) = this.handle.num.(elem_name)+1;
            this.handle.(elem_name).Id_real = this.handle.(elem_name).Id;
            this.handle.(elem_name).Id = (1:this.handle.num.(elem_name))';
        end
        
        function elimina_variable(this, variable)
            if isa(variable, 'cLinea')
                f = fieldnames(this.handle.Lineas);
                elem_name = 'Lineas';
                index = find(this.handle.Lineas.Id_real == variable.Id);
            elseif isa(variable, 'cTransformador2D')
                f = fieldnames(this.handle.Trafos);
                elem_name = 'Trafos';
                index = find(this.handle.Trafos.Id_real == variable.Id);
            elseif isa(variable, 'cBateria')
                f = fieldnames(this.handle.Baterias);
                elem_name = 'Baterias';
                index = find(this.handle.Baterias.Id_real == variable.Id);
            elseif isa(variable,'cSubestacion')
                f = fieldnames(this.handle.Subestaciones);
                elem_name = 'Subestaciones';
                index = find(this.handle.Subestaciones.Id_real == variable.Id);
            else
                error = MException('cFlujoPotencia:elimina_variable','Tipo de variable a agregar no implementado');
                throw(error)
            end
            for i = 1:numel(f)
                this.handle.(elem_name).(f{i})(index) = [];
            end
            this.handle.num.(elem_name) = this.handle.num.(elem_name)-1;
            this.handle.(elem_name).Id_real = this.handle.(elem_name).Id;
            this.handle.(elem_name).Id = (1:this.handle.num.(elem_name))';
        end
        
        function actualiza_punto_operacion(this,po)            
            % actualiza_punto_operacion: redactar el handle_actual que solamente tiene los
            % elementos del sistema que son en servicio en este hora po con su
            % parametros individuales
            if this.POActual == po
                % nada que hacer, ya que po corresponde a po actual
                return 
            end
            this.POActual = po;
            if this.pResEvaluacion.ContenedoresInicializadosOPF && this.pResEvaluacion.ExisteResultadoOPF
                % generadores
                this.handle.Generadores.P0 = this.pResEvaluacion.GeneradoresP(:,po);                
                if ~isempty(this.pResEvaluacion.EstadoOperacionGeneradores)
                    this.handle.Generadores.EnServicio = this.pResEvaluacion.EstadoOperacionGeneradores(:,po);                    
                else
                    %this.handle.Generadores.EnServicio = this.handle.Generadores.P0 ~= 0;
                    % Modo debug. No se hace nada. Se mantiene estado actual
                end
                
                % actualiza Qmin, Qmax, y Q0 de los generadores
                % sólo de los generadores en servicio
                indices = find(this.handle.Generadores.EnServicio == 1);
                for i = 1:length(indices)
                    s = indices(i);
                    if ~this.handle.Generadores.ControlaTension(s)
                        cos_phi = this.pSEP.Generadores(s, 1).Cosp;
                        if this.pSEP.Generadores(s, 1).TipoCosp > 0
                            qmax = this.pSEP.Generadores(s, 1).entrega_qmax_p(this.handle.Generadores.P0(s));
                            this.handle.Generadores.Q0(s) = min(qmax, this.handle.Generadores.P0(s)*sqrt(1/cos_phi^2 - 1));
                        else
                            qmin = this.pSEP.Generadores(s, 1).entrega_qmin_p(this.handle.Generadores.P0(s));
                            this.handle.Generadores.Q0(s) = max(qmin, -1*this.handle.Generadores.P0(s)*sqrt(1/cos_phi^2 - 1));
                        end
                        this.handle.Generadores.Qfp(s) = this.handle.Generadores.Q0(s);
                    else
                        this.handle.Generadores.Qmax(s) = this.pSEP.Generadores(s, 1).entrega_qmax_p(this.handle.Generadores.P0(s));
                        this.handle.Generadores.Qmin(s) = this.pSEP.Generadores(s, 1).entrega_qmin_p(this.handle.Generadores.P0(s));
                    end                    
                end
             
                % consumos
                if ~isempty(this.pAdmSc)
                    this.handle.Consumos.P0 = this.handle.Consumos.Pmax.*this.pAdmSc.PerfilesConsumo(this.handle.Consumos.IndiceAdmEscenarioPerfilP,po);
                    cosp = this.pAdmSc.PerfilesConsumo(this.handle.Consumos.IndiceAdmEscenarioPerfilQ,po);
                    this.handle.Consumos.Q0 = this.handle.Consumos.Pmax.*sqrt((1./cosp).^2-1);
                else
                    error = MException('cFlujoPotencia:actualiza_punto_operacion','Opción aún no implementada. Tiene que haber administrador de escenarios para actualizar punto de operación');
                    throw(error)                    
                end
                
                if ~isempty(this.pResEvaluacion.BateriasP)
                    this.handle.Baterias.P0 = this.pResEvaluacion.BateriasP(:,po);
                end
            else
                error = MException('cFlujoPotencia:actualiza_punto_operacion','Opción aún no implementada. Tiene que haber resultado evaluación para actualizar punto de operación');
                throw(error)
            end
        end
        
        function calcula_cant_subsistemas(this)
            % determina subsistemas. La cantidad de subsistemas se guarda en iCantSubsistemas
            num_lineas = sum(this.handle.Lineas.EnServicio == 1);
            num_trafos = sum(this.handle.Trafos.EnServicio == 1);
            conexiones = zeros(num_lineas + num_trafos, 2);
            conexiones(1:num_lineas,1) = this.handle.Lineas.Bus1(this.handle.Lineas.EnServicio == 1);
            conexiones(1:num_lineas,2) = this.handle.Lineas.Bus2(this.handle.Lineas.EnServicio == 1);
            conexiones(num_lineas + 1 : num_lineas +num_trafos,1) = this.handle.Trafos.Bus1(this.handle.Trafos.EnServicio == 1);
            conexiones(num_lineas + 1 : num_lineas +num_trafos,2) = this.handle.Trafos.Bus2(this.handle.Trafos.EnServicio == 1);
            
            G = sparse(conexiones(:,1), conexiones(:,2), 1, max(conexiones(:)), max(conexiones(:)));
            G = G + G.';
            [a,~,c] = dmperm(G'+speye(size(G)));
            this.iCantSubsistemas = numel(c)-1;
            if this.iCantSubsistemas > 1
                C = cumsum(full(sparse(1,c(1:end-1),1,1,size(G,1))));
                this.Subestaciones.IdSubsistema(a) = C';
                for i = 1:numel(this.num.Subestaciones)
                    this.Generadores.IdSubsistema([this.Subestaciones.Generadores{i}]) = this.Subestaciones.IdSubsistema(i);
                    this.Trafos.IdSubsistema([this.Subestaciones.Trafos{i}]) = this.Subestaciones.IdSubsistema(i);
                    this.Lineas.IdSubsistema([this.Subestaciones.Lineas{i}]) = this.Subestaciones.IdSubsistema(i);
                    this.Consumos.IdSubsistema([this.Subestaciones.Consumos{i}]) = this.Subestaciones.IdSubsistema(i);
                    this.Baterias.IdSubsistema([this.Subestaciones.Baterias{i}]) = this.Subestaciones.IdSubsistema(i);
                    this.Condensadores.IdSubsistema([this.Subestaciones.Condensadores{i}]) = this.Subestaciones.IdSubsistema(i);
                    this.Reactores.IdSubsistema([this.Subestaciones.Reactores{i}]) = this.Subestaciones.IdSubsistema(i);
                end
            end
            this.bCantSubsistemasCalculados = true;
        end
        
        function evalua_red(this)
            % evalúa la red para todos los puntos de operación, incuyendo
            % análisis de contingencia cuando corresponda
            % Por ahora sólo flujos en operación normal. Sin contingencias
            for po = 1:this.iCantPuntosOperacion
                this.calcula_flujo_potencia(po);
            end
        end
        
        function calcula_flujo_potencia(this, po)
            % calcula_flujo_potencia
            % astimate las parametros de los elementos en servicio del sistema por la
            % hora po asi que los limites de la flujo potencia y otros son cumplidos
            
            % Esta calculado la fp por una hora o por el criterio N - 1
            % por el criterio los variables ya son inicializados
            if this.FlagN1 == 0 && this.POActual ~= po
                this.actualiza_punto_operacion(po);
                if ~this.bCantSubsistemasCalculados
                    this.calcula_cant_subsistemas();
                end
            end
            
            if this.iCantSubsistemas == 1 && this.FlagN1 == 1
                this.FlagN1 = 2;
            end
            
            inicializa_variables_fp(this);
            for i = 1:this.iCantSubsistemas
                this.actualiza_subsistema(i);
                calcula_flujo_potencia_subsistema(this, i)
            end
        end
        
        function actualiza_subsistema(this, id_subsistema)
            % Subestaciones
            indice = this.handle.Subestaciones.IdSubsistema == id_subsistema;
            this.num.Subestaciones = sum(indice);
            fields = fieldnames(this.handle.Subestaciones);
            for i = 1:numel(fields)
                this.Subestaciones.(fields{i}) = [];                
                this.Subestaciones.(fields{i}) = this.handle.Subestaciones.(fields{i})(indice);
            end
            % Generadores
            indice = this.handle.Generadores.EnServicio & this.handle.Generadores.IdSubsistema == id_subsistema;
            this.num.Generadores = sum(indice);
            fields = fieldnames(this.handle.Generadores);
            for i = 1:numel(fields)
                this.Generadores.(fields{i}) = [];
                this.Generadores.(fields{i}) = this.handle.Generadores.(fields{i})(indice);
            end
            % Consumos
            indice = this.handle.Consumos.EnServicio & this.handle.Consumos.IdSubsistema == id_subsistema;
            this.num.Consumos = sum(indice);
            fields = fieldnames(this.handle.Consumos);
            for i = 1:numel(fields)
                this.Consumos.(fields{i}) = [];
                this.Consumos.(fields{i}) = this.handle.Consumos.(fields{i})(indice);
            end
            % Lineas
            indice = this.handle.Lineas.EnServicio & this.handle.Lineas.IdSubsistema == id_subsistema;
            this.num.Lineas = sum(indice);
            fields = fieldnames(this.handle.Lineas);
            for i = 1:numel(fields)
                this.Lineas.(fields{i}) = [];
                this.Lineas.(fields{i}) = this.handle.Lineas.(fields{i})(indice);
            end
            % Trafos
            indice = this.handle.Trafos.EnServicio & this.handle.Trafos.IdSubsistema == id_subsistema;
            this.num.Trafos = sum(indice);
            fields = fieldnames(this.handle.Trafos);
            for i = 1:numel(fields)
                this.Trafos.(fields{i}) = [];
                this.Trafos.(fields{i}) = this.handle.Trafos.(fields{i})(indice);
            end
            % Baterías
            indice = this.handle.Baterias.EnServicio & this.handle.Baterias.IdSubsistema == id_subsistema;
            this.num.Baterias = sum(indice);
            fields = fieldnames(this.handle.Baterias);
            for i = 1:numel(fields)
                this.Baterias.(fields{i}) = [];
                this.Baterias.(fields{i}) = this.handle.Baterias.(fields{i})(indice);
            end
            % Condensadores
            indice = this.handle.Condensadores.EnServicio & this.handle.Condensadores.IdSubsistema == id_subsistema;
            this.num.Condensadores = sum(indice);
            fields = fieldnames(this.handle.Condensadores);
            for i = 1:numel(fields)
                this.Condensadores.(fields{i}) = [];
                this.Condensadores.(fields{i}) = this.handle.Condensadores.(fields{i})(indice);
            end
            % Reactores
            indice = this.handle.Reactores.EnServicio & this.handle.Reactores.IdSubsistema == id_subsistema;
            this.num.Reactores = sum(indice);
            fields = fieldnames(this.handle.Reactores);
            for i = 1:numel(fields)
                this.Reactores.(fields{i}) = [];
                this.Reactores.(fields{i}) = this.handle.Reactores.(fields{i})(indice);
            end
            
            % cambio el nombre porque la Id necesita ser el index de la fila
            this.Subestaciones.Id_real = this.Subestaciones.Id;
            this.Generadores.Id_real = this.Generadores.Id;
            this.Lineas.Id_real = this.Lineas.Id;
            this.Consumos.Id_real = this.Consumos.Id;
            this.Trafos.Id_real = this.Trafos.Id;
            this.Baterias.Id_real = this.Baterias.Id;
            this.Condensadores.Id_real = this.Condensadores.Id;
            this.Reactores.Id_real = this.Reactores.Id;
            
            this.Subestaciones.Id = (1:this.num.Subestaciones)';
            this.Generadores.Id = (1:this.num.Generadores)';
            this.Lineas.Id = (1:this.num.Lineas)';
            this.Trafos.Id = (1:this.num.Trafos)';
            this.Consumos.Id = (1:this.num.Consumos)';
            this.Baterias.Id = (1:this.num.Baterias)';
            this.Condensadores.Id = (1:this.num.Condensadores)';
            this.Reactores.Id = (1:this.num.Reactores)';
            
            if isempty(find(this.Generadores.Slack == 1, 1))
                slack = find(this.Generadores.Pmax == max(this.Generadores.Pmax),1);
                this.Generadores.Slack(slack) = true;
            end
            
            this.Subestaciones.Lineas = cell(this.num.Subestaciones,1);
            this.Subestaciones.Trafos = cell(this.num.Subestaciones,1);
            this.Subestaciones.Generadores = cell(this.num.Subestaciones,1);
            this.Subestaciones.Consumos = cell(this.num.Subestaciones,1);
            this.Subestaciones.Baterias = cell(this.num.Subestaciones,1);
            this.Subestaciones.Condensadores = cell(this.num.Subestaciones,1);
            this.Subestaciones.Reactores = cell(this.num.Subestaciones,1);
            
            for i = 1:this.num.Subestaciones
                this.Subestaciones.Lineas(i) = {[this.Lineas.Id(this.Lineas.Bus1 == i)',...
                    this.Lineas.Id(this.Lineas.Bus2 == i)']};
                this.Subestaciones.Trafos(i) = {[this.Trafos.Id(this.Trafos.Bus1 == i)',...
                    this.Trafos.Id(this.Trafos.Bus2 == i)']};
                this.Subestaciones.Generadores(i) = {this.Generadores.Id(this.Generadores.Bus == i)'};
                this.Subestaciones.Consumos(i) = {this.Consumos.Id(this.Consumos.Bus == i)'};
                this.Subestaciones.Baterias(i) = {this.Consumos.Id(this.Baterias.Bus == i)'};
                this.Subestaciones.Condensadores(i) = {this.Consumos.Id(this.Condensadores.Bus == i)'};
                this.Subestaciones.Reactores(i) = {this.Consumos.Id(this.Reactores.Bus == i)'};
            end
        end
        
        function calcula_flujo_potencia_subsistema(this, nro_subsistema)
            sbase = cParametrosSistemaElectricoPotencia.getInstance().Sbase;
            % calcula flujo potencia por cada subsistema
            
            h = this.num.Subestaciones; % cantidad Buses
            if this.FlagN1 == 0
                this.construye_matriz_admitancia();
                this.inicializa_variables();
                this.determina_condiciones_iniciales();
                this.Subestaciones_init = this.Subestaciones;
                
                % Ojo que this.Subestaciones.q_consumo_const no se necesita. Se guardan valores actuales en this.Subestaciones.Snom
                %this.Subestaciones.q_consumo_const = this.Subestaciones.Snom(:,2);
            else
                % TODO: verificar con Lena por qué originalmente se
                % calculaba nuevamente q_consumo_const. Lo pongo aquí en
                % caso de que FlagN1 no sea cero (eventualmente hay que
                % calcular denuevo q_consumos_const
                
                % Código original que estaba antes de iter = 0
                % calcula consumo total que es siempre constante
                this.Subestaciones.q_consumo_const = zeros(h,1);
                for i = 1:h
                    if ~isempty(this.Subestaciones.Consumos{i})
                        Cons = [this.Subestaciones.Consumos{i,:}];
                        Cons_vali = this.Consumos.DepVoltaje(Cons) == 0;
                        if ~isempty(Cons_vali(Cons_vali))
                            this.Subestaciones.q_consumo_const(i) = this.Subestaciones.q_consumo_const(i) + ...
                                sum(-this.Consumos.Q0(Cons(Cons_vali))./cParametrosSistemaElectricoPotencia.getInstance().Sbase);
                        end
                    end
                end
                
            end
            
            this.Flag = -1; % valor inicial para subsistema actual
            obliga_verificacion_cambio_pv_pq = false;
            
            
            iter = 0;
            discreto = false;
            delta_s = zeros(h,2);
            
            % Ajustar los elementos ajustables (Generadores y Trafos) hasta que se
            % cumplan todos los límites de P,Q
            while true                
                ds_total = 0;
                ds_mw_total = 0;
                s_complejo = calcula_s_complejo(this);
                s = [real(s_complejo),imag(s_complejo)];
                
                if this.NivelDebug > 1
                    prot = cProtocolo.getInstance;
                    prot.imprime_vector([s(:,1);s(:,2)], 's');
                end
                
                % cálculo criterio convergencia
                not_slack = (this.Subestaciones.TipoBuses ~= 3);
                delta_s(not_slack,1) = this.Subestaciones.Snom(not_slack,1) - s(not_slack,1);
                passivo_PQ = (this.Subestaciones.TipoBuses < 2);
                delta_s(passivo_PQ,2) = this.Subestaciones.Snom(passivo_PQ,2) - s(passivo_PQ,2);
                ds_total = sum(sum(delta_s));
                ds_mw_total = sum(sum(abs(delta_s)));
                
                if this.NivelDebug > 0
                    prot = cProtocolo.getInstance;
                    %         prot.imprime_vector([this.Subestaciones.Snom(:,1); this.Subestaciones.Snom(:,2)], 'Snom');
                    prot.imprime_vector([delta_s(:,1);delta_s(:,2)], 'delta_s');
                    prot.imprime_valor(ds_total, ['ds_total it ' num2str(iter)]);
                    prot.imprime_valor(ds_mw_total, 'ds_mw_total');
                end
                % cambio tipo de buses PV --> PQ
                cambio_tipo_buses = false;
                if iter > this.pParFP.NumIterSinCambioPVaPQ || obliga_verificacion_cambio_pv_pq
                    % verificar si es necesario cambio de tipo de buses
                    % no es un bus cuyo voltaje es controlado por un trafo
                    % bus_PV_V: tiene todos Id de buses que son tipo PV y  no tienen transformadores reguladores
                    bus_PV_V = this.Subestaciones.Id(this.Subestaciones.TipoBuses == 2 & this.Subestaciones.TipoVarControl == 0);
                    if ~isempty(bus_PV_V)
                        % q_consumo_agregada: suma de Qfp de todos generadores que controlan la tension de este bus
                        % RA: saqué esto porque no se necesita. Q actual se encuentra siempre en this.Subestaciones.Snom
                        %q_consumo_agregada = zeros(length(bus_PV_V),1);
                        %for i = 1:length(bus_PV_V)
                        %    if ~isempty(this.Subestaciones.Generadores(bus_PV_V(i)))
                        %        gens = [this.Subestaciones.Generadores{bus_PV_V(i),:}];
                        %        Gen_const = gens(this.Generadores.ControlaTensionFP(gens) == 0);
                        %        q_consumo_agregada(i) = sum(this.Generadores.Qfp(Gen_const)./cParametrosSistemaElectricoPotencia.getInstance().Sbase);
                        %    end
                        %end
                        %q_consumo = this.Subestaciones.q_consumo_const(bus_PV_V) + q_consumo_agregada;
                        q_consumo = this.Subestaciones.Snom(bus_PV_V,2);
                        q_inyeccion = s(bus_PV_V,2) - q_consumo;
                        Qmin = zeros(length(bus_PV_V),1);
                        Qmax = zeros(length(bus_PV_V),1);
                        for n = 1:length(bus_PV_V)
                            gens_ids = [this.Subestaciones.Generadores{bus_PV_V(n)}];
                            gen_control_id = gens_ids(this.Generadores.ControlaTensionFP(gens_ids)== 1);
                            
                            bat_ids = [this.Subestaciones.Baterias{bus_PV_V(n)}];
                            bat_control_id = bat_ids(this.Baterias.ControlaTensionFP(bat_ids)== 1);
                            %--------------- Maybe still different in in old code!
%                             Qmin(n) = sum(this.Generadores.Qmin(gen_control_id));
%                             Qmax(n) = sum(this.Generadores.Qmax(gen_control_id));
                            % RA: cambio el siguiente código, ya que no hay diferencia entre generadores despachables y los no despachables
                            %if this.Generadores.Despachable(gen_control_id)
                                Qmin(n) = sum(this.Generadores.Qmin(gen_control_id));
                                Qmax(n) = sum(this.Generadores.Qmax(gen_control_id));
                                
                                Qmin(n) = Qmin(n) + sum(this.Baterias.Qmin(bat_control_id));
                                Qmax(n) = Qmax(n) + sum(this.Baterias.Qmax(bat_control_id));
                                
                                % TODO: Faltan condensadores y baterías
                                
                            %else % no dispachable                                
                            %    Pfp = this.Generadores.Pfp(gen_control_id);
                            %    q_no_disp = sqrt((Pfp/this.Generadores.Cosp(gen_control_id)).^2 - Pfp.^2); % TODO: se debe reemplazar por variable que indique cosp_min. 
                            %    Qmin(n) = sum(-q_no_disp);
                            %    Qmax(n) =  sum(q_no_disp);
                            %end
                        end
                        % q_min/q_max son vectores con los posibles Q max o min para cada
                        % bus
                        q_min = Qmin/sbase;
                        q_max = Qmax/sbase;
                        
                        for i = 1:length(q_inyeccion)
                            if (q_inyeccion(i) < q_min(i)) || (q_inyeccion(i) > q_max(i))
                                this.Subestaciones.TipoBuses(bus_PV_V(i)) = 1; % 'PQ'
                                if this.NivelDebug > 1
                                    text = ['Cambio bus ' num2str(bus_PV_V(i)) ' de PV a PQ porque inyeccion se encuentra fuera de rango' ...
                                        '. QInyecion: ' num2str(q_inyeccion(i)) '. Q min: ' num2str(q_min(i)) '. Qmax: ' num2str(q_max(i)) '\n'];
                                    cProtocolo.getInstance.imprime_texto(text);
                                end
                                % gens_bus: Ids de Generadores de este bus
                                % gens_control: Id de todos generadores que controlan
                                % gens_nodespach: Id de todos generadores que no son despachable
                                % gens: Id de generadores del bus que controlan
                                % gens2: Id de generadores del bus que controlan y no son despachable
                                %gens_bus = [this.Subestaciones.Generadores{bus_PV_V(i)}];
                                %gens_control = this.Generadores.Id(this.Generadores.ControlaTension == 1);
                                %gens_nodespach = this.Generadores.Id(this.Generadores.Despachable == 0);
                                %gens = intersect(gens_bus, gens_control);
                                %gens2 = intersect(gens, gens_nodespach);
                                gens = [this.Subestaciones.Generadores{bus_PV_V(i)}];
                                gens = gens(this.Generadores.ControlaTensionFP(gens)== 1);                                
                                bats = [this.Subestaciones.Baterias{bus_PV_V(i)}];
                                bats = bats(this.Baterias.ControlaTensionFP(bats)== 1);

                                this.Generadores.ControlaTensionFP(gens) = false;
                                this.Baterias.ControlaTensionFP(bats) = false;
                                
                                if q_inyeccion(i) < q_min(i)
                                    this.Subestaciones.Snom(bus_PV_V(i),2) = q_min(i) + q_consumo(i);
                                    
                                    % cambia Q de elementos que controlan tensión para que queden fijos                                    
                                    this.Generadores.Qfp(gens) = this.Generadores.Qmin(gens);
                                    this.Baterias.Qfp(bats) = this.Baterias.Qmin(bats);
                                    
                                    %if ~isempty(gens2)
                                    %    Pfps = this.Generadores.Pfp(gens2);
                                    %    this.Generadores.Qfp(gens2)= -sqrt((Pfps/0.9).^2 - Pfps.^2);
                                    %end
                                else
                                    this.Subestaciones.Snom(bus_PV_V(i),2) = q_max(i) + q_consumo(i);
                                    this.Generadores.Qfp(gens) = this.Generadores.Qmax(gens);
                                    this.Baterias.Qfp(bats) = this.Baterias.Qmax(bats);
                                    %if ~isempty(gens2)
                                    %    Pfps = this.Generadores.Pfp(gens2);
                                    %    this.Generadores.Qfp(gens2)= sqrt((Pfps/0.9).^2 - Pfps.^2);
                                    %end
                                end
                                cambio_tipo_buses = true;
                            end
                        end
                    end
                    %---------------
                    % voltaje controlado por trafo. Hay que verificar que tap está dentro de los límites
                    bus_PV_Tap = this.Subestaciones.Id(this.Subestaciones.TipoBuses == 2 & this.Subestaciones.TipoVarControl == 1);
                    if ~isempty(bus_PV_Tap)
                        t_tap_actual = this.Subestaciones.VarEstado(bus_PV_Tap,2);
                        trafo = ismember([this.Subestaciones.Trafos{bus_PV_Tap}], this.TrafosReg);
                        id_tap = this.Trafos.IdTapRegulador(trafo);
                        tap_nom = this.Trafos.TapNom(trafo,id_tap);
                        du_tap = this.Trafos.DuTap(trafo,id_tap);
                        tap_actual = (t_tap_actual-1)./du_tap+tap_nom; %trafo.entrega_tap_dado_t(id_tap, t_tap_actual);
                        tap_max = this.Trafos.TapMax(trafo,id_tap);
                        tap_min = this.Trafos.TapMax(trafo,id_tap);
                        
                        % fija trafo en tap máximo
                        tan_grande = tap_actual > tap_max;
                        this.Trafos.TapActual(trafo(tan_grande),id_tap) = tap_max;
                        this.Subestaciones.TipoBuses(bus_PV_Tap(tan_grande)) = 1; %'PQ'
                        this.Subestaciones.TipoVarControl(bus_PV_Tap(tan_grande)) = 0; % 'V'
                        
                        tan_chico = tap_actual < tap_min;
                        this.Trafos.TapActual(trafo(tan_chico),id_tap) = tap_min;
                        this.Subestaciones.TipoBuses(bus_PV_Tap(tan_chico)) = 1; % 'PQ'
                        this.Subestaciones.TipoVarControl(bus_PV_Tap(tan_chico)) = 0; % 'V'
                    end
                end
                
                % criterio de convergencia
                % flujo de potencia convergente cuando:
                % 1. error es menor que valor umbral epsilon
                % 2. no hay transformadores reguladores o estos ya fueron
                %    discretizados y
                % 3. no hubo cambio en tipo de buses
                
                if ~isnumeric(ds_mw_total)
                    % desviación total de mw no es numérico
                    %         convergencia = false;
                    %         Indicador_convergencia=2;
                    %         this. indicador_convergencia0= Indicador_convergencia;
                    this.Flag = 3;
                    break;
                end
                
                if (ds_mw_total < this.pParFP.MaxErrorMW) ...
                        && (discreto || isempty(this.TrafosReg)) ...
                        && ~cambio_tipo_buses
                    % hay convergencia
                    if iter < this.pParFP.NumIterSinCambioPVaPQ
                        obliga_verificacion_cambio_pv_pq = true;
                    else
                        %             convergencia = true;
                        this.Flag = 0;
                        break;
                    end
                end
                
                if iter > this.pParFP.MaxNumIter
                    % se alcanzó el máximo número de iteraciones. No hay convergencia
                    %         convergencia = false;
                    %         Indicador_convergencia=0;
                    %         this. indicador_convergencia0= Indicador_convergencia;
                    this.Flag = 2;
                    break;
                end
                %------------------
                if (ds_mw_total < this.pParFP.MaxErrorMW) && ~isempty(this.TrafosReg) && ~discreto
                    % convergió pero aún no se han discretizado los transformadores reguladores, condensadores y reactores
                    % Pasos:
                    % 1. Discretizar los pasos de los transformadores
                    %    reguladores
                    % 2. Cambiar estado de variables de UE --> U
                    % 3. TODO: condensadores y reactores
                    discreto = true;
                    for bus = 1:h
                        if this.Subestaciones.TipoVarControl(bus) == 1 % 'TapReg'
                            % entrega lista de transformadores que regulan tensión del bus
                            cantidad_trafos = this.entrega_cantidad_trafos_reguladores(this.pBuses(bus));
                            for ittraf = 1:cantidad_trafos
                                paso_actual = this.entrega_paso_trafo_regulador(this.pBuses(bus), ittraf, true);
                                this.inserta_paso_actual_trafo_regulador(round(paso_actual), this.pBuses(bus), ittraf, true);
                            end
                            if cantidad_trafos == 0
                                error = MException('calcula_flujo_potencia:calcula_flujo_potencia','Variable del bus es TapReg pero no hay transformadores reguladores');
                                throw(error)
                            end
                            %ajustar variables
                            this.Subestaciones.VarEstado(bus, 2) = this.entrega_trafo_regulador(this.pBuses(bus), 1, true).entrega_voltaje_objetivo_pu();
                            this.Subestaciones.TipoVarControl(bus) = 0; % 'V'
                            this.Subestaciones.TipoVarEstado(bus, 2) = 0; % 'V'
                        end
                    end
                end
                
                % nueva iteración
                % actualiza J debido a los cambios del transformadores
                this.actualiza_matriz_jacobiana();
                
                if this.NivelDebug > 1
                    prot = cProtocolo.getInstance;
                    prot.imprime_matriz(this.J, ['Matriz Jacobiana sin eliminacion en iteracion: ' num2str(iter)]);
                end
                
                %borrar filas y columnas de la barra slack
                % se borra el ángulo y el voltaje ya que son conocidos,
                % el voltaje, ya que es conocido.
                % El ángulo se mantiene ya que es desconocido
                % con Indexing
                indice_a_borrar = [ this.Subestaciones.TipoBuses == 3;...
                    ((this.Subestaciones.TipoBuses ==2 & this.Subestaciones.TipoVarControl == 0)...
                    | this.Subestaciones.TipoBuses == 3) ];
                
                % RA: Borro siguiente código ya que no es necesario volver a verificar bus slack
                %if ~find(this.Subestaciones.TipoBuses == 3) % no slack_encontrada
                %    error = MException('calcula_flujo_potencia:calcula_flujo_potencia','No se encontró slack');
                %    throw(error)
                %end
                
                % crea indices entre variables de estado y
                % las "nuevas" variables de estado, en donde se borraron
                % los valores conocidos
                IndiceVarSol = not(indice_a_borrar);
                delta_s_1 = [delta_s(:,1);delta_s(:,2)];
                VecSol = delta_s_1(IndiceVarSol);
                
                % borra filas y columnas de la matriz jacobiana
                this.J(:,indice_a_borrar) = [];
                this.J(indice_a_borrar,:) = [];
                
                % resuelve sistema de ecuaciones
                Sol = -this.J\VecSol;

                if this.NivelDebug > 1
                    prot = cProtocolo.getInstance;
                    prot.imprime_vector([this.Subestaciones.VarEstado(:,1);this.Subestaciones.VarEstado(:,2)], 'antiguo vector con variables de estado');
                    prot.imprime_vector(indice_a_borrar, 'indices a borrar');
                    prot.imprime_matriz(this.J, 'Matriz jacobiana sin filas ni columnas');
                    prot.imprime_vector(VecSol, 'VecSol');
                    prot.imprime_vector(IndiceVarSol, 'indice de variables y solucion');
                    prot.imprime_vector(Sol, 'Sol');
                end
                
                % escribe resultados en VarEstado
                VarEstado1 = reshape(this.Subestaciones.VarEstado,[],1);
                VarEstado1(IndiceVarSol) = VarEstado1(IndiceVarSol) - Sol()...
                    .*[ones(sum(IndiceVarSol(1:h)),1); this.Subestaciones.VarEstado(IndiceVarSol(h+1:end),2)];
                this.Subestaciones.VarEstado = reshape(VarEstado1, [], 2);
                
                if this.NivelDebug > 1
                    prot = cProtocolo.getInstance;
                    prot.imprime_vector([this.Subestaciones.VarEstado(:,1);this.Subestaciones.VarEstado(:,2)], 'nuevo vector solucion');
                    imprime_estado_variables(this);
                end
                %---------------------
                % actualizar paso de los transformadores
                bus_TapReg = find(this.Subestaciones.TipoVarControl == 1); % 'TapReg'
                for bus_i = 1:length(bus_TapReg)
                    bus = bus_TapReg(bus_i);
                    cantidad_trafos = this.entrega_cantidad_trafos_reguladores(this.pBuses(bus));
                    for itr = 1:cantidad_trafos
                        this.inserta_paso_actual_trafo_regulador(this.Subestaciones.VarEstado(bus, 2), this.pBuses(bus), itr, true);
                    end
                end
                
                % actualizar matriz de admitancia debido a transformadores
                % reguladores
                this.actualiza_matriz_admitancia();
                
                iter = iter + 1;
            end
            % fin de las iteraciones. Se calculan y escriben los resultados del flujo de potencias
            
            if this.NivelDebug > 1
                prot = cProtocolo.getInstance;
                text = ['Fin flujo de potencias. Estado flag: ' num2str(this.Flag) '\nImprime estado de variables\n'];
                prot.imprime_texto(text);
                imprime_estado_variables(this);
            end
            
            % Flujo de potencias convergente.
            this.calcula_y_escribe_resultados_fp();
            if this.NivelDebug > 1
                cProtocolo.getInstance.imprime_texto(['Flag final del flujo de potencias: ' num2str(this.Flag)]);
                % this.guarda_solucion_formato_matpower();
                %-----------------
                % elseif this.NivelDebug == 1
                %     guarda_solucion_indices(this)
                
            end
        end
        
        function inicializa_variables_fp(this)
            % Generadores
            this.handle.Generadores.ControlaTensionFP = this.handle.Generadores.ControlaTension;
            this.handle.Generadores.Pfp = this.handle.Generadores.P0;
            this.handle.Generadores.Qfp(this.handle.Generadores.ControlaTensionFP) = 0;
            this.handle.Generadores.Qfp(~this.handle.Generadores.ControlaTensionFP) = ...
                this.handle.Generadores.Q0(~this.handle.Generadores.ControlaTensionFP);
            
            % Consumo
            this.handle.Consumos.Qfp = this.handle.Consumos.Q0;
            this.handle.Consumos.Pfp = this.handle.Consumos.P0;
            this.handle.Consumos.Qfp(this.handle.Consumos.DepVoltaje) = 0;
            this.handle.Consumos.Pfp(this.handle.Consumos.DepVoltaje) = 0;
            
            % Baterias
            this.handle.Baterias.ControlaTensionFP = this.handle.Baterias.ControlaTension;
            this.handle.Baterias.Qfp(this.handle.Baterias.ControlaTensionFP) = 0;
            this.handle.Baterias.Qfp(~this.handle.Baterias.ControlaTensionFP) = ...
                this.handle.Baterias.Q0(~this.handle.Baterias.ControlaTensionFP);

            % Condensadores, reactores y trafos y trafos?
            
        end
        
        function construye_matriz_admitancia(this)
            this.Adm = zeros(this.num.Subestaciones);
            % Lineas
            if isprop(this,'Lineas')
                [y11, y12, y21, y22] = entrega_cuadripolo_linea(this);
                n = this.Subestaciones.Id(this.Lineas.Bus1);
                m = this.Subestaciones.Id(this.Lineas.Bus2);
                % signos están considerados en cálculo de cuadripolos. Aquí
                % sólo hay que ingresar los datos
                idx = sub2ind(size(this.Adm), n, m);
                [a,~,c] = unique(idx);
                y = accumarray(c,y12);
                this.Adm(a) = this.Adm(a) + y;
                
                idx = sub2ind(size(this.Adm), m, n);
                [a,~,c] = unique(idx);
                y = accumarray(c,y21);
                this.Adm(a) = this.Adm(a) + y;
                
                idx = sub2ind(size(this.Adm), n, n);
                [a,~,c] = unique(idx);
                y = accumarray(c,y11);
                this.Adm(a) = this.Adm(a) + y;
                
                idx = sub2ind(size(this.Adm), m, m);
                [a,~,c] = unique(idx);
                y = accumarray(c,y22);
                this.Adm(a) = this.Adm(a) + y;
            end
            % Trafos
            if isprop(this,'Trafos')
                [y11, y12, y21, y22] = entrega_cuadripolo_trafo(this);
                n = this.Subestaciones.Id(this.Trafos.Bus1);
                m = this.Subestaciones.Id(this.Trafos.Bus2);
                % signos están considerados en cálculo de cuadripolos. Aquí
                % sólo hay que ingresar los datos
                idx = sub2ind(size(this.Adm), n, m);
                [a,~,c] = unique(idx);
                y = accumarray(c,y12);
                this.Adm(a) = this.Adm(a) + y;
                
                idx = sub2ind(size(this.Adm), m, n);
                [a,~,c] = unique(idx);
                y = accumarray(c,y21);
                this.Adm(a) = this.Adm(a) + y;
                
                idx = sub2ind(size(this.Adm), n, n);
                [a,~,c] = unique(idx);
                y = accumarray(c,y11);
                this.Adm(a) = this.Adm(a) + y;
                
                idx = sub2ind(size(this.Adm), m, m);
                [a,~,c] = unique(idx);
                y = accumarray(c,y22);
                this.Adm(a) = this.Adm(a) + y;
            end
            % 2. Elementos paralelos (Condensador, Consumo, Reactor,(Generador))
            % Consumo
            if isprop(this,'Consumos')
                if this.Consumos.DepVoltaje ~= 0
                    cons = this.Consumos.DepVoltaje ~= 0;
                    ns = this.Subestaciones.Id(this.Consumos.Bus(cons));
                    vnom = this.Subestaciones.Vn(this.Consumos.Bus(cons));
                    ynn = complex(this.Consumos.P0(cons)./(vnom.^2),this.Consumos.Q0(cons)./(vnom.^2));
                    
                    idx = sub2ind(size(this.Adm), ns, ns);
                    [a,~,c] = unique(idx);
                    y = accumarray(c,ynn);
                    this.Adm(a) = this.Adm(a) + y;
                end
            end
            % Condensador
            if isprop(this,'Condensadores')
                ns = this.Subestaciones.Id(this.Condensadores.Bus);
                ynn = -complex(0,this.Condensadores.Qr./this.Condensadores.Vr .^2);
                ynn = ynn.*this.Condensadores.TapActual./this.Condensadores.TapMax;
                idx = sub2ind(size(this.Adm), ns, ns);
                [a,~,c] = unique(idx);
                y = accumarray(c,ynn);
                this.Adm(a) = this.Adm(a) + y;
            end
            % Reactores
            if isprop(this,'Reactores')
                ns = this.Subestaciones.Id(this.Reactores.Bus);
                vbase = this.Subestaciones.Vn(this.Reactores.Bus);
                ybase = cParametrosSistemaElectricoPotencia.getInstance().Sbase./vbase.^2;
                ynn = -complex(0,this.Reactores.Qr./this.Reactores.Vr .^2);
                ynn = ynn.*this.Reactores.TapActual./this.Reactores.TapMax;
                ynn = ynn./ybase;
                idx = sub2ind(size(this.Adm), ns, ns);
                [a,~,c] = unique(idx);
                y = accumarray(c,ynn);
                this.Adm(a) = this.Adm(a) + y;
            end
            if this.NivelDebug > 1
                prot = cProtocolo.getInstance;
                prot.imprime_matriz(this.Adm, 'Matriz Admitancia');
            end
            this.Adm_init = this.Adm;
        end
        
        function [y11, y12, y21, y22] = entrega_cuadripolo_linea(this)
            % Siempre en pu.
            if this.Lineas.Largo == 0
                error = MException('cLinea:entrega_cuadripolo','largo de la línea no definido');
                throw(error)
            end
            vbase = this.Subestaciones.Vn(this.Lineas.Bus1);
            zbase = vbase.^2./cParametrosSistemaElectricoPotencia.getInstance().Sbase;
            x = this.Lineas.Largo .* this.Lineas.Xpul;
            if sum(this.Lineas.PorcentajeCompensacion ~= 0)> 0
                x = x.*(ones(size(this.Lineas.PorcentajeCompensacion))-this.Lineas.PorcentajeCompensacion);
            end
            r = this.Lineas.Largo .* this.Lineas.Rpul;
            b = this.Lineas.Largo .* this.Lineas.Cpul * 2 *pi *50 / 1000000;
            g = this.Lineas.Largo .* this.Lineas.Gpul;
            yserie = 1./complex(r,x);
            y0 = complex(0.5*g,0.5*b);
            
            y12 = -yserie.*zbase;
            y21 = -yserie.*zbase;
            y11 = (y0 + yserie).*zbase;
            y22 = (y0 + yserie).*zbase;
        end
        
        function [y11, y12, y21, y22] = entrega_cuadripolo_trafo(this, varargin)
            % varargin entrega el valor del tap regulador, en caso de que se indique
            if nargin > 1
                valor_tap_regulador = varargin{1};
                this.Trafos.TapActual(this.Trafos.IdTapRegulador) = valor_tap_regulador;
            end
            
            vbase = this.Subestaciones.Vn(this.Trafos.Bus1);
            zbase = vbase.^2./cParametrosSistemaElectricoPotencia.getInstance().Sbase;
            
            % primero valores base convertidos a pu y luego consideran los taps
            r = this.Trafos.Pcu.*(this.Trafos.Vr1./this.Trafos.Sr).^2./zbase;
            x = this.Trafos.Uk .*((this.Trafos.Vr1.^2)./this.Trafos.Sr)./zbase;
            zk = complex(r, x);
            
            g = this.Trafos.P0 ./ this.Trafos.Vr1.^2 ./ 1000 .* zbase;
            b = sqrt(3)* this.Trafos.I0 ./ this.Trafos.Vr1 .* zbase;
            y0 = complex(0.5*g,0.5*b);
            
            y11 =  (1./zk + y0);
            y12 =  -1./zk;
            y21 =  -1./zk;
            y22 =  (1./zk + y0);
            
            %     if this.Trafos.CantidadTaps == 0
            %         y11 =  (1./zk + y0);
            %         y12 =  -1./zk;
            %         y21 =  -1./zk;
            %         y22 =  (1./zk + y0);
            %     else
            %         % calcula diferencia de voltaje en el primario (dup) y
            %         % secundario (dus). Para ello, se calcula la diferencia de voltaje de cada uno de los taps y luego se asignan al lado correspondiente
            %
            %         du_taps = (tap_actual - this.TapNom).*this.DuTap;
            %         angulo_taps = zeros(this.CantidadTaps,1);
            %         for i = 1:this.CantidadTaps
            %             if this.LadoTap(i) == 2
            %                 angulo_taps(i) = angle(this.RelTrans);
            %             end
            %         end
            %         du_taps = du_taps.*complex(cos(angulo_taps), sin(angulo_taps));
            %
            %         % calcula diferencia de voltaje en el primario y secundario
            %         du_p = sum(du_taps(this.LadoTap == 1));
            %         du_s = sum(du_taps(this.LadoTap == 2));
            %
            %         tp = (1+du_p)/abs(1+du_p)^2;
            %         ts = (1+du_s)/abs(1+du_s)^2;
            %
            %         y11 =  (1/zk + y0)*abs(tp)^2;
            %         y12 =  -1/zk*conj(tp)*ts;
            %         y21 =  -1/zk*tp*conj(ts);
            %         y22 =  (1/zk + y0)/abs(ts)^2;
            %     end
        end
        
        function inicializa_variables(this)
            if this.NivelDebug > 1
                prot = cProtocolo.getInstance;
                prot.imprime_texto('Inicializa variables');
            end
            % se identifican barras PV, PQ, Slack
            % Tipobuses: Se actualiza en cada iteración, indica si es
            %            Passivo = 0, PQ = 1, PV = 2 o Slack = 3.
            % VarEstado: Variables de estado tienene el formato ángulos (para todos los
            %            buses) y después los voltajes
            % TipoVarControl: Tipo de variable de control del bus. Puede ser
            %            'V' = 0 o 'TapReg' = 1 (para los transformadores reguladores)
            % Snom: contiene las potencias reales P (para todos los buses) y
            %            luego las potencias aparentes Q
            sbase = cParametrosSistemaElectricoPotencia.getInstance().Sbase;
            h = this.num.Subestaciones;
            Buses = this.Subestaciones;
            Buses.VarEstado = zeros(h,2);
            Buses.Snom = zeros(h,2);
            Buses.TipoBuses = zeros(h,1);
            Buses.TipoVarControl = zeros(h,1); %valor por defecto: 'V'
            Buses.VoltajeObjetivo = zeros(h,1);

            % 1. determina tipo de buses
            PQ = this.Consumos.Bus(:);
            Buses.TipoBuses(PQ) = 1;% PQ
            BGen_Slack = this.Generadores.Bus(this.Generadores.ControlaTension == 1 & this.Generadores.Slack == 1);
            if length(BGen_Slack) ~= 1
                error = MException('cFlujoPotencia:inicializa_variables','Error en datos de entrada. Hay más de un bus slack');
                throw(error)
            end
            BGen_noSlack = this.Generadores.Bus(this.Generadores.ControlaTension == 1 & this.Generadores.Slack == 0);
            BBat_conControlTension = this.Baterias.Bus(this.Baterias.ControlaTension == 1);
            
            Buses.TipoBuses(BGen_noSlack) = 2;% PV
            Buses.TipoBuses(BBat_conControlTension) = 2;% PV
            Buses.TipoBuses(BGen_Slack) = 3;% Slack. Siempre al final por si hay más de un generador conectado a la misma barra slack

            % 2. determina voltajes objetivo y verifica que sean los mismos para cada bus
            Volt_Slack = this.Generadores.VoltajeObjetivo(this.Generadores.ControlaTension == 1 & this.Generadores.Slack == 1)./Buses.Vn(BGen_Slack);
            Volt_Gen_noSlack = this.Generadores.VoltajeObjetivo(this.Generadores.ControlaTension == 1 & this.Generadores.Slack == 0)./Buses.Vn(BGen_noSlack);
            Volt_Bat = this.Baterias.VoltajeObjetivo(this.Baterias.ControlaTension == 1)./Buses.Vn(BBat_conControlTension);
            
            BVoltObj = [BGen_Slack Volt_Slack; BGen_noSlack Volt_Gen_noSlack; BBat_conControlTension Volt_Bat];
            BVoltObj_unique = unique(BVoltObj, 'rows');
            if length(BVoltObj_unique) ~= length(unique(BVoltObj(:,1)))
                error = MException('cFlujoPotencia:inicializa_variables','Hay más de un voltaje objetivo para los buses');
                throw(error)
            end
            
            Buses.VoltajeObjetivo(BVoltObj_unique(:,1)) = BVoltObj_unique(:,2);
            
            % 3. Determina Snom
            Cons = this.Consumos.Bus(this.Consumos.DepVoltaje == 0);
            if ~isempty(Cons)
                Buses.Snom(Cons,:) = [-this.Consumos.P0([Buses.Consumos{Cons}])/sbase, -this.Consumos.Q0([Buses.Consumos{Cons}])/sbase];
            end
            
            % Baterias
            if ~isempty(BBat_conControlTension)
                Buses.Snom(BBat_conControlTension,1) = Buses.Snom(BBat_conControlTension,1) + ...
                    this.Baterias.P0([Buses.Baterias{BBat_conControlTension}])/sbase;
            end
            
            BBat_sinControlTension = this.Baterias.Bus(this.Baterias.ControlaTension == 0);
            if ~isempty(BBat_sinControlTension)
                Buses.Snom(BBat_sinControlTension,:) = Buses.Snom(BBat_sinControlTension,:) + ...
                    [this.Baterias.P0([Buses.Baterias{BBat_sinControlTension}])/sbase, this.Baterias.Q0([Buses.Baterias{BBat_sinControlTension}])/sbase];
            end
            
            %Condensador, Reactor???
            %Cons = this.Consumos.Bus(this.Consumos.DepVoltaje == 1);
            %if ~isempty(Cons)
            %    Buses.Snom(Cons,:) = zeros(length(Cons),2);
            %end

            %Generadores
            unico = unique(this.Generadores.Bus);
            Pfp = cellfun(@(s) sum(this.Generadores.Pfp(s)), this.Subestaciones.Generadores(unico));
            Qfp = cellfun(@(s) sum(this.Generadores.Qfp(s)), this.Subestaciones.Generadores(unico));
            Buses.Snom(unico,:) = Buses.Snom(unico,:) + [Pfp/sbase, Qfp/sbase];
                        
            %Transformador
            Lados = this.Trafos.LadoTap(this.Trafos.ControlaTension == 1);
            if ~isempty(Lados)
                buses = [this.Trafos.Bus1(Lados == 1);this.Trafos.Bus2(Lados == 2)];
                members = ismember(buses, this.BusesConRegPorTrafo);
                this.BusesConRegPorTrafo = [this.BusesConRegPorTrafo buses(~members)];
                this.TrafosReg = [this.TrafosReg; this.Trafos.Id(this.Trafos.ControlaTension == 1)];
                Buses.TipoVarControl(buses(~members)) = 1; % 'TapReg'
                this.Trafos.ControlaTensionFP(buses(~members)) = true;
                % ya existe un transformador regulador
                % para este bus. Hay que verificar que
                % sean paralelos
                if ~ismember(this.Trafos.Id(this.Trafos.ControlaTension == 1),this.TrafosReg)
                    error = MException('calcula_flujo_potencia:inicializa_tipo_variables_decision','existen dos transformadores que regulan el mismo nodo pero no son paralelos');
                    throw(error)
                end
            end
            
            if this.NivelDebug > 1
                prot = cProtocolo.getInstance;
                prot.imprime_vector([Buses.Snom(:,1); Buses.Snom(:,2)], 'Snom');
            end
            this.Subestaciones = Buses;
        end
        
        function determina_condiciones_iniciales(this)
            % determina voltajes y ángulos de inicio
            % eventualmente falta agregar un mejor método
            % Por ahora, todos los voltajes en las barras PQ = valor nominal
            % y para las barras PV = valor voltaje objetivo
            
            this.Subestaciones.VarEstado(:) = 0;
            bus_PV_Slack = find(this.Subestaciones.TipoBuses > 1); % PV = 2, Slack = 3
            if ~isempty(bus_PV_Slack)
                this.Subestaciones.VarEstado(bus_PV_Slack,2) = ones(size(bus_PV_Slack))...
                    *this.Subestaciones.VoltajeObjetivo(bus_PV_Slack(1));
            end
            this.Subestaciones.VarEstado( this.Subestaciones.TipoBuses < 2,2) = 1.02; % PQ = 1, Pasivo = 0
            
            % asumiendo que son pocos los transformadores reguladores, es
            % m?s eficiente reemplazar valor original. Como en este caso se
            % est?n determinando las condiciones iniciales, no es necesario
            % verificar si el bus es PQ o PV
            if ~isempty(this.BusesConRegPorTrafo)
                tap_actual = this.Trafos.TapActual(this.Trafos.IdTapRegulador);
                tap_nom = this.Trafos.TapNom(this.Trafos.IdTapRegulador);
                du_tap = this.Trafos.DuTap(this.Trafos.IdTapRegulador);
                this.Subestaciones.VarEstado(this.BusesConRegPorTrafo, 2) = 1 + (tap_actual - tap_nom)*du_tap;
                this.Subestaciones.TipoBuses(this.BusesConRegPorTrafo) = 2; % 'PV'
            end
        end
        
        function s_complejo = calcula_s_complejo(this)
            %entrega la potencia como resultado del sistema de ecuaciones
            Buses = this.Subestaciones;
            u = zeros(this.num.Subestaciones,1);
            u(Buses.TipoVarControl==0) = Buses.VarEstado(Buses.TipoVarControl==0,2);
            TapReg = Buses.TipoVarControl==1;
            if sum(TapReg)~= 0
                if ~ismember([this.Subestaciones.Trafos{[4,5]}], this.TrafosReg)
                    error = MException('calcula_flujo_potencia:calcula_s_complejo','no se pudo encontrar trafo regulador y flag es obligatorio');
                    throw(error)
                end
                u(TapReg) = this.Trafos.VoltajeObjetivo(this.Subestaciones.Trafos(TapReg))./this.Subestaciones.Vn(TapReg);
            end
            theta = Buses.VarEstado(:,1);
            u_bus = (cos(theta)+ 1i*sin(theta)) .* u;
            
            s_complejo = diag(u_bus)*conj(this.Adm*u_bus);
            if this.NivelDebug > 1
                prot = cProtocolo.getInstance;
                prot.imprime_matriz(u_bus, 'u_bus');
                prot.imprime_vector(s_complejo, 's_complejo');
            end
        end
        
        function actualiza_matriz_jacobiana(this)
            h = this.num.Subestaciones;
            this.J = zeros(2*h);
            f = false(h);
            dpi_dui = zeros(h,1);
            dqi_dui = zeros(h,1);
            u = zeros(h,1);
            
            VarControl = this.Subestaciones.TipoVarControl == 1;
            u(~VarControl) = this.Subestaciones.VarEstado(~VarControl,2);
            for ff = 1: sum(VarControl)
                % transformador regulador
                fila = find(this.Subestaciones.TipoVarControl == 1);
                trafos = [this.Subestaciones.Trafos{fila(ff)}];
                indice = ismember(trafos, this.TrafosReg);
                if ~isempty(indice)
                    if this.Trafos.ControlaTension(trafos(indice))
                        u = this.Trafos.VoltajeObjetivo(trafos(indice))/this.Subestaciones.Vn(fila(ff));
                    else
                        error = MException('cTransformador2D:entrega_voltaje_objetivo','transformador no controla tension');
                        throw(error)
                    end
                else
                    error = MException('calcula_flujo_potencia:callcula_flujo_potencia','Variable del bus es TapReg pero no hay transformadores reguladores');
                    throw(error)
                end
            end
            t = this.Subestaciones.VarEstado(:,1);
            mat = this.Adm ~=0;
            % derivadas c/r al voltaje para buses no regulados por transformadores reguladores
            % En caso de que el bus sea regulado por un transformador, los valores
            % se agregan después a partir de los elementos fuera de la diagonal
            vars_ii = diag(this.Adm);
            ind_diag = find(vars_ii ~= 0);
            if sum(VarControl) > 0
                ind_diag = intersect(ind_diag, find(~VarControl));
            end
            
            yrii = real(vars_ii);
            yiii = imag(vars_ii);
            dpi_dui(ind_diag) = dpi_dui(ind_diag) + 2.*u(ind_diag).^2.*yrii(ind_diag);
            dqi_dui(ind_diag) = dqi_dui(ind_diag) - 2.*u(ind_diag).^2.*yiii(ind_diag);
            
            %fuera de la diagonal
            mat_ij = logical(logical(mat)-eye(h));
            vars_ij = this.Adm(mat_ij);
            [filas, cols] = find(mat_ij == 1);
            
            l = length(filas);
            dpi_duj = zeros(l,1);
            dqi_duj = zeros(l,1);
            
            sinij = sin(t(filas)-t(cols));
            cosij = cos(t(filas)-t(cols));
            
            yrij = real(vars_ij);
            yiij = imag(vars_ij);
            
            % derivadas con respecto a theta. No hay distinci?n
            % entre si el bus est? regulado por un trafo
            dpi_dtj = u(filas).*u(cols).*(yrij.*sinij-yiij.*cosij);
            dqi_dtj = -u(filas).*u(cols).*(yrij.*cosij+yiij.*sinij);
            
            this.J([mat_ij, f; f, f]) = dpi_dtj; % fila,col
            this.J([f, f; mat_ij, f]) = dqi_dtj; %fila + h ,col
            
            % agrega elementos para la diagonal para las
            % derivadas con respecto a theta
            [~,~,c] = unique(filas);
            dpi_dti = accumarray(c,-dpi_dtj);%dpi_dti(filas) - dpi_dtj;
            dqi_dti = accumarray(c,-dqi_dtj);%dqi_dti(filas) - dqi_dtj;
            
            % derivadas con respecto a u o a t. En este caso hay que
            % hacer una distinci?n entre buses regulados por
            % transformadores y los que no
            
            % agrega elemento para la diagonal en caso de que
            % el bus col no sea regulado por un transformador
            % regulador
            noControl = this.Subestaciones.TipoVarControl(filas) == 0; % 'V'
            filas_noControl = filas(noControl);
            [~,~,c] = unique(filas_noControl);
            dpi_dui_ges = u(filas_noControl).*u(cols(noControl)).*...
                (yrij(noControl).*cosij(noControl)+yiij(noControl).*sinij(noControl));
            dpi_dui = dpi_dui + accumarray(c,dpi_dui_ges);
            
            dqi_dui_ges =  u(filas_noControl).*u(cols(noControl)).*...
                (yrij(noControl).*sinij(noControl)-yiij(noControl).*cosij(noControl));
            dqi_dui = dqi_dui + accumarray(c,dqi_dui_ges);
            
            noControl = this.Subestaciones.TipoVarControl(cols) == 0; % 'V'
            dpi_duj(noControl) = u(filas(noControl)).*u(cols(noControl)).*...
                (yrij(noControl).*cosij(noControl)+yiij(noControl).*sinij(noControl));
            dqi_duj(noControl) = u(filas(noControl)).*u(cols(noControl)).*...
                (yrij(noControl).*sinij(noControl)-yiij(noControl).*cosij(noControl));
            
            this.J([f, mat_ij; f, f]) = dpi_duj; % fila,col+ h
            this.J([f, f; f, mat_ij]) = dqi_duj; % fila + h ,col+ h
            
            d = eye(h, 'logical');
            % dP
            this.J([d, f; f, f]) = dpi_dti; % fila, fila
            this.J([f, d; f, f]) = dpi_dui; % fila, fila + h
            % dQ
            this.J([f, f; d, f]) = dqi_dti; % fila + h, fila
            this.J([f, f; f, d]) = dqi_dui; % fila + h, fila + h
        end
        
        function imprime_estado_variables(this)
            % varargin indica si ?ngulos se imprimen en radianes o grados
            if this.NivelDebug > 0
                prot = cProtocolo.getInstance;
                prot.imprime_texto('variables y estados');
                
                prot.imprime_texto('Tipo buses entrada');
                texto = sprintf('%10s %10s', 'Bus', 'Tipo bus');
                prot.imprime_texto(texto);
            end
            h = this.num.Subestaciones;
            for bus = 1:h
                texto = sprintf('%10s %10s %10s', num2str(bus), num2str(this.Subestaciones.TipoBuses(bus)));
                prot.imprime_texto(texto);
            end
            
            prot.imprime_texto('Valores vector de estados');
            texto = sprintf('%10s %10s %10s %10s', 'Nr.Var', 'Bus', 'Tipo', 'Valor');
            prot.imprime_texto(texto);
            for bus = 1:h
                % primero angulos
                texto = sprintf('%10s %10s %10s %10s %10s', num2str(bus), num2str(bus),...
                    'Theta', num2str(this.Subestaciones.VarEstado(bus,1)),...
                    '(', num2str(this.Subestaciones.VarEstado(bus,1)/pi*180), ' grados)');
                prot.imprime_texto(texto);
            end
            for bus = 1:h
                % voltajes o tap de transformadores
                texto = sprintf('%10s %10s %10s', num2str(bus + h), num2str(bus),...
                    num2str(this.Subestaciones.TipoVarControl(bus)), num2str(this.Subestaciones.VarEstado(bus,2)));
                prot.imprime_texto(texto);
            end
            
            prot.imprime_texto('Snom:');
            texto = sprintf('%10s %10s %10s %10s', 'Nr.Var', 'Bus', 'Tipo', 'Valor');
            prot.imprime_texto(texto);
            for bus = 1:h
                % primero Pnom
                texto = sprintf('%10s %10s %10s %10s', num2str(bus), num2str(bus), 'MW', num2str(this.Subestaciones.Snom(bus,1)));
                prot.imprime_texto(texto);
            end
            for bus = 1:h
                % Qnom
                texto = sprintf('%10s %10s %10s %10s', num2str(bus + h), num2str(bus), 'MVA', num2str(this.Subestaciones.Snom(bus,2)));
                prot.imprime_texto(texto);
            end
        end
        
        function actualiza_matriz_admitancia(this)
            % hay que actualizar datos debido a los transformadores reguladores
            for i = 1:length(this.BusesConRegPorTrafo)
                for j = 1:length(this.TrafosReg(i).Lista)
                    eserie = this.TrafosReg(i).Lista(j);
                    n = this.TrafosReg(i).IDBusReg(j);  % en teoría redundante, ya que los buses son los mismos para todos los transformadores
                    m = this.TrafosReg(i).IDBusNoReg(j);
                    tap_antiguo = this.TrafosReg(i).PasoActualAdm(j);
                    tap_nuevo = eserie.entrega_elemento_red().entrega_tap_actual_regulador();
                    if tap_antiguo ~= tap_nuevo
                        %actualiza matriz admitancia
                        [y11, y12, y21, y22] = eserie.entrega_elemento_red().entrega_cuadripolo(tap_antiguo);
                        
                        this.Adm(n,m) = this.Adm(n,m) - y12;
                        this.Adm(m,n) = this.Adm(m,n) - y21;
                        this.Adm(n,n) = this.Adm(n,n) - y11;
                        this.Adm(m,m) = this.Adm(m,m) - y22;
                        
                        [y11, y12, y21, y22] = eserie.entrega_cuadripolo();
                        this.Adm(n,m) = this.Adm(n,m) + y12;
                        this.Adm(m,n) = this.Adm(m,n) + y21;
                        this.Adm(n,n) = this.Adm(n,n) + y11;
                        this.Adm(m,m) = this.Adm(m,m) + y22;
                        this.TrafosReg(i).PasoActualAdm(j) = tap_nuevo;
                    end
                end
            end
        end
        
        function calcula_y_escribe_resultados_fp(this)
            % escribe resultados del flujo de potencias para subsistema actual
            this.pResEvaluacion.FP_Flag(this.POActual) = this.Flag;
            if this.Flag > 1
                % Por ahora nada que hacer. Eventualmente se pueden extraer
                % resultados de por qué no convergió el FP
                return
            end
            sbase = cParametrosSistemaElectricoPotencia.getInstance().Sbase;
            s_complejo = calcula_s_complejo(this);
            delta_s = complex(this.Subestaciones.Snom(:,1), this.Subestaciones.Snom(:,2))- s_complejo;
            %     if this.NivelDebug > 1
            %         prot = cProtocolo.getInstance;
            %         prot.imprime_vector(delta_s, 'delta_s_fin');
            %     end
            % ingresa valores para cálculo de resultado
            P0 = this.Generadores.P0(this.Generadores.Slack);
            bus_con_gen_slack = this.Subestaciones.Id(this.Generadores.Bus(this.Generadores.Slack));
            P = P0/cParametrosSistemaElectricoPotencia.getInstance().Sbase - real(delta_s(bus_con_gen_slack));
            this.Generadores.Pfp(this.Generadores.Slack) = P*sbase;
            err = sum(abs(real(delta_s(this.Subestaciones.Id(this.Subestaciones.TipoBuses~= 3)))) > 0.001);
            if  err > 0
                error = MException('calcula_flujo_potencia:calcula_y_escribe_resultados_fp','%d bus(es) no es slack pero existe p residual significativo', err);
                throw(error)
            end
            
            for i = 1:length(delta_s)
                estado = this.distribuye_q_residual(i, -imag(delta_s(i)));
            end

            % Se ingresan resultados para consumos con dependencia de voltaje
            % Condensador & Reactor
            %     if isa(el_red, 'cCondensador') || isa(el_red, 'cReactor')
            %         y0 = el_red.entrega_dipolo_pu();
            %         pres = real(y0)*vbus^2;
            %         qres = -imag(y0)*vbus^2;
            %         el_red.inserta_resultados_flujo_potencia(this.id_fp, pres, qres);
            
            if isprop(this, 'Consumos') && ~isempty(this.Consumos.DepVoltaje == 1)
                cons = this.Consumos.Bus(this.Consumos.DepVoltaje == 1);
                vbus = this.Subestaciones.Vn(cons);
                vnom =this.Subestaciones.VarEstado(cons,2).*vbus;
                p0 = this.Consumos.P0(this.Consumos.DepVoltaje == 1);
                q0 = -this.Consumos.Q0(this.Consumos.DepVoltaje == 1);
                P = p0.*vbus.^2./vnom.^2;
                Q = q0.*vbus.^2./vnom.^2;
                this.Consumos.Pfp(this.Consumos.DepVoltaje == 1) = P*sbase;
                this.Consumos.Qfp(this.Consumos.DepVoltaje == 1) = Q*sbase;
            end
            
            if estado > 0
                % hay violaci?n de los l?mites de los generadores. Se
                % actualiza el Flag
                this.Flag = 1;
                this.pResEvaluacion.FP_Flag(this.POActual) = this.Flag;
                return
            end
            
            % Calcula flujos por elementos de red
            Perdidas = complex(0,0);
            % Flujos de los elementos en serie (Lineas, Trafos)
            % Lineas
            v1 = this.Subestaciones.VarEstado(this.Lineas.Bus1,2).*complex(...
                cos(this.Subestaciones.VarEstado(this.Lineas.Bus1,1)),...
                sin(this.Subestaciones.VarEstado(this.Lineas.Bus1,1)));
            v2 = this.Subestaciones.VarEstado(this.Lineas.Bus2,2).*complex(...
                cos(this.Subestaciones.VarEstado(this.Lineas.Bus2,1)),...
                sin(this.Subestaciones.VarEstado(this.Lineas.Bus2,1)));
            [y11, y12, y21, y22] = entrega_cuadripolo_linea(this);

            i1 = (v1.*y11+v2.*y12);
            i2 = (v1.*y21+v2.*y22);
            s1 = v1.*conj(i1);
            s2 = v2.*conj(i2);
            perdidas = s1+s2;

            % conversión a unidades de salida
            i1_angulo = angle(i1);
            i2_angulo = angle(i2);

            ibase = sbase./v1;
            this.Lineas.I1 = i1.*ibase/sqrt(3);
            this.Lineas.I2 = i2.*ibase/sqrt(3);
            this.Lineas.ThetaI1 = i1_angulo/pi*180;
            this.Lineas.ThetaI2 = i2_angulo/pi*180;
            this.Lineas.S1 = s1*sbase;
            this.Lineas.S2 = s2*sbase;
            this.Lineas.Perdidas = perdidas*sbase;

            Perdidas = Perdidas + sum(this.Lineas.Perdidas(this.Lineas.EnServicio));

            % Trafos
            v1 = this.Subestaciones.VarEstado(this.Trafos.Bus1,2).*complex(...
                cos(this.Subestaciones.VarEstado(this.Trafos.Bus1,1)),...
                sin(this.Subestaciones.VarEstado(this.Trafos.Bus1,1)));
            v2 = this.Subestaciones.VarEstado(this.Trafos.Bus2,2).*complex(...
                cos(this.Subestaciones.VarEstado(this.Trafos.Bus2,1)),...
                sin(this.Subestaciones.VarEstado(this.Trafos.Bus2,1)));
            [y11, y12, y21, y22] = entrega_cuadripolo_trafo(this);

            i1 = (v1.*y11+v2.*y12);
            i2 = (v1.*y21+v2.*y22);
            s1 = v1.*conj(i1);
            s2 = v2.*conj(i2);
            perdidas = s1+s2;

            % conversión a unidades de salida
            i1_angulo = angle(i1);
            i2_angulo = angle(i2);

            ibase = sbase./v1;
            this.Trafos.I1 = i1.*ibase/sqrt(3);
            this.Trafos.I2 = i2.*ibase/sqrt(3);
            this.Trafos.ThetaI1 = i1_angulo/pi*180;
            this.Trafos.ThetaI2 = i2_angulo/pi*180;
            this.Trafos.S1 = s1*sbase;
            this.Trafos.S2 = s2*sbase;
            this.Trafos.Perdidas = perdidas*sbase;
            
            Perdidas = Perdidas + sum(this.Trafos.Perdidas(this.Trafos.EnServicio));
            
            % escribe resultados
            this.pResEvaluacion.ExisteResultadoFP = true;
            
            % Flujos máximos
            this.pResEvaluacion.FP_LineasFlujoMaximo = unique([this.pResEvaluacion.FP_LineasFlujoMaximo; unique(this.Lineas.Id_real(this.Lineas.S1 > this.Lineas.Sr),'last')]);
            this.pResEvaluacion.FP_TrafosFlujoMaximo = unique([this.pResEvaluacion.FP_TrafosFlujoMaximo; unique(this.Trafos.Id_real(this.Trafos.S1 > this.Trafos.Sr),'last')]);
            
            % Buses con voltajes fuera de límites
            vmin_pu = cParametrosSistemaElectricoPotencia.getInstance().entrega_vmin_vn_pu(this.Subestaciones.Vn);
            vmax_pu = cParametrosSistemaElectricoPotencia.getInstance().entrega_vmax_vn_pu(this.Subestaciones.Vn);
            this.pResEvaluacion.FP_BusesVMaxFueraDeLimites = unique([this.pResEvaluacion.FP_BusesVMaxFueraDeLimites; this.Subestaciones.Id_real(this.Subestaciones.VarEstado(:,2) > vmax_pu)]);
            this.pResEvaluacion.FP_BusesVMinFueraDeLimites = unique([this.pResEvaluacion.FP_BusesVMinFueraDeLimites; this.Subestaciones.Id_real(this.Subestaciones.VarEstado(:,2) < vmin_pu)]);
            
            if this.NivelDetalleResultados > 0
                
                % por ahora nada
                if this.NivelDetalleResultados > 1
                    % resultados detallados
                    this.pResEvaluacion.FP_FlujoLineasP(this.Lineas.Id_real,this.POActual) = real(this.Lineas.S1);
                    this.pResEvaluacion.FP_FlujoLineasQ(this.Lineas.Id_real,this.POActual) = imag(this.Lineas.S1);
                    this.pResEvaluacion.FP_FlujoTransformadoresP(this.Trafos.Id_real,this.POActual) = real(this.Trafos.S1);
                    this.pResEvaluacion.FP_FlujoTransformadoresQ(this.Trafos.Id_real,this.POActual) = imag(this.Trafos.S1);
                    this.pResEvaluacion.FP_TapTransformadores(this.Trafos.Id_real,this.POActual) = this.Trafos.TapActual;
                    this.pResEvaluacion.FP_GeneradoresP(this.Generadores.Id_real,this.POActual) = this.Generadores.Pfp;
                    this.pResEvaluacion.FP_GeneradoresQ(this.Generadores.Id_real,this.POActual) = this.Generadores.Qfp;
                    this.pResEvaluacion.FP_TapCondensadores(this.Condensadores.Id_real,this.POActual) = this.Condensadores.TapActual;
                    this.pResEvaluacion.FP_TapReactores(this.Reactores.Id_real,this.POActual) = this.Reactores.TapActual;

                    this.pResEvaluacion.FP_BateriasP(this.Baterias.Id_real,this.POActual) = this.Baterias.Pfp;
                    this.pResEvaluacion.FP_BateriasQ(this.Baterias.Id_real,this.POActual) = this.Baterias.Qfp;

                    this.pResEvaluacion.FP_ConsumosP(this.Consumos.Id_real,this.POActual) = this.Consumos.Pfp;
                    this.pResEvaluacion.FP_ConsumosQ(this.Consumos.Id_real,this.POActual) = this.Consumos.Qfp;

                    this.pResEvaluacion.FP_AnguloSubestaciones(this.Subestaciones.Id_real,this.POActual) = this.Subestaciones.VarEstado(:,1)/pi*180;
                    this.pResEvaluacion.FP_VoltajeSubestaciones(this.Subestaciones.Id_real,this.POActual) = this.Subestaciones.VarEstado(:,2).*this.Subestaciones.Vn;
                    this.pResEvaluacion.FP_Perdidas(this.POActual) = this.pResEvaluacion.FP_Perdidas(this.POActual) + Perdidas;
                end
            end
        end
        
        function [estado] = distribuye_q_residual(this, bus_id, q_residual)
            % estado = 0 si todo está en orden
            % estado = 1 si se violan los l?mites de potencia reactiva de
            % los generadores
            sbase = cParametrosSistemaElectricoPotencia.getInstance().Sbase;
            estado = 0;
            if abs(q_residual) < 0.01
                % error es muy chico. No se hace nada para evitar errores numéricos
                return
            end
            % q residual se prorratea en base a Qmax de las unidades de generación y baterías. Se le da prioridad a las baterías
            gens_de_bus = [this.Subestaciones.Generadores{bus_id}]';
            bats_de_bus = [this.Subestaciones.Baterias{bus_id}]';
            if isempty(gens_de_bus) && isempty(bats_de_bus)
                estado = 1;
                return
            end
            gen_slack = gens_de_bus(this.Generadores.Slack(gens_de_bus)== 1);
            gens = this.Generadores.ControlaTensionFP(gens_de_bus)== 1;
            bats = this.Baterias.ControlaTensionFP(bats_de_bus) == 1;
            
            indices = gens_de_bus(gens);
            this.Generadores.Qfp(indices) = 0; % en teoría no se necesita, ya que están definidos así
            
            indices_bats = bats_de_bus(bats);
            this.Baterias.Qfp(indices_bats) = 0; % en teoría no se necesita, ya que están definidos así
            if q_residual > 0
                qlim_elemento = this.Generadores.Qmax(indices)/sbase;
                qlim_baterias = this.Baterias.Qmax(indices_bats)/sbase;
            else
                qlim_elemento = this.Generadores.Qmin(indices)/sbase;
                qlim_baterias = this.Baterias.Qmin(indices_bats)/sbase;
            end
            
            abs_suma_total = abs(sum(qlim_elemento)) + abs(sum(qlim_baterias));
            if isempty(gen_slack) && abs_suma_total < abs(q_residual)
                if this.NivelDebug > 0
                    texto = ['q residual (' num2str(q_residual) ') en bus ' num2str(bus_id)...
                        ' es mayor al límite de potencia reactiva de los generadores y baterías que controlan voltaje'];
                    warning(texto);
                end
                estado = 1;
                % como hay violación de los límites, valor residual se guarda en generador/batería con indice_max
                [~, indice] = max(qlim_elemento);
                indice_max = indices(indice);
                
                [~, indice_bat] = max(qlim_baterias);
                indice_max_baterias = indices_bats(indice_bat);                
            end
            
            % primero baterías
            if ~isempty(indices_bats)
                iter = 0;
                while true
                    iter = iter + 1;
                    % prorratea q_residual dependiendo de qmax
                    suma_qlim_baterias = sum(qlim_baterias);

                    q_nom = q_residual*qlim_baterias/suma_qlim_baterias;
                    indices_a_eliminar = [];
                    for i = 1:length(indices_bats)
                        if abs(q_nom(i)) < abs(qlim_baterias(i))
                            this.Baterias.Qfp(indices_bats(i))= q_nom(i)*sbase;
                            q_residual = q_residual - q_nom(i);
                            qlim_baterias(i) = qlim_baterias(i)-q_nom(i);
                        else
                            % fija al límite
                            this.Baterias.Qfp(indices_bats(i)) = qlim_baterias(i)*sbase;
                            q_residual = q_residual - qlim_baterias(i);
                            indices_a_eliminar = [indices_a_eliminar i];
                        end
                    end

                    if abs(q_residual) > 0.01
                        indices_bats(indices_a_eliminar) = [];
                        qlim_baterias(indices_a_eliminar) = [];
                    else
                        return;
                    end

                    if isempty(indices_bats)
                        % no hay más baterías. 
                        break
                    end
                end
            end
            
            % generadores
            iter = 0;
            while true
                iter = iter + 1;
                % prorratea q_residual dependiendo de qmax
                suma_qlim = sum(qlim_elemento);
                
                q_nom = q_residual*qlim_elemento/suma_qlim;
                indices_a_eliminar = [];
                for i = 1:length(indices)
                    if abs(q_nom(i)) < abs(qlim_elemento(i))
                        this.Generadores.Qfp(indices(i))= q_nom(i)*sbase;
                        q_residual = q_residual - q_nom(i);
                        qlim_elemento(i) = qlim_elemento(i)-q_nom(i);
                    else
                        % fija al límite
                        this.Generadores.Qfp(indices(i)) = qlim_elemento(i)* cParametrosSistemaElectricoPotencia.getInstance().Sbase;
                        q_residual = q_residual - qlim_elemento(i);
                        indices_a_eliminar = [indices_a_eliminar i];
                    end
                end
                
                if abs(q_residual) > 0.01
                    indices(indices_a_eliminar) = [];
                    qlim_elemento(indices_a_eliminar) = [];
                else
                    return;
                end
                
                if isempty(indices)
                    % no hay m?s ?ndices. Significa que queda s?lo el
                    % generador slack, o el estado es 1
                    if ~isempty(gen_slack)
                        qact = this.Generadores.Qfp(gen_slack)/sbase;
                        qact = qact + q_residual;
                        this.Generadores.Qfp(gen_slack) = qact*sbase;
                        return;
                    else
                        % distribuye lo restante en el generador de
                        % indice_max
                        qact = this.Generadores.Qfp(indice_max)/sbase;
                        qact = qact + q_residual;
                        this.Generadores.Qfp(indice_max) = qact*sbase;
                        return;
                    end
                end
                
                if iter > 10
                    texto = ['error de programación. Iteración es mayor a 10. Q residual es aún: ' num2str(q_residual)];
                    error = MException('calcula_flujo_potencia:distribuye_q_residual',texto);
                    throw(error)
                end
            end
        end
        
        function [] = calcula_flujo_n_menos_1( this, po)
            %prueba_n_menos_1: prueba el criterio N-1 por la hora actual
            %   calculas la fujo potencia por cada situacion en que un elemento (Linea o
            %   Transformador) de la lista no es en servicio y guardas los resultos en
            %   resultos_criterio.dat.
            %   Si el sistema todavia es convergente sin el elemento en servicio los
            %   resultados de la flujo potencia se quardan como en fp.dat. Si no se
            %   quardan el Flag
            this.ListaLineas = this.Lineas.Id((abs(this.Lineas.S1)> this.Lineas.Sr*this.pParFP.PorcCargaCriterioN1)&...
                (abs(this.Lineas.S2)> this.Lineas.Sr*this.pParFP.PorcCargaCriterioN1));
            this.ListaTrafos = this.Trafos.Id((abs(this.Trafos.S1)> (this.Trafos.Sr*this.pParFP.PorcCargaCriterioN1))&...
                (abs(this.Trafos.S2)> (this.Trafos.Sr*this.pParFP.PorcCargaCriterioN1)));
            
            this.FlagN1 = 1;
            
            % Lineas
            for i = 1:numel(this.ListaLineas)
                % actualiza matriz Adm
                this.Adm = this.Adm_init;
                [y11, y12, y21, y22] = entrega_cuadripolo_linea(this);
                this.Subestaciones = this.Subestaciones_init;
                n = this.Subestaciones.Id(this.Lineas.Bus1(this.ListaLineas(i)));
                m = this.Subestaciones.Id(this.Lineas.Bus2(this.ListaLineas(i)));
                this.Adm(n,m) = this.Adm(n,m) - y12(this.ListaLineas(i));
                this.Adm(m,n) = this.Adm(m,n) - y21(this.ListaLineas(i));
                this.Adm(n,n) = this.Adm(n,n) - y11(this.ListaLineas(i));
                this.Adm(m,m) = this.Adm(m,m) - y22(this.ListaLineas(i));
                
                supr = struct();
                fields = fieldnames(this.Lineas);
                for f = 1:numel(fields)
                    supr.(fields{f}) = [];
                    supr.(fields{f}) = this.Lineas.(fields{f})(this.ListaLineas(i));
                    this.Lineas.(fields{f})(this.ListaLineas(i)) = [];
                end
                this.num.Lineas = numel(this.Lineas.Id);
                this.Lineas.Id = (1:this.num.Lineas)';
                this.Subestaciones.Lineas = cell(this.num.Subestaciones);
                for f = 1:this.num.Subestaciones
                    this.Subestaciones.Lineas(f) = {[this.Lineas.Id(this.Lineas.Bus1 == f)',...
                        this.Lineas.Id(this.Lineas.Bus2 == f)']};
                end
                
                this.calcula_flujo_potencia(po);
                if this.NivelDebug > 0
                    if this.Flag > 1
                        texto = sprintf('Resultado flujo de potencias para hora %d ,Linea %d\nNo functiona porque Flag = %d',...
                            po, supr.Id_real, this.Flag);
                    else
                        texto = sprintf('Resultado flujo de potencias para hora %d ,Linea %d\nFunctiona y son guadado en cResultadoEvaluacionSEP.m',...
                            po, supr.Id_real);
                    end
                    prot = cProtocolo.getInstance;
                    prot.imprime_texto(this,texto)
                end
                for f = 1:numel(fields)
                    if this.ListaLineas(i) == 1
                        this.Lineas.(fields{f}) = [supr.(fields{f});...
                            this.Lineas.(fields{f})(this.ListaLineas(i):end)];
                    else
                        this.Lineas.(fields{f}) = ...
                            [this.Lineas.(fields{f})(1:this.ListaLineas(i)-1);supr.(fields{f});...
                            this.Lineas.(fields{f})(this.ListaLineas(i):end)];
                    end
                end
            end
            
            % Trafos
            for i = 1:numel(this.ListaTrafos)
                % actualiza matriz Adm
                this.Adm = this.Adm_init;
                [y11, y12, y21, y22] = entrega_cuadripolo_trafo(this);
                this.Subestaciones = this.Subestaciones_init;
                n = this.Subestaciones.Id(this.Trafos.Bus1(this.ListaTrafos(i)));
                m = this.Subestaciones.Id(this.Trafos.Bus2(this.ListaTrafos(i)));
                this.Adm(n,m) = this.Adm(n,m) - y12(this.ListaTrafos(i));
                this.Adm(m,n) = this.Adm(m,n) - y21(this.ListaTrafos(i));
                this.Adm(n,n) = this.Adm(n,n) - y11(this.ListaTrafos(i));
                this.Adm(m,m) = this.Adm(m,m) - y22(this.ListaTrafos(i));
                
                supr = struct();
                fields = fieldnames(this.Trafos);
                for f = 1:numel(fields)
                    supr.(fields{f}) = [];
                    supr.(fields{f}) = this.Trafos.(fields{f})(this.ListaTrafos(i));
                    this.Trafos.(fields{f})(this.ListaTrafos(i)) = [];
                end
                this.num.Trafos = numel(this.Trafos.Id);
                this.Trafos.Id = (1:this.num.Trafos)';
                this.Subestaciones.Trafos = cell(this.num.Subestaciones);
                for f = 1:this.num.Subestaciones
                    this.Subestaciones.Trafos(f) = {[this.Trafos.Id(this.Trafos.Bus1 == f)',...
                        this.Trafos.Id(this.Trafos.Bus2 == f)']};
                end
                
                this.calcula_flujo_potencia(po);
                if this.NivelDebug > 0
                    if this.Flag > 1
                        texto = sprintf('Resultado flujo de potencias para hora %d ,Trafo %d\nNo functiona porque Flag = %d',...
                            po, supr.Id_real, this.Flag);
                    else
                        texto = sprintf('Resultado flujo de potencias para hora %d ,Trafo %d\nFunctiona y son guadado en cResultadoEvaluacionSEP.m',...
                            po, supr.Id_real);
                    end
                    prot = cProtocolo.getInstance;
                    prot.imprime_texto(this,texto)
                end
                for f = 1:numel(fields)
                    if this.ListaTrafos(i) == 1
                        this.Trafos.(fields{f}) = [supr.(fields{f});...
                            this.Trafos.(fields{f})(this.ListaTrafos(i):end)];
                    else
                        this.Trafos.(fields{f}) = ...
                            [this.Trafos.(fields{f})(1:this.ListaTrafos(i)-1);supr.(fields{f});...
                            this.Trafos.(fields{f})(this.ListaTrafos(i):end)];
                    end
                end
            end
            this.FlagN1 = 0;
        end
        
        function copia_parametros_optimizacion(this, parametros)
            this.NivelDetalleResultados = parametros.NivelDetalleResultadosFP;
            this.NivelDebug = parametros.NivelDebugFP;
        end
    end
end