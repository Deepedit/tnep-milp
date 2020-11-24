function mpc = case7_TNEP_ERNC
% CASE6 Garver six-bus example in PLAS format for TNEP
% AC-Data from "Power system transmission network expansion planning using AC model

aumento_anual = 2.4;
%aumento_anual = 1.2;
%-----  Power Flow Data  -----%
% system MVA base
mpc.baseMVA = 100;
mpc.PuntosOperacion = [1 974; 2 974; 3 974; 4 973; 5 973; 6 973; 7 973; 8 973; 9 973];
mpc.PerfilERNC = [1 0.7 0.4 0.9 0.7 0.4 0.5 0.3 0.2;
                  1 0.5 0 0.5 0.3 0 0.2 0.1 0];
mpc.PerfilDemanda = [1 1 1 0.7 0.7 0.7 0.4 0.4 0.4];

% Parametros
% [ROW USD/Ha	Factor planificación proyectos		 
mpc.Costos = [
%5000	1.05;
0	1;
%30000	-; --> alternativa para costos de ROW 
];

%% bus data
%	bus_i	baseKV conectado (0/1) PosX	   PosY
mpc.Buses = [
	1	110 1	2000	2000;
	2   110 1	1250	1250;
	3   110 1	500		1500;
	4   110 1	1500	250	;
	5   110 1	750		2200;
	6   110 0	750		500;
    7   110 0   2000    2200
];

%              1   2    3         4         5          6
% Consumos = [id, bus, p0 (MW), q0 (MW), dep_volt, NLS costs USD/MWh %aumento anual]
mpc.Consumos = [
	1	1   80		16		0	10000 	aumento_anual;
	2	2   240		48		0	10000 	aumento_anual;
	3	3   40		8		0	10000 	aumento_anual;
	4	4   160		32		0	10000 	aumento_anual;
	5	5   240		48		0	10000 	aumento_anual;
];

    %              1    2  3    4     5     6     7     8      9      10      11   12       13 
    % Generador: [id, bus, P0, Q0, Pmax, Pmin, Qmax, Qmin, Vobj pu, status, Slack, USD/Mwh %aumento anual capacidad]
mpc.Generadores = [
% [id, bus, P0, Q0, Pmax, Pmin, Qmax, Qmin, Vobj pu, status, Slack, USD/MWh %aumento anual capacidad]
	1	1	150	0	150		0	48		10		1		1		1	60 		0;
	2	3	350	0	350		0	101		10		1		1		0	65 		0
];

mpc.GeneradoresERNC = [
% [id, bus, Pmax, Pmin, Qmax, Qmin, Vobj pu, status, Slack, USD/MWh  perfil inyeccion]
    3   6   0       0    0      0    1         0       0       0     1;
    4   7   0       0    0      0    1         0       0       0     2
];

% Conductores = [no, tipo (1: convencional, 2: HTLS), r (Ohm/km), x (Ohm/km), G (Ohm/km) C (Ohm/km), Imax (kA) Cfijo cond (mio. USD)	Cvar. conductor (mio. USD/MVA/km) Cvar. torre (mio. USD/MVA/km) vida_util Vnom (kV) ROW (Ha/km) Expansion
% Expansión indica que el conductor se puede utilizar para crear un nuevo corredor.
mpc.Conductores = [
%[  1,  2,  3, 			4			5			6			7			8				9				10				11			12		13			14 				15 expansion
%[no, tipo, r (Ohm/km), x (Ohm/km), G (Ohm/km), C (Ohm/km), Imax (kA), 	Cfijo cond,		Cvar. cond,		Cvar. torre, 	vida_util,	Vnom, 	ROW [Ha/km],diametro (mm),	1/0
	1	1	0.075625	0.75625		0			0			0.5249  	0				0.00072 		0.00168		 	40			110		3.3528		18.3			1;
	2	2	0.0253		0.5925		0			0			1.255   	0				0.0012	 		0.00168		 	40			110		3.3528		18.2			0;
	3	1	0.075625	0.75625		0			0			1.018	  	0				0.00042 		0.00098		 	40			220		4.2672		39.2			1;	
];

	% Transformadores = [no, Sr (MVA)	AT		BT		Sr		x (Ohm) Cfijo (mio USD)   Cvar. (mio. USD/MVA) vida_util
	%Datos de entrada: se asume x serie = uk*v^2/Sr, uk = 0.1
mpc.TipoTransformadores = [
%[no, 	Sr,	AT,		BT,		X serie(Ohm),	Cfijo (mio USD),   Cvar. (mio. USD/MVA), vida_util, expansion
%	1	2	3		4		5				6					7					8			9
%	1	50	220		110		96.8			0					0.00725				40			1;
%	2	100	220		110		48.4			0					0.00725				40			1;
	3	150	220		110		32.3			0					0.00725				40			1;
    4   200 220     110     24.2            0                   0.00725             40			1;
];
	% Compensacion serie = [no, Porcentaje compensacion, costos fijos (mio. USD), costos variables (mio. USD/MVA)]
mpc.CompensacionSerie = [
%[no, %comp, cfijo, cvar]
	1	0.25	0	0.031;
	2	0.5		0	0.031;
];
%[no, Vfinal 	costos fijos (mio. USD), costos variables (mio. USD/MVA)]
mpc.VoltageUprating = [
%[no, Vfinal 	c. fijos, cvar]
	1	220		1.5				0
];
	% Corredores = [bus1, bus2, largo (km), n max voltage uprating	series compensation	reconductoring]
	% en teoría, datos finales (VUR, SC y Reconductoring) no son necesarios, a menos que se quiera restringir (aún más) los casos de estudio
nmax = 3;	
mpc.Corredores = [
% 	1	2	3		4		5	6	7	
    1   2   64.0	nmax	1	0	1;
    1   4   96.0 	nmax	1	1	0;
    1   5   32.0 	nmax	1	0	1;
    2   3   32.0 	nmax	1	0	1;
    2   4   64.0 	nmax	1	0	1;
    2   6   48.0 	nmax	1	0	1;
    3   5   32.0 	nmax	1	0	1;
    3   6   76.8 	nmax	1	0	1;
    4   6   48.0 	nmax	1	0	1;
    1   7   150     nmax    1   1   0;
    5   7   100     nmax    1   1   0
];

	% a partir datos de conductor. En caso de haber, sobre-escriben datos anteriores
    % Lineas: [bus1, bus2, rpu, xpu, bpu, sr, status CI MM.USD  tipo conductor]
	% OJO: debido a los distintos anios de construcción, si hay líneas paralelas existentes en un mismo corredor, 
	% estas deben ser agregadas en forma separada
mpc.Lineas = [
%[bus1, bus2, rpu, 	xpu, 	bpu, 	sr, status, C (MM.USD) no_conductor  anio construccion]
%	1	2	3		4		5		6		7	8			9	10
	1 	2 	0.040 	0.400 	0.00 	100 	1 	7.7232		1 	1990;
	1 	3 	0.038 	0.380 	0.00 	100 	0 	7.33704		1 	0;
	1 	4 	0.060 	0.600 	0.00 	80 		1 	11.5848		1 	1990;
	1 	5 	0.020 	0.200 	0.00 	100 	1 	3.8616		1 	1990;
	1 	6 	0.068 	0.680 	0.00 	70 		0 	13.12944	1 	0;
	2 	3 	0.020 	0.200 	0.00 	100 	1 	3.8616		1 	1990;
	2 	4 	0.040 	0.400 	0.00 	100 	1 	7.7232		1 	1990;
	2 	5 	0.031 	0.310 	0.00 	100 	0 	5.98548		1 	0 ;
	2 	6 	0.030 	0.300 	0.00 	100 	0 	5.7924		1 	0 ;
	3 	4 	0.059 	0.590 	0.00 	82	 	0 	11.39172	1 	0 ;
	3 	5 	0.020 	0.200 	0.00 	100 	1 	3.8616		1 	1990;
	3 	6 	0.048 	0.480 	0.00 	100 	0 	9.26784		1 	0;
	4 	5 	0.063 	0.630 	0.00 	75 		0 	12.16404	1 	0;
	4 	6 	0.030 	0.300 	0.00 	100 	0 	5.79204		1 	0;
	5 	6 	0.061 	0.610 	0.00 	78 		0 	11.77788	1 	0;
];

mpc.Transformadores = [
%[bus1, bus2, xpu, 	sr, C (MM.USD) tipo_trafo  año construccion  ]
% 1		2		3	4	5			6			7				
];