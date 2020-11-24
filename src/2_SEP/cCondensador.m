classdef cCondensador < cElementoRed
        % clase que representa los transformadores
    properties
        %parámetros técnicos
        SE = cSubestacion.empty
		Vr
		Qr                  %Potencia reactiva en voltaje nominal. Debe ser positiva
        Qmax                % Máxima potencia reactiva que puede entregar el condensador
        Qmin = 0
		TapMax = 1 % tap siempre son enteros
        ControlaTension = true % en este caso, tap del condensador se ajusta en el flujo de potencias de acuerdo al voltaje objetivo
        VoltajeObjetivo = 0 % kV
        
        % parámetros operacionales en/para flujo de potencia
        TapActual = 1        
    end
    
    methods
        function this = cCondensador()
            this.TipoElementoRed = 'ElementoParalelo';
        end

        function condensador = crea_copia(this)
            condensador = cCondensador();
            condensador.Nombre = this.Nombre;
            condensador.Id = this.Id;
            condensador.EnServicio = this.EnServicio;
            condensador.FlagObservacion = this.FlagObservacion;
            condensador.Vr= this.Vr;
            condensador.Qr = this.Qr;
            condensador.Qmax = this.Qmax;
            condensador.TapActual = this.TapActual;
            condensador.ControlaTension = this.ControlaTension;
            condensador.VoltajeObjetivo = this.VoltajeObjetivo;
        end
        
        function inserta_qr(this, val)
            if val > 0
                this.Qr = val;
            else
                error = MException('cCondensador:inserta_qr','valor debe ser positivo');
                throw(error)
            end
        end
        
        function inserta_vr(this, val)
            this.Vr = val;
        end

        function se = entrega_se(this)
            se = this.SE;
        end
                
        function tap = entrega_tap_max(this)
            tap = this.TapMax;
        end
        
        function tap = entrega_tap_actual(this)
            tap = this.TapActual;
        end
        
        function inserta_tap_actual(this, val)
            if val <= this.TapMax
                this.TapActual = val;
            else
                error = MException('cCondensador:inserta_tap_actual','Tap actual fuera de rango');
                throw(error)
            end
        end

        function val = entrega_qr(this)
            val = this.Qr;
        end
        
        function val = en_servicio(this)
            val = this.EnServicio;
        end
                
        function inserta_tap_max(this, val)
            this.TapMax = val;
        end

        function val = entrega_admitancia(this)
            val = -complex(0,this.Qr/this.Vr^2);
            val = val*this.TapActual/this.TapMax;
        end
        
        function y = entrega_dipolo(this)
            % Siempre en pu. 
            % TODO FALTA!
            error = MException('cCondensador:entrega_dipolo','Aún no implementado');
            throw(error)
            
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            zbase = this.SE1.entrega_vbase()^2/sbase;
            
            y = -complex(0,this.Qr/this.Vr^2);
            y = y*this.TapActual/this.TapMax;
        end
        
        function valor = controla_tension(this)
            valor = this.ControlaTension;
        end
            
        function inserta_controla_tension(this)
            this.ControlaTension = true;
        end

        function inserta_voltaje_objetivo(this, val)
            this.VoltajeObjetivo = val;
        end
        
        function valor = entrega_voltaje_objetivo(this)
            if this.ControlaTension
                valor = this.VoltajeObjetivo;
            else
                error = MException('cCondensador:entrega_voltaje_objetivo','bateria no controla tension');
                throw(error)
            end
        end

        function valor = entrega_voltaje_objetivo_pu(this)
            if this.ControlaTension
                vbase = this.SE.entrega_vbase();
                valor = this.VoltajeObjetivo/vbase;
            else
                error = MException('cCondensador:entrega_voltaje_objetivo','generador no controla tension');
                throw(error)
            end
        end
        
        function valor = entrega_qmax(this)
            valor = this.Qmax;
        end
        
        function inserta_qmax(this, val)
            this.Qmax = val;
        end
    end
end