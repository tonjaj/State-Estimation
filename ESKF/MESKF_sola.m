clear all;
clc;
close all;

deg2rad = pi/180;   
rad2deg = 180/pi;

Z3 = zeros(3,3);
I3 = eye(3);

simtime = 250;
f_samp  = 100;          %imu frequency
f_low   = 10;           %aiding frequency
h       = 1/f_samp;     %sampling time
N       = simtime/h;    %number of iterations

%init values
delta_x = zeros(15, 1);    % [dp, dv, dbacc, dtheta, dbars]
x_ins = zeros(16, 1);      % [p, v, bacc, q, bars]
y = zeros(6,1);

std_pos = 2;
std_att = 5 * deg2rad;

phi_ins = 0;
theta_ins = 0;
psi_ins = 0;

q_n_ins = euler2q(phi_ins,theta_ins,psi_ins);
q_n_ins = q_n_ins/norm(q_n_ins);


% data storage
time_data = zeros(1, N);
ins_data = zeros(15, N);
att_n_nb = zeros(3, N);
g_err_data = zeros(3,N);

% from sim
[p_n_nb, v_n_nb, q_nb, bacc_b_nb, bars_b_nb, f_b_imu, omega_b_imu,time, g_n_nb, v_abs, acc_std, ars_std] = SkidPadSim(simtime,f_samp,0);
% [p_n_nb, v_n_nb, att_n_nb, f_b_imu, w_b_imu,time] = StandStillSim(simtime,f_samp,0);


% dual gnss config
r_b_1 = [0.5 0.5 0.5]';
r_b_2 = [-0.5 -0.2 0]';
r_b_3 = [0.5 -0.4 0.1]'; 

%initialization of kalman filter
f_b_imu_0 = [0 0 0]';
omega_b_imu_0 = [0 0 0]';
bacc_b_ins = [0 0 0]';
bars_b_ins = [0 0 0]';
E_prev = zeros(18,12);
ErrorStateKalman_sola(0,0,r_b_1, r_b_2, r_b_3, E_prev,0, 0, f_low, 1, f_b_imu_0, omega_b_imu_0, g_n_nb, x_ins);
Iterative_ESKF(0,0, 0, 0, 0, r_b_1, r_b_2, r_b_3, E_prev,0, 0, f_low, 1, f_b_imu_0,omega_b_imu_0, g_n_nb, x_ins);
% init
x_ins(1:3) = [5;6;7]; % for testing av ESKF
% x_ins(1:3) = p_n_nb(:,1);
x_ins(4:6) = [0;0;0]; % for testing av ESKF
% x_ins(4:6) = v_n_nb(:,1);
x_ins(10:13) = [1 0 0 0]'; % for testing av ESKF
% x_ins(4:6) = [v_abs;0;0]; % korrekt initialisering. For testing av INS

% matrices
C_ins = [I3 Z3 Z3 Z3 Z3
         Z3 Z3 Z3 I3 Z3];
     
g_n_hat = g_n_nb;
     
count = 10;
race_started = false;

for k = 1:N
   t = k * h;
   time_data(k) = t;
   g_err_data(1:3,k) = g_n_hat;
   
   if ((p_n_nb(1,k) - p_n_nb(1,1)) > 0.001) && (race_started == false)
       race_started = true;
       disp(t);
   end
   
   % split state vector
   p_n_ins = x_ins(1:3);
   v_n_ins = x_ins(4:6);
   bacc_b_ins = x_ins(7:9);
   q_n_ins = x_ins(10:13);
   q_n_ins = q_n_ins/norm(q_n_ins);
   bars_b_ins = x_ins(14:16);
   
   % compute rotation vector
   R_nb_ins = Rquat(q_n_ins);
   
   % store current state 
   [phi_ins, theta_ins, psi_ins] = q2euler(q_n_ins);
   att_n_ins = [phi_ins, theta_ins, psi_ins]';
   ins_data(:,k) = [p_n_ins ; v_n_ins ; bacc_b_ins ; att_n_ins ; bars_b_ins]; 
   
   [phi_t,theta_t,psi_t] = q2euler(q_nb(:,k));
   att_n_nb(1:3,k) = [phi_t theta_t psi_t]';
   
   % compute acceleration and angular rate
   a_n_ins = R_nb_ins*(f_b_imu(:,k) - bacc_b_ins) + g_n_hat;
   f_b_ins = R_nb_ins' * (a_n_ins - g_n_hat);
   omega_b_ins = omega_b_imu(:,k) - bars_b_ins;
   
   % compute quaternion from angular rates 
   q_omega_b_ins = qbuild(omega_b_ins, h);
   
   % update nominal states with imu input
   p_n_ins = p_n_ins + (h * v_n_ins) + (0.5 * h * h * a_n_ins);
   v_n_ins = v_n_ins +  (h * a_n_ins);
  %bacc_b_ins = bacc_b_ins;
   q_n_ins = quatprod(q_n_ins, q_omega_b_ins); 
   q_n_ins = q_n_ins/norm(q_n_ins);
  %bars_b_ins = bars_b_ins;
   
   x_ins = [p_n_ins ; v_n_ins ; bacc_b_ins ; q_n_ins ; bars_b_ins];
   
   
   count = count + 1;

   if (count >= 10)
        count = 0;
        
        % noisy measurements
        p_meas(1:3,k) = p_n_nb(1:3,k) +  0.001 * randn(3, 1);
        q_meas = q_nb(1:4,k) + (2 * deg2rad) * randn(4, 1);
        
        q_conj = quatconj(q_n_ins')';
        delta_q = quatprod(q_conj, q_meas);
        delta_theta = 2*delta_q(2:4);
        
%         p_gnss_1 = p_n_nb(1:3,k) + I3*R_nb_ins*r_b_1 - Smtrx(R_nb_ins*r_b_1)*delta_theta;
%         p_gnss_2 = p_n_nb(1:3,k) + I3*R_nb_ins*r_b_2 - Smtrx(R_nb_ins*r_b_2)*delta_theta;

% -----------------------------------------------------------------------
        % Dual gnss position meas
        R_nb_t = Rquat(q_nb(1:4,k)');
        y_gnss1 = p_n_nb(1:3,k) + R_nb_t * r_b_1;
        y_gnss2 = p_n_nb(1:3,k) + R_nb_t * r_b_2;

        y_gnss1_hat = p_n_ins + R_nb_ins * r_b_1;
        y_gnss2_hat = p_n_ins + R_nb_ins * r_b_2;
        
        H_gnss1 = [I3  Z3  Z3  -R_nb_ins*Smtrx(r_b_1)  Z3  Z3];
        H_gnss2 = [I3  Z3  Z3  -R_nb_ins*Smtrx(r_b_2)  Z3  Z3];

        std_pos = 2;
        R_pos = std_pos^2*I3;
        
        disp("dual 1");
        [delta_x, E_prev] = Iterative_ESKF(0, H_gnss1, R_pos, f_b_ins, race_started, r_b_1, r_b_2, r_b_3, E_prev,(y_gnss1 - y_gnss1_hat), R_nb_ins, f_low, 0, f_b_imu, omega_b_imu, g_n_nb, x_ins);
        [x_ins,g_n_hat] = InjectErrorState(delta_x, x_ins, g_n_hat);
%         x_ins = INSUpdate(h, x_ins, a_n_ins, omega_b_ins);

        disp("dual 2");
        [delta_x, E_prev] = Iterative_ESKF(0, H_gnss2, R_pos, f_b_ins, race_started, r_b_1, r_b_2, r_b_3, E_prev,(y_gnss2 - y_gnss2_hat), R_nb_ins, f_low, 0, f_b_imu, omega_b_imu, g_n_nb, x_ins);
        [x_ins,g_n_hat] = InjectErrorState(delta_x, x_ins, g_n_hat);
%         x_ins = INSUpdate(h, x_ins, a_n_ins, omega_b_ins);
        

        
% -----------------------------------------------------------------------
%         % Ground speed velocity meas
        if (race_started)
            H_gss_alloc = [1 0 0; 0 1 0; 0 0 0];
            y_gss = H_gss_alloc*( R_nb_ins'*v_n_nb(1:3,k) + Smtrx( omega_b_imu(:,k) - bars_b_nb)*r_b_3 );
            y_gss = norm( y_gss );

            y_gss_hat = R_nb_ins' * v_n_ins - r_b_3(3)*(bars_b_ins(2) - omega_b_imu(2,k)) + r_b_3(2)*(bars_b_ins(3) - omega_b_imu(3,k));
            y_gss_hat = norm(y_gss_hat);

            H_gss_pos = [ 0, 0, 0];
            H_gss_vel = [(R_nb_ins(1,2)*(R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1)) + R_nb_ins(1,1)*(R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2)))/((R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1))^2 + (R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2))^2)^(1/2), (R_nb_ins(2,2)*(R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1)) + R_nb_ins(1,3)*(R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2)))/((R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1))^2 + (R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2))^2)^(1/2), (R_nb_ins(3,2)*(R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1)) + R_nb_ins(2,3)*(R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2)))/((R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1))^2 + (R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2))^2)^(1/2)];
            H_gss_bacc = [0, 0, 0]; 
            H_gss_att = [((R_nb_ins(1,3)*v_n_ins(1) + R_nb_ins(2,3)*v_n_ins(2) + R_nb_ins(3,3)*v_n_ins(3))*(R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1)))/((R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1))^2 + (R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2))^2)^(1/2), -((R_nb_ins(1,3)*v_n_ins(1) + R_nb_ins(2,3)*v_n_ins(2) + R_nb_ins(3,3)*v_n_ins(3))*(R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2)))/((R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1))^2 + (R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2))^2)^(1/2), -(2*(R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3))*(R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1)) - 2*(R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3))*(R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2)))/(2*((R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1))^2 + (R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2))^2)^(1/2))];
            H_gss_bars = [(r_b_3(3)*(R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1)))/((R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1))^2 + (R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2))^2)^(1/2), -(r_b_3(3)*(R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2)))/((R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1))^2 + (R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2))^2)^(1/2), -(r_b_3(1)*(R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1)) - r_b_3(2)*(R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2)))/((R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1))^2 + (R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2))^2)^(1/2)]; 
            H_gss_g = [0, 0, 0];

            H_gss = [H_gss_pos  H_gss_vel  H_gss_bacc  H_gss_att  H_gss_bars  H_gss_g];

            std_vel = 1;
            R_vel = std_vel^2;
            
            disp("ground speed");
            [delta_x, E_prev] = Iterative_ESKF(0, H_gss, R_vel, f_b_ins, race_started, r_b_1, r_b_2, r_b_3, E_prev,(y_gss - y_gss_hat), R_nb_ins, f_low, 0, f_b_imu, omega_b_imu, g_n_nb, x_ins);
            [x_ins, g_n_hat] = InjectErrorState(delta_x, x_ins, g_n_hat);
%             x_ins = INSUpdate(h, x_ins, a_n_ins, omega_b_ins);
        end
        
        
% -----------------------------------------------------------------------
        % Moving baseline
        y_vec = R_nb_t * (r_b_2 - r_b_1) + 1*randn(1)*[5,1,1]';
        y_vec_hat = R_nb_ins * (r_b_2 - r_b_1);
        
        H_vec = [Z3  Z3  Z3  -Smtrx(R_nb_ins*(r_b_2-r_b_1))  Z3  Z3];
        
        std_pos = 2;
        R_vec = 20*std_pos^2*I3;
        
        last_meas = false;
        if (race_started)
            last_meas = true;
        end
        
        disp("Vec");
        [delta_x, E_prev] = Iterative_ESKF(last_meas, H_vec, R_vec, f_b_ins, race_started, r_b_1, r_b_2, r_b_3, E_prev,(y_vec - y_vec_hat), R_nb_ins, f_low, 0, f_b_imu, omega_b_imu, g_n_nb, x_ins);
        [x_ins, g_n_hat] = InjectErrorState(delta_x, x_ins, g_n_hat);
%         x_ins = INSUpdate(h, x_ins, a_n_ins, omega_b_ins);
        
        
% -----------------------------------------------------------------------        
%         % Stand-still acceleration
        if (~race_started)
            y_acc = f_b_imu(:,k); %-(R_nb_t)' * g_n_nb + bacc_b_nb(:,k);
            y_acc_hat = -(R_nb_ins)' * g_n_hat; % + bacc_b_ins;

            H_acc = [Z3  Z3  Z3  -Smtrx(R_nb_ins' * g_n_nb)  Z3  Z3];        

            std_acc = 1;
            R_acc = std_acc^2*I3;
            
            disp("Acc");
            [delta_x, E_prev] = Iterative_ESKF(1, H_acc, R_acc, f_b_ins, race_started, r_b_1, r_b_2, r_b_3, E_prev,(y_acc - y_acc_hat), R_nb_ins, f_low, 0, f_b_imu, omega_b_imu, g_n_nb, x_ins);
            [x_ins, g_n_hat] = InjectErrorState(delta_x, x_ins, g_n_hat);
%             x_ins = INSUpdate(h, x_ins, a_n_ins, omega_b_ins);
        end
        
        
        
%         % compute difference 
% %         delta_y = [(p_gnss_1 - p_hat_1) ; (p_gnss_2 - p_hat_2); (p_gnss_3 - p_hat_3); delta_theta]; 
% %         delta_y = [(p_gnss_1 - p_hat_1) ; (p_gnss_2 - p_hat_2); delta_theta]; 
% %         delta_y = [(p_gnss_1 - p_hat_1); (p_gnss_2 - p_hat_2)];
%         delta_y = [(y_gnss1 - y_gnss1_hat) ; (y_gnss2 - y_gnss2_hat) ; (y_gss - y_gss_hat) ; (y_vec - y_vec_hat) ; (y_acc - y_acc_hat)] ;
%         
%         % GNSS1
%         [delta_x, E_prev] = ErrorStateKalman_sola(f_b_ins, race_started, r_b_1, r_b_2,r_b_3, E_prev, delta_y(1:3), R_nb_ins, f_low, 0, f_b_imu(:,k), omega_b_imu(:,k), g_n_hat, x_ins);
%         x_ins = InjectErrorState(delta_x, x_ins, g_n_hat);
%         
%         % GNSS2
%         [delta_x, E_prev] = ErrorStateKalman_sola(f_b_ins, race_started, r_b_1, r_b_2,r_b_3, E_prev, delta_y(4:6), R_nb_ins, f_low, 0, f_b_imu(:,k), omega_b_imu(:,k), g_n_hat, x_ins);
%         x_ins = InjectErrorState(delta_x, x_ins, g_n_hat);
%         
%         % GSS
%         if (race_started)
%             [delta_x, E_prev] = ErrorStateKalman_sola(f_b_ins, race_started, r_b_1, r_b_2,r_b_3, E_prev, delta_y(7), R_nb_ins, f_low, 0, f_b_imu(:,k), omega_b_imu(:,k), g_n_hat, x_ins);
%             x_ins = InjectErrorState(delta_x, x_ins, g_n_hat);
%         end
%         
%         % VEC
%         [delta_x, E_prev] = ErrorStateKalman_sola(f_b_ins, race_started, r_b_1, r_b_2,r_b_3, E_prev, delta_y(8:10), R_nb_ins, f_low, 0, f_b_imu(:,k), omega_b_imu(:,k), g_n_hat, x_ins);
%         x_ins = InjectErrorState(delta_x, x_ins, g_n_hat);
%         
%         % ACC
%         if (~race_started)
%             [delta_x, E_prev] = ErrorStateKalman_sola(f_b_ins, race_started, r_b_1, r_b_2,r_b_3, E_prev, delta_y(11:13), R_nb_ins, f_low, 0, f_b_imu(:,k), omega_b_imu(:,k), g_n_hat, x_ins);
%             x_ins = InjectErrorState(delta_x, x_ins, g_n_hat);
%         end
%         
%         
%         
%         
%                   H_gnss1 = [I3  Z3  Z3  -R_nb_ins*Smtrx(r_b_1)  Z3  Z3];
%           
%           H_gnss2 = [I3  Z3  Z3  -R_nb_ins*Smtrx(r_b_2)  Z3  Z3];
%           
%           H_vec = [Z3  Z3  Z3  -Smtrx(R_nb_ins*(r_b_2-r_b_1))  Z3  Z3];
%           
%           H_acc = [Z3  Z3  Z3  -Smtrx(R_nb_ins' * g_n_nb)  Z3  Z3];              
% %           H_acc = [Z3  Z3  Z3  Z3  Z3  Z3]; 
% 
%           H_gss_pos = [ 0, 0, 0];
%           H_gss_vel = [(R_nb_ins(1,2)*(R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1)) + R_nb_ins(1,1)*(R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2)))/((R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1))^2 + (R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2))^2)^(1/2), (R_nb_ins(2,2)*(R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1)) + R_nb_ins(1,3)*(R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2)))/((R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1))^2 + (R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2))^2)^(1/2), (R_nb_ins(3,2)*(R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1)) + R_nb_ins(2,3)*(R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2)))/((R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1))^2 + (R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2))^2)^(1/2)];
%           H_gss_bacc = [0, 0, 0]; 
%           H_gss_att = [((R_nb_ins(1,3)*v_n_ins(1) + R_nb_ins(2,3)*v_n_ins(2) + R_nb_ins(3,3)*v_n_ins(3))*(R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1)))/((R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1))^2 + (R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2))^2)^(1/2), -((R_nb_ins(1,3)*v_n_ins(1) + R_nb_ins(2,3)*v_n_ins(2) + R_nb_ins(3,3)*v_n_ins(3))*(R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2)))/((R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1))^2 + (R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2))^2)^(1/2), -(2*(R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3))*(R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1)) - 2*(R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3))*(R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2)))/(2*((R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1))^2 + (R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2))^2)^(1/2))];
%           H_gss_bars = [(r_b_3(3)*(R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1)))/((R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1))^2 + (R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2))^2)^(1/2), -(r_b_3(3)*(R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2)))/((R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1))^2 + (R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2))^2)^(1/2), -(r_b_3(1)*(R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1)) - r_b_3(2)*(R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2)))/((R_nb_ins(1,2)*v_n_ins(1) + R_nb_ins(2,2)*v_n_ins(2) + R_nb_ins(3,2)*v_n_ins(3) - bars_b_ins(2)*r_b_3(1) + bars_b_ins(1)*r_b_3(3) - omega_b_imu(1)*r_b_3(3) + omega_b_imu(3)*r_b_3(1))^2 + (R_nb_ins(1,1)*v_n_ins(1) + R_nb_ins(1,3)*v_n_ins(2) + R_nb_ins(2,3)*v_n_ins(3) + bars_b_ins(2)*r_b_3(2) - bars_b_ins(2)*r_b_3(3) + omega_b_imu(2)*r_b_3(3) - omega_b_imu(3)*r_b_3(2))^2)^(1/2)]; 
%           H_gss_g = [0, 0, 0];
%           
%           H_gss = [H_gss_pos  H_gss_vel  H_gss_bacc  H_gss_att  H_gss_bars  H_gss_g];
%           
%           
%         std_pos = 2;
%         R_pos1 = std_pos^2*I3;
%         R_pos2 = std_pos^2*I3;
%         R_vec = 2*std_pos^2*I3;
%         std_att = 1 * deg2rad;
%         R_att = std_att^2*I3;
%         std_vel = 1;
%         R_vel = std_vel^2;
%         std_acc = 1;
%         R_acc = std_acc^2*I3;
%         R = blkdiag(R_pos1 , R_pos2, std_vel^2, R_vec, R_acc);
%         
%         
%         
%         
%         
%         
%         
%         
%         
%         
%         
        
        
        
%         delta_y = [(y_gnss1 - y_gnss1_hat) ; (y_gnss2 - y_gnss2_hat) ; (y_gss - y_gss_hat) ; (y_vec - y_vec_hat)];
        
%         if (race_started == false)
%             delta_y = [delta_y ; (f_imu - f_hat)];
%         end
        
%         f_b_ins = Smtrx(omega_b_imu(:,k) - bars_b_ins) * R_nb_ins' * v_n_ins;
        
        % compute error state with ESKF
%         [delta_x, E_prev] = ErrorStateKalman_sola(f_b_ins, race_started, r_b_1, r_b_2,r_b_3, E_prev, delta_y, R_nb_ins, f_low, 0, f_b_imu(:,k), omega_b_imu(:,k), g_n_hat, x_ins);
       
%         disp(delta_x);
        
%         % inject error state into nominal state
%         x_ins(1:9) = x_ins(1:9) + delta_x(1:9);
%         x_ins(14:16) = x_ins(14:16) + delta_x(13:15);
%         g_n_hat = g_n_hat + delta_x(16:18);
% %         disp(delta_x(16:18));
%         h_low = 1/10;
%         q_delta_omega = qbuild(delta_x(10:12)/h_low, h_low);
%         x_ins(10:13) = quatprod(x_ins(10:13), q_delta_omega);
% %         delta_q = [1 ; 0.5*delta_x(10:12)];
% %         x_ins(10:13) = quatprod(x_ins(10:13), delta_q);
%         x_ins(10:13) = x_ins(10:13)/norm(x_ins(10:13)); 

%         x_ins = InjectErrorState(delta_x, x_ins, g_n_hat);
        
   end
    
   
end


PlotResults;
% 
% % PLOTS
%       
 

% FUNCTIONS

%-------------------------------------------


function [x_ins_out,g_n_hat] = InjectErrorState(delta_x, x_ins, g_n_hat)
        % inject error state into nominal state
        x_ins(1:9) = x_ins(1:9) + delta_x(1:9);
        x_ins(14:16) = x_ins(14:16) + delta_x(13:15);
        g_n_hat = g_n_hat + delta_x(16:18);
%         disp(delta_x(16:18));
        h_low = 1/10;
        q_delta_omega = qbuild(delta_x(10:12)/h_low, h_low);
        x_ins(10:13) = quatprod(x_ins(10:13), q_delta_omega);
%         delta_q = [1 ; 0.5*delta_x(10:12)];
%         x_ins(10:13) = quatprod(x_ins(10:13), delta_q);
        x_ins(10:13) = x_ins(10:13)/norm(x_ins(10:13)); 
        
        x_ins_out = x_ins;
            
end

function x_ins = INSUpdate(h, x_ins, a_n_ins, omega_b_ins)

   
   % split state vector
   p_n_ins = x_ins(1:3);
   v_n_ins = x_ins(4:6);
   bacc_b_ins = x_ins(7:9);
   q_n_ins = x_ins(10:13);
   q_n_ins = q_n_ins/norm(q_n_ins);
   bars_b_ins = x_ins(14:16);
   % compute quaternion from angular rates 
   q_omega_b_ins = qbuild(omega_b_ins, h);
   
   % update nominal states with imu input
   p_n_ins = p_n_ins + (h * v_n_ins) + (0.5 * h * h * a_n_ins);
   v_n_ins = v_n_ins +  (h * a_n_ins);
  %bacc_b_ins = bacc_b_ins;
   q_n_ins = quatprod(q_n_ins, q_omega_b_ins); 
   q_n_ins = q_n_ins/norm(q_n_ins);
  %bars_b_ins = bars_b_ins;
   
   x_ins = [p_n_ins ; v_n_ins ; bacc_b_ins ; q_n_ins ; bars_b_ins];
end

