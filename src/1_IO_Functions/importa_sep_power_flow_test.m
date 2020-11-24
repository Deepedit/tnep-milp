function sep = importa_sep_power_flow_test()
    load('./input/IEEE_30_Bus_System.mat')
    %voltajes objetivos de los buses se escala a 220
    vbase = 220;  %kV
    sbase = 100; % MVA
    zbase = vbase^2/sbase;
    
    busdata(:,3) = busdata(:,3)*vbase;
    sep = cSistemaElectricoPotencia;
    for i = 1:length(busdata)
        se = cSubestacion;
        se.inserta_nombre(strcat('SE_',num2str(i)));
        se.inserta_vn(vbase);
		se.inserta_id(i);
        sep.agrega_subestacion(se);
    end
    
    %agrega consumos. Se hace en forma separada para verificar performance
    %e índices de búsqueda
    cant_consumos = 0;
    cant_gen = 0;
    for i = 1:length(busdata)
        if busdata(i,5) ~= 0 || busdata(i,6) ~= 0
            cant_consumos = cant_consumos + 1;
            consumo = cConsumo;
            nombre_bus = strcat('SE_', num2str(i));
            se = sep.entrega_subestacion(nombre_bus);
            if isempty(se)
                error = MException('cimporta_sep_power_flow_test:main','no se pudo encontrar subestación');
                throw(error)
            end
            
            consumo.inserta_subestacion(se);
            consumo.inserta_nombre(strcat('Consumo_',num2str(cant_consumos), '_', se.entrega_nombre()));
            consumo.inserta_p0(busdata(i,5));
            consumo.inserta_q0(busdata(i,6));
            consumo.inserta_tiene_dependencia_voltaje(false);
            sep.agrega_consumo(consumo);
        end
        % generadores
        if busdata(i,2) == 2
            cant_gen = cant_gen + 1;
            gen = cGenerador();
            nombre_bus = strcat('SE_', num2str(i));
            se = sep.entrega_subestacion(nombre_bus);
            if isempty(se)
                error = MException('cimporta_sep_power_flow_test:main','no se pudo encontrar subestación');
                throw(error)
            end
            gen.inserta_nombre(strcat('G',num2str(cant_gen), '_', nombre_bus));
            gen.inserta_subestacion(se);
            pgen = busdata(i,7);
            gen.inserta_pmax(100);
            if pgen > 0
                gen.inserta_p0(pgen);
            end
            if busdata(i,9) ~= 0
                qmin = busdata(i,9);
                gen.inserta_qmin(qmin);
            end
            if busdata(i,10) ~= 0
                qmax = busdata(i,9);
                gen.inserta_qmax(qmax);
            end
            gen.inserta_controla_tension();
            gen.inserta_voltaje_objetivo(busdata(i,3));
            sep.agrega_generador(gen);
            if i == 11
                gen.inserta_es_slack();
            end
        end
    end
    
    largo_referencia = 100; %km
    cant_lineas = 0;
    for i = 1:length(linedata)
        cant_lineas = cant_lineas + 1;
        bus1 = linedata(i,1);
        bus2 = linedata(i,2);
        rpu = zbase*linedata(i,3)/largo_referencia;
        xpu = zbase*linedata(i,4)/largo_referencia;
        bpu = zbase*linedata(i,5)*2/largo_referencia;
        nombre_bus1 = strcat('SE_', num2str(bus1));
        nombre_bus2 = strcat('SE_', num2str(bus2));
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
        
        linea = cLinea();
        nombre = strcat('L', num2str(cant_lineas), '_SE_', num2str(bus1), '_', num2str(bus2));
        linea.inserta_nombre(nombre);
        linea.agrega_subestacion(se1, 1);
        linea.agrega_subestacion(se2,2);
        linea.inserta_xpu(xpu);
        linea.inserta_rpu(rpu);
        linea.inserta_cpu(bpu/(2*pi*50)*1000000);
        linea.inserta_largo(largo_referencia);
        
        sep.agrega_linea(linea);
        
    end
end
