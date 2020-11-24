classdef (Sealed) cAdministradorGraficos < handle

    properties
        Figuras = [];

        Dx = 100;
        Dy = 100;
        
        ColorLineaActual = [0 0 0] %valor por defecto es negro
        black = [0 0 0]
        blue = [0 0 1]
        red = [1 0 0]
        
    end
    
    methods (Access = private)
        function this = cAdministradorGraficos
            %fprintf(this.docID, 'Comienzo del protocolo\n');
        end
    end
    
    methods (Static)
        function singleObj = getInstance
            persistent localObj
            if isempty(localObj) || ~isvalid(localObj)
                localObj = cAdministradorGraficos;
            end
            singleObj = localObj;
        end
    end
    
    methods

        function grafica_elemento(this, el_red, varargin)
            %varargin indica si se imprimen o no los resultados de la
            %operación (FP)
            operacion = true;
            if nargin > 2
                operacion = varargin{1};
            end
            if isa(el_red, 'cSubestacion')
                this.grafica_subestacion(el_red, operacion);
            elseif isa(el_red, 'cGenerador')
                this.grafica_generador(el_red, operacion);
            elseif isa(el_red, 'cConsumo')
                this.grafica_consumo(el_red, operacion);
            elseif isa(el_red, 'cLinea')
                this.grafica_linea(el_red, operacion);
            end
        end

        function grafica_resultado_flujo_potencia(this, el_red)
            if isa(el_red, 'cSubestacion')
                this.grafica_resultado_flujo_potencia_subestacion(el_red);
            elseif isa(el_red, 'cGenerador')
                this.grafica_resultado_flujo_potencia_generador(el_red);
            elseif isa(el_red, 'cConsumo')
                this.grafica_resultado_flujo_potencia_consumo(el_red);
            elseif isa(el_red, 'cLinea')
                this.grafica_resultado_flujo_potencia_linea(el_red);
            end
        end
        
        function grafica_subestacion(this, el_red, operacion)
            color_linea = this.ColorLineaActual;
        	[posX, posY] = el_red.entrega_posicion();

        	plot([posX - this.Dx, posX + this.Dx],...
                 [posY, posY], 'Color', color_linea);
            texto = el_red.entrega_nombre();
            text(posX - 3*this.Dx, posY, texto, 'FontSize',8);
            if operacion
                vn = el_red.entrega_voltaje_fp();
                angulo = round(el_red.entrega_angulo_fp(),1);
                texto = [num2str(vn) '\angle' num2str(angulo)];
                text(posX + this.Dx, posY+10, texto, 'FontSize', 8);
            end
        end

        function grafica_resultado_flujo_potencia_subestacion(this, el_red)
        	[posX, posY] = el_red.entrega_posicion();

            vn = el_red.entrega_voltaje_fp();
            angulo = round(el_red.entrega_angulo_fp(),1);
            texto = [num2str(vn) '\angle' num2str(angulo)];
            text(posX + this.Dx, posY+10, texto, 'FontSize', 8);
        end
        
        function grafica_generador(this, el_red, operacion)
            size_gen = 40;
            color_linea = this.ColorLineaActual;
            [posX, posY] = el_red.entrega_se().entrega_posicion();
            circles(posX - this.Dx/2, posY + this.Dy, size_gen, 'facecolor','none')
            plot([posX - this.Dx/2, posX - this.Dx/2],...
                 [posY + this.Dy - size_gen/2, posY], 'Color', color_linea);
            if operacion
                p_fp = num2str(round(el_red.entrega_p_fp(),1));
                text(posX - this.Dx, posY + this.Dy + 3*size_gen, p_fp, 'FontSize',8); 
            end
        end

        function grafica_resultado_flujo_potencia_generador(this, el_red)
            size_gen = 40;
            [posX, posY] = el_red.entrega_se().entrega_posicion();

            p_fp = num2str(round(el_red.entrega_p_fp(),1));
            text(posX - this.Dx, posY + this.Dy + 3*size_gen, p_fp, 'FontSize',8); 
        end
        
        function grafica_consumo(this, el_red, operacion)
            [posX, posY] = el_red.entrega_se().entrega_posicion();
            text(posX-this.Dx,posY - this.Dy/2,'\downarrow','FontSize',12,'FontWeight','bold')
            
            if operacion
                p_fp = num2str(el_red.entrega_p_fp());
                text(posX - this.Dx, posY - 2*this.Dy, p_fp, 'FontSize',8);
            end
        end

        function grafica_resultado_flujo_potencia_consumo(this, el_red)
            [posX, posY] = el_red.entrega_se().entrega_posicion();
            p_fp = num2str(el_red.entrega_p_fp());
            text(posX - this.Dx, posY - 2*this.Dy, p_fp, 'FontSize',8);
        end
        
        function grafica_linea(this, el_red, operacion)
            [posX1, posY1] = el_red.entrega_se1().entrega_posicion();
            [posX2, posY2] = el_red.entrega_se2().entrega_posicion();
            par_index = el_red.entrega_indice_paralelo();
            color_linea = this.ColorLineaActual;
            if this.ColorLineaActual == this.blue
                % se trata de una línea nueva
                if el_red.entrega_se1().entrega_vn() == 220
                    color_linea = this.red;
                end
            end
            plot([posX1 + this.Dx*(par_index-1)/2, posX2 + this.Dx*(par_index-1)/2],...
            	 [posY1, posY2], 'Color', color_linea);
            if operacion
                p_fp = el_red.entrega_p_in();
                %if par_index == 1
                    posx_texto = (posX1 + posX2)/2;
                    posy_texto = (posY1 + posY2)/2;
        
                    text(posx_texto, posy_texto, [num2str(round(p_fp,1)) '(x1)'], 'FontSize',6, 'BackgroundColor', 'white');
                    %text(posX2, posY2-this.Dy, [num2str(round(p_fp,1)) '(x1)'], 'FontSize',6);
                %end
            end
        end
        
        function id = crea_nueva_figura(this, titulo)
            id = length(this.Figuras)+1;
            this.Figuras(id) = figure;
            title(titulo);
            xlim([0 2500]);
            ylim([0 2500]);
            hold on
        end
        
        function activa_figura(this, id)
            figure(this.Figuras(id));
        end
        
        function fija_color_linea(this, color)
            if strcmp(color, 'azul')
                this.ColorLineaActual = this.blue;
            elseif strcmp(color, 'negro')
                this.ColorLineaActual = this.black;
            else
                error = MException('cAdministradorGraficos:fija_color_linea',['color ' color 'no incorporado']);
                throw(error)
            end
        end
        
        function agrega_resultado_corredor(this, se_1, se_2, p, cant_lineas, reactancia_lineas)
            [posX1, posY1] = se_1.entrega_posicion();
            [posX2, posY2] = se_2.entrega_posicion();
            dx = this.Dx;
            dy = this.Dy;
            posx_texto = (posX1 + posX2)/2;
            posy_texto = (posY1 + posY2)/2;
        
            reactancia_equivalente = reactancia_lineas/cant_lineas;
            text(posx_texto, posy_texto, [num2str(round(abs(p),1)) '(x' num2str(cant_lineas) ')'], 'FontSize',6, 'BackgroundColor', 'white');
            %text(posx_texto, posy_texto - dy, ['x ' num2str(cant_lineas) 'x_(tot) = ' num2str(round(reactancia_equivalente,1))], 'FontSize',6, 'BackgroundColor', 'white');

            r = 100;
            %theta = atan((posY2-posY1)/(posX2-posX1));
            theta = atan2(posY2-posY1, posX2-posX1);
            if p < 0
                theta = theta + pi;
            end
            
            u = r * cos(theta); % convert polar (theta,r) to cartesian
            v = r * sin(theta);
            quiver(posx_texto + dx,posy_texto,u,v, 'k', 'MaxHeadSize',5);
        end
            
    end
end