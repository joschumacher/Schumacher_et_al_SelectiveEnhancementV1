function singleConditionMaps = extractEpifluorescenceResponsesRevised5c(tifStack,stimConditionLabel,stimConditionOnsetTime,meanCCDTime)
% singleConditionMaps = extractEpifluorescenceResponsesRevised5c(tifStack,stimConditionLabel,stimConditionOnsetTime,meanCCDTime);
% 
% ANALYZES BLOCK_WISE ORIENTATION/DIRECTION, BLOCKWISE ON/OFF, AND RESTING STATE DATA (NO TEMPORALLY ENCODED MAPS, OD MAPS, OR SPATIAL FREQUENCY).
%
% Inputs:
% tifStack: (XxYxT) 3-d array of *.TIFs
% stimConditionLabel: stimulus labels for each presented trial
% stimConditionOnsetTime: stimulus time (in seconds) for each presented trial
% meanCCDTime: how long each frame last (in seconds).
%
% Output: 
% singleConditionMaps: (XxYxMxN) 4-d array, where X and Y dimensions are the image dimensions,
%                                           M denotes stimulus condition, and N denotes the trial.
%
% by David E. Whitney, Max Planck Florida Institute.
% Last update: 7/25/2016

% Checks if number of stimuli is correct (ie. too many conditions accidentally acquired)
if(~isempty(stimConditionLabel))
    numberOfExtraConditions = mod(sum(stimConditionLabel>0),max(stimConditionLabel));
    stimConditionLabel             =             stimConditionLabel(1:(length(stimConditionLabel)            -numberOfExtraConditions));
    stimConditionOnsetTime         =         stimConditionOnsetTime(1:(length(stimConditionOnsetTime)        -numberOfExtraConditions));
end

%% Stimulus Parameters
frameRate       = 1/meanCCDTime;         % Frame Rate of Camera (was fixed at 1/66E-3)
spatialBinning  = 4;                     % Spatial Binning (Typically 4)
pixelsPerMM     = 688/spatialBinning;    % Pixels per mm --> For spatial binning of 4, this value is ~153 (or 6.4micron per pixel spatial resolution)
stimConditionOnsetTimeInFrames = ceil(stimConditionOnsetTime*frameRate); % use this one. not the one in the MAT file

%% CORE SCRIPT PARAMETERS
isJustOrientation            = true;         % Ignores direction and computes orientation with all conditions
portionOfResponse            = 1;             % 0- Consider entire duration, 1-only during stimulation trials, % 2-Consider only during stimulus duration, 3-Consider anything outside stimulus period (non-stimulus), % 4,5,6 - variants of 1,2,3 but only considers the initial part of the desired period *****WARNING***** Due not use 1 or 4 for ON/OFF. Use either 2 or 5.
    durationToCheckInSeconds = 2;             % Used if selectedResponses=4,5,6. Specifies the partial duration to check after onset/offset.
    stimulusPeriodDetection  = 'Manual';   % 'Automatic' = Specifies that the stimulus period is half the entire trial period, 'Manual' - Uses Specified Values By the User
        stimulusDurationInSeconds = 2;        % 'Manual' - Uses this value if the automatic stimulus detection is not used (typically 5 or 15s)
createProbabilityMaps      = false;                 % Will generate probability maps, instead of differential maps  
useFirstFrameSubtraction   = true;                  % Will use the pre-stimulus trial frames to compute a baseline. Else will use the minimum intensity value for each pixel as the baseline.
    preStimDurationToUse   = 0.5;                   % Duration of time of the pre-stim period (in seconds)
selectedTrials             = [0];                  % -1 sums all available trials, 0- takes average of all trials (collapses all trials into one), any other number just selects a specific trials
loopedTrials               = false;                 % instead of summing responses above, loops through each selected trial
    trialDimensions        = 'Automatic';           % automatic - use preset dimensions, manual - uses dimensions specfied by trialPlotDimensions
    trialPlotDimensions    = [1 2];                 % Denotes the subplot ordering (x by y). the product of these numbers must be >= to length(selectedTrials)
blankType                  = 0;                     % Image Blank:    0 - No blank,           1 - Blank condition,     
                                                    %                 2 - Cocktail blank,     3 - difference images
spatialFilterMethod        = 0;                     % Spatial Filter: 0 - No Spatial Filter,  1 - Subtract Image Mean, 
                                                    %                 2 - 2d-bandpass filter, 3 - 2d-bandpass filter (Sets response below 0 to 0)
filterCutOffs              = [-1 1600];             % Lowpass and Highpass cutoffs for 2d bandpass filter (in microns)

%% ADVANCED SCRIPT PARAMETERS
directionsReversed           = false;         % Shifts direction responses by 180Deg (Moving Up becomes Moving Down) or Switches On/Off
correlateTrialImages         = false;         % Computes the trial-to-trial correlation of functional maps (use only if loopedTrials = true)
    correlationType = 'acrossConditions';     % Either computes correlations across all conditions ('acrossConditions'), or only within same stimulus condition ('onlyWithinCondition')
useFixedRange                = true;              % if set to true, uses FixedRange for images (else images are auto-scaled to their maximum)
    fixedClippingType        = 'stdDev';          % 'fixed' - fixed clipping based on a threshold, 'stdDev' - clipping based around: abs(mean)+/-clippingValue*std
        fixedRange           = 0.075/2;              % 0.2 is 20% DeltaF (used for 'fixed');
            if(createProbabilityMaps), fixedRange = 0.5; fixedClippingType = 'fixed'; end
        clippingValue        = 4;                 % Number of standard deviations around mean to clip (used for 'stdDev')
showPolarMap                 = true;              % Display Polar Maps for Orientation/Direction Preference
showColorbar                 = true;         % Shows Color bar
if(selectedTrials == -1), selectedTrials  = 1:sum(stimConditionLabel==1); end
if(createProbabilityMaps), loopedTrials = false; showTrialsTogether = false; end    
showTrialsTogether         = loopedTrials;      % Shows trial images together
showMaps                   = true;
useIntrinsic               = true;  
    
%% Make functional maps using either:
% 0.) all frames, 1.) the entire presentation of visual stimulus duration,
% 2.) during the stimulus duration, and 3.) the post-stimulus duration. It's
% also possible to only use a portion of the responses in 1-3. These are
% 4-6, and the portion of response checked is durationToCheck.
singleConditionMaps = [];
trialLength = min(diff(stimConditionOnsetTimeInFrames(stimConditionLabel~=0))); % in frames
durationToCheck  = floor(frameRate*durationToCheckInSeconds) ;  % Now in frames
switch stimulusPeriodDetection
    case 'Manual'
        stimulusDuration = floor(frameRate*stimulusDurationInSeconds);  % Now in frames
    case 'Automatic'
        stimulusDuration = floor(trialLength/2);
end
selectedStimulusCycle = [];
switch portionOfResponse
    case 0 % Consider all frames (even outside stimulation cycle)
        selectedStimulusCycle = cat(2,1:size(tifStack,3));
    case 1 % Consider only frames within the trial period
        for(ii = 1:length(stimConditionOnsetTimeInFrames))
            selectedStimulusCycle = cat(2,selectedStimulusCycle,...
                                          stimConditionOnsetTimeInFrames(ii):(stimConditionOnsetTimeInFrames(ii)+stimulusDuration-1));
            selectedStimulusCycle = cat(2,selectedStimulusCycle,...
                                          (stimConditionOnsetTimeInFrames(ii)+stimulusDuration):(stimConditionOnsetTimeInFrames(ii)+trialLength-1));                          
        end
    case 2 % Consider only during stimulus duration
        for(ii = 1:length(stimConditionOnsetTimeInFrames))
            selectedStimulusCycle = cat(2,selectedStimulusCycle,...
                                          stimConditionOnsetTimeInFrames(ii):(stimConditionOnsetTimeInFrames(ii)+stimulusDuration-1));
        end
    case 3 % Consider anything outside stimulus period (non-stimulus)
        %trialLength = mean(diff(stimConditionOnsetTimeInFrames));
        for(ii = 1:length(stimConditionOnsetTimeInFrames))
            selectedStimulusCycle = cat(2,selectedStimulusCycle,...
                                          (stimConditionOnsetTimeInFrames(ii)+stimulusDuration):(stimConditionOnsetTimeInFrames(ii)+trialLength-1));
        end
    case 4 % Same as 1, except only considers selected duration to check (both onset and offset)
        for(ii = 1:length(stimConditionOnsetTimeInFrames))
            selectedStimulusCycle = cat(2,selectedStimulusCycle,...
                                          stimConditionOnsetTimeInFrames(ii):(stimConditionOnsetTimeInFrames(ii)+durationToCheck-1));
            selectedStimulusCycle = cat(2,selectedStimulusCycle,...
                                          (stimConditionOnsetTimeInFrames(ii)+stimulusDuration):(stimConditionOnsetTimeInFrames(ii)+stimulusDuration+durationToCheck-1));                          
        end
    case 5 % Same as 2, except only considers selected duration to check
        for(ii = 1:length(stimConditionOnsetTimeInFrames))
            selectedStimulusCycle = cat(2,selectedStimulusCycle,...
                                          stimConditionOnsetTimeInFrames(ii):(stimConditionOnsetTimeInFrames(ii)+durationToCheck-1));
        end
    case 6 % Same as 3, except only considers selected duration to check
        for(ii = 1:length(stimConditionOnsetTimeInFrames))
            selectedStimulusCycle = cat(2,selectedStimulusCycle,...
                                          (stimConditionOnsetTimeInFrames(ii)+stimulusDuration):(stimConditionOnsetTimeInFrames(ii)+stimulusDuration+durationToCheck-1));
        end        
end

% Compute Baseline for Fluorescence Changes
referencedBaseline = 1;
switch referencedBaseline 
    case 0 % no baseline
        baselineImage     = zeros([size(calciumEvents,1) size(calciumEvents,2)]);
    case 1 % use lowest intensity image in .tif stack
        baselineImage     = min(tifStack,[],3);
        baselineImageBase = baselineImage;
end
baselineImage     = double(baselineImage);
baselineImageBase = double(baselineImageBase);

% Estimate Functional Maps (Capable of OR/Dir Maps and ON/OFF)
if(loopedTrials) 
    numberOfLoops = length(selectedTrials); 
else
    numberOfLoops = 1; 
end
if(strcmp(trialDimensions,'Automatic'))
    trialPlotDimensions = [ceil(numberOfLoops/5) ceil(numberOfLoops/ceil(numberOfLoops/5))];
end
for(currentLoop = 1:numberOfLoops)           
    if(loopedTrials)
        currentSelectedTrial = selectedTrials(currentLoop);
    else
        currentSelectedTrial = selectedTrials;
    end

    % Determine frames to assemble single-condition maps
    trialLength = min(diff(stimConditionOnsetTimeInFrames(stimConditionLabel~=0)));
    selectedFrames = []; 
    numberOfConditions = max(stimConditionLabel);
    isOrientationData = (numberOfConditions > 1); %implies orientation/direction preference
    for(currentSingleCondition = 1:numberOfConditions)
        selectedFrames{currentSingleCondition}.trialframes      = [];
        selectedFrames{currentSingleCondition}.trialStartFrames = [];
        trialLabels = find(stimConditionLabel == currentSingleCondition);
        if(min(currentSelectedTrial) > 0)
            trialLabels = trialLabels(currentSelectedTrial);
        end

        for(ii = trialLabels)
            putativeTrialFrames = stimConditionOnsetTimeInFrames(ii):(stimConditionOnsetTimeInFrames(ii)+floor(trialLength/(2-isOrientationData))-1); %floor(trialLength/(2-isOrientationData))
            framesPresentInSelectedStimulusCycle = max(repmat(putativeTrialFrames',[1 length(selectedStimulusCycle)])==repmat(selectedStimulusCycle,[length(putativeTrialFrames) 1]),[],2);
            putativeTrialFrames = putativeTrialFrames(framesPresentInSelectedStimulusCycle);

            selectedFrames{currentSingleCondition}.trialframes      = cat(2,selectedFrames{currentSingleCondition}.trialframes     ,putativeTrialFrames);
            selectedFrames{currentSingleCondition}.trialStartFrames = cat(2,selectedFrames{currentSingleCondition}.trialStartFrames,putativeTrialFrames(1));
        end
    end

    if(isOrientationData)
        singleConditionDirectionMap = generateSingleConditionMap(tifStack,baselineImage,baselineImageBase,selectedFrames,...
                                                                 'Direction',blankType,useFirstFrameSubtraction,createProbabilityMaps,...
                                                                 frameRate,preStimDurationToUse,spatialFilterMethod,filterCutOffs,pixelsPerMM,false,trialLength);
        if(~isJustOrientation)
            singleConditionOrientationMap = generateSingleConditionMap(tifStack,baselineImage,baselineImageBase,selectedFrames,...
                                                                       'Orientation',blankType,useFirstFrameSubtraction,createProbabilityMaps,...
                                                                       frameRate,preStimDurationToUse,spatialFilterMethod,filterCutOffs,pixelsPerMM,false,trialLength);
        else % because there are no directional stims, the  logic of a direction map is actually what we want for orientation when "isJustOrientation" flag is set to true
            singleConditionOrientationMap = singleConditionDirectionMap;
        end

        % Assign Phase to Stim IDs and construct orientation and direction preference maps
        numberOfFunctionalConditions = size(singleConditionOrientationMap,3);
        if(~isJustOrientation)
            stimDirection  = [0:360/numberOfFunctionalConditions:359]; 
            if(directionsReversed)
                halfwayPoint   = numberOfFunctionalConditions/2;
                singleConditionDirectionMap = singleConditionDirectionMap(:,:,[(halfwayPoint+1):numberOfFunctionalConditions 1:halfwayPoint]); 
            end
            orientationMap = vectorSum(singleConditionOrientationMap,2);
            directionMap   = vectorSum(singleConditionDirectionMap,1);
            selectedMapsToShow    = 1:2; %1:2 % signifies to show orientation/direction maps
            currentFunctionalMaps = singleConditionDirectionMap;
        else            
            stimDirection  = [0:180/numberOfFunctionalConditions:179]; 
            orientationMap = vectorSum(singleConditionOrientationMap,1);
            selectedMapsToShow = 1; % signifies to show orientation maps
            currentFunctionalMaps = singleConditionOrientationMap;
        end
    else % assume is ON/OFF maps
        % Construct single-condition map and apply a blank
        singleConditionOnOffMap = generateSingleConditionMap(tifStack,baselineImage,baselineImageBase,selectedFrames,...
                                                             'ONandOFF',blankType,useFirstFrameSubtraction,createProbabilityMaps,...
                                                             frameRate,preStimDurationToUse,spatialFilterMethod,filterCutOffs,pixelsPerMM,false,trialLength);

        if(directionsReversed)
            singleConditionOnOffMap = singleConditionOnOffMap(:,:,[2 1]);
        end
        selectedMapsToShow = 3; % signifies to show on/off maps
        currentFunctionalMaps = singleConditionOnOffMap;
    end

    % Display Functional Maps
    for(currentFunctionalMap = selectedMapsToShow)
        switch currentFunctionalMap
            case 1 % Orientation Preference Map
                if(~isJustOrientation)
                    numberOfSingleConditions = numberOfFunctionalConditions/2;
                else
                    numberOfSingleConditions = numberOfFunctionalConditions;
                end
                plotLabels = {};
                for(currentCondition = 1:numberOfSingleConditions)
                    plotLabels = cat(1,plotLabels,[num2str(stimDirection(currentCondition)) '\circ Single-Condition Map']);
                end
                plotLabels = cat(1,plotLabels,'Orientation Preference Map');
                if(numberOfSingleConditions == 4 && ~isJustOrientation)
                    if(showPolarMap),   currentSubplotLocation = [6 8 4 2 5];         plotSize = [3 3];
                    else                currentSubplotLocation = [1:4];               plotSize = [1 4];
                    end
                else
                    if(showPolarMap),   currentSubplotLocation = [1:(numberOfSingleConditions+1)]; plotSize = [4 ceil((1+numberOfSingleConditions)/4)];
                    else                currentSubplotLocation = [1:numberOfSingleConditions];     plotSize = [4 ceil(    numberOfSingleConditions/4)];
                    end
                end
            case 2 % Direction Preference Map
                numberOfSingleConditions = numberOfFunctionalConditions;
                plotLabels = {};
                for(currentCondition = 1:numberOfSingleConditions)
                    plotLabels = cat(1,plotLabels,[num2str(stimDirection(currentCondition)) '\circ Single-Condition Map']);
                end
                plotLabels = cat(1,plotLabels,'Direction Preference Map');
                if(numberOfSingleConditions == 8)
                    if(showPolarMap),   currentSubplotLocation = [2 3 6 9 8 7 4 1 5]; plotSize = [3 3];
                    else                currentSubplotLocation = [1:8];               plotSize = [2 4];
                    end
                else
                    if(showPolarMap),   currentSubplotLocation = [1:(numberOfSingleConditions+1)]; plotSize = [4 ceil((1+numberOfSingleConditions)/4)];
                    else                currentSubplotLocation = [1:numberOfSingleConditions];     plotSize = [4 ceil(    numberOfSingleConditions/4)];
                    end
                end
            case 3 % On/Off Map
                numberOfSingleConditions = 2;
                plotLabels = {'On Map' 'Off Map','Difference Map','Red-Green Overlay'}; 
                if(showPolarMap),   currentSubplotLocation = [1:4];    plotSize = [2 2];
                else                currentSubplotLocation = [1:2];    plotSize = [1 2];
                end
                if(showPolarMap), showPolarMap = 2; end % needs to be incremented so the difference map and red green overlay are shown together
        end

        % Loops through each functional map
        numberOfMaps = (numberOfSingleConditions+showPolarMap);
        for(currentMap = 1:numberOfMaps)
            % Specifies where to plot current functional map (and creates new Figures on Loop 1)
            if(loopedTrials && showTrialsTogether)  
                if(currentLoop == 1), handles(currentMap+(currentFunctionalMap-1)*numberOfMaps)  = figure();  end
                figure(handles((currentFunctionalMap-1)*numberOfMaps+currentMap));   
                subplot(trialPlotDimensions(1),trialPlotDimensions(2),currentLoop); 
            else
                if(currentMap == 1),  handles(currentLoop+(currentFunctionalMap-1)*numberOfLoops) = figure(); end
                figure(handles(currentLoop+(currentFunctionalMap-1)*numberOfLoops)); 
                subplot(plotSize(1),plotSize(2),currentSubplotLocation(currentMap));
            end

            % Show Single Condition Maps (and Polar Maps)
            isPolarMap = currentMap > numberOfSingleConditions;     % specifes whether polar map should be plotted
            if(showPolarMap && isPolarMap)
                switch currentFunctionalMap
                    case 1 % Orientation Preference Map
                        if(useFixedRange && strcmp(fixedClippingType,'fixed')),      
                            imagesc_fs(polarMap(orientationMap,hsv,[0 2*fixedRange]));
                        else
                            imagesc_fs(polarMap(orientationMap,hsv,clippingValue));
                        end
                        if(showTrialsTogether), title(['Polar Map / Trial ' num2str(currentSelectedTrial)]); end
                    case 2 % Direction Preference Map
                        if(useFixedRange && strcmp(fixedClippingType,'fixed')),      
                            imagesc_fs(polarMap(directionMap,hsv,[0 2*fixedRange]));
                        else
                            imagesc_fs(polarMap(directionMap,hsv,clippingValue));
                        end
                        if(showTrialsTogether), title(['Polar Map / Trial ' num2str(currentSelectedTrial)]); end
                    case 3 % ON/OFF
                        if(currentMap ==  numberOfMaps)
                            RGMap = zeros(size(singleConditionOnOffMap,1),size(singleConditionOnOffMap,2),3);
                            RGMap(:,:,1:2) = singleConditionOnOffMap(:,:,1:2);
                            if(useFixedRange && strcmp(fixedClippingType,'fixed')),
                                RGMap = RGMap./(2*fixedRange);
                            else
                                RGMap = RGMap./(abs(mean(RGMap(:)))+clippingValue*std(RGMap(:)));
                            end
                            RGMap(RGMap<0) = 0;
                            RGMap(RGMap>1) = 1;
                            imagesc_fs(RGMap);
                            if(showTrialsTogether), title(['RG Map / Trial ' num2str(currentSelectedTrial)]); end
                        else                                
                            imageToShow = singleConditionOnOffMap(:,:,1)-singleConditionOnOffMap(:,:,2);
                            imagesc_fs(imageToShow);

                            % Clipping Parameters
                            if(useFixedRange),
                                switch fixedClippingType
                                    case 'fixed' % fixed clipping based on a threshold
                                        caxis([-fixedRange fixedRange]); 
                                    case 'stdDev'
                                        clippingThreshold = abs(mean2(imageToShow))+clippingValue*std2(imageToShow);
                                        caxis([-clippingThreshold clippingThreshold]); 
                                end
                            end
                            if(showTrialsTogether), title(['ON/OFF Map / Trial ' num2str(currentSelectedTrial)]); end

                        end
                end
            else
                % Show Single Condition Maps
                switch currentFunctionalMap
                    case 1 % Orientation Single Condition Map
                        imageToShow = singleConditionOrientationMap(:,:,currentMap);
                    case 2 % Direction Single Condition Map
                        imageToShow = singleConditionDirectionMap(:,:,currentMap);
                    case 3 % On/Off Map
                        imageToShow = singleConditionOnOffMap(:,:,currentMap);
                end
                imagesc_fs(imageToShow);

                % Clipping Parameters
                if(useFixedRange),
                    switch fixedClippingType
                        case 'fixed' % fixed clipping based on a threshold
                            if(    blankType<2 ), caxis([0 2*fixedRange]); 
                            elseif(blankType>=2), caxis([-fixedRange fixedRange]); 
                            end
                        case 'stdDev'
                            clippingThreshold = abs(mean2(imageToShow))+clippingValue*std2(imageToShow);
                            if(    blankType<2 && spatialFilterMethod < 2), caxis([0 clippingThreshold]); 
                            elseif(blankType>=2 || spatialFilterMethod >= 2), caxis([-clippingThreshold clippingThreshold]); 
                            end
                    end
                end
            end
            colormap(gray); axis image; axis off; if(showColorbar), colorbar; end
            currentLabel = plotLabels{currentMap};
            if(showTrialsTogether), currentLabel = [currentLabel ' / Trial ' num2str(currentSelectedTrial)]; end
            title(currentLabel);
        end
    end
    
    % Save functional maps
    singleConditionMaps = cat(4,singleConditionMaps,currentFunctionalMaps);
end
for(ii=1:length(handles)), if(handles(ii)>0), tightfig(handles(ii)); end, end % make subplots tight

% Compute Trial-to-Trial Correlations of Functional Maps (Assesses Reliability)
if(correlateTrialImages)                     
    correlationData(:,:,currentLoop,:) = permute(singleConditionMaps,[1 2 4 3]);

    correlationFigureHandle = figure;
    correlationImgSize = size(correlationData);
    switch correlationType
        case 'acrossConditions'
            correlationData   = reshape(correlationData,[correlationImgSize(1) correlationImgSize(2) correlationImgSize(3)*correlationImgSize(4)]);
            correlationValues = computeCorrelations(correlationData,correlationData,false,false);
            meanGroupCorrelation = zeros(correlationImgSize(4));
            for(ii = 1:correlationImgSize(4))
                for(jj = 1:correlationImgSize(4))
                    currentTable = correlationValues((ii-1)*correlationImgSize(3)+[1:correlationImgSize(3)],...
                                                     (jj-1)*correlationImgSize(3)+[1:correlationImgSize(3)]);
                    meanCorrelation(ii,jj) = mean(currentTable(currentTable~=0 & abs(currentTable)~=1));
                end
            end

            figure(correlationFigureHandle);
            imagesc_fs(correlationValues); 
            axis image; caxis([-1 1]); colormap(rwb);
            set(gca,'FontSize',30); colorbar; hold on;
            set(gca,'LineWidth',3,...
                    'XTick',-0.5+[1:correlationImgSize(3):length(correlationValues)],'XTickLabel',[],...
                    'YTick',-0.5+[1:correlationImgSize(3):length(correlationValues)],'YTickLabel',[]);
                gridLength = length(correlationValues)+2;
                for(ii = 1:correlationImgSize(3):gridLength)
                    plot((1:gridLength)           -1.5,...
                         repmat(ii,[1 gridLength])-0.5,'k','LineWidth',3);
                    plot(repmat(ii,[1 gridLength])-0.5,...
                         (1:gridLength)           -1.5,'k','LineWidth',3);
                end
                for(ii = 1:gridLength)
                    plot((1:gridLength)           -1.5,...
                         repmat(ii,[1 gridLength])-1.5,'--k','LineWidth',1);
                    plot(repmat(ii,[1 gridLength])-1.5,...
                         (1:gridLength)           -1.5,'--k','LineWidth',1);
                end
            title('Trial-to-Trial Cross Correlation Table','FontSize',30);

            meanCorrelation
            drawnow
        case 'onlyWithinCondition'
            correlationValues = zeros(correlationImgSize(3),correlationImgSize(3),correlationImgSize(4));
            meanCorrelation   = zeros(correlationImgSize(4),1);
            for(currentCondition = 1:correlationImgSize(4))
                currentTable = computeCorrelations(correlationData(:,:,:,currentCondition),correlationData(:,:,:,currentCondition),false,false);
                correlationValues(:,:,currentCondition) = currentTable;
                meanCorrelation(currentCondition)       = mean(currentTable(currentTable~=0 & abs(currentTable)~=1));
            end
            correlationValues2 = reshape(correlationValues,[correlationImgSize(3) correlationImgSize(3)*correlationImgSize(4)]);

    end
end
return