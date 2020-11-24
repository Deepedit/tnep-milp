function vector = convierte_decimal_a_binario(nro_decimal,cantidad_digitos)
    vector = zeros(1, cantidad_digitos);
    q = floor(nro_decimal/2);
    r = rem(nro_decimal,2);
    id = 1;
    vector(id) = r;
    while q >= 2
        id = id + 1;
        nro_decimal = q;
        q = floor(nro_decimal/2);
        r = rem(nro_decimal,2);
        vector(id) = r;
    end
    if q ~= 0
        vector(id+1) = q;
    end
end