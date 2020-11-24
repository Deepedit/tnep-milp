function resumen = analiza_resultados_tnep_aco(path, minimo)
    contador = 0;
    nmax = 1000;
    %nmax = 100;
    itmax = 100;
    resumen.totex_it = zeros(nmax, itmax);
    resumen.id_fallida = [];
    resumen.it_fallida = [];
    resumen.tpo_promedio_por_iteracion = zeros(nmax, 1);
    resumen.tiempo_total_convergencia = zeros(nmax, 1);
    resumen.iteracion_en_llegar_al_optimo = zeros(nmax, 1);
%    resumen.tpo_iteraciones_base = cell(nmax, 0);
%    resumen.tpo_iteraciones_bl = cell(nmax, 0);
%    resumen.tpo_total_iteraciones = cell(nmax, 0);
    nombre_base = [path '\TNEP_ACO_118_Base_'];
    for i = 1:nmax
        nombre = [nombre_base num2str(i) '.mat'];
        %nombre = [nombre_base num2str(i)];
        if exist(nombre,'file') == 2
            contador = contador + 1;
            %resultados = load(nombre, '-mat');
            resultados = load(nombre);
            total_it_res = length(resultados.MejorResultadoGlobal);
            %resumen.tiempo_total_convergencia(contador) = find(resultados.MejorResultadoGlobal == min(resultados.MejorResultadoGlobal),1);
            resumen.iteracion_en_llegar_al_optimo(contador) = total_it_res;
            if round(resultados.MejorResultadoGlobal(total_it_res),4) > round(minimo,4)
                resumen.id_fallida(end+1) = i;
                resumen.it_fallida(end+1) = total_it_res;
            end
            for j = 1:itmax
                if j <= total_it_res
                    valor = resultados.MejorResultadoGlobal(j);  
                    mejor_valor = valor;
                else
                    valor = mejor_valor;
                end
                resumen.totex_it(contador,j) = valor;
            end
            resumen.tpo_iteraciones_base(contador).Tiempos = resultados.TiempoBase;
            promedio_trimmed = trimmean(resumen.tpo_iteraciones_base(contador).Tiempos, 90);
            resumen.tpo_iteraciones_base(contador).Tiempos(resumen.tpo_iteraciones_base(contador).Tiempos > promedio_trimmed) = [];
            
            resumen.tpo_iteraciones_bl(contador).Tiempos = resultados.TiempoBusquedaLocalEliminaDesplaza;
            promedio_trimmed = trimmean(resumen.tpo_iteraciones_bl(contador).Tiempos, 90);
            resumen.tpo_iteraciones_bl(contador).Tiempos(resumen.tpo_iteraciones_bl(contador).Tiempos > promedio_trimmed) = [];
            
            resumen.tpo_total_iteraciones(contador).Tiempos = resultados.TiempoBase + resultados.TiempoBusquedaLocalEliminaDesplaza;
            promedio_trimmed = trimmean(resumen.tpo_total_iteraciones(contador).Tiempos, 90);
            resumen.tpo_total_iteraciones(contador).Tiempos(resumen.tpo_total_iteraciones(contador).Tiempos > promedio_trimmed) = [];

            resumen.tpo_promedio_por_iteracion(contador) = mean(resumen.tpo_total_iteraciones(contador).Tiempos);
            resumen.tiempo_total_convergencia(contador) = resumen.tpo_promedio_por_iteracion(contador)*total_it_res;
        end
    end
    resumen.totex_it = resumen.totex_it(1:contador, :);
    resumen.tpo_promedio_por_iteracion = resumen.tpo_promedio_por_iteracion(1:contador,:);
    resumen.tiempo_total_convergencia= resumen.tiempo_total_convergencia(1:contador,:);
    resumen.iteracion_en_llegar_al_optimo = resumen.iteracion_en_llegar_al_optimo(1:contador,:);
%    resumen.tpo_iteraciones_base = resumen.tpo_iteraciones_base(1:contador,:);
%    resumen.tpo_iteraciones_bl = resumen.tpo_iteraciones_bl(1:contador,:);
%    resumen.tpo_total_iteraciones = resumen.tpo_total_iteraciones(1:contador,:);
end