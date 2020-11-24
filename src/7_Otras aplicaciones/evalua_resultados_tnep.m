proyectos_plan_optimo = [];
for i = 1:25
    proy = resultados.MejoresPlanes(1).Plan(i).Proyectos;
    proyectos_plan_optimo = [proyectos_plan_optimo proy];
end

%entrega planes base y cantidad que contienen todos los proyectos del plan óptimo
planes_base = cell(1,0);
planes_base_por_it_y_cantidad = [];
planes_cantidad_por_it_y_cantidad = [];
cantidad_planes_base = 0;
cantidad_planes_cantidad = 0;
cantidad_maxima_proy_para_evaluar = 35;
n_evaluar = 1;
n_actual = 0;
it_plan_evaluar = 0;
for it = 1:length(resultados.PlanesValidosPorIteracionBase) %iteraciones
    for id_plan = 1:length(resultados.PlanesValidosPorIteracionBase(it).Planes); % planes por iteración
        plan = [];
        for etapa = 1:length(resultados.PlanesValidosPorIteracionBase(it).Planes(id_plan).Plan)
            plan = [plan resultados.PlanesValidosPorIteracionBase(it).Planes(id_plan).Plan(etapa).Proyectos];
        end
        if sum(ismember(proyectos_plan_optimo, plan)) == length(proyectos_plan_optimo)
            cantidad_planes_base = cantidad_planes_base + 1;
            planes_base{cantidad_planes_base} = plan;
            planes_base_por_it_y_cantidad(cantidad_planes_base,1) = it;
            planes_base_por_it_y_cantidad(cantidad_planes_base,2) = length(plan);
            planes_base_por_it_y_cantidad(cantidad_planes_base,3) = id_plan; %ranking
            planes_base_por_it_y_cantidad(cantidad_planes_base,4) = resultados.PlanesValidosPorIteracionBase(it).Planes(id_plan).NroPlan;
            planes_base_por_it_y_cantidad(cantidad_planes_base,5) = resultados.PlanesValidosPorIteracionBase(it).Planes(id_plan).TotexTotal; 
            if length(plan) < cantidad_maxima_proy_para_evaluar
                n_actual = n_actual + 1;
                if n_actual == n_evaluar
                    plan_evaluar = resultados.PlanesValidosPorIteracionBase(it).Planes(id_plan);
                    it_plan_evaluar = it;
                end
            end
        end
    end
end

for it = 1:length(resultados.PlanesValidosPorIteracionBLCantidad) %iteraciones
    for id_plan = 1:length(resultados.PlanesValidosPorIteracionBLCantidad(it).Planes); % planes por iteración
        plan = [];
        for etapa = 1:length(resultados.PlanesValidosPorIteracionBLCantidad(it).Planes(id_plan).Plan)
            plan = [plan resultados.PlanesValidosPorIteracionBLCantidad(it).Planes(id_plan).Plan(etapa).Proyectos];
        end
        if sum(ismember(proyectos_plan_optimo, plan)) == length(proyectos_plan_optimo)
            cantidad_planes_cantidad = cantidad_planes_cantidad + 1;
            planes_cantidad_por_it_y_cantidad(cantidad_planes_cantidad,1) = it;
            planes_cantidad_por_it_y_cantidad(cantidad_planes_cantidad,2) = length(plan);
            planes_cantidad_por_it_y_cantidad(cantidad_planes_cantidad,3) = id_plan; %ranking
            planes_cantidad_por_it_y_cantidad(cantidad_planes_cantidad,4) = resultados.PlanesValidosPorIteracionBLCantidad(it).Planes(id_plan).NroPlan;
            planes_cantidad_por_it_y_cantidad(cantidad_planes_cantidad,5) =resultados.PlanesValidosPorIteracionBLCantidad(it).Planes(id_plan).TotexTotal; %ranking
        end
    end
end

