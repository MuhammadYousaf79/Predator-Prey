function TA_Simulation
clear;
clc;
%format short;
global MVA_Base Pref Vref YBus Pc Qc PL_ss QL_ss V_mag_ss V_angle_ss IG_mag_ss IG_angle_ss ws ...
    xd xq xd_prime xq_prime xd_double_prime xq_double_prime xl Rs Tdo_prime Tqo_prime H Kd KA TA Ksg Tsg R Kstab TW Tstab1 Tstab2...
    Tstab3 Tstab4 Nstate Nmachine Nsym f g Ts X_equilibrium ZIP Noise FO_bus FO_freq FO_mag FO_phase ...
    FO_load_bus FO_load_freq FO_load_mag FO_load_phase;
%---------------------Data-------------------------------------------------
MVA_Base=100;
[~,~,YBus,Pc,Qc,PL_ss,QL_ss,ZIP,V_mag_ss,V_angle_ss,IG_mag_ss,IG_angle_ss,ws,xd,xq,xd_prime,...
    xq_prime,xd_double_prime,xq_double_prime,xl,Rs,Tdo_prime,Tqo_prime,H,Kd,KA,TA,Ksg,Tsg,R,Kstab,TW,Tstab1,Tstab2,Tstab3,Tstab4]=Load_Kundur_System(MVA_Base);
%---------------------Initializations--------------------------------------
Nstate=9;                               %---Two axis flux decay model of synchronous machines
Nmachine=size(xd,1);                    %---Four machines
Nsym=size(YBus,1);                      %---Eleven bus system
X=zeros(Nmachine*Nstate,1);             %---State vector
Y=zeros(Nsym*2,1);                      %---Power flow variables
f=zeros(size(X));                       %---Differential Equations
g=zeros(size(Y));                       %---Algebraic Equations
%---------------------Equilibrium Point------------------------------------
%options = optimoptions('fsolve','Display','iter','Algorithm','Levenberg-Marquardt');
options = optimoptions('fsolve','Display','none');
%   [theta,w,Eq,Ed ,Efd,Psg,PSS1,PSS2,PSS3,Vref,Pref]
X0=[[0.2  ,1,1 ,0.5,2  ,7  ,0   ,0   ,0   ,1.03,7   ]...
    [0.3  ,1,1 ,0.5,2  ,7  ,0   ,0   ,0   ,1.01,7   ]...
    [0.5  ,1,1 ,0.5,2  ,7  ,0   ,0   ,0   ,1.03,7   ]...
    [0.7  ,1,1 ,0.5,2  ,7  ,0   ,0   ,0   ,1.01,7   ]];     %---Typical values from experience
X_equilibrium=fsolve(@f_initialization,X0,options)';
Vref=X_equilibrium(Nstate+1:Nstate+2:end,:);
Pref=X_equilibrium(Nstate+2:Nstate+2:end,:);

X_equilibrium(Nmachine*(Nstate+2),:)=[];
X_equilibrium(Nstate+1:Nstate+2:end,:)=[];
X_equilibrium(Nstate+1:Nstate+1:end,:)=[];
Y_equilibrium=[V_mag_ss;V_angle_ss];

Initialization_results=[X_equilibrium(0*Nstate+1:1*Nstate),...
                        X_equilibrium(1*Nstate+1:2*Nstate),...
                        X_equilibrium(2*Nstate+1:3*Nstate),...
                        X_equilibrium(3*Nstate+1:4*Nstate)];
display(Initialization_results);

%---------------------Transient Stability----------------------------------
Ts        = 1/30;
Z0        = [X_equilibrium;Y_equilibrium];
tspan     = (0:Ts:60*5);

%--- Noise Injection in Load ---
            % -------P------ || -------Q------  -Bus-
            %   Z    I    P       Z    I    P
Noise      = [0.00 0.00 0.00    0.00 0.00 0.00  % 1
              0.00 0.00 0.00    0.00 0.00 0.00  % 2
              0.00 0.00 0.00    0.00 0.00 0.00  % 3
              0.00 0.00 0.00    0.00 0.00 0.00  % 4
              0.00 0.00 0.00    0.00 0.00 0.00  % 5
              0.00 0.00 0.00    0.00 0.00 0.00  % 6
              0.00 0.00 0.00    0.00 0.00 0.00  % 7
              0.00 0.00 0.00    0.00 0.00 0.00  % 8
              0.00 0.00 0.00    0.00 0.00 0.00  % 9
              0.00 0.00 0.00    0.00 0.00 0.00  % 10
              0.00 0.00 0.00    0.00 0.00 0.00  % 11
              ].*randn(size(ZIP,1),size(ZIP,2),size(tspan,2));
%--- ----------------------- ---

%--- FO injection in Generator ---
FO_bus   = [1       2       3       4      ];
FO_freq  = [0.6077  0.6077  0.6077  0.6077 ];
FO_mag   = [0       0       0       0      ];
FO_phase = [0       0       0       0      ];
%--- ------------------------- ---

%--- FO injection in Load ---
FO_load_bus   = [7       9       ];
FO_load_freq  = [0.6077  0.6077      % P
                 0.6077  0.6077  ];  % Q
% FO_load_mag   = [0.0967  0.01767   % P
%                  0.01    0.01    ];% Q
FO_load_mag   = [0.00    0.00        % P
                 0.00    0.00    ];  % Q
FO_load_phase = [0       0           % P
                 0       0       ];  % Q
%--- -------------------- ---

M          = eye(Nmachine*Nstate+2*Nsym);
for i=Nmachine*Nstate+1:Nmachine*Nstate+2*Nsym
    M(i,i)=0;
end
options  = odeset('Mass',M,'RelTol',1e-9,'AbsTol',1e-12);
[tout,h] = ode15s(@daefun,tspan,Z0,options);

%---------------------Print Results----------------------------------------
figure(1);
Vm=pol2rect(h(:,Nstate*Nmachine+1:Nstate*Nmachine+11),h(:,Nstate*Nmachine+12:Nstate*Nmachine+22));
I78=-(Vm(:,7) - Vm(:,8)).*YBus(7,8);
P78=real(Vm(:,7).*conj(I78(:,1))*MVA_Base);
plot(tout,P78(:,1));
title('Forced Oscillation Injection');
grid;xlabel('Time (sec)');ylabel('Tie Line Flow (MW)');
%ylim([385 410]);
legend('Tie Line Flow (7-9)');
 
figure(2);
P=zeros(size(tout,1),Nsym);
Q=zeros(size(tout,1),Nsym);
V_mag=h(:,Nstate*Nmachine+1:Nstate*Nmachine+Nsym);V_angle=h(:,Nstate*Nmachine+Nsym+1:end);
for i=1:Nsym
    for j=1:Nsym
        P(:,i)=P(:,i)+V_mag(:,i).*V_mag(:,j).*abs(YBus(i,j)).*cos(V_angle(:,i)-V_angle(:,j)-angle(YBus(i,j)));
        Q(:,i)=Q(:,i)+V_mag(:,i).*V_mag(:,j).*abs(YBus(i,j)).*sin(V_angle(:,i)-V_angle(:,j)-angle(YBus(i,j)));
    end
end
plot(tout,P(:,1:4)*MVA_Base);grid;xlabel('Time (sec)');ylabel('Generator Power(MW)');

figure(3)
Pm = h(:,[(1-1)*Nstate+6,(2-1)*Nstate+6,(3-1)*Nstate+6,(4-1)*Nstate+6]);
plot(tout,Pm);grid;xlabel('Time (sec)');ylabel('Generator Torque(MW)');
%--------------------Save Results------------------------------------------
%assignin('base','X_equilibrium',X_equilibrium);
%assignin('base','h',h);assignin('base','tout',tout);

%--------------------Post Simulation Analysis------------------------------
%---Data for Estimation---
save("Estimation_Data","tspan","V_mag","V_angle","P","Q");
save("Equilibrium_Values","X_equilibrium","V_mag_ss","V_angle_ss","Pc","Qc");

end

function h = daefun(t,Z)
global Pref Vref YBus PL_ss QL_ss V_mag_ss ws ...
    xd xq xd_prime xq_prime xd_double_prime xq_double_prime xl Rs Tdo_prime Tqo_prime H Kd KA TA Ksg Tsg R Kstab TW Tstab1 Tstab2 ...
    Tstab3 Tstab4 Nstate Nmachine Nsym ZIP Noise Ts FO_bus FO_freq FO_mag FO_phase FO_load_bus FO_load_freq FO_load_mag FO_load_phase;

Vd=zeros(Nmachine,1);Vq=Vd;Id=Vd;Iq=Vd;Ig_mag=Iq;Pg=Ig_mag;Qg=Vd;Pe=Vd;
f=zeros(Nmachine*Nstate,1);g=zeros(2*Nsym,1);

X=Z(1:Nstate*Nmachine);Y=Z(Nstate*Nmachine+1:end);
V_mag=Y((1:Nsym));V_angle=Y((Nsym+1:end));

for i=1:Nmachine
    Vd(i,1)=Y(i)*sin(X(Nstate*(i-1)+1)-Y(Nsym+i));
    Vq(i,1)=Y(i)*cos(X(Nstate*(i-1)+1)-Y(Nsym+i));
    
    Id(i,1)=(X(Nstate*(i-1)+4)-Vd(i,1))*(Rs(i)/(Rs(i)^2+xd_prime(i)*xq_prime(i)))+(X(Nstate*(i-1)+3)-Vq(i,1))*(+xq_prime(i)/(Rs(i)^2+xd_prime(i)*xq_prime(i)));
    Iq(i,1)=(X(Nstate*(i-1)+3)-Vq(i,1))*(Rs(i)/(Rs(i)^2+xd_prime(i)*xq_prime(i)))+(X(Nstate*(i-1)+4)-Vd(i,1))*(-xd_prime(i)/(Rs(i)^2+xd_prime(i)*xq_prime(i)));
    Ig_mag(i,1)=sqrt(Id(i,1)^2+Iq(i,1)^2);
    
    Pg(i,1)=Vd(i)*Id(i)+Vq(i)*Iq(i);
    Qg(i,1)=Vq(i)*Id(i)-Vd(i)*Iq(i);
    Pe(i,1)=Pg(i)+Rs(i)*Ig_mag(i)^2;
end

for i=1:Nmachine
    f(Nstate*(i-1)+1,1)=ws*(X(Nstate*(i-1)+2)-1);
    f(Nstate*(i-1)+2,1)=1/(2*H(i))*(X(Nstate*(i-1)+6)-Pe(i)-Kd(i)*(X(Nstate*(i-1)+2)-1));
    f(Nstate*(i-1)+3,1)=1/Tdo_prime(i)*(-X(Nstate*(i-1)+3)-(xd(i)-xd_prime(i))*Id(i)+X(Nstate*(i-1)+5));
    %    f(Nstate*(i-1)+3,1)=1/Tdo_prime(i)*(-X(Nstate*(i-1)+3)-(xd(i)-xd_prime(i))*(Id(i)-(xd_prime(i)-xd_double_prime(i))/((xd_prime(i)-xl(i))^2)*((xd_prime(i)-xl(i))*Id(i)-X(Nstate*(i-1)+3)))+X(Nstate*(i-1)+5));
    f(Nstate*(i-1)+4,1)=1/Tqo_prime(i)*(-X(Nstate*(i-1)+4)+(xq(i)-xq_prime(i))*Iq(i));
    %    f(Nstate*(i-1)+4,1)=1/Tqo_prime(i)*(-X(Nstate*(i-1)+4)+(xq(i)-xq_prime(i))*(Iq(i)-(xq_prime(i)-xq_double_prime(i))/((xq_prime(i)-xl(i))^2)*((xq_prime(i)-xl(i))*Iq(i)+X(Nstate*(i-1)+4))));
    f(Nstate*(i-1)+5,1)=1/TA(i)*(-X(Nstate*(i-1)+5)+KA(i)*(Vref(i)-Y(i)-X(Nstate*(i-1)+9)));
    f(Nstate*(i-1)+6,1)=1/Tsg(i)*(-X(Nstate*(i-1)+6)+Ksg(i)*(Pref(i)+1/R(i)*(1-X(Nstate*(i-1)+2))+ismember(i,FO_bus)*sum(FO_mag(FO_bus==i))*cos(2*pi*sum(FO_freq(FO_bus==i))*t+sum(FO_phase(FO_bus==i))*pi/180)));
    f(Nstate*(i-1)+7,1)=1/TW(i)*(-X(Nstate*(i-1)+7)-Kstab(i)*TW(i)*f(Nstate*(i-1)+2));
    f(Nstate*(i-1)+8,1)=1/Tstab2(i)*(-X(Nstate*(i-1)+8)+X(Nstate*(i-1)+7)+Tstab1(i)*f(Nstate*(i-1)+7));
    f(Nstate*(i-1)+9,1)=1/Tstab4(i)*(-X(Nstate*(i-1)+9)+X(Nstate*(i-1)+8)+Tstab3(i)*f(Nstate*(i-1)+8));
end

PL_ZIP=ZIP(:,1:3)*diag([1+Noise(1,round(t/Ts+1)) 1+Noise(2,round(t/Ts+1)) 1+Noise(3,round(t/Ts+1))]);
QL_ZIP=ZIP(:,4:6)*diag([1+Noise(4,round(t/Ts+1)) 1+Noise(5,round(t/Ts+1)) 1+Noise(6,round(t/Ts+1))]);

PL=PL_ss.*(PL_ZIP(:,3)+PL_ZIP(:,2).*(Y((1:Nsym))./V_mag_ss)+PL_ZIP(:,1).*(Y((1:Nsym))./V_mag_ss).^2);
QL=QL_ss.*(QL_ZIP(:,3)+QL_ZIP(:,2).*(Y((1:Nsym))./V_mag_ss)+QL_ZIP(:,1).*(Y((1:Nsym))./V_mag_ss).^2);

for i=1:Nsym
    PL(i,1) = PL(i,1)+ismember(i,FO_load_bus)*sum(FO_load_mag(1,FO_load_bus==i))*sin(2*pi*sum(FO_load_freq(1,FO_load_bus==i))*t+sum(FO_load_phase(1,FO_load_bus==i))*pi/180);
    QL(i,1) = QL(i,1)+ismember(i,FO_load_bus)*sum(FO_load_mag(2,FO_load_bus==i))*sin(2*pi*sum(FO_load_freq(2,FO_load_bus==i))*t+sum(FO_load_phase(2,FO_load_bus==i))*pi/180);
end

PG=[Pg;zeros(Nsym-Nmachine,1)];
QG=[Qg;zeros(Nsym-Nmachine,1)];

P=zeros(Nsym,1);
Q=zeros(Nsym,1);

for i=1:Nsym
    for j=1:Nsym
        P(i,1)=P(i,1)+V_mag(i)*V_mag(j)*abs(YBus(i,j))*cos(V_angle(i)-V_angle(j)-angle(YBus(i,j)));
        Q(i,1)=Q(i,1)+V_mag(i)*V_mag(j)*abs(YBus(i,j))*sin(V_angle(i)-V_angle(j)-angle(YBus(i,j)));
    end
end

g(1:Nsym,1)=PG-PL-P;
g(Nsym+1:end,1)=QG-QL-Q;

h=[f;g];
end

function [IEEE_format_bus_data,IEEE_format_branch_data,YBus,Pc,Qc,PL_ss,QL_ss,ZIP, ...
    V_mag_ss,V_angle_ss,IG_mag_ss,IG_angle_ss,ws,xd,xq,xd_prime,xq_prime,xd_double_prime,xq_double_prime,xl,Rs, ...
    Tdo_prime,Tqo_prime,H,KD,KA,TA,Ksg,Tsg,R,Kstab,TW,Tstab1,Tstab2,Tstab3,Tstab4]=Load_Kundur_System(MVA_Base)
[IEEE_format_bus_data,IEEE_format_branch_data] = Load_Data('ieee11cdf - Bus.txt','ieee11cdf - Branch.txt');

%---Statics Data-----------------------------------------------------------
Power_flow_solution=load ('Power_Flow_Solution.mat');
YBus=Power_flow_solution.Y;
V_mag_ss=Power_flow_solution.V;
V_angle_ss=Power_flow_solution.theta;
PG_ss=Power_flow_solution.PG;Pc=PG_ss;
QG_ss=Power_flow_solution.QG;Qc=QG_ss;
PL_ss=Power_flow_solution.PL;
QL_ss=Power_flow_solution.QL;
IG_mag_ss=abs(conj((PG_ss+1j*QG_ss)./(V_mag_ss.*(cos(V_angle_ss)+1j*sin(V_angle_ss)))));
IG_angle_ss=angle(conj((PG_ss+1j*QG_ss)./(V_mag_ss.*(cos(V_angle_ss)+1j*sin(V_angle_ss)))));

%---Dynamics DAta----------------------------------------------------------
Nmachine=4;
ws=2*pi*60;

%---Synchronous Machines---------------------------------------------------
H= [6.5;6.5;6.175;6.175]*900/MVA_Base;
KD=0*ones(Nmachine,1)*900/MVA_Base;

xd=1.8*ones(Nmachine,1)*MVA_Base/900;
xq=1.7*ones(Nmachine,1)*MVA_Base/900;
xd_prime=0.3*ones(Nmachine,1)*MVA_Base/900;
xq_prime=0.55*ones(Nmachine,1)*MVA_Base/900;
xd_double_prime=0.25*ones(Nmachine,1)*MVA_Base/900;
xq_double_prime=0.25*ones(Nmachine,1)*MVA_Base/900;
xl=0.2*ones(Nmachine,1)*MVA_Base/900;
Rs=0.0025*ones(Nmachine,1)*MVA_Base/900;
Tdo_prime=8.0*ones(Nmachine,1);
Tqo_prime=0.4*ones(Nmachine,1);

%---Exitor-----------------------------------------------------------------
KA= [200 200 200 200]';
TA=0.01*ones(Nmachine,1);

%---Governer---------------------------------------------------------------
Ksg=10*[1 1 1 1]';
Tsg=0.01*[100 100 100 100]';
R=[0.05 0.05 0.05 0.05]';

%---Power System Stabilizers-----------------------------------------------
Kstab = 3.5*[1 1 1 1];
TW=[10 10 10 10];
Tstab1=[.02 .02 .02 .02];
Tstab2=[.05 .05 .05 .05];
Tstab3=2*[3 3 3 3];
Tstab4=[5.4 5.4 5.4 5.4];

% Tstab3=[15 3 3 3];
% Tstab4=[3 4.0 5.4 5.4];

%---Loads------------------------------------------------------------------
                       % P+Q
ZIP=zeros(size(PL_ss,1),3+3);
          % ----P---- ||| ----Q----
          % Z   I   P     Z   I   P
ZIP(7,:)= [ 0   0   1    0   0    1];
ZIP(9,:)= [ 0   0   1    0   0    1];
end

function f=f_initialization(X)
global Pc Qc V_mag_ss V_angle_ss IG_mag_ss IG_angle_ss ws ...
    xd xq xd_prime xq_prime xd_double_prime xq_double_prime xl Rs Tdo_prime Tqo_prime H Kd KA TA Ksg Tsg R Kstab TW Tstab1 Tstab2 ...
    Tstab3 Tstab4 Nstate Nmachine;
Nunknowns=Nstate+2;
Vd=zeros(Nmachine,1);Vq=Vd;Id=Vd;Iq=Vd;Pg=IG_mag_ss;Qg=Vd;Pe=Vd;
f=zeros(Nunknowns*Nmachine,1);

for i=1:Nmachine
    Vd(i,1)=V_mag_ss(i)*sin(X(Nunknowns*(i-1)+1)-V_angle_ss(i));
    Vq(i,1)=V_mag_ss(i)*cos(X(Nunknowns*(i-1)+1)-V_angle_ss(i));
    
    Id(i,1)=IG_mag_ss(i)*sin(X(Nunknowns*(i-1)+1)-IG_angle_ss(i));
    Iq(i,1)=IG_mag_ss(i)*cos(X(Nunknowns*(i-1)+1)-IG_angle_ss(i));
    
    Pg(i,1)=Pc(i);
    Qg(i,1)=Qc(i);
    Pe(i,1)=Pg(i)+Rs(i)*IG_mag_ss(i)^2;
    
    f(Nunknowns*(i-1)+1,1)=ws*(X(Nunknowns*(i-1)+2)-1);
    f(Nunknowns*(i-1)+2,1)=1/(2*H(i))*(X(Nunknowns*(i-1)+6)-Pe(i)-Kd(i)*(X(Nunknowns*(i-1)+2)-1));
    f(Nunknowns*(i-1)+3,1)=1/Tdo_prime(i)*(-X(Nunknowns*(i-1)+3)-(xd(i)-xd_prime(i))*Id(i)+X(Nunknowns*(i-1)+5));
    %    f(Nunknowns*(i-1)+3,1)=1/Tdo_prime(i)*(-X(Nunknowns*(i-1)+3)-(xd(i)-xd_prime(i))*(Id(i)-(xd_prime(i)-xd_double_prime(i))/((xd_prime(i)-xl(i))^2)*((xd_prime(i)-xl(i))*Id(i)-X(Nunknowns*(i-1)+3)))+X(Nunknowns*(i-1)+5));
    f(Nunknowns*(i-1)+4,1)=1/Tqo_prime(i)*(-X(Nunknowns*(i-1)+4)+(xq(i)-xq_prime(i))*Iq(i));
    %    f(Nunknowns*(i-1)+4,1)=1/Tqo_prime(i)*(-X(Nunknowns*(i-1)+4)+(xq(i)-xq_prime(i))*(Iq(i)-(xq_prime(i)-xq_double_prime(i))/((xq_prime(i)-xl(i))^2)*((xq_prime(i)-xl(i))*Iq(i)+X(Nunknowns*(i-1)+4))));
    f(Nunknowns*(i-1)+5,1)=1/TA(i)*(-X(Nunknowns*(i-1)+5)+KA(i)*(X(Nunknowns*(i-1)+Nstate+1)-V_mag_ss(i)-X(Nunknowns*(i-1)+8)));    %
    f(Nunknowns*(i-1)+6,1)=1/Tsg(i)*(-X(Nunknowns*(i-1)+6)+Ksg(i)*(X(Nunknowns*(i-1)+Nstate+2)+1/R(i)*(1-X(Nunknowns*(i-1)+2))));
    f(Nunknowns*(i-1)+7,1)=1/TW(i)*(-X(Nunknowns*(i-1)+7)-Kstab(i)*TW(i)*f(Nunknowns*(i-1)+2));
    f(Nunknowns*(i-1)+8,1)=1/Tstab2(i)*(-X(Nunknowns*(i-1)+8)+X(Nunknowns*(i-1)+7)+Tstab1(i)*f(Nunknowns*(i-1)+7));
    f(Nunknowns*(i-1)+9,1)=1/Tstab4(i)*(-X(Nunknowns*(i-1)+9)+X(Nunknowns*(i-1)+8)+Tstab3(i)*f(Nunknowns*(i-1)+8));
end

for i=1:Nmachine
    f(Nunknowns*(i-1)+Nstate+1,1)=-X(Nunknowns*(i-1)+4)+Vd(i)+Rs(i)*Id(i)-xq_prime(i)*Iq(i);
    f(Nunknowns*(i-1)+Nstate+2,1)=-X(Nunknowns*(i-1)+3)+Vq(i)+Rs(i)*Iq(i)+xd_prime(i)*Id(i);
end

end

function [IEEE_format_bus_data,IEEE_format_branch_data] = Load_Data(IEEE_format_bus_file, IEEE_format_branch_file)
IEEE_format_bus_data = (fscanf(fopen(IEEE_format_bus_file,'r'),'%f %s %f %s %f %f %f %f %f %f %f %f %f %f %f %f %f %f %f %f',[23,inf]))';
IEEE_format_branch_data = (fscanf(fopen(IEEE_format_branch_file,'r'),'%f',[21,inf]))';
fclose('all');
end

function rect = pol2rect(rho,theta)
rect = rho.*cos(theta) + 1i*rho.*sin(theta);
end
