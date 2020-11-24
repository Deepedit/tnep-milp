function importa_escenario_expansion(sep_base, adm_proy, pAdmOp, pParOpt)

    %lee subestaciones
	[~,~,raw] = xlsread('.\input\SEP','Subestaciones');
    
    contador = 0;
    for i = 2:length(raw)
        contador = contador + 1;
        subestacion = cSubestacion();
        nombre = raw(i,2);
        voltaje = cell2mat(raw(i,3));
        posx = cell2mat(raw(i,4));
        posy = cell2mat(raw(i,5));
        etapa = cell2mat(raw(i,6));  % por ahora no se utiliza, ya que no hay grado de libertad aquí
        
        subestacion.Nombre = nombre;
        subestacion.Id = contador;
        subestacion.Voltaje = voltaje;
        subestacion.PosX = 1.0;
        subestacion.PosY = 1.0;
        
        if etapa == 1
            sep_base.agrega_subestacion(subestacion);
        else
            % nada aún
            % eventualmente se puede agregar a los proyectos, en caso de que
            % se contemple la incorporación de una nueva subestación como
            % proyecto o como proyecto obligatorio
        end
    end

    %lee corredores y lineas
	[~,~,raw] = xlsread('.\input\SEP','Corredores');
    
    %indice_lineas = 0;
    indice_proyectos = 0;
    contador = 0;
    for i = 2:length(raw)
        codigo_base = raw(i,2);
        voltaje = cell2mat(raw(i,3));
        
        SE1 = sep_base.entrega_subestacion(raw(i,4));
        SE2 = sep_base.entrega_subestacion(raw(i,5));

        id_se_1 = SE1.Id;
        id_se_2 = SE2.Id;
        
        %parámetros técnicos de las lineas
        rpu = cell2mat(raw(i,6));
        xpu = cell2mat(raw(i,7));
        largo = cell2mat(raw(i,8));
        capacidad = cell2mat(raw(i,9));
        costo = cell2mat(raw(i,10));
        nro_lineas_existentes = cell2mat(raw(i,11));
        nro_max_lineas = cell2mat(raw(i,12));
        
        proy_dependiente = 0;
        
        for j = 1:nro_max_lineas
            contador = contador + 1;
            linea = cLinea;
            linea.Nombre = strcat('L_', num2str(id_se_1), '_', num2str(id_se_2), '_',num2str(j));
            linea.Id = contador;
            linea.IndiceParalelo = j;
            linea.agrega_subestacion(SE1,1);
            linea.agrega_subestacion(SE2,2);
            linea.Voltaje = voltaje;
            linea.Largo = largo;
			linea.Costo = costo;
			linea.Capacidad = capacidad;
			linea.Xpu = xpu;
			linea.Rpu = rpu;
			
            if j <= nro_lineas_existentes
                sep_base.agrega_linea(linea);
                SE1.agrega_linea(linea);
                SE2.agrega_linea(linea);
                
            else
                indice_proyectos = indice_proyectos + 1;
                proy.Linea = linea;
                proy.Indice = indice_proyectos;
                proy.IndiceDependencia = 0;
                if j == nro_lineas_existentes + 1
                    proy_dependiente = indice_proyectos;
                    proy.TieneDependencia = false;
                else
                    proy.TieneDependencia = true;
                    proy.IndiceDependencia = proy_dependiente;
                    proy_dependiente = indice_proyectos;
                end

                adm_proy.agrega_proyecto(proy);
            end
        end
    end
    
    %lee generadores
	[~,~,raw] = xlsread('.\input\SEP','Generacion');
    contador = 0;
    for i = 2:length(raw)
        nombre = raw(i,1);
        nombre_se = raw(i,2);
        capacidad = cell2mat(raw(i,3));
        costo = cell2mat(raw(i,4));
        etapa = cell2mat(raw(i,5));

        if etapa == 1
            contador = contador + 1;
            generador = cGenerador;
            generador.Nombre = nombre;
            generador.Id = contador;
            generador.Despachable = true;  %falta actualizar
            SE = sep_base.entrega_subestacion(nombre_se);
            id_se = SE.Id;
            generador.SE = SE;
            generador.Pmax(1) = capacidad;
            generador.Snom(1) = capacidad;
            generador.Cosp(1) = 1;
            generador.TipoCentral = 'T';
            generador.Costo_MWh = costo;
            sep_base.agrega_generador(generador);
            SE.agrega_generador(generador);
        else
            % generador ya existe. Sólo falta ingresar capacidad en las
            % siguientes etapas
            if pParOpt.CantidadEtapas >= etapa
                % sólo se agrega información si cantidad de etapas es mayor
                % que etapa actual
                generador = sep_base.entrega_generador(nombre);
                generador.Pmax(etapa) = capacidad;
                generador.Snom(etapa) = capacidad;
                generador.Cosp(etapa) = 1;
            end
        end           
    end

    %lee consumos
    % por ahora en consumos contiene el consumo, pero en teoría debiera ir
    % Pmax y eventualmente Cosp. Los datos de operación se guardan en
    % cAdministradorEscenariosOperacion
	[~,~,raw] = xlsread('.\input\SEP','Demanda');
    
    contador = 0;
    for i = 2:length(raw)
        etapa = cell2mat(raw(i,4));
        nombre = raw(i,1);
        demanda = cell2mat(raw(i,3));
        if etapa == 1
            contador = contador + 1;
            consumo = cConsumo;
            consumo.Nombre = nombre;
            consumo.Id = contador;
            SE = sep_base.entrega_subestacion(cell2mat(raw(i,2)));
            consumo.SE = SE;
            consumo.Pmax(1) = demanda;
            consumo.Cosp(1) = 1;
            sep_base.agrega_consumo(consumo);
            SE.agrega_consumo(consumo);
            indice = pAdmOp.ingresa_nuevo_consumo(nombre);
            pAdmOp.agrega_consumo(indice, etapa, 1, demanda)  %para estos datos sólo hay un punto de operación (tercer parámetro)
            consumo.IndiceOperacion = indice;
        else
            % consumo ya existe. Sólo falta ingresar capacidad en las
            % siguientes etapas si corresponde
            if pParOpt.CantidadEtapas >= etapa
                consumo = sep_base.entrega_consumo(nombre);
                consumo.Pmax(etapa) = demanda;
                consumo.Cosp(etapa) = 1;
                indice = consumo.IndiceOperacion;
                pAdmOp.agrega_consumo(indice, etapa, 1, demanda)  % por ahora sólo hay un punto de operación (tercer parámetro)
            end
        end           
    end
end
