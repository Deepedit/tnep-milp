function plan = crea_plan_en_base_a_feromonas(feromonas)

tope_probabilidad = 50; %porciento
[no_etapas, no_proyectos] = size(feromonas);
proyectos_totales = [];
cant_proyectos_totales = 0;
%plan por id
for i = 1:no_etapas
    fer = feromonas(i,:);
    [fer_ord, indices] = sort(fer, 'descend');
    minimo = min(fer_ord);
    id = fer_ord > minimo;
    proyectos = indices(id);
    if cant_proyectos_totales > 0
        proyectos(ismember(proyectos, proyectos_totales)) = [];
    end
    for j = 1:length(proyectos)
        cant_proyectos_totales = cant_proyectos_totales + 1;
        proyectos_totales(cant_proyectos_totales, 1) = i;
        proyectos_totales(cant_proyectos_totales, 2) = proyectos(j);
    end
end
plan.por_id = proyectos_totales;

% por porcentaje
% proyectos_totales = [];
% cant_proyectos_totales = 0;
% for i = 1:no_etapas
%     fer = feromonas(i,:);
%     [fer_ord, indices] = sort(fer, 'descend');
%     prob = fer_ord/sum(fer_ord)*100;
%     cum_prob = zeros(1,no_proyectos);
%     for j = 1:length(prob)
%         if j == 1
%             cum_prob(j) = prob(j);
%         else
%             cum_prob(j) = cum_prob(j-1)+prob(j);
%         end
%     end
%     
%     minimo = min(fer_ord);
%     id = fer_ord > minimo;
%     proyectos = indices(id);
%     if cant_proyectos_totales > 0
%         proyectos(ismember(proyectos, proyectos_totales)) = [];
%     end
%     for j = 1:length(proyectos)
%         cant_proyectos_totales = cant_proyectos_totales + 1;
%         proyectos_totales(cant_proyectos_totales, 1) = i;
%         proyectos_totales(cant_proyectos_totales, 2) = proyectos(j);
%     end
% end

        
    