
% ��������������󣬺���ʱ��
totalReq = 20;
latency = zeros(totalReq, 3);
for carNum = 1 : totalReq
    [latency(carNum, 1), latency(carNum, 2), latency(carNum, 3)] = offLoadingSelect(carNum);
end

plot(linspace(5, totalReq, totalReq),latency);
xlabel('num of req');
ylabel('average latency');
legend('total local', 'selective', 'total offloading');