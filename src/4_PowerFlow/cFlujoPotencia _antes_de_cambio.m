classdef cFlujoPotencia < handle
        % clase que representa las subestaciones
    properties
        pmsist = cmSistemaModal.empty
        
        % Punteros con buses, elementos serie y elementos paralelo. Estos
        % cambian dependiendo del subsistema a calcular
        pBuses = cmBus.empty
        pmElementoSerie = cmElementoSerie.empty
        pmElementoParalelo = cmElementoParalelo.empty
        
        pParFP = cParametrosFlujoPotencia.empty

        % Flag del flujo de potencias
        % -1 = no se ha calculado aún (valor por defecto)
        % 0 = convergente
        % 1 = convergente, pero hay violación de los límites de potencia
        %     reactiva en los generadores
        % 2 = no convergente. Se alcanzó el máximo número de iteraciones
        % 3 = no convergente. NaN
        Flag = -1
        
        % índices que conectan los elementos en serie y en paralelo con los
        % modelos modales
        %IndiceElementoRedBus
        %IndiceElementoRedSerie 
        %IndiceElementoRedParalelo
        
        Adm % matriz de admitancia
        J   % matriz jacobiana
        
        % BusesConRegPorTrafo contiene la lista de buses con transformadores
        % reguladores
        % TrafosReg contiene lista con trasformadores reguladores por bus
        % TrafosReg(indice en BusesConRegPorTrafo).Lista = [eserie1 eserie2 ... eserieN] 
        % TrafosReg(indice en BusesConRegPorTrafo).IDBusReg = [idx1 idx2 ... idxM]
        % TrafosReg(indice en BusesConRegPorTrafo).IDBusNoReg = [idx1 idx2 ... idxM]
        % TrafosReg(indice en BusesConRegPorTrafo).PasoActualAdm = [paso1 paso2 ... pasoM]
        BusesConRegPorTrafo
        TrafosReg
                
        
        %Tipobuses indica si es PV, PQ o Slack. Se actualiza en cada
        %iteración
        TipoBuses
        
        %Variables de estado tienene el formato Ángulos (para todos los
        %buses) y después los voltajes
        VarEstado
        
        %Tipo de variable de estado se utiliza para identificar si la
        %variable de estado es el voltaje, el ángulo, o la relacon de transformación de los transformadores
        %('Theta', 'V' o 'TapReg')
        TipoVarEstado

        %Tipo de variable de control del bus. Puede ser 'V' o 'TapReg' para
        %los transformadores reguladores
        TipoVarControl
        
        % Snom contiene las potencias reales (para todos los buses) y 
        % luego las potencias aparentes
        Snom

        %nBuses contiene el número de buses. Es para facilitar lectura del
        %código y no tener que hacerlo a través de length
        nBuses

        % Tipo flujo. Opciones son:
        % AC, DC, Desacoplado
        %Tipo = 'AC'
        NivelDebug = 2
        
        % Estructura que guarda los resultados en format matpower para
        % comparación. Sólo si nivel de debug > 1
        ResMatpower
        
        id_fp = 1 %para utilizar a futuro
    end
    
    methods
        function this = cFlujoPotencia(sep)
            % primero se determina sistemas modales. Eventualmente pueden
            % haber más de un sistema en caso de que existan zonas aisladas

            this.pParFP = cParametrosFlujoPotencia();
            %this.pmsist = cmSistemaModal(sep,this.id_fp);
            this.pmsist = sep.entrega_sistema_modal();
            this.pmsist.inserta_id_fp(this.id_fp);
            
            if this.NivelDebug > 1
                % imprime resultados parciales en archivo externo
                prot = cProtocolo.getInstance;
                prot.imprime_texto('Comienzo del flujo de potencias\n');
                prot.imprime_texto('Sistema eléctrico de potencias para el cálculo del flujo de potencia:');
                sep.imprime_sep();
            end
        end

        function convergencia = clacula_flujo_potencia(this)
            cant_subsistemas = this.pmsist.entrega_cantidad_subsistemas();
            convergencia_subsist = zeros(cant_subsistemas,1);
            if this.NivelDebug > 1
                this.inicializa_estructura_solucion_formato_matpower();
            end
            for i = 1:cant_subsistemas
                convergencia_subsist(i) = this.calcula_flujo_potencia_subsistema(i);
            end
            convergencia = min(convergencia_subsist);
            if this.NivelDebug > 1
                this.guarda_archivo_resultados_matpower();
            end
        end
            
        function convergencia = calcula_flujo_potencia_subsistema(this, nro_subsistema)
            this.pBuses = this.pmsist.entrega_buses(nro_subsistema);
            this.pmElementoSerie = this.pmsist.entrega_elementos_serie(nro_subsistema);
            this.pmElementoParalelo = this.pmsist.entrega_elementos_paralelo(nro_subsistema);

            this.Flag = -1; % valor inicial para subsistema actual
            obliga_verificacion_cambio_pv_pq = false;
            this.construye_matriz_admitancia();
            this.inicializa_variables();
            this.determina_condiciones_iniciales();

            if this.NivelDebug > 1
                this.imprime_estado_variables();
            end
            
            %potencia_total = 0;
            %suma_p_obj = 0;
            iter = 0;
            discreto = false;
            delta_s = zeros(2*this.nBuses,1);
            while true
                ds_total = 0;
                ds_mw_total = 0;
                s_complejo = this.calcula_s_complejo();
                s = zeros(2*this.nBuses,1);
                s(1:this.nBuses) = real(s_complejo);
                s(this.nBuses + 1:2*this.nBuses) = imag(s_complejo);
                
                if this.NivelDebug > 1
                    prot = cProtocolo.getInstance;
                    prot.imprime_vector(s, 's');
                end
                
                %p_sum_act = sum(real(s_aux));
                                
                %desviación de frecuencia
                %dfrecuencia = (p_sum_act - suma_p_obj)/l_ges;
                
                % cálculo criterio convergencia
                for bus = 1:length(this.pBuses)
                    if ~strcmp(this.TipoBuses(bus),'Slack')
                        % potencia activa
                        delta_s(bus) = this.Snom(bus)-s(bus); %+ dfrecuencia*leistungszahl%
                        ds_total = ds_total + delta_s(bus);
                        ds_mw_total = ds_mw_total + abs(delta_s(bus));
                        if ~strcmp(this.TipoBuses(bus),'PV')
                            % Potencia reactiva se verifica sólo para buses PQ
                            delta_s(bus + this.nBuses) = this.Snom(bus + this.nBuses)-s(bus + this.nBuses);
                            ds_total = ds_total + delta_s(bus + this.nBuses);
                            ds_mw_total = ds_mw_total + abs(delta_s(bus + this.nBuses));
                        end
                    end
                end

                if this.NivelDebug > 0
                    prot = cProtocolo.getInstance;
                    prot.imprime_vector(delta_s, 'delta_s');
                    prot.imprime_valor(ds_total, ['ds_total it ' num2str(iter)]);
                    prot.imprime_valor(ds_mw_total, 'ds_mw_total');
                end
                
                % campo tipo de buses PV --> PQ
                cambio_tipo_buses = false;
                if iter > this.pParFP.NumIterSinCambioPVaPQ || obliga_verificacion_cambio_pv_pq
                    % verificar si es necesario cambio de tipo de buses
                    for bus = 1:length(this.pBuses)
                        if strcmp(this.TipoBuses(bus),'PV')
                            if strcmp(this.TipoVarControl{bus},'V')
                                % no es un bus cuyo voltaje es controlado
                                % por un trafo
                                q_consumo = this.pBuses(bus).entrega_q_const_nom();
                                q_inyeccion = s(bus + this.nBuses) + q_consumo;
                                q_min = this.pBuses(bus).entrega_qmin();
                                q_max = this.pBuses(bus).entrega_qmax();
                                if (q_inyeccion < q_min) || (q_inyeccion > q_max)
                                    this.TipoBuses{bus} = 'PQ';
                                    if this.NivelDebug > 1
                                        text = ['Cambio bus ' num2str(bus) ' de PV a PQ porque inyección se encuentra fuera de rango' ...
                                                '. QInyeción: ' num2str(q_inyeccion) '. Q min: ' num2str(q_min) '. Qmax: ' num2str(q_max) '\n'];
                                        cProtocolo.getInstance.imprime_texto(text);
                                    end
                                    if q_inyeccion < q_min
                                        this.Snom(bus + this.nBuses) = q_min - q_consumo;
                                        % cambia Q de elementos que controlan
                                        % tensión para que queden fijos
                                        this.pBuses(bus).fija_q_const_nom_a_qmin();
                                    else
                                        this.Snom(bus + this.nBuses) = q_max - q_consumo;
                                        this.pBuses(bus).fija_q_const_nom_a_qmax();
                                    end
                                    cambio_tipo_buses = true;
                                end
                            else
                                % voltaje controlado por trafo. Hay que
                                % verificar que tap está dentro de los
                                % límites
                                t_tap_actual = this.VarEstado(bus + this.nBuses);
                                trafo = this.entrega_trafo_regulador(this.pBuses(bus), 1, true);
                                id_tap = trafo.entrega_id_tap_regulador();
                                tap_actual = trafo.entrega_tap_dado_t(id_tap, t_tap_actual);
                                tap_max = trafo.entrega_tap_max_regulador();
                                tap_min = trafo.entrega_tap_min_regulador();
                                if tap_actual > tap_max
                                    % fija trafo en tap máximo
                                    tap_max = trafo.entrega_tap_max(id_tap);
                                    trafo.inserta_tap_actual_regulador(tap_max);
                                    this.TipoBuses{bus} = 'PQ';
                                    this.TipoVarControl{bus} = 'V';
                                elseif tap_actual < tap_min
                                    tap_min = trafo.entrega_tap_min(id_tap);
                                    trafo.inserta_tap_actual_regulador(tap_min);
                                    this.TipoBuses{bus} = 'PQ';
                                    this.TipoVarControl{bus} = 'V';
                                end
                            end
                        end
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
                    convergencia = false;
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
                        convergencia = true;
                        this.Flag = 0;
                        break;
                    end
                end
                
                if iter > this.pParFP.MaxNumIter
                    % se alcanzó el máximo número de iteraciones. No hay
                    % convergencia
                    convergencia = false;
                    this.Flag = 2;
                    break;
                end
                
                if (ds_mw_total < this.pParFP.MaxErrorMW) ...
                   && ~isempty(this.TrafosReg) ...
                   && ~discreto
                    % convergió pero aún no se han discretizado los
                    % transformadores reguladores
                    % Pasos:
                    % 1. Discretizar los pasos de los transformadores
                    %    reguladores
                    % 2. Cambiar estado de variables de UE --> U
                    discreto = true;
                    for bus = 1:length(this.pBuses)
                        if strcmp(this.TipoVarControl{bus},'TapReg')
                            % entrega lista de transformadores que regulan
                            % tensión del bus
                            cantidad_trafos = this.entrega_cantidad_trafos_reguladores(this.pBuses(bus));
                            for ittraf = 1:cantidad_trafos
                                paso_actual = this.entrega_paso_trafo_regulador(this.pBuses(bus), ittraf, true);
                                this.inserta_paso_actual_trafo_regulador(round(paso_actual), this.pBuses(bus), ittraf, true);
                            end
                            if cantidad_trafos == 0
                                error = MException('cFlujoPotencia:calcula_flujo_potencia','Variable del bus es TapReg pero no hay transformadores reguladores');
                                throw(error)
                            end
                            %ajustar variables
                            this.VarEstado(bus + this.nBuses) = this.entrega_trafo_regulador(this.pBuses(bus), 1, true).entrega_voltaje_objetivo_pu();
                            this.TipoVarControl{bus} = 'V';
                            this.TipoVarEstado{bus + this.nBuses} = 'V';
                        end
                    end
                end
                
                % nueva iteración
                this.actualiza_matriz_jacobiana();

                if this.NivelDebug > 1
                    prot = cProtocolo.getInstance;
                    prot.imprime_matriz(this.J, ['Matriz Jacobiana sin eliminación en iteracion: ' num2str(iter)]);
                end
                
                %borrar filas y columnas de la barra slack
                slack_encontrada = false;
                indice_a_borrar = [];
                for bus = 1:length(this.pBuses)
                    if strcmp(this.TipoBuses(bus),'Slack')
                        % se borra el ángulo y el voltaje ya que son
                        % conocidos
                        indice_a_borrar = [indice_a_borrar bus];
                        indice_a_borrar = [indice_a_borrar bus + this.nBuses];
                        slack_encontrada = true;
                    elseif strcmp(this.TipoBuses(bus),'PV') && ~strcmp(this.TipoVarControl{bus},'TapReg')
                        % se borra el voltaje, ya que es conocido. El
                        % ángulo se mantiene ya que es desconocido
                        indice_a_borrar = [indice_a_borrar bus + this.nBuses];
                    end
                end
                if ~slack_encontrada
                   error = MException('cFlujoPotencia:callcula_flujo_potencia','No se encontró slack');
                   throw(error)
                end
                % crea indices entre variables de estado y
                % las "nuevas" variables de estado, en donde se borraron
                % los valores conocidos
                VecSol = zeros(length(this.VarEstado)-length(indice_a_borrar),1);
                IndiceVarSol = zeros(length(this.VarEstado),1);
                it_varsol = 1;
                for i = 1:length(this.VarEstado)
                    if find(indice_a_borrar == i)
                        IndiceVarSol(i) = 0;
                    else
                        VecSol(it_varsol) = delta_s(i);
                        IndiceVarSol(i) = it_varsol;
                        it_varsol = it_varsol + 1;                       
                    end
                end

                % borra filas y columnas de la matriz jacobiana
                this.J(:,indice_a_borrar) = [];
                this.J(indice_a_borrar,:) = [];
                
                % resuelve sistema de ecuaciones
                Sol = -inv(this.J)*VecSol;
                if this.NivelDebug > 1
                    prot = cProtocolo.getInstance;
                    prot.imprime_vector(this.VarEstado, 'antiguo vector con variables de estado');
                    prot.imprime_vector(indice_a_borrar, 'indices a borrar');
                    prot.imprime_matriz(this.J, 'Matriz jacobiana sin filas ni columnas');
                    prot.imprime_vector(VecSol, 'VecSol');
                    prot.imprime_vector(IndiceVarSol, 'indice de variables y solucion');
                    prot.imprime_vector(Sol, 'Sol');
                end
                
                % escribe resultados en VarDecision
                for indice = 1:length(this.VarEstado)
                    indice_en_sol = IndiceVarSol(indice);
                    if indice_en_sol > 0
                        if strcmp(this.TipoVarEstado{indice},'Theta')
                            this.VarEstado(indice) = this.VarEstado(indice) - Sol(indice_en_sol);
                        else
                            % V o Treg
                            this.VarEstado(indice) = this.VarEstado(indice) - Sol(indice_en_sol)*this.VarEstado(indice);
                        end
                    end
                end
                if this.NivelDebug > 1
                    prot = cProtocolo.getInstance;
                    prot.imprime_vector(this.VarEstado, 'nuevo vector solucion');
                    this.imprime_estado_variables();
                end
                
                % actualizar paso de los transformadores
                for bus = 1:length(this.pBuses)
                    if strcmp(this.TipoVarControl{bus},'TapReg')
                        cantidad_trafos = this.entrega_cantidad_trafos_reguladores(this.pBuses(bus));
                        for itr = 1:cantidad_trafos
                            this.inserta_paso_actual_trafo_regulador(this.VarEstado(bus + this.nBuses), this.pBuses(bus), itr, true);
                        end
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
                this.imprime_estado_variables();
            end
            
            % Flujo de potencias convergente.
            this.escribe_resultados_fp(nro_subsistema);
            if this.NivelDebug > 1
                cProtocolo.getInstance.imprime_texto(['Flag final del flujo de potencias: ' num2str(this.Flag)]);
                this.guarda_solucion_formato_matpower();
            end
        end
        
        function actualiza_matriz_jacobiana(this)

            this.J = zeros(2*length(this.pBuses));
            dpi_dui = zeros(length(this.pBuses),1);
            dqi_dui = zeros(length(this.pBuses),1);
            dpi_dti = zeros(length(this.pBuses),1);
            dqi_dti = zeros(length(this.pBuses),1);
            for fila =1:length(this.pBuses)
                if strcmp(this.TipoVarControl{fila},'V')
                    ui = this.VarEstado(fila + this.nBuses);
                else
                    % transformador regulador
                    indice = find(this.BusesConRegPorTrafo == this.pBuses(fila), 1);
                    if ~isempty(indice)
                        trafo = this.TrafosReg(indice).Lista(1).entrega_elemento_red();
                        ui = trafo.entrega_voltaje_objetivo_pu();
                    else
                        error = MException('cFlujoPotencia:callcula_flujo_potencia','Variable del bus es TapReg pero no hay transformadores reguladores');
                        throw(error)
                    end

                end
                ti = this.VarEstado(fila);

                indices_columnas = find(this.Adm(fila, :) ~= 0);
                for nro_col = 1:length(indices_columnas)
                    col = indices_columnas(nro_col);
                    if col == fila
                        %diagonal
                        if strcmp(this.TipoVarControl{fila},'V')
                            % derivadas c/r al voltaje para buses no
                            % regulados por transformadores reguladores
                            % En caso de que el bus sea regulado por un
                            % transformador, los valores se agregan después
                            % a partir de los elementos fuera de la
                            % diagonal
                            yrii = real(this.Adm(fila,col));
                            yiii = imag(this.Adm(fila,col));
                            dpi_dui(fila) = dpi_dui(fila) + 2*ui^2*yrii;
                            dqi_dui(fila) = dqi_dui(fila) - 2*ui^2*yiii;
                        end
                    else
                        %fuera de la diagonal
                        if strcmp(this.TipoVarControl{col},'V')
                            uj = this.VarEstado(col + this.nBuses);
                        else
                            % columna tiene transformador regulador para ese lado. El voltaje lo define el voltaje objetivo
                            indice = find(this.BusesConRegPorTrafo == this.pBuses(col), 1);
                            if ~isempty(indice)
                                trafo = this.TrafosReg(indice).Lista(1).entrega_elemento_red();
                                uj = trafo.entrega_voltaje_objetivo_pu();
                            else
                                error = MException('cFlujoPotencia:callcula_flujo_potencia','Variable del bus es TapReg pero no hay transformadores reguladores');
                                throw(error)
                            end
                        end

                        tj = this.VarEstado(col);
                        sinij = sin(ti-tj);
                        cosij = cos(ti-tj);

                        yrij = real(this.Adm(fila,col));
                        yiij = imag(this.Adm(fila,col));
                            
                        % derivadas con respecto a theta. No hay distinción
                        % entre si el bus está regulado por un trafo
                        dpi_dtj = ui*uj*(yrij*sinij-yiij*cosij);
                        dqi_dtj = -ui*uj*(yrij*cosij+yiij*sinij);

                        this.J(fila               ,col) = dpi_dtj;
                        this.J(fila + this.nBuses ,col) = dqi_dtj;

                        % agrega elementos para la diagonal para las
                        % derivadas con respecto a theta
                        dpi_dti(fila) = dpi_dti(fila) - dpi_dtj; 
                        dqi_dti(fila) = dqi_dti(fila) - dqi_dtj;

                        % derivadas con respecto a u o a t. En este caso hay que
                        % hacer una distinción entre buses regulados por
                        % transformadores y los que no
                        
                        % agrega elemento para la diagonal en caso de que
                        % el bus col no sea regulado por un transformador
                        % regulador
                        if strcmp(this.TipoVarControl{fila},'V')
                            dpi_dui(fila) = dpi_dui(fila) + ui*uj*(yrij*cosij+yiij*sinij);
                            dqi_dui(fila) = dqi_dui(fila) + ui*uj*(yrij*sinij-yiij*cosij);
                        end
                        
                        if strcmp(this.TipoVarControl{col},'V')
                            dpi_duj = ui*uj*(yrij*cosij+yiij*sinij);
                            dqi_duj = ui*uj*(yrij*sinij-yiij*cosij);

                            this.J(fila               ,col+ this.nBuses) = dpi_duj;
                            this.J(fila + this.nBuses ,col+ this.nBuses) = dqi_duj;
                        else
                            % columna de un bus regulado por trafo
                            % verificar si transformador conecta también a
                            % esta fila
                            idx_en_bus = find(this.BusesConRegPorTrafo == this.pBuses(col));
                            if isempty(idx_en_bus)
                                error = MException('cFlujoPotencia:actualiza_matriz_jacobiana','bus tiene regulación pero no se encuentra en BusesConRegPorTrafo');
                                throw(error)
                            end
                            idx_en_trafo = find(this.TrafosReg(idx_en_bus).IDBusReg == col, 1);
                            if isempty(idx_en_trafo)
                                error = MException('cFlujoPotencia:actualiza_matriz_jacobiana','No se encuentra índice con el bus regulado');
                                throw(error)
                            end
                            
                            if length(this.TrafosReg(idx_en_bus).IDBusNoReg) < idx_en_trafo
                                error = MException('cFlujoPotencia:actualiza_matriz_jacobiana','No se encuentra índice con el bus no regulado');
                                throw(error)
                            end
                            
                            id_bus_no_regulado = this.TrafosReg(idx_en_bus).IDBusNoReg(idx_en_trafo);
                            if id_bus_no_regulado ~= fila
                                % transformador reg. parte no regulada no corresponde a fila
                                % se elimina valor de fuera de diagonal (ya
                                % que trafo no conecta con fila actual)
                                % dPi/dt und dQi/dt
                                this.J(fila               ,col+ this.nBuses) = 0;
                                this.J(fila + this.nBuses ,col+ this.nBuses) = 0;
                            else
                                % transformador regulador conecta ambos
                                % buses. Estrategia: se "limpia"
                                % dependencia de la matriz de admitancia
                                % con respecto al tap regulador y luego se calculan las
                                % derivadas.
                                trafo = this.TrafosReg(idx_en_bus).Lista(1).entrega_elemento_red();
                                t_tap = trafo.entrega_t_tap_regulador_abs();
                                
                                yii = this.Adm(fila,fila); %yji ya que va de j a i y no al revés
                                yjj = this.Adm(col,col);
                                yij = this.Adm(fila, col);
                                yji = this.Adm(col, fila);
                                
                                % determinar si regulación es en el lado de
                                % alta o baja tensión
                                se_reg = trafo.entrega_subestacion_regulada();
                                se_no_reg = trafo.entrega_subestacion_no_regulada();
                                
                                if strcmp(trafo.entrega_nombre_lado_controlado(), 'secundario')
                                    yij = yij/t_tap;
                                    yji = yji/t_tap;
                                    yjj = yjj/t_tap^2;
                                else
                                    yii = yii/t_tap^2;
                                    yij = yij/t_tap;
                                    yji = yji/t_tap;
                                end
                                
                                yrii = real(yii);
                                yiii = imag(yii);
                                
                                yrjj = real(yjj);
                                yijj = imag(yjj);
                                
                                yrij = real(yij);
                                yiij = imag(yij);
                                
                                yrji = real(yji);
                                yiji = imag(yji);
                                
                                if strcmp(trafo.entrega_nombre_lado_controlado(), 'secundario')
                                    dpi_dtap = ui*uj*t_tap*(yrij*cos(ti-tj)+yiij*sin(ti-tj));
                                    dqi_dtap = ui*uj*t_tap*(yrij*sin(ti-tj)-yiij*cos(ti-tj));
                                    
                                    dpj_dtap = 2*yrjj*t_tap^2*uj^2+ui*uj*t_tap*(yrji*cos(tj-ti)+yiji*sin(tj-ti));
                                    dqj_dtap = -2*yijj*t_tap^2*uj^2+ui*uj*t_tap*(yrji*sin(tj-ti)-yiji*cos(tj-ti));
                                else
                                    dpi_dtap = 2*yrii*t_tap^2*ui^2+ui*uj*t_tap*(yrij*cos(ti-tj)+yiij*sin(ti-tj)); 
                                    dqi_dtap = -2*yiii*t_tap^2*ui^2+ui*uj*t_tap*(yrij*sin(ti-tj)-yiij*cos(ti-tj));
                                    
                                    dpj_dtap = ui*uj*t_tap*(yrji*cos(tj-ti)+yiji*sin(tj-ti));
                                    dqj_dtap = ui*uj*t_tap*(yrji*sin(tj-ti)-yiji*cos(tj-ti));
                                end
                                    
                                % se mantiene nomenclatura, a pesar de que
                                % en este caso se trata de dpi_dt y dqui_dt
                                dpi_dui(col) =  dpi_dtap;
                                dqi_dui(col) =  dqi_dtap;

                                % elementos fuera de la diagonal
                                this.J(fila            , col+this.nBuses) = dpj_dtap;
                                this.J(fila+this.nBuses, col+this.nBuses) = dqj_dtap; 
                            end
                        end
                    end
                end
            end
            
            % ingresar valores en diagonal
            for fila = 1:length(this.pBuses)
                % dP 
                this.J(fila, fila) = dpi_dti(fila);
                this.J(fila, fila + this.nBuses) = dpi_dui(fila);
                
                % dQ
                this.J(fila + this.nBuses, fila) = dqi_dti(fila);
                this.J(fila + this.nBuses, fila + this.nBuses) = dqi_dui(fila);
            end
            
            desacoplado = false;
            if desacoplado
                %for i_fila = 1:length(this.pBuses)
                %algo
            end
        end
        
        function trafo = entrega_trafo_regulador(this, bus, nr_trafo, obligatorio)
            indice = this.BusesConRegPorTrafo == bus;
            if ~isempty(indice)
                if length(this.TrafosReg(indice).Lista) >= nr_trafo
                    trafo = this.TrafosReg(indice).Lista(nr_trafo).entrega_elemento_red();
                end
            else
                if obligatorio
                    error = MException('cFlujoPotencia:entregea_trafo_regulador','no se pudo encontrar trafo regulador y flag es obligatorio');
                    throw(error)
                end
                trafo = cTransformador.empty;
            end
        end
        
        function paso = entrega_paso_trafo_regulador(this, bus, nr_trafo, obligatorio)
            indice = this.BusesConRegPorTrafo == bus;
            if ~isempty(indice)
                if length(this.TrafosReg(indice).Lista) >= nr_trafo
                    paso = this.TrafosReg(indice).PasoActualAdm(nr_trafo);
                end
            else
                if obligatorio
                    error = MException('cFlujoPotencia:entrega_paso_trafo_regulador','No se pudo encontrar trafo regulador y flag es obligatorio');
                    throw(error)
                end
                paso = 0;
            end
        end
            
        function inserta_paso_actual_trafo_regulador(this, valor_t_tap, bus, nr_trafo, obligatorio)
            indice = this.BusesConRegPorTrafo == bus;
            if ~isempty(indice)
                if length(this.TrafosReg(indice).Lista) >= nr_trafo
                    trafo = this.TrafosReg(indice).Lista(nr_trafo).entrega_elemento_red();
                    id_tap_regulador = trafo.entrega_id_tap_controlador();
                    tap_act = trafo.entrega_tap_dado_t(id_tap_regulador, valor_t_tap);
                    trafo.inserta_tap_actual_regulador(tap_act);
                else
                    error = MException('cFlujoPotencia:inserta_paso_actual_trafo_regulador','indice fuera de rango. Error de programación');
                    throw(error)
                end
            else
                if obligatorio
                    error = MException('cFlujoPotencia:inserta_paso_actual_trafo_regulador','No se pudo encontrar trafo regulador y flag es obligatorio');
                    throw(error)
                end
            end
        end
        
        function cantidad = entrega_cantidad_trafos_reguladores(this, bus)
            indice = this.BusesConRegPorTrafo == bus;
            cantidad = 0;
            if ~isempty(indice)
                cantidad = length(this.TrafosReg(indice).Lista);
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
        
        function construye_matriz_admitancia(this)
            % 1. obtención de los parámetros de elementos en serie
            this.Adm = zeros(length(this.pBuses));
            for eserie = 1:length(this.pmElementoSerie)
                [y11, y12, y21, y22] = this.pmElementoSerie(eserie).entrega_cuadripolo();
                n = this.pmElementoSerie(eserie).entrega_bus1().entrega_id();
                m = this.pmElementoSerie(eserie).entrega_bus2().entrega_id();
                
                % signos están considerados en cálculo de cuadripolos. Aquí
                % sólo hay que ingresar los datos
                this.Adm(n,m) = this.Adm(n,m) + y12;
                this.Adm(m,n) = this.Adm(m,n) + y21;
                this.Adm(n,n) = this.Adm(n,n) + y11;
                this.Adm(m,m) = this.Adm(m,m) + y22;
            end
            
            % 2. Elementos paralelos
            for epar = 1:length(this.pmElementoParalelo)
                bus = this.pmElementoParalelo(epar).entrega_bus(); 
                n = bus.entrega_id();
                el_red = this.pmElementoParalelo(epar).entrega_elemento_red();
                if isa(el_red, 'cCondensador') || isa(el_red, 'cReactor')
                    ynn = el_red.entrega_dipolo();
                    this.Adm(n,n) = this.Adm(n,n) + ynn;
                elseif isa(el_red, 'cConsumo')
                    if el_red.tiene_dependencia_voltaje()
                        ynn = el_red.entrega_dipolo();
                        this.Adm(n,n) = this.Adm(n,n) + ynn;
                    end
                end
            end
            if this.NivelDebug > 1
                prot = cProtocolo.getInstance;
                prot.imprime_matriz(this.Adm, 'Matriz Admitancia');
            end
        end

        function determina_condiciones_iniciales(this)
            % determina voltajes y ángulos de inicio
            % eventualmente falta agregar un mejor método
            % Por ahora, todos los voltajes en las barras PQ = valor nominal
            % y para las barras PV = valor voltaje objetivo
            
            for bus = 1:this.nBuses

                this.VarEstado(bus) = 0; %ángulo inicial
                if strcmp(this.TipoBuses{bus}, 'PV') || strcmp(this.TipoBuses{bus}, 'Slack')
                    this.VarEstado(this.nBuses + bus) = this.pBuses(bus).entrega_voltaje_objetivo();
                else
                    this.VarEstado(this.nBuses + bus) = 1.02;
                end
            end
            
            % asumiendo que son pocos los transformadores reguladores, es
            % más eficiente reemplazar valor original. Como en este caso se
            % están determinando las condiciones iniciales, no es necesario
            % verificar si el bus es PQ o PV
            for i = 1:length(this.BusesConRegPorTrafo)
                %trafo = this.TrafosReg(i).Lista(1);  %todos los trafos son iguales
                id_bus = this.BusesConRegPorTrafo(i).entrega_id();
                this.VarEstado(id_bus + this.nBuses) = this.TrafosReg(i).Lista(1).entrega_elemento_red().entrega_t_tap_regulador_abs();
                this.TipoBuses{id_bus} = 'PV';
            end
        end

        function inicializa_variables(this)
            % se identifican barras PV, PQ, Slack
            if this.NivelDebug > 1
                prot = cProtocolo.getInstance;
                prot.imprime_texto('Inicializa variables');
            end
            
            this.nBuses = length(this.pBuses);
            this.VarEstado = zeros(2*this.nBuses,1);
            this.TipoVarEstado = cell(2*this.nBuses,1);
            this.Snom = zeros(2*this.nBuses,1);
            this.TipoBuses = cell(this.nBuses,1);
            this.TipoVarControl = cell(this.nBuses,1);
            
            for bus = 1:this.nBuses
                this.TipoVarControl{bus} = 'V'; %valor por defecto
                this.TipoBuses{bus} = this.pBuses(bus).entrega_tipo_bus_entrada();
                this.Snom(bus) = this.pBuses(bus).entrega_p_const_nom();
                this.Snom(this.nBuses + bus) = this.pBuses(bus).entrega_q_const_nom();
                this.TipoVarEstado{bus} = 'Theta';
                this.TipoVarEstado{bus+this.nBuses} = 'V'; %valor por defecto
                
                % identifica si hay transformadores con regulación de
                % tensión para este bus
                nro_conexiones = this.pBuses(bus).entrega_cantidad_conexiones();
                for idx= 1:nro_conexiones
                    eserie = this.pBuses(bus).entrega_conexion(idx);
                    % por ahora sólo transformadores 2D implementados
                    if isa(eserie.entrega_elemento_red(),'cTransformador2D')
                        trafo = eserie.entrega_elemento_red();
                        if ~trafo.controla_tension()
                            continue;
                        end
                        % Transformador controla tensión. Verifica que este
                        % bus sea el bus regulado
                        se_reg = trafo.entrega_subestacion_regulada();
                        if se_reg ~= this.pBuses(bus).entrega_elemento_red()
                            continue;
                        end
                        
                        % transformador regula este bus
                        % a continuación se identifica el bus no
                        % regulado
                        bus1 = this.pBuses(bus).entrega_conexion(idx).entrega_bus1();
                        if bus1 == this.pBuses(bus)
                            bus_no_reg = this.pBuses(bus).entrega_conexion(idx).entrega_bus2();
                        else
                            bus_no_reg = bus1;
                        end
                        
                        if isempty(find(this.BusesConRegPorTrafo == this.pBuses(bus), 1))
                            % aún no se ha ingresado el transformador
                            % regulador
                            this.BusesConRegPorTrafo = [this.BusesConRegPorTrafo this.pBuses(bus)];
                            indice = length(this.BusesConRegPorTrafo);
                            this.TrafosReg(indice).Lista(1) = eserie;
                            this.TrafosReg(indice).IDBusReg(1) = bus;
                            this.TrafosReg(indice).IDBusNoReg(1) = bus_no_reg.entrega_id();
                            this.TrafosReg(indice).PasoActualAdm(1) = trafo.entrega_tap_actual(); 
                            this.TipoVarControl{bus} = 'TapReg';
                            this.TipoVarEstado{bus+this.nBuses} = 'Treg';
                            eserie.entrega_elemento_red().inserta_controla_tension_fp(true);
                        else
                            % ya existe un transformador regulador
                            % para este bus. Hay que verificar que
                            % sean paralelos
                            indice = this.BusesConRegPorTrafo == this.pBuses(bus);
                            for itLista = 1:length(this.TrafosReg(indice).Lista)
                                eserie_existente = this.TrafosReg(indice).Lista(itLista);
                                if ~eserie.es_paralelo(eserie_existente)
                                    error = MException('cFlujoPotencia:inicializa_tipo_variables_decision','existen dos transformadores que regulan el mismo nodo pero no son paralelos');
                                    throw(error)
                                end
                            end
                            %inserta datos
                            this.TrafosReg(indice).Lista = [this.TrafosReg(indice).Lista eserie];
                            this.TrafosReg(indice).IDBusReg = [this.TrafosReg(indice).IDBusReg bus];
                            this.TrafosReg(indice).PasoActualAdm = [this.TrafosReg(indice).PasoActualAdm trafo.entrega_tap_actual()];                                                 
                            this.TrafosReg(indice).IDBusNoReg = [this.TrafosReg(indice).IDBusNoReg bus_no_reg.entrega_id()];
                        end
                    end
                end
            end
        end
        
        function imprime_estado_variables(this)
            % varargin indica si ángulos se imprimen en radianes o grados
            prot = cProtocolo.getInstance;
            prot.imprime_texto('variables y estados');

            prot.imprime_texto('Tipo buses entrada');
            texto = sprintf('%10s %10s', 'Bus', 'Tipo bus');
            prot.imprime_texto(texto);
            for bus = 1:length(this.pBuses)
                texto = sprintf('%10s %10s %10s', num2str(bus), this.TipoBuses{bus});
                prot.imprime_texto(texto);
            end
            
            prot.imprime_texto('Valores vector de estados');
            texto = sprintf('%10s %10s %10s %10s', 'Nr.Var', 'Bus', 'Tipo', 'Valor');
            prot.imprime_texto(texto);
            for bus = 1:length(this.pBuses)
                % primero angulos
                texto = sprintf('%10s %10s %10s %10s %10s', num2str(bus), num2str(bus), 'Theta', num2str(this.VarEstado(bus)), '(', num2str(this.VarEstado(bus)/pi*180), ' grados)');
                prot.imprime_texto(texto);
            end
            for bus = 1:length(this.pBuses)
                % voltajes o tap de transformadores
                texto = sprintf('%10s %10s %10s', num2str(bus + this.nBuses), num2str(bus), this.TipoVarControl{bus}, num2str(this.VarEstado(bus + this.nBuses)));
                prot.imprime_texto(texto);
            end
            
            prot.imprime_texto('Snom:');
            texto = sprintf('%10s %10s %10s %10s', 'Nr.Var', 'Bus', 'Tipo', 'Valor');
            prot.imprime_texto(texto);
            for bus = 1:length(this.pBuses)
                % primero Pnom
                texto = sprintf('%10s %10s %10s %10s', num2str(bus), num2str(bus), 'MW', num2str(this.Snom(bus)));
                prot.imprime_texto(texto);
            end
            for bus = 1:length(this.pBuses)
                % Qnom
                texto = sprintf('%10s %10s %10s %10s', num2str(bus + this.nBuses), num2str(bus), 'MVA', num2str(this.Snom(bus + this.nBuses)));
                prot.imprime_texto(texto);
            end
        end
        
        function s_complejo = calcula_s_complejo(this)
            %entrega la potencia como resultado del sistema de
            %ecuaciones
            % S = diag(U)*conj(Y)*conj(U)
            u_bus = zeros(this.nBuses,1);
            for bus = 1:length(this.pBuses)
                if strcmp(this.TipoVarControl{bus},'V')
                    u = this.VarEstado(bus + this.nBuses);
                else     
                    u = this.entrega_trafo_regulador(this.pBuses(bus), 1, true).entrega_voltaje_objetivo_pu();
                end
                
                theta = this.VarEstado(bus);
                val_real = u*cos(theta);
                val_imag = u*sin(theta);
                % u_bus contiene voltaje de los buses
                u_bus(bus) = complex(val_real, val_imag);
            end
            
            s_complejo = diag(u_bus)*conj(this.Adm)*conj(u_bus);
            if this.NivelDebug > 1
                prot = cProtocolo.getInstance;
                prot.imprime_vector(u_bus, 'u_bus');
                prot.imprime_vector(s_complejo, 's_complejo');
            end
                        
            %DEBUG
%             u = zeros(length(this.pBuses),1);
%             t = zeros(length(this.pBuses),1);
%             for bus = 1:length(this.pBuses)
%                 if strcmp(this.TipoVarControl{bus},'V')
%                     u(bus) = this.VarEstado(bus + this.nBuses);
%                 else     
%                     u(bus) = this.entrega_trafo_regulador(this.pBuses(bus), 1, true).entrega_voltaje_objetivo_pu();
%                 end
%                 
%                 t(bus) = this.VarEstado(bus);
%             end
%             
%             p = zeros(length(this.pBuses),1);
%             q = zeros(length(this.pBuses),1);
%             for k = 1:length(this.pBuses)
%                 for m = 1:length(this.pBuses)
%                     p(k) = p(k) + u(k)*u(m)*(real(this.Adm(k,m))*cos(t(k)-t(m))+imag(this.Adm(k,m))*sin(t(k)-t(m)));
%                     q(k) = q(k) + u(k)*u(m)*(real(this.Adm(k,m))*sin(t(k)-t(m))-imag(this.Adm(k,m))*cos(t(k)-t(m)));
%                 end
%             end
%             this.imprime_vector(p, this.nombre_archivo, 'Pcalc');
%             this.imprime_vector(q, this.nombre_archivo, 'Qcalc');
            
        end
        
        function escribe_resultados_fp(this, nro_subsistema)
            % escribe resultados del flujo de potencias para subsistema actual

            if this.Flag > 1
                %Flujo de potencias no convergente. Se eliminan los
                %resultados en los elementos de red
                this.pmsist.inserta_resultado_fp_no_convergente(nro_subsistema, this.id_fp);
                return
            end

            s_complejo = this.calcula_s_complejo();
            delta_s = complex(this.Snom(1:this.nBuses), this.Snom(this.nBuses + 1:2*this.nBuses)) - s_complejo;
            if this.NivelDebug > 1
                prot = cProtocolo.getInstance;
                prot.imprime_vector(delta_s, 'delta_s_fin');
            end            
            % ingresa valores para cálculo de resultado
            for bus = 1:length(this.pBuses)
                this.pBuses(bus).inserta_angulo(this.VarEstado(bus));
                this.pBuses(bus).inserta_voltaje(this.VarEstado(bus + this.nBuses));
                this.pBuses(bus).entrega_elemento_red().inserta_resultados_fp_en_pu(this.id_fp, this.VarEstado(bus + this.nBuses), this.VarEstado(bus));
                this.pBuses(bus).entrega_elemento_red().inserta_es_slack(this.pBuses(bus).es_slack());
                estado = this.pBuses(bus).inserta_resultados_fp_elementos_paralelos(delta_s(bus));
            end
            
            if estado > 0
                % hay violación de los límites de los generadores. Se
                % actualiza el Flag
                this.Flag = 1;
            end
            
            % Flujos de los elementos en serie
            for eserie = 1:length(this.pmElementoSerie)
                this.pmElementoSerie(eserie).calcula_flujos();
                perdidas_p = this.pmElementoSerie(eserie).entrega_perdidas_p();
                perdidas_q = this.pmElementoSerie(eserie).entrega_perdidas_q();
                this.pmsist.agrega_perdidas_p(nro_subsistema, perdidas_p);
                this.pmsist.agrega_perdidas_q(nro_subsistema, perdidas_q);
            end
        end
        
        function guarda_solucion_formato_matpower(this)
            % Guarda solución en archivo .m para comparar resultados con
            % matpower
            
            % resultado buses
            for i = 1:length(this.pBuses)
                id = this.pBuses(i).entrega_id_global();
                this.ResMatpower.bus(id,1) = id;
                if strcmp(this.TipoBuses{i}, 'PQ') || strcmp(this.TipoBuses{i}, 'Pasivo')
                    this.ResMatpower.bus(id,2) = 1;
                elseif strcmp(this.TipoBuses{i}, 'PV')
                    this.ResMatpower.bus(id,2) = 2;
                elseif strcmp(this.TipoBuses{i}, 'Slack')
                    this.ResMatpower.bus(id,2) = 3;
                else
                    texto = ['Error de programación. Este tipo de bus (' this.TipoBuses{i} ') no corresponde'];
                    error = MException('cFlujoPotencia:guarda_solucion_formato_matpower',texto);
                    throw(error)
                end
                s = this.pBuses(i).entrega_consumo_constante_fp();
                this.ResMatpower.bus(id,3) = real(s);
                this.ResMatpower.bus(id,4) = imag(s);

                % TODO RAMRAM: Falta ver qué es exactamente Gs y Bs en
                % matpower (por ahora asumo que son los consumos
                % dependientes del voltaje + reactores y condensadores)
                s = this.pBuses(i).entrega_consumo_dep_voltaje_fp();
                this.ResMatpower.bus(id,5) = real(s);
                this.ResMatpower.bus(id,6) = imag(s);
                
                s = this.pBuses(i).entrega_inyeccion_reactivos_fp();
                this.ResMatpower.bus(id,5) = this.ResMatpower.bus(id,5) + real(s);
                this.ResMatpower.bus(id,6) = this.ResMatpower.bus(id,6) + imag(s);
                
                this.ResMatpower.bus(id,7) = this.pBuses(i).entrega_id_subsistema();
                this.ResMatpower.bus(id,8) = this.pBuses(i).entrega_voltaje();
                this.ResMatpower.bus(id,9) = this.pBuses(i).entrega_angulo()/pi*180;
                this.ResMatpower.bus(id,10) = this.pBuses(i).entrega_elemento_red().entrega_vbase();
            end
            
            % resultados generadores
            id_gen = 0;
            for i = 1:length(this.pmElementoParalelo)
                el_red = this.pmElementoParalelo(i).entrega_elemento_red();
                if isa(el_red, 'cGenerador')
                    id_gen = id_gen + 1;
                    %id_gen = this.pmElementoParalelo(i).entrega_id_global();
                    id_bus = this.pmElementoParalelo(i).entrega_bus().entrega_id_global();
                    this.ResMatpower.gen(id_gen, 1) = id_bus;
                    this.ResMatpower.gen(id_gen, 2) = el_red.entrega_p_fp();
                    this.ResMatpower.gen(id_gen, 3) = el_red.entrega_q_fp();
                    this.ResMatpower.gen(id_gen, 4) = el_red.entrega_qmax();
                    this.ResMatpower.gen(id_gen, 5) = el_red.entrega_qmin();
                    if el_red.controla_tension()
                        this.ResMatpower.gen(id_gen, 6) = el_red.entrega_voltaje_objetivo_pu();
                    else
                        this.ResMatpower.gen(id_gen, 6) = 0;
                    end
                    this.ResMatpower.gen(id_gen, 7) = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
                    this.ResMatpower.gen(id_gen, 8) = 1;  % el sistema modal sólo tiene generadores en servicio
                    this.ResMatpower.gen(id_gen, 9) = el_red.entrega_pmax();
                    this.ResMatpower.gen(id_gen, 10) = el_red.entrega_pmin();
                end
            end
                
            %branches
            for i = 1:length(this.pmElementoSerie)
                el_red = this.pmElementoSerie(i).entrega_elemento_red();
                id_serie = this.pmElementoSerie(i).entrega_id_global();
                id_bus1 = this.pmElementoSerie(i).entrega_bus1().entrega_id_global();
                id_bus2 = this.pmElementoSerie(i).entrega_bus2().entrega_id_global();
                this.ResMatpower.branch(id_serie,1) = id_bus1;
                this.ResMatpower.branch(id_serie,2) = id_bus2;
                this.ResMatpower.branch(id_serie,3) = el_red.entrega_resistencia_pu();
                this.ResMatpower.branch(id_serie,4) = el_red.entrega_reactancia_pu();
                this.ResMatpower.branch(id_serie,5) = el_red.entrega_susceptancia_pu();
                this.ResMatpower.branch(id_serie,6) = el_red.entrega_sr();
                this.ResMatpower.branch(id_serie,7) = el_red.entrega_sr(); %por ahora sólo un límite
                this.ResMatpower.branch(id_serie,8) = el_red.entrega_sr();
                if isa(el_red, 'cTransformador')
                    this.ResMatpower.branch(id_serie,9) = el_red.entrega_t_tap_secundario();
                    %this.ResMatpower.branch(id_serie,10) = el_red.entrega_desfase();
                else
                    this.ResMatpower.branch(id_serie,9) = 0;
                    this.ResMatpower.branch(id_serie,10) = 0; 
                end
                this.ResMatpower.branch(id_serie,11) = 1; %siempre en servicio para el sistema modal
            end
        end
        
        function inicializa_estructura_solucion_formato_matpower(this)
            cant_buses = this.pmsist.entrega_cantidad_buses();
            this.ResMatpower.bus = zeros(cant_buses, 13);
            
            cant_generadores = this.pmsist.entrega_cantidad_generadores();
            this.ResMatpower.gen = zeros(cant_generadores,21);
            
            cant_conexiones = this.pmsist.entrega_cantidad_conexiones();
            this.ResMatpower.branch = zeros(cant_conexiones,17);
        end 
        
        function guarda_archivo_resultados_matpower(this)
            savefile = './output/ResFP.mat';
            Res = this.ResMatpower;
            save(savefile,'-struct', 'Res');
        end
    end
end

    