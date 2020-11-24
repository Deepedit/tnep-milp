%load('C:\Users\ra\Desktop\ram\Nuevo_desde_robo\Publicaciones\201703 - Ant Colony Optimization for Multistage TNEP\Resultados\Nuevos resultados\scalability.mat')
close all
errorbar(x, yur_av,err_neg, err_pos,'o')
hold on
errorbar(x, ybase_av,err_neg_base, err_pos_base,'x')
%x = 0:0.1:10;
legend('includinig uprating options', 'without uprating options')

fplot(@(x) lin_ur.p1*x +lin_ur.p2, [1 9],'k')
fplot(@(x) lin_base.p1*x +lin_base.p2,[1 9],'k')

ylabel('Time (hours)')
xlabel('Number of operating conditions')
