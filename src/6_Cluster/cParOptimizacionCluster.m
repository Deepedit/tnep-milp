classdef cParOptimizacionCluster < handle
    % clase que guarda los parámetros del cluster
    properties
        NombreSistema = './input/Data_IEEE_118/IEEE_118_Bus_Data_ERNC_Cluster.xlsx'
        IdPuntosOperacion = 6
        %parámetros optimización
        DeltaEtapa = 1   %anios
        TBase = 2015
        TInicio = 2015
        %TFin = 2039
        TFin = 2029
        CantidadEtapas = 0
        CantidadPuntosOperacion = 1

        % a continuación parámetros para determinar los proyectos de
        % expansión. NO MODIFICAR!!!
        ConsideraTransicionEstados = false;
        ConsideraReconductoring = false;
        ConsideraCompensacionSerie = false;
        ConsideraVoltageUprating = false;
        CambioConductorVoltageUprating = false;
        ElijeTipoConductor = false; % Si es false, entonces sólo se determina conductor "base"
        ElijeVoltageLineasNuevas = false;
        % parámetros económicos
        TasaDescuento = 0.1
        FactorCostoDesarrolloProyecto = 1.0 %1.1 significa que se agrega un 10% de los costos de materiales al desarrollo del proyecto
        
        % Criterios generales para definición del problema
        ConsideraDesprendimientoCarga = true
        ConsideraRecorteRES = true
        PenalizacionRecorteRES = 1000  %$/MWh
        
        PlanValidoConENS = false
        PlanValidoConRecorteRES = false
        
        %parámetros para evaluación (OPF). Reemplazan parámetros por
        %defecto del OPF
        Solver = 'Xpress' % 'Intlinprog' o 'Xpress'
        
        FuncionObjetivo = 'MinC'  % Alternativas: OptV --> voltaje óptimo
        TipoFlujoPotencia = 'DC' %DC
        TipoRestriccionesSeguridad = 'N0'  % N1 corresponde a criterio N-1
        TipoProblema = 'Despacho'  % alternativa: 'Redespacho'
        
        % Parámetros para AC-OPF. Aún no está implementado!
        MetodoOptimizacionAC = 'IP'  % método del punto interior. Alternativa es ...
        OptimizaVoltajeOperacion = false
        
        % Parámetros para DC-OPF
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
