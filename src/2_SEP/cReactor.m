classdef cReactor < cElementoRed
        % clase que representa los transformadores
    properties		
        SE = cSubestacion.empty
        %parámetros técnicos
		Vr
        Qr           % para el reactor debe ser negativo
		Qmin
        Qmax = 0
        TapMax = 1

        ControlaTension = true % en este caso, tap del condensador se ajusta en el flujo de potencias de acuerdo al voltaje objetivo
        VoltajeObjetivo = 0 % kV
        
        % parámetros operacionales en/para flujo de potencia
        TapActual = 1        
    end
    
    methods
        function this = cReactor()
            this.TipoElementoRed = 'ElementoParalelo';
        end

        function reactor = crea_copia(this)
            reactor = cReactor();
            reactor.Nombre = this.Nombre;
            reactor.Id = this.Id;
            reactor.EnServicio = this.EnServicio;
            reactor.FlagObservacion = this.FlagObservacion;
            reactor.Vr= this.Vr;
            reactor.Qr = this.Qr;
            reactor.Qmin = this.Qmin;
            reactor.TapActual = this.TapActual;
            reactor.ControlaTension = this.ControlaTension;
            reactor.VoltajeObjetivo = this.VoltajeObjetivo;
        end
        
        function inserta_qr(this, val)
            if val < 0
                this.Qr = val;
            else
                error = MException('cReactor:inserta_qr','valor debe ser negativo');
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
        
        function val = entrega_admitancia(this)
            val = -complex(0,this.Qr/this.Vr^2);
            val = val*this.TapActual/this.TapMax;            
        end
        
        function y = entrega_dipolo(this)
            % Siempre en pu. 
            % TODO Falta!
            error = MException('cReactor:entrega_dipolo','Aún no implementado');
            throw(error)
            
            sbase = cParametrosSistemaElectricoPotencia.getInstance.entrega_sbase();
            zbase = this.SE.entrega_vbase()^2/sbase;

            sbase = this.pGPar.entrega_sbase();
            vbase = this.SE.entrega_vbase();
            ybase = sbase/vbase^2;
            y = -complex(0,this.Qr/this.Vr^2);
            y = y*this.TapActual/this.TapMax;
            y = y/ybase;
        end
        
        function inserta_resultados_fp_en_pu(this, id_fp, P, Q)
            % resultados se entregan en pu
            sbase = this.pGPar.entrega_sbase();
            this.id_fp = id_fp;
            this.P = P*sbase;
            this.Q = Q*sbase;
        end

        function inserta_resultados_fp(this, id_fp, P, Q)
            % resultados se entregan en valores reales
            this.id_fp = id_fp;
            this.P = P;
            this.Q = Q;
        end
        
        function val = entrega_q(this)
            if this.EnServicio
                val = this.Q;
            else
                val = 0;
            end
        end
        
        function val = en_servicio(this)
            val = this.EnServicio;
        end
        
        function val = entrega_p_fp(this)
            val = this.Pfp;
        end
        
        function val = entrega_q_fp(this)
            val = this.Qfp;
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
                error = MException('cReactor:entrega_voltaje_objetivo','bateria no controla tension');
                throw(error)
            end
        end

        function valor = entrega_voltaje_objetivo_pu(this)
            if this.ControlaTension
                vbase = this.SE.entrega_vbase();
                valor = this.VoltajeObjetivo/vbase;
            else
                error = MException('cReactor:entrega_voltaje_objetivo','generador no controla tension');
                throw(error)
            end
        end
        
        function valor = entrega_qmin(this)
            valor = this.Qmin;
        end
        
        function inserta_qmin(this, val)
            this.Qmin = val;
        end

    end
end