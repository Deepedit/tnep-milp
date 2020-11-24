classdef (Sealed) cAdministradorEscenarios < handle
    % clase administra los escenarios de operación. Contiene las series de
    % tiempo de los generadores no despachables y los consumos
    properties

        CapacidadGeneradores = [] % matriz de nro_generadores con evolucion de capadidad x etapas
        CapacidadConsumos = []
        PerfilesERNC = []
        PerfilesConsumo = [] % tanto para P como para Q
        PerfilesAfluentes = []
        PerfilesVertimientos = []
        
		Escenarios = []  % para mantener "track" de los escenarios considerados
        PesoEscenarios = []

        RepresentatividadPuntosOperacion = []
        IndicesPuntosOperacionConsecutivos = []
        ConsideraDependenciaTemporal = false
        
        CostosGeneracion = [] % costos de generacion variables (por si evolucionan a futuro)
        
        CantidadEtapas = 1
        CantidadPuntosOperacion = 1 % por escenario
        CantidadEscenarios = 1        
    end

    methods (Access = private)
        function this = cAdministradorEscenarios
        end
    end
    
    methods (Static)
        function singleObj = getInstance
            persistent localObj
            if isempty(localObj) || ~isvalid(localObj)
                localObj = cAdministradorEscenarios;
            end
            singleObj = localObj;
        end
    end
    
    methods
        function inicializa_escenarios(this, escenarios, peso_escenarios, cantidad_etapas, cantidad_puntos_operacion, pesos_puntos_operacion, varargin)
            % varargin indica indices de PO consecutivos para dependencia
            % temporal
            this.CantidadEscenarios = length(escenarios);
            this.CantidadEtapas = cantidad_etapas;
            this.CantidadPuntosOperacion = cantidad_puntos_operacion;
			this.RepresentatividadPuntosOperacion = pesos_puntos_operacion;
            this.Escenarios = escenarios;
            this.PesoEscenarios = peso_escenarios;
            if nargin > 6
                indices_po_consecutivos = varargin{1};
                % indices_po_consecutivos contiene datos "reales". Hay que
                % pasarlos a datos "relativos"
                [cant_po_consecutivos, ~] = size(indices_po_consecutivos);
                for i = 1:cant_po_consecutivos
                    cant_po = indices_po_consecutivos(i,2)-indices_po_consecutivos(i,1)+1;
                    if i == 1
                        this.IndicesPuntosOperacionConsecutivos(i,1) = 1;
                        this.IndicesPuntosOperacionConsecutivos(i,2) = cant_po;
                    else
                        this.IndicesPuntosOperacionConsecutivos(i,1) = this.IndicesPuntosOperacionConsecutivos(i-1,2)+1;
                        this.IndicesPuntosOperacionConsecutivos(i,2) = this.IndicesPuntosOperacionConsecutivos(i,1)+cant_po-1;
                    end
                end
                this.ConsideraDependenciaTemporal = true;
            end
        end
        
        function val = entrega_cantidad_etapas(this)
            val = this.CantidadEtapas;
        end

        function val = entrega_cantidad_puntos_operacion(this)
            val = this.CantidadPuntosOperacion;
        end
        
        function val = entrega_cantidad_escenarios(this)
            val = this.CantidadEscenarios;
        end
        
        function indice = inserta_perfil_ernc(this, perfil)
            [indice,~] = size(this.PerfilesERNC);
            indice = indice + 1;
            this.PerfilesERNC(indice, :) = perfil;
        end
        
        function perfil = entrega_perfil_ernc(this, indice_perfil)
            perfil = this.PerfilesERNC(indice_perfil, :);
        end
        
        function indice = inserta_perfil_consumo(this, perfil)
            [indice,~] = size(this.PerfilesConsumo);
            indice = indice + 1;
            this.PerfilesConsumo(indice, :) = perfil;
        end
                
        function perfil = entrega_perfil_consumo(this, indice_perfil)
            perfil = this.PerfilesConsumo(indice_perfil, :);
        end
        
        function indice = inserta_perfil_afluente(this, perfil)
            [indice,~] = size(this.PerfilesAfluentes);
            indice = indice + 1;
            this.PerfilesAfluentes(indice, :) = perfil;
        end
        
        function perfil = entrega_perfil_afluente(this, indice_perfil)
            perfil = this.PerfilesAfluentes(indice_perfil, :);
        end
        
        function indice = inserta_perfil_vertimiento(this, perfil)
            [indice,~] = size(this.PerfilesVertimientos);
            indice = indice + 1;
            this.PerfilesVertimientos(indice, :) = perfil;
        end
        
        function perfil = entrega_perfil_vertimiento(this, indice_perfil)
            perfil = this.PerfilesVertimientos(indice_perfil, :);
        end
        
        function rep = entrega_representatividad_punto_operacion(this, varargin)
            if nargin > 1
                punto_operacion = varargin{1};
                rep = this.RepresentatividadPuntosOperacion(punto_operacion);
            else
                rep = this.RepresentatividadPuntosOperacion;
            end
        end
        
        function costo = entrega_costos_generacion_etapa_pu(this, indice, etapa)
            costo = this.CostosGeneracion(indice, etapa)*cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
        end

        function costo = entrega_costos_generacion_etapa(this, indice, etapa)
            costo = this.CostosGeneracion(indice, etapa);
        end
        
        function indice = inserta_costos_generacion_etapa(this, costos)
            [indice, ~] = size(this.CostosGeneracion);
            indice = indice + 1;
            this.CostosGeneracion(indice, :) = costos;
        end

        function indice = agrega_capacidades_generador(this, capacidades)
            [indice, ~] = size(this.CapacidadGeneradores);
            indice = indice + 1;
            this.CapacidadGeneradores(indice, :) = capacidades;
        end
        
        function capacidad = entrega_capacidad_generador(this, indice_generador, etapa)
            capacidad = this.CapacidadGeneradores(indice_generador, etapa);
        end

        function indice = agrega_capacidades_consumo(this, capacidades)
            [indice, ~] = size(this.CapacidadConsumos);
            indice = indice + 1;
            this.CapacidadConsumos(indice, :) = capacidades;
        end
        
        function capacidad = entrega_capacidad_consumo(this, indice_consumo, etapa)
            capacidad = this.CapacidadConsumos(indice_consumo, etapa);
        end
                
        function peso = entrega_peso_escenario(this, escenario)
            peso = this.PesoEscenarios(escenario);
        end
        
        function inserta_peso_escenarios(this, pesos)
            this.PesoEscenarios = pesos;
        end
        
        function inserta_indices_po_consecutivos(this, indices)
            this.IndicesPuntosOperacionConsecutivos = indices;
        end
        
        function val = entrega_indices_po_consecutivos(this)
            val = this.IndicesPuntosOperacionConsecutivos;
        end
        
        function val = considera_dependencia_temporal(this)
            val = this.ConsideraDependenciaTemporal;
        end
    end
end