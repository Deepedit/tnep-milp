classdef cParOptimizacionOPF < handle
    % clase que guarda los par�metros de optimizaci�n
    properties        
        % Par�metros globales
        FuncionObjetivo = 'MinC'  % Alternativas: OptV --> voltaje �ptimo
        TipoFlujoPotencia = 'DC' %DC
        TipoRestriccionesSeguridad = 'N0'  % N1 corresponde a criterio N-1
        TipoProblema = 'Despacho'  % alternativa: 'Redespacho'

        % Modelo
        DeterminaUC = false % encendido/apagado de las unidades de generaci�n
        ConsideraContingenciaN1 = false % Despacho preventivo: flujos de l�neas y trafos luego de una falla deben permanecer dentro de los l�mites
        ConsideraEstadoPostContingencia = false % se considera el re-despacho de las unidades de generaci�n luego de ocurrida la falla (actuaci�n del control primario)
        ConsideraReservasMinimasSistema = false
        EstrategiaReservasMinimasSistema = 1 % 1: Pmax generador m�s grande; 2: Pmax generador m�s grande en operaci�n
        ConsideraRestriccionROCOF = false
        ROCOFMax = 0.125 % siepmre positivo
        
        OptimizaVoltajeOperacion = false % a�n no implementado
        FlujoDCconPerdidas = false % a�n no implementado
        
        % Resultados
        NivelDetalleResultados = 2 % 0: sin detalle, 2: m�ximo detalle
        PorcentajeUsoFlujosAltos = 0.95 % l�mite para guardar elementos de red con flujos altos/bajos
        PorcentajeUsoFlujosBajos = 0.5
        PorcentajeUsoAltoBateria = 0.99
        PorcentajeUsoBajoBateria = 0.5
        
        % Optimizador y m�todo de optimizaci�n
        OptimizaSoCInicialBaterias = true
        Solver = 'Xpress'; %'Xpress' o 'Intlinprog'
        MetodoOptimizacionAC = 'IP'  % m�todo del punto interior. Alternativa es ...
        
        % Par�metros para DC-OPF
        Penalizacion = 10000 % penalizaciones ens y recorte res en operaci�n normal. Valor equivalente a $/MWh
        
        % Penalizaciones en contingencia
        PenalizacionRecorteRES = 1000 %$/MWh
        PenalizacionENS = 1000 %$/MWh
        
        DecimalesRedondeo = 5
        AnguloMaximoBuses = pi
        
        ExportaResultadosFormatoExcel = false
    end
    
    methods        
        function val = entrega_funcion_objetivo(this)
            val = this.FuncionObjetivo;
        end
        
        function val = entrega_tipo_flujo(this) 
            val = this.TipoFlujoPotencia;
        end
        
        function val = entrega_tipo_restricciones_seguridad(this)
            val = this.TipoRestriccionesSeguridad;
        end
        
        function val = entrega_metodo_optimizacion(this)
            val = this.MetodoOptimizacionAC;
        end
        
        function val = entrega_flujo_dc_con_perdidas(this)
            val = this.FlujoDCconPerdidas;
        end
        
        function val = entrega_optimiza_voltaje_operacion(this)
            val = this.OptimizaVoltajeOperacion;
        end
        
        function val = entrega_tipo_problema(this)
            val = this.TipoProblema;
        end
        
        function val = entrega_penalizacion_recorte_res(this)
            val = this.PenalizacionRecorteRES;
        end
        
        function val = entrega_penalizacion_ens(this)
            val = this.PenalizacionENS;
        end
        
        function val = entrega_penalizacion(this)
            val = this.Penalizacion;
        end        
    end
end
