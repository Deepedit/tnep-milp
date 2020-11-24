classdef cEmbalse < cElementoRed
        % clase que representa los transformadores
    properties 
        %parámetros técnicos
		VolMax
        VolMin
        VolInicial
        VolFinal
        Eficiencia = 1
        
        % Turbinas de carga y descarga. Estas deben haber sido definidas
        % como Generadores y agregadas al SEP (generan potencia eléctrica)
        TurbinasCarga = cGenerador.empty
        TurbinasDescarga = cGenerador.empty
        
        % Vertimiento y Filtración quitan agua del embalse. 
        % Aportes adicoinales pueden ser vertimientos y filtraciones desde otros embalses. NO SON los aportes naturales de los afluentes ni turbinas de carga
        % Si bien estas tres variables se modelan como generadores, NO DEBEN IR AGREGADAS AL SEP. Sólo "existen" dentro de cada embalse
        Vertimiento = cGenerador.empty
        MaximoCaudalVertimiento = 0;
        
		Filtracion = cGenerador.empty
        AportesAdicionales = cGenerador.empty % vertimientos y filtraciones desde otros embalses. 
        
        PorcentajeFiltracion = 0; % en caso de que haya filtración
        
        IndiceAdmEscenarioAfluentes = 0
        IndiceAdmEscenarioVerimientoObligatorio = 0
        
        % Por ahora altura max y min no se utilizan. Eventualmente se puede considerar a futuro para un mejor cálculo de la altura de caida dependiendo del llenado del embalse
        AlturaMax = 0
        AlturaMin = 0
        AlturaCaida = 0
        
        VolActual = 0 % Sólo si para determinar la operación no se considera balance temporal. En este caso, las potencias las turbinas de carga y descarga deben ajustarse al volumen actual, mínimo y máximo del embalse
		%Indice para resultados y optimizacion de planificación
        IndiceVarOpt = 0;
        %IndiceEqFlujosAngulos = []        
    end
    
    methods
        function this = cEmbalse()
            this.TipoElementoRed = 'Embalse';
        end

        function copia = crea_copia(this)
          copia = cEmbalse();
          copia.Nombre = this.Nombre;
          copia.VolMax = this.VolMax;
          copia.VolMin = this.VolMin;
          copia.VolInicial = this.VolInicial;
          copia.VolFinal = this.VolFinal;
          copia.Eficiencia = this.Eficiencia;
          copia.IndiceAdmEscenarioAfluentes = this.IndiceAdmEscenarioAfluentes;
          copia.IndiceAdmEscenarioVerimientoObligatorio = this.IndiceAdmEscenarioVerimientoObligatorio;
          copia.AlturaMax = this.AlturaMax;
          copia.AlturaMin = this.AlturaMin;
          copia.AlturaCaida = this.AlturaCaida;
          copia.PorcentajeFiltracion = this.PorcentajeFiltracion;
          copia.VolActual = this.VolActual;
          copia.MaximoCaudalVertimiento = this.MaximoCaudalVertimiento;
          
          if ~isempty(this.Vertimiento)
              copia.crea_vertimiento();
          end
          if ~isempty(this.Filtracion)
              copia.crea_filtracion(this.PorcentajeFiltracion);
          end
        end
        
        function val = entrega_altura_caida(this)
            val = this.AlturaCaida;
        end
        
        function inserta_altura_caida(this, val)
            this.AlturaCaida = val;
        end
        function val = entrega_vol_max(this)
            val = this.VolMax;
        end
        
        function inserta_vol_max(this, val)
            this.VolMax = val;
        end
        function val = entrega_vol_min(this)
            val = this.VolMin;
        end
        
        function inserta_vol_min(this, val)
            this.VolMin = val;
        end
        function val = entrega_vol_inicial(this)
            val = this.VolInicial;
        end
        
        function inserta_vol_inicial(this, val)
            this.VolInicial = val;
        end
        
        function inserta_vol_final(this, val)
            this.VolFinal = val;
        end
        
        function val = entrega_vol_final(this)
            if this.VolFinal ~= 0
                val = this.VolFinal;
            else
                val = this.VolInicial;
            end
        end
        
        function turbinas = entrega_turbinas_carga(this)
            turbinas = this.TurbinasCarga;
        end
        function agrega_turbina_carga(this, gen)
          n = length(this.TurbinasCarga);
          this.TurbinasCarga(n+1) = gen;
        end

        function agrega_turbina_descarga(this, gen)
          n = length(this.TurbinasDescarga);
          this.TurbinasDescarga(n+1) = gen;
        end
        
        function turbina = entrega_turbina_carga(this, id)
            turbina = this.TurbinasCarga(id);
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
        
        function val = entrega_cantidad_turbinas_carga(this)
            val = length(this.TurbinasCarga);
        end
        
        function val = entrega_cantidad_turbinas_descarga(this)
            val = length(this.TurbinasDescarga);
        end
        
        function crea_vertimiento(this)
            this.Vertimiento = cGenerador();
            this.Vertimiento.Embalse = this;
            
            this.Vertimiento.Nombre = ['Vert_Embalse_' num2str(this.Id)];
        end
        
        function crea_filtracion(this, porcentaje_filtracion)
            this.Filtracion = cGenerador();
            this.Filtracion.Embalse = this;
            
            this.Filtracion.Nombre = ['Filtr_Embalse_' num2str(this.Id)];
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

        function id = entrega_id_turbinas_carga(this)
            id = zeros(1,length(this.TurbinasCarga));
            for i = 1:length(this.TurbinasCarga)
                id(i) = this.TurbinasCarga(i).entrega_id();
            end
        end

        function id = entrega_id_turbinas_descarga(this)
            id = zeros(1,length(this.TurbinasDescarga));
            for i = 1:length(this.TurbinasDescarga)
                id(i) = this.TurbinasDescarga(i).entrega_id();
            end
        end
        
        function val = entrega_maximo_caudal_filtracion(this)
            val = this.PorcentajeFiltracion*this.VolMax;
        end
        
        function val = entrega_porcentaje_filtracion(this)
            val = this.PorcentajeFiltracion;
        end
        
        function inserta_porcentaje_filtracion(this, val)
            this.PorcentajeFiltracion = val;
        end
        function val = entrega_volumen_actual(this)
            val = this.VolActual;
        end
        
        function agrega_aporte_adicional(this, aporte)
            n = length(this.AportesAdicionales);
            this.AportesAdicionales(n+1) = aporte;
        end
        
        function aportes = entrega_aportes_adicionales(this)
            aportes = this.AportesAdicionales;
        end
        
        function val = entrega_maximo_caudal_vertimiento(this)
            val = this.MaximoCaudalVertimiento;
        end
        
        function val = es_vertimiento(this, vertimiento)
            val = this.Vertimiento == vertimiento;
        end

        function val = es_filtracion(this, filtracion)
            val = this.Filtracion == filtracion;
        end
        
    end
end