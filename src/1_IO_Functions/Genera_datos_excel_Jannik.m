%Esta es la que importa datos desde excel al programa
function data = Genera_datos_excel_Jannik(id_punto_operacion)
    nombre_sistema = './input/Data_Chile/ChilePELP.xlsx';
    
    filename = nombre_sistema;
    data = crea_contenedores();

    data = importa_costos_globales(filename, data);
    data = importa_buses(filename, data);
    data = importa_demanda(filename, data);
    data = importa_generadores(filename, data);
    
    data = importa_lineas_transmision(filename, data);
    data = importa_conductores_ur(filename, data);
    data = importa_transformadores(filename, data);
    data = importa_transformadores_vu(filename, data);
    data = importa_compensacion_serie(filename, data);
    data = importa_baterias(filename, data);
    data = importa_tecnologias_bateria(filename, data);
    data = importa_puntos_operacion(filename, data, id_punto_operacion);
    data = importa_escenarios(filename, data);
    data = importa_perfil_ernc(filename, data);
    data = importa_perfil_afluente(filename, data);
    data = importa_perfil_vertimiento(filename, data);
    data = importa_perfil_demanda(filename, data);
    data = importa_evolucion_capacidad_generadores(filename, data);
    data = importa_datos_embalse(filename, data);
    data = importa_datos_hidro(filename, data);
end

function [po_desde, po_hasta] = entrega_puntos_operacion(base, tipo_po)
    if tipo_po == 2
        % d�as representativos
        po_desde = 1+(base-1)*24;
        po_hasta = base*24;
    elseif tipo_po == 3
        % semanas representativas
        po_desde = 1+(base-1)*168;
        po_hasta = base*168;
    else
        %a�o completo
        po_desde = 1;
        po_hasta = 8760;
    end 
end
function data = crea_contenedores()
    sbase = 100; %MVA
    data.baseMVA = sbase;

    data.Buses = [];
    data.Consumos = [];
    data.Generadores = [];
    data.Hidro = [];
    data.Corredores = [];
    data.Lineas = [];
    data.Transformadores = [];
    data.TipoTransformadores = [];
    data.PuntosOperacion = [];
    data.SeriesERNC = [];
    data.Afluentes = [];
    data.Vertimientos = [];
    data.SeriesConsumo = [];
    data.Baterias = [];
    data.TecnologiaBaterias = [];
    data.Embalses = [];
end

function data = importa_costos_globales(filename, data)
    num = xlsread(filename, 'CostAssumptions');
    inicio = 1;
    while isnan(num(inicio,1))
        inicio = inicio + 1;
    end    
    fila = inicio;
    data.Costos(1,1) = num(fila, 1); %ROW USD/Ha
    data.Costos(1,2) = num(fila, 2);  % factor desarrollo proyectos
    data.CostoSubestacion = num(fila, 3);
end

function data = importa_buses(filename, data)    
    num = xlsread(filename, 'Buses');
    inicio = 1;
    while isnan(num(inicio,1))
        inicio = inicio + 1;
    end    
    [n, ~] = size(num);
    contador_buses = 1;
    for fila = inicio:n
        if num(fila,1) == contador_buses
            data.Buses(contador_buses, 1) = contador_buses;
            data.Buses(contador_buses, 2) = num(fila,2); % voltaje kV
            data.Buses(contador_buses, 3) = num(fila,3);  % existente 
            data.Buses(contador_buses, 4) = num(fila,4); % vmax pu
            data.Buses(contador_buses, 5) = num(fila,5); % vmin pu
            %Cuando coloca 0 es que no esta considerando esa fila ni ese
            %dato.
            data.Buses(contador_buses, 6) = 0; % conectividad (se ve despu�s)
            data.Buses(contador_buses, 7) = 0; % posX
			data.Buses(contador_buses, 8) = 0; % posY
            data.Buses(contador_buses, 9) = 0; % Cantidad m�xima de Bater�as
            data.Buses(contador_buses, 10) = 0; % Cantidad m�xima de compensaci�n reactiva
            contador_buses = contador_buses+1;
        else
            error= MException('genera_datos_excel_generico:importa_buses','datos en buses no son secuenciales');
            throw(error)
        end
    end
end

function data = importa_demanda(filename, data)
    num = xlsread(filename, 'Demands');
    inicio = 1;
    while isnan(num(inicio,1))
        inicio = inicio + 1;
    end    
    [n, ~] = size(num);
    contador_consumo = 0;
    for fila = inicio:n
        contador_consumo = contador_consumo + 1;
        data.Consumos(contador_consumo, 1) = num(fila, 1); % bus
        data.Consumos(contador_consumo, 2) = num(fila, 3); % Pmax
        data.Consumos(contador_consumo, 3) = num(fila, 3); % Qmax
        data.Consumos(contador_consumo, 4) = num(fila, 4); %Existente
        data.Consumos(contador_consumo, 5) = num(fila, 5); % %costos NLSC
        data.Consumos(contador_consumo, 6) = num(fila, 6); % id perfil 
        data.Consumos(contador_consumo, 7) = num(fila, 7); % tipo evolucion capacidad (0: fija; 1: porcentaje fijo; 2: porcentaje variable por anio)
        data.Consumos(contador_consumo, 8) = num(fila, 8); % valor evolucion (depende de tipo de evolucion)		
    end
end

function data = importa_generadores(filename, data)%EL perfil se multiplca por la potencia m�xima
    num = xlsread(filename, 'Generators');    
    inicio = 1;
    while isnan(num(inicio,1))
        inicio = inicio + 1;
    end    
    contador_generadores = 0;
    [n, ~] = size(num);
    for fila = inicio:n
		contador_generadores = contador_generadores + 1;
        id_gen = num(fila,1);
        bus_gen = num(fila,2);
        
		data.Generadores(contador_generadores, 1) = id_gen; % Id
		data.Generadores(contador_generadores, 2) = bus_gen; %Bus
		data.Generadores(contador_generadores, 3) = num(fila,9); %P0
		data.Generadores(contador_generadores, 4) = 0; %Q0, no toma en consideraci�n 
		data.Generadores(contador_generadores, 5) = num(fila,9); %Pmax
		data.Generadores(contador_generadores, 6) = num(fila,10); %Pmin
		data.Generadores(contador_generadores, 7) = num(fila,11); %Qmax
		data.Generadores(contador_generadores, 8) = 0; %Qmin
		data.Generadores(contador_generadores, 9) = 1; %Vobj pu
		data.Generadores(contador_generadores, 10) = num(fila,21); % existente o proyectado
		data.Generadores(contador_generadores, 11) = num(fila,19); % slack
		data.Generadores(contador_generadores, 12) = num(fila,7)/10000; %costos generaci�n
        data.Generadores(contador_generadores, 13) = num(fila,20); % tipo: 0: convencional, 1: e�lico, 2: solar
        data.Generadores(contador_generadores, 14) = num(fila,22); % evolucion capacidad (si/no)
        data.Generadores(contador_generadores, 15) = num(fila,23); % evolucion costos (si/no)
        data.Generadores(contador_generadores, 16) = num(fila,24); % Perfil ERNCdata
        data.Generadores(contador_generadores, 17) = num(fila,25); %Eficiencia
        % falta eficiencia
        
        % por ahora s�lo estos datos de los generadores
    end
end





function data = importa_lineas_transmision(filename, data)
    sbase = data.baseMVA;
    num = xlsread(filename, 'Transmission_Lines_Data');
    inicio = 1;
    while isnan(num(inicio,1))
        inicio = inicio + 1;
    end    
    [n, ~] = size(num);
    contador_corredores = 0;
    contador_conductores = 0;
    contador_lineas = 0;
    for fila = inicio:n
        id_linea_orig = num(fila, 1);
        bus_inicio = num(fila, 2);
        bus_fin = num(fila, 3);
        if num(fila, 4) == 0 && num(fila, 9) == 0
            continue;
        end
        corredor_incorporado = false;
        if contador_corredores > 0
            indice = ismember(data.Corredores(:,1:2), [bus_inicio bus_fin],'rows');
            
            if  sum(indice) == 1
                id_corredor_incorporado = find(indice == 1);
                corredor_incorporado = true;
            end
        end
        if ~corredor_incorporado
            contador_corredores = contador_corredores + 1;
        end
        lpar = num(fila, 4);
        rpu = num(fila, 5);
        xpu = num(fila, 6);
        bpu = num(fila, 7);
        sr = num(fila, 8);
        expansion = num(fila, 9);%�Qu� significa aqu� el n�mero de expansi�n? Ahora esta en 3
        largo = num(fila, 10);
        cinv = num(fila, 11); % en MM USD
        vnom = num(fila, 12);
        cantidad_vu = num(fila, 13);
        cantidad_cs = num(fila, 14);%�Qu� es esto?
        cantidad_cc = num(fila, 15);%�Qu� es esto?
        anio_construccion = num(fila, 16);
        if ~corredor_incorporado
            data.Corredores(contador_corredores, 1) = bus_inicio;
            data.Corredores(contador_corredores, 2) = bus_fin;
            data.Corredores(contador_corredores, 3) = largo;
            if lpar > 0
                data.Corredores(contador_corredores, 4) = 1 + expansion;
            else
                data.Corredores(contador_corredores, 4) = expansion;
            end
            % valores para vu, sc, cc
            data.Corredores(contador_corredores, 5) = cantidad_vu; % vu
            data.Corredores(contador_corredores, 6) = cantidad_cs; % sc
            data.Corredores(contador_corredores, 7) = cantidad_cc; % cc

        else % corredor ya fue incorporado
            if lpar > 0
                data.Corredores(id_corredor_incorporado, 4) = data.Corredores(id_corredor_incorporado, 4) + 1 + expansion;
            else
                data.Corredores(id_corredor_incorporado, 4) = data.Corredores(id_corredor_incorporado, 4) + expansion;                    
            end
        end
        
        % crea linea
        zbase = vnom^2/sbase;
        r_ohm_km = rpu*zbase/largo;
        x_ohm_km = xpu*zbase/largo;
        c_uF_km = bpu/(2 *pi *50)*1000000/zbase/largo;
        %b = this.Largo * this.Cpul * 2 *pi *50 / 1000000;
        %Cpul = 0 % uF/km
        %Gpul = 0 % mS/Km
        imax = sr/(sqrt(3)*vnom);
        if fila > inicio
            id_conductor = find(ismember(data.Conductores(:,3:7), [r_ohm_km x_ohm_km 0 c_uF_km imax], 'rows'),1,'first');
        else
            id_conductor = [];
        end
        if isempty(id_conductor)
            contador_conductores = contador_conductores + 1;
            data.Conductores(contador_conductores, 1) = contador_conductores;
            data.Conductores(contador_conductores, 2) = 1;
            data.Conductores(contador_conductores, 3) = r_ohm_km;
            data.Conductores(contador_conductores, 4) = x_ohm_km;
            data.Conductores(contador_conductores, 5) = 0;
            data.Conductores(contador_conductores, 6) = c_uF_km;
            data.Conductores(contador_conductores, 7) = imax;
            
            cvar_conductor = cinv*0.4/largo/sr;
            cvar_torre = cinv*0.6/largo/sr;
            
            data.Conductores(contador_conductores, 8) = 0;
            data.Conductores(contador_conductores, 9) = cvar_conductor;
            data.Conductores(contador_conductores, 10) = cvar_torre;
            data.Conductores(contador_conductores, 11) = 40;
            data.Conductores(contador_conductores, 12) = vnom;
            if vnom <= 220
                data.Conductores(contador_conductores, 13) = 3.3528;
                data.Conductores(contador_conductores, 14) = 18.2;
            elseif vnom < 500
                data.Conductores(contador_conductores, 13) = 4.2672;
                data.Conductores(contador_conductores, 14) = 39.2;
            else
                data.Conductores(contador_conductores, 13) = 5.3645;                
                data.Conductores(contador_conductores, 14) = 39.2;
            end
            data.Conductores(contador_conductores, 15) = 0;  % este parametro es solo para conductores nuevos
            id_conductor = contador_conductores;
            
        end
        
        cantidad_lineas_existentes = lpar > 0;
        cantidad_lineas_nuevas = expansion;
        for linea_nueva = 1:cantidad_lineas_existentes + cantidad_lineas_nuevas
            contador_lineas = contador_lineas + 1;
            data.Lineas(contador_lineas, 1) = bus_inicio;
            data.Lineas(contador_lineas, 2) = bus_fin;
            data.Lineas(contador_lineas, 3) = rpu;
            data.Lineas(contador_lineas, 4) = xpu;
            data.Lineas(contador_lineas, 5) = bpu;
            data.Lineas(contador_lineas, 6) = sr;
            if linea_nueva <= cantidad_lineas_existentes
                data.Lineas(contador_lineas, 7) = 1; %status
                data.Lineas(contador_lineas, 10) = anio_construccion; %a�o construcci�n
            else
                data.Lineas(contador_lineas, 7) = 0; %status
                data.Lineas(contador_lineas, 10) = 0; %a�o construcci�n
            end
            data.Lineas(contador_lineas, 8) = cinv;
            data.Lineas(contador_lineas, 9) = id_conductor;
            data.Lineas(contador_lineas, 11) = id_linea_orig;
        end
    end
end

function data = importa_conductores_ur(filename, data)
    [~,AvailableSheets] = xlsfinfo(filename);
    sheetValid = any(strcmp(AvailableSheets, 'ConductorsUR'));
    if sheetValid
        num = xlsread(filename, 'ConductorsUR');
        inicio = 1;
        while isnan(num(inicio,1))
            inicio = inicio + 1;
        end
        [n, ~] = size(num);
        id_cond_ur = 900;
        cant_cond_ur = 0;
        Conductores_HTLS_VU = [];
        for fila = inicio:n
            if num(fila, 15) > 0
                id_cond_ur = id_cond_ur + 1;
                cant_cond_ur = cant_cond_ur + 1;
                Conductores_HTLS_VU(cant_cond_ur, 1) = id_cond_ur;
                for j = 2:15
                    Conductores_HTLS_VU(cant_cond_ur, j) = num(fila, j);
                end
            end
        end
        data.Conductores = [data.Conductores; Conductores_HTLS_VU];        
    end
end

function data = importa_transformadores(filename, data)
    [~,AvailableSheets] = xlsfinfo(filename);
    sheetValid = any(strcmp(AvailableSheets, 'Transformers'));
    if sheetValid
        num = xlsread(filename, 'Transformers');
        inicio = 1;
        while isnan(num(inicio,1))
            inicio = inicio + 1;
        end
        [n, ~] = size(num);
        contador_trafos = 0;
        contador_tipo_trafo= 0;
        [contador_corredores, ~] = size(data.Corredores);
        %contador_corredores=0;
        for fila = inicio:n
            id_linea_orig = num(fila, 1);
            bus_inicio = num(fila, 2);
            bus_fin = num(fila, 3);
            sr = num(fila, 4);
            v_at = num(fila, 5);
            v_bt = num(fila, 6);
            x_ohm = num(fila,7);
            cinv = num(fila, 8)/1000000; % en MM USD
            lpar = num(fila, 9);
            expansion = num(fila,10); 
            anio_construccion = num(fila, 11);
            id_corredor = find(ismember(data.Corredores(:,1:2), [bus_inicio bus_fin], 'rows'),1,'first');
            if ~isempty(id_corredor)
                error= MException('genera_datos_excel_generico:importa_transformadores','datos en transformadores incorrectos. Corredor ya se encuentra');
                throw(error)
            end
            contador_corredores = contador_corredores + 1;
            data.Corredores(contador_corredores, 1) = bus_inicio;
            data.Corredores(contador_corredores, 2) = bus_fin;
            data.Corredores(contador_corredores, 3) = 0;
            if lpar > 0
                data.Corredores(contador_corredores, 4) = 1 + expansion;
            else
                data.Corredores(contador_corredores, 4) = expansion;
            end

            if fila > inicio
                id_tipo_trafo = find(ismember(data.TipoTransformadores(:,2:5), [sr v_at v_bt x_ohm], 'rows'),1,'first');
            else
                id_tipo_trafo = [];
            end
            if isempty(id_tipo_trafo)
                contador_tipo_trafo = contador_tipo_trafo + 1;
                data.TipoTransformadores(contador_tipo_trafo, 1) = contador_tipo_trafo;
                data.TipoTransformadores(contador_tipo_trafo, 2) = sr;
                data.TipoTransformadores(contador_tipo_trafo, 3) = v_at;
                data.TipoTransformadores(contador_tipo_trafo, 4) = v_bt;
                data.TipoTransformadores(contador_tipo_trafo, 5) = x_ohm;
                data.TipoTransformadores(contador_tipo_trafo, 6) = 0;

                %data.TipoTransformadores(contador_tipo_trafo, 7) = 0.01035; %10350 USD/MVA para trafos 115/345
                data.TipoTransformadores(contador_tipo_trafo, 7) = cinv/sr;
                data.TipoTransformadores(contador_tipo_trafo, 8) = 40;
                id_tipo_trafo = contador_tipo_trafo;

                if sum(sum(ismember(data.TipoTransformadores(:,3:4), [v_at v_bt]))) == 2
                    data.TipoTransformadores(contador_tipo_trafo, 9) = 1;
                else
                    data.TipoTransformadores(contador_tipo_trafo, 9) = 0;
                end
            end
            cantidad_trafos_existentes = lpar > 0;
            cantidad_trafos_nuevos = expansion;
            for trafo = 1:cantidad_trafos_existentes + cantidad_trafos_nuevos
                contador_trafos = contador_trafos + 1;
                data.Transformadores(contador_trafos, 1) = bus_inicio;
                data.Transformadores(contador_trafos, 2) = bus_fin;
                data.Transformadores(contador_trafos, 3) = x_ohm;
                data.Transformadores(contador_trafos, 4) = sr;
                data.Transformadores(contador_trafos, 5) = id_tipo_trafo;
                data.Transformadores(contador_trafos, 6) = 10350*sr/1000000; %cinv. en MMUSD
                if trafo <= cantidad_trafos_existentes
                    data.Transformadores(contador_trafos, 7) = anio_construccion; %a�o construcci�n
                else
                    data.Transformadores(contador_trafos, 7) = 0; %a�o construcci�n
                end 
                data.Transformadores(contador_trafos, 8) = id_linea_orig;
            end
        end
    end
end

function data = importa_transformadores_vu(filename, data)
    % Voltage uprating
    [~,AvailableSheets] = xlsfinfo(filename);
    sheetValid = any(strcmp(AvailableSheets, 'TransformersVU'));
    if sheetValid
        num = xlsread(filename, 'TransformersVU');
        inicio = 1;
        while isnan(num(inicio,1))
            inicio = inicio + 1;
        end    
        [n, ~] = size(num);
        contador_vu = 0;
        contador_trafos_vu = 0;
        data.VoltageUprating = [];
        data.TransformadoresVU = [];
        for fila = inicio:n
            if num(fila, 9) > 0
                sr = num(fila, 2);
                v_at = num(fila, 3);
                v_bt = num(fila, 4);
                x_ohm = num(fila, 5);
                cfijo = num(fila, 6);
                cvar = num(fila, 7);
                vida_util = num(fila, 8);

                % Voltajes para VU
                if contador_vu > 0
                    id_tipo_vu = find(ismember(data.VoltageUprating(:,2), v_at, 'rows'),1,'first');
                else
                    id_tipo_vu = [];
                end
                if isempty(id_tipo_vu)
                    contador_vu = contador_vu + 1; 
                    data.VoltageUprating(contador_vu, :) = [contador_vu v_at data.CostoSubestacion 0]; %ultimo valor son costos variables de SE. Son cero
                end

                % Trafos para VU
                if contador_trafos_vu > 0
                    id_trafo_vu = find(ismember(data.TransformadoresVU(:,2:5), [sr v_at v_bt x_ohm], 'rows'),1,'first');
                else
                    id_trafo_vu = [];
                end

                if isempty(id_trafo_vu)
                    contador_trafos_vu = contador_trafos_vu + 1;
                    data.TransformadoresVU(contador_trafos_vu,:) = [contador_trafos_vu sr v_at v_bt x_ohm cfijo cvar vida_util];
                end
            end
        end
    else
        data.VoltageUprating = [];
        data.TransformadoresVU = [];        
    end
end

function data = importa_compensacion_serie(filename, data)
    % Compensaci�n serie
    [~,AvailableSheets] = xlsfinfo(filename);
    sheetValid = any(strcmp(AvailableSheets, 'SeriesCompensation'));
    if sheetValid
        num = xlsread(filename, 'SeriesCompensation');
        inicio = 1;
        while isnan(num(inicio,1))
            inicio = inicio + 1;
        end    
        [n, ~] = size(num);
        contador_cs = 0;
        for fila = inicio:n
            if num(fila, 5) > 0
                contador_cs = contador_cs + 1;
                data.CompensacionSerie (contador_cs, 1) = contador_cs; % nro.
                data.CompensacionSerie(contador_cs, 2) = num(fila, 2); % % compensaci�n
                data.CompensacionSerie(contador_cs, 3) = num(fila, 3); % Cfijo
                data.CompensacionSerie(contador_cs, 4) = num(fila, 4); % Cvar (M$/MVAr(
            end
        end
    else
        data.CompensacionSerie = [];
    end
end

function data = importa_baterias(filename, data)
    % Bater�as    
    [~,AvailableSheets] = xlsfinfo(filename);
    sheetValid = any(strcmp(AvailableSheets, 'Storage_Data'));
    %la funci�n any retorna un true si no hay zeros o l
    %la funci�n strcmp sirve para comparar dos strings
    if sheetValid
        num = xlsread(filename, 'Storage_Data');
        inicio = 1;
        while isnan(num(inicio,1))
            inicio = inicio + 1;
        end
        cant_bat = 0;
        cant_tecnologias = 0;
        [n, ~] = size(num);
        for fila = inicio:n
            id_bus = num(fila, 1);
            if num(fila, 2) > 0 % Existen bater�as en sistema inicial
                cant_bat = cant_bat +1;
                pmax = num(fila, 4);
                emax = num(fila, 5);
                cinv_potencia = num(fila, 6);
                cinv_capacidad = num(fila, 7);
                vida_util = num(fila, 8);
                anio_construccion = num(fila, 9);
                E_min = num(fila,10);
                eta_car = num(fila, 11);
                eta_descar = num(fila, 12);
                
                data.Baterias(cant_bat, 1) = id_bus; %id bus
                data.Baterias(cant_bat, 2) = num(fila, 2); % cant. bater�as existentes
                data.Baterias(cant_bat, 3) = pmax;
                data.Baterias(cant_bat, 4) = emax; 
                data.Baterias(cant_bat, 5) = cinv_potencia;
                data.Baterias(cant_bat, 6) = cinv_capacidad;
                data.Baterias(cant_bat, 7) = vida_util; 
                data.Baterias(cant_bat, 8) = anio_construccion;
                data.Baterias(cant_bat, 9) = E_min;
                data.Baterias(cant_bat, 10) = eta_car;
                data.Baterias(cant_bat, 11) = eta_descar;

                % verifica si tecnolog�a de la bater�a existe
                tecnologia_incorporada = false;
                if cant_tecnologias > 0
                    indice = ismember(data.TecnologiaBaterias(:,1:5), [pmax emax cinv_potencia cinv_capacidad vida_util],'rows');
                    if  sum(indice) == 1
                        tecnologia_incorporada = true;
                    end
                end
                if ~tecnologia_incorporada
                    cant_tecnologias = cant_tecnologias + 1;
                    data.Tecnologias(cant_tecnologias,1) = pmax;
                    data.TecnologiaBaterias(cant_tecnologias,2) = emax;
                    data.TecnologiaBaterias(cant_tecnologias,3) = cinv_potencia;
                    data.TecnologiaBaterias(cant_tecnologias,4) = cinv_capacidad;
                    data.TecnologiaBaterias(cant_tecnologias,5) = vida_util;
                    data.TecnologiaBaterias(cant_tecnologias,6) = E_min;
                end
            end
            if num(fila, 3) > 0
                % expansi�n. Indica cantidad m�xima de bater�as
                data.Buses(id_bus, 9) = num(fila, 3); % Cantidad m�xima de Bater�as
            end
        end
    else
        data.Baterias = [];
        data.TecnologiaBaterias = [];
    end
end

function data = importa_tecnologias_bateria(filename, data)
    % tecnolog�as de baterias
    [~,AvailableSheets] = xlsfinfo(filename);
    sheetValid = any(strcmp(AvailableSheets, 'Storage_Tech'));
    %Aqu� compara si hay alg�na hoja disponible llamada "storage tech" y
    %que no contenga ceros.
    if sheetValid
        num = xlsread(filename, 'Storage_Tech');
        inicio = 1;
        while isnan(num(inicio,1))
            inicio = inicio + 1;
        end
        [cant_tecnologias,~] = size(data.TecnologiaBaterias);
        [n, ~] = size(num);
        for fila = inicio:n
            emax = num(fila, 2);
            pmax = num(fila, 3);
            c_inv_potencia = num(fila, 4);
            c_inv_capacidad = num(fila, 5);
            vida_util = num(fila, 6);
            % verifica si tecnolog�a de la bater�a existe.  
            %Esta parte nunca funciona, o si?
            tecnologia_incorporada = false;
            if cant_tecnologias > 0
                indice = ismember(data.TecnologiaBaterias(:,1:5), [pmax emax c_inv_potencia c_inv_capacidad vida_util],'rows');
                %Antes el "indice" ten�a (:,2:6)
                if  sum(indice) == 1
                    tecnologia_incorporada = true;
                end
            end
            if ~tecnologia_incorporada
                cant_tecnologias = cant_tecnologias + 1;
                data.TecnologiaBaterias(cant_tecnologias,1) = cant_tecnologias;
                data.TecnologiaBaterias(cant_tecnologias,2) = pmax;
                data.TecnologiaBaterias(cant_tecnologias,3) = emax;
                data.TecnologiaBaterias(cant_tecnologias,4) = c_inv_potencia;
                data.TecnologiaBaterias(cant_tecnologias,5) = c_inv_capacidad;
                data.TecnologiaBaterias(cant_tecnologias,6) = vida_util;
            end
        end
    end
end

function data = importa_puntos_operacion(filename, data, id_punto_operacion)
    %data.PuntosOperacion = [PO1 weigth1; PO2 weigth2; ...]
    num = xlsread(filename, 'Operating_points');
    inicio = 1;
    while isnan(num(inicio,1))
        inicio = inicio + 1;
    end    
    [n, ~] = size(num);
    % identifica punto de operacion correspondiente
    fila_po = 0;
    for fila = inicio:n
        if num(fila,1) == id_punto_operacion
            fila_po = fila;
            break;
        end
    end
    if fila_po == 0
        %error = MException('genera_datos_ieee_bus_118_ernc:genera_datos','Punto de operacion indicado no existe');
        %throw(error)
        error = MException('genera_datos_excel_generico:importa_puntos_operacion','Punto de operacion indicado no existe');
        throw(error)
    end
    tipo_po = num(fila_po,2);
    
    col = 3;
    cantidad_po = 0;
    [~, cant_col] = size(num);
    data.IndicesPOConsecutivos = [];
    if tipo_po == 1
        while ~isnan(num(fila_po,col))
            cantidad_po = cantidad_po + 1;
            % OJO AQU�, CAMBIE A +2 EL LADO DEL PESO
            data.PuntosOperacion(cantidad_po,1) = num(fila_po,col); %id
            data.PuntosOperacion(cantidad_po,2) = num(fila_po+1,col); %peso
            col = col + 1;
            if col > cant_col
                break;
            end
        end
    else
        cant_indices_po_consecutivos = 0;
        % pueden ser d�as/semanas representativas o el a�o completo
        while ~isnan(num(fila_po,col))
            [po_desde, po_hasta] = entrega_puntos_operacion(num(fila_po,col), tipo_po);
            cant_indices_po_consecutivos = cant_indices_po_consecutivos + 1;
            data.IndicesPOConsecutivos(cant_indices_po_consecutivos, 1) = po_desde;
            data.IndicesPOConsecutivos(cant_indices_po_consecutivos, 2) = po_hasta;
            if tipo_po == 1
                peso = num(fila_po+1,col)/24;
            elseif tipo_po == 2
                peso = num(fila_po+1,col)/168;
            else
                peso = 1/8760;
            end
            for po = po_desde:po_hasta
                cantidad_po = cantidad_po + 1;
                data.PuntosOperacion(cantidad_po,1) = po;
                data.PuntosOperacion(cantidad_po,2) = peso;
            end
            col = col + 1;
            if col > cant_col
                break;
            end
        end
    end
    
end

function data = importa_escenarios(filename, data)
    % Escenarios
    id_escenario = 1;
    % data.Escenarios = [S1 weigth1; S2 weigth2; ...]
    num = xlsread(filename, 'Scenarios');
    inicio = 1;
    while isnan(num(inicio,1))
        inicio = inicio + 1;
    end    
    [n, ~] = size(num);
    % identifica escenario correspondiente
    fila_escenario = 0;
    for fila = inicio:n
        if num(fila,1) == id_escenario
            fila_escenario = fila;
            break;
        end
    end
    if fila_escenario == 0
        %error = MException('genera_datos_ieee_bus_118_ernc:genera_datos','Punto de operacion indicado no existe');
        %throw(error)
        error= MException('genera_datos_excel_generico:importa_escenarios','Escenario indicado no existe');
        throw(error)
    end
    col = 2;
    cantidad_escenarios = 0;
    [~, cant_col] = size(num);
    while ~isnan(num(fila_escenario,col))
        cantidad_escenarios = cantidad_escenarios + 1;
        data.Escenarios(cantidad_escenarios,1) = num(fila_escenario,col); %id
        data.Escenarios(cantidad_escenarios,2) = num(fila_escenario+1,col); %peso
        col = col + 1;
        if col > cant_col
            break;
        end
    end
end

function data = importa_perfil_ernc(filename, data)
%    data.PerfilesERNC = [perfil_id, inyeccion_po1, inyeccion_po2, ...];
    cantidad_po = length(data.PuntosOperacion(:,1));
    num = xlsread(filename, 'ERNC_Profiles');
    inicio = 2;
    while isnan(num(inicio,1))
        inicio = inicio + 2;
    end    
    [n, m] = size(num);
    cant_puntos_operacion_datos = m-1;
    cantidad_perfiles = 0;
    for fila = inicio:n
        cantidad_perfiles = cantidad_perfiles + 1;
%        id_perfil = num(fila,1);
%        data.PerfilesERNC(cantidad_perfiles,1) = id_perfil;
        id_po_actual = 1;
        po_actual = data.PuntosOperacion(id_po_actual,1);
        
        for po = 1:cant_puntos_operacion_datos
            if num(1,po+1) == po_actual
                inyeccion_pu = num(fila,po+1);
                data.PerfilesERNC(cantidad_perfiles,id_po_actual) = inyeccion_pu;
                if id_po_actual == cantidad_po
                    break
                else
                    id_po_actual = id_po_actual + 1;
                    po_actual = data.PuntosOperacion(id_po_actual,1);
                end
            end
        end
    end
end

function data = importa_perfil_afluente(filename, data)
%    data.PerfilesERNC = [perfil_id, inyeccion_po1, inyeccion_po2, ...];
    cantidad_po = length(data.PuntosOperacion(:,1));
    num = xlsread(filename, 'Afluentes');
    inicio = 2;
    while isnan(num(inicio,1))
        inicio = inicio + 2;
    end    
    [n, m] = size(num);
    cant_puntos_operacion_datos = m-1;
    cantidad_perfiles = 0;
    for fila = inicio:n
        cantidad_perfiles = cantidad_perfiles + 1;
%        id_perfil = num(fila,1);
%        data.PerfilesERNC(cantidad_perfiles,1) = id_perfil;
        id_po_actual = 1;
        po_actual = data.PuntosOperacion(id_po_actual,1);
        
        for po = 1:cant_puntos_operacion_datos
            if num(1,po+1) == po_actual
                inyeccion_pu = num(fila,po+1);
                data.Afluentes(cantidad_perfiles,id_po_actual) = inyeccion_pu;
                if id_po_actual == cantidad_po
                    break
                else
                    id_po_actual = id_po_actual + 1;
                    po_actual = data.PuntosOperacion(id_po_actual,1);
                end
            end
        end
    end
end

function data = importa_perfil_vertimiento(filename, data)
%    data.PerfilesERNC = [perfil_id, inyeccion_po1, inyeccion_po2, ...];
    cantidad_po = length(data.PuntosOperacion(:,1));
    num = xlsread(filename, 'Vertimientos');
    inicio = 2;
    while isnan(num(inicio,1))
        inicio = inicio + 2;
    end    
    [n, m] = size(num);
    cant_puntos_operacion_datos = m-1;
    cantidad_perfiles = 0;
    for fila = inicio:n
        cantidad_perfiles = cantidad_perfiles + 1;
%        id_perfil = num(fila,1);
%        data.PerfilesERNC(cantidad_perfiles,1) = id_perfil;
        id_po_actual = 1;
        po_actual = data.PuntosOperacion(id_po_actual,1);
        
        for po = 1:cant_puntos_operacion_datos
            if num(1,po+1) == po_actual
                inyeccion_pu = num(fila,po+1);
                data.Vertimientos(cantidad_perfiles,id_po_actual) = inyeccion_pu;
                if id_po_actual == cantidad_po
                    break
                else
                    id_po_actual = id_po_actual + 1;
                    po_actual = data.PuntosOperacion(id_po_actual,1);
                end
            end
        end
    end
end



function data = importa_perfil_demanda(filename, data)
    cantidad_po = length(data.PuntosOperacion(:,1));
    num = xlsread(filename, 'Demand_Profiles');
    inicio = 2;
    while isnan(num(inicio,1))
        inicio = inicio + 2;
    end    
    [n, m] = size(num);
    cant_puntos_operacion_datos = m-1;
    cantidad_perfiles_demanda = 0;
    for fila = inicio:n
        cantidad_perfiles_demanda = cantidad_perfiles_demanda + 1;
        %id_perfil = num(fila,1);
        %data.PerfilesDemanda(cantidad_perfiles_demanda,1) = id_perfil;
        id_po_actual = 1;
        po_actual = data.PuntosOperacion(id_po_actual,1);
        for po = 1:cant_puntos_operacion_datos
            if num(1,po+1) == po_actual
                perfil_pu = num(fila,po+1);
                data.PerfilesDemanda(cantidad_perfiles_demanda,id_po_actual) = perfil_pu;
                if id_po_actual == cantidad_po
                    break
                else
                    id_po_actual = id_po_actual + 1;
                    po_actual = data.PuntosOperacion(id_po_actual,1);
                end
            end
        end
    end
end

function data = importa_evolucion_capacidad_generadores(filename, data)
    cantidad_etapas = 1;
    num = xlsread(filename, 'Capacity_Evolution_Generators');
    inicio = 1;
    while isnan(num(inicio,1))
        inicio = inicio + 1;
    end    
    [n, m] = size(num);
    cantidad_etapas_datos = m - 2;
    if cantidad_etapas_datos < cantidad_etapas
        error = MException('genera_datos_excel_generico:genera_datos','Cantidad de etapas en datos es menor a cantidad de etapas en par�metros');
        throw(error)
    end
    
    cantidad_evol = 0;
    % data.EvolucionCapacidadGeneradores = [id_gen, escenario, cap. etapa 1, cap. etapa 2, ...]
    for fila = inicio:n
        id_escenario = num(fila,1);
        if ~ismember(id_escenario, data.Escenarios(:,1))
            continue
        end
        
        cantidad_evol = cantidad_evol + 1;
        id_gen = num(fila,2);
        data.EvolucionCapacidadGeneradores(cantidad_evol,1) = id_escenario;
        data.EvolucionCapacidadGeneradores(cantidad_evol,2) = id_gen;
        for etapa = 1:cantidad_etapas
            capacidad = num(fila,etapa+2);
            data.EvolucionCapacidadGeneradores(cantidad_evol,etapa+2) = capacidad;
        end
    end
end

function data = importa_datos_embalse(filename, data)%Aqu� metemos los datos de los embalses
    num = xlsread(filename, 'Embalses');    
    inicio = 1;
    while isnan(num(inicio,1))
        inicio = inicio + 1;
    end    
    contador_generadores = 0;
    [n, ~] = size(num);
    for fila = inicio:n
		contador_generadores = contador_generadores + 1;
        id_gen = num(fila,1);
        Vol_max = num(fila,3);
        
		data.Embalses(contador_generadores, 1) = id_gen; % Id
		data.Embalses(contador_generadores, 2) = Vol_max*1000000; %Volumen m�ximo
		data.Embalses(contador_generadores, 3) = num(fila,4)*1000000; %Volumen m�nimo
		data.Embalses(contador_generadores, 4) = num(fila,5); %Altura
		data.Embalses(contador_generadores, 5) = num(fila,6)*1000000; %Volumen inicial
		data.Embalses(contador_generadores, 6) = num(fila,7);% Id afluente
        data.Embalses(contador_generadores, 7) = num(fila,8);% Id vertimiento obligatorio
        data.Embalses(contador_generadores, 8) = num(fila,9);%id_bus
        data.Embalses(contador_generadores, 9) = num(fila,10);%Eficiencia (en la clase embalse dice que hay que incertar la eficiencia)
		data.Embalses(contador_generadores, 10) = num(fila,11)*1000000; %Volumen final
        data.Embalses(contador_generadores, 11) = num(fila,12); %Porcentaje filtraci�n
    end
end

function data = importa_datos_hidro(filename, data)%Aqu� metemos los datos de las centrales hidro
    num = xlsread(filename, 'Red_hidraulica');    
    inicio = 1;
    while isnan(num(inicio,1))
        inicio = inicio + 1;
    end    
    contador_generadores = 0;
    [n, ~] = size(num);
    for fila = inicio:n
		contador_generadores = contador_generadores + 1;
        id_gen = num(fila,1);
        tipo_tvf = num(fila,2);
        
		data.Hidro(contador_generadores, 1) = id_gen; % Id
		data.Hidro(contador_generadores, 2) = tipo_tvf; %Bus
		data.Hidro(contador_generadores, 3) = num(fila,3); %Embalse inicio
		data.Hidro(contador_generadores, 4) = num(fila,4); %Embalse fin
		data.Hidro(contador_generadores, 5) = num(fila,5); % % de filtraci�n
		data.Hidro(contador_generadores, 6) = num(fila,6);% Eficiencia turbina
		data.Hidro(contador_generadores, 7) = num(fila,7); % Altura embalse
		data.Hidro(contador_generadores, 8) = num(fila,8); %Potencia m�xima turbina
		data.Hidro(contador_generadores, 9) = num(fila,9); %Potencia m�nima de turbina
	    data.Hidro(contador_generadores, 10) = num(fila,10)*1000000; %Flujo m�nimo de salida
        data.Hidro(contador_generadores, 11) = num(fila,11); %Flujo m�ximo de salida
        data.Hidro(contador_generadores, 12) = num(fila,12)*1000000; %Vol. Max
        data.Hidro(contador_generadores, 13) = num(fila,13)*1000000; %Vol. M�n
        data.Hidro(contador_generadores, 14) = num(fila,14); %Id. afluente
        data.Hidro(contador_generadores, 15) = num(fila,15); %Bus
        data.Hidro(contador_generadores, 16) = num(fila,16)*1000000; %Vol. Inicial
        data.Hidro(contador_generadores, 17) = num(fila,17)*1000000; %Vol. Final
        
    end
end
