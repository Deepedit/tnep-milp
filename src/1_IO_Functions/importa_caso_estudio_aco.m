function importa_caso_estudio_aco(paropt, varargin)
    path = './input/InputDataACO/';
    filename = [path 'CasosEstudio.xlsx']; 

    [~,~,datos] = xlsread(filename);
    [n, m] = size(datos);

    if nargin > 1
        caso_estudio = varargin{1};
    else
        caso_estudio = -1;
    end
    columna_caso = 0;
    if caso_estudio >= 0
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
    paropt.CantidadEtapas = (paropt.TFin - paropt.TInicio + 1)/paropt.DeltaEtapa;
end

function agrega_parametro(paropt, parametro, valor)
    if strcmp(parametro,'NombreSistema')
        paropt.NombreSistema = valor;
    elseif strcmp(parametro,'IdPuntosOperacion')
        paropt.IdPuntosOperacion = valor;
    elseif strcmp(parametro,'ComputoParalelo')
        paropt.ComputoParalelo = valor;
    elseif strcmp(parametro,'CantWorkers')
        paropt.CantWorkers = valor;
    elseif strcmp(parametro,'OptimizaUsoMemoriaParalelo')
        paropt.OptimizaUsoMemoriaParalelo = valor;
    elseif strcmp(parametro,'Solver')
        paropt.Solver = valor;
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
    elseif strcmp(parametro,'CantidadHormigas')
        paropt.CantidadHormigas = valor;
    elseif strcmp(parametro,'CantidadMejoresPlanes')
        paropt.CantidadMejoresPlanes = valor;
    elseif strcmp(parametro,'MaxNroReparacionesPorEtapa')
        paropt.MaxNroReparacionesPorEtapa = valor;
    elseif strcmp(parametro,'MaxCantidadGeneracionPlanesPorEtapa')
        paropt.MaxCantidadGeneracionPlanesPorEtapa = valor;
    elseif strcmp(parametro,'MaxCantidadPlanesDesechados')
        paropt.MaxCantidadPlanesDesechados = valor;
    elseif strcmp(parametro,'MaxCantidadReparaciones')
        paropt.MaxCantidadReparaciones = valor;
    elseif strcmp(parametro,'CantidadPlanesBusquedaLocal')
        paropt.CantidadPlanesBusquedaLocal = valor;
    elseif strcmp(parametro,'PlanMasProbableFeromonasDesdeIteracion')
        paropt.PlanMasProbableFeromonasDesdeIteracion = valor;
    elseif strcmp(parametro,'CantidadIntentosFallidosAdelanta')
        paropt.CantidadIntentosFallidosAdelanta = valor;
    elseif strcmp(parametro,'BLEliminaDesplazaProyectos')
        paropt.BLEliminaDesplazaProyectos = valor;
    elseif strcmp(parametro,'BLEliminaDesplazaCantProyCompararBase')
        paropt.BLEliminaDesplazaCantProyCompararBase = valor;
    elseif strcmp(parametro,'BLEliminaDesplazaCantProyCompararSinMejora')
        paropt.BLEliminaDesplazaCantProyCompararSinMejora = valor;
    elseif strcmp(parametro,'BLEliminaDesplazaCantBusquedaFallida')
        paropt.BLEliminaDesplazaCantBusquedaFallida = valor;
    elseif strcmp(parametro,'BLEliminaDesplazaProyAlComienzo')
        paropt.BLEliminaDesplazaProyAlComienzo = valor;
    elseif strcmp(parametro,'BLEliminaDesplazaProyNormal')
        paropt.BLEliminaDesplazaProyNormal = valor;
    elseif strcmp(parametro,'BLEliminaDesplazaNuevoDesplaza')
        paropt.BLEliminaDesplazaNuevoDesplaza = valor;
    elseif strcmp(parametro,'BLEliminaDesplazaNuevoAgrega')
        paropt.BLEliminaDesplazaNuevoAgrega= valor;
    elseif strcmp(parametro,'CantidadIteracionesSinMejora')
        paropt.CantidadIteracionesSinMejora = valor;
    elseif strcmp(parametro,'MaxItPlanificacion')
        paropt.MaxItPlanificacion = valor;
    elseif strcmp(parametro,'MinItPlanificacion')
        paropt.MinItPlanificacion = valor;
    elseif strcmp(parametro,'NivelDebugACO')
        paropt.NivelDebugACO = valor;
    elseif strcmp(parametro,'NivelDebugAdmProy')
        paropt.NivelDebugAdmProy = valor;
    elseif strcmp(parametro,'NivelDebugParalelo')
        paropt.NivelDebugParalelo = valor;
    elseif strcmp(parametro,'ReparaPlanSecuencial')
        paropt.ReparaPlanSecuencial = valor;
    elseif strcmp(parametro,'ReparaPlanCantCompararIndirecto')
        paropt.ReparaPlanCantCompararIndirecto = valor;
    elseif strcmp(parametro,'NivelDebugParalelo')
        paropt.NivelDebugParalelo = valor;
    elseif strcmp(parametro,'PrioridadAdelantaProyectos')
        paropt.PrioridadAdelantaProyectos = valor;
    elseif strcmp(parametro,'PrioridadDesplazaSobreElimina')
        paropt.PrioridadDesplazaSobreElimina = valor;
    elseif strcmp(parametro,'ProbabilidadConstruccionInicial')
        paropt.ProbabilidadConstruccionInicial = valor;
    elseif strcmp(parametro,'ConsideraTransicionEstados')
        paropt.ConsideraTransicionEstados = valor;
    elseif strcmp(parametro,'CreaPlanOptimo')
        paropt.CreaPlanOptimo= valor;
    elseif strcmp(parametro,'ArchivoPlanOptimo')
        paropt.ArchivoPlanOptimo= valor;
    elseif strcmp(parametro,'HojaPlanOptimo')
        paropt.HojaPlanOptimo = valor;
    elseif strcmp(parametro,'TInicio')
        paropt.TInicio = valor;
    elseif strcmp(parametro,'TFin')
        paropt.TFin = valor;
    elseif strcmp(parametro,'BLEliminaDesplazaCambioUprating')
        paropt.BLEliminaDesplazaCambioUprating = valor;
    else
        error = MException('importa_caso_estudio:importa_caso_estudio',...
        ['Parametro ' parametro ' no implementado']);
        throw(error)
    end
end