function data = genera_datos_ieee_bus_118_ernc(parametros)
    nombre_sistema = parametros.NombreSistema;
    id_punto_operacion = parametros.IdPuntosOperacion;
    id_escenario = parametros.IdEscenario;
    cantidad_etapas = parametros.CantidadEtapas;
    filename = nombre_sistema;
    
    anio_construccion = 1990;
    sbase = 100; %MVA
    data.baseMVA = 100;
    % datos a agregar al final
    % Costos en USD/MW-km
    % caso 2: 1800 y 1100 USD/MW-km 
	Conductores_HTLS_VU = [
    %[  1,  2,      3, 			4			5			6			7			8				9				10				11			12		13			14 				15 expansion
    %[no,   tipo,   r (Ohm/km), x (Ohm/km), G (Ohm/km) 	C (Ohm/km), Imax (kA) 	Cfijo cond		Cvar. cond		Cvar. torre 	vida_util  	Vnom 	ROW [Ha/km] diametro (mm)	1/0
    %      2:HTLS
        998	1       0.021       0.242       0			0.00554 	0.83674     0				0.00044         0.00066         40			345		4.2672		39.2			1;
        999	2       0.1684      0.2612      0			0.00550     1.332       0				0.00052767      0.000890449     40			138		3.3528		18.2			1;	
    ];


    % caso 2: 650 y 250 USD/MW-km 
% 	Conductores_HTLS_VU = [
%     %[  1,  2,      3, 			4			5			6			7			8				9				10				11			12		13			14 				15 expansion
%     %[no,   tipo,   r (Ohm/km), x (Ohm/km), G (Ohm/km) 	C (Ohm/km), Imax (kA) 	Cfijo cond		Cvar. cond		Cvar. torre 	vida_util  	Vnom 	ROW [Ha/km] diametro (mm)	1/0
%     %      2:HTLS
%         98	1       0.021       0.242       0			0.00554 	0.83674     0				0.0001          0.00015         40			345		4.2672		39.2			1;
%         99	2       0.1684      0.2612      0			0.00550     1.332       0				0.000190549     0.000321551     40			138		3.3528		18.2			1;	
%     ];
    
    data.CompensacionSerie = [
    %[no, %comp, cfijo, cvar]
        %1	0.25	0	0.031;
        1	0.5		0	0.031;
    ];

    data.Costos(1,1) = 0;  %ROW USD/Ha
    data.Costos(1,2) = 1;  % factor desarrollo proyectos
    
    % Por ahora sólo se considera VU para ir a 345 kV
    data.VoltageUprating = [1 345 1.5 0];
    
    data.Buses = [];
    data.Consumos = [];
    data.Generadores = [];
    data.Corredores = [];
    data.Lineas = [];
    data.Transformadores = [];
    data.TipoTransformadores = [];
    data.PuntosOperacion = [];
    data.SeriesERNC = [];
    data.SeriesConsumo = [];
    
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
            data.Buses(contador_buses, 4) = 0; % num(fila,4); % vmax pu
            data.Buses(contador_buses, 5) = 0; % num(fila,5); % vmin pu
            data.Buses(contador_buses, 6) = 0; % conectividad (se ve después)
			data.Buses(contador_buses, 7) = 0; % posX
			data.Buses(contador_buses, 8) = 0; % posY
            contador_buses = contador_buses+1;
        else
            error= MException('genera_datos_ieee_bus_118_ernc:genera_datos','datos en buses no son secuenciales');
            throw(error)
        end
    end


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
        data.Consumos(contador_consumo, 2) = num(fila, 2); % Pmax
        data.Consumos(contador_consumo, 3) = num(fila, 2); % Qmax
        data.Consumos(contador_consumo, 4) = num(fila, 3); %Existente
        data.Consumos(contador_consumo, 5) = num(fila, 4); % %costos NLSC
        data.Consumos(contador_consumo, 6) = num(fila, 5); % id perfil 
        data.Consumos(contador_consumo, 7) = num(fila, 6); % tipo evolucion capacidad (0: fija; 1: porcentaje fijo; 2: porcentaje variable por anio)
        data.Consumos(contador_consumo, 8) = num(fila, 7); % valor evolucion (depende de tipo de evolucion)		
    end

    
    num = xlsread(filename, 'Generators');    
    contador_generadores = 0;
    [n, ~] = size(num);
    for fila = inicio:n
		contador_generadores = contador_generadores + 1;
        id_gen = num(fila,1);
        bus_gen = num(fila,2);
        
		data.Generadores(contador_generadores, 1) = id_gen; % Id
		data.Generadores(contador_generadores, 2) = bus_gen; %Bus
		data.Generadores(contador_generadores, 3) = num(fila,6); %P0
		data.Generadores(contador_generadores, 4) = 0; %Q0
		data.Generadores(contador_generadores, 5) = num(fila,6); %Pmax
		data.Generadores(contador_generadores, 6) = 0; %Pmin
		data.Generadores(contador_generadores, 7) = num(fila,8); %Qmax
		data.Generadores(contador_generadores, 8) = 0; %Qmin
		data.Generadores(contador_generadores, 9) = 1; %Vobj pu
		data.Generadores(contador_generadores, 10) = num(fila,18); % existente o proyectado
		data.Generadores(contador_generadores, 11) = num(fila,16); % slack
		data.Generadores(contador_generadores, 12) = num(fila,4)/10000; %costos generación
        data.Generadores(contador_generadores, 13) = num(fila,17); % tipo: 0: convencional, 1: eólico, 2: solar
        data.Generadores(contador_generadores, 14) = num(fila,19); % evolucion capacidad (si/no)
        data.Generadores(contador_generadores, 15) = num(fila,20); % evolucion costos (si/no)
        data.Generadores(contador_generadores, 16) = num(fila,21); % Perfil ERNC
        % por ahora sólo estos datos de los generadores
    end
    
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
        cantidad_vu = num(fila, 13);
        cantidad_cs = num(fila, 14);
        cantidad_cc = num(fila, 15);
        expansion = num(fila, 9);
        largo = num(fila, 10);
        cinv = num(fila, 11)/1000000; % en MM USD
        vnom = num(fila, 12);
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
                data.Lineas(contador_lineas, 10) = anio_construccion; %año construcción
            else
                data.Lineas(contador_lineas, 7) = 0; %status
                data.Lineas(contador_lineas, 10) = 0; %año construcción
            end
            data.Lineas(contador_lineas, 8) = cinv;
            data.Lineas(contador_lineas, 9) = id_conductor;
            data.Lineas(contador_lineas, 11) = id_linea_orig;
        end
    end

    num = xlsread(filename, 'Transformers');
    inicio = 1;
    while isnan(num(inicio,1))
        inicio = inicio + 1;
    end
    [n, ~] = size(num);
    contador_trafos = 0;
    contador_tipo_trafo= 0;
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
        id_corredor = find(ismember(data.Corredores(:,1:2), [bus_inicio bus_fin], 'rows'),1,'first');
        if ~isempty(id_corredor)
            error= MException('genera_datos_ieee_bus_118_ernc:genera_datos','datos en transformadores incorrectos. Corredor ya se encuentra');
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
                data.Transformadores(contador_trafos, 7) = anio_construccion; %año construcción
            else
                data.Transformadores(contador_trafos, 7) = 0; %año construcción
            end 
            data.Transformadores(contador_trafos, 8) = id_linea_orig;
        end
    end
    
    % determina conectividad buses
	[n, ~] = size(data.Buses);
    for bus = 1:n
        if ~isempty(find(data.Lineas(:,1) == bus, 1))
            data.Buses(bus, 3) = 1;
        elseif ~isempty(find(data.Lineas(:,2) == bus, 1))
            data.Buses(bus, 3) = 1;
        elseif ~isempty(find(data.Transformadores(:,1) == bus, 1))
            data.Buses(bus, 3) = 1;
        elseif ~isempty(find(data.Transformadores(:,2) == bus, 1))
            data.Buses(bus, 3) = 1;
        end
    end
    
    data.Conductores = [data.Conductores; Conductores_HTLS_VU];

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
        error = MException('genera_datos_ieee_bus_118_ernc:genera_datos','Punto de operacion indicado no existe');
        throw(error)
    end
    col = 2;
    cantidad_po = 0;
    [~, cant_col] = size(num);
    while ~isnan(num(fila_po,col))
        cantidad_po = cantidad_po + 1;
        data.PuntosOperacion(cantidad_po,1) = num(fila_po,col); %id
        data.PuntosOperacion(cantidad_po,2) = num(fila_po+1,col); %peso
        col = col + 1;
        if col > cant_col
            break;
        end
    end
    parametros.CantidadPuntosOperacion = cantidad_po;
    
    % Escenarios
    
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
        error= MException('genera_datos_ieee_bus_118_ernc:genera_datos','Escenario indicado no existe');
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
    parametros.CantidadPuntosOperacion = cantidad_po;
    parametros.CantidadEscenarios = cantidad_escenarios;
    
    
%    data.PerfilesERNC = [perfil_id, inyeccion_po1, inyeccion_po2, ...];    
    num = xlsread(filename, 'ERNC_Profiles');
    inicio = 1;
    while isnan(num(inicio,1))
        inicio = inicio + 1;
    end    
    [n, m] = size(num);
    cant_puntos_operacion_datos = m-1;
    cantidad_perfiles = 0;
    for fila = inicio:n
        cantidad_perfiles = cantidad_perfiles + 1;
        id_perfil = num(fila,1);
        data.PerfilesERNC(cantidad_perfiles,1) = id_perfil;
        id_po_actual = 1;
        po_actual = data.PuntosOperacion(id_po_actual,1);
        
        for po = 1:cant_puntos_operacion_datos
            if num(1,po+1) == po_actual
                inyeccion_pu = num(fila,po+1);
                data.PerfilesERNC(cantidad_perfiles,id_po_actual+1) = inyeccion_pu;
                if id_po_actual == cantidad_po
                    break
                else
                    id_po_actual = id_po_actual + 1;
                    po_actual = data.PuntosOperacion(id_po_actual,1);
                end
            end
        end
    end

    num = xlsread(filename, 'Demand_Profiles');
    inicio = 1;
    while isnan(num(inicio,1))
        inicio = inicio + 1;
    end    
    [n, m] = size(num);
    cant_puntos_operacion_datos = m-1;
    cantidad_perfiles_demanda = 0;
    for fila = inicio:n
        cantidad_perfiles_demanda = cantidad_perfiles_demanda + 1;
        id_perfil = num(fila,1);
        data.PerfilesDemanda(cantidad_perfiles_demanda,1) = id_perfil;
        id_po_actual = 1;
        po_actual = data.PuntosOperacion(id_po_actual,1);
        for po = 1:cant_puntos_operacion_datos
            if num(1,po+1) == po_actual
                perfil_pu = num(fila,po+1);
                data.PerfilesDemanda(cantidad_perfiles_demanda,id_po_actual+1) = perfil_pu;
                if id_po_actual == cantidad_po
                    break
                else
                    id_po_actual = id_po_actual + 1;
                    po_actual = data.PuntosOperacion(id_po_actual,1);
                end
            end
        end
    end

    num = xlsread(filename, 'Capacity_Evolution_Generators');
    inicio = 1;
    while isnan(num(inicio,1))
        inicio = inicio + 1;
    end    
    [n, m] = size(num);
    cantidad_etapas_datos = m - 2;
    if cantidad_etapas_datos < cantidad_etapas
        error = MException('genera_datos_ieee_bus_118_ernc:genera_datos','Cantidad de etapas en datos es menor a cantidad de etapas en parámetros');
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
