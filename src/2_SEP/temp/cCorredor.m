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
		
        %par�metros t�cnicos
        Voltaje
		
		%Indice para b�squeda r�pida
		%Indice
    end
	
	methods
		function agrega_linea(obj,linea)
			obj.Lineas = [obj.Lineas, linea];
		end
	end
end

    