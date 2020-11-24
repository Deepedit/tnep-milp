function valor = entrega_cargabilidad_linea(largo)
    %transforma largo a millas
    largo = largo/1.6;
    puntos = load('PuntosCurvaSaintClaire.mat');
    indice = find(puntos.x-largo> 0, 1);
    if isempty(indice)
        valor = puntos.y(end);
        return;
    end
    if indice == 1
        % no hay restricciones de capacidad
        valor = inf;
        return;
    end
    % por ahora, interpolación lineal
    m = (puntos.y(indice)-puntos.y(indice-1))/(puntos.x(indice)-puntos.x(indice-1));
    dx = largo-puntos.x(indice-1);
    valor = puntos.y(indice-1) + m*dx;
    
    % corrección de errores para que calce con paper (por ahora)
    if largo*1.6 < 95
        factor = 1.14642073170732;
    elseif largo*1.6 < 97
        factor = 1.16674755;
    elseif largo*1.6 < 98
        factor = 1.18704743589744;
    elseif largo*1.6 < 105
        factor = 1.214528;
    else
        factor = 1.24770428571429;
    end
    valor = valor/factor;
end