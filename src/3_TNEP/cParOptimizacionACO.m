classdef cParOptimizacionACO < handle
    % clase que guarda los parámetros de optimización
    properties
        NombreSistema = './input/Data_IEEE_118/IEEE_118_Bus_Data_ERNC.xlsx'
        IdPuntosOperacion = 1
        ComputoParalelo = false
        OptimizaUsoMemoriaParalelo = true
        Solver = 'Xpress'; %'Xpress' o 'Intlinprog'
        
        CreaPlanOptimo = true
        ArchivoPlanOptimo = './input/Data_IEEE_118/IEEE_118_Bus_Data_ERNC.xlsx'
        HojaPlanOptimo = 'Base'
        CantWorkers = 4
        
        %parámetros optimización
        DeltaEtapa = 1   %anios
        TBase = 2015
        TInicio = 2015
        %TFin = 2039
        TFin = 2029
        CantidadEtapas = 0
        CantidadPuntosOperacion = 1
        
        ConsideraTransicionEstados = true;
        ConsideraReconductoring = true;
        ConsideraCompensacionSerie = true;
        ConsideraVoltageUprating = true;
        CambioConductorVoltageUprating = true;
        ElijeTipoConductor = false; % Si es false, entonces sólo se determina conductor "base"
        ElijeVoltageLineasNuevas = true;
        % parámetros económicos
        TasaDescuento = 0.1
        FactorCostoDesarrolloProyecto = 1.0 %1.1 significa que se agrega un 10% de los costos de materiales al desarrollo del proyecto
        
        % Criterios generales para definición del problema
        ConsideraDesprendimientoCarga = true
        ConsideraRecorteRES = true
        PenalizacionRecorteRES = 1000  %$/MWh
        
        PlanValidoConENS = false
        PlanValidoConRecorteRES = false
        
        %parametros ACO
        CantidadHormigas = 50
        CantidadMejoresPlanes = 10  % entregan feromonas
        MaxNroReparacionesPorEtapa = 50
        ReparaPlanSecuencial = false   % quiere decir que uno a uno. La alternativa es en grupos y toma el mejor
        ReparaPlanCantCompararIndirecto = 5  % solo si no esta repara plan secuencial. 
        
        MaxCantidadGeneracionPlanesPorEtapa = 3
        MaxCantidadPlanesDesechados = 3
        MaxCantidadReparaciones = 1 % máxima cantidad de reparaciones simultaneas cuando plan no es válido
        DeterminaMaxCantidadProyectosInicio = true  %false: cantidad de proyectos se deja a libre elección en cada etapa
        
        % Estrategias de búsqueda local
        CantidadPlanesBusquedaLocal = 10
        PlanMasProbableFeromonasDesdeIteracion = 3
        
        CantidadIntentosFallidosAdelanta = 3;

        BLEliminaDesplazaProyectos = 1         % id = 1
        BLEliminaDesplazaCantProyCompararBase = 1;
        BLEliminaDesplazaCantProyCompararSinMejora = 1;        
        BLEliminaDesplazaCantBusquedaFallida = 3;
        BLEliminaDesplazaProyAlComienzo = false;
        BLEliminaDesplazaProyNormal = true;
        BLEliminaDesplazaNuevoDesplaza = true;
        BLEliminaDesplazaNuevoAgrega = true;
        PrioridadAdelantaProyectos = true;
        PrioridadDesplazaSobreElimina = true;
        BLEliminaDesplazaCambioUprating = true; % significa que evalúa cambios de uprating en mismo corredor
        
        BLAgregaProyectosFormaSecuencialCompleto = 0  % id = 2
        BLSecuencialCompletoCantBusquedaFallida = 3;
        BLSecuencialCompletoCantProyComparar = 2;
        BLSecuencialCompletoPrioridadSobrecargaElem = false;
        BLSecuencialCompletoMaxCantAumentoTotexIntento = 3;

        NivelFeromonaInicial = 1
        ProbabilidadConstruccionInicial = 0.4;
        TasaEvaporacion = 0.9
        MaxFeromona = 0.2
        FactorAlfa = 0.9
        
        
        %criterios de salida
        DeltaObjetivoParaSalida = 0.05   % en porcentaje
        CantidadIteracionesSinMejora = 30
        MaxItPlanificacion = 100
        MinItPlanificacion = 10
        
        %parámetros para evaluación (OPF). Reemplazan parámetros por
        %defecto del OPF
        FuncionObjetivo = 'MinC'  % Alternativas: OptV --> voltaje óptimo
        TipoFlujoPotencia = 'DC' %DC
        TipoRestriccionesSeguridad = 'N0'  % N1 corresponde a criterio N-1
        TipoProblema = 'Despacho'  % alternativa: 'Redespacho'
        
        % Parámetros para AC-OPF
        MetodoOptimizacionAC = 'IP'  % método del punto interior. Alternativa es ...
        OptimizaVoltajeOperacion = false
        
        % Parámetros para DC-OPF
        FlujoDCconPerdidas = false
        
        % Niveles de Debug de los distintos programas
        NivelDebugOPF = 0
        NivelDebugACO = 2
        NivelDebugAdmProy = 2
        NivelDebugParalelo = 0
    end
    
    methods
        function this = cParOptimizacionACO()
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
        
        function val = considera_busqueda_local(this)
            if this.BLEliminaDesplazaProyectos > 0 || ...
               this.BLAgregaProyectosFormaSecuencialCompleto > 0
                val = true;
            else
                val = false;
            end
        end
        
        function val = computo_paralelo(this)
            val = this.ComputoParalelo;
        end
        
        function val = entrega_nivel_debug(this)
            val = this.NivelDebugACO;
        end
    end
end
