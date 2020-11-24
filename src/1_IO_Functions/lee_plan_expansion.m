function data = lee_plan_expansion(archivo, hoja)
    filename = archivo;

    num = xlsread(filename, hoja);
    inicio = 1;
    while isnan(num(inicio,1))
        inicio = inicio + 1;
    end    
    [n, m] = size(num);
    plan = zeros(n,m);
    for fila = inicio:n
        for col = 1:m
            plan(fila, col) = num(fila,col);
        end
    end
    data.Plan = plan;
end