  % Map parameters
baseDirectory  = 'G:\'; 
baseDirectory  = 'E:\Animal\';
baseDirectory = 'C:\Data\Animal\';
baseDirectory = 'F:\Animal\';
baseDirectory = 'Z:\Joe\Data\';
name           = 'TsMaxB1603';
name           = 'Baby';
name           = 'qbert';
name           = 'bruiser';
name = 'TSMax1502';
name = 'Vida';
name = 'TsMax1808';
name = 'Vida';
name = 'Leia';
name = 'Qbert';
exptNumber     = 46;
exptNumber = 6;
exptNumber = 36;
readHeaderOnly = false;

% Read imaging data
t0=tic;
if(readHeaderOnly)
    [~,stimConditionLabel,stimConditionOnsetTime,meanCCDTime] = readImagingData(baseDirectory,name,exptNumber,readHeaderOnly);
else
    [tifStack,stimConditionLabel,stimConditionOnsetTime,meanCCDTime] = readImagingData(baseDirectory,name,exptNumber,readHeaderOnly);
end
toc(t0)

% Image registration by aligning all images to first image.
addSubMicronInPlaneAlignment = false;
if(addSubMicronInPlaneAlignment)
    referenceImg = real(bandpassFermiFilter_Revised(tifStack(:,:,1),-1,600,1000/172));
    numberOfImages = size(tifStack,3);
    parfor(ii = 2:numberOfImages)
        tifStack(:,:,ii)=subMicronInPlaneAlignment(referenceImg,tifStack(:,:,ii),[-1 600 1000/172],true,true);
%         if(mod(ii,250)==0),
%             disp([num2str(100*ii/numberOfImages) '% Done - Time Elapsed is ' num2str(toc) 's - Estimated Time Left is ' num2str((numberOfImages-ii)*toc/ii) 's']); 
%         end
    end
end
%%
% Show functional maps
analysisType = 'blockwiseMaps';
switch analysisType
    case 'none'
        % do nothing
    case 'viewRAWStack' % view raw stack
        ViewImageStack_DEW(tifStack);
    case 'makeAVIs' % make a deltaF over F movie and view it
        saveDirectory = [cd];
        stimulusTimes = [0 2]; % Stimulus Period (Onset and Offset relative to stimulus trigger)
        if(isempty(meanCCDTime)), meanCCDTime = 1/15.0966; end %assumes frame rate is 15Hz if no triggers are present
        movieStack    = makeEpiMovie2(tifStack,1/meanCCDTime,stimulusTimes,stimConditionLabel,stimConditionOnsetTime,saveDirectory);
        
        % Show AVI
        ViewImageStack_DEW(movieStack);
    case 'blockwiseMaps' % compute blockwise maps for orientation, direction, and/or ON-OFF
        singleConditionMaps = extractEpifluorescenceResponsesRevised5d(tifStack,stimConditionLabel,stimConditionOnsetTime,meanCCDTime);
        figure; imagesc(polarMap(bandpassFermiFilter_Revised(vectorSum(singleConditionMaps,1),-1,-1,1000/172),hsv,3));
        figure; imagesc(polarMap(bandpassFermiFilter_Revised(vectorSum(singleConditionMaps,2),-1,-1,1000/172),hsv,3));
        
        %some temporary analysis for qbert block 46
        figure; subplot(2,1,1); imagesc(singleConditionMaps(:,:,13)); colormap('gray'); caxis([0 .3])
        subplot(2,1,2); imagesc(singleConditionMaps(:,:,31)); colormap('gray');caxis([0 .3])
        targetMap = zeros(size(singleConditionMaps));
        targetMap(:,:,13) = singleConditionMaps(:,:,13);
        
    
    case 'fourierMaps' % compute Fourier maps using the DFT
        isDirectionData = true;
        fourierMaps     = readFourierMaps2(tifStack,stimConditionOnsetTime,meanCCDTime,isDirectionData);
    case 'spontaneousActivityCorrelationPatterns'
        spontStructure = computeCorrelationPatterns(tifStack);
        
        % Show correlation patterns
        h=figure; 
        currentIndex = 5000;
        while(1)
            imagesc(real(reshape(spontStructure.rho(currentIndex,:),spontStructure.outSize))); 
            colormap(rwb); axis image; caxis([-1 1]);
            title(currentTitle);

            % get interactive point to compute different correlation patterns
            [x,y] = ginput(1);
            currentIndex = sub2ind(spontStructure.outSize,round(y),round(x));
        end
end

%% Load miscellaneous data
fileForTriggers = 'twophotontimes.txt';
% Load timing information of images and visual stimulus
baseStimDirectory = baseDirectory; %'C:\Data\';
if(exptNumber<10)
    currentDirectory = [baseStimDirectory name '\t0000' num2str(exptNumber) '\'];
else
    currentDirectory = [baseStimDirectory name '\t000' num2str(exptNumber) '\'];
end
 
% Read file with frame times (if present)
if(exist([currentDirectory fileForTriggers]) ~= 0)  %twophotontimes.txt
    CCD_FramesTimes  = load([currentDirectory fileForTriggers]); %twophotontimes.txt
    startTime        = CCD_FramesTimes(1);
    offsetFrameTimes = CCD_FramesTimes-startTime;
    meanCCDTime      = median(diff(offsetFrameTimes));
else
    startTime   = [];
    meanCCDTime = [];
end

% Read file with frame times for stimulus onset (and stimulus label)
stimConditionLabel     = [];
stimConditionOnsetTime = [];
if(exist([currentDirectory 'stimontimes.txt']) ~= 0)
    StimData = load([currentDirectory 'stimontimes.txt']);
    if(~isempty(StimData))
        if StimData(1)==0
            stimConditionLabel     = StimData(3:2:end);
            stimConditionOnsetTime = StimData(4:2:end);
        else
            stimConditionLabel     = StimData(1:2:end);
            stimConditionOnsetTime = StimData(2:2:end);
        end
        stimConditionOnsetTime = stimConditionOnsetTime-startTime;
    end
end
%%
figure; imagesc(polarMap(bandpassFermiFilter_Revised(vectorSum(singleConditionMaps,1),-1,-1,1000/172),hsv,3));
figure; imagesc(polarMap(bandpassFermiFilter_Revised(vectorSum(singleConditionMaps,2),-1,-1,1000/172),hsv,3));
%%
%some temporary analysis for qbert block 46
figure; subplot(2,1,1); imagesc(singleConditionMaps(:,:,13)); colormap('gray'); caxis([0 .3])
subplot(2,1,2); imagesc(singleConditionMaps(:,:,31)); colormap('gray');caxis([0 .3])
targetMap = zeros(size(singleConditionMaps));
distractorMap1 = targetMap;
distractorMap2 = targetMap;
targetMap(:,:,13) = singleConditionMaps(:,:,13);
distractorMap1(:,:,18) = singleConditionMaps(:,:,21);
distractorMap2(:,:,31) = singleConditionMaps(:,:,31);
% targetMap(find(targetMap<0)) = 0;
% distractorMap1(find(distractorMap1<0))=0;
% distractorMap2(find(distractorMap2<0))=0;

figure; imagesc(polarMap(bandpassFermiFilter_Revised(vectorSum(targetMap,1),-1,-1,1000/172),hsv,3));
figure; imagesc(polarMap(bandpassFermiFilter_Revised(vectorSum(distractorMap1,1),-1,-1,1000/172),hsv,3));
figure; imagesc(polarMap(bandpassFermiFilter_Revised(vectorSum(distractorMap2,1),-1,-1,1000/172),hsv,3));
%%
figure
subplot(1,2,1)
H = fspecial('gaussian',[5 5]);
MapSmooth = filter2(H,singleConditionMaps(:,:,13));
imshow(MapSmooth)
subplot(1,2,2)
imshow(singleConditionMaps(:,:,13))