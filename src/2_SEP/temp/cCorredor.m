classdef cCorredor < handle
        % clase que representa las lineas de transmision
    properties
        %datos generales
        Nombre
        Codigo
        SE1
		SE2
		Lineas
		NroMaxLineas
		
        %parámetros técnicos
        Voltaje
		
		%Indice para búsqueda rápida
		%Indice
    end
	
	methods
		function agrega_linea(obj,linea)
			obj.Lineas = [obj.Lineas, linea];
		end
	end
end

    