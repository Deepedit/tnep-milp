function importa_caso_estudio_mcmc(paropt, varargin)
    path = './input/InputDataMCMC/';
    filename = [path 'CasosEstudio.xlsx']; 

    [~,~,datos] = xlsread(filename);
    [n, m] = size(datos);
    
    if nargin > 1
        caso_estudio = varargin{1};
    else
        caso_estudio = 0;
    end
    columna_caso = 0;
    if caso_estudio > 0
        for col = 3:m
            if datos{1,col} == caso_estudio
                columna_caso = col;
                break;
            end
        end
        if columna_caso == 0
            error = MException('importa_caso_estudio_aco:importa_caso_estudio_aco',...
            ['Caso de estudio ' num2str(caso_estudio) ' no se encuentra']);
            throw(error)
        end
    end
    
    for fila = 2:n
        parametro = datos{fila,1};
        valor = datos{fila,2};
        if columna_caso > 0 && ~sum(isnan(datos{fila,columna_caso}))
            valor = datos{fila,columna_caso};
        end
        agrega_parametro(paropt, parametro, valor);
    end
    % actualiza parametros a actualizar
    paropt.CantidadEtapas = (paropt.TFin - paropt.TInicio + 1)/paropt.DeltaEtapa;
end

function agrega_parametro(paropt, parametro, valor)
    if strcmp(parametro,'NombreSistema')
        paropt.NombreSistema = valor;
    elseif strcmp(parametro,'PathSistema')
        paropt.PathSistema = valor;
    elseif strcmp(parametro,'Output')
        paropt.Output = valor;
    elseif strcmp(parametro,'IdPuntosOperacion')
        paropt.IdPuntosOperacion = valor;
    elseif strcmp(parametro,'IdEscenario')
        paropt.IdEscenario = valor;
    elseif strcmp(parametro,'ConsideraReconductoring')
        paropt.ConsideraReconductoring = valor;
    elseif strcmp(parametro,'ConsideraCompensacionSerie')
        paropt.ConsideraCompensacionSerie = valor;
    elseif strcmp(parametro,'ConsideraVoltageUprating')
        paropt.ConsideraVoltageUprating = valor;
    elseif strcmp(parametro,'CambioConductorVoltageUprating')
        paropt.CambioConductorVoltageUprating = valor;
    elseif strcmp(parametro,'ElijeTipoConductor')
        paropt.ElijeTipoConductor = valor;
    elseif strcmp(parametro,'ElijeVoltageLineasNuevas')
        paropt.ElijeVoltageLineasNuevas = valor;
    elseif strcmp(parametro,'ComputoParalelo')
        paropt.ComputoParalelo = valor;
    elseif strcmp(parametro,'ConsideraIncertidumbre')
        paropt.ConsideraIncertidumbre = valor;
    elseif strcmp(parametro,'CantidadSimulacionesEscenarios')
        paropt.CantidadSimulacionesEscenarios = valor;
    elseif strcmp(parametro,'CantidadCadenas')
        paropt.CantidadCadenas = valor;
    elseif strcmp(parametro,'EstrategiaMCMC')
        paropt.EstrategiaMCMC = valor;
    elseif strcmp(parametro,'EstrategiaProyectosModificar')
        paropt.EstrategiaProyectosModificar = valor;
    elseif strcmp(parametro,'CantidadProyectosModificar')
        paropt.CantidadProyectosModificar = valor;
    elseif strcmp(parametro,'PorcentajeProyectosModificar')
        paropt.PorcentajeProyectosModificar = valor;
    elseif strcmp(parametro,'EstrategiaProyectosOptimizar')
        paropt.EstrategiaProyectosOptimizar = valor;
    elseif strcmp(parametro,'CantidadProyectosOptimizar')
        paropt.CantidadProyectosOptimizar = valor;
    elseif strcmp(parametro,'MinCantidadProyectosEnPlanOptimizar')
        paropt.MinCantidadProyectosEnPlanOptimizar = valor;
    elseif strcmp(parametro,'PorcentajeProyectosOptimizar')
        paropt.PorcentajeProyectosOptimizar = valor;
    elseif strcmp(parametro,'MinPorcentajeProyectosEnPlanOptimizar')
        paropt.MinPorcentajeProyectosEnPlanOptimizar = valor;
    elseif strcmp(parametro,'CantProyOptimizarPorModificadoCercano')
        paropt.CantProyOptimizarPorModificadoCercano = valor;
    elseif strcmp(parametro,'MinCantidadProyectosEnPlanOptimizarCercano')
        paropt.MinCantidadProyectosEnPlanOptimizarCercano = valor;
    elseif strcmp(parametro,'CantidadIntentosFallidosAdelanta')
        paropt.CantidadIntentosFallidosAdelanta = valor;
    elseif strcmp(parametro,'MaxCantidadPasos')
        paropt.MaxCantidadPasos = valor;
    elseif strcmp(parametro,'PasoActualizacion')
        paropt.PasoActualizacion = valor;
    elseif strcmp(parametro,'SigmaFuncionLikelihood')
        paropt.SigmaFuncionLikelihood = valor;
    elseif strcmp(parametro,'SigmaParametros')
        paropt.SigmaParametros = valor;
    elseif strcmp(parametro,'ConsideraTransicionEstados')
        paropt.ConsideraTransicionEstados = valor;
    elseif strcmp(parametro,'CantidadCalculosToleranciaSigma')
        paropt.CantidadCalculosToleranciaSigma = valor;
    elseif strcmp(parametro,'PasosParaToleranciaSigma')
        paropt.PasosParaToleranciaSigma = valor;
    elseif strcmp(parametro,'NToleranciaSigma')
        paropt.NToleranciaSigma = valor;
    elseif strcmp(parametro,'OptimizaEnCalculosTolerancia')
        paropt.OptimizaEnCalculosTolerancia = valor;
    elseif strcmp(parametro,'LimiteInferiorR')
        paropt.LimiteInferiorR = valor;
    elseif strcmp(parametro,'LimiteSuperiorR')
        paropt.LimiteSuperiorR = valor;
    elseif strcmp(parametro,'FactorMultCambioSigma')
        paropt.FactorMultCambioSigma = valor;
    elseif strcmp(parametro,'SigmaMax')
        paropt.SigmaMax = valor;
    elseif strcmp(parametro,'TInicio')
        paropt.TInicio = valor;
    elseif strcmp(parametro,'TFin')
        paropt.TFin = valor;        
    elseif strcmp(parametro,'SigmaMin')
        paropt.SigmaMin = valor;
    elseif strcmp(parametro,'NsIntercambioCadenas')
        paropt.NsIntercambioCadenas = valor;
    elseif strcmp(parametro,'NivelDebug')
        paropt.NivelDebug = valor;
    elseif strcmp(parametro,'NivelDebugAdmProy')
        paropt.NivelDebugAdmProy = valor;
    elseif strcmp(parametro,'CantidadProyOptimizarTolSigma')
        paropt.CantidadProyOptimizarTolSigma = valor;
    elseif strcmp(parametro,'TiempoEntradaOperacionTradicional')
        paropt.TiempoEntradaOperacionTradicional = valor;
    elseif strcmp(parametro,'TiempoEntradaOperacionUprating')
        paropt.TiempoEntradaOperacionUprating = valor;
    elseif strcmp(parametro,'MinCantidadProyEnPlanOptimizarTolSigma')
        paropt.MinCantidadProyEnPlanOptimizarTolSigma = valor;
    elseif strcmp(parametro,'NivelDebugParalelo')
        paropt.NivelDebugParalelo= valor;
    elseif strcmp(parametro,'NivelDebugOPF')
        paropt.NivelDebugOPF= valor;
    elseif strcmp(parametro,'NivelDebugFP')
        paropt.NivelDebugFP= valor;
    elseif strcmp(parametro,'NivelDebug')
        paropt.NivelDebug= valor;
    elseif strcmp(parametro,'NivelDebugAdmProy')
        paropt.NivelDebugAdmProy= valor;
    elseif strcmp(parametro,'NivelDetalleResultadosOPF')
        paropt.NivelDetalleResultadosOPF = valor;
    elseif strcmp(parametro,'NivelDetalleResultadosFP')
        paropt.NivelDetalleResultadosFP = valor;
    elseif strcmp(parametro,'ConsideraFlujosAC')
        paropt.ConsideraFlujosAC = valor;
    else
        error = MException('importa_caso_estudio:importa_caso_estudio',...
        ['Parametro ' parametro ' no implementado']);
        throw(error)
    end
end