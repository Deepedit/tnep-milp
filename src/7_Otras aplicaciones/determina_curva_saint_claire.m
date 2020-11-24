function curva = determina_curva_saint_claire()
    % datos de entrada
    x_ohm_km = [0.4880;0.3670];
    b_uS_km = [3.3710;4.5180];
    r_ohm_km = [0.05; 0.037];
    v = [230;345];
    Zc = sqrt(x_ohm_km./b_uS_km*1000000);
    SIL = v.^2./Zc;
    f = 50;

    c_uF_km = b_uS_km/(2*pi*f);

    cond = 1;
    robustez = 50; %kVA
    Buses = [1 v(cond) 1;2 v(cond) 1; 3 v(cond) 1; 4 v(cond) 1];

    StabilityMargin = 0.35;
    VoltageDrop = 0.05;

    e2 = 1;
    t2 = 0;
    
    e1 = 1;
    t1_lim = 44/180*pi;
    
    es = 1;
    
    %crea SEP
    sep = crea_sep(Buses, x_ohm_km, c_uF_km, v, cond, robustez);
    
    lineas = sep.entrega_lineas();
    se = sep.entrega_subestaciones();
    
    for largo = 50:1:600
        %inserta nuevo largo
        lineas(1).inserta_largo(largo);
        lineas(2).inserta_largo(largo);
        lineas(3).inserta_largo(largo);
        
        x1 = complex(0,lineas(1).entrega_reactancia_pu());
        zs = complex(0,lineas(2).entrega_susceptancia_pu());
        zr = compllex(0,lineas(2).entrega_susceptancia_pu());
        z = complex(lineas(2).entrega_resistencia_pu(), lineas(2).entrega_reactancia_pu());
        x2 = complex(0,lineas(3).entrega_reactancia_pu());
        
        Adm = [x1+zs    -zs     0;
               -zs      zs+z+zr zr;
               0        zr      zr+x2;];
           
        D = det(Adm);
        A = (D-x1*((zs+z+zr)*(zr+x2)-zr^2))/D;
        B = zs*zr*x1/D;

        for t1 = 0:0.0001:0.7679
            E1 = complex(e1*cos(t1), e1*sin(t1));
            E2 = complex(e2*cos(t2), e2*sin(t2));
            
            b = abs(B);
            tb = angle(B);
            a = abs(A);
            ta = angle(A);
            
            es = E1*A+E2*B;
            ts = asin(e2*b*sin(tb-t1-ta)/es)+t1+ta;
        end
    end
        
    %márgenes
    
    
    curva = 0
end

function sep = crea_sep(Buses, x_ohm_km, r_ohm_km, c_uF_km, cond, robustez)

    sep = cSistemaElectricoPotencia();

    % crea buses
    [nb, ~] = size(Buses);
    for i = 1:nb
        se = cSubestacion;
        se.inserta_nombre(strcat('SE_',num2str(i)));
        se.inserta_vn(Buses(i, 2));
        sep.agrega_subestacion(se);
    end

    % crea conexiones entre buses 1 y 2
    linea = cLinea();
    nombre = strcat('LC1');
    nombre_bus1 = strcat('SE_1');
    nombre_bus2 = strcat('SE_2');
    se1 = sep.entrega_subestacion(nombre_bus1);
    se2 = sep.entrega_subestacion(nombre_bus2);

    vn = se1.entrega_vn();
    x1 = 100/(sqrt(3)*robustez*vn);
    largo = 1;
    linea.inserta_nombre(nombre);
    linea.agrega_subestacion(se1,1);
    linea.agrega_subestacion(se2,2);
    linea.inserta_xpul(x1);
    linea.inserta_rpul(0);
    linea.inserta_cpul(0);
    linea.inserta_gpul(0);
    linea.inserta_largo(largo);
    
    capacidad = sqrt(3)*vn*1; % por ahora imax se pone en 1
    linea.inserta_sr(capacidad);
    linea.inserta_en_servicio(1);
    linea.inserta_tipo_conductor(cond);
    sep.agrega_linea(linea);
    se1.agrega_linea(linea);
    se2.agrega_linea(linea);

    % crea línea entre buses 2 y 3
    linea = cLinea();
    nombre = strcat('L1_C', num2str(cond));
    nombre_bus1 = strcat('SE_2');
    nombre_bus2 = strcat('SE_3');
    se1 = sep.entrega_subestacion(nombre_bus1);
    se2 = sep.entrega_subestacion(nombre_bus2);

    largo = 50; %largo inicial
    linea.inserta_nombre(nombre);
    linea.agrega_subestacion(se1,1);
    linea.agrega_subestacion(se2,2);
    linea.inserta_xpul(x_ohm_km(cond));
    linea.inserta_rpul(r_ohm_km(cond));
    linea.inserta_cpul(c_uF_km(cond));
    linea.inserta_gpul(0);
    linea.inserta_largo(largo);
    vn = se1.entrega_vn();
    capacidad = sqrt(3)*vn*1; % por ahora imax se pone en 1
    linea.inserta_sr(capacidad);
    linea.inserta_en_servicio(1);
    linea.inserta_tipo_conductor(cond);
    sep.agrega_linea(linea);
    se1.agrega_linea(linea);
    se2.agrega_linea(linea);

    % crea conexiones entre buses 3 y 4
    linea = cLinea();
    nombre = strcat('LC2');
    nombre_bus1 = strcat('SE_1');
    nombre_bus2 = strcat('SE_2');
    se1 = sep.entrega_subestacion(nombre_bus1);
    se2 = sep.entrega_subestacion(nombre_bus2);

    vn = se1.entrega_vn();
    x1 = 100/(sqrt(3)*robustez*vn);
    largo = 1;
    linea.inserta_nombre(nombre);
    linea.agrega_subestacion(se1,1);
    linea.agrega_subestacion(se2,2);
    linea.inserta_xpul(x1);
    linea.inserta_rpul(0);
    linea.inserta_cpul(0);
    linea.inserta_gpul(0);
    linea.inserta_largo(largo);
    
    capacidad = sqrt(3)*vn*1; % por ahora imax se pone en 1
    linea.inserta_sr(capacidad);
    linea.inserta_en_servicio(1);
    linea.inserta_tipo_conductor(cond);
    sep.agrega_linea(linea);
    se1.agrega_linea(linea);
    se2.agrega_linea(linea);
    
end