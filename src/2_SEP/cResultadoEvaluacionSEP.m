classdef cResultadoEvaluacionSEP < handle
    % Clase que guarda los resultados de la evaluación del sistema
    % eléctrico de potencia desde programas de optimización
    % todos los resultados en valores reales, no p.u.
    properties
        % Puntero al SEP. Un resultado de evaluación siempre está asociado
        % a un SEP específico.
        pSEP = cSistemaElectricoPotencia.empty
        pAdmSc % administrador de escenario
        iEtapa % etapa de cómputo
        
        ContenedoresInicializadosOPF = false
        ContenedoresInicializadosFP = false
                
        ExisteResultadoOPF = 0
        ExisteResultadoFP = 0
        NivelDetalleResultadosOPF = 0 % 0 sin detalle, 3 con máximo detalle
        NivelDetalleResultadosFP = 0 % 0 sin detalle, 3 con máximo detalle
        
        % 1. CONTENEDORES OPF
        % 1.1. NIVEL DETALLE >= 0
        % Si nivel de detalle > 0, columnas indican el PO
        % todos los valores son escalados al año de acuerdo a
        % representatividad de puntos de operación
        CostoGeneracion = []
        CostoRecorteRES = []
        CostoENS = []

        LineasFlujoMaximo = [] %[Id línea, parindex, id_se1, id_se2,porcentaje de carga máximo]
        TrafosFlujoMaximo = [] %[Id trafo parindex, id_se1, id_se2 porcentaje de carga máximo]
        LineasFlujoMaximoN1 = [] %Id línea y porcentaje de carga máximo por N menos 1
        TrafosFlujoMaximoN1 = [] %Id trafo y porcentaje de carga máximo por N menos 1
        
        LineasPocoUso = [] %[Id línea id_se1 id_se2  porcentaje de carga máximo]
        TrafosPocoUso = [] %[Id trafo id_se1 id_se2  porcentaje de carga máximo]
        LineasPocoUsoN1 = [] %Id línea y porcentaje de carga máximo por N menus 1
        TrafosPocoUsoN1 = [] %Id trafo y porcentaje de carga máximo por N menus 1

        % Baterías uso máximo y poco uso: se guarda sólo la última batería por subestación y por tipo de tecnología
        BateriasUsoMaximo = []; %[Id_bateria id_se parindex tecnología (Emaxuso-Eminuso)/(Emax - Emin)]
        BateriasPocoUso = []; %[Id bateria id_se parindex tecnología (Emaxuso-Eminuso)/(Emax - Emin)]
        
        ConsumosConENS = [] % id consumo con ENS
        SEConENS = [] % id subestaciones con ENS
        GeneradoresRecorteRES = [] % id generadores con ENS
        SEConRecorteRES = [];
        
        % 1.2 NIVEL DETALLE = 1
        UCGeneradores = []
        GeneradoresP = [] % todos, despachables y renovables
        ConsumosP = [] % se necesita en este nivel de detalle por si hay ENS

        % 1.3 Datos detallados. Columnas indican el PO
        ENS = []
        RecorteRES = []
        CostoEncendidoGeneradores = [];
        
        CantidadPuntosOperacionOPF = 0
        RepresentatividadPO = []
        
        FlujoLineasP = []
        FlujoTransformadoresP = []
        
        BateriasP = []
        BateriasE = [] % capacidad en MWh almacenada
                
        AnguloSubestaciones = [] % en grados

        EmbalsesVol = []
        EmbalsesVert = []
        EmbalsesFilt = []
        
        % 2. RESULTADOS FP
        CantidadPuntosOperacionFP = 0
        FP_Flag = []
        % 2.1. NIVEL DETALLE = 0
        FP_LineasFlujoMaximo = [] %[Id línea, id_se1, id_se2,porcentaje de carga máximo]
        FP_TrafosFlujoMaximo = [] %[Id trafo id_se1, id_se2 porcentaje de carga máximo]
        FP_LineasFlujoMaximoN1 = [] %Id línea y porcentaje de carga máximo por N menos 1
        FP_TrafosFlujoMaximoN1 = [] %Id trafo y porcentaje de carga máximo por N menos 1

        FP_BusesVMaxFueraDeLimites = []
        FP_BusesVMinFueraDeLimites = []
        
        % 2.2. NIVEL DETALLE = 1
        
        % 2.3. NIVEL DETALLE = 2
        
        FP_FlujoLineasP = [] 
        FP_FlujoLineasQ = []
        FP_FlujoTransformadoresP = [] 
        FP_FlujoTransformadoresQ = []
        FP_GeneradoresP = [] 
        FP_GeneradoresQ = []
        FP_TapTransformadores = []
        FP_TapCondensadores = []
        FP_TapReactores = []

        FP_BateriasP = []
        FP_BateriasQ = []
        
        FP_ConsumosP = []
        FP_ConsumosQ = []
        
        FP_AnguloSubestaciones = [] % en grados. 
        FP_VoltajeSubestaciones = [] % en kV

        FP_Perdidas = []
    end
    
    methods
        function this = cResultadoEvaluacionSEP(sep, tipo_resultados, nivel_detalle, n_po)
            this.pSEP = sep;
            if tipo_resultados == 1
                % OPF
                this.NivelDetalleResultadosOPF = nivel_detalle;
                this.inicializa_contenedores_opf(n_po)
            elseif tipo_resultados == 2
                % FP
                this.NivelDetalleResultadosFP = nivel_detalle;
                this.inicializa_contenedores_fp(n_po)
            else
                error = MException('cResultadoEvaluacionSEP:constructor','No existe el tipo de resultado indicado');
                throw(error)
            end
            sep.pResEvaluacion = this;
        end

        function inserta_nuevo_tipo_resultado(this, tipo_resultado, nivel_detalle, cant_po)
            if tipo_resultado == 1
                % OPF
                this.NivelDetalleResultadosOPF = nivel_detalle;
                this.inicializa_contenedores_opf(cant_po);
            elseif tipo_resultado == 2
                % FP
                this.NivelDetalleResultadosFP = nivel_detalle;
                this.inicializa_contenedores_fp(cant_po);
            else
                error = MException('cResultadoEvaluacionSEP:constructor','No existe el tipo de resultado indicado');
                throw(error)
            end
        end
        
        function inicializa_contenedores_opf(this, n_po)
            % varargin indica la cantidad de puntos de operación, en caso
            % de que los resultados sean detallados
            this.ContenedoresInicializadosOPF = true;
            this.CantidadPuntosOperacionOPF = 1;
            this.ExisteResultadoOPF = false;
            this.CostoGeneracion = 0;
            this.CostoRecorteRES = 0;
            this.CostoENS = 0;
            
            this.LineasFlujoMaximo = [];
            this.TrafosFlujoMaximo = [];
            this.LineasPocoUso = [];
            this.TrafosPocoUso = [];
            
            if this.NivelDetalleResultadosOPF > 0
                this.CantidadPuntosOperacionOPF = n_po;

                n_generadores = this.pSEP.entrega_cantidad_generadores();
                n_consumos = this.pSEP.entrega_cantidad_consumos();
                this.GeneradoresP = zeros(n_generadores, n_po);
                this.ConsumosP = zeros(n_consumos, n_po);
                
                if this.NivelDetalleResultadosOPF > 1
                    % todos los resultados
                    n_se = this.pSEP.entrega_cantidad_subestaciones();
                    n_lineas = this.pSEP.entrega_cantidad_lineas();
                    n_transformadores2D = this.pSEP.entrega_cantidad_transformadores_2D();
                    n_baterias = this.pSEP.entrega_cantidad_baterias();
                    n_embalses = this.pSEP.entrega_cantidad_embalses();
                
                    this.FlujoLineasP = zeros(n_lineas, n_po);
                    this.FlujoTransformadoresP = zeros(n_transformadores2D, n_po);
                    this.AnguloSubestaciones = zeros(n_se, n_po);
                    this.BateriasP = zeros(n_baterias, n_po);
                    this.BateriasE = zeros(n_baterias, n_po);

                    this.ENS = zeros(n_consumos, n_po);
                    this.RecorteRES = zeros(n_generadores, n_po);

                    this.CostoGeneracion = zeros(1,n_po);
                    this.CostoENS = zeros(1,n_po);
                    this.CostoRecorteRES = zeros(1,n_po);

                    this.EmbalsesVol = zeros(n_embalses, n_po);
                    this.EmbalsesVert= zeros(n_embalses, n_po);
                    this.EmbalsesFilt= zeros(n_embalses, n_po);
                end
            end
        end

        function inicializa_contenedores_fp(this, n_po)
            this.ContenedoresInicializadosFP = true;
            this.ExisteResultadoFP = 0;
            this.CantidadPuntosOperacionFP = 1;
            this.FP_LineasFlujoMaximo = [];
            this.FP_TrafosFlujoMaximo = [];
            this.FP_LineasFlujoMaximoN1 = [];
            this.FP_TrafosFlujoMaximoN1 = [];
            this.FP_BusesVMaxFueraDeLimites = [];
            this.FP_BusesVMinFueraDeLimites = [];
            this.FP_Flag = [];
            if this.NivelDetalleResultadosFP > 0
            
                % por ahora nada
                
                if this.NivelDetalleResultadosFP > 1            
                    this.CantidadPuntosOperacionFP = n_po;
                    n_se = this.pSEP.entrega_cantidad_subestaciones();
                    n_lineas = this.pSEP.entrega_cantidad_lineas();
                    n_consumos = this.pSEP.entrega_cantidad_consumos();
                    n_generadores = this.pSEP.entrega_cantidad_generadores();
                    n_trafos = this.pSEP.entrega_cantidad_transformadores_2D();
                    n_baterias = this.pSEP.entrega_cantidad_baterias();
                    n_condensadores = this.pSEP.entrega_cantidad_condensadores();
                    n_reactores = this.pSEP.entrega_cantidad_condensadores();
                    this.FP_Flag = zeros(1,n_po);
                    this.FP_FlujoLineasP = zeros(n_lineas, n_po);
                    this.FP_FlujoLineasQ = zeros(n_lineas, n_po);
                    this.FP_FlujoTransformadoresP = zeros(n_trafos, n_po);
                    this.FP_FlujoTransformadoresQ = zeros(n_trafos, n_po);
                    this.FP_GeneradoresP = zeros(n_generadores, n_po);
                    this.FP_GeneradoresQ = zeros(n_generadores, n_po);
                    this.FP_TapTransformadores = zeros(n_trafos, n_po);
                    this.FP_TapCondensadores = zeros(n_condensadores, n_po);
                    this.FP_TapReactores = zeros(n_reactores, n_po);

                    this.FP_BateriasP = zeros(n_baterias, n_po);
                    this.FP_BateriasQ = zeros(n_baterias, n_po);

                    this.FP_ConsumosP = zeros(n_consumos, n_po);
                    this.FP_ConsumosQ = zeros(n_consumos, n_po);

                    this.FP_AnguloSubestaciones = zeros(n_se, n_po);
                    this.FP_VoltajeSubestaciones = zeros(n_se, n_po);
                    this.FP_Perdidas = zeros(1, n_po);
                end
            end
        end
        
        function despacho = entrega_despacho_total(this, punto_operacion)
            if this.NivelDetalleResultadosOPF > 0
                despacho = this.GeneradoresP(:,punto_operacion);
            else
                error = MException('cResultadoEvaluacionSEP:entrega_despacho_total','No se guardaron los resultados detallados');
                throw(error)
            end
        end

        function despacho = entrega_despacho_generador(this, id_elemento, punto_operacion)
            if this.NivelDetalleResultadosOPF > 0
                despacho = this.GeneradoresP(id_elemento,punto_operacion);
            else
                error = MException('cResultadoEvaluacionSEP:entrega_despacho_generador','No se guardaron los resultados detallados');
                throw(error)                
            end
        end
        
        function val = entrega_ens(this)
           val = sum(sum(this.ENS)); 
        end
        
        function val = hay_ens(this)
            val = ~isempty(find(this.CostoENS ~= 0, 1,'first'));
        end
        
        function val = entrega_recorte_res(this)
           val = sum(sum(this.RecorteRES));
        end

        function val = hay_recorte_res(this)
            val = ~isempty(find(this.CostoRecorteRES ~= 0, 1));
        end
                
        function val = entrega_lineas_flujo_maximo(this)
            if ~isempty(this.LineasFlujoMaximo)
                val = this.pSEP.Lineas(this.LineasFlujoMaximo(:,1));
            else
                val = [];
            end
        end
        
        function val = entrega_resultado_lineas_flujo_maximo(this)
            val = this.LineasFlujoMaximo;
        end
        
        function val = entrega_flujo_linea(this, linea)
            if this.NivelDetalleResultadosOPF > 1
                val = this.FlujoLineasP(linea.entrega_id(),:);
            else
                error = MException('cResultadoEvaluacionSEP:entrega_flujo_linea','No se guardaron los flujos detallados');
                throw(error)
            end
        end
        
        function val = entrega_trafos_flujo_maximo(this)
            if ~isempty(this.TrafosFlujoMaximo)
                val = this.pSEP.Transformadores2D(this.TrafosFlujoMaximo(:,1));
            else
                val = [];
            end
        end

        function val = entrega_resultado_trafos_flujo_maximo(this)
            val = this.TrafosFlujoMaximo;
        end

        function val = entrega_resultado_lineas_y_trafos_flujo_maximo(this)
            val = [this.LineasFlujoMaximo; this.TrafosFlujoMaximo];
        end
        
        function val = entrega_lineas_poco_uso(this)
            if ~isempty(this.LineasPocoUso)
                val = this.pSEP.Lineas(this.LineasPocoUso(:,1));
            else
                val = [];
            end
        end

        function val = entrega_resultado_lineas_poco_uso(this)
            val = this.LineasPocoUso;
        end
        
        function val = entrega_trafos_poco_uso(this)
            if ~isempty(this.TrafosPocoUso)
                val = this.pSEP.Transformadores2D(this.TrafosPocoUso(:,1));
            else
                val = [];
            end
        end

        function val = entrega_resultado_trafos_poco_uso(this)
            val = this.TrafosPocoUso;
        end

        function val = entrega_baterias_uso_maximo(this)
            if ~isempty(this.BateriasUsoMaximo)
                val = this.pSEP.Baterias(this.BateriasUsoMaximo(:,1));
            else
                val = [];
            end
        end
        
        function [bat, id_se] = entrega_baterias_uso_maximo_y_id_se(this)
            if ~isempty(this.BateriasUsoMaximo)
                bat = this.pSEP.Baterias(this.BateriasUsoMaximo(:,1));
                id_se = this.BateriasUsoMaximo(:,2);
            else
                bat = [];
                id_se = [];
            end
        end
        
        function inserta_bateria_uso_maximo(this, bat, uso)
            %BateriasUsoMaximo = []; %[Id_bateria id_se tecnología parindex (Emaxuso-Eminuso)/(Emax - Emin)]          
            id_se = bat.entrega_se().entrega_id();
            id_tech = bat.entrega_id_tecnologia();
            if ~isempty(this.BateriasUsoMaximo)
                id = find(this.BateriasUsoMaximo(:,2) == id_se & this.BateriasUsoMaximo(:,3) == id_tech,1);
                if isempty(id)
                    this.BateriasUsoMaximo(end+1,:) = [bat.entrega_id() id_se id_tech bat.entrega_indice_paralelo() uso];
                elseif this.BateriasUsoMaximo(id, 4) < bat.entrega_indice_paralelo()
                    this.BateriasUsoMaximo(id, 4) = bat.entrega_indice_paralelo();
                    this.BateriasUsoMaximo(id, 1) = bat.entrega_id();
                    this.BateriasUsoMaximo(id, 5) = uso;
                end
            else
                this.BateriasUsoMaximo = [bat.entrega_id() id_se id_tech bat.entrega_indice_paralelo() uso];
            end
        end
        
        function inserta_bateria_poco_uso(this, bat, uso)
            % BateriasPocoUso = []; %[Id bateria id_se parindex tecnología (Emaxuso-Eminuso)/(Emax - Emin)]
            id_se = bat.entrega_se().entrega_id();
            id_tech = bat.entrega_id_tecnologia();
            if ~isempty(this.BateriasPocoUso)
                id = find(this.BateriasPocoUso(:,2) == id_se & this.BateriasPocoUso(:,3) == id_tech,1);
                if isempty(id)
                    this.BateriasPocoUso(end+1,:) = [bat.entrega_id() id_se id_tech bat.entrega_indice_paralelo() uso];
                elseif this.BateriasPocoUso(id, 4) < bat.entrega_indice_paralelo()
                    this.BateriasPocoUso(id, 4) = bat.entrega_indice_paralelo();
                    this.BateriasPocoUso(id, 1) = bat.entrega_id();
                    this.BateriasPocoUso(id, 5) = uso;
                end
            else
                this.BateriasPocoUso = [bat.entrega_id() id_se id_tech bat.entrega_indice_paralelo() uso];
            end
        end
        
        function val = entrega_resultado_baterias_uso_maximo(this)
            val = this.BateriasUsoMaximo;
        end
        
        function val = entrega_baterias_poco_uso(this)
            if ~isempty(this.BateriasPocoUso)
                val = this.pSEP.Baterias(this.BateriasPocoUso(:,1));
            else
                val = [];
            end
        end

        function val = entrega_resultado_baterias_poco_uso(this)
            val = this.BateriasPocoUso;
        end

        function inserta_generador_con_recorte_res(this, id_gen)
            this.GeneradoresRecorteRES(end+1) = id_gen;
            id_se = this.pSEP.Generadores(id_gen).entrega_se().entrega_id();
            if isempty(find(this.SEConRecorteRES == id_se,1))
                this.SEConRecorteRES(end+1) = id_se;
            end
        end

        function inserta_consumo_con_ens(this, id_cons)
            this.ConsumosConENS(end+1) = id_cons;
            id_se = this.pSEP.Consumos(id_cons).entrega_se().entrega_id();
            if isempty(find(this.SEConENS == id_se,1))
                this.SEConENS(end+1) = id_se;
            end
        end
        
        function val = entrega_generadores_res_con_recorte(this)
            val = this.pSEP.Generadores(this.GeneradoresRecorteRES);
        end

        function val = entrega_id_generadores_res_con_recorte(this)
            val = this.GeneradoresRecorteRES;
        end

        function val = entrega_se_con_recorte_res(this)
            val = this.pSEP.Subestaciones(this.SEConRecorteRES);
        end

        function val = entrega_id_se_con_recorte_res(this)
            val = this.SEConRecorteRES;
        end
        
        function val = entrega_consumos_ens(this)
            val = this.pSEP.Consumos(this.ConsumosConENS);
        end

        function val = entrega_id_consumos_ens(this)
            val = this.ConsumosConENS;
        end
        
        function val = entrega_se_con_consumos_ens(this)
            val = this.pSEP.Subestaciones(this.SEConENS);
        end

        function val = entrega_se_con_consumos_ens_o_recorte_res(this)
            id_validos = unique([this.SEConENS this.SEConRecorteRES]);
            val = this.pSEP.Subestaciones(id_validos);
        end
        
        function val = entrega_id_se_con_consumos_ens(this)
            val = this.SEConENS;
        end

        function costos = entrega_costos_generacion(this)
            costos = this.CostoGeneracion;
        end
        
        function costos = entrega_costos_ens(this)
            costos = this.CostoENS;
        end
        
        function costos = entrega_costos_operacion(this)
            costos = this.CostoGeneracion + this.CostoENS + this.CostoRecorteRES;
        end
        
        function imprime_resultados(this, varargin)
            % varargin{1} indica el título
            % varargin{2} indica el docID donde imprimir. Si no se indica
            % nada, entonces se manda al protocolo
            if this.NivelDetalleResultadosOPF > 1
                if nargin > 2
                    doc_id = varargin{2};
                else
                    prot = cProtocolo.getInstance;
                    doc_id = prot.entrega_doc_id();
                end

                if nargin > 1
                    fprintf(doc_id, strcat(varargin{1}, '\n'));
                else
                    texto = 'Resultados evaluacion SEP';
                    fprintf(doc_id, strcat(texto, '\n'));
                end
                fprintf(doc_id, strcat(texto, '\n'));
                % por ahora sólo un punto de operación
    %             demanda_total = zeros(length(this.PuntosOperacion),1);
    %             ens_total = zeros(length(this.PuntosOperacion),1);
    %             generacion_res = zeros(length(this.PuntosOperacion),1);
    %             recorte_res = zeros(length(this.PuntosOperacion),1);
                texto_base = sprintf('%-25s', '');
                texto_demanda = sprintf('%-25s', 'Demanda total:');
                texto_ens = sprintf('%-25s', 'ENS total:');
                texto_gen_res = sprintf('%-25s', 'Generacion RES total:');
                texto_recorte_res = sprintf('%-25s', 'Recorte RES total:');
                texto_costo_generacion = sprintf('%-25s', 'Costo generacion:');
                texto_costo_ens = sprintf('%-25s', 'Costo ENS:');
                texto_costo_recorte_res = sprintf('%-25s', 'Costo recorte RES:');
                texto_costo_operacion_total = sprintf('%-25s', 'Costo operacion total:');
                peso = 8760/length(this.PuntosOperacion);
                for i = 1:length(this.PuntosOperacion)
                    texto_base = [texto_base sprintf('%-10s', num2str(i))];
                    texto_demanda= [texto_demanda sprintf('%-10s', num2str(round(sum(this.ConsumosP(:,i)),2)))];
                    texto_ens = [texto_ens sprintf('%-10s', num2str(round(sum(this.ENS(:,i)),2)))];
                    texto_gen_res = [texto_gen_res sprintf('%-10s', num2str(round(sum(this.GeneradoresRESP(:,i)),2)))];
                    texto_recorte_res = [texto_recorte_res sprintf('%-10s', num2str(round(sum(this.RecorteRES(:,i)),2)))];
                    texto_costo_generacion = [texto_costo_generacion sprintf('%-10s', num2str(round(this.CostoGeneracion(i)*peso/1000000),2))];
                    texto_costo_ens = [texto_costo_ens sprintf('%-10s', num2str(round(this.CostoENS(i)*peso/1000000),2))];
                    texto_costo_recorte_res = [texto_costo_recorte_res sprintf('%-10s', num2str(round(this.CostoRecorteRES(i)*peso/1000000),2))];
                    costo_op_total = this.CostoGeneracion(i)*peso/1000000 + this.CostoENS(i)*peso/1000000 + this.CostoRecorteRES(i)*peso/1000000;
                    texto_costo_operacion_total = [texto_costo_operacion_total sprintf('%-10s', num2str(round(costo_op_total,2)))];
                end

                fprintf(doc_id, strcat(texto_base, '\n'));
                fprintf(doc_id, strcat(texto_demanda, '\n'));
                fprintf(doc_id, strcat(texto_gen_res, '\n'));
                fprintf(doc_id, strcat(texto_recorte_res, '\n'));
                fprintf(doc_id, strcat(texto_costo_generacion, '\n'));
                fprintf(doc_id, strcat(texto_costo_ens, '\n'));
                fprintf(doc_id, strcat(texto_costo_recorte_res, '\n'));
                fprintf(doc_id, strcat(texto_costo_operacion_total, '\n'));

                % despacho de generadores
                texto = '\nDespacho generadores';
                fprintf(doc_id, strcat(texto, '\n'));
                texto_base_1 = sprintf('%-5s %-15s %-10s %-10s', 'Id', 'Bus', 'Pmax.','Costo MWh');
                texto_base_2 = sprintf('%-5s %-15s %-10s %-10s', '', '', '','');
                for i = 1:length(this.PuntosOperacion)
                    texto_base_1 = [texto_base_1 sprintf('%-10s', 'Despacho')];
                    texto_base_2 = [texto_base_2 sprintf('%-10s', num2str(i))];
                end
                for i = 1:length(this.PuntosOperacion)
                    texto_base_1 = [texto_base_1 sprintf('%-10s', 'Loading')];
                    texto_base_2 = [texto_base_2 sprintf('%-10s', num2str(i))];
                end
                fprintf(doc_id, strcat(texto_base_1, '\n'));
                fprintf(doc_id, strcat(texto_base_2, '\n'));
                gen_despachables = this.pSEP.entrega_generadores_despachables();
                res_gen = zeros(length(gen_despachables),2+2*length(this.PuntosOperacion));
                for i = 1:length(gen_despachables)
                    res_gen(i,1) = i;
                    if ~isempty(this.pAdmSc)
                        id_generador_sc = gen_despachables(i).entrega_indice_escenario();
                        pmax = this.pAdmSc.entrega_capacidad_generador(id_generador_sc, this.iEtapa);
                    else
                        pmax = gen_despachables(i).entrega_pmax();
                    end

                    res_gen(i,2) = gen_despachables(i).entrega_costo_mwh();
                    for j = 1:length(this.PuntosOperacion)
                        res_gen(i,2+j) = this.GeneradoresDespachablesP(i,j);
                    end
                    for j = 1:length(this.PuntosOperacion)
                        res_gen(i,2+length(this.PuntosOperacion)+j) = abs(this.GeneradoresDespachablesP(i,j))/pmax*100;
                    end
                end

                [~, id_gen_ordenado] = sort(res_gen(:,2));
                for i = 1:length(id_gen_ordenado)
                    gen = gen_despachables(res_gen(id_gen_ordenado(i),1));
                    if ~isempty(this.pAdmSc)
                        id_generador_sc = gen.entrega_indice_escenario();
                        pmax = this.pAdmSc.entrega_capacidad_generador(id_generador_sc, this.iEtapa);
                    else
                        pmax = gen.entrega_pmax();
                    end
                    texto = sprintf('%-5s %-15s %-10s %-10s', ...
                        num2str(id_gen_ordenado(i)), ...
                        gen.entrega_se().entrega_nombre(), ...
                        num2str(pmax), ...
                        num2str(res_gen(id_gen_ordenado(i),2)));
                    for j = 1:length(this.PuntosOperacion)
                        texto = [texto sprintf('%-10s', num2str(round(res_gen(id_gen_ordenado(i),2+j),2)))];
                    end
                    for j = 1:length(this.PuntosOperacion)
                        texto = [texto sprintf('%-10s', num2str(round(res_gen(id_gen_ordenado(i),2+length(this.PuntosOperacion)+j),2)))];
                    end
                    fprintf(doc_id, strcat(texto, '\n'));
                end

                % Recorte RES
                if sum(sum(this.RecorteRES)) > 0
                    texto = '\nRecorte RES';
                    fprintf(doc_id, strcat(texto, '\n'));
                    texto = sprintf('%-5s %-5s', 'Id', 'Bus');
                    texto_2 = sprintf('%-5s %-5s', ' ', ' ');
                    for j = 1:length(this.PuntosOperacion)
                        texto = [texto sprintf('%-10s %-10s', 'Pmax', 'Recorte')];
                        texto_2 = [texto_2 sprintf('%-10s %-10s', num2str(j), num2str(j))];
                    end
                    fprintf(doc_id, strcat(texto, '\n'));
                    fprintf(doc_id, strcat(texto_2, '\n'));

                    generadores_ernc = this.pSEP.entrega_generadores_res();
                    for i = 1:length(generadores_ernc)
                        id_gen = generadores_ernc(i).entrega_id_resultado_evaluacion();
                        id_bus = generadores_ernc(i).entrega_se().entrega_id();
                        if sum(this.RecorteRES(id_gen,:)) > 0
                            texto = sprintf('%-5s %-5s', num2str(generadores_ernc(i).entrega_id()), num2str(id_bus));
                            for j = 1:length(this.PuntosOperacion)
                                pmax = this.GeneradoresRESP(id_gen,j)+this.RecorteRES(id_gen,j);
                                recorte = this.RecorteRES(id_gen,j);
                                texto = [texto sprintf('%-10s %-10s', num2str(round(pmax,2)), num2str(round(recorte,2)))];
                            end
                            fprintf(doc_id, strcat(texto, '\n'));
                        end
                    end
                else
                    texto = '\nNo hay recorte RES';
                    fprintf(doc_id, strcat(texto, '\n'));                
                end

                % Energía no suministrada
                if sum(sum(this.ENS)) > 0
                    texto = '\nHay energia no suministrada';
                else
                    texto = '\nNo hay energia no suministrada';
                end

                fprintf(doc_id, strcat(texto, '\n'));
                texto = sprintf('%-5s %-5s', 'Id', 'Bus');
                texto_2 = sprintf('%-5s %-5s', ' ', ' ');
                for j = 1:length(this.PuntosOperacion)
                    texto = [texto sprintf('%-10s %-10s', 'Pmax', 'ENS')];
                    texto_2 = [texto_2 sprintf('%-10s %-10s', num2str(j), num2str(j))];
                end
                fprintf(doc_id, strcat(texto, '\n'));
                fprintf(doc_id, strcat(texto_2, '\n'));

    %            texto = 'Consumos';
    %            fprintf(doc_id, strcat(texto, '\n'));

                consumos = this.pSEP.entrega_consumos();
                for i = 1:length(consumos)
    %                if sum(this.ENS(i,:)) > 0
                        con = consumos(i);
                        id_bus = con.entrega_se().entrega_id();
                        id_con = con.entrega_id();
                        texto = sprintf('%-5s %-5s', num2str(id_con), num2str(id_bus));
                        for j = 1:length(this.PuntosOperacion)
                            pmax = this.ConsumosP(i,j)+this.ENS(i,j);
                            ens = this.ENS(i,j);
                            texto = [texto sprintf('%-10s %-10s', num2str(round(pmax,2)), num2str(round(ens,2)))];
    %                    end 
                        fprintf(doc_id, strcat(texto, '\n'));
                    end
                end

                % flujos líneas
                texto = '\nFlujo lineas';
                fprintf(doc_id, strcat(texto, '\n'));
                texto_base_1 = sprintf('%-25s %-15s %-15s %-7s %-10s', 'Nombre', 'Bus1', 'Bus2', 'Largo', 'Pmax.');
                texto_base_2 = sprintf('%-25s %-15s %-15s %-7s %-10s', '', '', '','','');
                for i = 1:length(this.PuntosOperacion)
                    texto_base_1 = [texto_base_1 sprintf('%-10s', 'Flujo')];
                    texto_base_2 = [texto_base_2 sprintf('%-10s', num2str(i))];
                end
                for i = 1:length(this.PuntosOperacion)
                    texto_base_1 = [texto_base_1 sprintf('%-10s', 'Loading')];
                    texto_base_2 = [texto_base_2 sprintf('%-10s', num2str(i))];
                end
                fprintf(doc_id, strcat(texto_base_1, '\n'));
                fprintf(doc_id, strcat(texto_base_2, '\n'));
                lineas = this.pSEP.entrega_lineas();
                res_lineas = zeros(length(lineas),2+2*length(this.PuntosOperacion));
                for i = 1:length(lineas)
                    res_lineas(i,1)=i;
                    sr=lineas(i).entrega_sr();
                    res_lineas(i,2) = sr;
                    for j = 1:length(this.PuntosOperacion)
                        res_lineas(i,2+j) = this.FlujoLineasP(i,j);
                    end
                    for j = 1:length(this.PuntosOperacion)
                        res_lineas(i,2+length(this.PuntosOperacion)+j) = abs(this.FlujoLineasP(i,j))/sr*100;
                    end
                end

                [~, id_linea_ordenado] = sort(res_lineas(:,2),'descend');
                for i = 1:length(id_linea_ordenado)
                    linea = lineas(res_lineas(id_linea_ordenado(i),1));
                    se1 = linea.entrega_se1().entrega_nombre();
                    se2 = linea.entrega_se2().entrega_nombre();
                    pmax = linea.entrega_sr();
                    largo = linea.largo();
                    texto = sprintf('%-25s %-15s %-15s %-7s %-10s', ...
                        linea.entrega_nombre(), se1, se2, num2str(round(largo,1)), num2str(round(pmax,2)));
                    for j = 1:length(this.PuntosOperacion)
                        texto = [texto sprintf('%-10s', num2str(round(res_lineas(id_linea_ordenado(i),2+j),2)))];
                    end
                    for j = 1:length(this.PuntosOperacion)
                        texto = [texto sprintf('%-10s', num2str(round(res_lineas(id_linea_ordenado(i),2+length(this.PuntosOperacion)+j),2)))];
                    end
                    fprintf(doc_id, strcat(texto, '\n'));
                end

                % flujos transformadores
                texto = '\nFlujo transformadores';
                fprintf(doc_id, strcat(texto, '\n'));
                texto_base_1 = sprintf('%-25s %-15s %-15s %-10s', 'Nombre', 'Bus1', 'Bus2', 'Pmax.');
                texto_base_2 = sprintf('%-25s %-15s %-15s %-10s', '', '', '', '');
                fprintf(doc_id, strcat(texto_base_1, '\n'));
                fprintf(doc_id, strcat(texto_base_2, '\n'));

                trafos = this.pSEP.entrega_transformadores2d();
                res_trafos = zeros(length(trafos),2+2*length(this.PuntosOperacion));
                for i = 1:length(trafos)
                    res_trafos(i,1)=i;
                    sr=trafos(i).entrega_sr();
                    res_trafos(i,2) = sr;
                    for j = 1:length(this.PuntosOperacion)
                        res_trafos(i,2+j) = this.FlujoTransformadoresP(i,j);
                    end
                    for j = 1:length(this.PuntosOperacion)
                        res_trafos(i,2+length(this.PuntosOperacion)+j) = abs(this.FlujoTransformadoresP(i,j))/sr*100;
                    end
                end

                [~, id_ordenado] = sort(res_trafos(:,2),'descend');
                for i = 1:length(id_ordenado)
                    trafo = trafos(res_trafos(id_ordenado(i),1));
                    se1 = trafo.entrega_se1().entrega_nombre();
                    se2 = trafo.entrega_se2().entrega_nombre();
                    pmax = trafo.entrega_sr();
                    texto = sprintf('%-25s %-15s %-15s %-10s', ...
                        trafo.entrega_nombre(), se1, se2, num2str(pmax));
                    for j = 1:length(this.PuntosOperacion)
                        texto = [texto sprintf('%-10s', num2str(round(res_trafos(id_ordenado(i),2+j),2)))];
                    end                
                    for j = 1:length(this.PuntosOperacion)
                        texto = [texto sprintf('%-10s', num2str(round(res_trafos(id_ordenado(i),2+length(this.PuntosOperacion)+j),2)))];
                    end
                    fprintf(doc_id, strcat(texto, '\n'));
                end
            else
                error = MException('cResultadoEvaluacionSEP:imprime_resultados','Resultados no son detallados. Función no implementada aun');
                throw(error)
            end
        end
        
        function inserta_administrador_escenarios(this, adm_sc)
            this.pAdmSc = adm_sc;
        end

        function inserta_etapa(this, etapa)
            this.iEtapa = etapa;
        end

        function elimina_variable(this, variable)
            if isa(variable, 'cSubestacion')
                this.elimina_subestacion();
            elseif isa(variable, 'cLinea')
                this.elimina_linea(variable);
            elseif isa(variable, 'cTransformador2D')
                this.elimina_trafo(variable);
            elseif isa(variable, 'cBateria')
                this.elimina_bateria(variable);
            elseif isa(variable, 'cGenerador')
                this.elimina_generador(variable);
            else
                error = MException('cResultadoEvaluacionSEP:elimina_variable',['Tipo de variable ' class(variable) ' no implementada']);
                throw(error)                
            end
        end
        
        function elimina_subestacion(this)
            if this.ContenedoresInicializadosOPF && this.NivelDetalleResultadosOPF > 1
                % da lo mismo la fila de la subestación
                this.AnguloSubestaciones = this.AnguloSubestaciones(1:end-1,:);
            end
            if this.ContenedoresInicializadosFP && this.NivelDetalleResultadosFP > 1
                this.FP_AnguloSubestaciones = this.FP_AnguloSubestaciones(1:end-1,:);
                this.FP_VoltajeSubestaciones = this.FP_VoltajeSubestaciones(1:end-1,:);
            end
        end
        
        function elimina_linea(this, linea)
            if this.ContenedoresInicializadosOPF && this.NivelDetalleResultadosOPF > 1
                this.FlujoLineasP(linea.entrega_id(),:) = [];
            end
            if this.ContenedoresInicializadosFP && this.NivelDetalleResultadosFP > 1
                this.FP_FlujoLineasQ(linea.entrega_id(),:) = [];
                this.FP_FlujoLineasQ(linea.entrega_id(),:) = [];
            end
        end
        
        function elimina_transformador(this, trafo)
            if this.ContenedoresInicializadosOPF && this.NivelDetalleResultadosOPF > 1
                this.FlujoTransformadoresP(trafo.entrega_id(),:) = [];
            end
            if this.ContenedoresInicializadosFP && this.NivelDetalleResultadosFP > 1
                this.FP_FlujoLineasP(trafo.entrega_id(),:) = [];
                this.FP_FlujoLineasQ(trafo.entrega_id(),:) = [];
            end
        end
        
        function elimina_bateria(this, bateria)
            if this.ContenedoresInicializadosOPF && this.NivelDetalleResultadosOPF > 1
                this.BateriasP(bateria.entrega_id(), :) = [];
                this.BateriasE(bateria.entrega_id(), :) = [];
            end
            if this.ContenedoresInicializadosFP && this.NivelDetalleResultadosFP > 1
                this.FP_BateriasP(bateria.entrega_id(), :) = [];
                this.FP_BateriasQ(bateria.entrega_id(), :) = [];
            end
        end

        function elimina_generador(this, generador)
            if this.ContenedoresInicializadosOPF && this.NivelDetalleResultadosOPF > 1
                this.GeneradoresP(generador.entrega_id(), :) = [];
                if ~isempty(this.RecorteRES)
                    this.RecorteRES(generador.entrega_id(), :) = [];
                end
                if ~isempty(this.UCGeneradores)
                    this.UCGeneradores(generador.entrega_id(), :) = [];
                end
            end
            if this.ContenedoresInicializadosFP && this.NivelDetalleResultadosFP > 1
                this.FP_GeneradoresP(generador.entrega_id(), :) = [];
                this.FP_GeneradoresQ(generador.entrega_id(), :) = [];
            end
        end
        
        function agrega_variable(this, variable)
            if isa(variable, 'cSubestacion')
                this.agrega_subestacion();
            elseif isa(variable, 'cLinea')
                this.agrega_linea(variable);
            elseif isa(variable, 'cTransformador2D')
                this.agrega_trafo(variable);
            elseif isa(variable, 'cBateria')
                this.agrega_bateria(variable);
            elseif isa(variable, 'cGenerador')
                this.agrega_generador(variable);
            else
                error = MException('cResultadoEvaluacionSEP:agrega_variable',['Tipo de variable ' class(variable) ' no implementada']);
                throw(error)                
            end
        end
        
        function agrega_subestacion(this)
            if this.ContenedoresInicializadosOPF && this.NivelDetalleResultadosOPF > 1
                % siempre al final
                [~,m] = size(this.AnguloSubestaciones);
                this.AnguloSubestaciones = [this.AnguloSubestaciones; zeros(1,m)];
            end
            if this.ContenedoresInicializadosFP && this.NivelDetalleResultadosFP > 1
                [~,m] = size(this.AnguloSubestaciones);
                this.FP_AnguloSubestaciones = [this.FP_AnguloSubestaciones; zeros(1,m)];
                this.FP_VoltajeSubestaciones = [this.FP_VoltajeSubestaciones; zeros(1,m)];
            end
        end
        
        function agrega_linea(this, linea)
            if this.ContenedoresInicializadosOPF && this.NivelDetalleResultadosOPF > 1
                [n, m] = size(this.FlujoLineasP);
                if linea.entrega_id() ~= n+1
                    error = MException('cResultadoEvaluacionSEP:agrega_linea','Id de la línea no coincide con dimensiones de las matrices');
                    throw(error)
                end
                this.FlujoLineasP = [this.FlujoLineasP; zeros(1,m)];
            end
            if this.ContenedoresInicializadosFP && this.NivelDetalleResultadosFP > 1
                [n, m] = size(this.FP_FlujoLineasP);
                if linea.entrega_id() ~= n+1
                    error = MException('cResultadoEvaluacionSEP:agrega_linea','Id de la línea no coincide con dimensiones de las matrices');
                    throw(error)
                end
                this.FP_FlujoLineasP = [this.FP_FlujoLineasP; zeros(1,m)];
                this.FP_FlujoLineasQ = [this.FP_FlujoLineasQ; zeros(1,m)];
            end
        end
        
        function agrega_trafo(this, trafo)
            if this.ContenedoresInicializadosOPF && this.NivelDetalleResultadosOPF > 1
                [n, m] = size(this.FlujoTransformadoresP);
                if trafo.entrega_id() ~= n+1
                    error = MException('cResultadoEvaluacionSEP:agrega_linea','Id del trafo no coincide con dimensiones de las matrices');
                    throw(error)
                end
                this.FlujoTransformadoresP= [this.FlujoTransformadoresP; zeros(1,m)];
            end
            if this.ContenedoresInicializadosFP && this.NivelDetalleResultadosFP > 1
                [n, m] = size(this.FP_FlujoTransformadoresP);
                if trafo.entrega_id() ~= n+1
                    error = MException('cResultadoEvaluacionSEP:agrega_linea','Id del trafo no coincide con dimensiones de las matrices');
                    throw(error)
                end
                this.FP_FlujoTransformadoresP = [this.FP_FlujoTransformadoresP; zeros(1,m)];
                this.FP_FlujoTransformadoresQ = [this.FP_FlujoTransformadoresQ; zeros(1,m)];
                this.FP_TapTransformadores = [this.FP_TapTransformadores; zeros(1,m)];
            end
        end

        function agrega_bateria(this, bateria)
            if this.ContenedoresInicializadosOPF && this.NivelDetalleResultadosOPF > 1
                [n, m] = size(this.BateriasP);
                if bateria.entrega_id() ~= n+1
                    error = MException('cResultadoEvaluacionSEP:agrega_bateria','Id de la bateria no coincide con dimensiones de las matrices');
                    throw(error)
                end
                this.BateriasP = [this.BateriasP; zeros(1,m)];
                this.BateriasE = [this.BateriasE; zeros(1,m)];
            end
            if this.ContenedoresInicializadosFP && this.NivelDetalleResultadosFP > 1
                [n, m] = size(this.FP_BateriasP);
                if bateria.entrega_id() ~= n+1
                    error = MException('cResultadoEvaluacionSEP:agrega_bateria','Id de la bateria no coincide con dimensiones de las matrices');
                    throw(error)
                end
                this.FP_BateriasP = [this.FP_BateriasP; zeros(1,m)];
                this.FP_BateriasQ = [this.FP_BateriasQ; zeros(1,m)];
            end
        end
        
        function agrega_generador(this, generador)
            if this.ContenedoresInicializadosOPF && this.NivelDetalleResultadosOPF > 1
                [n, m] = size(this.GeneradoresP);
                if generador.entrega_id() ~= n+1
                    error = MException('cResultadoEvaluacionSEP:agrega_generador','Id del generador coincide con dimensiones de las matrices');
                    throw(error)
                end
                this.GeneradoresP = [this.GeneradoresP; zeros(1,m)];
                if ~isempty(this.RecorteRES)
                    this.RecorteRES = [this.RecorteRES; zeros(1,m)];
                end
                if ~isempty(this.UCGeneradores)
                    this.UCGeneradores = [this.UCGeneradores; zeros(1,m)];
                end
            end
            if this.ContenedoresInicializadosFP && this.NivelDetalleResultadosFP > 1
                [n, m] = size(this.FP_GeneradoresP);
                if generador.entrega_id() ~= n+1
                    error = MException('cResultadoEvaluacionSEP:agrega_generador','Id del generador no coincide con dimensiones de las matrices');
                    throw(error)
                end
                this.FP_GeneradoresP = [this.FP_GeneradoresP; zeros(1,m)];
                this.FP_GeneradoresQ = [this.FP_GeneradoresQ; zeros(1,m)];
            end
        end

        function borra_evaluacion_actual(this)
            this.ExisteResultadoOPF = 0;
            this.ExisteResultadoFP = 0;
            
            if this.ContenedoresInicializadosOPF
                this.CostoENS = 0*this.CostoENS;
                this.CostoRecorteRES = 0*this.CostoRecorteRES;
                this.CostoGeneracion = 0*this.CostoGeneracion;
                this.LineasFlujoMaximo = [];
                this.TrafosFlujoMaximo = [];
                this.LineasPocoUso = [];
                this.TrafosPocoUso = [];
                this.BateriasUsoMaximo = [];
                this.BateriasPocoUso = [];

                this.ConsumosConENS = [];
                this.GeneradoresRecorteRES = [];
                this.SEConRecorteRES = [];
                this.SEConENS = [];
                if this.NivelDetalleResultadosOPF > 0
                    this.GeneradoresP = 0*this.GeneradoresP;
                    this.ConsumosP = 0*this.ConsumosP;
                    this.UCGeneradores = 0*this.UCGeneradores;
                    
                    if this.NivelDetalleResultadosOPF > 1
                        this.FlujoLineasP = 0*this.FlujoLineasP;                
                        this.FlujoTransformadoresP = 0*this.FlujoTransformadoresP;
                        this.AnguloSubestaciones = 0*this.AnguloSubestaciones;
                        this.BateriasP = 0*this.BateriasP;
                        this.BateriasE = 0*this.BateriasE;
                        this.ENS = 0*this.ENS;
                        this.RecorteRES = 0*this.RecorteRES;
                        this.EmbalsesVol = 0*this.EmbalsesVol;
                        this.EmbalsesVert = 0*this.EmbalsesVert;
                        this.EmbalsesFilt = 0*this.EmbalsesFilt;
                    end
                end
            end
            if this.ContenedoresInicializadosFP
                this.FP_LineasFlujoMaximo = [];
                this.FP_TrafosFlujoMaximo = [];
                this.FP_LineasFlujoMaximoN1 = [];
                this.FP_TrafosFlujoMaximoN1 = [];
                this.FP_BusesVMaxFueraDeLimites = [];
                this.FP_BusesVMinFueraDeLimites = [];
                this.FP_Flag = [];
                if this.NivelDetalleResultadosFP > 0
                    % por ahora nada
            
                    if this.NivelDetalleResultadosFP > 1            
                        this.FP_Flag = 0*this.FP_Flag;
                        this.FP_FlujoLineasP = 0*this.FP_FlujoLineasP;
                        this.FP_FlujoLineasQ = 0*this.FP_FlujoLineasQ;
                        this.FP_FlujoTransformadoresP = 0*this.FP_FlujoTransformadoresP;
                        this.FP_FlujoTransformadoresQ = 0*this.FP_FlujoTransformadoresQ;
                        this.FP_GeneradoresP = 0*this.FP_GeneradoresP;
                        this.FP_GeneradoresQ = 0*this.FP_GeneradoresQ;
                        this.FP_TapTransformadores = 0*this.FP_TapTransformadores;
                        this.FP_TapCondensadores = 0*this.FP_TapCondensadores;
                        this.FP_TapReactores = 0*this.FP_TapReactores;

                        this.FP_BateriasP = 0*this.FP_BateriasP;
                        this.FP_BateriasQ = 0*this.FP_BateriasQ;

                        this.FP_ConsumosP = 0*this.FP_ConsumosP;
                        this.FP_ConsumosQ = 0*this.FP_ConsumosQ;

                        this.FP_AnguloSubestaciones = 0*this.FP_AnguloSubestaciones;
                        this.FP_VoltajeSubestaciones = 0*this.FP_VoltajeSubestaciones;
                        this.FP_Perdidas = 0*this.FP_Perdidas;
                    end
                end
            end
        end

        function exporta_resultados_formato_excel(this)
            prot = cProtocolo.getInstance();
            
            %EMBALSES
            %%agua_turbinada_por_mwh = 1000/(eficiencia_turbina * 9.81 * altura_caida * eficiencia_embalse);
            [n_emb, ~] = size(this.EmbalsesVol);
            nombre_embalses = cell(n_emb,0);
            eficiencia_embalses = cell(n_emb,0);
            altura_embalses = cell(n_emb,0);
            turbina_descarga = cell(n_emb,0);
            eficiencia_turbinades = cell(n_emb,0);
            coeficiente_caudal = cell(n_emb,0);
            embalses = this.pSEP.entrega_embalses();
            for i = 1:n_emb
                nombre_embalses{i} = embalses(i).entrega_nombre();
                eficiencia_embalses{i} = embalses(i).entrega_eficiencia();
                altura_embalses{i} = embalses(i).entrega_altura_caida();
                turbina_descarga{i} = embalses(1).entrega_turbinas_descarga();
                eficiencia_turbinades{i} = turbina_descarga{i}.entrega_eficiencia();
                coeficiente_caudal{i} = 1000/(eficiencia_turbinades{i}*9.81*altura_embalses{i}*altura_embalses{i});
            end
            
            %GENERADORES
            [n_gen, ~] = size(this.GeneradoresP);
            nombre_generadores = cell(n_gen,0);
            generadores = this.pSEP.entrega_generadores();
            for i = 1:n_gen
                nombre_generadores{i} = generadores(i).entrega_nombre();
            end
            
            %CONSUMOS
            [n_cons, ~] = size(this.ConsumosP);
            nombre_consumos = cell(n_cons,0);
            cargas = this.pSEP.entrega_consumos();
            for i = 1:n_cons
                nombre_consumos{i} = cargas(i).entrega_nombre();
            end  
            
            %BESS
            [n_BESS, ~] = size(this.BateriasP);
            nombre_BESS = cell(n_BESS,0);
            BESS = this.pSEP.entrega_baterias();
            for i = 1:n_BESS
                Nombre_BESS{i} = BESS(i).entrega_nombre();
            end  
            
            %agua_turbinada_por_mwh = 1000/(eficiencia_turbina * 9.81 * altura_caida * eficiencia_embalse);
            %imprime_matriz_formato_excel
            prot.imprime_matriz_formato_excel(this.EmbalsesVol, nombre_embalses, 'Volumenes de embalses', 'res_opf_balance_hidraulico', 'Volumenes');
            prot.imprime_matriz_formato_excel(this.EmbalsesVert, nombre_embalses, 'Vertimiento de embalses', 'res_opf_balance_hidraulico', 'Vertimientos');
            prot.imprime_matriz_formato_excel(this.EmbalsesFilt, nombre_embalses, 'Filtracion de embalses', 'res_opf_balance_hidraulico', 'Filtraciones');
            prot.imprime_matriz_formato_excel(this.GeneradoresP, nombre_generadores, 'Potencia Generadores', 'res_opf_balance_hidraulico', 'Potencia generada Gens');
            prot.imprime_matriz_formato_excel(this.BateriasP, Nombre_BESS, 'Potencia BESS', 'res_opf_balance_hidraulico', 'Potencia generada BESS');
            prot.imprime_matriz_formato_excel(this.BateriasE, Nombre_BESS, 'Energia BESS', 'res_opf_balance_hidraulico', 'Energía Almacenada');
            prot.imprime_matriz_formato_excel(this.ConsumosP, nombre_consumos, 'Potencia Demandada', 'res_opf_balance_hidraulico', 'Consumos');
            %prot.imprime_matriz_formato_excel(coeficiente_caudal{i}, coeficiente_caual, 'Coef. caudal', 'res_opf_balance_hidraulico', 'Coef. caudal'); 
        end		
    end
end