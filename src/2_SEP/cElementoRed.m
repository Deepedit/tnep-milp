classdef cElementoRed < handle & matlab.mixin.Heterogeneous
        % clase que representa las lineas de transmision
    properties
        %datos generales
        Nombre
        
        % Id contiene la Id de cada elemento de red, por tipo de elemento
        % Por cada tipo de elemento, esta Id es única
        Id = []

        Texto = '' % texto opcional
        
        %IdElementoRed es una Id única para todos los elementos de red
        IdElementoRed = []
        
        %IdAmdProyectos indica la posición del elemento en la clase cAdministradorProyectos. Se utiliza en programas de expansión
        IdAdmProyectos = 0
        Existente = false
        Proyectado = false % quiere decir que no existe, pero va a entrar en operación. No es lo mismo que variable de decisión de expansión!
		%parámetros de operación
		EnServicio = true
		TipoElementoRed = 'dnix'

        %parámetros para TNEP MILP
        TipoExpansion  %opciones: 'Base', 'CC', 'CS', 'VU'

        % Posición en donde se encuentra el elemento en el DC-OPF
        PosVarOpt
        
        DummyCero = 0
        
        % Flag observación se utiliza para TNEP, para guardar resultados de
        % flujos altos y bajos en los elementos de red
        FlagObservacion = true
    end
    
    methods
        function tipo = entrega_tipo_elemento_red(this)
            tipo = this.TipoElementoRed;
        end
        
        function id = entrega_id_elemento_red(this)
            id = this.IdElementoRed;
        end

        function id = entrega_id(this)
            id = this.Id;
        end
        
        function inserta_id(this, id)
            this.Id = id;
        end
        
        function val = en_servicio(this)
            val = this.EnServicio;
        end
        
        function val = entrega_q_const_nom(this)
            % valor por defecto si función no está definida en subclases es
            % cero. 
            val = this.DummyCero;
        end
        
        function val = entrega_p_const_nom(this)
            % valor por defecto si función no está definida en subclases es
            % cero. 
            val = this.DummyCero;
        end
        
        function nombre = entrega_nombre(this)
            nombre = this.Nombre;
        end
        
        function inserta_nombre(this, nombre)
            this.Nombre = nombre;
        end
        
        function inserta_en_servicio(this, val)
            this.EnServicio = val;
        end
        
        function val = entrega_id_adm_proyectos(this)
            val = this.IdAdmProyectos;
        end
        
        function em = entrega_elemento_modal(this)
            em = this.ElementoModal;
        end
        
        function val = tiene_flag_observacion(this)
            val = this.FlagObservacion;
        end
        
        function activa_flag_observacion(this)
            this.FlagObservacion = true;
        end
        
        function desactiva_flag_observacion(this)
            this.FlagObservacion = false;
        end
        function inserta_pos_varopt(this, valor)
            % IndiceVarOpt indica la posición en VarOpt donde se encuentra
            % la variable para el OPF. Se agregó para TNEP!
            this.PosVarOpt = valor;
        end
        
        function val = entrega_pos_varopt(this)
            val = this.PosVarOpt;
        end
            
    end
end
