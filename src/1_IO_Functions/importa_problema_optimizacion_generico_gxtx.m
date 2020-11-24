function importa_problema_optimizacion_generico_gxtx(data, sep, pAdmProy, pAdmSc, pParOpt)
    % Restricciones por ahora
    % 1. Sólo se permite agregar líneas paralelas cuando el conductor es el
    %    mismo (en caso de que haya más de una línea paralela)
    % 2. Por ahora no se considera compensación serie
    
    NivelDebug = pParOpt.entrega_nivel_debug();

	pAdmProy.inicializa_escenarios(pParOpt.CantidadEscenarios, pParOpt.CantidadEtapas);
    
    factor_desarrollo_proyectos = data.Costos(1,2);
    pParOpt.inserta_factor_costo_desarrollo_proyectos(factor_desarrollo_proyectos);
    
    se_aisladas = importa_buses(data,sep, pAdmProy);
    
	% inicializa los escenarios
    if isempty(data.IndicesPOConsecutivos)
    	pAdmSc.inicializa_escenarios(data.Escenarios(:,1), data.Escenarios(:,2), pParOpt.CantidadEtapas, length(data.PuntosOperacion(:,1)), data.PuntosOperacion(:,2))
    else
        pAdmSc.inicializa_escenarios(data.Escenarios(:,1), data.Escenarios(:,2), pParOpt.CantidadEtapas, length(data.PuntosOperacion(:,1)), data.PuntosOperacion(:,2), data.IndicesPOConsecutivos)
    end
	importa_perfiles_ernc(data, pAdmSc);
	importa_perfiles_consumos(data, pAdmSc);
	
	
    importa_consumos(data, pParOpt, sep, pAdmSc, se_aisladas);    
    importa_generadores(data, pParOpt, sep, pAdmSc, pAdmProy, se_aisladas);

    % corredores
    elementos = genera_elementos_red_serie(data,pParOpt,sep,pAdmProy,NivelDebug);
    elementos = genera_elementos_red_paralelo(elementos, data, sep, pAdmProy);

    % genera proyectos de expansión
    genera_proyectos_expansion(elementos, pAdmProy, pParOpt);
    for i = 1:length(se_aisladas)
        pAdmProy.agrega_proyectos_tx_obligatorios(se_aisladas(i));
    end
    
    if pParOpt.considera_reconductoring() || pParOpt.considera_compensacion_serie() || pParOpt.ConsideraVoltageUprating()
        pAdmProy.genera_dependencias_cambios_estado();
    end
    
    pAdmProy.determina_proyectos_por_elementos();
    
    if NivelDebug > 0
        pAdmProy.imprime_proyectos();
        %sep.grafica_sistema('Sistema inicial', false);
    end
end

function importa_perfiles_ernc(data, pAdmSc)
	[n, ~] = size(data.PerfilesERNC);
    for i = 1:n
        perfil = data.PerfilesERNC(i,1:end);
		pAdmSc.inserta_perfil_ernc(perfil);
    end
end

function importa_perfiles_consumos(data, pAdmSc)
    [n, ~] = size(data.PerfilesDemanda);
	for i = 1:n
		perfil = data.PerfilesDemanda(i,1:end);
		pAdmSc.inserta_perfil_consumo(perfil);
	end	
end

function se_aisladas = importa_buses(data, sep, pAdmProy)
    % Buses = [id, vn conectado (0/1)]
    Buses = data.Buses;

    se_aisladas = cSubestacion.empty;
    [nb, ~] = size(Buses);

    lineas_existentes = data.Lineas(data.Lineas(:,7) == 1,:);
    
    for i = 1:nb
        se = cSubestacion;
        se.inserta_nombre(strcat('SE_',num2str(i),'_VB_', num2str(Buses(i, 2))));
        se.inserta_vn(Buses(i, 2));
        se.inserta_vmax(Buses(i,4));
        se.inserta_vmin(Buses(i,5));
        se.inserta_id(i);
        posX = Buses(i,7);
        posY = Buses(i,8);
        se.inserta_posicion(posX, posY);
        se.inserta_ubicacion(i);
        if Buses(i,3) == 1
			se.Existente = true;
			sep.agrega_subestacion(se);
            if sum(lineas_existentes(:,1) == i) == 0
                if sum(lineas_existentes(:,2) == i) == 0
                    se_aisladas = [se_aisladas se];
                end
            end
            pAdmProy.inserta_subestacion_existente(se);
        else
			se.Existente = false;
            se_aisladas = [se_aisladas se];
             error = MException('cimporta_problema_optimizacion_tnep_118_ernc:main','Caso buses proyectados no se ha visto aun');
             throw(error)
        end
    end
end

function importa_consumos(data, param, sep, pAdmSc, se_aisladas)
    Consumos = data.Consumos;
    Buses = data.Buses;
    
    %              1   2     3         4           5         6
    % Consumos = [id, bus, p0 (MW), q0 (MW), dep_volt, NLS costs USD/MWh]
    [nc, ~] = size(Consumos);
    for i = 1:nc
        id_bus = Consumos(i,1);
        vn = Buses(id_bus,2);
        consumo = cConsumo;
        nombre_bus = strcat('SE_', num2str(Consumos(i,1)),'_VB_', num2str(vn));
        se = sep.entrega_subestacion(nombre_bus, false);
        consumo_proyectado = false;
        se_proyectada = false;
        if isempty(se)
            % puede ser un consumo proyectado en una nueva subestacion
            encontrado = false;
            for j = 1:length(se_aisladas)
                if strcmp(se_aisladas(j).Nombre, nombre_bus)
                    encontrado = true;
                    se = se_aisladas(j);
                    se_proyectada = true;
                    break
                end
            end
            
            if ~encontrado
                error = MException('cimporta_problema_optimizacion_tnep:main','no se pudo encontrar subestación');
                throw(error)
            end
        end
            
        consumo.inserta_subestacion(se);
        consumo.inserta_nombre(strcat('Consumo_',num2str(i), '_', se.entrega_nombre()));
        consumo.inserta_p0(Consumos(i,2));
        consumo.inserta_q0(0);
        consumo.inserta_tiene_dependencia_voltaje(false); % para TNEP no se considera dependencia de voltaje
        costo_nls = Consumos(i,4);
        consumo.inserta_costo_desconexion_carga(costo_nls);
        se.agrega_consumo(consumo);
		if Consumos(i,3) == 1
			consumo.Existente = true;
			sep.agrega_consumo(consumo);
		else
			consumo.Existente = false;
            consumo_proyectado = true;
            error = MException('cimporta_problema_optimizacion_tnep_118_ernc:main','Caso consumos proyectados no se ha visto aun');
            throw(error)
		end
        
        %agrega consumo a administrador de escenarios
        id_perfil_p = Consumos(i,5);
        consumo.inserta_indice_adm_escenario_perfil_p(id_perfil_p);
        id_perfil_q = Consumos(i,6);
        consumo.inserta_indice_adm_escenario_perfil_q(id_perfil_q);
		tipo_evol_capacidad = Consumos(i,7);
        cant_etapas = param.entrega_no_etapas();
		if tipo_evol_capacidad == 0
			aumento_porc = zeros(1, cant_etapas);
		elseif tipo_evol_capacidad == 1
			aumento_porc = [0 Consumos(i,8)*ones(1,cant_etapas-1)]; % se asume que en primera etapa P = Pmax
		else
			id_evol_capacidad = Consumos(i,8);
            error = MException('cimporta_problema_optimizacion_tnep_118_ernc:main','Caso evolucion variable de la capacidad no se ha visto aun');
            throw(error)			
		end
		
        pmax = Consumos(i,2);
        petapa = pmax;
		capacidades = zeros(1, cant_etapas);
        for j = 1:cant_etapas
			petapa = petapa*(1+aumento_porc(j)/100);
			capacidades(j) = petapa;
        end
		indice = pAdmSc.agrega_capacidades_consumo(capacidades);
		for escenario = 1:pAdmSc.CantidadEscenarios
			consumo.inserta_indice_adm_escenario_capacidad(escenario, indice); % por ahora no hay evolución de la capacidad específica por escenario
		end
    end
end

function importa_generadores(data, param, sep, pAdmSc, pAdmProy, se_aisladas)
    %              1    2  3    4     5     6     7     8      9      10      11 
    % Generador: [id, bus, P0, Q0, Pmax, Pmin, Qmax, Qmin, Vobj pu, status, Slack, USD/Mwh]
	Generadores = data.Generadores;
    Buses = data.Buses;
    [ng, nd] = size(Generadores);
    cant_etapas = param.CantidadEtapas;
    
    for i = 1:ng
        
        id_gen = Generadores(i,1);
        id_bus = Generadores(i,2);
        vn = Buses(id_bus,2);
        existente = Generadores(i,10);
        if ~existente
            % verifica que generador entra en operacion para algun
            % escenario en las etapas consideradas
			cant_escenarios_validos = 0;
            for escenario = 1:param.CantidadEscenarios
                id_escenario = data.Escenarios(escenario,1);
				fila_generador = find(ismember(data.EvolucionCapacidadGeneradores(:,1:2), [id_escenario id_gen],'rows'));
				if isempty(fila_generador)
					% quiere decir que generador no entra en este escenario
					continue
				end
				capacidades = data.EvolucionCapacidadGeneradores(fila_generador,3:end);

				etapa_entrada = find(capacidades > 0, 1);
				if isempty(etapa_entrada) || etapa_entrada > cant_etapas
					continue
				end
				
				cant_escenarios_validos	= cant_escenarios_validos +1;
            end
            if cant_escenarios_validos == 0
                warning(['Generador ' num2str(id_gen) ' no se considera ya que no entra en operacion para ningun escenario en las etapas consideradas'])
                continue
            end        
        end
        
        
        nombre_bus = strcat('SE_', num2str(Generadores(i,2)),'_VB_', num2str(vn));
        se = sep.entrega_subestacion(nombre_bus, false);
        if isempty(se)
            % generador entra en una subestacion proyectada
            encontrado = false;
            for j = 1:length(se_aisladas)
                if strcmp(se_aisladas(j).Nombre, nombre_bus)
                    encontrado = true;
                    se = se_aisladas(j);
                    break
                end
            end
            
            if ~encontrado
                error = MException('cimporta_problema_optimizacion_tnep:main','no se pudo encontrar subestación');
                throw(error)
            end
        end
        
        gen = cGenerador();
        gen.inserta_nombre(strcat('G', num2str(i), '_', nombre_bus));
        gen.inserta_subestacion(se);
        p0 = Generadores(i,3);
        q0 = Generadores(i,4);
        pmax = Generadores(i,5);
        pmin = Generadores(i,6);
        qmax = Generadores(i,7);
        qmin = Generadores(i,8);
        controla_tension = Generadores(i,9);
		
        Slack = Generadores(i,11);
        if Slack == 1
            gen.inserta_es_slack();
        end
		
        Costo_mwh = Generadores(i,12);
		tipo_generador = Generadores(i,13);
		evol_capacidad = Generadores(i,14);
		evol_costos = Generadores(i,15);
		perfil_ernc = Generadores(i,16);
		
        gen.inserta_pmax(pmax);
        gen.inserta_pmin(pmin);
        gen.inserta_costo_mwh(Costo_mwh);
        gen.inserta_qmin(qmin);
        gen.inserta_qmax(qmax);
        gen.inserta_p0(p0);
        gen.inserta_q0(q0);
        if controla_tension
            gen.inserta_controla_tension();
            gen.inserta_voltaje_objetivo(se.entrega_vn()*1);
        end
        gen.inserta_en_servicio(1);
        gen.inserta_es_despachable(perfil_ernc == 0);
        if tipo_generador == 1
            gen.inserta_tipo_central('Eol');
        elseif tipo_generador == 2
            gen.inserta_tipo_central('PV');
        else
            gen.inserta_tipo_central('Hidro');
        end
		
        if nd > 16 % tiempos mínimos de operación/detención, costos de encendido
            tmin_detencion = Generadores(i,17);
            tmin_operacion = Generadores(i,18);
            costo_partida = Generadores(i,19);
            gen.inserta_tiempo_minimo_operacion(tmin_operacion);
            gen.inserta_tiempo_minimo_detencion(tmin_detencion);
            gen.inserta_costo_partida(costo_partida);
        end
        if perfil_ernc > 0
			gen.inserta_indice_adm_escenario_perfil_ernc(perfil_ernc);
			if gen.es_despachable()
				error = MException('cimporta_problema_optimizacion_tnep:main','generador es convencional pero tiene perfil de ERNC');
				throw(error)
			end
        end

        
		if existente
			gen.Existente = 1;
			se.agrega_generador(gen);
			sep.agrega_generador(gen);
			if evol_capacidad
				for escenario = 1:param.CantidadEscenarios
					fila_generador = find(ismember(data.EvolucionCapacidadGeneradores(:,1:2), [escenario id_gen],'rows'));
					if isempty(fila_generador)
						error = MException('cimporta_problema_optimizacion_tnep_118_ernc:main','capacidad de generador existente evoluciona pero no se encuentran datos');
						throw(error)
					end
					capacidades = data.EvolucionCapacidadGeneradores(fila_generador,3:end);
					indice = pAdmSc.agrega_capacidades_generador(capacidades);
					gen.inserta_indice_adm_escenario_capacidad(escenario, indice);
					gen.inserta_evolucion_capacidad_a_futuro(escenario, true);
				end
			end
			if evol_costos
                for escenario = 1:param.CantidadEscenarios
                    gen.inserta_evolucion_costos_a_futuro(escenario, true);
                    error = MException('cimporta_problema_optimizacion_tnep_118_ernc:main','Caso evolucion de costos de generacion no se ha visto aun');
                    throw(error)
                end
			end
		else
			gen.Existente = 0;
%			cant_escenarios_validos = 0;
			for escenario = 1:param.CantidadEscenarios	
                id_escenario = data.Escenarios(escenario,1);
				fila_generador = find(ismember(data.EvolucionCapacidadGeneradores(:,1:2), [id_escenario id_gen],'rows'));
				if isempty(fila_generador)
					% quiere decir que generador no entra en este escenario
                    gen.inserta_etapa_entrada(escenario, 0);
                    if ~se.Existente
                        se.inserta_etapa_entrada(escenario, 0);
                    end
					continue
				end
				capacidades = data.EvolucionCapacidadGeneradores(fila_generador,3:end);

				etapa_entrada = find(capacidades > 0, 1);
				if isempty(etapa_entrada) || etapa_entrada > cant_etapas
                    gen.inserta_etapa_entrada(escenario, 0);
                    if ~se.Existente
                        se.inserta_etapa_entrada(escenario, 0);
                    end
					continue
				end
				
% 				cant_escenarios_validos	= cant_escenarios_validos +1;
% 				if cant_escenarios_validos > 1
% 					% crea copia del generador
% 					gen_escenario = gen.crea_copia();
% 				else
% 					gen_escenario = gen;
% 				end				
				
				gen.inserta_etapa_entrada(escenario, etapa_entrada);
				pAdmProy.agrega_generador_proyectado(gen, escenario, etapa_entrada);
                if ~se.Existente
                    % agrega subestacion proyectada a adm proy
                    pAdmProy.agrega_subestacion_proyectada(se, escenario, etapa_entrada);
                    se.inserta_etapa_entrada(escenario, etapa_entrada);
                end
                
                if evol_capacidad
					indice = pAdmSc.agrega_capacidades_generador(capacidades);
					gen.inserta_indice_adm_escenario_capacidad(escenario, indice);
					gen.inserta_evolucion_capacidad_a_futuro(escenario, true);
                else
                    gen.inserta_evolucion_capacidad_a_futuro(escenario, false);
                end
			end
		end
    end
end

function elementos_generados = genera_elementos_red_serie(data,param,sep,pAdmProy,NivelDebug)
    % Crea total de líneas por cada corredor.
    % Transformadores son igual que lineas, excepto que no hay CC, VU ni CS
    % Si se considera reconductoring se incluyen todos los tipos de
    % conductores para líneas cortas. Si no se considera reconductoring, se crean sólo las
    % líneas con el conductor indicado en archivo de Lineas
    % Si se considera compensación en serie, se crea un tipo de línea nuevo
    % con el valor compensado (sólo para líneas largas).
    % 
    % LineasBase guarda las líneas base
    % LineasBase(IdCorr).Nmax = número máximo de líneas
    % LineasBase(idCorr).NExistente = número de líneas existentes
    % LineasBase(idCorr).ConductorBase = conductor base
    % LineasBase(IdCorr).Linea = [(L1,Cbase), (L2, CBase),...,(Lnmax,Cbase)]
    % TrafosBase guarda transformadores base
    % TrafosBase(idCorr).Nmax;
    % TrafosBase(idCorr).NExistente;
    % TrafosBase(idCorr).TipoTrafoBase;
    % TrafosBase(idCorr).Trafo = [(T1, TBase), (T2, TBase), ...]

    % LineasCC guarda las líneas para reconductoring (por cada
    % tipo de conductor)
    % LineasCC(id_corr).Conductor(id_cond).Linea = [(L1,Cid)...
    % LineasReconductoring(id_corr).Existe = 0(no hay), 1(si hay)
    %
    % TrafosVU guarda los transformadores para VU
    % TrafosVU(id_ubicacion).Tipo(id_tipo).Trafos = [(T1,id_tipo), ...]
    % TrafosVU(id_ubicacion).Existe = 0 (no hay), 1
    % TrafosVU(id_ubicacion).Nmax --> indica cantidad de trafos paralelos

    Corredores = data.Corredores;
    [nc, ~] = size(Corredores);

    subestaciones = sep.entrega_subestaciones();
    TrafosVU = cell(length(subestaciones),0);
    for se = 1:length(subestaciones)
        ubicacion = subestaciones(se).entrega_ubicacion();
        TrafosVU(ubicacion).Existe = 0;
        TrafosVU(ubicacion).Nmax = 0;
    end
    % primero lineas base junto con reconductoring y compensación serie.
    % Voltage uprating se ve después
    % no es eficiente pero se entiende mejor el código

    % Primero líneas. Después se verán los trafos
    % Lineas: [bus1, bus2, rpu, xpu, bpu, sr, status, C (MM.USD) tipo_conductor]
    ElementosBase = cell(nc,0);
    LineasVU = cell(nc,0);
    LineasCC = cell(nc,0);
    LineasCS = cell(nc,0);    
    for id_corr = 1:nc
        % primero hay que buscar el voltaje base
        largo = Corredores(id_corr, 3);
        if largo == 0
            ElementosBase(id_corr).Largo = 0;
            ElementosBase = genera_transformadores(ElementosBase, id_corr, data, sep, pAdmProy);
        else
            ElementosBase(id_corr).Largo = Corredores(id_corr, 3);
            ElementosBase(id_corr).Elemento = [];
            LineasVU(id_corr).Existe = 0;
            LineasCS(id_corr).Existe = 0;
            LineasCC(id_corr).Existe = 0;
            %LineasCC(id_corr).Linea = [];
            %TrafosVU(id_corr).Existe = 0;

            [ElementosBase, LineasCC, LineasCS, LineasVU, TrafosVU] = genera_lineas(ElementosBase, LineasCC, LineasCS, LineasVU, TrafosVU, id_corr, data, param, sep, pAdmProy);            
        end
    end
    
    elementos_generados.ElementosBase = ElementosBase;
    elementos_generados.LineasCC = LineasCC;
    elementos_generados.LineasCS = LineasCS;
    elementos_generados.LineasVU = LineasVU;
    elementos_generados.TrafosVU = TrafosVU;
    
    if NivelDebug > 0
        Buses = data.Buses;
        % imprime líneas por corredor
        % primero, líneas existentes en el SEP y luego lineas proyectadas
        lineas_existentes = sep.entrega_lineas();
        trafos_existentes = sep.entrega_transformadores2d();
        elementos_proyectados = pAdmProy.entrega_elementos_serie_expansion();

        prot = cProtocolo.getInstance;
        prot.imprime_texto('Imprime lineas y transformadores');
        for id_corr = 1:nc
            id_bus_1 = Corredores(id_corr, 1);
            id_bus_2 = Corredores(id_corr, 2);
            largo = Corredores(id_corr, 3);
            vn_1 = Buses(id_bus_1,2);
            vn_2 = Buses(id_bus_2,2);
            nombre_bus1 = strcat('SE_', num2str(id_bus_1), '_VB_', num2str(vn_1));
            nombre_bus2 = strcat('SE_', num2str(id_bus_2), '_VB_', num2str(vn_2));

            se1 = sep.entrega_subestacion(nombre_bus1, false);
            if isempty(se1)
                se1 = pAdmProy.entrega_subestacion_proyectada_por_nombre(nombre_bus1);
            end
            
            se2 = sep.entrega_subestacion(nombre_bus2, false);
            if isempty(se2)
                se2 = pAdmProy.entrega_subestacion_proyectada_por_nombre(nombre_bus2);
            end
            
            ubicacion_1 = se1.entrega_ubicacion();
            ubicacion_2 = se2.entrega_ubicacion();
            elementos_a_borrar = [];
            primero = true;
            if largo > 0
                prot.imprime_texto(['\nCorredor ' num2str(id_corr) ' entre buses ' num2str(id_bus_1) '-' num2str(id_bus_2)]);
                for i = 1:length(lineas_existentes)
                    id_1 = lineas_existentes(i).entrega_se1().entrega_id();
                    id_2= lineas_existentes(i).entrega_se2().entrega_id();
                    if id_1 == id_bus_1 && id_2 == id_bus_2
                        elementos_a_borrar = [elementos_a_borrar i];
                        %lineas_existentes(i).imprime_parametros_pu(primero);
                        lineas_existentes(i).imprime_parametros_fisicos(primero, 'E');
                        primero = false;
                    end
                end
                lineas_existentes(elementos_a_borrar) = [];
                elementos_a_borrar = [];
                for i = 1:length(elementos_proyectados)
                    % pueden ser líneas normales o de VU. Por eso hay que
                    % verificar ubicación
                    if isa(elementos_proyectados(i), 'cLinea')
                        linea_proy = elementos_proyectados(i);
                        ubic_1 = linea_proy.entrega_se1().entrega_ubicacion();
                        ubic_2 = linea_proy.entrega_se2().entrega_ubicacion();
                        if ubic_1 == ubicacion_1 && ubic_2 == ubicacion_2
                            elementos_a_borrar = [elementos_a_borrar i];                    
                            linea_proy.imprime_parametros_fisicos(primero, 'P');
                            %linea_proy.imprime_parametros_pu(primero);
                            primero = false;
                        end
                    end
                end
                elementos_proyectados(elementos_a_borrar) = [];
            else
                prot.imprime_texto(['\nCorredor ' num2str(id_corr) ' entre buses ' num2str(id_bus_1) '-' num2str(id_bus_2) ' con voltajes v1 ' num2str(vn_1) ' y v2 ' num2str(vn_2)]);
                
                if vn_1 > vn_2
                    v_at_corr = vn_1;
                    v_bt_corr = vn_2;
                else
                	v_at_corr = vn_2;
                    v_bt_corr = vn_1;
                end

                for i = 1:length(trafos_existentes)
                    id_1 = trafos_existentes(i).entrega_se1().entrega_id();
                    id_2 = trafos_existentes(i).entrega_se2().entrega_id();
                    v_at = trafos_existentes(i).entrega_se1().entrega_vn();
                    v_bt = trafos_existentes(i).entrega_se2().entrega_vn();
                    

                    if (id_1 == id_bus_1 && id_2 == id_bus_2) || (id_2 == id_bus_1 && id_1 == id_bus_2)
                        elementos_a_borrar = [elementos_a_borrar i];
                        %lineas_existentes(i).imprime_parametros_pu(primero);
                        trafos_existentes(i).imprime_parametros_fisicos(primero, 'E');
                        primero = false;
                    end
                end
                trafos_existentes(elementos_a_borrar) = [];
                elementos_a_borrar = [];
                for i = 1:length(elementos_proyectados)
                    if isa(elementos_proyectados(i), 'cTransformador2D')
                        trafo_proy = elementos_proyectados(i);
                        id_1 = trafo_proy.entrega_se1().entrega_id();
                        id_2 = trafo_proy.entrega_se2().entrega_id();
                        v_at = trafo_proy.entrega_se1().entrega_vn();
                        v_bt = trafo_proy.entrega_se2().entrega_vn();
                        if (id_1 == id_bus_1 && id_2 == id_bus_2) || (id_2 == id_bus_1 && id_1 == id_bus_2)
                        	elementos_a_borrar = [elementos_a_borrar i];                    
                            trafo_proy.imprime_parametros_fisicos(primero, 'P');
                            %lineas_proyectadas(i).imprime_parametros_pu(primero);
                            primero = false;
                        end
                    end
                end
                elementos_proyectados(elementos_a_borrar) = [];
            end
        end

        % agrega nuevas subestaciones y nuevos transformadores (ambos de
        % VU)
        el_red = pAdmProy.entrega_subestaciones_expansion();
        se_existentes = sep.entrega_subestaciones();
        for k = 1:length(el_red)
            se = el_red(k);
            id_bus_1 = se.entrega_id();
            ubicacion = se.entrega_ubicacion();
            for j = 1:length(se_existentes)
                if se_existentes(j).entrega_ubicacion() == ubicacion
                    prot.imprime_texto(['\nNueva subestacion (VU) con id ' num2str(id_bus_1) ' en ubicacion ' num2str(ubicacion) ' en bus original ' num2str(se_existentes(j).entrega_id())]);
                    elementos_a_borrar = [];
                    id_bus_2 = se_existentes(j).entrega_id();
                    primero = true;
                    for i = 1:length(elementos_proyectados)
                        if isa(elementos_proyectados(i), 'cTransformador2D')
                            trafo_proy = elementos_proyectados(i);
                            id_1 = trafo_proy.entrega_se1().entrega_id();
                            id_2 = trafo_proy.entrega_se2().entrega_id();
                            v_at = trafo_proy.entrega_se1().entrega_vn();
                            v_bt = trafo_proy.entrega_se2().entrega_vn();
                        if (id_1 == id_bus_1 && id_2 == id_bus_2) || (id_2 == id_bus_1 && id_1 == id_bus_2)
                        	elementos_a_borrar = [elementos_a_borrar i];                    
                            trafo_proy.imprime_parametros_fisicos(primero, 'P');
                            %lineas_proyectadas(i).imprime_parametros_pu(primero);
                            primero = false;
                        end
                    end
                end
                elementos_proyectados(elementos_a_borrar) = [];
                end
            end
        end
                    
        %verifica que no existan líneas/trafos existentes o proyectados sin
        %haberse impreso
        elementos_faltantes = '';
        correcto = true;
        for i = 1:length(lineas_existentes)
            correcto = false;
            elementos_faltantes = [elementos_faltantes ' ' lineas_existentes(i).entrega_nombre()];
        end
        for i = 1:length(trafos_existentes)
            correcto = false;
            elementos_faltantes = [elementos_faltantes ' ' trafos_existentes(i).entrega_nombre()];
        end
        for i = 1:length(elementos_proyectados)
            correcto = false;
            elementos_faltantes = [elementos_faltantes ' ' elementos_proyectados(i).entrega_nombre()];
        end

        if ~correcto
            error = MException('cimporta_problema_optimizacion_tnep:genera_elementos_red_serie',...
                ['Error de programación. Al imprimir elementos faltan los siguientes: ' elementos_faltantes]);
            throw(error)
        end
        
        % grafica estados
        %close all
        
    end
end

function elementos_generados = genera_elementos_red_paralelo(elementos_generados, data, sep, pAdmProy)
    % Crea total de elementos paralelos.
    % Por ahora sólo baterías. A futuro, serán elementos de compensación de reactivos shunt

	Buses = data.Buses;
    [nb, ~] = size(Buses);

    Baterias = [];
    for id_bus = 1:nb
        % primero hay que buscar el voltaje base
        expansion_bateria = Buses(id_bus, 9);
        if expansion_bateria > 0
            Baterias = genera_baterias(Baterias, id_bus, data, sep, pAdmProy);
        end
    end
    elementos_generados.Baterias = Baterias;
end

function ElementosBase = genera_baterias(ElementosBase, id_bus, data, sep, pAdmProy)
    % Por ahora se asume que no hay cambios de estado de tipos de
    % tecnologías de baterías
    
    Baterias = data.Baterias;
    TecnologiaBaterias = data.TecnologiaBaterias;
    Buses = data.Buses;
    % primero hay que buscar el voltaje base
    vbase = Buses(id_bus,2);
    
	nombre_bus = strcat('SE_', num2str(id_bus), '_VB_', num2str(vbase));
    se = sep.entrega_subestacion(nombre_bus);
    if isempty(se)
        se = pAdmProy.entrega_subestacion_proyectada_por_nombre(nombre_bus);
    end
    
    nmax = Buses(id_bus,9);
	ElementosBase(id_bus).Nmax = nmax;

    if ~isempty(Baterias)
        id_bateria = ismember(Baterias(:,1),id_bus);
        nbaterias_existentes = Baterias(id_bateria, 2);
    else
        nbaterias_existentes = 0;
    end
    [cant_tecnologias, ~] = size(TecnologiaBaterias);
    
    ElementosBase(id_bus).NExistente = nbaterias_existentes;
    ElementosBase(id_bus).TipoBaseExistente = 0;
    if nbaterias_existentes > 0
        % identifica tipo base
        id_tecnologia = find(ismember(TecnologiaBaterias, Baterias(id_baterias,3:6), 'rows'));
        if ~isempty(id_tecnologia)
            ElementosBase(id_bus).TipoBaseExistente = id_tecnologia;
        end
    end
    for bpar = 1:nmax
        for tipo_bat = 1:cant_tecnologias
            
        	bateria = crea_bateria(TecnologiaBaterias(tipo_bat,:),se, bpar);

            if nbaterias_existentes >= bpar && tipo_bat == ElementosBase(id_bus).TipoBaseExistente
                bateria.inserta_anio_construccion(TrafosTotales(bpar, 7));
                bateria.Texto = ['E_' num2str(bpar)];
            
                %agrega bateria al SEP
                sep.agrega_bateria(bateria);
                se.agrega_bateria(bateria);
                pAdmProy.inserta_bateria_existente(bateria);
            else
                bateria.Existente = false;
                bateria.Texto = ['N_' num2str(bpar)];
                pAdmProy.inserta_bateria_expansion(bateria);
            end
        
%            if nbaterias_existentes == nmax
%                % no hay "nuevos proyectos" en este corredor. Se desactiva flag de observación
%                bateria.desactiva_flag_observacion();
%            else
%                % no es necesario, pero por si acaso (para entender mejor el
%                % código)
%                trafo.activa_flag_observacion();
%            end
        % se guarda el tipo de bateria
            if bpar == 1
                ElementosBase(id_bus).Tipo(tipo_bat).Elemento = bateria;
            else
                ElementosBase(id_bus).Tipo(tipo_bat).Elemento= [ElementosBase(id_bus).Tipo(tipo_bat).Elemento; bateria];
            end
        end
    end
end

function ElementosBase = genera_transformadores(ElementosBase, id_corr, data, sep, pAdmProy)
    Transformadores = data.Transformadores;
    TipoTrafos = data.TipoTransformadores;
    Corredores = data.Corredores;
    Buses = data.Buses;
    % primero hay que buscar el voltaje base
    id_bus_1 = Corredores(id_corr, 1);
    id_bus_2 = Corredores(id_corr, 2);
    vbase_1 = Buses(id_bus_1,2);
	vbase_2 = Buses(id_bus_2,2);
    
	nombre_bus1 = strcat('SE_', num2str(id_bus_1), '_VB_', num2str(vbase_1));
    nombre_bus2 = strcat('SE_', num2str(id_bus_2), '_VB_', num2str(vbase_2));
    se1 = sep.entrega_subestacion(nombre_bus1);
    if isempty(se1)
        se1 = pAdmProy.entrega_subestacion_proyectada_por_nombre(nombre_bus1);
    end
    
    se2 = sep.entrega_subestacion(nombre_bus2);
    if isempty(se2)
        se2 = pAdmProy.entrega_subestacion_proyectada_por_nombre(nombre_bus2);
    end

    vn_1 = se1.entrega_vn();
    vn_2 = se2.entrega_vn();

    ubicacion_1 = se1.entrega_ubicacion();
    ubicacion_2 = se2.entrega_ubicacion();
    if ubicacion_1 == 0 || ubicacion_2 == 0
        error = MException('importa_problema_optimizacion_tnep:genera_transformadores','Error en ubicación de las subestaciones. Hay una que no tiene valor');
        throw(error)
    end
    
	nmax = Corredores(id_corr,4);
	ElementosBase(id_corr).Nmax = nmax;

	id_trafos = ismember(Transformadores(:,1:2),[Corredores(id_corr,1) Corredores(id_corr,2)],'rows');
    TrafosAux = Transformadores(id_trafos,:); %contiene todos los trafos que pertenecen al corredor
    TrafosExistentes = TrafosAux(TrafosAux(:,7) ~= 0,:);
    TrafosNuevos = TrafosAux(TrafosAux(:,7) == 0,:);
    TrafosTotales = [TrafosExistentes; TrafosNuevos];
    [ntrafos_existentes, ~] = size(TrafosExistentes);
    
    ElementosBase(id_corr).NExistente = ntrafos_existentes;
    ElementosBase(id_corr).TipoTrafoBase = TrafosExistentes(1,5);
    for tpar = 1:nmax
        tipo_trafo_base = TrafosTotales(tpar, 5);
    	trafo = crea_transformador(TipoTrafos(tipo_trafo_base,:),se1, se2, tpar); 
        trafo.inserta_id_corredor(id_corr);
        if ntrafos_existentes >= tpar
        	trafo.inserta_anio_construccion(TrafosTotales(tpar, 7));
			trafo.Existente = true;					   
            trafo.Texto = ['E_' num2str(TrafosTotales(tpar, 8))];
            
            %agrega trafo al SEP
            sep.agrega_transformador(trafo);
            se1.agrega_transformador2D(trafo);
            se2.agrega_transformador2D(trafo);
            pAdmProy.inserta_elemento_serie_existente(trafo);
        else
        	trafo.Existente = false;
            trafo.Texto = ['N_' num2str(TrafosTotales(tpar, 8))];
            pAdmProy.inserta_elemento_serie_expansion(trafo);
        end
        
        if ntrafos_existentes == nmax
            % no hay "nuevos proyectos" en este corredor. Se desactiva flag de observación
            trafo.desactiva_flag_observacion();
        else
            % no es necesario, pero por si acaso (para entender mejor el
            % código)
            trafo.activa_flag_observacion();
        end
        % se guarda el tipo de trafo para transformador generado
        if tpar == 1
        	ElementosBase(id_corr).Elemento = trafo;
        else
            ElementosBase(id_corr).Elemento = [ElementosBase(id_corr).Elemento; trafo];
        end
    end
end

function [ElementosBase, LineasCC, LineasCS, LineasVU, TrafosVU] = genera_lineas(ElementosBase, LineasCC, LineasCS, LineasVU, TrafosVU, id_corr, data, param, sep, pAdmProy)
    Corredores = data.Corredores;
    Lineas = data.Lineas;
    Conductores = data.Conductores;
    Buses = data.Buses;
    
    largo = Corredores(id_corr, 3);
    
    id_bus_1 = Corredores(id_corr, 1);
    id_bus_2 = Corredores(id_corr, 2);
    vbase = Buses(id_bus_1,2);
    if Buses(id_bus_2,2) ~= vbase
        texto = ['Error en datos de entrada. Voltaje de buses no coincide, pero se trata de una línea. Id corredor ' num2str(id_corr) '. Bus1 ' num2str(id_bus_1) '. Bus2 ' num2str(id_bus_2)];
        texto = [texto '. Voltaje bus 1 ' num2str(vbase) '. Voltaje bus2 ' num2str(Buses(id_bus_2,2))];
        error = MException('importa_problema_optimizacion_tnep:genera_lineas',texto);
        throw(error)
    end

    nombre_bus1 = strcat('SE_', num2str(id_bus_1), '_VB_', num2str(vbase));
	nombre_bus2 = strcat('SE_', num2str(id_bus_2), '_VB_', num2str(vbase));
	se1 = sep.entrega_subestacion(nombre_bus1, false);
    if isempty(se1)
        se1 = pAdmProy.entrega_subestacion_proyectada_por_nombre(nombre_bus1);
    end

    se2 = sep.entrega_subestacion(nombre_bus2, false);
    if isempty(se2)
        se2 = pAdmProy.entrega_subestacion_proyectada_por_nombre(nombre_bus2);
    end
    
    if isempty(se1)
        texto = ['Error en datos de entrada o programación. En id_corr ' num2str(id_corr) ' no se puede encontrar se1 con nombre ' nombre_bus1];
        error = MException('importa_problema_optimizacion_tnep:genera_lineas',texto);
        throw(error)
    end
    if isempty(se2)
        texto = ['Error en datos de entrada o programación. En id_corr ' num2str(id_corr) ' no se puede encontrar se2 con nombre ' nombre_bus2];
        error = MException('importa_problema_optimizacion_tnep:genera_lineas',texto);
        throw(error)
    end

    vn = se1.entrega_vn();
        
	nmax = Corredores(id_corr,4);
    ElementosBase(id_corr).Nmax = nmax;

	id_lineas = ismember(Lineas(:,1:2),[Corredores(id_corr,1) Corredores(id_corr,2)],'rows');
	LineasAux = Lineas(id_lineas,:); %contiene todas las líneas que pertenecen al corredor
    LineasExistentes = LineasAux(LineasAux(:,7) == 1,:);
    LineasNuevas = LineasAux(LineasAux(:,7) == 0,:);
    LineasTotales = [LineasExistentes; LineasNuevas];
    [nlineas_existentes, ~] = size(LineasExistentes);

    % determina conductores para reconductoring
    % sólo si corredor se "puede expandir"
    con_reconductoring = false;
    if param.considera_reconductoring() && Corredores(id_corr,7) > 0 && nmax > nlineas_existentes && largo < 80
        % identifica conductor HTLS para este nivel de tensión
        con_reconductoring = true;
        conductores_comparar = [Conductores(:,2) Conductores(:,12)];
        indice = ismember(conductores_comparar, [2 vn],'rows');
        cond_htls = Conductores(indice,:);
        if isempty(cond_htls)
        	texto = ['Error en datos de entrada. No se puede considerar reconductoring, ya que no hay conductores HTLS para voltaje nominal ' num2str(vn)];
            %error = MException('importa_problema_optimizacion_tnep:genera_lineas',texto);
            %throw(error)
            warning(texto)
            con_reconductoring = false;
        else
            [ncond_htls, ~] = size(cond_htls);
            if ncond_htls > 1
                texto = ['Error en datos de entrada. Hay más de un conductor HTLS para voltaje nominal ' num2str(vnom)];
                error = MException('importa_problema_optimizacion_tnep:genera_lineas',texto);
                throw(error)
            end
        end
    end

    % determina conductores para compensación serie
    % sólo si corredor se puede expandir
    con_compensacion_serie = false;
	if param.considera_compensacion_serie() && Corredores(id_corr,6) > 0 && nmax > nlineas_existentes
        con_compensacion_serie = true;
    	Compensacion_serie = data.CompensacionSerie;        
        [ncomp_serie, ~] = size(Compensacion_serie);
%        texto = 'Error en parámetros. Compensación en serie no se ha implementado';
%        error = MException('importa_problema_optimizacion_tnep:genera_lineas',texto);
%        throw(error)
	end
    
    % determina conductores para VU y trafos
    con_voltage_uprating = false;
	VoltageUprating = data.VoltageUprating;
    if ~isempty(data.VoltageUprating)
        voltajes_vu = VoltageUprating(VoltageUprating(:,2)>vn,2);
        if Corredores(id_corr,5) > 0 && nlineas_existentes == 0 && param.elije_voltage_lineas_nuevas() && ~isempty(voltajes_vu)
            con_voltage_uprating = true;
            vu_con_conductor_actual = false;
            % en este caso se crean líneas con conductor acorde con
            % el voltaje. Para líneas cortas se considera conductor
            % base y HTLS (para el voltaje dado). Para líneas
            % largas sólo el conductor base del nuevo nivel de tensión
            if largo < 80
                conductores_comparar = [Conductores(:,12) Conductores(:,15)];
                expansion = ones(length(voltajes_vu),1);
                indices = ismember(conductores_comparar, [voltajes_vu expansion], 'rows');
                cond_vu = Conductores(indices,:);
            else
                conductores_comparar = [Conductores(:,2) Conductores(:,12) Conductores(:,15)];
                expansion = ones(length(voltajes_vu),1);
                indices = ismember(conductores_comparar, [expansion voltajes_vu expansion], 'rows');
                cond_vu = Conductores(indices,:);
            end
        end
    end    
    
    if Corredores(id_corr,5) > 0 && param.considera_voltage_uprating() && ~isempty(voltajes_vu) && nlineas_existentes > 0 && nmax > nlineas_existentes
        con_voltage_uprating = true;
        % ya hay líneas existentes. Se separan dos casos:
        % 1: voltage uprating se puede hacer con conductor
        % existente
        % 2: voltage uprating obliga a cambio de conductor
        if ~param.cambio_conductor_voltage_uprating()
            vu_con_conductor_actual = true;
            % caso 1: no es necesario cambiar de conductor. En
            % este caso se considera voltage uprating sólo para
            % conductor existente (no es la idea analizar
            % combinaciones de uprating)
            % no es necesario guardar el tipo de conductor
            %id_cond = conductor_base(1);
            %cond_vu = Conductores(id_cond,:);
        else
            % voltage uprating con cambio de conductor. Por ahora sólo
            % conductores convencionales
            vu_con_conductor_actual = false;
            conductores_comparar = [Conductores(:,2) Conductores(:,12) Conductores(:,15)];
            expansion = ones(length(voltajes_vu),1);
            indices = ismember(conductores_comparar, [expansion voltajes_vu expansion], 'rows');
            cond_vu = Conductores(indices,:);
        end
    end
        
    % se van creando las líneas dependiendo del tipo de conductor
    ElementosBase(id_corr).NExistente = nlineas_existentes;
    for lpar = 1:nmax
        % crea primero la línea base. Se separan los casos de líneas ya
        % existentes y los que no
        if lpar <= nlineas_existentes
            % línea existente. 
            id_cond = LineasTotales(lpar, 9);
            
            linea = crea_linea(Conductores(id_cond,:),Corredores(id_corr,:), data.Costos, se1, se2, lpar, id_corr);             

            linea.inserta_anio_construccion(LineasTotales(lpar, 10));
            linea.Existente = true;  % no es necesario pero para mejor comprension
            linea.TipoExpansion = 'Base';
            
            %agrega línea al SEP
            sep.agrega_linea(linea);
            se1.agrega_linea(linea);
            se2.agrega_linea(linea);
            linea.Texto = ['E_' num2str(LineasTotales(lpar, 11))];
            pAdmProy.inserta_elemento_serie_existente(linea);
        else
            % línea no existente. 
            id_cond = LineasTotales(lpar, 9);
            linea = crea_linea(Conductores(id_cond,:),Corredores(id_corr,:), data.Costos, se1, se2, lpar, id_corr);             
            linea.Existente = false;
            linea.TipoExpansion = 'Base';
            
            linea.Texto = ['N_' num2str(LineasTotales(lpar, 11))];
            pAdmProy.inserta_elemento_serie_expansion(linea);            
        end
        if nlineas_existentes == nmax && ~con_reconductoring && ~con_voltage_uprating && ~con_compensacion_serie
            % no hay "nuevos proyectos" en este corredor. Se desactiva flag de observación
            linea.desactiva_flag_observacion();
        else
            % no es necesario, pero por si acaso (para entender mejor el
            % código)
            linea.activa_flag_observacion();
        end
        
        % se guarda la línea generada
        ElementosBase(id_corr).Elemento = [ElementosBase(id_corr).Elemento; linea];
        
        % se crean líneas de reconductoring
        % sólo se considera HTLS y para voltaje base. No para voltajes
        % superiores
        if con_reconductoring && Corredores(id_corr,7) >= lpar
            % genera línea con conductor HTLS. Ojo que sólo hay un
            % conductor htls por cada nivel de tensión
            linea = crea_linea_htls(cond_htls,Corredores(id_corr,:), data.Costos, se1, se2, lpar, id_corr);
            linea.Texto = ['NCC_' num2str(LineasTotales(lpar, 11))];
            linea.TipoExpansion = 'CC';
            pAdmProy.inserta_elemento_serie_expansion(linea);
            if lpar == 1
                LineasCC(id_corr).Conductor(1).Linea = linea;
            else
                LineasCC(id_corr).Conductor(1).Linea = [LineasCC(id_corr).Conductor(1).Linea; linea];
            end
            LineasCC(id_corr).Existe = 1;
            linea.activa_flag_observacion();
        end
        
        if con_compensacion_serie
            % por cada tipo/cantidad de compensación, se crean nuevas
            % líneas (copia de las actuales) por cada tipo de conductor
            % existente
            for comp = 1:ncomp_serie
                porcentaje_comp = Compensacion_serie(comp,2);
                linea = ElementosBase(id_corr).Elemento(lpar).crea_copia();
                conductor_base = linea.entrega_tipo_conductor();
                id_se1 = se1().entrega_id();
                id_se2 = se2().entrega_id();
                nombre = strcat('L', num2str(lpar), '_C', num2str(conductor_base), '_Comp_', num2str(porcentaje_comp*100), ...
                    '_SE', num2str(id_se1), '_', num2str(id_se2));
                linea.inserta_nombre(nombre);
                costo_comp_mva = Compensacion_serie(comp,4);
                x = linea.entrega_reactancia();
                comp_total = x*porcentaje_comp;
                i_rated = linea.entrega_sth()/(sqrt(3)*vn); %kA
                Qcomp = comp_total*i_rated^2; %MVAr
                linea.inserta_compensacion_serie(porcentaje_comp);
                linea.inserta_costo_compensacion_serie(Qcomp*costo_comp_mva); %mio. USD
                linea.inserta_anio_construccion(0); %para estar seguro (en caso de que línea sea línea actual)
                linea.inserta_id(0); %idem arriba
                linea.Existente = false;
                linea.Texto = ['NCS' num2str(comp) '_' num2str(LineasTotales(lpar, 11))];
                linea.TipoExpansion = 'CS';
                
                % calcula nuevamente transferencia máxima
                %TODO hay que hacerlo con las curvas en forma
                %apropiada!!!
                x_ohm_km = linea.entrega_reactancia_pul();
                c_uF_km = linea.entrega_cpul();
                Zc = sqrt(x_ohm_km/(2*pi*50*c_uF_km)*1000000);
                SIL = vn^2/Zc;
                largo = linea.largo();
                factor_capacidad = entrega_cargabilidad_linea(largo);
                factor_capacidad = min(3, factor_capacidad);
                sr = factor_capacidad*SIL;
                sth = linea.entrega_sth();
                sr = min(sr, sth);
                linea.inserta_sr(sr);
                pAdmProy.inserta_elemento_serie_expansion(linea);

                if lpar == 1
                    LineasCS(id_corr).Conductor(conductor_base).Compensacion(comp).Linea = linea;
                    LineasCS(id_corr).Conductor(conductor_base).Compensacion(comp).Porcentaje = porcentaje_comp;
                    LineasCS(id_corr).Existe = 1;
                else
                    LineasCS(id_corr).Conductor(conductor_base).Compensacion(comp).Linea = [LineasCS(id_corr).Conductor(conductor_base).Compensacion(comp).Linea; linea];
                end
            end
        end
        
        if con_voltage_uprating && lpar <= Corredores(id_corr,5)
            voltaje_trafos = [];
            % TODO: Ojo que siguiente formulación funciona en realidad sólo
            % para un tipo de conductor VU y para 1 tipo de Trafo, cuya capacidad coincide con la capacidad de la línea!
            capacidad_linea_vu = 0;
            if vu_con_conductor_actual
                for i = 1:length(voltajes_vu)
                    vfinal = voltajes_vu(i);
                    nombre_bus1 = strcat('SE_', num2str(id_bus_1), '_VU_', num2str(vfinal));
                    nombre_bus2 = strcat('SE_', num2str(id_bus_2), '_VU_', num2str(vfinal));
                    se1_vur = pAdmProy.entrega_bus(nombre_bus1, false);
                    se2_vur = pAdmProy.entrega_bus(nombre_bus2, false);

                    if isempty(se1_vur)
                        id_vu = VoltageUprating(:,2) == vfinal;
                        costo_fijo = VoltageUprating(id_vu,3);
                        
                    	se1_vur = crea_nueva_subestacion(se1, vfinal, costo_fijo, pAdmProy);
                        % como es una nueva subestación (no uprating una existente), hay que
                        % agregar sus costos respectivos
                        pAdmProy.inserta_subestacion_expansion(se1_vur);
                    end
                    if isempty(se2_vur)
                        id_vu = VoltageUprating(:,2) == vfinal;
                        costo_fijo = VoltageUprating(id_vu,3);
                    	se2_vur = crea_nueva_subestacion(se2, vfinal, costo_fijo, pAdmProy);
                        pAdmProy.inserta_subestacion_expansion(se2_vur);
                    end

                    linea = crea_linea_voltage_uprating_mismo_conductor(ElementosBase(id_corr).Elemento(lpar), se1_vur, se2_vur);
                    linea.Texto = ['NVU_' num2str(LineasTotales(lpar, 11))];
                    linea.TipoExpansion = 'VU';
                
                    capacidad_linea_vu = linea.entrega_sr();
                    LineasVU(id_corr).Existe = 1;
                    if lpar == 1
                        LineasVU(id_corr).VUR(i).Conductor(1).Linea = [];
                        LineasVU(id_corr).VUR(i).Voltaje = vfinal;
                    end
                    LineasVU(id_corr).VUR(i).Conductor(1).Linea = [LineasVU(id_corr).VUR(i).Conductor(1).Linea; linea];
                    linea.Existente = false;
                    pAdmProy.inserta_elemento_serie_expansion(linea);
                    
                    voltaje_trafos(end+1,1) = vfinal;
                    voltaje_trafos(end, 2) = vn;
                end
            else
                % con distinto conductor
                [cant_cond_vu, ~] = size(cond_vu);
                for i = 1:cant_cond_vu
                    vfinal = cond_vu(i,12);
                    nombre_bus1 = strcat('SE_', num2str(id_bus_1), '_VU_', num2str(vfinal));
                    nombre_bus2 = strcat('SE_', num2str(id_bus_2), '_VU_', num2str(vfinal));
                    se1_vur = pAdmProy.entrega_bus(nombre_bus1, false);
                    se2_vur = pAdmProy.entrega_bus(nombre_bus2, false);

                    id_vu = VoltageUprating(:,2) == vfinal;
                    costo_fijo = VoltageUprating(id_vu,3);
                    if isempty(se1_vur)                        
                    	se1_vur = crea_nueva_subestacion(se1, vfinal, costo_fijo, pAdmProy);
                        % como es una nueva subestación (no uprating una existente), hay que
                        % agregar sus costos respectivos
                        pAdmProy.inserta_subestacion_expansion(se1_vur);
                    end
                    if isempty(se2_vur)
                    	se2_vur = crea_nueva_subestacion(se2, vfinal, costo_fijo, pAdmProy);
                        pAdmProy.inserta_subestacion_expansion(se2_vur);
                    end
                    
                    linea = crea_linea_voltage_uprating(cond_vu(i,:),Corredores(id_corr,:), data.Costos, se1_vur, se2_vur, lpar, id_corr);
                    linea.Texto = ['NVU_' num2str(LineasTotales(lpar, 11))];
                    linea.TipoExpansion = 'VU';
                    
                    capacidad_linea_vu = linea.entrega_sr();
                    
                    id_voltaje = voltajes_vu== cond_vu(i,12);
                    LineasVU(id_corr).Existe = 1;
                    if lpar == 1
                        LineasVU(id_corr).VUR(id_voltaje).Conductor(i).Linea = [];
                        LineasVU(id_corr).VUR(id_voltaje).Voltaje = vfinal;
                    end
                    LineasVU(id_corr).VUR(id_voltaje).Conductor(i).Linea = [LineasVU(id_corr).VUR(id_voltaje).Conductor(i).Linea; linea];
                    linea.Existente = false;
                    pAdmProy.inserta_elemento_serie_expansion(linea);
                    
                    if isempty(voltaje_trafos)
                        voltaje_trafos(end+1,1) = vfinal;
                        voltaje_trafos(end,2) = vn;
                    else
                        if ~ismember(voltaje_trafos, [vfinal, vn], 'rows')
                            voltaje_trafos(end+1,1) = vfinal;
                            voltaje_trafos(end,2) = vn;
                        end
                    end
                end
            end
                
            % se generan los transformadores en ambos lados si es que
            % aún no se han creado.
            ubicacion_1 = se1.entrega_ubicacion();
            ubicacion_2 = se2.entrega_ubicacion();
            TipoTrafos = data.TipoTransformadores;
            trafos_comparar = [TipoTrafos(:,3:4) TipoTrafos(:,9)];
            [ntipo, ~] = size(voltaje_trafos);
            expansion = ones(ntipo,1);
            indices = ismember(trafos_comparar, [voltaje_trafos expansion], 'rows');
            trafos_a_generar = TipoTrafos(indices,:);
            [ntipo, ~] = size(trafos_a_generar);
            for i = 1:ntipo
                vfinal = trafos_a_generar(i,3);
                nombre_bus1 = strcat('SE_', num2str(id_bus_1), '_VU_', num2str(vfinal));
                nombre_bus2 = strcat('SE_', num2str(id_bus_2), '_VU_', num2str(vfinal));
                se1_vur = pAdmProy.entrega_bus(nombre_bus1, false);
                se2_vur = pAdmProy.entrega_bus(nombre_bus2, false);
                if isempty(se1_vur) || isempty(se2_vur)
                	error = MException('cimporta_sep_power_flow_test:genera_lineas','subestación para transformadores no se pudo encontrar');
                    throw(error)
                end
                
                % verifica si trafos fueron creados
                crea_ubicacion_1 = false;
                crea_ubicacion_2 = false;
                trafo_creado = pAdmProy.entrega_elementos_serie_por_caracteristicas('cTransformador2D', ubicacion_1, vfinal, vn, lpar);
                if isempty(trafo_creado)
                    crea_ubicacion_1 = true;
                end
                trafo_creado = pAdmProy.entrega_elementos_serie_por_caracteristicas('cTransformador2D', ubicacion_2, vfinal, vn, lpar);
                if isempty(trafo_creado)
                    crea_ubicacion_2 = true;
                end
                
                if crea_ubicacion_1
                    if lpar == 1
                        TrafosVU(ubicacion_1).Existe = true;
                        TrafosVU(ubicacion_1).Tipo(i).Trafos = [];
                    end
                    
                    trafo = crea_transformador(trafos_a_generar(i,:), se1_vur, se1, lpar, capacidad_linea_vu);
                    trafo.activa_flag_observacion();
                    trafo.Existente = false;
                    trafo.Texto = 'NVU_T';
                    trafo.TipoExpansion = 'VU';
                                    
                    pAdmProy.inserta_elemento_serie_expansion(trafo);
                    TrafosVU(ubicacion_1).Tipo(i).Trafos = [TrafosVU(ubicacion_1).Tipo(i).Trafos; trafo]; 
                    TrafosVU(ubicacion_1).Nmax = TrafosVU(ubicacion_1).Nmax + 1;
                else
                    % verifica que capacidad de trafo sea la adecuada
                    trafo_ya_creado = pAdmProy.entrega_elementos_serie_por_caracteristicas('cTransformador2D', ubicacion_1, vfinal, vn, lpar);
                    sr_trafo = trafo_ya_creado.entrega_sr();
                    if sr_trafo < capacidad_linea_vu
                        % aumenta capacidad de trafo para que coincida con
                        % la capacidad de la línea
                        costo_fijo = trafos_a_generar(i,6);
                        costo_mva = trafos_a_generar(i,7);
                        costo_trafo = costo_fijo + costo_mva*capacidad_linea_vu;
                        trafo_ya_creado.inserta_sr(capacidad_linea_vu);
                        trafo_ya_creado.inserta_costo_transformador(costo_trafo);
                                                
                        x_ohm = trafos_a_generar(i,5);
                        uk = x_ohm*capacidad_linea_vu/vfinal^2;
                        trafo_ya_creado.inserta_uk(uk);                        
                        
                    end
                end
                
                if crea_ubicacion_2
                    if lpar == 1
                        TrafosVU(ubicacion_2).Existe = true;
                        TrafosVU(ubicacion_2).Tipo(i).Trafos = [];
                    end
                    trafo = crea_transformador(trafos_a_generar(i,:), se2_vur, se2, lpar, capacidad_linea_vu);
                    trafo.Existente = false;
                    trafo.Texto = 'NVU_T';

                    trafo.TipoExpansion = 'VU';
                    trafo.activa_flag_observacion();
                    pAdmProy.inserta_elemento_serie_expansion(trafo);
                    TrafosVU(ubicacion_2).Tipo(i).Trafos = [TrafosVU(ubicacion_2).Tipo(i).Trafos; trafo]; 
                    TrafosVU(ubicacion_2).Nmax = TrafosVU(ubicacion_2).Nmax + 1;
                else
                    trafo_ya_creado = pAdmProy.entrega_elementos_serie_por_caracteristicas('cTransformador2D', ubicacion_2, vfinal, vn, lpar);
                    sr_trafo = trafo_ya_creado.entrega_sr();
                    if sr_trafo < capacidad_linea_vu
                        % aumenta capacidad de trafo para que coincida con
                        % la capacidad de la línea
                        costo_fijo = trafos_a_generar(i,6);
                        costo_mva = trafos_a_generar(i,7);
                        costo_trafo = costo_fijo + costo_mva*capacidad_linea_vu;
                        trafo_ya_creado.inserta_sr(capacidad_linea_vu);
                        trafo_ya_creado.inserta_costo_transformador(costo_trafo);
                        
                        x_ohm = trafos_a_generar(i,5);
                        uk = x_ohm*capacidad_linea_vu/vfinal^2;
                        trafo_ya_creado.inserta_uk(uk);                        
                        
                    end
                end
            end
        end
    end
end

function genera_proyectos_expansion(elementos_generados, pAdmProy, pParOpt)
    ElementosBase = elementos_generados.ElementosBase;
    LineasCC = elementos_generados.LineasCC;
    LineasCS = elementos_generados.LineasCS;
    LineasVU = elementos_generados.LineasVU;
    TrafosVU = elementos_generados.TrafosVU;
    Baterias = elementos_generados.Baterias;
    
    estados_secundarios = genera_proyectos_expansion_subestaciones_transformadores_vu(TrafosVU, pAdmProy);
    estados_primarios = genera_proyectos_expansion_corredores(ElementosBase, LineasCC, LineasCS, LineasVU, pAdmProy, pParOpt);
    estados_primarios = genera_proyectos_expansion_elementos_paralelos(estados_primarios, Baterias,  pAdmProy); % por ahora sólo baterias
        
    pAdmProy.inserta_matriz_estados_decision_secundaria(estados_secundarios.MatrizEstados);
    pAdmProy.inserta_capacidad_por_estado_decisiones_secundarias(estados_secundarios.CapacidadPorEstado);

    pAdmProy.inserta_matriz_estados_decision_primaria_tx(estados_primarios.MatrizEstados);
    pAdmProy.inserta_capacidad_por_estado_decisiones_primarias_tx(estados_primarios.CapacidadPorEstado);
    pAdmProy.inserta_estados_iniciales_decision_primaria_tx(estados_primarios.EstadosIniciales);
    %pAdmProy.inserta_tipo_decision_primaria(estados_primarios.TipoEstado);
end

function estados_secundarios = genera_proyectos_expansion_subestaciones_transformadores_vu(TrafosVU, pAdmProy)
    % primero genera proyectos de subestaciones
    se_nuevas = pAdmProy.entrega_subestaciones_expansion();
    
    for i = 1:length(se_nuevas)
        proy = crea_proyecto_agrega_subestacion(se_nuevas(i));
        proy.inserta_etapas_entrada_en_operacion(1);
        proy.EsUprating = true;
        pAdmProy.agrega_proyecto_auxiliar(proy);
    end
    
    % TrafosVU(id_ubicacion).Tipo(id_tipo).Trafos = [(T1,id_tipo), ...]
    % TrafosVU(id_ubicacion).Existe = 0 (no hay), 1
    % TrafosVU(id_ubicacion).Nmax indica cantidad trafos paralelos

    MatrizEstados = [];
    CapacidadPorEstado = [];
    
    id_decision = 0;
    for ubic = 1:length(TrafosVU)
        if ~TrafosVU(ubic).Existe
            continue;
        end
        id_decision = id_decision + 1;
        EstadosTrafo = [];
        id_estado = 0;
        cant_tipo = length(TrafosVU(ubic).Tipo);
        cant_trafos_par = length(TrafosVU(ubic).Tipo(1).Trafos);
        CapacidadPorEstado(id_decision).Capacidad = zeros(cant_trafos_par, cant_tipo);
        for id_tipo = 1:length(TrafosVU(ubic).Tipo)
            if ~isempty(TrafosVU(ubic).Tipo(id_tipo).Trafos)
                EstadosTrafo(length(EstadosTrafo)+1,1) = id_tipo;
                id_estado = id_estado + 1;
                
                for i = 1:length(TrafosVU(ubic).Tipo(id_tipo).Trafos)
                    TrafosVU(ubic).Tipo(id_tipo).Trafos(i).inserta_id_estado_planificacion(id_estado);
                    TrafosVU(ubic).Tipo(id_tipo).Trafos(i).inserta_indice_decision_expansion(0);
                    TrafosVU(ubic).Tipo(id_tipo).Trafos(i).inserta_indice_decision_expansion_secundaria(id_decision);
                    sr = TrafosVU(ubic).Tipo(id_tipo).Trafos(i).entrega_sr();
                    MatrizEstados(id_decision).Estado(i,id_estado).Nombre{1,1} = ['T' num2str(i)];
                    MatrizEstados(id_decision).Estado(i,id_estado).Nombre{1,2} = ['S' num2str(sr)];
                    CapacidadPorEstado(id_decision).Capacidad(i,id_estado) = CapacidadPorEstado(id_decision).Capacidad(i,id_estado) + sr;
                end
            end
        end

        [ne_tr, ~] = size(EstadosTrafo);

        for ipar = 1:TrafosVU(ubic).Nmax
            if ipar > 1
                % ya hay estados conducentes
                EstadosConducentes = EstadosConducentesNuevo;
            else
                for i = 1:ne_tr
                    % sólo un proyecto por estado
                    EstadosConducentes{i} = cProyectoExpansion.empty;
                end
            end
            % se borran los estados conducentes nuevos
                
            for i = 1:ne_tr
            	EstadosConducentesNuevo{i}= cProyectoExpansion.empty;
            end
            
            proy_excluyentes = cProyectoExpansion.empty;
            for i = 1:ne_tr
                id_tipo = EstadosTrafo(i);
                trafo = TrafosVU(ubic).Tipo(id_tipo).Trafos(ipar);
                id_estado = trafo.entrega_id_estado_planificacion();
                proy = crea_proyecto_agrega_transformador(trafo, 'AV'); % a futuro, cuando se tengan "transformadores base", se indica aquí "Base" en vez de "AV"
                proy.EsUprating = true;
                proy.inserta_etapas_entrada_en_operacion(1);
                proy.inserta_indice_decision_expansion(id_decision);
                proy.inserta_estado_conducente(ipar, id_estado);
                proy.inserta_estado_inicial(ipar-1, id_estado);
                pAdmProy.agrega_proyecto_secundario(proy, id_decision);
                proy.inserta_capacidad_adicional(trafo.entrega_sr());
                
                MatrizEstados(id_decision).Estado(ipar, id_estado).ProyectosEntrantes = proy; %por ahora no hay "cambio" de trafos 
                MatrizEstados(id_decision).Estado(ipar, id_estado).IdProyectosEntrantes = proy.entrega_indice();
                if ipar == 1
                    proy_excluyentes(end+1) = proy;
                else
                    MatrizEstados(id_decision).Estado(ipar-1, id_estado).ProyectosSalientes = proy;
                    MatrizEstados(id_decision).Estado(ipar-1, id_estado).IdProyectosSalientes = proy.entrega_indice();
                end
                if TrafosVU(ubic).Nmax == 1
                    MatrizEstados(id_decision).Estado(ipar, id_estado).ProyectosSalientes = cProyectoExpansion.empty;
                end
                if ~isempty(EstadosConducentes{i})
                    proy.TieneDependencia = true;
                    proy.inserta_proyectos_dependientes(EstadosConducentes{i});
                end

                EstadosConducentesNuevo{i} = proy;
            end
            if length(proy_excluyentes) > 1
                pAdmProy.agrega_proyectos_tx_excluyentes(proy_excluyentes);
            end
        end
    end
    estados_secundarios.MatrizEstados = MatrizEstados;
    estados_secundarios.CapacidadPorEstado = CapacidadPorEstado;
end

function estados_primarios = genera_proyectos_expansion_elementos_paralelos(estados_primarios, ElementosBase, pAdmProy)
    % MatrizEstadosCorredores(idCorredor).Estado(parindex, no_estado).ProyectosSalientes = [Pr1; Pr2; ...]
    
    for id_bus = 1:length(ElementosBase)
        estados_primarios = genera_proyectos_expansion_baterias(id_bus, estados_primarios, ElementosBase, pAdmProy);
    end
end

function estados_primarios = genera_proyectos_expansion_baterias(id_bus, estados_primarios, ElementosBase, pAdmProy)
    MatrizEstados = estados_primarios.MatrizEstados;
    CapacidadPorEstado = estados_primarios.CapacidadPorEstado;
    EstadosIniciales = estados_primarios.EstadosIniciales;
    TipoEstado = estados_primarios.TipoEstado;

	baterias_existentes = ElementosBase(id_bus).NExistente;
    if baterias_existentes > 0
        error = MException('cimporta_problema_optimizacion_tnep:genera_proyectos_expansion_baterias','Por ahora no se ha visto el caso en donde hay baterias existentes!');
        throw(error)
    end
    nmax = ElementosBase(id_bus).Nmax;
    tipo_bateria_base = ElementosBase(id_bus).TipoBaseExistente;

    if isempty(nmax) || nmax<= baterias_existentes
        return
    end
    
    id_decision = length(MatrizEstados) + 1;
    MatrizEstados(id_decision).Largo = 0;
    TipoEstado(id_decision) = 2;
    
    id_estado = 1;
    %EstadosBase = tipo_trafo_base;
    existe_corredor = false;
    tipo_bateria_base = ElementosBase(id_bus).TipoBaseExistente;
    cant_tipos = length(ElementosBase(id_bus).Tipo);
    for i = 1:nmax        
        for j = 1:cant_tipos
            ElementosBase(id_bus).Tipo(j).Elemento(i).inserta_id_estado_planificacion(id_estado);
            ElementosBase(id_bus).Tipo(j).Elemento(i).inserta_indice_decision_expansion(id_decision);
            
            MatrizEstados(id_decision).Estado(i,j).ProyectosEntrantes = [];
            MatrizEstados(id_decision).Estado(i,j).ProyectosSalientes = [];
            MatrizEstados(id_decision).Estado(i,j).IdProyectosEntrantes = [];
            MatrizEstados(id_decision).Estado(i,j).IdProyectosSalientes = [];
            MatrizEstados(id_decision).Estado(i,j).Nombre{1,1} = ['S' num2str(i)];
            MatrizEstados(id_decision).Estado(i,j).Nombre{1,2} = ['Tipo_' num2str(j)]; 
        end
    end

    CapacidadPorEstado(id_decision).Capacidad = zeros(nmax, cant_tipos);

    if baterias_existentes > 1
        for i = 1:baterias_existentes
            sr = ElementosBase(id_bus).Tipo(tipo_bateria_base).Elemento(i).entrega_pmax_carga();
            CapacidadPorEstado(id_decision).Capacidad(i,tipo_bateria_base) = sr;
        end
        EstadosIniciales(id_decision,:) = [baterias_existentes, tipo_bateria_base];
    else
        EstadosIniciales(id_decision,:) = [0, 1];        
    end
    
    for bpar = baterias_existentes:nmax
        if bpar > 0
            % ya hay estados conducentes
            EstadosConducentes = EstadosConducentesNuevo;
        else
            % aún no se han definido los estados conducentes
            for tipo_bat = 1:cant_tipos
                EstadosConducentes.Base(tipo_bat).Proyectos = cProyectoExpansion.empty;
            end
        end
        

        % se borran los estados conducentes nuevos
        for tipo_bat = 1:cant_tipos
            EstadosConducentesNuevo.Base(tipo_bat).Proyectos = cProyectoExpansion.empty;
        end
        
        if bpar == 0
            % conducente a los estados bpar = 1
            % no hay baterias. No hay proyectos excluyentes!
            proy_excluyentes = cProyectoExpansion.empty;
            for tipo_bat = 1:cant_tipos
                %proyecto base
                bateria = ElementosBase(id_bus).Tipo(tipo_bat).Elemento(bpar+1);
                proy = crea_proyecto_agrega_bateria(bateria);
                proy.EsUprating = false;
                proy.inserta_etapas_entrada_en_operacion(1);
            
                pAdmProy.agrega_proyecto_tx_primario(proy, id_decision);
                proy_excluyentes(end+1) = proy;
                EstadosConducentesNuevo.Base(tipo_bat).Proyectos = proy;
                % MatrizEstadosCorredores(idCorredor).Estado(parindex, no_estado).ProyectosSalientes = [Pr1; Pr2; ...]
                id_estado_inicial = bateria.entrega_id_estado_planificacion();
                MatrizEstados(id_decision).Estado(bpar+1,id_estado_inicial).ProyectosEntrantes = proy;
                MatrizEstados(id_decision).Estado(bpar+1,id_estado_inicial).IdProyectosEntrantes = proy.entrega_indice();

                sr = bateria.entrega_pmax_carga();
            
                CapacidadPorEstado(id_decision).Capacidad(1,tipo_bat) = sr;

                proy.inserta_indice_decision_expansion(id_decision);
                proy.inserta_estado_conducente(bpar+1, id_estado_inicial);
                proy.inserta_estado_inicial(bpar, id_estado_inicial);
                proy.inserta_capacidad_adicional(sr);
            end
            if length(proy_excluyentes) > 1
                pAdmProy.agrega_proyectos_tx_excluyentes(proy_excluyentes);
            end
        else
            % ya existen baterías. Por cada estado, se agrega proyecto
            % "agregar bateria". No hay cambios de estado
            % No se consideran cambios de estado entre baterías, por lo que
            % no hay proyectos excluyentes
            %proy_excluyentes = cProyectoExpansion.empty;
            for tipo_bat = 1:cant_tipos    
                % Sólo si aún quedan baterias por agregar
                if bpar + 1 <= nmax
                    bateria = ElementosBase(id_bus).Tipo(tipo_bat).Elemento(bpar+1);
                    proy = crea_proyecto_agrega_bateria(bateria);
                    proy.EsUprating = false;
                    proy.inserta_etapas_entrada_en_operacion(1);

                    if ~isempty(EstadosConducentes.Base(tipo_bat).Proyectos)
                        proy.TieneDependencia = true;
                        proy.inserta_proyectos_dependientes(EstadosConducentes.Base(tipo_bat).Proyectos);
                    end
                
                    pAdmProy.agrega_proyecto_tx_primario(proy, id_decision);
                    %proy_excluyentes(end+1) = proy;
                    EstadosConducentesNuevo.Base(tipo_bat).Proyectos = proy;

                    id_estado_final = bateria.entrega_id_estado_planificacion();
                    MatrizEstados(id_decision).Estado(bpar+1,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_decision).Estado(bpar+1,id_estado_final).ProyectosEntrantes proy];
                    MatrizEstados(id_decision).Estado(bpar,id_estado_final).ProyectosSalientes = [MatrizEstados(id_decision).Estado(bpar,id_estado_final).ProyectosSalientes proy];
                    MatrizEstados(id_decision).Estado(bpar+1,id_estado_final).IdProyectosEntrantes = [MatrizEstados(id_decision).Estado(bpar+1,id_estado_final).IdProyectosEntrantes proy.entrega_indice()];
                    MatrizEstados(id_decision).Estado(bpar,id_estado_final).IdProyectosSalientes = [MatrizEstados(id_corid_decision).Estado(bpar,id_estado_final).IdProyectosSalientes proy.entrega_indice()];

                    sr = bateria.entrega_pmax_carga();
                    CapacidadPorEstado(id_decision).Capacidad(bpar+1,tipo_bat) = (bpar+1)*sr;
                    
                    proy.inserta_indice_decision_expansion(id_decision);
                    proy.inserta_estado_conducente(bpar+1, id_estado_inicial);
                    proy.inserta_estado_inicial(bpar, id_estado_inicial);                    
                    proy.inserta_capacidad_adicional(sr);
                end

                % fin de creación de proyectos a partir de los proyectos
                % base. Se agrega set de proyectos excluyentes

                %if length(proy_excluyentes) > 1
                %    pAdmProy.agrega_proyectos_tx_excluyentes(proy_excluyentes);
                %end
            end
        end
    end
    estados_primarios.MatrizEstados = MatrizEstados;
    estados_primarios.CapacidadPorEstado = CapacidadPorEstado;
    estados_primarios.EstadosIniciales = EstadosIniciales;
    estados_primarios.TipoEstado = TipoEstado;
end

function estados_primarios = genera_proyectos_expansion_corredores(ElementosBase, LineasCC, LineasCS, LineasVU, pAdmProy, pParOpt)
    % MatrizEstadosCorredores(idCorredor).Estado(parindex, no_estado).ProyectosSalientes = [Pr1; Pr2; ...]
    
    estados_primarios.MatrizEstados = [];
    estados_primarios.CapacidadPorEstado = [];
    estados_primarios.EstadosIniciales = [];
    estados_primarios.TipoEstado = [];
    
    for id_corr = 1:length(ElementosBase)
        largo = ElementosBase(id_corr).Largo;
        if largo > 0
            estados_primarios = genera_proyectos_expansion_lineas(id_corr, estados_primarios, ElementosBase, LineasCC, LineasCS, LineasVU, pAdmProy, pParOpt);
        else
            estados_primarios = genera_proyectos_expansion_transformadores(id_corr, estados_primarios, ElementosBase, pAdmProy);
        end
    end
end

function estados_primarios = genera_proyectos_expansion_lineas(id_corr, estados_primarios, ElementosBase, LineasCC, LineasCS, LineasVU, pAdmProy, pParOpt)
    MatrizEstados = estados_primarios.MatrizEstados;
    CapacidadPorEstado = estados_primarios.CapacidadPorEstado;
    EstadosIniciales = estados_primarios.EstadosIniciales;
    TipoEstado = estados_primarios.TipoEstado;
    
    considera_transicion_estados = pParOpt.ConsideraTransicionEstados;
	lineas_existentes = ElementosBase(id_corr).NExistente;
    nmax = ElementosBase(id_corr).Nmax;
    largo = ElementosBase(id_corr).Largo;
    
    if nmax <= lineas_existentes
        % nada que hacer
        return
    end
    
    %conductor_base = ElementosBase(id_corr).ConductorBase;

    id_estado = 1;
    %EstadosBase = conductor_base;
    EstadosCC = [];
    EstadosCS = [];
    EstadosVU = [];
    id_decision = length(MatrizEstados);
    id_decision = id_decision + 1;

    MatrizEstados(id_decision).Largo = ElementosBase(id_corr).Elemento(1).largo();
    TipoEstado(id_decision) = 1;
    for i = 1:nmax
        ElementosBase(id_corr).Elemento(i).inserta_id_estado_planificacion(id_estado);
        ElementosBase(id_corr).Elemento(i).inserta_indice_decision_expansion(id_decision);
        
        tipo_conductor = ElementosBase(id_corr).Elemento(i).entrega_tipo_conductor();
        MatrizEstados(id_decision).Estado(i,id_estado).ProyectosEntrantes = [];
        MatrizEstados(id_decision).Estado(i,id_estado).ProyectosSalientes = [];
        MatrizEstados(id_decision).Estado(i,id_estado).IdProyectosEntrantes = [];
        MatrizEstados(id_decision).Estado(i,id_estado).IdProyectosSalientes = [];
        MatrizEstados(id_decision).Estado(i,id_estado).Nombre{1,1} = ['L' num2str(i)];
        MatrizEstados(id_decision).Estado(i,id_estado).Nombre{1,2} = ['C' num2str(tipo_conductor)];
    end
        
    if LineasCC(id_corr).Existe
        for id_cond = 1:length(LineasCC(id_corr).Conductor)
        	if ~isempty(LineasCC(id_corr).Conductor(id_cond).Linea)
                EstadosCC(length(EstadosCC)+1,1) = id_cond;
                id_estado = id_estado + 1;
                for i = 1:length(LineasCC(id_corr).Conductor(id_cond).Linea)
                	LineasCC(id_corr).Conductor(id_cond).Linea(i).inserta_id_estado_planificacion(id_estado);
                    LineasCC(id_corr).Conductor(id_cond).Linea(i).inserta_indice_decision_expansion(id_decision);
                    tipo_conductor = LineasCC(id_corr).Conductor(id_cond).Linea(i).entrega_tipo_conductor();
                    MatrizEstados(id_decision).Estado(i,id_estado).ProyectosEntrantes = [];
                    MatrizEstados(id_decision).Estado(i,id_estado).ProyectosSalientes = [];
                    MatrizEstados(id_decision).Estado(i,id_estado).IdProyectosEntrantes = [];
                    MatrizEstados(id_decision).Estado(i,id_estado).IdProyectosSalientes = [];
                    MatrizEstados(id_decision).Estado(i,id_estado).Nombre{1,1} = ['L' num2str(i)];
                    MatrizEstados(id_decision).Estado(i,id_estado).Nombre{1,2} = ['CC' num2str(tipo_conductor)]; 
                end
            end
        end
    end
    
    if LineasCS(id_corr).Existe
        for id_cond = 1:length(LineasCS(id_corr).Conductor)
            for comp = 1:length(LineasCS(id_corr).Conductor(id_cond).Compensacion)
                if ~isempty(LineasCS(id_corr).Conductor(id_cond).Compensacion(comp).Linea)
                	[ne, ~] = size(EstadosCS);
                    EstadosCS(ne+1,1) = id_cond;
                    EstadosCS(ne+1,2) = comp;
                    id_estado = id_estado + 1;
                    for i = 1:length(LineasCS(id_corr).Conductor(id_cond).Compensacion(comp).Linea)
                    	LineasCS(id_corr).Conductor(id_cond).Compensacion(comp).Linea(i).inserta_id_estado_planificacion(id_estado);
                        LineasCS(id_corr).Conductor(id_cond).Compensacion(comp).Linea(i).inserta_indice_decision_expansion(id_decision);
                        compensacion = LineasCS(id_corr).Conductor(id_cond).Compensacion(comp).Linea(i).entrega_compensacion_serie()*100;
                        MatrizEstados(id_decision).Estado(i,id_estado).ProyectosEntrantes = [];
                        MatrizEstados(id_decision).Estado(i,id_estado).ProyectosSalientes = [];
                        MatrizEstados(id_decision).Estado(i,id_estado).IdProyectosEntrantes = [];
                        MatrizEstados(id_decision).Estado(i,id_estado).IdProyectosSalientes = [];
                        MatrizEstados(id_decision).Estado(i,id_estado).Nombre{1,1} = ['L' num2str(i)];
                        MatrizEstados(id_decision).Estado(i,id_estado).Nombre{1,2} = ['CS_' num2str(compensacion)]; 
                    end
                end
            end
        end
    end
    
    if LineasVU(id_corr).Existe
        for vur = 1:length(LineasVU(id_corr).VUR)
        	for id_cond = length(LineasVU(id_corr).VUR(vur).Conductor)
                if ~isempty(LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea)
                	[ne, ~] = size(EstadosVU);
                    EstadosVU(ne+1,1) = id_cond;
                    EstadosVU(ne+1,2) = vur;
                    id_estado = id_estado + 1;
                    for i = 1:length(LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea)
                    	LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea(i).inserta_id_estado_planificacion(id_estado);
                        LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea(i).inserta_indice_decision_expansion(id_decision);
                        voltaje = LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea(i).entrega_se1().entrega_vn();
                        MatrizEstados(id_decision).Estado(i,id_estado).ProyectosEntrantes = [];
                        MatrizEstados(id_decision).Estado(i,id_estado).ProyectosSalientes = [];
                        MatrizEstados(id_decision).Estado(i,id_estado).IdProyectosEntrantes = [];
                        MatrizEstados(id_decision).Estado(i,id_estado).IdProyectosSalientes = [];
                        MatrizEstados(id_decision).Estado(i,id_estado).Nombre{1,1} = ['L' num2str(i)];
                        MatrizEstados(id_decision).Estado(i,id_estado).Nombre{1,2} = ['AV_' num2str(voltaje)]; 
                    end
                end
            end
        end
    end
    
    CapacidadPorEstado(id_decision).Capacidad = zeros(nmax, id_estado); % id_estado contiene la cantidad de estados del corredor

    [ne_cc, ~] = size(EstadosCC);
    [ne_cs, ~] = size(EstadosCS);
    [ne_vu, ~] = size(EstadosVU);

    if lineas_existentes > 0
        for j = 1:lineas_existentes         
            linea = ElementosBase(id_corr).Elemento(j);
            sr = linea.entrega_sr();
            id_estado_inicial = linea.entrega_id_estado_planificacion();
            CapacidadPorEstado(id_corr).Capacidad(j,id_estado_inicial) = j*sr;
            if id_estado_inicial ~= 1
                error = MException('cimporta_problema_optimizacion_tnep:genera_proyectos_expansion_lineas','id_estado_inicial de linea existente no es 1. Error de datos de entrada');
                throw(error)
            end
        end
        EstadosIniciales(id_corr,:) = [lineas_existentes, 1];
    else
        EstadosIniciales(id_corr,:) = [0, 1];        
    end
    
    for lpar = lineas_existentes:nmax
        if lpar > lineas_existentes
        	% ya hay estados conducentes
            EstadosConducentes = EstadosConducentesNuevo;
        else
        	% aún no se han definido los estados conducentes
            EstadosConducentes.Base(1).Proyectos = cProyectoExpansion.empty;
                
            for i = 1:ne_cc
            	EstadosConducentes.CC(i).Proyectos = cProyectoExpansion.empty;
            end
            for i = 1:ne_cs
            	EstadosConducentes.CS(i).Proyectos = cProyectoExpansion.empty;
            end
            for i = 1:ne_vu
            	EstadosConducentes.VU(i).Proyectos = cProyectoExpansion.empty;
            end
        end
            
        % se borran los estados conducentes nuevos
        EstadosConducentesNuevo.Base(1).Proyectos = cProyectoExpansion.empty;
                
        for i = 1:ne_cc
        	EstadosConducentesNuevo.CC(i).Proyectos = cProyectoExpansion.empty;
        end
        for i = 1:ne_cs
        	EstadosConducentesNuevo.CS(i).Proyectos = cProyectoExpansion.empty;
        end
        for i = 1:ne_vu
        	EstadosConducentesNuevo.VU(i).Proyectos = cProyectoExpansion.empty;
        end

        if lpar == 0
        	% conducente a los estados lpar = 1
            % no hay líneas. Se agregan todos los proyectos. Cada
            % proyecto generado crea grupo de proyectos excluyentes                
            proy_excluyentes = cProyectoExpansion.empty;
                
            %proyecto base
            linea = ElementosBase(id_corr).Elemento(lpar+1);

            linea_base_nuevo_corredor = linea; % para agregar proyectos nuevo corredor en caso de que haya un proyecto de VU
            
            proy = crea_proyecto_agrega_linea(linea, 'Base');
            proy.EsUprating = false;
            proy.inserta_etapas_entrada_en_operacion(pParOpt.TiempoEntradaOperacionTradicional);

            pAdmProy.agrega_proyecto_tx_primario(proy, id_decision);
            proy_excluyentes(end+1) = proy;
            EstadosConducentesNuevo.Base(1).Proyectos = proy;
            % MatrizEstadosCorredores(idCorredor).Estado(parindex, no_estado).ProyectosSalientes = [Pr1; Pr2; ...]
            id_estado_inicial = linea.entrega_id_estado_planificacion();
            MatrizEstados(id_decision).Estado(lpar+1,id_estado_inicial).ProyectosEntrantes = proy;
            MatrizEstados(id_decision).Estado(lpar+1,id_estado_inicial).IdProyectosEntrantes = proy.entrega_indice();

            CapacidadPorEstado(id_decision).Capacidad(lpar+1,id_estado_inicial) = linea.entrega_sr();

            proy.inserta_indice_decision_expansion(id_decision);
            proy.inserta_estado_conducente(lpar+1, id_estado_inicial);
            proy.inserta_estado_inicial(lpar, id_estado_inicial);
            proy.inserta_capacidad_adicional(linea.entrega_sr());
            pAdmProy.inserta_proyecto_nuevo_corredor(proy);

            % reconductoring
            for i = 1:ne_cc
                id_cond = EstadosCC(i);
                linea = LineasCC(id_corr).Conductor(id_cond).Linea(lpar+1);
                proy = crea_proyecto_agrega_linea(linea, 'CC');
                proy.inserta_etapas_entrada_en_operacion(pParOpt.TiempoEntradaOperacionTradicional);
                proy.EsUprating = true;
                pAdmProy.agrega_proyecto_tx_primario(proy, id_decision);
                proy_excluyentes(end+1) = proy;
                EstadosConducentesNuevo.CC(i).Proyectos = proy;
    
                id_estado_final = linea.entrega_id_estado_planificacion();
                MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).ProyectosEntrantes  proy];
                MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).IdProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).IdProyectosEntrantes proy.entrega_indice()];
            
                CapacidadPorEstado(id_decision).Capacidad(lpar+1,id_estado_final) = linea.entrega_sr();

                proy.inserta_indice_decision_expansion(id_decision);
                proy.inserta_estado_conducente(lpar+1, id_estado_final);
                proy.inserta_estado_inicial(lpar, 1);
                proy.inserta_capacidad_adicional(linea.entrega_sr());
                
                pAdmProy.inserta_proyecto_nuevo_corredor(proy);
                
            end
                
            % compensacion serie
            for i = 1:ne_cs
            	id_cond = EstadosCS(i,1);
                comp = EstadosCS(i,2);
                linea = LineasCS(id_corr).Conductor(id_cond).Compensacion(comp).Linea(lpar+1);
                proy = crea_proyecto_agrega_linea(linea, 'CS');
                proy.inserta_etapas_entrada_en_operacion(pParOpt.TiempoEntradaOperacionTradicional);
                proy.EsUprating = true;
                pAdmProy.agrega_proyecto_tx_primario(proy, id_decision);
                proy_excluyentes(end+1) = proy;
                EstadosConducentesNuevo.CS(i).Proyectos = proy;

                id_estado_final = linea.entrega_id_estado_planificacion();
                MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).ProyectosEntrantes proy];
                MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).IdProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).IdProyectosEntrantes proy.entrega_indice()];
                
                CapacidadPorEstado(id_decision).Capacidad(lpar+1,id_estado_final) = linea.entrega_sr();

                proy.inserta_indice_decision_expansion(id_decision);
                proy.inserta_estado_conducente(lpar+1, id_estado_final);
                proy.inserta_estado_inicial(lpar,1);
                proy.inserta_capacidad_adicional(linea.entrega_sr());
                pAdmProy.inserta_proyecto_nuevo_corredor(proy);
                
            end
                
            % voltage uprating
            for i = 1:ne_vu
            	id_cond = EstadosVU(i,1);
                vur = EstadosVU(i,2);
                linea = LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea(lpar+1);
                proy = crea_proyecto_agrega_linea(linea, 'AV');
                proy.inserta_etapas_entrada_en_operacion(pParOpt.TiempoEntradaOperacionTradicional);
                proy.EsUprating = true;
                pAdmProy.agrega_proyecto_tx_primario(proy, id_decision);
                proy_excluyentes(end+1) = proy;
                EstadosConducentesNuevo.VU(i).Proyectos = proy;

                id_estado_final = linea.entrega_id_estado_planificacion();
                MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).ProyectosEntrantes proy];
                MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).IdProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).IdProyectosEntrantes proy.entrega_indice()];
                
                CapacidadPorEstado(id_decision).Capacidad(lpar+1,id_estado_final) = linea.entrega_sr();

                % como es línea nueva, hay que poner ingresar proyectos
                % de conectividad. Se ingresan sólo transformadores, ya
                % que estos, a su vez, tienen a la subestación como
                % requisito de conectividad
                proy.TieneRequisitosConectividad = true;
                proy_conectividad_se1 = pAdmProy.entrega_proyecto_subestacion(linea.entrega_se1());
                proy_conectividad_se2 = pAdmProy.entrega_proyecto_subestacion(linea.entrega_se2());                
                proy_conectividad_trafos_se1 = pAdmProy.entrega_proyectos_transformadores(linea.entrega_se1(), 1); %1 es índice paralelo
                proy_conectividad_trafos_se2 = pAdmProy.entrega_proyectos_transformadores(linea.entrega_se2(),1);                
                proy.inserta_grupo_proyectos_conectividad(proy_conectividad_se1);
                proy.inserta_grupo_proyectos_conectividad(proy_conectividad_se2);
                proy.inserta_grupo_proyectos_conectividad(proy_conectividad_trafos_se1);
                proy.inserta_grupo_proyectos_conectividad(proy_conectividad_trafos_se2);

                proy.inserta_indice_decision_expansion(id_decision);
                proy.inserta_estado_conducente(lpar+1, id_estado_final);
                proy.inserta_estado_inicial(lpar, 1);
                proy.inserta_capacidad_adicional(linea.entrega_sr());
                
                pAdmProy.inserta_proyecto_nuevo_corredor(proy, linea_base_nuevo_corredor.entrega_se1().entrega_id(), linea_base_nuevo_corredor.entrega_se2().entrega_id());
             
            end
            if length(proy_excluyentes) > 1
            	pAdmProy.agrega_proyectos_tx_excluyentes(proy_excluyentes);
            end
        else
            % ya existen líneas. Por cada estado, se agrega proyecto
            % "agregar linea" y luego los proyectos de cambio de estado

            %1) estado base (hacia capa inferior)
            proy_excluyentes = cProyectoExpansion.empty;
                
            % Sólo si aún quedan líneas por agregar
            if lpar + 1 <= nmax
                linea = ElementosBase(id_corr).Elemento(lpar+1);
                proy = crea_proyecto_agrega_linea(linea, 'Base');
                proy.EsUprating = false;
                proy.inserta_etapas_entrada_en_operacion(pParOpt.TiempoEntradaOperacionTradicional);
                
                if ~isempty(EstadosConducentes.Base(1).Proyectos)
                	proy.TieneDependencia = true;
                    proy.inserta_proyectos_dependientes(EstadosConducentes.Base(1).Proyectos);
                end
                
                pAdmProy.agrega_proyecto_tx_primario(proy, id_decision);
                proy_excluyentes(end+1) = proy;
                EstadosConducentesNuevo.Base(1).Proyectos = proy;

                id_estado_final = linea.entrega_id_estado_planificacion();
                MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).ProyectosEntrantes proy];
                MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosSalientes proy];
                MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).IdProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).IdProyectosEntrantes proy.entrega_indice()];
                MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosSalientes proy.entrega_indice()];
                
                proy.inserta_indice_decision_expansion(id_decision);
                proy.inserta_estado_conducente(lpar+1, id_estado_final);
                proy.inserta_estado_inicial(lpar, id_estado_final);
                CapacidadPorEstado(id_decision).Capacidad(lpar+1,id_estado_final) = (lpar+1)*linea.entrega_sr();
                proy.inserta_capacidad_adicional(linea.entrega_sr());
            end

            % cambios de estado
            lineas_a_remover = ElementosBase(id_corr).Elemento(1:lpar);
            id_estado_inicial = lineas_a_remover(1).entrega_id_estado_planificacion();
                
            % reconductoring
            for i = 1:ne_cc
                if largo > 80
                    % no se considera reconductoring para líneas largas
                    continue;
                end
                id_cond = EstadosCC(i);

                n_lineas_cc = length(LineasCC(id_corr).Conductor(id_cond).Linea);
                if lpar <= n_lineas_cc
                    lineas_a_agregar = LineasCC(id_corr).Conductor(id_cond).Linea(1:lpar);

                    proy = crea_proyecto_cambio_estado(lineas_a_remover, lineas_a_agregar, 'CC');
                    proy.EsUprating = true;
                    proy.inserta_etapas_entrada_en_operacion(pParOpt.TiempoEntradaOperacionUprating);

                    if ~isempty(EstadosConducentes.Base(1).Proyectos)
                        proy.TieneDependencia = true;
                        proy.inserta_proyectos_dependientes(EstadosConducentes.Base(1).Proyectos);
                    end

                    pAdmProy.agrega_proyecto_tx_primario(proy, id_decision);
                    proy_excluyentes(end+1) = proy;
                    % se agrega estado conducente en esta misma capa
                    EstadosConducentes.CC(i).Proyectos = [EstadosConducentes.CC(i).Proyectos; proy];

                    id_estado_final = lineas_a_agregar(1).entrega_id_estado_planificacion();
                    MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosEntrantes proy];
                    MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).ProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).ProyectosSalientes proy];
                    MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosEntrantes proy.entrega_indice()];
                    MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).IdProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).ProyectosSalientes proy.entrega_indice()];

                    proy.inserta_indice_decision_expansion(id_decision);
                    proy.inserta_estado_conducente(lpar, id_estado_final);
                    proy.inserta_estado_inicial(lpar, id_estado_inicial);
                    
                    CapacidadPorEstado(id_decision).Capacidad(lpar,id_estado_final) = lpar*lineas_a_agregar(1).entrega_sr();                

                    delta_capacidad = CapacidadPorEstado(id_decision).Capacidad(lpar,id_estado_final) - CapacidadPorEstado(id_decision).Capacidad(lpar,id_estado_inicial);
                    proy.inserta_capacidad_adicional(delta_capacidad);
                                        
                end
            end
                
            % compensacion serie
            for i = 1:ne_cs
            	id_cond = EstadosCS(i,1);
                comp = EstadosCS(i,2);
%                if id_cond ~= conductor_base
%                	% compensación serie sólo para el mismo conductor
%                    continue;
%                end
                lineas_a_agregar = LineasCS(id_corr).Conductor(id_cond).Compensacion(comp).Linea(1:lpar);
                proy = crea_proyecto_cambio_estado(lineas_a_remover, lineas_a_agregar, 'CS');
                proy.EsUprating = true;
                proy.inserta_etapas_entrada_en_operacion(1);
                
                if ~isempty(EstadosConducentes.Base(1).Proyectos)
                	proy.TieneDependencia = true;
                    proy.inserta_proyectos_dependientes(EstadosConducentes.Base(1).Proyectos);
                end
                pAdmProy.agrega_proyecto_tx_primario(proy, id_decision);
                proy_excluyentes(end+1) = proy;
                EstadosConducentes.CS(i).Proyectos = [EstadosConducentes.CS(i).Proyectos; proy];

                id_estado_final = lineas_a_agregar(1).entrega_id_estado_planificacion();
                MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosEntrantes proy];
                MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).ProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).ProyectosSalientes proy];
                MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosEntrantes proy.entrega_indice()];
                MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).IdProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).IdProyectosSalientes proy.entrega_indice()];

                proy.inserta_indice_decision_expansion(id_decision);
                proy.inserta_estado_conducente(lpar, id_estado_final);
                proy.inserta_estado_inicial(lpar, id_estado_inicial);
                
                CapacidadPorEstado(id_decision).Capacidad(lpar,id_estado_final) = lpar*lineas_a_agregar(1).entrega_sr();
                
                delta_capacidad = CapacidadPorEstado(id_decision).Capacidad(lpar,id_estado_final) - CapacidadPorEstado(id_decision).Capacidad(lpar,id_estado_inicial);
                proy.inserta_capacidad_adicional(delta_capacidad);
                
            end
                
            % voltage uprating
            for i = 1:ne_vu
                id_cond = EstadosVU(i,1);
                vur = EstadosVU(i,2);
                n_lineas_vu = length(LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea);
                if lpar <= n_lineas_vu
                    lineas_a_agregar = LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea(1:lpar);
                    proy = crea_proyecto_cambio_estado(lineas_a_remover, lineas_a_agregar, 'AV');
                    proy.EsUprating = true;
                    proy.inserta_etapas_entrada_en_operacion(pParOpt.TiempoEntradaOperacionUprating);
                    
                    if ~isempty(EstadosConducentes.Base(1).Proyectos)
                        proy.TieneDependencia = true;
                        proy.inserta_proyectos_dependientes(EstadosConducentes.Base(1).Proyectos);
                    end
                    % requisitos de conectividad
                    proy.TieneRequisitosConectividad = true;
                    proy_conectividad_se1 = pAdmProy.entrega_proyecto_subestacion(lineas_a_agregar(1).entrega_se1());
                    proy_conectividad_se2 = pAdmProy.entrega_proyecto_subestacion(lineas_a_agregar(1).entrega_se2());
                    proy_conectividad_trafos_se1 = pAdmProy.entrega_proyectos_transformadores(lineas_a_agregar(1).entrega_se1(), 1); %1 es índice paralelo
                    proy_conectividad_trafos_se2 = pAdmProy.entrega_proyectos_transformadores(lineas_a_agregar(1).entrega_se2(),1);
                    proy.inserta_grupo_proyectos_conectividad(proy_conectividad_se1);
                    proy.inserta_grupo_proyectos_conectividad(proy_conectividad_se2);
                    proy.inserta_grupo_proyectos_conectividad(proy_conectividad_trafos_se1);
                    proy.inserta_grupo_proyectos_conectividad(proy_conectividad_trafos_se2);

                    pAdmProy.agrega_proyecto_tx_primario(proy, id_decision);
                    proy_excluyentes(end+1) = proy;
                    EstadosConducentes.VU(i).Proyectos = [EstadosConducentes.VU(i).Proyectos; proy];

                    id_estado_final = lineas_a_agregar(1).entrega_id_estado_planificacion();
                    MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosEntrantes proy];
                    MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).ProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).ProyectosSalientes proy];                    
                    MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosEntrantes proy.entrega_indice()];
                    MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).IdProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).IdProyectosSalientes proy.entrega_indice()];

                    proy.inserta_indice_decision_expansion(id_decision);
                    proy.inserta_estado_conducente(lpar, id_estado_final);
                    proy.inserta_estado_inicial(lpar, id_estado_inicial);
                    
                    CapacidadPorEstado(id_decision).Capacidad(lpar,id_estado_final) = lpar*lineas_a_agregar(1).entrega_sr();
                    
                    delta_capacidad = CapacidadPorEstado(id_decision).Capacidad(lpar,id_estado_final) - CapacidadPorEstado(id_decision).Capacidad(lpar,id_estado_inicial);
                    proy.inserta_capacidad_adicional(delta_capacidad);
                end
            end
            % fin de creación de proyectos a partir de los proyectos
            % base. Se agrega set de proyectos excluyentes
                
            if length(proy_excluyentes) > 1
            	pAdmProy.agrega_proyectos_tx_excluyentes(proy_excluyentes);
            end                
                
            %2) proyectos de reconductoring (i.e. conductor diferente
            %al conductor base)
            % primero se agregan proyectos "agregar línea". Luego se
            % ven los cambios de estado
            for i = 1:ne_cc
            	proy_excluyentes = cProyectoExpansion.empty;
                id_cond_inicial = EstadosCC(i);

                n_lineas_cc = length(LineasCC(id_corr).Conductor(id_cond_inicial).Linea);
                if lpar + 1 <= n_lineas_cc
                	linea = LineasCC(id_corr).Conductor(id_cond_inicial).Linea(lpar+1);
                    proy = crea_proyecto_agrega_linea(linea, 'CC');
                    proy.EsUprating = true;
                    proy.inserta_etapas_entrada_en_operacion(pParOpt.TiempoEntradaOperacionTradicional);
                    
                    if ~isempty(EstadosConducentes.CC(i).Proyectos)
                    	proy.TieneDependencia = true;
                        proy.inserta_proyectos_dependientes(EstadosConducentes.CC(i).Proyectos);
                    end
                
                    pAdmProy.agrega_proyecto_tx_primario(proy, id_decision);
                    proy_excluyentes(end+1) = proy;
                    EstadosConducentesNuevo.CC(i).Proyectos = proy;

                    id_estado_final = linea.entrega_id_estado_planificacion();
                    MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).ProyectosEntrantes proy];
                    MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosSalientes proy];                        
                    MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).IdProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).IdProyectosEntrantes proy.entrega_indice()];
                    MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosSalientes proy.entrega_indice()];

                    proy.inserta_indice_decision_expansion(id_decision);
                    proy.inserta_estado_conducente(lpar+1, id_estado_final);
                    proy.inserta_estado_inicial(lpar, id_estado_final);
                    CapacidadPorEstado(id_decision).Capacidad(lpar+1,id_estado_final) = (lpar+1)*linea.entrega_sr();

                    proy.inserta_capacidad_adicional(linea.entrega_sr());
                end

                %2) cambios de estado reconductoring. 
                if considera_transicion_estados && lpar <= n_lineas_cc
                    lineas_a_remover = LineasCC(id_corr).Conductor(id_cond_inicial).Linea(1:lpar);
                    id_estado_inicial = lineas_a_remover(1).entrega_id_estado_planificacion();

                    % 2.1) otra opción de reconductoring "a la derecha"
                    for j = i + 1:ne_cc
                        if largo > 80
                            %Sólo para líneas cortas
                            continue;
                        end
                        id_cond_final = EstadosCC(j);
                        lineas_a_agregar = LineasCC(id_corr).Conductor(id_cond_final).Linea(1:lpar);
                        proy = crea_proyecto_cambio_estado(lineas_a_remover, lineas_a_agregar, 'CC');
                        proy.EsUprating = true;
                        proy.inserta_etapas_entrada_en_operacion(pParOpt.TiempoEntradaOperacionUprating);
                        
                        if ~isempty(EstadosConducentes.CC(i).Proyectos)
                            proy.TieneDependencia = true;
                            proy.inserta_proyectos_dependientes(EstadosConducentes.CC(i).Proyectos);
                        end

                        pAdmProy.agrega_proyecto_tx_primario(proy, id_decision);
                        proy_excluyentes(end+1) = proy;
                        EstadosConducentes.CC(j).Proyectos = [EstadosConducentes.CC(j).Proyectos; proy];

                        id_estado_final = lineas_a_agregar(1).entrega_id_estado_planificacion();
                        MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosEntrantes proy];
                        MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).ProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).ProyectosSalientes proy];
                        MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosEntrantes proy.entrega_indice()];
                        MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).IdProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).IdProyectosSalientes proy.entrega_indice()];

                        proy.inserta_indice_decision_expansion(id_decision);
                        proy.inserta_estado_conducente(lpar, id_estado_final);
                        proy.inserta_estado_inicial(lpar, id_estado_inicial);

                        delta_capacidad = lpar*(lineas_a_agregar(1).entrega_sr()-lineas_a_remover(1).entrega_sr());
                        proy.inserta_capacidad_adicional(delta_capacidad);
                        
                    end

                    % 2.2) VU (siempre es hacia la derecha
                    % voltage uprating
                    for j = 1:ne_vu
                        id_cond = EstadosVU(j,1);
                        vur = EstadosVU(j,2);
                        n_lineas_vu = length(LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea);
                        if lpar <= n_lineas_vu                
                            lineas_a_agregar = LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea(1:lpar);
                            proy = crea_proyecto_cambio_estado(lineas_a_remover, lineas_a_agregar, 'AV');
                            proy.EsUprating = true;
                            proy.inserta_etapas_entrada_en_operacion(pParOpt.TiempoEntradaOperacionUprating);
                            
                            if ~isempty(EstadosConducentes.CC(i).Proyectos)
                                proy.TieneDependencia = true;
                                proy.inserta_proyectos_dependientes(EstadosConducentes.CC(i).Proyectos);
                            end
                            % requisitos de conectividad
                            proy.TieneRequisitosConectividad = true;
                            proy_conectividad_se1 = pAdmProy.entrega_proyecto_subestacion(lineas_a_agregar(1).entrega_se1());
                            proy_conectividad_se2 = pAdmProy.entrega_proyecto_subestacion(lineas_a_agregar(1).entrega_se2());
                            proy_conectividad_trafos_se1 = pAdmProy.entrega_proyectos_transformadores(lineas_a_agregar(1).entrega_se1(), 1); %1 es índice paralelo
                            proy_conectividad_trafos_se2 = pAdmProy.entrega_proyectos_transformadores(lineas_a_agregar(1).entrega_se2(),1);
                            proy.inserta_grupo_proyectos_conectividad(proy_conectividad_se1);
                            proy.inserta_grupo_proyectos_conectividad(proy_conectividad_se2);
                            proy.inserta_grupo_proyectos_conectividad(proy_conectividad_trafos_se1);
                            proy.inserta_grupo_proyectos_conectividad(proy_conectividad_trafos_se2);

                            pAdmProy.agrega_proyecto_tx_primario(proy, id_decision);
                            proy_excluyentes(end+1) = proy;
                            EstadosConducentes.VU(j).Proyectos = [EstadosConducentes.VU(j).Proyectos; proy];

                            id_estado_final = lineas_a_agregar(1).entrega_id_estado_planificacion();
                            MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosEntrantes proy];
                            MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).ProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).ProyectosSalientes proy];
                            MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosEntrantes proy.entrega_indice()];
                            MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).IdProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).IdProyectosSalientes proy.entrega_indice()];

                            proy.inserta_indice_decision_expansion(id_decision);
                            proy.inserta_estado_conducente(lpar, id_estado_final);
                            proy.inserta_estado_inicial(lpar, id_estado_inicial);

                            delta_capacidad = lpar*(lineas_a_agregar(1).entrega_sr()-lineas_a_remover(1).entrega_sr());
                            proy.inserta_capacidad_adicional(delta_capacidad);
                            
                        end
                    end
                end
                
                % fin de estado de reconductoring actual. Se agregan
                % proyectos excluyentes
                if length(proy_excluyentes) > 1
                	pAdmProy.agrega_proyectos_tx_excluyentes(proy_excluyentes);
                end
            end
                    
            %3) proyectos de compensación serie
            for i = 1:ne_cs
            	proy_excluyentes = cProyectoExpansion.empty;
                id_cond_inicial = EstadosCS(i,1);
                comp_inicial = EstadosCS(i,2);
                % proyectos nuevos (capa inferior)
                if lpar + 1 <= nmax
                	linea = LineasCS(id_corr).Conductor(id_cond_inicial).Compensacion(comp_inicial).Linea(lpar+1);
                    proy = crea_proyecto_agrega_linea(linea, 'CS');
                    proy.EsUprating = true;
                    proy.inserta_etapas_entrada_en_operacion(pParOpt.TiempoEntradaOperacionTradicional);
                    
                    if ~isempty(EstadosConducentes.CS(i).Proyectos)
                    	proy.TieneDependencia = true;
                        proy.inserta_proyectos_dependientes(EstadosConducentes.CS(i).Proyectos);
                    end

                    pAdmProy.agrega_proyecto_tx_primario(proy, id_decision);
                    proy_excluyentes(end+1) = proy;
                    EstadosConducentesNuevo.CS(i).Proyectos = proy;

                    id_estado_final = linea.entrega_id_estado_planificacion();
                    MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).ProyectosEntrantes proy];
                    MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosSalientes proy];
                    MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).IdProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).IdProyectosEntrantes proy.entrega_indice()];
                    MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosSalientes proy.entrega_indice()];

                    proy.inserta_indice_decision_expansion(id_decision);
                    proy.inserta_estado_conducente(lpar+1, id_estado_final);
                    proy.inserta_estado_inicial(lpar, id_estado_final);
                    
                    CapacidadPorEstado(id_decision).Capacidad(lpar+1,id_estado_final) = (lpar+1)*linea.entrega_sr();

                    proy.inserta_capacidad_adicional(linea.entrega_sr());
                    
                end

                if considera_transicion_estados
                
                    % proyectos de cambio de estado de línea compensada. Se
                    % considera agregar nueva compensación en serie para un mismo
                    % conductor o VU
                    lineas_a_remover =  LineasCS(id_corr).Conductor(id_cond_inicial).Compensacion(comp_inicial).Linea(1:lpar);
                    id_estado_inicial = lineas_a_remover(1).entrega_id_estado_planificacion();

                    % 3.1) compensación "hacia la derecha"
                    for j = i+1:ne_cs
                        id_cond_final = EstadosCS(j,1);
                        comp_final = EstadosCS(j,2);

                        if id_cond_final ~= id_cond_inicial
                            % se agrega más compensación sólo para el mismo
                            % tipo de conductor
                            continue;
                        end
                        lineas_a_agregar = LineasCS(id_corr).Conductor(id_cond_inicial).Compensacion(comp_final).Linea(1:lpar);
                        proy = crea_proyecto_cambio_estado(lineas_a_remover, lineas_a_agregar, 'CS');
                        proy.EsUprating = true;
                        proy.inserta_etapas_entrada_en_operacion(1);
                        
                        if ~isempty(EstadosConducentes.CS(i).Proyectos)
                            proy.TieneDependencia = true;
                            proy.inserta_proyectos_dependientes(EstadosConducentes.CS(i).Proyectos);
                        end
                        pAdmProy.agrega_proyecto_tx_primario(proy, id_decision);
                        proy_excluyentes(end+1) = proy;
                        EstadosConducentes.CS(j).Proyectos = [EstadosConducentes.CS(j).Proyectos; proy];

                        id_estado_final = lineas_a_agregar(1).entrega_id_estado_planificacion();
                        MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosEntrantes proy];
                        MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).ProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).ProyectosSalientes proy];
                        MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosEntrantes proy.entrega_indice()];
                        MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).IdProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).IdProyectosSalientes proy.entrega_indice()];

                        proy.inserta_indice_decision_expansion(id_decision);
                        proy.inserta_estado_conducente(lpar, id_estado_final);
                        proy.inserta_estado_inicial(lpar, id_estado_inicial);

                        delta_capacidad = lpar*(lineas_a_agregar(1).entrega_sr()-lineas_a_remover(1).entrega_sr());
                        proy.inserta_capacidad_adicional(delta_capacidad);
                        
                    end
                
                    % 3.2) VU (siempre es hacia la derecha)
                    for j = 1:ne_vu
                        id_cond = EstadosVU(j,1);
                        vur = EstadosVU(j,2);
                        n_lineas_vu = length(LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea);
                        if lpar <= n_lineas_vu

                            lineas_a_agregar = LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea(1:lpar);
                            proy = crea_proyecto_cambio_estado(lineas_a_remover, lineas_a_agregar, 'AV');
                            proy.EsUprating = true;
                            proy.inserta_etapas_entrada_en_operacion(pParOpt.TiempoEntradaOperacionUprating);
                            
                            if ~isempty(EstadosConducentes.CS(i).Proyectos)
                                proy.TieneDependencia = true;
                                proy.inserta_proyectos_dependientes(EstadosConducentes.CS(i).Proyectos);
                            end
                            % requisitos de conectividad
                            proy.TieneRequisitosConectividad = true;
                            proy_conectividad_se1 = pAdmProy.entrega_proyecto_subestacion(lineas_a_agregar(1).entrega_se1());
                            proy_conectividad_se2 = pAdmProy.entrega_proyecto_subestacion(lineas_a_agregar(1).entrega_se2());
                            proy_conectividad_trafos_se1 = pAdmProy.entrega_proyectos_transformadores(lineas_a_agregar(1).entrega_se1(), 1); %1 es índice paralelo
                            proy_conectividad_trafos_se2 = pAdmProy.entrega_proyectos_transformadores(lineas_a_agregar(1).entrega_se2(),1);
                            proy.inserta_grupo_proyectos_conectividad(proy_conectividad_se1);
                            proy.inserta_grupo_proyectos_conectividad(proy_conectividad_se2);
                            proy.inserta_grupo_proyectos_conectividad(proy_conectividad_trafos_se1);
                            proy.inserta_grupo_proyectos_conectividad(proy_conectividad_trafos_se2);

                            pAdmProy.agrega_proyecto_tx_primario(proy, id_decision);
                            proy_excluyentes(end+1) = proy;
                            EstadosConducentes.VU(j).Proyectos = [EstadosConducentes.VU(j).Proyectos; proy];

                            id_estado_final = lineas_a_agregar(1).entrega_id_estado_planificacion();
                            MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosEntrantes proy];
                            MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).ProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).ProyectosSalientes proy];
                            MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosEntrantes proy.entrega_indice()];
                            MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).IdProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_inicial).IdProyectosSalientes proy.entrega_indice()];

                            proy.inserta_indice_decision_expansion(id_decision);
                            proy.inserta_estado_conducente(lpar, id_estado_final);
                            proy.inserta_estado_inicial(lpar, id_estado_inicial);

                            delta_capacidad = lpar*(lineas_a_agregar(1).entrega_sr()-lineas_a_remover(1).entrega_sr());
                            proy.inserta_capacidad_adicional(delta_capacidad);
                            
                        end
                    end
                end
                
                % fin de cambio de estado para CS actual. Se agregan
                % proyectos excluyentes
                if length(proy_excluyentes) > 1
                	pAdmProy.agrega_proyectos_tx_excluyentes(proy_excluyentes);
                end
            end
                
            % 4) proyectos de voltage uprating
            % en este caso hay sólo proyectos de agregar líneas
            % no hay proyectos excluyentes y tampoco tiene requisitos
            % de conectividad, ya que este tema se vio en voltage
            % uprating o durante la creación de una nueva línea con
            % voltaje superior
            if lpar + 1 <= nmax
                for i = 1:ne_vu
                	id_cond = EstadosVU(i,1);
                    vur = EstadosVU(i,2);
                    n_lineas_vu = length(LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea);
                    if lpar + 1 <= n_lineas_vu
                        linea = LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea(lpar+1);
                        proy = crea_proyecto_agrega_linea(linea, 'AV');
                        proy.EsUprating = true;
                        proy.inserta_etapas_entrada_en_operacion(pParOpt.TiempoEntradaOperacionTradicional);
                        
                        if ~isempty(EstadosConducentes.VU(i).Proyectos)
                            proy.TieneDependencia = true;
                            proy.inserta_proyectos_dependientes(EstadosConducentes.VU(i).Proyectos);
                        end
                        pAdmProy.agrega_proyecto_tx_primario(proy, id_decision);
                        EstadosConducentesNuevo.VU(i).Proyectos = proy;

                        id_estado_final = linea.entrega_id_estado_planificacion();
                        MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).ProyectosEntrantes proy];
                        MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).ProyectosSalientes proy];
                        MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).IdProyectosEntrantes = [MatrizEstados(id_decision).Estado(lpar+1,id_estado_final).IdProyectosEntrantes proy.entrega_indice()];
                        MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosSalientes = [MatrizEstados(id_decision).Estado(lpar,id_estado_final).IdProyectosSalientes proy.entrega_indice()];

                        proy.inserta_indice_decision_expansion(id_decision);
                        proy.inserta_estado_conducente(lpar+1, id_estado_final);
                        proy.inserta_estado_inicial(lpar, id_estado_final);
                        
                        CapacidadPorEstado(id_decision).Capacidad(lpar+1,id_estado_final) = (lpar+1)*linea.entrega_sr();

                        proy.inserta_capacidad_adicional(linea.entrega_sr());

                    end
                end
            end
        end
    end
    estados_primarios.MatrizEstados = MatrizEstados;
    estados_primarios.CapacidadPorEstado = CapacidadPorEstado;
    estados_primarios.EstadosIniciales = EstadosIniciales;
    estados_primarios.TipoEstado = TipoEstado;
end

function estados_primarios = genera_proyectos_expansion_transformadores(id_corr, estados_primarios, ElementosBase, pAdmProy)
    % MatrizEstadosCorredores(idCorredor).Estado(parindex, no_estado).ProyectosSalientes = [Pr1; Pr2; ...]
    MatrizEstados = estados_primarios.MatrizEstados;
    CapacidadPorEstado = estados_primarios.CapacidadPorEstado;
    EstadosIniciales = estados_primarios.EstadosIniciales;
    TipoEstado = estados_primarios.TipoEstado;

    trafos_existentes = ElementosBase(id_corr).NExistente;
    nmax = ElementosBase(id_corr).Nmax;
    tipo_trafo_base = ElementosBase(id_corr).TipoTrafoBase;

    if nmax <= trafos_existentes
        return
    end
    
    id_decision = length(MatrizEstados) + 1;
    MatrizEstados(id_decision).Largo = 0;
    TipoEstado(id_decision) = 1;
    id_estado = 1;
    %EstadosBase = tipo_trafo_base;
    existe_corredor = false;
    for i = 1:nmax
        ElementosBase(id_corr).Elemento(i).inserta_id_estado_planificacion(id_estado);
        tipo_trafo_base = ElementosBase(id_corr).Elemento(i).entrega_tipo_trafo();
        MatrizEstados(id_decision).Estado(i,id_estado).ProyectosEntrantes = [];
        MatrizEstados(id_decision).Estado(i,id_estado).ProyectosSalientes = [];
        MatrizEstados(id_decision).Estado(i,id_estado).IdProyectosEntrantes = [];
        MatrizEstados(id_decision).Estado(i,id_estado).IdProyectosSalientes = [];
        MatrizEstados(id_decision).Estado(i,id_estado).Nombre{1,1} = ['T' num2str(i)];
        MatrizEstados(id_decision).Estado(i,id_estado).Nombre{1,2} = ['Tipo_' num2str(tipo_trafo_base)]; 
    end
    
    CapacidadPorEstado(id_decision).Capacidad = zeros(nmax, 1); % sólo 1 tipo de trafo
        
    if trafos_existentes > 1
        for j = 1:trafos_existentes
            sr = ElementosBase(id_corr).Elemento(j).entrega_sr();
            CapacidadPorEstado(id_decision).Capacidad(j,1) = sr;
        end
        EstadosIniciales(id_decision,:) = [trafos_existentes, 1];
    else
        EstadosIniciales(id_decision,:) = [0, 1];        
    end
    
    for tpar = trafos_existentes:nmax
        if tpar > trafos_existentes
        	% ya hay estados conducentes
            EstadosConducentes = EstadosConducentesNuevo;
        else
        	% aún no se han definido los estados conducentes
            EstadosConducentes.Base(1).Proyectos = cProyectoExpansion.empty;
        end
            
        % se borran los estados conducentes nuevos
        EstadosConducentesNuevo.Base(1).Proyectos = cProyectoExpansion.empty;

        if tpar == 0
        	% conducente a los estados lpar = 1
            % no hay trafos. Se agregan todos los proyectos. Cada
            % proyecto generado crea grupo de proyectos excluyentes                
            proy_excluyentes = cProyectoExpansion.empty;
                
            %proyecto base
            trafo = ElementosBase(id_corr).Elemento(tpar+1);
            proy = crea_proyecto_agrega_transformador(trafo, 'Base');
            proy.EsUprating = false;
            proy.inserta_etapas_entrada_en_operacion(1);
            
            pAdmProy.agrega_proyecto_tx_primario(proy, id_decision);
            proy_excluyentes(end+1) = proy;
            EstadosConducentesNuevo.Base(1).Proyectos = proy;
            % MatrizEstadosCorredores(idCorredor).Estado(parindex, no_estado).ProyectosSalientes = [Pr1; Pr2; ...]
            id_estado_inicial = trafo.entrega_id_estado_planificacion();
            MatrizEstados(id_decision).Estado(tpar+1,id_estado_inicial).ProyectosEntrantes = proy;
            MatrizEstados(id_decision).Estado(tpar+1,id_estado_inicial).IdProyectosEntrantes = proy.entrega_indice();

            sr = trafo.entrega_sr();
            
            CapacidadPorEstado(id_decision).Capacidad(1,1) = sr;
            proy.inserta_capacidad_adicional(sr);
            
            if length(proy_excluyentes) > 1
            	pAdmProy.agrega_proyectos_tx_excluyentes(proy_excluyentes);
            end
        else
            % ya existen trafos. Por cada estado, se agrega proyecto
            % "agregar trafo". No hay cambios de estado

            proy_excluyentes = cProyectoExpansion.empty;
                
            % Sólo si aún quedan líneas por agregar
            if tpar + 1 <= nmax
            	trafo = ElementosBase(id_corr).Elemento(tpar+1);
                proy = crea_proyecto_agrega_transformador(trafo, 'Base');
                proy.EsUprating = false;
                proy.inserta_etapas_entrada_en_operacion(1);
                
                if ~isempty(EstadosConducentes.Base(1).Proyectos)
                	proy.TieneDependencia = true;
                    proy.inserta_proyectos_dependientes(EstadosConducentes.Base(1).Proyectos);
                end
                
                pAdmProy.agrega_proyecto_tx_primario(proy, id_decision);
                proy_excluyentes(end+1) = proy;
                EstadosConducentesNuevo.Base(1).Proyectos = proy;

                id_estado_final = trafo.entrega_id_estado_planificacion();
                MatrizEstados(id_decision).Estado(tpar+1,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_decision).Estado(tpar+1,id_estado_final).ProyectosEntrantes proy];
                MatrizEstados(id_decision).Estado(tpar,id_estado_final).ProyectosSalientes = [MatrizEstados(id_decision).Estado(tpar,id_estado_final).ProyectosSalientes proy];
                MatrizEstados(id_decision).Estado(tpar+1,id_estado_final).IdProyectosEntrantes = [MatrizEstados(id_decision).Estado(tpar+1,id_estado_final).IdProyectosEntrantes proy.entrega_indice()];
                MatrizEstados(id_decision).Estado(tpar,id_estado_final).IdProyectosSalientes = [MatrizEstados(id_corid_decision).Estado(tpar,id_estado_final).IdProyectosSalientes proy.entrega_indice()];

                sr = trafo.entrega_sr();
                CapacidadPorEstado(id_decision).Capacidad(tpar+1,1) = (tpar+1)*sr;
                proy.inserta_capacidad_adicional(sr);

            end

            % fin de creación de proyectos a partir de los proyectos
            % base. Se agrega set de proyectos excluyentes
                
            if length(proy_excluyentes) > 1
            	pAdmProy.agrega_proyectos_tx_excluyentes(proy_excluyentes);
            end
        end
    end
    estados_primarios.MatrizEstados = MatrizEstados;
    estados_primarios.CapacidadPorEstado = CapacidadPorEstado;
    estados_primarios.EstadosIniciales = EstadosIniciales;
    estados_primarios.TipoEstado = TipoEstado;    
end

function linea = crea_linea(Conductor,Corredor, Costos, se1, se2, lpar, id_corr)
    id_cond = Conductor(1);
    r_ohm_km = Conductor(3);
	x_ohm_km = Conductor(4);
	g_mS_km = Conductor(5);
	c_uF_km = Conductor(6);
	imax = Conductor(7);
    costo_fijo_conductor = Conductor(8);
	costo_conductor_mva_km = Conductor(9);
	costo_torre_mva_km = Conductor(10);
    row_ha_km = Conductor(13);
    diametro = Conductor(14);
    costo_servidumbre_ha = Costos(1,1);
	vida_util = Conductor(11);
	largo = Corredor(3);    
	linea = cLinea();
    vn = se1.entrega_vn();
    nombre = strcat('L', num2str(lpar), '_C', num2str(id_cond), '_SE', num2str(Corredor(1)), '_', num2str(Corredor(2)), '_V', num2str(vn));
    linea.inserta_nombre(nombre);
    linea.inserta_subestacion(se1, 1);
    linea.inserta_subestacion(se2,2);
    linea.inserta_id_corredor(id_corr);
    linea.inserta_xpul(x_ohm_km);
    linea.inserta_rpul(r_ohm_km);
    linea.inserta_cpul(c_uF_km);
    linea.inserta_gpul(g_mS_km);
    linea.inserta_largo(largo);
    vn = se1.entrega_vn();
    sth = sqrt(3)*vn*imax;
    linea.inserta_sth(sth);
	if c_uF_km == 0
    	% hay que modificar este valor para calcular el SIL
        % para ello, se determina c de tal forma que el límite
        % térmico sea 3*SIL si la línea tuviera 50 millas de
        % largo
        SIL = sth/3;
        Zc = vn^2/SIL;
        bpul = x_ohm_km/Zc^2;
        c_uF_km = bpul/(2 *pi *50)*1000000;
        linea.inserta_cpul(c_uF_km);
	end
    Zc = sqrt(x_ohm_km/(2*pi*50*c_uF_km)*1000000);
    SIL = vn^2/Zc;
    factor_capacidad = entrega_cargabilidad_linea(largo);
    factor_capacidad = min(3.465, factor_capacidad);
    sr = round(factor_capacidad*SIL,0);
    sr = min(sth, sr);
    linea.inserta_sr(sr);
    linea.inserta_en_servicio(1);
    costo_conductor = costo_fijo_conductor + costo_conductor_mva_km*sth*largo;
    linea.inserta_costo_conductor(costo_conductor);
    costo_torre = costo_torre_mva_km*sth*largo;
    linea.inserta_costo_torre(costo_torre);
    costo_servidumbre = costo_servidumbre_ha*row_ha_km*largo/1000000;
    linea.inserta_costo_servidumbre(costo_servidumbre);
    linea.inserta_row(row_ha_km*largo);
    linea.inserta_tipo_conductor(id_cond);
    linea.inserta_diametro_conductor(diametro);
    linea.inserta_vida_util(vida_util);
    linea.inserta_indice_paralelo(lpar);
end

function linea = crea_linea_htls(Conductor,Corredor, Costos, se1, se2, lpar, id_corr)
    linea = crea_linea(Conductor,Corredor, Costos, se1, se2, lpar, id_corr);
    % se actualizan los costos del conductor
    largo = linea.largo();
    if largo < 5
        factor = 1.5;
    elseif largo < 15
        factor = 1.2;
    else
        factor = 1;
    end
    sth = linea.entrega_sth();
    linea.inserta_sr(sth);
    costo_conductor = factor*linea.entrega_costo_conductor();
    costo_torre = factor*linea.entrega_costo_torre();
    costo_servidumbre = factor*linea.entrega_costo_servidumbre();
    linea.inserta_costo_conductor(costo_conductor);
    linea.inserta_costo_torre(costo_torre);
    linea.inserta_costo_servidumbre(costo_servidumbre);
end

function linea = crea_linea_voltage_uprating(Conductor,Corredor, Costos, se1, se2, lpar, id_corr)
    linea = crea_linea(Conductor,Corredor, Costos, se1, se2, lpar, id_corr);
    % se actualizan los costos del conductor
    largo = linea.largo();
    if largo < 5
        factor = 1.5;
    elseif largo < 15
        factor = 1.2;
    else
        factor = 1;
    end
    costo_conductor = factor*linea.entrega_costo_conductor();
    costo_torre = factor*linea.entrega_costo_torre();
    costo_servidumbre = factor*linea.entrega_costo_servidumbre();
    linea.inserta_costo_conductor(costo_conductor);
    linea.inserta_costo_torre(costo_torre);
    linea.inserta_costo_servidumbre(costo_servidumbre);
end

function linea = crea_linea_voltage_uprating_mismo_conductor(linea_base, se1_vur, se2_vur)
	linea = linea_base.crea_copia();
	largo = linea.largo();
    id_cond = linea.entrega_tipo_conductor();

	sth_orig = linea.entrega_sth();
    vn_orig = linea.entrega_se1().entrega_vn();
    ubicacion_1 = linea.entrega_se1().entrega_ubicacion();
    ubicacion_2 = linea.entrega_se2().entrega_ubicacion();
    linea.inserta_subestacion(se1_vur,1);
    linea.inserta_subestacion(se2_vur,2);
	vn_nuevo = linea.entrega_se1().entrega_vn();
    sth_nuevo = sth_orig/vn_orig*vn_nuevo;
    x_ohm_km = linea.entrega_reactancia_pul();
    c_uF_km = linea.entrega_cpul();
    Zc = sqrt(x_ohm_km/(2*pi*50*c_uF_km)*1000000);
    SIL = vn_nuevo^2/Zc;
    factor_capacidad = entrega_cargabilidad_linea(largo);
    factor_capacidad = min(3, factor_capacidad);
    sr_nuevo = factor_capacidad*SIL;
    sr_nuevo = min(sth_nuevo, sr_nuevo);
    linea.inserta_sr(sr_nuevo);
    linea.inserta_sth(sth_nuevo);

    lpar = linea.entrega_indice_paralelo();
    
    nombre = strcat('L', num2str(lpar), '_C', num2str(id_cond), '_SE', num2str(ubicacion_1), '_', num2str(ubicacion_2), '_V', num2str(se1_vur.entrega_vn()));
    linea.inserta_nombre(nombre);
    linea.inserta_anio_construccion(0);
end

function se_vur = crea_nueva_subestacion(se_base, voltaje, costo, pAdmProy)
	ubicacion = se_base.entrega_ubicacion();
	[posx, posy] = se_base.entrega_posicion();
    id_nombre = se_base.entrega_id();
    id_se = cantidad_se_existentes + pAdmProy.entrega_cantidad_subestaciones()+1;
    se_vur = cSubestacion();
    se_vur.inserta_nombre(strcat('SE_',num2str(id_nombre), '_VU_', num2str(voltaje)));
    se_vur.inserta_vn(voltaje);
    se_vur.inserta_posicion(posx, posy);
    se_vur.inserta_id(id_se);
    se_vur.inserta_ubicacion(ubicacion);
    se_vur.inserta_costo(costo);
    se_vur.Existente = false;
end

function proy = crea_proyecto_agrega_bateria(bateria)
    proy = cProyectoExpansion();
    proy.inserta_tipo_proyecto('AB'); %agregar bateria
	proy.Elemento = [proy.Elemento; bateria];
	proy.Accion = [proy.Accion ;'A'];
    costo_inversion = bateria.entrega_costo_inversion();
    proy.inserta_costo_inversion(costo_inversion);
	id_bat = bateria.entrega_id_tecnologia();
    id_par = bateria.entrega_indice_paralelo();

    if id_par == 1
        proy.inserta_capacidad_inicial('SC');
    else
        proy.inserta_capacidad_inicial(['C' num2str(id_par-1)]);
    end
    proy.inserta_capacidad_final(['C' num2str(id_bat)]);
    nombre = ['Agrega bateria S' num2str(id_par) ' tipo T' num2str(id_bat) ' en ' ...
                    bateria.entrega_se().entrega_nombre()]; 
    proy.inserta_nombre(nombre);
end

function proy = crea_proyecto_agrega_linea(linea, tipo_proyecto)
    proy = cProyectoExpansion();
    proy.inserta_tipo_proyecto('AL'); %agregar línea
	proy.Elemento = [proy.Elemento; linea];
	proy.Accion = [proy.Accion ;'A'];
    costo_inversion = linea.entrega_costo_conductor()+linea.entrega_costo_torre()+linea.entrega_costo_servidumbre();
    proy.inserta_costo_inversion(costo_inversion);
    
	id_cond = linea.entrega_tipo_conductor();
    id_par = linea.entrega_indice_paralelo();
    if strcmp(tipo_proyecto,'Base')
        if id_par == 1
            proy.inserta_capacidad_inicial('SC');
        else
            proy.inserta_capacidad_inicial(['LP_' num2str(id_par-1)]);
        end
        proy.inserta_capacidad_final(['C' num2str(id_cond)]);
        nombre = ['Agrega linea L' num2str(id_par) ' con conductor base C' num2str(id_cond) ' entre ' ...
                        linea.entrega_se1().entrega_nombre() ' y ' linea.entrega_se2().entrega_nombre()]; 
        proy.inserta_nombre(nombre);
    elseif strcmp(tipo_proyecto,'CC')
        if id_par == 1
            proy.inserta_capacidad_inicial('SC');
        else
            proy.inserta_capacidad_inicial(['LP_' num2str(id_par-1)]);
        end
        proy.inserta_capacidad_final(['C' num2str(id_cond)]);
        nombre = ['Agrega linea cc L' num2str(linea.entrega_indice_paralelo()) ' con conductor C' num2str(id_cond) ' entre ' ...
                linea.entrega_se1().entrega_nombre() ' y ' linea.entrega_se2().entrega_nombre()]; 
        proy.inserta_nombre(nombre);
    elseif strcmp(tipo_proyecto,'CS')
        porcentaje_comp = linea.entrega_compensacion_serie();
        if id_par == 1
            proy.inserta_capacidad_inicial('SC');
        else
            proy.inserta_capacidad_inicial(['LP_' num2str(id_par-1)]);
        end
        proy.inserta_capacidad_final(['C' num2str(id_cond) '_CS_' num2str(porcentaje_comp*100)]);
        nombre = ['Agrega linea compensada L' num2str(linea.entrega_indice_paralelo()) ' con conductor C' num2str(id_cond) ...
                        ' compensacion ' num2str(porcentaje_comp*100) ' entre ' linea.entrega_se1().entrega_nombre() ' y ' linea.entrega_se2().entrega_nombre()]; 
        proy.inserta_nombre(nombre);
    elseif strcmp(tipo_proyecto, 'AV')
        if id_par == 1
            proy.inserta_capacidad_inicial('SC');
        else
            proy.inserta_capacidad_inicial(['LP_' num2str(id_par-1)]);
        end
        vfinal = linea.entrega_se1().entrega_vn();
        proy.inserta_capacidad_final(['C' num2str(id_cond) '_VU_' num2str(vfinal)]);
        nombre = ['Agrega linea vu L' num2str(linea.entrega_indice_paralelo()) ' con conductor C' num2str(id_cond) ...
                        ' voltaje ' num2str(vfinal) ' entre ' linea.entrega_se1().entrega_nombre() ' y ' linea.entrega_se2().entrega_nombre()]; 
        proy.inserta_nombre(nombre);
    else
        error = MException('cimporta_problema_optimizacion_tnep:crea_proyecto_agrega_linea','caso no existe');
        throw(error)
    end
end

function proy = crea_proyecto_agrega_transformador(trafo, tipo_proyecto)
    proy = cProyectoExpansion();
    proy.inserta_tipo_proyecto('AT'); %agregar transformador
    
	proy.Elemento = [proy.Elemento; trafo];
	proy.Accion = [proy.Accion ;'A'];
	id_tipo = trafo.entrega_tipo_trafo(); 
    id_par = trafo.entrega_indice_paralelo();
    sr = trafo.entrega_sr();
    costo_transformador = trafo.entrega_costo_transformador();
    proy.inserta_costo_inversion(costo_transformador);
    ubicacion = trafo.entrega_ubicacion();
    v1 = trafo.entrega_se1().entrega_vn();
    v2 = trafo.entrega_se2().entrega_vn();
    if strcmp(tipo_proyecto,'Base')
        if id_par == 1
            proy.inserta_capacidad_inicial('SC');
        else
            proy.inserta_capacidad_inicial(['TP_' num2str(id_par-1)]);
        end
        proy.inserta_capacidad_final(['T' num2str(id_tipo)]);
        nombre = ['Agrega trafo T' num2str(id_par) ' con capacidad Sr ' num2str(sr) ' en bus B' num2str(ubicacion) ...
                   ' con voltajes ' num2str(v1) ' y ' num2str(v2) ' kV']; 
        proy.inserta_nombre(nombre);
    elseif strcmp(tipo_proyecto, 'AV')
        if id_par == 1
            proy.inserta_capacidad_inicial('SC');
        else
            proy.inserta_capacidad_inicial(['TP_' num2str(id_par-1)]);
        end
        proy.inserta_capacidad_final(['TP_' num2str(id_par)]);
        nombre = ['Agrega trafo vu T' num2str(id_par) ' con capacidad Sr ' num2str(sr) ' en bus B' num2str(ubicacion) ...
                   ' con voltajes ' num2str(v1) ' y ' num2str(v2) ' kV']; 
        proy.inserta_nombre(nombre);
    else
        error = MException('cimporta_problema_optimizacion_tnep:crea_proyecto_agrega_linea','caso no existe');
        throw(error)
    end
end

function proy = crea_proyecto_agrega_subestacion(se)
    proy = cProyectoExpansion();
    proy.inserta_tipo_proyecto('AS'); %agregar transformador
	proy.Elemento = [proy.Elemento; se];
	proy.Accion = [proy.Accion ;'A'];
    ubicacion = se.entrega_ubicacion();
    vn = se.entrega_vn();
	nombre = ['Agrega bus en ' num2str(ubicacion) ' con voltaje ' num2str(vn)]; 
    proy.inserta_nombre(nombre);
    costo = se.entrega_costo();
    proy.inserta_costo_inversion(costo);
end

function proy = crea_proyecto_cambio_estado(lineas_a_remover, lineas_a_agregar, tipo_proyecto)
    proy = cProyectoExpansion();
    proy.inserta_tipo_proyecto(tipo_proyecto);
   
    id_cond_inicial = lineas_a_remover(1).entrega_tipo_conductor();
    id_cond_final = lineas_a_agregar(1).entrega_tipo_conductor();
    compensacion_inicial = lineas_a_remover(1).entrega_compensacion_serie()*100;
    compensacion_final = lineas_a_agregar(1).entrega_compensacion_serie()*100;
    vinicial = lineas_a_remover(1).entrega_se1().entrega_vn();
    vfinal = lineas_a_agregar(1).entrega_se1().entrega_vn();
    for i = 1:length(lineas_a_remover)
        linea = lineas_a_remover(i);
        proy.Elemento = [proy.Elemento; linea];
        proy.Accion = [proy.Accion ;'R'];
    end
	for i = 1:length(lineas_a_agregar)
        linea = lineas_a_agregar(i);
        proy.Elemento = [proy.Elemento; linea];
        proy.Accion = [proy.Accion ;'A'];
	end

    costo_inv = 0;
    if strcmp(tipo_proyecto,'CC')
        proy.inserta_capacidad_inicial(['C' num2str(id_cond_inicial)]);
        proy.inserta_capacidad_final(['C' num2str(id_cond_final)]);
        nombre = ['Cambio conductor lineas L1 a ' num2str(length(lineas_a_remover)) ' de C' num2str(id_cond_inicial) ' a C' num2str(id_cond_final) ...
            ' entre ' lineas_a_remover(1).entrega_se1().entrega_nombre() ' y ' lineas_a_remover(1).entrega_se2().entrega_nombre()]; 
        proy.inserta_nombre(nombre);
        % costos asociados. Se separan casos con upgrade en la torre o no
        diametro_conductor_inicial = lineas_a_remover(1).entrega_diametro_conductor();
        diametro_conductor_final = lineas_a_agregar(1).entrega_diametro_conductor();
        for ii = 1:length(lineas_a_agregar)
        	costo_inv = costo_inv + lineas_a_agregar(ii).entrega_costo_conductor();
            if diametro_conductor_final > diametro_conductor_inicial
                % hay que hacer upgrade a las torres.
                % falta por hacer TODO RAMRAM!!!!
            end
        end
        proy.inserta_costo_inversion(costo_inv);
    elseif strcmp(tipo_proyecto,'CS')
        proy.inserta_capacidad_inicial(['CS_' num2str(compensacion_inicial)]);
        proy.inserta_capacidad_final(['CS_' num2str(compensacion_final)]);
        nombre = ['Compensacion serie lineas L1 a ' num2str(length(lineas_a_remover)) ' de CS_' num2str(compensacion_inicial) ' a CS_' num2str(compensacion_final) ...
            ' entre ' lineas_a_remover(1).entrega_se1().entrega_nombre() ' y ' lineas_a_remover(1).entrega_se2().entrega_nombre()]; 
        proy.inserta_nombre(nombre);
        %para costos se considera la diferencia de la compensación antigua
        %y la nueva
        for ii = 1:length(lineas_a_agregar)
        	costo_inv = costo_inv + lineas_a_agregar(ii).entrega_costo_compensacion_serie();
            costo_inv = costo_inv - lineas_a_remover(ii).entrega_costo_compensacion_serie();
        end
        proy.inserta_costo_inversion(costo_inv);
    elseif strcmp(tipo_proyecto,'AV') 
        proy.inserta_capacidad_inicial(['V_' num2str(vinicial)]);
        proy.inserta_capacidad_final(['V_' num2str(vfinal)]);
        nombre = ['Aumento voltaje lineas L1 a ' num2str(length(lineas_a_remover)) ' de V_' num2str(vinicial) ' a V_' num2str(vfinal) ...
            ' entre buses originales ' lineas_a_remover(1).entrega_se1().entrega_nombre() ' y ' lineas_a_remover(1).entrega_se2().entrega_nombre()]; 
        proy.inserta_nombre(nombre);
        
        tipo_cond_inicial = lineas_a_remover(1).entrega_tipo_conductor();
        tipo_cond_final = lineas_a_agregar(1).entrega_tipo_conductor();
        if tipo_cond_inicial == tipo_cond_final
            % VU se realiza sin cambio de conductor. Costo corresponde a
            % 20% de costo línea nueva
            costo_linea_nueva = lineas_a_remover(1).entrega_costo_conductor()+lineas_a_remover(1).entrega_costo_torre()+lineas_a_remover(1).entrega_costo_servidumbre();
            proy.inserta_cambio_conductor_aumento_voltaje(false);
            cantidad_lineas = length(lineas_a_remover);
            proy.inserta_costo_inversion(0.2*costo_linea_nueva*cantidad_lineas);
        else
            % VU se reliza cambiando de conductor. Se consideran los costos
            % totales
            
            proy.inserta_cambio_conductor_aumento_voltaje(true);
            for ii = 1:length(lineas_a_agregar)
                % si VU se realiza con el mismo conductor, entonces los costos
                % son cero
                servidumbre_linea_remover = lineas_a_remover(ii).entrega_costo_servidumbre();
                servidumbre_linea_agregar = lineas_a_agregar(ii).entrega_costo_servidumbre();
                delta_servidumbre = servidumbre_linea_agregar - servidumbre_linea_remover;
                costo_linea = lineas_a_agregar(ii).entrega_costo_conductor()+lineas_a_remover(ii).entrega_costo_torre() + delta_servidumbre;
                costo_inv = costo_inv + costo_linea;
                proy.inserta_costo_inversion(costo_inv);
            end
        end
    else
        error = MException('cimporta_problema_optimizacion_tnep:crea_proyecto_cambio_estado','caso no existe');
        throw(error)
    end        
end

function trafo = crea_transformador(TipoTrafo, se_at, se_bt, lpar, varargin)
    % varargin indica la capacidad del trafo, en caso de que esta se
    % modifique (porque es un trafo para VU)
    if nargin > 4
        capacidad_trafo = varargin{1};
    else
        capacidad_trafo = 0;
    end
    
	vat = se_at.entrega_vn();
    vbt = se_bt.entrega_vn();
    if capacidad_trafo == 0
        sr = TipoTrafo(2);
    else
        sr = capacidad_trafo;
    end
    tipo_trafo = TipoTrafo(1);
    x_ohm = TipoTrafo(5);
	uk = x_ohm*sr/vat^2;
    costo_fijo = TipoTrafo(6);
    costo_mva = TipoTrafo(7);
    costo_trafo = costo_fijo + costo_mva*sr;
    vida_util = TipoTrafo(8);
    trafo = cTransformador2D();
    ubicacion = se_at.entrega_ubicacion();
    nombre = strcat('T', num2str(lpar), '_B', num2str(ubicacion), '_Sr_', num2str(sr),'_V_', num2str(vat), '_', num2str(vbt));
	trafo.inserta_nombre(nombre);
    trafo.inserta_subestacion(se_at,1);
	trafo.inserta_subestacion(se_bt,2);
	trafo.inserta_tipo_conexion('Y', 'y', 0);
    trafo.inserta_sr(sr);
    trafo.inserta_indice_paralelo(lpar);
	trafo.inserta_pcu(0);
    trafo.inserta_uk(uk);
    trafo.inserta_i0(0);
    trafo.inserta_p0(0);
    trafo.inserta_tipo_trafo(tipo_trafo);
    trafo.inserta_anio_construccion(0);
    trafo.inserta_costo_transformador(costo_trafo);
    trafo.inserta_vida_util(vida_util);
end

function bateria = crea_bateria(TipoBateria, se, bpar)
    tipo_bat = TipoBateria(1);
    pmax = TipoBateria(2);
    emax = TipoBateria(3);
    cinv_potencia_mw = TipoBateria(4); %en k$/MW
    cinv_capacidad_mwh = TipoBateria(5); %en k$/MWh
    vida_util = TipoBateria(6);
    eta_carga = TipoBateria(7);
    eta_descarga = TipoBateria(8);
    
    cinv_potencia = cinv_potencia_mw*pmax/1000; % en M$
    cinv_capacidad = cinv_capacidad_mwh*emax/1000; % en M$
    bateria = cBateria();
    ubicacion = se.entrega_ubicacion();
    nombre = strcat('S', num2str(bpar), '_B', num2str(ubicacion), '_Sr_', num2str(pmax),'E_', num2str(emax));
	bateria.inserta_nombre(nombre);
    bateria.inserta_subestacion(se);
    bateria.inserta_pmax_carga(pmax);
    bateria.inserta_pmax_descarga(pmax); % por ahora pmax descarga = pmax carga
    bateria.inserta_sr(pmax*1.1); % por ahora
    bateria.inserta_capacidad(emax);
    bateria.inserta_indice_paralelo(bpar);
    bateria.inserta_id_tecnologia(tipo_bat);
    bateria.inserta_anio_construccion(0);
    bateria.inserta_costo_inversion_potencia(cinv_potencia);
    bateria.inserta_costo_inversion_capacidad(cinv_capacidad);
    bateria.inserta_vida_util(vida_util);
    bateria.inserta_eficiencia_carga(eta_carga);
    bateria.inserta_eficiencia_descarga(eta_descarga);    
end