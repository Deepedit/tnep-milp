function importa_caso_estudio_milp(paropt, varargin)
    path = './input/InputDataMILP/';
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
            error = MException('importa_caso_estudio_milp:importa_caso_estudio_aco',...
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
    elseif strcmp(parametro,'ConsideraTransicionEstados')
        paropt.ConsideraTransicionEstados = valor;
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
    elseif strcmp(parametro,'AnguloMaximoBuses')
        paropt.AnguloMaximoBuses = valor;
    elseif strcmp(parametro,'DecimalesRedondeo')
        paropt.DecimalesRedondeo = valor;
    elseif strcmp(parametro,'ImprimeProblemaOptimizacion')
        paropt.ImprimeProblemaOptimizacion = valor;
    elseif strcmp(parametro,'MaxMemory')
        paropt.MaxMemory= valor;
    elseif strcmp(parametro,'MaxTime')
        paropt.MaxTime= valor;
    elseif strcmp(parametro,'TInicio')
        paropt.TInicio = valor;
    elseif strcmp(parametro,'TFin')
        paropt.TFin = valor;
    elseif strcmp(parametro,'TiempoEntradaOperacionTradicional')
        paropt.TiempoEntradaOperacionTradicional = valor;
    elseif strcmp(parametro,'TiempoEntradaOperacionUprating')
        paropt.TiempoEntradaOperacionUprating = valor;
    elseif strcmp(parametro,'ConsideraValorResidualElementos')
        paropt.ConsideraValorResidualElementos = valor;
    elseif strcmp(parametro,'ComputoParalelo')
        paropt.ComputoParalelo = valor;
    elseif strcmp(parametro,'MaxIterBenders')
        paropt.MaxIterBenders = valor;
    elseif strcmp(parametro,'NivelDebug')
        paropt.NivelDebug = valor;
    elseif strcmp(parametro,'ImprimeProblemaOptimizacion')
        paropt.ImprimeProblemaOptimizacion = valor;
    elseif strcmp(parametro,'ImprimeResultadosProtocolo')
        paropt.ImprimeResultadosProtocolo = valor;
    elseif strcmp(parametro,'NivelSubetapasParaCortes')
        paropt.NivelSubetapasParaCortes = valor;
    elseif strcmp(parametro,'ConsideraAlphaMin')
        paropt.ConsideraAlphaMin = valor;
    elseif strcmp(parametro,'FactorMultiplicadorBigM')
        paropt.FactorMultiplicadorBigM = valor;
    elseif strcmp(parametro,'ExportaResultadosFormatoExcel')
        paropt.ExportaResultadosFormatoExcel = valor;
    elseif strcmp(parametro,'MaxGap')
        paropt.MaxGap= valor;
    elseif strcmp(parametro,'Penalizacion')
        paropt.Penalizacion= valor;
    else
        error = MException('importa_caso_estudio:importa_caso_estudio',...
        ['Parametro ' parametro ' no implementado']);
        throw(error)
    end
end