
function [aveLatencyLocal, aveLatencySelective, aveLatencyRemote] = offLoadingSelect(carNum)
%% �ɴ��������Ŀǰ�ȱ��ļ����趨
% task
% ������������[10, 15]֮���������
% taskKinds = 9 + unidrnd(6);
taskKinds = 15;
% ÿ�������С��[300, 500]kB֮���������
taskSize = floor(300 + (500 - 300) .* rand([taskKinds, 1])) .* 1e3 .* 8;
% ÿ����������������������
% �ض����㹫ʽ ���������С���[] (420kB / 1000MCycles �ó���ϵ)
taskComputeCycle = taskSize ./ 0.00336;

% car
% car����  ������ [5, 20]
% carNum = 4 + unidrnd(16);

% ����������[0.5, 1.5]GHz
carCpuFreq = (rand(carNum, 1) + 0.5) .* 1e9;
% �ܹ����̵�ʱ�ӣ� 1s
carLatencyRequired = 1;
% ���ݴ������� 50Mbit/s
carDataRate = 50 * 1e6;

% MEC server
% ����������С���ܹ����������������ݶ������涨Ϊ����������1/3
mecCacheNum = floor(taskKinds / 3);
% �ѻ��������[taskIndex, taskResult]���ݶ�ֻ��taskIndex�ֶΣ����������Ƿ������������Ļش�ʱ�ӵȣ�
% ��ʼ״̬ȫ0
mecCacheTable = zeros(mecCacheNum, 1);
% �����������������¼�� [taskIndex, usedNum]
% ��ʼ״̬ ʹ�ô���ȫ0
mecCacheRecordTable = [linspace(1, taskKinds, taskKinds); zeros(1, taskKinds)]';
% ������Դ��10GHz
mecCpuFreq = 10 * 1e9;
% ��ǰʣ�������Դ
mecRemainCpuFreq = mecCpuFreq;

% ��ÿ����������������� [1, taskKinds]
taskReq = floor((rand(carNum, 1) .* taskKinds) + 1);
% ��¼ÿ�������Ƿ������
taskIsDone = zeros(carNum, 1);

% ��¼��ʱ��
taskDoneLatency = zeros(carNum, 1);
% car�鿴mec�������㲥�Ļ�������������Ƿ����ֱ�Ӵӷ�����������

% ����ʱ��
transmitLatency = taskSize(taskReq) ./ carDataRate;
% ���ȶԸ��������������������Դ��С������������
% ֮�����ȶ�������Դ��С��������м���
sortedMinResourceRequire = [linspace(1, carNum, carNum)', (taskComputeCycle(taskReq) ./ (carLatencyRequired - transmitLatency))];
sortedMinResourceRequire = sortrows(sortedMinResourceRequire, 2);
sortedMinResourceIndex = sortedMinResourceRequire(:, 1);

% ��¼ĳ��������ǰ�Ƿ�ռ�÷������ļ�����Դ
% ��0����δռ�ã�������Ϊ�������Ԥ�ڼ���ʱ��
mecOccupiedTaskRecordTable = zeros(carNum, 1);

%% ȫ�����ؼ���
aveLatencyLocal = sum(taskComputeCycle(taskReq) ./ carCpuFreq) / carNum;

%% ����popular�ȣ���MEC����������� ѡ����ж�� ����ʵ��
% ��������Դ��С�Ŀ�ʼ����
% ���� Ӧ�þͲ��ö�α����ˣ�*******************************
for i = 1: carNum
    index = sortedMinResourceIndex(i);
    isDoneOnServer = 0;
    if taskIsDone(index) == 1
        % ��������ļ����������ڷ�����������
        sprintf('��%d���������� -> ���ڷ���������', index)
    elseif taskComputeCycle(taskReq(index)) / carCpuFreq(index) <= carLatencyRequired
        % 2. �����ؼ�����������ʱ�ӣ���ѡ���ڱ��ؼ���
        taskDoneLatency(index) = taskComputeCycle(taskReq(index)) / carCpuFreq(index);
        taskIsDone(index) = 1;
        sprintf('��%d���������� -> ���ؼ���', index)
        isDoneOnServer = 0;
        % ���ؼ���ʱ���Լ����������������Ƿ���Ҫ�ӵ�mecCacheRecordTable�У�*******************************
        % ���˸о���Ҫ
    elseif mecRemainCpuFreq > sortedMinResourceRequire(i, 2)
        % 3. ж�ص�MEC���������� �ٶ���MEC����������һ�����������̵�ʱ�������
        % �����жϵ�ǰmec������Դ�Ƿ��㹻
        % ��������Դ�㹻
        mecRemainCpuFreq = mecRemainCpuFreq - sortedMinResourceRequire(i, 2);
        taskIsDone(index) = 1;
        % ��Ϊ��Ҫ����֮ǰ�����й���Ҫ�ȴ�������ɣ����Դ˴���taskDoneLatency����������
        taskDoneLatency(index) = taskDoneLatency(index) + carLatencyRequired;
        % ��ǵ�ǰռ���˷�������Դ��ֵΪ����ʱ��
        mecOccupiedTaskRecordTable(index) = carLatencyRequired - transmitLatency(index);
        isDoneOnServer = 1;
        % ���ü����������������1
        mecCacheRecordTable(find(mecCacheRecordTable(:, 1) == taskReq(index)), 2) = mecCacheRecordTable(find(mecCacheRecordTable(:, 1) == taskReq(index)), 2) + 1;
        % ��mec������ �����������������¼�� ���½�������
        % ���������������mecCacheNum������������������������ѻ��������mecCacheTable��
        mecCacheRecordTable = sortrows(mecCacheRecordTable, 2, 'descend');
        mecCacheTable = mecCacheRecordTable(1: mecCacheNum, 1);
        sprintf('��%d���������� -> ж���Ҽ�����Դ�㹻', index)
    else
        % ��ǰmec������Դ����
        % �ڵ�ǰmec���������б��У��ճ��㹻��ǰ����������ɵļ�����Դ
        % �ʸ�����֮���������Ҫ�ȴ��յ�������ɵ�ʱ�����ֵ
        
        % ��mec�������ϼ����ʱ�� ӦΪ(carLatencyRequired - transmitLatency)
        % ���ȴ���ʱ��+����ʱ��+����ʱ�� > ʱ������ ��ô����� ��δ�����������*******************************
        % ���� Ŀǰ���ٶ���ʹ�ȴ�ĳЩ������ɣ����ɿ�������ʱ������
        
        % �ҳ�ռ�÷�������Դ�ļ�����������ʱ�䣬����������
        temp4Wait = sortrows(sortedMinResourceRequire, 2, 'descend');
        % �Ӽ���ʱ����С��ʼ�ռ�������Դ
        % ���Ǵ�ռ�ü�����Դ���ʼ�ռ�
        % Ŀǰ��Ϊ �Ӽ���ʱ����С��ʼ�ռ�
        gatheredCpuFreq = 0;
        waitedLatency = 0;
        for j = 1: length(temp4Wait)
            index4Wait = temp4Wait(j, 1);
            if mecOccupiedTaskRecordTable(index4Wait) == 0
                continue;
            else
                gatheredCpuFreq = gatheredCpuFreq + temp4Wait(j, 2);
                waitedLatency = waitedLatency + mecOccupiedTaskRecordTable(index4Wait);
                if mecRemainCpuFreq + gatheredCpuFreq >= sortedMinResourceRequire(index)
                    % �����ռ���Դ��ԭ����Դ �����㵱ǰ������ɼ���
                    % ��֮���������ʱ�Ӿ����ϸõȴ�ʱ��
                    taskIsDone(index) = 1;
                    mecRemainCpuFreq = mecRemainCpuFreq + gatheredCpuFreq - sortedMinResourceRequire(index);
                    % ��������������ĵȴ�ʱ��ͳһ��  �ȴ�ʱ��
                    taskDoneLatency(index : carNum) = taskDoneLatency(index : carNum) + waitedLatency;
                    taskDoneLatency(index) = taskDoneLatency(index) + carLatencyRequired;
                    % ������ǰ���ڼ�������֮��ĵȴ�ʱ��'��ȥ�õȴ�ʱ��
                    % ��ʾ���ȴ��� �ȴ�ʱ�� ʱ��
                    mecOccupiedTaskRecordTable = mecOccupiedTaskRecordTable - waitedLatency;

                    % ��ǵ�ǰռ���˷�������Դ��ֵΪ����ʱ��
                    mecOccupiedTaskRecordTable(index) = carLatencyRequired - transmitLatency(index);

                    % ���ü����������������1
                    mecCacheRecordTable(taskReq(index), 2) = mecCacheRecordTable(taskReq(index), 2) + 1;
                    % ��mec������ �����������������¼�� ���½�������
                    % ���������������mecCacheNum������������������������ѻ��������mecCacheTable��
                    mecCacheRecordTable = sortrows(mecCacheRecordTable, 2, 'descend');
                    mecCacheTable = mecCacheRecordTable(1: mecCacheNum, 1);
                    break;
                end
            end
        end
        sprintf('��%d���������� -> ж���Ҽ�����Դ��������Ҫ�ȴ�', index)
        isDoneOnServer = 1;
    end
    % �鿴�Ƿ�ǰ�����ڷ��������
    if isDoneOnServer == 1
        % ���ڷ�������ɣ��Ҳ���֮ǰ�ѻ���Ľ��
        % ������������ͬ�����������Ϊ���
        % ����¼��������������
       req = taskReq(index);
       taskReqTemp = taskReq;
       % �жϵ�ǰ���������Ƿ��ڻ�����
       if length(find(mecCacheTable(:, 1) == taskReq(index))) ~= 0
           % �ڻ�����
           taskIsDoneOnServerNow = find(taskReqTemp == req);
           taskIsDone(taskIsDoneOnServerNow) = 1;
       end
       mecCacheRecordTable(find(mecCacheRecordTable(:, 1) == taskReq(index)), 2) = mecCacheRecordTable(find(mecCacheRecordTable(:, 1) == taskReq(index)), 2) + length(taskIsDoneOnServerNow) - 1;
       % ��mec������ �����������������¼�� ���½�������
        % ���������������mecCacheNum������������������������ѻ��������mecCacheTable��
        mecCacheRecordTable = sortrows(mecCacheRecordTable, 2, 'descend');
        mecCacheTable = mecCacheRecordTable(1: mecCacheNum, 1);
    end
end

% ���ͳ��
aveLatencySelective = sum(taskDoneLatency) / carNum;

% �ָ��޸ĵı���
taskIsDone = zeros(carNum, 1);
mecRemainCpuFreq = mecCpuFreq;
taskDoneLatency = zeros(carNum, 1);
mecOccupiedTaskRecordTable = zeros(carNum, 1);

%% ȫ��ж�أ����޻���
for i = 1: carNum
	index = sortedMinResourceIndex(i);
	if mecRemainCpuFreq > sortedMinResourceRequire(i, 2)
        mecRemainCpuFreq = mecRemainCpuFreq - sortedMinResourceRequire(i, 2);
        taskIsDone(index) = 1;
        taskDoneLatency(index) = taskDoneLatency(index) + carLatencyRequired;
        mecOccupiedTaskRecordTable(index) = carLatencyRequired - transmitLatency(index);
    else
        temp4Wait = sortrows(sortedMinResourceRequire, 2, 'descend');
        gatheredCpuFreq = 0;
        waitedLatency = 0;
        for j = 1: length(temp4Wait)
            index4Wait = temp4Wait(j, 1);
            if mecOccupiedTaskRecordTable(index4Wait) == 0
                continue;
            else
                gatheredCpuFreq = gatheredCpuFreq + temp4Wait(j, 2);
                waitedLatency = waitedLatency + mecOccupiedTaskRecordTable(index4Wait);
                if mecRemainCpuFreq + gatheredCpuFreq >= sortedMinResourceRequire(index)
                    % �����ռ���Դ��ԭ����Դ �����㵱ǰ������ɼ���
                    % ��֮���������ʱ�Ӿ����ϸõȴ�ʱ��
                    taskIsDone(index) = 1;
                    mecRemainCpuFreq = mecRemainCpuFreq + gatheredCpuFreq - sortedMinResourceRequire(index);
                    % ��������������ĵȴ�ʱ��ͳһ��  �ȴ�ʱ��
                    taskDoneLatency(index : carNum) = taskDoneLatency(index : carNum) + waitedLatency;
                    taskDoneLatency(index) = taskDoneLatency(index) + carLatencyRequired;
                    % ������ǰ���ڼ�������֮��ĵȴ�ʱ��'��ȥ�õȴ�ʱ��
                    % ��ʾ�������� �ȴ�ʱ�� ʱ��
                    mecOccupiedTaskRecordTable = mecOccupiedTaskRecordTable - waitedLatency;

                    % ��ǵ�ǰռ���˷�������Դ��ֵΪ����ʱ��
                    mecOccupiedTaskRecordTable(index) = carLatencyRequired - transmitLatency(index);
                    break;
                end
            sprintf('��%d���������� -> ������Դ��������Ҫ�ȴ�', index)
            end
        end
    end
end
% ���ͳ��
aveLatencyRemote = sum(taskDoneLatency) / carNum;