classdef cFeromonaACO < handle
        % clase que representa las lineas de transmision
    properties
        FerProyectos
        DFerActual
    end
    
    methods    
        function obj = cFeromonaACO(nro_etapas, nro_proyectos)
            obj.FerProyectos = zeros(nro_etapas+1, nro_proyectos);
            obj.DFerActual = zeros(nro_etapas+1, nro_proyectos);
        end
        
        function inicializa_feromonas(obj, nro_etapas, nro_proyectos, prob_construccion_inicial, varargin)
            % varargin indica proyectos vetados
            obj.FerProyectos = zeros(nro_etapas+1, nro_proyectos);
            valor_etapa_no_construccion = 100 - prob_construccion_inicial*100;
            valor_inicial_etapas = 100*prob_construccion_inicial/nro_etapas;
            obj.FerProyectos(1:nro_etapas, :) = valor_inicial_etapas;
            obj.FerProyectos(nro_etapas + 1, :) = valor_etapa_no_construccion;
            if nargin > 4
                % hay proyectos vetados
                proy_vetados = varargin{1};
                obj.FerProyectos(1:nro_etapas, proy_vetados) = 0;
                obj.FerProyectos(nro_etapas + 1, proy_vetados) = 100;
            end
        end
                    
        function evapora_feromonas(obj, mult)
            obj.FerProyectos = obj.FerProyectos*mult;
        end
        
        function incrementa_feromona_proyecto(obj,etapa, indice_proyecto, valor)
            obj.FerProyectos(etapa+1, indice_proyecto)= obj.FerProyectos(etapa+1, indice_proyecto)+valor;
        end

        function fer = entrega_feromonas_acumuladas_hasta_etapa(this, nro_etapa, varargin)
            % varargin indica espacio de proyectos. Si no se indica nada,
            % se consideran todos los proyectos
            if nargin > 2
                fer = sum(this.FerProyectos(1:nro_etapa,varargin{1}));
            else
                fer = sum(this.FerProyectos(1:nro_etapa,:));
            end
        end

        function fer = entrega_delta_feromonas_acumuladas_hasta_etapa(this, nro_etapa, varargin)
            % varargin indica espacio de proyectos. Si no se indica nada,
            % se consideran todos los proyectos
            if nargin > 2
                fer = sum(this.DFerActual(1:nro_etapa,varargin{1}));
            else
                fer = sum(this.DFerActual(1:nro_etapa,:));
            end
        end
        
        function fer = entrega_feromonas_etapa(this, nro_etapa, varargin)
            % varargin indica espacio de proyectos. Si no se indica nada,
            % se consideran todos los proyectos
            if nargin > 2
                fer = this.FerProyectos(nro_etapa,varargin{1});
            else
                fer = this.FerProyectos(nro_etapa,:);
            end
        end
        
        function fer = entrega_feromonas_acumuladas_desde_etapa(this, nro_etapa, varargin)
            % varargin indica espacio de proyectos. Si no se indica nada,
            % se consideran todos los proyectos
            if nargin > 2
                fer = sum(this.FerProyectos(nro_etapa:end,varargin{1}));
            else
                fer = sum(this.FerProyectos(nro_etapa:end,:));
            end
        end
        
        function fer = entrega_feromonas_no_construccion(this, varargin)
            % varargin indica espacio de proyectos. Si no se indica nada,
            % se consideran todos los proyectos
            if nargin > 1
                fer = this.FerProyectos(end,varargin{1});
            else
                fer = this.FerProyectos(end,:);
            end
        end

        function fer = entrega_feromonas_construccion(this, varargin)
            % varargin indica espacio de proyectos. Si no se indica nada,
            % se consideran todos los proyectos
            if nargin > 1
                fer = 100 - this.FerProyectos(end,varargin{1});
            else
                fer = 100 - this.FerProyectos(end,:);
            end
        end
        
        function fer = entrega_feromonas_proyecto(this, id_proyecto)
           fer = this.FerProyectos(:,id_proyecto);
        end

        function fer = entrega_delta_feromonas_proyecto(this, id_proyecto)
           fer = this.DFerActual(:,id_proyecto);
        end
        
        function imprime_feromonas(this, nro_iteracion)
            prot = cProtocolo.getInstance;
            prot.imprime_texto(['Feromonas al final de la iteracion ' num2str(nro_iteracion)]);
            prot.imprime_matriz(this.FerProyectos, ['Feromonas probabilidad acumulada proyectos al final de iteracion ' num2str(nro_iteracion)]);
            
            [n,m] = size(this.FerProyectos);
            prob_fer = zeros(n,m);
            for i = 1:m
                prob_fer(:,i) = this.FerProyectos(:,i)/sum(this.FerProyectos(:,i));
            end
            prot.imprime_matriz(prob_fer, ['Densidad probabilidad construccion proyectos al final de iteracion ' num2str(nro_iteracion)]);
        end
    end
end
