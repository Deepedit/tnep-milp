function importa_problema_optimizacion_tnep(data, sep, adm_proy, pAdmSc, pParOpt)
    NivelDebug = 0;
    % data en formato PLAS
    
    factor_desarrollo_proyectos = data.Costos(1,2);
    pParOpt.inserta_factor_costo_desarrollo_proyectos(factor_desarrollo_proyectos);
    se_aisladas = importa_buses(data,sep);
    
    importa_consumos(data, pParOpt, sep, pAdmSc);
    
    importa_generadores(data, pParOpt, sep, pAdmSc);
    
    % corredores
    [LineasBase, LineasCC, LineasCS, LineasVU, TrafosVU] = genera_lineas(data, ...
                                                                  pParOpt, ...
                                                                  sep, ...
                                                                  adm_proy, ...
                                                                  NivelDebug);

    
    % genera proyectos de expansión
    genera_proyectos_expansion(LineasBase, LineasCC, LineasCS, LineasVU, TrafosVU, adm_proy);
    for i = 1:length(se_aisladas)
        adm_proy.agrega_proyectos_obligatorios(se_aisladas(i));
    end
    
    if pParOpt.considera_reconductoring() || pParOpt.considera_compensacion_serie() || pParOpt.ConsideraVoltageUprating()
        adm_proy.genera_dependencias_cambios_estado();
    end
    
    el_red_existente = sep.entrega_lineas();
    el_red_existente = [el_red_existente; sep.entrega_transformadores2d()];

    adm_proy.inserta_elementos_serie_existentes(el_red_existente);
    adm_proy.determina_proyectos_por_elementos();
    
    if NivelDebug > 1
        adm_proy.imprime_proyectos();
        %sep.grafica_sistema('Sistema inicial', false);
    end
end

function se_aisladas = importa_buses(data, sep)
    % Buses = [id, vn conectado (0/1)]
    Buses = data.Buses;

    se_aisladas = cSubestacion.empty;
    [nb, ~] = size(Buses);
    for i = 1:nb
        se = cSubestacion;
        se.inserta_nombre(strcat('SE_',num2str(i),'_VB_', num2str(Buses(i, 2))));
        se.inserta_vn(Buses(i, 2));
        sep.agrega_subestacion(se);
        if Buses(i,3) == 0
            se_aisladas(end+1) = se;
        end
        posX = Buses(i,4);
        posY = Buses(i,5);
        se.inserta_posicion(posX, posY);
        se.inserta_ubicacion(i);
    end
end

function importa_consumos(data, param, sep, pAdmSc)
    Consumos = data.Consumos;
    Buses = data.Buses;
    
    %              1   2     3         4           5         6
    % Consumos = [id, bus, p0 (MW), q0 (MW), dep_volt, NLS costs USD/MWh]
    [nc, ~] = size(Consumos);
    for i = 1:nc
        id_bus = Consumos(i,2);
        vn = Buses(id_bus,2);
        consumo = cConsumo;
        nombre_bus = strcat('SE_', num2str(Consumos(i,2)),'_VB_', num2str(vn));
        se = sep.entrega_subestacion(nombre_bus);
        if isempty(se)
            error = MException('cimporta_problema_optimizacion_tnep:main','no se pudo encontrar subestación');
            throw(error)
        end
            
        consumo.inserta_subestacion(se);
        consumo.inserta_nombre(strcat('Consumo_',num2str(i), '_', se.entrega_nombre()));
        consumo.inserta_p0(Consumos(i,3));
        consumo.inserta_q0(Consumos(i,4));
        if Consumos(i,5) == 0
            depvolt = false;
        else
            depvolt = true;
        end
        consumo.inserta_tiene_dependencia_voltaje(depvolt);
        costo_nls = Consumos(i,6);
        consumo.inserta_costo_desconexion_carga(costo_nls);
        se.agrega_consumo(consumo);
        sep.agrega_consumo(consumo);
        
        %agrega consumo a administrador de escenarios
        indice = pAdmSc.ingresa_nuevo_consumo(consumo.entrega_nombre);
        consumo.inserta_indice_escenario(indice);
        nro_etapas = param.entrega_no_etapas();
        cant_po = param.entrega_cantidad_puntos_operacion();
        aumento_porc = Consumos(i,7);
        p0 = Consumos(i,3);
        petapa = p0;
        for j = 1:nro_etapas
            if j > 1
                petapa = petapa*(1+aumento_porc/100);
            end
            for k = 1:cant_po
                pAdmSc.agrega_consumo(indice, j, k, petapa);
            end
        end
    end
end

function importa_generadores(data, param, sep, pAdmSc)
    %              1    2  3    4     5     6     7     8      9      10      11 
    % Generador: [id, bus, P0, Q0, Pmax, Pmin, Qmax, Qmin, Vobj pu, status, Slack, USD/Mwh]
	Generadores = data.Generadores;
    Buses = data.Buses;
    [ng, ~] = size(Generadores);
    for i = 1:ng
        gen = cGenerador();
        id_bus = Generadores(i,2);
        vn = Buses(id_bus,2);
        nombre_bus = strcat('SE_', num2str(Generadores(i,2)),'_VB_', num2str(vn));
        se = sep.entrega_subestacion(nombre_bus);
        if isempty(se)
            error = MException('cimporta_problema_optimizacion_tnep:main','no se pudo encontrar subestación');
            throw(error)
        end
    
        gen.inserta_nombre(strcat('G', num2str(i), '_', nombre_bus));
        gen.inserta_subestacion(se);
        p0 = Generadores(i,3);
        q0 = Generadores(i,4);
        pmax = Generadores(i,5);
        pmin = Generadores(i,6);
        qmax = Generadores(i,7);
        qmin = Generadores(i,8);
        Vobj = Generadores(i,9);
        status = Generadores(i,10);
        Slack = Generadores(i,11);
        if Slack == 1
            gen.inserta_es_slack();
        end
        Costo_mwh = Generadores(i,12);
        gen.inserta_pmax(pmax);
        gen.inserta_pmin(pmin);
        gen.inserta_costo_mwh(Costo_mwh);
        gen.inserta_qmin(qmin);
        gen.inserta_qmax(qmax);
        gen.inserta_p0(p0);
        gen.inserta_q0(q0);
        gen.inserta_controla_tension();
        gen.inserta_voltaje_objetivo(se.entrega_vn()*Vobj);
        gen.inserta_en_servicio(status);
        se.agrega_generador(gen);
        sep.agrega_generador(gen);

        %agrega generador a administrador de escenarios
        indice = pAdmSc.ingresa_nuevo_generador(gen.entrega_nombre);
        gen.inserta_indice_escenario(indice);
        nro_etapas = param.entrega_no_etapas();
        cant_po = param.entrega_cantidad_puntos_operacion();
        aumento_porc = Generadores(i,13);
        pmax = Generadores(i,5);
        petapa = pmax;
        for j = 1:nro_etapas
            if j > 1
                petapa = petapa*(1+aumento_porc/100);
            end
            for k = 1:cant_po
                pAdmSc.agrega_capacidad_generador(indice, j, petapa);
            end
        end
        
    end
end

function [LineasBase, LineasCC, LineasCS, LineasVU, TrafosVU] = genera_lineas(data, ...
                                                                    param, ...
                                                                    sep, ...
                                                                    adm_proy, ...
                                                                    NivelDebug)
    % Crea total de líneas por cada corredor.
    % Transformadores se tratan como líneas, con la diferencia que no hay
    % ni VU, CS ni CC
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
    Lineas = data.Lineas;
    Transformadores = data.Transformadores;
    Conductores = data.Conductores;
    TipoTransformadores = data.TipoTransformadores;
    UbicacionesTransformadoresVU = [];
    Buses = data.Buses;
    
    [nc, ~] = size(Corredores);
    [ncond, ~] = size(Conductores);
    [ntipo_trafos, ~] = size(TipoTransformadores);
    
    subestaciones = sep.entrega_subestaciones();
    for se = 1:length(subestaciones)
        ubicacion = subestaciones(se).entrega_ubicacion();
        TrafosVU(ubicacion).Existe = 0;
        TrafosVU(ubicacion).Nmax = 0;
    end
    % primero lineas base junto con reconductoring y compensación serie.
    % Voltage uprating se ve después
    % no es eficiente pero se entiende mejor el código
    
    % Lineas: [bus1, bus2, rpu, xpu, bpu, sr, status, C (MM.USD) tipo_conductor]
    for id_corr = 1:nc
        es_transformador = false;
        es_linea = false;
        % primero hay que buscar el voltaje base
        id_bus_1 = Corredores(id_corr, 1);
        id_bus_2 = Corredores(id_corr, 2);
        vbase = Buses(id_bus_1,2);
        vbase_1 = Buses(id_bus_1,2);
        vbase_2 = Buses(id_bus_2,2);
        largo = Corredores(id_corr, 3);
        if largo == 0
            % transformador base
            es_transformador = true;
            %continue;
        else
            es_linea = true;
        end
        nombre_bus1 = strcat('SE_', num2str(id_bus_1), '_VB_', num2str(vbase_1));
        nombre_bus2 = strcat('SE_', num2str(id_bus_2), '_VB_', num2str(vbase_2));
        se1 = sep.entrega_subestacion(nombre_bus1);
        se2 = sep.entrega_subestacion(nombre_bus2);
        vn = se1.entrega_vn();
        vn_1 = se1.entrega_vn();
        vn_2 = se2.entrega_vn();
        
        nmax = Corredores(id_corr,4);
        LineasBase(id_corr).Nmax = nmax;
        LineasBase(id_corr).Largo = largo;
        LineasReconductoring(id_corr).Existe = 0;
        LineasVU(id_corr).Existe = 0;
        LineasCS(id_corr).Existe = 0;
        LineasCC(id_corr).Existe = 0;
        % Verifica que datos de entrada sean consistentes en cuanto al tipo
        % de conductor. TODO: Método no es eficiente. Hay que buscar otro
        % más eficiente
        if es_linea
            id_lineas = ismember(Lineas(:,1:2),[Corredores(id_corr,1) Corredores(id_corr,2)],'rows');
            LineasAux = Lineas(id_lineas,:); %contiene todas las líneas que pertenecen a un mismo corredor
            conductor_base = LineasAux(1, 9);
            [naux, ~] = size(LineasAux);
            nlineas_existentes = 0;
            for aux = 1:naux
                if LineasAux(aux, 9) ~= conductor_base
                    error = MException('importa_problema_optimizacion_tnep:genera_lineas','Error en datos de entrada. Tipo de conductor para línea paralela no coincide');
                    throw(error)
                end
                if LineasAux(aux, 7) == 1
                    nlineas_existentes = nlineas_existentes +1;
                    anio_construccion(nlineas_existentes) = LineasAux(aux, 10);
                end
            end
        elseif es_transformador
            id_trafos = ismember(Transformadores(:,1:2),[Corredores(id_corr,1) Corredores(id_corr,2)],'rows');
            TrafosAux = Transformadores(id_trafos,:); %contiene todos los trafos que pertenecen a un mismo corredor
            tipo_trafo_base = TrafosAux(1, 6);
            [naux, ~] = size(TrafosAux);
            nlineas_existentes = 0;
            for aux = 1:naux
                if TrafosAux(aux, 6) ~= tipo_trafo_base
                    error = MException('importa_problema_optimizacion_tnep:genera_lineas','Error en datos de entrada. Tipo de transformador para trafo paralelo no coincide');
                    throw(error)
                end
                %if TrafosAux(aux, 7) == 1
                % en el caso de trafos siempre son existentes
                    nlineas_existentes = nlineas_existentes +1;
                    anio_construccion(nlineas_existentes) = TrafosAux(aux, 10);
                %end
            end
        else
            error = MException('importa_problema_optimizacion_tnep:genera_lineas','Error de programacion. Corredor no es ni linea ni transformador');
            throw(error)
        end
        LineasBase(id_corr).NExistente = nlineas_existentes;
        if es_linea
            LineasBase(id_corr).ConductorBase = conductor_base;
        else
            LineasBase(id_corr).ConductorBase = tipo_trafo_base;            
        end
        
        if es_linea
            n_actual = ncond;
        else
            n_actual = ntipo_trafos;
        end
        
        for id_cond = 1:ncond
            vn_conductor = Conductores(id_cond, 12);

            if vn_conductor ~= vn
                % líneas con voltage superior se ven en el marco de
                % voltage uprating
                continue;
            end
            
            % se separan casos de líneas existentes y proyectadas
            if nlineas_existentes > 0
                % en este caso ya hay líneas existentes. Se elijen otros
                % conductores sólo si se considera reconductoring
                if ~param.considera_reconductoring() 
                    if conductor_base ~= id_cond
                        % crea sólo líneas en base a conductor existente
                        continue;
                    end
                else
                    if largo > 80
                        % reconductoring sólo para líneas cortas
                        if conductor_base ~= id_cond
                            % crea sólo líneas en base a conductor existente
                            continue;
                        end
                    end 
                end
            else
                % no hay líneas existentes. Se consideran otros conductores
                % con el mismo voltage sólo si se puede elegir el tipo de conductor 
                %(si no, sólo se considera conductor base). 
                if ~param.elije_tipo_conductor()
                    if conductor_base ~= id_cond
                        % crea sólo líneas en base a conductor existente
                        continue;
                    end
                else
                    % se puede escoger el tipo de conductor. En este caso conductores HTLS 
                    % sólo se consideran para líneas cortas (por los
                    % costos). Otros conductores convencionales se
                    % consideran en ambos casos
                    if Conductores(id_cond, 2) == 2 && largo > 80
                        continue;
                    end
                end
            end
                        
            for lpar = 1:nmax
                linea = crea_linea(Conductores(id_cond,:),Corredores(id_corr,:), data.Costos, se1, se2, lpar, id_corr); 
                
                if nlineas_existentes >= lpar && LineasBase(id_corr).ConductorBase == id_cond
                    linea.inserta_anio_construccion(anio_construccion(lpar));
                    %agrega línea al SEP
                    sep.agrega_linea(linea);
                    se1.agrega_linea(linea);
                    se2.agrega_linea(linea);
                else
                    linea.Existente = false;
                    adm_proy.inserta_elemento_serie(linea);
                end
                % se guarda el tipo de conductor para la línea generada
                if lpar == 1
                    if LineasBase(id_corr).ConductorBase == id_cond
                        LineasBase(id_corr).Linea = linea;
                    else
                        LineasCC(id_corr).Conductor(id_cond).Linea = linea;
                        LineasCC(id_corr).Existe = 1;
                    end
                else
                    if LineasBase(id_corr).ConductorBase == id_cond
                        LineasBase(id_corr).Linea = [LineasBase(id_corr).Linea; linea];
                    else
                        LineasCC(id_corr).Conductor(id_cond).Linea = [LineasCC(id_corr).Conductor(id_cond).Linea; linea];
                    end
                end
            end
        end

        % voltage uprating
        % por cada línea, se agrega "nueva" línea con parámetros
        % adecuados. En caso de que no existan líneas en el corredor, se
        % considera otro voltaje sólo si parámetros del programa así lo
        % indican
        % en este punto no se han agregado buses con voltaje mayor al base
        % los transformadores también se generan aquí. Se asume que no hay
        % transformadores previos
        if param.considera_voltage_uprating() || param.elije_voltage_lineas_nuevas()
            VoltageUprating = data.VoltageUprating;
            [nvolt_ur, ~] = size(VoltageUprating);
    
            for vur = 1:nvolt_ur
                vfinal = VoltageUprating(vur,2);
                costo_fijo = VoltageUprating(vur,3);
                if vfinal <= vn
                    continue;
                end
                
                if nlineas_existentes == 0 && ~param.elije_voltage_lineas_nuevas()
                    % no hay líneas existentes y no se elije voltage en líneas
                    % nuevas. Nada que hacer
                    continue;
                end
                
                if nlineas_existentes > 0 && ~param.considera_voltage_uprating()
                    % hay líneas existentes pero no se considera voltage
                    % uprating
                    continue;
                end
                
                nombre_bus1 = strcat('SE_', num2str(id_bus_1), '_VU_', num2str(vfinal));
                nombre_bus2 = strcat('SE_', num2str(id_bus_2), '_VU_', num2str(vfinal));
                se1_vur = adm_proy.entrega_bus(nombre_bus1, false);
                se2_vur = adm_proy.entrega_bus(nombre_bus2, false);
                
                % en caso de que no existan, buses para voltage uprating se crean 
                % sólo en caso de que efectivamente se vayan a utilizar.
                % Eventualmente los datos de entrada hacen que en
                % determinados casos no sea necesario crear en bus

                % se separan los casos cuando hay líneas existentes y
                % cuando no
                if nlineas_existentes == 0
                    % en este caso se crean líneas con conductor acorde con
                    % el voltaje. Para líneas cortas se consideran todos
                    % los conductores; para líneas largas sólo conductores
                    % convencionales

                    for id_cond = 1:ncond
                        vn_conductor = Conductores(id_cond, 12);

                        if vn_conductor ~= vfinal
                            continue;
                        end
                        
                        if largo > 80 && Conductores(id_cond, 2) == 2
                            continue;
                        end

                        if isempty(se1_vur)
                            se1_vur = crea_nueva_subestacion(se1, vfinal, costo_fijo, adm_proy);
                            % como es una nueva subestación (no uprating una existente), hay que
                            % agregar sus costos respectivos
                            adm_proy.inserta_bus(se1_vur);
                        end
                        if isempty(se2_vur)
                            se2_vur = crea_nueva_subestacion(se2, vfinal, costo_fijo, adm_proy);
                            adm_proy.inserta_bus(se2_vur);
                        end
                        
                        for lpar = 1:nmax
                            linea = crea_linea(Conductores(id_cond,:),Corredores(id_corr,:), data.Costos, se1_vur, se2_vur, lpar, id_corr);

                            linea.inserta_anio_construccion(0);
                            linea.Existente = false;
                            adm_proy.inserta_elemento_serie(linea);
                            % se guarda el tipo de conductor para la línea generada
                            if lpar == 1
                                LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea = linea;
                                LineasVU(id_corr).VUR(vur).Voltaje = vfinal;
                                LineasVU(id_corr).Existe = 1;
                            else
                            	LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea = [LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea; linea];
                            end
                        end
                    end
                else
                    % ya hay líneas existentes. Se separan dos casos:
                    % 1: voltage uprating se puede hacer con conductor
                    % existente
                    % 2: voltage uprating obliga a cambio de conductor
                    if ~param.cambio_conductor_voltage_uprating()
                        % caso 1: no es necesario cambiar de conductor. En
                        % este caso se considera voltage uprating sólo para
                        % conductor existente (no es la idea analizar
                        % combinaciones de uprating)
                        id_cond = LineasBase(id_corr).ConductorBase;
                            
                        if isempty(se1_vur)
                            se1_vur = crea_nueva_subestacion(se1, vfinal, costo_fijo, adm_proy);
                            adm_proy.inserta_bus(se1_vur);
                        end
                        if isempty(se2_vur)
                        	se2_vur = crea_nueva_subestacion(se2, vfinal, costo_fijo, adm_proy);
                            adm_proy.inserta_bus(se2_vur);
                        end
                            
                        for id_linea = 1:length(LineasBase(id_corr).Linea)
                            linea = LineasBase(id_corr).Linea(id_linea).crea_copia();
                            sth_orig = linea.entrega_sth();
                            vn_orig = linea.entrega_se1().entrega_vn();
                            linea.agrega_subestacion(se1_vur,1);
                            linea.agrega_subestacion(se2_vur,2);
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
                            
                            id_corr1 = Corredores(id_corr,1);
                            id_corr2 = Corredores(id_corr,2);
                            nombre = strcat('L', num2str(lpar), '_C', num2str(id_cond), '_SE', num2str(id_corr1), '_', num2str(id_corr2), '_V', num2str(vfinal));
                            linea.inserta_nombre(nombre);
                            linea.inserta_anio_construccion(0);
                            linea.Existente = false;

                            adm_proy.inserta_elemento_serie(linea);
                            if id_linea == 1
                            	LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea = linea;
                                LineasVU(id_corr).VUR(vur).Voltaje = vfinal;
                                LineasVU(id_corr).Existe = 1;
                            else
                            	LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea = [LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea; linea];
                            end
                        end
                    else
                        % hay que generar líneas con conductor(es) ad-hoc
                        for id_cond = 1:ncond
                            vn_conductor = Conductores(id_cond, 12);

                            if vn_conductor ~= vfinal
                                continue;
                            end

                            if isempty(se1_vur)
                                se1_vur = crea_nueva_subestacion(se1, vfinal, costo_fijo, adm_proy);
                                adm_proy.inserta_bus(se1_vur);
                            end
                            if isempty(se2_vur)
                                se2_vur = crea_nueva_subestacion(se2, vfinal, costo_fijo, adm_proy);
                                adm_proy.inserta_bus(se2_vur);
                            end
                            
                            for lpar = 1:nmax
                                linea = crea_linea(Conductores(id_cond,:),Corredores(id_corr,:), data.Costos, se1_vur, se2_vur, lpar, id_corr); 

                                linea.inserta_anio_construccion(0);
                                linea.Existente = false;
                                adm_proy.inserta_elemento_serie(linea);
                                % se guarda el tipo de conductor para la línea generada
                                if lpar == 1
                                    LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea = linea;
                                    LineasVU(id_corr).VUR(vur).Voltaje = vfinal;
                                    LineasVU(id_corr).Existe = 1;
                                else
                                    LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea = [LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea; linea];
                                end
                            end
                        end
                    end
                end
                
                % se generan los transformadores en ambos lados si es que
                % aún no se han creado.
                % se crean tantos transformadores como nmax
                ubicacion_1 = se1.entrega_ubicacion();
                ubicacion_2 = se2.entrega_ubicacion();
                crea_ubicacion_1 = isempty(find(UbicacionesTransformadoresVU == ubicacion_1, 1));
                crea_ubicacion_2 = isempty(find(UbicacionesTransformadoresVU == ubicacion_2, 1));
                if crea_ubicacion_1 || crea_ubicacion_2
                    TipoTrafos = data.TipoTransformadores;
                    [nt, ~] = size(TipoTrafos);
                    for id_trafo = 1:nt
                        vat = TipoTrafos(id_trafo, 3);
                        vbt = TipoTrafos(id_trafo, 4);
                        if vat ~= vfinal || vbt ~= vn
                            continue;
                        end

                        if isempty(se1_vur) || isempty(se2_vur)
                            error = MException('cimporta_sep_power_flow_test:genera_lineas','subestación para transformadores no se pudo encontrar');
                            throw(error)
                        end
                        if crea_ubicacion_1
                            UbicacionesTransformadoresVU(end+1) = ubicacion_1;
                            TrafosVU(ubicacion_1).Existe = 1;
                            % trafo lado 1
                            for par = 1:nmax
                                trafo = crea_transformador(TipoTrafos(id_trafo,:), se1_vur, se1, par);
                                trafo.Existente = false;
                                adm_proy.inserta_elemento_serie(trafo);
                                if par == 1
                                    TrafosVU(ubicacion_1).Tipo(id_trafo).Trafos = trafo;
                                    TrafosVU(ubicacion_1).Nmax = 1;
                                else
                                    TrafosVU(ubicacion_1).Tipo(id_trafo).Trafos = [TrafosVU(ubicacion_1).Tipo(id_trafo).Trafos; trafo];
                                    TrafosVU(ubicacion_1).Nmax = TrafosVU(ubicacion_1).Nmax + 1;
                                end
                            end
                        end
                        if crea_ubicacion_2
                            UbicacionesTransformadoresVU(end+1) = ubicacion_2;
                            TrafosVU(ubicacion_2).Existe = 1;
                            % trafo lado 2
                            for par = 1:nmax
                                trafo = crea_transformador(TipoTrafos(id_trafo,:), se2_vur, se2, par);
                                trafo.Existente = false;
                                adm_proy.inserta_elemento_serie(trafo);
                                if par == 1
                                    TrafosVU(ubicacion_2).Tipo(id_trafo).Trafos = trafo;
                                    TrafosVU(ubicacion_2).Nmax = 1;
                                else
                                    TrafosVU(ubicacion_2).Tipo(id_trafo).Trafos = [TrafosVU(ubicacion_2).Tipo(id_trafo).Trafos; trafo];
                                    TrafosVU(ubicacion_2).Nmax = TrafosVU(ubicacion_2).Nmax + 1;
                                end
                                
                            end
                        end
                    end
                end
            end
        end
        
        % compensación en serie.
        if param.considera_compensacion_serie() && largo > 80
            Compensacion_serie = data.CompensacionSerie;        
        	[ncomp_serie, ~] = size(Compensacion_serie);
            
            % se crea compensación en serie separando los casos de líneas
            % base y para otras líneas (reconductoring en caso de que en
            % líneas nuevas se pueda elegir el tipo de conductor
            for id_linea = 1:length(LineasBase(id_corr).Linea)
                for comp = 1:ncomp_serie
                    % por cada tipo/cantidad de compensación, se crean nuevas
                    % líneas (copia de las actuales) por cada tipo de conductor
                    % existente
                    porcentaje_comp = Compensacion_serie(comp,2);
                    linea = LineasBase(id_corr).Linea(id_linea).crea_copia();
                    lpar = linea.entrega_indice_paralelo();
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
                    adm_proy.inserta_elemento_serie(linea);
                        
                    if id_linea == 1
                    	LineasCS(id_corr).Conductor(conductor_base).Compensacion(comp).Linea = linea;
                        LineasCS(id_corr).Conductor(conductor_base).Compensacion(comp).Porcentaje = porcentaje_comp;
                        LineasCS(id_corr).Existe = 1;
                    else
                        LineasCS(id_corr).Conductor(conductor_base).Compensacion(comp).Linea = [LineasCS(id_corr).Conductor(conductor_base).Compensacion(comp).Linea; linea];
                    end
                end
            end
            % otros conductores en caso de que se pueda elegir el tipo de
            % conductor para líneas nuevas
            if nlineas_existentes == 0 && param.elije_tipo_conductor()
                for id_cond = 1:length(LineasCC(id_corr).Conductor)
                    for id_linea = 1:length(LineasCC(id_corr).Conductor(id_cond).Linea)
                        for comp = 1:ncomp_serie
                            % por cada tipo/cantidad de compensación, se crean nuevas
                            % líneas (copia de las actuales) por cada tipo de conductor
                            % existente
                            porcentaje_comp = Compensacion_serie(comp,2);
                            linea = LineasCC(id_corr).Conductor(id_cond).Linea(id_linea).crea_copia();
                            lpar = linea.entrega_indice_paralelo();
                            id_se1 = se1().entrega_id();
                            id_se2 = se2().entrega_id();
                            nombre = strcat('L', num2str(lpar), '_C', num2str(id_cond), '_Comp_', num2str(porcentaje_comp*100), ...
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
                            
                            % cálculo de Sr
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

                            adm_proy.inserta_elemento_serie(linea);
                            if id_linea == 1
                                LineasCS(id_corr).Conductor(id_cond).Compensacion(comp).Linea = linea;
                                LineasCS(id_corr).Conductor(id_cond).Compensacion(comp).Porcentaje = porcentaje_comp;
                                LineasCS(id_corr).Existe = 1;
                            else
                                LineasCS(id_corr).Conductor(id_cond).Compensacion(comp).Linea = [LineasCS(id_corr).Conductor(id_cond).Compensacion(comp).Linea; linea];
                            end
                        end
                    end
                end
            end
        end
    end
    
    % agrega id de líneas proyectadas y nuevas subestaciones
    % no es necesario, pero por consistencia
    id_lineas = sep.entrega_cantidad_lineas();
    id_trafos = sep.entrega_cantidad_transformadores_2D();
    id_se = sep.entrega_cantidad_subestaciones();
    el_red = adm_proy.entrega_elementos_serie();
    el_red = [el_red; adm_proy.entrega_buses()];
    for i = 1:length(el_red)
        if isa(el_red(i), 'cLinea')
            id_lineas = id_lineas + 1;
            el_red(i).inserta_id(id_lineas);
        elseif isa(el_red(i), 'cSubestacion')
            id_se = id_se + 1;
            el_red(i).inserta_id(id_se);
        elseif isa(el_red(i), 'cTransformador2D')
            id_trafos = id_trafos + 1;
            el_red(i).inserta_id(id_trafos);
        else
            error = MException('cimporta_problema_optimizacion_tnep:genera_lineas','tipo elemento para expansión aún no implementado');
            throw(error)
        end
    end
    
    if NivelDebug > 1
        % imprime líneas por corredor
        % primero, líneas existentes en el SEP y luego lineas proyectadas
        lineas_existentes = sep.entrega_lineas();
        lineas_proyectadas = el_red;

        prot = cProtocolo.getInstance;
        prot.imprime_texto('Imprime lineas');
        for id_corr = 1:nc
            id_bus_1 = Corredores(id_corr, 1);
            id_bus_2 = Corredores(id_corr, 2);
            vbase = Buses(id_bus_1,2);

            nombre_bus1 = strcat('SE_', num2str(id_bus_1), '_VB_', num2str(vbase));
            nombre_bus2 = strcat('SE_', num2str(id_bus_2), '_VB_', num2str(vbase));

            se1 = sep.entrega_subestacion(nombre_bus1);
            se2 = sep.entrega_subestacion(nombre_bus2);
            ubicacion_1 = se1.entrega_ubicacion();
            ubicacion_2 = se2.entrega_ubicacion();
            lineas_a_borrar = [];
            primero = true;
            prot.imprime_texto(['Corredor ' num2str(id_corr) ' entre buses ' num2str(ubicacion_1) '-' num2str(ubicacion_2)]);
            for i = 1:length(lineas_existentes)
                ubic_1 = lineas_existentes(i).entrega_se1().entrega_ubicacion();
                ubic_2 = lineas_existentes(i).entrega_se2().entrega_ubicacion();
                if ubic_1 == ubicacion_1 && ubic_2 == ubicacion_2
                    lineas_a_borrar = [lineas_a_borrar i];
                    %lineas_existentes(i).imprime_parametros_pu(primero);
                    lineas_existentes(i).imprime_parametros_fisicos(primero, 'E');
                    primero = false;
                end
            end
            lineas_existentes(lineas_a_borrar) = [];
            lineas_a_borrar = [];
            for i = 1:length(lineas_proyectadas)
                if isa(lineas_proyectadas(i), 'cLinea')
                    linea_proy = lineas_proyectadas(i);
                    ubic_1 = linea_proy.entrega_se1().entrega_ubicacion();
                    ubic_2 = linea_proy.entrega_se2().entrega_ubicacion();
                    if ubic_1 == ubicacion_1 && ubic_2 == ubicacion_2
                        lineas_a_borrar = [lineas_a_borrar i];                    
                        linea_proy.imprime_parametros_fisicos(primero, 'P');
                        %lineas_proyectadas(i).imprime_parametros_pu(primero);
                        primero = false;
                    end
                end
            end
            lineas_proyectadas(lineas_a_borrar) = [];
        end
        %verifica que no existan líneas existentes o proyectadas sin
        %haberse impreso
        for i = 1:length(lineas_existentes)
            error = MException('cimporta_problema_optimizacion_tnep:genera_lineas',...
                ['linea existente ' lineas_existentes(i).entrega_nombre() ' no fue impresa']);
            throw(error)
        end
        for i = 1:length(lineas_proyectadas)
            if isa(lineas_proyectadas(i), 'cLinea')
                error = MException('cimporta_problema_optimizacion_tnep:genera_lineas',...
                    ['linea proyectada ' lineas_proyectadas(i).entrega_nombre() ' no fue impresa']);
                throw(error)
            end
        end

        % imprime transformadores por ubicaciones
        prot.imprime_texto('\nImprime transformadores');
        trafos_existentes = sep.entrega_transformadores2d();
        trafos_proyectados = el_red;
        subestaciones = sep.entrega_subestaciones();
        for se = 1:length(subestaciones)
            ubicacion = subestaciones(se).entrega_ubicacion();
            
            trafos_a_borrar = [];
            primero = true;
            prot = cProtocolo.getInstance;
            prot.imprime_texto(['Ubicacion' num2str(ubicacion)]);
            for i = 1:length(trafos_existentes)
                ubic = trafos_existentes(i).entrega_ubicacion();
                if ubic == ubicacion
                    trafos_a_borrar = [trafos_a_borrar i];
                    trafos_existentes(i).imprime_parametros_fisicos(primero, 'E');
                    primero = false;
                end
            end
            trafos_existentes(trafos_a_borrar) = [];
            
            trafos_a_borrar = [];
            for i = 1:length(trafos_proyectados)
                if isa(trafos_proyectados(i), 'cTransformador2D')
                    trafo_proy = trafos_proyectados(i);
                    ubic = trafo_proy.entrega_ubicacion();
                    if ubic == ubicacion
                        trafos_a_borrar = [trafos_a_borrar i];                    
                        trafo_proy.imprime_parametros_fisicos(primero, 'P');
                        %lineas_proyectadas(i).imprime_parametros_pu(primero);
                        primero = false;
                    end
                end
            end
            trafos_proyectados(trafos_a_borrar) = [];
        end
        %verifica que no existan trafos existentes o proyectados sin
        %haberse impreso
        for i = 1:length(trafos_existentes)
            error = MException('cimporta_problema_optimizacion_tnep:genera_lineas',...
                ['trafo existente ' trafos_existentes(i).entrega_nombre() ' no fue impreso']);
            throw(error)
        end
        for i = 1:length(trafos_proyectados)
            if isa(trafos_proyectados(i), 'cTransformador2D')
                error = MException('cimporta_problema_optimizacion_tnep:genera_lineas',...
                    ['trafo proyectado ' trafos_proyectados(i).entrega_nombre() ' no fue impreso']);
                throw(error)
            end
        end
        
        % grafica estados
        %close all
        
    end
end

function genera_proyectos_expansion(LineasBase, LineasCC, LineasCS, LineasVU, TrafosVU, adm_proy)
    genera_proyectos_expansion_subestaciones_transformadores(TrafosVU, adm_proy);
    genera_proyectos_expansion_lineas(LineasBase, LineasCC, LineasCS, LineasVU, adm_proy);
    genera_restricciones_conectividad_se_nuevas(adm_proy);
end

function genera_proyectos_expansion_subestaciones_transformadores(TrafosVU, adm_proy)
    % primero genera proyectos de subestaciones
    se_nuevas = adm_proy.entrega_buses();
    
    for i = 1:length(se_nuevas)
        proy = crea_proyecto_agrega_subestacion(se_nuevas(i));
        adm_proy.agrega_proyecto(proy);
    end
    
    % TrafosVU(id_ubicacion).Tipo(id_tipo).Trafos = [(T1,id_tipo), ...]
    % TrafosVU(id_ubicacion).Existe = 0 (no hay), 1
    % TrafosVU(id_ubicacion).Nmax indica cantidad trafos paralelos

    MatrizEstados = [];
    for ubic = 1:length(TrafosVU)
        if ~TrafosVU(ubic).Existe
            MatrizEstados(ubic).Existe = false;
            continue;
        end
        MatrizEstados(ubic).Existe = true;
        EstadosTrafo = [];
        id_estado = 0;        
        for id_tipo = 1:length(TrafosVU(ubic).Tipo)
            if ~isempty(TrafosVU(ubic).Tipo(id_tipo).Trafos)
                EstadosTrafo(length(EstadosTrafo)+1,1) = id_tipo;
                id_estado = id_estado + 1;
                for i = 1:length(TrafosVU(ubic).Tipo(id_tipo).Trafos)
                    TrafosVU(ubic).Tipo(id_tipo).Trafos(i).inserta_id_estado_planificacion(id_estado);
                    sr = TrafosVU(ubic).Tipo(id_tipo).Trafos(i).entrega_sr();
                    MatrizEstados(ubic).Estado(i,id_estado).Nombre{1,1} = ['T' num2str(i)];
                    MatrizEstados(ubic).Estado(i,id_estado).Nombre{1,2} = ['S' num2str(sr)];
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
                MatrizEstados(ubic).Estado(ipar, id_estado).ProyectosEntrantes = proy; %por ahora no hay "cambio" de trafos 
                if ipar == 1
                    proy_excluyentes(end+1) = proy;
                    proy.TieneRequisitosConectividad = true;
                    proy_conect = adm_proy.entrega_proyecto_subestacion(trafo.entrega_se1());
                    proy.inserta_grupo_proyectos_conectividad(proy_conect);
                else
                    MatrizEstados(ubic).Estado(ipar-1, id_estado).ProyectosSalientes = proy;
                end
                
                if ~isempty(EstadosConducentes{i})
                    proy.TieneDependencia = true;
                    proy.inserta_proyectos_dependientes(EstadosConducentes{i});
                end
                adm_proy.agrega_proyecto(proy);
                EstadosConducentesNuevo{i} = proy;
            end
            
            if length(proy_excluyentes) > 1
                adm_proy.agrega_proyectos_excluyentes(proy_excluyentes);
            end
        end
    end
    adm_proy.inserta_matriz_estados_trafos(MatrizEstados);    
end

function genera_proyectos_expansion_lineas(LineasBase, LineasCC, LineasCS, LineasVU, adm_proy)
    % MatrizEstadosCorredores(idCorredor).Estado(parindex, no_estado).ProyectosSalientes = [Pr1; Pr2; ...]

    MatrizEstados = [];
    for id_corr = 1:length(LineasBase)
        lineas_existentes = LineasBase(id_corr).NExistente;
        nmax = LineasBase(id_corr).Nmax;
        largo = LineasBase(id_corr).Largo;
        conductor_base = LineasBase(id_corr).ConductorBase;
        
        id_estado = 1;
        EstadosBase = conductor_base;
        EstadosCC = [];
        EstadosCS = [];
        EstadosVU = [];
        existe_corredor = false;
        for i = 1:nmax
            existe_corredor = true;
            LineasBase(id_corr).Linea(i).inserta_id_estado_planificacion(id_estado);
            tipo_conductor = LineasBase(id_corr).Linea(i).entrega_tipo_conductor();
            MatrizEstados(id_corr).Estado(i,id_estado).ProyectosEntrantes = [];
            MatrizEstados(id_corr).Estado(i,id_estado).ProyectosSalientes = [];
            MatrizEstados(id_corr).Estado(i,id_estado).Nombre{1,1} = ['L' num2str(i)];
            MatrizEstados(id_corr).Estado(i,id_estado).Nombre{1,2} = ['C' num2str(tipo_conductor)]; 
        end
        
        if LineasCC(id_corr).Existe
            existe_corredor = true;
            for id_cond = 1:length(LineasCC(id_corr).Conductor)
                if ~isempty(LineasCC(id_corr).Conductor(id_cond).Linea)
                    EstadosCC(length(EstadosCC)+1,1) = id_cond;
                    id_estado = id_estado + 1;
                    for i = 1:length(LineasCC(id_corr).Conductor(id_cond).Linea)
                        LineasCC(id_corr).Conductor(id_cond).Linea(i).inserta_id_estado_planificacion(id_estado);
                        tipo_conductor = LineasCC(id_corr).Conductor(id_cond).Linea(i).entrega_tipo_conductor();
                        MatrizEstados(id_corr).Estado(i,id_estado).ProyectosEntrantes = [];
                        MatrizEstados(id_corr).Estado(i,id_estado).ProyectosSalientes = [];
                        MatrizEstados(id_corr).Estado(i,id_estado).Nombre{1,1} = ['L' num2str(i)];
                        MatrizEstados(id_corr).Estado(i,id_estado).Nombre{1,2} = ['CC' num2str(tipo_conductor)]; 
                    end
                end
            end
        end
        if LineasCS(id_corr).Existe
            existe_corredor = true;
            for id_cond = 1:length(LineasCS(id_corr).Conductor)
                for comp = 1:length(LineasCS(id_corr).Conductor(id_cond).Compensacion)
                    if ~isempty(LineasCS(id_corr).Conductor(id_cond).Compensacion(comp).Linea)
                        [ne, ~] = size(EstadosCS);
                        EstadosCS(ne+1,1) = id_cond;
                        EstadosCS(ne+1,2) = comp;
                        id_estado = id_estado + 1;
                        for i = 1:length(LineasCS(id_corr).Conductor(id_cond).Compensacion(comp).Linea)
                            LineasCS(id_corr).Conductor(id_cond).Compensacion(comp).Linea(i).inserta_id_estado_planificacion(id_estado);
                            compensacion = LineasCS(id_corr).Conductor(id_cond).Compensacion(comp).Linea(i).entrega_compensacion_serie()*100;
                            MatrizEstados(id_corr).Estado(i,id_estado).ProyectosEntrantes = [];
                            MatrizEstados(id_corr).Estado(i,id_estado).ProyectosSalientes = [];
                            MatrizEstados(id_corr).Estado(i,id_estado).Nombre{1,1} = ['L' num2str(i)];
                            MatrizEstados(id_corr).Estado(i,id_estado).Nombre{1,2} = ['CS_' num2str(compensacion)]; 
                        end
                    end
                end
            end
        end
        if LineasVU(id_corr).Existe
            existe_corredor = true;
            for vur = 1:length(LineasVU(id_corr).VUR)
                for id_cond = length(LineasVU(id_corr).VUR(vur).Conductor)
                    if ~isempty(LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea)
                        [ne, ~] = size(EstadosVU);
                        EstadosVU(ne+1,1) = id_cond;
                        EstadosVU(ne+1,2) = vur;
                        id_estado = id_estado + 1;
                        for i = 1:length(LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea)
                            LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea(i).inserta_id_estado_planificacion(id_estado);
                            voltaje = LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea(i).entrega_se1().entrega_vn();
                            MatrizEstados(id_corr).Estado(i,id_estado).ProyectosEntrantes = [];
                            MatrizEstados(id_corr).Estado(i,id_estado).ProyectosSalientes = [];
                            MatrizEstados(id_corr).Estado(i,id_estado).Nombre{1,1} = ['L' num2str(i)];
                            MatrizEstados(id_corr).Estado(i,id_estado).Nombre{1,2} = ['AV_' num2str(voltaje)]; 
                        end
                    end
                end
            end
        end
        if existe_corredor
            MatrizEstados(id_corr).Existe = true;
        else
            MatrizEstados(id_corr).Existe = false;
        end
        
        [ne_cc, ~] = size(EstadosCC);
        [ne_cs, ~] = size(EstadosCS);
        [ne_vu, ~] = size(EstadosVU);

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
                linea = LineasBase(id_corr).Linea(lpar+1);
                proy = crea_proyecto_agrega_linea(linea, 'Base');
                adm_proy.agrega_proyecto(proy);
                proy_excluyentes(end+1) = proy;
                EstadosConducentesNuevo.Base(1).Proyectos = proy;
                % MatrizEstadosCorredores(idCorredor).Estado(parindex, no_estado).ProyectosSalientes = [Pr1; Pr2; ...]
                id_estado_inicial = linea.entrega_id_estado_planificacion();
                MatrizEstados(id_corr).Estado(lpar+1,id_estado_inicial).ProyectosEntrantes = proy;

                % reconductoring
                for i = 1:ne_cc
                    id_cond = EstadosCC(i);
                    linea = LineasCC(id_corr).Conductor(id_cond).Linea(lpar+1);
                    proy = crea_proyecto_agrega_linea(linea, 'CC');
                    adm_proy.agrega_proyecto(proy);
                    proy_excluyentes(end+1) = proy;
                    EstadosConducentesNuevo.CC(i).Proyectos = proy;
    
                    id_estado_final = linea.entrega_id_estado_planificacion();
                    MatrizEstados(id_corr).Estado(lpar+1,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_corr).Estado(lpar+1,id_estado_final).ProyectosEntrantes; proy];
                end
                
                % compensacion serie
                for i = 1:ne_cs
                    id_cond = EstadosCS(i,1);
                    comp = EstadosCS(i,2);
                    linea = LineasCS(id_corr).Conductor(id_cond).Compensacion(comp).Linea(lpar+1);
                    proy = crea_proyecto_agrega_linea(linea, 'CS');
                    adm_proy.agrega_proyecto(proy);
                    proy_excluyentes(end+1) = proy;
                    EstadosConducentesNuevo.CS(i).Proyectos = proy;

                    id_estado_final = linea.entrega_id_estado_planificacion();
                    MatrizEstados(id_corr).Estado(lpar+1,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_corr).Estado(lpar+1,id_estado_final).ProyectosEntrantes; proy];
                end
                
                % voltage uprating
                for i = 1:ne_vu
                    id_cond = EstadosVU(i,1);
                    vur = EstadosVU(i,2);
                    linea = LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea(lpar+1);
                    proy = crea_proyecto_agrega_linea(linea, 'AV');
                    adm_proy.agrega_proyecto(proy);
                    proy_excluyentes(end+1) = proy;
                    EstadosConducentesNuevo.VU(i).Proyectos = proy;

                    id_estado_final = linea.entrega_id_estado_planificacion();
                    MatrizEstados(id_corr).Estado(lpar+1,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_corr).Estado(lpar+1,id_estado_final).ProyectosEntrantes; proy];
                    % como es línea nueva, hay que poner ingresar proyectos
                    % de conectividad. Se ingresan sólo transformadores, ya
                    % que estos, a su vez, tienen a la subestación como
                    % requisito de conectividad
                    proy.TieneRequisitosConectividad = true;
                    proy_conectividad_se1 = adm_proy.entrega_proyectos_transformadores(linea.entrega_se1(), 1); %1 es índice paralelo
                    proy_conectividad_se2 = adm_proy.entrega_proyectos_transformadores(linea.entrega_se2(),1);
                    proy.inserta_grupo_proyectos_conectividad(proy_conectividad_se1);
                    proy.inserta_grupo_proyectos_conectividad(proy_conectividad_se2);
                end
                if length(proy_excluyentes) > 1
                    adm_proy.agrega_proyectos_excluyentes(proy_excluyentes);
                end                
            else
                % ya existen líneas. Por cada estado, se agrega proyecto
                % "agregar linea" y luego los proyectos de cambio de estado

                %1) estado base (hacia capa inferior)
                proy_excluyentes = cProyectoExpansion.empty;
                
                % Sólo si aún quedan líneas por agregar
                if lpar + 1 <= nmax
                    linea = LineasBase(id_corr).Linea(lpar+1);
                    proy = crea_proyecto_agrega_linea(linea, 'Base');
                    if ~isempty(EstadosConducentes.Base(1).Proyectos)
                        proy.TieneDependencia = true;
                        proy.inserta_proyectos_dependientes(EstadosConducentes.Base(1).Proyectos);
                    end
                
                    adm_proy.agrega_proyecto(proy);
                    proy_excluyentes(end+1) = proy;
                    EstadosConducentesNuevo.Base(1).Proyectos = proy;

                    id_estado_final = linea.entrega_id_estado_planificacion();
                    MatrizEstados(id_corr).Estado(lpar+1,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_corr).Estado(lpar+1,id_estado_final).ProyectosEntrantes; proy];
                    MatrizEstados(id_corr).Estado(lpar,id_estado_final).ProyectosSalientes = [MatrizEstados(id_corr).Estado(lpar,id_estado_final).ProyectosSalientes; proy];
                end

                % cambios de estado
                lineas_a_remover = LineasBase(id_corr).Linea(1:lpar);
                id_estado_inicial = lineas_a_remover(1).entrega_id_estado_planificacion();
                
                % reconductoring
                for i = 1:ne_cc
                    if largo > 80
                        % no se considera reconductoring para líneas largas
                        continue;
                    end
                    id_cond = EstadosCC(i);

                    lineas_a_agregar = LineasCC(id_corr).Conductor(id_cond).Linea(1:lpar);
                    proy = crea_proyecto_cambio_estado(lineas_a_remover, lineas_a_agregar, 'CC');
                    if ~isempty(EstadosConducentes.Base(1).Proyectos)
                        proy.TieneDependencia = true;
                        proy.inserta_proyectos_dependientes(EstadosConducentes.Base(1).Proyectos);
                    end

                    adm_proy.agrega_proyecto(proy);
                    proy_excluyentes(end+1) = proy;
                    % se agrega estado conducente en esta misma capa
                    EstadosConducentes.CC(i).Proyectos = [EstadosConducentes.CC(i).Proyectos; proy];

                    id_estado_final = lineas_a_agregar(1).entrega_id_estado_planificacion();
                    MatrizEstados(id_corr).Estado(lpar,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_corr).Estado(lpar,id_estado_final).ProyectosEntrantes; proy];
                    MatrizEstados(id_corr).Estado(lpar,id_estado_inicial).ProyectosSalientes = [MatrizEstados(id_corr).Estado(lpar,id_estado_inicial).ProyectosSalientes; proy];                    
                end
                
                % compensacion serie
                for i = 1:ne_cs
                    id_cond = EstadosCS(i,1);
                    comp = EstadosCS(i,2);
                    if id_cond ~= conductor_base
                        % compensación serie sólo para el mismo conductor
                        continue;
                    end
                    lineas_a_agregar = LineasCS(id_corr).Conductor(id_cond).Compensacion(comp).Linea(1:lpar);
                    proy = crea_proyecto_cambio_estado(lineas_a_remover, lineas_a_agregar, 'CS');
                    if ~isempty(EstadosConducentes.Base(1).Proyectos)
                        proy.TieneDependencia = true;
                        proy.inserta_proyectos_dependientes(EstadosConducentes.Base(1).Proyectos);
                    end
                    adm_proy.agrega_proyecto(proy);
                    proy_excluyentes(end+1) = proy;
                    EstadosConducentes.CS(i).Proyectos = [EstadosConducentes.CS(i).Proyectos; proy];

                    id_estado_final = lineas_a_agregar(1).entrega_id_estado_planificacion();
                    MatrizEstados(id_corr).Estado(lpar,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_corr).Estado(lpar,id_estado_final).ProyectosEntrantes; proy];
                    MatrizEstados(id_corr).Estado(lpar,id_estado_inicial).ProyectosSalientes = [MatrizEstados(id_corr).Estado(lpar,id_estado_inicial).ProyectosSalientes; proy];
                end
                
                % voltage uprating
                for i = 1:ne_vu
                    id_cond = EstadosVU(i,1);
                    vur = EstadosVU(i,2);
                    lineas_a_agregar = LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea(1:lpar);
                    proy = crea_proyecto_cambio_estado(lineas_a_remover, lineas_a_agregar, 'AV');
                    if ~isempty(EstadosConducentes.Base(1).Proyectos)
                        proy.TieneDependencia = true;
                        proy.inserta_proyectos_dependientes(EstadosConducentes.Base(1).Proyectos);
                    end
                    % requisitos de conectividad
                    proy.TieneRequisitosConectividad = true;
                    proy_conectividad_1 = adm_proy.entrega_proyectos_transformadores(lineas_a_agregar(1).entrega_se1(),1);
                    proy_conectividad_2 = adm_proy.entrega_proyectos_transformadores(lineas_a_agregar(1).entrega_se2(),1);
                    proy.inserta_grupo_proyectos_conectividad(proy_conectividad_1);
                    proy.inserta_grupo_proyectos_conectividad(proy_conectividad_2);
                    
                    adm_proy.agrega_proyecto(proy);
                    proy_excluyentes(end+1) = proy;
                    EstadosConducentes.VU(i).Proyectos = [EstadosConducentes.VU(i).Proyectos; proy];
                    
                    id_estado_final = lineas_a_agregar(1).entrega_id_estado_planificacion();
                    MatrizEstados(id_corr).Estado(lpar,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_corr).Estado(lpar,id_estado_final).ProyectosEntrantes; proy];
                    MatrizEstados(id_corr).Estado(lpar,id_estado_inicial).ProyectosSalientes = [MatrizEstados(id_corr).Estado(lpar,id_estado_inicial).ProyectosSalientes; proy];                    
                end
                % fin de creación de proyectos a partir de los proyectos
                % base. Se agrega set de proyectos excluyentes
                
                if length(proy_excluyentes) > 1
                    adm_proy.agrega_proyectos_excluyentes(proy_excluyentes);
                end                
                
                %2) proyectos de reconductoring (i.e. conductor diferente
                %al conductor base)
                % primero se agregan proyectos "agregar línea". Luego se
                % ven los cambios de estado
                for i = 1:ne_cc
                    proy_excluyentes = cProyectoExpansion.empty;
                    id_cond_inicial = EstadosCC(i);
    
                    if lpar + 1 <= nmax
                        linea = LineasCC(id_corr).Conductor(id_cond_inicial).Linea(lpar+1);
                        proy = crea_proyecto_agrega_linea(linea, 'CC');

                        if ~isempty(EstadosConducentes.CC(i).Proyectos)
                            proy.TieneDependencia = true;
                            proy.inserta_proyectos_dependientes(EstadosConducentes.CC(i).Proyectos);
                        end
                
                        adm_proy.agrega_proyecto(proy);
                        proy_excluyentes(end+1) = proy;
                        EstadosConducentesNuevo.CC(i).Proyectos = proy;

                        id_estado_final = linea.entrega_id_estado_planificacion();
                        MatrizEstados(id_corr).Estado(lpar+1,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_corr).Estado(lpar+1,id_estado_final).ProyectosEntrantes; proy];
                        MatrizEstados(id_corr).Estado(lpar,id_estado_final).ProyectosSalientes = [MatrizEstados(id_corr).Estado(lpar,id_estado_final).ProyectosSalientes; proy];                        
                    end
                    
                    %2) cambios de estado reconductoring. 
                    lineas_a_remover = LineasCC(id_corr).Conductor(id_cond_inicial).Linea(1:lpar);
                    id_estado_inicial = LineasCC(id_corr).Conductor(id_cond_inicial).Linea(1).entrega_id_estado_planificacion();
                    
                    % reconductoring siempre "a la derecha"
                    for j = i + 1:ne_cc
                        if largo > 80
                            %Sólo para líneas cortas
                            continue;
                        end
                        id_cond_final = EstadosCC(j);
                        lineas_a_agregar = LineasCC(id_corr).Conductor(id_cond_final).Linea(1:lpar);
                        proy = crea_proyecto_cambio_estado(lineas_a_remover, lineas_a_agregar, 'CC');
                        if ~isempty(EstadosConducentes.CC(i).Proyectos)
                            proy.TieneDependencia = true;
                            proy.inserta_proyectos_dependientes(EstadosConducentes.CC(i).Proyectos);
                        end
                        
                        adm_proy.agrega_proyecto(proy);
                        proy_excluyentes(end+1) = proy;
                        EstadosConducentes.CC(j).Proyectos = [EstadosConducentes.CC(j).Proyectos; proy];

                        id_estado_final = lineas_a_agregar(1).entrega_id_estado_planificacion();
                        MatrizEstados(id_corr).Estado(lpar,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_corr).Estado(lpar,id_estado_final).ProyectosEntrantes; proy];
                        MatrizEstados(id_corr).Estado(lpar,id_estado_inicial).ProyectosSalientes = [MatrizEstados(id_corr).Estado(lpar,id_estado_inicial).ProyectosSalientes; proy];                    
                    end
                    
                    %3) compensación serie
                    for j = 1:ne_cs
                        id_cond_cs = EstadosCS(j,1);
                        comp = EstadosCS(j,2);
                        if id_cond_inicial ~= id_cond_cs
                            % compensación serie sólo para el mismo conductor
                            continue;
                        end
                        
                        lineas_a_agregar = LineasCS(id_corr).Conductor(id_cond_cs).Compensacion(comp).Linea(1:lpar);
                        proy = crea_proyecto_cambio_estado(lineas_a_remover, lineas_a_agregar, 'CS');
                        if ~isempty(EstadosConducentes.CC(i).Proyectos)
                            proy.TieneDependencia = true;
                            proy.inserta_proyectos_dependientes(EstadosConducentes.CC(i).Proyectos);
                        end
                        adm_proy.agrega_proyecto(proy);
                        proy_excluyentes(end+1) = proy;
                        EstadosConducentes.CS(j).Proyectos = [EstadosConducentes.CS(j).Proyectos; proy];

                        id_estado_final = lineas_a_agregar(1).entrega_id_estado_planificacion();
                        MatrizEstados(id_corr).Estado(lpar,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_corr).Estado(lpar,id_estado_final).ProyectosEntrantes; proy];
                        MatrizEstados(id_corr).Estado(lpar,id_estado_inicial).ProyectosSalientes = [MatrizEstados(id_corr).Estado(lpar,id_estado_inicial).ProyectosSalientes; proy];                    

                    end
                    % fin de estado de reconductoring actual. Se agregan
                    % proyectos excluyentes
                    if length(proy_excluyentes) > 1
                        adm_proy.agrega_proyectos_excluyentes(proy_excluyentes);
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

                        if ~isempty(EstadosConducentes.CS(i).Proyectos)
                            proy.TieneDependencia = true;
                            proy.inserta_proyectos_dependientes(EstadosConducentes.CS(i).Proyectos);
                        end

                        adm_proy.agrega_proyecto(proy);
                        proy_excluyentes(end+1) = proy;
                        EstadosConducentesNuevo.CS(i).Proyectos = proy;

                        id_estado_final = linea.entrega_id_estado_planificacion();
                        MatrizEstados(id_corr).Estado(lpar+1,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_corr).Estado(lpar+1,id_estado_final).ProyectosEntrantes; proy];
                        MatrizEstados(id_corr).Estado(lpar,id_estado_final).ProyectosSalientes = [MatrizEstados(id_corr).Estado(lpar,id_estado_final).ProyectosSalientes; proy];                        
                    end
                    % proyectos de cambio de estado. En este caso, sólo
                    % agregar nueva compensación en serie para un mismo
                    % conductor
                    lineas_a_remover =  LineasCS(id_corr).Conductor(id_cond_inicial).Compensacion(comp_inicial).Linea(1:lpar);
                    id_estado_inicial = lineas_a_remover(1).entrega_id_estado_planificacion();
                    
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
                        if ~isempty(EstadosConducentes.CS(i).Proyectos)
                            proy.TieneDependencia = true;
                            proy.inserta_proyectos_dependientes(EstadosConducentes.CS(i).Proyectos);
                        end
                        adm_proy.agrega_proyecto(proy);
                        proy_excluyentes(end+1) = proy;
                        EstadosConducentes.CS(j).Proyectos = [EstadosConducentes.CS(j).Proyectos; proy];

                        id_estado_final = lineas_a_agregar(1).entrega_id_estado_planificacion();
                        MatrizEstados(id_corr).Estado(lpar,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_corr).Estado(lpar,id_estado_final).ProyectosEntrantes; proy];
                        MatrizEstados(id_corr).Estado(lpar,id_estado_inicial).ProyectosSalientes = [MatrizEstados(id_corr).Estado(lpar,id_estado_inicial).ProyectosSalientes; proy];                    
                    end
                    % fin de cambio de estado para CS actual. Se agregan
                    % proyectos excluyentes
                    if length(proy_excluyentes) > 1
                        adm_proy.agrega_proyectos_excluyentes(proy_excluyentes);
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
                        linea = LineasVU(id_corr).VUR(vur).Conductor(id_cond).Linea(lpar+1);
                        proy = crea_proyecto_agrega_linea(linea, 'AV');
                        if ~isempty(EstadosConducentes.VU(i).Proyectos)
                            proy.TieneDependencia = true;
                            proy.inserta_proyectos_dependientes(EstadosConducentes.VU(i).Proyectos);
                        end
                        adm_proy.agrega_proyecto(proy);
                        EstadosConducentesNuevo.VU(i).Proyectos = proy;

                        id_estado_final = linea.entrega_id_estado_planificacion();
                        MatrizEstados(id_corr).Estado(lpar+1,id_estado_final).ProyectosEntrantes = [MatrizEstados(id_corr).Estado(lpar+1,id_estado_final).ProyectosEntrantes; proy];
                        MatrizEstados(id_corr).Estado(lpar,id_estado_final).ProyectosSalientes = [MatrizEstados(id_corr).Estado(lpar,id_estado_final).ProyectosSalientes; proy];                        
                    end
                end
            end
        end
    end
    adm_proy.inserta_matriz_estados_corredores(MatrizEstados);
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
    linea.agrega_subestacion(se1, 1);
    linea.agrega_subestacion(se2,2);
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
    factor_capacidad = min(3, factor_capacidad);
    sr = factor_capacidad*SIL;
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

function se_vur = crea_nueva_subestacion(se_base, voltaje, costo, adm_proy)
	ubicacion = se_base.entrega_ubicacion();
	[posx, posy] = se_base.entrega_posicion();
    id_nombre = se_base.entrega_id();
    id_se = adm_proy.entrega_cantidad_buses()+1;
    se_vur = cSubestacion();
    se_vur.inserta_nombre(strcat('SE_',num2str(id_nombre), '_VU_', num2str(voltaje)));
    se_vur.inserta_vn(voltaje);
    se_vur.inserta_posicion(posx, posy);
    se_vur.inserta_id(id_se);                    
    se_vur.inserta_ubicacion(ubicacion);
    se_vur.inserta_costo(costo);
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
        % costos de aumento de voltaje son 20% de costo de línea más los
        % costos de los transformadores y subestaciones. Estos últimos sin
        % embargo no se consideran en este proyecto, sino que en proyecto independiente 
        proy.inserta_capacidad_inicial(['V_' num2str(vinicial)]);
        proy.inserta_capacidad_final(['V_' num2str(vfinal)]);
        nombre = ['Aumento voltaje lineas L1 a ' num2str(length(lineas_a_remover)) ' de V_' num2str(vinicial) ' a V_' num2str(vfinal) ...
            ' entre buses originales ' lineas_a_remover(1).entrega_se1().entrega_nombre() ' y ' lineas_a_remover(1).entrega_se2().entrega_nombre()]; 
        proy.inserta_nombre(nombre);
        costo_row_inicial = lineas_a_remover(1).entrega_costo_servidumbre();
        costo_row_final = lineas_a_agregar(1).entrega_costo_servidumbre();
        costo_linea_nueva = (lineas_a_agregar(1).entrega_costo_conductor()+lineas_a_agregar(1).entrega_costo_torre())*1.05;
        
        tipo_cond_inicial = lineas_a_remover(1).entrega_tipo_conductor();
        tipo_cond_final = lineas_a_agregar(1).entrega_tipo_conductor();
        if tipo_cond_inicial == tipo_cond_final
            proy.inserta_cambio_conductor_aumento_voltaje(false);
            proy.inserta_costo_inversion(0.2*costo_linea_nueva);
        else
            % TODO. Hay que revisar este caso. Por ahora no se da
            proy.inserta_cambio_conductor_aumento_voltaje(true);
            for ii = 1:length(lineas_a_agregar)
                % si VU se realiza con el mismo conductor, entonces los costos
                % son cero
                costo_inv = costo_inv + lineas_a_agregar(ii).entrega_costo_conductor() ...
                    + costo_row_inicial- costo_row_final;
                proy.inserta_costo_inversion(costo_inv);
            end
        end
    else
        error = MException('cimporta_problema_optimizacion_tnep:crea_proyecto_cambio_estado','caso no existe');
        throw(error)
    end        
end

function trafo = crea_transformador(TipoTrafo, se_at, se_bt, lpar)
	vat = se_at.entrega_vn();
    vbt = se_bt.entrega_vn();
	sr = TipoTrafo(2);
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

function genera_restricciones_conectividad_se_nuevas(adm_proy)
	for i= 1:length(adm_proy.Proyectos)
        if strcmp(adm_proy.Proyectos(i).entrega_tipo_proyecto(),'AS')
            proy = adm_proy.Proyectos(i);
            se = proy.Elemento(1);
            proyectos_conectividad = cProyectoExpansion.empty;
            for j = 1:length(adm_proy.Proyectos)
                if strcmp(adm_proy.Proyectos(j).entrega_tipo_proyecto(),'AL')
                    el_red = adm_proy.Proyectos(j).Elemento(end);
                    if el_red.entrega_se1() == se || el_red.entrega_se2() == se 
                        % proyecto conecta la subestación
                        proyectos_conectividad = [proyectos_conectividad; adm_proy.Proyectos(j)];
                    end
                end
            end
            proy.TieneRequisitosConectividad = true;
            proy.inserta_grupo_proyectos_conectividad(proyectos_conectividad);
        end
	end
end
