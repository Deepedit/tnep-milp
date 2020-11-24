clear
close all
clc

syms x ds

restDelta = 44; %[grados]
restDelta = restDelta*pi/180; %Se pasa a [rad]

restVolt = 0.95; % [pu]

modEs = 1;
modE2 = 1; %referencia del sistema

Zbase = (345e3)^2/(100e6);

Z1 = 0.333*1i/100;
Z2 = 0.333*1i/100;
%Z1 = 1e-6;
%Z2 = 1e-6;

z = (0.00571 + 1i*0.06432)/100;
y = 1i*0.6604/100;

Zc = sqrt(z/y);

SIL = 1/abs(Zc);

propa = sqrt(y*z);

largo = 50:10:600;
delta = 0.6649:pi/45:1.6443;
% delta = 0:pi/45:pi;
Sr = zeros(1, length(largo));

for i = 1:1:length(largo)
    Z = largo(i)*z;
    Y = largo(i)*y/2;
%         Z = Zc*sinh(propa*largo(i));
%         Y = (cosh(propa*largo(i))-1)/(Zc*sinh(propa*largo(i)));
    
    Zs = 1/Y;
    ImpMatrix = [[Z1+Zs,-Zs,0];[-Zs,Z+2*Zs,Zs];[0,Zs,Zs+Z2]];
   
    if largo(i) == 100
       test = 1
       
    end
    for j =1:1:length(delta)
        
        beta = Zs^2/((2*Zs+Z)*(Zs+Z2)-Zs^2);
        b1 = real(beta);
        b2 = imag(beta);
        
        eta = ((Zs+Z2)*beta-(Z1+Zs))/Z1;
        n1 = real(eta);
        n2 = imag(eta);
        
        k1 = real(eta+1);
        k2 = imag(eta+1);
        
        
        [modE1,Ds] = vpasolve([x*(k1*cos(delta(j))-k2*sin(delta(j)))-n1*cos(ds)+n2*sin(ds)-b1, x*(k2*cos(delta(j))+k1*sin(delta(j)))-n2*cos(ds)-n1*sin(ds)-b2==0],[x,ds],[1,pi/2]);
        modE1 = double(modE1);
        Ds = double(Ds);
        
        I = ImpMatrix^-1*[modE1*exp(delta(j)*1i);0;1];
        Er = 1-I(3)*Z2;
        
        if abs(modEs-abs(Er)) > 1-restVolt
            Sr(1, i) = -Er*conj(I(3));
            break
        elseif angle(Er)-Ds > -restDelta
            Sr(1, i) = -Er*conj(I(3));
            break
        end
    end
end

xclair = [60, 80, 140, 180, 260, 400, 580];
yclair = [2.8, 2.3, 1.7, 1.4, 1.1, 0.8, 0.6];

figure(1)
plot(largo, real(Sr)./SIL)
grid on
%axis([0 600 0 3.5])
hold on
plot(xclair, yclair, '--r')
xlabel('Largo [millas]')
ylabel('Cargabilidad %SIL')
title('Curva St. Clair línea de 345 [kV]')