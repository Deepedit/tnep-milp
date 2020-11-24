function sep = importa_sep_power_flow_matpower()
    % data corresponde a datos de matpower
    data = case39_trafos_t_1;
    %data = case39_trafos_t_1test;
    %data = case5;
    %data = case5_test;
    sep = cSistemaElectricoPotencia;
    par_sep = cParametrosSistemaElectricoPotencia.getInstance;
    sbase_matpower = data.baseMVA;
    par_sep.inserta_sbase(sbase_matpower);
    
    % redundante pero para ver que funciones
    sbase = par_sep.entrega_sbase();    

    [n, ~] = size(data.bus);
    %Buses: [No, Vn]
    % Consumo: [Bus, P0, Q0, dep_volt]
    Buses = zeros(n,2);
    Consumos = [];
    Condensadores = [];
    Reactores = [];
    busref = 0;
    for i = 1:n
        Buses(i,1) = data.bus(i,1);
        Buses(i,2) = data.bus(i,10);
        if data.bus(i,2) == 3
            busref = data.bus(i,1);
        end
        if data.bus(i,3) ~= 0 || data.bus(i,4) ~= 0
            Consumos(end+1,1) = data.bus(i,1); %bus
            Consumos(end,2) = data.bus(i,3); % P0
            Consumos(end,3) = data.bus(i,4); % Q0
            Consumos(end,4) = 0; % dependencia de voltaje
        end
        if data.bus(i,5) ~= 0 && data.bus(i,6) ~= 0
            % asumo que se trata de un consumo dependiente de voltaje
            Gs = data.bus(i,5);
            Bs = data.bus(i,6);
            % FALTA TERMINAR 
        elseif data.bus(i,6) ~= 0
            % condensador o reactor
            Bs = data.bus(i,6);
            %FALTA TERMINAR
        end
    end
    %              1    2  3    4     5     6     7     8    9       10  11 
    % Generador: [Bus, P0, Q0, Pmax, Pmin, Qmax, Qmin, Vobj, status, Slack, USD/Mwh]
    [n, ~] = size(data.gen);
    Generadores = zeros(n,11);
    for i = 1:n
        Generadores(i,1)=data.gen(i,1);
        Generadores(i,2) = data.gen(i,2);
        Generadores(i,3) = data.gen(i,3);
        Generadores(i,4) = data.gen(i,9);
        Generadores(i,5) = data.gen(i,10);
        Generadores(i,6) = data.gen(i,4);
        Generadores(i,7) = data.gen(i,5);
        Generadores(i,8) = data.gen(i,6);
        Generadores(i,9) = data.gen(i,8);
        if busref == data.gen(i,1)
            Generadores(i,10) = 1;
        end 
    end
        
    
    % Lineas: [Bus1, Bus2, rpu, xpu, admitancia paralelo pu MVA status]
	% % Trafos: [Bus1, Bus2, r, xcc, B, MVA, status, tapmin, tapmax, tap_nom, du_tap, tap_actual lado_tap]
    [n, ~] = size(data.branch);
    Lineas = [];
    Trafos = [];
    for i = 1:n
        bus1 = data.branch(i,1);
        bus2 = data.branch(i,2);
        rpu = data.branch(i,3);
        xpu = data.branch(i,4);
        bpu = data.branch(i,5);
        rate_mva = data.branch(i,6);
        status = data.branch(i,11);
        if data.branch(i,9) == 0
            %línea
            Lineas(end+1,1)=bus1;
            Lineas(end,2) = bus2;
            Lineas(end,3) = rpu;
            Lineas(end,4) = xpu;
            Lineas(end,5) = bpu;
            Lineas(end,6) = rate_mva;
            Lineas(end,7) = status;
        else
            %trafos
            % Trafos: [Bus1, Bus2, r, xcc, B, MVA, status, tapmin, tapmax, tap_nom, du_tap, tap_actual lado_tap]
            Trafos(end+1,1) = bus1;
            Trafos(end,2) = bus2;
            Trafos(end,3) = rpu;
            Trafos(end,4) = xpu;
            Trafos(end,5) = bpu;
            Trafos(end,6) = rate_mva;
            Trafos(end,7) = status;
            tapmin = -20;
            tapmax = 20;
            tapnom = 0;
            Trafos(end,8) = tapmin;
            Trafos(end,9) = tapmax;
            Trafos(end,10) = tapnom;
            ttrafo = data.branch(i,9);  %1.025
            du_tap = 0.005; % para cubrir el espectro 0.9 a 1.1
            Trafos(end,11) = du_tap;
            tap_actual = (ttrafo-1)/du_tap+tapnom;
            Trafos(end,12) = tap_actual;
            Trafos(end,13) = 1; %lado tap
        end
    end
    
    % Formato PLAS
    % Buses = [id, vn] 
    [nb, ~] = size(Buses);
    for i = 1:nb
        se = cSubestacion;
        se.inserta_nombre(strcat('SE_',num2str(i)));
        se.inserta_vn(Buses(i, 2));
		se.inserta_id(i);
        sep.agrega_subestacion(se);
    end
    %              1      2       3         4
    % Consumos = [bus, p0 (MW), q0 (MW), dep_volt]
    [nc, ~] = size(Consumos);
    for i = 1:nc
        consumo = cConsumo;
        nombre_bus = strcat('SE_', num2str(Consumos(i,1)));
        se = sep.entrega_subestacion(nombre_bus);
        if isempty(se)
            error = MException('cimporta_sep_power_flow_test:main','no se pudo encontrar subestación');
            throw(error)
        end
            
        consumo.inserta_subestacion(se);
        consumo.inserta_nombre(strcat('Consumo_',num2str(i), '_', se.entrega_nombre()));
        consumo.inserta_p0(Consumos(i,2));
        consumo.inserta_q0(Consumos(i,3));
        if Consumos(i,4) == 0
            depvolt = false;
        else
            depvolt = true;
        end
        consumo.inserta_tiene_dependencia_voltaje(depvolt);
        se.agrega_consumo(consumo);
        sep.agrega_consumo(consumo);
    end
    %              1    2  3    4     5     6     7     8      9      10      11 
    % Generador: [bus, P0, Q0, Pmax, Pmin, Qmax, Qmin, Vobj, status, Slack, USD/Mwh]
    [ng, ~] = size(Generadores);
    for i = 1:ng
        gen = cGenerador();
        nombre_bus = strcat('SE_', num2str(Generadores(i,1)));
        se = sep.entrega_subestacion(nombre_bus);
        if isempty(se)
            error = MException('cimporta_sep_power_flow_test:main','no se pudo encontrar subestación');
            throw(error)
        end
    
        gen.inserta_nombre(strcat('G', num2str(i), '_', nombre_bus));
        gen.inserta_subestacion(se);
        p0 = Generadores(i,2);
        q0 = Generadores(i,3);
        pmax = Generadores(i,4);
        pmin = Generadores(i,5);
        qmax = Generadores(i,6);
        qmin = Generadores(i,7);
        Vobj = Generadores(i,8);
        status = Generadores(i,9);
        Slack = Generadores(i,10);
        if Slack == 1
            gen.inserta_es_slack();
        end
        Costo_mwh = Generadores(i,11);
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
    end
    % Lineas: [bus1, bus2, rpu, xpu, bpu, sr, status]
	% Trafos: [bus1, bus2, r, xcc, B, MVA, status, tapmin, tapmax, tap_nom, du_tap, tap_actual lado_tap]

    % Lineas: [bus1, bus2, rpu, xpu, bpu, sr, status, C (MM.USD)]
    [nl, ~] = size(Lineas);
    for i = 1:nl

        nombre_bus1 = strcat('SE_', num2str(Lineas(i,1)));
        nombre_bus2 = strcat('SE_', num2str(Lineas(i,2)));
        rpu = Lineas(i,3);
        xpu = Lineas(i,4);
        largo = 100; %km
        %bpu = 2.93023;
        bpu = Lineas(i,5);
        capacidad = Lineas(i,6);
        status = Lineas(i,7);
        
        se1 = sep.entrega_subestacion(nombre_bus1);
        se2 = sep.entrega_subestacion(nombre_bus2);
        
        if isempty(se1)
            error = MException('cimporta_sep_power_flow_test:main','no se pudo encontrar subestación 1');
            throw(error)
        end
        if isempty(se2)
            error = MException('cimporta_sep_power_flow_test:main','no se pudo encontrar subestación 2');
            throw(error)
        end
        vbase = se1.entrega_vbase();
        zbase = vbase^2/sbase;
        xpul = xpu*zbase/largo;
        rpul = rpu*zbase/largo;
        cpul = bpu/zbase/(largo*2*pi*50/1000000);
        linea = cLinea();
        nombre = strcat('L', num2str(i), '_SE_', num2str(Lineas(i,1)), '_', num2str(Lineas(i,2)));
        linea.inserta_nombre(nombre);
        linea.agrega_subestacion(se1, 1);
        linea.agrega_subestacion(se2,2);
        linea.inserta_xpul(xpul);
        linea.inserta_rpul(rpul);
        linea.inserta_cpul(cpul);
        linea.inserta_largo(largo);
        linea.inserta_sr(capacidad);
        linea.inserta_en_servicio(status);
        sep.agrega_linea(linea);
        se1.agrega_linea(linea);
        se2.agrega_linea(linea);
    end
    
    % Trafos: [Bus1, Bus2, r, xcc, B, MVA, status, tapmin, tapmax, tap_nom, du_tap, tap_actual lado_tap]
    [nt, ~] = size(Trafos);
    for i = 1:nt
        nombre_bus1 = strcat('SE_', num2str(Trafos(i,1)));
        nombre_bus2 = strcat('SE_', num2str(Trafos(i,2)));
        se1 = sep.entrega_subestacion(nombre_bus1);
        se2 = sep.entrega_subestacion(nombre_bus2);
        if isempty(se1)
            error = MException('cimporta_sep_power_flow_test:main','no se pudo encontrar subestación 1');
            throw(error)
        end
        if isempty(se2)
            error = MException('cimporta_sep_power_flow_test:main','no se pudo encontrar subestación 2');
            throw(error)
        end

        vn = se1.entrega_vn();
        vbase = se1.entrega_vbase();
        zbase = vbase^2/sbase;
        rpu = Trafos(i,3);
        rk = rpu*zbase;
        xpu = Trafos(i,4);
        xk = xpu*zbase; %0.1*impedancia_base (220^2/100)
        bpu = Trafos(i,5);
        I0 = bpu/sqrt(3)*vn/zbase;
        sr = Trafos(i,6);
        status = Trafos(i,7);
        tapmin = Trafos(i,8);
        tapmax = Trafos(i,9);
        tapnom = Trafos(i,10);
        dutap = Trafos(i,11);
        tap_actual = Trafos(i,12);
        lado_tap = Trafos(i,13);

        trafo = cTransformador2D();
        nombre = strcat('T', num2str(i), '_SE_', num2str(Trafos(i,1)), '_', num2str(Trafos(i,2)));
        trafo.inserta_nombre(nombre);
        trafo.inserta_subestacion(se1,1);
        trafo.inserta_subestacion(se2,2);
        trafo.inserta_tipo_conexion('Y', 'y', 0);
        trafo.inserta_cantidad_de_taps(1);
        trafo.inserta_en_servicio(status);
        
        trafo.inserta_tap_min(tapmin);
        trafo.inserta_tap_max(tapmax);
        trafo.inserta_tap_nom(tapnom);
        trafo.inserta_tap_actual(tap_actual);
        trafo.inserta_du_tap(dutap);
        trafo.inserta_lado_tap(lado_tap);

        trafo.inserta_sr(sr);
        trafo.inserta_pcu(rk/(vn/sr)^2);
        trafo.inserta_uk(xk/(vn^2/sr));
        trafo.inserta_i0(I0);
        trafo.inserta_p0(0);
        %tap regulador
        %trafo.inserta_voltaje_objetivo(110);
        %trafo.inserta_indice_se_regulada(2);
        %trafo.inserta_id_tap_controlador(1);
        sep.agrega_transformador(trafo);
        se1.agrega_transformador2D(trafo);
        se2.agrega_transformador2D(trafo);
    end
end
