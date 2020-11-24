classdef cParOptimizacionMILP < handle
    % clase que guarda los parámetros de optimización
    properties
        NombreSistema = 'IEEE 118 ERNC_MILP Base'
        Output = 'prot_milp_118_ernc'
        PathSistema = './input/Data_IEEE_118/IEEE_118_Bus_Data_ERNC_MILP.xlsx'
        IdPuntosOperacion = 1
        IdEscenario = 1
        ComputoParalelo = true
        %parámetros optimización
        DeltaEtapa = 1   %anios
        TBase = 2015
        TInicio = 2015
        TFin = 2017
        CantidadEtapas = 0
        CantidadPuntosOperacion = 1
        CantidadEscenarios = 1
        
        TiempoEntradaOperacionTradicional = 0
        TiempoEntradaOperacionUprating = 1
        
        AnguloMaximoBuses = 1.57
        DecimalesRedondeo = 5
        MaxMemory = 47500
        MaxTime = 14400
        MaxGap = 0
        
        OptimizaSoCInicialBaterias = true
        
        GraficaResultados = false
        ImprimeResultadosProtocolo = true
        ExportaResultadosFormatoExcel = true
        ConsideraRecorteRES = true;
        PenalizacionRecorteRES = 10000; %$/MWh, para recorte RES en contingencia
        ConsideraDesprendimientoCarga = true;
        
        ConsideraTransicionEstados = false;
        ConsideraReconductoring = false;
        ConsideraCompensacionSerie = false;
        ConsideraVoltageUprating = false;
        CambioConductorVoltageUprating = false;
        ElijeTipoConductor = false; % Si es false, entonces sólo se determina conductor "base"
        ElijeVoltageLineasNuevas = false;
        ConsideraValorResidualElementos = false;
        
        EstrategiaAngulosSENuevas = 1; %0: igual al ángulo de SE adyacente; 1: cero
        EstrategiaOptimizacion = 'Benders' % 'SingleMILP', 'Benders'
        MaxIterBenders = 250
        NivelSubetapasParaCortes = 3  % 1: anual, 2: PO consecutivos, 3: Por cada PO 
        ConsideraAlphaMin = false
        FactorMultiplicadorBigM = 1.5 % DEBUG: Es para ver si tiene un efecto (eventualmente cálculo de BigM puede ser erróneo)
        
        % parámetros económicos
        TasaDescuento = 0.1
        Penalizacion = 1000 % penalización de recorte res y ENS en estado normal. 
        
        FactorCostoDesarrolloProyecto = 1 %1.1 significa que se agrega un 10% de los costos de materiales al desarrollo del proyecto
        Solver = 'Xpress'; %'Xpress', 'Intlinprog' o 'FICO'
        GuardaProblemaOptimizacion = false  % guarda problema optimizacion en archivo .mat. Sólo en modo debug!
        ImprimeProblemaOptimizacion = false
        ImprimeProblemaSoloVariablesDecisionActivas = false % si se fija la solución, las variables "inactivas" no se imprimen
        ImprimeConIndices = false % false: imprime con nombres
        CalculaSolucionInicial = false

        TestRestriccionesProyEscenariosExhaustivas = false
        
        NivelDebug = 2;
        
        % los siguientes parámetros se utilizan sólo para evaluar el plan óptimo! Para nada más
        FuncionObjetivo = 'MinC' 
        TipoFlujoPotencia = 'DC' %DC
        TipoRestriccionesSeguridad = 'N0'  % N1 corresponde a criterio N-1
    end
    
    methods
        function this = cParOptimizacionMILP()
            this.CantidadEtapas = (this.TFin - this.TInicio + 1)/this.DeltaEtapa;
        end
        
        function val = considera_reconductoring(this)
            val = this.ConsideraReconductoring;
        end
        
        function val = calcula_solucion_inicial(this)
            val = this.CalculaSolucionInicial;
        end

        function val = considera_desprendimiento_carga(this)
            val = this.ConsideraDesprendimientoCarga;
        end

        function val = considera_recorte_res(this)
            val = this.ConsideraRecorteRES;
        end
        
        function val = entrega_penalizacion_recorte_res(this)
            val = this.PenalizacionRecorteRES;
        end
        
        function val = considera_compensacion_serie(this)
            val = this.ConsideraCompensacionSerie;
        end
        
        function val = considera_voltage_uprating(this)
            val = this.ConsideraVoltageUprating;
        end
        
        function val = considera_valor_residual_elementos(this)
            val = this.ConsideraValorResidualElementos;
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
        
        function val = entrega_penalizacion(this)
            val = this.Penalizacion;
        end
                
        function val = guarda_problema_optimizacion(this)
            val = this.GuardaProblemaOptimizacion;
        end
        
        function val = imprime_problema_optimizacion(this)
            val = this.ImprimeProblemaOptimizacion;
        end
        
        function inserta_factor_costo_desarrollo_proyectos(this, val)
            this.FactorCostoDesarrolloProyecto = val;
        end
        
        function val = entrega_factor_costo_desarrollo_proyectos(this)
            val = this.FactorCostoDesarrolloProyecto;
        end
        
        function val = entrega_nivel_debug(this)
            val = this.NivelDebug;
        end
        
        function val = entrega_cantidad_escenarios(this)
            val = this.CantidadEscenarios;
        end
    end
end
