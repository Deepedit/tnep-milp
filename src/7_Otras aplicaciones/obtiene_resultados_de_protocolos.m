limite_1 = 1;
limite_2 = 0.4;
limite_3 = 0.1;

resumen_gap = zeros(500,8);
gap_por_it = zeros(500,50);
for i = 1:length(protocolos)
    [cant_it, ~] = size(protocolos(i).Res);
    resumen_gap(i,1) = cant_it;
    resumen_gap(i,2) = protocolos(i).Res(end,10);
    for j = 1:cant_it
       gap_por_it(i,j) = protocolos(i).Res(j,5);
       if resumen_gap(i,3) == 0 && protocolos(i).Res(j,5) <= limite_1
           resumen_gap(i,3) = j;
           resumen_gap(i,4) = protocolos(i).Res(j,10);
       end
       if resumen_gap(i,5) == 0 && protocolos(i).Res(j,5) <= limite_2
           resumen_gap(i,5) = j;
           resumen_gap(i,6) = protocolos(i).Res(j,10);
       end
       if resumen_gap(i,7) == 0 && protocolos(i).Res(j,5) <= limite_3
           resumen_gap(i,7) = j;
           resumen_gap(i,8) = protocolos(i).Res(j,10);
       end
   end
end

%figure(1)
%plot(max(gap_por_it),'k');
%hold on
%plot(mean(gap_por_it),'k');
%plot(min(gap_por_it),'k');
    