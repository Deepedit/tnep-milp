classdef cSistemaElectricoPotencia < handle
    % Clase que representa el sistema electrico de potencia
    % Cada SEP tiene subestaciones, líneas, consumoms y
    % generadores
    %
    properties
        Nombre = 'SistemaElectricoPotencia'
        
        %Elementos de red
        Subestaciones = cSubestacion.empty
        Lineas = cLinea.empty
        RelLineasSEParIndex = []
        IdSubestacionSlack = 0;
        
        Consumos = cConsumo.empty

        Generadores = cGenerador.empty
        TipoGeneradores = [] % 1:central térmica, 2: central hidráulica; 3: ernc
        IndiceGeneradoresDespachables = []
        
        Condensadores = cCondensador.empty
        Reactores = cReactor.empty
        Transformadores2D = cTransformador2D.empty
        Baterias = cBateria.empty
        Embalses = cEmbalse.empty
        Almacenamientos = cAlmacenamiento.empty
        
        %ElementosRed guarda todos los elementos de red del SEP. Debiera
        %eliminarse
        
        ElementosRed = cElementoRed.empty
        
        ProyectosExpansionTx = [];
        ProyectosExpansionGx = [];
                        
        % Punteros a otros programas
        % @Lena: ich habe das Parameter pFP hinzugefügt. Du sollst beim
        % Konstruktor im Lastflussrechnung das Pointer hier speichern
        % (siehe Konstruktor des DCOPF).
        pOPF = cOPF.empty
        pFP = cFlujoPotencia.empty
        pResEvaluacion = cResultadoEvaluacionSEP.empty        
    end
    
    methods        
        function agrega_subestacion(this, subestacion)
            cant_se = length(this.Subestaciones)+1;
            this.Subestaciones(cant_se,1) = subestacion;
            subestacion.Id = cant_se;
            
            %agrega elemento de red
            cant_elementos = length(this.ElementosRed)+1;
            this.ElementosRed(cant_elementos,1) = subestacion;
            subestacion.IdElementoRed = cant_elementos;
        end
        
        function correcto = agrega_proyecto(this, proyecto, varargin)
            protocoliza = false;
            if nargin > 2
                protocoliza = varargin{1};
            end

            tipo_proyecto = proyecto.entrega_id_tipo_proyecto();
            if  tipo_proyecto == 1 % proyecto de expansión de transmisión
                if ~isempty(find(this.ProyectosExpansionTx == proyecto.entrega_indice(), 1))
                    error = MException('cSistemaElectricoPotencia:agrega_proyecto',['Proyecto de Tx ' num2str(proyecto.entrega_indice()) ' no se puede agregar al sep porque ya esta. Proyectos en sep: ' num2str(this.ProyectosExpansionTx)]);
                    throw(error)
                end
            elseif tipo_proyecto == 2 % proyecto de expansión de generación
                if ~isempty(find(this.ProyectosExpansionGx == proyecto.entrega_indice(), 1))
                    error = MException('cSistemaElectricoPotencia:agrega_proyecto',['Proyecto de Gx ' num2str(proyecto.entrega_indice()) ' no se puede agregar al sep porque ya esta. Proyectos en sep: ' num2str(this.ProyectosExpansionGx)]);
                    throw(error)
                end
            else
                    error = MException('cSistemaElectricoPotencia:agrega_proyecto',['Tipo de proyecto ' num2str(proyecto.entrega_id_tipo_proyecto()) ' aún no implementado']);
                    throw(error)
            end
            
            for i = 1:length(proyecto.Elemento)
                if strcmp(proyecto.Accion{i}, 'A')
                    el_red = proyecto.Elemento(i).crea_copia();
                    if strcmp(el_red.entrega_tipo_elemento_red(), 'ElementoSerie')
                        SE1 = this.entrega_subestacion(el_red.entrega_nombre_se(1), false);
                        SE2 = this.entrega_subestacion(el_red.entrega_nombre_se(2), false);
                        
                        if isempty(SE1) || isempty(SE2)
                            correcto = false;
                            texto = '';
                            if isempty(SE1)
                            	texto = [texto ' se1 no se encuentra (' el_red.entrega_nombre_se(1) '); '];
                            end
                            if isempty(SE2)
                                texto = [texto ' se2 no se encuentra. (' el_red.entrega_nombre_se(2) '); '];
                            end
                            if protocoliza
                                prot = cProtocolo.getInstance;
                                prot.imprime_texto(['Proyecto ' num2str(proyecto.Indice) ' ' proyecto.Nombre ' no pudo ser implementado, ya que' ...
                                    ' para elemento ' el_red.entrega_nombre() texto]);
                            end
                            error = MException('cSistemaElectricoPotencia:agrega_proyecto',['Error al agregar proyecto ' num2str(proyecto.entrega_indice()) '. ' texto]);
                            throw(error)                      
                            %return;
                        end
                        if isa(el_red, 'cLinea') || isa(el_red, 'cTransformador2D')
                            el_red.inserta_subestacion(SE1,1);
                            el_red.inserta_subestacion(SE2,2);
                        else
                            texto = ['Tipo de elemento ' class(el_red) ' no implementado. Sólo líneas y transformadores'];
                            error = MException('cSistemaElectricoPotencia:agrega_proyecto',texto);
                            throw(error)
                        end
                            
                        SE1.agrega_elemento_red(el_red);
                        SE2.agrega_elemento_red(el_red);                        
                    elseif strcmp(el_red.entrega_tipo_elemento_red(), 'ElementoParalelo')
                        SE = this.entrega_subestacion(el_red.entrega_nombre_se(), false);
                        if isempty(SE)
                            correcto = false;
                            if protocoliza
                                prot = cProtocolo.getInstance;
                                prot.imprime_texto(['Proyecto ' num2str(proyecto.Indice) ' ' proyecto.Nombre ' no pudo ser implementado, ya que ' ...
                                    ' para elemento ' el_red.entrega_nombre() ' subestacion ' SE.entrega_nombre() ' no pudo ser encontrada.']);
                            end
                            
                            return;
                        end

                        el_red.inserta_subestacion(SE);
                        SE.agrega_elemento_red(el_red);

                        if isa(el_red, 'cGenerador') && el_red.tiene_almacenamiento()
                            almacenamiento = this.entrega_almacenamiento(el_red.entrega_nombre_almacenamiento());
                            almacenamiento.agrega_turbina_descarga(el_red);
                            el_red.inserta_almacenamiento(almacenamiento);
                        end
                        
                    elseif strcmp(el_red.entrega_tipo_elemento_red(), 'Bus')
                        % nada que hacer, ya que elemento de red se agrega
                        % al final
                    elseif strcmp(el_red.entrega_tipo_elemento_red(), 'Almacenamiento')
                        % nada que hacer, ya que elemento de red se agrega
                        % al final
                    else
                        texto = ['tipo elemento de red ' el_red.entrega_tipo_elemento_red() ' no implementado aún'];
                        error = MException('cSistemaElectricoPotencia:agrega_proyecto',texto);
                        throw(error)                        
                    end                    
                    this.agrega_elemento_red(el_red);

                    if ~isempty(this.pOPF)
                    	this.pOPF.agrega_variable(el_red);
                    end
                    if ~isempty(this.pFP)
                        this.pFP.agrega_variable(el_red);
                    end
                    if ~isempty(this.pResEvaluacion)
                        this.pResEvaluacion.agrega_variable(el_red);
                    end
                else
                    % Acción del proyecto consiste en remover elemento (se quita del SEP)
                    if strcmp(proyecto.Elemento(i).entrega_tipo_elemento_red(), 'ElementoSerie')
                        el_red = this.entrega_elemento(class(proyecto.Elemento(i)), proyecto.Elemento(i).entrega_nombre(), false);
                        if isempty(el_red)
                            correcto = false;
                            if protocoliza
                                prot = cProtocolo.getInstance;
                                prot.imprime_texto(['Proyecto ' num2str(proyecto.Indice) ' ' proyecto.Nombre ' no pudo ser implementado, ya que ' ...
                                    ' elemento ' proyecto.Elemento(i).entrega_nombre() ' no se encuentra en el SEP']);
                                this.imprime_elementos(class(proyecto.Elemento(i)));
                            end
                            return;
                        end
                        % verificar si hay que modificar OPF
                        if ~isempty(this.pOPF)
                        	this.pOPF.elimina_variable(el_red);
                        end
                        if ~isempty(this.pFP)
                            this.pFP.elimina_variable(el_red);
                        end
                        if ~isempty(this.pResEvaluacion)
                            this.pResEvaluacion.elimina_variable(el_red);
                        end
                        
                        this.elimina_elemento_red(el_red);
                    else
                        error = MException('cSistemaElectricoPotencia:agrega_proyecto','Sólo se han implementado proyectos de cambio de elementos en serie');
                        throw(error)
                    end
                end
            end
            if tipo_proyecto == 1
                this.ProyectosExpansionTx = [this.ProyectosExpansionTx proyecto.entrega_indice()];
            elseif tipo_proyecto == 2
                this.ProyectosExpansionGx = [this.ProyectosExpansionGx proyecto.entrega_indice()];
            end
            correcto = true;
        end

        function correcto = elimina_proyecto(this, proyecto, varargin)
            protocoliza = false;
            if nargin > 2
                protocoliza = varargin{1};
            end
            
            for i = length(proyecto.Elemento):-1:1
                if strcmp(proyecto.Accion{i}, 'R')
                    % Acción en el proyecto es de remover, por lo que hay que agregar en este caso. Por ahora sólo elementos en serie
                    el_red = proyecto.Elemento(i).crea_copia();
                    if strcmp(el_red.entrega_tipo_elemento_red(), 'ElementoSerie')
                        SE1 = this.entrega_subestacion(el_red.entrega_nombre_se(1), false);
                        SE2 = this.entrega_subestacion(el_red.entrega_nombre_se(2), false);
                        
                        if isempty(SE1) || isempty(SE2)
                            correcto = false;
                            texto = '';
                            if isempty(SE1)
                            	texto = [texto ' se1 no se encuentra (' el_red.entrega_nombre_se(1) '); '];
                            end
                            if isempty(SE2)
                                texto = [texto ' se2 no se encuentra. (' el_red.entrega_nombre_se(2) '); '];
                            end
                            if protocoliza
                                prot = cProtocolo.getInstance;
                                prot.imprime_texto(['Proyecto ' num2str(proyecto.Indice) ' ' proyecto.Nombre ' no pudo ser implementado, ya que' ...
                                    ' para elemento ' el_red.entrega_nombre() texto]);
                            end
                            error = MException('cSistemaElectricoPotencia:elimina_proyecto',texto);
                            throw(error)                      
                            %return;
                        end
                        if isa(el_red, 'cLinea') || isa(el_red, 'cTransformador2D')
                            el_red.inserta_subestacion(SE1,1);
                            el_red.inserta_subestacion(SE2,2);
                        else
                            texto = ['Tipo de elemento ' class(el_red) ' no implementado. Sólo líneas y transformadores'];
                            error = MException('cSistemaElectricoPotencia:elimina_proyecto',texto);
                            throw(error)
                        end
                            
                        SE1.agrega_elemento_red(el_red);
                        SE2.agrega_elemento_red(el_red);
                    else
                        % elementos paralelos o buses. Este caso no se ha
                        % implementado aún
                        error = MException('cSistemaElectricoPotencia:elimina_proyecto','Elemento a eliminar no es elemento en serie. Sólo se han implementado proyectos de cambio de elementos en serie');
                        throw(error)
                        
%                     elseif strcmp(el_red.entrega_tipo_elemento_red(), 'ElementoParalelo')
%                         SE = this.entrega_subestacion(el_red.entrega_nombre_se(), false);
%                         if isempty(SE)
%                             correcto = false;
%                             if protocoliza
%                                 prot = cProtocolo.getInstance;
%                                 prot.imprime_texto(['Proyecto ' num2str(proyecto.Indice) ' ' proyecto.Nombre ' no pudo ser implementado, ya que ' ...
%                                     ' para elemento ' el_red.entrega_nombre() ' subestacion ' SE.entrega_nombre() ' no pudo ser encontrada.']);
%                             end
%                             
%                             return;
%                         end
% 
%                         el_red.inserta_subestacion(SE);
%                         SE.agrega_elemento_red(el_red);
%                         
%                     elseif strcmp(el_red.entrega_tipo_elemento_red(), 'Bus')
%                         % nada que hacer, ya que elemento de red se agrega
%                         % al final
%                     else
%                         texto = ['tipo elemento de red ' el_red.entrega_tipo_elemento_red() ' no implementado aún'];
%                         error = MException('cSistemaElectricoPotencia:elimina_proyecto',texto);
%                         throw(error)                        
                    end
                    this.agrega_elemento_red(el_red);

                    if ~isempty(this.pOPF)
                    	this.pOPF.agrega_variable(el_red);
                    end
                    if ~isempty(this.pFP)
                        this.pFP.agrega_variable(el_red);
                    end
                    if ~isempty(this.pResEvaluacion)
                        this.pResEvaluacion.agrega_variable(el_red);
                    end
                    
                else
                    % elemento se agrega dentro del proyecto a eliminar, por lo que se elimina del SEP
                    if strcmp(proyecto.Elemento(i).entrega_tipo_elemento_red(), 'ElementoSerie')
                        el_red = this.entrega_elemento(class(proyecto.Elemento(i)), proyecto.Elemento(i).entrega_nombre(), false);
                        if isempty(el_red)
                            correcto = false;
                            if protocoliza
                                prot = cProtocolo.getInstance;
                                prot.imprime_texto(['Proyecto ' num2str(proyecto.Indice) ' ' proyecto.Nombre ' no pudo ser implementado, ya que ' ...
                                    ' elemento ' proyecto.Elemento(i).entrega_nombre() ' no se encuentra en el SEP']);
                                this.imprime_elementos(class(proyecto.Elemento(i)));
                            end
                            texto = ['Proyecto ' num2str(proyecto.Indice) ' ' proyecto.Nombre ' no pudo ser implementado, ya que ' ...
                                    ' elemento ' proyecto.Elemento(i).entrega_nombre() ' no se encuentra en el SEP'];
                            texto = [texto '. Proyectos actuales en el SEP: '];
                            for ii = 1:length(this.ProyectosExpansionTx)
                                texto = [texto ' ' num2str(this.ProyectosExpansionTx(ii))];
                            end
                            error = MException('cSistemaElectricoPotencia:elimina_proyecto',texto);
                            throw(error)                        
%                            return;
                        end
                        % verificar si hay que modificar opf
                        if ~isempty(this.pOPF)
                        	this.pOPF.elimina_variable(el_red);
                        end
                        if ~isempty(this.pFP)
                            this.pFP.elimina_variable(el_red);
                        end
                        if ~isempty(this.pResEvaluacion)
                            this.pResEvaluacion.elimina_variable(el_red);
                        end
                        
                        this.elimina_elemento_red(el_red);
                    elseif strcmp(proyecto.Elemento(i).entrega_tipo_elemento_red(), 'ElementoParalelo')                        
                        el_red = this.entrega_elemento(class(proyecto.Elemento(i)), proyecto.Elemento(i).entrega_nombre(), false);
                        if isempty(el_red)
                            correcto = false;
                            if protocoliza
                                prot = cProtocolo.getInstance;
                                prot.imprime_texto(['Proyecto ' num2str(proyecto.Indice) ' ' proyecto.Nombre ' no pudo ser implementado, ya que ' ...
                                    ' elemento ' proyecto.Elemento(i).entrega_nombre() ' no se encuentra en el SEP']);
                                this.imprime_elementos(class(proyecto.Elemento(i)));
                            end
                            texto = ['Proyecto ' num2str(proyecto.Indice) ' ' proyecto.Nombre ' no pudo ser implementado, ya que ' ...
                                    ' elemento ' proyecto.Elemento(i).entrega_nombre() ' no se encuentra en el SEP'];
                            texto = [texto '. Proyectos actuales en el SEP: '];
                            for ii = 1:length(this.ProyectosExpansionTx)
                                texto = [texto ' ' num2str(this.ProyectosExpansionTx(ii))];
                            end
                            error = MException('cSistemaElectricoPotencia:elimina_proyecto',texto);
                            throw(error)                        
%                            return;
                        end
                        
                        % verificar si hay que modificar opf
                        if ~isempty(this.pOPF)
                        	this.pOPF.elimina_variable(el_red);
                        end
                        if ~isempty(this.pFP)
                            this.pFP.elimina_variable(el_red);
                        end
                        if ~isempty(this.pResEvaluacion)
                            this.pResEvaluacion.elimina_variable(el_red);
                        end
                        
                        if isa(el_red, 'cGenerador') && el_red.tiene_almacenamiento()
                            almacenamiento = el_red.entrega_almacenamiento();
                            almacenamiento.elimina_turbina_descarga(el_red);
                        end
                        
                        this.elimina_elemento_red(el_red);
                    elseif strcmp(proyecto.Elemento(i).entrega_tipo_elemento_red(), 'Bus')
                        el_red = this.entrega_elemento(class(proyecto.Elemento(i)), proyecto.Elemento(i).entrega_nombre(), false);
                        if isempty(el_red)
                            correcto = false;
                            if protocoliza
                                prot = cProtocolo.getInstance;
                                prot.imprime_texto(['Proyecto ' num2str(proyecto.Indice) ' ' proyecto.Nombre ' no pudo ser implementado, ya que ' ...
                                    ' elemento ' proyecto.Elemento(i).entrega_nombre() ' no se encuentra en el SEP']);
                                this.imprime_elementos(class(proyecto.Elemento(i)));
                            end
                            return;
                        end
                        % verificar si hay que modificar opf
                        if ~isempty(this.pOPF)
                        	this.pOPF.elimina_variable(el_red);
                        end
                        if ~isempty(this.pFP)
                            this.pFP.elimina_variable(el_red);
                        end
                        if ~isempty(this.pResEvaluacion)
                            this.pResEvaluacion.elimina_variable(el_red);
                        end
                        
                        this.elimina_elemento_red(el_red);                
                    elseif strcmp(proyecto.Elemento(i).entrega_tipo_elemento_red(), 'Almacenamiento')
                        el_red = this.entrega_elemento(class(proyecto.Elemento(i)), proyecto.Elemento(i).entrega_nombre(), false);
                        if isempty(el_red)
                            correcto = false;
                            if protocoliza
                                prot = cProtocolo.getInstance;
                                prot.imprime_texto(['Proyecto ' num2str(proyecto.Indice) ' ' proyecto.Nombre ' no pudo ser implementado, ya que ' ...
                                    ' elemento ' proyecto.Elemento(i).entrega_nombre() ' no se encuentra en el SEP']);
                                this.imprime_elementos(class(proyecto.Elemento(i)));
                            end
                            return;
                        end
                        % verificar si hay que modificar opf
                        if ~isempty(this.pOPF)
                        	this.pOPF.elimina_variable(el_red);
                        end
                        if ~isempty(this.pFP)
                            this.pFP.elimina_variable(el_red);
                        end
                        if ~isempty(this.pResEvaluacion)
                            this.pResEvaluacion.elimina_variable(el_red);
                        end

                        this.elimina_elemento_red(el_red);                        
                    else
                        error = MException('cSistemaElectricoPotencia:elimina_proyecto','Sólo se han implementado proyectos de cambio de elementos en serie');
                        throw(error)
                    end
                end
            end
            tipo_proyecto = proyecto.entrega_id_tipo_proyecto();
            if tipo_proyecto == 1
                this.ProyectosExpansionTx(ismember(this.ProyectosExpansionTx,proyecto.entrega_indice())) = [];
            else
                this.ProyectosExpansionGx(ismember(this.ProyectosExpansionGx,proyecto.entrega_indice())) = [];
            end
            
            correcto = true;
        end

        function elimina_proyectos(this, adm_proy)
            proy_en_sep = this.ProyectosExpansionTx;
            for proy = length(proy_en_sep):-1:1
                proyecto = adm_proy.entrega_proyecto(proy_en_sep(proy));
                this.elimina_proyecto(proyecto);
            end
        end
        
        function existe = existe_proyecto(this, proyecto, tipo_proyecto)
            if tipo_proyecto == 1
                existe = ~isempty(find(this.ProyectosExpansionTx == proyecto, 1));
            else
                existe = ~isempty(find(this.ProyectosExpansionGx == proyecto, 1));
            end
        end
        
        function existe = existe_proyecto_tx(this,proyecto)
            existe = ~isempty(find(this.ProyectosExpansionTx == proyecto, 1));
        end

        function existe = existe_proyecto_gx(this,proyecto)
            existe = ~isempty(find(this.ProyectosExpansionGx == proyecto, 1));
        end
        
        function agrega_linea(this, linea)
            cant_lineas = length(this.Lineas)+1;
            this.Lineas(cant_lineas,1) = linea;
            linea.Id = cant_lineas;
            
            %agrega elemento de red
            cant_elementos = length(this.ElementosRed)+ 1;
            this.ElementosRed(cant_elementos,1) = linea;
            linea.IdElementoRed = cant_elementos;            
        end
        
        function agrega_transformador(this, trafo)
            cant_trafos = length(this.Transformadores2D)+1;
            this.Transformadores2D(cant_trafos,1) = trafo;
            trafo.Id = cant_trafos;
            
            %agrega elemento de red
            cant_elementos = length(this.ElementosRed)+ 1;
            this.ElementosRed(cant_elementos,1) = trafo;
            trafo.IdElementoRed = cant_elementos;
        end
        
        
        function agrega_consumo(this, consumo)
            cant_consumos = length(this.Consumos)+1;
            this.Consumos(cant_consumos,1) = consumo;
            consumo.Id = cant_consumos;

            %agrega elemento de red
            cant_elementos = length(this.ElementosRed)+1;
            this.ElementosRed(cant_elementos,1) = consumo;
            consumo.IdElementoRed = cant_elementos;
        end
        
        function agrega_generador(this, generador)
            cant_gen = length(this.Generadores)+1;
            this.Generadores(cant_gen,1) = generador;
            generador.Id = cant_gen;
            this.IndiceGeneradoresDespachables(cant_gen,1) = generador.Despachable;
            
            %agrega elemento de red
            cant_elementos = length(this.ElementosRed)+1;
            this.ElementosRed(cant_elementos,1) = generador;
            generador.IdElementoRed = cant_elementos;
            
            if generador.es_slack()
                this.IdSubestacionSlack = generador.entrega_se().entrega_id();
            end
        end
        
        function id = entrega_id_se_slack(this)
            id = this.IdSubestacionSlack;
        end
        
        function se = entrega_se_slack(this)
            se = this.Subestaciones(this.IdSubestacionSlack);
        end
        
        function agrega_condensador(this, condensador)
            cant_cond = length(this.Condensadores)+1;
            this.Condensadores(cant_cond,1) = condensador;
            condensador.Id = cant_cond;
            
            %agrega elemento de red
            cant_elementos = length(this.ElementosRed)+1;
            this.ElementosRed(cant_elementos,1) = condensador;
            condensador.IdElementoRed = cant_elementos;
        end
        
        function agrega_reactor(this, reactor)
            cant_react = length(this.Reactores)+1;
            this.Reactores(cant_react,1) = reactor;
            reactor.Id = cant_react;
            
            %agrega elemento de red
            cant_elementos = length(this.ElementosRed)+1;
            this.ElementosRed(cant_elementos,1) = reactor;
            reactor.IdElementoRed = cant_elementos;
        end

        function agrega_bateria(this, bateria)
            cant_bat = length(this.Baterias)+1;
            this.Baterias(cant_bat,1) = bateria;
            bateria.Id = cant_bat;
            
            %agrega elemento de red
            cant_elementos = length(this.ElementosRed)+1;
            this.ElementosRed(cant_elementos,1) = bateria;
            bateria.IdElementoRed = cant_elementos;
        end

        function agrega_embalse(this, embalse)
            cant_embalses = length(this.Embalses)+1;
            this.Embalses(cant_embalses,1) = embalse;
            embalse.Id = cant_embalses;
            
            %agrega elemento de red
            cant_elementos = length(this.ElementosRed)+1;
            this.ElementosRed(cant_elementos,1) = embalse;
            embalse.IdElementoRed = cant_elementos;
        end

        function agrega_almacenamiento(this, almacenamiento)
            cant_almacenamientos = length(this.Almacenamientos)+1;
            this.Almacenamientos(cant_almacenamientos,1) = almacenamiento;
            almacenamiento.Id = cant_almacenamientos;
            
            %agrega elemento de red
            cant_elementos = length(this.ElementosRed)+1;
            this.ElementosRed(cant_elementos,1) = almacenamiento;
            almacenamiento.IdElementoRed = cant_elementos;
        end
        
        function agrega_elemento_red(this, el_red)
            if isa(el_red, 'cLinea')
                this.agrega_linea(el_red);
            elseif isa(el_red, 'cGenerador')
                this.agrega_generador(el_red);
            elseif isa(el_red, 'cConsumo')
                this.agrega_consumo(el_red)
            elseif isa(el_red, 'cTransformador2D')
                this.agrega_transformador(el_red);
            elseif isa(el_red, 'cReactor')
                this.agrega_reactor(el_red);
            elseif isa(el_red, 'cCondensador')
                this.agrega_condensador(el_red);
            elseif isa(el_red, 'cSubestacion')
                this.agrega_subestacion(el_red);
            elseif isa(el_red, 'cBateria')
                this.agrega_bateria(el_red);
            elseif isa(el_red, 'cEmbalse')
                this.agrega_embalse(el_red);
            elseif isa(el_red, 'cAlmacenamiento')
                this.agrega_almacenamiento(el_red);
            else
                error = MException('cSistemaElectricoPotencia:agrega_elemento_red','elemento no implementado');
                throw(error)
            end
        end        

        function agrega_y_conecta_elemento_red(this, el_red)
            if isa(el_red, 'cLinea')
                this.agrega_linea(el_red);
                se1 = el_red.entrega_se1();
                if ~isempty(se1)
                    se_en_sep = this.entrega_subestacion(se1.entrega_nombre(), true);
                    se_en_sep.agrega_linea(el_red);
                    el_red.inserta_subestacion(se_en_sep, 1);
                else
                    error = MException('cSistemaElectricoPotencia:agrega_y_conecta_elemento_red','No se pudo agregar linea porque no está definida la subestacion');
                    throw(error)                    
                end
                se2 = el_red.entrega_se2();
                if ~isempty(se2)
                    se_en_sep = this.entrega_subestacion(se2.entrega_nombre(), true);
                    se_en_sep.agrega_linea(el_red);
                    el_red.inserta_subestacion(se_en_sep, 2);
                else
                    error = MException('cSistemaElectricoPotencia:agrega_y_conecta_elemento_red','No se pudo agregar linea porque no está definida la subestacion');
                    throw(error)                    
                end
            elseif isa(el_red, 'cGenerador')
                this.agrega_generador(el_red);
                se = el_red.entrega_se();
                if ~isempty(se)
                    se_en_sep = this.entrega_subestacion(se.entrega_nombre(), true);                    
                    se_en_sep.agrega_generador(el_red); 
                    el_red.inserta_subestacion(se_en_sep);
                else
                    error = MException('cSistemaElectricoPotencia:agrega_y_conecta_elemento_red','No se pudo agregar generador porque no está definida la subestacion');
                    throw(error)                    
                end
            elseif isa(el_red, 'cConsumo')
                this.agrega_consumo(el_red)
                se = el_red.entrega_se();
                if ~isempty(se)
                    se_en_sep = this.entrega_subestacion(se.entrega_nombre(), true);                    
                    se_en_sep.agrega_consumo(el_red); 
                    el_red.inserta_subestacion(se_en_sep);
                else
                    error = MException('cSistemaElectricoPotencia:agrega_y_conecta_elemento_red','No se pudo agregar consumo porque no está definida la subestacion');
                    throw(error)                    
                end
            elseif isa(el_red, 'cTransformador2D')
                this.agrega_transformador(el_red);
                se1 = el_red.entrega_se1();
                if ~isempty(se1)
                    se_en_sep = this.entrega_subestacion(se1.entrega_nombre(), true);                    
                    se_en_sep.agrega_transformador2D(el_red); 
                    el_red.inserta_subestacion(se_en_sep, 1);
                else
                    error = MException('cSistemaElectricoPotencia:agrega_y_conecta_elemento_red','No se pudo agregar trafo porque no está definida la subestacion');
                    throw(error)                    
                end
                se2 = el_red.entrega_se2();
                if ~isempty(se2)
                    se_en_sep = this.entrega_subestacion(se2.entrega_nombre(), true);                    
                    se_en_sep.agrega_transformador2D(el_red); 
                    el_red.inserta_subestacion(se_en_sep, 2);
                else
                    error = MException('cSistemaElectricoPotencia:agrega_y_conecta_elemento_red','No se pudo agregar trafo porque no está definida la subestacion');
                    throw(error)                    
                end
            elseif isa(el_red, 'cReactor')
                this.agrega_reactor(el_red);
                error = MException('cSistemaElectricoPotencia:agrega_y_conecta_elemento_red','Reactores aún no implementado');
                throw(error)                    
            elseif isa(el_red, 'cCondensador')
                this.agrega_condensador(el_red);
                error = MException('cSistemaElectricoPotencia:agrega_y_conecta_elemento_red','Condensadores aún no implementado');
                throw(error)
            elseif isa(el_red, 'cSubestacion')
                this.agrega_subestacion(el_red);
            elseif isa(el_red, 'cBateria')
                this.agrega_bateria(el_red);
                se = el_red.entrega_se();
                if ~isempty(se)
                    se_en_sep = this.entrega_subestacion(se.entrega_nombre(), true);                    
                    se_en_sep.agrega_bateria(el_red); 
                    el_red.inserta_subestacion(se_en_sep);
                else
                    error = MException('cSistemaElectricoPotencia:agrega_y_conecta_elemento_red','No se pudo agregar consumo porque no está definida la subestacion');
                    throw(error)                    
                end
            elseif isa(el_red, 'cEmbalse')
                this.agrega_embalse(el_red);
            else
                error = MException('cSistemaElectricoPotencia:agrega_elemento_red','elemento no implementado');
                throw(error)
            end
        end
        
        function subestacion = entrega_subestacion(this, nombre, varargin)
            %varargin indica si es obligatorio o no. Valor por defecto es
            %que si
            obligatorio = true;
            if nargin > 2
                obligatorio = varargin{1};
            end
            
            for i = 1:length(this.Subestaciones)
                if strcmp(this.Subestaciones(i).Nombre, nombre)
                    subestacion = this.Subestaciones(i);
                    return
                end
            end
            
            if obligatorio
                texto = ['subestacion con nombre ' nombre ' no encontrada'];
                error = MException('cSistemaElectricoPotencia:entrega_subestacion',texto);
                throw(error)
            else
                subestacion = cSubestacion.empty;
            end
        end     

        function almacenamiento = entrega_almacenamiento(this, nombre)
            for i = 1:length(this.Almacenamientos)
                if strcmp(this.Almacenamientos(i).Nombre, nombre)
                    almacenamiento = this.Almacenamientos(i);
                    return
                end
            end
            error = MException('cSistemaElectricoPotencia:entrega_almacenamiento','almacenamiento no encontrado');
            throw(error)
        end
        
        function generador = entrega_generador(this, nombre)
            for i = 1:length(this.Generadores)
                if strcmp(this.Generadores(i).Nombre, nombre)
                    generador = this.Generadores(i);
                    return
                end
            end
            error = MException('cSistemaElectricoPotencia:entrega_generador','generador no encontrado');
            throw(error)
        end     

        function consumo = entrega_consumo(this, nombre)
            for i = 1:length(this.Consumos)
                if strcmp(this.Consumos(i).Nombre, nombre)
                    consumo = this.Consumos(i);
                    return
                end
            end
            error = MException('cSistemaElectricoPotencia:entrega_consumo','Demanda no encontrada');
            throw(error)
        end    
        
        function imprime_sep(this, varargin)
            detallado = false;
            if nargin > 1
                detallado = varargin{1};
                adm_sc = varargin{2};
            end
            
            prot = cProtocolo.getInstance;
            prot.imprime_texto('Imprime SEP\n');
            
            texto = cell(1);
            texto{1} = 'Sistema Electrico de Potencia'; 
            texto{end+1} = '-----------------------------------------------';
            texto{end+1} = sprintf('%-45s %-50s','Cant. Subestaciones:', num2str(length(this.Subestaciones)));
            texto{end+1} = sprintf('%-45s %-50s','Cant. Lineas:', num2str(length(this.Lineas)));
            texto{end+1} = sprintf('%-45s %-50s','Cant. trafos:', num2str(length(this.Transformadores2D)));
            texto{end+1} = sprintf('%-45s %-50s','Cant. Consumos:',num2str(length(this.Consumos)));
            texto{end+1} = sprintf('%-45s %-50s','Cant. Generadores:',num2str(length(this.Generadores)));
            texto{end+1} = sprintf('%-45s %-50s','Cant. Generadores Despachables:',num2str(length(this.Generadores(this.IndiceGeneradoresDespachables == 1))));
            texto{end+1} = sprintf('%-45s %-50s','Cant. Generadores RES:',num2str(length(this.Generadores(this.IndiceGeneradoresDespachables == 0))));
            texto{end+1} = sprintf('%-45s %-50s','Cant. Condensadores:',num2str(length(this.Condensadores)));
            texto{end+1} = sprintf('%-45s %-50s','Cant. Reactores:',num2str(length(this.Reactores)));
            texto{end+1} = sprintf('%-45s %-50s','Cant. Baterias:',num2str(length(this.Baterias)));
            texto{end+1} = sprintf('%-45s %-50s','Cant. Embalses:',num2str(length(this.Embalses)));

            for i = 1:length(texto)
                prot.imprime_texto(texto{i});
            end
            if ~detallado
                return
            end

            % imprime demanda
            prot.imprime_texto('Consumo');
            texto = sprintf('%-30s %-5s %-7s %-5s %-7s %-10s', 'Nombre', 'Bus', 'Etapa', 'PO', 'Rep.PO', 'P (MW)');            
            prot.imprime_texto(texto);
            cantidad_etapas = adm_sc.entrega_cantidad_etapas();
            cantidad_po = adm_sc.entrega_cantidad_puntos_operacion();
            demanda_total = zeros(cantidad_etapas, cantidad_po);
            for i = 1:length(this.Consumos)
                consumo = this.Consumos(i);
                nombre = consumo.entrega_nombre();
                id_bus = consumo.entrega_se().entrega_id();
                for etapa = 1:cantidad_etapas
                    for oper = 1:cantidad_po
                        id_escenario = consumo.entrega_indice_escenario();
                        pmax = adm_sc.entrega_consumo(id_escenario, etapa, oper);
                        demanda_total(etapa, oper) = demanda_total(etapa, oper) + pmax;                        
                        rep = adm_sc.RepresentatividadPuntosOperacion(oper);
                        texto = sprintf('%-30s %-5s %-7s %-5s %-7s %-10s', nombre,...
                            num2str(id_bus),...
                            num2str(etapa),...
                            num2str(oper),...
                            num2str(rep),...
                            num2str(pmax));            
                        prot.imprime_texto(texto);
                    end
                end
            end
            prot.imprime_texto('');
            
            % imprime generadores
            prot.imprime_texto('Generadores');
            texto = sprintf('%-20s %-5s %-5s %-5s %-7s %-10s %-10s', 'Nombre', 'Bus', 'Tipo', 'Des.', 'Slack', 'Pn', '$/MWh');
            prot.imprime_texto(texto);
            for i = 1:length(this.Generadores)
                gen = this.Generadores(i);
                texto = sprintf('%-20s %-5s %-5s %-5s %-7s %-10s %-10s', gen.entrega_nombre(),...
                    num2str(gen.entrega_se().entrega_id()),...
                    gen.entrega_tipo_central(), ...
                    num2str(gen.es_despachable()),...
                    num2str(gen.es_slack()), ...
                    num2str(round(gen.entrega_pmax(),1)), ...
                    num2str(round(gen.entrega_costo_mwh(),4)));
                
                prot.imprime_texto(texto);                
            end

            % imprime series generadores ERNC
            generacion_res_total = zeros(cantidad_etapas, cantidad_po);
            prot.imprime_texto('Series generadores ERNC');
            texto = sprintf('%-20s %-5s %-7s %-5s %-7s %-10s', 'Nombre', 'Bus', 'Etapa', 'PO', 'Rep.PO', 'P (MW)');            
            prot.imprime_texto(texto);
            for i = 1:length(this.GeneradoresRES)
                gen = this.GeneradoresRES(i);
                nombre = gen.entrega_nombre();
                id_bus = gen.entrega_se().entrega_id();
                for etapa = 1:cantidad_etapas
                    for oper = 1:cantidad_po
                        id_escenario = gen.entrega_indice_escenario();
                        pmax = adm_sc.entrega_inyeccion(id_escenario, etapa, oper);
                        generacion_res_total(etapa, oper) = generacion_res_total(etapa, oper) + pmax;
                        rep = adm_sc.RepresentatividadPuntosOperacion(oper);
                        texto = sprintf('%-20s %-5s %-7s %-5s %-7s %-10s', nombre,...
                            num2str(id_bus),...
                            num2str(etapa),...
                            num2str(oper),...
                            num2str(rep),...
                            num2str(pmax));            
                        prot.imprime_texto(texto);
                    end
                end
            end
            
            prot.imprime_texto('');
            prot.imprime_texto('Demanda y generacion ERNC total');
            texto = sprintf('%-7s','Etapa');
            for oper = 1:cantidad_po
                txt = sprintf('%-10s',num2str(oper));
                texto = [texto txt];
                txt = sprintf('%-10s',num2str(oper));
                texto = [texto txt];
            end
            prot.imprime_texto(texto);
            for etapa = 1:cantidad_etapas
                texto = sprintf('%-7s',num2str(etapa));
                for oper = 1:cantidad_po
                    txt = sprintf('%-10s',num2str(demanda_total(etapa, oper)));
                    texto = [texto txt];
                    txt = sprintf('%-10s',num2str(generacion_res_total(etapa, oper)));
                    texto = [texto txt];
                end
                prot.imprime_texto(texto);
            end
        end
        
        function imprime_elementos(this, clase)
            prot = cProtocolo.getInstance;
            prot.imprime_texto(['Elementos de la clase ' clase ' pertenecientes al SEP:']);
            
            if strcmp(clase, 'cLinea')
                for i = 1:length(this.Lineas)
                    prot.imprime_texto(this.Lineas(i).entrega_nombre());
                end
            elseif strcmp(clase, 'cTransformador2D')
                for i = 1:length(this.Transformadores2D)
                    prot.imprime_texto(this.Transformadores2D(i).entrega_nombre());
                end
            else
                error = MException('cSistemaElectricoPotencia:imprime_elementos','tipo elemento aún no implelmentado');
                throw(error)
            end
        end
            
        function copia = crea_copia(this)
            % Crea una copia del sistema eléctrico de potencia
            % Con tal de mantener las relaciones entre los elementos de
            % red, es necesario primero crear un índice para luego
            % interconectar cada uno de los elementos copiados. OJO: No se
            % puede utilizar eval(class(this)) ya que mantiene los punteros
            % pero no realiza ninguna copia. 
            
            copia = cSistemaElectricoPotencia();
            
            %genera copias
            % subestaciones
            for i = 1:length(this.Subestaciones)
                nueva_subestacion = this.Subestaciones(i).crea_copia();
                copia.agrega_subestacion(nueva_subestacion);
            end
            
            %lineas
            for i = 1:length(this.Lineas)
                nueva_linea = this.Lineas(i).crea_copia();
                nombre_se1 = this.Lineas(i).entrega_nombre_se(1);
                nombre_se2 = this.Lineas(i).entrega_nombre_se(2);
                SE1 = copia.entrega_subestacion(nombre_se1);
                SE2 = copia.entrega_subestacion(nombre_se2);
                nueva_linea.inserta_subestacion(SE1,1);
                nueva_linea.inserta_subestacion(SE2,2);
                copia.agrega_linea(nueva_linea);                
                SE1.agrega_linea(nueva_linea);
                SE2.agrega_linea(nueva_linea);
            end

            %transformadores2D
            for i = 1:length(this.Transformadores2D)
                nuevo_trafo = this.Transformadores2D(i).crea_copia();
                nombre_se1 = this.Transformadores2D(i).entrega_nombre_se(1);
                nombre_se2 = this.Transformadores2D(i).entrega_nombre_se(2);
                SE1 = copia.entrega_subestacion(nombre_se1);
                SE2 = copia.entrega_subestacion(nombre_se2);
                nuevo_trafo.inserta_subestacion(SE1,1);
                nuevo_trafo.inserta_subestacion(SE2,2);
                copia.agrega_transformador(nuevo_trafo);                
                SE1.agrega_transformador2D(nuevo_trafo);
                SE2.agrega_transformador2D(nuevo_trafo);
            end
            
            %consumos
            for i = 1:length(this.Consumos)
                nuevos_consumo = this.Consumos(i).crea_copia();
                nombre_se = this.Consumos(i).entrega_nombre_se();
                SE = copia.entrega_subestacion(nombre_se);
                nuevos_consumo.SE = SE;
                copia.agrega_consumo(nuevos_consumo);
                SE.agrega_consumo(nuevos_consumo);
            end
            
            %generadores
            for i = 1:length(this.Generadores)
                nuevo_generador = this.Generadores(i).crea_copia();
                nombre_se = this.Generadores(i).entrega_nombre_se();
                SE = copia.entrega_subestacion(nombre_se);
                nuevo_generador.SE = SE;
                copia.agrega_generador(nuevo_generador);
                SE.agrega_generador(nuevo_generador);                
            end

            %condensadores
            for i = 1:length(this.Condensadores)
                nuevo_condensador = this.Condensadores(i).crea_copia();
                nombre_se = this.Condensadores(i).entrega_nombre_se();
                SE = copia.entrega_subestacion(nombre_se);
                nuevo_condensador.SE = SE;
                copia.agrega_condensador(nuevo_condensador);
                SE.agrega_condensador(nuevo_condensador);
            end
            
            %reactores
            for i = 1:length(this.Reactores)
                nuevo_reactor = this.Reactores(i).crea_copia();
                nombre_se = this.Reactores(i).entrega_nombre_se();
                SE = copia.entrega_subestacion(nombre_se);
                nuevo_reactor.SE = SE;
                copia.agrega_reactor(nuevo_reactor);
                SE.agrega_reactor(nuevo_reactor);
            end
            
            % baterias
            for i = 1:length(this.Baterias)
                nueva_bateria = this.Baterias(i).crea_copia();
                nombre_se = this.Baterias(i).entrega_nombre_se();
                SE = copia.entrega_subestacion(nombre_se);
                nueva_bateria.SE = SE;
                copia.agrega_bateria(nueva_bateria);
                SE.agrega_bateria(nueva_bateria);
            end

            % embalses
            for i = 1:length(this.Embalses)
              nuevo_embalse = this.Embalses(i).crea_copia();
              copia.agrega_embalse(nuevo_embalse);
              nuevo_embalse.crea_spillage();
              
              % turbinas carga
              cant_turb_carga = this.Embalses(i).entrega_cantidad_turbinas_carga();
              for j = 1:cant_turb_carga
                  nombre_turb = this.Embalses(i).entrega_turbina_carga(j).Nombre;
                  gen = copia.entrega_generador(nombre_turb);
                  nuevo_embalse.agrega_turbina_carga(gen);
              end
              
              % turbinas descarga
              cant_turb_descarga = this.Embalses(i).entrega_cantidad_turbinas_descarga();
              for j = 1:cant_turb_descarga
                  nombre_turb = this.Embalses(i).entrega_turbina_descarga(j).Nombre;
                  gen = copia.entrega_generador(nombre_turb);
                  nuevo_embalse.agrega_turbina_descarga(gen);
              end              
            end
            
            copia.ProyectosExpansionTx = this.ProyectosExpansionTx;            
        end
        
        function elemento = entrega_elemento_red(this, idx, varargin)
            % varargin indica si se entrega error o no. Valor por default
            % es si
            obligatorio = true;
            if nargin > 2
                obligatorio = varargin{1};
            end
            
            if idx <= length(this.ElementosRed)
                elemento = this.ElementosRed(idx);
            else
                if obligatorio
                    error = MException('cSistemaElectricoPotencia:entrega_elemento_red',strcat('índice fuera de rango. Indice entregado: ', num2str(idx), ...
                        '. Cantidad elementos de red: ', num2str(length(this.ElementosRed))));
                    throw(error)
                else
                    elemento = cElementoRed.empty;
                end
            end
        end
        
        function elemento = entrega_elemento(this, clase, nombre, varargin)
%TODO: Eventualmente se puede mejorar esta parte
            obligatorio = true;
            if nargin > 3
                obligatorio = varargin{1};
            end
            if strcmp(clase, 'cLinea')
                for i = 1:length(this.Lineas)
                    if strcmp(this.Lineas(i).entrega_nombre(), nombre)
                        elemento = this.Lineas(i);
                        return
                    end
                end
            elseif strcmp(clase, 'cTransformador2D')
                for i = 1:length(this.Transformadores2D)
                    if strcmp(this.Transformadores2D(i).entrega_nombre(), nombre)
                        elemento = this.Transformadores2D(i);
                        return
                    end
                end
            elseif strcmp(clase, 'cSubestacion')
                for i = 1:length(this.Subestaciones)
                    if strcmp(this.Subestaciones(i).entrega_nombre(), nombre)
                        elemento = this.Subestaciones(i);
                        return
                    end
                end
            elseif strcmp(clase, 'cBateria')
                for i = 1:length(this.Baterias)
                    if strcmp(this.Baterias(i).entrega_nombre(), nombre)
                        elemento = this.Baterias(i);
                        return
                    end
                end
            elseif strcmp(clase, 'cGenerador')
                for i = 1:length(this.Generadores)
                    if strcmp(this.Generadores(i).entrega_nombre(), nombre)
                        elemento = this.Generadores(i);
                        return
                    end
                end
            elseif strcmp(clase, 'cAlmacenamiento')
                for i = 1:length(this.Almacenamientos)
                    if strcmp(this.Almacenamientos(i).entrega_nombre(), nombre)
                        elemento = this.Almacenamientos(i);
                        return
                    end
                end
            else
                error = MException('cSistemaElectricoPotencia:entrega_elemento','tipo elemento aún no implelmentado');
                throw(error)
            end
            
            if obligatorio
                error = MException('cSistemaElectricoPotencia:entrega_elemento',...
                    ['Error de programación. Elemento ' nombre ' no existe en el SEP']);
                throw(error)
            else
                elemento = cElementoRed.empty;
            end
        end

        function cantidad = entrega_cantidad_elementos_red(this)
            cantidad = length(this.ElementosRed);
        end
        
        function cantidad = entrega_cantidad_subestaciones(this)
            cantidad = length(this.Subestaciones);
        end
        
        function cantidad = entrega_cantidad_elementos_serie(this)
            cantidad = length(this.Lineas)+length(this.Transformadores2D);
        end

        function cantidad = entrega_cantidad_lineas(this)
            cantidad = length(this.Lineas);
        end
        
        function cantidad = entrega_cantidad_generadores_despachables(this)
            cantidad = length(this.Generadores(this.IndiceGeneradoresDespachables == 1));
        end
        
        function cantidad = entrega_cantidad_generadores_res(this)
            cantidad = length(this.Generadores(this.IndiceGeneradoresDespachables == 0));
        end

        function gen = entrega_generadores(this)
            gen = this.Generadores;
        end
        
        function gen = entrega_generadores_res(this)
            gen = this.Generadores(this.IndiceGeneradoresDespachables == 0);
        end

        function bat = entrega_baterias(this)
            bat = this.Baterias;
        end
        
        function embalses = entrega_embalses(this)
          embalses = this.Embalses;
        end
        
        function consumos = entrega_consumos(this)
            consumos = this.Consumos;
        end
        
        function cantidad = entrega_cantidad_generadores(this)
            cantidad = length(this.Generadores);
        end
        
        function cantidad = entrega_cantidad_transformadores_2D(this)
            cantidad = length(this.Transformadores2D);
        end
        
        function cantidad = entrega_cantidad_condensadores(this)
            cantidad = length(this.Condensadores);
        end
        
        function cantidad = entrega_cantidad_reactores(this)
            cantidad = length(this.Reactores);
        end
        
        function cantidad = entrega_cantidad_consumos(this)
            cantidad = length(this.Consumos);
        end

        function cantidad = entrega_cantidad_baterias(this)
            cantidad = length(this.Baterias);
        end

        function cantidad = entrega_cantidad_embalses(this)
            cantidad = length(this.Embalses);
        end
        
        function imprime_resultados_flujo_potencia(this, varargin)
            % TODO: Tiene que venir de Flujo de Potencia
        end
                        
        function gen = entrega_generadores_opf(this)
            gen = cGenerador.empty(length(this.Generadores),0);
            contador = 0;
            for i = 1:length(this.Generadores)
                if this.Generadores(i).entrega_flag_opf()
                    contador = contador + 1;
                    gen(contador,19) = this.Generadores(i);
                end
            end
            gen = gen(1:contador);
        end
        
        function se = entrega_subestaciones_opf(this)
            se = cSubestacion.empty(length(this.Subestaciones),0);
            contador = 0;
            for i = 1:length(this.Subestaciones)
                if this.Subestaciones(i).entrega_flag_opf()
                    contador = contador + 1;
                    se(contador,1) = this.Subestaciones(i);
                end
            end
            se = se(1:contador);
        end

        function se = entrega_subestaciones_no_opf(this)
            se = cSubestacion.empty(length(this.Subestaciones),0);
            contador = 0;
            for i = 1:length(this.Subestaciones)
                if ~this.Subestaciones(i).entrega_flag_opf()
                    contador = contador + 1;
                    se(contador,1) = this.Subestaciones(i);
                end
            end
            se = se(1:contador);
        end
           
        function se = entrega_subestaciones(this)
            se = this.Subestaciones;
        end
        
        function lineas = entrega_lineas(this)
            lineas = this.Lineas;
        end
        
        function existe = existe_linea(this, linea)
            for i = 1:length(this.Lineas)
                if this.Lineas(i) == linea
                    existe = true;
                    return
                end
            end
            existe = false;
            return;
        end

        function existe = existe_subestacion(this, se)
            for i = 1:length(this.Subestaciones)
                if this.Subestaciones(i) == se
                    existe = true;
                    return
                end
            end
            existe = false;
            return;
        end        
         
        function existe = existe_elemento(this, el_red)
            if isa(el_red, 'cLinea')
                existe = this.existe_linea(el_red);
            elseif isa(el_red, 'cTransformador2D')
                existe = this.existe_trafo_2d(el_red);
            elseif isa(el_red, 'cSubestacion')
                existe = this.existe_subestacion(el_red);
            else
                error = MException('cSistemaElectricoPotencia:existe_elemento','tipo elemento aún no implelmentado');
                throw(error)
            end
        end
        
        function existe = existe_trafo_2d(this, trafo)
            for i = 1:length(this.Transformadores2D)
                if this.Transformadores2D(i) == trafo
                    existe = true;
                    return
                end
            end
            existe = false;
            return;
        end
        
        function trafo = entrega_transformadores2d_opf(this)
            trafo = cTransformador2D.empty(length(this.Transformadores2D), 0);
            contador = 0;
            for i = 1:length(this.Transformadores2D)
                if this.Transformadores2D(i).entrega_flag_opf()
                    contador = contador + 1;
                    trafo(contador,1) = this.Transformadores2D(i);
                end
            end
            trafo = trafo(1:contador);
        end

        function trafo = entrega_transformadores2d(this)
            trafo = this.Transformadores2D;
        end
        
        function cond = entrega_condensadores_opf(this)
            cond = cCondensador.empty(length(this.Condensadores),0);
            contador = 0;
            for i = 1:length(this.Condensadores)
                if this.Condensadores(i).entrega_flag_opf()
                    contador = contador + 1;
                    cond(contador,1) = this.Condensadores(i);
                end
            end
            cond = cond(1:contador); 
        end

        function react = entrega_reactores_opf(this)
            react = cReactor.empty(length(this.Reactores),0);
            contador = 0;
            for i = 1:length(this.Reactores)
                if this.Reactores(i).entrega_flag_opf()
                    contador = contador + 1;
                    react(contador,1) = this.Reactores(i);
                end
            end
            react = react(1:contador);
        end
        
        function borra_resultados_fp(this)
            for i = 1:length(this.ElementosRed)
                this.ElementosRed(i).borra_resultados_fp();
            end
        end
        
        function gen = entrega_generadores_despachables(this)
            gen = this.Generadores(this.IndiceGeneradoresDespachables == 1);
        end
                
        function elimina_elemento_red(this, el_red)            
            if isa(el_red, 'cLinea')
                this.elimina_linea(el_red)
            elseif isa(el_red, 'cTransformador2D')
                this.elimina_transformador2D(el_red);
            elseif isa(el_red, 'cSubestacion')
                this.elimina_subestacion(el_red);
            elseif isa(el_red,'cBateria')
                this.elimina_bateria(el_red);
            elseif isa(el_red,'cAlmacenamiento')
                this.elimina_almacenamiendo(el_red);
            %elseif isa(el_red, 'cGenerador')
            %    this.elimina_generador(el_red);
            %elseif isa(el_red, 'cConsumo')
            %    this.elimina_consumo(el_red)
            %elseif isa(el_red, 'cReactor')
            %    this.elimina_reactor(el_red);
            %elseif isa(el_red, 'cCondensador')
            %    this.elimina_condensador(el_red);
            else
                error = MException('cSistemaElectricoPotencia:elimina_elemento_red','elemento no implementado');
                throw(error)
            end
        end

        function elimina_subestacion(this, se)
            id_elred = se.IdElementoRed;
            id_se = se.Id;
            
            %verifica que no hayan elementos conectados
            if se.existe_conectividad()
                error = MException('cSistemaElectricoPotencia:elimina_subestacion','subestacion no se puede eliminar ya que aún hay elementos conectados a ella');
                throw(error)
            end
            
            cantidad_se = length(this.Subestaciones);
            if cantidad_se < id_se || this.Subestaciones(id_se) ~= se
                for i = 1:cantidad_se
                    id = this.Subestaciones(i).Id;
                    disp(strcat('Id: ', num2str(id), ' .Posicion en Subestaciones: ', num2str(i)));
                    if this.Subestaciones(i) == se
                        disp(strcat('Id se buscada es: ', num2str(i), ' Id incorrecta', num2str(id_se)));
                    end
                end
                error = MException('cSistemaElectricoPotencia:elimina_subestacion','id se no coincide');
                throw(error)
                
            end
            if this.ElementosRed(id_elred) ~= se
                error = MException('cSistemaElectricoPotencia:elimina_subestacion','id elemento de red no coincide');
                throw(error)
            end
            
            this.Subestaciones(id_se) = [];
            %actualiza id de subestaciones
            for i = id_se:length(this.Subestaciones)
                this.Subestaciones(i).Id = i;
            end
                        
            % actualiza elementos de red
            this.ElementosRed(id_elred) = [];
            for i = id_elred:length(this.ElementosRed)
                this.ElementosRed(i).IdElementoRed = i;
            end

            %elimina objeto
            delete(se);
            clear se;
        end
        
        function elimina_transformador2D(this, trafo)
            se1 = trafo.entrega_se1();
            se2 = trafo.entrega_se2();
            id_elred = trafo.IdElementoRed;
            id_trafo = trafo.Id;
            
            if this.Transformadores2D(id_trafo) ~= trafo
                error = MException('cSistemaElectricoPotencia:elimina_transformador2D','id trafo no coincide');
                throw(error)
            end
            if this.ElementosRed(id_elred) ~= trafo
                error = MException('cSistemaElectricoPotencia:elimina_transformador2D','id elemento de red no coincide');
                throw(error)
            end

            se1.elimina_elemento_red(trafo);
            se2.elimina_elemento_red(trafo);
            
            this.Transformadores2D(id_trafo) = [];
            %actualiza lineas
            for i = id_trafo:length(this.Transformadores2D)
                this.Transformadores2D(i).Id = i;
            end
                        
            % actualiza elementos de red
            this.ElementosRed(id_elred) = [];
            for i = id_elred:length(this.ElementosRed)
                this.ElementosRed(i).IdElementoRed = i;
            end

            %elimina objeto
            delete(trafo);
            clear trafo;
        end
        
        function elimina_linea(this, linea)
            se1 = linea.entrega_se1();
            se2 = linea.entrega_se2();
            id_elred = linea.IdElementoRed;
            id_linea = linea.Id;
            
            if this.Lineas(id_linea) ~= linea
                error = MException('cSistemaElectricoPotencia:elimina_linea','id linea no coincide');
                throw(error)
            end
            if this.ElementosRed(id_elred) ~= linea
                error = MException('cSistemaElectricoPotencia:elimina_linea','id elemento de red no coincide');
                throw(error)
            end

            se1.elimina_elemento_red(linea);
            se2.elimina_elemento_red(linea);
            
            this.Lineas(id_linea) = [];
            %actualiza lineas
            for i = id_linea:length(this.Lineas)
                this.Lineas(i).Id = i;
            end
            
            % actualiza elementos de red
            this.ElementosRed(id_elred) = [];
            for i = id_elred:length(this.ElementosRed)
                this.ElementosRed(i).IdElementoRed = i;
            end

            %elimina objeto línea
            delete(linea);
            clear linea;
        end

        function elimina_bateria(this, bateria)
            se = bateria.entrega_se();
            id_elred = bateria.IdElementoRed;
            id_bateria = bateria.Id;
            
            if this.Baterias(id_bateria) ~= bateria
                error = MException('cSistemaElectricoPotencia:elimina_bateria','id bateria no coincide');
                throw(error)
            end
            if this.ElementosRed(id_elred) ~= bateria
                error = MException('cSistemaElectricoPotencia:elimina_bateria','id elemento de red no coincide');
                throw(error)
            end

            se.elimina_elemento_red(bateria);
            
            this.Baterias(id_bateria) = [];
            %actualiza baterias
            for i = id_bateria:length(this.Baterias)
                this.Baterias(i).Id = i;
            end
            
            % actualiza elementos de red
            this.ElementosRed(id_elred) = [];
            for i = id_elred:length(this.ElementosRed)
                this.ElementosRed(i).IdElementoRed = i;
            end

            %elimina objeto línea
            delete(bateria);
            clear bateria;
        end

        function elimina_almacenamiento(this, almacenamiento)
            id_elred = almacenamiento.IdElementoRed;
            id_alm = almacenamiento.Id;
            
            if this.Almacenamientos(id_alm) ~= almacenamiento
                error = MException('cSistemaElectricoPotencia:elimina_almacenamiento','id almacenamiento no coincide');
                throw(error)
            end
            if this.ElementosRed(id_elred) ~= almacenamiento
                error = MException('cSistemaElectricoPotencia:elimina_almacenamiento','id elemento de red no coincide');
                throw(error)
            end

            se.elimina_elemento_red(almacenamiento);
            
            this.Almacenamientos(id_alm) = [];
            %actualiza baterias
            for i = id_alm:length(this.Almacenamientos)
                this.Almacenamientos(i).Id = i;
            end
            
            % actualiza elementos de red
            this.ElementosRed(id_elred) = [];
            for i = id_elred:length(this.ElementosRed)
                this.ElementosRed(i).IdElementoRed = i;
            end

            %elimina objeto línea
            delete(almacenamiento);
            clear almacenamiento;
        end
        
        function id_grafico = grafica_sistema(this, nombre, solo_corredores)
            graficos = cAdministradorGraficos.getInstance();
            id_grafico = graficos.crea_nueva_figura(nombre);
            for se = 1:length(this.Subestaciones)
                graficos.grafica_elemento(this.Subestaciones(se), false);
                
                %generadores
                for gen = 1:length(this.Subestaciones(se).Generadores)
                    graficos.grafica_elemento(this.Subestaciones(se).Generadores(gen), false);
                end

                %consumos
                for cons = 1:length(this.Subestaciones(se).Consumos)
                    graficos.grafica_elemento(this.Subestaciones(se).Consumos(cons), false);
                end
                        
                for gen = 1:length(this.Subestaciones(se).GeneradoresRES)
                    graficos.grafica_elemento(this.Subestaciones(se).GeneradoresRES(gen), false);
                end

                %lineas
                for linea = 1:length(this.Subestaciones(se).Lineas)
                    [se_1, ~] = this.Subestaciones(se).Lineas(linea).entrega_subestaciones();
                    if se_1 ~= this.Subestaciones(se)
                    	continue;
                    end
                    
                    if solo_corredores
                        if this.Subestaciones(se).Lineas(linea).entrega_indice_paralelo() == 1
                            graficos.grafica_elemento(this.Subestaciones(se).Lineas(linea), false);
                        end
                    else
                        graficos.grafica_elemento(this.Subestaciones(se).Lineas(linea), false);
                    end
                end % fin puntos de operación
            end % fin cantidad de etapas
        end
        
        function grafica_resultado_flujo_potencia(this, id_grafico)
            graficos = cAdministradorGraficos.getInstance();
            graficos.activa_figura(id_grafico);

            cant_corredores = 0;
            p_corredores = [];
            nro_lineas = [];
            reactancia_lineas = [];
            for se = 1:length(this.Subestaciones)
                graficos.grafica_resultado_flujo_potencia(this.Subestaciones(se));
                
                %generadores
                for gen = 1:length(this.Subestaciones(se).Generadores)
                    graficos.grafica_resultado_flujo_potencia(this.Subestaciones(se).Generadores(gen));
                end

                %consumos
                for cons = 1:length(this.Subestaciones(se).Consumos)
                    graficos.grafica_resultado_flujo_potencia(this.Subestaciones(se).Consumos(cons));
                end
                        
                for gen = 1:length(this.Subestaciones(se).GeneradoresRES)
                    graficos.grafica_resultado_flujo_potencia(this.Subestaciones(se).GeneradoresRES(gen));
                end

                %lineas
                for id_linea = 1:length(this.Subestaciones(se).Lineas)
                    [se_1, se_2] = this.Subestaciones(se).Lineas(id_linea).entrega_subestaciones();
                    if se_1 ~= this.Subestaciones(se)
                    	continue;
                    end
                    linea = this.Subestaciones(se).Lineas(id_linea);
                    p_linea = linea.entrega_p_in();
                    id_corr = [];
                    if cant_corredores ~= 0
                        id_corr = find(ismember(corredores, [se_1 se_2], 'rows'));
                    end
                    if ~isempty(id_corr)
                    	p_corredores(id_corr) = p_corredores(id_corr) + p_linea;
                        nro_lineas(id_corr) = nro_lineas(id_corr) + 1;
                        % verifica reactancia
                        x = linea.entrega_reactancia();
                        if reactancia_lineas(id_corr) ~= x
                            error = MException('cSistemaElectricoPotencia:grafica_resultado_flujo_potencia','reactancia de las líneas paralelas no coincide');
                            throw(error)
                        end
                    else
                    	cant_corredores = cant_corredores + 1;
                        corredores(cant_corredores,1) = se_1;
                        corredores(cant_corredores,2) = se_2;
                        p_corredores(cant_corredores,1) = p_linea;
                        nro_lineas(cant_corredores,1) = 1;
                        x = linea.entrega_reactancia();
                        reactancia_lineas(cant_corredores,1) = x;
                    end
                end
            end
            
            % se agregan los resultados de los corredores
            for corr = 1:length(corredores)
            	se_1 = corredores(corr,1);
                se_2 = corredores(corr,2);
                p = p_corredores(corr);
                cant_lineas = nro_lineas(corr);
                x_linea = reactancia_lineas(id_corr);
                graficos.agrega_resultado_corredor(se_1, se_2, p, cant_lineas, x_linea);
            end
        end
                
        function opf = entrega_opf(this)
            opf = this.pOPF;
        end
        
        function fp = entrega_fp(this)
            fp = this.pFP;
        end
        
        function res_eval = entrega_evaluacion(this)
            res_eval = this.pResEvaluacion;
        end
                
        function proyectos = entrega_proyectos(this)
            proyectos = this.ProyectosExpansionTx;
        end
        
        function elem = entrega_elementos_serie(this)
            elem = this.Lineas;
            elem = [elem; this.Transformadores2D];
        end

         function mpc = genera_version_matpower(this)
            %CASE118    Power flow data for IEEE 118 bus test case.
            %   Please see CASEFORMAT for details on the case file format.
            %   This data was converted from IEEE Common Data Format
            %   (ieee118cdf.txt) on 15-Oct-2014 by cdf2matp, rev. 2393
            %   See end of file for warnings generated during conversion.
            %
            %   Converted from IEEE CDF file from:
            %       http://www.ee.washington.edu/research/pstca/
            %   With baseKV data take from the PSAP format file from the same site,
            %   added manually on 10-Mar-2006.
            % 
            %   08/25/93 UW ARCHIVE           100.0  1961 W IEEE 118 Bus Test Case

            %   MATPOWER
            parsep = cParametrosSistemaElectricoPotencia.getInstance();
            CantidadSubestaciones = length(this.Subestaciones);
            CantidadGeneradores = length(this.Generadores);
            CantidadLineas = length(this.Lineas);
            CantidadTransformadores2D = length(this.Transformadores2D);
             
            % MATPOWER Case Format : Version 2
            mpc.version = '2';
             
            %-----  Power Flow Data  -----%%
            % system MVA base
            mpc.baseMVA = parsep.entrega_sbase();

            % bus data
            %	bus_i	type	Pd	Qd	Gs	Bs	area	Vm	Va	baseKV	zone	Vmax	Vmin
            bus = zeros(CantidadSubestaciones, 13);
            bus(:,2) = ones(CantidadSubestaciones, 1);
            bus(:,8) = ones(CantidadSubestaciones, 1);
            for i = 1:CantidadSubestaciones
                bus(i,1) = this.Subestaciones(i, 1).Id;
                if ~isempty(this.Subestaciones(i, 1).Generadores)
                    for g = 1:numel(this.Subestaciones(i, 1).Generadores)
                        if this.Subestaciones(i, 1).Generadores(g,1).ControlaTension
                            if this.Subestaciones(i, 1).Generadores(g,1).Slack
                                bus(i,2) = 3; % Slack
                            else
                                bus(i,2) = 2; % PV
                            end
                        else
                            bus(i,2) = 1; % PQ
                            bus(i,3) = bus(i,3)-this.Subestaciones(i, 1).Generadores(g,1).Pfp;
                            bus(i,4) = bus(i,4)-this.Subestaciones(i, 1).Generadores(g,1).Qfp;
                        end
                    end
                end
                if ~isempty(this.Subestaciones(i, 1).Consumos)
                    for g = 1:numel(this.Subestaciones(i, 1).Consumos)
                        bus(i,3) = bus(i,3)+this.Subestaciones(i, 1).Consumos(g,1).Pfp;
                        bus(i,4) = bus(i,4)+this.Subestaciones(i, 1).Consumos(g,1).Qfp;
                    end
                end
                bus(i,7) = 1;
                bus(i,10) = this.Subestaciones(i, 1).Vn;
                bus(i,8) = this.Subestaciones(i, 1).Vfp/bus(i,10);
                bus(i,9) = this.Subestaciones(i, 1).Angulofp;
                bus(i,11) = 1;
                % Vmin y Vmax en pu
                if this.Subestaciones(i, 1).VMax ~= 0
                    bus(i,12) = this.Subestaciones(i, 1).VMax;
                else
                    bus(i,12) = parsep.entrega_vmax_vn_pu(this.Subestaciones(i, 1).Vn);
                end
                if this.Subestaciones(i, 1).VMin ~= 0
                    bus(i,13) = this.Subestaciones(i, 1).VMin;
                else
                    bus(i,13) = parsep.entrega_vmin_vn_pu(this.Subestaciones(i, 1).Vn);
                end
            end
            mpc.bus = bus;
            % generator data
            %	bus	Pg	Qg	Qmax	Qmin	Vg	mBase	status	Pmax	Pmin	Pc1	Pc2	Qc1min	Qc1max	Qc2min	Qc2max	ramp_agc	ramp_10	ramp_30	ramp_q	apf
            bus = zeros(CantidadGeneradores, 21);
            bus(:,6) = ones(CantidadGeneradores, 1);
            for i = 1:CantidadGeneradores
                bus(i,1) = this.Generadores(i, 1).SE.Id;
                bus(i,2) = this.Generadores(i, 1).Pfp;
                bus(i,3) = this.Generadores(i, 1).Qfp;
                bus(i,4) = this.Generadores(i, 1).Qmax;
                bus(i,5) = this.Generadores(i, 1).Qmin;
                bus(i,8) = this.Generadores(i, 1).EnServicio;
                bus(i,9) = this.Generadores(i, 1).Pmax;
                bus(i,10) = this.Generadores(i, 1).Pmin;
            end
            bus(:,7) = sqrt(max(abs(bus(:,4)),abs(bus(:,5))).^2+max(abs(bus(:,9)), abs(bus(:,10))).^2);
            mpc.gen = bus;
            
            % branch data
            %	fbus	tbus	r	x	b	rateA	rateB	rateC	ratio	angle	status	angmin	angmax
            bus = zeros(CantidadLineas + CantidadTransformadores2D, 13);
            bus(:,11) = ones(CantidadLineas + CantidadTransformadores2D, 1);
            bus(:,12) = -ones(CantidadLineas + CantidadTransformadores2D, 1)*parsep.entrega_angulo_maximo_buses()*180/pi;
            bus(:,13) = ones(CantidadLineas + CantidadTransformadores2D, 1)*parsep.entrega_angulo_maximo_buses()*180/pi;
            for i = 1:CantidadLineas
                [Bus1, Bus2] = this.Lineas(i, 1).entrega_subestaciones();
                bus(i,1) = Bus1.entrega_id();
                bus(i,2) = Bus2.entrega_id();
                bus(i,3) = this.Lineas(i, 1).entrega_resistencia_pu();
                bus(i,4) = this.Lineas(i, 1).entrega_reactancia_pu();
                bus(i,5) = this.Lineas(i, 1).entrega_susceptancia_pu();
            end
            for i = 1:CantidadTransformadores2D
                [Bus1, Bus2] = this.Transformadores2D(i, 1).entrega_subestaciones();
                bus(i + CantidadLineas,1) = Bus1.entrega_id();
                bus(i + CantidadLineas,2) = Bus2.entrega_id();
                bus(i + CantidadLineas,3) = 0;
                bus(i + CantidadLineas,4) = this.Transformadores2D(i, 1).entrega_reactancia_pu();
                bus(i + CantidadLineas,5) = 0;
                bus(i + CantidadLineas,9) = this.Transformadores2D(i, 1).entrega_TapActual()- ...
                           this.Transformadores2D(i, 1).entrega_TapNom();
            end
            
            mpc.branch = bus;
            % -----  OPF Data  -----%%
            % generator cost data
            %	1	startup	shutdown	n	x1	y1	...	xn	yn
            %	2	startup	shutdown	n	c(n-1)	...	c0
            bus = zeros(CantidadGeneradores, 7);
            bus(:,1) = ones(CantidadGeneradores, 1)*2;
            bus(:,4) = ones(CantidadGeneradores, 1)*2;
            for i = 1:CantidadGeneradores
                bus(i,2) = this.Generadores(i, 1).CostoPartida;
                bus(i,3) = this.Generadores(i, 1).CostoDetencion;
                bus(i,5) = this.Generadores(i, 1).Costo_MWh;
                bus(i,6) = this.Generadores(i, 1).CostoFijo;
            end
            mpc.gencost = bus;
            
            % bus names
            mpc.bus_name = cell(CantidadSubestaciones,1);
            for i = 1:CantidadSubestaciones
                mpc.bus_name{i} = this.Subestaciones(i, 1).Nombre;
            end
        end
	end
end