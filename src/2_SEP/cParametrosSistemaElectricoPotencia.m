classdef (Sealed) cParametrosSistemaElectricoPotencia < handle
    % Clase que guarda los parámetros globales del SEP
    properties
        Sbase = 100 % MVA
        %Vbase contiene todos los voltajes bases permisibles. TODO: Al
        %momento de importar el sistema, verificar que Vn en todas las
        %subestaciones/terminales correspondan a alguno de estos valores
        Vbase = [500; 220; 154; 110; 100; 66; 13.2];
        Vmin = [0.9; 0.9; 0.9; 0.9; 0.9; 0.9; 0.9];
        Vmax = [1.1; 1.1; 1.1; 1.1; 1.1; 1.1; 1.1];
        
        AnguloMaximoBuses = 3.14 %rad
    end
    
   methods (Access = private)
      function obj = cParametrosSistemaElectricoPotencia
      end
   end
   
   methods (Static)
      function singleObj = getInstance
         persistent localObj
         if isempty(localObj) || ~isvalid(localObj)
            localObj = cParametrosSistemaElectricoPotencia;
         end
         singleObj = localObj;
      end
   end
   
   methods
      function inserta_sbase(this, val)
          this.Sbase = val;
      end
      function val = entrega_sbase(this)
          val = this.Sbase;
      end
      
      function val = entrega_vmin_vn_pu(this, vn)
          [~,ids] = ismember(vn, this.Vbase);
          if ~isempty(find(ids == 0, 1))
              error = MException('cParametrosSistemaElectricoPotencia:entrega_vmin_vn','Vbase no encontrado');
              throw(error)
          end
          
          val = this.Vmin(ids);
      end
      
      function val = entrega_vmax_vn_pu(this, vn)
          [~,ids] = ismember(vn, this.Vbase);
          if ~isempty(find(ids == 0, 1))
              error = MException('cParametrosSistemaElectricoPotencia:entrega_vmin_vn','Vbase no encontrado');
              throw(error)
          end
          val = this.Vmax(ids);          
      end
      
      function val = entrega_angulo_maximo_buses(this)
          val = this.AnguloMaximoBuses;
      end
	end
end