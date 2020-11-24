classdef cParametrosFlujoPotencia
        % clase que representa las subestaciones
    properties
        % Número de iteraciones sin cambios en tipo de buses
        % buses de PU a PQ
        MaxNumIter = 30
        NumIterSinCambioPVaPQ = 4
        NumIterDesacoplado = 0
        MaxErrorMW = 0.00001
		PorcCargaCriterioN1 = 0.5
        
        DiscretizaTapCondensadoresReactores = false % si es false, se utiliza para programas de expansión cuyo objetivo es dimensionar los condensadores y reactores
        DiscretizaTapTransformadoresReguladores = false % idem anterior
    end 
end