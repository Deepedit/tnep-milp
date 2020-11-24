function [resultados_proyectos, resultados_sigmas] = analiza_resultados_mcmc(path, id_caso)
    % importa resultados de cadenas principales
    %path = 'C:\Users\ra\Desktop\ram\Nuevo_desde_robo\Publicaciones\2018 - MCMC incertidumbre\Pruebas\Nuevos_resultados_Fevalencia\resultados_sim_id_1_cadena_1_ppal.txt';
    close all
    plan_optimo = [3 68; 8 67; 8 69; 8 70; 10 9; 11 65; 12 64; 13 21; 13 77; 13 87; 14 12; 14 91; 14 93; 15 59; 15 62; 15 63; 15 76];
    cantidad_acierto = [0 0; 0.1 0; 0.5 0; 1 0]; %en porcentaje
    [ntasas, ~] = size(cantidad_acierto);
    tasa_cambio = zeros(20,1);
    id_cadena_principal = 0;
    resultados_sigmas = cell(20,1);
    resultados_totex = cell(20,1);
    evolucion_sigma_es_igual = true;
    for id_cadena = 1:5:96
        id_cadena_principal = id_cadena_principal + 1;
        filename = [path 'resultados_sim_id_' num2str(id_caso) '_cadena_' num2str(id_cadena) '_ppal.txt'];
        delimiter = ' ';
        startRow = 2;
        formatSpec = '%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%[^\n\r]';
        fileID = fopen(filename,'r');
        dataArray = textscan(fileID, formatSpec, 'Delimiter', delimiter, 'MultipleDelimsAsOne', true, 'EmptyValue' ,NaN,'HeaderLines' ,startRow-1, 'ReturnOnError', false);
        fclose(fileID);
        %res_proy_cadena = zeros(1000, 95);
res_proy_cadena = zeros(2000, 95);        
        res_totex_cadena = zeros(2000,1);
        res_sigmas_cadena = zeros(11,95);
        resultados_cadena = [dataArray{1:end-1}];
        res_totex_cadena = resultados_cadena(:, 2);
        for proy = 1:95
            col = 5 + 2*(proy-1);
            %res_proy_cadena(:,proy) = resultados_cadena(1001:end, col);
res_proy_cadena(:,proy) = resultados_cadena(1:end, col);            
            res_sigmas_cadena(1,proy) = 5;
            paso_sigma = 1;
            for j = 100:100:1000
                paso_sigma = paso_sigma + 1;
                res_sigmas_cadena(paso_sigma,proy) = resultados_cadena(j+1, col+1);
            end
        end
        resultados_sigmas{id_cadena_principal} = res_sigmas_cadena;
        resultados_totex{id_cadena_principal} = res_totex_cadena;
        if id_cadena == 1
            resultados_proyectos = res_proy_cadena;
        else
            resultados_proyectos = [resultados_proyectos; res_proy_cadena];
        end
        if id_cadena > 1 && evolucion_sigma_es_igual
            evolucion_sigma_es_igual = sum(sum(resultados_sigmas{id_cadena_principal}-resultados_sigmas{1} ~= 0)) == 0;
        end
            
        best_totex_cadena = min(resultados_cadena(1:end, 2));
        tasa_cambio(id_cadena_principal) = sum(resultados_cadena(1:end, 3))/1000;
        for i = 1:ntasas
           gap = round((best_totex_cadena-3146.6811)/3146.6811*100,4);
           if gap <= cantidad_acierto(i,1)
               cantidad_acierto(i,2) = cantidad_acierto(i,2) + 1;
           end 
        end
        clearvars filename delimiter startRow formatSpec fileID dataArray ans;
        
    end
    tasas_acierto = cantidad_acierto;
    tasas_acierto(:,2) = tasas_acierto(:,2)/20;
    
    resultados_proyectos(resultados_proyectos == 0) = 16;
    proyectos_plan_optimo = plan_optimo(:,2);
    todos_los_proyectos = 1:1:59;
    todos_los_proyectos = todos_los_proyectos';
    proyectos_no_en_optimo = todos_los_proyectos(~ismember(todos_los_proyectos,proyectos_plan_optimo));
    nuevo_subplot = true;
    figura_actual = 0;
    id_subplot_actual = 1;
    proyectos_plot = [proyectos_plan_optimo; proyectos_no_en_optimo];
    etapas_plot = plan_optimo(:,1);
    etapas_plot = [etapas_plot; zeros(length(proyectos_no_en_optimo),1)];

    %grafica histogramas
    for i = 1:length(proyectos_plot)
        if nuevo_subplot
            figura_actual = figura_actual + 1;
            figure(figura_actual)
            id_subplot_actual = 1;
            nuevo_subplot = false;
        else
            id_subplot_actual = id_subplot_actual + 1;
            if id_subplot_actual == 8
                nuevo_subplot = true;
                
            end
        end
        subplot(4,2,id_subplot_actual);
        histogram(resultados_proyectos(:,proyectos_plot(i)), 'BinMethod','integers','BinLimits',[1,17]);
        title(['Proy ' num2str(proyectos_plot(i)) '(optimo: ' num2str(etapas_plot(i)) ')']);
    end
    
    % grafica evolución temporal
    nuevo_subplot = true;
    for i = 1:length(proyectos_plot)
        if nuevo_subplot
            figura_actual = figura_actual + 1;
            figure(figura_actual)
            id_subplot_actual = 1;
            nuevo_subplot = false;
        else
            id_subplot_actual = id_subplot_actual + 1;
            if id_subplot_actual == 8
                nuevo_subplot = true;
                
            end
        end
        subplot(4,2,id_subplot_actual);
        plot(resultados_proyectos(:,proyectos_plot(i)),'x');
        ylim([0 17])
        title(['Evol. proy ' num2str(proyectos_plot(i)) '(optimo: ' num2str(etapas_plot(i)) ')']);
    end

%    grafica sigmas
    nuevo_subplot = true;
    for i = 1:length(proyectos_plot)
        if nuevo_subplot
            figura_actual = figura_actual + 1;
            figure(figura_actual)
            id_subplot_actual = 1;
            nuevo_subplot = false;
        else
            id_subplot_actual = id_subplot_actual + 1;
            if id_subplot_actual == 8
                nuevo_subplot = true;
            end
        end
        subplot(4,2,id_subplot_actual);
        for j = 1:20
            plot(resultados_sigmas{j}(:,proyectos_plot(i)));
            ylim([0 25])
            if j == 1;
                title(['Sigma proy ' num2str(proyectos_plot(i)) '(optimo: ' num2str(etapas_plot(i)) ')']);
                hold on;
            end
        end
    end
    
    % resultado totex cadenas
    nuevo_subplot = true;
    for j = 1:20
        if nuevo_subplot
            figura_actual = figura_actual + 1;
            figure(figura_actual)
            id_subplot_actual = 1;
            nuevo_subplot = false;
        else
            id_subplot_actual = id_subplot_actual + 1;
            if id_subplot_actual == 8
                nuevo_subplot = true;
            end
        end
        subplot(4,2,id_subplot_actual);
        plot(resultados_totex{id_cadena_principal});
        if j == 1;
            title(['Evol totex cadena ' num2str(j)]);
            hold on;
        end
    end
    
    for i = 1:ntasas
        disp(['Tasa acierto ' num2str(tasas_acierto(i,1)) '% gap: ' num2str(tasas_acierto(i,2)) ' (' num2str(cantidad_acierto(i,2)) '/20)'])
    end
    disp(['tasa cambio min: ' num2str(min(tasa_cambio))]);
    disp(['tasa cambio max: ' num2str(max(tasa_cambio))]);    
    disp(['tasa cambio promedio: ' num2str(mean(tasa_cambio))]);
    disp(['tasa cambio std dev : ' num2str(std(tasa_cambio))]);
    if evolucion_sigma_es_igual
        disp('Evolucion de los sigmas es igual para todas las cadenas, y todos los proyectos');
    else
        disp('Hay diferencias en la evolucion de los sigmas entre las cadenas');
    end
end