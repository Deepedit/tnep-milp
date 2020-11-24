classdef (Sealed) cProtocolo < handle

    properties
        nombre_archivo = './output/protocolo.dat';
        docID
        caso_estudio = -1
    end
    
    methods (Access = private)
        function this = cProtocolo(nombre_archivo)
            this.nombre_archivo = nombre_archivo;           
            this.docID = fopen(this.nombre_archivo, 'w');
            %fprintf(this.docID, 'Comienzo del protocolo\n');
        end
    end
    
    methods (Static)
        function singleObj = getInstance(varargin)
            if nargin > 0
                nombre_archivo = varargin{1};
            else
                nombre_archivo = './output/protocolo.dat';
            end
            persistent localObj
            if isempty(localObj) || ~isvalid(localObj)
                localObj = cProtocolo(nombre_archivo);
            end
            singleObj = localObj;
        end
    end
    
    methods
        function abre_nuevo_archivo(this, nombre_archivo)
            fclose(this.docID);
            this.nombre_archivo = nombre_archivo;
            this.docID = fopen(this.nombre_archivo, 'w');            
        end
        
        function inserta_caso_estudio(this, caso)
            this.caso_estudio = caso;
        end
        
        function cierra_archivo(this)
            fclose(this.docID);
        end
            
        function imprime_matriz(this, matriz, varargin)
            if nargin > 2
                titulo = varargin{1};
            else
                titulo = 'matriz sin título';
            end
            
            [n,m] = size(matriz);
            largo = num2str(n);
            
            text = cell(n+1,1);
            % título
            text{1} = sprintf('%-4s %-3s', ' ', ' ');
            for j = 1:m
                txt = sprintf('%-6s',num2str(j));
                text{1} = [text{1}  txt];
            end
           
            for i = 1:n
                text{i+1} = sprintf('%-4s %-3s', num2str(i), '|');
                for j = 1:m
                    txt = sprintf('%-6s',num2str(round(matriz(i,j),2)));
                    text{i+1} = [text{i+1} txt];
                end
            end
            
            fprintf(this.docID, strcat(titulo, '\n'));
            fprintf(this.docID, strcat(text{1},'\n'));
            segundo = sprintf('%-4s %-3s', ' ', '___');
            for aux = 1:m
                txt = sprintf('%-6s', '______');
            	segundo = [segundo txt];
            end
            fprintf(this.docID, strcat(segundo,'\n'));
            for i = 2:length(text)
                fprintf(this.docID, strcat(text{i},'\n'));
            end
            fprintf(this.docID, '\n');
        end
        
        function docid = entrega_doc_id(this)
            docid = this.docID;
        end
        
        function imprime_valor(this, val, nombre)
            fprintf(this.docID, strcat(nombre, ':', num2str(val), '\n\n'));
        end
        
        function imprime_vector(this, vector, varargin)
            if nargin > 2
                titulo = varargin{1};
            else
                titulo = 'Vector sin título';
            end
            
            n= length(vector);
            text = cell(n+1,1);
            % título
            text{1} = strcat(titulo,':');
           
            for i = 1:n
                text{i+1} = sprintf('%4s %3s', num2str(i), '|', num2str(vector(i)));
            end
            
            for i = 1:length(text)
                fprintf(this.docID, strcat(text{i},'\n'));
            end
            fprintf(this.docID, '\n');
        end

        function imprime_vector_texto(this, vector, varargin)
            if nargin > 2
                titulo = varargin{1};
            else
                titulo = 'Vector sin título';
            end
            fprintf(this.docID, strcat(titulo,'\n'));
            
            for i = 1:length(vector)
                fprintf(this.docID, strcat(vector{i},'\n'));
            end
            fprintf(this.docID, '\n');
        end
        
        function imprime_texto(this,texto)
            fprintf(this.docID, strcat(texto, '\n'));
        end
        
        function imprime_matriz_formato_excel(this, matriz, headers, nombre_matriz, nombre_archivo, nombre_hoja)
            fprintf(this.docID, strcat('Imprime matriz', nombre_matriz, ' a excel', '\n'));
            filename = ['./output/' nombre_archivo '.xlsx'];
            xlRange = 'A1';
            xlswrite(filename, nombre_matriz, nombre_hoja, xlRange);
            
            xlRange = 'A2';
            xlswrite(filename, headers, nombre_hoja, xlRange);
            
            matriz=matriz';
            xlRange = 'A3';
            xlswrite(filename, matriz, nombre_hoja, xlRange);
        end
        
    end
end