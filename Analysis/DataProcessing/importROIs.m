% loads stimulus and two photon timing data
% then gets image data from MIJ;
% assumes that user has started Miji and has ROI's drawn;
%%
clear all;
close all;

curdir = cd

tsID = 'TsMaxB1600';
expID = 't00012';

tsID = 'Baby';
expID = 't00065';

tsID = 'qbert';
expID = 't00027';


tsID = 'Vida';
expID = 't00025';
expID = 't00051';
expID = 't00064';
expID = 't00073';
expID = 't00092';
expID = 't00094';
expID = 't00126';
expID = 't00115';
expID = 't00072';
expID = 't00063';
expID = 't00028';
expID = 't00029';
expID = 't00025';
expID = 't00026';
expID = 't00055';
% expID = 't00031';
% expID = 't00032';
% expID = 't00033';
% expID = 't00034';
% expID = 't00086';
% expID = 't00087';
% expID=  't00093';
% expID=  't00094';
% expID=  't00064';
% expID=  't00060';
% expID=  't00059';
% expID = 't00129';
% expID = 't00130';
% expID = 't00114';
% expID = 't00115';
% expID = 't00113';
% expID = 't00112';


% %expID = 't00032';
% %expID = 't00115';
% tsID = 'shrewby';
% expID = 't00006';
% expID = 't00021';
% 
% tsID = 'Amidala';
% %expID = 't00072';
% %expID = 't00071'
% %expID = 't00083';
%  %expID = 't00060';
%  %expID = 't00059';
% expID = 't00082';


% 
% tsID = 'Splinter';
% expID = 't00026';

% tsID = 'Baby';
% %expID = 't00041';
% expID = 't00061';
% expID = 't00066';

% tsID = 'TsMax171866'
% expID = 't00004'

%  tsID = 'tsm181922'
%  expID = 't00001'
%  expID = 't00002' 
%   expID = 't00003'
%   expID = 't00004'
%   expID = 't00005'

% tsID = 'qbert';
% expID = 't00027';
% expID = 't00028';
% expID = 't00005';
% expID = 't00006';
% expID = 't00054';
% expID = 't00053';
% 
tsID = 'Splinter';
expID = 't00025';

% tsID = 'Vida';
% expID = 't00056 ';

tsID = 'Baby';
expID = 't00086';

tsID = 'Chewie';
expID = 't00065';

tsID = 'blue';
expID = 't00007';
expID = 't00001';
expID = 't00012';
expID = 't00015';

tsID = 'amidala'
expID = 't00078';
expID = 't00071';

%stimDir = ['C:\Users\SchumacherJ\Documents\Data\' tsID '\' expID];
%stimDir = ['E:\Animal\' tsID '\' expID];
stimDir = ['C:\Data\Animal\' tsID '\' expID];
%stimDir = ['G:\' tsID '\' expID];
%dataDir = ['C:\Users\SchumacherJ\Documents\Data\' tsID '\03'];
%stimDir = ['G:\AchProject\' tsID '\' expID];
downSample=1;
%%Parameters
dendrite = 1; % first dendrite
spine = 2; % first spine
 
%% Load Stimulus Data

cd(stimDir)
twophotontimes = load('twophotontimes.txt');
frametrigger = load('frametrigger.txt');
S = load('stimontimes.txt');
stimOn = S(2:2:length(S));
stimID = S(1:2:length(S)-1);  

if ~isempty(stimID)
if stimID(1)==0 
    stimOn(1) = [];
    stimID(1) = [];
end;

 

f1 = fopen('stimtimes.txt', 'r');
ST = fscanf(f1, '%f');
end
uniqStims = unique(stimID);
disp(['Loaded ', num2str(length(uniqStims)), ' unique stimCodes.'])
disp(['Loaded ', num2str(length(stimOn)), ' stim on times'])


%preVisStim = find( twophotontimes < stimOn(1));
%twophotontimes(min(preVisStim):max(preVisStim)) = [];
cells(1).twophotontimes = twophotontimes;
cells(1).copyStimID = stimID;
cells(1).copyStimOn = stimOn;
cells(1).uniqStims = uniqStims;
% cells(1).randStimID = randStimID;
 
%[cells] = getInfo(loc,cells)
%%
%%Get MIJ, get ROI manager
import ij.*;
import ij.IJ.*;
RM = ij.plugin.frame.RoiManager();
RC = RM.getInstance();
count = RC.getCount();
for i = 1:count 
    disp(i);
RC.select(i-1)
cells(i).loc = char(RC.getName(i-1));
currentROI = MIJ.getRoi(i-1);
MIJ.run('Plot Z-axis Profile');
MIJ.run('Close','');
RT = MIJ.getResultsTable;
MIJ.run('Clear Results');
if size(RT,2)>1
cells(i).y = RT(:,2);
end 
cells(i).baseline = mean(cells(i).y);
%cells(i).y = conv(cells(i).y,gaussFilter,'same');
%cells(i).y = conv(cells(i).y,gaussFilter,'same');
cells(i).DF = (cells(i).y - cells(i).baseline)/cells(i).baseline;
cells(i).scanPeriod = mean(diff(twophotontimes(3:11)));
cells(i).rate = 1/cells(i).scanPeriod;
cells(i).scans = 1:length(cells(i).y);
cells(i).scanTimes = cells(i).scans*cells(i).scanPeriod;
cells(i).scanTimes = cells(i).scanTimes + min(twophotontimes);
clear CurrentROI
end;

%cells.tsID = tsID;
%cells.expID = expID;
%savename = [tsID '_' expID];
mySave(cells,'cellData')

