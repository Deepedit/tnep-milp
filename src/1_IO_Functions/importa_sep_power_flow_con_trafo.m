function sep = importa_sep_power_flow_con_trafo()
    sep = cSistemaElectricoPotencia;
    sbase = cParametrosSistemaElectricoPotencia.getInstance().entrega_sbase();    

    %Buses: [Nr., Vn]
    Buses = [1, 220; 2, 220; 3, 220; 4, 220; 5, 110];
    % Lineas: [Bus1, Bus2, rpu, xpu, admitancia paralelo pu MVA]
    Lineas = [1, 2, 0.001, 0.05, 0.05, 100; ...
              2, 4, 0.001, 0.05, 0.05, 250;...
              3, 4, 0.001, 0.05, 0.05, 100];
    % Trafos: [Bus1, Bus2, Zcc, tapmin, tapmax, paso MVA]
    Trafos = [4, 5, 0.1, 0.9, 1.1, 0.005, 150];
    
    % Generador: [Bus, P0, Pmax, Qmin, Qmax, Vobj, Slack USD/Mwh] 
    Generadores = [1, 100, 100, -80, 80, 1, 1, 30;...
                 2, 150, 150, -100, 100, 1, 0, 80];
    % Consumo: [Bus, P0, Q0, dependencia de voltaje]
    Consumos = [3, 50, 10, 0;...
               5, 100, 50, 0];
    
    [nb, ~] = size(Buses);
    for i = 1:nb
        se = cSubestacion;
        se.inserta_nombre(strcat('SE_',num2str(i)));
        se.inserta_vn(Buses(i, 2));
		se.inserta_id(i);
        sep.agrega_subestacion(se);
    end
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
    %[Bus, P0, Pmax, Qmin, Qmax, Vobj, Slack]
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
        pmax = Generadores(i,3);
        qmin = Generadores(i,4);
        qmax = Generadores(i,5);
        Vobj = Generadores(i,6);
        Slack = Generadores(i,7);
        Costo_mwh = Generadores(i,8);
        gen.inserta_pmax(pmax);
        gen.inserta_costo_mwh(Costo_mwh);
        if p0 > 0
            gen.inserta_p0(p0);
        end
        gen.inserta_qmin(qmin);
        gen.inserta_qmax(qmax);
        gen.inserta_controla_tension();
        gen.inserta_voltaje_objetivo(se.entrega_vn()*Vobj);
        if Slack == 1
            gen.inserta_es_slack();
        end
        se.agrega_generador(gen);
        sep.agrega_generador(gen);
    end

    % Lineas: [Bus1, Bus2, rpu, xpu, 1/2admitancia paralelo pu]
    [nl, ~] = size(Lineas);
    for i = 1:nl

        nombre_bus1 = strcat('SE_', num2str(Lineas(i,1)));
        nombre_bus2 = strcat('SE_', num2str(Lineas(i,2)));
        rpu = Lineas(i,3);
        xpu = Lineas(i,4);
        largo = 100; %km
        %bpu = 2.93023;
        bpu = 2*Lineas(i,5);
        capacidad = Lineas(i,6);
        
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
        
        sep.agrega_linea(linea);
        se1.agrega_linea(linea);
        se2.agrega_linea(linea);
    end
	% Trafo:   [Bus1, Bus2, Zcc, tapmin, tapmax, paso capacidad]
    % Trafos = [4   , 5   , 0.1, 0.9   , 1.1   , 0.005, 150];
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
        zcc_pu = Trafos(i,3);
        xk = zcc_pu*zbase; %0.1*impedancia_base (220^2/100)
        vmin = Trafos(i,4)*vn;
        vmax = Trafos(i,5)*vn;
        dutap = Trafos(i,6); %en porcentaje de vn del lado del tap
        sr = Trafos(i,7);
        
        tap_nom = 0;
        tap_min = (vmin-vn)/dutap/vn;
        tap_max = (vmax-vn)/dutap/vn;
        
        trafo = cTransformador2D();
        nombre = strcat('T', num2str(i), '_SE_', num2str(Trafos(i,1)), '_', num2str(Trafos(i,2)));
        trafo.inserta_nombre(nombre);
        trafo.inserta_subestacion(se1,1);
        trafo.inserta_subestacion(se2,2);
        trafo.inserta_tipo_conexion('Y', 'y', 0);
        trafo.inserta_cantidad_de_taps(1);
        
        trafo.inserta_tap_min(tap_min);
        trafo.inserta_tap_max(tap_max);
        trafo.inserta_tap_nom(tap_nom);
        trafo.inserta_tap_actual(0);
        trafo.inserta_du_tap(dutap);
        trafo.inserta_lado_tap(1);

        trafo.inserta_sr(sr);
        trafo.inserta_pcu(0);
        trafo.inserta_uk(xk/(vn^2/sr));
        trafo.inserta_i0(0);
        trafo.inserta_p0(0);
        %tap regulador
        trafo.inserta_voltaje_objetivo(110);
        trafo.inserta_indice_se_regulada(2);
        trafo.inserta_id_tap_controlador(1);
        sep.agrega_transformador(trafo);
        se1.agrega_transformador2D(trafo);
        se2.agrega_transformador2D(trafo);
    end
end
