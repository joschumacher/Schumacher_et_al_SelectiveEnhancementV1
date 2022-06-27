%script for loading in behavior data and passive static grating data,
%then doing population d' analysis to determine separation of target and distractor in
%population code.



for kk = 1:length(b1s)
    clear opt
    b1 = b1s(kk);
    b2 = b2s(kk);
    b3 = b3s(kk);
    b4 = b4s(kk);
    
    ovrWrt = 1;
    
    if ispc
    datadir = ['E:\Animal\' tsID '\'];
    datadir = ['Z:\Joe\Recovered\Animal\' tsID '\'];
    %datadir = ['G:\Animal\' tsID '\'];
    load([datadir 't' sprintf('%05d', b1) '\cellData.mat']); 
    activeData = data;
    load([datadir 't' sprintf('%05d', b2) '\cellData.mat']);
    passiveData = data;
    behaveData = load([datadir 't' sprintf('%05d', b1) '\' tsID '_' 't' sprintf('%05d', b1) '.mat']);
    
    load([datadir 't' sprintf('%05d', b3) '\cellData.mat']);    
    activeData2 = data;
    load([datadir 't' sprintf('%05d', b4) '\cellData.mat']);
    passiveData2 = data;
    behaveData2 = load([datadir 't' sprintf('%05d', b3) '\' tsID '_' 't' sprintf('%05d', b3) '.mat']);
    
    %load('E:\Animal\qbert\comp54_28_6.mat')
    load('Z:\Joe\Recovered\Animal\qbert\comp54_28_6.mat')
    
else
%     datadir = '/Users/Schumacher/Dropbox (Personal)/2pAnalysis/Qbert_LongAnalysis/';
%     load([datadir '/crossref53_28.mat']);
%     load([datadir '/t000' num2str(b1) '/cellData.mat']);
%     data2 = data;
%     load([datadir '/t000' num2str(b2) '/cellData.mat']);
%     data1 = data;
%     oriDat = load([datadir '/t000' num2str(b1) '/qbert_Splus_Sminus_by_ori.mat']);
    end


    
clear data
opt.plotter=0;
opt.preStim = .5;
opt.stimDur = .5;
opt.postStim = .5;

%% starting with passive data, get responses aligned to experiment
opt.plotter=0;
opt.preStim = .5;
opt.stimDur = .5;
opt.postStim = .5;

plotter = 0;
nTrials = 10;
   
phis = [0:2.5:177.5];   

nStims = length(phis);

tuningInds = [1:length(phis)];

%%do a check to see if the resps for passive exists

exclude = [];
for j=1:length(exclude)
    compList(exclude(j),3) = nan;
end
    c2u = find(~isnan(compList(:,3)));
    c2u = compList(c2u,3);
    
    c2uPre = c2u;

uniqStims1 = passiveData(1).uniqStims;
if exist([datadir 't' sprintf('%05d', b2) '/resps.mat'])==2 & ovrWrt~=1
    load([datadir 't' sprintf('%05d', b2) '/resps.mat']);
    resps1 = resps
else
    [resps] = alignStimResp(passiveData,uniqStims1,opt);
    save([datadir 't' sprintf('%05d', b2) '/resps.mat'],'resps');
    resps1 = resps;
end


respsPre = resps1;

%go ahead and calculate pOris
clear pOri pOri2
for c = 1:length(resps1) 
resps1(c).curveK(find(isinf(resps1(c).curveK)))=0;
resps1(c).curveK(find(isnan(resps1(c).curveK)))=0;
resps1(c).curveK = resps1(c).curveK(1:min([10 size(resps1(c).curveK,1)]),:);
%generate 1000 tuning curves by sampling curve k 10 times at each stim
numSims = 100;
numSimTs = 5;
tmp = resps1(c).curveK;
tic
for j = 1:numSims
    
    tempCurve = [];
    for k = 1:size(tmp,2)
        tmpSamps = randi(10,[size(tmp,1),1]);
        tempCurve = [tempCurve tmp(tmpSamps,k)];
    end
    sim(c).curve{j} = tempCurve;
    tCtemp = mean(tempCurve);
    tCtemp = tCtemp(1:end-1);
    %pref ori = maxresp(tCtemp)
    sim(c).pOri(j) = phis(find(tCtemp==max(tCtemp),1));
    sim(c).pOriR(j) = max(tCtemp);
    
    %now a measure of reliability at pOri
    sim(c).cvPOri(j) = std(tempCurve(:,find(tCtemp==max(tCtemp),1)))/mean(tempCurve(:,find(tCtemp==max(tCtemp),1)));
    sim(c).cvFlank(j) =std(tempCurve(:,find(phis(find(phis>=135&phis<=165))))')/mean(tempCurve(:,find(phis(find(phis>=135&phis<=165))))');
   
    %pref ori = resultant theta, vectorsum(tCtemp)
    rs = tCtemp/max(tCtemp);
    ts = 2*phis;
    ts = circ_ang2rad(ts);
    [theta,r]=circ_polarResultant(ts,rs);
    theta = circ_rad2ang(theta);
    theta = theta/2;
    if theta<0
        theta = theta+180;
    end
    sim(c).pOri2(j) = theta;
    sim(c).vs(j) = r;
end
pOri1(c) = mean(sim(c).pOri);
pOri2(c) = mean(sim(c).pOri2);
curve1(c,:) = mean(tmp);
end

pOri1 = pOri1(c2u);
pOri2 = pOri2(c2u);
curve1a = curve1(c2u,:);

phis2 = [0:2.5:180];
MeanNet = [];
CummNet = [];
CNgs = [];
for j = 1:length(resps1(1).stim)
    nettemp = [];
    for k = 1:10%size(resps(1).curveK,1)
        trialtemp = [];
        for l = 1:length(c2u)%1:size(resps1,2)
            ind = c2u(l);
            trialtemp = [trialtemp resps1(ind).curveK(k,j)];
        end
        nettemp = [nettemp;trialtemp];
    end
    StimNet{j} = nettemp;
    MeanNet = [MeanNet;mean(StimNet{j})];
    CummNet = [CummNet; nettemp];
    CNgs = [CNgs;phis2(j)*ones(size(nettemp,1),1)];
    DistMat{j} = pdist(StimNet{j});
end
DistMeanMat = pdist(MeanNet);
scanRate = activeData(1).rate;


%%
%Gathering relevant behavior data
exptData = behaveData.exptData;
% these are the frames that the stims start with
sFrames = exptData.data.stimBlock2P(:,3)

% these are the times of the different stims
sTimes = exptData.data.twophotontimes(sFrames)

% these are the corresponding outcomes
outC = exptData.data.blockOutcome

% now we need the orienatations and times
oTimes = exptData.data.oriTime;
oTemp = exptData.data.ori(2,:)

%ori(j) will be the orientation for sTimes(j)
clear ori otime
for j = 1:length(sTimes)
    switch outC(j)
        case 0
            ori(j)=nan;
        otherwise
            temp = abs(oTimes-sTimes(j))
            tInd = find(temp==min(temp,1));
            ori(j) = exptData.data.ori(2,tInd);
            oTime(j) = oTimes(tInd)
    end
end

%testing to see if for older data, oTime is more accurate tahn sTimes
oTime2 = oTime;
oTime2(find(oTime==0)) = sTimes(find(oTime==0));

oriDat.stim_type = ori; %(this could be changed to have stim be 4 or 5 for +/-
oriDat.time = oTime2;% sTimes;
oriDat.outcome = outC;
oriDat.orientation = ori;
%also going to want to package oriDat.outC somehow, but will come back to
%that.
opt.oriDat = oriDat;

uniqStims2 = unique(oriDat.orientation);
uniqStims2 = uniqStims2(find(~isnan(uniqStims2)));


% now we go for the active pre trials
if exist([datadir 't000' num2str(b1) '/resps.mat'])==2 & ovrWrt~=1
    load([datadir 't000' num2str(b1) '/resps.mat']);
    resps1 = resps
else
    [resps] = alignStimResp(activeData,uniqStims2,opt);
    if(b1<10)
    save([datadir 't0000' num2str(b1) '/resps.mat'],'resps');
    else
        save([datadir 't000' num2str(b1) '/resps.mat'],'resps');
    end
    resps1 = resps;
end



%%
MeanNet = [];
CummNet2 = [];
CNgs2 = [];
for j = 1:length(resps1(1).stim)
    nettemp = [];
    for k = 1:length(resps1(1).curveK2{j})
        trialtemp = [];
        for l = 1:length(c2u)%1:size(resps1,2)
            ind = c2u(l);
            trialtemp = [trialtemp resps1(ind).curveK2{j}(k)];
        end
        nettemp = [nettemp;trialtemp];
    end
    StimNet{j} = nettemp;
    MeanNet = [MeanNet;mean(StimNet{j})];
    CummNet2 = [CummNet2; nettemp];
    CNgs2 = [CNgs2;uniqStims2(j)*ones(size(nettemp,1),1)];
    DistMat{j} = pdist(StimNet{j});
end
DistMeanMat = pdist(MeanNet);
scanRate = activeData(1).rate;

%%
%now we go for the post trials
%%do a check to see if the resps for passive exists
    c2u = find(~isnan(compList(:,3)));
    c2u = compList(c2u,1);
uniqStims1 = passiveData2(1).uniqStims;
opt = rmfield(opt,'oriDat')
if exist([datadir 't' sprintf('%05d', b4) '/resps.mat'])==2 & ovrWrt~=1
    load([datadir 't' sprintf('%05d', b4) '/resps.mat']);
    resps1 = resps
else
    [resps] = alignStimResp(passiveData2,uniqStims1,opt);
    save([datadir 't' sprintf('%05d', b4) '/resps.mat'],'resps');
    resps1 = resps;
end
%go ahead and calculate pOris
clear pOriPost pOri2Post
for c = 1:length(resps1) 
resps1(c).curveK(find(isinf(resps1(c).curveK)))=0;
resps1(c).curveK(find(isnan(resps1(c).curveK)))=0;
resps1(c).curveK = resps1(c).curveK(1:min([10 size(resps1(c).curveK,1)]),:);
%generate 1000 tuning curves by sampling curve k 10 times at each stim
numSims = 100;
numSimTs = 5;
tmp = resps1(c).curveK;
tic

for j = 1:numSims
    
    tempCurve = [];
    for k = 1:size(tmp,2)
        tmpSamps = randi(size(tmp,1),[size(tmp,1),1]);
        tempCurve = [tempCurve tmp(tmpSamps,k)];
    end
    sim(c).curve{j} = tempCurve;
    tCtemp = mean(tempCurve);
    tCtemp = tCtemp(1:end-1);
    %pref ori = maxresp(tCtemp)
    sim(c).pOri(j) = phis(find(tCtemp==max(tCtemp),1));
    sim(c).pOriR(j) = max(tCtemp);
    
    %now a measure of reliability at pOri
    sim(c).cvPOri(j) = std(tempCurve(:,find(tCtemp==max(tCtemp),1)))/mean(tempCurve(:,find(tCtemp==max(tCtemp),1)));
    sim(c).cvFlank(j) =std(tempCurve(:,find(phis(find(phis>=135&phis<=165))))')/mean(tempCurve(:,find(phis(find(phis>=135&phis<=165))))');
   
    %pref ori = resultant theta, vectorsum(tCtemp)
    rs = tCtemp/max(tCtemp);
    ts = 2*phis;
    ts = circ_ang2rad(ts);
    [theta,r]=circ_polarResultant(ts,rs);
    theta = circ_rad2ang(theta);
    theta = theta/2;
    if theta<0
        theta = theta+180;
    end
    sim(c).pOri2(j) = theta;
    sim(c).vs(j) = r;
end
pOri1Post(c) = mean(sim(c).pOri);
pOri2Post(c) = mean(sim(c).pOri2);
end
pOri1Post = pOri1Post(c2u);
pOri2Post = pOri2Post(c2u);

respsPost = resps1;
c2uPost = c2u;

phis2 = [0:2.5:180];
MeanNet = [];
CummNet3 = [];
CNgs3 = [];

for j = 1:length(resps1(1).stim)
    nettemp = [];
    for k = 1:10%size(resps(1).curveK,1)
        trialtemp = [];
        for l = 1:length(c2u)%1:size(resps1,2)
            ind = c2u(l);
            trialtemp = [trialtemp resps1(ind).curveK(k,j)];
        end
        nettemp = [nettemp;trialtemp];
    end
    StimNet{j} = nettemp;
    MeanNet = [MeanNet;mean(StimNet{j})];
    CummNet3 = [CummNet3; nettemp];
    CNgs3 = [CNgs3;phis2(j)*ones(size(nettemp,1),1)];
    DistMat{j} = pdist(StimNet{j});
end
DistMeanMat = pdist(MeanNet);
scanRate = activeData(1).rate;

for c = 1:length(resps1)
    curve2(c,:) = mean(resps1(c).curveK);
end
curve2a = curve2(c2u,:);

%Gathering relevant behavior data
exptData = behaveData2.exptData;
% these are the frames that the stims start with
sFrames = exptData.data.stimBlock2P(:,3)

% these are the times of the different stims
sTimes = exptData.data.twophotontimes(sFrames)

% these are the corresponding outcomes
outC = exptData.data.blockOutcome

% now we need the orienatations and times
oTimes = exptData.data.oriTime;
oTemp = exptData.data.ori(2,:)

%ori(j) will be the orientation for sTimes(j)
clear ori oTime
for j = 1:length(sTimes)
    switch outC(j)
        case 0
            ori(j)=nan;
        otherwise
            temp = abs(oTimes-sTimes(j))
            tInd = find(temp==min(temp,1));
            ori(j) = exptData.data.ori(2,tInd);
            oTime(j) = oTimes(tInd)
    end
end

%testing to see if for older data, oTime is more accurate tahn sTimes
oTime2 = oTime;
oTime2(find(oTime==0)) = sTimes(find(oTime==0));

oriDat.stim_type = ori; %(this could be changed to have stim be 4 or 5 for +/-
oriDat.time = oTime2;% sTimes;
oriDat.outcome = outC;
oriDat.orientation = ori;
%also going to want to package oriDat.outC somehow, but will come back to
%that.
opt.oriDat = oriDat;

uniqStims2 = unique(oriDat.orientation);
uniqStims2 = uniqStims2(find(~isnan(uniqStims2)));


% now we go for the active post trials
if exist([datadir 't000' num2str(b3) '/resps.mat'])==2 & ovrWrt~=1
    load([datadir 't000' num2str(b3) '/resps.mat']);
    resps1 = resps
else
    [resps] = alignStimResp(activeData2,uniqStims2,opt);
    save([datadir 't000' num2str(b3) '/resps.mat'],'resps');
    resps1 = resps;
end


MeanNet = [];
CummNet4 = [];
CNgs4 = [];
for j = 1:length(resps1(1).stim)
    nettemp = [];
    for k = 1:length(resps1(1).curveK2{j})
        trialtemp = [];
        for l = 1:length(c2u)%1:size(resps1,2)
            ind = c2u(l);
            trialtemp = [trialtemp resps1(ind).curveK2{j}(k)];
        end
        nettemp = [nettemp;trialtemp];
    end
    StimNet{j} = nettemp;
    MeanNet = [MeanNet;mean(StimNet{j})];
    CummNet4 = [CummNet4; nettemp];
    CNgs4 = [CNgs4;uniqStims2(j)*ones(size(nettemp,1),1)];
    DistMat{j} = pdist(StimNet{j});
end
DistMeanMat = pdist(MeanNet);
scanRate = activeData(1).rate;


%%
%Here is the second method for calculating population d-prime
%Project each point onto the line characterized by the mean
%population response to two different stimuli

df = CummNet3(find(CNgs3==dfori),:)
mDF = mean(df);
tp = CummNet3(find(CNgs3==tpori),:)
mTP = mean(tp);
v = mTP-mDF;
for j = 1:size(df,1)
    pDF(j) = v*df(j,:)'/norm(v);
end
for j = 1:size(tp,1)
    pTP(j) = v*tp(j,:)'/norm(v);
end    

figure
%subplot(2,1,1)
hist(pTP)
hold on;
%subplot(2,1,2)
hist(pDF)

%2.49427704643009 vs. 1.34863539057259 orig.
dProj = abs((mean(pTP)-mean(pDF))/(sqrt(.5*((std(pTP)^2)+std(pDF)^2))))


