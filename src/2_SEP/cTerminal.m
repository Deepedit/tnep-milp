classdef cTerminal < cElementoRed
        % clase que representa los transformadores
    properties		
        Subestacion = cCSubestacion.empty
        
        Generadores = cGenerador.empty
        GeneradoresDespachables = cGenerador.empty
        GeneradoresRES = cGenerador.empty
        Consumos = cConsumo.empty
        Lineas = cLinea.empty
        Transformadores2D = cTransformador2D.empty
        %Transformadores3D = cTransformador3D.empty

        % Id del bus al cual pertenece el terminal
        IdBus
        
        % Resultado del flujo de potencia
        id_fp
        Vfp
        Angulofp % en grados
        Slack
        
    end
    
    methods
        function this = cTerminal(varargin)
            % varargin contiene la subestación
            this.TipoElementoRed = 'Bus';
            if nargin > 0
                this.Subestacion = varargin{1};
            end
        end

        function agrega_linea(obj, linea)
            obj.Lineas = [obj.Lineas linea];
        end
        
        function agrega_generador(obj, generador)
            obj.Generadores = [obj.Generadores generador];
            if generador.Despachable
                obj.GeneradoresDespachables = [obj.GeneradoresDespachables generador];
            else
                obj.GeneradoresRES = [obj.GeneradoresRES generador];
            end
        end
        
        function agrega_consumo(obj, consumo)
            obj.Consumos = [obj.Consumos consumo];
        end

        function agrega_transformador2D(obj, trafo)
            obj.Transformadores2D = [obj.Transformadores2D trafo];
        end

%        function agrega_transformador3D(obj, trafo)
%            obj.Transformadores3D = [obj.Transformadores3D trafo];
%        end
        
        function conectividad = existe_conectividad_estructural(obj)
            conectividad = true;
            if isempty(obj.Lineas) && isempty(obj.Transformadores2D) && isempty(obj.Transformadores3D)
                conectividad = false;
            end
        end
        
        function conectividad = existe_conectividad_operacional(this)
            if ~this.existe_conectividad()
                conectividad = false;
                return
            end
            
            for i = 1:length(this.Lineas)
                if this.Lineas(i).en_servicio()
                    conectividad = true;
                    return
                end
            end

            for i = 1:length(this.Transformadores2D)
                if this.Transformadores2D(i).en_servicio()
                    conectividad = true;
                    return
                end
            end

            for i = 1:length(this.Transformadores3D)
                if this.Transformadores3D(i).en_servicio()
                    conectividad = true;
                    return
                end
            end
            
            conectividad = false;
        end
        function inserta_resultados_flujo_potencia_pu(this, id_fp, voltaje, angulo)
            this.id_fp = id_fp;
            this.Vfp = voltaje*this.Vn;
            this.Angulofp = angulo/pi*180;
        end
        
        function val = entrega_voltaje_fp(this)
            val = this.Vfp;
        end
        
        function val = entrega_angulo_fp(this)
            val = this.Angulofp;
        end
        
        function inserta_es_slack(this, val)
            this.Slack = val;
        end
        
        function val = es_slack(this)
            val = this.Slack;
        end
        
        function val = tiene_se(this)
            if isempty(this.Subestacion)
                val = false;
            else
                val = true;
            end
        end
    end
end    