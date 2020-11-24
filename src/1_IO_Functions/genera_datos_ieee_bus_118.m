function data = genera_datos_ieee_bus_118(parametros, id_operating_points)
    path = './input/Data_IEEE_118/';
    filename = [path 'IEEE_118_Bus_Data.xlsx']; 

    sbase = 100; %MVA
    data.baseMVA = 100;
    % datos a agregar al final

	Conductores_HTLS_VU = [
    %[  1,  2,  3, 			4			5			6			7			8				9				10				11			12		13			14 				15 expansion
    %[no, tipo, r (Ohm/km), x (Ohm/km), G (Ohm/km) 	C (Ohm/km), Imax (kA) 	Cfijo cond		Cvar. cond		Cvar. torre 	vida_util  	Vnom 	ROW [Ha/km] diametro (mm)	1/0
        99	2	0.0253		0.5925		0			0			1.255   	0				0.00258037 		0.00098555987 	40			138		3.3528		18.2			1;
        %4	1	0.075625	0.75625		0			0			1.018	  	0				0.00060283 		0.00082888662 	40			345		4.2672		39.2			1;	
    ];
    
    data.Costos(1,1) = 5000;  %ROW USD/Ha
    data.Costos(1,2) = 1.05;  % factor desarrollo proyectos
    
    % Por ahora sólo se considera VU para ir a 345 kV
    data.VoltageUprating = [1 345 1.5 0];
    
    data.Buses = [];
    data.Consumos = [];
    data.Generadores = [];
    data.Corredores = [];
    data.Lineas = [];
    data.Transformadores = [];
    data.TipoTransformadores = [];
    num = xlsread(filename, 'Bus_Data');
    inicio = 1;
    while isnan(num(inicio,1))
        inicio = inicio + 1;
    end    
    [n, ~] = size(num);
    contador_buses = 1;
    contador_consumo = 0;
    contador_generadores = 0;
    for fila = inicio:n
        if num(fila,1) == contador_buses
            data.Buses(contador_buses, 1) = contador_buses;
            data.Buses(contador_buses, 2) = num(fila,4);
            data.Buses(contador_buses, 3) = 0;  % conectividad. Se ve después
            data.Buses(contador_buses, 4) = 0;
            data.Buses(contador_buses,5) = 0;
            
            if num(fila, 5) > 0 
                contador_consumo = contador_consumo + 1;
                data.Consumos(contador_consumo, 1) = contador_consumo;
                data.Consumos(contador_consumo, 2) = contador_buses;
                data.Consumos(contador_consumo, 3) = num(fila, 5); %P0
                data.Consumos(contador_consumo, 4) = 0; % Q0
                data.Consumos(contador_consumo, 5) = 0; % Dep volt.
                data.Consumos(contador_consumo, 6) = num(fila, 6); %costos NLSC
                data.Consumos(contador_consumo, 7) = 3.25; % aumento anual
            end
            
            if num(fila,7) > 0
               contador_generadores = contador_generadores + 1;
               data.Generadores(contador_generadores, 1) = 0; % Id
               data.Generadores(contador_generadores, 2) = contador_buses; %Bus
               data.Generadores(contador_generadores, 3) = num(fila,7); %P0
               data.Generadores(contador_generadores, 4) = 0; %Q0
               data.Generadores(contador_generadores, 5) = num(fila,7); %Pmax
               data.Generadores(contador_generadores, 6) = 0; %Pmin
               data.Generadores(contador_generadores, 7) = 0; %Qmax
               data.Generadores(contador_generadores, 8) = 0; %Qmin
               data.Generadores(contador_generadores, 9) = 1; %Vobj pu
               data.Generadores(contador_generadores, 10) = 1; % status
               data.Generadores(contador_generadores, 11) = 0; % slack
               data.Generadores(contador_generadores, 12) = num(fila,8); %costos generación
               data.Generadores(contador_generadores, 13) = 3.25; % aumento anual
            end

            contador_buses = contador_buses+1;
        else
            error('datos en buses no son secuenciales')
        end
    end
    num = xlsread(filename, 'Generators_Data');
    inicio = 1;
    while isnan(num(inicio,1))
        inicio = inicio + 1;
    end    
    [n, ~] = size(num);
    for fila = inicio:n
        id_gen = num(fila,1);
        bus_gen = num(fila,2);
        indice_generadores = find(data.Generadores(:,2) == bus_gen);
        [cant_indices, ~] = size(indice_generadores);
        if cant_indices == 0
            error('no se encontró bus para el generador');
        elseif cant_indices > 1
            error('existe más de un bus para el generador');
        else
            data.Generadores(indice_generadores,1) = id_gen;
        end
        data.Generadores(indice_generadores, 11) = num(fila, 27);
        %data.Generadores(indice_generadores, 13) = num(fila, 29); % aumento anual
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
        expansion = num(fila, 9);
        largo = num(fila, 10);
        cinv = num(fila, 11)/1000000; % en MM USD
        vnom = num(fila, 12);
        if ~corredor_incorporado
            data.Corredores(contador_corredores, 1) = bus_inicio;
            data.Corredores(contador_corredores, 2) = bus_fin;
            data.Corredores(contador_corredores, 3) = largo;
            if expansion == 1
                data.Corredores(contador_corredores, 4) = 2;
            else
                data.Corredores(contador_corredores, 4) = 1;
            end
            % valores por defecto para vu, sc, cc
            data.Corredores(contador_corredores, 5) = 0; % vu
            data.Corredores(contador_corredores, 6) = 0; % sc
            data.Corredores(contador_corredores, 7) = 0; % cc

            data.Corredores(contador_corredores, 5) = expansion; % vu
            if largo >= 80
                data.Corredores(contador_corredores, 6) = expansion; % sc
            else
                data.Corredores(contador_corredores, 7) = expansion; % cc
            end
        else
            if expansion == 1
                data.Corredores(id_corredor_incorporado, 4) = data.Corredores(id_corredor_incorporado, 4) + 1;
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
            
            cvar_conductor = cinv*0.35/largo/sr;
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
            
            id_conductor = contador_conductores;
            
            % solución provisional para el tipo de conductor base. 
            % el primer conductor de cada nivel de tensión se considerará
            % como base
            if sum(ismember(data.Conductores(:,12), vnom)) == 1
                data.Conductores(contador_conductores, 15) = 1;
            else
                data.Conductores(contador_conductores, 15) = 0;
            end
        end
        
        contador_lineas = contador_lineas + 1;
        data.Lineas(contador_lineas, 1) = bus_inicio;
        data.Lineas(contador_lineas, 2) = bus_fin;
        data.Lineas(contador_lineas, 3) = rpu;
        data.Lineas(contador_lineas, 4) = xpu;
        data.Lineas(contador_lineas, 5) = bpu;
        data.Lineas(contador_lineas, 6) = sr;
        data.Lineas(contador_lineas, 7) = 1; %status
        data.Lineas(contador_lineas, 8) = cinv;
        data.Lineas(contador_lineas, 9) = id_conductor;
        data.Lineas(contador_lineas, 10) = 1990; %año construcción
        data.Lineas(contador_lineas, 11) = id_linea_orig;
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
        bus_inicio = num(fila, 2);
        bus_fin = num(fila, 3);
        sr = num(fila, 5);
        v_at = num(fila, 6);
        v_bt = num(fila, 7);
        x_ohm = num(fila,8);
        cinv = num(fila, 9)/1000000; % en MM USD
        n_existente = num(fila, 13);
        expansion = num(fila,18); 
        id_corredor = find(ismember(data.Corredores(:,1:2), [bus_inicio bus_fin], 'rows'),1,'first');
        if ~isempty(id_corredor)
            error('datos en transformadores incorrectos. Corredor ya se encuentra')
        end
        contador_corredores = contador_corredores + 1;
        data.Corredores(contador_corredores, 1) = bus_inicio;
        data.Corredores(contador_corredores, 2) = bus_fin;
        data.Corredores(contador_corredores, 3) = 0;
        if expansion == 1
            data.Corredores(contador_corredores, 4) = n_existente + 1;
        else
            data.Corredores(contador_corredores, 4) = n_existente;
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
        for trafo = 1:n_existente
            contador_trafos = contador_trafos + 1;
            data.Transformadores(contador_trafos, 1) = bus_inicio;
            data.Transformadores(contador_trafos, 2) = bus_fin;
            data.Transformadores(contador_trafos, 3) = x_ohm;
            data.Transformadores(contador_trafos, 4) = sr;
            data.Transformadores(contador_trafos, 5) = id_tipo_trafo;
            data.Transformadores(contador_trafos, 6) = 10350*sr/1000000; %cinv. en MMUSD
            data.Transformadores(contador_trafos, 7) = 1990; %año construcción
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
        if num(fila,1) == id_operating_points
            fila_po = fila;
            break;
        end
    end
    if fila_po == 0
        %error = MException('genera_datos_ieee_bus_118_ernc:genera_datos','Punto de operacion indicado no existe');
        %throw(error)
        error('Punto de operacion indicado no existe')
    end
    col = 2;
    cantidad_po = 0;
    [~, max_col] = size(num);
    while col <= max_col && ~isnan(num(fila_po,col))
        cantidad_po = cantidad_po + 1;
        data.PuntosOperacion(cantidad_po,1) = num(fila_po,col);
        data.PuntosOperacion(cantidad_po,2) = num(fila_po+1,col);
        col = col + 1;
    end
    parametros.CantidadPuntosOperacion = cantidad_po;

    % identifica factor de multiplicacion de la demanda para cada punto de
    % operación
    num = xlsread(filename, 'Demand_factor');
    for i = 1:cantidad_po
        punto_operacion = data.PuntosOperacion(i,1);
        data.PuntosOperacion(i,3) = num(punto_operacion,2);
    end    
end
