classdef cFlujoPotencia_orig < handle
        % clase que representa las subestaciones
    properties
        pmsist = cmSistemaModal.empty
        pBuses = cmBus.empty
        pmElementoSerie = cmElementoSerie.empty
        pmElementoParalelo = cmElementoParalelo.empty
        
        pParFP = cParametrosFlujoPotencia.empty
        
        % índices que conectan los elementos en serie y en paralelo con los
        % modelos modales
        %IndiceElementoRedBus
        %IndiceElementoRedSerie 
        %IndiceElementoRedParalelo
        
        Adm % matriz de admitancia
        J   % matriz jacobiana
        
        % TrafosReg contiene lista con trasformadores reguladores por bus
        % TrafosReg(indice en BusesConTrafosReg).Lista = [eserie1 eserie2 ... eserieN] 
        % TrafosReg(indice en BusesConTrafosReg).IndiceBusReg = [idx1 idx2 ... idxM]
        % TrafosReg(indice en BusesConTrafosReg).IndiceBusNoReg = [idx1 idx2 ... idxM]        
        TrafosReg
        BusesConTrafosReg
        
        TipoVarDecision
        VarDecision
        
        %Tipo de variable de decision en matriz jacobiana
        JTipoVarDecision
        
        %por cada variable, se determina si el tipo de variable de control 
        %es el voltaje, ángulo o tap de los
        %transformadores reguladores)
        
        % Tipo flujo. Opciones son:
        % AC, DC, Desacoplado
        %Tipo = 'AC'
        NivelDebug = 2
        nombre_archivo = './output/fp.dat'
    end
    
    methods
        function this = cFlujoPotencia_orig(sep)
            % primero se determina sistemas modales. Eventualmente pueden
            % haber más de un sistema en caso de que existan zonas aisladas
            this.pmsist = cmSistemaModal(sep);
            this.pParFP = cParametrosFlujoPotencia();

            if this.NivelDebug > 1
                % imprime resultados parciales en archivo externo
                docID = fopen(this.nombre_archivo,'w');
                fprintf(docID, 'Comienzo del flujo de potencias\n');
                fprintf(docID, '\n');
                fprintf(docID, 'Sistema eléctrico de potencias para el cálculo del flujo de potencia:');
                fclose(docID);
                sep.imprime_sep('./output/fp.dat', false); %false indica que archivo no se sobre-escribe, sino que copia al final
            end

        end

        function convergencia = clacula_flujo_potencia(this)
            cant_subsistemas = this.pmsist.entrega_cantidad_subsistemas();
            convergencia_subsist = zeros(cant_subsistemas,1);
            for i = 1:cant_subsistemas
                convergencia_subsist(i) = this.calcula_flujo_potencia_subsistema(i);
            end
            convergencia = min(convergencia_subsist);
        end
            
        function convergencia = calcula_flujo_potencia_subsistema(this, nro_subsistema)
            this.pBuses = this.pmsist.entrega_buses(nro_subsistema);
            this.pmElementoSerie = this.pmsist.entrega_elementos_serie(nro_subsistema);
            this.pmElementoParalelo = this.pmsist.entrega_elementos_paralelo(nro_subsistema);

            this.construye_matriz_admitancia();
            this.determina_valores_iniciales();
            this.inicializa_tipo_variables();

            % vector objetivo: voltajes y ángulos de los buses
            % Formato: 
            % indices impares = voltaje o relación de transformación para transformadores reguladores
            % indices pares = ángulos de voltajes
            % se incluyen voltajes y ángulos de la slack, aunque después se
            % eliminan durante el cálculo
            this.VarDecision = zeros(2*length(this.pBuses),1); 
            
            % determina valor vector objetivo, potencia aparente y variación
            % s_nom y delta_s tienen las mismas dimensiones de las
            % variables de decisión. Primero va P y luego va Q
            s_nom = zeros(2*length(this.pBuses),1);
            delta_s = zeros(2*length(this.pBuses),1);
            
            %potencia_total = 0;
            %suma_p_obj = 0;
            
            if this.NivelDebug > 1
                docID = fopen(this.nombre_archivo, 'a+');
                fprintf(docID, strcat('Valores iniciales para flujo de potencia', '\n'));
                texto = sprintf('%10s %10s %10s', 'VarDec.', 'Bus', 'TipoVar', 'Valor');
                fprintf(docID, strcat(texto, '\n'));
            end
            for bus = 1:length(this.pBuses)
                if strcmp(this.TipoVarDecision{2*bus-1},'V')
                    this.VarDecision(2*bus-1) = this.pBuses.entrega_voltaje();
                    if this.NivelDebug > 1
                        texto = sprintf('%10s %10s %10s %10s', num2str(2*bus-1), num2str(bus), 'V', num2str(this.VarDecision(2*bus-1)));
                        fprintf(docID, strcat(texto, '\n'));
                    end
                else
                    % transformador regulador
                    indice = this.BusesConTrafosReg == this.pBuses(bus);
                    if ~isempty(indice)
                        trafo = this.TrafosReg(indice).Lista(1);  %todos los trafos son iguales
                        this.VarDecision(2*bus-1) = trafo.entrega_paso_actual();
                        if this.NivelDebug > 1
                            texto = sprintf('%10s %10s %10s %10s', num2str(2*bus-1), num2str(bus), 'VTr', num2str(this.VarDecision(2*bus-1)));
                            fprintf(docID, strcat(texto, '\n'));
                        end
                    else
                        error = MException('cFlujoPotencia:calcula_flujo_potencia','Tipo de var decision es para transformador regulador pero no hay ninguno conectado al bus actual');
                        throw(error)
                    end
                end
                this.VarDecision(2*bus) = this.pBuses(bus).entrega_angulo()/180*pi;
                if this.NivelDebug > 1
                    texto = sprintf('%10s %10s %10s %10s', num2str(2*bus), num2str(bus), 'Theta', num2str(this.VarDecision(2*bus)));
                    fprintf(docID, strcat(texto, '\n'));
                end
                s_nom(2*bus-1) = this.pBuses(bus).entrega_p_const_nom();
                s_nom(2*bus) = this.pBuses(bus).entrega_q_const_nom();
                this.pBuses(bus).inserta_tipo_bus_salida(this.pBuses(bus).entrega_tipo_bus_entrada());
            end

            if this.NivelDebug > 1
                % imprime snom y tipos de bus de entrada/salida (debieran
                % ser iguales)
                docID = fopen(this.nombre_archivo, 'a+');
                fprintf(docID, strcat('Snom', '\n'));
                texto = sprintf('%10s %10s %10s %10s', 'Nr.Var', 'Bus', 'Tipo', 'Valor');
                fprintf(docID, strcat(texto, '\n'));
                for bus = 1:length(this.pBuses)
                    texto = sprintf('%10s %10s %10s', num2str(2*bus-1), num2str(bus), 'MW', num2str(s_nom(2*bus-1)));
                    fprintf(docID, strcat(texto, '\n'));
                    texto = sprintf('%10s %10s %10s', num2str(2*bus), num2str(bus), 'MVA', num2str(s_nom(2*bus)));
                    fprintf(docID, strcat(texto, '\n'));
                end
                
                fprintf(docID, strcat('Tipo buses entrada/salida', '\n'));
                texto = sprintf('%10s %10s %10s', 'Bus', 'Tipo in', 'Tipo out');
                fprintf(docID, strcat(texto, '\n'));
                for bus = 1:length(this.pBuses)
                    tipo_in = this.pBuses(bus).entrega_tipo_bus_entrada();
                    tipo_out = this.pBuses(bus).entrega_tipo_bus_salida();
                    texto = sprintf('%10s %10s %10s', num2str(bus), tipo_in, tipo_out);
                    fprintf(docID, strcat(texto, '\n'));
                end
            end
            
            this.JTipoVarDecision = this.TipoVarDecision;
            
            iter = 0;
            discreto = false;
            while true
                ds_total = 0;
                ds_mw_total = 0;
                s = zeros(2*length(this.pBuses),1);
                u_bus = zeros(length(this.pBuses),1);
                % S = diag(U)*conj(Y)*conj(U)
                for bus = 1:length(this.pBuses)
                    if strcmp(this.JTipoVarDecision{2*bus-1},'V')
                        u = this.VarDecision(2*bus-1);
                    else     
                        trafo = this.entrega_trafo_regulador(this.pBuses(bus), 1, true); %basta con el primer trafo y tiene que ser obligatorio
                        u = trafo.entrega_paso_actual();
                    end
                    val_real = u*cos(this.VarDecision(2*bus));
                    val_imag = u*sin(this.VarDecision(2*bus));
                    % u_bus contiene voltaje de los buses
                    u_bus(bus) = complex(val_real, val_imag);
                end
                %s_aux contiene la potencia como resultado del sistema de
                %ecuaciones
%s_aux = 3*diag(u_bus)*conj(this.Adm)*conj(u_bus);
                s_aux = diag(u_bus)*conj(this.Adm)*conj(u_bus);
                if this.NivelDebug > 1
                    this.imprime_vector(u_bus, this.nombre_archivo, 'u_bus');
                    this.imprime_vector(s_aux, this.nombre_archivo, 's_aux');
                end
                %p_sum_act = sum(real(s_aux));
                
                % separación de P y Q por buses... se debiera hacer
                % directamente TODO
                for bus = 1:length(this.pBuses)
                    s(2*bus-1) = real(s_aux(bus));
                    s(2*bus) = imag(s_aux(bus));
                end
                if this.NivelDebug > 1
                    this.imprime_matriz(s, this.nombre_archivo, 's');
                end
                
                %desviación de frecuencia
                %dfrecuencia = (p_sum_act - suma_p_obj)/l_ges;
                
                % cálculo criterio convergencia
                for bus = 1:length(this.pBuses)
                    if ~this.pBuses(bus).es_slack()
                        delta_s(2*bus-1) = s_nom(2*bus-1) - s(2*bus-1); %+ dfrecuencia*leistungszahl%
                        ds_total = ds_total + delta_s(2*bus-1);
                        ds_mw_total = ds_mw_total + abs(delta_s(2*bus-1));
                    end
                    
                    if ~strcmp(this.pBuses(bus).entrega_tipo_bus_entrada(), 'PV')
                        % Potencia reactiva se verifica sólo para buses PQ
                        delta_s(2*bus) = s_nom(2*bus) - s(2*bus);
                        ds_total = ds_total + delta_s(2*bus);
                        ds_mw_total = ds_mw_total + abs(delta_s(2*bus));
                    end
                end

                if this.NivelDebug > 1
                    this.imprime_vector(delta_s, this.nombre_archivo, 'delta_s');
                    this.imprime_valor(ds_total, 'ds_total');
                    this.imprime_valor(ds_mw_total, 'ds_mw_total');
                end
                
                % campo tipo de buses PV --> PQ
                cambio_tipo_buses = false;
                if iter > this.pParFP.NumIterSinCambioPUaPQ
                    % verificar si es necesario cambio de tipo de buses
                    for bus = 1:length(this.pBuses)
                        if strcmp(this.pBuses(bus).entrega_tipo_bus_salida(), 'PV')
                            q_consumo = this.pBuses(bus).entrega_q_const_nom();
                            q_inyeccion = s(2*bus) + q_consumo;
                            q_min = this.pBuses(bus).entrega_q_min();
                            q_max = this.pBuses(bus).entrega_q_max();
                            if (q_inyeccion < q_min) || (q_inyeccion > q_max)
                                this.pBuses(bus).inserta_tipo_bus_salida('PQ')
                                if q_inyeccion < q_min
                                    s_nom(2*bus) = q_min - q_consumo;
                                else
                                    s_nom(2*bus) = q_max - q_consumo;
                                end
                                cambio_tipo_buses = true;
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
                    return;
                end
                
                if (ds_mw_total < this.pParFP.MaxErrorMW) ... 
                    && (discreto || isempty(this.TrafosReg)) ...
                    && ~cambio_tipo_buses
                   % hay convergencia
                   convergencia = true;
                   break;
                end
                
                if iter > this.pParFP.MaxNumIter
                    % se alcanzó el máximo número de iteraciones. No hay
                    % convergencia
                    convergencia = false;
                    return;
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
                        if strcmp(this.TipoVarDecision{2*bus-1},'PasoTrafo')
                            % entrega lista de transformadores que regulan
                            % tensión del bus
                            cantidad_trafos = entrega_cantidad_trafos_reguladores(this.pBuses(bus));
                            for ittraf = 1:cantidad_trafos
                                trafoiter = this.entrega_trafo_regulador(this.pBuses(bus), ittraf, true);
                                trafoiter.inserta_paso_actual(round(trafoiter.entrega_paso_actual()));
                            end
                            if cantidad_trafos == 0
                                error = MException('cFlujoPotencia:calcula_flujo_potencia','Variable del bus es PasoTrafo pero no hay transformadores reguladores');
                                throw(error)
                            end
                            %ajustar variables
                            this.VarDecision(2*bus-1) = this.entrega_trafo_regulador(this.pBuses(bus), 1, true).entrega_voltaje_objetivo();
                            this.TipoVarDecision{2*bus-1} = 'V';
                        end
                    end
                end
                
                % nueva iteración
                this.actualiza_matriz_jacobiana();

                if this.NivelDebug > 1
                    this.imprime_matriz(this.J, this.nombre_archivo, ['Matriz Jacobiana iteracion: ' num2str(iter)]);
                end
                
                %borrar filas y columnas de la barra slack
                slack_encontrada = false;
                indice_a_borrar = [];
                for bus = 1:length(this.pBuses)
                    if this.pBuses(bus).es_slack()
                        indice_a_borrar = [indice_a_borrar 2*bus-1];
                        indice_a_borrar = [indice_a_borrar 2*bus];
                        slack_encontrada = true;
                    elseif strcmp(this.pBuses(bus).entrega_tipo_bus_salida(),'V')
                        indice_a_borrar = [indice_a_borrar 2*bus-1];
                    end
                end
                if ~slack_encontrada
                   error = MException('cFlujoPotencia:callcula_flujo_potencia','No se encontró slack');
                   throw(error)
                end
                % crea indices entre vectores originales y
                % nuevos
                VarSol = zeros(length(this.VarDecision)-length(indice_a_borrar),1);
                IndiceVarSol = zeros(length(this.VarDecision),1);
                it_varsol = 1;
                for i = 1:length(this.VarDecision)
                    if find(indice_a_borrar == i)
                        IndiceVarSol(i) = 0;
                    else
                        VarSol(it_varsol) = this.VarDecision(i);
                        IndiceVarSol(i) = it_varsol;
                        it_varsol = it_varsol + 1;                       
                    end
                end
                            
                % borra columnas de matrizl
                this.J(:,indice_a_borrar) = [];
                this.J(indice_a_borrar,:) = [];
                
                % resuelve sistema de ecuaciones
                Sol = this.J/VarSol';

                if this.NivelDebug > 1
                    this.imprime_vector(this.VarDecision, this.nombre_archivo, 'antiguo vector solucion');
                    this.imprime_vector(indice_a_borrar, this.nombre_archivo, 'indices a borrar');
                    this.imprime_matriz(this.J, this.nombre_archivo, 'Matriz jacobiana sin filas y columnas');
                    this.imprime_vector(Sol, this.nombre_archivo, 'vector solucion');
                    this.imprime_vector(IndiceVarSol, this.nombre_archivo, 'indice de variables y solucion');
                end
                % escribe resultados en VarDecision
                for indice = 1:length(this.VarDecision)
                    indice_en_sol = IndiceVarSol(indice);
                    if indice_en_sol > 0
                        this.VarDecision(indice) = this.VarDecision(indice) + Sol(indice_en_sol);
                    end
                end
                if this.NivelDebug > 1
                    this.imprime_vector(this.VarDecision, this.nombre_archivo, 'nuevo vector solucion');
                end            
                % actualizar paso de los transformadores
                for bus = 1:length(this.pBuses)
                    if strcmp(this.JTipoVarDecision{2*bus-1},'PasoTrafo')
                        cantidad_trafos = this.entrega_cantidad_trafos_reguladores(this.pBuses(bus));
                        for itr = 1:cantidad_trafos
                            trafo = this.entrega_trafo_regulador(this.pBuses(bus), itr, true);
                            trafo.inserta_paso_actual(this.VarDecision(2*bus-1));
                        end
                    end
                end
                
                % actualizar matriz de admitancia debido a transformadores
                % reguladores
                this.actualiza_matriz_admitancia();
                
                iter = iter + 1;
            end
            
            % ingresa valores para cálculo de resultado
            for bus = 1:length(this.pBuses)
                % no es necesario para la slack ya que voltaje y ángulos
                % son conocidos y fueron ingresados durante inicialización
                % de variables
                if strcmp(this.pBuses(bus).entrega_tipo_bus_salida(),'PV')
                    % sólo ángulos, ya que voltaje fue mantenido (si no
                    % hubiera cambiado a PQ) y ya fue ingresado durante
                    % inicialización de variables
                    this.pBuses(bus).inserta_angulo(this.VarDecision(2*bus)/pi*180);
                elseif strcmp(this.pBuses(bus).entrega_tipo_bus_salida(),'PQ')
                    this.pBuses(bus).inserta_voltaje(this.VarDecision(2*bus-1));
                    this.pBuses(bus).inserta_angulo(this.VarDecision(2*bus)/pi*180);
                end
            end
            
            % Flujo se calcula en base a los resultados de V y Theta
            this.pmsist.calcula_flujos(nro_subsistema);
            
        end
        
        function actualiza_matriz_jacobiana(this)

            this.J = zeros(2*length(this.pBuses));
            dpi_dui = zeros(length(this.pBuses),1);
            dqi_dui = zeros(length(this.pBuses),1);

            col = 0;
            for fila_actual =1:length(this.pBuses)
                %col = col + 1;
                fila = fila_actual;
                if strcmp(this.JTipoVarDecision{2*fila-1},'V')
                    ui = this.VarDecision(2*fila-1);
                else
                    % transformador regulador
                    indice = find(this.BusesConTrafosReg == fila, 1);
                    if ~isempty(indice)
                        trafo = this.TrafosReg(indice).Lista(1).entrega_elemento_red();
                        ui = trafo.entrega_voltaje_objetivo();
                    else
                        error = MException('cFlujoPotencia:callcula_flujo_potencia','Variable del bus es PasoTrafo pero no hay transformadores reguladores');
                        throw(error)
                    end

                end
                ti = this.VarDecision(2*fila);

                dpi_dti = 0.;
                dqi_dti = 0.;
                indices_columnas = find(this.Adm(fila, :) ~= 0);
                for nro_col = 1:length(indices_columnas)
                    col = indices_columnas(nro_col);
                    if col == fila
                        %diagonal
                        if strcmp(this.JTipoVarDecision{2*fila-1},'V')
                            yrii = real(this.Adm(fila,col));
                            yiii = imag(this.Adm(fila,col));
                            dpi_dui(fila) = dpi_dui(fila) + 2*ui*yrii;
                            dqi_dui(fila) = dqi_dui(fila) - 2*ui*yiii;
                        end
                    else
                        % elemento fuera de la diagonal
                        if strcmp(this.JTipoVarDecision{2*col-1},'V')
                            uj = this.VarDecision(2*col-1);
                        else
                            % transformador regulador
                            indice = find(this.BusesConTrafosReg == col, 1);
                            if ~isempty(indice)
                                trafo = this.TrafosReg(indice).Lista(1).entrega_elemento_red();
                                uj = trafo.entrega_voltaje_objetivo();
                            else
                                error = MException('cFlujoPotencia:callcula_flujo_potencia','Variable del bus es PasoTrafo pero no hay transformadores reguladores');
                                throw(error)
                            end
                        end
                        
                        tj = this.VarDecision(2*col);
                        sinij = sin(ti-tj);
                        cosij = cos(ti-tj);

                        yrij = real(this.Adm(fila,col));
                        yiij = imag(this.Adm(fila,col));
                            
                        %theta
                        dqi_dtj = -ui*uj*(yrij*cosij+yiij*sinij);
                        dpi_dtj = ui*uj*(yrij*sinij-yiij*cosij);

                        this.J(2*fila-1,2*col) = dpi_dtj;
                        this.J(2*fila,2*col) = dqi_dtj;
                        
                        % agregar elemento para la diagonal
                        dpi_dti = dpi_dti - dpi_dtj;
                        dqi_dti = dqi_dti - dqi_dtj;

                        dpi_duj = yrij*cosij+yiij*sinij;
                        dqi_duj = yrij*sinij-yiij*cosij;
                        
                        if strcmp(this.JTipoVarDecision{2*fila-1},'V')
                            dpi_dui(fila) = dpi_dui(fila) + uj*dpi_duj;
                            dqi_dui(fila) = dqi_dui(fila) + uj*dqi_duj;
                        end
                        
                        % código abajo correcto: se verifica tipo de
                        % columna
                        if strcmp(this.JTipoVarDecision{2*col-1},'V')
                            % columna de un bus no regulado por
                            % transformador
                            
                            this.J(2*fila-1,2*col-1) = ui*dpi_duj;
                            this.J(2*fila,2*col-1) = ui*dqi_duj;
                        else
                            % columna de un bus regulado por trafo
                            % verificar si transformador regula ambos buses
                            idx_en_bus = find(this.BusesConTrafosReg == this.pBuses(col));
                            if isempty(idx_en_bus)
                                error = MException('cFlujoPotencia:actualiza_matriz_jacobiana','bus tiene regulación pero no se encuentra en BusesConTrafosReg');
                                throw(error)
                            end
                            idx_en_trafo = find(this.TrafosReg(idx_en_bus).IndiceBusReg == col, 1);
                            if isempty(idx_en_trafo)
                                error = MException('cFlujoPotencia:actualiza_matriz_jacobiana','No se encuentra índice con el bus regulado');
                                throw(error)
                            end
                            
                            if length(this.TrafosReg(idx_en_bus).IndiceBusNoReg) < id_en_trafo
                                error = MException('cFlujoPotencia:actualiza_matriz_jacobiana','No se encuentra índice con el bus no regulado');
                                throw(error)
                            end
                            
                            id_bus_no_regulado = this.TrafosReg(idx_en_bus).IndiceBusNoReg(id_en_trafo);
                            if id_bus_no_regulado ~= fila
                                % transformador reg. parte no regulada no corresponde a fila
                                % se elimina valor de fuera de diagonal
                                % dPi/duj und dQi/duj
                                this.J(2*fila-1,2*col-1) = 0;
                                this.J(2*fila,2*col-1) = 0;
                            else
                                trafo = this.TrafosReg(idx_en_bus).Lista(1).entrega_elemento_red();
                                ue = trafo.entrega_relacion_transformacion();
                                ue_c = conj(ue);

                                yji = complex(this.Adm(col,fila),this.Adm(col+1,fila)); 
                                yjj = complex(-this.Adm(col,fila),-this.Adm(col+1,fila));
                                
                                % determinar si regulación es en el lado de
                                % alta o baja tensión
                                se_reg = trafo.entrega_subestacion_regulada();
                                se_no_reg = trafo.entrega_subestacion_no_regulada();
                                
                                if se_reg.entrega_voltaje() < se_no_reg.entrega_voltaje()
                                    yjj = yjj/ue;
                                    yji = yji/ue;

                                    yji_c = conj(yji);
                                    yjj_c = conj(yjj);
                                    
                                    cosi = cos(ti);
                                    sini = sin(ti);
                                    cosj = cos(tj);
                                    sinj = sin(tj);

                                    uj_ = complex(uj*cosj,uj*sinj);
                                    ui_ = complex(ui*cosi,ui*sini);

                                    uj_c = conj(uj_);
                                    ui_c = conj(ui_);
                                    
                                    due_ds = trafo.entrega_du_a_ds();
                                    due_ds_c = conj(du_ds);
                                    
                                    %determinación del elemento en la
                                    %diagonal
                                    diag = uj*uj*yjj_c*(ue*due_ds_c+ue_c*due_ds)+uj_*yji_c*ui_c*due_ds;

                                    % elemento fuera de la diagonal
                                    fuera_diag = ui_*yji_c*uj_c*due_ds_c;
                                else
                                    yjj = yjj/ue_c;
                                    yji = yji/ue_c;
                                    yjj_c = conj(yjj); 
                                    yji_c = conj(yji); 
                                    yrji = real(yji);
                                    yiji = imag(yji);

                                    cosi = cos(ti);
                                    sini = sin(ti);
                                    cosj = cos(tj);
                                    sinj = sin(tj);

                                    uj_ = complex(uj*cosj,uj*sinj);
                                    ui_ = complex(ui*cosi,ui*sini);

                                    uj_c = conj(uj_);
                                    ui_c = conj(ui_);

                                    due_ds = trafo.entrega_du_a_ds();
                                    due_ds_c = conj(due_ds);

                                    % elemento en la diagonal
                                    % regula en el lado de alta tensión
                                    diag = uj_*yji_c*ui_c*due_ds_c;

                                    % elemento fuera de la diagonal
                                    fuera_diag = ui*ui*yjj_c*(ue*due_ds_c+ue_c*due_ds)+ui_*yji_c*uj_c*due_ds;
                                end

                                dpi_dui(col) =  real(diag);
                                dqi_dui(col) =  imag(diag);

                                this.J(2*fila-1,2*col-1) = real(fuera_diag);
                                this.J(2*fila,2*col-1) = imag(fuera_diag);
                            end
                        end
                    end
                end
                this.J(2*fila-1, 2*col) = dpi_dti;
                this.J(2*fila, 2*col) = dqi_dti;
            end
            
            % ingresar valores en diagonal para U y Ue
            for i_fila = 1:length(this.pBuses)
                this.J(2*i_fila-1, 2*i_fila-1) = dpi_dui(i_fila);
                this.J(2*i_fila, 2*i_fila-1) = dqi_dui(i_fila);
            end
            
            desacoplado = false;
            if desacoplado
                %for i_fila = 1:length(this.pBuses)
                %algo
            end
        end
        
        function trafo = entrega_trafo_regulador(this, bus, nr_trafo, obligatorio)
            indice = this.BusesConTrafosReg == bus;
            if ~isempty(indice)
                if length(this.TrafosReg(indice).Lista) >= nr_trafo
                    trafo = this.TrafosReg(indice).Lista(nr_trafo);
                end
            end
            
            if obligatorio
                error = MException('cFlujoPotencia:calcula_flujo_potencia','Tipo de var decision es para transformador regulador pero no hay ninguno conectado al bus actual');
                throw(error)
            end
            trafo = cTransformador.empty;
        end
        
        function cantidad = entrega_cantidad_trafos_reguladores(this, bus)
            indice = this.BusesConTrafosReg == bus;
            cantidad = 0;
            if ~isempty(indice)
                cantidad = length(this.TrafosReg(indice).Lista);
            end
        end
        
        function actualiza_matriz_admitancia(this)
            % hay que actualizar datos debido a los transformadores reguladores
            
        end
        
        function construye_matriz_admitancia(this)
            % 1. obtención de los parámetros de elementos en serie
            this.Adm = zeros(length(this.pBuses));
            for eserie = 1:length(this.pmElementoSerie)
                [y11, y12, y21, y22] = this.pmElementoSerie.entrega_cuadripolo();
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
                    y11 = el_red.entrega_dipolo();
                    this.Adm(n,n) = this.Adm(n,n) + y11;
                elseif isa(el_red, 'cConsumo')
                    if el_red.tiene_dependencia_voltaje()
                        vnom = bus.entrega_vn();
                        p0 = el_red.entrega_p0();
                        q0 = -el_red.entrega_q0();
                        y11 = complex(p0/vnom^2,q0/vnom^2);
                        this.Adm(n,n) = this.Adm(n,n) + y11;
                    end
                end
            end
            if this.NivelDebug > 1
                this.imprime_matriz(this.Adm, this.nombre_archivo, 'Matriz Admitancia');
            end
        end

        function determina_valores_iniciales(this)
            % determina voltajes y ángulos de inicio
            % falta hacer. 
            % Por ahora, todos los voltajes = valor nominal o
            % 1.05 voltaje objetivo
            
            for bus = 1:length(this.pBuses)
                if strcmp(this.pBuses(bus).entrega_tipo_bus_entrada(), 'PV')
                    voltaje_objetivo = this.pBuses(bus).entrega_voltaje_objetivo();
                    this.pBuses(bus).inserta_voltaje(voltaje_objetivo);
                    this.pBuses(bus).inserta_angulo(0);
                    if this.pBuses(bus).es_slack()
                        % redundante, pero a futuro ángulos iniciales
                        % entre los buses debiera ser distinto
                        this.pBuses(bus).inserta_angulo(0);
                    end
                elseif strcmp(this.pBuses(bus).entrega_tipo_bus_entrada(), 'PQ')
                    vn = this.pBuses(bus).entrega_vn();
                    this.pBuses(bus).inserta_voltaje(1.05*vn);
                    this.pBuses(bus).inserta_angulo(0);
                elseif strcmp(this.pBuses(bus).entrega_tipo_bus_entrada(), 'Pasivo')
                    vn = this.pBuses(bus).entrega_vn();
                    this.pBuses(bus).inserta_voltaje(1.05*vn);
                    this.pBuses(bus).inserta_angulo(0);
                else
                    error = MException('cFlujoPotencia:determina_valores_iniciales',...
                        strcat(['Tipo de bus de entrada indicado (' this.pBuses(bus).entrega_tipo_bus_entrada() ') no es correcto' ]));
                    throw(error)
                end
            end
        end

        function inicializa_tipo_variables(this)
            % determina dimensiones y tipo de variable de control
            if this.NivelDebug > 1
                docID = fopen(this.nombre_archivo, 'a+');
                fprintf(docID, strcat('Inicializa variables', '\n'));
            end

            this.TipoVarDecision = cell(2*length(this.pBuses), 1);
            for bus = 1:length(this.pBuses)
                % determina el tipo de variables de decision
                this.TipoVarDecision{2*bus-1} = 'V';  % valor por defecto. Luego se actualiza con los transformadores reguladores
                this.TipoVarDecision{2*bus} = 'Angulo';
                % identifica transformadores con regulación de tensión
                nro_conexiones = this.pBuses(bus).entrega_cantidad_conexiones();
                for idx= 1:nro_conexiones
                    eserie = this.pBuses(bus).entrega_conexion(idx);
                    if isa(class(eserie.entrega_elemento_red()),'cTransformador')
                        trafo = eserie.entrega_elemento_red();
                        if trafo.controla_tension()
                            se_reg = trafo.entrega_subestacion_regulada();
                            if se_reg == this.pBuses(bus).entrega_elemento_red()
                                bus1 = this.pBuses(bus).entrega_conexion(idx).entrega_bus1();
                                if bus1 == this.pBuses(bus)
                                    bus_no_regulado = this.pBuses(bus).entrega_conexion(idx).entrega_bus2();
                                else
                                    bus_no_regulado = bus1;
                                end
                                
                                if ~(find(this.BusesConTrafosReg == this.pBuses(bus)))
                                    this.BusesConTrafosReg = [this.BusesConTrafosReg this.pBuses(bus)];
                                    indice = length(this.BusesConTrafosReg);
                                    this.TrafosReg(indice).Lista(1) = eserie;
                                    this.TrafosReg(indice).IndiceBusReg(1) = bus;
                                    this.TrafosReg(indice).IndiceBusNoReg(1) = bus_no_regulado.entrega_id();
                                    this.TipoVarDecision{2*bus-1} = 'PasoTrafo';
                                else
                                    % ya existe un transformador regulador
                                    % para este bus. Hay que verificar que
                                    % sean paralelos
                                    indice = this.BusesConTrafosReg == this.pBuses(bus);
                                    for itLista = 1:length(this.TrafosReg(indice).Lista)
                                        eserie_existente = this.TrafosReg(indice).Lista(itLista);
                                        if ~eserie.es_paralelo(eserie_existente)
                                            error = MException('cFlujoPotencia:inicializa_tipo_variables_decision','existen dos transformadores que regulan el mismo nodo pero no son paralelos');
                                            throw(error)
                                        end
                                    end
                                    %inserta datos
                                    this.TrafosReg(indice).Lista = [this.TrafosReg(indice).Lista eserie];
                                    this.TrafosReg(indice).IndiceBusReg = [this.TrafosReg(indice).IndiceBusReg bus];
                                    this.TrafosReg(indice).IndiceBusNoReg = [this.TrafosReg(indice).IndiceBusNoReg bus_no_regulado.entrega_id()];
                                end
                            end
                        end
                    end
                end
            end
            if this.NivelDebug > 1
                fclose(docID);
            end
            
        end
        
        function imprime_matriz(this, matriz, varargin)
%            matriz
            archivo = false;
            if nargin > 2
                archivo = true;
                nombre_doc = varargin{1};
                titulo = varargin{2};
            end
            
            [n,m] = size(matriz);
            largo = num2str(n);
            
            text = cell(n+1,1);
            % título
            text{1} = sprintf('%13s', ' ');
            for j = 1:m
                txt = sprintf('%20s',num2str(j));
                text{1} = strcat(text{1}, txt);
            end
           
            for i = 1:n
                text{i+1} = sprintf('%4s %3s', num2str(i), '|');
                for j = 1:m
                    txt = sprintf('%20s',num2str(matriz(i,j)));
                    text{i+1} = strcat(text{i+1}, txt);
                end
            end
            
            if archivo
                docID = fopen(nombre_doc, 'a+');
                fprintf(docID, strcat(titulo, '\n'));
                fprintf(docID, strcat(text{1},'\n'));
                segundo = sprintf('%13s', ' ');
                for aux = 1:length(text)
                    segundo = strcat(segundo, '____');
                end
                fprintf(docID, strcat(segundo,'\n'));
                for i = 2:length(text)
                    fprintf(docID, strcat(text{i},'\n'));
                end
                
                fclose(docID);
            else
                for i = 1:length(text)
                    disp(text{i});
                end
            end
        end
        
        function imprime_valor(this, val, nombre)
                docID = fopen(this.nombre_archivo, 'a+');
                fprintf(docID, strcat(nombre, ':', num2str(val), '\n'));
                fclose(docID);
        end
        function imprime_vector(this, vector, varargin)
%            matriz
            archivo = false;
            if nargin > 2
                archivo = true;
                nombre_doc = varargin{1};
                titulo = varargin{2};
            end
            
            n= length(vector);
            text = cell(n+1,1);
            % título
            text{1} = strcat(titulo,':');
           
            for i = 1:n
                text{i+1} = sprintf('%4s %3s', num2str(i), '|', num2str(vector(i)));
            end
            
            if archivo
                docID = fopen(nombre_doc, 'a+');
                for i = 1:length(text)
                    fprintf(docID, strcat(text{i},'\n'));
                end
                
                fclose(docID);
            else
                for i = 1:length(text)
                    disp(text{i});
                end
            end
        end
        
    end
end

    