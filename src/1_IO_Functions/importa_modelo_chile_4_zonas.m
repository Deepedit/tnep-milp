function importa_modelo_chile_4_zonas(data, sep, pAdmSc, NivelDebug)

    se_aisladas = importa_buses(data,sep);
    
	% inicializa los escenarios
    if isempty(data.IndicesPOConsecutivos)
        error = MException('importa_modelo_chile_4_zonas:main','Error en ingreso de datos. Indica que puntos de operacion no son consecutivos');
        throw(error)
    else
        pAdmSc.inicializa_escenarios(data.Escenarios(:,1), data.Escenarios(:,2), 1, length(data.PuntosOperacion(:,1)), data.PuntosOperacion(:,2), data.IndicesPOConsecutivos)        
    end
	importa_perfiles_ernc(data, pAdmSc);
	importa_perfiles_consumos(data, pAdmSc);
	importa_perfiles_afluentes(data, pAdmSc);
    importa_perfiles_vertimientos(data, pAdmSc);
	
    importa_consumos(data, sep, pAdmSc);    
    importa_generadores(data, sep);
    
    importa_baterias(data, sep);
    importa_embalses(data, sep, pAdmSc);
    importa_red_hidro(data, sep);
    %importa_lineas(data, sep);

    % corredores
    elementos = genera_elementos_red_serie(data,sep,NivelDebug);
    elementos = genera_elementos_red_paralelo(elementos, data, sep);
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

function importa_perfiles_afluentes(data, pAdmSc)
    [n, ~] = size(data.Afluentes);
	for i = 1:n
		perfil = data.Afluentes(i,1:end);
		pAdmSc.inserta_perfil_afluente(perfil);
	end	
end

function importa_perfiles_vertimientos(data, pAdmSc)
    [n, ~] = size(data.Vertimientos);
	for i = 1:n
		perfil = data.Vertimientos(i,1:end);
		pAdmSc.inserta_perfil_vertimiento(perfil);
	end	
end


function se_aisladas = importa_buses(data, sep)
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
        else
			se.Existente = false;
            se_aisladas = [se_aisladas se];
            error = MException('cimporta_problema_optimizacion_tnep_118_ernc:main','Caso buses proyectados no se ha visto aun');
            throw(error)
        end
    end
end

function importa_consumos(data, sep, pAdmSc)
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
        if isempty(se)
            error = MException('cimporta_problema_optimizacion_tnep:main','no se pudo encontrar subestación');
            throw(error)
        end
            
        consumo.inserta_subestacion(se);
        consumo.inserta_nombre(strcat('Consumo_',num2str(i), '_', se.entrega_nombre()));
        consumo.inserta_p0(Consumos(i,2));
        consumo.inserta_q0(Consumos(i,3));
        consumo.inserta_tiene_dependencia_voltaje(false); % para TNEP no se considera dependencia de voltaje
        costo_nls = Consumos(i,5);
        consumo.inserta_costo_desconexion_carga(costo_nls);
        se.agrega_consumo(consumo);
		if Consumos(i,4) == 1
			consumo.Existente = true;
			sep.agrega_consumo(consumo);
		else
            error = MException('cimporta_problema_optimizacion_tnep_118_ernc:main','Caso consumos proyectados no se ha visto aun');
            throw(error)
		end
        
        %agrega consumo a administrador de escenarios
        id_perfil = Consumos(i,6);
        consumo.inserta_indice_adm_escenario_perfil_p(id_perfil);
		tipo_evol_capacidad = Consumos(i,7);
        cant_etapas = 1;
		if tipo_evol_capacidad == 0
			aumento_porc = zeros(1, cant_etapas);
		elseif tipo_evol_capacidad == 1
			aumento_porc = [0 Consumos(i,8)*ones(1,cant_etapas-1)]; % se asume que en primera etapa P = Pmax
		else
            error = MException('cimporta_problema_optimizacion_tnep_118_ernc:main','Caso evolucion variable de la capacidad no se ha visto aun');
            throw(error)			
		end
		
        p0 = Consumos(i,2);
        petapa = p0;
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

function importa_generadores(data, sep)
    %              1    2  3    4     5     6     7     8      9      10      11 
    % Generador: [id, bus, P0, Q0, Pmax, Pmin, Qmax, Qmin, Vobj pu, status, Slack, USD/Mwh]
	Generadores = data.Generadores;
    Buses = data.Buses;
    [ng, ~] = size(Generadores);
    cant_etapas = 1;
    
    contador_PV = 1;
    contador_W = 1;
    contador_H = 1;
    
    for i = 1:ng
        
        id_bus = Generadores(i,2);
        vn = Buses(id_bus,2);
        existente = Generadores(i,10);
        if ~existente
            error = MException('importa_modelo_chile_4_zonas:main','Error en datos de entrada. Indica que generador no es existente');
            throw(error)
        end
        
        nombre_bus = strcat('SE_', num2str(Generadores(i,2)),'_VB_', num2str(vn));
        se = sep.entrega_subestacion(nombre_bus, false);
        if isempty(se)
            error = MException('importa_modelo_chile_4_zonas:main','no se pudo encontrar subestación');
            throw(error)
        end
        
        gen = cGenerador();
        %gen.inserta_nombre(strcat('G', num2str(i), '_', nombre_bus));
        gen.inserta_subestacion(se);
        p0 = Generadores(i,3);
        q0 = Generadores(i,4);
        pmax = Generadores(i,5);
        pmin = Generadores(i,6);
        qmax = Generadores(i,7);
        qmin = Generadores(i,8);
        Vobj = Generadores(i,9);
		
        Slack = Generadores(i,11);
        if Slack == 1
            gen.inserta_es_slack();
        end
		
        Costo_mwh = Generadores(i,12);
		tipo_generador = Generadores(i,13);
		evol_capacidad = Generadores(i,14);
		evol_costos = Generadores(i,15);
		perfil_ernc = Generadores(i,16);
        eficiencia = Generadores(i,17);
		
        gen.inserta_pmax(pmax);
        gen.inserta_pmin(pmin);
        gen.inserta_costo_mwh(Costo_mwh);
        gen.inserta_qmin(qmin);
        gen.inserta_qmax(qmax);
        gen.inserta_p0(p0);
        gen.inserta_q0(q0);
        gen.inserta_controla_tension();
        gen.inserta_voltaje_objetivo(se.entrega_vn()*Vobj);
        gen.inserta_en_servicio(1);
        gen.inserta_es_despachable(perfil_ernc == 0);
        gen.inserta_eficiencia(eficiencia);
        if tipo_generador == 1
            gen.inserta_tipo_central('Eol');
            gen.inserta_nombre(strcat('Wind', num2str(contador_W), '_', nombre_bus));
            contador_W = contador_W + 1;
        elseif tipo_generador == 2
            gen.inserta_tipo_central('PV');
            gen.inserta_nombre(strcat('PV', num2str(contador_PV), '_', nombre_bus));
            contador_PV = contador_PV + 1;
        else
            gen.inserta_tipo_central('Hidro');
            gen.inserta_nombre(strcat('H', num2str(contador_H), '_', nombre_bus));
            contador_H = contador_H + 1;
            %gen.inserta_eficiencia(eficiencia_hidro);
        end
		
		if perfil_ernc > 0
			gen.inserta_indice_adm_escenario_perfil_ernc(perfil_ernc);
			if gen.es_despachable()
				error = MException('importa_modelo_4_zonas:main','generador es convencional pero tiene perfil de ERNC');
				throw(error)
			end
        end
        
        if existente
			gen.Existente = 1;
			se.agrega_generador(gen);
			sep.agrega_generador(gen);
			if evol_capacidad
                error = MException('importa_modelo_chile_4_zonas:main','Error en datos de entrada. Hay evolucion de la capacidad de los generadores');
                throw(error)
			end
			if evol_costos
                error = MException('importa_modelo_chile_4_zonas:main','Error en datos de entrada. Hay evolucion en los costos de los generadores');
                throw(error)
			end
        else
            error = MException('importa_modelo_chile_4_zonas:main','Error en datos de entrada. Generador no es existente (es proyectado)');
            throw(error)            
        end
    end
end

function importa_embalses(data, sep, pAdmSc)
    %           1     2         3        4        5         6         7      8       9           10         11
    %Embalse: [id, Vol. Max, Vol. Min, Altura, Vol. Ini., Id Aflu, Id Verti, Bus, Eficiencia, Vol Final, % Filtra]
    Embalses = data.Embalses;
    [ne, ~] = size(Embalses);
    
    for i = 1:ne
        id_embalse = Embalses(i,1);
        Vol_max = Embalses(i,2);
        Vol_min = Embalses(i,3);
        ALtura = Embalses(i,4);
        Vol_ini = Embalses(i,5);
        Id_aflu = Embalses(i,6);
        Id_verti = Embalses(i,7);
        Bus = Embalses(i,8);
        Eficiencia = Embalses(i,9);
        Vol_fin = Embalses(i,10);
        Filtra = Embalses(i,11);
        
        %vn = 500;
        
        %Aquí Vn debería representar la tensión de la central, al igual que
        %la tensión de la subestación a la cual se conecta.
        %nombre_Hidro = strcat('SE_', num2str(Bus),'_VB_', num2str(vn));
        nombre_Hidro = strcat('SE_', num2str(Bus));
        se = sep.entrega_subestacion(nombre_Hidro, false);
%         if isempty(se)
%             error = MException('importa_modelo_chile_4_zonas:main','no se pudo encontrar subestación');
%             throw(error)
%         end
        Emb = cEmbalse();
        Emb.inserta_nombre(strcat('H', num2str(id_embalse), '_', nombre_Hidro));
        Emb.inserta_vol_max(Vol_max);
        Emb.inserta_vol_min(Vol_min);
        Emb.inserta_altura_caida(ALtura);
        Emb.inserta_vol_inicial(Vol_ini);
        Emb.inserta_indice_adm_escenario_afluentes(Id_aflu);
        %afluente_max = max(pAdmSc.entrega_perfil_afluentes(Id_aflu));
        %Emb.inserta_maximo_caudal_vertimiento(0);%(afluente_max);
        Emb.inserta_indice_adm_escenario_vertimiento_obligatorio(Id_verti);
        Emb.inserta_eficiencia(Eficiencia);
        Emb.inserta_vol_final(Vol_fin);
        
        Emb.crea_vertimiento(); %Crea generador(¿?)
        %Emb.crea_filtracion(0); %Creo la fltración como un generador. Ojo aquí
        %Emb.crea_aporte_adicional();

        
        sep.agrega_embalse(Emb);
        
        
    end
       
    
    
end

%% AQUÍ COMIENZA FUNCIÓN IMPORTA EMBALSES
function importa_red_hidro(data, sep) %importa_embalses(data, sep)
    %              1   2         3           4          5           6          7      8      9       10         11         12       13         14        15       16 
    % Generador: [id, Tipo, Emb. Inicio, Emb. Fin, %Filtración, Eta Turbina, Altura, Pmax, Pmin, Flujo.min, Flujo.max, Vol. Max, Vol. Min, Id. Afluente, Bus, Vol. Inicial]
	red = data.Hidro;
    Buses = data.Buses;
    generadores_existente = sep.entrega_generadores();
    [nb, ~] = size(red);
    [n_gene, ~] = size(generadores_existente);
    cant_etapas = 1;
    vn = 500;
    
    for i = 1:nb
        
         %              1   2         3           4          5           6          7      8      9       10         11         12       13         14        15      16        17
       % Generador: [id, Tipo, Emb. Inicio, Emb. Fin, %Filtración, Eta Turbina, Altura, Pmax, Pmin, Flujo.min, Flujo.max, Vol. Max, Vol. Min, Id. Afluente, Bus, Vol. Ini, Vol. Fin]
        
        %Emb = cEmbalse();
        %nombre_Hidro = strcat('SE_', num2str(red(i,15)),'_VB_', num2str(vn));
        %Emb.inserta_nombre(strcat('H', num2str(id_embalse), '_', nombre_Hidro));
        %Emb.inserta_subestacion(se);
        id = red(i,1);
        Tipo = red(i,2);
        Emb_ini = red(i,3);
        Emb_fin = red(i,4);
        Filtra = red(i,5);
        %Eta_turb = red(i,6);     
        %Altura = red(i,7);
        P_max = red(i,8);
        P_min = red(i,9);
        Flux_min = red(i,10);
        Flux_max = red(i,11);
        %Vol_max = red(i,12);
        %Vol_min = red(i,13);
        %Id_aflu = red(i,14);
        Bus = red(i,15);
        %Vol_ini = red(i,16);
        Vol_fin = red(i,17);
        
        %sep.Embalses(Emb_ini).crea_vertimiento(); %Crea generador(¿?)
        %sep.Embalses(Emb_ini).crea_filtracion(Filtra); %Creo la fltración como un generador.
        
        %sep.Embalses(Emb_ini).tiene_filtracion();
        %sep.Embalses(Emb_ini).es_filtracion(Filtra);
        %sep.Embalses(Emb_ini).inserta_porcentaje_filtracion(Filtra);
        
        %generadores_existente = sep.entrega_generadores();
        %embalses_existente = sep.entrega_embalses();
        
        if Tipo == 0 || Tipo > 3
            error = MException('importa_modelo_chile_4_zonas:main','Error en datos de entrada. Indica que generador no es existente');
            throw(error)
        
        
        elseif Tipo == 1
            for j = 1:n_gene
                nom_gen = sep.Generadores(j).entrega_nombre;
                no_hid = strcat('H', num2str(i),'_SE_', num2str(red(i,15)),'_VB_', num2str(vn));
                if strcmp(nom_gen,no_hid) == 1 %Esta parte esta funcionando
                    if Emb_ini > 0
                        generador_turbina = generadores_existente(j);
                        sep.Embalses(Emb_ini).agrega_turbina_descarga(generador_turbina);%funcion... pero hay que revisar
                        if Emb_fin >0
                            sep.Embalses(Emb_fin).agrega_turbina_carga(generador_turbina);
                        else
                        end
                    else
                    end
                else
                end
            end
        elseif Tipo == 2
            if Emb_fin > 0
                %sep.Embalses(Emb_ini).crea_aporte_adicional();
                %crea vertimiento en el embalse correspondiente
                %sep.Embalses(Emb_fin).crea_aporte_adicional();
                %Entrega el generador vertimiento de dicho embalse
                %sep.Embalses(Emb_ini).agrega_aporte_adicional();
                %Emb.crea_aporte_adicional();
                %Emb.crea_aporte_adicional();
                vert_entr=sep.Embalses(Emb_ini).entrega_vertimiento();
                %Entrega el generador como aporte adicional al embalse
                %final correspondiente
%                 generador_vert = generadores_existente(Emb_ini);
                sep.Embalses(Emb_fin).agrega_aporte_adicional(vert_entr);
                %agrega_aporte_adicional
                
            else
            end
        elseif Tipo == 3
            if Emb_fin > 0
                
                %crea vertimiento en el embalse correspondiente
                %sep.Embalses(Emb_ini).crea_filtracion(Filtra);
                %Debemos entregar el porcentaje de filtración. Lo deje
                %puesto arriba.
                %sep.Embalses(Emb_ini).inserta_porcentaje_filtracion(Filtra);
                %Entrega el generador vertimiento de dicho embalse
                sep.Embalses(Emb_ini).crea_aporte_adicional();
                filtr_entr=sep.Embalses(Emb_ini).entrega_filtracion();
                %Entrega el generador como aporte adicional al embalse
                %final correspondiente (si es que existe)
%                 generador_vert = generadores_existente(Emb_ini);
                sep.Embalses(Emb_fin).agrega_aporte_adicional(filtr_entr);
            else
            end
        else
        end
        
    end
end


%% AQUÍ COMIENZA LA FUNCIÓN IMPORTA BATERÍAS
function importa_baterias(data, sep)
    %              1    2       3      4     5     6         7             8            9
    % Generador: [id, N° BESS, Pmax, Emax, C_pot, C_cap, vida_util, Año_construcción, SOC_min]
	Baterias = data.Baterias;
    Buses = data.Buses;
    [nb, ~] = size(Baterias);
    cant_etapas = 1;
    
    for i = 1:nb
        
        id_bus = Baterias(i,1);
        vn = Buses(id_bus,2);
        existente = Baterias(i,2);
        
        %OJO CON ESTE PUNTO, PUEDE TIRAR UN ERROR
        if existente == 0
            error = MException('importa_modelo_chile_4_zonas:main','Error en datos de entrada. Indica que generador no es existente');
            throw(error)
        end
        %nombre_bus = strcat('SE_', num2str(Generadores(i,2)),'_VB_', num2str(vn));
        nombre_BESS = strcat('SE_', num2str(Baterias(i,1)),'_VB_', num2str(vn));
        se = sep.entrega_subestacion(nombre_BESS, false);
        if isempty(se)
            error = MException('importa_modelo_chile_4_zonas:main','no se pudo encontrar subestación');
            throw(error)
        end
        
        %              1    2       3      4     5     6         7             8           9       10       11
        % Generador: [id, N° BESS, Pmax, Emax, C_pot, C_cap, vida_util, Año_construcción, Emin, Eta_car, Eta_des]
        
        bat = cBateria();
        bat.inserta_nombre(strcat('BESS', num2str(i), '_', nombre_BESS));
        bat.inserta_subestacion(se);
        Pmax = Baterias(i,3);
        Emax = Baterias(i,4);
        C_pot = Baterias(i,5);
        C_cap = Baterias(i,6);
        Vida_util = Baterias(i,7);
        Year_constr = Baterias(i,8);
        SocMin = Baterias(i,9);
        eta_car = Baterias(i, 10);
        eta_descar = Baterias(i, 11);
        %Costo_mwh = Generadores(i,12);
		%tipo_generador = Generadores(i,13);
        
        %OJO, QUE ESTOS TRES SEGUIDOS PUEDEN OCASIONAR ALGÚN PROBLEMA
		evol_capacidad = 0;%Generadores(i,14);
		evol_costos = 0;%Generadores(i,15);
		perfil_ernc = 0;%Generadores(i,16);
        bat.inserta_costo_inversion_potencia(C_pot);
        bat.inserta_costo_inversion_capacidad(C_cap);
        bat.inserta_vida_util(Vida_util);
        bat.inserta_capacidad(Emax);
        bat.inserta_pmax_carga(Pmax);
        bat.inserta_pmax_descarga(Pmax);
        bat.inserta_soc_min(SocMin);
        bat.inserta_eficiencia_carga(1);
        bat.inserta_eficiencia_descarga(1);
        bat.inserta_eficiencia_almacenamiento(1);
        bat.inserta_controla_tension();
        bat.inserta_anio_construccion(Year_constr);
        bat.inserta_eficiencia_carga(eta_car);
        bat.inserta_eficiencia_descarga(eta_descar);
        
        %AQUÍ EMPIEZA A FALLAR... 
% 		bat.inserta_pmax(Pmax);
%         bat.inserta_pmin(0);
%         bat.inserta_costo_mwh(C_cap);
%         bat.inserta_qmin(0);
%         bat.inserta_qmax(Pmax);
%         bat.inserta_p0(Pmax);
%         bat.inserta_q0(Pmax);
%         bat.inserta_controla_tension();
        %bat.inserta_voltaje_objetivo(se.entrega_vn()*Vobj);
        bat.inserta_en_servicio(1);
        %bat.inserta_es_despachable(tipo_generador == 0);
%         if tipo_generador == 1
%             bat.inserta_tipo_central('Eol');
%         else
%             bat.inserta_tipo_central('PV');
%         end
		
		if perfil_ernc > 0
			bat.inserta_indice_adm_escenario_perfil_ernc(perfil_ernc);
			if bat.es_despachable()
				error = MException('importa_modelo_4_zonas:main','generador es convencional pero tiene perfil de ERNC');
				throw(error)
			end
        end
        
        %OJO CON EL SIGUIENTE IF, SE ARRASTRA DESDE EL NÚMERO DE BESS POR
        %LO QUE NO DEBERÍA ENTRAR A ESTE IF
        if existente >0
			bat.Existente = 1;
			se.agrega_bateria(bat);
			sep.agrega_bateria(bat);
			if evol_capacidad
                error = MException('importa_modelo_chile_4_zonas:main','Error en datos de entrada. Hay evolucion de la capacidad de los generadores');
                throw(error)
			end
			if evol_costos
                error = MException('importa_modelo_chile_4_zonas:main','Error en datos de entrada. Hay evolucion en los costos de los generadores');
                throw(error)
			end
        else
            error = MException('importa_modelo_chile_4_zonas:main','Error en datos de entrada. Generador no es existente (es proyectado)');
            throw(error)            
        end
    end
end

function elementos_generados = genera_elementos_red_serie(data,sep,NivelDebug)
    Corredores = data.Corredores;
    [nc, ~] = size(Corredores);

    subestaciones = sep.entrega_subestaciones();
    ElementosBase = cell(nc,0);
    for id_corr = 1:nc
        % primero hay que buscar el voltaje base
        largo = Corredores(id_corr, 3);
        if largo == 0
            ElementosBase(id_corr).Largo = 0;
            ElementosBase = genera_transformadores(ElementosBase, id_corr, data, sep);
        else
            ElementosBase(id_corr).Largo = Corredores(id_corr, 3);
            ElementosBase(id_corr).Elemento = [];

            ElementosBase = genera_lineas(ElementosBase,id_corr, data, sep);            
        end
    end
    
    elementos_generados.ElementosBase = ElementosBase;
    
    if NivelDebug > 0
        Buses = data.Buses;
        % imprime líneas por corredor
        % primero, líneas existentes en el SEP y luego lineas proyectadas
        lineas_existentes = sep.entrega_lineas();
        trafos_existentes = sep.entrega_transformadores2d();

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
                error = MException('importa_modelo_chile_4_zonas:alguna_funcion','No encuentra subestacion de la linea');
                throw(error)
            end
            
            se2 = sep.entrega_subestacion(nombre_bus2, false);
            if isempty(se2)
                error = MException('importa_modelo_chile_4_zonas:alguna_funcion','No encuentra subestacion de la linea');
                throw(error)
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

        if ~correcto
            error = MException('importa_modelo_chile_4_zonas:genera_elementos_red_serie',...
                ['Error de programación. Al imprimir elementos faltan los siguientes: ' elementos_faltantes]);
            throw(error)
        end
        
        % grafica estados
        %close all
        
    end
end

function elementos_generados = genera_elementos_red_paralelo(elementos_generados, data,sep)
    % Crea total de elementos paralelos. 
    % Por ahora sólo baterías. A futuro, serán elementos de compensación de reactivos shunt

	Buses = data.Buses;
    [nb, ~] = size(Buses);

    Baterias = [];
    for id_bus = 1:nb
        % primero hay que buscar el voltaje base
        expansion_bateria = Buses(id_bus, 9);
        if expansion_bateria > 0
            Baterias = genera_baterias(Baterias, id_bus, data, sep);
        end
    end
    elementos_generados.Baterias = Baterias;
end

function ElementosBase = genera_baterias(ElementosBase, id_bus, data, sep)
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
        error = MException('importa_modelo_chile_4_zonas:genera_elementos_paralelos','No se encontro el bus de la bateria. Error de programacion');
        throw(error)
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
                bateria.Texto = ['E_' num2str(bpar)];
            
                %agrega bateria al SEP
                sep.agrega_bateria(bateria);
                se.agrega_bateria(bateria);
            else
                error = MException('importa_modelo_chile_4_zonas:genera_elementos_paralelos','Error en datos de entrada, ya que bateria no es existente');
                throw(error)
            end
        
            if bpar == 1
                ElementosBase(id_bus).Tipo(tipo_bat).Elemento = bateria;
            else
                ElementosBase(id_bus).Tipo(tipo_bat).Elemento= [ElementosBase(id_bus).Tipo(tipo_bat).Elemento; bateria];
            end
        end
    end
end

function ElementosBase = genera_transformadores(ElementosBase, id_corr, data, sep)
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
        error = MException('importa_problema_optimizacion_tnep:genera_transformadores','No se encuentra se1');
        throw(error)
    end
    
    se2 = sep.entrega_subestacion(nombre_bus2);
    if isempty(se2)
        error = MException('importa_problema_optimizacion_tnep:genera_transformadores','No se encuentra se2');
        throw(error)
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
        else
			error = MException('importa_problema_optimizacion_tnep:genera_transformadores','Por ahora sólo transformadores existentes');
			throw(error)
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

function ElementosBase = genera_lineas(ElementosBase, id_corr, data, sep)
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
        error = MException('importa_modelo_chile_4_zonas:genera_lineas','No se pudo encontrar la se1');
        throw(error)
    end

    se2 = sep.entrega_subestacion(nombre_bus2, false);
    if isempty(se2)
        error = MException('importa_modelo_chile_4_zonas:genera_lineas','No se pudo encontrar la se1');
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

    % se van creando las líneas dependiendo del tipo de conductor
    ElementosBase(id_corr).NExistente = nlineas_existentes;
    for lpar = 1:nmax
        % crea primero la línea base. Se separan los casos de líneas ya
        % existentes y los que no
        if lpar <= nlineas_existentes
            % línea existente. 
            id_cond = LineasTotales(lpar, 9);
            
            linea = crea_linea(Conductores(id_cond,:),Corredores(id_corr,:), data.Costos, se1, se2, lpar, id_corr);             

            linea.Existente = true;  % no es necesario pero para mejor comprension
            linea.TipoExpansion = 'Base';
            
            %agrega línea al SEP
            sep.agrega_linea(linea);
            se1.agrega_linea(linea);
            se2.agrega_linea(linea);
            linea.Texto = ['E_' num2str(LineasTotales(lpar, 11))];
        else
            error = MException('importa_modelo_chile_4_zonas:genera_lineas','Error en datos de entrada. Aparece que hay lineas proyectadas');
            throw(error)
        end
        
        % se guarda la línea generada
        ElementosBase(id_corr).Elemento = [ElementosBase(id_corr).Elemento; linea];   
    end
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
% 	if c_uF_km == 0
%     	% hay que modificar este valor para calcular el SIL
%         % para ello, se determina c de tal forma que el límite
%         % térmico sea 3*SIL si la línea tuviera 50 millas de
%         % largo
%         SIL = sth/3;
%         Zc = vn^2/SIL;
%         bpul = x_ohm_km/Zc^2;
%         c_uF_km = bpul/(2 *pi *50)*1000000;
%         linea.inserta_cpul(c_uF_km);
% 	end
%     Zc = sqrt(x_ohm_km/(2*pi*50*c_uF_km)*1000000);
%     SIL = vn^2/Zc;
%     factor_capacidad = entrega_cargabilidad_linea(largo);
%     factor_capacidad = min(3.465, factor_capacidad);
%     sr = round(factor_capacidad*SIL,0);
%     sr = min(sth, sr);
    linea.inserta_sr(sth);%(sr);
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

function bateria = crea_bateria(TipoBateria, se, bpar)
    tipo_bat = TipoBateria(1);
    pmax = TipoBateria(2);
    emax = TipoBateria(3);
    cinv_potencia_mw = TipoBateria(4); %en k$/MW
    cinv_capacidad_mwh = TipoBateria(5); %en k$/MWh
    vida_util = TipoBateria(6);

    cinv_potencia = cinv_potencia_mw*pmax/1000; % en M$
    cinv_capacidad = cinv_capacidad_mwh*emax/1000; % en M$
    bateria = cBateria();
    ubicacion = se.entrega_ubicacion();
    nombre = strcat('S', num2str(bpar), '_B', num2str(ubicacion), '_Sr_', num2str(pmax),'E_', num2str(emax));
	bateria.inserta_nombre(nombre);
    bateria.inserta_subestacion(se);
    bateria.inserta_pmax_carga(pmax);
    bateria.inserta_pmax_descarga(pmax); % por ahora pmax descarga = pmax carga
    bateria.inserta_capacidad(emax);
    bateria.inserta_indice_paralelo(bpar);
    bateria.inserta_tipo_bateria(tipo_bat);
    bateria.inserta_anio_construccion(0);
    bateria.inserta_costo_inversion_potencia(cinv_potencia);
    bateria.inserta_costo_inversion_capacidad(cinv_capacidad);
    bateria.inserta_vida_util(vida_util);
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
