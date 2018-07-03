
function [aveLatencyLocal, aveLatencySelective, aveLatencyRemote] = offLoadingSelect(carNum)
%% 可传入参数，目前先本文件中设定
% task
% 任务种类数：[10, 15]之间随机整数
% taskKinds = 9 + unidrnd(6);
taskKinds = 15;
% 每个任务大小：[300, 500]kB之间随机整数
taskSize = floor(300 + (500 - 300) .* rand([taskKinds, 1])) .* 1e3 .* 8;
% 每个任务计算完成所需周期数
% 特定计算公式 根据任务大小获得[] (420kB / 1000MCycles 得出关系)
taskComputeCycle = taskSize ./ 0.00336;

% car
% car个数  请求数 [5, 20]
% carNum = 4 + unidrnd(16);

% 计算能力：[0.5, 1.5]GHz
carCpuFreq = (rand(carNum, 1) + 0.5) .* 1e9;
% 能够容忍的时延： 1s
carLatencyRequired = 1;
% 数据传输速率 50Mbit/s
carDataRate = 50 * 1e6;

% MEC server
% 缓存能力大小：能够缓存的任务个数（暂定），规定为总任务数的1/3
mecCacheNum = floor(taskKinds / 3);
% 已缓存任务表：[taskIndex, taskResult]（暂定只有taskIndex字段，后续考虑是否加入对任务结果的回传时延等）
% 初始状态全0
mecCacheTable = zeros(mecCacheNum, 1);
% 所有任务被请求次数记录表： [taskIndex, usedNum]
% 初始状态 使用次数全0
mecCacheRecordTable = [linspace(1, taskKinds, taskKinds); zeros(1, taskKinds)]';
% 计算资源：10GHz
mecCpuFreq = 10 * 1e9;
% 当前剩余计算资源
mecRemainCpuFreq = mecCpuFreq;

% 对每个请求随机分配任务 [1, taskKinds]
taskReq = floor((rand(carNum, 1) .* taskKinds) + 1);
% 记录每个请求是否已完成
taskIsDone = zeros(carNum, 1);

% 记录总时延
taskDoneLatency = zeros(carNum, 1);
% car查看mec服务器广播的缓存任务表，决定是否可以直接从服务器请求结果

% 传输时延
transmitLatency = taskSize(taskReq) ./ carDataRate;
% 首先对各任务请求所需服务器资源大小进行升序排序
% 之后优先对所需资源较小的任务进行计算
sortedMinResourceRequire = [linspace(1, carNum, carNum)', (taskComputeCycle(taskReq) ./ (carLatencyRequired - transmitLatency))];
sortedMinResourceRequire = sortrows(sortedMinResourceRequire, 2);
sortedMinResourceIndex = sortedMinResourceRequire(:, 1);

% 记录某计算请求当前是否占用服务器的计算资源
% 若0，则未占用，否则标记为该请求的预期计算时间
mecOccupiedTaskRecordTable = zeros(carNum, 1);

%% 全部本地计算
aveLatencyLocal = sum(taskComputeCycle(taskReq) ./ carCpuFreq) / carNum;

%% 基于popular度；带MEC服务器缓存的 选择性卸载 代码实现
% 从请求资源最小的开始遍历
% 所以 应该就不用多次遍历了？*******************************
for i = 1: carNum
    index = sortedMinResourceIndex(i);
    isDoneOnServer = 0;
    if taskIsDone(index) == 1
        % 若该请求的计算任务已在服务器缓存中
        sprintf('第%d个请求任务 -> 已在服务器缓存', index)
    elseif taskComputeCycle(taskReq(index)) / carCpuFreq(index) <= carLatencyRequired
        % 2. 若本地计算满足容忍时延，则选择在本地计算
        taskDoneLatency(index) = taskComputeCycle(taskReq(index)) / carCpuFreq(index);
        taskIsDone(index) = 1;
        sprintf('第%d个请求任务 -> 本地计算', index)
        isDoneOnServer = 0;
        % 本地计算时，对计算任务的请求个数是否需要加到mecCacheRecordTable中？*******************************
        % 个人感觉需要
    elseif mecRemainCpuFreq > sortedMinResourceRequire(i, 2)
        % 3. 卸载到MEC服务器计算 假定在MEC服务器计算一定可以在容忍的时间内完成
        % 首先判断当前mec计算资源是否足够
        % 若计算资源足够
        mecRemainCpuFreq = mecRemainCpuFreq - sortedMinResourceRequire(i, 2);
        taskIsDone(index) = 1;
        % 因为需要考虑之前可能有过需要等待任务完成，所以此处在taskDoneLatency基础上增加
        taskDoneLatency(index) = taskDoneLatency(index) + carLatencyRequired;
        % 标记当前占用了服务器资源，值为计算时间
        mecOccupiedTaskRecordTable(index) = carLatencyRequired - transmitLatency(index);
        isDoneOnServer = 1;
        % 将该计算任务的请求数加1
        mecCacheRecordTable(find(mecCacheRecordTable(:, 1) == taskReq(index)), 2) = mecCacheRecordTable(find(mecCacheRecordTable(:, 1) == taskReq(index)), 2) + 1;
        % 对mec服务器 所有任务被请求次数记录表 重新降序排列
        % 并将请求次数最多的mecCacheNum个计算任务索引及结果放入已缓存任务表mecCacheTable中
        mecCacheRecordTable = sortrows(mecCacheRecordTable, 2, 'descend');
        mecCacheTable = mecCacheRecordTable(1: mecCacheNum, 1);
        sprintf('第%d个请求任务 -> 卸载且计算资源足够', index)
    else
        % 当前mec计算资源不够
        % 在当前mec计算任务列表中，凑出足够当前请求任务完成的计算资源
        % 故该请求之后任务均需要等待凑的任务完成的时间最大值
        
        % 在mec服务器上计算的时间 应为(carLatencyRequired - transmitLatency)
        % 若等待的时间+计算时间+传输时间 > 时延容忍 怎么解决？ 现未考虑这个问题*******************************
        % 所以 目前均假定即使等待某些任务完成，依旧可以满足时延容忍
        
        % 找出占用服务器资源的计算任务所需时间，并升序排序
        temp4Wait = sortrows(sortedMinResourceRequire, 2, 'descend');
        % 从计算时间最小开始收集计算资源
        % 还是从占用计算资源最大开始收集
        % 目前定为 从计算时间最小开始收集
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
                    % 若已收集资源加原有资源 已满足当前任务完成计算
                    % 将之后计算任务时延均加上该等待时延
                    taskIsDone(index) = 1;
                    mecRemainCpuFreq = mecRemainCpuFreq + gatheredCpuFreq - sortedMinResourceRequire(index);
                    % 将后续计算任务的等待时间统一加  等待时延
                    taskDoneLatency(index : carNum) = taskDoneLatency(index : carNum) + waitedLatency;
                    taskDoneLatency(index) = taskDoneLatency(index) + carLatencyRequired;
                    % 并将当前正在计算任务之后的等待时延'减去该等待时延
                    % 表示均等待了 等待时延 时间
                    mecOccupiedTaskRecordTable = mecOccupiedTaskRecordTable - waitedLatency;

                    % 标记当前占用了服务器资源，值为计算时间
                    mecOccupiedTaskRecordTable(index) = carLatencyRequired - transmitLatency(index);

                    % 将该计算任务的请求数加1
                    mecCacheRecordTable(taskReq(index), 2) = mecCacheRecordTable(taskReq(index), 2) + 1;
                    % 对mec服务器 所有任务被请求次数记录表 重新降序排列
                    % 并将请求次数最多的mecCacheNum个计算任务索引及结果放入已缓存任务表mecCacheTable中
                    mecCacheRecordTable = sortrows(mecCacheRecordTable, 2, 'descend');
                    mecCacheTable = mecCacheRecordTable(1: mecCacheNum, 1);
                    break;
                end
            end
        end
        sprintf('第%d个请求任务 -> 卸载且计算资源不够，需要等待', index)
        isDoneOnServer = 1;
    end
    % 查看是否当前任务在服务器完成
    if isDoneOnServer == 1
        % 若在服务器完成，且不是之前已缓存的结果
        % 将其他请求相同计算的任务标记为完成
        % 并记录该任务的请求个数
       req = taskReq(index);
       taskReqTemp = taskReq;
       % 判断当前请求任务是否在缓存中
       if length(find(mecCacheTable(:, 1) == taskReq(index))) ~= 0
           % 在缓存中
           taskIsDoneOnServerNow = find(taskReqTemp == req);
           taskIsDone(taskIsDoneOnServerNow) = 1;
       end
       mecCacheRecordTable(find(mecCacheRecordTable(:, 1) == taskReq(index)), 2) = mecCacheRecordTable(find(mecCacheRecordTable(:, 1) == taskReq(index)), 2) + length(taskIsDoneOnServerNow) - 1;
       % 对mec服务器 所有任务被请求次数记录表 重新降序排列
        % 并将请求次数最多的mecCacheNum个计算任务索引及结果放入已缓存任务表mecCacheTable中
        mecCacheRecordTable = sortrows(mecCacheRecordTable, 2, 'descend');
        mecCacheTable = mecCacheRecordTable(1: mecCacheNum, 1);
    end
end

% 结果统计
aveLatencySelective = sum(taskDoneLatency) / carNum;

% 恢复修改的变量
taskIsDone = zeros(carNum, 1);
mecRemainCpuFreq = mecCpuFreq;
taskDoneLatency = zeros(carNum, 1);
mecOccupiedTaskRecordTable = zeros(carNum, 1);

%% 全部卸载，且无缓存
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
                    % 若已收集资源加原有资源 已满足当前任务完成计算
                    % 将之后计算任务时延均加上该等待时延
                    taskIsDone(index) = 1;
                    mecRemainCpuFreq = mecRemainCpuFreq + gatheredCpuFreq - sortedMinResourceRequire(index);
                    % 将后续计算任务的等待时间统一加  等待时延
                    taskDoneLatency(index : carNum) = taskDoneLatency(index : carNum) + waitedLatency;
                    taskDoneLatency(index) = taskDoneLatency(index) + carLatencyRequired;
                    % 并将当前正在计算任务之后的等待时延'减去该等待时延
                    % 表示均经过了 等待时延 时间
                    mecOccupiedTaskRecordTable = mecOccupiedTaskRecordTable - waitedLatency;

                    % 标记当前占用了服务器资源，值为计算时间
                    mecOccupiedTaskRecordTable(index) = carLatencyRequired - transmitLatency(index);
                    break;
                end
            sprintf('第%d个请求任务 -> 计算资源不够，需要等待', index)
            end
        end
    end
end
% 结果统计
aveLatencyRemote = sum(taskDoneLatency) / carNum;