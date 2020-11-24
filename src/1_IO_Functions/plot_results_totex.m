function plot_results_totex(resultados, min_value)
    itmax = 100;
    cantidad_min = zeros(itmax,1);
    [cantidad_res, ~] = size(resultados.totex_it);
    for i = 1:itmax
        cantidad_min(i) = sum(round(resultados.totex_it(:,i),4) == round(min_value,4))/cantidad_res * 100;
    end
    cantidad_min = [0; cantidad_min];
    plot([0:1:itmax], cantidad_min)
    xlabel('Iteration')
    ylabel('Percentage of runs that reached optimal solution')    
    tasa_asierto = cantidad_min(end)
    r1_tpo_promedio_por_iteracion = mean(resultados.tpo_promedio_por_iteracion) % en segundos
    r2_iteracion_en_llegar_al_optimo = mean(resultados.iteracion_en_llegar_al_optimo)
    r3_tpo_promedio_convergencia = mean(resultados.tiempo_total_convergencia)
    r3_tpo_promedio_convergencia_minutos = r3_tpo_promedio_convergencia/60
    r3_tpo_promedio_convergencia_horas = r3_tpo_promedio_convergencia_minutos/60
%    figure(2)
%    histogram
end
