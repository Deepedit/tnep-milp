classdef cAlmacenamiento < cElementoRed
        % clase que representa los transformadores
    properties 
        %parámetros técnicos
		EMax
        EMin
        EInicial
        Eficiencia = 1
        
        % Turbinas de carga y descarga. Estas deben haber sido definidas
        % como Generadores y agregadas al SEP (generan potencia eléctrica)
        TurbinasCarga = cGenerador.empty
        TurbinasDescarga = cGenerador.empty
        
        % Vertimiento y Filtración quitan energía del almacenamiento. 
        % Si bien estas variables se modelan como generadores, NO DEBEN IR AGREGADAS AL SEP. Sólo "existen" dentro de cada embalse
        Vertimiento = cGenerador.empty
        VertimientoMaximo = 0;
        
		Filtracion = cGenerador.empty
        PorcentajeFiltracion = 0; % en caso de que haya filtración
        
        IndiceAdmEscenarioAfluentes = 0
        
		%Indice para resultados y optimizacion de planificación
        IndiceVarOpt = 0;
    end
    
    methods
        function this = cAlmacenamiento()
            this.TipoElementoRed = 'Almacenamiento';
        end

        function copia = crea_copia(this)
          copia = cAlmacenamiento();
          copia.Nombre = this.Nombre;
          copia.EMax = this.EMax;
          copia.EMin = this.EMin;
          copia.EInicial = this.EInicial;
          copia.Eficiencia = this.Eficiencia;
          copia.IndiceAdmEscenarioAfluentes = this.IndiceAdmEscenarioAfluentes;
          copia.PorcentajeFiltracion = this.PorcentajeFiltracion;
          
          if ~isempty(this.Vertimiento)
              copia.crea_vertimiento();
          end
          if ~isempty(this.Filtracion)
              copia.crea_filtracion(this.PorcentajeFiltracion);
          end
        end
        
        function val = entrega_vol_emax(this)
            val = this.EMax;
        end
        
        function inserta_emax(this, val)
            this.EMax = val;
        end
        function val = entrega_emin(this)
            val = this.EMin;
        end
        
        function inserta_emin(this, val)
            this.EMin = val;
        end
        function val = entrega_e_inicial(this)
            val = this.EInicial;
        end
        
        function inserta_e_inicial(this, val)
            this.EInicial = val;
        end
                

        function agrega_turbina_descarga(this, gen)
          n = length(this.TurbinasDescarga);
          this.TurbinasDescarga(n+1) = gen;
        end
        
		function turbinas = entrega_turbinas_descarga(this)
			turbinas = this.TurbinasDescarga;
        end
		
		function turbina = entrega_turbina_descarga(this, id)
			turbina = this.TurbinasDescarga(id);
        end
        
		function spill = entrega_vertimiento(this)
			spill = this.Vertimiento;
        end
        
        function val = entrega_cantidad_turbinas_descarga(this)
            val = length(this.TurbinasDescarga);
        end
        
        function crea_vertimiento(this)
            this.Vertimiento = cGenerador();
            this.Vertimiento.Almacenamiento = this;
            
            this.Vertimiento.Nombre = ['Vert_Almacenamiento_' num2str(this.Id)];
        end
        
        function crea_filtracion(this, porcentaje_filtracion)
            this.Filtracion = cGenerador();
            this.Filtracion.Almacenamiento = this;
            
            this.Filtracion.Nombre = ['Filtr_Almacenamiento_' num2str(this.Id)];
            this.PorcentajeFiltracion = porcentaje_filtracion;
        end
        
        function filt = entrega_filtracion(this)
            filt = this.Filtracion;
        end
        
        function val = tiene_filtracion(this)
            val = ~isempty(this.Filtracion);
        end
        
        function val = entrega_eficiencia(this)
            val = this.Eficiencia;
        end
        
        function inserta_eficiencia(this, val)
            this.Eficiencia = val;
        end
        
        function id = entrega_indice_adm_escenario_afluentes(this)
            id = this.IndiceAdmEscenarioAfluentes;
        end
        
        function inserta_indice_adm_escenario_afluentes(this, val)
            this.IndiceAdmEscenarioAfluentes = val;
        end
        
        function id = entrega_indice_adm_escenario_vertimiento_obligatorio(this)
            id = this.IndiceAdmEscenarioVerimientoObligatorio;
        end
        
        function inserta_indice_adm_escenario_vertimiento_obligatorio(this, val)
            this.IndiceAdmEscenarioVerimientoObligatorio = val;
        end

        function id = entrega_id_turbinas_descarga(this)
            id = zeros(1,length(this.TurbinasDescarga));
            for i = 1:length(this.TurbinasDescarga)
                id(i) = this.TurbinasDescarga(i).entrega_id();
            end
        end
        
        function val = entrega_maximo_caudal_filtracion(this)
            val = this.PorcentajeFiltracion*this.EMax;
        end
        
        function val = entrega_porcentaje_filtracion(this)
            val = this.PorcentajeFiltracion;
        end
        
        function inserta_porcentaje_filtracion(this, val)
            this.PorcentajeFiltracion = val;
        end
        
        function val = es_vertimiento(this, vertimiento)
            val = this.Vertimiento == vertimiento;
        end

        function val = es_filtracion(this, filtracion)
            val = this.Filtracion == filtracion;
        end
        
    end
end