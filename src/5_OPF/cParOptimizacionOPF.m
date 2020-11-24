classdef cParOptimizacionOPF < handle
    % clase que guarda los parámetros de optimización
    properties        
        % Parámetros globales
        FuncionObjetivo = 'MinC'  % Alternativas: OptV --> voltaje óptimo
        TipoFlujoPotencia = 'DC' %DC
        TipoRestriccionesSeguridad = 'N0'  % N1 corresponde a criterio N-1
        TipoProblema = 'Despacho'  % alternativa: 'Redespacho'

        % Modelo
        DeterminaUC = false % encendido/apagado de las unidades de generación
        ConsideraContingenciaN1 = false % Despacho preventivo: flujos de líneas y trafos luego de una falla deben permanecer dentro de los límites
        ConsideraEstadoPostContingencia = false % se considera el re-despacho de las unidades de generación luego de ocurrida la falla (actuación del control primario)
        ConsideraReservasMinimasSistema = false
        EstrategiaReservasMinimasSistema = 1 % 1: Pmax generador más grande; 2: Pmax generador más grande en operación
        ConsideraRestriccionROCOF = false
        ROCOFMax = 0.125 % siepmre positivo
        
        OptimizaVoltajeOperacion = false % aún no implementado
        FlujoDCconPerdidas = false % aún no implementado
        
        % Resultados
        NivelDetalleResultados = 2 % 0: sin detalle, 2: máximo detalle
        PorcentajeUsoFlujosAltos = 0.95 % límite para guardar elementos de red con flujos altos/bajos
        PorcentajeUsoFlujosBajos = 0.5
        PorcentajeUsoAltoBateria = 0.99
        PorcentajeUsoBajoBateria = 0.5
        
        % Optimizador y método de optimización
        OptimizaSoCInicialBaterias = true
        Solver = 'Xpress'; %'Xpress' o 'Intlinprog'
        MetodoOptimizacionAC = 'IP'  % método del punto interior. Alternativa es ...
        
        % Parámetros para DC-OPF
        Penalizacion = 10000 % penalizaciones ens y recorte res en operación normal. Valor equivalente a $/MWh
        
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
