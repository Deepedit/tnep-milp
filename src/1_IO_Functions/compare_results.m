function compare_results(res_fp, res_mp)
    % compare results bus data
    bus_mp = res_mp.bus;
    bus_fp = res_fp.bus;

    
    delta_p_inyeccion = bus_mp(:,3)-bus_fp(:,3);
    delta_q_inyeccion = bus_mp(:,4)-bus_fp(:,4);
    delta_vpu = bus_mp(:,8)-bus_fp(:,8);
    delta_theta = bus_mp(:,9)-bus_fp(:,9);
    
    gen_mp = res_mp.gen;
    gen_fp = res_fp.gen;
    delta_p_gen = gen_mp(:,2)-gen_fp(:,2);
    delta_q_gen = gen_mp(:,3)-gen_fp(:,3);
    
    prot = cProtocolo.getInstance;
    prot.imprime_texto('Comparación resultados\n');
    
    texto = ['Maxima diferencia P inyeccion bus' num2str(sum(delta_p_inyeccion)) ' MW'];
    prot.imprime_texto(texto)
    texto = ['Maxima diferencia Q inyeccion bus' num2str(sum(delta_q_inyeccion)) ' MW'];
    prot.imprime_texto(texto)
    
    texto = ['Maxima diferencia V p.u.' num2str(max(delta_vpu))];
    prot.imprime_texto(texto)

    texto = ['Maxima diferencia Angulo' num2str(max(delta_theta))];
    prot.imprime_texto(texto)
    
    vpu_buses = [bus_mp(:,8) bus_fp(:,8)];
    theta_buses = [bus_mp(:,9) bus_fp(:,9)];
    prot.imprime_matriz(vpu_buses, 'V buses mp - V Buses fp');
    prot.imprime_matriz(theta_buses, 'Theta buses mp - Theta Buses fp');
end