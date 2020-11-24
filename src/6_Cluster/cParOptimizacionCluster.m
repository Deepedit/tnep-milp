classdef cParOptimizacionCluster < handle
    % clase que guarda los par�metros del cluster
    properties
        NombreSistema = './input/Data_IEEE_118/IEEE_118_Bus_Data_ERNC_Cluster.xlsx'
        IdPuntosOperacion = 6
        %par�metros optimizaci�n
        DeltaEtapa = 1   %anios
        TBase = 2015
        TInicio = 2015
        %TFin = 2039
        TFin = 2029
        CantidadEtapas = 0
        CantidadPuntosOperacion = 1

        % a continuaci�n par�metros para determinar los proyectos de
        % expansi�n. NO MODIFICAR!!!
        ConsideraTransicionEstados = false;
        ConsideraReconductoring = false;
        ConsideraCompensacionSerie = false;
        ConsideraVoltageUprating = false;
        CambioConductorVoltageUprating = false;
        ElijeTipoConductor = false; % Si es false, entonces s�lo se determina conductor "base"
        ElijeVoltageLineasNuevas = false;
        % par�metros econ�micos
        TasaDescuento = 0.1
        FactorCostoDesarrolloProyecto = 1.0 %1.1 significa que se agrega un 10% de los costos de materiales al desarrollo del proyecto
        
        % Criterios generales para definici�n del problema
        ConsideraDesprendimientoCarga = true
        ConsideraRecorteRES = true
        PenalizacionRecorteRES = 1000  %$/MWh
        
        PlanValidoConENS = false
        PlanValidoConRecorteRES = false
        
        %par�metros para evaluaci�n (OPF). Reemplazan par�metros por
        %defecto del OPF
        Solver = 'Xpress' % 'Intlinprog' o 'Xpress'
        
        FuncionObjetivo = 'MinC'  % Alternativas: OptV --> voltaje �ptimo
        TipoFlujoPotencia = 'DC' %DC
        TipoRestriccionesSeguridad = 'N0'  % N1 corresponde a criterio N-1
        TipoProblema = 'Despacho'  % alternativa: 'Redespacho'
        
        % Par�metros para AC-OPF. A�n no est� implementado!
        MetodoOptimizacionAC = 'IP'  % m�todo del punto interior. Alternativa es ...
        OptimizaVoltajeOperacion = false
        
        % Par�metros para DC-OPF
        FlujoDCconPerdidas = false
        
        MuestraDetalleIteracionOpt = true
        
        % Niveles de Debug de los distintos programas
        NivelDebugOPF = 0
        NivelDebugAdmProy = 2
        NivelDebugCluster = 2
    end
    
    methods
        function this = cParOptimizacionCluster()
            this.CantidadEtapas = (this.TFin - this.TInicio + 1)/this.DeltaEtapa;
        end
        
        function val = considera_reconductoring(this)
            val = this.ConsideraReconductoring;
        end

        function val = considera_compensacion_serie(this)
            val = this.ConsideraCompensacionSerie;
        end
        
        function val = considera_voltage_uprating(this)
            val = this.ConsideraVoltageUprating;
        end
        
        function val = elije_tipo_conductor(this)
            val = this.ElijeTipoConductor;
        end
        
        function val = elije_voltage_lineas_nuevas(this)
            val = this.ElijeVoltageLineasNuevas;
        end
        
        function val = cambio_conductor_voltage_uprating(this)
            val = this.CambioConductorVoltageUprating;
        end
        
        function no = entrega_no_etapas(this)
            no = this.CantidadEtapas;
        end
        
        function no = entrega_cantidad_puntos_operacion(this)
            no = this.CantidadPuntosOperacion;
        end
        
        function val = entrega_penalizacion_recorte_res(this)
            val = this.PenalizacionRecorteRES;
        end

        function inserta_factor_costo_desarrollo_proyectos(this, val)
            this.FactorCostoDesarrolloProyecto = val;
        end
        
        function val = entrega_factor_costo_desarrollo_proyectos(this)
            val = this.FactorCostoDesarrolloProyecto;
        end
        
        function val = considera_desprendimiento_carga(this)
            val = this.ConsideraDesprendimientoCarga;
        end
                
        function val = entrega_nivel_debug(this)
            val = this.NivelDebugCluster;
        end
    end
end
