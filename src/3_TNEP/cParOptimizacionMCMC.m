classdef cParOptimizacionMCMC < handle
    % clase que guarda los par�metros de optimizaci�n
    properties
        NombreSistema = 'IEEE 118 ERNC_MILP Base'
        PathSistema = './input/Data_IEEE_118/IEEE_118_Bus_Data_ERNC_MILP_Base.xlsx'
        Output = 'prot_ieee_118_ernc_milp'
        IdPuntosOperacion = 1
        IdEscenario = 1
        CantidadEscenarios = 1
        ComputoParalelo = false
        CantWorkers = 4
		MaxTiempoSimulacion = 172800  % segundos
        %par�metros optimizaci�n
        DeltaEtapa = 1   %anios
        TBase = 2015 
        TInicio = 2015
        %TFin = 2039
        TFin = 2029
        CantidadEtapas = 0
        CantidadPuntosOperacion = 1

        EstrategiaGeneraPlanesBase = 0.5 %1: greedy; 2: random; otro valor: porcentaje: porcentaje greedy (el resto random)
        GeneraPlanOptimoComoBase = false
        GeneraPlanMasProbable = true % TODO A FUTURO
        ProbNoConstruirPlanBase = 0.8
        ProbConstruirPlanBaseGeneracion = 0.1
        ConsideraIncertidumbre = false
        CantidadSimulacionesEscenarios = 3  % n�mero de escenarios a simular cuando se considera incertidumbre

        TiempoEntradaOperacionTradicional = 0
        TiempoEntradaOperacionUprating = 1
        
        CantidadCadenas = 10  % cadenas principales. Las cadenas secundarias se determinan por el beta
        DimensionSubsetS = 3
        CantCorredoresModificar = 3 % m�xima cantidad de corredores a modificar por iteracion (de cambio)
        EstrategiaMCMC = 1; % 1: walker move; 2: replacement move
        
        % Par�metros para b�squeda local
        EstrategiaBusquedaLocal = 2 % 0: no hay b�squeda local, 1: simple, 2: detallada
        
        % Parametros espec�ficos para busqueda local simple
        EstrategiaProyectosOptimizar = 1 % 0: no se optimiza, 1: aleatoria, 2: por prioridad 
        MaximaCantProyectosOptimizar = 0 % 0: no se limita, >0: cant m�xima de  decisiones primarias a optimizar
        OptimizaCorredoresModificados = 1 % 0: no, 1: si

        % Par�metros espec�ficos para busqueda local detallada
        BLDetalladaCantFallida = 3
        BLDetalladaCantProyCompararBase = 3
        BLDetalladaCantProyCompararSinMejora = 5;        
        
        BLDetalladaPrioridadDesplazaSobreElimina = false% 1: si hay una mejora parcial en desplazamiento y luego costos totales vuelven a aumentar, no se sigue evaluando
        CantIntentosFallidosAdelantaOptimiza = 3
        BLDetalladaPrioridadAdelantaSobreDesplaza = false;
        
        % Par�metros para reparar plan
        CantProyCompararReparaPlan = 3
        
        % Par�metros de caso de estudio
        ConsideraTransicionEstados = false;
        ConsideraReconductoring = false;
        ConsideraCompensacionSerie = false;
        ConsideraVoltageUprating = false;
        CambioConductorVoltageUprating = false;
        ElijeTipoConductor = false; % Si es false, entonces s�lo se determina conductor "base"
        ElijeVoltageLineasNuevas = false;
        % par�metros econ�micos
        TasaDescuento = 0.1

        DecimalesRedondeo = 5
        FactorCostoDesarrolloProyecto = 1.0 %1.1 significa que se agrega un 10% de los costos de materiales al desarrollo del proyecto
        
        % Criterios generales para definici�n del problema
        PlanValidoConENS = false
        PlanValidoConRecorteRES = false
        
        %parametros MCMC
        MaxCantidadPasos = 10000
        PasoActualizacion = 10; 
        SigmaFuncionLikelihood = 100  % 1 mill�n
        SigmaParametros = 1  
        
        %par�metros para evaluaci�n (OPF). Reemplazan par�metros por
        %defecto del OPF
        FuncionObjetivo = 'MinC'  % Alternativas: OptV --> voltaje �ptimo
        TipoFlujoPotencia = 'DC' %DC
        TipoRestriccionesSeguridad = 'N0'  % N1 corresponde a criterio N-1
        TipoProblema = 'Despacho'  % alternativa: 'Redespacho'
        Solver = 'Xpress'; %'Xpress', 'Intlinprog' o 'FICO'
        DeterminaUC = true;
        ConsideraContingenciaN1 = false % Despacho preventivo: flujos de l�neas y trafos luego de una falla deben permanecer dentro de los l�mites
        ConsideraEstadoPostContingencia = false % se considera el re-despacho de las unidades de generaci�n luego de ocurrida la falla (actuaci�n del control primario)
        
        % Par�metros para AC-OPF
        MetodoOptimizacionAC = 'IP'  % m�todo del punto interior. Alternativa es ...
        OptimizaVoltajeOperacion = false
        
        % Par�metros para DC-OPF
        FlujoDCconPerdidas = false
        
        PorcentajeUsoFlujosAltos = 0.95;
        PorcentajeUsoFlujosBajos = 0.5;

        NivelDetalleResultadosOPF = 2
        NivelDetalleResultadosFP = 2
        
        ConsideraFlujosAC = false
        % Niveles de Debug de los distintos programas
        NivelDebugOPF = 2
        NivelDebugFP = 2
        NivelDebug = 0
        NivelDebugAdmProy = 0
        NivelDebugParalelo = 2
        
    end
    
    methods
        function this = cParOptimizacionMCMC()
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
        
        function inserta_factor_costo_desarrollo_proyectos(this, val)
            this.FactorCostoDesarrolloProyecto = val;
        end
        
        function val = entrega_factor_costo_desarrollo_proyectos(this)
            val = this.FactorCostoDesarrolloProyecto;
        end
                
        function val = computo_paralelo(this)
            val = this.ComputoParalelo;
        end
        
        function val = entrega_nivel_debug(this)
            val = this.NivelDebug;
        end
        
        function val = considera_flujos_ac(this)
            val = this.ConsideraFlujosAC;
        end
    end
end
