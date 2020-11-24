function imprime_resultados_aco(resultados)

id_figura = 0;
id_figura = id_figura + 1;
figure(id_figura)
hold off
%grafica evolución total
plot(resultados.MejorResultadoGlobal);
hold on
plot(resultados.MejorResultadoIteracion,'g')
title('Evolucion')
legend('Mejor resultado global', 'Mejor resultado iteracion')

id_figura = id_figura + 1;
figure(id_figura)
% evolución totex planes generados
totex = [];
limite_iteracion = [];
cum = 0;

for i = 1:length(resultados.PlanesValidosPorIteracion)
    planes_it = resultados.PlanesValidosPorIteracion(i).Planes;
    [~,indice]=sort([planes_it.NroPlan]);
	planes_it = planes_it(indice);
    for j = 1:length(planes_it)
        totex(end+1) = planes_it(j).TotexTotal;
    end
    cum = cum + length(resultados.PlanesValidosPorIteracion(i).Planes);
    limite_iteracion(i) = cum;
end
plot(totex)
hold on
max_totex = max(totex);
min_totex = min(totex);
for i = 1:length(limite_iteracion)
    plot([limite_iteracion(i) limite_iteracion(i)], [0 max_totex*1.05], 'k');
end
axis([0 length(totex) min_totex*0.9 max_totex*1.05]);
title('Evolucion totex planes generados')

% imprime resultados bl secuencial
id_figura = id_figura + 1;
figure(id_figura)
totex = [];
limite_iteracion = [];
cum = 0;

for i = 1:length(resultados.PlanesValidosPorIteracionBLSecuencial)
    planes_it = resultados.PlanesValidosPorIteracionBLSecuencial(i).Planes;
    [~,indice]=sort([planes_it.NroPlan]);
	planes_it = planes_it(indice);
    for j = 1:length(planes_it)
        totex(end+1) = planes_it(j).TotexTotal;
    end
    cum = cum + length(resultados.PlanesValidosPorIteracionBLSecuencial(i).Planes);
    limite_iteracion(i) = cum;
end
plot(totex)
hold on
max_totex = max(totex);
min_totex = min(totex);
for i = 1:length(limite_iteracion)
    plot([limite_iteracion(i) limite_iteracion(i)], [0 max_totex*1.05], 'k');
end
axis([0 length(totex) min_totex*0.9 max_totex*1.05]);
title('Evolucion totex planes generados bl cantidad')

id_figura = id_figura + 1;
figure(id_figura)
totex = [];
limite_iteracion = [];
cum = 0;

for i = 1:length(resultados.PlanesValidosPorIteracionBLCantidad)
    planes_it = resultados.PlanesValidosPorIteracionBLCantidad(i).Planes;
    [~,indice]=sort([planes_it.NroPlan]);
	planes_it = planes_it(indice);
    for j = 1:length(planes_it)
        totex(end+1) = planes_it(j).TotexTotal;
    end
    cum = cum + length(resultados.PlanesValidosPorIteracionBLCantidad(i).Planes);
    limite_iteracion(i) = cum;
end
plot(totex)
hold on
max_totex = max(totex);
min_totex = min(totex);
for i = 1:length(limite_iteracion)
    plot([limite_iteracion(i) limite_iteracion(i)], [0 max_totex*1.05], 'k');
end
axis([0 length(totex) min_totex*0.9 max_totex*1.05]);
title('Evolucion totex planes generados bl cantidad')

end
