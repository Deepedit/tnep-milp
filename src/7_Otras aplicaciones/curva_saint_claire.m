function curva = curva_saint_claire()
    % datos de entrada
	% idealmente hacerlo para más de un conductor. Para ello, agregar los parámetros de los otros conductores a los vectores abajo
    x_ohm_km = [0.4880];
    b_uS_km = [3.3710];
    r_ohm_km = [0.05];
    v = [230];
    Zc = sqrt(x_ohm_km./b_uS_km*1000000);
    SIL = v.^2./Zc;
    f = 50;

    c_uF_km = b_uS_km/(2*pi*f);

    cond = 1;
	
	% idem a los conductores, la idea es evaluar distintos tipos de redes en cuanto a robustez
    robustez = 50; %kVA
    Buses = [1 v(cond) 1;2 v(cond) 1; 3 v(cond) 1; 4 v(cond) 1];

    StabilityMargin = 0.35;
    VoltageDrop = 0.05;

    e2 = 1;
    t2 = 0;
    
    e1 = 1;
    t1_lim = 44/180*pi;
    
    es = 1;
    
    for largo = 50:1:600
		% metodología
	end
end
